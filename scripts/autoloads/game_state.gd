extends Node

signal floor_changed(new_floor: int)
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_exp_changed(exp: int, exp_needed: int, level: int)
signal player_leveled_up(level: int)
signal player_died()
signal player_won()
signal combat_message(msg: String)
signal inventory_changed()
signal equipment_changed()
signal inventory_toggle()
signal player_action_requested(action_name: String)
signal player_throw_primed(item: Item)
signal player_tool_primed(item: Item)
signal class_chosen(chosen_class: Stats.CharacterClass)
signal hunger_changed(value: int)
signal player_status_changed()
signal debug_jump_floor(floor_num: int)
signal short_rest_changed
signal stairs_discovered
signal short_rest_completed
signal short_rest_aborted
signal camera_recenter_requested
signal debug_reveal_all
signal debug_see_all(active: bool)
signal crit_banner(text: String, color: Color)
signal screen_shake(strength: float)
signal potion_drunk
signal ability_bar_changed()
# Emitted when equip/unequip is done intentionally (costs 1 turn). Not emitted on auto-pickup.
signal equip_action_taken()
signal talent_invested(talent_id: String, new_rank: int)
signal talent_points_changed(available: int)

const QUICKBAR_SIZE: int = 9
const ABILITY_BAR_SIZE: int = 9
const INVENTORY_SIZE: int = 24

# Wild Heart Tier 2 companion stats by rank (data-driven, no hardcoded logic)
const WILD_HEART_COMPANION_STATS: Dictionary = {
	1: {"animal": "Squirrel", "ac": 12, "hp": 10, "die_count": 1, "die_sides": 6},
	2: {"animal": "Boar",     "ac": 14, "hp": 20, "die_count": 2, "die_sides": 6},
	3: {"animal": "Bear",     "ac": 16, "hp": 30, "die_count": 3, "die_sides": 6},
}

# talent_id → icons/barbarian/<folder>_<rank>.png stem. Rank-specific art (1-3), see icons/barbarian/CLAUDE.md.
const TALENT_ICON_FOLDER: Dictionary = {
	"rage": "base/primal_fury",
	"reckless_attack": "base/reckless_attack",
	"danger_sense": "base/feral_instinct",
	"rager": "berserker/unchained_momentum",
	"frenzy": "berserker/crimson_cleaver",
	"retaliation": "berserker/vengeful_reflex",
	"one_with_nature": "wild_heart/primal_bond",
	"natural_rager": "wild_heart/aspect_of_the_wild",
	"natural_sleeper": "wild_heart/dreamwalker_instinct",
	"ironwood_bark": "world_tree/ironwood_bark",
	"grip_of_the_forest": "world_tree/grip_of_the_forest",
	"branching_strike": "world_tree/branching_strike",
	"divine_fury": "zealot/divine_fury",
	"blessed_warrior": "zealot/blessed_warrior",
	"zealous_presence": "zealot/zealous_presence",
}

## Returns the rank-specific icon for a talent/ability (rank clamped to 1-3); "" if unmapped.
func talent_icon_path(id: String, rank: int) -> String:
	if not TALENT_ICON_FOLDER.has(id):
		return ""
	var r: int = clampi(rank, 1, 3)
	return "res://icons/barbarian/%s_%d.png" % [TALENT_ICON_FOLDER[id], r]

enum HungerState { SATIATED, HUNGRY, STARVING }
const MAX_HUNGER: int = 1000

const STARVE_INTERVAL: int = 10
var _starvation_tick: int = 0

var current_floor: int = 1
var player_stats: Stats
var run_seed: int = 0
var is_game_over: bool = false
var inventory_open: bool = false
var class_selected: bool = false
var invincible: bool = false
var noclip: bool = false
var god_mode: bool = false
var hit_dice: int = 1
var short_rests_remaining: int = 2
var max_short_rests: int = 2
var short_rest_open: bool = false
var talent_picker_open: bool = false

# Talent system — points earned per level, invested per talent.
# Points are tier-locked: Tier 1 levels fill tier1_talent_points, Tier 2 levels fill tier2_talent_points.
# talent_points_available is a computed sum used for backward-compat (signals, auto-close logic).
var tier1_talent_points: int = 0
var tier2_talent_points: int = 0
var talent_points_available: int:
	get: return tier1_talent_points + tier2_talent_points
var talent_investments: Dictionary = {}   # talent_id → current_rank (int)
var _class_talents: Array[Talent] = []    # all talents for current class, populated on class select
# Tier 2 auto-unlocks at level 7 (no boss kill required).
var tier2_unlocked: bool = false
# Debug subclass cycling — only Berserker is fully implemented; others are placeholders.
const TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Zealot", "World Tree", "Wild Heart"]
var active_tier2_subclass: String = "Berserker"
var short_rest_active: bool = false
var short_rest_turns_remaining: int = 0
var short_rest_pending_heal: int = 0

# ── Wild Heart Tier 2 state ───────────────────────────────────────────────────
# Natural Rager: toggle between Bear/Eagle/Wolf; effects only apply while is_raging.
var natural_rager_form: String = "Bear"
# Natural Sleeper: toggle between Owl/Panther/Salmon; activates on floor entry (long rest).
# natural_sleeper_form = chosen form (preview); active_sleeper_form = locked in at last rest.
var natural_sleeper_form: String = ""   # "" = no form chosen; locks in at floor descent
var active_sleeper_form: String = ""    # locks in at short rest or floor descent
var wild_heart_sleeper_active: bool = false
# Eagle R3: no-op pending future Opportunity Attack system — do NOT remove this flag.
var player_evades_opportunity_attacks: bool = false
# Reference to living companion node (null when no companion). Set by player.gd.
var player_companion: Variant = null
# AC bonus from Natural Sleeper R3 terrain — added in recalculate_stats().
var terrain_ac_bonus: int = 0

# ── Zealot Tier 2 state ────────────────────────────────────────────────────
# Divine Fury: toggle-only damage type selector, persists between turns (does NOT reset per turn).
var zealot_divine_fury_type: String = "Radiant"
# Blessed Warrior: long-rest-recharged charge pool. Max scales with rank (see BLESSED_WARRIOR_MAX_CHARGES).
var zealot_blessed_charges: int = 0
# Set true when the player activates Blessed Warrior; consumed by the next successful hit this turn
# (hit only — a miss still spends the activation with no heal). Reset per-turn cap lives in player.gd.
var zealot_blessed_heal_queued: bool = false
const BLESSED_WARRIOR_MAX_CHARGES: Array = [0, 2, 4, 6]
# Zealous Presence: separate long-rest-recharged resource (1 charge/rest, independent of Rage's pool).
# Activation prefers this charge; falls back to consuming 1 Rage charge only when this is 0.
var zealot_zp_charges: int = 0
var player_grid_pos: Vector2i = Vector2i.ZERO
# Items whose ammo/projectile fell into a chasm mid-shot — reappear at a random walkable floor
# tile on the NEXT floor down, drained by DungeonFloor._spawn_pending_chasm_items() during
# _load_floor(). General-purpose (not arrow-specific) so any future "item falls into a chasm"
# mechanic can push onto this list.
var pending_chasm_items: Array[Item] = []
var current_stairs_pos: Vector2i = Vector2i.ZERO
var hunger: int = MAX_HUNGER
var hunger_state: HungerState:
	get:
		if hunger > 600: return HungerState.SATIATED
		if hunger > 200: return HungerState.HUNGRY
		return HungerState.STARVING

var player_quickbar: Array = []   # 9 item slots shown in HUD action bar
var player_ability_bar: Array = [] # 9 ability slots (Tab to switch)
var player_inventory: Array = []  # 24-slot bag

var equipment: Dictionary = {
	"melee": null, "hand2": null, "ranged": null, "armor": null,
	"boots": null, "gloves": null, "head": null, "trinket": null,
}

# Convenience read-only properties (backward compat with player.gd)
var equipped_weapon: Item:
	get: return equipment.get("melee") as Item

var equipped_ranged: Item:
	get: return equipment.get("ranged") as Item

var equipped_armor: Item:
	get: return equipment.get("armor") as Item

func _ready() -> void:
	start_new_run()
	short_rest_completed.connect(_on_short_rest_completed)

func start_new_run() -> void:
	run_seed = randi()
	current_floor = 1
	is_game_over = false
	inventory_open = false
	class_selected = false
	invincible = false
	noclip = false
	short_rest_open = false
	talent_picker_open = false
	tier1_talent_points = 0
	tier2_talent_points = 0
	talent_investments = {}
	_class_talents = []
	tier2_unlocked = false
	active_tier2_subclass = "Berserker"
	zealot_divine_fury_type = "Radiant"
	zealot_blessed_charges = 0
	zealot_blessed_heal_queued = false
	zealot_zp_charges = 0
	hit_dice = 1
	short_rests_remaining = 2
	max_short_rests = 2
	hunger = MAX_HUNGER
	_starvation_tick = 0
	player_stats = Stats.new()
	player_stats.apply_class_defaults()  # defaults until class select overrides
	player_quickbar.clear()
	for _i: int in QUICKBAR_SIZE:
		player_quickbar.append(null)
	player_ability_bar.clear()
	for _i: int in ABILITY_BAR_SIZE:
		player_ability_bar.append(null)
	player_inventory.clear()
	for _i: int in INVENTORY_SIZE:
		player_inventory.append(null)
	for key: String in equipment:
		equipment[key] = null
	natural_rager_form = "Bear"
	natural_sleeper_form = ""
	active_sleeper_form = ""
	wild_heart_sleeper_active = false
	player_evades_opportunity_attacks = false
	player_companion = null
	terrain_ac_bonus = 0
	_give_starting_items()

func _give_starting_items() -> void:
	var ration := Item.new()
	ration.item_name = "Ration"
	ration.item_type = Item.Type.FOOD
	ration.heal_amount = 200
	ration.icon_path = "res://sprites/items/Food/MeatCooked.png"
	ration.description = "Fills you up"
	ration.quantity = 3
	add_item(ration)

	var tools := Item.new()
	tools.item_name = "Thief Tools"
	tools.item_type = Item.Type.TOOL
	tools.icon_path = "res://sprites/items/Misc/KeyIron.png"
	tools.description = "Left-click to use, then click an adjacent revealed trap to disarm. Consumed on failure."
	tools.quantity = 3
	add_item(tools)

# Called by class_select.gd after player picks a class, replaces generic starting gear.
func give_class_starting_items() -> void:
	if equipment.get("melee") != null or player_ability_bar[0] != null:
		return
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN:
			_give_barbarian_starting_items()
			_setup_barbarian_talents()
		Stats.CharacterClass.MONK:
			_give_monk_starting_items()

func _give_barbarian_starting_items() -> void:
	var axe := Item.new()
	axe.item_name = "Greataxe"
	axe.item_type = Item.Type.WEAPON
	axe.icon_path = "res://sprites/weapons/weapon_double_axe.png"
	axe.description = ""
	axe.is_heavy = true
	axe.bonus_damage = 0      # proficiency adds to attack roll, not to damage
	axe.damage_die_min = 1    # weapon defines its own dice: 1d12
	axe.damage_die_max = 12
	axe.floor_min = 1
	axe.floor_max = 10
	axe.is_ranged = false
	axe.is_two_handed = true
	axe.damage_type = "Slashing"
	axe.weapon_mastery = "Cleave"
	axe.weapon_category = "Martial"
	# Equip silently (no turn cost, no turn consumed — startup)
	equipment["melee"] = axe
	recalculate_stats()
	equipment_changed.emit()

	# Rage ability in slot 0 of ability bar
	var rage := Ability.new()
	rage.ability_id = "rage"
	rage.ability_name = "Rage"
	rage.description = _build_rage_description()
	rage.icon_path = talent_icon_path("rage", maxi(get_talent_rank("rage"), 1))
	rage.uses_remaining = player_stats.rage_uses_remaining
	rage.uses_max = player_stats.rage_uses_max
	add_ability(rage)

func _give_monk_starting_items() -> void:
	# Monks start unarmed — fists are their weapons.
	# Unarmored Defense passive
	var ud := Ability.new()
	ud.ability_id = "unarmored_defense_monk"
	ud.ability_name = "Unarmored Defense"
	ud.description = "Passive: AC = 10 + DEX + WIS while wearing no armor."
	ud.icon_path = "res://sprites/items/Misc/KeyIron.png"
	ud.uses_remaining = 0
	ud.uses_max = 0
	ud.is_passive = true
	add_ability(ud)
	# Martial Arts passive — die scales with level (1d6 → 1d8 → 1d10 → 1d12)
	var ma := Ability.new()
	ma.ability_id = "martial_arts"
	ma.ability_name = "Martial Arts"
	ma.description = "Passive: Unarmed strikes use DEX + 1d6. After a main-action unarmed strike, make a free bonus-action unarmed strike. Die scales at levels 5/11/17."
	ma.icon_path = "res://sprites/items/Misc/KeyIron.png"
	ma.uses_remaining = 0
	ma.uses_max = 0
	ma.is_passive = true
	add_ability(ma)
	recalculate_stats()
	equipment_changed.emit()

func _find_ability_by_id(id: String) -> Ability:
	for slot in player_ability_bar:
		if slot != null and (slot as Ability).ability_id == id:
			return slot as Ability
	return null

func add_ability(ability: Ability) -> bool:
	if ability.is_passive:
		return false
	for i: int in ABILITY_BAR_SIZE:
		if player_ability_bar[i] == null:
			player_ability_bar[i] = ability
			ability_bar_changed.emit()
			return true
	game_log("[color=red]Ability bar is full![/color]")
	return false

func advance_floor() -> void:
	current_floor += 1
	# Floor descent = long rest: refill rage uses, hit dice, short rest slots
	player_stats.rage_uses_remaining = player_stats.rage_uses_max
	hit_dice = player_stats.character_level
	short_rests_remaining = 2
	max_short_rests = 2
	# Natural Sleeper activates on floor entry (long rest trigger).
	# active_sleeper_form locks in the chosen form for this floor.
	wild_heart_sleeper_active = get_talent_rank("natural_sleeper") >= 1
	active_sleeper_form = natural_sleeper_form
	terrain_ac_bonus = 0  # reset terrain AC; player.gd will reapply on next move
	# Zealot long-rest resources (independent pools — see CLAUDE.md "long-rest-recharged resource" pattern).
	var bw_rank: int = get_talent_rank("blessed_warrior")
	if bw_rank >= 1:
		zealot_blessed_charges = BLESSED_WARRIOR_MAX_CHARGES[bw_rank]
	if get_talent_rank("zealous_presence") >= 1:
		zealot_zp_charges = 1
	if wild_heart_sleeper_active:
		if active_sleeper_form != "":
			game_log("[color=cyan]Natural Sleeper: you wake — %s Form is active this floor.[/color]" % active_sleeper_form)
		else:
			game_log("[color=gray]Natural Sleeper: no form chosen — press the ability to select one.[/color]")
	# Companion: restore HP if alive; otherwise charge will be restored in _sync_ability_uses
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	_sync_ability_uses()
	short_rest_changed.emit()
	floor_changed.emit(current_floor)
	if current_floor > 10:
		player_won.emit()

# Keeps ability resource uses_remaining in sync with player_stats after a long rest.
func _sync_ability_uses() -> void:
	for slot in player_ability_bar:
		if slot == null:
			continue
		var ab := slot as Ability
		if ab.ability_id == "rage":
			ab.uses_remaining = player_stats.rage_uses_remaining
			ab.uses_max = player_stats.rage_uses_max
		elif ab.ability_id == "one_with_nature":
			ab.uses_remaining = 1  # always restore on long rest
	ability_bar_changed.emit()

# Triggered on short rest completion. Heals companion (if alive) AND restores One with Nature charge.
func _on_short_rest_completed() -> void:
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	var owtn: Ability = _find_ability_by_id("one_with_nature")
	if owtn != null:
		owtn.uses_remaining = 1
		ability_bar_changed.emit()
		game_log("[color=lime]One with Nature: companion charge refreshed.[/color]")
	# Natural Sleeper: short rest also locks in the chosen form (same as floor descent)
	if get_talent_rank("natural_sleeper") >= 1:
		wild_heart_sleeper_active = true
		if active_sleeper_form != natural_sleeper_form:
			active_sleeper_form = natural_sleeper_form
			if active_sleeper_form != "":
				game_log("[color=cyan]Natural Sleeper: %s Form is now active.[/color]" % active_sleeper_form)
			else:
				game_log("[color=gray]Natural Sleeper: no form chosen — press the ability to select one.[/color]")

func hit_die_sides() -> int:
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN: return 12
		Stats.CharacterClass.RANGER:    return 10
		Stats.CharacterClass.MONK:      return 8
		Stats.CharacterClass.WIZARD:    return 6
		_:                              return 8

func check_player_death() -> void:
	if player_stats.is_dead() and not is_game_over and not invincible:
		is_game_over = true
		AudioManager.play("player_die")
		player_died.emit()

func heal(amount: int) -> void:
	player_stats.current_hp = mini(player_stats.current_hp + amount, player_stats.max_hp)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)

func gain_exp(amount: int) -> void:
	var old_max_hp: int = player_stats.max_hp
	var old_rage_max: int = player_stats.rage_uses_max
	var leveled_up := player_stats.gain_exp(amount)
	player_exp_changed.emit(player_stats.experience, player_stats.exp_to_next(), player_stats.character_level)
	if leveled_up:
		player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
		var hp_gained: int = player_stats.max_hp - old_max_hp
		var lv: int = player_stats.character_level
		if lv >= 1 and lv <= 5:
			# Tier 1 points: immediately available (tier-locked to Tier 1 talents)
			tier1_talent_points += 1
			talent_points_changed.emit(talent_points_available)
		elif lv >= 7 and lv <= 12:
			# Tier 2 auto-unlocks on first Tier 2 level-up (level 7).
			if not tier2_unlocked:
				unlock_tier2()
			tier2_talent_points += 1
			talent_points_changed.emit(talent_points_available)
		# Level 6 and 13+: no talent points (gap between tiers)
		# Rage uses scale by level — grant the extra use immediately on the triggering level-up.
		if player_stats.character_class == Stats.CharacterClass.BARBARIAN:
			var new_rage_max: int = player_stats.rage_uses_max
			if new_rage_max > old_rage_max:
				player_stats.rage_uses_remaining = mini(
					player_stats.rage_uses_remaining + (new_rage_max - old_rage_max),
					new_rage_max)
				_sync_ability_uses()
		var lv_str: String = ""
		if (lv >= 1 and lv <= 5) or (lv >= 7 and lv <= 12):
			lv_str = " +1 talent point."
		var level_msg: String = "[color=yellow]Level up! You are now level %d. (+%d max HP.%s)[/color]" % [player_stats.character_level, hp_gained, lv_str]
		combat_message.emit(level_msg)
		short_rest_changed.emit()
		_apply_monk_level_features(player_stats.character_level)
		player_leveled_up.emit(player_stats.character_level)

func unlock_tier2() -> void:
	if tier2_unlocked:
		return
	tier2_unlocked = true
	_setup_tier2_for_active_subclass()
	game_log("[color=gold]%s Tier 2 talents unlocked![/color]" % active_tier2_subclass)

func _setup_tier2_for_active_subclass() -> void:
	match active_tier2_subclass:
		"Berserker": _setup_barbarian_tier2_talents()
		"Wild Heart": _setup_wild_heart_tier2_talents()
		"World Tree": _setup_world_tree_tier2_talents()
		"Zealot": _setup_zealot_tier2_talents()
		_: pass

func debug_switch_subclass(direction: int) -> void:
	var idx: int = TIER2_SUBCLASSES.find(active_tier2_subclass)
	if idx < 0:
		idx = 0
	idx = (idx + direction + TIER2_SUBCLASSES.size()) % TIER2_SUBCLASSES.size()
	active_tier2_subclass = TIER2_SUBCLASSES[idx]
	# Collect tier 2 talent IDs currently in _class_talents
	var tier2_ids: Array[String] = []
	for t: Talent in _class_talents:
		if t.tier == 2:
			tier2_ids.append(t.talent_id)
	# Clear tier 2 investments
	for id: String in tier2_ids:
		talent_investments.erase(id)
	# Clear tier 2 ability bar entries
	for i: int in player_ability_bar.size():
		var ab: Ability = player_ability_bar[i] as Ability
		if ab != null and ab.ability_id in tier2_ids:
			player_ability_bar[i] = null
	ability_bar_changed.emit()
	# Replace tier 2 talent entries
	var new_talents: Array[Talent] = []
	for t: Talent in _class_talents:
		if t.tier != 2:
			new_talents.append(t)
	_class_talents = new_talents
	# Setup talents for newly selected subclass
	_setup_tier2_for_active_subclass()
	game_log("[color=purple][DEBUG] Subclass → %s[/color]" % active_tier2_subclass)


func debug_level_up() -> void:
	gain_exp(player_stats.exp_to_next())
	player_stats.experience = 0
	player_exp_changed.emit(0, player_stats.exp_to_next(), player_stats.character_level)

# ── Equipment ─────────────────────────────────────────────────────────────────

# costs_turn: if true, emits equip_action_taken so player.gd consumes 1 turn.
# Pass false for auto-equip on pickup and startup.
func equip(item: Item, slot_name: String = "", costs_turn: bool = false) -> void:
	if slot_name == "":
		match item.item_type:
			Item.Type.WEAPON:
				if item.is_ranged:
					slot_name = "ranged"
				else:
					slot_name = "melee"
			Item.Type.ARMOR:  slot_name = "armor"
			_: return
	if not equipment.has(slot_name):
		return

	var prev: Item = equipment[slot_name] as Item
	equipment[slot_name] = item
	_remove_from_bags(item)
	if prev != null:
		_add_to_bags_silent(prev)
	recalculate_stats()
	combat_message.emit("[color=cyan]Equipped [b]%s[/b].[/color]" % item.item_name)
	equipment_changed.emit()
	inventory_changed.emit()
	if costs_turn and class_selected:
		equip_action_taken.emit()

func unequip(slot_name: String, costs_turn: bool = false) -> void:
	if not equipment.has(slot_name):
		return
	var item: Item = equipment[slot_name] as Item
	if item == null:
		return
	if add_item(item):
		equipment[slot_name] = null
		recalculate_stats()
		combat_message.emit("[color=cyan]Unequipped [b]%s[/b].[/color]" % item.item_name)
		equipment_changed.emit()
		if costs_turn and class_selected:
			equip_action_taken.emit()
	else:
		combat_message.emit("[color=red]No bag space to unequip %s![/color]" % item.item_name)

func toggle_versatile_grip() -> void:
	var item: Item = equipment.get("melee") as Item
	if item == null or not item.is_versatile:
		return
	var tmp_min: int = item.damage_die_min
	var tmp_max: int = item.damage_die_max
	item.damage_die_min = item.versatile_die_min
	item.damage_die_max = item.versatile_die_max
	item.versatile_die_min = tmp_min
	item.versatile_die_max = tmp_max
	item.is_two_handed = not item.is_two_handed
	recalculate_stats()
	combat_message.emit("[color=cyan]%s gripped %s-handed.[/color]" % [item.item_name, "two" if item.is_two_handed else "one"])
	equipment_changed.emit()

func recalculate_stats() -> void:
	var s: Stats = player_stats
	s.armor = 0
	var has_armor: bool = (equipment.get("armor") as Item) != null
	s.recalc_ac(has_armor)
	# Start from weapon's own damage die if it defines one, else base stats
	var melee: Item = equipment.get("melee") as Item
	if melee != null and melee.damage_die_min > 0:
		s.min_damage = melee.damage_die_min + melee.bonus_damage
		s.max_damage = melee.damage_die_max + melee.bonus_damage
	else:
		s.min_damage = s.base_min_damage + (melee.bonus_damage if melee != null else 0)
		s.max_damage = s.base_max_damage + (melee.bonus_damage if melee != null else 0)
	for slot_name: String in equipment:
		var it: Item = equipment[slot_name] as Item
		if it == null:
			continue
		if slot_name == "melee":
			continue  # already handled above
		s.armor_class += it.bonus_ac
	s.armor_class += terrain_ac_bonus

func move_item(src: String, src_idx: int, src_slot: String,
			   dest: String, dest_idx: int, dest_slot: String) -> void:
	if src == dest and src_idx == dest_idx and src_slot == dest_slot:
		return
	var src_item: Item  = _get_slot_item(src, src_idx, src_slot)
	var dest_item: Item = _get_slot_item(dest, dest_idx, dest_slot)
	_set_slot_item(src, src_idx, src_slot, dest_item)
	_set_slot_item(dest, dest_idx, dest_slot, src_item)
	recalculate_stats()
	equipment_changed.emit()
	inventory_changed.emit()
	# Drag-drop into/from equipment slot costs 1 turn
	var touches_equip: bool = (src == "equipment" or dest == "equipment")
	if touches_equip and class_selected:
		equip_action_taken.emit()

func _get_slot_item(source: String, idx: int, slot_name: String) -> Item:
	match source:
		"equipment": return equipment.get(slot_name) as Item
		"quickbar":
			if idx >= 0 and idx < player_quickbar.size():
				return player_quickbar[idx] as Item
		"inventory":
			if idx >= 0 and idx < player_inventory.size():
				return player_inventory[idx] as Item
	return null

func _set_slot_item(source: String, idx: int, slot_name: String, item: Item) -> void:
	match source:
		"equipment": equipment[slot_name] = item
		"quickbar":
			if idx >= 0 and idx < player_quickbar.size():
				player_quickbar[idx] = item
		"inventory":
			if idx >= 0 and idx < player_inventory.size():
				player_inventory[idx] = item

# ── Item management ───────────────────────────────────────────────────────────

func add_item(item: Item) -> bool:
	# Weapons with individual durability (uses_max > 0, e.g. thrown weapons) never merge into a
	# shared quantity stack — each carries its own uses_remaining, and merging would silently
	# discard that per-instance state. Each one always lands in its own slot instead, so it can
	# be thrown/equipped one at a time independently of any others of the same name.
	var stackable: bool = not (item.item_type == Item.Type.WEAPON and item.uses_max > 0)
	if stackable:
		# Try stacking in quickbar, then bag
		for i: int in QUICKBAR_SIZE:
			var ex: Item = player_quickbar[i] as Item
			if ex != null and ex.item_name == item.item_name:
				ex.quantity += item.quantity
				inventory_changed.emit()
				return true
		for i: int in INVENTORY_SIZE:
			var ex: Item = player_inventory[i] as Item
			if ex != null and ex.item_name == item.item_name:
				ex.quantity += item.quantity
				inventory_changed.emit()
				return true
	# Empty quickbar slot first, then bag
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == null:
			player_quickbar[i] = item
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			player_inventory[i] = item
			inventory_changed.emit()
			return true
	combat_message.emit("[color=red]Your bag is full![/color]")
	return false

func use_item(item: Item) -> void:
	match item.item_type:
		Item.Type.POTION:
			AudioManager.play("drink_potion")
			if item.heal_dice_count > 0:
				# Dice-based heal (e.g. 2d4+CON for Health Potion)
				var raw_roll: int = 0
				for _i: int in item.heal_dice_count:
					raw_roll += randi_range(1, item.heal_dice_sides)
				var con_mod: int = player_stats.con_modifier()
				var amount: int = maxi(1, raw_roll + con_mod)
				var before: int = player_stats.current_hp
				heal(amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					var _hm: String = "heal:dice=%d,sides=%d,con=%d,roll=%d,total=%d" % [item.heal_dice_count, item.heal_dice_sides, con_mod, raw_roll, healed]
					combat_message.emit("You drink [b]%s[/b] and heal [url=%s][color=lime]+%d HP[/color][/url]" % [item.item_name, _hm, healed])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
			elif item.heal_amount > 0:
				var before: int = player_stats.current_hp
				heal(item.heal_amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					combat_message.emit("[color=green]You drink [b]%s[/b] and recover %d HP.[/color]" % [item.item_name, healed])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
			if item.str_bonus > 0:
				player_stats.base_min_damage += item.str_bonus
				player_stats.base_max_damage += item.str_bonus
				recalculate_stats()
				combat_message.emit("[color=yellow]You drink [b]%s[/b]. Your attacks surge! (+%d ATK)[/color]" % [item.item_name, item.str_bonus])
			if not invincible:
				consume_one(item)
			potion_drunk.emit()
		Item.Type.FOOD:
			AudioManager.play("eat_food")
			if item.item_name == "Rotten Meat":
				restore_hunger(item.heal_amount)
				apply_player_status("poison", 3)
				game_log("[color=red]You choke down the rotten meat. You feel sick! (Poisoned 3 turns)[/color]")
			else:
				restore_hunger(item.heal_amount)
				game_log("[color=green]You eat [b]%s[/b]. Not so hungry anymore.[/color]" % item.item_name)
			consume_one(item)
		Item.Type.WEAPON, Item.Type.ARMOR:
			equip(item, "", false)  # equipping from bag/quickbar is a free action
		Item.Type.TOOL:
			player_tool_primed.emit(item)

func consume_one(item: Item) -> void:
	if item.quantity > 1:
		item.quantity -= 1
		inventory_changed.emit()
	else:
		remove_item(item)

func remove_item(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == item:
			player_quickbar[i] = null
			inventory_changed.emit()
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == item:
			player_inventory[i] = null
			inventory_changed.emit()
			return

func _remove_from_bags(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == item:
			player_quickbar[i] = null
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == item:
			player_inventory[i] = null
			return

func _add_to_bags_silent(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == null:
			player_quickbar[i] = item
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			player_inventory[i] = item
			return

func game_log(msg: String) -> void:
	combat_message.emit(msg)

# ── Hunger ────────────────────────────────────────────────────────────────────

func deplete_hunger() -> void:
	if is_game_over:
		return
	var prev_state: HungerState = hunger_state
	hunger = maxi(0, hunger - 1)
	hunger_changed.emit(hunger)
	var new_state: HungerState = hunger_state
	if new_state != prev_state:
		if new_state == HungerState.HUNGRY:
			AudioManager.play("hungry")
		elif new_state == HungerState.STARVING:
			AudioManager.play("starving")
	if hunger == 0:
		_starvation_tick += 1
		if _starvation_tick >= STARVE_INTERVAL:
			_starvation_tick = 0
			take_damage_raw(1)
			game_log("[color=red]You are starving![/color]")
	else:
		_starvation_tick = 0

func restore_hunger(amount: int) -> void:
	hunger = mini(MAX_HUNGER, hunger + amount)
	hunger_changed.emit(hunger)

# is_raging is set by player.gd and read here to apply damage resistance.
var is_raging: bool = false
# reckless_attack_active is set by player.gd; enemies read it to decide their attack bonus type.
var reckless_attack_active: bool = false
# Set true after first reckless attack this turn — locks the toggle and blocks further bonus.
var reckless_locked_this_turn: bool = false
# Set true by take_damage_raw when the player takes physical hit damage (not status/starvation).
# Player.gd reads this in _on_turn_started to decide whether to pause the rage countdown.
var player_was_hit_this_turn: bool = false

var reckless_rank: int:
	get: return get_talent_rank("reckless_attack")

# Synced by player.gd each turn so HUD can display remaining rage turns on the ability slot.
var rage_turns_remaining: int = 0

func take_damage_raw(amount: int, ignore_rage: bool = false, damage_type: String = "") -> int:
	if is_game_over or invincible:
		return 0
	var final_amount: int = amount
	# Rage talent ranks 2+: physical damage reduction (Bludgeoning/Piercing/Slashing only).
	# Status effects and traps pass damage_type="" — they bypass reduction intentionally.
	const PHYSICAL_TYPES: Array = ["Slashing", "Piercing", "Bludgeoning"]
	const CELESTIAL_TYPES: Array = ["Necrotic", "Radiant", "Psychic"]
	var is_physical: bool = damage_type in PHYSICAL_TYPES
	var rage_rank: int = get_talent_rank("rage")
	if is_raging and not ignore_rage and rage_rank >= 2 and is_physical:
		var reduction: float = 0.5 if rage_rank >= 3 else 0.25
		final_amount = int(floor(float(amount) * (1.0 - reduction)))
	# Natural Rager Bear form: magical DR while raging (R1: 25%, R2+: 50%, R3: +50% celestial)
	var nr_rank: int = get_talent_rank("natural_rager")
	if nr_rank >= 1 and is_raging and natural_rager_form == "Bear" and not ignore_rage:
		var is_magical: bool = not (damage_type in PHYSICAL_TYPES or damage_type == "")
		if is_magical:
			var bear_dr: float = 0.25 if nr_rank == 1 else 0.5
			final_amount = int(floor(float(final_amount) * (1.0 - bear_dr)))
			if nr_rank >= 3 and damage_type in CELESTIAL_TYPES:
				final_amount = int(floor(float(final_amount) * 0.5))
	# DR can reduce damage to 0 — skip Stats.take_damage() which floors at 1.
	if final_amount <= 0:
		if is_physical and not ignore_rage:
			player_was_hit_this_turn = true
		return 0
	var actual: int = player_stats.take_damage(final_amount)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	if is_physical and not ignore_rage:
		player_was_hit_this_turn = true
	check_player_death()
	return actual


func apply_player_status(type: String, turns: int) -> bool:
	# Rager rank 1: chance to negate a status/debuff while raging.
	if get_talent_rank("rager") >= 1 and is_raging:
		var chance: int = player_stats.rage_bonus_damage * 10  # 20%/30%/40%
		if randi_range(1, 100) <= chance:
			game_log("[color=orange]Rager shrugs off the %s![/color]" % type)
			return false
	match type:
		"poison":   player_stats.poison_turns  = maxi(player_stats.poison_turns, turns)
		"burning":  player_stats.burning_turns = maxi(player_stats.burning_turns, turns)
		"bleeding": player_stats.bleeding_turns = maxi(player_stats.bleeding_turns, turns)
		"slowed":   player_stats.slowed_turns  = maxi(player_stats.slowed_turns, turns)
	player_status_changed.emit()
	return true


func _apply_monk_level_features(level: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.MONK:
		return
	var die_sides: int = player_stats.martial_arts_die_sides
	match level:
		4:
			player_stats.dexterity += 2
			recalculate_stats()
			combat_message.emit("[color=cyan]Level 4 Monk: DEX +2 (now [b]%d[/b], modifier +%d)![/color]" % [player_stats.dexterity, player_stats.dex_modifier()])
		5, 11, 17:
			var ma: Ability = _find_ability_by_id("martial_arts")
			if ma != null:
				ma.description = "Passive: Unarmed strikes use DEX + 1d%d. Bonus-action unarmed strike after main-action attack. Die scales at levels 5/11/17." % die_sides
			ability_bar_changed.emit()
			combat_message.emit("[color=cyan]Level %d Monk: Martial Arts die increased to [b]1d%d[/b]![/color]" % [level, die_sides])

func debug_jump_to_floor(n: int) -> void:
	is_game_over = false
	current_floor = n
	floor_changed.emit(current_floor)
	debug_jump_floor.emit(n)

# ── Talent system ─────────────────────────────────────────────────────────────

func get_talent_rank(id: String) -> int:
	return talent_investments.get(id, 0)

func _find_talent(id: String) -> Talent:
	for t: Talent in _class_talents:
		if t.talent_id == id:
			return t
	return null

func can_invest_talent(id: String) -> bool:
	var t: Talent = _find_talent(id)
	if t == null:
		return false
	if get_talent_rank(id) >= t.max_rank:
		return false
	var pool: int = tier1_talent_points if t.tier == 1 else tier2_talent_points
	return pool > 0

func invest_talent(id: String) -> void:
	if not can_invest_talent(id):
		return
	var t: Talent = _find_talent(id)
	var new_rank: int = get_talent_rank(id) + 1
	talent_investments[id] = new_rank
	if not invincible:
		if t.tier == 1:
			tier1_talent_points -= 1
		else:
			tier2_talent_points -= 1
	_apply_talent_rank(id, new_rank)
	talent_invested.emit(id, new_rank)
	talent_points_changed.emit(talent_points_available)

func debug_set_talent_rank(id: String, new_rank: int) -> void:
	var talent: Talent = _find_talent(id)
	if talent == null:
		return
	new_rank = clampi(new_rank, 0, talent.max_rank)
	var old_rank: int = get_talent_rank(id)
	if new_rank == old_rank:
		return
	if new_rank < old_rank:
		if id == "danger_sense" and old_rank >= 3 and new_rank < 3:
			player_stats.strength = maxi(10, player_stats.strength - 2)
			recalculate_stats()
		if new_rank == 0 and id != "rage":
			for i: int in player_ability_bar.size():
				var ab: Ability = player_ability_bar[i]
				if ab != null and ab.ability_id == id:
					player_ability_bar[i] = null
					break
	if new_rank == 0:
		talent_investments.erase(id)
	else:
		talent_investments[id] = new_rank
	if new_rank > old_rank:
		for r: int in range(old_rank + 1, new_rank + 1):
			if r == 1 and _find_ability_by_id(id) != null:
				continue
			_apply_talent_rank(id, r)
	elif new_rank > 0:
		_apply_talent_rank(id, new_rank)
	talent_invested.emit(id, new_rank)
	ability_bar_changed.emit()
	talent_points_changed.emit(talent_points_available)

func _apply_talent_rank(id: String, rank: int) -> void:
	match id:
		"rage":
			_sync_ability_uses()
			var rage_ab: Ability = _find_ability_by_id("rage")
			if rage_ab != null:
				rage_ab.description = _build_rage_description()
				rage_ab.icon_path = talent_icon_path("rage", rank)
		"reckless_attack":
			if rank == 1:
				var ra := Ability.new()
				ra.ability_id = "reckless_attack"
				ra.ability_name = "Reckless"
				ra.description = _build_reckless_description(1)
				ra.icon_path = talent_icon_path("reckless_attack", 1)
				ra.uses_remaining = 0
				ra.uses_max = 0
				add_ability(ra)
			else:
				var ra: Ability = _find_ability_by_id("reckless_attack")
				if ra != null:
					ra.description = _build_reckless_description(rank)
					ra.icon_path = talent_icon_path("reckless_attack", rank)
		"rager":
			if rank == 1:
				var rager_ab := Ability.new()
				rager_ab.ability_id = "rager"
				rager_ab.ability_name = "Rager"
				rager_ab.description = _build_rager_description()
				rager_ab.icon_path = talent_icon_path("rager", 1)
				rager_ab.uses_remaining = 0
				rager_ab.uses_max = 0
				rager_ab.is_passive = true
				add_ability(rager_ab)
			else:
				var rager_ab: Ability = _find_ability_by_id("rager")
				if rager_ab != null:
					rager_ab.description = _build_rager_description()
					rager_ab.icon_path = talent_icon_path("rager", rank)
		"frenzy":
			if rank == 1:
				var frenzy_ab := Ability.new()
				frenzy_ab.ability_id = "frenzy"
				frenzy_ab.ability_name = "Frenzy"
				frenzy_ab.description = _build_frenzy_description()
				frenzy_ab.icon_path = talent_icon_path("frenzy", 1)
				frenzy_ab.uses_remaining = 0
				frenzy_ab.uses_max = 0
				frenzy_ab.is_passive = true
				add_ability(frenzy_ab)
			else:
				var frenzy_ab: Ability = _find_ability_by_id("frenzy")
				if frenzy_ab != null:
					frenzy_ab.description = _build_frenzy_description()
					frenzy_ab.icon_path = talent_icon_path("frenzy", rank)
		"retaliation":
			if rank == 1:
				var ret_ab := Ability.new()
				ret_ab.ability_id = "retaliation"
				ret_ab.ability_name = "Retaliation"
				ret_ab.description = _build_retaliation_description()
				ret_ab.icon_path = talent_icon_path("retaliation", 1)
				ret_ab.uses_remaining = 0
				ret_ab.uses_max = 0
				ret_ab.is_passive = true
				add_ability(ret_ab)
			else:
				var ret_ab: Ability = _find_ability_by_id("retaliation")
				if ret_ab != null:
					ret_ab.description = _build_retaliation_description()
					ret_ab.icon_path = talent_icon_path("retaliation", rank)
		"danger_sense":
			if rank == 1:
				var ds := Ability.new()
				ds.ability_id = "danger_sense"
				ds.ability_name = "Danger Sense"
				ds.description = _build_danger_sense_description(1)
				ds.icon_path = talent_icon_path("danger_sense", 1)
				ds.uses_remaining = 0
				ds.uses_max = 0
				ds.is_passive = true
				add_ability(ds)
			elif rank == 2:
				var ds: Ability = _find_ability_by_id("danger_sense")
				if ds != null:
					ds.description = _build_danger_sense_description(2)
					ds.icon_path = talent_icon_path("danger_sense", 2)
			elif rank == 3:
				player_stats.strength += 2
				recalculate_stats()
				var ds: Ability = _find_ability_by_id("danger_sense")
				if ds != null:
					ds.description = _build_danger_sense_description(3)
					ds.icon_path = talent_icon_path("danger_sense", 3)
				combat_message.emit("[color=cyan]Danger Sense 3: STR +2 (now [b]%d[/b])![/color]" % player_stats.strength)
		"one_with_nature":
			if rank == 1:
				var owtn := Ability.new()
				owtn.ability_id = "one_with_nature"
				owtn.ability_name = "One with Nature"
				owtn.description = _build_one_with_nature_description()
				owtn.icon_path = talent_icon_path("one_with_nature", 1)
				owtn.uses_remaining = 1
				owtn.uses_max = 1
				add_ability(owtn)
			else:
				var owtn: Ability = _find_ability_by_id("one_with_nature")
				if owtn != null:
					owtn.description = _build_one_with_nature_description()
					owtn.icon_path = talent_icon_path("one_with_nature", rank)
		"natural_rager":
			if rank == 1:
				var nr := Ability.new()
				nr.ability_id = "natural_rager"
				nr.ability_name = "Natural Rager"
				nr.description = _build_natural_rager_description()
				nr.icon_path = talent_icon_path("natural_rager", 1)
				nr.uses_remaining = 0
				nr.uses_max = 0
				add_ability(nr)
			else:
				var nr: Ability = _find_ability_by_id("natural_rager")
				if nr != null:
					nr.description = _build_natural_rager_description()
					nr.icon_path = talent_icon_path("natural_rager", rank)
		"natural_sleeper":
			if rank == 1:
				var ns := Ability.new()
				ns.ability_id = "natural_sleeper"
				ns.ability_name = "Natural Sleeper"
				ns.description = _build_natural_sleeper_description()
				ns.icon_path = talent_icon_path("natural_sleeper", 1)
				ns.uses_remaining = 0
				ns.uses_max = 0
				add_ability(ns)
			else:
				var ns: Ability = _find_ability_by_id("natural_sleeper")
				if ns != null:
					ns.description = _build_natural_sleeper_description()
					ns.icon_path = talent_icon_path("natural_sleeper", rank)
		"ironwood_bark":
			if rank == 1:
				var ib := Ability.new()
				ib.ability_id = "ironwood_bark"
				ib.ability_name = "Ironwood Bark"
				ib.description = _build_ironwood_bark_description()
				ib.icon_path = talent_icon_path("ironwood_bark", 1)
				ib.uses_remaining = 0
				ib.uses_max = 0
				ib.is_passive = true
				add_ability(ib)
			else:
				var ib: Ability = _find_ability_by_id("ironwood_bark")
				if ib != null:
					ib.description = _build_ironwood_bark_description()
					ib.icon_path = talent_icon_path("ironwood_bark", rank)
		"grip_of_the_forest":
			if rank == 1:
				var gotf := Ability.new()
				gotf.ability_id = "grip_of_the_forest"
				gotf.ability_name = "Grip of the Forest"
				gotf.description = _build_grip_of_the_forest_description()
				gotf.icon_path = talent_icon_path("grip_of_the_forest", 1)
				gotf.uses_remaining = 0
				gotf.uses_max = 0
				add_ability(gotf)
			else:
				var gotf: Ability = _find_ability_by_id("grip_of_the_forest")
				if gotf != null:
					gotf.description = _build_grip_of_the_forest_description()
					gotf.icon_path = talent_icon_path("grip_of_the_forest", rank)
		"branching_strike":
			if rank == 1:
				var bs := Ability.new()
				bs.ability_id = "branching_strike"
				bs.ability_name = "Branching Strike"
				bs.description = _build_branching_strike_description()
				bs.icon_path = talent_icon_path("branching_strike", 1)
				bs.uses_remaining = 0
				bs.uses_max = 0
				bs.is_passive = true
				add_ability(bs)
			else:
				var bs: Ability = _find_ability_by_id("branching_strike")
				if bs != null:
					bs.description = _build_branching_strike_description()
					bs.icon_path = talent_icon_path("branching_strike", rank)
		"divine_fury":
			if rank == 1:
				var df := Ability.new()
				df.ability_id = "divine_fury"
				df.ability_name = "Divine Fury"
				df.description = _build_divine_fury_description()
				df.icon_path = talent_icon_path("divine_fury", 1)
				df.uses_remaining = 0
				df.uses_max = 0
				add_ability(df)
			else:
				var df: Ability = _find_ability_by_id("divine_fury")
				if df != null:
					df.description = _build_divine_fury_description()
					df.icon_path = talent_icon_path("divine_fury", rank)
		"blessed_warrior":
			var new_max: int = BLESSED_WARRIOR_MAX_CHARGES[rank]
			if rank == 1:
				zealot_blessed_charges = new_max
				var bw := Ability.new()
				bw.ability_id = "blessed_warrior"
				bw.ability_name = "Blessed Warrior"
				bw.description = _build_blessed_warrior_description()
				bw.icon_path = talent_icon_path("blessed_warrior", 1)
				bw.uses_remaining = zealot_blessed_charges
				bw.uses_max = new_max
				add_ability(bw)
			else:
				# Rank-up mid-run: new pool size is the new rank's max, minus charges
				# already spent this long-rest cycle (spec: preserve "already used", not "already left").
				var old_max: int = BLESSED_WARRIOR_MAX_CHARGES[rank - 1]
				var used: int = old_max - zealot_blessed_charges
				zealot_blessed_charges = maxi(0, new_max - used)
				var bw: Ability = _find_ability_by_id("blessed_warrior")
				if bw != null:
					bw.description = _build_blessed_warrior_description()
					bw.icon_path = talent_icon_path("blessed_warrior", rank)
					bw.uses_remaining = zealot_blessed_charges
					bw.uses_max = new_max
		"zealous_presence":
			if rank == 1:
				zealot_zp_charges = 1
				var zp := Ability.new()
				zp.ability_id = "zealous_presence"
				zp.ability_name = "Zealous Presence"
				zp.description = _build_zealous_presence_description()
				zp.icon_path = talent_icon_path("zealous_presence", 1)
				zp.uses_remaining = zealot_zp_charges
				zp.uses_max = 1
				add_ability(zp)
			else:
				var zp: Ability = _find_ability_by_id("zealous_presence")
				if zp != null:
					zp.icon_path = talent_icon_path("zealous_presence", rank)
					zp.description = _build_zealous_presence_description()
	ability_bar_changed.emit()

func _build_rager_description() -> String:
	var rank: int = get_talent_rank("rager")
	var chance: int = player_stats.rage_bonus_damage * 10
	var lines: Array[String] = []
	lines.append("While Raging: %d%% chance per trigger (scales with Rage damage bonus)." % chance)
	if rank >= 1: lines.append("R1: Negate incoming status/debuff effects.")
	if rank >= 2: lines.append("R2: Move may not end your turn (once per round).")
	if rank >= 3: lines.append("R3: Attack may not end your turn (once per round, independent).")
	return "\n".join(lines)


func _build_frenzy_description() -> String:
	var rank: int = get_talent_rank("frenzy")
	var bonus: int = player_stats.rage_bonus_damage
	var die_sides: int = [0, 4, 6, 8][mini(rank, 3)]
	return "While Raging, first STR attack each turn: +1d%d × %d (%s) Slashing bonus damage." % [
		die_sides, bonus, "current die" if rank > 0 else ""]


func _build_retaliation_description() -> String:
	var rank: int = get_talent_rank("retaliation")
	var bonus: int = player_stats.rage_bonus_damage
	var lines: Array[String] = []
	match rank:
		1: lines.append("When hit by adjacent melee: deal %d back (rage bonus)." % bonus)
		2: lines.append("When hit by adjacent melee: deal weapon damage back (no rage bonus at this rank).")
		3: lines.append("When hit by adjacent melee: deal weapon damage + %d rage + STR mod back." % bonus)
	return "\n".join(lines)


func _build_rage_description() -> String:
	var rank: int = get_talent_rank("rage")
	var uses: int = player_stats.rage_uses_max
	var bonus: int = player_stats.rage_bonus_damage
	var lines: Array[String] = []
	lines.append("Lasts 10 turns. +%d damage on STR attacks." % bonus)
	if rank >= 1:
		lines.append("Countdown pauses when you attack or are hit.")
	if rank >= 2:
		lines.append("25% DR vs Bludgeoning/Piercing/Slashing.")
	if rank >= 3:
		lines.append("50% DR vs Bludgeoning/Piercing/Slashing.")
	lines.append("%d use%s per floor (scales with level)." % [uses, "s" if uses != 1 else ""])
	return "\n".join(lines)

func _build_reckless_description(rank: int) -> String:
	match rank:
		1: return "Toggle (free action): +2 to your first STR melee attack roll this turn. Enemies also get +2 to their attack rolls against you."
		2: return "Toggle (free action): Advantage on your first STR melee attack roll. Enemies gain Advantage against you."
		3: return "Toggle (free action): Advantage on all STR melee attack rolls. Enemies gain Advantage against you."
	return ""

func _build_danger_sense_description(rank: int) -> String:
	var lines: Array[String] = ["Passive."]
	if rank >= 1:
		lines.append("Advantage on DEX checks (traps, locks).")
	if rank >= 2:
		lines.append("For DEX/WIS/CHA checks, use whichever is higher: normal modifier or STR modifier.")
	if rank >= 3:
		lines.append("STR +2.")
	return "\n".join(lines)

func _build_one_with_nature_description() -> String:
	var rank: int = get_talent_rank("one_with_nature")
	var d: Dictionary = WILD_HEART_COMPANION_STATS.get(maxi(rank, 1), {})
	var animal: String = d.get("animal", "Squirrel")
	var hp: int = d.get("hp", 10)
	var ac: int = d.get("ac", 12)
	var dc: int = d.get("die_count", 1)
	var ds_: int = d.get("die_sides", 6)
	return "Summon a %s (HP %d, AC %d, %dd%d) to fight by your side.\n1 charge — refreshes on rest. Re-activate to dismiss and resummon." % [animal, hp, ac, dc, ds_]

func _build_natural_rager_description() -> String:
	var rank: int = get_talent_rank("natural_rager")
	var form: String = natural_rager_form
	var lines: Array[String] = []
	lines.append("[%s Form] — effects active while Raging. Click to cycle forms." % form)
	match form:
		"Bear":
			if rank >= 1: lines.append("R1: −25% incoming magical damage.")
			if rank >= 2: lines.append("R2: −50% incoming magical damage.")
			if rank >= 3: lines.append("R3: Also −50% Necrotic/Radiant/Psychic (total 75%).")
		"Eagle":
			if rank >= 1: lines.append("R1: 50%% chance a move doesn't end your turn (once/round).")
			if rank >= 2: lines.append("R2: Guaranteed second move each turn (replaces R1).")
			if rank >= 3: lines.append("R3: Evade opportunity attacks. [color=gray](No-op until OA system added.)[/color]")
		"Wolf":
			var threshold: int = [0, 4, 3, 2][mini(rank, 3)]
			lines.append("ADV on attack rolls when %d+ enemies are in your FOV." % threshold)
	return "\n".join(lines)

func _build_natural_sleeper_description() -> String:
	var rank: int = get_talent_rank("natural_sleeper")
	var form: String = natural_sleeper_form  # chosen form (preview for next rest)
	var lines: Array[String] = []
	# No form chosen yet
	if form == "":
		lines.append("[No form chosen] — press to select Owl / Panther / Salmon.")
		if not wild_heart_sleeper_active:
			lines.append("[color=gray](Rest or descend to activate chosen form.)[/color]")
		return "\n".join(lines)
	# Form chosen — show header and per-form rank effects
	if wild_heart_sleeper_active and active_sleeper_form != form:
		var active_label: String = active_sleeper_form if active_sleeper_form != "" else "none"
		lines.append("[%s Form] — activates next rest. [color=gray]Active now: %s[/color]" % [form, active_label])
	elif wild_heart_sleeper_active:
		lines.append("[%s Form — active this floor] Press to choose next rest's form." % form)
	else:
		lines.append("[%s Form] — will activate on floor descent. Press to cycle." % form)
	match form:
		"Owl":
			if rank >= 1: lines.append("R1: Pass through chasms freely.")
			if rank >= 2: lines.append("R2: 2d6 temp HP at the start of each turn while in a chasm.")
			if rank >= 3: lines.append("R3: +2 AC while standing in a chasm.")
		"Panther":
			if rank >= 1: lines.append("R1: Mud is no longer difficult terrain.")
			if rank >= 2: lines.append("R2: 2d6 temp HP at the start of each turn while in mud.")
			if rank >= 3: lines.append("R3: +2 AC while standing in mud.")
		"Salmon":
			if rank >= 1: lines.append("R1: Water is no longer difficult terrain.")
			if rank >= 2: lines.append("R2: 2d6 temp HP at the start of each turn while in water.")
			if rank >= 3: lines.append("R3: +2 AC while standing in water.")
	if not wild_heart_sleeper_active:
		lines.append("[color=gray](Rest or descend to activate.)[/color]")
	return "\n".join(lines)

func _build_ironwood_bark_description() -> String:
	var rank: int = get_talent_rank("ironwood_bark")
	var bonus: int = player_stats.rage_bonus_damage
	var lines: Array[String] = []
	if rank >= 1: lines.append("R1: Activating Rage grants 1d6 × %d temp HP." % bonus)
	if rank >= 2: lines.append("R2: While Raging, refresh temp HP (1d6 × %d) if you start your turn at 0." % bonus)
	if rank >= 3: lines.append("R3: While Raging, if you start your turn with temp HP > 0, your next attack deals bonus damage equal to it.")
	return "\n".join(lines)

func _build_grip_of_the_forest_description() -> String:
	var rank: int = get_talent_rank("grip_of_the_forest")
	var hook_range: int = [0, 3, 4, 5][mini(rank, 3)]
	var lines: Array[String] = ["While Raging, once per turn: target an enemy within %d tiles (STR check DC 8+STR mod+prof to resist) and pull them into melee range." % hook_range]
	if rank >= 2: lines.append("R2: On success, the target can't move on their next turn.")
	if rank >= 3: lines.append("R3: On success, the target also has Disadvantage on their next attack roll.")
	return "\n".join(lines)

func _build_branching_strike_description() -> String:
	var rank: int = get_talent_rank("branching_strike")
	var lines: Array[String] = []
	if rank >= 2: lines.append("R2: +2 tiles reach with Heavy/Versatile melee weapons.")
	elif rank >= 1: lines.append("R1: +1 tile reach with Heavy/Versatile melee weapons.")
	if rank >= 3: lines.append("R3: On hit with a Heavy/Versatile melee weapon, push the target 1 tile away (CON check DC 8+STR mod+prof to resist).")
	return "\n".join(lines)


func _build_divine_fury_description() -> String:
	var rank: int = get_talent_rank("divine_fury")
	var lvl: int = player_stats.character_level
	var lines: Array[String] = ["[%s] — click to switch damage type." % zealot_divine_fury_type]
	match rank:
		1: lines.append("First attack each turn: +1d6 bonus damage.")
		2: lines.append("First attack each turn: +1d6 + %d bonus damage (level/4)." % (lvl / 4))
		3: lines.append("First attack each turn: +1d6 + %d bonus damage (level/2)." % (lvl / 2))
	return "\n".join(lines)

func _build_blessed_warrior_description() -> String:
	var rank: int = get_talent_rank("blessed_warrior")
	var max_charges: int = BLESSED_WARRIOR_MAX_CHARGES[maxi(rank, 1)]
	return "Activate (max once/turn, %d/%d charges) to queue a 1d12 heal on your next successful hit this turn. A miss still spends the charge. Recharges on long rest." % [zealot_blessed_charges, max_charges]

func _build_zealous_presence_description() -> String:
	var rank: int = get_talent_rank("zealous_presence")
	var duration: int = [0, 1, 3, 5][mini(rank, 3)]
	var lines: Array[String] = [
		"Grant Advantage on all attack rolls and checks to yourself and friendly entities in FOV for %d turn(s)." % duration,
		"%d/1 Zealous Presence charge — recharges on long rest." % zealot_zp_charges,
		"If out of charges, consumes 1 Rage charge instead (silently, only if a ZP charge isn't available).",
	]
	return "\n".join(lines)

func _setup_barbarian_talents() -> void:
	_class_talents = []

	var rage_talent := Talent.new()
	rage_talent.talent_id = "rage"
	rage_talent.talent_name = "Rage"
	rage_talent.description = "Upgrade your Rage ability."
	rage_talent.icon_path = talent_icon_path("rage", 1)
	rage_talent.tier = 1
	rage_talent.class_id = Stats.CharacterClass.BARBARIAN
	rage_talent.max_rank = 3
	rage_talent.ranks = [
		{"description": "Rage countdown pauses when you attack or are hit (active combat extends duration)."},
		{"description": "25% damage reduction vs Bludgeoning, Piercing, and Slashing damage while raging."},
		{"description": "50% damage reduction vs Bludgeoning, Piercing, and Slashing damage while raging."},
	]
	_class_talents.append(rage_talent)

	var reckless_talent := Talent.new()
	reckless_talent.talent_id = "reckless_attack"
	reckless_talent.talent_name = "Reckless Attack"
	reckless_talent.description = "Unlock and upgrade Reckless Attack."
	reckless_talent.icon_path = talent_icon_path("reckless_attack", 1)
	reckless_talent.tier = 1
	reckless_talent.class_id = Stats.CharacterClass.BARBARIAN
	reckless_talent.max_rank = 3
	reckless_talent.ranks = [
		{"description": "Toggle: +2 to first STR attack roll. Enemies +2 to attacks vs you."},
		{"description": "Toggle: Advantage on first STR attack roll. Enemies gain Advantage vs you."},
		{"description": "Toggle: Advantage on all STR attack rolls. Enemies gain Advantage vs you."},
	]
	_class_talents.append(reckless_talent)

	var ds_talent := Talent.new()
	ds_talent.talent_id = "danger_sense"
	ds_talent.talent_name = "Danger Sense"
	ds_talent.description = "Unlock and upgrade Danger Sense."
	ds_talent.icon_path = talent_icon_path("danger_sense", 1)
	ds_talent.tier = 1
	ds_talent.class_id = Stats.CharacterClass.BARBARIAN
	ds_talent.max_rank = 3
	ds_talent.ranks = [
		{"description": "Advantage on DEX checks (traps, locks, Sleight of Hand)."},
		{"description": "For DEX/WIS/CHA checks, use max(normal mod, STR mod) automatically."},
		{"description": "STR +2 (flat stat increase)."},
	]
	_class_talents.append(ds_talent)


func _setup_barbarian_tier2_talents() -> void:
	# Called by unlock_tier2() when Necromancer is defeated. Appends Tier 2 to _class_talents.
	var chance_str: String = "%d%%" % (player_stats.rage_bonus_damage * 10)

	var rager_talent := Talent.new()
	rager_talent.talent_id = "rager"
	rager_talent.talent_name = "Rager"
	rager_talent.description = "Berserker fury bends the flow of combat while Raging."
	rager_talent.icon_path = talent_icon_path("rager", 1)
	rager_talent.tier = 2
	rager_talent.class_id = Stats.CharacterClass.BARBARIAN
	rager_talent.max_rank = 3
	rager_talent.ranks = [
		{"description": "%s chance to fully negate an incoming status/debuff while Raging." % chance_str},
		{"description": "%s chance after moving that the move doesn't end your turn (once per round)." % chance_str},
		{"description": "%s chance after attacking that the attack doesn't end your turn (once per round, independent of rank 2)." % chance_str},
	]
	_class_talents.append(rager_talent)

	var frenzy_talent := Talent.new()
	frenzy_talent.talent_id = "frenzy"
	frenzy_talent.talent_name = "Frenzy"
	frenzy_talent.description = "First attack each turn deals bonus Rage-scaled damage while Raging."
	frenzy_talent.icon_path = talent_icon_path("frenzy", 1)
	frenzy_talent.tier = 2
	frenzy_talent.class_id = Stats.CharacterClass.BARBARIAN
	frenzy_talent.max_rank = 3
	frenzy_talent.ranks = [
		{"description": "First STR attack while Raging: +1d4 × rage bonus (%d) extra damage." % player_stats.rage_bonus_damage},
		{"description": "Die increases to 1d6 × rage bonus (%d)." % player_stats.rage_bonus_damage},
		{"description": "Die increases to 1d8 × rage bonus (%d)." % player_stats.rage_bonus_damage},
	]
	_class_talents.append(frenzy_talent)

	var retaliation_talent := Talent.new()
	retaliation_talent.talent_id = "retaliation"
	retaliation_talent.talent_name = "Retaliation"
	retaliation_talent.description = "Strike back at enemies who hit you in melee."
	retaliation_talent.icon_path = talent_icon_path("retaliation", 1)
	retaliation_talent.tier = 2
	retaliation_talent.class_id = Stats.CharacterClass.BARBARIAN
	retaliation_talent.max_rank = 3
	retaliation_talent.ranks = [
		{"description": "When hit by a melee attack: deal %d damage back (rage bonus only)." % player_stats.rage_bonus_damage},
		{"description": "Deal weapon damage back instead (no rage bonus at this rank — intentional)."},
		{"description": "Deal weapon damage + rage bonus (%d) + STR modifier back." % player_stats.rage_bonus_damage},
	]
	_class_talents.append(retaliation_talent)


func _setup_wild_heart_tier2_talents() -> void:
	# Wild Heart is an experimental subclass — balance will change significantly after playtesting.
	# Key design deviation: taking rank 1 of Natural Rager/Sleeper grants 3 simultaneous
	# switchable form effects (not 1 per point like standard talents). This is intentional.
	var owtn_talent := Talent.new()
	owtn_talent.talent_id = "one_with_nature"
	owtn_talent.talent_name = "One with Nature"
	owtn_talent.description = "Summon an animal companion that fights alongside you."
	owtn_talent.icon_path = talent_icon_path("one_with_nature", 1)
	owtn_talent.tier = 2
	owtn_talent.class_id = Stats.CharacterClass.BARBARIAN
	owtn_talent.max_rank = 3
	owtn_talent.ranks = [
		{"description": "Summon a Squirrel (HP 10, AC 12, 1d6). 1 charge per rest."},
		{"description": "Summon a Boar instead (HP 20, AC 14, 2d6). Replaces Squirrel."},
		{"description": "Summon a Bear instead (HP 30, AC 16, 3d6). Replaces Boar."},
	]
	_class_talents.append(owtn_talent)

	var nr_talent := Talent.new()
	nr_talent.talent_id = "natural_rager"
	nr_talent.talent_name = "Natural Rager"
	nr_talent.description = "Unlock Bear/Eagle/Wolf forms while Raging. 1 rank grants all 3 forms."
	nr_talent.icon_path = talent_icon_path("natural_rager", 1)
	nr_talent.tier = 2
	nr_talent.class_id = Stats.CharacterClass.BARBARIAN
	nr_talent.max_rank = 3
	nr_talent.ranks = [
		{"description": "Bear: −25% magical DMG. Eagle: 50%% free-move chance. Wolf: ADV at 4+ enemies."},
		{"description": "Bear: −50% magical. Eagle: guaranteed 2nd move (replaces R1). Wolf: threshold 3+."},
		{"description": "Bear: +−50% celestial. Eagle: OA evasion (flag only). Wolf: threshold 2+."},
	]
	_class_talents.append(nr_talent)

	var ns_talent := Talent.new()
	ns_talent.talent_id = "natural_sleeper"
	ns_talent.talent_name = "Natural Sleeper"
	ns_talent.description = "Unlock Owl/Panther/Salmon terrain forms. Activate on floor entry."
	ns_talent.icon_path = talent_icon_path("natural_sleeper", 1)
	ns_talent.tier = 2
	ns_talent.class_id = Stats.CharacterClass.BARBARIAN
	ns_talent.max_rank = 3
	ns_talent.ranks = [
		{"description": "Owl: chasm passthrough. Panther: mud is normal. Salmon: water is normal."},
		{"description": "Each form: 2d6 temp HP at the start of each turn while on its terrain."},
		{"description": "Each form: +2 AC while standing in its terrain."},
	]
	_class_talents.append(ns_talent)

func _setup_world_tree_tier2_talents() -> void:
	var rage_bonus: int = player_stats.rage_bonus_damage

	var ib_talent := Talent.new()
	ib_talent.talent_id = "ironwood_bark"
	ib_talent.talent_name = "Ironwood Bark"
	ib_talent.description = "Bark-like temporary HP fueled by Rage, with a damage payoff at rank 3."
	ib_talent.icon_path = talent_icon_path("ironwood_bark", 1)
	ib_talent.tier = 2
	ib_talent.class_id = Stats.CharacterClass.BARBARIAN
	ib_talent.max_rank = 3
	ib_talent.ranks = [
		{"description": "Activating Rage grants 1d6 × rage bonus (%d) temporary HP." % rage_bonus},
		{"description": "While Raging, if you start your turn with 0 temp HP, refresh it (1d6 × rage bonus)."},
		{"description": "While Raging, if you start your turn with temp HP > 0, your next attack this turn deals bonus damage equal to that temp HP amount."},
	]
	_class_talents.append(ib_talent)

	var gotf_talent := Talent.new()
	gotf_talent.talent_id = "grip_of_the_forest"
	gotf_talent.talent_name = "Grip of the Forest"
	gotf_talent.description = "While Raging, once per turn, pull a distant enemy into melee range."
	gotf_talent.icon_path = talent_icon_path("grip_of_the_forest", 1)
	gotf_talent.tier = 2
	gotf_talent.class_id = Stats.CharacterClass.BARBARIAN
	gotf_talent.max_rank = 3
	gotf_talent.ranks = [
		{"description": "Target an enemy within 3 tiles (STR check DC 8+STR mod+prof to resist) and pull them into melee range."},
		{"description": "Range increases to 4 tiles. On success, the target can't move on their next turn."},
		{"description": "Range increases to 5 tiles. On success, the target also has Disadvantage on their next attack roll."},
	]
	_class_talents.append(gotf_talent)

	var bs_talent := Talent.new()
	bs_talent.talent_id = "branching_strike"
	bs_talent.talent_name = "Branching Strike"
	bs_talent.description = "Extend your reach with heavy/versatile melee weapons, and push foes back."
	bs_talent.icon_path = talent_icon_path("branching_strike", 1)
	bs_talent.tier = 2
	bs_talent.class_id = Stats.CharacterClass.BARBARIAN
	bs_talent.max_rank = 3
	bs_talent.ranks = [
		{"description": "+1 tile reach when wielding a Heavy or Versatile melee weapon."},
		{"description": "+2 tiles reach when wielding a Heavy or Versatile melee weapon (replaces rank 1)."},
		{"description": "On a hit with a Heavy/Versatile melee weapon, push the target 1 tile away (CON check DC 8+STR mod+prof to resist)."},
	]
	_class_talents.append(bs_talent)

func _setup_zealot_tier2_talents() -> void:
	var df_talent := Talent.new()
	df_talent.talent_id = "divine_fury"
	df_talent.talent_name = "Divine Fury"
	df_talent.description = "Your first attack each turn is charged with Radiant or Necrotic power."
	df_talent.icon_path = talent_icon_path("divine_fury", 1)
	df_talent.tier = 2
	df_talent.class_id = Stats.CharacterClass.BARBARIAN
	df_talent.max_rank = 3
	df_talent.ranks = [
		{"description": "First attack each turn: +1d6 bonus damage (Radiant or Necrotic, your choice)."},
		{"description": "+1d6 + floor(level/4) bonus damage (replaces rank 1's formula)."},
		{"description": "+1d6 + floor(level/2) bonus damage (replaces rank 2's formula)."},
	]
	_class_talents.append(df_talent)

	var bw_talent := Talent.new()
	bw_talent.talent_id = "blessed_warrior"
	bw_talent.talent_name = "Blessed Warrior"
	bw_talent.description = "A pool of divine healing charges you can call on mid-fight."
	bw_talent.icon_path = talent_icon_path("blessed_warrior", 1)
	bw_talent.tier = 2
	bw_talent.class_id = Stats.CharacterClass.BARBARIAN
	bw_talent.max_rank = 3
	bw_talent.ranks = [
		{"description": "2 charges/long rest. Activate (max once/turn) to queue a 1d12 heal on your next successful hit this turn."},
		{"description": "4 charges/long rest."},
		{"description": "6 charges/long rest."},
	]
	_class_talents.append(bw_talent)

	var zp_talent := Talent.new()
	zp_talent.talent_id = "zealous_presence"
	zp_talent.talent_name = "Zealous Presence"
	zp_talent.description = "Rally yourself and nearby allies with Advantage on all rolls."
	zp_talent.icon_path = talent_icon_path("zealous_presence", 1)
	zp_talent.tier = 2
	zp_talent.class_id = Stats.CharacterClass.BARBARIAN
	zp_talent.max_rank = 3
	zp_talent.ranks = [
		{"description": "Grant Advantage on all attack rolls and checks to yourself and friendly entities in FOV for 1 turn. 1 charge/long rest (falls back to consuming a Rage charge if out)."},
		{"description": "Duration increases to 3 turns."},
		{"description": "Duration increases to 5 turns."},
	]
	_class_talents.append(zp_talent)
