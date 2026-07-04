class_name BspBuilder
extends RefCounted
# Build phase of the generation pipeline (architecture doc §2.2):
# takes the planned room list, returns a DungeonData with grid (FLOOR/WALL room +
# corridor shapes only — no water/grass/pillars, that's LevelPainter) and rooms set.
#
# All carving logic here is moved VERBATIM from the pre-refactor
# dungeon_generator.gd — same helpers, same rng call order — so output stays
# byte-identical (§8 step 1). BspBuilder is the guaranteed-success fallback
# builder; it never returns null.

const GRID_WIDTH: int = 48
const GRID_HEIGHT: int = 48
const MIN_ROOM_SIZE: int = 5
const MAX_ROOM_DIM: int = 11
const MAX_DEPTH: int = 6


# PHASE 1 NOTE: BSP determines room count and geometry itself, exactly like the
# pre-refactor generator — the planned `rooms` list is NOT consumed as a hard
# constraint (its Entrance/Exit rects are assigned post-hoc by the orchestrator).
# Consuming the plan (placing planned rooms into BSP leaves) is Phase 2+ work.
static func build(_rooms: Array, rng: RandomNumberGenerator) -> DungeonData:
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
	var bsp_pairs: Dictionary = {}
	_connect_bsp(root, data, bsp_pairs)
	_collect_rooms(root, data.rooms)
	_add_room_extensions(data, rng)
	_add_extra_corridors(data, rng, bsp_pairs)

	return data


static func _split_bsp(node: BSPNode, depth: int, rng: RandomNumberGenerator) -> void:
	var min_size := MIN_ROOM_SIZE * 2 + 2

	if depth >= MAX_DEPTH or node.rect.size.x < min_size or node.rect.size.y < min_size:
		# Leaf — carve a room with random margins inside this rect
		var margin_x := rng.randi_range(2, maxi(2, node.rect.size.x / 4))
		var margin_y := rng.randi_range(2, maxi(2, node.rect.size.y / 4))
		var rw := mini(maxi(MIN_ROOM_SIZE, node.rect.size.x - margin_x * 2), MAX_ROOM_DIM)
		var rh := mini(maxi(MIN_ROOM_SIZE, node.rect.size.y - margin_y * 2), MAX_ROOM_DIM)
		var room_x: int = node.rect.position.x + margin_x
		var room_y: int = node.rect.position.y + margin_y
		rw = maxi(1, mini(rw, GRID_WIDTH - 1 - room_x))
		rh = maxi(1, mini(rh, GRID_HEIGHT - 1 - room_y))
		node.room = Rect2i(room_x, room_y, rw, rh)
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


static func _pair_key(a: Vector2i, b: Vector2i) -> String:
	if a.x < b.x or (a.x == b.x and a.y <= b.y):
		return "%d,%d|%d,%d" % [a.x, a.y, b.x, b.y]
	return "%d,%d|%d,%d" % [b.x, b.y, a.x, a.y]


static func _connect_bsp(node: BSPNode, data: DungeonData, bsp_pairs: Dictionary) -> void:
	if node.is_leaf():
		return
	_connect_bsp(node.left_child, data, bsp_pairs)
	_connect_bsp(node.right_child, data, bsp_pairs)
	var a := _get_room_center(node.left_child)
	var b := _get_room_center(node.right_child)
	bsp_pairs[_pair_key(a, b)] = true
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


static func _add_room_extensions(data: DungeonData, rng: RandomNumberGenerator) -> void:
	for room_entry in data.rooms:
		var r: Rect2i = room_entry
		if rng.randf() >= 0.40:
			continue
		var side: int = rng.randi_range(0, 3)
		var ext_w: int = rng.randi_range(2, mini(4, maxi(2, r.size.x - 2)))
		var ext_h: int = rng.randi_range(2, 3)
		var ext: Rect2i
		match side:
			0:  # North
				var x: int = r.position.x + rng.randi_range(1, maxi(1, r.size.x - ext_w - 1))
				ext = Rect2i(x, r.position.y - ext_h, ext_w, ext_h)
			1:  # South
				var x: int = r.position.x + rng.randi_range(1, maxi(1, r.size.x - ext_w - 1))
				ext = Rect2i(x, r.position.y + r.size.y, ext_w, ext_h)
			2:  # West
				var y: int = r.position.y + rng.randi_range(1, maxi(1, r.size.y - ext_h - 1))
				ext = Rect2i(r.position.x - ext_w, y, ext_w, ext_h)
			_:  # East
				var y: int = r.position.y + rng.randi_range(1, maxi(1, r.size.y - ext_h - 1))
				ext = Rect2i(r.position.x + r.size.x, y, ext_w, ext_h)
		ext = ext.intersection(Rect2i(1, 1, GRID_WIDTH - 2, GRID_HEIGHT - 2))
		if ext.size.x > 0 and ext.size.y > 0:
			_carve_rect(ext, data)


static func _add_extra_corridors(data: DungeonData, rng: RandomNumberGenerator, bsp_pairs: Dictionary) -> void:
	if data.rooms.size() < 3:
		return
	var num_extra: int = rng.randi_range(2, 3)
	for _i: int in num_extra:
		for _attempt: int in 8:
			var ai: int = rng.randi_range(0, data.rooms.size() - 1)
			var bi: int = rng.randi_range(0, data.rooms.size() - 1)
			if ai == bi:
				continue
			var ra: Rect2i = data.rooms[ai]
			var rb: Rect2i = data.rooms[bi]
			var ca := Vector2i(ra.position.x + ra.size.x / 2, ra.position.y + ra.size.y / 2)
			var cb := Vector2i(rb.position.x + rb.size.x / 2, rb.position.y + rb.size.y / 2)
			if bsp_pairs.has(_pair_key(ca, cb)):
				continue
			if abs(ca.x - cb.x) + abs(ca.y - cb.y) < 12:
				continue
			# Carve via the corner point (vertical-first L-shape for variety)
			var corner := Vector2i(ca.x, cb.y)
			_carve_corridor(ca, corner, data)
			_carve_corridor(corner, cb, data)
			break
