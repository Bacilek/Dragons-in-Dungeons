class_name WeaponForge
extends RefCounted

# Blacksmith random-weapon crafting (scripts/items/CLAUDE.md's "WeaponForge" section). Pure
# data-construction — every field it sets is already interpreted correctly by existing combat/UI
# code, so no new gameplay code is needed anywhere else. All randomness goes through Rng (gameplay
# stream), per the project's seeded-determinism rule.

const DICE_SHAPES: Array = [
	[1, 4], [1, 6], [1, 8], [1, 10], [1, 12], [2, 12],
]

const REQUIREMENT_POOL: Array[String] = ["Heavy", "Two-handed", "Martial", "Ammo"]
const PROPERTY_POOL: Array[String] = ["Finesse", "Reach", "Thrown", "Versatile"]
const AMMO_ITEMS: Array[String] = ["Arrow", "Bolt", "Buckshot"]

const DAMAGE_TYPES_PHYSICAL: Array[String] = ["Slashing", "Piercing", "Bludgeoning"]
const DAMAGE_TYPES_ELEMENTAL: Array[String] = ["Fire", "Cold", "Acid", "Poison", "Thunder", "Lightning"]
const DAMAGE_TYPES_MAGICAL: Array[String] = ["Force", "Necrotic", "Psychic", "Radiant"]

const NAME_LETTERS := "abcdefghijklmnopqrstuvwxyz"

const GOLD_VALUE := 10


static func generate_random_weapon() -> Item:
	var item := Item.new()
	item.item_type = Item.Type.WEAPON
	item.quantity = 1

	# 1. Damage die
	var die: Array = Rng.pick(DICE_SHAPES)
	item.damage_die_min = die[0]
	item.damage_die_max = die[1]

	# 2. Requirements (1-2, no replacement)
	var req_count: int = Rng.range_i(1, 2)
	var req_pool: Array[String] = REQUIREMENT_POOL.duplicate()
	Rng.shuffle(req_pool)
	var requirements: Array[String] = req_pool.slice(0, req_count)

	item.weapon_category = "Martial" if "Martial" in requirements else "Simple"
	if "Heavy" in requirements:
		item.is_heavy = true
	if "Two-handed" in requirements:
		item.is_two_handed = true
	if "Ammo" in requirements:
		item.is_ranged = true
		item.ammo_item_name = Rng.pick(AMMO_ITEMS)
		item.range = Rng.range_i(3, 5)
		item.long_range = item.range * 4

	# 3. Properties (1-2, no replacement, from a 4-item pool). A ranged (Ammo) weapon can never
	# also roll Reach — Reach is a melee-only concept (grants +1 tile melee range) and doesn't
	# make sense alongside a bow/crossbow-shaped result.
	var prop_pool: Array[String] = PROPERTY_POOL.duplicate()
	if item.is_ranged:
		prop_pool.erase("Reach")
	var prop_count: int = Rng.range_i(1, mini(2, prop_pool.size()))
	Rng.shuffle(prop_pool)
	var properties: Array[String] = prop_pool.slice(0, prop_count)

	if "Finesse" in properties:
		item.is_finesse = true
	if "Reach" in properties:
		item.is_reach = true
	if "Thrown" in properties:
		item.is_thrown = true
		item.uses_max = Rng.range_i(3, 6)
		item.uses_remaining = item.uses_max
		if item.is_ranged:
			# Share the already-rolled ranged range/long_range rather than re-rolling — one
			# consistent number for both the ranged attack and the throw (Item has only one
			# range/long_range field pair).
			pass
		else:
			item.range = Rng.range_i(2, 4)
			item.long_range = item.range * 4
	if "Versatile" in properties:
		item.is_versatile = true
		var vdie: Array = Rng.pick(DICE_SHAPES)
		item.versatile_die_min = vdie[0]
		item.versatile_die_max = vdie[1]

	# 4. Weapon mastery — always assigned; may be a "dead" mastery if the rolled shape doesn't
	# match its trigger context (e.g. Sap on a non-thrown weapon). Intentional chaos. Exception:
	# Slow is a ranged-only mastery (Longbow) in every real weapon in the game, so a melee result
	# (not is_ranged) can never roll it.
	var mastery_pool: Array[String] = Stats.ALL_WEAPON_MASTERIES.duplicate()
	if not item.is_ranged:
		mastery_pool.erase("Slow")
	item.weapon_mastery = Rng.pick(mastery_pool)

	# 5. Damage type — weighted: 70% Physical, 25% Elemental, 5% Magical.
	item.damage_type = _random_damage_type()

	# 6. Icon — reuse existing weapon sprites, heuristic by rolled shape.
	item.icon_path = _pick_icon(item)

	# 7. Name — random letters (deliberately absurdist).
	item.item_name = _random_name()

	# 8. Fixed price.
	item.gold_value = GOLD_VALUE
	item.silver_value = 0

	return item


static func _random_damage_type() -> String:
	var roll: int = Rng.roll(100)
	if roll <= 70:
		return Rng.pick(DAMAGE_TYPES_PHYSICAL)
	elif roll <= 95:
		return Rng.pick(DAMAGE_TYPES_ELEMENTAL)
	else:
		return Rng.pick(DAMAGE_TYPES_MAGICAL)


static func _random_name() -> String:
	var length: int = Rng.range_i(5, 8)
	var letters: PackedStringArray = []
	for _i: int in length:
		letters.append(NAME_LETTERS[Rng.range_i(0, NAME_LETTERS.length() - 1)])
	var word: String = "".join(letters)
	return word.capitalize()


static func _pick_icon(item: Item) -> String:
	var weapons := DungeonFloorData.WEAPONS_PATH
	var items := DungeonFloorData.ITEMS_PATH
	if item.is_ranged:
		if item.weapon_category == "Martial" and item.is_heavy:
			return items + "weapons/bow_arrow_gold.png"  # Heavy Crossbow-shaped
		elif item.is_heavy:
			return items + "weapons/bow.png"  # Longbow-shaped
		else:
			return items + "weapons/bow_arrow.png"  # Short Bow-shaped
	if item.is_two_handed and item.is_heavy:
		return weapons + "weapon_big_hammer.png"  # Maul-shaped
	if item.is_versatile:
		return weapons + "weapon_green_magic_staff.png"  # Quarterstaff-shaped
	if item.is_thrown:
		return weapons + "weapon_throwing_axe.png"  # Handaxe-shaped
	return weapons + "weapon_duel_sword.png"  # Rapier-shaped default
