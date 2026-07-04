class_name ExitRoom
extends Room
# The room containing the stairs down. Always planned exactly once per floor.


func _init() -> void:
	type_id = "exit"
	required = true
