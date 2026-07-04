# Dungeon Generation Architecture

Current state (`scripts/dungeon/dungeon_generator.gd`): a single pure static `DungeonGenerator.generate(seed, floor_num) -> DungeonData` function that does BSP partition → carve rooms → connect corridors → carve extra loop corridors → place pillars/chasms/water/mud/grass, all in one procedure with no concept of "room type." Adding a shop or vault today means inserting a new special case into this one function — every new room type increases the coupling. This doc specs a room-first, three-phase pipeline (Initialize → Build → Paint, after Shattered Pixel Dungeon's v0.6.0 levelgen) that makes new room types additive instead of invasive, while keeping today's BSP output byte-identical at every commit along the way.

---

## 1. Where this lives and what stays untouched

New files under `scripts/dungeon/` (same "pure generation, no node/GameState/signal dependencies" rule as today — see `scripts/dungeon/CLAUDE.md`):
- `scripts/dungeon/room_type.gd` — `Room` base class + concrete room types
- `scripts/dungeon/floor_planner.gd` — Initialize phase
- `scripts/dungeon/builders/` — `bsp_builder.gd`, `loop_builder.gd`, `fixed_builder.gd` (Build phase, one file per builder)
- `scripts/dungeon/level_painter.gd` — Paint phase (level-wide overlays: water/grass/traps/feelings)
- `scripts/dungeon/floor_feeling.gd` — feeling data table

**Untouched:** `DungeonData`'s existing public fields (`grid`, `rooms`, `player_start`, `stairs_pos`, `boss_room`, `start_room`, `width`, `height`) and `is_walkable()`/`get_tile()`. `DungeonFloor` (`scripts/world/dungeon_floor.gd`) consumes `DungeonData` today and must keep working unmodified through the whole migration — that's the hard constraint that makes the phased migration path (§7) possible.

---

## 2. The three-phase pipeline

### 2.1 Initialize — `FloorPlanner.plan(floor_num: int, feeling: String, rng: RandomNumberGenerator) -> Array[Room]`

Decides *what* rooms exist, not where. Always emits exactly one `EntranceRoom` and one `ExitRoom`, plus a depth-scaled budget of rooms drawn from the weighted pool (§4). Boss floors (`floor_num % 5 == 0`) still call this (so the pipeline has one entry point, no special "skip planning" case) but the plan is ignored by `FixedBuilder` (§2.2) — Initialize output is only consumed by builders that want it.

Output is a flat `Array[Room]` with no position/size assigned yet (`rect` stays `Rect2i()` until Build runs) — this is the phase boundary: Initialize commits to *identity and count*, Build commits to *geometry*.

### 2.2 Build — duck-typed builder contract

```gdscript
# Any builder implements:
func build(rooms: Array[Room], rng: RandomNumberGenerator) -> DungeonData
```

Takes the planned room list, returns a fully-carved `DungeonData` (grid painted with FLOOR/WALL for room+corridor shapes only — no water/grass/traps yet, that's Paint) with each `Room.rect` set and `room.connections: Array[Room]` populated. No shared base "Builder" class is needed — GDScript duck typing plus a documented function signature is enough for a project this size (**rejected: interface-via-inheritance boilerplate** for a contract with one method).

Failure handling: a builder may fail to place all rooms (e.g. `LoopBuilder` runs out of space). Contract: return `null` on failure rather than a partial/invalid `DungeonData`. Caller (`FloorPlanner`-adjacent orchestration, see §2.4) retries the same builder up to N times with a fresh rng substream, then falls back to `BspBuilder` (which — being the current always-succeeds algorithm — is the guaranteed-success fallback for every non-fixed floor).

**Boss floors use `FixedBuilder`**, which ignores its `rooms` argument and returns one of a small set of hand-authored `DungeonData` layouts keyed by `boss_id` (matching the `boss_id` key the Enemy doc adds to `BOSS_POOL`). This is still "just a builder" in the same pipeline — no `if floor_num % 5 == 0: special_generate()` branch anywhere in orchestration code. `FixedBuilder.build()` sets `boss_room` itself instead of `LevelPainter` inferring it.

### 2.3 Paint — `LevelPainter.paint(data: DungeonData, rooms: Array[Room], rng: RandomNumberGenerator, feeling: String) -> void`

Two sub-steps, both mutating `data.grid` in place:
1. **Per-room paint**: for each `Room` with an assigned `rect`, call `room.paint(data, rng)`. A `StandardRoom.paint()` is a no-op (BSP already carved plain floor in Build — see §3 on why paint-then-carve order is flipped for MVP). A `TrapRoom.paint()` places 1-2 traps from the existing `TRAP_POOL` directly inside its rect. A `ShopRoom.paint()` (until shop content exists) simply isn't overridden — see §3's placeholder-fallback mechanism.
2. **Level-wide overlay paint**: today's `_place_pillars`/`_place_chasms`/`_place_water_mud`/`_place_grass_clusters` move here verbatim (they already operate on the whole `data.grid` post-carve, so they're already "level painter" shaped) — each reads `FloorFeeling` multipliers (§5) instead of hardcoded ranges.

---

## 3. `Room` base class and placeholder fallback

```gdscript
class_name Room
extends RefCounted   # not Resource — pure generation-time data, never serialized, never inspected in-editor

var type_id: String
var rect: Rect2i = Rect2i()
var connections: Array[Room] = []
var required: bool = false   # true only for Entrance/Exit

func min_size() -> Vector2i: return Vector2i(5, 5)
func max_size() -> Vector2i: return Vector2i(11, 11)
func max_connections() -> int: return 4
func paint(data: DungeonData, rng: RandomNumberGenerator) -> void:
    pass   # StandardRoom behavior: no-op, rect is already plain floor from Build
```

Concrete types for MVP: `EntranceRoom`, `ExitRoom`, `StandardRoom`, `TrapRoom`, `ShopRoom`, `TreasureRoom`, `GardenRoom`, `SecretRoom`.

**Placeholder fallback = plain inheritance, not a runtime check.** `ShopRoom extends StandardRoom` and simply does not override `paint()` — it inherits `StandardRoom`'s no-op. When shop content is designed later, only `ShopRoom.paint()` gets written; nothing else in the pipeline changes, and there is no `if not room.has_content(): fallback_paint()` branch anywhere to maintain. This is the entire mechanism the brief asked for "graceful degradation, not a crash" — achieved with zero fallback machinery:

```gdscript
class_name ShopRoom
extends StandardRoom
# paint() not overridden yet — inherits StandardRoom's no-op. Override here when shop content lands.

class_name TrapRoom
extends StandardRoom
func paint(data: DungeonData, rng: RandomNumberGenerator) -> void:
    # non-placeholder from day one — reuses existing TRAP_POOL via DungeonFloorData
    ...

class_name TreasureRoom
extends StandardRoom
# placeholder — locked-door + reward-item reuse of the existing _spawn_locked_doors() pattern comes later
```

`EntranceRoom`/`ExitRoom` override `required = true` in `_init()` and are the only types `FloorPlanner` always includes regardless of the weighted pool.

---

## 4. Room pool — weighted, depth-dependent, additive

```gdscript
# floor_planner.gd
const ROOM_POOL: Array[Dictionary] = [
    {"script": StandardRoom, "weight": 10, "min_depth": 1},
    {"script": TrapRoom,     "weight": 3,  "min_depth": 1, "max_per_floor": 2},
    {"script": ShopRoom,     "weight": 1,  "min_depth": 3, "max_per_floor": 1},
    {"script": TreasureRoom, "weight": 2,  "min_depth": 2, "max_per_floor": 1},
    {"script": GardenRoom,   "weight": 2,  "min_depth": 1, "max_per_floor": 1},
    {"script": SecretRoom,   "weight": 1,  "min_depth": 4, "max_per_floor": 1},
]
```

Adding a new room type = one new class file + one new `ROOM_POOL` entry. `FloorPlanner.plan()` never special-cases a `type_id` string — it only ever reads `weight`/`min_depth`/`max_per_floor` generically and instantiates `entry["script"].new()`. This is the concrete "must be easy to add new room types without modifying the core generator" requirement from the brief.

---

## 5. Floor feelings — data, not branches

```gdscript
# floor_feeling.gd
const FEELINGS: Dictionary = {
    "large": {"room_budget_mult": 1.5, "enemy_mult": 1.3, "loot_mult": 1.3},
    "traps": {"trap_mult": 3.0},
    "water": {"water_mult": 2.0},
}

static func roll(rng: RandomNumberGenerator) -> String:
    if rng.randf() >= 0.5:
        return ""   # no feeling, 50% of non-boss floors
    var keys := FEELINGS.keys()
    return keys[rng.randi_range(0, keys.size() - 1)]
```

`FloorPlanner.plan()` multiplies its base room-budget/enemy-count/item-count by `FEELINGS.get(feeling, {}).get("room_budget_mult", 1.0)` etc. — always a dictionary lookup with a neutral default, never an `if feeling == "large": ... elif feeling == "traps": ...` chain. Same pattern in `LevelPainter` for `trap_mult`/`water_mult`. Adding a new feeling later is one new dict entry; nothing else changes. `DungeonData` gains `feeling: String = ""` (empty = none) purely for display/debug (compass/seed-info panels) — no gameplay code should ever switch on it directly; gameplay code reads the multiplier dicts.

---

## 6. Boss floors, integration with existing systems

- **Boss floors**: `FixedBuilder.build()` returns the hand-authored `DungeonData` for that `boss_id` and sets `boss_room` directly — same pipeline entry point (`FloorPlanner.plan()` still runs for bookkeeping/consistency but its output is discarded by `FixedBuilder`), no parallel code path. `_spawn_boss()` in `dungeon_floor.gd` is unaffected — it already keys off `boss_room`/floor number, not off how the floor was generated.
- **Doors**: stay runtime-detected exactly as today (`_spawn_doors()` scans room perimeters in `dungeon_floor.gd`) — this works on *any* room geometry, procedural or fixed, so it needs no change for MVP. Noted as a later improvement (Build phase could emit door positions into `Room.connections` directly), explicitly **out of scope** now — don't build it speculatively.
- **Traps**: `TrapRoom.paint()` calls straight into the existing `TRAP_POOL`/trap-placement helpers in `dungeon_floor_data.gd` — reused, not reimplemented. Level-wide trap density additionally scales via the `"traps"` feeling multiplier in `LevelPainter`.
- **FOV**: no change. Shadowcasting reads `data.grid`/tile types agnostically regardless of how the grid was produced.
- **Water/Garden**: `GardenRoom.paint()` (once implemented) paints WATER/GRASS tiles directly inside its rect; the `"water"` feeling multiplies the level-wide water cluster count in `LevelPainter`. Same tile types, same `TileType` enum — no new tile types needed for this doc's scope.

---

## 7. BSP's fate: converted, not retired

`DungeonGenerator`'s current BSP logic (`_split_bsp`/`_carve_rooms`/`_connect_bsp`/`_add_room_extensions`/`_add_extra_corridors`) becomes `BspBuilder.build()` verbatim — it already produces exactly a `DungeonData` with carved rooms/corridors, which is precisely the Build-phase contract. It is **not** retired: it's the guaranteed-success fallback every other builder retries into (§2.2), and remains the only builder for a while (§8 migration step 1 doesn't even need a second builder to ship). `LoopBuilder` (SPD-style, room-graph loops instead of a tree) is a later addition that plugs into the same `build(rooms, rng) -> DungeonData` contract — this doc does not need to fully design `LoopBuilder`'s internals now; that's implementation work for the session that adds it, not an architecture gap.

---

## 8. Migration path — game stays playable at every commit

The current `DungeonGenerator.generate(seed, floor_num) -> DungeonData` static function is a public API consumed only by `DungeonFloor._load_floor()` (one call site). That single call site is the entire migration surface.

**Step 1 (minimum viable first commit):** Introduce the pipeline with `BspBuilder` as the only builder, `FloorPlanner` producing only `EntranceRoom`/`ExitRoom`/`StandardRoom` (no special room types active yet), and `LevelPainter` doing exactly today's pillar/chasm/water/mud/grass calls with no feelings active (feeling always `""`). Wrap all of this behind a new `DungeonGenerator.generate(seed, floor_num) -> DungeonData` that has the **same signature** as today, so `dungeon_floor.gd` needs zero changes. Verify: same seed + floor number produce byte-identical `DungeonData.grid`/`rooms`/`player_start`/`stairs_pos` to the pre-migration output (diff the grids in a debug script) — this is the commit that proves the refactor is behavior-preserving before any new room type is even reachable.

**Step 2:** Activate `TrapRoom` in the pool (already non-placeholder) — first room type that visibly changes generated output. Verify: floors show TrapRoom-tagged rects using existing traps, nothing else regresses.

**Step 3:** Wire feelings (`FloorFeeling.roll()` + multiplier reads in `FloorPlanner`/`LevelPainter`) — still `BspBuilder`-only.

**Step 4:** Add `LoopBuilder`, wire the retry-then-fallback-to-Bsp orchestration.

**Step 5+ (explicitly out of scope for this doc, per the brief):** implement `ShopRoom`/`TreasureRoom`/`GardenRoom`/`SecretRoom` paint bodies, one at a time, whenever their content is designed. Each is a single-file change plus flipping its `ROOM_POOL` weight up from a low placeholder value.

Each numbered step above is independently shippable and leaves the game fully playable — this is the answer to "what's the minimum viable first commit."
