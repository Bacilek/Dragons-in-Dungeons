class_name StandardSlotPool
extends Resource

# Wizard's spell-slot bookkeeper — docs/architecture/leveled-spells-and-slots-plan.md §2.
# Deliberately NOT split into a SpellSlotPool base class + subclass hierarchy (the framework
# doc's §4.3 shape): only one caster type exists in the game, so a pluggable-pool abstraction
# for Pact/Cooldown pools that don't exist yet would be speculative. Add the base class back
# when a second caster archetype actually needs a different pool behavior.

const SLOT_TABLE: Dictionary = {
	1: {1: 2},
	2: {1: 3},
	3: {1: 4, 2: 2},
	4: {1: 4, 2: 3},
	5: {1: 4, 2: 3, 3: 2},
	6: {1: 4, 2: 3, 3: 3},
	7: {1: 4, 2: 3, 3: 3, 4: 1},
	8: {1: 4, 2: 3, 3: 3, 4: 2},
	9: {1: 4, 2: 3, 3: 3, 4: 3, 5: 1},
	10: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2},
	11: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1},
	12: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1},
	13: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1},
	14: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1},
	15: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1},
	16: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1},
	17: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1, 9: 1},
	18: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 1, 7: 1, 8: 1, 9: 1},
	19: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 2, 7: 1, 8: 1, 9: 1},
	20: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 2, 7: 2, 8: 1, 9: 1},
}

var owner_stats: Stats = null
var remaining: Dictionary = {}   # slot_level:int -> remaining:int

func max_slots() -> Dictionary:
	if owner_stats == null:
		return {}
	var lv: int = mini(owner_stats.character_level, 20)
	return SLOT_TABLE.get(lv, {})

# Highest spell level a full caster can currently cast at, by character level — 0 if no slots at
# all yet (never happens for Wizard, who has 1st-level slots from level 1). Static/table-driven so
# it can be reused anywhere that needs "what level could this character learn right now" without
# an actual SpellcasterState instance (e.g. floor-loot scroll eligibility).
static func highest_accessible_level(character_level: int) -> int:
	var lv: int = mini(character_level, 20)
	var slots: Dictionary = SLOT_TABLE.get(lv, {})
	var highest: int = 0
	for slot_level: int in slots:
		highest = maxi(highest, slot_level)
	return highest

# A spell is locked to its OWN slot level — no upcasting into a higher, still-available slot.
# Returns spell.level if that level currently has an unspent slot, else -1. Cantrips (level 0)
# never touch this pool at all.
func available_level(spell: Spell) -> int:
	if spell.level == 0:
		return 0
	if remaining.get(spell.level, 0) > 0:
		return spell.level
	return -1

func can_cast(spell: Spell) -> bool:
	return spell.level == 0 or available_level(spell) != -1

func consume(cast_level: int) -> void:
	if cast_level <= 0:
		return
	remaining[cast_level] = remaining.get(cast_level, 0) - 1

func on_long_rest() -> void:
	remaining = max_slots().duplicate()

# Called from GameState.gain_exp() right after a level-up so newly unlocked/grown slots are
# immediately usable instead of sitting empty until the next long rest (deviation from the
# framework doc's "new slots arrive empty" note — justified in leveled-spells-and-slots-plan.md
# §2, since Wizard has no short-rest recharge to fall back on).
func grant_new_slots_on_levelup(old_max: Dictionary) -> void:
	var new_max: Dictionary = max_slots()
	for lv: int in new_max:
		var delta: int = new_max[lv] - old_max.get(lv, 0)
		if delta > 0:
			remaining[lv] = remaining.get(lv, 0) + delta

func ui_summary() -> String:
	var parts: PackedStringArray = []
	var mx: Dictionary = max_slots()
	var levels: Array = mx.keys()
	levels.sort()
	for lv: int in levels:
		parts.append("%d: %d/%d" % [lv, remaining.get(lv, 0), mx[lv]])
	return "  ".join(parts)
