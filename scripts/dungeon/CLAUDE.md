# scripts/dungeon

Pure procedural dungeon generation — no node dependencies, no GameState access, no signals.

## Maintenance rule
When adding tile types or changing generation parameters, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Generation pipeline (Initialize → Build → Paint)
Spec: `docs/architecture/DUNGEON_GENERATION_ARCHITECTURE.md`. Phase 1 of the migration (§8 step 1) is done: the old monolithic generator is split behind the pipeline with **byte-identical output** (runtime-diffed). Public entry point unchanged.

### DungeonGenerator (`dungeon_generator.gd`) — orchestrator
`DungeonGenerator.generate(seed: int, floor_num: int) -> DungeonData` — pure static function, safe to call anywhere; the only call site is `DungeonFloor._load_floor()`.

Floor seed: `run_seed XOR (floor_num * 0x9e3779b9)` (computed inside `generate()`).
Flow: seeded rng → `FloorPlanner.plan()` → `BspBuilder.build()` → inline post-processing (fallback room if empty; `player_start` = center of smallest room; `stairs_pos` = center of Manhattan-farthest room; `boss_room` when `floor_num % 5 == 0`; tags Entrance/Exit `Room.rect`) → `LevelPainter.paint()`.

### Room types (`room_type.gd`, `standard_room.gd`, `entrance_room.gd`, `exit_room.gd`)
`Room` extends `RefCounted` (deliberately NOT `Resource` — pure generation-time data). Fields: `type_id: String`, `rect: Rect2i` (empty until Build), `connections: Array[Room]`, `required: bool`. Virtuals: `min_size()`, `max_size()`, `max_connections()`, `paint(data, rng)` (no-op base). Concrete: `StandardRoom` (plain floor), `EntranceRoom`/`ExitRoom` (`required = true`). One `class_name` per file — new special room types extend `StandardRoom` in their own file; placeholder types simply don't override `paint()`. Only these three exist in Phase 1 (TrapRoom/Shop/etc. are future phases).

### FloorPlanner (`floor_planner.gd`) — Initialize
`FloorPlanner.plan(floor_num, feeling, rng) -> Array` (of `Room`). Phase 1: returns exactly `[EntranceRoom, ExitRoom]` and **makes zero rng calls** (any rng use here would shift the stream and break byte-identity — BspBuilder still determines room count itself). `feeling` accepted and ignored (Phase 2 wires Floor Feelings). The weighted `ROOM_POOL`/room-budget logic is Phase 2.

### BspBuilder (`builders/bsp_builder.gd`) — Build
`BspBuilder.build(rooms: Array, rng) -> DungeonData` — grid fill, BSP split/carve, corridor connect + dedup (`bsp_pairs`), room extensions, extra loop corridors. Owns the generation constants (`GRID_WIDTH/GRID_HEIGHT = 48`, `MIN_ROOM_SIZE = 5`, `MAX_ROOM_DIM = 11`, `MAX_DEPTH = 6`). Ignores the planned room list in Phase 1 (BSP recursion decides count/geometry, exactly as pre-refactor). Never fails — it is the guaranteed-success fallback builder for future builders.

### LevelPainter (`level_painter.gd`) — Paint
`LevelPainter.paint(data, rooms, rng, feeling) -> void` — first calls `room.paint(data, rng)` per planned room (all no-ops in Phase 1), then level-wide overlays in fixed order: `_place_pillars` → `_place_chasms` → `_place_water_mud` → `_place_grass_clusters`. `_is_connected()` lives here (only pillars/chasms use it). `feeling` accepted and ignored (Phase 2). **Known preserved bug**: two unseeded `dirs4.shuffle()` calls in water/mud/grass — fix is Phase 2 (`SEEDED_FLOOR_POPULATION.md` §1.1); do NOT fix piecemeal.

### Byte-identity rule (until migration completes)
Any change to this pipeline must preserve the seeded-rng call order unless it is an intentional generation change. Verify with `scripts/dungeon/_verify/dump_gen.gd` (temporary headless dump script — run via `godot --headless --path <project> --script res://scripts/dungeon/_verify/dump_gen.gd` with `DUMP_PATH` env var, diff dumps before/after; it seeds the global RNG so the unseeded shuffles are reproducible). Delete `_verify/` once the migration (Phase 2/3) no longer needs it.

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
