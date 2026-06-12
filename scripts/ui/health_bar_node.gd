class_name HealthBarNode
extends Node2D

var _ratio: float = 1.0
const BAR_WIDTH: float = 14.0
const BAR_HEIGHT: float = 3.0

func _draw() -> void:
	draw_rect(Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH, BAR_HEIGHT), Color(0.25, 0.0, 0.0))
	var fg := Color(1.0 - _ratio, _ratio * 0.85, 0.0)
	draw_rect(Rect2(-BAR_WIDTH * 0.5, 0.0, BAR_WIDTH * _ratio, BAR_HEIGHT), fg)

func update_bar(current_hp: int, max_hp: int) -> void:
	_ratio = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	queue_redraw()
