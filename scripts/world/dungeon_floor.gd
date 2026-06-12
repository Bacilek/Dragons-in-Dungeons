class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const ATLAS_ORIGIN := Vector2i(0, 0)
const SOURCE_FLOOR: int = 0
const SOURCE_WALL: int = 1
const SOURCE_STAIRS: int = 2

const SPRITES_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _data: DungeonData
var _player: Player

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
	TurnManager.clear_enemies()

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

func is_walkable(pos: Vector2i) -> bool:
	return _data.is_walkable(pos)

func get_tile_type(pos: Vector2i) -> DungeonData.TileType:
	return _data.get_tile(pos.x, pos.y)

func on_player_reached_stairs() -> void:
	GameState.advance_floor()
	_load_floor()
