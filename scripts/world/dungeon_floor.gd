class_name DungeonFloor
extends Node2D

const TILE_SIZE: int = 16
const ATLAS_ORIGIN := Vector2i(0, 0)
const SOURCE_FLOOR: int = 0
const SOURCE_WALL: int = 1
const SOURCE_STAIRS: int = 2
const TILE_SPRITES_PATH := "res://sprites/tiles/"
const WEAPONS_PATH := "res://sprites/weapons/"
const OBJECTS_PATH := "res://sprites/objects/"

const ENEMY_COUNT_MIN: int = 3
const ENEMY_COUNT_MAX: int = 5
const FOV_RADIUS: int = 6
const TRAP_COUNT_MIN: int = 4
const TRAP_COUNT_MAX: int = 7
const TRAP_PATH := "res://sprites/Traps/"

const TRAP_POOL: Array = [
	{"name": "Bear Trap",  "sprite": "Bear_Trap.png",       "damage": 5, "msg": "The bear trap snaps shut on you!", "wall_trap": false},
	{"name": "Fire Trap",  "sprite": "Fire_Trap.png",        "damage": 8, "msg": "Jets of flame engulf you!",        "wall_trap": false},
	{"name": "Spike Trap", "sprite": "Spike Trap.png",       "damage": 6, "msg": "Spikes shoot up from the floor!", "wall_trap": false},
	{"name": "Pit Spikes", "sprite": "Pit_Trap_Spikes.png",  "damage": 7, "msg": "You fall into a spike pit!",       "wall_trap": false},
	{"name": "Piston",     "sprite": "Push_Trap_Front.png",  "damage": 0, "msg": "A piston blasts you!",             "wall_trap": true},
]

# item_type: 0=WEAPON 1=ARMOR 2=POTION  (matches Item.Type enum)
const ITEM_POOL: Array = [
	{"name": "Rusty Sword",   "type": 0, "icon": "weapon_rusty_sword.png",   "src": "weapons", "bonus_dmg": 1, "heal": 0,  "fmin": 1, "fmax": 3,  "desc": "+1 damage"},
	{"name": "Short Sword",   "type": 0, "icon": "weapon_knife.png",          "src": "weapons", "bonus_dmg": 1, "heal": 0,  "fmin": 1, "fmax": 4,  "desc": "+1 damage"},
	{"name": "Sword",         "type": 0, "icon": "weapon_regular_sword.png",  "src": "weapons", "bonus_dmg": 2, "heal": 0,  "fmin": 2, "fmax": 6,  "desc": "+2 damage"},
	{"name": "Knight Sword",  "type": 0, "icon": "weapon_knight_sword.png",   "src": "weapons", "bonus_dmg": 3, "heal": 0,  "fmin": 4, "fmax": 8,  "desc": "+3 damage"},
	{"name": "Golden Sword",  "type": 0, "icon": "weapon_golden_sword.png",   "src": "weapons", "bonus_dmg": 4, "heal": 0,  "fmin": 6, "fmax": 10, "desc": "+4 damage"},
	{"name": "Lavish Sword",  "type": 0, "icon": "weapon_lavish_sword.png",   "src": "weapons", "bonus_dmg": 5, "heal": 0,  "fmin": 8, "fmax": 10, "desc": "+5 damage"},
	{"name": "Health Potion",   "type": 2, "icon": "flask_red.png",    "src": "objects", "bonus_dmg": 0, "heal": 10, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 10 HP"},
	{"name": "Strength Potion","type": 2, "icon": "flask_big_yellow.png","src": "objects","bonus_dmg": 2, "heal": 0,  "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)"},
]

const ENEMY_POOL: Array = [
	{"display_name": "Tiny Zombie", "sprite": "tiny_zombie", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 3,  "hp": 5,  "hp_per_floor": 1, "dmg_min": 1, "dmg_max": 3, "armor": 0, "exp": 4},
	{"display_name": "Orc Warrior", "sprite": "orc_warrior", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,  "hp": 8,  "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "exp": 8},
	{"display_name": "Goblin",      "sprite": "goblin",      "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 6,  "hp": 7,  "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 4, "armor": 0, "exp": 6},
	{"display_name": "Orc Shaman",  "sprite": "orc_shaman",  "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 0, "exp": 12},
	{"display_name": "Masked Orc",  "sprite": "masked_orc",  "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 12, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 1, "exp": 10},
	{"display_name": "Skeleton",    "sprite": "skelet",      "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 9,  "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 6, "armor": 1, "exp": 9},
	{"display_name": "Wogol",       "sprite": "wogol",       "idle_frames": 4, "run_frames": 4, "floor_min": 5, "floor_max": 8,  "hp": 14, "hp_per_floor": 3, "dmg_min": 3, "dmg_max": 6, "armor": 1, "exp": 15},
	{"display_name": "Imp",         "sprite": "imp",         "idle_frames": 4, "run_frames": 4, "floor_min": 6, "floor_max": 9,  "hp": 11, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 7, "armor": 1, "exp": 13},
	{"display_name": "Chort",       "sprite": "chort",       "idle_frames": 4, "run_frames": 4, "floor_min": 7, "floor_max": 10, "hp": 16, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 8, "armor": 2, "exp": 20},
	{"display_name": "Pumpkin Dude","sprite": "pumpkin_dude","idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 20, "hp_per_floor": 4, "dmg_min": 5, "dmg_max": 9, "armor": 2, "exp": 25},
]

@onready var tilemap: TileMapLayer = $TileMap
@onready var entities: Node2D = $Entities

var _data: DungeonData
var _player: Player
var _enemies: Array[Enemy] = []
var _traps: Dictionary = {}   # Vector2i → {name, damage, msg, sprite_node, revealed}

var _floor_items: Dictionary = {}         # Vector2i → Item
var _floor_item_sprites: Dictionary = {}  # Vector2i → Sprite2D

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
	_add_tile_source(tile_set, SOURCE_FLOOR,  TILE_SPRITES_PATH + "floor_1.png")
	_add_tile_source(tile_set, SOURCE_WALL,   TILE_SPRITES_PATH + "wall_mid.png")
	_add_tile_source(tile_set, SOURCE_STAIRS, TILE_SPRITES_PATH + "floor_stairs.png")
	tilemap.tile_set = tile_set

func _add_tile_source(tile_set: TileSet, source_id: int, path: String) -> void:
	var atlas := TileSetAtlasSource.new()
	atlas.texture = load(path)
	atlas.texture_region_size = Vector2i(TILE_SIZE, TILE_SIZE)
	atlas.create_tile(ATLAS_ORIGIN)
	tile_set.add_source(atlas, source_id)

func _load_floor() -> void:
	for e in _enemies:
		if is_instance_valid(e):
			e.queue_free()
	_enemies.clear()
	TurnManager.clear_enemies()
	TurnManager.reset()
	for pos: Vector2i in _traps:
		var sn: Sprite2D = _traps[pos].get("sprite_node")
		if sn != null and is_instance_valid(sn):
			sn.queue_free()
	_traps.clear()
	for pos: Vector2i in _floor_item_sprites:
		var sn: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(sn):
			sn.queue_free()
	_floor_items.clear()
	_floor_item_sprites.clear()

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
	_spawn_traps()
	_spawn_items()
	_setup_fog()
	update_fog(_data.player_start)

func _spawn_enemies() -> void:
	var candidates: Array = []
	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) == DungeonData.TileType.FLOOR:
				if pos != _data.player_start and pos != _data.stairs_pos:
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

	for i: int in count:
		var type_data: Dictionary = eligible[randi() % eligible.size()]
		var enemy: Enemy = enemy_scene.instantiate() as Enemy
		enemy.configure(type_data)
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
			var tile_pos := Vector2i(x, y)
			var in_fov: bool = (dx * dx + dy * dy <= r2) and has_line_of_sight(player_pos, tile_pos)
			if in_fov:
				_explored[tile_pos] = true
				_fog_image.set_pixel(x, y, Color(0, 0, 0, 0))
			elif _explored.get(tile_pos, false):
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
			enemy.visible = (dx * dx + dy * dy) <= r2 and has_line_of_sight(player_pos, enemy.grid_pos)

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
	if _traps.has(pos):
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

func get_visible_enemies() -> Array[Enemy]:
	var result: Array[Enemy] = []
	for e: Enemy in _enemies:
		if is_instance_valid(e) and e.visible:
			result.append(e)
	return result

func on_player_reached_stairs() -> void:
	GameState.advance_floor()
	if GameState.current_floor > 10:
		return
	_load_floor()

func _spawn_traps() -> void:
	var floor_cands: Array = []
	var wall_cands: Array = []  # {floor_pos, wall_pos, push_dir}
	var cardinal: Array[Vector2i] = [Vector2i(1,0), Vector2i(-1,0), Vector2i(0,1), Vector2i(0,-1)]

	for y: int in _data.height:
		for x: int in _data.width:
			var pos: Vector2i = Vector2i(x, y)
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if maxi(abs(pos.x - _data.player_start.x), abs(pos.y - _data.player_start.y)) < 2:
				continue
			floor_cands.append(pos)
			for d: Vector2i in cardinal:
				var wp: Vector2i = pos + d
				if _data.get_tile(wp.x, wp.y) == DungeonData.TileType.WALL:
					wall_cands.append({"floor_pos": pos, "wall_pos": wp, "push_dir": Vector2i(-d.x, -d.y)})
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
		sprite.modulate.a = 0.5
		entities.add_child(sprite)
		_traps[pos] = {"name": t["name"], "damage": t["damage"], "msg": t["msg"],
					   "sprite_node": sprite, "revealed": false, "is_push": false}

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
			sprite.position = Vector2(wall_pos.x * TILE_SIZE + TILE_SIZE * 0.5, wall_pos.y * TILE_SIZE + TILE_SIZE * 0.5)
			# Sprite faces down at 0°; subtract PI/2 to map push_dir to correct facing
			sprite.rotation = atan2(float(push_dir.y), float(push_dir.x)) - PI / 2.0
			sprite.z_index = 1
			sprite.modulate.a = 0.5
			entities.add_child(sprite)
			_traps[floor_pos] = {"name": t["name"], "damage": 0, "msg": t["msg"],
								 "sprite_node": sprite, "revealed": false, "is_push": true,
								 "push_dir": push_dir}

	GameState.log("[color=gray]Floor has %d hidden traps.[/color]" % _traps.size())

func get_trap_at(pos: Vector2i) -> Dictionary:
	return _traps.get(pos, {})

func trigger_trap(pos: Vector2i, entity: Node2D = null) -> void:
	if not _traps.has(pos):
		return
	var trap: Dictionary = _traps[pos]
	var sprite_node: Sprite2D = trap.get("sprite_node") as Sprite2D
	if is_instance_valid(sprite_node):
		sprite_node.modulate.a = 1.0
	_traps.erase(pos)

	var target: Node2D
	if entity != null:
		target = entity
	elif _player != null:
		target = _player

	if trap.get("is_push", false):
		await _push_entity(target, trap["push_dir"], 2, sprite_node)
	else:
		var dmg: int = trap["damage"] + GameState.current_floor / 2
		_apply_trap_damage(target, dmg, trap["msg"])
		if is_instance_valid(sprite_node):
			_play_trap_animation(sprite_node)

func _apply_trap_damage(entity: Node2D, damage: int, msg: String) -> void:
	if entity is Player:
		var actual: int = GameState.player_stats.take_damage(damage)
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.log("[color=red]%s[/color] You take [color=yellow]%d[/color] damage!" % [msg, actual])
		GameState.check_player_death()
	elif entity is Enemy:
		var e: Enemy = entity as Enemy
		var actual: int = e.stats.take_damage(damage)
		e.update_hp_bar()
		GameState.log("[color=orange]%s[/color] triggers a trap for [color=yellow]%d[/color] damage!" % [e.display_name, actual])
		if e.stats.is_dead():
			GameState.log("[color=orange]%s[/color] [color=gray]is killed by a trap.[/color]" % e.display_name)
			GameState.gain_exp(e.exp_reward)
			remove_enemy(e)
			e.die()

func _push_entity(entity: Node2D, push_dir: Vector2i, distance: int, trap_sprite: Sprite2D = null) -> void:
	if not is_instance_valid(entity):
		if is_instance_valid(trap_sprite):
			_play_trap_animation(trap_sprite)
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
		_play_trap_animation(trap_sprite)
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
		GameState.log("[color=red]You are blasted%s for [color=yellow]%d[/color] damage![/color]" % [wall_str, actual])
		GameState.check_player_death()
	elif entity is Enemy:
		var enemy: Enemy = entity as Enemy
		var actual: int = enemy.stats.take_damage(push_dmg)
		enemy.update_hp_bar()
		GameState.log("[color=orange]%s[/color] is blasted%s for [color=yellow]%d[/color] damage!" % [enemy.display_name, wall_str, actual])
		if enemy.stats.is_dead():
			GameState.log("[color=orange]%s[/color] [color=gray]is killed![/color]" % enemy.display_name)
			GameState.gain_exp(enemy.exp_reward)
			remove_enemy(enemy)
			enemy.die()

func _play_trap_animation(sprite_node: Sprite2D) -> void:
	var tex: Texture2D = sprite_node.texture
	if tex == null:
		sprite_node.queue_free()
		return
	var frame_count: int = int(tex.get_width()) / 32
	if frame_count <= 1:
		sprite_node.queue_free()
		return
	for f: int in range(1, frame_count):
		sprite_node.region_rect = Rect2(f * 32, 0, 32, 32)
		await get_tree().create_timer(0.07).timeout
	sprite_node.queue_free()

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

func search_around(pos: Vector2i) -> int:
	var found: int = 0
	for dy: int in range(-1, 2):
		for dx: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			if reveal_trap(pos + Vector2i(dx, dy)):
				found += 1
	return found

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
			if _data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == _data.player_start or pos == _data.stairs_pos:
				continue
			if _traps.has(pos):
				continue
			candidates.append(pos)
	candidates.shuffle()

	var count: int = mini(randi_range(2, 3), candidates.size())
	for i: int in count:
		var d: Dictionary = eligible[randi() % eligible.size()]
		var pos: Vector2i = candidates[i]

		var item := Item.new()
		item.item_name = d["name"]
		item.item_type = d["type"] as Item.Type
		item.bonus_damage = d["bonus_dmg"]
		item.heal_amount = d["heal"]
		item.str_bonus = d.get("str_bonus", 0)
		item.floor_min = d["fmin"]
		item.floor_max = d["fmax"]
		item.description = d["desc"]
		var base_path: String = WEAPONS_PATH if d["src"] == "weapons" else OBJECTS_PATH
		item.icon_path = "res://sprites/%s/%s" % [d["src"], d["icon"]]

		var tex: Texture2D = load(base_path + d["icon"])
		if tex == null:
			continue
		var sprite := Sprite2D.new()
		sprite.texture = tex
		sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sprite.position = Vector2(pos.x * TILE_SIZE + TILE_SIZE * 0.5, pos.y * TILE_SIZE + TILE_SIZE * 0.5)
		sprite.z_index = 1
		entities.add_child(sprite)

		_floor_items[pos] = item
		_floor_item_sprites[pos] = sprite

func get_item_at(pos: Vector2i) -> Item:
	return _floor_items.get(pos, null) as Item

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
		if e2 > -dy:
			err -= dy
			x += sx
		if e2 < dx:
			err += dx
			y += sy
		if x == to.x and y == to.y:
			break
		if _data.get_tile(x, y) == DungeonData.TileType.WALL:
			return false
	return true

func remove_floor_item(pos: Vector2i) -> void:
	if _floor_item_sprites.has(pos):
		var sn: Sprite2D = _floor_item_sprites[pos]
		if is_instance_valid(sn):
			sn.queue_free()
		_floor_item_sprites.erase(pos)
	_floor_items.erase(pos)
