# CLAUDE.md

This file provides guidance to Claude Code (claude.ai/code) when working with code in this repository.

**This is an index, not the full reference.** Detailed mechanics live in the sub-directory CLAUDE.md files — follow the pointers below rather than expecting everything here. Keeping this file lean matters: it is loaded into every single conversation turn, unlike the sub-docs, which only get read when work actually touches that area.

## Maintenance rule (applies to all sessions)
After every feature, fix, or refactor that changes architecture, adds a system, or modifies any documented behaviour: **update the relevant sub-directory CLAUDE.md and this root CLAUDE.md without waiting to be asked**. Sub-directory CLAUDE.md files live in `scripts/autoloads/`, `scripts/entities/`, `scripts/world/`, `scripts/ui/`, `scripts/dungeon/`, and `scripts/items/`. **Put class-specific / subsystem-specific detail in the sub-directory file, not here** — root should only gain a line or two pointing at it. If you're about to write more than ~3 sentences on one topic, it almost certainly belongs in a sub-doc instead.

**Doc-cleanup habit (part of the same rule, not a separate ask):** once a `docs/architecture/*.md` design doc's scope has fully shipped AND the relevant sub-directory CLAUDE.md documents it in full, **delete the design doc** in that same pass — don't wait to be asked, don't leave it "for the record". A shipped design doc that still exists on disk is signal-to-noise debt: the sub-doc is what an agent actually reads, so a lingering design doc's status header silently rots (see `enemy-stat-block-design.md`'s history before this rule for what that looked like). Before deleting, grep the repo for the filename and fix any CLAUDE.md line that points at it as a "read this" pointer — reword to "implemented; design doc shipped and was deleted, `X/CLAUDE.md` is now authoritative" (the existing precedent for `opportunity-attacks-design.md`, already gone this way). Stray citations inside `.gd` comments (`"per docs/architecture/foo.md §3"`) are fine to leave as historical citations — not worth a mass edit. **Keep** a design doc if any real scope in it is still unbuilt (partial implementation, e.g. `special-rooms-economy-design.md`'s sessions 7c-7f, or `ENEMY_SYSTEM_ARCHITECTURE.md`'s boss phases) — annotate its top with an implementation-status line instead of deleting, same pattern as those two files.

## Project

**Dragons in Dungeons** — a 2D pixel roguelike built in Godot 4 (GDScript only, Mono build). Pixel Dungeon gameplay loop crossed with D&D 5.5e (2024) mechanics: ability scores, classes, spells. Sprites from 0x72 DungeonTilesetII (CC0, 16×16 px).

## Running the Game

Open `project.godot` in **Godot 4.6 (Mono build)**. Press **F5** to run. No CLI build commands.

**Controls:** Arrow keys/WASD = move (cardinal). Q/E/Z/C or Numpad diagonals = diagonal move. Space/./Numpad5 = wait (also forfeits Extra Attack). Alt = rest (short/long tabs). RMB on world (no tool primed) = instant Inspect on the clicked tile/enemy; a quick second RMB (within 0.5s) instead performs a full-area Search. 1–9 = use active quickbar slot 0–8. **Tab = toggle between item bar and ability bar**. I = open inventory. **R = open Wizard Spellbook** (choose prepared leveled spells; no-op for non-casters). Left-click enemy = chase+attack (melee). Shift+left-click enemy/tile = ranged attack (if ranged weapon equipped and in range). Ctrl+left-click enemy/tile = cast whichever spell is in the Special quick-cast slot (if one is assigned — see Spellbook overlay). Left-click floor = pathfind. RMB on food in quickbar = throw mode, then LMB = throw. Esc = cancel throw/tool. **Thief Tools keyboard**: prime via quickbar hotkey → WASD into open/closed door = lock attempt; WASD into locked door = pick/unlock attempt; RMB while primed also completes the same action without moving. Note: F key no longer opens doors.

## Architecture

### Singletons (autoloads)
Full signal list, state fields, and API live in **`scripts/autoloads/CLAUDE.md`** — read it before touching `game_state.gd`, `turn_manager.gd`, or `audio_manager.gd`.
- **`GameState`** (`scripts/autoloads/game_state.gd`) — run seed, floor number, player `Stats`, inventory (quickbar 9 slots + bag 24), ability bar (9 slots), equipment, rest state, talent state. Call `GameState.game_log(msg)` for combat log — **never call `log()`** (that's GDScript's built-in float math function).
- **`TurnManager`** (`scripts/autoloads/turn_manager.gd`) — phase state machine: `WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT`. Player input hard-gated on `phase == WAITING_FOR_INPUT`. New entity: `TurnManager.register_enemy(self)` on spawn, `TurnManager.clear_enemies()` before floor reload.
- **`AudioManager`** (`scripts/autoloads/audio_manager.gd`) — drop `.ogg` files into `res://audio/`; missing files silently ignored. `AudioManager.play("name")` for SFX, `AudioManager.play_music(path)` for looping BGM.
- **`Rng`** (`scripts/autoloads/rng.gd`) — seeded gameplay RNG service (same run seed → same rolls). **RULE: all gameplay-affecting randomness (`Rng.roll/range_i/chance/pick/shuffle`) goes through it — never global `randi_range`/`randf`/`Array.shuffle()`. Cosmetic jitter stays global.** Floor population uses `DungeonFloor._pop_rng` instead. Full API + save-state rules: `scripts/autoloads/CLAUDE.md`.
- **`SaveManager`** (`scripts/autoloads/save_manager.gd`) — single-slot run save at `user://save/run.json` (atomic write + `.bak` backup, deleted on death/win). **Phase A complete (3a+3b+3c)**: full serialization (`GameState.to_dict()/from_dict()`, abilities rebuilt via talent replay), floor-entry checkpoint + close/pause lifecycle autosave, and a "Continue Saved Run" button on the character-select screen (`DungeonFloor.reload_from_save()` regenerates the saved floor from the seed — mid-floor state is Phase B). Details: `scripts/autoloads/CLAUDE.md`, design: `docs/architecture/SAVE_LOAD_ARCHITECTURE.md`.

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
- **Multi-entrance connectivity** — Entrance/Exit rooms are guaranteed ≥2 distinct corridor connections (Pixel Dungeon-style multi-path floors): `Room.min_connections()` + `LoopBuilder`'s forced-edge pass (hard guarantee) and `BspBuilder.reinforce_min_degree()` (best-effort fallback-path reinforcement). Fully implemented — the design doc (`multi-entrance-level-design.md`) was deleted from `docs/architecture/` once shipped; `scripts/dungeon/CLAUDE.md` is now the authoritative reference.
- Special rooms (Shop/Treasure/Garden/Secret, left as placeholder-fallback stubs by the dungeon-generation doc) plus a gold currency to make a shop meaningful — full data model, `ROOM_POOL` mechanism, and session-sized implementation sequence: `docs/architecture/special-rooms-economy-design.md`. **Gold economy core (session 7a) is implemented**: `GameState.gold` wallet + `gold_changed` signal, `Item.gold_value` prices, floor-scatter/enemy-drop/boss gold piles, HUD counter, saved in `to_dict()` — see `scripts/autoloads/CLAUDE.md` and `scripts/world/CLAUDE.md`. **ROOM_POOL + metadata bridge (session 7b) is implemented**: `FloorPlanner.ROOM_POOL` Bernoulli selection, four room classes, `DungeonData.room_metadata`, `DungeonFloor._spawn_special_rooms()` dispatcher — see `scripts/dungeon/CLAUDE.md` and `scripts/world/CLAUDE.md`. **TreasureRoom (session 7c) and GardenRoom (session 7d) are implemented**: TreasureRoom guards 3 guaranteed items + a gold pile behind a locked door (plus floor ≥4 traps) via `DungeonFloor._spawn_treasure()`; GardenRoom paints a grass/water interior at generation time (`GardenRoom.paint()`) and drops 1-2 Healing Herb items via `_spawn_garden_items()` — see `scripts/dungeon/CLAUDE.md` and `scripts/world/CLAUDE.md`. Sessions 7e–7f (ShopRoom + shop UI, SecretRoom + hidden doors) remain design-only.

### Entity hierarchy
```
Entity (CharacterBody2D)   ← grid_pos, move_to() 0.08s tween, _tile_center(), is_friendly
  ├── Player               ← input, 9-slot quickbar, throw mode, blood trail
  ├── Enemy                ← take_turn(), behavior enum (SLEEPING/STATIONARY/ROAMING/CHASING/SEARCHING)
  └── Companion            ← Wild Heart ally, auto-attacks nearest enemy
```
World position = `pos * TILE_SIZE + TILE_SIZE/2`. `TILE_SIZE = 16`. z-index: floor items=1, enemies=1, player=3, fog=2, damage labels=10; blood decals=0.
Full combat rolls, ADV/DISADV rules, status effects, enemy AI states, and per-class talent trees: **`scripts/entities/CLAUDE.md`**.
Full D&D-style enemy stat-block schema — CR, ability-score `mods`/proficiency, damage resist/immune/vuln (3 lists), condition immunities, creature type, senses, multiattack, ability cooldown/uses_max/recharge, regeneration/undead-fortitude traits, legendary resistance — is **implemented** as optional `ENEMY_POOL`/`BOSS_POOL` pool keys (every new key has a safe legacy-behavior default, so authoring a new enemy is "add a dict"). Design doc (source of the schema, still useful as the field-by-field reference): `docs/architecture/enemy-stat-block-design.md`. Still design-only/deferred: size (multi-tile occupancy), reactions beyond Opportunity Attacks, conditional triggers, legendary actions, CR-budgeted spawning. Full field table and worked examples: `scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema" section.
Opportunity Attacks (movement out of threat range provokes a free reactive melee attack, Retaliation-style inline resolution, no TurnManager changes): **`scripts/entities/CLAUDE.md`**'s "Opportunity Attacks" section.
Stealth & Surprise Attacks (5e-style Stealth-vs-Passive-Perception check deciding whether a SLEEPING/STATIONARY/ROAMING enemy notices the player, rolled once per real player turn; corrected surprise-ADV trigger table; debug-only "Show Stealth Checks" reveal toggle): **`scripts/entities/CLAUDE.md`**'s "Stealth & Surprise Attacks" section.

### D&D stats (`scripts/entities/stats.gd`)
`Stats` extends `Resource`. `modifier(score)` = `floor((score-10)/2)`. `apply_class_defaults()` sets scores, derives `max_hp`, and calls `recalc_ac(has_armor)`. Classes: BARBARIAN (d12, STR/CON check prof), RANGER (d10, STR/DEX), WIZARD (d6, INT/WIS), MONK (d8, STR/DEX). Barbarian and Monk both get unarmored-defense AC formulas — see `scripts/entities/CLAUDE.md` for the full combat-roll table, proficiency scaling, and class-specific mechanics.

### Character select
The very first screen of a new run is `scripts/ui/character_select.gd` (`hud.gd` spawns it, not
`class_select.gd` directly): 5 side-by-side cards — 4 premade heroes (fixed class+race+weapon
masteries, click drops straight into the already-loaded floor 1, bypassing every picker below)
and a "Custom" card that hands off unchanged to the class/race/mastery flow. Also owns the
"Continue Saved Run" button. Full detail: `scripts/ui/CLAUDE.md`'s "Character select" section.

### Point buy (ability score allocation)
Custom-path onboarding order: **class select → point buy → race select → mastery picker → game
starts**. `point_buy_select.gd` is a one-time blocking overlay spawned right after class
selection, before race select (premade heroes bypass it entirely). D&D 2024 point-buy: all six
scores start at 8, `-`/`+` per score within 8–15, 27-point budget, 14/15 cost 2 points/step
(others 1) — matches the standard 5e point-buy cost table exactly. No racial ability-score
bonuses (race select runs after and never touches base scores). `Stats.apply_point_buy_scores()`
(`scripts/entities/stats.gd`) applies the result and re-derives HP/AC; UI is
`scripts/ui/point_buy_select.gd` (`scripts/ui/CLAUDE.md`).

### Race system
Onboarding order (Custom path): **class select → point buy → race select → mastery picker → game
starts**. `race_select.gd` is a one-time blocking overlay spawned right after point buy confirms
(mirrors `subclass_select.gd`'s pattern), and itself spawns the Mastery Picker on confirm. 6 races (Orc, Human, Halfling, Dwarf,
Elf w/ 3 sub-races, Dragonborn) each with distinct traits — darkvision/FOV bonus, long-rest-gated
charges (Orc Relentless Endurance, Human Heroic Inspiration), a d20-reroll mechanic (Human
miss-reroll — still stubbed; Halfling nat-1-reroll — implemented, see below), Dwarf +1 HP/level
(including level 1), Elf shorter rests + sub-race spell-like ability, Dragonborn ancestry-based
resistance/breath type. Still deferred/stubbed: Human miss-reroll, Elf sub-race spell-like
ability, Dragonborn breath weapon — these are cosmetic/flavor gaps, not blockers.
**Halfling Lucky**: rolling a natural 1 on any player d20 roll (attack roll or the trap-disarm
check) triggers an automatic, must-use reroll — `CombatMath.halfling_reroll(die)`
(`scripts/entities/combat_math.gd`), baked into `CombatMath.roll_with_adv_disadv()` (the shared
roll used by all 6 player attack sites) so every attack gets it for free; `player_thief_tools.gd`'s
`attempt_disarm()` calls it directly. The chat log line wraps in dark green with a ☘ marker
(`CombatMath.wrap_halfling_luck()`) and the hover tooltip shows a struck-through "1 → N" line
(`fmt_hit_tooltip()`/`fmt_save_tooltip()` in `scripts/ui/tooltip_formatters.gd`) whenever it fires.
`Stats.apply_race_defaults()`
(`scripts/entities/stats.gd`) and `GameState.choose_race()`/`give_race_starting_items()`
(`scripts/autoloads/CLAUDE.md`) hold the mechanical hooks; UI is `scripts/ui/race_select.gd`
(`scripts/ui/CLAUDE.md`).

### Ability system
`Ability` (`scripts/items/ability.gd`) — resource with `ability_id`, `ability_name`, `description`, `icon_path`, `uses_remaining`, `uses_max`, `is_active`. `uses_max == 0` means infinite/passive. `GameState.player_ability_bar: Array` holds 9 slots (parallel to `player_quickbar`). `Tab` toggles HUD between item bar and ability bar. `GameState.add_ability(ability)` places in first empty slot. Ability activation dispatched in `player.gd._use_ability_slot(idx)` by `ability_id`. New abilities are granted by `GameState._apply_talent_rank()` and `GameState._apply_monk_level_features(level)`.

### Spellcasting
**Wizard cantrips** (free, at-will — 8 total: the original attack-roll trio Fire Bolt / Ray of
Frost / Shocking Grasp, plus 5 more adding SAVE-resolution and SELF-target/AoE cantrips —
Toll the Dead, Blade Ward (the one cantrip with a real, minimal Concentration mechanic), Thunderclap,
Mind Sliver, Light (a real FOV light source, not cosmetic) — picked via **two** "pick 1 of 3"
rounds right after race select via `scripts/ui/cantrip_select.gd`) **and leveled spells
with real D&D 2024 spell slots are both implemented.** Leveled spells: `StandardSlotPool`'s
1–20 full-caster slot table (long-rest-only recharge), prepared count = character level, a
level-up "pick 1 of 3" spellbook-growth picker (`scripts/ui/spell_learn_picker.gd`), scroll-taught
spells, and an **R-key Spellbook overlay** (`scripts/ui/spellbook_overlay.gd`) — level tabs,
hover description, click-to-prepare, drag-and-drop onto a specific ability-bar slot, bottom-right
"X / Y prepared" counter. 11 leveled spells (Magic Missile, Shield, Mage Armor, Misty Step, Fireball,
Chromatic Orb, Burning Hands, Witch Bolt — the last 3 add a leveled ATTACK_ROLL path with a
one-shot leap-on-doubles mechanic, a directional cone AoE shape, and a second Concentration DoT
effect alongside Blade Ward, respectively — plus Expeditious Retreat, False Life, Fog Cloud: a
third/fourth Concentration effect (a free-move-once-per-turn buff and a Blinded status zone
readable by both player- and enemy-side attack rolls) and a flat Temp HP grant). Full
Concentration support for Blade Ward/Witch Bolt/Expeditious Retreat/Fog Cloud (one slot,
`Stats.concentration_spell_id`), no reactions, no line/cube AoE (sphere + cone
only), no upcast slot-level picker (always casts at the cheapest available slot) — see
`scripts/entities/CLAUDE.md`'s "Wizard leveled spells (spell slots)" section, `scripts/items/CLAUDE.md`'s spellcasting-data section, and
`scripts/ui/CLAUDE.md`'s Spellbook/spell-learn-picker sections for the full implementation.
Design doc: `docs/architecture/spellcasting-design.md` (the original full-framework design —
concentration/reactions/enemy-casters/half-casters/multiclass remain design-only per that doc).
The narrower leveled-spells-and-slots plan that was actually implemented (superseding the
framework doc's prepared-count formula and casting-surface UI for Wizard) shipped and its
design doc was deleted from `docs/architecture/` — `scripts/entities/CLAUDE.md`'s "Wizard
leveled spells" section is now the authoritative reference. The Spellbook overlay also has an always-present Cantrips tab and a **Special quick-cast
slot** (assigned there, one spell — cantrip or leveled — cast from anywhere with **Ctrl+click**,
displayed read-only in the Inventory overlay next to Ranged) — see `scripts/ui/CLAUDE.md`'s
Spellbook/Inventory sections and `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" for
`PlayerSpellcasting.cast_direct()`. The debug panel's **Give Spell...** sub-panel (F3) lets God
Mode grant any cantrip or leveled spell directly for testing.

**Scroll of &lt;Spell&gt;** (one-shot cast scrolls, 13 in `ITEM_POOL`/`debug_panel.ALL_ITEMS`, one
per `SpellDb` spell): unlike scroll-taught spells above, these are **castable by any class**, not
just Wizard — a non-caster reading one uses `proficiency_bonus + INT modifier` in place of a
`SpellcasterState`'s own ability. Full mechanism: `scripts/items/CLAUDE.md`'s "Scroll of
&lt;Spell&gt;" section and `scripts/entities/CLAUDE.md`'s scrolls entry.

### Talent system (`scripts/items/talent.gd`, `scripts/autoloads/game_state.gd`)
`Talent` is a reusable Resource: `talent_id`, `talent_name`, `description`, `icon_path`, `tier`, `class_id`, `max_rank`, `ranks: Array[Dictionary]`. `rank_description(rank)` returns the description string for a given rank.

**GameState talent state**: `talent_points_available`, `talent_investments` (talent_id → rank), `_class_talents`, `talent_picker_open` (blocks all input). **Key functions**: `get_talent_rank(id)`, `can_invest_talent(id)`, `invest_talent(id)` → `_apply_talent_rank(id, rank)` (dispatches side effects) → emits `talent_invested`. Long rest is no longer floor descent — see "Rest system" below for where `rage_uses_remaining`/`hit_dice` actually refill. Level-up grants +1 point into the per-tier `talent_points` dict (`tier_for_level()` schedule). `hud.gd._on_player_leveled_up()` spawns `talent_picker.gd` when points > 0.

**Icons**: art lives under `icons/classes/barbarian/{t0,t1,t2/<subclass>}/`. `GameState.talent_icon_path(id, rank)` is the single resolver every Talent/Ability sets `icon_path` via. Most talents resolve to one flat icon (`TALENT_ICON_FLAT`, rank ignored); World Tree's 3 talents still gradient 1–3 (`TALENT_ICON_FOLDER`, `..._<rank>.png`); Wild Heart's form-driven abilities (Animal Form, Natural Sleeper, Wild Companion) read live form/rank state instead of a fixed path (`WILD_HEART_FORM_ICON`/`WILD_HEART_SLEEPER_ICON`/`WILD_HEART_COMPANION_ICON`) — `player_wild_heart.gd`'s `cycle_animal_form()`/`cycle_natural_sleeper_form()` re-set `ab.icon_path` on every toggle so the ability-bar icon tracks the active form. **Barbarian (Tier 1: Psycho/Bruiser/Battlefield Expert — Rage is now a baked-in level-1 baseline, not a talent; Reckless Attack and Danger Sense were removed as vestigial/unused; Tier 2: Berserker/Scarred Warrior/Wild Heart/Zealot/World Tree, 5 subclasses, 3 talents each) and Monk full talent/ability tables: `scripts/entities/CLAUDE.md`.** Tier 2 is boss-gated: defeating the floor-5 boss (`GameState.boss_defeated` → `subclass_choice_required`) opens the one-time blocking `scripts/ui/subclass_select.gd` overlay (`choose_subclass()`); Tier-2 points earned at levels 7–12 pend until then. The God-Mode talent-picker arrows remain a debug-only override — see `scripts/autoloads/CLAUDE.md`. Four of the five subclasses (all but World Tree) grant one free, rank-independent activation ability directly at subclass selection (Frenzy/Limit Break/Animal Form/Zealot Strike) — their Tier 2 talents only upgrade that ability, never gate its existence; source specs: `markdowns/barbarian_base.md`, `markdowns/berserker.md`, `markdowns/scarred_warrior.md`, `markdowns/wild_heart.md`, `markdowns/zealot.md`.

### Weapon mastery selection ("Mastery Picker")
`Stats.ALL_WEAPON_MASTERIES` (all 8) + `Stats.mastery_cap()` (per-class/level, computed live) back `scripts/ui/mastery_picker.gd`, which populates `Stats.known_weapon_masteries` — the array every weapon-mastery combat effect already gates on. Spawns once right after class selection (`class_select.gd`), and again after any completed long rest if the player opts in (see "Rest system" below). Implementation detail: `scripts/ui/CLAUDE.md`.

### Items and combat
Weapon fields (`damage_die_min/max`, `damage_type`, `weapon_mastery`, `weapon_category`, `is_heavy`, `is_two_handed`, `is_finesse`, `is_light`, `is_reach`, `is_versatile`/`versatile_die_min/max`, `is_thrown`/`uses_max`/`uses_remaining`, `ammo_item_name`), weapon masteries (Cleave, Vex, Push, Graze, Topple, Sap, Nick, Slow), weapon proficiency, ranged weapons/ammo/long-range rules, equipment slots + dual-wielding (Off-hand only accepts a Light weapon when Main Hand is also Light — Handaxe/Dagger — and fires a bonus Off-hand attack per swing, its damage roll dropping the ability modifier unless negative; a Nick-mastery weapon in either hand adds a third, identical bonus attack), the click-to-toggle Versatile grip (Quarterstaff, Spear), Thrown weapons (Spear, Handaxe, Dagger — RMB/LMB throw using the melee attack modifier, durability "uses"), Shields (`Item.is_shield` — Off-hand, +2 AC, gated by `Stats.proficient_shields` and an available non-two-handed Main Hand, blocks spellcasting while equipped, equip/unequip costs 1 turn — the only equip action that does), the Torch (`Item.is_torch` — click-while-equipped to light for 100 turns, +1 FOV in either hand, +1d4 Fire damage on the Main Hand swing only, permanently burns out into a Burnt Torch), and the full `Item` field table: **`scripts/items/CLAUDE.md`**.
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

**Multiple sessions (local + remote) can be working on this repo at once.** Before starting work AND immediately before that final push, run `git pull origin main` (or `git fetch origin main && git rebase origin/main` if local commits already exist) — a push that's behind `origin/main` is rejected outright (git refuses to silently overwrite unseen work), so catching this early avoids a late, confusing failure. If the pull/rebase produces a real conflict (both sessions touched the same lines), resolve it before pushing — don't force-push over it.

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
- **RULE — damage stacking**: when multiple bonus damage sources apply to the same attack, sum same-type ones into the base damage **before** calling `Enemy.take_typed_damage()`/`DungeonFloor.show_damage()` — one call, one floater, one chat log segment per damage TYPE (a source with its own distinct type, e.g. Zealot's Judgement Day, becomes a second independent instance/floater/segment in the same log line, not a third `game_log()` call). Each source keeps a **named** field in the `dmg` meta string for the tooltip; the visible log line itself never lists per-source names or amounts. Multi-die sources (weapon `NdM`, spell dice) show every individual die roll in the tooltip via `CombatMath.build_damage_instance()`/`encode_damage_instance()`, and `Enemy.take_typed_damage()` applies per-type resist/vuln (`Enemy.resist_types`/`vuln_types`, from `ENEMY_POOL`'s `"resist"`/`"vuln"` keys) before the floor-at-1 clamp. See `scripts/entities/CLAUDE.md`'s "Damage types / resistances" section for the full rule and `player.gd._bump_attack()`/`PlayerRanged.ranged_attack()` for the reference implementation.
- **RULE — no mechanic names in enemy attack log lines**: `enemy.gd._attack_player()` never names a specific player talent/ability in the log text — that context lives only in the `ehit` tooltip.
- **UI conventions** (mouse filters, focus mode, slot sizing, drag-hit detection, TextureRect icon sizing, click-vs-drag, quickbar/inventory tooltips, keyword glossary, compass): all in **`scripts/ui/CLAUDE.md`** — read it before touching any HUD/overlay script, several of its rules are non-obvious footguns.
