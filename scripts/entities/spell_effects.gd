class_name SpellEffects
extends RefCounted

# Cast resolution for the cantrip-only slice of docs/architecture/spellcasting-design.md.
# Static helper, mirrors CombatMath/TooltipFormatters' pattern. Self-contained like
# PlayerRanged.ranged_attack() — owns the full turn envelope (begin_player_action ...
# _handle_post_attack_turn), not just the roll/damage math.

const TIER_LEVELS: Array[int] = [1, 5, 11, 17]
const CHROMATIC_ORB_TYPES: Array[String] = ["Acid", "Cold", "Fire", "Lightning", "Poison", "Thunder"]

# Caster-optional spellcasting math — every player character can end up casting a spell (Scroll
# of <Spell>, Item.scroll_spell_id, castable by any class), but only Stats.caster (Wizard) has a
# SpellcasterState with its own spellcasting_ability. Anyone without one uses proficiency_bonus +
# INT modifier, per the design call in CLAUDE.md ("non-casters use INT as their casting stat").
# `spell` is optional and only matters for a Tiefling casting one of their own Fiendish Legacy
# spells (scripts/entities/CLAUDE.md's "Tiefling" section) — those use "whichever of INT/WIS/CHA
# is highest" instead of the character's own class spellcasting_ability (or the INT-only
# non-caster fallback), checked BEFORE either of those. Every call site already has `spell` in
# local scope, so this never needed a second parallel set of helpers.
static func _attack_bonus(stats: Stats, spell: Spell = null) -> int:
	if spell != null and stats.character_race == Stats.CharacterRace.TIEFLING and spell.spell_id in stats.tiefling_legacy_spell_ids:
		return stats.proficiency_bonus + stats.tiefling_best_ability_mod()
	if stats.caster != null:
		return stats.caster.spell_attack_bonus(stats)
	return stats.proficiency_bonus + stats.int_modifier()

static func _save_dc(stats: Stats, spell: Spell = null) -> int:
	if spell != null and stats.character_race == Stats.CharacterRace.TIEFLING and spell.spell_id in stats.tiefling_legacy_spell_ids:
		return 8 + stats.proficiency_bonus + stats.tiefling_best_ability_mod()
	if stats.caster != null:
		return stats.caster.spell_save_dc(stats)
	return 8 + stats.proficiency_bonus + stats.int_modifier()

static func _cast_ability_mod(stats: Stats, spell: Spell = null) -> int:
	if spell != null and stats.character_race == Stats.CharacterRace.TIEFLING and spell.spell_id in stats.tiefling_legacy_spell_ids:
		return stats.tiefling_best_ability_mod()
	if stats.caster != null:
		return stats.caster._ability_mod(stats)
	return stats.int_modifier()

## Which stat label _cast_ability_mod() actually used — for the "sphit" hit tooltip, which used to
## hardcode "INT" (true back when Wizard was the only caster; wrong for Warlock's CHA, Ranger's
## WIS, and a Tiefling's highest-of-three Fiendish Legacy cast). Mirrors _cast_ability_mod()'s own
## branches exactly, including tiefling_best_ability_mod()'s maxi(int, maxi(wis, cha)) tie order.
static func _cast_ability_label(stats: Stats, spell: Spell = null) -> String:
	if spell != null and stats.character_race == Stats.CharacterRace.TIEFLING and spell.spell_id in stats.tiefling_legacy_spell_ids:
		if stats.int_modifier() >= stats.wis_modifier() and stats.int_modifier() >= stats.cha_modifier(): return "INT"
		if stats.wis_modifier() >= stats.cha_modifier(): return "WIS"
		return "CHA"
	if stats.caster != null:
		return stats.caster.spellcasting_ability
	return "INT"

# Warlock Pact Magic upcast (PactSlotPool.available_level() always returns the current pact slot
# level, so cast_level can exceed spell.level — see scripts/items/CLAUDE.md's PactSlotPool entry).
# Wizard/Ranger's own slot pools never upcast, so this is 0 for every cast through those.
static func _upcast_extra_levels(spell: Spell, cast_level: int) -> int:
	return maxi(0, cast_level - spell.level)

static func _cantrip_tier(character_level: int) -> int:
	var tier: int = 1
	for i: int in TIER_LEVELS.size():
		if character_level >= TIER_LEVELS[i]:
			tier = i + 1
	return tier

## Public wrapper — lets PlayerSpellcasting._multi_target_beam_count() derive Eldritch Blast's
## beam count (1/2/3/4 at character levels 1/5/11/17) without duplicating the tier table.
static func cantrip_tier(character_level: int) -> int:
	return _cantrip_tier(character_level)

static func cast_spell(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	await _resolve_cantrip_hit(player, spell, target, dungeon_floor)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Multi-beam cantrip (Eldritch Blast): one independent ATTACK_ROLL hit per collected target,
# gathered click-by-click in PlayerSpellcasting._handle_multi_target_click() exactly like Magic
# Missile's darts (any combination of repeats — focusing more than one beam on the same enemy is
# legal, unlike Magic Missile there's no auto-hit grouping since each beam needs its own d20).
# Barrel/door target descriptors are skipped outright (no AC to roll an attack against).
static func cast_multi_beam_cantrip(player: Player, spell: Spell, targets: Array[Dictionary], dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var first_pos: Vector2i = _mm_target_pos(targets[0])
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = first_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	for t: Dictionary in targets:
		if t["kind"] != "enemy":
			continue
		var target: Enemy = t["enemy"]
		if not is_instance_valid(target) or target.stats.is_dead():
			continue
		await _resolve_cantrip_hit(player, spell, target, dungeon_floor)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Single-target attack-roll resolution shared by cast_spell() (one target) and
# cast_multi_beam_cantrip() (one call per beam) — everything from the pre-attack ADV/DISADV state
# capture through the post-hit effect_id dispatch, EXCLUDING the swing animation and the
# turn/fog/post-attack-turn envelope, which the two callers own themselves (once per cast, not
# once per beam).
static func _resolve_cantrip_hit(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node) -> void:
	# Captured BEFORE on_disturbed() wakes the target — has_advantage() reads pre-attack
	# behavior/surprise_available state, which on_disturbed() immediately mutates away.
	var target_was_unaware: bool = player._vfx.is_target_unaware(target)
	var was_surprised: bool = player._vfx.has_advantage(target)
	target.on_disturbed(player.grid_pos)

	var stats: Stats = player.stats
	var attack_bonus: int = _attack_bonus(stats, spell)

	var adv_count: int = 0
	adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if was_surprised: adv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	# Disadvantage: ranged spell attack at melee range (Chebyshev distance 1), EXCEPT against a
	# genuinely unaware target (PlayerVfx.is_target_unaware()) — see that function's own comment
	# for why this is narrower than has_advantage()'s ADV sources (Paralyzed/Incapacitated/Faerie
	# Fire/Blinded net normally against this DISADV instead of being exempted from it).
	if spell.range_tiles > 1 and target.min_dist_to(player.grid_pos) <= 1 and not target_was_unaware: disadv_count += 1
	if GameState.is_blinded(player.grid_pos): disadv_count += 1
	if stats.has_disadvantage_condition(): disadv_count += 1
	if player._frightened_active(): disadv_count += 1
	# Prone: melee/touch spells (range_tiles <= 1) get ADV against a prone target, ranged spells
	# get DISADV — same split as every other attack-roll site.
	if target.prone:
		if spell.range_tiles <= 1: adv_count += 1
		else: disadv_count += 1

	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var sp_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + attack_bonus + sp_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit()
		player._berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1

	var hit_meta: String = "sphit:die=%d,d1=%d,d2=%d,int=%d,prof=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,stat=%s,exh=%d" % [
		die, die1, die2, _cast_ability_mod(stats, spell), stats.proficiency_bonus, roll, target.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0, 1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, _cast_ability_label(stats, spell), sp_exh]

	if not is_crit and (is_nat_one or roll < target.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("You cast [color=cyan]%s[/color] at [color=orange]%s[/color] — [url=%s]%s[/url]." % [spell.spell_name, target.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		return

	if is_crit: AudioManager.play_crit(null)
	else: AudioManager.play("ranged_hit")
	player._vfx.flash_hit(target)
	if adv and not disadv:
		player._vfx.show_surprise_mark(target)

	var tier: int = _cantrip_tier(stats.character_level) if spell.cantrip_tier_scaling else 1
	var dice_count: int = spell.dice_count * tier
	var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
	# Agonizing Blast (Eldritch Invocation): +CHA mod damage on Eldritch Blast hits — folded in as
	# a same-type flat_mods entry per the damage-stacking rule (scripts/entities/CLAUDE.md), not a
	# second instance.
	var flat_mods: Array = []
	if spell.spell_id == "eldritch_blast" and GameState.knows_invocation("agonizing_blast"):
		flat_mods.append({"name": "Agonizing Blast", "amount": stats.cha_modifier(), "color": Color(0.80, 0.60, 1.0)})
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, flat_mods, is_crit, spell.damage_type)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var result: Dictionary = target.take_typed_damage(inst["subtotal"], spell.damage_type, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
		if spell.spell_id == "fire_bolt":
			dungeon_floor.play_impact_vfx(target.position, "explosion_small")

	# Hex (Warlock): a hit against the hexed target with ANY attack — including a cantrip attack
	# roll, per the spell's own "weapon, cantrip, or spell attack" text — deals a second,
	# independent Necrotic damage instance, same shape as Hunter's Mark's Force bonus.
	var hex_actual: int = 0
	var hex_inst: Dictionary = {}
	var hex_die: int = player._warlock.hex_bonus_die(target)
	if hex_die > 0:
		var hex_rolls: Array[int] = [hex_die]
		hex_inst = CombatMath.build_damage_instance(hex_rolls, 6, [], is_crit, "Necrotic")
		var hex_result: Dictionary = target.take_typed_damage(hex_inst["subtotal"], "Necrotic", is_crit)
		hex_inst["final"] = hex_result["actual"]
		hex_inst["resist_mul"] = hex_result["mul"]
		hex_actual = hex_result["actual"]
		target.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(target.position, hex_actual, false, CombatMath.damage_type_color("Necrotic"), 1)

	# Fire/Frost/Hill Giant Ancestry: same "next attack that hits" trigger melee already has —
	# extended to spell attack rolls too, see PlayerGoliath.consume_giant_ancestry_on_hit(). Skipped
	# if this cast already killed the target — no point rolling bonus damage/Prone on a corpse.
	var gol_actual: int = 0
	var gol_inst: Dictionary = {}
	var gol_type: String = ""
	if actual > 0 and not target.stats.is_dead():
		gol_type = player._goliath.consume_giant_ancestry_on_hit(target)
		if gol_type == "Fire" or gol_type == "Cold":
			var gol_sides: int = 6 if gol_type == "Cold" else 10
			var gol_rolls: Array[int] = Rng.roll_dice(1, gol_sides)
			gol_inst = CombatMath.build_damage_instance(gol_rolls, gol_sides, [], is_crit, gol_type)
			var gol_result: Dictionary = target.take_typed_damage(gol_inst["subtotal"], gol_type, is_crit)
			gol_inst["final"] = gol_result["actual"]
			gol_inst["resist_mul"] = gol_result["mul"]
			gol_actual = gol_result["actual"]
			target.update_hp_bar()
			var gol_stack_index: int = 1
			if hex_actual > 0: gol_stack_index += 1
			if dungeon_floor != null:
				dungeon_floor.show_damage(target.position, gol_actual, false, CombatMath.damage_type_color(gol_type), gol_stack_index)
			player._goliath.finish_giant_ancestry_bonus_damage()
		elif gol_type == "Prone":
			# Hill's Prone was already applied inside consume_giant_ancestry_on_hit() — its flavor
			# line logs AFTER the primary hit line below, same ordering as Frost's own flavor line.
			player._goliath.finish_giant_ancestry_bonus_damage()

	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % spell.damage_type
	var is_lethal: bool = target.stats.is_dead()
	var dmg_segment: String = "[url=%s][color=yellow]%d[/color][/url]%s" % [dmg_meta, actual, type_tag]
	if hex_actual > 0:
		var hex_meta: String = CombatMath.encode_damage_instance(hex_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Necrotic[/color]" % [hex_meta, hex_actual]
	if gol_actual > 0:
		var gol_meta: String = CombatMath.encode_damage_instance(gol_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [gol_meta, gol_actual, gol_type]

	var verb: String = "CRIT! " if is_crit else ""
	GameState.game_log(CombatMath.wrap_halfling_luck("%sYou [url=%s]cast[/url] [color=cyan]%s[/color] at [color=orange]%s[/color] for %s dmg.%s" % [
		verb, hit_meta, spell.spell_name, target.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	# Frost/Hill Giant Ancestry flavor lines — always AFTER the primary hit line above.
	if gol_type == "Cold" and not target.stats.is_dead():
		GameState.game_log("[color=cyan]Frost's Chill slows %s.[/color]" % target.display_name)
	elif gol_type == "Prone":
		GameState.game_log("[color=cyan]Hill's Tumble knocks %s Prone.[/color]" % target.display_name)

	if is_lethal:
		player._finish_kill(target)
	else:
		match spell.effect_id:
			"ray_of_frost":
				var dc: int = _save_dc(stats, spell)
				var save: Dictionary = target.resist_check_detailed(dc, false, false, false, false, true)
				var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
					save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
				if not save["pass"]:
					target.apply_status("slowed", 3)
					GameState.game_log("[color=cyan]%s is [url=%s]slowed[/url] by the cold![/color]" % [target.display_name, save_meta])
				else:
					GameState.game_log("[color=gray]%s [url=%s]resists[/url] the freeze.[/color]" % [target.display_name, save_meta])
			"shocking_grasp":
				target.shocked_no_oa = true
				GameState.game_log("[color=cyan]%s is Shocked![/color]" % target.display_name)
			"chill_touch":
				# Only concrete hook this engine has for "can't regain HP" — blocks the
				# "regeneration" trait's next tick (see Enemy._tick_regeneration()). Doesn't stop
				# healing from other sources (potions, Zealot Strike, etc.) — documented
				# simplification, same tier as Undead-matchup being unimplemented.
				target._regen_blocked_this_round = true
				GameState.game_log("[color=cyan]%s is chilled — it can't regenerate until your next turn.[/color]" % target.display_name)
			_:
				if dungeon_floor != null and dungeon_floor.get_tile_type(target.grid_pos) == DungeonData.TileType.GRASS:
					if dungeon_floor.ignite_grass(target.grid_pos):
						GameState.game_log("[color=orange]The grass catches fire![/color]")
				elif dungeon_floor != null:
					dungeon_floor.ignite_flammable(target.grid_pos)
		# Repelling Blast (Eldritch Invocation): unconditional 1-tile push on a non-lethal Eldritch
		# Blast hit — no save, unlike the Heavy Crossbow's Push weapon mastery.
		if spell.spell_id == "eldritch_blast" and GameState.knows_invocation("repelling_blast") and dungeon_floor != null:
			var away_dir: Vector2i = Vector2i(sign(target.grid_pos.x - player.grid_pos.x), sign(target.grid_pos.y - player.grid_pos.y))
			if away_dir != Vector2i.ZERO:
				await dungeon_floor.resolve_push(target, away_dir)

# Single-target SAVE-resolution cantrips (Toll the Dead, Mind Sliver) — no attack roll, the target
# just makes a save. Mirrors cast_spell()'s turn envelope/animation but skips the hit-roll block
# entirely (there's nothing to roll against an AC).
static func cast_cantrip_save_at_enemy(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	target.on_disturbed(player.grid_pos)
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var dc: int = _save_dc(stats, spell)
	var save: Dictionary = target.resist_check_detailed(dc,
		spell.save_stat == "CON", spell.save_stat == "DEX", spell.save_stat == "WIS", spell.save_stat == "INT", true)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]

	if save["pass"]:
		GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s resists[/url].[/color]" % [
			spell.spell_name, target.display_name, save_meta, target.display_name])
	else:
		var tier: int = _cantrip_tier(stats.character_level) if spell.cantrip_tier_scaling else 1
		# Toll the Dead: bigger die (d12 instead of d8) whenever the target is already missing HP.
		var dice_sides: int = spell.dice_sides
		if spell.effect_id == "toll_the_dead" and target.stats.current_hp < target.stats.max_hp:
			dice_sides = 12
		var dice_count: int = spell.dice_count * tier
		var rolls: Array[int] = Rng.roll_dice(dice_count, dice_sides)
		var inst: Dictionary = CombatMath.build_damage_instance(rolls, dice_sides, [], false, spell.damage_type)
		var result: Dictionary = target.take_typed_damage(inst["subtotal"], spell.damage_type)
		inst["final"] = result["actual"]
		inst["resist_mul"] = result["mul"]
		var actual: int = result["actual"]
		target.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		var is_lethal: bool = target.stats.is_dead()
		GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s fails[/url] and takes [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
			spell.spell_name, target.display_name, save_meta, target.display_name, dmg_meta, actual, spell.damage_type, CombatMath.death_suffix(is_lethal)])
		if spell.effect_id == "mind_sliver" and not is_lethal:
			target.mind_sliver_penalty_die = true
			GameState.game_log("[color=cyan]%s's mind reels — their next check falters.[/color]" % target.display_name)
		if is_lethal:
			player._finish_kill(target)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Self-centered instant burst (Thunderclap) — every creature within spell.shape_size tiles of the
# CASTER (not an impact point elsewhere) rolls a CON save or takes damage. No friendly fire (the
# caster is the origin, not a target) — unlike Fireball's sphere, which can catch the caster too.
static func _resolve_thunderclap(player: Player, spell: Spell, dungeon_floor: Node) -> void:
	var stats: Stats = player.stats
	var tier: int = _cantrip_tier(stats.character_level) if spell.cantrip_tier_scaling else 1
	var dice_count: int = spell.dice_count * tier
	var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
	var base_inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, "Thunder")
	var roll_total: int = int(base_inst["subtotal"])
	var r: int = spell.shape_size

	GameState.game_log("[color=cyan]A thunderous clap bursts outward from you![/color]")
	if dungeon_floor == null:
		return
	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if maxi(absi(e.grid_pos.x - player.grid_pos.x), absi(e.grid_pos.y - player.grid_pos.y)) > r:
			continue
		if not dungeon_floor.has_ranged_los(player.grid_pos, e.grid_pos):
			continue
		e.on_disturbed(player.grid_pos)
		var dc: int = _save_dc(stats, spell)
		var save: Dictionary = e.resist_check_detailed(dc, true, false, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		if save["pass"]:
			GameState.game_log("%s [url=%s]resists[/url] the thunderclap." % [e.display_name, save_meta])
			continue
		var result: Dictionary = e.take_typed_damage(roll_total, "Thunder")
		var actual: int = result["actual"]
		var inst: Dictionary = base_inst.duplicate()
		inst["final"] = actual
		inst["resist_mul"] = result["mul"]
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		e.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color("Thunder"))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]rocked[/url] by the thunderclap for [url=%s][color=yellow]%d[/color][/url] Thunder dmg.%s" % [
			e.display_name, save_meta, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

# Light cantrip — touch almost anything except terrain/walls and living creatures and it becomes
# a real light source: DungeonFloor.update_fog() unions its own shadowcast into the player's FOV
# every turn (scripts/world/CLAUDE.md), so it genuinely pushes back the fog, not just a cosmetic
# glow. Valid targets, checked in this priority order: a floor item (never a worn/carried one), a
# door, a grass tile, or a barrel — deliberately EXCLUDES Mud/Water (and every other bare terrain
# tile) and any living entity (no enemy/player click path even resolves here). Only one Light
# source active at a time (GameState.set_light_source() replaces whatever was lit before); ends on
# rest or floor descent, or the instant the lit thing itself is gone (item picked up, door/barrel
# burnt down, grass destroyed) — see GameState.clear_light_source()'s call sites and
# DungeonFloor.update_fog()'s per-kind validity check.
static func cast_light_at_tile(player: Player, spell: Spell, tile_pos: Vector2i, dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = tile_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var target_item: Item = dungeon_floor.get_item_at(tile_pos) if dungeon_floor != null else null
	var target_kind: String = ""
	var target_desc: String = ""
	if target_item != null:
		target_kind = "item"
		target_desc = target_item.item_name
	elif dungeon_floor != null and dungeon_floor.has_door_at(tile_pos):
		target_kind = "door"
		target_desc = "door"
	elif dungeon_floor != null and dungeon_floor.get_tile_type(tile_pos) == DungeonData.TileType.GRASS:
		target_kind = "grass"
		target_desc = "grass"
	elif dungeon_floor != null and dungeon_floor.has_barrel_at(tile_pos):
		target_kind = "barrel"
		target_desc = "barrel"
	elif dungeon_floor != null and not dungeon_floor.get_trap_at(tile_pos).is_empty():
		# Shining a light directly on a trap mechanism reveals it, lit or not — same "obviously
		# visible once lit" logic as everything else Light can touch. Works on an unrevealed trap
		# too (the whole point — you couldn't tell it was there until you lit it up).
		target_kind = "trap"
		target_desc = "trap"
		dungeon_floor.reveal_trap(tile_pos)

	if target_kind == "":
		GameState.game_log("[color=gray]You must touch an object, door, patch of grass, barrel, or trap.[/color]")
	else:
		const LIGHT_COLORS: Array[Color] = [
			Color(1.0, 0.85, 0.55), Color(0.55, 0.85, 1.0), Color(0.6, 1.0, 0.65),
			Color(1.0, 0.6, 0.8), Color(0.8, 0.65, 1.0), Color(1.0, 1.0, 0.6),
		]
		var c: Color = Rng.pick(LIGHT_COLORS)
		GameState.set_light_source(tile_pos, c, target_item, target_kind)
		GameState.game_log("[color=cyan]The %s begins to glow with a soft light.[/color]" % target_desc)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Casting at an empty tile (no enemy there) — still costs the turn (same convention as
# PlayerRanged.ranged_attack_tile()), but there's no attack roll/target: nothing happens unless
# the tile itself is flammable (Fire Bolt's grass-ignite side effect, generic-path spells only).
static func cast_spell_at_tile(player: Player, spell: Spell, tile_pos: Vector2i, dungeon_floor: Node) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = tile_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	if dungeon_floor != null:
		dungeon_floor.try_shoot_tripwire(tile_pos)

	if spell.effect_id == "" and dungeon_floor != null and dungeon_floor.get_tile_type(tile_pos) == DungeonData.TileType.GRASS:
		if dungeon_floor.ignite_grass(tile_pos):
			GameState.game_log("[color=orange]The grass catches fire![/color]")
	elif spell.effect_id == "" and dungeon_floor != null:
		dungeon_floor.ignite_flammable(tile_pos)
	if spell.spell_id == "fire_bolt" and dungeon_floor != null:
		dungeon_floor.play_impact_vfx(Vector2(tile_pos.x * DungeonFloor.TILE_SIZE + 8, tile_pos.y * DungeonFloor.TILE_SIZE + 8), "explosion_small")

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# ── Leveled spells (docs/architecture/leveled-spells-and-slots-plan.md) ──────────────────────
# Deliberately simplified vs. the framework doc: no upcasting at all — a spell is locked to its own
# slot level (StandardSlotPool.available_level()), never auto-promoted to a higher still-available
# slot, and AoE is sphere-only (no cone/line/cube). God Mode (GameState.invincible) skips the
# slot-availability check entirely (PlayerSpellcasting._cast_level_for()) as well as consumption
# (_consume_slot() below) — casting never needs or spends a slot while active.

# from_scroll: a Scroll of <Spell> is self-contained (its magic doesn't draw on the reader's
# spellbook), so it never touches Stats.caster.slot_pool — that's true even for a Wizard reading
# a scroll of their own known spell, not just for a non-caster.
# An Elf lineage spell's first cast each long rest is free — Stats.is_lineage_free_cast_available()
# — checked BEFORE ever touching caster.slot_pool, so it works even for a non-caster class (a
# Barbarian Elf has no SpellcasterState at all; the free use is the only cast available to them).
static func _consume_slot(player: Player, spell: Spell, cast_level: int, from_scroll: bool = false) -> void:
	if from_scroll:
		return
	# Ritual casting (Spell.is_ritual — Detect Magic): free, no slot spent, PROVIDED no enemy is
	# currently hunting the caster. Checked before every other free-cast path since it applies
	# regardless of caster class (even a non-Wizard reading a ritual-tagged scroll — though no
	# ritual spell has one today — would still hit the from_scroll early-return above first).
	if spell.is_ritual and not player.is_being_pursued():
		GameState.spell_slots_changed.emit()
		return
	# BUGFIX: this used to unconditionally decrement elf_lineage's own counter whenever
	# is_lineage_free_cast_available() (elf OR tiefling) was true — for a Tiefling-only spell
	# (e.g. Infernal's Darkness), the elf_lineage dict never actually gates that spell_id, so the
	# real (tiefling) counter never decremented and the free cast was effectively infinite. Decrement
	# whichever pool actually contains this spell_id — the two never overlap on the same spell_id.
	if player.stats.is_lineage_free_cast_available(spell.spell_id):
		if not GameState.invincible:
			if spell.spell_id in player.stats.elf_lineage_spell_ids:
				player.stats.elf_lineage_free_casts_remaining[spell.spell_id] = player.stats.elf_lineage_free_casts_remaining.get(spell.spell_id, 0) - 1
			if spell.spell_id in player.stats.tiefling_legacy_spell_ids:
				player.stats.tiefling_legacy_free_casts_remaining[spell.spell_id] = player.stats.tiefling_legacy_free_casts_remaining.get(spell.spell_id, 0) - 1
		GameState.spell_slots_changed.emit()
		return
	if player.stats.is_gnome_lineage_free_cast_available(spell.spell_id):
		if not GameState.invincible:
			player.stats.gnome_lineage_free_casts_remaining[spell.spell_id] = player.stats.gnome_lineage_free_casts_remaining.get(spell.spell_id, 0) - 1
		GameState.spell_slots_changed.emit()
		return
	# Warlock Invocation at-will free cast — genuinely unlimited, nothing to decrement.
	if GameState.warlock_invocation_free_cast(spell.spell_id):
		GameState.spell_slots_changed.emit()
		return
	if cast_level > 0 and not GameState.invincible:
		player.stats.caster.slot_pool.consume(cast_level)
	GameState.spell_slots_changed.emit()

# SELF target (Shield) — no targeting, no attack roll, resolves on activation. `clicked` (default
# sentinel Vector2i(-1,-1) = "no touch-target choice to make") is only read by the "invisibility"/
# "longstrider" upcast branches below — see their own comments.
static func cast_leveled_self(player: Player, spell: Spell, cast_level: int, dungeon_floor: Node, from_scroll: bool = false, clicked: Vector2i = Vector2i(-1, -1)) -> void:
	# Blade Ward/Barkskin/Expeditious Retreat are all Bonus Action casts in 5e RAW (not a normal
	# action) — gated on the Bonus Action economy BEFORE the turn/slot are ever touched, see
	# scripts/entities/CLAUDE.md's "Bonus Action economy" section.
	if spell.effect_id in ["blade_ward", "barkskin", "expeditious_retreat"] and GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	_consume_slot(player, spell, cast_level, from_scroll)
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	match spell.effect_id:
		"shield":
			player.stats.shield_ac_bonus = 5
			GameState.recalculate_stats()
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — AC +5 until your next turn.[/color]" % spell.spell_name)
			# Free action (unlike every other cast_leveled_self() spell) — doesn't cost the turn,
			# so it's live for the rest of THIS turn too (e.g. right before provoking an
			# Opportunity Attack), not just the next one. Same revert_to_waiting() pattern as
			# Battlefield Expert R3's free side-step / Berserker's Frenzy.
			if dungeon_floor != null:
				dungeon_floor.update_fog(player.grid_pos)
			player._reverted_this_round = true
			TurnManager.revert_to_waiting()
			return
		"mage_armor":
			var has_armor: bool = (GameState.equipment.get("armor") as Item) != null
			if has_armor:
				GameState.game_log("[color=gray]You cast [b]%s[/b], but your armor blocks it from taking hold.[/color]" % spell.spell_name)
			else:
				player.stats.mage_armor_active = true
				GameState.recalculate_stats()
				GameState.game_log("[color=cyan]You cast [b]%s[/b] — a shimmering force settles over you.[/color]" % spell.spell_name)
		"blade_ward":
			# Concentration: only one concentration effect at a time (5e rule) — recasting Blade
			# Ward just refreshes its own duration; casting a DIFFERENT concentration spell breaks
			# this one first via GameState.end_concentration(), which also zeroes Blade Ward's own
			# turn counter (not just the id) so it can't linger after the switch.
			if player.stats.concentration_spell_id != "":
				GameState.end_concentration("" if player.stats.concentration_spell_id == "blade_ward" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "blade_ward"
			player.stats.blade_ward_turns = 10
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — attacks against you falter for up to 10 turns.[/color]" % spell.spell_name)
			# Costs a Bonus Action, not the full turn (5e RAW casting time) — same
			# revert_to_waiting() free-action pattern as Shield above.
			if not GameState.invincible:
				GameState.bonus_action_used = true
			GameState.ability_bar_changed.emit()
			if dungeon_floor != null:
				dungeon_floor.update_fog(player.grid_pos)
			player._reverted_this_round = true
			TurnManager.revert_to_waiting()
			return
		"thunderclap":
			_resolve_thunderclap(player, spell, dungeon_floor)
		"expeditious_retreat":
			if player.stats.concentration_spell_id != "":
				GameState.end_concentration("" if player.stats.concentration_spell_id == "expeditious_retreat" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "expeditious_retreat"
			player.stats.expeditious_retreat_turns = 100
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — your reflexes quicken for up to 100 turns.[/color]" % spell.spell_name)
			# Costs a Bonus Action, not the full turn (5e RAW casting time) — same
			# revert_to_waiting() free-action pattern as Shield/Blade Ward. The spell's own
			# movement-free-step EFFECT (once-per-turn free move while the buff is active) is a
			# separate, unrelated mechanic in player.gd's _try_move() and is untouched by this.
			if not GameState.invincible:
				GameState.bonus_action_used = true
			GameState.ability_bar_changed.emit()
			if dungeon_floor != null:
				dungeon_floor.update_fog(player.grid_pos)
			player._reverted_this_round = true
			TurnManager.revert_to_waiting()
			return
		"false_life":
			var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
			var total: int = 4 + spell.upcast_flat_amount * extra_levels
			for v: int in rolls:
				total += v
			player.stats.temp_hp = maxi(player.stats.temp_hp, total)
			GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — a sickly resilience grants [color=lightblue]%d[/color] Temp HP.[/color]" % [spell.spell_name, total])
		"invisibility":
			# A real Concentration spell, same as Blade Ward/Witch Bolt/Fog Cloud/Darkness/etc —
			# mutually exclusive with any other concentration spell, AND breakable by taking damage
			# via the normal GameState._check_concentration_break() CON-check chokepoint (direct
			# owner request — this codebase used to deliberately deviate from 5e RAW here to avoid
			# a damage-based break; that deviation was reversed on request, so it's now identical to
			# every other concentration effect). invisibility_just_cast still skips this same cast's
			# own stealth_check_skip=true (set above) from immediately ending it.
			if player.stats.concentration_spell_id != "":
				GameState.end_concentration("" if player.stats.concentration_spell_id == "invisibility" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "invisibility"
			player.stats.invisibility_turns = 600
			player.stats.invisibility_just_cast = true
			player._update_invisibility_visual()
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — you fade from view for up to 600 turns.[/color]" % spell.spell_name)
			# Upcast (+1 creature you touch, per slot level above 2nd — Warlock Pact Magic only,
			# see Spell.upcast_extra_targets' own comment): this engine's only other valid touch
			# target is the Companion (same "self, or the Companion" scope as Healing Hands, no
			# general ally-targeting system exists) — clicking its own tile also turns it invisible,
			# sharing the caster's own Concentration/duration (see player.gd's turn-tick and
			# GameState.end_concentration()'s "invisibility" branch, both of which clear it too).
			if extra_levels > 0 and spell.upcast_extra_targets > 0 and clicked != Vector2i(-1, -1):
				var comp: Companion = GameState.player_companion
				if comp != null and is_instance_valid(comp) and comp.grid_pos == clicked:
					comp.invisibility_turns = 600
					GameState.game_log("[color=cyan]%s fades from view too.[/color]" % comp.animal_name)
		"detect_magic":
			_resolve_detect_magic(player, spell)
		"longstrider":
			player.stats.longstrider_turns = 600
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — your steps quicken for up to 600 turns.[/color]" % spell.spell_name)
			# Upcast (+1 creature you touch, per slot level above 1st — Warlock Pact Magic only):
			# same "self, or the Companion" touch-target scope as Invisibility above. No movement-
			# speed-scaling system exists for Companion (its own decide/execute turn has no "extra
			# move" concept to grant) — flavor-only, a documented simplification, same tier as
			# Speak with Animals having no mechanical effect.
			if extra_levels > 0 and spell.upcast_extra_targets > 0 and clicked != Vector2i(-1, -1):
				var comp2: Companion = GameState.player_companion
				if comp2 != null and is_instance_valid(comp2) and comp2.grid_pos == clicked:
					GameState.game_log("[color=cyan]%s feels the same swiftness (flavor only — no mechanical speed system exists for companions).[/color]" % comp2.animal_name)
		"cure_wounds":
			_resolve_cure_wounds(player, spell, extra_levels, clicked)
		"aid":
			_resolve_aid(player, spell, extra_levels, clicked)
		"barkskin":
			_resolve_barkskin(player, spell, clicked)
			# Costs a Bonus Action, not the full turn (5e RAW casting time) — same
			# revert_to_waiting() free-action pattern as Shield/Blade Ward.
			if not GameState.invincible:
				GameState.bonus_action_used = true
			GameState.ability_bar_changed.emit()
			if dungeon_floor != null:
				dungeon_floor.update_fog(player.grid_pos)
			player._reverted_this_round = true
			TurnManager.revert_to_waiting()
			return
		"pass_without_trace":
			if player.stats.concentration_spell_id != "":
				GameState.end_concentration("" if player.stats.concentration_spell_id == "pass_without_trace" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "pass_without_trace"
			player.stats.pass_without_trace_turns = 600
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — your steps and voice are muffled for up to 100 turns.[/color]" % spell.spell_name)
		"minor_illusion":
			player.stats.minor_illusion_turns = 10
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — a small distraction covers your movements for 10 turns.[/color]" % spell.spell_name)
		"speak_with_animals":
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — the chittering of nearby creatures briefly makes sense to you.[/color]" % spell.spell_name)
		"mending":
			var main_hand: Item = GameState.equipment.get("melee") as Item
			if main_hand != null and main_hand.uses_max > 0 and main_hand.uses_remaining < main_hand.uses_max:
				main_hand.uses_remaining = main_hand.uses_max
				GameState.game_log("[color=cyan]You cast [b]%s[/b] — your %s is fully repaired.[/color]" % [spell.spell_name, main_hand.item_name])
			else:
				GameState.game_log("[color=gray]You cast [b]%s[/b], but there's nothing to mend right now.[/color]" % spell.spell_name)
		_:
			GameState.game_log("[color=cyan]You cast [b]%s[/b].[/color]" % spell.spell_name)
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# TILE target (Misty Step teleport, Fireball AoE) — no attack roll against the tile itself.
static func cast_leveled_at_tile(player: Player, spell: Spell, cast_level: int, tile_pos: Vector2i, dungeon_floor: Node, from_scroll: bool = false) -> void:
	# Misty Step is a Bonus Action cast in 5e RAW — gated on the Bonus Action economy BEFORE the
	# turn/slot are ever touched, see scripts/entities/CLAUDE.md's "Bonus Action economy" section.
	if spell.effect_id == "misty_step" and GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	_consume_slot(player, spell, cast_level, from_scroll)
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	if extra_levels > 0 and spell.upcast_dice_count > 0:
		spell.dice_count += spell.upcast_dice_count * extra_levels
	if dungeon_floor != null:
		dungeon_floor.try_shoot_tripwire(tile_pos)
	match spell.effect_id:
		"misty_step":
			player.set_grid_pos(tile_pos)
			GameState.player_grid_pos = tile_pos
			GameState.game_log("[color=cyan]You blink in a puff of silver mist.[/color]")
			# Costs a Bonus Action, not the full turn (5e RAW casting time) — same
			# revert_to_waiting() free-action pattern as Shield/Blade Ward.
			if not GameState.invincible:
				GameState.bonus_action_used = true
			GameState.ability_bar_changed.emit()
			if dungeon_floor != null:
				dungeon_floor.update_fog(player.grid_pos)
			player._reverted_this_round = true
			TurnManager.revert_to_waiting()
			return
		"burning_hands":
			_resolve_cone_aoe(player, spell, tile_pos, dungeon_floor)
		"fog_cloud":
			_resolve_fog_cloud(player, spell, tile_pos, extra_levels)
		"faerie_fire":
			_resolve_faerie_fire(player, spell, tile_pos, dungeon_floor)
		"darkness":
			_resolve_darkness(player, spell, tile_pos, dungeon_floor)
		_:
			if spell.shape == "sphere":
				_resolve_sphere_aoe(player, spell, tile_pos, dungeon_floor)
	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Shared cone tile-gather, also reused by DungeonFloor's AoE preview so the preview and the actual
# blast use identical math. Matches 5e PHB's own cone definition ("the cone's width at a given
# point along its length is equal to that point's distance from you") rather than a fixed-angle
# pie slice: for a tile at forward distance `f` along the aim direction (its projection onto
# `dir_v`) and lateral (perpendicular) distance `l` from that centerline, the tile is in the cone
# iff `f` is between 0 and `length` AND `l <= f / 2` (half of the full width-equals-distance rule,
# since `l` is only one side of the centerline) — a true narrowing triangle from a point at the
# origin, not the much wider 90°-pie-slice shape this used to produce. The clicked/hovered
# `aim_tile` only supplies a direction, not an impact point — it need not itself be in range.
# LOS-gated from origin (a wall casts a "shadow" through the cone). Origin tile itself never
# included (forward must be > 0).
const DIR8: Array[Vector2] = [
	Vector2(1, 0), Vector2(0.7071067811865476, 0.7071067811865476),
	Vector2(0, 1), Vector2(-0.7071067811865476, 0.7071067811865476),
	Vector2(-1, 0), Vector2(-0.7071067811865476, -0.7071067811865476),
	Vector2(0, -1), Vector2(0.7071067811865476, -0.7071067811865476),
]  # E, SE, S, SW, W, NW, N, NE (Godot's +Y is down) — exact unit vectors, no cos()/sin() rounding

static func cone_tiles(origin: Vector2i, aim_tile: Vector2i, length: int, dungeon_floor: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var delta: Vector2 = Vector2(aim_tile - origin)
	if delta.length() < 0.001:
		return out
	# Snapped to the nearest of 8 fixed compass directions (same convention as Dragonborn's Breath
	# Weapon Line, PlayerDragonborn._line_tiles()) rather than a continuous freely-rotating angle —
	# direct owner request: the cone's orientation should only change when the mouse crosses into a
	# genuinely different one of the 8 tiles immediately adjacent to the caster, not flicker/reorient
	# continuously as the cursor drifts anywhere at a slightly different angle further away.
	# Bugfix: this used to compute dir_v as Vector2(cos(snapped), sin(snapped)) — East (angle 0) is
	# the only one of the 8 snapped angles cos()/sin() evaluate to EXACTLY (1,0); every other
	# direction (multiples of PI/2 or PI/4) picks up a tiny (~1e-16) floating-point residue in the
	# component that should be exactly 0, which was just barely enough to flip a boundary tile's
	# `lateral <= forward * 0.5` comparison at the cone's far edge — the cone was missing one tile
	# at max range for every direction except aiming due East. DIR8 is an exact lookup table instead.
	var step: float = PI / 4.0
	var idx: int = int(round(delta.angle() / step)) % 8
	if idx < 0:
		idx += 8
	var dir_v: Vector2 = DIR8[idx]
	for dy: int in range(-length, length + 1):
		for dx: int in range(-length, length + 1):
			if dx == 0 and dy == 0:
				continue
			var v: Vector2 = Vector2(dx, dy)
			# `forward` is measured in GRID (Chebyshev) tiles, not continuous Euclidean distance —
			# bugfix: a continuous dot-product `forward` (v.dot(dir_v), dir_v a unit vector) scales
			# a diagonal step by sqrt(2) versus a cardinal step's exact 1, so at a fixed integer
			# `length` (a tile-count range) the diagonal cone's own grid points (e.g. (2,1) relative
			# to a SE aim) measure as `forward > length` well before they're actually `length` tiles
			# out — squeezing the cone down to a single tile at any diagonal aim. Chebyshev distance
			# (`max(|dx|,|dy|)`) treats a diagonal step as costing exactly 1 tile too, matching how
			# this engine's own diagonal movement already works, and makes the cone widen
			# symmetrically in every one of the 8 aim directions instead of only the 4 cardinal ones.
			if v.dot(dir_v) <= 0.0:
				continue
			var forward: float = float(maxi(absi(dx), absi(dy)))
			if forward > float(length):
				continue
			var lateral: float = absf(v.x * dir_v.y - v.y * dir_v.x)
			if lateral > forward * 0.5:
				continue
			var p: Vector2i = origin + Vector2i(dx, dy)
			if dungeon_floor != null and not dungeon_floor.has_ranged_los(origin, p):
				continue
			out.append(p)
	return out

# Cone AoE damage-SAVE resolution (Burning Hands) — a self-centered directional burst from the
# CASTER outward toward the clicked/hovered tile. Unlike Fireball's sphere, this NEVER damages the
# caster (per the spell's own text) and doesn't hit a companion either (matching _resolve_sphere_
# aoe()'s existing scope — enemies + the player only, no companion targeting). Every GRASS tile the
# cone passes through ignites, mirroring Fire Bolt/Thunderclap's flammable-terrain side effect.
static func _resolve_cone_aoe(player: Player, spell: Spell, aim_tile: Vector2i, dungeon_floor: Node) -> void:
	if dungeon_floor == null:
		return
	var stats: Stats = player.stats
	var origin: Vector2i = player.grid_pos
	var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
	var base_inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, spell.damage_type)
	var roll_total: int = int(base_inst["subtotal"])

	var cone: Array[Vector2i] = cone_tiles(origin, aim_tile, spell.shape_size, dungeon_floor)
	GameState.game_log("[color=orange]Flames roar from your hands![/color]")

	var tile_set: Dictionary = {}
	for p: Vector2i in cone:
		tile_set[p] = true
		if dungeon_floor.get_tile_type(p) == DungeonData.TileType.GRASS:
			dungeon_floor.ignite_grass(p)
		else:
			dungeon_floor.ignite_flammable(p)

	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if not tile_set.has(e.grid_pos):
			continue
		e.on_disturbed(player.grid_pos)
		var dc: int = _save_dc(stats, spell)
		var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		var dmg: int = roll_total if not save["pass"] else roll_total / 2
		var result: Dictionary = e.take_typed_damage(dmg, spell.damage_type)
		var actual: int = result["actual"]
		var inst: Dictionary = base_inst.duplicate()
		inst["final"] = actual
		inst["resist_mul"] = result["mul"]
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		e.update_hp_bar()
		dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]%s[/url] by the flames for [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
			e.display_name, save_meta, "caught" if not save["pass"] else "singed", dmg_meta, actual, spell.damage_type, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

# Sphere AoE damage-SAVE resolution (Fireball). Friendly fire is real — hits the player and any
# enemy within shape_size tiles (Euclidean, matching the framework doc §6.1 convention) with LOS
# from the impact tile. Damage-stacking RULE: one take_damage()/show_damage() call per target.
static func _resolve_sphere_aoe(player: Player, spell: Spell, center: Vector2i, dungeon_floor: Node) -> void:
	var stats: Stats = player.stats
	var r: int = spell.shape_size
	var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
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

	GameState.game_log("[color=orange]A sphere of fire erupts![/color]")
	if dungeon_floor != null:
		dungeon_floor.play_impact_vfx(Vector2(center.x * DungeonFloor.TILE_SIZE + 8, center.y * DungeonFloor.TILE_SIZE + 8), "explosion_large", float(2 * r + 1) * DungeonFloor.TILE_SIZE)
		for dy: int in range(-r, r + 1):
			for dx: int in range(-r, r + 1):
				if dx * dx + dy * dy > r * r:
					continue
				var p: Vector2i = center + Vector2i(dx, dy)
				if not dungeon_floor.has_ranged_los(center, p):
					continue
				if dungeon_floor.get_tile_type(p) == DungeonData.TileType.GRASS:
					dungeon_floor.ignite_grass(p)
				else:
					dungeon_floor.ignite_flammable(p)
	for e: Enemy in targets:
		e.on_disturbed(player.grid_pos)
		var dc: int = _save_dc(stats, spell)
		var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
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
		var pdc: int = _save_dc(stats, spell)
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
		GameState.flush_stone_endurance_log()
		GameState.flush_deflect_attacks_log()

## Groups a dart-target descriptor (see PlayerSpellcasting._resolve_multi_target_at()) into a
## unique string key so repeated picks of the same target focus multiple darts onto it instead of
## resolving as separate instances.
static func _mm_target_key(t: Dictionary) -> String:
	if t["kind"] == "enemy":
		return "enemy:%d" % (t["enemy"] as Object).get_instance_id()
	var pos: Vector2i = t["pos"]
	return "%s:%d:%d" % [t["kind"], pos.x, pos.y]

static func _mm_target_pos(t: Dictionary) -> Vector2i:
	if t["kind"] == "enemy":
		return (t["enemy"] as Enemy).grid_pos
	return t["pos"]

# ENEMY/prop MULTI-TARGET, AUTO_HIT resolution (Magic Missile) — no attack roll. `targets` is
# exactly 3 dart-target descriptors, one per dart, gathered click-by-click in
# PlayerSpellcasting._handle_multi_target_click() (any combination of repeats — see that
# function's own header comment). Grouped here by unique target so a repeated pick focuses more
# than one dart's damage onto that target instead of resolving as separate hits. A barrel/door
# target has no HP/AC system yet (scripts/entities/CLAUDE.md's Enemy stat-block schema still only
# covers Enemy) — the dart(s) visibly strike it with no mechanical effect until that lands; a
# forward-compatible slot, not a bug.
static func cast_magic_missile(player: Player, spell: Spell, cast_level: int, targets: Array[Dictionary], dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()

	var order: Array[String] = []
	var groups: Dictionary = {}  # key -> {"desc": Dictionary, "count": int}
	for t: Dictionary in targets:
		var key: String = _mm_target_key(t)
		if not groups.has(key):
			groups[key] = {"desc": t, "count": 0}
			order.append(key)
		groups[key]["count"] += 1

	var first_pos: Vector2i = _mm_target_pos(targets[0])
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = first_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, spell, cast_level, from_scroll)

	for key: String in order:
		var g: Dictionary = groups[key]
		var desc: Dictionary = g["desc"]
		var darts: int = g["count"]
		var dart_rolls: Array[int] = []
		var total: int = 0
		for _i: int in darts:
			var r: int = Rng.range_i(1, 4) + 1
			dart_rolls.append(r)
			total += r
		var rolls_str: String = "|".join(dart_rolls.map(func(x: int) -> String: return str(x)))
		var plural: String = "s" if darts != 1 else ""

		match desc["kind"]:
			"enemy":
				var target: Enemy = desc["enemy"]
				if not is_instance_valid(target) or target.stats.is_dead():
					continue
				target.on_disturbed(player.grid_pos)
				var actual: int = target.take_typed_damage(total, "Force")["actual"]
				target.update_hp_bar()
				if dungeon_floor != null:
					dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color("Force"))
				var dmg_meta: String = "mmdmg:darts=%d,rolls=%s,total=%d,final=%d" % [darts, rolls_str, total, actual]
				var is_lethal: bool = target.stats.is_dead()
				GameState.game_log("%d dart%s of force streak toward %s for [url=%s][color=yellow]%d[/color][/url] Force dmg.%s" % [
					darts, plural, target.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
				if is_lethal:
					player._finish_kill(target)
			"barrel", "door":
				var noun: String = "barrel" if desc["kind"] == "barrel" else "door"
				GameState.game_log("%d dart%s of force streak toward the %s and shatter harmlessly against it." % [darts, plural, noun])

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# ENEMY target, ATTACK_ROLL resolution, LEVELED spells (Chromatic Orb, Witch Bolt) — rolls an
# attack vs the target's AC exactly like a cantrip (cast_spell()), but also consumes a spell slot.
# `is_leap` is Chromatic Orb's single extra bolt (see effect_id dispatch below) — a fresh attack +
# damage roll against a second target, reusing the same log-line shape with the "leaps to" phrasing
# instead of "cast ... at".
static func _resolve_spell_attack_bolt(player: Player, spell: Spell, target: Enemy, dtype: String, dungeon_floor: Node, is_leap: bool) -> Dictionary:
	# Captured BEFORE on_disturbed() wakes the target — both has_advantage() and
	# PlayerVfx.is_target_unaware() read pre-attack behavior/surprise_available state, which
	# on_disturbed() immediately mutates away.
	var target_was_unaware: bool = player._vfx.is_target_unaware(target)
	var was_surprised: bool = player._vfx.has_advantage(target)
	target.on_disturbed(player.grid_pos)
	var stats: Stats = player.stats
	var attack_bonus: int = _attack_bonus(stats, spell)

	var adv_count: int = 0
	if not is_leap:
		adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if was_surprised: adv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	# Disadvantage: ranged spell attack at melee range, EXCEPT against an unaware target — same
	# exemption as cast_spell() above / PlayerRanged.ranged_attack().
	if spell.range_tiles > 1 and target.min_dist_to(player.grid_pos) <= 1 and not target_was_unaware: disadv_count += 1
	if GameState.is_blinded(player.grid_pos): disadv_count += 1
	if stats.has_disadvantage_condition(): disadv_count += 1
	if player._frightened_active(): disadv_count += 1
	# Prone: melee/touch spells (range_tiles <= 1) get ADV against a prone target, ranged spells
	# get DISADV — same split as every other attack-roll site.
	if target.prone:
		if spell.range_tiles <= 1: adv_count += 1
		else: disadv_count += 1

	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var sp_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + attack_bonus + sp_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit()
		player._berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1

	var hit_meta: String = "sphit:die=%d,d1=%d,d2=%d,int=%d,prof=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,stat=%s,exh=%d" % [
		die, die1, die2, _cast_ability_mod(stats, spell), stats.proficiency_bonus, roll, target.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0, 1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, _cast_ability_label(stats, spell), sp_exh]

	if not is_crit and (is_nat_one or roll < target.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		var miss_line: String
		if is_leap:
			miss_line = "[color=cyan]%s[/color] leaps to %s — [url=%s]%s[/url]." % [spell.spell_name, target.display_name, hit_meta, miss_color]
		else:
			miss_line = "You cast [color=cyan]%s[/color] at [color=orange]%s[/color] — [url=%s]%s[/url]." % [spell.spell_name, target.display_name, hit_meta, miss_color]
		GameState.game_log(CombatMath.wrap_halfling_luck(miss_line, r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		return {"hit": false, "lethal": false, "rolls": []}

	if is_crit: AudioManager.play_crit(null)
	else: AudioManager.play("ranged_hit")
	player._vfx.flash_hit(target)
	if adv and not disadv:
		player._vfx.show_surprise_mark(target)
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], is_crit, dtype)
	var result: Dictionary = target.take_typed_damage(inst["subtotal"], dtype, is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(dtype))

	# Hex (Warlock): a hit against the hexed target with ANY attack — including a leveled spell
	# attack roll (Chromatic Orb/Witch Bolt/Ray of Sickness), per the spell's own "weapon, cantrip,
	# or spell attack" text — deals a second, independent Necrotic damage instance. Fires on the
	# leap re-roll too (a leap can land on the hexed target just as easily as the primary bolt).
	var hex_actual: int = 0
	var hex_inst: Dictionary = {}
	var hex_die: int = player._warlock.hex_bonus_die(target)
	if hex_die > 0:
		var hex_rolls: Array[int] = [hex_die]
		hex_inst = CombatMath.build_damage_instance(hex_rolls, 6, [], is_crit, "Necrotic")
		var hex_result: Dictionary = target.take_typed_damage(hex_inst["subtotal"], "Necrotic", is_crit)
		hex_inst["final"] = hex_result["actual"]
		hex_inst["resist_mul"] = hex_result["mul"]
		hex_actual = hex_result["actual"]
		target.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(target.position, hex_actual, false, CombatMath.damage_type_color("Necrotic"), 1)

	# Fire/Frost/Hill Giant Ancestry: same "next attack that hits" trigger melee already has —
	# extended to leveled spell attack rolls too (not on the leap re-roll — only the primary bolt).
	# Skipped if this bolt already killed the target — no point rolling bonus damage/Prone on a corpse.
	var gol_actual: int = 0
	var gol_inst: Dictionary = {}
	var gol_type: String = ""
	if actual > 0 and not is_leap and not target.stats.is_dead():
		gol_type = player._goliath.consume_giant_ancestry_on_hit(target)
		if gol_type == "Fire" or gol_type == "Cold":
			var gol_sides: int = 6 if gol_type == "Cold" else 10
			var gol_rolls: Array[int] = Rng.roll_dice(1, gol_sides)
			gol_inst = CombatMath.build_damage_instance(gol_rolls, gol_sides, [], is_crit, gol_type)
			var gol_result: Dictionary = target.take_typed_damage(gol_inst["subtotal"], gol_type, is_crit)
			gol_inst["final"] = gol_result["actual"]
			gol_inst["resist_mul"] = gol_result["mul"]
			gol_actual = gol_result["actual"]
			target.update_hp_bar()
			var gol_stack_index: int = 1
			if hex_actual > 0: gol_stack_index += 1
			if dungeon_floor != null:
				dungeon_floor.show_damage(target.position, gol_actual, false, CombatMath.damage_type_color(gol_type), gol_stack_index)
			player._goliath.finish_giant_ancestry_bonus_damage()
		elif gol_type == "Prone":
			# Hill's Prone was already applied inside consume_giant_ancestry_on_hit() — its flavor
			# line logs AFTER the primary hit line below, same ordering as Frost's own flavor line.
			player._goliath.finish_giant_ancestry_bonus_damage()

	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % dtype
	var is_lethal: bool = target.stats.is_dead()
	var dmg_segment: String = "[url=%s][color=yellow]%d[/color][/url]%s" % [dmg_meta, actual, type_tag]
	if hex_actual > 0:
		var hex_meta: String = CombatMath.encode_damage_instance(hex_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Necrotic[/color]" % [hex_meta, hex_actual]
	if gol_actual > 0:
		var gol_meta: String = CombatMath.encode_damage_instance(gol_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]%s[/color]" % [gol_meta, gol_actual, gol_type]
	var verb: String = "CRIT! " if is_crit else ""
	var hit_line: String
	if is_leap:
		hit_line = "%sThe orb [url=%s]leaps[/url] to [color=orange]%s[/color] for %s dmg.%s" % [
			verb, hit_meta, target.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)]
	else:
		hit_line = "%sYou [url=%s]cast[/url] [color=cyan]%s[/color] at [color=orange]%s[/color] for %s dmg.%s" % [
			verb, hit_meta, spell.spell_name, target.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)]
	GameState.game_log(CombatMath.wrap_halfling_luck(hit_line, r["lucky"]))
	# Frost/Hill Giant Ancestry flavor lines — always AFTER the primary hit line above.
	if gol_type == "Cold" and not target.stats.is_dead():
		GameState.game_log("[color=cyan]Frost's Chill slows %s.[/color]" % target.display_name)
	elif gol_type == "Prone":
		GameState.game_log("[color=cyan]Hill's Tumble knocks %s Prone.[/color]" % target.display_name)

	if is_lethal:
		player._finish_kill(target)
	return {"hit": true, "lethal": is_lethal, "rolls": rolls}

# Picks a random OTHER alive enemy visible to the player (Chromatic Orb's leap target) — never the
# player, a companion, or any target already hit this cast (`exclude` — "a creature can be
# targeted only once by each casting", real for the upcast's chained-leap case). Returns null if no
# other visible enemy exists.
static func _pick_chromatic_orb_leap_target(dungeon_floor: Node, exclude: Array[Enemy]) -> Enemy:
	if dungeon_floor == null:
		return null
	var candidates: Array[Enemy] = []
	for e: Enemy in dungeon_floor.get_visible_enemies():
		if e in exclude or not is_instance_valid(e) or e.stats.is_dead():
			continue
		candidates.append(e)
	if candidates.is_empty():
		return null
	return Rng.pick(candidates)

# ENEMY target, ATTACK_ROLL resolution, LEVELED spells (Chromatic Orb, Witch Bolt).
static func cast_leveled_attack_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, spell, cast_level, from_scroll)
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	if extra_levels > 0 and spell.upcast_dice_count > 0:
		spell.dice_count += spell.upcast_dice_count * extra_levels

	match spell.effect_id:
		"chromatic_orb":
			# Damage type is rolled once per cast, before the attack roll — a leap (if triggered)
			# reuses the same type rather than re-rolling, like the orb's energy carrying over.
			# Upcast: "the orb can leap a maximum number of times equal to the level of the slot
			# expended, and a creature can be targeted only once by each casting" — so a leap can
			# now chain repeatedly (up to cast_level total leaps) instead of firing at most once,
			# each leap excluding every target already hit this cast.
			var dtype: String = Rng.pick(CHROMATIC_ORB_TYPES)
			var used_targets: Array[Enemy] = [target]
			var cur_res: Dictionary = _resolve_spell_attack_bolt(player, spell, target, dtype, dungeon_floor, false)
			var leaps_done: int = 0
			var max_leaps: int = cast_level
			while cur_res["hit"] and not cur_res["lethal"] and leaps_done < max_leaps:
				var rolls: Array = cur_res["rolls"]
				var seen: Dictionary = {}
				var has_pair: bool = false
				for v: int in rolls:
					seen[v] = seen.get(v, 0) + 1
					if seen[v] >= 2:
						has_pair = true
				if not has_pair:
					break
				var leap_target: Enemy = _pick_chromatic_orb_leap_target(dungeon_floor, used_targets)
				if leap_target == null:
					break
				GameState.game_log("[color=cyan]The orb crackles and leaps toward a new target![/color]")
				cur_res = _resolve_spell_attack_bolt(player, spell, leap_target, dtype, dungeon_floor, true)
				used_targets.append(leap_target)
				leaps_done += 1
		"witch_bolt":
			var res2: Dictionary = _resolve_spell_attack_bolt(player, spell, target, spell.damage_type, dungeon_floor, false)
			if res2["hit"] and not res2["lethal"]:
				var stats: Stats = player.stats
				if stats.concentration_spell_id != "":
					GameState.end_concentration("" if stats.concentration_spell_id == "witch_bolt" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
				stats.concentration_spell_id = "witch_bolt"
				stats.witch_bolt_target = target
				stats.witch_bolt_turns = 10
				stats.witch_bolt_just_cast = true
				GameState.game_log("[color=cyan]%s is Jolted — crackling energy will keep striking it.[/color]" % target.display_name)
		"ray_of_sickness":
			# Abyssal Tiefling lineage spell (level 3 grant): attack roll + damage exactly like
			# Chromatic Orb. On a landed non-lethal hit the target is automatically Poisoned —
			# no save — approximated as a fixed 2-turn duration (RAW: "until the end of your next
			# turn", same fixed-duration precedent as Mind Sliver's own documented gap).
			var res3: Dictionary = _resolve_spell_attack_bolt(player, spell, target, spell.damage_type, dungeon_floor, false)
			if res3["hit"] and not res3["lethal"]:
				target.apply_status("poisoned_condition", 2)
				GameState.game_log("[color=cyan]%s retches and doubles over — Poisoned![/color]" % target.display_name)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Single-target SAVE-resolution LEVELED spells (Hold Person, Hideous Laughter — the leveled
# counterpart to cast_cantrip_save_at_enemy() above, with real spell-slot consumption). A spell
# with dice_count <= 0 is a pure debuff/condition with no damage roll at all (Hold Person); any
# other spell deals damage, halved on a successful save (spell.save_for_half).
# `also_targets`: additional enemies the Warlock Pact Magic upcast collected (Spell.
# upcast_extra_targets, see PlayerSpellcasting._begin_multi_target()'s generalized SAVE-multi-target
# flow) — each rolls its own independent save under this ONE cast's shared turn/slot/Concentration.
# Empty for a normal, non-upcast single-target cast (every existing call site), so this parameter
# changes nothing about the base spell's behavior.
static func cast_leveled_save_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node, from_scroll: bool = false, also_targets: Array[Enemy] = []) -> void:
	# Hold Person only works on Humanoids (5e RAW) — a targeting restriction, not a resisted
	# effect, so it's checked before any turn/slot/animation is spent: a Fiend (the Bearded Devil, etc.)
	# was never a legal target at all, unlike a condition-immune creature (still legally targeted,
	# just doesn't get the status — see Enemy.apply_status()'s condition_immunities gate).
	if spell.effect_id == "hold_person" and target.creature_type != "Humanoid":
		GameState.game_log("[color=gray]%s is unaffected — Hold Person only works on Humanoids.[/color]" % target.display_name)
		return
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	target.on_disturbed(player.grid_pos)
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, spell, cast_level, from_scroll)

	var stats: Stats = player.stats

	if spell.dice_count <= 0:
		# Every enemy this cast actually affects — the primary target plus any upcast-collected
		# extras (a non-Humanoid extra against Hold Person is skipped, same targeting-restriction
		# rule as the primary's own gate above). Each rolls an independent save; the Concentration
		# switch-check (breaking a DIFFERENT already-active spell) only fires ONCE for the whole
		# cast, and only if at least one target's save actually fails — a whiffed cast never touches
		# an existing unrelated concentration effect, matching the original single-target behavior.
		var all_targets: Array[Enemy] = [target]
		for e: Enemy in also_targets:
			if not is_instance_valid(e) or e.stats.is_dead() or e == target:
				continue
			if spell.effect_id == "hold_person" and e.creature_type != "Humanoid":
				GameState.game_log("[color=gray]%s is unaffected — Hold Person only works on Humanoids.[/color]" % e.display_name)
				continue
			e.on_disturbed(player.grid_pos)
			all_targets.append(e)

		var failed: Array[Dictionary] = []  # {"enemy": Enemy, "dc": int}
		for e: Enemy in all_targets:
			var dc: int = _save_dc(stats, spell)
			var save: Dictionary = e.resist_check_detailed(dc,
				spell.save_stat == "CON", spell.save_stat == "DEX", spell.save_stat == "WIS", spell.save_stat == "INT", true)
			var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
				save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
			if save["pass"] and spell.effect_id == "ray_of_enfeeblement":
				# A successful CON save still leaves a minor one-shot debuff: Disadvantage on the
				# target's own next attack roll (reuses Grip of the Forest R3's field/consumption
				# point) — the spell otherwise ends here, no Concentration started.
				e.disadv_next_attack = true
				GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s resists[/url], but reels for a moment.[/color]" % [
					spell.spell_name, e.display_name, save_meta, e.display_name])
			elif save["pass"]:
				GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s resists[/url].[/color]" % [
					spell.spell_name, e.display_name, save_meta, e.display_name])
			else:
				GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s fails the save[/url]!" % [
					spell.spell_name, e.display_name, save_meta, e.display_name])
				failed.append({"enemy": e, "dc": dc})

		if not failed.is_empty():
			if stats.concentration_spell_id != "":
				GameState.end_concentration("" if stats.concentration_spell_id == spell.effect_id else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			match spell.effect_id:
				"hold_person":
					stats.concentration_spell_id = "hold_person"
					stats.hold_person_turns = 10
					for f: Dictionary in failed:
						var e2: Enemy = f["enemy"]
						e2.paralyzed_turns = 10
						e2.paralyze_save_dc = f["dc"]
						e2._refresh_paralyzed_visual()
						stats.hold_person_target.append(e2)
						GameState.game_log("[color=cyan]%s is paralyzed, unable to act![/color]" % e2.display_name)
				"ray_of_enfeeblement":
					# No upcast target (Spell.upcast_extra_targets == 0) — always exactly 1 entry.
					var f0: Dictionary = failed[0]
					var e3: Enemy = f0["enemy"]
					e3.enfeeble_turns = 10
					e3.enfeeble_save_dc = f0["dc"]
					stats.concentration_spell_id = "ray_of_enfeeblement"
					stats.ray_of_enfeeblement_target = e3
					stats.ray_of_enfeeblement_turns = 10
					GameState.game_log("[color=cyan]%s's muscles wither with enfeeblement![/color]" % e3.display_name)
				"hideous_laughter":
					stats.concentration_spell_id = "hideous_laughter"
					stats.hideous_laughter_turns = 10
					for f: Dictionary in failed:
						var e4: Enemy = f["enemy"]
						e4.apply_status("prone", 1)
						e4.incapacitated_turns = 10
						e4.hideous_laughter_save_dc = f["dc"]
						stats.hideous_laughter_target.append(e4)
						GameState.game_log("[color=cyan]%s collapses in a fit of uncontrollable laughter![/color]" % e4.display_name)
		if dungeon_floor != null:
			dungeon_floor.update_fog(player.grid_pos)
		player._handle_post_attack_turn()
		return

	# Damage-dealing SAVE spells (dice_count > 0) are single-target only — no current spell reaches
	# this branch with also_targets non-empty (only Hold Person/Hideous Laughter, both pure debuffs
	# with dice_count <= 0, ever collect extra targets today).
	var dc: int = _save_dc(stats, spell)
	var save: Dictionary = target.resist_check_detailed(dc,
		spell.save_stat == "CON", spell.save_stat == "DEX", spell.save_stat == "WIS", spell.save_stat == "INT", true)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
	var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, spell.damage_type)
	var roll_total: int = int(inst["subtotal"])
	var dmg: int = roll_total if not save["pass"] else roll_total / 2
	var result: Dictionary = target.take_typed_damage(dmg, spell.damage_type)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var is_lethal: bool = target.stats.is_dead()
	GameState.game_log("You cast [color=cyan]%s[/color] at %s — [url=%s]%s[/url] and takes [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
		spell.spell_name, target.display_name, save_meta, "resists" if save["pass"] else "fails", dmg_meta, actual, spell.damage_type, CombatMath.death_suffix(is_lethal)])
	if is_lethal:
		player._finish_kill(target)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

const HEX_ABILITIES: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]

# AUTO_HIT ENEMY target (Hex — the only spell using this shape today; Magic Missile is AUTO_HIT too
# but is intercepted earlier via the multi-target flow, never reaches this function). No attack
# roll, no save — placing the curse always succeeds against any visible in-range target. Free
# casting time (RAW: bonus action) — ends via the same revert_to_waiting() free-action pattern as
# Shield, instead of player._handle_post_attack_turn().
static func cast_leveled_auto_hit_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	# Hex is a Bonus Action cast in 5e RAW — gated on the Bonus Action economy BEFORE the turn/slot
	# are ever touched (this covers a manual re-cast too — Enemy.die()'s free-recast-on-kill arming
	# only ever gets spent through this same function, never fires on its own). See
	# scripts/entities/CLAUDE.md's "Bonus Action economy" section.
	if spell.effect_id == "hex" and GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	target.on_disturbed(player.grid_pos)
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	match spell.effect_id:
		"hex":
			_resolve_hex(player, spell, cast_level, target, from_scroll)
		_:
			_consume_slot(player, spell, cast_level, from_scroll)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._reverted_this_round = true
	TurnManager.revert_to_waiting()

# Hex (Warlock, level 1) — places a curse: every landed attack (weapon, cantrip, or spell — see
# PlayerWarlock.hex_bonus_die(), wired into every ATTACK_ROLL damage site) against the target deals
# an extra 1d6 Necrotic, and the target has Disadvantage on any check using one randomly-chosen
# ability score (Enemy.resist_check_detailed()'s own hex_disadv term). Real Concentration, up to
# 600 turns (+600 more per upcast slot level above 1st — a DURATION bump, unlike every other
# upcast spell's dice/target-count shape, see Spell.upcast_flat_amount's own comment). If the
# hexed target dies while this Concentration is still active, Enemy.die() arms
# Stats.hex_free_recast_pending — consumed here, before the generic slot-consumption chokepoint, so
# the very next Hex cast (any target) costs no slot at all.
static func _resolve_hex(player: Player, spell: Spell, cast_level: int, target: Enemy, from_scroll: bool) -> void:
	var stats: Stats = player.stats
	if not GameState.invincible:
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	if stats.hex_free_recast_pending and not from_scroll:
		stats.hex_free_recast_pending = false
		GameState.game_log("[color=cyan]Hex: your fallen quarry lets you recast for free.[/color]")
	else:
		_consume_slot(player, spell, cast_level, from_scroll)
	if stats.concentration_spell_id != "":
		GameState.end_concentration("" if stats.concentration_spell_id == "hex" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "hex"
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	stats.hex_turns = spell.duration_turns + spell.upcast_flat_amount * extra_levels
	stats.hex_target = target
	stats.hex_ability = Rng.pick(HEX_ABILITIES)
	GameState.game_log("[color=cyan]You curse %s with Hex — it falters whenever its %s is tested.[/color]" % [target.display_name, stats.hex_ability.to_upper()])

# Hellish Rebuke as a REACTION (a real learnable Warlock spell, and still the Infernal Tiefling's
# free legacy grant — scripts/entities/CLAUDE.md's "Tiefling"/"Warlock class" sections): armed via
# the ability bar toggle (PlayerTiefling.activate_hellish_rebuke(), mirrors Storm Giant Ancestry's
# own arm/consume-on-proc shape) rather than cast on demand. Called from enemy.gd._attack_player()
# right after a landed hit — no TurnManager envelope (fires mid-enemy-turn, not a player action)
# and no attack roll of its own; the attacker just makes a DEX save. Consumes the free-cast-per-
# long-rest economy every other Fiendish Legacy spell uses first (Tiefling only — a non-Tiefling
# Warlock never has this counter), falling back to a real spell slot once that's spent/absent — if
# neither is available the reaction simply can't fire yet (stays armed for the next opportunity).
static func trigger_hellish_rebuke(player: Player, attacker: Enemy, dungeon_floor: Node) -> void:
	var spell: Spell = SpellDb.get_spell("hellish_rebuke")
	var stats: Stats = player.stats
	# The actual slot level this reaction fires at — spell.level (1) for the free-cast/God-Mode
	# paths, or whatever the caster's own slot_pool would actually cast it at otherwise (for a
	# Warlock's PactSlotPool, this can be ABOVE 1 — auto-upcast — so it must be read via
	# available_level(), never hardcoded to spell.level, or the wrong slot key gets consumed).
	var cast_level: int = spell.level
	if stats.is_tiefling_legacy_free_cast_available("hellish_rebuke"):
		if not GameState.invincible:
			stats.tiefling_legacy_free_casts_remaining["hellish_rebuke"] = stats.tiefling_legacy_free_casts_remaining.get("hellish_rebuke", 0) - 1
	elif stats.caster != null and stats.caster.slot_pool != null and (GameState.invincible or stats.caster.slot_pool.can_cast(spell)):
		if not GameState.invincible:
			cast_level = stats.caster.slot_pool.available_level(spell)
			stats.caster.slot_pool.consume(cast_level)
	else:
		GameState.game_log("[color=gray]Hellish Rebuke has no charge left to fuel it.[/color]")
		return
	GameState.spell_slots_changed.emit()
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	if extra_levels > 0 and spell.upcast_dice_count > 0:
		spell.dice_count += spell.upcast_dice_count * extra_levels

	var dc: int = _save_dc(stats, spell)
	var save: Dictionary = attacker.resist_check_detailed(dc, false, true, false, false, true)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]

	var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, spell.damage_type)
	var roll_total: int = int(inst["subtotal"])
	var dmg: int = roll_total if not save["pass"] else roll_total / 2
	var result: Dictionary = attacker.take_typed_damage(dmg, spell.damage_type)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	attacker.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(attacker.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var is_lethal: bool = attacker.stats.is_dead()
	GameState.game_log("[color=cyan]Hellish Rebuke[/color] flares as %s hurts you — [url=%s]%s[/url] and takes [url=%s][color=yellow]%d[/color][/url] Fire dmg.%s" % [
		attacker.display_name, save_meta, "resists" if save["pass"] else "fails the save", dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
	if is_lethal:
		player._finish_kill(attacker)

# Hail of Thorns (Ranger's own real 5e spell list entry) — the offensive mirror of Hellish Rebuke's
# toggle-armed-reaction shape (see PlayerRangerTalents' own header comment): armed via the ability
# bar, consumed by the CALLER (PlayerRanged.ranged_attack(), which clears Stats.hail_of_thorns_armed
# BEFORE calling this, same convention as enemy.gd's own Hellish Rebuke call site) the instant a
# ranged shot lands. `primary` is the shot's own target — included in the burst only if it's still
# alive (a shot that already killed it outright leaves nothing there for the thorns to catch), plus
# every OTHER living enemy within Chebyshev 1 of `primary`'s tile (5e RAW's "5 feet"). Each rolls an
# independent DEX save; a fail takes the full roll, a pass takes half (rounded down).
static func trigger_hail_of_thorns(player: Player, primary: Enemy, dungeon_floor: Node) -> void:
	var spell: Spell = SpellDb.get_spell("hail_of_thorns")
	var stats: Stats = player.stats
	var cast_level: int = spell.level
	if stats.caster != null and stats.caster.slot_pool != null and (GameState.invincible or stats.caster.slot_pool.can_cast(spell)):
		if not GameState.invincible:
			cast_level = stats.caster.slot_pool.available_level(spell)
			stats.caster.slot_pool.consume(cast_level)
	else:
		GameState.game_log("[color=gray]Hail of Thorns has no spell slot left to fuel it.[/color]")
		return
	GameState.spell_slots_changed.emit()
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	var dice_count: int = spell.dice_count + spell.upcast_dice_count * extra_levels
	var dc: int = _save_dc(stats, spell)

	var targets: Array[Enemy] = []
	if is_instance_valid(primary) and not primary.stats.is_dead():
		targets.append(primary)
	if dungeon_floor != null:
		for e: Enemy in dungeon_floor.get_all_enemies():
			if e == primary or not is_instance_valid(e) or e.stats.is_dead():
				continue
			if primary.min_dist_to_entity(e) <= 1:
				targets.append(e)
	if targets.is_empty():
		return

	GameState.game_log("[color=lime]Hail of Thorns[/color] rains down around %s!" % primary.display_name)
	for e: Enemy in targets:
		var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
		var inst: Dictionary = CombatMath.build_damage_instance(rolls, spell.dice_sides, [], false, spell.damage_type)
		var roll_total: int = int(inst["subtotal"])
		var dmg: int = roll_total if not save["pass"] else roll_total / 2
		var result: Dictionary = e.take_typed_damage(dmg, spell.damage_type)
		inst["final"] = result["actual"]
		inst["resist_mul"] = result["mul"]
		var actual: int = result["actual"]
		e.update_hp_bar()
		if dungeon_floor != null:
			dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color(spell.damage_type))
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]%s[/url] by the thorns for [url=%s][color=yellow]%d[/color][/url] Piercing dmg.%s" % [
			e.display_name, save_meta, "torn" if not save["pass"] else "grazed", dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

# Ensnaring Strike (Ranger's own real 5e spell list entry) — same toggle-armed-reaction shape as
# Hail of Thorns (see PlayerRangerTalents' own header comment), triggered from the CALLER (player.gd
# _bump_attack()/PlayerRanged.ranged_attack() — any weapon hit, not just ranged), which clears
# Stats.ensnaring_strike_armed BEFORE calling this. Unlike Hail of Thorns/Hellish Rebuke's one-shot
# burst, a failed save here starts a genuine ongoing Concentration effect (Enemy.restrained_turns'
# own repeated-save/DoT-tick mechanism, ticked from that enemy's own decide_turn()) rather than
# resolving everything in one call.
static func trigger_ensnaring_strike(player: Player, target: Enemy, dungeon_floor: Node) -> void:
	var spell: Spell = SpellDb.get_spell("ensnaring_strike")
	var stats: Stats = player.stats
	var cast_level: int = spell.level
	if stats.caster != null and stats.caster.slot_pool != null and (GameState.invincible or stats.caster.slot_pool.can_cast(spell)):
		if not GameState.invincible:
			cast_level = stats.caster.slot_pool.available_level(spell)
			stats.caster.slot_pool.consume(cast_level)
	else:
		GameState.game_log("[color=gray]Ensnaring Strike has no spell slot left to fuel it.[/color]")
		return
	GameState.spell_slots_changed.emit()
	var extra_levels: int = _upcast_extra_levels(spell, cast_level)
	var dice_count: int = spell.dice_count + spell.upcast_dice_count * extra_levels
	var dc: int = _save_dc(stats, spell)
	# Large-or-bigger creatures roll this initial save with Advantage (a house-rule addition on top
	# of real 5e's own Ensnaring Strike text, per the owner's own stat block) — same "footprint > 1
	# tile OR creature_size Large+" check Halfling Nimbleness uses for "is this a big creature".
	var is_big: bool = target.creature_size in ["Large", "Huge", "Gargantuan"] or target.size.x * target.size.y > 1
	var save: Dictionary = target.resist_check_detailed(dc, false, false, false, false, true, false, is_big)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
	if save["pass"]:
		GameState.game_log("[color=lime]Ensnaring Strike[/color] lashes out at %s — [url=%s]it resists[/url] the entangling thorns." % [target.display_name, save_meta])
		return
	if stats.concentration_spell_id != "" and stats.concentration_spell_id != "ensnaring_strike":
		GameState.end_concentration("[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "ensnaring_strike"
	stats.ensnaring_strike_turns = spell.duration_turns
	stats.ensnaring_strike_target = target
	stats.ensnaring_strike_dice_count = dice_count
	target.restrained_turns = spell.duration_turns
	target.restrain_save_dc = dc
	GameState.game_log("[color=lime]Ensnaring Strike[/color] lashes out at %s — [url=%s]it fails[/url] the save and is bound by thorns!" % [target.display_name, save_meta])

# Witch Bolt's per-turn damage tick (called from player.gd's _on_turn_started(), NOT a player
# action — no TurnManager envelope, no slot consumption, no fresh attack roll; only the initial
# cast above rolls to hit). Automatic 1d12 Lightning to the Jolted target.
static func tick_witch_bolt(player: Player, target: Enemy, dungeon_floor: Node) -> void:
	var rolls: Array[int] = Rng.roll_dice(1, 12)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, 12, [], false, "Lightning")
	var result: Dictionary = target.take_typed_damage(inst["subtotal"], "Lightning")
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color("Lightning"))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var is_lethal: bool = target.stats.is_dead()
	GameState.game_log("[color=cyan]Witch Bolt[/color] jolts %s for [url=%s][color=yellow]%d[/color][/url] Lightning dmg.%s" % [
		target.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)])
	if is_lethal:
		player._finish_kill(target)

# Fog Cloud — places a persistent circular Blinded zone (GameState.fog_cloud_pos/radius) rather
# than dealing damage. Duration uses the generic concentration_spell_id mechanism ("fog_cloud"),
# same recast/break-another-concentration-spell rule as Blade Ward/Witch Bolt/Expeditious Retreat.
# The actual ADV/DISADV consequences of standing in the cloud are read live, at point of attack, by
# player_vfx.gd's has_advantage(), the disadv_count block at every player attack-roll site, and
# enemy.gd._resolve_attack_roll()'s extra_adv/extra_disadv params — nothing here applies a status
# effect directly. See scripts/entities/CLAUDE.md's "Fog Cloud" section.

# Cure Wounds (Ranger's own real 5e spell list entry) — touch a creature and heal it 2d8 + your
# spellcasting ability modifier, +2d8 per slot level above 1st (Warlock Pact Magic auto-upcast
# only — Ranger's own HalfCasterSlotPool never upcasts, see "Spell upcasting"). Same "self, or the
# Companion" touch-target scope as Healing Hands/Longstrider (no general ally-targeting system
# exists) — clicking the Companion's own tile heals it instead of the caster.
static func _resolve_cure_wounds(player: Player, spell: Spell, extra_levels: int, clicked: Vector2i) -> void:
	var stats: Stats = player.stats
	var dice_count: int = spell.dice_count + spell.upcast_dice_count * extra_levels
	var rolls: Array[int] = Rng.roll_dice(dice_count, spell.dice_sides)
	var mod: int = _cast_ability_mod(stats, spell)
	var roll_total: int = 0
	for r: int in rolls:
		roll_total += r
	var amount: int = maxi(1, roll_total + mod)
	var companion: Companion = GameState.player_companion
	var heal_companion: bool = companion != null and is_instance_valid(companion) and companion.grid_pos == clicked
	if heal_companion:
		companion.stats.current_hp = mini(companion.stats.max_hp, companion.stats.current_hp + amount)
		var hm: String = "heal:dice=%d,sides=%d,con=%d,roll=%d,bonus=%s,total=%d" % [dice_count, spell.dice_sides, mod, roll_total, CombatMath.encode_bonus_sources([]), amount]
		GameState.game_log("[color=cyan]You cast [b]%s[/b] on %s — [url=%s]%d[/url] HP restored.[/color]" % [spell.spell_name, companion.animal_name, hm, amount])
	else:
		var bruiser_bonus: int = GameState.heal(amount)
		var total: int = amount + bruiser_bonus
		var bonus_sources: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus, "color": "orange"}])
		var hm2: String = "heal:dice=%d,sides=%d,con=%d,roll=%d,bonus=%s,total=%d" % [dice_count, spell.dice_sides, mod, roll_total, bonus_sources, total]
		GameState.game_log("[color=cyan]You cast [b]%s[/b] — [url=%s]%d[/url] HP restored.[/color]" % [spell.spell_name, hm2, total])

# Aid (2nd level Abjuration): flat max-HP AND current-HP increase, lasting until the caster's next
# long rest (Stats.aid_bonus_hp — not a turn-ticked duration, cleared by GameState.long_rest()).
# RAW targets up to 3 creatures; this engine only has one other valid touch target (the Companion,
# same "self, or the Companion" scope as Cure Wounds above) — unlike Cure Wounds' either/or click,
# Aid always affects the caster AND additionally affects the Companion if the click landed on it,
# since RAW genuinely buffs multiple creatures with one cast.
static func _resolve_aid(player: Player, spell: Spell, extra_levels: int, clicked: Vector2i) -> void:
	var amount: int = 5 + spell.upcast_flat_amount * extra_levels
	player.stats.max_hp += amount
	player.stats.current_hp += amount
	player.stats.aid_bonus_hp += amount
	GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
	GameState.game_log("[color=cyan]You cast [b]%s[/b] — your max HP swells by [color=lightgreen]%d[/color] until your next long rest.[/color]" % [spell.spell_name, amount])
	var companion: Companion = GameState.player_companion
	if companion != null and is_instance_valid(companion) and companion.grid_pos == clicked:
		companion.stats.max_hp += amount
		companion.stats.current_hp += amount
		companion.stats.aid_bonus_hp += amount
		GameState.game_log("[color=cyan]%s's max HP swells by [color=lightgreen]%d[/color] too.[/color]" % [companion.animal_name, amount])

# Barkskin (2nd level Transmutation): NOT Concentration (see Stats.barkskin_turns' own comment) —
# a flat 600-turn buff floors the touched creature's AC at 17 (Stats.recalc_ac() applies the floor
# for the player; the Companion has no live AC-recompute system, so its AC is floored directly here
# and restored from `barkskin_pre_ac` when the duration runs out, see player.gd's turn-tick).
# Same "self, or the Companion" touch scope as Cure Wounds/Aid — but only ONE target is ever
# affected per cast, unlike Aid's simultaneous self+Companion.
static func _resolve_barkskin(player: Player, spell: Spell, clicked: Vector2i) -> void:
	var companion: Companion = GameState.player_companion
	var on_companion: bool = companion != null and is_instance_valid(companion) and companion.grid_pos == clicked
	player.stats.barkskin_turns = 600
	player.stats.barkskin_on_companion = on_companion
	if on_companion:
		companion.stats.barkskin_pre_ac = companion.stats.armor_class
		companion.stats.armor_class = maxi(companion.stats.armor_class, 17)
		GameState.game_log("[color=cyan]You cast [b]%s[/b] on %s — their skin turns rough as tree bark, AC can be no lower than 17.[/color]" % [spell.spell_name, companion.animal_name])
	else:
		GameState.recalculate_stats()
		GameState.game_log("[color=cyan]You cast [b]%s[/b] — your skin turns rough as tree bark, your AC can be no lower than 17.[/color]" % spell.spell_name)

static func _resolve_fog_cloud(player: Player, spell: Spell, center: Vector2i, extra_levels: int = 0) -> void:
	var stats: Stats = player.stats
	if stats.concentration_spell_id != "":
		GameState.end_concentration("" if stats.concentration_spell_id == "fog_cloud" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "fog_cloud"
	stats.fog_cloud_turns = 600
	GameState.fog_cloud_pos = center
	GameState.fog_cloud_radius = spell.shape_size + spell.upcast_flat_amount * extra_levels
	GameState.game_log("[color=cyan]A thick fog billows outward, obscuring the area![/color]")

# Darkness (real LEVELED_SPELL_IDS entry, also the Drow lineage spell) — a second, independent
# Heavily Obscured zone, otherwise identical mechanism to Fog Cloud above (see
# GameState.darkness_pos/darkness_radius and is_heavily_obscured()'s "checks both zones" comment).
# Can be cast at a bare point OR at a tile holding an unattended floor object — 5e RAW: cast on an
# object and the darkness follows it if moved, INCLUDING ending if it's picked up. GameState.
# darkness_item (mirrors light_source_item's own tracking) records that specific Item reference
# when one is present at cast time; DungeonFloor.update_fog() clears the zone the instant it's no
# longer at darkness_pos (picked up, or otherwise removed) — see scripts/world/CLAUDE.md's "Fog
# Cloud spell zone" section. A bare-point cast (or one on a worn/equipped/carried item, which never
# shows up in dungeon_floor.get_item_at()) leaves darkness_item null and the zone just stays a
# fixed position+radius like before.
static func _resolve_darkness(player: Player, spell: Spell, center: Vector2i, dungeon_floor: Node = null) -> void:
	var stats: Stats = player.stats
	if stats.concentration_spell_id != "":
		GameState.end_concentration("" if stats.concentration_spell_id == "darkness" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "darkness"
	stats.darkness_turns = 100
	GameState.darkness_pos = center
	GameState.darkness_radius = spell.shape_size
	GameState.darkness_item = dungeon_floor.get_item_at(center) if dungeon_floor != null else null
	GameState.game_log("[color=cyan]Magical darkness pools outward, swallowing the light![/color]")
	_darkness_dispel_overlapping_light(spell.shape_size, center)

# If this Darkness zone's area overlaps a currently-active Light cantrip's glow (a level-0 spell —
# "level 2 or lower" per the spell's own text), the light is snuffed out. Two overlapping circles
# (Darkness's own radius + the Light source's GameState.LIGHT_SOURCE_RADIUS) touch iff the distance
# between their centers is <= the sum of their radii. Only the Light cantrip counts here — a lit
# Torch's glow isn't a spell at all, so it's untouched by this check.
static func _darkness_dispel_overlapping_light(darkness_radius: int, center: Vector2i) -> void:
	if GameState.light_source_pos == Vector2i(-1, -1):
		return
	var d: Vector2i = GameState.light_source_pos - center
	var reach: int = darkness_radius + GameState.LIGHT_SOURCE_RADIUS
	if d.x * d.x + d.y * d.y <= reach * reach:
		GameState.clear_light_source()
		GameState.game_log("[color=cyan]The darkness swallows the nearby light![/color]")

# Faerie Fire (Drow lineage spell) — every enemy within spell.shape_size tiles (Euclidean, LOS'd
# from the impact tile — same target-gathering shape as _resolve_sphere_aoe()) makes a DEX save;
# on a fail, Enemy.faerie_fire_turns is set (10 turns — grants Advantage to every attack against
# it PROVIDED the attacker can see it, see PlayerVfx.has_advantage(); also emanates a small light
# bubble and forces an invisible failed-save creature visible-but-translucent instead of hidden —
# see Enemy.is_outlined_while_invisible()/DungeonFloor._update_enemy_visibility()). No damage, no
# friendly fire (the player is never a target). Objects in the cube are cosmetic-only per the real
# spell text ("if the object is worn or carried..."); this engine has no generic prop-tinting
# system to hang a persistent object outline on, so only the creature-side effects are implemented
# — a documented scope cut, not an oversight. One random color (blue/green/violet) is rolled ONCE
# per cast and shared by every creature outlined this cast (Enemy.faerie_fire_color), matching "all
# the same color" — a real 5e spell, Concentration up to 10 turns (the caster's own duration is
# tracked separately, Stats.faerie_fire_turns, ticked in player.gd's per-turn block).
const FAERIE_FIRE_COLORS: Array[Color] = [
	Color(0.35, 0.6, 1.0),   # blue
	Color(0.4, 0.9, 0.45),   # green
	Color(0.65, 0.35, 0.95), # violet
]
static func _resolve_faerie_fire(player: Player, spell: Spell, center: Vector2i, dungeon_floor: Node) -> void:
	if dungeon_floor == null:
		return
	var stats: Stats = player.stats
	# Unconditional (not just "if switching to a different spell") — recasting Faerie Fire itself
	# must also fully clear the PREVIOUS cast's outlined enemies first (end_concentration()'s own
	# "faerie_fire" branch does that un-outlining), or a fresh cast elsewhere left the old cast's
	# targets permanently debuffed/advantaged since nothing else ever cleared them (bugfix).
	if stats.concentration_spell_id != "":
		GameState.end_concentration("" if stats.concentration_spell_id == "faerie_fire" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "faerie_fire"
	stats.faerie_fire_turns = 10
	var r: int = spell.shape_size
	var color: Color = Rng.pick(FAERIE_FIRE_COLORS)
	GameState.game_log("[color=cyan]Dancing lights swirl outward, seeking to outline your foes![/color]")
	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		var d: Vector2i = e.grid_pos - center
		# Faerie Fire's cube is a literal `r`-tiles-wide (2x2 for shape_size=2) corner-anchored
		# block, not a centered radius — `shape_size` is a side length here, matching the real
		# spell's small 2-tile-cube footprint (a "radius 2" Chebyshev square would have been 5x5,
		# far too large). Bugfix: an earlier pass treated it as a Chebyshev radius by mistake.
		if d.x < 0 or d.x >= r or d.y < 0 or d.y >= r:
			continue
		if not dungeon_floor.has_ranged_los(center, e.grid_pos):
			continue
		e.on_disturbed(player.grid_pos)
		var dc: int = _save_dc(stats, spell)
		var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		if save["pass"]:
			GameState.game_log("%s [url=%s]resists[/url] the light." % [e.display_name, save_meta])
		else:
			e.faerie_fire_turns = 10
			e.faerie_fire_color = color
			e._refresh_faerie_fire_visual()
			GameState.game_log("%s is [url=%s]outlined[/url] in dancing light!" % [e.display_name, save_meta])
	# Faerie Fire outlines ANY creature caught in the cube, not just enemies — including the caster
	# themselves, if their own 2x2 footprint happens to include their own tile (e.g. casting it on
	# their own square). Mirrors the enemy loop above exactly (same footprint check, own DEX save)
	# but writes to Stats.faerie_fire_outlined_turns (a field distinct from the caster's own
	# faerie_fire_turns concentration countdown — see that field's own doc comment for why they
	# can't share one name). Once outlined, enemies get Advantage attacking the player, symmetric to
	# the existing enemy-side "Advantage against an outlined enemy, if the attacker can see it" rule
	# — see enemy.gd's _attack_player().
	var pd: Vector2i = player.grid_pos - center
	if pd.x >= 0 and pd.x < r and pd.y >= 0 and pd.y < r and dungeon_floor.has_ranged_los(center, player.grid_pos):
		var pdc: int = _save_dc(stats, spell)
		var pdex_mod: int = stats.dex_modifier()
		var pprof: int = stats.proficiency_bonus if stats.check_prof_dex else 0
		var pdie: int = Rng.roll(20)
		var ptotal: int = pdie + pdex_mod + pprof
		var ppass: bool = ptotal >= pdc
		var psave_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Proficiency,total=%d,dc=%d,stat=DEX,pass=%d" % [
			pdie, pdex_mod, pprof, ptotal, pdc, int(ppass)]
		if ppass:
			GameState.game_log("You [url=%s]resist[/url] the light." % psave_meta)
		else:
			stats.faerie_fire_outlined_turns = 10
			stats.faerie_fire_outlined_color = color
			player._refresh_faerie_fire_visual()
			GameState.game_log("You are [url=%s]outlined[/url] in dancing light!" % psave_meta)

# Detect Magic — a real, lasting sense now (previously a one-shot instant read; that read's own
# item-qualifying rule — Item.requires_attunement, or a nonzero bonus_ac/bonus_damage — lives on
# unchanged as GameState.is_magic_item(), just reused every fog update instead of once at cast
# time). Concentration up to 100 turns: Stats.detect_magic_turns, ticked in player.gd alongside
# every other 100/600-turn buff. While active, DungeonFloor._update_detect_magic_markers() (called
# from update_fog(), same pooled-Sprite2D convention as Dwarf Stonecunning's own tremorsense ping —
# scripts/entities/CLAUDE.md's "Dwarf" section) shows a pulsing BLUE dot over every qualifying
# magic item within Spell.shape_size (3) tiles of the player (Chebyshev), sight-independent exactly
# like Tremorsense (works through walls/Blinded).
static func _resolve_detect_magic(player: Player, spell: Spell) -> void:
	if player.stats.concentration_spell_id != "":
		GameState.end_concentration("" if player.stats.concentration_spell_id == "detect_magic" else "[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	player.stats.concentration_spell_id = "detect_magic"
	player.stats.detect_magic_turns = 100
	GameState.game_log("[color=cyan]You cast [b]%s[/b] — you sense the presence of magic around you.[/color]" % spell.spell_name)
