class_name Entity
extends CharacterBody2D

const TILE_SIZE: int = 16

var grid_pos: Vector2i = Vector2i.ZERO
var stats: Stats

func take_turn() -> void:
	pass

func move_to(new_pos: Vector2i, duration: float = 0.08) -> void:
	grid_pos = new_pos
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(new_pos), duration)
	await tween.finished

func set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = _tile_center(pos)

func _tile_center(pos: Vector2i) -> Vector2:
	return Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
