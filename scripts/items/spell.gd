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
@export var dice_count: int = 1
@export var dice_sides: int = 6
@export var damage_type: String = ""
@export var cantrip_tier_scaling: bool = false   # dice_count × tier at character levels 1/5/11/17
@export var upcast_dice_per_level: int = 0       # extra dice per slot level above `level` (leveled spells only)

# SAVE resolution only
@export var save_stat: String = ""     # "STR"/"DEX"/"CON"/"INT"/"WIS"/"CHA"
@export var save_for_half: bool = false

# AoE — deliberately minimal: only single-target ("") and sphere exist (no cone/line/cube,
# see leveled-spells-and-slots-plan.md §7's content-scope cut).
@export var shape: String = ""         # "" = single target, "sphere" = AoE radius
@export var shape_size: int = 0        # sphere radius in tiles

@export var effect_id: String = ""     # "" = pure generic damage; else SpellEffects dispatch
@export var class_list: Array[String] = []
