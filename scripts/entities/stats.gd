class_name Stats
extends Resource

enum CharacterClass { BARBARIAN, RANGER, WIZARD, CLERIC }

# --- Save proficiency flags (Barbarian: STR + CON) ---
# TODO: When spell saving throws are implemented, check `save_prof_str` / `save_prof_con`
# for Barbarian advantage on STR saves and automatic proficiency on both.
# Barbarian save proficiencies: Strength, Constitution.
# Other classes: Ranger = DEX+STR, Wizard = INT+WIS, Cleric = WIS+CHA.
var save_prof_str: bool = false
var save_prof_con: bool = false
var save_prof_dex: bool = false
var save_prof_int: bool = false
var save_prof_wis: bool = false
var save_prof_cha: bool = false

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

# Rage uses (Barbarian only). Reset to max on long rest (advance_floor in GameState).
# TODO: When multiple classes get abilities, move per-class resources to a separate struct.
var rage_uses_remaining: int = 0
var rage_uses_max: int = 2

var poison_turns: int = 0
var burning_turns: int = 0
var bleeding_turns: int = 0
var slowed_turns: int = 0

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
		CharacterClass.CLERIC:    return 5 + con_modifier()
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
	var actual: int = maxi(1, amount - armor)
	current_hp -= actual
	return actual

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
# Barbarian unarmored defense: if no armor equipped, AC = 10 + DEX + CON instead of 10 + DEX.
func recalc_ac(has_armor_equipped: bool) -> void:
	if character_class == CharacterClass.BARBARIAN and not has_armor_equipped:
		armor_class = 10 + dex_modifier() + con_modifier()
	else:
		armor_class = 10 + dex_modifier()

func apply_class_defaults() -> void:
	match character_class:
		CharacterClass.BARBARIAN:
			strength = 16; constitution = 14; dexterity = 12
			intelligence = 8; wisdom = 10; charisma = 10
			max_hp = 12 + modifier(constitution)   # Barbarian HD d12
			rage_uses_remaining = 2
			rage_uses_max = 2
			save_prof_str = true
			save_prof_con = true
		CharacterClass.RANGER:
			dexterity = 16; wisdom = 14; constitution = 12
			strength = 10; intelligence = 10; charisma = 8
			max_hp = 10 + modifier(constitution)   # Ranger HD d10
			save_prof_str = true
			save_prof_dex = true
		CharacterClass.WIZARD:
			intelligence = 16; dexterity = 14; wisdom = 12
			constitution = 10; strength = 8; charisma = 10
			max_hp = 6 + modifier(constitution)    # Wizard HD d6
			save_prof_int = true
			save_prof_wis = true
		CharacterClass.CLERIC:
			wisdom = 16; constitution = 14; strength = 12
			dexterity = 10; intelligence = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Cleric HD d8
			save_prof_wis = true
			save_prof_cha = true
	current_hp = max_hp
	# Barbarian starts with no armor → unarmored defense (DEX + CON)
	recalc_ac(false)
