extends Node

enum Phase { WAITING_FOR_INPUT, RESOLVING_PLAYER, RESOLVING_ENEMIES }

signal player_turn_started()
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

func begin_player_action() -> void:
	phase = Phase.RESOLVING_PLAYER

func on_player_action_complete() -> void:
	if phase != Phase.RESOLVING_PLAYER:
		return
	phase = Phase.RESOLVING_ENEMIES
	_process_enemies()

func _process_enemies() -> void:
	var valid: Array = []
	for e in _enemies:
		if is_instance_valid(e):
			valid.append(e)
	if valid.is_empty():
		_end_turn()
		return
	_remaining_enemies = valid.size()
	for e in valid:
		_run_single_enemy(e)

func reset() -> void:
	_remaining_enemies = 0
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()

func _run_single_enemy(enemy: Node) -> void:
	await enemy.take_turn()
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
