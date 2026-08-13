class_name PlayerHuman
extends Node

# Human race ability: Heroic Inspiration. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md's "Human" section. Skillful (bonus ability-check proficiency) and
# Resourceful's long-rest refill are handled entirely by Stats.apply_race_defaults()/
# GameState.long_rest() — no code lives here for either.

var player: Player

func activate_heroic_inspiration() -> void:
	if not GameState.player_stats.heroic_inspiration_available and not GameState.invincible:
		return
	if not GameState.invincible:
		GameState.player_stats.heroic_inspiration_available = false
	GameState._sync_ability_uses()
	GameState.heroic_inspiration_pending = true
	GameState.game_log("[color=#e8b923]Heroic Inspiration: your next roll is guaranteed to succeed![/color]")
