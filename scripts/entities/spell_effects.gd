class_name SpellEffects
extends RefCounted

# Cast resolution for the cantrip-only slice of docs/architecture/spellcasting-design.md.
# Static helper, mirrors CombatMath/TooltipFormatters' pattern. Self-contained like
# PlayerRanged.ranged_attack() — owns the full turn envelope (begin_player_action ...
# _handle_post_attack_turn), not just the roll/damage math.

const TIER_LEVELS: Array[int] = [1, 5, 11, 17]

# Caster-optional spellcasting math — every player character can end up casting a spell (Scroll
# of <Spell>, Item.scroll_spell_id, castable by any class), but only Stats.caster (Wizard) has a
# SpellcasterState with its own spellcasting_ability. Anyone without one uses proficiency_bonus +
# INT modifier, per the design call in CLAUDE.md ("non-casters use INT as their casting stat").
static func _attack_bonus(stats: Stats) -> int:
	if stats.caster != null:
		return stats.caster.spell_attack_bonus(stats)
	return stats.proficiency_bonus + stats.int_modifier()

static func _save_dc(stats: Stats) -> int:
	if stats.caster != null:
		return stats.caster.spell_save_dc(stats)
	return 8 + stats.proficiency_bonus + stats.int_modifier()

static func _cast_ability_mod(stats: Stats) -> int:
	if stats.caster != null:
		return stats.caster._ability_mod(stats)
	return stats.int_modifier()

static func _cantrip_tier(character_level: int) -> int:
	var tier: int = 1
	for i: int in TIER_LEVELS.size():
		if character_level >= TIER_LEVELS[i]:
			tier = i + 1
	return tier

static func cast_spell(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var attack_bonus: int = _attack_bonus(stats)

	var adv_count: int = 0
	adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if player._vfx.has_advantage(target): adv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	var d_vec: Vector2i = target.grid_pos - player.grid_pos
	if spell.range_tiles > 1 and maxi(abs(d_vec.x), abs(d_vec.y)) <= 1: disadv_count += 1

	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + attack_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit()
		player._berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1

	var hit_meta: String = "sphit:die=%d,d1=%d,d2=%d,int=%d,prof=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d" % [
		die, die1, die2, _cast_ability_mod(stats), stats.proficiency_bonus, roll, target.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0, 1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0]

	if not is_crit and (is_nat_one or roll < target.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("You cast [color=cyan]%s[/color] at [color=orange]%s[/color] — [url=%s]%s[/url]." % [spell.spell_name, target.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		if dungeon_floor != null:
			dungeon_floor.update_fog(player.grid_pos)
		player._handle_post_attack_turn()
		return

	if is_crit: AudioManager.play_crit(null)
	else: AudioManager.play("ranged_hit")
	player._vfx.flash_hit(target)
	if adv and not disadv:
		player._vfx.show_surprise_mark(target)

	var tier: int = _cantrip_tier(stats.character_level) if spell.cantrip_tier_scaling else 1
	var dice_count: int = spell.dice_count * tier
	var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], is_crit, spell.damage_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var result: Dictionary = target.take_typed_damage(inst["subtotal"], spell.damage_type)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(spell.damage_type))

	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % spell.damage_type
	var is_lethal: bool = target.stats.is_dead()

	var verb: String = "CRIT! " if is_crit else ""
	GameState.game_log(CombatMath.wrap_halfling_luck("%sYou [url=%s]cast[/url] [color=cyan]%s[/color] at [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [
		verb, hit_meta, spell.spell_name, target.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)], r["lucky"]))

	if is_lethal:
		player._finish_kill(target)
	else:
		match spell.effect_id:
			"ray_of_frost":
				var dc: int = _save_dc(stats)
				var save: Dictionary = target.resist_check_detailed(dc, false)
				var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d" % [
					save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"])]
				if not save["pass"]:
					target.frozen_feet_turns = maxi(target.frozen_feet_turns, 1)
					GameState.game_log("[color=cyan]%s's feet [url=%s]freeze[/url] to the ground![/color]" % [target.display_name, save_meta])
				else:
					GameState.game_log("[color=gray]%s [url=%s]resists[/url] the freeze.[/color]" % [target.display_name, save_meta])
			"shocking_grasp":
				target.shocked_no_oa = true
				GameState.game_log("[color=cyan]%s is Shocked![/color]" % target.display_name)
			_:
				if dungeon_floor != null and dungeon_floor.get_tile_type(target.grid_pos) == DungeonData.TileType.GRASS:
					dungeon_floor.destroy_grass(target.grid_pos)
					GameState.game_log("[color=orange]The grass catches fire![/color]")

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Casting at an empty tile (no enemy there) — still costs the turn (same convention as
# PlayerRanged.ranged_attack_tile()), but there's no attack roll/target: nothing happens unless
# the tile itself is flammable (Fire Bolt's grass-ignite side effect, generic-path spells only).
static func cast_spell_at_tile(player: Player, spell: Spell, tile_pos: Vector2i, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = tile_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	if spell.effect_id == "" and dungeon_floor != null and dungeon_floor.get_tile_type(tile_pos) == DungeonData.TileType.GRASS:
		dungeon_floor.destroy_grass(tile_pos)
		GameState.game_log("[color=orange]The grass catches fire![/color]")

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# ── Leveled spells (docs/architecture/leveled-spells-and-slots-plan.md) ──────────────────────
# Deliberately simplified vs. the framework doc: always casts at the LOWEST available slot level
# (no upcast slot-level picker UI for v1 — plan §2/§9), and AoE is sphere-only (no cone/line/cube).

# from_scroll: a Scroll of <Spell> is self-contained (its magic doesn't draw on the reader's
# spellbook), so it never touches Stats.caster.slot_pool — that's true even for a Wizard reading
# a scroll of their own known spell, not just for a non-caster.
static func _consume_slot(player: Player, cast_level: int, from_scroll: bool = false) -> void:
	if from_scroll:
		return
	if cast_level > 0 and not GameState.invincible:
		player.stats.caster.slot_pool.consume(cast_level)
	GameState.spell_slots_changed.emit()

# SELF target (Shield) — no targeting, no attack roll, resolves on activation.
static func cast_leveled_self(player: Player, spell: Spell, cast_level: int, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	_consume_slot(player, cast_level, from_scroll)
	match spell.effect_id:
		"shield":
			player.stats.shield_ac_bonus = 5
			GameState.recalculate_stats()
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — AC +5 until your next turn.[/color]" % spell.spell_name)
		"mage_armor":
			var has_armor: bool = (GameState.equipment.get("armor") as Item) != null
			if has_armor:
				GameState.game_log("[color=gray]You cast [b]%s[/b], but your armor blocks it from taking hold.[/color]" % spell.spell_name)
			else:
				player.stats.mage_armor_active = true
				GameState.recalculate_stats()
				GameState.game_log("[color=cyan]You cast [b]%s[/b] — a shimmering force settles over you.[/color]" % spell.spell_name)
		_:
			GameState.game_log("[color=cyan]You cast [b]%s[/b].[/color]" % spell.spell_name)
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# TILE target (Misty Step teleport, Fireball AoE) — no attack roll against the tile itself.
static func cast_leveled_at_tile(player: Player, spell: Spell, cast_level: int, tile_pos: Vector2i, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	_consume_slot(player, cast_level, from_scroll)
	match spell.effect_id:
		"misty_step":
			player.set_grid_pos(tile_pos)
			GameState.player_grid_pos = tile_pos
			GameState.game_log("[color=cyan]You blink in a puff of silver mist.[/color]")
		_:
			if spell.shape == "sphere":
				_resolve_sphere_aoe(player, spell, cast_level, tile_pos, dungeon_floor)
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Sphere AoE damage-SAVE resolution (Fireball). Friendly fire is real — hits the player and any
# enemy within shape_size tiles (Euclidean, matching the framework doc §6.1 convention) with LOS
# from the impact tile. Damage-stacking RULE: one take_damage()/show_damage() call per target.
static func _resolve_sphere_aoe(player: Player, spell: Spell, cast_level: int, center: Vector2i, dungeon_floor: Node) -> void:
	var stats: Stats = player.stats
	var r: int = spell.shape_size
	var extra_dice: int = spell.upcast_dice_per_level * maxi(0, cast_level - spell.level)
	var dice_count: int = spell.dice_count + extra_dice
	var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
	var base_inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, "Fire")
	var roll_total: int = int(base_inst["subtotal"])

	var targets: Array[Enemy] = []
	if dungeon_floor != null:
		for e: Enemy in dungeon_floor.get_all_enemies():
			if not is_instance_valid(e) or e.stats.is_dead():
				continue
			var d: Vector2i = e.grid_pos - center
			if d.x * d.x + d.y * d.y > r * r:
				continue
			if not dungeon_floor.has_ranged_los(center, e.grid_pos):
				continue
			targets.append(e)

	# Casting always spends the cheapest AVAILABLE slot (StandardSlotPool.lowest_available_level())
	# — if the base slot level is exhausted, that can silently auto-upcast to a higher slot and add
	# upcast dice. Surface it in the log line instead of leaving a mysteriously bigger dice pool
	# unexplained.
	var upcast_note: String = "" if cast_level <= spell.level else " [color=gray](cast at %s level — your %s slots were empty)[/color]" % [SpellDb.ordinal(cast_level), SpellDb.ordinal(spell.level)]
	GameState.game_log("[color=orange]A sphere of fire erupts![/color]%s" % upcast_note)
	for e: Enemy in targets:
		var dc: int = _save_dc(stats)
		var save: Dictionary = e.resist_check_detailed(dc, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"])]
		var dmg: int = roll_total if not save["pass"] else roll_total / 2
		var result: Dictionary = e.take_typed_damage(dmg, "Fire")
		var actual: int = result["actual"]
		var inst: Dictionary = base_inst.duplicate()
		inst["final"] = actual
		inst["resist_mul"] = result["mul"]
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		e.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color("Fire"))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]%s[/url] by the flames for [url=%s][color=yellow]%d[/color][/url] Fire dmg.%s" % [
			e.display_name, save_meta, "caught" if not save["pass"] else "singed", dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

	var d_player: Vector2i = player.grid_pos - center
	if d_player.x * d_player.x + d_player.y * d_player.y <= r * r and (dungeon_floor == null or dungeon_floor.has_ranged_los(center, player.grid_pos)):
		var pdc: int = _save_dc(stats)
		var pdex_mod: int = stats.dex_modifier()
		var pprof: int = stats.proficiency_bonus if stats.check_prof_dex else 0
		var pdie: int = Rng.roll(20)
		var pcheck_total: int = pdie + pdex_mod + pprof
		var pass_save: bool = pcheck_total >= pdc
		# Same hoverable save breakdown as the enemy targets above — previously the player's own
		# catch-in-blast line had no save tooltip at all, so there was no way to see whether the
		# DEX check passed (half dmg) or failed (full dmg) for yourself specifically.
		var psave_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=DEX,pass=%d" % [
			pdie, pdex_mod, pprof, pcheck_total, pdc, int(pass_save)]
		var pdmg: int = roll_total if not pass_save else roll_total / 2
		var actual_p: int = GameState.take_damage_raw(pdmg, false, "Fire")
		var p_inst: Dictionary = base_inst.duplicate()
		p_inst["final"] = actual_p
		var pdmg_meta: String = CombatMath.encode_damage_instance(p_inst)
		# Rage/Bear-form DR and temp HP absorption can all silently shave actual_p below pdmg with
		# no indication in the tooltip (unlike enemies, GameState.take_damage_raw() doesn't return a
		# clean multiplier to plug into "rmul") — call out the pre-mitigation number in plain text
		# instead of leaving a "31 rolled but only 25 landed" gap unexplained.
		var reduced_note: String = "" if actual_p == pdmg else " [color=gray](%d before your own reductions)[/color]" % pdmg
		GameState.game_log("[color=orange]You are [url=%s]%s[/url] in your own blast for [url=%s]%d[/url] Fire dmg%s.[/color]" % [
			psave_meta, "caught" if not pass_save else "singed", pdmg_meta, actual_p, reduced_note])

# ENEMY target, AUTO_HIT resolution (Magic Missile) — no attack roll.
static func cast_leveled_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, cast_level, from_scroll)

	match spell.effect_id:
		"magic_missile":
			var darts: int = 3 + maxi(0, cast_level - spell.level)
			var dart_rolls: Array[int] = []
			var total: int = 0
			for _i: int in darts:
				var r: int = Rng.range_i(1, 4) + 1
				dart_rolls.append(r)
				total += r
			var actual: int = target.take_typed_damage(total, "Force")["actual"]
			target.update_hp_bar()
			if dungeon_floor != null:
				dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color("Force"))
			var rolls_str: String = "|".join(dart_rolls.map(func(x: int) -> String: return str(x)))
			var dmg_meta: String = "mmdmg:darts=%d,rolls=%s,total=%d,final=%d" % [darts, rolls_str, total, actual]
			var is_lethal: bool = target.stats.is_dead()
			GameState.game_log("%d darts of force streak toward %s for [url=%s][color=yellow]%d[/color][/url] Force dmg.%s" % [
				darts, target.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
			if is_lethal:
				player._finish_kill(target)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()
