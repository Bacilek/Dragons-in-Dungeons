class_name PlayerGoliath
extends Node

# Goliath race features. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md's "Goliath" section. Large Form and Giant Ancestry are the two
# grantable abilities (see GameState.give_race_starting_items()'s GOLIATH branch); Powerful Build
# (ADV to end Grappled) has no hook — no Grappled condition exists anywhere in this engine, same
# "granted but nothing to hook into" precedent as Elf's Fey Ancestry/Dwarf's Poisoned-check half.

var player: Player

# ── Large Form ───────────────────────────────────────────────────────────────────
# Wood-Elf-style duty cycle for the +1/3 movement bonus (see scripts/entities/CLAUDE.md's "Elf"
# section, "Wood Elf's 35 ft speed") — every 3rd real move while Large Form is active doesn't cost
# a turn. Not serialized — mid-floor combat bookkeeping, same tier as Player._speed_gate_accum.
var _large_form_move_counter: int = 0

## Rewind snapshot — see scripts/autoloads/rewind_manager.gd.
func get_rewind_fields() -> Dictionary:
	return {
		"large_form_move_counter": _large_form_move_counter,
		"cloud_teleport_mode_active": cloud_teleport_mode_active,
	}

func set_rewind_fields(d: Dictionary) -> void:
	_large_form_move_counter = int(d.get("large_form_move_counter", 0))
	cloud_teleport_mode_active = bool(d.get("cloud_teleport_mode_active", false))

func activate_large_form() -> void:
	if player.stats.character_level < 5:
		return
	# Second press while already active ends it early.
	if player.stats.large_form_turns > 0:
		end_large_form()
		return
	if player.stats.large_form_used and not GameState.invincible:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not _footprint_free(player.grid_pos):
		GameState.game_log("[color=gray]Large Form: not enough open space here.[/color]")
		return
	if not GameState.invincible:
		player.stats.large_form_used = true
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	player.stats.large_form_turns = 100
	player.size = Vector2i(2, 2)
	_large_form_move_counter = 0
	GameState.player_status_changed.emit()
	GameState.game_log("[color=cyan]You swell to giant size — Large Form active for up to 100 turns.[/color]")
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)

func end_large_form() -> void:
	if player.size == Vector2i.ONE:
		return
	player.stats.large_form_turns = 0
	player.size = Vector2i.ONE
	GameState.game_log("[color=gray]Large Form fades — you return to normal size.[/color]")
	GameState.player_status_changed.emit()
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)

# ADV on the one player-side STR check that exists today (Web escape) — see
# PlayerThiefTools/player.gd's _attempt_web_escape().
func has_large_form_str_adv() -> bool:
	return player.stats.large_form_turns > 0

# Called from player.gd's per-real-turn "first move free" gate, alongside Expeditious Retreat/
# Longstrider/Wood Elf's own counters — a duty-cycle +1/3 speed bonus (every 3rd real move is
# free), sharing the same CombatMath.tick_duty_cycle() accumulator math Player._consume_duty_cycle()
# uses for Wood Elf/Longstrider/Exhaustion (kept as its own local counter rather than folded into
# Player._speed_gate_accum, since Large Form is a single implementation, not a duplicate).
func consume_large_form_free_move() -> bool:
	if player.stats.large_form_turns <= 0:
		return false
	var r: Dictionary = CombatMath.tick_duty_cycle(_large_form_move_counter, 1, 3)
	_large_form_move_counter = r["accum"]
	return r["fires"] > 0

func _footprint_free(top_left: Vector2i) -> bool:
	if player._dungeon_floor == null:
		return false
	for dy: int in 2:
		for dx: int in 2:
			var t: Vector2i = top_left + Vector2i(dx, dy)
			if not player._dungeon_floor.is_walkable(t):
				return false
			if player._dungeon_floor.get_enemy_at(t) != null:
				return false
	return true

# Called from player.gd's _try_move() before the normal single-tile walkability check — the 3 NEW
# tiles a 2x2 move into `target` would cover (excluding tiles already part of the CURRENT
# footprint, which are handled by the existing bump-attack/walkability logic on the leading tile).
# Returns true (blocks the move) if any of those 3 tiles isn't free.
func blocks_large_form_move(target: Vector2i) -> bool:
	if player._dungeon_floor == null:
		return true
	for dy: int in 2:
		for dx: int in 2:
			var t: Vector2i = target + Vector2i(dx, dy)
			if player.occupies(t):
				continue
			if not player._dungeon_floor.is_walkable(t):
				return true
			var e: Enemy = player._dungeon_floor.get_enemy_at(t)
			if e != null and not e.is_hidden_from_player():
				return true
	return false

# ── Giant Ancestry ───────────────────────────────────────────────────────────────
var cloud_teleport_mode_active: bool = false
const CLOUD_TELEPORT_RANGE: int = 3

func activate_giant_ancestry() -> void:
	if player.stats.giant_ancestry_uses_remaining <= 0 and not GameState.invincible:
		return
	match player.stats.race_variant:
		Stats.GiantAncestry.CLOUD:
			cloud_teleport_mode_active = true
			GameState.game_log("[color=cyan]Cloud Giant: click a tile within %d tiles to teleport there.[/color]" % CLOUD_TELEPORT_RANGE)
		Stats.GiantAncestry.STONE:
			# Toggle only — the 1d12+CON reduction is unknown until it actually rolls, at the
			# moment damage lands (GameState.take_damage_raw()), not here at arm time. Cancelling
			# manually loses the buff for free (no charge spent) — same "arm now, spend the charge
			# only when it actually triggers" shape as Fire/Frost/Storm's shared toggle below.
			player.stats.giant_ancestry_armed = not player.stats.giant_ancestry_armed
			if player.stats.giant_ancestry_armed:
				GameState.game_log("[color=cyan]Stone's Endurance braces — your next hit taken will be reduced by 1d12 + CON (rolled when it lands).[/color]")
			else:
				GameState.game_log("[color=gray]Stone's Endurance stood down.[/color]")
		Stats.GiantAncestry.FIRE, Stats.GiantAncestry.FROST, Stats.GiantAncestry.HILL, Stats.GiantAncestry.STORM:
			player.stats.giant_ancestry_armed = not player.stats.giant_ancestry_armed
			if player.stats.giant_ancestry_armed:
				GameState.game_log("[color=cyan]%s is armed.[/color]" % GameState._giant_ancestry_name(player.stats.race_variant))
			else:
				GameState.game_log("[color=gray]%s stood down.[/color]" % GameState._giant_ancestry_name(player.stats.race_variant))

# Called from player.gd._bump_attack() right after the primary hit lands (actual > 0). Returns
# "Fire"/"Cold" for Fire/Frost Giant (a damage instance, merged onto the SAME chat line as the
# primary hit — see each call site's own gol_actual/gol_inst block) or "Prone" for Hill Giant (no
# damage of its own — the caller logs a separate "Hill's Tumble knocks X Prone." line, but only
# AFTER its own primary-hit log line has already been printed, direct owner request: this ability
# is a bonus/reaction to an attack, not part of narrating the attack itself, so it must never read
# as having happened before the hit that triggered it). Applies Hill's Prone status right here
# (silent — no log, no charge spend yet) so the condition is live immediately; the charge itself is
# only spent once the caller actually logs the effect — every call site does this via
# finish_giant_ancestry_bonus_damage(), called AFTER its own damage instance (Fire/Cold) or flavor
# line (Prone) is resolved, same "effect first, spend after" order Stone's Endurance/Storm's
# Thunder both use. A miss never reaches this function at all, so a charge is only ever spent on a
# landed hit, matching "misses don't spend charges".
func consume_giant_ancestry_on_hit(enemy: Enemy) -> String:
	if player.stats.character_race != Stats.CharacterRace.GOLIATH or not player.stats.giant_ancestry_armed:
		return ""
	match player.stats.race_variant:
		Stats.GiantAncestry.FIRE:
			return "Fire"
		Stats.GiantAncestry.FROST:
			enemy.apply_status("slowed", 3)
			return "Cold"
		Stats.GiantAncestry.HILL:
			# "Large or smaller" — every enemy in this game today is Medium or Large (2x2, area
			# multiplier 4) at most, so this is unconditional in practice; the size check is kept
			# for correctness against any future Huge+ enemy.
			if enemy.size.x * enemy.size.y <= 4:
				enemy.apply_status("prone", 1)
				return "Prone"
	return ""

func _spend_giant_ancestry_charge() -> void:
	player.stats.giant_ancestry_armed = false
	if not GameState.invincible:
		player.stats.giant_ancestry_uses_remaining -= 1
	GameState._sync_ability_uses()

## Called by player.gd once a Fire/Frost bonus damage instance has actually been dealt (damage
## rolled, applied via Enemy.take_typed_damage(), HP bar updated, floater shown) — only then is the
## charge spent and the toggle cleared, matching Hill/Stone/Storm's own "resolve the effect, THEN
## spend" order. No-op for any other race/variant (never called otherwise).
func finish_giant_ancestry_bonus_damage() -> void:
	_spend_giant_ancestry_charge()

func resolve_cloud_teleport(clicked: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	if player.stats.giant_ancestry_uses_remaining <= 0 and not GameState.invincible:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	var dist: int = maxi(absi(clicked.x - player.grid_pos.x), absi(clicked.y - player.grid_pos.y))
	if dist > CLOUD_TELEPORT_RANGE:
		GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % CLOUD_TELEPORT_RANGE)
		return
	if not player._dungeon_floor.is_tile_visible(clicked):
		GameState.game_log("[color=gray]You can't see that space.[/color]")
		return
	if not player._dungeon_floor.is_walkable(clicked) or player._dungeon_floor.get_enemy_at(clicked) != null:
		GameState.game_log("[color=gray]That space is occupied.[/color]")
		return
	if player.size != Vector2i.ONE and blocks_large_form_move(clicked):
		GameState.game_log("[color=gray]Not enough room there for your Large Form.[/color]")
		return
	if not GameState.invincible:
		player.stats.giant_ancestry_uses_remaining -= 1
		GameState.bonus_action_used = true
	GameState._sync_ability_uses()
	GameState.ability_bar_changed.emit()
	var prev: Vector2i = player.grid_pos
	player.set_grid_pos(clicked)
	GameState.game_log("[color=cyan]Cloud's Jaunt: you blink through the air.[/color]")
	if player._dungeon_floor.has_door_at(prev):
		player._dungeon_floor.close_door(prev)
	player._dungeon_floor.update_fog(player.grid_pos)
