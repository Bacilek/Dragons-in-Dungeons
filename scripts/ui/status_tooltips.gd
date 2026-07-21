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
	"torch": "Torch Lit",
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
		"concentration":
			return "You can only concentrate on one spell at a time — casting another concentration spell ends this one immediately, and taking damage forces a CON check to keep it up."
		"torch":
			var t: Item = GameState.lit_torch_item()
			if t == null:
				return "Lit."
			var in_main_hand: bool = GameState.equipment.get("melee") as Item == t
			var fire_note: String = " Attacks also deal +1d4 Fire damage." if in_main_hand else ""
			return "Lit — burns out in %d more turns.\n+1 FOV.%s" % [t.torch_turns_remaining, fire_note]
		_:
			return ""

static func build_bbcode(id: String) -> String:
	if id == "concentration":
		var spell_id: String = GameState.player_stats.concentration_spell_id
		var sp: Spell = SpellDb.get_spell(spell_id) if spell_id != "" else null
		var spell_name: String = sp.spell_name if sp != null else "a spell"
		return "[b]Concentrating: %s[/b]\n%s" % [spell_name, get_text(id)]
	var title: String = TITLES.get(id, id)
	var text: String = get_text(id)
	return "[b]%s[/b]\n%s" % [title, text]
