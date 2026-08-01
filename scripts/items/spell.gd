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
# Ritual casting (5e): can be cast without expending a spell slot, PROVIDED no enemy is currently
# hunting the caster (Enemy.Behavior.CHASING/SEARCHING anywhere on the floor — Player.
# is_being_pursued()). The real rule is "takes 10 extra minutes"; this engine has no clock to hang
# that on, so it's simplified to "free, but only when not being actively pursued" — see
# SpellEffects._consume_slot()'s ritual branch. Detect Magic is the first (and so far only) user.
@export var is_ritual: bool = false
