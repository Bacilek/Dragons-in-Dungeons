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
signal player_throw_primed(item: Item)
signal player_tool_primed(item: Item)
signal class_chosen(chosen_class: Stats.CharacterClass)
signal hunger_changed(value: int)
signal player_status_changed()
signal debug_jump_floor(floor_num: int)
signal short_rest_changed
signal stairs_discovered
signal short_rest_completed
signal short_rest_aborted
signal camera_recenter_requested
signal debug_reveal_all
signal debug_see_all(active: bool)
signal crit_banner(text: String, color: Color)
signal screen_shake(strength: float)
signal potion_drunk
signal ability_bar_changed()
# Emitted when equip/unequip is done intentionally (costs 1 turn). Not emitted on auto-pickup.
signal equip_action_taken()

const QUICKBAR_SIZE: int = 9
const ABILITY_BAR_SIZE: int = 9
const INVENTORY_SIZE: int = 24

enum HungerState { SATIATED, HUNGRY, STARVING }
const MAX_HUNGER: int = 1000

const STARVE_INTERVAL: int = 10
var _starvation_tick: int = 0

var current_floor: int = 1
var player_stats: Stats
var run_seed: int = 0
var is_game_over: bool = false
var inventory_open: bool = false
var class_selected: bool = false
var invincible: bool = false
var noclip: bool = false
var god_mode: bool = false
var hit_dice: int = 1
var short_rests_remaining: int = 2
var max_short_rests: int = 2
var short_rest_open: bool = false
var short_rest_active: bool = false
var short_rest_turns_remaining: int = 0
var short_rest_pending_heal: int = 0
var player_grid_pos: Vector2i = Vector2i.ZERO
var current_stairs_pos: Vector2i = Vector2i.ZERO
var hunger: int = MAX_HUNGER
var hunger_state: HungerState:
	get:
		if hunger > 600: return HungerState.SATIATED
		if hunger > 200: return HungerState.HUNGRY
		return HungerState.STARVING

var player_quickbar: Array = []   # 9 item slots shown in HUD action bar
var player_ability_bar: Array = [] # 9 ability slots (Tab to switch)
var player_inventory: Array = []  # 24-slot bag

var equipment: Dictionary = {
	"melee": null, "ranged": null, "armor": null,
	"boots": null, "gloves": null, "head": null, "trinket": null,
}

# Convenience read-only properties (backward compat with player.gd)
var equipped_weapon: Item:
	get: return equipment.get("melee") as Item

var equipped_ranged: Item:
	get: return equipment.get("ranged") as Item

var equipped_armor: Item:
	get: return equipment.get("armor") as Item

func _ready() -> void:
	start_new_run()

func start_new_run() -> void:
	run_seed = randi()
	current_floor = 1
	is_game_over = false
	inventory_open = false
	class_selected = false
	invincible = false
	noclip = false
	short_rest_open = false
	hit_dice = 1
	short_rests_remaining = 2
	max_short_rests = 2
	hunger = MAX_HUNGER
	_starvation_tick = 0
	player_stats = Stats.new()
	player_stats.apply_class_defaults()  # defaults until class select overrides
	player_quickbar.clear()
	for _i: int in QUICKBAR_SIZE:
		player_quickbar.append(null)
	player_ability_bar.clear()
	for _i: int in ABILITY_BAR_SIZE:
		player_ability_bar.append(null)
	player_inventory.clear()
	for _i: int in INVENTORY_SIZE:
		player_inventory.append(null)
	for key: String in equipment:
		equipment[key] = null
	_give_starting_items()

func _give_starting_items() -> void:
	var ration := Item.new()
	ration.item_name = "Ration"
	ration.item_type = Item.Type.FOOD
	ration.heal_amount = 200
	ration.icon_path = "res://sprites/items/Food/MeatCooked.png"
	ration.description = "Fills you up"
	ration.quantity = 3
	add_item(ration)

	var tools := Item.new()
	tools.item_name = "Thief Tools"
	tools.item_type = Item.Type.TOOL
	tools.icon_path = "res://sprites/items/Misc/KeyIron.png"
	tools.description = "Left-click to use, then click an adjacent revealed trap to disarm. Consumed on failure."
	tools.quantity = 3
	add_item(tools)

# Called by class_select.gd after player picks a class, replaces generic starting gear.
func give_class_starting_items() -> void:
	if equipment.get("melee") != null or player_ability_bar[0] != null:
		return
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN:
			_give_barbarian_starting_items()
		Stats.CharacterClass.MONK:
			_give_monk_starting_items()

func _give_barbarian_starting_items() -> void:
	var axe := Item.new()
	axe.item_name = "Greataxe"
	axe.item_type = Item.Type.WEAPON
	axe.icon_path = "res://sprites/weapons/weapon_double_axe.png"
	axe.description = ""
	axe.is_heavy = true
	axe.bonus_damage = 0      # proficiency adds to attack roll, not to damage
	axe.damage_die_min = 1    # weapon defines its own dice: 1d12
	axe.damage_die_max = 12
	axe.floor_min = 1
	axe.floor_max = 10
	axe.is_ranged = false
	axe.is_two_handed = true
	axe.damage_type = "Slashing"
	# Equip silently (no turn cost, no turn consumed — startup)
	equipment["melee"] = axe
	recalculate_stats()
	equipment_changed.emit()

	# Rage ability in slot 0 of ability bar
	var rage := Ability.new()
	rage.ability_id = "rage"
	rage.ability_name = "Rage"
	rage.description = "2 uses/long rest. Resistance to all damage (half, rounded down). +2 STR weapon damage. STR checks/saves with advantage. Lasts 1 round; extended by attacking, forcing saves, or using a bonus action to maintain. Ends if heavy armor worn."
	rage.icon_path = "res://sprites/weapons/weapon_double_axe.png"
	rage.uses_remaining = player_stats.rage_uses_remaining
	rage.uses_max = player_stats.rage_uses_max
	add_ability(rage)

func _give_monk_starting_items() -> void:
	# Monks start unarmed — fists are their weapons.
	# Unarmored Defense passive
	var ud := Ability.new()
	ud.ability_id = "unarmored_defense_monk"
	ud.ability_name = "Unarmored Defense"
	ud.description = "Passive: AC = 10 + DEX + WIS while wearing no armor."
	ud.icon_path = "res://sprites/items/Misc/KeyIron.png"
	ud.uses_remaining = 0
	ud.uses_max = 0
	add_ability(ud)
	# Martial Arts passive — die scales with level (1d6 → 1d8 → 1d10 → 1d12)
	var ma := Ability.new()
	ma.ability_id = "martial_arts"
	ma.ability_name = "Martial Arts"
	ma.description = "Passive: Unarmed strikes use DEX + 1d6. After a main-action unarmed strike, make a free bonus-action unarmed strike. Die scales at levels 5/11/17."
	ma.icon_path = "res://sprites/items/Misc/KeyIron.png"
	ma.uses_remaining = 0
	ma.uses_max = 0
	add_ability(ma)
	recalculate_stats()
	equipment_changed.emit()

func _find_ability_by_id(id: String) -> Ability:
	for slot in player_ability_bar:
		if slot != null and (slot as Ability).ability_id == id:
			return slot as Ability
	return null

func add_ability(ability: Ability) -> bool:
	for i: int in ABILITY_BAR_SIZE:
		if player_ability_bar[i] == null:
			player_ability_bar[i] = ability
			ability_bar_changed.emit()
			return true
	game_log("[color=red]Ability bar is full![/color]")
	return false

func advance_floor() -> void:
	current_floor += 1
	short_rests_remaining = 2
	max_short_rests = 2
	short_rest_changed.emit()
	floor_changed.emit(current_floor)
	if current_floor > 10:
		player_won.emit()

# Keeps ability resource uses_remaining in sync with player_stats after a long rest.
func _sync_ability_uses() -> void:
	for slot in player_ability_bar:
		if slot == null:
			continue
		var ab := slot as Ability
		if ab.ability_id == "rage":
			ab.uses_remaining = player_stats.rage_uses_remaining
			ab.uses_max = player_stats.rage_uses_max
	ability_bar_changed.emit()

func hit_die_sides() -> int:
	match player_stats.character_class:
		Stats.CharacterClass.BARBARIAN: return 12
		Stats.CharacterClass.RANGER:    return 10
		Stats.CharacterClass.MONK:      return 8
		Stats.CharacterClass.WIZARD:    return 6
		_:                              return 8

func check_player_death() -> void:
	if player_stats.is_dead() and not is_game_over and not invincible:
		is_game_over = true
		AudioManager.play("player_die")
		player_died.emit()

func heal(amount: int) -> void:
	player_stats.current_hp = mini(player_stats.current_hp + amount, player_stats.max_hp)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)

func gain_exp(amount: int) -> void:
	var old_max_hp: int = player_stats.max_hp
	var leveled_up := player_stats.gain_exp(amount)
	player_exp_changed.emit(player_stats.experience, player_stats.exp_to_next(), player_stats.character_level)
	if leveled_up:
		player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
		player_leveled_up.emit(player_stats.character_level)
		var hp_gained: int = player_stats.max_hp - old_max_hp
		hit_dice = player_stats.character_level
		player_stats.rage_uses_remaining = player_stats.rage_uses_max
		_sync_ability_uses()
		max_short_rests += 1
		short_rests_remaining = mini(short_rests_remaining + 1, max_short_rests)
		combat_message.emit("[color=yellow]Level up! You are now level %d. (+%d max HP, fully restored, +1 hit die)[/color]" % [player_stats.character_level, hp_gained])
		heal(player_stats.max_hp - player_stats.current_hp)
		short_rest_changed.emit()
		_apply_barbarian_level_features(player_stats.character_level)
		_apply_monk_level_features(player_stats.character_level)

func debug_level_up() -> void:
	gain_exp(player_stats.exp_to_next())
	player_stats.experience = 0
	player_exp_changed.emit(0, player_stats.exp_to_next(), player_stats.character_level)

# ── Equipment ─────────────────────────────────────────────────────────────────

# costs_turn: if true, emits equip_action_taken so player.gd consumes 1 turn.
# Pass false for auto-equip on pickup and startup.
func equip(item: Item, slot_name: String = "", costs_turn: bool = false) -> void:
	if slot_name == "":
		match item.item_type:
			Item.Type.WEAPON:
				if item.is_ranged:
					slot_name = "ranged"
				else:
					slot_name = "melee"
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
	if costs_turn and class_selected:
		equip_action_taken.emit()

func unequip(slot_name: String, costs_turn: bool = false) -> void:
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
		if costs_turn and class_selected:
			equip_action_taken.emit()
	else:
		combat_message.emit("[color=red]No bag space to unequip %s![/color]" % item.item_name)

func recalculate_stats() -> void:
	var s: Stats = player_stats
	s.armor = 0
	var has_armor: bool = (equipment.get("armor") as Item) != null
	s.recalc_ac(has_armor)
	# Start from weapon's own damage die if it defines one, else base stats
	var melee: Item = equipment.get("melee") as Item
	if melee != null and melee.damage_die_min > 0:
		s.min_damage = melee.damage_die_min + melee.bonus_damage
		s.max_damage = melee.damage_die_max + melee.bonus_damage
	else:
		s.min_damage = s.base_min_damage + (melee.bonus_damage if melee != null else 0)
		s.max_damage = s.base_max_damage + (melee.bonus_damage if melee != null else 0)
	for slot_name: String in equipment:
		var it: Item = equipment[slot_name] as Item
		if it == null:
			continue
		if slot_name == "melee":
			continue  # already handled above
		s.armor_class += it.bonus_ac

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
	# Drag-drop into/from equipment slot costs 1 turn
	var touches_equip: bool = (src == "equipment" or dest == "equipment")
	if touches_equip and class_selected:
		equip_action_taken.emit()

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
			AudioManager.play("drink_potion")
			if item.heal_dice_count > 0:
				# Dice-based heal (e.g. 2d4+CON for Health Potion)
				var raw_roll: int = 0
				for _i: int in item.heal_dice_count:
					raw_roll += randi_range(1, item.heal_dice_sides)
				var con_mod: int = player_stats.con_modifier()
				var amount: int = maxi(1, raw_roll + con_mod)
				var before: int = player_stats.current_hp
				heal(amount)
				var healed: int = player_stats.current_hp - before
				if healed > 0:
					var _hm: String = "heal:dice=%d,sides=%d,con=%d,roll=%d,total=%d" % [item.heal_dice_count, item.heal_dice_sides, con_mod, raw_roll, healed]
					combat_message.emit("You drink [b]%s[/b] and heal [url=%s][color=lime]+%d HP[/color][/url]" % [item.item_name, _hm, healed])
				else:
					combat_message.emit("[color=gray]Already at full health.[/color]")
			elif item.heal_amount > 0:
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
			if not invincible:
				consume_one(item)
			potion_drunk.emit()
		Item.Type.FOOD:
			AudioManager.play("eat_food")
			if item.item_name == "Rotten Meat":
				restore_hunger(item.heal_amount)
				player_stats.poison_turns = maxi(player_stats.poison_turns, 3)
				player_status_changed.emit()
				game_log("[color=red]You choke down the rotten meat. You feel sick! (Poisoned 3 turns)[/color]")
			else:
				restore_hunger(item.heal_amount)
				game_log("[color=green]You eat [b]%s[/b]. Not so hungry anymore.[/color]" % item.item_name)
			consume_one(item)
		Item.Type.WEAPON, Item.Type.ARMOR:
			equip(item, "", true)  # intentional equip from bag/quickbar costs 1 turn
		Item.Type.TOOL:
			player_tool_primed.emit(item)

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

func game_log(msg: String) -> void:
	combat_message.emit(msg)

# ── Hunger ────────────────────────────────────────────────────────────────────

func deplete_hunger() -> void:
	if is_game_over:
		return
	var prev_state: HungerState = hunger_state
	hunger = maxi(0, hunger - 1)
	hunger_changed.emit(hunger)
	var new_state: HungerState = hunger_state
	if new_state != prev_state:
		if new_state == HungerState.HUNGRY:
			AudioManager.play("hungry")
		elif new_state == HungerState.STARVING:
			AudioManager.play("starving")
	if hunger == 0:
		_starvation_tick += 1
		if _starvation_tick >= STARVE_INTERVAL:
			_starvation_tick = 0
			take_damage_raw(1)
			game_log("[color=red]You are starving![/color]")
	else:
		_starvation_tick = 0

func restore_hunger(amount: int) -> void:
	hunger = mini(MAX_HUNGER, hunger + amount)
	hunger_changed.emit(hunger)

# is_raging is set by player.gd and read here to apply damage resistance.
var is_raging: bool = false
# reckless_attack_active is set by player.gd; enemies read it to gain ADV on their attacks.
var reckless_attack_active: bool = false
# Set true after first reckless attack this turn — locks the toggle and blocks ADV on 2nd attack.
var reckless_locked_this_turn: bool = false

func take_damage_raw(amount: int, ignore_rage: bool = false) -> void:
	if is_game_over or invincible:
		return
	var final_amount: int = amount
	# Rage: resistance to all physical damage (half, rounded down).
	# TODO: Once enemies have damage types (Bludgeoning/Piercing/Slashing), restrict resistance
	# to only those three types instead of all damage. For now all melee damage counts.
	if is_raging and not ignore_rage:
		final_amount = amount / 2
	player_stats.take_damage(final_amount)
	player_hp_changed.emit(player_stats.current_hp, player_stats.max_hp)
	check_player_death()

func _apply_barbarian_level_features(level: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.BARBARIAN:
		return
	match level:
		2:
			player_stats.danger_sense = true
			# Danger Sense — passive, shows in ability bar
			var ds := Ability.new()
			ds.ability_id = "danger_sense"
			ds.ability_name = "Danger Sense"
			ds.description = "Passive: advantage on DEX saves against traps."
			ds.icon_path = "res://sprites/items/Misc/KeyIron.png"
			ds.uses_remaining = 0
			ds.uses_max = 0
			add_ability(ds)
			# Reckless Attack — toggle, infinite uses
			var ra := Ability.new()
			ra.ability_id = "reckless_attack"
			ra.ability_name = "Reckless"
			ra.description = "Toggle (free action): advantage on all STR melee attacks this turn. Enemies also gain advantage against you until your next turn."
			ra.icon_path = "res://sprites/weapons/weapon_double_axe.png"
			ra.uses_remaining = 0
			ra.uses_max = 0
			add_ability(ra)
			combat_message.emit("[color=cyan]Level 2 Barbarian: [b]Danger Sense[/b] + [b]Reckless Attack[/b] unlocked![/color]")
		3:
			player_stats.rage_uses_max += 1
			player_stats.rage_uses_remaining = player_stats.rage_uses_max
			_sync_ability_uses()
			combat_message.emit("[color=cyan]Level 3 Barbarian: +1 Rage use — now [b]%d[/b] per long rest![/color]" % player_stats.rage_uses_max)
		4:
			player_stats.strength += 2
			recalculate_stats()
			combat_message.emit("[color=cyan]Level 4 Barbarian: STR +2 (now [b]%d[/b], modifier +%d)![/color]" % [player_stats.strength, player_stats.str_modifier()])
		5:
			player_stats.extra_attack = true
			combat_message.emit("[color=cyan]Level 5 Barbarian: [b]Extra Attack[/b]! Your first melee attack no longer ends your turn.[/color]")

func _apply_monk_level_features(level: int) -> void:
	if player_stats.character_class != Stats.CharacterClass.MONK:
		return
	var die_sides: int = player_stats.martial_arts_die_sides
	match level:
		4:
			player_stats.dexterity += 2
			recalculate_stats()
			combat_message.emit("[color=cyan]Level 4 Monk: DEX +2 (now [b]%d[/b], modifier +%d)![/color]" % [player_stats.dexterity, player_stats.dex_modifier()])
		5, 11, 17:
			var ma: Ability = _find_ability_by_id("martial_arts")
			if ma != null:
				ma.description = "Passive: Unarmed strikes use DEX + 1d%d. Bonus-action unarmed strike after main-action attack. Die scales at levels 5/11/17." % die_sides
			ability_bar_changed.emit()
			combat_message.emit("[color=cyan]Level %d Monk: Martial Arts die increased to [b]1d%d[/b]![/color]" % [level, die_sides])

func debug_jump_to_floor(n: int) -> void:
	is_game_over = false
	current_floor = n
	floor_changed.emit(current_floor)
	debug_jump_floor.emit(n)
