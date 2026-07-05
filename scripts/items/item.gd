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
@export var is_versatile: bool = false    # Versatile: World Tree's Branching Strike keys off it alongside is_heavy; also toggles two-handed grip (see versatile_die_min/max)
# Versatile weapons only: damage die used while gripped two-handed (toggled via Main Hand slot
# click in inventory_overlay.gd, which also flips is_two_handed). 0 = not versatile / no alt die.
@export var versatile_die_min: int = 0
@export var versatile_die_max: int = 0
@export var is_finesse: bool = false      # Finesse: attack/damage modifier uses max(STR, DEX) instead of STR — see CombatMath.finesse_modifier()
@export var is_light: bool = false        # Light: only Light weapons may be equipped in the Off-hand slot alongside a Main Hand weapon
@export var is_reach: bool = false        # Reach: +1 tile melee range — see CombatMath.melee_reach()
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
# Weapon category — "Simple" or "Martial" ("" = n/a, e.g. non-weapon items). Determines
# whether Stats.proficient_simple_weapons/proficient_martial_weapons grants the attack
# roll's proficiency bonus (see Stats and player.gd._weapon_prof_bonus()).
@export var weapon_category: String = ""
# Name of the Item this ranged weapon consumes as ammo per shot (e.g. "Arrow"). "" = no named
# ammo required (falls back to consumes_on_ranged on the weapon's own stack, e.g. the legacy
# Throwing-Dagger pattern, or infinite ammo). Long range for ranged weapons is NOT a per-item
# field — it's always the player's live FOV (DungeonFloor.FOV_RADIUS), only the "normal" range
# (`range` above) differs per weapon; see player.gd._is_ranged_target_in_range().
@export var ammo_item_name: String = ""
# Thrown: can be primed via RMB (same UX as quickbar food throw) then thrown at a tile with LMB.
# Uses the wielder's MELEE attack modifier (STR, or max(STR,DEX) if is_finesse) even though it's
# thrown — not a separate ranged stat. `range` (above) is the thrown weapon's normal range; beyond
# that but within the player's live FOV the throw still works but rolls with Disadvantage — same
# normal/FOV-long-range convention as ranged weapons (see PlayerRanged.is_ranged_target_in_range()).
@export var is_thrown: bool = false
# Thrown weapons only: durability. uses_remaining starts at uses_max and decrements by 1 per throw
# (0 on a natural-20 critical hit, 2 on a natural-1 critical fumble). Reaching 0 breaks the weapon
# (GameState.remove_item()). Not consumed by ordinary melee attacks — only by throwing.
@export var uses_max: int = 0
@export var uses_remaining: int = 0

func get_display_name() -> String:
	if quantity > 1:
		return "%s ×%d" % [item_name, quantity]
	return item_name
