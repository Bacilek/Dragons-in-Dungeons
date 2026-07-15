# TEMPORARY verification harness for Phase 3 (LOOP_BUILDER_ARCHITECTURE.md §8).
# Run:  Godot_..._console.exe --headless --path <project> --script res://scripts/dungeon/_verify/loop_check.gd
# Generates 200 floors (seeds 1-20 × floors 1-10) via LoopBuilder.build() directly
# (replicating the orchestrator's substream seeding) and asserts §8's 8 checks,
# plus the multi-entrance guarantee (multi-entrance-level-design.md §4/§6):
# entrance/exit degree >= 2 on every LoopBuilder floor, fallback-rate tracking
# for before/after comparison, and Tier C edge-disjointness telemetry.
# DELETE THIS FOLDER once the migration no longer needs it.
extends SceneTree

var fails: Array = []


func _init() -> void:
	randomize()  # prove no hidden global-RNG dependence, same as dump_gen.gd

	var fallback_count: int = 0
	var no_loop_big_floors: int = 0
	var big_floors: int = 0
	var total_loops: int = 0
	var floors_built: int = 0
	var total_forced: int = 0
	var edge_disjoint_true: int = 0

	for s: int in range(1, 21):
		for f: int in range(1, 11):
			var floor_seed: int = s ^ (f * 0x9e3779b9)
			var rng := RandomNumberGenerator.new()
			rng.seed = floor_seed
			var feeling: String = "" if f % 5 == 0 else FloorFeeling.roll(rng)
			var rooms: Array = FloorPlanner.plan(f, feeling, rng)

			var data: DungeonData = null
			var win_attempt: int = -1
			for attempt: int in 3:
				var sub_rng := RandomNumberGenerator.new()
				sub_rng.seed = floor_seed + (attempt * 0x1000193)
				data = LoopBuilder.build(rooms, sub_rng)
				if data != null:
					win_attempt = attempt
					break
			if data == null:
				fallback_count += 1  # assertion 8 tallies this; not a hard fail
				continue
			floors_built += 1
			var stats: Dictionary = LoopBuilder.last_stats.duplicate()
			var n: int = data.rooms.size()

			# --- 1. Determinism: rebuild same substream, compare grid + rooms ---
			var rng2 := RandomNumberGenerator.new()
			rng2.seed = floor_seed + (win_attempt * 0x1000193)
			var data2: DungeonData = LoopBuilder.build(rooms, rng2)
			if data2 == null or str(data2.rooms) != str(data.rooms):
				_fail(s, f, "determinism: rooms differ")
			else:
				for y: int in data.height:
					if str(data.grid[y]) != str(data2.grid[y]):
						_fail(s, f, "determinism: grid row %d differs" % y)
						break
			# data/rooms rects now reflect the rebuild — identical by determinism.

			# --- 2. No overlaps / >=2 separation ---
			for i: int in n:
				for j: int in range(i + 1, n):
					if (data2.rooms[i] as Rect2i).grow(2).intersects(data2.rooms[j] as Rect2i):
						_fail(s, f, "separation: rooms %d/%d closer than 2" % [i, j])

			# --- 3. Full connectivity: BFS reaches every room center + stairs ---
			var reached: Dictionary = _bfs_walkable(data2)
			if not reached.has(data2.stairs_pos):
				_fail(s, f, "connectivity: stairs unreachable")
			for r: Rect2i in data2.rooms:
				var c := Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)
				if not reached.has(c):
					_fail(s, f, "connectivity: room center %s unreachable" % c)

			# --- 4. Connections <-> corridors bookkeeping ---
			var deg_sum: int = 0
			for room_obj in rooms:
				var room: Room = room_obj
				deg_sum += room.connections.size()
				for other_obj in room.connections:
					var other: Room = other_obj
					if not other.connections.has(room):
						_fail(s, f, "connections not symmetric")
					if room.connections.count(other) != 1:
						_fail(s, f, "duplicate connection entry")
			var expected_edges: int = int(stats["mst_edges"]) + int(stats["loop_edges"]) \
					+ int(stats["forced_edges"])
			if int(stats["mst_edges"]) != n - 1:
				_fail(s, f, "MST edge count %d != N-1 (%d)" % [int(stats["mst_edges"]), n - 1])
			if int(stats["edge_keys"]) != expected_edges:
				_fail(s, f, "edge_keys %d != mst+loops %d" % [int(stats["edge_keys"]), expected_edges])
			if deg_sum != expected_edges * 2:
				_fail(s, f, "sum(deg) %d != 2*edges %d" % [deg_sum, expected_edges * 2])

			# --- 5. Loops actually exist (soft: tallied, reported) ---
			total_loops += int(stats["loop_edges"])
			if n >= 8:
				big_floors += 1
				if int(stats["loop_edges"]) == 0:
					no_loop_big_floors += 1

			# --- 6. Entrance/Exit pacing: max pairwise center distance ---
			var entrance: Room = null
			var exit_room: Room = null
			for room_obj in rooms:
				if room_obj is EntranceRoom:
					entrance = room_obj
				elif room_obj is ExitRoom:
					exit_room = room_obj
			var ee_dist: int = _mdist(_rc(entrance.rect), _rc(exit_room.rect))
			var max_dist: int = 0
			for i: int in n:
				for j: int in range(i + 1, n):
					max_dist = maxi(max_dist, _mdist(_rc(data2.rooms[i]), _rc(data2.rooms[j])))
			if ee_dist != max_dist:
				_fail(s, f, "pacing: entrance/exit dist %d != max %d" % [ee_dist, max_dist])
			if data2.start_room != entrance.rect:
				_fail(s, f, "start_room != entrance rect")
			if not exit_room.rect.has_point(data2.stairs_pos):
				_fail(s, f, "stairs not inside exit room")

			# --- 9. Multi-entrance guarantee (multi-entrance-level-design.md §4):
			# entrance/exit degree >= 2 on every floor LoopBuilder builds ---
			var ent_deg: int = int(stats.get("entrance_degree", -1))
			var exit_deg: int = int(stats.get("exit_degree", -1))
			if ent_deg < 2:
				_fail(s, f, "entrance degree %d < 2" % ent_deg)
			if exit_deg < 2:
				_fail(s, f, "exit degree %d < 2" % exit_deg)
			total_forced += int(stats.get("forced_edges", 0))
			# Tier C telemetry — informational only, deliberately NOT asserted
			# (measured-not-enforced per the design doc §2/§6).
			if bool(stats.get("edge_disjoint_start_exit", false)):
				edge_disjoint_true += 1

	# --- 7. Boss floors via FULL orchestration (floors 5, 10 per seed) ---
	for s: int in range(1, 21):
		for f: int in [5, 10]:
			var d: DungeonData = DungeonGenerator.generate(s, f)
			if d.boss_room == Rect2i():
				_fail(s, f, "boss_room empty on boss floor")
			elif not d.boss_room.has_point(d.stairs_pos):
				_fail(s, f, "boss_room does not contain stairs")

	# --- End-to-end smoke + loop-visibility check through generate() ---
	var e2e_loops: int = 0
	for pair: Array in [[12345, 1], [12345, 3], [98765, 7], [555, 10], [-42, 2], [7, 4], [7, 8]]:
		var d: DungeonData = DungeonGenerator.generate(pair[0], pair[1])
		if d == null or d.rooms.is_empty() or d.grid.is_empty() \
				or d.player_start == Vector2i() or d.stairs_pos == Vector2i():
			_fail(pair[0], pair[1], "e2e: DungeonData not fully populated")
		if int(LoopBuilder.last_stats.get("loop_edges", 0)) > 0:
			e2e_loops += 1

	print("=== loop_check results ===")
	print("floors built by LoopBuilder: %d / 200" % floors_built)
	print("assertion 8 - fallback count: %d (expected 0-1; >4 means lower the room budget)" % fallback_count)
	print("assertion 5 - big floors (>=8 rooms): %d, of which 0-loop: %d; total loop edges: %d" % [big_floors, no_loop_big_floors, total_loops])
	print("multi-entrance - LoopBuilder fallback rate (for before/after comparison): %d / 200 floors fell back to BSP" % fallback_count)
	print("multi-entrance - forced edges added across all successful floors: %d" % total_forced)
	print("multi-entrance - Tier C edge-disjoint start<->exit (informational, not asserted): %d / %d successful floors" % [edge_disjoint_true, floors_built])
	print("e2e generate() runs with >=1 loop edge: %d / 7" % e2e_loops)
	if fails.is_empty():
		print("ALL HARD ASSERTIONS PASSED")
	else:
		print("FAILURES (%d):" % fails.size())
		for msg: String in fails:
			print("  " + msg)
	quit(0 if fails.is_empty() else 1)


func _fail(s: int, f: int, msg: String) -> void:
	fails.append("seed=%d floor=%d: %s" % [s, f, msg])


func _rc(r: Rect2i) -> Vector2i:
	return Vector2i(r.position.x + r.size.x / 2, r.position.y + r.size.y / 2)


func _mdist(a: Vector2i, b: Vector2i) -> int:
	return absi(a.x - b.x) + absi(a.y - b.y)


func _bfs_walkable(data: DungeonData) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array = [data.player_start]
	visited[data.player_start] = true
	var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d in dirs:
			var nxt: Vector2i = cur + (d as Vector2i)
			if not visited.has(nxt) and data.is_walkable(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return visited
