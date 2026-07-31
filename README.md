# Dragons in Dungeons

A 2D pixel roguelike built in **Godot 4 (Mono build)** — Pixel Dungeon's gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells, talents.

## Features

- **Procedural dungeon generation** — BSP tree, 48×48 grid, L-shaped corridors, reproducible per run seed + floor, guaranteed multi-path connectivity between entrance/exit rooms
- **Turn-based combat** — bump-to-attack, diagonal movement, ADV/DISADV house rules, Opportunity Attacks, Stealth & Surprise Attacks
- **D&D 5.5e (2024) mechanics** — point-buy ability scores, background ASI, modifiers, proficiency bonus, armor class, real D&D Conditions (Poisoned, Prone, Restrained, Incapacitated)
- **4 playable classes** — Barbarian, Ranger, Wizard, Monk — each with a talent tree, boss-gated Tier 2 subclasses, and class-specific mechanics (Rage, Hunter's Mark, spell slots, martial arts dice)
- **6 races** — Orc, Human, Halfling, Dwarf, Elf (3 sub-races), Dragonborn — each with distinct traits (darkvision, rest charges, Halfling Lucky reroll, etc.)
- **Wizard spellcasting** — 8 cantrips + 15 leveled spells with real D&D 2024 spell slots, Concentration, an R-key Spellbook overlay, and Scrolls castable by any class
- **Enemy AI** — Sleeping/Stationary/Roaming/Chasing/Searching states, full D&D-style stat blocks (CR, resistances, multiattack, legendary resistance), CR-budgeted floor spawning, multi-tile Large enemies
- **Fog of war** — configurable-radius FOV, explored (dim) vs unseen (black), LOS with diagonal shoulder check
- **Environment variety** — chasms, water/mud (difficult terrain), destructible grass, doors, flammable barrels, fire spread
- **Trap & door system** — Bear Trap, Fire Trap, Spike Trap, Pit Spikes, Piston, Thief Tools lock-picking
- **Special rooms & economy** — Treasure Rooms, Garden Rooms, a gold-currency wallet, and a Blacksmith weapon-forging sink
- **Full inventory** — 9-slot quickbar + 24-slot bag, 9-slot ability bar, equipment slots (weapons, shield, armor, torch), drag & drop, magic item Attunement
- **Rest system** — Short Rest (hit dice) and Long Rest (food-cost, full heal, resource refill, optional mastery reselection); no hunger mechanic
- **Persistent saves** — single-slot run save/continue from the character-select screen

## Controls

Full up-to-date control list lives in `CLAUDE.md`'s "Running the Game" section. Highlights:

| Key | Action |
|-----|--------|
| Arrow keys / WASD | Move (cardinal) |
| Q/E/Z/C or Numpad diagonals | Move diagonal |
| Space / `.` / Numpad 5 | Wait a turn |
| **I** | Open inventory |
| **R** | Open Wizard Spellbook |
| **Tab** | Toggle item bar / ability bar |
| **Alt** | Open Rest panel (short/long rest) |
| 1–9 | Use quickbar slot |
| Left-click enemy | Chase + melee attack |
| Shift + left-click | Ranged attack |
| Ctrl + left-click | Cast Special quick-cast spell |
| Left-click floor | Pathfind |
| RMB (no tool primed) | Inspect; quick second RMB = Search |
| RMB on item | Item interaction menu (Throw/Drop/etc.) |

## Running

Open `project.godot` in **Godot 4.6 (Mono build)** and press **F5**. No CLI build steps.

## Architecture

This is a high-level map — see `CLAUDE.md` (project root) for the authoritative, actively-maintained index, and the sub-directory `CLAUDE.md` files for full mechanics:

- **Singletons (`scripts/autoloads/`):** `GameState` (run/floor/inventory/talent state), `TurnManager` (turn phase state machine), `AudioManager`, `Rng` (seeded gameplay RNG), `SaveManager`
- **Dungeon generation (`scripts/dungeon/`):** `DungeonGenerator.generate(seed, floor)` → `DungeonData`, pipelined through `FloorPlanner` → `BspBuilder` → `LevelPainter`
- **World (`scripts/world/`):** `DungeonFloor` — tilemap, fog, traps, doors, barrels, floor items, special rooms
- **Entities (`scripts/entities/`):** `Entity` (CharacterBody2D) → `Player` / `Enemy` / `Companion`, `Stats` (D&D ability scores/combat math)
- **Items (`scripts/items/`):** `Item`, `Ability`, `Talent`, spellcasting data, `WeaponForge`
- **UI (`scripts/ui/`):** HUD, character/class/race/mastery pickers, Spellbook overlay, inventory overlay, debug panel

## Sprites

Assets are organized under `sprites/`, split by category (`characters/classes/`, `characters/enemies/`, `characters/npcs/`, `tiles/`, `objects/`, `weapons/`, `traps/`, `items/`), each with a matching `_unused/` folder for sourced-but-unreferenced art. Full naming conventions: `CLAUDE.md`'s "Sprite Assets" section.

All sprites from [0x72 DungeonTilesetII](https://0x72.itch.io/dungeontileset-ii) (CC0, 16×16 px), plus Superdark's CC0 16×16 packs for newer character sets.
