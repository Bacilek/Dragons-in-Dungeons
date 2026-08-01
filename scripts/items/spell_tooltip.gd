class_name SpellTooltip
extends RefCounted

# Unified structured spell tooltip — mirrors WeaponTooltip.build()/ArmorTooltip.build()'s shape,
# see scripts/items/CLAUDE.md's "Unified weapon tooltip format". Every spell readout in the game
# (Spellbook overlay, cantrip/level-up pickers, ability-bar hover, Scroll of <Spell>, debug "Give
# Spell") goes through this one function so the format can never drift apart between call sites.
#
# [b]Name[/b]
# School, Level (Classes)
# Casting Time: Action/Free
# Range: N | Self
# Area: N-tile cone/sphere/cube          — only if the spell has an AoE shape
# Duration: Concentration, N turns | N turns   — omitted entirely for an instantaneous spell
# <functional description>
# Cantrip Upgrade                        — only if the spell scales with character level
#
# Every FIXED line (name/header/casting time/range/area/duration) is glued together with
# non-breaking spaces (U+00A0) so it can never word-wrap across two lines — only the final
# free-form `description` line (and its own natural length) is allowed to wrap. Callers that
# render this in a fixed-width box should size that box to fit via required_width() below rather
# than let a long fixed line silently get clipped — direct owner request.

const CLASS_DISPLAY_NAMES: Dictionary = {
	"WIZARD": "Wizard",
	"RANGER": "Ranger",
	"WARLOCK": "Warlock",
}

const _PADDING: float = 24.0
const _MIN_WIDTH: float = 140.0

static func _nobreak(s: String) -> String:
	return s.replace(" ", "\u00A0")

static func _level_label(level: int) -> String:
	if level == 0:
		return "Cantrip"
	return "%s Level" % SpellDb.ordinal(level)

static func _area_label(shape: String, shape_size: int) -> String:
	match shape:
		"sphere": return "%d-tile sphere" % shape_size
		"cone": return "%d-tile cone" % shape_size
		"cube": return "%d-tile cube" % shape_size
		_: return ""

static func _duration_label(spell: Spell) -> String:
	if spell.duration_turns <= 0:
		return ""
	if spell.is_concentration:
		return "Concentration, %d turns" % spell.duration_turns
	return "%d turns" % spell.duration_turns

## Plain (no BBCode) text of every FIXED line — name, header, casting time, range, area,
## duration — shared by build() (which BBCode-wraps + nobreak-glues each one) and required_width()
## (which measures each one to size the box that will hold them).
static func _fixed_lines(spell: Spell) -> Array[String]:
	var lines: Array[String] = []
	lines.append(spell.spell_name)

	var header: String = spell.school
	header += ", %s" % _level_label(spell.level)
	if not spell.class_list.is_empty():
		var names: Array[String] = []
		for c: String in spell.class_list:
			names.append(CLASS_DISPLAY_NAMES.get(c, c))
		header += " (%s)" % ", ".join(names)
	lines.append(header)

	lines.append("Casting Time: %s" % spell.casting_time)

	if spell.target_kind == Spell.TargetKind.SELF and spell.range_tiles == 0:
		lines.append("Range: Self")
	else:
		lines.append("Range: %d" % spell.range_tiles)

	var area: String = _area_label(spell.shape, spell.shape_size)
	if area != "":
		lines.append("Area: %s" % area)

	var duration: String = _duration_label(spell)
	if duration != "":
		lines.append("Duration: %s" % duration)

	return lines

## interactive = true wraps the "Cantrip Upgrade" keyword in a [url=keyword:...] link (only
## meaningful inside a RichTextLabel already wired to a glossary-popup meta_hover handler — see
## hud.gd/inventory_overlay.gd's qbar tooltip). Callers without that wiring (spellbook_overlay,
## cantrip_select, spell_learn_picker, debug_panel) pass interactive = false for a plain colored
## (non-clickable) keyword line instead.
static func build(spell: Spell, interactive: bool = true) -> String:
	if spell == null:
		return ""
	var fixed: Array[String] = _fixed_lines(spell)
	var lines: Array[String] = []
	lines.append("[b]%s[/b]" % _nobreak(fixed[0]))
	lines.append("[color=gray]%s[/color]" % _nobreak(fixed[1]))
	for i: int in range(2, fixed.size()):
		lines.append(_nobreak(fixed[i]))

	if not spell.description.is_empty():
		lines.append("[color=#c8c8cc]%s[/color]" % WeaponTooltip.linkify_conditions(spell.description, interactive))

	if spell.cantrip_tier_scaling or spell.multi_beam_scaling:
		var kw_id: String = "cantrip_upgrade_beams" if spell.multi_beam_scaling else "cantrip_upgrade_dice"
		if interactive:
			lines.append("[color=#c9a227][url=keyword:%s]Cantrip\u00A0Upgrade[/url][/color]" % kw_id)
		else:
			lines.append("[color=#c9a227]Cantrip\u00A0Upgrade[/color]")

	return "\n".join(lines)

## Plain-text variant (no BBCode at all) for native Control.tooltip_text consumers, which don't
## render BBCode — e.g. debug_panel.gd's "Give Spell..." row hover.
static func build_plain(spell: Spell) -> String:
	var bbcode: String = build(spell, false)
	var reg := RegEx.new()
	reg.compile("\\[/?[^\\]]*\\]")
	return reg.sub(bbcode, "", true).replace("\u00A0", " ")

## Pixel width needed to fit the longest FIXED line (name/header/casting-time/range/area/duration)
## without wrapping, at the given font_size — a character-length/font-measurement heuristic (same
## precedent as inspect_panel.gd's own "estimated line count" sizing). Callers should size their
## tooltip box to at least this width. Not used for `description`, which is expected to wrap.
static func required_width(spell: Spell, font_size: int = 14) -> float:
	if spell == null:
		return _MIN_WIDTH
	var font: Font = ThemeDB.fallback_font
	var widest: float = 0.0
	for line: String in _fixed_lines(spell):
		var w: float = font.get_string_size(line, HORIZONTAL_ALIGNMENT_LEFT, -1, font_size).x
		widest = maxf(widest, w)
	return maxf(_MIN_WIDTH, widest + _PADDING)
