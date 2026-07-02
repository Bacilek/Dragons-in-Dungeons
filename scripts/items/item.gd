class_name Item
extends Resource

enum Type { WEAPON, ARMOR, POTION, SCROLL, FOOD, GOLD, KEY, TOOL }

@export var item_name: String = ""
@export var item_type: Type = Type.POTION
@export var quantity: int = 1
@export var description: String = ""
@export var icon_path: String = ""
@export var bonus_damage: int = 0
@export var bonus_ac: int = 0
@export var heal_amount: int = 0
@export var str_bonus: int = 0
@export var floor_min: int = 1
@export var floor_max: int = 10
@export var is_ranged: bool = false
@export var range: int = 0
@export var consumes_on_ranged: bool = false
@export var is_two_handed: bool = false
@export var is_heavy_armor: bool = false  # ends Barbarian Rage immediately on equip
@export var is_heavy: bool = false        # Heavy: attacking with STR < 13 imposes Disadvantage
@export var is_versatile: bool = false    # Versatile: no weapon currently sets this; World Tree's Branching Strike keys off it alongside is_heavy
# If > 0, overrides Stats.base_min/max_damage when this weapon is equipped (e.g. 1d12 Greataxe).
# recalculate_stats() in GameState applies these instead of base_min/max_damage when non-zero.
@export var damage_die_min: int = 0
@export var damage_die_max: int = 0
# Damage type categories (for reference — no enum, just documentation):
#   Physical:  "Slashing", "Piercing", "Bludgeoning"
#   Elemental: "Fire", "Cold", "Acid", "Poison", "Thunder", "Lightning"
#   Magical:   "Force", "Necrotic", "Psychic", "Radiant"
# "" = unknown/unset.
@export var damage_type: String = ""
@export var heal_dice_count: int = 0   # if > 0, roll N dice of heal_dice_sides + CON instead of heal_amount
@export var heal_dice_sides: int = 0
# Weapon mastery — one signature effect per weapon, keyed by name (e.g. "Cleave").
# "" = no mastery. WeaponProperties.MASTERY_GLOSSARY holds the tooltip description.
@export var weapon_mastery: String = ""

func get_display_name() -> String:
	if quantity > 1:
		return "%s ×%d" % [item_name, quantity]
	return item_name
