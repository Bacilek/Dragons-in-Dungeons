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
# "gold" = Item.gold_value (base shop price; 0/absent = unpriced/not for sale) — read by
# DungeonFloor._build_floor_item() and mirrored in debug_panel.ALL_ITEMS per the item sync rule.
const ITEM_POOL: Array = [
	{"name": "Health Potion",  "type": 2, "icon": "Potions/Health/HealthPotionMedium.png", "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4, "gold": 30},
	{"name": "Strength Potion","type": 2, "icon": "Potions/Mana/ManaPotionMedium.png",    "src": "items", "bonus_dmg": 2, "heal": 0,   "str_bonus": 2, "fmin": 3, "fmax": 10, "desc": "+2 ATK (permanent this run)", "gold": 80},
	{"name": "Ration",         "type": 4, "icon": "Food/MeatCooked.png",                  "src": "items", "bonus_dmg": 0, "heal": 0, "food_value": 50, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Required for a long rest.", "gold": 15},
	{"name": "Mystery Meat",   "type": 4, "icon": "Food/Meat.png",                        "src": "items", "bonus_dmg": 0, "heal": 0, "food_value": 25, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Required for a long rest.", "gold": 8},
	# Healing Herb (special-rooms-economy-design.md §4.3, session 7d): fmin/fmax 99 is a
	# sentinel — no floor's current_floor ever reaches 99, so it never spawns via the generic
	# floor-eligibility filters (_spawn_items()/_spawn_locked_doors()); DungeonFloor._spawn_garden_items()
	# looks it up by name and places it directly. FOOD type + food_value counts toward the normal
	# long-rest fuel total; heal_amount is the one exception a FOOD item gets — see game_state.gd
	# use_item()'s FOOD branch.
	{"name": "Healing Herb",   "type": 4, "icon": "Food/SaladFlowerPurple.png",           "src": "items", "bonus_dmg": 0, "heal": 4, "food_value": 25, "str_bonus": 0, "fmin": 99, "fmax": 99, "desc": "A fragrant garden herb. Eating it heals 4 HP and also counts as long-rest fuel.", "gold": 10},
	{"name": "Short Bow",      "type": 0, "icon": "Weapons/BowArrow.png",                 "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 2, "fmax": 6,  "desc": "Ranged, DEX-based. Normal range 4, long range = FOV (DISADV). Requires Arrows.", "is_ranged": true, "range": 4, "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Vex", "ammo": "Arrow", "gold": 50},
	{"name": "Heavy Crossbow", "type": 0, "icon": "Weapons/BowArrowGold.png",             "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Ranged, DEX-based. Normal range 4, long range = FOV (DISADV). Heavy (DEX 13+), two-handed. Requires Bolts.", "is_ranged": true, "range": 4, "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Push", "ammo": "Bolt", "heavy": true, "two_handed": true, "gold": 120},
	{"name": "Longbow",       "type": 0, "icon": "Weapons/Bow.png",                      "src": "items",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 5, "fmax": 10, "desc": "Ranged, DEX-based. Normal range 5, long range = FOV (DISADV). Heavy (DEX 13+), two-handed. Requires Arrows.", "is_ranged": true, "range": 5, "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 8, "mastery": "Slow", "ammo": "Arrow", "heavy": true, "two_handed": true},
	{"name": "Rapier",         "type": 0, "icon": "weapon_duel_sword.png",               "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Finesse: uses STR or DEX, whichever is higher.", "dmg_type": "Piercing", "category": "Martial", "die_min": 1, "die_max": 8, "mastery": "Vex", "finesse": true},
	{"name": "Greatsword",     "type": 0, "icon": "weapon_knight_sword.png",            "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed. Graze: a miss still deals damage equal to your STR modifier.", "dmg_type": "Slashing", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Graze", "heavy": true, "two_handed": true},
	{"name": "Glaive",         "type": 0, "icon": "weapon_spear.png",                   "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed, Reach (+1 tile). Graze: a miss still deals damage equal to your STR modifier.", "dmg_type": "Slashing", "category": "Martial", "die_min": 1, "die_max": 10, "mastery": "Graze", "heavy": true, "two_handed": true, "reach": true},
	{"name": "Maul",           "type": 0, "icon": "weapon_big_hammer.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 3, "fmax": 10, "desc": "Melee. Heavy, two-handed. Topple: on a hit, target rolls a CON save or is knocked Prone, skipping its next turn.", "dmg_type": "Bludgeoning", "category": "Martial", "die_min": 2, "die_max": 12, "mastery": "Topple", "heavy": true, "two_handed": true},
	{"name": "Quarterstaff",   "type": 0, "icon": "weapon_green_magic_staff.png",     "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Versatile (1d8): click Main Hand to grip two-handed. Topple: on a hit, target rolls a CON save or is knocked Prone, skipping its next turn.", "dmg_type": "Bludgeoning", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Topple", "versatile": true},
	{"name": "Spear",          "type": 0, "icon": "weapon_spear.png",                 "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Versatile (1d8): click Main Hand to grip two-handed. Thrown (3/FOV): RMB then LMB a tile — uses your melee attack modifier. Sap: on a hit, target has Disadvantage on its next attack next turn. 5 uses before it breaks.", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "mastery": "Sap", "versatile": true, "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Handaxe",        "type": 0, "icon": "weapon_throwing_axe.png",        "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Light: pair with another Light weapon in the Off-hand to attack with both (off-hand swing skips your ability modifier unless it's negative). Thrown (3/FOV): RMB then LMB a tile — uses your melee attack modifier. Vex: on a hit, gain Advantage on your next attack this round against that enemy. 5 uses before it breaks.", "dmg_type": "Slashing", "category": "Simple", "die_min": 1, "die_max": 6, "mastery": "Vex", "light": true, "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Dagger",         "type": 0, "icon": "weapon_knife.png",              "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple, Finesse, Light: pair with another Light weapon in the Off-hand to attack with both (off-hand swing skips your ability modifier unless it's negative). Thrown (3/FOV): RMB then LMB a tile — uses your melee attack modifier. Nick: while dual-wielding Light weapons, make one further attack this turn identical to the Off-hand swing (max 3 attacks total). 5 uses before it breaks.", "dmg_type": "Piercing", "category": "Simple", "die_min": 1, "die_max": 4, "mastery": "Nick", "finesse": true, "light": true, "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Torch",          "type": 0, "icon": "weapon_torch.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Melee. Simple. Can be equipped in Main Hand or Off-hand (like a Shield — never fires a bonus Off-hand attack). Click while equipped to light it: burns for 100 turns (even unequipped, in a stack, on the floor, or embedded in an enemy), granting +1 FOV while equipped and a radius-2 light wherever it's lying/embedded. While lit and wielded in Main Hand, melee attacks also deal +1d4 Fire damage. Thrown (3/FOV): RMB then LMB a tile — 1d4 Bludgeoning, +1d4 Fire if lit. 3 uses before it breaks. Burns out permanently into a Burnt Torch.", "dmg_type": "Bludgeoning", "category": "Simple", "die_min": 1, "die_max": 4, "torch": true, "thrown": true, "range": 3, "uses_max": 3},
	{"name": "Arrow",          "type": 7, "icon": "Weapons/weapon_arrow.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Short Bow and Longbow.", "qty": 6, "gold": 1},
	{"name": "Bolt",           "type": 7, "icon": "Weapons/weapon_arrow.png",             "src": "weapons", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Ammunition for the Heavy Crossbow.", "qty": 6},
	{"name": "Thief Tools",    "type": 7, "icon": "Misc/KeyIron.png",                    "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 2, "fmax": 10, "desc": "Disarm traps, lock doors. Consumed on failure.", "qty": 2, "gold": 25},
	{"name": "Shield",         "type": 1, "icon": "Shields/Shield1.png",                "src": "items", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "fmin": 1, "fmax": 10, "desc": "Off-hand. +2 AC. Requires shield proficiency; can't be worn with a two-handed Main Hand weapon, and blocks spellcasting while equipped. Equip/unequip takes 1 turn.", "bonus_ac": 2, "is_shield": true, "gold": 40},
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
]

const BOSS_POOL: Array = [
	{"boss_id": "big_demon",   "display_name": "Big Demon",   "sprite": "big_demon",   "idle_frames": 4, "run_frames": 4, "floor": 5,  "hp": 80,  "hp_per_floor": 0, "dmg_min": 8,  "dmg_max": 14, "armor": 3, "ac": 16, "exp": 100,
	 "cr": 5, "creature_type": "Fiend", "legendary_resistances": 3},
	{"boss_id": "necromancer", "display_name": "Necromancer", "sprite": "necromancer", "idle_frames": 4, "run_frames": 4, "floor": 10, "hp": 120, "hp_per_floor": 0, "dmg_min": 10, "dmg_max": 18, "armor": 4, "ac": 13, "exp": 200,
	 "cr": 8, "creature_type": "Humanoid",
	 "idle_fmt": "res://sprites/characters/necromancer_anim_f%d.png",
	 "run_fmt":  "res://sprites/characters/necromancer_anim_f%d.png"},
]

const ENEMY_POOL: Array = [
	# Goblin Minion — Small Fey, CN, CR 1/8. HP 2d6 (avg 7), AC 12 (natural armor).
	# STR 8 (-1) DEX 15 (+2) CON 10 (+0) INT 10 (+0) WIS 8 (-1) CHA 8 (-1). Speed 1 (default).
	# Skills: Stealth +6 — flavor only, no mechanical consumer yet (see Goblin Warrior's note above).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 6 -> 7 here).
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
	 "cr": 0.125, "creature_type": "Fey",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}],
	 "multiattack": [{"name": "Dagger", "count": 1, "dmg_min": 3, "dmg_max": 6, "damage_type": "Piercing"}],
	 "thrown_weapon": {"name": "Dagger", "dmg_min": 3, "dmg_max": 6, "damage_type": "Piercing", "range": 4, "flee_only": true},
	 "unarmed_fallback": {"name": "Fists", "dmg_min": 1, "dmg_max": 1, "damage_type": "Bludgeoning", "attack_stat": "str"}},
	# Orc Warrior — Medium Humanoid (Orc), CR 1/2, proficiency +2. HP 15, AC 13.
	# STR 16 (+3) DEX 12 (+1) CON 16 (+3) INT 7 (-2) WIS 11 (+0) CHA 10 (+0). Speed 1 (default).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 6 -> 7 here).
	# Passive Perception = 10 + WIS mod = 10.
	# Greataxe: +5 to hit (STR+prof — the default melee attack_stat, no "attack_profile" override
	# needed), reach 1, 1d12+3 Slashing — single-entry multiattack sub-attack for the real damage
	# type (same pattern as Skeleton's Shortsword above).
	# Javelin (pool "thrown_weapon"/"unarmed_fallback", one-shot per life — the exact same generic
	# mechanism as Goblin Minion's Dagger above, just re-authored with Javelin/Fists numbers): +5 to
	# hit (STR, same as the Greataxe — no "attack_stat" override needed), range 3, 1d6+3 Piercing,
	# rolled with Disadvantage (reuses _attack_player()/_attack_companion()'s `long_shot` param).
	# Whenever NOT yet adjacent, thrown once instead of closing to melee; once gone, every attack
	# after this reverts to an unarmed Fist strike ("unarmed_fallback": flat 4 Bludgeoning — "1 +
	# STR mod", Orc's STR mod is +3) — Enemy._attack_target()'s dispatch, same as Goblin's Fists.
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
	 "cr": 0.5, "creature_type": "Humanoid",
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
	 "cr": 0.25, "creature_type": "Fey",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}, {"id": "advantage_bonus", "sides": 4}],
	 "multiattack": [{"name": "Scimitar", "count": 1, "dmg_min": 3, "dmg_max": 8, "damage_type": "Slashing"}]},
	{"enemy_id": "orc_shaman",    "display_name": "Orc Shaman",  "sprite": "orc_shaman",  "idle_frames": 4, "run_frames": 4, "floor_min": 3, "floor_max": 6,  "hp": 10, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 0, "ac": 10, "exp": 12,
	 "cr": 0.25, "creature_type": "Humanoid"},
	{"enemy_id": "masked_orc",    "display_name": "Masked Orc",  "sprite": "masked_orc",  "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,  "hp": 12, "hp_per_floor": 2, "dmg_min": 2, "dmg_max": 5, "armor": 1, "ac": 13, "exp": 10,
	 "cr": 0.25, "creature_type": "Humanoid"},
	# Skeleton — Medium Undead, CR 1/4, proficiency +2. HP 13, AC 14 (natural armor).
	# STR 10 (+0) DEX 14 (+2) CON 15 (+2) INT 6 (-2) WIS 8 (-1) CHA 3 (-4). Speed 1 (default).
	# Darkvision: +1 to the default enemy notice/LOS radius (Enemy.FOV_RADIUS = 6 -> 7 here).
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
	 "cr": 0.25, "creature_type": "Undead",
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
	# rooted_turns). Darkvision: +1 to the default enemy notice/LOS radius (FOV_RADIUS 6 -> 7).
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
	# Invisibility (pool "invisibility", cooldown 5 turns, duration up to 100 turns): while CHASING/
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
	 "cr": 1, "creature_type": "Fiend",
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
	 "invisibility": {"cooldown": 5, "duration": 100},
	 "multiattack": [{"name": "Sting", "count": 1, "dmg_min": 4, "dmg_max": 9, "damage_type": "Piercing",
	                  "extra": {"dmg_min": 2, "dmg_max": 12, "damage_type": "Poison"}}]},
	{"enemy_id": "chort",         "display_name": "Chort",       "sprite": "chort",       "idle_frames": 4, "run_frames": 4, "floor_min": 7, "floor_max": 10, "hp": 16, "hp_per_floor": 3, "dmg_min": 4, "dmg_max": 8, "armor": 2, "ac": 14, "exp": 20, "resist": ["Fire"],
	 "cr": 0.5, "creature_type": "Fiend"},
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
	 "cr": 0.25, "creature_type": "Fey",
	 "mods": {"str": -1, "dex": 2, "con": 0, "int": 0, "wis": -1, "cha": -1},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 9,
	 "attack_profile": {"attack_stat": "dex"},
	 "traits": [{"id": "nimble_escape"}, {"id": "advantage_bonus", "sides": 4}],
	 "abilities": [{"id": "goblin_archer_shortbow", "name": "Shortbow", "range": 4, "long_range": 16, "dmg_min": 3, "dmg_max": 8, "damage_type": "Piercing"}]},
	# Ogre — Large Giant, CE, CR 2, proficiency +2. HP 59, AC 11 (natural armor).
	# STR 19 (+4) DEX 8 (-1) CON 16 (+3) INT 5 (-3) WIS 7 (-2) CHA 7 (-2). Speed 1 (default) — the
	# stat block's 40ft/30ft swim speed is flavor only, this codebase has no fractional/variable
	# per-turn movement rate to encode it against (see "aggressive"-trait bonus_moves for the only
	# movement-rate lever that exists). "Large" size is flavor only too — multi-tile occupancy is
	# still design-only per the stat-block schema doc (scripts/entities/CLAUDE.md), so the Ogre
	# occupies a single tile like every other enemy; its sprite (ogre_idle_anim_f0-3/ogre_run_anim_f0-3,
	# already dropped into sprites/characters/) is just drawn larger by the art itself.
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
	# closing to melee; once gone, every attack after this reverts to an unarmed Fist strike
	# ("unarmed_fallback": flat 5 Bludgeoning — "1 + STR mod", Ogre's STR mod is +4).
	# Recovery: 50% chance (default "drop_chance", same as Orc Warrior's Javelin) to find it
	# wherever the target stands when this Ogre eventually dies; "random_uses": true — the
	# recovered Javelin is already partially worn down, not pristine.
	{"enemy_id": "ogre", "display_name": "Ogre", "sprite": "ogre", "idle_frames": 4, "run_frames": 4, "floor_min": 8, "floor_max": 10, "hp": 59, "hp_per_floor": 4, "dmg_min": 6, "dmg_max": 20, "armor": 0, "ac": 11, "exp": 40,
	 "cr": 2, "creature_type": "Giant",
	 "mods": {"str": 4, "dex": -1, "con": 3, "int": -3, "wis": -2, "cha": -2},
	 "senses": {"sight_bonus": 1},
	 "passive_perception": 8,
	 "multiattack": [{"name": "Greatclub", "count": 1, "dmg_min": 6, "dmg_max": 20, "damage_type": "Bludgeoning"}],
	 "thrown_weapon": {"name": "Javelin", "range": 3, "dmg_min": 6, "dmg_max": 20, "damage_type": "Piercing",
		"icon": "weapon_spear.png", "drop_die_min": 2, "drop_die_max": 8, "weapon_category": "Simple",
		"is_finesse": false, "is_light": false, "weapon_mastery": "", "drop_uses_max": 5, "random_uses": true},
	 "unarmed_fallback": {"name": "Fists", "dmg_min": 5, "dmg_max": 5, "damage_type": "Bludgeoning", "attack_stat": "str"}},
]
