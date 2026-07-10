class_name Player
extends Entity

const KNIGHT_PATH := "res://sprites/characters/"
const UNDEAD_NAMES: Array = ["Tiny Zombie", "Goblin", "Skeleton", "Orc Warrior", "Orc Shaman", "Masked Orc", "Wogol"]

var _dungeon_floor: Node

# ── Split-out modules (composition child-nodes / static helper) ──────────────────────────────
# See "Split-out modules" in scripts/entities/CLAUDE.md for what moved where and why.
var _wild_heart: PlayerWildHeart
var _zealot: PlayerZealot
var _berserker: PlayerBerserker
var _scarred_warrior: PlayerScarredWarrior
var _base_talents: PlayerBaseTalents
var _ammo: PlayerAmmo
var _throw_tool: PlayerThrowTool
var _thief_tools: PlayerThiefTools
var _vfx: PlayerVfx
var _actions: PlayerActions
var _ranged: PlayerRanged

var _queued_path: Array[Vector2i] = []
var _path_executing: bool = false
var _last_move_dir := Vector2i.ZERO
var _target_enemy: Enemy = null

var _prev_dir: Vector2i = Vector2i.ZERO  # direction held in the previous WAITING_FOR_INPUT frame
var _interrupted: bool = false           # set when enemy seen mid-hold; cleared only on key release

var _throw_item: Item = null
var _tool_item: Item = null
var _inspect_mode: bool = false
var _rest_interrupt_shown: bool = false

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
# Baseline: lasts 1 turn, refreshed to 1 by attacking or being attacked (unconditional).
# _rage_attacked_this_turn: set in _bump_attack when raging + STR weapon; cleared at turn start.
var _is_raging: bool = false
var _rage_turns: int = 0
var _rage_attacked_this_turn: bool = false

# ── Wild Heart state (Tier 2) ─────────────────────────────────────────────────
# Eagle Natural Rager: per-round free-move cap (max 1×/round). Only resets on REAL turns.
var _eagle_free_move_used: bool = false
# Flag set before revert_to_waiting() so _on_turn_started() knows it's a reverted (non-enemy) turn.
# Per-round caps are NOT reset on reverted turns — only after enemies go.
var _reverted_this_round: bool = false

# ── World Tree state (Tier 2) ─────────────────────────────────────────────────
# Ironwood Bark R3: bonus damage from temp HP snapshotted at turn start, consumed by next attack.
var _ironwood_bark_bonus_pending: int = 0
# Grip of the Forest: once-per-turn hook-targeting mode (armed via ability bar, resolved on click).
var _hook_mode_active: bool = false
var _grip_used_this_turn: bool = false

# ── Weapon mastery state ────────────────────────────────────────────────────────
# Vex (Short Bow): after a Short-Bow hit, grants Advantage on the very next attack THIS ROUND
# against that exact same enemy (any attack type — melee, cleave, ranged). Consumed on the
# next attack attempt regardless of hit/miss. Cleared at a real new-round turn start; survives
# a revert_to_waiting() free-action chain (Rager move/attack, Eagle) within the same round.
var _vex_adv_target: Enemy = null

# ── Opportunity Attack state ──────────────────────────────────────────────────
# Once-per-round reaction cap (5e: one reaction per round). Reset in _on_turn_started()'s
# "not came_from_revert" block alongside the other per-round caps — must survive
# revert_to_waiting() free-action chains and only reset after enemies actually take a round.
var _oa_used_this_round: bool = false


# ── Equip action tracking ─────────────────────────────────────────────────────
var _pending_equip_turn: bool = false  # set by equip_action_taken signal; consumed in next action gate


func _ready() -> void:
	stats = GameState.player_stats
	is_friendly = true
	z_index = 3
	_setup_animations()

	_wild_heart = PlayerWildHeart.new(); _wild_heart.player = self; add_child(_wild_heart)
	_zealot = PlayerZealot.new(); _zealot.player = self; add_child(_zealot)
	_berserker = PlayerBerserker.new(); _berserker.player = self; add_child(_berserker)
	_scarred_warrior = PlayerScarredWarrior.new(); _scarred_warrior.player = self; add_child(_scarred_warrior)
	_base_talents = PlayerBaseTalents.new(); _base_talents.player = self; add_child(_base_talents)
	GameState.force_rage_end.connect(_end_rage)
	_ammo = PlayerAmmo.new(); _ammo.player = self; add_child(_ammo)
	_throw_tool = PlayerThrowTool.new(); _throw_tool.player = self; add_child(_throw_tool)
	_thief_tools = PlayerThiefTools.new(); _thief_tools.player = self; add_child(_thief_tools)
	_vfx = PlayerVfx.new(); _vfx.player = self; add_child(_vfx)
	_actions = PlayerActions.new(); _actions.player = self; add_child(_actions)
	_ranged = PlayerRanged.new(); _ranged.player = self; add_child(_ranged)

	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_action_requested.connect(_on_action_requested)
	GameState.player_throw_primed.connect(_throw_tool.on_throw_primed)
	GameState.player_tool_primed.connect(_throw_tool.on_tool_primed)
	GameState.player_died.connect(_on_player_died)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.camera_recenter_requested.connect(_reset_camera_offset)
	GameState.screen_shake.connect(_vfx.screen_shake)
	GameState.equip_action_taken.connect(_on_equip_action_taken)
	GameState.equipment_changed.connect(_on_equipment_changed)
	GameState.potion_drunk.connect(func():
		if GameState.add_item(_throw_tool.make_empty_bottle()):
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
	# Determine whether this is a reverted turn (Eagle free action) or a real new round.
	var came_from_revert: bool = _reverted_this_round
	_reverted_this_round = false
	# Per-round caps only reset on REAL turns (after enemies resolve).
	# On reverted turns, Eagle's free-move flag persists so it can't fire again this round.
	if not came_from_revert:
		_eagle_free_move_used = false
		_grip_used_this_turn = false
		_vex_adv_target = null
		_oa_used_this_round = false
		_berserker.clear_turn_start_ac_bonus()
		_berserker.tick_frenzied_killer()
		# Zealot Strike deactivates with no effect if the turn ends without a melee attack.
		_zealot.zealot_strike_armed = false
		# Battlefield Expert R3: reads "was hit last turn" — same flag the rage-tick block below
		# reads. Read-only here (not cleared) so Rage's own combat_last_turn check further down
		# still sees the value; the flag is cleared once, after both readers, further below.
		_base_talents.tick_free_sidestep(GameState.player_was_hit_this_turn)
	GameState.ability_bar_changed.emit()
	# Natural Sleeper R2: 2d6 temp HP (replace, not stack) if standing in form's terrain.
	# Only fires on real turns, not on reverted turns.
	if not came_from_revert and GameState.wild_heart_sleeper_active:
		var _ns_rank_ts: int = GameState.get_talent_rank("expanded_forms")
		if _ns_rank_ts >= 2 and _dungeon_floor != null:
			var _af: String = GameState.active_sleeper_form
			var _ct: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
			var _terrain_match: bool = (
				(_af == "Panther" and _ct == DungeonData.TileType.MUD) or
				(_af == "Salmon" and _ct == DungeonData.TileType.WATER) or
				(_af == "Owl" and _ct == DungeonData.TileType.CHASM)
			)
			if _terrain_match:
				var _thp: int = Rng.roll(6) + Rng.roll(6)
				GameState.player_stats.temp_hp = _thp  # replace, not stack
				GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
				GameState.game_log("[color=cyan]%s Form: %d temp HP (2d6).[/color]" % [_af, _thp])

	# Bloodied Regen (Scarred Warrior): temp HP each real turn while Bloodied.
	if not came_from_revert:
		_scarred_warrior.tick_bloodied_regen()

	# Ironwood Bark R2/R3: mutually exclusive per turn — both ranks read the SAME pre-turn
	# temp HP snapshot, so R2's refresh this tick cannot also trigger R3 this same tick.
	_ironwood_bark_bonus_pending = 0
	if not came_from_revert:
		var _ib_rank: int = GameState.get_talent_rank("ironwood_bark")
		if _ib_rank >= 2 and _is_raging:
			var _ib_snapshot_thp: int = GameState.player_stats.temp_hp
			if _ib_snapshot_thp == 0:
				var _ib_thp: int = Rng.roll(6) * GameState.player_stats.rage_bonus_damage
				GameState.player_stats.temp_hp = _ib_thp
				GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
				GameState.game_log("[color=cyan]Ironwood Bark: %d temp HP (1d6 × rage bonus).[/color]" % _ib_thp)
			elif _ib_rank >= 3:
				_ironwood_bark_bonus_pending = _ib_snapshot_thp
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

	# Tick rage duration. Baseline: lasts 1 turn, refreshed to 1 turn by attacking (hit or miss)
	# or being attacked (hit or miss) last turn (Masochist Monster R3 can further override expiry
	# — see below). Gated on real turns only — a reverted/free-action turn (Frenzy, Battlefield
	# Expert's free side-step) hasn't actually let a round pass, so it must never tick Rage down
	# or count as "no combat this turn".
	if _is_raging and not came_from_revert:
		var combat_last_turn: bool = _rage_attacked_this_turn or GameState.player_was_hit_this_turn or GameState.player_attacked_this_turn
		var masochist_r3_active: bool = GameState.get_talent_rank("masochist_monster") >= 3 \
				and not _fov_this_turn.is_empty()
		if masochist_r3_active:
			pass  # Masochist Monster R3: Rage doesn't expire while an enemy is in FOV
		elif combat_last_turn:
			_rage_turns = 1
		else:
			_rage_turns -= 1
		GameState.rage_turns_remaining = _rage_turns
		GameState.ability_bar_changed.emit()
		if _rage_turns <= 0:
			_end_rage()
			GameState.game_log("[color=gray]Your Rage fades.[/color]")
	# Cleared once per real turn regardless of Rage state, so Battlefield Expert R3's "was hit
	# last turn" check (read further up) stays scoped to "last turn" instead of leaking true
	# forever after the first hit of the run.
	if not came_from_revert:
		_rage_attacked_this_turn = false
		GameState.player_was_hit_this_turn = false
		GameState.player_attacked_this_turn = false

	# Short rest in progress — player waits in place
	if GameState.short_rest_active:
		if GameState.short_rest_open:
			return  # Panel open — freeze until player clicks Continue/Abort
		if not _fov_this_turn.is_empty() and not _rest_interrupt_shown:
			_rest_interrupt_shown = true
			GameState.short_rest_open = true
			var panel_script = load("res://scripts/ui/rest_interrupt_panel.gd")
			get_tree().root.call_deferred("add_child", panel_script.new())
			_actions.do_rest_wait_turn()
			return
		GameState.short_rest_turns_remaining -= 1
		if GameState.short_rest_turns_remaining <= 0:
			GameState.short_rest_active = false
			_rest_interrupt_shown = false
			if GameState.long_rest_pending:
				GameState.long_rest_pending = false
				GameState.short_rest_pending_heal = 0
				GameState.long_rest()
				GameState.mastery_picker_open = true
				var prompt_script = load("res://scripts/ui/mastery_reselect_prompt.gd")
				get_tree().root.call_deferred("add_child", prompt_script.new())
			else:
				var pending_heal: int = GameState.short_rest_pending_heal
				GameState.short_rest_pending_heal = 0
				var before_hp: int = GameState.player_stats.current_hp
				var bruiser_bonus: int = GameState.heal(pending_heal)
				var healed: int = GameState.player_stats.current_hp - before_hp
				AudioManager.play("rest")
				var bonus_sources: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus, "color": "cyan"}])
				var _hm: String = "heal:dice=0,sides=0,con=0,roll=0,bonus=%s,total=%d" % [bonus_sources, healed]
				GameState.game_log("[color=cyan]You finish your short rest and recover [url=%s][b]+%d HP[/b][/url].[/color]" % [_hm, healed])
				GameState.short_rest_completed.emit()
			GameState.short_rest_changed.emit()
		_actions.do_rest_wait_turn()
		return

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
	if GameState.is_game_over or GameState.inventory_open or GameState.short_rest_open \
			or GameState.subclass_picker_open or not GameState.class_selected:
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
			if not GameState.short_rest_open and not GameState.mastery_picker_open \
					and not GameState.subclass_picker_open:
				GameState.inventory_toggle.emit()
			return
		# T key opens talent screen regardless of turn phase; bypasses phase gate
		if key.physical_keycode == KEY_T:
			if not GameState.inventory_open and not GameState.short_rest_open \
					and not GameState.short_rest_active and not GameState.talent_picker_open \
					and not GameState.mastery_picker_open and not GameState.subclass_picker_open:
				_actions.open_talent_picker()
				get_viewport().set_input_as_handled()
			return
		if GameState.inventory_open or GameState.short_rest_open or GameState.short_rest_active \
				or GameState.talent_picker_open or GameState.mastery_picker_open \
				or GameState.subclass_picker_open:
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
			if _hook_mode_active:
				_hook_mode_active = false
				GameState.game_log("[color=gray]Grip of the Forest cancelled.[/color]")
			if _berserker.frenzy_mode_active:
				_berserker.frenzy_mode_active = false
				GameState.game_log("[color=gray]Frenzy cancelled.[/color]")
			if _scarred_warrior.limit_break_mode_active:
				_scarred_warrior.limit_break_mode_active = false
				GameState.game_log("[color=gray]Limit Break cancelled.[/color]")
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
			KEY_SPACE, KEY_PERIOD, KEY_KP_5: _actions.wait_action()
			KEY_CTRL: _actions.handle_search_request()
			KEY_ALT: _actions.open_short_rest()
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
					if not _ranged.is_ranged_target_in_range(rw, pending):
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % DungeonFloor.FOV_RADIUS)
						return
					if not _dungeon_floor.has_ranged_los(grid_pos, pending):
						GameState.game_log("[color=gray]No clear shot to target.[/color]")
						return
					var enemy_shift: Enemy = _dungeon_floor.get_enemy_at(pending)
					if enemy_shift != null:
						_ranged.ranged_attack(enemy_shift)
					else:
						_ranged.ranged_attack_tile(pending)
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
					_throw_tool.try_fill_bottle(bottle, clicked)
				else:
					var had_tool: bool = _tool_item != null
					_tool_item = null
					_actions.interact_action(had_tool, clicked)
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
				_actions.do_inspect(clicked)
			return

		# Grip of the Forest hook-targeting mode
		if _hook_mode_active:
			_hook_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var rank_h: int = GameState.get_talent_rank("grip_of_the_forest")
				var hook_range: int = [0, 3, 4, 5][mini(rank_h, 3)]
				var target_enemy: Enemy = _dungeon_floor.get_enemy_at(clicked)
				if target_enemy == null:
					GameState.game_log("[color=gray]Grip of the Forest: no target there.[/color]")
				else:
					var dv: Vector2i = clicked - grid_pos
					if maxi(absi(dv.x), absi(dv.y)) > hook_range:
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % hook_range)
					elif not _dungeon_floor.has_ranged_los(grid_pos, clicked):
						GameState.game_log("[color=gray]No clear line to target.[/color]")
					else:
						_execute_hook(target_enemy)
			return

		# Frenzy targeting mode (Berserker) — melee only, must be adjacent.
		if _berserker.frenzy_mode_active:
			_berserker.frenzy_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var frenzy_target: Enemy = _dungeon_floor.get_enemy_at(clicked)
				if frenzy_target == null:
					GameState.game_log("[color=gray]Frenzy: no target there.[/color]")
				else:
					var dv2: Vector2i = clicked - grid_pos
					if maxi(absi(dv2.x), absi(dv2.y)) > 1:
						GameState.game_log("[color=gray]Frenzy: target must be adjacent.[/color]")
					else:
						_berserker.execute_frenzy(frenzy_target)
			return

		# Limit Break targeting mode (Scarred Warrior) — range depends on Enough is Enough rank.
		if _scarred_warrior.limit_break_mode_active:
			_scarred_warrior.limit_break_mode_active = false
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing and _dungeon_floor != null:
				var lb_target: Enemy = _dungeon_floor.get_enemy_at(clicked)
				if lb_target == null:
					GameState.game_log("[color=gray]Limit Break: no target there.[/color]")
				else:
					var lb_rank: int = GameState.get_talent_rank("enough_is_enough")
					var lb_range: int = 5 if lb_rank >= 3 else 1
					var dv3: Vector2i = clicked - grid_pos
					if maxi(absi(dv3.x), absi(dv3.y)) > lb_range:
						GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % lb_range)
					elif lb_range > 1 and not _dungeon_floor.has_ranged_los(grid_pos, clicked):
						GameState.game_log("[color=gray]No clear line to target.[/color]")
					else:
						_scarred_warrior.execute_limit_break(lb_target)
			return

		# Tool targeting mode — route by tool type
		if _tool_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				var dist: int = maxi(absi(clicked.x - grid_pos.x), absi(clicked.y - grid_pos.y))
				if dist <= 1:
					var tool: Item = _tool_item
					_tool_item = null
					if tool.item_name == "Empty Bottle":
						_throw_tool.try_fill_bottle(tool, clicked)
					else:
						_actions.interact_action(true, clicked)  # Thief Tools: door lock / trap disarm / nothing
				else:
					GameState.game_log("[color=gray]Too far — click an adjacent tile.[/color]")
			else:
				_tool_item = null
			return

		# Throw mode — consume left-click for the toss (immediate intentional click)
		if _throw_item != null:
			if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT and not _path_executing:
				_throw_tool.do_throw(clicked)
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

			if chase_path.size() <= CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike")):
				# In melee (or extended reach) range — attack
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
			_resolve_enemy_opportunity_attacks(prev_c, next)
			if GameState.is_game_over:
				_target_enemy = null
				break
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
				_vfx.leave_blood_trail(prev_c)
				if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
					_dungeon_floor.destroy_grass(grid_pos)
				_actions.check_pickup()
				_play_footstep_sound()
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
				_ranged.ranged_attack(enemy_there)
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

		_resolve_enemy_opportunity_attacks(prev_p, next)
		if GameState.is_game_over:
			_queued_path.clear()
			break
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
			_vfx.leave_blood_trail(prev_p)
			if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
				_dungeon_floor.destroy_grass(grid_pos)
				_dungeon_floor.update_fog(grid_pos)
			_actions.check_pickup()
			_play_footstep_sound()
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

# Opportunity Attacks: called on every voluntary player-move step (keyboard _try_move and both
# _execute_queued_path bodies) BEFORE the move tween starts, while the player is still on `prev`.
# Each threatening enemy that isn't SLEEPING, can see `prev`, and hasn't used its reaction this
# round gets one free inline attack — Retaliation-style, no TurnManager involvement, no phase
# change. See docs/architecture/opportunity-attacks-design.md.
func _resolve_enemy_opportunity_attacks(prev: Vector2i, next: Vector2i) -> void:
	if GameState.noclip or _dungeon_floor == null:
		return
	var evading: bool = GameState.player_evades_opportunity_attacks
	var evaded_any: bool = false
	for e: Enemy in _dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead() or e.behavior == Enemy.Behavior.SLEEPING:
			continue
		if e.oa_used_this_round:
			continue
		if not _dungeon_floor.has_line_of_sight(e.grid_pos, prev):
			continue
		var reach: int = e.melee_reach()
		var d_prev: int = maxi(absi(prev.x - e.grid_pos.x), absi(prev.y - e.grid_pos.y))
		var d_next: int = maxi(absi(next.x - e.grid_pos.x), absi(next.y - e.grid_pos.y))
		# Battlefield Expert: a side-step (still-adjacent move around this same enemy) falls
		# through the no-OA branch below with zero changes to OA logic itself — see
		# markdowns/barbarian_base.md. Only counts as a genuine "around the enemy" pivot when the
		# step itself is diagonal (dx and dy both nonzero) — a pure lateral slide along one side
		# of the enemy (e.g. NW -> N) stays adjacent too but isn't really going around it.
		var is_diagonal_step: bool = absi(next.x - prev.x) == 1 and absi(next.y - prev.y) == 1
		if d_prev <= reach and d_next <= reach and prev != next and is_diagonal_step:
			_base_talents.on_sidestep(e)
		if d_prev > reach or d_next <= reach:
			continue
		if evading:
			evaded_any = true
			continue
		e.oa_used_this_round = true
		e._attack_player(self)
		if GameState.is_game_over:
			return
	if evaded_any:
		GameState.game_log("[color=gray]Eagle Form: you slip past their reach.[/color]")

func _play_footstep_sound() -> void:
	match _dungeon_floor.get_tile_type(grid_pos):
		DungeonData.TileType.GRASS, DungeonData.TileType.TRAMPLED_GRASS:
			AudioManager.play("step_grass")
		DungeonData.TileType.MUD:
			AudioManager.play("step_mud")
		DungeonData.TileType.WATER:
			AudioManager.play("step_water")
		_:
			AudioManager.play("step_floor")

func _try_move(dir: Vector2i) -> void:
	if _dungeon_floor == null:
		return
	_reset_camera_offset()
	var target: Vector2i = grid_pos + dir

	var enemy: Enemy = _dungeon_floor.get_enemy_at(target)
	if enemy != null:
		# Frenzy/Limit Break armed: a directional bump into an adjacent enemy targets it, same
		# as a normal melee attack — mouse click-to-target (player.gd's click handler) still
		# works as the alternative. Neither auto-fires without an explicit bump or click.
		if _berserker.frenzy_mode_active:
			_berserker.frenzy_mode_active = false
			_berserker.execute_frenzy(enemy)
			return
		if _scarred_warrior.limit_break_mode_active:
			_scarred_warrior.limit_break_mode_active = false
			_scarred_warrior.execute_limit_break(enemy)
			return
		if Input.is_key_pressed(KEY_SHIFT) and GameState.equipped_ranged != null:
			_ranged.ranged_attack(enemy)
		else:
			_bump_attack(enemy, dir)
		return

	# Thief Tools primed + bump = interact without moving (door or revealed trap).
	if _tool_item != null and _tool_item.item_name == "Thief Tools":
		# Revealed trap adjacent: disarm it.
		var adjacent_trap: Dictionary = _dungeon_floor.get_trap_at(target)
		if not adjacent_trap.is_empty() and adjacent_trap.get("revealed", false):
			_tool_item = null
			_thief_tools.attempt_disarm(target)
			return
		# Door adjacent: lock/unlock/pick action.
		if _dungeon_floor.has_door_at(target):
			_tool_item = null
			if _dungeon_floor.is_door_open(target):
				_thief_tools.attempt_lock_door(target)
			elif _dungeon_floor.is_door_locked(target):
				if _dungeon_floor.is_door_player_locked(target):
					TurnManager.begin_player_action()
					_dungeon_floor.unlock_door(target)
					_dungeon_floor.open_door(target)
					GameState.game_log("[color=cyan]You unlock the door you set.[/color]")
					_dungeon_floor.update_fog(grid_pos)
					TurnManager.on_player_action_complete()
				else:
					_thief_tools.attempt_disarm_lock(target)
			else:
				_thief_tools.attempt_lock_door(target)
			return
		# Nothing to interact with — cancel tool and move normally.
		_tool_item = null
		GameState.game_log("[color=gray]Nothing to interact with.[/color]")


	var _ns_rank: int = GameState.get_talent_rank("expanded_forms")
	var _ns_form: String = GameState.active_sleeper_form  # locked in at last floor descent
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
	_resolve_enemy_opportunity_attacks(prev_pos, target)
	if GameState.is_game_over:
		return
	# Battlefield Expert R3: captured here (right after side-step detection) since
	# consume_free_sidestep() clears sidestep_detected_this_move — used at the end of this move.
	var _free_sidestep: bool = _base_talents.consume_free_sidestep()
	TurnManager.begin_player_action()
	$AnimatedSprite2D.flip_h = dir.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(target)
	$AnimatedSprite2D.play("idle")
	if _dungeon_floor != null:
		if _dungeon_floor.has_door_at(prev_pos):
			_dungeon_floor.close_door(prev_pos)
		_vfx.leave_blood_trail(prev_pos)
		# Destroy grass before fog update so our own tile doesn't block sight
		if _dungeon_floor.get_tile_type(grid_pos) == DungeonData.TileType.GRASS:
			_dungeon_floor.destroy_grass(grid_pos)
		_dungeon_floor.update_fog(grid_pos)
		_actions.passive_trap_check()
		_actions.check_pickup()
		_play_footstep_sound()
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
	if _free_sidestep:
		GameState.game_log("[color=cyan]Battlefield Expert: that side-step didn't cost you your turn.[/color]")
		_reverted_this_round = true
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

func _activate_rage() -> void:
	if _is_raging:
		GameState.game_log("[color=red]You are already raging![/color]")
		return
	var ab: Ability = _find_ability("rage")
	if ab == null or not ab.has_uses():
		GameState.game_log("[color=red]No Rage uses remaining (resets on floor descent).[/color]")
		return
	_is_raging = true
	_rage_turns = 1  # baseline: lasts 1 turn, refreshed to 1 by attacking or being attacked
	_rage_attacked_this_turn = false
	GameState.is_raging = true
	GameState.rage_turns_remaining = _rage_turns
	if not GameState.invincible:
		ab.uses_remaining -= 1
	GameState.player_stats.rage_uses_remaining = ab.uses_remaining
	GameState.ability_bar_changed.emit()
	AudioManager.play("rage")
	$AnimatedSprite2D.modulate = Color(1.6, 0.55, 0.55)  # red tint
	var rage_dmg_bonus: int = stats.rage_bonus_damage
	GameState.game_log("[color=red]You fly into a RAGE! +%d STR damage. 50%% physical DR. (%d use(s) left)[/color]" % [rage_dmg_bonus, ab.uses_remaining])
	# Ironwood Bark R1: activating Rage grants temp HP (1d6 × rage bonus).
	if GameState.get_talent_rank("ironwood_bark") >= 1:
		var ib_thp: int = Rng.roll(6) * rage_dmg_bonus
		GameState.player_stats.temp_hp = ib_thp
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.game_log("[color=cyan]Ironwood Bark: %d temp HP (1d6 × rage bonus).[/color]" % ib_thp)
	# Free action — does NOT consume the turn.

func _activate_grip_of_the_forest() -> void:
	if not _is_raging:
		GameState.game_log("[color=gray]Grip of the Forest requires Raging.[/color]")
		return
	if _grip_used_this_turn:
		GameState.game_log("[color=gray]Grip of the Forest: already used this turn.[/color]")
		return
	_hook_mode_active = true
	var rank: int = GameState.get_talent_rank("grip_of_the_forest")
	var hook_range: int = [0, 3, 4, 5][mini(rank, 3)]
	GameState.game_log("[color=lime]Grip of the Forest — click an enemy within %d tiles. [Esc] to cancel.[/color]" % hook_range)

func _execute_hook(enemy: Enemy) -> void:
	_grip_used_this_turn = true
	TurnManager.begin_player_action()
	var rank: int = GameState.get_talent_rank("grip_of_the_forest")
	var dc: int = 8 + stats.str_modifier() + stats.proficiency_bonus
	var die1: int = Rng.roll(20)
	var roll: int = die1 + enemy.stats.str_modifier() + GameState.current_floor / 3
	var check_meta: String = "check:stat=STR,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=0" % [
		die1, die1, die1, enemy.stats.str_modifier(), GameState.current_floor / 3, roll, dc, 1 if roll >= dc else 0]
	if roll >= dc:
		GameState.game_log("[color=gray]%s resists Grip of the Forest! [url=%s]%d vs DC %d[/url][/color]" % [enemy.display_name, check_meta, roll, dc])
	else:
		GameState.game_log("[color=lime]Grip of the Forest pulls %s toward you! [url=%s]%d vs DC %d[/url][/color]" % [enemy.display_name, check_meta, roll, dc])
		if _dungeon_floor != null:
			var guard: int = 0
			while maxi(absi(enemy.grid_pos.x - grid_pos.x), absi(enemy.grid_pos.y - grid_pos.y)) > 1 and guard < 20:
				guard += 1
				var step_dir: Vector2i = Vector2i(sign(grid_pos.x - enemy.grid_pos.x), sign(grid_pos.y - enemy.grid_pos.y))
				var moved: int = await _dungeon_floor.force_move_entity(enemy, step_dir, 1, false)
				if moved == 0:
					break
		if rank >= 2:
			enemy.rooted_turns = 1
			GameState.game_log("[color=gray]%s is rooted![/color]" % enemy.display_name)
		if rank >= 3:
			enemy.disadv_next_attack = true
			GameState.game_log("[color=gray]%s has Disadvantage on their next attack.[/color]" % enemy.display_name)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	TurnManager.on_player_action_complete()

func _end_rage() -> void:
	_is_raging = false
	_rage_turns = 0
	GameState.is_raging = false
	GameState.rage_turns_remaining = 0
	$AnimatedSprite2D.modulate = Color(1.0, 1.0, 1.0)

# Branching Strike reach bonus, Divine Fury flat bonus, and weapon proficiency bonus are all
# pure math — computed in scripts/entities/combat_math.gd (CombatMath) now; see call sites below.

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

	_vfx.show_sword_slash(dir)

	# D&D attack roll: d20 + modifier + proficiency bonus + weapon enhancement vs enemy AC
	# Advantage (2d20 higher) when target is sleeping or entered FOV this turn.
	# Monk unarmed: uses DEX for both attack roll and damage. Others: STR.
	var is_unarmed: bool = GameState.equipped_weapon == null
	var is_monk_unarmed: bool = is_unarmed and stats.character_class == Stats.CharacterClass.MONK
	var is_str_weapon: bool = not is_unarmed and not (GameState.equipped_weapon.is_ranged)
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(null if is_unarmed else GameState.equipped_weapon, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var weapon_bonus: int = GameState.equipped_weapon.bonus_damage if not is_unarmed else 0
	var is_finesse_weapon: bool = not is_unarmed and GameState.equipped_weapon.is_finesse
	# Monk unarmed uses DEX; Finesse weapons use max(STR, DEX); everyone else uses STR for melee attack roll.
	var attack_mod: int = dex_mod if is_monk_unarmed else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var total_hit_bonus: int = attack_mod + prof + weapon_bonus
	# Advantage sources are counted; net ADV count vs DISADV count decides outcome.
	# Two ADV sources + one DISADV = net +1 = ADV (house rule: count beats cancel).
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if _vfx.has_advantage(enemy): adv_count += 1
	# Zealous Presence: Advantage on all attack rolls while buffed.
	if stats.zealous_presence_turns > 0: adv_count += 1
	# Vex (Short Bow): ADV on the attack immediately following a Short-Bow hit on this same enemy.
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	# Heavy weapon penalty: STR < 13 imposes Disadvantage
	var weapon_item_ref: Item = GameState.equipped_weapon
	if weapon_item_ref != null and weapon_item_ref.is_heavy and stats.strength < 13: disadv_count += 1
	# Animal Form Wolf: ADV when enough enemies are in FOV — always active in Wolf form (no
	# Rage required). Enhanced Forms lowers the threshold; R3 also counts 1 enemy + 1 friendly.
	if GameState.natural_rager_form == "Wolf" and is_str_weapon and _dungeon_floor != null:
		var enh_rank: int = GameState.get_talent_rank("enhanced_forms")
		var wolf_threshold: int = [4, 4, 3, 2][mini(enh_rank, 3)]
		var visible_enemies: int = _dungeon_floor.get_visible_enemies().size()
		var r3_alt: bool = enh_rank >= 3 and visible_enemies >= 1 and GameState.player_companion != null and is_instance_valid(GameState.player_companion)
		if visible_enemies >= wolf_threshold or r3_alt:
			adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + total_hit_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
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
	# Use dex= key for Monk unarmed, or for a Finesse weapon whose DEX mod is the one actually used.
	var mod_key: String = "dex" if (is_monk_unarmed or (is_finesse_weapon and dex_mod > str_mod)) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, w_enh, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0]

	# Zealot Strike heal resolves off the very next melee attack this turn regardless of hit/miss.
	_zealot.resolve_zealot_strike_heal()
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
		_try_graze(enemy, is_str_weapon, attack_mod)
		_try_cleave(enemy, is_str_weapon)
		_try_offhand_attack(enemy, is_str_weapon)
		_handle_post_attack_turn(is_monk_unarmed)
		return

	if is_crit: AudioManager.play_crit(weapon_item_ref)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	if adv:
		_vfx.show_surprise_mark(enemy)
	# Vex (e.g. Rapier): melee hit grants ADV on the next attack this round against this enemy — mirrors PlayerRanged's ranged Vex trigger.
	if weapon_item_ref != null and weapon_item_ref.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
		_vex_adv_target = enemy

	var die_roll: int = Rng.range_i(w_dmin, w_dmax)
	var rage_bonus: int = stats.rage_bonus_damage if (_is_raging and is_str_weapon) else 0
	# Monk unarmed uses DEX for damage; Finesse weapons use max(STR, DEX); all others use STR.
	var dmg_mod: int = dex_mod if is_monk_unarmed else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)

	# All bonus damage sources (Ironwood Bark, Judgement Day) are computed BEFORE
	# take_damage/show_damage and folded into one number — see "damage stacking" rule in
	# scripts/entities/CLAUDE.md. Never call take_damage/show_damage separately per source.
	# Each source keeps its own named amount in dmg_meta (not just a combined "bonus" total)
	# so the hover tooltip can name exactly which source(s) fired — the visible log line only
	# ever shows the single combined damage number, never a per-source text breakdown.
	# Frenzy (Berserker) is its own action (player_berserker.gd) — it no longer piggybacks a
	# bonus onto ordinary attacks.
	var frenzy_bonus: int = 0
	var ironwood_bonus: int = 0
	var judgement_bonus: int = 0

	# Ironwood Bark R3: next attack this turn deals bonus damage equal to the temp HP snapshotted at turn start.
	if _ironwood_bark_bonus_pending > 0:
		ironwood_bonus = _ironwood_bark_bonus_pending
		_ironwood_bark_bonus_pending = 0

	# Judgement Day: consumed on the attack AFTER the Zealot Strike heal that armed it.
	if _zealot.judgement_day_pending:
		_zealot.judgement_day_pending = false
		var jd_rank: int = GameState.get_talent_rank("judgement_day")
		judgement_bonus = jd_rank * stats.rage_bonus_damage * Rng.roll(6)

	var bonus_dmg: int = frenzy_bonus + ironwood_bonus + judgement_bonus
	# Multiplication always happens LAST: sum every source (dice, weapon enh, rage, ability mod,
	# and every bonus source above) into one total, THEN double it on a crit — never double a
	# partial subtotal and tack bonuses on afterward, or a crit silently skips doubling whichever
	# source was computed after the multiply.
	var pre_crit: int = die_roll + w_enh + rage_bonus + dmg_mod + bonus_dmg
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)

	var bonus_sources: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
		{"name": "Frenzy", "amount": frenzy_bonus, "color": "red"},
		{"name": "Ironwood Bark", "amount": ironwood_bonus, "color": "cyan"},
		{"name": "%s — Judgement Day" % _zealot.judgement_day_damage_type(), "amount": judgement_bonus,
			"color": "gold"},
	])
	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,%s=%d,bonus=%s,crit=%d,final=%d" % [
		die_roll, w_dmin, w_dmax, w_enh, mod_key, dmg_mod, bonus_sources, 1 if is_crit else 0, actual]
	var verb: String = "strike" if is_monk_unarmed else ("punch" if is_unarmed else "strike")
	var weapon_item: Item = GameState.equipped_weapon
	var dmg_type: String = weapon_item.damage_type if weapon_item != null and not weapon_item.damage_type.is_empty() else ("Bludgeoning" if is_unarmed else "<unknown_damage_type>")
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type

	if is_crit:
		GameState.game_log("[color=red]CRIT![/color] You [url=%s]%s[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, verb, enemy.display_name, dmg_meta, actual, type_tag])
	else:
		GameState.game_log("You [url=%s]%s[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, verb, enemy.display_name, dmg_meta, actual, type_tag])

	# Branching Strike R3: push the target 1 tile away on a hit with a Heavy/Versatile melee weapon.
	if GameState.get_talent_rank("branching_strike") >= 3 and is_str_weapon and not enemy.stats.is_dead() \
			and weapon_item_ref != null and (weapon_item_ref.is_heavy or weapon_item_ref.is_versatile) and _dungeon_floor != null:
		var push_dc: int = 8 + str_mod + prof
		if not enemy.resist_check(push_dc, true):
			var away_dir: Vector2i = Vector2i(sign(enemy.grid_pos.x - grid_pos.x), sign(enemy.grid_pos.y - grid_pos.y))
			if away_dir != Vector2i.ZERO:
				await _dungeon_floor.force_move_entity(enemy, away_dir, 1, false)
				GameState.game_log("[color=cyan]Branching Strike: %s is pushed back![/color]" % enemy.display_name)
		else:
			GameState.game_log("[color=gray]Branching Strike: %s resists the push.[/color]" % enemy.display_name)

	_try_topple(enemy, is_str_weapon, prof, str_mod)

	if enemy.stats.is_dead():
		_finish_kill(enemy)
	if _dungeon_floor != null:
		_dungeon_floor.update_fog(grid_pos)
	_try_cleave(enemy, is_str_weapon)
	_try_offhand_attack(enemy, is_str_weapon)
	_handle_post_attack_turn(is_monk_unarmed)

# Graze mastery (Greatsword): a missed melee attack still deals damage equal to the ability
# modifier used for the attack roll (min 0) — a separate, self-contained damage instance
# logged on its own line, not folded into the (nonexistent) hit damage of this swing.
func _try_graze(enemy: Enemy, is_str_weapon: bool, attack_mod: int) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Graze" or not stats.knows_mastery("Graze") or not is_str_weapon:
		return
	var graze_dmg: int = enemy.stats.take_damage(maxi(attack_mod, 0))
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, graze_dmg, false)
	var graze_meta: String = "grz:mod=%d,final=%d" % [attack_mod, graze_dmg]
	GameState.game_log("[color=cyan]Graze:[/color] %s still takes [url=%s][color=yellow]%d[/color][/url] dmg." % [enemy.display_name, graze_meta, graze_dmg])
	if enemy.stats.is_dead():
		_finish_kill(enemy)

# Topple mastery (Maul): on a hit, the target rolls a CON save (DC 8 + prof + STR mod) or is
# knocked Prone — Enemy.prone_turns skips its entire next turn (no movement, no attack).
func _try_topple(enemy: Enemy, is_str_weapon: bool, prof: int, str_mod: int) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Topple" or not stats.knows_mastery("Topple") \
			or not is_str_weapon or enemy.stats.is_dead():
		return
	var topple_dc: int = 8 + prof + str_mod
	var save: Dictionary = enemy.resist_check_detailed(topple_dc, true)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"])]
	if not save["pass"]:
		enemy.prone_turns = 1
		GameState.game_log("[color=cyan]Topple:[/color] %s [url=%s]is knocked[/url] [color=orange]Prone[/color]!" % [enemy.display_name, save_meta])
	else:
		GameState.game_log("[color=gray]Topple: %s [url=%s]resists[/url] being knocked prone.[/color]" % [enemy.display_name, save_meta])

# Cleave mastery (Greataxe): if 2+ distinct enemies are within melee reach, the swing also
# rolls a fully independent attack + damage roll against a second target — the one closest
# to the primary target, per weapon-mastery design. Fires regardless of whether the primary
# attack hit or missed (it's a separate swing of the arc, not a bonus tacked onto the primary).
func _try_cleave(primary: Enemy, is_str_weapon: bool) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or weapon.weapon_mastery != "Cleave" or not stats.knows_mastery("Cleave") or not is_str_weapon or _dungeon_floor == null:
		return
	var reach: int = CombatMath.melee_reach(weapon, GameState.get_talent_rank("branching_strike"))
	var candidates: Array[Enemy] = []
	for e: Enemy in _dungeon_floor.get_visible_enemies():
		if e == primary or e.stats.is_dead():
			continue
		var d: Vector2i = e.grid_pos - grid_pos
		if maxi(absi(d.x), absi(d.y)) <= reach:
			candidates.append(e)
	if candidates.is_empty():
		return
	candidates.sort_custom(func(a: Enemy, b: Enemy) -> bool:
		var da: Vector2i = a.grid_pos - primary.grid_pos
		var db: Vector2i = b.grid_pos - primary.grid_pos
		return maxi(absi(da.x), absi(da.y)) < maxi(absi(db.x), absi(db.y)))
	_resolve_cleave_attack(candidates[0], weapon)

func _resolve_cleave_attack(enemy: Enemy, weapon: Item) -> void:
	var str_mod: int = stats.str_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(weapon, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var weapon_bonus: int = weapon.bonus_damage
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if weapon.is_heavy and stats.strength < 13: disadv_count += 1
	# Vex (Short Bow): future-proofing — a weapon could carry both Cleave and Vex.
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + str_mod + prof + weapon_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,str=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, str_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("[color=cyan]Cleave:[/color] you swing at [color=orange]%s[/color] — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	var w_dmin: int = weapon.damage_die_min if weapon.damage_die_min > 0 else stats.base_min_damage
	var w_dmax: int = weapon.damage_die_max if weapon.damage_die_max > 0 else stats.base_max_damage
	var die_roll: int = Rng.range_i(w_dmin, w_dmax)
	var rage_bonus: int = stats.rage_bonus_damage if _is_raging else 0
	var pre_crit: int = die_roll + weapon_bonus + rage_bonus + str_mod
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)
	var bonus_sources: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	])
	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,str=%d,bonus=%s,crit=%d,final=%d" % [
		die_roll, w_dmin, w_dmax, weapon_bonus, str_mod, bonus_sources, 1 if is_crit else 0, actual]
	var dmg_type: String = weapon.damage_type if not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	GameState.game_log("[color=cyan]Cleave:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, enemy.display_name, dmg_meta, actual, type_tag])
	if enemy.stats.is_dead():
		_finish_kill(enemy)

# Dual-wielding (Two-Weapon Fighting): if Main Hand and the Off-hand (GameState.equipment["hand2"])
# both hold a Light melee weapon, every melee attack also swings the off-hand weapon at the same
# target — a fully independent roll, fired regardless of whether the primary attack hit or missed
# (mirrors Cleave's call sites). Per the house rule: the off-hand damage roll skips the STR/finesse
# ability modifier entirely UNLESS it's negative, in which case it's always applied.
func _try_offhand_attack(enemy: Enemy, is_str_weapon: bool) -> void:
	var main_hand: Item = GameState.equipped_weapon
	if main_hand == null or not main_hand.is_light or not is_str_weapon or enemy.stats.is_dead():
		return
	var off_hand: Item = GameState.equipment.get("hand2") as Item
	if off_hand == null or off_hand.item_type != Item.Type.WEAPON or off_hand.is_ranged or not off_hand.is_light:
		return
	_resolve_offhand_attack(enemy, off_hand)
	# Nick (Dagger): while dual-wielding two Light weapons, if either one carries Nick, get one
	# further attack this turn — identical to the Off-hand swing above (same "no ability modifier
	# unless negative" rule) — for a maximum of 3 attacks total (Main Hand, Off-hand, Nick bonus).
	if not enemy.stats.is_dead() and stats.knows_mastery("Nick") \
			and (main_hand.weapon_mastery == "Nick" or off_hand.weapon_mastery == "Nick"):
		_resolve_offhand_attack(enemy, off_hand, "Nick")

func _resolve_offhand_attack(enemy: Enemy, weapon: Item, label: String = "Off-hand") -> void:
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var attack_mod: int = CombatMath.finesse_modifier(str_mod, dex_mod, weapon.is_finesse)
	var prof: int = CombatMath.weapon_prof_bonus(weapon, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var weapon_bonus: int = weapon.bonus_damage
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if weapon.is_heavy and stats.strength < 13: disadv_count += 1
	var vex_triggered: bool = _vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	if vex_triggered:
		_vex_adv_target = null
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + attack_mod + prof + weapon_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var mod_key: String = "dex" if (weapon.is_finesse and dex_mod > str_mod) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("[color=cyan]%s:[/color] you swing at [color=orange]%s[/color] — [url=%s]%s[/url]." % [label, enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	if weapon.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
		_vex_adv_target = enemy
	var w_dmin: int = weapon.damage_die_min if weapon.damage_die_min > 0 else stats.base_min_damage
	var w_dmax: int = weapon.damage_die_max if weapon.damage_die_max > 0 else stats.base_max_damage
	var die_roll: int = Rng.range_i(w_dmin, w_dmax)
	var rage_bonus: int = stats.rage_bonus_damage if _is_raging else 0
	# Off-hand damage drops the positive ability modifier; a negative modifier still always applies.
	var dmg_mod: int = mini(attack_mod, 0)
	var pre_crit: int = die_roll + weapon_bonus + rage_bonus + dmg_mod
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)
	var bonus_sources: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	])
	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,%s=%d,bonus=%s,crit=%d,final=%d" % [
		die_roll, w_dmin, w_dmax, weapon_bonus, mod_key, dmg_mod, bonus_sources, 1 if is_crit else 0, actual]
	var dmg_type: String = weapon.damage_type if not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	GameState.game_log("[color=cyan]%s:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [label, hit_meta, enemy.display_name, dmg_meta, actual, type_tag])
	if enemy.stats.is_dead():
		_finish_kill(enemy)

# Opportunity Attack: a self-contained, turn-free melee swing triggered when an enemy leaves the
# player's threat range (see docs/architecture/opportunity-attacks-design.md). Modeled on
# _resolve_cleave_attack() — no TurnManager involvement, no per-turn talent effects. Vex/
# Frenzy/Divine-Fury/Ironwood-Bark are deliberately excluded — those are per-turn action
# effects, and this fires on the enemy's turn, not the player's.
func resolve_opportunity_attack(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or enemy.stats.is_dead():
		return
	var weapon: Item = GameState.equipped_weapon
	var is_unarmed: bool = weapon == null
	var is_monk_unarmed: bool = is_unarmed and stats.character_class == Stats.CharacterClass.MONK
	var is_str_weapon: bool = not is_unarmed and not weapon.is_ranged
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(null if is_unarmed else weapon, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var weapon_bonus: int = weapon.bonus_damage if not is_unarmed else 0
	var is_finesse_weapon: bool = not is_unarmed and weapon.is_finesse
	var attack_mod: int = dex_mod if is_monk_unarmed else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var adv_count: int = 0
	adv_count += _base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if weapon != null and weapon.is_heavy and stats.strength < 13: disadv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + attack_mod + prof + weapon_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		_base_talents.on_crit()
		_berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1
	var mod_key: String = "dex" if (is_monk_unarmed or (is_finesse_weapon and dex_mod > str_mod)) else "str"
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, mod_key, attack_mod, prof, weapon_bonus, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("[color=cyan]Opportunity attack:[/color] you swing at [color=orange]%s[/color] as it flees — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	_vfx.flash_hit(enemy)
	var w_dmin: int
	var w_dmax: int
	if is_monk_unarmed:
		w_dmin = 1
		w_dmax = stats.martial_arts_die_sides
	elif not is_unarmed and weapon.damage_die_min > 0:
		w_dmin = weapon.damage_die_min
		w_dmax = weapon.damage_die_max
	else:
		w_dmin = stats.base_min_damage
		w_dmax = stats.base_max_damage
	var die_roll: int = Rng.range_i(w_dmin, w_dmax)
	var rage_bonus: int = stats.rage_bonus_damage if (_is_raging and is_str_weapon) else 0
	var dmg_mod: int = dex_mod if is_monk_unarmed else CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var pre_crit: int = die_roll + weapon_bonus + rage_bonus + dmg_mod
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(enemy.position, actual, false)
	var bonus_sources: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	])
	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,%s=%d,bonus=%s,crit=%d,final=%d" % [
		die_roll, w_dmin, w_dmax, weapon_bonus, mod_key, dmg_mod, bonus_sources, 1 if is_crit else 0, actual]
	var dmg_type: String = weapon.damage_type if (not is_unarmed and not weapon.damage_type.is_empty()) else ("Bludgeoning" if is_unarmed else "<unknown_damage_type>")
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	GameState.game_log("[color=cyan]Opportunity attack:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, enemy.display_name, dmg_meta, actual, type_tag])
	if enemy.stats.is_dead():
		_finish_kill(enemy)

func _handle_post_attack_turn(_from_monk_unarmed: bool = false) -> void:
	TurnManager.on_player_action_complete()


func _finish_kill(enemy: Enemy, dropped_ammo: Item = null) -> void:
	_base_talents.on_kill()
	GameState.game_log("[color=orange]%s[/color] [color=gray]dies.[/color]" % enemy.display_name)
	GameState.gain_exp(maxi(1, enemy.exp_reward / 2))
	var was_boss: bool = enemy.is_boss
	var kill_pos: Vector2i = enemy.grid_pos
	var killed_name: String = enemy.display_name
	var killed_boss_id: String = enemy.enemy_id
	_dungeon_floor.remove_enemy(enemy)
	enemy.die()
	if was_boss:
		_dungeon_floor.drop_boss_loot(kill_pos)
		GameState.boss_defeated.emit(killed_boss_id)
	if killed_name in UNDEAD_NAMES and Rng.chance(0.20):
		var rotten := Item.new()
		rotten.item_name = "Rotten Meat"
		rotten.item_type = Item.Type.FOOD
		rotten.food_value = 10
		rotten.icon_path = "res://sprites/items/Food/Meat.png"
		rotten.description = "Throw into fire to cook into Cooked Meat."
		_dungeon_floor.place_item_on_floor(kill_pos, rotten)
		GameState.game_log("[color=gray]%s dropped [b]Rotten Meat[/b].[/color]" % killed_name)
	# Ammo drop-from-corpse: 50% chance the killing shot's arrow/bolt is recoverable.
	if dropped_ammo != null and Rng.chance(0.5):
		_ammo.resolve_ammo_landing(dropped_ammo, kill_pos)
		GameState.game_log("[color=gray]The %s drops from the corpse.[/color]" % dropped_ammo.item_name)

func _on_action_requested(action_name: String) -> void:
	if action_name == "short_rest_begin":
		if TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT:
			_queued_path.clear()
			_path_executing = false
			_actions.do_rest_wait_turn()
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
		"wait":     _actions.wait_action()
		"search":   _actions.handle_search_request()
		"interact": _actions.interact_action()

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
		"unarmored_defense_monk":  GameState.game_log("[color=gray]Unarmored Defense is passive — active when unarmored (AC = 10+DEX+WIS).[/color]")
		"martial_arts":            GameState.game_log("[color=gray]Martial Arts is passive — attack unarmed to trigger a bonus-action strike.[/color]")
		"wild_companion":         _wild_heart.activate_one_with_nature(ab)
		"animal_form":             _wild_heart.cycle_animal_form(ab)
		"enhanced_forms":
			GameState.game_log("[color=gray]%s is passive — upgrades Animal Form automatically.[/color]" % ab.ability_name)
		"expanded_forms":         _wild_heart.cycle_natural_sleeper_form(ab)
		"ironwood_bark":           GameState.game_log("[color=gray]Ironwood Bark is passive — triggers on Rage activation and while Raging.[/color]")
		"grip_of_the_forest":      _activate_grip_of_the_forest()
		"branching_strike":        GameState.game_log("[color=gray]Branching Strike is passive — reach and push apply automatically.[/color]")
		"zealot_strike":           _zealot.activate_zealot_strike(ab)
		"judgement_day", "overheal_shield", "never_back_down":
			GameState.game_log("[color=gray]%s is passive — upgrades Zealot Strike automatically.[/color]" % ab.ability_name)
		"frenzy":                  _berserker.activate_frenzy()
		"sadist_monster", "masochist_monster", "frenzied_killer":
			GameState.game_log("[color=gray]%s is passive — upgrades Frenzy automatically.[/color]" % ab.ability_name)
		"limit_break":             _scarred_warrior.activate_limit_break()
		"born_in_blood", "enough_is_enough", "bloodied_regen":
			GameState.game_log("[color=gray]%s is passive — upgrades Limit Break or triggers automatically.[/color]" % ab.ability_name)
		_:                         GameState.game_log("[color=gray]%s: not yet implemented.[/color]" % ab.ability_name)
