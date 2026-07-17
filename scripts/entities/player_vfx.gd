class_name PlayerVfx
extends Node

# Misc combat/movement VFX + the ADV surprise-attack check. Composition child-node split out
# of player.gd — see scripts/entities/CLAUDE.md.

const SWORD_SPRITE := "res://sprites/weapons/weapon_anime_sword.png"

var player: Player

func leave_blood_trail(pos: Vector2i) -> void:
	if player._dungeon_floor != null and GameState.player_stats.bleeding_turns > 0:
		player._dungeon_floor.place_blood_decal(pos)

func has_advantage(enemy: Enemy) -> bool:
	if enemy.just_crossed_door:
		enemy.just_crossed_door = false
		return true
	# Fog Cloud (Blinded): attack rolls against a Blinded creature have Advantage.
	if GameState.is_in_fog_cloud(enemy.grid_pos):
		return true
	return enemy.behavior == Enemy.Behavior.SLEEPING

func show_surprise_mark(enemy: Enemy) -> void:
	if not is_instance_valid(enemy):
		return
	var lbl := Label.new()
	lbl.text = "!"
	lbl.add_theme_font_size_override("font_size", 20)
	lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.0))
	lbl.position = enemy.position + Vector2(-4.0, -26.0)
	lbl.z_index = 10
	player.get_parent().add_child(lbl)
	var tween := lbl.create_tween()
	tween.tween_property(lbl, "position:y", lbl.position.y - 10.0, 0.7)
	tween.parallel().tween_property(lbl, "modulate:a", 0.0, 0.7).set_delay(0.3)
	tween.tween_callback(lbl.queue_free)

func flash_hit(target: Entity) -> void:
	if not is_instance_valid(target):
		return
	var tween := target.create_tween()
	tween.tween_property(target, "modulate", Color(1.8, 0.3, 0.3), 0.05)
	tween.tween_property(target, "modulate", Color(1.0, 1.0, 1.0), 0.1)

func show_sword_slash(dir: Vector2i) -> void:
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
	pivot.position = player._tile_center(player.grid_pos)
	pivot.z_index = 5
	pivot.rotation = attack_angle - deg_to_rad(start_off)

	var slash := Sprite2D.new()
	slash.texture = load(weapon_path)
	slash.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	slash.position = Vector2(12.0, 0.0)
	# All 0x72 weapon sprites point upper-right (~45°); rotate to point right.
	slash.rotation = -PI * 0.25

	pivot.add_child(slash)
	player.get_parent().add_child(pivot)

	var tween := pivot.create_tween()
	tween.tween_property(pivot, "rotation", attack_angle + deg_to_rad(end_off), dur) \
		.set_trans(Tween.TRANS_CUBIC).set_ease(Tween.EASE_OUT)
	tween.parallel().tween_property(slash, "modulate:a", 0.0, dur * 0.4).set_delay(dur * 0.6)
	tween.tween_callback(pivot.queue_free)

func screen_shake(strength: float = 5.0) -> void:
	if player._camera == null:
		return
	var t := player.create_tween()
	for i: int in 8:
		t.tween_callback(func():
			player._camera.offset = Vector2(randf_range(-strength, strength), randf_range(-strength, strength))
		)
		t.tween_interval(0.035)
	t.tween_callback(func(): player._camera.offset = Vector2.ZERO)
