class_name Ability
extends Resource

# Unique string ID used by player.gd to dispatch activation logic.
@export var ability_id: String = ""
@export var ability_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var uses_remaining: int = 0
@export var uses_max: int = 0

func get_display_name() -> String:
	return ability_name

func has_uses() -> bool:
	return uses_remaining > 0
