class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"

var _dungeon_floor: Node  # set by DungeonFloor after spawning

var _queued_path: Array[Vector2i] = []
var _path_executing: bool = false

var _regen_counter: int = 0
const REGEN_TURNS: int = 6

func _ready() -> void:
	stats = GameState.player_stats
	z_index = 3  # render above fog overlay
	_setup_animations()
	_setup_hp_bar()
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	TurnManager.player_turn_started.connect(_on_turn_started)

func _on_player_hp_changed(_c: int, _m: int) -> void:
	update_hp_bar()

func _on_turn_started() -> void:
	_regen_counter += 1
	if _regen_counter < REGEN_TURNS:
		return
	_regen_counter = 0
	var s: Stats = GameState.player_stats
	if s.current_hp < s.max_hp and not GameState.is_game_over:
		GameState.heal(1)
		GameState.log("[color=green]You recover 1 HP.[/color]")

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", KNIGHT_PATH + "knight_m_idle_anim_f%d.png", 4, true,  8.0)
	_add_anim(frames, "run",  KNIGHT_PATH + "knight_m_run_anim_f%d.png",  4, false, 16.0)
	_add_anim(frames, "hit",  KNIGHT_PATH + "knight_m_hit_anim_f%d.png",  1, false, 8.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -8)
	$AnimatedSprite2D.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i in count:
		frames.add_frame(anim_name, load(path_fmt % i))

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		_queued_path.clear()
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			return
		match key.physical_keycode:
			KEY_UP, KEY_W:         _try_move(Vector2i(0, -1))
			KEY_DOWN, KEY_S:       _try_move(Vector2i(0, 1))
			KEY_LEFT, KEY_A:       _try_move(Vector2i(-1, 0))
			KEY_RIGHT, KEY_D:      _try_move(Vector2i(1, 0))
			KEY_SPACE, KEY_PERIOD: _wait_action()

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
		var path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, clicked)
		if path.is_empty():
			return
		_queued_path = path
		if not _path_executing:
			_execute_queued_path()

func _execute_queued_path() -> void:
	_path_executing = true
	TurnManager.fast_mode = true
	while not _queued_path.is_empty():
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started
		var next: Vector2i = _queued_path[0]
		_queued_path.remove_at(0)
		var dir: Vector2i = next - grid_pos

		var enemy_there: Enemy = _dungeon_floor.get_enemy_at(next)
		if enemy_there != null:
			_bump_attack(enemy_there, dir)
			if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
				await TurnManager.player_turn_started
			break

		if not _dungeon_floor.is_walkable(next):
			_queued_path.clear()
			break

		var is_stairs: bool = _dungeon_floor.get_tile_type(next) == DungeonData.TileType.STAIRS_DOWN

		TurnManager.begin_player_action()
		$AnimatedSprite2D.flip_h = dir.x < 0
		$AnimatedSprite2D.play("run")
		# Start player move and enemy turns simultaneously
		move_to(next, 0.05)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
		await move_completed
		$AnimatedSprite2D.play("idle")

		if is_stairs:
			_dungeon_floor.on_player_reached_stairs.call_deferred()
			TurnManager.fast_mode = false
			_path_executing = false
			return

		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
			await TurnManager.player_turn_started
	TurnManager.fast_mode = false
	_path_executing = false

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	var target: Vector2i = grid_pos + dir

	var enemy: Enemy = _dungeon_floor.get_enemy_at(target)
	if enemy != null:
		_bump_attack(enemy, dir)
		return

	if not _dungeon_floor.is_walkable(target):
		return

	var is_stairs: bool = _dungeon_floor.get_tile_type(target) == DungeonData.TileType.STAIRS_DOWN

	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(target)
	$AnimatedSprite2D.play("idle")
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()
	if is_stairs:
		_dungeon_floor.on_player_reached_stairs.call_deferred()

func _bump_attack(enemy: Enemy, dir: Vector2i) -> void:
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")
	var dmg: int = stats.roll_damage()
	var actual: int = enemy.stats.take_damage(dmg)
	enemy.update_hp_bar()
	GameState.log("You strike [color=orange]%s[/color] for [color=yellow]%d[/color] dmg." % [enemy.display_name, actual])
	if enemy.stats.is_dead():
		GameState.log("[color=orange]%s[/color] [color=gray]dies.[/color]" % enemy.display_name)
		_dungeon_floor.remove_enemy(enemy)
		enemy.die()
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _wait_action() -> void:
	TurnManager.begin_player_action()
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()
