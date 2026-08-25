class_name PlayerMonk
extends Node

# Monk's Martial Arts feature (D&D 2024 PHB text, given directly by the project owner):
# while unarmed or wielding only Monk weapons (Simple weapons, or Martial weapons with the Light
# property — exactly Stats.martial_weapon_restriction's own "light" definition, see
# scripts/entities/CLAUDE.md's "Monk class"), and wearing no armor and no shield:
#   - Bonus Unarmed Strike: after the Attack action lands or misses, make one free unarmed strike.
#   - Martial Arts Die: unarmed damage (and, in place of a Monk weapon's own weaker die) uses
#     Stats.martial_arts_die_sides, which scales with level.
#   - Dextrous Attacks: DEX instead of STR for the attack AND damage roll of unarmed strikes and
#     Monk weapons.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md's "Split-out
# modules". Grapple/shove with DEX is not implemented (no grapple/shove mechanic exists at all).

var player: Player

# Monk's Focus (D&D 2024's "Ki", Stats.monk_focus_points/monk_focus_points_max) — three level-2
# activatable features, each costing 1 Focus Point, spent via GameState.spend_monk_focus().
# Flurry of Blows: arms the NEXT Bonus Unarmed Strike (see try_bonus_unarmed_strike() below) to
# resolve twice instead of once. Not serialized (mid-combat transient, same tier as every other
# per-turn pending flag) — captured/restored via get_rewind_fields()/set_rewind_fields() below.
var flurry_pending: bool = false

# Step of the Wind: arm-then-click/WASD one-tile free dash, same shape as Orc's Adrenaline Rush
# (player_orc.gd) — see resolve_step_of_wind() below. Once per turn (GameState.
# step_of_wind_used_this_turn, reset in Player._on_turn_started(), same precedent as Grip of the
# Forest/Halfling Nimbleness's own once-per-turn flags).
var step_of_wind_mode_active: bool = false
const STEP_OF_WIND_RANGE: int = 1

func get_rewind_fields() -> Dictionary:
	return {"flurry_pending": flurry_pending, "step_of_wind_mode_active": step_of_wind_mode_active}

func set_rewind_fields(d: Dictionary) -> void:
	flurry_pending = bool(d.get("flurry_pending", false))
	step_of_wind_mode_active = bool(d.get("step_of_wind_mode_active", false))

# item == null means unarmed, always a Monk weapon. Mirrors Stats.martial_weapon_restriction's
# own "light" definition (Simple weapons, or Martial weapons with the Light property) — the exact
# same subset Monk is proficient with, see EquipRequirements.can_equip_weapon()/
# Stats.is_weapon_proficient().
static func is_monk_weapon(item: Item) -> bool:
	if item == null:
		return true
	if item.item_type != Item.Type.WEAPON:
		return false
	match item.weapon_category:
		"Simple": return true
		"Martial": return item.is_light
		_: return false

# Shared "Monk, no armor, no shield" gate — every unarmored Monk feature (Martial Arts,
# Unarmored Movement) requires this baseline; Martial Arts additionally requires the Main Hand
# itself to be a Monk weapon (see martial_arts_active() below), Unarmored Movement doesn't care
# what's in Main Hand at all. Static (reads GameState directly, no Player reference needed) so
# GameState.is_ability_usable()/ability_unusable_reason() can call it for the Focus abilities'
# ability-bar greying below without needing a live Player node.
static func _unarmored_and_unshielded() -> bool:
	if GameState.player_stats.character_class != Stats.CharacterClass.MONK:
		return false
	if GameState.equipment.get("armor") != null:
		return false
	var off_hand: Item = GameState.equipment.get("hand2") as Item
	if off_hand != null and off_hand.is_shield:
		return false
	return true

# Martial Arts as a whole is only active for a Monk with no armor and no shield equipped, wielding
# nothing but a Monk weapon (or nothing at all) in Main Hand. Off-hand isn't checked here — see
# try_bonus_unarmed_strike()'s own dual-wield exclusion below.
static func martial_arts_active(main_hand: Item) -> bool:
	if not _unarmored_and_unshielded():
		return false
	return is_monk_weapon(main_hand)

# Unarmored Movement (level 2+): while unarmored and shield-free, extra speed as a fraction of a
# real move — 1/3 at level 2, 1/2 at 6, 2/3 at 10, 5/6 at 14, a full extra move (i.e. every move is
# free) at 18. Expressed as a numerator out of a fixed denominator of 6 so it reuses the same
# Bresenham-style duty-cycle machinery as Longstrider/Wood Elf speed (Player._consume_duty_cycle(),
# CombatMath.tick_duty_cycle()) instead of a bespoke fraction system.
const UNARMORED_MOVEMENT_DUTY_CYCLE_PER: int = 6

static func unarmored_movement_numerator(level: int) -> int:
	if level >= 18: return 6  # +1 (every move free)
	if level >= 14: return 5  # +5/6
	if level >= 10: return 4  # +2/3
	if level >= 6:  return 3  # +1/2
	if level >= 2:  return 2  # +1/3
	return 0

static func unarmored_movement_active() -> bool:
	return _unarmored_and_unshielded() and unarmored_movement_numerator(GameState.player_stats.character_level) > 0

# Whether the player is currently "engaged" (adjacent to a live, visible enemy) — Patient
# Defense's own gating condition. Static for the same GameState-only-callable reason as
# martial_arts_active() above; uses Enemy.min_dist_to() so a Large enemy's whole footprint counts,
# not just its origin tile.
static func is_engaged() -> bool:
	var tree: SceneTree = Engine.get_main_loop() as SceneTree
	if tree == null:
		return false
	var df: Node = tree.get_first_node_in_group("dungeon_floor")
	if df == null:
		return false
	for e: Enemy in df.get_visible_enemies():
		if is_instance_valid(e) and not e.stats.is_dead() and e.min_dist_to(GameState.player_grid_pos) <= 1:
			return true
	return false

# Martial Arts Die: use it in place of the weapon's own damage die whenever it would deal more
# (unarmed always uses it, since it has no weapon die of its own). Returns (dmin, dmax).
func damage_die(main_hand: Item) -> Vector2i:
	var ma_max: int = player.stats.martial_arts_die_sides
	if main_hand == null or main_hand.damage_die_max <= 0:
		return Vector2i(1, ma_max)
	if ma_max > main_hand.damage_die_max:
		return Vector2i(1, ma_max)
	return Vector2i(main_hand.damage_die_min, main_hand.damage_die_max)

# Bonus Unarmed Strike: a free extra unarmed attack after the main swing lands or misses — called
# from both the hit and miss tails of Player._bump_attack(), same timing as _try_offhand_attack().
# Flurry of Blows (Monk's Focus, level 2+): if armed, this single strike becomes two.
func try_bonus_unarmed_strike(enemy: Enemy) -> void:
	if not is_instance_valid(enemy) or enemy.stats.is_dead():
		return
	var main_hand: Item = GameState.equipped_weapon
	if not martial_arts_active(main_hand):
		return
	# Don't stack with the generic dual-wield Off-hand bonus attack (Player._try_offhand_attack) —
	# a Monk dual-wielding two Light weapons already gets a free extra swing from that; Martial
	# Arts' own Bonus Unarmed Strike only fires when nothing else already did.
	var off_hand: Item = GameState.equipment.get("hand2") as Item
	if main_hand != null and main_hand.is_light and off_hand != null \
			and off_hand.item_type == Item.Type.WEAPON and not off_hand.is_ranged and off_hand.is_light:
		return
	var swings: int = 1
	if flurry_pending:
		# Flurry's own activation already spent the Bonus Action when it was armed — this trigger
		# bypasses the gate entirely and just resolves the doubled strike.
		flurry_pending = false
		swings = 2
		GameState.game_log("[color=cyan]Flurry of Blows![/color]")
	else:
		# A plain Bonus Unarmed Strike is itself a bonus-action-shaped free attack (Bonus Action
		# economy, scripts/entities/CLAUDE.md) — gate it exactly like every other bonus-action
		# ability: no strike at all if the bonus action is already spent on something else.
		if GameState.bonus_action_used and not GameState.invincible:
			return
		if not GameState.invincible:
			GameState.bonus_action_used = true
			GameState.ability_bar_changed.emit()
	for i: int in swings:
		if not is_instance_valid(enemy) or enemy.stats.is_dead():
			break
		_resolve_bonus_unarmed_strike(enemy)

func _resolve_bonus_unarmed_strike(enemy: Enemy) -> void:
	var stats: Stats = player.stats
	enemy.on_disturbed(player.grid_pos)
	var dex_mod: int = stats.dex_modifier()
	var prof: int = stats.proficiency_bonus  # unarmed strikes are always proficient
	var adv_count: int = 0
	adv_count += player._base_talents.consume_psycho_or_battlefield_adv()
	if enemy.prone: adv_count += 1
	if enemy.restrained_turns > 0: adv_count += 1
	var disadv_count: int = 0
	if GameState.is_blinded(player.grid_pos): disadv_count += 1
	if stats.has_disadvantage_condition(): disadv_count += 1
	if player._frightened_active(): disadv_count += 1
	var r := CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
	var die1: int = r["die1"]
	var die2: int = r["die2"]
	var die: int = r["die"]
	var adv: bool = r["adv"]
	var disadv: bool = r["disadv"]
	var bonus_exh: int = CombatMath.exhaustion_penalty()
	var roll: int = die + dex_mod + prof + bonus_exh
	var is_crit: bool = CombatMath.is_critical_hit(die, adv)
	if is_crit:
		player._base_talents.on_crit()
	var is_nat_one: bool = die == 1
	var hit_meta: String = "hit:die=%d,d1=%d,d2=%d,dex=%d,prof=%d,wpn=0,reck=0,total=%d,ac=%d,adv=%d,disadv=%d,n20=%d,n1=%d,lucky1=%d,lucky2=%d,exh=%d" % [
		die, die1, die2, dex_mod, prof, roll, enemy.stats.armor_class,
		1 if (adv and not disadv) else 0, 1 if (disadv and not adv) else 0, 1 if is_crit else 0, 1 if is_nat_one else 0,
		1 if r["lucky1"] else 0, 1 if r["lucky2"] else 0, bonus_exh]
	if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
		var miss_color: String = "[color=red]critical fail[/color]" if is_nat_one else "[color=gray]miss[/color]"
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Bonus Unarmed Strike:[/color] you strike at [color=orange]%s[/color] — [url=%s]%s[/url]." % [enemy.display_name, hit_meta, miss_color], r["lucky"]))
		AudioManager.play("crit_fail" if is_nat_one else "miss_enemy")
		return
	if is_crit: AudioManager.play_crit()
	else: AudioManager.play_hit(enemy.enemy_id)
	player._vfx.flash_hit(enemy)
	var ma_max: int = stats.martial_arts_die_sides
	var rolls: Array[int] = Rng.roll_dice(1, ma_max)
	var raw_mods: Array = [{"name": "DEX mod", "amount": dex_mod, "color": "lightblue"}]
	var flat_mods: Array = raw_mods.filter(func(m: Dictionary) -> bool: return int(m.get("amount", 0)) != 0)
	var inst: Dictionary = CombatMath.build_damage_instance(rolls, ma_max, flat_mods, is_crit, "Bludgeoning")
	if is_crit:
		GameState.crit_banner.emit("CRITICAL HIT!", Color(1.0, 0.85, 0.0))
		GameState.screen_shake.emit(5.0)
	var result: Dictionary = enemy.take_typed_damage(inst["subtotal"], "Bludgeoning", is_crit)
	inst["final"] = result["actual"]
	inst["resist_mul"] = result["mul"]
	var actual: int = result["actual"]
	enemy.update_hp_bar()
	if actual > 0:
		enemy.on_melee_hit(player)
	if player._dungeon_floor != null:
		player._dungeon_floor.show_damage(enemy.position, actual, false, CombatMath.damage_type_color("Bludgeoning"))
	var dmg_meta: String = CombatMath.encode_damage_instance(inst)
	var is_lethal: bool = enemy.stats.is_dead()
	GameState.game_log(CombatMath.wrap_halfling_luck("[color=cyan]Bonus Unarmed Strike:[/color] you [url=%s]strike[/url] [color=orange]%s[/color] for [url=%s][color=yellow]%d[/color][/url] [color=gray]Bludgeoning[/color] dmg.%s" % [hit_meta, enemy.display_name, dmg_meta, actual, CombatMath.death_suffix(is_lethal)], r["lucky"]))
	if is_lethal:
		player._finish_kill(enemy)

# ── Monk's Focus: Flurry of Blows ───────────────────────────────────────────
# A free action (no turn cost) — arms flurry_pending, consumed by the very next Bonus Unarmed
# Strike trigger (try_bonus_unarmed_strike() above). Silently no-ops if already armed (never
# double-spends Focus for the same pending buff) or if Martial Arts isn't currently active (same
# gear/armor/shield gate the Bonus Unarmed Strike it doubles already requires).
func activate_flurry_of_blows() -> void:
	if flurry_pending:
		return
	if not martial_arts_active(GameState.equipped_weapon):
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.spend_monk_focus(1):
		return
	if not GameState.invincible:
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	flurry_pending = true
	GameState.game_log("[color=cyan]Flurry of Blows: your next Bonus Unarmed Strike hits twice.[/color]")

# ── Monk's Focus: Patient Defense ───────────────────────────────────────────
# Costs the player's turn (a Dodge action substitute, not a free buff) — grants Stats.dodge_turns
# = 1, which imposes DISADV on every attack roll against the player (enemy.gd's _attack_player())
# until it ticks to 0 at the start of the player's own next turn (Stats.tick_status()). Only
# activatable while engaged (PlayerMonk.is_engaged()) — see GameState.is_ability_usable()'s
# "patient_defense" case for the matching ability-bar grey-out.
func activate_patient_defense() -> void:
	if not is_engaged():
		return
	if not GameState.spend_monk_focus(1):
		return
	TurnManager.begin_player_action()
	player.stats.dodge_turns = 1
	GameState.player_status_changed.emit()
	GameState.game_log("[color=cyan]Patient Defense: attacks against you have Disadvantage until your next turn.[/color]")
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# ── Monk's Focus: Step of the Wind ──────────────────────────────────────────
# Arm-then-click/WASD one-tile free dash — directly modeled on Orc's Adrenaline Rush
# (player_orc.gd's dash_mode_active/resolve_dash()), just Focus-gated instead of a per-rest
# counter, no temp HP, and limited to once per turn (GameState.step_of_wind_used_this_turn).
func activate_step_of_wind() -> void:
	if GameState.step_of_wind_used_this_turn:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.spend_monk_focus(1):
		return
	if not GameState.invincible:
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	step_of_wind_mode_active = true
	GameState.game_log("[color=cyan]Step of the Wind: click an adjacent tile to dash there for free.[/color]")

func cancel_step_of_wind() -> void:
	step_of_wind_mode_active = false

## Resolves the armed one-tile dash — genuinely free (no turn cost, no TurnManager envelope at
## all, matching Adrenaline Rush's own resolve_dash()), just a normal move-animation slide onto an
## adjacent tile so it visibly reads as "one free move." Marks step_of_wind_used_this_turn on a
## successful dash only — a cancelled/out-of-range/blocked attempt spends nothing further (the
## Focus Point itself was already spent on activation, matching Adrenaline Rush's own convention
## of spending the resource on arm, not on a successful landing).
func resolve_step_of_wind(clicked: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	if clicked == player.grid_pos:
		return
	var d: Vector2i = clicked - player.grid_pos
	if maxi(absi(d.x), absi(d.y)) > STEP_OF_WIND_RANGE:
		GameState.game_log("[color=gray]Step of the Wind: that tile isn't adjacent.[/color]")
		return
	if not player._dungeon_floor.is_tile_visible(clicked):
		GameState.game_log("[color=gray]You can't see that space.[/color]")
		return
	if not player._dungeon_floor.is_walkable(clicked) or player._dungeon_floor.get_enemy_at(clicked) != null:
		GameState.game_log("[color=gray]That space is occupied.[/color]")
		return
	if player.size != Vector2i.ONE and player._goliath.blocks_large_form_move(clicked):
		GameState.game_log("[color=gray]Not enough room there for your Large Form.[/color]")
		return
	var prev: Vector2i = player.grid_pos
	GameState.step_of_wind_used_this_turn = true
	GameState.ability_bar_changed.emit()
	await player.move_to(clicked)
	if player._dungeon_floor.has_door_at(prev):
		player._dungeon_floor.close_door(prev)
	player._dungeon_floor.update_fog(player.grid_pos)
	GameState.game_log("[color=cyan]Step of the Wind: you dash forward.[/color]")
