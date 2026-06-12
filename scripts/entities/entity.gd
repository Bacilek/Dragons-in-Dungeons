class_name Entity
extends CharacterBody2D

const TILE_SIZE: int = 16

var grid_pos: Vector2i = Vector2i.ZERO
var stats: Stats

func take_turn() -> void:
	pass

func move_to(new_pos: Vector2i) -> void:
	grid_pos = new_pos
	var tween := create_tween()
	tween.tween_property(self, "position",
		Vector2(new_pos.x * TILE_SIZE, new_pos.y * TILE_SIZE), 0.08)
	await tween.finished

func set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
