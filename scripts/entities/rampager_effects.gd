class_name RampagerEffects
extends RefCounted

# Resolution for the Rampager class's abilities (docs/architecture/rampager-class-design.md).
# Static, self-contained — mirrors HybridEffects almost exactly (same cooldown + nova economy),
# just STR-based power math and a collision hook instead of surface reactions.
#
# Ability math: SpellEffects._attack_bonus(stats) / _save_dc(stats) fall back to
# proficiency_bonus + INT modifier for a null caster — the Rampager wants STR, so the two entry
# points below add (str_mod - int_mod) to realign onto rampager_attack_bonus / rampager_power_dc.

# ── shared helpers (copied from HybridEffects — kept local, no cross-class coupling) ──
static func _dice(def: Dictionary) -> Array:
	var s: String = str(def.get("dice", "1d6"))
	var bits: PackedStringArray = s.split("d")
	return [int(bits[0]), int(bits[1])]

static func _str_realign(stats: Stats) -> int:
	# SpellEffects helpers use INT; Rampager power is STR. Shift by the modifier difference.
	return stats.str_modifier() - stats.int_modifier()

static func _deal(target: Enemy, count: int, sides: int, dtype: String, is_crit: bool, dungeon_floor: Node, stack_index: int = 0) -> Dictionary:
	var rolls: Array[int] = Rng.roll_dice(count, sides)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, sides, [], is_crit, dtype)
	var result: Dictionary = target.take_typed_damage(inst["subtotal"], dtype, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, result["actual"], false, CombatMath.damage_type_color(dtype), stack_index)
	return {"actual": int(result["actual"]), "meta": CombatMath.encode_damage_instance(inst), "lethal": target.stats.is_dead()}

static func _finish(player: Player, dungeon_floor: Node) -> void:
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn(false, true)

# ── Overrun (cooldown charge + ram) ─────────────────────────────────────────
static func overrun(player: Player, def: Dictionary, dest: Vector2i, dungeon_floor: Node) -> void:
	if dungeon_floor == null:
		return
	var from: Vector2i = player.grid_pos
	var dv: Vector2i = dest - from
	if maxi(absi(dv.x), absi(dv.y)) == 0:
		return
	var step: Vector2i = Vector2i(signi(dv.x), signi(dv.y))
	var reach: int = int(def.get("range", 4))
	# Walk the straight line; stop before the first wall or occupied tile.
	var landing: Vector2i = from
	var rammed: Enemy = null
	for _i: int in reach:
		var nxt: Vector2i = landing + step
		var e: Enemy = dungeon_floor.get_enemy_at(nxt)
		if e != null and not e.stats.is_dead():
			rammed = e
			break
		if not dungeon_floor.is_walkable(nxt):
			break
		landing = nxt
	if landing == from and rammed == null:
		GameState.game_log("[color=gray]Overrun: nowhere to charge that way.[/color]")
		return

	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = step.x < 0
	if landing != from:
		await player.move_to(landing)

	if rammed != null and is_instance_valid(rammed) and not rammed.stats.is_dead():
		var stats: Stats = player.stats
		rammed.on_disturbed(player.grid_pos)
		var r := CombatMath.roll_with_adv_disadv(0, 0)
		var die: int = r["die"]
		var atk: int = SpellEffects._attack_bonus(stats) + _str_realign(stats) + CombatMath.exhaustion_penalty()
		var roll: int = die + atk
		var is_crit: bool = CombatMath.is_critical_hit(die, r["adv"])
		var dc_ac: int = rammed.stats.armor_class
		sprite.play("hit")
		await sprite.animation_finished
		sprite.play("idle")
		var parts: Array = _dice(def)
		if not is_crit and (die == 1 or roll < dc_ac):
			GameState.game_log(CombatMath.wrap_halfling_luck("You charge [color=orange]%s[/color] with [color=cyan]Overrun[/color] - miss (%d vs AC %d)." % [rammed.display_name, roll, dc_ac], r["lucky"]))
			AudioManager.play("miss_enemy")
			_finish(player, dungeon_floor)
			return
		player._vfx.flash_hit(rammed)
		var d: Dictionary = _deal(rammed, parts[0], parts[1], def["damage_type"], is_crit, dungeon_floor)
		GameState.game_log(CombatMath.wrap_halfling_luck("%sYou ram [color=orange]%s[/color] with [color=cyan]Overrun[/color] for [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
			"CRIT! " if is_crit else "", rammed.display_name, d["meta"], d["actual"], def["damage_type"], CombatMath.death_suffix(d["lethal"])], r["lucky"]))
		if d["lethal"]:
			player._finish_kill(rammed)
		elif is_instance_valid(rammed):
			await dungeon_floor.resolve_push(rammed, step)
	_finish(player, dungeon_floor)

# ── Shockwave (fury nova — STR save AoE + Prone) ────────────────────────────
static func shockwave(player: Player, def: Dictionary, center: Vector2i, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var rad: int = int(def.get("shape_size", 2))
	var parts: Array = _dice(def)
	var base_rolls: Array[int] = Rng.roll_dice(parts[0], parts[1])
	var base_inst: Dictionary = CombatMath.build_damage_instance(base_rolls, parts[1], [], false, def["damage_type"])
	var full: int = int(base_inst["subtotal"])
	var dc: int = SpellEffects._save_dc(stats) + _str_realign(stats)

	GameState.game_log("[color=cyan]Shockwave: the ground erupts![/color]")
	if dungeon_floor != null and dungeon_floor.has_method("play_impact_vfx"):
		dungeon_floor.play_impact_vfx(Vector2(center.x * DungeonFloor.TILE_SIZE + 8, center.y * DungeonFloor.TILE_SIZE + 8), "explosion_large", float(2 * rad + 1) * DungeonFloor.TILE_SIZE)

	var any_prone := false
	if dungeon_floor != null:
		for e: Enemy in dungeon_floor.get_all_enemies():
			if not is_instance_valid(e) or e.stats.is_dead():
				continue
			if e.min_dist_to(center) > rad or not dungeon_floor.has_ranged_los(center, e.grid_pos):
				continue
			e.on_disturbed(player.grid_pos)
			var save: Dictionary = e.resist_check_detailed(dc)  # STR save (all-false default)
			var amount: int = full if not save["pass"] else full / 2
			var res: Dictionary = e.take_typed_damage(amount, def["damage_type"])
			var inst: Dictionary = base_inst.duplicate()
			inst["final"] = res["actual"]; inst["resist_mul"] = res["mul"]
			e.update_hp_bar()
			dungeon_floor.show_damage(e.position, res["actual"], false, CombatMath.damage_type_color(def["damage_type"]))
			var lethal: bool = e.stats.is_dead()
			GameState.game_log("[color=orange]%s[/color] takes [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
				e.display_name, CombatMath.encode_damage_instance(inst), res["actual"], def["damage_type"], CombatMath.death_suffix(lethal)])
			if lethal:
				player._finish_kill(e)
			elif not save["pass"]:
				e.apply_status("prone", 1)
				any_prone = true
	if any_prone:
		GameState.game_log("[color=cyan]The blast knocks them off their feet![/color]")
	_finish(player, dungeon_floor)
