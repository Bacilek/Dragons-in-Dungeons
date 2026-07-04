class_name FloorFeeling
extends RefCounted
# Floor Feelings — data, not branches (DUNGEON_GENERATION_ARCHITECTURE.md §5).
# Consumers ALWAYS read multipliers via dictionary lookup with a neutral default:
#     FloorFeeling.FEELINGS.get(feeling, {}).get("water_mult", 1.0)
# Never an `if feeling == "...":` chain. Adding a new feeling = one dict entry.
#
# Multiplier wiring status (Phase 2):
#   water_mult       — LIVE: scales water cluster count in LevelPainter._place_water_mud().
#   room_budget_mult — structurally wired into FloorPlanner.plan() but INERT: room
#                      count is still decided by BspBuilder's BSP recursion, which
#                      does not consume the plan. Becomes live with LoopBuilder /
#                      a real room budget (Phase 3+).
#   trap_mult        — nothing to multiply in this pipeline: traps are placed at
#                      runtime by dungeon_floor.gd (out of scope for scripts/dungeon/).
#   enemy_mult / loot_mult — same: enemy/item spawning lives in dungeon_floor.gd.
#                      A future population-side session reads them from DungeonData.feeling.


const FEELINGS: Dictionary = {
	"large": {"room_budget_mult": 1.5, "enemy_mult": 1.3, "loot_mult": 1.3},
	"traps": {"trap_mult": 3.0},
	"water": {"water_mult": 2.0},
}


# 50% chance of "" (no feeling), else uniform pick among FEELINGS keys.
# Boss floors never get a feeling — the orchestrator (DungeonGenerator.generate)
# simply doesn't call roll() on them, so this stays floor-number-agnostic.
static func roll(rng: RandomNumberGenerator) -> String:
	if rng.randf() >= 0.5:
		return ""
	var keys: Array = FEELINGS.keys()
	return keys[rng.randi_range(0, keys.size() - 1)]
