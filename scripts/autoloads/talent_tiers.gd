class_name TalentTiers
extends RefCounted

# Pure talent-tier level/unlock gating — extracted out of game_state.gd, same static-func-only
# pattern as TalentIcons/EquipRequirements. GameState.tier_for_level()/tier_unlocked() are 1-line
# delegators; GameState.TIER_LEVEL_RANGES is kept as a const alias since nothing outside this file
# reads it directly today, but aliasing costs nothing and keeps the door open.

# Level → talent-point tier schedule. Levels outside every range (21+) grant nothing.
const TIER_LEVEL_RANGES: Dictionary = {1: [1, 6], 2: [7, 12], 3: [13, 17], 4: [18, 20]}

## Which tier's pool a level-up at `lv` feeds. 0 = no talent point (level 21+).
static func tier_for_level(lv: int) -> int:
	for tier: int in TIER_LEVEL_RANGES:
		var r: Array = TIER_LEVEL_RANGES[tier]
		if lv >= r[0] and lv <= r[1]:
			return tier
	return 0

## Whether talents of `tier` can currently be invested in. Points accumulate while locked.
static func tier_unlocked(tier: int, tier2_unlocked: bool, tier3_selected_class: int, character_level: int) -> bool:
	match tier:
		1: return true
		2: return tier2_unlocked
		3: return tier3_selected_class != -1 and character_level >= 13
		4: return character_level >= 18
		_: return false
