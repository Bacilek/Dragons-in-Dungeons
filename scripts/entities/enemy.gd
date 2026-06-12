class_name Enemy
extends Entity

const SPRITES_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"
const FOV_RADIUS: int = 6

var _dungeon_floor: Node
var display_name: String = "Enemy"
var exp_reward: int = 5
var _type: Dictionary = {}

func configure(type_data: Dictionary) -> void:
	_type = type_data
	display_name = type_data.get("display_name", "Enemy")

func _ready() -> void:
	stats = Stats.new()
	_apply_stats()
	z_index = 1
	_setup_animations()
	_setup_hp_bar()

func _apply_stats() -> void:
	var f: int = GameState.current_floor
	stats.max_hp     = _type.get("hp", 8)      + (f - 1) * _type.get("hp_per_floor", 2)
	stats.min_damage = _type.get("dmg_min", 1) + (f - 1) / 3
	stats.max_damage = _type.get("dmg_max", 4) + (f - 1) / 2
	stats.armor      = _type.get("armor", 0)   + f / 5
	stats.current_hp = stats.max_hp
	exp_reward       = _type.get("exp", 5)

func _setup_animations() -> void:
	var prefix: String = _type.get("sprite", "orc_warrior")
	var idle_n: int    = _type.get("idle_frames", 4)
	var run_n: int     = _type.get("run_frames", 4)
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", SPRITES_PATH + prefix + "_idle_anim_f%d.png", idle_n, true,  8.0)
	_add_anim(frames, "run",  SPRITES_PATH + prefix + "_run_anim_f%d.png",  run_n, false, 16.0)
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
		if maxi(abs(dx), abs(dy)) == 1:
			_attack_player(player)
			return
		var step: Vector2i = _chase_step(dx, dy)
		if step != Vector2i.ZERO and _dungeon_floor.is_walkable_for_enemy(grid_pos + step):
			$AnimatedSprite2D.flip_h = step.x < 0
			$AnimatedSprite2D.play("run")
			await move_to(grid_pos + step, 0.04 if TurnManager.fast_mode else 0.08)
			$AnimatedSprite2D.play("idle")
			return

	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
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
	var sx: int = sign(dx)
	var sy: int = sign(dy)
	# Try diagonal first
	if sx != 0 and sy != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(sx, sy)):
		return Vector2i(sx, sy)
	# Fall back to primary axis
	if abs(dx) >= abs(dy):
		if sx != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(sx, 0)):
			return Vector2i(sx, 0)
		if sy != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(0, sy)):
			return Vector2i(0, sy)
	else:
		if sy != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(0, sy)):
			return Vector2i(0, sy)
		if sx != 0 and _dungeon_floor.is_walkable_for_enemy(grid_pos + Vector2i(sx, 0)):
			return Vector2i(sx, 0)
	return Vector2i.ZERO

func _attack_player(_player: Player) -> void:
	var dmg: int = stats.roll_damage()
	var actual: int = GameState.player_stats.take_damage(dmg)
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.log("[color=tomato]%s[/color] strikes you for [color=yellow]%d[/color] dmg." % [display_name, actual])
	GameState.check_player_death()
