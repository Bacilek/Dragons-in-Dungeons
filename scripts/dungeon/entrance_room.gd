class_name EntranceRoom
extends Room
# The room the player spawns in. Always planned exactly once per floor.


func _init() -> void:
	type_id = "entrance"
	required = true
