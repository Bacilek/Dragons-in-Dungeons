class_name Room
extends RefCounted
# NOT Resource — pure generation-time data, never serialized, never inspected in-editor
# (see docs/architecture/DUNGEON_GENERATION_ARCHITECTURE.md §3).
#
# Base class for planned dungeon rooms. FloorPlanner decides *which* rooms exist
# (identity/count), a builder (e.g. BspBuilder) decides *where* they go (geometry),
# and LevelPainter calls paint() on each room after carving.
# Concrete types live in their own files so each gets a global class_name:
# standard_room.gd, entrance_room.gd, exit_room.gd.

var type_id: String = ""
var rect: Rect2i = Rect2i()          # assigned during Build; empty until then
var connections: Array[Room] = []    # populated during Build
var required: bool = false           # true only for Entrance/Exit


func min_size() -> Vector2i:
	return Vector2i(5, 5)


func max_size() -> Vector2i:
	return Vector2i(11, 11)


func max_connections() -> int:
	return 4


# Invariant for every room type: min_connections() <= max_connections()
# (multi-entrance-level-design.md §3). Builders read this generically —
# never special-case on type_id.
func min_connections() -> int:
	return 1


func paint(_data: DungeonData, _rng: RandomNumberGenerator) -> void:
	pass  # StandardRoom behavior: no-op, rect is already plain floor from Build
