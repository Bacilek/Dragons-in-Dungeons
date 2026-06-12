class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const ATLAS_ORIGIN := Vector2i(0, 0)
const SOURCE_FLOOR: int = 0
const SOURCE_WALL: int = 1
const SOURCE_STAIRS: int = 2
const SPRITES_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"

const ENEMY_COUNT_MIN: int = 3
const ENEMY_COUNT_MAX: int = 5
const FOV_RADIUS: int = 6

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _data: DungeonData
var _player: Player
var _enemies: Array[Enemy] = []

var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_sprite: Sprite2D
var _explored: Dictionary = {}  # Vector2i → bool

func _ready() -> void:
	_setup_tileset()
	_load_floor()

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_add_tile_source(tile_set, SOURCE_FLOOR,  SPRITES_PATH + "floor_1.png")
	_add_tile_source(tile_set, SOURCE_WALL,   SPRITES_PATH + "wall_mid.png")
	_add_tile_source(tile_set, SOURCE_STAIRS, SPRITES_PATH + "floor_stairs.png")
	tilemap.tile_set = tile_set

func _add_tile_source(tile_set: TileSet, source_id: int, path: String) -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(path)
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(ATLAS_ORIGIN)
	tile_set.add_source(atlas, source_id)

func _load_floor() -> void:
	# Clean up enemies from previous floor
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	TurnManager.clear_enemies()
	TurnManager.reset()

	_data = DungeonGenerator.generate(GameState.run_seed, GameState.current_floor)

	tilemap.clear()
	for y in _data.height:
		for x in _data.width:
			var tile: DungeonData.TileType = _data.grid[y][x]
			match tile:
				DungeonData.TileType.FLOOR:
					tilemap.set_cell(Vector2i(x, y), SOURCE_FLOOR, ATLAS_ORIGIN)
				DungeonData.TileType.WALL:
					tilemap.set_cell(Vector2i(x, y), SOURCE_WALL, ATLAS_ORIGIN)
				DungeonData.TileType.STAIRS_DOWN:
					tilemap.set_cell(Vector2i(x, y), SOURCE_STAIRS, ATLAS_ORIGIN)

	# Spawn player on first load; reuse the same instance on subsequent floors
	if _player == null:
		var player_scene: PackedScene = preload("res://scenes/game/player.tscn")
		_player = player_scene.instantiate() as Player
		entities.add_child(_player)

	_player._dungeon_floor = self
	_player.stats = GameState.player_stats
	_player.set_grid_pos(_data.player_start)

	_spawn_enemies()
	_setup_fog()
	update_fog(_data.player_start)

func _spawn_enemies() -> void:
	# Collect candidate floor tiles (not player start, not stairs)
	var candidates: Array = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) == DungeonData.TileType.FLOOR:
				if pos != _data.player_start and pos != _data.stairs_pos:
					candidates.append(pos)
	candidates.shuffle()

	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var count: int = randi_range(ENEMY_COUNT_MIN, ENEMY_COUNT_MAX)
	count = mini(count, candidates.size())

	for i in count:
		var enemy: Enemy = enemy_scene.instantiate() as Enemy
		enemy._dungeon_floor = self
		entities.add_child(enemy)
		enemy.set_grid_pos(candidates[i])
		_enemies.append(enemy)
		TurnManager.register_enemy(enemy)

func _setup_fog() -> void:
	# Remove old fog sprite if reloading floor
	if _fog_sprite != null and is_instance_valid(_fog_sprite):
		_fog_sprite.queue_free()

	_explored.clear()
	_fog_image = Image.create(_data.width, _data.height, false, Image.FORMAT_RGBA8)
	_fog_image.fill(Color(0, 0, 0, 1.0))
	_fog_texture = ImageTexture.create_from_image(_fog_image)

	_fog_sprite = Sprite2D.new()
	_fog_sprite.texture = _fog_texture
	_fog_sprite.centered = false
	_fog_sprite.scale = Vector2(TILE_SIZE, TILE_SIZE)
	_fog_sprite.z_index = 2
	_fog_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	add_child(_fog_sprite)

func update_fog(player_pos: Vector2i) -> void:
	var r2: int = FOV_RADIUS * FOV_RADIUS
	for y: int in _data.height:
		for x: int in _data.width:
			var dx: int = x - player_pos.x
			var dy: int = y - player_pos.y
			if dx * dx + dy * dy <= r2:
				_explored[Vector2i(x, y)] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif _explored.get(Vector2i(x, y), false):
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0.65))
			else:
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 1.0))
	_fog_texture.update(_fog_image)
	_update_enemy_visibility(player_pos, r2)

func _update_enemy_visibility(player_pos: Vector2i, r2: int) -> void:
	for enemy in _enemies:
		if is_instance_valid(enemy):
			var dx := enemy.grid_pos.x - player_pos.x
			var dy := enemy.grid_pos.y - player_pos.y
			enemy.visible = (dx * dx + dy * dy) <= r2

func is_walkable(pos: Vector2i) -> bool:
	return _data.is_walkable(pos)

func is_walkable_for_enemy(pos: Vector2i) -> bool:
	if not _data.is_walkable(pos):
		return false
	if _player != null and _player.grid_pos == pos:
		return false
	for e in _enemies:
		if is_instance_valid(e) and e.grid_pos == pos:
			return false
	return true

func get_enemy_at(pos: Vector2i) -> Enemy:
	for e in _enemies:
		if is_instance_valid(e) and e.grid_pos == pos:
			return e as Enemy
	return null

func get_player() -> Player:
	return _player

func remove_enemy(enemy: Enemy) -> void:
	_enemies.erase(enemy)
	TurnManager.unregister_enemy(enemy)

func get_tile_type(pos: Vector2i) -> DungeonData.TileType:
	return _data.get_tile(pos.x, pos.y)

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not _explored.get(to, false):
		return []
	if not _data.is_walkable(to) and get_enemy_at(to) == null:
		return []

	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {}
	came_from[from] = from
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]

	while not queue.is_empty():
		var current: Vector2i = queue.pop_front()
		if current == to:
			break
		for d: Vector2i in dirs:
			var nxt: Vector2i = current + d
			if came_from.has(nxt):
				continue
			if not _explored.get(nxt, false):
				continue
			if _data.is_walkable(nxt) or nxt == to:
				came_from[nxt] = current
				queue.append(nxt)

	if not came_from.has(to):
		return []

	var path: Array[Vector2i] = []
	var cur: Vector2i = to
	while cur != from:
		path.push_front(cur)
		cur = came_from[cur]
	return path

func on_player_reached_stairs() -> void:
	GameState.advance_floor()
	_load_floor()
