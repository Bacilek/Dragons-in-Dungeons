# scripts/dungeon

Pure procedural dungeon generation — no node dependencies, no GameState access, no signals.

## Maintenance rule
When adding tile types or changing generation parameters, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## DungeonGenerator (`dungeon_generator.gd`)
`DungeonGenerator.generate(seed: int, floor_num: int) -> DungeonData` — pure static function, safe to call anywhere.

Floor seed: `run_seed XOR (floor_num * 0x9e3779b9)` (computed inside `generate()`).
Parameters: BSP depth 5, 48×48 grid, L-shaped corridors with dedup to prevent overlaps.

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
