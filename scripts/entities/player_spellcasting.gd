class_name PlayerSpellcasting
extends Node

# Player-side cantrip casting UX — composition child-node split out of player.gd, mirroring the
# Grip-of-the-Forest hook-mode pattern (single-target, no picker, no preview: arm on ability
# activation, LMB on a valid target resolves the cast). See scripts/entities/CLAUDE.md.

var player: Player
var spell_targeting_active: bool = false
var _armed_spell_id: String = ""

func begin_cast(spell_id: String) -> void:
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	_armed_spell_id = spell_id
	spell_targeting_active = true
	GameState.game_log("[color=lime]%s — click a target within %d tiles. [Esc] to cancel.[/color]" % [spell.spell_name, spell.range_tiles])

func cancel() -> void:
	spell_targeting_active = false
	_armed_spell_id = ""

# Called from player.gd's LMB dispatch when spell_targeting_active is true. Consumes the armed
# state regardless of outcome (same one-shot pattern as Grip of the Forest's hook mode).
# Range check is Chebyshev (diagonal counts as 1, not the ranged-weapon-style Euclidean/FOV-capped
# check) — a diagonal-adjacent target is in range of a 1-tile touch spell like Shocking Grasp,
# same convention as melee reach elsewhere. Range itself is not additionally clamped to the live
# FOV — visibility (has_ranged_los / fog) already governs what's actually clickable, so a spell
# whose range exceeds the player's FOV radius simply can't reach further than they can currently
# see, without a second redundant cap.
func try_cast_at(clicked: Vector2i) -> void:
	var spell_id: String = _armed_spell_id
	spell_targeting_active = false
	_armed_spell_id = ""
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null or player._dungeon_floor == null:
		return
	var d: Vector2i = clicked - player.grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	if dist_cheb > spell.range_tiles:
		GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % spell.range_tiles)
		return
	if not player._dungeon_floor.has_ranged_los(player.grid_pos, clicked):
		GameState.game_log("[color=gray]No clear line to target.[/color]")
		return
	var target: Enemy = player._dungeon_floor.get_enemy_at(clicked)
	if target == null:
		await SpellEffects.cast_spell_at_tile(player, spell, clicked, player._dungeon_floor)
	else:
		await SpellEffects.cast_spell(player, spell, target, player._dungeon_floor)
