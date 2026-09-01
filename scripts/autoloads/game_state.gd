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
signal player_scroll_primed(item: Item)
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
signal enemy_inspected(enemy: Enemy)  # RMB-inspect on an enemy — hud.gd spawns/refreshes the Enemy Info Panel
signal enemy_inspect_closed           # RMB-inspect target lost/cleared/Esc — hud.gd hides the Enemy Info Panel
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
# Fired when a Warlock's Eldritch Invocation schedule opens a new pending slot.
# hud.gd listens and spawns scripts/ui/invocation_picker.gd — GameState never instantiates UI.
signal invocation_choice_required
signal gold_changed(new_amount: int)
signal long_rest_completed()
# Bruiser R3: fired instead of player_died when the revive triggers. player.gd connects this to
# _end_rage() since Rage state lives there, not on GameState.
signal force_rage_end()
# Death save sequence (see check_player_death()/begin_death_save_sequence() below) —
# scripts/ui/death_save_overlay.gd is the sole listener/spawner, driven entirely off these three.
signal death_save_started
signal death_save_rolled(die: int, result: String, successes: int, failures: int)  # result: "critfail"/"fail"/"success"/"critsuccess"
signal death_save_finished(revived: bool)

const QUICKBAR_SIZE: int = 9
const ABILITY_BAR_SIZE: int = 9
const INVENTORY_SIZE: int = 24

# Wild Heart Tier 2 companion stats by rank (data-driven, no hardcoded logic)
const WILD_HEART_COMPANION_STATS: Dictionary = {
	1: {"animal": "Squirrel", "ac": 12, "hp": 10, "die_count": 1, "die_sides": 6},
	2: {"animal": "Boar",     "ac": 14, "hp": 20, "die_count": 2, "die_sides": 6},
	3: {"animal": "Bear",     "ac": 16, "hp": 30, "die_count": 3, "die_sides": 6},
}

# Talent/ability icon lookup tables + resolution logic live in TalentIcons
# (scripts/autoloads/talent_icons.gd) — extracted out of this file since they're pure data with no
# GameState-specific state of their own (besides the two live form fields passed into resolve()).
func talent_icon_path(id: String, rank: int) -> String:
	return TalentIcons.resolve(id, rank, natural_rager_form, natural_sleeper_form)

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
# Death save sequence — a hit that would drop the player to 0 HP (and isn't caught by Bruiser R3 /
# Relentless Endurance) enters this state instead of setting is_game_over immediately. Blocks ALL
# player input (threaded into player.gd's is_game_over guard chains — see check_player_death()/
# begin_death_save_sequence() below) and stalls the turn economy (no further player action means
# TurnManager never starts another round) while scripts/ui/death_save_overlay.gd runs the dramatic
# rolling animation. Not serialized — combat-transient, same tier as is_game_over itself.
var is_dying: bool = false
var death_save_successes: int = 0
var death_save_failures: int = 0
# "Risen from the Dead" buff: granted on a successful death-save revive. Total invulnerability
# (no damage from ANY source — attacks, OAs, status ticks, traps, even self-inflicted) through the
# rest of the round the player revives into plus the following enemy round, clearing the instant
# the player's NEXT real round begins — cleared from player.gd's _on_turn_started() (see that
# file's own comment). Not serialized — combat-transient, same tier as is_raging.
var risen_from_dead_active: bool = false
var inventory_open: bool = false
var class_selected: bool = false
# Custom character-creation Back-navigation state (scripts/ui/CLAUDE.md's "Custom character
# creation: Back navigation + summary screen"). Both are transient onboarding-only state,
# never serialized — cleared by reset_for_class_reselect().
var pending_point_buy_scores: Dictionary = {}   # last-confirmed point_buy_select.gd scores, empty = none yet
var pending_background_bonus: Dictionary = {}   # last-confirmed background_select.gd bonus dict, empty = none yet
var character_summary_open: bool = false        # blocks input while character_summary.gd is visible
var invincible: bool = false
var noclip: bool = false
var god_mode: bool = false
# Stealth-vs-Passive-Perception check (docs/architecture/stealth-and-surprise-attacks-design.md
# §3.3): the CURRENT player action's classification, set by the action's own call site right
# before TurnManager.begin_player_action(), consumed and reset by Player._resolve_stealth_check()
# (called from _on_turn_ending(), once per real action). Neither flag set = "movement" (check
# fires, no stillness ADV) — the default, untouched classification.
var stealth_check_skip: bool = false        # true: this action was an attack/spell — no check at all
var stealth_check_stillness: bool = false   # true: this action was combat-free & movement-free — ADV on the check
var debug_show_all_checks: bool = false # debug-only: log EVERY resist/save-style check (pass or fail) — Stealth-vs-PP, Undead Fortitude, Thief Tools disarm/lock/pick, etc. — not just real events, never changes the roll/outcome, visibility only
var hit_dice: int = 1
var short_rests_remaining: int = 2
var max_short_rests: int = 2
var gold: int = 0   # the wallet — plain int counter, earned via add_gold(), spent via spend_gold()
# Blacksmith crafting (scripts/items/CLAUDE.md's "WeaponForge" section). mold_target_floor is
# rolled once at run start (Rng, gameplay stream) uniform across floors 1-4 — DungeonFloor.
# _spawn_mold() guarantees exactly one Mold on that floor; mold_spawned prevents it re-spawning
# on floor reload/save-load.
var mold_target_floor: int = 1
var mold_spawned: bool = false
# Tenebrous NPC (see scripts/world/CLAUDE.md's "Tenebrous prop"): a special-room ROOM_POOL entry
# whose prop only actually spawns once per run — interacting grants one random Major Arcana card
# item and permanently flips this true, so any later TenebrousRoom that generates is just an empty
# vault with no prop in it.
var tenebrous_card_given: bool = false
# Snapshot of the just-finished character creation (class/scores/race/masteries/known spells) —
# see snapshot_character_creation()/retry_same_character() below. Survives start_new_run() (which
# never touches it) so death's "Try Again" can rebuild the same character on a fresh run/seed.
var character_creation_snapshot: Dictionary = {}
var blacksmith_panel_open: bool = false     # blocks ALL player input while blacksmith_panel.gd is visible
var shop_open: bool = false                 # blocks ALL player input while shop_panel.gd is visible
var short_rest_open: bool = false
var talent_picker_open: bool = false
var mastery_picker_open: bool = false
var mastery_reselect_used_this_long_rest: bool = false  # long-rest hub: Weapon Masteries reselect is limited to once per long-rest cycle, reset in long_rest()
var subclass_picker_open: bool = false  # blocks ALL player input while the subclass-select overlay is visible
var race_picker_open: bool = false  # blocks ALL player input while the race-select overlay is visible (scripts/ui/race_select.gd)
var point_buy_open: bool = false  # blocks ALL player input while the point-buy overlay is visible (scripts/ui/point_buy_select.gd, Custom path only)
var background_select_open: bool = false  # blocks ALL player input while the background-select overlay is visible (scripts/ui/background_select.gd, Custom path only)
var cantrip_picker_open: bool = false  # blocks ALL player input while the cantrip-select overlay is visible (scripts/ui/cantrip_select.gd, Wizard only)
# Leveled spells / spellbook (docs/architecture/leveled-spells-and-slots-plan.md):
var spell_learn_pending: bool = false        # set on a Wizard level-up with eligible spells to learn
var spell_learn_choices: Array[String] = []  # up to 3 rolled candidate spell ids
var spell_learn_picker_open: bool = false    # blocks ALL player input while spell_learn_picker.gd is visible
var spellbook_open: bool = false             # blocks ALL player input while spellbook_overlay.gd (R key) is visible
signal spell_slots_changed

# Set on a level-up that raises Stats.mastery_cap() (e.g. Barbarian hitting level 4/10) —
# hud.gd spawns mastery_picker.gd immediately so the extra slot can be picked on the spot,
# same "instant pick" treatment as hit dice/spell slots growing on level-up.
var mastery_learn_pending: bool = false

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
# Tier/level schedule + gating logic lives in TalentTiers (scripts/autoloads/talent_tiers.gd).
const TIER_LEVEL_RANGES: Dictionary = TalentTiers.TIER_LEVEL_RANGES
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
# Warlock Eldritch Invocations (scripts/entities/CLAUDE.md's "Warlock class") — cumulative
# known-count schedule, permanent picks (no respec, matching talent investment permanence).
# Points earned before enough level-appropriate content exists sit pending (same precedent as
# Tier-2 talent points pending on the boss-kill gate).
var warlock_invocations_known: Array[String] = []
var warlock_invocation_slots_pending: int = 0
var invocation_picker_open: bool = false  # blocks ALL player input while invocation_picker.gd is visible
const WARLOCK_INVOCATION_SCHEDULE: Dictionary = {1: 1, 2: 3, 5: 5, 7: 6, 9: 7, 12: 8, 15: 9, 18: 10}

var short_rest_active: bool = false
var short_rest_turns_remaining: int = 0
var short_rest_pending_heal: int = 0
# Individual per-hit-die raw rolls (before CON) behind short_rest_pending_heal's total — lets the
# completion log's tooltip show each die separately instead of just the summed number.
var short_rest_pending_heal_rolls: Array[int] = []
# Set true when the in-progress short_rest_active countdown is actually a long rest (Alt menu's
# Long Rest tab). Consumed on completion by player.gd's _on_turn_started(), which calls
# long_rest() instead of applying the short-rest heal. See long_rest() below.
var long_rest_pending: bool = false

# ── Scroll-learning (Wizard "Learn" RMB interaction, scripts/items/CLAUDE.md's
# "Scroll of <Spell>" section) ────────────────────────────────────────────────
# Studying a scroll into the spellbook takes 2 real turns per spell level (a cantrip scroll is
# learned instantly, no turns). Ticked in player.gd's _on_turn_started(), mirrors short_rest_active's
# auto-wait/interrupt shape but is its own independent flag (not a rest).
var armor_change_active: bool = false
var armor_change_turns_remaining: int = 0
var armor_change_total_turns: int = 0
var armor_change_new_item: Item = null  # item being equipped into "armor" — null if only removing
var armor_change_old_item: Item = null  # item being removed from "armor" — null if only equipping

var scroll_learn_active: bool = false
var scroll_learn_turns_remaining: int = 0
var scroll_learn_total_turns: int = 0
var scroll_learn_spell_id: String = ""
var scroll_learn_item: Item = null

# ── Wild Heart Tier 2 state ───────────────────────────────────────────────────
# Animal Form: switch between Bear/Eagle/Wolf freely, any time — NOT rest-gated (that's Natural
# Sleeper below, a different talent). natural_rager_form is the TARGET form just selected;
# active_rager_form is what's actually granting effects right now. Each individual switch step
# (one cycle press = one step to the adjacent form in the Bear→Eagle→Wolf→Bear cycle) takes
# ANIMAL_FORM_SWITCH_TURNS (1) real turn to complete — rager_form_switch_turns_remaining counts
# down each real turn (player.gd._on_turn_started()) via _tick_animal_form_transition(); reaching 0
# snaps active_rager_form to natural_rager_form. Re-cycling mid-transition just retargets and
# restarts the count — since there's no way to jump directly to the 3rd form in the cycle, going
# e.g. Bear→Wolf costs 2 presses/turns (one per intermediate step), not one flat wait.
var natural_rager_form: String = "Bear"
var active_rager_form: String = "Bear"
const ANIMAL_FORM_SWITCH_TURNS: int = 1
var rager_form_switch_turns_remaining: int = 0
# Natural Sleeper: toggle between Owl/Panther/Salmon; activates/locks in on a completed long rest.
# natural_sleeper_form = chosen form (preview); active_sleeper_form = locked in at last long rest.
var natural_sleeper_form: String = ""   # "" = no form chosen; locks in on long_rest()
var active_sleeper_form: String = ""    # locks in on long_rest() only
var wild_heart_sleeper_active: bool = false
# Wild Heart Eagle form: true for as long as active_rager_form == "Eagle" (kept in sync by
# _apply_active_rager_form_effects(), NOT turn-scoped) - enemies never gain Opportunity Attacks
# against the player while active. Do not reset this on a turn boundary; it tracks form state, not
# a per-round buff. Monk's own per-round Disengage (Patient Defense/Step of the Wind) is a SEPARATE
# flag, monk_disengage_this_round, precisely so it can't stomp this one - see that flag's comment.
var player_evades_opportunity_attacks: bool = false
# Monk Disengage-for-the-round (Patient Defense/Step of the Wind, scripts/entities/player_monk.gd,
# D&D 2024 PHB text folds a Disengage into both): while true, none of the player's voluntary moves
# THIS ROUND provoke an Opportunity Attack (Player._resolve_enemy_opportunity_attacks() ORs it with
# player_evades_opportunity_attacks above). Reset every REAL turn start alongside the other
# once-per-round flags in Player._on_turn_started() - kept independent of the Eagle-form flag above
# so that reset can never interrupt an active Eagle form.
var monk_disengage_this_round: bool = false
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
# True while the player's CURRENT tile is Mud/Water and not bypassed (Trailblazer R1, Natural
# Sleeper Panther/Salmon) — recomputed live every player turn-start in player.gd._on_turn_started()
# from grid_pos, deliberately NOT derived from Stats.slowed_turns' decaying counter (that field
# also carries Bear Trap's real 20-turn debuff and gets ticked to 0 the instant a real turn passes,
# which made the status-tray icon flicker for a single frame on each terrain step instead of
# staying up the whole time the player stands in Mud/Water). Status-tray display only — the actual
# "next move costs 2 turns" penalty still runs entirely off Stats.slowed_turns, unchanged.
var player_on_difficult_terrain: bool = false
# Psycho R1/R2 and Battlefield Expert R1's pending-Advantage windows — live here (not on
# PlayerBaseTalents) so the HUD status tray can display them while only reading GameState, per
# scripts/ui/CLAUDE.md's "HUD only reads GameState" convention. See scripts/entities/CLAUDE.md's
# Barbarian Tier 1 talents section.
var psycho_adv_pending: bool = false
var battlefield_adv_pending: bool = false
# Grip of the Forest's once-per-turn cap and Halfling Nimbleness's once-per-round cap — mirrored
# here from Player._grip_used_this_turn / PlayerHalfling.used_this_turn (same "HUD only reads
# GameState" reasoning as psycho_adv_pending/battlefield_adv_pending above) so is_ability_usable()
# can grey the ability bar for these per-round caps too, not just rest-gated resources.
var grip_of_the_forest_used_this_turn: bool = false
var halfling_nimbleness_used_this_turn: bool = false
var step_of_wind_used_this_turn: bool = false  # Monk's Step of the Wind — once per turn, see player_monk.gd
# Bonus Action economy (see scripts/entities/CLAUDE.md's "Bonus Action economy" section): a single shared
# once-per-real-round gate over every "free action" ability that would otherwise chain infinitely
# in one round (Rage, Frenzy, Zealot Strike, Flurry of Blows, Step of the Wind, Halfling
# Nimbleness, Cloud Giant's Jaunt, Orc Adrenaline Rush, Human Heroic Inspiration, Blade Ward, Grip
# of the Forest). Reset in player.gd's _on_turn_started()'s `if not came_from_revert:` block,
# alongside grip_of_the_forest_used_this_turn etc. Captured in RewindManager.
# REWIND_GAMESTATE_FIELDS so Backspace can't be used to refresh it for free.
var bonus_action_used: bool = false
# Monk's Extra Attack (level 5+, see player.gd's _handle_post_attack_turn()): monk_extra_attack_pending
# is true for the whole granted second-attack window (nothing but landing that attack or Wait can
# happen while it's open — see _try_move()/the LMB click handler/_use_quickbar_slot()'s own
# guards); monk_extra_attack_used_this_turn is the once-per-real-turn gate on GRANTING the window
# in the first place, reset in player.gd's _on_turn_started().
var monk_extra_attack_pending: bool = false
var monk_extra_attack_used_this_turn: bool = false
# Fighter's Action Surge (level 2+): true while the granted extra-action window is open, consumed
# by the player's very next move (player.gd._try_move()'s tail) or attack (melee/ranged/thrown —
# player._handle_post_attack_turn()'s `is_spell == false` branch) — either reverts to waiting
# instead of ending the turn. A spell cast (is_spell == true) deliberately does NOT consume/extend
# it — it just resolves normally, ending the turn as if Action Surge had never been used. No
# separate "used this turn" cap like Extra Attack — this is a manually-spent charge
# (Stats.action_surge_uses_remaining), not an automatic per-turn trigger. Reset (cleared without
# refunding) at the start of the player's next REAL turn if it was activated but never consumed by
# a qualifying action (item/ability use, Wait, etc. all silently let it lapse) — see
# player.gd's _on_turn_started().
var action_surge_pending: bool = false
# Human Heroic Inspiration: activating the ability arms this; the player's very next d20 roll
# (attack, check, or save — anything routed through CombatMath.roll_with_adv_disadv() or the
# stealth-check/Thief-Tools-disarm rolls) is forced to a natural 20, guaranteeing a critical
# success, then consumed. See scripts/entities/CLAUDE.md's "Human" section.
var heroic_inspiration_pending: bool = false
# Battlefield Expert R1's Tactician buff expires if unused: counts down by 1 on every REAL
# player turn-start (not on Battlefield Expert R3's free/reverted side-step turns) and clears
# battlefield_adv_pending when it hits 0 — see PlayerBaseTalents.on_sidestep()/
# tick_battlefield_adv_expiry() and scripts/entities/CLAUDE.md's Barbarian Tier 1 talents.
var battlefield_adv_expire_turns: int = 0

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
	mold_target_floor = Rng.range_i(1, 4)
	mold_spawned = false
	tenebrous_card_given = false
	blacksmith_panel_open = false
	shop_open = false
	current_floor = 1
	is_game_over = false
	is_dying = false
	death_save_successes = 0
	death_save_failures = 0
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
	background_select_open = false
	cantrip_picker_open = false
	spell_learn_pending = false
	spell_learn_choices = []
	spell_learn_picker_open = false
	spellbook_open = false
	mastery_learn_pending = false
	invocation_picker_open = false
	warlock_invocations_known = []
	warlock_invocation_slots_pending = 0
	light_source_pos = Vector2i(-1, -1)
	light_source_item = null
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
	special_slot_spell_id = ""
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
	active_rager_form = "Bear"
	rager_form_switch_turns_remaining = 0
	natural_sleeper_form = ""
	active_sleeper_form = ""
	wild_heart_sleeper_active = false
	player_evades_opportunity_attacks = false
	monk_disengage_this_round = false
	player_companion = null
	pending_companion_restore = {}
	terrain_ac_bonus = 0
	# Combat/turn-transient state that otherwise survives death into the next character (was never
	# cleared here — e.g. Rage staying "active" in the status tray for a brand-new run/character).
	is_raging = false
	rage_turns_remaining = 0
	berserker_frenzy_used = false
	berserker_turns_since_frenzy = 0
	masochist_ac_bonus = 0
	scarred_warrior_limit_break_used = false
	bruiser_revive_used_this_floor = false
	player_was_hit_this_turn = false
	player_attacked_this_turn = false
	enemy_noticed_player_this_turn = false
	fov_radius_bonus = 0
	psycho_adv_pending = false
	battlefield_adv_pending = false
	heroic_inspiration_pending = false
	battlefield_adv_expire_turns = 0
	fog_cloud_pos = Vector2i(-1, -1)
	fog_cloud_radius = 0
	darkness_pos = Vector2i(-1, -1)
	darkness_radius = 0
	darkness_item = null
	_give_starting_items()

# Captures exactly what's needed to rebuild this same character (class, final ability scores,
# race, weapon masteries, known Wizard spells) fresh at level 1 with starting gear — called once,
# right when character creation actually completes (character_select.gd's premade pick, or
# character_summary.gd's final "Yes" confirm on the Custom path). Deliberately NOT a to_dict()
# snapshot of the whole run — it must survive stripped back down to a brand-new run_seed/floor 1
# on retry_same_character(), not replay this playthrough's progress.
func snapshot_character_creation() -> void:
	var d: Dictionary = {}
	d["character_class"] = int(player_stats.character_class)
	d["scores"] = {
		"str": player_stats.strength, "dex": player_stats.dexterity, "con": player_stats.constitution,
		"int": player_stats.intelligence, "wis": player_stats.wisdom, "cha": player_stats.charisma,
	}
	d["race"] = int(player_stats.character_race)
	d["race_variant"] = player_stats.race_variant
	d["race_prof_ability"] = player_stats.race_prof_ability
	d["masteries"] = player_stats.known_weapon_masteries.duplicate()
	if player_stats.character_class == Stats.CharacterClass.FIGHTER:
		d["fighting_style"] = player_stats.fighting_style
	if player_stats.caster != null:
		d["known_spells"] = player_stats.caster.known_spells.duplicate()
		d["special_slot_spell_id"] = special_slot_spell_id
	character_creation_snapshot = d

# "Try Again" after death: same class/race/scores/masteries/spells, fresh level-1 run (new seed,
# floor 1, starting items) — skips the whole character-creation UI chain. Falls back to a plain
# start_new_run() (character select screen) if no snapshot was ever captured.
func retry_same_character() -> bool:
	if character_creation_snapshot.is_empty():
		start_new_run()
		return false
	var d: Dictionary = character_creation_snapshot
	start_new_run()
	player_stats.character_class = int(d.get("character_class", Stats.CharacterClass.BARBARIAN)) as Stats.CharacterClass
	player_stats.apply_class_defaults()
	var scores: Dictionary = d.get("scores", {})
	if not scores.is_empty():
		player_stats.apply_point_buy_scores(scores)
	give_class_starting_items()
	choose_race(int(d.get("race", Stats.CharacterRace.HUMAN)) as Stats.CharacterRace, int(d.get("race_variant", 0)), int(d.get("race_prof_ability", -1)))
	var masteries: Array = d.get("masteries", [])
	if not masteries.is_empty():
		player_stats.known_weapon_masteries.clear()
		for m: Variant in masteries:
			player_stats.known_weapon_masteries.append(String(m))
		known_masteries_changed.emit()
	if d.has("fighting_style"):
		player_stats.fighting_style = String(d["fighting_style"])
		recalculate_stats()
	if player_stats.caster != null:
		for sid: Variant in d.get("known_spells", []):
			var spell_id: String = String(sid)
			var spell: Spell = SpellDb.get_spell(spell_id)
			if spell == null:
				continue
			if spell.level == 0:
				choose_cantrip(spell_id, true)
			else:
				choose_starting_spell(spell_id, true)
		var special: String = String(d.get("special_slot_spell_id", ""))
		if special != "" and player_stats.caster.known_spells.has(special):
			set_special_slot(special)
	class_selected = true
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	class_chosen.emit(player_stats.character_class)
	return true

func _give_starting_items() -> void:
	var ration := Item.new()
	ration.item_name = "Cooked Meat"
	ration.item_type = Item.Type.FOOD
	ration.food_value = 75
	ration.icon_path = "res://sprites/items/food/meat_cooked.png"
	ration.description = "Roasted over a fire trap."
	ration.quantity = 3
	add_item(ration)

	var tools := Item.new()
	tools.item_name = "Thief Tools"
	tools.item_type = Item.Type.TOOL
	tools.icon_path = "res://sprites/items/misc/key_iron.png"
	tools.description = "Left-click to use, then click an adjacent revealed trap to disarm. Consumed on failure."
	tools.quantity = 3
	add_item(tools)

	var potion := Item.new()
	potion.item_name = "Health Potion"
	potion.item_type = Item.Type.POTION
	potion.icon_path = "res://sprites/items/potions/health/medium.png"
	potion.description = "Restores 2d4+CON HP"
	potion.heal_dice_count = 2
	potion.heal_dice_sides = 4
	potion.quantity = 3
	add_item(potion)

# Called by class_select.gd's _on_class_selected() every time a class is (re)confirmed — including
# re-picking a DIFFERENT class after using the Custom flow's Back navigation. give_class_starting_
# items() only ever grants gear once (guarded on equipment/ability-bar slot 0 being empty), so
# without this wipe, going back to class_select and choosing a different class would silently keep
# the OLD class's weapon/abilities/talents while apply_class_defaults() reset only the ability
# scores. Safe to call even on a first-ever class pick (everything is already empty). The player
# can never observe any of this mid-wipe — input is hard-gated on class_selected, which stays
# false for the entire Custom flow now (see character_summary.gd).
func reset_for_class_reselect() -> void:
	player_stats = Stats.new()
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
	talent_points = {1: 0, 2: 0, 3: 0, 4: 0}
	talent_investments = {}
	_class_talents = []
	tier2_unlocked = false
	subclass_chosen = false
	active_tier2_subclass = "Berserker"
	hit_dice = 1
	special_slot_spell_id = ""
	pending_point_buy_scores = {}
	pending_background_bonus = {}
	warlock_invocations_known = []
	warlock_invocation_slots_pending = 0
	_give_starting_items()

# Wipes a Wizard's onboarding cantrip/starting-spell pick (known/prepared spells, their ability-bar
# entries, and the Special slot) so cantrip_select.gd can be safely re-entered — either round 1's
# own Back button returning to round 1, or character_summary.gd's "Take me back" re-opening the
# whole picker from scratch — without leaving a stale first pick alongside the new one (choose_
# cantrip()/choose_starting_spell() only ever APPEND to known_spells, they never replace). No-op-
# safe to call on a fresh Wizard that hasn't picked anything yet.
# Called by class_select.gd after player picks a class, replaces generic starting gear.
func give_class_starting_items() -> void:
	if equipment.get("melee") != null or player_ability_bar[0] != null:
		return
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN:
			_give_barbarian_starting_items()
			_setup_barbarian_talents()
		Stats.CharacterClass.RANGER:
			_give_ranger_starting_items()
			_setup_ranger_talents()
		Stats.CharacterClass.MONK:
			_give_monk_starting_items()
		Stats.CharacterClass.WIZARD:
			_give_wizard_starting_items()
		Stats.CharacterClass.WARLOCK:
			_give_warlock_starting_items()
		Stats.CharacterClass.FIGHTER:
			_give_fighter_starting_items()
		Stats.CharacterClass.HYBRID:
			_give_hybrid_starting_items()
		Stats.CharacterClass.RAMPAGER:
			_give_rampager_starting_items()

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
	# Darkvision/FOV bonus and anything else derived from the race pick only take effect on
	# DungeonFloor's next update_fog() call, which otherwise doesn't happen until the player's
	# first move — reuse equipment_changed (dungeon_floor.gd already listens to it and calls
	# update_fog() immediately; hud.gd's AC label also listens, harmless no-op there since race
	# doesn't touch AC) so the FOV ring is correct the instant race select confirms.
	equipment_changed.emit()

# Called once by choose_race() at the actual race pick — grants full starting uses. Elf sub-race
# spells are still deferred — see root CLAUDE.md's "Race system". Dragonborn grants Breath Weapon
# immediately (level 1, full uses) and Draconic Flight once character_level >= 5 (see
# scripts/entities/CLAUDE.md's "Dragonborn" section); Dwarf grants Stonecunning immediately (level
# 1, full uses — see that file's "Dwarf" section); Human grants Heroic Inspiration immediately
# (level 1, 1 use — see that file's "Human" section); Orc grants Adrenaline Rush immediately
# (level 1, full uses — see that file's "Orc" section). Save-load replay uses
# _restore_race_ability_bar() instead (below) — it must NOT re-run this uses-reset logic, since by
# the time it runs Stats.from_dict() has already restored the true saved uses count.
func give_race_starting_items() -> void:
	match player_stats.character_race:
		Stats.CharacterRace.ORC:
			if _find_ability_by_id("adrenaline_rush") == null:
				player_stats.adrenaline_rush_uses_remaining = player_stats.proficiency_bonus
				add_ability(_build_adrenaline_rush_ability())
		Stats.CharacterRace.DRAGONBORN:
			if _find_ability_by_id("breath_weapon") == null:
				player_stats.breath_weapon_uses_remaining = player_stats.proficiency_bonus
				add_ability(_build_breath_weapon_ability())
			if player_stats.character_level >= 5 and _find_ability_by_id("draconic_flight") == null:
				add_ability(_build_draconic_flight_ability())
		Stats.CharacterRace.DWARF:
			if _find_ability_by_id("stonecunning") == null:
				player_stats.stonecunning_uses_remaining = player_stats.proficiency_bonus
				add_ability(_build_stonecunning_ability())
		Stats.CharacterRace.HUMAN:
			if _find_ability_by_id("heroic_inspiration") == null:
				player_stats.heroic_inspiration_available = true
				add_ability(_build_heroic_inspiration_ability())
		Stats.CharacterRace.TIEFLING:
			_grant_tiefling_legacy_spell(_tiefling_legacy_spell_for(player_stats.race_variant, 1))
		Stats.CharacterRace.GNOME:
			_grant_gnome_lineage_spells()
		Stats.CharacterRace.AASIMAR:
			if _find_ability_by_id("healing_hands") == null:
				player_stats.aasimar_healing_hands_available = true
				add_ability(_build_healing_hands_ability())
			if _find_ability_by_id("spell:light") == null:
				add_ability(_build_spell_ability("light"))
			if player_stats.character_level >= 3 and _find_ability_by_id("celestial_revelation") == null:
				add_ability(_build_celestial_revelation_ability())
		Stats.CharacterRace.GOLIATH:
			if player_stats.character_level >= 5 and _find_ability_by_id("large_form") == null:
				add_ability(_build_large_form_ability())
			if _find_ability_by_id("giant_ancestry") == null:
				player_stats.giant_ancestry_uses_remaining = player_stats.proficiency_bonus
				add_ability(_build_giant_ancestry_ability())
		Stats.CharacterRace.HALFLING:
			if _find_ability_by_id("halfling_nimbleness") == null:
				add_ability(_build_halfling_nimbleness_ability())

# from_dict()-only counterpart to give_race_starting_items(): re-adds the race ability-bar
# entries from ALREADY-restored Stats state (player_stats.from_dict() has run by the time this is
# called) without resetting breath_weapon_uses_remaining/draconic_flight_used/
# stonecunning_uses_remaining — _build_*_ability() read those fields directly, and
# _sync_ability_uses() (called right after, in from_dict()'s own tail) reconciles
# ab.uses_remaining/uses_max against them one more time regardless.
func _restore_race_ability_bar() -> void:
	match player_stats.character_race:
		Stats.CharacterRace.ORC:
			if _find_ability_by_id("adrenaline_rush") == null:
				add_ability(_build_adrenaline_rush_ability())
		Stats.CharacterRace.DRAGONBORN:
			if _find_ability_by_id("breath_weapon") == null:
				add_ability(_build_breath_weapon_ability())
			if player_stats.character_level >= 5 and _find_ability_by_id("draconic_flight") == null:
				add_ability(_build_draconic_flight_ability())
		Stats.CharacterRace.DWARF:
			if _find_ability_by_id("stonecunning") == null:
				add_ability(_build_stonecunning_ability())
		Stats.CharacterRace.HUMAN:
			if _find_ability_by_id("heroic_inspiration") == null:
				add_ability(_build_heroic_inspiration_ability())
		Stats.CharacterRace.ELF:
			for sid: String in player_stats.elf_lineage_spell_ids:
				if _find_ability_by_id("spell:" + sid) == null:
					add_ability(_build_spell_ability(sid))
		Stats.CharacterRace.TIEFLING:
			for tsid: String in player_stats.tiefling_legacy_spell_ids:
				if tsid == "hellish_rebuke":
					if _find_ability_by_id("hellish_rebuke_toggle") == null:
						add_ability(_build_hellish_rebuke_ability())
				elif _find_ability_by_id("spell:" + tsid) == null:
					add_ability(_build_spell_ability(tsid))
		Stats.CharacterRace.GNOME:
			for gsid: String in player_stats.gnome_lineage_spell_ids:
				if _find_ability_by_id("spell:" + gsid) == null:
					add_ability(_build_spell_ability(gsid))
		Stats.CharacterRace.AASIMAR:
			if _find_ability_by_id("healing_hands") == null:
				add_ability(_build_healing_hands_ability())
			if _find_ability_by_id("spell:light") == null:
				add_ability(_build_spell_ability("light"))
			if player_stats.character_level >= 3 and _find_ability_by_id("celestial_revelation") == null:
				add_ability(_build_celestial_revelation_ability())
		Stats.CharacterRace.GOLIATH:
			if player_stats.character_level >= 5 and _find_ability_by_id("large_form") == null:
				add_ability(_build_large_form_ability())
			if _find_ability_by_id("giant_ancestry") == null:
				add_ability(_build_giant_ancestry_ability())
		Stats.CharacterRace.HALFLING:
			if _find_ability_by_id("halfling_nimbleness") == null:
				add_ability(_build_halfling_nimbleness_ability())

## Elven Lineage (scripts/entities/CLAUDE.md's "Elf" section): which spell each sub-race's lineage
## grants at character level 3 vs. 5. Misty Step (High Elf, level 5) is the one lineage spell that
## also exists as a real Wizard/Ranger leveled spell — reused verbatim, no separate copy needed.
func _elf_lineage_spell_for(subrace: int, threshold_level: int) -> String:
	match subrace:
		Stats.ElfSubrace.DROW:
			return "faerie_fire" if threshold_level == 3 else "darkness"
		Stats.ElfSubrace.HIGH_ELF:
			return "detect_magic" if threshold_level == 3 else "misty_step"
		Stats.ElfSubrace.WOOD_ELF:
			return "longstrider" if threshold_level == 3 else "pass_without_trace"
		_:
			return ""

## Fiendish Legacy (scripts/entities/CLAUDE.md's "Tiefling" section): which spell each legacy
## grants at character level 1 (cantrip)/3 (1st-level)/5 (2nd-level). Fire Bolt (Infernal, level 1)
## and False Life/Darkness (Chthonic level 3 / Infernal level 5) reuse the existing Wizard cantrip
## and Wizard/Elf-lineage leveled spells verbatim, same "no separate copy needed" precedent as
## Elven Lineage's own Misty Step reuse above.
func _tiefling_legacy_spell_for(legacy: int, threshold_level: int) -> String:
	match legacy:
		Stats.TieflingLegacy.ABYSSAL:
			if threshold_level == 1: return "poison_spray"
			return "ray_of_sickness" if threshold_level == 3 else "hold_person"
		Stats.TieflingLegacy.CHTHONIC:
			if threshold_level == 1: return "chill_touch"
			return "false_life" if threshold_level == 3 else "ray_of_enfeeblement"
		Stats.TieflingLegacy.INFERNAL:
			if threshold_level == 1: return "fire_bolt"
			return "hellish_rebuke" if threshold_level == 3 else "darkness"
		_:
			return ""

## Gnomish Lineage (scripts/entities/CLAUDE.md's "Gnome" section): which spell(s) each lineage
## grants, all immediately at race select (unlike Elf/Tiefling's level-3/5 staggering — Gnomish
## Lineage doesn't scale with character level).
func _gnome_lineage_spells_for(lineage: int) -> Array[String]:
	var out: Array[String] = []
	match lineage:
		Stats.GnomeLineage.FOREST:
			out.append("minor_illusion")
			out.append("speak_with_animals")
		Stats.GnomeLineage.ROCK:
			out.append("mending")
	return out

## Grants every Gnomish Lineage spell for the player's chosen lineage — ALWAYS PREPARED, outside
## known_spells/prepared_spells/SpellcasterState bookkeeping (same shape as Elven Lineage/Fiendish
## Legacy), each with its own proficiency_bonus-per-long-rest free-cast counter instead of a single
## free-cast bool. Idempotent — safe to call again (e.g. via _restore_race_ability_bar() replay).
func _grant_gnome_lineage_spells() -> void:
	for spell_id: String in _gnome_lineage_spells_for(player_stats.race_variant):
		if spell_id in player_stats.gnome_lineage_spell_ids:
			continue
		player_stats.gnome_lineage_spell_ids.append(spell_id)
		player_stats.gnome_lineage_free_casts_remaining[spell_id] = player_stats.proficiency_bonus
		if _find_ability_by_id("spell:" + spell_id) == null:
			add_ability(_build_spell_ability(spell_id))
		var spell: Spell = SpellDb.get_spell(spell_id)
		if spell != null:
			game_log("[color=lime]Gnomish Lineage grants you %s![/color]" % spell.spell_name)

## Grants a Fiendish Legacy spell — ALWAYS PREPARED, outside known_spells/prepared_spells/
## SpellcasterState bookkeeping, exactly mirroring _grant_elf_lineage_spell() above. Idempotent.
## Grants exactly 1 free cast per long rest (see _grant_elf_lineage_spell()'s own comment).
func _grant_tiefling_legacy_spell(spell_id: String) -> void:
	if spell_id == "" or spell_id in player_stats.tiefling_legacy_spell_ids:
		return
	_migrate_spell_out_of_known_bookkeeping(spell_id)
	player_stats.tiefling_legacy_spell_ids.append(spell_id)
	player_stats.tiefling_legacy_free_casts_remaining[spell_id] = 1
	# Hellish Rebuke is a toggle-armed reaction, not a normal on-demand cast — see Stats.
	# hellish_rebuke_armed's own comment and scripts/entities/CLAUDE.md's "Tiefling" section.
	if spell_id == "hellish_rebuke":
		if _find_ability_by_id("hellish_rebuke_toggle") == null:
			add_ability(_build_hellish_rebuke_ability())
	elif _find_ability_by_id("spell:" + spell_id) == null:
		add_ability(_build_spell_ability(spell_id))
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell != null:
		game_log("[color=lime]Fiendish Legacy grants you %s![/color]" % spell.spell_name)

func _build_hellish_rebuke_ability() -> Ability:
	var spell: Spell = SpellDb.get_spell("hellish_rebuke")
	var ab := Ability.new()
	ab.ability_id = "hellish_rebuke_toggle"
	ab.ability_name = spell.spell_name if spell != null else "Hellish Rebuke"
	ab.description = SpellTooltip.build(spell) if spell != null else ""
	ab.icon_path = spell.icon_path if spell != null else ""
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab

func _build_hail_of_thorns_ability() -> Ability:
	var spell: Spell = SpellDb.get_spell("hail_of_thorns")
	var ab := Ability.new()
	ab.ability_id = "hail_of_thorns_toggle"
	ab.ability_name = spell.spell_name if spell != null else "Hail of Thorns"
	ab.description = SpellTooltip.build(spell) if spell != null else ""
	ab.icon_path = spell.icon_path if spell != null else ""
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab

func _build_ensnaring_strike_ability() -> Ability:
	var spell: Spell = SpellDb.get_spell("ensnaring_strike")
	var ab := Ability.new()
	ab.ability_id = "ensnaring_strike_toggle"
	ab.ability_name = spell.spell_name if spell != null else "Ensnaring Strike"
	ab.description = SpellTooltip.build(spell) if spell != null else ""
	ab.icon_path = spell.icon_path if spell != null else ""
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab


## Pulls `spell_id` OUT of the caster's normal known_spells/prepared_spells bookkeeping and drops
## its existing ability-bar entry (regardless of which system put it there) — called right before
## a lineage/legacy grant takes over a spell the player already learned normally (e.g. a Ranger who
## picked Pass Without Trace from the level-up spell-learn picker, then hits Wood Elf's own level-5
## grant for the same spell). Without this, the spell would be tracked by BOTH the normal Spellbook
## prepare/unprepare flow AND the lineage always-prepared flow at once — the two systems fighting
## over the same ability_id is exactly what used to let it end up duplicated on the ability bar
## (learned+prepared once via the level-up picker, then a second independent copy added by the
## lineage grant once it found no CURRENT ability-bar entry, e.g. because the spell had since been
## unprepared). A no-op for a spell that was never known normally (nothing to migrate).
func _migrate_spell_out_of_known_bookkeeping(spell_id: String) -> void:
	_remove_ability_by_id("spell:" + spell_id)
	var caster: SpellcasterState = player_stats.caster
	if caster == null:
		return
	if spell_id in caster.known_spells or spell_id in caster.prepared_spells:
		caster.known_spells.erase(spell_id)
		caster.prepared_spells.erase(spell_id)
		spell_slots_changed.emit()

## Grants a lineage spell — ALWAYS PREPARED, outside the normal known_spells/prepared_spells/
## SpellcasterState bookkeeping entirely (never counts against a caster's known-cantrip or
## prepared-spell cap; works even for a non-caster class). Idempotent — safe to call again
## (gain_exp()'s own old_level < N guard already prevents a double-grant in practice, but
## _restore_race_ability_bar() above may re-run this indirectly via save/load replay). Grants
## exactly 1 free cast per long rest (not proficiency_bonus — direct owner correction, matching
## Hunter's Mark's own "free once, then costs the real resource" framing) before falling back to a
## real spell slot of the spell's own level.
func _grant_elf_lineage_spell(spell_id: String) -> void:
	if spell_id == "" or spell_id in player_stats.elf_lineage_spell_ids:
		return
	_migrate_spell_out_of_known_bookkeeping(spell_id)
	player_stats.elf_lineage_spell_ids.append(spell_id)
	player_stats.elf_lineage_free_casts_remaining[spell_id] = 1
	if _find_ability_by_id("spell:" + spell_id) == null:
		add_ability(_build_spell_ability(spell_id))
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell != null:
		game_log("[color=lime]Elven Lineage grants you %s![/color]" % spell.spell_name)

## High Elf lineage (level-1 benefit): "when long resting you may change 1 cantrip from your
## chosen/known ones and change it for one from the Wizard spell list you don't know yet." Only
## meaningful for a High Elf who's actually a Wizard (cantrips don't exist for any other class) —
## a non-caster High Elf simply has nothing to swap, a documented no-op (same "narrow case, not the
## full system" precedent as other race features with no hook to grab onto yet). Reachable only
## from the long-rest hub (scripts/ui/high_elf_cantrip_swap.gd), same "changeable only at a long
## rest" gating as Attunement/Weapon Masteries.
func is_high_elf_caster() -> bool:
	return player_stats.character_race == Stats.CharacterRace.ELF \
		and player_stats.race_variant == Stats.ElfSubrace.HIGH_ELF \
		and player_stats.caster != null

func high_elf_known_cantrips() -> Array[String]:
	if player_stats.caster == null:
		return []
	var out: Array[String] = []
	for sid: String in player_stats.caster.known_spells:
		if SpellDb.get_spell(sid) != null and SpellDb.get_spell(sid).level == 0:
			out.append(sid)
	return out

func high_elf_learnable_cantrips() -> Array[String]:
	if player_stats.caster == null:
		return []
	var known: Array[String] = high_elf_known_cantrips()
	var out: Array[String] = []
	for sid: String in SpellDb.CANTRIP_IDS:
		if sid not in known:
			out.append(sid)
	return out

func swap_high_elf_cantrip(old_id: String, new_id: String) -> bool:
	if not is_high_elf_caster():
		return false
	var caster: SpellcasterState = player_stats.caster
	if old_id not in caster.known_spells or new_id in caster.known_spells:
		return false
	var was_prepared: bool = caster.prepared_spells.has(old_id)
	caster.known_spells.erase(old_id)
	caster.prepared_spells.erase(old_id)
	_remove_ability_by_id("spell:" + old_id)
	caster.known_spells.append(new_id)
	if was_prepared:
		caster.prepared_spells.append(new_id)
		add_ability(_build_spell_ability(new_id))
	if special_slot_spell_id == old_id:
		set_special_slot(new_id)
	var old_spell: Spell = SpellDb.get_spell(old_id)
	var new_spell: Spell = SpellDb.get_spell(new_id)
	game_log("[color=lime]High Elf Cantrip Swap: %s replaced with %s.[/color]" % [
		old_spell.spell_name if old_spell != null else old_id,
		new_spell.spell_name if new_spell != null else new_id])
	return true

func _build_stonecunning_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "stonecunning"
	ab.ability_name = "Stonecunning"
	ab.description = "Gain Tremorsense for up to 100 turns: sense any living creature within %d tiles standing on the same terrain type as you, even through walls/darkness/blindness — shown as a red tremor ping, not a clear sighting. Costs a Bonus Action." % Stats.STONECUNNING_RANGE
	ab.icon_path = "res://icons/races/dwarf/stonecunning.png"
	ab.uses_remaining = player_stats.stonecunning_uses_remaining
	ab.uses_max = player_stats.proficiency_bonus
	return ab

func _build_adrenaline_rush_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "adrenaline_rush"
	ab.ability_name = "Adrenaline Rush"
	# BUGFIX: this used to bake the CURRENT proficiency_bonus straight into the description text
	# ("2 uses") at grant time — _sync_ability_uses() keeps ab.uses_max itself live on every
	# proficiency-bonus level-up crossing, but never regenerates ab.description, so the hover
	# tooltip's own copy of the number went stale the moment proficiency_bonus grew (levels 5/9/
	# 13/17). Rule text now describes the SCALING rule instead of a snapshot number — same
	# "describe the rule, not a number" pattern _build_breath_weapon_ability()/
	# _build_stonecunning_ability() already use, and the ability-bar's own "X/Y" badge (which reads
	# uses_remaining/uses_max live) already shows the actual current numbers regardless.
	ab.description = "Gain temporary HP equal to your proficiency bonus and dash one tile for free. Costs a Bonus Action, uses = your proficiency bonus — refills on short rest AND long rest."
	ab.icon_path = "res://icons/races/orc/adrenaline_rush.png"
	ab.uses_remaining = player_stats.adrenaline_rush_uses_remaining
	ab.uses_max = player_stats.proficiency_bonus
	return ab

func _build_heroic_inspiration_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "heroic_inspiration"
	ab.ability_name = "Heroic Inspiration"
	ab.description = "Your very next d20 roll (attack, check, or save) is guaranteed to succeed as a critical natural 20. Costs a Bonus Action, 1 use per long rest."
	ab.icon_path = "res://icons/races/human/heroic_inspiration.png"
	ab.uses_remaining = 1 if player_stats.heroic_inspiration_available else 0
	ab.uses_max = 1
	return ab

func _build_healing_hands_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "healing_hands"
	ab.ability_name = "Healing Hands"
	ab.description = "Costs your action. Touch a creature (yourself or your companion) to heal 1d4 × your proficiency bonus (%d) HP. 1 use per long rest." % player_stats.proficiency_bonus
	ab.icon_path = "res://icons/races/aasimar/healing_hands.png"
	ab.uses_remaining = 1 if player_stats.aasimar_healing_hands_available else 0
	ab.uses_max = 1
	return ab

func _build_celestial_revelation_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "celestial_revelation"
	ab.ability_name = "Celestial Revelation"
	ab.description = "Costs a Bonus Action. Choose Heavenly Wings, Inner Radiance, or Necrotic Shroud — press to cycle the choice, click anywhere to activate. For 10 turns, the first damage you deal each turn is boosted by your proficiency bonus (%d). 1 use per long rest." % player_stats.proficiency_bonus
	ab.icon_path = "res://icons/races/aasimar/celestial_revelation.png"
	ab.uses_remaining = 0 if player_stats.aasimar_celestial_revelation_used else 1
	ab.uses_max = 1
	return ab

func _build_breath_weapon_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "breath_weapon"
	ab.ability_name = "Breath Weapon"
	# Structured readout mirroring SpellTooltip.build()'s fixed-line format (Casting Time / Range /
	# Area / Duration), so hovering Breath Weapon shows its ranges/area the same way a spell does,
	# fixed lines glued with non-breaking spaces so they never word-wrap.
	var _bw_type: String = Stats.DRAGONBORN_DAMAGE_TYPE[clampi(player_stats.race_variant, 0, Stats.DRAGONBORN_DAMAGE_TYPE.size() - 1)]
	var _bw_lines: Array[String] = [
		"Casting Time: Action",
		"Range: Self",
		"Area: %d-tile Cone or %d-tile Line" % [PlayerDragonborn.BREATH_CONE_LENGTH, PlayerDragonborn.BREATH_LINE_LENGTH],
		"Duration: Instantaneous",
	]
	var _nbsp: String = String.chr(0x00A0)
	for _i: int in _bw_lines.size():
		_bw_lines[_i] = _bw_lines[_i].replace(" ", _nbsp)
	ab.description = "\n".join(_bw_lines) + "\n%dd10 %s damage, DEX save for half. Uses = your proficiency bonus, refilled on a long rest. Click to arm (Cone), click again to switch to Line, once more to cancel, then click a direction to fire." % [
		player_stats.breath_weapon_dice_count(), _bw_type]
	ab.icon_path = "res://icons/races/dragonborn/breath_weapon.png"
	ab.uses_remaining = player_stats.breath_weapon_uses_remaining
	ab.uses_max = player_stats.proficiency_bonus
	return ab

func _build_draconic_flight_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "draconic_flight"
	ab.ability_name = "Draconic Flight"
	ab.description = "Take to the air for up to 100 turns: cross chasms, never trample grass, never trigger traps, and ignore standing-on-fire damage. Costs a Bonus Action, 1/long rest."
	ab.icon_path = "res://icons/races/dragonborn/draconic_flight.png"
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab

func _build_large_form_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "large_form"
	ab.ability_name = "Large Form"
	ab.description = "Grow to Large size for up to 100 turns (needs a free 2x2 space): Advantage on STR checks, +1/3 movement speed. Press again to end early (free). Costs a Bonus Action to activate, 1/long rest."
	ab.icon_path = "res://icons/races/goliath/large_form.png"
	ab.uses_remaining = 0 if player_stats.large_form_used else 1
	ab.uses_max = 1
	return ab

## Giant Ancestry's own flavor/effect text, per Stats.GiantAncestry — shown on the single
## activatable ability every Goliath gets (see player_goliath.gd / scripts/entities/CLAUDE.md's
## "Goliath" section).
func _giant_ancestry_name(variant: int) -> String:
	match variant:
		Stats.GiantAncestry.CLOUD: return "Cloud's Jaunt"
		Stats.GiantAncestry.FIRE:  return "Fire's Burn"
		Stats.GiantAncestry.FROST: return "Frost's Chill"
		Stats.GiantAncestry.HILL:  return "Hill's Tumble"
		Stats.GiantAncestry.STONE: return "Stone's Endurance"
		Stats.GiantAncestry.STORM: return "Storm's Thunder"
		_: return "Giant Ancestry"

func _giant_ancestry_description(variant: int) -> String:
	match variant:
		Stats.GiantAncestry.CLOUD:
			return "Costs a Bonus Action: teleport up to 3 tiles to an unoccupied space you can see. %d uses/long rest." % player_stats.proficiency_bonus
		Stats.GiantAncestry.FIRE:
			return "Arm, then your next attack that hits also deals +1d10 Fire damage (a miss doesn't spend a charge). %d uses/long rest." % player_stats.proficiency_bonus
		Stats.GiantAncestry.FROST:
			return "Arm, then your next attack that hits also chills the target, slowing it for a few turns (a miss doesn't spend a charge). %d uses/long rest." % player_stats.proficiency_bonus
		Stats.GiantAncestry.HILL:
			return "Arm, then the next hit you land on a Large-or-smaller creature knocks it Prone (a miss doesn't spend a charge). %d uses/long rest." % player_stats.proficiency_bonus
		Stats.GiantAncestry.STONE:
			return "Arm, then the next damage you take is reduced by 1d12 + your CON modifier. %d uses/long rest." % player_stats.proficiency_bonus
		Stats.GiantAncestry.STORM:
			return "Toggle on, then the next creature that damages you takes 1d8 Thunder damage back. %d uses/long rest." % player_stats.proficiency_bonus
		_:
			return ""

## One icon per Giant Ancestry variant — see icons/races/goliath/giant_ancestry/.
func _giant_ancestry_icon_path(variant: int) -> String:
	match variant:
		Stats.GiantAncestry.CLOUD: return "res://icons/races/goliath/giant_ancestry/cloud.png"
		Stats.GiantAncestry.FIRE:  return "res://icons/races/goliath/giant_ancestry/fire.png"
		Stats.GiantAncestry.FROST: return "res://icons/races/goliath/giant_ancestry/frost.png"
		Stats.GiantAncestry.HILL:  return "res://icons/races/goliath/giant_ancestry/hill.png"
		Stats.GiantAncestry.STONE: return "res://icons/races/goliath/giant_ancestry/stone.png"
		Stats.GiantAncestry.STORM: return "res://icons/races/goliath/giant_ancestry/storm.png"
		_: return ""

func _build_giant_ancestry_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "giant_ancestry"
	ab.ability_name = _giant_ancestry_name(player_stats.race_variant)
	ab.description = _giant_ancestry_description(player_stats.race_variant)
	ab.icon_path = _giant_ancestry_icon_path(player_stats.race_variant)
	ab.uses_remaining = player_stats.giant_ancestry_uses_remaining
	ab.uses_max = player_stats.proficiency_bonus
	return ab

func _build_halfling_nimbleness_ability() -> Ability:
	var ab := Ability.new()
	ab.ability_id = "halfling_nimbleness"
	ab.ability_name = "Nimbleness"
	ab.description = "Slip through the space of a creature larger than you. Click one of the 8 tiles next to you that holds a larger creature to come out the other side. Costs a Bonus Action, once per round."
	ab.icon_path = "res://icons/races/halfling/nimbleness.png"
	# uses_max = 0 (infinite/free) — gated by PlayerHalfling.used_this_turn, a per-round flag, not
	# a rest-refilled counter, same shape as Grip of the Forest's "_grip_used_this_turn".
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab

# Wizard's one-time cantrip pick (cantrip_select.gd's round 1, or a premade hero's "cantrip" key
# in character_select.gd). `silent` skips the log line for save/load replay (game_state.gd
# from_dict()), mirroring how talent replay never re-logs old investments. Also auto-assigns the
# picked cantrip into the Special quick-cast slot (owner-requested — always available via
# Alt+click immediately, no separate Spellbook trip needed) — safe to do unconditionally since
# this function only ever runs once per character (the old "2 cantrips" round 2 was repurposed
# into choose_starting_spell()'s level-1 spell pick, see above).
func choose_cantrip(spell_id: String, silent: bool = false) -> void:
	if player_stats.caster == null:
		return
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if not player_stats.caster.known_spells.has(spell_id):
		player_stats.caster.known_spells.append(spell_id)
	if not player_stats.caster.prepared_spells.has(spell_id):
		player_stats.caster.prepared_spells.append(spell_id)
	add_ability(_build_spell_ability(spell_id))
	set_special_slot(spell_id)
	if not silent:
		game_log("[color=lime]You learn %s![/color]" % spell.spell_name)

## Builds the ability-bar Ability wrapper for a known/prepared spell — shared by choose_cantrip(),
## _give_wizard_starting_items(), set_spell_prepared(), place_spell_in_slot(), and save replay.
## uses_max stays 0 for every spell (cantrips are free/infinite; leveled-spell slot state lives on
## SpellcasterState.slot_pool, never in Ability.uses_remaining — see leveled-spells-and-slots-plan.md §5.3).
## Maps a known spell id to its actual ability-bar id — "spell:X" for every normal on-demand-cast
## spell, except Hellish Rebuke, a toggle-armed reaction (see _build_hellish_rebuke_ability() and
## scripts/entities/CLAUDE.md's "Warlock class"/"Tiefling" sections), which keeps its own fixed
## "hellish_rebuke_toggle" id instead. Now a genuinely learnable Warlock spell (not just a Tiefling
## legacy grant), so every "spell:" + id lookup/removal site needs this, not just the Tiefling-
## specific grant path that already special-cased it directly.
func _spell_ability_id(spell_id: String) -> String:
	if spell_id == "hellish_rebuke":
		return "hellish_rebuke_toggle"
	if spell_id == "hail_of_thorns":
		return "hail_of_thorns_toggle"
	if spell_id == "ensnaring_strike":
		return "ensnaring_strike_toggle"
	return "spell:" + spell_id

## Inverse of _spell_ability_id() — "" if `ability_id` isn't a spell-backed ability at all.
func _spell_id_from_ability_id(ability_id: String) -> String:
	if ability_id == "hellish_rebuke_toggle":
		return "hellish_rebuke"
	if ability_id == "hail_of_thorns_toggle":
		return "hail_of_thorns"
	if ability_id == "ensnaring_strike_toggle":
		return "ensnaring_strike"
	if ability_id.begins_with("spell:"):
		return ability_id.trim_prefix("spell:")
	return ""

func _build_spell_ability(spell_id: String) -> Ability:
	if spell_id == "hellish_rebuke":
		return _build_hellish_rebuke_ability()
	if spell_id == "hail_of_thorns":
		return _build_hail_of_thorns_ability()
	if spell_id == "ensnaring_strike":
		return _build_ensnaring_strike_ability()
	var spell: Spell = SpellDb.get_spell(spell_id)
	var ab := Ability.new()
	ab.ability_id = "spell:" + spell_id
	ab.ability_name = spell.spell_name if spell != null else spell_id
	ab.description = SpellTooltip.build(spell) if spell != null else ""
	ab.icon_path = spell.icon_path if spell != null else ""
	ab.uses_remaining = 0
	ab.uses_max = 0
	return ab

## Wizard's starting spell-slot pool — no known spells populated here anymore (owner-requested:
## a Custom Wizard now picks their own single starting level-1 spell via cantrip_select.gd's
## round 2, see choose_starting_spell() below; premade heroes grant one explicitly via their
## PREMADE entry's "spell1" key in character_select.gd).
func _give_wizard_starting_items() -> void:
	if player_stats.caster == null:
		return
	# BUGFIX: slot_pool.remaining otherwise stays {} (no slots at all) until the first long rest
	# or level-up — a level-1 Wizard needs their 2× 1st-level slots available from character
	# creation, not zero. Same population StandardSlotPool.on_long_rest() does.
	if player_stats.caster.slot_pool != null:
		player_stats.caster.slot_pool.remaining = player_stats.caster.slot_pool.max_slots().duplicate()
		spell_slots_changed.emit()

	# Wizard starts with an already-lit Torch in the Off-hand (owner-requested) — same Item
	# shape as the floor-loot Torch (DungeonFloorData.ITEM_POOL), just pre-lit at creation
	# instead of needing a click-to-light.
	var torch := Item.new()
	torch.item_name = "Torch"
	torch.item_type = Item.Type.WEAPON
	torch.icon_path = DungeonFloorData.WEAPONS_PATH + "weapon_torch.png"
	torch.description = "Click while equipped to light it — burns 100 turns, granting +1 FOV and (in Main Hand) +2d4 Fire on hit. Thrown and lodged in an enemy, it sets them ablaze for 2d4 Fire each round until doused or they die, and casts a radius-1 glow around them; lying on the ground it casts a radius-2 glow instead. Can be equipped in either hand like a Shield. Burns out permanently into a Burnt Torch."
	torch.damage_die_min = 1
	torch.damage_die_max = 4
	torch.damage_type = "Bludgeoning"
	torch.weapon_category = "Simple"
	torch.is_torch = true
	torch.is_thrown = true
	torch.range = 2
	torch.long_range = 4
	torch.uses_max = 1
	torch.uses_remaining = 1
	torch.gold_value = 10
	torch.torch_lit = true
	torch.torch_turns_remaining = 600
	equipment["hand2"] = torch
	recalculate_stats()
	equipment_changed.emit()

## Warlock's starting gear + Pact Magic slot seeding — mirrors _give_ranger_starting_items()'s
## half-caster pattern (see scripts/entities/CLAUDE.md's "Warlock class"): a Dagger (Main Hand) +
## Leather Armor, then seeds the freshly-built PactSlotPool the same way Wizard's own
## BUGFIX-seeding comment above does (slot_pool.remaining otherwise stays {} until the first
## short/long rest or level-up).
func _give_warlock_starting_items() -> void:
	equipment["melee"] = _build_ranger_dagger()

	var armor := Item.new()
	armor.item_name = "Leather Armor"
	armor.item_type = Item.Type.ARMOR
	armor.icon_path = "res://sprites/items/materials/plate/iron.png"
	armor.description = ""
	armor.armor_category = Item.ArmorCategory.LIGHT
	armor.base_ac = 11
	armor.dex_cap = -1
	armor.gold_value = 10
	equipment["armor"] = armor

	recalculate_stats()
	equipment_changed.emit()

	if player_stats.caster != null and player_stats.caster.slot_pool != null:
		player_stats.caster.slot_pool.remaining = player_stats.caster.slot_pool.max_slots().duplicate()
		spell_slots_changed.emit()

	# Level 1's own Eldritch Invocation slot — gain_exp()'s threshold-crossing grant only fires on
	# a level-UP (old_level < N and new >= N), which never covers the character's starting level 1
	# itself. Idempotent (character_creation_snapshot's "Try Again" replay calls this again).
	if warlock_invocation_slots_pending == 0 and warlock_invocations_known.is_empty():
		warlock_invocation_slots_pending = WARLOCK_INVOCATION_SCHEDULE.get(1, 0)
		if warlock_invocation_slots_pending > 0:
			invocation_choice_required.emit()

## Wizard's one-time starting level-1 spell pick (cantrip_select.gd's round 2, or a premade
## hero's fixed "spell1" key in character_select.gd) — learns AND prepares it in one call, since
## prepared cap is 1 at level 1 so there's nothing else it could contend with.
func choose_starting_spell(spell_id: String, silent: bool = false) -> void:
	if player_stats.caster == null:
		return
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if not player_stats.caster.known_spells.has(spell_id):
		player_stats.caster.known_spells.append(spell_id)
	set_spell_prepared(spell_id, true)
	if not silent:
		game_log("[color=lime]You learn %s![/color]" % spell.spell_name)

func _give_barbarian_starting_items() -> void:
	# Tier-1 Spear main-hand + 2 thrown Handaxes (weapon-tiers-design.md §6 option (a)) — the
	# Greataxe moved to a real Tier-4 floor-loot entry (DungeonFloorData.ITEM_POOL, fmin=6) instead
	# of guaranteed starting gear; a fresh Barbarian no longer starts with what should be an
	# end-game find. Accepted tradeoff: Greataxe was the only Cleave-mastery weapon in the game, so
	# a Barbarian now has no guaranteed way to use a picked Cleave mastery rank until one drops.
	var spear := Item.new()
	spear.item_name = "Spear"
	spear.item_type = Item.Type.WEAPON
	spear.icon_path = "res://sprites/weapons/weapon_spear.png"
	spear.description = ""
	spear.bonus_damage = 0
	spear.damage_die_min = 1
	spear.damage_die_max = 6
	spear.versatile_die_min = 1
	spear.versatile_die_max = 8
	spear.is_versatile = true
	spear.floor_min = 1
	spear.floor_max = 10
	spear.is_ranged = false
	spear.damage_type = "Piercing"
	spear.weapon_mastery = "Sap"
	spear.weapon_category = "Simple"
	spear.is_thrown = true
	spear.range = 3
	spear.long_range = 12
	spear.uses_max = 5
	spear.uses_remaining = 5
	spear.gold_value = 1
	# Equip silently (no turn cost, no turn consumed — startup)
	equipment["melee"] = spear
	recalculate_stats()
	equipment_changed.emit()

	for _i: int in 2:
		add_item(_build_barbarian_handaxe())

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

func _give_fighter_starting_items() -> void:
	# Sword-and-board starter: a one-handed Simple melee weapon (versatile, so a Dueling/
	# Great-Weapon-Fighting build can still grip it two-handed) + Shield + Chain Shirt (Medium,
	# no STR requirement, capped DEX bonus) — works reasonably for a STR or DEX build alike, since
	# Fighting Style/ability scores are both entirely up to Custom point buy for this class (no
	# fixed stat block — see Stats.apply_class_defaults()'s FIGHTER branch).
	var spear := Item.new()
	spear.item_name = "Spear"
	spear.item_type = Item.Type.WEAPON
	spear.icon_path = "res://sprites/weapons/weapon_spear.png"
	spear.description = ""
	spear.bonus_damage = 0
	spear.damage_die_min = 1
	spear.damage_die_max = 6
	spear.versatile_die_min = 1
	spear.versatile_die_max = 8
	spear.is_versatile = true
	spear.floor_min = 1
	spear.floor_max = 10
	spear.is_ranged = false
	spear.damage_type = "Piercing"
	spear.weapon_mastery = "Sap"
	spear.weapon_category = "Simple"
	spear.is_thrown = true
	spear.range = 3
	spear.long_range = 12
	spear.uses_max = 5
	spear.uses_remaining = 5
	spear.gold_value = 1
	equipment["melee"] = spear

	var shield := Item.new()
	shield.item_name = "Shield"
	shield.item_type = Item.Type.ARMOR
	shield.icon_path = "res://sprites/items/shields/wood.png"
	shield.description = ""
	shield.is_shield = true
	shield.bonus_ac = 2
	shield.gold_value = 40
	equipment["hand2"] = shield

	var armor := Item.new()
	armor.item_name = "Chain Shirt"
	armor.item_type = Item.Type.ARMOR
	armor.icon_path = "res://sprites/items/materials/plate/iron.png"
	armor.description = ""
	armor.armor_category = Item.ArmorCategory.MEDIUM
	armor.base_ac = 13
	armor.dex_cap = 2
	armor.gold_value = 50
	equipment["armor"] = armor

	recalculate_stats()
	equipment_changed.emit()

	# Fighting Style info entry (slot 0 of ability bar) — same "passive, ability-bar entry purely
	# for the icon/tooltip, click just logs a reminder" treatment as Barbarian's Unarmored Defense.
	# The actual pick happens in fighting_style_picker.gd, spawned once mastery_picker.gd's own
	# Learn-mode "pick 3 masteries" round finishes (see that file's _finish_learn()).
	var fs := Ability.new()
	fs.ability_id = "fighting_style"
	fs.ability_name = "Fighting Style"
	fs.description = "Passive: your chosen Fighting Style's effect is always active. Reselectable on every level-up."
	fs.icon_path = "res://sprites/items/misc/key_iron.png"
	fs.uses_remaining = 0
	fs.uses_max = 0
	fs.is_passive = true
	add_ability(fs)

	# Second Wind (D&D 2024, Bonus Action) — slot 1. Uses live on Stats.second_wind_uses_remaining/
	# uses_max (same "real resource, not the free-base-ability uses_max==0 convention" shape as
	# Rage), refilled to max here at character creation, then only on a completed LONG rest
	# (GameState.long_rest()) — see Stats.second_wind_uses_max's own comment.
	player_stats.second_wind_uses_remaining = player_stats.second_wind_uses_max
	var sw := Ability.new()
	sw.ability_id = "second_wind"
	sw.ability_name = "Second Wind"
	sw.description = "Bonus Action. Regain 1d10 + your Fighter level in HP."
	sw.icon_path = "res://sprites/items/misc/key_iron.png"
	sw.uses_remaining = player_stats.second_wind_uses_remaining
	sw.uses_max = player_stats.second_wind_uses_max
	add_ability(sw)

func _build_barbarian_handaxe() -> Item:
	var handaxe := Item.new()
	handaxe.item_name = "Handaxe"
	handaxe.item_type = Item.Type.WEAPON
	handaxe.icon_path = "res://sprites/weapons/weapon_throwing_axe.png"
	handaxe.description = ""
	handaxe.damage_type = "Slashing"
	handaxe.weapon_category = "Simple"
	handaxe.damage_die_min = 1
	handaxe.damage_die_max = 6
	handaxe.weapon_mastery = "Vex"
	handaxe.is_light = true
	handaxe.is_thrown = true
	handaxe.range = 3
	handaxe.long_range = 12
	handaxe.uses_max = 5
	handaxe.uses_remaining = 5
	handaxe.gold_value = 5
	return handaxe

func _give_ranger_starting_items() -> void:
	# Half-caster spell-slot seeding — same BUGFIX reasoning as _give_wizard_starting_items()
	# above: slot_pool.remaining otherwise stays {} until the first long rest/level-up, and the
	# 2024-rules half-caster table already grants slots at character level 1 (HalfCasterSlotPool,
	# scripts/items/half_caster_slot_pool.gd), so a level-1 Ranger needs them available immediately.
	if player_stats.caster != null and player_stats.caster.slot_pool != null:
		player_stats.caster.slot_pool.remaining = player_stats.caster.slot_pool.max_slots().duplicate()
		spell_slots_changed.emit()
	# Two Daggers (Main Hand + Off-hand — immediate dual-wield melee is a fully "correct" Ranger
	# build, not a fallback) plus a Short Bow in the ranged slot — the player picks whichever
	# fits the moment, neither path is favored mechanically.
	var dagger_main := _build_ranger_dagger()
	var dagger_off := _build_ranger_dagger()
	equipment["melee"] = dagger_main
	equipment["hand2"] = dagger_off

	var bow := Item.new()
	bow.item_name = "Short Bow"
	bow.item_type = Item.Type.WEAPON
	bow.icon_path = "res://sprites/items/weapons/bow_arrow.png"
	bow.description = ""
	bow.is_ranged = true
	bow.range = 4
	bow.long_range = 16
	bow.damage_type = "Piercing"
	bow.weapon_category = "Simple"
	bow.damage_die_min = 1
	bow.damage_die_max = 6
	bow.weapon_mastery = "Vex"
	bow.ammo_item_name = "Arrow"
	equipment["ranged"] = bow

	var arrows := Item.new()
	arrows.item_name = "Arrow"
	arrows.item_type = Item.Type.TOOL
	arrows.icon_path = "res://sprites/items/ammo/arrow.png"
	arrows.description = "Ammunition for the Short Bow and Longbow."
	arrows.quantity = 20
	add_item(arrows)

	recalculate_stats()
	equipment_changed.emit()

	# Hunter's Mark ability in slot 0 of ability bar — granted directly like Rage, not
	# talent-gated. Uses tracking lives on Stats.hunters_mark_uses_remaining, not the Ability's
	# own uses_remaining/uses_max (which stay 0/0, matching the cantrip-ability convention).
	var mark := Ability.new()
	mark.ability_id = "hunters_mark"
	mark.ability_name = "Hunter's Mark"
	mark.description = _build_hunters_mark_description()
	mark.icon_path = talent_icon_path("hunters_mark", 1)
	mark.uses_remaining = 0
	mark.uses_max = 0
	add_ability(mark)

func _build_ranger_dagger() -> Item:
	var dagger := Item.new()
	dagger.item_name = "Dagger"
	dagger.item_type = Item.Type.WEAPON
	dagger.icon_path = "res://sprites/weapons/weapon_knife.png"
	dagger.description = ""
	dagger.damage_type = "Piercing"
	dagger.weapon_category = "Simple"
	dagger.damage_die_min = 1
	dagger.damage_die_max = 4
	dagger.weapon_mastery = "Nick"
	dagger.is_finesse = true
	dagger.is_light = true
	dagger.is_thrown = true
	dagger.range = 3
	dagger.long_range = 12
	dagger.uses_max = 5
	dagger.uses_remaining = 5
	return dagger

# ── Hybrid class (docs/architecture/hybrid-class-design.md) ───────────────────
func _give_hybrid_starting_items() -> void:
	equipment["melee"] = _build_ranger_dagger()
	var armor := Item.new()
	armor.item_name = "Leather Armor"
	armor.item_type = Item.Type.ARMOR
	armor.icon_path = "res://sprites/items/materials/plate/iron.png"
	armor.armor_category = Item.ArmorCategory.LIGHT
	armor.base_ac = 11
	armor.dex_cap = -1
	armor.gold_value = 10
	equipment["armor"] = armor
	recalculate_stats()
	equipment_changed.emit()
	_grant_hybrid_abilities_for_level()

func _build_hybrid_ability(id: String) -> Ability:
	var def: Dictionary = HybridAbilityDb.get_def(id)
	var ab := Ability.new()
	ab.ability_id = id
	ab.ability_name = str(def.get("name", id))
	ab.description = "[b]%s[/b]\n%s" % [def.get("name", id), def.get("description", "")]
	ab.icon_path = str(def.get("icon", ""))
	# Deliberately NOT ab.is_passive — a passive Hybrid ability still shows on the bar as a
	# clickable reminder (same treatment as Monk's Unarmored Defense / Martial Arts entries).
	ab.cooldown_max = int(def.get("cooldown", 0))
	ab.essence_cost = int(def.get("essence_cost", 0))
	return ab

# Grants every Hybrid ability the character's level currently entitles them to that isn't already
# on the bar. No pick-1-of-3 growth picker yet (docs §4.4) — auto-grant is the first-pass stand-in.
func _grant_hybrid_abilities_for_level() -> void:
	if player_stats.character_class != Stats.CharacterClass.HYBRID:
		return
	for id: String in HybridAbilityDb.ids_for_level(player_stats.character_level):
		var already := false
		for slot in player_ability_bar:
			if slot != null and (slot as Ability).ability_id == id:
				already = true
				break
		if not already:
			add_ability(_build_hybrid_ability(id))

# ── Rampager class (docs/architecture/rampager-class-design.md) ───────────────
# Same cooldown + nova economy as the Hybrid, Fury in place of Essence, STR-based power.
func _give_rampager_starting_items() -> void:
	# Same starter as the Barbarian today: Tier-1 Spear + 2 thrown Handaxes.
	var spear := Item.new()
	spear.item_name = "Spear"
	spear.item_type = Item.Type.WEAPON
	spear.icon_path = "res://sprites/weapons/weapon_spear.png"
	spear.damage_die_min = 1
	spear.damage_die_max = 6
	spear.versatile_die_min = 1
	spear.versatile_die_max = 8
	spear.is_versatile = true
	spear.floor_min = 1
	spear.floor_max = 10
	spear.damage_type = "Piercing"
	spear.weapon_mastery = "Sap"
	spear.weapon_category = "Simple"
	spear.is_thrown = true
	spear.range = 3
	spear.long_range = 12
	spear.uses_max = 5
	spear.uses_remaining = 5
	spear.gold_value = 1
	equipment["melee"] = spear
	recalculate_stats()
	equipment_changed.emit()
	for _i: int in 2:
		add_item(_build_barbarian_handaxe())
	_grant_rampager_abilities_for_level()

func _build_rampager_ability(id: String) -> Ability:
	var def: Dictionary = RampagerAbilityDb.get_def(id)
	var ab := Ability.new()
	ab.ability_id = id
	ab.ability_name = str(def.get("name", id))
	ab.description = "[b]%s[/b]\n%s" % [def.get("name", id), def.get("description", "")]
	ab.icon_path = str(def.get("icon", ""))
	ab.cooldown_max = int(def.get("cooldown", 0))
	ab.fury_cost = int(def.get("fury_cost", 0))
	return ab

func _grant_rampager_abilities_for_level() -> void:
	if player_stats.character_class != Stats.CharacterClass.RAMPAGER:
		return
	for id: String in RampagerAbilityDb.ids_for_level(player_stats.character_level):
		var already := false
		for slot in player_ability_bar:
			if slot != null and (slot as Ability).ability_id == id:
				already = true
				break
		if not already:
			add_ability(_build_rampager_ability(id))

func _build_hunters_mark_description() -> String:
	var uses: int = Stats.HUNTERS_MARK_USES_MAX
	var lines: Array[String] = []
	lines.append("Mark a visible enemy. Every hit against it (any weapon) deals +1d6 Force damage.")
	lines.append("Moving the mark to a new target costs a use, unless the previous quarry just died and this is your very next turn.")
	lines.append("%d use%s per long rest. Costs a Bonus Action." % [uses, "s" if uses != 1 else ""])
	return "\n".join(lines)

func _give_monk_starting_items() -> void:
	# Monks start unarmed — fists are their weapons.
	# Unarmored Defense passive
	var ud := Ability.new()
	ud.ability_id = "unarmored_defense_monk"
	ud.ability_name = "Unarmored Defense"
	ud.description = "Passive: AC = 10 + DEX + WIS while wearing no armor."
	ud.icon_path = "res://sprites/items/misc/key_iron.png"
	ud.uses_remaining = 0
	ud.uses_max = 0
	ud.is_passive = true
	add_ability(ud)
	# Martial Arts passive — die scales with level (1d6 → 1d8 → 1d10 → 1d12)
	var ma := Ability.new()
	ma.ability_id = "martial_arts"
	ma.ability_name = "Martial Arts"
	ma.description = "Passive, while unarmed or wielding only Monk weapons (Simple, or Martial+Light), unarmored, no shield: Dextrous Attacks (use DEX instead of STR), Martial Arts Die (1d6, replaces a weaker weapon die, scales at levels 5/11/17), Bonus Unarmed Strike (a free extra unarmed strike after your attack lands or misses)."
	ma.icon_path = "res://sprites/items/misc/key_iron.png"
	ma.uses_remaining = 0
	ma.uses_max = 0
	ma.is_passive = true
	add_ability(ma)
	recalculate_stats()
	equipment_changed.emit()

# Monk's Focus (level 2+): grants the three level-2 Focus abilities directly onto the ability bar
# — real activatable abilities (unlike Unarmored Defense/Martial Arts above, which are pure
# passives), each costing 1 Focus Point via GameState.spend_monk_focus(). uses_max stays 0 (the
# "free-base-ability" convention, same as Rage) since the shared Focus pool — not a per-ability
# use count — is what actually gates them; hud.gd shows the live Focus Points count on their slots
# instead of a normal use-count badge (see "Ability bar greying" in scripts/ui/CLAUDE.md).
func _grant_monk_focus_abilities() -> void:
	var fob := Ability.new()
	fob.ability_id = "flurry_of_blows"
	fob.ability_name = "Flurry of Blows"
	fob.description = "1 Focus Point + a Bonus Action. Requires Martial Arts active (unarmed or a Monk weapon, unarmored, no shield). Your next Bonus Unarmed Strike this turn hits twice instead of once."
	fob.icon_path = "res://sprites/items/misc/key_iron.png"
	fob.uses_remaining = 0
	fob.uses_max = 0
	add_ability(fob)

	var pd := Ability.new()
	pd.ability_id = "patient_defense"
	pd.ability_name = "Patient Defense"
	pd.description = "1 Focus Point. Requires being engaged (adjacent to a live enemy). Costs your turn — attacks against you have Disadvantage until the start of your next turn."
	pd.icon_path = "res://sprites/items/misc/key_iron.png"
	pd.uses_remaining = 0
	pd.uses_max = 0
	add_ability(pd)

	var sow := Ability.new()
	sow.ability_id = "step_of_wind"
	sow.ability_name = "Step of the Wind"
	sow.description = "1 Focus Point + a Bonus Action, once per turn. A free 1-tile dash that costs no turn — click (or move into) an adjacent visible, walkable tile."
	sow.icon_path = "res://sprites/items/misc/key_iron.png"
	sow.uses_remaining = 0
	sow.uses_max = 0
	add_ability(sow)

	var um := Ability.new()
	um.ability_id = "uncanny_metabolism"
	um.ability_name = "Uncanny Metabolism"
	um.description = "1/long rest, free action. Roll a Martial Arts die + your Monk level: heal that many HP, and refresh ALL your Focus Points to max."
	um.icon_path = "res://sprites/items/misc/key_iron.png"
	um.uses_remaining = 0
	um.uses_max = 0
	add_ability(um)

func _find_ability_by_id(id: String) -> Ability:
	for slot in player_ability_bar:
		if slot != null and (slot as Ability).ability_id == id:
			return slot as Ability
	return null

func add_ability(ability: Ability) -> bool:
	if ability.is_passive:
		return false
	# Never place two abilities sharing the same ability_id — most call sites already
	# defensively check `_find_ability_by_id(id) == null` before calling this, but
	# set_spell_prepared()/place_spell_in_slot() didn't, which used to let a spell already
	# granted outside known_spells/prepared_spells (an Elf/Tiefling lineage spell) end up
	# duplicated on the bar the moment it was ALSO learned/prepared through the normal
	# spellbook flow. This is the single generic backstop for that whole class of bug.
	for i: int in ABILITY_BAR_SIZE:
		var existing: Ability = player_ability_bar[i] as Ability
		if existing != null and existing.ability_id == ability.ability_id:
			return true
	for i: int in ABILITY_BAR_SIZE:
		if player_ability_bar[i] == null:
			player_ability_bar[i] = ability
			ability_bar_changed.emit()
			return true
	game_log("[color=red]Ability bar is full![/color]")
	return false

## Removes an ability-bar entry by id, if present (leveled-spells-and-slots-plan.md §5.3) — the
## unprepare-a-spell counterpart to add_ability(). No generalized "remove ability" existed before
## this; every other ability-bar entry is permanent for the run.
func _remove_ability_by_id(id: String) -> void:
	for i: int in ABILITY_BAR_SIZE:
		var slot: Ability = player_ability_bar[i] as Ability
		if slot != null and slot.ability_id == id:
			player_ability_bar[i] = null
			ability_bar_changed.emit()
			return

# ── Leveled spells / spellbook (docs/architecture/leveled-spells-and-slots-plan.md) ──────

## Adds `spell_id` to the Wizard's known spellbook (level-up picker choice or scroll-taught).
## Also auto-slots it onto the ability bar if there's room: a cantrip goes straight on (subject to
## SpellcasterState.cantrip_max()); a leveled spell auto-prepares via set_spell_prepared(), which
## itself no-ops past SpellcasterState.prepared_max() — matches the owner-requested "auto-add to
## the spell quickbar, provided I'm not already full" behavior. spell_learn_picker.gd calls this
## on a card click.
func learn_spell(spell_id: String) -> void:
	if player_stats.caster == null:
		return
	var caster: SpellcasterState = player_stats.caster
	var s: Spell = SpellDb.get_spell(spell_id)
	if not caster.known_spells.has(spell_id):
		caster.known_spells.append(spell_id)
	spell_learn_pending = false
	spell_learn_choices.clear()
	if s != null:
		game_log("[color=lime]You add %s to your spellbook.[/color]" % s.spell_name)
		# Learning past the cap (cantrip cap or leveled prepared_max) is allowed — the spell just
		# sits known-but-unselected in the spellbook until the player frees up a slot and prepares
		# it manually (Spellbook overlay), same "known but not selected" shape leveled spells
		# already had. set_spell_prepared() silently no-ops past either cap.
		set_spell_prepared(spell_id, true)

## Wizard-only "Learn" RMB scroll interaction (scripts/items/item_interactions.gd's "learn" id):
## true iff the player is a caster who doesn't already know the scroll's spell. Works on either
## kind of scroll — scroll_spell_id (one-shot cast scrolls) or taught_spell_id. Learning is never
## blocked by the cantrip cap — a cantrip learned past the cap just sits known-but-unprepared in
## the spellbook (same "known but not selected" shape a leveled spell already had past prepared_max),
## see learn_spell()/set_spell_prepared().
func can_learn_scroll_spell(item: Item) -> bool:
	if player_stats == null or player_stats.caster == null:
		return false
	var spell_id: String = item.scroll_spell_id if item.scroll_spell_id != "" else item.taught_spell_id
	if spell_id == "":
		return false
	var caster: SpellcasterState = player_stats.caster
	if caster.known_spells.has(spell_id):
		return false
	# Already granted for free by a racial lineage/legacy (Elf/Tiefling) — same reasoning as
	# _roll_spell_learn_choices()'s own exclusion above.
	if spell_id in player_stats.elf_lineage_spell_ids or spell_id in player_stats.tiefling_legacy_spell_ids:
		return false
	return true

## Starts studying a scroll into the spellbook: a cantrip (level 0) is learned instantly; a leveled
## spell takes 2 real turns per spell level, ticked in player.gd's _on_turn_started(). The scroll is
## only consumed on successful completion — see complete_scroll_learn()/cancel_scroll_learn().
func begin_scroll_learn(item: Item) -> void:
	var spell_id: String = item.scroll_spell_id if item.scroll_spell_id != "" else item.taught_spell_id
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if spell.level <= 0:
		learn_spell(spell_id)
		remove_item(item)
		return
	var turns: int = 2 * spell.level
	scroll_learn_active = true
	scroll_learn_turns_remaining = turns
	scroll_learn_total_turns = turns
	scroll_learn_spell_id = spell_id
	scroll_learn_item = item
	game_log("[color=cyan]You begin studying the scroll... (%d turns)[/color]" % turns)
	# Kick the first countdown tick immediately instead of waiting for the player's next real
	# turn — without this, the countdown only started once the player pressed another key.
	if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
		stealth_check_stillness = true
		TurnManager.begin_player_action()
		TurnManager.on_player_action_complete()

func cancel_scroll_learn(interrupted: bool = false) -> void:
	if interrupted:
		game_log("[color=gray]Your studying is interrupted![/color]")
	scroll_learn_active = false
	scroll_learn_turns_remaining = 0
	scroll_learn_total_turns = 0
	scroll_learn_spell_id = ""
	scroll_learn_item = null

func complete_scroll_learn() -> void:
	var spell_id: String = scroll_learn_spell_id
	var item: Item = scroll_learn_item
	scroll_learn_active = false
	scroll_learn_turns_remaining = 0
	scroll_learn_total_turns = 0
	scroll_learn_spell_id = ""
	scroll_learn_item = null
	learn_spell(spell_id)
	if item != null:
		remove_item(item)

## Reconciles the ability bar's "spell:" entries against the (just-restored) known/prepared lists
## after Stats.from_dict() — abilities are derived state, never serialized as objects (same
## "derive, don't serialize" convention talent replay uses). give_class_starting_items() ran
## earlier in from_dict() and may have added a placeholder starting-spellbook entry that the save
## didn't actually have prepared; this removes anything now-invalid and adds anything missing.
func _rebuild_spell_ability_bar() -> void:
	if player_stats.caster == null:
		return
	var caster: SpellcasterState = player_stats.caster
	# Backward-compat migration: an old save's prepared_spells predates cantrips ever entering it
	# (they used to be forced onto the ability bar unconditionally, regardless of any cap) —
	# treat any known-but-not-yet-prepared cantrip as newly prepared here, capped exactly like a
	# fresh learn would be, so an old save's Wizard keeps their pre-existing cantrips selected
	# without silently exceeding cantrip_max().
	for sid: String in caster.known_spells:
		if caster.is_cantrip(sid) and not caster.prepared_spells.has(sid):
			set_spell_prepared(sid, true)
	for i: int in ABILITY_BAR_SIZE:
		var ab: Ability = player_ability_bar[i] as Ability
		if ab == null:
			continue
		var sid: String = _spell_id_from_ability_id(ab.ability_id)
		if sid != "" and not caster.prepared_spells.has(sid):
			player_ability_bar[i] = null
	for sid: String in caster.prepared_spells:
		if _find_ability_by_id(_spell_ability_id(sid)) == null:
			add_ability(_build_spell_ability(sid))
	ability_bar_changed.emit()

## Rolls up to 3 candidate spells for the level-up learn picker (§4.1) — every level-up, not just
## even ones (owner decision). Candidates: this character's own class spell list
## (SpellDb.CLASS_SPELL_LISTS, keyed by class-enum name — WIZARD or RANGER today, see
## scripts/entities/CLAUDE.md's "Ranger class"), spell.level > 0 (cantrips excluded), spell.level
## <= the highest slot level the character can currently cast (no offering a 4th-level spell at
## character level 5), not already known. Sets spell_learn_pending only if >= 1 candidate exists;
## otherwise logs a gray "nothing new" line — the content-count caveat in
## leveled-spells-and-slots-plan.md §7 means this happens often with only a handful of spells.
func _roll_spell_learn_choices() -> void:
	var caster: SpellcasterState = player_stats.caster
	if caster == null or caster.slot_pool == null:
		return
	var max_level: int = 0
	for lv: int in caster.slot_pool.max_slots():
		max_level = maxi(max_level, lv)
	var class_name_str: String = Stats.CharacterClass.keys()[player_stats.character_class]
	var pool_variant: Variant = SpellDb.CLASS_SPELL_LISTS.get(class_name_str)
	var candidates: Array[String] = []
	if pool_variant == null:
		return
	for sid: String in (pool_variant as Array[String]):
		var s: Spell = SpellDb.get_spell(sid)
		# Skip a spell already granted for free by a racial lineage/legacy (Elf/Tiefling) — offering
		# it here would just be a wasted pick (learn_spell()/set_spell_prepared() would try to
		# prepare it into known_spells/prepared_spells alongside the lineage's own always-prepared
		# copy of the same spell_id; add_ability() now blocks the resulting duplicate ability-bar
		# entry, but there's no reason to ever offer the pick at all).
		var already_lineage_granted: bool = sid in player_stats.elf_lineage_spell_ids or sid in player_stats.tiefling_legacy_spell_ids
		if s != null and s.level > 0 and s.level <= max_level and not caster.known_spells.has(sid) and not already_lineage_granted:
			candidates.append(sid)
	Rng.shuffle(candidates)
	if candidates.is_empty():
		game_log("[color=gray]No new spells available to learn.[/color]")
		return
	spell_learn_choices = candidates.slice(0, mini(3, candidates.size()))
	spell_learn_pending = true

## Toggles whether a known spell — cantrip OR leveled — is prepared/selected (§5.3). Adds/removes
## the matching ability-bar entry. Returns false (no-op) if the spell isn't known, or if preparing
## would exceed the relevant cap: SpellcasterState.cantrip_max() for a cantrip (a known-but-over-cap
## cantrip — e.g. Learned from a scroll past the 3/4/5 known-cantrip cap — sits in known_spells but
## never gets selected until the player frees a slot), SpellcasterState.prepared_max() for a leveled
## spell (unchanged). D&D 2024 note: cantrips can normally only be swapped on a class level-up, not
## selected/deselected freely at will — this Spellbook toggle is a deliberate simplification (direct
## owner request) so a cantrip learned past the cap isn't otherwise permanently unusable.
func set_spell_prepared(spell_id: String, prepared: bool) -> bool:
	var caster: SpellcasterState = player_stats.caster
	if caster == null or not caster.known_spells.has(spell_id):
		return false
	var spell_check: Spell = SpellDb.get_spell(spell_id)
	if spell_check == null:
		return false
	var is_cantrip: bool = spell_check.level == 0
	var cap: int = caster.cantrip_max(player_stats) if is_cantrip else caster.prepared_max(player_stats)
	if prepared:
		if caster.prepared_spells.has(spell_id):
			return true
		var count: int = caster.prepared_cantrip_count() if is_cantrip else caster.prepared_leveled_count()
		if count >= cap:
			return false
		caster.prepared_spells.append(spell_id)
		add_ability(_build_spell_ability(spell_id))
	else:
		if not caster.prepared_spells.has(spell_id):
			return true
		caster.prepared_spells.erase(spell_id)
		_remove_ability_by_id(_spell_ability_id(spell_id))
	spell_slots_changed.emit()
	return true

## Drag-and-drop placement from the Spellbook onto a specific ability-bar slot index
## (leveled-spells-and-slots-plan.md §5.4). Dropping a not-yet-prepared spell both prepares it and
## places it in one motion; dropping an already-prepared spell just repositions it. Whatever
## previously occupied `index` is bumped back on via add_ability() (first empty slot), never lost.
## Caller (spellbook_overlay.gd) is responsible for rejecting drops onto the item quickbar/inventory
## before calling this — see scripts/ui/CLAUDE.md's "Spellbook overlay" section.
func place_spell_in_slot(spell_id: String, index: int) -> bool:
	var caster: SpellcasterState = player_stats.caster
	if caster == null or not caster.known_spells.has(spell_id) or index < 0 or index >= ABILITY_BAR_SIZE:
		return false
	var spell_check: Spell = SpellDb.get_spell(spell_id)
	if spell_check == null:
		return false
	# Dropping a not-yet-prepared/selected spell (cantrip OR leveled) both selects it and places it
	# in one motion — same per-kind cap as set_spell_prepared() above.
	if not caster.prepared_spells.has(spell_id):
		var is_cantrip: bool = spell_check.level == 0
		var cap: int = caster.cantrip_max(player_stats) if is_cantrip else caster.prepared_max(player_stats)
		var count: int = caster.prepared_cantrip_count() if is_cantrip else caster.prepared_leveled_count()
		if count >= cap:
			return false
		caster.prepared_spells.append(spell_id)
	var existing: Ability = _find_ability_by_id(_spell_ability_id(spell_id))
	var displaced: Ability = player_ability_bar[index] as Ability
	if existing != null:
		var old_idx: int = player_ability_bar.find(existing)
		if old_idx == index:
			spell_slots_changed.emit()
			return true   # already sitting exactly there
		if old_idx != -1:
			player_ability_bar[old_idx] = null   # vacate its previous slot before re-homing
	else:
		existing = _build_spell_ability(spell_id)
	player_ability_bar[index] = existing
	if displaced != null and displaced != existing:
		add_ability(displaced)   # bumped entry re-homes to the first empty slot, doesn't vanish
	ability_bar_changed.emit()
	spell_slots_changed.emit()
	return true

## In-game ability-bar reorder (no Spellbook needed) — hud.gd's own press-and-drag on an ActionBar
## slot while showing the ability bar. Plain swap, works for ANY ability (spells included, via the
## same "spell:"-prefixed id — no special-casing needed here since this never changes
## known/prepared state, only bar position).
func swap_ability_slots(a: int, b: int) -> bool:
	if a < 0 or a >= ABILITY_BAR_SIZE or b < 0 or b >= ABILITY_BAR_SIZE or a == b:
		return false
	var tmp: Ability = player_ability_bar[a] as Ability
	player_ability_bar[a] = player_ability_bar[b]
	player_ability_bar[b] = tmp
	ability_bar_changed.emit()
	return true

## Special quick-cast slot: a single spell (cantrip or leveled) assigned from inside the Spellbook
## overlay's own drop target, displayed read-only in the Inventory overlay next to Ranged, and cast
## with Alt+click in player.gd — independent of the ability bar and of prepared_spells (a third,
## lightweight home for a spell reference, not an Item-shaped equipment slot).
signal special_slot_changed()
var special_slot_spell_id: String = ""
var quickbar_hover_thrown_item: Item = null  # transient, not serialized — set/cleared by hud.gd's quickbar slot hover, read by player.gd._update_ranged_range_preview() to show a thrown item's range preview without needing Shift/an equipped ranged weapon

func set_special_slot(spell_id: String) -> bool:
	var caster: SpellcasterState = player_stats.caster
	if caster == null or not caster.known_spells.has(spell_id):
		return false
	# Hellish Rebuke is a toggle-armed reaction (hellish_rebuke_toggle ability), not a normal
	# on-demand cast — PlayerSpellcasting.cast_direct() (the Special slot's Alt+click resolver)
	# only knows how to arm-then-target a spell the normal way, which would bypass the toggle
	# entirely. Its own ability-bar slot (via the Spellbook/level-up learn) is the only way to use it.
	if spell_id == "hellish_rebuke":
		return false
	special_slot_spell_id = spell_id
	special_slot_changed.emit()
	return true

func clear_special_slot() -> void:
	special_slot_spell_id = ""
	special_slot_changed.emit()

## Light cantrip — a real light source, not a cosmetic effect: DungeonFloor.update_fog() unions
## its own shadowcast (radius LIGHT_SOURCE_RADIUS, centered on light_source_pos) into the player's
## visible-tiles set every time fog recomputes, so it genuinely pushes back fog of war around the
## lit object — see scripts/world/CLAUDE.md. Only one instance can be active at a time (5e's Light
## spell is also singular per caster); casting again replaces it outright. `(-1,-1)` = none active.
## Ends on a completed rest (short or long), on descending to the next floor, or the instant the
## lit object is no longer on the floor tile (picked up, or otherwise removed) — checked every
## fog recompute in DungeonFloor.update_fog() via light_source_item's presence in
## get_items_at(light_source_pos). See clear_light_source()'s explicit call sites in
## _on_short_rest_completed()/long_rest()/advance_floor() for the other three end conditions.
signal light_source_changed()
const LIGHT_SOURCE_RADIUS: int = 4
# Torch: radius of the passive light bubble a lit Torch casts while lying on the floor or
# embedded in an enemy (dungeon_floor.gd's DungeonFloor._compute_torch_light_tiles()) — separate
# from the flat +1 FOV bonus an EQUIPPED lit torch grants (has_lit_torch_equipped()).
const TORCH_LIGHT_RADIUS: int = 2
const TORCH_BURN_LIGHT_RADIUS: int = 1  # a lit torch embedded in a creature (not lying on the floor) casts a smaller radius-1 glow around that creature — separate constant from TORCH_LIGHT_RADIUS since the floor-lying case keeps its own bigger radius-2 bubble
var light_source_pos: Vector2i = Vector2i(-1, -1)
var light_source_color: Color = Color.WHITE
var light_source_item: Item = null
## What kind of thing is lit — "item" (default, the original floor-item-only behavior, validity
## checked via light_source_item's presence), "door", "grass", or "barrel" (see spell_effects.gd's
## cast_light_at_tile() — Light can now touch almost anything except terrain/walls/living
## creatures/Mud/Water). DungeonFloor.update_fog() branches on this to decide whether the lit
## thing is still there each recompute; item stays the only kind that carries a live Item ref.
var light_source_kind: String = "item"

func set_light_source(pos: Vector2i, color: Color, item: Item, kind: String = "item") -> void:
	light_source_pos = pos
	light_source_color = color
	light_source_item = item
	light_source_kind = kind
	light_source_changed.emit()

func clear_light_source() -> void:
	if light_source_pos == Vector2i(-1, -1):
		return
	light_source_pos = Vector2i(-1, -1)
	light_source_item = null
	light_source_kind = "item"
	light_source_changed.emit()

## Fog Cloud (leveled spell, Conjuration) — a persistent circular zone, tracked purely as
## position + radius rather than a live Item/Enemy reference (unlike Light/Witch Bolt), since it
## Blinds anyone standing inside it — player OR enemy, not a single caster/target pair. Every
## attack-roll ADV/DISADV chokepoint queries `is_in_fog_cloud()` directly (player_vfx.gd's
## has_advantage(), the disadv_count block at all 8 player attack-roll sites, and
## enemy.gd._resolve_attack_roll()'s extra_adv/extra_disadv params) — see
## scripts/entities/CLAUDE.md's "Fog Cloud" section. Duration uses the generic
## concentration_spell_id mechanism ("fog_cloud") — see Stats.fog_cloud_turns. `(-1,-1)` = none
## active. Explicitly cleared on floor descent (advance_floor()): unlike Light (whose lit Item) or
## Witch Bolt (whose target Enemy) naturally invalidate themselves when the floor reloads, a bare
## position would otherwise silently keep blinding whoever stands at those same coordinates on the
## next floor.
var fog_cloud_pos: Vector2i = Vector2i(-1, -1)
var fog_cloud_radius: int = 0

func is_in_fog_cloud(pos: Vector2i) -> bool:
	if fog_cloud_pos == Vector2i(-1, -1):
		return false
	var d: Vector2i = pos - fog_cloud_pos
	return d.x * d.x + d.y * d.y <= fog_cloud_radius * fog_cloud_radius

func clear_fog_cloud() -> void:
	fog_cloud_pos = Vector2i(-1, -1)
	fog_cloud_radius = 0

## Darkness (Drow lineage spell, level 5) — a second, independent Heavily Obscured zone, same bare
## position+radius shape as Fog Cloud above (Stats.darkness_turns/concentration_spell_id ==
## "darkness" drives its duration). Kept as its own pos/radius pair rather than reusing Fog Cloud's
## fields so both spells can be active at once without one silently overwriting the other.
var darkness_pos: Vector2i = Vector2i(-1, -1)
var darkness_radius: int = 0
## The specific floor Item this Darkness was cast on, if any (null = cast at a bare point, or on a
## worn/equipped/carried item — dungeon_floor.get_item_at() only ever returns an unattended floor
## item). Mirrors light_source_item's own tracking — DungeonFloor.update_fog() clears the whole
## zone the instant this item is no longer at darkness_pos (picked up or otherwise removed), same
## "cast on an object, ends if it's moved/taken" RAW behavior the Light cantrip already has.
var darkness_item: Item = null

func is_in_darkness(pos: Vector2i) -> bool:
	if darkness_pos == Vector2i(-1, -1):
		return false
	var d: Vector2i = pos - darkness_pos
	return d.x * d.x + d.y * d.y <= darkness_radius * darkness_radius

func clear_darkness() -> void:
	darkness_pos = Vector2i(-1, -1)
	darkness_radius = 0
	darkness_item = null

## Heavily Obscured (5e terrain concept — distinct from the Blinded CONDITION it grants below):
## Fog Cloud and Darkness are the two sources of Heavily Obscured terrain today; a further future
## source would extend this function rather than every call site checking multiple zones by hand.
func is_heavily_obscured(pos: Vector2i) -> bool:
	return is_in_fog_cloud(pos) or is_in_darkness(pos)

## Blinded condition: standing in a Heavily Obscured tile grants it to WHOEVER is standing there —
## player or enemy, symmetric, since it's purely positional. Effects (5e text): can't see (auto-
## fails sight-based checks — not modeled, this engine has none), attack rolls against you have
## ADV, your own attack rolls have DISADV (both wired at every attack-roll call site — see
## scripts/entities/CLAUDE.md's "Conditions" section), and see effective_fov_radius() below for
## the "can only see 1 tile" effect. This is the canonical name every ADV/DISADV combat call site
## should use going forward — `is_in_fog_cloud()` above stays as the lower-level positional check
## (still used by the spell's own visual/duration plumbing, where "fog cloud specifically" is the
## more precise concept).
func is_blinded(pos: Vector2i) -> bool:
	return is_heavily_obscured(pos)

## Single source of truth for the player's own FOV radius — used by both DungeonFloor.update_fog()
## (actual fog-of-war) and DungeonFloor.get_visible_enemies() (targeting/Cleave-candidate search),
## so the two can never drift out of sync. Blinded (5e RAW: "can't see") collapses vision to a flat
## 1-tile radius regardless of every other bonus, INCLUDING darkvision — a blinded creature is
## blind, darkvision doesn't help.
func effective_fov_radius(pos: Vector2i) -> int:
	# Devil's Sight (Eldritch Invocation): ignores the vision-collapse-to-1 penalty specifically
	# from standing inside Fog Cloud/Darkness — every other Blinded source (and every other
	# combat-roll ADV/DISADV effect of being Blinded) still applies normally.
	if is_blinded(pos) and not knows_invocation("devils_sight"):
		return 1
	return DungeonFloor.FOV_RADIUS + fov_radius_bonus + celestial_radiance_fov_bonus() + player_stats.darkvision_bonus + (1 if has_lit_torch_equipped() else 0)

## Aasimar Celestial Revelation's Inner Radiance transformation: +2 FOV radius while active — see
## scripts/entities/CLAUDE.md's "Aasimar" section. Applied BEFORE darkvision in the sum above (own
## light source reaching out, same conceptual slot the equipped-torch bonus occupies) and gets its
## own ring color in DungeonFloor's FOV-bonus-ring visuals (see that file's "FOV" section).
func celestial_radiance_fov_bonus() -> int:
	return 2 if (player_stats.celestial_revelation_turns > 0 and player_stats.celestial_revelation_transform == Stats.AasimarTransformation.INNER_RADIANCE) else 0

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

# Monk's Focus spend chokepoint — Flurry of Blows/Patient Defense/Step of the Wind (and any
# future Monk Focus feature) all funnel through this rather than touching monk_focus_points
# directly. Same "invincible skips consumption" invariant as spend_gold() above.
func spend_monk_focus(amount: int) -> bool:
	if invincible:
		return true
	if amount > player_stats.monk_focus_points:
		return false
	player_stats.monk_focus_points -= amount
	ability_bar_changed.emit()
	return true

# Hybrid class Essence spend chokepoint (docs/architecture/hybrid-class-design.md) — same
# "invincible skips consumption" invariant as spend_monk_focus()/spend_gold().
func spend_hybrid_essence(amount: int) -> bool:
	if invincible:
		return true
	if amount > player_stats.hybrid_essence:
		return false
	player_stats.hybrid_essence -= amount
	ability_bar_changed.emit()
	return true

func grant_hybrid_essence(amount: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.HYBRID:
		return
	player_stats.hybrid_essence = mini(player_stats.hybrid_essence + amount, player_stats.hybrid_essence_max)
	ability_bar_changed.emit()

# Rampager Fury — exact clone of hybrid_essence's spend/grant, against Stats.rampager_fury.
func spend_rampager_fury(amount: int) -> bool:
	if invincible:
		return true
	if amount > player_stats.rampager_fury:
		return false
	player_stats.rampager_fury -= amount
	ability_bar_changed.emit()
	return true

func grant_rampager_fury(amount: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.RAMPAGER:
		return
	player_stats.rampager_fury = mini(player_stats.rampager_fury + amount, player_stats.rampager_fury_max)
	ability_bar_changed.emit()

func advance_floor() -> void:
	current_floor += 1
	grant_hybrid_essence(1)  # the slow Essence drip — one per floor descent
	grant_rampager_fury(1)   # the slow Fury drip — one per floor descent
	# Floor descent is no longer a rest — see long_rest() for every long-rest-gated resource.
	# Only floor bookkeeping and terrain reset happen here.
	terrain_ac_bonus = 0  # reset terrain AC; player.gd will reapply on next move
	bruiser_revive_used_this_floor = false
	# Light cantrip: the lit object is left behind on the previous floor — ends on descent.
	clear_light_source()
	# Fog Cloud/Darkness: same reasoning as Light above — the cloud/zone is left behind on the
	# previous floor.
	clear_fog_cloud()
	clear_darkness()
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
	if player_stats.aid_bonus_hp > 0:
		player_stats.max_hp = maxi(1, player_stats.max_hp - player_stats.aid_bonus_hp)
		player_stats.aid_bonus_hp = 0
	if player_companion != null and is_instance_valid(player_companion) and player_companion.stats.aid_bonus_hp > 0:
		player_companion.stats.max_hp = maxi(1, player_companion.stats.max_hp - player_companion.stats.aid_bonus_hp)
		player_companion.stats.aid_bonus_hp = 0
	player_stats.current_hp = player_stats.max_hp
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	clear_light_source()  # Light cantrip — ends on a completed rest, short or long
	player_stats.poison_turns = 0
	player_stats.burning_turns = 0
	player_stats.bleeding_turns = 0
	player_stats.slowed_turns = 0
	player_stats.exhaustion_level = maxi(0, player_stats.exhaustion_level - 1)
	player_status_changed.emit()
	player_stats.rage_uses_remaining = player_stats.rage_uses_max
	player_stats.monk_focus_points = player_stats.monk_focus_points_max
	player_stats.wet_turns = 0
	player_stats.shocked_turns = 0
	player_stats.hybrid_essence = player_stats.hybrid_essence_max  # Hybrid Essence — full on a long rest
	player_stats.rampager_fury = player_stats.rampager_fury_max    # Rampager Fury — full on a long rest
	# Hybrid / Rampager ability cooldowns clear on a long rest.
	for _cd_ab in player_ability_bar:
		if _cd_ab != null:
			(_cd_ab as Ability).cooldown_remaining = 0
	player_stats.uncanny_metabolism_used = false
	player_stats.second_wind_uses_remaining = player_stats.second_wind_uses_max
	player_stats.action_surge_uses_remaining = player_stats.action_surge_uses_max
	player_stats.hunters_mark_uses_remaining = Stats.HUNTERS_MARK_USES_MAX
	player_stats.breath_weapon_uses_remaining = player_stats.proficiency_bonus
	player_stats.draconic_flight_used = false
	player_stats.stonecunning_uses_remaining = player_stats.proficiency_bonus
	if player_stats.concentration_spell_id == "hunters_mark":
		player_stats.concentration_spell_id = ""
	player_stats.hunters_mark_turns = 0
	player_stats.hunters_mark_target = null
	player_stats.hunters_mark_fresh = false
	player_stats.hunters_mark_free_recast_pending = false
	player_stats.hunters_mark_free_recast_available = false
	hit_dice = max_hit_dice()
	short_rests_remaining = max_short_rests
	mastery_reselect_used_this_long_rest = false
	berserker_frenzy_used = false
	berserker_turns_since_frenzy = 0
	scarred_warrior_limit_break_used = false
	player_stats.relentless_endurance_used = false
	player_stats.heroic_inspiration_available = true
	player_stats.adrenaline_rush_uses_remaining = player_stats.proficiency_bonus
	player_stats.aasimar_healing_hands_available = true
	player_stats.aasimar_celestial_revelation_used = false
	player_stats.large_form_used = false
	player_stats.giant_ancestry_uses_remaining = player_stats.proficiency_bonus
	# Elven Lineage / Fiendish Legacy: each lineage spell's free-cast counter refills to exactly 1
	# (a leveled spell falls back to a real spell slot once that 1 use is spent — Gnomish Lineage
	# below stays on the proficiency_bonus counter since its 3 grants are cantrips with no slot
	# fallback at all).
	for elf_sid: String in player_stats.elf_lineage_spell_ids:
		player_stats.elf_lineage_free_casts_remaining[elf_sid] = 1
	for tsid2: String in player_stats.tiefling_legacy_spell_ids:
		player_stats.tiefling_legacy_free_casts_remaining[tsid2] = 1
	# Gnomish Lineage: each lineage spell's free-cast counter refills to proficiency_bonus.
	for gnome_sid: String in player_stats.gnome_lineage_spell_ids:
		player_stats.gnome_lineage_free_casts_remaining[gnome_sid] = player_stats.proficiency_bonus
	# Natural Sleeper activates/locks in on long rest only (not short rest, not floor descent).
	# Form is no longer player-chosen — a random one is rolled every long rest (owner request:
	# simplify/ease the game by removing the manual cycling step).
	wild_heart_sleeper_active = get_talent_rank("expanded_forms") >= 1
	if wild_heart_sleeper_active:
		natural_sleeper_form = Rng.pick(["Owl", "Panther", "Salmon"])
		active_sleeper_form = natural_sleeper_form
		game_log("[color=cyan]Natural Sleeper: you wake — %s Form is active.[/color]" % active_sleeper_form)
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	_sync_ability_uses()
	if player_stats.caster != null and player_stats.caster.slot_pool != null:
		player_stats.caster.slot_pool.on_long_rest()
		spell_slots_changed.emit()
	_consume_food_value(LONG_REST_FOOD_COST)
	if player_stats.mage_armor_active:
		player_stats.mage_armor_active = false
		recalculate_stats()
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
		elif ab.ability_id == "breath_weapon":
			ab.uses_remaining = player_stats.breath_weapon_uses_remaining
			ab.uses_max = player_stats.proficiency_bonus
		elif ab.ability_id == "stonecunning":
			ab.uses_remaining = player_stats.stonecunning_uses_remaining
			ab.uses_max = player_stats.proficiency_bonus
		elif ab.ability_id == "heroic_inspiration":
			ab.uses_remaining = 1 if player_stats.heroic_inspiration_available else 0
			ab.uses_max = 1
		elif ab.ability_id == "adrenaline_rush":
			ab.uses_remaining = player_stats.adrenaline_rush_uses_remaining
			ab.uses_max = player_stats.proficiency_bonus
		elif ab.ability_id == "healing_hands":
			ab.uses_remaining = 1 if player_stats.aasimar_healing_hands_available else 0
			ab.uses_max = 1
		elif ab.ability_id == "celestial_revelation":
			ab.uses_remaining = 0 if player_stats.aasimar_celestial_revelation_used else 1
			ab.uses_max = 1
		elif ab.ability_id == "large_form":
			ab.uses_remaining = 0 if player_stats.large_form_used else 1
			ab.uses_max = 1
		elif ab.ability_id == "giant_ancestry":
			ab.uses_remaining = player_stats.giant_ancestry_uses_remaining
			ab.uses_max = player_stats.proficiency_bonus
		elif ab.ability_id == "second_wind":
			ab.uses_remaining = player_stats.second_wind_uses_remaining
			ab.uses_max = player_stats.second_wind_uses_max
		elif ab.ability_id == "action_surge":
			ab.uses_remaining = player_stats.action_surge_uses_remaining
			ab.uses_max = player_stats.action_surge_uses_max
	ability_bar_changed.emit()

# Ability ids gated behind the shared Bonus Action economy (scripts/entities/CLAUDE.md's "Bonus
# Action economy" section) — checked generically in is_ability_usable()/ability_unusable_reason()
# below as an ADDITIONAL condition on top of each ability's own existing checks, not a replacement.
# "giant_ancestry"/"hail_of_thorns_toggle"/"ensnaring_strike_toggle"/spell-prefixed ids are handled
# separately in _bonus_action_blocks() since their bare ability_id doesn't uniquely identify a
# gated ability (Giant Ancestry is shared by all 6 variants — only Cloud's Jaunt is gated; the two
# toggles only cost the Bonus Action on ARMING, never on disarming; spell abilities are prefixed).
const BONUS_ACTION_ABILITY_IDS: PackedStringArray = [
	"rage", "frenzy", "zealot_strike", "flurry_of_blows", "step_of_wind", "patient_defense",
	"halfling_nimbleness", "adrenaline_rush", "draconic_flight",
	"stonecunning", "large_form", "celestial_revelation", "hunters_mark", "grip_of_the_forest",
	"second_wind",
]

func _bonus_action_blocks(ab: Ability) -> bool:
	if invincible or not bonus_action_used:
		return false
	if ab.ability_id in BONUS_ACTION_ABILITY_IDS:
		return true
	if ab.ability_id == "giant_ancestry":
		return player_stats.race_variant == Stats.GiantAncestry.CLOUD
	# Hail of Thorns/Ensnaring Strike: only ARMING costs the Bonus Action — disarming (pressing
	# again while already armed) must always stay free, so these two aren't in the flat
	# BONUS_ACTION_ABILITY_IDS list above; they need their own armed-state-aware check.
	if ab.ability_id == "hail_of_thorns_toggle":
		return not player_stats.hail_of_thorns_armed
	if ab.ability_id == "ensnaring_strike_toggle":
		return not player_stats.ensnaring_strike_armed
	if ab.ability_id.begins_with("spell:"):
		return ab.ability_id.substr(6) in ["blade_ward", "hex", "misty_step", "expeditious_retreat", "barkskin"]
	return false

## Whether an ability-bar entry can currently be activated — beyond the generic uses_remaining
## pool, several free base-abilities (uses_max == 0, i.e. always "has_uses") are additionally
## gated by external boolean state (a requirement to be raging, a once-per-rest flag, a spent
## Hit Die). Used by hud.gd to grey out slots that LOOK available (infinite uses) but currently
## aren't actionable — never call this to block the actual activation logic in player.gd, each
## ability's own activation function is still the source of truth for its own gate.
func is_ability_usable(ab: Ability) -> bool:
	if not ab.has_uses():
		return false
	# Monk's Extra Attack (level 5+): every ability greys out during the granted second-attack
	# window — nothing but landing that attack (or Wait, which forfeits it) is allowed, matching
	# the same hard block player.gd's _use_quickbar_slot() already applies to actual activation.
	if monk_extra_attack_pending:
		return false
	if _bonus_action_blocks(ab):
		return false
	# Hybrid class — generic cooldown / Essence gate (docs/architecture/hybrid-class-design.md).
	if ab.is_on_cooldown():
		return false
	if ab.essence_cost > 0 and not invincible and player_stats.hybrid_essence < ab.essence_cost:
		return false
	if ab.fury_cost > 0 and not invincible and player_stats.rampager_fury < ab.fury_cost:
		return false
	match ab.ability_id:
		"frenzy":
			return is_raging and not berserker_frenzy_used
		"limit_break":
			return not scarred_warrior_limit_break_used
		"zealot_strike":
			return hit_dice > 0
		"grip_of_the_forest":
			return is_raging and not grip_of_the_forest_used_this_turn
		"halfling_nimbleness":
			return not halfling_nimbleness_used_this_turn
		"hunters_mark":
			# Bonus-action cooldown (Stats.hunters_mark_cast_this_round) — see
			# player_ranger_talents.gd's commit_mark(). Greys the slot for the round, matching
			# Frenzy's own cooldown-greying treatment. Beyond the round cooldown, also greys out
			# once there's no resource left to actually mark a NEW target with: re-clicking the
			# CURRENTLY marked target is always free (just refreshes duration), so a live target
			# alone keeps it usable even at 0 uses/slots — mirrors commit_mark()'s own gating.
			if player_stats.hunters_mark_cast_this_round:
				return false
			if invincible:
				return true
			if player_stats.hunters_mark_target != null and is_instance_valid(player_stats.hunters_mark_target):
				return true
			if player_stats.hunters_mark_free_recast_available:
				return true
			if player_stats.hunters_mark_uses_remaining > 0:
				return true
			var hm_slot_pool = player_stats.caster.slot_pool if player_stats.caster != null else null
			return hm_slot_pool != null and hm_slot_pool.remaining.get(1, 0) > 0
		"draconic_flight":
			return player_stats.character_level >= 5 and not player_stats.draconic_flight_used
		"hellish_rebuke_toggle":
			if player_stats.hellish_rebuke_armed or invincible:
				return true
			if player_stats.is_tiefling_legacy_free_cast_available("hellish_rebuke"):
				return true
			# Warlock's PactSlotPool only ever has ONE key (the current pact slot level, which can
			# be well above 1) — can_cast() is the generic "does this pool have any charge this
			# spell could use" check, unlike the old hardcoded remaining.get(1, 0) look-up, which
			# only ever worked for a Wizard/Ranger whose slot table still keys level 1 by "1".
			return player_stats.caster != null and player_stats.caster.slot_pool != null and player_stats.caster.slot_pool.can_cast(SpellDb.get_spell("hellish_rebuke"))
		"hail_of_thorns_toggle":
			if player_stats.hail_of_thorns_armed or invincible:
				return true
			return player_stats.caster != null and player_stats.caster.slot_pool != null and player_stats.caster.slot_pool.can_cast(SpellDb.get_spell("hail_of_thorns"))
		"ensnaring_strike_toggle":
			if player_stats.ensnaring_strike_armed or invincible:
				return true
			return player_stats.caster != null and player_stats.caster.slot_pool != null and player_stats.caster.slot_pool.can_cast(SpellDb.get_spell("ensnaring_strike"))
		"flurry_of_blows":
			if player_stats.monk_focus_points <= 0 and not invincible:
				return false
			return PlayerMonk.martial_arts_active(equipped_weapon)
		"patient_defense":
			if player_stats.monk_focus_points <= 0 and not invincible:
				return false
			return PlayerMonk.is_engaged()
		"step_of_wind":
			if step_of_wind_used_this_turn:
				return false
			return invincible or player_stats.monk_focus_points > 0
		"uncanny_metabolism":
			return invincible or not player_stats.uncanny_metabolism_used
	if ab.ability_id.begins_with("spell:"):
		return can_cast_spell_now(ab.ability_id.substr(6))
	return true

## Whether a known spell (cantrip or leveled, referenced by its "spell:<id>" ability-bar entry)
## currently has any way to actually be cast — a free racial/lineage/invocation cast still
## remaining, ritual casting, or a real spell slot of its own level. Used by is_ability_usable()
## to grey out a spell whose free uses ran dry AND has no backing spell slot left, until either
## refreshes (long rest, or a short rest for Warlock's Pact Magic). Mirrors begin_cast()'s own
## gating checks (scripts/entities/player_spellcasting.gd) without needing a live Player reference.
func can_cast_spell_now(spell_id: String) -> bool:
	if invincible:
		return true
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return true
	if spell.level == 0:
		if spell_id in player_stats.gnome_lineage_spell_ids:
			return player_stats.is_gnome_lineage_free_cast_available(spell_id)
		return true
	if spell.is_ritual:
		return true
	if player_stats.is_lineage_free_cast_available(spell_id):
		return true
	if warlock_invocation_free_cast(spell_id):
		return true
	if spell_id in player_stats.gnome_lineage_spell_ids and player_stats.is_gnome_lineage_free_cast_available(spell_id):
		return true
	var caster: SpellcasterState = player_stats.caster
	return caster != null and caster.slot_pool != null and caster.slot_pool.can_cast(spell)

## Short red-text reason shown directly on an ability-bar slot whenever is_ability_usable(ab) is
## false — replaces the old chat-log "why can't I use this" messages (removed) with an always-
## visible on-slot explanation instead, hud.gd's "Ability bar greying" section. Empty string means
## no extra text is needed — either the ability turns out to actually be usable, or it already
## shows its own countdown/counter badge that already reads as the reason (Frenzy/Hunter's Mark's
## cooldown, a racial free-cast "X/Y" counter that still has a real spell slot to fall back on).
func ability_unusable_reason(ab: Ability) -> String:
	if monk_extra_attack_pending:
		return "Attack/Wait"
	# "No Bonus Action" only wins when it's the SOLE blocker — a more specific existing reason
	# (e.g. "No Rage", "Not Engaged") still takes priority if that's ALSO true, checked below.
	var bonus_action_reason: String = "No Bonus Action" if _bonus_action_blocks(ab) else ""
	if ab.is_on_cooldown():
		return "CD %d" % ab.cooldown_remaining
	if ab.essence_cost > 0 and not invincible and player_stats.hybrid_essence < ab.essence_cost:
		return "No Essence"
	if ab.fury_cost > 0 and not invincible and player_stats.rampager_fury < ab.fury_cost:
		return "No Fury"
	match ab.ability_id:
		"frenzy":
			if not is_raging:
				return "No Rage"
			if berserker_frenzy_used:
				return "Used"
		"limit_break":
			if scarred_warrior_limit_break_used:
				return "Used"
		"zealot_strike":
			if hit_dice <= 0:
				return "No HD"
		"grip_of_the_forest":
			if not is_raging:
				return "No Rage"
			if grip_of_the_forest_used_this_turn:
				return "Used"
		"halfling_nimbleness":
			if halfling_nimbleness_used_this_turn:
				return "Used"
		"draconic_flight":
			if player_stats.character_level < 5:
				return "Lvl 5"
			if player_stats.draconic_flight_used:
				return "Used"
		"hellish_rebuke_toggle":
			return "No Slot"
		"hail_of_thorns_toggle", "ensnaring_strike_toggle":
			if bonus_action_reason == "":
				return "No Slot"
		"flurry_of_blows":
			if player_stats.monk_focus_points <= 0 and not invincible:
				return "No Focus"
			if not PlayerMonk.martial_arts_active(equipped_weapon):
				return "Need Monk Gear"
		"patient_defense":
			if player_stats.monk_focus_points <= 0 and not invincible:
				return "No Focus"
			if not PlayerMonk.is_engaged():
				return "Not Engaged"
		"step_of_wind":
			if step_of_wind_used_this_turn:
				return "Used"
			if player_stats.monk_focus_points <= 0 and not invincible:
				return "No Focus"
		"uncanny_metabolism":
			if player_stats.uncanny_metabolism_used and not invincible:
				return "Used"
		"hunters_mark":
			# The round-cooldown case is already shown via hud.gd's own "%dt"/flat-"1" countdown
			# overlay (frenzy_cooldown_turns), so this only ever fires for the "out of every
			# resource" case (no live target to free-refresh, no free recast, no uses, no slot) —
			# unless the Bonus Action itself is the actual blocker, checked below instead.
			if bonus_action_reason == "":
				return "No Slot"
	if bonus_action_reason != "":
		return bonus_action_reason
	if ab.ability_id.begins_with("spell:"):
		var spell: Spell = SpellDb.get_spell(ab.ability_id.substr(6))
		return "No Uses" if spell != null and spell.level == 0 else "No Slot"
	if not ab.has_uses():
		return "No Uses"
	return ""

# Triggered on short rest completion. Heals companion (if alive) AND restores One with Nature charge.
# Natural Sleeper's form lock does NOT happen here — long rest only (see long_rest()).
func _on_short_rest_completed() -> void:
	clear_light_source()  # Light cantrip — ends on a completed rest, short or long
	# Monk's Focus: unlike every other per-rest resource in this codebase, refills on BOTH a short
	# AND a long rest (D&D 2024 RAW) — see Stats.monk_focus_points_max's own comment.
	player_stats.monk_focus_points = player_stats.monk_focus_points_max
	# Fighter's Action Surge: same "short OR long rest" refill as Monk's Focus above (unlike
	# Second Wind, which is long-rest-only) — see Stats.action_surge_uses_max's own comment.
	player_stats.action_surge_uses_remaining = player_stats.action_surge_uses_max
	if berserker_frenzy_used and _find_ability_by_id("frenzy") != null:
		game_log("[color=lime]Frenzy: use refreshed.[/color]")
	berserker_frenzy_used = false
	berserker_turns_since_frenzy = 0
	if player_stats.character_race == Stats.CharacterRace.ORC and player_stats.adrenaline_rush_uses_remaining < player_stats.proficiency_bonus:
		player_stats.adrenaline_rush_uses_remaining = player_stats.proficiency_bonus
		_sync_ability_uses()
		game_log("[color=lime]Adrenaline Rush: uses refreshed.[/color]")
	if player_companion != null and is_instance_valid(player_companion):
		player_companion.heal_to_max()
		game_log("[color=lime]%s rests and recovers fully.[/color]" % player_companion.animal_name)
	var owtn: Ability = _find_ability_by_id("wild_companion")
	if owtn != null:
		owtn.uses_remaining = 1
		ability_bar_changed.emit()
		game_log("[color=lime]One with Nature: companion charge refreshed.[/color]")
	# Warlock Pact Magic — recharges on a completed SHORT rest, not long rest (the opposite of
	# every other caster's slot pool) — see scripts/items/pact_slot_pool.gd.
	if player_stats.caster != null and player_stats.caster.slot_pool is PactSlotPool:
		player_stats.caster.slot_pool.on_short_rest()
		spell_slots_changed.emit()

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
		Stats.CharacterClass.FIGHTER:   return 10
		Stats.CharacterClass.PALADIN:   return 10
		Stats.CharacterClass.SORCERER:  return 6
		Stats.CharacterClass.HYBRID:    return 10
		Stats.CharacterClass.RAMPAGER:  return 12
		_:                              return 8  # Bard/Cleric/Druid/Rogue/Warlock: d8

func check_player_death() -> void:
	if player_stats.is_dead() and not is_game_over and not is_dying and not invincible:
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
		begin_death_save_sequence()

# Dramatic, BG3-style death-save sequence — replaces the old instant-death-on-0-HP behavior.
# `is_dying` blocks all player input (threaded into player.gd's is_game_over guard chains) and
# stalls the turn economy (no player input means TurnManager never starts another round), so play
# is effectively frozen on whatever's already mid-animation while scripts/ui/death_save_overlay.gd
# (the sole listener of the three death_save_* signals) runs the roll animation full-screen.
# Known limitation: an enemy round already IN FLIGHT when the killing blow lands (its own
# decide/execute coroutine, already started before this function ran) finishes normally rather
# than being interrupted mid-animation — the full-screen overlay covers it visually either way,
# and no NEW round can ever start afterward since player input stays blocked the whole time.
# Deliberately a bare, unmodified d20 (no ability mod, no Halfling Luck reroll, no Heroic
# Inspiration, no Exhaustion penalty) — matches 5e RAW's own death save (no modifiers apply to it
# by default) and keeps the outcome bands exactly the raw-die ranges they were designed around.
const DEATH_SAVE_FIRST_DELAY: float = 0.9
const DEATH_SAVE_ROLL_INTERVAL: float = 1.1
const DEATH_SAVE_END_DELAY: float = 1.2

func begin_death_save_sequence() -> void:
	is_dying = true
	death_save_successes = 0
	death_save_failures = 0
	death_save_started.emit()
	_run_death_save_sequence()

func _run_death_save_sequence() -> void:
	await get_tree().create_timer(DEATH_SAVE_FIRST_DELAY).timeout
	while true:
		var die: int = Rng.roll(20)
		var result: String
		if die == 1:
			death_save_failures += 2
			result = "critfail"
		elif die <= 9:
			death_save_failures += 1
			result = "fail"
		elif die <= 19:
			death_save_successes += 1
			result = "success"
		else:
			result = "critsuccess"
		death_save_rolled.emit(die, result, death_save_successes, death_save_failures)
		if result == "critsuccess" or death_save_successes >= 3:
			await get_tree().create_timer(DEATH_SAVE_END_DELAY).timeout
			_end_death_save_sequence(true)
			return
		if death_save_failures >= 3:
			await get_tree().create_timer(DEATH_SAVE_END_DELAY).timeout
			_end_death_save_sequence(false)
			return
		await get_tree().create_timer(DEATH_SAVE_ROLL_INTERVAL).timeout

func _end_death_save_sequence(revived: bool) -> void:
	is_dying = false
	if revived:
		player_stats.exhaustion_level += 1
		if player_stats.exhaustion_level >= 6:
			game_log("[color=red]Your body finally gives out under the weight of exhaustion.[/color]")
			is_game_over = true
			AudioManager.play("player_die")
			player_died.emit()
			death_save_finished.emit(false)
			return
		player_stats.current_hp = 1
		player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
		game_log("[color=lime]You cling to life and rise with 1 HP![/color]")
		game_log("[color=orange]Clawing back from death leaves you Exhausted (level %d).[/color]" % player_stats.exhaustion_level)
		risen_from_dead_active = true
		game_log("[color=cyan]Risen from the Dead: you are invulnerable until your next turn![/color]")
		player_status_changed.emit()
	else:
		is_game_over = true
		AudioManager.play("player_die")
		player_died.emit()
	death_save_finished.emit(revived)

func heal(amount: int) -> int:
	# Bearded Devil's Beard attack: "can't regain any HPs while poisoned" — see
	# Stats.poisoned_condition_save_dc's own comment for why this is gated on the DC field, not
	# just poisoned_condition_turns > 0 (Tripwire/Rend's plain Poisoned application is unaffected).
	if player_stats.poisoned_condition_turns > 0 and player_stats.poisoned_condition_save_dc > 0:
		game_log("[color=gray]The poison courses through you — you can't regain any HP.[/color]")
		return 0
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
	# Any landed healing closes an active Infernal Wound (Bearded Devil's Glaive attack — see
	# Stats.infernal_wound_active's own comment; "magical healing" simplified to "any healing").
	if player_stats.infernal_wound_active:
		player_stats.infernal_wound_active = false
		player_stats.infernal_wound_dice = 0
		game_log("[color=lime]The infernal wound closes as your wounds mend.[/color]")
	return bruiser_bonus

func gain_exp(amount: int) -> void:
	var old_max_hp: int = player_stats.max_hp
	var old_rage_max: int = player_stats.rage_uses_max
	var old_focus_max: int = player_stats.monk_focus_points_max
	var old_second_wind_max: int = player_stats.second_wind_uses_max
	var old_max_hit_dice: int = max_hit_dice()
	var old_mastery_cap: int = player_stats.mastery_cap()
	var old_prof_bonus: int = player_stats.proficiency_bonus
	var old_level: int = player_stats.character_level
	var old_slot_max: Dictionary = player_stats.caster.slot_pool.max_slots() if player_stats.caster != null and player_stats.caster.slot_pool != null else {}
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
		# Monk's Focus scales 1:1 with level — grant the extra point immediately, same "on the
		# triggering level-up, not only after the next rest" treatment as Rage above.
		if player_stats.character_class == Stats.CharacterClass.MONK:
			var new_focus_max: int = player_stats.monk_focus_points_max
			if new_focus_max > old_focus_max:
				player_stats.monk_focus_points = mini(
					player_stats.monk_focus_points + (new_focus_max - old_focus_max),
					new_focus_max)
				ability_bar_changed.emit()
		# Second Wind uses scale at levels 4/10 — grant the extra use immediately, same
		# "on the triggering level-up, not only after the next rest" treatment as Rage above.
		if player_stats.character_class == Stats.CharacterClass.FIGHTER:
			var new_second_wind_max: int = player_stats.second_wind_uses_max
			if new_second_wind_max > old_second_wind_max:
				player_stats.second_wind_uses_remaining = mini(
					player_stats.second_wind_uses_remaining + (new_second_wind_max - old_second_wind_max),
					new_second_wind_max)
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
		_apply_fighter_level_features(player_stats.character_level)
		_grant_hybrid_abilities_for_level()  # auto-grant newly-eligible Hybrid abilities
		_grant_rampager_abilities_for_level()  # auto-grant newly-eligible Rampager abilities
		if player_stats.caster != null and player_stats.caster.slot_pool != null:
			player_stats.caster.slot_pool.grant_new_slots_on_levelup(old_slot_max)
			spell_slots_changed.emit()
			_roll_spell_learn_choices()
		if player_stats.mastery_cap() > old_mastery_cap:
			mastery_learn_pending = true
		# Dragonborn Breath Weapon: a proficiency-bonus increase (levels 5/9/13/17) grants +1
		# CURRENT use immediately, not just a higher cap (mirrors Rage's own grant-now treatment
		# above). Draconic Flight unlocks the instant character_level reaches 5.
		if player_stats.character_race == Stats.CharacterRace.DRAGONBORN:
			var new_prof_bonus: int = player_stats.proficiency_bonus
			if new_prof_bonus > old_prof_bonus:
				player_stats.breath_weapon_uses_remaining = mini(
					player_stats.breath_weapon_uses_remaining + (new_prof_bonus - old_prof_bonus),
					new_prof_bonus)
				_sync_ability_uses()
			if old_level < 5 and player_stats.character_level >= 5:
				give_race_starting_items()
		# Stonecunning: same proficiency-bonus-crossing +1-current-use grant as Breath Weapon above.
		if player_stats.character_race == Stats.CharacterRace.DWARF:
			var new_prof_bonus_dw: int = player_stats.proficiency_bonus
			if new_prof_bonus_dw > old_prof_bonus:
				player_stats.stonecunning_uses_remaining = mini(
					player_stats.stonecunning_uses_remaining + (new_prof_bonus_dw - old_prof_bonus),
					new_prof_bonus_dw)
				_sync_ability_uses()
		# Adrenaline Rush: same proficiency-bonus-crossing +1-current-use grant as Breath
		# Weapon/Stonecunning above.
		if player_stats.character_race == Stats.CharacterRace.ORC:
			var new_prof_bonus_orc: int = player_stats.proficiency_bonus
			if new_prof_bonus_orc > old_prof_bonus:
				player_stats.adrenaline_rush_uses_remaining = mini(
					player_stats.adrenaline_rush_uses_remaining + (new_prof_bonus_orc - old_prof_bonus),
					new_prof_bonus_orc)
				_sync_ability_uses()
		# Elven Lineage: grants one spell at character level 3, a second at level 5 (see
		# scripts/entities/CLAUDE.md's "Elf" section).
		if player_stats.character_race == Stats.CharacterRace.ELF:
			if old_level < 3 and player_stats.character_level >= 3:
				_grant_elf_lineage_spell(_elf_lineage_spell_for(player_stats.race_variant, 3))
			if old_level < 5 and player_stats.character_level >= 5:
				_grant_elf_lineage_spell(_elf_lineage_spell_for(player_stats.race_variant, 5))
		# Fiendish Legacy: grants a 1st-level spell at character level 3, a 2nd-level spell at
		# level 5 (the level-1 cantrip is granted immediately at race select — see
		# give_race_starting_items()) — see scripts/entities/CLAUDE.md's "Tiefling" section.
		if player_stats.character_race == Stats.CharacterRace.TIEFLING:
			if old_level < 3 and player_stats.character_level >= 3:
				_grant_tiefling_legacy_spell(_tiefling_legacy_spell_for(player_stats.race_variant, 3))
			if old_level < 5 and player_stats.character_level >= 5:
				_grant_tiefling_legacy_spell(_tiefling_legacy_spell_for(player_stats.race_variant, 5))
		# Eldritch Invocations: schedule-driven pending-slot grant (see WARLOCK_INVOCATION_SCHEDULE
		# above) — scripts/entities/CLAUDE.md's "Warlock class".
		if player_stats.character_class == Stats.CharacterClass.WARLOCK:
			_grant_invocation_slots_for_level(old_level, player_stats.character_level)
		# Celestial Revelation unlocks the instant character_level reaches 3 (same
		# "give_race_starting_items() re-run is idempotent" pattern as Dragonborn's Draconic Flight
		# unlocking at level 5).
		if player_stats.character_race == Stats.CharacterRace.AASIMAR and old_level < 3 and player_stats.character_level >= 3:
			give_race_starting_items()
		# Giant Ancestry: same proficiency-bonus-crossing +1-current-use grant as Breath
		# Weapon/Stonecunning/Adrenaline Rush above. Large Form unlocks the instant
		# character_level reaches 5 (same "give_race_starting_items() re-run is idempotent"
		# pattern as Dragonborn's Draconic Flight/Aasimar's Celestial Revelation above).
		if player_stats.character_race == Stats.CharacterRace.GOLIATH:
			var new_prof_bonus_gol: int = player_stats.proficiency_bonus
			if new_prof_bonus_gol > old_prof_bonus:
				player_stats.giant_ancestry_uses_remaining = mini(
					player_stats.giant_ancestry_uses_remaining + (new_prof_bonus_gol - old_prof_bonus),
					new_prof_bonus_gol)
				_sync_ability_uses()
			if old_level < 5 and player_stats.character_level >= 5:
				give_race_starting_items()
		AudioManager.play("level_up")
		player_leveled_up.emit(player_stats.character_level)

## Which tier's pool a level-up at `lv` feeds. 0 = no talent point (level 21+).
func tier_for_level(lv: int) -> int:
	return TalentTiers.tier_for_level(lv)

## Whether talents of `tier` can currently be invested in. Points accumulate while locked.
func tier_unlocked(tier: int) -> bool:
	return TalentTiers.tier_unlocked(tier, tier2_unlocked, tier3_selected_class, player_stats.character_level)

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

# Pure gating logic lives in EquipRequirements (scripts/autoloads/equip_requirements.gd) — this is
# just a 1-line delegator, same pattern as talent_icon_path()/TalentIcons.
func can_equip_shield(item: Item) -> bool:
	return EquipRequirements.can_equip_shield(item, player_stats, equipment)

func log_shield_equip_blocked(item: Item) -> void:
	if not player_stats.proficient_shields:
		combat_message.emit("[color=red]You lack proficiency with shields.[/color]")
	else:
		combat_message.emit("[color=red]Cannot equip a Shield while wielding a two-handed weapon.[/color]")

# ── Weapons (Item.Type.WEAPON, category proficiency) ────────────────────────────
func can_equip_weapon(item: Item) -> bool:
	return EquipRequirements.can_equip_weapon(item, player_stats)

func log_weapon_equip_blocked(item: Item) -> void:
	combat_message.emit("[color=red]You lack proficiency with %s weapons.[/color]" % item.weapon_category.to_lower())

# ── Body armor (Item.Type.ARMOR, is_shield == false) ───────────────────────────
func can_equip_armor(item: Item) -> bool:
	return EquipRequirements.can_equip_armor(item, player_stats)

## Whether the currently-equipped body armor imposes Disadvantage on the Stealth-vs-Passive-
## Perception check (Item.stealth_disadvantage — Studded Leather/Scale Mail/Half Plate/Ring
## Mail/Chain Mail/Splint/Plate all set it, per their real D&D "Stealth (Disadvantage)" property).
## Read by Player._resolve_stealth_check() — see scripts/entities/CLAUDE.md's "Stealth & Surprise
## Attacks".
func player_has_stealth_disadvantage() -> bool:
	var a: Item = equipment.get("armor") as Item
	return a != null and a.stealth_disadvantage

func log_armor_equip_blocked(item: Item) -> void:
	var lacks_prof: bool = false
	match item.armor_category:
		Item.ArmorCategory.LIGHT:    lacks_prof = not player_stats.proficient_light_armor
		Item.ArmorCategory.MEDIUM:   lacks_prof = not player_stats.proficient_medium_armor
		Item.ArmorCategory.HEAVY:    lacks_prof = not player_stats.proficient_heavy_armor
	if lacks_prof:
		combat_message.emit("[color=red]You lack proficiency with this armor.[/color]")
	else:
		combat_message.emit("[color=red]You aren't strong enough to wear %s (requires %d STR).[/color]" % [item.item_name, item.str_requirement])

# Alias so GameState.ARMOR_CHANGE_TURNS keeps working for existing external readers
# (e.g. ArmorTooltip.build()) without change — the real table lives on EquipRequirements now.
const ARMOR_CHANGE_TURNS: Dictionary = EquipRequirements.ARMOR_CHANGE_TURNS

func _armor_change_turns(new_item: Item, old_item: Item) -> int:
	return EquipRequirements.armor_change_turns(new_item, old_item)

func _has_bag_space() -> bool:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == null:
			return true
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			return true
	return false

# Body armor (Item.Type.ARMOR, non-shield) equip/unequip/swap in the "armor" slot takes real turns
# to resolve (ARMOR_CHANGE_TURNS above) instead of being a free action like every other equip —
# see equip()/unequip()/move_item()'s "armor" branches. Neither item is actually moved yet (mirrors
# GameState.begin_scroll_learn()'s "nothing consumed until it finishes" precedent) — the physical
# slot swap happens in complete_armor_change(). Interrupted outright (no Continue/Abort prompt,
# nothing's changed yet) the instant an enemy enters FOV — same convention as scroll-learning
# (GameState.scroll_learn_active), ticked in player.gd._on_turn_started().
func begin_armor_change(new_item: Item, old_item: Item) -> void:
	var turns: int = _armor_change_turns(new_item, old_item)
	armor_change_active = true
	armor_change_turns_remaining = turns
	armor_change_total_turns = turns
	armor_change_new_item = new_item
	armor_change_old_item = old_item
	var verb: String = "swap"
	if new_item == null:
		verb = "take off"
	elif old_item == null:
		verb = "put on"
	game_log("[color=cyan]You begin to %s your armor... (%d turns)[/color]" % [verb, turns])
	# Kick the first countdown tick immediately instead of waiting for the player's next real
	# turn — without this, the countdown only started once the player pressed another key.
	if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
		stealth_check_stillness = true
		TurnManager.begin_player_action()
		TurnManager.on_player_action_complete()

func cancel_armor_change(interrupted: bool = false) -> void:
	if interrupted:
		game_log("[color=gray]Your armor change is interrupted![/color]")
	armor_change_active = false
	armor_change_turns_remaining = 0
	armor_change_total_turns = 0
	armor_change_new_item = null
	armor_change_old_item = null

func complete_armor_change() -> void:
	var new_item: Item = armor_change_new_item
	var old_item: Item = armor_change_old_item
	armor_change_active = false
	armor_change_turns_remaining = 0
	armor_change_total_turns = 0
	armor_change_new_item = null
	armor_change_old_item = null
	if new_item != null:
		_remove_from_bags(new_item)
	equipment["armor"] = new_item
	if old_item != null:
		_add_to_bags_silent(old_item)
	if new_item != null and player_stats.mage_armor_active:
		player_stats.mage_armor_active = false
	recalculate_stats()
	if new_item != null:
		combat_message.emit("[color=cyan]Equipped [b]%s[/b].[/color]" % new_item.item_name)
	elif old_item != null:
		combat_message.emit("[color=cyan]Unequipped [b]%s[/b].[/color]" % old_item.item_name)
	equipment_changed.emit()
	inventory_changed.emit()

# Equip/unequip/re-equip is always a free action — EXCEPT a Shield (Item.is_shield), which takes
# 1 turn to equip or unequip (see can_equip_shield() and the "costs_turn" blocks below), and body
# armor (the "armor" slot), which takes real turns per ARMOR_CHANGE_TURNS (see begin_armor_change()).
func equip(item: Item, slot_name: String = "") -> void:
	if slot_name == "":
		match item.item_type:
			Item.Type.WEAPON:
				if item.is_ranged:
					slot_name = "ranged"
				else:
					slot_name = "melee"
			Item.Type.ARMOR:  slot_name = "hand2" if item.is_shield else "armor"
			_: return
	if not equipment.has(slot_name):
		return
	if item.is_shield and not can_equip_shield(item):
		log_shield_equip_blocked(item)
		return
	if item.item_type == Item.Type.WEAPON and not can_equip_weapon(item):
		log_weapon_equip_blocked(item)
		return

	if slot_name == "armor":
		if armor_change_active:
			return
		if not can_equip_armor(item):
			log_armor_equip_blocked(item)
			return
		begin_armor_change(item, equipment.get("armor") as Item)
		return

	var costs_turn: bool = item.is_shield and TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT
	if costs_turn:
		stealth_check_stillness = true
		TurnManager.begin_player_action()

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
	# Mage Armor ends the moment Armor OR a Shield is equipped (not other slots — robes/clothes-as-
	# accessories aren't modeled as a distinct item type; a Shield counts too since 5e RAW treats
	# it as worn armor even though it lives in "hand2", not "armor" — see Item.is_shield).
	if (slot_name == "armor" or to_equip.is_shield) and player_stats.mage_armor_active:
		player_stats.mage_armor_active = false
	recalculate_stats()
	combat_message.emit("[color=cyan]Equipped [b]%s[/b].[/color]" % to_equip.item_name)
	equipment_changed.emit()
	inventory_changed.emit()
	if costs_turn:
		TurnManager.on_player_action_complete()

# Silently returns whatever's in the off-hand slot to the bag (no log line of its own —
# called as a side effect of equipping a two-handed main-hand weapon, see equip()/move_item()).
func _auto_unequip_offhand() -> void:
	var hand2: Item = equipment.get("hand2") as Item
	if hand2 == null:
		return
	equipment["hand2"] = null
	_add_to_bags_silent(hand2)

# Pure stack-splitting logic lives in ItemStackSplit (scripts/items/item_stack_split.gd) — these
# stay as 1-line delegators (not renamed) since player_throw_tool.gd already calls
# GameState._split_one_unit(weapon) directly.
func _should_split_for_equip(item: Item) -> bool:
	return ItemStackSplit.should_split_for_equip(item)

func _split_one_unit(item: Item) -> Item:
	return ItemStackSplit.split_one_unit(item)

func unequip(slot_name: String) -> void:
	if not equipment.has(slot_name):
		return
	var item: Item = equipment[slot_name] as Item
	if item == null:
		return
	if slot_name == "armor":
		if armor_change_active:
			return
		if not _has_bag_space():
			combat_message.emit("[color=red]No bag space to unequip %s![/color]" % item.item_name)
			return
		begin_armor_change(null, item)
		return
	if not add_item(item):
		combat_message.emit("[color=red]No bag space to unequip %s![/color]" % item.item_name)
		return
	var costs_turn: bool = item.is_shield and TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT
	if costs_turn:
		stealth_check_stillness = true
		TurnManager.begin_player_action()
	equipment[slot_name] = null
	recalculate_stats()
	combat_message.emit("[color=cyan]Unequipped [b]%s[/b].[/color]" % item.item_name)
	equipment_changed.emit()
	if costs_turn:
		TurnManager.on_player_action_complete()

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
	# Gripping two-handed can't coexist with an Off-hand item (Shield included) — mirrors
	# equip()'s auto-unequip-offhand rule for a two-handed weapon.
	if item.is_two_handed:
		_auto_unequip_offhand()
	recalculate_stats()
	combat_message.emit("[color=cyan]%s gripped %s-handed.[/color]" % [item.item_name, "two" if item.is_two_handed else "one"])
	equipment_changed.emit()

# Torch: whether any currently-equipped Torch (Main Hand or Off-hand) is lit — computed live
# (never cached) so the FOV formula and the Fire-bonus-damage check both stay in sync with
# equip/unequip/light/burnout without a separate mutable fov bonus field to keep consistent.
func has_lit_torch_equipped() -> bool:
	var mh: Item = equipment.get("melee") as Item
	var oh: Item = equipment.get("hand2") as Item
	return (mh != null and mh.torch_lit) or (oh != null and oh.torch_lit)

# Returns whichever currently-equipped Item is the lit torch (Main Hand checked first), or null.
# Used by the status tray to show the icon + turns-remaining tooltip for the buff.
func lit_torch_item() -> Item:
	var mh: Item = equipment.get("melee") as Item
	if mh != null and mh.torch_lit:
		return mh
	var oh: Item = equipment.get("hand2") as Item
	if oh != null and oh.torch_lit:
		return oh
	return null

func light_torch(item: Item) -> void:
	if item == null or item.torch_burnt or item.torch_lit:
		return
	item.torch_lit = true
	item.torch_turns_remaining = 600
	game_log("You light the torch.")
	equipment_changed.emit()
	ability_bar_changed.emit()

func burn_out_torch(item: Item) -> void:
	item.torch_lit = false
	item.torch_burnt = true
	item.item_name = "Burnt Torch"
	game_log("[color=gray]Your torch burns out.[/color]")
	equipment_changed.emit()
	ability_bar_changed.emit()

func recalculate_stats() -> void:
	var s: Stats = player_stats
	s.armor = 0
	var armor_item: Item = equipment.get("armor") as Item
	var has_armor: bool = armor_item != null
	var hand2_item: Item = equipment.get("hand2") as Item
	var has_shield: bool = hand2_item != null and hand2_item.is_shield
	s.recalc_ac(has_armor, armor_item, has_shield)
	# Start from weapon's own damage die if it defines one, else base stats
	var melee: Item = equipment.get("melee") as Item
	var melee_bonus_dmg: int = melee.bonus_damage if (melee != null and _item_bonus_active(melee)) else 0
	if melee != null and melee.damage_die_min > 0:
		s.min_damage = melee.damage_die_min + melee_bonus_dmg
		s.max_damage = melee.damage_die_max + melee_bonus_dmg
	else:
		s.min_damage = s.base_min_damage + melee_bonus_dmg
		s.max_damage = s.base_max_damage + melee_bonus_dmg
	for slot_name: String in equipment:
		var it: Item = equipment[slot_name] as Item
		if it == null:
			continue
		if slot_name == "melee":
			continue  # already handled above
		if _item_bonus_active(it):
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
	# Weapon category proficiency (Simple/Martial) — mirrors can_equip_shield()'s own hard-block
	# shape below. Melee, Ranged, AND Off-hand (dual-wield) all gate on it — an unproficient
	# character can't equip the weapon into any hand.
	var entering_weapon: bool = dest == "equipment" and dest_slot in ["melee", "ranged", "hand2"] \
		and src_item != null and src_item.item_type == Item.Type.WEAPON
	if entering_weapon and not can_equip_weapon(src_item):
		log_weapon_equip_blocked(src_item)
		return
	# Body armor (Item.Type.ARMOR, non-shield) landing in or leaving "armor" takes real turns
	# instead of the instant swap below — see begin_armor_change(). Neither item is physically
	# moved here; complete_armor_change() does that once the turn countdown finishes.
	var entering_armor: bool = dest == "equipment" and dest_slot == "armor" \
		and src_item != null and src_item.item_type == Item.Type.ARMOR and not src_item.is_shield
	var leaving_armor: bool = src == "equipment" and src_slot == "armor" \
		and src_item != null and not src_item.is_shield
	if entering_armor or leaving_armor:
		if armor_change_active:
			return
		if entering_armor and not can_equip_armor(src_item):
			log_armor_equip_blocked(src_item)
			return
		if entering_armor:
			begin_armor_change(src_item, dest_item)
		else:
			begin_armor_change(null, src_item)
		return
	# Shield (Item.is_shield) equip/unequip via drag costs 1 turn and is gated by
	# can_equip_shield() — covers dragging a Shield into "hand2" (entering), dragging it back out
	# to the bag/quickbar (leaving), and dragging a different item onto an occupied "hand2" Shield
	# (displacing it). Mirrors equip()/unequip()'s own gating.
	var entering_shield: bool = dest == "equipment" and dest_slot == "hand2" \
		and src_item != null and src_item.is_shield
	var leaving_shield: bool = src == "equipment" and src_slot == "hand2" \
		and src_item != null and src_item.is_shield
	var displaced_shield: bool = dest == "equipment" and dest_slot == "hand2" \
		and not entering_shield and dest_item != null and dest_item.is_shield
	if entering_shield and not can_equip_shield(src_item):
		log_shield_equip_blocked(src_item)
		return
	var shield_involved: bool = entering_shield or leaving_shield or displaced_shield
	var costs_turn: bool = shield_involved and TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT
	if costs_turn:
		stealth_check_stillness = true
		TurnManager.begin_player_action()
	# Dragging a stacked weapon (e.g. Handaxe/Dagger, quantity > 1) into an equipment slot only
	# equips a single unit — the rest of the stack stays put instead of the whole pile moving
	# into the slot. Mirrors equip()'s splitting rule (see _should_split_for_equip()).
	# Dropping a stackable item (dest not an equipment slot) merges with any matching stack
	# ALREADY sitting anywhere in the quickbar/bag — not only the exact slot dropped onto — so
	# e.g. unequipping a Thrown weapon and dropping it in any empty slot still finds and joins an
	# existing pile of the same weapon instead of starting a second one (see _items_can_stack()).
	var stack_target: Item = null
	if dest != "equipment" and src_item != null:
		stack_target = _find_matching_stack(src_item, src, src_idx)
	if dest == "equipment" and src_item != null and _should_split_for_equip(src_item):
		_set_slot_item(dest, dest_idx, dest_slot, _split_one_unit(src_item))
		if dest_item != null:
			_add_to_bags_silent(dest_item)
	elif stack_target != null:
		_merge_into_stack(stack_target, src_item)
		_set_slot_item(src, src_idx, src_slot, null)
	else:
		_set_slot_item(src, src_idx, src_slot, dest_item)
		_set_slot_item(dest, dest_idx, dest_slot, src_item)
	# Dragging a two-handed weapon into the main hand can't coexist with an off-hand
	# weapon — kick whatever's in "hand2" back to the bag automatically (mirrors equip()).
	if dest == "equipment" and dest_slot == "melee" and src_item != null and src_item.is_two_handed:
		_auto_unequip_offhand()
	# Mage Armor ends the moment Armor or a Shield lands in an equipment slot — mirrors equip()'s
	# own gate. Armor/Shield are only ever equipped via this drag path (never auto-equipped on
	# pickup, unlike weapons), so this is the actual chokepoint that matters in normal play.
	if dest == "equipment" and src_item != null and player_stats.mage_armor_active \
			and (dest_slot == "armor" or src_item.is_shield):
		player_stats.mage_armor_active = false
	recalculate_stats()
	equipment_changed.emit()
	inventory_changed.emit()
	if costs_turn:
		TurnManager.on_player_action_complete()

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

# Two items stack together iff they share an item_name AND (neither is a WEAPON, OR both are
# Thrown weapons with matching uses_max — see _merge_into_stack()). A non-Thrown weapon (sword,
# axe, bow, ...) never stacks with anything, even another copy of the exact same weapon — each
# unit is its own distinct instance and always takes its own slot.
func _items_can_stack(a: Item, b: Item) -> bool:
	if a.item_name != b.item_name:
		return false
	if a.item_type != Item.Type.WEAPON:
		return true
	return a.is_thrown and b.is_thrown and a.uses_max == b.uses_max

# Scans the whole quickbar+bag for an existing stack `item` can merge into, skipping the slot
# `item` itself is currently sitting in (`exclude_src`/`exclude_idx` — irrelevant, and left
# unexcluded, when the source is an equipment slot). Used by move_item() so dropping a stackable
# item (e.g. unequipping a Thrown weapon) merges with a matching pile anywhere in the inventory,
# not only when dropped directly onto it.
func _find_matching_stack(item: Item, exclude_src: String, exclude_idx: int) -> Item:
	for i: int in QUICKBAR_SIZE:
		if exclude_src == "quickbar" and exclude_idx == i:
			continue
		var ex: Item = player_quickbar[i] as Item
		if ex != null and _items_can_stack(ex, item):
			return ex
	for i: int in INVENTORY_SIZE:
		if exclude_src == "inventory" and exclude_idx == i:
			continue
		var ex: Item = player_inventory[i] as Item
		if ex != null and _items_can_stack(ex, item):
			return ex
	return null

func add_item(item: Item) -> bool:
	# Try stacking in quickbar, then bag
	for i: int in QUICKBAR_SIZE:
		var ex: Item = player_quickbar[i] as Item
		if ex != null and _items_can_stack(ex, item):
			_merge_into_stack(ex, item)
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		var ex: Item = player_inventory[i] as Item
		if ex != null and _items_can_stack(ex, item):
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
			# Healing Herb (special-rooms-economy-design.md §4.3) is the one FOOD item with a
			# real heal_amount — every other FOOD entry has heal_amount == 0 and keeps the
			# "saved as fuel" framing below unchanged.
			if item.heal_amount > 0:
				var before3: int = player_stats.current_hp
				var bruiser_bonus3: int = heal(item.heal_amount)
				var healed3: int = player_stats.current_hp - before3
				if healed3 > 0:
					var bonus_sources3: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus3, "color": "cyan"}])
					var _hm3: String = "heal:dice=0,sides=0,con=0,roll=0,bonus=%s,total=%d" % [bonus_sources3, healed3]
					combat_message.emit("[color=green]You eat [b]%s[/b] and recover [url=%s]%d HP[/url].[/color]" % [item.item_name, _hm3, healed3])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
				if not invincible:
					consume_one(item)
			else:
				game_log("[color=gray]%s isn't eaten directly — it's saved as fuel for your next long rest (hold Alt).[/color]" % item.item_name)
		Item.Type.WEAPON, Item.Type.ARMOR:
			equip(item)  # free action except a Shield (1 turn) or body armor (ARMOR_CHANGE_TURNS)
		Item.Type.TOOL:
			player_tool_primed.emit(item)
		Item.Type.SCROLL:
			# scroll_spell_id: single one-shot cast baked into this scroll, castable by any class
			# (see Item.scroll_spell_id / SpellEffects) — arms targeting via PlayerSpellcasting,
			# same LMB-resolve flow as an ability-bar spell. Consumed on cast, not on read.
			if item.scroll_spell_id != "":
				player_scroll_primed.emit(item)
			# leveled-spells-and-slots-plan.md §4.2: scroll-taught spells. Item.taught_spell_id
			# empty = not a spell scroll (every pre-existing SCROLL item stays a no-op).
			elif item.taught_spell_id != "" and player_stats.caster != null:
				if player_stats.caster.known_spells.has(item.taught_spell_id):
					game_log("[color=gray]You already know this spell.[/color]")
				else:
					learn_spell(item.taught_spell_id)
					if not invincible:
						consume_one(item)

func consume_one(item: Item) -> void:
	if item.quantity > 1:
		item.quantity -= 1
		inventory_changed.emit()
	else:
		remove_item(item)

func drop_item(item: Item) -> void:
	var df: Node = get_tree().get_first_node_in_group("dungeon_floor")
	if df == null:
		return
	TurnManager.begin_player_action()
	remove_item(item)
	df.place_item_on_floor(player_grid_pos, item)
	combat_message.emit("[color=gray]You drop [b]%s[/b].[/color]" % item.get_display_name())
	TurnManager.on_player_action_complete()

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

# Fire Trap (see dungeon_floor.gd's trigger_trap()): destroys one random Scroll from the player's
# quickbar+bag as a one-shot punishment, replacing the old burning-status DoT. Returns the burned
# item's display name, or "" if no scroll was being carried (no-op in that case).
func burn_random_scroll() -> String:
	var candidates: Array[Item] = []
	for i: int in QUICKBAR_SIZE:
		var it: Item = player_quickbar[i]
		if it != null and it.item_type == Item.Type.SCROLL:
			candidates.append(it)
	for i: int in INVENTORY_SIZE:
		var it: Item = player_inventory[i]
		if it != null and it.item_type == Item.Type.SCROLL:
			candidates.append(it)
	if candidates.is_empty():
		return ""
	var chosen: Item = Rng.pick(candidates)
	var burned_name: String = chosen.item_name
	if chosen.quantity > 1:
		chosen.quantity -= 1
	else:
		remove_item(chosen)
	inventory_changed.emit()
	return burned_name

func _remove_from_bags(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == item:
			player_quickbar[i] = null
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == item:
			player_inventory[i] = null
			return

# Debug-only "Enhance" button (F3 → Enhance Item on Slot 1): +1 per press to whatever sits in
# item-quickbar slot 1 (index 0). Weapon → bonus_damage (already flows into both the attack roll
# AND the damage roll at every player attack site, and is already shown by name in the hit/dmg
# hover tooltips — "weapon +N"/"Weapon enhancement" — so no new tooltip plumbing was needed).
# Armor/Shield (both Item.Type.ARMOR) → bonus_ac (already folded in generically by
# recalculate_stats()'s per-equipment-slot loop). Not wired into the floor-loot/debug item-giver
# pools per direct owner request — this is purely a "take an item I already have and enhance it"
# tool, not a new lootable item variant.
func enhance_quickbar_slot1_item() -> void:
	var item: Item = player_quickbar[0] if player_quickbar.size() > 0 else null
	if item == null:
		game_log("[color=gray]No item in quickbar slot 1 to enhance.[/color]")
		return
	if item.item_type == Item.Type.WEAPON:
		item.enhancement_level += 1
		item.bonus_damage += 1
	elif item.item_type == Item.Type.ARMOR:
		item.enhancement_level += 1
		item.bonus_ac += 1
	else:
		game_log("[color=gray]%s can't be enhanced — only weapons, armor, and shields can.[/color]" % item.get_display_name())
		return
	item.item_name = "%s +%d" % [_enhancement_base_name(item.item_name), item.enhancement_level]
	game_log("[color=cyan]%s[/color] is now [b]+%d[/b]!" % [item.item_name, item.enhancement_level])
	inventory_changed.emit()

func _enhancement_base_name(current_name: String) -> String:
	var plus_idx: int = current_name.rfind(" +")
	if plus_idx != -1 and current_name.substr(plus_idx + 2).is_valid_int():
		return current_name.substr(0, plus_idx)
	return current_name

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
# Set true by Enemy._notice_target() whenever a SLEEPING/STATIONARY/ROAMING enemy spots the
# player (stealth check failed, or the true-adjacency/can-see wake backstops). Read by
# Player._execute_queued_path()'s chase-to-attack loop to cancel an in-progress auto-chase the
# instant the target (or any other enemy) notices the player, not just once it actually swings.
var enemy_noticed_player_this_turn: bool = false

# Stone Giant Ancestry's "X absorbs N damage" line — set by take_damage_raw() the instant the
# reduction rolls (right when damage lands) but deliberately NOT logged there: take_damage_raw()
# is called from inside whatever attack resolver is building its own "you take N dmg" line, and
# that line hasn't been logged yet at this point — see flush_stone_endurance_log()'s own comment
# for why this is deferred rather than logged inline like every other combat-math side effect.
var _pending_stone_endurance_log: String = ""

# Monk's Deflect Attacks (level 3+) — same deferred-log shape as Stone's Endurance above, set by
# take_damage_raw() the instant the reduction rolls. deflect_attacks_used_this_turn is the
# once-per-turn gate (auto-consumed by the FIRST physical hit each turn, not player-armed) —
# reset in player.gd's _on_turn_started() alongside the other once-per-turn ability flags.
var _pending_deflect_attacks_log: String = ""
var deflect_attacks_used_this_turn: bool = false

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
	if invincible or risen_from_dead_active:
		# Skip the actual HP change, but still register "the player was hit this turn" so
		# god-mode play doesn't silently break turn-based triggers that key off it (e.g.
		# Battlefield Expert R3's free Side Step charge — see player_base_talents.gd).
		if is_physical and not ignore_rage:
			player_was_hit_this_turn = true
		return 0
	var final_amount: int = amount
	if is_raging and not ignore_rage and is_physical:
		final_amount = int(floor(float(amount) * 0.5))
	# Animal Form Bear: elemental DR while Raging (Bear's effect is Rage-gated, unlike Eagle/Wolf
	# which stay always-active — see markdowns/wild_heart.md). Enhanced Forms R1 also covers
	# magical damage; R2/R3 raise the %. Checks active_rager_form (the form CURRENTLY active — see
	# _tick_animal_form_transition()), not natural_rager_form (the target of an in-progress switch).
	# BUGFIX: active_rager_form defaults to "Bear" for every character (it's only ever changed by
	# Wild Heart's own cycle_animal_form()/_tick_animal_form_transition()), so without the subclass/
	# unlock gate below this DR applied to ANY class's own Fire/Cold/etc. damage — including a Wizard's
	# own Fireball catching themselves in the blast — even though they never touched Wild Heart at all.
	if active_rager_form == "Bear" and active_tier2_subclass == "Wild Heart" and tier2_unlocked and is_raging and not ignore_rage:
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
	# Race damage resistance (Dragonborn's own ancestry type, Dwarven Resilience's Poison) — a flat
	# 50% reduction, floored, same convention as Enemy.take_typed_damage()'s own resist multiplier.
	# BUGFIX: Stats.damage_resistances was set by apply_race_defaults() but never actually read
	# anywhere before this — a Dragonborn's own passive resistance silently did nothing.
	if damage_type != "" and damage_type in player_stats.damage_resistances:
		final_amount = int(floor(float(final_amount) * 0.5))
	# Stone Giant ancestry (Goliath, see player_goliath.gd): a toggle, not a one-shot arm — the
	# 1d12+CON reduction is unknown until it actually rolls, right here, at the moment the very
	# next instance of damage lands (status-tick/trap damage never reaches this function, so it can
	# only ever be consumed by a real attack — same scope as the concentration-break check below).
	# Bugfix/redesign, direct owner request: this used to roll (and commit to) the reduction amount
	# the instant the toggle was armed, well before any damage was actually taken.
	if not ignore_rage and player_stats.character_race == Stats.CharacterRace.GOLIATH \
			and player_stats.race_variant == Stats.GiantAncestry.STONE and player_stats.giant_ancestry_armed:
		var stone_die: int = Rng.roll(12)
		var stone_con: int = player_stats.con_modifier()
		var reduction: int = maxi(0, stone_die + stone_con)
		player_stats.giant_ancestry_armed = false
		if not invincible:
			player_stats.giant_ancestry_uses_remaining -= 1
		_sync_ability_uses()
		final_amount = maxi(0, final_amount - reduction)
		var stone_meta: String = "stonedr:die=%d,con=%d,total=%d" % [stone_die, stone_con, reduction]
		# Deliberately NOT logged here — this is a reaction to the hit currently being resolved by
		# the caller, whose own "X hits you for N dmg" line hasn't been printed yet at this point.
		# Stashed instead and flushed by flush_stone_endurance_log(), called by every caller right
		# after its own hit line — same "reaction logs after the attack it reacted to" ordering as
		# Storm's Thunder/Hellish Rebuke (see enemy.gd._attack_player()).
		_pending_stone_endurance_log = "[color=cyan]Stone's Endurance[/color] absorbs [url=%s][color=yellow]%d[/color][/url] damage." % [stone_meta, reduction]
	# Monk's Deflect Attacks (level 3+, PASSIVE — auto-fires on the first physical hit each turn,
	# no player activation): 1d10 + DEX mod + Monk level, reduces Slashing/Piercing/Bludgeoning
	# damage only. Same "roll at the moment damage actually lands" + deferred-log shape as Stone's
	# Endurance above (flush_deflect_attacks_log(), called by the same set of take_damage_raw()
	# callers right after their own hit line).
	if not ignore_rage and is_physical and player_stats.character_class == Stats.CharacterClass.MONK \
			and player_stats.character_level >= 3 and not deflect_attacks_used_this_turn:
		deflect_attacks_used_this_turn = true
		var deflect_die: int = Rng.roll(10)
		var deflect_dex: int = player_stats.dex_modifier()
		var deflect_lvl: int = player_stats.character_level
		var deflect_reduction: int = maxi(0, deflect_die + deflect_dex + deflect_lvl)
		final_amount = maxi(0, final_amount - deflect_reduction)
		var deflect_meta: String = "deflect:die=%d,dex=%d,lvl=%d,total=%d" % [deflect_die, deflect_dex, deflect_lvl, deflect_reduction]
		_pending_deflect_attacks_log = "[color=cyan]Deflect Attacks[/color] reduces the damage by [url=%s][color=yellow]%d[/color][/url]." % [deflect_meta, deflect_reduction]
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
	_check_concentration_break(actual)
	check_player_death()
	return actual

## Logs Stone's Endurance's "absorbs N damage" line if take_damage_raw() just stashed one (i.e.
## the toggle was armed and fired on the hit that was just resolved) — a no-op otherwise. Callers
## that build their own "you take N dmg" line around a take_damage_raw() call must call this
## immediately after logging that line, so the reaction reads as happening AFTER the attack it
## reacted to (same ordering rule as Storm's Thunder/Hellish Rebuke) — see enemy.gd._attack_player(),
## spell_effects.gd's Fireball self-catch, and player_berserker.gd's Frenzy self-damage.
func flush_stone_endurance_log() -> void:
	if _pending_stone_endurance_log.is_empty():
		return
	game_log(_pending_stone_endurance_log)
	_pending_stone_endurance_log = ""

## Same shape as flush_stone_endurance_log() above, for Monk's Deflect Attacks — every
## take_damage_raw() caller that builds its own hit line must call this immediately after logging
## it (same call sites as flush_stone_endurance_log(): enemy.gd._attack_player(),
## player_berserker.gd's two Frenzy self-damage branches, spell_effects.gd's Fireball self-catch,
## dungeon_floor.gd's standing-in-fire tick, and player.gd's status-tick block).
func flush_deflect_attacks_log() -> void:
	if _pending_deflect_attacks_log.is_empty():
		return
	game_log(_pending_deflect_attacks_log)
	_pending_deflect_attacks_log = ""

# Blade Ward cantrip (and any future concentration spell): taking damage forces a CON check —
# DC = max(10, damage taken), 5e's concentration-save shape but without the usual "half rounded
# down" reduction (per the spell's own text). Failure ends the concentration effect immediately —
# scoped to take_damage_raw()'s callers only (melee/ranged/enemy attacks, Fireball's own blast);
# status-tick damage (poison/burning/bleeding) and trap damage bypass this chokepoint entirely and
# don't trigger a concentration check — a documented simplification, not an oversight.
func _check_concentration_break(actual_damage: int) -> void:
	if player_stats.concentration_spell_id == "" or actual_damage <= 0:
		return
	var dc: int = maxi(10, actual_damage)
	var mod: int = player_stats.con_modifier()
	var die: int = Rng.roll(20)
	var total: int = die + mod
	var passed: bool = total >= dc
	# Hoverable roll breakdown (die + CON mod vs DC), same convention as every other check/save
	# tooltip — see TooltipFormatters.fmt_conc_tooltip(), dispatched via hud.gd's "conc" kind.
	var conc_meta: String = "conc:die=%d,mod=%d,total=%d,dc=%d,pass=%d" % [die, mod, total, dc, int(passed)]
	if passed:
		game_log("[color=gray]Concentration holds [url=%s](CON %d vs DC %d)[/url].[/color]" % [conc_meta, total, dc])
	else:
		end_concentration("[color=gray]Your concentration breaks! [url=%s](CON %d vs DC %d)[/url][/color]" % [conc_meta, total, dc])

# Single chokepoint for ending whatever the player is currently concentrating on — clears
# concentration_spell_id AND that spell's own duration/target fields (5e: only one concentration
# effect at a time, so switching to a NEW concentration spell must fully clear the old one's state,
# not just repoint the id — otherwise e.g. Witch Bolt kept ticking damage after concentration moved
# to Blade Ward, since its tick only ever checked witch_bolt_turns, never concentration_spell_id).
# No-op if not currently concentrating. `reason_log`, if non-empty, is logged after clearing.
func end_concentration(reason_log: String = "") -> void:
	var broken_spell: String = player_stats.concentration_spell_id
	if broken_spell == "":
		return
	player_stats.concentration_spell_id = ""
	if broken_spell == "blade_ward":
		player_stats.blade_ward_turns = 0
	elif broken_spell == "witch_bolt":
		player_stats.witch_bolt_turns = 0
		player_stats.witch_bolt_target = null
		player_stats.witch_bolt_just_cast = false
	elif broken_spell == "expeditious_retreat":
		player_stats.expeditious_retreat_turns = 0
	elif broken_spell == "fog_cloud":
		player_stats.fog_cloud_turns = 0
		clear_fog_cloud()
	elif broken_spell == "darkness":
		player_stats.darkness_turns = 0
		clear_darkness()
	elif broken_spell == "detect_magic":
		player_stats.detect_magic_turns = 0
	elif broken_spell == "pass_without_trace":
		player_stats.pass_without_trace_turns = 0
	elif broken_spell == "hunters_mark":
		player_stats.hunters_mark_turns = 0
		player_stats.hunters_mark_target = null
		player_stats.hunters_mark_fresh = false
	elif broken_spell == "ray_of_enfeeblement":
		player_stats.ray_of_enfeeblement_turns = 0
		if is_instance_valid(player_stats.ray_of_enfeeblement_target):
			player_stats.ray_of_enfeeblement_target.enfeeble_turns = 0
		player_stats.ray_of_enfeeblement_target = null
	elif broken_spell == "hold_person":
		player_stats.hold_person_turns = 0
		for e: Enemy in player_stats.hold_person_target:
			if is_instance_valid(e):
				e.paralyzed_turns = 0
				e._refresh_paralyzed_visual()
		player_stats.hold_person_target = []
	elif broken_spell == "hideous_laughter":
		player_stats.hideous_laughter_turns = 0
		# Prone is deliberately left alone — it clears itself normally the next time this enemy's
		# own turn lets it stand up (see the Enemy.prone field's own comment), not tied to
		# Concentration at all. Only the Incapacitated half ends here.
		for e: Enemy in player_stats.hideous_laughter_target:
			if is_instance_valid(e):
				e.incapacitated_turns = 0
		player_stats.hideous_laughter_target = []
	elif broken_spell == "faerie_fire":
		player_stats.faerie_fire_turns = 0
		# Faerie Fire is Concentration too, and losing it should retroactively un-outline every
		# creature it lit up this cast — not just stop the caster's own duration counter (bugfix:
		# this used to only clear the caster's field, so an enemy's own outline/debuff silently
		# outlived the concentration that was supposedly sustaining it).
		player_stats.faerie_fire_outlined_turns = 0
		var df: Node = get_tree().get_first_node_in_group("dungeon_floor")
		if df != null:
			for e: Enemy in df.get_all_enemies():
				if is_instance_valid(e) and e.faerie_fire_turns > 0:
					e.faerie_fire_turns = 0
					e._refresh_faerie_fire_visual()
			var p: Node = df.get_player()
			if p != null and is_instance_valid(p):
				p._refresh_faerie_fire_visual()
	elif broken_spell == "invisibility":
		player_stats.invisibility_turns = 0
		if player_companion != null and is_instance_valid(player_companion) and player_companion.invisibility_turns > 0:
			player_companion.invisibility_turns = 0
	elif broken_spell == "hex":
		player_stats.hex_turns = 0
		player_stats.hex_target = null
		player_stats.hex_ability = ""
	elif broken_spell == "ensnaring_strike":
		player_stats.ensnaring_strike_turns = 0
		if is_instance_valid(player_stats.ensnaring_strike_target):
			player_stats.ensnaring_strike_target.restrained_turns = 0
		player_stats.ensnaring_strike_target = null
	if reason_log != "":
		game_log(reason_log)

# Removes ONE Enemy from a multi-target Hold Person/Hideous Laughter cast's own target array
# (its individual repeated-save success — Enemy.decide_turn() — already zeroed that enemy's own
# status field before calling this) WITHOUT touching any other still-held target. Concentration
# itself (and the whole spell) only actually ends once every target has escaped. Caller passes
# `spell_id` ("hold_person"/"hideous_laughter") so this stays correct if the player has since
# started concentrating on something else entirely (a stale repeated-save tick from an enemy whose
# effect already ended some other way).
func remove_hold_person_target(enemy: Enemy) -> void:
	player_stats.hold_person_target.erase(enemy)
	if player_stats.hold_person_target.is_empty() and player_stats.concentration_spell_id == "hold_person":
		end_concentration()

func remove_hideous_laughter_target(enemy: Enemy) -> void:
	player_stats.hideous_laughter_target.erase(enemy)
	if player_stats.hideous_laughter_target.is_empty() and player_stats.concentration_spell_id == "hideous_laughter":
		end_concentration()


func apply_player_status(type: String, turns: int, save_dc: int = 0) -> bool:
	# Only emit when a counter-based status' value actually increases — re-applying (e.g. every
	# Mud/Water step re-calling "slowed" with maxi()) is otherwise a same-value no-op that still
	# unconditionally emitted, which could flash a duplicate identical-looking status-tray icon
	# for one frame when player_on_difficult_terrain (recomputed separately, see its own comment)
	# was already true from the previous tile — see scripts/entities/CLAUDE.md's status-tray note.
	var _changed: bool = true
	match type:
		"poison":
			_changed = turns > player_stats.poison_turns
			player_stats.poison_turns = maxi(player_stats.poison_turns, turns)
		"burning":
			_changed = turns > player_stats.burning_turns
			player_stats.burning_turns = maxi(player_stats.burning_turns, turns)
		"bleeding":
			_changed = turns > player_stats.bleeding_turns
			player_stats.bleeding_turns = maxi(player_stats.bleeding_turns, turns)
		"slowed":
			_changed = turns > player_stats.slowed_turns
			player_stats.slowed_turns = maxi(player_stats.slowed_turns, turns)
		# Poisoned CONDITION (DISADV on attacks/checks — Stats.has_disadvantage_condition()) —
		# deliberately separate from "poison" above (the pre-existing damage-over-time counter).
		# `save_dc` (optional 3rd param, default 0): when a source explicitly sets it (Bearded
		# Devil's Beard attack), the condition also grants a repeated end-of-turn CON save to end
		# early (Player._on_turn_started()) and blocks GameState.heal() entirely — see
		# Stats.poisoned_condition_save_dc's own comment. A plain 0 (Tripwire/Rend) leaves both of
		# those effects off, unchanged from before this param existed.
		"poisoned_condition":
			_changed = turns > player_stats.poisoned_condition_turns
			player_stats.poisoned_condition_turns = maxi(player_stats.poisoned_condition_turns, turns)
			if save_dc > 0:
				player_stats.poisoned_condition_save_dc = save_dc
		# Prone — not turn-counted (see Stats.prone's own comment); "turns" is ignored, stays
		# Prone until Player._try_move()'s stand-up redirect fires.
		"prone":
			_changed = not player_stats.prone
			player_stats.prone = true
		# Incapacitated — also breaks Concentration immediately (5e: "can't concentrate on
		# anything" — same chokepoint the CON-check break path already uses).
		"incapacitated":
			_changed = turns > player_stats.incapacitated_turns
			player_stats.incapacitated_turns = maxi(player_stats.incapacitated_turns, turns)
			if player_stats.concentration_spell_id != "":
				end_concentration("You lose concentration!")
	if _changed:
		player_status_changed.emit()
	return true

# Frightened — a dedicated setter rather than a apply_player_status() match case, since it needs
# to store a live Enemy SOURCE reference alongside the turn count (5e: DISADV on checks/attacks
# only while that specific source is in sight, and "can't approach" only applies relative to it) —
# see Stats.frightened_source/frightened_turns' own comment. Re-applying while already frightened
# by the SAME source just refreshes the duration (maxi); a DIFFERENT source overwrites outright
# (5e doesn't stack multiple Frightened sources — the newer fear replaces the old).
func apply_player_frightened(source: Enemy, turns: int, save_dc: int = 10) -> void:
	if player_stats.frightened_source == source:
		player_stats.frightened_turns = maxi(player_stats.frightened_turns, turns)
	else:
		player_stats.frightened_source = source
		player_stats.frightened_turns = turns
	player_stats.frightened_save_dc = save_dc
	player_status_changed.emit()

func clear_player_frightened() -> void:
	player_stats.frightened_source = null
	player_stats.frightened_turns = 0
	player_status_changed.emit()

# Paralyzed — player-side mirror of Enemy.apply_status()'s "paralyzed_turns" write (Hold Person),
# see Stats.paralyzed_turns' own comment. Like apply_player_frightened() above, this is a dedicated
# setter rather than an apply_player_status() match case since it needs to stash a save DC/stat
# alongside the turn count. Also ends Concentration immediately, same as the "incapacitated" case
# in apply_player_status() below — 5e's real Paralyzed condition implies Incapacitated.
func apply_player_paralyzed(turns: int, save_dc: int = 10, stat: String = "con") -> void:
	player_stats.paralyzed_turns = maxi(player_stats.paralyzed_turns, turns)
	player_stats.paralyze_save_dc = save_dc
	player_stats.paralyze_save_stat = stat
	if player_stats.concentration_spell_id != "":
		end_concentration("You lose concentration!")
	player_status_changed.emit()

func clear_player_paralyzed() -> void:
	player_stats.paralyzed_turns = 0
	player_status_changed.emit()


func _apply_monk_level_features(level: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.MONK:
		return
	var die_sides: int = player_stats.martial_arts_die_sides
	match level:
		2:
			_grant_monk_focus_abilities()
			combat_message.emit("[color=cyan]Level 2 Monk: Monk's Focus unlocked — Flurry of Blows, Patient Defense, Step of the Wind, Uncanny Metabolism (%d Focus Points).[/color]" % player_stats.monk_focus_points_max)
		3:
			var da := Ability.new()
			da.ability_id = "deflect_attacks"
			da.ability_name = "Deflect Attacks"
			da.description = "Passive: the first time you're hit by Slashing/Piercing/Bludgeoning damage each turn, automatically reduce it by 1d10 + DEX modifier + your Monk level."
			da.icon_path = "res://sprites/items/misc/key_iron.png"
			da.uses_remaining = 0
			da.uses_max = 0
			add_ability(da)
			combat_message.emit("[color=cyan]Level 3 Monk: Deflect Attacks unlocked — 1d10 + DEX + level physical damage reduction, once per turn.[/color]")
		4:
			player_stats.dexterity += 2
			recalculate_stats()
			# Slow Fall — PLACEHOLDER ONLY, per direct owner request: grants the ability-bar entry
			# (so the level-up reads as a real feature) but the mechanic itself does nothing yet.
			# No fall-damage system exists anywhere in this codebase to hook into — chasms are an
			# instant remove/kill, not a damage roll (see scripts/world/CLAUDE.md's forced-movement/
			# chasm handling) — so there's nothing for "reduce fall damage" to reduce today. Revisit
			# if/when a real fall-damage mechanic is ever added.
			var sf := Ability.new()
			sf.ability_id = "slow_fall"
			sf.ability_name = "Slow Fall"
			sf.description = "Passive: not yet implemented — this game has no fall-damage mechanic to reduce yet."
			sf.icon_path = "res://sprites/items/misc/key_iron.png"
			sf.uses_remaining = 0
			sf.uses_max = 0
			sf.is_passive = true
			add_ability(sf)
			combat_message.emit("[color=cyan]Level 4 Monk: DEX +2 (now [b]%d[/b], modifier +%d)! Slow Fall unlocked (not yet implemented).[/color]" % [player_stats.dexterity, player_stats.dex_modifier()])
		5:
			var ea := Ability.new()
			ea.ability_id = "extra_attack"
			ea.ability_name = "Extra Attack"
			ea.description = "Passive: your first melee attack each turn no longer ends your turn — you may make one more attack. No movement or other action in between; Space/Wait forfeits the second attack."
			ea.icon_path = "res://sprites/items/misc/key_iron.png"
			ea.uses_remaining = 0
			ea.uses_max = 0
			add_ability(ea)
			var ma5: Ability = _find_ability_by_id("martial_arts")
			if ma5 != null:
				ma5.description = "Passive, while unarmed or wielding only Monk weapons (Simple, or Martial+Light), unarmored, no shield: Dextrous Attacks (use DEX instead of STR), Martial Arts Die (1d%d, replaces a weaker weapon die), Bonus Unarmed Strike (a free extra unarmed strike after your attack lands or misses)." % die_sides
			ability_bar_changed.emit()
			combat_message.emit("[color=cyan]Level 5 Monk: [b]Extra Attack[/b]! Your first melee attack no longer ends your turn. Martial Arts die increased to [b]1d%d[/b]![/color]" % die_sides)
		11, 17:
			var ma: Ability = _find_ability_by_id("martial_arts")
			if ma != null:
				ma.description = "Passive, while unarmed or wielding only Monk weapons (Simple, or Martial+Light), unarmored, no shield: Dextrous Attacks (use DEX instead of STR), Martial Arts Die (1d%d, replaces a weaker weapon die), Bonus Unarmed Strike (a free extra unarmed strike after your attack lands or misses)." % die_sides
			ability_bar_changed.emit()
			combat_message.emit("[color=cyan]Level %d Monk: Martial Arts die increased to [b]1d%d[/b]![/color]" % [level, die_sides])

func _apply_fighter_level_features(level: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.FIGHTER:
		return
	match level:
		2:
			player_stats.action_surge_uses_remaining = player_stats.action_surge_uses_max
			var asu := Ability.new()
			asu.ability_id = "action_surge"
			asu.ability_name = "Action Surge"
			asu.description = "Instant, no action cost. Take one additional non-magical action (move or attack) this turn — casting a spell with it still ends your turn as normal."
			asu.icon_path = "res://sprites/items/misc/key_iron.png"
			asu.uses_remaining = player_stats.action_surge_uses_remaining
			asu.uses_max = player_stats.action_surge_uses_max
			add_ability(asu)
			combat_message.emit("[color=cyan]Level 2 Fighter: [b]Action Surge[/b] unlocked — take one extra move or attack this turn, %d use(s) per rest.[/color]" % player_stats.action_surge_uses_max)
		17:
			var asu17: Ability = _find_ability_by_id("action_surge")
			if asu17 != null:
				asu17.uses_max = player_stats.action_surge_uses_max
				asu17.description = "Instant, no action cost. Take one additional non-magical action (move or attack) this turn — casting a spell with it still ends your turn as normal. 2 uses per rest."
			player_stats.action_surge_uses_remaining = mini(player_stats.action_surge_uses_remaining + 1, player_stats.action_surge_uses_max)
			ability_bar_changed.emit()
			combat_message.emit("[color=cyan]Level 17 Fighter: Action Surge now has [b]2 uses[/b] per rest.[/color]")

func debug_jump_to_floor(n: int) -> void:
	is_game_over = false
	is_dying = false
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

# ── Eldritch Invocations (Warlock only) ───────────────────────────────────────
# scripts/items/eldritch_invocation.gd's EldritchInvocation is a simpler, pick-once cousin of
# Talent — no ranks. Built in code like Talent/SpellDb, no .tres files, via a static func rather
# than a const (a Resource .new() isn't a valid const expression) — mirrors SpellDb.get_spell()'s
# "build fresh every call" convention rather than caching one shared array. 8 entries for this pass
# (levels 12/15/18's schedule slots sit pending with nothing yet to spend them on — same
# Tier-2-pending precedent as talent_points). See scripts/entities/CLAUDE.md's "Warlock class".
static func eldritch_invocation_list() -> Array[EldritchInvocation]:
	var list: Array[EldritchInvocation] = []
	var defs: Array = [
		{"id": "agonizing_blast", "name": "Agonizing Blast", "lvl": 1,
			"desc": "Add your Charisma modifier to the damage of your Eldritch Blast hits."},
		{"id": "repelling_blast", "name": "Repelling Blast", "lvl": 1,
			"desc": "A creature you hit with Eldritch Blast is pushed 1 tile directly away from you on a failed CON save."},
		{"id": "armor_of_shadows", "name": "Armor of Shadows", "lvl": 1,
			"desc": "Cast Mage Armor on yourself at will, without expending a spell slot."},
		{"id": "fiendish_vigor", "name": "Fiendish Vigor", "lvl": 1,
			"desc": "Cast False Life on yourself at will, without expending a spell slot."},
		{"id": "eldritch_sight", "name": "Eldritch Sight", "lvl": 1,
			"desc": "Cast Detect Magic at will, without expending a spell slot."},
		{"id": "devils_sight", "name": "Devil's Sight", "lvl": 5,
			"desc": "You ignore the vision penalty of standing inside a Fog Cloud or Darkness zone."},
		{"id": "beguiling_defenses", "name": "Beguiling Defenses", "lvl": 5,
			"desc": "You have Advantage on saving throws to avoid or end the Frightened condition."},
		{"id": "ascendant_step", "name": "Ascendant Step", "lvl": 9,
			"desc": "Cast Misty Step on yourself at will, without expending a spell slot."},
	]
	for d: Dictionary in defs:
		var inv := EldritchInvocation.new()
		inv.invocation_id = d["id"]
		inv.invocation_name = d["name"]
		inv.description = d["desc"]
		inv.min_level = d["lvl"]
		list.append(inv)
	return list

func eldritch_invocations_eligible() -> Array[EldritchInvocation]:
	var out: Array[EldritchInvocation] = []
	for inv: EldritchInvocation in eldritch_invocation_list():
		if player_stats.character_level >= inv.min_level and not warlock_invocations_known.has(inv.invocation_id):
			out.append(inv)
	return out

func knows_invocation(id: String) -> bool:
	return warlock_invocations_known.has(id)

## Armor of Shadows/Fiendish Vigor/Eldritch Sight/Ascendant Step — genuinely unlimited at-will
## casts (unlike the Elf/Tiefling lineage's proficiency_bonus-per-long-rest counter), gated purely
## on knowing the matching invocation. Checked at every chokepoint the Elf/Tiefling free-cast check
## already is (begin_cast()'s slot-availability gate, _cast_level_for(), _consume_slot()).
const WARLOCK_INVOCATION_SPELL_GRANT: Dictionary = {
	"mage_armor": "armor_of_shadows",
	"false_life": "fiendish_vigor",
	"detect_magic": "eldritch_sight",
	"misty_step": "ascendant_step",
}
func warlock_invocation_free_cast(spell_id: String) -> bool:
	var inv_id: String = WARLOCK_INVOCATION_SPELL_GRANT.get(spell_id, "")
	return inv_id != "" and knows_invocation(inv_id)

## Called by invocation_picker.gd's confirm — permanent, no respec.
func learn_invocation(id: String) -> void:
	if warlock_invocations_known.has(id):
		return
	var inv: EldritchInvocation = null
	for i: EldritchInvocation in eldritch_invocation_list():
		if i.invocation_id == id:
			inv = i
			break
	if inv == null:
		return
	warlock_invocations_known.append(id)
	warlock_invocation_slots_pending = maxi(0, warlock_invocation_slots_pending - 1)
	match id:
		"armor_of_shadows":
			add_ability(_build_invocation_spell_ability("mage_armor", "armor_of_shadows"))
		"fiendish_vigor":
			add_ability(_build_invocation_spell_ability("false_life", "fiendish_vigor"))
		"eldritch_sight":
			add_ability(_build_invocation_spell_ability("detect_magic", "eldritch_sight"))
		"ascendant_step":
			add_ability(_build_invocation_spell_ability("misty_step", "ascendant_step"))
		# Agonizing Blast / Repelling Blast / Devil's Sight / Beguiling Defenses are pure passive
		# flags read directly via knows_invocation() at their trigger site (spell_effects.gd,
		# GameState.is_heavily_obscured() callers, the Frightened save site) — no ability granted.
	game_log("[color=cyan]You gain the %s invocation.[/color]" % inv.invocation_name)

## An at-will free-cast Invocation grants an always-available ability-bar entry for an existing
## spell — same "always prepared, outside known_spells/prepared_spells bookkeeping" shape as an
## Elf/Tiefling lineage spell (see scripts/entities/CLAUDE.md's "Elf" section), just gated on
## knows_invocation(invocation_id) instead of a free-cast-per-long-rest counter (genuinely
## unlimited, per RAW).
func _build_invocation_spell_ability(spell_id: String, invocation_id: String) -> Ability:
	var ab: Ability = _build_spell_ability(spell_id)
	ab.description += " (Invocation: at will, no spell slot.)"
	return ab

## Called from gain_exp()'s level-up block — grants any newly-opened schedule slots and, if any
## opened, tells hud.gd to spawn the picker (invocation_choice_required).
func _grant_invocation_slots_for_level(old_level: int, new_level: int) -> void:
	var old_known: int = 0
	var new_known: int = 0
	for threshold: int in WARLOCK_INVOCATION_SCHEDULE:
		if old_level >= threshold:
			old_known = maxi(old_known, WARLOCK_INVOCATION_SCHEDULE[threshold])
		if new_level >= threshold:
			new_known = maxi(new_known, WARLOCK_INVOCATION_SCHEDULE[threshold])
	var delta: int = new_known - old_known
	if delta > 0:
		warlock_invocation_slots_pending += delta
		invocation_choice_required.emit()

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

# Long-rest reselect — mastery_picker.gd's Swap mode (scripts/ui/CLAUDE.md's "Mastery picker"
# section). Gives up `old_name`; the picker then runs a mandatory "pick 1 of 3" round (same shape
# as Learn mode) to choose the replacement — NOT an automatic random roll. Just removes `old_name`
# from `known` and emits the change signal; the picker itself rolls the 3 replacement candidates
# (excluding both `old_name` and every still-known mastery) and calls toggle_mastery() on the pick.
func discard_mastery(old_name: String) -> void:
	player_stats.known_weapon_masteries.erase(old_name)
	known_masteries_changed.emit()

# Fighter's Fighting Style pick/reselect — scripts/ui/fighting_style_picker.gd's only mutator.
# recalculate_stats() re-runs immediately so a swap into/out of "defense" updates AC right away
# (matching every other equip/level-up path that can move armor_class).
# Blind Fighting Style (Fighter): blindsight 1 tile — ignores every vision-related ADV/DISADV
# source (Fog Cloud/Darkness Heavily-Obscured blindness) on BOTH sides whenever the other party is
# within Chebyshev 1 tile: the player's own attack-roll DISADV for standing in it (every player
# attack-roll site's `GameState.is_blinded(grid_pos)` check) AND an attacker's ADV for attacking a
# blinded player (enemy.gd's `fog_adv`) — both funnel through this one helper so the two can never
# drift out of sync. Footprint-aware via Enemy.min_dist_to() so a Large enemy's whole footprint
# counts, not just its origin tile. Darkvision/truesight-style "see in the dark" is a separate,
# unrelated mechanic (`Stats.darkvision_bonus`/`sees_through_magical_darkness`) — this is purely
# about the ADV/DISADV a Heavily Obscured zone imposes on a roll, not FOV/exploration.
func blind_fighting_ignores(enemy: Enemy) -> bool:
	return player_stats.fighting_style == "blind_fighting" and is_instance_valid(enemy) and enemy.min_dist_to(player_grid_pos) <= 1

func set_fighting_style(id: String) -> void:
	player_stats.fighting_style = id
	recalculate_stats()
	ability_bar_changed.emit()
	game_log("[color=cyan]Fighting Style: %s.[/color]" % Stats.FIGHTING_STYLE_NAMES.get(id, id))

# ── Magic item attunement (Item.requires_attunement/is_attuned) ─────────────────────
# Only ever mutated from scripts/ui/attunement_picker.gd, itself only reachable from the
# long-rest hub (mastery_reselect_prompt.gd) — "changeable only at a long rest" per direct owner
# request. An unattuned magic item can still be equipped/carried; it just doesn't contribute its
# bonus_ac/bonus_damage — see _item_bonus_active(), used by recalculate_stats().
# Pure gating logic lives in AttunementRules (scripts/items/attunement_rules.gd) — these stay as
# delegators under their original names since attunement_picker.gd already calls several directly.
const MAX_ATTUNED_ITEMS: int = AttunementRules.MAX_ATTUNED_ITEMS

func attunable_items() -> Array[Item]:
	return AttunementRules.attunable_items(player_quickbar, player_inventory, equipment)

func attuned_count() -> int:
	return AttunementRules.attuned_count(attunable_items())

func can_attune(item: Item) -> bool:
	return AttunementRules.can_attune(item, attuned_count())

func _item_bonus_active(item: Item) -> bool:
	return AttunementRules.item_bonus_active(item)

func attune_item(item: Item) -> bool:
	if not can_attune(item):
		return false   # hard-block at MAX_ATTUNED_ITEMS, same silent-no-op feel as mastery cap
	item.is_attuned = true
	recalculate_stats()
	inventory_changed.emit()
	equipment_changed.emit()
	return true

func unattune_item(item: Item) -> void:
	if item == null or not item.is_attuned:
		return
	item.is_attuned = false
	recalculate_stats()
	inventory_changed.emit()
	equipment_changed.emit()

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
		"born_in_blood", "bloodied_regen", "psycho", "bruiser", "battlefield_expert", "trailblazer", "bloodhound", "twin_fang":
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
		"Once per short rest (also resets on long rest). Costs a Bonus Action.",
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
	lines.append("Lasts 1 turn; refreshed to 1 turn by attacking, being attacked, or a leftover bonus action.")
	lines.append("%d use%s per floor (scales with level)." % [uses, "s" if uses != 1 else ""])
	lines.append("Costs a Bonus Action.")
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
	var form: String = natural_rager_form  # target form (what's being switched TO)
	var lines: Array[String] = []
	if active_rager_form != form:
		lines.append("[%s Form] — shifting in %d turn%s. [color=gray]Active now: %s[/color]" % [form, rager_form_switch_turns_remaining, "s" if rager_form_switch_turns_remaining != 1 else "", active_rager_form])
	else:
		lines.append("[%s Form — active] Click to switch forms (%d turn%s per step)." % [form, ANIMAL_FORM_SWITCH_TURNS, "s" if ANIMAL_FORM_SWITCH_TURNS != 1 else ""])
	match form:
		"Bear":
			lines.append("While Raging: 25% resistance to elemental damage (Fire/Cold/Lightning/Thunder/Acid/Poison).")
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
	var form: String = natural_sleeper_form
	var lines: Array[String] = []
	# No form rolled yet (no long rest taken since gaining this talent)
	if form == "":
		lines.append("[No form yet] — a random form (Owl/Panther/Salmon) is rolled on your next long rest.")
		return "\n".join(lines)
	lines.append("[%s Form — active] A new random form is rolled every long rest." % form)
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
	var lines: Array[String] = ["While Raging, once per turn (costs a Bonus Action): target an enemy within %d tiles (STR check DC 8+STR mod+prof to resist) and pull them into melee range." % hook_range]
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
		"Hit dice: %d/%d. Costs a Bonus Action to arm." % [hit_dice, max_hit_dice()],
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


func _setup_ranger_talents() -> void:
	_class_talents = []

	var trailblazer_talent := Talent.new()
	trailblazer_talent.talent_id = "trailblazer"
	trailblazer_talent.talent_name = "Trailblazer"
	trailblazer_talent.description = "You move through the wild like it isn't even there."
	trailblazer_talent.icon_path = talent_icon_path("trailblazer", 1)
	trailblazer_talent.tier = 1
	trailblazer_talent.class_id = Stats.CharacterClass.RANGER
	trailblazer_talent.max_rank = 3
	trailblazer_talent.ranks = [
		{"description": "Mud and Water no longer slow you down — you move through difficult terrain at full speed."},
		{"description": "Enemies standing in Mud or Water have Disadvantage on attacks against you."},
		{"description": "Passively detect traps in a wider radius around you as you move."},
	]
	_class_talents.append(trailblazer_talent)

	var bloodhound_talent := Talent.new()
	bloodhound_talent.talent_id = "bloodhound"
	bloodhound_talent.talent_name = "Bloodhound"
	bloodhound_talent.description = "Once you've marked something, it's already dead — it just doesn't know it yet."
	bloodhound_talent.icon_path = talent_icon_path("bloodhound", 1)
	bloodhound_talent.tier = 1
	bloodhound_talent.class_id = Stats.CharacterClass.RANGER
	bloodhound_talent.max_rank = 3
	bloodhound_talent.ranks = [
		{"description": "Your first attack against a freshly-marked target is made with Advantage."},
		{"description": "Your Marked target is easier for you to sneak up on (reduced effective Passive Perception vs. you)."},
		{"description": "When your Marked target dies, Hunter's Mark instantly and freely re-attaches to the nearest visible enemy."},
	]
	_class_talents.append(bloodhound_talent)

	var twin_fang_talent := Talent.new()
	twin_fang_talent.talent_id = "twin_fang"
	twin_fang_talent.talent_name = "Twin Fang"
	twin_fang_talent.description = "Bow, blade, it makes no difference to the hunt."
	twin_fang_talent.icon_path = talent_icon_path("twin_fang", 1)
	twin_fang_talent.tier = 1
	twin_fang_talent.class_id = Stats.CharacterClass.RANGER
	twin_fang_talent.max_rank = 3
	twin_fang_talent.ranks = [
		{"description": "Hunter's Mark's bonus damage also applies to your Off-hand and Nick bonus attacks against the mark."},
		{"description": "Your Off-hand attack against the Marked target keeps its full ability modifier (no dual-wield penalty)."},
		{"description": "The Marked target can never gain Advantage on attacks against you."},
	]
	_class_talents.append(twin_fang_talent)


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
	# Active immediately at subclass grant — no 2-turn transition for the very first form.
	active_rager_form = natural_rager_form
	rager_form_switch_turns_remaining = 0
	_apply_active_rager_form_effects()

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

# Applies whichever form is currently ACTIVE (active_rager_form) to the always-on Eagle knobs.
# Bear's own DR is checked live off active_rager_form in take_damage_raw() instead (also gated on
# is_raging there); Wolf's ADV is checked live off active_rager_form in player.gd's attack roll.
# Called after active_rager_form changes (_tick_animal_form_transition(), _setup_wild_heart_tier2_talents(),
# from_dict() restore) and whenever Enhanced Forms rank changes what Eagle grants.
func _apply_active_rager_form_effects() -> void:
	player_evades_opportunity_attacks = active_rager_form == "Eagle"
	var enh_rank: int = get_talent_rank("enhanced_forms")
	fov_radius_bonus = 1 if (active_rager_form == "Eagle" and enh_rank >= 1) else 0

# Kicks off (or restarts) the ANIMAL_FORM_SWITCH_TURNS-turn transition toward `form`. A no-op
# (0 turns) if `form` is already active. Called from player_wild_heart.gd.cycle_animal_form()
# once per cycle step — note `form` here is always the adjacent form in the Bear/Eagle/Wolf
# cycle, never a direct jump, so reaching the 3rd form away takes 2 separate calls/turns.
func start_animal_form_switch(form: String) -> void:
	natural_rager_form = form
	if form == active_rager_form:
		rager_form_switch_turns_remaining = 0
	else:
		rager_form_switch_turns_remaining = ANIMAL_FORM_SWITCH_TURNS

# Ticked once per REAL player turn (not on Eagle-style reverted/free-action turns) from
# player.gd._on_turn_started(). Counts down rager_form_switch_turns_remaining; reaching 0 snaps
# active_rager_form to whatever natural_rager_form currently targets. Returns true if the active
# form just changed this tick (caller refreshes fog, since Eagle's FOV bonus may have shifted).
func _tick_animal_form_transition() -> bool:
	if rager_form_switch_turns_remaining <= 0:
		return false
	rager_form_switch_turns_remaining -= 1
	if rager_form_switch_turns_remaining > 0:
		return false
	active_rager_form = natural_rager_form
	_apply_active_rager_form_effects()
	game_log("[color=orange]Animal Form: you shift into %s Form.[/color]" % active_rager_form)
	return true

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
		"mold_target_floor": mold_target_floor,
		"mold_spawned": mold_spawned,
		"tenebrous_card_given": tenebrous_card_given,
		"special_slot_spell_id": special_slot_spell_id,
		"player_stats": player_stats.to_dict(),
		"talents": {
			"talent_investments": talent_investments.duplicate(),
			"talent_points": talent_points.duplicate(),
			"tier2_unlocked": tier2_unlocked,
			"active_tier2_subclass": active_tier2_subclass,
			"natural_rager_form": natural_rager_form,
			"active_rager_form": active_rager_form,
			"rager_form_switch_turns_remaining": rager_form_switch_turns_remaining,
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
	mold_target_floor = int(d.get("mold_target_floor", 1))
	mold_spawned = bool(d.get("mold_spawned", false))
	tenebrous_card_given = bool(d.get("tenebrous_card_given", false))
	var stats_d: Dictionary = d.get("player_stats", {})
	var talents_d: Dictionary = d.get("talents", {})
	var inv_d: Dictionary = d.get("inventory", {})
	var rest_d: Dictionary = d.get("rest", {})
	# 1. Class + defaults + baseline class gear/abilities/talent definitions.
	player_stats.character_class = int(stats_d.get("character_class", Stats.CharacterClass.BARBARIAN)) as Stats.CharacterClass
	player_stats.apply_class_defaults()
	class_selected = true
	give_class_starting_items()
	# Wizard's known/prepared spells + slot pool are fully restored by Stats.from_dict() below
	# (called last, per the restore-stats-last rule) — _give_wizard_starting_items() above only
	# seeds a placeholder starting spellbook that from_dict() then overwrites; _rebuild_spell_ability_bar()
	# reconciles the ability bar against the FINAL restored known/prepared lists afterward.
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
	active_rager_form = String(talents_d.get("active_rager_form", natural_rager_form))
	rager_form_switch_turns_remaining = int(talents_d.get("rager_form_switch_turns_remaining", 0))
	# _setup_tier2_for_active_subclass() above ran _apply_active_rager_form_effects() against the
	# still-default "Bear" active_rager_form (this save's actual value wasn't restored yet) — redo
	# it now that active_rager_form holds the real saved form.
	if active_tier2_subclass == "Wild Heart" and tier2_unlocked:
		_apply_active_rager_form_effects()
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
	_rebuild_spell_ability_bar()
	_restore_race_ability_bar()
	_grant_hybrid_abilities_for_level()  # Hybrid abilities are derived from class+level, not serialized
	_grant_rampager_abilities_for_level()  # ditto for Rampager
	# Restore the special quick-cast slot last — set_special_slot() validates against the just-
	# restored known_spells and silently clears (returns false, leaves "" default) if the saved
	# spell is no longer known (e.g. a respec edge case), never crashes on a stale id.
	var saved_special: String = String(d.get("special_slot_spell_id", ""))
	if saved_special != "":
		set_special_slot(saved_special)
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
