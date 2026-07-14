class_name SpellEffects
extends RefCounted

# Cast resolution for the cantrip-only slice of docs/architecture/spellcasting-design.md.
# Static helper, mirrors CombatMath/TooltipFormatters' pattern. Self-contained like
# PlayerRanged.ranged_attack() — owns the full turn envelope (begin_player_action ...
# _handle_post_attack_turn), not just the roll/damage math.

const TIER_LEVELS: Array[int] = [1, 5, 11, 17]

static func _cantrip_tier(character_level: int) -> int:
	var tier: int = 1
	for i: int in TIER_LEVELS.size():
		if character_level >= TIER_LEVELS[i]:
			tier = i + 1
	return tier

static func cast_spell(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var caster: SpellcasterState = stats.caster
	var attack_bonus: int = caster.spell_attack_bonus(stats)

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
		die, die1, die2, caster._ability_mod(stats), stats.proficiency_bonus, roll, target.stats.armor_class,
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
	var roll_total: int = 0
	for _i: int in dice_count:
		roll_total += Rng.range_i(1, spell.dice_sides)
	var pre_crit: int = roll_total
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var actual: int = target.stats.take_damage(pre_crit)
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false)

	var bonus_sources: String = CombatMath.encode_bonus_sources([])
	var dmg_meta: String = "dmg:roll=%d,dmax=%d,wpn=0,bonus=%s,crit=%d,final=%d" % [
		roll_total, spell.dice_sides, bonus_sources, 1 if is_crit else 0, actual]
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
				var dc: int = caster.spell_save_dc(stats)
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

static func _consume_slot(player: Player, cast_level: int) -> void:
	if cast_level > 0 and not GameState.invincible:
		player.stats.caster.slot_pool.consume(cast_level)
	GameState.spell_slots_changed.emit()

# SELF target (Shield) — no targeting, no attack roll, resolves on activation.
static func cast_leveled_self(player: Player, spell: Spell, cast_level: int, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	_consume_slot(player, cast_level)
	match spell.effect_id:
		"shield":
			player.stats.shield_ac_bonus = 5
			GameState.recalculate_stats()
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — AC +5 until your next turn.[/color]" % spell.spell_name)
		_:
			GameState.game_log("[color=cyan]You cast [b]%s[/b].[/color]" % spell.spell_name)
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# TILE target (Misty Step teleport, Fireball AoE) — no attack roll against the tile itself.
static func cast_leveled_at_tile(player: Player, spell: Spell, cast_level: int, tile_pos: Vector2i, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	_consume_slot(player, cast_level)
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
	var caster: SpellcasterState = stats.caster
	var r: int = spell.shape_size
	var extra_dice: int = spell.upcast_dice_per_level * maxi(0, cast_level - spell.level)
	var dice_count: int = spell.dice_count + extra_dice
	var roll_total: int = 0
	for _i: int in dice_count:
		roll_total += Rng.range_i(1, spell.dice_sides)
	var dmg_meta: String = "dmg:roll=%d,dmax=%d,wpn=0,bonus=%s,crit=0,final=%d" % [
		roll_total, spell.dice_sides, CombatMath.encode_bonus_sources([]), roll_total]

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

	GameState.game_log("[color=orange]A sphere of fire erupts![/color]")
	# Book-accurate Fireball is a DEX save, but Enemy.resist_check_detailed() only supports
	# STR/CON (no enemy DEX data exists yet — same limitation Ray of Frost's cantrip already
	# accepts). Reusing the STR-flavored check here rather than inventing enemy DEX stats.
	for e: Enemy in targets:
		var dc: int = caster.spell_save_dc(stats)
		var save: Dictionary = e.resist_check_detailed(dc, false)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=STR,pass=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], int(save["pass"])]
		var dmg: int = roll_total if not save["pass"] else roll_total / 2
		var actual: int = e.stats.take_damage(dmg)
		e.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(e.position, actual, false)
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]%s[/url] by the flames for [url=%s][color=yellow]%d[/color][/url] Fire dmg.%s" % [
			e.display_name, save_meta, "caught" if not save["pass"] else "singed", dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

	var d_player: Vector2i = player.grid_pos - center
	if d_player.x * d_player.x + d_player.y * d_player.y <= r * r and (dungeon_floor == null or dungeon_floor.has_ranged_los(center, player.grid_pos)):
		var pdc: int = caster.spell_save_dc(stats)
		var check_total: int = Rng.roll(20) + stats.dex_modifier() + (stats.proficiency_bonus if stats.check_prof_dex else 0)
		var pass_save: bool = check_total >= pdc
		var pdmg: int = roll_total if not pass_save else roll_total / 2
		var actual_p: int = GameState.take_damage_raw(pdmg, false, "Fire")
		var pdmg_meta: String = "dmg:roll=%d,dmax=%d,wpn=0,bonus=%s,crit=0,final=%d" % [
			roll_total, spell.dice_sides, CombatMath.encode_bonus_sources([]), actual_p]
		GameState.game_log("[color=orange]You are caught in your own blast for [url=%s]%d[/url] Fire dmg.[/color]" % [pdmg_meta, actual_p])

# ENEMY target, AUTO_HIT resolution (Magic Missile) — no attack roll.
static func cast_leveled_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, cast_level)

	match spell.effect_id:
		"magic_missile":
			var darts: int = 3 + maxi(0, cast_level - spell.level)
			var total: int = 0
			for _i: int in darts:
				total += Rng.range_i(1, 4) + 1
			var actual: int = target.stats.take_damage(total)
			target.update_hp_bar()
			if dungeon_floor != null:
				dungeon_floor.show_damage(target.position, actual, false)
			var dmg_meta: String = "dmg:roll=%d,dmax=4,wpn=0,bonus=%s,crit=0,final=%d" % [total, CombatMath.encode_bonus_sources([]), actual]
			var is_lethal: bool = target.stats.is_dead()
			GameState.game_log("%d darts of force streak toward %s for [url=%s][color=yellow]%d[/color][/url] Force dmg.%s" % [
				darts, target.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
			if is_lethal:
				player._finish_kill(target)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()
