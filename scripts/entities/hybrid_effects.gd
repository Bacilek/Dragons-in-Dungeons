class_name HybridEffects
extends RefCounted

# Resolution for the Hybrid class's abilities (docs/architecture/hybrid-class-design.md).
# Static, self-contained like SpellEffects/PlayerRanged - each public entry owns its own
# TurnManager.begin_player_action() ... player._handle_post_attack_turn() turn envelope.
#
# Ability math reuses SpellEffects._attack_bonus(stats) / _save_dc(stats) (both fall back to
# proficiency_bonus + INT modifier when stats.caster == null, which IS the Hybrid's
# hybrid_attack_bonus / hybrid_power_dc). Damage instances go through CombatMath so the hover
# tooltips work like every other damage source.

const ARC_RADIUS_SPREAD := 2   # spark's arc reach (tiles) between wet / in-water enemies

# ── shared damage helper ─────────────────────────────────────────────────────
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

static func _on_water(dungeon_floor: Node, e: Enemy) -> bool:
	return dungeon_floor != null and dungeon_floor.get_tile_type(e.grid_pos) == DungeonData.TileType.WATER

static func _is_conductive(dungeon_floor: Node, e: Enemy) -> bool:
	return e.wet_turns > 0 or _on_water(dungeon_floor, e)

# ── Spark (cooldown attack) ──────────────────────────────────────────────────
static func spark(player: Player, def: Dictionary, target: Enemy, dungeon_floor: Node) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var was_surprised: bool = player._vfx.has_advantage(target)
	target.on_disturbed(player.grid_pos)
	var adv: int = 1 if was_surprised else 0
	var r := CombatMath.roll_with_adv_disadv(adv, 0)
	var die: int = r["die"]
	var atk: int = SpellEffects._attack_bonus(stats) + CombatMath.exhaustion_penalty()
	var roll: int = die + atk
	var is_crit: bool = CombatMath.is_critical_hit(die, r["adv"])
	var dc_ac: int = target.stats.armor_class

	var parts: Array = _dice(def)
	if not is_crit and (die == 1 or roll < dc_ac):
		GameState.game_log(CombatMath.wrap_halfling_luck("You loose [color=cyan]Spark[/color] at [color=orange]%s[/color] - miss (%d vs AC %d)." % [target.display_name, roll, dc_ac], r["lucky"]))
		AudioManager.play("miss_enemy")
		_finish(player, dungeon_floor)
		return

	player._vfx.flash_hit(target)
	var d: Dictionary = _deal(target, parts[0], parts[1], def["damage_type"], is_crit, dungeon_floor)
	GameState.game_log(CombatMath.wrap_halfling_luck("%sYou strike [color=orange]%s[/color] with [color=cyan]Spark[/color] for [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
		"CRIT! " if is_crit else "", target.display_name, d["meta"], d["actual"], def["damage_type"], CombatMath.death_suffix(d["lethal"])], r["lucky"]))
	if d["lethal"]:
		player._finish_kill(target)

	# Arc: if the primary target conducts, jump to every other conductive enemy within 2 tiles.
	if is_instance_valid(target) and _is_conductive(dungeon_floor, target) and dungeon_floor != null:
		var hit_any := false
		for e: Enemy in dungeon_floor.get_visible_enemies():
			if e == target or not is_instance_valid(e) or e.stats.is_dead():
				continue
			if e.min_dist_to(target.grid_pos) > ARC_RADIUS_SPREAD or not _is_conductive(dungeon_floor, e):
				continue
			hit_any = true
			e.on_disturbed(player.grid_pos)
			var ad: Dictionary = _deal(e, parts[0], parts[1], def["damage_type"], false, dungeon_floor)
			GameState.game_log("The current arcs to [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
				e.display_name, ad["meta"], ad["actual"], def["damage_type"], CombatMath.death_suffix(ad["lethal"])])
			if ad["lethal"]:
				player._finish_kill(e)
		if hit_any:
			GameState.game_log("[color=cyan]The water carries the charge![/color]")

	_finish(player, dungeon_floor)

# ── Tide (cooldown surface-layer) ────────────────────────────────────────────
static func tide(player: Player, def: Dictionary, center: Vector2i, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var rad: int = int(def.get("shape_size", 1))
	var soaked := 0
	if dungeon_floor != null:
		for e: Enemy in dungeon_floor.get_all_enemies():
			if not is_instance_valid(e) or e.stats.is_dead():
				continue
			if e.min_dist_to(center) > rad:
				continue
			e.apply_status("wet", 4)
			if e.stats.burning_turns > 0:
				e.stats.burning_turns = 0
			soaked += 1
		# put out burning grass in the splash
		for dy: int in range(-rad, rad + 1):
			for dx: int in range(-rad, rad + 1):
				var p: Vector2i = center + Vector2i(dx, dy)
				if dungeon_floor.has_method("douse_tile"):
					dungeon_floor.douse_tile(p)
	GameState.game_log("[color=cyan]Tide: water washes over the area%s.[/color]" % ("" if soaked == 0 else " - %d soaked" % soaked))
	_finish(player, dungeon_floor)

# ── Arc (essence nova) ──────────────────────────────────────────────────────
static func arc(player: Player, def: Dictionary, center: Vector2i, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var rad: int = int(def.get("shape_size", 2))
	var parts: Array = _dice(def)
	var base_rolls: Array[int] = Rng.roll_dice(parts[0], parts[1])
	var base_inst: Dictionary = CombatMath.build_damage_instance(base_rolls, parts[1], [], false, "Lightning")
	var full: int = int(base_inst["subtotal"])
	var dc: int = SpellEffects._save_dc(stats)

	GameState.game_log("[color=cyan]Arc: lightning cracks outward![/color]")
	if dungeon_floor != null and dungeon_floor.has_method("play_impact_vfx"):
		dungeon_floor.play_impact_vfx(Vector2(center.x * DungeonFloor.TILE_SIZE + 8, center.y * DungeonFloor.TILE_SIZE + 8), "explosion_large", float(2 * rad + 1) * DungeonFloor.TILE_SIZE)

	var conductive_hit := false
	if dungeon_floor != null:
		for e: Enemy in dungeon_floor.get_all_enemies():
			if not is_instance_valid(e) or e.stats.is_dead():
				continue
			if e.min_dist_to(center) > rad or not dungeon_floor.has_ranged_los(center, e.grid_pos):
				continue
			e.on_disturbed(player.grid_pos)
			var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, true)
			var amount: int = full if not save["pass"] else full / 2
			var res: Dictionary = e.take_typed_damage(amount, "Lightning")
			var inst: Dictionary = base_inst.duplicate()
			inst["final"] = res["actual"]; inst["resist_mul"] = res["mul"]
			e.update_hp_bar()
			dungeon_floor.show_damage(e.position, res["actual"], false, CombatMath.damage_type_color("Lightning"))
			var lethal: bool = e.stats.is_dead()
			GameState.game_log("[color=orange]%s[/color] takes [url=%s][color=yellow]%d[/color][/url] Lightning dmg.%s" % [
				e.display_name, CombatMath.encode_damage_instance(inst), res["actual"], CombatMath.death_suffix(lethal)])
			if not lethal and _is_conductive(dungeon_floor, e):
				e.apply_status("shocked", 2)
				conductive_hit = true
			if lethal:
				player._finish_kill(e)
	if conductive_hit:
		GameState.game_log("[color=cyan]The soaked ground conducts - enemies are staggered![/color]")
	_finish(player, dungeon_floor)

# ── Emberstep (cooldown dash) ───────────────────────────────────────────────
static func emberstep(player: Player, def: Dictionary, dest: Vector2i, dungeon_floor: Node) -> void:
	if dungeon_floor == null:
		return
	var from: Vector2i = player.grid_pos
	var dv: Vector2i = dest - from
	var reach: int = int(def.get("range", 3))
	if maxi(absi(dv.x), absi(dv.y)) == 0:
		return
	var step: Vector2i = Vector2i(signi(dv.x), signi(dv.y))
	# walk the straight line, stopping at the first wall / occupied tile, up to `reach`
	var landing: Vector2i = from
	var crossed: Array[Vector2i] = []
	for _i: int in reach:
		var nxt: Vector2i = landing + step
		if not dungeon_floor.is_walkable(nxt) or dungeon_floor.get_enemy_at(nxt) != null:
			break
		landing = nxt
		crossed.append(nxt)
	if landing == from:
		GameState.game_log("[color=gray]Emberstep: nowhere to go that way.[/color]")
		return
	TurnManager.begin_player_action()
	await player.move_to(landing)
	for p: Vector2i in crossed:
		if dungeon_floor.get_tile_type(p) == DungeonData.TileType.GRASS:
			dungeon_floor.ignite_grass(p)
	GameState.game_log("[color=#e8622e]Emberstep: you streak forward, leaving fire in your wake.[/color]")
	_finish(player, dungeon_floor)

# ── helpers ─────────────────────────────────────────────────────────────────
static func _dice(def: Dictionary) -> Array:
	var s: String = str(def.get("dice", "1d6"))
	var bits: PackedStringArray = s.split("d")
	return [int(bits[0]), int(bits[1])]

static func _finish(player: Player, dungeon_floor: Node) -> void:
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn(false, true)
