class_name Enemy
extends Entity

enum Behavior { SLEEPING, STATIONARY, ROAMING, CHASING, SEARCHING }

const SPRITES_PATH := "res://sprites/characters/"
const FOV_RADIUS: int = 6
const WAKE_RADIUS_SQ: int = 4  # 2-tile adjacency wakes sleeping enemies

var _dungeon_floor: Node
var display_name: String = "Enemy"
var exp_reward: int = 5
var _type: Dictionary = {}

var is_boss: bool = false
var initial_behavior: Behavior = Behavior.SLEEPING
var behavior: Behavior = Behavior.SLEEPING
var last_known_player_pos: Vector2i = Vector2i(-1, -1)

var just_crossed_door: bool = false
var slowed_turns: int = 0
var _roam_target: Vector2i = Vector2i(-1, -1)
var _roam_path: Array[Vector2i] = []
# Search state — used when enemy loses sight of player after chasing
var _search_heading: Vector2i = Vector2i(0, 0)
var _search_turns_remaining: int = 0
var _search_target: Vector2i = Vector2i(-1, -1)
var _search_path: Array[Vector2i] = []

var _zzz_label: Label
var _zzz_tween: Tween

func configure(type_data: Dictionary) -> void:
	_type = type_data
	display_name = type_data.get("display_name", "Enemy")

func _ready() -> void:
	stats = Stats.new()
	_apply_stats()
	z_index = 1
	_setup_animations()
	_setup_hp_bar()
	_setup_zzz()
	behavior = initial_behavior
	if behavior == Behavior.SLEEPING:
		_start_zzz()

func _apply_stats() -> void:
	var f: int = GameState.current_floor
	stats.max_hp      = _type.get("hp", 8)      + (f - 1) * _type.get("hp_per_floor", 2)
	stats.min_damage  = _type.get("dmg_min", 1) + (f - 1) / 3
	stats.max_damage  = _type.get("dmg_max", 4) + (f - 1) / 2
	stats.armor       = 0
	stats.armor_class = _type.get("ac", 10) + _type.get("armor", 0) + f / 5
	stats.current_hp  = stats.max_hp
	exp_reward        = _type.get("exp", 5)

func _setup_animations() -> void:
	var prefix: String = _type.get("sprite", "orc_warrior")
	var idle_n: int    = _type.get("idle_frames", 4)
	var run_n: int     = _type.get("run_frames", 4)
	var idle_fmt: String = _type.get("idle_fmt", SPRITES_PATH + prefix + "_idle_anim_f%d.png")
	var run_fmt: String  = _type.get("run_fmt",  SPRITES_PATH + prefix + "_run_anim_f%d.png")
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", idle_fmt, idle_n, true,  8.0)
	_add_anim(frames, "run",  run_fmt,  run_n, false, 16.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -8)
	$AnimatedSprite2D.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i: int in count:
		frames.add_frame(anim_name, load(path_fmt % i))

func _setup_zzz() -> void:
	_zzz_label = Label.new()
	_zzz_label.text = "z z z"
	_zzz_label.add_theme_font_size_override("font_size", 7)
	_zzz_label.position = Vector2(-9, -22)
	_zzz_label.z_index = 4
	_zzz_label.modulate.a = 0.0
	_zzz_label.visible = false
	add_child(_zzz_label)

func _start_zzz() -> void:
	if not is_instance_valid(_zzz_label):
		return
	_zzz_label.visible = true
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
	_zzz_tween = create_tween().set_loops()
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 1.0, 1.0)
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 0.3, 1.0)

func _stop_zzz() -> void:
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
		_zzz_tween = null
	if is_instance_valid(_zzz_label):
		_zzz_label.visible = false

func _wake_up() -> void:
	behavior = Behavior.CHASING
	_stop_zzz()

func take_turn() -> void:
	if _dungeon_floor == null:
		return
	if slowed_turns > 0:
		slowed_turns -= 1
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return
	var player: Player = _dungeon_floor.get_player()
	if player == null:
		return

	var dx: int = player.grid_pos.x - grid_pos.x
	var dy: int = player.grid_pos.y - grid_pos.y
	var dist_sq: int = dx * dx + dy * dy
	var can_see: bool = dist_sq <= FOV_RADIUS * FOV_RADIUS \
		and _dungeon_floor.has_line_of_sight(grid_pos, player.grid_pos)

	match behavior:
		Behavior.SLEEPING:
			if can_see or dist_sq <= WAKE_RADIUS_SQ:
				_wake_up()
				last_known_player_pos = player.grid_pos
				await _act_toward(player)
			else:
				# Spend the turn doing nothing — keeps turn rhythm consistent
				await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

		Behavior.STATIONARY:
			if can_see:
				last_known_player_pos = player.grid_pos
				behavior = Behavior.CHASING
				await _act_toward(player)
			else:
				await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

		Behavior.ROAMING:
			if can_see:
				last_known_player_pos = player.grid_pos
				behavior = Behavior.CHASING
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				await _act_toward(player)
			else:
				await _do_roam_walk()

		Behavior.CHASING:
			if can_see:
				last_known_player_pos = player.grid_pos
				# Record the direction toward the player so we can search that way if we lose sight
				_search_heading = Vector2i(sign(dx), sign(dy))
			await _act_toward(player)
			if not is_instance_valid(self) or stats.is_dead():
				return
			# Reached last known position without spotting player — enter search mode
			if not can_see and last_known_player_pos != Vector2i(-1, -1) and grid_pos == last_known_player_pos:
				behavior = Behavior.SEARCHING
				_search_turns_remaining = 7
				_search_target = last_known_player_pos + _search_heading * 5
				_search_path.clear()
				last_known_player_pos = Vector2i(-1, -1)

		Behavior.SEARCHING:
			if can_see:
				# Found the player — resume chasing
				behavior = Behavior.CHASING
				last_known_player_pos = player.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
				await _act_toward(player)
			elif _search_turns_remaining > 0:
				_search_turns_remaining -= 1
				if _search_path.is_empty() or grid_pos == _search_target:
					_search_path = _bfs_to(_search_target)
				if not _search_path.is_empty():
					var next: Vector2i = _search_path[0]
					_search_path = _search_path.slice(1)
					await _move_step(next - grid_pos, next)
				else:
					await _do_random_step()
			else:
				behavior = Behavior.ROAMING
				_search_target = Vector2i(-1, -1)
				_search_path.clear()
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)

# Attack if adjacent to player; otherwise step toward last known / player position.
func _act_toward(player: Player) -> void:
	var dx: int = player.grid_pos.x - grid_pos.x
	var dy: int = player.grid_pos.y - grid_pos.y
	if maxi(abs(dx), abs(dy)) == 1:
		_attack_player(player)
		return

	var target: Vector2i = last_known_player_pos if last_known_player_pos != Vector2i(-1, -1) else player.grid_pos
	var tdx: int = target.x - grid_pos.x
	var tdy: int = target.y - grid_pos.y

	for step: Vector2i in _preferred_steps(tdx, tdy):
		var next_pos: Vector2i = grid_pos + step
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)
			return

	# Greedy failed — BFS fallback to navigate around obstacles
	var bfs_path: Array[Vector2i] = _bfs_to(target)
	if not bfs_path.is_empty():
		var next_pos: Vector2i = bfs_path[0]
		var step: Vector2i = next_pos - grid_pos
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)

func _pick_roam_target() -> Vector2i:
	var centers: Array[Vector2i] = _dungeon_floor.get_room_centers()
	centers.shuffle()
	for c: Vector2i in centers:
		if maxi(absi(c.x - grid_pos.x), absi(c.y - grid_pos.y)) < 4:
			continue
		if _dungeon_floor.is_walkable_for_enemy(c):
			return c
	return Vector2i(-1, -1)

func _do_roam_walk() -> void:
	if _roam_path.is_empty() or grid_pos == _roam_target:
		_roam_target = _pick_roam_target()
		if _roam_target == Vector2i(-1, -1):
			await _do_random_step()
			return
		_roam_path = _bfs_to(_roam_target)
		if _roam_path.is_empty():
			_roam_target = Vector2i(-1, -1)
			await _do_random_step()
			return
	var next_pos: Vector2i = _roam_path[0]
	if not _dungeon_floor.is_walkable_for_enemy(next_pos):
		_roam_path.clear()
		_roam_target = Vector2i(-1, -1)
		await _do_random_step()
		return
	_roam_path.remove_at(0)
	if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
		_dungeon_floor.open_door(next_pos)
	await _move_step(next_pos - grid_pos, next_pos)

func _do_random_step() -> void:
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	dirs.shuffle()
	for dir: Vector2i in dirs:
		var target: Vector2i = grid_pos + dir
		if _dungeon_floor.has_door_at(target):
			continue
		if _dungeon_floor.is_walkable_for_enemy(target):
			await _move_step(dir, target)
			return
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

func _move_step(step: Vector2i, next_pos: Vector2i) -> void:
	var prev_pos: Vector2i = grid_pos
	var stepping_through_door: bool = _dungeon_floor.has_door_at(next_pos)
	$AnimatedSprite2D.flip_h = step.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(next_pos, 0.04 if TurnManager.fast_mode else 0.08)
	if not is_instance_valid(self):
		return
	$AnimatedSprite2D.play("idle")
	if stepping_through_door:
		just_crossed_door = true
	if _dungeon_floor.has_door_at(prev_pos):
		_dungeon_floor.close_door(prev_pos)
	var tile_type: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	if tile_type == DungeonData.TileType.WATER or tile_type == DungeonData.TileType.MUD:
		slowed_turns = maxi(slowed_turns, 1)
	if tile_type == DungeonData.TileType.GRASS:
		_dungeon_floor.destroy_grass(grid_pos)
	var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
	if not trap.is_empty():
		await _dungeon_floor.trigger_trap(grid_pos, self)

# Returns movement direction candidates in priority order (diagonal first, then axes).
func _preferred_steps(dx: int, dy: int) -> Array[Vector2i]:
	var sx: int = sign(dx)
	var sy: int = sign(dy)
	var steps: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		steps.append(Vector2i(sx, sy))
	if abs(dx) >= abs(dy):
		if sx != 0: steps.append(Vector2i(sx, 0))
		if sy != 0: steps.append(Vector2i(0, sy))
	else:
		if sy != 0: steps.append(Vector2i(0, sy))
		if sx != 0: steps.append(Vector2i(sx, 0))
	return steps

func _bfs_to(target: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [grid_pos]
	var came: Dictionary = {grid_pos: grid_pos}
	var limit: int = 0
	while not queue.is_empty() and limit < 200:
		limit += 1
		var cur: Vector2i = queue.pop_front()
		if cur == target:
			var path: Array[Vector2i] = []
			while cur != grid_pos:
				path.push_front(cur)
				cur = came[cur]
			return path
		for d: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var nxt: Vector2i = cur + d
			if not came.has(nxt) and (_dungeon_floor.is_walkable_for_enemy(nxt) or nxt == target):
				came[nxt] = cur
				queue.append(nxt)
	return []

func _attack_player(_player: Player) -> void:
	if GameState.invincible:
		GameState.game_log("[color=tomato]%s[/color] strikes you — [color=gray]blocked (invincible)[/color]" % display_name)
		return
	# D&D attack roll: d20 + floor-scaled bonus vs player AC
	var attack_bonus: int = GameState.current_floor / 3
	var die: int = randi_range(1, 20)
	var roll: int = die + attack_bonus
	var player_ac: int = GameState.player_stats.armor_class
	var is_crit: bool = die == 20
	var hit_meta: String = "ehit:die=%d,bonus=%d,total=%d,ac=%d,crit=%d" % [die, attack_bonus, roll, player_ac, 1 if is_crit else 0]
	if not is_crit and roll < player_ac:
		GameState.game_log("[color=tomato]%s[/color] [url=%s]misses[/url]!" % [display_name, hit_meta])
		return
	var dmg_roll: int = stats.roll_damage()
	var dmg: int = dmg_roll * (2 if is_crit else 1)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(0.95, 0.15, 0.15))
		GameState.screen_shake.emit(7.0)
		AudioManager.play("crit")
	else:
		AudioManager.play("player_hurt")
	var actual: int = GameState.player_stats.take_damage(dmg)
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(_player.position, actual, true)
	var dmg_meta: String = "edmg:roll=%d,min=%d,max=%d,crit=%d,final=%d" % [dmg_roll, stats.min_damage, stats.max_damage, 1 if is_crit else 0, actual]
	if is_crit:
		GameState.game_log("[color=tomato]%s[/color] [url=%s][color=red]CRITICAL HIT![/color][/url] for [url=%s][color=yellow]%d[/color][/url] dmg." % [display_name, hit_meta, dmg_meta, actual])
	else:
		GameState.game_log("[color=tomato]%s[/color] [url=%s]hits[/url] you for [url=%s][color=yellow]%d[/color][/url] dmg." % [display_name, hit_meta, dmg_meta, actual])
	# Orc Shaman applies poison on hit
	if display_name == "Orc Shaman" and GameState.player_stats.poison_turns < 3:
		GameState.player_stats.poison_turns = 3
		GameState.player_status_changed.emit()
		GameState.game_log("[color=lime]You are poisoned! (3 turns)[/color]")
	GameState.check_player_death()
