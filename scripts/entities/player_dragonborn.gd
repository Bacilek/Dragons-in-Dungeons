class_name PlayerDragonborn
extends Node

# Dragonborn race abilities: Breath Weapon (Cone/Line AoE, arm-toggle-cancel targeting on the
# ability bar) + Draconic Flight (level-5 unlock, free-action 100-turn flight buff). Composition
# child-node split out of player.gd — see scripts/entities/CLAUDE.md's "Dragonborn" section.

var player: Player

# Arm-then-click targeting, same shape as Grip of the Forest's _hook_mode_active — but a 3rd press
# of the same slot cycles the AoE shape instead of firing immediately: 1st press arms (Cone,
# default), 2nd press (same slot) toggles Cone<->Line, 3rd press cancels. Esc/WASD movement/a click
# elsewhere in the world all cancel it exactly like every other armed player.gd targeting mode.
var breath_weapon_mode_active: bool = false
var breath_weapon_shape: String = "cone"  # "cone" or "line"

const BREATH_CONE_LENGTH: int = 2
const BREATH_LINE_LENGTH: int = 3

func activate_breath_weapon() -> void:
	if breath_weapon_mode_active:
		if breath_weapon_shape == "cone":
			breath_weapon_shape = "line"
			GameState.game_log("[color=lime]Breath Weapon: switched to a %d-tile Line. Click again to cancel.[/color]" % BREATH_LINE_LENGTH)
		else:
			breath_weapon_mode_active = false
			GameState.game_log("[color=gray]Breath Weapon cancelled.[/color]")
		return
	if player.stats.breath_weapon_uses_remaining <= 0 and not GameState.invincible:
		GameState.game_log("[color=gray]Breath Weapon: no uses remaining (long rest to recover).[/color]")
		return
	breath_weapon_mode_active = true
	breath_weapon_shape = "cone"
	GameState.game_log("[color=lime]Breath Weapon armed — a %d-tile Cone. Click a direction to fire, click again to switch to Line, once more to cancel.[/color]" % BREATH_CONE_LENGTH)

func cancel_breath_weapon() -> void:
	if breath_weapon_mode_active:
		breath_weapon_mode_active = false
		GameState.game_log("[color=gray]Breath Weapon cancelled.[/color]")

# Straight 1-wide line in the direction of aim_tile, snapped to the nearest of 8 directions
# (unlike SpellEffects.cone_tiles(), which uses a continuous aim angle) — mirrors the 5e "line"
# AoE shape being a fixed-width ray rather than a widening triangle. Stops at the first tile that
# breaks LOS from origin, same "wall casts a shadow" rule cone_tiles() already follows.
static func _line_tiles(origin: Vector2i, aim_tile: Vector2i, length: int, dungeon_floor: Node) -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	var delta: Vector2 = Vector2(aim_tile - origin)
	if delta.length() < 0.001:
		return out
	var step: float = PI / 4.0
	var snapped: float = round(delta.angle() / step) * step
	var dir_v := Vector2i(int(round(cos(snapped))), int(round(sin(snapped))))
	for i: int in range(1, length + 1):
		var p: Vector2i = origin + dir_v * i
		if dungeon_floor != null and not dungeon_floor.has_ranged_los(origin, p):
			break
		out.append(p)
	return out

# Resolves the armed breath weapon toward aim_tile (any world click confirms — aim_tile only
# supplies a direction, same convention as Burning Hands' cone). DEX save vs 8 + CON mod + prof
# bonus (5e 2024's own Breath Weapon DC), half damage on a success, floor-rounded down.
func resolve_breath_weapon(aim_tile: Vector2i) -> void:
	breath_weapon_mode_active = false
	var dungeon_floor: Node = player._dungeon_floor
	if dungeon_floor == null:
		return
	var stats: Stats = player.stats
	var origin: Vector2i = player.grid_pos
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	if not GameState.invincible:
		stats.breath_weapon_uses_remaining -= 1
	GameState._sync_ability_uses()
	var damage_type: String = Stats.DRAGONBORN_DAMAGE_TYPE[clampi(stats.race_variant, 0, Stats.DRAGONBORN_DAMAGE_TYPE.size() - 1)]
	var dice_count: int = stats.breath_weapon_dice_count()
	var rolls: Array[int] = Rng.roll_dice(dice_count, 10)
	var base_inst: Dictionary = CombatMath.build_damage_instance(rolls, 10, [], false, damage_type)
	var roll_total: int = int(base_inst["subtotal"])
	var dc: int = 8 + stats.con_modifier() + stats.proficiency_bonus

	var tiles: Array[Vector2i]
	var shape_label: String
	if breath_weapon_shape == "line":
		tiles = _line_tiles(origin, aim_tile, BREATH_LINE_LENGTH, dungeon_floor)
		shape_label = "a line of"
	else:
		tiles = SpellEffects.cone_tiles(origin, aim_tile, BREATH_CONE_LENGTH, dungeon_floor)
		shape_label = "a cone of"
	GameState.game_log("[color=orange]You unleash %s %s breath![/color]" % [shape_label, damage_type.to_lower()])

	var tile_set: Dictionary = {}
	for p: Vector2i in tiles:
		tile_set[p] = true
		if damage_type == "Fire":
			if dungeon_floor.get_tile_type(p) == DungeonData.TileType.GRASS:
				dungeon_floor.ignite_grass(p)
			else:
				dungeon_floor.ignite_flammable(p)

	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if not tile_set.has(e.grid_pos):
			continue
		e.on_disturbed(origin)
		var save: Dictionary = e.resist_check_detailed(dc, false, true, false, false, false)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		var dmg: int = roll_total if not save["pass"] else roll_total / 2
		var result: Dictionary = e.take_typed_damage(dmg, damage_type)
		var actual: int = result["actual"]
		var inst: Dictionary = base_inst.duplicate()
		inst["final"] = actual
		inst["resist_mul"] = result["mul"]
		var dmg_meta: String = CombatMath.encode_damage_instance(inst)
		e.update_hp_bar()
		dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color(damage_type))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is [url=%s]%s[/url] by the breath for [url=%s][color=yellow]%d[/color][/url] %s dmg.%s" % [
			e.display_name, save_meta, "caught" if not save["pass"] else "singed", dmg_meta, actual, damage_type, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

	dungeon_floor.update_fog(origin)
	player._handle_post_attack_turn()

# Draconic Flight (level 5+, 1/long rest, free action — does not cost a turn): see
# scripts/entities/CLAUDE.md's "Dragonborn" section for the movement-bypass mechanism this flag
# gates (chasm crossing, no grass trample, no trap trigger, immune to standing-on-fire damage).
func activate_draconic_flight() -> void:
	if player.stats.character_level < 5:
		return
	if player.stats.draconic_flight_used and not GameState.invincible:
		GameState.game_log("[color=gray]Draconic Flight: already used this long rest.[/color]")
		return
	if not GameState.invincible:
		player.stats.draconic_flight_used = true
	player.stats.draconic_flight_turns = 100
	GameState.player_status_changed.emit()
	GameState.game_log("[color=cyan]Your wings unfurl — you take to the air for up to 100 turns.[/color]")
