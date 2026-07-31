class_name Enemy
extends Entity

enum Behavior { SLEEPING, STATIONARY, ROAMING, CHASING, SEARCHING }

const SPRITES_PATH := "res://sprites/characters/enemies/"
const FOV_RADIUS: int = 5
const SCARE_FRIGHTENED_TURNS: int = 10  # Quasit's Scare — 5e's "1 minute" duration cap, expressed as ~10 real turns (repeated WIS saves usually end it well before this — see Player._on_turn_started())

# sprites/characters/enemies/ is organized one subfolder per in-game enemy/boss identity (see
# root CLAUDE.md's "Sprite Assets" section) — a pool "sprite" key (a stable id, not a
# filename fragment) maps to its containing folder here. Filenames inside each folder are just
# "idle_1.png".."idle_4.png"/"run_1.png".."run_4.png" (1-indexed) — no character prefix, since the
# folder itself already identifies the character. Absent = "sprite" key used verbatim as the
# folder name too (the common case for every key that already matches its folder name 1:1).
const SPRITE_FOLDER: Dictionary = {
	"big_demon": "BigDemon", "necromancer": "Necromancer", "goblin": "Goblin",
	"orc_warrior": "OrcWarrior", "orc_shaman": "OrcShaman", "masked_orc": "MaskedOrc",
	"skelet": "Skeleton", "tiny_zombie": "Zombie", "wogol": "Wogol", "imp": "Imp",
	"quasit": "Quasit", "pumpkin_dude": "PumpkinDude", "ogre": "Ogre", "rat": "Rat", "spider": "Spider",
}

var _dungeon_floor: Node
var display_name: String = "Enemy"
var exp_reward: int = 5
var _type: Dictionary = {}
var enemy_id: String = ""  # from pool "enemy_id"/"boss_id" key — stable id, unlike display_name (UI text)

var is_boss: bool = false
var initial_behavior: Behavior = Behavior.SLEEPING
var behavior: Behavior = Behavior.SLEEPING
var last_known_target_pos: Vector2i = Vector2i(-1, -1)

# Surprise-attack ADV (see "Stealth & Surprise Attacks" in scripts/entities/CLAUDE.md): set only
# when THIS enemy's own decision cycle is what re-establishes sight of an already-noticed target
# (a door-camping ambush, a mid-chase obstacle break, or Invisibility ending while still hunted —
# see _decide_action()'s CHASING/SEARCHING branches) — never by a player-triggered stealth-check
# notice, which stays purely behavior-gated (see PlayerVfx.has_advantage()). Lifetime = exactly one
# round (the round after it's set) — cleared by _execute_action()'s expiry guard if unconsumed, or
# consumed one-shot by PlayerVfx.has_advantage().
var surprise_available: bool = false
# Tracks whether this enemy could see its current target as of its own last decision — the false→
# true edge is what fires the regain-notice above. Set true unconditionally by _notice_target()/
# on_disturbed() so the round right after a fresh notice never double-fires a regain.
var _had_los_to_player: bool = false
var passive_perception: int = 10  # docs/architecture/stealth-and-surprise-attacks-design.md §3.2 — static DC (pool key "passive_perception", default 10 + WIS mod, derived in _apply_stats())
var oa_used_this_round: bool = false  # Opportunity Attack reaction cap — reset at the top of take_turn()
var slowed_turns: int = 0
var rooted_turns: int = 0        # World Tree Grip of the Forest R2 — skips movement, still attacks if adjacent
var disadv_next_attack: bool = false  # World Tree Grip of the Forest R3 — consumed on next attack roll
var prone: bool = false          # Maul's Topple mastery — real Prone condition (not turn-counted): auto-stands at the top of this enemy's own next turn, consuming one point of movement budget to do so (see decide_turn()). While it remains prone (i.e. on the PLAYER's turns before then), Player.gd's melee/ranged attack sites grant ADV/DISADV against it directly off this field.
var poisoned_condition_turns: int = 0  # true 5e Poisoned condition (DISADV on this enemy's own attack rolls/checks) — separate from any future enemy-side damage-over-time status, mirrors Stats.poisoned_condition_turns
var incapacitated_turns: int = 0       # "can't take actions" — skips this enemy's entire turn (decide_turn() below) and makes every player attack against it a Surprise Attack (PlayerVfx.has_advantage())
var faerie_fire_turns: int = 0   # Drow lineage spell Faerie Fire — a failed DEX save outlines the target in light: every attack roll against it gets Advantage (PlayerVfx.has_advantage()), ONLY if the attacker can actually see it (see PlayerVfx.has_advantage()'s own gate). Purely a to-hit modifier, no movement/attack restriction of its own — ticked once per real turn in decide_turn(). Also emanates a small light bubble (DungeonFloor.update_fog(), TORCH_BURN_LIGHT_RADIUS) and overrides Invisibility's own hidden-sprite behavior (see is_outlined_while_invisible() below).
var faerie_fire_color: Color = Color(0.4, 0.7, 1.0)  # the one random color (blue/green/violet) rolled once per cast in SpellEffects._resolve_faerie_fire() and shared by every creature outlined that same cast — drives _faerie_fire_indicator's tint below.
var shocked_no_oa: bool = false  # Shocking Grasp — blocks this enemy's next Opportunity Attack exposure, whenever it next happens
var mind_sliver_penalty_die: bool = false  # Mind Sliver cantrip — the next check this enemy makes (any resist_check_detailed() call) rolls with -1d4. Consumed on that next check; deliberately not turn-expiry-timed against "until the end of your next turn" per the spell text — enemy checks are rare enough that this one-shot-consumed simplification is documented here rather than adding a second timing system for it.
var frightened_turns: int = 0    # Aasimar Necrotic Shroud (Celestial Revelation) — a failed CHA check frightens this enemy. Simplified vs. the real player-side Frightened (scripts/entities/CLAUDE.md's "Conditions"): DISADV on this enemy's own attack rolls only, no can't-approach-the-source movement block (no enemy-side "source" tracking exists) — ticked once per real turn in decide_turn(), same shape as faerie_fire_turns/enfeeble_turns.
var enfeeble_turns: int = 0      # Chthonic Tiefling lineage spell Ray of Enfeeblement — this enemy's own weapon (physical: Slashing/Piercing/Bludgeoning) damage is halved while active. Purely a damage modifier, no movement/attack restriction — ticked once per real turn in decide_turn(), same shape as faerie_fire_turns above. Simplified vs. RAW: no repeated CON save to end it early, fixed duration instead (same precedent as mind_sliver_penalty_die's own documented simplification).
var embedded_items: Array[Item] = []  # thrown weapons stuck in a non-lethal hit (PlayerThrowTool._throw_weapon) — dropped at 100% chance wherever/whenever this enemy eventually dies, see die() override below
var escape_turns: int = 0    # Nimble Escape trait (Goblin) — random 1-5 turns fleeing escape_from, set in on_melee_hit()
var escape_from: Node = null  # entity being fled from; always is_instance_valid()-checked before use (may die/despawn mid-flee)
var _hits_taken: int = 0     # incremented in take_typed_damage() on every instance of actual > 0 damage — lets on_melee_hit() below tell whether THIS melee hit is this enemy's first damage ever this life
var _thrown_weapon_used: bool = false        # a one-shot thrown weapon (pool "thrown_weapon") — true once used; _attack_target() then dispatches to "unarmed_fallback" (a bare-handed Fist strike) instead of the normal multiattack — Goblin Minion's Dagger and Orc Warrior's Javelin both work this way
var _thrown_weapon_lodged_target: Node = null  # who the thrown weapon was aimed at, for the delayed drop-on-death check in die()
var _thrown_weapon_lodged_item: Item = null    # the actual Item to place on the floor if the drop chance succeeds
var _thrown_weapon_lodged_chance: float = 0.5  # per-enemy drop chance (pool "thrown_weapon"'s "drop_chance", default 0.5 matches Goblin Minion's original hardcoded rate)
var _invis_turns: int = 0                # Invisibility ability (Imp) — turns remaining; hides sprite (visible=false) + skipped by DungeonFloor.get_targetable_enemy_at()
var _invis_cooldown_remaining: int = 0   # turns until Invisibility can be cast again (pool "invisibility" -> "cooldown")
var _web_cooldown_remaining: int = 0     # turns until Web can be cast again (Spider, pool "web" -> "cooldown")
var _scare_used: bool = false            # Quasit's Scare — real stat block is "1/Day"; enemies never rest, so this is a one-shot per-life flag (same "N/day = N/life" precedent as legendary_resistances_remaining)
const SHAPE_SHIFT_FORMS: PackedStringArray = ["rat", "raven", "spider"]  # default form list for the "shape_shift" trait — Imp's own set. An entry can override with its own pool "shape_shift_forms" array (Quasit: bat/centipede/toad) via _shape_shift_forms() below.
var _shifted_form: String = ""  # Shape Shift trait (Imp/Quasit) — "" = true form; else one of this enemy's shape_shift_forms(). Reverts on any damage taken (take_typed_damage()), swaps the visible sprite via _refresh_shape_shift_visual().
# Visual sprite config for shape-shifted forms (SHAPE_SHIFT_FORMS keys missing here — currently
# just "raven", no art yet — fall back to leaving whatever sprite is already showing untouched,
# i.e. the true Imp form stays visible; asset debt only, not a missing feature). "variants" empty
# = single fixed look (Spider); non-empty = a Rat-style random cosmetic recolor, same convention as
# Giant Rat's own "sprite_variants" pool key (picked with plain randi(), not Rng — cosmetic only).
const SHAPE_SHIFT_SPRITES: Dictionary = {
	"rat":    {"folder": "Rat", "variants": ["Gray", "Brown", "White"], "idle_frames": 6, "run_frames": 6,
			   "frame_size": {"w": 64, "h": 64}, "scale": 0.35},
	"spider": {"folder": "Spider", "variants": [], "idle_frames": 6, "run_frames": 6,
			   "frame_size": {"w": 32, "h": 32}, "scale": 0.5},
}

# ── D&D stat-block schema (docs/architecture/enemy-stat-block-design.md) ──────────────────────
var cr: float = 0.25                             # authored challenge rating, pool key "cr"
var creature_type: String = "Humanoid"           # pool key "creature_type", flavor/tag only (§7)
var damage_resistances: Array[String] = []       # ×0.5 — pool "damage_resistances" (fallback: legacy "resist")
var damage_immunities: Array[String] = []        # ×0   — pool "damage_immunities"
var damage_vulnerabilities: Array[String] = []   # ×2.0 — pool "damage_vulnerabilities" (fallback: legacy "vuln")
var condition_immunities: Array[String] = []     # blocks the STATUS COUNTER from ever being set (§6) —
												  # separate axis from damage immunity above. Vocabulary:
												  # "slowed"/"rooted"/"prone"/"forced_move"/
												  # "poisoned_condition"/"incapacitated" (enemy-side
												  # control fields, see apply_status() below) and
												  # "poisoned"/"burning"/"bleeding" (Stats counters,
												  # reserved — nothing ticks them on enemies yet).
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

var just_noticed: bool = false  # set the instant an unaware enemy detects the player (stealth-check notice — including at true adjacency, now just a very-high-DC roll rather than an auto-notice — or, vs the Companion only, the true-adjacency backstop) — consumed by the very next _decide_action(), which skips movement/attack that round (shows _notice_label instead) so a freshly-noticed enemy can't also act the same round it noticed. NOT set on the "wake-on-attacked" path (on_disturbed's default via_attack), which still wakes+acts immediately, unchanged.
var _notice_label: Label

var _mark_indicator: Label  # Ranger's Hunter's Mark — small red arrow shown above the currently-marked enemy
var _mark_tween: Tween
var _mark_base_y: float = -34.0

var _faerie_fire_indicator: Label  # Faerie Fire — small sparkle shown above an outlined enemy, tinted faerie_fire_color

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
	_setup_mark_indicator()
	_setup_faerie_fire_indicator()
	behavior = initial_behavior
	if behavior == Behavior.SLEEPING:
		_start_zzz()
	# Shape Shift (Imp/Quasit): 50% chance to already be shape-shifted into a random form at spawn.
	if _has_trait("shape_shift") and Rng.chance(0.5):
		var forms: Array = _shape_shift_forms()
		_shifted_form = String(forms[Rng.range_i(0, forms.size() - 1)])
		_refresh_shape_shift_visual()

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

	# Multi-tile footprint (pool "size": {"w","h"}, e.g. Ogre's Large 2x2) — Entity.size, default
	# ONE. grid_pos stays the top-left corner (Entity.occupied_tiles()/occupies()/min_dist_to()/
	# nearest_occupied_tile() derive everything else from it) — see "Enemy D&D stat-block schema".
	var size_data: Dictionary = _type.get("size", {})
	size = Vector2i(int(size_data.get("w", 1)), int(size_data.get("h", 1)))

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
			var save: Dictionary = resist_check_detailed(dc, true)
			var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
				save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
			if save["pass"]:
				_undead_fortitude_used = true
				effective = stats.current_hp - 1
				GameState.game_log("[color=gray]%s's [url=%s]Undead Fortitude[/url] keeps it standing![/color]" % [display_name, save_meta])
			elif GameState.debug_show_all_checks:
				GameState.game_log("[color=gray][url=%s]%s's Undead Fortitude check fails.[/url][/color]" % [save_meta, display_name])
			break
	var actual: int = stats.take_damage(effective)
	if actual > 0:
		_hits_taken += 1
	# Shape Shift (Imp): any actual damage taken (an immune hit deals 0 and returned earlier above,
	# so this never fires from those) reverts a shape-shifted enemy to its true form immediately.
	if actual > 0 and _shifted_form != "":
		_shifted_form = ""
		_refresh_shape_shift_visual()
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
		"prone":    prone = true  # not turn-counted — see the `prone` field's own comment
		"poisoned": stats.poison_turns  = maxi(stats.poison_turns, turns)
		"burning":  stats.burning_turns = maxi(stats.burning_turns, turns)
		"bleeding": stats.bleeding_turns = maxi(stats.bleeding_turns, turns)
		"poisoned_condition": poisoned_condition_turns = maxi(poisoned_condition_turns, turns)
		"incapacitated": incapacitated_turns = maxi(incapacitated_turns, turns)
		"frightened": frightened_turns = maxi(frightened_turns, turns)
	return true

# Nimble Escape (Goblin trait): after taking damage from a MELEE attack, the enemy's next action(s)
# become fleeing the attacker for a random 1-5 turns instead of acting normally — see the
# escape_turns branch in _decide_action() and _flee_from() below. Wired only into the melee-only
# player attack call sites (_bump_attack/_resolve_cleave_attack/_resolve_offhand_attack/
# resolve_opportunity_attack in player.gd) — NOT ranged/thrown/spell hits, which aren't "a melee
# attack" by the trait's own text.
# ONLY triggers on this enemy's very first damage instance this life (_hits_taken == 1, already
# incremented by the take_typed_damage() call this same hit made just before on_melee_hit() is
# called) — direct owner request: if the goblin was already damaged before this melee swing (shot
# by a ranged weapon, say), fleeing melee range is pointless since the player can just shoot it
# while it runs, so a melee hit landed on an already-damaged goblin no longer triggers a flee.
# Also fires an immediate one-tile "flinch" hop directly away from the attacker, right here in
# reaction to the hit that provoked it (still within the attacker's own turn, before TurnManager
# ever hands control to this enemy) — otherwise the goblin would stand still eating a follow-up
# swing on the very turn its escape starts, letting the player just walk in lockstep with it for
# the whole flee and get a free stab at the end regardless. Reuses _flee_from() as-is: same
# no-OA-provoked step, and if it's cornered (wall/blocked tile behind it) _flee_from() simply
# returns false without moving — no special-casing needed, the goblin just stays put this beat and
# starts its normal (possibly cornered-fight) flee behavior on its own turn as usual.
func on_melee_hit(attacker: Node) -> void:
	if stats.is_dead() or not _has_trait("nimble_escape") or _hits_taken > 1:
		return
	escape_turns = Rng.range_i(1, 5)
	escape_from = attacker
	await _flee_from(attacker)

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
	return _invis_turns > 0 and faerie_fire_turns <= 0

# Faerie Fire "can't be invisible" clause: an outlined creature that's ALSO invisible is forced
# visible (rendered translucent) rather than hidden — see DungeonFloor._update_enemy_visibility().
func is_outlined_while_invisible() -> bool:
	return _invis_turns > 0 and faerie_fire_turns > 0

# Web ability cooldown (Spider, pool "web"): ticks down every real turn regardless of whether
# Web is currently ready — same one-line shape as _invis_cooldown_remaining above.
func _tick_web_cooldown() -> void:
	if _web_cooldown_remaining > 0:
		_web_cooldown_remaining -= 1

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
		var forms: Array = _shape_shift_forms()
		_shifted_form = String(forms[Rng.range_i(0, forms.size() - 1)])
		_refresh_shape_shift_visual()

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
		# Shape Shift: while shifted, speed comes from pool "shape_shift_speed" if authored,
		# else falls back to Imp's original hardcoded mundane-critter speed. Imp's three animal
		# forms are all slower than its own true-form flight (none of them can fly) — Quasit's own
		# forms (bat/centipede/toad) instead keep its normal 4/3 speed via an explicit override,
		# since none of them are meant to be slower than its true form.
		sp = _type.get("shape_shift_speed", {"moves": 2, "per": 3})
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

# Which random-form list the "shape_shift" trait picks from — an entry's own pool
# "shape_shift_forms" array (Quasit: bat/centipede/toad) if authored, else the shared
# SHAPE_SHIFT_FORMS default (Imp: rat/raven/spider). Returning a plain Array (not
# PackedStringArray) since pool data is untyped GDScript literals.
func _shape_shift_forms() -> Array:
	var forms: Array = _type.get("shape_shift_forms", [])
	return forms if not forms.is_empty() else Array(SHAPE_SHIFT_FORMS)

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
	if _dungeon_floor == null or not _dungeon_floor.has_clear_shot(grid_pos, target.grid_pos):
		return {}
	var blinded: bool = GameState.is_blinded(grid_pos)
	for ab: Dictionary in abilities:
		var id: String = ab.get("id", "")
		# Blinded: same 1-tile reach collapse as the ranged attack_profile branch above.
		var max_reach: int = 1 if blinded else int(ab.get("long_range", ab.get("range", 5)))
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
# Priority when multiple use_* flags are somehow true: DEX > WIS > INT > CHA > CON > STR (arbitrary
# — every real call site only ever sets one).
# `magical`: true when this check is a saving throw against a SPELL (Ray of Frost, Toll the Dead,
# Mind Sliver, Thunderclap, Fireball) — NOT a weapon-mastery save (Push/Topple/Grip of the Forest/
# Branching Strike), which aren't spells and never pass this. Combined with the "magic_resistance"
# trait (Imp), rolls the d20 with Advantage (max of two rolls) — Magic Resistance's real D&D text.
func resist_check_detailed(dc: int, use_con: bool = false, use_dex: bool = false, use_wis: bool = false, use_int: bool = false, magical: bool = false, use_cha: bool = false) -> Dictionary:
	var mod: int
	var stat_name: String
	var stat_key: String
	if use_dex:
		mod = stats.dex_modifier(); stat_name = "DEX"; stat_key = "dex"
	elif use_wis:
		mod = stats.wis_modifier(); stat_name = "WIS"; stat_key = "wis"
	elif use_int:
		mod = stats.int_modifier(); stat_name = "INT"; stat_key = "int"
	elif use_cha:
		mod = stats.cha_modifier(); stat_name = "CHA"; stat_key = "cha"
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
	# Opener-mode thrown weapon (Orc Warrior's/Ogre's Javelin — "thrown_weapon" present, NOT
	# flee_only) that never actually left this enemy's hand: killed before it got an opening to
	# throw, or the target was already adjacent the very first time it could act (so the opener's
	# own "target 2+ tiles away" condition never fired and it went straight to melee instead).
	# Either way the Javelin is still physically on the corpse, so it drops here guaranteed (no
	# drop_chance roll, no next-turn delay — unlike the lodged-in-target recovery above) — but
	# with only 2 of its drop_uses_max uses, not a fresh full stack, since this copy still saw
	# some prior wear same as any other dropped weapon. Goblin Minion's flee_only Dagger is
	# deliberately excluded — that one only ever throws as a one-time parting shot, not an opener,
	# and already drops via the lodged-weapon path above when it does.
	if not _thrown_weapon_used and _dungeon_floor != null:
		var opener_wpn: Dictionary = _type.get("thrown_weapon", {})
		if not opener_wpn.is_empty() and not bool(opener_wpn.get("flee_only", false)):
			var unused_item: Item = _build_thrown_weapon_item(opener_wpn)
			unused_item.uses_remaining = mini(2, unused_item.uses_max)
			_dungeon_floor.place_item_on_floor(grid_pos, unused_item)
	# Bloodhound R3: if this was the Hunter's Mark target, re-mark the nearest visible enemy for free.
	if _dungeon_floor != null and _dungeon_floor._player != null:
		_dungeon_floor._player._ranger_talents.try_bloodhound_remark(self)
	# Frightened: if this enemy was the fear source, the condition would otherwise sit inert
	# (DISADV/can't-approach both already no-op once the source is invalid) until its own timer
	# or repeat-save clears it — cleared immediately instead, for a status tray that doesn't keep
	# showing "Frightened" of something already dead.
	if GameState.player_stats.frightened_source == self:
		GameState.clear_player_frightened()
	super.die()

func _setup_animations() -> void:
	var variants: Array = _type.get("sprite_variants", [])
	if not variants.is_empty():
		_setup_sheet_animations(variants)
		return
	# A sheet-sliced enemy with no cosmetic color variant at all (Spider — one fixed idle.png/
	# run.png sheet, no Rat-style Gray/Brown/White subfolder) still needs the sheet-slicing path,
	# just without a variant subfolder — same "sprite_frame_size present" signal + empty-variants
	# branch _refresh_shape_shift_visual() already uses for this exact art asset (Imp's Shape Shift
	# reuses the same Spider sheet cosmetically; this is the real Spider enemy's own setup).
	if _type.has("sprite_frame_size"):
		_setup_sheet_animations([])
		return
	var prefix: String = _type.get("sprite", "orc_warrior")
	var idle_n: int    = _type.get("idle_frames", 4)
	var run_n: int     = _type.get("run_frames", 4)
	var folder: String = SPRITE_FOLDER.get(prefix, prefix)
	var folder_path: String = SPRITES_PATH + folder + "/"
	var idle_fmt: String = _type.get("idle_fmt", folder_path + "idle_%d.png")
	var run_fmt: String  = _type.get("run_fmt",  folder_path + "run_%d.png")
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", idle_fmt, idle_n, true,  8.0)
	_add_anim(frames, "run",  run_fmt,  run_n, false, 16.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -8)
	$AnimatedSprite2D.play("idle")

# Filenames are 1-indexed (idle_1.png, idle_2.png, ...), not 0-indexed.
func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i: int in count:
		frames.add_frame(anim_name, load(path_fmt % (i + 1)))

# Cosmetic random-variant sprite sheets (Giant Rat's Gray/Brown/White recolors) — one PNG per
# animation state holding all frames side-by-side, instead of Wogol-style one-file-per-frame.
# Which variant renders never affects gameplay, so it's picked with plain global randi(), NOT
# Rng — per scripts/autoloads/CLAUDE.md's "cosmetic jitter stays global" rule; drawing from the
# seeded Rng/_pop_rng streams here would perturb every other system that depends on them for
# reproducible runs.
func _setup_sheet_animations(variants: Array) -> void:
	var prefix: String = _type.get("sprite", "rat")
	var folder: String = SPRITE_FOLDER.get(prefix, prefix)
	var sheet_path_fmt: String
	if variants.is_empty():
		sheet_path_fmt = "%s%s/%%s.png" % [SPRITES_PATH, folder]
	else:
		var variant: String = String(variants[randi() % variants.size()])
		sheet_path_fmt = "%s%s/%s/%%s.png" % [SPRITES_PATH, folder, variant.to_lower()]
	var frame_size: Dictionary = _type.get("sprite_frame_size", {})
	var fw: int = int(frame_size.get("w", 64))
	var fh: int = int(frame_size.get("h", 64))
	var idle_n: int = _type.get("idle_frames", 6)
	var run_n: int  = _type.get("run_frames", 6)
	var frames := SpriteFrames.new()
	_add_anim_sheet(frames, "idle", sheet_path_fmt % "idle", idle_n, fw, fh, true,  8.0)
	_add_anim_sheet(frames, "run",  sheet_path_fmt % "run",  run_n, fw, fh, false, 16.0)
	$AnimatedSprite2D.sprite_frames = frames
	var offset: Dictionary = _type.get("sprite_offset", {})
	$AnimatedSprite2D.offset = Vector2(float(offset.get("x", 0)), float(offset.get("y", -8)))
	$AnimatedSprite2D.scale = Vector2.ONE * float(_type.get("sprite_scale", 1.0))
	$AnimatedSprite2D.play("idle")

func _add_anim_sheet(frames: SpriteFrames, anim_name: String, sheet_path: String,
					  count: int, fw: int, fh: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	var tex: Texture2D = load(sheet_path)
	for i: int in count:
		var atlas := AtlasTexture.new()
		atlas.atlas = tex
		atlas.region = Rect2(i * fw, 0, fw, fh)
		frames.add_frame(anim_name, atlas)

# Shape Shift (Imp) visual swap — called whenever _shifted_form changes (spawn roll, mid-chase
# roll in _tick_shape_shift(), or reverting to true form on taking damage). Reverting rebuilds the
# true Imp sprite via the normal _setup_animations() path; shifting in swaps to the small-critter
# sheet described by SHAPE_SHIFT_SPRITES (a no-op, keeping whatever's currently shown, for a form
# with no entry — i.e. Raven today).
func _refresh_shape_shift_visual() -> void:
	if _shifted_form == "":
		_setup_animations()
		$AnimatedSprite2D.scale = Vector2.ONE  # undo any shifted-form scale (e.g. Spider's 0.5)
		return
	var cfg: Dictionary = SHAPE_SHIFT_SPRITES.get(_shifted_form, {})
	if cfg.is_empty():
		return
	var folder: String = String(cfg.get("folder", ""))
	var variants: Array = cfg.get("variants", [])
	var sheet_path_fmt: String
	if variants.is_empty():
		sheet_path_fmt = "%s%s/%%s.png" % [SPRITES_PATH, folder]
	else:
		var variant: String = String(variants[randi() % variants.size()])
		sheet_path_fmt = "%s%s/%s/%%s.png" % [SPRITES_PATH, folder, variant.to_lower()]
	var frame_size: Dictionary = cfg.get("frame_size", {})
	var fw: int = int(frame_size.get("w", 64))
	var fh: int = int(frame_size.get("h", 64))
	var frames := SpriteFrames.new()
	_add_anim_sheet(frames, "idle", sheet_path_fmt % "idle", int(cfg.get("idle_frames", 6)), fw, fh, true,  8.0)
	_add_anim_sheet(frames, "run",  sheet_path_fmt % "run",  int(cfg.get("run_frames", 6)),  fw, fh, false, 16.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -8)
	$AnimatedSprite2D.scale = Vector2.ONE * float(cfg.get("scale", 1.0))
	$AnimatedSprite2D.play("idle")

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

func _setup_mark_indicator() -> void:
	_mark_indicator = Label.new()
	_mark_indicator.text = "▼"
	_mark_indicator.add_theme_font_size_override("font_size", 16)
	_mark_indicator.add_theme_color_override("font_color", Color(0.9, 0.15, 0.15))
	_mark_indicator.position = Vector2(-4, _mark_base_y)
	_mark_indicator.z_index = 10
	_mark_indicator.visible = false
	add_child(_mark_indicator)

func _start_mark_bob() -> void:
	if not is_instance_valid(_mark_indicator):
		return
	_mark_indicator.visible = true
	if _mark_tween != null and _mark_tween.is_valid():
		_mark_tween.kill()
	_mark_indicator.position.y = _mark_base_y
	_mark_tween = create_tween().set_loops()
	_mark_tween.set_trans(Tween.TRANS_SINE).set_ease(Tween.EASE_IN_OUT)
	_mark_tween.tween_property(_mark_indicator, "position:y", _mark_base_y - 5.0, 0.35)
	_mark_tween.tween_property(_mark_indicator, "position:y", _mark_base_y, 0.35)

func _stop_mark_bob() -> void:
	if _mark_tween != null and _mark_tween.is_valid():
		_mark_tween.kill()
		_mark_tween = null
	if is_instance_valid(_mark_indicator):
		_mark_indicator.visible = false

func _setup_faerie_fire_indicator() -> void:
	_faerie_fire_indicator = Label.new()
	_faerie_fire_indicator.text = "✦"
	_faerie_fire_indicator.add_theme_font_size_override("font_size", 14)
	_faerie_fire_indicator.position = Vector2(6, -24)
	_faerie_fire_indicator.z_index = 10
	_faerie_fire_indicator.visible = false
	add_child(_faerie_fire_indicator)

# Called whenever faerie_fire_turns is set or ticked to 0 — updates the sparkle's visibility and
# tints it faerie_fire_color (the one random color rolled per cast, shared by every creature
# outlined that cast).
func _refresh_faerie_fire_visual() -> void:
	if not is_instance_valid(_faerie_fire_indicator):
		return
	_faerie_fire_indicator.visible = faerie_fire_turns > 0
	if faerie_fire_turns > 0:
		_faerie_fire_indicator.add_theme_color_override("font_color", faerie_fire_color)

func _process(_delta: float) -> void:
	if not is_instance_valid(_mark_indicator):
		return
	var should_show: bool = GameState.player_stats != null \
		and GameState.player_stats.hunters_mark_target == self \
		and not stats.is_dead()
	if should_show and not _mark_indicator.visible:
		_start_mark_bob()
	elif not should_show and _mark_indicator.visible:
		_stop_mark_bob()

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
	_had_los_to_player = true  # so the very next CHASING check doesn't immediately re-fire a regain
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
	_had_los_to_player = true  # being struck already implies awareness; avoid a spurious regain-fire
	if behavior in [Behavior.SLEEPING, Behavior.STATIONARY, Behavior.ROAMING]:
		_wake_up()
		last_known_target_pos = source_pos

# Public wrapper for the Stealth-vs-Passive-Perception check (player.gd) — reuses the exact same
# sight metric take_turn() uses internally, verbatim.
func can_see(target: Node) -> bool:
	return _can_see_entity(target)

# Public wrapper — player.gd's stealth check uses this enemy's own sight range (darkvision etc.)
# to scale its distance-to-DC bonus (see _resolve_stealth_check()'s "closer = harder to hide" rule).
func sight_range() -> int:
	return _sight_range()

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

# Both measured against the NEAREST tile of this enemy's own footprint, not always grid_pos —
# a no-op for every 1x1 enemy (occupied_tiles() == [grid_pos]), and what makes a Large enemy's
# attack range/sight/adjacency checks correct from whichever side of its 2x2 block is closest.
func _dist_sq_to(e: Node) -> int:
	var t: Vector2i = nearest_occupied_tile(e.grid_pos)
	var dx: int = e.grid_pos.x - t.x
	var dy: int = e.grid_pos.y - t.y
	return dx * dx + dy * dy

func _chebyshev_to(e: Node) -> int:
	# e may itself be a footprint larger than 1x1 (Large-Form Goliath player) — min_dist_to_entity()
	# checks every occupied tile on both sides, reducing to the plain min_dist_to(e.grid_pos) for
	# any 1x1 target (every other case today).
	if e is Entity:
		return min_dist_to_entity(e)
	return min_dist_to(e.grid_pos)

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
	# Web Walker (Spider trait "web_walker"): "knows the location of any creature in contact with
	# the same web" — a target currently Restrained by THIS spider's Web is never lost track of,
	# regardless of distance/LOS (mirrors the invisibility short-circuit above, just the opposite
	# direction: always-seen instead of never-seen).
	if _has_trait("web_walker") and e is Player and GameState.player_stats.web_restrained:
		return true
	var r: int = _sight_range()
	return _dist_sq_to(e) <= r * r and _dungeon_floor.has_line_of_sight(nearest_occupied_tile(e.grid_pos), e.grid_pos)

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
	await execute_turn(decide_turn())

# Decision half of the round-simultaneity split (see TurnManager._process_enemies()): reads state
# and picks an intent WITHOUT performing any world-mutating side effect (no movement, no door
# opens, no attacks) — every enemy's decide_turn() runs back-to-back, against the exact same
# pre-round world state, before ANY enemy's execute_turn() runs. This is what stops e.g. a melee
# enemy opening a door from granting a ranged enemy behind it same-round LOS to shoot through —
# the ranged enemy's decision was already locked in while the door was still closed. Still mutates
# this enemy's OWN internal fields (behavior/FSM/search state, per-turn ticks) exactly as before —
# only cross-entity/world mutation is deferred to execute_turn().
func decide_turn() -> Dictionary:
	oa_used_this_round = false
	if _dungeon_floor == null:
		return {"type": "wait"}
	# Standing on a burning door tile — checked at the very top of THIS enemy's own turn (direct
	# owner request: fire damage lands "at the start of their own turn", not lumped into a single
	# global round tick — see DungeonFloor.tick_fire_damage_for()'s own doc comment). Can kill this
	# enemy outright; TurnManager._run_single_enemy() already guards on `not stats.is_dead()`
	# before calling execute_turn(), so bailing out here with a harmless "wait" intent is safe.
	_dungeon_floor.tick_fire_damage_for(self)
	if stats.is_dead():
		return {"type": "wait"}
	_tick_abilities()
	_tick_regeneration()
	_tick_speed_gate()
	_tick_invisibility()
	_tick_web_cooldown()
	_tick_shape_shift()
	if faerie_fire_turns > 0:
		faerie_fire_turns -= 1
		if faerie_fire_turns <= 0:
			_refresh_faerie_fire_visual()
	if enfeeble_turns > 0:
		enfeeble_turns -= 1
	if frightened_turns > 0:
		frightened_turns -= 1
	if poisoned_condition_turns > 0:
		poisoned_condition_turns -= 1
	# Incapacitated: "can't take actions" — skips this entire turn outright, same shape the OLD
	# Prone behavior used to have (see below). Checked before target selection since it doesn't
	# need one.
	if incapacitated_turns > 0:
		incapacitated_turns -= 1
		return {"type": "idle_tick"}
	# Prone (real 5e rules, not a turn-skip): auto-stands at the top of this enemy's own turn,
	# consuming one point of this turn's movement budget to do so (`_tick_speed_gate()` already
	# ran above) — matches the player's own "any direction key stands up instead of moving"
	# behavior. Does NOT return: once stood, this enemy is no longer prone and falls straight
	# through to the normal decision logic below with whatever movement budget remains (an
	# Aggressive-bonus-move enemy that was adjacent when knocked prone can still stand AND attack
	# the same turn — the exact "Orc Warrior gets up and still attacks" case). While it REMAINS
	# prone (i.e. on the player's own turns, before this code runs), Player.gd's melee/ranged
	# attack sites read `prone` directly for ADV/DISADV against it.
	if prone:
		prone = false
		_moves_this_turn = maxi(0, _moves_this_turn - 1)
	# Slowed (Mud/Water): unlike prone/rooted, this is deliberately NOT a full-turn skip — an
	# attack this turn is completely unaffected (per direct owner correction: "slow by nemělo mít
	# nic společného s útokem"). It only ever shaves ONE step off whatever movement this turn would
	# otherwise have — see the "slowed" param threaded into _act_toward()/_do_roam_walk() etc. below.
	# A plain 1-move-per-turn enemy therefore still effectively "takes 2 rounds to move 1 tile"
	# (1 - 1 = 0 this round), but a 2-move round (Aggressive's bonus step, or an above-baseline
	# "speed" entry) only loses one of its two steps, not both — and an off-cycle round for a
	# below-baseline "speed" entry (e.g. Zombie's 2/3) that already grants 0 movement credit is
	# untouched by this (nothing left to reduce), matching "no difference on a round it wasn't
	# going to move anyway".
	var _slowed_this_turn: bool = slowed_turns > 0
	if _slowed_this_turn:
		slowed_turns -= 1
	var _intent: Dictionary = _decide_action()
	_intent["slowed"] = _slowed_this_turn
	return _intent

# Execution half — all tweens/animation/movement/attack/door-open side effects, run per-enemy in
# TurnManager's existing sequential order (unchanged) once every enemy's decide_turn() has already
# run.
func execute_turn(intent: Dictionary) -> void:
	if intent.get("type", "wait") == "idle_tick":
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return
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
	# including attacking an adjacent target — a fleeing goblin doesn't stop to swing. A
	# "flee_only" thrown weapon (Goblin Minion's Dagger) is NOT thrown mid-flee — it's a parting
	# shot thrown the instant Nimble Escape WEARS OFF, only if the target still isn't adjacent
	# (close enough to just stab instead). See the "thrown_weapon" check further below for the
	# non-flee-only case (Orc Warrior's Javelin).
	if escape_turns > 0:
		escape_turns -= 1
		if escape_turns == 0:
			var flee_wpn: Dictionary = _type.get("thrown_weapon", {})
			if not flee_wpn.is_empty() and bool(flee_wpn.get("flee_only", false)) and not _thrown_weapon_used:
				var flee_target: Node = escape_from if is_instance_valid(escape_from) else target
				var throw_range_flee: int = int(flee_wpn.get("range", 4))
				var dist_flee: int = _chebyshev_to(flee_target)
				if dist_flee >= 2 and dist_flee <= throw_range_flee and _dungeon_floor.has_clear_shot(grid_pos, flee_target.grid_pos):
					return {"type": "throw_weapon", "target": flee_target, "weapon": flee_wpn}
			# Escape just wore off with no throw (adjacent, or out of throw range/LOS) — fall
			# through to the normal decision logic below (chase/attack) instead of fleeing again.
		else:
			return {"type": "flee", "target": escape_from if is_instance_valid(escape_from) else target}

	# One-shot thrown weapon (pool "thrown_weapon" — Orc Warrior's Javelin; Goblin Minion's Dagger
	# is "flee_only" and handled above instead): once not actively escaping (the check above
	# already guarantees escape_turns <= 0 here), if the target isn't adjacent, throw the weapon
	# at range instead of closing to melee. Doesn't need movement budget, so this is checked
	# before the rooted/frozen/speed-gate movement restrictions below — a rooted or speed-gated
	# enemy can still throw. Generic — keyed purely on the pool key's presence, not on enemy_id,
	# so any enemy can opt in by authoring the same two dict keys (see "thrown_weapon"/
	# "unarmed_fallback" in the Enemy D&D stat-block schema).
	# Gated on the enemy actually being aware of (actively pursuing) the target — an unaware
	# SLEEPING/STATIONARY/ROAMING enemy has no business throwing a weapon at someone it hasn't
	# noticed yet; `has_ranged_los()` (below) only checks line-of-sight, not awareness.
	var thrown_wpn: Dictionary = _type.get("thrown_weapon", {})
	if not thrown_wpn.is_empty() and not bool(thrown_wpn.get("flee_only", false)) and not _thrown_weapon_used \
			and behavior in [Behavior.CHASING, Behavior.SEARCHING] and not _target_is_untouchable(target):
		var throw_range: int = int(thrown_wpn.get("range", 4))
		var dist: int = _chebyshev_to(target)
		if dist >= 2 and dist <= throw_range and _dungeon_floor.has_clear_shot(grid_pos, target.grid_pos):
			return {"type": "throw_weapon", "target": target, "weapon": thrown_wpn}

	# Imp — Invisibility (pool "invisibility"): while pursuing (CHASING/SEARCHING) and not yet
	# adjacent, casts Invisibility on itself instead of closing distance, once the cooldown is
	# ready and it isn't already invisible. Costs the turn (a real action).
	var invis_cfg: Dictionary = _type.get("invisibility", {})
	if not invis_cfg.is_empty() and _invis_turns <= 0 and _invis_cooldown_remaining <= 0 \
			and behavior in [Behavior.CHASING, Behavior.SEARCHING] and _chebyshev_to(target) > 1:
		return {"type": "cast_invisibility", "config": invis_cfg}

	# Spider — Web (pool "web": {"cooldown","range","save_dc"}): a ranged, non-damage, SAVE-based
	# restraint ability, Player-only (the only entity with a Restrained/escape mechanic — see
	# Stats.web_restrained). Priority is identical to Invisibility above: while already aware of the
	# target (CHASING/SEARCHING — never on a fresh notice), not yet adjacent, off cooldown, and the
	# target isn't already stuck in an earlier web, cast it instead of closing distance the instant
	# it's in range AND nothing blocks the shot (has_clear_shot, matching every other ranged
	# ability's own obstruction check). "Already knows about the hero" per the owner's own framing —
	# a SLEEPING/STATIONARY/ROAMING spider that hasn't noticed anyone never webs blind.
	var web_cfg: Dictionary = _type.get("web", {})
	if not web_cfg.is_empty() and _web_cooldown_remaining <= 0 and target is Player \
			and not GameState.player_stats.web_restrained and not _target_is_untouchable(target) \
			and behavior in [Behavior.CHASING, Behavior.SEARCHING] and _chebyshev_to(target) > 1:
		var web_range: int = int(web_cfg.get("range", 6))
		if _chebyshev_to(target) <= web_range and _dungeon_floor.has_clear_shot(grid_pos, target.grid_pos):
			return {"type": "cast_web", "target": target, "config": web_cfg}

	# Quasit — Scare (pool "scare": {"range","save_dc"}): a ranged, non-damage, SAVE-based fear
	# effect, 1/life (the real stat block is "1/Day" — enemies don't rest, same "N/day = N/life"
	# precedent as Legendary Resistance, see legendary_resistances_remaining above). Same
	# priority/gating shape as Web above: only while already pursuing (CHASING/SEARCHING), not yet
	# adjacent, off its one-shot flag, in range, and nothing blocks the line.
	var scare_cfg: Dictionary = _type.get("scare", {})
	if not scare_cfg.is_empty() and not _scare_used and target is Player \
			and not _target_is_untouchable(target) \
			and behavior in [Behavior.CHASING, Behavior.SEARCHING] and _chebyshev_to(target) > 1:
		var scare_range: int = int(scare_cfg.get("range", 2))
		if _chebyshev_to(target) <= scare_range and _dungeon_floor.has_clear_shot(grid_pos, target.grid_pos):
			return {"type": "cast_scare", "target": target, "config": scare_cfg}

	# World Tree Grip of the Forest R2: rooted — no movement this turn, but can still attack if adjacent.
	if rooted_turns > 0:
		rooted_turns -= 1
		if _chebyshev_to(target) == 1 and not _target_is_untouchable(target):
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	# Movement-speed scaling (§ "Movement speed scaling"): a below-baseline "speed" pool entry
	# (e.g. Zombie) can roll a turn with zero movement credit — same shape as rooted_turns above,
	# still attacks if already adjacent.
	if _moves_this_turn <= 0:
		if _chebyshev_to(target) == 1 and not _target_is_untouchable(target):
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	var can_see: bool = _can_see_entity(target)
	var dx: int = target.grid_pos.x - grid_pos.x
	var dy: int = target.grid_pos.y - grid_pos.y

	match behavior:
		Behavior.SLEEPING:
			# vs the Player: no free adjacency auto-notice anymore — the Stealth-vs-Passive-
			# Perception check's distance-to-DC bonus (player.gd._resolve_stealth_check()) already
			# makes standing adjacent an extremely hard (not automatic) check to fail.
			# vs the Companion (no stealth-check equivalent exists for it): true-adjacency
			# backstop remains, same as before.
			if target is Player:
				return {"type": "wait"}
			if _chebyshev_to(target) <= 1:
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "wait"}

		Behavior.STATIONARY:
			# vs the Player: no free LOS-based notice, and no adjacency backstop either — same
			# reasoning as SLEEPING above, the stealth check's distance bonus already covers it.
			# vs the Companion (no stealth-check equivalent exists for it): unchanged can_see wake.
			if target is Player:
				return {"type": "wait"}
			if can_see:
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "wait"}

		Behavior.ROAMING:
			if target is Player:
				return {"type": "roam"}
			if can_see:
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				_notice_target(target.grid_pos)
				return {"type": "notice"}
			return {"type": "roam"}

		Behavior.CHASING:
			if can_see:
				# LOS-regain (SPD-style ring-around/door-ambush/invisibility-ending): this enemy's
				# OWN turn is what re-establishes sight after having lost it — grants one round of
				# surprise-attack eligibility on the player's very next attack. See "Stealth &
				# Surprise Attacks" in scripts/entities/CLAUDE.md for why this differs from a
				# player-triggered stealth-check notice (which never grants this).
				if not _had_los_to_player:
					_had_los_to_player = true
					surprise_available = true
					_notice_target(target.grid_pos)
					return {"type": "notice"}
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
			else:
				_had_los_to_player = false
			return _act_toward_or_ability(target, can_see, {"chasing": true})

		Behavior.SEARCHING:
			if can_see:
				if not _had_los_to_player:
					_had_los_to_player = true
					surprise_available = true
					behavior = Behavior.CHASING
					_notice_target(target.grid_pos)
					return {"type": "notice"}
				behavior = Behavior.CHASING
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
				return _act_toward_or_ability(target, can_see)
			_had_los_to_player = false
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
	# surprise_available expiry: snapshot BEFORE dispatch so a flag set THIS round (a regain-notice
	# just decided above, or door-ambush-equivalent) is never immediately wiped by the guard below —
	# only a flag that already survived a full round unconsumed gets cleared once this enemy takes a
	# real (non-"notice") action. See "Stealth & Surprise Attacks" in scripts/entities/CLAUDE.md.
	var had_surprise_before: bool = surprise_available
	match intent.get("type", "wait"):
		"notice":
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"attack":
			_attack_target(intent["target"])
		"flee":
			var fled: bool = await _flee_from(intent["target"], intent.get("slowed", false))
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
		"cast_web":
			_execute_cast_web(intent["target"], intent["config"])
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"cast_scare":
			_execute_cast_scare(intent["target"], intent["config"])
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"act_toward":
			# Aggressive (§ trait): while it can see its target, gets one extra movement step this
			# turn on top of whatever _moves_this_turn/speed already grants — Orc Warrior's trait.
			var bonus_moves: int = 1 if (intent.get("can_see", false) and _has_trait("aggressive")) else 0
			await _act_toward(intent["target"], bonus_moves, intent.get("slowed", false))
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
			await _do_roam_walk(intent.get("slowed", false))
		"search":
			if intent.get("slowed", false):
				# Same "shave one step off this round's movement" rule as act_toward/roam — a
				# search round only ever has 1 step of budget to begin with, so slowed just skips
				# this round's step outright (still awaits real time, doesn't burn the countdown).
				await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
			elif _search_turns_remaining > 0:
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
	if intent.get("type", "wait") != "notice" and had_surprise_before:
		surprise_available = false

# True if `target` is within this enemy's current attack_profile range (melee default = adjacent).
# An invisible player can't be attacked even while adjacent — an enemy that has no idea where
# it is standing shouldn't be able to swing at it (see "Invisibility" in scripts/entities/
# CLAUDE.md). Movement already can't land ON the player's tile (is_walkable_for_enemy() always
# blocks it), so this only ever matters for the "already adjacent" attack-without-moving case.
func _target_is_untouchable(target: Node) -> bool:
	return target is Player and GameState.player_stats.invisibility_turns > 0

func _in_attack_range(target: Node) -> bool:
	if _target_is_untouchable(target):
		return false
	var profile: Dictionary = _type.get("attack_profile", {})
	match profile.get("kind", "melee"):
		"ranged":
			# Blinded: this enemy's own ranged reach collapses to 1 tile — same rule as the
			# player's ranged/thrown/spell reach, see PlayerRanged.is_ranged_target_in_range().
			var rng: int = 1 if GameState.is_blinded(grid_pos) else profile.get("range", 4)
			return _chebyshev_to(target) <= rng and _dungeon_floor.has_clear_shot(nearest_occupied_tile(target.grid_pos), target.grid_pos)
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
	# Once a one-shot thrown weapon is used, every attack reverts to an unarmed Fist strike (pool
	# "unarmed_fallback") instead of the normal multiattack — but ONLY when the thrown weapon IS
	# the enemy's own melee weapon (Goblin Minion's Dagger: thrown away = no more Dagger for melee
	# either). An enemy whose thrown weapon is a SEPARATE item from its melee weapon (Orc Warrior:
	# Javelin thrown at range, Greataxe still in hand) keeps using its normal multiattack once
	# adjacent — throwing the Javelin away doesn't make the Greataxe disappear too. Distinguished by
	# comparing the thrown weapon's name against the multiattack's own weapon name; same name = same
	# weapon (Goblin), different name = a separate weapon (Orc) that was never lost.
	var fallback: Dictionary = _type.get("unarmed_fallback", {})
	var thrown: Dictionary = _type.get("thrown_weapon", {})
	var multi: Array = _type.get("multiattack", [])
	var is_same_weapon: bool = not multi.is_empty() and thrown.get("name", "") == multi[0].get("name", "")
	if _thrown_weapon_used and not fallback.is_empty() and is_same_weapon:
		if target is Player:
			_attack_player(target, fallback)
		elif target is Companion:
			_attack_companion(target, fallback)
		return
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
		_attack_player(target, ab, long_shot, true)
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
# Whether this enemy's WHOLE footprint fits at `top_left` (all size.x*size.y tiles walkable,
# excluding itself so its own current tiles never falsely block a move that vacates them) —
# a no-op wrapper around DungeonFloor.is_walkable_for_enemy() for a 1x1 enemy, so every existing
# non-Large call site behaves exactly as before.
func _footprint_walkable(top_left: Vector2i) -> bool:
	return _dungeon_floor.is_area_walkable_for_enemy(top_left, size, self)

# Each iteration either attacks (if already in range going into it) or spends one step of
# movement. A plain enemy (total_steps == 1) therefore either attacks OR moves, never both — the
# in-range check only re-fires on a LATER iteration, which only exists for an enemy with spare
# movement budget (Orc Warrior's "aggressive" trait, or an above-baseline "speed" pool entry).
# There is deliberately no post-loop attack check: an enemy that spends its entire budget closing
# distance and ends the turn adjacent does NOT also get a free attack that same turn.
# `slowed` (Mud/Water — see decide_turn()) shaves exactly ONE step off this turn's total MOVEMENT
# budget — never the attack check itself, which still fires on every iteration regardless (an
# already-adjacent enemy attacks immediately without spending any movement, slowed or not). A
# plain 1-step turn's movement budget drops to 0 (no movement this round if not already adjacent —
# same net "takes 2 rounds to move 1 tile" feel as before), while a 2-step turn (Aggressive's bonus
# step, or an above-baseline "speed" entry) only loses one of its two steps of movement, not the
# ability to close the last tile and swing. `move_budget` gates stepping only, never the
# `_in_attack_range()` check at the top of the loop — reducing `total_steps` itself instead would
# have silently skipped even the free "already adjacent, no movement needed" attack whenever slow
# reduced it to 0.
func _act_toward(target: Node, bonus_moves: int = 0, slowed: bool = false) -> void:
	var total_steps: int = maxi(1, _moves_this_turn) + bonus_moves
	var move_budget: int = total_steps - 1 if slowed else total_steps
	for _i: int in total_steps:
		if _in_attack_range(target):
			_attack_target(target)
			return
		if _i >= move_budget:
			# No movement budget left this round — still await real time (see entities/CLAUDE.md's
			# "every decide/execute path must await something real") rather than resolving instantly.
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
			return
		var moved: bool = await _act_toward_single_step(target)
		if not is_instance_valid(self) or stats.is_dead():
			return
		if not moved:
			return

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
		if _footprint_walkable(next_pos):
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
		if _footprint_walkable(next_pos):
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
		if _footprint_walkable(c):
			return c
	return Vector2i(-1, -1)

func _do_roam_walk(slowed: bool = false) -> void:
	if slowed:
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return
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
	if not _footprint_walkable(next_pos):
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
		if _footprint_walkable(target):
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
# Returns true if a step was actually taken (already awaited the move tween); false if stuck
# (or slowed — a slowed round has zero movement budget, same "shave the only step off" rule as
# roam/act_toward/search, which naturally falls into the cornered-fight fallback in
# _execute_action()'s "flee" case if the fleeing enemy is still in range of its attacker).
func _flee_from(from_entity: Node, slowed: bool = false) -> bool:
	if slowed:
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return false
	var from_pos: Vector2i = from_entity.grid_pos if is_instance_valid(from_entity) else grid_pos
	var dx: int = grid_pos.x - from_pos.x
	var dy: int = grid_pos.y - from_pos.y
	if dx == 0 and dy == 0:
		dx = 1
	for step: Vector2i in _preferred_steps(dx, dy):
		var next_pos: Vector2i = grid_pos + step
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _footprint_walkable(next_pos):
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
		_attack_player(target, sub, true, true)
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
	_invis_turns = int(cfg.get("duration", 600))
	_invis_cooldown_remaining = int(cfg.get("cooldown", 5))
	visible = false
	GameState.game_log("[color=purple]%s fades from view.[/color]" % display_name)

# Spider's Web ability (pool "web": {"cooldown","range","save_dc"}) — Player-only ranged restraint.
# A DEX saving throw, not an attack roll: rolled the exact same way the player's own DEX save vs a
# friendly-fire Fireball is (spell_effects.gd's cast_leveled_at_area()'s "pdc"/"pdex_mod"/"pprof"
# block) — d20 + DEX mod + (proficiency, if Stats.check_prof_dex) vs the pool's "save_dc". Costs
# the turn and starts the cooldown regardless of outcome. On a fail: Stats.web_restrained = true
# (blocks ALL player movement — see player.gd's _try_move()/_attempt_web_escape()) and a Web
# structure (DungeonFloor.spawn_web()) appears on the target's own tile, matching the real spell's
# "web appears at the target's square" text.
func _execute_cast_web(target: Node, cfg: Dictionary) -> void:
	_web_cooldown_remaining = int(cfg.get("cooldown", 10))
	var dc: int = int(cfg.get("save_dc", 13))
	var s: Stats = target.stats
	var dex_mod: int = s.dex_modifier()
	var prof: int = s.proficiency_bonus if s.check_prof_dex else 0
	var die: int = Rng.roll(20)
	var total: int = die + dex_mod + prof
	var passed: bool = total >= dc
	var meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=DEX,pass=%d" % [
		die, dex_mod, prof, total, dc, int(passed)]
	if passed:
		GameState.game_log("%s spits a web at you, but you [url=%s]dodge clear[/url]." % [display_name, meta])
		return
	GameState.game_log("%s spits a web at you — you're [url=%s]caught and restrained[/url]!" % [display_name, meta])
	s.web_restrained = true
	s.web_escape_dc = dc
	GameState.player_status_changed.emit()
	_dungeon_floor.spawn_web(target.grid_pos)

# Quasit's Scare ability (pool "scare": {"range","save_dc"}) — Player-only ranged fear effect,
# 1/life. A WIS saving throw, not an attack roll — same d20 + WIS mod + (proficiency, if
# Stats.check_prof_wis) vs the pool's "save_dc" shape as Web's own DEX save above. Costs the turn
# and is consumed regardless of outcome. On a fail the target becomes Frightened of THIS Quasit
# (GameState.apply_player_frightened(self, FRIGHTENED_TURNS, dc)) — see scripts/entities/
# CLAUDE.md's "Conditions" section for the full Frightened mechanic (DISADV on attacks/checks
# while this Quasit is in sight, can't willingly move closer to it, repeats the save each turn).
func _execute_cast_scare(target: Node, cfg: Dictionary) -> void:
	_scare_used = true
	var dc: int = int(cfg.get("save_dc", 10))
	var s: Stats = target.stats
	var wis_mod: int = s.wis_modifier()
	var prof: int = s.proficiency_bonus if s.check_prof_wis else 0
	# Halfling Brave: ADV on saves to avoid the Frightened condition. Gnomish Cunning: same ADV,
	# only if the player chose WIS as their one Gnomish-Cunning stat (see scripts/entities/CLAUDE.md's
	# "Gnome" section).
	var scare_adv: int = 1 if (s.character_race == Stats.CharacterRace.HALFLING or s.gnomish_cunning_grants_adv("wis")) else 0
	var die: int = CombatMath.roll_with_adv_disadv(scare_adv, 0)["die"]
	var total: int = die + wis_mod + prof
	var passed: bool = total >= dc
	var meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=WIS,pass=%d" % [
		die, wis_mod, prof, total, dc, int(passed)]
	if passed:
		GameState.game_log("%s shrieks at you, but you [url=%s]hold your nerve[/url]." % [display_name, meta])
		return
	GameState.game_log("%s shrieks at you — you're [url=%s]frozen with fear[/url]!" % [display_name, meta])
	GameState.apply_player_frightened(self, SCARE_FRIGHTENED_TURNS, dc)

func _move_step(step: Vector2i, next_pos: Vector2i, provokes_oa: bool = true) -> void:
	var prev_pos: Vector2i = grid_pos
	if provokes_oa:
		_check_opportunity_attacks_on_move(prev_pos, next_pos)
	if not is_instance_valid(self) or stats.is_dead():
		return
	$AnimatedSprite2D.flip_h = step.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(next_pos, 0.04 if TurnManager.fast_mode else 0.08)
	if not is_instance_valid(self):
		return
	$AnimatedSprite2D.play("idle")
	if visible:
		AudioManager.play("footstep")
	# Door-camping ambush is no longer detected here — it's fully subsumed by the general
	# CHASING/SEARCHING LOS-regain check in _decide_action() (see "Stealth & Surprise Attacks" in
	# scripts/entities/CLAUDE.md): a door blocks LOS while closed, so crossing it and regaining
	# sight of the target on THIS enemy's own next decision fires the same regain-notice branch.
	if _dungeon_floor.has_door_at(prev_pos):
		_dungeon_floor.close_door(prev_pos)
	var tile_type: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	# Spider Climb (trait "ignore_terrain_slow"): "can go through difficult surfaces without being
	# slowed" — skips the generic Water/Mud slow application entirely, unlike every other enemy.
	# Quasit's Toad form additionally ignores WATER specifically (swims freely) while shifted,
	# without the blanket trait — real amphibian flavor, not a general terrain-ignore ability.
	var ignore_slow: bool = _has_trait("ignore_terrain_slow") \
			or (_shifted_form == "toad" and tile_type == DungeonData.TileType.WATER)
	if (tile_type == DungeonData.TileType.WATER or tile_type == DungeonData.TileType.MUD) \
			and not ignore_slow:
		apply_status("slowed", 1)
	if tile_type == DungeonData.TileType.WATER and stats.burning_turns > 0:
		stats.burning_turns = 0
		GameState.game_log("[color=cyan]The water extinguishes %s's flames![/color]" % display_name)
	# A lit torch embedded in this enemy (thrown-and-lodged, scripts/items/CLAUDE.md's "Torch")
	# also douses out when it steps into water — same "water extinguishes fire" rule as the
	# burning_turns status above, just for the physically-embedded torch item instead.
	if tile_type == DungeonData.TileType.WATER:
		for it: Item in embedded_items:
			if it.is_torch and it.torch_lit:
				it.torch_lit = false
				GameState.game_log("[color=cyan]The water douses the torch lodged in %s![/color]" % display_name)
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
	# An invisible PLAYER doesn't get a reactive Opportunity Attack either — same "unseen mover"
	# logic as the enemy-side check above, just from the other direction (see "Invisibility" in
	# scripts/entities/CLAUDE.md).
	if GameState.player_stats.invisibility_turns > 0:
		return
	var player: Player = _dungeon_floor.get_player()
	if player != null and is_instance_valid(player) and not player.stats.is_dead() and not player._oa_used_this_round:
		var reach: int = CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike"))
		var d_prev: int = player.min_dist_to(prev_pos)
		var d_next: int = player.min_dist_to(next_pos)
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
			if not came.has(nxt) and (_footprint_walkable(nxt) or nxt == target):
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
func _attack_player(_player: Player, sub: Dictionary = {}, long_shot: bool = false, is_ranged: bool = false) -> void:
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
	# Trailblazer R2: this enemy standing on Mud/Water when it attacks rolls with Disadvantage.
	var terrain_disadv: bool = false
	if _dungeon_floor != null:
		var my_tile: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
		if (my_tile == DungeonData.TileType.MUD or my_tile == DungeonData.TileType.WATER) \
				and GameState.get_talent_rank("trailblazer") >= 2:
			terrain_disadv = true
	# Twin Fang R3: the Marked target can never gain Advantage on attacks against the Ranger.
	var twin_fang_blocks_adv: bool = GameState.get_talent_rank("twin_fang") >= 3 \
		and GameState.player_stats.hunters_mark_target == self
	var fog_adv: bool = GameState.is_blinded(_player.grid_pos) and not twin_fang_blocks_adv
	# Pack Tactics (Giant Rat): Advantage whenever another awake ally is within 5 ft (1 tile) of
	# the target. SLEEPING is the closest analogue this engine has to 5e's "incapacitated" — no
	# other enemy status here (rooted/frozen/etc.) maps to a real incapacitating condition.
	var pack_tactics_adv: bool = false
	if _has_trait("pack_tactics") and _dungeon_floor != null:
		for other: Enemy in _dungeon_floor.get_all_enemies():
			if other != self and is_instance_valid(other) and other.behavior != Behavior.SLEEPING \
					and other.min_dist_to(_player.grid_pos) <= 1:
				pack_tactics_adv = true
				break
	# Restrained/Prone conditions on the TARGET (5e: these affect attacks made against them, not
	# the attacker's own condition state — unlike Poisoned/Prone's own-attack DISADV above, which
	# is entirely the player's side and lives in has_disadvantage_condition()). Restrained grants
	# ADV regardless of attack kind; Prone splits by kind (melee ADV, ranged DISADV) since a prone
	# target is an easy target up close but a harder one at range.
	var target_restrained: bool = GameState.player_stats.web_restrained
	var target_prone: bool = GameState.player_stats.prone
	var condition_adv: bool = target_restrained or (target_prone and not is_ranged)
	var condition_disadv: bool = target_prone and is_ranged
	var r: Dictionary = _resolve_attack_roll(GameState.player_stats.armor_class, _attack_bonus_for(sub), bw_penalty,
		fog_adv or pack_tactics_adv or condition_adv,
		# poisoned_condition_turns/frightened_turns here are THIS enemy's own conditions (DISADV on
		# its own attack) — separate from target_prone/target_restrained above, which are the
		# PLAYER's. frightened_turns: Aasimar Necrotic Shroud (Celestial Revelation transformation,
		# scripts/entities/CLAUDE.md's "Aasimar" section) — simplified vs. real Frightened (no
		# can't-approach-the-source movement block, DISADV-on-own-attacks only).
		long_shot or GameState.is_blinded(grid_pos) or terrain_disadv or condition_disadv or poisoned_condition_turns > 0 or frightened_turns > 0)
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
	var roll_info: Dictionary = CombatMath.roll_flat_range(min_d, max_d)
	var dmg_roll: int = roll_info["total"] + adv_bonus_roll
	var dmg: int = dmg_roll * (2 if is_crit else 1)
	# Ray of Enfeeblement (Chthonic Tiefling lineage spell): this enemy's own physical weapon
	# damage is halved while enfeebled — same "weapon attacks that use Strength" scope as RAW,
	# approximated here as any physical damage type since this engine doesn't track per-attack
	# ability score usage for enemies.
	if enfeeble_turns > 0 and dmg_type in ["Slashing", "Piercing", "Bludgeoning"]:
		dmg = maxi(1, dmg / 2)
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
	# Storm Giant ancestry (Goliath, see player_goliath.gd): toggled on, the next entity that
	# deals ANY damage to the player takes 1d8 Thunder back. Consumes the armed flag + a charge
	# only when it actually procs.
	if actual > 0 and GameState.player_stats.character_race == Stats.CharacterRace.GOLIATH \
			and GameState.player_stats.race_variant == Stats.GiantAncestry.STORM \
			and GameState.player_stats.giant_ancestry_armed and not stats.is_dead():
		GameState.player_stats.giant_ancestry_armed = false
		if not GameState.invincible:
			GameState.player_stats.giant_ancestry_uses_remaining -= 1
		GameState._sync_ability_uses()
		var storm_dmg: int = Rng.roll(8)
		var storm_result: Dictionary = take_typed_damage(storm_dmg, "Thunder")
		update_hp_bar()
		GameState.game_log("[color=cyan]Storm's Thunder crackles back at %s for [color=yellow]%d[/color] dmg![/color]" % [display_name, storm_result["actual"]])
		if stats.is_dead():
			GameState.game_log("[color=orange]%s[/color] [color=gray]is killed by the backlash![/color]" % display_name)
			GameState.gain_exp(maxi(1, exp_reward / 2))
			if _dungeon_floor != null:
				_dungeon_floor.remove_enemy(self)
			die()
	# Hellish Rebuke (Infernal Tiefling, see player_tiefling.gd/spell_effects.gd's own
	# trigger_hellish_rebuke() comment): toggled on, the next enemy the player can see within the
	# spell's own range that deals ANY damage to the player is engulfed in flames. Consumes the
	# armed flag only when it actually procs (visible + in range + still alive).
	if actual > 0 and not stats.is_dead() and GameState.player_stats.character_race == Stats.CharacterRace.TIEFLING \
			and GameState.player_stats.hellish_rebuke_armed and "hellish_rebuke" in GameState.player_stats.tiefling_legacy_spell_ids:
		var hr_spell: Spell = SpellDb.get_spell("hellish_rebuke")
		if min_dist_to(_player.grid_pos) <= hr_spell.range_tiles and _dungeon_floor != null and _dungeon_floor.is_tile_visible(grid_pos):
			GameState.player_stats.hellish_rebuke_armed = false
			SpellEffects.trigger_hellish_rebuke(_player, self, _dungeon_floor)
	# Rage's 50% DR (take_damage_raw()) was live for this hit whenever the player was raging AND
	# dmg_type is one of the three physical types.
	var rage_applied: int = 1 if GameState.is_raging else 0
	var dmg_meta: String = "edmg:sides=%d,flat=%d,die=%d,crit=%d,rage=%d,final=%d,advb=%d" % [
		roll_info["sides"], roll_info["flat"], roll_info["die"], 1 if is_crit else 0, rage_applied, actual, adv_bonus_roll]
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
		var e_roll_info: Dictionary = CombatMath.roll_flat_range(e_min, e_max)
		var e_roll: int = e_roll_info["total"]
		var e_dmg: int = e_roll * (2 if is_crit else 1)
		var e_actual: int = GameState.take_damage_raw(e_dmg, false, extra_type)
		if _dungeon_floor != null and not invincible:
			_dungeon_floor.show_damage(_player.position, e_actual, true, CombatMath.damage_type_color(extra_type), 1)
		var extra_meta: String = "edmg:sides=%d,flat=%d,die=%d,crit=%d,rage=0,final=%d,advb=0" % [
			e_roll_info["sides"], e_roll_info["flat"], e_roll_info["die"], 1 if is_crit else 0, e_actual]
		extra_suffix = " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [extra_meta, e_actual, extra_type]
	if is_crit:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s][color=red]CRITICAL HIT![/color][/url] for [url=%s][color=yellow]%d[/color][/url] dmg%s.%s%s" % [bracket_l, atk_label, hit_meta, dmg_meta, actual, extra_suffix, god_suffix, bracket_r])
	else:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s]hits[/url] you for [url=%s][color=yellow]%d[/color][/url] dmg%s.%s%s" % [bracket_l, atk_label, hit_meta, dmg_meta, actual, extra_suffix, god_suffix, bracket_r])
	# Orc Shaman applies poison on hit (top-level attack only — never a multiattack/ability sub-swing).
	if sub.is_empty() and not invincible and display_name == "Orc Shaman" and GameState.player_stats.poison_turns < 3:
		if GameState.apply_player_status("poison", 3):
			GameState.game_log("[color=lime]You are poisoned! (3 turns)[/color]")
	# Generic on-hit condition (pool "multiattack" sub-entry's optional "status"/"status_turns" —
	# same shape "abilities" already supports via _execute_ability()'s own status block). First
	# user: Quasit's Rend (real text: "poisoned condition until Quasit's next turn" — modeled as a
	# flat 1-turn Poisoned condition here, since this engine doesn't track individual enemies'
	# own next-turn timing against the player's status counters).
	if sub.has("status") and not invincible and is_instance_valid(_player) and not _player.stats.is_dead():
		var cond_turns: int = int(sub.get("status_turns", 1))
		if GameState.apply_player_status(String(sub["status"]), cond_turns):
			var cond_label: String = String(sub["status"]).replace("_condition", "").capitalize()
			GameState.game_log("[color=lime]You are %s! (%d turn%s)[/color]" % [cond_label, cond_turns, "" if cond_turns == 1 else "s"])

# Companion (Wild Heart summon) as attack target — see docs/architecture/enemy_system_architecture.md §5.
# No invincible/poison/Retaliation hooks: those are player-only systems. Companion.take_damage_from_enemy()
# already logs the hit/HP line and handles death, so only the miss line needs logging here.
func _attack_companion(companion: Companion, sub: Dictionary = {}, long_shot: bool = false) -> void:
	var atk_label: String = display_name if sub.get("name", "") == "" else "%s's %s" % [display_name, sub["name"]]
	# Pack Tactics (Giant Rat) — see the matching comment in _attack_player() above.
	var pack_tactics_adv: bool = false
	if _has_trait("pack_tactics") and _dungeon_floor != null:
		for other: Enemy in _dungeon_floor.get_all_enemies():
			if other != self and is_instance_valid(other) and other.behavior != Behavior.SLEEPING \
					and other.min_dist_to(companion.grid_pos) <= 1:
				pack_tactics_adv = true
				break
	var r: Dictionary = _resolve_attack_roll(companion.stats.armor_class, _attack_bonus_for(sub), 0,
		GameState.is_blinded(companion.grid_pos) or pack_tactics_adv,
		long_shot or GameState.is_blinded(grid_pos) or poisoned_condition_turns > 0 or frightened_turns > 0)
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
