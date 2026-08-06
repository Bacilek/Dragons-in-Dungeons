class_name EnemyInspect
extends RefCounted

# Static-func-only helper for the Inspect Panel's enemy view (scripts/ui/inspect_panel.gd) —
# builds the status-icon entry list + hover copy for whatever conditions/debuffs are currently
# active on an Enemy, and the auto-generated "Medium Undead, CR 1/4" flavor line. Mirrors
# status_tooltips.gd's "UI copy, not game data" pattern, generalized to take an Enemy param since
# StatusTooltips itself is hardwired to GameState.player_stats. See scripts/entities/CLAUDE.md's
# "Conditions" section for what each status actually does mechanically.

const TITLES: Dictionary = {
	"shocked": "Shocked",
	"jolted": "Jolted (Witch Bolt)",
	"poisoned_condition": "Poisoned",
	"outlined": "Outlined (Faerie Fire)",
	"prone": "Prone",
	"incapacitated": "Incapacitated",
	"frightened": "Frightened",
	"paralyzed": "Paralyzed",
	"blinded": "Blinded",
	"restrained": "Restrained (Ensnaring Strike)",
}

const COLORS: Dictionary = {
	"shocked": Color.CYAN,
	"jolted": Color.CYAN,
	"poisoned_condition": Color(0.4, 0.9, 0.3),
	"outlined": Color.MAGENTA,
	"prone": Color(0.8, 0.65, 0.4),
	"incapacitated": Color(0.6, 0.6, 0.6),
	"frightened": Color(0.6, 0.3, 0.8),
	"paralyzed": Color(0.5, 0.5, 0.9),
	"blinded": Color(0.35, 0.35, 0.35),
	"restrained": Color(0.45, 0.65, 0.25),
}

static func status_entries(enemy: Enemy) -> Array[Dictionary]:
	var entries: Array[Dictionary] = []
	if enemy.shocked_no_oa:
		entries.append(_entry("shocked"))
	if GameState.player_stats.witch_bolt_turns > 0 and GameState.player_stats.witch_bolt_target == enemy:
		entries.append(_entry("jolted"))
	if enemy.poisoned_condition_turns > 0:
		entries.append(_entry("poisoned_condition"))
	if enemy.faerie_fire_turns > 0:
		entries.append(_entry("outlined"))
	if enemy.prone:
		entries.append(_entry("prone"))
	if enemy.incapacitated_turns > 0:
		entries.append(_entry("incapacitated"))
	if enemy.frightened_turns > 0:
		entries.append(_entry("frightened"))
	if enemy.paralyzed_turns > 0:
		entries.append(_entry("paralyzed"))
	if GameState.is_blinded(enemy.grid_pos):
		entries.append(_entry("blinded"))
	if enemy.restrained_turns > 0:
		entries.append(_entry("restrained"))
	return entries

static func _entry(id: String) -> Dictionary:
	return {"id": id, "icon_path": "", "fallback_color": COLORS.get(id, Color.WHITE)}

static func get_text(id: String) -> String:
	match id:
		"shocked":
			return "Can't provoke an Opportunity Attack on its next exposed move (Shocking Grasp)."
		"jolted":
			return "Takes an automatic Lightning hit at the end of your turns (Witch Bolt)."
		"poisoned_condition":
			return "Disadvantage on its own attack rolls and ability checks."
		"outlined":
			return "Every attack roll against it has Advantage if the attacker can see it. Can't be Invisible."
		"prone":
			return "Melee attacks against it have Advantage, ranged attacks have Disadvantage. Must stand up (spending movement) before it can act normally again."
		"incapacitated":
			return "Can't take actions this turn. Every attack against it counts as a Surprise Attack."
		"frightened":
			return "Disadvantage on its own attack rolls."
		"paralyzed":
			return "Can't act. Auto-fails STR/DEX checks. Every attack against it has Advantage, and a hit from within 1 tile is an automatic critical."
		"blinded":
			return "Standing in a Heavily Obscured zone — Advantage on attacks against it, Disadvantage on its own attacks."
		"restrained":
			return "Speed 0. Advantage on attacks against it (any kind), Disadvantage on its own attack rolls. Takes 1d6 Piercing at the start of its turns and repeats a STR save to break free."
		_:
			return ""

static func build_bbcode(id: String) -> String:
	return "[b]%s[/b]\n%s" % [TITLES.get(id, id), get_text(id)]

# D&D fractional CR display for the common sub-1 values; anything else prints as-is.
static func cr_label(cr: float) -> String:
	if cr <= 0.0:
		return "0"
	if cr >= 1.0:
		return str(int(cr)) if is_equal_approx(cr, floor(cr)) else str(cr)
	if is_equal_approx(cr, 0.125):
		return "1/8"
	if is_equal_approx(cr, 0.25):
		return "1/4"
	if is_equal_approx(cr, 0.5):
		return "1/2"
	return str(cr)

static func description_line(enemy: Enemy) -> String:
	return "%s %s, CR %s" % [enemy.creature_size, enemy.creature_type, cr_label(enemy.cr)]
