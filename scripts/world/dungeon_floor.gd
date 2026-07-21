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

const ENEMY_COUNT_MIN: int = 3
const ENEMY_COUNT_MAX: int = 5
const FOV_RADIUS: int = 7
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
var _doors: Dictionary = {}         # Vector2i → {is_open: bool, sprite: Sprite2D}

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
var _fog_cloud_sprites: Array[Sprite2D] = []  # Fog Cloud spell zone — see _update_fog_cloud_visual()
var _fog_cloud_tex: ImageTexture
var _explored: Dictionary = {}
var _visible_tiles: Dictionary = {}  # Vector2i → true; current FOV set, reset each update_fog
var _fov_player_pos: Vector2i = Vector2i(-1, -1)
var _see_all_active: bool = false

# Sphere-AoE spell-targeting preview (e.g. Fireball) — see "AoE targeting preview" below.
var _aoe_preview_rects: Array[Sprite2D] = []
var _aoe_preview_last_key: String = ""

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
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_CLOSED,    DungeonFloorData.OBJECTS_PATH + "doors_leaf_closed.png", Color(0.5, 0.3, 0.1))
	_add_tile_source_or_color(tile_set, SOURCE_DOOR_OPEN,      DungeonFloorData.OBJECTS_PATH + "doors_leaf_open.png",   Color(0.3, 0.2, 0.05))
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

	if ResourceLoader.exists(DungeonFloorData.ITEMS_PATH + "Misc/KeyIron.png"):
		_lock_icon_tex = load(DungeonFloorData.ITEMS_PATH + "Misc/KeyIron.png")
	# Seeded floor population (SEEDED_FLOOR_POPULATION.md §2). The call order below AND
	# the number of _pop_rng draws inside each function are load-bearing for
	# reproducibility — reordering or inserting a draw changes everything downstream.
	_pop_rng = RandomNumberGenerator.new()
	_pop_rng.seed = GameState.run_seed ^ (GameState.current_floor * POPULATION_SEED_MIX)
	_spawn_enemies()
	_spawn_traps()
	_spawn_doors()
	_spawn_items()
	_spawn_locked_doors()
	_spawn_pending_chasm_items()
	_spawn_gold_piles()
	_spawn_special_rooms()
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

	_visible_tiles = _compute_shadowcast(player_pos, FOV_RADIUS + GameState.fov_radius_bonus + GameState.player_stats.darkvision_bonus + (1 if GameState.has_lit_torch_equipped() else 0))

	# Light cantrip: ends the instant the lit object is no longer on its floor tile (picked up, or
	# otherwise removed) — checked every fog recompute, same cadence the light itself refreshes.
	# Cleared directly (not via GameState.clear_light_source()) to avoid re-entering update_fog():
	# that function's own emit is wired straight back to update_fog() (see _ready() below), and
	# we're already mid-update here — this same call handles the resulting visual refresh below.
	if GameState.light_source_pos != Vector2i(-1, -1):
		var still_there: bool = GameState.light_source_item != null \
			and get_items_at(GameState.light_source_pos).has(GameState.light_source_item)
		if not still_there:
			GameState.light_source_pos = Vector2i(-1, -1)
			GameState.light_source_item = null

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
	_update_fog_cloud_visual()

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

func show_aoe_preview(center: Vector2i, radius: int) -> void:
	var tiles: Array[Vector2i] = []
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				tiles.append(center + Vector2i(dx, dy))
	_paint_aoe_preview_tiles("sphere,%d,%d,%d" % [center.x, center.y, radius], tiles)

# Cone-shaped spell preview (Burning Hands) — same pooled-Sprite2D tint as show_aoe_preview()
# above, just fed the cone's tile set (SpellEffects.cone_tiles(), shared with the actual blast
# resolver so the preview and the real footprint always agree) instead of a Euclidean disc.
func show_cone_preview(origin: Vector2i, aim: Vector2i, length: int) -> void:
	var key: String = "cone,%d,%d,%d,%d,%d" % [origin.x, origin.y, aim.x, aim.y, length]
	_paint_aoe_preview_tiles(key, SpellEffects.cone_tiles(origin, aim, length, self))

func _paint_aoe_preview_tiles(key: String, tiles: Array[Vector2i]) -> void:
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
		spr.modulate = Color(0.65, 0.25, 0.85, 0.35)
		spr.z_index = 2
		add_child(spr)
		_aoe_preview_rects.append(spr)
	for i: int in _aoe_preview_rects.size():
		var spr: Sprite2D = _aoe_preview_rects[i]
		if i < tiles.size():
			spr.position = Vector2(tiles[i].x * TILE_SIZE, tiles[i].y * TILE_SIZE)
			spr.visible = true
		else:
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

# Fog Cloud spell — a persistent gray tint over GameState.fog_cloud_pos/radius (a raw Euclidean
# disc, same distance check as GameState.is_in_fog_cloud() and show_aoe_preview()'s own preview
# circle — no LOS filtering, matching a real cloud of fog rather than a line-of-sight effect).
# Rebuilt every update_fog() call (cheap — pooled Sprite2Ds, same convention as the light glow
# above) so it tracks the cloud fading/moving without needing its own dedicated signal.
func _update_fog_cloud_visual() -> void:
	if GameState.fog_cloud_pos == Vector2i(-1, -1):
		for spr: Sprite2D in _fog_cloud_sprites:
			spr.visible = false
		return
	if _fog_cloud_tex == null:
		var img := Image.create(1, 1, false, Image.FORMAT_RGBA8)
		img.fill(Color(1, 1, 1, 1))
		_fog_cloud_tex = ImageTexture.create_from_image(img)
	var center: Vector2i = GameState.fog_cloud_pos
	var radius: int = GameState.fog_cloud_radius
	var tiles: Array[Vector2i] = []
	for dy: int in range(-radius, radius + 1):
		for dx: int in range(-radius, radius + 1):
			if dx * dx + dy * dy <= radius * radius:
				tiles.append(center + Vector2i(dx, dy))
	while _fog_cloud_sprites.size() < tiles.size():
		var spr := Sprite2D.new()
		spr.texture = _fog_cloud_tex
		spr.centered = false
		spr.scale = Vector2(TILE_SIZE, TILE_SIZE)
		spr.modulate = Color(0.75, 0.75, 0.8, 0.45)
		spr.z_index = 2
		add_child(spr)
		_fog_cloud_sprites.append(spr)
	for i: int in _fog_cloud_sprites.size():
		var spr: Sprite2D = _fog_cloud_sprites[i]
		if i < tiles.size():
			spr.position = Vector2(tiles[i].x * TILE_SIZE, tiles[i].y * TILE_SIZE)
			spr.visible = true
		else:
			spr.visible = false

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
	var eff_radius: int = FOV_RADIUS + GameState.fov_radius_bonus + GameState.player_stats.darkvision_bonus + (1 if GameState.has_lit_torch_equipped() else 0)
	var r2: int = eff_radius * eff_radius
	for e: Enemy in _enemies:
		if not is_instance_valid(e):
			continue
		var dx: int = e.grid_pos.x - _player.grid_pos.x
		var dy: int = e.grid_pos.y - _player.grid_pos.y
		if dx * dx + dy * dy <= r2 and has_line_of_sight(_player.grid_pos, e.grid_pos):
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
	RngUtil.shuffle(candidates, _pop_rng)

	var eligible: Array = []
	for entry in DungeonFloorData.ENEMY_POOL:
		var t: Dictionary = entry
		if GameState.current_floor >= t["floor_min"] and GameState.current_floor <= t["floor_max"]:
			eligible.append(t)
	if eligible.is_empty():
		eligible = [DungeonFloorData.ENEMY_POOL[0]]

	var enemy_scene: PackedScene = preload("res://scenes/game/enemy.tscn")
	var count: int = mini(_pop_rng.randi_range(ENEMY_COUNT_MIN, ENEMY_COUNT_MAX), candidates.size())

	for i: int in count:
		var type_data: Dictionary = eligible[_pop_rng.randi_range(0, eligible.size() - 1)]
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
		enemy.set_grid_pos(candidates[i])
		_enemies.append(enemy)
		TurnManager.register_enemy(enemy)

	if is_boss_floor:
		_spawn_boss()

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


# Multiple items can occupy the same tile — they stack in _floor_items[pos] (Array[Item],
# oldest first). Only the newest (last) item's sprite is shown, so a spot where several
# arrows/items landed still reads as a single pickup icon; walking onto the tile
# (PlayerActions.check_pickup()) collects the whole stack at once.
func place_item_on_floor(pos: Vector2i, item: Item) -> void:
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
	for _i: int in max_distance:
		var nxt: Vector2i = current + direction
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
	if ResourceLoader.exists(DungeonFloorData.OBJECTS_PATH + "doors_leaf_closed.png"):
		tex_closed = load(DungeonFloorData.OBJECTS_PATH + "doors_leaf_closed.png")
	if ResourceLoader.exists(DungeonFloorData.OBJECTS_PATH + "doors_leaf_open.png"):
		tex_open = load(DungeonFloorData.OBJECTS_PATH + "doors_leaf_open.png")

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
	item.food_value = d.get("food_value", 0)
	item.gold_value = d.get("gold", 0)
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
	item.consumes_on_ranged = d.get("consumes", false)
	item.quantity = d.get("qty", 1)
	item.taught_spell_id = d.get("taught_spell", "")
	item.scroll_spell_id = d.get("scroll_spell", "")
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
	place_item_on_floor(pos, item)

func _spawn_items() -> void:
	var eligible: Array = []
	for entry in DungeonFloorData.ITEM_POOL:
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
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos):
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
	item.icon_path = DungeonFloorData.ITEMS_PATH + "Misc/CoinGold.png"
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
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos):
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
				pass  # _spawn_shop(meta["rect"]) — session 7e
			"treasure":
				_spawn_treasure(meta["rect"])
			"garden":
				_spawn_garden_items(meta["rect"])
			"secret":
				pass  # _spawn_secret_room(meta["rect"]) — session 7f

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
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"]:
			eligible.append(entry)

	var candidates: Array[Vector2i] = []
	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos) or _doors.has(pos) or _floor_items.has(pos):
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

func _spawn_locked_doors() -> void:
	if _doors.is_empty():
		return
	# One gated-loot room per floor (special-rooms-economy-design.md §4.2, session 7c) — a
	# TreasureRoom already IS that room, so skip the generic locked-door pass entirely rather
	# than double up on gated loot.
	for meta: Dictionary in _data.room_metadata:
		if meta["type_id"] == "treasure":
			return
	var eligible: Array = []
	for entry: Dictionary in DungeonFloorData.ITEM_POOL:
		if GameState.current_floor >= entry["fmin"] and GameState.current_floor <= entry["fmax"]:
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
	{"name": "Strength Potion","type": 2, "icon": "Potions/Mana/ManaPotionMedium.png",     "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)", "gold": 80},
	{"name": "Health Potion",  "type": 2, "icon": "Potions/Health/HealthPotionMedium.png",  "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4, "gold": 30},
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
	if get_enemy_at(dest) != null or (_player != null and _player.grid_pos == dest):
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
