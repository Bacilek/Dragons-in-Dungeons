class_name Item
extends Resource

enum Type { WEAPON, ARMOR, POTION, SCROLL, FOOD, GOLD, KEY }

@export var item_name: String = ""
@export var item_type: Type = Type.POTION
@export var quantity: int = 1
@export var description: String = ""
@export var icon_path: String = ""

func get_display_name() -> String:
	if quantity > 1:
		return "%s ×%d" % [item_name, quantity]
	return item_name
