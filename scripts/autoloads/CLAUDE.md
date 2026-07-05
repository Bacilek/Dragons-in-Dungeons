# scripts/autoloads

Core singletons — loaded at engine start, affect the entire game. Files: `game_state.gd`, `turn_manager.gd`, `audio_manager.gd`, `save_manager.gd`.

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
| `player_status_changed` | — | status effect change |
| `short_rest_changed` | — | hit dice / rests update |
| `short_rest_completed` | — | short rest finished |
| `short_rest_aborted` | — | rest cancelled |
| `long_rest_completed` | — | `GameState.long_rest()` finished restoring everything |
| `stairs_discovered` | — | fog reveals stairs tile |
| `camera_recenter_requested` | — | re-center camera |
| `debug_jump_floor` | `floor_num: int` | debug jump |
| `debug_reveal_all` | — | reveal map |
| `debug_see_all` | `active: bool` | F3 See All toggle |
| `crit_banner` | `text: String, color: Color` | nat 20 / nat 1 overlay banner |
| `screen_shake` | `strength: float` | camera shake (handled by `PlayerVfx.screen_shake`, `scripts/entities/player_vfx.gd`) |
| `known_masteries_changed` | — | `known_weapon_masteries` mutated via `toggle_mastery()` |

---

## AudioManager (`audio_manager.gd`)
Autoload singleton. Drop `.ogg` files into `res://audio/` with these names; missing files are silently ignored.

```gdscript
AudioManager.play("hit_enemy")          # one-shot SFX
AudioManager.play_music("res://audio/music_dungeon.ogg")  # looping track
AudioManager.stop_music()
```

**SFX names:** `hit_enemy, miss_enemy, crit, crit_fail, player_hurt, player_die, kill_enemy, shoot, open_door, close_door, lock_door, step_grass, step_mud, step_water, step_floor, trap_fire, trap_spike, trap_piston, trap_bear, drink_potion, lockpick, cook_meat, throw_item, bottle_fill`

**Music:** `music_dungeon.ogg` (normal floors), `music_boss.ogg` (boss floors: floor % 5 == 0). Enable **Loop** in Godot import settings for music files.

**Recommended free asset sources:** [kenney.nl](https://kenney.nl/assets) RPG pack, [freesound.org](https://freesound.org) (CC0 filter).

### Key state fields
```
short_rest_open: bool        # blocks ALL player input while true
short_rest_active: bool      # a rest is in progress (ticking turns) — short OR long, see long_rest_pending
long_rest_pending: bool      # true when the in-progress short_rest_active countdown is actually a long rest
hit_dice: int                # available dice (refills to character_level only in long_rest())
short_rests_remaining: int   # 2 per long-rest cycle, resets in long_rest() (NOT advance_floor)
LONG_REST_FOOD_COST: int     # const 100 — combined Item.food_value required to long rest
LONG_REST_TURNS: int         # const 20 — turns a long rest takes (short rest: SHORT_REST_TURNS = 5)
talent_picker_open: bool     # blocks ALL player input while talent picker is visible
mastery_picker_open: bool    # blocks ALL player input while the Mastery Picker is visible (scripts/ui/mastery_picker.gd)
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

**Weapon mastery selection**: `can_select_mastery(name) -> bool` / `toggle_mastery(name) -> bool` mutate `player_stats.known_weapon_masteries` (the single source of truth every combat mastery gate reads — no parallel copy on `GameState`). Hard-blocks selecting past `Stats.mastery_cap()`; deselection always allowed. Emits `known_masteries_changed`. Used by `scripts/ui/mastery_picker.gd` — see `scripts/ui/CLAUDE.md`'s "Mastery picker" and `docs/architecture/weapon-mastery-selection-design.md`.

**Status chokepoint**: `apply_player_status(type: String, turns: int) -> bool` — single entry point for all player status/debuff application. If Rager R1 is active and raging, applies a % chance to negate and returns false (caller skips log). On success: sets `player_stats.{type}_turns = maxi(existing, turns)` and emits `player_status_changed`. All trap, enemy, terrain, and rotten-meat callers must use this — never set `player_stats.{status}_turns` directly.

**Tier 2 unlock**: `unlock_tier2()` — auto-called from `gain_exp()` at level 7. Calls `_setup_barbarian_tier2_talents()` to append Rager/Frenzy/Retaliation to `_class_talents`. No longer tied to Necromancer kill.

**Debug subclass switching**: `TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Zealot", "World Tree", "Wild Heart"]`. `active_tier2_subclass: String` tracks current. `debug_switch_subclass(direction: int)` — clears tier 2 investments + ability bar entries + `_class_talents` tier 2 entries, then re-runs `_setup_tier2_for_active_subclass()` (dispatches to Berserker/Wild Heart/World Tree/Zealot setup — all four implemented). Called from talent_picker.gd's subclass arrow buttons (only visible in God Mode). Adding a 4th+ subclass only requires a new `match` case here plus its `_setup_X_tier2_talents()` — nothing else in the subclass-selection system assumes a fixed count.

**Rest system**: `advance_floor()` is floor bookkeeping ONLY (floor number, terrain AC reset) — it does not restore anything. `GameState.long_rest()` is the single chokepoint for every long-rest-gated resource: full HP heal, cleared status effects, `rage_uses_remaining`, `hit_dice = character_level`, `short_rests_remaining = max_short_rests`, Natural Sleeper form lock-in, Zealot `zealot_blessed_charges`/`zealot_zp_charges`, companion heal, `_sync_ability_uses()` (One with Nature charge). Triggered explicitly by the player via the Alt-menu's Long Rest tab (`scripts/ui/short_rest_panel.gd`), never automatically. **Any new "per long rest" resource must be refilled in `long_rest()` and nowhere else** — `advance_floor()` must never regain restore logic. `GameState.total_food_value() -> int` sums `Item.food_value × quantity` across quickbar+bag; `can_long_rest() -> bool` (always true when `invincible`) gates the button; `_consume_food_value(amount)` spends cheapest-value FOOD items first, skipped entirely while `invincible` (so God Mode long rests cost nothing). `long_rest_pending: bool` tells the shared short-rest turn-countdown in `player.gd._on_turn_started()` to call `long_rest()` instead of the short-rest heal when the countdown reaches 0; `rest_interrupt_panel.gd`'s abort path also clears it. Level-up via `gain_exp()` only grants `+1 talent_points_available` and emits `player_leveled_up` — it does NOT reset resources or heal the player.

**Rage DR**: `take_damage_raw(amount, ignore_rage, damage_type: String) -> int` — returns actual damage after DR. Physical types ("Slashing"/"Piercing"/"Bludgeoning") are reduced at Rage talent rank ≥ 2 (25% DR) or ≥ 3 (50% DR). All callers must pass `damage_type`; missing/empty type bypasses DR.

### Equipment slots
`GameState.equipment` dict: keys `"melee"` (Main Hand), `"hand2"` (Off-hand), `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`.
`GameState.equipped_ranged` property returns ranged slot item.
`equip()` auto-routes by `item.is_ranged` (weapons always land in `"melee"`/`"ranged"`, never `"hand2"` — Off-hand is only reachable via explicit drag in `inventory_overlay.gd`). `"hand2"` accepts a Light melee weapon only when Main Hand is also Light — dual-wielding two Light weapons (Handaxe, Dagger) fires a bonus Off-hand attack on every melee swing (`player.gd._try_offhand_attack()`) — see `scripts/items/CLAUDE.md`'s "Dual-wielding". Dragging a stacked durability weapon (`quantity > 1`) onto any equipment slot equips only one unit (`move_item()`'s `_should_split_for_equip()`/`_split_one_unit()`, shared with `equip()`) — see `scripts/items/CLAUDE.md`'s "Dragging a stack".

---

## SaveManager (`save_manager.gd`)

Save-file plumbing for the single-slot run save (design: `docs/architecture/SAVE_LOAD_ARCHITECTURE.md`). **Phase A session 3a only** — file mechanics exist, but the payload is still a version-only stub `{"save_version": 1}`; real `to_dict()/from_dict()` serialization is session 3b, Continue-flow UI is 3c.

### Files
- `user://save/run.json` — active run (versioned JSON, `save_version` first key)
- `user://save/run.json.bak` — previous good save (auto-created on every write)
- `user://save/run.json.tmp` — transient atomic-write staging file

### API
```gdscript
SaveManager.has_save() -> bool   # a parseable, version-compatible run.json (or .bak) exists
SaveManager.save_run()           # atomic write: .tmp → rotate old save to .bak → rename into place
SaveManager.load_run() -> bool   # validates/parses only (stub); 3b/3c will apply the state
SaveManager.delete_save()        # removes run.json + .bak + .tmp
SaveManager.v2i_to_arr(v) / SaveManager.arr_to_v2i(a)  # shared Vector2i↔[x,y] JSON helpers (static)
```

### Behavior rules
- **Permadeath**: `_ready()` connects `GameState.player_died` and `player_won` → `delete_save()`.
- **Never crashes on a bad file**: unreadable/unparseable/unknown-version saves fall back to `.bak`, then to "no run" (`{}`/false). Saves with `save_version > SAVE_VERSION` (newer build) are refused.
- **Migrations**: `_migrations: Dictionary` of `save_version → Callable` upgraders, applied in a loop until current. Dev-phase policy: a missing migrator silently discards the save (doc §7).
- No checksums/encryption — save-scumming via OS copy is explicitly not defended against.

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

Each turn: `Stats.tick_status()` deals status damage. Hunger has been removed — see "Rest system" above.
