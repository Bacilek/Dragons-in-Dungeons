class_name PlayerThrowTool
extends Node

# Throw-mode / tool-priming activation and the empty-bottle mechanic.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
#
# NOTE: `_throw_item`/`_tool_item` deliberately stay as FIELDS on Player itself (read from
# ~10 other input/movement call sites to cancel throw/tool mode on move/Esc/other actions) —
# only the functions below moved here; they mutate the fields via the `player` back-reference.

var player: Player

func on_throw_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._tool_item = null
	if player._throw_item != null:
		player._throw_item = item
		return
	player._throw_item = item
	GameState.game_log("[color=yellow]Throw [b]%s[/b] — left-click target tile. [Esc] to cancel.[/color]" % item.item_name)

func on_tool_primed(item: Item) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._throw_item = null
	player._tool_item = item
	if item.item_name == "Empty Bottle":
		GameState.game_log("[color=cyan]Empty Bottle — right-click on adjacent water or mud to fill. [Esc] to cancel.[/color]")
	else:
		GameState.game_log("[color=yellow]Thief Tools — click an adjacent revealed trap to disarm. [Esc] to cancel.[/color]")

func do_throw(pos: Vector2i) -> void:
	var item: Item = player._throw_item
	player._throw_item = null
	if player._dungeon_floor == null:
		return
	var _found: bool = false
	for _s in GameState.player_quickbar:
		if _s == item:
			_found = true
			break
	if not _found:
		for _s in GameState.player_inventory:
			if _s == item:
				_found = true
				break
	if not _found:
		GameState.game_log("[color=gray]Throw cancelled — item no longer in inventory.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("throw_item")
	if player._dungeon_floor.has_door_at(pos) and not player._dungeon_floor.is_door_open(pos):
		player._dungeon_floor.open_door(pos)
	var trap: Dictionary = player._dungeon_floor.get_trap_at(pos)
	var is_fire: bool = not trap.is_empty() and trap.get("name", "") == "Fire Trap" and trap.get("revealed", false)
	if is_fire and item.item_name == "Rotten Meat":
		GameState.consume_one(item)
		var cooked: Item = player._dungeon_floor.cook_rotten_meat(pos)
		player._dungeon_floor.place_item_on_floor(pos, cooked)
		GameState.game_log("[color=orange]You throw the meat into the fire — it sizzles and cooks! [b]Cooked Meat[/b] landed where the trap was.[/color]")
	else:
		var dropped := Item.new()
		dropped.item_name = item.item_name
		dropped.item_type = item.item_type
		dropped.heal_amount = item.heal_amount
		dropped.icon_path = item.icon_path
		dropped.description = item.description
		dropped.quantity = 1
		GameState.consume_one(item)
		player._dungeon_floor.place_item_on_floor(pos, dropped)
		GameState.game_log("[color=gray]You throw [b]%s[/b].[/color]" % dropped.item_name)
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

func make_empty_bottle() -> Item:
	var b := Item.new()
	b.item_name = "Empty Bottle"
	b.item_type = Item.Type.TOOL
	b.icon_path = "res://sprites/items/Materials/BottleSmall.png"
	b.description = "An empty glass bottle. Fill it from water or mud."
	return b

func try_fill_bottle(bottle: Item, target: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	var dist: int = maxi(absi(target.x - player.grid_pos.x), absi(target.y - player.grid_pos.y))
	if dist > 1:
		GameState.game_log("[color=gray]Too far — stand next to water or mud.[/color]")
		return
	var tile_t: DungeonData.TileType = player._dungeon_floor.get_tile_type(target)
	if tile_t != DungeonData.TileType.WATER and tile_t != DungeonData.TileType.MUD:
		GameState.game_log("[color=gray]Nothing to fill the bottle with here.[/color]")
		return
	TurnManager.begin_player_action()
	# Nat 1: bottle shatters
	var fill_roll: int = randi_range(1, 20)
	if fill_roll == 1:
		GameState.game_log("[color=red]You fumble — the bottle shatters![/color]")
		if not GameState.invincible:
			GameState.consume_one(bottle)
		GameState.inventory_changed.emit()
		player._dungeon_floor.update_fog(player.grid_pos)
		TurnManager.on_player_action_complete()
		return
	if tile_t == DungeonData.TileType.WATER:
		bottle.item_name = "Bottle of Water"
		bottle.icon_path = "res://sprites/items/Materials/BottleMedium.png"
		bottle.description = "A bottle of dungeon water."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=cyan]You fill the bottle with water.[/color]")
	else:
		bottle.item_name = "Bottle of Mud"
		bottle.icon_path = "res://sprites/items/Materials/BottleSmall.png"
		bottle.description = "A bottle of foul mud. Maybe useful for something."
		AudioManager.play("bottle_fill")
		GameState.game_log("[color=gray]You fill the bottle with mud.[/color]")
	GameState.inventory_changed.emit()
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()
