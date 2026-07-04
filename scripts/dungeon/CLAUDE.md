# scripts/dungeon

Pure procedural dungeon generation — no node dependencies, no GameState access, no signals.

## Maintenance rule
When adding tile types or changing generation parameters, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Generation pipeline (Initialize → Build → Paint)
Spec: `docs/architecture/DUNGEON_GENERATION_ARCHITECTURE.md`. Phase 1 (§8 step 1, pipeline split) and Phase 2 (seeded-shuffle fix + Floor Feelings, §8 step 3) are done. Public entry point unchanged. Phase 2 intentionally diverged from the Phase-1 byte-identical baseline (shuffle fix + feeling roll changed the rng stream); the invariant now is **reproducibility**: same seed+floor → identical output, no global-RNG dependence.

### DungeonGenerator (`dungeon_generator.gd`) — orchestrator
`DungeonGenerator.generate(seed: int, floor_num: int) -> DungeonData` — pure static function, safe to call anywhere; the only call site is `DungeonFloor._load_floor()`.

Floor seed: `run_seed XOR (floor_num * 0x9e3779b9)` (computed inside `generate()`).
Flow: seeded rng → **feeling roll** (`FloorFeeling.roll(rng)`, FIRST rng-consuming call — position in the stream is load-bearing; boss floors get `""` without rolling) → `FloorPlanner.plan()` → `BspBuilder.build()` → inline post-processing (fallback room if empty; `player_start` = center of smallest room; `stairs_pos` = center of Manhattan-farthest room; `boss_room` when `floor_num % 5 == 0`; sets `data.feeling`; tags Entrance/Exit `Room.rect`) → `LevelPainter.paint()`.

### FloorFeeling (`floor_feeling.gd`) + RngUtil (`rng_util.gd`)
`FloorFeeling.FEELINGS` (data table, §5: `"large"`/`"traps"`/`"water"`) + `roll(rng) -> String` (50% `""`, else uniform pick). Consumers read multipliers ONLY via `FEELINGS.get(feeling, {}).get("x_mult", 1.0)` — never an if/elif chain on the feeling name. **Multiplier status**: `water_mult` **live** (scales water cluster count in `LevelPainter`); `room_budget_mult` **wired but inert** (no room budget exists until LoopBuilder/ROOM_POOL, Phase 3+); `enemy_mult`/`loot_mult`/`trap_mult` **out of scope for this directory** — they belong to runtime population in `dungeon_floor.gd` (future session reads them off `DungeonData.feeling`).
`RngUtil.shuffle(arr, rng)` — seeded Fisher-Yates (SEEDED_FLOOR_POPULATION.md §3). Godot's `Array.shuffle()` uses the global RNG; **never call `.shuffle()` inside generation code** — always `RngUtil.shuffle`.

### Room types (`room_type.gd`, `standard_room.gd`, `entrance_room.gd`, `exit_room.gd`)
`Room` extends `RefCounted` (deliberately NOT `Resource` — pure generation-time data). Fields: `type_id: String`, `rect: Rect2i` (empty until Build), `connections: Array[Room]`, `required: bool`. Virtuals: `min_size()`, `max_size()`, `max_connections()`, `paint(data, rng)` (no-op base). Concrete: `StandardRoom` (plain floor), `EntranceRoom`/`ExitRoom` (`required = true`). One `class_name` per file — new special room types extend `StandardRoom` in their own file; placeholder types simply don't override `paint()`. Only these three exist in Phase 1 (TrapRoom/Shop/etc. are future phases).

### FloorPlanner (`floor_planner.gd`) — Initialize
`FloorPlanner.plan(floor_num, feeling, rng) -> Array` (of `Room`). Still returns exactly `[EntranceRoom, ExitRoom]` and **makes zero rng calls** (BspBuilder still determines room count itself). Reads `room_budget_mult` from `FloorFeeling` (structurally wired) but it is **inert** — nothing consumes a room budget yet. The weighted `ROOM_POOL`/room-budget logic is Phase 3+.

### BspBuilder (`builders/bsp_builder.gd`) — Build
`BspBuilder.build(rooms: Array, rng) -> DungeonData` — grid fill, BSP split/carve, corridor connect + dedup (`bsp_pairs`), room extensions, extra loop corridors. Owns the generation constants (`GRID_WIDTH/GRID_HEIGHT = 48`, `MIN_ROOM_SIZE = 5`, `MAX_ROOM_DIM = 11`, `MAX_DEPTH = 6`). Ignores the planned room list in Phase 1 (BSP recursion decides count/geometry, exactly as pre-refactor). Never fails — it is the guaranteed-success fallback builder for future builders.

### LevelPainter (`level_painter.gd`) — Paint
`LevelPainter.paint(data, rooms, rng, feeling) -> void` — first calls `room.paint(data, rng)` per planned room (all currently no-ops), then level-wide overlays in fixed order: `_place_pillars` → `_place_chasms` → `_place_water_mud` → `_place_grass_clusters`. `_is_connected()` lives here (only pillars/chasms use it). The `"water"` feeling scales `_place_water_mud()`'s cluster count (`roundi(randi_range(2,4) * water_mult)`); `trap_mult` has nothing to multiply here (traps are runtime-placed by `dungeon_floor.gd`). **Shuffle bug FIXED in Phase 2**: the two formerly-unseeded `dirs4.shuffle()` calls (SEEDED_FLOOR_POPULATION.md §1.1) now use `RngUtil.shuffle(dirs4, rng)`; the old inline Fisher-Yates loops in pillars/chasms were also replaced with `RngUtil.shuffle` (identical rng consumption).

### Reproducibility rule
Any change to this pipeline must preserve the seeded-rng call order unless it is an intentional generation change, and must never touch the global RNG (`.shuffle()`, bare `randi()`/`randf()`). Verify with `scripts/dungeon/_verify/dump_gen.gd` (temporary headless dump script — run via `godot --headless --path <project> --script res://scripts/dungeon/_verify/dump_gen.gd` with `DUMP_PATH` env var; it deliberately randomizes the global RNG, so two consecutive runs producing identical dumps proves full seededness). Delete `_verify/` once the migration (Phase 3) no longer needs it.

---

## DungeonData (`dungeon_data.gd`)
```gdscript
grid: Array          # grid[y][x] → TileType int  (NOT Array[Array[int]] — untyped for speed)
rooms: Array         # Array[Rect2i] — all BSP leaf rooms
player_start: Vector2i
stairs_pos: Vector2i
boss_room: Rect2i    # valid only when floor_num % 5 == 0; otherwise empty Rect2i()
start_room: Rect2i   # the room the player spawns in
width: int           # 48
height: int          # 48
feeling: String      # Floor Feeling id ("" = none; always "" on boss floors) — display/debug only
```

Helper: `get_tile(x, y) -> TileType` — returns VOID for out-of-bounds.
`is_walkable(pos) -> bool` — true for FLOOR, STAIRS_DOWN, WATER, MUD, GRASS, TRAMPLED_GRASS.

---

## TileType enum (complete)
| Value | Name | Walkable | Blocks LOS | Movement cost | Notes |
|---|---|---|---|---|---|
| 0 | VOID | no | yes | — | out-of-bounds / empty space |
| 1 | FLOOR | yes | no | 1 | standard |
| 2 | WALL | no | yes | — | |
| 3 | STAIRS_DOWN | yes | no | 1 | triggers descent |
| 4 | CHASM | no | no | — | ranged LOS passes through |
| 5 | WATER | yes | no | 2 | slows movement |
| 6 | MUD | yes | no | 2 | slows movement |
| 7 | GRASS | yes | no | 1 | ranged LOS passes through |
| 8 | TRAMPLED_GRASS | yes | no | 1 | grass walked on by enemy |

LOS behaviour: `has_line_of_sight()` (Bresenham, strict) blocks WALL, VOID, CHASM.
`has_ranged_los()` (permissive) blocks WALL and VOID only — passes through doors, grass, chasms.

---

## Adding a new tile type
1. Add to `TileType` enum in `dungeon_data.gd`
2. Update `is_walkable()` in `dungeon_data.gd` if walkable
3. Add atlas source entry in `DungeonFloor._setup_tileset()`
4. Handle in `DungeonFloor._load_floor()` match block (place tile, apply any effects)
5. Update LOS functions in `dungeon_floor.gd` if the tile has special sight rules
6. Update the table above in this file

---

## BSP node (`bsp_node.gd`)
Recursive binary space partition tree. Leaf nodes become rooms. Internal nodes connect children with L-shaped corridors. Corridor dedup pass prevents doubled-up paths between the same pair of rooms.
