class_name TalentTiers
extends RefCounted

# Pure talent-tier level/unlock gating — extracted out of game_state.gd, same static-func-only
# pattern as TalentIcons/EquipRequirements. GameState.tier_for_level()/tier_unlocked() are 1-line
# delegators; GameState.TIER_LEVEL_RANGES is kept as a const alias since nothing outside this file
# reads it directly today, but aliasing costs nothing and keeps the door open.

# Level → talent-point tier schedule (docs/architecture/class-progression-rules.md §4): three tiers
# of 6 points each, then the Epic Boon pool at level 20. A tier's point count is the number of
# level-up TRANSITIONS inside its range, so T1 [1,7] yields 6 (into levels 2-7) — no point is ever
# granted at level 1. Levels past Stats.MAX_LEVEL are unreachable (Stats.gain_exp() clamps).
const TIER_LEVEL_RANGES: Dictionary = {1: [1, 7], 2: [8, 13], 3: [14, 19], 4: [20, 20]}

## First level of a tier's range — also the level that tier unlocks at (tiers 2-4).
static func tier_start_level(tier: int) -> int:
	return int(TIER_LEVEL_RANGES[tier][0])

## Which tier's pool a level-up at `lv` feeds. 0 = no talent point (outside every range).
static func tier_for_level(lv: int) -> int:
	for tier: int in TIER_LEVEL_RANGES:
		var r: Array = TIER_LEVEL_RANGES[tier]
		if lv >= r[0] and lv <= r[1]:
			return tier
	return 0

## Whether talents of `tier` can currently be invested in. Points accumulate while locked.
## Level-only gates — no boss kill required (direct owner decision, 2026-09-10). Tier 2 still
## reads its own flag because it also needs setup (Barbarian's subclass pick builds the tree);
## GameState._check_tier2_level_gate() flips it the moment tier_start_level(2) is reached.
static func tier_unlocked(tier: int, tier2_unlocked: bool, character_level: int) -> bool:
	match tier:
		1: return true
		2: return tier2_unlocked
		3: return character_level >= tier_start_level(3)
		4: return character_level >= tier_start_level(4)
		_: return false
