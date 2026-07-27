class_name ArmorTooltip
extends RefCounted

# Shared armor-tooltip body builder — mirrors WeaponTooltip.build()'s "single shared function"
# convention so hud.gd's quickbar hover and inventory_overlay.gd's bag/equipment hover can never
# drift out of sync. Covers body armor (Item.Type.ARMOR, armor_category != NONE) and the Shield
# (Item.is_shield) — the only two ARMOR-type items with their own stat block worth a dedicated
# format. See scripts/items/CLAUDE.md's "Body armor" / "Shields" sections for the mechanics behind
# each line.
#
# Fixed line order: Name / Type (Light/Medium/Heavy Armor or Shield) / "AC: N" / optional
# "Disadvantage on Stealth" / "Don/Doff: N turn(s)". Description, Attunement, price, and the
# "Ctrl: inspect" hint are appended by the caller AFTER this, same split as WeaponTooltip.

static func is_armor_item(item: Item) -> bool:
	return item.item_type == Item.Type.ARMOR and (item.is_shield or item.armor_category != Item.ArmorCategory.NONE)

static func _category_name(item: Item) -> String:
	if item.is_shield:
		return "Shield"
	match item.armor_category:
		Item.ArmorCategory.LIGHT:
			return "Light Armor"
		Item.ArmorCategory.MEDIUM:
			return "Medium Armor"
		Item.ArmorCategory.HEAVY:
			return "Heavy Armor"
		_:
			return "Armor"

static func build(item: Item) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % item.item_name)
	lines.append(_category_name(item))

	if item.is_shield:
		lines.append("AC: +%d" % item.bonus_ac)
	else:
		var ac_line: String = "AC: %d" % item.base_ac
		match item.dex_cap:
			-1:
				ac_line += " + DEX"
			0:
				pass
			_:
				ac_line += " + DEX (max +%d)" % item.dex_cap
		lines.append(ac_line)

	if item.stealth_disadvantage:
		lines.append("[color=orange][url=keyword:stealth_disadv]Disadvantage on Stealth[/url][/color]")

	var change_turns: int = 1 if item.is_shield else GameState.ARMOR_CHANGE_TURNS.get(item.armor_category, 1)
	lines.append("[color=gray]Don/Doff: %d turn%s[/color]" % [change_turns, "" if change_turns == 1 else "s"])

	return "\n".join(lines)
