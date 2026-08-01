class_name PactSlotPool
extends Resource

# Warlock's Pact Magic bookkeeper — the THIRD distinct slot-progression table
# (StandardSlotPool/HalfCasterSlotPool's own header comments both predicted this). Deliberately
# still a duplicate implementation rather than a shared base class, matching this codebase's own
# "duplicate rather than force a premature abstraction" precedent — but with real behavioral
# differences from the other two, not just a different table:
#   - `max_slots()` always has exactly ONE key (the current pact slot level), not one per level.
#   - `available_level(spell)` returns the CURRENT PACT SLOT LEVEL (not spell.level) whenever a
#     known spell's own level is at or below it and a charge remains — every Pact Magic spell is
#     always cast at the single current slot level, i.e. always auto-upcast. This is the opposite
#     of StandardSlotPool's explicit "no upcasting" rule (see that file's own comment for why that
#     rule was correct for Wizard) — Warlock is a different, correctly-isolated pool class, so
#     that rejection doesn't carry over here. PlayerSpellcasting._cast_level_for() already just
#     forwards whatever available_level() returns straight into SpellEffects.cast_*(), so this one
#     method is 100% of what "always cast at the highest slot" needs — no other file changes.
#   - Recharges on a SHORT rest, not a long rest — `on_short_rest()` (a method neither other pool
#     implements) is the real recharge path; `on_long_rest()` is kept as a harmless full-refill
#     fallback since a long rest also grants everything a short rest would.

const SLOT_COUNT_TABLE: Dictionary = {1: 1, 2: 2, 11: 3, 17: 4}
const SLOT_LEVEL_TABLE: Dictionary = {1: 1, 3: 2, 5: 3, 7: 4, 9: 5}

var owner_stats: Stats = null
var remaining: Dictionary = {}   # {pact_slot_level: remaining_count} — always at most one key

func _table_lookup(table: Dictionary, character_level: int) -> int:
	var value: int = 0
	for threshold: int in table:
		if character_level >= threshold:
			value = maxi(value, table[threshold])
	return value

func pact_slot_level() -> int:
	if owner_stats == null:
		return 0
	return _table_lookup(SLOT_LEVEL_TABLE, mini(owner_stats.character_level, 20))

func pact_slot_count() -> int:
	if owner_stats == null:
		return 0
	return _table_lookup(SLOT_COUNT_TABLE, mini(owner_stats.character_level, 20))

func max_slots() -> Dictionary:
	var lvl: int = pact_slot_level()
	var count: int = pact_slot_count()
	if lvl <= 0 or count <= 0:
		return {}
	return {lvl: count}

static func highest_accessible_level(character_level: int) -> int:
	var lvl: int = 0
	for threshold: int in SLOT_LEVEL_TABLE:
		if character_level >= threshold:
			lvl = maxi(lvl, SLOT_LEVEL_TABLE[threshold])
	return lvl

# Auto-upcast: a known spell at or below the current pact slot level is always cast AT that slot
# level (not its own), as long as a charge remains — see the header comment above.
func available_level(spell: Spell) -> int:
	if spell.level == 0:
		return 0
	var lvl: int = pact_slot_level()
	if lvl <= 0 or spell.level > lvl:
		return -1
	if remaining.get(lvl, 0) > 0:
		return lvl
	return -1

func can_cast(spell: Spell) -> bool:
	return spell.level == 0 or available_level(spell) != -1

func consume(cast_level: int) -> void:
	if cast_level <= 0:
		return
	remaining[cast_level] = remaining.get(cast_level, 0) - 1

func on_long_rest() -> void:
	remaining = max_slots().duplicate()

func on_short_rest() -> void:
	remaining = max_slots().duplicate()

func grant_new_slots_on_levelup(old_max: Dictionary) -> void:
	# A level-up can raise the pact slot LEVEL (the dict's key changes, e.g. 1 -> 2) and/or the
	# slot COUNT (same key, higher value). If the key itself changed, the old `remaining` entry is
	# keyed to a spell level that no longer applies — start that new, higher level fully fresh.
	# If only the count grew, top up the existing key by the delta, same shape as the other pools.
	var new_max: Dictionary = max_slots()
	if new_max.is_empty():
		remaining = {}
		return
	var new_lvl: int = new_max.keys()[0]
	if old_max.has(new_lvl):
		remaining[new_lvl] = remaining.get(new_lvl, 0) + (new_max[new_lvl] - old_max[new_lvl])
	else:
		remaining = new_max.duplicate()

func ui_summary() -> String:
	var mx: Dictionary = max_slots()
	if mx.is_empty():
		return ""
	var lvl: int = mx.keys()[0]
	return "%d: %d/%d" % [lvl, remaining.get(lvl, 0), mx[lvl]]
