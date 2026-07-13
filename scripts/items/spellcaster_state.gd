class_name SpellcasterState
extends Resource

# Minimal per-caster spellcasting state — the cantrip-only slice of
# docs/architecture/spellcasting-design.md §4.2. Deliberately holds no SpellSlotPool/prepared-vs-
# known distinction: cantrips are always castable, unconditionally free. Lives on Stats.caster
# (not GameState) so a future enemy/companion caster can carry its own instance — same reasoning
# as every other per-entity combat field.

@export var spellcasting_ability: String = "INT"   # "INT" / "WIS" / "CHA"
@export var known_spells: Array[String] = []

# Computed live, never cached — mirrors Stats.mastery_cap()'s "recompute every time" convention
# so a level-up (proficiency_bonus) is picked up automatically. Deliberately NOT derived from
# character_class (see design doc §10.3 — this placement is what keeps a future multiclass sane).
func spell_attack_bonus(stats: Stats) -> int:
	return stats.proficiency_bonus + _ability_mod(stats)

func spell_save_dc(stats: Stats) -> int:
	return 8 + stats.proficiency_bonus + _ability_mod(stats)

func _ability_mod(stats: Stats) -> int:
	match spellcasting_ability:
		"WIS": return stats.wis_modifier()
		"CHA": return stats.cha_modifier()
		_:     return stats.int_modifier()
