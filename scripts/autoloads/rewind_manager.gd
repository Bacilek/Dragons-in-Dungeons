extends Node

# RewindManager — Phase 1 of the "undo 1 turn" feature (docs/architecture plan, see root
# CLAUDE.md's maintenance-rule pointer). Captures an in-memory snapshot at the start of every
# REAL player turn and can restore the most recent one on demand. Never touches disk (unrelated
# to SaveManager's floor-entry checkpoint, which is a much coarser, curated snapshot).
#
# Phase 1+2+3, all implemented: player position/Stats/RNG-stream/TurnManager round state (plus
# the scattered per-turn transient fields on Player/its composition children), every live
# Enemy/Companion (positions/HP/AI state, respawning ones that died this turn, despawning ones
# summoned mid-turn — see DungeonFloor.capture_rewind_enemies()/restore_rewind_enemies()), and
# floor prop state (traps/dispensers/doors/barrels/webs/burning grass/floor items/pending
# thrown-weapon drops — see DungeonFloor.capture_rewind_props()/restore_rewind_props()). One
# documented gap: a trap/dispenser disarmed or looted during the rewound turn is not respawned —
# see that function's own doc comment.
#
# Snapshot point: TurnManager.player_action_starting, fired from the top of begin_player_action()
# — i.e. right BEFORE any player action (real or a revert_to_waiting() free action) resolves.
# Deliberately NOT player_turn_started: that signal fires AFTER the action + enemy phase already
# resolved, at which point the "current" state and the "about to snapshot" state are identical —
# rewinding from a player_turn_started-taken snapshot was a no-op (bugfix, this used to be the
# snapshot point). Capturing pre-action means the snapshot naturally survives untouched across the
# WAITING_FOR_INPUT gap until the player's NEXT action begins, which is exactly when Backspace
# needs it. A free action's own snapshot simply becomes the rewind target for that free action
# alone (nothing wrong with that — undoing a free action is a well-defined, useful thing to do).

const MAX_SNAPSHOTS: int = 1

var _snapshots: Array[Dictionary] = []
var _rewind_in_progress: bool = false


func _ready() -> void:
	TurnManager.player_action_starting.connect(_on_player_action_starting)


func _get_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _get_floor() -> DungeonFloor:
	return get_tree().get_first_node_in_group("dungeon_floor") as DungeonFloor


func _on_player_action_starting() -> void:
	if _rewind_in_progress:
		return
	var player: Player = _get_player()
	if player == null:
		return
	_push(_capture_snapshot(player))


func can_rewind() -> bool:
	return _snapshots.size() > 0 and not _rewind_in_progress \
		and TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT


func rewind() -> bool:
	if not can_rewind():
		return false
	var snap: Dictionary = _snapshots.pop_back()
	_rewind_in_progress = true
	_restore_snapshot(snap)
	_rewind_in_progress = false
	return true


## Called from the floor-load path so a stale snapshot can never survive a floor transition —
## rewind is explicitly scoped to "within the same floor" (see the plan's non-goals).
func clear() -> void:
	_snapshots.clear()


func _push(snap: Dictionary) -> void:
	_snapshots.push_back(snap)
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


func _capture_snapshot(player: Player) -> Dictionary:
	var floor: DungeonFloor = _get_floor()
	return {
		"rng_state": Rng.get_state(),
		"turn_phase": TurnManager.phase,
		"enemy_actions_this_round": TurnManager.enemy_actions_this_round,
		"player_stats": GameState.player_stats.duplicate(true),
		"player_state": player.capture_rewind_state(),
		"enemies": floor.capture_rewind_enemies() if floor != null else [],
		"props": floor.capture_rewind_props() if floor != null else {},
		"floor_ref": weakref(floor) if floor != null else null,
	}


func _restore_snapshot(snap: Dictionary) -> void:
	var player: Player = _get_player()
	var current_floor: DungeonFloor = _get_floor()
	if player == null or current_floor == null:
		return
	var floor_ref: WeakRef = snap.get("floor_ref")
	if floor_ref == null or floor_ref.get_ref() != current_floor:
		# Snapshot belongs to a floor that's no longer current (shouldn't normally happen —
		# clear() already runs on every floor load — but this is the defensive backstop the
		# plan calls for).
		GameState.game_log("[color=gray]Cannot rewind across a floor change.[/color]")
		clear()
		return

	Rng.set_state(int(snap.get("rng_state", Rng.get_state())))

	current_floor.restore_rewind_enemies(snap.get("enemies", []))
	current_floor.restore_rewind_props(snap.get("props", {}))

	var restored_stats: Stats = snap.get("player_stats") as Stats
	if restored_stats != null:
		# Live Enemy-reference concentration/target fields (Hunter's Mark, Witch Bolt, etc.) end
		# on rewind unconditionally — matches existing save/load precedent (see root CLAUDE.md's
		# "Wizard leveled spells" / Ranger sections, "not serialized, live reference").
		restored_stats.hunters_mark_target = null
		restored_stats.witch_bolt_target = null
		restored_stats.ray_of_enfeeblement_target = null
		restored_stats.hold_person_target = []
		restored_stats.hideous_laughter_target = []
		restored_stats.hex_target = null
		restored_stats.frightened_source = null
		restored_stats.ensnaring_strike_target = null
		GameState.player_stats = restored_stats
		player.stats = restored_stats

	player.restore_rewind_state(snap.get("player_state", {}))

	TurnManager.enemy_actions_this_round = int(snap.get("enemy_actions_this_round", 1))
	TurnManager.phase = snap.get("turn_phase", TurnManager.Phase.WAITING_FOR_INPUT)

	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.equipment_changed.emit()
	GameState.player_status_changed.emit()
	GameState.game_log("[color=gray]You rewind time to the start of the turn.[/color]")
