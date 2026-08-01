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

# Multi-target/multi-beam collection state — shared by Magic Missile (Spell.effect_id ==
# "magic_missile", exactly 3 AUTO_HIT darts, barrel/door valid) and Eldritch Blast
# (Spell.multi_beam_scaling, 1-4 ATTACK_ROLL beams depending on character level, enemies only).
# Both are intercepted before the normal single-click ENEMY flow
# (begin_cast()/cast_direct()/on_scroll_primed()) and instead collect one target pick per
# instance (repeats allowed — see try_cast_at()'s _mm_active branch and
# SpellEffects.cast_magic_missile()/cast_multi_beam_cantrip()). Esc (cancel()) at any point during
# collection refunds nothing because nothing was ever spent yet — the slot/turn are only consumed
# once every instance is assigned. See scripts/entities/CLAUDE.md's Magic Missile/Eldritch Blast
# entries.
var _mm_active: bool = false
var _mm_targets: Array[Dictionary] = []
var _mm_count: int = 3
var _mm_enemies_only: bool = false

# A Shield (Item.is_shield) in the Off-hand blocks all spellcasting while equipped — 5e's
# "shield blocks somatic components" rule, applied uniformly regardless of caster hand.
func _shield_blocks_casting() -> bool:
	var hand2: Item = GameState.equipment.get("hand2") as Item
	return hand2 != null and hand2.is_shield

## Whether `spell` needs the multi-target click-collection flow instead of a normal single click.
func _uses_multi_target_flow(spell: Spell) -> bool:
	return spell.effect_id == "magic_missile" or spell.multi_beam_scaling

## How many target picks to collect — Magic Missile is always exactly 3 darts; a multi_beam_scaling
## cantrip (Eldritch Blast) scales with character level via the same tier table cantrip_tier_scaling
## damage dice use, just applied to beam COUNT instead of dice count (1/2/3/4 at levels 1/5/11/17).
func _multi_target_beam_count(spell: Spell) -> int:
	if spell.effect_id == "magic_missile":
		return 3
	if spell.multi_beam_scaling:
		return SpellEffects.cantrip_tier(player.stats.character_level)
	return 1

func begin_cast(spell_id: String) -> void:
	if _shield_blocks_casting():
		GameState.game_log("[color=gray]You can't cast with a Shield equipped.[/color]")
		return
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	# Ritual casting (Detect Magic): free of the slot-availability gate entirely, as long as no
	# enemy is currently hunting the caster — see Spell.is_ritual's own comment.
	var ritual_free: bool = spell.is_ritual and not player.is_being_pursued()
	if spell.level > 0 and not GameState.invincible and not ritual_free and not player.stats.is_lineage_free_cast_available(spell_id) and not GameState.warlock_invocation_free_cast(spell_id):
		var caster: SpellcasterState = player.stats.caster
		if caster == null or caster.slot_pool == null or not caster.slot_pool.can_cast(spell):
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return
	# Gnomish Lineage cantrips have no spell-slot fallback at all — proficiency_bonus free casts
	# per long rest IS the entire resource (see Stats.gnome_lineage_free_casts_remaining).
	if spell_id in player.stats.gnome_lineage_spell_ids and not GameState.invincible and not player.stats.is_gnome_lineage_free_cast_available(spell_id):
		GameState.game_log("[color=gray]You have no uses of %s left this long rest.[/color]" % spell.spell_name)
		return
	if _uses_multi_target_flow(spell):
		_begin_multi_target(spell_id, false, null)
		return

	match spell.target_kind:
		Spell.TargetKind.SELF:
			if spell.range_tiles <= 0:
				# Instant self-buff (Shield) — no targeting step, resolves on activation.
				_cast_self(spell)
				return
			# Touch-range self buff (Mage Armor) — activation only ARMS it; a follow-up click
			# ANYWHERE resolves the cast on yourself (the only valid target — see try_cast_at()),
			# same "arm then confirm" flow every other spell uses. Prevents an accidental
			# hotkey/ability-bar press from instantly burning a slot on a buff the player didn't
			# mean to cast yet. Also resolvable via a quick double-press of the same hotkey/slot
			# (see player.gd._use_ability_slot()) or Alt+click from the Special slot.
			_armed_spell_id = spell_id
			spell_targeting_active = true
			GameState.game_log("[color=lime]%s (touch) — click anywhere to cast on yourself, or press the slot again. [Esc] to cancel.[/color]" % spell.spell_name)
			return
		_:
			_armed_spell_id = spell_id
			spell_targeting_active = true
			var range_hint: String = "your full field of view" if spell.range_is_fov else "%d tiles" % spell.range_tiles
			GameState.game_log("[color=lime]%s — click a target within %s. [Esc] to cancel.[/color]" % [spell.spell_name, range_hint])

## Entry point for reading a Scroll of <Spell> (game_state.gd's player_scroll_primed signal).
## No spell-slot check (a scroll is self-contained) — always casts at the spell's own base level.
func on_scroll_primed(item: Item) -> void:
	if _shield_blocks_casting():
		GameState.game_log("[color=gray]You can't cast with a Shield equipped.[/color]")
		return
	var spell: Spell = SpellDb.get_spell(item.scroll_spell_id)
	if spell == null:
		return
	if spell.target_kind == Spell.TargetKind.SELF and spell.range_tiles <= 0:
		_consume_scroll(item)
		await _cast_self(spell, true)
		return
	if _uses_multi_target_flow(spell):
		_begin_multi_target(item.scroll_spell_id, true, item)
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
	_mm_active = false
	_mm_targets = []
	_mm_count = 3
	_mm_enemies_only = false

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
	if GameState.invincible:
		return spell.level  # God Mode: never needs (or spends) a slot — see _consume_slot()
	# Ritual casting (Detect Magic) — free, no slot needed, as long as no enemy is currently
	# hunting the caster. See Spell.is_ritual's own comment.
	if spell.is_ritual and not player.is_being_pursued():
		return spell.level
	# Elf lineage spell's free-per-long-rest cast — works even for a non-caster class (no
	# SpellcasterState/slot_pool to read at all), see Stats.is_lineage_free_cast_available().
	if player.stats.is_lineage_free_cast_available(spell.spell_id):
		return spell.level
	# Warlock Invocation at-will free cast (Armor of Shadows/Fiendish Vigor/Eldritch Sight/
	# Ascendant Step) — genuinely unlimited, no counter to check.
	if GameState.warlock_invocation_free_cast(spell.spell_id):
		return spell.level
	var caster: SpellcasterState = player.stats.caster
	if caster == null or caster.slot_pool == null:
		return -1
	return caster.slot_pool.available_level(spell)

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
## caster's LIVE FOV radius when spell.range_is_fov is set (no current spell sets this — Magic
## Missile used to, but was switched to a plain fixed 12-tile range + Spell.bypasses_los per direct
## owner correction, see scripts/entities/CLAUDE.md's Magic Missile entry — kept as a general
## mechanism for any future spell that wants "reach = however far you can currently see", e.g. Wild
## Heart Eagle's +1 FOV radius).
func _effective_range(spell: Spell) -> int:
	# Blinded: every spell's reach collapses to 1 tile (Chebyshev), same rule as ranged weapons/
	# thrown weapons — see PlayerRanged.is_ranged_target_in_range(). Overrides range_is_fov too.
	if GameState.is_blinded(player.grid_pos):
		return 1
	if spell.range_is_fov:
		# Matches dungeon_floor.gd's own live FOV radius formula exactly (update_fog()/
		# _decide_action() visibility checks) — darkvision (Orc/Dwarf) and Wild Heart Eagle's
		# fov_radius_bonus both genuinely extend how far a character can see, and therefore how
		# far a full-FOV-range spell can reach.
		return DungeonFloor.FOV_RADIUS + GameState.fov_radius_bonus + GameState.player_stats.darkvision_bonus
	return spell.range_tiles

## Direct one-motion cast for the Special quick-cast slot (Alt+click in player.gd, mirroring
## Shift+ranged's single-motion resolve — no separate arm-then-click step like the ability-bar's
## begin_cast()/try_cast_at() pair). SELF-target spells (Shield, and touch buffs like Mage Armor)
## ignore `clicked` entirely and self-cast immediately — Alt+click is always "target myself",
## regardless of range_tiles, unlike begin_cast()'s own SELF branch which arms touch spells for a
## follow-up click instead.
func cast_direct(spell_id: String, clicked: Vector2i) -> void:
	if _shield_blocks_casting():
		GameState.game_log("[color=gray]You can't cast with a Shield equipped.[/color]")
		return
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	# Ritual casting (Detect Magic): free of the slot-availability gate entirely, as long as no
	# enemy is currently hunting the caster — see Spell.is_ritual's own comment.
	var ritual_free: bool = spell.is_ritual and not player.is_being_pursued()
	if spell.level > 0 and not GameState.invincible and not ritual_free and not player.stats.is_lineage_free_cast_available(spell_id) and not GameState.warlock_invocation_free_cast(spell_id):
		var caster: SpellcasterState = player.stats.caster
		if caster == null or caster.slot_pool == null or not caster.slot_pool.can_cast(spell):
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return
	if spell.target_kind == Spell.TargetKind.SELF:
		_cast_self(spell)
		return
	if _uses_multi_target_flow(spell):
		_begin_multi_target(spell_id, false, null)
		_handle_multi_target_click(clicked)
		return
	_armed_spell_id = spell_id
	try_cast_at(clicked)

func try_cast_at(clicked: Vector2i) -> void:
	if _mm_active:
		_handle_multi_target_click(clicked)
		return
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
	# SELF-target touch spells (Mage Armor) only ever have one valid target — the caster. Any
	# click at all (regardless of where it landed) confirms the cast; there's no "range"/"LOS to
	# yourself" concept worth enforcing, and requiring the click to land pixel-perfectly on your
	# own tile was needless friction for a spell that literally cannot target anything else yet.
	if spell.target_kind == Spell.TargetKind.SELF:
		if from_scroll:
			_consume_scroll(scroll_item)
		await _cast_self(spell, from_scroll)
		return
	# Cone-shaped spells (Burning Hands) are self-centered — the clicked tile only supplies an aim
	# DIRECTION from the caster, not an impact point, so it's exempt from the normal range/LOS
	# gate (the click need not itself be reachable or even visible).
	if spell.shape != "cone":
		var d: Vector2i = clicked - player.grid_pos
		var dist_cheb: int = maxi(absi(d.x), absi(d.y))
		var eff_range: int = _effective_range(spell)
		if dist_cheb > eff_range:
			GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % eff_range)
			return
		if spell.bypasses_los:
			# Magic Missile-style "seeking dart" — no LOS needed, but a real walkable path must
			# exist (chasms aside, see DungeonFloor.has_walkable_route_ignoring_chasms()).
			if not player._dungeon_floor.has_walkable_route_ignoring_chasms(player.grid_pos, clicked):
				GameState.game_log("[color=gray]No path to the target.[/color]")
				return
		elif not player._dungeon_floor.has_ranged_los(player.grid_pos, clicked):
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
		# Dispatched by resolution shape, not a hardcoded effect_id list, so a new SAVE-resolution
		# cantrip (e.g. Poison Spray, a Tiefling Fiendish Legacy grant) never needs a matching edit
		# here — only Light needs special-casing (touches a tile/prop, not an enemy).
		if spell.effect_id == "light":
			await SpellEffects.cast_light_at_tile(player, spell, clicked, player._dungeon_floor, from_scroll)
		elif spell.resolution == Spell.Resolution.SAVE:
			var save_target: Enemy = player._dungeon_floor.get_targetable_enemy_at(clicked)
			if save_target == null:
				GameState.game_log("[color=gray]%s needs a target.[/color]" % spell.spell_name)
			else:
				await SpellEffects.cast_cantrip_save_at_enemy(player, spell, save_target, player._dungeon_floor, from_scroll)
		else:
			var target0: Enemy = player._dungeon_floor.get_targetable_enemy_at(clicked)
			if target0 == null:
				await SpellEffects.cast_spell_at_tile(player, spell, clicked, player._dungeon_floor)
			else:
				await SpellEffects.cast_spell(player, spell, target0, player._dungeon_floor, from_scroll)
		return

	match spell.target_kind:
		Spell.TargetKind.TILE:
			await SpellEffects.cast_leveled_at_tile(player, spell, lvl, clicked, player._dungeon_floor, from_scroll)
		Spell.TargetKind.ENEMY:
			# Magic Missile (the only AUTO_HIT ENEMY-target leveled spell) is intercepted earlier
			# via _begin_multi_target() before it ever reaches this dispatch — so every spell that
			# actually resolves here is ATTACK_ROLL (Chromatic Orb/Witch Bolt/Ray of Sickness/Ray of
			# Enfeeblement) or SAVE (Hold Person/Hellish Rebuke — Tiefling Fiendish Legacy grants).
			var target: Enemy = player._dungeon_floor.get_targetable_enemy_at(clicked)
			if target == null:
				GameState.game_log("[color=gray]%s needs a target.[/color]" % spell.spell_name)
			elif spell.resolution == Spell.Resolution.ATTACK_ROLL:
				await SpellEffects.cast_leveled_attack_at_enemy(player, spell, lvl, target, player._dungeon_floor, from_scroll)
			elif spell.resolution == Spell.Resolution.SAVE:
				await SpellEffects.cast_leveled_save_at_enemy(player, spell, lvl, target, player._dungeon_floor, from_scroll)
		_:
			pass

# ── Multi-target/multi-beam collection (Magic Missile's 3 darts, Eldritch Blast's 1-4 beams) ──
# Arms exactly like any other spell (spell_targeting_active stays true across all _mm_count clicks
# so player.gd's existing dispatch keeps routing every click into try_cast_at(), which forwards
# here whenever _mm_active is set) but doesn't resolve on the first click — collects one
# target-per-instance (repeats allowed, focusing more than one dart/beam onto the same target)
# until _mm_count are gathered, then resolves the whole volley in a single turn/slot-consumption
# via SpellEffects.cast_magic_missile()/cast_multi_beam_cantrip(). Esc (cancel()) at any point
# clears _mm_active/_mm_targets with nothing spent, since the slot/turn are only touched once
# every pick is in.
## Whether a multi-target cast is currently mid-collection (some or none of its picks made yet) —
## lets player.gd's RMB handler special-case "undo last pick" over its normal RMB behavior.
func is_collecting_multi_target() -> bool:
	return _mm_active

## RMB during dart collection — un-locks the most recent pick instead of cancelling the whole
## cast (that's still Esc/cancel()'s job). No-op if nothing's been picked yet (RMB before any dart
## is locked in has nothing to undo, and the mode is still active so a further LMB pick still
## works normally).
func undo_last_multi_target_pick() -> void:
	if not _mm_active or _mm_targets.is_empty():
		return
	var spell: Spell = SpellDb.get_spell(_armed_spell_id)
	var noun: String = "dart" if spell != null and spell.effect_id == "magic_missile" else "beam"
	var removed: Dictionary = _mm_targets.pop_back()
	var remaining: int = _mm_count - _mm_targets.size()
	GameState.game_log("[color=gray]Un-locked the %s aimed at %s. Choose %d more target%s. [Esc] to cancel.[/color]" % [
		noun, removed.get("label", "that target"), remaining, "s" if remaining != 1 else ""])

func _begin_multi_target(spell_id: String, from_scroll: bool, scroll_item: Item) -> void:
	var spell: Spell = SpellDb.get_spell(spell_id)
	_armed_spell_id = spell_id
	spell_targeting_active = true
	_casting_from_scroll = from_scroll
	_armed_scroll_item = scroll_item
	_mm_active = true
	_mm_targets = []
	_mm_count = _multi_target_beam_count(spell)
	_mm_enemies_only = spell.effect_id != "magic_missile"
	if spell.effect_id == "magic_missile":
		GameState.game_log("[color=lime]Magic Missile — choose up to 3 targets (1 dart each; click the same target again to focus more darts on it). Enemies, barrels, and doors are all valid. [Esc] to cancel.[/color]")
	else:
		GameState.game_log("[color=lime]%s — choose %d target%s (1 beam each; click the same target again to focus more beams onto it). Enemies only. [Esc] to cancel.[/color]" % [
			spell.spell_name, _mm_count, "s" if _mm_count != 1 else ""])

## Resolves whatever's at `pos` into a dart-target descriptor, or `{}` if nothing valid is there.
## Enemy first (matches every other spell's targeting priority), then the two destructible-prop
## kinds that don't have HP/AC yet (scripts/entities/CLAUDE.md's Enemy stat-block schema) but are
## still valid things to point a dart at per direct owner request — forward-compatible slot for
## once that system exists.
func _resolve_multi_target_at(pos: Vector2i) -> Dictionary:
	var dungeon_floor: Node = player._dungeon_floor
	var enemy: Enemy = dungeon_floor.get_targetable_enemy_at(pos)
	if enemy != null:
		return {"kind": "enemy", "enemy": enemy, "label": enemy.display_name}
	if _mm_enemies_only:
		return {}
	if dungeon_floor.has_barrel_at(pos):
		return {"kind": "barrel", "pos": pos, "label": "the barrel"}
	if dungeon_floor.has_door_at(pos):
		return {"kind": "door", "pos": pos, "label": "the door"}
	return {}

func _handle_multi_target_click(clicked: Vector2i) -> void:
	var spell: Spell = SpellDb.get_spell(_armed_spell_id)
	if spell == null or player._dungeon_floor == null:
		cancel()
		return

	var d: Vector2i = clicked - player.grid_pos
	var dist_cheb: int = maxi(absi(d.x), absi(d.y))
	var eff_range: int = _effective_range(spell)
	if dist_cheb > eff_range:
		GameState.game_log("[color=gray]Target out of range (max %d tiles).[/color]" % eff_range)
		return
	if spell.bypasses_los:
		if not player._dungeon_floor.has_walkable_route_ignoring_chasms(player.grid_pos, clicked):
			GameState.game_log("[color=gray]No path to the target.[/color]")
			return
	elif not player._dungeon_floor.has_ranged_los(player.grid_pos, clicked):
		GameState.game_log("[color=gray]No clear line to target.[/color]")
		return

	var desc: Dictionary = _resolve_multi_target_at(clicked)
	if desc.is_empty():
		GameState.game_log("[color=gray]Nothing to target there.[/color]")
		return

	_mm_targets.append(desc)
	var remaining: int = _mm_count - _mm_targets.size()
	if remaining > 0:
		var noun: String = "Dart" if spell.effect_id == "magic_missile" else "Beam"
		GameState.game_log("[color=lime]%s %d locked onto %s. Choose %d more target%s (or click it again). [Esc] to cancel.[/color]" % [
			noun, _mm_targets.size(), desc["label"], remaining, "s" if remaining != 1 else ""])
		return

	var from_scroll: bool = _casting_from_scroll
	var scroll_item: Item = _armed_scroll_item
	var targets: Array[Dictionary] = _mm_targets
	spell_targeting_active = false
	_armed_spell_id = ""
	_casting_from_scroll = false
	_armed_scroll_item = null
	_mm_active = false
	_mm_targets = []

	var lvl: int = spell.level
	if not from_scroll and spell.level > 0:
		lvl = _cast_level_for(spell)
		if lvl == -1:
			GameState.game_log("[color=gray]No spell slot available for %s.[/color]" % spell.spell_name)
			return
	if from_scroll:
		_consume_scroll(scroll_item)

	if spell.effect_id == "magic_missile":
		await SpellEffects.cast_magic_missile(player, spell, lvl, targets, player._dungeon_floor, from_scroll)
	else:
		await SpellEffects.cast_multi_beam_cantrip(player, spell, targets, player._dungeon_floor, from_scroll)
