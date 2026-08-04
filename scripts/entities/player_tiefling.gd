class_name PlayerTiefling
extends Node

# Tiefling race features requiring dedicated reactive logic. Composition child-node split out of
# player.gd, same pattern as PlayerGoliath. Hellish Rebuke (a real Warlock spell — see scripts/
# entities/CLAUDE.md's "Warlock class" section — and still the Infernal Tiefling Fiendish Legacy's
# free grant at character level 3, "Tiefling" section) is implemented as a toggle-armed REACTION
# instead of a normal on-demand cast — RAW casts it as a reaction to being hit, and this engine has
# no reaction-casting framework. Arming it here mirrors Storm Giant Ancestry's own armed-reaction
# toggle (player_goliath.gd's activate_giant_ancestry()); the actual cast resolves from
# enemy.gd._attack_player() via SpellEffects.trigger_hellish_rebuke() the moment a qualifying enemy
# hurts the player. Despite the class name, this module is class-agnostic (it only ever reads
# `player.stats` directly) — a Warlock who's simply learned the spell normally routes through the
# exact same activate_hellish_rebuke()/can_activate_hellish_rebuke() pair as a Tiefling.

var player: Player

## Whether Hellish Rebuke can actually fuel a reaction right now — a free Fiendish Legacy cast
## still remaining this long rest (Tiefling only), OR any caster's own slot_pool actually being
## able to cast it. Mirrors PlayerSpellcasting.begin_cast()'s own slot-availability gate — arming
## with neither would let the toggle sit lit forever with no way to ever actually fire
## (trigger_hellish_rebuke() would just log "no charge left" every time it tried).
## Uses slot_pool.can_cast(spell) rather than a hardcoded remaining.get(1, 0) check — a Warlock's
## PactSlotPool only ever has ONE key, the CURRENT pact slot level (which can be well above 1 once
## past character level 2), so the old hardcoded "does slot level 1 have a charge" check would
## silently read as "no charge" forever for any Warlock past their first pact-level bump.
func can_activate_hellish_rebuke() -> bool:
	if GameState.invincible:
		return true
	if player.stats.is_tiefling_legacy_free_cast_available("hellish_rebuke"):
		return true
	var caster: SpellcasterState = player.stats.caster
	if caster == null or caster.slot_pool == null:
		return false
	return caster.slot_pool.can_cast(SpellDb.get_spell("hellish_rebuke"))

func activate_hellish_rebuke() -> void:
	if not player.stats.hellish_rebuke_armed and not can_activate_hellish_rebuke():
		GameState.game_log("[color=gray]Hellish Rebuke has no charge left to fuel it.[/color]")
		return
	player.stats.hellish_rebuke_armed = not player.stats.hellish_rebuke_armed
	if player.stats.hellish_rebuke_armed:
		GameState.game_log("[color=cyan]Hellish Rebuke is armed — the next enemy you can see that hurts you suffers for it.[/color]")
	else:
		GameState.game_log("[color=gray]Hellish Rebuke stood down.[/color]")
