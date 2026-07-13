# scripts/autoloads

Core singletons — loaded at engine start, affect the entire game. Files: `rng.gd`, `game_state.gd`, `turn_manager.gd`, `audio_manager.gd`, `save_manager.gd`. (`Rng` is registered FIRST in project.godot — `GameState._ready()` → `start_new_run()` calls `Rng.reseed()`, so it must already exist.)

## Maintenance rule
When you add signals, state fields, or change turn flow here, **immediately update this file and root `CLAUDE.md`** to reflect the change — without waiting to be asked.

---

## Rng (`rng.gd`)

The shared gameplay RNG service (project-wide retrofit of SAVE_LOAD_ARCHITECTURE.md §6, done for **seeded-run determinism**: same `run_seed` + same player inputs → identical playthrough). Wraps one `RandomNumberGenerator`.

### API
```gdscript
Rng.roll(sides) -> int          # 1..sides inclusive — D&D die roll (was randi_range(1, sides))
Rng.range_i(from, to) -> int    # inclusive int range (was randi_range(from, to))
Rng.chance(p) -> bool           # true with probability p (was randf() < p)
Rng.pick(arr) -> Variant        # uniform element (was arr[randi() % arr.size()])
Rng.shuffle(arr)                # seeded in-place Fisher-Yates via RngUtil (was Array.shuffle())
Rng.reseed(seed_value)          # called by GameState.start_new_run() with run_seed
Rng.get_state() / Rng.set_state(s)  # exact stream position (int64) for save/load
```

### Rules
- **All gameplay-affecting randomness DURING a floor goes through `Rng`**: to-hit/damage/crit rolls (player, enemy, companion, CombatMath), resist/ability checks, trap-trigger saves, search/lockpick/disarm checks, talent proc chances (Rager, Eagle, Frenzy, Divine Fury, Ironwood Bark, Blessed Warrior), enemy roam/wander shuffles, loot rolled at kill time (boss loot, Rotten Meat, ammo-from-corpse), push wall-slam damage, potion/hit-die/rest healing rolls.
- **Cosmetic randomness stays on the global unseeded RNG and is never migrated** (camera shake in `player_vfx.gd`, tween/particle jitter) — IMPLEMENTATION_SEQUENCE.md invariant 8.
- **Floor structure/population does NOT use `Rng`**: tile gen uses `DungeonGenerator`'s own seeded rng; population uses `DungeonFloor._pop_rng` (seeded `run_seed ^ (floor * 0x1234ABCD)`). Both must stay pure functions of `(run_seed, floor)` so a reloaded save regenerates the identical floor regardless of how many gameplay rolls were consumed first.
- **Save/load**: `GameState.to_dict()` stores `rng_state` **as a String** (JSON round-trips numbers through float — a raw int64 above 2^53 would silently corrupt); `from_dict()` restores it via `set_state()`, or falls back to `reseed(run_seed)` for v1 saves that predate the field (SAVE_VERSION 2).
- `Rng` is registered before `GameState` in project.godot — do not reorder.

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
| `subclass_choice_required` | — | Tier 2 gating boss defeated with an unchosen subclass — hud.gd spawns `subclass_select.gd` |
| `boss_defeated` | `boss_id: String` | any boss killed (player kill or Push-into-chasm) — GameState's own `_on_boss_defeated()` runs the Tier 2 gate |
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
Autoload singleton, all one-shot SFX + music routed through it — never call `AudioStreamPlayer` directly from gameplay code. `SFX_FILES` (single file) and `SFX_BANKS` (array of files, one picked at random per `play()` call — used for `player_hurt` and `footstep`) map logical names to real filenames under `res://audio/`; unmapped names (`miss_enemy`, `player_die`, `open_door`, `close_door`, `lock_door`, `trap_spike`, `trap_bear`, `drink_potion`, `cook_meat`, `bottle_fill`) have no asset yet and silently no-op — owed assets, not bugs.

```gdscript
AudioManager.play("hit_enemy")            # one-shot SFX by logical name
AudioManager.play_crit(weapon)            # nat-20 stinger, auto-picks bludgeon/piercing variant from weapon.damage_type (null/empty = bludgeon)
AudioManager.play_hit(enemy.enemy_id)     # normal hit, auto-picks a per-enemy-type variant if one exists (else "hit_enemy")
AudioManager.play_random_bgm()            # random normal-floor track (bgm.mp3 / bgm2.mp3)
AudioManager.play_boss_music()            # boss.mp3
AudioManager.stop_music()
```

**Single-file SFX:** `hit_enemy, hit_skeleton, hit_zombie, ranged_hit, shoot, crit, crit_piercing, crit_fail, kill_enemy, level_up, lockpick, next_floor, open_inventory, rage, rest, step_grass, step_floor, step_water, step_mud, talent_point_spent, trap_fire, trap_piston, weapon_break, throw_item`.
**Random-variant banks:** `player_hurt` (5 files under `audio/get_hit/`), `footstep` (10 files `audio/footstep/footstepNN.ogg` — used for enemy movement; player movement uses the tile-typed `step_*` names instead, via `Player._play_footstep_sound()`).
**Music:** `audio/bgm/bgm.mp3` + `bgm2.mp3` (normal floors, `play_random_bgm()`), `audio/bgm/boss.mp3` (boss floors, `play_boss_music()`) — picked in `DungeonFloor._load_floor()`. Looping is handled in code, not the import setting: `_music.finished` is connected to `_on_music_finished()`, which replays the same stream from the start — works regardless of each file's own "Loop" import flag.
**Adding a new SFX**: drop the file under `res://audio/`, add a `logical_name: "relative/path.ext"` entry to `SFX_FILES` (or a new key in `SFX_BANKS` for randomized variants), then call `AudioManager.play("logical_name")` at the trigger site — no other plumbing needed.
**Volume**: SFX play at `SFX_VOLUME_DB` (-9.0 dB), music at `-8.0 + VOLUME_50_PCT_DB` (≈-14.02 dB, i.e. half of its original -8.0 dB baseline). `VOLUME_50_PCT_DB` (-6.0206 dB) is the linear-to-dB constant for "50% volume" — reuse it rather than hardcoding another half-volume dB value.
**Mute**: `AudioManager.toggle_mute()` / `set_muted(bool)` mute the entire `"Master"` audio bus via `AudioServer.set_bus_mute()` — covers music and every SFX player in one call since they all route through `"Master"`. State lives on the autoload (`is_muted`, `mute_changed` signal) so it survives floor/level transitions for free, and is additionally persisted to `user://audio_settings.cfg` (loaded in `_ready()`) so it survives app restarts. HUD toggle: `scenes/ui/hud.tscn`'s `MuteButton` (top-right corner) + `hud.gd._on_mute_pressed()`/`_on_mute_changed()`.

### Key state fields
```
short_rest_open: bool        # blocks ALL player input while true
short_rest_active: bool      # a rest is in progress (ticking turns) — short OR long, see long_rest_pending
long_rest_pending: bool      # true when the in-progress short_rest_active countdown is actually a long rest
hit_dice: int                # available dice (refills to max_hit_dice() in long_rest(); gain_exp() also grants the level-up's +1 die to CURRENT hit_dice, not just the cap, so it's usable in a short rest before the next long rest)
short_rests_remaining: int   # 2 per long-rest cycle, resets in long_rest() (NOT advance_floor)
LONG_REST_FOOD_COST: int     # const 100 — combined Item.food_value required to long rest
LONG_REST_TURNS: int         # const 20 — turns a long rest takes (short rest: SHORT_REST_TURNS = 5)
talent_picker_open: bool     # blocks ALL player input while talent picker is visible
mastery_picker_open: bool    # blocks ALL player input while the Mastery Picker is visible (scripts/ui/mastery_picker.gd)
subclass_picker_open: bool   # blocks ALL player input while the subclass-select overlay is visible (scripts/ui/subclass_select.gd)
talent_points: Dictionary    # {1:0, 2:0, 3:0, 4:0} tier → unspent points; accumulates even while a tier is locked
talent_points_available: int # computed sum over talent_points (backward-compat: signals, auto-close logic)
talent_investments: Dict     # talent_id → current_rank (int, 0 = not invested)
_class_talents: Array[Talent]# all talents for current class (Tier 1 + unlocked Tier 2)
tier2_unlocked: bool         # set when the gating boss dies — via choose_subclass() (Barbarian) or unlock_tier2() directly (other classes); NOT level-gated
TIER2_GATING_BOSS_ID: String # const "big_demon" — the floor-5 boss whose death unlocks Tier 2
tier3_selected_class: int    # -1 until a Tier 3 multiclass is chosen (stub — no Tier 3 content yet; read by tier_unlocked(3))
subclass_chosen: bool        # true once the player has made the one-time subclass choice (reset in start_new_run)
active_tier2_subclass: String# current Tier 2 subclass name ("Berserker" default until chosen); God-Mode debug-switchable
TIER2_SUBCLASSES: PackedStringArray  # ["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]
zealot_divine_fury_type: String      # "Radiant"/"Necrotic", persists across turns (toggle only, not per-turn)
zealot_blessed_charges: int          # long-rest resource, max via BLESSED_WARRIOR_MAX_CHARGES[rank] = [0,2,4,6]
zealot_blessed_heal_queued: bool     # set on Blessed Warrior activation; consumed by next successful hit this turn
zealot_zp_charges: int               # Zealous Presence charge, 1/long rest, independent of rage_uses_remaining
invincible: bool             # debug flag
noclip: bool                 # debug flag
player_grid_pos: Vector2i    # synced every move
pending_chasm_items: Array[Item]  # ammo (or any future item) that fell into a chasm mid-shot; drained onto the NEXT floor's random walkable tiles by DungeonFloor._spawn_pending_chasm_items()
```

**Ability usability check**: `GameState.is_ability_usable(ab: Ability) -> bool` — beyond the generic `uses_remaining`/`uses_max` pool (`Ability.has_uses()`), several free base-abilities (`uses_max == 0`, always "has uses") are additionally gated by external state that isn't visible from the `Ability` resource alone: `"frenzy"` needs `is_raging` and `not berserker_frenzy_used`, `"limit_break"` needs `not scarred_warrior_limit_break_used`, `"zealot_strike"` needs `hit_dice > 0`, `"grip_of_the_forest"` needs `is_raging`. Used only by `hud.gd`'s ability-bar greying (`scripts/ui/CLAUDE.md`) — never gates the actual activation logic, which each ability's own function (`player_berserker.gd` etc.) still owns independently.

**Weapon mastery selection**: `can_select_mastery(name) -> bool` / `toggle_mastery(name) -> bool` mutate `player_stats.known_weapon_masteries` (the single source of truth every combat mastery gate reads — no parallel copy on `GameState`). Hard-blocks selecting past `Stats.mastery_cap()`; deselection always allowed. Emits `known_masteries_changed`. Used by `scripts/ui/mastery_picker.gd` — see `scripts/ui/CLAUDE.md`'s "Mastery picker" and `docs/architecture/weapon-mastery-selection-design.md`.

**Status chokepoint**: `apply_player_status(type: String, turns: int) -> bool` — single entry point for all player status/debuff application. If Rager R1 is active and raging, applies a % chance to negate and returns false (caller skips log). On success: sets `player_stats.{type}_turns = maxi(existing, turns)` and emits `player_status_changed`. All trap, enemy, terrain, and rotten-meat callers must use this — never set `player_stats.{status}_turns` directly.

**`choose_race()` re-emits `player_hp_changed`**: `apply_race_defaults()` can change `max_hp` (Dwarf's +1/level, including level 1 — see root `CLAUDE.md`'s "Race system"), so `choose_race()` emits `player_hp_changed(current_hp, max_hp)` itself after applying race defaults, rather than relying on whichever earlier signal the calling onboarding screen fired (both `character_select.gd`'s premade path and `point_buy_select.gd`'s confirm emit it with the PRE-race value, since race is chosen after).

**Tier 2 unlock + subclass selection (boss-gated)**: Tier 2 does NOT unlock by level. Every boss kill emits `boss_defeated(boss_id)` (from `player.gd._finish_kill()` and `DungeonFloor.resolve_push()`'s chasm path); GameState's own `_on_boss_defeated()` ignores everything except `TIER2_GATING_BOSS_ID` ("big_demon", floor 5). On that kill: Barbarian (has subclasses) with `not subclass_chosen` emits `subclass_choice_required` — hud.gd spawns `scripts/ui/subclass_select.gd` (blocking, non-dismissable overlay showing all four subclasses); its confirm calls `choose_subclass(name)` which sets `active_tier2_subclass` + `subclass_chosen = true` and calls `unlock_tier2()`. Other classes (or an already-made choice) call `unlock_tier2()` directly. `unlock_tier2()` sets `tier2_unlocked` and runs `_setup_tier2_for_active_subclass()` (dispatches to the four `_setup_X_tier2_talents()` — all implemented). `choose_subclass()` is one-time: it no-ops once `subclass_chosen` is true. Levels 7–12 fill `talent_points[2]` unconditionally — points earned before the boss kill sit **pending** (the talent picker shows a pending badge) and become spendable the instant Tier 2 unlocks. If the player never kills the gating boss, Tier 2 points stay pending for the rest of the run — intentional, no special handling. If debug Jump-to-Floor skips floor 5, the God-Mode subclass arrows / debug panel unlock button remain the escape hatch.

**Tier scaffolding (Tiers 1–4)**: `TIER_LEVEL_RANGES = {1: [1,6], 2: [7,12], 3: [13,17], 4: [18,20]}` + `tier_for_level(lv) -> int` (returns 0 for level 21+, the only gap) drive point grants in `gain_exp()`. `tier_unlocked(tier) -> bool`: 1 = always; 2 = `tier2_unlocked`; 3 = `tier3_selected_class != -1` and level ≥ 13; 4 = level ≥ 18. `can_invest_talent()` gates on `tier_unlocked(t.tier)` plus `talent_points[t.tier] > 0` (with an extra explicit tier-2 lock guard). Tier 3/4 content is NOT implemented — only the accessor shape exists (see `docs/architecture/TALENT_SYSTEM_ARCHITECTURE.md` §4).

**Debug subclass switching (God-Mode-only override, NOT the player path)**: `TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]`. `debug_switch_subclass(direction: int)` — clears tier 2 investments + ability bar entries (including the outgoing subclass's free base ability via `TIER2_BASE_ABILITY_ID`) + `_class_talents` tier 2 entries, then re-runs `_setup_tier2_for_active_subclass()`. Called from talent_picker.gd's subclass arrow buttons (only visible in God Mode); it deliberately does NOT set `subclass_chosen`. Adding another subclass requires a new `match` case here plus its `_setup_X_tier2_talents()`, a `TIER2_BASE_ABILITY_ID` entry if it grants a free base ability, plus a card entry in `subclass_select.gd`'s `SUBCLASSES` const.

**Rest system**: `advance_floor()` is floor bookkeeping ONLY (floor number, terrain AC reset) — it does not restore anything. `GameState.long_rest()` is the single chokepoint for every long-rest-gated resource: full HP heal, cleared status effects, `rage_uses_remaining`, `hit_dice = character_level`, `short_rests_remaining = max_short_rests`, Natural Sleeper form lock-in, Zealot `zealot_blessed_charges`/`zealot_zp_charges`, companion heal, `_sync_ability_uses()` (One with Nature charge). Triggered explicitly by the player via the Alt-menu's Long Rest tab (`scripts/ui/short_rest_panel.gd`), never automatically. **Any new "per long rest" resource must be refilled in `long_rest()` and nowhere else** — `advance_floor()` must never regain restore logic. `GameState.total_food_value() -> int` sums `Item.food_value × quantity` across quickbar+bag; `can_long_rest() -> bool` (always true when `invincible`) gates the button; `_consume_food_value(amount)` spends cheapest-value FOOD items first, skipped entirely while `invincible` (so God Mode long rests cost nothing). `long_rest_pending: bool` tells the shared short-rest turn-countdown in `player.gd._on_turn_started()` to call `long_rest()` instead of the short-rest heal when the countdown reaches 0; `rest_interrupt_panel.gd`'s abort path also clears it. Level-up via `gain_exp()` only grants `+1 talent_points_available` and emits `player_leveled_up` — it does NOT reset resources or heal the player.

**Level-up max HP tooltip**: `GameState.gain_exp()`'s "Level up!" chat line wraps the `+N max HP` text in an `[url=hplvl:...]` tag (`Stats.hp_per_level_breakdown()` supplies `die_sides`/`avg`/`con`/`dwarf`/`total`; the meta also carries `n`, how many level thresholds this one `gain_exp()` call crossed, since a single large XP grant can level up more than once) — hover shows the same additive breakdown (hit-die average + CON mod + Dwarven Toughness) that `dmg:`/`heal:` tooltips use for combat numbers. `TooltipFormatters.fmt_hplvl_tooltip()`, dispatched in `hud.gd._format_tooltip()`.

**Rage DR**: `take_damage_raw(amount, ignore_rage, damage_type: String) -> int` — returns actual damage after DR. Physical types ("Slashing"/"Piercing"/"Bludgeoning") are always reduced 50% while raging (baked-in baseline, no longer talent-gated — see `scripts/entities/CLAUDE.md`'s Barbarian class section). Scarred Warrior's Born in Blood talent applies an additional Bloodied-based modifier afterward. All callers must pass `damage_type`; missing/empty type bypasses DR.

### Equipment slots
`GameState.equipment` dict: keys `"melee"` (Main Hand), `"hand2"` (Off-hand), `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`.
`GameState.equipped_ranged` property returns ranged slot item.
`equip()` auto-routes by `item.is_ranged` (weapons always land in `"melee"`/`"ranged"`, never `"hand2"` — Off-hand is only reachable via explicit drag in `inventory_overlay.gd`). `"hand2"` accepts a Light melee weapon only when Main Hand is also Light — dual-wielding two Light weapons (Handaxe, Dagger) fires a bonus Off-hand attack on every melee swing (`player.gd._try_offhand_attack()`) — see `scripts/items/CLAUDE.md`'s "Dual-wielding". Dragging a stacked durability weapon (`quantity > 1`) onto any equipment slot equips only one unit (`move_item()`'s `_should_split_for_equip()`/`_split_one_unit()`, shared with `equip()`) — see `scripts/items/CLAUDE.md`'s "Dragging a stack".
**Auto-unequip on two-handed equip**: equipping (or drag-dropping) a two-handed weapon into `"melee"` automatically kicks whatever's sitting in `"hand2"` back to the bag first (`GameState._auto_unequip_offhand()`, called from both `equip()` and `move_item()`) — a two-handed Main Hand and an Off-hand item can never coexist anymore, so switching from dual Light weapons to e.g. the Greataxe no longer strands the off-hand weapon equipped.
**Equip is always a free action**: `equip()`/`unequip()`/`move_item()` never cost a turn (the old `equip_action_taken` signal + `costs_turn` params + `player.gd`'s `_pending_equip_turn` machinery were removed) — swapping gear, including mid-combat, doesn't burn the player's turn.

---

## SaveManager (`save_manager.gd`)

Save-file plumbing for the single-slot run save (design: `docs/architecture/SAVE_LOAD_ARCHITECTURE.md`). **Phase A is FULLY done (sessions 3a + 3b + 3c)** — file mechanics, full Phase-A serialization, AND the Continue flow + autosave triggers are live. Phase B (mid-floor state) has not started.

### Continue flow (session 3c)
- **Entry point**: `character_select.gd` (the actual first screen of a run — see `scripts/ui/CLAUDE.md`) shows a gold "Continue Saved Run" button (below the cards) only when `SaveManager.has_save()`. Pressing it: `load_run()` → `GameState.class_chosen.emit(restored class)` (player sprite + HUD portrait re-derive; `from_dict()` deliberately doesn't emit it) → `DungeonFloor.reload_from_save()` → `queue_free()` (character select skipped entirely). New-game path unchanged.
- **`DungeonFloor.reload_from_save()`**: runs `_load_floor()` against the restored `run_seed`/`current_floor` (floor regenerates fresh from the seeded generator — Phase A restores floor-entry state only), then emits `GameState.floor_changed` (HUD floor label / log clear / compass reset).
- **Companion restore**: `GameState.pending_companion_restore` (set by `from_dict()`) is consumed by `DungeonFloor._restore_companion_from_save()` inside `_load_floor()` (after spawns, before the checkpoint) — rebuilds the Wild Heart companion from `WILD_HEART_COMPANION_STATS[one_with_nature rank]` adjacent to the player start and clamps its HP to the saved value. No-op on normal floor loads (dict empty).

### Autosave triggers (doc §2 — exactly these, no others)
- **Floor entry**: `SaveManager.checkpoint()` at the end of `DungeonFloor._load_floor()` (after all spawns) — snapshots `GameState.to_dict()` into memory (`_snapshot`) and writes it. Also fired on `GameState.class_chosen` (floor 1 is loaded *before* class selection, so class pick is the run-start checkpoint). No-op while `class_selected == false`, after death (`is_game_over`), or after the run ended (`_run_over` — set on `player_died`/`player_won`, cleared on class pick / `load_run()`).
- **Lifecycle**: `SaveManager._notification()` calls `save_run()` on `NOTIFICATION_WM_CLOSE_REQUEST` and `NOTIFICATION_APPLICATION_PAUSED` (Android backgrounding).
- **`save_run()` writes the in-memory floor-entry snapshot, never live state** — quitting mid-floor persists floor-entry state, so mid-floor HP/inventory can't be saved against a freshly regenerated floor (doc §2's dupe/loss rule). Consequence: mid-floor progress (including talent points spent or masteries re-picked since floor entry) is lost on load — accepted MVP limitation.

### Serialization (Phase A schema, doc §4)
- `save_run()` writes `{"save_version": 2}` merged with **`GameState.to_dict()`**: `run_seed`, `rng_state` (gameplay Rng stream position, String — see Rng section), `current_floor`, `player_stats` (`Stats.to_dict()` — scores, level/XP, HP, base damage, rage uses, temp HP, status turns, `known_weapon_masteries`), `talents` (investments, per-tier points, `tier2_unlocked`, `active_tier2_subclass`, Wild Heart forms, Zealot charges, plus small `ability_uses`/`ability_active` id-keyed maps), `inventory` (quickbar/bag as positional arrays of `Item.to_dict()` or null, `equipment` slot dict, `pending_chasm_items`, companion `{alive, current_hp}`), `rest` (`hit_dice`, `short_rests_remaining`).
- `load_run()` applies via **`GameState.from_dict()`** (doc §4.3 order): `start_new_run()` clean slate → class + `apply_class_defaults()` + `give_class_starting_items()` → **talent replay** (`_apply_talent_rank(id, r)` for rank 1..saved per invested talent — abilities are derived state, never serialized as objects) → inventory/equipment/rest → **Stats restored LAST** (so replay one-shots like Danger Sense R3's STR +2 don't double-apply) → `recalculate_stats()` + `_sync_ability_uses()` → per-ability `uses_remaining`/`is_active` patches → UI-refresh signals. `floor_changed` is deliberately NOT emitted — `DungeonFloor.reload_from_save()` drives the floor reload from `run_seed` + `current_floor` and emits it after. Companion save state lands in `GameState.pending_companion_restore`, consumed by `DungeonFloor._restore_companion_from_save()` (see "Continue flow" above).
- **Every serialized class uses hand-written `to_dict()`/`from_dict()`** (`Stats` instance pair, `Item.to_dict()` + `static Item.from_dict()`) — never `store_var()` a Resource. Adding an `Item`/`Stats` field means adding it to both functions.
- Per-floor world state (enemies/doors/traps/fog/floor items/`player_grid_pos`) is NOT serialized in Phase A — the floor reloads fresh from the seeded generator (doc §2 accepted limitation; mid-floor state is Phase B).

### Files
- `user://save/run.json` — active run (versioned JSON, `save_version` first key)
- `user://save/run.json.bak` — previous good save (auto-created on every write)
- `user://save/run.json.tmp` — transient atomic-write staging file

### API
```gdscript
SaveManager.has_save() -> bool   # a parseable, version-compatible run.json (or .bak) exists
SaveManager.checkpoint()         # snapshot GameState.to_dict() into memory + write (floor entry / class pick)
SaveManager.save_run()           # atomic write of the SNAPSHOT: .tmp → rotate old save to .bak → rename into place
SaveManager.load_run() -> bool   # parses + fully repopulates GameState via from_dict(); caller drives the floor reload
SaveManager.delete_save()        # removes run.json + .bak + .tmp and clears the in-memory snapshot
SaveManager.v2i_to_arr(v) / SaveManager.arr_to_v2i(a)  # shared Vector2i↔[x,y] JSON helpers (static)
```

### Behavior rules
- **Permadeath**: `_ready()` connects `GameState.player_died` and `player_won` → `delete_save()`.
- **Never crashes on a bad file**: unreadable/unparseable/unknown-version saves fall back to `.bak`, then to "no run" (`{}`/false). Saves with `save_version > SAVE_VERSION` (newer build) are refused.
- **Migrations**: `_migrations: Dictionary` of `save_version → Callable` upgraders, applied in a loop until current. Dev-phase policy: a missing migrator silently discards the save (doc §7). Existing: v1→v2 (adds `rng_state`; migrator just stamps the version — `from_dict()` re-seeds from `run_seed` when the key is absent).
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
