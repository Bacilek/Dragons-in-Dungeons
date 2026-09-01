class_name RampagerAbilityDb
extends RefCounted

# Data definitions for the Rampager class's ability kit (docs/architecture/rampager-class-design.md).
# Static factory, exact same shape/convention as HybridAbilityDb — the Rampager runs on the same
# cooldown + nova-pool economy, just with Fury in place of Essence and STR-based power math.
#
# GameState._build_rampager_ability(id) turns one into an Ability; RampagerEffects.<effect>(...)
# executes it; PlayerRampager owns arming / targeting. Owner iterates the kit by editing DEFS.
#
# Fields: name, description, icon, min_level, kind ("passive"|"activation"),
#   power_type ("cooldown"|"fury"|"passive"), cooldown / fury_cost (one, per power_type),
#   target ("self"|"enemy"|"tile"|"direction"|"sphere"), range, shape_size,
#   resolution ("attack"|"save"|"auto"), save_stat, save_for_half, dice, damage_type, effect.

const ICON_DIR := "res://icons/classes/rampager/"

const DEFS: Dictionary = {
	"rmp_bracer": {
		"name": "Bracer",
		"description": "Passive. You build no resource for free — Fury refills +1 per floor descent and fully on a long rest. Your shove / hurl abilities slam enemies into walls, each other, traps and chasms.",
		"icon": ICON_DIR + "bracer.png",
		"min_level": 1, "kind": "passive",
		"power_type": "passive",
		"effect": "passive",
	},
	"rmp_overrun": {
		"name": "Overrun",
		"description": "Charge up to 4 tiles in a straight line and ram the first enemy hit: a melee attack for 2d6 Bludgeoning, then shove them 1 tile (wall-slam / collision / trap / chasm all apply). Barrels and unlocked doors in the path are smashed through.",
		"icon": ICON_DIR + "overrun.png",
		"min_level": 1, "kind": "activation",
		"power_type": "cooldown", "cooldown": 2,
		"target": "direction", "range": 4,
		"resolution": "attack",
		"dice": "2d6", "damage_type": "Bludgeoning",
		"effect": "overrun",
	},
	"rmp_shockwave": {
		"name": "Shockwave",
		"description": "Smash the ground: every enemy within 2 tiles makes a STR save or takes 3d8 Bludgeoning (half on a save). Anyone who fails is knocked Prone.",
		"icon": ICON_DIR + "shockwave.png",
		"min_level": 3, "kind": "activation",
		"power_type": "fury", "fury_cost": 2,
		"target": "sphere", "range": 6, "shape_size": 2,
		"resolution": "save", "save_stat": "str", "save_for_half": true,
		"dice": "3d8", "damage_type": "Bludgeoning",
		"effect": "shockwave",
	},
}

static func ids() -> Array:
	return DEFS.keys()

static func get_def(id: String) -> Dictionary:
	return DEFS.get(id, {})

static func is_rampager_ability(id: String) -> bool:
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
