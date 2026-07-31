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
	"poisoned_condition": "Poisoned",
	"prone": "Prone",
	"restrained": "Restrained",
	"incapacitated": "Incapacitated",
	"weapon_mastery": "Weapon Masteries",
	"blinded": "Blinded",
	"frightened": "Frightened",
	"race_bonus": "Race Bonus",
}

# Race display name + ability-score-proficiency/subrace/ancestry naming for the "race_bonus"
# status-tray entry below — small local const tables mirroring character_summary.gd's own
# RACE_NAMES/ELF_SUBRACES/DRAGONBORN_ANCESTRIES/ABILITY_SCORE_NAMES (kept separate rather than
# centralized, same "UI copy, not shared game data" precedent as everything else in this file).
const RACE_NAMES: Dictionary = {
	Stats.CharacterRace.ORC: "Orc",
	Stats.CharacterRace.HUMAN: "Human",
	Stats.CharacterRace.HALFLING: "Halfling",
	Stats.CharacterRace.DWARF: "Dwarf",
	Stats.CharacterRace.ELF: "Elf",
	Stats.CharacterRace.DRAGONBORN: "Dragonborn",
	Stats.CharacterRace.TIEFLING: "Tiefling",
	Stats.CharacterRace.AASIMAR: "Aasimar",
	Stats.CharacterRace.GNOME: "Gnome",
	Stats.CharacterRace.GOLIATH: "Goliath",
}
const ABILITY_SCORE_NAMES: Array[String] = ["STR", "DEX", "CON", "INT", "WIS", "CHA"]
const ELF_SUBRACES: Array[String] = ["Drow", "High Elf", "Wood Elf"]
const DRAGONBORN_ANCESTRIES: Array[String] = [
	"Black", "Blue", "Brass", "Bronze", "Copper", "Gold", "Green", "Red", "Silver", "White",
]
const TIEFLING_LEGACIES: Array[String] = ["Abyssal", "Chthonic", "Infernal"]
const GNOME_LINEAGES: Array[String] = ["Forest", "Rock"]
const GIANT_ANCESTRIES: Array[String] = ["Cloud", "Fire", "Frost", "Hill", "Stone", "Storm"]

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
		"race_bonus":
			return race_bonus_text(GameState.player_stats)
		_:
			return ""

# Race display name (e.g. "High Elf", "Red Dragonborn") — mirrors
# character_summary.gd's own _race_display_name(), duplicated locally per this file's
# "static-func helper, UI copy not game data" convention (see file header).
static func race_display_name(stats: Stats) -> String:
	var base_name: String = RACE_NAMES.get(stats.character_race, "")
	match stats.character_race:
		Stats.CharacterRace.ELF:
			var idx: int = stats.race_variant
			if idx >= 0 and idx < ELF_SUBRACES.size():
				return "%s (%s)" % [base_name, ELF_SUBRACES[idx]]
		Stats.CharacterRace.DRAGONBORN:
			var idx2: int = stats.race_variant
			if idx2 >= 0 and idx2 < DRAGONBORN_ANCESTRIES.size():
				return "%s %s" % [DRAGONBORN_ANCESTRIES[idx2], base_name]
		Stats.CharacterRace.TIEFLING:
			var idx3: int = stats.race_variant
			if idx3 >= 0 and idx3 < TIEFLING_LEGACIES.size():
				return "%s (%s)" % [base_name, TIEFLING_LEGACIES[idx3]]
		Stats.CharacterRace.GNOME:
			var idx4: int = stats.race_variant
			if idx4 >= 0 and idx4 < GNOME_LINEAGES.size():
				return "%s %s" % [GNOME_LINEAGES[idx4], base_name]
		Stats.CharacterRace.GOLIATH:
			var idx5: int = stats.race_variant
			if idx5 >= 0 and idx5 < GIANT_ANCESTRIES.size():
				return "%s (%s Giant)" % [base_name, GIANT_ANCESTRIES[idx5]]
	return base_name

# Full plain-English rundown of every trait the current race grants — the "race_bonus"
# status-tray entry's hover text, always showing the FULL kit at a glance (not just whichever
# traits happen to be mechanically active right now, unlike every other tray entry).
static func race_bonus_text(stats: Stats) -> String:
	var darkvision: String = "No darkvision." if stats.darkvision_bonus <= 0 else (
		"Superior darkvision." if stats.darkvision_bonus >= 2 else "Darkvision.")
	match stats.character_race:
		Stats.CharacterRace.ORC:
			return "Relentless Endurance: when a hit would drop you to 0 HP, drop to 1 HP instead (once per long rest).\nAdrenaline Rush: activate to gain temp HP equal to proficiency bonus and make your next move free (proficiency-bonus uses, refills on short AND long rest).\n%s" % darkvision
		Stats.CharacterRace.HUMAN:
			var abil: String = ABILITY_SCORE_NAMES[stats.race_prof_ability] if stats.race_prof_ability >= 0 and stats.race_prof_ability < ABILITY_SCORE_NAMES.size() else "?"
			return "Heroic Inspiration: activate to guarantee your next roll (attack, check, or save) critically succeeds (once per long rest).\nSkillful: bonus %s check proficiency.\nVersatile: gain an Origin feat (not yet implemented).\n%s" % [abil, darkvision]
		Stats.CharacterRace.HALFLING:
			return "Small, Speed 1.\nLuck: a natural 1 on any d20 roll is automatically rerolled (must use the new result).\nBrave: Advantage on saves to avoid or end the Frightened condition.\nHalfling Nimbleness: can move through the space of a larger creature (not yet implemented).\nNo darkvision."
		Stats.CharacterRace.DWARF:
			return "+1 max HP every level (including level 1).\nDwarven Resilience: resistance to Poison damage.\nStonecunning: activate to sense living creatures within 6 tiles standing on your same terrain, through walls/darkness (proficiency-bonus uses per long rest).\n%s" % darkvision
		Stats.CharacterRace.ELF:
			var lineage: String = ""
			match stats.race_variant:
				Stats.ElfSubrace.DROW:
					lineage = "Elven Lineage (Drow): Faerie Fire at level 3, Darkness at level 5 — each free once per long rest."
				Stats.ElfSubrace.HIGH_ELF:
					lineage = "Elven Lineage (High Elf): a free long-rest cantrip swap, Detect Magic at level 3, Misty Step at level 5 — each free once per long rest."
				Stats.ElfSubrace.WOOD_ELF:
					lineage = "Elven Lineage (Wood Elf): 35 ft speed (an extra free move roughly every 6th step), Longstrider at level 3, Pass Without Trace at level 5 — each free once per long rest."
			return "Keen Senses: WIS check proficiency.\nFey Ancestry: Advantage on checks to avoid/end Charmed (no Charmed condition exists yet).\nTrance: shorter long rests.\n%s\n%s" % [lineage, darkvision]
		Stats.CharacterRace.DRAGONBORN:
			var dmg_type: String = Stats.DRAGONBORN_DAMAGE_TYPE[clampi(stats.race_variant, 0, Stats.DRAGONBORN_DAMAGE_TYPE.size() - 1)]
			return "%s ancestry: resistance to %s damage, plus a matching Breath Weapon (Cone or Line AoE, %s damage).\nDraconic Flight at level 5 (once per long rest): cross chasms, immune to standing fire damage, no grass trample/traps.\n%s" % [
				DRAGONBORN_ANCESTRIES[clampi(stats.race_variant, 0, DRAGONBORN_ANCESTRIES.size() - 1)], dmg_type, dmg_type, darkvision]
		Stats.CharacterRace.TIEFLING:
			var legacy_dmg: String = Stats.TIEFLING_LEGACY_RESIST[clampi(stats.race_variant, 0, Stats.TIEFLING_LEGACY_RESIST.size() - 1)]
			var legacy_name: String = TIEFLING_LEGACIES[clampi(stats.race_variant, 0, TIEFLING_LEGACIES.size() - 1)]
			var legacy_spells: String = ""
			match stats.race_variant:
				Stats.TieflingLegacy.ABYSSAL:
					legacy_spells = "Poison Spray at level 1, Ray of Sickness at level 3, Hold Person at level 5."
				Stats.TieflingLegacy.CHTHONIC:
					legacy_spells = "Chill Touch at level 1, False Life at level 3, Ray of Enfeeblement at level 5."
				Stats.TieflingLegacy.INFERNAL:
					legacy_spells = "Fire Bolt at level 1, Hellish Rebuke at level 3, Darkness at level 5."
			return "Fiendish Legacy (%s): resistance to %s damage.\n%s Cast with your best of INT/WIS/CHA — each free once per long rest, then a real spell slot.\n%s" % [
				legacy_name, legacy_dmg, legacy_spells, darkvision]
		Stats.CharacterRace.AASIMAR:
			return "Celestial Resistance: resistance to Necrotic and Radiant damage.\nHealing Hands: touch-heal 1d4 × proficiency bonus HP, costs your action (once per long rest).\nLight Bearer: know the Light cantrip.\nCelestial Revelation (from level 3): choose Heavenly Wings/Inner Radiance/Necrotic Shroud, once per long rest — 10 turns, first damage each turn deals bonus Radiant/Necrotic damage equal to your proficiency bonus.\n%s" % darkvision
		Stats.CharacterRace.GNOME:
			var cunning_stat: String = stats.gnomish_cunning_stat.to_upper() if stats.gnomish_cunning_stat != "" else "?"
			var gnome_lineage: String = ""
			match stats.race_variant:
				Stats.GnomeLineage.FOREST:
					gnome_lineage = "Gnomish Lineage (Forest): know Minor Illusion and Speak with Animals, each castable proficiency-bonus times for free per long rest."
				Stats.GnomeLineage.ROCK:
					gnome_lineage = "Gnomish Lineage (Rock): know Mending, castable proficiency-bonus times for free per long rest."
			return "Gnomish Cunning: Advantage on %s saves.\n%s\n%s" % [cunning_stat, gnome_lineage, darkvision]
		Stats.CharacterRace.GOLIATH:
			var giant_name: String = GIANT_ANCESTRIES[clampi(stats.race_variant, 0, GIANT_ANCESTRIES.size() - 1)]
			return "Large Form (from level 5): grow to a 2x2 giant for up to 100 turns in a big enough space — Advantage on STR checks, +1/3 movement speed — once per long rest, press again to end early.\nPowerful Build: Advantage to end the Grappled condition (not yet wired — no Grappled condition exists yet).\nGiant Ancestry (%s Giant): activate for a proficiency-bonus-per-long-rest effect.\nNo darkvision." % giant_name
	return "No race selected."

static func build_bbcode(id: String) -> String:
	if id == "concentration":
		var spell_id: String = GameState.player_stats.concentration_spell_id
		var sp: Spell = SpellDb.get_spell(spell_id) if spell_id != "" else null
		var spell_name: String = sp.spell_name if sp != null else "a spell"
		var turns_left: int = GameState.player_stats.concentration_turns_remaining()
		return "[b]Concentrating: %s[/b]\n%s\n%d turns remaining (if concentration holds)." % [spell_name, get_text(id), turns_left]
	if id == "race_bonus":
		return "[b]Race Bonus: %s[/b]\n%s" % [race_display_name(GameState.player_stats), get_text(id)]
	var title: String = TITLES.get(id, id)
	var text: String = get_text(id)
	return "[b]%s[/b]\n%s" % [title, text]
