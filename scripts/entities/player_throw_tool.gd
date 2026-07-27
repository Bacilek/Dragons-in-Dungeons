class_name PlayerThrowTool
extends Node

# Throw-mode / tool-priming activation and the empty-bottle mechanic.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
#
# NOTE: `_throw_item`/`_tool_item` deliberately stay as FIELDS on Player itself (read from
# ~10 other input/movement call sites to cancel throw/tool mode on move/Esc/other actions) —
# only the functions below moved here; they mutate the fields via the `player` back-reference.

var player: Player

func on_throw_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._tool_item = null
	if player._throw_item != null:
		player._throw_item = item
		return
	player._throw_item = item
	GameState.game_log("[color=yellow]Throw [b]%s[/b] — left-click target tile. [Esc] to cancel.[/color]" % item.item_name)

func on_tool_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._throw_item = null
	player._tool_item = item
	if item.item_name == "Empty Bottle":
		GameState.game_log("[color=cyan]Empty Bottle — right-click on adjacent water or mud to fill. [Esc] to cancel.[/color]")
	else:
		GameState.game_log("[color=yellow]Thief Tools — click an adjacent revealed trap to disarm. [Esc] to cancel.[/color]")

func do_throw(pos: Vector2i) -> void:
	var item: Item = player._throw_item
	player._throw_item = null
	if player._dungeon_floor == null:
		return
	var _found: bool = false
	for _s in GameState.player_quickbar:
		if _s == item:
			_found = true
			break
	if not _found:
		for _s in GameState.player_inventory:
			if _s == item:
				_found = true
				break
	if not _found:
		GameState.game_log("[color=gray]Throw cancelled — item no longer in inventory.[/color]")
		return
	if item.item_type == Item.Type.WEAPON and item.is_thrown:
		await _throw_weapon(item, pos)
		return
	GameState.stealth_check_stillness = true
	TurnManager.begin_player_action()
	AudioManager.play("throw_item")
	if player._dungeon_floor.has_door_at(pos) and not player._dungeon_floor.is_door_open(pos):
		player._dungeon_floor.open_door(pos)
	if item.item_type == Item.Type.POTION:
		_shatter_potion(item, pos)
		player._dungeon_floor.update_fog(player.grid_pos)
		TurnManager.on_player_action_complete()
		return
	var trap: Dictionary = player._dungeon_floor.get_trap_at(pos)
	var is_fire: bool = not trap.is_empty() and trap.get("name", "") == "Fire Trap"
	if is_fire and item.item_name == "Rotten Meat":
		GameState.consume_one(item)
		var cooked: Item = player._dungeon_floor.cook_rotten_meat(pos)
		player._dungeon_floor.place_item_on_floor(pos, cooked)
		GameState.game_log("[color=orange]You throw the meat into the fire — it sizzles and cooks! [b]Cooked Meat[/b] landed where the trap was.[/color]")
	elif not trap.is_empty():
		var trap_name: String = trap.get("name", "trap")
		var land_pos: Vector2i = player._dungeon_floor.throw_item_onto_trap(pos, item)
		GameState.consume_one(item)
		if land_pos == Vector2i(-1, -1):
			GameState.game_log("[color=orange]You throw [b]%s[/b] onto the %s — it catches fire and burns to ash![/color]" % [item.item_name, trap_name])
		else:
			var dropped: Item = Item.from_dict(item.to_dict())
			dropped.quantity = 1
			player._dungeon_floor.place_item_on_floor(land_pos, dropped)
			if trap_name == "Pit Spikes":
				GameState.game_log("[color=gray]You throw [b]%s[/b].[/color]" % dropped.item_name)
			elif land_pos != pos:
				GameState.game_log("[color=gray]You throw [b]%s[/b] — the trap shoves it aside as it lands.[/color]" % dropped.item_name)
			else:
				GameState.game_log("[color=gray]You throw [b]%s[/b] — it triggers the trap![/color]" % dropped.item_name)
	else:
		var dropped: Item = Item.from_dict(item.to_dict())
		dropped.quantity = 1
		GameState.consume_one(item)
		player._dungeon_floor.place_item_on_floor(pos, dropped)
		GameState.game_log("[color=gray]You throw [b]%s[/b].[/color]" % dropped.item_name)
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# Potions are glass — thrown, they never land intact (unlike Drop, which places the whole,
# unbroken stack — see GameState.drop_item()). Whatever's on the target tile takes the shattered
# effect (heal-type potions heal it; a potion with no applicable effect just shatters harmlessly);
# an empty tile just breaks the glass for nothing. No Empty Bottle or any other item is ever
# dropped from the shattering — the potion is fully consumed either way.
func _shatter_potion(item: Item, pos: Vector2i) -> void:
	var enemy: Enemy = player._dungeon_floor.get_targetable_enemy_at(pos)
	GameState.consume_one(item)
	if enemy == null:
		GameState.game_log("[color=gray]You throw [b]%s[/b] — it shatters on the ground.[/color]" % item.item_name)
		return
	enemy.on_disturbed(player.grid_pos)
	if item.heal_dice_count > 0 or item.heal_amount > 0:
		var amount: int = 0
		if item.heal_dice_count > 0:
			for _i: int in item.heal_dice_count:
				amount += Rng.roll(item.heal_dice_sides)
		else:
			amount = item.heal_amount
		var before: int = enemy.stats.current_hp
		enemy.stats.current_hp = mini(enemy.stats.max_hp, enemy.stats.current_hp + amount)
		var healed: int = enemy.stats.current_hp - before
		enemy.update_hp_bar()
		GameState.game_log("[color=orange]You throw [b]%s[/b] at [color=orange]%s[/color] — it shatters, healing them for %d HP![/color]" % [item.item_name, enemy.display_name, healed])
	else:
		GameState.game_log("[color=gray]You throw [b]%s[/b] at [color=orange]%s[/color] — it shatters harmlessly.[/color]" % [item.item_name, enemy.display_name])

func make_empty_bottle() -> Item:
	var b := Item.new()
	b.item_name = "Empty Bottle"
	b.item_type = Item.Type.TOOL
	b.icon_path = "res://sprites/items/materials/bottle/small.png"
	b.description = "An empty glass bottle. Fill it from water or mud."
	return b

func try_fill_bottle(bottle: Item, target: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	var dist: int = maxi(absi(target.x - player.grid_pos.x), absi(target.y - player.grid_pos.y))
	if dist > 1:
		GameState.game_log("[color=gray]Too far — stand next to water or mud.[/color]")
		return
	var tile_t: DungeonData.TileType = player._dungeon_floor.get_tile_type(target)
	if tile_t != DungeonData.TileType.WATER and tile_t != DungeonData.TileType.MUD:
		GameState.game_log("[color=gray]Nothing to fill the bottle with here.[/color]")
		return
	GameState.stealth_check_stillness = true
	TurnManager.begin_player_action()
	# Nat 1: bottle shatters
	var fill_roll: int = Rng.roll(20)
	if fill_roll == 1:
		GameState.game_log("[color=red]You fumble — the bottle shatters![/color]")
		if not GameState.invincible:
			GameState.consume_one(bottle)
		GameState.inventory_changed.emit()
		player._dungeon_floor.update_fog(player.grid_pos)
		TurnManager.on_player_action_complete()
		return
	if tile_t == DungeonData.TileType.WATER:
		bottle.item_name = "Bottle of Water"
		bottle.icon_path = "res://sprites/items/materials/bottle/medium.png"
		bottle.description = "A bottle of dungeon water."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=cyan]You fill the bottle with water.[/color]")
	else:
		bottle.item_name = "Bottle of Mud"
		bottle.icon_path = "res://sprites/items/materials/bottle/small.png"
		bottle.description = "A bottle of foul mud. Maybe useful for something."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=gray]You fill the bottle with mud.[/color]")
	GameState.inventory_changed.emit()
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# Thrown weapon (e.g. Spear): uses the melee attack modifier (STR, or max(STR,DEX) if Finesse),
# not a separate DEX/ranged stat. Normal range = weapon.range; beyond that but within weapon.
# long_range (a real fixed field, same as ranged weapons — see item.gd) the throw still works but
# rolls with Disadvantage, and must be in current FOV (is_tile_visible) — same convention as
# ranged weapons (see PlayerRanged.is_ranged_target_in_range()/ranged_shot_disadvantage()). A throw at an
# adjacent target (Chebyshev 1) also rolls with Disadvantage, mirroring ranged_attack()'s
# melee-range check.
#
# Landing (mirrors the ranged-ammo landing model, scripts/items/CLAUDE.md's "Ammo items", but
# with a thrown weapon's own rules): no target tile → lands on the ground at the thrown tile, no
# use lost. A MISS against an enemy → falls to the ground at the enemy's tile (100% chance, does
# NOT embed) — same durability loss as before (-1 use, -2 on a nat-1 fumble). A non-lethal HIT
# still embeds in the enemy (Enemy.embedded_items) instead of landing anywhere (-1 use, 0 on a
# nat-20 crit) — dropped later at 100% chance whenever that enemy eventually dies, from ANY cause,
# via Enemy.die()'s override. If durability hits 0 on this throw the weapon shatters instead of
# landing/embedding (see _consume_throw_use()).
func _throw_weapon(weapon: Item, pos: Vector2i) -> void:
	# Throwing from a stack (quantity > 1, units may carry different durability — see
	# GameState.add_item()) only ever throws a single unit: split the most-damaged one off
	# (GameState._split_one_unit(), shared with equip()'s identical stack split) so the rest of
	# the stack keeps sitting in the bag with its own durability untouched.
	if weapon.quantity > 1:
		weapon = GameState._split_one_unit(weapon)
		GameState.inventory_changed.emit()
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	var sprite: AnimatedSprite2D = player.get_node("AnimatedSprite2D")
	sprite.flip_h = pos.x < player.grid_pos.x
	sprite.play("hit")
	await sprite.animation_finished
	sprite.play("idle")

	var stats: Stats = player.stats
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var atk_mod: int = CombatMath.finesse_modifier(str_mod, dex_mod, weapon.is_finesse)
	var prof: int = CombatMath.weapon_prof_bonus(weapon, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var total_hit_bonus: int = atk_mod + prof + weapon.bonus_damage

	var d: Vector2i = pos - player.grid_pos
	var dist_sq: int = d.x * d.x + d.y * d.y
	var long_r: int = weapon.long_range if weapon.long_range > 0 else DungeonFloor.FOV_RADIUS
	var in_normal_range: bool = dist_sq <= weapon.range * weapon.range
	var in_range: bool = in_normal_range or (dist_sq <= long_r * long_r and player._dungeon_floor.is_tile_visible(pos))
	if not in_range:
		GameState.game_log("[color=gray]Too far to throw %s.[/color]" % weapon.item_name)
		player._handle_post_attack_turn()
		return
	var long_throw: bool = not in_normal_range

	var enemy: Enemy = player._dungeon_floor.get_targetable_enemy_at(pos)
	# Captured BEFORE on_disturbed() wakes the enemy — both has_advantage() and the melee-range
	# DISADV exemption below read pre-attack behavior/door_ambush state, which on_disturbed()
	# immediately mutates away.
	var was_surprised: bool = false
	var target_was_unaware: bool = false
	if enemy != null:
		was_surprised = player._vfx.has_advantage(enemy)
		target_was_unaware = enemy.behavior in [Enemy.Behavior.SLEEPING, Enemy.Behavior.STATIONARY, Enemy.Behavior.ROAMING]
		enemy.on_disturbed(player.grid_pos)
	var target_world_pos: Vector2 = enemy.position if enemy != null else Vector2(pos.x * 16 + 8, pos.y * 16 + 8)
	player._ranged.show_projectile(target_world_pos, weapon)

	if enemy == null:
		GameState.game_log("[color=gray]You throw [b]%s[/b] — it lands on the ground.[/color]" % weapon.item_name)
		if weapon.is_torch and weapon.torch_lit:
			if player._dungeon_floor.get_tile_type(pos) == DungeonData.TileType.WATER:
				weapon.torch_lit = false
				GameState.game_log("[color=cyan]The water douses the torch![/color]")
			else:
				player._dungeon_floor.ignite_flammable(pos)
		GameState.remove_item(weapon)
		player._dungeon_floor.place_item_on_floor(pos, weapon)
		player._dungeon_floor.update_fog(player.grid_pos)
		player._handle_post_attack_turn()
		return

	var adv_count: int = 0
	adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	# Bloodhound R1: the first attack against a freshly-marked Hunter's Mark target gets Advantage.
	adv_count += player._ranger_talents.consume_bloodhound_fresh_adv(enemy)
	var disadv_count: int = 0
	if was_surprised: adv_count += 1
	if stats.zealous_presence_turns > 0: adv_count += 1
	if long_throw: disadv_count += 1
	if weapon.is_heavy and stats.strength < 13: disadv_count += 1
	# Same convention as ranged weapons: throwing at an adjacent target (Chebyshev 1) is
	# awkward at that range, so it rolls with Disadvantage too (PlayerRanged.ranged_attack()).
	# EXCEPT against an unaware target (SLEEPING/STATIONARY/ROAMING) — 5e RAW exempts an
	# incapacitated nearby creature from this "distracted by a hostile at melee range" penalty,
	# and a sleeping/unaware enemy is the closest equivalent this engine has; without this
	# exemption the surprise-attack Advantage from has_advantage() always cancels right back out.
	if maxi(absi(d.x), absi(d.y)) <= 1 and not target_was_unaware: disadv_count += 1
	if GameState.is_blinded(player.grid_pos): disadv_count += 1
	if stats.has_disadvantage_condition(): disadv_count += 1
	if enemy.prone: disadv_count += 1  # Prone: ranged/thrown attacks against it have DISADV
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var roll: int = die + total_hit_bonus
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit()
		player._berserker.refresh_on_any_crit()
	var is_nat_one: bool = die == 1

	var mod_key: String = "dex" if (weapon.is_finesse and dex_mod > str_mod) else "str"
	var hit_meta: String = "thrhit:die=%d,d1=%d,d2=%d,%s=%d,prof=%d,wpn=%d,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d" % [
		die, die1, die2, mod_key, atk_mod, prof, weapon.bonus_damage, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0,
		1 if is_crit else 0, 1 if is_nat_one else 0, 1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0]

	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("You throw [b]%s[/b] at [color=orange]%s[/color] — [url=%s]%s[/url]." % [weapon.item_name, enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		if is_nat_one:
			GameState.crit_banner.emit("CRITICAL FAIL!", Color(0.9, 0.1, 0.1))
			GameState.screen_shake.emit(2.5)
		if not _consume_throw_use(weapon, 2 if is_nat_one else 1):
			GameState.remove_item(weapon)
			player._dungeon_floor.place_item_on_floor(pos, weapon)
		player._dungeon_floor.update_fog(player.grid_pos)
		player._handle_post_attack_turn()
		return

	if is_crit: AudioManager.play_crit(weapon)
	else: AudioManager.play_hit(enemy.enemy_id)
	player._vfx.flash_hit(enemy)
	if adv and not disadv:
		player._vfx.show_surprise_mark(enemy)

	var dmin: int = weapon.damage_die_min if weapon.damage_die_min > 0 else stats.base_min_damage
	var dmax: int = weapon.damage_die_max if weapon.damage_die_max > 0 else stats.base_max_damage
	var die_roll: int = Rng.range_i(dmin, dmax)
	var pre_crit: int = die_roll + weapon.bonus_damage + atk_mod
	if is_crit:
		pre_crit *= 2
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)

	var actual: int = enemy.stats.take_damage(pre_crit)
	enemy.update_hp_bar()
	player._dungeon_floor.show_damage(enemy.position, actual, false)

	var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,%s=%d,rage=0,frenzy=0,ironwood=0,divine=0,divtype=,crit=%d,final=%d" % [
		die_roll, dmin, dmax, weapon.bonus_damage, mod_key, atk_mod, 1 if is_crit else 0, actual]
	var dmg_type: String = weapon.damage_type if not weapon.damage_type.is_empty() else "<unknown_damage_type>"
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type

	# Torch: a lit torch thrown at an enemy also deals a second, independent 1d4 Fire damage
	# instance — mirrors the Main-Hand melee Fire bonus in player.gd._bump_attack() exactly (own
	# take_typed_damage() call, own floater, own dmg: tooltip segment on the same log line).
	var torch_actual: int = 0
	var torch_inst: Dictionary = {}
	if weapon.is_torch and weapon.torch_lit:
		var torch_rolls: Array[int] = Rng.roll_dice(1, 4)
		torch_inst = CombatMath.build_damage_instance(torch_rolls, 4, [], is_crit, "Fire")
		var torch_result: Dictionary = enemy.take_typed_damage(torch_inst["subtotal"], "Fire", is_crit)
		torch_inst["final"] = torch_result["actual"]
		torch_inst["resist_mul"] = torch_result["mul"]
		torch_actual = torch_result["actual"]
		enemy.update_hp_bar()
		player._dungeon_floor.show_damage(enemy.position, torch_actual, false, CombatMath.damage_type_color("Fire"), 1)

	# Hunter's Mark: second, independent Force damage instance on a hit against the marked target.
	var hm_actual: int = 0
	var hm_inst: Dictionary = {}
	var hm_die: int = player._ranger_talents.hunters_mark_bonus_die(enemy, true)
	if hm_die > 0:
		var hm_rolls: Array[int] = [hm_die]
		hm_inst = CombatMath.build_damage_instance(hm_rolls, 6, [], is_crit, "Force")
		var hm_result: Dictionary = enemy.take_typed_damage(hm_inst["subtotal"], "Force", is_crit)
		hm_inst["final"] = hm_result["actual"]
		hm_inst["resist_mul"] = hm_result["mul"]
		hm_actual = hm_result["actual"]
		enemy.update_hp_bar()
		player._dungeon_floor.show_damage(enemy.position, hm_actual, false, CombatMath.damage_type_color("Force"), 2 if torch_actual > 0 else 1)

	var is_lethal: bool = enemy.stats.is_dead()

	var dmg_segment: String = "[url=%s][color=yellow]%d[/color][/url]%s" % [dmg_meta, actual, type_tag]
	if torch_actual > 0:
		var torch_meta: String = CombatMath.encode_damage_instance(torch_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Fire[/color]" % [torch_meta, torch_actual]
	if hm_actual > 0:
		var hm_meta: String = CombatMath.encode_damage_instance(hm_inst)
		dmg_segment += " and [url=%s][color=yellow]%d[/color][/url] [color=gray]Force[/color]" % [hm_meta, hm_actual]

	if is_crit:
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=red]CRIT![/color] You [url=%s]throw[/url] [b]%s[/b] at [color=orange]%s[/color] for %s dmg.%s" % [hit_meta, weapon.item_name, enemy.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	else:
		GameState.game_log(CombatMath.wrap_halfling_luck("You [url=%s]throw[/url] [b]%s[/b] at [color=orange]%s[/color] for %s dmg.%s" % [hit_meta, weapon.item_name, enemy.display_name, dmg_segment, CombatMath.death_suffix(is_lethal)], r["lucky"]))

	# Sap: on a hit, the target has Disadvantage on its very next attack, next turn. Reuses the
	# same Enemy.disadv_next_attack flag/consumption point as Grip of the Forest R3.
	if weapon.weapon_mastery == "Sap" and stats.knows_mastery("Sap"):
		enemy.disadv_next_attack = true

	if not _consume_throw_use(weapon, 0 if is_crit else 1):
		# Embed rather than drop — survives on the enemy until it dies (any cause, any turn),
		# at which point Enemy.die() drops it at 100% chance. Embedding before the is_dead()
		# check below means an immediate kill on this same throw drops it right away too.
		GameState.remove_item(weapon)
		enemy.embedded_items.append(weapon)

	if is_lethal:
		player._finish_kill(enemy)

	player._dungeon_floor.update_fog(player.grid_pos)
	player._handle_post_attack_turn()

# Returns true if the weapon broke (already logged + removed from GameState) — callers should
# skip landing/embedding it anywhere in that case, since it no longer physically exists.
func _consume_throw_use(weapon: Item, uses_lost: int) -> bool:
	if GameState.invincible or uses_lost <= 0:
		return false
	weapon.uses_remaining = maxi(0, weapon.uses_remaining - uses_lost)
	if weapon.uses_remaining <= 0:
		AudioManager.play("weapon_break")
		GameState.game_log("[color=gray]Your %s breaks![/color]" % weapon.item_name)
		GameState.remove_item(weapon)
		return true
	return false
