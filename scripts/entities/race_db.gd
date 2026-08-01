class_name RaceDb
extends RefCounted

# Structured race data — mirrors SpellDb's "build fresh every call" convention, but keyed off a
# live Stats instance (not a fixed id) since several races' trait text depends on race_variant
# (Elf sub-race, Tiefling legacy, Dragonborn ancestry, Gnome lineage, Goliath ancestry) and on
# darkvision_bonus (already resolved by Stats.apply_race_defaults()). See RaceTooltip
# (race_tooltip.gd) for the structured-tooltip formatter that consumes this, and
# scripts/entities/CLAUDE.md's per-race sections for the mechanics these descriptions summarize.

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
const ELF_SUBRACES: Array[String] = ["Drow", "High Elf", "Wood Elf"]
const DRAGONBORN_ANCESTRIES: Array[String] = [
	"Black", "Blue", "Brass", "Bronze", "Copper", "Gold", "Green", "Red", "Silver", "White",
]
const TIEFLING_LEGACIES: Array[String] = ["Abyssal", "Chthonic", "Infernal"]
const GNOME_LINEAGES: Array[String] = ["Forest", "Rock"]
const GIANT_ANCESTRIES: Array[String] = ["Cloud", "Fire", "Frost", "Hill", "Stone", "Storm"]

static func _darkvision_label(bonus: int) -> String:
	if bonus >= 2:
		return "Superior"
	if bonus >= 1:
		return "Normal"
	return "None"

## trait: {id, name, desc, subs: Array[{id, name, desc}]} — subs empty for a plain trait.
static func _t(id: String, name: String, desc: String, subs: Array = []) -> Dictionary:
	return {"id": id, "name": name, "desc": desc, "subs": subs}

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

## {creature_type, size, speed, darkvision, traits: Array[Dictionary]}
static func build(stats: Stats) -> Dictionary:
	var dv: String = _darkvision_label(stats.darkvision_bonus)
	var traits: Array = []
	match stats.character_race:
		Stats.CharacterRace.ORC:
			traits = [
				_t("relentless_endurance", "Relentless Endurance", "When a hit would drop you to 0 HP, drop to 1 HP instead. Once per long rest."),
				_t("adrenaline_rush", "Adrenaline Rush", "Free action. Gain temp HP equal to your proficiency bonus and your next move is free. Proficiency-bonus uses, refills on short AND long rest."),
			]
			return {"creature_type": "Humanoid", "size": "Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.HUMAN:
			traits = [
				_t("skillful", "Skillful", "Bonus check proficiency in one ability score of your choosing."),
				_t("versatile", "Versatile", "Gain an Origin feat. (Not yet implemented.)"),
				_t("heroic_inspiration", "Heroic Inspiration", "Free action. Your next d20 roll (attack, check, or save) is guaranteed a natural 20. Once per long rest."),
			]
			return {"creature_type": "Humanoid", "size": "Small or Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.HALFLING:
			traits = [
				_t("luck", "Luck", "A natural 1 on any of your d20 rolls is automatically rerolled — you must use the new result."),
				_t("brave", "Brave", "Advantage on saves to avoid or end Frightened."),
				_t("nimbleness", "Halfling Nimbleness", "Free action, once per round. Slip through the space of a creature larger than you."),
			]
			return {"creature_type": "Humanoid", "size": "Small", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.DWARF:
			traits = [
				_t("dwarven_toughness", "Dwarven Toughness", "+1 max HP every level, including level 1."),
				_t("dwarven_resilience", "Dwarven Resilience", "Resistance to Poison damage."),
				_t("stonecunning", "Stonecunning", "Free action. Sense living creatures within 6 tiles standing on your same terrain, through walls/darkness. Proficiency-bonus uses per long rest."),
			]
			return {"creature_type": "Humanoid", "size": "Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.ELF:
			var lineage_desc: String = ""
			match stats.race_variant:
				Stats.ElfSubrace.DROW:
					lineage_desc = "Drow: learn Faerie Fire at level 3, Darkness at level 5 — each free once per long rest."
				Stats.ElfSubrace.HIGH_ELF:
					lineage_desc = "High Elf: a free long-rest cantrip swap, learn Detect Magic at level 3, Misty Step at level 5 — each free once per long rest."
				Stats.ElfSubrace.WOOD_ELF:
					lineage_desc = "Wood Elf: +1/3 movement speed, learn Longstrider at level 3, Pass Without Trace at level 5 — each free once per long rest."
			traits = [
				_t("keen_senses", "Keen Senses", "WIS check proficiency."),
				_t("fey_ancestry", "Fey Ancestry", "Advantage on checks to avoid/end Charmed. (No Charmed condition exists yet.)"),
				_t("trance", "Trance", "Your long rests take half as long."),
				_t("elven_lineage", "Elven Lineage", lineage_desc),
			]
			return {"creature_type": "Humanoid", "size": "Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.DRAGONBORN:
			var dmg_type: String = Stats.DRAGONBORN_DAMAGE_TYPE[clampi(stats.race_variant, 0, Stats.DRAGONBORN_DAMAGE_TYPE.size() - 1)]
			traits = [
				_t("draconic_ancestry", "Draconic Ancestry", "Resistance to %s damage, plus a matching Breath Weapon (Cone or Line AoE, %s damage)." % [dmg_type, dmg_type]),
				_t("draconic_flight", "Draconic Flight", "Free action, once per long rest. For 100 turns: cross chasms, immune to standing-fire damage, no grass trample/traps. From level 5."),
			]
			return {"creature_type": "Humanoid", "size": "Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.TIEFLING:
			var legacy_name: String = TIEFLING_LEGACIES[clampi(stats.race_variant, 0, TIEFLING_LEGACIES.size() - 1)]
			var legacy_dmg: String = Stats.TIEFLING_LEGACY_RESIST[clampi(stats.race_variant, 0, Stats.TIEFLING_LEGACY_RESIST.size() - 1)]
			traits = [
				_t("fiendish_legacy", "Fiendish Legacy", "%s Legacy: resistance to %s damage, plus one spell each at levels 1/3/5, castable free (best of INT/WIS/CHA) before costing a real spell slot." % [legacy_name, legacy_dmg]),
			]
			return {"creature_type": "Humanoid", "size": "Small or Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.AASIMAR:
			traits = [
				_t("celestial_resistance", "Celestial Resistance", "Resistance to Necrotic and Radiant damage."),
				_t("healing_hands", "Healing Hands", "Costs your action. Touch-heal (proficiency bonus)d4 HP. Once per long rest."),
				_t("light_bearer", "Light Bearer", "You know the Light cantrip."),
				_t("celestial_revelation", "Celestial Revelation",
					"From level 3, once per long rest. Transform for 10 turns — the first damage you deal each turn is boosted by your proficiency bonus. Choose a form on activation:",
					[
						{"id": "heavenly_wings", "name": "Heavenly Wings", "desc": "Grants flight for the duration: cross chasms, immune to standing-fire damage, no grass trample/traps."},
						{"id": "inner_radiance", "name": "Inner Radiance", "desc": "Deals proficiency-bonus Radiant damage to every enemy within 2 tiles on activation, and again at the end of every turn for the duration. +2 FOV radius."},
						{"id": "necrotic_shroud", "name": "Necrotic Shroud", "desc": "On activation, every enemy within 2 tiles rolls a CHA check or becomes Frightened of you for 2 turns."},
					]),
			]
			return {"creature_type": "Humanoid", "size": "Small or Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.GNOME:
			var cunning_stat: String = stats.gnomish_cunning_stat.to_upper() if stats.gnomish_cunning_stat != "" else "?"
			var lineage_name: String = GNOME_LINEAGES[clampi(stats.race_variant, 0, GNOME_LINEAGES.size() - 1)]
			var gnome_desc: String = ""
			match stats.race_variant:
				Stats.GnomeLineage.FOREST:
					gnome_desc = "Forest: know Minor Illusion and Speak with Animals, each castable proficiency-bonus times per long rest for free."
				Stats.GnomeLineage.ROCK:
					gnome_desc = "Rock: know Mending, castable proficiency-bonus times per long rest for free."
			traits = [
				_t("gnomish_cunning", "Gnomish Cunning", "Advantage on %s saves." % cunning_stat),
				_t("gnomish_lineage", "Gnomish Lineage", gnome_desc if gnome_desc != "" else "%s lineage." % lineage_name),
			]
			return {"creature_type": "Humanoid", "size": "Small", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
		Stats.CharacterRace.GOLIATH:
			var giant_name: String = GIANT_ANCESTRIES[clampi(stats.race_variant, 0, GIANT_ANCESTRIES.size() - 1)]
			traits = [
				_t("powerful_build", "Powerful Build", "Advantage to end Grappled. (No Grappled condition exists yet.)"),
				_t("large_form", "Large Form", "From level 5, once per long rest. Grow to a 2x2 giant for up to 100 turns: Advantage on STR checks, +1/3 movement speed."),
				_t("giant_ancestry", "Giant Ancestry", "%s Giant: a proficiency-bonus-per-long-rest activatable effect." % giant_name),
			]
			return {"creature_type": "Humanoid", "size": "Medium", "speed": "1 tile/turn", "darkvision": dv, "traits": traits}
	return {"creature_type": "", "size": "", "speed": "", "darkvision": dv, "traits": []}
