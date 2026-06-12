class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"

var _dungeon_floor: Node  # set by DungeonFloor after spawning

func _ready() -> void:
	stats = GameState.player_stats
	z_index = 3  # render above fog overlay
	_setup_animations()

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", KNIGHT_PATH + "knight_m_idle_anim_f%d.png", 4, true,  8.0)
	_add_anim(frames, "run",  KNIGHT_PATH + "knight_m_run_anim_f%d.png",  4, false, 16.0)
	_add_anim(frames, "hit",  KNIGHT_PATH + "knight_m_hit_anim_f%d.png",  1, false, 8.0)
	$AnimatedSprite2D.sprite_frames = frames
	$AnimatedSprite2D.offset = Vector2(0, -4)
	$AnimatedSprite2D.play("idle")

func _add_anim(frames: SpriteFrames, anim_name: String, path_fmt: String,
			   count: int, loop: bool, fps: float) -> void:
	frames.add_animation(anim_name)
	frames.set_animation_loop(anim_name, loop)
	frames.set_animation_speed(anim_name, fps)
	for i in count:
		frames.add_frame(anim_name, load(path_fmt % i))

func _unhandled_input(event: InputEvent) -> void:
	if not event is InputEventKey:
		return
	if not (event as InputEventKey).pressed or (event as InputEventKey).echo:
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
		return

	match (event as InputEventKey).physical_keycode:
		KEY_UP, KEY_W:
			_try_move(Vector2i(0, -1))
		KEY_DOWN, KEY_S:
			_try_move(Vector2i(0, 1))
		KEY_LEFT, KEY_A:
			_try_move(Vector2i(-1, 0))
		KEY_RIGHT, KEY_D:
			_try_move(Vector2i(1, 0))
		KEY_SPACE, KEY_PERIOD:
			_wait_action()

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	var target: Vector2i = grid_pos + dir

	# Bump into enemy = attack
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
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _wait_action() -> void:
	TurnManager.begin_player_action()
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()
