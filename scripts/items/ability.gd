class_name Ability
extends Resource

# Unique string ID used by player.gd to dispatch activation logic.
@export var ability_id: String = ""
@export var ability_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var uses_remaining: int = 0
@export var uses_max: int = 0
# For toggle abilities (e.g. Reckless Attack): true while toggled on.
@export var is_active: bool = false
# Passive abilities are shown only in the talent screen, never placed in the ability bar.
@export var is_passive: bool = false

func get_display_name() -> String:
	return ability_name

func has_uses() -> bool:
	return uses_max == 0 or uses_remaining > 0  # uses_max == 0 means infinite
