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
@export var prepared_spells: Array[String] = []      # today's prepared leveled spells (never cantrips)

var slot_pool: StandardSlotPool = null               # null until the caster's class-defaults init grants one

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
# ability_mod + caster_level formula for Wizard.
func prepared_max(stats: Stats) -> int:
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

# How many cantrips this caster can know at once, by class + character level. Wizard: 3 (levels
# 1-3), 4 (levels 4-9), 5 (levels 10+) — direct owner spec. Not derived generically since other
# classes are expected to get their own progression later; add a branch here when they do.
func cantrip_max(stats: Stats) -> int:
	match stats.character_class:
		Stats.CharacterClass.WIZARD:
			if stats.character_level >= 10:
				return 5
			if stats.character_level >= 4:
				return 4
			return 3
		_:
			return 0
