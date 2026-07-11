class_name PlayerActions
extends Node

# Panel openers, wait/search/inspect, passive trap perception, floor pickup, and door/trap
# interact dispatch. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md.

var player: Player

var _last_search_request: float = -999.0
var _traps_in_proximity: Array[Vector2i] = []

func open_short_rest() -> void:
	GameState.short_rest_open = true
	var panel_script = load("res://scripts/ui/short_rest_panel.gd")
	player.get_tree().root.add_child(panel_script.new())

func open_talent_picker() -> void:
	if GameState._class_talents.is_empty():
		return
	var picker = load("res://scripts/ui/talent_picker.gd").new()
	player.get_tree().root.add_child(picker)

func check_pickup() -> void:
	if player._dungeon_floor == null:
		return
	var items: Array[Item] = player._dungeon_floor.get_items_at(player.grid_pos)
	if items.is_empty():
		return
	player._dungeon_floor.remove_floor_item(player.grid_pos)
	# Multiple items can be stacked on one tile (e.g. every arrow that landed on the same
	# spot) — pick up the whole stack in one step. Silent: no chat log line per pickup.
	for item: Item in items:
		var is_first_weapon: bool = item.item_type == Item.Type.WEAPON and GameState.equipped_weapon == null
		GameState.add_item(item)
		if is_first_weapon:
			GameState.equip(item)

func wait_action() -> void:
	TurnManager.begin_player_action()
	GameState.game_log("[color=gray]You skipped a turn.[/color]")
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

func do_rest_wait_turn() -> void:
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.begin_player_action()
	TurnManager.on_player_action_complete()

func handle_search_request() -> void:
	var now: float = Time.get_ticks_msec() / 1000.0
	if now - _last_search_request < 0.5:
		# Double press — trigger actual search
		player._inspect_mode = false
		_last_search_request = -999.0
		search_action()
	else:
		# First press — enter inspect mode
		_last_search_request = now
		player._inspect_mode = true
		GameState.game_log("[color=cyan]Inspect — left-click any visible tile for info. [Esc] to cancel. Press Ctrl/Search again to search area.[/color]")

func search_action() -> void:
	if player._dungeon_floor == null:
		return
	TurnManager.begin_player_action()
	var wis_mod: int = GameState.player_stats.wis_modifier()
	var dc: int = maxi(10, 10 + GameState.current_floor / 3)
	var die1: int = Rng.roll(20)
	var die2: int = Rng.roll(20)
	var roll: int = maxi(die1, die2) + wis_mod
	if roll >= dc:
		var found: int = player._dungeon_floor.search_around(player.grid_pos)
		if found > 0:
			GameState.game_log("[color=cyan]You search carefully and reveal %d trap(s)! (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [found, die1, die2, maxi(die1, die2), wis_mod, roll, dc])
		else:
			GameState.game_log("[color=gray]You search but find nothing suspicious. (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [die1, die2, maxi(die1, die2), wis_mod, roll, dc])
	else:
		GameState.game_log("[color=gray]You search but notice nothing. (adv [%d,%d]→%d+%d=[color=yellow]%d[/color] vs DC %d)[/color]" % [die1, die2, maxi(die1, die2), wis_mod, roll, dc])
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

func do_inspect(pos: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	if not player._dungeon_floor.is_explored(pos):
		GameState.game_log("[color=gray]You haven't explored that area.[/color]")
		return
	if not player._dungeon_floor.is_tile_visible(pos):
		GameState.game_log("[color=gray]You can't see that from here.[/color]")
		return
	var enemy: Enemy = player._dungeon_floor.get_enemy_at(pos)
	if enemy != null and enemy.visible:
		if GameState.god_mode:
			GameState.game_log("[color=orange]%s[/color] — HP: %d/%d  AC: %d  Dmg: %d–%d  EXP: %d%s" % [
				enemy.display_name,
				enemy.stats.current_hp, enemy.stats.max_hp,
				enemy.stats.armor_class,
				enemy.stats.min_damage, enemy.stats.max_damage,
				enemy.exp_reward,
				"  [color=red]BOSS[/color]" if enemy.is_boss else ""])
		else:
			GameState.game_log("[color=orange]%s[/color] — HP: %d/%d, AC: %d" % [enemy.display_name, enemy.stats.current_hp, enemy.stats.max_hp, enemy.stats.armor_class])
		return
	var trap: Dictionary = player._dungeon_floor.get_trap_at(pos)
	if not trap.is_empty() and trap.get("revealed", false):
		GameState.game_log("[color=orange]%s[/color] — revealed trap" % trap.get("name", "Trap"))
		return
	var floor_stack: Array[Item] = player._dungeon_floor.get_items_at(pos)
	if not floor_stack.is_empty():
		var floor_item: Item = floor_stack.back()
		var extra: String = " (+%d more)" % (floor_stack.size() - 1) if floor_stack.size() > 1 else ""
		GameState.game_log("[color=cyan]%s[/color] — on the floor%s" % [floor_item.get_display_name(), extra])
		return
	var tile_t: DungeonData.TileType = player._dungeon_floor.get_tile_type(pos)
	var tile_name: String
	match tile_t:
		DungeonData.TileType.FLOOR:          tile_name = "Stone floor"
		DungeonData.TileType.WALL:           tile_name = "Stone wall"
		DungeonData.TileType.STAIRS_DOWN:    tile_name = "Stairs leading down"
		DungeonData.TileType.CHASM:          tile_name = "Chasm — deadly fall"
		DungeonData.TileType.WATER:          tile_name = "Water — slows movement"
		DungeonData.TileType.MUD:            tile_name = "Mud — slows movement"
		DungeonData.TileType.GRASS:          tile_name = "Tall grass — blocks line of sight"
		DungeonData.TileType.TRAMPLED_GRASS: tile_name = "Trampled grass"
		_:                                   tile_name = "Unknown"
	GameState.game_log("[color=gray]%s.[/color]" % tile_name)

func passive_trap_check() -> void:
	if player._dungeon_floor == null:
		return
	var wis_mod: int = GameState.player_stats.wis_modifier()
	var dc: int = maxi(8, 8 + GameState.current_floor / 2)
	var now_in_range: Array[Vector2i] = []
	for trap_pos: Vector2i in player._dungeon_floor.get_unrevealed_traps():
		var diff: Vector2i = trap_pos - player.grid_pos
		if maxi(absi(diff.x), absi(diff.y)) > 2:
			continue
		now_in_range.append(trap_pos)
		if trap_pos in _traps_in_proximity:
			continue  # already knew it was near — don't re-roll
		var die: int = Rng.roll(20)
		if die + wis_mod >= dc:
			player._dungeon_floor.reveal_trap(trap_pos)
			if player._queued_path.size() > 0:
				player._queued_path.clear()
				GameState.game_log("[color=yellow]You notice something suspicious nearby and stop cautiously.[/color]")
			else:
				GameState.game_log("[color=yellow]You notice something suspicious on the floor.[/color]")
	_traps_in_proximity = now_in_range

func interact_action(can_lock: bool = true, target: Vector2i = Vector2i(-1, -1)) -> void:
	if player._dungeon_floor == null:
		return
	var dirs8: Array[Vector2i] = [
		Vector2i(0,-1), Vector2i(0,1), Vector2i(-1,0), Vector2i(1,0),
		Vector2i(-1,-1), Vector2i(1,-1), Vector2i(-1,1), Vector2i(1,1)
	]
	# Priority 1: revealed trap
	# When called from RMB with a target tile, only check that exact tile.
	# When called from keyboard/debug (no target), scan all 8 neighbors.
	var trap_tiles: Array[Vector2i] = []
	if target != Vector2i(-1, -1):
		var diff: Vector2i = target - player.grid_pos
		if abs(diff.x) <= 1 and abs(diff.y) <= 1:
			trap_tiles.append(target)
	else:
		for d: Vector2i in dirs8:
			trap_tiles.append(player.grid_pos + d)
	for pos: Vector2i in trap_tiles:
		var trap: Dictionary = player._dungeon_floor.get_trap_at(pos)
		if not trap.is_empty() and trap.get("revealed", false):
			player._thief_tools.attempt_disarm(pos)
			return
	# Priority 2: door
	# When called from RMB (target provided), only interact with that exact tile if adjacent.
	# When called from F key (no target), scan all 8 neighbors for the first door.
	var door_candidates: Array[Vector2i] = []
	if target != Vector2i(-1, -1):
		var diff: Vector2i = target - player.grid_pos
		if abs(diff.x) <= 1 and abs(diff.y) <= 1 and player._dungeon_floor.has_door_at(target):
			door_candidates.append(target)
	else:
		for d: Vector2i in dirs8:
			var pos: Vector2i = player.grid_pos + d
			if player._dungeon_floor.has_door_at(pos):
				door_candidates.append(pos)
	for pos: Vector2i in door_candidates:
		if player._dungeon_floor.is_door_locked(pos):
			if player._dungeon_floor.is_door_player_locked(pos):
				# Player set this lock — can unlock freely (free action on F)
				TurnManager.begin_player_action()
				player._dungeon_floor.unlock_door(pos)
				player._dungeon_floor.open_door(pos)
				GameState.game_log("[color=cyan]You unlock your own lock and open the door.[/color]")
				player._dungeon_floor.update_fog(player.grid_pos)
				TurnManager.on_player_action_complete()
			else:
				# Dungeon-generated lock — attempt to pick with Thief Tools
				if player._thief_tools.find_thief_tools() != null:
					player._thief_tools.attempt_disarm_lock(pos)
				else:
					GameState.game_log("[color=red]Locked. You need Thief Tools to pick this lock.[/color]")
			return
		if player._dungeon_floor.is_door_open(pos):
			# F/RMB on open door → close it
			TurnManager.begin_player_action()
			player._dungeon_floor.close_door(pos)
			player._dungeon_floor.update_fog(player.grid_pos)
			TurnManager.on_player_action_complete()
			return
		# Closed unlocked door: lock if tools available, else open
		if can_lock and player._thief_tools.find_thief_tools() != null:
			player._thief_tools.attempt_lock_door(pos)
		else:
			TurnManager.begin_player_action()
			player._dungeon_floor.open_door(pos)
			player._dungeon_floor.update_fog(player.grid_pos)
			TurnManager.on_player_action_complete()
		return
	GameState.game_log("[color=gray]Nothing to interact with nearby.[/color]")

func find_item_by_name(item_name: String) -> Item:
	for slot: Item in GameState.player_quickbar:
		if slot != null and slot.item_name == item_name:
			return slot
	for slot: Item in GameState.player_inventory:
		if slot != null and slot.item_name == item_name:
			return slot
	return null
