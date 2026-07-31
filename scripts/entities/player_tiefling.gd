class_name PlayerTiefling
extends Node

# Tiefling race features requiring dedicated reactive logic. Composition child-node split out of
# player.gd, same pattern as PlayerGoliath. Hellish Rebuke (Infernal Fiendish Legacy, granted at
# character level 3 — scripts/entities/CLAUDE.md's "Tiefling" section) is implemented as a
# toggle-armed REACTION instead of a normal on-demand cast — RAW casts it as a reaction to being
# hit, and this engine has no reaction-casting framework. Arming it here mirrors Storm Giant
# Ancestry's own armed-reaction toggle (player_goliath.gd's activate_giant_ancestry()); the actual
# cast resolves from enemy.gd._attack_player() via SpellEffects.trigger_hellish_rebuke() the moment
# a qualifying enemy hurts the player.

var player: Player

func activate_hellish_rebuke() -> void:
	player.stats.hellish_rebuke_armed = not player.stats.hellish_rebuke_armed
	if player.stats.hellish_rebuke_armed:
		GameState.game_log("[color=cyan]Hellish Rebuke is armed — the next enemy you can see that hurts you suffers for it.[/color]")
	else:
		GameState.game_log("[color=gray]Hellish Rebuke stood down.[/color]")
