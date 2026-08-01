class_name RaceTooltip
extends RefCounted

# Unified structured race tooltip — mirrors SpellTooltip.build()'s shape (scripts/items/
# spell_tooltip.gd). Consumed by hud.gd's always-on "race_bonus" status-tray icon hover (the one
# place a player checks "what do my racial traits do").
#
# [b]Race Name[/b]
# Creature Type: X
# Size: X
# Speed: X
# Darkvision: None/Normal/Superior
# <trait keywords, one per line — hover for a description popup, no Ctrl needed>
#
# A trait with sub-options (currently only Aasimar's Celestial Revelation) shows its own
# description plus each sub-option as a further hoverable keyword INSIDE that popup — a real
# two-level nested hover, not a flat list. See hud.gd's "Quickbar hover tooltip" section for the
# popup-chain mechanism this depends on.
#
# Every FIXED line (name/header lines) is glued with a non-breaking space (U+00A0) so it never
# word-wraps, same rule as SpellTooltip — see that file's own header comment for why.

const NBSP: String = " "

static func _nobreak(s: String) -> String:
	return s.replace(" ", NBSP)

## Top-level tooltip: header + fixed lines + one hoverable [url=race_trait:id] link per trait.
static func build(stats: Stats) -> String:
	if stats == null:
		return ""
	var info: Dictionary = RaceDb.build(stats)
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _nobreak(RaceDb.race_display_name(stats)))
	lines.append(_nobreak("Creature Type: %s" % info["creature_type"]))
	lines.append(_nobreak("Size: %s" % info["size"]))
	lines.append(_nobreak("Speed: %s" % info["speed"]))
	lines.append(_nobreak("Darkvision: %s" % info["darkvision"]))
	lines.append("")
	for t: Dictionary in info["traits"]:
		lines.append("[color=#e8d27a][url=race_trait:%s]%s[/url][/color]" % [t["id"], t["name"]])
	return "\n".join(lines)

## Level-1 popup body for a single trait: description + (if it has sub-options) each sub-option
## as its own further hoverable [url=race_sub:trait_id:sub_id] link.
static func build_trait_detail(trait_dict: Dictionary) -> String:
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % trait_dict["name"])
	lines.append(WeaponTooltip.linkify_conditions(trait_dict["desc"]))
	var subs: Array = trait_dict.get("subs", [])
	if not subs.is_empty():
		for sub: Dictionary in subs:
			lines.append("[color=#c9a227][url=race_sub:%s:%s]%s[/url][/color]" % [trait_dict["id"], sub["id"], sub["name"]])
	return "\n".join(lines)

## Level-2 popup body for a sub-option (e.g. Heavenly Wings under Celestial Revelation) — plain,
## no further nesting.
static func build_sub_detail(sub_dict: Dictionary) -> String:
	return "[b]%s[/b]\n%s" % [sub_dict["name"], WeaponTooltip.linkify_conditions(sub_dict["desc"], false)]

## Looks up a trait dict by id from a freshly-built RaceDb.build(stats) result.
static func find_trait(stats: Stats, trait_id: String) -> Dictionary:
	var info: Dictionary = RaceDb.build(stats)
	for t: Dictionary in info["traits"]:
		if t["id"] == trait_id:
			return t
	return {}

static func find_sub(stats: Stats, trait_id: String, sub_id: String) -> Dictionary:
	var t: Dictionary = find_trait(stats, trait_id)
	for sub: Dictionary in t.get("subs", []):
		if sub["id"] == sub_id:
			return sub
	return {}
