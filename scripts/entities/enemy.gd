class_name Enemy
extends Entity

const ORC_PATH := "res://sprites/0x72_DungeonTilesetII_v1.7/frames/"

var _dungeon_floor: Node  # set by DungeonFloor after spawning

func _ready() -> void:
	stats = Stats.new()
	stats.character_class = Stats.CharacterClass.FIGHTER
	stats.strength = 12
	stats.constitution = 14
	stats.dexterity = 8
	stats.apply_class_defaults()
	stats.max_hp = 8 + stats.con_modifier()
	stats.current_hp = stats.max_hp
	z_index = 1
	_setup_animations()

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
	var dirs: Array[Vector2i] = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	dirs.shuffle()
	for dir: Vector2i in dirs:
		var target: Vector2i = grid_pos + dir
		if _dungeon_floor.is_walkable_for_enemy(target):
			$AnimatedSprite2D.flip_h = dir.x < 0
			$AnimatedSprite2D.play("run")
			await move_to(target)
			$AnimatedSprite2D.play("idle")
			return
