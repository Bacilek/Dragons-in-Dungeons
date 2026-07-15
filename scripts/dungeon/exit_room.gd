class_name ExitRoom
extends Room
# The room containing the stairs down. Always planned exactly once per floor.


func _init() -> void:
	type_id = "exit"
	required = true


# Multi-entrance guarantee (multi-entrance-level-design.md §3): the stairs room
# must always have >=2 distinct incoming connections.
func min_connections() -> int:
	return 2
