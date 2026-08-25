class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/characters/classes/"
# Bloodhound R2: how much easier the Hunter's Mark target is to sneak past (Passive Perception
# effectively lowered by this much, vs the player only) — tunable, see markdowns/ranger_base.md.
const BLOODHOUND_R2_PP_DEBUFF: int = 2
const UNDEAD_NAMES: Array = ["Zombie", "Goblin Warrior", "Goblin Archer", "Goblin Minion", "Skeleton", "Orc Warrior", "Orc Shaman", "Masked Orc", "Wogol"]

var _dungeon_floor: Node

# ── Split-out modules (composition child-nodes / static helper) ──────────────────────────────
# See "Split-out modules" in scripts/entities/CLAUDE.md for what moved where and why.
var _wild_heart: PlayerWildHeart
var _zealot: PlayerZealot
var _berserker: PlayerBerserker
var _scarred_warrior: PlayerScarredWarrior
var _base_talents: PlayerBaseTalents
var _ranger_talents: PlayerRangerTalents
var _ammo: PlayerAmmo
var _throw_tool: PlayerThrowTool
var _thief_tools: PlayerThiefTools
var _vfx: PlayerVfx
var _actions: PlayerActions
var _ranged: PlayerRanged
var _spellcasting: PlayerSpellcasting
var _dragonborn: PlayerDragonborn
var _dwarf: PlayerDwarf
var _human: PlayerHuman
var _orc: PlayerOrc
var _aasimar: PlayerAasimar
var _goliath: PlayerGoliath
var _tiefling: PlayerTiefling
var _halfling: PlayerHalfling
var _warlock: PlayerWarlock
var _monk: PlayerMonk

var _queued_path: Array[Vector2i] = []
var _path_executing: bool = false
var _last_move_dir := Vector2i.ZERO
var _target_enemy: Enemy = null
# Snapshot of GameState.player_attacked_this_turn taken in _on_turn_started() BEFORE that
# function clears it — lets the chase-to-attack loop below see "an enemy attacked me last round"
# without racing the flag's own reset (see _execute_queued_path()'s chase-interrupt check).
var _enemy_attacked_last_round: bool = false
# Same snapshot-before-clear pattern, for GameState.enemy_noticed_player_this_turn.
var _enemy_noticed_last_round: bool = false

var _prev_dir: Vector2i = Vector2i.ZERO  # direction held in the previous WAITING_FOR_INPUT frame
var _interrupted: bool = false           # set when enemy seen mid-hold; cleared only on key release

# Set true by PlayerActions.passive_trap_check() the instant it reveals a trap; consumed by the
# very next _process() hold-interrupt check (same frame the move that found it just finished) so
# a freshly-discovered trap stops held movement exactly like a freshly-visible enemy does.
var _trap_alert: bool = false

# Hold-to-wait: holding Space repeats wait_action() once per real turn for as long as it's held
# (mirrors the movement-hold-repeat mechanic above), stopping the instant an enemy becomes visible
# (same interrupt-on-sight rule as movement) until the key is released and re-pressed.
var _wait_held_active: bool = false      # a wait was already issued for the current WAITING_FOR_INPUT frame
var _wait_interrupted: bool = false      # enemy seen mid-hold; blocks further repeats until key release

var _throw_item: Item = null
var _tool_item: Item = null
var _rest_interrupt_shown: bool = false

# Multi-turn action interrupt baseline (short rest / armor change / scroll learn): snapshot of
# {Enemy: grid_pos at the moment the action began}. A merely-visible unaware enemy that was
# already accounted for when the player consciously started the action (and hasn't moved since)
# no longer interrupts it — only a genuinely NEW arrival, an already-tracked enemy that moved, or
# any currently-hunting (CHASING/SEARCHING) enemy does. Matches SPD's "you knew about that
# sleeper" tolerance instead of any-enemy-in-FOV being an auto-interrupt.
var _interrupt_baseline: Dictionary = {}
var _interrupt_baseline_set: bool = false

# FOV snapshots for advantage (surprise attack) detection
var _fov_prev_turn: Array[Enemy] = []  # visible enemies at START of previous player turn
var _fov_this_turn: Array[Enemy] = []  # visible enemies at START of current player turn

@onready var _camera: Camera2D = $Camera2D
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 5.0
const ZOOM_STEP: float = 0.25

var _is_panning: bool = false
var _lmb_panning: bool = false
# True when the LMB press that's currently held down started over a UI Control (any overlay,
# the ActionBar, etc.) rather than the game world — gates camera panning in _input()'s motion
# handler below. General fix for "dragging a UI element also pans the background/level": the
# previous fix only excluded specific known overlay-open flags one at a time (spellbook_open,
# inventory_open, ...) and still missed plain ActionBar-slot drags with no overlay open at all.
var _lmb_press_over_ui: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_cam: Vector2 = Vector2.ZERO
var _click_start_screen_pos: Vector2 = Vector2(-1.0, -1.0)
var _pending_click_tile: Vector2i = Vector2i(-1, -1)

var _hover_indicator: Sprite2D = null
var _hover_last_icon_path: String = ""
var _hover_last_texture: Texture2D = null
const HOVER_ICON_TARGET_PX: float = 12.0  # ~16px weapon/ranged art at the old flat 0.75 scale

# Movement-speed consistency (scripts/entities/CLAUDE.md's "Movement speed scaling",
# TurnManager.enemy_actions_this_round): a free move runs zero enemy actions, so without an
# artificial beat the very next input becomes available almost instantly - several free moves in
# a row would visibly warp/jitter across tiles instead of reading as "opponents just don't act."
const FREE_MOVE_BEAT_SEC: float = 0.08

# ── Rage state ────────────────────────────────────────────────────────────────
# Baseline: lasts 1 turn, refreshed to 1 by attacking or being attacked (unconditional).
# _rage_attacked_this_turn: set in _bump_attack when raging + STR weapon; cleared at turn start.
var _is_raging: bool = false
var _rage_turns: int = 0
var _rage_attacked_this_turn: bool = false

# ── Wild Heart state (Tier 2) ─────────────────────────────────────────────────
# Eagle Natural Rager: per-round free-move cap (max 1×/round). Only resets on REAL turns.
var _eagle_free_move_used: bool = false
# Flag set before revert_to_waiting() so _on_turn_started() knows it's a reverted (non-enemy) turn.
# Per-round caps are NOT reset on reverted turns — only after enemies go.
var _reverted_this_round: bool = false

# ── World Tree state (Tier 2) ─────────────────────────────────────────────────
# Ironwood Bark R3: bonus damage from temp HP snapshotted at turn start, consumed by next attack.
var _ironwood_bark_bonus_pending: int = 0
# Grip of the Forest: once-per-turn hook-targeting mode (armed via ability bar, resolved on click).
# The "used this turn" flag lives on GameState.grip_of_the_forest_used_this_turn, not here, so
# is_ability_usable() can grey the ability-bar slot for it — see that field's own comment.
var _hook_mode_active: bool = false

# ── Ranger state ───────────────────────────────────────────────────────────────
# Hunter's Mark: same arm-then-click targeting-mode pattern as Grip of the Forest's hook mode
# above, but no per-turn "used" cap (retargeting an active mark is free, see player_ranger_talents.gd).
var _hunters_mark_mode_active: bool = false

# ── Weapon mastery state ────────────────────────────────────────────────────────
# Vex (Short Bow): after a Short-Bow hit, grants Advantage on the very next attack THIS ROUND
# against that exact same enemy (any attack type — melee, cleave, ranged). Consumed on the
# next attack attempt regardless of hit/miss. Cleared at a real new-round turn start; survives
# a revert_to_waiting() free-action chain (Rager move/attack, Eagle) within the same round.
var _vex_adv_target: Enemy = null

# ── Opportunity Attack state ──────────────────────────────────────────────────
# Once-per-round reaction cap (5e: one reaction per round). Reset in _on_turn_started()'s
# "not came_from_revert" block alongside the other per-round caps — must survive
# revert_to_waiting() free-action chains and only reset after enemies actually take a round.
var _oa_used_this_round: bool = false

# Expeditious Retreat: once-per-round free-move cap, same reset point as the caps above. Scoped
# to _try_move() (single-step WASD movement) only — the queued-path/chase-to-target movement
# functions don't check it, same documented scope limitation as Battlefield Expert R3's own
# free side-step.
var _expeditious_retreat_move_used_this_turn: bool = false
# Shared duty-cycle bookkeeping for every player-side movement-speed modifier that works as an
# "every Nth real move" gate — Wood Elf's 35 ft speed, Longstrider's +1/3 speed, and Exhaustion's
# -1/6-per-level movement penalty (Large Form's own +1/3 counter stays local to PlayerGoliath,
# see player_goliath.gd, since it's a single implementation, not a duplicate). Replaces what used
# to be three separate hand-rolled int counters (`_wood_elf_move_counter`/
# `_exhaustion_move_counter`/`_longstrider_move_counter`) with one id-keyed accumulator dict, ticked
# via CombatMath.tick_duty_cycle() (the same Bresenham-style math Enemy._tick_speed_gate() uses for
# its "speed" pool key) through `_consume_duty_cycle()` below — see scripts/entities/CLAUDE.md's
# "Movement speed scaling". Not serialized — mid-floor combat bookkeeping, same tier as
# `_expeditious_retreat_move_used_this_turn`.
var _speed_gate_accum: Dictionary = {}

# Ticks the named duty-cycle source (`id`) by `moves` out of every `per` real moves and returns
# whether it "fires" this call — see `_speed_gate_accum`'s own comment above.
func _consume_duty_cycle(id: String, moves: int, per: int) -> bool:
	var r: Dictionary = CombatMath.tick_duty_cycle(int(_speed_gate_accum.get(id, 0)), moves, per)
	_speed_gate_accum[id] = r["accum"]
	return r["fires"] > 0

## Rewind snapshot of the scattered per-turn transient fields that live on Player/its composition
## children rather than on Stats/GameState — see scripts/autoloads/rewind_manager.gd.
func capture_rewind_state() -> Dictionary:
	return {
		"grid_pos": grid_pos,
		"oa_used_this_round": _oa_used_this_round,
		"reverted_this_round": _reverted_this_round,
		"enemy_attacked_last_round": _enemy_attacked_last_round,
		"enemy_noticed_last_round": _enemy_noticed_last_round,
		"speed_gate_accum": _speed_gate_accum.duplicate(),
		# Rage's own live gate + visual — GameState.is_raging is only a UI mirror; every actual
		# combat-roll check (e.g. _bump_attack()'s rage_bonus) reads THIS field, so restoring
		# GameState.is_raging alone (rewind_manager.gd's own gs_fields list) would leave Rage's
		# real mechanical effect and sprite tint out of sync with the restored HUD state.
		"is_raging": _is_raging,
		"rage_turns": _rage_turns,
		"rage_attacked_this_turn": _rage_attacked_this_turn,
		"eagle_free_move_used": _eagle_free_move_used,
		"ironwood_bark_bonus_pending": _ironwood_bark_bonus_pending,
		"hook_mode_active": _hook_mode_active,
		"hunters_mark_mode_active": _hunters_mark_mode_active,
		"expeditious_retreat_move_used_this_turn": _expeditious_retreat_move_used_this_turn,
		"berserker": _berserker.get_rewind_fields(),
		"scarred_warrior": _scarred_warrior.get_rewind_fields(),
		"zealot": _zealot.get_rewind_fields(),
		"goliath": _goliath.get_rewind_fields(),
		"halfling": _halfling.get_rewind_fields(),
		"orc": _orc.get_rewind_fields(),
		"monk": _monk.get_rewind_fields(),
	}

func restore_rewind_state(d: Dictionary) -> void:
	set_grid_pos(d.get("grid_pos", grid_pos))
	_oa_used_this_round = bool(d.get("oa_used_this_round", false))
	_reverted_this_round = bool(d.get("reverted_this_round", false))
	_enemy_attacked_last_round = bool(d.get("enemy_attacked_last_round", false))
	_enemy_noticed_last_round = bool(d.get("enemy_noticed_last_round", false))
	_speed_gate_accum = (d.get("speed_gate_accum", {}) as Dictionary).duplicate()
	_vex_adv_target = null
	_is_raging = bool(d.get("is_raging", false))
	_rage_turns = int(d.get("rage_turns", 0))
	_rage_attacked_this_turn = bool(d.get("rage_attacked_this_turn", false))
	GameState.is_raging = _is_raging
	GameState.rage_turns_remaining = _rage_turns
	$AnimatedSprite2D.modulate = Color(1.6, 0.55, 0.55) if _is_raging else Color(1.0, 1.0, 1.0)
	_eagle_free_move_used = bool(d.get("eagle_free_move_used", false))
	_ironwood_bark_bonus_pending = int(d.get("ironwood_bark_bonus_pending", 0))
	_hook_mode_active = bool(d.get("hook_mode_active", false))
	_hunters_mark_mode_active = bool(d.get("hunters_mark_mode_active", false))
	_expeditious_retreat_move_used_this_turn = bool(d.get("expeditious_retreat_move_used_this_turn", false))
	_berserker.set_rewind_fields(d.get("berserker", {}))
	_scarred_warrior.set_rewind_fields(d.get("scarred_warrior", {}))
	_zealot.set_rewind_fields(d.get("zealot", {}))
	_goliath.set_rewind_fields(d.get("goliath", {}))
	_halfling.set_rewind_fields(d.get("halfling", {}))
	_orc.set_rewind_fields(d.get("orc", {}))
	_monk.set_rewind_fields(d.get("monk", {}))


func _ready() -> void:
	stats = GameState.player_stats
	is_friendly = true
	z_index = 3
	add_to_group("player")
	_setup_animations()
	_setup_faerie_fire_indicator()

	_wild_heart = PlayerWildHeart.new(); _wild_heart.player = self; add_child(_wild_heart)
	_zealot = PlayerZealot.new(); _zealot.player = self; add_child(_zealot)
	_berserker = PlayerBerserker.new(); _berserker.player = self; add_child(_berserker)
	_scarred_warrior = PlayerScarredWarrior.new(); _scarred_warrior.player = self; add_child(_scarred_warrior)
	_base_talents = PlayerBaseTalents.new(); _base_talents.player = self; add_child(_base_talents)
	_ranger_talents = PlayerRangerTalents.new(); _ranger_talents.player = self; add_child(_ranger_talents)
	GameState.force_rage_end.connect(_end_rage)
	_ammo = PlayerAmmo.new(); _ammo.player = self; add_child(_ammo)
	_throw_tool = PlayerThrowTool.new(); _throw_tool.player = self; add_child(_throw_tool)
	_thief_tools = PlayerThiefTools.new(); _thief_tools.player = self; add_child(_thief_tools)
	_vfx = PlayerVfx.new(); _vfx.player = self; add_child(_vfx)
	_actions = PlayerActions.new(); _actions.player = self; add_child(_actions)
	_ranged = PlayerRanged.new(); _ranged.player = self; add_child(_ranged)
	_spellcasting = PlayerSpellcasting.new(); _spellcasting.player = self; add_child(_spellcasting)
	_dragonborn = PlayerDragonborn.new(); _dragonborn.player = self; add_child(_dragonborn)
	_dwarf = PlayerDwarf.new(); _dwarf.player = self; add_child(_dwarf)
	_human = PlayerHuman.new(); _human.player = self; add_child(_human)
	_orc = PlayerOrc.new(); _orc.player = self; add_child(_orc)
	_aasimar = PlayerAasimar.new(); _aasimar.player = self; add_child(_aasimar)
	_goliath = PlayerGoliath.new(); _goliath.player = self; add_child(_goliath)
	_tiefling = PlayerTiefling.new(); _tiefling.player = self; add_child(_tiefling)
	_halfling = PlayerHalfling.new(); _halfling.player = self; add_child(_halfling)
	_warlock = PlayerWarlock.new(); _warlock.player = self; add_child(_warlock)
	_monk = PlayerMonk.new(); _monk.player = self; add_child(_monk)

	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_action_requested.connect(_on_action_requested)
	GameState.player_throw_primed.connect(_throw_tool.on_throw_primed)
	GameState.player_tool_primed.connect(_throw_tool.on_tool_primed)
	GameState.player_scroll_primed.connect(_spellcasting.on_scroll_primed)
	GameState.player_died.connect(_on_player_died)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.camera_recenter_requested.connect(_reset_camera_offset)
	GameState.screen_shake.connect(_vfx.screen_shake)
	GameState.equipment_changed.connect(_on_equipment_changed)
	GameState.potion_drunk.connect(func():
		if GameState.add_item(_throw_tool.make_empty_bottle()):
			GameState.game_log("[color=gray]Empty bottle added to your bag.[/color]")
	)
	TurnManager.player_turn_started.connect(_on_turn_started)
	TurnManager.player_turn_ending.connect(_on_turn_ending)

func _on_equipment_changed() -> void:
	if _throw_item != null:
		_throw_item = null
		GameState.game_log("[color=gray]Throw cancelled.[/color]")
	# Wearing heavy armor while raging ends rage immediately (D&D 5e rule)
	if _is_raging:
		var armor: Item = GameState.equipped_armor
		if armor != null and armor.is_heavy_armor:
			_end_rage()
			GameState.game_log("[color=gray]The heavy armor weighs you down — Rage ends![/color]")

func _on_player_died() -> void:
	visible = false
	_queued_path.clear()
	_path_executing = false

func _on_class_chosen(_cls: Stats.CharacterClass) -> void:
	# BUGFIX: reset_for_class_reselect() (Custom character-creation path) replaces
	# GameState.player_stats with a brand-new Stats object rather than mutating the one
	# `_ready()` cached into this node's own `stats` field — DungeonFloor._load_floor() (which
	# would otherwise re-sync it) has already run once for floor 1 before class selection even
	# starts, and doesn't run again until the player descends to floor 2. Without this re-sync,
	# `stats` kept pointing at the stale pre-selection placeholder for the entire first floor —
	# e.g. a fresh Wizard's `stats.caster` read null, so PlayerSpellcasting reported "no spell
	# slot available" even though GameState.player_stats.caster.slot_pool was correctly seeded.
	stats = GameState.player_stats
	_setup_animations()

func _on_player_hp_changed(_c: int, _m: int) -> void:
	update_hp_bar()

func _on_turn_started() -> void:
	GameState.player_grid_pos = grid_pos
	# Determine whether this is a reverted turn (Eagle free action) or a real new round.
	var came_from_revert: bool = _reverted_this_round
	_reverted_this_round = false
	# Per-round caps only reset on REAL turns (after enemies resolve).
	# On reverted turns, Eagle's free-move flag persists so it can't fire again this round.
	if not came_from_revert:
		# Risen from the Dead (see GameState.risen_from_dead_active's own comment): protects the
		# revive round itself plus the enemy round right after it, then clears the instant the
		# FOLLOWING real player round begins — this is exactly that clear point.
		if GameState.risen_from_dead_active:
			GameState.risen_from_dead_active = false
			GameState.player_status_changed.emit()
		_eagle_free_move_used = false
		if GameState.grip_of_the_forest_used_this_turn or GameState.halfling_nimbleness_used_this_turn or GameState.step_of_wind_used_this_turn or GameState.deflect_attacks_used_this_turn or GameState.monk_extra_attack_used_this_turn:
			GameState.grip_of_the_forest_used_this_turn = false
			GameState.halfling_nimbleness_used_this_turn = false
			GameState.step_of_wind_used_this_turn = false
			GameState.deflect_attacks_used_this_turn = false
			GameState.monk_extra_attack_used_this_turn = false
			GameState.ability_bar_changed.emit()
		# Bonus Action refreshes at the start of every real round — see scripts/entities/CLAUDE.md's
		# "Bonus Action economy" section.
		if GameState.bonus_action_used:
			GameState.bonus_action_used = false
			GameState.ability_bar_changed.emit()
		_vex_adv_target = null
		# Loading: a weapon that fired this turn can fire again next real turn — see Item.
		# is_loading's own comment. Equipped weapon only; a Loading weapon sitting unequipped in
		# the bag was never able to fire in the first place, so there's nothing to reset there.
		if GameState.equipped_ranged != null and GameState.equipped_ranged.is_loading:
			GameState.equipped_ranged.loading_used_this_turn = false
		# Hunter's Mark is a bonus action in 5e — only one cast per round, see Stats.
		# hunters_mark_cast_this_round's own comment.
		stats.hunters_mark_cast_this_round = false
		_oa_used_this_round = false
		_expeditious_retreat_move_used_this_turn = false
		_halfling.reset_turn()
		_berserker.clear_turn_start_ac_bonus()
		_berserker.tick_frenzied_killer()
		# Zealot Strike deactivates with no effect if the turn ends without a melee attack.
		_zealot.zealot_strike_armed = false
		# Battlefield Expert R3: reads "was hit last turn" — same flag the rage-tick block below
		# reads. Read-only here (not cleared) so Rage's own combat_last_turn check further down
		# still sees the value; the flag is cleared once, after both readers, further below.
		_base_talents.tick_free_sidestep(GameState.player_was_hit_this_turn)
		# Tactician (Battlefield Expert R1) buff expiry — only ticks on a real turn, never on a
		# reverted/free-action turn (R3's own free side-step).
		_base_talents.tick_battlefield_adv_expiry()
		# Shield spell (leveled-spells-and-slots-plan.md §7): +5 AC lasts until the start of the
		# caster's next real turn.
		if stats.shield_ac_bonus > 0:
			stats.shield_ac_bonus = 0
			GameState.recalculate_stats()
		# Blade Ward cantrip: 10-turn duration, ticked once per real turn. Reaching 0 ends the
		# effect and clears concentration (a CON-check failure on taking damage — see
		# GameState.take_damage_raw() — can also end it earlier).
		if stats.blade_ward_turns > 0:
			stats.blade_ward_turns -= 1
			if stats.blade_ward_turns <= 0:
				stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]Blade Ward fades.[/color]")
		# Expeditious Retreat: 100-turn duration, ticked once per real turn (same pattern as
		# Blade Ward above).
		if stats.expeditious_retreat_turns > 0:
			stats.expeditious_retreat_turns -= 1
			if stats.expeditious_retreat_turns <= 0:
				if stats.concentration_spell_id == "expeditious_retreat":
					stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]Expeditious Retreat fades.[/color]")
		# Fog Cloud: 600-turn duration, ticked once per real turn — also clears the actual cloud
		# position/radius on GameState (unlike Blade Ward/Witch Bolt, which have nothing to clear
		# beyond their own Stats fields).
		if stats.fog_cloud_turns > 0:
			stats.fog_cloud_turns -= 1
			if stats.fog_cloud_turns <= 0:
				if stats.concentration_spell_id == "fog_cloud":
					stats.concentration_spell_id = ""
				GameState.clear_fog_cloud()
				GameState.game_log("[color=gray]The fog cloud dissipates.[/color]")
		# Darkness (Drow lineage spell): same 100-turn Concentration pattern as Fog Cloud above.
		if stats.darkness_turns > 0:
			stats.darkness_turns -= 1
			if stats.darkness_turns <= 0:
				if stats.concentration_spell_id == "darkness":
					stats.concentration_spell_id = ""
				GameState.clear_darkness()
				GameState.game_log("[color=gray]The darkness dissipates.[/color]")
		# Faerie Fire (Drow lineage spell): same 10-turn Concentration pattern as Darkness above —
		# this only ticks the CASTER's own concentration duration; each outlined enemy's own
		# faerie_fire_turns (whether it stays lit/outlined) ticks down independently in that
		# enemy's own decide_turn(), so the effect doesn't retroactively end on already-outlined
		# enemies just because the caster's concentration expires (documented simplification,
		# same "no full framework" precedent as every other concentration spell here).
		if stats.faerie_fire_turns > 0:
			stats.faerie_fire_turns -= 1
			if stats.faerie_fire_turns <= 0:
				if stats.concentration_spell_id == "faerie_fire":
					stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]Faerie Fire fades — the dancing lights die out.[/color]")
		# The PLAYER's own "am I outlined" counter — independent of the caster-side duration above
		# (see Stats.faerie_fire_outlined_turns's own doc comment for why they're separate fields).
		if stats.faerie_fire_outlined_turns > 0:
			stats.faerie_fire_outlined_turns -= 1
			if stats.faerie_fire_outlined_turns <= 0:
				GameState.game_log("[color=gray]The dancing light outlining you fades.[/color]")
				_refresh_faerie_fire_visual()
		# Longstrider: NOT Concentration — 600-turn flat duration (5e RAW's "1 hour").
		if stats.longstrider_turns > 0:
			stats.longstrider_turns -= 1
			if stats.longstrider_turns <= 0:
				GameState.game_log("[color=gray]Longstrider fades.[/color]")
		# Barkskin: flat 600-turn duration, NOT Concentration (see Stats.barkskin_turns' own
		# comment). Restoring the Companion's own AC (if that's who was touched) mirrors
		# Invisibility's own companion-mirror pattern above.
		if stats.barkskin_turns > 0:
			stats.barkskin_turns -= 1
			if stats.barkskin_turns <= 0:
				if stats.barkskin_on_companion and GameState.player_companion != null and is_instance_valid(GameState.player_companion):
					GameState.player_companion.stats.armor_class = GameState.player_companion.stats.barkskin_pre_ac
				stats.barkskin_on_companion = false
				GameState.recalculate_stats()
				GameState.game_log("[color=gray]Barkskin fades.[/color]")
		# Detect Magic: same 600-turn Concentration pattern as Fog Cloud/Darkness above — nothing
		# beyond the Stats field to clear (the blue-dot markers are recomputed live off
		# detect_magic_turns > 0 every update_fog() call, no position/state to reset).
		if stats.detect_magic_turns > 0:
			stats.detect_magic_turns -= 1
			if stats.detect_magic_turns <= 0:
				if stats.concentration_spell_id == "detect_magic":
					stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]Your sense of magic fades.[/color]")
		# Pass Without Trace: same 600-turn Concentration pattern as Fog Cloud/Darkness above.
		if stats.pass_without_trace_turns > 0:
			stats.pass_without_trace_turns -= 1
			if stats.pass_without_trace_turns <= 0:
				if stats.concentration_spell_id == "pass_without_trace":
					stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]Pass Without Trace fades.[/color]")
		# Minor Illusion (Forest Gnome lineage cantrip): flat duration, NOT Concentration.
		if stats.minor_illusion_turns > 0:
			stats.minor_illusion_turns -= 1
			if stats.minor_illusion_turns <= 0:
				GameState.game_log("[color=gray]Your minor illusion fades.[/color]")
		# Hunter's Mark: 600-turn Concentration duration, ticked once per real turn (same pattern
		# as Blade Ward/Expeditious Retreat/Fog Cloud above, just a longer flat duration).
		if stats.hunters_mark_turns > 0:
			stats.hunters_mark_turns -= 1
			if stats.hunters_mark_turns <= 0:
				if stats.concentration_spell_id == "hunters_mark":
					stats.concentration_spell_id = ""
				stats.hunters_mark_target = null
				stats.hunters_mark_fresh = false
				GameState.game_log("[color=gray]Hunter's Mark fades.[/color]")
		# Baseline free-recast window (markdowns/ranger_base.md's Hunter's Mark section): `_pending`
		# (armed the instant the Marked target died) becomes `_available` for exactly this one real
		# turn; if it was already available and still unused from the PREVIOUS turn, the window has
		# now expired.
		if stats.hunters_mark_free_recast_available:
			stats.hunters_mark_free_recast_available = false
			GameState.game_log("[color=gray]Hunter's Mark: the free re-mark window has passed.[/color]")
			GameState.ability_bar_changed.emit()
		elif stats.hunters_mark_free_recast_pending:
			stats.hunters_mark_free_recast_pending = false
			stats.hunters_mark_free_recast_available = true
			GameState.ability_bar_changed.emit()
		# Hex: 600-turn Concentration cap (+600/upcast level — see Spell.upcast_flat_amount's own
		# comment). No repeated-save early-end exists for this one (unlike Ray of Enfeeblement/Hold
		# Person/Hideous Laughter below) — the curse only ever ends via this duration backstop, a
		# damage-based concentration break, casting a different concentration spell, or the hexed
		# target dying (Enemy.die(), which also arms hex_free_recast_pending).
		if stats.hex_turns > 0:
			stats.hex_turns -= 1
			if stats.hex_turns <= 0:
				if stats.concentration_spell_id == "hex":
					stats.concentration_spell_id = ""
				stats.hex_target = null
				stats.hex_ability = ""
				GameState.game_log("[color=gray]Hex fades.[/color]")
		# Ray of Enfeeblement: 10-turn Concentration cap — the target's own repeated end-of-turn
		# save (Enemy.decide_turn()) usually ends this earlier by clearing enfeeble_turns to 0
		# directly; this is just the outer duration backstop.
		if stats.ray_of_enfeeblement_turns > 0:
			stats.ray_of_enfeeblement_turns -= 1
			if stats.ray_of_enfeeblement_turns <= 0:
				if stats.concentration_spell_id == "ray_of_enfeeblement":
					stats.concentration_spell_id = ""
				if is_instance_valid(stats.ray_of_enfeeblement_target):
					stats.ray_of_enfeeblement_target.enfeeble_turns = 0
				stats.ray_of_enfeeblement_target = null
				GameState.game_log("[color=gray]Ray of Enfeeblement fades.[/color]")
		# Ensnaring Strike: same 10-turn Concentration cap/backstop as Ray of Enfeeblement above —
		# the target's own repeated STR save (Enemy.decide_turn()) usually ends this earlier by
		# clearing restrained_turns to 0 directly; this is just the outer duration backstop.
		if stats.ensnaring_strike_turns > 0:
			stats.ensnaring_strike_turns -= 1
			if stats.ensnaring_strike_turns <= 0:
				if stats.concentration_spell_id == "ensnaring_strike":
					stats.concentration_spell_id = ""
				if is_instance_valid(stats.ensnaring_strike_target):
					stats.ensnaring_strike_target.restrained_turns = 0
				stats.ensnaring_strike_target = null
				GameState.game_log("[color=gray]Ensnaring Strike fades.[/color]")
		# Hold Person: same 10-turn Concentration cap/backstop as Ray of Enfeeblement above.
		if stats.hold_person_turns > 0:
			stats.hold_person_turns -= 1
			if stats.hold_person_turns <= 0:
				if stats.concentration_spell_id == "hold_person":
					stats.concentration_spell_id = ""
				for e: Enemy in stats.hold_person_target:
					if is_instance_valid(e):
						e.paralyzed_turns = 0
						e._refresh_paralyzed_visual()
				stats.hold_person_target = []
				GameState.game_log("[color=gray]Hold Person fades.[/color]")
		# Tasha's Hideous Laughter: same 10-turn Concentration cap/backstop as Hold Person above
		# — the target's own repeated saves (Enemy.decide_turn(), and on-hit in
		# take_typed_damage()) usually end this earlier by clearing incapacitated_turns to 0
		# directly. Prone is left untouched either way (see end_concentration()'s own comment).
		if stats.hideous_laughter_turns > 0:
			stats.hideous_laughter_turns -= 1
			if stats.hideous_laughter_turns <= 0:
				if stats.concentration_spell_id == "hideous_laughter":
					stats.concentration_spell_id = ""
				for e: Enemy in stats.hideous_laughter_target:
					if is_instance_valid(e):
						e.incapacitated_turns = 0
				stats.hideous_laughter_target = []
				GameState.game_log("[color=gray]Tasha's Hideous Laughter fades.[/color]")
		# Invisibility: 600-turn duration, ticked once per real turn. Usually already ended earlier
		# this same turn transition via _resolve_stealth_check()'s attack/cast check (which runs
		# first, from _on_turn_ending()) — this decrement is a no-op whenever that already zeroed
		# it, and only matters for the "never attacked, just wore off" case.
		if stats.invisibility_turns > 0:
			stats.invisibility_turns -= 1
			if stats.invisibility_turns <= 0:
				if stats.concentration_spell_id == "invisibility":
					stats.concentration_spell_id = ""
				GameState.game_log("[color=gray]You fade back into view.[/color]")
				var _comp: Companion = GameState.player_companion
				if _comp != null and is_instance_valid(_comp) and _comp.invisibility_turns > 0:
					_comp.invisibility_turns = 0
		# Unconditional sync, every real turn, regardless of the branch above — Invisibility being
		# a real Concentration effect now means it can also end via a completely different code
		# path (GameState._check_concentration_break()'s damage-based CON check, or casting a
		# different concentration spell), neither of which has a Player node reference to call
		# _update_invisibility_visual() from directly. Bugfix: those paths correctly zeroed
		# invisibility_turns/cleared concentration_spell_id, but the player's own sprite stayed
		# translucent since nothing ever told it to refresh. Idempotent — cheap no-op most turns.
		_update_invisibility_visual()
		# Draconic Flight: 100-turn duration, ticked once per real turn (same pattern above).
		if stats.draconic_flight_turns > 0:
			stats.draconic_flight_turns -= 1
			if stats.draconic_flight_turns <= 0:
				GameState.game_log("[color=gray]You touch back down to the ground.[/color]")
				GameState.player_status_changed.emit()
		# Celestial Revelation: 10-turn duration, ticked once per real turn (same pattern above) —
		# celestial_revelation_bonus_used_this_turn resets every tick so "the first damage you
		# deal EACH turn" is genuinely per-turn, not just the one attack right after activation
		# (see _bump_attack() for where the bonus is consumed).
		# Large Form (Goliath): 100-turn duration, ticked once per real turn (same pattern
		# above) - see player_goliath.gd.
		if stats.large_form_turns > 0:
			stats.large_form_turns -= 1
			if stats.large_form_turns <= 0:
				_goliath.end_large_form()
		if stats.celestial_revelation_turns > 0:
			stats.celestial_revelation_bonus_used_this_turn = false
			stats.celestial_revelation_turns -= 1
			if stats.celestial_revelation_turns <= 0:
				stats.celestial_revelation_transform = -1
				GameState.game_log("[color=gray]Celestial Revelation fades.[/color]")
				GameState.player_status_changed.emit()
			else:
				# Inner Radiance re-bursts at the end of every turn it's still active, not just
				# the first — see PlayerAasimar.tick_inner_radiance()'s own comment.
				_aasimar.tick_inner_radiance()
		# Stonecunning's Tremorsense: 100-turn duration, ticked once per real turn (same pattern).
		if stats.tremorsense_turns > 0:
			stats.tremorsense_turns -= 1
			if stats.tremorsense_turns <= 0:
				GameState.game_log("[color=gray]The tremor-sense fades.[/color]")
				GameState.player_status_changed.emit()
				if _dungeon_floor != null:
					_dungeon_floor.update_fog(grid_pos)
		# Frightened: repeats the WIS save once per real turn (5e: "at the end of each of its
		# turns" — ticked at turn START here instead, same cadence as every other duration in
		# this block; no other timing hook exists for a single-slot condition). A pass ends it
		# early; a fail just ticks toward the outer "1 minute" cap (frightened_turns). LOS to
		# the source is NOT required for the repeat save itself, only for the ADV/DISADV-while-
		# frightened effect (see _frightened_active()) — 5e lets you keep shaking off fear even
		# once the source is out of sight.
		if stats.frightened_turns > 0 and stats.frightened_source != null:
			if not is_instance_valid(stats.frightened_source) or stats.frightened_source.stats.is_dead():
				GameState.clear_player_frightened()
			else:
				var fr_wis_mod: int = stats.wis_modifier()
				var fr_prof: int = stats.proficiency_bonus if stats.check_prof_wis else 0
				# Halfling Brave: ADV on saves to end the Frightened condition. Gnomish Cunning:
				# same ADV, but only if the player chose WIS as their one Gnomish-Cunning stat
				# (see scripts/entities/CLAUDE.md's "Gnome" section — this is the only existing
				# player-side WIS SAVE in the game; search_action()/passive_trap_check() are WIS
				# CHECKS and deliberately untouched by this trait).
				var fr_adv: int = 1 if (stats.character_race == Stats.CharacterRace.HALFLING or stats.gnomish_cunning_grants_adv("wis") or GameState.knows_invocation("beguiling_defenses")) else 0
				var fr_roll: Dictionary = CombatMath.roll_with_adv_disadv(fr_adv, 0)
				var fr_die: int = fr_roll["die"]
				var fr_exh: int = CombatMath.exhaustion_penalty()
				var fr_total: int = fr_die + fr_wis_mod + fr_prof + fr_exh
				var fr_pass: bool = fr_total >= stats.frightened_save_dc
				# Bugfix: this save used to log a bare, non-hoverable line with no roll breakdown at
				# all — no way to see the d20 result, let alone whether Halfling Brave's Advantage
				# (two dice, pick higher) actually applied. Now wrapped exactly like every other
				# save's [url=] tooltip.
				var fr_meta: String = "save:die=%d,d1=%d,d2=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=WIS,pass=%d,adv=%d,disadv=%d,lucky1=%d,lucky2=%d,exh=%d" % [
					fr_die, fr_roll["die1"], fr_roll["die2"], fr_wis_mod, fr_prof, fr_total, stats.frightened_save_dc, int(fr_pass),
					int(fr_roll["adv"]), int(fr_roll["disadv"]), int(fr_roll["lucky1"]), int(fr_roll["lucky2"]), fr_exh]
				if fr_pass:
					GameState.game_log("[color=lime]You [url=%s]shake off[/url] your fear of %s![/color]" % [fr_meta, stats.frightened_source.display_name])
					GameState.clear_player_frightened()
				else:
					GameState.game_log("[color=gray]You [url=%s]remain frightened[/url] of %s.[/color]" % [fr_meta, stats.frightened_source.display_name])
					stats.frightened_turns -= 1
					if stats.frightened_turns <= 0:
						GameState.clear_player_frightened()
		# Bearded Devil's Beard attack: repeats a CON save once per real turn to end the
		# Poisoned condition early — mirrors Frightened's own repeated-save shape above, just
		# CON instead of WIS and gated on poisoned_condition_save_dc > 0 (a plain Tripwire/Rend
		# Poisoned application, save_dc == 0, only ever decays via Stats.tick_status(), never
		# rolls this). tick_status() (below) still decrements poisoned_condition_turns by 1
		# every real turn regardless — this save is just an extra way to end it early.
		# BUGFIX: this block (and Infernal Wound right below it) used to be accidentally nested
		# one level too deep, inside the `if stats.frightened_turns > 0` branch above — so a
		# poisoned-but-not-frightened player never got this early-end save (fell back to the
		# plain tick_status() decay only). Dedented to its own top-level sibling check.
		if stats.poisoned_condition_turns > 0 and stats.poisoned_condition_save_dc > 0:
			var pc_mod: int = stats.con_modifier()
			var pc_prof: int = stats.proficiency_bonus if stats.check_prof_con else 0
			var pc_roll: Dictionary = CombatMath.roll_with_adv_disadv(0, 0)
			var pc_die: int = pc_roll["die"]
			var pc_exh: int = CombatMath.exhaustion_penalty()
			var pc_total: int = pc_die + pc_mod + pc_prof + pc_exh
			var pc_pass: bool = pc_total >= stats.poisoned_condition_save_dc
			var pc_meta: String = "save:die=%d,d1=%d,d2=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=CON,pass=%d,adv=0,disadv=0,lucky1=%d,lucky2=%d,exh=%d" % [
				pc_die, pc_roll["die1"], pc_roll["die2"], pc_mod, pc_prof, pc_total, stats.poisoned_condition_save_dc, int(pc_pass),
				int(pc_roll["lucky1"]), int(pc_roll["lucky2"]), pc_exh]
			if pc_pass:
				GameState.game_log("[color=lime]You [url=%s]fight off[/url] the venom![/color]" % pc_meta)
				stats.poisoned_condition_turns = 0
				stats.poisoned_condition_save_dc = 0
				GameState.player_status_changed.emit()
			else:
				GameState.game_log("[color=gray]You [url=%s]remain poisoned[/url].[/color]" % pc_meta)
		# Infernal Wound (Bearded Devil's Glaive attack): infernal_wound_dice d10 Necrotic at
		# the start of every real turn while active — see Stats.infernal_wound_active's own
		# comment for how it ends (any healing, GameState.heal()'s tail). Same BUGFIX dedent as
		# the Poisoned repeated-save block above — this used to only tick while also frightened.
		if stats.infernal_wound_active:
			var iw_rolls: Array[int] = Rng.roll_dice(stats.infernal_wound_dice, 10)
			var iw_inst: Dictionary = CombatMath.build_damage_instance(iw_rolls, 10, [], false, "Necrotic")
			var iw_actual: int = GameState.take_damage_raw(iw_inst["subtotal"], false, "Necrotic")
			iw_inst["final"] = iw_actual
			GameState.flush_stone_endurance_log()
			GameState.flush_deflect_attacks_log()
			if _dungeon_floor != null:
				_dungeon_floor.show_damage(position, iw_actual, true, CombatMath.damage_type_color("Necrotic"))
			var iw_meta: String = CombatMath.encode_damage_instance(iw_inst)
			GameState.game_log("[color=orange]The infernal wound tears at you for [url=%s][color=yellow]%d[/color][/url] Necrotic dmg.[/color]" % [iw_meta, iw_actual])
		# Paralyzed: repeats a save (Stats.paralyze_save_stat, default CON) once per real turn to
		# end early — mirrors Frightened's own repeated-save shape above, deliberately its OWN
		# top-level check (not nested under the frightened_turns branch above) so it fires
		# regardless of whether the player also happens to be frightened. See Stats.paralyzed_turns'
		# own comment / scripts/entities/CLAUDE.md's "Conditions" table (Paralyzed row) — mirrors
		# Enemy's own Hold Person-driven Paralyzed repeated save (Enemy.decide_turn()).
		if stats.paralyzed_turns > 0:
			var pz_stat: String = stats.paralyze_save_stat
			var pz_mod: int
			var pz_prof_ok: bool
			match pz_stat:
				"str": pz_mod = stats.str_modifier(); pz_prof_ok = stats.check_prof_str
				"dex": pz_mod = stats.dex_modifier(); pz_prof_ok = stats.check_prof_dex
				"int": pz_mod = stats.int_modifier(); pz_prof_ok = stats.check_prof_int
				"wis": pz_mod = stats.wis_modifier(); pz_prof_ok = stats.check_prof_wis
				"cha": pz_mod = stats.cha_modifier(); pz_prof_ok = stats.check_prof_cha
				_:    pz_mod = stats.con_modifier(); pz_prof_ok = stats.check_prof_con
			var pz_prof: int = stats.proficiency_bonus if pz_prof_ok else 0
			var pz_roll: Dictionary = CombatMath.roll_with_adv_disadv(0, 0)
			var pz_die: int = pz_roll["die"]
			var pz_exh: int = CombatMath.exhaustion_penalty()
			var pz_total: int = pz_die + pz_mod + pz_prof + pz_exh
			var pz_pass: bool = pz_total >= stats.paralyze_save_dc
			var pz_meta: String = "save:die=%d,d1=%d,d2=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=%s,pass=%d,adv=0,disadv=0,lucky1=%d,lucky2=%d,exh=%d" % [
				pz_die, pz_roll["die1"], pz_roll["die2"], pz_mod, pz_prof, pz_total, stats.paralyze_save_dc, pz_stat.to_upper(), int(pz_pass),
				int(pz_roll["lucky1"]), int(pz_roll["lucky2"]), pz_exh]
			if pz_pass:
				GameState.game_log("[color=lime]You [url=%s]shake off[/url] the paralysis![/color]" % pz_meta)
				GameState.clear_player_paralyzed()
			else:
				GameState.game_log("[color=gray]You [url=%s]remain paralyzed[/url].[/color]" % pz_meta)
				stats.paralyzed_turns -= 1
				if stats.paralyzed_turns <= 0:
					GameState.clear_player_paralyzed()
		# Torch: 600-turn duration per lit torch, ticked once per real turn — regardless of
		# where it currently is (equipped, quickbar/bag, floor, or embedded in an enemy). Equipped
		# slots + quickbar/bag are swept here (GameState-only data); floor items and enemy-embedded
		# items are swept by DungeonFloor.tick_torches() (needs _floor_items/get_all_enemies()).
		for _torch_slot: String in ["melee", "hand2"]:
			var _torch: Item = GameState.equipment.get(_torch_slot) as Item
			if _torch != null and _torch.is_torch and _torch.torch_lit:
				_torch.torch_turns_remaining -= 1
				if _torch.torch_turns_remaining <= 0:
					GameState.burn_out_torch(_torch)
		for _qb_item: Variant in GameState.player_quickbar:
			if _qb_item is Item and _qb_item.is_torch and _qb_item.torch_lit:
				_qb_item.torch_turns_remaining -= 1
				if _qb_item.torch_turns_remaining <= 0:
					GameState.burn_out_torch(_qb_item)
		for _bag_item: Variant in GameState.player_inventory:
			if _bag_item is Item and _bag_item.is_torch and _bag_item.torch_lit:
				_bag_item.torch_turns_remaining -= 1
				if _bag_item.torch_turns_remaining <= 0:
					GameState.burn_out_torch(_bag_item)
		if _dungeon_floor != null:
			_dungeon_floor.tick_torches()
			# The player's own "standing on a burning door/grass tile" damage MUST be checked
			# BEFORE tick_burning_props() below — that call can destroy the very door/finish
			# burning the very grass tile the player is standing on this same tick (its own 2d4
			# HP-loss roll, or _tick_burning_grass()'s one-round expiry), which would silently
			# rob the player of their last tick of damage if checked afterward. Enemy/Companion
			# each do the equivalent check for themselves at the top of their own decide_turn(),
			# which always runs later in the round than this, so they don't share this ordering
			# concern the same way.
			_dungeon_floor.tick_fire_damage_for(self)
			# Barrel/door burn-down + fire-propagation-between-props, at the start of the round
			# (see DungeonFloor.tick_burning_props()'s own doc comment for why this moved off
			# player_turn_ending).
			_dungeon_floor.tick_burning_props()
	GameState.ability_bar_changed.emit()
	# Natural Sleeper R2: 2d6 temp HP (replace, not stack) if standing in form's terrain.
	# Only fires on real turns, not on reverted turns.
	if not came_from_revert and GameState.wild_heart_sleeper_active:
		var _ns_rank_ts: int = GameState.get_talent_rank("expanded_forms")
		if _ns_rank_ts >= 2 and _dungeon_floor != null:
			var _af: String = GameState.active_sleeper_form
			var _ct: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
			var _terrain_match: bool = (
				(_af == "Panther" and _ct == DungeonData.TileType.MUD) or
				(_af == "Salmon" and _ct == DungeonData.TileType.WATER) or
				(_af == "Owl" and _ct == DungeonData.TileType.CHASM)
			)
			if _terrain_match:
				var _thp: int = Rng.roll(6) + Rng.roll(6)
				GameState.player_stats.temp_hp = _thp  # replace, not stack
				GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
				GameState.game_log("[color=cyan]%s Form: %d temp HP (2d6).[/color]" % [_af, _thp])

	# Bloodied Regen (Scarred Warrior): temp HP each real turn while Bloodied.
	if not came_from_revert:
		_scarred_warrior.tick_bloodied_regen()

	# Animal Form: per-step switch transition (GameState.start_animal_form_switch(), 1 real turn
	# per cycle step), ticked once per real turn only. Refresh fog if it just completed — Eagle's
	# FOV bonus may have changed.
	if not came_from_revert and GameState._tick_animal_form_transition() and _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)

	# Ironwood Bark R2/R3: mutually exclusive per turn — both ranks read the SAME pre-turn
	# temp HP snapshot, so R2's refresh this tick cannot also trigger R3 this same tick.
	_ironwood_bark_bonus_pending = 0
	if not came_from_revert:
		var _ib_rank: int = GameState.get_talent_rank("ironwood_bark")
		if _ib_rank >= 2 and _is_raging:
			var _ib_snapshot_thp: int = GameState.player_stats.temp_hp
			if _ib_snapshot_thp == 0:
				var _ib_thp: int = Rng.roll(6) * GameState.player_stats.rage_bonus_damage
				GameState.player_stats.temp_hp = _ib_thp
				GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
				GameState.game_log("[color=cyan]Ironwood Bark: %d temp HP (1d6 × rage bonus).[/color]" % _ib_thp)
			elif _ib_rank >= 3:
				_ironwood_bark_bonus_pending = _ib_snapshot_thp
	# Refresh visibility after enemy turns, then snapshot FOV
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
		_fov_prev_turn = _fov_this_turn
		_fov_this_turn = _dungeon_floor.get_visible_enemies()

	# Interrupt-baseline bookkeeping: captured once, the first turn any of the three multi-turn
	# actions below is active; cleared the instant none of them are (so the NEXT such action starts
	# its own fresh baseline). See the field comment above for the tolerance rule this backs.
	var _interrupt_action_active: bool = GameState.short_rest_active or GameState.armor_change_active or GameState.scroll_learn_active
	if _interrupt_action_active:
		if not _interrupt_baseline_set:
			_interrupt_baseline.clear()
			for e: Enemy in _fov_this_turn:
				_interrupt_baseline[e] = e.grid_pos
			_interrupt_baseline_set = true
	else:
		_interrupt_baseline_set = false
		_interrupt_baseline.clear()

	# Tick rage duration. Baseline: lasts 1 turn, refreshed to 1 turn by attacking (hit or miss)
	# or being attacked (hit or miss) last turn (Masochist Monster R3 can further override expiry
	# — see below). Gated on real turns only — a reverted/free-action turn (Frenzy, Battlefield
	# Expert's free side-step) hasn't actually let a round pass, so it must never tick Rage down
	# or count as "no combat this turn".
	if _is_raging and not came_from_revert:
		var combat_last_turn: bool = _rage_attacked_this_turn or GameState.player_was_hit_this_turn or GameState.player_attacked_this_turn
		var masochist_r3_active: bool = GameState.get_talent_rank("masochist_monster") >= 3 \
				and not _fov_this_turn.is_empty()
		if masochist_r3_active:
			pass  # Masochist Monster R3: Rage doesn't expire while an enemy is in FOV
		elif combat_last_turn:
			_rage_turns = 1
		else:
			_rage_turns -= 1
		GameState.rage_turns_remaining = _rage_turns
		GameState.ability_bar_changed.emit()
		if _rage_turns <= 0:
			_end_rage()
			GameState.game_log("[color=gray]Your Rage fades.[/color]")
	# Cleared once per real turn regardless of Rage state, so Battlefield Expert R3's "was hit
	# last turn" check (read further up) stays scoped to "last turn" instead of leaking true
	# forever after the first hit of the run.
	if not came_from_revert:
		# Snapshot before clearing — chase-to-attack (_execute_queued_path()) reads this after
		# the round to know an enemy noticed/attacked the player (hit or miss) mid-chase.
		_enemy_attacked_last_round = GameState.player_attacked_this_turn
		_enemy_noticed_last_round = GameState.enemy_noticed_player_this_turn
		_rage_attacked_this_turn = false
		GameState.player_was_hit_this_turn = false
		GameState.player_attacked_this_turn = false
		GameState.enemy_noticed_player_this_turn = false

	# Short rest in progress — player waits in place
	if GameState.short_rest_active:
		if GameState.short_rest_open:
			return  # Panel open — freeze until player clicks Continue/Abort
		if _rest_interrupted() and not _rest_interrupt_shown:
			_rest_interrupt_shown = true
			GameState.short_rest_open = true
			var panel_script = load("res://scripts/ui/rest_interrupt_panel.gd")
			get_tree().root.call_deferred("add_child", panel_script.new())
			_actions.do_rest_wait_turn()
			return
		GameState.short_rest_turns_remaining -= 1
		if GameState.short_rest_turns_remaining <= 0:
			GameState.short_rest_active = false
			_rest_interrupt_shown = false
			if GameState.long_rest_pending:
				GameState.long_rest_pending = false
				GameState.short_rest_pending_heal = 0
				GameState.long_rest()
				GameState.mastery_picker_open = true
				var prompt_script = load("res://scripts/ui/mastery_reselect_prompt.gd")
				get_tree().root.call_deferred("add_child", prompt_script.new())
			else:
				var pending_heal: int = GameState.short_rest_pending_heal
				var pending_rolls: Array[int] = GameState.short_rest_pending_heal_rolls
				GameState.short_rest_pending_heal = 0
				GameState.short_rest_pending_heal_rolls = []
				var before_hp: int = GameState.player_stats.current_hp
				var bruiser_bonus: int = GameState.heal(pending_heal)
				var healed: int = GameState.player_stats.current_hp - before_hp
				AudioManager.play("rest")
				var bonus_sources: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus, "color": "cyan"}])
				var con_mod: int = GameState.player_stats.con_modifier()
				var rolls_str: String = "|".join(pending_rolls.map(func(x: int) -> String: return str(x)))
				var _hm: String = "heal:dice=%d,sides=%d,con=%d,rolls=%s,bonus=%s,total=%d" % [pending_rolls.size(), GameState.hit_die_sides(), con_mod, rolls_str, bonus_sources, healed]
				GameState.game_log("[color=cyan]You finish your short rest and recover [url=%s][b]+%d HP[/b][/url].[/color]" % [_hm, healed])
				GameState.short_rest_completed.emit()
			GameState.short_rest_changed.emit()
		_actions.do_rest_wait_turn()
		return

	# Armor change (equip/unequip/swap of body armor) in progress — player waits in place, same
	# auto-wait/interrupt shape as scroll-learning below (no Continue/Abort prompt — nothing's
	# physically moved yet, just re-issue the equip/unequip once it's safe again).
	if GameState.armor_change_active:
		if _rest_interrupted():
			GameState.cancel_armor_change(true)
			return
		GameState.armor_change_turns_remaining -= 1
		if GameState.armor_change_turns_remaining <= 0:
			GameState.complete_armor_change()
		_actions.do_rest_wait_turn()
		return

	# Scroll-learning in progress — player waits in place, same auto-wait/interrupt shape as a
	# short rest but its own independent flag (not a rest). _rest_interrupted() interrupts the
	# studying outright (no Continue/Abort prompt — nothing's been consumed yet, just re-issue the
	# RMB Learn command once it's safe again).
	if GameState.scroll_learn_active:
		if _rest_interrupted():
			GameState.cancel_scroll_learn(true)
			return
		GameState.scroll_learn_turns_remaining -= 1
		if GameState.scroll_learn_turns_remaining <= 0:
			GameState.complete_scroll_learn()  # logs "You add X to your spellbook." via learn_spell()
		_actions.do_rest_wait_turn()
		return

	var status_dmg: int = GameState.player_stats.tick_status()
	if status_dmg > 0:
		GameState.take_damage_raw(status_dmg)
		GameState.flush_stone_endurance_log()
		GameState.flush_deflect_attacks_log()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(position, status_dmg, true)
		GameState.player_status_changed.emit()

	# Difficult terrain status-tray flag: recomputed live from the CURRENT tile every turn-start
	# (moved or waited, real or reverted) instead of riding Stats.slowed_turns' decaying counter —
	# see GameState.player_on_difficult_terrain's comment for why.
	if _dungeon_floor != null:
		var _dt_tile: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
		var _dt_difficult: bool = _dt_tile == DungeonData.TileType.WATER or _dt_tile == DungeonData.TileType.MUD
		if _dt_difficult:
			var _dt_ns_rank: int = GameState.get_talent_rank("expanded_forms")
			var _dt_sleeper_on: bool = GameState.wild_heart_sleeper_active and _dt_ns_rank >= 1
			var _dt_ns_form: String = GameState.active_sleeper_form
			var _dt_panther_bypass: bool = _dt_sleeper_on and _dt_ns_form == "Panther" and _dt_tile == DungeonData.TileType.MUD
			var _dt_salmon_bypass: bool = _dt_sleeper_on and _dt_ns_form == "Salmon" and _dt_tile == DungeonData.TileType.WATER
			var _dt_trailblazer_bypass: bool = GameState.get_talent_rank("trailblazer") >= 1
			var _dt_flying_bypass: bool = GameState.player_stats.draconic_flight_turns > 0
			_dt_difficult = not _dt_panther_bypass and not _dt_salmon_bypass and not _dt_trailblazer_bypass and not _dt_flying_bypass
		if _dt_difficult != GameState.player_on_difficult_terrain:
			GameState.player_on_difficult_terrain = _dt_difficult
			GameState.player_status_changed.emit()

# Witch Bolt's per-turn jolt fires at the END of the player's turn (TurnManager.player_turn_ending,
# right before enemies act), not the start of the next one — matches the user-facing framing "the
# bolt strikes at the end of your turn". `witch_bolt_just_cast` skips the very first firing (the
# cast's own action-complete), so the first automatic 1d12 lands at the end of the turn AFTER the
# casting turn, not the casting turn itself.
func _on_turn_ending() -> void:
	_resolve_stealth_check()
	# Rage house-rule (Bonus Action economy, scripts/entities/CLAUDE.md): a leftover, unused Bonus
	# Action at the end of a real turn automatically extends Rage — on top of (not replacing) the
	# existing "attack or be attacked" trigger the _on_turn_started() rage-tick block reads.
	# _on_turn_ending() only ever fires on a real (non-reverted) turn (TurnManager.player_turn_ending's
	# own contract), so no extra revert guard is needed here.
	if _is_raging and not GameState.bonus_action_used:
		_rage_attacked_this_turn = true
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
		GameState.game_log("[color=gray]Your leftover bonus action keeps the Rage going.[/color]")
	var stats: Stats = GameState.player_stats
	if stats.witch_bolt_turns <= 0:
		return
	if stats.witch_bolt_just_cast:
		stats.witch_bolt_just_cast = false
		return
	var wb_target: Enemy = stats.witch_bolt_target
	if is_instance_valid(wb_target) and not wb_target.stats.is_dead():
		SpellEffects.tick_witch_bolt(self, wb_target, _dungeon_floor)
	stats.witch_bolt_turns -= 1
	var wb_still_alive: bool = is_instance_valid(wb_target) and not wb_target.stats.is_dead()
	if stats.witch_bolt_turns <= 0 or not wb_still_alive:
		stats.witch_bolt_turns = 0
		stats.witch_bolt_target = null
		if stats.concentration_spell_id == "witch_bolt":
			stats.concentration_spell_id = ""
		GameState.game_log("[color=gray]Witch Bolt fades.[/color]")

# Whether a multi-turn action (short rest / armor change / scroll learn) should be interrupted
# THIS turn — see _interrupt_baseline's field comment. An enemy that was already visible and
# unaware when the action began, and hasn't moved since, is tolerated; a currently-hunting
# (CHASING/SEARCHING) enemy always interrupts (whether baseline or freshly noticed — a freshly
# noticed one flips to CHASING via _notice_target() the same turn _resolve_stealth_check() catches
# it, so this naturally covers "the sleeper woke up" too, no separate behavior-change tracking
# needed).
# Ritual spellcasting's "not being pursued" gate (Spell.is_ritual — see spell.gd's own comment):
# true if ANY live enemy on the current floor is currently CHASING/SEARCHING, floor-wide (not just
# _fov_this_turn — an enemy hunting you from just out of sight still counts as "pursued").
func is_being_pursued() -> bool:
	if _dungeon_floor == null:
		return false
	for e: Enemy in _dungeon_floor.get_all_enemies():
		if is_instance_valid(e) and not e.stats.is_dead() and e.behavior in [Enemy.Behavior.CHASING, Enemy.Behavior.SEARCHING]:
			return true
	return false

func _rest_interrupted() -> bool:
	for e: Enemy in _fov_this_turn:
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if e.behavior in [Enemy.Behavior.CHASING, Enemy.Behavior.SEARCHING]:
			return true
		if not _interrupt_baseline.has(e):
			return true
		if e.grid_pos != _interrupt_baseline[e]:
			return true
	return false

# Stealth check vs Passive Perception (docs/architecture/stealth-and-surprise-attacks-design.md
# §3): rolled once per REAL player turn (this fires from player_turn_ending, exactly once per
# non-reverted action), reused against every currently-unaware enemy in FOV. Skipped entirely on
# an attack/spell turn (the attacked enemy already got on_disturbed() at the attack call site —
# a second roll against it would be pointless) and on noclip. Detection happens BEFORE the
# player's next action, so a just-detected enemy never grants surprise ADV on that next attack.
func _resolve_stealth_check() -> void:
	var skip: bool = GameState.stealth_check_skip
	var stillness: bool = GameState.stealth_check_stillness
	GameState.stealth_check_skip = false
	GameState.stealth_check_stillness = false
	# Invisibility ends the instant an attack or spell-cast turn happens (5e RAW) — `skip` IS
	# exactly that same "this turn was an attack/spell-cast" signal every attack/cast call site
	# already sets right before its own begin_player_action() call.
	if skip and stats.invisibility_turns > 0:
		if stats.invisibility_just_cast:
			stats.invisibility_just_cast = false
		else:
			stats.invisibility_turns = 0
			if stats.concentration_spell_id == "invisibility":
				stats.concentration_spell_id = ""
			GameState.game_log("[color=purple]Your Invisibility ends.[/color]")
			_update_invisibility_visual()
	if skip or GameState.noclip or _dungeon_floor == null:
		return
	var observers: Array[Enemy] = []
	for e: Enemy in _dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if e.behavior not in [Enemy.Behavior.SLEEPING, Enemy.Behavior.STATIONARY, Enemy.Behavior.ROAMING]:
			continue
		if e.can_see(self):
			observers.append(e)
	if observers.is_empty():
		return
	var s: Stats = GameState.player_stats
	var dex_mod: int = s.dex_modifier()
	var prof: int = s.proficiency_bonus if s.check_prof_dex else 0
	var base_adv: int = 0
	if stillness:
		base_adv += 1
	if s.zealous_presence_turns > 0:
		base_adv += 1
	var base_disadv: int = 1 if GameState.player_has_stealth_disadvantage() else 0
	# Rolled once, reused against every observer (5e group-stealth style) — but ADV/DISADV is a
	# property of the roll against THAT specific target (SLEEPING grants +1 net ADV, per-observer),
	# so a second d20 is only rolled when a given observer's own net ADV/DISADV differs from 0.
	var r1: Dictionary = CombatMath.halfling_reroll(Rng.roll(20))
	var die1: int = r1["value"]
	var lucky1: bool = r1["lucky"]
	# Heroic Inspiration: consumed once for this whole check (not per-observer) — forces every
	# observer's resolved die to a natural 20, guaranteeing you stay hidden from all of them.
	var heroic: bool = CombatMath.consume_heroic_inspiration()
	for e: Enemy in observers:
		# Baseline is a NORMAL roll (no ADV/DISADV) against an awake-but-unaware observer
		# (STATIONARY/ROAMING) — ADV only ever comes from an explicit source (SLEEPING's own +1,
		# stillness, Zealous Presence), DISADV only from an explicit source (stealth-disadvantage
		# armor). SLEEPING is easier to sneak past than baseline (+1 ADV); STATIONARY/ROAMING gets
		# no penalty of its own anymore — distance-to-DC (below) is what makes an awake observer
		# harder to sneak past up close, not a flat DISADV term.
		var obs_net: int = base_adv + (1 if e.behavior == Enemy.Behavior.SLEEPING else 0) - base_disadv
		var die: int = die1
		var die2: int = die1
		var lucky2: bool = false
		if obs_net != 0:
			var r2: Dictionary = CombatMath.halfling_reroll(Rng.roll(20))
			die2 = r2["value"]
			lucky2 = r2["lucky"]
			die = maxi(die1, die2) if obs_net > 0 else mini(die1, die2)
		if heroic:
			die = 20
		var stealth_exh: int = CombatMath.exhaustion_penalty()
		var total: int = die + dex_mod + prof + stealth_exh
		# Pass Without Trace (Wood Elf/Ranger spell) and Minor Illusion (Forest Gnome lineage
		# cantrip) both grant a flat bonus to the stealth roll while active — stbonus/stbonus_id
		# below carry whichever is active into the tooltip breakdown (fmt_stealth_tooltip()),
		# which used to silently fold this into `total` with no visible line explaining the gap
		# between die+dex+prof and the shown total.
		var stbonus: int = 0
		var stbonus_id: int = 0
		if stats.pass_without_trace_turns > 0:
			total += Stats.PASS_WITHOUT_TRACE_BONUS
			stbonus += Stats.PASS_WITHOUT_TRACE_BONUS
			stbonus_id = 1
		if stats.minor_illusion_turns > 0:
			total += Stats.MINOR_ILLUSION_BONUS
			stbonus += Stats.MINOR_ILLUSION_BONUS
			stbonus_id = 2 if stbonus_id == 0 else 3
		# Distance-to-DC bonus: the closer you are relative to THIS enemy's own sight range
		# (darkvision etc. included), the harder you are to miss — +1 DC per tile closer than its
		# FOV edge, capped at 0 for anything at or beyond max sight range. Chebyshev, matching
		# every other adjacency/range check in this file. Replaces the old flat true-adjacency
		# auto-notice (see enemy.gd's SLEEPING/STATIONARY/ROAMING vs-Player branches) — standing
		# next to an unaware enemy is now just a very hard check, not an automatic notice.
		var e_sight_range: int = e.sight_range()
		var e_dist: int = e.min_dist_to(grid_pos)
		var dist_bonus: int = maxi(0, e_sight_range - e_dist)
		# Bloodhound R2: the Marked target is easier for the player specifically to sneak up on.
		var effective_pp: int = e.passive_perception + dist_bonus
		if e == s.hunters_mark_target and GameState.get_talent_rank("bloodhound") >= 2:
			effective_pp -= BLOODHOUND_R2_PP_DEBUFF
		var noticed: bool = total < effective_pp
		var stealth_meta: String = "stealth:die=%d,d1=%d,d2=%d,dex=%d,prof=%d,total=%d,epp=%d,basepp=%d,distbonus=%d,adv=%d,pass=%d,lucky1=%d,lucky2=%d,stbonus=%d,stbonusid=%d,exh=%d" % [
			die, die1, die2, dex_mod, prof, total, effective_pp, e.passive_perception, dist_bonus,
			signi(obs_net), 0 if noticed else 1, 1 if lucky1 else 0, 1 if lucky2 else 0, stbonus, stbonus_id, stealth_exh]
		var god_suffix: String = " [color=gray](Stealth %d vs PP %d)[/color]" % [total, e.passive_perception] if GameState.god_mode else ""
		if noticed:
			e._notice_target(grid_pos)
			GameState.game_log("[color=tomato]%s[/color] [url=%s]notices[/url] you!%s" % [e.display_name, stealth_meta, god_suffix])
		elif GameState.debug_show_all_checks:
			GameState.game_log("[color=gray][url=%s]Player vs %s: stealth check (not noticed)[/url]%s[/color]" % [stealth_meta, e.display_name, god_suffix])

# Purely cosmetic — the actual "can't be seen" mechanic is Enemy._can_see_entity()'s invisibility
# check, not this. Translucent tint so the PLAYER can still tell their own state at a glance.
func _update_invisibility_visual() -> void:
	$AnimatedSprite2D.modulate.a = 0.4 if stats.invisibility_turns > 0 else 1.0

# Small sparkle shown above the player while outlined by Faerie Fire — mirrors Enemy's own
# _faerie_fire_indicator/_refresh_faerie_fire_visual() exactly (scripts/entities/enemy.gd), so the
# player gets the same visible feedback an outlined enemy already had. Bugfix: casting Faerie Fire
# on yourself correctly set Stats.faerie_fire_outlined_turns (granting enemies Advantage against
# you) but had no matching visual — no status-tray icon and no above-character marker — so nothing
# on screen ever showed it took effect.
var _faerie_fire_indicator: Label

func _setup_faerie_fire_indicator() -> void:
	_faerie_fire_indicator = Label.new()
	_faerie_fire_indicator.text = "✦"
	_faerie_fire_indicator.add_theme_font_size_override("font_size", 14)
	_faerie_fire_indicator.position = Vector2(6, -24)
	_faerie_fire_indicator.z_index = 10
	_faerie_fire_indicator.visible = false
	add_child(_faerie_fire_indicator)

func _refresh_faerie_fire_visual() -> void:
	if not is_instance_valid(_faerie_fire_indicator):
		return
	_faerie_fire_indicator.visible = stats.faerie_fire_outlined_turns > 0
	if stats.faerie_fire_outlined_turns > 0:
		_faerie_fire_indicator.add_theme_color_override("font_color", stats.faerie_fire_outlined_color)

func _setup_animations() -> void:
	var char_folder: String
	match GameState.player_stats.character_class:
		Stats.CharacterClass.RANGER:  char_folder = "Ranger"
		Stats.CharacterClass.WIZARD:  char_folder = "Wizard"
		Stats.CharacterClass.MONK:    char_folder = "Monk"
		Stats.CharacterClass.WARLOCK: char_folder = "Warlock"
		_:                            char_folder = "Barbarian"   # BARBARIAN default
	var base: String = KNIGHT_PATH + char_folder + "/"
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", base + "idle_%d.png", 4, true,  8.0)
	_add_anim(frames, "run",  base + "run_%d.png",  4, false, 16.0)
	# Barbarian/Ranger's hit_1.png is a carried-over placeholder from their pre-swap art (the
	# sourced idle/run packs shipped no matching hit frame) — it visibly mismatches the new
	# idle/run sprites, so until real art exists these two classes play a static idle frame
	# instead (no swing animation) rather than flashing the wrong-looking sprite.
	var has_real_hit_art: bool = char_folder in ["Wizard", "Monk"]
	_add_anim(frames, "hit",  base + (("hit" if has_real_hit_art else "idle") + "_%d.png"), 1, false, 8.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -11)
	$AnimatedSprite2D.play("idle")

# Filenames are 1-indexed (idle_1.png, idle_2.png, ...), not 0-indexed.
func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i: int in count:
		frames.add_frame(anim_name, load(path_fmt % (i + 1)))

# Cardinal + diagonal movement via per-frame key sampling so two held cardinals = diagonal
func _process(_delta: float) -> void:
	_update_hover_indicator()
	var spell_preview_active: bool = _update_spell_aoe_preview()
	var ranged_preview_active: bool = _update_ranged_range_preview()
	if _dungeon_floor != null:
		_dungeon_floor.set_fov_bonus_overlay_suppressed(spell_preview_active or ranged_preview_active)
	if (GameState.is_game_over or GameState.is_dying) or GameState.inventory_open or GameState.short_rest_open \
			or GameState.subclass_picker_open or GameState.race_picker_open or GameState.point_buy_open \
			or GameState.background_select_open or GameState.blacksmith_panel_open or GameState.shop_open \
			or GameState.invocation_picker_open \
			or not GameState.class_selected:
		_prev_dir = Vector2i.ZERO
		_last_move_dir = Vector2i.ZERO
		_interrupted = false
		_wait_held_active = false
		_wait_interrupted = false
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		_last_move_dir = Vector2i.ZERO
		_wait_held_active = false
		return
	var dx: int = 0
	var dy: int = 0
	if Input.is_physical_key_pressed(KEY_UP)    or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_KP_8): dy -= 1
	if Input.is_physical_key_pressed(KEY_DOWN)  or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_KP_2): dy += 1
	if Input.is_physical_key_pressed(KEY_LEFT)  or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_KP_4): dx -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_KP_6): dx += 1
	var dir := Vector2i(dx, dy)
	if dir == Vector2i.ZERO:
		_prev_dir = Vector2i.ZERO
		_last_move_dir = Vector2i.ZERO
		_interrupted = false
		# No movement key held — a stale trap-alert from a single-tap move that already ended on
		# its own (never got the chance to interrupt a hold) must not leak into the next,
		# unrelated key press.
		_trap_alert = false
		if Input.is_physical_key_pressed(KEY_SPACE):
			_handle_space_hold()
		else:
			_wait_held_active = false
			_wait_interrupted = false
		return
	if _prev_dir == Vector2i.ZERO:
		_interrupted = false
	elif _interrupted:
		# Key still physically held after interrupt — block until finger lifted
		_prev_dir = dir
		return
	elif not GameState.noclip and (not _fov_this_turn.is_empty() or _trap_alert):
		# Any enemy visible, or a trap was just discovered — interrupt hold movement
		_interrupted = true
		_trap_alert = false
		_prev_dir = dir
		return
	_prev_dir = dir
	if dir == _last_move_dir:
		return
	_last_move_dir = dir
	_queued_path.clear()
	if _throw_item != null:
		_throw_item = null
		GameState.game_log("[color=gray]Throw cancelled.[/color]")
	# Thief Tools: let _try_move handle door/trap bump — don't cancel the tool here.
	if _tool_item != null and _tool_item.item_name != "Thief Tools":
		_tool_item = null
		GameState.game_log("[color=gray]Disarm cancelled.[/color]")
	# Moving cancels an armed spell/scroll cast — same as Esc (scripts/entities/CLAUDE.md's
	# "Wizard leveled spells" targeting flow).
	if _spellcasting.spell_targeting_active:
		_spellcasting.cancel()
		GameState.game_log("[color=gray]Spell cancelled.[/color]")
	_dragonborn.cancel_breath_weapon()
	_aasimar.cancel_healing_hands()
	if _goliath.cloud_teleport_mode_active:
		_goliath.cloud_teleport_mode_active = false
		GameState.game_log("[color=gray]Cloud Giant teleport cancelled.[/color]")
	# Adrenaline Rush dash: let _try_move handle a WASD direction as the dash's own target — same
	# "don't cancel here, resolve in _try_move" pattern as Thief Tools above.
	if _halfling.nimbleness_mode_active:
		_halfling.cancel()
		GameState.game_log("[color=gray]Nimbleness cancelled.[/color]")
	_try_move(dir)

# Holding Space repeats a single wait_action() per real turn for as long as it's held down —
# called from _process() only while no movement key is held (dir == Vector2i.ZERO).
func _handle_space_hold() -> void:
	if _wait_interrupted:
		# Key still physically held after interrupt — block until finger lifted
		return
	if not GameState.noclip and not _fov_this_turn.is_empty():
		_wait_interrupted = true
		return
	if _wait_held_active:
		return
	_wait_held_active = true
	_actions.wait_action()

func _ensure_hover_indicator() -> void:
	if _hover_indicator != null and is_instance_valid(_hover_indicator):
		return
	if _dungeon_floor == null:
		return
	_hover_indicator = Sprite2D.new()
	_hover_indicator.z_index = 12
	_hover_indicator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hover_indicator.scale = Vector2(0.75, 0.75)
	_hover_indicator.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_hover_indicator.visible = false
	_dungeon_floor.add_child(_hover_indicator)

func _update_hover_indicator() -> void:
	_ensure_hover_indicator()
	if _hover_indicator == null or _dungeon_floor == null:
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing \
			or GameState.short_rest_open or GameState.inventory_open or (GameState.is_game_over or GameState.is_dying) \
			or GameState.blacksmith_panel_open or GameState.shop_open:
		_hover_indicator.visible = false
		return
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var enemy: Enemy = _dungeon_floor.get_targetable_enemy_at(tile)
	if enemy == null or not is_instance_valid(enemy):
		_hover_indicator.visible = false
		return
	# Blind-firing into an unseen tile must still work (see click handlers below), but the icon
	# itself would give away a hidden enemy's exact position — only show it when at least one of
	# the enemy's occupied tiles is actually in the player's current FOV.
	var enemy_seen: bool = false
	for occ_tile: Vector2i in enemy.occupied_tiles():
		if _dungeon_floor.is_tile_visible(occ_tile):
			enemy_seen = true
			break
	if not enemy_seen:
		_hover_indicator.visible = false
		return
	# Priority mirrors the LMB click handler's own dispatch order: Alt+Special-slot spell wins
	# over Shift+Ranged, which wins over the default melee weapon.
	var icon_path: String = ""
	if Input.is_key_pressed(KEY_ALT) and GameState.special_slot_spell_id != "":
		var spell: Spell = SpellDb.get_spell(GameState.special_slot_spell_id)
		if spell != null:
			icon_path = spell.icon_path
	elif Input.is_key_pressed(KEY_SHIFT):
		var ranged: Item = GameState.equipped_ranged
		if ranged != null:
			icon_path = ranged.icon_path
	else:
		var weapon: Item = GameState.equipped_weapon
		if weapon != null:
			icon_path = weapon.icon_path
	if icon_path == "":
		_hover_indicator.visible = false
		return
	if icon_path != _hover_last_icon_path:
		_hover_last_icon_path = icon_path
		_hover_last_texture = load(icon_path) as Texture2D
		_hover_indicator.texture = _hover_last_texture
		# Weapon/ranged icons are ~tile-sized source art (fine at the old flat 0.75 scale), but a
		# spell's icon comes from res://icons/spells/ at a much higher native resolution — scale by
		# the texture's own longest side so every icon kind ends up the same on-screen size instead
		# of a spell icon dwarfing the melee/ranged one. Same longest-side-uniform-scale approach as
		# place_item_on_floor() (scripts/world/CLAUDE.md's "Floor items").
		if _hover_last_texture != null:
			var tex_size: Vector2 = _hover_last_texture.get_size()
			var longest_side: float = maxf(tex_size.x, tex_size.y)
			var s: float = HOVER_ICON_TARGET_PX / longest_side if longest_side > 0.0 else 0.75
			_hover_indicator.scale = Vector2(s, s)
	_hover_indicator.global_position = enemy.global_position + Vector2(6, -14)
	_hover_indicator.visible = true

# Dynamic tile-tint preview while a spell is armed for targeting — see dungeon_floor.gd's "AoE
# targeting preview" section. A blue "maximum reach" backdrop shows for ANY armed spell (single-
# target or AoE); sphere/cone spells additionally get the exact purple/red footprint preview on
# top (red instead of purple on a tile with a known, targetable enemy); a plain single-target
# ENEMY spell (Fire Bolt, Shocking Grasp, ...) gets just the red highlight on the hovered tile,
# with no purple footprint at all, whenever a targetable enemy stands there. The ability-bar
# arm-then-click flow (PlayerSpellcasting.begin_cast()) arms spell_targeting_active for this
# directly; the Alt+click Special-slot one-motion cast never arms it (cast_direct() resolves the
# same frame it's clicked), so while Alt is held with a spell in the Special slot, preview that
# spell instead — same tile-tint, just keyed off the held modifier instead of armed-targeting
# state. Returns whether a preview is actually showing this frame — `_process()` uses this (OR'd
# with `_update_ranged_range_preview()`'s own return) to suppress the torch/darkvision FOV-bonus
# glows so their yellow/gray never visually blends with this preview's blue/purple/red.
func _update_spell_aoe_preview() -> bool:
	if _dungeon_floor == null:
		return false
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing \
			or GameState.short_rest_open or GameState.inventory_open or (GameState.is_game_over or GameState.is_dying) \
			or GameState.blacksmith_panel_open or GameState.shop_open:
		_dungeon_floor.hide_aoe_preview()
		_dungeon_floor.hide_spell_range_preview()
		return false
	var spell: Spell = _spellcasting.get_armed_spell()
	if spell == null and Input.is_key_pressed(KEY_ALT) and GameState.special_slot_spell_id != "":
		spell = SpellDb.get_spell(GameState.special_slot_spell_id)
	if spell == null:
		if _dragonborn.breath_weapon_mode_active:
			return _update_breath_weapon_preview()
		if _halfling.nimbleness_mode_active:
			return _update_nimbleness_preview()
		if _goliath.cloud_teleport_mode_active:
			return _update_cloud_teleport_preview()
		if _orc.dash_mode_active:
			return _update_adrenaline_dash_preview()
		if _monk.step_of_wind_mode_active:
			return _update_step_of_wind_preview()
		if _hunters_mark_mode_active:
			return _update_hunters_mark_preview()
		_dungeon_floor.hide_aoe_preview()
		_dungeon_floor.hide_spell_range_preview()
		return false
	# Blue "maximum reach" backdrop — every tile that could possibly be hit from here, shown for
	# any armed spell (not just AoE shapes). Cone: since its aim is now snapped to only 8 fixed
	# directions (SpellEffects.DIR8), its true max-reach envelope is a finite, exactly computable
	# set — the union of SpellEffects.cone_tiles() over all 8 directions — rather than an
	# approximated disc that either over- or under-represents the wedge's real shape at its tip
	# (bugfix: a circle of radius `length` under-represents it, since a corner tile at
	# forward=length,lateral=1 sits at Euclidean distance sqrt(length²+1) > length; a larger circle
	# then over-represents it elsewhere). Sphere/cube: reach = how far the blast's own center can be
	# placed, plus the blast's own extent (the impact point can land at the edge of range and still
	# splash further out — cube's shape_size is a corner-anchored SIDE LENGTH now, not a radius, so
	# only shape_size-1 extra tiles are actually reachable, not the full shape_size). Everything
	# else (single-target ENEMY/TILE spells): reach = the spell's plain range.
	if spell.shape == "cone":
		var cone_union: Dictionary = {}
		for dir_v: Vector2 in SpellEffects.DIR8:
			var aim: Vector2i = grid_pos + Vector2i(roundi(dir_v.x * 100), roundi(dir_v.y * 100))
			for t: Vector2i in SpellEffects.cone_tiles(grid_pos, aim, spell.shape_size, _dungeon_floor):
				cone_union[t] = true
		# Dictionary.keys() returns a plain untyped Array — show_spell_range_preview_tiles() takes
		# a typed Array[Vector2i], so it must be rebuilt into one explicitly (bugfix: passing the
		# untyped keys() result directly crashed with "does not have the same element type as the
		# expected typed array argument").
		var cone_tiles_typed: Array[Vector2i] = []
		cone_tiles_typed.assign(cone_union.keys())
		_dungeon_floor.show_spell_range_preview_tiles(cone_tiles_typed)
	else:
		# Sphere's shape_size is a real radius (Fireball) — full +shape_size reach. Cube's
		# shape_size is a corner-anchored SIDE LENGTH (Faerie Fire) — only shape_size-1 extra tiles
		# beyond the impact point are actually reachable in any direction, not the full shape_size
		# (bugfix: using the sphere formula for cube overstated its reach, e.g. showing radius 5
		# for a range-3/shape_size-2 spell that can only ever reach out to radius 4).
		var extra: int = spell.shape_size if spell.shape == "sphere" else (spell.shape_size - 1 if spell.shape == "cube" else 0)
		var range_radius: int = spell.range_tiles + extra
		_dungeon_floor.show_spell_range_preview(grid_pos, range_radius, false)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	# Chebyshev distance to the hovered tile vs the spell's own actual castable range — the same
	# check try_cast_at() enforces for real. Gates whether any enemy in the preview is allowed to
	# tint red (see show_aoe_preview()'s/show_single_target_preview()'s own doc comments) — a tile
	# the player couldn't actually cast at never implies "this would hit."
	var d: Vector2i = tile - grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var in_range: bool = dist_cheb <= _spellcasting._effective_range(spell)
	# Magic Missile-style spells need a real walkable path too (see try_cast_at()'s own check) —
	# never preview red on an enemy the dart genuinely couldn't reach, even if it's in range.
	if in_range and spell.bypasses_los:
		in_range = _dungeon_floor.has_walkable_route_ignoring_chasms(grid_pos, tile)
	if spell.target_kind == Spell.TargetKind.TILE and spell.shape == "cone":
		_dungeon_floor.show_cone_preview(grid_pos, tile, spell.shape_size)
	elif spell.target_kind == Spell.TargetKind.TILE and spell.shape in ["sphere", "cube"]:
		_dungeon_floor.show_aoe_preview(tile, spell.shape_size, in_range, spell.shape)
	elif spell.target_kind == Spell.TargetKind.ENEMY:
		_dungeon_floor.show_single_target_preview(tile, in_range)
	elif spell.target_kind == Spell.TargetKind.TILE:
		# No-shape TILE-target spells (Misty Step) — a plain purple highlight on the exact tile
		# the spell would resolve at (e.g. the teleport destination), no enemy required. Previously
		# these fell through to the `else` branch below and got no preview at all.
		_dungeon_floor.show_touch_target_preview(tile, in_range)
	elif spell.target_kind == Spell.TargetKind.SELF and spell.range_tiles > 0:
		# Touch-range SELF spells (Mage Armor, Invisibility) — any click confirms the self-cast
		# regardless of where it lands, so always highlight the caster's OWN tile (not the hovered
		# one) to visually confirm "this resolves on you." range_tiles <= 0 SELF spells (Shield)
		# instant-cast on activation and never reach this function armed, so no branch needed there.
		_dungeon_floor.show_touch_target_preview(grid_pos, true)
	else:
		_dungeon_floor.hide_aoe_preview()
	return true

# Dragonborn Breath Weapon's own targeting preview — mirrors Burning Hands' cone preview exactly
# (blue max-reach backdrop + purple/red exact-footprint highlight), just fed from
# PlayerDragonborn's own armed state (breath_weapon_shape/BREATH_CONE_LENGTH/BREATH_LINE_LENGTH)
# instead of a Spell resource, since Breath Weapon isn't cast through the spell system at all.
# Bugfix: this used to have no preview whatsoever — the only armed ability-bar action with none.
func _update_breath_weapon_preview() -> bool:
	var origin: Vector2i = grid_pos
	if _dragonborn.breath_weapon_shape == "line":
		var length: int = PlayerDragonborn.BREATH_LINE_LENGTH
		var line_union: Dictionary = {}
		for dir_v: Vector2 in SpellEffects.DIR8:
			var aim_dir: Vector2i = origin + Vector2i(roundi(dir_v.x * 100), roundi(dir_v.y * 100))
			for t: Vector2i in PlayerDragonborn._line_tiles(origin, aim_dir, length, _dungeon_floor):
				line_union[t] = true
		var line_tiles_typed: Array[Vector2i] = []
		line_tiles_typed.assign(line_union.keys())
		_dungeon_floor.show_spell_range_preview_tiles(line_tiles_typed)
		var world_mouse: Vector2 = get_global_mouse_position()
		var aim_tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
		_dungeon_floor.show_line_preview(PlayerDragonborn._line_tiles(origin, aim_tile, length, _dungeon_floor))
	else:
		var length: int = PlayerDragonborn.BREATH_CONE_LENGTH
		var cone_union: Dictionary = {}
		for dir_v: Vector2 in SpellEffects.DIR8:
			var aim_dir: Vector2i = origin + Vector2i(roundi(dir_v.x * 100), roundi(dir_v.y * 100))
			for t: Vector2i in SpellEffects.cone_tiles(origin, aim_dir, length, _dungeon_floor):
				cone_union[t] = true
		var cone_tiles_typed: Array[Vector2i] = []
		cone_tiles_typed.assign(cone_union.keys())
		_dungeon_floor.show_spell_range_preview_tiles(cone_tiles_typed)
		var world_mouse2: Vector2 = get_global_mouse_position()
		var aim_tile2: Vector2i = Vector2i(floori(world_mouse2.x / 16.0), floori(world_mouse2.y / 16.0))
		_dungeon_floor.show_cone_preview(origin, aim_tile2, length)
	return true

# Halfling Nimbleness targeting preview — a blue backdrop over the 8 tiles directly adjacent to
# the player (same "maximum reach" convention as a touch spell's own range-1 backdrop), plus a red
# highlight on the hovered tile whenever it holds a targetable enemy LARGER than the Halfling
# (PlayerHalfling.is_larger_than_halfling()) — reuses show_single_target_preview() verbatim, same
# red-means-valid-target convention every other single-target preview uses.
func _update_nimbleness_preview() -> bool:
	var tiles: Array[Vector2i] = _halfling.adjacent_tiles()
	_dungeon_floor.show_spell_range_preview_tiles(tiles)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var target: Enemy = _dungeon_floor.get_targetable_enemy_at(tile)
	var valid: bool = tile in tiles and target != null and PlayerHalfling.is_larger_than_halfling(target)
	_dungeon_floor.show_single_target_preview(tile, valid)
	return true

# Cloud Giant's Jaunt targeting preview — same shape as Misty Step's own TILE-target preview (blue
# max-reach backdrop + purple/gray exact-tile highlight via show_touch_target_preview()), just fed
# from PlayerGoliath's own armed state instead of a Spell resource, since Cloud's Jaunt isn't cast
# through the spell system at all. Bugfix: this used to have no preview whatsoever, same gap Breath
# Weapon had before its own preview was added.
func _update_cloud_teleport_preview() -> bool:
	_dungeon_floor.show_spell_range_preview(grid_pos, PlayerGoliath.CLOUD_TELEPORT_RANGE, false)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var d: Vector2i = tile - grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var in_range: bool = dist_cheb <= PlayerGoliath.CLOUD_TELEPORT_RANGE \
		and _dungeon_floor.is_tile_visible(tile) and _dungeon_floor.is_walkable(tile) \
		and _dungeon_floor.get_enemy_at(tile) == null
	_dungeon_floor.show_touch_target_preview(tile, in_range)
	return true

# Adrenaline Rush's one-tile dash targeting preview — same shape as Cloud Giant's Jaunt above,
# just clamped to PlayerOrc.DASH_RANGE (1 tile).
func _update_adrenaline_dash_preview() -> bool:
	_dungeon_floor.show_spell_range_preview(grid_pos, PlayerOrc.DASH_RANGE, false)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var d: Vector2i = tile - grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var in_range: bool = tile != grid_pos and dist_cheb <= PlayerOrc.DASH_RANGE \
		and _dungeon_floor.is_tile_visible(tile) and _dungeon_floor.is_walkable(tile) \
		and _dungeon_floor.get_enemy_at(tile) == null
	_dungeon_floor.show_touch_target_preview(tile, in_range)
	return true

# Step of the Wind's one-tile dash targeting preview — identical shape to Adrenaline Rush's own
# above, just PlayerMonk.STEP_OF_WIND_RANGE (also 1 tile).
func _update_step_of_wind_preview() -> bool:
	_dungeon_floor.show_spell_range_preview(grid_pos, PlayerMonk.STEP_OF_WIND_RANGE, false)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var d: Vector2i = tile - grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var in_range: bool = tile != grid_pos and dist_cheb <= PlayerMonk.STEP_OF_WIND_RANGE \
		and _dungeon_floor.is_tile_visible(tile) and _dungeon_floor.is_walkable(tile) \
		and _dungeon_floor.get_enemy_at(tile) == null
	_dungeon_floor.show_touch_target_preview(tile, in_range)
	return true

# Hunter's Mark targeting preview — same shape every other spell/ability gets: a blue max-range
# backdrop (Stats.HUNTERS_MARK_RANGE) plus a red highlight on the hovered tile whenever it holds a
# targetable enemy in range. Bugfix: this used to have no preview whatsoever, same gap Breath
# Weapon/Cloud Giant's Jaunt had before their own previews were added.
func _update_hunters_mark_preview() -> bool:
	_dungeon_floor.show_spell_range_preview(grid_pos, Stats.HUNTERS_MARK_RANGE, false)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var d: Vector2i = tile - grid_pos
	# Chebyshev, matching commit_mark()'s own range check (player_ranger_talents.gd).
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var in_range: bool = dist_cheb <= Stats.HUNTERS_MARK_RANGE
	_dungeon_floor.show_single_target_preview(tile, in_range)
	return true

# Shift+hover ranged-weapon targeting preview — mirrors _update_spell_aoe_preview()'s shape but for
# a plain equipped ranged weapon: a two-tone blue backdrop (light = normal range, dark = the extra
# long-range band that rolls with Disadvantage — DungeonFloor.show_ranged_range_preview()) plus the
# same red single-tile enemy highlight spells use (DungeonFloor.show_single_target_preview() —
# shared, not duplicated). Only active while no spell is armed for targeting, so the two previews
# never fight over the same frame — see the comment on show_ranged_range_preview() itself. Returns
# whether the preview is actually showing this frame, same reason as _update_spell_aoe_preview()'s
# own return.
func _update_ranged_range_preview() -> bool:
	if _dungeon_floor == null:
		return false
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing \
			or GameState.short_rest_open or GameState.inventory_open or (GameState.is_game_over or GameState.is_dying) \
			or GameState.blacksmith_panel_open or GameState.shop_open:
		_dungeon_floor.hide_ranged_range_preview()
		return false
	var spell_armed: bool = _spellcasting.get_armed_spell() != null \
			or (Input.is_key_pressed(KEY_ALT) and GameState.special_slot_spell_id != "")
	if spell_armed:
		_dungeon_floor.hide_ranged_range_preview()
		return false
	# Primed throw mode (_throw_item armed via on_throw_primed()): show the same two-tone range
	# backdrop plus a world-tile red/single-target highlight so the player can actually see where
	# the throw will land — bugfix, this used to show nothing once primed (only the pre-activation
	# quickbar-hover preview below existed), so there was no feedback at all while "ready to throw."
	if _throw_item != null and _throw_item.item_type == Item.Type.WEAPON and _throw_item.is_thrown:
		var throw_long_r: int = _throw_item.long_range if _throw_item.long_range > 0 else DungeonFloor.FOV_RADIUS
		_dungeon_floor.show_ranged_range_preview(grid_pos, _throw_item.range, throw_long_r)
		var world_mouse_t: Vector2 = get_global_mouse_position()
		var tile_t: Vector2i = Vector2i(floori(world_mouse_t.x / 16.0), floori(world_mouse_t.y / 16.0))
		var d_t: Vector2i = tile_t - grid_pos
		var dist_cheb_t: int = maxi(absi(d_t.x), absi(d_t.y))
		var in_range_t: bool = dist_cheb_t <= throw_long_r
		_dungeon_floor.show_single_target_preview(tile_t, in_range_t)
		return true
	# Quickbar hover: hovering a thrown item in the item bar (hud.gd) previews ITS range/
	# long_range, same two-tone backdrop, no Shift/equipped-ranged-weapon needed — no world-tile
	# enemy highlight though, since the mouse is over UI, not a game-world tile.
	var hover_item: Item = GameState.quickbar_hover_thrown_item
	if hover_item != null:
		var hover_long_r: int = hover_item.long_range if hover_item.long_range > 0 else DungeonFloor.FOV_RADIUS
		_dungeon_floor.show_ranged_range_preview(grid_pos, hover_item.range, hover_long_r)
		return true
	if not Input.is_key_pressed(KEY_SHIFT):
		_dungeon_floor.hide_ranged_range_preview()
		return false
	var weapon: Item = GameState.equipped_ranged
	if weapon == null:
		_dungeon_floor.hide_ranged_range_preview()
		return false
	var long_r: int = weapon.long_range if weapon.long_range > 0 else DungeonFloor.FOV_RADIUS
	_dungeon_floor.show_ranged_range_preview(grid_pos, weapon.range, long_r)
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	# Same range/FOV check the real shot enforces (is_ranged_target_in_range()) — an enemy beyond
	# the weapon's own long range (or hiding beyond the normal range in unexplored fog) never tints
	# red, matching the spell-preview rule above.
	var in_range: bool = _ranged.is_ranged_target_in_range(weapon, tile)
	_dungeon_floor.show_single_target_preview(tile, in_range)
	return true

func _reset_camera_offset() -> void:
	if _camera != null:
		_camera.position = Vector2.ZERO
	_is_panning = false
	_lmb_panning = false
	_pending_click_tile = Vector2i(-1, -1)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _camera != null:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_cam = _camera.position
			else:
				_is_panning = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Capture pan origin; actual panning activates after 8px threshold in motion handler.
				# gui_get_hovered_control() reflects whatever Control (if any) is currently under the
				# mouse — checked here, at press time, so a drag that STARTS on a UI element (Spellbook
				# row, ActionBar slot, any overlay) never pans the camera, no matter where the drag
				# later travels. A drag starting on bare game world still pans normally.
				_pan_start_mouse = mb.position
				_pan_start_cam = _camera.position
				_lmb_panning = false
				_lmb_press_over_ui = get_viewport().gui_get_hovered_control() != null
			elif _lmb_panning:
				_lmb_panning = false
				_is_panning = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _camera != null:
		if _is_panning:
			var motion := event as InputEventMouseMotion
			_camera.position = _pan_start_cam - (motion.position - _pan_start_mouse) / _camera.zoom.x
			get_viewport().set_input_as_handled()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _lmb_panning and not _lmb_press_over_ui \
				and not GameState.inventory_open and not GameState.spellbook_open and not GameState.spell_learn_picker_open:
			# BUGFIX: this camera-pan detector lives in _input(), which fires before any Control's
			# gui_input — so without a guard here, holding LMB and dragging ANY UI element (a
			# Spellbook row, an ActionBar slot for the in-bar reorder drag, any future overlay) also
			# panned the game world/camera underneath it (reported as "drag drags the
			# background/level"). _lmb_press_over_ui is the general fix (set at press time above);
			# the explicit overlay-flag checks are kept as defense-in-depth.
			var motion := event as InputEventMouseMotion
			if motion.position.distance_to(_pan_start_mouse) > 8.0:
				_lmb_panning = true
				_is_panning = true
				# Reset pan baseline to current position so camera doesn't jump
				_pan_start_mouse = motion.position
				_pan_start_cam = _camera.position
				_queued_path.clear()
				_target_enemy = null
				_pending_click_tile = Vector2i(-1, -1)
				_click_start_screen_pos = Vector2(-1.0, -1.0)
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if (GameState.is_game_over or GameState.is_dying) or not GameState.class_selected:
		return
	# BUGFIX: mouse events reaching here were never gated by ANY blocking overlay (only keyboard
	# input was, further below) — a mouse-button release landing over the game world while a
	# blocking picker was open (e.g. releasing a Spellbook drag past the overlay's dim) could still
	# trigger a game-world move/attack underneath it. Every overlay's own doc comment already
	# claims it "blocks ALL player input" — this closes the mouse-specific gap in that claim.
	if (event is InputEventMouseButton or event is InputEventMouseMotion) and (
			GameState.inventory_open or GameState.short_rest_open or GameState.short_rest_active \
			or GameState.talent_picker_open or GameState.mastery_picker_open \
			or GameState.subclass_picker_open or GameState.race_picker_open or GameState.point_buy_open \
			or GameState.background_select_open or GameState.blacksmith_panel_open or GameState.shop_open \
			or GameState.cantrip_picker_open or GameState.spell_learn_picker_open or GameState.spellbook_open \
			or GameState.invocation_picker_open):
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		# I key toggles inventory regardless of turn phase (blocked during short rest)
		if key.physical_keycode == KEY_I:
			if not GameState.short_rest_open and not GameState.mastery_picker_open \
					and not GameState.subclass_picker_open and not GameState.race_picker_open \
					and not GameState.point_buy_open and not GameState.background_select_open \
					and not GameState.cantrip_picker_open and not GameState.blacksmith_panel_open \
					and not GameState.shop_open \
					and not GameState.spell_learn_picker_open and not GameState.spellbook_open \
					and not GameState.invocation_picker_open:
				GameState.inventory_toggle.emit()
			return
		# T key opens talent screen regardless of turn phase; bypasses phase gate
		if key.physical_keycode == KEY_T:
			if not GameState.inventory_open and not GameState.short_rest_open \
					and not GameState.short_rest_active and not GameState.talent_picker_open \
					and not GameState.mastery_picker_open and not GameState.subclass_picker_open \
					and not GameState.race_picker_open and not GameState.point_buy_open \
					and not GameState.background_select_open and not GameState.blacksmith_panel_open \
					and not GameState.shop_open \
					and not GameState.cantrip_picker_open and not GameState.spell_learn_picker_open \
					and not GameState.spellbook_open and not GameState.invocation_picker_open:
				_actions.open_talent_picker()
				get_viewport().set_input_as_handled()
			return
		# O key opens the Wizard Spellbook (docs/architecture/leveled-spells-and-slots-plan.md §5)
		if key.physical_keycode == KEY_O:
			if GameState.player_stats.caster != null \
					and not GameState.inventory_open and not GameState.short_rest_open \
					and not GameState.short_rest_active and not GameState.talent_picker_open \
					and not GameState.mastery_picker_open and not GameState.subclass_picker_open \
					and not GameState.race_picker_open and not GameState.point_buy_open \
					and not GameState.background_select_open and not GameState.blacksmith_panel_open \
					and not GameState.shop_open \
					and not GameState.cantrip_picker_open and not GameState.spell_learn_picker_open \
					and not GameState.spellbook_open and not GameState.invocation_picker_open:
				var picker = load("res://scripts/ui/spellbook_overlay.gd").new()
				get_tree().root.add_child(picker)
				get_viewport().set_input_as_handled()
			return
		if GameState.inventory_open or GameState.short_rest_open or GameState.short_rest_active \
				or GameState.talent_picker_open or GameState.mastery_picker_open \
				or GameState.subclass_picker_open or GameState.race_picker_open or GameState.point_buy_open \
				or GameState.background_select_open or GameState.blacksmith_panel_open or GameState.shop_open \
				or GameState.cantrip_picker_open or GameState.spell_learn_picker_open or GameState.spellbook_open \
				or GameState.invocation_picker_open:
			return
		if key.physical_keycode == KEY_ESCAPE:
			if _throw_item != null:
				_throw_item = null
				GameState.game_log("[color=gray]Throw cancelled.[/color]")
			if _tool_item != null:
				_tool_item = null
				GameState.game_log("[color=gray]Disarm cancelled.[/color]")
			if _hook_mode_active:
				_hook_mode_active = false
				GameState.game_log("[color=gray]Grip of the Forest cancelled.[/color]")
			if _hunters_mark_mode_active:
				_hunters_mark_mode_active = false
				GameState.game_log("[color=gray]Hunter's Mark cancelled.[/color]")
			if _goliath.cloud_teleport_mode_active:
				_goliath.cloud_teleport_mode_active = false
				GameState.game_log("[color=gray]Cloud Giant teleport cancelled.[/color]")
			if _orc.dash_mode_active:
				_orc.cancel()
				GameState.game_log("[color=gray]Adrenaline Rush dash cancelled.[/color]")
			if _monk.step_of_wind_mode_active:
				_monk.cancel_step_of_wind()
				GameState.game_log("[color=gray]Step of the Wind cancelled.[/color]")
			if _halfling.nimbleness_mode_active:
				_halfling.cancel()
				GameState.game_log("[color=gray]Nimbleness cancelled.[/color]")
			_dragonborn.cancel_breath_weapon()
			_aasimar.cancel_healing_hands()
			if _spellcasting.spell_targeting_active:
				_spellcasting.cancel()
				GameState.game_log("[color=gray]Spell cancelled.[/color]")
			if _berserker.frenzy_mode_active:
				_berserker.frenzy_mode_active = false
				GameState.game_log("[color=gray]Frenzy cancelled.[/color]")
			if _scarred_warrior.limit_break_mode_active:
				_scarred_warrior.limit_break_mode_active = false
				GameState.game_log("[color=gray]Limit Break cancelled.[/color]")
			return
		# Tab toggles between item bar and ability bar (valid any time except game over)
		if key.physical_keycode == KEY_TAB:
			GameState.player_action_requested.emit("toggle_ability_bar")
			return
		# [Space] during an upcast SAVE spell's multi-target collection (Hold Person/Hideous
		# Laughter) resolves the cast now with whatever's picked so far, instead of falling through
		# to the normal Space=wait binding below — see PlayerSpellcasting.finish_multi_target_early().
		if key.physical_keycode == KEY_SPACE and _spellcasting.is_collecting_multi_target():
			_spellcasting.finish_multi_target_early()
			return
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
			return
		_queued_path.clear()
		match key.physical_keycode:
			KEY_Q, KEY_KP_7:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(-1, -1))
			KEY_E, KEY_KP_9:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(1, -1))
			KEY_Z, KEY_KP_1:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(-1, 1))
			KEY_C, KEY_KP_3:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(1, 1))
			KEY_SPACE, KEY_PERIOD, KEY_KP_5: _actions.wait_action()
			KEY_R: _actions.open_short_rest()
			KEY_BACKSPACE:
				if not RewindManager.rewind():
					GameState.game_log("[color=gray]Nothing to rewind.[/color]")
			KEY_1: _use_quickbar_slot(0)
			KEY_2: _use_quickbar_slot(1)
			KEY_3: _use_quickbar_slot(2)
			KEY_4: _use_quickbar_slot(3)
			KEY_5: _use_quickbar_slot(4)
			KEY_6: _use_quickbar_slot(5)
			KEY_7: _use_quickbar_slot(6)
			KEY_8: _use_quickbar_slot(7)
			KEY_9: _use_quickbar_slot(8)

	elif event is InputEventMouseMotion:
		if _click_start_screen_pos.x >= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var motion := event as InputEventMouseMotion
			if motion.position.distance_to(_click_start_screen_pos) > 8.0:
				_queued_path.clear()
				_target_enemy = null
				_pending_click_tile = Vector2i(-1, -1)
				_click_start_screen_pos = Vector2(-1.0, -1.0)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Zoom deferred here so ScrollContainers (debug panel) get wheel events via _gui_input first
		if mb.pressed and _camera != null:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom = Vector2.ONE * clampf(_camera.zoom.x + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom = Vector2.ONE * clampf(_camera.zoom.x - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()
				return
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_click_start_screen_pos = Vector2(-1.0, -1.0)
				var pending := _pending_click_tile
				_pending_click_tile = Vector2i(-1, -1)
				if _lmb_panning or pending == Vector2i(-1, -1) or _dungeon_floor == null:
					return
				if GameState.short_rest_active or GameState.short_rest_open or GameState.blacksmith_panel_open or GameState.shop_open:
					return
				# Extra Attack (Monk, level 5+): during the granted second-attack window, a click
				# only ever resolves as the second attack itself (an already-adjacent, targetable
				# enemy — no movement needed to reach it) — any other click (an empty tile, a
				# distant enemy that would require chasing, a spell) is blocked outright, same
				# "attack again or wait, nothing else" rule _try_move() enforces for WASD.
				if GameState.monk_extra_attack_pending:
					var _ea_enemy: Enemy = _dungeon_floor.get_targetable_enemy_at(pending)
					var _ea_ok: bool = _ea_enemy != null and _ea_enemy.min_dist_to(grid_pos) <= 1 \
						and not Input.is_key_pressed(KEY_SHIFT) and not Input.is_key_pressed(KEY_ALT)
					if not _ea_ok:
						GameState.game_log("[color=gray]Extra Attack: attack again, or wait to end your turn.[/color]")
						return
				# BUGFIX: this Alt+special-slot check must run BEFORE the "pending == grid_pos"
				# no-op-move guard below — a SELF-target spell (Mage Armor) in the Special slot is
				# naturally Alt+clicked ON your own tile (the only valid target), which used to
				# hit that guard's early return first and silently do nothing.
				if Input.is_key_pressed(KEY_ALT) and GameState.special_slot_spell_id != "":
					if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
						return
					_spellcasting.cast_direct(GameState.special_slot_spell_id, pending)
					return
				if pending == grid_pos:
					return
				if Input.is_key_pressed(KEY_SHIFT):
					var rw: Item = GameState.equipped_ranged
					if rw == null:
						GameState.game_log("[color=gray]No ranged weapon equipped.[/color]")
						return
					if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
						return
					if not _ranged.is_ranged_target_in_range(rw, pending):
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % DungeonFloor.FOV_RADIUS)
						return
					if not _dungeon_floor.has_ranged_los(grid_pos, pending):
						GameState.game_log("[color=gray]No clear shot to target.[/color]")
						return
					var enemy_shift: Enemy = _dungeon_floor.get_targetable_enemy_at(pending)
					if enemy_shift != null:
						_ranged.ranged_attack(enemy_shift)
					else:
						_ranged.ranged_attack_tile(pending)
					return
				var enemy_on_tile: Enemy = _dungeon_floor.get_targetable_enemy_at(pending)
				if enemy_on_tile != null:
					_target_enemy = enemy_on_tile
					_enemy_attacked_last_round = false
					_enemy_noticed_last_round = false
					_queued_path.clear()
					if not _path_executing:
						_execute_queued_path()
					return
				_target_enemy = null
				var release_path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, pending)
				if release_path.is_empty():
					return
				_queued_path = release_path
				if not _path_executing:
					_execute_queued_path()
			else:
				_click_start_screen_pos = Vector2(-1.0, -1.0)
			return
		if _dungeon_floor == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var clicked: Vector2i = Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			# Multi-target/multi-beam picking (Magic Missile/Eldritch Blast): RMB undoes the most
			# recently locked-in pick instead of whatever RMB would normally do
			# (Inspect/tool-complete/etc.) — takes priority over everything else below while a
			# pick is in progress.
			if _spellcasting.is_collecting_multi_target():
				if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
					_spellcasting.undo_last_multi_target_pick()
				return
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_throw_item = null
				if _tool_item != null and _tool_item.item_name == "Empty Bottle":
					var bottle: Item = _tool_item
					_tool_item = null
					_throw_tool.try_fill_bottle(bottle, clicked)
				elif _tool_item != null:
					# A tool (e.g. Thief Tools) is actively primed — RMB completes that tool's
					# action exactly as before. Only the no-tool-primed fallback below changed
					# (plain RMB is now instant Inspect / double-RMB Search, not interact_action()).
					_tool_item = null
					_actions.interact_action(true, clicked)
				else:
					_actions.handle_rmb_click(clicked)
			return

		if mb.button_index != MOUSE_BUTTON_LEFT:
			return

		_click_start_screen_pos = mb.position

		# Ctrl+click = Inspect the clicked tile/entity/item, regardless of what a plain click there
		# would otherwise do (movement, attack, targeting mode, etc.) — takes priority over
		# everything else below. Mirrors the RMB instant-Inspect gating (only while it's actually
		# the player's turn to act).
		if Input.is_key_pressed(KEY_CTRL):
			_click_start_screen_pos = Vector2(-1.0, -1.0)
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_actions.do_inspect(clicked)
			return

		if GameState.short_rest_active or GameState.short_rest_open or GameState.blacksmith_panel_open or GameState.shop_open:
			return

		# Cantrip targeting mode
		if _spellcasting.spell_targeting_active:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				# Alt+click always resolves centered on the caster's own tile, regardless of the
				# exact pixel clicked — a guaranteed way to self-target a sphere AoE (Fireball) or
				# a touch SELF spell (Mage Armor) without needing to click precisely on your own
				# sprite, which sits under the camera-follow crosshair and can be fiddly to hit.
				var cast_target: Vector2i = grid_pos if Input.is_key_pressed(KEY_ALT) else clicked
				_spellcasting.try_cast_at(cast_target)
			else:
				_spellcasting.cancel()
			return

		# Hunter's Mark targeting mode (Ranger) — range gate (9 tiles) is checked inside commit_mark().
		if _hunters_mark_mode_active:
			_hunters_mark_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var mark_target: Enemy = _dungeon_floor.get_targetable_enemy_at(clicked)
				if mark_target == null:
					GameState.game_log("[color=gray]Hunter's Mark: no target there.[/color]")
				else:
					_ranger_talents.commit_mark(mark_target)
			return

		# Grip of the Forest hook-targeting mode
		if _hook_mode_active:
			_hook_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var rank_h: int = GameState.get_talent_rank("grip_of_the_forest")
				var hook_range: int = [0, 3, 4, 5][mini(rank_h, 3)]
				var target_enemy: Enemy = _dungeon_floor.get_targetable_enemy_at(clicked)
				if target_enemy == null:
					GameState.game_log("[color=gray]Grip of the Forest: no target there.[/color]")
				else:
					var dv: Vector2i = clicked - grid_pos
					if maxi(absi(dv.x), absi(dv.y)) > hook_range:
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % hook_range)
					elif not _dungeon_floor.has_ranged_los(grid_pos, clicked):
						GameState.game_log("[color=gray]No clear line to target.[/color]")
					else:
						_execute_hook(target_enemy)
			return

		# Cloud Giant teleport targeting mode (Goliath Giant Ancestry) — click a visible tile
		# within 3; the charge is only spent on a CONFIRMED teleport (Esc/any other click mode
		# switch costs nothing, see player_goliath.gd).
		if _goliath.cloud_teleport_mode_active:
			_goliath.cloud_teleport_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_goliath.resolve_cloud_teleport(clicked)
			return

		# Adrenaline Rush's one-tile dash targeting mode (Orc) — click an adjacent visible tile;
		# a genuinely free action, no turn cost either way (see player_orc.gd).
		if _orc.dash_mode_active:
			_orc.dash_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_orc.resolve_dash(clicked)
			return

		# Step of the Wind's one-tile dash targeting mode (Monk) — click an adjacent visible tile;
		# a genuinely free action, no turn cost either way (see player_monk.gd).
		if _monk.step_of_wind_mode_active:
			_monk.step_of_wind_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_monk.resolve_step_of_wind(clicked)
			return

		# Halfling Nimbleness targeting mode — click one of the 8 adjacent tiles (blue preview);
		# the charge is only spent on a CONFIRMED slip-through, same "nothing spent on cancel/miss"
		# convention as Cloud Giant's teleport above.
		if _halfling.nimbleness_mode_active:
			_halfling.nimbleness_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_halfling.resolve_nimbleness(clicked)
			return

		# Breath Weapon targeting mode (Dragonborn) — any click supplies a direction only, the
		# clicked tile need not itself be in range (same convention as Burning Hands' cone).
		if _dragonborn.breath_weapon_mode_active:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_dragonborn.resolve_breath_weapon(clicked)
			else:
				_dragonborn.cancel_breath_weapon()
			return

		# Healing Hands targeting mode (Aasimar) — any click confirms, same "no aim needed"
		# convention as Mage Armor's self-cast. Celestial Revelation no longer uses a targeting
		# mode at all — it's a click-to-choose picker overlay instead, see
		# celestial_revelation_picker.gd / PlayerAasimar.activate_celestial_revelation().
		if _aasimar.healing_hands_mode_active:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				_aasimar.resolve_healing_hands(clicked)
			else:
				_aasimar.cancel_healing_hands()
			return

		# Frenzy targeting mode (Berserker) — melee only, must be adjacent.
		if _berserker.frenzy_mode_active:
			_berserker.frenzy_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var frenzy_target: Enemy = _dungeon_floor.get_targetable_enemy_at(clicked)
				if frenzy_target == null:
					GameState.game_log("[color=gray]Frenzy: no target there.[/color]")
				else:
					var dv2: Vector2i = clicked - grid_pos
					if maxi(absi(dv2.x), absi(dv2.y)) > 1:
						GameState.game_log("[color=gray]Frenzy: target must be adjacent.[/color]")
					else:
						_berserker.execute_frenzy(frenzy_target)
			return

		# Limit Break targeting mode (Scarred Warrior) — range depends on Enough is Enough rank.
		if _scarred_warrior.limit_break_mode_active:
			_scarred_warrior.limit_break_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var lb_target: Enemy = _dungeon_floor.get_targetable_enemy_at(clicked)
				if lb_target == null:
					GameState.game_log("[color=gray]Limit Break: no target there.[/color]")
				else:
					var lb_rank: int = GameState.get_talent_rank("enough_is_enough")
					var lb_range: int = 5 if lb_rank >= 3 else 1
					var dv3: Vector2i = clicked - grid_pos
					if maxi(absi(dv3.x), absi(dv3.y)) > lb_range:
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % lb_range)
					elif lb_range > 1 and not _dungeon_floor.has_ranged_los(grid_pos, clicked):
						GameState.game_log("[color=gray]No clear line to target.[/color]")
					else:
						_scarred_warrior.execute_limit_break(lb_target)
			return

		# Tool targeting mode — route by tool type
		if _tool_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				var dist: int = maxi(absi(clicked.x - grid_pos.x), absi(clicked.y - grid_pos.y))
				if dist <= 1:
					var tool: Item = _tool_item
					_tool_item = null
					if tool.item_name == "Empty Bottle":
						_throw_tool.try_fill_bottle(tool, clicked)
					else:
						_actions.interact_action(true, clicked)  # Thief Tools: door lock / trap disarm / nothing
				else:
					GameState.game_log("[color=gray]Too far — click an adjacent tile.[/color]")
			else:
				_tool_item = null
			return

		# Throw mode — consume left-click for the toss (immediate intentional click)
		if _throw_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_throw_tool.do_throw(clicked)
			else:
				_throw_item = null
			return

		# Movement/attack: store tile, execute on release to distinguish from drag
		_pending_click_tile = clicked

func _execute_queued_path() -> void:
	_path_executing = true
	TurnManager.fast_mode = not TurnManager.has_any_enemy()
	_reset_camera_offset()


	var fov_snapshot: Array[Enemy] = _dungeon_floor.get_visible_enemies()

	while true:
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started

		# ── Enemy-chase mode: target was set by clicking on an enemy ──────
		if _target_enemy != null:
			# An enemy noticed or attacked the player (hit or miss) during the round that just
			# resolved — cancel the auto-chase so a fast-approaching ranged/aware enemy can't
			# get several free swings in before the player can react and issue a new command.
			if _enemy_attacked_last_round or _enemy_noticed_last_round:
				_target_enemy = null
				var _interrupt_msg: String = "An enemy attacks" if _enemy_attacked_last_round else "An enemy notices you"
				GameState.game_log("[color=yellow]%s — chase interrupted.[/color]" % _interrupt_msg)
				break
			if not is_instance_valid(_target_enemy) or _target_enemy.stats.is_dead():
				_target_enemy = null
				break

			# Path to whichever occupied tile of the target is closest — for a 1x1 enemy this is
			# always just its grid_pos; for a Large enemy it lets the player approach from whatever
			# side of its footprint is nearest instead of always circling to its top-left corner.
			var chase_dest: Vector2i = _target_enemy.nearest_occupied_tile(grid_pos)
			var chase_path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, chase_dest)
			if chase_path.is_empty():
				_target_enemy = null
				break

			if chase_path.size() <= CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike")):
				# In melee (or extended reach) range — attack
				var atk_dir: Vector2i = chase_dest - grid_pos
				_bump_attack(_target_enemy, atk_dir)
				_target_enemy = null
				if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
					await TurnManager.player_turn_started
				break

			# One step closer
			var next: Vector2i = chase_path[0]
			var dir: Vector2i = next - grid_pos
			var prev_c: Vector2i = grid_pos
			_resolve_enemy_opportunity_attacks(prev_c, next)
			if (GameState.is_game_over or GameState.is_dying):
				_target_enemy = null
				break
			_apply_queued_step_speed(next)
			TurnManager.begin_player_action()
			$AnimatedSprite2D.flip_h = dir.x < 0
			$AnimatedSprite2D.play("run")
			move_to(next, 0.08)
			if _dungeon_floor != null:
				_dungeon_floor.update_fog(grid_pos)
			TurnManager.on_player_action_complete()
			await move_completed
			$AnimatedSprite2D.play("idle")

			if _dungeon_floor != null:
				if _dungeon_floor.has_door_at(prev_c):
					_dungeon_floor.close_door(prev_c)
				_vfx.leave_blood_trail(prev_c)
				# Draconic Flight: never tramples grass, never triggers traps (root CLAUDE.md's
				# "Race system" / scripts/entities/CLAUDE.md's "Dragonborn").
				var _flying_c: bool = GameState.player_stats.draconic_flight_turns > 0
				if not _flying_c and _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
					_dungeon_floor.destroy_grass(grid_pos)
				if not _flying_c:
					_actions.passive_trap_check()
				_actions.check_pickup()
				_play_footstep_sound()
				var trap_c: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
				if not _flying_c and not trap_c.is_empty():
					await _dungeon_floor.trigger_trap(grid_pos, self)
					_target_enemy = null
					break
				if _trap_alert:
					_trap_alert = false
					_target_enemy = null
					break

			if _has_new_enemy_in_fov(fov_snapshot):
				_target_enemy = null
				break
			continue

		# ── Regular queued-path mode ──────────────────────────────────────
		if _queued_path.is_empty():
			break

		var next: Vector2i = _queued_path[0]
		_queued_path.remove_at(0)
		var dir: Vector2i = next - grid_pos

		var enemy_there: Enemy = _dungeon_floor.get_enemy_at(next)
		if enemy_there != null:
			if enemy_there.is_hidden_from_player():
				# Invisible enemy blocking the path reads as a wall — stop here silently,
				# same as _try_move()'s bump handling.
				break
			if Input.is_key_pressed(KEY_SHIFT) and GameState.equipped_ranged != null:
				_ranged.ranged_attack(enemy_there)
			else:
				_bump_attack(enemy_there, dir)
			if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
				await TurnManager.player_turn_started
			break

		# Door handling read-only decision — deliberately does NOT mutate the door yet, same
		# reasoning as _try_move()'s own identical fix: mutating before begin_player_action()
		# would happen before RewindManager's snapshot, so a rewind could never restore the door
		# back to closed.
		var _door_will_open: bool = false
		var _door_will_unlock: bool = false

		if GameState.noclip:
			# Noclip: reject only off-grid VOID tiles
			if _dungeon_floor.get_tile_type(next) == DungeonData.TileType.VOID:
				_queued_path.clear()
				break
		else:
			if _dungeon_floor.has_door_at(next) and not _dungeon_floor.is_door_open(next):
				if _dungeon_floor.is_door_locked(next):
					if _dungeon_floor.is_door_player_locked(next):
						_door_will_unlock = true
						_door_will_open = true
					else:
						GameState.game_log("[color=red]The door is locked.[/color]")
						_queued_path.clear()
						break
				else:
					_door_will_open = true

			if not _dungeon_floor.is_walkable(next) and not _door_will_open:
				_queued_path.clear()
				break

		if _frightened_blocks_move_to(next):
			_queued_path.clear()
			break

		var is_stairs: bool = _dungeon_floor.get_tile_type(next) == DungeonData.TileType.STAIRS_DOWN
		var prev_p: Vector2i = grid_pos

		_resolve_enemy_opportunity_attacks(prev_p, next)
		if (GameState.is_game_over or GameState.is_dying):
			_queued_path.clear()
			break
		_apply_queued_step_speed(next)
		TurnManager.begin_player_action()
		# Door mutation, deferred from the read-only decision above — see that block's own
		# comment.
		if _door_will_unlock:
			_dungeon_floor.unlock_door(next)
			GameState.game_log("[color=cyan]You pass through the door you locked.[/color]")
		if _door_will_open:
			_dungeon_floor.open_door(next)
		$AnimatedSprite2D.flip_h = dir.x < 0
		$AnimatedSprite2D.play("run")
		move_to(next, 0.08)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
		await move_completed
		$AnimatedSprite2D.play("idle")

		if _dungeon_floor != null:
			if _dungeon_floor.has_door_at(prev_p):
				_dungeon_floor.close_door(prev_p)
			_vfx.leave_blood_trail(prev_p)
			var _flying_p: bool = GameState.player_stats.draconic_flight_turns > 0
			if not _flying_p and _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
				_dungeon_floor.destroy_grass(grid_pos)
				_dungeon_floor.update_fog(grid_pos)
			if not _flying_p:
				_actions.passive_trap_check()
			_actions.check_pickup()
			_play_footstep_sound()
			var trap_p: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
			if not _flying_p and not trap_p.is_empty():
				await _dungeon_floor.trigger_trap(grid_pos, self)
				_queued_path.clear()
				break
			if _trap_alert:
				_trap_alert = false
				_queued_path.clear()
				break

		if is_stairs:
			_dungeon_floor.on_player_reached_stairs.call_deferred()
			TurnManager.fast_mode = false
			_path_executing = false
			return

		if _has_new_enemy_in_fov(fov_snapshot):
			_queued_path.clear()
			break

		# Difficult terrain / Slowed: stop the queued path so the player consciously decides
		# whether to keep walking through it — the extra enemy-round cost itself was already
		# applied pre-move by _apply_queued_step_speed() (before this step's own
		# on_player_action_complete() call above), never a second begin/complete pair here.
		if GameState.player_stats.slowed_turns > 0 and GameState.get_talent_rank("trailblazer") < 1:
			_queued_path.clear()
			break

		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started

	TurnManager.fast_mode = false
	_path_executing = false

# Movement-speed consistency (see FREE_MOVE_BEAT_SEC / TurnManager.enemy_actions_this_round) for
# queued-path movement (mouse click / enemy-chase): mirrors _try_move()'s WATER/MUD difficult-
# terrain check, but evaluated on the tile ABOUT TO be stepped onto — before the move — so
# TurnManager.enemy_actions_this_round is set before THIS step's own on_player_action_complete()
# call, never via a second begin_player_action()/on_player_action_complete() pair afterward (that
# used to fire player_turn_ending twice — double Witch Bolt tick, double Stealth check — and flash
# the phase back to WAITING_FOR_INPUT mid-move). Doesn't check the Natural Sleeper Panther/Salmon
# bypasses _try_move() has — pre-existing asymmetry between the two movement paths, unchanged here.
func _apply_queued_step_speed(next_pos: Vector2i) -> void:
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(next_pos)
	if (tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD) \
			and GameState.get_talent_rank("trailblazer") < 1 \
			and GameState.player_stats.draconic_flight_turns <= 0:
		GameState.apply_player_status("slowed", maxi(1, GameState.player_stats.slowed_turns))
	if tile_t == DungeonData.TileType.WATER and GameState.player_stats.burning_turns > 0:
		GameState.player_stats.burning_turns = 0
		GameState.player_status_changed.emit()
		GameState.game_log("[color=cyan]The water extinguishes your flames![/color]")
	# See the identical has_any_enemy() guard in _try_move() — no live enemy means no turn economy
	# to protect, so Slowed/Exhaustion's extra-enemy-round trick is skipped entirely.
	if not TurnManager.has_any_enemy():
		return
	if GameState.player_stats.slowed_turns > 0 and GameState.get_talent_rank("trailblazer") < 1:
		TurnManager.enemy_actions_this_round = 2
	if _exhaustion_move_penalizes():
		TurnManager.enemy_actions_this_round = 2

# Exhaustion's -1/6 movement speed per level, spread evenly across a 6-move cycle rather than
# front-loaded (e.g. level 3 penalizes exactly 3 of every 6 moves = 50% slower, matching -15 ft of
# the 30 ft baseline). Returns whether THIS move should cost double (TurnManager.
# enemy_actions_this_round = 2, same knob Slowed uses) — never touches the visual tween itself, per
# the "Player movement-speed visual consistency" permanent rule. BUGFIX: this used to be a plain
# `counter % 6 < exhaustion_level` check, which is actually front-loaded (penalizes the first N of
# every 6 moves) despite this comment's own claim of an even spread — now genuinely evenly spread
# via the shared CombatMath.tick_duty_cycle() accumulator (e.g. level 2 fires on moves 3 and 6, not
# 1 and 2).
func _exhaustion_move_penalizes() -> bool:
	if GameState.player_stats.exhaustion_level <= 0:
		return false
	return _consume_duty_cycle("exhaustion", GameState.player_stats.exhaustion_level, 6)

func _has_new_enemy_in_fov(snapshot: Array[Enemy]) -> bool:
	if _dungeon_floor == null or GameState.noclip:
		return false
	for e: Enemy in _dungeon_floor.get_visible_enemies():
		if e not in snapshot:
			return true
	return false

# Opportunity Attacks: called on every voluntary player-move step (keyboard _try_move and both
# _execute_queued_path bodies) BEFORE the move tween starts, while the player is still on `prev`.
# Each threatening enemy that isn't SLEEPING, can see `prev`, and hasn't used its reaction this
# round gets one free inline attack — Retaliation-style, no TurnManager involvement, no phase
# change. See docs/architecture/opportunity-attacks-design.md.
func _resolve_enemy_opportunity_attacks(prev: Vector2i, next: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	# Noclip suppresses actual Opportunity Attacks (the player can move through/past enemies
	# freely), but Battlefield Expert's Side Step detection below is independent of OA resolution
	# and must still run in God Mode (God Mode sets noclip alongside invincible) — otherwise the
	# whole Tactician/Side Step trigger silently never fires while debugging.
	var noclip: bool = GameState.noclip
	var evading: bool = GameState.player_evades_opportunity_attacks
	var evaded_any: bool = false
	# Invisible (unseen) player: enemies have no idea where you are, so they can't react with an
	# Opportunity Attack — matches Enemy._can_see_entity()'s same outright-false treatment.
	var player_invisible: bool = GameState.player_stats.invisibility_turns > 0
	for e: Enemy in _dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		# An enemy that hasn't detected the player yet (SLEEPING/STATIONARY/ROAMING — hasn't failed
		# its Stealth-vs-Passive-Perception check, hasn't been attacked) has no idea anything is
		# there to react to, so it can't take an Opportunity Attack — only CHASING/SEARCHING (it
		# has noticed/is hunting the target) qualifies. Bugfix: this used to only exclude SLEEPING,
		# so an idle ROAMING/STATIONARY enemy that had never spotted the player could still land a
		# free reactive swing the instant the player stepped out of its threat range.
		if e.behavior in [Enemy.Behavior.SLEEPING, Enemy.Behavior.STATIONARY, Enemy.Behavior.ROAMING]:
			continue
		if e.oa_used_this_round:
			continue
		if not _dungeon_floor.has_line_of_sight(e.nearest_occupied_tile(prev), prev):
			continue
		var reach: int = e.melee_reach()
		var d_prev: int = e.min_dist_to(prev)
		var d_next: int = e.min_dist_to(next)
		# Battlefield Expert: a side-step (still-adjacent move around this same enemy) falls
		# through the no-OA branch below with zero changes to OA logic itself — see
		# markdowns/barbarian_base.md. Only counts as a genuine "around the enemy" pivot when the
		# step itself is diagonal (dx and dy both nonzero) — a pure lateral slide along one side
		# of the enemy (e.g. NW -> N) stays adjacent too but isn't really going around it.
		var is_diagonal_step: bool = absi(next.x - prev.x) == 1 and absi(next.y - prev.y) == 1
		if d_prev <= reach and d_next <= reach and prev != next and is_diagonal_step:
			_base_talents.on_sidestep(e)
		if noclip:
			continue
		if player_invisible:
			continue
		if d_prev > reach or d_next <= reach:
			continue
		if evading:
			evaded_any = true
			continue
		e.oa_used_this_round = true
		e._attack_player(self)
		if (GameState.is_game_over or GameState.is_dying):
			return
	if evaded_any:
		GameState.game_log("[color=gray]Eagle Form: you slip past their reach.[/color]")

func _play_footstep_sound() -> void:
	match _dungeon_floor.get_tile_type(grid_pos):
		DungeonData.TileType.GRASS, DungeonData.TileType.TRAMPLED_GRASS:
			AudioManager.play("step_grass")
		DungeonData.TileType.MUD:
			AudioManager.play("step_mud")
		DungeonData.TileType.WATER:
			AudioManager.play("step_water")
		_:
			AudioManager.play("step_floor")

# Frightened: DISADV on attacks/checks while the source is in sight (5e text — NOT unconditional
# like Poisoned/Prone/Restrained, hence its own helper rather than folding into
# Stats.has_disadvantage_condition()). Needs `_dungeon_floor` for the LOS check, so it lives here
# rather than on Stats; called from every attack-roll/check site alongside
# `has_disadvantage_condition()`.
func _frightened_active() -> bool:
	var src: Enemy = stats.frightened_source
	if src == null or not is_instance_valid(src) or src.stats.is_dead() or _dungeon_floor == null:
		return false
	return _dungeon_floor.has_line_of_sight(grid_pos, src.grid_pos)

# Frightened's "can't willingly move closer to the source of fear" — true when stepping onto
# `next_pos` would strictly decrease the (squared) distance to the fear source. Forced movement
# (Push, a chasm shove, a future teleport) never calls this — only the two voluntary-movement
# entry points below (_try_move()'s single bump-step, the queued-path executor's per-step loop) do.
func _frightened_blocks_move_to(next_pos: Vector2i) -> bool:
	var src: Enemy = stats.frightened_source
	if src == null or not is_instance_valid(src) or src.stats.is_dead():
		return false
	var cur_d2: int = (grid_pos - src.grid_pos).length_squared()
	var new_d2: int = (next_pos - src.grid_pos).length_squared()
	if new_d2 < cur_d2:
		GameState.game_log("[color=gray]You're too frightened of %s to move closer![/color]" % src.display_name)
		return true
	return false

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	_reset_camera_offset()
	# Spider's Web (see scripts/entities/CLAUDE.md's "Spider" entry): Restrained blocks ALL
	# movement — any direction key instead attempts to tear free (a STR check, D&D's alternate
	# "5+ slashing/fire damage or a Strength/Dexterity check against the escape DC" text
	# simplified to just the check, since this engine has no attack-a-structure system to hang the
	# damage-based escape route on). Consumes the turn either way, same as a real move would.
	# Incapacitated: "can't take actions" — blocks movement/bump-attack entirely, costing the turn
	# (same "any direction key redirects" shape as Restrained/Prone below). See _use_ability_slot()
	# for the ability/spell half of the guard. Paralyzed implies Incapacitated (5e) plus its own
	# extra effects (ADV against/auto-crit within reach — enemy.gd's _attack_player(); a repeated
	# save each real turn — see below) — same guard, same "any key just burns the turn" shape.
	if stats.incapacitated_turns > 0 or stats.paralyzed_turns > 0:
		var _lock_msg: String = "paralyzed" if stats.paralyzed_turns > 0 else "incapacitated"
		GameState.game_log("[color=gray]You're %s and can't act![/color]" % _lock_msg)
		TurnManager.begin_player_action()
		TurnManager.on_player_action_complete()
		return
	if stats.web_restrained:
		_attempt_web_escape()
		return
	# Prone: can't move — any direction key instead stands up (5e: "standing up... uses all of
	# your movement for the turn"), costing the turn without moving, same "any direction key gets
	# redirected" simplification as Restrained above. Attacking while Prone (mouse click, not a
	# directional bump) is still allowed — this only blocks movement/bump-bump-attack.
	if stats.prone:
		stats.prone = false
		GameState.player_status_changed.emit()
		GameState.game_log("[color=silver]You stand up.[/color]")
		TurnManager.begin_player_action()
		TurnManager.on_player_action_complete()
		return
	var target: Vector2i = grid_pos + dir

	# Adrenaline Rush dash primed: a WASD/arrow direction picks the dash's own target instead of
	# the normal move, exactly like Thief Tools' door/trap bump below — the armed mode is consumed
	# here rather than cancelled by movement (see the movement-key handler's own comment).
	if _orc.dash_mode_active:
		_orc.dash_mode_active = false
		_orc.resolve_dash(target)
		return

	# Step of the Wind dash primed: a WASD/arrow direction picks the dash's own target instead of
	# the normal move, same precedent as Adrenaline Rush directly above.
	if _monk.step_of_wind_mode_active:
		_monk.step_of_wind_mode_active = false
		_monk.resolve_step_of_wind(target)
		return

	# Large Form (Goliath, see player_goliath.gd): a 2x2 footprint needs its WHOLE destination
	# block free, not just the single leading tile the rest of this function checks — otherwise a
	# Large player could squeeze partway through a 1-wide gap. Only the 3 NEW tiles (the ones not
	# already part of the current footprint) are checked here; the leading `target` tile itself
	# still goes through the normal enemy-bump/walkability logic below unchanged.
	if size != Vector2i.ONE and not GameState.noclip and _goliath.blocks_large_form_move(target):
		return

	var enemy: Enemy = _dungeon_floor.get_enemy_at(target)
	if enemy != null and enemy.is_hidden_from_player():
		# Invisible enemy's tile feels exactly like a wall bump: no move, no blind attack, no
		# reveal via slash VFX/damage floater. Symmetric with is_walkable_for_enemy() always
		# blocking an enemy from landing ON the (possibly invisible) player's tile.
		return
	if enemy != null:
		# Frenzy/Limit Break armed: a directional bump into an adjacent enemy targets it, same
		# as a normal melee attack — mouse click-to-target (player.gd's click handler) still
		# works as the alternative. Neither auto-fires without an explicit bump or click.
		if _berserker.frenzy_mode_active:
			_berserker.frenzy_mode_active = false
			_berserker.execute_frenzy(enemy)
			return
		if _scarred_warrior.limit_break_mode_active:
			_scarred_warrior.limit_break_mode_active = false
			_scarred_warrior.execute_limit_break(enemy)
			return
		if Input.is_key_pressed(KEY_SHIFT) and GameState.equipped_ranged != null:
			_ranged.ranged_attack(enemy)
		else:
			_bump_attack(enemy, dir)
		return

	# Extra Attack (Monk, level 5+, see PlayerMonk/_bump_attack()'s own trigger): while the
	# granted second-attack window is open, nothing but landing that second attack (the enemy!=null
	# branch above) or forfeiting via Wait can happen this "turn" — no genuine movement, no
	# interact-without-moving (Thief Tools bump below), matching the 5e text that Extra Attack
	# grants more attacks, never more movement. Placed after the enemy-bump branch (which already
	# returned) so a bump INTO an adjacent enemy — the actual second attack — is never blocked here.
	if GameState.monk_extra_attack_pending:
		GameState.game_log("[color=gray]Extra Attack: attack again, or wait to end your turn.[/color]")
		return

	# Thief Tools primed + bump = interact without moving (door or revealed trap).
	if _tool_item != null and _tool_item.item_name == "Thief Tools":
		# Revealed trap adjacent: disarm it.
		var adjacent_trap: Dictionary = _dungeon_floor.get_trap_at(target)
		if not adjacent_trap.is_empty() and adjacent_trap.get("revealed", false):
			_tool_item = null
			_thief_tools.attempt_disarm(target)
			return
		# Door adjacent: lock/unlock/pick action.
		if _dungeon_floor.has_door_at(target):
			_tool_item = null
			if _dungeon_floor.is_door_open(target):
				_thief_tools.attempt_lock_door(target)
			elif _dungeon_floor.is_door_locked(target):
				if _dungeon_floor.is_door_player_locked(target):
					GameState.stealth_check_stillness = true
					TurnManager.begin_player_action()
					_dungeon_floor.unlock_door(target)
					_dungeon_floor.open_door(target)
					GameState.game_log("[color=cyan]You unlock the door you set.[/color]")
					_dungeon_floor.update_fog(grid_pos)
					TurnManager.on_player_action_complete()
				else:
					_thief_tools.attempt_disarm_lock(target)
			else:
				_thief_tools.attempt_lock_door(target)
			return
		# Nothing to interact with — cancel tool and move normally.
		_tool_item = null
		GameState.game_log("[color=gray]Nothing to interact with.[/color]")


	var _ns_rank: int = GameState.get_talent_rank("expanded_forms")
	var _ns_form: String = GameState.active_sleeper_form  # locked in at last floor descent
	var _sleeper_on: bool = GameState.wild_heart_sleeper_active and _ns_rank >= 1
	var _target_tile: DungeonData.TileType = _dungeon_floor.get_tile_type(target)

	# Door handling read-only decision (locked doors distinguish dungeon-generated vs
	# player-set) — deliberately does NOT mutate the door yet. See the begin_player_action()
	# call below for why: mutating here would happen BEFORE RewindManager's snapshot, so a
	# rewind could never restore the door back to closed (bugfix — this used to open/unlock
	# right here, unconditionally ahead of the turn actually starting).
	var _door_will_open: bool = false
	var _door_will_unlock: bool = false

	if GameState.noclip:
		# Noclip: only reject off-grid VOID
		if _dungeon_floor.get_tile_type(target) == DungeonData.TileType.VOID:
			return
	else:
		# Natural Sleeper Owl R1 / Draconic Flight: allow movement into CHASM tiles
		var _owl_override: bool = (_sleeper_on and _ns_form == "Owl" and _target_tile == DungeonData.TileType.CHASM) \
				or (GameState.player_stats.draconic_flight_turns > 0 and _target_tile == DungeonData.TileType.CHASM)
		# Blacksmith prop: bump-to-open instead of blocking pointlessly against the (impassable)
		# tile — mirrors door auto-open-on-step-in ergonomics.
		if _dungeon_floor.has_blacksmith_at(target):
			_actions.open_blacksmith_panel()
			return
		# Shopkeeper prop: bump-to-open, same ergonomics as the Blacksmith prop above.
		if _dungeon_floor.has_shopkeeper_at(target):
			_actions.open_shop_panel(target)
			return
		if _dungeon_floor.has_door_at(target) and not _dungeon_floor.is_door_open(target):
			if _dungeon_floor.is_door_locked(target):
				if _dungeon_floor.is_door_player_locked(target):
					# Player set this lock — walk through freely (you know it)
					_door_will_unlock = true
					_door_will_open = true
				else:
					# Dungeon-generated lock — can't walk through
					GameState.game_log("[color=red]The door is locked.[/color]")
					return
			else:
				_door_will_open = true

		if not _dungeon_floor.is_walkable(target) and not _owl_override and not _door_will_open:
			return

	if _frightened_blocks_move_to(target):
		return

	var is_stairs: bool = _dungeon_floor.get_tile_type(target) == DungeonData.TileType.STAIRS_DOWN

	var prev_pos: Vector2i = grid_pos
	_resolve_enemy_opportunity_attacks(prev_pos, target)
	if (GameState.is_game_over or GameState.is_dying):
		return
	# Battlefield Expert R3: captured here (right after side-step detection) since
	# consume_free_sidestep() clears sidestep_detected_this_move — used at the end of this move.
	var _free_sidestep: bool = _base_talents.consume_free_sidestep()
	TurnManager.begin_player_action()
	# Door mutation, deferred from the read-only decision above — happens right after
	# begin_player_action() so RewindManager's snapshot still captures the door closed.
	if _door_will_unlock:
		_dungeon_floor.unlock_door(target)
		GameState.game_log("[color=cyan]You pass through the door you locked.[/color]")
	if _door_will_open:
		_dungeon_floor.open_door(target)
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(target)
	$AnimatedSprite2D.play("idle")
	if _dungeon_floor != null:
		if _dungeon_floor.has_door_at(prev_pos):
			_dungeon_floor.close_door(prev_pos)
		_vfx.leave_blood_trail(prev_pos)
		# Destroy grass before fog update so our own tile doesn't block sight
		var _flying: bool = GameState.player_stats.draconic_flight_turns > 0
		if not _flying and _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
			_dungeon_floor.destroy_grass(grid_pos)
		_dungeon_floor.update_fog(grid_pos)
		if not _flying:
			_actions.passive_trap_check()
		_actions.check_pickup()
		_play_footstep_sound()
		var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
		if not _flying and not trap.is_empty():
			await _dungeon_floor.trigger_trap(grid_pos, self)  # push trap still awaits; others return instantly
	if is_stairs:
		TurnManager.on_player_action_complete()
		_dungeon_floor.on_player_reached_stairs.call_deferred()
		return
	# Difficult terrain: apply status before Rager / Eagle check.
	# Natural Sleeper Panther R1 bypasses mud; Salmon R1 bypasses water.
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	var _panther_bypass: bool = _sleeper_on and _ns_form == "Panther" and tile_t == DungeonData.TileType.MUD
	var _salmon_bypass: bool = _sleeper_on and _ns_form == "Salmon" and tile_t == DungeonData.TileType.WATER
	# Trailblazer R1: Ranger ignores Mud/Water's difficult-terrain penalty entirely.
	var _trailblazer_bypass: bool = GameState.get_talent_rank("trailblazer") >= 1
	# Draconic Flight: flying over the terrain, not wading through it.
	var _flying_bypass: bool = GameState.player_stats.draconic_flight_turns > 0
	if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD:
		if not _panther_bypass and not _salmon_bypass and not _trailblazer_bypass and not _flying_bypass:
			GameState.apply_player_status("slowed", maxi(1, GameState.player_stats.slowed_turns))
	if tile_t == DungeonData.TileType.WATER and GameState.player_stats.burning_turns > 0:
		GameState.player_stats.burning_turns = 0
		GameState.player_status_changed.emit()
		GameState.game_log("[color=cyan]The water extinguishes your flames![/color]")
	# Natural Sleeper R3: AC bonus while standing in form's terrain
	if _ns_rank >= 3 and GameState.wild_heart_sleeper_active:
		var _ac_terrain_match: bool = (
			(_ns_form == "Owl" and tile_t == DungeonData.TileType.CHASM) or
			(_ns_form == "Panther" and tile_t == DungeonData.TileType.MUD) or
			(_ns_form == "Salmon" and tile_t == DungeonData.TileType.WATER)
		)
		var _new_ac_bonus: int = 2 if _ac_terrain_match else 0
		if _new_ac_bonus != GameState.terrain_ac_bonus:
			GameState.terrain_ac_bonus = _new_ac_bonus
			GameState.recalculate_stats()
	# With no live enemy on the floor, turn economy (free moves, Slowed, Exhaustion) is moot, so
	# that bookkeeping is skipped — but WASD movement (this function) still pays the same
	# FREE_MOVE_BEAT_SEC pacing beat an idle enemy's own turn would normally cost, so walking speed
	# stays identical to a floor with enemies on it (direct owner request — holding WASD used to
	# visibly speed up the instant the last enemy died, purely because there was no enemy round left
	# to wait on). Click-to-move (_execute_queued_path()) deliberately does NOT pay this beat — it's
	# the one sanctioned way to move fast, exactly as intended.
	if not TurnManager.has_any_enemy():
		await get_tree().create_timer(FREE_MOVE_BEAT_SEC).timeout
		TurnManager.on_player_action_complete()
		return
	if _free_sidestep:
		GameState.game_log("[color=cyan]Battlefield Expert: that side-step didn't cost you your turn.[/color]")
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	var _wood_elf_free_step: bool = false
	if stats.character_race == Stats.CharacterRace.ELF and stats.race_variant == Stats.ElfSubrace.WOOD_ELF:
		_wood_elf_free_step = _consume_duty_cycle("wood_elf", 1, 6)
	var _longstrider_free_step: bool = false
	if stats.longstrider_turns > 0:
		_longstrider_free_step = _consume_duty_cycle("longstrider", 1, 3)
	var _monk_um_free_step: bool = false
	if _monk.unarmored_movement_active():
		_monk_um_free_step = _consume_duty_cycle("monk_unarmored_movement", PlayerMonk.unarmored_movement_numerator(stats.character_level), PlayerMonk.UNARMORED_MOVEMENT_DUTY_CYCLE_PER)
	var _large_form_free_step: bool = _goliath.consume_large_form_free_move()
	if _large_form_free_step:
		GameState.game_log("[color=cyan]Large Form: your giant stride carries you further at no cost.[/color]")
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	if stats.expeditious_retreat_turns > 0 and not _expeditious_retreat_move_used_this_turn:
		_expeditious_retreat_move_used_this_turn = true
		GameState.game_log("[color=cyan]Expeditious Retreat: that move didn't cost you your turn.[/color]")
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	elif _longstrider_free_step:
		# Deliberately silent — no game_log() here. This fires roughly every 3rd move for the
		# whole ~600-turn duration; the status-tray icon/tooltip already communicates the effect
		# continuously, so a chat line every 3rd step was pure log spam.
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	elif _wood_elf_free_step:
		# Deliberately silent — same reasoning as Longstrider above (this fires roughly every
		# 6th move for the whole run; a chat line every 6th step was pure log spam).
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	elif _monk_um_free_step:
		# Deliberately silent — same reasoning as Longstrider/Wood Elf above.
		await _take_free_move_beat()
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	# Slowed extra turn cost (skip if Panther/Salmon/Trailblazer bypassed the terrain penalty):
	# opponents get 2 actions for this 1 move, resolved inside the SAME enemy-phase cycle as the
	# move itself — never a second begin_player_action()/on_player_action_complete() pair, which
	# used to fire player_turn_ending twice (double Witch Bolt tick, double Stealth check) and
	# flash the phase back to WAITING_FOR_INPUT mid-move. See TurnManager.enemy_actions_this_round.
	if GameState.player_stats.slowed_turns > 0 and not _panther_bypass and not _salmon_bypass and not _trailblazer_bypass:
		TurnManager.enemy_actions_this_round = 2
	if _exhaustion_move_penalizes():
		TurnManager.enemy_actions_this_round = 2
	TurnManager.on_player_action_complete()

# See FREE_MOVE_BEAT_SEC's own comment — inserted before every free-move revert_to_waiting() so
# chained free moves read as a normal, paced walk rather than an instant multi-tile warp.
func _take_free_move_beat() -> void:
	await get_tree().create_timer(FREE_MOVE_BEAT_SEC).timeout

# ── Rage helpers ─────────────────────────────────────────────────────────────

# Spider's Web escape attempt (Stats.web_restrained) — a Strength check against the DC the
# original failed DEX save rolled against (Stats.web_escape_dc), rolled the same
# die+mod+proficiency-if-trained shape as every other authored check in this file. Success clears
# the condition and destroys the web at the player's own tile (guaranteed to still be underfoot —
# Restrained blocks ALL movement, see _try_move()'s guard above, so the player can never have
# wandered off the web's tile in the meantime). Failure just costs the turn, same as a real D&D
# escape-attempt action.
func _attempt_web_escape() -> void:
	TurnManager.begin_player_action()
	var dc: int = stats.web_escape_dc
	var str_mod: int = stats.str_modifier()
	var prof: int = stats.proficiency_bonus if stats.check_prof_str else 0
	# Poisoned (DISADV on ALL checks, including this STR check — Restrained's own DEX-check
	# clause doesn't apply here since this is STR).
	var has_disadv: bool = stats.poisoned_condition_turns > 0 or _frightened_active()
	# Large Form (Goliath): ADV on STR checks — the one player-side STR check that exists today.
	var has_adv: bool = _goliath.has_large_form_str_adv()
	var roll_net: bool = has_adv and not has_disadv
	var roll_both: bool = has_adv == has_disadv and has_adv  # both true cancels to a flat roll
	var die1: int = Rng.roll(20)
	var die2: int = Rng.roll(20) if (has_adv or has_disadv) and not (has_adv and has_disadv) else die1
	var die: int
	if roll_both:
		die = die1
	elif roll_net:
		die = maxi(die1, die2)
	elif has_disadv:
		die = mini(die1, die2)
	else:
		die = die1
	var total: int = die + str_mod + prof
	var passed: bool = total >= dc
	var meta: String = "check:stat=STR,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [
		die, die1, die2, str_mod, prof, total, dc, int(passed), 1 if roll_net else 0]
	if passed:
		GameState.game_log("[color=lime]You tear free of the webbing! [url=%s]%d vs DC %d[/url][/color]" % [meta, total, dc])
		stats.web_restrained = false
		GameState.player_status_changed.emit()
		if _dungeon_floor != null:
			_dungeon_floor.destroy_web(grid_pos)
	else:
		GameState.game_log("[color=gray]You struggle against the webbing but can't break free. [url=%s]%d vs DC %d[/url][/color]" % [meta, total, dc])
	TurnManager.on_player_action_complete()

func _activate_rage() -> void:
	if _is_raging:
		GameState.game_log("[color=red]You are already raging![/color]")
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	var ab: Ability = _find_ability("rage")
	if ab == null or not ab.has_uses():
		GameState.game_log("[color=red]No Rage uses remaining (resets on floor descent).[/color]")
		return
	if not GameState.invincible:
		GameState.bonus_action_used = true
	_is_raging = true
	_rage_turns = 1  # baseline: lasts 1 turn, refreshed to 1 by attacking or being attacked
	_rage_attacked_this_turn = false
	GameState.is_raging = true
	GameState.rage_turns_remaining = _rage_turns
	if not GameState.invincible:
		ab.uses_remaining -= 1
	GameState.player_stats.rage_uses_remaining = ab.uses_remaining
	GameState.ability_bar_changed.emit()
	AudioManager.play("rage")
	$AnimatedSprite2D.modulate = Color(1.6, 0.55, 0.55)  # red tint
	var rage_dmg_bonus: int = stats.rage_bonus_damage
	GameState.game_log("[color=red]You fly into a RAGE! +%d STR damage. 50%% physical DR. (%d use(s) left)[/color]" % [rage_dmg_bonus, ab.uses_remaining])
	# Ironwood Bark R1: activating Rage grants temp HP (1d6 × rage bonus).
	if GameState.get_talent_rank("ironwood_bark") >= 1:
		var ib_thp: int = Rng.roll(6) * rage_dmg_bonus
		GameState.player_stats.temp_hp = ib_thp
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.game_log("[color=cyan]Ironwood Bark: %d temp HP (1d6 × rage bonus).[/color]" % ib_thp)
	# Free action — does NOT consume the turn.

func _activate_grip_of_the_forest() -> void:
	if not _is_raging:
		return
	if GameState.grip_of_the_forest_used_this_turn:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.invincible:
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	_hook_mode_active = true
	var rank: int = GameState.get_talent_rank("grip_of_the_forest")
	var hook_range: int = [0, 3, 4, 5][mini(rank, 3)]
	GameState.game_log("[color=lime]Grip of the Forest — click an enemy within %d tiles. [Esc] to cancel.[/color]" % hook_range)

func _execute_hook(enemy: Enemy) -> void:
	GameState.grip_of_the_forest_used_this_turn = true
	GameState.ability_bar_changed.emit()
	GameState.stealth_check_stillness = true
	TurnManager.begin_player_action()
	var rank: int = GameState.get_talent_rank("grip_of_the_forest")
	var dc: int = 8 + stats.str_modifier() + stats.proficiency_bonus
	var die1: int = Rng.roll(20)
	var roll: int = die1 + enemy.stats.str_modifier() + GameState.current_floor / 3
	var check_meta: String = "check:stat=STR,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=0" % [
		die1, die1, die1, enemy.stats.str_modifier(), GameState.current_floor / 3, roll, dc, 1 if roll >= dc else 0]
	if roll >= dc:
		GameState.game_log("[color=gray]%s resists Grip of the Forest! [url=%s]%d vs DC %d[/url][/color]" % [enemy.display_name, check_meta, roll, dc])
	else:
		GameState.game_log("[color=lime]Grip of the Forest pulls %s toward you! [url=%s]%d vs DC %d[/url][/color]" % [enemy.display_name, check_meta, roll, dc])
		if _dungeon_floor != null:
			var guard: int = 0
			while enemy.min_dist_to(grid_pos) > 1 and guard < 20:
				guard += 1
				var step_dir: Vector2i = Vector2i(sign(grid_pos.x - enemy.grid_pos.x), sign(grid_pos.y - enemy.grid_pos.y))
				var moved: int = await _dungeon_floor.force_move_entity(enemy, step_dir, 1, false)
				if moved == 0:
					break
		if rank >= 2:
			if enemy.apply_status("rooted", 1):
				GameState.game_log("[color=gray]%s is rooted![/color]" % enemy.display_name)
		if rank >= 3:
			enemy.disadv_next_attack = true
			GameState.game_log("[color=gray]%s has Disadvantage on their next attack.[/color]" % enemy.display_name)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _end_rage() -> void:
	_is_raging = false
	_rage_turns = 0
	GameState.is_raging = false
	GameState.rage_turns_remaining = 0
	$AnimatedSprite2D.modulate = Color(1.0, 1.0, 1.0)

# Branching Strike reach bonus, Divine Fury flat bonus, and weapon proficiency bonus are all
# pure math — computed in scripts/entities/combat_math.gd (CombatMath) now; see call sites below.

func _find_ability(ab_id: String) -> Ability:
	for slot in GameState.player_ability_bar:
		if slot != null and (slot as Ability).ability_id == ab_id:
			return slot as Ability
	return null

# ── Melee attack ─────────────────────────────────────────────────────────────

func _bump_attack(enemy: Enemy, dir: Vector2i) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	# Captured BEFORE on_disturbed() wakes the enemy — has_advantage() reads pre-attack
	# behavior/surprise_available state, which on_disturbed() immediately mutates away.
	var was_surprised: bool = _vfx.has_advantage(enemy)
	enemy.on_disturbed(grid_pos)
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")

	_vfx.show_sword_slash(dir)

	# D&D attack roll: d20 + modifier + proficiency bonus + weapon enhancement vs enemy AC
	# Advantage (2d20 higher) when target is sleeping or entered FOV this turn.
	# Monk unarmed: uses DEX for both attack roll and damage. Others: STR.
	var is_unarmed: bool = GameState.equipped_weapon == null
	var is_monk_unarmed: bool = is_unarmed and stats.character_class == Stats.CharacterClass.MONK
	# Martial Arts' Dextrous Attacks: DEX for both attack + damage rolls, active while unarmed OR
	# wielding a Monk weapon (Simple, or Martial+Light), unarmored, shield-free — see player_monk.gd.
	var monk_ma_active: bool = stats.character_class == Stats.CharacterClass.MONK and _monk.martial_arts_active(GameState.equipped_weapon)
	var is_str_weapon: bool = not is_unarmed and not (GameState.equipped_weapon.is_ranged)
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(null if is_unarmed else GameState.equipped_weapon, stats.proficiency_bonus, stats)
	var weapon_bonus: int = GameState.equipped_weapon.bonus_damage if not is_unarmed else 0
	var is_finesse_weapon: bool = not is_unarmed and GameState.equipped_weapon.is_finesse
	# Monk Dextrous Attacks uses DEX; Finesse weapons use max(STR, DEX); everyone else uses STR.
	var attack_mod: int = dex_mod if monk_ma_active else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var attack_exh: int = CombatMath.exhaustion_penalty()
	var total_hit_bonus: int = attack_mod + prof + weapon_bonus + attack_exh
	# Advantage/Disadvantage sources are counted, but CombatMath.roll_with_adv_disadv() applies the
	# standard 5e cancel rule: any ADV source together with any DISADV source is a flat roll — e.g.
	# two ADV sources + one DISADV is still a flat roll, not ADV.
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	# Bloodhound R1: the first attack against a freshly-marked Hunter's Mark target gets Advantage.
	adv_count += _ranger_talents.consume_bloodhound_fresh_adv(enemy)
	var disadv_count: int = 0
	if was_surprised: adv_count += 1
	# Prone (melee attacks against a prone target have ADV; see the matching ranged-DISADV note
	# at the ranged/thrown/spell attack sites).
	if enemy.prone: adv_count += 1
	# Ensnaring Strike's Restrained condition: ADV on attacks against it, any kind (unlike Prone's
	# melee-ADV/ranged-DISADV split) — see enemy.gd's restrained_turns field comment.
	if enemy.restrained_turns > 0: adv_count += 1
	# Zealous Presence: Advantage on all attack rolls while buffed.
	if stats.zealous_presence_turns > 0: adv_count += 1
	# Vex (Short Bow): ADV on the attack immediately following a Short-Bow hit on this same enemy.
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	# Heavy weapon penalty: STR < 13 imposes Disadvantage
	var weapon_item_ref: Item = GameState.equipped_weapon
	if weapon_item_ref != null and weapon_item_ref.is_heavy and stats.strength < 13: disadv_count += 1
	# Fog Cloud (Blinded): your own attack rolls have Disadvantage while standing inside the cloud.
	if GameState.is_blinded(grid_pos): disadv_count += 1
	# Poisoned / Prone / Restrained condition — DISADV on your own attack rolls (5e: none of
	# these three stack disadvantage with each other, hence the single combined helper).
	if stats.has_disadvantage_condition(): disadv_count += 1
	if _frightened_active(): disadv_count += 1
	# Animal Form Wolf: ADV when enough enemies are in FOV — always active in Wolf form (no
	# Rage required). Enhanced Forms lowers the threshold; R3 also counts 1 enemy + 1 friendly.
	# active_rager_form is the LOCKED-IN form, not natural_rager_form (the preview for next rest).
	if GameState.active_rager_form == "Wolf" and is_str_weapon and _dungeon_floor != null:
		var enh_rank: int = GameState.get_talent_rank("enhanced_forms")
		var wolf_threshold: int = [4, 4, 3, 2][mini(enh_rank, 3)]
		var visible_enemies: int = _dungeon_floor.get_visible_enemies().size()
		var r3_alt: bool = enh_rank >= 3 and visible_enemies >= 1 and GameState.player_companion != null and is_instance_valid(GameState.player_companion)
		if visible_enemies >= wolf_threshold or r3_alt:
			adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + total_hit_bonus
	var is_nat_one: bool = die == 1
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	# Hold Person's Paralyzed condition: any hit made from within 1 tile is an automatic critical
	# hit (5e RAW) — melee is always within 1 tile of its target, so this is unconditional here,
	# but a natural-1 miss still misses (the condition only upgrades an actual hit).
	if not is_crit and not is_nat_one and roll >= enemy.stats.armor_class and enemy.paralyzed_turns > 0:
		is_crit = true
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()

	# Track that we attacked while raging (for rank 1 countdown pause)
	if _is_raging and is_str_weapon:
		_rage_attacked_this_turn = true

	# Compute damage breakdown for tooltip (separate die vs enhancement vs rage)
	var w_dmin: int
	var w_dmax: int
	if monk_ma_active:
		# Martial Arts Die: replaces the weapon's own die (or stands in for no weapon at all)
		# whenever it would deal more — see PlayerMonk.damage_die().
		var ma_die: Vector2i = _monk.damage_die(null if is_unarmed else GameState.equipped_weapon)
		w_dmin = ma_die.x
		w_dmax = ma_die.y
	elif not is_unarmed and GameState.equipped_weapon.damage_die_min > 0:
		w_dmin = GameState.equipped_weapon.damage_die_min
		w_dmax = GameState.equipped_weapon.damage_die_max
	else:
		w_dmin = stats.base_min_damage
		w_dmax = stats.base_max_damage
	var w_enh: int = weapon_bonus  # weapon.bonus_damage
	# Use dex= key for Monk Martial Arts, or for a Finesse weapon whose DEX mod is the one actually used.
	var mod_key: String = "dex" if (monk_ma_active or (is_finesse_weapon and dex_mod > str_mod)) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,exh=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, w_enh, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0, 1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, attack_exh]

	# Zealot Strike heal resolves off the very next melee attack this turn regardless of hit/miss.
	_zealot.resolve_zealot_strike_heal()
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_verb: String = "strike at" if is_monk_unarmed else ("punch" if is_unarmed else "swing")
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("You %s [color=orange]%s[/color] — [url=%s]%s[/url]." % [miss_verb, enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		_try_graze(enemy, is_str_weapon, attack_mod)
		_try_cleave(enemy, is_str_weapon)
		_try_offhand_attack(enemy, is_str_weapon)
		_monk.try_bonus_unarmed_strike(enemy)
		_handle_post_attack_turn(is_monk_unarmed)
		return

	if is_crit: AudioManager.play_crit(weapon_item_ref)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	if adv:
		_vfx.show_surprise_mark(enemy)
	# Vex (e.g. Rapier): melee hit grants ADV on the next attack this round against this enemy — mirrors PlayerRanged's ranged Vex trigger.
	if weapon_item_ref != null and weapon_item_ref.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
		_vex_adv_target = enemy

	var dice_ct: Vector2i = CombatMath.dice_notation(w_dmin, w_dmax)
	var rolls: Array[int] = Rng.roll_dice(dice_ct.x, dice_ct.y)
	var rage_bonus: int = stats.rage_bonus_damage if (_is_raging and is_str_weapon) else 0
	# Monk Dextrous Attacks uses DEX for damage; Finesse weapons use max(STR, DEX); all others use STR.
	var dmg_mod: int = dex_mod if monk_ma_active else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)

	# All bonus damage sources (Ironwood Bark, Judgement Day) are computed BEFORE
	# take_damage/show_damage — see "Damage types / resistances" rule in
	# scripts/entities/CLAUDE.md. Same-type sources (Rage, Frenzy, Ironwood Bark) fold into the
	# main instance as flat modifiers; Judgement Day carries its OWN damage type (Radiant), so it
	# becomes a second, independent damage instance with its own floater/tooltip/resist check.
	# Frenzy (Berserker) is its own action (player_berserker.gd) — it no longer piggybacks a
	# bonus onto ordinary attacks.
	var frenzy_bonus: int = 0
	var ironwood_bonus: int = 0
	var judgement_bonus: int = 0

	# Ironwood Bark R3: next attack this turn deals bonus damage equal to the temp HP snapshotted at turn start.
	if _ironwood_bark_bonus_pending > 0:
		ironwood_bonus = _ironwood_bark_bonus_pending
		_ironwood_bark_bonus_pending = 0

	# Judgement Day: consumed on the attack AFTER the Zealot Strike heal that armed it.
	if _zealot.judgement_day_pending:
		_zealot.judgement_day_pending = false
		var jd_rank: int = GameState.get_talent_rank("judgement_day")
		judgement_bonus = jd_rank * stats.rage_bonus_damage * Rng.roll(6)

	var dmg_type: String = weapon_item_ref.damage_type if weapon_item_ref != null and not weapon_item_ref.damage_type.is_empty() else ("Bludgeoning" if is_unarmed else "<unknown_damage_type>")
	var raw_mods: Array = [
		{"name": "Weapon enhancement", "amount": w_enh, "color": "lightblue"},
		{"name": "%s mod" % ("DEX" if mod_key == "dex" else "STR"), "amount": dmg_mod, "color": "lightblue"},
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
		{"name": "Frenzy", "amount": frenzy_bonus, "color": "red"},
		{"name": "Ironwood Bark", "amount": ironwood_bonus, "color": "cyan"},
	]
	var main_flat_mods: Array = raw_mods.filter(func(m: Dictionary) -> bool: return int(m.get("amount", 0)) != 0)
	# Multiplication always happens LAST: build_damage_instance() sums dice + flat mods THEN
	# doubles on a crit — never double a partial subtotal and tack bonuses on afterward.
	var main_inst: Dictionary = CombatMath.build_damage_instance(rolls, dice_ct.y, main_flat_mods, is_crit, dmg_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var main_result: Dictionary = enemy.take_typed_damage(main_inst["subtotal"], dmg_type, is_crit)
	main_inst["final"] = main_result["actual"]
	main_inst["resist_mul"] = main_result["mul"]
	var actual: int = main_result["actual"]
	enemy.update_hp_bar()
	if actual > 0:
		enemy.on_melee_hit(self)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false, CombatMath.damage_type_color(dmg_type), 0)

	var jd_actual: int = 0
	var jd_type: String = ""
	var jd_inst: Dictionary = {}
	if judgement_bonus > 0:
		jd_type = _zealot.judgement_day_damage_type()
		jd_inst = CombatMath.build_damage_instance([], 0, [{"name": "Judgement Day", "amount": judgement_bonus, "color": "gold"}], is_crit, jd_type)
		var jd_result: Dictionary = enemy.take_typed_damage(jd_inst["subtotal"], jd_type, is_crit)
		jd_inst["final"] = jd_result["actual"]
		jd_inst["resist_mul"] = jd_result["mul"]
		jd_actual = jd_result["actual"]
		enemy.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, jd_actual, false, CombatMath.damage_type_color(jd_type), 1)

	# Torch: while lit and wielded in Main Hand (the weapon _bump_attack always swings), a hit
	# also deals a second, independent 2d4 + STR mod Fire damage instance — see
	# scripts/items/CLAUDE.md's damage-stacking rule (same "one hit, two damage types" shape as
	# Judgement Day above). Same dmg_mod as the primary Bludgeoning instance above — a Torch is
	# never Finesse/unarmed, so this is always the plain STR modifier.
	var torch_actual: int = 0
	var torch_inst: Dictionary = {}
	if weapon_item_ref != null and weapon_item_ref.is_torch and weapon_item_ref.torch_lit:
		var torch_rolls: Array[int] = Rng.roll_dice(2, 4)
		var torch_flat_mods: Array = [{"name": "STR mod", "amount": dmg_mod, "color": "lightblue"}] if dmg_mod != 0 else []
		torch_inst = CombatMath.build_damage_instance(torch_rolls, 4, torch_flat_mods, is_crit, "Fire")
		var torch_result: Dictionary = enemy.take_typed_damage(torch_inst["subtotal"], "Fire", is_crit)
		torch_inst["final"] = torch_result["actual"]
		torch_inst["resist_mul"] = torch_result["mul"]
		torch_actual = torch_result["actual"]
		enemy.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, torch_actual, false, CombatMath.damage_type_color("Fire"), 2 if judgement_bonus > 0 else 1)

	# Hunter's Mark (Ranger, baseline): a hit against the marked target deals a second, independent
	# Force damage instance — same "one hit, two damage types" shape as Judgement Day/Torch above.
	var hm_actual: int = 0
	var hm_inst: Dictionary = {}
	var hm_die: int = _ranger_talents.hunters_mark_bonus_die(enemy, true)
	if hm_die > 0:
		var hm_rolls: Array[int] = [hm_die]
		hm_inst = CombatMath.build_damage_instance(hm_rolls, 6, [], is_crit, "Force")
		var hm_result: Dictionary = enemy.take_typed_damage(hm_inst["subtotal"], "Force", is_crit)
		hm_inst["final"] = hm_result["actual"]
		hm_inst["resist_mul"] = hm_result["mul"]
		hm_actual = hm_result["actual"]
		enemy.update_hp_bar()
		var hm_stack_index: int = 1
		if jd_actual > 0: hm_stack_index += 1
		if torch_actual > 0: hm_stack_index += 1
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, hm_actual, false, CombatMath.damage_type_color("Force"), hm_stack_index)

	# Hex (Warlock): a hit against the hexed target deals a second, independent Necrotic damage
	# instance — same "one hit, two damage types" shape as Hunter's Mark above, just usable by any
	# attack type (weapon/cantrip/spell), not just weapons.
	var hex_actual: int = 0
	var hex_inst: Dictionary = {}
	var hex_die: int = _warlock.hex_bonus_die(enemy)
	if hex_die > 0:
		var hex_rolls: Array[int] = [hex_die]
		hex_inst = CombatMath.build_damage_instance(hex_rolls, 6, [], is_crit, "Necrotic")
		var hex_result: Dictionary = enemy.take_typed_damage(hex_inst["subtotal"], "Necrotic", is_crit)
		hex_inst["final"] = hex_result["actual"]
		hex_inst["resist_mul"] = hex_result["mul"]
		hex_actual = hex_result["actual"]
		enemy.update_hp_bar()
		var hex_stack_index: int = 1
		if jd_actual > 0: hex_stack_index += 1
		if torch_actual > 0: hex_stack_index += 1
		if hm_actual > 0: hex_stack_index += 1
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, hex_actual, false, CombatMath.damage_type_color("Necrotic"), hex_stack_index)

	# Aasimar Celestial Revelation: the FIRST damage dealt each turn while active gets a bonus
	# instance equal to proficiency bonus, Radiant or Necrotic depending on the chosen
	# transformation — same "one hit, two damage types" shape as Judgement Day/Torch/Hunter's Mark
	# above. Scope limitation: only wired into this primary melee hit, same documented gap as
	# those three (see scripts/entities/CLAUDE.md's "Aasimar" section).
	var cr_actual: int = 0
	var cr_inst: Dictionary = {}
	var cr_type: String = ""
	if stats.celestial_revelation_turns > 0 and not stats.celestial_revelation_bonus_used_this_turn:
		stats.celestial_revelation_bonus_used_this_turn = true
		cr_type = "Necrotic" if stats.celestial_revelation_transform == Stats.AasimarTransformation.NECROTIC_SHROUD else "Radiant"
		cr_inst = CombatMath.build_damage_instance([], 0, [{"name": "Celestial Revelation", "amount": stats.proficiency_bonus, "color": "gold"}], is_crit, cr_type)
		var cr_result: Dictionary = enemy.take_typed_damage(cr_inst["subtotal"], cr_type, is_crit)
		cr_inst["final"] = cr_result["actual"]
		cr_inst["resist_mul"] = cr_result["mul"]
		cr_actual = cr_result["actual"]
		enemy.update_hp_bar()
		var cr_stack_index: int = 1
		if jd_actual > 0: cr_stack_index += 1
		if torch_actual > 0: cr_stack_index += 1
		if hm_actual > 0: cr_stack_index += 1
		if hex_actual > 0: cr_stack_index += 1
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, cr_actual, false, CombatMath.damage_type_color(cr_type), cr_stack_index)

	# Fire Giant ancestry (Goliath, see player_goliath.gd): armed, next hit also deals a second,
	# independent Fire damage instance (same "one hit, two damage types" shape as Torch/Hunter's
	# Mark above) — a miss never reaches this line at all, so the charge is only ever spent on a
	# landed hit, matching the "misses don't spend charges" rule.
	var gol_actual: int = 0
	var gol_inst: Dictionary = {}
	var gol_type: String = ""
	# Skip entirely if this hit (or an earlier bonus instance already stacked onto it — Judgement
	# Day/Torch/Hunter's Mark/Celestial Revelation above) already killed the target: no point
	# rolling bonus Fire/Cold damage, or knocking a corpse Prone, on something already dead.
	if actual > 0 and not enemy.stats.is_dead():
		gol_type = _goliath.consume_giant_ancestry_on_hit(enemy)
		if gol_type == "Fire" or gol_type == "Cold":
			# Fire Giant's Burn is 1d10 Fire; Frost Giant's Chill is 1d6 Cold (real 5e trait text —
			# bugfix, Frost used to deal no damage instance at all, see consume_giant_ancestry_on_hit()).
			var gol_sides: int = 6 if gol_type == "Cold" else 10
			var gol_rolls: Array[int] = Rng.roll_dice(1, gol_sides)
			gol_inst = CombatMath.build_damage_instance(gol_rolls, gol_sides, [], is_crit, gol_type)
			var gol_result: Dictionary = enemy.take_typed_damage(gol_inst["subtotal"], gol_type, is_crit)
			gol_inst["final"] = gol_result["actual"]
			gol_inst["resist_mul"] = gol_result["mul"]
			gol_actual = gol_result["actual"]
			enemy.update_hp_bar()
			var gol_stack_index: int = 1
			if jd_actual > 0: gol_stack_index += 1
			if torch_actual > 0: gol_stack_index += 1
			if hm_actual > 0: gol_stack_index += 1
			if hex_actual > 0: gol_stack_index += 1
			if cr_actual > 0: gol_stack_index += 1
			if _dungeon_floor != null:
				_dungeon_floor.show_damage(enemy.position, gol_actual, false, CombatMath.damage_type_color(gol_type), gol_stack_index)
			# The Fire/Frost bonus damage instance has now actually been dealt — only NOW does the
			# charge get spent and the toggle clear (matches Hill/Stone/Storm's own "effect first,
			# spend after" order — see PlayerGoliath.finish_giant_ancestry_bonus_damage()'s comment).
			_goliath.finish_giant_ancestry_bonus_damage()
		elif gol_type == "Prone":
			# Hill's Prone was already applied inside consume_giant_ancestry_on_hit() — its own flavor
			# line logs AFTER the primary hit line below (direct owner request: a reaction/bonus effect
			# must never narrate as happening before the attack that triggered it). Spend the charge
			# now — the effect has already landed, only the log line is deferred.
			_goliath.finish_giant_ancestry_bonus_damage()

	var is_lethal: bool = enemy.stats.is_dead()

	var dmg_meta: String = CombatMath.encode_damage_instance(main_inst)
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var death_tag: String = CombatMath.death_suffix(is_lethal)
	var dmg_segment: String = "[url=%s][color=yellow]%d[/color][/url]%s" % [dmg_meta, actual, type_tag]
	if jd_actual > 0:
		var jd_meta: String = CombatMath.encode_damage_instance(jd_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [jd_meta, jd_actual, jd_type]
	if torch_actual > 0:
		var torch_meta: String = CombatMath.encode_damage_instance(torch_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Fire[/color]" % [torch_meta, torch_actual]
	if hm_actual > 0:
		var hm_meta: String = CombatMath.encode_damage_instance(hm_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Force[/color]" % [hm_meta, hm_actual]
	if hex_actual > 0:
		var hex_meta: String = CombatMath.encode_damage_instance(hex_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Necrotic[/color]" % [hex_meta, hex_actual]
	if cr_actual > 0:
		var cr_meta: String = CombatMath.encode_damage_instance(cr_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [cr_meta, cr_actual, cr_type]
	if gol_actual > 0:
		var gol_meta: String = CombatMath.encode_damage_instance(gol_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [gol_meta, gol_actual, gol_type]
	var verb: String = "strike" if is_monk_unarmed else ("punch" if is_unarmed else "strike")

	if is_crit:
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=red]CRIT![/color] You [url=%s]%s[/url] [color=orange]%s[/color] for %s dmg.%s" % [hit_meta, verb, enemy.display_name, dmg_segment, death_tag], r["lucky"]))
	else:
		GameState.game_log(CombatMath.wrap_halfling_luck("You [url=%s]%s[/url] [color=orange]%s[/color] for %s dmg.%s" % [hit_meta, verb, enemy.display_name, dmg_segment, death_tag], r["lucky"]))
	# Frost Giant's Chill: logged AFTER the main hit line (which already carries the Cold damage
	# instance above) — correct chronological order, damage first, then the slow flavor line.
	if gol_type == "Cold" and not enemy.stats.is_dead():
		GameState.game_log("[color=cyan]Frost's Chill slows %s.[/color]" % enemy.display_name)
	# Hill Giant's Tumble: same "reaction/bonus, not part of the attack itself" ordering as Frost's
	# own flavor line above — logged strictly after the hit line, never merged into it (no damage).
	elif gol_type == "Prone":
		GameState.game_log("[color=cyan]Hill's Tumble knocks %s Prone.[/color]" % enemy.display_name)

	# Ensnaring Strike: consumed the instant a weapon attack lands (armed via the ability bar
	# toggle — PlayerRangerTalents.activate_ensnaring_strike()). Cleared here, BEFORE the trigger
	# resolves, same convention as Hail of Thorns'/Hellish Rebuke's own call sites. Off-hand/
	# Cleave/OA don't trigger this — a documented scope limit, only wired into the primary swing.
	if stats.ensnaring_strike_armed and not enemy.stats.is_dead():
		stats.ensnaring_strike_armed = false
		SpellEffects.trigger_ensnaring_strike(self, enemy, _dungeon_floor)

	# Branching Strike R3: push the target 1 tile away on a hit with a Heavy/Versatile melee weapon.
	if GameState.get_talent_rank("branching_strike") >= 3 and is_str_weapon and not enemy.stats.is_dead() \
			and weapon_item_ref != null and (weapon_item_ref.is_heavy or weapon_item_ref.is_versatile) and _dungeon_floor != null:
		var push_dc: int = 8 + str_mod + prof
		if not enemy.resist_check(push_dc, true):
			var away_dir: Vector2i = Vector2i(sign(enemy.grid_pos.x - grid_pos.x), sign(enemy.grid_pos.y - grid_pos.y))
			if away_dir != Vector2i.ZERO:
				await _dungeon_floor.force_move_entity(enemy, away_dir, 1, false)
				GameState.game_log("[color=cyan]Branching Strike: %s is pushed back![/color]" % enemy.display_name)
		else:
			GameState.game_log("[color=gray]Branching Strike: %s resists the push.[/color]" % enemy.display_name)

	_try_topple(enemy, is_str_weapon, prof, str_mod)

	if enemy.stats.is_dead():
		_finish_kill(enemy)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	_try_cleave(enemy, is_str_weapon)
	_try_offhand_attack(enemy, is_str_weapon)
	_monk.try_bonus_unarmed_strike(enemy)
	_handle_post_attack_turn(is_monk_unarmed)

# Graze mastery (Greatsword): a missed melee attack still deals damage equal to the ability
# modifier used for the attack roll (min 0) — a separate, self-contained damage instance
# logged on its own line, not folded into the (nonexistent) hit damage of this swing.
func _try_graze(enemy: Enemy, is_str_weapon: bool, attack_mod: int) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Graze" or not stats.knows_mastery("Graze") or not is_str_weapon:
		return
	var graze_dmg: int = enemy.take_typed_damage(maxi(attack_mod, 0), weapon.damage_type)["actual"]
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, graze_dmg, false)
	var graze_meta: String = "grz:mod=%d,final=%d" % [attack_mod, graze_dmg]
	GameState.game_log("[color=cyan]Graze:[/color] %s still takes [url=%s][color=yellow]%d[/color][/url] dmg.%s" % [enemy.display_name, graze_meta, graze_dmg, CombatMath.death_suffix(enemy.stats.is_dead())])
	if enemy.stats.is_dead():
		_finish_kill(enemy)

# Topple mastery (Maul): on a hit, the target rolls a CON save (DC 8 + prof + STR mod) or is
# knocked Prone — the real Prone condition (Enemy.prone), not a turn-skip: melee attacks against
# it get ADV / ranged get DISADV until its own next turn, when it auto-stands (consuming one
# point of movement) and can still act normally. See scripts/entities/CLAUDE.md's "Conditions".
func _try_topple(enemy: Enemy, is_str_weapon: bool, prof: int, str_mod: int) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Topple" or not stats.knows_mastery("Topple") \
			or not is_str_weapon or enemy.stats.is_dead():
		return
	var topple_dc: int = 8 + prof + str_mod
	var save: Dictionary = enemy.resist_check_detailed(topple_dc, true)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
	if not save["pass"]:
		if enemy.apply_status("prone", 1):
			GameState.game_log("[color=cyan]Topple:[/color] %s [url=%s]is knocked[/url] [color=orange]Prone[/color]!" % [enemy.display_name, save_meta])
	else:
		GameState.game_log("[color=gray]Topple: %s [url=%s]resists[/url] being knocked prone.[/color]" % [enemy.display_name, save_meta])

# Cleave mastery (Greataxe): if 2+ distinct enemies are within melee reach, the swing also
# rolls a fully independent attack + damage roll against a second target — the one closest
# to the primary target, per weapon-mastery design. Fires regardless of whether the primary
# attack hit or missed (it's a separate swing of the arc, not a bonus tacked onto the primary).
func _try_cleave(primary: Enemy, is_str_weapon: bool) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Cleave" or not stats.knows_mastery("Cleave") or not is_str_weapon or _dungeon_floor == null:
		return
	var reach: int = CombatMath.melee_reach(weapon, GameState.get_talent_rank("branching_strike"))
	var candidates: Array[Enemy] = []
	for e: Enemy in _dungeon_floor.get_visible_enemies():
		if e == primary or e.stats.is_dead():
			continue
		var d: Vector2i = e.grid_pos - grid_pos
		if maxi(absi(d.x), absi(d.y)) <= reach:
			candidates.append(e)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		var da: Vector2i = a.grid_pos - primary.grid_pos
		var db: Vector2i = b.grid_pos - primary.grid_pos
		return maxi(absi(da.x), absi(da.y)) < maxi(absi(db.x), absi(db.y)))
	_resolve_cleave_attack(candidates[0], weapon)

func _resolve_cleave_attack(enemy: Enemy, weapon: Item) -> void:
	# Captured before on_disturbed() wakes the enemy — a still-unaware secondary Cleave target
	# gets its own surprise Advantage same as a primary target would.
	var was_surprised: bool = _vfx.has_advantage(enemy)
	enemy.on_disturbed(grid_pos)
	var str_mod: int = stats.str_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(weapon, stats.proficiency_bonus, stats)
	var weapon_bonus: int = weapon.bonus_damage
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	# Bloodhound R1: the first attack against a freshly-marked Hunter's Mark target gets Advantage.
	adv_count += _ranger_talents.consume_bloodhound_fresh_adv(enemy)
	if was_surprised: adv_count += 1
	# Prone (melee attacks against a prone target have ADV; see the matching ranged-DISADV note
	# at the ranged/thrown/spell attack sites).
	if enemy.prone: adv_count += 1
	var disadv_count: int = 0
	if weapon.is_heavy and stats.strength < 13: disadv_count += 1
	if GameState.is_blinded(grid_pos): disadv_count += 1
	# Poisoned / Prone / Restrained condition — DISADV on your own attack rolls (5e: none of
	# these three stack disadvantage with each other, hence the single combined helper).
	if stats.has_disadvantage_condition(): disadv_count += 1
	if _frightened_active(): disadv_count += 1
	# Vex (Short Bow): future-proofing — a weapon could carry both Cleave and Vex.
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var cleave_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + str_mod + prof + weapon_bonus + cleave_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,str=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,exh=%d" % [
		die, die1, die2, str_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0,
		1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, cleave_exh]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Cleave:[/color] you swing at [color=orange]%s[/color] — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	var w_dmin: int = weapon.damage_die_min if weapon.damage_die_min > 0 else stats.base_min_damage
	var w_dmax: int = weapon.damage_die_max if weapon.damage_die_max > 0 else stats.base_max_damage
	var dice_ct: Vector2i = CombatMath.dice_notation(w_dmin, w_dmax)
	var rolls: Array[int] = Rng.roll_dice(dice_ct.x, dice_ct.y)
	var rage_bonus: int = stats.rage_bonus_damage if _is_raging else 0
	var dmg_type: String = weapon.damage_type if not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var raw_mods: Array = [
		{"name": "Weapon enhancement", "amount": weapon_bonus, "color": "lightblue"},
		{"name": "STR mod", "amount": str_mod, "color": "lightblue"},
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	]
	var flat_mods: Array = raw_mods.filter(func(m: Dictionary) -> bool: return int(m.get("amount", 0)) != 0)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, dice_ct.y, flat_mods, is_crit, dmg_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var result: Dictionary = enemy.take_typed_damage(inst["subtotal"], dmg_type, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	enemy.update_hp_bar()
	if actual > 0:
		enemy.on_melee_hit(self)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false, CombatMath.damage_type_color(dmg_type))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var is_lethal: bool = enemy.stats.is_dead()
	GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Cleave:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [hit_meta, enemy.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	if is_lethal:
		_finish_kill(enemy)

# Dual-wielding (Two-Weapon Fighting): if Main Hand and the Off-hand (GameState.equipment["hand2"])
# both hold a Light melee weapon, every melee attack also swings the off-hand weapon at the same
# target — a fully independent roll, fired regardless of whether the primary attack hit or missed
# (mirrors Cleave's call sites). Per the house rule: the off-hand damage roll skips the STR/finesse
# ability modifier entirely UNLESS it's negative, in which case it's always applied.
func _try_offhand_attack(enemy: Enemy, is_str_weapon: bool) -> void:
	var main_hand: Item = GameState.equipped_weapon
	if main_hand == null or not main_hand.is_light or not is_str_weapon or enemy.stats.is_dead():
		return
	var off_hand: Item = GameState.equipment.get("hand2") as Item
	if off_hand == null or off_hand.item_type != Item.Type.WEAPON or off_hand.is_ranged or not off_hand.is_light:
		return
	_resolve_offhand_attack(enemy, off_hand)
	# Nick (Dagger): while dual-wielding two Light weapons, if either one carries Nick, get one
	# further attack this turn — identical to the Off-hand swing above (same "no ability modifier
	# unless negative" rule) — for a maximum of 3 attacks total (Main Hand, Off-hand, Nick bonus).
	if not enemy.stats.is_dead() and stats.knows_mastery("Nick") \
			and (main_hand.weapon_mastery == "Nick" or off_hand.weapon_mastery == "Nick"):
		_resolve_offhand_attack(enemy, off_hand, "Nick")

func _resolve_offhand_attack(enemy: Enemy, weapon: Item, label: String = "Off-hand") -> void:
	enemy.on_disturbed(grid_pos)
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var attack_mod: int = CombatMath.finesse_modifier(str_mod, dex_mod, weapon.is_finesse)
	var prof: int = CombatMath.weapon_prof_bonus(weapon, stats.proficiency_bonus, stats)
	var weapon_bonus: int = weapon.bonus_damage
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	# Bloodhound R1: the first attack against a freshly-marked Hunter's Mark target gets Advantage.
	adv_count += _ranger_talents.consume_bloodhound_fresh_adv(enemy)
	if enemy.prone: adv_count += 1  # Prone: melee attacks against it have ADV
	var disadv_count: int = 0
	if weapon.is_heavy and stats.strength < 13: disadv_count += 1
	if GameState.is_blinded(grid_pos): disadv_count += 1
	# Poisoned / Prone / Restrained condition — DISADV on your own attack rolls (5e: none of
	# these three stack disadvantage with each other, hence the single combined helper).
	if stats.has_disadvantage_condition(): disadv_count += 1
	if _frightened_active(): disadv_count += 1
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var offhand_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + attack_mod + prof + weapon_bonus + offhand_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var mod_key: String = "dex" if (weapon.is_finesse and dex_mod > str_mod) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,exh=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0,
		1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, offhand_exh]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]%s:[/color] you swing at [color=orange]%s[/color] — [url=%s]%s[/url]." % [label, enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	if weapon.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
		_vex_adv_target = enemy
	var w_dmin: int = weapon.damage_die_min if weapon.damage_die_min > 0 else stats.base_min_damage
	var w_dmax: int = weapon.damage_die_max if weapon.damage_die_max > 0 else stats.base_max_damage
	var dice_ct: Vector2i = CombatMath.dice_notation(w_dmin, w_dmax)
	var rolls: Array[int] = Rng.roll_dice(dice_ct.x, dice_ct.y)
	var rage_bonus: int = stats.rage_bonus_damage if _is_raging else 0
	# Off-hand damage drops the positive ability modifier; a negative modifier still always applies
	# — UNLESS Twin Fang R2 is active against this exact target (Marked, rank >= 2), which keeps
	# the full modifier just for that swing.
	var dmg_mod: int = attack_mod if _ranger_talents.twin_fang_r2_active(enemy) else mini(attack_mod, 0)
	var dmg_type: String = weapon.damage_type if not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var raw_mods: Array = [
		{"name": "Weapon enhancement", "amount": weapon_bonus, "color": "lightblue"},
		{"name": "%s mod" % ("DEX" if mod_key == "dex" else "STR"), "amount": dmg_mod, "color": "lightblue"},
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	]
	var flat_mods: Array = raw_mods.filter(func(m: Dictionary) -> bool: return int(m.get("amount", 0)) != 0)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, dice_ct.y, flat_mods, is_crit, dmg_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var result: Dictionary = enemy.take_typed_damage(inst["subtotal"], dmg_type, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	enemy.update_hp_bar()
	if actual > 0:
		enemy.on_melee_hit(self)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false, CombatMath.damage_type_color(dmg_type))

	# Hunter's Mark: the bonus die applies to Off-hand/Nick swings too (baseline, not talent-gated
	# — see hunters_mark_bonus_die()).
	var hm_actual: int = 0
	var hm_inst: Dictionary = {}
	var hm_die: int = _ranger_talents.hunters_mark_bonus_die(enemy, false)
	if hm_die > 0:
		var hm_rolls: Array[int] = [hm_die]
		hm_inst = CombatMath.build_damage_instance(hm_rolls, 6, [], is_crit, "Force")
		var hm_result: Dictionary = enemy.take_typed_damage(hm_inst["subtotal"], "Force", is_crit)
		hm_inst["final"] = hm_result["actual"]
		hm_inst["resist_mul"] = hm_result["mul"]
		hm_actual = hm_result["actual"]
		enemy.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, hm_actual, false, CombatMath.damage_type_color("Force"), 1)

	# Hex: same as above, extended to the Off-hand/Nick swing too.
	var hex_actual: int = 0
	var hex_inst: Dictionary = {}
	var hex_die: int = _warlock.hex_bonus_die(enemy)
	if hex_die > 0:
		var hex_rolls: Array[int] = [hex_die]
		hex_inst = CombatMath.build_damage_instance(hex_rolls, 6, [], is_crit, "Necrotic")
		var hex_result: Dictionary = enemy.take_typed_damage(hex_inst["subtotal"], "Necrotic", is_crit)
		hex_inst["final"] = hex_result["actual"]
		hex_inst["resist_mul"] = hex_result["mul"]
		hex_actual = hex_result["actual"]
		enemy.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, hex_actual, false, CombatMath.damage_type_color("Necrotic"), 1 if hm_actual <= 0 else 2)

	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var is_lethal: bool = enemy.stats.is_dead()
	var dmg_segment: String = "[url=%s][color=yellow]%d[/color][/url]%s" % [dmg_meta, actual, type_tag]
	if hm_actual > 0:
		var hm_meta: String = CombatMath.encode_damage_instance(hm_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Force[/color]" % [hm_meta, hm_actual]
	if hex_actual > 0:
		var hex_meta: String = CombatMath.encode_damage_instance(hex_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Necrotic[/color]" % [hex_meta, hex_actual]
	GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]%s:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for %s dmg.%s" % [label, hit_meta, enemy.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	if is_lethal:
		_finish_kill(enemy)

# Opportunity Attack: a self-contained, turn-free melee swing triggered when an enemy leaves the
# player's threat range (see docs/architecture/opportunity-attacks-design.md). Modeled on
# _resolve_cleave_attack() — no TurnManager involvement, no per-turn talent effects. Vex/
# Frenzy/Divine-Fury/Ironwood-Bark are deliberately excluded — those are per-turn action
# effects, and this fires on the enemy's turn, not the player's.
func resolve_opportunity_attack(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or enemy.stats.is_dead():
		return
	# Captured before on_disturbed() wakes the enemy — a still-unaware enemy leaving threat range
	# (e.g. a ROAMING enemy that wandered off obliviously) gets surprise Advantage on the OA too.
	var was_surprised: bool = _vfx.has_advantage(enemy)
	enemy.on_disturbed(grid_pos)
	var weapon: Item = GameState.equipped_weapon
	var is_unarmed: bool = weapon == null
	# Martial Arts' Dextrous Attacks/Martial Arts Die apply to Opportunity Attacks too — same
	# unarmed-or-Monk-weapon-and-unarmored gate as _bump_attack(), see player_monk.gd.
	var monk_ma_active: bool = stats.character_class == Stats.CharacterClass.MONK and _monk.martial_arts_active(weapon)
	var is_str_weapon: bool = not is_unarmed and not weapon.is_ranged
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(null if is_unarmed else weapon, stats.proficiency_bonus, stats)
	var weapon_bonus: int = weapon.bonus_damage if not is_unarmed else 0
	var is_finesse_weapon: bool = not is_unarmed and weapon.is_finesse
	var attack_mod: int = dex_mod if monk_ma_active else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	# Bloodhound R1: the first attack against a freshly-marked Hunter's Mark target gets Advantage.
	adv_count += _ranger_talents.consume_bloodhound_fresh_adv(enemy)
	if was_surprised: adv_count += 1
	# Prone (melee attacks against a prone target have ADV; see the matching ranged-DISADV note
	# at the ranged/thrown/spell attack sites).
	if enemy.prone: adv_count += 1
	var disadv_count: int = 0
	if weapon != null and weapon.is_heavy and stats.strength < 13: disadv_count += 1
	if GameState.is_blinded(grid_pos): disadv_count += 1
	# Poisoned / Prone / Restrained condition — DISADV on your own attack rolls (5e: none of
	# these three stack disadvantage with each other, hence the single combined helper).
	if stats.has_disadvantage_condition(): disadv_count += 1
	if _frightened_active(): disadv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var oa_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + attack_mod + prof + weapon_bonus + oa_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var mod_key: String = "dex" if (monk_ma_active or (is_finesse_weapon and dex_mod > str_mod)) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,exh=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0,
		1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, oa_exh]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Opportunity attack:[/color] you swing at [color=orange]%s[/color] as it flees — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	var w_dmin: int
	var w_dmax: int
	if monk_ma_active:
		var ma_die: Vector2i = _monk.damage_die(null if is_unarmed else weapon)
		w_dmin = ma_die.x
		w_dmax = ma_die.y
	elif not is_unarmed and weapon.damage_die_min > 0:
		w_dmin = weapon.damage_die_min
		w_dmax = weapon.damage_die_max
	else:
		w_dmin = stats.base_min_damage
		w_dmax = stats.base_max_damage
	var dice_ct: Vector2i = CombatMath.dice_notation(w_dmin, w_dmax)
	var rolls: Array[int] = Rng.roll_dice(dice_ct.x, dice_ct.y)
	var rage_bonus: int = stats.rage_bonus_damage if (_is_raging and is_str_weapon) else 0
	var dmg_mod: int = dex_mod if monk_ma_active else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var dmg_type: String = weapon.damage_type if (not is_unarmed and not weapon.damage_type.is_empty()) else ("Bludgeoning" if is_unarmed else "<unknown_damage_type>")
	var raw_mods: Array = [
		{"name": "Weapon enhancement", "amount": weapon_bonus, "color": "lightblue"},
		{"name": "%s mod" % ("DEX" if mod_key == "dex" else "STR"), "amount": dmg_mod, "color": "lightblue"},
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	]
	var flat_mods: Array = raw_mods.filter(func(m: Dictionary) -> bool: return int(m.get("amount", 0)) != 0)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, dice_ct.y, flat_mods, is_crit, dmg_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var result: Dictionary = enemy.take_typed_damage(inst["subtotal"], dmg_type, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	enemy.update_hp_bar()
	if actual > 0:
		enemy.on_melee_hit(self)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false, CombatMath.damage_type_color(dmg_type))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var is_lethal: bool = enemy.stats.is_dead()
	GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Opportunity attack:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [hit_meta, enemy.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	if is_lethal:
		_finish_kill(enemy)

func _handle_post_attack_turn(_from_monk_unarmed: bool = false) -> void:
	# Monk's Extra Attack (level 5+): the granted second attack was just resolved (hit or miss,
	# same "doesn't matter which" convention as Bonus Unarmed Strike) — clear the window and end
	# the turn for real. Only this chokepoint (the PRIMARY swing both hit/miss branches of
	# _bump_attack() funnel through — never Cleave/Off-hand/OA, which don't call this at all) can
	# consume the window, matching 5e's "more attacks with the Attack action," not a chain of
	# every bonus swing.
	if GameState.monk_extra_attack_pending:
		GameState.monk_extra_attack_pending = false
		TurnManager.on_player_action_complete()
		return
	# First primary attack of a real turn: grant the second one instead of ending the turn.
	# GameState.monk_extra_attack_used_this_turn (reset every real turn) makes this a genuine
	# once-per-turn grant, not "every attack chains forever." _try_move()/the LMB click handler
	# both refuse anything but landing that second attack (or Wait, which forfeits it) while the
	# window is open — see their own "Extra Attack" comments.
	if stats.character_class == Stats.CharacterClass.MONK and stats.character_level >= 5 \
			and not GameState.monk_extra_attack_used_this_turn:
		GameState.monk_extra_attack_used_this_turn = true
		GameState.monk_extra_attack_pending = true
		GameState.game_log("[color=cyan]Extra Attack: attack again, or wait to end your turn.[/color]")
		_reverted_this_round = true
		TurnManager.revert_to_waiting()
		return
	TurnManager.on_player_action_complete()


func _finish_kill(enemy: Enemy, dropped_ammo: Item = null) -> void:
	# The "and died" text is folded into the attack's own hit-log line (CombatMath.death_suffix(),
	# one call per attack site) rather than logged again here as a separate message.
	_base_talents.on_kill()
	GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
	var was_boss: bool = enemy.is_boss
	var kill_pos: Vector2i = enemy.grid_pos
	var killed_name: String = enemy.display_name
	var killed_boss_id: String = enemy.enemy_id
	_dungeon_floor.remove_enemy(enemy)
	enemy.die()
	if was_boss:
		_dungeon_floor.drop_boss_loot(kill_pos)
		GameState.boss_defeated.emit(killed_boss_id)
	if killed_name in UNDEAD_NAMES and Rng.chance(0.20):
		var rotten := Item.new()
		rotten.item_name = "Rotten Meat"
		rotten.item_type = Item.Type.FOOD
		rotten.food_value = 10
		rotten.icon_path = "res://sprites/items/food/meat.png"
		rotten.description = "Throw into fire to cook into Cooked Meat."
		_dungeon_floor.place_item_on_floor(kill_pos, rotten)
	# Ammo drop-from-corpse: 50% chance the killing shot's arrow/bolt is recoverable.
	if dropped_ammo != null and Rng.chance(0.5):
		_ammo.resolve_ammo_landing(dropped_ammo, kill_pos)

func _on_action_requested(action_name: String) -> void:
	if action_name == "short_rest_begin":
		if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
			_queued_path.clear()
			_path_executing = false
			_actions.do_rest_wait_turn()
		return
	if action_name == "toggle_ability_bar":
		_ability_bar_active = not _ability_bar_active
		return
	if action_name.begins_with("use_ability_"):
		var idx: int = action_name.substr(12).to_int()
		if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
			_use_ability_slot(idx)
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	match action_name:
		"wait":     _actions.wait_action()
		"search":   _actions.search_action()
		"interact": _actions.interact_action()

func _use_quickbar_slot(idx: int) -> void:
	if idx < 0 or idx >= GameState.QUICKBAR_SIZE:
		return
	# Extra Attack (Monk, level 5+): no items/abilities during the granted second-attack window —
	# same "attack again or wait, nothing else" rule as movement (_try_move()) and mouse clicks.
	if GameState.monk_extra_attack_pending:
		GameState.game_log("[color=gray]Extra Attack: attack again, or wait to end your turn.[/color]")
		return
	# Delegate to item bar or ability bar depending on current HUD mode
	# The HUD manages the visual toggle; player.gd reads _ability_bar_active via signal
	if _ability_bar_active:
		_use_ability_slot(idx)
		return
	var raw = GameState.player_quickbar[idx]
	if raw == null:
		return
	GameState.use_item(raw as Item)

# Set by HUD when Tab toggles bar mode
var _ability_bar_active: bool = false

# Double-press-same-slot detection for instant self-cast of touch SELF spells (Mage Armor) — lets
# a player quickcast onto themselves via the hotkey/slot alone, no mouse click needed at all.
const DOUBLE_TAP_WINDOW_SEC: float = 0.4
var _last_ability_slot_idx: int = -1
var _last_ability_slot_press_msec: int = 0

func _use_ability_slot(idx: int) -> void:
	if idx < 0 or idx >= GameState.ABILITY_BAR_SIZE:
		return
	# Incapacitated: "can't take actions" — blocks ability/spell activation. See _try_move()'s own
	# incapacitated guard for the movement/melee-bump half (Paralyzed shares that same guard);
	# mouse-click attacks and item/tool use aren't gated here (partial coverage — see
	# scripts/entities/CLAUDE.md's "Conditions" section).
	if stats.incapacitated_turns > 0 or stats.paralyzed_turns > 0:
		var _lock_msg: String = "paralyzed" if stats.paralyzed_turns > 0 else "incapacitated"
		GameState.game_log("[color=gray]You're %s and can't act![/color]" % _lock_msg)
		return
	var raw = GameState.player_ability_bar[idx]
	if raw == null:
		return
	var ab := raw as Ability
	if ab.ability_id.begins_with("spell:"):
		var spell_id: String = ab.ability_id.trim_prefix("spell:")
		var now_msec: int = Time.get_ticks_msec()
		var is_double_tap: bool = idx == _last_ability_slot_idx \
				and (now_msec - _last_ability_slot_press_msec) <= int(DOUBLE_TAP_WINDOW_SEC * 1000.0)
		_last_ability_slot_idx = idx
		_last_ability_slot_press_msec = now_msec
		var spell: Spell = SpellDb.get_spell(spell_id)
		if is_double_tap and spell != null and spell.target_kind == Spell.TargetKind.SELF:
			# Second press within the window while armed (or already resolved) from the first —
			# resolve straight onto yourself, same as Alt+click, no world click required at all.
			_spellcasting.cancel()
			_spellcasting.cast_direct(spell_id, grid_pos)
			return
		# Pressing the same slot again while THIS spell is already armed cancels the cast — same
		# as Esc. (SELF-touch spells never reach here: the double-tap branch above claims them.)
		# Spell.spell_id compared, not the Resource itself — SpellDb.get_spell() builds a fresh
		# instance every call, so two calls for the same id are never reference-equal.
		var armed: Spell = _spellcasting.get_armed_spell()
		if _spellcasting.spell_targeting_active and armed != null and armed.spell_id == spell_id:
			_spellcasting.cancel()
			GameState.game_log("[color=gray]Spell cancelled.[/color]")
			return
		_spellcasting.begin_cast(spell_id)
		return
	match ab.ability_id:
		"rage":                    _activate_rage()
		"hunters_mark":            _ranger_talents.activate_hunters_mark()
		"unarmored_defense_monk":  GameState.game_log("[color=gray]Unarmored Defense is passive — active when unarmored (AC = 10+DEX+WIS).[/color]")
		"martial_arts":            GameState.game_log("[color=gray]Martial Arts is passive — attack unarmed or with a Monk weapon to trigger it.[/color]")
		"deflect_attacks":         GameState.game_log("[color=gray]Deflect Attacks is passive — it triggers automatically on the first physical hit each turn.[/color]")
		"slow_fall":               GameState.game_log("[color=gray]Slow Fall isn't implemented yet — this game has no fall-damage mechanic.[/color]")
		"extra_attack":            GameState.game_log("[color=gray]Extra Attack is passive — it triggers automatically on your first melee attack each turn.[/color]")
		"flurry_of_blows":         _monk.activate_flurry_of_blows()
		"patient_defense":         _monk.activate_patient_defense()
		"step_of_wind":            _monk.activate_step_of_wind()
		"wild_companion":         _wild_heart.activate_one_with_nature(ab)
		"animal_form":             _wild_heart.cycle_animal_form(ab)
		"enhanced_forms":
			GameState.game_log("[color=gray]%s is passive — upgrades Animal Form automatically.[/color]" % ab.ability_name)
		"expanded_forms":
			GameState.game_log("[color=gray]%s is passive — a random form is rolled every long rest.[/color]" % ab.ability_name)
		"ironwood_bark":           GameState.game_log("[color=gray]Ironwood Bark is passive — triggers on Rage activation and while Raging.[/color]")
		"grip_of_the_forest":      _activate_grip_of_the_forest()
		"branching_strike":        GameState.game_log("[color=gray]Branching Strike is passive — reach and push apply automatically.[/color]")
		"zealot_strike":           _zealot.activate_zealot_strike(ab)
		"judgement_day", "overheal_shield", "never_back_down":
			GameState.game_log("[color=gray]%s is passive — upgrades Zealot Strike automatically.[/color]" % ab.ability_name)
		"frenzy":                  _berserker.activate_frenzy()
		"sadist_monster", "masochist_monster", "frenzied_killer":
			GameState.game_log("[color=gray]%s is passive — upgrades Frenzy automatically.[/color]" % ab.ability_name)
		"limit_break":             _scarred_warrior.activate_limit_break()
		"born_in_blood", "enough_is_enough", "bloodied_regen":
			GameState.game_log("[color=gray]%s is passive — upgrades Limit Break or triggers automatically.[/color]" % ab.ability_name)
		"breath_weapon":           _dragonborn.activate_breath_weapon()
		"draconic_flight":         _dragonborn.activate_draconic_flight()
		"stonecunning":            _dwarf.activate_stonecunning()
		"heroic_inspiration":      _human.activate_heroic_inspiration()
		"adrenaline_rush":         _orc.activate_adrenaline_rush()
		"healing_hands":           _aasimar.activate_healing_hands()
		"celestial_revelation":    _aasimar.activate_celestial_revelation()
		"large_form":              _goliath.activate_large_form()
		"giant_ancestry":          _goliath.activate_giant_ancestry()
		"hellish_rebuke_toggle":   _tiefling.activate_hellish_rebuke()
		"hail_of_thorns_toggle":   _ranger_talents.activate_hail_of_thorns()
		"ensnaring_strike_toggle": _ranger_talents.activate_ensnaring_strike()
		"halfling_nimbleness":     _halfling.activate_nimbleness()
		_:                         GameState.game_log("[color=gray]%s: not yet implemented.[/color]" % ab.ability_name)
