class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/characters/"
const SWORD_SPRITE := "res://sprites/weapons/weapon_anime_sword.png"
const ARROW_SPRITE := "res://sprites/weapons/weapon_arrow.png"
const UNDEAD_NAMES: Array = ["Tiny Zombie", "Goblin", "Skeleton", "Orc Warrior", "Orc Shaman", "Masked Orc", "Wogol"]

var _dungeon_floor: Node

var _queued_path: Array[Vector2i] = []
var _path_executing: bool = false
var _last_move_dir := Vector2i.ZERO
var _target_enemy: Enemy = null

var _prev_dir: Vector2i = Vector2i.ZERO  # direction held in the previous WAITING_FOR_INPUT frame
var _interrupted: bool = false           # set when enemy seen mid-hold; cleared only on key release

var _throw_item: Item = null
var _tool_item: Item = null
var _inspect_mode: bool = false
var _last_search_request: float = -999.0
var _rest_interrupt_shown: bool = false
var _traps_in_proximity: Array[Vector2i] = []

# FOV snapshots for advantage (surprise attack) detection
var _fov_prev_turn: Array[Enemy] = []  # visible enemies at START of previous player turn
var _fov_this_turn: Array[Enemy] = []  # visible enemies at START of current player turn

@onready var _camera: Camera2D = $Camera2D
const ZOOM_MIN: float = 1.0
const ZOOM_MAX: float = 5.0
const ZOOM_STEP: float = 0.25

var _is_panning: bool = false
var _lmb_panning: bool = false
var _pan_start_mouse: Vector2 = Vector2.ZERO
var _pan_start_cam: Vector2 = Vector2.ZERO
var _click_start_screen_pos: Vector2 = Vector2(-1.0, -1.0)
var _pending_click_tile: Vector2i = Vector2i(-1, -1)

var _hover_indicator: Sprite2D = null
var _hover_last_icon_path: String = ""
var _hover_last_texture: Texture2D = null

# ── Rage state ────────────────────────────────────────────────────────────────
# Baseline: lasts 10 turns, countdown each turn. Talent rank 1: pause when attacking or hit.
# _rage_attacked_this_turn: set in _bump_attack when raging + STR weapon; cleared at turn start.
var _is_raging: bool = false
var _rage_turns: int = 0
var _rage_attacked_this_turn: bool = false

# ── Rager state (Tier 2) ──────────────────────────────────────────────────────
# Per-round free-action caps for Rager R2 (move) and R3 (attack). Reset at turn start.
var _rager_move_triggered: bool = false
var _rager_attack_triggered: bool = false
# Per-turn Frenzy cap: fires once per turn. Reset at turn start.
var _frenzy_triggered_this_turn: bool = false

# ── Wild Heart state (Tier 2) ─────────────────────────────────────────────────
# Eagle Natural Rager: per-turn free-move cap. Reset at turn start.
var _eagle_free_move_used: bool = false

# ── Reckless Attack state ─────────────────────────────────────────────────────
# Talent-gated toggle (not available at rank 0). Free action — toggling does not consume a turn.
# Rank 1: +2 flat to first STR attack / enemies +2. Rank 2+: ADV / enemies ADV.
var _reckless_active: bool = false


# ── Equip action tracking ─────────────────────────────────────────────────────
var _pending_equip_turn: bool = false  # set by equip_action_taken signal; consumed in next action gate


func _ready() -> void:
	stats = GameState.player_stats
	z_index = 3
	_setup_animations()
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_action_requested.connect(_on_action_requested)
	GameState.player_throw_primed.connect(_on_throw_primed)
	GameState.player_tool_primed.connect(_on_tool_primed)
	GameState.player_died.connect(_on_player_died)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.camera_recenter_requested.connect(_reset_camera_offset)
	GameState.screen_shake.connect(_screen_shake)
	GameState.equip_action_taken.connect(_on_equip_action_taken)
	GameState.equipment_changed.connect(_on_equipment_changed)
	GameState.potion_drunk.connect(func():
		if GameState.add_item(_make_empty_bottle()):
			GameState.game_log("[color=gray]Empty bottle added to your bag.[/color]")
	)
	TurnManager.player_turn_started.connect(_on_turn_started)

func _on_equipment_changed() -> void:
	if _throw_item != null:
		_throw_item = null
		GameState.game_log("[color=gray]Throw cancelled.[/color]")
	# Wearing heavy armor while raging ends rage immediately (D&D 5e rule)
	if _is_raging:
		var armor: Item = GameState.equipped_armor
		if armor != null and armor.is_heavy_armor:
			_end_rage()
			GameState.game_log("[color=gray]The heavy armor weighs you down — Rage ends![/color]")

func _on_equip_action_taken() -> void:
	# Consume 1 turn the next time we have control (may be immediately if WAITING_FOR_INPUT)
	if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing \
			and not GameState.short_rest_open and not GameState.short_rest_active:
		TurnManager.begin_player_action()
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
	else:
		_pending_equip_turn = true

func _on_player_died() -> void:
	visible = false
	_queued_path.clear()
	_path_executing = false

func _on_class_chosen(_cls: Stats.CharacterClass) -> void:
	_setup_animations()

func _on_player_hp_changed(_c: int, _m: int) -> void:
	update_hp_bar()

func _on_turn_started() -> void:
	GameState.player_grid_pos = grid_pos
	# Reckless lock clears each turn — toggle becomes available again.
	GameState.reckless_locked_this_turn = false
	# Rager per-round free-action caps and Frenzy per-turn cap reset each turn.
	_rager_move_triggered = false
	_rager_attack_triggered = false
	_frenzy_triggered_this_turn = false
	_eagle_free_move_used = false
	GameState.ability_bar_changed.emit()
	# Refresh visibility after enemy turns, then snapshot FOV
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
		_fov_prev_turn = _fov_this_turn
		_fov_this_turn = _dungeon_floor.get_visible_enemies()

	# Consume a pending equip turn (couldn't be spent last frame)
	if _pending_equip_turn:
		_pending_equip_turn = false
		TurnManager.begin_player_action()
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
		return

	# Tick rage countdown. Talent rank 1: pause if player attacked or was hit last turn.
	if _is_raging:
		var rage_rank: int = GameState.get_talent_rank("rage")
		var combat_last_turn: bool = _rage_attacked_this_turn or GameState.player_was_hit_this_turn
		if rage_rank >= 1 and combat_last_turn:
			pass  # countdown paused — active combat extended rage
		else:
			_rage_turns -= 1
		_rage_attacked_this_turn = false
		GameState.player_was_hit_this_turn = false
		GameState.rage_turns_remaining = _rage_turns
		GameState.ability_bar_changed.emit()
		if _rage_turns <= 0:
			_end_rage()
			GameState.game_log("[color=gray]Your Rage fades.[/color]")

	# Short rest in progress — player waits in place
	if GameState.short_rest_active:
		if GameState.short_rest_open:
			return  # Panel open — freeze until player clicks Continue/Abort
		if not _fov_this_turn.is_empty() and not _rest_interrupt_shown:
			_rest_interrupt_shown = true
			GameState.short_rest_open = true
			var panel_script = load("res://scripts/ui/rest_interrupt_panel.gd")
			get_tree().root.call_deferred("add_child", panel_script.new())
			_do_rest_wait_turn()
			return
		GameState.short_rest_turns_remaining -= 1
		if GameState.short_rest_turns_remaining > 0:
			GameState.game_log("[color=gray]Resting... (%d turn(s) remaining)[/color]" % GameState.short_rest_turns_remaining)
		else:
			var healed: int = GameState.short_rest_pending_heal
			GameState.heal(healed)
			GameState.game_log("[color=cyan]You finish your short rest and recover [b]+%d HP[/b].[/color]" % healed)
			GameState.short_rest_active = false
			GameState.short_rest_pending_heal = 0
			_rest_interrupt_shown = false
			GameState.short_rest_changed.emit()
		_do_rest_wait_turn()
		return

	GameState.deplete_hunger()
	var status_dmg: int = GameState.player_stats.tick_status()
	if status_dmg > 0:
		GameState.take_damage_raw(status_dmg)
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(position, status_dmg, true)
		GameState.player_status_changed.emit()

func _setup_animations() -> void:
	var char_name: String
	match GameState.player_stats.character_class:
		Stats.CharacterClass.RANGER:  char_name = "elf_m"
		Stats.CharacterClass.WIZARD:  char_name = "wizzard_m"
		Stats.CharacterClass.MONK:    char_name = "dwarf_m"
		_:                            char_name = "knight_m"   # BARBARIAN default
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
	_update_hover_indicator()
	if GameState.is_game_over or GameState.inventory_open or GameState.short_rest_open or not GameState.class_selected:
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
		_interrupted = false
	elif _interrupted:
		# Key still physically held after interrupt — block until finger lifted
		_prev_dir = dir
		return
	elif not GameState.noclip and not _fov_this_turn.is_empty():
		# Any enemy visible — interrupt hold movement
		_interrupted = true
		_prev_dir = dir
		return
	_prev_dir = dir
	if dir == _last_move_dir:
		return
	_last_move_dir = dir
	_queued_path.clear()
	if _throw_item != null:
		_throw_item = null
		GameState.game_log("[color=gray]Throw cancelled.[/color]")
	# Thief Tools: let _try_move handle door/trap bump — don't cancel the tool here.
	if _tool_item != null and _tool_item.item_name != "Thief Tools":
		_tool_item = null
		GameState.game_log("[color=gray]Disarm cancelled.[/color]")
	_try_move(dir)

func _ensure_hover_indicator() -> void:
	if _hover_indicator != null and is_instance_valid(_hover_indicator):
		return
	if _dungeon_floor == null:
		return
	_hover_indicator = Sprite2D.new()
	_hover_indicator.z_index = 12
	_hover_indicator.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_hover_indicator.scale = Vector2(0.75, 0.75)
	_hover_indicator.modulate = Color(1.0, 1.0, 1.0, 0.85)
	_hover_indicator.visible = false
	_dungeon_floor.add_child(_hover_indicator)

func _update_hover_indicator() -> void:
	_ensure_hover_indicator()
	if _hover_indicator == null or _dungeon_floor == null:
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing \
			or GameState.short_rest_open or GameState.inventory_open or GameState.is_game_over:
		_hover_indicator.visible = false
		return
	var world_mouse: Vector2 = get_global_mouse_position()
	var tile: Vector2i = Vector2i(floori(world_mouse.x / 16.0), floori(world_mouse.y / 16.0))
	var enemy: Enemy = _dungeon_floor.get_enemy_at(tile)
	if enemy == null or not is_instance_valid(enemy):
		_hover_indicator.visible = false
		return
	var weapon: Item = GameState.equipped_ranged if Input.is_key_pressed(KEY_SHIFT) else GameState.equipped_weapon
	if weapon == null:
		_hover_indicator.visible = false
		return
	if weapon.icon_path != _hover_last_icon_path:
		_hover_last_icon_path = weapon.icon_path
		_hover_last_texture = load(weapon.icon_path) as Texture2D
		_hover_indicator.texture = _hover_last_texture
	_hover_indicator.global_position = enemy.global_position + Vector2(6, -14)
	_hover_indicator.visible = true

func _reset_camera_offset() -> void:
	if _camera != null:
		_camera.position = Vector2.ZERO
	_is_panning = false
	_lmb_panning = false
	_pending_click_tile = Vector2i(-1, -1)

func _screen_shake(strength: float = 5.0) -> void:
	if _camera == null:
		return
	var t := create_tween()
	for i: int in 8:
		t.tween_callback(func():
			_camera.offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		)
		t.tween_interval(0.035)
	t.tween_callback(func(): _camera.offset = Vector2.ZERO)

func _input(event: InputEvent) -> void:
	if event is InputEventMouseButton and _camera != null:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_MIDDLE:
			if mb.pressed:
				_is_panning = true
				_pan_start_mouse = mb.position
				_pan_start_cam = _camera.position
			else:
				_is_panning = false
			get_viewport().set_input_as_handled()
		elif mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed:
				# Capture pan origin; actual panning activates after 8px threshold in motion handler
				_pan_start_mouse = mb.position
				_pan_start_cam = _camera.position
				_lmb_panning = false
			elif _lmb_panning:
				_lmb_panning = false
				_is_panning = false
				get_viewport().set_input_as_handled()
	elif event is InputEventMouseMotion and _camera != null:
		if _is_panning:
			var motion := event as InputEventMouseMotion
			_camera.position = _pan_start_cam - (motion.position - _pan_start_mouse) / _camera.zoom.x
			get_viewport().set_input_as_handled()
		elif Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT) and not _lmb_panning and not GameState.inventory_open:
			var motion := event as InputEventMouseMotion
			if motion.position.distance_to(_pan_start_mouse) > 8.0:
				_lmb_panning = true
				_is_panning = true
				# Reset pan baseline to current position so camera doesn't jump
				_pan_start_mouse = motion.position
				_pan_start_cam = _camera.position
				_queued_path.clear()
				_target_enemy = null
				_pending_click_tile = Vector2i(-1, -1)
				_click_start_screen_pos = Vector2(-1.0, -1.0)
				get_viewport().set_input_as_handled()

func _unhandled_input(event: InputEvent) -> void:
	if GameState.is_game_over or not GameState.class_selected:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if not key.pressed or key.echo:
			return
		# I key toggles inventory regardless of turn phase (blocked during short rest)
		if key.physical_keycode == KEY_I:
			if not GameState.short_rest_open:
				GameState.inventory_toggle.emit()
			return
		# T key opens talent screen regardless of turn phase; bypasses phase gate
		if key.physical_keycode == KEY_T:
			if not GameState.inventory_open and not GameState.short_rest_open \
					and not GameState.short_rest_active and not GameState.talent_picker_open:
				_open_talent_picker()
				get_viewport().set_input_as_handled()
			return
		if GameState.inventory_open or GameState.short_rest_open or GameState.short_rest_active or GameState.talent_picker_open:
			return
		if key.physical_keycode == KEY_ESCAPE:
			if _inspect_mode:
				_inspect_mode = false
				GameState.game_log("[color=gray]Inspect cancelled.[/color]")
				return
			if _throw_item != null:
				_throw_item = null
				GameState.game_log("[color=gray]Throw cancelled.[/color]")
			if _tool_item != null:
				_tool_item = null
				GameState.game_log("[color=gray]Disarm cancelled.[/color]")
			return
		# Tab toggles between item bar and ability bar (valid any time except game over)
		if key.physical_keycode == KEY_TAB:
			GameState.player_action_requested.emit("toggle_ability_bar")
			return
		if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
			return
		_queued_path.clear()
		match key.physical_keycode:
			KEY_Q, KEY_KP_7:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(-1, -1))
			KEY_E, KEY_KP_9:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(1, -1))
			KEY_Z, KEY_KP_1:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(-1, 1))
			KEY_C, KEY_KP_3:
				if _throw_item != null: _throw_item = null; GameState.game_log("[color=gray]Throw cancelled.[/color]")
				if _tool_item != null and _tool_item.item_name != "Thief Tools": _tool_item = null; GameState.game_log("[color=gray]Disarm cancelled.[/color]")
				_try_move(Vector2i(1, 1))
			KEY_SPACE, KEY_PERIOD, KEY_KP_5: _wait_action()
			KEY_CTRL: _handle_search_request()
			KEY_ALT: _open_short_rest()
			KEY_1: _use_quickbar_slot(0)
			KEY_2: _use_quickbar_slot(1)
			KEY_3: _use_quickbar_slot(2)
			KEY_4: _use_quickbar_slot(3)
			KEY_5: _use_quickbar_slot(4)
			KEY_6: _use_quickbar_slot(5)
			KEY_7: _use_quickbar_slot(6)
			KEY_8: _use_quickbar_slot(7)
			KEY_9: _use_quickbar_slot(8)

	elif event is InputEventMouseMotion:
		if _click_start_screen_pos.x >= 0.0 and Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			var motion := event as InputEventMouseMotion
			if motion.position.distance_to(_click_start_screen_pos) > 8.0:
				_queued_path.clear()
				_target_enemy = null
				_pending_click_tile = Vector2i(-1, -1)
				_click_start_screen_pos = Vector2(-1.0, -1.0)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		# Zoom deferred here so ScrollContainers (debug panel) get wheel events via _gui_input first
		if mb.pressed and _camera != null:
			if mb.button_index == MOUSE_BUTTON_WHEEL_UP:
				_camera.zoom = Vector2.ONE * clampf(_camera.zoom.x + ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()
				return
			elif mb.button_index == MOUSE_BUTTON_WHEEL_DOWN:
				_camera.zoom = Vector2.ONE * clampf(_camera.zoom.x - ZOOM_STEP, ZOOM_MIN, ZOOM_MAX)
				get_viewport().set_input_as_handled()
				return
		if not mb.pressed:
			if mb.button_index == MOUSE_BUTTON_LEFT:
				_click_start_screen_pos = Vector2(-1.0, -1.0)
				var pending := _pending_click_tile
				_pending_click_tile = Vector2i(-1, -1)
				if _lmb_panning or pending == Vector2i(-1, -1) or _dungeon_floor == null:
					return
				if GameState.short_rest_active or GameState.short_rest_open:
					return
				if pending == grid_pos:
					return
				if Input.is_key_pressed(KEY_SHIFT):
					var rw: Item = GameState.equipped_ranged
					if rw == null:
						GameState.game_log("[color=gray]No ranged weapon equipped.[/color]")
						return
					if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
						return
					var dv: Vector2i = pending - grid_pos
					if dv.x * dv.x + dv.y * dv.y > rw.range * rw.range:
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % rw.range)
						return
					if not _dungeon_floor.has_ranged_los(grid_pos, pending):
						GameState.game_log("[color=gray]No clear shot to target.[/color]")
						return
					var enemy_shift: Enemy = _dungeon_floor.get_enemy_at(pending)
					if enemy_shift != null:
						_ranged_attack(enemy_shift)
					else:
						_ranged_attack_tile(pending)
					return
				var enemy_on_tile: Enemy = _dungeon_floor.get_enemy_at(pending)
				if enemy_on_tile != null:
					_target_enemy = enemy_on_tile
					_queued_path.clear()
					if not _path_executing:
						_execute_queued_path()
					return
				_target_enemy = null
				var release_path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, pending)
				if release_path.is_empty():
					return
				_queued_path = release_path
				if not _path_executing:
					_execute_queued_path()
			else:
				_click_start_screen_pos = Vector2(-1.0, -1.0)
			return
		if _dungeon_floor == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var clicked: Vector2i = Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_throw_item = null
				if _tool_item != null and _tool_item.item_name == "Empty Bottle":
					var bottle: Item = _tool_item
					_tool_item = null
					_try_fill_bottle(bottle, clicked)
				else:
					var had_tool: bool = _tool_item != null
					_tool_item = null
					_interact_action(had_tool, clicked)
			return

		if mb.button_index != MOUSE_BUTTON_LEFT:
			return

		_click_start_screen_pos = mb.position

		if GameState.short_rest_active or GameState.short_rest_open:
			return

		# Inspect mode — show info about clicked tile (immediate intentional click)
		if _inspect_mode:
			_inspect_mode = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
				_do_inspect(clicked)
			return

		# Tool targeting mode — route by tool type
		if _tool_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				var dist: int = maxi(absi(clicked.x - grid_pos.x), absi(clicked.y - grid_pos.y))
				if dist <= 1:
					var tool: Item = _tool_item
					_tool_item = null
					if tool.item_name == "Empty Bottle":
						_try_fill_bottle(tool, clicked)
					else:
						_interact_action(true, clicked)  # Thief Tools: door lock / trap disarm / nothing
				else:
					GameState.game_log("[color=gray]Too far — click an adjacent tile.[/color]")
			else:
				_tool_item = null
			return

		# Throw mode — consume left-click for the toss (immediate intentional click)
		if _throw_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_do_throw(clicked)
			else:
				_throw_item = null
			return

		# Movement/attack: store tile, execute on release to distinguish from drag
		_pending_click_tile = clicked

func _execute_queued_path() -> void:
	_path_executing = true
	TurnManager.fast_mode = not TurnManager.has_any_enemy()
	_reset_camera_offset()


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
				# Adjacent — melee attack
				var atk_dir: Vector2i = _target_enemy.grid_pos - grid_pos
				_bump_attack(_target_enemy, atk_dir)
				_target_enemy = null
				if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
					await TurnManager.player_turn_started
				break

			# One step closer
			var next: Vector2i = chase_path[0]
			var dir: Vector2i = next - grid_pos
			var prev_c: Vector2i = grid_pos
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
				if _dungeon_floor.has_door_at(prev_c):
					_dungeon_floor.close_door(prev_c)
				_leave_blood_trail(prev_c)
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
			if Input.is_key_pressed(KEY_SHIFT) and GameState.equipped_ranged != null:
				_ranged_attack(enemy_there)
			else:
				_bump_attack(enemy_there, dir)
			if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
				await TurnManager.player_turn_started
			break

		if GameState.noclip:
			# Noclip: reject only off-grid VOID tiles
			if _dungeon_floor.get_tile_type(next) == DungeonData.TileType.VOID:
				_queued_path.clear()
				break
		else:
			# Door handling — locked doors distinguish dungeon-generated vs player-set
			if _dungeon_floor.has_door_at(next) and not _dungeon_floor.is_door_open(next):
				if _dungeon_floor.is_door_locked(next):
					if _dungeon_floor.is_door_player_locked(next):
						_dungeon_floor.unlock_door(next)
						_dungeon_floor.open_door(next)
						GameState.game_log("[color=cyan]You pass through the door you locked.[/color]")
					else:
						GameState.game_log("[color=red]The door is locked.[/color]")
						_queued_path.clear()
						break
				else:
					_dungeon_floor.open_door(next)

			if not _dungeon_floor.is_walkable(next):
				_queued_path.clear()
				break

		var is_stairs: bool = _dungeon_floor.get_tile_type(next) == DungeonData.TileType.STAIRS_DOWN
		var prev_p: Vector2i = grid_pos

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
			if _dungeon_floor.has_door_at(prev_p):
				_dungeon_floor.close_door(prev_p)
			_leave_blood_trail(prev_p)
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

		# Difficult terrain or slowed: costs 2 turns — stop queued path and waste a turn
		var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
		if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD:
			GameState.apply_player_status("slowed", maxi(1, GameState.player_stats.slowed_turns))
		if tile_t == DungeonData.TileType.WATER and GameState.player_stats.burning_turns > 0:
			GameState.player_stats.burning_turns = 0
			GameState.player_status_changed.emit()
			GameState.game_log("[color=cyan]The water extinguishes your flames![/color]")
		if GameState.player_stats.slowed_turns > 0:
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
	if _dungeon_floor == null or GameState.noclip:
		return false
	for e: Enemy in _dungeon_floor.get_visible_enemies():
		if e not in snapshot:
			return true
	return false

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	_reset_camera_offset()
	var target: Vector2i = grid_pos + dir

	var enemy: Enemy = _dungeon_floor.get_enemy_at(target)
	if enemy != null:
		if Input.is_key_pressed(KEY_SHIFT) and GameState.equipped_ranged != null:
			_ranged_attack(enemy)
		else:
			_bump_attack(enemy, dir)
		return

	# Thief Tools primed + bump = interact without moving (door or revealed trap).
	if _tool_item != null and _tool_item.item_name == "Thief Tools":
		# Revealed trap adjacent: disarm it.
		var adjacent_trap: Dictionary = _dungeon_floor.get_trap_at(target)
		if not adjacent_trap.is_empty() and adjacent_trap.get("revealed", false):
			_tool_item = null
			_attempt_disarm(target)
			return
		# Door adjacent: lock/unlock/pick action.
		if _dungeon_floor.has_door_at(target):
			_tool_item = null
			if _dungeon_floor.is_door_open(target):
				_attempt_lock_door(target)
			elif _dungeon_floor.is_door_locked(target):
				if _dungeon_floor.is_door_player_locked(target):
					TurnManager.begin_player_action()
					_dungeon_floor.unlock_door(target)
					_dungeon_floor.open_door(target)
					GameState.game_log("[color=cyan]You unlock the door you set.[/color]")
					_dungeon_floor.update_fog(grid_pos)
					TurnManager.on_player_action_complete()
				else:
					_attempt_disarm_lock(target)
			else:
				_attempt_lock_door(target)
			return
		# Nothing to interact with — cancel tool and move normally.
		_tool_item = null
		GameState.game_log("[color=gray]Nothing to interact with.[/color]")


	var _ns_rank: int = GameState.get_talent_rank("natural_sleeper")
	var _ns_form: String = GameState.natural_sleeper_form
	var _sleeper_on: bool = GameState.wild_heart_sleeper_active and _ns_rank >= 1
	var _target_tile: DungeonData.TileType = _dungeon_floor.get_tile_type(target)

	if GameState.noclip:
		# Noclip: only reject off-grid VOID
		if _dungeon_floor.get_tile_type(target) == DungeonData.TileType.VOID:
			return
	else:
		# Natural Sleeper Owl R1: allow movement into CHASM tiles
		var _owl_override: bool = _sleeper_on and _ns_form == "Owl" and _target_tile == DungeonData.TileType.CHASM
		# Door handling — locked doors distinguish dungeon-generated vs player-set
		if _dungeon_floor.has_door_at(target) and not _dungeon_floor.is_door_open(target):
			if _dungeon_floor.is_door_locked(target):
				if _dungeon_floor.is_door_player_locked(target):
					# Player set this lock — walk through freely (you know it)
					_dungeon_floor.unlock_door(target)
					_dungeon_floor.open_door(target)
					GameState.game_log("[color=cyan]You pass through the door you locked.[/color]")
				else:
					# Dungeon-generated lock — can't walk through
					GameState.game_log("[color=red]The door is locked.[/color]")
					return
			else:
				_dungeon_floor.open_door(target)

		if not _dungeon_floor.is_walkable(target) and not _owl_override:
			return

	var is_stairs: bool = _dungeon_floor.get_tile_type(target) == DungeonData.TileType.STAIRS_DOWN

	var prev_pos: Vector2i = grid_pos
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(target)
	$AnimatedSprite2D.play("idle")
	if _dungeon_floor != null:
		if _dungeon_floor.has_door_at(prev_pos):
			_dungeon_floor.close_door(prev_pos)
		_leave_blood_trail(prev_pos)
		# Destroy grass before fog update so our own tile doesn't block sight
		if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
			_dungeon_floor.destroy_grass(grid_pos)
		_dungeon_floor.update_fog(grid_pos)
		_passive_trap_check()
		_check_pickup()
		match _dungeon_floor.get_tile_type(grid_pos):
			DungeonData.TileType.GRASS, DungeonData.TileType.TRAMPLED_GRASS:
				AudioManager.play("step_grass")
			DungeonData.TileType.MUD:
				AudioManager.play("step_mud")
			DungeonData.TileType.WATER:
				AudioManager.play("step_water")
			_:
				AudioManager.play("step_floor")
		var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
		if not trap.is_empty():
			await _dungeon_floor.trigger_trap(grid_pos, self)  # push trap still awaits; others return instantly
	if is_stairs:
		TurnManager.on_player_action_complete()
		_dungeon_floor.on_player_reached_stairs.call_deferred()
		return
	# Difficult terrain: apply status before Rager / Eagle check.
	# Natural Sleeper Panther R1 bypasses mud; Salmon R1 bypasses water.
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	var _panther_bypass: bool = _sleeper_on and _ns_form == "Panther" and tile_t == DungeonData.TileType.MUD
	var _salmon_bypass: bool = _sleeper_on and _ns_form == "Salmon" and tile_t == DungeonData.TileType.WATER
	if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD:
		if not _panther_bypass and not _salmon_bypass:
			GameState.apply_player_status("slowed", maxi(1, GameState.player_stats.slowed_turns))
	if tile_t == DungeonData.TileType.WATER and GameState.player_stats.burning_turns > 0:
		GameState.player_stats.burning_turns = 0
		GameState.player_status_changed.emit()
		GameState.game_log("[color=cyan]The water extinguishes your flames![/color]")
	# Natural Sleeper R2: 5 temp HP when entering form's terrain
	if _ns_rank >= 2 and GameState.wild_heart_sleeper_active:
		var _sleeper_terrain_match: bool = (
			(_ns_form == "Owl" and tile_t == DungeonData.TileType.CHASM) or
			(_ns_form == "Panther" and tile_t == DungeonData.TileType.MUD) or
			(_ns_form == "Salmon" and tile_t == DungeonData.TileType.WATER)
		)
		if _sleeper_terrain_match:
			GameState.player_stats.temp_hp += 5
			GameState.game_log("[color=cyan]Natural Sleeper: 5 temp HP from %s terrain.[/color]" % _ns_form)
	# Natural Sleeper R3: AC bonus while standing in form's terrain
	if _ns_rank >= 3 and GameState.wild_heart_sleeper_active:
		var _ac_terrain_match: bool = (
			(_ns_form == "Owl" and tile_t == DungeonData.TileType.CHASM) or
			(_ns_form == "Panther" and tile_t == DungeonData.TileType.MUD) or
			(_ns_form == "Salmon" and tile_t == DungeonData.TileType.WATER)
		)
		var _new_ac_bonus: int = 2 if _ac_terrain_match else 0
		if _new_ac_bonus != GameState.terrain_ac_bonus:
			GameState.terrain_ac_bonus = _new_ac_bonus
			GameState.recalculate_stats()
	# Rager R2: chance to grant a free action after moving (skips enemy turn + slowed penalty)
	if _is_raging and GameState.get_talent_rank("rager") >= 2 and not _rager_move_triggered:
		if randi_range(1, 100) <= GameState.player_stats.rage_bonus_damage * 10:
			_rager_move_triggered = true
			_rage_attacked_this_turn = true  # pause rage countdown on the reverted turn
			GameState.game_log("[color=orange]Rager: fury drives you — the move didn't cost a turn![/color]")
			TurnManager.revert_to_waiting()
			return
	# Natural Rager Eagle: free-move. R1 = 50% chance once/turn; R2 = guaranteed once/turn.
	var _nr_rank: int = GameState.get_talent_rank("natural_rager")
	if _is_raging and _nr_rank >= 1 and GameState.natural_rager_form == "Eagle" and not _eagle_free_move_used:
		var _should_eagle_free: bool = _nr_rank >= 2 or randi_range(1, 100) <= 50
		if _should_eagle_free:
			_eagle_free_move_used = true
			_rage_attacked_this_turn = true  # pause rage countdown on reverted turn
			GameState.game_log("[color=lime]Eagle Form: wings carry you — the move didn't cost a turn![/color]")
			TurnManager.revert_to_waiting()
			return
	TurnManager.on_player_action_complete()
	# Slowed extra turn cost (skip if Panther/Salmon bypassed the terrain penalty)
	if GameState.player_stats.slowed_turns > 0 and not _panther_bypass and not _salmon_bypass:
		await TurnManager.player_turn_started
		TurnManager.begin_player_action()
		_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()

# ── Rage helpers ─────────────────────────────────────────────────────────────

func _activate_reckless() -> void:
	var ab: Ability = _find_ability("reckless_attack")
	if ab == null:
		return
	if GameState.reckless_locked_this_turn:
		GameState.game_log("[color=gray]Reckless Attack can only be toggled before your first attack.[/color]")
		return
	_reckless_active = not _reckless_active
	ab.is_active = _reckless_active
	GameState.reckless_attack_active = _reckless_active
	GameState.ability_bar_changed.emit()
	var rank: int = GameState.get_talent_rank("reckless_attack")
	if _reckless_active:
		match rank:
			1: GameState.game_log("[color=yellow]Reckless Attack: ON — +2 to STR attack roll, enemies +2 to attack you.[/color]")
			2: GameState.game_log("[color=yellow]Reckless Attack: ON — ADV on first STR attack, enemies ADV against you.[/color]")
			3: GameState.game_log("[color=yellow]Reckless Attack: ON — ADV on all STR attacks, enemies ADV against you.[/color]")
	else:
		GameState.game_log("[color=gray]Reckless Attack: OFF.[/color]")
	# Free action: does NOT consume the turn.

func _activate_rage() -> void:
	if _is_raging:
		GameState.game_log("[color=red]You are already raging![/color]")
		return
	var ab: Ability = _find_ability("rage")
	if ab == null or not ab.has_uses():
		GameState.game_log("[color=red]No Rage uses remaining (resets on floor descent).[/color]")
		return
	_is_raging = true
	_rage_turns = 10  # baseline: 10-turn countdown
	_rage_attacked_this_turn = false
	GameState.is_raging = true
	GameState.rage_turns_remaining = _rage_turns
	if not GameState.invincible:
		ab.uses_remaining -= 1
	GameState.player_stats.rage_uses_remaining = ab.uses_remaining
	GameState.ability_bar_changed.emit()
	$AnimatedSprite2D.modulate = Color(1.6, 0.55, 0.55)  # red tint
	var rage_rank: int = GameState.get_talent_rank("rage")
	var dr_note: String = ""
	if rage_rank >= 3: dr_note = " 50% physical DR."
	elif rage_rank >= 2: dr_note = " 25% physical DR."
	var rage_dmg_bonus: int = stats.rage_bonus_damage
	GameState.game_log("[color=red]You fly into a RAGE! +%d STR damage.%s (%d turns, %d use(s) left)[/color]" % [rage_dmg_bonus, dr_note, _rage_turns, ab.uses_remaining])
	# Free action — does NOT consume the turn.

func _end_rage() -> void:
	_is_raging = false
	_rage_turns = 0
	GameState.is_raging = false
	GameState.rage_turns_remaining = 0
	$AnimatedSprite2D.modulate = Color(1.0, 1.0, 1.0)

func _find_ability(ab_id: String) -> Ability:
	for slot in GameState.player_ability_bar:
		if slot != null and (slot as Ability).ability_id == ab_id:
			return slot as Ability
	return null

# ── Melee attack ─────────────────────────────────────────────────────────────

func _bump_attack(enemy: Enemy, dir: Vector2i) -> void:
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")

	_show_sword_slash(dir)

	# D&D attack roll: d20 + modifier + proficiency bonus + weapon enhancement vs enemy AC
	# Advantage (2d20 higher) when target is sleeping or entered FOV this turn.
	# Monk unarmed: uses DEX for both attack roll and damage. Others: STR.
	var is_unarmed: bool = GameState.equipped_weapon == null
	var is_monk_unarmed: bool = is_unarmed and stats.character_class == Stats.CharacterClass.MONK
	var is_str_weapon: bool = not is_unarmed and not (GameState.equipped_weapon.is_ranged)
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var prof: int = stats.proficiency_bonus  # all melee weapons are proficient for now
	var weapon_bonus: int = GameState.equipped_weapon.bonus_damage if not is_unarmed else 0
	# Monk unarmed uses DEX; everyone else uses STR for melee attack roll.
	var attack_mod: int = dex_mod if is_monk_unarmed else str_mod
	var total_hit_bonus: int = attack_mod + prof + weapon_bonus
	# Advantage sources are counted; net ADV count vs DISADV count decides outcome.
	# Two ADV sources + one DISADV = net +1 = ADV (house rule: count beats cancel).
	var adv_count: int = 0
	var disadv_count: int = 0
	var reckless_flat_bonus: int = 0  # rank 1 flat +2 (not ADV)
	if _has_advantage(enemy): adv_count += 1
	# Reckless Attack: rank 1 = flat +2 on first attack; rank 2+ = ADV on first; rank 3 = ADV on all.
	var reckless_rank: int = GameState.get_talent_rank("reckless_attack")
	var reckless_applies: bool = _reckless_active and is_str_weapon and not GameState.reckless_locked_this_turn
	var reckless_all_attacks: bool = _reckless_active and is_str_weapon and reckless_rank >= 3
	if reckless_applies or reckless_all_attacks:
		match reckless_rank:
			1:
				reckless_flat_bonus = 2
			2, 3:
				adv_count += 1
	# Heavy weapon penalty: STR < 13 imposes Disadvantage
	var weapon_item_ref: Item = GameState.equipped_weapon
	if weapon_item_ref != null and weapon_item_ref.is_heavy and stats.strength < 13: disadv_count += 1
	# Natural Rager Wolf: ADV when enough enemies are in FOV while Raging
	var wolf_nr_rank: int = GameState.get_talent_rank("natural_rager")
	if wolf_nr_rank >= 1 and _is_raging and GameState.natural_rager_form == "Wolf" and is_str_weapon:
		var wolf_threshold: int = [0, 4, 3, 2][mini(wolf_nr_rank, 3)]
		if _dungeon_floor != null and _dungeon_floor.get_visible_enemies().size() >= wolf_threshold:
			adv_count += 1
	var net: int = adv_count - disadv_count
	var adv: bool = net > 0
	var disadv: bool = net < 0
	# Commit Reckless: lock toggle after first attack (not needed for rank 3 all-attacks mode).
	if reckless_applies and reckless_rank < 3:
		GameState.reckless_locked_this_turn = true
		GameState.ability_bar_changed.emit()
	# die2 is ALWAYS rolled independently when ADV/DISADV is active — nat 1 on die1 does NOT skip it.
	var die1: int = randi_range(1, 20)
	var die2: int = die1
	var die: int = die1
	if adv and not disadv:
		die2 = randi_range(1, 20)
		die = maxi(die1, die2)
	elif disadv and not adv:
		die2 = randi_range(1, 20)
		die = mini(die1, die2)
	var roll: int = die + total_hit_bonus + reckless_flat_bonus
	var is_crit: bool = die == 20
	var is_nat_one: bool = die == 1

	# Track that we attacked while raging (for rank 1 countdown pause)
	if _is_raging and is_str_weapon:
		_rage_attacked_this_turn = true

	# Compute damage breakdown for tooltip (separate die vs enhancement vs rage)
	var w_dmin: int
	var w_dmax: int
	if is_monk_unarmed:
		w_dmin = 1
		w_dmax = stats.martial_arts_die_sides
	elif not is_unarmed and GameState.equipped_weapon.damage_die_min > 0:
		w_dmin = GameState.equipped_weapon.damage_die_min
		w_dmax = GameState.equipped_weapon.damage_die_max
	else:
		w_dmin = stats.base_min_damage
		w_dmax = stats.base_max_damage
	var w_enh: int = weapon_bonus  # weapon.bonus_damage
	# Use dex= key for Monk unarmed so the HUD tooltip labels it correctly.
	var mod_key: String = "dex" if is_monk_unarmed else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,reck=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, w_enh, reckless_flat_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0]

	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_verb: String = "strike at" if is_monk_unarmed else ("punch" if is_unarmed else "swing")
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("You %s [color=orange]%s[/color] — [url=%s]%s[/url]." % [miss_verb, enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		_handle_post_attack_turn(is_monk_unarmed)
		return

	AudioManager.play("crit" if is_crit else "hit_enemy")
	_flash_hit(enemy)
	if adv:
		_show_surprise_mark(enemy)

	var die_roll: int = randi_range(w_dmin, w_dmax)
	var rage_bonus: int = stats.rage_bonus_damage if (_is_raging and is_str_weapon) else 0
	# Monk unarmed uses DEX for damage; all others use STR.
	var dmg_mod: int = dex_mod if is_monk_unarmed else str_mod
	var pre_crit: int = die_roll + w_enh + rage_bonus + dmg_mod
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)

	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,%s=%d,rage=%d,crit=%d,final=%d" % [
		die_roll, w_dmin, w_dmax, w_enh, mod_key, dmg_mod, rage_bonus, 1 if is_crit else 0, actual]
	var verb: String = "strike" if is_monk_unarmed else ("punch" if is_unarmed else "strike")
	var weapon_item: Item = GameState.equipped_weapon
	var dmg_type: String = weapon_item.damage_type if weapon_item != null and not weapon_item.damage_type.is_empty() else ("Bludgeoning" if is_unarmed else "<unknown_damage_type>")
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var god_hp: String = " [color=gray][%d/%d HP][/color]" % [enemy.stats.current_hp, enemy.stats.max_hp] if GameState.god_mode and not enemy.stats.is_dead() else ""
	# Frenzy: compute BEFORE logging so the bonus can be appended to the same line.
	var frenzy_tag: String = ""
	var frenzy_rank: int = GameState.get_talent_rank("frenzy")
	if frenzy_rank >= 1 and _is_raging and is_str_weapon and not _frenzy_triggered_this_turn and not enemy.stats.is_dead():
		_frenzy_triggered_this_turn = true
		var frenzy_sides: int = [0, 4, 6, 8][frenzy_rank]
		var frenzy_roll: int = randi_range(1, frenzy_sides)
		var frenzy_bonus: int = frenzy_roll * stats.rage_bonus_damage
		enemy.stats.take_damage(frenzy_bonus)
		enemy.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(enemy.position, frenzy_bonus, false)
		frenzy_tag = " [color=red](+%d Frenzy)[/color]" % frenzy_bonus

	if is_crit:
		GameState.game_log("[color=red]CRIT![/color] You [url=%s]%s[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s%s" % [hit_meta, verb, enemy.display_name, dmg_meta, actual, type_tag, frenzy_tag, god_hp])
	else:
		GameState.game_log("You [url=%s]%s[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s%s" % [hit_meta, verb, enemy.display_name, dmg_meta, actual, type_tag, frenzy_tag, god_hp])

	if enemy.stats.is_dead():
		_finish_kill(enemy)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	_handle_post_attack_turn(is_monk_unarmed)

func _handle_post_attack_turn(_from_monk_unarmed: bool = false) -> void:
	# Rager R3: chance to grant a free action after attacking (once per round)
	if _is_raging and GameState.get_talent_rank("rager") >= 3 and not _rager_attack_triggered:
		if randi_range(1, 100) <= GameState.player_stats.rage_bonus_damage * 10:
			_rager_attack_triggered = true
			_rage_attacked_this_turn = true  # pause rage countdown on revert
			GameState.game_log("[color=orange]Rager: fury drives you — the attack didn't cost a turn![/color]")
			TurnManager.revert_to_waiting()
			return
	TurnManager.on_player_action_complete()

func _show_sword_slash(dir: Vector2i) -> void:
	if GameState.equipped_weapon == null:
		return

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

func try_retaliation(attacker: Enemy) -> void:
	var rank: int = GameState.get_talent_rank("retaliation")
	if rank < 1:
		return
	var rage_bonus: int = stats.rage_bonus_damage
	var melee_item: Item = GameState.equipment.get("melee", null)
	var wpn_roll: int = 0
	var wpn_bonus: int = 0
	if melee_item != null:
		wpn_roll = randi_range(melee_item.damage_die_min, melee_item.damage_die_max)
		wpn_bonus = melee_item.bonus_damage
	var wpn_dmg: int = wpn_roll + wpn_bonus
	var ret_dmg: int = 0
	match rank:
		1: ret_dmg = rage_bonus                            # rage bonus only
		2: ret_dmg = wpn_dmg                               # weapon only — rage bonus NOT included at rank 2 (intentional)
		3: ret_dmg = wpn_dmg + rage_bonus + stats.str_modifier()
	ret_dmg = maxi(0, ret_dmg)
	if ret_dmg <= 0:
		return
	var dmg_type: String = melee_item.damage_type if melee_item != null else "Slashing"
	attacker.stats.take_damage(ret_dmg)
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(attacker.position, ret_dmg, false)
	var ret_meta: String = "ret:rank=%d,wpn_roll=%d,wpn_bonus=%d,rage=%d,str=%d,final=%d" % [
		rank, wpn_roll, wpn_bonus, rage_bonus, stats.str_modifier(), ret_dmg]
	GameState.game_log("[color=orange]Retaliation! [url=%s][color=yellow]%d[/color][/url] %s back to %s.[/color]" % [
		ret_meta, ret_dmg, dmg_type, attacker.display_name])
	if attacker.stats.is_dead():
		_finish_kill(attacker)


func _finish_kill(enemy: Enemy) -> void:
	GameState.game_log("[color=orange]%s[/color] [color=gray]dies.[/color]" % enemy.display_name)
	GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
	var was_boss: bool = enemy.is_boss
	var kill_pos: Vector2i = enemy.grid_pos
	var killed_name: String = enemy.display_name
	_dungeon_floor.remove_enemy(enemy)
	enemy.die()
	if was_boss:
		_dungeon_floor.drop_boss_loot(kill_pos)
	if killed_name in UNDEAD_NAMES and randf() < 0.20:
		var rotten := Item.new()
		rotten.item_name = "Rotten Meat"
		rotten.item_type = Item.Type.FOOD
		rotten.heal_amount = 20
		rotten.icon_path = "res://sprites/items/Food/Meat.png"
		rotten.description = "Throw into fire to cook. Raw: minimal nutrition + 3 turns poison."
		_dungeon_floor.place_item_on_floor(kill_pos, rotten)
		GameState.game_log("[color=gray]%s dropped [b]Rotten Meat[/b].[/color]" % killed_name)

func _on_action_requested(action_name: String) -> void:
	if action_name == "short_rest_begin":
		if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
			_queued_path.clear()
			_path_executing = false
			_do_rest_wait_turn()
		return
	if action_name == "toggle_ability_bar":
		_ability_bar_active = not _ability_bar_active
		return
	if action_name.begins_with("use_ability_"):
		var idx: int = action_name.substr(12).to_int()
		if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
			_use_ability_slot(idx)
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	match action_name:
		"wait":     _wait_action()
		"search":   _handle_search_request()
		"interact": _interact_action()

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
	GameState.game_log("[color=gray]You skipped a turn.[/color]")
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _do_rest_wait_turn() -> void:
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.begin_player_action()
	TurnManager.on_player_action_complete()

func _handle_search_request() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_search_request < 0.5:
		# Double press — trigger actual search
		_inspect_mode = false
		_last_search_request = -999.0
		_search_action()
	else:
		# First press — enter inspect mode
		_last_search_request = now
		_inspect_mode = true
		GameState.game_log("[color=cyan]Inspect — left-click any visible tile for info. [Esc] to cancel. Press Ctrl/Search again to search area.[/color]")

func _search_action() -> void:
	if _dungeon_floor == null:
		return
	TurnManager.begin_player_action()
	var wis_mod: int = GameState.player_stats.wis_modifier()
	var dc: int = maxi(10, 10 + GameState.current_floor / 3)
	var die1: int = randi_range(1, 20)
	var die2: int = randi_range(1, 20)
	var roll: int = maxi(die1, die2) + wis_mod
	if roll >= dc:
		var found: int = _dungeon_floor.search_around(grid_pos)
		if found > 0:
			GameState.game_log("[color=cyan]You search carefully and reveal %d trap(s)! (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [found, die1, die2, maxi(die1, die2), wis_mod, roll, dc])
		else:
			GameState.game_log("[color=gray]You search but find nothing suspicious. (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [die1, die2, maxi(die1, die2), wis_mod, roll, dc])
	else:
		GameState.game_log("[color=gray]You search but notice nothing. (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [die1, die2, maxi(die1, die2), wis_mod, roll, dc])
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _do_inspect(pos: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	if not _dungeon_floor.is_explored(pos):
		GameState.game_log("[color=gray]You haven't explored that area.[/color]")
		return
	if not _dungeon_floor.is_tile_visible(pos):
		GameState.game_log("[color=gray]You can't see that from here.[/color]")
		return
	var enemy: Enemy = _dungeon_floor.get_enemy_at(pos)
	if enemy != null and enemy.visible:
		if GameState.god_mode:
			GameState.game_log("[color=orange]%s[/color] — HP: %d/%d  AC: %d  Dmg: %d–%d  EXP: %d%s" % [
				enemy.display_name,
				enemy.stats.current_hp, enemy.stats.max_hp,
				enemy.stats.armor_class,
				enemy.stats.min_damage, enemy.stats.max_damage,
				enemy.exp_reward,
				"  [color=red]BOSS[/color]" if enemy.is_boss else ""])
		else:
			GameState.game_log("[color=orange]%s[/color] — HP: %d/%d, AC: %d" % [enemy.display_name, enemy.stats.current_hp, enemy.stats.max_hp, enemy.stats.armor_class])
		return
	var trap: Dictionary = _dungeon_floor.get_trap_at(pos)
	if not trap.is_empty() and trap.get("revealed", false):
		GameState.game_log("[color=orange]%s[/color] — revealed trap" % trap.get("name", "Trap"))
		return
	var floor_item: Item = _dungeon_floor.get_item_at(pos)
	if floor_item != null:
		GameState.game_log("[color=cyan]%s[/color] — on the floor" % floor_item.get_display_name())
		return
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(pos)
	var tile_name: String
	match tile_t:
		DungeonData.TileType.FLOOR:          tile_name = "Stone floor"
		DungeonData.TileType.WALL:           tile_name = "Stone wall"
		DungeonData.TileType.STAIRS_DOWN:    tile_name = "Stairs leading down"
		DungeonData.TileType.CHASM:          tile_name = "Chasm — deadly fall"
		DungeonData.TileType.WATER:          tile_name = "Water — slows movement"
		DungeonData.TileType.MUD:            tile_name = "Mud — slows movement"
		DungeonData.TileType.GRASS:          tile_name = "Tall grass — blocks line of sight"
		DungeonData.TileType.TRAMPLED_GRASS: tile_name = "Trampled grass"
		_:                                   tile_name = "Unknown"
	GameState.game_log("[color=gray]%s.[/color]" % tile_name)

func _passive_trap_check() -> void:
	if _dungeon_floor == null:
		return
	var wis_mod: int = GameState.player_stats.wis_modifier()
	var dc: int = maxi(8, 8 + GameState.current_floor / 2)
	var now_in_range: Array[Vector2i] = []
	for trap_pos: Vector2i in _dungeon_floor.get_unrevealed_traps():
		var diff: Vector2i = trap_pos - grid_pos
		if maxi(absi(diff.x), absi(diff.y)) > 2:
			continue
		now_in_range.append(trap_pos)
		if trap_pos in _traps_in_proximity:
			continue  # already knew it was near — don't re-roll
		var die: int = randi_range(1, 20)
		if die + wis_mod >= dc:
			_dungeon_floor.reveal_trap(trap_pos)
			if _queued_path.size() > 0:
				_queued_path.clear()
				GameState.game_log("[color=yellow]You notice something suspicious nearby and stop cautiously.[/color]")
			else:
				GameState.game_log("[color=yellow]You notice something suspicious on the floor.[/color]")
	_traps_in_proximity = now_in_range

func _interact_action(can_lock: bool = true, target: Vector2i = Vector2i(-1, -1)) -> void:
	if _dungeon_floor == null:
		return
	var dirs8: Array[Vector2i] = [
		Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)
	]
	# Priority 1: revealed trap
	# When called from RMB with a target tile, only check that exact tile.
	# When called from keyboard/debug (no target), scan all 8 neighbors.
	var trap_tiles: Array[Vector2i] = []
	if target != Vector2i(-1, -1):
		var diff: Vector2i = target - grid_pos
		if abs(diff.x) <= 1 and abs(diff.y) <= 1:
			trap_tiles.append(target)
	else:
		for d: Vector2i in dirs8:
			trap_tiles.append(grid_pos + d)
	for pos: Vector2i in trap_tiles:
		var trap: Dictionary = _dungeon_floor.get_trap_at(pos)
		if not trap.is_empty() and trap.get("revealed", false):
			_attempt_disarm(pos)
			return
	# Priority 2: door
	# When called from RMB (target provided), only interact with that exact tile if adjacent.
	# When called from F key (no target), scan all 8 neighbors for the first door.
	var door_candidates: Array[Vector2i] = []
	if target != Vector2i(-1, -1):
		var diff: Vector2i = target - grid_pos
		if abs(diff.x) <= 1 and abs(diff.y) <= 1 and _dungeon_floor.has_door_at(target):
			door_candidates.append(target)
	else:
		for d: Vector2i in dirs8:
			var pos: Vector2i = grid_pos + d
			if _dungeon_floor.has_door_at(pos):
				door_candidates.append(pos)
	for pos: Vector2i in door_candidates:
		if _dungeon_floor.is_door_locked(pos):
			if _dungeon_floor.is_door_player_locked(pos):
				# Player set this lock — can unlock freely (free action on F)
				TurnManager.begin_player_action()
				_dungeon_floor.unlock_door(pos)
				_dungeon_floor.open_door(pos)
				GameState.game_log("[color=cyan]You unlock your own lock and open the door.[/color]")
				_dungeon_floor.update_fog(grid_pos)
				TurnManager.on_player_action_complete()
			else:
				# Dungeon-generated lock — attempt to pick with Thief Tools
				if _find_thief_tools() != null:
					_attempt_disarm_lock(pos)
				else:
					GameState.game_log("[color=red]Locked. You need Thief Tools to pick this lock.[/color]")
			return
		if _dungeon_floor.is_door_open(pos):
			# F/RMB on open door → close it
			TurnManager.begin_player_action()
			_dungeon_floor.close_door(pos)
			_dungeon_floor.update_fog(grid_pos)
			TurnManager.on_player_action_complete()
			return
		# Closed unlocked door: lock if tools available, else open
		if can_lock and _find_thief_tools() != null:
			_attempt_lock_door(pos)
		else:
			TurnManager.begin_player_action()
			_dungeon_floor.open_door(pos)
			_dungeon_floor.update_fog(grid_pos)
			TurnManager.on_player_action_complete()
		return
	GameState.game_log("[color=gray]Nothing to interact with nearby.[/color]")

func _find_thief_tools() -> Item:
	for i: int in GameState.QUICKBAR_SIZE:
		var it: Item = GameState.player_quickbar[i] as Item
		if it != null and it.item_name == "Thief Tools":
			return it
	for i: int in GameState.INVENTORY_SIZE:
		var it: Item = GameState.player_inventory[i] as Item
		if it != null and it.item_name == "Thief Tools":
			return it
	return null

func _attempt_disarm(trap_pos: Vector2i) -> void:
	var tools: Item = _find_thief_tools()
	if tools == null:
		GameState.game_log("[color=red]You need Thief Tools to disarm traps![/color]")
		return

	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var s: Stats = GameState.player_stats
	var danger_rank: int = GameState.get_talent_rank("danger_sense")
	var dex_mod: int = s.dex_modifier()
	var effective_stat: String = "DEX"
	if danger_rank >= 2 and s.str_modifier() > dex_mod:
		dex_mod = s.str_modifier()
		effective_stat = "STR"
	var has_prof: bool = s.check_prof_dex
	var prof_bonus: int = s.proficiency_bonus if has_prof else 0
	var die1: int = randi_range(1, 20)
	var die2: int = die1
	if danger_rank >= 1:
		die2 = randi_range(1, 20)
	var die: int = maxi(die1, die2)
	var total: int = die + dex_mod + prof_bonus
	const DC: int = 10
	var trap: Dictionary = _dungeon_floor.get_trap_at(trap_pos)
	var trap_name: String = trap.get("name", "trap")
	var adv_tag: String = " [color=gray](Danger Sense)[/color]" if danger_rank >= 1 else ""
	var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [effective_stat, die, die1, die2, dex_mod, prof_bonus, total, DC, 1 if total >= DC else 0, 1 if danger_rank >= 1 else 0]

	if total >= DC:
		GameState.game_log("[color=green]Disarmed [b]%s[/b]!%s [url=%s]%d vs DC %d[/url][/color]" % [trap_name, adv_tag, check_meta, total, DC])
		_dungeon_floor.disarm_trap(trap_pos)
	else:
		GameState.game_log("[color=red]Failed to disarm [b]%s[/b]!%s [url=%s]%d vs DC %d[/url]%s[/color]" % [trap_name, adv_tag, check_meta, total, DC, " — Thief Tools lost!" if not GameState.invincible else ""])
		if not GameState.invincible:
			GameState.consume_one(tools)

	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _attempt_lock_door(door_pos: Vector2i) -> void:
	var tools: Item = _find_thief_tools()
	if tools == null:
		GameState.game_log("[color=gray]You need Thief Tools to lock a door.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var dex_mod: int = stats.dex_modifier()
	var die: int = randi_range(1, 20)
	var total: int = die + dex_mod
	const LOCK_DC: int = 10
	var door_world: Vector2 = Vector2(door_pos * TILE_SIZE) + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	var check_meta: String = "check:stat=DEX,die=%d,mod=%d,prof=0,total=%d,dc=%d,pass=%d" % [die, dex_mod, total, LOCK_DC, 1 if total >= LOCK_DC else 0]
	if total >= LOCK_DC:
		_dungeon_floor.lock_door(door_pos, true)  # by_player=true
		GameState.game_log("[color=green]You lock the door! [url=%s]%d vs DC %d[/url][/color]" % [check_meta, total, LOCK_DC])
		_show_float_text(door_world, "LOCKED!", Color(0.7, 0.4, 1.0))
	else:
		GameState.game_log("[color=red]Failed to lock the door [url=%s]%d vs DC %d[/url]%s[/color]" % [check_meta, total, LOCK_DC, " — Thief Tools lost!" if not GameState.invincible else ""])
		if not GameState.invincible:
			GameState.consume_one(tools)
		_show_float_text(door_world, "FAIL!", Color(1.0, 0.3, 0.3))
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

# Attempt to pick a dungeon-locked door with Thief Tools (DEX check, prof only for DEX-check-proficient classes)
func _attempt_disarm_lock(door_pos: Vector2i) -> void:
	var tools: Item = _find_thief_tools()
	if tools == null:
		GameState.game_log("[color=red]You need Thief Tools to pick this lock.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var s: Stats = GameState.player_stats
	var danger_rank: int = GameState.get_talent_rank("danger_sense")
	var dex_mod: int = s.dex_modifier()
	var effective_stat: String = "DEX"
	if danger_rank >= 2 and s.str_modifier() > dex_mod:
		dex_mod = s.str_modifier()
		effective_stat = "STR"
	var has_prof: bool = s.check_prof_dex
	var prof_bonus: int = s.proficiency_bonus if has_prof else 0
	var die1: int = randi_range(1, 20)
	var die2: int = die1
	if danger_rank >= 1:
		die2 = randi_range(1, 20)
	var die: int = maxi(die1, die2)
	var total: int = die + dex_mod + prof_bonus
	var dc: int = 10 + GameState.current_floor / 3
	var adv_tag: String = " [color=gray](Danger Sense)[/color]" if danger_rank >= 1 else ""
	var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [effective_stat, die, die1, die2, dex_mod, prof_bonus, total, dc, 1 if total >= dc else 0, 1 if danger_rank >= 1 else 0]
	var door_world: Vector2 = Vector2(door_pos * TILE_SIZE) + Vector2(TILE_SIZE * 0.5, TILE_SIZE * 0.5)
	if total >= dc:
		_dungeon_floor.unlock_door(door_pos)
		_dungeon_floor.open_door(door_pos)
		GameState.game_log("[color=green]You pick the lock!%s [url=%s]%d vs DC %d[/url][/color]" % [adv_tag, check_meta, total, dc])
		_show_float_text(door_world, "UNLOCKED!", Color(0.4, 1.0, 0.5))
	else:
		GameState.game_log("[color=red]Failed to pick the lock%s [url=%s]%d vs DC %d[/url]%s[/color]" % [adv_tag, check_meta, total, dc, " — Thief Tools lost!" if not GameState.invincible else ""])
		if not GameState.invincible:
			GameState.consume_one(tools)
		_show_float_text(door_world, "FAIL!", Color(1.0, 0.3, 0.3))
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _use_quickbar_slot(idx: int) -> void:
	if idx < 0 or idx >= GameState.QUICKBAR_SIZE:
		return
	# Delegate to item bar or ability bar depending on current HUD mode
	# The HUD manages the visual toggle; player.gd reads _ability_bar_active via signal
	if _ability_bar_active:
		_use_ability_slot(idx)
		return
	var raw = GameState.player_quickbar[idx]
	if raw == null:
		return
	GameState.use_item(raw as Item)

# Set by HUD when Tab toggles bar mode
var _ability_bar_active: bool = false

func _use_ability_slot(idx: int) -> void:
	if idx < 0 or idx >= GameState.ABILITY_BAR_SIZE:
		return
	var raw = GameState.player_ability_bar[idx]
	if raw == null:
		return
	var ab := raw as Ability
	match ab.ability_id:
		"rage":                    _activate_rage()
		"reckless_attack":         _activate_reckless()
		"danger_sense":            GameState.game_log("[color=gray]Danger Sense is passive — no activation needed.[/color]")
		"unarmored_defense_monk":  GameState.game_log("[color=gray]Unarmored Defense is passive — active when unarmored (AC = 10+DEX+WIS).[/color]")
		"martial_arts":            GameState.game_log("[color=gray]Martial Arts is passive — attack unarmed to trigger a bonus-action strike.[/color]")
		"one_with_nature":         _activate_one_with_nature(ab)
		"natural_rager":           _cycle_natural_rager_form(ab)
		"natural_sleeper":         _cycle_natural_sleeper_form(ab)
		_:                         GameState.game_log("[color=gray]%s: not yet implemented.[/color]" % ab.ability_name)

func _make_empty_bottle() -> Item:
	var b := Item.new()
	b.item_name = "Empty Bottle"
	b.item_type = Item.Type.TOOL
	b.icon_path = "res://sprites/items/Materials/BottleSmall.png"
	b.description = "An empty glass bottle. Fill it from water or mud."
	return b

func _try_fill_bottle(bottle: Item, target: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	var dist: int = maxi(absi(target.x - grid_pos.x), absi(target.y - grid_pos.y))
	if dist > 1:
		GameState.game_log("[color=gray]Too far — stand next to water or mud.[/color]")
		return
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(target)
	if tile_t != DungeonData.TileType.WATER and tile_t != DungeonData.TileType.MUD:
		GameState.game_log("[color=gray]Nothing to fill the bottle with here.[/color]")
		return
	TurnManager.begin_player_action()
	# Nat 1: bottle shatters
	var fill_roll: int = randi_range(1, 20)
	if fill_roll == 1:
		GameState.game_log("[color=red]You fumble — the bottle shatters![/color]")
		if not GameState.invincible:
			GameState.consume_one(bottle)
		GameState.inventory_changed.emit()
		_dungeon_floor.update_fog(grid_pos)
		TurnManager.on_player_action_complete()
		return
	if tile_t == DungeonData.TileType.WATER:
		bottle.item_name = "Bottle of Water"
		bottle.icon_path = "res://sprites/items/Materials/BottleMedium.png"
		bottle.description = "A bottle of dungeon water."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=cyan]You fill the bottle with water.[/color]")
	else:
		bottle.item_name = "Bottle of Mud"
		bottle.icon_path = "res://sprites/items/Materials/BottleSmall.png"
		bottle.description = "A bottle of foul mud. Maybe useful for something."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=gray]You fill the bottle with mud.[/color]")
	GameState.inventory_changed.emit()
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _find_item_by_name(item_name: String) -> Item:
	for slot: Item in GameState.player_quickbar:
		if slot != null and slot.item_name == item_name:
			return slot
	for slot: Item in GameState.player_inventory:
		if slot != null and slot.item_name == item_name:
			return slot
	return null

func _leave_blood_trail(pos: Vector2i) -> void:
	if _dungeon_floor != null and GameState.player_stats.bleeding_turns > 0:
		_dungeon_floor.place_blood_decal(pos)

func _has_advantage(enemy: Enemy) -> bool:
	if enemy.just_crossed_door:
		enemy.just_crossed_door = false
		return true
	return enemy.behavior == Enemy.Behavior.SLEEPING

func _show_float_text(world_pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = world_pos + Vector2(-16.0, -20.0)
	lbl.z_index = 10
	get_parent().add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 14.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_callback(lbl.queue_free)

func _show_surprise_mark(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var lbl := Label.new()
	lbl.text = "!"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	lbl.position = enemy.position + Vector2(-4.0, -26.0)
	lbl.z_index = 10
	get_parent().add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 10.0, 0.7)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(lbl.queue_free)

func _is_in_ranged_range(enemy: Enemy) -> bool:
	var weapon: Item = GameState.equipped_ranged
	if weapon == null or not weapon.is_ranged or _dungeon_floor == null:
		return false
	var d: Vector2i = enemy.grid_pos - grid_pos
	var dist_sq: int = d.x * d.x + d.y * d.y
	return dist_sq <= weapon.range * weapon.range \
		and _dungeon_floor.has_ranged_los(grid_pos, enemy.grid_pos)

func _ranged_attack(enemy: Enemy) -> void:
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = enemy.grid_pos.x < grid_pos.x
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")

	var weapon: Item = GameState.equipped_ranged
	_show_projectile(enemy.position, weapon)

	var dex_mod: int = stats.dex_modifier()
	var prof: int = stats.proficiency_bonus
	var weapon_bonus: int = (weapon.bonus_damage if weapon != null else 0) + prof
	# Advantage: target sleeping or just entered FOV this turn
	var adv: bool = _has_advantage(enemy)
	# Disadvantage: ranged weapon fired at melee range (Chebyshev distance 1)
	var d_vec: Vector2i = enemy.grid_pos - grid_pos
	var disadv: bool = maxi(abs(d_vec.x), abs(d_vec.y)) <= 1
	# adv + disadv cancel each other → normal 1d20
	var die1: int = randi_range(1, 20)
	var die2: int = die1
	var die: int = die1
	if adv and not disadv:
		die2 = randi_range(1, 20)
		die = maxi(die1, die2)
	elif disadv and not adv:
		die2 = randi_range(1, 20)
		die = mini(die1, die2)
	var roll: int = die + dex_mod + weapon_bonus
	var is_crit: bool = die == 20
	var is_nat_one: bool = die == 1

	# Consume throwing weapon before resolving hit (it was thrown regardless)
	if weapon != null and weapon.consumes_on_ranged and not GameState.invincible:
		weapon.quantity -= 1
		GameState.inventory_changed.emit()
		if weapon.quantity <= 0:
			GameState.equipment["ranged"] = null
			GameState.recalculate_stats()
			GameState.equipment_changed.emit()
			GameState.game_log("[color=gray]Last throwing dagger used.[/color]")

	var r_wpn_enh: int = weapon.bonus_damage if weapon != null else 0
	var hit_meta: String = "rhit:die=%d,d1=%d,d2=%d,dex=%d,prof=%d,wpn=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, dex_mod, prof, r_wpn_enh, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0]

	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("You shoot at [color=orange]%s[/color] — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		if _dungeon_floor != null:
			_dungeon_floor.update_fog(grid_pos)
		_handle_post_attack_turn()
		return

	AudioManager.play("crit" if is_crit else "hit_enemy")
	_flash_hit(enemy)
	if adv and not disadv:
		_show_surprise_mark(enemy)
	var r_die_roll: int = randi_range(stats.base_min_damage, stats.base_max_damage)
	var r_pre_crit: int = r_die_roll + r_wpn_enh + dex_mod
	if is_crit:
		r_pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(r_pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)

	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,dex=%d,rage=0,crit=%d,final=%d" % [
		r_die_roll, stats.base_min_damage, stats.base_max_damage, r_wpn_enh, dex_mod, 1 if is_crit else 0, actual]
	var r_dmg_type: String = weapon.damage_type if weapon != null and not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var r_type_tag: String = " [color=gray]%s[/color]" % r_dmg_type
	var r_god_hp: String = " [color=gray][%d/%d HP][/color]" % [enemy.stats.current_hp, enemy.stats.max_hp] if GameState.god_mode and not enemy.stats.is_dead() else ""
	if is_crit:
		GameState.game_log("[color=red]CRIT![/color] You [url=%s]shoot[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [hit_meta, enemy.display_name, dmg_meta, actual, r_type_tag, r_god_hp])
	else:
		GameState.game_log("You [url=%s]shoot[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [hit_meta, enemy.display_name, dmg_meta, actual, r_type_tag, r_god_hp])

	if enemy.stats.is_dead():
		_finish_kill(enemy)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	_handle_post_attack_turn()

func _show_projectile(target_world_pos: Vector2, weapon: Item) -> void:
	if weapon == null:
		return
	var proj_path: String
	var tumble: bool = false
	match weapon.item_name:
		"Throwing Daggers": proj_path = "res://sprites/weapons/weapon_knife.png"
		"Crossbow":
			proj_path = ARROW_SPRITE
			tumble = true
		_: proj_path = ARROW_SPRITE

	AudioManager.play("shoot")
	var tex: Texture2D = load(proj_path)
	var from: Vector2 = _tile_center(grid_pos)
	var angle: float = (target_world_pos - from).angle()
	var direction: Vector2 = (target_world_pos - from).normalized()
	var dur: float = 0.18

	# Ghost trail sprites (i=1,2 trail behind main i=0)
	const ALPHAS: Array = [1.0, 0.5, 0.22]
	const DELAYS: Array = [0.0, 0.028, 0.055]
	for i: int in 3:
		var sp := Sprite2D.new()
		sp.texture = tex
		sp.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		sp.scale = Vector2(0.5, 0.5)
		sp.position = from - direction * (i * 5.0)
		sp.rotation = angle
		sp.z_index = 5 - i
		sp.modulate.a = ALPHAS[i]
		get_parent().add_child(sp)
		var t := sp.create_tween()
		var d: float = dur - DELAYS[i]
		if DELAYS[i] > 0.0:
			t.tween_interval(DELAYS[i])
		t.tween_property(sp, "position", target_world_pos, d)
		if tumble:
			t.parallel().tween_property(sp, "rotation", angle + TAU, d)
		if i == 0:
			t.parallel().tween_property(sp, "modulate:a", 0.0, d * 0.3).set_delay(d * 0.7)
		t.tween_callback(sp.queue_free)

func _ranged_attack_tile(target_pos: Vector2i) -> void:
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = target_pos.x < grid_pos.x
	$AnimatedSprite2D.play("hit")
	await $AnimatedSprite2D.animation_finished
	$AnimatedSprite2D.play("idle")
	var weapon: Item = GameState.equipped_ranged
	var target_world: Vector2 = Vector2(target_pos.x * 16 + 8, target_pos.y * 16 + 8)
	_show_projectile(target_world, weapon)
	if weapon != null and weapon.consumes_on_ranged and not GameState.invincible:
		weapon.quantity -= 1
		GameState.inventory_changed.emit()
		if weapon.quantity <= 0:
			GameState.equipment["ranged"] = null
			GameState.recalculate_stats()
			GameState.equipment_changed.emit()
			GameState.game_log("[color=gray]Last throwing dagger thrown.[/color]")
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	_handle_post_attack_turn()


func _on_throw_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	_tool_item = null
	if _throw_item != null:
		_throw_item = item
		return
	_throw_item = item
	GameState.game_log("[color=yellow]Throw [b]%s[/b] — left-click target tile. [Esc] to cancel.[/color]" % item.item_name)

func _on_tool_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	_throw_item = null
	_tool_item = item
	if item.item_name == "Empty Bottle":
		GameState.game_log("[color=cyan]Empty Bottle — right-click on adjacent water or mud to fill. [Esc] to cancel.[/color]")
	else:
		GameState.game_log("[color=yellow]Thief Tools — click an adjacent revealed trap to disarm. [Esc] to cancel.[/color]")

func _do_throw(pos: Vector2i) -> void:
	var item: Item = _throw_item
	_throw_item = null
	if _dungeon_floor == null:
		return
	var _found: bool = false
	for _s in GameState.player_quickbar:
		if _s == item:
			_found = true
			break
	if not _found:
		for _s in GameState.player_inventory:
			if _s == item:
				_found = true
				break
	if not _found:
		GameState.game_log("[color=gray]Throw cancelled — item no longer in inventory.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("throw_item")
	if _dungeon_floor.has_door_at(pos) and not _dungeon_floor.is_door_open(pos):
		_dungeon_floor.open_door(pos)
	var trap: Dictionary = _dungeon_floor.get_trap_at(pos)
	var is_fire: bool = not trap.is_empty() and trap.get("name", "") == "Fire Trap" and trap.get("revealed", false)
	if is_fire and item.item_name == "Rotten Meat":
		GameState.consume_one(item)
		var cooked: Item = _dungeon_floor.cook_rotten_meat(pos)
		_dungeon_floor.place_item_on_floor(pos, cooked)
		GameState.game_log("[color=orange]You throw the meat into the fire — it sizzles and cooks! [b]Cooked Meat[/b] landed where the trap was.[/color]")
	else:
		var dropped := Item.new()
		dropped.item_name = item.item_name
		dropped.item_type = item.item_type
		dropped.heal_amount = item.heal_amount
		dropped.icon_path = item.icon_path
		dropped.description = item.description
		dropped.quantity = 1
		GameState.consume_one(item)
		_dungeon_floor.place_item_on_floor(pos, dropped)
		GameState.game_log("[color=gray]You throw [b]%s[/b].[/color]" % dropped.item_name)
	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _open_short_rest() -> void:
	if GameState.short_rests_remaining <= 0:
		GameState.game_log("[color=gray]No short rests remaining on this floor. Descend to refresh.[/color]")
		return
	GameState.short_rest_open = true
	var panel_script = load("res://scripts/ui/short_rest_panel.gd")
	get_tree().root.add_child(panel_script.new())

func _open_talent_picker() -> void:
	if GameState._class_talents.is_empty():
		return
	var picker = load("res://scripts/ui/talent_picker.gd").new()
	get_tree().root.add_child(picker)


# ── Wild Heart helpers ────────────────────────────────────────────────────────

func _activate_one_with_nature(ab: Ability) -> void:
	var rank: int = GameState.get_talent_rank("one_with_nature")
	if ab.uses_remaining <= 0:
		GameState.game_log("[color=gray]One with Nature: no charge available (rest to restore).[/color]")
		return
	if GameState.player_companion != null and is_instance_valid(GameState.player_companion):
		_dismiss_companion()
	_summon_companion(rank)
	if not GameState.invincible:
		ab.uses_remaining = 0
	GameState.ability_bar_changed.emit()

func _summon_companion(rank: int) -> void:
	if _dungeon_floor == null:
		return
	var stats_data: Dictionary = GameState.WILD_HEART_COMPANION_STATS.get(rank, {})
	var companion := Companion.new()
	companion.configure(stats_data)
	var spawn_pos: Vector2i = _find_free_adjacent()
	if spawn_pos == Vector2i(-1, -1):
		GameState.game_log("[color=gray]No room to summon companion![/color]")
		return
	_dungeon_floor.spawn_companion(companion, spawn_pos)
	GameState.player_companion = companion
	GameState.game_log("[color=lime]You summon a %s to fight by your side![/color]" % companion.animal_name)

func _dismiss_companion() -> void:
	var comp = GameState.player_companion
	if comp == null or not is_instance_valid(comp):
		GameState.player_companion = null
		return
	if _dungeon_floor != null:
		_dungeon_floor.remove_companion(comp)
	TurnManager.unregister_enemy(comp)
	GameState.game_log("[color=gray]%s is dismissed.[/color]" % comp.animal_name)
	comp.queue_free()
	GameState.player_companion = null

func _find_free_adjacent() -> Vector2i:
	if _dungeon_floor == null:
		return Vector2i(-1, -1)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for d: Vector2i in dirs:
		var p: Vector2i = grid_pos + d
		if _dungeon_floor.is_walkable_for_companion(p):
			return p
	return Vector2i(-1, -1)

func _cycle_natural_rager_form(ab: Ability) -> void:
	var forms: PackedStringArray = ["Bear", "Eagle", "Wolf"]
	var idx: int = forms.find(GameState.natural_rager_form)
	GameState.natural_rager_form = forms[(idx + 1) % forms.size()]
	ab.description = GameState._build_natural_rager_description()
	GameState.ability_bar_changed.emit()
	GameState.game_log("[color=orange]Natural Rager: switched to %s Form.[/color]" % GameState.natural_rager_form)

func _cycle_natural_sleeper_form(ab: Ability) -> void:
	var forms: PackedStringArray = ["Owl", "Panther", "Salmon"]
	var idx: int = forms.find(GameState.natural_sleeper_form)
	GameState.natural_sleeper_form = forms[(idx + 1) % forms.size()]
	ab.description = GameState._build_natural_sleeper_description()
	GameState.ability_bar_changed.emit()
	GameState.game_log("[color=cyan]Natural Sleeper: switched to %s Form.[/color]" % GameState.natural_sleeper_form)
