extends Node

enum Phase { WAITING_FOR_INPUT, RESOLVING_PLAYER, RESOLVING_ENEMIES }

signal player_turn_started()
signal player_turn_ending()  # fired once per real (non-reverted) player action, right before enemies act
signal turn_resolved()

var phase: Phase = Phase.WAITING_FOR_INPUT
var fast_mode: bool = false

var _enemies: Array = []
var _remaining_enemies: int = 0

func _ready() -> void:
	call_deferred("_start_player_turn")

func register_enemy(enemy: Node) -> void:
	_enemies.append(enemy)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)

func clear_enemies() -> void:
	_enemies.clear()

func has_any_enemy() -> bool:
	for e in _enemies:
		if is_instance_valid(e):
			return true
	return false

func begin_player_action() -> void:
	phase = Phase.RESOLVING_PLAYER

func on_player_action_complete() -> void:
	if phase != Phase.RESOLVING_PLAYER:
		return
	player_turn_ending.emit()
	phase = Phase.RESOLVING_ENEMIES
	_process_enemies()

# Rager talent: grants a free action by skipping enemy phase and returning to player input.
# Intentionally narrow — do NOT generalize this into a general action-economy system.
func revert_to_waiting() -> void:
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()

func _process_enemies() -> void:
	var valid: Array = []
	for e in _enemies:
		if is_instance_valid(e):
			valid.append(e)
	if valid.is_empty():
		_end_turn()
		return
	# Decide-then-execute split (see Enemy.decide_turn()/execute_turn()): every enemy's decision is
	# made FIRST, back-to-back, against the identical pre-round world state, before any of them
	# actually moves/attacks/opens a door — so the round reads as simultaneous rather than as a
	# strict sequence where an earlier enemy's move can change what a later enemy is able to see
	# and act on THIS SAME round (e.g. a melee enemy opening a door mid-round granting a ranged
	# enemy behind it same-round line-of-sight to shoot through).
	var pending: Array = []
	for e in valid:
		if not is_instance_valid(e):
			continue
		pending.append([e, e.decide_turn()])
	_remaining_enemies = pending.size()
	if _remaining_enemies == 0:
		_end_turn()
		return
	for pair: Array in pending:
		_run_single_enemy(pair[0], pair[1])

func reset() -> void:
	_remaining_enemies = 0
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()

func _run_single_enemy(enemy: Node, intent: Dictionary) -> void:
	if is_instance_valid(enemy) and not enemy.stats.is_dead():
		await enemy.execute_turn(intent)
	if _remaining_enemies <= 0:
		return
	_remaining_enemies -= 1
	if _remaining_enemies <= 0:
		_end_turn()

func _end_turn() -> void:
	turn_resolved.emit()
	_start_player_turn()

func _start_player_turn() -> void:
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()
