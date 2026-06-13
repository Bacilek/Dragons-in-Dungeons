extends Node

signal floor_changed(new_floor: int)
signal player_hp_changed(current_hp: int, max_hp: int)
signal player_exp_changed(exp: int, exp_needed: int, level: int)
signal player_leveled_up(level: int)
signal player_died()
signal combat_message(msg: String)
signal inventory_changed()
signal player_action_requested(action_name: String)

const INVENTORY_SIZE: int = 5

var current_floor: int = 1
var player_stats: Stats
var run_seed: int = 0
var is_game_over: bool = false
var player_inventory: Array = []  # Array of Item or null

func _ready() -> void:
	start_new_run()

func start_new_run() -> void:
	run_seed = randi()
	current_floor = 1
	is_game_over = false
	player_stats = Stats.new()
	player_stats.apply_class_defaults()
	player_inventory.clear()
	for _i: int in INVENTORY_SIZE:
		player_inventory.append(null)

func advance_floor() -> void:
	current_floor += 1
	floor_changed.emit(current_floor)

func apply_damage(amount: int) -> void:
	player_stats.current_hp -= amount
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	if player_stats.current_hp <= 0:
		is_game_over = true

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

func add_item(item: Item) -> bool:
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] != null and (player_inventory[i] as Item).item_name == item.item_name:
			(player_inventory[i] as Item).quantity += item.quantity
			inventory_changed.emit()
			return true
	for i: int in INVENTORY_SIZE:
		if player_inventory[i] == null:
			player_inventory[i] = item
			inventory_changed.emit()
			return true
	log("[color=red]Your bag is full![/color]")
	return false

func log(msg: String) -> void:
	combat_message.emit(msg)
