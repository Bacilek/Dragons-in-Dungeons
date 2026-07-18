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
	if GameState.is_in_fog_cloud(player.grid_pos): disadv_count += 1

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
				var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
					save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
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

# Single-target SAVE-resolution cantrips (Toll the Dead, Mind Sliver) — no attack roll, the target
# just makes a save. Mirrors cast_spell()'s turn envelope/animation but skips the hit-roll block
# entirely (there's nothing to roll against an AC).
static func cast_cantrip_save_at_enemy(player: Player, spell: Spell, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var dc: int = _save_dc(stats)
	var use_wis: bool = spell.effect_id == "toll_the_dead"
	var use_int: bool = spell.effect_id == "mind_sliver"
	var save: Dictionary = target.resist_check_detailed(dc, false, false, use_wis, use_int)
	var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
		save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]

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
		var dc: int = _save_dc(stats)
		var save: Dictionary = e.resist_check_detailed(dc, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
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

# Light cantrip — touch an object resting on the ground (a floor item, never a worn/carried one)
# and it becomes a real light source: DungeonFloor.update_fog() unions its own shadowcast into the
# player's FOV every turn (scripts/world/CLAUDE.md), so it genuinely pushes back the fog, not just
# a cosmetic glow. Only one Light source active at a time (GameState.set_light_source() replaces
# whatever was lit before); ends on rest or floor descent — see GameState.clear_light_source()'s
# call sites.
static func cast_light_at_tile(player: Player, spell: Spell, tile_pos: Vector2i, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = tile_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var target_item: Item = dungeon_floor.get_item_at(tile_pos) if dungeon_floor != null else null
	if target_item == null:
		GameState.game_log("[color=gray]You must touch an object resting on the ground.[/color]")
	else:
		const LIGHT_COLORS: Array[Color] = [
			Color(1.0, 0.85, 0.55), Color(0.55, 0.85, 1.0), Color(0.6, 1.0, 0.65),
			Color(1.0, 0.6, 0.8), Color(0.8, 0.65, 1.0), Color(1.0, 1.0, 0.6),
		]
		var c: Color = Rng.pick(LIGHT_COLORS)
		GameState.set_light_source(tile_pos, c, target_item)
		GameState.game_log("[color=cyan]The %s begins to glow with a soft light.[/color]" % target_item.item_name)

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
# Deliberately simplified vs. the framework doc: no upcasting at all — a spell is locked to its own
# slot level (StandardSlotPool.available_level()), never auto-promoted to a higher still-available
# slot, and AoE is sphere-only (no cone/line/cube). God Mode (GameState.invincible) skips the
# slot-availability check entirely (PlayerSpellcasting._cast_level_for()) as well as consumption
# (_consume_slot() below) — casting never needs or spends a slot while active.

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
		"blade_ward":
			# Concentration: only one concentration effect at a time (5e rule) — recasting Blade
			# Ward just refreshes its own duration; casting a DIFFERENT concentration spell breaks
			# this one first via GameState.end_concentration(), which also zeroes Blade Ward's own
			# turn counter (not just the id) so it can't linger after the switch.
			if player.stats.concentration_spell_id != "" and player.stats.concentration_spell_id != "blade_ward":
				GameState.end_concentration("[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "blade_ward"
			player.stats.blade_ward_turns = 10
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — attacks against you falter for up to 10 turns.[/color]" % spell.spell_name)
		"thunderclap":
			_resolve_thunderclap(player, spell, dungeon_floor)
		"expeditious_retreat":
			if player.stats.concentration_spell_id != "" and player.stats.concentration_spell_id != "expeditious_retreat":
				GameState.end_concentration("[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
			player.stats.concentration_spell_id = "expeditious_retreat"
			player.stats.expeditious_retreat_turns = 100
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — your reflexes quicken for up to 100 turns.[/color]" % spell.spell_name)
		"false_life":
			var rolls: Array[int] = Rng.roll_dice(spell.dice_count, spell.dice_sides)
			var total: int = 4
			for v: int in rolls:
				total += v
			player.stats.temp_hp = maxi(player.stats.temp_hp, total)
			GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
			GameState.game_log("[color=cyan]You cast [b]%s[/b] — a sickly resilience grants [color=lightblue]%d[/color] Temp HP.[/color]" % [spell.spell_name, total])
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
		"burning_hands":
			_resolve_cone_aoe(player, spell, tile_pos, dungeon_floor)
		"fog_cloud":
			_resolve_fog_cloud(player, spell, tile_pos)
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
static func cone_tiles(origin: Vector2i, aim_tile: Vector2i, length: int, dungeon_floor: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var dir_v: Vector2 = Vector2(aim_tile - origin)
	if dir_v.length() < 0.001:
		return out
	dir_v = dir_v.normalized()
	for dy: int in range(-length, length + 1):
		for dx: int in range(-length, length + 1):
			if dx == 0 and dy == 0:
				continue
			var v: Vector2 = Vector2(dx, dy)
			var forward: float = v.dot(dir_v)
			if forward <= 0.0 or forward > float(length):
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
			dungeon_floor.destroy_grass(p)

	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if not tile_set.has(e.grid_pos):
			continue
		var dc: int = _save_dc(stats)
		var save: Dictionary = e.resist_check_detailed(dc, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
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
	for e: Enemy in targets:
		var dc: int = _save_dc(stats)
		var save: Dictionary = e.resist_check_detailed(dc, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=Floor,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
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
			var darts: int = 3
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

# ENEMY target, ATTACK_ROLL resolution, LEVELED spells (Chromatic Orb, Witch Bolt) — rolls an
# attack vs the target's AC exactly like a cantrip (cast_spell()), but also consumes a spell slot.
# `is_leap` is Chromatic Orb's single extra bolt (see effect_id dispatch below) — a fresh attack +
# damage roll against a second target, reusing the same log-line shape with the "leaps to" phrasing
# instead of "cast ... at".
static func _resolve_spell_attack_bolt(player: Player, spell: Spell, target: Enemy, dtype: String, dungeon_floor: Node, is_leap: bool) -> Dictionary:
	var stats: Stats = player.stats
	var attack_bonus: int = _attack_bonus(stats)

	var adv_count: int = 0
	if not is_leap:
		adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	var disadv_count: int = 0
	if player._vfx.has_advantage(target): adv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	var d_vec: Vector2i = target.grid_pos - player.grid_pos
	if spell.range_tiles > 1 and maxi(abs(d_vec.x), abs(d_vec.y)) <= 1: disadv_count += 1
	if GameState.is_in_fog_cloud(player.grid_pos): disadv_count += 1

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
	var result: Dictionary = target.take_typed_damage(inst["subtotal"], dtype)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	target.update_hp_bar()
	if dungeon_floor != null:
		dungeon_floor.show_damage(target.position, actual, false, CombatMath.damage_type_color(dtype))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var type_tag: String = " [color=gray]%s[/color]" % dtype
	var is_lethal: bool = target.stats.is_dead()
	var verb: String = "CRIT! " if is_crit else ""
	var hit_line: String
	if is_leap:
		hit_line = "%sThe orb [url=%s]leaps[/url] to [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [
			verb, hit_meta, target.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)]
	else:
		hit_line = "%sYou [url=%s]cast[/url] [color=cyan]%s[/color] at [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url]%s dmg.%s" % [
			verb, hit_meta, spell.spell_name, target.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)]
	GameState.game_log(CombatMath.wrap_halfling_luck(hit_line, r["lucky"]))

	if is_lethal:
		player._finish_kill(target)
	return {"hit": true, "lethal": is_lethal, "rolls": rolls}

# Picks a random OTHER alive enemy visible to the player (Chromatic Orb's leap target) — never the
# player, a companion, or the original target. Returns null if no other visible enemy exists.
static func _pick_chromatic_orb_leap_target(dungeon_floor: Node, exclude: Enemy) -> Enemy:
	if dungeon_floor == null:
		return null
	var candidates: Array[Enemy] = []
	for e: Enemy in dungeon_floor.get_visible_enemies():
		if e == exclude or not is_instance_valid(e) or e.stats.is_dead():
			continue
		candidates.append(e)
	if candidates.is_empty():
		return null
	return Rng.pick(candidates)

# ENEMY target, ATTACK_ROLL resolution, LEVELED spells (Chromatic Orb, Witch Bolt).
static func cast_leveled_attack_at_enemy(player: Player, spell: Spell, cast_level: int, target: Enemy, dungeon_floor: Node, from_scroll: bool = false) -> void:
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = target.grid_pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")
	_consume_slot(player, cast_level, from_scroll)

	match spell.effect_id:
		"chromatic_orb":
			# Damage type is rolled once per cast, before the attack roll — a leap (if triggered)
			# reuses the same type rather than re-rolling, like the orb's energy carrying over.
			var dtype: String = Rng.pick(CHROMATIC_ORB_TYPES)
			var res: Dictionary = _resolve_spell_attack_bolt(player, spell, target, dtype, dungeon_floor, false)
			if res["hit"] and not res["lethal"]:
				var rolls: Array = res["rolls"]
				var seen: Dictionary = {}
				var has_pair: bool = false
				for v: int in rolls:
					seen[v] = seen.get(v, 0) + 1
					if seen[v] >= 2:
						has_pair = true
				if has_pair:
					var leap_target: Enemy = _pick_chromatic_orb_leap_target(dungeon_floor, target)
					if leap_target != null:
						GameState.game_log("[color=cyan]The orb crackles and leaps toward a new target![/color]")
						_resolve_spell_attack_bolt(player, spell, leap_target, dtype, dungeon_floor, true)
		"witch_bolt":
			var res2: Dictionary = _resolve_spell_attack_bolt(player, spell, target, spell.damage_type, dungeon_floor, false)
			if res2["hit"] and not res2["lethal"]:
				var stats: Stats = player.stats
				if stats.concentration_spell_id != "" and stats.concentration_spell_id != "witch_bolt":
					GameState.end_concentration("[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
				stats.concentration_spell_id = "witch_bolt"
				stats.witch_bolt_target = target
				stats.witch_bolt_turns = 10
				stats.witch_bolt_just_cast = true
				GameState.game_log("[color=cyan]%s is Jolted — crackling energy will keep striking it.[/color]" % target.display_name)

	if dungeon_floor != null:
		dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

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
static func _resolve_fog_cloud(player: Player, spell: Spell, center: Vector2i) -> void:
	var stats: Stats = player.stats
	if stats.concentration_spell_id != "" and stats.concentration_spell_id != "fog_cloud":
		GameState.end_concentration("[color=gray]Casting %s breaks your concentration.[/color]" % spell.spell_name)
	stats.concentration_spell_id = "fog_cloud"
	stats.fog_cloud_turns = 100
	GameState.fog_cloud_pos = center
	GameState.fog_cloud_radius = spell.shape_size
	GameState.game_log("[color=cyan]A thick fog billows outward, obscuring the area![/color]")
