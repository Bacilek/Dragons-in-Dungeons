class_name BlacksmithRoom
extends StandardRoom
# Blacksmith special room (docs/architecture — random-weapon-crafting design worked out
# interactively, no standalone design doc). Unlike Treasure/Garden/Shop/Secret, this room is NOT
# a ROOM_POOL Bernoulli entry — it's guaranteed exactly once, only on floor 4, force-appended by
# FloorPlanner.plan() outside the pool loop entirely (mirrors how the boss room is special-cased
# outside ROOM_POOL, consuming zero extra rng draws). paint() stays a no-op guard — the room is
# plain floor; runtime content (the Blacksmith prop) is DungeonFloor._spawn_blacksmith().


func _init() -> void:
	type_id = "blacksmith"


func min_size() -> Vector2i:
	return Vector2i(5, 5)


func max_size() -> Vector2i:
	return Vector2i(7, 7)


func max_connections() -> int:
	return 1


func paint(_data: DungeonData, _rng: RandomNumberGenerator) -> void:
	if rect == Rect2i():
		return
	# No tile changes — plain floor; the override exists only for the guard/symmetry.
