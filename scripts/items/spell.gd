class_name Spell
extends Resource

# Minimal spell data model — the cantrip-only slice of docs/architecture/spellcasting-design.md.
# Trimmed to what Fire Bolt / Ray of Frost / Shocking Grasp actually need: no spell slots, no
# AoE, no concentration, no upcasting. Extend this (and SpellSlotPool/ActiveSpellEffect from the
# design doc) when leveled spells are added — see scripts/items/CLAUDE.md.

enum Resolution { ATTACK_ROLL }

@export var spell_id: String = ""
@export var spell_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var level: int = 0            # always 0 (cantrip) in this slice
@export var school: String = ""
@export var range_tiles: int = 1

@export var resolution: Resolution = Resolution.ATTACK_ROLL
@export var dice_count: int = 1
@export var dice_sides: int = 6
@export var damage_type: String = ""
@export var cantrip_tier_scaling: bool = false   # dice_count × tier at character levels 1/5/11/17

@export var effect_id: String = ""     # "" = pure generic damage; else SpellEffects dispatch
@export var class_list: Array[String] = []
