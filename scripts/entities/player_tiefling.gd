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

## Whether Hellish Rebuke can actually fuel a reaction right now — a free Fiendish Legacy cast
## still remaining this long rest, OR (Wizard/Ranger casters only) a real 1st-level spell slot.
## Mirrors PlayerSpellcasting.begin_cast()'s own slot-availability gate — arming with neither would
## let the toggle sit lit forever with no way to ever actually fire (trigger_hellish_rebuke() would
## just log "no charge left" every time it tried).
func can_activate_hellish_rebuke() -> bool:
	if GameState.invincible:
		return true
	if player.stats.is_tiefling_legacy_free_cast_available("hellish_rebuke"):
		return true
	var caster: SpellcasterState = player.stats.caster
	return caster != null and caster.slot_pool != null and caster.slot_pool.remaining.get(1, 0) > 0

func activate_hellish_rebuke() -> void:
	if not player.stats.hellish_rebuke_armed and not can_activate_hellish_rebuke():
		GameState.game_log("[color=gray]Hellish Rebuke has no charge left to fuel it.[/color]")
		return
	player.stats.hellish_rebuke_armed = not player.stats.hellish_rebuke_armed
	if player.stats.hellish_rebuke_armed:
		GameState.game_log("[color=cyan]Hellish Rebuke is armed — the next enemy you can see that hurts you suffers for it.[/color]")
	else:
		GameState.game_log("[color=gray]Hellish Rebuke stood down.[/color]")
