class_name MaterialTable
extends RefCounted

# Generic material → AC lookup (D&D-style "object AC by material" table) — not tied to any one
# prop type. Any destructible prop/object that needs a defense value can just name its material
# instead of hand-authoring its own AC. First consumers: Barrels and Doors (both Wood,
# scripts/world/dungeon_floor.gd's _place_barrel()/_spawn_doors()) — a future prop (an Iron
# portcullis, a Glass window, a Rope bridge) just picks a material key from this table.

const MATERIAL_AC: Dictionary = {
	"cloth": 11, "paper": 11, "rope": 11,
	"crystal": 13, "glass": 13, "ice": 13,
	"wood": 15, "bone": 15,
	"stone": 17,
	"iron": 19, "steel": 19,
	"mithral": 21,
	"adamantine": 23,
}

## Unknown/unset material falls back to Wood's AC (15) — the most common prop material in this
## game today, and a reasonable "solid but not exotic" default for anything not yet in the table.
static func ac_for(material: String) -> int:
	return MATERIAL_AC.get(material, 15)
