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
	var range_shown: int = mini(spell.range_tiles, DungeonFloor.FOV_RADIUS)
	GameState.game_log("[color=lime]%s — click a target within %d tiles. [Esc] to cancel.[/color]" % [spell.spell_name, range_shown])

func cancel() -> void:
	spell_targeting_active = false
	_armed_spell_id = ""

# Called from player.gd's LMB dispatch when spell_targeting_active is true. Consumes the armed
# state regardless of outcome (same one-shot pattern as Grip of the Forest's hook mode).
func try_cast_at(clicked: Vector2i) -> void:
	var spell_id: String = _armed_spell_id
	spell_targeting_active = false
	_armed_spell_id = ""
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null or player._dungeon_floor == null:
		return
	var target: Enemy = player._dungeon_floor.get_enemy_at(clicked)
	if target == null:
		GameState.game_log("[color=gray]%s: no target there.[/color]" % spell.spell_name)
		return
	var d: Vector2i = clicked - player.grid_pos
	var dist_sq: int = d.x * d.x + d.y * d.y
	var fov_r: int = DungeonFloor.FOV_RADIUS
	if dist_sq > spell.range_tiles * spell.range_tiles or dist_sq > fov_r * fov_r:
		GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % mini(spell.range_tiles, fov_r))
		return
	if not player._dungeon_floor.has_ranged_los(player.grid_pos, clicked):
		GameState.game_log("[color=gray]No clear line to target.[/color]")
		return
	await SpellEffects.cast_spell(player, spell, target, player._dungeon_floor)
