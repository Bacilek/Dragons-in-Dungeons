class_name PlayerOrc
extends Node

# Orc race ability: Adrenaline Rush. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md's "Orc" section. Relentless Endurance is a passive check in
# GameState.check_player_death() — no code lives here for it.

var player: Player

func activate_adrenaline_rush() -> void:
	if player.stats.adrenaline_rush_uses_remaining <= 0 and not GameState.invincible:
		return
	if not GameState.invincible:
		player.stats.adrenaline_rush_uses_remaining -= 1
	GameState._sync_ability_uses()
	player.stats.temp_hp = player.stats.proficiency_bonus
	GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
	player.stats.adrenaline_rush_move_free_pending = true
	GameState.game_log("[color=#e8622e]Adrenaline Rush: %d temp HP — your next move is free.[/color]" % player.stats.proficiency_bonus)
