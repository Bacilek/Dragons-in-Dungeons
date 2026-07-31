class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const FLOOR_ICON_MAX_PX: float = 24.0  # place_item_on_floor()'s longest-side clamp — 1.5x TILE_SIZE, lets art poke past the tile a bit without covering the screen
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

const CR_BUDGET_BASE: float = 1.0
const CR_BUDGET_PER_FLOOR: float = 0.35
const CR_BUDGET_DEFAULT_CR: float = 0.25
const BOSS_FLOOR_BUDGET_SCALE: float = 0.4
const CR_BUDGET_SAFETY_CAP: int = 12
const FOV_RADIUS: int = 5
const TRAP_COUNT_MIN: int = 4
const TRAP_COUNT_MAX: int = 7
const TRAP_PATH := "res://sprites/traps/"

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _grass_layer: TileMapLayer

var _data: DungeonData
var _player: Player
var _enemies: Array[Enemy] = []
var _companions: Array = []  # Array[Companion] — ally entities processed in enemy phase
var _traps: Dictionary = {}         # Vector2i → {name, damage, msg, sprite_node, revealed, triggered, is_push}
var _dispensers: Dictionary = {}    # Vector2i → {revealed: bool, spent: bool, tripwire_pos: Vector2i} — Tripwire trap's hidden poison-dart shooter, disguised as plain floor (see "Tripwire trap" below)
var _doors: Dictionary = {}         # Vector2i → {is_open: bool, sprite: Sprite2D}
var _barrels: Dictionary = {}       # Vector2i → {sprite: Sprite2D, burning: bool, material: String, ac: int, hp: int, max_hp: int} — see "Flammable props" below
const BARREL_TEX_PATH: String = DungeonFloorData.OBJECTS_PATH + "crate.png"
const BARREL_COUNT_MIN: int = 1
const BARREL_COUNT_MAX: int = 3
const BARREL_MATERIAL: String = "wood"
const BARREL_MAX_HP: int = 5
const DOOR_MATERIAL: String = "wood"
const DOOR_MAX_HP: int = 10
const FIRE_TINT := Color(1.0, 0.5, 0.25)
var _burning_grass: Dictionary = {}  # Vector2i → true — GRASS tiles mid-burn, see "Grass" below (ignite_grass()/_tick_burning_grass())

# Blacksmith prop (BlacksmithRoom, always floor 4 — see scripts/dungeon/CLAUDE.md). Same
# dict-of-tile convention as _barrels/_traps/_doors, but no burn/interaction state of its own —
# just a solid, impassable landmark tile the player bumps/RMB-interacts with to open
# blacksmith_panel.gd. No dedicated art exists yet — reuses crate.png with a distinct tint,
# same "no art yet" placeholder precedent as several weapons/armor entries.
var _blacksmiths: Dictionary = {}   # Vector2i → {sprite: Sprite2D}
const BLACKSMITH_TEX_PATH: String = DungeonFloorData.OBJECTS_PATH + "crate.png"
const BLACKSMITH_TINT := Color(0.85, 0.55, 0.35)

var _shopkeepers: Dictionary = {}   # Vector2i → {sprite: Sprite2D, stock: Array[Item]}
# No dedicated shopkeeper sprite exists in the live sprites/ tree yet (see root CLAUDE.md's
# Sprite Assets — sprites/characters/npcs/ is reserved but empty). Try a future dwarf NPC sprite
# first (ResourceLoader.exists() guard, same convention as BLACKSMITH_TEX_PATH), falling back to
# the same crate.png placeholder Blacksmith uses, distinguished by its own tint.
const SHOPKEEPER_TEX_PATH: String = "res://sprites/characters/npcs/dwarf_m/idle_1.png"
const SHOPKEEPER_FALLBACK_TEX_PATH: String = DungeonFloorData.OBJECTS_PATH + "crate.png"
const SHOPKEEPER_TINT := Color(0.4, 0.75, 0.95)
const SHOP_STOCK_MIN: int = 4
const SHOP_STOCK_MAX: int = 6

# Spider's Web ability (see scripts/entities/CLAUDE.md's "Spider" entry) — a lightweight
# destructible-terrain dict, same shape/convention as _barrels above but with no burn-tick timer
# (a web only ever goes away via Player._attempt_web_escape()'s successful STR check, never on its
# own). Vector2i → {sprite: Sprite2D, hp: int, ac: int}. No dedicated art exists yet
# (ResourceLoader.exists guards it exactly like BARREL_TEX_PATH above) — mechanically fully wired,
# visually a no-op until a web sprite is authored.
var _webs: Dictionary = {}
const WEB_TEX_PATH: String = DungeonFloorData.OBJECTS_PATH + "web.png"
const WEB_HP: int = 5
const WEB_AC: int = 10

var _floor_items: Dictionary = {}
var _floor_item_sprites: Dictionary = {}
var _blood_decals: Array[Sprite2D] = []
var _lock_icon_tex: Texture2D = null
# Seeded per-floor population RNG (SEEDED_FLOOR_POPULATION.md): valid only during
# _load_floor()'s spawn block — never use elsewhere. Kept separate from the Rng
# autoload's gameplay stream so population stays a pure function of (run_seed, floor)
# and a reloaded save regenerates the identical floor.
var _pop_rng: RandomNumberGenerator
const POPULATION_SEED_MIX: int = 0x1234ABCD

var _fog_image: Image
var _fog_texture: ImageTexture
var _fog_sprite: Sprite2D
var _light_glow_sprites: Array[Sprite2D] = []  # Light cantrip glow — see _update_light_source_glow()
var _light_glow_tex: ImageTexture
var _torch_glow_sprites: Array[Sprite2D] = []  # lit floor/embedded Torch glow — see _update_torch_light_glow()
var _torch_glow_tex: ImageTexture
var _fog_cloud_sprites: Array[Sprite2D] = []  # Fog Cloud spell zone — see _update_fog_cloud_visual()
var _fog_cloud_tex: ImageTexture
var _fire_glow_sprites: Array[Sprite2D] = []  # every currently-burning Barrel/Door/grass tile — see _update_burning_tiles_glow()
var _fire_glow_tex: ImageTexture
var _tremor_marker_sprites: Array[Sprite2D] = []  # Dwarf Stonecunning's tremorsense ping — see _update_tremor_markers()
var _tremor_marker_tex: ImageTexture
var _detect_magic_marker_sprites: Array[Sprite2D] = []  # Detect Magic's own blue ping — see _update_detect_magic_markers()
var _detect_magic_marker_tex: ImageTexture
var _torch_fov_ring_sprites: Array[Sprite2D] = []  # equipped-lit-Torch's +1 FOV ring — see _update_torch_fov_ring_glow()
var _torch_fov_ring_tex: ImageTexture
var _celestial_fov_ring_sprites: Array[Sprite2D] = []  # Aasimar Inner Radiance's +2 FOV ring — see _update_celestial_fov_ring_glow()
var _celestial_fov_ring_tex: ImageTexture
var _darkvision_ring_sprites: Array[Sprite2D] = []  # darkvision's own FOV ring — see _update_darkvision_ring_glow()
var _darkvision_ring_tex: ImageTexture
var _explored: Dictionary = {}
var _visible_tiles: Dictionary = {}  # Vector2i → true; current FOV set, reset each update_fog
var _ignore_magical_darkness: bool = false  # true only during the player's own FOV shadowcast when Stats.sees_through_magical_darkness — see _blocks_los()
var _fov_player_pos: Vector2i = Vector2i(-1, -1)
var _see_all_active: bool = false

# Sphere-AoE spell-targeting preview (e.g. Fireball) — see "AoE targeting preview" below.
var _aoe_preview_rects: Array[Sprite2D] = []
var _aoe_preview_last_key: String = ""
const AOE_PREVIEW_TINT := Color(0.65, 0.25, 0.85, 0.35)
const AOE_PREVIEW_ENEMY_TINT := Color(0.9, 0.15, 0.15, 0.45)

# Blue "maximum reach" preview — every tile that could possibly be hit by the currently-targeted
# spell from the caster's own position (a wider, static backdrop behind the purple/red exact-
# footprint preview above). See "AoE targeting preview" below.
var _spell_range_rects: Array[Sprite2D] = []
var _spell_range_last_key: String = ""
var _spell_range_tex: ImageTexture
const SPELL_RANGE_TINT := Color(0.25, 0.55, 0.95, 0.20)

var _ranged_range_rects: Array[Sprite2D] = []
var _ranged_range_last_key: String = ""
var _ranged_range_tex: ImageTexture
const RANGED_NORMAL_TINT := Color(0.35, 0.65, 1.0, 0.20)
const RANGED_LONG_TINT := Color(0.05, 0.15, 0.5, 0.28)

# While any targeting preview (Shift ranged-range, or a spell's blue/purple/red preview) is on
# screen, the torch glow (yellow) and darkvision ring (dark gray) FOV-bonus overlays are hidden
# outright rather than left to visually blend with the preview's own colors — set by
# player.gd's per-frame preview updates, read by _update_torch_light_glow()/
# _update_darkvision_ring_glow() (both no-op to fully hidden while this is true, regardless of
# their own tile set) and consumed here to force an immediate re-show once the preview ends.
var fov_bonus_overlay_suppressed: bool = false

func set_fov_bonus_overlay_suppressed(v: bool) -> void:
	if v == fov_bonus_overlay_suppressed:
		return
	fov_bonus_overlay_suppressed = v
	if v:
		for spr: Sprite2D in _torch_glow_sprites:
			spr.visible = false
		for spr: Sprite2D in _darkvision_ring_sprites:
			spr.visible = false
	elif _player != null:
		update_fog(_player.grid_pos)

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
	# Light cantrip ending early (rest completion) doesn't otherwise trigger a fresh update_fog()
	# call — refresh immediately so the glow sprite/lit tiles disappear right away instead of
	# lingering until the player's next move.
	GameState.light_source_changed.connect(func() -> void: update_fog(_fov_player_pos))
	# Equipping/unequipping/lighting a Torch (or anything else touching effective_fov_radius())
	# is a free action (no turn cost — root CLAUDE.md's "Equip is always a free action") but fog
	# otherwise only recomputes on the player's NEXT real action — refresh immediately so the FOV
	# ring visibly grows/shrinks the instant gear changes, not a turn later.
	GameState.equipment_changed.connect(func() -> void: update_fog(_fov_player_pos))
	TurnManager.player_turn_started.connect(_resolve_pending_thrown_weapon_drops)
	# tick_burning_props()/tick_fire_damage_for() are called directly from player.gd's
	# _on_turn_started() now (start-of-round timing, see their own doc comments below) — no signal
	# connection needed here.

func _on_debug_jump_floor(_n: int) -> void:
	_load_floor()

func _setup_tileset() -> void:
	var tile_set := TileSet.new()
	tile_set.tile_size = Vector2i(TILE_SIZE, TILE_SIZE)
	_add_tile_source(tile_set, SOURCE_FLOOR,  TILE_SPRITES_PATH + "floor/1.png")
	_add_tile_source(tile_set, SOURCE_WALL,   TILE_SPRITES_PATH + "wall/mid.png")
	_add_tile_source(tile_set, SOURCE_STAIRS, TILE_SPRITES_PATH + "floor_stairs.png")
	# New tile types — extract from atlas sheets or use solid-color fallbacks
	_add_tile_source_or_color(tile_set, SOURCE_CHASM, TILE_SPRITES_PATH + "hole.png", Color(0.06, 0.04, 0.08))
	_add_tile_from_atlas(tile_set, SOURCE_WATER, "res://sprites/tiles/water_rock_dirt.png", 64, 16, Color(0.10, 0.30, 0.72))
	_add_tile_from_atlas(tile_set, SOURCE_MUD,   "res://sprites/tiles/water_rock_dirt.png",  0, 0, Color(0.30, 0.18, 0.08))
	_add_tile_from_atlas(tile_set, SOURCE_GRASS,         "res://sprites/tiles/grass.png", 368, 176, Color(0.10, 0.42, 0.10))
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_CLOSED,    DungeonFloorData.OBJECTS_PATH + "doors/leaf_closed.png", Color(0.5, 0.3, 0.1))
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_OPEN,      DungeonFloorData.OBJECTS_PATH + "doors/leaf_open.png",   Color(0.3, 0.2, 0.05))
	_add_tile_from_atlas(tile_set, SOURCE_TRAMPLED_GRASS, "res://sprites/tiles/grass.png", 352, 192, Color(0.38, 0.30, 0.10))
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
	_dispensers.clear()

	for pos: Vector2i in _doors:
		var sp: Sprite2D = _doors[pos].get("sprite")
		if sp != null and is_instance_valid(sp):
			sp.queue_free()
		if _doors[pos].has("lock_icon"):
			var icon: Node = _doors[pos]["lock_icon"]
			if is_instance_valid(icon):
				icon.queue_free()
	_doors.clear()

	for pos: Vector2i in _barrels:
		var bsp: Sprite2D = _barrels[pos].get("sprite")
		if bsp != null and is_instance_valid(bsp):
			bsp.queue_free()
	_barrels.clear()

	for pos: Vector2i in _blacksmiths:
		var ksp: Sprite2D = _blacksmiths[pos].get("sprite")
		if ksp != null and is_instance_valid(ksp):
			ksp.queue_free()
	_blacksmiths.clear()

	for pos: Vector2i in _shopkeepers:
		var ssp: Sprite2D = _shopkeepers[pos].get("sprite")
		if ssp != null and is_instance_valid(ssp):
			ssp.queue_free()
	_shopkeepers.clear()

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

	# Music: boss floors get boss theme, others get a random dungeon-ambient track
	if GameState.current_floor % 5 == 0:
		AudioManager.play_boss_music()
	else:
		AudioManager.play_random_bgm()

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

	if ResourceLoader.exists(DungeonFloorData.ITEMS_PATH + "misc/key_iron.png"):
		_lock_icon_tex = load(DungeonFloorData.ITEMS_PATH + "misc/key_iron.png")
	# Seeded floor population (SEEDED_FLOOR_POPULATION.md §2). The call order below AND
	# the number of _pop_rng draws inside each function are load-bearing for
	# reproducibility — reordering or inserting a draw changes everything downstream.
	_pop_rng = RandomNumberGenerator.new()
	_pop_rng.seed = GameState.run_seed ^ (GameState.current_floor * POPULATION_SEED_MIX)
	_spawn_traps()
	_spawn_tripwire_traps()
	_spawn_doors()
	_spawn_barrels()
	_spawn_items()
	_spawn_locked_doors()
	_spawn_special_rooms()
	_spawn_mold()
	_spawn_enemies()
	_spawn_pending_chasm_items()
	_spawn_gold_piles()
	_restore_companion_from_save()
	_setup_fog()
	_see_all_active = false
	update_fog(_data.player_start)
	if not GameState.debug_reveal_all.is_connected(reveal_all):
		GameState.debug_reveal_all.connect(reveal_all)
	if not GameState.debug_see_all.is_connected(_on_debug_see_all):
		GameState.debug_see_all.connect(_on_debug_see_all)
	if GameState.god_mode:
		_on_debug_see_all(true)

	# Floor-entry checkpoint (Save/Load Phase A, doc §2) — snapshot + write once the
	# floor is fully populated. No-op before class selection or after the run ended.
	SaveManager.checkpoint()

# ── Save/Load Continue flow (Phase A, session 3c) ─────────────────────────────

# Rebuild the current floor from the restored run_seed + current_floor after
# SaveManager.load_run(). Phase A does not restore mid-floor state — the floor
# regenerates fresh from the seeded generator, exactly like a normal floor load
# (doc §2 accepted limitation). Emits floor_changed so the HUD floor label /
# compass reset, since GameState.from_dict() deliberately does not.
func reload_from_save() -> void:
	_load_floor()
	GameState.floor_changed.emit(GameState.current_floor)

# Consume GameState.pending_companion_restore (set by GameState.from_dict()):
# rebuild the Wild Heart companion from WILD_HEART_COMPANION_STATS[rank] adjacent
# to the player start and restore its saved HP (doc §4.4). No-op on any normal
# (non-Continue) floor load — the dict is empty then.
func _restore_companion_from_save() -> void:
	var saved: Dictionary = GameState.pending_companion_restore
	GameState.pending_companion_restore = {}
	if saved.is_empty() or not bool(saved.get("alive", false)):
		return
	var rank: int = GameState.get_talent_rank("wild_companion")
	if rank <= 0:
		return
	var stats_data: Dictionary = GameState.WILD_HEART_COMPANION_STATS.get(rank, {})
	var spawn_pos: Vector2i = Vector2i(-1, -1)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for dir: Vector2i in dirs:
		var p: Vector2i = _data.player_start + dir
		if is_walkable_for_companion(p):
			spawn_pos = p
			break
	if spawn_pos == Vector2i(-1, -1):
		return
	var companion: Companion = Companion.new()
	companion.configure(stats_data)
	spawn_companion(companion, spawn_pos)  # add_child inside → _ready() creates stats
	GameState.player_companion = companion
	var max_hp: int = int(stats_data.get("hp", 10))
	companion.stats.current_hp = clampi(int(saved.get("current_hp", max_hp)), 1, max_hp)
	companion.update_hp_bar()

# ── Tilemap queries ───────────────────────────────────────────────────────────

func get_tile_type(pos: Vector2i) -> DungeonData.TileType:
	return _data.get_tile(pos.x, pos.y)

func is_walkable(pos: Vector2i) -> bool:
	if _doors.has(pos) and not _doors[pos]["is_open"]:
		return false
	if _barrels.has(pos):
		return false
	if _blacksmiths.has(pos):
		return false
	if _shopkeepers.has(pos):
		return false
	return _data.is_walkable(pos)

func is_walkable_for_enemy(pos: Vector2i, excluding: Enemy = null) -> bool:
	if not _data.is_walkable(pos):
		return false
	if _barrels.has(pos):
		return false
	if _blacksmiths.has(pos):
		return false
	if _shopkeepers.has(pos):
		return false
	if _doors.has(pos):
		# Closed doors block normal movement (enemy handles opening separately)
		if not _doors[pos]["is_open"]:
			return false
	if _player != null and _player.occupies(pos):
		return false
	for e in _enemies:
		if is_instance_valid(e) and e != excluding and e.occupies(pos):
			return false
	if _traps.has(pos):
		var trap: Dictionary = _traps[pos]
		if trap.get("is_push", false):
			return false  # Push traps always avoided
		if not trap.get("triggered", false):
			return false  # Active non-push traps avoided
		# Triggered single-use traps: enemy can walk through
	return true

# Whether an entire WxH footprint anchored at `top_left` is walkable for an enemy — every tile
# checked via is_walkable_for_enemy() above (so a large enemy needs a full free block, never a
# 1-wide corridor: a corridor's cross-section is only 1 tile, so no 2x2+ block can exist inside
# one). `excluding` should be the enemy doing the moving, so its own current footprint's tiles
# (which overlap the destination when it only steps 1 tile) never falsely block the move.
func is_area_walkable_for_enemy(top_left: Vector2i, size: Vector2i, excluding: Enemy = null) -> bool:
	for dy: int in size.y:
		for dx: int in size.x:
			if not is_walkable_for_enemy(top_left + Vector2i(dx, dy), excluding):
				return false
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

	var full_fov_radius: int = GameState.effective_fov_radius(player_pos)
	_ignore_magical_darkness = GameState.player_stats.sees_through_magical_darkness
	_visible_tiles = _compute_shadowcast(player_pos, full_fov_radius)
	_ignore_magical_darkness = false

	# Heavily Obscured terrain can't be seen INTO from outside it, even at the boundary tile —
	# _blocks_los() above already stops the shadowcast from reaching past a fog tile, but the
	# tile marking in _cast_light() happens before the block check runs, so the very first fog
	# tile along each ray would otherwise still show up as visible (same as a wall/grass tile
	# "showing its face"). Strip every heavily-obscured tile from an outside, non-magic-sight
	# viewer's own visible set so nothing inside the cloud (not even its edge) is ever revealed —
	# a player already standing inside the cloud (is_blinded) is unaffected: their own radius is
	# already collapsed to 1 by effective_fov_radius(), and immediate neighbors must stay visible.
	if not GameState.is_blinded(player_pos) and not GameState.player_stats.sees_through_magical_darkness:
		for pos: Vector2i in _visible_tiles.keys():
			if GameState.is_heavily_obscured(pos):
				_visible_tiles.erase(pos)

	# Torch/celestial/darkvision FOV bonus rings — tinted overlays diffed against progressively
	# larger shadowcasts, in the SAME order effective_fov_radius() sums them (base → torch →
	# celestial → darkvision), so each ring always sits at its own distinct band (torch closest,
	# darkvision furthest out), matching the real 5e stacking (a torch's light only reaches so far;
	# darkvision sees further into the dark past it). All empty outright when blinded — is_blinded()
	# already zeroes every bonus term inside effective_fov_radius(), so there's no "extra" radius to
	# ring.
	var torch_ring_tiles: Dictionary = {}
	var celestial_ring_tiles: Dictionary = {}
	var darkvision_ring_tiles: Dictionary = {}
	if not GameState.is_blinded(player_pos):
		var base_radius: int = DungeonFloor.FOV_RADIUS + GameState.fov_radius_bonus
		var torch_bonus: int = 1 if GameState.has_lit_torch_equipped() else 0
		var celestial_bonus: int = GameState.celestial_radiance_fov_bonus()
		var dark_bonus: int = GameState.player_stats.darkvision_bonus
		var base_tiles: Dictionary = _compute_shadowcast(player_pos, base_radius)
		var torch_tiles: Dictionary = _compute_shadowcast(player_pos, base_radius + torch_bonus) if torch_bonus > 0 else base_tiles
		var celestial_tiles: Dictionary = _compute_shadowcast(player_pos, base_radius + torch_bonus + celestial_bonus) if celestial_bonus > 0 else torch_tiles
		if torch_bonus > 0:
			for pos: Vector2i in torch_tiles:
				if not base_tiles.has(pos):
					torch_ring_tiles[pos] = true
		if celestial_bonus > 0:
			for pos: Vector2i in celestial_tiles:
				if not torch_tiles.has(pos):
					celestial_ring_tiles[pos] = true
		if dark_bonus > 0:
			for pos: Vector2i in _visible_tiles:
				if not celestial_tiles.has(pos):
					darkvision_ring_tiles[pos] = true
	_update_torch_fov_ring_glow(torch_ring_tiles)
	_update_celestial_fov_ring_glow(celestial_ring_tiles)
	_update_darkvision_ring_glow(darkvision_ring_tiles)

	# Light cantrip: ends the instant the lit thing is no longer there (item picked up, door
	# burnt away, grass destroyed/trampled by fire, barrel burnt down) — checked every fog
	# recompute, same cadence the light itself refreshes. Cleared directly (not via
	# GameState.clear_light_source()) to avoid re-entering update_fog(): that function's own emit
	# is wired straight back to update_fog() (see _ready() below), and we're already mid-update
	# here — this same call handles the resulting visual refresh below.
	if GameState.light_source_pos != Vector2i(-1, -1):
		var still_there: bool
		match GameState.light_source_kind:
			"door":
				still_there = has_door_at(GameState.light_source_pos)
			"grass":
				still_there = get_tile_type(GameState.light_source_pos) == DungeonData.TileType.GRASS
			"barrel":
				still_there = has_barrel_at(GameState.light_source_pos)
			"trap":
				still_there = not get_trap_at(GameState.light_source_pos).is_empty()
			_:
				still_there = GameState.light_source_item != null \
					and get_items_at(GameState.light_source_pos).has(GameState.light_source_item)
		if not still_there:
			GameState.light_source_pos = Vector2i(-1, -1)
			GameState.light_source_item = null
			GameState.light_source_kind = "item"

	# Darkness cast on an unattended floor item: ends the instant that specific item is picked up
	# (or otherwise removed) — same "cast on an object, ends if it's moved/taken" RAW rule as Light
	# above. Cleared directly (not via GameState.clear_darkness(), which has no signal to re-enter
	# update_fog() from anyway) and also ends Concentration if darkness is still the active spell.
	if GameState.darkness_item != null and not get_items_at(GameState.darkness_pos).has(GameState.darkness_item):
		if GameState.player_stats.concentration_spell_id == "darkness":
			GameState.player_stats.concentration_spell_id = ""
		GameState.player_stats.darkness_turns = 0
		GameState.clear_darkness()

	# A real light source, not cosmetic — union its own shadowcast (walls still block it, same
	# algorithm as the player's own FOV) into the visible-tiles set every time fog recomputes, so
	# tiles near the lit object become visible/explored even far from the player. The exact same
	# tile set also drives the colored glow tint below, so the visuals always match what's actually
	# lit rather than being a single decorative square.
	var lit_tiles: Dictionary = {}
	if GameState.light_source_pos != Vector2i(-1, -1):
		lit_tiles = _compute_shadowcast(GameState.light_source_pos, GameState.LIGHT_SOURCE_RADIUS)
		for pos: Vector2i in lit_tiles:
			_visible_tiles[pos] = true
	_update_light_source_glow(lit_tiles)

	# Torch: every lit Torch lying on the floor casts a radius-2 light bubble (GameState.
	# TORCH_LIGHT_RADIUS); one embedded in a live enemy instead casts a smaller radius-1 bubble
	# (GameState.TORCH_BURN_LIGHT_RADIUS) — both recomputed fresh every fog update (no persistent
	# registry to keep in sync with throw/pickup/drop/die/burnout). An embedded torch's bubble is
	# centered on its carrying enemy's CURRENT grid_pos, so it moves for free as the enemy moves,
	# without any dedicated tracking.
	var torch_tiles: Dictionary = _compute_torch_light_tiles()
	for pos: Vector2i in torch_tiles:
		_visible_tiles[pos] = true
	_update_torch_light_glow(torch_tiles)
	# Faerie Fire — an outlined creature (failed DEX save) emanates its own small light bubble,
	# same radius as a torch embedded in a burning creature (GameState.TORCH_BURN_LIGHT_RADIUS),
	# recomputed fresh every fog update off each outlined enemy's current grid_pos (moves for free,
	# no tracking needed) — mechanical FOV push-back only, no dedicated glow tint painted (documented
	# scope cut — see scripts/entities/CLAUDE.md's "Elf" section, Faerie Fire entry).
	for enemy: Enemy in get_all_enemies():
		if enemy.faerie_fire_turns > 0:
			for lit_pos: Vector2i in _compute_shadowcast(enemy.grid_pos, GameState.TORCH_BURN_LIGHT_RADIUS):
				_visible_tiles[lit_pos] = true
	_update_fog_cloud_visual()
	_update_burning_tiles_glow()
	_update_tremor_markers(player_pos)
	_update_detect_magic_markers(player_pos)

	# While Blinded (standing inside a Fog Cloud/Darkness zone), vision genuinely collapses to just
	# the currently-visible tiles — the normal "dimmed memory of already-explored tiles" fog-of-war
	# view is suppressed, so the player can't see the remembered dungeon layout around them, only
	# what effective_fov_radius()'s flattened 1-tile shadowcast actually reaches right now. Explored
	# tiles are still marked (so map memory outside the cloud is untouched once it ends).
	var _player_blinded: bool = GameState.is_blinded(player_pos)
	for y: int in _data.height:
		for x: int in _data.width:
			var tile_pos := Vector2i(x, y)
			if _visible_tiles.has(tile_pos):
				_explored[tile_pos] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif GameState.is_heavily_obscured(tile_pos) and not _player_blinded and not GameState.player_stats.sees_through_magical_darkness:
				# A tile inside a Fog Cloud/Darkness zone is never shown via the dimmed "remembered
				# map" even if it was explored before the cloud appeared there — you can't see into
				# a heavily-obscured area from outside it, full stop, not even a memory of its
				# layout. Deliberately doesn't touch _explored, so the tile renders normally again
				# once the cloud dissipates. A tile just outside the zone's own radius is untouched
				# by this branch (is_heavily_obscured() only matches strictly inside it).
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 1.0))
			elif _explored.get(tile_pos, false) and not _player_blinded:
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0.65))
			else:
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 1.0))

	_fog_texture.update(_fog_image)
	_update_enemy_visibility()
	if _see_all_active:
		_apply_see_all()
	if not stairs_was_known and _explored.get(_data.stairs_pos, false):
		GameState.stairs_discovered.emit()

# ── AoE targeting preview (e.g. Fireball, Burning Hands) ────────────────────────
# Purple tile tint following the mouse while a sphere- or cone-shaped spell is armed for targeting
# (player.gd's _update_spell_aoe_preview(), driven by PlayerSpellcasting.get_armed_spell()).
# Sphere: deliberately NOT LOS-filtered — a Fireball's blast fills its whole radius around a corner
# from the impact point (it's an explosion, not a line-of-sight laser), so the preview always shows
# the full raw circle — matches _resolve_sphere_aoe()'s own distance check exactly, just without
# its additional per-target LOS gate. Cone: IS LOS-filtered (SpellEffects.cone_tiles(), shared with
# the resolver) — a wall casts a "shadow" through the cone, same shape in the preview as the blast.
# Uses pooled Sprite2D + a shared 1×1 white texture (tinted via modulate), same Node2D-world
# convention as the fog overlay above, rather than a Control — this node lives under DungeonFloor
# (a Node2D), not a CanvasLayer.
var _aoe_preview_tex: ImageTexture

# `center_in_range` (default true): whether the impact point itself is a legally castable target
# (Chebyshev distance vs the spell's own range — same check try_cast_at() enforces). When false,
# the caster is aiming at a tile they couldn't actually cast at — footprint tiles still preview
# (purple), but no enemy anywhere in the footprint tints red, since nothing in an invalid cast
# actually gets hit. When true, every enemy in the footprint tints red regardless of its own
# individual distance from the caster — a splash spell aimed at the LAST valid tile in range still
# correctly reds out enemies caught in the overhang beyond that range circle, since the blast
# radius is centered on a legitimately-reachable impact point.
func show_aoe_preview(center: Vector2i, radius: int, center_in_range: bool = true, shape: String = "sphere") -> void:
	var tiles: Array[Vector2i] = []
	if shape == "cube":
		# Cube (Faerie Fire) — `radius` here is a literal SIDE LENGTH (2 = a 2x2 block), corner-
		# anchored at `center`, NOT a centered Chebyshev radius — matches SpellEffects.
		# _resolve_faerie_fire()'s own tile-gather exactly, so preview and real footprint can never
		# diverge. A centered radius-2 square would have been 5x5, far larger than the real spell's
		# small 2-tile cube.
		for dy: int in range(radius):
			for dx: int in range(radius):
				var t: Vector2i = center + Vector2i(dx, dy)
				if _in_grid_bounds(t):
					tiles.append(t)
	else:
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					var t: Vector2i = center + Vector2i(dx, dy)
					if _in_grid_bounds(t):
						tiles.append(t)
	_paint_aoe_preview_tiles("%s,%d,%d,%d,%d" % [shape, center.x, center.y, radius, int(center_in_range)], tiles, center_in_range)

# Every tile-preview overlay (blue max-reach backdrop, purple/red sphere footprint, two-tone ranged
# backdrop) is a raw Euclidean/Chebyshev disc computed from the caster's position with no wall/LOS
# filtering by design (see this section's own doc comments on show_aoe_preview()/
# show_spell_range_preview()) — but that also means, unfiltered, it would happily paint tiles past
# the map's own edge (VOID, x/y outside `_data.width`/`_data.height`) for a caster standing near a
# border. This is the one bounds check every such preview clips against — never a walkability/LOS
# filter, just "is this coordinate part of the level at all".
func _in_grid_bounds(pos: Vector2i) -> bool:
	return pos.x >= 0 and pos.y >= 0 and pos.x < _data.width and pos.y < _data.height

# Cone-shaped spell preview (Burning Hands) — same pooled-Sprite2D tint as show_aoe_preview()
# above, just fed the cone's tile set (SpellEffects.cone_tiles(), shared with the actual blast
# resolver so the preview and the real footprint always agree) instead of a Euclidean disc. A cone
# is always self-centered and direction-only (see try_cast_at()'s own exemption), so there's no
# "out of range aim point" concept here — every enemy caught in the cone always tints red.
func show_cone_preview(origin: Vector2i, aim: Vector2i, length: int) -> void:
	var key: String = "cone,%d,%d,%d,%d,%d" % [origin.x, origin.y, aim.x, aim.y, length]
	_paint_aoe_preview_tiles(key, SpellEffects.cone_tiles(origin, aim, length, self), true)

# Every tile in the footprint that has a known (non-invisible) enemy standing on it tints red
# ("to be hit") instead of the flat purple every other footprint tile gets — a splash spell
# (Burning Hands, Fireball) hitting several enemies shows all of them red, not just the one exact
# tile the player is precisely aiming at. `allow_enemy_tint` (see show_aoe_preview()'s
# `center_in_range` doc above) gates whether ANY tile in this footprint is allowed to tint red at
# all — every tile still shows purple regardless, since the footprint preview itself is always
# informative even when the exact aim point can't currently be cast at. **Also requires
# `is_tile_visible(t)`** — an enemy standing in a Heavily Obscured tile (Fog Cloud) that the caster
# can't actually see into (scripts/entities/CLAUDE.md's "Conditions"/"Fog Cloud") never tints red,
# even though it's still a valid blind-cast target mechanically; that tile just stays plain purple
# like any other footprint tile, so the preview never gives away an unseen enemy's exact position.
func _paint_aoe_preview_tiles(key: String, tiles: Array[Vector2i], allow_enemy_tint: bool = true) -> void:
	if key == _aoe_preview_last_key:
		return
	_aoe_preview_last_key = key
	if _aoe_preview_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_aoe_preview_tex = ImageTexture.create_from_image(img)
	while _aoe_preview_rects.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _aoe_preview_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.modulate = AOE_PREVIEW_TINT
		spr.z_index = 2
		add_child(spr)
		_aoe_preview_rects.append(spr)
	for i: int in _aoe_preview_rects.size():
		var spr: Sprite2D = _aoe_preview_rects[i]
		if i < tiles.size():
			var t: Vector2i = tiles[i]
			spr.position = Vector2(t.x * TILE_SIZE, t.y * TILE_SIZE)
			spr.modulate = AOE_PREVIEW_ENEMY_TINT if (allow_enemy_tint and is_tile_visible(t) and get_targetable_enemy_at(t) != null) else AOE_PREVIEW_TINT
			spr.visible = true
		else:
			spr.visible = false

# Single-target ENEMY spell / Shift-hover ranged-weapon preview — no AoE shape, so there's no
# purple footprint to paint; the hovered tile only ever shows anything at all (a red highlight)
# when a known, targetable enemy actually stands there, that tile is currently visible (an enemy
# hidden inside a Heavily Obscured Fog Cloud tile never highlights, even if hovered/known-about —
# same reasoning as _paint_aoe_preview_tiles() above), AND that tile is within `in_range` (default
# true — the exact attack/cast range, Chebyshev for spells or the weapon's own long-range check for
# ranged, computed by the caller). An enemy standing beyond max range never tints red, regardless
# of whether it happens to be visible/hovered — a shot/cast that can't actually reach it shouldn't
# imply it would be hit.
func show_single_target_preview(tile: Vector2i, in_range: bool = true) -> void:
	if in_range and is_tile_visible(tile) and get_targetable_enemy_at(tile) != null:
		_paint_aoe_preview_tiles("single,%d,%d" % [tile.x, tile.y], [tile])
	else:
		hide_aoe_preview()

# Blue "maximum reach" preview — every tile within `radius` of `center` (the caster) that the
# currently-armed spell could conceivably hit, shown as a wide static backdrop while any spell is
# armed for targeting (not just AoE shapes — single-target spells get one too). Independent pooled-
# Sprite2D set from the purple/red exact-footprint preview above so both can render at once (this
# one at a lower z-index so the exact footprint always reads on top of it).
func show_spell_range_preview(center: Vector2i, radius: int, euclidean: bool = false) -> void:
	var key: String = "range,%d,%d,%d,%d" % [center.x, center.y, radius, 1 if euclidean else 0]
	if key == _spell_range_last_key:
		return
	_spell_range_last_key = key
	if _spell_range_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_spell_range_tex = ImageTexture.create_from_image(img)
	var tiles: Array[Vector2i] = []
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			# Chebyshev, not Euclidean, for every non-cone spell — must match try_cast_at()'s own
			# range check exactly (see player_spellcasting.gd's dist_cheb comment), or a diagonal
			# tile at radius 1 (a touch spell like Mage Armor/Shocking Grasp) reads as "out of
			# range" in this backdrop despite being a perfectly valid cast.
			# A cone (Burning Hands) is different: its origin is always the caster and its aim can
			# point in any direction, so the true union of every possible cone orientation is a
			# EUCLIDEAN disc of radius `shape_size` (aiming straight at a tile puts it on the
			# cone's own zero-lateral-offset center line, reachable out to its full length) — a
			# Chebyshev square overstates this, including diagonal "corner" tiles whose real
			# Euclidean distance exceeds the cone's length and which the cone can therefore never
			# actually reach no matter how it's aimed (bugfix — this used to always use Chebyshev,
			# so Burning Hands' blue backdrop looked like a square the cone's own corners could
			# never fill).
			var in_range: bool = (dx * dx + dy * dy <= radius * radius) if euclidean else (maxi(absi(dx), absi(dy)) <= radius)
			if in_range:
				var t: Vector2i = center + Vector2i(dx, dy)
				if _in_grid_bounds(t):
					tiles.append(t)
	while _spell_range_rects.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _spell_range_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.modulate = SPELL_RANGE_TINT
		spr.z_index = 1
		add_child(spr)
		_spell_range_rects.append(spr)
	for i: int in _spell_range_rects.size():
		var spr: Sprite2D = _spell_range_rects[i]
		if i < tiles.size():
			spr.position = Vector2(tiles[i].x * TILE_SIZE, tiles[i].y * TILE_SIZE)
			spr.visible = true
		else:
			spr.visible = false

func hide_spell_range_preview() -> void:
	if _spell_range_last_key == "":
		return
	_spell_range_last_key = ""
	for spr: Sprite2D in _spell_range_rects:
		spr.visible = false

# Ranged-weapon targeting preview (Shift+hover) — two-tone reach backdrop, driven every frame from
# player.gd's ranged-preview update while Shift is held and a ranged weapon is equipped, no spell
# armed. Light blue = normal range (full accuracy); darker blue = the extra long-range band (shot
# still possible but rolls with Disadvantage) — same normal/long split as
# `PlayerRanged.is_ranged_target_in_range()`/`ranged_shot_disadvantage()`. The hovered enemy tile's
# own red highlight is handled separately by `show_single_target_preview()` (shared with
# single-target spells) — this function only paints the backdrop.
func show_ranged_range_preview(center: Vector2i, normal_radius: int, long_radius: int) -> void:
	var key: String = "ranged,%d,%d,%d,%d" % [center.x, center.y, normal_radius, long_radius]
	if key == _ranged_range_last_key:
		return
	_ranged_range_last_key = key
	if _ranged_range_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_ranged_range_tex = ImageTexture.create_from_image(img)
	var tiles: Array[Vector2i] = []
	var tints: Array[Color] = []
	for dy: int in range(-long_radius, long_radius + 1):
		for dx: int in range(-long_radius, long_radius + 1):
			var dist_sq: int = dx * dx + dy * dy
			var t: Vector2i = center + Vector2i(dx, dy)
			if not _in_grid_bounds(t):
				continue
			if dist_sq <= normal_radius * normal_radius:
				tiles.append(t)
				tints.append(RANGED_NORMAL_TINT)
			elif dist_sq <= long_radius * long_radius:
				tiles.append(t)
				tints.append(RANGED_LONG_TINT)
	while _ranged_range_rects.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _ranged_range_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 1
		add_child(spr)
		_ranged_range_rects.append(spr)
	for i: int in _ranged_range_rects.size():
		var spr: Sprite2D = _ranged_range_rects[i]
		if i < tiles.size():
			spr.position = Vector2(tiles[i].x * TILE_SIZE, tiles[i].y * TILE_SIZE)
			spr.modulate = tints[i]
			spr.visible = true
		else:
			spr.visible = false

func hide_ranged_range_preview() -> void:
	if _ranged_range_last_key == "":
		return
	_ranged_range_last_key = ""
	for spr: Sprite2D in _ranged_range_rects:
		spr.visible = false

# Light cantrip's visual glow — tints every tile actually reached by the light's own shadowcast
# (lit_tiles, computed once in update_fog() and passed in here — same set that pushes back fog),
# not just a single square over the source tile. Pooled Sprite2D + shared 1×1 white texture, same
# convention as show_aoe_preview() above.
func _update_light_source_glow(lit_tiles: Dictionary) -> void:
	if GameState.light_source_pos == Vector2i(-1, -1) or lit_tiles.is_empty():
		for spr: Sprite2D in _light_glow_sprites:
			spr.visible = false
		return
	if _light_glow_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_light_glow_tex = ImageTexture.create_from_image(img)
	var tiles: Array = lit_tiles.keys()
	while _light_glow_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _light_glow_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_light_glow_sprites.append(spr)
	var tint := Color(GameState.light_source_color.r, GameState.light_source_color.g, GameState.light_source_color.b, 0.28)
	for i: int in _light_glow_sprites.size():
		var spr: Sprite2D = _light_glow_sprites[i]
		if i < tiles.size():
			var pos: Vector2i = tiles[i]
			spr.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
			spr.modulate = tint
			spr.visible = true
		else:
			spr.visible = false

# Equipped-lit-Torch's own +1 FOV bonus ring (distinct from the floor/embedded Torch light bubble
# below) — a faint, pale-yellow tint over just the outermost ring of tiles the torch itself grants,
# so the extra visibility reads as a small noticeable bonus without overpowering the rest of FOV.
func _update_torch_fov_ring_glow(ring_tiles: Dictionary) -> void:
	if ring_tiles.is_empty():
		for spr: Sprite2D in _torch_fov_ring_sprites:
			spr.visible = false
		return
	if _torch_fov_ring_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_torch_fov_ring_tex = ImageTexture.create_from_image(img)
	var tiles: Array = ring_tiles.keys()
	while _torch_fov_ring_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _torch_fov_ring_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_torch_fov_ring_sprites.append(spr)
	for i: int in _torch_fov_ring_sprites.size():
		var spr: Sprite2D = _torch_fov_ring_sprites[i]
		if i < tiles.size():
			var pos: Vector2i = tiles[i]
			spr.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
			spr.modulate = Color(1.0, 0.95, 0.55, 0.16)
			spr.visible = true
		else:
			spr.visible = false

# Aasimar Inner Radiance's own +2 FOV bonus ring (GameState.celestial_radiance_fov_bonus()) —
# sits between the torch ring and the darkvision ring (same "base -> torch -> celestial ->
# darkvision" order effective_fov_radius() sums its terms in), tinted a bright celestial
# gold/yellow — warmer and brighter than the torch's own pale-yellow ring, reading as divine light
# rather than a mundane flame.
func _update_celestial_fov_ring_glow(ring_tiles: Dictionary) -> void:
	if ring_tiles.is_empty():
		for spr: Sprite2D in _celestial_fov_ring_sprites:
			spr.visible = false
		return
	if _celestial_fov_ring_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_celestial_fov_ring_tex = ImageTexture.create_from_image(img)
	var tiles: Array = ring_tiles.keys()
	while _celestial_fov_ring_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _celestial_fov_ring_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_celestial_fov_ring_sprites.append(spr)
	for i: int in _celestial_fov_ring_sprites.size():
		var spr: Sprite2D = _celestial_fov_ring_sprites[i]
		if i < tiles.size():
			var pos: Vector2i = tiles[i]
			spr.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
			spr.modulate = Color(1.0, 0.92, 0.45, 0.22)
			spr.visible = true
		else:
			spr.visible = false

# Darkvision's own FOV bonus ring — the ring of tiles seen only because of darkvision (standard or
# superior, same field just a bigger radius — see Stats.darkvision_bonus), always the OUTERMOST
# ring (computed past the torch ring in update_fog(), never overlapping it). Tinted a dim, desaturated
# gray rather than the torch's warm yellow — darkvision reads as monochrome/dusky sight, not light.
func _update_darkvision_ring_glow(ring_tiles: Dictionary) -> void:
	if ring_tiles.is_empty() or fov_bonus_overlay_suppressed:
		for spr: Sprite2D in _darkvision_ring_sprites:
			spr.visible = false
		return
	if _darkvision_ring_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_darkvision_ring_tex = ImageTexture.create_from_image(img)
	var tiles: Array = ring_tiles.keys()
	while _darkvision_ring_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _darkvision_ring_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_darkvision_ring_sprites.append(spr)
	for i: int in _darkvision_ring_sprites.size():
		var spr: Sprite2D = _darkvision_ring_sprites[i]
		if i < tiles.size():
			var pos: Vector2i = tiles[i]
			spr.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
			spr.modulate = Color(0.25, 0.27, 0.32, 0.38)
			spr.visible = true
		else:
			spr.visible = false

# Torch: sweeps every lit-and-unburnt Torch currently lying on this floor's ground or embedded in
# one of its live enemies, and unions a shadowcast per torch found into a single result dict —
# floor torches get a radius-2 bubble (GameState.TORCH_LIGHT_RADIUS) at their own tile; embedded
# torches get a SMALLER radius-1 bubble (GameState.TORCH_BURN_LIGHT_RADIUS) at their carrying
# enemy's CURRENT grid_pos (so the bubble moves with the enemy for free, no extra tracking) — a
# torch stuck in a moving, burning creature lights less than one just sitting on the ground.
# Called fresh every update_fog() — no persistent state, so throw/pickup/drop/die/burnout all
# "just work" without any dedicated cleanup code anywhere.
func _compute_torch_light_tiles() -> Dictionary:
	var result: Dictionary = {}
	for pos: Vector2i in _floor_items.keys():
		for it: Item in _floor_items[pos]:
			if it.is_torch and it.torch_lit:
				for lit_pos: Vector2i in _compute_shadowcast(pos, GameState.TORCH_LIGHT_RADIUS):
					result[lit_pos] = true
	for enemy: Enemy in get_all_enemies():
		for it: Item in enemy.embedded_items:
			if it.is_torch and it.torch_lit:
				for lit_pos: Vector2i in _compute_shadowcast(enemy.grid_pos, GameState.TORCH_BURN_LIGHT_RADIUS):
					result[lit_pos] = true
	return result

# Fixed warm-orange glow (a Torch's flame isn't randomized/per-cast the way the Light cantrip's
# color is) — same pooled-Sprite2D convention as _update_light_source_glow() above, just its own
# sprite pool/texture so the two light sources' visuals never fight over the same nodes.
func _update_torch_light_glow(lit_tiles: Dictionary) -> void:
	if lit_tiles.is_empty() or fov_bonus_overlay_suppressed:
		for spr: Sprite2D in _torch_glow_sprites:
			spr.visible = false
		return
	if _torch_glow_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_torch_glow_tex = ImageTexture.create_from_image(img)
	var tiles: Array = lit_tiles.keys()
	while _torch_glow_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _torch_glow_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_torch_glow_sprites.append(spr)
	var tint := Color(1.0, 0.55, 0.1, 0.28)
	for i: int in _torch_glow_sprites.size():
		var spr: Sprite2D = _torch_glow_sprites[i]
		if i < tiles.size():
			var pos: Vector2i = tiles[i]
			spr.position = Vector2(pos.x * TILE_SIZE, pos.y * TILE_SIZE)
			spr.modulate = tint
			spr.visible = true
		else:
			spr.visible = false

# Torch: ticks down torch_turns_remaining once per real turn for every lit Torch lying on this
# floor's ground or embedded in one of its live enemies — the counterpart to player.gd's own
# equipped/quickbar/bag sweep (see _on_turn_started()). Called from there once per real turn.
# A lit Torch **embedded in an enemy** (thrown-and-landed, see scripts/items/CLAUDE.md's "Torch")
# also burns them for a fresh 2d4 Fire hit every round it stays lodged and lit — same rate as a
# creature standing on a burning door (tick_fire_damage_for() below), just applied through the
# embedded weapon instead of the tile. A lit Torch merely lying on the floor does NOT
# damage anything standing on its tile (unlike a burning door) — direct owner's ask was specifically
# about an embedded torch continuing to burn whoever it's stuck in, not floor-dropped torches.
func tick_torches() -> void:
	for pos: Vector2i in _floor_items.keys():
		for it: Item in _floor_items[pos]:
			if it.is_torch and it.torch_lit:
				it.torch_turns_remaining -= 1
				if it.torch_turns_remaining <= 0:
					GameState.burn_out_torch(it)
	for enemy: Enemy in get_all_enemies().duplicate():
		if not is_instance_valid(enemy):
			continue
		var still_burning: bool = false
		for it: Item in enemy.embedded_items:
			if it.is_torch and it.torch_lit:
				it.torch_turns_remaining -= 1
				if it.torch_turns_remaining <= 0:
					GameState.burn_out_torch(it)
				else:
					still_burning = true
		if still_burning and not enemy.stats.is_dead():
			var inst: Dictionary = _roll_fire_damage_instance()
			var result: Dictionary = enemy.take_typed_damage(int(inst["subtotal"]), "Fire")
			var actual: int = result["actual"]
			inst["final"] = actual
			inst["resist_mul"] = result["mul"]
			var dmg_meta: String = CombatMath.encode_damage_instance(inst)
			enemy.update_hp_bar()
			show_damage(enemy.position, actual, false, CombatMath.damage_type_color("Fire"))
			var is_lethal: bool = enemy.stats.is_dead()
			GameState.game_log("%s is scorched by the lodged torch for [url=%s][color=yellow]%d[/color][/url] Fire dmg.%s" % [
				enemy.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
			if is_lethal:
				GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
				remove_enemy(enemy)
				enemy.die()

# Fog Cloud / Darkness spell zones — two persistent, distinctly-tinted Heavily Obscured overlays
# over GameState.fog_cloud_pos/radius and GameState.darkness_pos/radius (a raw Euclidean disc each,
# same distance check as GameState.is_in_fog_cloud()/is_in_darkness() and show_aoe_preview()'s own
# preview circle — no LOS filtering, matching a real cloud/pool rather than a line-of-sight effect).
# Rebuilt every update_fog() call (cheap — pooled Sprite2Ds, same convention as the light glow
# above) so it tracks either zone fading/moving without needing its own dedicated signal.
# Colors are deliberately swapped from Darkness's original shared tint (Color(0.10, 0.10, 0.13,
# 0.80)) — Darkness keeps that near-black tone (it's the "true" magical darkness), Fog Cloud now
# gets a lighter, genuinely gray tone so the two zones read as visually distinct despite both being
# mechanically identical Heavily Obscured terrain (GameState.is_heavily_obscured() still treats
# them as equivalent).
const FOG_CLOUD_TINT := Color(0.55, 0.55, 0.58, 0.72)
const DARKNESS_TINT := Color(0.10, 0.10, 0.13, 0.80)
func _update_fog_cloud_visual() -> void:
	if GameState.fog_cloud_pos == Vector2i(-1, -1) and GameState.darkness_pos == Vector2i(-1, -1):
		for spr: Sprite2D in _fog_cloud_sprites:
			spr.visible = false
		return
	if _fog_cloud_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_fog_cloud_tex = ImageTexture.create_from_image(img)
	# A tile inside BOTH zones renders with Darkness's tint (drawn second, below) — Darkness reads
	# as the "stronger" effect of the two, matching its own dispel-the-lesser-light-source text.
	var tile_colors: Dictionary = {}  # Vector2i -> Color, insertion order preserved (fog first, darkness overwrites)
	for zone: Array in [[GameState.fog_cloud_pos, GameState.fog_cloud_radius, FOG_CLOUD_TINT], [GameState.darkness_pos, GameState.darkness_radius, DARKNESS_TINT]]:
		var center: Vector2i = zone[0]
		var radius: int = zone[1]
		var tint: Color = zone[2]
		if center == Vector2i(-1, -1):
			continue
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if dx * dx + dy * dy <= radius * radius:
					var t: Vector2i = center + Vector2i(dx, dy)
					# Deliberately NOT LOS-filtered (reverted — an earlier pass tried gating this
					# on has_line_of_sight(), but the direct owner wants the full footprint visible
					# whenever it's within the player's own explored/FOV range, not hidden behind
					# walls the moment any part of the zone dips out of view — the actual "can't
					# see into/out of it" blocking already lives in update_fog()'s _visible_tiles
					# stripping + dimmed-memory suppression below, not in this visual paint).
					# WALL tiles are excluded so the cloud never paints over/hides a wall — the map
					# geometry stays visible exactly where it is, the cloud's rendered footprint
					# just ends up smaller wherever it overlaps a wall.
					if _data.get_tile(t.x, t.y) != DungeonData.TileType.WALL:
						tile_colors[t] = tint
	var tiles: Array = tile_colors.keys()
	while _fog_cloud_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _fog_cloud_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_fog_cloud_sprites.append(spr)
	for i: int in _fog_cloud_sprites.size():
		var spr: Sprite2D = _fog_cloud_sprites[i]
		if i < tiles.size():
			var p: Vector2i = tiles[i]
			spr.position = Vector2(p.x * TILE_SIZE, p.y * TILE_SIZE)
			spr.modulate = tile_colors[p]
			spr.visible = true
		else:
			spr.visible = false

## Visual "this is on fire" indicator for every currently-burning tile — Barrels/Doors (which
## already get their own sprite's FIRE_TINT modulate) AND burning GRASS (`_burning_grass`, which
## has no sprite of its own to tint — a TileMapLayer cell can't be modulated per-instance the way
## a Sprite2D can). A translucent red overlay, same pooled-Sprite2D convention as the Fog Cloud/
## Light/Torch glows above, rebuilt every update_fog() call — needs no dedicated signal, just
## naturally tracks whatever's burning right now (including a barrel/door/grass tile going out).
func _update_burning_tiles_glow() -> void:
	var tiles: Array[Vector2i] = []
	for pos: Vector2i in _barrels.keys():
		if _barrels[pos]["burning"]:
			tiles.append(pos)
	for pos: Vector2i in _doors.keys():
		if _doors[pos].get("burning", false):
			tiles.append(pos)
	for pos: Vector2i in _burning_grass.keys():
		tiles.append(pos)
	if tiles.is_empty():
		for spr: Sprite2D in _fire_glow_sprites:
			spr.visible = false
		return
	if _fire_glow_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_fire_glow_tex = ImageTexture.create_from_image(img)
	while _fire_glow_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _fire_glow_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.z_index = 2
		add_child(spr)
		_fire_glow_sprites.append(spr)
	var tint := Color(1.0, 0.15, 0.05, 0.38)
	for i: int in _fire_glow_sprites.size():
		var spr: Sprite2D = _fire_glow_sprites[i]
		if i < tiles.size():
			spr.position = Vector2(tiles[i].x * TILE_SIZE, tiles[i].y * TILE_SIZE)
			spr.modulate = tint
			spr.visible = true
		else:
			spr.visible = false

## Dwarf Stonecunning's Tremorsense ping (scripts/entities/CLAUDE.md's "Dwarf" section). While
## GameState.player_stats.tremorsense_turns > 0, every living Enemy within Stats.STONECUNNING_RANGE
## (Chebyshev) standing on the EXACT SAME TileType as the player right now — and NOT already
## normally visible this FOV update — gets a shaking red dot at its tile. Sight-independent by
## design (works while Blinded/heavily obscured — this function never checks _visible_tiles or
## is_blinded()), which is the whole point: it's a vibration sense, not eyesight. Only reveals
## presence, never identity — same red dot regardless of which enemy it is. Rebuilt every
## update_fog() call, same pooled-Sprite2D convention as _update_burning_tiles_glow() above.
func _update_tremor_markers(player_pos: Vector2i) -> void:
	var tiles: Array[Vector2i] = []
	if GameState.player_stats.tremorsense_turns > 0:
		var player_tile: DungeonData.TileType = get_tile_type(player_pos)
		var range_t: int = Stats.STONECUNNING_RANGE
		for enemy: Enemy in _enemies:
			if not is_instance_valid(enemy) or enemy.stats.is_dead():
				continue
			if _visible_tiles.has(enemy.grid_pos) and not enemy.is_hidden_from_player():
				continue  # already plainly visible this turn — no ping needed
			var dist: int = maxi(absi(enemy.grid_pos.x - player_pos.x), absi(enemy.grid_pos.y - player_pos.y))
			if dist > range_t:
				continue
			if get_tile_type(enemy.grid_pos) != player_tile:
				continue
			tiles.append(enemy.grid_pos)
	if tiles.is_empty():
		for spr: Sprite2D in _tremor_marker_sprites:
			spr.visible = false
		return
	if _tremor_marker_tex == null:
		_tremor_marker_tex = _build_tremor_marker_texture()
	while _tremor_marker_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _tremor_marker_tex
		spr.centered = true
		spr.z_index = 4
		add_child(spr)
		_tremor_marker_sprites.append(spr)
		# Continuous "trembling" pulse — created once per pooled sprite, loops forever regardless
		# of which tile the sprite gets repositioned to on later refreshes.
		var tw: Tween = create_tween()
		tw.set_loops()
		tw.tween_property(spr, "scale", Vector2(1.3, 1.3), 0.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(spr, "scale", Vector2(0.8, 0.8), 0.3).set_trans(Tween.TRANS_SINE)
	for i: int in _tremor_marker_sprites.size():
		var spr2: Sprite2D = _tremor_marker_sprites[i]
		if i < tiles.size():
			spr2.position = Vector2(tiles[i].x * TILE_SIZE + TILE_SIZE / 2, tiles[i].y * TILE_SIZE + TILE_SIZE / 2)
			spr2.visible = true
		else:
			spr2.visible = false

## Small filled red circle (10px diameter) — no art asset exists or is needed, procedurally drawn
## once and cached, same "Image/ImageTexture, no dedicated asset" convention as the Tripwire rope
## sprite (scripts/world/CLAUDE.md's "Tripwire trap").
func _build_tremor_marker_texture() -> ImageTexture:
	const D: int = 10
	var img := Image.create(D, D, false, Image.FORMAT_RGBA8)
	var r: float = float(D) / 2.0
	for y: int in D:
		for x: int in D:
			var dx: float = float(x) - r + 0.5
			var dy: float = float(y) - r + 0.5
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, Color(1.0, 0.1, 0.1, 0.9))
	return ImageTexture.create_from_image(img)

## Detect Magic's own ping (scripts/entities/CLAUDE.md's "Elf" section, High Elf's level-3 grant —
## also a real learnable spell now, see SpellDb.LEVELED_SPELL_IDS). While
## GameState.player_stats.detect_magic_turns > 0, every magic item (Item.requires_attunement, or a
## nonzero bonus_ac/bonus_damage) lying on the floor within Spell.shape_size (3) tiles of the
## player (Chebyshev) gets a pulsing BLUE dot — same mechanism/texture-build pattern as Dwarf
## Stonecunning's tremorsense ping above, just a different color and reading items instead of
## creatures. Sight-independent by design (never checks _visible_tiles/is_blinded()) — the whole
## point of a magic-sense is that it isn't eyesight. Rebuilt every update_fog() call.
const DETECT_MAGIC_RANGE: int = 3
func _update_detect_magic_markers(player_pos: Vector2i) -> void:
	var tiles: Array[Vector2i] = []
	if GameState.player_stats.detect_magic_turns > 0:
		for dy: int in range(-DETECT_MAGIC_RANGE, DETECT_MAGIC_RANGE + 1):
			for dx: int in range(-DETECT_MAGIC_RANGE, DETECT_MAGIC_RANGE + 1):
				var p: Vector2i = player_pos + Vector2i(dx, dy)
				for item: Item in get_items_at(p):
					if item.requires_attunement or item.bonus_ac > 0 or item.bonus_damage > 0:
						tiles.append(p)
						break
	if tiles.is_empty():
		for spr: Sprite2D in _detect_magic_marker_sprites:
			spr.visible = false
		return
	if _detect_magic_marker_tex == null:
		_detect_magic_marker_tex = _build_detect_magic_marker_texture()
	while _detect_magic_marker_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _detect_magic_marker_tex
		spr.centered = true
		spr.z_index = 4
		add_child(spr)
		_detect_magic_marker_sprites.append(spr)
		var tw: Tween = create_tween()
		tw.set_loops()
		tw.tween_property(spr, "scale", Vector2(1.3, 1.3), 0.3).set_trans(Tween.TRANS_SINE)
		tw.tween_property(spr, "scale", Vector2(0.8, 0.8), 0.3).set_trans(Tween.TRANS_SINE)
	for i: int in _detect_magic_marker_sprites.size():
		var spr2: Sprite2D = _detect_magic_marker_sprites[i]
		if i < tiles.size():
			spr2.position = Vector2(tiles[i].x * TILE_SIZE + TILE_SIZE / 2, tiles[i].y * TILE_SIZE + TILE_SIZE / 2)
			spr2.visible = true
		else:
			spr2.visible = false

## Small filled blue circle (10px diameter) — same procedurally-drawn convention as
## _build_tremor_marker_texture(), just blue for "magic" instead of red for "creature".
func _build_detect_magic_marker_texture() -> ImageTexture:
	const D: int = 10
	var img := Image.create(D, D, false, Image.FORMAT_RGBA8)
	var r: float = float(D) / 2.0
	for y: int in D:
		for x: int in D:
			var dx: float = float(x) - r + 0.5
			var dy: float = float(y) - r + 0.5
			if dx * dx + dy * dy <= r * r:
				img.set_pixel(x, y, Color(0.25, 0.45, 1.0, 0.9))
	return ImageTexture.create_from_image(img)

func hide_aoe_preview() -> void:
	if _aoe_preview_last_key == "":
		return
	_aoe_preview_last_key = ""
	for spr: Sprite2D in _aoe_preview_rects:
		spr.visible = false

func _compute_shadowcast(center: Vector2i, radius: int = FOV_RADIUS) -> Dictionary:
	var visible: Dictionary = {}
	visible[center] = true
	for i: int in 8:
		_cast_light(visible, center, radius, 1, 1.0, 0.0,
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
			# Euclidean radius bound gives a normal circular FOV at any larger radius, but at
			# radius<=1 (Blinded — see GameState.effective_fov_radius()) it mathematically excludes
			# all 4 true diagonal neighbors (dx²+j²=2 > 1) — a groping-blind creature should still
			# sense all 8 adjacent tiles, not just the 4 cardinals. Chebyshev at radius<=1 only.
			var within_radius: bool = (maxi(absi(dx), absi(j)) <= radius) if radius <= 1 else (dx * dx + j * j <= r2)
			if within_radius and x >= 0 and x < _data.width and y >= 0 and y < _data.height:
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
			enemy.visible = _visible_tiles.has(enemy.grid_pos) and not enemy.is_hidden_from_player()
			# Faerie Fire overrides Invisibility's own visible=false — an outlined creature "can't
			# be invisible" (Elf lineage spell text): it's forced visible above, rendered at reduced
			# opacity instead of fully hidden, same translucent-tint convention as the player's own
			# invisibility visual (Player._update_invisibility_visual()).
			enemy.modulate.a = 0.4 if enemy.is_outlined_while_invisible() else 1.0

func _blocks_los(bx: int, by: int) -> bool:
	var t: DungeonData.TileType = _data.get_tile(bx, by)
	if t == DungeonData.TileType.WALL or t == DungeonData.TileType.GRASS:
		return true
	var pos := Vector2i(bx, by)
	if _doors.has(pos) and not _doors[pos]["is_open"]:
		return true
	# Heavily Obscured terrain (Fog Cloud) blocks sight like a wall — nothing beyond it is
	# visible from outside, unless the viewer can see through magical darkness (not granted by
	# anything today, see Stats.sees_through_magical_darkness). Shared by every shadowcast
	# (player FOV, torch/light-cantrip glows) and has_line_of_sight() (enemy AI/search) — none of
	# those callers have magic sight either, so this always blocks except during the player's own
	# FOV shadowcast when _ignore_magical_darkness is explicitly set.
	if not _ignore_magical_darkness and GameState.is_heavily_obscured(pos):
		return true
	return false

func _blocks_projectile(bx: int, by: int) -> bool:
	var t: DungeonData.TileType = _data.get_tile(bx, by)
	if t == DungeonData.TileType.WALL or t == DungeonData.TileType.VOID:
		return true
	var pos := Vector2i(bx, by)
	return _doors.has(pos) and not _doors[pos]["is_open"]

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

# Walks the same Bresenham ray as has_ranged_los() but checks for a living body occupying an
# INTERMEDIATE tile (endpoints excluded — the shooter's own tile and the intended target's tile
# never count as "blocking"). Returns the first Enemy/Player/Companion found, or null if the ray
# is clear. Used to answer "would a projectile actually reach `to`, or does something in the way
# intercept it first" — a separate question from has_ranged_los()'s terrain/door check.
func get_blocking_body_on_line(from: Vector2i, to: Vector2i) -> Node:
	var x: int = from.x; var y: int = from.y
	var dx: int = abs(to.x - x); var dy: int = abs(to.y - y)
	var sx: int = 1 if x < to.x else -1
	var sy: int = 1 if y < to.y else -1
	var err: int = dx - dy
	while x != to.x or y != to.y:
		var e2: int = 2 * err
		if e2 > -dy: err -= dy; x += sx
		if e2 < dx:  err += dx; y += sy
		if x == to.x and y == to.y: break
		var pos := Vector2i(x, y)
		var blocker: Enemy = get_enemy_at(pos)
		if blocker != null:
			return blocker
		if _player != null and is_instance_valid(_player) and _player.occupies(pos):
			return _player
		var comp: Variant = GameState.player_companion
		if comp != null and is_instance_valid(comp) and comp.grid_pos == pos:
			return comp
	return null

# Terrain/door/grass LOS AND "nothing living stands in the way" — the gate every RANGED ATTACK
# decision should check before actually taking a shot. A blocked shot is not simply refused for
# the player (see PlayerRanged.ranged_attack(), which redirects to whichever body is actually in
# the way, and uses the permissive has_ranged_los() directly — a player can still blind-fire
# through grass they can't fully see through) but IS what makes an enemy's own ranged
# attack_profile/ability/thrown-weapon logic treat the target as "not in range" so it falls back
# to approaching instead of firing at someone it can't actually see (deliberately uses
# has_line_of_sight(), NOT has_ranged_los() — an aware/CHASING enemy tracking a target's last-seen
# position must not be able to keep shooting at it the instant grass breaks actual sight, even
# though has_ranged_los() alone would still call that a "clear" shot).
func has_clear_shot(from: Vector2i, to: Vector2i) -> bool:
	return has_line_of_sight(from, to) and get_blocking_body_on_line(from, to) == null

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

# Magic Missile's "seeking dart" targeting (Spell.bypasses_los, see spell.gd) — is there a route a
# walking character could physically take from `from` to `to`, EXCEPT chasms don't block it here
# (the missile flies over one; a character on foot couldn't) — direct owner spec, BG3-inspired.
# Deliberately NOT gated on `_explored` (unlike find_path(), which is real click-to-move and
# shouldn't path through unseen fog) — a spell target can be blind-cast at an unexplored tile, same
# as every other spell/ranged attack in this codebase (see scripts/entities/CLAUDE.md's spellcasting
# sections). 8-directional BFS, same shape as find_path() otherwise; `to` itself is always treated
# as enterable (an enemy's own tile) even if `_is_walkable_ignoring_chasm()` would say no (matches
# find_path()'s `or nxt == to` treatment of the destination tile).
func has_walkable_route_ignoring_chasms(from: Vector2i, to: Vector2i) -> bool:
	if from == to:
		return true
	var visited: Dictionary = {from: true}
	var queue: Array[Vector2i] = [from]
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	while not queue.is_empty():
		var cur: Vector2i = queue.pop_front()
		if cur == to:
			return true
		for d: Vector2i in dirs:
			var nxt: Vector2i = cur + d
			if visited.has(nxt):
				continue
			if nxt != to and not _is_walkable_ignoring_chasm(nxt):
				continue
			visited[nxt] = true
			queue.append(nxt)
	return false

# WALL/VOID still block; every other tile type passes — CHASM included (the one deliberate
# difference from `is_walkable()`/`_data.is_walkable()`), same reasoning as find_path()'s "closed
# doors are passable" comment: a real physical obstacle (barrel/blacksmith/shopkeeper prop) still
# blocks, since those are solid whether you're walking or the dart is flying past at head height.
func _is_walkable_ignoring_chasm(pos: Vector2i) -> bool:
	if _barrels.has(pos) or _blacksmiths.has(pos) or _shopkeepers.has(pos):
		return false
	var t: DungeonData.TileType = get_tile_type(pos)
	return t != DungeonData.TileType.WALL and t != DungeonData.TileType.VOID

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
		if is_instance_valid(e) and e.occupies(pos):
			return e as Enemy
	return null

# Same as get_enemy_at(), but returns null for an Invisible enemy (Enemy.is_hidden_from_player())
# — the chokepoint for every DIRECT click-based target resolution (melee chase-click, Frenzy/
# Limit Break click, spell Ctrl/LMB click, thrown-weapon click). Bump-into-movement detection
# (walking into an enemy's tile) deliberately keeps calling get_enemy_at() directly instead — an
# invisible enemy can still be bumped into, per "not invincible, just unseen" (see
# scripts/entities/CLAUDE.md's "Invisibility" section). AoE spells (Fireball/Thunderclap) don't
# target by click at all, so they're unaffected either way.
func get_targetable_enemy_at(pos: Vector2i) -> Enemy:
	var e: Enemy = get_enemy_at(pos)
	if e != null and e.is_hidden_from_player():
		return null
	return e

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
	if _barrels.has(pos):
		return false
	if _blacksmiths.has(pos):
		return false
	if _shopkeepers.has(pos):
		return false
	if _doors.has(pos) and not _doors[pos]["is_open"]:
		return false
	if _player != null and _player.occupies(pos):
		return false
	for e: Enemy in _enemies:
		if is_instance_valid(e) and e.occupies(pos):
			return false
	for c in _companions:
		if is_instance_valid(c) and c.grid_pos == pos:
			return false
	return true

## `color_override`: unset (alpha 0) keeps the existing red/yellow default. `stack_index`: offsets
## spawn x by 10px per index so two simultaneous typed-damage floaters (e.g. Slashing + Radiant
## from one attack) don't fully overlap.
func show_damage(world_pos: Vector2, amount: int, is_player_hit: bool, color_override: Color = Color(0, 0, 0, 0), stack_index: int = 0) -> void:
	var lbl := Label.new()
	lbl.text = "-%d" % amount
	lbl.add_theme_font_size_override("font_size", 8)
	var color: Color = color_override if color_override.a > 0.0 else (Color(1.0, 0.25, 0.25) if is_player_hit else Color(1.0, 0.9, 0.3))
	lbl.add_theme_color_override("font_color", color)
	lbl.z_index = 10
	lbl.position = world_pos - Vector2(4.0 - stack_index * 10.0, 14.0)
	$Entities.add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position", lbl.position + Vector2(0.0, -20.0), 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9)
	tw.tween_callback(lbl.queue_free)

func get_visible_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	if _player == null:
		return result
	var eff_radius: int = GameState.effective_fov_radius(_player.grid_pos)
	var r2: int = eff_radius * eff_radius
	for e: Enemy in _enemies:
		if not is_instance_valid(e):
			continue
		var near: Vector2i = e.nearest_occupied_tile(_player.grid_pos)
		var dx: int = near.x - _player.grid_pos.x
		var dy: int = near.y - _player.grid_pos.y
		# Same Chebyshev-at-radius<=1 fix as _cast_light() above — a plain Euclidean bound would
		# exclude a true diagonal neighbor while Blinded (dx²+dy²=2 > 1).
		var within_radius: bool = (maxi(absi(dx), absi(dy)) <= eff_radius) if eff_radius <= 1 else (dx * dx + dy * dy <= r2)
		if within_radius and has_line_of_sight(_player.grid_pos, near):
			result.append(e)
	return result

func on_player_reached_stairs() -> void:
	AudioManager.play("next_floor")
	GameState.advance_floor()
	if GameState.current_floor > 10:
		return
	_load_floor()

# ── Enemy spawning ────────────────────────────────────────────────────────────

func _spawn_enemies() -> void:
	var is_boss_floor: bool = GameState.current_floor % 5 == 0 and _data.boss_room.has_area()

	var candidates: Array[Vector2i] = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) == DungeonData.TileType.FLOOR:
				if pos != _data.player_start and pos != _data.stairs_pos:
					if _data.start_room.has_area() and _data.start_room.grow(1).has_point(pos):
						continue  # keep starting room safe
					if is_boss_floor and _data.boss_room.has_point(pos):
						continue  # reserve boss room for the boss
					if _traps.has(pos) or _doors.has(pos) or _barrels.has(pos) or _floor_items.has(pos) or _blacksmiths.has(pos):
						continue  # tile already claimed by a trap/door/barrel/item/prop
					candidates.append(pos)
	RngUtil.shuffle(candidates, _pop_rng)

	var eligible: Array = []
	for entry in DungeonFloorData.ENEMY_POOL:
		var t: Dictionary = entry
		if GameState.current_floor >= t["floor_min"] and GameState.current_floor <= t["floor_max"]:
			eligible.append(t)
	if eligible.is_empty():
		eligible = [DungeonFloorData.ENEMY_POOL[0]]

	# `remaining` tracks which shuffled candidate tiles are still free THIS spawn pass — every
	# non-Large pick still just pops the front in shuffled order (identical to the old plain
	# candidates[i] indexing, since nothing else ever removed from that array either), so a floor
	# with no Large-footprint entry in its `eligible` pool spawns byte-identical to before this.
	var remaining: Array[Vector2i] = candidates.duplicate()
	var remaining_set: Dictionary = {}
	for c: Vector2i in remaining:
		remaining_set[c] = true

	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var to_spawn: Array[Dictionary] = _pick_cr_budgeted_enemies(eligible, is_boss_floor)

	for type_data: Dictionary in to_spawn:
		var footprint: Vector2i = _enemy_pool_footprint(type_data)
		var spawn_pos: Vector2i = Vector2i(-1, -1)
		if footprint != Vector2i.ONE:
			# Large enemy (e.g. Ogre, 2x2): needs an ENTIRE free footprint of plain open floor —
			# every tile independently re-passes the same single-tile eligibility rules that built
			# `remaining_set` (not start/stairs-adjacent, not the boss room). A straight 1-wide
			# corridor can never contain a 2x2+ block of floor tiles, so this alone is what keeps a
			# Large enemy from ever spawning in one — no separate corridor-detection code needed.
			for cand: Vector2i in remaining:
				if _footprint_fits(cand, footprint, remaining_set):
					spawn_pos = cand
					break
			if spawn_pos == Vector2i(-1, -1):
				continue  # this floor's layout has no room for it this pass — skip the slot
			for dy: int in footprint.y:
				for dx: int in footprint.x:
					var t: Vector2i = spawn_pos + Vector2i(dx, dy)
					remaining.erase(t)
					remaining_set.erase(t)
		else:
			if remaining.is_empty():
				continue
			spawn_pos = remaining.pop_front()
			remaining_set.erase(spawn_pos)

		var enemy: Enemy = enemy_scene.instantiate() as Enemy
		enemy.configure(type_data)
		# Assign random initial behavior
		var behavior_roll: int = _pop_rng.randi() % 3
		match behavior_roll:
			0: enemy.initial_behavior = Enemy.Behavior.SLEEPING
			1: enemy.initial_behavior = Enemy.Behavior.STATIONARY
			2: enemy.initial_behavior = Enemy.Behavior.ROAMING
		enemy._dungeon_floor = self
		entities.add_child(enemy)
		enemy.set_grid_pos(spawn_pos)
		_enemies.append(enemy)
		TurnManager.register_enemy(enemy)

	if is_boss_floor:
		_spawn_boss()

func _cr_budget(floor_num: int) -> float:
	return CR_BUDGET_BASE + floor_num * CR_BUDGET_PER_FLOOR

# CR-budgeted selection (docs/architecture/cr-budgeted-spawning-design.md): repeatedly picks a
# uniformly-random enemy from whichever `eligible` entries still fit the remaining budget, instead
# of a flat random count — a floor whose eligible band skews expensive (e.g. late-game Ogre) ends up
# with fewer, scarier spawns rather than always 3-5 regardless of strength. Boss's own "cr" is never
# deducted here — `_spawn_boss()` always spawns unconditionally on top of this.
func _pick_cr_budgeted_enemies(eligible: Array, is_boss_floor: bool) -> Array[Dictionary]:
	var budget: float = _cr_budget(GameState.current_floor)
	if is_boss_floor:
		budget *= BOSS_FLOOR_BUDGET_SCALE

	var to_spawn: Array[Dictionary] = []
	while to_spawn.size() < CR_BUDGET_SAFETY_CAP:
		var affordable: Array = []
		for entry in eligible:
			var t: Dictionary = entry
			if float(t.get("cr", CR_BUDGET_DEFAULT_CR)) <= budget:
				affordable.append(t)
		if affordable.is_empty():
			break
		var pick: Dictionary = affordable[_pop_rng.randi_range(0, affordable.size() - 1)]
		to_spawn.append(pick)
		budget -= float(pick.get("cr", CR_BUDGET_DEFAULT_CR))
	return to_spawn

func _enemy_pool_footprint(type_data: Dictionary) -> Vector2i:
	var s: Dictionary = type_data.get("size", {})
	return Vector2i(int(s.get("w", 1)), int(s.get("h", 1)))

func _footprint_fits(top_left: Vector2i, size: Vector2i, remaining_set: Dictionary) -> bool:
	for dy: int in size.y:
		for dx: int in size.x:
			if not remaining_set.has(top_left + Vector2i(dx, dy)):
				return false
	return true

func _spawn_boss() -> void:
	var floor_num: int = GameState.current_floor
	var boss_data: Dictionary = {}
	for b in DungeonFloorData.BOSS_POOL:
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
	var behavior_roll: int = _pop_rng.randi() % 3
	match behavior_roll:
		0: boss.initial_behavior = Enemy.Behavior.SLEEPING
		1: boss.initial_behavior = Enemy.Behavior.STATIONARY
		2: boss.initial_behavior = Enemy.Behavior.ROAMING

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

# Shared floor-trap placement (sprite + _traps dict entry) — extracted from _spawn_traps()'s own
# floor-trap loop so TreasureRoom (special-rooms-economy-design.md §4.2, session 7c) can place a
# trap of its own using the exact same shape without duplicating the sprite setup.
func _place_floor_trap(pos: Vector2i, t: Dictionary) -> void:
	var tex: Texture2D = load(TRAP_PATH + t["sprite"])
	if tex == null:
		return
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

	RngUtil.shuffle(floor_cands, _pop_rng)
	RngUtil.shuffle(wall_cands, _pop_rng)

	var floor_pool: Array = []
	var wall_pool: Array = []
	for entry in DungeonFloorData.TRAP_POOL:
		var t: Dictionary = entry
		if t.get("wall_trap", false):
			wall_pool.append(t)
		else:
			floor_pool.append(t)

	var used: Dictionary = {}
	var floor_count: int = mini(_pop_rng.randi_range(TRAP_COUNT_MIN, TRAP_COUNT_MAX), floor_cands.size())
	for i: int in floor_count:
		var t: Dictionary = floor_pool[_pop_rng.randi_range(0, floor_pool.size() - 1)]
		var pos: Vector2i = floor_cands[i]
		used[pos] = true
		_place_floor_trap(pos, t)

	if not wall_pool.is_empty():
		var valid_wc: Array = []
		for wc in wall_cands:
			var wcd: Dictionary = wc
			if not used.has(wcd["floor_pos"]):
				valid_wc.append(wcd)
		var push_count: int = mini(_pop_rng.randi_range(2, 3), valid_wc.size())
		for i: int in push_count:
			var wcd: Dictionary = valid_wc[i]
			var t: Dictionary = wall_pool[_pop_rng.randi_range(0, wall_pool.size() - 1)]
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

# ── Tripwire trap (rope spanning a 1-wide corridor + hidden poison-dart dispenser) ────────────
# A rope stretched wall-to-wall across a straight 1-tile-wide corridor tile (or a corridor's own
# entrance/exit into a room, which is detected by the exact same "FLOOR-FLOOR through axis,
# WALL-WALL perpendicular axis" check). Walking across it (or hitting it with a ranged attack,
# thrown item, or spell — see try_shoot_tripwire()/throw_item_onto_trap() below) fires a single
# poisoned dart from a hidden dispenser one tile further along the corridor, in the direction the
# rope was strung FROM — the dart travels back down the corridor through the rope's own tile and
# beyond, hitting whichever Player/Enemy is first in its path (nobody in the way = harmless).
# The dispenser itself is disguised as plain floor (no sprite, no grid change) until the player
# finds it via Search (same passive/active detection as every other trap, since it lives in the
# same _traps dict) — at which point it can be RMB-looted for its one Poisoned Arrow instead of
# triggering it, see PlayerActions.interact_action()'s dispenser priority.
const TRIPWIRE_COUNT_MAX: int = 1
const TRIPWIRE_ARROW_RANGE: int = 14
const TRIPWIRE_DMG_MIN: int = 3
const TRIPWIRE_DMG_MAX: int = 6
const TRIPWIRE_POISON_TURNS: int = 6

func _spawn_tripwire_traps() -> void:
	var axes: Array[Vector2i] = [Vector2i(1, 0), Vector2i(0, 1)]
	var candidates: Array = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _data.start_room.has_area() and _data.start_room.grow(1).has_point(pos):
				continue
			if maxi(abs(pos.x - _data.player_start.x), abs(pos.y - _data.player_start.y)) < 3:
				continue
			if _traps.has(pos) or _doors.has(pos) or _barrels.has(pos) or _floor_items.has(pos) \
				or _blacksmiths.has(pos) or _shopkeepers.has(pos):
				continue
			for axis: Vector2i in axes:
				var perp: Vector2i = Vector2i(-axis.y, axis.x)
				var through_a: Vector2i = pos + axis
				var through_b: Vector2i = pos - axis
				var perp_a: Vector2i = pos + perp
				var perp_b: Vector2i = pos - perp
				var is_narrow: bool = \
					_data.get_tile(through_a.x, through_a.y) == DungeonData.TileType.FLOOR \
					and _data.get_tile(through_b.x, through_b.y) == DungeonData.TileType.FLOOR \
					and _data.get_tile(perp_a.x, perp_a.y) != DungeonData.TileType.FLOOR \
					and _data.get_tile(perp_b.x, perp_b.y) != DungeonData.TileType.FLOOR
				if not is_narrow:
					continue
				var ends: Array[Vector2i] = [axis, -axis]
				RngUtil.shuffle(ends, _pop_rng)
				for d: Vector2i in ends:
					var dispenser_pos: Vector2i = pos + d
					if dispenser_pos == _data.player_start or dispenser_pos == _data.stairs_pos:
						continue
					if _traps.has(dispenser_pos) or _doors.has(dispenser_pos) or _barrels.has(dispenser_pos) \
						or _floor_items.has(dispenser_pos) or _blacksmiths.has(dispenser_pos) or _shopkeepers.has(dispenser_pos):
						continue
					candidates.append({"pos": pos, "dispenser_pos": dispenser_pos, "fire_dir": -d})
					break
				break

	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var claimed: Dictionary = {}
	var placed: int = 0
	for c: Dictionary in candidates:
		if placed >= TRIPWIRE_COUNT_MAX:
			break
		if claimed.has(c["pos"]) or claimed.has(c["dispenser_pos"]):
			continue
		_place_tripwire_trap(c["pos"], c["dispenser_pos"], c["fire_dir"])
		claimed[c["pos"]] = true
		claimed[c["dispenser_pos"]] = true
		placed += 1

func _place_tripwire_trap(pos: Vector2i, dispenser_pos: Vector2i, fire_dir: Vector2i) -> void:
	var perp: Vector2i = Vector2i(-fire_dir.y, fire_dir.x)
	var img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
	img.fill(Color(0, 0, 0, 0))
	var rope_color := Color(0.55, 0.42, 0.25, 1.0)
	var mid: int = TILE_SIZE / 2
	for i: int in TILE_SIZE:
		if perp.x != 0:
			img.set_pixel(i, mid, rope_color)
			img.set_pixel(i, mid - 1, rope_color)
		else:
			img.set_pixel(mid, i, rope_color)
			img.set_pixel(mid - 1, i, rope_color)
	var tex := ImageTexture.create_from_image(img)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	sprite.modulate.a = 0.0
	entities.add_child(sprite)
	_traps[pos] = {"name": "Tripwire", "damage": 0,
				   "msg": "A tripwire snaps taut — a poisoned dart hisses out!",
				   "sprite_node": sprite, "revealed": false, "is_push": false, "triggered": false,
				   "reusable": false, "tripwire": true, "dispenser_pos": dispenser_pos, "fire_dir": fire_dir}
	_dispensers[dispenser_pos] = {"revealed": false, "spent": false, "tripwire_pos": pos}

func has_tripwire_at(pos: Vector2i) -> bool:
	return _traps.has(pos) and _traps[pos].get("tripwire", false) and not _traps[pos].get("triggered", false)

# Called from a ranged shot / thrown item / spell landing on an EMPTY tile — "shooting the rope"
# deliberately, per the player's own choice, rather than walking into it. Only ever triggers a
# still-armed Tripwire; every other trap type is untouched by a shot at an empty tile.
func try_shoot_tripwire(pos: Vector2i) -> bool:
	if not has_tripwire_at(pos):
		return false
	_trigger_tripwire(pos, _traps[pos])
	return true

func _trigger_tripwire(pos: Vector2i, trap: Dictionary) -> void:
	if trap.get("triggered", false):
		return
	trap["triggered"] = true
	trap["revealed"] = true
	var sprite_node: Sprite2D = trap.get("sprite_node") as Sprite2D
	if is_instance_valid(sprite_node):
		sprite_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
	GameState.game_log("[color=orange]%s[/color]" % trap["msg"])
	_fire_dispenser_arrow(trap)

func _fire_dispenser_arrow(trap: Dictionary) -> void:
	var dispenser_pos: Vector2i = trap.get("dispenser_pos", Vector2i(-1, -1))
	var fire_dir: Vector2i = trap.get("fire_dir", Vector2i.ZERO)
	if dispenser_pos == Vector2i(-1, -1) or fire_dir == Vector2i.ZERO:
		return
	if _dispensers.has(dispenser_pos):
		if _dispensers[dispenser_pos].get("spent", false):
			GameState.game_log("[color=gray]The dispenser is empty — nothing happens.[/color]")
			return
		_dispensers[dispenser_pos]["spent"] = true
		_dispensers[dispenser_pos]["revealed"] = true
	var pos: Vector2i = dispenser_pos
	var hit_target: Node2D = null
	for _i: int in TRIPWIRE_ARROW_RANGE:
		pos += fire_dir
		var tt: int = _data.get_tile(pos.x, pos.y)
		if tt == DungeonData.TileType.WALL or tt == DungeonData.TileType.VOID:
			break
		if has_door_at(pos) and not is_door_open(pos):
			break
		if _player != null and is_instance_valid(_player) and _player.occupies(pos) and not _player.stats.is_dead():
			hit_target = _player
			break
		var e: Enemy = get_enemy_at(pos)
		if e != null and is_instance_valid(e) and not e.stats.is_dead():
			hit_target = e
			break
	if hit_target == null:
		GameState.game_log("[color=gray]A poisoned dart streaks down the passage and clatters harmlessly against the wall.[/color]")
		return
	_resolve_dispenser_hit(hit_target)

func _resolve_dispenser_hit(target: Node2D) -> void:
	var dmg: int = Rng.range_i(TRIPWIRE_DMG_MIN, TRIPWIRE_DMG_MAX)
	var msg: String = "A poisoned dart hits you!" if target is Player else "A poisoned dart strikes %s!" % (target as Enemy).display_name
	_apply_trap_damage(target, dmg, msg)
	if target is Player and not GameState.player_stats.is_dead():
		if GameState.apply_player_status("poisoned_condition", TRIPWIRE_POISON_TURNS):
			GameState.game_log("[color=green]You are poisoned! (%d turns, Disadvantage)[/color]" % TRIPWIRE_POISON_TURNS)
	elif target is Enemy and not (target as Enemy).stats.is_dead():
		(target as Enemy).apply_status("poisoned_condition", TRIPWIRE_POISON_TURNS)

func has_dispenser_at(pos: Vector2i) -> bool:
	return _dispensers.has(pos)

func get_dispenser_at(pos: Vector2i) -> Dictionary:
	return _dispensers.get(pos, {})

func reveal_dispenser(pos: Vector2i) -> bool:
	if not _dispensers.has(pos):
		return false
	if _dispensers[pos].get("revealed", false):
		return false
	_dispensers[pos]["revealed"] = true
	GameState.game_log("[color=yellow]You discover a hidden dart dispenser![/color]")
	return true

# RMB loot — only reachable once the dispenser's been found via Search, and only while it still
# has its one dart (see PlayerActions.interact_action()'s dispenser priority).
func loot_dispenser(pos: Vector2i) -> Item:
	if not _dispensers.has(pos):
		return null
	var d: Dictionary = _dispensers[pos]
	if d.get("spent", false):
		return null
	d["spent"] = true
	var poison_arrow: Dictionary = {}
	for entry in DungeonFloorData.ITEM_POOL:
		if entry.get("name", "") == "Poisoned Arrow":
			poison_arrow = entry
			break
	if poison_arrow.is_empty():
		return null
	return _build_item_from_pool(poison_arrow)

func get_trap_at(pos: Vector2i) -> Dictionary:
	return _traps.get(pos, {})

func trigger_trap(pos: Vector2i, entity: Node2D = null) -> void:
	if not _traps.has(pos):
		return
	var trap: Dictionary = _traps[pos]
	var is_push: bool = trap.get("is_push", false)

	if trap.get("tripwire", false):
		_trigger_tripwire(pos, trap)
		return

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
	if target is Player:
		var s: Stats = GameState.player_stats
		var dex_mod: int = s.dex_modifier()
		var has_prof: bool = s.check_prof_dex
		var prof_bonus: int = s.proficiency_bonus if has_prof else 0
		var has_adv: bool = s.zealous_presence_turns > 0
		var die1: int = Rng.roll(20)
		var die2: int = die1
		if has_adv:
			die2 = Rng.roll(20)
		var die: int = maxi(die1, die2)
		var effective_stat: String = "DEX"
		var roll: int = die + dex_mod + prof_bonus
		var dc: int = 10 + GameState.current_floor
		var adv_tag: String = " [color=gray](Zealous Presence)[/color]" if has_adv else ""
		var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [
			effective_stat, die, die1, die2, dex_mod, prof_bonus, roll, dc, 1 if roll >= dc else 0, 1 if has_adv else 0]
		if roll >= dc:
			GameState.game_log("[color=cyan]You dodge [b]%s[/b]!%s [url=%s]%d vs DC %d[/url][/color]" % [trap["name"], adv_tag, check_meta, roll, dc])
			return
		else:
			GameState.game_log("[color=orange]%s triggered!%s [url=%s]%d vs DC %d[/url][/color]" % [trap["name"], adv_tag, check_meta, roll, dc])

	if is_push:
		AudioManager.play("trap_piston")
		await force_move_entity(target, trap["push_dir"], 2, true, sprite_node)
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

## SecretRoom hidden-door reveal (special-rooms-economy-design.md §4.4) — undoes _spawn_secret_room()'s
## hide: un-hides the door's own Sprite2D (already built by _spawn_doors(), never removed, just
## invisible), restores the tilemap cell from the WALL-lookalike back to FLOOR, and logs the find.
## Only ever called from search_around()'s hidden-door loop.
func _reveal_secret_door(pos: Vector2i) -> void:
	_doors[pos]["hidden"] = false
	var sp: Sprite2D = _doors[pos]["sprite"]
	if is_instance_valid(sp):
		sp.visible = true
	tilemap.set_cell(pos, SOURCE_FLOOR, ATLAS_ORIGIN)
	GameState.game_log("[color=yellow]You discover a hidden door![/color]")

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

# Throwing ANY item onto a trap tile activates it — reveals it and, for Fire/Bear Traps, consumes
# its single use exactly like an entity triggering it — but nobody rolls a dodge check and no
# damage/status is ever applied (an inanimate item can't dodge or bleed). A Piston trap shoves the
# item exactly as far as it would shove an entity (same 2-tile/wall-stop rule as
# force_move_entity(), reimplemented here without a tween since there's no Entity to move). Pit
# Spikes are inert against a thrown item — it just lands on top, no reveal, no trigger. Returns the
# tile the item should actually land on (`pos` unless a Piston shoved it), or the
# Vector2i(-1, -1) sentinel if a flammable item (Item.is_flammable) landed on a Fire Trap and burned
# to ash instead of landing anywhere. No-ops (returns `pos`) if there's no trap at `pos` at all.
func throw_item_onto_trap(pos: Vector2i, item: Item) -> Vector2i:
	if not _traps.has(pos):
		return pos
	var trap: Dictionary = _traps[pos]
	var trap_name: String = trap.get("name", "")
	if trap.get("tripwire", false):
		_trigger_tripwire(pos, trap)
		return pos
	if trap_name == "Pit Spikes":
		return pos
	var sprite_node: Sprite2D = trap.get("sprite_node") as Sprite2D
	trap["revealed"] = true
	if is_instance_valid(sprite_node):
		sprite_node.modulate = Color(1.0, 1.0, 1.0, 1.0)
	if trap.get("is_push", false):
		AudioManager.play("trap_piston")
		var current: Vector2i = pos
		var dir: Vector2i = trap["push_dir"]
		for _i: int in 2:
			var nxt: Vector2i = current + dir
			if not _data.is_walkable(nxt):
				break
			current = nxt
		_play_trap_animation(sprite_node)
		return current
	if not trap.get("triggered", false):
		trap["triggered"] = true
		if is_instance_valid(sprite_node):
			sprite_node.modulate = Color(0.25, 0.25, 0.25, 0.85)
		_play_trap_animation(sprite_node)
	if trap_name == "Fire Trap":
		AudioManager.play("trap_fire")
		if item.is_flammable:
			return Vector2i(-1, -1)
	elif trap_name == "Bear Trap":
		AudioManager.play("trap_bear")
	return pos


# Multiple items can occupy the same tile — they stack in _floor_items[pos] (Array[Item],
# oldest first). Only the newest (last) item's sprite is shown, so a spot where several
# arrows/items landed still reads as a single pickup icon; walking onto the tile
# (PlayerActions.check_pickup()) collects the whole stack at once.
## An item must never land on a tile the player can't stand on (barrel, blacksmith, shopkeeper,
## closed door, wall/void, chasm) — it would become permanently unreachable. Every place_item_on_
## floor() caller funnels through this redirect, so a stray miss (a thrown weapon or ranged shot
## that lands square on a crate/door tile) always resolves to the nearest actual pickup spot
## instead of silently eating the item. No-op (returns pos unchanged) when pos is already walkable.
func _resolve_item_drop_pos(pos: Vector2i) -> Vector2i:
	if is_walkable(pos):
		return pos
	for radius: int in range(1, 6):
		for dy: int in range(-radius, radius + 1):
			for dx: int in range(-radius, radius + 1):
				if maxi(absi(dx), absi(dy)) != radius:
					continue
				var cand := Vector2i(pos.x + dx, pos.y + dy)
				if _in_grid_bounds(cand) and is_walkable(cand):
					return cand
	return pos  # no walkable tile found nearby — shouldn't happen on any real floor layout

func place_item_on_floor(pos: Vector2i, item: Item) -> void:
	pos = _resolve_item_drop_pos(pos)
	var tex: Texture2D
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		tex = load(item.icon_path)
	else:
		var fallback_img := Image.create(TILE_SIZE, TILE_SIZE, false, Image.FORMAT_RGBA8)
		fallback_img.fill(Color(0.80, 0.55, 0.15))
		tex = ImageTexture.create_from_image(fallback_img)
	# Source art isn't uniformly tile-sized (weapon sprites are tall/thin, ~10x37px; res://icons/spells/
	# PNGs are thousands of px across), so clamp the longest side to FLOOR_ICON_MAX_PX instead of
	# stretching to fill a square tile (that squashed thin weapon art wide-and-short) or trusting
	# native resolution (that let huge spell PNGs render screen-covering). Scale is uniform — aspect
	# ratio preserved — and only ever shrinks, so already-tile-sized art (~16px) is untouched and can
	# still poke slightly past the tile edge, same as it always has.
	var tex_size: Vector2 = Vector2(tex.get_size())
	var longest_side: float = max(tex_size.x, tex_size.y)
	var uniform_scale: float = min(1.0, FLOOR_ICON_MAX_PX / longest_side) if longest_side > 0.0 else 1.0
	var tile_scale: Vector2 = Vector2(uniform_scale, uniform_scale)
	if _floor_item_sprites.has(pos):
		var existing: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(existing):
			existing.texture = tex
			existing.scale = tile_scale
	else:
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.scale = tile_scale
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
		sprite.z_index = 1
		entities.add_child(sprite)
		_floor_item_sprites[pos] = sprite
	if not _floor_items.has(pos):
		_floor_items[pos] = [] as Array[Item]
	(_floor_items[pos] as Array).append(item)

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
	cooked.food_value = 75
	cooked.icon_path = "res://sprites/items/food/meat_cooked.png"
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
	# SecretRoom hidden doors (special-rooms-economy-design.md §4.4): reads the raw _doors dict
	# directly, bypassing has_door_at()'s hidden-filter — this loop is the ONE place a hidden door
	# can ever be found. Logs its own line per door via _reveal_secret_door(); deliberately not
	# folded into `found`/the trap-count summary PlayerActions.search_action() builds from it.
	for door_pos: Vector2i in _doors.keys():
		if not _doors[door_pos].get("hidden", false):
			continue
		var d: Vector2i = door_pos - pos
		if absi(d.x) > radius or absi(d.y) > radius:
			continue
		if not has_line_of_sight(pos, door_pos):
			continue
		_reveal_secret_door(door_pos)
	# Tripwire's hidden dispenser (see "Tripwire trap" above) — same radius+LOS gate, its own
	# dict since it isn't keyed by _traps. Counts toward the returned trap-found total.
	for disp_pos: Vector2i in _dispensers.keys():
		var dd: Vector2i = disp_pos - pos
		if absi(dd.x) > radius or absi(dd.y) > radius:
			continue
		if not has_line_of_sight(pos, disp_pos):
			continue
		if reveal_dispenser(disp_pos):
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

## Generalized forced-movement primitive — walks `entity` step-by-step in `direction`,
## stopping early on wall/occupant collision. Used for pushes (piston traps, Branching
## Strike R3) and pulls (Grip of the Forest — pass the direction toward the player and
## max_distance = current_distance - 1 so the target lands adjacent, not on top of the player).
## `deal_damage=true` reproduces the old piston-trap-only splash damage; World Tree forced
## movement (pull/push) does not deal damage, so it passes deal_damage=false.
# Forced movement never provokes an Opportunity Attack (5e RAW) — intentionally does not call
# either OA hook (enemy.gd._check_opportunity_attacks_on_move / player.gd._resolve_enemy_opportunity_attacks).
func force_move_entity(entity: Node2D, direction: Vector2i, max_distance: int, deal_damage: bool = false, trap_sprite: Sprite2D = null) -> int:
	if not is_instance_valid(entity):
		if is_instance_valid(trap_sprite):
			await _play_trap_animation(trap_sprite)
		return 0
	if entity is Enemy and "forced_move" in (entity as Enemy).condition_immunities:
		return 0
	var e: Entity = entity as Entity
	var start: Vector2i = e.grid_pos
	var current: Vector2i = start
	var hit_wall: bool = false
	var large_enemy: Enemy = (entity as Enemy) if entity is Enemy and (entity as Enemy).size != Vector2i.ONE else null
	for _i: int in max_distance:
		var nxt: Vector2i = current + direction
		if large_enemy != null:
			# A multi-tile mover needs its WHOLE footprint free at every step — a single-tile
			# is_walkable() check would let e.g. only its top-left corner clip through a wall.
			if not is_area_walkable_for_enemy(nxt, large_enemy.size, large_enemy):
				hit_wall = true
				break
		else:
			if not _data.is_walkable(nxt):
				hit_wall = true
				break
			if entity is Player and get_enemy_at(nxt) != null:
				hit_wall = true
				break
			if entity is Enemy and _player != null and _player.occupies(nxt):
				hit_wall = true
				break
		current = nxt
	if is_instance_valid(trap_sprite):
		_play_trap_animation(trap_sprite)  # fires async — simultaneous with movement
	if current != e.grid_pos:
		await e.move_to(current, 0.15)
	var tiles_moved: int = absi(current.x - start.x) + absi(current.y - start.y)
	if not is_instance_valid(entity) or not deal_damage:
		return tiles_moved
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
	return tiles_moved

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
	if ResourceLoader.exists(DungeonFloorData.OBJECTS_PATH + "doors/leaf_closed.png"):
		tex_closed = load(DungeonFloorData.OBJECTS_PATH + "doors/leaf_closed.png")
	if ResourceLoader.exists(DungeonFloorData.OBJECTS_PATH + "doors/leaf_open.png"):
		tex_open = load(DungeonFloorData.OBJECTS_PATH + "doors/leaf_open.png")

	for pos: Vector2i in door_candidates:
		if _pop_rng.randf() > 0.65:
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
		_doors[pos] = {"is_open": false, "locked": false, "player_locked": false, "sprite": sprite, "tex_open": tex_open, "tex_closed": tex_closed,
			"material": DOOR_MATERIAL, "ac": MaterialTable.ac_for(DOOR_MATERIAL), "hp": DOOR_MAX_HP, "max_hp": DOOR_MAX_HP}

## Returns false for a still-hidden SecretRoom door (special-rooms-economy-design.md §4.4) —
## every door-interaction path (bump-open, F/RMB priority, enemy pathing, ignite_flammable(),
## _spawn_locked_doors()' candidate scan) reads THIS query, never the raw _doors dict, so a hidden
## door stays invisible to all of them. Only search_around() reads _doors directly to find one.
func has_door_at(pos: Vector2i) -> bool:
	return _doors.has(pos) and not _doors[pos].get("hidden", false)

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
	if _player != null and _player.occupies(pos):
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

# ── Barrels (flammable obstacle prop) ──────────────────────────────────────────

# 1-3 per floor, confined to room interiors (never corridors, so a barrel can never be the only
# thing blocking a 1-wide passage) — a solid obstacle (blocks movement, see
# is_walkable()/is_walkable_for_enemy()/is_walkable_for_companion() above) until ignited (see
# "Flammable props" below), at which point it burns for FLAMMABLE_BURN_TURNS turns and disappears,
# matching Shattered Pixel Dungeon's Sewer-level barrel (a flammable terrain object that resolves
# to an empty tile once its fire timer runs out). Candidates are gathered per `_data.rooms` rect
# (corridors are carved outside every room rect, so restricting to rects alone already excludes
# them) and corner tiles of the rect are preferred — clusters of 2-3 in one room's corners are
# fine, since gameplay-visible clumping was the actual ask, only corridor-blocking wasn't wanted.
# Each candidate is placement-checked with `_bfs_reachable()` (same connectivity guard
# `_spawn_locked_doors()` uses) against every barrel already placed this floor, so a barrel is
# never allowed to be the move that disconnects player_start from stairs_pos.
func _spawn_barrels() -> void:
	var corner_candidates: Array[Vector2i] = []
	var room_candidates: Array[Vector2i] = []
	for room: Rect2i in _data.rooms:
		var left: int = room.position.x
		var right: int = room.position.x + room.size.x - 1
		var top: int = room.position.y
		var bottom: int = room.position.y + room.size.y - 1
		for y: int in range(top, bottom + 1):
			for x: int in range(left, right + 1):
				var pos := Vector2i(x, y)
				if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
					continue
				if pos == _data.player_start or pos == _data.stairs_pos:
					continue
				if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos):
					continue
				if (x == left or x == right) and (y == top or y == bottom):
					corner_candidates.append(pos)
				else:
					room_candidates.append(pos)
	if corner_candidates.is_empty() and room_candidates.is_empty():
		return
	RngUtil.shuffle(corner_candidates, _pop_rng)
	RngUtil.shuffle(room_candidates, _pop_rng)
	var ordered: Array[Vector2i] = corner_candidates + room_candidates
	var target: int = _pop_rng.randi_range(BARREL_COUNT_MIN, BARREL_COUNT_MAX)
	var tex: Texture2D = null
	if ResourceLoader.exists(BARREL_TEX_PATH):
		tex = load(BARREL_TEX_PATH)
	var placed: Array[Vector2i] = []
	for pos: Vector2i in ordered:
		if placed.size() >= target:
			break
		var exclude: Array[Vector2i] = placed.duplicate()
		exclude.append(pos)
		if not _bfs_reachable(_data.player_start, _data.stairs_pos, exclude):
			continue
		_place_barrel(pos, tex)
		placed.append(pos)

func _place_barrel(pos: Vector2i, tex: Texture2D) -> void:
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	if tex != null:
		var ts: Vector2 = tex.get_size()
		sprite.scale = Vector2(float(TILE_SIZE) / ts.x, float(TILE_SIZE) / ts.y)
	entities.add_child(sprite)
	_barrels[pos] = {"sprite": sprite, "burning": false, "material": BARREL_MATERIAL,
		"ac": MaterialTable.ac_for(BARREL_MATERIAL), "hp": BARREL_MAX_HP, "max_hp": BARREL_MAX_HP}

func has_barrel_at(pos: Vector2i) -> bool:
	return _barrels.has(pos)

## Generic physical-damage chokepoint for a solid destructible prop (Barrel, or a closed — locked
## or unlocked — Door) at `pos`. Unlike fire's own per-tick burn (tick_burning_props()), a physical
## hit is a single instantaneous amount, always applied (no attack roll — a stationary prop can't
## dodge, same convention as fire). Returns {"hit", "kind" ("barrel"/"door"/""), "destroyed",
## "damage"} — "hit" is false (no-op) when neither prop is at pos. Destroying a barrel frees its
## sprite/entry outright (tile becomes plain walkable floor); destroying a door frees its sprite +
## lock icon too (permanently gone, same as burning one down — see "Barrels + flammable props").
## Call sites: PlayerRanged.ranged_attack_tile() (a ranged shot aimed at an empty tile) and
## PlayerThrowTool._throw_weapon() (a thrown weapon with no enemy at the target tile).
func damage_prop_at(pos: Vector2i, amount: int) -> Dictionary:
	if _barrels.has(pos):
		var dmg: int = maxi(1, amount)
		_barrels[pos]["hp"] -= dmg
		var destroyed: bool = _barrels[pos]["hp"] <= 0
		if destroyed:
			var sp: Sprite2D = _barrels[pos]["sprite"]
			if is_instance_valid(sp):
				sp.queue_free()
			_barrels.erase(pos)
			if _player != null:
				update_fog(_player.grid_pos)
		return {"hit": true, "kind": "barrel", "destroyed": destroyed, "damage": dmg}
	# Hidden (undiscovered secret) doors read as a plain wall to every other chokepoint
	# (has_door_at()) — must be excluded here too, or blind-shooting a wall tile could damage/
	# reveal/destroy a secret door before it's ever found via Search.
	if _doors.has(pos) and not _doors[pos]["is_open"] and not _doors[pos].get("hidden", false):
		var dmg2: int = maxi(1, amount)
		_doors[pos]["hp"] -= dmg2
		var destroyed2: bool = _doors[pos]["hp"] <= 0
		if destroyed2:
			var sp2: Sprite2D = _doors[pos]["sprite"]
			if is_instance_valid(sp2):
				sp2.queue_free()
			if _doors[pos].has("lock_icon"):
				var icon: Node = _doors[pos]["lock_icon"]
				if is_instance_valid(icon):
					icon.queue_free()
			_doors.erase(pos)
			if _player != null:
				update_fog(_player.grid_pos)
		return {"hit": true, "kind": "door", "destroyed": destroyed2, "damage": dmg2}
	return {"hit": false, "kind": "", "destroyed": false, "damage": 0}

# ── Spider Web (see scripts/entities/CLAUDE.md's "Spider" entry) ───────────────
# Placed at the target's own tile the instant its DEX save vs the Web ability fails
# (Enemy._execute_cast_web()) — never pre-seeded at generation time like Barrels/Traps. No-op if a
# web already occupies pos (can't happen in practice: a restrained target is never re-targeted,
# see the "already web_restrained" skip in Enemy._decide_action()).
func spawn_web(pos: Vector2i) -> void:
	if _webs.has(pos):
		return
	var tex: Texture2D = null
	if ResourceLoader.exists(WEB_TEX_PATH):
		tex = load(WEB_TEX_PATH)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	if tex != null:
		var ts: Vector2 = tex.get_size()
		sprite.scale = Vector2(float(TILE_SIZE) / ts.x, float(TILE_SIZE) / ts.y)
	entities.add_child(sprite)
	_webs[pos] = {"sprite": sprite, "hp": WEB_HP, "ac": WEB_AC}

func destroy_web(pos: Vector2i) -> void:
	if not _webs.has(pos):
		return
	var sp: Sprite2D = _webs[pos]["sprite"]
	if is_instance_valid(sp):
		sp.queue_free()
	_webs.erase(pos)

func has_web_at(pos: Vector2i) -> bool:
	return _webs.has(pos)

# ── Flammable props (Barrels + Doors) ──────────────────────────────────────────

# Generic ignition entry point — the single chokepoint every fire source calls (Fire Bolt/
# Fireball/Burning Hands hitting a tile in spell_effects.gd, a thrown lit Torch landing on a tile
# in player_throw_tool.gd, and the adjacency check in _check_burning_ignition_sources() below).
# Barrels and OPEN or CLOSED (but not locked) doors are both flammable — mirrors Shattered Pixel
# Dungeon's Terrain.FLAMABLE flag, which covers ordinary doors alongside grass/barrels but excludes
# locked/crystal doors. No-ops (returns false) if the tile has neither, or is already burning.
func ignite_flammable(pos: Vector2i) -> bool:
	if get_tile_type(pos) == DungeonData.TileType.WATER:
		return false
	if _barrels.has(pos) and not _barrels[pos]["burning"]:
		_barrels[pos]["burning"] = true
		var sp: Sprite2D = _barrels[pos]["sprite"]
		if is_instance_valid(sp):
			sp.modulate = FIRE_TINT
		GameState.game_log("[color=orange]The barrel catches fire![/color]")
		return true
	if _doors.has(pos) and not _doors[pos]["locked"] and not _doors[pos].get("burning", false) \
			and not _doors[pos].get("hidden", false):
		_doors[pos]["burning"] = true
		var sp: Sprite2D = _doors[pos]["sprite"]
		if is_instance_valid(sp):
			sp.modulate = FIRE_TINT
		GameState.game_log("[color=orange]The door catches fire![/color]")
		return true
	return false

## Rolls 2d4 — the fire damage rate for both a burning prop's own HP loss and a creature caught
## standing on one, per direct owner design (both use the same die, just applied to different HP
## pools). Two independent rolls per tick (see below), not one shared number.
static func _roll_fire_tick_damage() -> int:
	var rolls: Array[int] = Rng.roll_dice(2, 4)
	var total: int = 0
	for v: int in rolls:
		total += v
	return total

## Same 2d4 roll as _roll_fire_tick_damage(), but packed into a real CombatMath damage instance
## instead of a bare int — every damage number actually shown to the player in the chat log must
## carry a hoverable per-die tooltip breakdown (root CLAUDE.md's chat-log-tooltip RULE: "every new
## damage source must get a [url=kind:key=val,...] tag on the number... never log bare damage
## numbers"). Only used by tick_fire_damage_for()/tick_torches() below, where the roll IS shown as
## a number — the barrel/door's own HP-loss roll above never displays a number, so it stays on the
## plain int helper.
static func _roll_fire_damage_instance() -> Dictionary:
	var rolls: Array[int] = Rng.roll_dice(2, 4)
	return CombatMath.build_damage_instance(rolls, 4, [], false, "Fire")

## Whether `pos` is a currently-burning DOOR or a currently-burning GRASS tile — both stay
## walkable while on fire (Barrels remain a solid `is_walkable()` obstacle for their entire burn
## regardless of `"burning"`, so nothing can ever stand on one). Public — Player/Enemy/Companion
## each ask this about their own tile(s) at the start of their own turn, see
## tick_fire_damage_for() below.
func is_tile_on_fire(pos: Vector2i) -> bool:
	return (_doors.has(pos) and _doors[pos].get("burning", false)) or _burning_grass.has(pos)

## Deals a fresh, independent 2d4 Fire hit to `entity` if it's currently standing on a burning
## door OR currently-burning grass tile — called from EACH entity's own turn-start
## (Player._on_turn_started(), Enemy.decide_turn(), Companion.decide_turn()), not from a single
## global per-round sweep, so the damage always lands precisely "at the start of that creature's
## own turn" (direct owner request) rather than wherever a single round-level tick happens to sit
## relative to whichever entity is standing there. Footprint-aware via occupied_tiles() (works for
## a Large enemy's multi-tile occupancy same as a normal 1x1 entity).
func tick_fire_damage_for(entity: Entity) -> void:
	if entity == null or not is_instance_valid(entity):
		return
	var on_fire: bool = false
	for t: Vector2i in entity.occupied_tiles():
		if is_tile_on_fire(t):
			on_fire = true
			break
	if not on_fire:
		return
	if entity is Player:
		if GameState.player_stats.is_dead():
			return
		# Draconic Flight: airborne, immune to standing-on-fire damage (see root CLAUDE.md's
		# "Race system" / scripts/entities/CLAUDE.md's "Dragonborn").
		if GameState.player_stats.draconic_flight_turns > 0:
			return
		var inst: Dictionary = _roll_fire_damage_instance()
		var actual: int = GameState.take_damage_raw(int(inst["subtotal"]), false, "Fire")
		inst["final"] = actual
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		show_damage(entity.position, actual, true, CombatMath.damage_type_color("Fire"))
		GameState.game_log("[color=orange]You are burned by the flames for [url=%s][color=yellow]%d[/color][/url] Fire dmg.[/color]" % [dmg_meta, actual])
		GameState.check_player_death()
	elif entity is Enemy:
		var e: Enemy = entity
		if e.stats.is_dead():
			return
		var inst2: Dictionary = _roll_fire_damage_instance()
		var result: Dictionary = e.take_typed_damage(int(inst2["subtotal"]), "Fire")
		var actual2: int = result["actual"]
		inst2["final"] = actual2
		inst2["resist_mul"] = result["mul"]
		var dmg_meta2: String = CombatMath.encode_damage_instance(inst2)
		e.update_hp_bar()
		show_damage(e.position, actual2, false, CombatMath.damage_type_color("Fire"))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is burned by the flames for [url=%s][color=yellow]%d[/color][/url] Fire dmg.%s" % [
			e.display_name, dmg_meta2, actual2, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			GameState.gain_exp(maxi(1, e.exp_reward / 2))
			remove_enemy(e)
			e.die()
	elif entity is Companion:
		entity.take_damage_from_enemy(int(_roll_fire_damage_instance()["subtotal"]))

## Ticks every burning barrel/door's own HP loss AND fire propagation between adjacent flammable
## props — called once per real player turn from player.gd's _on_turn_started() (the top of the
## PLAYER's own turn, i.e. "the start of the round" for anything not tied to one specific entity's
## own turn — see tick_fire_damage_for() above for the per-entity-turn-start damage instead. Each
## burning prop takes 2d4 Fire damage off its own HP (5 for a Barrel, 10 for a Door — both Wood,
## MaterialTable.ac_for("wood"), scripts/items/material_table.gd) instead of a flat fixed-turn
## timer; at 0 HP it's destroyed: a barrel's sprite/entry is removed outright (tile becomes plain
## walkable floor again); a door's sprite/lock-icon/entry is removed outright too (permanently
## gone, unlike close_door() — the tile stays passable forever, matching SPD's
## door-burns-to-EMBERS behavior). GRASS has no HP pool at all (direct owner design) — it just
## gets exactly one round in `_burning_grass` (long enough to spread, see _spread_fire_between_
## props()/ignite_grass()) before _tick_burning_grass() converts it to TRAMPLED_GRASS.
func tick_burning_props() -> void:
	var burnt_barrels: Array[Vector2i] = []
	for pos: Vector2i in _barrels:
		if not _barrels[pos]["burning"]:
			continue
		_barrels[pos]["hp"] -= _roll_fire_tick_damage()
		if _barrels[pos]["hp"] <= 0:
			burnt_barrels.append(pos)
	for pos: Vector2i in burnt_barrels:
		var sp: Sprite2D = _barrels[pos]["sprite"]
		if is_instance_valid(sp):
			sp.queue_free()
		_barrels.erase(pos)
		GameState.game_log("[color=gray]The barrel burns to nothing.[/color]")

	var burnt_doors: Array[Vector2i] = []
	for pos: Vector2i in _doors:
		if not _doors[pos].get("burning", false):
			continue
		_doors[pos]["hp"] -= _roll_fire_tick_damage()
		if _doors[pos]["hp"] <= 0:
			burnt_doors.append(pos)
	for pos: Vector2i in burnt_doors:
		var sp: Sprite2D = _doors[pos]["sprite"]
		if is_instance_valid(sp):
			sp.queue_free()
		if _doors[pos].has("lock_icon"):
			var icon: Node = _doors[pos]["lock_icon"]
			if is_instance_valid(icon):
				icon.queue_free()
		_doors.erase(pos)
		GameState.game_log("[color=gray]The door burns away.[/color]")

	if not burnt_barrels.is_empty() or not burnt_doors.is_empty():
		if _player != null:
			update_fog(_player.grid_pos)

	# Snapshot BEFORE spreading — these grass tiles have already had one full round to spread
	# (ignited last round or earlier), so they finish burning at the end of THIS tick. Anything
	# _spread_fire_between_props() ignites fresh below is added to _burning_grass after this
	# snapshot was taken, so it survives untouched into next round's own spread step first.
	# Dictionary.keys() returns a plain untyped Array — must be rebuilt into a typed one manually,
	# a bare `= dict.keys()` assignment into an `Array[Vector2i]` var throws at runtime.
	var grass_pre_tick: Array[Vector2i] = []
	for k: Vector2i in _burning_grass.keys():
		grass_pre_tick.append(k)

	_check_burning_ignition_sources()
	_spread_fire_between_props()
	_tick_burning_grass(grass_pre_tick)

# Fire spreads from a burning entity standing next to an unlit barrel/door — currently only the
# player can carry burning_turns (see scripts/entities/CLAUDE.md's "Status effects" table; enemy
# burning is reserved/unwired), so this checks the player only. Chebyshev adjacency, same reach
# convention as melee.
func _check_burning_ignition_sources() -> void:
	if _player == null or GameState.player_stats.burning_turns <= 0:
		return
	var p: Vector2i = _player.grid_pos
	for pos: Vector2i in _barrels.keys():
		if _barrels[pos]["burning"]:
			continue
		if maxi(absi(pos.x - p.x), absi(pos.y - p.y)) <= 1:
			ignite_flammable(pos)
	for pos: Vector2i in _doors.keys():
		if _doors[pos].get("burning", false) or _doors[pos]["locked"]:
			continue
		if maxi(absi(pos.x - p.x), absi(pos.y - p.y)) <= 1:
			ignite_flammable(pos)

# Fire spreads between adjacent flammable PROPS themselves (direct owner request) — independent of
# _check_burning_ignition_sources() above, which is about a burning ENTITY (the player) igniting
# nearby props by proximity. Any currently-burning Barrel or Door ignites a not-yet-burning
# Barrel/Door within Chebyshev 1 (8 directions) — the same as before. A currently-burning GRASS
# tile (_burning_grass, see below) spreads only along the 4 CARDINAL directions (direct owner
# request: "should spread in the four main directions" — an orthogonal wildfire, not a diagonal
# blob) to its own grass/barrel/door neighbors. Runs once per real player turn, right after the
# player-adjacency check above, so a spreading blaze catches everything flammable nearby before
# the player even acts this round. Web/pavučina isn't flammable yet (no "burning" field on
# `_webs`) — add it here once it is.
const GRASS_SPREAD_DIRS: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]

func _spread_fire_between_props() -> void:
	var prop_sources: Array[Vector2i] = []
	for pos: Vector2i in _barrels.keys():
		if _barrels[pos]["burning"]:
			prop_sources.append(pos)
	for pos: Vector2i in _doors.keys():
		if _doors[pos].get("burning", false):
			prop_sources.append(pos)
	var grass_sources: Array[Vector2i] = []
	for k: Vector2i in _burning_grass.keys():
		grass_sources.append(k)
	if prop_sources.is_empty() and grass_sources.is_empty():
		return
	# Collect every neighbor tile first (de-duped) — ignite_flammable()/ignite_grass() mutate
	# _barrels/_doors/_burning_grass, so mutating mid-scan of the burning-source lists would be
	# unsafe/order-dependent.
	var to_ignite: Dictionary = {}
	for bpos: Vector2i in prop_sources:
		for dy: int in range(-1, 2):
			for dx: int in range(-1, 2):
				if dx == 0 and dy == 0:
					continue
				to_ignite[bpos + Vector2i(dx, dy)] = true
	for gpos: Vector2i in grass_sources:
		for d: Vector2i in GRASS_SPREAD_DIRS:
			to_ignite[gpos + d] = true
	for npos: Vector2i in to_ignite.keys():
		if get_tile_type(npos) == DungeonData.TileType.GRASS:
			if ignite_grass(npos):
				GameState.game_log("[color=orange]The grass catches fire from the nearby blaze![/color]")
		else:
			ignite_flammable(npos)

# ── Grass ─────────────────────────────────────────────────────────────────────

func destroy_grass(pos: Vector2i) -> void:
	if _data.get_tile(pos.x, pos.y) != DungeonData.TileType.GRASS:
		return
	_data.grid[pos.y][pos.x] = DungeonData.TileType.TRAMPLED_GRASS
	_grass_layer.set_cell(pos, SOURCE_TRAMPLED_GRASS, ATLAS_ORIGIN)
	_burning_grass.erase(pos)

## Starts a GRASS tile burning — unlike destroy_grass() (an instant, permanent conversion to
## TRAMPLED_GRASS with no time window), this leaves the tile marked "on fire" in `_burning_grass`
## for exactly one full round: long enough for tick_fire_damage_for() to burn whoever stands on it
## and for _spread_fire_between_props() to see it as a source and spread to its 4 cardinal
## neighbors, before _tick_burning_grass() finally converts it. Grass deliberately has NO HP pool
## (direct owner design — it isn't a Barrel/Door with a damage pool, just a one-round transient
## flag). No-ops (returns false) if the tile isn't GRASS or is already burning — every fire source
## that ignites a GRASS tile (Fire Bolt/Fireball/Burning Hands in spell_effects.gd, a thrown lit
## Torch, prop-to-grass and grass-to-grass spread above) should call this instead of destroy_grass()
## directly; destroy_grass() itself is now only ever called from _tick_burning_grass() below (plus
## the unrelated "walking tramples grass underfoot" call sites in player.gd/enemy.gd, which have
## nothing to do with fire).
func ignite_grass(pos: Vector2i) -> bool:
	if _data.get_tile(pos.x, pos.y) != DungeonData.TileType.GRASS:
		return false
	if _burning_grass.has(pos):
		return false
	_burning_grass[pos] = true
	return true

## Finalizes every GRASS tile that was ALREADY burning before this round's own spread step —
## converts it to TRAMPLED_GRASS via destroy_grass(). Called from tick_burning_props() AFTER
## _spread_fire_between_props() runs, and only acts on a snapshot taken BEFORE that spread step —
## a tile freshly ignited by this same tick's spread survives into _burning_grass untouched, so it
## gets its own full round to spread before this same function catches up to it next tick. Without
## this snapshot ordering, a newly-lit tile would be destroyed the instant it caught fire and could
## never spread to a second tile at all.
func _tick_burning_grass(pre_tick_snapshot: Array[Vector2i]) -> void:
	for pos: Vector2i in pre_tick_snapshot:
		if _burning_grass.has(pos):
			destroy_grass(pos)

# ── Items ─────────────────────────────────────────────────────────────────────

func _build_floor_item(pos: Vector2i, d: Dictionary) -> void:
	place_item_on_floor(pos, _build_item_from_pool(d))

## Constructs an Item from an ITEM_POOL dict without placing it anywhere — shared by
## _build_floor_item() (floor placement) and _spawn_shop() (shop stock, never touches the floor).
func _build_item_from_pool(d: Dictionary) -> Item:
	var item := Item.new()
	item.item_name = d["name"]
	item.item_type = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.food_value = d.get("food_value", 0)
	item.gold_value = d.get("gold", 0)
	item.silver_value = d.get("silver", 0)
	item.heal_dice_count = d.get("heal_dice", 0)
	item.heal_dice_sides = d.get("heal_sides", 0)
	item.damage_type = d.get("dmg_type", "")
	item.weapon_category = d.get("category", "")
	item.weapon_mastery = d.get("mastery", "")
	item.damage_die_min = d.get("die_min", 0)
	item.damage_die_max = d.get("die_max", 0)
	item.is_heavy = d.get("heavy", false)
	item.is_two_handed = d.get("two_handed", false)
	item.bonus_ac = d.get("bonus_ac", 0)
	item.is_shield = d.get("is_shield", false)
	item.armor_category = int(d.get("armor_cat", 0)) as Item.ArmorCategory
	item.base_ac = d.get("base_ac", 0)
	item.dex_cap = d.get("dex_cap", -1)
	item.str_requirement = d.get("str_req", 0)
	item.stealth_disadvantage = d.get("stealth_disadv", false)
	item.is_finesse = d.get("finesse", false)
	item.is_light = d.get("light", false)
	item.is_torch = d.get("torch", false)
	item.is_reach = d.get("reach", false)
	item.is_versatile = d.get("versatile", false)
	item.versatile_die_min = d.get("vmin", 0)
	item.versatile_die_max = d.get("vmax", 0)
	item.is_thrown = d.get("thrown", false)
	item.uses_max = d.get("uses_max", 0)
	item.uses_remaining = item.uses_max
	item.ammo_item_name = d.get("ammo", "")
	item.str_bonus = d.get("str_bonus", 0)
	item.is_ranged = d.get("is_ranged", false)
	item.range = d.get("range", 0)
	item.long_range = d.get("long_range", 0)
	item.consumes_on_ranged = d.get("consumes", false)
	item.quantity = d.get("qty", 1)
	item.taught_spell_id = d.get("taught_spell", "")
	item.scroll_spell_id = d.get("scroll_spell", "")
	item.is_flammable = item.item_type == Item.Type.SCROLL
	item.floor_min = d["fmin"]
	item.floor_max = d["fmax"]
	item.description = d["desc"]
	if d["src"] == "spells":
		# Scroll of <Spell> reuses the spell's OWN icon_path (SpellDb) rather than reconstructing a
		# flat "res://icons/spells/<name>.png" path from the pool's "icon" key — spell icons live
		# nested by level (res://icons/spells/<level>/<id>.png), so a single source of truth here
		# avoids the two ever drifting out of sync.
		var _scroll_spell: Spell = SpellDb.get_spell(item.scroll_spell_id)
		item.icon_path = _scroll_spell.icon_path if _scroll_spell != null else ""
	else:
		var base_path: String
		match d["src"]:
			"weapons": base_path = DungeonFloorData.WEAPONS_PATH
			"items":   base_path = DungeonFloorData.ITEMS_PATH
			_:         base_path = DungeonFloorData.OBJECTS_PATH
		item.icon_path = base_path + d["icon"]
	return item

func _spawn_items() -> void:
	var eligible: Array = []
	for entry in DungeonFloorData.ITEM_POOL:
		var d: Dictionary = entry
		if GameState.current_floor >= d["fmin"] and GameState.current_floor <= d["fmax"] \
				and DungeonFloorData.is_scroll_level_eligible(d, GameState.player_stats.character_level):
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
			if _traps.has(pos) or _doors.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	RngUtil.shuffle(candidates, _pop_rng)

	var count: int = mini(_pop_rng.randi_range(2, 3), candidates.size())
	for i: int in count:
		var d: Dictionary = eligible[_pop_rng.randi_range(0, eligible.size() - 1)]
		_build_floor_item(candidates[i], d)

# Drains GameState.pending_chasm_items (arrows/ammo that fell into a chasm on the previous
# floor) onto random walkable tiles of THIS floor. Same candidate-picking pattern as
# _spawn_items(). General-purpose, not arrow-specific.
func _spawn_pending_chasm_items() -> void:
	if GameState.pending_chasm_items.is_empty():
		return
	var candidates: Array[Vector2i] = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos := Vector2i(x, y)
			var tile: DungeonData.TileType = _data.get_tile(x, y)
			if tile != DungeonData.TileType.FLOOR and tile != DungeonData.TileType.MUD:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var items: Array[Item] = GameState.pending_chasm_items.duplicate()
	GameState.pending_chasm_items.clear()
	for i: int in items.size():
		place_item_on_floor(candidates[i % candidates.size()], items[i])

# ── Gold (docs/architecture/special-rooms-economy-design.md §2.3) ─────────────

# Builds a Type.GOLD floor item — gold_value doubles as the pile size. Picked up into
# GameState.gold by PlayerActions.check_pickup(), never into the inventory.
func _make_gold_item(amount: int) -> Item:
	var item := Item.new()
	item.item_name = "Gold"
	item.item_type = Item.Type.GOLD
	item.gold_value = maxi(1, amount)
	item.description = "A pile of gold coins."
	item.icon_path = DungeonFloorData.ITEMS_PATH + "misc/coin_gold.png"
	return item

# Floor scatter: 1-2 gold piles on random walkable tiles. Same candidate-picking pattern as
# _spawn_items(). Runs LAST in the _load_floor() spawn order (after _spawn_pending_chasm_items())
# so every pre-existing _pop_rng draw keeps its position — the spawn call order and per-function
# draw counts are load-bearing for reproducibility (scripts/world/CLAUDE.md).
func _spawn_gold_piles() -> void:
	var candidates: Array[Vector2i] = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos := Vector2i(x, y)
			var tile: DungeonData.TileType = _data.get_tile(x, y)
			if tile != DungeonData.TileType.FLOOR and tile != DungeonData.TileType.MUD:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var count: int = mini(_pop_rng.randi_range(1, 2), candidates.size())
	for i: int in count:
		var amount: int = _pop_rng.randi_range(5, 10) + GameState.current_floor
		place_item_on_floor(candidates[i], _make_gold_item(amount))

# Special-room population dispatcher (special-rooms-economy-design.md §3.3, session 7b).
# The ONE place a room type_id string is matched — it dispatches *population*, not generation.
# Runs LAST in the _load_floor() spawn order (after _spawn_gold_piles()) so every pre-existing
# _pop_rng draw keeps its position. Treasure/Garden are live (sessions 7c/7d) — floors that
# actually roll one of those rooms now consume extra _pop_rng draws here, an intentional
# generation-footprint change on those floors only (same precedent as the ROOM_POOL session).
func _spawn_special_rooms() -> void:
	for meta: Dictionary in _data.room_metadata:
		match meta["type_id"]:
			"shop":
				_spawn_shop(meta["rect"])
			"treasure":
				_spawn_treasure(meta["rect"])
			"garden":
				_spawn_garden_items(meta["rect"])
			"secret":
				_spawn_secret_room(meta["rect"])
			"blacksmith":
				_spawn_blacksmith(meta["rect"])

# TreasureRoom content (special-rooms-economy-design.md §4.2, session 7c): 3 guaranteed
# ITEM_POOL rolls + 1 guaranteed gold pile, guarded by locking the room's one connecting door
# (same manual lock — no AudioManager at generation time — as _spawn_locked_doors() above), and
# on floors >= 4, 1-2 traps inside the vault. Guard mirrors every other special-room population
# function: an empty rect (BSP-fallback floor, §3.2) means this room never materialized.
func _spawn_treasure(rect: Rect2i) -> void:
	if rect == Rect2i():
		return
	var eligible: Array = []
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"] \
				and DungeonFloorData.is_scroll_level_eligible(entry, GameState.player_stats.character_level):
			eligible.append(entry)

	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)

	var used: int = 0
	if not eligible.is_empty():
		var loot_count: int = mini(3, candidates.size())
		for i: int in loot_count:
			var d: Dictionary = eligible[_pop_rng.randi_range(0, eligible.size() - 1)]
			_build_floor_item(candidates[i], d)
			used += 1
	if used < candidates.size():
		var amount: int = _pop_rng.randi_range(15, 25) + 2 * GameState.current_floor
		place_item_on_floor(candidates[used], _make_gold_item(amount))
		used += 1

	if GameState.current_floor >= 4 and used < candidates.size():
		var trap_pool: Array = []
		for entry: Dictionary in DungeonFloorData.TRAP_POOL:
			if not entry.get("wall_trap", false):
				trap_pool.append(entry)
		if not trap_pool.is_empty():
			var trap_count: int = mini(_pop_rng.randi_range(1, 2), candidates.size() - used)
			for i: int in trap_count:
				var t: Dictionary = trap_pool[_pop_rng.randi_range(0, trap_pool.size() - 1)]
				_place_floor_trap(candidates[used + i], t)

	# Guard the vault: lock the door on the room's immediate perimeter ring (its one connection,
	# max_connections() == 1). _spawn_doors() places doors probabilistically (65%/candidate), so
	# an unlucky floor can leave this junction door-less — no lock exists to place; the loot still
	# spawns, just undefended. Accepted degrade, same tolerance as BSP-fallback floors losing
	# their special rooms entirely (§3.2) — no forcing machinery added for this edge case.
	for pos: Vector2i in _doors.keys():
		if rect.grow(1).has_point(pos) and not rect.has_point(pos):
			if not _doors[pos]["locked"]:
				_doors[pos]["locked"] = true
				_doors[pos]["player_locked"] = false
				var sp: Sprite2D = _doors[pos]["sprite"]
				if is_instance_valid(sp):
					sp.modulate = Color(0.55, 0.35, 0.85)
				_add_lock_icon_at(pos)
			break

# GardenRoom content (special-rooms-economy-design.md §4.3, session 7d): 1-2 Healing Herb items
# on the GRASS tiles GardenRoom.paint() already carpeted at generation time. Herb is looked up by
# name (sentinel fmin/fmax 99 keeps it out of every floor-eligibility filter elsewhere) rather
# than gated by floor range, since this room is its only spawn path.
func _spawn_garden_items(rect: Rect2i) -> void:
	if rect == Rect2i():
		return
	var herb: Dictionary = {}
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if entry["name"] == "Healing Herb":
			herb = entry
			break
	if herb.is_empty():
		return

	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.GRASS:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var count: int = mini(_pop_rng.randi_range(1, 2), candidates.size())
	for i: int in count:
		_build_floor_item(candidates[i], herb)

# SecretRoom content (special-rooms-economy-design.md §4.4, session 7f): hides the room's one
# connecting door (see has_door_at()/_reveal_secret_door() above) and spawns a reward that's
# "strictly better than a locked-door room" — 2-3 ITEM_POOL rolls (one biased to the top half by
# gold_value, a rarity proxy) plus a guaranteed larger gold pile. Same door-finding technique as
# _spawn_treasure()'s lock loop just above. If _spawn_doors()' probabilistic 65%/candidate roll
# missed this room's one junction, there's no door to hide — unlike TreasureRoom's own "loot still
# spawns, just undefended" degrade, an unguarded top-tier reward is worse than none, so this skips
# the whole reward outright rather than granting free loot.
func _spawn_secret_room(rect: Rect2i) -> void:
	if rect == Rect2i():
		return
	var door_pos: Vector2i = Vector2i(-1, -1)
	for pos: Vector2i in _doors.keys():
		if rect.grow(1).has_point(pos) and not rect.has_point(pos):
			door_pos = pos
			break
	if door_pos == Vector2i(-1, -1):
		return

	_doors[door_pos]["hidden"] = true
	var door_sprite: Sprite2D = _doors[door_pos]["sprite"]
	if is_instance_valid(door_sprite):
		door_sprite.visible = false
	tilemap.set_cell(door_pos, SOURCE_WALL, ATLAS_ORIGIN)

	var eligible: Array = []
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"] \
				and DungeonFloorData.is_scroll_level_eligible(entry, GameState.player_stats.character_level):
			eligible.append(entry)

	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)

	var used: int = 0
	if not eligible.is_empty() and used < candidates.size():
		var by_value: Array = eligible.duplicate()
		by_value.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a.get("gold", 0) > b.get("gold", 0))
		var top_half: Array = by_value.slice(0, maxi(1, by_value.size() / 2))
		var biased: Dictionary = top_half[_pop_rng.randi_range(0, top_half.size() - 1)]
		_build_floor_item(candidates[used], biased)
		used += 1
		var extra_count: int = mini(_pop_rng.randi_range(1, 2), candidates.size() - used)
		for i: int in extra_count:
			var d: Dictionary = eligible[_pop_rng.randi_range(0, eligible.size() - 1)]
			_build_floor_item(candidates[used + i], d)
		used += extra_count

	if used < candidates.size():
		var amount: int = _pop_rng.randi_range(20, 30) + 2 * GameState.current_floor
		place_item_on_floor(candidates[used], _make_gold_item(amount))

# BlacksmithRoom content: a single impassable prop tile the player bumps/RMB-interacts with to
# open blacksmith_panel.gd (scripts/ui/CLAUDE.md). No-op if rect is empty (BSP-fallback floor,
# same guard every other special-room population function uses) or the room has no candidate tile.
func _spawn_blacksmith(rect: Rect2i) -> void:
	if rect == Rect2i():
		return
	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var pos: Vector2i = candidates[0]
	var tex: Texture2D = null
	if ResourceLoader.exists(BLACKSMITH_TEX_PATH):
		tex = load(BLACKSMITH_TEX_PATH)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = BLACKSMITH_TINT
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	if tex != null:
		var ts: Vector2 = tex.get_size()
		sprite.scale = Vector2(float(TILE_SIZE) / ts.x, float(TILE_SIZE) / ts.y)
	entities.add_child(sprite)
	_blacksmiths[pos] = {"sprite": sprite}

func has_blacksmith_at(pos: Vector2i) -> bool:
	return _blacksmiths.has(pos)

# ShopRoom content (special-rooms-economy-design.md §4.1, session 7e): one impassable shopkeeper
# prop tile (bump/RMB opens shop_panel.gd, same interaction shape as the Blacksmith prop) plus a
# generated stock of 4-6 distinct ITEM_POOL entries. Stock is overlay-only — never placed on the
# floor, never restocked, discarded when the floor unloads (no persistence). No-op if rect is
# empty (BSP-fallback floor, same guard every other special-room population function uses) or the
# room has no candidate tile.
func _spawn_shop(rect: Rect2i) -> void:
	if rect == Rect2i():
		return
	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	var pos: Vector2i = candidates[0]

	var tex: Texture2D = null
	var tint: Color = SHOPKEEPER_TINT
	if ResourceLoader.exists(SHOPKEEPER_TEX_PATH):
		tex = load(SHOPKEEPER_TEX_PATH)
	elif ResourceLoader.exists(SHOPKEEPER_FALLBACK_TEX_PATH):
		tex = load(SHOPKEEPER_FALLBACK_TEX_PATH)
	var sprite := Sprite2D.new()
	sprite.texture = tex
	sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	sprite.modulate = tint
	sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
	sprite.z_index = 1
	if tex != null:
		var ts: Vector2 = tex.get_size()
		sprite.scale = Vector2(float(TILE_SIZE) / ts.x, float(TILE_SIZE) / ts.y)
	entities.add_child(sprite)

	var eligible: Array = []
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if entry.get("gold", 0) <= 0:
			continue
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"] \
				and DungeonFloorData.is_scroll_level_eligible(entry, GameState.player_stats.character_level):
			eligible.append(entry)
	RngUtil.shuffle(eligible, _pop_rng)

	var stock: Array[Item] = []
	var have_food: bool = false
	var ration_entry: Dictionary = {}
	for entry: Dictionary in eligible:
		if entry["name"] == "Ration":
			ration_entry = entry
		if stock.size() >= mini(SHOP_STOCK_MAX, eligible.size()):
			break
		stock.append(_build_item_from_pool(entry))
		if entry.get("type") == Item.Type.FOOD:
			have_food = true
	if not have_food and not ration_entry.is_empty() and stock.size() < SHOP_STOCK_MAX:
		stock.append(_build_item_from_pool(ration_entry))
	while stock.size() < mini(SHOP_STOCK_MIN, eligible.size()):
		stock.append(_build_item_from_pool(eligible[stock.size() % eligible.size()]))

	_shopkeepers[pos] = {"sprite": sprite, "stock": stock}

func has_shopkeeper_at(pos: Vector2i) -> bool:
	return _shopkeepers.has(pos)

## Returns the LIVE stock array for the shopkeeper at pos (not a copy) — shop_panel.gd removes
## bought items from it directly. Empty array if there's no shopkeeper there.
func get_shopkeeper_stock(pos: Vector2i) -> Array[Item]:
	if not _shopkeepers.has(pos):
		return []
	return _shopkeepers[pos]["stock"]

# Mold (Blacksmith crafting material): guaranteed exactly once per run, on GameState.
# mold_target_floor (rolled once at run start, uniform across floors 1-4 — see
# scripts/autoloads/CLAUDE.md). No-op on every other floor, and once mold_spawned flips true.
# Sentinel fmin/fmax=99 on the ITEM_POOL entry (same convention as Healing Herb) keeps it out of
# every generic floor-loot roll — this is its only spawn path.
func _spawn_mold() -> void:
	if GameState.current_floor != GameState.mold_target_floor or GameState.mold_spawned:
		return
	var mold: Dictionary = {}
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if entry["name"] == "Mold":
			mold = entry
			break
	if mold.is_empty():
		return
	var candidates: Array[Vector2i] = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos := Vector2i(x, y)
			var tile: DungeonData.TileType = _data.get_tile(x, y)
			if tile != DungeonData.TileType.FLOOR and tile != DungeonData.TileType.MUD:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos) or _barrels.has(pos) or _blacksmiths.has(pos):
				continue
			candidates.append(pos)
	if candidates.is_empty():
		return
	RngUtil.shuffle(candidates, _pop_rng)
	_build_floor_item(candidates[0], mold)
	GameState.mold_spawned = true

# Enemy gold drop: 30% chance on any non-boss enemy death (bosses drop a guaranteed pile in
# drop_boss_loot() instead). Kill-time randomness → gameplay Rng stream, same load-time-vs-runtime
# split as _roll_boss_loot_item(). Called from Enemy.die() — the single chokepoint every death
# call site already ends with (same reasoning as embedded_items).
func maybe_drop_enemy_gold(enemy: Enemy) -> void:
	if enemy.is_boss:
		return
	if not Rng.chance(0.3):
		return
	var amount: int = Rng.range_i(1, 4) + GameState.current_floor / 2
	place_item_on_floor(enemy.grid_pos, _make_gold_item(amount))

# A one-shot thrown weapon (Goblin Minion's Dagger, Orc Warrior's Javelin, whether the throw
# landed or missed — both are queued unconditionally, matching Goblin Minion's original behavior):
# queued by Enemy.die() when that enemy had one lodged near a target, resolved one player turn
# later (via TurnManager.player_turn_started, connected in _ready()) — a per-enemy chance to
# actually find it (both Goblin's Dagger and Orc's Javelin default to 50%), dropped at wherever
# the target currently stands (not the thrower's own death tile). Deliberately a one-turn delay,
# not an instant drop, per the original spec ("the turn after goblin dies").
var _pending_thrown_weapon_drops: Array[Dictionary] = []

func queue_thrown_weapon_drop(target: Node, item: Item, chance: float = 0.5) -> void:
	_pending_thrown_weapon_drops.append({"target": target, "item": item, "chance": chance})

func _resolve_pending_thrown_weapon_drops() -> void:
	if _pending_thrown_weapon_drops.is_empty():
		return
	for entry: Dictionary in _pending_thrown_weapon_drops:
		var target: Node = entry["target"]
		if is_instance_valid(target) and Rng.chance(float(entry.get("chance", 0.5))):
			place_item_on_floor(target.grid_pos, entry["item"])
	_pending_thrown_weapon_drops.clear()

func _spawn_locked_doors() -> void:
	if _doors.is_empty():
		return
	# One gated-loot room per floor (special-rooms-economy-design.md §4.2, session 7c) — a
	# TreasureRoom already IS that room, so skip the generic locked-door pass entirely rather
	# than double up on gated loot. Also skip on a SecretRoom (§4.4, session 7f): this pass runs
	# BEFORE _spawn_special_rooms(), so without this it could lock-and-reward the SecretRoom's own
	# sole connecting door before _spawn_secret_room() ever gets to hide it.
	for meta: Dictionary in _data.room_metadata:
		if meta["type_id"] == "treasure" or meta["type_id"] == "secret":
			return
	var eligible: Array = []
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"] \
				and DungeonFloorData.is_scroll_level_eligible(entry, GameState.player_stats.character_level):
			eligible.append(entry)
	if eligible.is_empty():
		return

	var door_positions: Array = _doors.keys()
	RngUtil.shuffle(door_positions, _pop_rng)

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
					if _traps.has(rp) or _floor_items.has(rp) or _doors.has(rp) or _barrels.has(rp):
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
		RngUtil.shuffle(reward_candidates, _pop_rng)
		var count: int = mini(_pop_rng.randi_range(2, 3), reward_candidates.size())
		for i: int in count:
			var d: Dictionary = eligible[_pop_rng.randi_range(0, eligible.size() - 1)]
			_build_floor_item(reward_candidates[i], d)

		break  # max 1 locked door per floor

# Returns the newest (topmost, last-dropped) item at pos — the one whose icon is showing.
func get_item_at(pos: Vector2i) -> Item:
	var stack: Array = _floor_items.get(pos, [])
	return stack.back() as Item if not stack.is_empty() else null

# Returns the full stack at pos (oldest first), e.g. every arrow that landed on one tile.
func get_items_at(pos: Vector2i) -> Array[Item]:
	var stack: Array = _floor_items.get(pos, [])
	var out: Array[Item] = []
	for it: Item in stack:
		out.append(it)
	return out

func remove_floor_item(pos: Vector2i) -> void:
	if _floor_item_sprites.has(pos):
		var sn: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(sn):
			sn.queue_free()
		_floor_item_sprites.erase(pos)
	_floor_items.erase(pos)

const BOSS_LOOT_POOL: Array = [
	{"name": "Strength Potion","type": 2, "icon": "potions/mana/medium.png",     "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)", "gold": 80},
	{"name": "Health Potion",  "type": 2, "icon": "potions/health/medium.png",  "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4, "gold": 30},
]

func _roll_boss_loot_item() -> Item:
	var d: Dictionary = Rng.pick(BOSS_LOOT_POOL)  # rolled at kill time → gameplay Rng stream
	var item := Item.new()
	item.item_name = d["name"]
	item.item_type = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.food_value = d.get("food_value", 0)
	item.gold_value = d.get("gold", 0)
	item.silver_value = d.get("silver", 0)
	item.heal_dice_count = d.get("heal_dice", 0)
	item.heal_dice_sides = d.get("heal_sides", 0)
	item.str_bonus = d.get("str_bonus", 0)
	item.floor_min = d["fmin"]
	item.floor_max = d["fmax"]
	item.description = d["desc"]
	match d["src"]:
		"weapons": item.icon_path = DungeonFloorData.WEAPONS_PATH + d["icon"]
		"items":   item.icon_path = DungeonFloorData.ITEMS_PATH + d["icon"]
		_:         item.icon_path = DungeonFloorData.OBJECTS_PATH + d["icon"]
	return item

func drop_boss_loot(pos: Vector2i) -> void:
	# No physical melee weapons drop as loot anymore (Barbarian's Greataxe, Short Bow,
	# and Heavy Crossbow are the only weapons in the game) — boss loot is potions only.
	var item: Item = _roll_boss_loot_item()
	place_item_on_floor(pos, item)
	GameState.game_log("[color=yellow][b]The boss dropped [/b][color=white]%s[/color][b]![/b][/color]" % item.item_name)
	# Guaranteed gold pile alongside the potion loot (special-rooms-economy-design.md §2.3).
	var gold_amount: int = 20 + 5 * GameState.current_floor
	place_item_on_floor(pos, _make_gold_item(gold_amount))
	GameState.game_log("[color=gold][b]The boss dropped %d gold![/b][/color]" % gold_amount)

## Push weapon mastery (Heavy Crossbow): shoves `enemy` exactly 1 tile in `direction`.
## Distinct from force_move_entity() because a CHASM destination here is a valid outcome
## (the target falls in and is removed, loot deferred to the next floor down via
## GameState.pending_chasm_items) rather than treated as blocking, and hitting a WALL
## deals a flat 1d4 Bludgeoning instead of the piston-style splash-damage formula.
## Forced movement never provokes an Opportunity Attack (5e RAW) — intentionally OA-free.
func resolve_push(enemy: Enemy, direction: Vector2i) -> void:
	if not is_instance_valid(enemy) or direction == Vector2i.ZERO:
		return
	if "forced_move" in enemy.condition_immunities:
		return
	var dest: Vector2i = enemy.grid_pos + direction
	if enemy.size != Vector2i.ONE:
		# Large enemy (multi-tile footprint): the wall-bump/chasm special cases below are authored
		# for a single destination tile and don't generalize cleanly to a 2x2+ block straddling a
		# wall corner or a chasm edge — Push instead only succeeds when the ENTIRE destination
		# footprint is plain open floor, otherwise it's simply blocked (too bulky to shove).
		if not is_area_walkable_for_enemy(dest, enemy.size, enemy):
			return
		await enemy.move_to(dest, 0.15)
		GameState.game_log("[color=cyan]Push:[/color] [color=orange]%s[/color] [color=gray]is shoved back.[/color]" % enemy.display_name)
		return
	if get_enemy_at(dest) != null or (_player != null and _player.occupies(dest)):
		return  # blocked by another occupant — stays put, no damage
	var tile: DungeonData.TileType = _data.get_tile(dest.x, dest.y)
	if tile == DungeonData.TileType.CHASM:
		GameState.game_log("[color=cyan]%s is pushed into the chasm and vanishes![/color]" % enemy.display_name)
		if enemy.is_boss:
			GameState.pending_chasm_items.append(_roll_boss_loot_item())
			GameState.boss_defeated.emit(enemy.enemy_id)
		GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
		remove_enemy(enemy)
		enemy.die()
		return
	if not _data.is_walkable(dest):
		var dmg: int = Rng.roll(4)
		var actual: int = enemy.stats.take_damage(dmg)
		enemy.update_hp_bar()
		show_damage(enemy.position, actual, false)
		GameState.game_log("[color=cyan]Push:[/color] [color=orange]%s[/color] slams into a wall for [color=yellow]%d[/color] [color=gray]Bludgeoning[/color] dmg." % [enemy.display_name, actual])
		if enemy.stats.is_dead():
			GameState.game_log("[color=orange]%s[/color] [color=gray]is killed![/color]" % enemy.display_name)
			GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
			remove_enemy(enemy)
			enemy.die()
		return
	await enemy.move_to(dest, 0.15)
	GameState.game_log("[color=cyan]Push:[/color] [color=orange]%s[/color] [color=gray]is shoved back.[/color]" % enemy.display_name)
	if _traps.has(dest):
		trigger_trap(dest, enemy)
