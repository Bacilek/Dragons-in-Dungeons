class_name AttunementRules
extends RefCounted

# Pure attunement-gating logic (Item.requires_attunement/is_attuned — see
# scripts/items/CLAUDE.md's "Attunement") extracted out of game_state.gd, same static-func-only
# pattern as WeaponTooltip/ArmorTooltip/ItemStackSplit. GameState keeps its original function
# names as thin delegators (attunable_items()/attuned_count()/can_attune()/_item_bonus_active())
# since scripts/ui/attunement_picker.gd already calls several of them directly.

const MAX_ATTUNED_ITEMS: int = 3

# Every item currently requiring attunement across quickbar + bag + every equipment slot — whether
# or not it's actually attuned yet (the attunement picker needs to list both states).
static func attunable_items(quickbar: Array, inventory: Array, equipment: Dictionary) -> Array[Item]:
	var out: Array[Item] = []
	for it: Variant in quickbar:
		if it is Item and (it as Item).requires_attunement:
			out.append(it as Item)
	for it: Variant in inventory:
		if it is Item and (it as Item).requires_attunement:
			out.append(it as Item)
	for slot_name: String in equipment:
		var it: Item = equipment[slot_name] as Item
		if it != null and it.requires_attunement:
			out.append(it)
	return out

static func attuned_count(items: Array[Item]) -> int:
	var count: int = 0
	for it: Item in items:
		if it.is_attuned:
			count += 1
	return count

static func can_attune(item: Item, current_attuned_count: int) -> bool:
	return item != null and item.requires_attunement and not item.is_attuned \
		and current_attuned_count < MAX_ATTUNED_ITEMS

# A non-magic item (requires_attunement == false) always contributes its bonuses — unaffected by
# this system. A magic item only contributes once attuned.
static func item_bonus_active(item: Item) -> bool:
	return item != null and (not item.requires_attunement or item.is_attuned)
