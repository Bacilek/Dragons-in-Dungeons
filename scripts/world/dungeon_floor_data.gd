class_name DungeonFloorData
extends RefCounted

const WEAPONS_PATH := "res://sprites/weapons/"
const OBJECTS_PATH := "res://sprites/objects/"
const ITEMS_PATH   := "res://sprites/items/"

const TRAP_POOL: Array = [
	{"name": "Bear Trap",  "sprite": "Bear_Trap.png",       "damage": 0, "msg": "The bear trap snaps shut on you!", "wall_trap": false},
	{"name": "Fire Trap",  "sprite": "Fire_Trap.png",        "damage": 8, "msg": "Jets of flame engulf you!",        "wall_trap": false},
	{"name": "Pit Spikes", "sprite": "Pit_Trap_Spikes.png",  "damage": 7, "msg": "You fall into a spike pit!",       "wall_trap": false, "reusable": true},
	{"name": "Piston",     "sprite": "Push_Trap_Front.png",  "damage": 0, "msg": "A piston blasts you!",             "wall_trap": true},
]

# item_type: 0=WEAPON 1=ARMOR 2=POTION 4=FOOD  (matches Item.Type enum)
const ITEM_POOL: Array = [
	{"name": "Health Potion",  "type": 2, "icon": "Potions/Health/HealthPotionMedium.png", "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4},
	{"name": "Strength Potion","type": 2, "icon": "Potions/Mana/ManaPotionMedium.png",    "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)"},
	{"name": "Ration",         "type": 4, "icon": "Food/MeatCooked.png",                  "src": "items", "bonus_dmg": 0, "heal": 200, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Fills you up"},
	{"name": "Mystery Meat",   "type": 4, "icon": "Food/Meat.png",                        "src": "items", "bonus_dmg": 0, "heal": 120, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Better than nothing"},
	{"name": "Short Bow",      "type": 0, "icon": "Weapons/BowArrow.png",                 "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 6,  "desc": "Ranged, DEX-based. Normal range 4, long range = FOV (DISADV). Requires Arrows.", "is_ranged": true, "range": 4, "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Vex", "ammo": "Arrow"},
	{"name": "Heavy Crossbow", "type": 0, "icon": "Weapons/BowArrowGold.png",             "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Ranged, DEX-based. Normal range 4, long range = FOV (DISADV). Heavy (DEX 13+), two-handed. Requires Bolts.", "is_ranged": true, "range": 4, "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Push", "ammo": "Bolt", "heavy": true, "two_handed": true},
	{"name": "Rapier",         "type": 0, "icon": "weapon_duel_sword.png",               "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Finesse: uses STR or DEX, whichever is higher.", "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 8, "mastery": "Vex", "finesse": true},
	{"name": "Greatsword",     "type": 0, "icon": "weapon_knight_sword.png",            "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed. Graze: a miss still deals damage equal to your STR modifier.", "dmg_type": "Slashing", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Graze", "heavy": true, "two_handed": true},
	{"name": "Glaive",         "type": 0, "icon": "weapon_spear.png",                   "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed, Reach (+1 tile). Graze: a miss still deals damage equal to your STR modifier.", "dmg_type": "Slashing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Graze", "heavy": true, "two_handed": true, "reach": true},
	{"name": "Maul",           "type": 0, "icon": "weapon_big_hammer.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed. Topple: on a hit, target rolls a CON save or is knocked Prone, skipping its next turn.", "dmg_type": "Bludgeoning", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Topple", "heavy": true, "two_handed": true},
	{"name": "Quarterstaff",   "type": 0, "icon": "weapon_green_magic_staff.png",     "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Versatile (1d8): click Main Hand to grip two-handed. Topple: on a hit, target rolls a CON save or is knocked Prone, skipping its next turn.", "dmg_type": "Bludgeoning", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Topple", "versatile": true},
	{"name": "Spear",          "type": 0, "icon": "weapon_spear.png",                 "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Versatile (1d8): click Main Hand to grip two-handed. Thrown (3/FOV): RMB then LMB a tile — uses your melee attack modifier. Sap: on a hit, target has Disadvantage on its next attack next turn. 5 uses before it breaks.", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Sap", "versatile": true, "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Arrow",          "type": 7, "icon": "Weapons/weapon_arrow.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Short Bow.", "qty": 6},
	{"name": "Bolt",           "type": 7, "icon": "Weapons/weapon_arrow.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Heavy Crossbow.", "qty": 6},
	{"name": "Thief Tools",    "type": 7, "icon": "Misc/KeyIron.png",                    "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Disarm traps, lock doors. Consumed on failure.", "qty": 2},
]

const BOSS_POOL: Array = [
	{"boss_id": "big_demon",   "display_name": "Big Demon",   "sprite": "big_demon",   "idle_frames": 4, "run_frames": 4, "floor": 5,  "hp": 80,  "hp_per_floor": 0, "dmg_min": 8,  "dmg_max": 14, "armor": 3, "ac": 16, "exp": 100},
	{"boss_id": "necromancer", "display_name": "Necromancer", "sprite": "necromancer", "idle_frames": 4, "run_frames": 4, "floor": 10, "hp": 120, "hp_per_floor": 0, "dmg_min": 10, "dmg_max": 18, "armor": 4, "ac": 13, "exp": 200,
	 "idle_fmt": "res://sprites/characters/necromancer_anim_f%d.png",
	 "run_fmt":  "res://sprites/characters/necromancer_anim_f%d.png"},
]

const ENEMY_POOL: Array = [
	{"enemy_id": "tiny_zombie",   "display_name": "Tiny Zombie", "sprite": "tiny_zombie", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 3,  "hp": 5,  "hp_per_floor": 1, "dmg_min": 1, "dmg_max": 3, "armor": 0, "ac": 10, "exp": 4},
	{"enemy_id": "orc_warrior",   "display_name": "Orc Warrior", "sprite": "orc_warrior", "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,  "hp": 8,  "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 11, "exp": 8},
	{"enemy_id": "goblin",        "display_name": "Goblin",      "sprite": "goblin",      "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 6,  "hp": 7,  "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 4, "armor": 0, "ac": 12, "exp": 6},
	{"enemy_id": "orc_shaman",    "display_name": "Orc Shaman",  "sprite": "orc_shaman",  "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 0, "ac": 10, "exp": 12},
	{"enemy_id": "masked_orc",    "display_name": "Masked Orc",  "sprite": "masked_orc",  "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 12, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 1, "ac": 13, "exp": 10},
	{"enemy_id": "skeleton",      "display_name": "Skeleton",    "sprite": "skelet",      "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 9,  "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 12, "exp": 9},
	{"enemy_id": "wogol",         "display_name": "Wogol",       "sprite": "wogol",       "idle_frames": 4, "run_frames": 4, "floor_min": 5, "floor_max": 8,  "hp": 14, "hp_per_floor": 3, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 13, "exp": 15},
	{"enemy_id": "imp",           "display_name": "Imp",         "sprite": "imp",         "idle_frames": 4, "run_frames": 4, "floor_min": 6, "floor_max": 9,  "hp": 11, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 7, "armor": 1, "ac": 13, "exp": 13},
	{"enemy_id": "chort",         "display_name": "Chort",       "sprite": "chort",       "idle_frames": 4, "run_frames": 4, "floor_min": 7, "floor_max": 10, "hp": 16, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 8, "armor": 2, "ac": 14, "exp": 20},
	{"enemy_id": "pumpkin_dude",  "display_name": "Pumpkin Dude","sprite": "pumpkin_dude","idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 20, "hp_per_floor": 4, "dmg_min": 5, "dmg_max": 9, "armor": 2, "ac": 12, "exp": 25},
	{"enemy_id": "goblin_archer", "display_name": "Goblin Archer", "sprite": "goblin", "idle_frames": 4, "run_frames": 4, "floor_min": 2, "floor_max": 7,  "hp": 6,  "hp_per_floor": 1, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 11, "exp": 7,
	 "attack_profile": {"kind": "ranged", "range": 5, "projectile": "arrow"}},
]
