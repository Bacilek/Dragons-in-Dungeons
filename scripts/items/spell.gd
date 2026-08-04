class_name Spell
extends Resource

# Spell data model. Started as the cantrip-only slice of
# docs/architecture/spellcasting-design.md; extended per
# docs/architecture/leveled-spells-and-slots-plan.md for leveled spells + spell slots.
# Still a trimmed subset of the full framework doc's Spell shape — no concentration, no
# reactions, no components, no cone/line/cube AoE (only single-target and sphere AoE exist).

enum Resolution { ATTACK_ROLL, SAVE, AUTO_HIT }
enum TargetKind { ENEMY, SELF, TILE }

@export var spell_id: String = ""
@export var spell_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var level: int = 0            # 0 = cantrip; 1-9 = leveled spell
@export var school: String = ""
@export var range_tiles: int = 1

@export var resolution: Resolution = Resolution.ATTACK_ROLL
@export var target_kind: TargetKind = TargetKind.ENEMY
# When true, `range_tiles` is ignored and the spell's real range is the caster's LIVE FOV radius
# (DungeonFloor.FOV_RADIUS + GameState.fov_radius_bonus) instead of a fixed "book" number — some
# characters see further than others (e.g. Wild Heart Eagle's +1 FOV radius), so a fixed range
# would be wrong for them. See PlayerSpellcasting.try_cast_at().
@export var range_is_fov: bool = false
# BG3-style "seeking" targeting (Magic Missile): when true, the normal has_ranged_los() check is
# skipped entirely and replaced with a walkable-PATH-exists check instead (DungeonFloor.
# has_walkable_route_ignoring_chasms()) — the caster doesn't need to SEE the target (it can be
# behind a wall corner, grass, closed door — anything), it just needs a route a walking character
# could physically take to reach it, EXCEPT chasms don't block that route (the missile flies over
# one; a character on foot couldn't). See PlayerSpellcasting.try_cast_at().
@export var bypasses_los: bool = false
@export var dice_count: int = 1
@export var dice_sides: int = 6
@export var damage_type: String = ""
@export var cantrip_tier_scaling: bool = false   # dice_count × tier at character levels 1/5/11/17
# Eldritch Blast-style scaling: instead of growing dice_count per tier (cantrip_tier_scaling
# above), the cast gains one extra independently-targetable beam per tier (1/2/3/4 beams at
# character levels 1/5/11/17), each its own attack roll at dice_count/dice_sides. Mutually
# exclusive with cantrip_tier_scaling in practice (no spell sets both). See
# PlayerSpellcasting._multi_target_beam_count() / SpellEffects.cast_multi_beam_cantrip().
@export var multi_beam_scaling: bool = false

# SAVE resolution only
@export var save_stat: String = ""     # "STR"/"DEX"/"CON"/"INT"/"WIS"/"CHA"
@export var save_for_half: bool = false

# AoE — deliberately minimal: only single-target (""), sphere, and cone exist (no line/cube).
# "cone" (Burning Hands) is a directional 90°-arc burst from the CASTER outward toward the
# clicked/hovered tile — see SpellEffects.cone_tiles()/PlayerSpellcasting.try_cast_at()'s
# shape == "cone" special-case (the clicked tile only supplies a direction, not an impact point,
# so it's exempt from the normal range/LOS gate).
@export var shape: String = ""         # "" = single target, "sphere" = AoE radius (Euclidean), "cone" = 90° arc, "cube" = AoE radius (Chebyshev/square, Faerie Fire)
@export var shape_size: int = 0        # sphere/cube: radius in tiles; cone: length in tiles

@export var effect_id: String = ""     # "" = pure generic damage; else SpellEffects dispatch
@export var class_list: Array[String] = []

# ── Structured tooltip fields (SpellTooltip.build(), scripts/items/spell_tooltip.gd) ──────────
# Casting Time: this engine only distinguishes "Action" (costs the player's real turn) and "Free"
# (doesn't) — no bonus-action/reaction tier exists, so a RAW reaction (Hellish Rebuke) or bonus
# action (Misty Step) is approximated to whichever of the two fits its actual implementation.
@export var casting_time: String = "Action"
# 0 = instantaneous (no Duration line shown at all). A positive value is the real turn count the
# effect persists for (Concentration or not, see is_concentration below) — was previously only
# ever stated as prose inside `description`.
@export var duration_turns: int = 0
@export var is_concentration: bool = false
# Ritual casting (5e): can be cast without expending a spell slot, PROVIDED no enemy is currently
# hunting the caster (Enemy.Behavior.CHASING/SEARCHING anywhere on the floor — Player.
# is_being_pursued()). The real rule is "takes 10 extra minutes"; this engine has no clock to hang
# that on, so it's simplified to "free, but only when not being actively pursued" — see
# SpellEffects._consume_slot()'s ritual branch. Detect Magic is the first (and so far only) user.
@export var is_ritual: bool = false

# ── Upcasting (Warlock Pact Magic only — PactSlotPool.available_level() auto-upcasts every cast to
# the caster's single current pact slot level, unlike Wizard/Ranger's own pools which never upcast
# at all; see scripts/items/CLAUDE.md's PactSlotPool entry) ──────────────────────────────────────
# `extra_levels = cast_level - spell.level` (SpellEffects._upcast_extra_levels()) drives all three
# — each is applied ONCE PER extra level above the spell's own base level, D&D 2024 "for each slot
# level above Nth" convention. A spell with none of these three set simply has no upcast benefit
# (matches real 5e/5.5e RAW for several spells here — Misty Step, Expeditious Retreat, Darkness,
# Ray of Enfeeblement all genuinely have no "At Higher Levels" text). Generic fields usable by any
# slot pool; only PactSlotPool ever actually produces cast_level > spell.level today.
@export var upcast_dice_count: int = 0     # extra dice (of this spell's own dice_sides) per level above base
@export var upcast_extra_targets: int = 0  # extra target per level above base (Magic Missile darts, Hideous Laughter/Invisibility/Hold Person/Longstrider targets)
@export var upcast_flat_amount: int = 0    # flat amount per level above base — meaning is per-effect_id (False Life Temp HP, Fog Cloud radius)
