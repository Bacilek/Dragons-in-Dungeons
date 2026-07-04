class_name FloorPlanner
extends RefCounted
# Initialize phase of the generation pipeline (architecture doc §2.1):
# decides *what* rooms exist, not where. Geometry is assigned by a builder.
#
# Phase 3 (LoopBuilder): plan() now emits a REAL room budget — Entrance + Exit +
# (budget - 2) StandardRooms — because LoopBuilder actually places every planned
# room (BspBuilder still ignores the list content, so the BSP fallback path is
# unaffected by budget size). `room_budget_mult` (Floor Feelings) is therefore
# LIVE as of Phase 3: the "large" feeling scales the room count.
#
# RNG FOOTPRINT CHANGE (Phase 3, intentional): plan() now consumes exactly ONE
# rng call (the base-budget roll below). The Phase-1/2 "plan() makes zero rng
# calls" invariant is gone; the seeded call sequence is now:
#   feeling roll → plan() [1 call] → builder → painter.
# Same seed+floor still reproduces identical output — only the stream layout
# shifted, which is an intentional generation change (see scripts/dungeon/CLAUDE.md).
#
# Budget calibration (LOOP_BUILDER_ARCHITECTURE.md §1 density math + assumption c):
# base 8-10 rooms + up to +3 with depth, ×room_budget_mult, hard-clamped to 15 —
# above ~15 rooms of 5-11 tiles, rejection sampling on the 46×46 usable area
# starts failing often enough to trip the fallback ladder. If the §8 harness ever
# measures a fallback rate >2%, LOWER this budget — do not raise retry counts.

const MAX_ROOM_BUDGET: int = 13
const MIN_ROOM_BUDGET: int = 4


static func plan(floor_num: int, feeling: String, rng: RandomNumberGenerator) -> Array:
	var mult: float = FloorFeeling.FEELINGS.get(feeling, {}).get("room_budget_mult", 1.0)
	# ONE rng call — position in the seeded stream is load-bearing (see header).
	var base: int = rng.randi_range(7, 9) + mini(floor_num / 3, 2)
	var budget: int = clampi(roundi(base * mult), MIN_ROOM_BUDGET, MAX_ROOM_BUDGET)

	var rooms: Array = []
	rooms.append(EntranceRoom.new())
	rooms.append(ExitRoom.new())
	for _i: int in budget - 2:
		rooms.append(StandardRoom.new())
	return rooms
