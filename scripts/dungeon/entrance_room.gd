class_name EntranceRoom
extends Room
# The room the player spawns in. Always planned exactly once per floor.


func _init() -> void:
	type_id = "entrance"
	required = true


# Multi-entrance guarantee (multi-entrance-level-design.md §3): the player must
# always have >=2 distinct routes out of the spawn room.
func min_connections() -> int:
	return 2
