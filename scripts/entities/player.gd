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

var _throw_item: Item = null

var _regen_counter: int = 0
const REGEN_TURNS: int = 10

func _ready() -> void:
	stats = GameState.player_stats
	z_index = 3
	_setup_animations()
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_action_requested.connect(_on_action_requested)
	GameState.player_throw_primed.connect(_on_throw_primed)
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
	if s.current_hp < s.max_hp and not GameState.is_game_over \
			and GameState.hunger_state != GameState.HungerState.STARVING:
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
		if key.physical_keycode == KEY_ESCAPE:
			if _throw_item != null:
				_throw_item = null
				GameState.game_log("[color=gray]Throw cancelled.[/color]")
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
			KEY_F: _interact_action()
			KEY_CTRL: _search_action()
			KEY_1: _use_quickbar_slot(0)
			KEY_2: _use_quickbar_slot(1)
			KEY_3: _use_quickbar_slot(2)
			KEY_4: _use_quickbar_slot(3)
			KEY_5: _use_quickbar_slot(4)
			KEY_6: _use_quickbar_slot(5)
			KEY_7: _use_quickbar_slot(6)
			KEY_8: _use_quickbar_slot(7)
			KEY_9: _use_quickbar_slot(8)

	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if not mb.pressed:
			return
		if _dungeon_floor == null:
			return
		var world_pos: Vector2 = get_global_mouse_position()
		var clicked: Vector2i = Vector2i(int(world_pos.x / TILE_SIZE), int(world_pos.y / TILE_SIZE))

		if mb.button_index == MOUSE_BUTTON_RIGHT:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_interact_action()
			return

		if mb.button_index != MOUSE_BUTTON_LEFT:
			return

		# Throw mode — consume left-click for the toss
		if _throw_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_do_throw(clicked)
			else:
				_throw_item = null
			return

		if clicked == grid_pos:
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
		if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD \
				or GameState.player_stats.slowed_turns > 0:
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
		_check_pickup()
		var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
		if not trap.is_empty():
			await _dungeon_floor.trigger_trap(grid_pos, self)  # push trap still awaits; others return instantly
	TurnManager.on_player_action_complete()
	if is_stairs:
		_dungeon_floor.on_player_reached_stairs.call_deferred()
		return
	# Difficult terrain or slowed: costs 2 turns per step
	var tile_t: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	if tile_t == DungeonData.TileType.WATER or tile_t == DungeonData.TileType.MUD \
			or GameState.player_stats.slowed_turns > 0:
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
		var kill_pos: Vector2i = enemy.grid_pos
		var killed_name: String = enemy.display_name
		_dungeon_floor.remove_enemy(enemy)
		enemy.die()
		if was_boss:
			_dungeon_floor.drop_boss_loot(kill_pos)
		# 20% Rotten Meat drop from undead humanoids
		const UNDEAD_NAMES: Array = ["Tiny Zombie", "Goblin", "Skeleton", "Orc Warrior", "Orc Shaman", "Masked Orc", "Wogol"]
		if killed_name in UNDEAD_NAMES and randf() < 0.20:
			var rotten := Item.new()
			rotten.item_name = "Rotten Meat"
			rotten.item_type = Item.Type.FOOD
			rotten.heal_amount = 20
			rotten.icon_path = "res://sprites/items/Sprites trial/Food/Meat.png"
			rotten.description = "Throw into fire to cook. Raw: minimal nutrition + 3 turns poison."
			_dungeon_floor.place_item_on_floor(kill_pos, rotten)
			GameState.game_log("[color=gray]%s dropped [b]Rotten Meat[/b].[/color]" % killed_name)
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
		"wait":     _wait_action()
		"search":   _search_action()
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

func _interact_action() -> void:
	if _dungeon_floor == null:
		return
	var dirs8: Array[Vector2i] = [
		Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)
	]
	# Priority 1: revealed trap
	for d: Vector2i in dirs8:
		var pos: Vector2i = grid_pos + d
		var trap: Dictionary = _dungeon_floor.get_trap_at(pos)
		if not trap.is_empty() and trap.get("revealed", false):
			_attempt_disarm(pos)
			return
	# Priority 2: door — toggle open/close
	for d: Vector2i in dirs8:
		var pos: Vector2i = grid_pos + d
		if _dungeon_floor.has_door_at(pos):
			TurnManager.begin_player_action()
			if _dungeon_floor.is_door_open(pos):
				_dungeon_floor.close_door(pos)
			else:
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
	var roll: int = randi_range(1, 20)
	var dex_mod: int = GameState.player_stats.dex_modifier()
	var total: int = roll + dex_mod
	const DC: int = 10
	var trap: Dictionary = _dungeon_floor.get_trap_at(trap_pos)
	var trap_name: String = trap.get("name", "trap")

	if total >= DC:
		GameState.game_log("[color=green]Disarmed [b]%s[/b]! (d20 %d+%d=%d vs DC %d)[/color]" % [trap_name, roll, dex_mod, total, DC])
		_dungeon_floor.disarm_trap(trap_pos)
	else:
		GameState.game_log("[color=red]Failed to disarm [b]%s[/b] (d20 %d+%d=%d vs DC %d) — Thief Tools lost![/color]" % [trap_name, roll, dex_mod, total, DC])
		GameState.consume_one(tools)

	_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _use_quickbar_slot(idx: int) -> void:
	if idx < 0 or idx >= GameState.QUICKBAR_SIZE:
		return
	var raw = GameState.player_quickbar[idx]
	if raw == null:
		return
	GameState.use_item(raw as Item)

func _leave_blood_trail(pos: Vector2i) -> void:
	if _dungeon_floor != null and GameState.player_stats.bleeding_turns > 0:
		_dungeon_floor.place_blood_decal(pos)

func _on_throw_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or _path_executing:
		return
	_throw_item = item
	GameState.game_log("[color=yellow]Throw [b]%s[/b] — left-click target tile. [Esc] to cancel.[/color]" % item.item_name)

func _do_throw(pos: Vector2i) -> void:
	var item: Item = _throw_item
	_throw_item = null
	if _dungeon_floor == null:
		return
	TurnManager.begin_player_action()
	var trap: Dictionary = _dungeon_floor.get_trap_at(pos)
	var is_fire: bool = not trap.is_empty() and trap.get("name", "") == "Fire Trap"
	if is_fire and item.item_name == "Rotten Meat":
		GameState.consume_one(item)
		var cooked: Item = _dungeon_floor.cook_rotten_meat(pos)
		if not GameState.add_item(cooked):
			_dungeon_floor.place_item_on_floor(grid_pos, cooked)
		GameState.game_log("[color=orange]You throw the meat into the fire — it sizzles and cooks! [b]Cooked Meat[/b] obtained.[/color]")
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
