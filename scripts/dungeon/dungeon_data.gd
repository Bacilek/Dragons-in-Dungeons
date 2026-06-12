class_name DungeonData
extends Resource

enum TileType { VOID = 0, FLOOR = 1, WALL = 2, STAIRS_DOWN = 3 }

var grid: Array = []        # grid[y][x] → TileType int
var rooms: Array = []       # Array[Rect2i]
var player_start: Vector2i = Vector2i.ZERO
var stairs_pos: Vector2i = Vector2i.ZERO
var width: int = 0
var height: int = 0

func get_tile(x: int, y: int) -> TileType:
	if x < 0 or y < 0 or x >= width or y >= height:
		return TileType.VOID
	return grid[y][x] as TileType

func is_walkable(pos: Vector2i) -> bool:
	var t: TileType = get_tile(pos.x, pos.y)
	return t == TileType.FLOOR or t == TileType.STAIRS_DOWN
