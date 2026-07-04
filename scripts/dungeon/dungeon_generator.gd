class_name DungeonGenerator
extends RefCounted
# Thin orchestrator for the three-phase generation pipeline
# (docs/architecture/DUNGEON_GENERATION_ARCHITECTURE.md):
#   Initialize (FloorPlanner.plan) → Build (LoopBuilder, BspBuilder fallback)
#   → Paint (LevelPainter.paint)
# The public generate(seed_val, floor_num) signature is unchanged — the single
# call site in DungeonFloor._load_floor() needs no modification.
#
# Phase 2 (§8 step 3): Floor Feelings are rolled here, FIRST in the seeded call
# sequence — FloorFeeling.roll() consumes 1–2 rng calls, so its position in the
# stream is load-bearing for reproducibility. Boss floors never roll a feeling
# (this orchestrator already knows floor_num % 5 == 0; roll() stays floor-agnostic).
#
# Phase 3 (LOOP_BUILDER_ARCHITECTURE.md §5–§6): LoopBuilder is the primary
# builder. It gets BUILDER_RETRIES calls, each on a FRESH deterministic rng
# substream (floor_seed + attempt * 0x1000193) so the main rng stream position
# is identical whether LoopBuilder succeeds on attempt 1, 3, or not at all.
# On exhaustion, BspBuilder.build() runs on the SAME planned rooms list (no
# re-plan — BspBuilder ignores list content and never fails) using the MAIN rng.
# boss_room is assigned builder-agnostically: the room containing stairs_pos.

const BUILDER_RETRIES: int = 3   # total LoopBuilder.build() calls before fallback


static func generate(seed_val: int, floor_num: int) -> DungeonData:
	var floor_seed: int = seed_val ^ (floor_num * 0x9e3779b9)
	var rng := RandomNumberGenerator.new()
	rng.seed = floor_seed

	var is_boss_floor: bool = floor_num % 5 == 0
	var feeling: String = "" if is_boss_floor else FloorFeeling.roll(rng)

	# Initialize — what rooms exist. Phase 3: consumes 1 rng call (room budget).
	var rooms: Array = FloorPlanner.plan(floor_num, feeling, rng)

	# Build — LoopBuilder with retries on fresh substreams, then Bsp fallback.
	var data: DungeonData = null
	for attempt: int in BUILDER_RETRIES:
		var sub_rng := RandomNumberGenerator.new()
		sub_rng.seed = floor_seed + (attempt * 0x1000193)
		data = LoopBuilder.build(rooms, sub_rng)
		if data != null:
			break

	if data == null:
		# Guaranteed-success fallback (Dungeon doc §7). Same rooms list, main rng.
		data = BspBuilder.build(rooms, rng)

		if data.rooms.is_empty():
			var fallback := Rect2i(10, 10, 10, 10)
			BspBuilder._carve_rect(fallback, data)
			data.rooms.append(fallback)

		# BSP keeps the legacy heuristics: start = smallest room,
		# stairs = Manhattan-farthest room from start.
		var start_room: Rect2i = data.rooms[0]
		for room: Rect2i in data.rooms:
			if room.get_area() < start_room.get_area():
				start_room = room
		data.start_room = start_room
		data.player_start = Vector2i(
			clampi(start_room.position.x + start_room.size.x / 2, 1, data.width - 2),
			clampi(start_room.position.y + start_room.size.y / 2, 1, data.height - 2)
		)

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

		# Tag the planned Entrance/Exit rooms with their resolved geometry
		# (LoopBuilder does this itself; the fallback must too).
		for room_obj in rooms:
			if room_obj is EntranceRoom:
				(room_obj as Room).rect = start_room
			elif room_obj is ExitRoom:
				(room_obj as Room).rect = farthest_room

	# Boss room — builder-agnostic (LOOP_BUILDER_ARCHITECTURE.md §5): the room
	# containing the stairs. For BspBuilder output this is exactly the old
	# "farthest room" (stairs_pos is that room's clamped center, rooms never
	# overlap, and the clamp is a no-op for rects inside the 1-tile border).
	if is_boss_floor and data.boss_room == Rect2i():
		for r: Rect2i in data.rooms:
			if r.has_point(data.stairs_pos):
				data.boss_room = r
				break

	data.feeling = feeling

	# Paint — per-room paint (all no-ops currently) + level-wide overlays.
	LevelPainter.paint(data, rooms, rng, feeling)

	return data
