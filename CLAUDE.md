# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

## Maintenance rule (applies to all sessions)
After every feature, fix, or refactor that changes architecture, adds a system, or modifies any documented behaviour: **update the relevant sub-directory CLAUDE.md and this root CLAUDE.md without waiting to be asked**. Sub-directory CLAUDE.md files live in `scripts/autoloads/`, `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/dungeon/`, and `scripts/items/`.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. No CLI build commands.

**Controls:** Arrow keys/WASD = move (cardinal). Q/E/Z/C or Numpad diagonals = diagonal move. Space/./Numpad5 = wait. Ctrl = search. Alt = short rest. RMB on world = interact. 1–9 = use active quickbar slot 0–8. **Tab = toggle between item bar and ability bar**. I = open inventory. Left-click enemy = chase+attack (melee). Shift+left-click enemy/tile = ranged attack (if ranged weapon equipped and in range). Left-click floor = pathfind. RMB on food in quickbar = throw mode, then LMB = throw. Esc = cancel throw. Note: F key no longer opens doors.

## Architecture

### Singletons (autoloads)
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, floor number, player `Stats`, inventory (quickbar 9 slots + bag 24 slots), **ability bar (9 slots, `player_ability_bar`)**, equipment, hunger, short rest state. Key signals: `floor_changed`, `player_hp_changed`, `player_exp_changed`, `player_leveled_up`, `player_died`, `player_won`, `combat_message`, `inventory_changed`, `equipment_changed`, `ability_bar_changed`, `equip_action_taken`, `hunger_changed`, `player_status_changed`, `player_throw_primed(item)`, `class_chosen`, `player_action_requested(action_name)`, `short_rest_changed`, `stairs_discovered`, `debug_see_all(active: bool)`, `crit_banner(text, color)`, `screen_shake(strength)`. Short rest fields: `hit_dice` (available, refills to `character_level` on `advance_floor()`), `short_rests_remaining` (2/floor), `short_rest_open: bool` (blocks all player input while panel is open). `hit_die_sides() -> int` returns class die (Barbarian 12, Ranger 10, Cleric 8, Wizard 6). `is_raging: bool` — set by player.gd; read by `take_damage_raw()` to halve damage. `equip(item, slot, costs_turn)` / `unequip(slot, costs_turn)` — pass `costs_turn=true` for intentional player equips; emits `equip_action_taken`. `give_class_starting_items()` — called by `class_select.gd` after class pick; gives class weapons + ability bar entries. Call `GameState.game_log(msg)` for combat log — **never call `log()`** (that's GDScript's built-in float math function).
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input hard-gated on `phase == WAITING_FOR_INPUT`. New entity: `TurnManager.register_enemy(self)` on spawn, `TurnManager.clear_enemies()` before floor reload.
- **`AudioManager`** (`scripts/autoloads/audio_manager.gd`) — drop `.ogg` files into `res://audio/`; missing files silently ignored. `AudioManager.play("name")` for SFX, `AudioManager.play_music("res://audio/music_dungeon.ogg")` for looping BGM. Enable Loop in Godot import settings for music files. SFX names: `hit_enemy, miss_enemy, crit, crit_fail, player_hurt, player_die, kill_enemy, shoot, open_door, close_door, lock_door, step_grass/mud/water/floor, trap_fire/spike/piston/bear, eat_food, drink_potion, lockpick, hungry, starving, cook_meat, throw_item, bottle_fill`.

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
**Enemy roaming**: ROAMING enemies use waypoint navigation. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks one at Chebyshev distance ≥4 that `is_walkable_for_enemy`. `_do_roam_walk()` follows a cached `_roam_path: Array[Vector2i]` (BFS via `_bfs_to()`); on arrival or blocked path picks a new target; falls back to `_do_random_step()`. `_roam_path`/`_roam_target` are cleared when switching to/from CHASING. **Enemy search**: when CHASING enemy reaches `last_known_player_pos` without regaining LOS → enters SEARCHING for 7 turns. Walks in recorded `_search_heading` direction (BFS to `_search_target = last_known_pos + heading * 5`). If player spotted → CHASING. After 7 turns → ROAMING. Fields: `_search_heading`, `_search_turns_remaining`, `_search_target`, `_search_path`.
World position = `pos * TILE_SIZE + TILE_SIZE/2`. `TILE_SIZE = 16`. z-index: floor items=1, enemies=1, player=3, fog=2, damage labels=10. Blood decals: z=0.

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. `modifier(score)` = `floor((score-10)/2)`. `apply_class_defaults()` sets scores, derives `max_hp`, and calls `recalc_ac(has_armor)`. `proficiency_bonus` is now a **computed property** that scales per D&D 5e (+2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.). Classes: BARBARIAN (d12, 12+CON HP, +7+CON/lvl, STR/CON save proficiency), RANGER (d10, 10+CON HP, STR/DEX), WIZARD (d6, 6+CON HP, INT/WIS), CLERIC (d8, 8+CON HP, WIS/CHA). Save proficiency flags: `save_prof_str/con/dex/int/wis/cha` (currently informational; TODO wire into saves when saving throw system is built). **Barbarian unarmored defense**: `recalc_ac(has_armor_equipped)` — if BARBARIAN and no armor, AC = 10 + DEX + CON instead of 10 + DEX. `rage_uses_remaining / rage_uses_max` on Stats (2/2 for Barbarian, reset on `advance_floor`). Status fields: `poison_turns`, `burning_turns`, `bleeding_turns`, `slowed_turns`. `tick_status() -> int` ticks all four and returns total dmg (slowed deals no damage, just decrements). HUD status dots: green=poison, orange=burning, red=bleeding, brown=slowed, **crimson=raging**. Spike Trap: reusable, bleeding 5 turns. Bear Trap: slowed 20 turns.

**Combat rolls**: attack roll = d20 + STR mod + **proficiency_bonus** + weapon.bonus_damage vs target `armor_class`. Ranged: DEX mod + proficiency + weapon bonus. Player AC = `recalc_ac()` result + armor `bonus_ac`. Enemy AC = type `"ac"` + type `"armor"` + floor/5. Enemy attack roll = d20 + floor/3 vs player AC. **Critical hit (nat 20)**: auto-hit + 2× damage + gold "CRITICAL HIT!" overlay + screen shake. **Fumble (nat 1)**: always miss + red "CRITICAL FAIL!" overlay + mild shake. `Stats.take_damage(dmg)` = `maxi(1, dmg)` — no DR; `stats.armor` is always 0 (the pool `"armor"` field is folded into `armor_class`).

### Ability system
`Ability` (`scripts/items/ability.gd`) — resource with `ability_id: String`, `ability_name`, `description`, `icon_path`, `uses_remaining`, `uses_max`. `GameState.player_ability_bar: Array` holds 9 slots (parallel to `player_quickbar`). `Tab` toggles HUD between item bar and ability bar. `GameState.add_ability(ability)` places in first empty slot. `_sync_ability_uses()` in `advance_floor()` refills class ability uses. Ability activation is dispatched in `player.gd._use_ability_slot(idx)` by `ability_id`.

### Barbarian class
Starting equipment (given in `GameState.give_class_starting_items()` after class selection):
- **Greataxe** — 1d12 Slashing, `is_two_handed=true`. `damage_die_min/max` on Item define dice; `recalculate_stats()` applies them. Two-handed blocks the ranged slot; equipping ranged while two-handed is blocked.
- **Rage** — ability in slot 0. 2 uses/long rest (resets on floor descent). Activation costs 1 turn. Effects while active: `GameState.is_raging=true` → all incoming damage halved (TODO: restrict to BPS types once damage types added); +2 damage on STR-based melee attacks; red sprite tint. Duration: starts at 0 extra turns; attacking with STR melee adds +1 turn each time. Rage ends if heavy armor equipped (`item.is_heavy_armor`). TODO: also extend via bonus action and forcing enemy saves.

### Item fields (new)
`Item.is_two_handed: bool` — blocks ranged slot while equipped in melee.
`Item.is_heavy_armor: bool` — ends Barbarian Rage on equip.
`Item.damage_die_min / damage_die_max: int` — weapon-specific damage dice; override base stats when > 0.
`Item.damage_type: String` — "Slashing", "Piercing", "Bludgeoning", or "" (unknown). Shown in attack chat log.
`Item.heal_dice_count / heal_dice_sides: int` — if > 0, `use_item()` rolls N×d(sides) + CON mod instead of flat `heal_amount`. Health Potion uses 2d4+CON.

**Advantage / Disadvantage**: ADV = roll 2d20 take higher; DISADV = roll 2d20 take lower; ADV+DISADV cancel to 1d20. Player gets ADV when attacking a SLEEPING enemy, or an enemy whose `just_crossed_door == true` (set in `enemy.gd._move_step()` when the enemy steps onto a door tile — consumed one-shot by `_has_advantage()`). DISADV on ranged attacks at Chebyshev distance 1 (melee range). ADV surprise attacks show a yellow "!" floating above the enemy. `_fov_prev_turn` / `_fov_this_turn` in `player.gd` are maintained but no longer grant ADV on their own.

**Ranged weapons** (`Item.is_ranged=true`, `Item.range: int`): Short Bow (+1, range 6, DEX, infinite), Crossbow (+3, range 8, DEX, infinite), Throwing Daggers (range 4, DEX, consumable qty 3). `Item.consumes_on_ranged=true` → decrement/unequip on use. Ranged attack uses DISADV at distance 1, otherwise same ADV rules as melee.

**Equipment slots**: `GameState.equipment` dict has keys `"melee"` and `"ranged"` (renamed from `right_hand`/`left_hand`). `GameState.equipped_ranged` property returns ranged slot item. `equip()` routes `is_ranged` items automatically to `"ranged"` slot. Inventory overlay labels them Melee/Ranged and enforces slot type (melee rejects ranged items and vice versa).

**Ranged attack flow**: Shift+click enemy or floor tile → fires ranged weapon if `equipped_ranged` exists and target is in range. LMB on enemy within ranged range+LOS → `_ranged_attack()` (DEX-based, projectile VFX). Shift+click any tile (not just enemies) → `_ranged_attack_tile()` for VFX + ammo consumption without requiring an enemy target. Chase always ends in melee (no auto-ranged-when-chasing). **LOS for ranged**: `has_ranged_los()` in `dungeon_floor.gd` — blocks only WALL/VOID, passes through grass/doors/chasms (more permissive than `has_line_of_sight()`). **Hover indicator**: weapon icon shown above hovered enemy — melee icon normally, ranged icon when Shift held and ranged weapon equipped.

### Item system (`scripts/items/item.gd`)
`Item.Type` enum: `WEAPON=0, ARMOR=1, POTION=2, SCROLL=3, FOOD=4, GOLD=5, KEY=6, TOOL=7`. Key fields: `item_name`, `item_type`, `quantity`, `icon_path`, `heal_amount`, `bonus_damage`, `bonus_ac`, `str_bonus`, `is_ranged: bool`, `range: int`, `consumes_on_ranged: bool`. `get_display_name()` appends `×N` if quantity > 1.

### Hunger system
`GameState.hunger` (0–1000). Thresholds: >600 SATIATED, >200 HUNGRY, else STARVING. Depletes 1/turn. Starvation damage: 1 HP every 10 turns at hunger=0. HP regen disabled while Starving. Eat food: `GameState.use_item(item)` → `restore_hunger(heal_amount)`.

### Water terrain
`TileType.WATER` (=5) is fully rendered and implemented. Stepping into water: costs 2 turns (difficult terrain, same as mud) AND extinguishes burning (`burning_turns = 0`, logged in cyan). Both `_try_move()` and `_execute_queued_path()` handle this.

### Empty bottle mechanic
Drinking any POTION adds an `Empty Bottle` (TOOL type, `sprites/items/Materials/BottleSmall.png`) to inventory via `potion_drunk` signal → `GameState.add_item()`. **Fill is manual**: use the bottle from quickbar/inventory (enters tool mode via `player_tool_primed`), then RMB on an adjacent WATER tile → `Bottle of Water` (TOOL, BottleMedium sprite); adjacent MUD → `Bottle of Mud` (TOOL, BottleSmall sprite). Neither restores hunger. Fill costs 1 turn. `_try_fill_bottle(bottle, target)` in `player.gd` checks adjacency and tile type.

### Trap system (in DungeonFloor)
`_traps: Dictionary` maps `Vector2i → {name, damage, msg, sprite_node, revealed, triggered, is_push, reusable?, push_dir?, wall_pos?}`. Key functions: `trigger_trap(pos)`, `reveal_trap(pos)`, `disarm_trap(pos)`, `search_around(pos) -> int`. Piston traps: only detectable from the push side (`search_around` filters by `-push_dir`). Spike Trap: reusable, applies bleeding 5 turns. Bear Trap: applies slowed 20 turns. Fire Trap: burning 4 turns.

### Door system (in DungeonFloor)
`_doors: Dictionary` maps `Vector2i → {is_open: bool, locked: bool, sprite: Sprite2D, tex_open, tex_closed, lock_icon?: Sprite2D}`. Auto-opens when entity steps on tile, auto-closes when entity leaves. Enemies open doors and walk through in same turn. **Locked doors**: enemies cannot open (blocked by `is_walkable_for_enemy` + `open_door` guard); player auto-unlocks by walking through (free action). Purple sprite tint + small key icon = locked. `_spawn_locked_doors()` pre-locks 1 door per floor at generation time (only if it doesn't block spawn→stairs path; BFS validated) and places 2–3 reward items in the room behind it. F key on closed+unlocked door with Thief Tools → `_attempt_lock_door()` (DC 10 DEX); fail consumes tools. F key on locked door → unlock+open (action). `lock_door()` / `unlock_door()` manage the icon automatically. Functions: `has_door_at`, `is_door_open`, `is_door_locked`, `open_door`, `close_door`, `lock_door`, `unlock_door`.

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
- **New item**: whenever a new item is added to `ITEM_POOL` in `dungeon_floor.gd`, also add a matching entry to `ALL_ITEMS` in `scripts/ui/debug_panel.gd` so it appears in the debug Give Item browser. Mirror all relevant fields (`is_ranged`, `range`, `consumes`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.) and update `_on_give_item` if new Item fields are introduced.
- **Invincible mode** (`GameState.invincible`): when true, skip all consumption — potions, tools, ranged ammo, ability uses, and short rest hit dice are never decremented. Every consumption site must guard: `if not GameState.invincible: consume(...)`. Short rest in `short_rest_panel.gd` also guards hit dice decrement.
- **`_interact_action(target)`**: when `target != Vector2i(-1, -1)` (called from RMB), only check that exact tile for traps/doors — NOT all 8 neighbors. This prevents Thief Tools RMB on a door from being hijacked by a revealed trap that happens to be adjacent.
- **New class-specific starting gear**: add to `GameState.give_class_starting_items()` → `_give_{class}_starting_items()`. Always call `equipment_changed.emit()` at end. For weapons with custom dice, set `item.damage_die_min/max` instead of patching `player_stats.base_min/max_damage`. For abilities, create an `Ability` resource and call `GameState.add_ability(ability)`.
- **New ability**: add to `player_ability_bar` via `GameState.add_ability()`. Dispatch activation in `player.gd._use_ability_slot()` by matching `ability_id`. Sync uses on `advance_floor()` via `_sync_ability_uses()`.
- **Debug panel** (`scripts/ui/debug_panel.gd`, layer=25, F3): **God Mode** checkbox (sets `GameState.god_mode`, syncs Invincible + Noclip + See All; exposes enemy rolls/AC inline in chat log, enemy HP after hits, full stat dump on inspect), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel of all ENEMY_POOL + BOSS_POOL; calls `dungeon_floor.debug_spawn_enemy()` → spawns adjacent to player in CHASING state; DungeonFloor is in group `"dungeon_floor"` for lookup), **Level Up** (`GameState.debug_level_up()`), See All. See All emits `GameState.debug_see_all(active)` → `_on_debug_see_all()` in DungeonFloor. All debug buttons have `FOCUS_NONE`.
- **Chat log tooltips** (`hud.gd`): hover `[url=meta]...[/url]` tags → `_format_tooltip(meta)`. Supported prefixes: `hit`/`miss` (player melee), `rhit`/`rmiss` (ranged), `dmg` (player damage), `ehit`/`edmg` (enemy attack hit/damage), `save`/`check`. ADV/DISADV hits show `d1` vs `d2` dice with which was taken. Damage log appends `[color=gray]Type[/color]` after the number (Slashing/Piercing/Bludgeoning). Enemy attack log uses `ehit:`/`edmg:` meta with d20 roll + attack_bonus.
- **Quickbar/inventory hover tooltips**: `hud.gd` has `_qbar_tooltip` Panel (follows mouse); `inventory_overlay.gd` has `_inv_tooltip` Panel. Both show item name, weapon die + damage_type, heal dice, and description. Quickbar tooltip also handles ability bar mode (shows ability name + description).
- **Compass** (in `hud.gd`): hidden at floor start. Appears at **top-center** only when stairs enter FOV — `_on_stairs_discovered()` sets `_stairs_found_this_floor = true` and shows panel. Hides again on floor change. `_update_compass()` early-returns until flag is true. Emitted from `update_fog()` and from `_on_debug_see_all(true)`.
- **Inventory slots**: in non-Container parents, `custom_minimum_size` does NOT set `size` — hit areas remain zero. Always set `slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)` explicitly. `_finish_drag()` uses `Rect2(slot.position, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(local_mouse)` not `slot.get_rect()`.
- **Click-vs-drag**: player.gd records `_click_start_screen_pos` on LMB press. `InputEventMouseMotion` in `_unhandled_input` cancels `_queued_path` if mouse moves >8 screen px while button held, so drag gestures don't start pathfinding.
- **UI mouse filters**: `LogPanel` and `StatsPanel` in `scenes/ui/hud.tscn` use `MOUSE_FILTER_IGNORE` so clicks on the game world pass through the HUD overlay. Interactive children (Buttons) still receive events normally. Do not set these back to STOP — it blocks click-to-move in the lower half of the screen.
