class_name Stats
extends Resource

enum CharacterClass { BARBARIAN, RANGER, WIZARD, MONK }
enum CharacterRace { ORC, HUMAN, HALFLING, DWARF, ELF, DRAGONBORN }
enum ElfSubrace { DROW, HIGH_ELF, WOOD_ELF }          # only meaningful when character_race == ELF
enum DragonbornAncestry { BLACK, BLUE, BRASS, BRONZE, COPPER, GOLD, GREEN, RED, SILVER, WHITE }

const DRAGONBORN_DAMAGE_TYPE: Array[String] = [
	"Acid", "Lightning", "Fire", "Fire", "Acid", "Fire", "Poison", "Fire", "Lightning", "Cold"
]

# Check proficiency flags — which ability checks the class rolls with proficiency bonus.
# Barbarian: STR + CON. Ranger: STR + DEX. Wizard: INT + WIS. Monk: STR + DEX.
# Monk also has proficiency with simple weapons + martial weapons with light property (TODO: enforce).
var check_prof_str: bool = false
var check_prof_con: bool = false
var check_prof_dex: bool = false
var check_prof_int: bool = false
var check_prof_wis: bool = false
var check_prof_cha: bool = false

# Weapon proficiency — whether the class adds proficiency_bonus to attack rolls with
# Simple/Martial weapons (Item.weapon_category). Lacking proficiency still lets the
# character use the weapon; it just skips the proficiency bonus on the attack roll.
var proficient_simple_weapons: bool = false
var proficient_martial_weapons: bool = false

# Weapon mastery ownership — a weapon's Item.weapon_mastery (e.g. "Cleave", "Vex") only
# triggers its effect if the character actually knows that mastery. Populated by the Mastery
# Picker (scripts/ui/mastery_picker.gd, via GameState.toggle_mastery()) — see mastery_cap()
# below for the per-class/level selection limit.
var known_weapon_masteries: Array[String] = []

func knows_mastery(mastery_name: String) -> bool:
	return mastery_name in known_weapon_masteries

# Canonical mastery vocabulary shown by the Mastery Picker (scripts/ui/mastery_picker.gd) —
# see docs/architecture/weapon-mastery-selection-design.md. Alphabetical, stable render order.
const ALL_WEAPON_MASTERIES: Array[String] = [
	"Cleave", "Graze", "Nick", "Push", "Sap", "Slow", "Topple", "Vex"
]

# How many masteries this character may know at once. Computed live (never cached) so a
# level-up silently raises the cap with no stale value — see design doc decision #4.
func mastery_cap() -> int:
	match character_class:
		CharacterClass.BARBARIAN:
			if character_level >= 10: return 4
			if character_level >= 4:  return 3
			return 2
		CharacterClass.RANGER:
			return 2
		_:
			return 0   # WIZARD, MONK

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var character_class: CharacterClass = CharacterClass.BARBARIAN
@export var character_level: int = 1

@export var character_race: CharacterRace = CharacterRace.HUMAN
@export var race_variant: int = 0        # ElfSubrace or DragonbornAncestry ordinal; unused otherwise
@export var race_prof_ability: int = -1  # Human only: which of STR..CHA got proficiency; -1 = unset

# Always re-derived by apply_race_defaults() — never saved directly (mirrors check_prof_* above).
var darkvision_bonus: int = 0            # 0 = none, 1 = standard (+1 FOV tile), 2 = superior (+2)
var damage_resistances: Array[String] = []

# Per-long-rest race charge trackers — reset in GameState.long_rest(), same chokepoint as
# rage_uses_remaining/hit_dice.
var relentless_endurance_used: bool = false     # Orc
var heroic_inspiration_available: bool = false  # Human

@export var max_hp: int = 10
@export var current_hp: int = 10
@export var armor_class: int = 10

# Proficiency bonus scales per D&D 5e: +2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.
var proficiency_bonus: int:
	get: return 2 + (character_level - 1) / 4

@export var base_min_damage: int = 1
@export var base_max_damage: int = 4
@export var min_damage: int = 1
@export var max_damage: int = 4
@export var armor: int = 0

@export var experience: int = 0

# Rage uses (Barbarian only). rage_uses_max scales by level; reset to max on floor descent.
var rage_uses_remaining: int = 0
var rage_uses_max: int:
	get:
		if character_class != CharacterClass.BARBARIAN: return 0
		if character_level >= 17: return 5
		if character_level >= 12: return 5
		if character_level >= 6:  return 4
		if character_level >= 4:  return 3
		return 2

# Rage bonus damage scales with Barbarian level (+2 / +3 / +4).
var rage_bonus_damage: int:
	get:
		if character_class != CharacterClass.BARBARIAN: return 0
		if character_level >= 16: return 4
		if character_level >= 9:  return 3
		return 2

var poison_turns: int = 0
var burning_turns: int = 0
var bleeding_turns: int = 0
var slowed_turns: int = 0
var temp_hp: int = 0  # Natural Sleeper R2 — consumed before regular HP damage
var zealous_presence_turns: int = 0  # Zealot Zealous Presence — Advantage on attacks/checks while > 0


# Monk: Martial Arts die scales with level. Global default 1d4 is used by all other classes.
var martial_arts_die_sides: int:
	get:
		if character_class == CharacterClass.MONK:
			if character_level >= 17: return 12
			if character_level >= 11: return 10
			if character_level >= 5:  return 8
			return 6
		return 4  # global default: 1d4 for unarmed

func exp_for_level(lv: int) -> int:
	return lv * 10

func exp_to_next() -> int:
	return exp_for_level(character_level)

func gain_exp(amount: int) -> bool:
	experience += amount
	var leveled := false
	while experience >= exp_for_level(character_level):
		experience -= exp_for_level(character_level)
		character_level += 1
		var hp_gain: int = _hp_per_level()
		max_hp += hp_gain
		current_hp = mini(current_hp + hp_gain, max_hp)
		leveled = true
	return leveled

func _hp_per_level() -> int:
	var gain: int
	match character_class:
		CharacterClass.BARBARIAN: gain = 7 + con_modifier()
		CharacterClass.RANGER:    gain = 6 + con_modifier()
		CharacterClass.WIZARD:    gain = 4 + con_modifier()
		CharacterClass.MONK:      gain = 5 + con_modifier()  # d8 avg = 5
		_:                        gain = 5 + con_modifier()
	if character_race == CharacterRace.DWARF:
		gain += 1
	return gain

func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

func str_modifier() -> int: return modifier(strength)
func dex_modifier() -> int: return modifier(dexterity)
func con_modifier() -> int: return modifier(constitution)
func int_modifier() -> int: return modifier(intelligence)
func wis_modifier() -> int: return modifier(wisdom)
func cha_modifier() -> int: return modifier(charisma)

func ability_check(score: int, proficient: bool, dc: int) -> bool:
	var roll: int = Rng.roll(20)
	var bonus: int = modifier(score) + (proficiency_bonus if proficient else 0)
	return (roll + bonus) >= dc

func roll_damage() -> int:
	return Rng.range_i(min_damage, max_damage)

func take_damage(amount: int) -> int:
	var clamped: int = maxi(1, amount)
	# Temp HP (from Natural Sleeper R2) absorbs damage first
	if temp_hp > 0:
		var absorbed: int = mini(temp_hp, clamped)
		temp_hp -= absorbed
		clamped -= absorbed
		if clamped <= 0:
			return 0  # fully absorbed
	current_hp -= clamped
	return clamped

func is_dead() -> bool:
	return current_hp <= 0

# Shared "Bloodied" mechanic (Scarred Warrior and any future consumer) — see markdowns/scarred_warrior.md.
# Below 50% max HP (integer division, round down), recomputed live from current/max HP.
func is_bloodied() -> bool:
	return current_hp < max_hp / 2

func tick_status() -> int:
	var dmg: int = 0
	if poison_turns > 0:
		dmg += 1 + poison_turns / 3
		poison_turns -= 1
	if burning_turns > 0:
		dmg += character_level
		burning_turns -= 1
	if bleeding_turns > 0:
		dmg += 1
		bleeding_turns -= 1
	if slowed_turns > 0:
		slowed_turns -= 1
	return dmg

# Recalculates armor_class based on what is equipped.
# Called externally by GameState.recalculate_stats().
# Barbarian unarmored defense: AC = 10 + DEX + CON when no armor.
# Monk unarmored defense:     AC = 10 + DEX + WIS when no armor.
func recalc_ac(has_armor_equipped: bool) -> void:
	if character_class == CharacterClass.BARBARIAN and not has_armor_equipped:
		armor_class = 10 + dex_modifier() + con_modifier()
	elif character_class == CharacterClass.MONK and not has_armor_equipped:
		armor_class = 10 + dex_modifier() + wis_modifier()
	else:
		armor_class = 10 + dex_modifier()

# ── Save/load (Phase A — docs/architecture/SAVE_LOAD_ARCHITECTURE.md §4.1) ──────
# Persist mutable state only. Computed properties (proficiency_bonus, rage_uses_max,
# martial_arts_die_sides) and class-set flags (check_prof_*, weapon proficiency) are
# never saved — from_dict() re-derives them via apply_class_defaults().

func to_dict() -> Dictionary:
	return {
		"strength": strength,
		"dexterity": dexterity,
		"constitution": constitution,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"charisma": charisma,
		"character_class": int(character_class),
		"character_level": character_level,
		"character_race": int(character_race),
		"race_variant": race_variant,
		"race_prof_ability": race_prof_ability,
		"relentless_endurance_used": relentless_endurance_used,
		"heroic_inspiration_available": heroic_inspiration_available,
		"experience": experience,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"base_min_damage": base_min_damage,
		"base_max_damage": base_max_damage,
		"rage_uses_remaining": rage_uses_remaining,
		"temp_hp": temp_hp,
		"poison_turns": poison_turns,
		"burning_turns": burning_turns,
		"bleeding_turns": bleeding_turns,
		"slowed_turns": slowed_turns,
		"zealous_presence_turns": zealous_presence_turns,
		"known_weapon_masteries": known_weapon_masteries.duplicate(),
	}

# Order matters (doc §4.1): apply_class_defaults() first (resets scores/HP/flags),
# THEN saved values overwrite. armor_class and min/max_damage are not restored here —
# GameState.recalculate_stats() recomputes both from equipment after the full load.
func from_dict(d: Dictionary) -> void:
	character_class = int(d.get("character_class", CharacterClass.BARBARIAN)) as CharacterClass
	apply_class_defaults()
	character_race = int(d.get("character_race", CharacterRace.HUMAN)) as CharacterRace
	race_variant = int(d.get("race_variant", 0))
	race_prof_ability = int(d.get("race_prof_ability", -1))
	apply_race_defaults()
	relentless_endurance_used = bool(d.get("relentless_endurance_used", false))
	heroic_inspiration_available = bool(d.get("heroic_inspiration_available", true))
	strength = int(d.get("strength", strength))
	dexterity = int(d.get("dexterity", dexterity))
	constitution = int(d.get("constitution", constitution))
	intelligence = int(d.get("intelligence", intelligence))
	wisdom = int(d.get("wisdom", wisdom))
	charisma = int(d.get("charisma", charisma))
	character_level = int(d.get("character_level", 1))
	experience = int(d.get("experience", 0))
	max_hp = int(d.get("max_hp", max_hp))
	current_hp = int(d.get("current_hp", max_hp))
	base_min_damage = int(d.get("base_min_damage", base_min_damage))
	base_max_damage = int(d.get("base_max_damage", base_max_damage))
	rage_uses_remaining = int(d.get("rage_uses_remaining", 0))
	temp_hp = int(d.get("temp_hp", 0))
	poison_turns = int(d.get("poison_turns", 0))
	burning_turns = int(d.get("burning_turns", 0))
	bleeding_turns = int(d.get("bleeding_turns", 0))
	slowed_turns = int(d.get("slowed_turns", 0))
	zealous_presence_turns = int(d.get("zealous_presence_turns", 0))
	known_weapon_masteries.clear()
	for m: Variant in (d.get("known_weapon_masteries", []) as Array):
		known_weapon_masteries.append(String(m))

func apply_class_defaults() -> void:
	match character_class:
		CharacterClass.BARBARIAN:
			strength = 16; constitution = 14; dexterity = 12
			intelligence = 8; wisdom = 10; charisma = 10
			max_hp = 12 + modifier(constitution)   # Barbarian HD d12
			rage_uses_remaining = rage_uses_max    # = 2 at level 1
			check_prof_str = true
			check_prof_con = true
			proficient_simple_weapons = true
			proficient_martial_weapons = true
		CharacterClass.RANGER:
			dexterity = 16; wisdom = 14; constitution = 12
			strength = 10; intelligence = 10; charisma = 8
			max_hp = 10 + modifier(constitution)   # Ranger HD d10
			check_prof_str = true
			check_prof_dex = true
		CharacterClass.WIZARD:
			intelligence = 16; dexterity = 14; wisdom = 12
			constitution = 10; strength = 8; charisma = 10
			max_hp = 6 + modifier(constitution)    # Wizard HD d6
			check_prof_int = true
			check_prof_wis = true
		CharacterClass.MONK:
			dexterity = 16; wisdom = 14; constitution = 12
			strength = 10; intelligence = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Monk HD d8
			rage_uses_remaining = 0               # Monk never rages (rage_uses_max computed = 0)
			check_prof_str = true
			check_prof_dex = true
	current_hp = max_hp
	# Barbarian and Monk start unarmored — apply unarmored defense formulas.
	recalc_ac(false)

# Race defaults apply strictly AFTER class defaults, additively, and never touch the base
# ability scores — none of the six races grant a raw ability-score bonus (see
# docs/architecture/race-selection-design.md §2.3). Always fully re-derives darkvision_bonus/
# damage_resistances from character_race/race_variant (idempotent — safe to call again on respec
# or from_dict()).
func apply_race_defaults() -> void:
	darkvision_bonus = 0
	damage_resistances.clear()
	match character_race:
		CharacterRace.ORC:
			darkvision_bonus = 2
		CharacterRace.HUMAN:
			darkvision_bonus = 0
			heroic_inspiration_available = true
			if race_prof_ability >= 0:
				_grant_ability_proficiency(race_prof_ability)
		CharacterRace.HALFLING:
			darkvision_bonus = 0
		CharacterRace.DWARF:
			darkvision_bonus = 2
		CharacterRace.ELF:
			darkvision_bonus = 1
			check_prof_wis = true
		CharacterRace.DRAGONBORN:
			darkvision_bonus = 1
			var dmg_type: String = DRAGONBORN_DAMAGE_TYPE[clampi(race_variant, 0, DRAGONBORN_DAMAGE_TYPE.size() - 1)]
			damage_resistances = [dmg_type]

func _grant_ability_proficiency(idx: int) -> void:
	match idx:
		0: check_prof_str = true
		1: check_prof_dex = true
		2: check_prof_con = true
		3: check_prof_int = true
		4: check_prof_wis = true
		5: check_prof_cha = true
