class_name Stats
extends Resource

enum CharacterClass { FIGHTER, ROGUE, WIZARD, CLERIC }

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var character_class: CharacterClass = CharacterClass.FIGHTER
@export var character_level: int = 1

@export var max_hp: int = 10
@export var current_hp: int = 10
@export var armor_class: int = 10
@export var proficiency_bonus: int = 2

@export var min_damage: int = 1
@export var max_damage: int = 4
@export var armor: int = 0

@export var experience: int = 0

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
		max_hp += 5
		current_hp = mini(current_hp + 5, max_hp)
		strength += 1
		leveled = true
	return leveled

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

func apply_class_defaults() -> void:
	match character_class:
		CharacterClass.FIGHTER:
			strength = 16; constitution = 14; dexterity = 12
			intelligence = 10; wisdom = 10; charisma = 8
			max_hp = 10 + modifier(constitution)   # Fighter HD d10
		CharacterClass.ROGUE:
			dexterity = 16; intelligence = 14; constitution = 12
			strength = 10; wisdom = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Rogue HD d8
		CharacterClass.WIZARD:
			intelligence = 16; dexterity = 14; wisdom = 12
			constitution = 10; strength = 8; charisma = 10
			max_hp = 6 + modifier(constitution)    # Wizard HD d6
		CharacterClass.CLERIC:
			wisdom = 16; constitution = 14; strength = 12
			dexterity = 10; intelligence = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Cleric HD d8
	current_hp = max_hp
	armor_class = 10 + modifier(dexterity)
	proficiency_bonus = 2
