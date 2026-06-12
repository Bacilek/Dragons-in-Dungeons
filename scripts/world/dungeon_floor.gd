class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const SOURCE_ID: int = 0
const ATLAS_FLOOR := Vector2i(0, 0)
const ATLAS_WALL := Vector2i(1, 0)
const ATLAS_STAIRS := Vector2i(2, 0)

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _data: DungeonData
var _player: Player

func _ready() -> void:
	_setup_tileset()
	_load_floor()

func _setup_tileset() -> void:
	# Build a 48×16 atlas programmatically: [floor | wall | stairs]
	var img := Image.create(48, 16, false, Image.FORMAT_RGB8)
	for y in 16:
		for x in 16:
			img.set_pixel(x, y, Color(0.23, 0.23, 0.23))       # floor — dark gray
		for x in range(16, 32):
			img.set_pixel(x, y, Color(0.10, 0.10, 0.10))       # wall — near black
		for x in range(32, 48):
			img.set_pixel(x, y, Color(0.83, 0.63, 0.09))       # stairs — gold

	var tex := ImageTexture.create_from_image(img)

	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(Vector2i(0, 0))  # floor
	atlas.create_tile(Vector2i(1, 0))  # wall
	atlas.create_tile(Vector2i(2, 0))  # stairs

	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	tile_set.add_source(atlas, SOURCE_ID)

	tilemap.tile_set = tile_set

func _load_floor() -> void:
	TurnManager.clear_enemies()

	_data = DungeonGenerator.generate(GameState.run_seed, GameState.current_floor)

	tilemap.clear()
	for y in _data.height:
		for x in _data.width:
			var tile: DungeonData.TileType = _data.grid[y][x]
			match tile:
				DungeonData.TileType.FLOOR:
					tilemap.set_cell(Vector2i(x, y), SOURCE_ID, ATLAS_FLOOR)
				DungeonData.TileType.WALL:
					tilemap.set_cell(Vector2i(x, y), SOURCE_ID, ATLAS_WALL)
				DungeonData.TileType.STAIRS_DOWN:
					tilemap.set_cell(Vector2i(x, y), SOURCE_ID, ATLAS_STAIRS)

	# Spawn player on first load; reuse the same instance on subsequent floors
	if _player == null:
		var player_scene: PackedScene = preload("res://scenes/game/player.tscn")
		_player = player_scene.instantiate() as Player
		entities.add_child(_player)

	_player._dungeon_floor = self
	_player.stats = GameState.player_stats
	_player.set_grid_pos(_data.player_start)

func is_walkable(pos: Vector2i) -> bool:
	return _data.is_walkable(pos)

func get_tile_type(pos: Vector2i) -> DungeonData.TileType:
	return _data.get_tile(pos.x, pos.y)

func on_player_reached_stairs() -> void:
	GameState.advance_floor()
	_load_floor()
