class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const ATLAS_ORIGIN := Vector2i(0, 0)
const SOURCE_FLOOR:       int = 0
const SOURCE_WALL:        int = 1
const SOURCE_STAIRS:      int = 2
const SOURCE_CHASM:       int = 3
const SOURCE_WATER:       int = 4
const SOURCE_MUD:         int = 5
const SOURCE_GRASS:       int = 6
const SOURCE_DOOR_CLOSED:    int = 7
const SOURCE_DOOR_OPEN:      int = 8
const SOURCE_TRAMPLED_GRASS: int = 9
const TILE_SPRITES_PATH := "res://sprites/tiles/"
const WEAPONS_PATH := "res://sprites/weapons/"
const OBJECTS_PATH := "res://sprites/objects/"
const ITEMS_PATH   := "res://sprites/items/"

const ENEMY_COUNT_MIN: int = 3
const ENEMY_COUNT_MAX: int = 5
const FOV_RADIUS: int = 7
const TRAP_COUNT_MIN: int = 4
const TRAP_COUNT_MAX: int = 7
const TRAP_PATH := "res://sprites/traps/"

const TRAP_POOL: Array = [
	{"name": "Bear Trap",  "sprite": "Bear_Trap.png",       "damage": 0, "msg": "The bear trap snaps shut on you!", "wall_trap": false},
	{"name": "Fire Trap",  "sprite": "Fire_Trap.png",        "damage": 8, "msg": "Jets of flame engulf you!",        "wall_trap": false},
	{"name": "Pit Spikes", "sprite": "Pit_Trap_Spikes.png",  "damage": 7, "msg": "You fall into a spike pit!",       "wall_trap": false, "reusable": true},
	{"name": "Piston",     "sprite": "Push_Trap_Front.png",  "damage": 0, "msg": "A piston blasts you!",             "wall_trap": true},
]

# item_type: 0=WEAPON 1=ARMOR 2=POTION 4=FOOD  (matches Item.Type enum)
const ITEM_POOL: Array = [
	{"name": "Rusty Sword",    "type": 0, "icon": "weapon_rusty_sword.png",    "src": "weapons", "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 3,  "desc": "+1 damage", "dmg_type": "Slashing"},
	{"name": "Short Sword",    "type": 0, "icon": "weapon_knife.png",           "src": "weapons", "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 4,  "desc": "+1 damage", "dmg_type": "Slashing"},
	{"name": "Sword",          "type": 0, "icon": "weapon_regular_sword.png",   "src": "weapons", "bonus_dmg": 2, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 6,  "desc": "+2 damage", "dmg_type": "Slashing"},
	{"name": "Knight Sword",   "type": 0, "icon": "weapon_knight_sword.png",    "src": "weapons", "bonus_dmg": 3, "heal": 0,   "str_bonus": 0, "fmin": 4, "fmax": 8,  "desc": "+3 damage", "dmg_type": "Slashing"},
	{"name": "Golden Sword",   "type": 0, "icon": "weapon_golden_sword.png",    "src": "weapons", "bonus_dmg": 4, "heal": 0,   "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "+4 damage", "dmg_type": "Slashing"},
	{"name": "Lavish Sword",   "type": 0, "icon": "weapon_lavish_sword.png",    "src": "weapons", "bonus_dmg": 5, "heal": 0,   "str_bonus": 0, "fmin": 8, "fmax": 10, "desc": "+5 damage", "dmg_type": "Slashing"},
	{"name": "Health Potion",  "type": 2, "icon": "Potions/Health/HealthPotionMedium.png", "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4},
	{"name": "Strength Potion","type": 2, "icon": "Potions/Mana/ManaPotionMedium.png",    "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)"},
	{"name": "Ration",         "type": 4, "icon": "Food/MeatCooked.png",                  "src": "items", "bonus_dmg": 0, "heal": 200, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Fills you up"},
	{"name": "Mystery Meat",   "type": 4, "icon": "Food/Meat.png",                        "src": "items", "bonus_dmg": 0, "heal": 120, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Better than nothing"},
	{"name": "Short Bow",      "type": 0, "icon": "Weapons/BowArrow.png",                 "src": "items", "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 6,  "desc": "Ranged, DEX-based. Range 6.", "is_ranged": true, "range": 6, "dmg_type": "Piercing"},
	{"name": "Crossbow",       "type": 0, "icon": "Weapons/BowArrowGold.png",             "src": "items", "bonus_dmg": 3, "heal": 0,   "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Ranged, DEX-based. Range 8.", "is_ranged": true, "range": 8, "dmg_type": "Piercing"},
	{"name": "Throwing Daggers","type": 0,"icon": "Weapons/Throwing/Shuriken.png",        "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 8,  "desc": "Ranged, DEX-based. Range 4. Consumed on throw.", "is_ranged": true, "range": 4, "consumes": true, "qty": 3, "dmg_type": "Slashing"},
	{"name": "Thief Tools",    "type": 7, "icon": "Misc/KeyIron.png",                    "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Disarm traps, lock doors. Consumed on failure.", "qty": 2},
]

const BOSS_POOL: Array = [
	{"display_name": "Big Demon",   "sprite": "big_demon",   "idle_frames": 4, "run_frames": 4, "floor": 5,  "hp": 80,  "hp_per_floor": 0, "dmg_min": 8,  "dmg_max": 14, "armor": 3, "ac": 16, "exp": 100},
	{"display_name": "Necromancer", "sprite": "necromancer", "idle_frames": 4, "run_frames": 4, "floor": 10, "hp": 120, "hp_per_floor": 0, "dmg_min": 10, "dmg_max": 18, "armor": 4, "ac": 13, "exp": 200,
	 "idle_fmt": "res://sprites/characters/necromancer_anim_f%d.png",
	 "run_fmt":  "res://sprites/characters/necromancer_anim_f%d.png"},
]

const ENEMY_POOL: Array = [
	{"display_name": "Tiny Zombie", "sprite": "tiny_zombie", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 3,  "hp": 5,  "hp_per_floor": 1, "dmg_min": 1, "dmg_max": 3, "armor": 0, "ac": 10, "exp": 4},
	{"display_name": "Orc Warrior", "sprite": "orc_warrior", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,  "hp": 8,  "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 11, "exp": 8},
	{"display_name": "Goblin",      "sprite": "goblin",      "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 6,  "hp": 7,  "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 4, "armor": 0, "ac": 12, "exp": 6},
	{"display_name": "Orc Shaman",  "sprite": "orc_shaman",  "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 0, "ac": 10, "exp": 12},
	{"display_name": "Masked Orc",  "sprite": "masked_orc",  "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 12, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 1, "ac": 13, "exp": 10},
	{"display_name": "Skeleton",    "sprite": "skelet",      "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 9,  "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 12, "exp": 9},
	{"display_name": "Wogol",       "sprite": "wogol",       "idle_frames": 4, "run_frames": 4, "floor_min": 5, "floor_max": 8,  "hp": 14, "hp_per_floor": 3, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 13, "exp": 15},
	{"display_name": "Imp",         "sprite": "imp",         "idle_frames": 4, "run_frames": 4, "floor_min": 6, "floor_max": 9,  "hp": 11, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 7, "armor": 1, "ac": 13, "exp": 13},
	{"display_name": "Chort",       "sprite": "chort",       "idle_frames": 4, "run_frames": 4, "floor_min": 7, "floor_max": 10, "hp": 16, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 8, "armor": 2, "ac": 14, "exp": 20},
	{"display_name": "Pumpkin Dude","sprite": "pumpkin_dude","idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 20, "hp_per_floor": 4, "dmg_min": 5, "dmg_max": 9, "armor": 2, "ac": 12, "exp": 25},
]

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _grass_layer: TileMapLayer

var _data: DungeonData
var _player: Player
var _enemies: Array[Enemy] = []
var _companions: Array = []  # Array[Companion] — ally entities processed in enemy phase
var _traps: Dictionary = {}         # Vector2i → {name, damage, msg, sprite_node, revealed, triggered, is_push}
var _doors: Dictionary = {}         # Vector2i → {is_open: bool, sprite: Sprite2D}

var _floor_items: Dictionary = {}
var _floor_item_sprites: Dictionary = {}
var _blood_decals: Array[Sprite2D] = []
var _lock_icon_tex: Texture2D = null

var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_sprite: Sprite2D
var _explored: Dictionary = {}
var _visible_tiles: Dictionary = {}  # Vector2i → true; current FOV set, reset each update_fog
var _fov_player_pos: Vector2i = Vector2i(-1, -1)
var _see_all_active: bool = false

# Octant multiplier tables for recursive shadowcasting (8 octants, Roguebasin standard)
# X = center.x + dx * _SC_XX[i] + j * _SC_XY[i]
# Y = center.y + dx * _SC_YX[i] + j * _SC_YY[i]
const _SC_XX: Array = [1,  0,  0, -1, -1,  0,  0,  1]
const _SC_XY: Array = [0,  1, -1,  0,  0, -1,  1,  0]
const _SC_YX: Array = [0,  1,  1,  0,  0, -1, -1,  0]
const _SC_YY: Array = [1,  0,  0,  1, -1,  0,  0, -1]

func _ready() -> void:
	add_to_group("dungeon_floor")
	_setup_tileset()
	_load_floor()
	GameState.debug_jump_floor.connect(_on_debug_jump_floor)

func _on_debug_jump_floor(_n: int) -> void:
	_load_floor()

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_add_tile_source(tile_set, SOURCE_FLOOR,  TILE_SPRITES_PATH + "floor_1.png")
	_add_tile_source(tile_set, SOURCE_WALL,   TILE_SPRITES_PATH + "wall_mid.png")
	_add_tile_source(tile_set, SOURCE_STAIRS, TILE_SPRITES_PATH + "floor_stairs.png")
	# New tile types — extract from atlas sheets or use solid-color fallbacks
	_add_tile_source_or_color(tile_set, SOURCE_CHASM, TILE_SPRITES_PATH + "hole.png", Color(0.06, 0.04, 0.08))
	_add_tile_from_atlas(tile_set, SOURCE_WATER, "res://sprites/tiles/WaterRockDirt.png", 32, 0, Color(0.10, 0.30, 0.72))
	_add_tile_from_atlas(tile_set, SOURCE_MUD,   "res://sprites/tiles/WaterRockDirt.png",  0, 0, Color(0.30, 0.18, 0.08))
	_add_tile_from_atlas(tile_set, SOURCE_GRASS,         "res://sprites/tiles/Grass.png", 368, 176, Color(0.10, 0.42, 0.10))
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_CLOSED,    OBJECTS_PATH + "doors_leaf_closed.png", Color(0.5, 0.3, 0.1))
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_OPEN,      OBJECTS_PATH + "doors_leaf_open.png",   Color(0.3, 0.2, 0.05))
	_add_tile_from_atlas(tile_set, SOURCE_TRAMPLED_GRASS, "res://sprites/tiles/Grass.png", 352, 192, Color(0.38, 0.30, 0.10))
	tilemap.tile_set = tile_set
	_grass_layer = TileMapLayer.new()
	_grass_layer.tile_set = tile_set
	_grass_layer.z_index = 0
	add_child(_grass_layer)

func _add_tile_source(tile_set: TileSet, source_id: int, path: String) -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(path)
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(ATLAS_ORIGIN)
	tile_set.add_source(atlas, source_id)

func _add_tile_from_atlas(tile_set: TileSet, source_id: int, atlas_path: String, px_x: int, px_y: int, fallback: Color) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(atlas_path):
		var atlas_tex := load(atlas_path) as Texture2D
		if atlas_tex != null:
			var img := atlas_tex.get_image()
			if img != null and not img.is_empty():
				var region := img.get_region(Rect2i(px_x, px_y, TILE_SIZE, TILE_SIZE))
				tex = ImageTexture.create_from_image(region)
	if tex == null:
		var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(fallback)
		tex = ImageTexture.create_from_image(img)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(ATLAS_ORIGIN)
	tile_set.add_source(atlas, source_id)

func _add_tile_source_or_color(tile_set: TileSet, source_id: int, path: String, fallback: Color) -> void:
	var tex: Texture2D = null
	if ResourceLoader.exists(path):
		tex = load(path) as Texture2D
	if tex == null:
		var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		img.fill(fallback)
		tex = ImageTexture.create_from_image(img)
	var atlas := TileSetAtlasSource.new()
	atlas.texture = tex
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(ATLAS_ORIGIN)
	tile_set.add_source(atlas, source_id)

func _load_floor() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	for c in _companions:
		if is_instance_valid(c):
			c.queue_free()
	_companions.clear()
	GameState.player_companion = null
	TurnManager.clear_enemies()
	TurnManager.reset()

	for pos: Vector2i in _traps:
		var sn: Sprite2D = _traps[pos].get("sprite_node")
		if sn != null and is_instance_valid(sn):
			sn.queue_free()
	_traps.clear()

	for pos: Vector2i in _doors:
		var sp: Sprite2D = _doors[pos].get("sprite")
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
		if _doors[pos].has("lock_icon"):
			var icon: Node = _doors[pos]["lock_icon"]
			if is_instance_valid(icon):
				icon.queue_free()
	_doors.clear()

	for pos: Vector2i in _floor_item_sprites:
		var sn: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(sn):
			sn.queue_free()
	_floor_items.clear()
	_floor_item_sprites.clear()

	for spr: Sprite2D in _blood_decals:
		if is_instance_valid(spr):
			spr.queue_free()
	_blood_decals.clear()

	_data = DungeonGenerator.generate(GameState.run_seed, GameState.current_floor)

	# Music: boss floors get boss theme, others get dungeon ambient
	if GameState.current_floor % 5 == 0:
		AudioManager.play_music("res://audio/music_boss.ogg")
	else:
		AudioManager.play_music("res://audio/music_dungeon.ogg")

	tilemap.clear()
	_grass_layer.clear()
	for y: int in _data.height:
		for x: int in _data.width:
			var pos := Vector2i(x, y)
			match _data.grid[y][x] as DungeonData.TileType:
				DungeonData.TileType.FLOOR:
					tilemap.set_cell(pos, SOURCE_FLOOR, ATLAS_ORIGIN)
				DungeonData.TileType.WALL:
					tilemap.set_cell(pos, SOURCE_WALL, ATLAS_ORIGIN)
				DungeonData.TileType.STAIRS_DOWN:
					tilemap.set_cell(pos, SOURCE_STAIRS, ATLAS_ORIGIN)
				DungeonData.TileType.CHASM:
					tilemap.set_cell(pos, SOURCE_CHASM, ATLAS_ORIGIN)
				DungeonData.TileType.WATER:
					tilemap.set_cell(pos, SOURCE_WATER, ATLAS_ORIGIN)
				DungeonData.TileType.MUD:
					tilemap.set_cell(pos, SOURCE_MUD, ATLAS_ORIGIN)
				DungeonData.TileType.GRASS:
					tilemap.set_cell(pos, SOURCE_FLOOR, ATLAS_ORIGIN)
					_grass_layer.set_cell(pos, SOURCE_GRASS, ATLAS_ORIGIN)
				DungeonData.TileType.TRAMPLED_GRASS:
					tilemap.set_cell(pos, SOURCE_FLOOR, ATLAS_ORIGIN)
					_grass_layer.set_cell(pos, SOURCE_TRAMPLED_GRASS, ATLAS_ORIGIN)

	if _player == null:
		var player_scene: PackedScene = preload("res://scenes/game/player.tscn")
		_player = player_scene.instantiate() as Player
		entities.add_child(_player)

	_player._dungeon_floor = self
	_player.stats = GameState.player_stats
	_player.set_grid_pos(_data.player_start)
	GameState.player_grid_pos = _data.player_start
	GameState.current_stairs_pos = _data.stairs_pos

	if ResourceLoader.exists(ITEMS_PATH + "Misc/KeyIron.png"):
		_lock_icon_tex = load(ITEMS_PATH + "Misc/KeyIron.png")
	_spawn_enemies()
	_spawn_traps()
	_spawn_doors()
	_spawn_items()
	_spawn_locked_doors()
	_setup_fog()
	_see_all_active = false
	update_fog(_data.player_start)
	if not GameState.debug_reveal_all.is_connected(reveal_all):
		GameState.debug_reveal_all.connect(reveal_all)
	if not GameState.debug_see_all.is_connected(_on_debug_see_all):
		GameState.debug_see_all.connect(_on_debug_see_all)
	if GameState.god_mode:
		_on_debug_see_all(true)

# ── Tilemap queries ───────────────────────────────────────────────────────────

func get_tile_type(pos: Vector2i) -> DungeonData.TileType:
	return _data.get_tile(pos.x, pos.y)

func is_walkable(pos: Vector2i) -> bool:
	if _doors.has(pos) and not _doors[pos]["is_open"]:
		return false
	return _data.is_walkable(pos)

func is_walkable_for_enemy(pos: Vector2i) -> bool:
	if not _data.is_walkable(pos):
		return false
	if _doors.has(pos):
		# Closed doors block normal movement (enemy handles opening separately)
		if not _doors[pos]["is_open"]:
			return false
	if _player != null and _player.grid_pos == pos:
		return false
	for e in _enemies:
		if is_instance_valid(e) and e.grid_pos == pos:
			return false
	if _traps.has(pos):
		var trap: Dictionary = _traps[pos]
		if trap.get("is_push", false):
			return false  # Push traps always avoided
		if not trap.get("triggered", false):
			return false  # Active non-push traps avoided
		# Triggered single-use traps: enemy can walk through
	return true

# ── Fog of war ────────────────────────────────────────────────────────────────

func _setup_fog() -> void:
	if _fog_sprite != null and is_instance_valid(_fog_sprite):
		_fog_sprite.queue_free()
	_explored.clear()
	_visible_tiles.clear()
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
	_fov_player_pos = player_pos
	var stairs_was_known: bool = _explored.get(_data.stairs_pos, false)

	_visible_tiles = _compute_shadowcast(player_pos)

	for y: int in _data.height:
		for x: int in _data.width:
			var tile_pos := Vector2i(x, y)
			if _visible_tiles.has(tile_pos):
				_explored[tile_pos] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif _explored.get(tile_pos, false):
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0.65))
			else:
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 1.0))

	_fog_texture.update(_fog_image)
	_update_enemy_visibility()
	if _see_all_active:
		_apply_see_all()
	if not stairs_was_known and _explored.get(_data.stairs_pos, false):
		GameState.stairs_discovered.emit()

func _compute_shadowcast(center: Vector2i) -> Dictionary:
	var visible: Dictionary = {}
	visible[center] = true
	for i: int in 8:
		_cast_light(visible, center, FOV_RADIUS, 1, 1.0, 0.0,
			_SC_XX[i], _SC_XY[i], _SC_YX[i], _SC_YY[i])
	return visible

func _cast_light(visible: Dictionary, center: Vector2i, radius: int,
				  row: int, start: float, end: float,
				  xx: int, xy: int, yx: int, yy: int) -> void:
	if start < end:
		return
	var new_start: float = 0.0
	var r2: int = radius * radius
	var blocked: bool = false
	var j: int = row
	while j <= radius and not blocked:
		var dx: int = -j
		blocked = false
		while dx <= 0:
			var x: int = center.x + dx * xx - j * yx
			var y: int = center.y + dx * xy - j * yy
			var l_slope: float = (float(dx) - 0.5) / (-float(j) + 0.5)
			var r_slope: float = (float(dx) + 0.5) / (-float(j) - 0.5)
			if start < r_slope:
				dx += 1
				continue
			elif end > l_slope:
				break
			if dx * dx + j * j <= r2 and x >= 0 and x < _data.width and y >= 0 and y < _data.height:
				visible[Vector2i(x, y)] = true
			if blocked:
				if _blocks_los(x, y):
					new_start = r_slope
				else:
					blocked = false
					start = new_start
			else:
				if _blocks_los(x, y) and j < radius:
					blocked = true
					_cast_light(visible, center, radius, j + 1, start, l_slope, xx, xy, yx, yy)
					new_start = r_slope
			dx += 1
		if blocked:
			break
		j += 1

func _on_debug_see_all(active: bool) -> void:
	_see_all_active = active
	if not active:
		for trap_pos: Vector2i in _traps.keys():
			var trap_d: Dictionary = _traps[trap_pos]
			if not trap_d.get("revealed", false):
				var trap_spr: Sprite2D = trap_d.get("sprite_node") as Sprite2D
				if trap_spr != null and is_instance_valid(trap_spr):
					trap_spr.modulate = Color(1.0, 1.0, 1.0, 0.0)
	if _player != null:
		update_fog(_player.grid_pos)

func _apply_see_all() -> void:
	for y: int in _data.height:
		for x: int in _data.width:
			if _data.get_tile(x, y) != DungeonData.TileType.VOID:
				var pos := Vector2i(x, y)
				_explored[pos] = true
				_visible_tiles[pos] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
	_fog_texture.update(_fog_image)
	for e: Enemy in _enemies:
		if is_instance_valid(e):
			e.visible = true
	for trap_pos: Vector2i in _traps.keys():
		var trap_d: Dictionary = _traps[trap_pos]
		if trap_d.get("revealed", false):
			continue
		var trap_spr: Sprite2D = trap_d.get("sprite_node") as Sprite2D
		if trap_spr != null and is_instance_valid(trap_spr):
			trap_spr.modulate = Color(0.55, 0.75, 1.0, 0.42)

func reveal_all() -> void:
	for y: int in _data.height:
		for x: int in _data.width:
			if _data.get_tile(x, y) != DungeonData.TileType.VOID:
				_explored[Vector2i(x, y)] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
	_fog_texture.update(_fog_image)
	for enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.visible = true
	for pos: Vector2i in _traps.keys():
		reveal_trap(pos)

func _update_enemy_visibility() -> void:
	for enemy: Enemy in _enemies:
		if is_instance_valid(enemy):
			enemy.visible = _visible_tiles.has(enemy.grid_pos)

func _blocks_los(bx: int, by: int) -> bool:
	var t: DungeonData.TileType = _data.get_tile(bx, by)
	if t == DungeonData.TileType.WALL or t == DungeonData.TileType.GRASS:
		return true
	var pos := Vector2i(bx, by)
	return _doors.has(pos) and not _doors[pos]["is_open"]

func _blocks_projectile(bx: int, by: int) -> bool:
	var t: DungeonData.TileType = _data.get_tile(bx, by)
	return t == DungeonData.TileType.WALL or t == DungeonData.TileType.VOID

func has_ranged_los(from: Vector2i, to: Vector2i) -> bool:
	var x: int = from.x; var y: int = from.y
	var dx: int = abs(to.x - x); var dy: int = abs(to.y - y)
	var sx: int = 1 if x < to.x else -1
	var sy: int = 1 if y < to.y else -1
	var err: int = dx - dy
	while x != to.x or y != to.y:
		var e2: int = 2 * err
		var old_x: int = x; var old_y: int = y
		if e2 > -dy: err -= dy; x += sx
		if e2 < dx:  err += dx; y += sy
		if x == to.x and y == to.y: break
		if _blocks_projectile(x, y): return false
		if x != old_x and y != old_y:
			if _blocks_projectile(x, old_y) and _blocks_projectile(old_x, y):
				return false
	return true

func has_line_of_sight(from: Vector2i, to: Vector2i) -> bool:
	var x: int = from.x
	var y: int = from.y
	var dx: int = abs(to.x - x)
	var dy: int = abs(to.y - y)
	var sx: int = 1 if x < to.x else -1
	var sy: int = 1 if y < to.y else -1
	var err: int = dx - dy
	while x != to.x or y != to.y:
		var e2: int = 2 * err
		var old_x: int = x
		var old_y: int = y
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		if x == to.x and y == to.y:
			break
		if _blocks_los(x, y):
			return false
		# Diagonal step: also check shoulder tiles so doors/walls can't be seen around
		if x != old_x and y != old_y:
			if _blocks_los(x, old_y) and _blocks_los(old_x, y):
				return false
	return true

# ── Pathfinding ───────────────────────────────────────────────────────────────

func find_path(from: Vector2i, to: Vector2i) -> Array[Vector2i]:
	if not _explored.get(to, false):
		return []
	if not _data.is_walkable(to) and get_enemy_at(to) == null:
		return []
	var queue: Array[Vector2i] = [from]
	var came_from: Dictionary = {}
	came_from[from] = from
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
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
			# Treat closed doors as passable for player pathfinding (will open on arrival)
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

func _bfs_reachable(from: Vector2i, to: Vector2i, exclude: Array) -> bool:
	var visited: Dictionary = {}
	var queue: Array = [from]
	visited[from] = true
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt) or exclude.has(nxt):
				continue
			if _data.is_walkable(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return false

func _bfs_collect(from: Vector2i, exclude: Array) -> Dictionary:
	var visited: Dictionary = {}
	var queue: Array = [from]
	visited[from] = true
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt) or exclude.has(nxt):
				continue
			if _data.is_walkable(nxt):
				visited[nxt] = true
				queue.append(nxt)
	return visited

# ── Enemy management ──────────────────────────────────────────────────────────

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
	close_door(enemy.grid_pos)
	AudioManager.play("kill_enemy")

func get_all_enemies() -> Array[Enemy]:
	return _enemies

func spawn_companion(companion: Companion, pos: Vector2i) -> void:
	companion._dungeon_floor = self
	entities.add_child(companion)
	companion.set_grid_pos(pos)
	_companions.append(companion)

func remove_companion(companion: Companion) -> void:
	_companions.erase(companion)

func is_walkable_for_companion(pos: Vector2i) -> bool:
	if not _data.is_walkable(pos):
		return false
	if _doors.has(pos) and not _doors[pos]["is_open"]:
		return false
	if _player != null and _player.grid_pos == pos:
		return false
	for e: Enemy in _enemies:
		if is_instance_valid(e) and e.grid_pos == pos:
			return false
	for c in _companions:
		if is_instance_valid(c) and c.grid_pos == pos:
			return false
	return true

func show_damage(world_pos: Vector2, amount: int, is_player_hit: bool) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 8)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.25, 0.25) if is_player_hit else Color(1.0, 0.9, 0.3))
	lbl.z_index = 10
	lbl.position = world_pos - Vector2(4.0, 14.0)
	$Entities.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0.0, -20.0), 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)

func get_visible_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if _player == null:
		return result
	var r2: int = FOV_RADIUS * FOV_RADIUS
	for e: Enemy in _enemies:
		if not is_instance_valid(e):
			continue
		var dx: int = e.grid_pos.x - _player.grid_pos.x
		var dy: int = e.grid_pos.y - _player.grid_pos.y
		if dx * dx + dy * dy <= r2 and has_line_of_sight(_player.grid_pos, e.grid_pos):
			result.append(e)
	return result

func on_player_reached_stairs() -> void:
	GameState.advance_floor()
	if GameState.current_floor > 10:
		return
	_load_floor()

# ── Enemy spawning ────────────────────────────────────────────────────────────

func _spawn_enemies() -> void:
	var is_boss_floor: bool = GameState.current_floor % 5 == 0 and _data.boss_room.has_area()

	var candidates: Array = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) == DungeonData.TileType.FLOOR:
				if pos != _data.player_start and pos != _data.stairs_pos:
					if _data.start_room.has_area() and _data.start_room.grow(1).has_point(pos):
						continue  # keep starting room safe
					if is_boss_floor and _data.boss_room.has_point(pos):
						continue  # reserve boss room for the boss
					candidates.append(pos)
	candidates.shuffle()

	var eligible: Array = []
	for entry in ENEMY_POOL:
		var t: Dictionary = entry
		if GameState.current_floor >= t["floor_min"] and GameState.current_floor <= t["floor_max"]:
			eligible.append(t)
	if eligible.is_empty():
		eligible = [ENEMY_POOL[0]]

	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var count: int = mini(randi_range(ENEMY_COUNT_MIN, ENEMY_COUNT_MAX), candidates.size())
	var rng := RandomNumberGenerator.new()
	rng.seed = GameState.run_seed ^ (GameState.current_floor * 0x1234ABCD)

	for i: int in count:
		var type_data: Dictionary = eligible[randi() % eligible.size()]
		var enemy: Enemy = enemy_scene.instantiate() as Enemy
		enemy.configure(type_data)
		# Assign random initial behavior
		var behavior_roll: int = rng.randi() % 3
		match behavior_roll:
			0: enemy.initial_behavior = Enemy.Behavior.SLEEPING
			1: enemy.initial_behavior = Enemy.Behavior.STATIONARY
			2: enemy.initial_behavior = Enemy.Behavior.ROAMING
		enemy._dungeon_floor = self
		entities.add_child(enemy)
		enemy.set_grid_pos(candidates[i])
		_enemies.append(enemy)
		TurnManager.register_enemy(enemy)

	if is_boss_floor:
		_spawn_boss()

func _spawn_boss() -> void:
	var floor_num: int = GameState.current_floor
	var boss_data: Dictionary = {}
	for b in BOSS_POOL:
		var bd: Dictionary = b
		if bd["floor"] == floor_num:
			boss_data = bd
			break
	if boss_data.is_empty():
		return

	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var boss: Enemy = enemy_scene.instantiate() as Enemy
	boss.configure(boss_data)
	boss.is_boss = true
	boss.initial_behavior = Enemy.Behavior.CHASING

	# Place at room center, shift 1 tile up if center == stairs
	var center: Vector2i = Vector2i(
		_data.boss_room.position.x + _data.boss_room.size.x / 2,
		_data.boss_room.position.y + _data.boss_room.size.y / 2
	)
	var boss_pos: Vector2i = center
	if boss_pos == _data.stairs_pos:
		for d: Vector2i in [Vector2i(0,-2), Vector2i(0,2), Vector2i(-2,0), Vector2i(2,0)]:
			var candidate: Vector2i = center + d
			if _data.is_walkable(candidate) and candidate != _data.player_start:
				boss_pos = candidate
				break

	boss._dungeon_floor = self
	entities.add_child(boss)
	boss.set_grid_pos(boss_pos)
	_enemies.append(boss)
	TurnManager.register_enemy(boss)
	GameState.game_log("[color=red][b]You sense a terrifying presence...[/b][/color]")

func debug_spawn_enemy(type_data: Dictionary) -> void:
	var player_pos: Vector2i = GameState.player_grid_pos
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1)
	]
	var spawn_pos: Vector2i = Vector2i(-1, -1)
	for d: Vector2i in dirs:
		var p: Vector2i = player_pos + d
		if is_walkable_for_enemy(p) and get_enemy_at(p) == null:
			spawn_pos = p
			break
	if spawn_pos == Vector2i(-1, -1):
		GameState.game_log("[color=red][DEBUG] No open tile to spawn %s[/color]" % type_data.get("display_name", "enemy"))
		return
	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var enemy: Enemy = enemy_scene.instantiate() as Enemy
	enemy.initial_behavior = Enemy.Behavior.CHASING
	enemy.configure(type_data)
	enemy._dungeon_floor = self
	entities.add_child(enemy)
	enemy.set_grid_pos(spawn_pos)
	_enemies.append(enemy)
	TurnManager.register_enemy(enemy)
	GameState.game_log("[color=lime][DEBUG] Spawned %s[/color]" % type_data.get("display_name", "enemy"))

# ── Trap system ───────────────────────────────────────────────────────────────

func _spawn_traps() -> void:
	var floor_cands: Array = []
	var wall_cands: Array = []
	var cardinal: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _data.start_room.has_area() and _data.start_room.grow(1).has_point(pos):
				continue  # keep starting room safe
			if maxi(abs(pos.x - _data.player_start.x), abs(pos.y - _data.player_start.y)) < 2:
				continue
			# Only place floor traps where there's an alternate path (bypass check)
			if _bfs_reachable(_data.player_start, _data.stairs_pos, [pos]):
				floor_cands.append(pos)
			for d: Vector2i in cardinal:
				var wp: Vector2i = pos + d
				if _data.get_tile(wp.x, wp.y) == DungeonData.TileType.WALL:
					# Piston only goes into open areas — skip 1-wide corridors where player can't step aside
					var perp1: Vector2i = Vector2i(-d.y, d.x)
					var perp2: Vector2i = Vector2i(d.y, -d.x)
					var is_narrow: bool = \
						_data.get_tile((pos + perp1).x, (pos + perp1).y) != DungeonData.TileType.FLOOR \
						and _data.get_tile((pos + perp2).x, (pos + perp2).y) != DungeonData.TileType.FLOOR
					var push_d: Vector2i = Vector2i(-d.x, -d.y)
					var land: Vector2i = pos + push_d
					if not is_narrow and _data.is_walkable(land) and _bfs_reachable(_data.player_start, _data.stairs_pos, [pos]):
						wall_cands.append({"floor_pos": pos, "wall_pos": wp, "push_dir": push_d})
					break

	floor_cands.shuffle()
	wall_cands.shuffle()

	var floor_pool: Array = []
	var wall_pool: Array = []
	for entry in TRAP_POOL:
		var t: Dictionary = entry
		if t.get("wall_trap", false):
			wall_pool.append(t)
		else:
			floor_pool.append(t)

	var used: Dictionary = {}
	var floor_count: int = mini(randi_range(TRAP_COUNT_MIN, TRAP_COUNT_MAX), floor_cands.size())
	for i: int in floor_count:
		var t: Dictionary = floor_pool[randi() % floor_pool.size()]
		var pos: Vector2i = floor_cands[i]
		used[pos] = true
		var tex: Texture2D = load(TRAP_PATH + t["sprite"])
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.region_enabled = true
		sprite.region_rect = Rect2(0, 0, 32, 32)
		sprite.scale = Vector2(0.5, 0.5)
		sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
		sprite.z_index = 1
		sprite.modulate.a = 0.0
		entities.add_child(sprite)
		_traps[pos] = {"name": t["name"], "damage": t["damage"], "msg": t["msg"],
					   "sprite_node": sprite, "revealed": false, "is_push": false, "triggered": false,
					   "reusable": t.get("reusable", false)}

	if not wall_pool.is_empty():
		var valid_wc: Array = []
		for wc in wall_cands:
			var wcd: Dictionary = wc
			if not used.has(wcd["floor_pos"]):
				valid_wc.append(wcd)
		var push_count: int = mini(randi_range(2, 3), valid_wc.size())
		for i: int in push_count:
			var wcd: Dictionary = valid_wc[i]
			var t: Dictionary = wall_pool[randi() % wall_pool.size()]
			var floor_pos: Vector2i = wcd["floor_pos"]
			var wall_pos: Vector2i  = wcd["wall_pos"]
			var push_dir: Vector2i  = wcd["push_dir"]
			var tex: Texture2D = load(TRAP_PATH + t["sprite"])
			if tex == null:
				continue
			var frame_size: int = tex.get_height()
			var sprite := Sprite2D.new()
			sprite.texture = tex
			sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
			sprite.region_enabled = true
			sprite.region_rect = Rect2(0, 0, frame_size, frame_size)
			sprite.scale = Vector2(float(TILE_SIZE) / float(frame_size), float(TILE_SIZE) / float(frame_size))
			# Sprite stays visually embedded 6px into the wall (floor_pos side)
			var wall_offset: Vector2 = Vector2(-push_dir.x, -push_dir.y) * 6.0
			sprite.position = Vector2(floor_pos.x * TILE_SIZE + TILE_SIZE * 0.5, floor_pos.y * TILE_SIZE + TILE_SIZE * 0.5) + wall_offset
			sprite.rotation = atan2(float(push_dir.y), float(push_dir.x)) - PI / 2.0
			sprite.z_index = 1
			sprite.modulate.a = 0.0
			entities.add_child(sprite)
			var detect_pos: Vector2i = floor_pos
			_traps[detect_pos] = {"name": t["name"], "damage": 0, "msg": t["msg"],
								  "sprite_node": sprite, "revealed": false, "is_push": true,
								  "push_dir": push_dir, "wall_pos": wall_pos, "triggered": false}

	GameState.game_log("[color=gray]Floor has %d hidden traps.[/color]" % _traps.size())

func get_trap_at(pos: Vector2i) -> Dictionary:
	return _traps.get(pos, {})

func trigger_trap(pos: Vector2i, entity: Node2D = null) -> void:
	if not _traps.has(pos):
		return
	var trap: Dictionary = _traps[pos]
	var is_push: bool = trap.get("is_push", false)

	# Single-use traps already spent: skip
	if trap.get("triggered", false) and not is_push:
		return

	# Always reveal when triggered by anyone
	trap["revealed"] = true
	var sprite_node: Sprite2D = trap.get("sprite_node") as Sprite2D
	if is_instance_valid(sprite_node):
		sprite_node.modulate = Color(1.0, 1.0, 1.0, 1.0)

	var target: Node2D = entity if entity != null else _player

	# DEX check for player: 1d20 + DEX mod + prof (only if DEX check proficiency) vs DC
	# Danger Sense talent rank 1: advantage on DEX checks vs traps — roll 2d20 take higher.
	if target is Player:
		var s: Stats = GameState.player_stats
		var dex_mod: int = s.dex_modifier()
		var has_prof: bool = s.check_prof_dex
		var prof_bonus: int = s.proficiency_bonus if has_prof else 0
		var danger_rank: int = GameState.get_talent_rank("danger_sense")
		var has_adv: bool = danger_rank >= 1
		var die1: int = randi_range(1, 20)
		var die2: int = die1
		if has_adv:
			die2 = randi_range(1, 20)
		var die: int = maxi(die1, die2)
		# Danger Sense rank 2: use max(DEX mod, STR mod) for DEX/WIS/CHA checks
		var effective_stat: String = "DEX"
		if danger_rank >= 2 and s.str_modifier() > dex_mod:
			dex_mod = s.str_modifier()
			effective_stat = "STR"
		var roll: int = die + dex_mod + prof_bonus
		var dc: int = 10 + GameState.current_floor
		var adv_tag: String = " [color=gray](Danger Sense)[/color]" if has_adv else ""
		var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [
			effective_stat, die, die1, die2, dex_mod, prof_bonus, roll, dc, 1 if roll >= dc else 0, 1 if has_adv else 0]
		if roll >= dc:
			GameState.game_log("[color=cyan]You dodge [b]%s[/b]!%s [url=%s]%d vs DC %d[/url][/color]" % [trap["name"], adv_tag, check_meta, roll, dc])
			return
		else:
			GameState.game_log("[color=orange]%s triggered!%s [url=%s]%d vs DC %d[/url][/color]" % [trap["name"], adv_tag, check_meta, roll, dc])

	if is_push:
		AudioManager.play("trap_piston")
		await _push_entity(target, trap["push_dir"], 2, sprite_node)
		# Stay fully visible if already revealed, otherwise return to semi-hidden
		if is_instance_valid(sprite_node):
			sprite_node.modulate = Color(1.0, 1.0, 1.0, 1.0 if trap.get("revealed", false) else 0.5)
	else:
		var is_reusable: bool = trap.get("reusable", false)
		if not is_reusable:
			trap["triggered"] = true
			if is_instance_valid(sprite_node):
				sprite_node.modulate = Color(0.25, 0.25, 0.25, 0.85)  # Dark = spent
		var dmg: int = trap["damage"] + GameState.current_floor / 2
		_apply_trap_damage(target, dmg, trap["msg"])
		# Fire Trap applies burning
		if trap["name"] == "Fire Trap" and target is Player:
			AudioManager.play("trap_fire")
			if GameState.apply_player_status("burning", 4):
				GameState.game_log("[color=orange]You are burning! (4 turns)[/color]")
		# Pit Spikes apply bleeding (5 turns, 1 dmg/turn)
		if trap["name"] == "Pit Spikes" and target is Player:
			AudioManager.play("trap_spike")
			if GameState.apply_player_status("bleeding", 5):
				GameState.game_log("[color=red]You are bleeding! (5 turns)[/color]")
		# Bear Trap slows movement for 20 turns (each step costs 2 turns)
		if trap["name"] == "Bear Trap" and target is Player:
			AudioManager.play("trap_bear")
			if GameState.apply_player_status("slowed", 20):
				GameState.game_log("[color=yellow]Your leg is caught! Slowed for 20 turns.[/color]")
		# Animation plays asynchronously — does not block player input
		if is_instance_valid(sprite_node):
			_play_trap_animation(sprite_node)

func reveal_trap(pos: Vector2i) -> bool:
	if not _traps.has(pos):
		return false
	var trap: Dictionary = _traps[pos]
	if trap.get("revealed", false):
		return false
	trap["revealed"] = true
	var sprite_node: Sprite2D = trap["sprite_node"]
	if is_instance_valid(sprite_node):
		sprite_node.modulate.a = 1.0
	return true

func disarm_trap(pos: Vector2i) -> void:
	if not _traps.has(pos):
		return
	var sprite_node: Sprite2D = _traps[pos].get("sprite_node")
	if sprite_node != null and is_instance_valid(sprite_node):
		sprite_node.modulate = Color(0.5, 0.5, 0.5, 0.4)
		var tw := sprite_node.create_tween()
		tw.tween_property(sprite_node, "modulate:a", 0.0, 0.5)
		tw.tween_callback(sprite_node.queue_free)
	_traps.erase(pos)

func place_item_on_floor(pos: Vector2i, item: Item) -> void:
	var target: Vector2i = pos
	if _floor_items.has(target):
		for d: Vector2i in [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]:
			var alt: Vector2i = pos + d
			if _data.is_walkable(alt) and not _floor_items.has(alt):
				target = alt
				break
	var tex: Texture2D
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		tex = load(item.icon_path)
	else:
		var fallback_img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color(0.80, 0.55, 0.15))
		tex = ImageTexture.create_from_image(fallback_img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(target.x * TILE_SIZE + TILE_SIZE * 0.5, target.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	entities.add_child(sprite)
	_floor_items[target] = item
	_floor_item_sprites[target] = sprite

func place_blood_decal(pos: Vector2i) -> void:
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	for py: int in TILE_SIZE:
		for px: int in TILE_SIZE:
			var cx: float = float(px) - TILE_SIZE * 0.5 + 0.5
			var cy: float = float(py) - TILE_SIZE * 0.5 + 0.5
			if cx * cx + cy * cy < 36.0:
				img.set_pixel(px, py, Color(0.55, 0.0, 0.0, 0.65))
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 0
	entities.add_child(sprite)
	_blood_decals.append(sprite)

func cook_rotten_meat(trap_pos: Vector2i) -> Item:
	AudioManager.play("cook_meat")
	if _traps.has(trap_pos):
		var trap: Dictionary = _traps[trap_pos]
		var sprite_node: Sprite2D = trap.get("sprite_node") as Sprite2D
		trap["triggered"] = true
		if sprite_node != null and is_instance_valid(sprite_node):
			sprite_node.z_index = 8
			var tw := sprite_node.create_tween()
			tw.tween_property(sprite_node, "modulate", Color(2.5, 1.5, 0.1, 1.0), 0.08)
			tw.tween_property(sprite_node, "modulate", Color(1.5, 0.7, 0.05, 1.0), 0.12)
			tw.tween_property(sprite_node, "modulate", Color(0.25, 0.25, 0.25, 0.85), 0.20)
			tw.tween_callback(func() -> void:
				if is_instance_valid(sprite_node):
					sprite_node.z_index = 0)
	var cooked := Item.new()
	cooked.item_name = "Cooked Meat"
	cooked.item_type = Item.Type.FOOD
	cooked.heal_amount = 150
	cooked.icon_path = "res://sprites/items/Food/MeatCooked.png"
	cooked.description = "Roasted over a fire trap."
	return cooked

func search_around(pos: Vector2i, radius: int = 2) -> int:
	var found: int = 0
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx == 0 and dy == 0:
				continue
			var trap_pos: Vector2i = pos + Vector2i(dx, dy)
			if not has_line_of_sight(pos, trap_pos):
				continue
			if reveal_trap(trap_pos):
				found += 1
	return found

func get_unrevealed_traps() -> Array[Vector2i]:
	var result: Array[Vector2i] = []
	for pos: Vector2i in _traps:
		if not _traps[pos].get("revealed", false):
			result.append(pos)
	return result

func is_explored(pos: Vector2i) -> bool:
	return _explored.get(pos, false)

func is_tile_visible(pos: Vector2i) -> bool:
	return _visible_tiles.has(pos)

func get_room_centers() -> Array[Vector2i]:
	var centers: Array[Vector2i] = []
	for r: Rect2i in _data.rooms:
		centers.append(r.get_center())
	return centers

func _apply_trap_damage(entity: Node2D, damage: int, msg: String) -> void:
	if entity is Player:
		if GameState.invincible:
			GameState.game_log("[color=red]%s[/color] [color=gray](invincible)[/color]" % msg)
			return
		var actual: int = GameState.player_stats.take_damage(damage)
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.game_log("[color=red]%s[/color] You take [color=yellow]%d[/color] damage!" % [msg, actual])
		show_damage(entity.position, actual, true)
		GameState.check_player_death()
	elif entity is Enemy:
		var e: Enemy = entity as Enemy
		var actual: int = e.stats.take_damage(damage)
		e.update_hp_bar()
		show_damage(e.position, actual, false)
		GameState.game_log("[color=orange]%s[/color] triggers a trap for [color=yellow]%d[/color] damage!" % [e.display_name, actual])
		if e.stats.is_dead():
			GameState.game_log("[color=orange]%s[/color] [color=gray]is killed by a trap.[/color]" % e.display_name)
			GameState.gain_exp(maxi(1, e.exp_reward / 2))
			remove_enemy(e)
			e.die()

func _push_entity(entity: Node2D, push_dir: Vector2i, distance: int, trap_sprite: Sprite2D = null) -> void:
	if not is_instance_valid(entity):
		if is_instance_valid(trap_sprite):
			await _play_trap_animation(trap_sprite)
		return
	var e: Entity = entity as Entity
	var current: Vector2i = e.grid_pos
	var hit_wall: bool = false
	for _i: int in distance:
		var nxt: Vector2i = current + push_dir
		if not _data.is_walkable(nxt):
			hit_wall = true
			break
		if entity is Player and get_enemy_at(nxt) != null:
			hit_wall = true
			break
		if entity is Enemy and _player != null and _player.grid_pos == nxt:
			hit_wall = true
			break
		current = nxt
	if is_instance_valid(trap_sprite):
		_play_trap_animation(trap_sprite)  # fires async — simultaneous with movement
	if current != e.grid_pos:
		await e.move_to(current, 0.15)
	if not is_instance_valid(entity):
		return
	var push_dmg: int = 2 + GameState.current_floor / 2
	if hit_wall:
		push_dmg += 4
	var wall_str: String = " into a wall" if hit_wall else ""
	if entity is Player:
		var actual: int = GameState.player_stats.take_damage(push_dmg)
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.game_log("[color=red]You are blasted%s for [color=yellow]%d[/color] damage![/color]" % [wall_str, actual])
		GameState.check_player_death()
	elif entity is Enemy:
		var enemy: Enemy = entity as Enemy
		var actual: int = enemy.stats.take_damage(push_dmg)
		enemy.update_hp_bar()
		GameState.game_log("[color=orange]%s[/color] is blasted%s for [color=yellow]%d[/color] damage!" % [enemy.display_name, wall_str, actual])
		if enemy.stats.is_dead():
			GameState.game_log("[color=orange]%s[/color] [color=gray]is killed![/color]" % enemy.display_name)
			GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
			remove_enemy(enemy)
			enemy.die()

func _play_trap_animation(sprite_node: Sprite2D) -> void:
	if not is_instance_valid(sprite_node):
		return
	var tex: Texture2D = sprite_node.texture
	if tex == null:
		return
	var frame_count: int = int(tex.get_width()) / 32
	if frame_count <= 1:
		return
	for f: int in range(1, frame_count):
		if not is_instance_valid(sprite_node):
			return
		sprite_node.region_rect = Rect2(f * 32, 0, 32, 32)
		await get_tree().create_timer(0.07).timeout

# ── Door system ───────────────────────────────────────────────────────────────

func _spawn_doors() -> void:
	var cardinal: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]
	var door_candidates: Array = []  # Array[Vector2i], preserves per-room limit

	for room_entry in _data.rooms:
		var r: Rect2i = room_entry
		var added_for_room: int = 0

		# Check perimeter tiles of this room
		for y: int in range(r.position.y, r.position.y + r.size.y):
			if added_for_room >= 2:
				break
			for x: int in range(r.position.x, r.position.x + r.size.x):
				if added_for_room >= 2:
					break
				# Only border tiles of the room rect
				if x != r.position.x and x != r.position.x + r.size.x - 1 \
				   and y != r.position.y and y != r.position.y + r.size.y - 1:
					continue
				var pos: Vector2i = Vector2i(x, y)
				if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
					continue
				if pos == _data.player_start or pos == _data.stairs_pos:
					continue
				# Check if any neighbor outside this room is FLOOR and that corridor is 1 tile wide
				for d: Vector2i in cardinal:
					var out: Vector2i = pos + d
					if r.has_point(out):
						continue
					if _data.get_tile(out.x, out.y) != DungeonData.TileType.FLOOR:
						continue
					# Perpendicular directions — corridor must be narrow at this junction
					var perp1: Vector2i = Vector2i(-d.y, d.x)
					var perp2: Vector2i = Vector2i(d.y, -d.x)
					var narrow: bool = _data.get_tile((out + perp1).x, (out + perp1).y) == DungeonData.TileType.WALL \
						and _data.get_tile((out + perp2).x, (out + perp2).y) == DungeonData.TileType.WALL
					# Place door at the corridor tile (out), not the room border (pos)
					if narrow and not door_candidates.has(out):
						# Reject if within 2 tiles of any existing door (prevents adjacent doors in short corridors)
						var too_close: bool = false
						for ex: Vector2i in door_candidates:
							if maxi(abs(out.x - ex.x), abs(out.y - ex.y)) <= 2:
								too_close = true
								break
						if not too_close:
							door_candidates.append(out)
							added_for_room += 1
					break

	# Place doors with 65% probability, max 2 per room is handled by room perimeter size
	var tex_closed: Texture2D = null
	var tex_open: Texture2D = null
	if ResourceLoader.exists(OBJECTS_PATH + "doors_leaf_closed.png"):
		tex_closed = load(OBJECTS_PATH + "doors_leaf_closed.png")
	if ResourceLoader.exists(OBJECTS_PATH + "doors_leaf_open.png"):
		tex_open = load(OBJECTS_PATH + "doors_leaf_open.png")

	for pos: Vector2i in door_candidates:
		if randf() > 0.65:
			continue
		if _traps.has(pos) or _floor_items.has(pos):
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex_closed
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
		sprite.z_index = 1
		# Scale sprite to exactly one tile
		if tex_closed != null:
			var ts: Vector2 = tex_closed.get_size()
			sprite.scale = Vector2(float(TILE_SIZE) / ts.x, float(TILE_SIZE) / ts.y)
		entities.add_child(sprite)
		_doors[pos] = {"is_open": false, "locked": false, "player_locked": false, "sprite": sprite, "tex_open": tex_open, "tex_closed": tex_closed}

func has_door_at(pos: Vector2i) -> bool:
	return _doors.has(pos)

func is_door_open(pos: Vector2i) -> bool:
	if not _doors.has(pos):
		return true
	if _doors[pos]["locked"]:
		return false
	return _doors[pos]["is_open"]

func is_door_locked(pos: Vector2i) -> bool:
	return _doors.has(pos) and _doors[pos]["locked"]

func is_door_player_locked(pos: Vector2i) -> bool:
	return _doors.has(pos) and _doors[pos].get("player_locked", false)

func _add_lock_icon_at(pos: Vector2i) -> void:
	if _lock_icon_tex == null or _doors[pos].has("lock_icon"):
		return
	var icon := Sprite2D.new()
	icon.texture = _lock_icon_tex
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + 3.0)
	icon.scale = Vector2(0.5, 0.5)
	icon.z_index = 1
	entities.add_child(icon)
	_doors[pos]["lock_icon"] = icon

func lock_door(pos: Vector2i, by_player: bool = false) -> void:
	if not _doors.has(pos) or _doors[pos]["is_open"] or _doors[pos]["locked"]:
		return
	_doors[pos]["locked"] = true
	_doors[pos]["player_locked"] = by_player
	var sp: Sprite2D = _doors[pos]["sprite"]
	if is_instance_valid(sp):
		sp.modulate = Color(0.55, 0.35, 0.85)  # purple tint = locked
	_add_lock_icon_at(pos)
	AudioManager.play("lock_door")

func unlock_door(pos: Vector2i) -> void:
	if not _doors.has(pos):
		return
	_doors[pos]["locked"] = false
	var sp: Sprite2D = _doors[pos]["sprite"]
	if is_instance_valid(sp):
		sp.modulate = Color(1.0, 1.0, 1.0)
	if _doors[pos].has("lock_icon"):
		var icon: Node = _doors[pos]["lock_icon"]
		if is_instance_valid(icon):
			icon.queue_free()
		_doors[pos].erase("lock_icon")

func open_door(pos: Vector2i) -> void:
	if not _doors.has(pos) or _doors[pos]["is_open"] or _doors[pos]["locked"]:
		return
	_doors[pos]["is_open"] = true
	var sp: Sprite2D = _doors[pos]["sprite"]
	if is_instance_valid(sp):
		sp.texture = _doors[pos]["tex_open"]
	AudioManager.play("open_door")
	if _player != null:
		update_fog(_player.grid_pos)

func close_door(pos: Vector2i) -> void:
	if not _doors.has(pos) or not _doors[pos]["is_open"]:
		return
	if _player != null and _player.grid_pos == pos:
		return
	for e: Enemy in _enemies:
		if is_instance_valid(e) and e.grid_pos == pos:
			return
	if _floor_items.has(pos):
		return
	_doors[pos]["is_open"] = false
	var sp: Sprite2D = _doors[pos]["sprite"]
	if is_instance_valid(sp):
		sp.texture = _doors[pos]["tex_closed"]
	AudioManager.play("close_door")
	if _player != null:
		update_fog(_player.grid_pos)

# ── Grass ─────────────────────────────────────────────────────────────────────

func destroy_grass(pos: Vector2i) -> void:
	if _data.get_tile(pos.x, pos.y) != DungeonData.TileType.GRASS:
		return
	_data.grid[pos.y][pos.x] = DungeonData.TileType.TRAMPLED_GRASS
	_grass_layer.set_cell(pos, SOURCE_TRAMPLED_GRASS, ATLAS_ORIGIN)

# ── Items ─────────────────────────────────────────────────────────────────────

func _build_floor_item(pos: Vector2i, d: Dictionary) -> void:
	var item := Item.new()
	item.item_name = d["name"]
	item.item_type = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.heal_dice_count = d.get("heal_dice", 0)
	item.heal_dice_sides = d.get("heal_sides", 0)
	item.damage_type = d.get("dmg_type", "")
	item.str_bonus = d.get("str_bonus", 0)
	item.is_ranged = d.get("is_ranged", false)
	item.range = d.get("range", 0)
	item.consumes_on_ranged = d.get("consumes", false)
	item.quantity = d.get("qty", 1)
	item.floor_min = d["fmin"]
	item.floor_max = d["fmax"]
	item.description = d["desc"]
	var base_path: String
	match d["src"]:
		"weapons": base_path = WEAPONS_PATH
		"items":   base_path = ITEMS_PATH
		_:         base_path = OBJECTS_PATH
	var icon_path: String = base_path + d["icon"]
	item.icon_path = icon_path
	var tex: Texture2D
	if ResourceLoader.exists(icon_path):
		tex = load(icon_path)
	else:
		var fallback_img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color(0.80, 0.55, 0.15))
		tex = ImageTexture.create_from_image(fallback_img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	entities.add_child(sprite)
	_floor_items[pos] = item
	_floor_item_sprites[pos] = sprite

func _spawn_items() -> void:
	var eligible: Array = []
	for entry in ITEM_POOL:
		var d: Dictionary = entry
		if GameState.current_floor >= d["fmin"] and GameState.current_floor <= d["fmax"]:
			eligible.append(d)
	if eligible.is_empty():
		return

	var candidates: Array = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			var tile: DungeonData.TileType = _data.get_tile(x, y)
			if tile != DungeonData.TileType.FLOOR and tile != DungeonData.TileType.MUD:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos):
				continue
			candidates.append(pos)
	candidates.shuffle()

	var count: int = mini(randi_range(2, 3), candidates.size())
	for i: int in count:
		var d: Dictionary = eligible[randi() % eligible.size()]
		_build_floor_item(candidates[i], d)

func _spawn_locked_doors() -> void:
	if _doors.is_empty():
		return
	var eligible: Array = []
	for entry: Dictionary in ITEM_POOL:
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"]:
			eligible.append(entry)
	if eligible.is_empty():
		return

	var door_positions: Array = _doors.keys()
	door_positions.shuffle()

	for pos: Vector2i in door_positions:
		# Skip already-locked doors (shouldn't happen at gen time, but be safe)
		if _doors[pos]["locked"]:
			continue
		# Critical path check: player must still reach stairs without this door
		if not _bfs_reachable(_data.player_start, _data.stairs_pos, [pos]):
			continue

		# Find tiles behind this door (unreachable from start when door is blocked)
		var reachable: Dictionary = _bfs_collect(_data.player_start, [pos])
		var reward_candidates: Array[Vector2i] = []
		for room: Rect2i in _data.rooms:
			var rc: Vector2i = Vector2i(room.get_center())
			if reachable.has(rc):
				continue
			for ry: int in range(room.position.y, room.position.y + room.size.y):
				for rx: int in range(room.position.x, room.position.x + room.size.x):
					var rp: Vector2i = Vector2i(rx, ry)
					if _data.get_tile(rx, ry) != DungeonData.TileType.FLOOR:
						continue
					if rp == _data.stairs_pos or rp == _data.player_start:
						continue
					if _traps.has(rp) or _floor_items.has(rp) or _doors.has(rp):
						continue
					reward_candidates.append(rp)

		if reward_candidates.is_empty():
			continue

		# Lock the door (no audio at generation time; dungeon-generated = not player_locked)
		_doors[pos]["locked"] = true
		_doors[pos]["player_locked"] = false
		var sp: Sprite2D = _doors[pos]["sprite"]
		if is_instance_valid(sp):
			sp.modulate = Color(0.55, 0.35, 0.85)
		_add_lock_icon_at(pos)

		# Spawn 2–3 reward items in the locked room
		reward_candidates.shuffle()
		var count: int = mini(randi_range(2, 3), reward_candidates.size())
		for i: int in count:
			var d: Dictionary = eligible[randi() % eligible.size()]
			_build_floor_item(reward_candidates[i], d)

		break  # max 1 locked door per floor

func get_item_at(pos: Vector2i) -> Item:
	return _floor_items.get(pos, null) as Item

func remove_floor_item(pos: Vector2i) -> void:
	if _floor_item_sprites.has(pos):
		var sn: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(sn):
			sn.queue_free()
		_floor_item_sprites.erase(pos)
	_floor_items.erase(pos)

func drop_boss_loot(pos: Vector2i) -> void:
	var loot_pool: Array = []
	if GameState.current_floor >= 8:
		loot_pool = [
			{"name": "Lavish Sword",   "type": 0, "icon": "weapon_lavish_sword.png",  "src": "weapons", "bonus_dmg": 5, "heal": 0, "str_bonus": 0, "fmin": 8, "fmax": 10, "desc": "+5 damage"},
			{"name": "Golden Sword",   "type": 0, "icon": "weapon_golden_sword.png",  "src": "weapons", "bonus_dmg": 4, "heal": 0, "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "+4 damage"},
		]
	else:
		loot_pool = [
			{"name": "Knight Sword",   "type": 0, "icon": "weapon_knight_sword.png",  "src": "weapons", "bonus_dmg": 3, "heal": 0, "str_bonus": 0, "fmin": 4, "fmax": 8,  "desc": "+3 damage"},
			{"name": "Strength Potion","type": 2, "icon": "Potions/Mana/ManaPotionMedium.png", "src": "items", "bonus_dmg": 2, "heal": 0, "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)"},
		]
	var d: Dictionary = loot_pool[randi() % loot_pool.size()]

	var item := Item.new()
	item.item_name = d["name"]
	item.item_type = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.str_bonus = d.get("str_bonus", 0)
	item.floor_min = d["fmin"]
	item.floor_max = d["fmax"]
	item.description = d["desc"]
	match d["src"]:
		"weapons": item.icon_path = WEAPONS_PATH + d["icon"]
		"items":   item.icon_path = ITEMS_PATH + d["icon"]
		_:         item.icon_path = OBJECTS_PATH + d["icon"]
	place_item_on_floor(pos, item)
	GameState.game_log("[color=yellow][b]The boss dropped [/b][color=white]%s[/color][b]![/b][/color]" % item.item_name)
