class_name PlayerAmmo
extends Node

# Named-ammo stack bookkeeping + landing resolution. Composition child-node split out of
# player.gd — see scripts/entities/CLAUDE.md.

var player: Player

# Named-ammo lookup (Item.ammo_item_name), separate from the legacy consumes_on_ranged
# (weapon's own quantity) pattern. Searches quickbar then bag by item_name, same order as
# GameState.add_item()'s stacking search.
func find_ammo_stack(ammo_name: String) -> Item:
	for it: Item in GameState.player_quickbar:
		if it != null and it.item_name == ammo_name and it.quantity > 0:
			return it
	for it: Item in GameState.player_inventory:
		if it != null and it.item_name == ammo_name and it.quantity > 0:
			return it
	return null

func remove_ammo_stack(ammo_name: String) -> void:
	for i: int in GameState.player_quickbar.size():
		var it: Item = GameState.player_quickbar[i]
		if it != null and it.item_name == ammo_name:
			GameState.player_quickbar[i] = null
			return
	for i: int in GameState.player_inventory.size():
		var it: Item = GameState.player_inventory[i]
		if it != null and it.item_name == ammo_name:
			GameState.player_inventory[i] = null
			return

# Generalized ammo-landing resolver — works for any stackable Item passed as ammo_item (only
# "Arrow" is spawned in-game today, but this makes no assumptions beyond "a stackable Item that
# should reappear as a floor pickup at its impact point"). Called from _ranged_attack_tile()
# (open-ground/wall shots, no enemy involved — always lands normally) and _finish_kill()
# (kill-shot 50% drop-from-corpse). Deliberately NOT called for a shot fired AT an enemy that
# doesn't kill it — hit or miss, the ammo stays embedded/lodged with the enemy, no pickup at all,
# so missed shots can't be walked up and re-collected for an effectively infinite ammo supply.
func resolve_ammo_landing(ammo_item: Item, impact_pos: Vector2i) -> void:
	if ammo_item == null or player._dungeon_floor == null:
		return
	match player._dungeon_floor.get_tile_type(impact_pos):
		DungeonData.TileType.WALL:
			return  # destroyed, no pickup
		DungeonData.TileType.CHASM:
			var dropped := Item.new()
			dropped.item_name = ammo_item.item_name
			dropped.item_type = ammo_item.item_type
			dropped.icon_path = ammo_item.icon_path
			dropped.description = ammo_item.description
			dropped.quantity = 1
			GameState.pending_chasm_items.append(dropped)
			GameState.game_log("[color=gray]The %s falls into the chasm...[/color]" % ammo_item.item_name)
		_:
			var landed := Item.new()
			landed.item_name = ammo_item.item_name
			landed.item_type = ammo_item.item_type
			landed.icon_path = ammo_item.icon_path
			landed.description = ammo_item.description
			landed.quantity = 1
			player._dungeon_floor.place_item_on_floor(impact_pos, landed)
