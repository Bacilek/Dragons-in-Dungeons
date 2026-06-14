# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. No CLI build commands.

**Controls:** Arrow keys/WASD = move (cardinal). Q/E/Z/C or Numpad diagonals = diagonal move. Space/./Numpad5 = wait. F = interact (traps/doors). Ctrl = search. RMB on world = interact. 1–9 = use quickbar slot 0–8. I = open inventory. Left-click enemy = chase+attack. Left-click floor = pathfind.

## Architecture

### Singletons (autoloads)
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, floor number, player `Stats`, inventory (quickbar 9 slots + bag 24 slots), equipment, hunger. Key signals: `floor_changed`, `player_hp_changed`, `player_exp_changed`, `player_leveled_up`, `player_died`, `player_won`, `combat_message`, `inventory_changed`, `equipment_changed`, `hunger_changed`, `player_status_changed`, `player_throw_primed(item)`, `class_chosen`, `player_action_requested(action_name)`. Call `GameState.game_log(msg)` for combat log — **never call `log()`** (that's GDScript's built-in float math function).
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input hard-gated on `phase == WAITING_FOR_INPUT`. New entity: `TurnManager.register_enemy(self)` on spawn, `TurnManager.clear_enemies()` before floor reload.

### Turn flow
1. Player key → `player.gd` calls `TurnManager.begin_player_action()` (phase → RESOLVING_PLAYER)
2. Action completes (after tween) → `TurnManager.on_player_action_complete()`
3. `TurnManager._process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase → WAITING_FOR_INPUT. `player_turn_started` signal fires.

Each turn: hunger depletes 1, status effects tick (`Stats.tick_status()` → dmg), HP regen every 10 turns (blocked while Starving).

### Dungeon
- **`DungeonGenerator.generate(seed, floor_num)`** — pure static, returns `DungeonData`. Seed: `run_seed XOR (floor * 0x9e3779b9)`. BSP depth 5, 48×48 grid, L-shaped corridors.
- **`DungeonData`** — `grid: Array[Array[int]]` indexed `[y][x]`. `TileType`: `VOID=0, FLOOR=1, WALL=2, STAIRS_DOWN=3, CHASM=4, WATER=5, MUD=6, GRASS=7`. `boss_room: Rect2i` (empty if not boss floor).
- **`DungeonFloor`** (`scripts/world/dungeon_floor.gd`) — owns TileMapLayer, Entities node, enemy list, fog overlay, traps, doors, floor items. Calls `_load_floor()` on start and stair descent.

### Entity hierarchy
```
Entity (CharacterBody2D)   ← grid_pos, move_to() 0.08s tween, _tile_center()
  ├── Player               ← input, 9-slot quickbar, throw mode, blood trail
  └── Enemy                ← take_turn(), behavior enum (SLEEPING/STATIONARY/ROAMING/CHASING)
```
World position = `pos * TILE_SIZE + TILE_SIZE/2`. `TILE_SIZE = 16`. z-index: floor items=1, enemies=1, player=3, fog=2, damage labels=10. Blood decals: z=0.

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. `modifier(score)` = `floor((score-10)/2)`. `apply_class_defaults()` sets scores and derives `max_hp`, `armor_class`, `proficiency_bonus=2`. Classes: FIGHTER (d10), ROGUE (d8), WIZARD (d6), CLERIC (d8). Status fields: `poison_turns`, `burning_turns`, `bleeding_turns`. `tick_status() -> int` ticks all three and returns total dmg.

### Item system (`scripts/items/item.gd`)
`Item.Type` enum: `WEAPON=0, ARMOR=1, POTION=2, SCROLL=3, FOOD=4, GOLD=5, KEY=6, TOOL=7`. Key fields: `item_name`, `item_type`, `quantity`, `icon_path`, `heal_amount`, `bonus_damage`, `bonus_ac`, `str_bonus`. `get_display_name()` appends `×N` if quantity > 1.

### Hunger system
`GameState.hunger` (0–1000). Thresholds: >600 SATIATED, >200 HUNGRY, else STARVING. Depletes 1/turn. Starvation damage: 1 HP every 10 turns at hunger=0. HP regen disabled while Starving. Eat food: `GameState.use_item(item)` → `restore_hunger(heal_amount)`.

### Trap system (in DungeonFloor)
`_traps: Dictionary` maps `Vector2i → {name, damage, msg, sprite_node, revealed, triggered, is_push, reusable?, push_dir?, wall_pos?}`. Key functions: `trigger_trap(pos)`, `reveal_trap(pos)`, `disarm_trap(pos)`, `search_around(pos) -> int`. Piston traps: only detectable from the push side (`search_around` filters by `-push_dir`). Spike Trap: reusable. Bear Trap: bleeding 5 turns. Fire Trap: burning 4 turns.

### Door system (in DungeonFloor)
`_doors: Dictionary` maps `Vector2i → {is_open: bool, sprite: Sprite2D}`. Auto-opens when entity steps on tile, auto-closes when entity leaves. Enemies open doors and walk through in same turn. Functions: `has_door_at(pos)`, `is_door_open(pos)`, `open_door(pos)`, `close_door(pos)`.

### Floor items (in DungeonFloor)
`_floor_items: Dictionary`, `_floor_item_sprites: Dictionary`. `place_item_on_floor(pos, item)` creates sprite + registers. `pick_up_item(pos) -> Item` removes. `cook_rotten_meat(trap_pos) -> Item` disarms Fire Trap and returns Cooked Meat.

### Throw mechanic
Right-click food item in HUD quickbar → `GameState.player_throw_primed.emit(item)` → player enters throw mode. Left-click target tile → `_do_throw(pos)`. Rotten Meat + Fire Trap = Cooked Meat. Esc cancels.

### Boss rooms
`DungeonData.boss_room: Rect2i` set on floors divisible by 5. `DungeonFloor._spawn_boss()` spawns from `BOSS_POOL`. Floor 5: Big Demon (hp=80). Floor 10: Necromancer (hp=120). Boss dies → `drop_boss_loot(pos)`. `enemy.is_boss: bool`.

## Sprite Assets

- `sprites/characters/` — `{character}_{anim}_f{n}.png`. Characters: `knight_m`, `elf_m`, `wizzard_m`, `dwarf_m`, `orc_warrior`, `masked_orc`, `big_demon`, `necromancer`, etc.
- `sprites/tiles/` — `floor_1.png`, `wall_mid.png` (**not** `wall_top_mid.png`), `floor_stairs.png`.
- `sprites/objects/` — props, flasks, doors, etc.
- `sprites/weapons/` — `weapon_anime_sword.png`, etc.
- `sprites/items/Sprites trial/` — item icons. Constant `ITEMS_PATH` in `dungeon_floor.gd`. Subfolders: `Food/`, `Potions/Health/`, `Potions/Mana/`, `Misc/`.

`SpriteFrames` built in `_setup_animations()` — no `.tres` files needed.

## Git Workflow

After every feature/fix: `git add`, `git commit`, `git push origin HEAD:main`. No need to ask — always commit and push. Use `HEAD:main` (not `main`) — sessions may run in a worktree branch.

## Key Conventions

- **`GameState.game_log(msg)`** — never `log()` (GDScript built-in math).
- **New enemy**: extend `Entity`, implement `take_turn()`, `_setup_animations()`, register via `TurnManager.register_enemy(self)` in `DungeonFloor._spawn_enemies()`. Add `idle_fmt`/`run_fmt` overrides to ENEMY_POOL if sprite naming is non-standard.
- **New floor tile**: add to `DungeonData.TileType`, add source in `DungeonFloor._setup_tileset()`, handle in `_load_floor()` match block.
- **Fog after every action**: call `_dungeon_floor.update_fog(grid_pos)` before `TurnManager.on_player_action_complete()`.
- **Floor transitions**: `DungeonFloor.on_player_reached_stairs()` → `GameState.advance_floor()` → `_load_floor()`. `_explored` dict and fog reset each `_load_floor()`.
- **UI signals**: HUD connects to `GameState` signals only — never poll `GameState` in `_process()`.
- **GDScript types**: always explicit (`var x: int`, `Array[Enemy]`, `for y: int in n`). Untyped arrays/loops cause parser errors on `:=` expressions.
- **Item spawn paths**: `match d["src"]: "weapons" → WEAPONS_PATH, "items" → ITEMS_PATH, _ → OBJECTS_PATH`.
- **Status effects**: set `player_stats.{poison/burning/bleeding}_turns = N`, then `player_status_changed.emit()`. `tick_status()` is called once per turn in `_on_turn_started()`.
