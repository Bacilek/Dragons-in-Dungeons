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
| `player_leveled_up` | `level: int` | XP threshold crossed — hud.gd spawns talent_picker if points > 0 |
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
hit_dice: int                # available dice (refills to character_level on advance_floor = long rest)
short_rests_remaining: int   # 2 per floor, resets on advance_floor
talent_picker_open: bool     # blocks ALL player input while talent picker is visible
talent_points_available: int # unspent talent points (Tier 1 + Tier 2)
talent_investments: Dict     # talent_id → current_rank (int, 0 = not invested)
_class_talents: Array[Talent]# all talents for current class (Tier 1 + unlocked Tier 2)
tier2_unlocked: bool         # auto-set at level 7 via gain_exp() → unlock_tier2()
active_tier2_subclass: String# current Tier 2 subclass name ("Berserker" default); debug-switchable
TIER2_SUBCLASSES: PackedStringArray  # ["Berserker", "Zealot", "World Tree", "Wild Heart"]
zealot_divine_fury_type: String      # "Radiant"/"Necrotic", persists across turns (toggle only, not per-turn)
zealot_blessed_charges: int          # long-rest resource, max via BLESSED_WARRIOR_MAX_CHARGES[rank] = [0,2,4,6]
zealot_blessed_heal_queued: bool     # set on Blessed Warrior activation; consumed by next successful hit this turn
zealot_zp_charges: int               # Zealous Presence charge, 1/long rest, independent of rage_uses_remaining
invincible: bool             # debug flag
noclip: bool                 # debug flag
player_grid_pos: Vector2i    # synced every move
pending_chasm_items: Array[Item]  # ammo (or any future item) that fell into a chasm mid-shot; drained onto the NEXT floor's random walkable tiles by DungeonFloor._spawn_pending_chasm_items()
```

**Status chokepoint**: `apply_player_status(type: String, turns: int) -> bool` — single entry point for all player status/debuff application. If Rager R1 is active and raging, applies a % chance to negate and returns false (caller skips log). On success: sets `player_stats.{type}_turns = maxi(existing, turns)` and emits `player_status_changed`. All trap, enemy, terrain, and rotten-meat callers must use this — never set `player_stats.{status}_turns` directly.

**Tier 2 unlock**: `unlock_tier2()` — auto-called from `gain_exp()` at level 7. Calls `_setup_barbarian_tier2_talents()` to append Rager/Frenzy/Retaliation to `_class_talents`. No longer tied to Necromancer kill.

**Debug subclass switching**: `TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Zealot", "World Tree", "Wild Heart"]`. `active_tier2_subclass: String` tracks current. `debug_switch_subclass(direction: int)` — clears tier 2 investments + ability bar entries + `_class_talents` tier 2 entries, then re-runs `_setup_tier2_for_active_subclass()` (dispatches to Berserker/Wild Heart/World Tree/Zealot setup — all four implemented). Called from talent_picker.gd's subclass arrow buttons (only visible in God Mode). Adding a 4th+ subclass only requires a new `match` case here plus its `_setup_X_tier2_talents()` — nothing else in the subclass-selection system assumes a fixed count.

**Long rest = floor descent**: `advance_floor()` resets `rage_uses_remaining`, `hit_dice`, and `short_rests_remaining`. Level-up via `gain_exp()` only grants `+1 talent_points_available` and emits `player_leveled_up` — it does NOT reset resources or heal the player.

**Rage DR**: `take_damage_raw(amount, ignore_rage, damage_type: String) -> int` — returns actual damage after DR. Physical types ("Slashing"/"Piercing"/"Bludgeoning") are reduced at Rage talent rank ≥ 2 (25% DR) or ≥ 3 (50% DR). All callers must pass `damage_type`; missing/empty type bypasses DR.

### Hunger thresholds
`hunger` 0–1000. Computed property `hunger_state`:
- `> 600` → SATIATED
- `> 200` → HUNGRY
- `<= 200` → STARVING (1 dmg / 10 turns, no HP regen)

### Equipment slots
`GameState.equipment` dict: keys `"melee"` (displayed "Hand 1" in the inventory overlay), `"hand2"` (displayed "Hand 2" — placeholder slot, no `equip()`/`_fits_slot()` routing yet, not read by combat code, exists only so the inventory grid has a second hand slot for a future dual-wield/offhand feature), `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`.
`GameState.equipped_ranged` property returns ranged slot item.
`equip()` auto-routes by `item.is_ranged` (weapons always land in `"melee"`/`"ranged"`, never `"hand2"`).

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
TurnManager.revert_to_waiting()         # Rager talent only — skips enemy phase, returns to WAITING_FOR_INPUT
                                        # DO NOT generalize: this is not a general action-economy system
```

### Turn sequence
1. Player key → `begin_player_action()` → phase = RESOLVING_PLAYER
2. Action + tween → `on_player_action_complete()`
3. `_process_enemies()` awaits each enemy's `take_turn()` sequentially
4. Phase = WAITING_FOR_INPUT → `player_turn_started` signal fires

Each turn: hunger −1, `Stats.tick_status()` deals status damage, HP regen every 10 turns (blocked while STARVING).
