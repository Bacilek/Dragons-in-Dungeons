class_name FloorPlanner
extends RefCounted
# Initialize phase of the generation pipeline (architecture doc §2.1):
# decides *what* rooms exist, not where. Geometry is assigned by a builder.


# PHASE 1 NOTE — intentionally minimal (deviation from a literal reading of §2.1,
# reasoned per §8 step 1): the plan is only [EntranceRoom, ExitRoom]. Today's BSP
# algorithm has no explicit room budget — room count falls out of _split_bsp's
# MAX_DEPTH/MIN_ROOM_SIZE recursion — and BspBuilder (Phase 1) reproduces that
# behavior exactly, so it does not consume the plan's room count as a constraint.
# Emitting a guessed StandardRoom count here would be dead data and, worse, any
# rng consumption in plan() would shift the RNG stream and break the byte-identical
# guarantee. So plan() makes ZERO rng calls in Phase 1. The weighted ROOM_POOL,
# depth-scaled budget, and feeling multipliers land in Phase 2.
#
# `feeling` is accepted and ignored so Phase 2 doesn't have to change this signature.
static func plan(_floor_num: int, _feeling: String, _rng: RandomNumberGenerator) -> Array:
	var rooms: Array = []
	rooms.append(EntranceRoom.new())
	rooms.append(ExitRoom.new())
	return rooms
