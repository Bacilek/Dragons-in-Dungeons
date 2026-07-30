class_name HalfCasterSlotPool
extends Resource

# Ranger/Paladin's spell-slot bookkeeper — the D&D 2024 half-caster table (slots start at
# character level 1, unlike the 2014 rules' level-2 start; max spell level 5, reached at
# character level 17). Same shape/interface as StandardSlotPool (scripts/items/spell_slot_pool.gd)
# on purpose — a duplicate implementation, not a shared base class, matching this codebase's own
# "duplicate rather than force a premature abstraction" precedent (see scripts/entities/CLAUDE.md's
# Conditions section for the same reasoning) until a THIRD distinct slot-progression table shows up.

const SLOT_TABLE: Dictionary = {
	1:  {1: 2},
	2:  {1: 2},
	3:  {1: 3},
	4:  {1: 3},
	5:  {1: 4, 2: 2},
	6:  {1: 4, 2: 2},
	7:  {1: 4, 2: 3},
	8:  {1: 4, 2: 3},
	9:  {1: 4, 2: 3, 3: 2},
	10: {1: 4, 2: 3, 3: 2},
	11: {1: 4, 2: 3, 3: 3},
	12: {1: 4, 2: 3, 3: 3},
	13: {1: 4, 2: 3, 3: 3, 4: 1},
	14: {1: 4, 2: 3, 3: 3, 4: 1},
	15: {1: 4, 2: 3, 3: 3, 4: 2},
	16: {1: 4, 2: 3, 3: 3, 4: 2},
	17: {1: 4, 2: 3, 3: 3, 4: 3, 5: 1},
	18: {1: 4, 2: 3, 3: 3, 4: 3, 5: 1},
	19: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2},
	20: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2},
}

var owner_stats: Stats = null
var remaining: Dictionary = {}   # slot_level:int -> remaining:int

func max_slots() -> Dictionary:
	if owner_stats == null:
		return {}
	var lv: int = mini(owner_stats.character_level, 20)
	return SLOT_TABLE.get(lv, {})

static func highest_accessible_level(character_level: int) -> int:
	var lv: int = mini(character_level, 20)
	var slots: Dictionary = SLOT_TABLE.get(lv, {})
	var highest: int = 0
	for slot_level: int in slots:
		highest = maxi(highest, slot_level)
	return highest

# Same "no upcasting, locked to the spell's own level" rule as StandardSlotPool — see that file's
# own comment for why.
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
