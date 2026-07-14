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
