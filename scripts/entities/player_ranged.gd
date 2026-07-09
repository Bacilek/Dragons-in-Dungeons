class_name PlayerRanged
extends Node

# Ranged combat: range/LOS checks, the ranged attack roll, projectile VFX, and ranged-at-tile.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.

const ARROW_SPRITE := "res://sprites/weapons/weapon_arrow.png"

var player: Player

# Range gate for ranged weapons: within a weapon's "normal" range (weapon.range), the shot
# rolls normally. Beyond normal range but within the player's live FOV (DungeonFloor.FOV_RADIUS,
# gated by actual is_tile_visible — not just distance, so shots around corners don't count) the
# shot is still possible but will roll with Disadvantage (see ranged_shot_disadvantage()).
# "Long range" is intentionally NOT a per-weapon field — every ranged weapon shares this same
# FOV-based long-range rule; only the normal range differs per weapon.
func is_ranged_target_in_range(weapon: Item, target_pos: Vector2i) -> bool:
	if weapon == null or player._dungeon_floor == null:
		return false
	var d: Vector2i = target_pos - player.grid_pos
	var dist_sq: int = d.x * d.x + d.y * d.y
	var fov_r: int = DungeonFloor.FOV_RADIUS
	if dist_sq > fov_r * fov_r:
		return false
	if dist_sq > weapon.range * weapon.range and not player._dungeon_floor.is_tile_visible(target_pos):
		return false
	return true

func ranged_shot_disadvantage(weapon: Item, target_pos: Vector2i) -> bool:
	if weapon == null:
		return false
	var d: Vector2i = target_pos - player.grid_pos
	return (d.x * d.x + d.y * d.y) > weapon.range * weapon.range

func is_in_ranged_range(enemy: Enemy) -> bool:
	var weapon: Item = GameState.equipped_ranged
	if weapon == null or not weapon.is_ranged or player._dungeon_floor == null:
		return false
	return is_ranged_target_in_range(weapon, enemy.grid_pos) \
		and player._dungeon_floor.has_ranged_los(player.grid_pos, enemy.grid_pos)

func ranged_attack(enemy: Enemy) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = enemy.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var weapon: Item = GameState.equipped_ranged

	# Ammo check + consume happens BEFORE the projectile animation, so a shot that can't fire
	# never plays the arrow-fly VFX. Named ammo (weapon.ammo_item_name) takes priority over the
	# legacy consumes_on_ranged (weapon's own stack) path below, which stays unchanged for
	# weapons that don't set ammo_item_name (e.g. old Throwing-Dagger-style items).
	var ammo_item: Item = null
	if weapon != null and not weapon.ammo_item_name.is_empty():
		ammo_item = player._ammo.find_ammo_stack(weapon.ammo_item_name)
		if ammo_item == null:
			GameState.game_log("[color=red]No %s left![/color]" % weapon.ammo_item_name)
			if player._dungeon_floor != null:
				player._dungeon_floor.update_fog(player.grid_pos)
			player._handle_post_attack_turn()
			return
		if not GameState.invincible:
			ammo_item.quantity -= 1
			if ammo_item.quantity <= 0:
				player._ammo.remove_ammo_stack(weapon.ammo_item_name)
			GameState.inventory_changed.emit()
	elif weapon != null and weapon.consumes_on_ranged and not GameState.invincible:
		weapon.quantity -= 1
		GameState.inventory_changed.emit()
		if weapon.quantity <= 0:
			GameState.equipment["ranged"] = null
			GameState.recalculate_stats()
			GameState.equipment_changed.emit()
			GameState.game_log("[color=gray]Last throwing dagger used.[/color]")

	show_projectile(enemy.position, weapon)

	var dex_mod: int = player.stats.dex_modifier()
	var prof: int = CombatMath.weapon_prof_bonus(weapon, player.stats.proficiency_bonus, player.stats.proficient_simple_weapons, player.stats.proficient_martial_weapons)
	var weapon_bonus: int = (weapon.bonus_damage if weapon != null else 0) + prof
	# Advantage / Disadvantage: sources are counted (house rule — net decides outcome, not
	# a simple boolean OR/cancel). See player.gd._bump_attack() for the reference melee implementation.
	var adv_count: int = 0
	adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if player._vfx.has_advantage(enemy): adv_count += 1
	if player.stats.zealous_presence_turns > 0: adv_count += 1
	# Vex: if the flag targets this exact enemy, grant ADV and consume it on this attempt.
	var vex_triggered: bool = player._vex_adv_target == enemy
	if vex_triggered: adv_count += 1
	# Disadvantage: ranged weapon fired at melee range (Chebyshev distance 1), Heavy weapon with
	# DEX < 13, or a long-range shot (beyond the weapon's normal range but within FOV).
	var d_vec: Vector2i = enemy.grid_pos - player.grid_pos
	if maxi(abs(d_vec.x), abs(d_vec.y)) <= 1: disadv_count += 1
	if weapon != null and weapon.is_heavy and player.stats.dexterity < 13: disadv_count += 1
	if ranged_shot_disadvantage(weapon, enemy.grid_pos): disadv_count += 1
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	if vex_triggered:
		player._vex_adv_target = null
	var roll: int = die + dex_mod + weapon_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit_or_kill()
		player._berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1

	var r_wpn_enh: int = weapon.bonus_damage if weapon != null else 0
	var hit_meta: String = "rhit:die=%d,d1=%d,d2=%d,dex=%d,prof=%d,wpn=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d" % [
		die, die1, die2, dex_mod, prof, r_wpn_enh, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0]

	# Zealot Strike / Judgement Day are melee-only (see markdowns/zealot.md) — no ranged hook here.
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log("You shoot at [color=orange]%s[/color] — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color])
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		# A miss against a still-alive enemy leaves the arrow lodged in it — no floor pickup at
		# all, same as a non-lethal hit (see PlayerAmmo.resolve_ammo_landing()'s doc comment).
		# Only a killing shot still rolls the existing 50% corpse-drop via _finish_kill().
		if player._dungeon_floor != null:
			player._dungeon_floor.update_fog(player.grid_pos)
		player._handle_post_attack_turn()
		return

	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play("ranged_hit")
	player._vfx.flash_hit(enemy)
	if adv and not disadv:
		player._vfx.show_surprise_mark(enemy)
	if weapon != null and weapon.weapon_mastery == "Vex" and player.stats.knows_mastery("Vex"):
		player._vex_adv_target = enemy
	var r_dmin: int = weapon.damage_die_min if weapon != null and weapon.damage_die_min > 0 else player.stats.base_min_damage
	var r_dmax: int = weapon.damage_die_max if weapon != null and weapon.damage_die_max > 0 else player.stats.base_max_damage
	var r_die_roll: int = Rng.range_i(r_dmin, r_dmax)
	var r_pre_crit: int = r_die_roll + r_wpn_enh + dex_mod
	if is_crit:
		r_pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var actual: int = enemy.stats.take_damage(r_pre_crit)
	enemy.update_hp_bar()
	if player._dungeon_floor != null:
		player._dungeon_floor.show_damage(enemy.position, actual, false)

	var bonus_sources: String = CombatMath.encode_bonus_sources([])
	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,dex=%d,bonus=%s,crit=%d,final=%d" % [
		r_die_roll, r_dmin, r_dmax, r_wpn_enh, dex_mod, bonus_sources, 1 if is_crit else 0, actual]
	var r_dmg_type: String = weapon.damage_type if weapon != null and not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var r_type_tag: String = " [color=gray]%s[/color]" % r_dmg_type

	if is_crit:
		GameState.game_log("[color=red]CRIT![/color] You [url=%s]shoot[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, enemy.display_name, dmg_meta, actual, r_type_tag])
	else:
		GameState.game_log("You [url=%s]shoot[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg." % [hit_meta, enemy.display_name, dmg_meta, actual, r_type_tag])

	if enemy.stats.is_dead():
		# Enemy died to this shot — arrow drop-from-corpse (50% chance) is handled inside
		# _finish_kill so it can use the corpse's final tile after remove_enemy()/die().
		# If the enemy survives (branch not taken), the arrow stays embedded — no pickup.
		player._finish_kill(enemy, ammo_item)
	elif weapon != null and weapon.weapon_mastery == "Push" and player.stats.knows_mastery("Push") and player._dungeon_floor != null:
		var push_dc: int = 8 + prof + dex_mod
		if not enemy.resist_check(push_dc, true):
			var away_dir: Vector2i = Vector2i(sign(enemy.grid_pos.x - player.grid_pos.x), sign(enemy.grid_pos.y - player.grid_pos.y))
			if away_dir != Vector2i.ZERO:
				await player._dungeon_floor.resolve_push(enemy, away_dir)
		else:
			GameState.game_log("[color=gray]Push: %s resists the shove.[/color]" % enemy.display_name)
	elif weapon != null and weapon.weapon_mastery == "Slow" and player.stats.knows_mastery("Slow"):
		enemy.slowed_turns = maxi(enemy.slowed_turns, 1)
		GameState.game_log("[color=gray]Slow: %s is slowed.[/color]" % enemy.display_name)
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

func show_projectile(target_world_pos: Vector2, weapon: Item) -> void:
	if weapon == null:
		return
	var proj_path: String
	var tumble: bool = false
	match weapon.item_name:
		"Heavy Crossbow":
			proj_path = ARROW_SPRITE
			tumble = true
		_: proj_path = ARROW_SPRITE

	AudioManager.play("shoot")
	var tex: Texture2D = load(proj_path)
	var from: Vector2 = player._tile_center(player.grid_pos)
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
		player.get_parent().add_child(sp)
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

func ranged_attack_tile(target_pos: Vector2i) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	var weapon: Item = GameState.equipped_ranged
	var ammo_item: Item = null
	if weapon != null and not weapon.ammo_item_name.is_empty():
		ammo_item = player._ammo.find_ammo_stack(weapon.ammo_item_name)
		if ammo_item == null:
			GameState.game_log("[color=red]No %s left![/color]" % weapon.ammo_item_name)
			if player._dungeon_floor != null:
				player._dungeon_floor.update_fog(player.grid_pos)
			player._handle_post_attack_turn()
			return
		if not GameState.invincible:
			ammo_item.quantity -= 1
			if ammo_item.quantity <= 0:
				player._ammo.remove_ammo_stack(weapon.ammo_item_name)
			GameState.inventory_changed.emit()
	elif weapon != null and weapon.consumes_on_ranged and not GameState.invincible:
		weapon.quantity -= 1
		GameState.inventory_changed.emit()
		if weapon.quantity <= 0:
			GameState.equipment["ranged"] = null
			GameState.recalculate_stats()
			GameState.equipment_changed.emit()
			GameState.game_log("[color=gray]Last throwing dagger thrown.[/color]")
	var target_world: Vector2 = Vector2(target_pos.x * 16 + 8, target_pos.y * 16 + 8)
	show_projectile(target_world, weapon)
	player._ammo.resolve_ammo_landing(ammo_item, target_pos)
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()
