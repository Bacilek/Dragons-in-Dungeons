class_name DungeonData
extends Resource

enum TileType { VOID = 0, FLOOR = 1, WALL = 2, STAIRS_DOWN = 3, CHASM = 4, WATER = 5, MUD = 6, GRASS = 7, TRAMPLED_GRASS = 8 }

var grid: Array = []        # grid[y][x] → TileType int
var rooms: Array = []       # Array[Rect2i]
var player_start: Vector2i = Vector2i.ZERO
var stairs_pos: Vector2i = Vector2i.ZERO
var boss_room: Rect2i = Rect2i()   # valid only on boss floors (floor % 5 == 0)
var start_room: Rect2i = Rect2i()  # the room the player spawns in
var width: int = 0
var height: int = 0
var feeling: String = ""           # Floor Feeling id ("" = none; always "" on boss floors).
                                   # Display/debug only — gameplay code reads FloorFeeling.FEELINGS multipliers, never switches on this.
var room_metadata: Array = []      # Array[Dictionary]: {"type_id": String, "rect": Rect2i} — one entry
                                   # per placed special room (special-rooms-economy-design.md §3.3).
                                   # Additive generation→runtime bridge; regenerated from seed every
                                   # _load_floor(), never serialized. Empty on BSP-fallback floors.

func get_tile(x: int, y: int) -> TileType:
	if x < 0 or y < 0 or x >= width or y >= height:
		return TileType.VOID
	return grid[y][x] as TileType

func is_walkable(pos: Vector2i) -> bool:
	var t: TileType = get_tile(pos.x, pos.y)
	return t == TileType.FLOOR or t == TileType.STAIRS_DOWN \
		or t == TileType.WATER or t == TileType.MUD or t == TileType.GRASS \
		or t == TileType.TRAMPLED_GRASS
