extends Node

# Rng — the shared gameplay RNG service (SAVE_LOAD_ARCHITECTURE.md §6, implemented
# for seeded-run determinism: same run_seed + same inputs → identical playthrough).
#
# ALL gameplay-affecting randomness that happens DURING a floor (combat rolls, crits,
# enemy AI decisions, resist checks, trap-trigger saves, loot rolled at kill time,
# status-effect durations, push damage, rest healing) draws from this single stream.
# Cosmetic randomness (camera shake, tween/particle jitter) deliberately stays on the
# global unseeded RNG and must never be migrated (IMPLEMENTATION_SEQUENCE.md invariant 8).
#
# NOT this stream: floor-load-time structure/population. Tile generation uses
# DungeonGenerator's own seeded rng; floor population uses DungeonFloor._pop_rng
# (seeded per-floor from run_seed — SEEDED_FLOOR_POPULATION.md). Those must stay
# pure functions of (run_seed, floor) so a reloaded save regenerates the identical
# floor regardless of how many gameplay rolls were consumed before saving.
#
# Seeding: GameState.start_new_run() calls Rng.reseed(run_seed). Save/load persists
# the exact stream position via get_state()/set_state() (GameState.to_dict()/from_dict(),
# stored as a String because JSON round-trips large int64s through float and would
# lose precision).

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


## Reset the stream to the start of a run. Called by GameState.start_new_run().
func reseed(seed_value: int) -> void:
	_rng.seed = seed_value


## Die roll: 1..sides inclusive (D&D semantics — replaces randi_range(1, sides)).
func roll(sides: int) -> int:
	return _rng.randi_range(1, sides)


## Integer in [from, to] inclusive (replaces randi_range(from, to)).
func range_i(from: int, to: int) -> int:
	return _rng.randi_range(from, to)


## True with the given probability in [0, 1] (replaces randf() < p).
func chance(probability: float) -> bool:
	return _rng.randf() < probability


## Uniform random element of a non-empty array (replaces arr[randi() % arr.size()]).
func pick(arr: Array) -> Variant:
	return arr[_rng.randi_range(0, arr.size() - 1)]


## In-place seeded Fisher-Yates (replaces Array.shuffle(), which only uses the
## global RNG). Delegates to the shared RngUtil helper so there is one implementation.
func shuffle(arr: Array) -> void:
	RngUtil.shuffle(arr, _rng)


## Exact stream position for save files. int64 — serialize as String (see header).
func get_state() -> int:
	return _rng.state


func set_state(s: int) -> void:
	_rng.state = s
