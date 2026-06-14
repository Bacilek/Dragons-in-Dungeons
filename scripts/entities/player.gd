class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/characters/"
const SWORD_SPRITE := "res://sprites/weapons/weapon_anime_sword.png"

var _dungeon_floor: Node

var _queued_path: Array[Vector2i] = []
var _path_executing: bool = false
var _last_move_dir := Vector2i.ZERO
var _target_enemy: Enemy = null

var _prev_dir: Vector2i = Vector2i.ZERO  # direction held in the previous WAITING_FOR_INPUT frame
var _interrupted: bool = false           # set when enemy seen mid-hold; cleared only on key release

var _regen_counter: int = 0
const REGEN_TURNS: int = 6

func _ready() -> void:
	stats = GameState.player_stats
	z_index = 3
	_setup_animations()
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_action_requested.connect(_on_action_requested)
	GameState.player_died.connect(_on_player_died)
	GameState.class_chosen.connect(_on_class_chosen)
	TurnManager.player_turn_started.connect(_on_turn_started)

func _on_player_died() -> void:
	visible = false
	_queued_path.clear()
	_path_executing = false

func _on_class_chosen(_cls: Stats.CharacterClass) -> void:
	_setup_animations()

func _on_player_hp_changed(_c: int, _m: int) -> void:
	update_hp_bar()

func _on_turn_started() -> void:
	GameState.deplete_hunger()
	var status_dmg: int = GameState.player_stats.tick_status()
	if status_dmg > 0:
		GameState.take_damage_raw(status_dmg)
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(position, status_dmg, true)
		GameState.player_status_changed.emit()
	_regen_counter += 1
	if _regen_counter < REGEN_TURNS:
		return
	_regen_counter = 0
	var s: Stats = GameState.player_stats
	if s.current_hp < s.max_hp and not GameState.is_game_over:
		GameState.heal(1)

func _setup_animations() -> void:
	var char_name: String
	match GameState.player_stats.character_class:
		Stats.CharacterClass.ROGUE:   char_name = "elf_m"
		Stats.CharacterClass.WIZARD:  char_name = "wizzard_m"
		Stats.CharacterClass.CLERIC:  char_name = "dwarf_m"
		_:                            char_name = "knight_m"   # FIGHTER default
	var base: String = KNIGHT_PATH + char_name + "_"
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", base + "idle_anim_f%d.png", 4, true,  8.0)
	_add_anim(frames, "run",  base + "run_anim_f%d.png",  4, false, 16.0)
	_add_anim(frames, "hit",  base + "hit_anim_f%d.png",  1, false, 8.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -11)
	$AnimatedSprite2D.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i: int in count:
		frames.add_frame(anim_name, load(path_fmt % i))

# Cardinal + diagonal movement via per-frame key sampling so two held cardinals = diagonal
func _process(_delta: float) -> void:
	if GameState.is_game_over or GameState.inventory_open or not GameState.class_selected:
		_prev_dir = Vector2i.ZERO
		_last_move_dir = Vector2i.ZERO
		_interrupted = false
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		_last_move_dir = Vector2i.ZERO
		return
	var dx: int = 0
	var dy: int = 0
	if Input.is_physical_key_pressed(KEY_UP)    or Input.is_physical_key_pressed(KEY_W) or Input.is_physical_key_pressed(KEY_KP_8): dy -= 1
	if Input.is_physical_key_pressed(KEY_DOWN)  or Input.is_physical_key_pressed(KEY_S) or Input.is_physical_key_pressed(KEY_KP_2): dy += 1
	if Input.is_physical_key_pressed(KEY_LEFT)  or Input.is_physical_key_pressed(KEY_A) or Input.is_physical_key_pressed(KEY_KP_4): dx -= 1
	if Input.is_physical_key_pressed(KEY_RIGHT) or Input.is_physical_key_pressed(KEY_D) or Input.is_physical_key_pressed(KEY_KP_6): dx += 1
	var dir := Vector2i(dx, dy)
	if dir == Vector2i.ZERO:
		_prev_dir = Vector2i.ZERO
		_last_move_dir = Vector2i.ZERO
		_interrupted = false
		return
	if _prev_dir == Vector2i.ZERO:
		# Fresh key press — always allow, clear any old interrupt
		_interrupted = false
	elif _interrupted:
		# Key still physically held after interrupt — block until finger lifted
		_prev_dir = dir
		return
	elif _dungeon_floor != null and not _dungeon_floor.get_visible_enemies().is_empty():
		# Continuing hold, enemy in FOV — interrupt
		_interrupted = true
		_prev_dir = dir
		return
	_prev_dir = dir
	if dir == _last_move_dir:
		return
	_last_move_dir = dir
	_queued_path.clear()
	_try_move(dir)

func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_game_over or not GameState.class_selected:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		# I key toggles inventory regardless of turn phase
		if key.physical_keycode == KEY_I:
			GameState.inventory_toggle.emit()
			return
		if GameState.inventory_open:
			return
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
			return
		_queued_path.clear()
		match key.physical_keycode:
			KEY_Q, KEY_KP_7: _try_move(Vector2i(-1, -1))
			KEY_E, KEY_KP_9: _try_move(Vector2i(1, -1))
			KEY_Z, KEY_KP_1: _try_move(Vector2i(-1, 1))
			KEY_C, KEY_KP_3: _try_move(Vector2i(1, 1))
			KEY_SPACE, KEY_PERIOD, KEY_KP_5: _wait_action()

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index != MOUSE_BUTTON_LEFT or not mb.pressed:
			return
		if _dungeon_floor == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var clicked: Vector2i = Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))
		if clicked == grid_pos:
			return
		# Click on open door while adjacent → close it
		if _dungeon_floor.has_door_at(clicked) and _dungeon_floor.is_door_open(clicked):
			var diff: Vector2i = clicked - grid_pos
			if maxi(abs(diff.x), abs(diff.y)) <= 1:
				TurnManager.begin_player_action()
				_dungeon_floor.close_door(clicked)
				_dungeon_floor.update_fog(grid_pos)
				TurnManager.on_player_action_complete()
				return
		# Clicking on an enemy → chase and attack
		var enemy_clicked: Enemy = _dungeon_floor.get_enemy_at(clicked)
		if enemy_clicked != null:
			_target_enemy = enemy_clicked
			_queued_path.clear()
			if not _path_executing:
				_execute_queued_path()
			return
		# Regular floor click → path walk
		_target_enemy = null
		var path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, clicked)
		if path.is_empty():
			return
		_queued_path = path
		if not _path_executing:
			_execute_queued_path()

func _execute_queued_path() -> void:
	_path_executing = true
	TurnManager.fast_mode = true
	var fov_snapshot: Array[Enemy] = _dungeon_floor.get_visible_enemies()

	while true:
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started

		# ── Enemy-chase mode: target was set by clicking on an enemy ──────
		if _target_enemy != null:
			if not is_instance_valid(_target_enemy) or _target_enemy.stats.is_dead():
				_target_enemy = null
				break

			var chase_path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, _target_enemy.grid_pos)
			if chase_path.is_empty():
				_target_enemy = null
				break

			if chase_path.size() == 1:
				# Adjacent — attack
				var atk_dir: Vector2i = _target_enemy.grid_pos - grid_pos
				_bump_attack(_target_enemy, atk_dir)
				_target_enemy = null
				if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
					await TurnManager.player_turn_started
				break

			# One step closer
			var next: Vector2i = chase_path[0]
			var dir: Vector2i = next - grid_pos
			TurnManager.begin_player_action()
			$AnimatedSprite2D.flip_h = dir.x < 0
			$AnimatedSprite2D.play("run")
			move_to(next, 0.08)
			if _dungeon_floor != null:
				_dungeon_floor.update_fog(grid_pos)
			TurnManager.on_player_action_complete()
			await move_completed
			$AnimatedSprite2D.play("idle")

			if _dungeon_floor != null:
				if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
					_dungeon_floor.destroy_grass(grid_pos)
				_check_pickup()
				var trap_c: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
				if not trap_c.is_empty():
					await _dungeon_floor.trigger_trap(grid_pos, self)
					_target_enemy = null
					break

			if _has_new_enemy_in_fov(fov_snapshot):
				_target_enemy = null
				break
			continue

		# ── Regular queued-path mode ──────────────────────────────────────
		if _queued_path.is_empty():
			break

		var next: Vector2i = _queued_path[0]
		_queued_path.remove_at(0)
		var dir: Vector2i = next - grid_pos

		var enemy_there: Enemy = _dungeon_floor.get_enemy_at(next)
		if enemy_there != null:
			_bump_attack(enemy_there, dir)
			if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
				await TurnManager.player_turn_started
			break

		# Open closed door for free — movement continues in the same turn
		if _dungeon_floor.has_door_at(next) and not _dungeon_floor.is_door_open(next):
			_dungeon_floor.open_door(next)

		if not _dungeon_floor.is_walkable(next):
			_queued_path.clear()
			break

		var is_stairs: bool = _dungeon_floor.get_tile_type(next) == DungeonData.TileType.STAIRS_DOWN

		TurnManager.begin_player_action()
		$AnimatedSprite2D.flip_h = dir.x < 0
		$AnimatedSprite2D.play("run")
		move_to(next, 0.08)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
		await move_completed
		$AnimatedSprite2D.play("idle")

		if _dungeon_floor != null:
			if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
				_dungeon_floor.destroy_grass(grid_pos)
				_dungeon_floor.update_fog(grid_pos)
			_check_pickup()
			var trap_p: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
			if not trap_p.is_empty():
				await _dungeon_floor.trigger_trap(grid_pos, self)
				_queued_path.clear()
				break

		if is_stairs:
			_dungeon_floor.on_player_reached_stairs.call_deferred()
			TurnManager.fast_mode = false
			_path_executing = false
			return

		if _has_new_enemy_in_fov(fov_snapshot):
			_queued_path.clear()
			break

		# Difficult terrain: water/mud costs 2 turns — stop queued path and waste a turn
		var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
		if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD:
			_queued_path.clear()
			if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
				await TurnManager.player_turn_started
			TurnManager.begin_player_action()
			_dungeon_floor.update_fog(grid_pos)
			TurnManager.on_player_action_complete()
			break

		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started

	TurnManager.fast_mode = false
	_path_executing = false

func _has_new_enemy_in_fov(snapshot: Array[Enemy]) -> bool:
	if _dungeon_floor == null:
		return false
	for e: Enemy in _dungeon_floor.get_visible_enemies():
		if e not in snapshot:
			return true
	return false

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	var target: Vector2i = grid_pos + dir

	var enemy: Enemy = _dungeon_floor.get_enemy_at(target)
	if enemy != null:
		_bump_attack(enemy, dir)
		return

	# Open closed door for free — movement continues in the same turn
	if _dungeon_floor.has_door_at(target) and not _dungeon_floor.is_door_open(target):
		_dungeon_floor.open_door(target)

	if not _dungeon_floor.is_walkable(target):
		return

	var is_stairs: bool = _dungeon_floor.get_tile_type(target) == DungeonData.TileType.STAIRS_DOWN

	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(target)
	$AnimatedSprite2D.play("idle")
	if _dungeon_floor != null:
		# Destroy grass before fog update so our own tile doesn't block sight
		if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
			_dungeon_floor.destroy_grass(grid_pos)
		_dungeon_floor.update_fog(grid_pos)
		_check_pickup()
		var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
		if not trap.is_empty():
			await _dungeon_floor.trigger_trap(grid_pos, self)  # push trap still awaits; others return instantly
	TurnManager.on_player_action_complete()
	if is_stairs:
		_dungeon_floor.on_player_reached_stairs.call_deferred()
		return
	# Difficult terrain: water/mud costs 2 turns per step
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD:
		await TurnManager.player_turn_started
		TurnManager.begin_player_action()
		_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()

func _bump_attack(enemy: Enemy, dir: Vector2i) -> void:
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")

	_show_sword_slash(dir)
	_flash_hit(enemy)

	var dmg: int = stats.roll_damage()
	var actual: int = enemy.stats.take_damage(dmg)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)
	GameState.game_log("You strike [color=orange]%s[/color] for [color=yellow]%d[/color] dmg." % [enemy.display_name, actual])
	if enemy.stats.is_dead():
		GameState.game_log("[color=orange]%s[/color] [color=gray]dies.[/color]" % enemy.display_name)
		GameState.gain_exp(enemy.exp_reward)
		var was_boss: bool = enemy.is_boss
		var boss_pos: Vector2i = enemy.grid_pos
		_dungeon_floor.remove_enemy(enemy)
		enemy.die()
		if was_boss:
			_dungeon_floor.drop_boss_loot(boss_pos)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _show_sword_slash(dir: Vector2i) -> void:
	var attack_angle := atan2(float(dir.y), float(dir.x))

	# Arc width and speed scale with weapon tier (bonus_damage)
	var bonus: int = 0
	var weapon_path: String = SWORD_SPRITE
	if GameState.equipped_weapon != null:
		bonus = GameState.equipped_weapon.bonus_damage
		if GameState.equipped_weapon.icon_path != "":
			weapon_path = GameState.equipped_weapon.icon_path

	var start_off: float
	var end_off: float
	var dur: float
	match bonus:
		1:   start_off = 55.0;  end_off = 38.0;  dur = 0.14
		2:   start_off = 75.0;  end_off = 50.0;  dur = 0.18
		3:   start_off = 88.0;  end_off = 60.0;  dur = 0.20
		4:   start_off = 95.0;  end_off = 68.0;  dur = 0.22
		5:   start_off = 105.0; end_off = 78.0;  dur = 0.26
		_:   start_off = 60.0;  end_off = 42.0;  dur = 0.15

	var pivot := Node2D.new()
	pivot.position = _tile_center(grid_pos)
	pivot.z_index = 5
	pivot.rotation = attack_angle - deg_to_rad(start_off)

	var slash := Sprite2D.new()
	slash.texture = load(weapon_path)
	slash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slash.position = Vector2(12.0, 0.0)
	# All 0x72 weapon sprites point upper-right (~45°); rotate to point right.
	slash.rotation = -PI * 0.25

	pivot.add_child(slash)
	get_parent().add_child(pivot)

	var tween := pivot.create_tween()
	tween.tween_property(pivot, "rotation", attack_angle + deg_to_rad(end_off), dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(slash, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.6)
	tween.tween_callback(pivot.queue_free)

func _flash_hit(target: Entity) -> void:
	if not is_instance_valid(target):
		return
	var tween := target.create_tween()
	tween.tween_property(target, "modulate", Color(1.8, 0.3, 0.3), 0.05)
	tween.tween_property(target, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func _on_action_requested(action_name: String) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	match action_name:
		"wait":   _wait_action()
		"search": _search_action()

func _check_pickup() -> void:
	if _dungeon_floor == null:
		return
	var item: Item = _dungeon_floor.get_item_at(grid_pos)
	if item == null:
		return
	_dungeon_floor.remove_floor_item(grid_pos)
	var is_first_weapon: bool = item.item_type == Item.Type.WEAPON and GameState.equipped_weapon == null
	GameState.add_item(item)
	if is_first_weapon:
		GameState.equip(item)
		GameState.game_log("[color=cyan]You pick up [b]%s[/b] and equip it.[/color]" % item.item_name)
	else:
		GameState.game_log("[color=cyan]You pick up [b]%s[/b].[/color]" % item.item_name)

func _wait_action() -> void:
	TurnManager.begin_player_action()
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _search_action() -> void:
	if _dungeon_floor == null:
		return
	TurnManager.begin_player_action()
	var found: int = _dungeon_floor.search_around(grid_pos)
	if found > 0:
		GameState.game_log("[color=cyan]You search the area and reveal %d trap(s)![/color]" % found)
	else:
		GameState.game_log("[color=gray]You search the area. Nothing found.[/color]")
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()
