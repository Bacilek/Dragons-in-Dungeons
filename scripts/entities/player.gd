class_name Player
extends Entity

var _dungeon_floor: Node  # set by DungeonFloor after spawning

func _ready() -> void:
	stats = GameState.player_stats
	_setup_sprite()

func _setup_sprite() -> void:
	var img := Image.create(16, 16, false, Image.FORMAT_RGB8)
	img.fill(Color(0.2, 0.4, 0.9))  # blue player square
	$Sprite2D.texture = ImageTexture.create_from_image(img)

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
	var target := grid_pos + dir
	if not _dungeon_floor.is_walkable(target):
		return

	var is_stairs: bool = _dungeon_floor.get_tile_type(target) == DungeonData.TileType.STAIRS_DOWN

	TurnManager.begin_player_action()
	await move_to(target)
	TurnManager.on_player_action_complete()

	if is_stairs:
		_dungeon_floor.on_player_reached_stairs.call_deferred()

func _wait_action() -> void:
	TurnManager.begin_player_action()
	TurnManager.on_player_action_complete()
