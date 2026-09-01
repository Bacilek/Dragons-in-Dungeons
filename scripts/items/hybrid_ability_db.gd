class_name HybridAbilityDb
extends RefCounted

# Data definitions for the Hybrid class's ability kit (docs/architecture/hybrid-class-design.md).
# Static factory, same "build in code, no .tres" convention as SpellDb / Talent / SpriteFrames.
#
# Each entry is a plain Dictionary. GameState._build_hybrid_ability(id) turns one into an Ability
# resource for the bar; HybridEffects.resolve(id, ...) executes it. The owner iterates the kit by
# editing DEFS below - no other file needs to change to add / retune an ability.
#
# Fields:
#   name, description, icon           - display
#   min_level                         - level at which the ability is granted (auto, no picker yet).
#                                       Progression cadence (docs/architecture/hybrid-class-design.md
#                                       Section 4.3): L1 = 1 passive + 1 activation, then a new
#                                       activation every odd level (3, 5, 7, ...); L5's slot is the
#                                       free subclass activation once subclasses land.
#   kind: "passive"|"activation"       - which cadence track this entry belongs to
#   power_type: "cooldown"|"essence"|"passive"
#   cooldown / essence_cost           - one of the two, per power_type
#   target: "self"|"enemy"|"tile"|"direction"|"sphere"
#   range, shape_size                 - tiles (Chebyshev)
#   resolution: "attack"|"save"|"auto"
#   save_stat, save_for_half          - for "save"
#   dice, damage_type                 - "NdM"
#   effect                            - HybridEffects dispatch key

const ICON_DIR := "res://icons/classes/hybrid/"

const DEFS: Dictionary = {
	"hb_spark": {
		"name": "Spark",
		"description": "Ranged spell attack, deals 1d8 Lightning. If the target is Wet or standing in water, the bolt arcs to every other Wet / in-water enemy within 2 tiles for the same damage.",
		"icon": ICON_DIR + "spark.png",
		"min_level": 1, "kind": "activation",
		"power_type": "cooldown", "cooldown": 2,
		"target": "enemy", "range": 4,
		"resolution": "attack",
		"dice": "1d8", "damage_type": "Lightning",
		"effect": "spark",
	},
	"hb_tide": {
		"name": "Tide",
		"description": "Soaks a radius-1 area: enemies there become Wet for 4 turns, any burning is put out. No damage - the setup half of the combo.",
		"icon": ICON_DIR + "tide.png",
		"min_level": 3, "kind": "activation",
		"power_type": "cooldown", "cooldown": 4,
		"target": "tile", "range": 5, "shape_size": 1,
		"resolution": "auto",
		"effect": "tide",
	},
	"hb_ground": {
		"name": "Grounded",
		"description": "Passive. You never take arc / electrified-water damage from your own Lightning abilities.",
		"icon": ICON_DIR + "ground.png",
		"min_level": 1, "kind": "passive",
		"power_type": "passive",
		"effect": "passive",
	},
	"hb_arc": {
		"name": "Arc",
		"description": "DEX save or take 4d8 Lightning, half on a save, to everything within 2 tiles of the impact. Any Wet / in-water enemy caught triggers the full arc spread.",
		"icon": ICON_DIR + "arc.png",
		"min_level": 5, "kind": "activation",
		"power_type": "essence", "essence_cost": 2,
		"target": "sphere", "range": 6, "shape_size": 2,
		"resolution": "save", "save_stat": "dex", "save_for_half": true,
		"dice": "4d8", "damage_type": "Lightning",
		"effect": "arc",
	},
	"hb_emberstep": {
		"name": "Emberstep",
		"description": "Dash up to 3 tiles. Every grass tile crossed is set alight.",
		"icon": ICON_DIR + "emberstep.png",
		"min_level": 7, "kind": "activation",
		"power_type": "cooldown", "cooldown": 3,
		"target": "direction", "range": 3,
		"resolution": "auto",
		"effect": "emberstep",
	},
}

static func ids() -> Array:
	return DEFS.keys()

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func is_hybrid_ability(id: String) -> bool:
	return DEFS.has(id)

static func kind_of(id: String) -> String:
	return str(DEFS.get(id, {}).get("kind", "activation"))

# ids the character is entitled to at a given level, in min_level then key order.
static func ids_for_level(level: int) -> Array:
	var out: Array = []
	for id: String in DEFS.keys():
		if int(DEFS[id].get("min_level", 1)) <= level:
			out.append(id)
	return out
