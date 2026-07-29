class_name TalentIcons
extends RefCounted

# Pure icon-path resolution for talents/abilities — extracted out of game_state.gd (which was
# growing into a god-object) the same way WeaponTooltip/ArmorTooltip were split out of
# hud.gd/inventory_overlay.gd: a static-func-only helper, no mutable state, no signals.
# GameState.talent_icon_path(id, rank) is a 1-line delegator to resolve() below — every other
# file in the project already goes through that function and never touched these dicts directly,
# so nothing else needed to change.

# talent_id → icons/classes/barbarian/<path>_<rank>.png stem. Rank-gradient art (1-3) —
# World Tree only, see icons/classes/barbarian/t2/world_tree/.
const TALENT_ICON_FOLDER: Dictionary = {
	"ironwood_bark": "t2/world_tree/ironwood_bark",
	"grip_of_the_forest": "t2/world_tree/grip_of_the_forest",
	"branching_strike": "t2/world_tree/branching_strike",
}

# talent_id/ability_id → icons/classes/barbarian/<path>.png. Single flat icon (no rank
# gradient) — everything except World Tree (TALENT_ICON_FOLDER above) and the Wild Heart
# form-driven abilities (WILD_HEART_*_ICON below, keyed by current form/rank instead of a
# fixed file).
const TALENT_ICON_FLAT: Dictionary = {
	"rage": "t0/rage",
	"psycho": "t1/psycho_killer",
	"bruiser": "t1/bruiser",
	"battlefield_expert": "t1/battlefield_expert",
	# Berserker
	"frenzy": "t2/berserker/frenzy",
	"sadist_monster": "t2/berserker/sadist",
	"masochist_monster": "t2/berserker/masochist",
	"frenzied_killer": "t2/berserker/blood-rush",
	# Scarred Warrior
	"limit_break": "t2/scarred_warrior/limit_break",
	"born_in_blood": "t2/scarred_warrior/blood_born",
	"enough_is_enough": "t2/scarred_warrior/enough_is_enough",
	"bloodied_regen": "t2/scarred_warrior/blood_flow",
	# Wild Heart (Enhanced Forms only — Animal Form/Natural Sleeper/Wild Companion are
	# form-driven, see WILD_HEART_*_ICON below)
	"enhanced_forms": "t2/wild_heart/animal_instincts",
	# Zealot
	"zealot_strike": "t2/zealot/zealous_strike",
	"judgement_day": "t2/zealot/judgement_day",
	"overheal_shield": "t2/zealot/overheal",
	"never_back_down": "t2/zealot/never_back_down",
	# Barbarian passive, no talent — see GameState._give_barbarian_starting_items()
	"unarmored_defense": "t0/unarmored_defence",
}

# Ranger talent/ability icons — separate dict + folder prefix since TALENT_ICON_FLAT above always
# resolves under res://icons/classes/barbarian/.
const RANGER_TALENT_ICON_FLAT: Dictionary = {
	"hunters_mark": "t0/hunters_mark",
	"trailblazer": "t1/trailblazer",
	"bloodhound": "t1/bloodhound",
	"twin_fang": "t1/twin_fang",
}

# Animal Form's icon follows the currently active form (Bear/Eagle/Wolf) instead of rank.
const WILD_HEART_FORM_ICON: Dictionary = {
	"Bear": "res://icons/classes/barbarian/t2/wild_heart/wild_form_bear.png",
	"Eagle": "res://icons/classes/barbarian/t2/wild_heart/wild_form_eagle.png",
	"Wolf": "res://icons/classes/barbarian/t2/wild_heart/wild_form_wolf.png",
}

# Natural Sleeper's icon follows the previewed/active form (Owl/Panther/Salmon) instead of rank.
const WILD_HEART_SLEEPER_ICON: Dictionary = {
	"Owl": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_owl.png",
	"Panther": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_panther.png",
	"Salmon": "res://icons/classes/barbarian/t2/wild_heart/sleeper_form_salmon.png",
}

# Wild Companion's icon follows the rank's summoned animal — matches GameState.WILD_HEART_COMPANION_STATS.
const WILD_HEART_COMPANION_ICON: Dictionary = {
	1: "res://icons/classes/barbarian/t2/wild_heart/companion_squirrel.png",
	2: "res://icons/classes/barbarian/t2/wild_heart/companion_boar.png",
	3: "res://icons/classes/barbarian/t2/wild_heart/companion_bear.png",
}

## Returns the icon for a talent/ability; "" if unmapped. Most talents resolve to a single flat
## icon (rank ignored) via TALENT_ICON_FLAT; World Tree talents still gradient 1-3 via
## TALENT_ICON_FOLDER; Wild Heart's form-driven abilities (Animal Form/Natural Sleeper/Wild
## Companion) read the CURRENT form state (passed in by the caller — GameState.natural_rager_form/
## natural_sleeper_form — since this class holds no state of its own) instead of a fixed mapping.
static func resolve(id: String, rank: int, current_rager_form: String, current_sleeper_form: String) -> String:
	match id:
		"animal_form":
			return WILD_HEART_FORM_ICON.get(current_rager_form, WILD_HEART_FORM_ICON["Bear"])
		"expanded_forms":
			var preview: String = current_sleeper_form if current_sleeper_form != "" else "Owl"
			return WILD_HEART_SLEEPER_ICON.get(preview, WILD_HEART_SLEEPER_ICON["Owl"])
		"wild_companion":
			return WILD_HEART_COMPANION_ICON.get(clampi(rank, 1, 3), WILD_HEART_COMPANION_ICON[1])
	if RANGER_TALENT_ICON_FLAT.has(id):
		return "res://icons/classes/ranger/%s.png" % RANGER_TALENT_ICON_FLAT[id]
	if TALENT_ICON_FLAT.has(id):
		return "res://icons/classes/barbarian/%s.png" % TALENT_ICON_FLAT[id]
	if TALENT_ICON_FOLDER.has(id):
		var r: int = clampi(rank, 1, 3)
		return "res://icons/classes/barbarian/%s_%d.png" % [TALENT_ICON_FOLDER[id], r]
	return ""
