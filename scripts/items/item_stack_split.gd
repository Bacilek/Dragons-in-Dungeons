class_name ItemStackSplit
extends RefCounted

# Pure stack-splitting logic for durability-tracked weapons (Handaxe/Dagger/Spear — see
# scripts/items/CLAUDE.md's "Mixed-durability stacking") — extracted out of game_state.gd, same
# static-func-only pattern as WeaponTooltip/ArmorTooltip. Operates purely on the Item passed in, no
# GameState state read or written, so this was a clean lift-and-shift.
# GameState._should_split_for_equip()/_split_one_unit() are now 1-line delegators — kept on
# GameState (not renamed to a method call like ItemStackSplit.split_one_unit(item)) because
# scripts/entities/player_throw_tool.gd already calls GameState._split_one_unit(weapon) directly.

# A stacked thrown weapon (quantity > 1, units may carry different durability — see
# GameState.add_item()) only ever equips a single unit: split one off instead of moving the whole
# stack into a slot, so the rest keep sitting in the bag with their own durability untouched.
# Shared by GameState.equip(), move_item()'s drag-to-equipment-slot path, and
# PlayerThrowTool._throw_weapon().
static func should_split_for_equip(item: Item) -> bool:
	return item.quantity > 1 and item.item_type == Item.Type.WEAPON and item.uses_max > 0

# Splits the most-damaged unit (lowest uses_remaining — the one "on top" of the stack) off into
# its own single-quantity Item, leaving the rest of the stack behind with their own durability.
static func split_one_unit(item: Item) -> Item:
	var unit: Item = item.duplicate()
	unit.quantity = 1
	unit.stack_uses = []
	if item.uses_max > 0:
		var stack: Array = item.get_stack_uses()
		stack.sort()
		var taken: int = int(stack[0])
		stack.remove_at(0)
		unit.uses_remaining = taken
		var remaining: Array[int] = []
		for v: Variant in stack:
			remaining.append(int(v))
		if remaining.size() > 1:
			item.stack_uses = remaining
		else:
			var empty: Array[int] = []
			item.stack_uses = empty
		if not remaining.is_empty():
			item.uses_remaining = remaining[0]
	item.quantity -= 1
	return unit
