class_name DungeonFloorData
extends RefCounted

const WEAPONS_PATH := "res://sprites/weapons/"
const OBJECTS_PATH := "res://sprites/objects/"
const ITEMS_PATH   := "res://sprites/items/"

# Scroll of <Spell> loot gate: an entry carrying "scroll_spell" is only eligible to spawn once the
# player could actually LEARN a spell of that level themselves (StandardSlotPool.
# highest_accessible_level()) — a level-1 character can never find a 2nd-level scroll, etc.
# Non-scroll entries (no "scroll_spell" key) are unaffected. Shared by every ITEM_POOL floor/loot
# eligibility filter in dungeon_floor.gd (_spawn_items(), _spawn_treasure(), _spawn_locked_doors()).
static func is_scroll_level_eligible(entry: Dictionary, character_level: int) -> bool:
	var spell_id: String = entry.get("scroll_spell", "")
	if spell_id == "":
		return true
	var s: Spell = SpellDb.get_spell(spell_id)
	if s == null:
		return true
	return s.level <= StandardSlotPool.highest_accessible_level(character_level)

const TRAP_POOL: Array = [
	{"name": "Bear Trap",  "sprite": "bear_trap.png",       "damage": 0, "msg": "The bear trap snaps shut on you!", "wall_trap": false},
	{"name": "Fire Trap",  "sprite": "fire_trap.png",        "damage": 8, "msg": "Jets of flame engulf you!",        "wall_trap": false},
	{"name": "Pit Spikes", "sprite": "pit_trap_spikes.png",  "damage": 7, "msg": "You fall into a spike pit!",       "wall_trap": false, "reusable": true},
	{"name": "Piston",     "sprite": "push_trap/front.png",  "damage": 0, "msg": "A piston blasts you!",             "wall_trap": true},
]

# item_type: 0=WEAPON 1=ARMOR 2=POTION 4=FOOD  (matches Item.Type enum)
# "gold" = Item.gold_value (base shop price; 0/absent = unpriced/not for sale) — read by
# DungeonFloor._build_floor_item() and mirrored in debug_panel.ALL_ITEMS per the item sync rule.
const ITEM_POOL: Array = [
	{"name": "Health Potion",  "type": 2, "icon": "potions/health/medium.png", "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4, "gold": 30},
	{"name": "Strength Potion","type": 2, "icon": "potions/mana/medium.png",    "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)", "gold": 80},
	{"name": "Ration",         "type": 4, "icon": "food/meat_cooked.png",                  "src": "items", "bonus_dmg": 0, "heal": 0, "food_value": 50, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Required for a long rest.", "gold": 15},
	{"name": "Mystery Meat",   "type": 4, "icon": "food/meat.png",                        "src": "items", "bonus_dmg": 0, "heal": 0, "food_value": 25, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Required for a long rest.", "gold": 8},
	# Healing Herb (special-rooms-economy-design.md §4.3, session 7d): fmin/fmax 99 is a
	# sentinel — no floor's current_floor ever reaches 99, so it never spawns via the generic
	# floor-eligibility filters (_spawn_items()/_spawn_locked_doors()); DungeonFloor._spawn_garden_items()
	# looks it up by name and places it directly. FOOD type + food_value counts toward the normal
	# long-rest fuel total; heal_amount is the one exception a FOOD item gets — see game_state.gd
	# use_item()'s FOOD branch.
	{"name": "Healing Herb",   "type": 4, "icon": "food/salad_flower_purple.png",           "src": "items", "bonus_dmg": 0, "heal": 4, "food_value": 25, "str_bonus": 0, "fmin": 99, "fmax": 99, "desc": "A fragrant garden herb. Eating it heals 4 HP and also counts as long-rest fuel.", "gold": 10},
	{"name": "Short Bow",      "type": 0, "icon": "weapons/bow_arrow.png",                 "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 6,  "desc": "Ranged, DEX-based. Normal range 4, long range 16 (DISADV). Requires Arrows.", "is_ranged": true, "range": 4, "long_range": 16, "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Vex", "ammo": "Arrow", "gold": 50},
	{"name": "Heavy Crossbow", "type": 0, "icon": "weapons/bow_arrow_gold.png",             "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "Ranged, DEX-based. Normal range 5, long range 20 (DISADV). Heavy (DEX 13+), two-handed. Requires Bolts.", "is_ranged": true, "range": 5, "long_range": 20, "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Push", "ammo": "Bolt", "heavy": true, "two_handed": true, "gold": 120},
	{"name": "Longbow",       "type": 0, "icon": "weapons/bow.png",                      "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Ranged, DEX-based. Normal range 8, long range 30 (DISADV). Heavy (DEX 13+), two-handed. Requires Arrows.", "is_ranged": true, "range": 8, "long_range": 30, "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 8, "mastery": "Slow", "ammo": "Arrow", "heavy": true, "two_handed": true, "gold": 50},
	# Tier 3 (weapon-tiers-design.md §3): moved from fmin=1 — 25gp/1d8-finesse/Martial doesn't
	# belong next to a 2sp Quarterstaff on floor 1, see that doc's §1 for the full rationale.
	{"name": "Rapier",         "type": 0, "icon": "weapon_duel_sword.png",               "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 4, "fmax": 10, "desc": "", "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 8, "mastery": "Vex", "finesse": true, "gold": 25},
	{"name": "Greatsword",     "type": 0, "icon": "weapon_knight_sword.png",            "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "", "dmg_type": "Slashing", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Graze", "heavy": true, "two_handed": true, "gold": 50},
	{"name": "Glaive",         "type": 0, "icon": "weapon_spear.png",                   "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "", "dmg_type": "Slashing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Graze", "heavy": true, "two_handed": true, "reach": true, "gold": 20},
	{"name": "Maul",           "type": 0, "icon": "weapon_big_hammer.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "", "dmg_type": "Bludgeoning", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Topple", "heavy": true, "two_handed": true, "gold": 10},
	# Tier 4 (weapon-tiers-design.md §3, §7): a real floor-loot entry — was guaranteed Barbarian
	# starting gear only (no fmin/fmax) until the Barbarian's starter was downgraded to a Spear
	# (see _give_barbarian_starting_items()); the Greataxe is now a genuine late-game find, the
	# only Cleave-mastery weapon in the game.
	{"name": "Greataxe",       "type": 0, "icon": "weapon_double_axe.png",            "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "", "dmg_type": "Slashing", "category": "Martial", "die_min": 1, "die_max": 12, "mastery": "Cleave", "heavy": true, "two_handed": true, "gold": 30},
	{"name": "Quarterstaff",   "type": 0, "icon": "weapon_green_magic_staff.png",     "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Bludgeoning", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Topple", "versatile": true, "silver": 2},
	{"name": "Spear",          "type": 0, "icon": "weapon_spear.png",                 "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Sap", "versatile": true, "thrown": true, "range": 2, "long_range": 6, "uses_max": 5, "gold": 1},
	{"name": "Handaxe",        "type": 0, "icon": "weapon_throwing_axe.png",        "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Slashing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Vex", "light": true, "thrown": true, "range": 2, "long_range": 6, "uses_max": 5, "gold": 5},
	{"name": "Dagger",         "type": 0, "icon": "weapon_knife.png",              "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 4, "mastery": "Nick", "finesse": true, "light": true, "thrown": true, "range": 2, "long_range": 6, "uses_max": 5, "gold": 2},
	# Scimitar: Martial, not Thrown (unlike Dagger/Handaxe, the two other Nick-mastery/Light
	# weapons) — a plain melee-only Finesse+Light sword. Second Nick-mastery weapon alongside
	# Dagger (real 5e 2024 both carry it).
	{"name": "Scimitar",       "type": 0, "icon": "weapon_scimitar.png",           "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Slashing", "category": "Martial", "die_min": 1, "die_max": 6, "mastery": "Nick", "finesse": true, "light": true, "gold": 25},
	{"name": "Javelin",        "type": 0, "icon": "weapon_spear.png",              "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Slow", "thrown": true, "range": 3, "long_range": 12, "uses_max": 5, "silver": 5},
	{"name": "Torch",          "type": 0, "icon": "weapon_torch.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Click while equipped to light it — burns 100 turns, granting +1 FOV and (in Main Hand) +2d4 Fire on hit. Thrown and lodged in an enemy, it sets them ablaze for 2d4 Fire each round until doused or they die, and casts a radius-1 glow around them; lying on the ground it casts a radius-2 glow instead. Can be equipped in either hand like a Shield. Burns out permanently into a Burnt Torch.", "dmg_type": "Bludgeoning", "category": "Simple", "die_min": 1, "die_max": 4, "torch": true, "thrown": true, "range": 2, "long_range": 4, "uses_max": 1, "gold": 10},
	{"name": "Arrow",          "type": 7, "icon": "ammo/arrow.png",             "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Short Bow and Longbow.", "qty": 6, "gold": 1},
	{"name": "Bolt",           "type": 7, "icon": "ammo/arrow_gold.png",             "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Heavy Crossbow.", "qty": 6, "gold": 1},
	{"name": "Buckshot",       "type": 7, "icon": "misc/coin_gold.png",             "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for muskets and other firearms.", "qty": 6, "gold": 1},
	{"name": "Thief Tools",    "type": 7, "icon": "misc/key_iron.png",                    "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Disarm traps, lock doors. Consumed on failure.", "qty": 2, "gold": 25},
	# Mold: Blacksmith crafting material (scripts/items/CLAUDE.md's "WeaponForge" section). Sentinel
	# fmin/fmax=99 keeps it out of every generic floor-loot roll — its only spawn path is
	# DungeonFloor._spawn_mold()'s guaranteed once-per-run placement (scripts/world/CLAUDE.md).
	{"name": "Mold",           "type": 7, "icon": "Materials/plate/iron.png",           "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 99, "fmax": 99, "desc": "A strange mold. A Blacksmith could forge it into a weapon — for a price."},
	# Poisoned Arrow: the one dart inside a Tripwire trap's hidden dispenser (scripts/world/CLAUDE.md's
	# "Tripwire trap"). Sentinel fmin/fmax=99 keeps it out of every generic floor-loot roll — its only
	# spawn path is DungeonFloor.loot_dispenser(). Single-use thrown weapon; a landed hit also poisons
	# the target (player_throw_tool.gd's item_name == "Poisoned Arrow" check).
	{"name": "Poisoned Arrow", "type": 0, "icon": "ammo/arrow.png",              "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 99, "fmax": 99, "desc": "A single dart tipped with venom. Poisons whatever it strikes.", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 4, "finesse": true, "light": true, "thrown": true, "range": 4, "long_range": 12, "uses_max": 1, "gold": 15},
	{"name": "Shield",         "type": 1, "icon": "shields/wood.png",                "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Requires shield proficiency; can't be worn with a two-handed Main Hand weapon, and blocks spellcasting while equipped.", "bonus_ac": 2, "is_shield": true, "gold": 40},
	# Body armor (Item.armor_category — see Item.gd, GameState.can_equip_armor()/ARMOR_CHANGE_TURNS
	# and Stats.recalc_ac()). No dedicated armor sprites exist yet — every entry placeholder-reuses
	# sprites/items/materials/plate/iron.png (same "no art yet" precedent as several weapons above).
	# 1=Light armor_cat, 2=Medium, 3=Heavy. dex_cap: -1=unlimited, N=capped at N, 0=none.
	{"name": "Padded Armor",           "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "armor_cat": 1, "base_ac": 11, "dex_cap": -1, "stealth_disadv": true, "gold": 5},
	{"name": "Leather Armor",          "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "armor_cat": 1, "base_ac": 11, "dex_cap": -1, "gold": 10},
	{"name": "Studded Leather Armor",  "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "", "armor_cat": 1, "base_ac": 12, "dex_cap": -1, "gold": 45},
	{"name": "Hide Armor",             "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "armor_cat": 2, "base_ac": 12, "dex_cap": 2, "gold": 10},
	{"name": "Chain Shirt",            "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "", "armor_cat": 2, "base_ac": 13, "dex_cap": 2, "gold": 50},
	{"name": "Scale Mail",             "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "", "armor_cat": 2, "base_ac": 14, "dex_cap": 2, "stealth_disadv": true, "gold": 50},
	{"name": "Breastplate",            "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 4, "fmax": 10, "desc": "", "armor_cat": 2, "base_ac": 14, "dex_cap": 2, "gold": 400},
	{"name": "Half Plate Armor",       "type": 1, "icon": "materials/plate/gold.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "", "armor_cat": 2, "base_ac": 15, "dex_cap": 2, "stealth_disadv": true, "gold": 750},
	{"name": "Ring Mail",              "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "", "armor_cat": 3, "base_ac": 14, "dex_cap": 0, "stealth_disadv": true, "gold": 30},
	{"name": "Chain Mail",             "type": 1, "icon": "materials/plate/iron.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Requires 13 STR.", "armor_cat": 3, "base_ac": 16, "dex_cap": 0, "str_req": 13, "stealth_disadv": true, "gold": 75},
	{"name": "Splint Armor",           "type": 1, "icon": "materials/plate/gold.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Requires 15 STR.", "armor_cat": 3, "base_ac": 17, "dex_cap": 0, "str_req": 15, "stealth_disadv": true, "gold": 200},
	{"name": "Plate Armor",            "type": 1, "icon": "materials/plate/gold.png", "src": "items", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 8, "fmax": 10, "desc": "Requires 15 STR.", "armor_cat": 3, "base_ac": 18, "dex_cap": 0, "str_req": 15, "stealth_disadv": true, "gold": 1500},
	# Scroll of <Spell> — a single one-shot cast of the named spell, castable by ANY class
	# (see Item.scroll_spell_id / SpellEffects' caster-optional attack-bonus/save-DC helpers:
	# non-casters use their INT modifier + proficiency bonus). Reusing the spell's own icon since
	# no dedicated scroll sprite exists yet. Always casts at the spell's base level — no upcasting.
	{"name": "Scroll of Fire Bolt",     "type": 3, "icon": "fire_bolt.png",      "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Fire Bolt once, then it crumbles to dust.", "scroll_spell": "fire_bolt", "gold": 25},
	{"name": "Scroll of Ray of Frost",  "type": 3, "icon": "ray_of_frost.png",   "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Ray of Frost once, then it crumbles to dust.", "scroll_spell": "ray_of_frost", "gold": 25},
	{"name": "Scroll of Shocking Grasp","type": 3, "icon": "shocking_grasp.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Shocking Grasp once, then it crumbles to dust.", "scroll_spell": "shocking_grasp", "gold": 25},
	{"name": "Scroll of Toll the Dead","type": 3, "icon": "toll_the_dead.png",  "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Toll the Dead once, then it crumbles to dust.", "scroll_spell": "toll_the_dead", "gold": 25},
	{"name": "Scroll of Blade Ward",   "type": 3, "icon": "blade_ward.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Blade Ward once, then it crumbles to dust.", "scroll_spell": "blade_ward", "gold": 25},
	{"name": "Scroll of Thunderclap",  "type": 3, "icon": "thunderclap.png",   "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Thunderclap once, then it crumbles to dust.", "scroll_spell": "thunderclap", "gold": 25},
	{"name": "Scroll of Mind Sliver",  "type": 3, "icon": "mind_sliver.png",   "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Mind Sliver once, then it crumbles to dust.", "scroll_spell": "mind_sliver", "gold": 25},
	{"name": "Scroll of Light",        "type": 3, "icon": "light.png",        "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Light once, then it crumbles to dust.", "scroll_spell": "light", "gold": 15},
	{"name": "Scroll of Magic Missile", "type": 3, "icon": "magic_missile.png",  "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Magic Missile once, then it crumbles to dust.", "scroll_spell": "magic_missile", "gold": 60},
	{"name": "Scroll of Shield",        "type": 3, "icon": "shield.png",        "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Shield once, then it crumbles to dust.", "scroll_spell": "shield", "gold": 60},
	{"name": "Scroll of Mage Armor",    "type": 3, "icon": "mage_armor.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Mage Armor once, then it crumbles to dust.", "scroll_spell": "mage_armor", "gold": 60},
	{"name": "Scroll of Misty Step",    "type": 3, "icon": "misty_step.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 4, "fmax": 10, "desc": "Reading this casts Misty Step once, then it crumbles to dust.", "scroll_spell": "misty_step", "gold": 100},
	{"name": "Scroll of Fireball",      "type": 3, "icon": "fireball.png",      "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 6, "fmax": 10, "desc": "Reading this casts Fireball once, then it crumbles to dust.", "scroll_spell": "fireball", "gold": 180},
	{"name": "Scroll of Chromatic Orb", "type": 3, "icon": "chromatic_orb.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Chromatic Orb once, then it crumbles to dust.", "scroll_spell": "chromatic_orb", "gold": 60},
	{"name": "Scroll of Burning Hands", "type": 3, "icon": "burning_hands.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Burning Hands once, then it crumbles to dust.", "scroll_spell": "burning_hands", "gold": 60},
	{"name": "Scroll of Witch Bolt",    "type": 3, "icon": "witch_bolt.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Witch Bolt once, then it crumbles to dust.", "scroll_spell": "witch_bolt", "gold": 60},
	{"name": "Scroll of Expeditious Retreat", "type": 3, "icon": "expeditious_retreat.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Expeditious Retreat once, then it crumbles to dust.", "scroll_spell": "expeditious_retreat", "gold": 60},
	{"name": "Scroll of False Life",   "type": 3, "icon": "false_life.png",   "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts False Life once, then it crumbles to dust.", "scroll_spell": "false_life", "gold": 60},
	{"name": "Scroll of Fog Cloud",    "type": 3, "icon": "fog_cloud.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Fog Cloud once, then it crumbles to dust.", "scroll_spell": "fog_cloud", "gold": 60},
	{"name": "Scroll of Invisibility", "type": 3, "icon": "invisibility.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Reading this casts Invisibility once, then it crumbles to dust.", "scroll_spell": "invisibility", "gold": 100},
	{"name": "Scroll of Darkness",    "type": 3, "icon": "darkness.png",    "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Reading this casts Darkness once, then it crumbles to dust.", "scroll_spell": "darkness", "gold": 100},
	{"name": "Scroll of Longstrider", "type": 3, "icon": "longstrider.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Longstrider once, then it crumbles to dust.", "scroll_spell": "longstrider", "gold": 50},
	{"name": "Scroll of Detect Magic", "type": 3, "icon": "detect_magic.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Detect Magic once, then it crumbles to dust.", "scroll_spell": "detect_magic", "gold": 50},
	{"name": "Scroll of Pass Without Trace", "type": 3, "icon": "pass_without_trace.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Pass Without Trace once, then it crumbles to dust.", "scroll_spell": "pass_without_trace", "gold": 60},
	# Full spell-coverage pass: every remaining SpellDb.get_spell() id (lineage/legacy-only grants
	# included) now has a matching scroll — see scripts/items/CLAUDE.md's "Scroll of <Spell>" for
	# why these were previously missing (lineage-only spells were deliberately excluded). Only
	# "hellish_rebuke" stays without one — it's a reaction-toggle ability
	# (GameState._build_hellish_rebuke_ability()), not a normal on-demand cast, so it can't go
	# through the generic on_scroll_primed()/begin_cast() flow every other scroll uses.
	{"name": "Scroll of Eldritch Blast", "type": 3, "icon": "eldritch_blast.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Eldritch Blast once, then it crumbles to dust.", "scroll_spell": "eldritch_blast", "gold": 25},
	{"name": "Scroll of Faerie Fire", "type": 3, "icon": "faerie_fire.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Faerie Fire once, then it crumbles to dust.", "scroll_spell": "faerie_fire", "gold": 60},
	{"name": "Scroll of Poison Spray", "type": 3, "icon": "poison_spray.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Poison Spray once, then it crumbles to dust.", "scroll_spell": "poison_spray", "gold": 25},
	{"name": "Scroll of Chill Touch", "type": 3, "icon": "chill_touch.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Chill Touch once, then it crumbles to dust.", "scroll_spell": "chill_touch", "gold": 25},
	{"name": "Scroll of Ray of Sickness", "type": 3, "icon": "ray_of_sickness.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Ray of Sickness once, then it crumbles to dust.", "scroll_spell": "ray_of_sickness", "gold": 60},
	{"name": "Scroll of Hold Person", "type": 3, "icon": "hold_person.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Reading this casts Hold Person once, then it crumbles to dust.", "scroll_spell": "hold_person", "gold": 100},
	{"name": "Scroll of Tasha's Hideous Laughter", "type": 3, "icon": "hideous_laughter.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Reading this casts Tasha's Hideous Laughter once, then it crumbles to dust.", "scroll_spell": "hideous_laughter", "gold": 60},
	{"name": "Scroll of Ray of Enfeeblement", "type": 3, "icon": "ray_of_enfeeblement.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Reading this casts Ray of Enfeeblement once, then it crumbles to dust.", "scroll_spell": "ray_of_enfeeblement", "gold": 100},
	{"name": "Scroll of Minor Illusion", "type": 3, "icon": "minor_illusion.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Minor Illusion once, then it crumbles to dust.", "scroll_spell": "minor_illusion", "gold": 25},
	{"name": "Scroll of Speak with Animals", "type": 3, "icon": "speak_with_animals.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Speak with Animals once, then it crumbles to dust.", "scroll_spell": "speak_with_animals", "gold": 25},
	{"name": "Scroll of Mending", "type": 3, "icon": "mending.png", "src": "spells", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Reading this casts Mending once, then it crumbles to dust.", "scroll_spell": "mending", "gold": 25},
]

const BOSS_POOL: Array = [
	{"boss_id": "big_demon",   "display_name": "Big Demon",   "sprite": "big_demon",   "idle_frames": 4, "run_frames": 4, "floor": 5,  "hp": 80,  "hp_per_floor": 0, "dmg_min": 8,  "dmg_max": 14, "armor": 3, "ac": 16, "exp": 100,
	 "cr": 5, "creature_type": "Fiend", "legendary_resistances": 3},
	{"boss_id": "necromancer", "display_name": "Necromancer", "sprite": "necromancer", "idle_frames": 4, "run_frames": 4, "floor": 10, "hp": 120, "hp_per_floor": 0, "dmg_min": 10, "dmg_max": 18, "armor": 4, "ac": 13, "exp": 200,
	 "cr": 8, "creature_type": "Humanoid",
	 "idle_fmt": "res://sprites/characters/enemies/Necromancer/anim_%d.png",
	 "run_fmt":  "res://sprites/characters/enemies/Necromancer/anim_%d.png"},
]

const ENEMY_POOL: Array = [
	# Goblin Minion — Small Fey, CN, CR 1/8. HP 2d6 (avg 7), AC 12 (natural armor).
	# STR 8 (-1) DEX 15 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1). Speed 1 (default).
	# Skills: Stealth +6 — flavor only, no mechanical consumer yet (see Goblin Warrior's note above).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 5 -> 6 here).
	# Nimble Escape: after being hit by a melee attack, its next action(s) become fleeing the
	# attacker for a random 1-5 turns instead of acting normally, never provoking an Opportunity
	# Attack while doing so — Enemy.escape_turns/on_melee_hit()/_flee_from().
	# Dagger, melee: +4 to hit (DEX+prof, finesse), reach 1, 1 target, 1d4+2 Piercing (encoded as a
	# single-entry multiattack sub-attack so the hit gets a real Piercing damage type/name instead
	# of the top-level-stats default of Bludgeoning).
	# Dagger, thrown (pool "thrown_weapon", one-shot per life — Enemy._thrown_weapon_used,
	# "flee_only": true): a parting shot thrown the instant Nimble Escape's flee state (melee-hit
	# triggered, escape_turns > 0) WEARS OFF — never mid-flee, and never off a ranged/spell hit
	# (Fire Bolt etc. never sets escape_turns at all) — and only if the target still isn't
	# adjacent at that moment (close enough, it just stabs instead). NOT a general chase-opener
	# before closing to melee — see Enemy._decide_action()'s `escape_turns == 0` check, reached
	# only on the turn the counter's own decrement brings it to zero. Same 1d4+2 Piercing, rolled
	# with Disadvantage (reuses _attack_player()/_attack_companion()'s `long_shot` param purely
	# for its Disadvantage side effect, not its usual normal/long-range meaning). Range capped at
	# 4 tiles (authored judgment call — no player-facing "thrown Dagger at unlimited range" item
	# exists to mirror). Once thrown, the Dagger is gone for good: every attack after this reverts
	# to an unarmed Fist strike (pool "unarmed_fallback") — see Enemy._attack_target()'s dispatch.
	# Contrast with Orc Warrior's Javelin below, which has no "flee_only" key and is instead a
	# general opener thrown whenever CHASING/SEARCHING and not yet adjacent.
	# Fists (pool "unarmed_fallback"): STR-based (+prof) to-hit despite the Dagger being DEX-based —
	# a per-sub "attack_stat" override (Enemy._attack_bonus_for()) so this one swing ignores
	# attack_profile's enemy-wide "dex" default. Flat 1 Bludgeoning damage (1 + STR mod -1, floored
	# at 1 — pre-baked into dmg_min/dmg_max like every other authored attack, not computed at
	# runtime) — "can't go under 1" per spec.
	# Recovering the thrown Dagger: DungeonFloor.queue_thrown_weapon_drop()/Enemy.die() — 50%
	# chance (this pool entry's default "drop_chance") to find it (dropped at whoever it was
	# thrown at) resolved on the player's next turn after THIS goblin dies, whether or not the
	# throw actually landed (same generic mechanism Orc Warrior's Javelin below reuses).
	{"enemy_id": "goblin_minion", "display_name": "Goblin Minion", "sprite": "goblin", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 3,  "hp": 7,  "hp_per_floor": 1, "dmg_min": 3, "dmg_max": 6, "armor": 0, "ac": 12, "exp": 4,
	 "cr": 0.125, "creature_type": "Fey", "size_category": "Small",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}],
	 "multiattack": [{"name": "Dagger", "count": 1, "dmg_min": 3, "dmg_max": 6, "damage_type": "Piercing"}],
	 "thrown_weapon": {"name": "Dagger", "dmg_min": 3, "dmg_max": 6, "damage_type": "Piercing", "range": 2, "flee_only": true},
	 "unarmed_fallback": {"name": "Fists", "dmg_min": 1, "dmg_max": 1, "damage_type": "Bludgeoning", "attack_stat": "str"}},
	# Giant Rat — Small Beast, unaligned, CR 1/8, proficiency +2. HP 7, AC 13.
	# STR 7 (-2) DEX 16 (+3) CON 11 (+0) INT 2 (-4) WIS 10 (+0) CHA 4 (-3). Speed 1 (default/30ft).
	# Darkvision: +1 to the default enemy notice/LOS radius. Passive Perception 10 (10 + WIS mod).
	# Bite: +5 to hit (DEX+prof, finesse — attack_profile.attack_stat), 1d4+3 Piercing.
	# Pack Tactics: Advantage on this attack whenever another awake ally is within 5 ft of the
	# target — see the traits dispatch in enemy.gd's _attack_player()/_attack_companion().
	# Visual: random Gray/Brown/White sprite variant per spawn, sliced from a sprite sheet — see
	# enemy.gd's _setup_sheet_animations(). Idle/Run only; the art's Attack/Hurt/Dead/Sniff/Stand/
	# Walk sheets go unused, same as every other enemy's un-wired animation states (see CLAUDE.md).
	{"enemy_id": "giant_rat", "display_name": "Giant Rat", "sprite": "rat",
	 "sprite_variants": ["Gray", "Brown", "White"], "idle_frames": 6, "run_frames": 6,
	 "sprite_frame_size": {"w": 64, "h": 64}, "sprite_scale": 0.35,
	 "floor_min": 1, "floor_max": 2, "hp": 7, "hp_per_floor": 1, "dmg_min": 4, "dmg_max": 7,
	 "armor": 0, "ac": 13, "exp": 3,
	 "cr": 0.125, "creature_type": "Beast", "size_category": "Small",
	 "mods": {"str": -2, "dex": 3, "con": 0, "int": -4, "wis": 0, "cha": -3},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 10,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "pack_tactics"}],
	 "multiattack": [{"name": "Bite", "count": 1, "dmg_min": 4, "dmg_max": 7, "damage_type": "Piercing"}]},
	# Orc Warrior — Medium Humanoid (Orc), CR 1/2, proficiency +2. HP 15, AC 13.
	# STR 16 (+3) DEX 12 (+1) CON 16 (+3) INT 7 (-2) WIS 11 (+0) CHA 10 (+0). Speed 1 (default).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 5 -> 6 here).
	# Passive Perception = 10 + WIS mod = 10.
	# Greataxe: +5 to hit (STR+prof — the default melee attack_stat, no "attack_profile" override
	# needed), reach 1, 1d12+3 Slashing — single-entry multiattack sub-attack for the real damage
	# type (same pattern as Skeleton's Shortsword above).
	# Javelin (pool "thrown_weapon"/"unarmed_fallback", one-shot per life — the exact same generic
	# mechanism as Goblin Minion's Dagger above, just re-authored with Javelin/Fists numbers): +5 to
	# hit (STR, same as the Greataxe — no "attack_stat" override needed), range 3, 1d6+3 Piercing,
	# rolled with Disadvantage (reuses _attack_player()/_attack_companion()'s `long_shot` param).
	# Whenever NOT yet adjacent, thrown once instead of closing to melee. Unlike Goblin's Dagger
	# (thrown AND melee weapon in one — losing it means Fists forever), the Javelin is a SEPARATE
	# weapon from the Greataxe: Enemy._attack_target() only falls back to "unarmed_fallback" when
	# the thrown weapon's name matches the multiattack's own weapon name (same weapon lost), so
	# once the Javelin is gone this Orc keeps swinging its Greataxe normally in melee — it never
	# permanently goes bare-fisted the way a Goblin Minion does.
	# Recovery: 50% chance (this pool entry's default "drop_chance", same as Goblin's Dagger) to
	# find it wherever the target stands when this Orc eventually dies. "random_uses": true — the
	# recovered Javelin is already partially worn down (a random 1 to "drop_uses_max" uses left),
	# not pristine — the one difference from Goblin's Dagger, which drops fully intact.
	# Aggressive trait: while it can see its target, gets +1 movement step this turn (Enemy._act_toward()'s
	# bonus_moves param, wired from _execute_action()'s "act_toward" case whenever _has_trait("aggressive")
	# and the target is visible) — covers "move + move" (still out of range after the bonus step) and
	# "move + attack" (in range after either step, _act_toward() re-checks range every step and attacks
	# immediately) for free; "attack + move" and "just attack" are the two cases where it's already
	# adjacent, handled by the normal _act_toward_or_ability() dispatch (attacks immediately, no bonus
	# movement spent) — D&D's own text only grants a movement bonus, never a second attack.
	{"enemy_id": "orc_warrior",   "display_name": "Orc Warrior", "sprite": "orc_warrior", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,  "hp": 15, "hp_per_floor": 2, "dmg_min": 4, "dmg_max": 15, "armor": 0, "ac": 13, "exp": 8,
	 "cr": 0.5, "creature_type": "Humanoid", "size_category": "Medium",
	 "mods": {"str": 3, "dex": 1, "con": 3, "int": -2, "wis": 0, "cha": 0},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 10,
	 "traits": [{"id": "aggressive"}],
	 "multiattack": [{"name": "Greataxe", "count": 1, "dmg_min": 4, "dmg_max": 15, "damage_type": "Slashing"}],
	 "thrown_weapon": {"name": "Javelin", "range": 3, "dmg_min": 4, "dmg_max": 9, "damage_type": "Piercing",
		"icon": "weapon_spear.png", "drop_die_min": 1, "drop_die_max": 6, "weapon_category": "Simple",
		"is_finesse": false, "is_light": false, "weapon_mastery": "", "drop_uses_max": 5, "random_uses": true},
	 "unarmed_fallback": {"name": "Fists", "dmg_min": 4, "dmg_max": 4, "damage_type": "Bludgeoning", "attack_stat": "str"}},
	# Goblin Warrior — Small Fey, CE, CR 1/4. HP 10, AC 15 (natural armor — no shield).
	# STR 8 (-1) DEX 15 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1). Speed 1 (default).
	# Skills: Stealth +6 — flavor only, no mechanical consumer yet (this codebase's Stealth system
	# is player-sneaks-past-enemy via Passive Perception, not the reverse; nothing rolls an enemy's
	# own Stealth check today).
	# Darkvision: +1 to the default enemy notice/LOS radius (senses.sight_bonus).
	# Passive Perception = 10 + WIS mod = 9.
	# Scimitar: +4 to hit (DEX+prof, finesse — attack_profile.attack_stat), reach 1, 1d6+2 Slashing —
	# single-entry multiattack sub-attack for the real damage type (same pattern as goblin_minion's
	# Dagger above).
	# Nimble Escape: after being hit by a melee attack, its next action(s) become fleeing the
	# attacker for a random 1-5 turns instead of acting normally, and that flight never provokes an
	# Opportunity Attack — see Enemy.escape_turns/on_melee_hit()/_flee_from() in enemy.gd.
	# Advantage bonus: whenever this attack (Scimitar included) lands with net Advantage, deals an
	# extra 1d4 damage — Enemy._advantage_bonus_sides()/_attack_player()/_attack_companion().
	{"enemy_id": "goblin_warrior", "display_name": "Goblin Warrior", "sprite": "goblin", "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 8, "armor": 0, "ac": 15, "exp": 10,
	 "cr": 0.25, "creature_type": "Fey", "size_category": "Small",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}, {"id": "advantage_bonus", "sides": 4}],
	 "multiattack": [{"name": "Scimitar", "count": 1, "dmg_min": 3, "dmg_max": 8, "damage_type": "Slashing"}]},
	{"enemy_id": "orc_shaman",    "display_name": "Orc Shaman",  "sprite": "orc_shaman",  "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 0, "ac": 10, "exp": 12,
	 "cr": 0.25, "creature_type": "Humanoid", "size_category": "Medium"},
	{"enemy_id": "masked_orc",    "display_name": "Masked Orc",  "sprite": "masked_orc",  "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 12, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 1, "ac": 13, "exp": 10,
	 "cr": 0.25, "creature_type": "Humanoid", "size_category": "Medium"},
	# Skeleton — Medium Undead, CR 1/4, proficiency +2. HP 13, AC 14 (natural armor).
	# STR 10 (+0) DEX 14 (+2) CON 15 (+2) INT 6 (-2) WIS 8 (-1) CHA 3 (-4). Speed 1 (default).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 5 -> 6 here).
	# Passive Perception = 10 + WIS mod = 9.
	# Shortsword: +4 to hit (DEX+prof), reach 1, 1d6+2 Piercing — encoded as a single-entry
	# multiattack sub-attack so the hit gets a real Piercing damage type instead of the top-level
	# stats' default Bludgeoning (same reasoning as Goblin Minion's Dagger above).
	# Shortbow: +4 to hit (DEX+prof), range 4 (normal)/16 (long, DISADV via "long_range" —
	# Enemy._ability_is_long_shot()), 1d6+2 Piercing — encoded as an uncapped "abilities" entry
	# (no cooldown/uses_max/recharge = always ready), which the shared _pick_ready_ability() picks
	# over melee approach whenever the target is visible and NOT already adjacent — switches to
	# the Shortsword automatically once it closes in. DnD's 80/320 ft (16/64 squares) scaled down
	# /20, not the /10 used for spell ranges — see scripts/entities/CLAUDE.md's "Ranged distance
	# scaling convention" note for why shooting ranges get the steeper divisor.
	{"enemy_id": "skeleton",      "display_name": "Skeleton",    "sprite": "skelet",      "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 13, "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 8, "armor": 0, "ac": 14, "exp": 9,
	 "cr": 0.25, "creature_type": "Undead", "size_category": "Medium",
	 "mods": {"str": 0, "dex": 2, "con": 2, "int": -2, "wis": -1, "cha": -4},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "damage_vulnerabilities": ["Bludgeoning"],
	 "damage_immunities": ["Poison"],
	 "condition_immunities": ["poisoned", "exhausted"],
	 "attack_profile": {"attack_stat": "dex"},
	 "multiattack": [{"name": "Shortsword", "count": 1, "dmg_min": 3, "dmg_max": 8, "damage_type": "Piercing"}],
	 "abilities": [{"id": "skeleton_shortbow", "name": "Shortbow", "range": 4, "long_range": 16, "dmg_min": 3, "dmg_max": 8, "damage_type": "Piercing"}]},
	# Zombie — Medium Undead, CR 1/4, proficiency +2. HP 22, AC 8.
	# STR 13 (+1) DEX 6 (-2) CON 16 (+3) INT 3 (-4) WIS 6 (-2) CHA 5 (-3).
	# Speed 20 ft (below the 30 ft baseline) -> "speed": {"moves": 2, "per": 3}: skips its movement
	# roughly 1 turn in 3 (Enemy._tick_speed_gate(), see scripts/entities/CLAUDE.md's "Movement
	# speed scaling" note — still attacks if already adjacent on a no-move turn, same shape as
	# rooted_turns). Darkvision: +1 to the default enemy notice/LOS radius (FOV_RADIUS 5 -> 6).
	# Passive Perception = 10 + WIS mod = 8.
	# Undead Fortitude (dc_base 5): on a would-be-lethal hit, CON check vs 5 + damage taken to stay
	# at 1 HP instead — EXCEPT a Radiant killing blow or a critical hit, which the generic trait
	# dispatch now excludes (Enemy.take_typed_damage()'s is_crit param — Zombie is the worked example
	# that motivated adding it).
	# Slam: +3 to hit (STR+prof — default melee attack_stat), reach 1, 1d6+1 Bludgeoning — single-entry
	# multiattack sub-attack for the real damage type/name.
	{"enemy_id": "zombie",        "display_name": "Zombie",      "sprite": "tiny_zombie", "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 7,  "hp": 22, "hp_per_floor": 3, "dmg_min": 2, "dmg_max": 7, "armor": 0, "ac": 8, "exp": 9,
	 "cr": 0.25, "creature_type": "Undead",
	 "mods": {"str": 1, "dex": -2, "con": 3, "int": -4, "wis": -2, "cha": -3},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 8,
	 "speed": {"moves": 2, "per": 3},
	 "damage_immunities": ["Poison"],
	 "condition_immunities": ["poisoned"],
	 "traits": [{"id": "undead_fortitude", "dc_base": 5}],
	 "multiattack": [{"name": "Slam", "count": 1, "dmg_min": 2, "dmg_max": 7, "damage_type": "Bludgeoning"}]},
	{"enemy_id": "wogol",         "display_name": "Wogol",       "sprite": "wogol",       "idle_frames": 4, "run_frames": 4, "floor_min": 5, "floor_max": 8,  "hp": 14, "hp_per_floor": 3, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 13, "exp": 15,
	 "cr": 0.5, "creature_type": "Beast"},
	# Imp — Small Fiend (Devil), LE, CR 1, proficiency +2. HP 21, AC 13 (natural armor).
	# STR 6 (-2) DEX 17 (+3) CON 13 (+1) INT 11 (+0) WIS 12 (+1) CHA 14 (+2).
	# Skills: Deception +4, Insight +3, Stealth +5 — flavor only, no mechanical consumer yet (same
	# caveat as Goblin's Stealth +6 above).
	# Superior darkvision: +2 to the default enemy notice/LOS radius (senses.sight_bonus).
	# Passive Perception = 10 + WIS mod = 11.
	# Speed: walks (20 ft, "speed_ground": {"moves":2,"per":3}) OR flies (40 ft, "speed_flying":
	# {"moves":4,"per":3}) depending on behavior — Enemy._tick_speed_gate() picks "speed_flying"
	# while CHASING/SEARCHING (knowingly pursuing/last saw the target) and "speed_ground" otherwise
	# (SLEEPING/STATIONARY/ROAMING). Both pool keys are read generically; any future enemy that
	# wants a single flat speed regardless of behavior just keeps using the legacy "speed" key.
	# Magic Resistance (trait "magic_resistance"): Advantage on saves against spells — implemented
	# as a `magical` flag on Enemy.resist_check_detailed(), rolling the die with Advantage when both
	# the flag and this trait are present. Threaded through every SAVE-resolution spell in
	# spell_effects.gd (Ray of Frost, Toll the Dead, Mind Sliver's own save, Thunderclap, Fireball) —
	# NOT weapon-mastery saves (Push/Topple/Grip of the Forest/Branching Strike), which aren't spells.
	# Shape Shift (trait "shape_shift"): can secretly transform into a Rat, Raven, or Spider (same
	# stats, only speed differs — all three use {"moves":2,"per":3}) while CHASING/SEARCHING and the
	# target hasn't seen it for at least 1 turn (invisible counts) — see Enemy._tick_shape_shift().
	# 50% roll per eligible turn, no turn cost. 50% chance to already be shape-shifted (random form)
	# at spawn. Reverts to true Imp form immediately after taking any damage. **No dedicated
	# rat/raven/spider sprites exist yet** (checked `sprites/characters/`) — mechanically fully wired
	# (speed changes, "true form" tracking, damage-triggered revert) but visually a no-op today,
	# per direct owner decision (asset debt, not a missing feature) — swap in real sprites via
	# `_setup_animations()`'s sprite-prefix lookup once art exists, no other change needed.
	# Invisibility (pool "invisibility", cooldown 5 turns, duration up to 600 turns): while CHASING/
	# SEARCHING (pursuing) and NOT yet adjacent to the target, and the cooldown is ready, casts
	# Invisibility on itself instead of closing distance — costs the turn (a real action, unlike
	# Nimble Escape's free-form flee). Ends immediately on attacking (Sting) or, per the mirrored
	# player spell's own rule, would end on casting another spell (N/A for a non-caster enemy).
	# Hides its own sprite (`Enemy.is_hidden_from_player()`) and is skipped by every direct
	# click-target resolution (`DungeonFloor.get_targetable_enemy_at()`) — but NOT by bump-into-move
	# attacks or AoE spells (Fireball/Thunderclap), which don't target by click at all. See
	# "Invisibility" in this file's own header section below for the full mechanism (shared with the
	# player-castable level-2 spell of the same name).
	# Sting: +5 to hit (DEX+prof), reach 1, 1d6+3 Piercing AND 2d6 Poison on the SAME hit (one attack
	# roll, two independent typed damage instances/floaters/log segments — pool "multiattack" sub-
	# entry's new optional "extra" key, mirrors the player-side Judgement Day/Fireball-friendly-fire
	# "one hit, multiple damage types" convention). Imp's own Poison IMMUNITY doesn't apply to
	# damage it DEALS, only damage it takes — no interaction between the two.
	{"enemy_id": "imp",           "display_name": "Imp",         "sprite": "imp",         "idle_frames": 4, "run_frames": 4, "floor_min": 6, "floor_max": 9,  "hp": 21, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 9, "armor": 0, "ac": 13, "exp": 22,
	 "cr": 1, "creature_type": "Fiend", "size_category": "Tiny",
	 "mods": {"str": -2, "dex": 3, "con": 1, "int": 0, "wis": 1, "cha": 2},
	 "senses": {"sight_bonus": 2},
	 "passive_perception": 11,
	 "attack_profile": {"attack_stat": "dex"},
	 "speed_ground": {"moves": 2, "per": 3},
	 "speed_flying": {"moves": 4, "per": 3},
	 "damage_resistances": ["Cold"],
	 "damage_immunities": ["Fire", "Poison"],
	 "condition_immunities": ["poisoned"],
	 "traits": [{"id": "magic_resistance"}, {"id": "shape_shift"}],
	 "invisibility": {"cooldown": 5, "duration": 600},
	 "multiattack": [{"name": "Sting", "count": 1, "dmg_min": 4, "dmg_max": 9, "damage_type": "Piercing",
	                  "extra": {"dmg_min": 2, "dmg_max": 12, "damage_type": "Poison"}}]},
	# Quasit — Tiny Fiend (Demon), Chaotic Evil, CR 1. AC 13 (natural armor). STR 5 (-3) DEX 17 (+3)
	# CON 10 (+0) INT 7 (-2) WIS 10 (+0) CHA 10 (+0). Speed 30ft -> {"moves": 4, "per": 3}. Superior
	# darkvision -> "senses": {"sight_bonus": 2}. Passive Perception 10.
	# Rend: +5 to hit (DEX+prof), reach 1, 1d4+3 Slashing (dmg_min/dmg_max 4/7), plus the real
	# Poisoned condition (DISADV on attacks/checks) for 1 turn — "status"/"status_turns" on the
	# "multiattack" sub-entry, applied generically by Enemy._attack_player() on a landed hit (see
	# its own comment). Distinct from "poison" (the pre-existing damage-over-time status) — Rend
	# deals no poison damage, only the condition.
	# Scare (pool "scare": {"range","save_dc"}, enemy.gd's _execute_cast_scare()): ranged (2 tiles),
	# WIS save DC 10, 1/life (real text is "1/Day" — enemies don't rest, see legendary-resistance
	# precedent). On a fail the target is meant to become Frightened — this engine still has no
	# mechanical Frightened condition (only Poisoned/Prone/Restrained/Incapacitated exist today),
	# so this one's still flavor-logged only, a documented gap pending a Frightened pass.
	# Invisibility: identical mechanism to Imp's own (pool "invisibility": {"cooldown","duration"}).
	# Shape Shift: same trait as Imp, but its own form list (pool "shape_shift_forms") — Bat
	# (flying), Centipede, Toad, all keeping Quasit's own 4/3 speed (pool "shape_shift_speed",
	# overriding Imp's slower hardcoded default) since none of them are meant to be slower than its
	# true form; Toad additionally swims freely (ignores Water's difficult-terrain slow while
	# shifted — enemy.gd's _move_step()). Only the look and movement/terrain adaptation change per
	# form, never stats or attacks — same "cosmetic + movement only" rule as Imp's own forms. No
	# art authored yet for any of the three forms (asset debt, same precedent as Imp's own Raven —
	# falls back to leaving the true Quasit sprite showing).
	{"enemy_id": "quasit",        "display_name": "Quasit",      "sprite": "quasit",      "idle_frames": 4, "run_frames": 4, "floor_min": 7, "floor_max": 10, "hp": 25, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 7, "armor": 0, "ac": 13, "exp": 20,
	 "cr": 1, "creature_type": "Fiend", "size_category": "Tiny",
	 "mods": {"str": -3, "dex": 3, "con": 0, "int": -2, "wis": 0, "cha": 0},
	 "senses": {"sight_bonus": 2},
	 "passive_perception": 10,
	 "attack_profile": {"attack_stat": "dex"},
	 "speed": {"moves": 4, "per": 3},
	 "damage_resistances": ["Cold", "Fire", "Lightning"],
	 "damage_immunities": ["Poison"],
	 "condition_immunities": ["poisoned"],
	 "traits": [{"id": "magic_resistance"}, {"id": "shape_shift"}],
	 "shape_shift_forms": ["bat", "centipede", "toad"],
	 "shape_shift_speed": {"moves": 4, "per": 3},
	 "invisibility": {"cooldown": 5, "duration": 600},
	 "scare": {"range": 2, "save_dc": 10},
	 "multiattack": [{"name": "Rend", "count": 1, "dmg_min": 4, "dmg_max": 7, "damage_type": "Slashing",
	                  "status": "poisoned_condition", "status_turns": 1}]},
	{"enemy_id": "pumpkin_dude",  "display_name": "Pumpkin Dude","sprite": "pumpkin_dude","idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 20, "hp_per_floor": 4, "dmg_min": 5, "dmg_max": 9, "armor": 2, "ac": 12, "exp": 25,
	 "cr": 1, "creature_type": "Plant"},
	# Goblin Archer — same base stat block as Goblin Warrior above (Small Fey, CE, CR 1/4, HP 10,
	# AC 15 natural armor — no shield on either goblin now), re-equipped with a Shortbow instead of
	# a Scimitar; everything else (mods, senses, passive perception, Nimble Escape, advantage bonus
	# die) is identical.
	# Shortbow: +4 to hit (DEX+prof), range 4 (normal)/16 (long, DISADV via "long_range" —
	# Enemy._ability_is_long_shot()), 1d6+2 Piercing — encoded as an uncapped "abilities" entry
	# (no cooldown/uses_max/recharge = always ready), same shape as Skeleton's Shortbow. No melee
	# weapon of its own — closing to melee range falls back to the top-level dmg_min/dmg_max
	# (a bare improvised scuffle, same fallback every legacy non-multiattack entry already uses).
	{"enemy_id": "goblin_archer", "display_name": "Goblin Archer", "sprite": "goblin", "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 7,  "hp": 10, "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 15, "exp": 10,
	 "cr": 0.25, "creature_type": "Fey", "size_category": "Small",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}, {"id": "advantage_bonus", "sides": 4}],
	 "abilities": [{"id": "goblin_archer_shortbow", "name": "Shortbow", "range": 4, "long_range": 16, "dmg_min": 3, "dmg_max": 8, "damage_type": "Piercing"}]},
	# Ogre — Large Giant, CE, CR 2, proficiency +2. HP 59, AC 11 (natural armor).
	# STR 19 (+4) DEX 8 (-1) CON 16 (+3) INT 5 (-3) WIS 7 (-2) CHA 7 (-2). Speed 40ft, faster than
	# the 30ft baseline every other pool entry implicitly runs at (1 move/turn) — pool "speed":
	# {"moves": 4, "per": 3} (Enemy._tick_speed_gate()'s Bresenham-style accumulator: 4 moves over
	# every 3 real turns, landing as 1/1/2 — an extra step on every 3rd turn — same mechanism as
	# Zombie's 20ft-speed {"moves": 2, "per": 3} slow-down, just above baseline instead of below it).
	# "Large" size is a real 2x2 footprint — pool "size": {"w": 2, "h": 2} (Entity.size, see
	# scripts/entities/CLAUDE.md's "Multi-tile footprint (Large enemies)"), the first enemy to use
	# it: occupies 4 tiles at once (grid_pos is the top-left corner), blocks movement/targeting on
	# all 4, and its own attack range/sight/LOS are measured from whichever occupied tile is
	# closest. Spawn placement requires the WHOLE 2x2 block to be free — see
	# DungeonFloor._spawn_enemies()'s footprint guard — so it can never land in a 1-wide corridor.
	# Its sprite (idle_1-4/run_1-4, already dropped into sprites/characters/enemies/Ogre/,
	# 32x36px vs. e.g. Orc Warrior's 16x23px) is sized to match the 2x2 footprint.
	# Darkvision: +1 to the default enemy notice/LOS radius (senses.sight_bonus).
	# Passive Perception = 10 + WIS mod (-2) = 8.
	# Greatclub: +6 to hit (STR+prof — default melee attack_stat, no "attack_profile" override
	# needed), reach 1, 2d8+4 Bludgeoning — single-entry multiattack sub-attack for the real damage
	# type (same pattern as Orc Warrior's Greataxe above).
	# Javelin (pool "thrown_weapon"/"unarmed_fallback", one-shot per life — the same generic
	# mechanism as Orc Warrior's Javelin above, re-authored with Ogre's numbers): +6 to hit (STR,
	# same as the Greatclub), range 3 tiles — reusing Orc Warrior's own Javelin range verbatim, the
	# only precedent in this codebase for how far a thrown Javelin flies — 2d8+4 Piercing, rolled
	# with Disadvantage (`long_shot` param). Whenever NOT yet adjacent, thrown once instead of
	# closing to melee. Same "separate weapon" rule as Orc Warrior's Javelin/Greataxe above ("Javelin"
	# != "Greatclub" by name) — once the Javelin is gone this Ogre keeps swinging its Greatclub
	# normally in melee, never permanently falling back to Fists.
	# Recovery: 50% chance (default "drop_chance", same as Orc Warrior's Javelin) to find it
	# wherever the target stands when this Ogre eventually dies; "random_uses": true — the
	# recovered Javelin is already partially worn down, not pristine.
	{"enemy_id": "ogre", "display_name": "Ogre", "sprite": "ogre", "idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 59, "hp_per_floor": 4, "dmg_min": 6, "dmg_max": 20, "armor": 0, "ac": 11, "exp": 40,
	 "cr": 2, "creature_type": "Giant", "size_category": "Large",
	 "mods": {"str": 4, "dex": -1, "con": 3, "int": -3, "wis": -2, "cha": -2},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 8,
	 "speed": {"moves": 4, "per": 3},
	 "size": {"w": 2, "h": 2},
	 "multiattack": [{"name": "Greatclub", "count": 1, "dmg_min": 6, "dmg_max": 20, "damage_type": "Bludgeoning"}],
	 "thrown_weapon": {"name": "Javelin", "range": 3, "dmg_min": 6, "dmg_max": 20, "damage_type": "Piercing",
		"icon": "weapon_spear.png", "drop_die_min": 2, "drop_die_max": 8, "weapon_category": "Simple",
		"is_finesse": false, "is_light": false, "weapon_mastery": "", "drop_uses_max": 5, "random_uses": true},
	 "unarmed_fallback": {"name": "Fists", "dmg_min": 5, "dmg_max": 5, "damage_type": "Bludgeoning", "attack_stat": "str"}},
	# Spider — Large Beast, unaligned, CR 1, proficiency +2. HP 26, AC 14 (natural armor).
	# STR 14 (+2) DEX 16 (+3) CON 12 (+1) INT 2 (-4) WIS 11 (+0) CHA 4 (-3). Speed 30ft (default,
	# no "speed" key needed).
	# "Large" size: 2x2 footprint (Entity.size), same mechanism as Ogre above — see
	# scripts/entities/CLAUDE.md's "Multi-tile footprint (Large enemies)".
	# Sprite: reuses the existing sliced Spider/{idle,run}.png sheet (32x32 frames, scale 1.0 — full
	# native frame size, so its render footprint actually fills its 2x2 tile area instead of looking
	# tile-sized like a Small/Medium enemy, 6 frames each) already authored for Imp's Shape Shift
	# trait — see "sprite_frame_size"/"sprite_scale" below and Enemy._setup_animations()'s
	# no-variant sheet-loading branch.
	# Darkvision: +1 to the default enemy notice/LOS radius (senses.sight_bonus).
	# Passive Perception = 10 + WIS mod (0) = 10.
	# Spider Climb (trait "ignore_terrain_slow"): "can go through difficult surfaces without being
	# slowed" — Enemy._move_step() skips the generic Water/Mud "slowed" status application whenever
	# this trait is present (every other enemy still gets slowed by difficult terrain).
	# Web Walker / Web Sense (trait "web_walker"): "ignores movement restrictions caused by
	# webbing and knows the location of any creature in contact with the same web" — implemented as
	# the second half: Enemy._can_see_entity() never loses track of a target currently Restrained by
	# this spider's own Web (below), regardless of distance/LOS. The "ignores its own web" half is a
	# no-op in practice (nothing else here ever walks into a web), documented for completeness.
	# Bite: +5 to hit (DEX+prof — attack_profile.attack_stat), reach 1, 1d8+3 Piercing AND 2d6
	# Poison on the SAME hit (multiattack "extra", same one-hit-two-damage-types convention as
	# Imp's Sting).
	# Web (pool "web": {"cooldown","range","save_dc"}) — a ranged, non-damage, SAVE-based restraint
	# ability, Player-only (see Stats.web_restrained/web_escape_dc and player.gd's
	# _attempt_web_escape()): while already aware of the target (CHASING/SEARCHING — never on a
	# fresh notice, per the owner's own framing "won't web just because it exists, only once it
	# already knows about the hero"), not yet adjacent, off its 10-turn cooldown, the target isn't
	# already stuck in an earlier web, and nothing blocks the shot (has_clear_shot — "can only spit
	# it if nothing/nobody is standing in the way"), Web is picked over closing the distance the
	# instant the target is in range — the SAME "ranged option beats melee approach" priority slot
	# Imp's Invisibility already occupies (see Enemy._decide_action()). On a failed DEX save (rolled
	# the identical d20+DEX mod+proficiency-if-trained shape as the player's own DEX save vs a
	# friendly-fire Fireball), the target is Restrained (ALL movement blocked — see
	# player.gd._try_move()'s guard) until a STR check vs the same DC breaks free
	# (player.gd._attempt_web_escape()) — the D&D alternate escape route (rather than needing to
	# deal 5+ slashing/fire damage to the web structure itself, which this engine has no
	# attack-a-structure system to support yet; documented simplification, not an oversight). The
	# web structure itself (DungeonFloor.spawn_web(), AC 10 / HP 5 / vulnerable to Fire / immune to
	# Poison and Psychic per the real spell's text) is currently pure flavor data — nothing can
	# actually attack it directly today, only the STR-check escape route above ever removes it.
	{"enemy_id": "spider", "display_name": "Spider", "sprite": "spider",
	 "sprite_frame_size": {"w": 32, "h": 32}, "sprite_scale": 1.0, "idle_frames": 6, "run_frames": 6,
	 "floor_min": 4, "floor_max": 8, "hp": 26, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 11, "armor": 0, "ac": 14, "exp": 22,
	 "cr": 1, "creature_type": "Beast", "size_category": "Large",
	 "mods": {"str": 2, "dex": 3, "con": 1, "int": -4, "wis": 0, "cha": -3},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 10,
	 "attack_profile": {"attack_stat": "dex"},
	 "size": {"w": 2, "h": 2},
	 "traits": [{"id": "ignore_terrain_slow"}, {"id": "web_walker"}],
	 "multiattack": [{"name": "Bite", "count": 1, "dmg_min": 4, "dmg_max": 11, "damage_type": "Piercing",
	                  "extra": {"dmg_min": 2, "dmg_max": 12, "damage_type": "Poison"}}],
	 "web": {"cooldown": 10, "range": 6, "save_dc": 13}},
]
