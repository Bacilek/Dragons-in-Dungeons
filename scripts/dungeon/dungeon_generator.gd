class_name DungeonGenerator
extends RefCounted
# Thin orchestrator for the three-phase generation pipeline
# (docs/architecture/DUNGEON_GENERATION_ARCHITECTURE.md):
#   Initialize (FloorPlanner.plan) → Build (BspBuilder.build) → Paint (LevelPainter.paint)
# The public generate(seed_val, floor_num) signature is unchanged — the single
# call site in DungeonFloor._load_floor() needs no modification.
#
# Phase 2 (§8 step 3): Floor Feelings are rolled here, FIRST in the seeded call
# sequence — FloorFeeling.roll() consumes 1–2 rng calls, so its position in the
# stream is load-bearing for reproducibility. Boss floors never roll a feeling
# (this orchestrator already knows floor_num % 5 == 0; roll() stays floor-agnostic).


static func generate(seed_val: int, floor_num: int) -> DungeonData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ (floor_num * 0x9e3779b9)

	var is_boss_floor: bool = floor_num % 5 == 0
	var feeling: String = "" if is_boss_floor else FloorFeeling.roll(rng)

	# Initialize — what rooms exist (still makes zero rng calls, see floor_planner.gd).
	var rooms: Array = FloorPlanner.plan(floor_num, feeling, rng)

	# Build — carve rooms + corridors into a fresh DungeonData.
	var data: DungeonData = BspBuilder.build(rooms, rng)

	if data.rooms.is_empty():
		var fallback := Rect2i(10, 10, 10, 10)
		BspBuilder._carve_rect(fallback, data)
		data.rooms.append(fallback)

	# Player start = center of smallest room (most constrained, interesting start)
	var start_room: Rect2i = data.rooms[0]
	for room: Rect2i in data.rooms:
		if room.get_area() < start_room.get_area():
			start_room = room
	data.start_room = start_room
	data.player_start = Vector2i(
		clampi(start_room.position.x + start_room.size.x / 2, 1, data.width - 2),
		clampi(start_room.position.y + start_room.size.y / 2, 1, data.height - 2)
	)

	# Stairs = center of room farthest from player start (Manhattan)
	var farthest_room: Rect2i = data.rooms[0]
	var farthest_dist: int = 0
	for room: Rect2i in data.rooms:
		var center := Vector2i(
			room.position.x + room.size.x / 2,
			room.position.y + room.size.y / 2
		)
		var dist: int = abs(center.x - data.player_start.x) + abs(center.y - data.player_start.y)
		if dist > farthest_dist:
			farthest_dist = dist
			farthest_room = room

	data.stairs_pos = Vector2i(
		clampi(farthest_room.position.x + farthest_room.size.x / 2, 1, data.width - 2),
		clampi(farthest_room.position.y + farthest_room.size.y / 2, 1, data.height - 2)
	)
	data.grid[data.stairs_pos.y][data.stairs_pos.x] = DungeonData.TileType.STAIRS_DOWN

	if is_boss_floor:
		data.boss_room = farthest_room

	data.feeling = feeling

	# Tag the planned Entrance/Exit rooms with their resolved geometry (no rng impact).
	for room_obj in rooms:
		if room_obj is EntranceRoom:
			(room_obj as Room).rect = start_room
		elif room_obj is ExitRoom:
			(room_obj as Room).rect = farthest_room

	# Paint — per-room paint (all no-ops currently) + level-wide overlays.
	LevelPainter.paint(data, rooms, rng, feeling)

	return data
