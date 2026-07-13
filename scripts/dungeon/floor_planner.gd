class_name FloorPlanner
extends RefCounted
# Initialize phase of the generation pipeline (architecture doc §2.1):
# decides *what* rooms exist, not where. Geometry is assigned by a builder.
#
# Phase 3 (LoopBuilder): plan() emits a REAL room budget — Entrance + Exit +
# fill StandardRooms — because LoopBuilder actually places every planned
# room (BspBuilder still ignores the list content, so the BSP fallback path is
# unaffected by budget size). `room_budget_mult` (Floor Feelings) is therefore
# LIVE as of Phase 3: the "large" feeling scales the room count.
#
# Session 7b (special-rooms-economy-design.md §3): ROOM_POOL special-room
# selection. Each pool entry gets an independent Bernoulli draw per eligible
# slot — deliberately NOT weighted draws, so the number of rng calls depends
# ONLY on floor_num (eligibility is depth-gated, never seed-gated) and the
# seeded stream layout is identical for every seed at a given depth.
#
# RNG FOOTPRINT (intentional changes, documented per scripts/dungeon/CLAUDE.md):
# - Phase 3: plan() consumes exactly ONE rng call (the base-budget roll below).
# - Session 7b: on non-boss floors >= 2, plan() additionally consumes one
#   rng.randf() per eligible ROOM_POOL slot AFTER the budget roll. Floor 1
#   (below every min_depth) and boss floors (floor_num % 5 == 0) consume ZERO
#   extra calls and emit the exact pre-7b room list — byte-identical output
#   for every existing seed on those floors. Floors 2+ intentionally shift the
#   stream (same precedent as Phase 3's footprint change).
# The seeded call sequence is: feeling roll → plan() → builder → painter.
#
# Budget calibration (LOOP_BUILDER_ARCHITECTURE.md §1 density math + assumption c):
# base 8-10 rooms + up to +3 with depth, ×room_budget_mult, hard-clamped to 15 —
# above ~15 rooms of 5-11 tiles, rejection sampling on the 46×46 usable area
# starts failing often enough to trip the fallback ladder. If the §8 harness ever
# measures a fallback rate >2%, LOWER this budget — do not raise retry counts.

const MAX_ROOM_BUDGET: int = 13
const MIN_ROOM_BUDGET: int = 4

# chance = independent per-floor spawn probability (design doc §3.2 for why not
# weights). plan() never special-cases a type_id — it reads chance/min_depth/
# max_per_floor generically and instantiates entry["script"].new(). Adding a
# room type = one class file + one pool entry. DECLARATION ORDER IS LOAD-BEARING:
# it fixes the rng draw order for every seed.
const ROOM_POOL: Array[Dictionary] = [
	{"script": TreasureRoom, "chance": 0.30, "min_depth": 2, "max_per_floor": 1},
	{"script": ShopRoom,     "chance": 0.40, "min_depth": 3, "max_per_floor": 1},
	{"script": GardenRoom,   "chance": 0.35, "min_depth": 2, "max_per_floor": 1},
	{"script": SecretRoom,   "chance": 0.30, "min_depth": 4, "max_per_floor": 1},
]


static func plan(floor_num: int, feeling: String, rng: RandomNumberGenerator) -> Array:
	var mult: float = FloorFeeling.FEELINGS.get(feeling, {}).get("room_budget_mult", 1.0)
	# Budget roll — UNCHANGED call #1; position in the seeded stream is load-bearing.
	var base: int = rng.randi_range(7, 9) + mini(floor_num / 3, 2)
	var budget: int = clampi(roundi(base * mult), MIN_ROOM_BUDGET, MAX_ROOM_BUDGET)

	var specials: Array = []
	if floor_num % 5 != 0:                       # no special rooms on boss floors
		for entry: Dictionary in ROOM_POOL:      # fixed declaration order — load-bearing
			if floor_num < entry["min_depth"]:
				continue                          # ineligible: NO rng consumed
			for _i: int in entry.get("max_per_floor", 1):
				if rng.randf() < entry["chance"]:  # one draw per eligible slot
					specials.append(entry["script"].new())

	var rooms: Array = []
	rooms.append(EntranceRoom.new())
	rooms.append(ExitRoom.new())
	rooms.append_array(specials)
	var standards: int = maxi(budget - 2 - specials.size(), 2)   # floor: ≥2 standard rooms
	for _i: int in standards:
		rooms.append(StandardRoom.new())
	return rooms
