# scripts/entities

Entity hierarchy, combat mechanics, D&D stats, status effects, enemy AI.

## Maintenance rule
When adding a new entity type, status effect, or changing combat rules, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Entity hierarchy
```
Entity (CharacterBody2D)   grid_pos: Vector2i, move_to() 0.08 s tween, _tile_center(), is_friendly: bool
  ├── Player               input handling, quickbar, throw mode, blood trail (is_friendly = true)
  ├── Enemy                take_turn(), Behavior enum, hp bar, zzz label (is_friendly = false, default)
  └── Companion            Wild Heart ally — auto-attacks nearest enemy, shares enemy phase (is_friendly = true)
```
`Entity.is_friendly: bool` (default false) — true on `Player` and `Companion`. Added for Zealot's Zealous Presence AOE targeting ("friendly entities in FOV"); reusable by any future ally-scoped system (e.g. Phase 2 multiplayer) without per-class type checks.

## Companion (`companion.gd`)
Extends Entity. Same configure-before-add_child pattern as Enemy (fields set in `configure()`, Stats created in `_ready()`). Key fields: `animal_name`, `armor_class`, `die_count`, `die_sides`. `DungeonFloor.spawn_companion(companion, pos)` sets `_dungeon_floor` and registers via TurnManager. Enemies ignore companions (MVP). On death: sets `GameState.player_companion = null`, unregisters, calls `queue_free()`. `heal_to_max()` called on rest via `GameState._on_short_rest_completed()` and `advance_floor()`. Attack rolls: d20 + `player_stats.proficiency_bonus` vs `enemy.stats.armor_class`.
World pos = `grid_pos * TILE_SIZE + Vector2i(8, 8)`. `TILE_SIZE = 16`.
Z-index: enemies = 1, player = 3.

---

## Adding a new enemy
1. Extend `Entity`, implement `take_turn()` and `_setup_animations()`
2. `TurnManager.register_enemy(self)` in `_ready()` (not in `configure()`)
3. Add entry to `ENEMY_POOL` in `dungeon_floor.gd`; add `idle_fmt`/`run_fmt` keys if sprite naming is non-standard
4. If boss: add to `BOSS_POOL`, set `is_boss = true`

---

## Stats (`stats.gd`)
`modifier(score) -> int` = `floor((score - 10) / 2)`.
`apply_class_defaults()` sets all six ability scores and derives `max_hp` and `armor_class`.
`hit_die_sides() -> int`: Barbarian 12, Ranger 10, Monk 8, Wizard 6.
`_hp_per_level()`: class HP gain per level-up.

**Check proficiency flags** (formerly "save_prof"): `check_prof_str/con/dex/int/wis/cha`. Used for traps, lockpick, disarm. No separate saving throw system — all defensive rolls are "checks". Barbarian: STR+CON. Ranger/Monk: STR+DEX. Wizard: INT+WIS.

### Enemy stat scaling (in `_apply_stats()`)
```gdscript
max_hp      = type["hp"]      + (floor_num - 1) * type["hp_per_floor"]
armor_class = type["ac"]      + floor_num / 5
min_damage  = type["dmg_min"] + (floor_num - 1) / 3
max_damage  = type["dmg_max"] + (floor_num - 1) / 2
```

---

## Combat rolls
| Roll | Formula |
|---|---|
| Player attack | d20 + STR mod + `weapon.bonus_damage` vs enemy `armor_class` |
| Enemy attack | d20 + `floor_num / 3` vs player `armor_class` |
| Player AC | 10 + DEX mod + equipped armor `bonus_ac` (recalc via `GameState.recalculate_stats()`) |
| Enemy AC | type `"ac"` + type `"armor"` + `floor_num / 5` (pool `"armor"` folded into AC, not DR) |
| Critical hit | Natural 20 → auto-hit + 2× damage (both sides) |
| Fumble | Natural 1 → always misses |
| Ranged (DEX) | Same formula but uses DEX mod instead of STR |

`Stats.take_damage(dmg) = maxi(1, dmg)` — no damage reduction. `stats.armor` is always 0.

### Advantage / Disadvantage
- **ADV**: attacking a SLEEPING enemy; attacking enemy whose `just_crossed_door == true` (consumed one-shot after check)
- **DISADV**: ranged attack at Chebyshev distance 1 (melee range); melee with a `is_heavy` weapon when STR < 13
- ADV + DISADV cancel → 1d20
- Yellow "!" floats above enemy on ADV surprise attacks
- Enemy attack log lines (`enemy.gd._attack_player()`) never name the specific talent/ability that granted ADV/DISADV (e.g. no `"(Reckless)"` text) — that context lives only in the `ehit` tooltip roll breakdown, not the log line.

### Bonus damage stacking (Frenzy / Ironwood Bark / Divine Fury, etc.)
When more than one bonus damage source can trigger on the same attack, compute all of them **before** the single `Stats.take_damage()` / `DungeonFloor.show_damage()` call and add them into the base damage total — one number, one floater, one chat log line (each source may still append its own colored `(+N Source)` fragment to that one line for flavor). Never call `take_damage()`/`show_damage()` once per source — besides producing a confusing multi-part log line, a source gated on `not enemy.stats.is_dead()` can silently fail to trigger if an earlier source already killed the enemy. See `player.gd._bump_attack()` / `_ranged_attack()` for the reference implementation (Frenzy + Ironwood Bark + Divine Fury summed into `bonus_dmg` before `enemy.stats.take_damage(pre_crit + bonus_dmg)`).

---

## Temp HP
`Stats.temp_hp: int = 0`. Set by Natural Sleeper R2 (2d6 THP per round while starting a turn on the active form's terrain — replaces existing THP, doesn't stack) and by World Tree's Ironwood Bark (`1d6 × rage_bonus_damage` on Rage activation, and again at turn start while Raging if temp HP is 0 — see `player.gd._on_turn_started()`). `take_damage()` absorbs temp HP before regular HP — if fully absorbed, returns 0. Displayed in HUD as a light-blue strip above the HP bar (`_temp_hp_fill` in hud.gd), proportional to `temp_hp / max_hp`.

## Zealous Presence buff (Zealot)
`Stats.zealous_presence_turns: int = 0` — on the shared `Stats` resource so both `Player` and `Companion` can carry it independently. While > 0, grants Advantage on that entity's attack rolls (`_bump_attack()`, `_ranged_attack()`, `Companion._attack_enemy()`) and on the player's DEX checks (trap disarm, lock picking, trap trigger — same call sites Danger Sense already grants Advantage at). Decrements by 1 at the start of **that entity's own turn** (player: `player.gd._on_turn_started()`, real turns only; companion: top of `Companion.take_turn()`) — not the caster's turn, so a buffed ally's duration ticks down on its own schedule. Set by `player.gd._activate_zealous_presence()` on both `stats` (self) and `GameState.player_companion.stats` (if alive) at cast time only — entities that enter FOV after the cast are not retroactively buffed.

## Status effects
Fields on `Stats`: `poison_turns`, `burning_turns`, `bleeding_turns`, `slowed_turns`.
`tick_status() -> int` decrements all counters and returns total damage dealt (slowed = 0 damage, only movement penalty).

Apply a status:
```gdscript
GameState.player_stats.bleeding_turns = 5
GameState.player_status_changed.emit()
```

| Status | HUD dot | Source | Effect |
|---|---|---|---|
| Poison | green | potions, enemies | damage/turn |
| Burning | orange | Fire Trap | damage/turn |
| Bleeding | red | Spike Trap (5t) | damage/turn |
| Slowed | brown | Bear Trap (20t), mud, water | movement costs 2 turns |

---

## Enemy resist checks (World Tree)
`Enemy.resist_check(dc: int, use_con: bool = false) -> bool` — rolls `d20 + floor/3 + (con_modifier or str_modifier)` vs `dc`; true = enemy resists. Backing stats: `ENEMY_POOL`/`BOSS_POOL` entries may set optional `"str_mod"`/`"con_mod"` int keys (default 0); `_apply_stats()` converts them to `Stats.strength/constitution` (`10 + mod * 2`). Used by Grip of the Forest's pull (STR) and Branching Strike R3's push (CON), both vs DC `8 + player STR mod + proficiency`.
`Enemy.rooted_turns: int` — Grip of the Forest R2. Checked at the top of `take_turn()`: decrements, skips movement, still attacks if already adjacent.
`Enemy.disadv_next_attack: bool` — Grip of the Forest R3. Consumed in `_attack_player()`'s roll (adds a Disadvantage source, combined with Reckless Attack's Advantage via the same net-ADV/DISADV house rule as the player's own attacks).

## Enemy behavior states
`SLEEPING → STATIONARY → ROAMING → CHASING → SEARCHING`

**SLEEPING**: shows zzz label. Wakes when player within `WAKE_RADIUS_SQ = 4` (2-tile adjacency).
**ROAMING**: waypoint BFS. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks tile at Chebyshev ≥ 4. Follows `_roam_path: Array[Vector2i]` via `_bfs_to()`. Falls back to `_do_random_step()` if blocked.
**CHASING**: follows player directly. Opens doors (sets `just_crossed_door = true` when stepping onto door tile). Records `_search_heading` (direction toward player) each turn player is visible.
**SEARCHING**: entered when CHASING enemy reaches `last_known_player_pos` without LOS. Searches for 7 turns in `_search_heading` direction (BFS to `_search_target = last_known_pos + heading * 5`). If player spotted → CHASING. After 7 turns → ROAMING. Fields: `_search_heading: Vector2i`, `_search_turns_remaining: int`, `_search_target: Vector2i`, `_search_path: Array[Vector2i]`.

`_roam_path` and `_roam_target` are cleared on state transitions.

---

## Player-specific (`player.gd`)
- `_click_start_screen_pos`: recorded on LMB press; drag > 8 px cancels `_queued_path`
- `_fov_prev_turn` / `_fov_this_turn`: maintained per turn (no longer grant ADV on their own)
- Throw mode entered via `GameState.player_throw_primed` signal; Esc cancels
- All input gated on `TurnManager.phase == WAITING_FOR_INPUT` AND `GameState.short_rest_open == false` AND `GameState.talent_picker_open == false`
