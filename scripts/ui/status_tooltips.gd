class_name StatusTooltips
extends RefCounted

# Static description strings for the status/passive icon tray (status_tray.gd). Mirrors
# tooltip_formatters.gd's "static-func helper, UI copy not game data" pattern.

const TITLES: Dictionary = {
	"poisoned": "Poisoned",
	"burning": "Burning",
	"bleeding": "Bleeding",
	"slowed": "Slowed",
	"raging": "Raging",
	"temp_hp": "Temporary HP",
	"unarmored_defense": "Unarmored Defense",
	"tactician": "Tactician",
	"psycho_adv": "Psycho",
}

static func get_text(id: String) -> String:
	match id:
		"poisoned":
			return "Taking 1 + (turns remaining / 3) damage per turn."
		"burning":
			return "Taking damage equal to your character level per turn."
		"bleeding":
			return "Taking 1 damage per turn."
		"slowed":
			return "Your next move costs 2 turns instead of 1."
		"raging":
			return "50% reduced Slashing/Piercing/Bludgeoning damage taken. Refreshed by attacking or being attacked."
		"temp_hp":
			return "%d temporary HP — absorbed before regular HP." % GameState.player_stats.temp_hp
		"unarmored_defense":
			var s: Stats = GameState.player_stats
			var stat_name: String = "CON" if s.character_class == Stats.CharacterClass.BARBARIAN else "WIS"
			var stat_mod: int = s.con_modifier() if s.character_class == Stats.CharacterClass.BARBARIAN else s.wis_modifier()
			return "AC = 10 + DEX (%+d) + %s (%+d) = %d, while unarmored." % [s.dex_modifier(), stat_name, stat_mod, s.armor_class]
		"tactician":
			return "Battlefield Expert: your next attack this turn is made with Advantage."
		"psycho_adv":
			return "Psycho: your next attack this turn is made with Advantage."
		_:
			return ""

static func build_bbcode(id: String) -> String:
	var title: String = TITLES.get(id, id)
	var text: String = get_text(id)
	return "[b]%s[/b]\n%s" % [title, text]
