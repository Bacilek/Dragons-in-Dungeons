class_name PlayerWarlock
extends Node

# Warlock-specific combat hooks. Composition child-node split out of player.gd, same convention as
# PlayerRangerTalents/PlayerTiefling — always instantiated regardless of class, so every call site
# just works for a non-Warlock too (hex_bonus_die() returns 0 whenever Stats.hex_target is unset).

var player: Player

# Hex's bonus damage die — a SECOND, independent Necrotic damage instance (Judgement Day/Hunter's
# Mark pattern, scripts/entities/CLAUDE.md's damage-stacking rule) on every landed attack against
# the hexed target. Unlike Hunter's Mark (weapon-only), this is wired into every ATTACK_ROLL damage
# site including cantrips/leveled spells too — Hex's own text says "weapon, cantrip, or spell
# attack" (see SpellEffects._resolve_hex()). Returns 0 if the target isn't currently hexed.
func hex_bonus_die(enemy: Enemy) -> int:
	if enemy == null or GameState.player_stats.hex_target != enemy:
		return 0
	return Rng.roll(6)
