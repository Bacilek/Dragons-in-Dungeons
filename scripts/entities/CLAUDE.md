# scripts/entities

Entity hierarchy, combat mechanics, D&D stats, status effects, enemy AI.

## Maintenance rule
When adding a new entity type, status effect, or changing combat rules, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Entity hierarchy
```
Entity (CharacterBody2D)   grid_pos: Vector2i, move_to() 0.08 s tween, _tile_center()
  ├── Player               input handling, quickbar, throw mode, blood trail
  └── Enemy                take_turn(), Behavior enum, hp bar, zzz label
```
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
`hit_die_sides() -> int`: Barbarian 12, Ranger 10, Cleric 8, Wizard 6.
`_hp_per_level()`: class HP gain per level-up.

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
| Enemy AC | type `"ac"` + `floor_num / 5` |
| Critical hit | Natural 20 → auto-hit + 2× damage (both sides) |
| Ranged (DEX) | Same formula but uses DEX mod instead of STR |

### Advantage / Disadvantage
- **ADV**: attacking a SLEEPING enemy; attacking enemy whose `just_crossed_door == true` (consumed one-shot after check)
- **DISADV**: ranged attack at Chebyshev distance 1 (melee range)
- ADV + DISADV cancel → 1d20
- Yellow "!" floats above enemy on ADV surprise attacks

---

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

## Enemy behavior states
`SLEEPING → STATIONARY → ROAMING → CHASING`

**SLEEPING**: shows zzz label. Wakes when player within `WAKE_RADIUS_SQ = 4` (2-tile adjacency).
**ROAMING**: waypoint BFS. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks tile at Chebyshev ≥ 4. Follows `_roam_path: Array[Vector2i]` via `_bfs_to()`. Falls back to `_do_random_step()` if blocked.
**CHASING**: follows player directly. Opens doors (sets `just_crossed_door = true` when stepping onto door tile).

`_roam_path` and `_roam_target` are cleared on state transitions.

---

## Player-specific (`player.gd`)
- `_click_start_screen_pos`: recorded on LMB press; drag > 8 px cancels `_queued_path`
- `_fov_prev_turn` / `_fov_this_turn`: maintained per turn (no longer grant ADV on their own)
- Throw mode entered via `GameState.player_throw_primed` signal; Esc cancels
- All input gated on `TurnManager.phase == WAITING_FOR_INPUT` AND `GameState.short_rest_open == false`
