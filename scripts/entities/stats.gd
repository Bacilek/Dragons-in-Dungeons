class_name Stats
extends Resource

enum CharacterClass { BARBARIAN, RANGER, WIZARD, MONK }

# Check proficiency flags — which ability checks the class rolls with proficiency bonus.
# Barbarian: STR + CON. Ranger: STR + DEX. Wizard: INT + WIS. Monk: STR + DEX.
# Monk also has proficiency with simple weapons + martial weapons with light property (TODO: enforce).
var check_prof_str: bool = false
var check_prof_con: bool = false
var check_prof_dex: bool = false
var check_prof_int: bool = false
var check_prof_wis: bool = false
var check_prof_cha: bool = false

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var character_class: CharacterClass = CharacterClass.BARBARIAN
@export var character_level: int = 1

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
	match character_class:
		CharacterClass.BARBARIAN: return 7 + con_modifier()
		CharacterClass.RANGER:    return 6 + con_modifier()
		CharacterClass.WIZARD:    return 4 + con_modifier()
		CharacterClass.MONK:      return 5 + con_modifier()  # d8 avg = 5
		_:                        return 5 + con_modifier()

func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

func str_modifier() -> int: return modifier(strength)
func dex_modifier() -> int: return modifier(dexterity)
func con_modifier() -> int: return modifier(constitution)
func int_modifier() -> int: return modifier(intelligence)
func wis_modifier() -> int: return modifier(wisdom)
func cha_modifier() -> int: return modifier(charisma)

func ability_check(score: int, proficient: bool, dc: int) -> bool:
	var roll: int = randi_range(1, 20)
	var bonus: int = modifier(score) + (proficiency_bonus if proficient else 0)
	return (roll + bonus) >= dc

func roll_damage() -> int:
	return randi_range(min_damage, max_damage)

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

func apply_class_defaults() -> void:
	match character_class:
		CharacterClass.BARBARIAN:
			strength = 16; constitution = 14; dexterity = 12
			intelligence = 8; wisdom = 10; charisma = 10
			max_hp = 12 + modifier(constitution)   # Barbarian HD d12
			rage_uses_remaining = rage_uses_max    # = 2 at level 1
			check_prof_str = true
			check_prof_con = true
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
