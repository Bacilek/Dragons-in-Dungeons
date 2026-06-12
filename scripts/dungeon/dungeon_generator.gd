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
