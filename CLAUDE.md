# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This is an index, not the full reference.** Detailed mechanics live in the sub-directory CLAUDE.md files — follow the pointers below rather than expecting everything here. Keeping this file lean matters: it is loaded into every single conversation turn, unlike the sub-docs, which only get read when work actually touches that area.

## Maintenance rule (applies to all sessions)
After every feature, fix, or refactor that changes architecture, adds a system, or modifies any documented behaviour: **update the relevant sub-directory CLAUDE.md and this root CLAUDE.md without waiting to be asked**. Sub-directory CLAUDE.md files live in `scripts/autoloads/`, `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/dungeon/`, and `scripts/items/`. **Put class-specific / subsystem-specific detail in the sub-directory file, not here** — root should only gain a line or two pointing at it. If you're about to write more than ~3 sentences on one topic, it almost certainly belongs in a sub-doc instead.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. No CLI build commands.

**Controls:** Arrow keys/WASD = move (cardinal). Q/E/Z/C or Numpad diagonals = diagonal move. Space/./Numpad5 = wait (also forfeits Extra Attack). Ctrl = search. Alt = rest (short/long tabs). RMB on world = interact. 1–9 = use active quickbar slot 0–8. **Tab = toggle between item bar and ability bar**. I = open inventory. Left-click enemy = chase+attack (melee). Shift+left-click enemy/tile = ranged attack (if ranged weapon equipped and in range). Left-click floor = pathfind. RMB on food in quickbar = throw mode, then LMB = throw. Esc = cancel throw/tool. **Thief Tools keyboard**: prime via quickbar hotkey → WASD into open/closed door = lock attempt; WASD into locked door = pick/unlock attempt. Note: F key no longer opens doors.

## Architecture

### Singletons (autoloads)
Full signal list, state fields, and API live in **`scripts/autoloads/CLAUDE.md`** — read it before touching `game_state.gd`, `turn_manager.gd`, or `audio_manager.gd`.
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, floor number, player `Stats`, inventory (quickbar 9 slots + bag 24), ability bar (9 slots), equipment, rest state, talent state. Call `GameState.game_log(msg)` for combat log — **never call `log()`** (that's GDScript's built-in float math function).
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input hard-gated on `phase == WAITING_FOR_INPUT`. New entity: `TurnManager.register_enemy(self)` on spawn, `TurnManager.clear_enemies()` before floor reload.
- **`AudioManager`** (`scripts/autoloads/audio_manager.gd`) — drop `.ogg` files into `res://audio/`; missing files silently ignored. `AudioManager.play("name")` for SFX, `AudioManager.play_music(path)` for looping BGM.
- **`SaveManager`** (`scripts/autoloads/save_manager.gd`) — single-slot run save at `user://save/run.json` (atomic write + `.bak` backup, deleted on death/win). Payload still a version-only stub — serialization/Continue flow are later sessions. Details: `scripts/autoloads/CLAUDE.md`, design: `docs/architecture/SAVE_LOAD_ARCHITECTURE.md`.

### Turn flow
1. Player key → `player.gd` calls `TurnManager.begin_player_action()` (phase → RESOLVING_PLAYER)
2. Action completes (after tween) → `TurnManager.on_player_action_complete()`
3. `TurnManager._process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase → WAITING_FOR_INPUT. `player_turn_started` signal fires.

Each turn: status effects tick (`Stats.tick_status()` → dmg). Hunger has been removed — food items are long-rest fuel only (see "Rest system" below).

### Dungeon
- **`DungeonGenerator.generate(seed, floor_num)`** — pure static, returns `DungeonData`. Seed: `run_seed XOR (floor * 0x9e3779b9)`. BSP depth 5, 48×48 grid, L-shaped corridors. Internally a three-phase pipeline (`FloorPlanner` → `BspBuilder` → `LevelPainter`, with `Room` type classes) — details in `scripts/dungeon/CLAUDE.md`.
- **`DungeonData`** — `grid: Array[Array[int]]` indexed `[y][x]`. `TileType`: `VOID=0, FLOOR=1, WALL=2, STAIRS_DOWN=3, CHASM=4, WATER=5, MUD=6, GRASS=7, TRAMPLED_GRASS=8`. `boss_room: Rect2i` (empty if not boss floor). `rooms: Array[Rect2i]` — all BSP leaf rooms. `feeling: String` — Floor Feeling id, `""` on boss floors (see `scripts/dungeon/CLAUDE.md`).
- **`DungeonFloor`** (`scripts/world/dungeon_floor.gd`) — owns TileMapLayer, Entities node, enemy list, fog overlay, traps, doors, floor items. Full query-method list, FOV algorithm, traps, doors, floor items, spawning, water/bottle/throw mechanics, and boss floors: **`scripts/world/CLAUDE.md`**.

### Entity hierarchy
```
Entity (CharacterBody2D)   ← grid_pos, move_to() 0.08s tween, _tile_center(), is_friendly
  ├── Player               ← input, 9-slot quickbar, throw mode, blood trail
  ├── Enemy                ← take_turn(), behavior enum (SLEEPING/STATIONARY/ROAMING/CHASING/SEARCHING)
  └── Companion            ← Wild Heart ally, auto-attacks nearest enemy
```
World position = `pos * TILE_SIZE + TILE_SIZE/2`. `TILE_SIZE = 16`. z-index: floor items=1, enemies=1, player=3, fog=2, damage labels=10; blood decals=0.
Full combat rolls, ADV/DISADV rules, status effects, enemy AI states, and per-class talent trees: **`scripts/entities/CLAUDE.md`**.
Target schema for full D&D-style enemy stat blocks (CR, ability scores, resist/immune/vuln, creature type, size, senses, traits, multiattack, reactions, conditional triggers, legendary resistance) — design only, not yet implemented: `docs/architecture/enemy-stat-block-design.md`.
Opportunity Attacks (movement out of threat range provokes a free reactive melee attack, Retaliation-style inline resolution, no TurnManager changes): **`scripts/entities/CLAUDE.md`**'s "Opportunity Attacks" section (design doc: `docs/architecture/opportunity-attacks-design.md`).

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. `modifier(score)` = `floor((score-10)/2)`. `apply_class_defaults()` sets scores, derives `max_hp`, and calls `recalc_ac(has_armor)`. Classes: BARBARIAN (d12, STR/CON check prof), RANGER (d10, STR/DEX), WIZARD (d6, INT/WIS), MONK (d8, STR/DEX). Barbarian and Monk both get unarmored-defense AC formulas — see `scripts/entities/CLAUDE.md` for the full combat-roll table, proficiency scaling, and class-specific mechanics.

### Ability system
`Ability` (`scripts/items/ability.gd`) — resource with `ability_id`, `ability_name`, `description`, `icon_path`, `uses_remaining`, `uses_max`, `is_active`. `uses_max == 0` means infinite/passive. `GameState.player_ability_bar: Array` holds 9 slots (parallel to `player_quickbar`). `Tab` toggles HUD between item bar and ability bar. `GameState.add_ability(ability)` places in first empty slot. Ability activation dispatched in `player.gd._use_ability_slot(idx)` by `ability_id`. New abilities are granted by `GameState._apply_talent_rank()` and `GameState._apply_monk_level_features(level)`.

### Spellcasting (design only, not yet implemented)
Full D&D 5.5e spellcasting framework — spell data model, spell slots (long-rest/pact-magic/enemy-cooldown behind one interface), prepared vs. known spell lists, upcasting, concentration, BG3-style reactions, and tile-grid AoE targeting (cone/sphere/line/cube). Wizard (already in `Stats.CharacterClass`) is the first integration target. No code ships with the design: `docs/architecture/spellcasting-design.md`.

### Talent system (`scripts/items/talent.gd`, `scripts/autoloads/game_state.gd`)
`Talent` is a reusable Resource: `talent_id`, `talent_name`, `description`, `icon_path`, `tier`, `class_id`, `max_rank`, `ranks: Array[Dictionary]`. `rank_description(rank)` returns the description string for a given rank.

**GameState talent state**: `talent_points_available`, `talent_investments` (talent_id → rank), `_class_talents`, `talent_picker_open` (blocks all input). **Key functions**: `get_talent_rank(id)`, `can_invest_talent(id)`, `invest_talent(id)` → `_apply_talent_rank(id, rank)` (dispatches side effects) → emits `talent_invested`. Long rest is no longer floor descent — see "Rest system" below for where `rage_uses_remaining`/`hit_dice` actually refill. Level-up only grants `+1 talent_points_available`. `hud.gd._on_player_leveled_up()` spawns `talent_picker.gd` when points > 0.

**Rank-gradient icons**: `GameState.TALENT_ICON_FOLDER` maps every Barbarian talent_id to `res://icons/barbarian/<subclass>/<name>_<rank>.png`. `GameState.talent_icon_path(id, rank)` clamps rank to 1–3 and returns the matching file. Every Talent/Ability sets `icon_path` via this helper so both the talent-tree icon and the ability-bar icon "gradate" as ranks are invested.

**Barbarian (Tier 1: Rage/Reckless Attack/Danger Sense; Tier 2 at level 7: Berserker/Zealot/World Tree/Wild Heart, 3 talents each) and Monk full talent/ability tables: `scripts/entities/CLAUDE.md`.**

### Weapon mastery selection ("Mastery Picker")
`Stats.ALL_WEAPON_MASTERIES` (all 8) + `Stats.mastery_cap()` (per-class/level, computed live) back `scripts/ui/mastery_picker.gd`, which populates `Stats.known_weapon_masteries` — the array every weapon-mastery combat effect already gates on. Spawns once right after class selection (`class_select.gd`), and again after any completed long rest if the player opts in (see "Rest system" below). Full design: `docs/architecture/weapon-mastery-selection-design.md`; implementation detail: `scripts/ui/CLAUDE.md`.

### Items and combat
Weapon fields (`damage_die_min/max`, `damage_type`, `weapon_mastery`, `weapon_category`, `is_heavy`, `is_two_handed`, `is_finesse`, `is_light`, `is_reach`, `is_versatile`/`versatile_die_min/max`, `is_thrown`/`uses_max`/`uses_remaining`, `ammo_item_name`), weapon masteries (Cleave, Vex, Push, Graze, Topple, Sap, Nick, Slow), weapon proficiency, ranged weapons/ammo/long-range rules, equipment slots + dual-wielding (Off-hand only accepts a Light weapon when Main Hand is also Light — Handaxe/Dagger — and fires a bonus Off-hand attack per swing, its damage roll dropping the ability modifier unless negative; a Nick-mastery weapon in either hand adds a third, identical bonus attack), the click-to-toggle Versatile grip (Quarterstaff, Spear), Thrown weapons (Spear, Handaxe, Dagger — RMB/LMB throw using the melee attack modifier, durability "uses"), and the full `Item` field table: **`scripts/items/CLAUDE.md`**.
ADV/DISADV house rule, combat roll formulas, damage-stacking rule, and enemy resist checks: **`scripts/entities/CLAUDE.md`**.

### Rest system (short rest / long rest), traps, doors
Hunger has been removed. `Alt` opens a tabbed rest panel (`scripts/ui/short_rest_panel.gd`) — **Short Rest** (default tab, up to 2/long-rest-cycle, spends hit dice) and **Long Rest** (explicit player action, NOT floor descent). Long rest requires sacrificing FOOD items worth `GameState.LONG_REST_FOOD_COST` (100) combined `Item.food_value`, takes `GameState.LONG_REST_TURNS` (20) turns (interruptible by enemies, same mechanism as short rest), fully heals HP, clears status effects, and refills every long-rest-gated resource (hit dice, short rests, Rage uses, Zealot/Wild Heart charges, companion HP) via the single `GameState.long_rest()` chokepoint — see `scripts/autoloads/CLAUDE.md`. On completion the player is asked whether to reselect weapon masteries (re-spawns the Mastery Picker). All player input is blocked while `GameState.short_rest_open == true`. Trap/door/floor-item systems and spawning live on `DungeonFloor` (see `scripts/world/CLAUDE.md`).

## Sprite Assets

- `sprites/characters/` — `{character}_{anim}_f{n}.png`. Characters: `knight_m`, `elf_m`, `wizzard_m`, `dwarf_m`, `orc_warrior`, `masked_orc`, `big_demon`, `necromancer`, etc.
- `sprites/tiles/` — `floor_1.png`, `wall_mid.png` (**not** `wall_top_mid.png`), `floor_stairs.png`.
- `sprites/objects/` — props, flasks, doors, etc.
- `sprites/weapons/` — `weapon_anime_sword.png`, etc.
- `sprites/items/Sprites trial/` — item icons. Constant `ITEMS_PATH` in `dungeon_floor.gd`. Subfolders: `Food/`, `Potions/Health/`, `Potions/Mana/`, `Misc/`.

`SpriteFrames` built in `_setup_animations()` — no `.tres` files needed.

## Git Workflow

After every feature/fix: `git add`, `git commit`, `git push origin HEAD:main`. No need to ask — always commit and push. Use `HEAD:main` (not `main`) — sessions may run in a worktree branch.

**Background/worktree sessions that open a PR**: don't stop at draft. Mark it ready (`gh pr ready <n>`) and squash-merge it into `main` (`gh pr merge <n> --squash --delete-branch`) without waiting to be asked. After merging, pull the user's main working copy so Godot picks up the change: `git -C "C:/Users/Doupo/Desktop/Dragons-in-Dungeons" pull`.

## Key Conventions

- **`GameState.game_log(msg)`** — never `log()` (GDScript built-in math).
- **New enemy**: extend `Entity`, implement `take_turn()`, `_setup_animations()`, register via `TurnManager.register_enemy(self)`. Add `idle_fmt`/`run_fmt` overrides to `DungeonFloorData.ENEMY_POOL` if sprite naming is non-standard. Full steps: `scripts/entities/CLAUDE.md`.
- **New floor tile**: add to `DungeonData.TileType`, add source in `DungeonFloor._setup_tileset()`, handle in `_load_floor()` match block.
- **Fog after every action**: call `_dungeon_floor.update_fog(grid_pos)` before `TurnManager.on_player_action_complete()`.
- **Floor transitions**: `DungeonFloor.on_player_reached_stairs()` → `GameState.advance_floor()` → `_load_floor()`. `_explored` dict and fog reset each `_load_floor()`.
- **UI signals**: HUD connects to `GameState` signals only — never poll `GameState` in `_process()`.
- **GDScript types**: always explicit (`var x: int`, `Array[Enemy]`, `for y: int in n`). Untyped arrays/loops cause parser errors on `:=` expressions.
- **New item**: add to `DungeonFloorData.ITEM_POOL` **and** mirror in `debug_panel.ALL_ITEMS`. Full field-mirroring checklist: `scripts/items/CLAUDE.md`.
- **Invincible mode** (`GameState.invincible`): when true, skip all consumption — potions, tools, ranged ammo, ability uses, and short rest hit dice are never decremented. Every consumption site must guard: `if not GameState.invincible: consume(...)`.
- **`PlayerActions.interact_action(target)`** (`scripts/entities/player_actions.gd`): when `target != Vector2i(-1, -1)` (called from RMB), only check that exact tile for traps/doors — NOT all 8 neighbors.
- **New class-specific starting gear**: add to `GameState.give_class_starting_items()` → `_give_{class}_starting_items()`. Always call `equipment_changed.emit()` at end.
- **New ability**: add to `player_ability_bar` via `GameState.add_ability()`. Dispatch activation in `player.gd._use_ability_slot()` by matching `ability_id`. Sync uses on `advance_floor()` via `_sync_ability_uses()`.
- **Debug panel** (`scripts/ui/debug_panel.gd`, layer=25, F3): God Mode, Jump to Floor, Give Item, Spawn Enemy, Level Up. Full detail: `scripts/ui/CLAUDE.md`.
- **Chat log tooltips**: hover `[url=meta]...[/url]` tags → `hud.gd._format_tooltip(meta)`, formatter bodies in `scripts/ui/tooltip_formatters.gd`. **RULE: every new damage source must get a `[url=kind:key=val,...]` tag on the number AND a matching `fmt_kind_tooltip()` static handler — never log bare damage numbers.**
- **RULE — damage stacking**: when multiple bonus damage sources apply to the same attack, sum them into the base damage **before** calling `Stats.take_damage()`/`DungeonFloor.show_damage()` — one call, one floater, one chat log line. Each source keeps a **named** field in the `dmg` meta string for the tooltip; the visible log line itself never lists per-source names or amounts. See `scripts/entities/CLAUDE.md` for the full rule and `player.gd._bump_attack()`/`PlayerRanged.ranged_attack()` for the reference implementation.
- **RULE — no mechanic names in enemy attack log lines**: `enemy.gd._attack_player()` never names a specific player talent/ability in the log text — that context lives only in the `ehit` tooltip.
- **UI conventions** (mouse filters, focus mode, slot sizing, drag-hit detection, TextureRect icon sizing, click-vs-drag, quickbar/inventory tooltips, keyword glossary, compass): all in **`scripts/ui/CLAUDE.md`** — read it before touching any HUD/overlay script, several of its rules are non-obvious footguns.
