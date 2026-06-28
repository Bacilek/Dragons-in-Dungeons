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

# Talent system — points earned per level, invested per talent
var talent_points_available: int = 0
var talent_investments: Dictionary = {}   # talent_id → current_rank (int)
var _class_talents: Array[Talent] = []    # all talents for current class, populated on class select
# Tier 2 gating: Berserker unlocks on Necromancer kill (floor 10)
var tier2_unlocked: bool = false
var _pending_tier2_points: int = 0
var short_rest_active: bool = false
var short_rest_turns_remaining: int = 0
var short_rest_pending_heal: int = 0
var player_grid_pos: Vector2i = Vector2i.ZERO
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
	"melee": null, "ranged": null, "armor": null,
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
	talent_points_available = 0
	talent_investments = {}
	_class_talents = []
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
	# Equip silently (no turn cost, no turn consumed — startup)
	equipment["melee"] = axe
	recalculate_stats()
	equipment_changed.emit()

	# Rage ability in slot 0 of ability bar
	var rage := Ability.new()
	rage.ability_id = "rage"
	rage.ability_name = "Rage"
	rage.description = _build_rage_description()
	rage.icon_path = "res://sprites/weapons/weapon_double_axe.png"
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
	add_ability(ud)
	# Martial Arts passive — die scales with level (1d6 → 1d8 → 1d10 → 1d12)
	var ma := Ability.new()
	ma.ability_id = "martial_arts"
	ma.ability_name = "Martial Arts"
	ma.description = "Passive: Unarmed strikes use DEX + 1d6. After a main-action unarmed strike, make a free bonus-action unarmed strike. Die scales at levels 5/11/17."
	ma.icon_path = "res://sprites/items/Misc/KeyIron.png"
	ma.uses_remaining = 0
	ma.uses_max = 0
	add_ability(ma)
	recalculate_stats()
	equipment_changed.emit()

func _find_ability_by_id(id: String) -> Ability:
	for slot in player_ability_bar:
		if slot != null and (slot as Ability).ability_id == id:
			return slot as Ability
	return null

func add_ability(ability: Ability) -> bool:
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
	ability_bar_changed.emit()

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
			# Tier 1 points: immediately available
			talent_points_available += 1
			talent_points_changed.emit(talent_points_available)
		elif lv >= 7 and lv <= 12:
			# Tier 2 points: queued until Necromancer killed, then released by unlock_tier2()
			if tier2_unlocked:
				talent_points_available += 1
				talent_points_changed.emit(talent_points_available)
			else:
				_pending_tier2_points += 1
				combat_message.emit("[color=gray]Tier 2 talent point held — defeat the Necromancer to unlock Berserker.[/color]")
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
		if (lv >= 1 and lv <= 5) or (tier2_unlocked and lv >= 7 and lv <= 12):
			lv_str = " +1 talent point."
		elif lv >= 7 and lv <= 12:
			lv_str = " (Tier 2 point pending — defeat the Necromancer)"
		var level_msg: String = "[color=yellow]Level up! You are now level %d. (+%d max HP.%s)[/color]" % [player_stats.character_level, hp_gained, lv_str]
		combat_message.emit(level_msg)
		short_rest_changed.emit()
		_apply_monk_level_features(player_stats.character_level)
		player_leveled_up.emit(player_stats.character_level)

func unlock_tier2() -> void:
	if tier2_unlocked:
		return
	tier2_unlocked = true
	_setup_barbarian_tier2_talents()
	var pts: int = _pending_tier2_points
	_pending_tier2_points = 0
	talent_points_available += pts
	talent_points_changed.emit(talent_points_available)
	combat_message.emit("[color=gold]Berserker Subclass unlocked! %d Tier 2 talent point(s) available.[/color]" % pts)
	if talent_points_available > 0:
		player_leveled_up.emit(player_stats.character_level)


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
			equip(item, "", true)  # intentional equip from bag/quickbar costs 1 turn
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
	var is_physical: bool = damage_type in ["Slashing", "Piercing", "Bludgeoning"]
	var rage_rank: int = get_talent_rank("rage")
	if is_raging and not ignore_rage and rage_rank >= 2 and is_physical:
		var reduction: float = 0.5 if rage_rank >= 3 else 0.25
		final_amount = int(floor(float(amount) * (1.0 - reduction)))
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
	if talent_points_available <= 0:
		return false
	var t: Talent = _find_talent(id)
	if t == null:
		return false
	return get_talent_rank(id) < t.max_rank

func invest_talent(id: String) -> void:
	if not can_invest_talent(id):
		return
	var new_rank: int = get_talent_rank(id) + 1
	talent_investments[id] = new_rank
	if not invincible:
		talent_points_available -= 1
	_apply_talent_rank(id, new_rank)
	talent_invested.emit(id, new_rank)
	talent_points_changed.emit(talent_points_available)

func _apply_talent_rank(id: String, rank: int) -> void:
	match id:
		"rage":
			_sync_ability_uses()
			var rage_ab: Ability = _find_ability_by_id("rage")
			if rage_ab != null:
				rage_ab.description = _build_rage_description()
		"reckless_attack":
			if rank == 1:
				var ra := Ability.new()
				ra.ability_id = "reckless_attack"
				ra.ability_name = "Reckless"
				ra.description = _build_reckless_description(1)
				ra.icon_path = "res://sprites/weapons/weapon_double_axe.png"
				ra.uses_remaining = 0
				ra.uses_max = 0
				add_ability(ra)
			else:
				var ra: Ability = _find_ability_by_id("reckless_attack")
				if ra != null:
					ra.description = _build_reckless_description(rank)
		"rager":
			if rank == 1:
				var rager_ab := Ability.new()
				rager_ab.ability_id = "rager"
				rager_ab.ability_name = "Rager"
				rager_ab.description = _build_rager_description()
				rager_ab.icon_path = "res://sprites/weapons/weapon_double_axe.png"
				rager_ab.uses_remaining = 0
				rager_ab.uses_max = 0
				add_ability(rager_ab)
			else:
				var rager_ab: Ability = _find_ability_by_id("rager")
				if rager_ab != null:
					rager_ab.description = _build_rager_description()
		"frenzy":
			if rank == 1:
				var frenzy_ab := Ability.new()
				frenzy_ab.ability_id = "frenzy"
				frenzy_ab.ability_name = "Frenzy"
				frenzy_ab.description = _build_frenzy_description()
				frenzy_ab.icon_path = "res://sprites/weapons/weapon_double_axe.png"
				frenzy_ab.uses_remaining = 0
				frenzy_ab.uses_max = 0
				add_ability(frenzy_ab)
			else:
				var frenzy_ab: Ability = _find_ability_by_id("frenzy")
				if frenzy_ab != null:
					frenzy_ab.description = _build_frenzy_description()
		"retaliation":
			if rank == 1:
				var ret_ab := Ability.new()
				ret_ab.ability_id = "retaliation"
				ret_ab.ability_name = "Retaliation"
				ret_ab.description = _build_retaliation_description()
				ret_ab.icon_path = "res://sprites/weapons/weapon_double_axe.png"
				ret_ab.uses_remaining = 0
				ret_ab.uses_max = 0
				add_ability(ret_ab)
			else:
				var ret_ab: Ability = _find_ability_by_id("retaliation")
				if ret_ab != null:
					ret_ab.description = _build_retaliation_description()
		"danger_sense":
			if rank == 1:
				var ds := Ability.new()
				ds.ability_id = "danger_sense"
				ds.ability_name = "Danger Sense"
				ds.description = _build_danger_sense_description(1)
				ds.icon_path = "res://sprites/items/Misc/KeyIron.png"
				ds.uses_remaining = 0
				ds.uses_max = 0
				add_ability(ds)
			elif rank == 2:
				var ds: Ability = _find_ability_by_id("danger_sense")
				if ds != null:
					ds.description = _build_danger_sense_description(2)
			elif rank == 3:
				player_stats.strength += 2
				recalculate_stats()
				var ds: Ability = _find_ability_by_id("danger_sense")
				if ds != null:
					ds.description = _build_danger_sense_description(3)
				combat_message.emit("[color=cyan]Danger Sense 3: STR +2 (now [b]%d[/b])![/color]" % player_stats.strength)
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

func _setup_barbarian_talents() -> void:
	_class_talents = []

	var rage_talent := Talent.new()
	rage_talent.talent_id = "rage"
	rage_talent.talent_name = "Rage"
	rage_talent.description = "Upgrade your Rage ability."
	rage_talent.icon_path = "res://sprites/weapons/weapon_double_axe.png"
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
	reckless_talent.icon_path = "res://sprites/weapons/weapon_double_axe.png"
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
	ds_talent.icon_path = "res://sprites/items/Misc/KeyIron.png"
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
	rager_talent.icon_path = "res://sprites/weapons/weapon_double_axe.png"
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
	frenzy_talent.icon_path = "res://sprites/weapons/weapon_double_axe.png"
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
	retaliation_talent.icon_path = "res://sprites/weapons/weapon_double_axe.png"
	retaliation_talent.tier = 2
	retaliation_talent.class_id = Stats.CharacterClass.BARBARIAN
	retaliation_talent.max_rank = 3
	retaliation_talent.ranks = [
		{"description": "When hit by a melee attack: deal %d damage back (rage bonus only)." % player_stats.rage_bonus_damage},
		{"description": "Deal weapon damage back instead (no rage bonus at this rank — intentional)."},
		{"description": "Deal weapon damage + rage bonus (%d) + STR modifier back." % player_stats.rage_bonus_damage},
	]
	_class_talents.append(retaliation_talent)
