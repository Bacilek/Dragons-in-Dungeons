class_name SecretRoom
extends StandardRoom
# Dead-end room (special-rooms-economy-design.md §4.4, session 7f) whose one connecting door is
# hidden — rendered as a plain wall, impassable, invisible until found via the existing Ctrl
# search verb. Smallest of the four special rooms (5x5-6x6, stays inside the builders' 5-11
# range). paint() stays a no-op guard — content is the runtime hidden door + reward, not terrain.
# Runtime content is DungeonFloor._spawn_secret_room()/_reveal_secret_door() (scripts/world/CLAUDE.md).


func _init() -> void:
	type_id = "secret"


func min_size() -> Vector2i:
	return Vector2i(5, 5)


func max_size() -> Vector2i:
	return Vector2i(6, 6)


func max_connections() -> int:
	return 1


func paint(_data: DungeonData, _rng: RandomNumberGenerator) -> void:
	if rect == Rect2i():
		return
	# No tile changes — content is the runtime hidden door + reward, not terrain.
