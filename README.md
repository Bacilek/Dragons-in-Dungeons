# Dragons in Dungeons

A 2D pixel roguelike built in **Godot 4 (Mono build)** — Pixel Dungeon's gameplay loop crossed with D&D 5.5e (2024) mechanics.

## Features

- **Procedural dungeon generation** — BSP tree, 48×48 grid, L-shaped corridors, reproducible per seed+floor
- **Turn-based combat** — bump-to-attack, diagonal movement, arc sword-slash animation
- **D&D 5.5e mechanics** — ability scores, modifiers, class HP, proficiency bonus, armor class
- **Enemy AI** — four behavior states (Sleeping/Stationary/Roaming/Chasing), ZZZ indicator, memory through grass
- **Fog of war** — radius-6 FOV, explored (dim) vs unseen (black), LOS with diagonal shoulder check
- **Environment variety** — chasms, water/mud (difficult terrain), destructible grass, doors
- **Trap system** — Bear Trap, Fire Trap, Spike Trap, Pit Spikes (single-use), Piston (permanent), bypass-safety check
- **Full inventory** — 24-slot bag + 5-slot quickbar (HUD), equipment slots (right hand, armor, head, …), drag & drop in overlay (`I` key)
- **Items** — weapons (6 tiers, +damage), armor (+AC), potions (heal, strength), auto-equip on first pickup

## Controls

| Key | Action |
|-----|--------|
| Arrow keys / WASD | Move (cardinal) |
| Q/E/Z/C or Numpad diagonals | Move diagonal |
| Space / `.` / Numpad 5 | Wait a turn |
| Click floor | Pathfind to tile |
| Click enemy | Auto-chase and attack |
| Click open door (adjacent) | Close door |
| **I** | Open / close inventory |
| Right-click item in inventory | Use / equip |
| Drag item | Move between bag / quickbar / equipment slots |

## Running

Open `project.godot` in **Godot 4.6 (Mono build)** and press **F5**. No CLI build steps.

## Architecture

- **Singletons:** `GameState` (floor, player stats, inventory, signals), `TurnManager` (WAITING → RESOLVING_PLAYER → RESOLVING_ENEMIES)
- **Dungeon:** `DungeonGenerator.generate(seed, floor)` → `DungeonData` (grid, rooms, player_start, stairs_pos)
- **World:** `DungeonFloor` — tilemap, fog, traps dict, doors dict, enemy list
- **Entities:** `Entity` (CharacterBody2D, grid_pos, move_to tween) → `Player` / `Enemy`
- **UI:** `HUD` (CanvasLayer 10), `InventoryOverlay` (CanvasLayer 15, I key)

## Sprites

- Characters: `sprites/characters/` — `{name}_{idle|run}_anim_f{n}.png`  
- Tiles: `sprites/tiles/` — `floor_1.png`, `wall_mid.png`, `floor_stairs.png`, `hole.png`
- Objects: `sprites/objects/` — doors, flasks, chests, coins
- Weapons: `sprites/weapons/`

All sprites from [0x72 DungeonTilesetII](https://0x72.itch.io/dungeontileset-ii) (CC0, 16×16 px).
