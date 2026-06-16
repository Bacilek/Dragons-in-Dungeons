# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintenance rule (applies to all sessions)
After every feature, fix, or refactor that changes architecture, adds a system, or modifies any documented behaviour: **update the relevant sub-directory CLAUDE.md and this root CLAUDE.md without waiting to be asked**. Sub-directory CLAUDE.md files live in `scripts/autoloads/`, `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/dungeon/`, and `scripts/items/`.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. No CLI build commands.

**Controls:** Arrow keys/WASD = move (cardinal). Q/E/Z/C or Numpad diagonals = diagonal move. Space/./Numpad5 = wait. F = interact (traps/doors). Ctrl = search. Alt = short rest. RMB on world = interact. 1–9 = use quickbar slot 0–8. I = open inventory. Left-click enemy = chase+attack (melee). Shift+left-click enemy/tile = ranged attack (if ranged weapon equipped and in range). Left-click floor = pathfind. RMB on food in quickbar = throw mode, then LMB = throw. Esc = cancel throw.

## Architecture

### Singletons (autoloads)
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, floor number, player `Stats`, inventory (quickbar 9 slots + bag 24 slots), equipment, hunger, short rest state. Key signals: `floor_changed`, `player_hp_changed`, `player_exp_changed`, `player_leveled_up`, `player_died`, `player_won`, `combat_message`, `inventory_changed`, `equipment_changed`, `hunger_changed`, `player_status_changed`, `player_throw_primed(item)`, `class_chosen`, `player_action_requested(action_name)`, `short_rest_changed`, `stairs_discovered`, `debug_see_all(active: bool)`. Short rest fields: `hit_dice` (available, refills to `character_level` on `advance_floor()`), `short_rests_remaining` (2/floor), `short_rest_open: bool` (blocks all player input while panel is open). `hit_die_sides() -> int` returns class die (Barbarian 12, Ranger 10, Cleric 8, Wizard 6). Call `GameState.game_log(msg)` for combat log — **never call `log()`** (that's GDScript's built-in float math function).
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input hard-gated on `phase == WAITING_FOR_INPUT`. New entity: `TurnManager.register_enemy(self)` on spawn, `TurnManager.clear_enemies()` before floor reload.

### Turn flow
1. Player key → `player.gd` calls `TurnManager.begin_player_action()` (phase → RESOLVING_PLAYER)
2. Action completes (after tween) → `TurnManager.on_player_action_complete()`
3. `TurnManager._process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase → WAITING_FOR_INPUT. `player_turn_started` signal fires.

Each turn: hunger depletes 1, status effects tick (`Stats.tick_status()` → dmg), HP regen every 10 turns (blocked while Starving).

### Dungeon
- **`DungeonGenerator.generate(seed, floor_num)`** — pure static, returns `DungeonData`. Seed: `run_seed XOR (floor * 0x9e3779b9)`. BSP depth 5, 48×48 grid, L-shaped corridors.
- **`DungeonData`** — `grid: Array[Array[int]]` indexed `[y][x]`. `TileType`: `VOID=0, FLOOR=1, WALL=2, STAIRS_DOWN=3, CHASM=4, WATER=5, MUD=6, GRASS=7, TRAMPLED_GRASS=8`. `boss_room: Rect2i` (empty if not boss floor). `rooms: Array[Rect2i]` — all BSP leaf rooms.
- **`DungeonFloor`** (`scripts/world/dungeon_floor.gd`) — owns TileMapLayer, Entities node, enemy list, fog overlay, traps, doors, floor items. Calls `_load_floor()` on start and stair descent. Key query methods: `get_room_centers() -> Array[Vector2i]` (room center tiles for enemy roaming), `is_explored(pos) -> bool`, `is_tile_visible(pos) -> bool` (O(1) dict lookup into `_visible_tiles`), `get_visible_enemies() -> Array[Enemy]`. `FOV_RADIUS = 7`. **Player FOV**: recursive shadowcasting (`_compute_shadowcast` → `_cast_light`, 8 octants, Roguebasin multiplier tables) — result stored in `_visible_tiles: Dictionary`. **Enemy/misc LOS**: Bresenham `has_line_of_sight()` (still used by enemy AI, `search_around()`). LogPanel and StatsPanel in HUD use `MOUSE_FILTER_IGNORE` so game-world clicks pass through the overlay.

### Entity hierarchy
```
Entity (CharacterBody2D)   ← grid_pos, move_to() 0.08s tween, _tile_center()
  ├── Player               ← input, 9-slot quickbar, throw mode, blood trail
  └── Enemy                ← take_turn(), behavior enum (SLEEPING/STATIONARY/ROAMING/CHASING)
```
**Enemy roaming**: ROAMING enemies use waypoint navigation. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks one at Chebyshev distance ≥4 that `is_walkable_for_enemy`. `_do_roam_walk()` follows a cached `_roam_path: Array[Vector2i]` (BFS via `_bfs_to()`); on arrival or blocked path picks a new target; falls back to `_do_random_step()`. `_roam_path`/`_roam_target` are cleared when switching to/from CHASING.
World position = `pos * TILE_SIZE + TILE_SIZE/2`. `TILE_SIZE = 16`. z-index: floor items=1, enemies=1, player=3, fog=2, damage labels=10. Blood decals: z=0.

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. `modifier(score)` = `floor((score-10)/2)`. `apply_class_defaults()` sets scores and derives `max_hp`, `armor_class = 10 + dex_modifier()`, `proficiency_bonus=2`. Classes: BARBARIAN (d12, 12+CON HP, +7+CON/lvl), RANGER (d10, 10+CON HP, +6+CON/lvl), WIZARD (d6, 6+CON HP, +4+CON/lvl), CLERIC (d8, 8+CON HP, +5+CON/lvl). `_hp_per_level()` computes class HP gain per level-up. Status fields: `poison_turns`, `burning_turns`, `bleeding_turns`, `slowed_turns`. `tick_status() -> int` ticks all four and returns total dmg (slowed deals no damage, just decrements). HUD status dots: green=poison, orange=burning, red=bleeding, brown=slowed. Spike Trap: reusable, bleeding 5 turns. Bear Trap: slowed 20 turns (each movement costs 2 turns like mud/water).

**Combat rolls**: attack roll = d20 + STR mod + weapon.bonus_damage vs target `armor_class`. Player AC = 10 + DEX mod + armor item `bonus_ac` (recalculated by `GameState.recalculate_stats()`). Enemy AC = type `"ac"` field + floor/5. Enemy attack roll = d20 + floor/3 vs player AC. **Critical hit**: natural 20 on d20 = auto-hit + 2× damage (both player and enemies).

**Advantage / Disadvantage**: ADV = roll 2d20 take higher; DISADV = roll 2d20 take lower; ADV+DISADV cancel to 1d20. Player gets ADV when attacking a SLEEPING enemy, or an enemy whose `just_crossed_door == true` (set in `enemy.gd._move_step()` when the enemy steps onto a door tile — consumed one-shot by `_has_advantage()`). DISADV on ranged attacks at Chebyshev distance 1 (melee range). ADV surprise attacks show a yellow "!" floating above the enemy. `_fov_prev_turn` / `_fov_this_turn` in `player.gd` are maintained but no longer grant ADV on their own.

**Ranged weapons** (`Item.is_ranged=true`, `Item.range: int`): Short Bow (+1, range 6, DEX, infinite), Crossbow (+3, range 8, DEX, infinite), Throwing Daggers (range 4, DEX, consumable qty 3). `Item.consumes_on_ranged=true` → decrement/unequip on use. Ranged attack uses DISADV at distance 1, otherwise same ADV rules as melee.

**Equipment slots**: `GameState.equipment` dict has keys `"melee"` and `"ranged"` (renamed from `right_hand`/`left_hand`). `GameState.equipped_ranged` property returns ranged slot item. `equip()` routes `is_ranged` items automatically to `"ranged"` slot. Inventory overlay labels them Melee/Ranged and enforces slot type (melee rejects ranged items and vice versa).

**Ranged attack flow**: Shift+click enemy or floor tile → fires ranged weapon if `equipped_ranged` exists and target is in range. LMB on enemy within ranged range+LOS → `_ranged_attack()` (DEX-based, projectile VFX). Shift+click any tile (not just enemies) → `_ranged_attack_tile()` for VFX + ammo consumption without requiring an enemy target. Chase always ends in melee (no auto-ranged-when-chasing). **LOS for ranged**: `has_ranged_los()` in `dungeon_floor.gd` — blocks only WALL/VOID, passes through grass/doors/chasms (more permissive than `has_line_of_sight()`). **Hover indicator**: weapon icon shown above hovered enemy — melee icon normally, ranged icon when Shift held and ranged weapon equipped.

### Item system (`scripts/items/item.gd`)
`Item.Type` enum: `WEAPON=0, ARMOR=1, POTION=2, SCROLL=3, FOOD=4, GOLD=5, KEY=6, TOOL=7`. Key fields: `item_name`, `item_type`, `quantity`, `icon_path`, `heal_amount`, `bonus_damage`, `bonus_ac`, `str_bonus`, `is_ranged: bool`, `range: int`, `consumes_on_ranged: bool`. `get_display_name()` appends `×N` if quantity > 1.

### Hunger system
`GameState.hunger` (0–1000). Thresholds: >600 SATIATED, >200 HUNGRY, else STARVING. Depletes 1/turn. Starvation damage: 1 HP every 10 turns at hunger=0. HP regen disabled while Starving. Eat food: `GameState.use_item(item)` → `restore_hunger(heal_amount)`.

### Trap system (in DungeonFloor)
`_traps: Dictionary` maps `Vector2i → {name, damage, msg, sprite_node, revealed, triggered, is_push, reusable?, push_dir?, wall_pos?}`. Key functions: `trigger_trap(pos)`, `reveal_trap(pos)`, `disarm_trap(pos)`, `search_around(pos) -> int`. Piston traps: only detectable from the push side (`search_around` filters by `-push_dir`). Spike Trap: reusable, applies bleeding 5 turns. Bear Trap: applies slowed 20 turns. Fire Trap: burning 4 turns.

### Door system (in DungeonFloor)
`_doors: Dictionary` maps `Vector2i → {is_open: bool, sprite: Sprite2D}`. Auto-opens when entity steps on tile, auto-closes when entity leaves. Enemies open doors and walk through in same turn. Functions: `has_door_at(pos)`, `is_door_open(pos)`, `open_door(pos)`, `close_door(pos)`.

### Floor items (in DungeonFloor)
`_floor_items: Dictionary`, `_floor_item_sprites: Dictionary`. `place_item_on_floor(pos, item)` creates sprite + registers. `pick_up_item(pos) -> Item` removes. `cook_rotten_meat(trap_pos) -> Item` — erases Fire Trap from `_traps`, plays orange flash tween on its sprite, returns Cooked Meat (heal=150). Only triggers from `_do_throw()` when trap `"revealed"` is true.

### Short rest system
`Alt` key → `player.gd._open_short_rest()` → spawns `scripts/ui/short_rest_panel.gd` (CanvasLayer, layer=25). Panel shows rests remaining, hit dice available, minus/plus picker, heal range preview, Cancel/Rest buttons. Keyboard: ←/A/KP4 = minus, →/D/KP6 = plus, Enter = rest, Esc = close. On Rest: rolls `_dice_to_spend` × class die + CON mod (min 1 per die), calls `GameState.heal()`, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`. All player input blocked while `GameState.short_rest_open == true`. `advance_floor()` resets `hit_dice = character_level` and `short_rests_remaining = 2`. All buttons have `focus_mode = FOCUS_NONE` — keyboard events route to `_unhandled_input`, not button focus.

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
- **New item**: whenever a new item is added to `ITEM_POOL` in `dungeon_floor.gd`, also add a matching entry to `ALL_ITEMS` in `scripts/ui/debug_panel.gd` so it appears in the debug Give Item browser. Mirror all relevant fields (`is_ranged`, `range`, `consumes`, `qty`, etc.) and update `_on_give_item` if new Item fields are introduced.
- **Debug panel** (`scripts/ui/debug_panel.gd`, layer=25, F3): Invincible, Noclip, Jump to Floor, Give Item, See All toggle. See All emits `GameState.debug_see_all(active)` → `_on_debug_see_all()` in DungeonFloor sets `_see_all_active`, updates `_explored` for all non-void tiles (enabling click-to-move), and emits `stairs_discovered`. All debug buttons have `FOCUS_NONE`.
- **Compass** (in `hud.gd`): always visible from floor start showing "?" / "find it". `_stairs_found_this_floor` flag set by `_on_stairs_discovered()`. `_update_compass()` early-returns until flag is true. Emitted from `update_fog()` (after `_apply_see_all()` so See All also triggers it) and from `_on_debug_see_all(true)`.
- **Inventory slots**: in non-Container parents, `custom_minimum_size` does NOT set `size` — hit areas remain zero. Always set `slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)` explicitly. `_finish_drag()` uses `Rect2(slot.position, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(local_mouse)` not `slot.get_rect()`.
- **Click-vs-drag**: player.gd records `_click_start_screen_pos` on LMB press. `InputEventMouseMotion` in `_unhandled_input` cancels `_queued_path` if mouse moves >8 screen px while button held, so drag gestures don't start pathfinding.
- **UI mouse filters**: `LogPanel` and `StatsPanel` in `scenes/ui/hud.tscn` use `MOUSE_FILTER_IGNORE` so clicks on the game world pass through the HUD overlay. Interactive children (Buttons) still receive events normally. Do not set these back to STOP — it blocks click-to-move in the lower half of the screen.
