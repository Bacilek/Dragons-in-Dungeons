class_name Enemy
extends Entity

enum Behavior { SLEEPING, STATIONARY, ROAMING, CHASING, SEARCHING }

const SPRITES_PATH := "res://sprites/characters/"
const FOV_RADIUS: int = 6

var _dungeon_floor: Node
var display_name: String = "Enemy"
var exp_reward: int = 5
var _type: Dictionary = {}
var enemy_id: String = ""  # from pool "enemy_id"/"boss_id" key — stable id, unlike display_name (UI text)

var is_boss: bool = false
var initial_behavior: Behavior = Behavior.SLEEPING
var behavior: Behavior = Behavior.SLEEPING
var last_known_target_pos: Vector2i = Vector2i(-1, -1)

var door_ambush: bool = false  # set in _move_step() when stepping through a door with no prior LOS to the player; expires at the top of the NEXT take_turn() (lifetime = the round it happened), consumed one-shot by PlayerVfx.has_advantage()
var passive_perception: int = 10  # docs/architecture/stealth-and-surprise-attacks-design.md §3.2 — static DC (pool key "passive_perception", default 10 + WIS mod, derived in _apply_stats())
var oa_used_this_round: bool = false  # Opportunity Attack reaction cap — reset at the top of take_turn()
var slowed_turns: int = 0
var rooted_turns: int = 0        # World Tree Grip of the Forest R2 — skips movement, still attacks if adjacent
var disadv_next_attack: bool = false  # World Tree Grip of the Forest R3 — consumed on next attack roll
var prone_turns: int = 0         # Maul's Topple mastery — skips the ENTIRE turn (no movement, no attack)
var frozen_feet_turns: int = 0   # Ray of Frost's STR-save-fail — skips movement, still attacks if adjacent (same shape as rooted_turns, kept separate so inspect can name it "Frozen Feet")
var shocked_no_oa: bool = false  # Shocking Grasp — blocks this enemy's next Opportunity Attack exposure, whenever it next happens
var mind_sliver_penalty_die: bool = false  # Mind Sliver cantrip — the next check this enemy makes (any resist_check_detailed() call) rolls with -1d4. Consumed on that next check; deliberately not turn-expiry-timed against "until the end of your next turn" per the spell text — enemy checks are rare enough that this one-shot-consumed simplification is documented here rather than adding a second timing system for it.
var embedded_items: Array[Item] = []  # thrown weapons stuck in a non-lethal hit (PlayerThrowTool._throw_weapon) — dropped at 100% chance wherever/whenever this enemy eventually dies, see die() override below
var escape_turns: int = 0    # Nimble Escape trait (Goblin) — random 1-5 turns fleeing escape_from, set in on_melee_hit()
var escape_from: Node = null  # entity being fled from; always is_instance_valid()-checked before use (may die/despawn mid-flee)
var _thrown_weapon_used: bool = false        # a one-shot thrown weapon (pool "thrown_weapon") — true once used; _attack_target() then dispatches to "unarmed_fallback" (a bare-handed Fist strike) instead of the normal multiattack — Goblin Minion's Dagger and Orc Warrior's Javelin both work this way
var _thrown_weapon_lodged_target: Node = null  # who the thrown weapon was aimed at, for the delayed drop-on-death check in die()
var _thrown_weapon_lodged_item: Item = null    # the actual Item to place on the floor if the drop chance succeeds
var _thrown_weapon_lodged_chance: float = 0.5  # per-enemy drop chance (pool "thrown_weapon"'s "drop_chance", default 0.5 matches Goblin Minion's original hardcoded rate)
var _invis_turns: int = 0                # Invisibility ability (Imp) — turns remaining; hides sprite (visible=false) + skipped by DungeonFloor.get_targetable_enemy_at()
var _invis_cooldown_remaining: int = 0   # turns until Invisibility can be cast again (pool "invisibility" -> "cooldown")
const SHAPE_SHIFT_FORMS: PackedStringArray = ["rat", "raven", "spider"]
var _shifted_form: String = ""  # Shape Shift trait (Imp) — "" = true form; else one of SHAPE_SHIFT_FORMS. No dedicated sprites exist yet (mechanic-only: forces the shared small-critter speed, reverts on any damage taken)

# ── D&D stat-block schema (docs/architecture/enemy-stat-block-design.md) ──────────────────────
var cr: float = 0.25                             # authored challenge rating, pool key "cr"
var creature_type: String = "Humanoid"           # pool key "creature_type", flavor/tag only (§7)
var damage_resistances: Array[String] = []       # ×0.5 — pool "damage_resistances" (fallback: legacy "resist")
var damage_immunities: Array[String] = []        # ×0   — pool "damage_immunities"
var damage_vulnerabilities: Array[String] = []   # ×2.0 — pool "damage_vulnerabilities" (fallback: legacy "vuln")
var condition_immunities: Array[String] = []     # blocks the STATUS COUNTER from ever being set (§6) —
												  # separate axis from damage immunity above. Vocabulary:
												  # "slowed"/"rooted"/"prone"/"forced_move" (enemy-side
												  # control fields) and "poisoned"/"burning"/"bleeding"
												  # (Stats counters, reserved — nothing ticks them on
												  # enemies yet, see apply_status() below).
var legendary_resistances_remaining: int = 0     # pool "legendary_resistances" (BOSS_POOL only) — consumed
												  # on a would-be-failed resist_check_detailed() (§15)
var _mods: Dictionary = {}                       # ability score modifiers, pool "mods" (§4). Empty = every
												  # attack/check roll falls back to the legacy floor/3 bonus.
var _check_profs: Array = []                     # pool "check_profs" — which _mods stats add _prof_bonus to checks
var _prof_bonus: int = 0                         # pool "prof_bonus", default derived from cr when "mods" is set
var _attack_prof: bool = true                    # pool "attack_prof" — whether _prof_bonus applies to attacks
var _undead_fortitude_used: bool = false         # traits: "undead_fortitude" — once per life
var _regen_blocked_this_round: bool = false      # traits: "regeneration" — set by a shutoff-type hit
var _ability_cooldowns: Dictionary = {}          # ability_id -> turns_remaining (pool "abilities" "cooldown")
var _ability_uses: Dictionary = {}                # ability_id -> uses_remaining (pool "abilities" "uses_max")
var _ability_recharge_ready: Dictionary = {}      # ability_id -> bool (pool "abilities" "recharge")
var _speed_accum: int = 0                         # Bresenham-style accumulator backing _tick_speed_gate()
var _moves_this_turn: int = 1                     # movement steps allowed THIS turn — pool "speed" (§ movement scaling)
var _roam_target: Vector2i = Vector2i(-1, -1)
var _roam_path: Array[Vector2i] = []
# Search state — used when enemy loses sight of player after chasing
var _search_heading: Vector2i = Vector2i(0, 0)
var _search_turns_remaining: int = 0
var _search_target: Vector2i = Vector2i(-1, -1)
var _search_path: Array[Vector2i] = []

var _zzz_label: Label
var _zzz_tween: Tween

var just_noticed: bool = false  # set the instant an unaware enemy detects the player (stealth-check notice or SLEEPING's true-adjacency backstop) — consumed by the very next _decide_action(), which skips movement/attack that round (shows _notice_label instead) so a freshly-noticed enemy can't also act the same round it noticed. NOT set on the "wake-on-attacked" path (on_disturbed's default via_attack), which still wakes+acts immediately, unchanged.
var _notice_label: Label

func configure(type_data: Dictionary) -> void:
	_type = type_data
	display_name = type_data.get("display_name", "Enemy")
	enemy_id = type_data.get("enemy_id", type_data.get("boss_id", ""))

func _ready() -> void:
	stats = Stats.new()
	_apply_stats()
	z_index = 1
	_setup_animations()
	_setup_hp_bar()
	_setup_zzz()
	_setup_notice_mark()
	behavior = initial_behavior
	if behavior == Behavior.SLEEPING:
		_start_zzz()
	# Shape Shift (Imp): 50% chance to already be shape-shifted into a random form at spawn.
	if _has_trait("shape_shift") and Rng.chance(0.5):
		_shifted_form = SHAPE_SHIFT_FORMS[Rng.range_i(0, SHAPE_SHIFT_FORMS.size() - 1)]

func _apply_stats() -> void:
	var f: int = GameState.current_floor
	stats.max_hp      = _type.get("hp", 8)      + (f - 1) * _type.get("hp_per_floor", 2)
	stats.min_damage  = _type.get("dmg_min", 1) + (f - 1) / 3
	stats.max_damage  = _type.get("dmg_max", 4) + (f - 1) / 2
	stats.armor       = 0
	stats.armor_class = _type.get("ac", 10) + _type.get("armor", 0) + f / 5
	stats.current_hp  = stats.max_hp
	exp_reward        = _type.get("exp", 5)
	cr                = float(_type.get("cr", 0.25))
	creature_type     = String(_type.get("creature_type", "Humanoid"))
	legendary_resistances_remaining = int(_type.get("legendary_resistances", 0))

	# Ability score modifiers (docs/architecture/enemy-stat-block-design.md §4). "mods" is the
	# real stat block (six ability modifiers); an entry that supplies it switches to the real
	# mod+proficiency formula EVERYWHERE (checks, attacks) INSTEAD OF the legacy floor-scaling
	# bonus — never both (see resist_check_detailed()/_attack_bonus()). str_mod/con_mod/dex_mod/
	# wis_mod/int_mod stay as the fallback for unmigrated entries.
	_mods = _type.get("mods", {})
	_check_profs = Array(_type.get("check_profs", []), TYPE_STRING, "", null)
	_attack_prof = bool(_type.get("attack_prof", true))
	if not _mods.is_empty():
		# Default proficiency bonus derived from CR, D&D-style: +2 at CR 1-4, +3 at 5-8, ...
		_prof_bonus = int(_type.get("prof_bonus", 2 + maxi(0, ceili(cr) - 1) / 4))
		stats.strength      = 10 + int(_mods.get("str", 0)) * 2
		stats.dexterity     = 10 + int(_mods.get("dex", 0)) * 2
		stats.constitution  = 10 + int(_mods.get("con", 0)) * 2
		stats.intelligence  = 10 + int(_mods.get("int", 0)) * 2
		stats.wisdom        = 10 + int(_mods.get("wis", 0)) * 2
		stats.charisma      = 10 + int(_mods.get("cha", 0)) * 2
	else:
		_prof_bonus = 0
		stats.strength      = 10 + _type.get("str_mod", 0) * 2
		stats.constitution  = 10 + _type.get("con_mod", 0) * 2
		stats.dexterity     = 10 + _type.get("dex_mod", 0) * 2
		stats.wisdom        = 10 + _type.get("wis_mod", 0) * 2
		stats.intelligence  = 10 + _type.get("int_mod", 0) * 2

	# Passive Perception (stealth-and-surprise-attacks-design.md §3.2): an authored
	# "passive_perception" pool key always wins (same "authored field overrides formula"
	# precedent as "cr"); absent, derive the real 5e formula from the now-resolved WIS score.
	passive_perception = int(_type.get("passive_perception", 10 + stats.wis_modifier()))

	# Damage resist/immune/vuln (§5) — three explicit multiplier lists, priority immunity >
	# vulnerability > resistance (an entry listing a type in more than one is an authoring error).
	# Legacy "resist"/"vuln" keys are read as a fallback so unmigrated entries keep working.
	damage_resistances     = Array(_type.get("damage_resistances", _type.get("resist", [])), TYPE_STRING, "", null)
	damage_vulnerabilities = Array(_type.get("damage_vulnerabilities", _type.get("vuln", [])), TYPE_STRING, "", null)
	damage_immunities      = Array(_type.get("damage_immunities", []), TYPE_STRING, "", null)
	condition_immunities   = Array(_type.get("condition_immunities", []), TYPE_STRING, "", null)

# Single chokepoint for typed damage against this enemy — applies immunity (×0) / vulnerability
# (×2) / resistance (×0.5), priority in that order (§5), before Stats.take_damage()'s flat
# floor-at-1 clamp. Also the two trait hooks that fire off a hit (§11): a "regeneration" trait's
# shutoff_types block next turn's heal, and an "undead_fortitude" trait may intercept a lethal hit.
# Returns {actual, mul} so callers can show the multiplier in a damage tooltip. Every player
# attack/spell call site that deals damage to an enemy should route through this instead of
# calling stats.take_damage() directly — see scripts/entities/CLAUDE.md's "Damage types /
# resistances" section.
func take_typed_damage(amount: int, damage_type: String, is_crit: bool = false) -> Dictionary:
	for tr: Dictionary in _type.get("traits", []):
		if tr.get("id", "") == "regeneration" and damage_type in Array(tr.get("shutoff_types", []), TYPE_STRING, "", null):
			_regen_blocked_this_round = true
	var mul: float = 1.0
	if damage_type in damage_immunities:
		mul = 0.0
	elif damage_type in damage_vulnerabilities:
		mul = 2.0
	elif damage_type in damage_resistances:
		mul = 0.5
	if mul == 0.0:
		return {"actual": 0, "mul": 0.0}
	var effective: int = maxi(1, int(floor(amount * mul))) if mul != 1.0 else amount
	# Undead Fortitude (§11) never triggers on Radiant damage or a critical hit — matches the D&D
	# trait text exactly (Zombie is the first user, worked example in the design doc's §18).
	if effective >= stats.current_hp and not _undead_fortitude_used and damage_type != "Radiant" and not is_crit:
		for tr: Dictionary in _type.get("traits", []):
			if tr.get("id", "") != "undead_fortitude":
				continue
			var dc: int = int(tr.get("dc_base", 5)) + effective
			if resist_check_detailed(dc, true)["pass"]:
				_undead_fortitude_used = true
				effective = stats.current_hp - 1
				GameState.game_log("[color=gray]%s's Undead Fortitude keeps it standing![/color]" % display_name)
			break
	var actual: int = stats.take_damage(effective)
	# Shape Shift (Imp): any actual damage taken (an immune hit deals 0 and returned earlier above,
	# so this never fires from those) reverts a shape-shifted enemy to its true form immediately.
	if actual > 0 and _shifted_form != "":
		_shifted_form = ""
	return {"actual": actual, "mul": mul}

# Single chokepoint for applying a condition to this enemy (§6) — a separate axis from typed
# damage immunity above: this blocks the STATUS COUNTER from ever being set, no matter what
# applied it. Returns whether it stuck (false + a gray "unaffected" log line on immunity).
func apply_status(condition: String, turns: int) -> bool:
	if condition in condition_immunities:
		GameState.game_log("[color=gray]%s is unaffected.[/color]" % display_name)
		return false
	match condition:
		"slowed":   slowed_turns = maxi(slowed_turns, turns)
		"rooted":   rooted_turns = maxi(rooted_turns, turns)
		"prone":    prone_turns  = maxi(prone_turns, turns)
		"poisoned": stats.poison_turns  = maxi(stats.poison_turns, turns)
		"burning":  stats.burning_turns = maxi(stats.burning_turns, turns)
		"bleeding": stats.bleeding_turns = maxi(stats.bleeding_turns, turns)
	return true

# Nimble Escape (Goblin trait): after taking damage from a MELEE attack, the enemy's next action(s)
# become fleeing the attacker for a random 1-5 turns instead of acting normally — see the
# escape_turns branch in _decide_action() and _flee_from() below. Wired only into the melee-only
# player attack call sites (_bump_attack/_resolve_cleave_attack/_resolve_offhand_attack/
# resolve_opportunity_attack in player.gd) — NOT ranged/thrown/spell hits, which aren't "a melee
# attack" by the trait's own text.
func on_melee_hit(attacker: Node) -> void:
	if stats.is_dead() or not _has_trait("nimble_escape"):
		return
	escape_turns = Rng.range_i(1, 5)
	escape_from = attacker

# Traits (§11): "regeneration" heals at the top of a real turn unless a shutoff-type hit landed
# last round (take_typed_damage() sets _regen_blocked_this_round). Called from take_turn().
func _tick_regeneration() -> void:
	for tr: Dictionary in _type.get("traits", []):
		if tr.get("id", "") != "regeneration":
			continue
		if _regen_blocked_this_round:
			_regen_blocked_this_round = false
			return
		if stats.current_hp < stats.max_hp:
			var healed: int = mini(int(tr.get("amount", 0)), stats.max_hp - stats.current_hp)
			if healed > 0:
				stats.current_hp += healed
				GameState.game_log("[color=gray]%s regenerates %d HP.[/color]" % [display_name, healed])
		return

# Invisibility ability (Imp, pool "invisibility"): ticks the cast-again cooldown and the active
# duration every real turn. Ending via duration expiry restores visibility the same way
# _end_invisibility() does when it ends early from attacking (see _attack_target()).
func _tick_invisibility() -> void:
	if _invis_cooldown_remaining > 0:
		_invis_cooldown_remaining -= 1
	if _invis_turns > 0:
		_invis_turns -= 1
		if _invis_turns <= 0:
			_end_invisibility()

func is_hidden_from_player() -> bool:
	return _invis_turns > 0

func _end_invisibility() -> void:
	_invis_turns = 0
	visible = _dungeon_floor.is_tile_visible(grid_pos) if _dungeon_floor != null else true

# Shape Shift (Imp, trait "shape_shift"): while CHASING and the player hasn't seen this enemy on
# THIS turn (either it's out of the player's FOV, or it's currently Invisible), 50% chance per
# eligible turn to secretly transform into a random small-critter form (SHAPE_SHIFT_FORMS) — no
# turn cost. "Hasn't seen it for at least 1 turn" is simplified to "isn't seen right now" (checked
# once per turn at decision time) rather than a running unseen-turn counter — same one-shot-
# checked-at-use-time simplification precedent as Mind Sliver's penalty die. Reverts to the true
# Imp form the instant it takes any damage — see take_typed_damage()'s revert call.
func _tick_shape_shift() -> void:
	if _shifted_form != "" or not _has_trait("shape_shift") or behavior != Behavior.CHASING:
		return
	if _dungeon_floor == null:
		return
	var unseen: bool = is_hidden_from_player() or not _dungeon_floor.is_tile_visible(grid_pos)
	if unseen and Rng.chance(0.5):
		_shifted_form = SHAPE_SHIFT_FORMS[Rng.range_i(0, SHAPE_SHIFT_FORMS.size() - 1)]

# Movement-speed scaling (§ "Ranged distance scaling convention"'s sibling rule — see
# scripts/entities/CLAUDE.md's "Movement speed scaling" note): D&D's default speed is 30 ft = our
# baseline of 1 tile/turn. Pool key "speed": {"moves": N, "per": M} authors a creature slower
# (moves < per, e.g. Zombie's 20 ft -> {"moves": 2, "per": 3}: skips movement roughly 1 turn in 3)
# or faster (moves > per) than baseline. Absent = {"moves": 1, "per": 1}, i.e. exactly today's
# unconditional 1-move-every-turn behavior — zero change for every enemy that doesn't author it.
# Bresenham-style integer accumulator (no floats, no drift) — same technique as the FOV
# shadowcasting multiplier tables, sets _moves_this_turn for _decide_action()/_act_toward() to
# consume. Called once per real turn from take_turn(), alongside _tick_abilities()/_tick_regeneration().
# Dual ground/flying speed (Imp): an entry with BOTH "speed_ground" and "speed_flying" picks
# between them by current `behavior` instead of a single flat "speed" — flying while CHASING/
# SEARCHING (knowingly pursuing or still hunting a lost target), grounded otherwise (SLEEPING/
# STATIONARY/ROAMING). Falls back to the legacy single "speed" key (or the {1,1} default) whenever
# either half of the pair is missing, so every existing single-speed entry is unaffected.
func _tick_speed_gate() -> void:
	var sp: Dictionary = _type.get("speed", {})
	if _shifted_form != "":
		# Shape Shift (Imp): all three animal forms share the same mundane ground speed regardless
		# of the true form's own speed_ground/speed_flying pair — none of them can fly.
		sp = {"moves": 2, "per": 3}
	elif _type.has("speed_ground") and _type.has("speed_flying"):
		sp = _type["speed_flying"] if behavior in [Behavior.CHASING, Behavior.SEARCHING] else _type["speed_ground"]
	var moves: int = int(sp.get("moves", 1))
	var per: int = maxi(1, int(sp.get("per", 1)))
	_speed_accum += moves
	_moves_this_turn = 0
	while _speed_accum >= per:
		_speed_accum -= per
		_moves_this_turn += 1

# Pool "traits" membership check (id-only presence, no payload) — e.g. Orc Warrior's "aggressive".
func _has_trait(id: String) -> bool:
	for tr: Dictionary in _type.get("traits", []):
		if tr.get("id", "") == id:
			return true
	return false

# "advantage_bonus" trait (Goblin Warrior/Archer): whenever this enemy's OWN attack roll lands
# with net Advantage, its damage gets one extra die (pool `{"id": "advantage_bonus", "sides": N}`,
# default 4 — a d4). Returns the die size, or 0 if the enemy doesn't carry this trait at all (0 =
# "don't roll a bonus die" — the caller only rolls when both this is nonzero AND the roll had
# advantage). Rolled by _attack_player()/_attack_companion(), which both already have the roll
# result (`_resolve_attack_roll()`'s "adv" key — net advantage, disadvantage already cancelled out).
func _advantage_bonus_sides() -> int:
	for tr: Dictionary in _type.get("traits", []):
		if tr.get("id", "") == "advantage_bonus":
			return int(tr.get("sides", 4))
	return 0

# Ability cooldowns/uses/recharge (§12) — decremented/rolled once per real turn regardless of
# what action was actually taken this turn. Called from take_turn().
func _tick_abilities() -> void:
	for id: String in _ability_cooldowns.keys():
		if _ability_cooldowns[id] > 0:
			_ability_cooldowns[id] -= 1
	for ab: Dictionary in _type.get("abilities", []):
		var id: String = ab.get("id", "")
		if ab.has("recharge") and not bool(_ability_recharge_ready.get(id, false)):
			if Rng.roll(6) >= int(ab["recharge"]):
				_ability_recharge_ready[id] = true

func _ability_ready(id: String, ab: Dictionary) -> bool:
	if ab.has("cooldown"):
		return int(_ability_cooldowns.get(id, 0)) <= 0
	if ab.has("uses_max"):
		return int(_ability_uses.get(id, int(ab["uses_max"]))) > 0
	if ab.has("recharge"):
		return bool(_ability_recharge_ready.get(id, false))
	return true

func _consume_ability(id: String, ab: Dictionary) -> void:
	if ab.has("cooldown"):
		_ability_cooldowns[id] = int(ab["cooldown"])
	if ab.has("uses_max"):
		_ability_uses[id] = int(_ability_uses.get(id, int(ab["uses_max"]))) - 1
	if ab.has("recharge"):
		_ability_recharge_ready[id] = false

# Picks a ready ability whose range covers `target`, preferring it over melee approach ONLY while
# not already melee-adjacent (matches the stat-block doc's Skeleton example: snipe at range,
# switch to melee once close). Returns {} if no ability qualifies. An optional "long_range" key
# extends the reachable distance beyond "range" (weapon-style normal/long split — see
# _ability_is_long_shot()); a shot only possible at long_range still counts as "in range" here,
# it just rolls with Disadvantage when actually executed.
func _pick_ready_ability(target: Node) -> Dictionary:
	var abilities: Array = _type.get("abilities", [])
	if abilities.is_empty() or _chebyshev_to(target) <= 1:
		return {}
	if _dungeon_floor == null or not _dungeon_floor.has_ranged_los(grid_pos, target.grid_pos):
		return {}
	for ab: Dictionary in abilities:
		var id: String = ab.get("id", "")
		var max_reach: int = int(ab.get("long_range", ab.get("range", 5)))
		if id == "" or _chebyshev_to(target) > max_reach:
			continue
		if _ability_ready(id, ab):
			return ab
	return {}

# True when `ab` has a "long_range" key AND target is beyond its "range" (but within long_range,
# already guaranteed by _pick_ready_ability's max_reach check) — the weapon-style normal/long
# range split (mirrors PlayerRanged.ranged_shot_disadvantage()), Disadvantage instead of an
# outright miss. Skeleton's Shortbow ("range": 8, "long_range": 32) is the first user.
func _ability_is_long_shot(ab: Dictionary, target: Node) -> bool:
	return ab.has("long_range") and _chebyshev_to(target) > int(ab.get("range", 999))

# Rolls d20 + (con_modifier if use_con else str_modifier) vs dc.
# Used by World Tree's Grip of the Forest (STR) and Branching Strike R3 push (CON).
# Returns true if the enemy RESISTS (roll >= dc).
func resist_check(dc: int, use_con: bool = false) -> bool:
	return resist_check_detailed(dc, use_con)["pass"]

# Same roll as resist_check(), but returns the full breakdown so callers can log a chat-log
# tooltip (see Topple's "save" meta in player.gd._try_topple()) instead of just the pass/fail
# bool. "pass" here means the enemy RESISTS (roll >= dc), matching resist_check().
# Priority when multiple use_* flags are somehow true: DEX > WIS > INT > CON > STR (arbitrary —
# every real call site only ever sets one).
# `magical`: true when this check is a saving throw against a SPELL (Ray of Frost, Toll the Dead,
# Mind Sliver, Thunderclap, Fireball) — NOT a weapon-mastery save (Push/Topple/Grip of the Forest/
# Branching Strike), which aren't spells and never pass this. Combined with the "magic_resistance"
# trait (Imp), rolls the d20 with Advantage (max of two rolls) — Magic Resistance's real D&D text.
func resist_check_detailed(dc: int, use_con: bool = false, use_dex: bool = false, use_wis: bool = false, use_int: bool = false, magical: bool = false) -> Dictionary:
	var mod: int
	var stat_name: String
	var stat_key: String
	if use_dex:
		mod = stats.dex_modifier(); stat_name = "DEX"; stat_key = "dex"
	elif use_wis:
		mod = stats.wis_modifier(); stat_name = "WIS"; stat_key = "wis"
	elif use_int:
		mod = stats.int_modifier(); stat_name = "INT"; stat_key = "int"
	elif use_con:
		mod = stats.con_modifier(); stat_name = "CON"; stat_key = "con"
	else:
		mod = stats.str_modifier(); stat_name = "STR"; stat_key = "str"
	# §4: an entry with "mods" rolls d20 + mod + (prof_bonus if that stat is in "check_profs")
	# INSTEAD OF the legacy floor-scaling bonus — never both. prof_label distinguishes the two
	# in the hover tooltip (TooltipFormatters.fmt_save_tooltip()).
	var bonus: int
	var prof_label: String
	if _mods.is_empty():
		bonus = GameState.current_floor / 3
		prof_label = "Floor"
	else:
		bonus = _prof_bonus if stat_key in _check_profs else 0
		prof_label = "Proficiency"
	var die: int = Rng.roll(20)
	var magic_resistance_adv: bool = magical and _has_trait("magic_resistance")
	if magic_resistance_adv:
		die = maxi(die, Rng.roll(20))
	# Mind Sliver cantrip: the target's next check (any resist_check_detailed() call) rolls with
	# -1d4 — consumed here regardless of which stat this particular check happens to use.
	var sliver_penalty: int = 0
	if mind_sliver_penalty_die:
		mind_sliver_penalty_die = false
		sliver_penalty = Rng.roll(4)
	var total: int = die + bonus + mod - sliver_penalty
	var passed: bool = total >= dc
	# Legendary Resistance (§15, BOSS_POOL only): consumes a charge to force a pass on what would
	# otherwise be a failed check. Per-life counter — enemies don't rest, so "N/day" = N/life.
	var legendary_used: bool = false
	if not passed and legendary_resistances_remaining > 0:
		legendary_resistances_remaining -= 1
		passed = true
		legendary_used = true
		GameState.game_log("[color=gray]%s shrugs off the effect. (Legendary Resistance, %d remaining)[/color]" % [display_name, legendary_resistances_remaining])
	return {
		"die": die, "mod": mod, "floor_bonus": bonus, "prof_label": prof_label, "dc": dc,
		"total": total, "pass": passed, "stat": stat_name, "sliver_penalty": sliver_penalty,
		"legendary_used": legendary_used,
	}

# Overrides Entity.die(): drop any thrown weapons embedded in this enemy (see embedded_items
# above) at 100% chance before freeing — regardless of what actually killed it or how many turns
# ago they were embedded. Every death call site (player.gd._finish_kill, companion.gd, trap/chasm
# deaths in dungeon_floor.gd) already calls enemy.die() as its last step, so this single override
# covers all of them with no other call site changes needed.
func die() -> void:
	# Gold economy (special-rooms-economy-design.md §2.3): non-boss enemies have a 30% chance
	# to drop a gold pile at their death tile — resolved by DungeonFloor.maybe_drop_enemy_gold()
	# on the gameplay Rng stream. Hooked here for the same reason as embedded_items below: every
	# death call site already ends with die(), so one hook covers them all.
	if _dungeon_floor != null:
		_dungeon_floor.maybe_drop_enemy_gold(self)
	if not embedded_items.is_empty() and _dungeon_floor != null:
		for it: Item in embedded_items:
			_dungeon_floor.place_item_on_floor(grid_pos, it)
		embedded_items.clear()
	# A one-shot thrown weapon (Goblin Minion's Dagger, Orc Warrior's Javelin), whether it hit or
	# missed: queued for a per-enemy drop chance to be found near whoever it was thrown at,
	# resolved on the player's next turn (see DungeonFloor.queue_thrown_weapon_drop()/
	# _resolve_pending_thrown_weapon_drops()) — not dropped here directly, since "the turn after it
	# dies" is a deliberate one-turn delay, not an instant drop.
	if _thrown_weapon_lodged_target != null and is_instance_valid(_thrown_weapon_lodged_target) and _dungeon_floor != null:
		_dungeon_floor.queue_thrown_weapon_drop(_thrown_weapon_lodged_target, _thrown_weapon_lodged_item, _thrown_weapon_lodged_chance)
	super.die()

func _setup_animations() -> void:
	var prefix: String = _type.get("sprite", "orc_warrior")
	var idle_n: int    = _type.get("idle_frames", 4)
	var run_n: int     = _type.get("run_frames", 4)
	var idle_fmt: String = _type.get("idle_fmt", SPRITES_PATH + prefix + "_idle_anim_f%d.png")
	var run_fmt: String  = _type.get("run_fmt",  SPRITES_PATH + prefix + "_run_anim_f%d.png")
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", idle_fmt, idle_n, true,  8.0)
	_add_anim(frames, "run",  run_fmt,  run_n, false, 16.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -8)
	$AnimatedSprite2D.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i: int in count:
		frames.add_frame(anim_name, load(path_fmt % i))

func _setup_zzz() -> void:
	_zzz_label = Label.new()
	_zzz_label.text = "z z z"
	_zzz_label.add_theme_font_size_override("font_size", 7)
	_zzz_label.position = Vector2(-9, -22)
	_zzz_label.z_index = 4
	_zzz_label.modulate.a = 0.0
	_zzz_label.visible = false
	add_child(_zzz_label)

func _start_zzz() -> void:
	if not is_instance_valid(_zzz_label):
		return
	_zzz_label.visible = true
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
	_zzz_tween = create_tween().set_loops()
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 1.0, 1.0)
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 0.3, 1.0)

func _stop_zzz() -> void:
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
		_zzz_tween = null
	if is_instance_valid(_zzz_label):
		_zzz_label.visible = false

func _setup_notice_mark() -> void:
	_notice_label = Label.new()
	_notice_label.text = "?"
	_notice_label.add_theme_font_size_override("font_size", 16)
	_notice_label.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	_notice_label.position = Vector2(-4, -24)
	_notice_label.z_index = 10
	_notice_label.visible = false
	add_child(_notice_label)

func _show_notice_mark() -> void:
	if is_instance_valid(_notice_label):
		_notice_label.visible = true

func _hide_notice_mark() -> void:
	if is_instance_valid(_notice_label):
		_notice_label.visible = false

func _wake_up() -> void:
	behavior = Behavior.CHASING
	_stop_zzz()

# Shared by every "just spotted the player, hasn't acted on it yet" transition (stealth-check
# notice, SLEEPING's true-adjacency backstop, STATIONARY/ROAMING's can-see wake): wakes to
# CHASING and flags just_noticed so the very next _decide_action() burns this round showing the
# golden "?" instead of moving/attacking — "noticed intent this round, acts on it next round".
# Deliberately NOT used by the wake-on-attacked path below (that one still acts immediately).
func _notice_target(source_pos: Vector2i) -> void:
	_wake_up()
	last_known_target_pos = source_pos
	just_noticed = true
	_show_notice_mark()
	GameState.enemy_noticed_player_this_turn = true

# Wake-on-attacked (stealth-and-surprise-attacks-design.md §3.5): call after EVERY player-side
# attack against this enemy, hit or miss — you swung steel near its head. Only meaningful while
# still unaware; a CHASING/SEARCHING enemy is already awake, so this is a no-op for them. Unlike
# _notice_target() above, this wakes the enemy WITHOUT the notice freeze — it can act (retaliate)
# on its very next turn, since being struck is a much bigger tell than merely being spotted.
# Also unconditionally cancels an ALREADY-PENDING notice freeze from a prior round (just_noticed/
# the "?" marker) — being directly attacked always overrides "merely noticed", even if the enemy
# had already spotted the player one or more rounds ago and was still sitting on its freebie
# freeze round when the attack landed.
func on_disturbed(source_pos: Vector2i) -> void:
	if just_noticed:
		just_noticed = false
		_hide_notice_mark()
	if behavior in [Behavior.SLEEPING, Behavior.STATIONARY, Behavior.ROAMING]:
		_wake_up()
		last_known_target_pos = source_pos

# Public wrapper for the Stealth-vs-Passive-Perception check (player.gd) — reuses the exact same
# sight metric take_turn() uses internally, verbatim.
func can_see(target: Node) -> bool:
	return _can_see_entity(target)

# Threat range in tiles for Opportunity Attacks. Flat 1 for all current enemies (pool key
# "reach", default 1) — a future reach enemy (whip skeleton, tentacle boss) is a one-line pool entry.
func melee_reach() -> int:
	return _type.get("reach", 1)

# --- Targeting (§5 of docs/architecture/enemy_system_architecture.md) ---
# Both the player and the Wild Heart companion are valid targets: whoever first gets into the
# enemy's attack range wins the fight, re-evaluated fresh every turn — no target-lock state.
func _get_target_candidates() -> Array:
	var out: Array = []
	var player: Player = _dungeon_floor.get_player()
	if player != null and is_instance_valid(player) and not player.stats.is_dead():
		out.append(player)
	var comp: Variant = GameState.player_companion
	if comp != null and is_instance_valid(comp) and not comp.stats.is_dead():
		out.append(comp)
	return out

func _dist_sq_to(e: Node) -> int:
	var dx: int = e.grid_pos.x - grid_pos.x
	var dy: int = e.grid_pos.y - grid_pos.y
	return dx * dx + dy * dy

func _chebyshev_to(e: Node) -> int:
	return maxi(absi(e.grid_pos.x - grid_pos.x), absi(e.grid_pos.y - grid_pos.y))

# §10: pool "senses" -> "sight_bonus" is an offset relative to FOV_RADIUS (e.g. +1 = darkvision,
# +2 = superior darkvision, -1 = weak sight), so changing the default FOV_RADIUS doesn't require
# re-touching every enemy's authored value. Absent = 0 (FOV_RADIUS unchanged).
func _sight_range() -> int:
	return FOV_RADIUS + int(_type.get("senses", {}).get("sight_bonus", 0))

func _can_see_entity(e: Node) -> bool:
	# Invisibility (player-cast spell, or a future invisible companion): an invisible target is
	# treated as fully unseen regardless of distance/LOS — per direct owner design, enemies don't
	# "try" to track it; they just lose it like any other lost-sight target (existing CHASING ->
	# reaches last_known_target_pos -> SEARCHING -> ROAMING flow already covers "goes to where it
	# vanished, searches briefly, then gives up").
	if e is Player and GameState.player_stats.invisibility_turns > 0:
		return false
	var r: int = _sight_range()
	return _dist_sq_to(e) <= r * r and _dungeon_floor.has_line_of_sight(grid_pos, e.grid_pos)

# door_ambush gate (§4.3): true if this enemy could already see the player from `from_pos`
# (BEFORE the door step) — used to tell "door-camping ambush" (no prior LOS) apart from an
# already-aware hunter that simply opened a door mid-chase (has LOS, no ambush).
func _had_los_to_player_from(from_pos: Vector2i) -> bool:
	var player: Player = _dungeon_floor.get_player()
	if player == null or not is_instance_valid(player):
		return false
	var r: int = _sight_range()
	var dx: int = player.grid_pos.x - from_pos.x
	var dy: int = player.grid_pos.y - from_pos.y
	return dx * dx + dy * dy <= r * r and _dungeon_floor.has_line_of_sight(from_pos, player.grid_pos)

# Adjacency wins first (first to reach range gets attacked); ties broken by lower current HP.
# Otherwise, whichever candidate is nearer is the one stepped toward / seen.
func _select_target(candidates: Array) -> Node:
	var adjacent: Array = []
	for c: Node in candidates:
		if _chebyshev_to(c) == 1:
			adjacent.append(c)
	if adjacent.size() == 1:
		return adjacent[0]
	if adjacent.size() > 1:
		var best: Node = adjacent[0]
		for c: Node in adjacent:
			if c.stats.current_hp < best.stats.current_hp:
				best = c
		return best
	var nearest: Node = candidates[0]
	var nearest_d: int = _dist_sq_to(nearest)
	for c: Node in candidates:
		var d: int = _dist_sq_to(c)
		if d < nearest_d:
			nearest_d = d
			nearest = c
	return nearest

func take_turn() -> void:
	oa_used_this_round = false
	door_ambush = false  # lifetime = exactly one round ("the round it came through the door")
	if _dungeon_floor == null:
		return
	_tick_abilities()
	_tick_regeneration()
	_tick_speed_gate()
	_tick_invisibility()
	_tick_shape_shift()
	if prone_turns > 0:
		prone_turns -= 1
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return
	if slowed_turns > 0:
		slowed_turns -= 1
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return

	var intent: Dictionary = _decide_action()
	await _execute_action(intent)

# Pure(ish) decision step — reads state, mutates only internal FSM/target-memory fields (not
# visuals), returns an intent for _execute_action() to carry out. See docs/architecture/
# enemy_system_architecture.md §1.
func _decide_action() -> Dictionary:
	# Just noticed the player this round (stealth-check notice from the player's own turn, set via
	# on_disturbed(..., true)/_notice_target()) — burn this round showing the "?" instead of
	# moving/attacking. Consumed here so it only ever costs the one round right after noticing.
	if just_noticed:
		just_noticed = false
		return {"type": "notice"}
	var candidates: Array = _get_target_candidates()
	if candidates.is_empty():
		return {"type": "wait"}
	var target: Node = _select_target(candidates)

	# Nimble Escape (Goblin trait): fleeing takes priority over every other behavior below,
	# including attacking an adjacent target — a fleeing goblin doesn't stop to swing.
	if escape_turns > 0:
		escape_turns -= 1
		return {"type": "flee", "target": escape_from if is_instance_valid(escape_from) else target}

	# One-shot thrown weapon (pool "thrown_weapon" — Goblin Minion's Dagger, Orc Warrior's Javelin):
	# once not actively escaping (the check above already guarantees escape_turns <= 0 here), if
	# the target isn't adjacent, throw the weapon at range instead of closing to melee. Doesn't
	# need movement budget, so this is checked before the rooted/frozen/speed-gate movement
	# restrictions below — a rooted or speed-gated enemy can still throw. Generic — keyed purely
	# on the pool key's presence, not on enemy_id, so any enemy can opt in by authoring the same
	# two dict keys (see "thrown_weapon"/"unarmed_fallback" in the Enemy D&D stat-block schema).
	var thrown_wpn: Dictionary = _type.get("thrown_weapon", {})
	if not thrown_wpn.is_empty() and not _thrown_weapon_used:
		var throw_range: int = int(thrown_wpn.get("range", 4))
		var dist: int = _chebyshev_to(target)
		if dist >= 2 and dist <= throw_range and _dungeon_floor.has_ranged_los(grid_pos, target.grid_pos):
			return {"type": "throw_weapon", "target": target, "weapon": thrown_wpn}

	# Imp — Invisibility (pool "invisibility"): while pursuing (CHASING/SEARCHING) and not yet
	# adjacent, casts Invisibility on itself instead of closing distance, once the cooldown is
	# ready and it isn't already invisible. Costs the turn (a real action).
	var invis_cfg: Dictionary = _type.get("invisibility", {})
	if not invis_cfg.is_empty() and _invis_turns <= 0 and _invis_cooldown_remaining <= 0 \
			and behavior in [Behavior.CHASING, Behavior.SEARCHING] and _chebyshev_to(target) > 1:
		return {"type": "cast_invisibility", "config": invis_cfg}

	# World Tree Grip of the Forest R2: rooted — no movement this turn, but can still attack if adjacent.
	if rooted_turns > 0:
		rooted_turns -= 1
		if _chebyshev_to(target) == 1:
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	# Ray of Frost's Frozen Feet — same shape as rooted_turns above (no movement, can still attack).
	if frozen_feet_turns > 0:
		frozen_feet_turns -= 1
		if _chebyshev_to(target) == 1:
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	# Movement-speed scaling (§ "Movement speed scaling"): a below-baseline "speed" pool entry
	# (e.g. Zombie) can roll a turn with zero movement credit — same shape as rooted_turns above,
	# still attacks if already adjacent.
	if _moves_this_turn <= 0:
		if _chebyshev_to(target) == 1:
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	var can_see: bool = _can_see_entity(target)
	var dx: int = target.grid_pos.x - grid_pos.x
	var dy: int = target.grid_pos.y - grid_pos.y

	match behavior:
		Behavior.SLEEPING:
			# LOS-based deterministic wake is gone — replaced by the player-turn Stealth-vs-
			# Passive-Perception check (player.gd._resolve_stealth_check()). This is only the
			# free-wake backstop at true adjacency (stealth-and-surprise-attacks-design.md §3.4):
			# lingering adjacent without ever having been noticed still wakes it, but — same as
			# every other notice path — it only notices this round (golden "?"), acting next round.
			if _chebyshev_to(target) <= 1:
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "wait"}

		Behavior.STATIONARY:
			if can_see:
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "wait"}

		Behavior.ROAMING:
			if can_see:
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "roam"}

		Behavior.CHASING:
			if can_see:
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
			return _act_toward_or_ability(target, can_see, {"chasing": true})

		Behavior.SEARCHING:
			if can_see:
				behavior = Behavior.CHASING
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
				return _act_toward_or_ability(target, can_see)
			return {"type": "search"}

	return {"type": "wait"}

# Shared by every _decide_action() branch above that would otherwise return a bare "act_toward"
# intent: prefers a ready ability (§3/§12) over the melee-approach path whenever one is in range
# and the target isn't already adjacent (see _pick_ready_ability()'s doc comment).
func _act_toward_or_ability(target: Node, can_see: bool, extra: Dictionary = {}) -> Dictionary:
	if can_see:
		var ab: Dictionary = _pick_ready_ability(target)
		if not ab.is_empty():
			return {"type": "ability", "ability_id": ab.get("id", ""), "target": target, "ability": ab}
	var intent: Dictionary = {"type": "act_toward", "target": target, "can_see": can_see}
	intent.merge(extra)
	return intent

# All the tween/animation/await/log side effects, dispatched on intent.type. See docs/
# architecture/enemy_system_architecture.md §1.
func _execute_action(intent: Dictionary) -> void:
	# The "?" marker is a one-round flag — clear it the instant this enemy takes any real action
	# (the round after noticing), so it never lingers into a turn where the enemy is actually
	# chasing/attacking. "notice" itself is handled by its own case below (label stays up).
	if intent.get("type", "wait") != "notice":
		_hide_notice_mark()
	match intent.get("type", "wait"):
		"notice":
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"attack":
			_attack_target(intent["target"])
		"flee":
			var fled: bool = await _flee_from(intent["target"])
			if not fled and is_instance_valid(self) and not stats.is_dead():
				# Cornered: couldn't step directly away (wall/occupied tile behind it) — turns and
				# fights instead of idling in place, if whatever it's fleeing is in attack range.
				var flee_target: Node = intent["target"]
				if is_instance_valid(flee_target) and not flee_target.stats.is_dead() and _in_attack_range(flee_target):
					_attack_target(flee_target)
		"throw_weapon":
			_execute_thrown_weapon_attack(intent["target"], intent["weapon"])
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"cast_invisibility":
			_execute_cast_invisibility(intent["config"])
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"act_toward":
			# Aggressive (§ trait): while it can see its target, gets one extra movement step this
			# turn on top of whatever _moves_this_turn/speed already grants — Orc Warrior's trait.
			var bonus_moves: int = 1 if (intent.get("can_see", false) and _has_trait("aggressive")) else 0
			await _act_toward(intent["target"], bonus_moves)
			if not is_instance_valid(self) or stats.is_dead():
				return
			# Reached last known position without spotting the target — enter search mode.
			if intent.get("chasing", false) and not intent.get("can_see", false) \
					and last_known_target_pos != Vector2i(-1, -1) and grid_pos == last_known_target_pos:
				behavior = Behavior.SEARCHING
				_search_turns_remaining = 7
				_search_target = last_known_target_pos + _search_heading * 5
				_search_path.clear()
				last_known_target_pos = Vector2i(-1, -1)
		"ability":
			_execute_ability(intent)
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"roam":
			await _do_roam_walk()
		"search":
			if _search_turns_remaining > 0:
				_search_turns_remaining -= 1
				if _search_path.is_empty() or grid_pos == _search_target:
					_search_path = _bfs_to(_search_target)
				if not _search_path.is_empty():
					var next: Vector2i = _search_path[0]
					_search_path = _search_path.slice(1)
					await _move_step(next - grid_pos, next)
				else:
					await _do_random_step()
			else:
				behavior = Behavior.ROAMING
				_search_target = Vector2i(-1, -1)
				_search_path.clear()
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				# State transition only, no movement this turn — still await the idle timer
				# (see the matching comment in _act_toward()'s BFS-fallback-failure path).
				await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"wait":
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

# True if `target` is within this enemy's current attack_profile range (melee default = adjacent).
func _in_attack_range(target: Node) -> bool:
	var profile: Dictionary = _type.get("attack_profile", {})
	match profile.get("kind", "melee"):
		"ranged":
			var rng: int = profile.get("range", 4)
			return _chebyshev_to(target) <= rng and _dungeon_floor.has_ranged_los(grid_pos, target.grid_pos)
		_:
			return _chebyshev_to(target) == 1

# Multiattack (§12): pool "multiattack" is a list of sub-attacks ({name, count, dmg_min, dmg_max,
# damage_type}), each swing resolved as its own independent roll/floater/log line via the SAME
# _attack_player()/_attack_companion() functions (they accept an optional `sub` dict — see below).
# Absent = today's single top-level-stats attack, unchanged.
func _attack_target(target: Node) -> void:
	# Invisibility ends the instant this enemy attacks (Imp, or the mirrored player spell's own
	# rule) — matches 5e Invisibility's "ends early if you attack" text.
	if _invis_turns > 0:
		_end_invisibility()
		GameState.game_log("[color=purple]%s reappears![/color]" % display_name)
	# Once a one-shot thrown weapon is used (Goblin Minion's Dagger, Orc Warrior's Javelin), every
	# attack reverts to an unarmed Fist strike (pool "unarmed_fallback") instead of the normal
	# multiattack — the weapon is gone, thrown at range earlier this fight.
	var fallback: Dictionary = _type.get("unarmed_fallback", {})
	if _thrown_weapon_used and not fallback.is_empty():
		if target is Player:
			_attack_player(target, fallback)
		elif target is Companion:
			_attack_companion(target, fallback)
		return
	var multi: Array = _type.get("multiattack", [])
	if multi.is_empty():
		if target is Player:
			_attack_player(target)
		elif target is Companion:
			_attack_companion(target)
		return
	for sub: Dictionary in multi:
		for _i: int in int(sub.get("count", 1)):
			if not is_instance_valid(target) or target.stats.is_dead():
				return
			if not is_instance_valid(self) or stats.is_dead():
				return
			if target is Player:
				_attack_player(target, sub)
			elif target is Companion:
				_attack_companion(target, sub)

# Generic ability execution (§3/§12): abilities share the exact same ranged-damage(+status) shape
# as a multiattack sub-attack ({dmg_min, dmg_max, damage_type, name} plus optional {status, turns}),
# so it reuses _attack_player()/_attack_companion() wholesale instead of a second damage path.
func _execute_ability(intent: Dictionary) -> void:
	var ab: Dictionary = intent.get("ability", {})
	var target: Node = intent.get("target")
	if not is_instance_valid(target) or target.stats.is_dead():
		return
	_consume_ability(ab.get("id", ""), ab)
	var long_shot: bool = _ability_is_long_shot(ab, target)
	if target is Player:
		_attack_player(target, ab, long_shot)
	elif target is Companion:
		_attack_companion(target, ab, long_shot)
	if ab.has("status") and target is Player and is_instance_valid(target) and not target.stats.is_dead():
		if GameState.apply_player_status(String(ab["status"]), int(ab.get("turns", 1))):
			GameState.game_log("[color=lime]You are %s! (%d turns)[/color]" % [String(ab["status"]), int(ab.get("turns", 1))])

# Attack if in range of target; otherwise step toward last known / target position — up to
# maxi(1, _moves_this_turn) + bonus_moves steps this call (movement-speed scaling §, plus Orc
# Warrior's Aggressive trait bonus passed in from _execute_action()). Re-checks attack range after
# EVERY step so a multi-step turn stops moving and swings the instant it's in range (covers the
# "move + attack" combo from the trait's D&D text; a target already in range on the very first
# check is the plain "just attack" combo, unchanged from before this was multi-step).
func _act_toward(target: Node, bonus_moves: int = 0) -> void:
	var total_steps: int = maxi(1, _moves_this_turn) + bonus_moves
	for _i: int in total_steps:
		if _in_attack_range(target):
			_attack_target(target)
			return
		var moved: bool = await _act_toward_single_step(target)
		if not is_instance_valid(self) or stats.is_dead():
			return
		if not moved:
			return
	if _in_attack_range(target):
		_attack_target(target)

# One greedy-then-BFS movement step toward `target`'s last-known/current position. Returns true if
# a step was actually taken (already awaited the move tween); false if stuck this turn (already
# awaited the idle timer itself — see the comment below on why that still has to happen).
func _act_toward_single_step(target: Node) -> bool:
	var dest: Vector2i = last_known_target_pos if last_known_target_pos != Vector2i(-1, -1) else target.grid_pos
	var tdx: int = dest.x - grid_pos.x
	var tdy: int = dest.y - grid_pos.y

	for step: Vector2i in _preferred_steps(tdx, tdy):
		var next_pos: Vector2i = grid_pos + step
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)
			return true

	# Greedy failed — BFS fallback to navigate around obstacles. If the BFS route is also empty,
	# or its first step turns out to be unwalkable, the enemy is stuck this turn: still await the
	# idle timer so the turn takes real time instead of resolving instantly (a stuck-but-alive
	# enemy previously made TurnManager burn through the enemy phase with zero elapsed time,
	# which looked like an empty/cleared floor even with TurnManager.fast_mode == false).
	var bfs_path: Array[Vector2i] = _bfs_to(dest)
	if not bfs_path.is_empty():
		var next_pos: Vector2i = bfs_path[0]
		var step: Vector2i = next_pos - grid_pos
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)
			return true
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
	return false

func _pick_roam_target() -> Vector2i:
	var centers: Array[Vector2i] = _dungeon_floor.get_room_centers()
	Rng.shuffle(centers)
	for c: Vector2i in centers:
		if maxi(absi(c.x - grid_pos.x), absi(c.y - grid_pos.y)) < 4:
			continue
		if _dungeon_floor.is_walkable_for_enemy(c):
			return c
	return Vector2i(-1, -1)

func _do_roam_walk() -> void:
	if _roam_path.is_empty() or grid_pos == _roam_target:
		_roam_target = _pick_roam_target()
		if _roam_target == Vector2i(-1, -1):
			await _do_random_step()
			return
		_roam_path = _bfs_to(_roam_target)
		if _roam_path.is_empty():
			_roam_target = Vector2i(-1, -1)
			await _do_random_step()
			return
	var next_pos: Vector2i = _roam_path[0]
	if not _dungeon_floor.is_walkable_for_enemy(next_pos):
		_roam_path.clear()
		_roam_target = Vector2i(-1, -1)
		await _do_random_step()
		return
	_roam_path.remove_at(0)
	if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
		_dungeon_floor.open_door(next_pos)
	await _move_step(next_pos - grid_pos, next_pos)

func _do_random_step() -> void:
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	Rng.shuffle(dirs)
	for dir: Vector2i in dirs:
		var target: Vector2i = grid_pos + dir
		if _dungeon_floor.has_door_at(target):
			continue
		if _dungeon_floor.is_walkable_for_enemy(target):
			await _move_step(dir, target)
			return
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

# Nimble Escape (Goblin trait): step directly away from `from_entity` (the attacker who last hit
# it in melee — see on_melee_hit()/escape_turns above). provokes_oa=false on the _move_step() call
# is the trait's "doesn't provoke Opportunity Attacks while escaping" clause — its own movement can
# never trigger the player/companion OA hook during a flee, unlike every other enemy movement path.
# Greedy-only (no BFS fallback, unlike _act_toward_single_step) — a cornered goblin that can't step
# directly away doesn't path the long way around; it lashes out at whatever cornered it instead
# (see the caller in _execute_action()'s "flee" case, which attacks if this returns false and the
# target is in range — a trapped animal turning to fight, not idling in place).
# Returns true if a step was actually taken (already awaited the move tween); false if stuck.
func _flee_from(from_entity: Node) -> bool:
	var from_pos: Vector2i = from_entity.grid_pos if is_instance_valid(from_entity) else grid_pos
	var dx: int = grid_pos.x - from_pos.x
	var dy: int = grid_pos.y - from_pos.y
	if dx == 0 and dy == 0:
		dx = 1
	for step: Vector2i in _preferred_steps(dx, dy):
		var next_pos: Vector2i = grid_pos + step
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos, false)
			return true
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
	return false

# One-shot thrown weapon (Goblin Minion's Dagger, Orc Warrior's Javelin) — resolves as a normal
# attack but forces Disadvantage via _attack_player()/_attack_companion()'s `long_shot` param
# (reused here purely for its Disadvantage side effect, not its usual normal/long-range meaning).
# Marks _thrown_weapon_used so this only ever fires once per this enemy's life — _attack_target()
# reverts every subsequent attack to "unarmed_fallback" (both Goblin Minion and Orc Warrior author
# one — a bare-handed Fist strike either way). Registers the target with
# DungeonFloor.queue_thrown_weapon_drop() unconditionally, regardless of hit or miss (matches
# Goblin Minion's original behavior exactly) — a per-enemy chance (pool "drop_chance", default 0.5)
# to recover the weapon resolves the turn after THIS enemy dies (see die() below), dropped wherever
# the target stands at that time.
func _execute_thrown_weapon_attack(target: Node, wpn: Dictionary) -> void:
	_thrown_weapon_used = true
	var sub: Dictionary = {
		"name": wpn.get("name", "Dagger"),
		"dmg_min": wpn.get("dmg_min", stats.min_damage),
		"dmg_max": wpn.get("dmg_max", stats.max_damage),
		"damage_type": wpn.get("damage_type", "Piercing"),
	}
	if target is Player:
		_attack_player(target, sub, true)
	elif target is Companion:
		_attack_companion(target, sub, true)
	if _dungeon_floor != null and is_instance_valid(target):
		_thrown_weapon_lodged_target = target
		_thrown_weapon_lodged_item = _build_thrown_weapon_item(wpn)
		_thrown_weapon_lodged_chance = float(wpn.get("drop_chance", 0.5))

# A plain pickupable weapon Item, built generically from the "thrown_weapon" pool dict — NOT from
# the enemy's own dmg_min/dmg_max (those are the enemy's already-ability-mod-inflated attack
# numbers, not the raw weapon's die). Every field has a Dagger-shaped default so Goblin Minion's
# original pool entry (which doesn't set any of these new keys) reproduces its exact old output —
# see the field-by-field defaults below, each matching what the old hardcoded Dagger builder set.
# A new consumer (Orc Warrior's Javelin, or any future one) is expected to set every field itself
# rather than lean on these fallbacks. "random_uses" (default false) picks between an already-full
# weapon (Goblin's Dagger) and a randomly-worn-down one (Orc's Javelin — "already used").
func _build_thrown_weapon_item(wpn: Dictionary) -> Item:
	var it := Item.new()
	it.item_name = wpn.get("name", "Dagger")
	it.item_type = Item.Type.WEAPON
	it.icon_path = DungeonFloorData.WEAPONS_PATH + String(wpn.get("icon", "weapon_knife.png"))
	it.damage_die_min = int(wpn.get("drop_die_min", 1))
	it.damage_die_max = int(wpn.get("drop_die_max", 4))
	it.damage_type = wpn.get("damage_type", "Piercing")
	it.weapon_category = wpn.get("weapon_category", "Simple")
	it.is_finesse = bool(wpn.get("is_finesse", true))
	it.is_light = bool(wpn.get("is_light", true))
	it.is_thrown = true
	it.range = int(wpn.get("range", 3))
	it.weapon_mastery = wpn.get("weapon_mastery", "Nick")
	var uses_max: int = int(wpn.get("drop_uses_max", 5))
	it.uses_max = uses_max
	it.uses_remaining = Rng.range_i(1, uses_max) if bool(wpn.get("random_uses", false)) else uses_max
	return it

# Imp's Invisibility ability (pool "invisibility": {"cooldown", "duration"}) — the enemy-side
# mirror of the player-castable level-2 spell of the same name (SpellEffects' "invisibility"
# effect_id). Hides this enemy's own sprite immediately (also re-applied generically every
# DungeonFloor.update_fog() via _update_enemy_visibility()) and starts the cooldown; ends early on
# attacking (_attack_target()'s hook below) or naturally via _tick_invisibility()'s duration countdown.
func _execute_cast_invisibility(cfg: Dictionary) -> void:
	_invis_turns = int(cfg.get("duration", 100))
	_invis_cooldown_remaining = int(cfg.get("cooldown", 5))
	visible = false
	GameState.game_log("[color=purple]%s fades from view.[/color]" % display_name)

func _move_step(step: Vector2i, next_pos: Vector2i, provokes_oa: bool = true) -> void:
	var prev_pos: Vector2i = grid_pos
	if provokes_oa:
		_check_opportunity_attacks_on_move(prev_pos, next_pos)
	if not is_instance_valid(self) or stats.is_dead():
		return
	var stepping_through_door: bool = _dungeon_floor.has_door_at(next_pos)
	$AnimatedSprite2D.flip_h = step.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(next_pos, 0.04 if TurnManager.fast_mode else 0.08)
	if not is_instance_valid(self):
		return
	$AnimatedSprite2D.play("idle")
	if visible:
		AudioManager.play("footstep")
	if stepping_through_door and not _had_los_to_player_from(prev_pos):
		door_ambush = true
	if _dungeon_floor.has_door_at(prev_pos):
		_dungeon_floor.close_door(prev_pos)
	var tile_type: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	if tile_type == DungeonData.TileType.WATER or tile_type == DungeonData.TileType.MUD:
		apply_status("slowed", 1)
	if tile_type == DungeonData.TileType.GRASS:
		_dungeon_floor.destroy_grass(grid_pos)
	var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
	if not trap.is_empty():
		await _dungeon_floor.trigger_trap(grid_pos, self)

# Opportunity Attacks: this enemy is the mover, the player (and any live companions) are the
# potential attackers. Voluntary-movement chokepoint for ALL enemy movement (chase/roam/random/
# search) — see docs/architecture/opportunity-attacks-design.md. Forced movement (force_move_entity,
# resolve_push) intentionally bypasses this and must NOT call it.
func _check_opportunity_attacks_on_move(prev_pos: Vector2i, next_pos: Vector2i) -> void:
	if _dungeon_floor == null or not _dungeon_floor.is_tile_visible(prev_pos):
		return
	if shocked_no_oa:
		shocked_no_oa = false
		return
	if _invis_turns > 0:
		return
	var player: Player = _dungeon_floor.get_player()
	if player != null and is_instance_valid(player) and not player.stats.is_dead() and not player._oa_used_this_round:
		var reach: int = CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike"))
		var d_prev: int = maxi(absi(prev_pos.x - player.grid_pos.x), absi(prev_pos.y - player.grid_pos.y))
		var d_next: int = maxi(absi(next_pos.x - player.grid_pos.x), absi(next_pos.y - player.grid_pos.y))
		if d_prev <= reach and d_next > reach:
			player._oa_used_this_round = true
			player.resolve_opportunity_attack(self)
			if not is_instance_valid(self) or stats.is_dead():
				return
	for c: Node in get_tree().get_nodes_in_group("companions"):
		var comp: Companion = c as Companion
		if comp == null or not is_instance_valid(comp) or comp.stats.is_dead() or comp.oa_used_this_round:
			continue
		var cd_prev: int = maxi(absi(prev_pos.x - comp.grid_pos.x), absi(prev_pos.y - comp.grid_pos.y))
		var cd_next: int = maxi(absi(next_pos.x - comp.grid_pos.x), absi(next_pos.y - comp.grid_pos.y))
		if cd_prev <= 1 and cd_next > 1:
			comp.oa_used_this_round = true
			comp._attack_enemy(self)
			if not is_instance_valid(self) or stats.is_dead():
				return

# Returns movement direction candidates in priority order (diagonal first, then axes).
func _preferred_steps(dx: int, dy: int) -> Array[Vector2i]:
	var sx: int = sign(dx)
	var sy: int = sign(dy)
	var steps: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		steps.append(Vector2i(sx, sy))
	if abs(dx) >= abs(dy):
		if sx != 0: steps.append(Vector2i(sx, 0))
		if sy != 0: steps.append(Vector2i(0, sy))
	else:
		if sy != 0: steps.append(Vector2i(0, sy))
		if sx != 0: steps.append(Vector2i(sx, 0))
	return steps

func _bfs_to(target: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [grid_pos]
	var came: Dictionary = {grid_pos: grid_pos}
	var limit: int = 0
	while not queue.is_empty() and limit < 200:
		limit += 1
		var cur: Vector2i = queue.pop_front()
		if cur == target:
			var path: Array[Vector2i] = []
			while cur != grid_pos:
				path.push_front(cur)
				cur = came[cur]
			return path
		for d: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var nxt: Vector2i = cur + d
			if not came.has(nxt) and (_dungeon_floor.is_walkable_for_enemy(nxt) or nxt == target):
				came[nxt] = cur
				queue.append(nxt)
	return []

# Shared d20-vs-AC roll used by every enemy attack (melee, ranged, vs-player, vs-companion) — see
# docs/architecture/enemy_system_architecture.md §2. Only computes the roll; callers apply damage/log.
# roll_penalty: flat subtracted from the roll AFTER advantage/disadvantage resolves, before the
# AC comparison — Blade Ward's -1d4 (player-only, passed by _attack_player()). Never affects the
# crit check (a nat 20 still auto-hits regardless of penalty).
# §4: with "mods" present, the attack roll uses ability modifier + proficiency (stat from
# attack_profile's "attack_stat", default STR melee / DEX ranged) INSTEAD OF the legacy
# floor-scaling bonus — never both, same opt-in-per-entry rule as resist_check_detailed().
# TODO(future refactor): "attack_stat" is authored by hand per enemy (e.g. goblin_minion's Dagger
# sets it to "dex" for finesse) because enemy weapons are plain dmg_min/dmg_max/damage_type dicts,
# not a real weapon object with an is_finesse flag the way Item is for the player. If enemy
# multiattack/abilities entries ever grow a proper weapon shape, attack_stat should be DERIVED
# from that (finesse -> max(STR,DEX), else STR melee/DEX ranged) instead of authored — flagged
# here, not attempted yet, since it's a schema change across ENEMY_POOL/BOSS_POOL, not a one-liner.
func _attack_bonus() -> int:
	if _mods.is_empty():
		return GameState.current_floor / 3
	var profile: Dictionary = _type.get("attack_profile", {})
	var stat_key: String = profile.get("attack_stat", "dex" if profile.get("kind", "melee") == "ranged" else "str")
	return int(_mods.get(stat_key, 0)) + (_prof_bonus if _attack_prof else 0)

# Per-sub-attack stat override: a multiattack/ability/thrown_weapon/unarmed_fallback sub dict may
# carry its own "attack_stat" (e.g. Goblin Minion's Fists use STR while its Dagger uses DEX) —
# overrides attack_profile's enemy-wide default for just this one swing. Falls back to the normal
# _attack_bonus() when the sub doesn't specify one (every pre-existing multiattack/ability entry).
func _attack_bonus_for(sub: Dictionary) -> int:
	if not sub.has("attack_stat") or _mods.is_empty():
		return _attack_bonus()
	return int(_mods.get(String(sub["attack_stat"]), 0)) + (_prof_bonus if _attack_prof else 0)

func _resolve_attack_roll(target_ac: int, attack_bonus_override: int = -9999, roll_penalty: int = 0, extra_adv: bool = false, extra_disadv: bool = false) -> Dictionary:
	# D&D attack roll: d20 + floor-scaled (or mods+prof, see _attack_bonus()) bonus vs target AC.
	# extra_adv/extra_disadv: Fog Cloud (Blinded) — extra_adv when the TARGET is standing in the
	# cloud (attacks against a Blinded creature have Advantage), extra_disadv when THIS enemy (the
	# attacker) is standing in it instead (its own attacks have Disadvantage).
	var attack_bonus: int = attack_bonus_override if attack_bonus_override > -9999 else _attack_bonus()
	var die1: int = Rng.roll(20)
	var die2: int = die1
	var die: int = die1
	var enemy_adv: bool = extra_adv
	var enemy_disadv: bool = disadv_next_attack or extra_disadv
	disadv_next_attack = false  # World Tree Grip of the Forest R3 — consumed after one attack
	if enemy_adv != enemy_disadv:
		die2 = Rng.roll(20)
		die = maxi(die1, die2) if enemy_adv else mini(die1, die2)
	var roll: int = die + attack_bonus - roll_penalty
	var bonus: int = attack_bonus
	var is_crit: bool = die == 20
	return {
		"die": die, "die1": die1, "die2": die2, "bonus": bonus, "roll": roll, "target_ac": target_ac,
		"is_crit": is_crit, "is_hit": is_crit or roll >= target_ac,
		"adv": enemy_adv and not enemy_disadv, "disadv": enemy_disadv and not enemy_adv,
		"roll_penalty": roll_penalty,
	}

# `sub`: optional multiattack/ability sub-attack dict ({name, dmg_min, dmg_max, damage_type}) —
# empty (default) = the top-level pool stats, today's unchanged single-attack behavior.
# `long_shot`: true when an "abilities" attack is firing beyond its "range" into "long_range" —
# see _ability_is_long_shot() — adds Disadvantage, same weapon-style normal/long split as the
# player's own ranged attacks (PlayerRanged.ranged_shot_disadvantage()).
func _attack_player(_player: Player, sub: Dictionary = {}, long_shot: bool = false) -> void:
	# Rage's duration refresh cares about being attacked at all, not just being hit — set
	# regardless of the roll's outcome (see player.gd._on_turn_started()'s rage tick).
	GameState.player_attacked_this_turn = true
	var invincible: bool = GameState.invincible
	var bracket_l: String = "[" if invincible else ""
	var bracket_r: String = "]" if invincible else ""
	var atk_label: String = display_name if sub.get("name", "") == "" else "%s's %s" % [display_name, sub["name"]]
	var dmg_type: String = sub.get("damage_type", "Bludgeoning")
	# Blade Ward cantrip: while active, subtract 1d4 from this attack roll before comparing to AC.
	var bw_penalty: int = Rng.roll(4) if GameState.player_stats.blade_ward_turns > 0 else 0
	var r: Dictionary = _resolve_attack_roll(GameState.player_stats.armor_class, _attack_bonus_for(sub), bw_penalty,
		GameState.is_in_fog_cloud(_player.grid_pos), long_shot or GameState.is_in_fog_cloud(grid_pos))
	var hit_meta: String = "ehit:die=%d,d1=%d,d2=%d,bonus=%d,total=%d,ac=%d,crit=%d,adv=%d,disadv=%d,bw=%d" % [
		r["die"], r["die1"], r["die2"], r["bonus"], r["roll"], r["target_ac"],
		1 if r["is_crit"] else 0, 1 if r["adv"] else 0, 1 if r["disadv"] else 0, r["roll_penalty"]]
	if not r["is_hit"]:
		var miss_suffix: String = " [color=gray](d20%+d=%d vs AC %d)[/color]" % [r["bonus"], r["roll"], r["target_ac"]] if GameState.god_mode else ""
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s]misses[/url]!%s%s" % [bracket_l, atk_label, hit_meta, miss_suffix, bracket_r])
		return
	var is_crit: bool = r["is_crit"]
	var min_d: int = int(sub.get("dmg_min", stats.min_damage))
	var max_d: int = int(sub.get("dmg_max", stats.max_damage))
	# "advantage_bonus" trait (Goblin Warrior/Archer): an extra die on top of the normal roll
	# whenever this attack landed with net Advantage — folded into the crit doubling below, same
	# as any other damage die (matches how a weapon's own dice would double on a crit).
	var adv_bonus_sides: int = _advantage_bonus_sides()
	var adv_bonus_roll: int = Rng.roll(adv_bonus_sides) if (adv_bonus_sides > 0 and r["adv"]) else 0
	var dmg_roll: int = Rng.range_i(min_d, maxi(min_d, max_d)) + adv_bonus_roll
	var dmg: int = dmg_roll * (2 if is_crit else 1)
	if is_crit:
		AudioManager.play("crit")
	else:
		AudioManager.play("player_hurt")
	# Route through take_damage_raw for rage DR. take_damage_raw handles player_hp_changed and
	# check_player_death internally, and (while invincible) still registers "player was hit this
	# turn" without changing HP — see its own invincible branch — so god-mode play doesn't break
	# turn-based triggers keyed off that flag.
	var actual: int = GameState.take_damage_raw(dmg, false, dmg_type)
	if _dungeon_floor != null and not invincible:
		_dungeon_floor.show_damage(_player.position, actual, true)
	# Rage's 50% DR (take_damage_raw()) was live for this hit whenever the player was raging AND
	# dmg_type is one of the three physical types.
	var rage_applied: int = 1 if GameState.is_raging else 0
	var dmg_meta: String = "edmg:roll=%d,min=%d,max=%d,crit=%d,rage=%d,final=%d,advb=%d" % [dmg_roll, min_d, max_d, 1 if is_crit else 0, rage_applied, actual, adv_bonus_roll]
	var god_suffix: String = " [color=gray](d20%+d=%d vs AC %d)[/color]" % [r["bonus"], r["roll"], r["target_ac"]] if GameState.god_mode else ""
	# Second typed damage component on the SAME hit (Imp's Sting — Piercing weapon dmg + Poison
	# venom, one attack roll, two independent damage instances/floaters/log segments) — pool
	# "multiattack" sub-entry's optional "extra" key. Mirrors the player-side Judgement Day/
	# Fireball-friendly-fire "one hit, multiple damage types" convention.
	var extra_suffix: String = ""
	if sub.has("extra"):
		var extra: Dictionary = sub["extra"]
		var extra_type: String = extra.get("damage_type", "Poison")
		var e_min: int = int(extra.get("dmg_min", 0))
		var e_max: int = int(extra.get("dmg_max", 0))
		var e_roll: int = Rng.range_i(e_min, maxi(e_min, e_max))
		var e_dmg: int = e_roll * (2 if is_crit else 1)
		var e_actual: int = GameState.take_damage_raw(e_dmg, false, extra_type)
		if _dungeon_floor != null and not invincible:
			_dungeon_floor.show_damage(_player.position, e_actual, true, CombatMath.damage_type_color(extra_type), 1)
		var extra_meta: String = "edmg:roll=%d,min=%d,max=%d,crit=%d,rage=0,final=%d,advb=0" % [e_roll, e_min, e_max, 1 if is_crit else 0, e_actual]
		extra_suffix = " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [extra_meta, e_actual, extra_type]
	if is_crit:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s][color=red]CRITICAL HIT![/color][/url] for [url=%s][color=yellow]%d[/color][/url] dmg%s.%s%s" % [bracket_l, atk_label, hit_meta, dmg_meta, actual, extra_suffix, god_suffix, bracket_r])
	else:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s]hits[/url] you for [url=%s][color=yellow]%d[/color][/url] dmg%s.%s%s" % [bracket_l, atk_label, hit_meta, dmg_meta, actual, extra_suffix, god_suffix, bracket_r])
	# Orc Shaman applies poison on hit (top-level attack only — never a multiattack/ability sub-swing).
	if sub.is_empty() and not invincible and display_name == "Orc Shaman" and GameState.player_stats.poison_turns < 3:
		if GameState.apply_player_status("poison", 3):
			GameState.game_log("[color=lime]You are poisoned! (3 turns)[/color]")

# Companion (Wild Heart summon) as attack target — see docs/architecture/enemy_system_architecture.md §5.
# No invincible/poison/Retaliation hooks: those are player-only systems. Companion.take_damage_from_enemy()
# already logs the hit/HP line and handles death, so only the miss line needs logging here.
func _attack_companion(companion: Companion, sub: Dictionary = {}, long_shot: bool = false) -> void:
	var atk_label: String = display_name if sub.get("name", "") == "" else "%s's %s" % [display_name, sub["name"]]
	var r: Dictionary = _resolve_attack_roll(companion.stats.armor_class, _attack_bonus_for(sub), 0,
		GameState.is_in_fog_cloud(companion.grid_pos), long_shot or GameState.is_in_fog_cloud(grid_pos))
	if not r["is_hit"]:
		GameState.game_log("[color=tomato]%s[/color] attacks %s and misses!" % [atk_label, companion.animal_name])
		return
	var min_d: int = int(sub.get("dmg_min", stats.min_damage))
	var max_d: int = int(sub.get("dmg_max", stats.max_damage))
	# "advantage_bonus" trait — see the matching comment in _attack_player() above.
	var adv_bonus_sides: int = _advantage_bonus_sides()
	var adv_bonus_roll: int = Rng.roll(adv_bonus_sides) if (adv_bonus_sides > 0 and r["adv"]) else 0
	var dmg_roll: int = Rng.range_i(min_d, maxi(min_d, max_d)) + adv_bonus_roll
	var dmg: int = dmg_roll * (2 if r["is_crit"] else 1)
	# Second typed damage component on the same hit (e.g. Imp's Sting) — Companion has no per-type
	# resist/tooltip system at all (pre-existing simplification), so this just folds straight into
	# the one flat damage number rather than getting its own instance/floater.
	if sub.has("extra"):
		var extra: Dictionary = sub["extra"]
		var e_min: int = int(extra.get("dmg_min", 0))
		var e_max: int = int(extra.get("dmg_max", 0))
		var e_roll: int = Rng.range_i(e_min, maxi(e_min, e_max))
		dmg += e_roll * (2 if r["is_crit"] else 1)
	if r["is_crit"]:
		AudioManager.play("crit")
	else:
		AudioManager.play("player_hurt")
	companion.take_damage_from_enemy(dmg)
