class_name Enemy
extends Entity

const ORC_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"
const FOV_RADIUS: int = 6

var _dungeon_floor: Node  # set by DungeonFloor after spawning
var display_name: String = "Orc Warrior"

func _ready() -> void:
	stats = Stats.new()
	_apply_floor_scaling()
	z_index = 1
	_setup_animations()
	_setup_hp_bar()

func _apply_floor_scaling() -> void:
	var f: int = GameState.current_floor
	stats.max_hp      = 8  + (f - 1) * 3
	stats.min_damage  = 1  + (f - 1) / 2
	stats.max_damage  = 4  + (f - 1)
	stats.armor       = f  / 3
	stats.current_hp  = stats.max_hp

func _setup_animations() -> void:
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", ORC_PATH + "orc_warrior_idle_anim_f%d.png", 4, true,  8.0)
	_add_anim(frames, "run",  ORC_PATH + "orc_warrior_run_anim_f%d.png",  4, false, 16.0)
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

func take_turn() -> void:
	if _dungeon_floor == null:
		return
	var player: Player = _dungeon_floor.get_player()
	if player == null:
		return

	var dx: int = player.grid_pos.x - grid_pos.x
	var dy: int = player.grid_pos.y - grid_pos.y
	var dist_sq: int = dx * dx + dy * dy

	if dist_sq <= FOV_RADIUS * FOV_RADIUS:
		# Adjacent = attack
		if dist_sq <= 2:  # chebyshev dist 1 includes diagonals; use manhattan
			var manhattan: int = abs(dx) + abs(dy)
			if manhattan == 1:
				_attack_player(player)
				return
		# Chase: step toward player
		var step: Vector2i = _chase_step(dx, dy)
		if step != Vector2i.ZERO and _dungeon_floor.is_walkable_for_enemy(grid_pos + step):
			$AnimatedSprite2D.flip_h = step.x < 0
			$AnimatedSprite2D.play("run")
			await move_to(grid_pos + step, 0.04 if TurnManager.fast_mode else 0.08)
			$AnimatedSprite2D.play("idle")
			return

	# Random wander
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0)]
	dirs.shuffle()
	for dir: Vector2i in dirs:
		var target: Vector2i = grid_pos + dir
		if _dungeon_floor.is_walkable_for_enemy(target):
			$AnimatedSprite2D.flip_h = dir.x < 0
			$AnimatedSprite2D.play("run")
			await move_to(target, 0.04 if TurnManager.fast_mode else 0.08)
			$AnimatedSprite2D.play("idle")
			return

func _chase_step(dx: int, dy: int) -> Vector2i:
	# Try primary axis (larger delta first), then secondary
	var step_x: int = sign(dx)
	var step_y: int = sign(dy)
	if abs(dx) >= abs(dy):
		if step_x != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(step_x, 0)):
			return Vector2i(step_x, 0)
		if step_y != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(0, step_y)):
			return Vector2i(0, step_y)
	else:
		if step_y != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(0, step_y)):
			return Vector2i(0, step_y)
		if step_x != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(step_x, 0)):
			return Vector2i(step_x, 0)
	return Vector2i.ZERO

func _attack_player(_player: Player) -> void:
	var dmg: int = stats.roll_damage()
	var actual: int = GameState.player_stats.take_damage(dmg)
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.log("[color=tomato]%s[/color] strikes you for [color=yellow]%d[/color] dmg." % [display_name, actual])
	GameState.check_player_death()
