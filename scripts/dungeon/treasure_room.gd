class_name TreasureRoom
extends StandardRoom
# Vault room (special-rooms-economy-design.md §4.2, session 7c). Dead-end (max_connections() = 1)
# so locking its one door gates the room cleanly; runtime content (guaranteed loot/gold, the
# lock itself, floor >= 4 traps) is DungeonFloor._spawn_treasure() — paint() stays a no-op guard,
# a vault is plain floor.


func _init() -> void:
	type_id = "treasure"


func min_size() -> Vector2i:
	return Vector2i(5, 5)


func max_size() -> Vector2i:
	return Vector2i(7, 7)


func max_connections() -> int:
	return 1


func paint(_data: DungeonData, _rng: RandomNumberGenerator) -> void:
	if rect == Rect2i():
		return
	# No tile changes — a vault is plain floor; the override exists only for the guard/symmetry.
