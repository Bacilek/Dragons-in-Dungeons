class_name PlayerDwarf
extends Node

# Dwarf race ability: Stonecunning (Tremorsense). Composition child-node split out of player.gd —
# see scripts/entities/CLAUDE.md's "Dwarf" section. Dwarven Resilience (Poison resistance) is a
# passive Stats.damage_resistances entry (apply_race_defaults()) — no code lives here for it.

var player: Player

func activate_stonecunning() -> void:
	if player.stats.stonecunning_uses_remaining <= 0 and not GameState.invincible:
		return
	if not GameState.invincible:
		player.stats.stonecunning_uses_remaining -= 1
	GameState._sync_ability_uses()
	player.stats.tremorsense_turns = 100
	GameState.player_status_changed.emit()
	GameState.game_log("[color=cyan]You press a hand to the stone — Tremorsense stirs for up to 100 turns.[/color]")
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
