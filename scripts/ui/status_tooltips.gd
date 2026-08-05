class_name StatusTooltips
extends RefCounted

# Static description strings for the status/passive icon tray (status_tray.gd). Mirrors
# tooltip_formatters.gd's "static-func helper, UI copy not game data" pattern.

const TITLES: Dictionary = {
	"poisoned": "Poisoned",
	"burning": "Burning",
	"bleeding": "Bleeding",
	"slowed": "Slowed",
	"difficult_terrain": "Difficult Terrain",
	"raging": "Raging",
	"temp_hp": "Temporary HP",
	"unarmored_defense": "Unarmored Defense",
	"tactician": "Tactician",
	"psycho_adv": "Psycho",
	"torch": "Torch Lit",
	"longstrider": "Longstrider",
	"faerie_fire_outlined": "Outlined (Faerie Fire)",
	"poisoned_condition": "Poisoned",
	"prone": "Prone",
	"restrained": "Restrained",
	"incapacitated": "Incapacitated",
	"weapon_mastery": "Weapon Masteries",
	"blinded": "Blinded",
	"frightened": "Frightened",
	"risen_from_dead": "Risen from the Dead",
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
		"difficult_terrain":
			return "Standing in Mud/Water. Moving costs 2 turns instead of 1."
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
		"risen_from_dead":
			return "You just cheated death. Completely invulnerable to all damage until your next turn begins."
		"concentration":
			return "You can only concentrate on one spell at a time — casting another concentration spell ends this one immediately, and taking damage forces a CON check to keep it up."
		"torch":
			var t: Item = GameState.lit_torch_item()
			if t == null:
				return "Lit."
			var in_main_hand: bool = GameState.equipment.get("melee") as Item == t
			var fire_note: String = " Attacks also deal +1d4 Fire damage." if in_main_hand else ""
			return "Lit — burns out in %d more turns.\n+1 FOV.%s" % [t.torch_turns_remaining, fire_note]
		"longstrider":
			return "+1/3 movement speed — every 3rd real move doesn't cost a turn.\nFades in %d more turns." % GameState.player_stats.longstrider_turns
		"faerie_fire_outlined":
			return "You're outlined in dancing light — every attack roll against you has Advantage if the attacker can see you.\nFades in %d more turns." % GameState.player_stats.faerie_fire_outlined_turns
		"poisoned_condition":
			return "Disadvantage on attack rolls and ability checks. Separate from the green Poisoned damage-over-time status."
		"prone":
			return "Melee attacks against you have Advantage, ranged attacks against you have Disadvantage. Can't move — any direction key stands up instead, costing the turn."
		"restrained":
			return "Speed 0. Attacks against you have Advantage, your own attacks have Disadvantage, and you have Disadvantage on DEX checks. Attempt a STR check each turn (movement key) to break free."
		"incapacitated":
			return "Can't take actions — movement, attacks, and ability/spell use are all blocked. Breaks Concentration immediately."
		"weapon_mastery":
			var known: Array[String] = GameState.player_stats.known_weapon_masteries
			return "Currently known: %s" % ", ".join(known)
		"blinded":
			return "You're Heavily Obscured. Can't see past 1 tile (darkvision doesn't help). Attacks against you have Advantage, your own attacks have Disadvantage."
		"frightened":
			var src: Enemy = GameState.player_stats.frightened_source
			var src_name: String = src.display_name if src != null and is_instance_valid(src) else "the source"
			return "Disadvantage on attacks and checks while %s is in sight. Can't willingly move closer to it. Repeats a WIS save each turn to end early." % src_name
		_:
			return ""

# Race portrait — same art race_select.gd's tile grid shows (icons/races/<id>/portrait.png,
# id = the lowercase RaceDb.RACE_NAMES display name, e.g. "Dragonborn" -> "dragonborn") — reused
# directly for the always-first "race_bonus" status-tray entry so the HUD buff icon and the
# onboarding tile show the identical portrait, not two separate art assets to keep in sync.
# The structured hover text itself now comes from RaceTooltip.build() (scripts/entities/
# race_tooltip.gd) — hud.gd's "race_bonus" case intercepts before ever calling get_text()/
# build_bbcode() below, so race_display_name()/race_bonus_text() were removed as dead code; use
# RaceDb.race_display_name(stats) (scripts/entities/race_db.gd) instead.
static func race_portrait_icon_path(stats: Stats) -> String:
	var id: String = RaceDb.RACE_NAMES.get(stats.character_race, "").to_lower()
	return "res://icons/races/%s/portrait.png" % id if id != "" else ""

static func build_bbcode(id: String) -> String:
	if id == "concentration":
		var spell_id: String = GameState.player_stats.concentration_spell_id
		var sp: Spell = SpellDb.get_spell(spell_id) if spell_id != "" else null
		var spell_name: String = sp.spell_name if sp != null else "a spell"
		var turns_left: int = GameState.player_stats.concentration_turns_remaining()
		return "[b]Concentrating: %s[/b]\n%s\n%d turns remaining (if concentration holds)." % [spell_name, get_text(id), turns_left]
	var title: String = TITLES.get(id, id)
	var text: String = get_text(id)
	return "[b]%s[/b]\n%s" % [title, text]
