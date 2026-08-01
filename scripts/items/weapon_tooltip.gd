class_name WeaponTooltip
extends RefCounted

# Single shared builder for the weapon tooltip body — used identically by hud.gd's quickbar
# hover and inventory_overlay.gd's bag/equipment hover so the two can never drift out of sync
# again. See scripts/items/CLAUDE.md's "Unified weapon tooltip format" section for the full
# field-by-field spec this implements.
#
# Fixed line order: Name (Mastery) / Requirements / Damage + Type / Range (ranged only) /
# Properties (alphabetical, one per line). Description ("additional info"), Uses: X/Y, Attunement,
# gold price, and the "Ctrl: inspect" hint are all appended by the caller AFTER this — they're
# either generic across every item type (description, Attunement, Ctrl hint) or already
# per-caller-positioned (Uses:), so they stay outside this weapon-only builder.

# The single shared [url=keyword:X] glossary for hud.gd/inventory_overlay.gd's Ctrl-freeze popup
# (scripts/ui/CLAUDE.md's "Ctrl-freeze tooltip") — grown beyond weapon-only keywords to also cover
# general D&D condition/terrain terms (Heavily Obscured, Blinded, Frightened, Poisoned/Prone/
# Restrained/Incapacitated — see scripts/entities/CLAUDE.md's "Conditions" section) since this is
# the game's one glossary mechanism, not something weapon-specific.
const KEYWORD_GLOSSARY: Dictionary = {
	"heavy_str": "Heavy weapon.\nRequires STR 13+.\nAttacking without enough\nStrength imposes\nDisadvantage.",
	"heavy_dex": "Heavy weapon.\nRequires DEX 13+.\nAttacking without enough\nDexterity imposes\nDisadvantage.",
	"two_handed": "Two-handed weapon.\nOccupies Main Hand.\nOff-hand cannot be used\nwhile equipped.",
	"cleave": "Mastery: Cleave.\nIf 2+ enemies are within\nmelee reach, this attack\nalso strikes the one closest\nto your primary target —\nwith its own attack roll\nand damage roll.",
	"simple": "Simple weapon.\nEasy to use — most\ncharacters are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"martial": "Martial weapon.\nRequires training — only\nsome classes are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"vex": "Mastery: Vex.\nOn a hit, gain Advantage\non your next attack this\nround against the same\ntarget (any attack type).",
	"push": "Mastery: Push.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ DEX) or is shoved 1 tile\ndirectly away from you.\nHitting a wall deals 1d4\nBludgeoning instead of\nmoving; falling into a\nchasm removes it (loot,\nif any, appears a floor\ndown).",
	"finesse": "Finesse weapon.\nUse either STR or DEX\n(whichever is higher) for\nboth the attack roll and\nthe damage roll.",
	"light": "Light weapon.\nPair another Light weapon\nin the Off-hand to attack\nwith both. The Off-hand\nswing skips your ability\nmodifier on damage, unless\nit's negative.",
	"graze": "Mastery: Graze.\nOn a miss, still deal\ndamage equal to the\nability modifier used\nfor the attack (min 0).",
	"reach": "Reach weapon.\n+1 tile melee range —\ncan attack (and chase-\nattack) from 2 tiles away\ninstead of 1.",
	"topple": "Mastery: Topple.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ STR) or is knocked Prone\n(see the Prone keyword).",
	"versatile": "Versatile weapon.\nClick the Main Hand slot\nto switch grip: one-handed\nuses the die shown, two-\nhanded uses the die listed\nhere instead.",
	"thrown": "Thrown weapon.\nRight-click to prime a\nthrow, then left-click a\ntarget tile — uses your\nmelee attack modifier.\nNormal range is the weapon's\nown range; beyond it (still\nwithin the long range shown\nin its tooltip) rolls with\nDisadvantage. Has limited\nuses before it breaks.",
	"sap": "Mastery: Sap.\nOn a hit, the target has\nDisadvantage on its very\nnext attack, next turn.",
	"nick": "Mastery: Nick.\nWhile dual-wielding two\nLight weapons, make one\nfurther attack this turn —\nsame rules as the Off-hand\nswing (max 3 attacks total).",
	"slow": "Mastery: Slow.\nOn a hit, the target is\nSlowed — its next move\ncosts an extra turn, same\nas stepping into mud/water.",
	"ammo": "Ammo.\nThis weapon consumes one\nunit of the named ammo\nitem per shot.",
	"heavily_obscured": "Heavily Obscured terrain.\nAnyone standing in it —\nplayer or enemy — is\nBlinded (see the Blinded\nkeyword). Fog Cloud is the\nonly source today.",
	"blinded": "Blinded (condition).\nCan't see — automatically\nfails checks requiring\nsight. Attacks against you\nhave Advantage, your own\nattacks have Disadvantage.\nVision collapses to 1 tile,\neven with darkvision.",
	"frightened": "Frightened (condition).\nDisadvantage on checks and\nattacks while the source of\nfear is in sight. Can't\nwillingly move closer to it\n(forced movement is fine).\nRepeats a WIS save each\nturn to end early.",
	"poisoned_condition": "Poisoned (condition).\nDisadvantage on attack\nrolls and ability checks.\nSeparate from the green\nPoisoned damage-over-time\nstatus.",
	"prone": "Prone (condition).\nMelee attacks against you\nhave Advantage, ranged have\nDisadvantage. Can't move\nuntil you stand up (costs\nthe turn).",
	"restrained": "Restrained (condition).\nSpeed 0. Attacks against\nyou have Advantage, your\nown attacks and DEX checks\nhave Disadvantage.",
	"incapacitated": "Incapacitated (condition).\nCan't take actions —\nmovement, attacks, ability/\nspell use all blocked.\nBreaks Concentration.",
	"stealth_disadv": "Stealth Disadvantage.\nWhile worn, adds a\nDisadvantage source to the\nStealth-vs-Passive-\nPerception check that\ndecides whether an enemy\nnotices you.",
}

# "" = unpriced (both gold_value and silver_value are 0) — caller should skip the price line
# entirely in that case. "Xg Ysp" / "Xg" / "Ysp" otherwise (see Item.silver_value).
static func format_price(item: Item) -> String:
	if item.gold_value <= 0 and item.silver_value <= 0:
		return ""
	if item.gold_value > 0 and item.silver_value > 0:
		return "%dg %dsp" % [item.gold_value, item.silver_value]
	if item.gold_value > 0:
		return "%dg" % item.gold_value
	return "%dsp" % item.silver_value

static func is_category_proficient(category: String, stats: Stats) -> bool:
	match category:
		"Simple":  return stats.proficient_simple_weapons
		"Martial": return stats.proficient_martial_weapons
		_: return true

# Returns the full weapon-specific tooltip body (header through Properties) as BBCode.
# Caller is expected to be the one appending description/Uses/Attunement/price/Ctrl-hint after.
static func build(item: Item) -> String:
	var stats: Stats = GameState.player_stats
	var lines: Array[String] = []

	# Name (Mastery) — name always bold+default color; only the mastery text itself is
	# green/red (know it / don't). No mastery at all (e.g. Torch) → bare name, no parens.
	var header: String = "[b]%s[/b]" % item.item_name
	if not item.weapon_mastery.is_empty():
		var known: bool = stats.knows_mastery(item.weapon_mastery)
		header += " [color=%s][url=keyword:%s](%s)[/url][/color]" % [
			"green" if known else "red", item.weapon_mastery.to_lower(), item.weapon_mastery]
	lines.append(header)

	# Requirements — everything the character might not meet, red if unmet, white if met.
	# Comma-joined onto one line (unlike Properties, which are one-per-line). Heavy shows as the
	# bare word "Heavy" here (not "STR 13+"/"DEX 13+") — the exact stat/threshold only shows on
	# hover, via the glossary popup.
	var reqs: Array[String] = []
	if not item.weapon_category.is_empty():
		var cat_ok: bool = is_category_proficient(item.weapon_category, stats)
		reqs.append("[color=%s][url=keyword:%s]%s[/url][/color]" % [
			"white" if cat_ok else "red", item.weapon_category.to_lower(), item.weapon_category])
	if item.is_heavy:
		var score: int = stats.dexterity if item.is_ranged else stats.strength
		var heavy_key: String = "heavy_dex" if item.is_ranged else "heavy_str"
		reqs.append("[color=%s][url=keyword:%s]Heavy[/url][/color]" % [
			"white" if score >= 13 else "red", heavy_key])
	if not reqs.is_empty():
		lines.append(", ".join(reqs))

	# Damage + type. Multiple damage instances (none exist on any weapon today) would be
	# joined with " + " here if a future weapon ever needs it.
	var dmg_parts: Array[String] = []
	if item.damage_die_max > 0:
		dmg_parts.append("1d%d" % item.damage_die_max)
	if item.bonus_damage > 0:
		dmg_parts.append("+%d" % item.bonus_damage)
	if not dmg_parts.is_empty():
		var dmg_line: String = " ".join(dmg_parts)
		if not item.damage_type.is_empty():
			dmg_line += " [color=gray]%s[/color]" % item.damage_type
		lines.append(dmg_line)

	# Range — ranged weapons only, "range: normal/long".
	if item.is_ranged:
		var long_r: int = item.long_range if item.long_range > 0 else item.range
		lines.append("range: %d/%d" % [item.range, long_r])

	# Properties — alphabetical, one per line. Ammo(<name>) and Versatile(1dN) are the two
	# properties with a value baked into the tag itself. Heavy lives in Requirements above, not
	# here.
	var props: Array[Dictionary] = []
	if not item.ammo_item_name.is_empty():
		props.append({"key": "Ammo", "text": "[url=keyword:ammo]Ammo(%s)[/url]" % item.ammo_item_name})
	if item.is_finesse:
		props.append({"key": "Finesse", "text": "[url=keyword:finesse]Finesse[/url]"})
	if item.is_light:
		props.append({"key": "Light", "text": "[url=keyword:light]Light[/url]"})
	if item.is_reach:
		props.append({"key": "Reach", "text": "[url=keyword:reach]Reach[/url]"})
	if item.is_thrown:
		props.append({"key": "Thrown", "text": "[url=keyword:thrown]Thrown[/url]"})
	if item.is_two_handed:
		props.append({"key": "Two-handed", "text": "[url=keyword:two_handed]Two-handed[/url]"})
	if item.is_versatile:
		props.append({"key": "Versatile", "text": "[url=keyword:versatile]Versatile(1d%d)[/url]" % item.versatile_die_max})
	props.sort_custom(func(a: Dictionary, b: Dictionary) -> bool: return a["key"] < b["key"])
	for p: Dictionary in props:
		lines.append(p["text"])

	return "\n".join(lines)
