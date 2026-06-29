class_name Companion
extends Entity

var animal_name: String = "Squirrel"
var armor_class: int = 12
var die_count: int = 1
var die_sides: int = 6
var _config: Dictionary = {}
var _dungeon_floor: DungeonFloor

var _sprite: Sprite2D

func configure(d: Dictionary) -> void:
	_config = d
	animal_name = d.get("animal", "Squirrel")
	armor_class = d.get("ac", 12)
	die_count = d.get("die_count", 1)
	die_sides = d.get("die_sides", 6)

func _ready() -> void:
	stats = Stats.new()
	stats.max_hp = _config.get("hp", 10)
	stats.current_hp = stats.max_hp
	stats.armor_class = armor_class
	z_index = 1

	# Programmatic sprite — use wizard sprite (green tint) as placeholder
	_sprite = Sprite2D.new()
	var tex: Texture2D = null
	var candidate_path: String = "res://sprites/characters/wizzard_m_idle_anim_f0.png"
	if ResourceLoader.exists(candidate_path):
		tex = load(candidate_path) as Texture2D
	if tex == null:
		var img := Image.create(16, 16, false, Image.FORMAT_RGBA8)
		img.fill(Color(0.3, 0.9, 0.3))
		tex = ImageTexture.create_from_image(img)
	_sprite.texture = tex
	_sprite.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_sprite.offset = Vector2(0, -8)
	_sprite.modulate = Color(0.5, 1.2, 0.5)  # green tint = friendly
	add_child(_sprite)

	var col := CollisionShape2D.new()
	var shape := CapsuleShape2D.new()
	shape.radius = 5.0
	shape.height = 12.0
	col.shape = shape
	add_child(col)

	_setup_hp_bar()
	update_hp_bar()
	add_to_group("companions")
	TurnManager.register_enemy(self)  # companions share the enemy phase

func heal_to_max() -> void:
	if stats != null:
		stats.current_hp = stats.max_hp
		update_hp_bar()

func take_damage_from_enemy(amount: int) -> void:
	if stats == null:
		return
	var actual: int = maxi(1, amount)
	stats.current_hp -= actual
	update_hp_bar()
	if _dungeon_floor != null:
		_dungeon_floor.show_damage(position, actual, true)
	GameState.game_log("[color=red]%s is hit for %d! (%d/%d HP)[/color]" % [animal_name, actual, stats.current_hp, stats.max_hp])
	if stats.current_hp <= 0:
		_on_companion_die()

func _on_companion_die() -> void:
	GameState.game_log("[color=orange]%s has fallen![/color]" % animal_name)
	GameState.player_companion = null
	TurnManager.unregister_enemy(self)
	if _dungeon_floor != null:
		_dungeon_floor.remove_companion(self)
	queue_free()

func take_turn() -> void:
	if not is_instance_valid(self) or stats == null or stats.current_hp <= 0:
		return
	await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout
	if _dungeon_floor == null:
		return

	var nearest: Enemy = _find_nearest_enemy()
	if nearest != null:
		var diff: Vector2i = nearest.grid_pos - grid_pos
		if maxi(absi(diff.x), absi(diff.y)) <= 1:
			_attack_enemy(nearest)
			return
		_move_step_toward(nearest.grid_pos)
	else:
		_move_step_toward(GameState.player_grid_pos)

func _find_nearest_enemy() -> Enemy:
	if _dungeon_floor == null:
		return null
	var best: Enemy = null
	var best_dist: int = 999
	for e: Enemy in _dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		var diff: Vector2i = e.grid_pos - grid_pos
		var dist: int = maxi(absi(diff.x), absi(diff.y))
		if dist < best_dist:
			best_dist = dist
			best = e
	return best

func _attack_enemy(target: Enemy) -> void:
	if not is_instance_valid(target) or target.stats.is_dead():
		return
	var prof: int = GameState.player_stats.proficiency_bonus
	var die_roll: int = randi_range(1, 20)
	var roll: int = die_roll + prof
	if die_roll == 20 or roll >= target.stats.armor_class:
		var dmg: int = 0
		for _i: int in die_count:
			dmg += randi_range(1, die_sides)
		dmg = maxi(1, dmg)
		if die_roll == 20:
			dmg *= 2
		target.stats.take_damage(dmg)
		target.update_hp_bar()
		if _dungeon_floor != null:
			_dungeon_floor.show_damage(target.position, dmg, false)
		var crit_tag: String = " [color=red]CRIT![/color]" if die_roll == 20 else ""
		GameState.game_log("[color=lime]%s[/color] attacks [color=orange]%s[/color] for [color=yellow]%d[/color].%s" % [animal_name, target.display_name, dmg, crit_tag])
		if target.stats.is_dead():
			GameState.game_log("[color=lime]%s kills %s![/color]" % [animal_name, target.display_name])
			GameState.gain_exp(maxi(1, target.exp_reward / 2))
			_dungeon_floor.remove_enemy(target)
			target.die()
	else:
		GameState.game_log("[color=gray]%s misses %s.[/color]" % [animal_name, target.display_name])

func _move_step_toward(target_pos: Vector2i) -> void:
	if _dungeon_floor == null or target_pos == grid_pos:
		return
	var path: Array[Vector2i] = _dungeon_floor.find_path(grid_pos, target_pos)
	if path.is_empty():
		return
	var next: Vector2i = path[0]
	if _dungeon_floor.is_walkable_for_companion(next):
		if _sprite != null:
			_sprite.flip_h = next.x < grid_pos.x
		await move_to(next, 0.04 if TurnManager.fast_mode else 0.08)
