class_name Enemy
extends Entity

enum Behavior { SLEEPING, STATIONARY, ROAMING, CHASING, SEARCHING }

const SPRITES_PATH := "res://sprites/characters/"
const FOV_RADIUS: int = 6
const WAKE_RADIUS_SQ: int = 4  # 2-tile adjacency wakes sleeping enemies

var _dungeon_floor: Node
var display_name: String = "Enemy"
var exp_reward: int = 5
var _type: Dictionary = {}
var enemy_id: String = ""  # from pool "enemy_id"/"boss_id" key — stable id, unlike display_name (UI text)

var is_boss: bool = false
var initial_behavior: Behavior = Behavior.SLEEPING
var behavior: Behavior = Behavior.SLEEPING
var last_known_target_pos: Vector2i = Vector2i(-1, -1)

var just_crossed_door: bool = false
var oa_used_this_round: bool = false  # Opportunity Attack reaction cap — reset at the top of take_turn()
var slowed_turns: int = 0
var rooted_turns: int = 0        # World Tree Grip of the Forest R2 — skips movement, still attacks if adjacent
var disadv_next_attack: bool = false  # World Tree Grip of the Forest R3 — consumed on next attack roll
var prone_turns: int = 0         # Maul's Topple mastery — skips the ENTIRE turn (no movement, no attack)
var embedded_items: Array[Item] = []  # thrown weapons stuck in a non-lethal hit (PlayerThrowTool._throw_weapon) — dropped at 100% chance wherever/whenever this enemy eventually dies, see die() override below
var _roam_target: Vector2i = Vector2i(-1, -1)
var _roam_path: Array[Vector2i] = []
# Search state — used when enemy loses sight of player after chasing
var _search_heading: Vector2i = Vector2i(0, 0)
var _search_turns_remaining: int = 0
var _search_target: Vector2i = Vector2i(-1, -1)
var _search_path: Array[Vector2i] = []

var _zzz_label: Label
var _zzz_tween: Tween

func configure(type_data: Dictionary) -> void:
	_type = type_data
	display_name = type_data.get("display_name", "Enemy")
	enemy_id = type_data.get("enemy_id", type_data.get("boss_id", ""))

func _ready() -> void:
	stats = Stats.new()
	_apply_stats()
	z_index = 1
	_setup_animations()
	_setup_hp_bar()
	_setup_zzz()
	behavior = initial_behavior
	if behavior == Behavior.SLEEPING:
		_start_zzz()

func _apply_stats() -> void:
	var f: int = GameState.current_floor
	stats.max_hp      = _type.get("hp", 8)      + (f - 1) * _type.get("hp_per_floor", 2)
	stats.min_damage  = _type.get("dmg_min", 1) + (f - 1) / 3
	stats.max_damage  = _type.get("dmg_max", 4) + (f - 1) / 2
	stats.armor       = 0
	stats.armor_class = _type.get("ac", 10) + _type.get("armor", 0) + f / 5
	stats.current_hp  = stats.max_hp
	exp_reward        = _type.get("exp", 5)
	# Optional per-pool-entry resist modifiers (default 0) — used by resist_check() below.
	stats.strength    = 10 + _type.get("str_mod", 0) * 2
	stats.constitution = 10 + _type.get("con_mod", 0) * 2

# Rolls d20 + (con_modifier if use_con else str_modifier) vs dc.
# Used by World Tree's Grip of the Forest (STR) and Branching Strike R3 push (CON).
# Returns true if the enemy RESISTS (roll >= dc).
func resist_check(dc: int, use_con: bool = false) -> bool:
	return resist_check_detailed(dc, use_con)["pass"]

# Same roll as resist_check(), but returns the full breakdown so callers can log a chat-log
# tooltip (see Topple's "save" meta in player.gd._try_topple()) instead of just the pass/fail
# bool. "pass" here means the enemy RESISTS (roll >= dc), matching resist_check().
func resist_check_detailed(dc: int, use_con: bool = false) -> Dictionary:
	var mod: int = stats.con_modifier() if use_con else stats.str_modifier()
	var floor_bonus: int = GameState.current_floor / 3
	var die: int = Rng.roll(20)
	var total: int = die + floor_bonus + mod
	return {
		"die": die, "mod": mod, "floor_bonus": floor_bonus, "dc": dc,
		"total": total, "pass": total >= dc, "stat": "CON" if use_con else "STR",
	}

# Overrides Entity.die(): drop any thrown weapons embedded in this enemy (see embedded_items
# above) at 100% chance before freeing — regardless of what actually killed it or how many turns
# ago they were embedded. Every death call site (player.gd._finish_kill, companion.gd, trap/chasm
# deaths in dungeon_floor.gd) already calls enemy.die() as its last step, so this single override
# covers all of them with no other call site changes needed.
func die() -> void:
	if not embedded_items.is_empty() and _dungeon_floor != null:
		for it: Item in embedded_items:
			_dungeon_floor.place_item_on_floor(grid_pos, it)
		embedded_items.clear()
	super.die()

func _setup_animations() -> void:
	var prefix: String = _type.get("sprite", "orc_warrior")
	var idle_n: int    = _type.get("idle_frames", 4)
	var run_n: int     = _type.get("run_frames", 4)
	var idle_fmt: String = _type.get("idle_fmt", SPRITES_PATH + prefix + "_idle_anim_f%d.png")
	var run_fmt: String  = _type.get("run_fmt",  SPRITES_PATH + prefix + "_run_anim_f%d.png")
	var frames := SpriteFrames.new()
	_add_anim(frames, "idle", idle_fmt, idle_n, true,  8.0)
	_add_anim(frames, "run",  run_fmt,  run_n, false, 16.0)
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

func _setup_zzz() -> void:
	_zzz_label = Label.new()
	_zzz_label.text = "z z z"
	_zzz_label.add_theme_font_size_override("font_size", 7)
	_zzz_label.position = Vector2(-9, -22)
	_zzz_label.z_index = 4
	_zzz_label.modulate.a = 0.0
	_zzz_label.visible = false
	add_child(_zzz_label)

func _start_zzz() -> void:
	if not is_instance_valid(_zzz_label):
		return
	_zzz_label.visible = true
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
	_zzz_tween = create_tween().set_loops()
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 1.0, 1.0)
	_zzz_tween.tween_property(_zzz_label, "modulate:a", 0.3, 1.0)

func _stop_zzz() -> void:
	if _zzz_tween != null and _zzz_tween.is_valid():
		_zzz_tween.kill()
		_zzz_tween = null
	if is_instance_valid(_zzz_label):
		_zzz_label.visible = false

func _wake_up() -> void:
	behavior = Behavior.CHASING
	_stop_zzz()

# Threat range in tiles for Opportunity Attacks. Flat 1 for all current enemies (pool key
# "reach", default 1) — a future reach enemy (whip skeleton, tentacle boss) is a one-line pool entry.
func melee_reach() -> int:
	return _type.get("reach", 1)

# --- Targeting (§5 of docs/architecture/enemy_system_architecture.md) ---
# Both the player and the Wild Heart companion are valid targets: whoever first gets into the
# enemy's attack range wins the fight, re-evaluated fresh every turn — no target-lock state.
func _get_target_candidates() -> Array:
	var out: Array = []
	var player: Player = _dungeon_floor.get_player()
	if player != null and is_instance_valid(player) and not player.stats.is_dead():
		out.append(player)
	var comp: Variant = GameState.player_companion
	if comp != null and is_instance_valid(comp) and not comp.stats.is_dead():
		out.append(comp)
	return out

func _dist_sq_to(e: Node) -> int:
	var dx: int = e.grid_pos.x - grid_pos.x
	var dy: int = e.grid_pos.y - grid_pos.y
	return dx * dx + dy * dy

func _chebyshev_to(e: Node) -> int:
	return maxi(absi(e.grid_pos.x - grid_pos.x), absi(e.grid_pos.y - grid_pos.y))

func _can_see_entity(e: Node) -> bool:
	return _dist_sq_to(e) <= FOV_RADIUS * FOV_RADIUS and _dungeon_floor.has_line_of_sight(grid_pos, e.grid_pos)

# Adjacency wins first (first to reach range gets attacked); ties broken by lower current HP.
# Otherwise, whichever candidate is nearer is the one stepped toward / seen.
func _select_target(candidates: Array) -> Node:
	var adjacent: Array = []
	for c: Node in candidates:
		if _chebyshev_to(c) == 1:
			adjacent.append(c)
	if adjacent.size() == 1:
		return adjacent[0]
	if adjacent.size() > 1:
		var best: Node = adjacent[0]
		for c: Node in adjacent:
			if c.stats.current_hp < best.stats.current_hp:
				best = c
		return best
	var nearest: Node = candidates[0]
	var nearest_d: int = _dist_sq_to(nearest)
	for c: Node in candidates:
		var d: int = _dist_sq_to(c)
		if d < nearest_d:
			nearest_d = d
			nearest = c
	return nearest

func take_turn() -> void:
	oa_used_this_round = false
	if _dungeon_floor == null:
		return
	if prone_turns > 0:
		prone_turns -= 1
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return
	if slowed_turns > 0:
		slowed_turns -= 1
		await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		return

	var intent: Dictionary = _decide_action()
	await _execute_action(intent)

# Pure(ish) decision step — reads state, mutates only internal FSM/target-memory fields (not
# visuals), returns an intent for _execute_action() to carry out. See docs/architecture/
# enemy_system_architecture.md §1.
func _decide_action() -> Dictionary:
	var candidates: Array = _get_target_candidates()
	if candidates.is_empty():
		return {"type": "wait"}
	var target: Node = _select_target(candidates)

	# World Tree Grip of the Forest R2: rooted — no movement this turn, but can still attack if adjacent.
	if rooted_turns > 0:
		rooted_turns -= 1
		if _chebyshev_to(target) == 1:
			return {"type": "attack", "target": target}
		return {"type": "wait"}

	var dist_sq: int = _dist_sq_to(target)
	var can_see: bool = _can_see_entity(target)
	var dx: int = target.grid_pos.x - grid_pos.x
	var dy: int = target.grid_pos.y - grid_pos.y

	match behavior:
		Behavior.SLEEPING:
			if can_see or dist_sq <= WAKE_RADIUS_SQ:
				_wake_up()
				last_known_target_pos = target.grid_pos
				return {"type": "act_toward", "target": target, "can_see": can_see}
			return {"type": "wait"}

		Behavior.STATIONARY:
			if can_see:
				last_known_target_pos = target.grid_pos
				behavior = Behavior.CHASING
				return {"type": "act_toward", "target": target, "can_see": can_see}
			return {"type": "wait"}

		Behavior.ROAMING:
			if can_see:
				last_known_target_pos = target.grid_pos
				behavior = Behavior.CHASING
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				return {"type": "act_toward", "target": target, "can_see": can_see}
			return {"type": "roam"}

		Behavior.CHASING:
			if can_see:
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
			return {"type": "act_toward", "target": target, "can_see": can_see, "chasing": true}

		Behavior.SEARCHING:
			if can_see:
				behavior = Behavior.CHASING
				last_known_target_pos = target.grid_pos
				_search_heading = Vector2i(sign(dx), sign(dy))
				return {"type": "act_toward", "target": target, "can_see": can_see}
			return {"type": "search"}

	return {"type": "wait"}

# All the tween/animation/await/log side effects, dispatched on intent.type. See docs/
# architecture/enemy_system_architecture.md §1.
func _execute_action(intent: Dictionary) -> void:
	match intent.get("type", "wait"):
		"attack":
			_attack_target(intent["target"])
		"act_toward":
			await _act_toward(intent["target"])
			if not is_instance_valid(self) or stats.is_dead():
				return
			# Reached last known position without spotting the target — enter search mode.
			if intent.get("chasing", false) and not intent.get("can_see", false) \
					and last_known_target_pos != Vector2i(-1, -1) and grid_pos == last_known_target_pos:
				behavior = Behavior.SEARCHING
				_search_turns_remaining = 7
				_search_target = last_known_target_pos + _search_heading * 5
				_search_path.clear()
				last_known_target_pos = Vector2i(-1, -1)
		"roam":
			await _do_roam_walk()
		"search":
			if _search_turns_remaining > 0:
				_search_turns_remaining -= 1
				if _search_path.is_empty() or grid_pos == _search_target:
					_search_path = _bfs_to(_search_target)
				if not _search_path.is_empty():
					var next: Vector2i = _search_path[0]
					_search_path = _search_path.slice(1)
					await _move_step(next - grid_pos, next)
				else:
					await _do_random_step()
			else:
				behavior = Behavior.ROAMING
				_search_target = Vector2i(-1, -1)
				_search_path.clear()
				_roam_path.clear()
				_roam_target = Vector2i(-1, -1)
				# State transition only, no movement this turn — still await the idle timer
				# (see the matching comment in _act_toward()'s BFS-fallback-failure path).
				await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
		"wait":
			await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

# True if `target` is within this enemy's current attack_profile range (melee default = adjacent).
func _in_attack_range(target: Node) -> bool:
	var profile: Dictionary = _type.get("attack_profile", {})
	match profile.get("kind", "melee"):
		"ranged":
			var rng: int = profile.get("range", 4)
			return _chebyshev_to(target) <= rng and _dungeon_floor.has_ranged_los(grid_pos, target.grid_pos)
		_:
			return _chebyshev_to(target) == 1

func _attack_target(target: Node) -> void:
	if target is Player:
		_attack_player(target)
	elif target is Companion:
		_attack_companion(target)

# Attack if in range of target; otherwise step toward last known / target position.
func _act_toward(target: Node) -> void:
	if _in_attack_range(target):
		_attack_target(target)
		return

	var dest: Vector2i = last_known_target_pos if last_known_target_pos != Vector2i(-1, -1) else target.grid_pos
	var tdx: int = dest.x - grid_pos.x
	var tdy: int = dest.y - grid_pos.y

	for step: Vector2i in _preferred_steps(tdx, tdy):
		var next_pos: Vector2i = grid_pos + step
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)
			return

	# Greedy failed — BFS fallback to navigate around obstacles. If the BFS route is also empty,
	# or its first step turns out to be unwalkable, the enemy is stuck this turn: still await the
	# idle timer so the turn takes real time instead of resolving instantly (a stuck-but-alive
	# enemy previously made TurnManager burn through the enemy phase with zero elapsed time,
	# which looked like an empty/cleared floor even with TurnManager.fast_mode == false).
	var bfs_path: Array[Vector2i] = _bfs_to(dest)
	if not bfs_path.is_empty():
		var next_pos: Vector2i = bfs_path[0]
		var step: Vector2i = next_pos - grid_pos
		if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
			_dungeon_floor.open_door(next_pos)
		if _dungeon_floor.is_walkable_for_enemy(next_pos):
			await _move_step(step, next_pos)
			return
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

func _pick_roam_target() -> Vector2i:
	var centers: Array[Vector2i] = _dungeon_floor.get_room_centers()
	Rng.shuffle(centers)
	for c: Vector2i in centers:
		if maxi(absi(c.x - grid_pos.x), absi(c.y - grid_pos.y)) < 4:
			continue
		if _dungeon_floor.is_walkable_for_enemy(c):
			return c
	return Vector2i(-1, -1)

func _do_roam_walk() -> void:
	if _roam_path.is_empty() or grid_pos == _roam_target:
		_roam_target = _pick_roam_target()
		if _roam_target == Vector2i(-1, -1):
			await _do_random_step()
			return
		_roam_path = _bfs_to(_roam_target)
		if _roam_path.is_empty():
			_roam_target = Vector2i(-1, -1)
			await _do_random_step()
			return
	var next_pos: Vector2i = _roam_path[0]
	if not _dungeon_floor.is_walkable_for_enemy(next_pos):
		_roam_path.clear()
		_roam_target = Vector2i(-1, -1)
		await _do_random_step()
		return
	_roam_path.remove_at(0)
	if _dungeon_floor.has_door_at(next_pos) and not _dungeon_floor.is_door_open(next_pos):
		_dungeon_floor.open_door(next_pos)
	await _move_step(next_pos - grid_pos, next_pos)

func _do_random_step() -> void:
	var dirs: Array[Vector2i] = [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
			Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]
	Rng.shuffle(dirs)
	for dir: Vector2i in dirs:
		var target: Vector2i = grid_pos + dir
		if _dungeon_floor.has_door_at(target):
			continue
		if _dungeon_floor.is_walkable_for_enemy(target):
			await _move_step(dir, target)
			return
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout

func _move_step(step: Vector2i, next_pos: Vector2i) -> void:
	var prev_pos: Vector2i = grid_pos
	_check_opportunity_attacks_on_move(prev_pos, next_pos)
	if not is_instance_valid(self) or stats.is_dead():
		return
	var stepping_through_door: bool = _dungeon_floor.has_door_at(next_pos)
	$AnimatedSprite2D.flip_h = step.x < 0
	$AnimatedSprite2D.play("run")
	await move_to(next_pos, 0.04 if TurnManager.fast_mode else 0.08)
	if not is_instance_valid(self):
		return
	$AnimatedSprite2D.play("idle")
	if visible:
		AudioManager.play("footstep")
	if stepping_through_door:
		just_crossed_door = true
	if _dungeon_floor.has_door_at(prev_pos):
		_dungeon_floor.close_door(prev_pos)
	var tile_type: DungeonData.TileType = _dungeon_floor.get_tile_type(grid_pos)
	if tile_type == DungeonData.TileType.WATER or tile_type == DungeonData.TileType.MUD:
		slowed_turns = maxi(slowed_turns, 1)
	if tile_type == DungeonData.TileType.GRASS:
		_dungeon_floor.destroy_grass(grid_pos)
	var trap: Dictionary = _dungeon_floor.get_trap_at(grid_pos)
	if not trap.is_empty():
		await _dungeon_floor.trigger_trap(grid_pos, self)

# Opportunity Attacks: this enemy is the mover, the player (and any live companions) are the
# potential attackers. Voluntary-movement chokepoint for ALL enemy movement (chase/roam/random/
# search) — see docs/architecture/opportunity-attacks-design.md. Forced movement (force_move_entity,
# resolve_push) intentionally bypasses this and must NOT call it.
func _check_opportunity_attacks_on_move(prev_pos: Vector2i, next_pos: Vector2i) -> void:
	if _dungeon_floor == null or not _dungeon_floor.is_tile_visible(prev_pos):
		return
	var player: Player = _dungeon_floor.get_player()
	if player != null and is_instance_valid(player) and not player.stats.is_dead() and not player._oa_used_this_round:
		var reach: int = CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike"))
		var d_prev: int = maxi(absi(prev_pos.x - player.grid_pos.x), absi(prev_pos.y - player.grid_pos.y))
		var d_next: int = maxi(absi(next_pos.x - player.grid_pos.x), absi(next_pos.y - player.grid_pos.y))
		if d_prev <= reach and d_next > reach:
			player._oa_used_this_round = true
			player.resolve_opportunity_attack(self)
			if not is_instance_valid(self) or stats.is_dead():
				return
	for c: Node in get_tree().get_nodes_in_group("companions"):
		var comp: Companion = c as Companion
		if comp == null or not is_instance_valid(comp) or comp.stats.is_dead() or comp.oa_used_this_round:
			continue
		var cd_prev: int = maxi(absi(prev_pos.x - comp.grid_pos.x), absi(prev_pos.y - comp.grid_pos.y))
		var cd_next: int = maxi(absi(next_pos.x - comp.grid_pos.x), absi(next_pos.y - comp.grid_pos.y))
		if cd_prev <= 1 and cd_next > 1:
			comp.oa_used_this_round = true
			comp._attack_enemy(self)
			if not is_instance_valid(self) or stats.is_dead():
				return

# Returns movement direction candidates in priority order (diagonal first, then axes).
func _preferred_steps(dx: int, dy: int) -> Array[Vector2i]:
	var sx: int = sign(dx)
	var sy: int = sign(dy)
	var steps: Array[Vector2i] = []
	if sx != 0 and sy != 0:
		steps.append(Vector2i(sx, sy))
	if abs(dx) >= abs(dy):
		if sx != 0: steps.append(Vector2i(sx, 0))
		if sy != 0: steps.append(Vector2i(0, sy))
	else:
		if sy != 0: steps.append(Vector2i(0, sy))
		if sx != 0: steps.append(Vector2i(sx, 0))
	return steps

func _bfs_to(target: Vector2i) -> Array[Vector2i]:
	var queue: Array[Vector2i] = [grid_pos]
	var came: Dictionary = {grid_pos: grid_pos}
	var limit: int = 0
	while not queue.is_empty() and limit < 200:
		limit += 1
		var cur: Vector2i = queue.pop_front()
		if cur == target:
			var path: Array[Vector2i] = []
			while cur != grid_pos:
				path.push_front(cur)
				cur = came[cur]
			return path
		for d: Vector2i in [Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
				Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)]:
			var nxt: Vector2i = cur + d
			if not came.has(nxt) and (_dungeon_floor.is_walkable_for_enemy(nxt) or nxt == target):
				came[nxt] = cur
				queue.append(nxt)
	return []

# Shared d20-vs-AC roll used by every enemy attack (melee, ranged, vs-player, vs-companion) — see
# docs/architecture/enemy_system_architecture.md §2. Only computes the roll; callers apply damage/log.
func _resolve_attack_roll(target_ac: int, attack_bonus_override: int = -1) -> Dictionary:
	# D&D attack roll: d20 + floor-scaled bonus vs target AC.
	var attack_bonus: int = attack_bonus_override if attack_bonus_override >= 0 else GameState.current_floor / 3
	var die1: int = Rng.roll(20)
	var die2: int = die1
	var die: int = die1
	var enemy_adv: bool = false
	var enemy_disadv: bool = disadv_next_attack
	disadv_next_attack = false  # World Tree Grip of the Forest R3 — consumed after one attack
	if enemy_adv != enemy_disadv:
		die2 = Rng.roll(20)
		die = maxi(die1, die2) if enemy_adv else mini(die1, die2)
	var roll: int = die + attack_bonus
	var bonus: int = attack_bonus
	var is_crit: bool = die == 20
	return {
		"die": die, "die1": die1, "die2": die2, "bonus": bonus, "roll": roll, "target_ac": target_ac,
		"is_crit": is_crit, "is_hit": is_crit or roll >= target_ac,
		"adv": enemy_adv and not enemy_disadv, "disadv": enemy_disadv and not enemy_adv,
	}

func _attack_player(_player: Player) -> void:
	# Rage's duration refresh cares about being attacked at all, not just being hit — set
	# regardless of the roll's outcome (see player.gd._on_turn_started()'s rage tick).
	GameState.player_attacked_this_turn = true
	var invincible: bool = GameState.invincible
	var bracket_l: String = "[" if invincible else ""
	var bracket_r: String = "]" if invincible else ""
	var r: Dictionary = _resolve_attack_roll(GameState.player_stats.armor_class)
	var hit_meta: String = "ehit:die=%d,d1=%d,d2=%d,bonus=%d,total=%d,ac=%d,crit=%d,adv=%d,disadv=%d" % [
		r["die"], r["die1"], r["die2"], r["bonus"], r["roll"], r["target_ac"],
		1 if r["is_crit"] else 0, 1 if r["adv"] else 0, 1 if r["disadv"] else 0]
	if not r["is_hit"]:
		var miss_suffix: String = " [color=gray](d20%+d=%d vs AC %d)[/color]" % [r["bonus"], r["roll"], r["target_ac"]] if GameState.god_mode else ""
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s]misses[/url]!%s%s" % [bracket_l, display_name, hit_meta, miss_suffix, bracket_r])
		return
	var is_crit: bool = r["is_crit"]
	var dmg_roll: int = stats.roll_damage()
	var dmg: int = dmg_roll * (2 if is_crit else 1)
	if is_crit:
		AudioManager.play("crit")
	else:
		AudioManager.play("player_hurt")
	# Route through take_damage_raw for rage DR; enemies deal Bludgeoning by default.
	# take_damage_raw handles player_hp_changed and check_player_death internally.
	# Invincible: skip the actual HP change but still roll/log normally (wrapped in [] for debugging).
	var actual: int = 0 if invincible else GameState.take_damage_raw(dmg, false, "Bludgeoning")
	if _dungeon_floor != null and not invincible:
		_dungeon_floor.show_damage(_player.position, actual, true)
	var dmg_meta: String = "edmg:roll=%d,min=%d,max=%d,crit=%d,final=%d" % [dmg_roll, stats.min_damage, stats.max_damage, 1 if is_crit else 0, actual]
	var god_suffix: String = " [color=gray](d20%+d=%d vs AC %d)[/color]" % [r["bonus"], r["roll"], r["target_ac"]] if GameState.god_mode else ""
	if is_crit:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s][color=red]CRITICAL HIT![/color][/url] for [url=%s][color=yellow]%d[/color][/url] dmg.%s%s" % [bracket_l, display_name, hit_meta, dmg_meta, actual, god_suffix, bracket_r])
	else:
		GameState.game_log("%s[color=tomato]%s[/color] [url=%s]hits[/url] you for [url=%s][color=yellow]%d[/color][/url] dmg.%s%s" % [bracket_l, display_name, hit_meta, dmg_meta, actual, god_suffix, bracket_r])
	# Orc Shaman applies poison on hit
	if not invincible and display_name == "Orc Shaman" and GameState.player_stats.poison_turns < 3:
		if GameState.apply_player_status("poison", 3):
			GameState.game_log("[color=lime]You are poisoned! (3 turns)[/color]")

# Companion (Wild Heart summon) as attack target — see docs/architecture/enemy_system_architecture.md §5.
# No invincible/poison/Retaliation hooks: those are player-only systems. Companion.take_damage_from_enemy()
# already logs the hit/HP line and handles death, so only the miss line needs logging here.
func _attack_companion(companion: Companion) -> void:
	var r: Dictionary = _resolve_attack_roll(companion.stats.armor_class)
	if not r["is_hit"]:
		GameState.game_log("[color=tomato]%s[/color] attacks %s and misses!" % [display_name, companion.animal_name])
		return
	var dmg_roll: int = stats.roll_damage()
	var dmg: int = dmg_roll * (2 if r["is_crit"] else 1)
	if r["is_crit"]:
		AudioManager.play("crit")
	else:
		AudioManager.play("player_hurt")
	companion.take_damage_from_enemy(dmg)
