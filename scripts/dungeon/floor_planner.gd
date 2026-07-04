class_name FloorPlanner
extends RefCounted
# Initialize phase of the generation pipeline (architecture doc §2.1):
# decides *what* rooms exist, not where. Geometry is assigned by a builder.


# STILL intentionally minimal (deviation from a literal reading of §2.1, reasoned
# per §8 step 1): the plan is only [EntranceRoom, ExitRoom]. Today's BSP algorithm
# has no explicit room budget — room count falls out of _split_bsp's
# MAX_DEPTH/MIN_ROOM_SIZE recursion — and BspBuilder reproduces that behavior
# exactly, so it does not consume the plan's room count as a constraint. Emitting
# a guessed StandardRoom count here would be dead data, and plan() still makes
# ZERO rng calls (any rng use here would shift the seeded stream).
#
# Phase 2 (Floor Feelings): `room_budget_mult` is read below so the wiring exists,
# but it is currently INERT — there is no room budget for it to multiply until a
# builder that consumes the planned room count lands (LoopBuilder / weighted
# ROOM_POOL, Phase 3+). Do not mistake this for the feeling doing nothing overall:
# `water_mult` is live in LevelPainter, and `enemy_mult`/`loot_mult` belong to the
# population side (dungeon_floor.gd), not to this planner.
static func plan(_floor_num: int, feeling: String, _rng: RandomNumberGenerator) -> Array:
	# Wired-but-inert until a real room budget exists (see note above).
	var _room_budget_mult: float = FloorFeeling.FEELINGS.get(feeling, {}).get("room_budget_mult", 1.0)

	var rooms: Array = []
	rooms.append(EntranceRoom.new())
	rooms.append(ExitRoom.new())
	return rooms
