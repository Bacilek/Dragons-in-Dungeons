class_name DungeonGenerator
extends RefCounted

const GRID_WIDTH: int = 48
const GRID_HEIGHT: int = 48
const MIN_ROOM_SIZE: int = 5
const MAX_DEPTH: int = 5

static func generate(seed_val: int, floor_num: int) -> DungeonData:
	var rng := RandomNumberGenerator.new()
	rng.seed = seed_val ^ (floor_num * 0x9e3779b9)

	var data := DungeonData.new()
	data.width = GRID_WIDTH
	data.height = GRID_HEIGHT

	# Fill with walls
	data.grid = []
	for y in GRID_HEIGHT:
		var row: Array = []
		for x in GRID_WIDTH:
			row.append(DungeonData.TileType.WALL)
		data.grid.append(row)

	# BSP partition, carve rooms, connect corridors
	var root := BSPNode.new(Rect2i(1, 1, GRID_WIDTH - 2, GRID_HEIGHT - 2))
	_split_bsp(root, 0, rng)
	_carve_rooms(root, data)
	_connect_bsp(root, data)
	_collect_rooms(root, data.rooms)

	if data.rooms.is_empty():
		var fallback := Rect2i(10, 10, 10, 10)
		_carve_rect(fallback, data)
		data.rooms.append(fallback)

	# Player start = center of first room
	var start_room: Rect2i = data.rooms[0]
	data.player_start = Vector2i(
		start_room.position.x + start_room.size.x / 2,
		start_room.position.y + start_room.size.y / 2
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
		farthest_room.position.x + farthest_room.size.x / 2,
		farthest_room.position.y + farthest_room.size.y / 2
	)
	data.grid[data.stairs_pos.y][data.stairs_pos.x] = DungeonData.TileType.STAIRS_DOWN

	if floor_num % 5 == 0:
		data.boss_room = farthest_room

	_place_pillars(data, rng)
	_place_chasms(data, rng)
	_place_water_mud(data, rng)
	_place_grass_clusters(data, rng)

	return data


static func _split_bsp(node: BSPNode, depth: int, rng: RandomNumberGenerator) -> void:
	var min_size := MIN_ROOM_SIZE * 2 + 2

	if depth >= MAX_DEPTH or node.rect.size.x < min_size or node.rect.size.y < min_size:
		# Leaf — carve a room with random margins inside this rect
		var margin_x := rng.randi_range(1, maxi(1, node.rect.size.x / 4))
		var margin_y := rng.randi_range(1, maxi(1, node.rect.size.y / 4))
		var rw := maxi(MIN_ROOM_SIZE, node.rect.size.x - margin_x * 2)
		var rh := maxi(MIN_ROOM_SIZE, node.rect.size.y - margin_y * 2)
		node.room = Rect2i(
			node.rect.position.x + margin_x,
			node.rect.position.y + margin_y,
			rw, rh
		)
		return

	# Decide split axis based on aspect ratio, randomise when square-ish
	var split_h: bool
	if node.rect.size.y > node.rect.size.x * 1.25:
		split_h = true
	elif node.rect.size.x > node.rect.size.y * 1.25:
		split_h = false
	else:
		split_h = rng.randi() % 2 == 0

	if split_h:
		var split := rng.randi_range(MIN_ROOM_SIZE + 1, node.rect.size.y - MIN_ROOM_SIZE - 1)
		node.left_child = BSPNode.new(Rect2i(
			node.rect.position.x, node.rect.position.y,
			node.rect.size.x, split
		))
		node.right_child = BSPNode.new(Rect2i(
			node.rect.position.x, node.rect.position.y + split,
			node.rect.size.x, node.rect.size.y - split
		))
	else:
		var split := rng.randi_range(MIN_ROOM_SIZE + 1, node.rect.size.x - MIN_ROOM_SIZE - 1)
		node.left_child = BSPNode.new(Rect2i(
			node.rect.position.x, node.rect.position.y,
			split, node.rect.size.y
		))
		node.right_child = BSPNode.new(Rect2i(
			node.rect.position.x + split, node.rect.position.y,
			node.rect.size.x - split, node.rect.size.y
		))

	_split_bsp(node.left_child, depth + 1, rng)
	_split_bsp(node.right_child, depth + 1, rng)


static func _carve_rooms(node: BSPNode, data: DungeonData) -> void:
	if node.is_leaf():
		_carve_rect(node.room, data)
		return
	if node.left_child:
		_carve_rooms(node.left_child, data)
	if node.right_child:
		_carve_rooms(node.right_child, data)


static func _carve_rect(rect: Rect2i, data: DungeonData) -> void:
	for y in range(rect.position.y, rect.position.y + rect.size.y):
		for x in range(rect.position.x, rect.position.x + rect.size.x):
			if y >= 0 and y < data.height and x >= 0 and x < data.width:
				data.grid[y][x] = DungeonData.TileType.FLOOR


static func _connect_bsp(node: BSPNode, data: DungeonData) -> void:
	if node.is_leaf():
		return
	_connect_bsp(node.left_child, data)
	_connect_bsp(node.right_child, data)
	var a := _get_room_center(node.left_child)
	var b := _get_room_center(node.right_child)
	_carve_corridor(a, b, data)


static func _get_room_center(node: BSPNode) -> Vector2i:
	if node.is_leaf():
		return Vector2i(
			node.room.position.x + node.room.size.x / 2,
			node.room.position.y + node.room.size.y / 2
		)
	return _get_room_center(node.left_child)


static func _carve_corridor(a: Vector2i, b: Vector2i, data: DungeonData) -> void:
	# L-shaped: horizontal segment first, then vertical
	var x := a.x
	var step_x := 1 if b.x >= a.x else -1
	while x != b.x:
		if x >= 0 and x < data.width and a.y >= 0 and a.y < data.height:
			if data.grid[a.y][x] == DungeonData.TileType.WALL:
				data.grid[a.y][x] = DungeonData.TileType.FLOOR
		x += step_x

	var y := a.y
	var step_y := 1 if b.y >= a.y else -1
	while y != b.y + step_y:
		if b.x >= 0 and b.x < data.width and y >= 0 and y < data.height:
			if data.grid[y][b.x] == DungeonData.TileType.WALL:
				data.grid[y][b.x] = DungeonData.TileType.FLOOR
		y += step_y


static func _collect_rooms(node: BSPNode, rooms: Array) -> void:
	if node.is_leaf():
		rooms.append(node.room)
		return
	if node.left_child:
		_collect_rooms(node.left_child, rooms)
	if node.right_child:
		_collect_rooms(node.right_child, rooms)


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
	# Place dedicated water clusters (1-2) then mud clusters (1-2) — both always appear
	var water_count: int = rng.randi_range(1, 2)
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
		var max_size: int = rng.randi_range(4, 9)
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
