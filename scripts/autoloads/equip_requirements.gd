class_name EquipRequirements
extends RefCounted

# Pure equip-gating logic (can THIS item go into THIS slot, given the player's proficiencies and
# currently equipped gear) extracted out of game_state.gd — same static-func-only, no-mutable-
# state pattern as TalentIcons (scripts/autoloads/talent_icons.gd) and WeaponTooltip/ArmorTooltip
# (scripts/items). GameState.can_equip_shield()/can_equip_armor() are now 1-line delegators to the
# functions below; the log-emitting wrappers (log_shield_equip_blocked()/log_armor_equip_blocked())
# stay on GameState since they need its combat_message signal, which this class deliberately has
# no access to (it's pure, no signals, no side effects).

# Turns required to equip/unequip/swap body armor — keyed by the HEAVIEST armor_category involved
# (putting on, taking off, or swapping between two pieces all cost the same as their own worst
# category). NONE (unarmored/clothing-tier, no current ITEM_POOL entry) is 1 turn, same as a free
# equip effectively costing "an action".
const ARMOR_CHANGE_TURNS: Dictionary = {
	Item.ArmorCategory.NONE: 1,
	Item.ArmorCategory.LIGHT: 5,
	Item.ArmorCategory.MEDIUM: 10,
	Item.ArmorCategory.HEAVY: 15,
}

# Shield gate: Item.is_shield requires Stats.proficient_shields, and can't coexist with a
# two-handed Main Hand weapon. Returns true for any non-shield item (no-op gate).
static func can_equip_shield(item: Item, stats: Stats, equipment: Dictionary) -> bool:
	if not item.is_shield:
		return true
	if not stats.proficient_shields:
		return false
	var main_hand: Item = equipment.get("melee") as Item
	if main_hand != null and main_hand.is_two_handed:
		return false
	return true

# Body armor gate: armor_category requires the matching Stats.proficient_*_armor flag, and
# str_requirement (Heavy armor only) blocks equipping below that STR score. Returns true for any
# non-body-armor item (Shield, or any other item type — no-op gate, mirrors can_equip_shield()'s
# own shape).
static func can_equip_armor(item: Item, stats: Stats) -> bool:
	if item == null or item.item_type != Item.Type.ARMOR or item.is_shield:
		return true
	match item.armor_category:
		Item.ArmorCategory.LIGHT:
			if not stats.proficient_light_armor:
				return false
		Item.ArmorCategory.MEDIUM:
			if not stats.proficient_medium_armor:
				return false
		Item.ArmorCategory.HEAVY:
			if not stats.proficient_heavy_armor:
				return false
	if item.str_requirement > 0 and stats.strength < item.str_requirement:
		return false
	return true

# Weapon proficiency gate: a WEAPON item whose weapon_category is "Simple"/"Martial" requires
# Stats.is_weapon_proficient() to be equipped at all (folds in proficient_simple_weapons/
# proficient_martial_weapons and martial_weapon_restriction, e.g. Monk's Martial-Light-only
# proficiency) — unlike the attack-roll proficiency bonus (CombatMath.weapon_prof_bonus()), which
# just drops a bonus, an unproficient character can't wield the weapon in the first place. Returns
# true for any non-weapon item, or a weapon with no category ("" = n/a), same no-op-gate shape as
# the others.
static func can_equip_weapon(item: Item, stats: Stats) -> bool:
	if item == null or item.item_type != Item.Type.WEAPON:
		return true
	return stats.is_weapon_proficient(item)

static func armor_change_turns(new_item: Item, old_item: Item) -> int:
	var worst: int = int(Item.ArmorCategory.NONE)
	if new_item != null:
		worst = maxi(worst, int(new_item.armor_category))
	if old_item != null:
		worst = maxi(worst, int(old_item.armor_category))
	return ARMOR_CHANGE_TURNS.get(worst, 1)
