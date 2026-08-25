class_name PlayerOrc
extends Node

# Orc race ability: Adrenaline Rush. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md's "Orc" section. Relentless Endurance is a passive check in
# GameState.check_player_death() — no code lives here for it.

var player: Player

# Arm-then-click targeting (same family as Cloud Giant's Jaunt) — activating grants temp HP and
# arms a one-tile free dash instead of the old "your next WASD move doesn't cost a turn" flag.
var dash_mode_active: bool = false
const DASH_RANGE: int = 1

func get_rewind_fields() -> Dictionary:
	return {"dash_mode_active": dash_mode_active}

func set_rewind_fields(d: Dictionary) -> void:
	dash_mode_active = bool(d.get("dash_mode_active", false))

func activate_adrenaline_rush() -> void:
	if player.stats.adrenaline_rush_uses_remaining <= 0 and not GameState.invincible:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.invincible:
		player.stats.adrenaline_rush_uses_remaining -= 1
		GameState.bonus_action_used = true
	GameState._sync_ability_uses()
	GameState.ability_bar_changed.emit()
	player.stats.temp_hp = player.stats.proficiency_bonus
	GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
	dash_mode_active = true
	GameState.game_log("[color=#e8622e]Adrenaline Rush: %d temp HP — click an adjacent tile to dash there for free.[/color]" % player.stats.proficiency_bonus)

func cancel() -> void:
	dash_mode_active = false

## Resolves the armed one-tile dash — a genuinely free action (no turn cost, no
## TurnManager envelope at all, matching Cloud's Jaunt), just a normal move-animation slide onto
## an adjacent tile instead of Cloud Giant's instant blink, so it visibly reads as "one free move."
func resolve_dash(clicked: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	if clicked == player.grid_pos:
		return
	var d: Vector2i = clicked - player.grid_pos
	if maxi(absi(d.x), absi(d.y)) > DASH_RANGE:
		GameState.game_log("[color=gray]Adrenaline Rush: that tile isn't adjacent.[/color]")
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
	await player.move_to(clicked)
	if player._dungeon_floor.has_door_at(prev):
		player._dungeon_floor.close_door(prev)
	player._dungeon_floor.update_fog(player.grid_pos)
	GameState.game_log("[color=#e8622e]Adrenaline Rush: you dash forward.[/color]")
