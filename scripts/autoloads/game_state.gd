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
signal race_chosen(race: Stats.CharacterRace)
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
signal talent_invested(talent_id: String, new_rank: int)
signal talent_points_changed(available: int)
# Fired when the Tier 2 gating boss dies and the player must pick a subclass.
# hud.gd listens and spawns scripts/ui/subclass_select.gd — GameState never instantiates UI.
signal subclass_choice_required
# Fired on every boss kill (player.gd._finish_kill() and the resolve_push() chasm path),
# carrying the BOSS_POOL "boss_id". GameState listens to its own signal (_on_boss_defeated)
# to run the Tier 2 unlock gate; future systems can also connect.
signal boss_defeated(boss_id: String)
signal known_masteries_changed
signal gold_changed(new_amount: int)
signal long_rest_completed()
# Bruiser R3: fired instead of player_died when the revive triggers. player.gd connects this to
# _end_rage() since Rage state lives there, not on GameState.
signal force_rage_end()

const QUICKBAR_SIZE: int = 9
const ABILITY_BAR_SIZE: int = 9
const INVENTORY_SIZE: int = 24

# Wild Heart Tier 2 companion stats by rank (data-driven, no hardcoded logic)
const WILD_HEART_COMPANION_STATS: Dictionary = {
	1: {"animal": "Squirrel", "ac": 12, "hp": 10, "die_count": 1, "die_sides": 6},
	2: {"animal": "Boar",     "ac": 14, "hp": 20, "die_count": 2, "die_sides": 6},
	3: {"animal": "Bear",     "ac": 16, "hp": 30, "die_count": 3, "die_sides": 6},
}

# talent_id → icons/classes/barbarian/<path>_<rank>.png stem. Rank-gradient art (1-3) —
# World Tree only, see icons/classes/barbarian/t2/world_tree/.
const TALENT_ICON_FOLDER: Dictionary = {
	"ironwood_bark": "t2/world_tree/ironwood_bark",
	"grip_of_the_forest": "t2/world_tree/grip_of_the_forest",
	"branching_strike": "t2/world_tree/branching_strike",
}

# talent_id/ability_id → icons/classes/barbarian/<path>.png. Single flat icon (no rank
# gradient) — everything except World Tree (TALENT_ICON_FOLDER above) and the Wild Heart
# form-driven abilities (WILD_HEART_*_ICON below, keyed by current form/rank instead of a
# fixed file).
const TALENT_ICON_FLAT: Dictionary = {
	"rage": "t0/rage",
	"psycho": "t1/psycho_killer",
	"bruiser": "t1/bruiser",
	"battlefield_expert": "t1/battlefield_expert",
	# Berserker
	"frenzy": "t2/berserker/frenzy",
	"sadist_monster": "t2/berserker/sadist",
	"masochist_monster": "t2/berserker/masochist",
	"frenzied_killer": "t2/berserker/blood-rush",
	# Scarred Warrior
	"limit_break": "t2/scarred_warrior/limit_break",
	"born_in_blood": "t2/scarred_warrior/blood_born",
	"enough_is_enough": "t2/scarred_warrior/enough_is_enough",
	"bloodied_regen": "t2/scarred_warrior/blood_flow",
	# Wild Heart (Enhanced Forms only — Animal Form/Natural Sleeper/Wild Companion are
	# form-driven, see WILD_HEART_*_ICON below)
	"enhanced_forms": "t2/wild_heart/animal_instincts",
	# Zealot
	"zealot_strike": "t2/zealot/zealous_strike",
	"judgement_day": "t2/zealot/judgement_day",
	"overheal_shield": "t2/zealot/overheal",
	"never_back_down": "t2/zealot/never_back_down",
	# Barbarian passive, no talent — see _give_barbarian_starting_items()
	"unarmored_defense": "t0/unarmored_defence",
}

# Animal Form's icon follows the currently active form (Bear/Eagle/Wolf) instead of rank.
const WILD_HEART_FORM_ICON: Dictionary = {
	"Bear": "res://icons/classes/barbarian/t2/wild_heart/wild_form_bear.png",
	"Eagle": "res://icons/classes/barbarian/t2/wild_heart/wild_form_eagle.png",
	"Wolf": "res://icons/classes/barbarian/t2/wild_heart/wild_form_wolf.png",
}

# Natural Sleeper's icon follows the previewed/active form (Owl/Panther/Salmon) instead of rank.
const WILD_HEART_SLEEPER_ICON: Dictionary = {
	"Owl": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_owl.png",
	"Panther": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_panther.png",
	"Salmon": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_salmon.png",
}

# Wild Companion's icon follows the rank's summoned animal — matches WILD_HEART_COMPANION_STATS.
const WILD_HEART_COMPANION_ICON: Dictionary = {
	1: "res://icons/classes/barbarian/t2/wild_heart/companion_squirrel.png",
	2: "res://icons/classes/barbarian/t2/wild_heart/companion_boar.png",
	3: "res://icons/classes/barbarian/t2/wild_heart/companion_bear.png",
}

## Returns the icon for a talent/ability; "" if unmapped. Most talents resolve to a single flat
## icon (rank ignored) via TALENT_ICON_FLAT; World Tree talents still gradient 1-3 via
## TALENT_ICON_FOLDER; Wild Heart's form-driven abilities (Animal Form/Natural Sleeper/Wild
## Companion) read current form/rank state directly instead of a fixed mapping.
func talent_icon_path(id: String, rank: int) -> String:
	match id:
		"animal_form":
			return WILD_HEART_FORM_ICON.get(natural_rager_form, WILD_HEART_FORM_ICON["Bear"])
		"expanded_forms":
			var preview: String = natural_sleeper_form if natural_sleeper_form != "" else "Owl"
			return WILD_HEART_SLEEPER_ICON.get(preview, WILD_HEART_SLEEPER_ICON["Owl"])
		"wild_companion":
			return WILD_HEART_COMPANION_ICON.get(clampi(rank, 1, 3), WILD_HEART_COMPANION_ICON[1])
	if TALENT_ICON_FLAT.has(id):
		return "res://icons/classes/barbarian/%s.png" % TALENT_ICON_FLAT[id]
	if TALENT_ICON_FOLDER.has(id):
		var r: int = clampi(rank, 1, 3)
		return "res://icons/classes/barbarian/%s_%d.png" % [TALENT_ICON_FOLDER[id], r]
	return ""

# Long rest: an explicit, Alt-menu-triggered rest (NOT floor descent — see long_rest()).
# Requires sacrificing FOOD items worth LONG_REST_FOOD_COST combined food_value, and takes
# LONG_REST_TURNS turns to complete (interruptible by enemies, same mechanism as short rest).
const LONG_REST_FOOD_COST: int = 100
const LONG_REST_TURNS: int = 20
const SHORT_REST_TURNS: int = 5

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
var gold: int = 0   # the wallet — plain int counter, earned via add_gold(), spent via spend_gold()
var short_rest_open: bool = false
var talent_picker_open: bool = false
var mastery_picker_open: bool = false
var subclass_picker_open: bool = false  # blocks ALL player input while the subclass-select overlay is visible
var race_picker_open: bool = false  # blocks ALL player input while the race-select overlay is visible (scripts/ui/race_select.gd)
var point_buy_open: bool = false  # blocks ALL player input while the point-buy overlay is visible (scripts/ui/point_buy_select.gd, Custom path only)

# Talent system — points earned per level, invested per talent.
# Points are tier-locked pools: talent_points[tier] holds that tier's unspent points
# (levels 1-6 → tier 1, 7-12 → tier 2, 13-17 → tier 3, 18-20 → tier 4; see TIER_LEVEL_RANGES).
# Points accumulate even while a tier is locked (Tier 2 points pend until the gating boss dies).
# talent_points_available is a computed sum used for backward-compat (signals, auto-close logic).
var talent_points: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}   # tier → unspent points
var talent_points_available: int:
	get:
		var total: int = 0
		for t: int in talent_points:
			total += talent_points[t]
		return total
# Level → talent-point tier schedule. Levels outside every range (21+) grant nothing.
const TIER_LEVEL_RANGES: Dictionary = {1: [1, 6], 2: [7, 12], 3: [13, 17], 4: [18, 20]}
var talent_investments: Dictionary = {}   # talent_id → current_rank (int)
var _class_talents: Array[Talent] = []    # all talents for current class, populated on class select
# Tier 2 unlocks when the gating boss (TIER2_GATING_BOSS_ID, the floor-5 boss) is defeated —
# NOT at level 7. Levels 7-12 still fill talent_points[2], pending until the kill. On the kill,
# classes with subclasses (Barbarian) get the one-time subclass choice (subclass_choice_required
# → scripts/ui/subclass_select.gd → choose_subclass() → unlock_tier2()); other classes unlock
# directly. See _on_boss_defeated().
var tier2_unlocked: bool = false
const TIER2_GATING_BOSS_ID: String = "big_demon"
# Tier 3 (multiclass) selection stub — no Tier 3 content yet; -1 = no multiclass chosen.
# tier_unlocked(3) reads it so the accessor shape is final before Tier 3 lands.
var tier3_selected_class: int = -1
var subclass_chosen: bool = false  # true once the player has made their one-time subclass choice
const TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]
var active_tier2_subclass: String = "Berserker"
# Each subclass's free, rank-independent activation ability (granted on subclass selection,
# not gated by any talent investment) — see the *.md specs in /markdowns/. World Tree has no
# such base ability; its three Tier 2 talents are all still individually rank-1-gated.
const TIER2_BASE_ABILITY_ID: Dictionary = {
	"Berserker": "frenzy",
	"Scarred Warrior": "limit_break",
	"Wild Heart": "animal_form",
	"Zealot": "zealot_strike",
}
var short_rest_active: bool = false
var short_rest_turns_remaining: int = 0
var short_rest_pending_heal: int = 0
# Set true when the in-progress short_rest_active countdown is actually a long rest (Alt menu's
# Long Rest tab). Consumed on completion by player.gd's _on_turn_started(), which calls
# long_rest() instead of applying the short-rest heal. See long_rest() below.
var long_rest_pending: bool = false

# ── Wild Heart Tier 2 state ───────────────────────────────────────────────────
# Natural Rager: toggle between Bear/Eagle/Wolf; effects only apply while is_raging.
var natural_rager_form: String = "Bear"
# Natural Sleeper: toggle between Owl/Panther/Salmon; activates/locks in on a completed long rest.
# natural_sleeper_form = chosen form (preview); active_sleeper_form = locked in at last long rest.
var natural_sleeper_form: String = ""   # "" = no form chosen; locks in on long_rest()
var active_sleeper_form: String = ""    # locks in on long_rest() only
var wild_heart_sleeper_active: bool = false
# Eagle R3: no-op pending future Opportunity Attack system — do NOT remove this flag.
var player_evades_opportunity_attacks: bool = false
# Wild Heart Enhanced Forms R1: +1 while in Eagle form, threaded into DungeonFloor's FOV radius.
var fov_radius_bonus: int = 0
# Reference to living companion node (null when no companion). Set by player.gd.
var player_companion: Variant = null
# Companion state loaded from a save ({alive: bool, current_hp: int}, {} = none) —
# populated by from_dict(); consumed by the Continue-flow floor load (session 3c),
# which rebuilds the node from WILD_HEART_COMPANION_STATS[rank] (doc §4.4).
var pending_companion_restore: Dictionary = {}
# AC bonus from Natural Sleeper R3 terrain — added in recalculate_stats().
var terrain_ac_bonus: int = 0
# Psycho R1/R2 and Battlefield Expert R1's pending-Advantage windows — live here (not on
# PlayerBaseTalents) so the HUD status tray can display them while only reading GameState, per
# scripts/ui/CLAUDE.md's "HUD only reads GameState" convention. See scripts/entities/CLAUDE.md's
# Barbarian Tier 1 talents section.
var psycho_adv_pending: bool = false
var battlefield_adv_pending: bool = false

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
	boss_defeated.connect(_on_boss_defeated)

func start_new_run() -> void:
	run_seed = randi()
	Rng.reseed(run_seed)  # gameplay RNG stream — same seed → same run (rng.gd)
	current_floor = 1
	is_game_over = false
	inventory_open = false
	class_selected = false
	invincible = false
	noclip = false
	short_rest_open = false
	talent_picker_open = false
	mastery_picker_open = false
	subclass_picker_open = false
	race_picker_open = false
	point_buy_open = false
	talent_points = {1: 0, 2: 0, 3: 0, 4: 0}
	tier3_selected_class = -1
	talent_investments = {}
	_class_talents = []
	tier2_unlocked = false
	subclass_chosen = false
	active_tier2_subclass = "Berserker"
	zealot_divine_fury_type = "Radiant"
	zealot_blessed_charges = 0
	zealot_blessed_heal_queued = false
	zealot_zp_charges = 0
	hit_dice = 1
	short_rests_remaining = 2
	max_short_rests = 2
	gold = 0
	long_rest_pending = false
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
	pending_companion_restore = {}
	terrain_ac_bonus = 0
	_give_starting_items()

func _give_starting_items() -> void:
	var ration := Item.new()
	ration.item_name = "Ration"
	ration.item_type = Item.Type.FOOD
	ration.food_value = 50
	ration.icon_path = "res://sprites/items/Food/MeatCooked.png"
	ration.description = "Required for a long rest."
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

# One-time, permanent race choice — called by race_select.gd's confirm button, fired between
# class selection and the Mastery Picker. Mirrors choose_subclass()'s shape: sets the choice on
# Stats, re-derives race-defined state via apply_race_defaults(), then any starting gear.
func choose_race(race: Stats.CharacterRace, variant: int = 0, prof_ability: int = -1) -> void:
	player_stats.character_race = race
	player_stats.race_variant = variant
	player_stats.race_prof_ability = prof_ability
	player_stats.apply_race_defaults()
	give_race_starting_items()
	recalculate_stats()
	# apply_race_defaults() can change max_hp (Dwarf's +1) — re-emit so the HUD's HP bar picks
	# it up. Every onboarding path emits player_hp_changed with the PRE-race max_hp before this
	# function runs (character_select.gd's premade path, or point_buy_select.gd's confirm), and
	# nothing else re-syncs it afterward, so without this the bar silently under-reports Dwarf's
	# bonus HP even though player_stats.max_hp itself is correct.
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	race_chosen.emit(race)

# Idempotency-guard pattern mirrors give_class_starting_items() — safe to call again on save
# replay. No race currently grants starting gear/abilities (Elf sub-race spells and the
# Dragonborn breath weapon are deferred — see docs/architecture/race-selection-design.md §8).
func give_race_starting_items() -> void:
	pass

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
	rage.icon_path = talent_icon_path("rage", 3)
	rage.uses_remaining = player_stats.rage_uses_remaining
	rage.uses_max = player_stats.rage_uses_max
	add_ability(rage)

	# Unarmored Defense passive (AC = 10 + DEX + CON while unarmored — see Stats.recalc_ac()).
	# No talent rank, no activation — ability-bar entry exists purely to surface the icon/tooltip.
	var ud := Ability.new()
	ud.ability_id = "unarmored_defense"
	ud.ability_name = "Unarmored Defense"
	ud.description = "Passive: AC = 10 + DEX + CON while wearing no armor."
	ud.icon_path = talent_icon_path("unarmored_defense", 1)
	ud.uses_remaining = 0
	ud.uses_max = 0
	ud.is_passive = true
	add_ability(ud)

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

## Grants a subclass's free, rank-independent Tier 2 activation ability (Frenzy, Limit Break,
## Animal Form, Zealot Strike) directly at subclass selection — NOT gated by any talent rank.
## No-op if already present (idempotent — safe to call from every _setup_X_tier2_talents()).
func _grant_tier2_base_ability(id: String, ability_name: String, description: String) -> void:
	if _find_ability_by_id(id) != null:
		return
	var ab := Ability.new()
	ab.ability_id = id
	ab.ability_name = ability_name
	ab.description = description
	ab.icon_path = talent_icon_path(id, 1)
	ab.uses_remaining = 0
	ab.uses_max = 0
	add_ability(ab)

# ── Gold economy (design: docs/architecture/special-rooms-economy-design.md §2) ──────

func add_gold(amount: int) -> void:
	if amount <= 0:
		return
	gold += amount
	gold_changed.emit(gold)

# Returns true if the purchase went through. While invincible, spending always succeeds
# WITHOUT decrementing (project invariant: invincible skips all consumption).
func spend_gold(amount: int) -> bool:
	if invincible:
		gold_changed.emit(gold)  # re-emit so UI refreshes anyway
		return true
	if amount > gold:
		return false
	gold -= amount
	gold_changed.emit(gold)
	return true

func advance_floor() -> void:
	current_floor += 1
	# Floor descent is no longer a rest — see long_rest() for every long-rest-gated resource.
	# Only floor bookkeeping and terrain reset happen here.
	terrain_ac_bonus = 0  # reset terrain AC; player.gd will reapply on next move
	bruiser_revive_used_this_floor = false
	short_rest_changed.emit()
	floor_changed.emit(current_floor)
	if current_floor > 10:
		player_won.emit()

# ── Rations / long rest ───────────────────────────────────────────────────────

# Sums food_value × quantity across quickbar + bag for every FOOD item.
func total_food_value() -> int:
	var total: int = 0
	for it: Item in player_quickbar:
		if it != null and it.item_type == Item.Type.FOOD:
			total += it.food_value * it.quantity
	for it: Item in player_inventory:
		if it != null and it.item_type == Item.Type.FOOD:
			total += it.food_value * it.quantity
	return total

func can_long_rest() -> bool:
	if invincible:
		return true
	return total_food_value() >= LONG_REST_FOOD_COST

# Removes FOOD items worth `amount` combined food_value, cheapest-value items first so a
# handful of low-value scraps get spent before a stack of Rations. No-op while invincible
# (project invariant: invincible skips all consumption).
func _consume_food_value(amount: int) -> void:
	if invincible or amount <= 0:
		return
	var remaining: int = amount
	var candidates: Array[Item] = []
	for it: Item in player_quickbar:
		if it != null and it.item_type == Item.Type.FOOD and it.food_value > 0:
			candidates.append(it)
	for it: Item in player_inventory:
		if it != null and it.item_type == Item.Type.FOOD and it.food_value > 0:
			candidates.append(it)
	candidates.sort_custom(func(a: Item, b: Item) -> bool: return a.food_value < b.food_value)
	for it: Item in candidates:
		if remaining <= 0:
			break
		var qty: int = it.quantity
		for _i: int in qty:
			if remaining <= 0:
				break
			consume_one(it)
			remaining -= it.food_value

# The single chokepoint for every "per long rest" resource. Triggered explicitly by the player
# via the Alt-menu Long Rest tab (see short_rest_panel.gd) — NEVER by advance_floor(). Any new
# long-rest-gated resource must be refilled here and nowhere else.
# Elf: Trance halves the long rest's turn count (long-rest-only, per race-selection-design.md §3.5).
func long_rest_turns_needed() -> int:
	if player_stats.character_race == Stats.CharacterRace.ELF:
		return int(LONG_REST_TURNS * 0.5)
	return LONG_REST_TURNS

func long_rest() -> void:
	player_stats.current_hp = player_stats.max_hp
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	player_stats.poison_turns = 0
	player_stats.burning_turns = 0
	player_stats.bleeding_turns = 0
	player_stats.slowed_turns = 0
	player_status_changed.emit()
	player_stats.rage_uses_remaining = player_stats.rage_uses_max
	hit_dice = max_hit_dice()
	short_rests_remaining = max_short_rests
	berserker_frenzy_used = false
	berserker_turns_since_frenzy = 0
	scarred_warrior_limit_break_used = false
	player_stats.relentless_endurance_used = false
	player_stats.heroic_inspiration_available = true
	# Natural Sleeper activates/locks in on long rest only (not short rest, not floor descent).
	wild_heart_sleeper_active = get_talent_rank("expanded_forms") >= 1
	active_sleeper_form = natural_sleeper_form
	if wild_heart_sleeper_active:
		if active_sleeper_form != "":
			game_log("[color=cyan]Natural Sleeper: you wake — %s Form is active.[/color]" % active_sleeper_form)
		else:
			game_log("[color=gray]Natural Sleeper: no form chosen — press the ability to select one.[/color]")
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	_sync_ability_uses()
	_consume_food_value(LONG_REST_FOOD_COST)
	short_rest_changed.emit()
	AudioManager.play("rest")
	game_log("[color=cyan]You finish your long rest, fully healed and refreshed.[/color]")
	long_rest_completed.emit()

# Keeps ability resource uses_remaining in sync with player_stats after a long rest.
func _sync_ability_uses() -> void:
	for slot in player_ability_bar:
		if slot == null:
			continue
		var ab := slot as Ability
		if ab.ability_id == "rage":
			ab.uses_remaining = player_stats.rage_uses_remaining
			ab.uses_max = player_stats.rage_uses_max
		elif ab.ability_id == "wild_companion":
			ab.uses_remaining = 1  # always restore on long rest
	ability_bar_changed.emit()

## Whether an ability-bar entry can currently be activated — beyond the generic uses_remaining
## pool, several free base-abilities (uses_max == 0, i.e. always "has_uses") are additionally
## gated by external boolean state (a requirement to be raging, a once-per-rest flag, a spent
## Hit Die). Used by hud.gd to grey out slots that LOOK available (infinite uses) but currently
## aren't actionable — never call this to block the actual activation logic in player.gd, each
## ability's own activation function is still the source of truth for its own gate.
func is_ability_usable(ab: Ability) -> bool:
	if not ab.has_uses():
		return false
	match ab.ability_id:
		"frenzy":
			return is_raging and not berserker_frenzy_used
		"limit_break":
			return not scarred_warrior_limit_break_used
		"zealot_strike":
			return hit_dice > 0
		"grip_of_the_forest":
			return is_raging
	return true

# Triggered on short rest completion. Heals companion (if alive) AND restores One with Nature charge.
# Natural Sleeper's form lock does NOT happen here — long rest only (see long_rest()).
func _on_short_rest_completed() -> void:
	if berserker_frenzy_used and _find_ability_by_id("frenzy") != null:
		game_log("[color=lime]Frenzy: use refreshed.[/color]")
	berserker_frenzy_used = false
	berserker_turns_since_frenzy = 0
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	var owtn: Ability = _find_ability_by_id("wild_companion")
	if owtn != null:
		owtn.uses_remaining = 1
		ability_bar_changed.emit()
		game_log("[color=lime]One with Nature: companion charge refreshed.[/color]")

## Never Back Down (Zealot): +1/+2/+4 max Hit Dice by rank (non-cumulative — matches every other
## Barbarian talent's "higher rank replaces, doesn't stack with" convention).
func max_hit_dice() -> int:
	var rank: int = get_talent_rank("never_back_down")
	var bonus: int = [0, 1, 2, 4][mini(rank, 3)]
	return player_stats.character_level + bonus

func hit_die_sides() -> int:
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN: return 12
		Stats.CharacterClass.RANGER:    return 10
		Stats.CharacterClass.MONK:      return 8
		Stats.CharacterClass.WIZARD:    return 6
		_:                              return 8

func check_player_death() -> void:
	if player_stats.is_dead() and not is_game_over and not invincible:
		if get_talent_rank("bruiser") >= 3 and is_raging and not bruiser_revive_used_this_floor:
			bruiser_revive_used_this_floor = true
			player_stats.current_hp = 1
			player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
			force_rage_end.emit()
			game_log("[color=gold]Bruiser: you refuse to fall! (1 HP, Rage ends)[/color]")
			return
		if player_stats.character_race == Stats.CharacterRace.ORC and not player_stats.relentless_endurance_used:
			player_stats.relentless_endurance_used = true
			player_stats.current_hp = 1
			player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
			game_log("[color=orange]Relentless Endurance holds you at 1 HP![/color]")
			return
		is_game_over = true
		AudioManager.play("player_die")
		player_died.emit()

func heal(amount: int) -> int:
	var final_amount: int = amount
	# Bruiser R1: +1d4 to any incoming heal while Bloodied. Returned so callers can name it as
	# its own bonus source in the heal tooltip, instead of it silently vanishing into the total.
	var bruiser_bonus: int = 0
	if get_talent_rank("bruiser") >= 1 and player_stats.is_bloodied():
		bruiser_bonus = Rng.roll(4)
		final_amount += bruiser_bonus
	player_stats.current_hp = mini(player_stats.current_hp + final_amount, player_stats.max_hp)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	if get_talent_rank("bruiser") >= 2:
		recalculate_stats()
	return bruiser_bonus

func gain_exp(amount: int) -> void:
	var old_max_hp: int = player_stats.max_hp
	var old_rage_max: int = player_stats.rage_uses_max
	var old_max_hit_dice: int = max_hit_dice()
	var leveled_up := player_stats.gain_exp(amount)
	player_exp_changed.emit(player_stats.experience, player_stats.exp_to_next(), player_stats.character_level)
	if leveled_up:
		player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
		var hp_gained: int = player_stats.max_hp - old_max_hp
		var lv: int = player_stats.character_level
		var point_tier: int = tier_for_level(lv)
		if point_tier > 0:
			# Points accumulate into their tier pool even while the tier is locked —
			# Tier 2 points earned at levels 7-12 sit pending until the gating boss dies
			# (see _on_boss_defeated(); Tier 2 is NOT auto-unlocked by leveling).
			talent_points[point_tier] += 1
			talent_points_changed.emit(talent_points_available)
		# Levels outside TIER_LEVEL_RANGES (21+ past tier 4): no talent points (gap between tiers)
		# Max hit dice grows by 1 per level (character_level term of max_hit_dice()) — grant the
		# extra die immediately to CURRENT hit_dice too (not just the cap), so it's usable in a
		# short rest right away instead of only after the next long rest.
		var new_max_hit_dice: int = max_hit_dice()
		if new_max_hit_dice > old_max_hit_dice:
			hit_dice = mini(hit_dice + (new_max_hit_dice - old_max_hit_dice), new_max_hit_dice)
		# Rage uses scale by level — grant the extra use immediately on the triggering level-up.
		if player_stats.character_class == Stats.CharacterClass.BARBARIAN:
			var new_rage_max: int = player_stats.rage_uses_max
			if new_rage_max > old_rage_max:
				player_stats.rage_uses_remaining = mini(
					player_stats.rage_uses_remaining + (new_rage_max - old_rage_max),
					new_rage_max)
				_sync_ability_uses()
		var lv_str: String = ""
		if point_tier > 0:
			lv_str = " +1 talent point."
		# A single gain_exp() call can cross more than one level threshold on a large XP grant —
		# the breakdown's per-component values are per-level (CON mod / Dwarf bonus don't change
		# level to level), so scale by how many levels this call actually applied.
		var b: Dictionary = player_stats.hp_per_level_breakdown()
		var levels_gained: int = 1 if b["total"] <= 0 else roundi(float(hp_gained) / float(b["total"]))
		var hplvl_meta: String = "hplvl:die=%d,avg=%d,con=%d,dwarf=%d,n=%d,total=%d" % [
			b["die_sides"], b["avg"], b["con"], b["dwarf"], levels_gained, hp_gained]
		var level_msg: String = "[color=yellow]Level up! You are now level %d. ([url=%s]+%d max HP[/url].%s)[/color]" % [player_stats.character_level, hplvl_meta, hp_gained, lv_str]
		combat_message.emit(level_msg)
		short_rest_changed.emit()
		_apply_monk_level_features(player_stats.character_level)
		AudioManager.play("level_up")
		player_leveled_up.emit(player_stats.character_level)

## Which tier's pool a level-up at `lv` feeds. 0 = no talent point (level 21+).
func tier_for_level(lv: int) -> int:
	for tier: int in TIER_LEVEL_RANGES:
		var r: Array = TIER_LEVEL_RANGES[tier]
		if lv >= r[0] and lv <= r[1]:
			return tier
	return 0

## Whether talents of `tier` can currently be invested in. Points accumulate while locked.
func tier_unlocked(tier: int) -> bool:
	match tier:
		1: return true
		2: return tier2_unlocked
		3: return tier3_selected_class != -1 and player_stats.character_level >= 13
		4: return player_stats.character_level >= 18
		_: return false

# The Tier 2 gate. Fires on every boss kill; only TIER2_GATING_BOSS_ID matters. Classes with
# subclasses (Barbarian) get the one-time subclass overlay; other classes unlock directly.
# God-Mode debug arrows / debug panel remain the escape hatch if Jump-to-Floor skips floor 5.
func _on_boss_defeated(boss_id: String) -> void:
	if boss_id != TIER2_GATING_BOSS_ID or tier2_unlocked:
		return
	if player_stats.character_class == Stats.CharacterClass.BARBARIAN and not subclass_chosen:
		subclass_choice_required.emit()
	else:
		unlock_tier2()

func unlock_tier2() -> void:
	if tier2_unlocked:
		return
	tier2_unlocked = true
	_setup_tier2_for_active_subclass()
	game_log("[color=gold]%s Tier 2 talents unlocked![/color]" % active_tier2_subclass)

# One-time, permanent player subclass choice — called by subclass_select.gd's confirm button.
# Reuses the same setup path as unlock_tier2()/debug_switch_subclass(); after this only the
# God-Mode debug arrows in talent_picker.gd can change the subclass.
func choose_subclass(subclass_name: String) -> void:
	if subclass_chosen or not TIER2_SUBCLASSES.has(subclass_name):
		return
	active_tier2_subclass = subclass_name
	subclass_chosen = true
	unlock_tier2()

func _setup_tier2_for_active_subclass() -> void:
	match active_tier2_subclass:
		"Berserker": _setup_barbarian_tier2_talents()
		"Scarred Warrior": _setup_scarred_warrior_tier2_talents()
		"Wild Heart": _setup_wild_heart_tier2_talents()
		"World Tree": _setup_world_tree_tier2_talents()
		"Zealot": _setup_zealot_tier2_talents()
		_: pass

func debug_switch_subclass(direction: int) -> void:
	var old_base_ability_id: String = String(TIER2_BASE_ABILITY_ID.get(active_tier2_subclass, ""))
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
	if old_base_ability_id != "":
		tier2_ids.append(old_base_ability_id)
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

# Equip/unequip/re-equip is always a free action — never costs a turn.
func equip(item: Item, slot_name: String = "") -> void:
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

	var to_equip: Item = item
	if _should_split_for_equip(item):
		to_equip = _split_one_unit(item)
	else:
		_remove_from_bags(item)

	var prev: Item = equipment[slot_name] as Item
	equipment[slot_name] = to_equip
	if prev != null:
		_add_to_bags_silent(prev)
	# Equipping a two-handed weapon into the main hand can't coexist with an off-hand
	# weapon — kick whatever's in "hand2" back to the bag automatically.
	if slot_name == "melee" and to_equip.is_two_handed:
		_auto_unequip_offhand()
	recalculate_stats()
	combat_message.emit("[color=cyan]Equipped [b]%s[/b].[/color]" % to_equip.item_name)
	equipment_changed.emit()
	inventory_changed.emit()

# Silently returns whatever's in the off-hand slot to the bag (no log line of its own —
# called as a side effect of equipping a two-handed main-hand weapon, see equip()/move_item()).
func _auto_unequip_offhand() -> void:
	var hand2: Item = equipment.get("hand2") as Item
	if hand2 == null:
		return
	equipment["hand2"] = null
	_add_to_bags_silent(hand2)

# A stacked thrown weapon (quantity > 1, units may carry different durability — see add_item())
# only ever equips a single unit: split one off instead of moving the whole stack into a slot,
# so the rest keep sitting in the bag with their own durability untouched. Shared by equip(),
# move_item()'s drag-to-equipment-slot path, and PlayerThrowTool._throw_weapon().
func _should_split_for_equip(item: Item) -> bool:
	return item.quantity > 1 and item.item_type == Item.Type.WEAPON and item.uses_max > 0

# Splits the most-damaged unit (lowest uses_remaining — the one "on top" of the stack) off into
# its own single-quantity Item, leaving the rest of the stack behind with their own durability.
func _split_one_unit(item: Item) -> Item:
	var unit: Item = item.duplicate()
	unit.quantity = 1
	unit.stack_uses = []
	if item.uses_max > 0:
		var stack: Array = item.get_stack_uses()
		stack.sort()
		var taken: int = int(stack[0])
		stack.remove_at(0)
		unit.uses_remaining = taken
		var remaining: Array[int] = []
		for v: Variant in stack:
			remaining.append(int(v))
		if remaining.size() > 1:
			item.stack_uses = remaining
		else:
			var empty: Array[int] = []
			item.stack_uses = empty
		if not remaining.is_empty():
			item.uses_remaining = remaining[0]
	item.quantity -= 1
	return unit

func unequip(slot_name: String) -> void:
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
	s.armor_class += masochist_ac_bonus
	# Bruiser R2: +1 AC while Bloodied.
	if get_talent_rank("bruiser") >= 2 and s.is_bloodied():
		s.armor_class += 1

func move_item(src: String, src_idx: int, src_slot: String,
			   dest: String, dest_idx: int, dest_slot: String) -> void:
	if src == dest and src_idx == dest_idx and src_slot == dest_slot:
		return
	var src_item: Item  = _get_slot_item(src, src_idx, src_slot)
	var dest_item: Item = _get_slot_item(dest, dest_idx, dest_slot)
	# Dragging a stacked weapon (e.g. Handaxe/Dagger, quantity > 1) into an equipment slot only
	# equips a single unit — the rest of the stack stays put instead of the whole pile moving
	# into the slot. Mirrors equip()'s splitting rule (see _should_split_for_equip()).
	if dest == "equipment" and src_item != null and _should_split_for_equip(src_item):
		_set_slot_item(dest, dest_idx, dest_slot, _split_one_unit(src_item))
		if dest_item != null:
			_add_to_bags_silent(dest_item)
	else:
		_set_slot_item(src, src_idx, src_slot, dest_item)
		_set_slot_item(dest, dest_idx, dest_slot, src_item)
	# Dragging a two-handed weapon into the main hand can't coexist with an off-hand
	# weapon — kick whatever's in "hand2" back to the bag automatically (mirrors equip()).
	if dest == "equipment" and dest_slot == "melee" and src_item != null and src_item.is_two_handed:
		_auto_unequip_offhand()
	recalculate_stats()
	equipment_changed.emit()
	inventory_changed.emit()

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
	# Weapons with individual durability (uses_max > 0, e.g. thrown weapons) stack with any
	# existing same-named pile regardless of durability — each unit's own uses_remaining is kept
	# via Item.stack_uses (see _merge_into_stack()), so a mixed-durability stack still throws/
	# equips its most-damaged unit first (equip()/PlayerThrowTool._throw_weapon() splitting).
	var is_durability_weapon: bool = item.item_type == Item.Type.WEAPON and item.uses_max > 0
	# Try stacking in quickbar, then bag
	for i: int in QUICKBAR_SIZE:
		var ex: Item = player_quickbar[i] as Item
		if ex != null and ex.item_name == item.item_name and (not is_durability_weapon or ex.uses_max == item.uses_max):
			_merge_into_stack(ex, item)
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		var ex: Item = player_inventory[i] as Item
		if ex != null and ex.item_name == item.item_name and (not is_durability_weapon or ex.uses_max == item.uses_max):
			_merge_into_stack(ex, item)
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

# Merges `incoming` into existing stack `ex`. Durability weapons keep every unit's own
# uses_remaining (Item.stack_uses, sorted ascending — index 0/most-damaged mirrors into
# ex.uses_remaining so it's always the one shown/thrown/equipped first). Plain items just sum.
func _merge_into_stack(ex: Item, incoming: Item) -> void:
	if ex.item_type == Item.Type.WEAPON and ex.uses_max > 0:
		var merged: Array = ex.get_stack_uses() + incoming.get_stack_uses()
		merged.sort()
		var typed: Array[int] = []
		for v: Variant in merged:
			typed.append(int(v))
		ex.stack_uses = typed
		ex.quantity = typed.size()
		ex.uses_remaining = typed[0]
	else:
		ex.quantity += incoming.quantity

func use_item(item: Item) -> void:
	match item.item_type:
		Item.Type.POTION:
			AudioManager.play("drink_potion")
			if item.heal_dice_count > 0:
				# Dice-based heal (e.g. 2d4+CON for Health Potion)
				var raw_roll: int = 0
				for _i: int in item.heal_dice_count:
					raw_roll += Rng.roll(item.heal_dice_sides)
				var con_mod: int = player_stats.con_modifier()
				var amount: int = maxi(1, raw_roll + con_mod)
				var before: int = player_stats.current_hp
				var bruiser_bonus: int = heal(amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					var bonus_sources: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus, "color": "cyan"}])
					var _hm: String = "heal:dice=%d,sides=%d,con=%d,roll=%d,bonus=%s,total=%d" % [item.heal_dice_count, item.heal_dice_sides, con_mod, raw_roll, bonus_sources, healed]
					combat_message.emit("You drink [b]%s[/b] and heal [url=%s][color=lime]+%d HP[/color][/url]" % [item.item_name, _hm, healed])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
			elif item.heal_amount > 0:
				var before: int = player_stats.current_hp
				var bruiser_bonus2: int = heal(item.heal_amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					var bonus_sources2: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus2, "color": "cyan"}])
					var _hm2: String = "heal:dice=0,sides=0,con=0,roll=0,bonus=%s,total=%d" % [bonus_sources2, healed]
					combat_message.emit("[color=green]You drink [b]%s[/b] and recover [url=%s]%d HP[/url].[/color]" % [item.item_name, _hm2, healed])
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
			game_log("[color=gray]%s isn't eaten directly — it's saved as fuel for your next long rest (hold Alt).[/color]" % item.item_name)
		Item.Type.WEAPON, Item.Type.ARMOR:
			equip(item)  # equipping from bag/quickbar is always a free action
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

# is_raging is set by player.gd and read here to apply damage resistance.
var is_raging: bool = false
# Berserker Frenzy — once per short rest (also resets on long rest). Frenzied Killer talent
# refreshes it early on kill/crit/every-3-turns — see player_berserker.gd.
var berserker_frenzy_used: bool = false
# Frenzied Killer R3: turns since Frenzy was last used, incremented every real turn in
# player.gd._on_turn_started(), reset to 0 whenever Frenzy is used or auto-refreshed.
var berserker_turns_since_frenzy: int = 0
# Masochist Monster R1: +1 AC until the start of the player's next turn, folded into
# recalculate_stats() alongside terrain_ac_bonus. Set/cleared by player_berserker.gd.
var masochist_ac_bonus: int = 0
# Scarred Warrior Limit Break — once per long rest.
var scarred_warrior_limit_break_used: bool = false
# Bruiser R3 (base Barbarian Tier 1) — once per floor, resets in advance_floor().
var bruiser_revive_used_this_floor: bool = false
# Set true by take_damage_raw when the player takes physical hit damage (not status effects).
# Player.gd reads this in _on_turn_started to decide whether to pause the rage countdown.
var player_was_hit_this_turn: bool = false
# Set true by enemy.gd._attack_player() on ANY attack roll against the player, hit or miss.
# Separate from player_was_hit_this_turn (which specifically means damage landed) because
# Rage's duration refresh triggers on being attacked at all — see _on_turn_started()'s rage tick.
var player_attacked_this_turn: bool = false

# Synced by player.gd each turn so HUD can display remaining rage turns on the ability slot.
var rage_turns_remaining: int = 0

func take_damage_raw(amount: int, ignore_rage: bool = false, damage_type: String = "") -> int:
	if is_game_over:
		return 0
	# Rage baseline: flat 50% physical damage reduction while raging (Bludgeoning/Piercing/
	# Slashing only), unconditional — no longer talent-gated. Status effects and traps pass
	# damage_type="" — they bypass reduction intentionally.
	const PHYSICAL_TYPES: Array = ["Slashing", "Piercing", "Bludgeoning"]
	const ELEMENTAL_TYPES: Array = ["Fire", "Cold", "Lightning", "Thunder", "Acid", "Poison"]
	const MAGICAL_TYPES: Array = ["Radiant", "Necrotic", "Force"]
	var is_physical: bool = damage_type in PHYSICAL_TYPES
	if invincible:
		# Skip the actual HP change, but still register "the player was hit this turn" so
		# god-mode play doesn't silently break turn-based triggers that key off it (e.g.
		# Battlefield Expert R3's free Side Step charge — see player_base_talents.gd).
		if is_physical and not ignore_rage:
			player_was_hit_this_turn = true
		return 0
	var final_amount: int = amount
	if is_raging and not ignore_rage and is_physical:
		final_amount = int(floor(float(amount) * 0.5))
	# Animal Form Bear: always-active elemental DR (no Rage or talent rank required — see
	# markdowns/wild_heart.md). Enhanced Forms R1 also covers magical damage; R2/R3 raise the %.
	if natural_rager_form == "Bear" and not ignore_rage:
		var enh_rank: int = get_talent_rank("enhanced_forms")
		var resisted: bool = damage_type in ELEMENTAL_TYPES or (enh_rank >= 1 and damage_type in MAGICAL_TYPES)
		if resisted:
			var bear_dr: float = 0.25
			if enh_rank >= 3: bear_dr = 0.5
			elif enh_rank >= 2: bear_dr = 1.0 / 3.0
			final_amount = int(floor(float(final_amount) * (1.0 - bear_dr)))
	# Born in Blood (Scarred Warrior): NOT Bloodied -> take MORE incoming damage; Bloodied ->
	# take LESS. Applied after Rage/Bear DR, on top of the reduced amount.
	var bib_rank: int = get_talent_rank("born_in_blood")
	if bib_rank >= 1 and not ignore_rage:
		var bib_delta: int = bib_rank * player_stats.rage_bonus_damage
		final_amount += bib_delta if not player_stats.is_bloodied() else -bib_delta
		final_amount = maxi(0, final_amount)
	# DR can reduce damage to 0 — skip Stats.take_damage() which floors at 1.
	if final_amount <= 0:
		if is_physical and not ignore_rage:
			player_was_hit_this_turn = true
		return 0
	var actual: int = player_stats.take_damage(final_amount)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	if is_physical and not ignore_rage:
		player_was_hit_this_turn = true
	# Bruiser R2's +1 AC is Bloodied-conditional — recompute AC live whenever HP crosses the
	# threshold (only bothers if the talent is actually invested).
	if get_talent_rank("bruiser") >= 2:
		recalculate_stats()
	check_player_death()
	return actual


func apply_player_status(type: String, turns: int) -> bool:
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
	# Belt-and-braces: while Tier 2 is locked, _class_talents holds no tier-2 talents anyway,
	# but the explicit guard protects against future ordering changes.
	if t.tier == 2 and not tier2_unlocked:
		return false
	if not tier_unlocked(t.tier):
		return false
	return talent_points.get(t.tier, 0) > 0

func invest_talent(id: String) -> void:
	if not can_invest_talent(id):
		return
	var t: Talent = _find_talent(id)
	var new_rank: int = get_talent_rank(id) + 1
	talent_investments[id] = new_rank
	if not invincible:
		talent_points[t.tier] -= 1
	_apply_talent_rank(id, new_rank)
	AudioManager.play("talent_point_spent")
	talent_invested.emit(id, new_rank)
	talent_points_changed.emit(talent_points_available)

## Weapon mastery selection (Mastery Picker, scripts/ui/mastery_picker.gd) —
## see docs/architecture/weapon-mastery-selection-design.md.
func can_select_mastery(mastery_name: String) -> bool:
	if player_stats.knows_mastery(mastery_name):
		return true   # deselection is always allowed
	return player_stats.known_weapon_masteries.size() < player_stats.mastery_cap()

func toggle_mastery(mastery_name: String) -> bool:
	if player_stats.knows_mastery(mastery_name):
		player_stats.known_weapon_masteries.erase(mastery_name)
		known_masteries_changed.emit()
		return true
	if not can_select_mastery(mastery_name):
		return false   # hard-block at cap
	player_stats.known_weapon_masteries.append(mastery_name)
	known_masteries_changed.emit()
	return true

func debug_set_talent_rank(id: String, new_rank: int) -> void:
	var talent: Talent = _find_talent(id)
	if talent == null:
		return
	new_rank = clampi(new_rank, 0, talent.max_rank)
	var old_rank: int = get_talent_rank(id)
	if new_rank == old_rank:
		return
	if new_rank < old_rank:
		if new_rank == 0:
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
		"sadist_monster", "masochist_monster", "frenzied_killer":
			# All three upgrade the free base Frenzy ability rather than granting their own
			# ability-bar entry — refresh Frenzy's description so its tooltip stays current.
			var frenzy_ab: Ability = _find_ability_by_id("frenzy")
			if frenzy_ab != null:
				frenzy_ab.description = _build_frenzy_description()
		"born_in_blood", "bloodied_regen", "psycho", "bruiser", "battlefield_expert":
			pass  # pure stat-modifier/reactive talents — no ability to refresh
		"enough_is_enough":
			var lb_ab: Ability = _find_ability_by_id("limit_break")
			if lb_ab != null:
				lb_ab.description = _build_limit_break_description()
		"wild_companion":
			if rank == 1:
				var owtn := Ability.new()
				owtn.ability_id = "wild_companion"
				owtn.ability_name = "Wild Companion"
				owtn.description = _build_one_with_nature_description()
				owtn.icon_path = talent_icon_path("wild_companion", 1)
				owtn.uses_remaining = 1
				owtn.uses_max = 1
				add_ability(owtn)
			else:
				var owtn: Ability = _find_ability_by_id("wild_companion")
				if owtn != null:
					owtn.description = _build_one_with_nature_description()
					owtn.icon_path = talent_icon_path("wild_companion", rank)
		"enhanced_forms":
			# Upgrades the free base Animal Form ability rather than granting its own
			# ability-bar entry — refresh Animal Form's description so its tooltip stays current.
			var af_ab: Ability = _find_ability_by_id("animal_form")
			if af_ab != null:
				af_ab.description = _build_natural_rager_description()
		"expanded_forms":
			if rank == 1:
				var ns := Ability.new()
				ns.ability_id = "expanded_forms"
				ns.ability_name = "Natural Sleeper"
				ns.description = _build_natural_sleeper_description()
				ns.icon_path = talent_icon_path("expanded_forms", 1)
				ns.uses_remaining = 0
				ns.uses_max = 0
				add_ability(ns)
			else:
				var ns: Ability = _find_ability_by_id("expanded_forms")
				if ns != null:
					ns.description = _build_natural_sleeper_description()
					ns.icon_path = talent_icon_path("expanded_forms", rank)
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
		"judgement_day", "overheal_shield":
			# Both upgrade the free base Zealot Strike ability rather than granting their own
			# ability-bar entry — refresh its description so the tooltip stays current.
			var zs_ab: Ability = _find_ability_by_id("zealot_strike")
			if zs_ab != null:
				zs_ab.description = _build_zealot_strike_description()
		"never_back_down":
			hit_dice = mini(hit_dice + ([0, 1, 1, 2][mini(rank, 3)]), max_hit_dice())
	ability_bar_changed.emit()

func _build_frenzy_description() -> String:
	var sadist_rank: int = get_talent_rank("sadist_monster")
	var lines: Array[String] = [
		"Requires Raging. Move into or click an adjacent enemy. Rolls a plain d20 (no attack modifier, no AC) to decide the outcome — weapon damage always includes your STR mod + Rage bonus, same as a normal attack.",
		"Nat 1: miss — only you take the damage. 2-19: hit — enemy AND you both take the same damage roll. Nat 20: enemy takes double damage, you take none.",
		"Once per short rest (also resets on long rest).",
	]
	if sadist_rank >= 1:
		lines.append("Sadist Monster: enemy also takes +%dd6 bonus damage (self-damage unaffected)." % sadist_rank)
	return "\n".join(lines)


func _build_limit_break_description() -> String:
	var rank: int = get_talent_rank("enough_is_enough")
	var lines: Array[String] = [
		"Deal damage equal to your missing HP (Max HP - Current HP) to target enemy — no roll to hit, no damage roll.",
		"Once per long rest.",
	]
	if rank >= 1: lines.append("Enough is Enough: automatically applies your weapon's mastery effect.")
	if rank >= 2: lines.append("Also deals full damage to every entity adjacent to the target.")
	if rank >= 3: lines.append("Becomes ranged (5 tiles) and pierces every entity in a line to the target.")
	return "\n".join(lines)


func _build_rage_description() -> String:
	var uses: int = player_stats.rage_uses_max
	var bonus: int = player_stats.rage_bonus_damage
	var lines: Array[String] = []
	lines.append("+%d damage on STR attacks. 50%% DR vs Bludgeoning/Piercing/Slashing." % bonus)
	lines.append("Lasts 1 turn; refreshed to 1 turn by attacking or being attacked.")
	lines.append("%d use%s per floor (scales with level)." % [uses, "s" if uses != 1 else ""])
	return "\n".join(lines)

func _build_one_with_nature_description() -> String:
	var rank: int = get_talent_rank("wild_companion")
	var d: Dictionary = WILD_HEART_COMPANION_STATS.get(maxi(rank, 1), {})
	var animal: String = d.get("animal", "Squirrel")
	var hp: int = d.get("hp", 10)
	var ac: int = d.get("ac", 12)
	var dc: int = d.get("die_count", 1)
	var ds_: int = d.get("die_sides", 6)
	return "Summon a %s (HP %d, AC %d, %dd%d) to fight by your side.\n1 charge — refreshes on rest. Re-activate to dismiss and resummon." % [animal, hp, ac, dc, ds_]

func _build_natural_rager_description() -> String:
	var rank: int = get_talent_rank("enhanced_forms")
	var form: String = natural_rager_form
	var lines: Array[String] = []
	lines.append("[%s Form] — always active (no Rage required). Click to cycle forms." % form)
	match form:
		"Bear":
			lines.append("25% resistance to elemental damage (Fire/Cold/Lightning/Thunder/Acid/Poison).")
			if rank >= 1: lines.append("Enhanced Forms R1: resistance also covers magical damage (Radiant/Necrotic/Force).")
			if rank >= 2: lines.append("Enhanced Forms R2: resistance increased to 33%.")
			if rank >= 3: lines.append("Enhanced Forms R3: resistance increased to 50%.")
		"Eagle":
			lines.append("Enemies do not gain Opportunity Attacks against you.")
			if rank >= 1: lines.append("Enhanced Forms R1: +1 FOV radius.")
			if rank >= 2: lines.append("Enhanced Forms R2: ranged attacks against you have -2 to hit.")
			if rank >= 3: lines.append("Enhanced Forms R3: ranged enemies have Disadvantage to hit you.")
		"Wolf":
			var threshold: int = [4, 4, 3, 2][mini(rank, 3)]
			lines.append("ADV on attack rolls when %d+ enemies are in your FOV." % threshold)
			if rank >= 3: lines.append("Enhanced Forms R3: also ADV when 1 enemy + 1 friendly entity are in your FOV.")
	return "\n".join(lines)

func _build_natural_sleeper_description() -> String:
	var rank: int = get_talent_rank("expanded_forms")
	var form: String = natural_sleeper_form  # chosen form (preview for next rest)
	var lines: Array[String] = []
	# No form chosen yet
	if form == "":
		lines.append("[No form chosen] — press to select Owl / Panther / Salmon.")
		if not wild_heart_sleeper_active:
			lines.append("[color=gray](Long rest to activate chosen form.)[/color]")
		return "\n".join(lines)
	# Form chosen — show header and per-form rank effects
	if wild_heart_sleeper_active and active_sleeper_form != form:
		var active_label: String = active_sleeper_form if active_sleeper_form != "" else "none"
		lines.append("[%s Form] — activates next long rest. [color=gray]Active now: %s[/color]" % [form, active_label])
	elif wild_heart_sleeper_active:
		lines.append("[%s Form — active] Press to choose next long rest's form." % form)
	else:
		lines.append("[%s Form] — will activate on your next long rest. Press to cycle." % form)
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


func _build_zealot_strike_description() -> String:
	var jd_rank: int = get_talent_rank("judgement_day")
	var os_rank: int = get_talent_rank("overheal_shield")
	var lines: Array[String] = [
		"Your next melee attack this turn (hit or miss) consumes 1 Hit Die and heals you for the roll (1d%d + CON mod)." % hit_die_sides(),
		"Hit dice: %d/%d." % [hit_dice, max_hit_dice()],
	]
	if jd_rank >= 1:
		lines.append("Judgement Day: your next attack after the heal deals +%d× Rage bonus × 1d6 bonus damage." % jd_rank)
	if os_rank >= 1:
		var os_desc: String = ["", "the overheal amount", "the entire heal amount", "the entire heal + overheal amount"][os_rank]
		lines.append("Overheal Shield: gain Temporary HP equal to %s." % os_desc)
	return "\n".join(lines)

func _setup_barbarian_talents() -> void:
	_class_talents = []

	var psycho_talent := Talent.new()
	psycho_talent.talent_id = "psycho"
	psycho_talent.talent_name = "Psycho"
	psycho_talent.description = "Momentum: kills (and, at higher ranks, crits) feed into your next strike."
	psycho_talent.icon_path = talent_icon_path("psycho", 1)
	psycho_talent.tier = 1
	psycho_talent.class_id = Stats.CharacterClass.BARBARIAN
	psycho_talent.max_rank = 3
	psycho_talent.ranks = [
		{"description": "After a kill, your next attack is made with Advantage."},
		{"description": "After a critical hit, your next attack is made with Advantage."},
		{"description": "When attacking with Advantage, your crit range expands to 19-20."},
	]
	_class_talents.append(psycho_talent)

	var bruiser_talent := Talent.new()
	bruiser_talent.talent_id = "bruiser"
	bruiser_talent.talent_name = "Bruiser"
	bruiser_talent.description = "The lower you fall, the harder you hit back."
	bruiser_talent.icon_path = talent_icon_path("bruiser", 1)
	bruiser_talent.tier = 1
	bruiser_talent.class_id = Stats.CharacterClass.BARBARIAN
	bruiser_talent.max_rank = 3
	bruiser_talent.ranks = [
		{"description": "While Bloodied (below 50% max HP), any healing you receive is improved by +1d4."},
		{"description": "While Bloodied, gain +1 AC."},
		{"description": "Once per floor: if a hit while Raging would drop you to 0 HP, survive at 1 HP instead and Rage ends immediately."},
	]
	_class_talents.append(bruiser_talent)

	var battlefield_talent := Talent.new()
	battlefield_talent.talent_id = "battlefield_expert"
	battlefield_talent.talent_name = "Battlefield Expert"
	battlefield_talent.description = "Use footwork to dictate the fight."
	battlefield_talent.icon_path = talent_icon_path("battlefield_expert", 1)
	battlefield_talent.tier = 1
	battlefield_talent.class_id = Stats.CharacterClass.BARBARIAN
	battlefield_talent.max_rank = 3
	battlefield_talent.ranks = [
		{"description": "After side-stepping around an adjacent enemy, your next attack is made with Advantage."},
		{"description": "After side-stepping, the enemy you side-stepped around has Disadvantage on their next attack."},
		{"description": "Once per turn: if you were hit last turn, your first side-step this turn is free (doesn't cost the turn)."},
	]
	_class_talents.append(battlefield_talent)


func _setup_barbarian_tier2_talents() -> void:
	# Called via unlock_tier2() → _setup_tier2_for_active_subclass(). Appends Tier 2 to _class_talents.
	# Frenzy itself is a free, rank-independent activation ability (see markdowns/berserker.md) —
	# granted directly, not gated by talent investment.
	_grant_tier2_base_ability("frenzy", "Frenzy", _build_frenzy_description())

	var sadist_talent := Talent.new()
	sadist_talent.talent_id = "sadist_monster"
	sadist_talent.talent_name = "Sadist Monster"
	sadist_talent.description = "Frenzy deals bonus damage to the enemy only (not to you)."
	sadist_talent.icon_path = talent_icon_path("sadist_monster", 1)
	sadist_talent.tier = 2
	sadist_talent.class_id = Stats.CharacterClass.BARBARIAN
	sadist_talent.max_rank = 3
	sadist_talent.ranks = [
		{"description": "Frenzy's hit deals +1d6 bonus damage to the enemy (self-damage unaffected)."},
		{"description": "+2d6 bonus damage to the enemy."},
		{"description": "+3d6 bonus damage to the enemy."},
	]
	_class_talents.append(sadist_talent)

	var masochist_talent := Talent.new()
	masochist_talent.talent_id = "masochist_monster"
	masochist_talent.talent_name = "Masochist Monster"
	masochist_talent.description = "Being hurt on your turn fuels your defense."
	masochist_talent.icon_path = talent_icon_path("masochist_monster", 1)
	masochist_talent.tier = 2
	masochist_talent.class_id = Stats.CharacterClass.BARBARIAN
	masochist_talent.max_rank = 3
	masochist_talent.ranks = [
		{"description": "If you take any damage on your turn (including Frenzy self-damage): +1 AC until the start of your next turn."},
		{"description": "Also gain Temporary HP equal to (Rage bonus damage) d4, rolled separately and summed."},
		{"description": "Rage does not expire while at least 1 enemy is in your Field of View."},
	]
	_class_talents.append(masochist_talent)

	var frenzied_killer_talent := Talent.new()
	frenzied_killer_talent.talent_id = "frenzied_killer"
	frenzied_killer_talent.talent_name = "Frenzied Killer"
	frenzied_killer_talent.description = "Frenzy refreshes its use more frequently."
	frenzied_killer_talent.icon_path = talent_icon_path("frenzied_killer", 1)
	frenzied_killer_talent.tier = 2
	frenzied_killer_talent.class_id = Stats.CharacterClass.BARBARIAN
	frenzied_killer_talent.max_rank = 3
	frenzied_killer_talent.ranks = [
		{"description": "Frenzy's use refreshes whenever Frenzy itself lands the killing blow."},
		{"description": "Also refreshes whenever you land a critical hit with ANY attack, not just Frenzy."},
		{"description": "Also refreshes automatically every 3 turns."},
	]
	_class_talents.append(frenzied_killer_talent)


func _setup_scarred_warrior_tier2_talents() -> void:
	# Limit Break is a free, rank-independent activation ability — see markdowns/scarred_warrior.md.
	_grant_tier2_base_ability("limit_break", "Limit Break", _build_limit_break_description())

	var born_talent := Talent.new()
	born_talent.talent_id = "born_in_blood"
	born_talent.talent_name = "Born in Blood"
	born_talent.description = "Damage scaling changes based on Bloodied status."
	born_talent.icon_path = talent_icon_path("born_in_blood", 1)
	born_talent.tier = 2
	born_talent.class_id = Stats.CharacterClass.BARBARIAN
	born_talent.max_rank = 3
	born_talent.ranks = [
		{"description": "Not Bloodied: +1× Rage bonus incoming damage. Bloodied: -1× Rage bonus incoming damage (min 0)."},
		{"description": "+/- 2× Rage bonus incoming damage."},
		{"description": "+/- 3× Rage bonus incoming damage."},
	]
	_class_talents.append(born_talent)

	var enough_talent := Talent.new()
	enough_talent.talent_id = "enough_is_enough"
	enough_talent.talent_name = "Enough is Enough"
	enough_talent.description = "Upgrades Limit Break."
	enough_talent.icon_path = talent_icon_path("enough_is_enough", 1)
	enough_talent.tier = 2
	enough_talent.class_id = Stats.CharacterClass.BARBARIAN
	enough_talent.max_rank = 3
	enough_talent.ranks = [
		{"description": "Limit Break automatically applies your equipped weapon's mastery effect to the target."},
		{"description": "Limit Break also deals full damage to every entity adjacent to the primary target."},
		{"description": "Limit Break becomes ranged (5 tiles) and pierces — it hits every entity in a line to the target."},
	]
	_class_talents.append(enough_talent)

	var regen_talent := Talent.new()
	regen_talent.talent_id = "bloodied_regen"
	regen_talent.talent_name = "Spite"
	regen_talent.description = "While Bloodied, regenerate Temporary HP each turn."
	regen_talent.icon_path = talent_icon_path("bloodied_regen", 1)
	regen_talent.tier = 2
	regen_talent.class_id = Stats.CharacterClass.BARBARIAN
	regen_talent.max_rank = 3
	regen_talent.ranks = [
		{"description": "While Bloodied, gain 1× Rage bonus Temporary HP at the start of your turn."},
		{"description": "2× Rage bonus Temporary HP."},
		{"description": "3× Rage bonus Temporary HP."},
	]
	_class_talents.append(regen_talent)


func _setup_wild_heart_tier2_talents() -> void:
	# Wild Heart is an experimental subclass — balance will change significantly after playtesting.
	# Animal Form (Bear/Eagle/Wolf) is a free, rank-independent activation ability — see
	# markdowns/wild_heart.md — granted directly, not gated by talent investment.
	_grant_tier2_base_ability("animal_form", "Animal Form", _build_natural_rager_description())
	player_evades_opportunity_attacks = natural_rager_form == "Eagle"

	var owtn_talent := Talent.new()
	owtn_talent.talent_id = "wild_companion"
	owtn_talent.talent_name = "Wild Companion"
	owtn_talent.description = "After each long rest, summon an animal companion that fights alongside you."
	owtn_talent.icon_path = talent_icon_path("wild_companion", 1)
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
	nr_talent.talent_id = "enhanced_forms"
	nr_talent.talent_name = "Enhanced Forms"
	nr_talent.description = "Upgrades the base Bear/Eagle/Wolf Animal Forms."
	nr_talent.icon_path = talent_icon_path("enhanced_forms", 1)
	nr_talent.tier = 2
	nr_talent.class_id = Stats.CharacterClass.BARBARIAN
	nr_talent.max_rank = 3
	nr_talent.ranks = [
		{"description": "Bear: resistance also covers magical damage. Eagle: +1 FOV radius. Wolf: ADV threshold drops to 3+ enemies."},
		{"description": "Bear: resistance increased to 33%. Eagle: ranged attacks against you have -2 to hit. Wolf: threshold drops to 2+ enemies."},
		{"description": "Bear: resistance increased to 50%. Eagle: ranged enemies have Disadvantage to hit you. Wolf: also ADV at 1 enemy + 1 friendly in FOV."},
	]
	_class_talents.append(nr_talent)

	var ns_talent := Talent.new()
	ns_talent.talent_id = "expanded_forms"
	ns_talent.talent_name = "Expanded Forms"
	ns_talent.description = "Unlock Owl/Panther/Salmon terrain forms. Activates on long rest."
	ns_talent.icon_path = talent_icon_path("expanded_forms", 1)
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
	# Zealot Strike is a free, rank-independent activation ability — see markdowns/zealot.md.
	_grant_tier2_base_ability("zealot_strike", "Zealot Strike", _build_zealot_strike_description())

	var jd_talent := Talent.new()
	jd_talent.talent_id = "judgement_day"
	jd_talent.talent_name = "Judgement Day"
	jd_talent.description = "After healing from Zealot Strike, your next attack deals bonus Radiant damage."
	jd_talent.icon_path = talent_icon_path("judgement_day", 1)
	jd_talent.tier = 2
	jd_talent.class_id = Stats.CharacterClass.BARBARIAN
	jd_talent.max_rank = 3
	jd_talent.ranks = [
		{"description": "Bonus damage: 1× Rage bonus × 1d6."},
		{"description": "2× Rage bonus × 1d6."},
		{"description": "3× Rage bonus × 1d6."},
	]
	_class_talents.append(jd_talent)

	var os_talent := Talent.new()
	os_talent.talent_id = "overheal_shield"
	os_talent.talent_name = "Overheal Shield"
	os_talent.description = "Overhealing from Zealot Strike generates Temporary HP."
	os_talent.icon_path = talent_icon_path("overheal_shield", 1)
	os_talent.tier = 2
	os_talent.class_id = Stats.CharacterClass.BARBARIAN
	os_talent.max_rank = 3
	os_talent.ranks = [
		{"description": "Gain Temporary HP equal to the overheal amount."},
		{"description": "Gain Temporary HP equal to the entire heal amount."},
		{"description": "Gain Temporary HP equal to the entire heal + overheal amount."},
	]
	_class_talents.append(os_talent)

	var nbd_talent := Talent.new()
	nbd_talent.talent_id = "never_back_down"
	nbd_talent.talent_name = "Never Back Down"
	nbd_talent.description = "Gain additional max Hit Dice."
	nbd_talent.icon_path = talent_icon_path("never_back_down", 1)
	nbd_talent.tier = 2
	nbd_talent.class_id = Stats.CharacterClass.BARBARIAN
	nbd_talent.max_rank = 3
	nbd_talent.ranks = [
		{"description": "+1 max Hit Dice."},
		{"description": "+2 max Hit Dice (replaces rank 1)."},
		{"description": "+4 max Hit Dice (replaces rank 2)."},
	]
	_class_talents.append(nbd_talent)

# ── Save/load (Phase A — docs/architecture/SAVE_LOAD_ARCHITECTURE.md §4) ────────
# Assembles/restores the full Phase-A run snapshot. SaveManager owns file I/O and the
# top-level save_version key; GameState only produces/consumes the payload. Per-floor
# world state (enemies, doors, traps, fog, floor items, player_grid_pos) is deliberately
# NOT serialized — Phase A reloads the floor fresh from run_seed + current_floor.
# Abilities are DERIVED state (doc §4.3): never serialized as objects, always rebuilt by
# replaying _apply_talent_rank() per saved talent_investments, then patched with the small
# ability_uses / ability_active maps below.

func to_dict() -> Dictionary:
	var ability_uses: Dictionary = {}
	var ability_active: Dictionary = {}
	for slot in player_ability_bar:
		if slot != null:
			var ab := slot as Ability
			ability_uses[ab.ability_id] = ab.uses_remaining
			ability_active[ab.ability_id] = ab.is_active
	var companion: Dictionary = {}
	if player_companion != null and is_instance_valid(player_companion):
		companion = {"alive": true, "current_hp": int(player_companion.stats.current_hp)}
	var equipment_dicts: Dictionary = {}
	for key: String in equipment:
		var it: Item = equipment[key] as Item
		equipment_dicts[key] = it.to_dict() if it != null else null
	var chasm_dicts: Array = []
	for it: Item in pending_chasm_items:
		chasm_dicts.append(it.to_dict())
	return {
		"run_seed": run_seed,
		# Exact gameplay-RNG stream position (rng.gd). Stored as String: JSON parses
		# all numbers as float, which silently corrupts int64 states above 2^53.
		"rng_state": str(Rng.get_state()),
		"current_floor": current_floor,
		"gold": gold,
		"player_stats": player_stats.to_dict(),
		"talents": {
			"talent_investments": talent_investments.duplicate(),
			"talent_points": talent_points.duplicate(),
			"tier2_unlocked": tier2_unlocked,
			"active_tier2_subclass": active_tier2_subclass,
			"natural_rager_form": natural_rager_form,
			"natural_sleeper_form": natural_sleeper_form,
			"active_sleeper_form": active_sleeper_form,
			"wild_heart_sleeper_active": wild_heart_sleeper_active,
			"zealot_divine_fury_type": zealot_divine_fury_type,
			"zealot_blessed_charges": zealot_blessed_charges,
			"zealot_zp_charges": zealot_zp_charges,
			"ability_uses": ability_uses,
			"ability_active": ability_active,
		},
		"inventory": {
			"quickbar": _item_slots_to_dicts(player_quickbar),
			"bag": _item_slots_to_dicts(player_inventory),
			"equipment": equipment_dicts,
			"pending_chasm_items": chasm_dicts,
			"companion": companion,
		},
		"rest": {
			"hit_dice": hit_dice,
			"short_rests_remaining": short_rests_remaining,
		},
	}

# Restores the full run state from a parsed save dict (load order per doc §4.3):
# clean slate → class defaults + starting gear rebuild → talent replay → inventory/
# equipment → rest → Stats LAST (so any stat-mutating replay one-shots are overwritten by
# the saved, already-buffed values instead of double-applying) →
# per-ability uses/toggle patches. Does NOT load the floor — the caller (session 3c's
# Continue flow) decides when to reload the floor from run_seed + current_floor.
func from_dict(d: Dictionary) -> void:
	start_new_run()
	run_seed = int(d.get("run_seed", run_seed))
	# Resume the exact gameplay-RNG stream position; saves that predate rng_state
	# (v1) fall back to re-seeding from run_seed — a fresh but still seeded stream.
	if d.has("rng_state"):
		Rng.set_state(str(d["rng_state"]).to_int())
	else:
		Rng.reseed(run_seed)
	current_floor = int(d.get("current_floor", 1))
	gold = int(d.get("gold", 0))  # old saves predating the gold economy load as 0
	var stats_d: Dictionary = d.get("player_stats", {})
	var talents_d: Dictionary = d.get("talents", {})
	var inv_d: Dictionary = d.get("inventory", {})
	var rest_d: Dictionary = d.get("rest", {})
	# 1. Class + defaults + baseline class gear/abilities/talent definitions.
	player_stats.character_class = int(stats_d.get("character_class", Stats.CharacterClass.BARBARIAN)) as Stats.CharacterClass
	player_stats.apply_class_defaults()
	class_selected = true
	give_class_starting_items()
	# 2. Talent replay. Investments are set in full BEFORE replaying so the _build_*
	# description helpers (which read get_talent_rank()) see final ranks. Tier 2 setup
	# runs silently (no unlock_tier2() log line) via _setup_tier2_for_active_subclass().
	active_tier2_subclass = String(talents_d.get("active_tier2_subclass", "Berserker"))
	if bool(talents_d.get("tier2_unlocked", false)):
		tier2_unlocked = true
		_setup_tier2_for_active_subclass()
	talent_investments = {}
	var saved_investments: Dictionary = talents_d.get("talent_investments", {})
	for id: String in saved_investments:
		talent_investments[id] = int(saved_investments[id])
	for id: String in talent_investments:
		var rank: int = talent_investments[id]
		for r: int in range(1, rank + 1):
			_apply_talent_rank(id, r)
	var saved_points: Dictionary = talents_d.get("talent_points", {})
	for t: int in talent_points:
		talent_points[t] = int(saved_points.get(str(t), saved_points.get(t, 0)))
	# Wild Heart / Zealot state — restored AFTER the replay, which resets charge pools to max.
	natural_rager_form = String(talents_d.get("natural_rager_form", "Bear"))
	natural_sleeper_form = String(talents_d.get("natural_sleeper_form", ""))
	active_sleeper_form = String(talents_d.get("active_sleeper_form", ""))
	wild_heart_sleeper_active = bool(talents_d.get("wild_heart_sleeper_active", false))
	zealot_divine_fury_type = String(talents_d.get("zealot_divine_fury_type", "Radiant"))
	zealot_blessed_charges = int(talents_d.get("zealot_blessed_charges", 0))
	zealot_zp_charges = int(talents_d.get("zealot_zp_charges", 0))
	# 3. Inventory / equipment (null slots preserved to keep positions).
	_dicts_into_item_slots(inv_d.get("quickbar", []), player_quickbar, QUICKBAR_SIZE)
	_dicts_into_item_slots(inv_d.get("bag", []), player_inventory, INVENTORY_SIZE)
	var eq_d: Dictionary = inv_d.get("equipment", {})
	for key: String in equipment:
		var slot_d: Variant = eq_d.get(key)
		equipment[key] = Item.from_dict(slot_d) if slot_d is Dictionary else null
	pending_chasm_items.clear()
	for cd: Variant in (inv_d.get("pending_chasm_items", []) as Array):
		if cd is Dictionary:
			pending_chasm_items.append(Item.from_dict(cd))
	pending_companion_restore = inv_d.get("companion", {})
	# 4. Rest resources.
	hit_dice = int(rest_d.get("hit_dice", 1))
	short_rests_remaining = int(rest_d.get("short_rests_remaining", max_short_rests))
	# 5. Stats LAST (restore-stats-last rule, doc §4.3), then derive AC/damage from equipment.
	player_stats.from_dict(stats_d)
	recalculate_stats()
	# Re-derive level-scaled ability maxima (e.g. Rage uses_max) from the restored stats;
	# the saved ability_uses patches below then overwrite uses_remaining where applicable.
	_sync_ability_uses()
	# 6. Per-ability derived-state patches (uses_remaining / toggle state).
	var uses_d: Dictionary = talents_d.get("ability_uses", {})
	var active_d: Dictionary = talents_d.get("ability_active", {})
	for slot in player_ability_bar:
		if slot == null:
			continue
		var ab := slot as Ability
		if uses_d.has(ab.ability_id):
			ab.uses_remaining = int(uses_d[ab.ability_id])
		if active_d.has(ab.ability_id):
			ab.is_active = bool(active_d[ab.ability_id])
	# 7. UI refresh (signals only — HUD never polls). floor_changed is deliberately NOT
	# emitted here; the Continue flow (3c) drives the actual floor load.
	inventory_changed.emit()
	equipment_changed.emit()
	ability_bar_changed.emit()
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	player_exp_changed.emit(player_stats.experience, player_stats.exp_to_next(), player_stats.character_level)
	player_status_changed.emit()
	short_rest_changed.emit()
	talent_points_changed.emit(talent_points_available)
	known_masteries_changed.emit()
	gold_changed.emit(gold)

func _item_slots_to_dicts(slots: Array) -> Array:
	var out: Array = []
	for slot in slots:
		out.append((slot as Item).to_dict() if slot != null else null)
	return out

func _dicts_into_item_slots(dicts: Array, slots: Array, size: int) -> void:
	for i: int in size:
		var entry: Variant = dicts[i] if i < dicts.size() else null
		slots[i] = Item.from_dict(entry) if entry is Dictionary else null
