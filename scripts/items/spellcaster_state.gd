class_name SpellcasterState
extends Resource

# Per-caster spellcasting state. Started as the cantrip-only slice of
# docs/architecture/spellcasting-design.md §4.2; extended per
# docs/architecture/leveled-spells-and-slots-plan.md §3 for leveled spells + spell slots.
# Lives on Stats.caster (not GameState) so a future enemy/companion caster can carry its own
# instance — same reasoning as every other per-entity combat field.

@export var spellcasting_ability: String = "INT"   # "INT" / "WIS" / "CHA"
@export var known_spells: Array[String] = []        # ALL known spells: cantrips (always castable)
                                                      # AND leveled spells (spellbook, subset prepared)
@export var prepared_spells: Array[String] = []      # currently prepared/selected spells — BOTH
                                                      # cantrips (capped by cantrip_max()) and leveled
                                                      # spells (capped by prepared_max()); a spell can
                                                      # be known (in known_spells) without being here,
                                                      # e.g. learned past its kind's cap

# Untyped (not `: StandardSlotPool`) on purpose: holds a `StandardSlotPool` (Wizard, full-caster)
# OR a `HalfCasterSlotPool` (Ranger, half-caster, scripts/items/half_caster_slot_pool.gd) — the two
# are deliberate duplicate implementations sharing an identical method surface, not a common base
# class (see HalfCasterSlotPool's own header comment), so a static `StandardSlotPool` type
# annotation here would reject assigning the Ranger's pool. Every call site only ever calls the
# shared interface methods (`max_slots()`/`available_level()`/`can_cast()`/`consume()`/
# `on_long_rest()`/`grant_new_slots_on_levelup()`/`ui_summary()`), which both classes implement
# identically in shape, so this resolves correctly at runtime regardless of which one is stored.
var slot_pool = null               # null until the caster's class-defaults init grants one

# Computed live, never cached — mirrors Stats.mastery_cap()'s "recompute every time" convention
# so a level-up (proficiency_bonus, character_level) is picked up automatically. Deliberately NOT
# derived from character_class (see design doc §10.3 — this placement is what keeps a future
# multiclass sane).
func spell_attack_bonus(stats: Stats) -> int:
	return stats.proficiency_bonus + _ability_mod(stats)

func spell_save_dc(stats: Stats) -> int:
	return 8 + stats.proficiency_bonus + _ability_mod(stats)

func _ability_mod(stats: Stats) -> int:
	match spellcasting_ability:
		"WIS": return stats.wis_modifier()
		"CHA": return stats.cha_modifier()
		_:     return stats.int_modifier()

# leveled-spells-and-slots-plan.md §1 owner decision: prepared count = character level, counting
# only leveled (non-cantrip) prepared spells. Supersedes the framework doc's
# ability_mod + caster_level formula for Wizard. Ranger (half-caster, scripts/entities/CLAUDE.md's
# "Ranger class") uses the real 2024 half-caster formula instead: WIS mod + half level (floored),
# minimum 1 — a Ranger always has at least one spell prepared once they have any slot at all.
func prepared_max(stats: Stats) -> int:
	if stats.character_class == Stats.CharacterClass.RANGER:
		return maxi(1, _ability_mod(stats) + stats.character_level / 2)
	return stats.character_level

func is_cantrip(spell_id: String) -> bool:
	var s: Spell = SpellDb.get_spell(spell_id)
	return s != null and s.level == 0

func known_cantrip_count() -> int:
	var count: int = 0
	for sid: String in known_spells:
		if is_cantrip(sid):
			count += 1
	return count

# How many currently-prepared/selected entries in prepared_spells are cantrips vs leveled spells —
# GameState.set_spell_prepared() checks the matching one against cantrip_max()/prepared_max()
# before adding a new entry, since prepared_spells now holds BOTH kinds (see game_state.gd).
func prepared_cantrip_count() -> int:
	var count: int = 0
	for sid: String in prepared_spells:
		if is_cantrip(sid):
			count += 1
	return count

func prepared_leveled_count() -> int:
	var count: int = 0
	for sid: String in prepared_spells:
		if not is_cantrip(sid):
			count += 1
	return count

# How many cantrips this caster can know at once, by class + character level. Wizard: 3 (levels
# 1-3), 4 (levels 4-9), 5 (levels 10+) — direct owner spec. Not derived generically since other
# classes are expected to get their own progression later; add a branch here when they do.
# Warlock reuses the exact same numbers (real 5e Warlock cantrip cap differs slightly, 2/3/4, but
# this project already takes this "reuse Wizard's shape" liberty elsewhere — see scripts/entities/
# CLAUDE.md's "Warlock class").
func cantrip_max(stats: Stats) -> int:
	match stats.character_class:
		Stats.CharacterClass.WIZARD, Stats.CharacterClass.WARLOCK:
			if stats.character_level >= 10:
				return 5
			if stats.character_level >= 4:
				return 4
			return 3
		_:
			return 0
