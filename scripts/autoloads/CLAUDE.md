# scripts/autoloads

Core singletons — loaded at engine start, affect the entire game. Two files: `game_state.gd` and `turn_manager.gd`.

## Maintenance rule
When you add signals, state fields, or change turn flow here, **immediately update this file and root `CLAUDE.md`** to reflect the change — without waiting to be asked.

---

## GameState (`game_state.gd`)

### Critical: never use `log()`
`log()` is a GDScript built-in (float math). Always use `GameState.game_log(msg)` for the combat log.

### All signals (complete list)
| Signal | Payload | When emitted |
|---|---|---|
| `floor_changed` | `new_floor: int` | after `advance_floor()` |
| `player_hp_changed` | `current_hp, max_hp` | after heal/damage |
| `player_exp_changed` | `exp, exp_needed, level` | XP update |
| `player_leveled_up` | `level: int` | XP threshold crossed |
| `player_died` | — | HP hits 0 |
| `player_won` | — | win condition |
| `combat_message` | `msg: String` | combat log entries |
| `inventory_changed` | — | quickbar/bag mutations |
| `equipment_changed` | — | slot equip/unequip |
| `inventory_toggle` | — | I key |
| `player_action_requested` | `action_name: String` | debug/input shortcuts |
| `player_throw_primed` | `item: Item` | RMB food in quickbar |
| `player_tool_primed` | `item: Item` | tool use primed |
| `class_chosen` | `chosen_class: Stats.CharacterClass` | class select screen |
| `hunger_changed` | `value: int` | each hunger tick |
| `player_status_changed` | — | status effect change |
| `short_rest_changed` | — | hit dice / rests update |
| `short_rest_completed` | — | rest finished |
| `short_rest_aborted` | — | rest cancelled |
| `stairs_discovered` | — | fog reveals stairs tile |
| `camera_recenter_requested` | — | re-center camera |
| `debug_jump_floor` | `floor_num: int` | debug jump |
| `debug_reveal_all` | — | reveal map |
| `debug_see_all` | `active: bool` | F3 See All toggle |
| `crit_banner` | `text: String, color: Color` | nat 20 / nat 1 overlay banner |
| `screen_shake` | `strength: float` | camera shake (handled by Player._screen_shake) |

---

## AudioManager (`audio_manager.gd`)
Autoload singleton. Drop `.ogg` files into `res://audio/` with these names; missing files are silently ignored.

```gdscript
AudioManager.play("hit_enemy")          # one-shot SFX
AudioManager.play_music("res://audio/music_dungeon.ogg")  # looping track
AudioManager.stop_music()
```

**SFX names:** `hit_enemy, miss_enemy, crit, crit_fail, player_hurt, player_die, kill_enemy, shoot, open_door, close_door, lock_door, step_grass, step_mud, step_water, step_floor, trap_fire, trap_spike, trap_piston, trap_bear, eat_food, drink_potion, lockpick, hungry, starving, cook_meat, throw_item, bottle_fill`

**Music:** `music_dungeon.ogg` (normal floors), `music_boss.ogg` (boss floors: floor % 5 == 0). Enable **Loop** in Godot import settings for music files.

**Recommended free asset sources:** [kenney.nl](https://kenney.nl/assets) RPG pack, [freesound.org](https://freesound.org) (CC0 filter).

### Key state fields
```
short_rest_open: bool        # blocks ALL player input while true
short_rest_active: bool      # a rest is in progress (ticking turns)
hit_dice: int                # available dice (refills to character_level on advance_floor)
short_rests_remaining: int   # 2 per floor, resets on advance_floor
invincible: bool             # debug flag
noclip: bool                 # debug flag
player_grid_pos: Vector2i    # synced every move
```

### Hunger thresholds
`hunger` 0–1000. Computed property `hunger_state`:
- `> 600` → SATIATED
- `> 200` → HUNGRY
- `<= 200` → STARVING (1 dmg / 10 turns, no HP regen)

### Equipment slots
`GameState.equipment` dict: keys `"melee"` and `"ranged"`.
`GameState.equipped_ranged` property returns ranged slot item.
`equip()` auto-routes by `item.is_ranged`.

---

## TurnManager (`turn_manager.gd`)

### Phase machine
```
WAITING_FOR_INPUT → RESOLVING_PLAYER → RESOLVING_ENEMIES → WAITING_FOR_INPUT
```
Player input is **hard-gated** on `phase == WAITING_FOR_INPUT`. Also gated on `GameState.short_rest_open == false`.

### API
```gdscript
TurnManager.begin_player_action()       # call at start of any player action
TurnManager.on_player_action_complete() # call after action tween finishes
TurnManager.register_enemy(enemy)       # call in enemy _ready()
TurnManager.clear_enemies()             # call in DungeonFloor before floor reload
```

### Turn sequence
1. Player key → `begin_player_action()` → phase = RESOLVING_PLAYER
2. Action + tween → `on_player_action_complete()`
3. `_process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase = WAITING_FOR_INPUT → `player_turn_started` signal fires

Each turn: hunger −1, `Stats.tick_status()` deals status damage, HP regen every 10 turns (blocked while STARVING).
