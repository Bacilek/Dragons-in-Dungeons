class_name Item
extends Resource

enum Type { WEAPON, ARMOR, POTION, SCROLL, FOOD, GOLD, KEY }

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

func get_display_name() -> String:
	if quantity > 1:
		return "%s ×%d" % [item_name, quantity]
	return item_name
