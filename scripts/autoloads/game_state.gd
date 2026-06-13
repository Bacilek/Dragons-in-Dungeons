extends Node

signal floor_changed(new_floor: int)
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_exp_changed(exp: int, exp_needed: int, level: int)
signal player_leveled_up(level: int)
signal player_died()
signal player_won()
signal combat_message(msg: String)
signal inventory_changed()
signal equipment_changed()
signal inventory_toggle()
signal player_action_requested(action_name: String)

const QUICKBAR_SIZE: int = 5
const INVENTORY_SIZE: int = 24

var current_floor: int = 1
var player_stats: Stats
var run_seed: int = 0
var is_game_over: bool = false
var inventory_open: bool = false

var player_quickbar: Array = []   # 5 slots shown in HUD action bar
var player_inventory: Array = []  # 24-slot bag

var equipment: Dictionary = {
	"right_hand": null, "left_hand": null, "armor": null,
	"boots": null, "gloves": null, "head": null, "trinket": null,
}

# Convenience read-only properties (backward compat with player.gd)
var equipped_weapon: Item:
	get: return equipment.get("right_hand") as Item

var equipped_armor: Item:
	get: return equipment.get("armor") as Item

func _ready() -> void:
	start_new_run()

func start_new_run() -> void:
	run_seed = randi()
	current_floor = 1
	is_game_over = false
	inventory_open = false
	player_stats = Stats.new()
	player_stats.apply_class_defaults()
	player_quickbar.clear()
	for _i: int in QUICKBAR_SIZE:
		player_quickbar.append(null)
	player_inventory.clear()
	for _i: int in INVENTORY_SIZE:
		player_inventory.append(null)
	for key: String in equipment:
		equipment[key] = null

func advance_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)
	if current_floor > 10:
		player_won.emit()

func check_player_death() -> void:
	if player_stats.is_dead() and not is_game_over:
		is_game_over = true
		player_died.emit()

func heal(amount: int) -> void:
	player_stats.current_hp = mini(player_stats.current_hp + amount, player_stats.max_hp)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)

func gain_exp(amount: int) -> void:
	var leveled_up := player_stats.gain_exp(amount)
	player_exp_changed.emit(player_stats.experience, player_stats.exp_to_next(), player_stats.character_level)
	if leveled_up:
		player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
		player_leveled_up.emit(player_stats.character_level)
		combat_message.emit("[color=yellow]Level up! You are now level %d. (+5 HP, +1 STR)[/color]" % player_stats.character_level)

# ── Equipment ─────────────────────────────────────────────────────────────────

func equip(item: Item, slot_name: String = "") -> void:
	if slot_name == "":
		match item.item_type:
			Item.Type.WEAPON: slot_name = "right_hand"
			Item.Type.ARMOR:  slot_name = "armor"
			_: return
	if not equipment.has(slot_name):
		return
	var prev: Item = equipment[slot_name] as Item
	equipment[slot_name] = item
	_remove_from_bags(item)
	if prev != null:
		_add_to_bags_silent(prev)
	recalculate_stats()
	combat_message.emit("[color=cyan]Equipped [b]%s[/b].[/color]" % item.item_name)
	equipment_changed.emit()
	inventory_changed.emit()

func unequip(slot_name: String) -> void:
	if not equipment.has(slot_name):
		return
	var item: Item = equipment[slot_name] as Item
	if item == null:
		return
	if add_item(item):
		equipment[slot_name] = null
		recalculate_stats()
		combat_message.emit("[color=cyan]Unequipped [b]%s[/b].[/color]" % item.item_name)
		equipment_changed.emit()
	else:
		combat_message.emit("[color=red]No bag space to unequip %s![/color]" % item.item_name)

func recalculate_stats() -> void:
	var s: Stats = player_stats
	s.min_damage = s.base_min_damage
	s.max_damage = s.base_max_damage
	s.armor = 0
	for slot_name: String in equipment:
		var it: Item = equipment[slot_name] as Item
		if it == null:
			continue
		s.min_damage += it.bonus_damage
		s.max_damage += it.bonus_damage
		s.armor += it.bonus_ac

func move_item(src: String, src_idx: int, src_slot: String,
			   dest: String, dest_idx: int, dest_slot: String) -> void:
	if src == dest and src_idx == dest_idx and src_slot == dest_slot:
		return
	var src_item: Item  = _get_slot_item(src, src_idx, src_slot)
	var dest_item: Item = _get_slot_item(dest, dest_idx, dest_slot)
	_set_slot_item(src, src_idx, src_slot, dest_item)
	_set_slot_item(dest, dest_idx, dest_slot, src_item)
	recalculate_stats()
	equipment_changed.emit()
	inventory_changed.emit()

func _get_slot_item(source: String, idx: int, slot_name: String) -> Item:
	match source:
		"equipment": return equipment.get(slot_name) as Item
		"quickbar":
			if idx >= 0 and idx < player_quickbar.size():
				return player_quickbar[idx] as Item
		"inventory":
			if idx >= 0 and idx < player_inventory.size():
				return player_inventory[idx] as Item
	return null

func _set_slot_item(source: String, idx: int, slot_name: String, item: Item) -> void:
	match source:
		"equipment": equipment[slot_name] = item
		"quickbar":
			if idx >= 0 and idx < player_quickbar.size():
				player_quickbar[idx] = item
		"inventory":
			if idx >= 0 and idx < player_inventory.size():
				player_inventory[idx] = item

# ── Item management ───────────────────────────────────────────────────────────

func add_item(item: Item) -> bool:
	# Try stacking in quickbar, then bag
	for i: int in QUICKBAR_SIZE:
		var ex: Item = player_quickbar[i] as Item
		if ex != null and ex.item_name == item.item_name:
			ex.quantity += item.quantity
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		var ex: Item = player_inventory[i] as Item
		if ex != null and ex.item_name == item.item_name:
			ex.quantity += item.quantity
			inventory_changed.emit()
			return true
	# Empty quickbar slot first, then bag
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == null:
			player_quickbar[i] = item
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			player_inventory[i] = item
			inventory_changed.emit()
			return true
	combat_message.emit("[color=red]Your bag is full![/color]")
	return false

func use_item(item: Item) -> void:
	match item.item_type:
		Item.Type.POTION:
			if item.heal_amount > 0:
				var before: int = player_stats.current_hp
				heal(item.heal_amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					combat_message.emit("[color=green]You drink [b]%s[/b] and recover %d HP.[/color]" % [item.item_name, healed])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
			if item.str_bonus > 0:
				player_stats.base_min_damage += item.str_bonus
				player_stats.base_max_damage += item.str_bonus
				recalculate_stats()
				combat_message.emit("[color=yellow]You drink [b]%s[/b]. Your attacks surge! (+%d ATK)[/color]" % [item.item_name, item.str_bonus])
			consume_one(item)
		Item.Type.WEAPON, Item.Type.ARMOR:
			equip(item)

func consume_one(item: Item) -> void:
	if item.quantity > 1:
		item.quantity -= 1
		inventory_changed.emit()
	else:
		remove_item(item)

func remove_item(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == item:
			player_quickbar[i] = null
			inventory_changed.emit()
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == item:
			player_inventory[i] = null
			inventory_changed.emit()
			return

func _remove_from_bags(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == item:
			player_quickbar[i] = null
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == item:
			player_inventory[i] = null
			return

func _add_to_bags_silent(item: Item) -> void:
	for i: int in QUICKBAR_SIZE:
		if player_quickbar[i] == null:
			player_quickbar[i] = item
			return
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			player_inventory[i] = item
			return

func log(msg: String) -> void:
	combat_message.emit(msg)
