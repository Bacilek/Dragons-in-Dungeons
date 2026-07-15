class_name PlayerSpellcasting
extends Node

# Player-side casting UX — composition child-node split out of player.gd. Cantrips (level 0)
# mirror the Grip-of-the-Forest hook-mode pattern (single-target, no picker, no preview: arm on
# ability activation, LMB on a valid target resolves the cast). Leveled spells
# (docs/architecture/leveled-spells-and-slots-plan.md) extend this to SELF/TILE targets and slot
# consumption, but deliberately skip the framework doc's upcast slot-level picker — always casts
# at the lowest available slot level (plan §2/§9).

var player: Player
var spell_targeting_active: bool = false
var _armed_spell_id: String = ""
# Scroll-cast state (Item.scroll_spell_id — see game_state.gd's SCROLL branch/CLAUDE.md).
# Reuses spell_targeting_active/_armed_spell_id for the actual targeting/AoE-preview plumbing;
# these two just remember it's a scroll so try_cast_at()/_cast_self() skip the slot-pool check/
# consume and instead consume the scroll item itself once the cast actually resolves.
var _casting_from_scroll: bool = false
var _armed_scroll_item: Item = null

func begin_cast(spell_id: String) -> void:
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if spell.level > 0:
		var caster: SpellcasterState = player.stats.caster
		if caster == null or caster.slot_pool == null or not caster.slot_pool.can_cast(spell):
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return
	match spell.target_kind:
		Spell.TargetKind.SELF:
			_cast_self(spell)
			return
		_:
			_armed_spell_id = spell_id
			spell_targeting_active = true
			var range_hint: String = "your full field of view" if spell.range_is_fov else "%d tiles" % spell.range_tiles
			GameState.game_log("[color=lime]%s — click a target within %s. [Esc] to cancel.[/color]" % [spell.spell_name, range_hint])

## Entry point for reading a Scroll of <Spell> (game_state.gd's player_scroll_primed signal).
## No spell-slot check (a scroll is self-contained) — always casts at the spell's own base level.
func on_scroll_primed(item: Item) -> void:
	var spell: Spell = SpellDb.get_spell(item.scroll_spell_id)
	if spell == null:
		return
	if spell.target_kind == Spell.TargetKind.SELF:
		_consume_scroll(item)
		await _cast_self(spell, true)
		return
	_armed_spell_id = item.scroll_spell_id
	_armed_scroll_item = item
	_casting_from_scroll = true
	spell_targeting_active = true
	var range_hint: String = "your full field of view" if spell.range_is_fov else "%d tiles" % spell.range_tiles
	GameState.game_log("[color=lime]%s (Scroll) — click a target within %s. [Esc] to cancel.[/color]" % [spell.spell_name, range_hint])

func _consume_scroll(item: Item) -> void:
	if not GameState.invincible:
		GameState.consume_one(item)

func cancel() -> void:
	spell_targeting_active = false
	_armed_spell_id = ""
	_casting_from_scroll = false
	_armed_scroll_item = null

## Currently armed spell while targeting is active, or null — lets player.gd's per-frame AoE
## preview (dungeon_floor.gd's show_aoe_preview()/hide_aoe_preview()) read the spell's shape
## without reaching into the private _armed_spell_id field directly.
func get_armed_spell() -> Spell:
	if not spell_targeting_active:
		return null
	return SpellDb.get_spell(_armed_spell_id)

func _cast_level_for(spell: Spell) -> int:
	if spell.level == 0:
		return 0
	var caster: SpellcasterState = player.stats.caster
	return caster.slot_pool.lowest_available_level(spell)

func _cast_self(spell: Spell, from_scroll: bool = false) -> void:
	var lvl: int = spell.level if from_scroll else _cast_level_for(spell)
	if not from_scroll and spell.level > 0 and lvl == -1:
		GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
		return
	await SpellEffects.cast_leveled_self(player, spell, lvl, player._dungeon_floor, from_scroll)

# Called from player.gd's LMB dispatch when spell_targeting_active is true. Consumes the armed
# state regardless of outcome (same one-shot pattern as Grip of the Forest's hook mode).
# Range check is Chebyshev (diagonal counts as 1, not the ranged-weapon-style Euclidean/FOV-capped
# check) — a diagonal-adjacent target is in range of a 1-tile touch spell like Shocking Grasp,
# same convention as melee reach elsewhere. Range itself is not additionally clamped to the live
# FOV — visibility (has_ranged_los / fog) already governs what's actually clickable, so a spell
# whose range exceeds the player's FOV radius simply can't reach further than they can currently
# see, without a second redundant cap.
## Effective range in tiles for the range check below — spell.range_tiles normally, or the
## caster's LIVE FOV radius when spell.range_is_fov is set (Magic Missile — some characters see
## further than the base FOV_RADIUS, e.g. Wild Heart Eagle's +1, so this must be read live, never
## a fixed constant).
func _effective_range(spell: Spell) -> int:
	if spell.range_is_fov:
		# Matches dungeon_floor.gd's own live FOV radius formula exactly (update_fog()/
		# _decide_action() visibility checks) — darkvision (Orc/Dwarf) and Wild Heart Eagle's
		# fov_radius_bonus both genuinely extend how far a character can see, and therefore how
		# far a full-FOV-range spell can reach.
		return DungeonFloor.FOV_RADIUS + GameState.fov_radius_bonus + GameState.player_stats.darkvision_bonus
	return spell.range_tiles

## Direct one-motion cast for the Special quick-cast slot (Ctrl+click in player.gd, mirroring
## Shift+ranged's single-motion resolve — no separate arm-then-click step like the ability-bar's
## begin_cast()/try_cast_at() pair). SELF-target spells (Shield) ignore `clicked` entirely and
## self-cast immediately, same as begin_cast()'s own SELF branch.
func cast_direct(spell_id: String, clicked: Vector2i) -> void:
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if spell.level > 0:
		var caster: SpellcasterState = player.stats.caster
		if caster == null or caster.slot_pool == null or not caster.slot_pool.can_cast(spell):
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return
	if spell.target_kind == Spell.TargetKind.SELF:
		_cast_self(spell)
		return
	_armed_spell_id = spell_id
	try_cast_at(clicked)

func try_cast_at(clicked: Vector2i) -> void:
	var spell_id: String = _armed_spell_id
	var from_scroll: bool = _casting_from_scroll
	var scroll_item: Item = _armed_scroll_item
	spell_targeting_active = false
	_armed_spell_id = ""
	_casting_from_scroll = false
	_armed_scroll_item = null
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null or player._dungeon_floor == null:
		return
	var d: Vector2i = clicked - player.grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var eff_range: int = _effective_range(spell)
	if dist_cheb > eff_range:
		GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % eff_range)
		return
	if not player._dungeon_floor.has_ranged_los(player.grid_pos, clicked):
		GameState.game_log("[color=gray]No clear line to target.[/color]")
		return

	var lvl: int = spell.level
	if not from_scroll and spell.level > 0:
		lvl = _cast_level_for(spell)
		if lvl == -1:
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return

	# A scroll is spent the instant its cast actually resolves (range/LOS already checked above) —
	# same "consumed even on a miss" convention as a real D&D scroll.
	if from_scroll:
		_consume_scroll(scroll_item)

	if spell.level == 0:
		var target0: Enemy = player._dungeon_floor.get_enemy_at(clicked)
		if target0 == null:
			await SpellEffects.cast_spell_at_tile(player, spell, clicked, player._dungeon_floor)
		else:
			await SpellEffects.cast_spell(player, spell, target0, player._dungeon_floor, from_scroll)
		return

	match spell.target_kind:
		Spell.TargetKind.TILE:
			await SpellEffects.cast_leveled_at_tile(player, spell, lvl, clicked, player._dungeon_floor, from_scroll)
		Spell.TargetKind.ENEMY:
			var target: Enemy = player._dungeon_floor.get_enemy_at(clicked)
			if target == null:
				GameState.game_log("[color=gray]%s needs a target.[/color]" % spell.spell_name)
			else:
				await SpellEffects.cast_leveled_at_enemy(player, spell, lvl, target, player._dungeon_floor, from_scroll)
		_:
			pass
