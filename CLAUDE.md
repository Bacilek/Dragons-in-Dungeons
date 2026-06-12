# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. There are no CLI build commands — Godot is the only way to run or export.

Controls: Arrow keys / WASD = move, Space = sword attack (passes turn), `.` = wait.

## Architecture

### Singletons (autoloads, always accessible by name)
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, current floor number, player `Stats` resource, signals `floor_changed` / `player_hp_changed`. Call `GameState.advance_floor()` on stair descent.
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — turn phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input is hard-gated on `TurnManager.phase == WAITING_FOR_INPUT`. Any new entity must call `TurnManager.register_enemy(self)` after spawn and `TurnManager.clear_enemies()` before floor reload.

### Turn flow (critical to understand before touching player or enemy code)
1. Player presses key → `player.gd` calls `TurnManager.begin_player_action()` (phase → RESOLVING_PLAYER)
2. Player action completes (after tween) → calls `TurnManager.on_player_action_complete()`
3. `TurnManager._process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase returns to WAITING_FOR_INPUT

### Dungeon
- **`DungeonGenerator.generate(seed, floor_num)`** — pure static function, returns a `DungeonData` resource. Reproducible: seed is `run_seed XOR (floor * 0x9e3779b9)`. BSP tree depth 5, 48×48 grid, L-shaped corridors between sibling room centers.
- **`DungeonData`** — holds `grid: Array[Array[int]]` (indexed `grid[y][x]`), `rooms`, `player_start`, `stairs_pos`. `TileType` enum: `VOID=0, FLOOR=1, WALL=2, STAIRS_DOWN=3`.
- **`DungeonFloor`** (`scripts/world/dungeon_floor.gd`) — owns the `TileMapLayer`, `Entities` node, enemy list, and fog overlay. Calls `_load_floor()` on start and on each stair descent. Tileset is built programmatically at runtime (no `.tres` file needed).

### Entity hierarchy
```
Entity (CharacterBody2D)        ← grid_pos, move_to() with 0.08s tween, _tile_center()
  ├── Player                    ← input handling, AnimatedSprite2D with knight_m frames
  └── Enemy                     ← take_turn() random walk, orc_warrior frames
```
World position = `pos * TILE_SIZE + TILE_SIZE / 2` (centered on tile). `TILE_SIZE = 16`.

### Fog of war
`DungeonFloor` maintains a 48×48 RGBA `Image` scaled ×16 as a `Sprite2D` at `z_index = 2`. Transparent = visible (radius 6), 65% black = explored, fully black = unknown. Player at `z_index = 3` (always visible). Enemies at `z_index = 1` (hidden under fog when outside FOV). Call `dungeon_floor.update_fog(player_pos)` after every player action.

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. Ability scores default to 10; `modifier(score)` returns `floor((score-10)/2)`. `apply_class_defaults()` sets class-appropriate scores and derives `max_hp` (max HD roll + CON mod), `armor_class` (10 + DEX mod), `proficiency_bonus = 2`. Classes: `FIGHTER` (d10), `ROGUE` (d8), `WIZARD` (d6), `CLERIC` (d8).

## Sprite Assets

All character sprites are individual 16×16 PNGs under `sprites/0x72_DungeonTilesetII_v1.7/frames/`. Naming pattern: `{character}_{anim}_f{n}.png`. Available characters: `knight_m`, `knight_f`, `orc_warrior`, `masked_orc` (each with `idle`/`run` 4-frame and `hit` 1-frame). Dungeon tiles: `floor_1.png`, `wall_mid.png`, `floor_stairs.png`. **Use `wall_mid.png` for walls, NOT `wall_top_mid.png`** — the `_top_` variant is just a thin horizontal bar at the bottom edge of the frame; it makes walls appear shifted down and creates visual confusion about tile boundaries. `SpriteFrames` are built in `_setup_animations()` in each entity script — no `.tres` import files needed.

## Git Workflow

After every feature, fix, or meaningful change: `git add`, `git commit`, `git push origin main`. No need to ask — always commit and push as part of finishing any task.

## Key Conventions

- **New enemy type**: extend `Entity`, implement `take_turn()`, build `SpriteFrames` in `_setup_animations()`, call `TurnManager.register_enemy(self)` from `DungeonFloor._spawn_enemies()`.
- **New floor tile type**: add value to `DungeonData.TileType`, add a source in `DungeonFloor._setup_tileset()`, handle in the `match` block in `_load_floor()`.
- **UI signals**: HUD connects to `GameState` signals (`floor_changed`, `player_hp_changed`). Add new HUD elements by connecting additional signals from `GameState` — never read `GameState` state directly in `_process()`.
- **Fog after any action**: every player action must call `_dungeon_floor.update_fog(grid_pos)` before `TurnManager.on_player_action_complete()`.
- **Floor transitions**: `DungeonFloor.on_player_reached_stairs()` calls `GameState.advance_floor()` then `_load_floor()`. The `_explored` dict and fog image reset on each `_load_floor()` call.
- **GDScript type inference**: always use explicit types (`var x: int`, `Array[Enemy]`, `for y: int in n`). Iterating over an `int` or an untyped `Array` yields untyped loop variables, causing parser errors on any `:=` expression that depends on them. Prefer typed arrays and annotated for-loop variables throughout.
