# scripts/dungeon

Pure procedural dungeon generation — no node dependencies, no GameState access, no signals.

## Maintenance rule
When adding tile types or changing generation parameters, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Generation pipeline (Initialize → Build → Paint)
Phase 1 (pipeline split), Phase 2 (seeded-shuffle fix + Floor Feelings), and Phase 3 (LoopBuilder + room budget + retry/fallback orchestration) are done. Public entry point unchanged. The invariant is **reproducibility**: same seed+floor → identical output, no global-RNG dependence.

### DungeonGenerator (`dungeon_generator.gd`) — orchestrator
`DungeonGenerator.generate(seed: int, floor_num: int) -> DungeonData` — pure static function, safe to call anywhere; the only call site is `DungeonFloor._load_floor()`.

Floor seed: `run_seed XOR (floor_num * 0x9e3779b9)` (computed inside `generate()`).
Flow: seeded rng → **feeling roll** (`FloorFeeling.roll(rng)`, FIRST rng-consuming call — position in the stream is load-bearing; boss floors get `""` without rolling) → `FloorPlanner.plan()` (1 rng call, room budget) → **builder with retry/fallback**: `LoopBuilder.build()` up to `BUILDER_RETRIES = 3` times, each on a fresh deterministic substream (`floor_seed + attempt * 0x1000193` — the MAIN rng stream position is identical no matter which attempt wins or whether all fail); on exhaustion, `BspBuilder.build()` with the **same rooms list** on the main rng (no re-plan). BSP-fallback path keeps the legacy post-processing (fallback room if empty; `player_start` = smallest room; `stairs_pos` = farthest room; tags Entrance/Exit `Room.rect`); LoopBuilder sets all of that itself. Then builder-agnostic `boss_room` = the room containing `stairs_pos` when `floor_num % 5 == 0` (for BSP output this equals the old "farthest room"); sets `data.feeling` → **exports `data.room_metadata`** (session 7b bridge: one `{"type_id", "rect"}` entry per planned room whose `type_id` isn't standard/entrance/exit AND whose `rect` is non-empty — on BSP-fallback floors specials never get a rect, so they silently don't materialize, by design) → `LevelPainter.paint()`.

### FloorFeeling (`floor_feeling.gd`) + RngUtil (`rng_util.gd`)
`FloorFeeling.FEELINGS` (data table, §5: `"large"`/`"traps"`/`"water"`) + `roll(rng) -> String` (50% `""`, else uniform pick). Consumers read multipliers ONLY via `FEELINGS.get(feeling, {}).get("x_mult", 1.0)` — never an if/elif chain on the feeling name. **Multiplier status**: `water_mult` **live** (scales water cluster count in `LevelPainter`); `room_budget_mult` **live** (scales `FloorPlanner.plan()`'s room budget since Phase 3); `enemy_mult`/`loot_mult`/`trap_mult` **out of scope for this directory** — they belong to runtime population in `dungeon_floor.gd` (future session reads them off `DungeonData.feeling`).
`RngUtil.shuffle(arr, rng)` — seeded Fisher-Yates. Godot's `Array.shuffle()` uses the global RNG; **never call `.shuffle()` inside generation code** — always `RngUtil.shuffle`.

### Room types (`room_type.gd`, `standard_room.gd`, `entrance_room.gd`, `exit_room.gd`, `shop_room.gd`, `treasure_room.gd`, `garden_room.gd`, `secret_room.gd`)
`Room` extends `RefCounted` (deliberately NOT `Resource` — pure generation-time data). Fields: `type_id: String`, `rect: Rect2i` (empty until Build), `connections: Array[Room]`, `required: bool`. Virtuals: `min_size()`, `max_size()`, `max_connections()`, `paint(data, rng)` (no-op base). Concrete: `StandardRoom` (plain floor), `EntranceRoom`/`ExitRoom` (`required = true`), plus the four session-7b special-room **stubs** (`shop_room.gd`/`treasure_room.gd`/`garden_room.gd`/`secret_room.gd` — each `extends StandardRoom`, `_init()` sets only `type_id` (`"shop"`/`"treasure"`/`"garden"`/`"secret"`), everything else inherited; their real sizing/`max_connections()`/`paint()` overrides land in sessions 7c–7f per `docs/architecture/special-rooms-economy-design.md` §4). One `class_name` per file — placeholder types simply don't override anything (structural fallback; never write a `has_content()` runtime check).

### FloorPlanner (`floor_planner.gd`) — Initialize
`FloorPlanner.plan(floor_num, feeling, rng) -> Array` (of `Room`). Rng call #1 is the room-budget roll (`randi_range(7,9) + mini(floor/3, 2)`, × `room_budget_mult` — **live**, clamped 4–13). **Session 7b (special-rooms-economy-design.md §3)**: `ROOM_POOL: Array[Dictionary]` (`{"script", "chance", "min_depth", "max_per_floor"}` — Treasure 0.30/d2, Shop 0.40/d3, Garden 0.35/d2, Secret 0.30/d4) is selected via **independent Bernoulli draws** (one `rng.randf()` per eligible slot, pool declaration order fixed/load-bearing), deliberately NOT weighted draws: the rng call count depends only on `floor_num` (eligibility depth-gated via `min_depth`, `continue` before any draw), so the stream layout is seed-independent at a given depth. Boss floors (`floor % 5 == 0`) and floor 1 (below every `min_depth`) consume **zero** extra calls → byte-identical pre-7b output; floors 2+ intentionally shifted the stream (documented RNG FOOTPRINT change, same precedent as Phase 3). Output: `[Entrance, Exit] + specials + maxi(budget - 2 - specials.size(), 2) × StandardRoom`. `plan()` never special-cases a `type_id` — new room type = one class file + one pool entry.

### BspBuilder (`builders/bsp_builder.gd`) — Build
`BspBuilder.build(rooms: Array, rng) -> DungeonData` — grid fill, BSP split/carve, corridor connect + dedup (`bsp_pairs`), room extensions, extra loop corridors. Owns the generation constants (`GRID_WIDTH/GRID_HEIGHT = 48`, `MIN_ROOM_SIZE = 5`, `MAX_ROOM_DIM = 11`, `MAX_DEPTH = 6`). Ignores the planned room list in Phase 1 (BSP recursion decides count/geometry, exactly as pre-refactor). Never fails — it is the guaranteed-success fallback builder for future builders.

### LevelPainter (`level_painter.gd`) — Paint
`LevelPainter.paint(data, rooms, rng, feeling) -> void` — first calls `room.paint(data, rng)` per planned room (all currently no-ops), then level-wide overlays in fixed order: `_place_pillars` → `_place_chasms` → `_place_water_mud` → `_place_grass_clusters`. `_is_connected()` lives here (only pillars/chasms use it). The `"water"` feeling scales `_place_water_mud()`'s cluster count (`roundi(randi_range(2,4) * water_mult)`); `trap_mult` has nothing to multiply here (traps are runtime-placed by `dungeon_floor.gd`). **Shuffle bug FIXED in Phase 2**: the two formerly-unseeded `dirs4.shuffle()` calls now use `RngUtil.shuffle(dirs4, rng)`; the old inline Fisher-Yates loops in pillars/chasms were also replaced with `RngUtil.shuffle` (identical rng consumption).

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
room_metadata: Array # Array[Dictionary] {"type_id": String, "rect": Rect2i} — one per placed special
                     # room (session 7b bridge); regenerated from seed each _load_floor(), never
                     # serialized; empty on floor 1 / boss floors / BSP-fallback floors
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
