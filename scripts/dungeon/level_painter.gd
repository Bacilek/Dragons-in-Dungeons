class_name LevelPainter
extends RefCounted
# Paint phase of the generation pipeline (architecture doc §2.3). Two sub-steps,
# both mutating data.grid in place:
#   1. Per-room paint — room.paint(data, rng) for each planned room (all no-ops
#      in Phase 1: only Entrance/Exit/Standard exist and none override paint()).
#   2. Level-wide overlays — pillars/chasms/water/mud/grass, moved VERBATIM from
#      the pre-refactor dungeon_generator.gd (same rng call order, byte-identical
#      output per §8 step 1).
#
# KNOWN BUG, DELIBERATELY PRESERVED IN PHASE 1: the two `dirs4.shuffle()` calls in
# _place_water_mud/_place_grass_clusters use the UNSEEDED global RNG (see
# docs/architecture/SEEDED_FLOOR_POPULATION.md §1.1). Fixing them is Phase 2's
# job — Phase 1 must reproduce today's behavior exactly, bugs included.
#
# `feeling` is accepted and ignored so Phase 2 (feeling multipliers) doesn't have
# to change this signature.
# _is_connected() lives here (not shared with BspBuilder) because its only
# callers are _place_pillars/_place_chasms — no duplication needed.


static func paint(data: DungeonData, rooms: Array, rng: RandomNumberGenerator, _feeling: String) -> void:
	# Per-room paint first (§2.3 step 1). All Phase 1 room types are no-ops that
	# consume zero rng calls, so this cannot perturb the seeded stream.
	for room in rooms:
		(room as Room).paint(data, rng)

	# Level-wide overlays (§2.3 step 2) — same order as the old generate().
	_place_pillars(data, rng)
	_place_chasms(data, rng)
	_place_water_mud(data, rng)
	_place_grass_clusters(data, rng)


static func _place_pillars(data: DungeonData, rng: RandomNumberGenerator) -> void:
	for room_entry in data.rooms:
		var r: Rect2i = room_entry
		if r.size.x < 7 or r.size.y < 7:
			continue

		# Inner zone: at least 2 tiles from every room edge — avoids corridor mouths
		var candidates: Array = []
		for y: int in range(r.position.y + 2, r.position.y + r.size.y - 2):
			for x: int in range(r.position.x + 2, r.position.x + r.size.x - 2):
				candidates.append(Vector2i(x, y))

		# Fisher-Yates shuffle using the seeded rng
		for i: int in range(candidates.size() - 1, 0, -1):
			var j: int = rng.randi_range(0, i)
			var tmp = candidates[i]
			candidates[i] = candidates[j]
			candidates[j] = tmp

		var max_p: int = clampi(r.size.x * r.size.y / 40, 1, 4)
		var placed: Array = []

		for cand in candidates:
			if placed.size() >= max_p:
				break
			var cp: Vector2i = cand
			if cp == data.player_start or cp == data.stairs_pos:
				continue
			# Enforce minimum Chebyshev spacing of 3 between pillars
			var too_close: bool = false
			for prev in placed:
				var pp: Vector2i = prev
				if maxi(abs(cp.x - pp.x), abs(cp.y - pp.y)) < 3:
					too_close = true
					break
			if too_close:
				continue
			# Place pillar and verify stairs remain reachable; revert if not
			data.grid[cp.y][cp.x] = DungeonData.TileType.WALL
			if _is_connected(data):
				placed.append(cp)
			else:
				data.grid[cp.y][cp.x] = DungeonData.TileType.FLOOR


static func _is_connected(data: DungeonData) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [data.player_start]
	visited[data.player_start] = true
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == data.stairs_pos:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if not visited.has(nxt) and data.is_walkable(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return false


static func _place_chasms(data: DungeonData, rng: RandomNumberGenerator) -> void:
	# Chasms are rare — 40% chance to skip entirely
	if rng.randf() < 0.40:
		return
	# Only in large rooms
	var large_rooms: Array = []
	for room_entry in data.rooms:
		var r: Rect2i = room_entry
		if r.size.x >= 7 and r.size.y >= 7:
			large_rooms.append(r)
	if large_rooms.is_empty():
		return
	# Pick 1–2 rooms for chasm clusters
	for i: int in range(large_rooms.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp = large_rooms[i]; large_rooms[i] = large_rooms[j]; large_rooms[j] = tmp
	var num_clusters: int = rng.randi_range(1, mini(2, large_rooms.size()))
	var dirs4: Array = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	for ci: int in num_clusters:
		var r: Rect2i = large_rooms[ci]
		# Seed 2+ tiles from room edges
		var inner: Array = []
		for y: int in range(r.position.y + 2, r.position.y + r.size.y - 2):
			for x: int in range(r.position.x + 2, r.position.x + r.size.x - 2):
				var pos: Vector2i = Vector2i(x, y)
				if pos != data.player_start and pos != data.stairs_pos and data.grid[y][x] == DungeonData.TileType.FLOOR:
					inner.append(pos)
		if inner.is_empty():
			continue
		var seed: Vector2i = inner[rng.randi_range(0, inner.size() - 1)]
		var max_size: int = rng.randi_range(5, 10)
		var queue: Array = [seed]
		var placed: Array = []
		data.grid[seed.y][seed.x] = DungeonData.TileType.CHASM
		placed.append(seed)
		while not queue.is_empty() and placed.size() < max_size:
			var cur: Vector2i = queue.pop_front()
			for _d in dirs4:
				var d: Vector2i = _d
				if placed.size() >= max_size:
					break
				var nxt: Vector2i = cur + d
				if nxt == data.player_start or nxt == data.stairs_pos:
					continue
				if data.grid[nxt.y][nxt.x] != DungeonData.TileType.FLOOR:
					continue
				# Stay 2+ tiles from room edges
				if nxt.x <= r.position.x + 1 or nxt.x >= r.position.x + r.size.x - 2 \
				   or nxt.y <= r.position.y + 1 or nxt.y >= r.position.y + r.size.y - 2:
					continue
				if rng.randf() < 0.65:
					data.grid[nxt.y][nxt.x] = DungeonData.TileType.CHASM
					placed.append(nxt)
					queue.append(nxt)
		# Revert whole cluster if it blocks connectivity
		if not _is_connected(data):
			for p in placed:
				var pv: Vector2i = p
				data.grid[pv.y][pv.x] = DungeonData.TileType.FLOOR


static func _place_water_mud(data: DungeonData, rng: RandomNumberGenerator) -> void:
	var all_floor: Array = []
	for y: int in data.height:
		for x: int in data.width:
			if data.grid[y][x] == DungeonData.TileType.FLOOR:
				var pos: Vector2i = Vector2i(x, y)
				if pos != data.player_start and pos != data.stairs_pos:
					all_floor.append(pos)
	if all_floor.is_empty():
		return
	var dirs4: Array = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	# Place dedicated water clusters then mud clusters — both always appear
	var water_count: int = rng.randi_range(2, 4)
	var mud_count: int   = rng.randi_range(1, 2)
	var schedule: Array = []
	for _w: int in water_count:
		schedule.append(DungeonData.TileType.WATER)
	for _m: int in mud_count:
		schedule.append(DungeonData.TileType.MUD)
	for tile_type: DungeonData.TileType in schedule:
		if all_floor.is_empty():
			break
		var seed_idx: int = rng.randi_range(0, all_floor.size() - 1)
		var seed: Vector2i = all_floor[seed_idx]
		if data.grid[seed.y][seed.x] != DungeonData.TileType.FLOOR:
			continue
		var max_size: int = rng.randi_range(5, 12)
		var queue: Array = [seed]
		var placed_count: int = 0
		data.grid[seed.y][seed.x] = tile_type
		placed_count += 1
		while not queue.is_empty() and placed_count < max_size:
			var cur: Vector2i = queue.pop_front()
			dirs4.shuffle()
			for d in dirs4:
				var nxt: Vector2i = cur + (d as Vector2i)
				if nxt == data.player_start or nxt == data.stairs_pos:
					continue
				if data.grid[nxt.y][nxt.x] != DungeonData.TileType.FLOOR:
					continue
				if rng.randf() < 0.55:
					data.grid[nxt.y][nxt.x] = tile_type
					placed_count += 1
					queue.append(nxt)


static func _place_grass_clusters(data: DungeonData, rng: RandomNumberGenerator) -> void:
	var all_floor: Array = []
	for y: int in data.height:
		for x: int in data.width:
			if data.grid[y][x] == DungeonData.TileType.FLOOR:
				var pos: Vector2i = Vector2i(x, y)
				if pos != data.player_start and pos != data.stairs_pos:
					all_floor.append(pos)
	if all_floor.is_empty():
		return
	var dirs4: Array = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	var num_clusters: int = rng.randi_range(2, 5)
	for _c: int in num_clusters:
		if all_floor.is_empty():
			break
		var seed_idx: int = rng.randi_range(0, all_floor.size() - 1)
		var seed: Vector2i = all_floor[seed_idx]
		if data.grid[seed.y][seed.x] != DungeonData.TileType.FLOOR:
			continue
		var max_size: int = rng.randi_range(6, 14)
		var queue: Array = [seed]
		var placed_count: int = 0
		data.grid[seed.y][seed.x] = DungeonData.TileType.GRASS
		placed_count += 1
		while not queue.is_empty() and placed_count < max_size:
			var cur: Vector2i = queue.pop_front()
			dirs4.shuffle()
			for d in dirs4:
				var nxt: Vector2i = cur + (d as Vector2i)
				if nxt == data.player_start or nxt == data.stairs_pos:
					continue
				if data.grid[nxt.y][nxt.x] != DungeonData.TileType.FLOOR:
					continue
				if rng.randf() < 0.60:
					data.grid[nxt.y][nxt.x] = DungeonData.TileType.GRASS
					placed_count += 1
					queue.append(nxt)
