extends Node

enum Phase { WAITING_FOR_INPUT, RESOLVING_PLAYER, RESOLVING_ENEMIES }

signal player_turn_started()
signal turn_resolved()

var phase: Phase = Phase.WAITING_FOR_INPUT
var fast_mode: bool = false

var _enemies: Array = []  # Array[Entity]

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
	for enemy in _enemies:
		if is_instance_valid(enemy):
			await enemy.take_turn()
	_end_turn()

func _end_turn() -> void:
	turn_resolved.emit()
	_start_player_turn()

func _start_player_turn() -> void:
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()
