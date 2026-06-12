class_name BSPNode
extends RefCounted

var rect: Rect2i
var left_child: BSPNode
var right_child: BSPNode
var room: Rect2i  # only set on leaf nodes

func _init(p_rect: Rect2i) -> void:
	rect = p_rect

func is_leaf() -> bool:
	return left_child == null and right_child == null
