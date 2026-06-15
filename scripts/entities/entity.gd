class_name Entity
extends CharacterBody2D

const TILE_SIZE: int = 16

signal move_completed

var grid_pos: Vector2i = Vector2i.ZERO
var stats: Stats
var _hp_bar: HealthBarNode

func _setup_hp_bar() -> void:
	_hp_bar = HealthBarNode.new()
	_hp_bar.position = Vector2(0.0, -20.0)
	_hp_bar.z_index = 10
	_hp_bar.z_as_relative = false
	add_child(_hp_bar)

func update_hp_bar() -> void:
	if _hp_bar != null and stats != null:
		_hp_bar.update_bar(stats.current_hp, stats.max_hp)

func take_turn() -> void:
	pass

func die() -> void:
	queue_free()

func move_to(new_pos: Vector2i, duration: float = 0.08) -> void:
	grid_pos = new_pos
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(new_pos), duration)
	await tween.finished
	move_completed.emit()

func set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = _tile_center(pos)

func _tile_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
