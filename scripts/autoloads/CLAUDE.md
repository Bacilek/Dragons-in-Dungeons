# scripts/autoloads

Core singletons — loaded at engine start, affect the entire game. Files: `rng.gd`, `game_state.gd`, `turn_manager.gd`, `audio_manager.gd`, `save_manager.gd`, `rewind_manager.gd`. (`Rng` is registered FIRST in project.godot — `GameState._ready()` → `start_new_run()` calls `Rng.reseed()`, so it must already exist.)

`game_state.gd` (3300+ lines) is mid-refactor into smaller pieces, same "extract a static-func
`RefCounted` helper" pattern `scripts/items/CLAUDE.md`'s `WeaponTooltip`/`ArmorTooltip` already
established — pulled out purely to make the file more readable, no behavior change. `talent_icons.gd`
(`TalentIcons`, not an autoload — just a plain class, `class_name`-addressable like `WeaponTooltip`)
is the first piece: every icon lookup table (`TALENT_ICON_FLAT`/`TALENT_ICON_FOLDER`/
`RANGER_TALENT_ICON_FLAT`/`WILD_HEART_FORM_ICON`/`WILD_HEART_SLEEPER_ICON`/
`WILD_HEART_COMPANION_ICON`) plus the resolution logic, called via `TalentIcons.resolve(id, rank,
current_rager_form, current_sleeper_form)`. `GameState.talent_icon_path(id, rank)` is now a
1-line delegator to it — every other file already only ever called that function, never the dicts
directly, so no other call site anywhere needed to change. Second piece: `equip_requirements.gd`
(`EquipRequirements`) holds the pure equip-gating checks — `can_equip_shield(item, stats,
equipment)`, `can_equip_armor(item, stats)`, `can_equip_weapon(item, stats)`,
`armor_change_turns(new_item, old_item)`, and the
`ARMOR_CHANGE_TURNS` table itself. `GameState.can_equip_shield()`/`can_equip_armor()`/
`can_equip_weapon()`/`_armor_change_turns()` are 1-line delegators; `GameState.ARMOR_CHANGE_TURNS` is kept as a const
alias (`= EquipRequirements.ARMOR_CHANGE_TURNS`) since `ArmorTooltip.build()` reads it directly —
same "no external call site needs to change" bar as the icon extraction. The log-emitting wrappers
(`log_shield_equip_blocked()`/`log_armor_equip_blocked()`/`log_weapon_equip_blocked()`) stayed on `GameState` since they need
its `combat_message` signal, which a pure static-func class deliberately doesn't have access to.
`can_equip_weapon(item, stats)` hard-blocks equipping a `weapon_category` "Simple"/"Martial" weapon
(into Main Hand, Ranged, OR Off-hand) without the matching `Stats.proficient_simple_weapons`/
`proficient_martial_weapons` flag — checked at every equip entry point (`GameState.equip()`,
`move_item()`, and `inventory_overlay.gd`'s `_fits_slot()` drag-preview gate), same hard-block
shape as `can_equip_shield()` (unlike the attack-roll proficiency bonus in
`CombatMath.weapon_prof_bonus()`, which only drops a bonus rather than blocking the equip).
Third piece: `talent_tiers.gd` (`TalentTiers`) holds `TIER_LEVEL_RANGES` +
`tier_for_level(lv)`/`tier_unlocked(tier, tier2_unlocked, tier3_selected_class, character_level)`
— `GameState.tier_for_level()`/`tier_unlocked()` are 1-line delegators, `GameState.
TIER_LEVEL_RANGES` a const alias. Fourth piece: `scripts/items/item_stack_split.gd`
(`ItemStackSplit`) holds the durability-stack-splitting logic (see `scripts/items/CLAUDE.md`'s
"Mixed-durability stacking") — filed under `scripts/items` instead of `scripts/autoloads` since it
operates purely on an `Item` with zero `GameState` state involved, so it's thematically an item
concern, not a game-state concern, even though the extraction started from `game_state.gd`.
`GameState._should_split_for_equip()`/`_split_one_unit()` stay as delegators under their original
(underscore-prefixed) names rather than being renamed to `ItemStackSplit.split_one_unit(item)` at
every call site, because `player_throw_tool.gd` already calls `GameState._split_one_unit(weapon)`
directly.

Fifth piece: `scripts/items/attunement_rules.gd` (`AttunementRules`) holds the attunement-gating
logic (`MAX_ATTUNED_ITEMS`, `attunable_items()`, `attuned_count()`, `can_attune()`,
`item_bonus_active()` — see `scripts/items/CLAUDE.md`'s "Attunement") — filed under `scripts/items`
like `ItemStackSplit`, same reasoning (it's fundamentally about `Item.requires_attunement`/
`is_attuned`, not `GameState`-specific). `GameState`'s versions of these keep their exact original
names since `scripts/ui/attunement_picker.gd` calls several directly.

More subsystems will move out the same way over time — this is an incremental, ongoing
decomposition, not a one-shot finished refactor. (Stateful, turn-tick-coupled subsystems like
armor-change's own countdown or scroll-learning are intentionally NOT extracted this way — their
fields are read directly by other files, e.g. `player.gd`'s turn ticker, so pulling them out would
mean either breaking that direct-field-access convention or adding a pass-through property for
every field, which trades a smaller file for more boilerplate. Only worth it if a future pass
converts those call sites too — not attempted yet.)

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
- **Cosmetic randomness stays on the global unseeded RNG and is never migrated** (camera shake in `player_vfx.gd`, tween/particle jitter).
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
| `gold_changed` | `new_amount: int` | `add_gold()`/`spend_gold()` (also re-emitted by `spend_gold()` while invincible, and by `from_dict()`) |
| `spell_slots_changed` | — | Wizard spell-slot pool mutated (`consume()`, `on_long_rest()`, level-up grant) or a spell prepared/unprepared — see "Leveled spells / spellbook" below |
| `special_slot_changed` | — | `set_special_slot()`/`clear_special_slot()` — the Special quick-cast slot's assigned spell changed |
| `light_source_changed` | — | `set_light_source()`/`clear_light_source()` (Light cantrip) — `dungeon_floor.gd` connects this to force an immediate `update_fog()` call |
| `death_save_started` | — | a 0-HP hit enters the death-save sequence — `hud.gd` spawns `scripts/ui/death_save_overlay.gd` |
| `death_save_rolled` | `die: int, result: String, successes: int, failures: int` | each ~1s death-save roll — see "Death save sequence" below |
| `death_save_finished` | `revived: bool` | sequence resolved — overlay frees itself; `player_died` already fired first if not revived |

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
**Mute**: `AudioManager.toggle_mute()` / `set_muted(bool)` mute the entire `"Master"` audio bus via `AudioServer.set_bus_mute()` — covers music and every SFX player in one call since they all route through `"Master"`. State lives on the autoload (`is_muted`, `mute_changed` signal) so it survives floor/level transitions for free, and is additionally persisted to `user://audio_settings.cfg` (loaded in `_ready()`) so it survives app restarts. Two UI entry points, both listening to the same `mute_changed` signal: `scenes/ui/hud.tscn`'s `MuteButton` (top-right corner, small/icon-only — `hud.gd._on_mute_pressed()`/`_on_mute_changed()`) and a labeled button at the bottom of the F3 debug panel's main page (`debug_panel.gd._on_mute_pressed()`/`_on_mute_changed()`, below "Give 100 Gold" — added as a more-discoverable second spot since the HUD corner button is easy to miss).

### Key state fields
```
short_rest_open: bool        # blocks ALL player input while true
short_rest_active: bool      # a rest is in progress (ticking turns) — short OR long, see long_rest_pending
long_rest_pending: bool      # true when the in-progress short_rest_active countdown is actually a long rest
armor_change_active: bool    # body-armor equip/unequip/swap in progress — ticked in player.gd, see scripts/items/CLAUDE.md's "Body armor". begin_armor_change() kicks the first countdown tick itself (TurnManager.begin_player_action()/on_player_action_complete()) so the wait starts immediately instead of needing another keypress first.
armor_change_turns_remaining/armor_change_total_turns: int  # 5/10/15 turns per Light/Medium/Heavy (ARMOR_CHANGE_TURNS), keyed by the heavier item involved
scroll_learn_active: bool    # Wizard "Learn" RMB scroll interaction in progress — ticked in player.gd, see scripts/items/CLAUDE.md's "Learn". begin_scroll_learn() likewise self-kicks the first tick.
scroll_learn_turns_remaining/scroll_learn_total_turns: int  # 2 real turns per spell level; a cantrip learns instantly, never sets this
scroll_learn_spell_id: String # the spell being studied; scroll_learn_item: Item — consumed only on GameState.complete_scroll_learn()
hit_dice: int                # available dice (refills to max_hit_dice() in long_rest(); gain_exp() also grants the level-up's +1 die to CURRENT hit_dice, not just the cap, so it's usable in a short rest before the next long rest)
short_rests_remaining: int   # 2 per long-rest cycle, resets in long_rest() (NOT advance_floor)
LONG_REST_FOOD_COST: int     # const 100 — combined Item.food_value required to long rest
LONG_REST_TURNS: int         # const 20 — turns a long rest takes (short rest: SHORT_REST_TURNS = 5)
talent_picker_open: bool     # blocks ALL player input while talent picker is visible
mastery_picker_open: bool    # blocks ALL player input while the Mastery Picker is visible (scripts/ui/mastery_picker.gd)
mastery_reselect_used_this_long_rest: bool  # long-rest hub's Weapon Masteries reselect is limited to once per cycle — set true when a Swap-mode discard+pick round completes, reset false in long_rest()
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
gold: int                    # the wallet (special-rooms-economy-design.md §2, session 7a) — plain int counter like hit_dice
mold_target_floor: int       # rolled once via Rng.range_i(1,4) in start_new_run() — the floor DungeonFloor._spawn_mold() guarantees one Mold on (scripts/world/CLAUDE.md, scripts/items/CLAUDE.md's "Mold")
mold_spawned: bool           # set true once _spawn_mold() places its one guaranteed Mold — prevents re-spawning on floor reload/save-load
blacksmith_panel_open: bool  # blocks ALL player input while blacksmith_panel.gd is visible (scripts/ui/CLAUDE.md)
shop_open: bool              # blocks ALL player input while shop_panel.gd is visible (scripts/ui/CLAUDE.md)
spell_learn_pending: bool    # Wizard level-up spell-learn picker should be shown (leveled-spells-and-slots-plan.md §4.1)
mastery_learn_pending: bool  # a level-up raised Stats.mastery_cap() — hud.gd should spawn mastery_picker.gd immediately
spell_learn_choices: Array[String]  # up to 3 rolled candidate spell ids for that picker
spell_learn_picker_open: bool       # blocks ALL player input while spell_learn_picker.gd is visible
spellbook_open: bool                # blocks ALL player input while spellbook_overlay.gd (R key) is visible
special_slot_spell_id: String        # "" = none; the Special quick-cast slot's assigned spell (cantrip or leveled), see below
light_source_pos: Vector2i           # (-1,-1) = none active; Light cantrip's lit-object position — see scripts/world/CLAUDE.md's "FOV" section
light_source_color: Color            # Light cantrip's randomized glow color
light_source_item: Item              # the specific floor Item touched at cast time; auto-clears the light when it's no longer at light_source_pos (picked up/removed)
```

**Leveled spells / spellbook** (implemented; design doc shipped and was deleted from `docs/architecture/`): Wizard-only,
built on top of the cantrip slice — see `scripts/entities/CLAUDE.md`'s "Wizard leveled spells"
section for the full walkthrough (slot table, casting, AoE, persistence). Key `GameState`
functions: `learn_spell(id)` (spellbook growth — level-up picker or scroll), `set_spell_prepared(id,
bool)` (Spellbook overlay click-toggle, hard-capped at `SpellcasterState.prepared_max()`),
`place_spell_in_slot(id, index)` (Spellbook drag-and-drop onto a specific ability-bar slot),
`swap_ability_slots(a, b)` (in-game ActionBar reorder without opening the Spellbook — works for
any ability, not spell-specific; `hud.gd`'s own press-and-drag, see `scripts/ui/CLAUDE.md`'s
"In-bar reorder drag"), `_build_spell_ability(id)`/`_remove_ability_by_id(id)` (the add/remove primitives every spell-
ability-bar mutation funnels through), `_rebuild_spell_ability_bar()` (save-load replay —
reconciles the ability bar against the just-restored known/prepared lists),
`_roll_spell_learn_choices()` (called from `gain_exp()`'s level-up block, WIZARD only). Slot-pool
refill hooks into the existing chokepoints: `long_rest()` gains one
`player_stats.caster.slot_pool.on_long_rest()` line; `gain_exp()` snapshots the pool's
`max_slots()` before applying a level-up and calls `grant_new_slots_on_levelup(old_max)` after, so
newly-grown slots are immediately usable rather than empty until the next long rest.

**Special quick-cast slot**: `set_special_slot(spell_id) -> bool` (validates caster exists and
`known_spells.has(spell_id)`) / `clear_special_slot()` — a single spell reference independent of
`player_ability_bar` and `prepared_spells`, assigned from inside the Spellbook overlay (see
`scripts/ui/CLAUDE.md`), displayed read-only in the Inventory overlay next to Ranged, cast with
Alt+click via `PlayerSpellcasting.cast_direct()` (see `scripts/entities/CLAUDE.md`'s "Wizard
leveled spells"). `choose_cantrip()` also calls this automatically on the character-creation
cantrip pick (both the Custom `cantrip_select.gd` flow and premade Jace), so a fresh Wizard
always starts with their cantrip already loaded into Alt+click. Persisted as a top-level `"special_slot_spell_id"` string in `to_dict()`/
`from_dict()` (same pattern as `gold`); restored last in `from_dict()`, after `Stats.from_dict()`
repopulates `known_spells`, and silently clears if the saved id is no longer known.

**Gold economy (session 7a)**: `add_gold(amount)` (ignores ≤ 0) and `spend_gold(amount) -> bool` are the only mutation points — both emit `gold_changed(gold)`. While `invincible`, `spend_gold()` succeeds WITHOUT decrementing (consumption-skip invariant; earning is unaffected). Reset to 0 in `start_new_run()`; persists across floors (`advance_floor()` never touches it). Serialized as a top-level `"gold"` key in `to_dict()`/`from_dict()` (`int(d.get("gold", 0))` — old saves load as 0). Gold piles on the floor are `Item.Type.GOLD` items whose `gold_value` is the pile size — picked up straight into the wallet by `PlayerActions.check_pickup()`, never into the inventory. **Spend sinks**: the Blacksmith's random-weapon crafting (`scripts/ui/blacksmith_panel.gd`, `BLACKSMITH_GOLD_COST` = 50) and, since session 7e, the ShopRoom's Buy tab (`scripts/ui/shop_panel.gd`) — the first real two-directional gold sink/source, since Shop also buys items back from the player via its Sell tab (`GameState.remove_item()` + `add_gold()`).

**Ability usability check**: `GameState.is_ability_usable(ab: Ability) -> bool` — beyond the generic `uses_remaining`/`uses_max` pool (`Ability.has_uses()`), several free base-abilities (`uses_max == 0`, always "has uses") are additionally gated by external state that isn't visible from the `Ability` resource alone: `"frenzy"` needs `is_raging` and `not berserker_frenzy_used`, `"limit_break"` needs `not scarred_warrior_limit_break_used`, `"zealot_strike"` needs `hit_dice > 0`, `"grip_of_the_forest"` needs `is_raging`. `"hunters_mark"`'s own case (bugfix, 2026-08-07) checks the SAME resource chain `PlayerRangerTalents.commit_mark()` does — not just the round cooldown — before reporting usable: a live already-marked target (free re-click) OR `hunters_mark_free_recast_available` OR `hunters_mark_uses_remaining > 0` OR a real 1st-level Ranger spell slot; previously it only ever checked `not hunters_mark_cast_this_round`, so the slot silently never greyed out even at 0 free uses AND 0 spell slots. Used only by `hud.gd`'s ability-bar greying (`scripts/ui/CLAUDE.md`) — never gates the actual activation logic, which each ability's own function (`player_berserker.gd` etc.) still owns independently.

**Weapon mastery selection**: `can_select_mastery(name) -> bool` / `toggle_mastery(name) -> bool` mutate `player_stats.known_weapon_masteries` (the single source of truth every combat mastery gate reads — no parallel copy on `GameState`). Hard-blocks selecting past `Stats.mastery_cap()`; deselection always allowed. Emits `known_masteries_changed`. `discard_mastery(old_name)` (long-rest Swap mode's step 1 — just removes, rolls nothing; the picker itself runs a mandatory "pick 1 of 3" round and calls `toggle_mastery()` for the replacement — see `scripts/ui/CLAUDE.md`'s "Mastery picker" section) is the only other mutator. Used by `scripts/ui/mastery_picker.gd`.

**Status chokepoint**: `apply_player_status(type: String, turns: int) -> bool` — single entry point for all player status/debuff application. If Rager R1 is active and raging, applies a % chance to negate and returns false (caller skips log). On success: sets `player_stats.{type}_turns = maxi(existing, turns)` and emits `player_status_changed`. All trap, enemy, terrain, and rotten-meat callers must use this — never set `player_stats.{status}_turns` directly.

**Custom character-creation Back navigation** (see `scripts/ui/CLAUDE.md`'s "Custom character
creation: Back navigation + summary screen" for the full walkthrough): `class_selected` is no
longer set `true` inside `class_select.gd` — it stays `false` for the entire Custom flow (player
input is hard-gated on it) until `character_summary.gd`'s final "Yes" confirm. Supporting state,
transient/onboarding-only, never serialized: `pending_point_buy_scores`/`pending_background_bonus`
(`Dictionary`, empty = "not yet confirmed this flow", written by `point_buy_select.gd`/
`background_select.gd`'s own Confirm, read by that same screen's `_ready()` to prefill when
re-opened via Back). `GameState.reset_for_class_reselect()` wipes equipment/ability-bar/quickbar/
bag/talents/masteries and re-grants the generic starting items whenever `class_select.gd`'s confirm
handler runs (including re-picking a DIFFERENT class after backing up to it) — without this,
`give_class_starting_items()`'s own idempotency guard would silently no-op on the second call and
leave the old class's gear equipped. **Weapon masteries and starting cantrips/spells are picked
AFTER `character_summary.gd`'s "Yes, I'm Ready!"** (direct owner request — removes the "Back ->
reconfirm race select -> reroll" cheese that existed when those pickers ran before the final
confirm), so `character_summary.gd`'s own "Take Me Back" always reopens `race_select.gd` — there's
no longer a `pending_summary_return_scene` to track, and neither `mastery_picker.gd` nor
`cantrip_select.gd` has a Back button in this post-spawn mode. See `scripts/ui/CLAUDE.md`'s
"Mastery picker"/"Cantrip / starting-spell picker" sections.

**`give_race_starting_items()` / `_restore_race_ability_bar()`**: Dragonborn-only today (Breath
Weapon at level 1, Draconic Flight at level 5) — see `scripts/entities/CLAUDE.md`'s "Dragonborn"
section for the full mechanism. `give_race_starting_items()` is called once by `choose_race()` (sets
starting uses); `from_dict()` calls the read-only `_restore_race_ability_bar()` counterpart instead
(after `Stats.from_dict()` has already restored the real saved uses) so a save/load never resets
`breath_weapon_uses_remaining` back to full.

**`choose_race()` re-emits `player_hp_changed`**: `apply_race_defaults()` can change `max_hp` (Dwarf's +1/level, including level 1 — see root `CLAUDE.md`'s "Race system"), so `choose_race()` emits `player_hp_changed(current_hp, max_hp)` itself after applying race defaults, rather than relying on whichever earlier signal the calling onboarding screen fired (both `character_select.gd`'s premade path and `point_buy_select.gd`'s confirm emit it with the PRE-race value, since race is chosen after).

**Onboarding stats must be correct before the player's first move, not just before the first real action**: `DungeonFloor._load_floor()` computes the very first `update_fog()` (FOV/darkvision) at floor-load time, before ANY Custom-path onboarding screen (point buy/background/race) has run — and `hud.gd`'s AC label only refreshes on `equipment_changed`/`player_status_changed`/`player_turn_started`, none of which point buy/background/race used to fire. Bugfix: `point_buy_select.gd._on_confirm()` and `background_select.gd._on_confirm()` now each also call `GameState.equipment_changed.emit()` right after applying their score changes (AC depends on ability scores), and `choose_race()` itself emits `equipment_changed` after `race_chosen` (darkvision/FOV bonus depends on race) — `dungeon_floor.gd`'s existing `equipment_changed` listener (`update_fog(_fov_player_pos)`) and `hud.gd`'s existing `_update_ac_label()` listener both already exist for the equip-gear case, this just reuses them so a fresh character's AC/darkvision/FOV are right at init instead of only updating after the player's first turn.

**Tier 2 unlock + subclass selection (boss-gated)**: Tier 2 does NOT unlock by level. Every boss kill emits `boss_defeated(boss_id)` (from `player.gd._finish_kill()` and `DungeonFloor.resolve_push()`'s chasm path); GameState's own `_on_boss_defeated()` ignores everything except `TIER2_GATING_BOSS_ID` ("big_demon", floor 5). On that kill: Barbarian (has subclasses) with `not subclass_chosen` emits `subclass_choice_required` — hud.gd spawns `scripts/ui/subclass_select.gd` (blocking, non-dismissable overlay showing all four subclasses); its confirm calls `choose_subclass(name)` which sets `active_tier2_subclass` + `subclass_chosen = true` and calls `unlock_tier2()`. Other classes (or an already-made choice) call `unlock_tier2()` directly. `unlock_tier2()` sets `tier2_unlocked` and runs `_setup_tier2_for_active_subclass()` (dispatches to the four `_setup_X_tier2_talents()` — all implemented). `choose_subclass()` is one-time: it no-ops once `subclass_chosen` is true. Levels 7–12 fill `talent_points[2]` unconditionally — points earned before the boss kill sit **pending** (the talent picker shows a pending badge) and become spendable the instant Tier 2 unlocks. If the player never kills the gating boss, Tier 2 points stay pending for the rest of the run — intentional, no special handling. If debug Jump-to-Floor skips floor 5, the God-Mode subclass arrows / debug panel unlock button remain the escape hatch.

**Tier scaffolding (Tiers 1–4)**: `TIER_LEVEL_RANGES = {1: [1,6], 2: [7,12], 3: [13,17], 4: [18,20]}` + `tier_for_level(lv) -> int` (returns 0 for level 21+, the only gap) drive point grants in `gain_exp()`. `tier_unlocked(tier) -> bool`: 1 = always; 2 = `tier2_unlocked`; 3 = `tier3_selected_class != -1` and level ≥ 13; 4 = level ≥ 18. `can_invest_talent()` gates on `tier_unlocked(t.tier)` plus `talent_points[t.tier] > 0` (with an extra explicit tier-2 lock guard). Tier 3/4 content is NOT implemented — only the accessor shape exists.

**Debug subclass switching (God-Mode-only override, NOT the player path)**: `TIER2_SUBCLASSES: PackedStringArray = ["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]`. `debug_switch_subclass(direction: int)` — clears tier 2 investments + ability bar entries (including the outgoing subclass's free base ability via `TIER2_BASE_ABILITY_ID`) + `_class_talents` tier 2 entries, then re-runs `_setup_tier2_for_active_subclass()`. Called from talent_picker.gd's subclass arrow buttons (only visible in God Mode); it deliberately does NOT set `subclass_chosen`. Adding another subclass requires a new `match` case here plus its `_setup_X_tier2_talents()`, a `TIER2_BASE_ABILITY_ID` entry if it grants a free base ability, plus a card entry in `subclass_select.gd`'s `SUBCLASSES` const.

**"Try Again" (death → same character, fresh run)**: `character_creation_snapshot: Dictionary`
(empty = none captured) is written once by `snapshot_character_creation()` right when character
creation actually finishes — `character_select.gd`'s premade-card click calls it directly before
`queue_free()`. On the Custom path, masteries/cantrips/starting spells are now picked AFTER
`character_summary.gd`'s "Yes, I'm Ready!" (see "Custom character-creation Back navigation" above),
so the snapshot call moved to wherever that chain actually ends: `character_summary.gd._on_confirm()`
itself for a class with neither (e.g. Monk), or the tail of `mastery_picker.gd._finish_learn()`/
`cantrip_select.gd._on_chosen()` for a class that has one or both — always the last thing that
happens before the character is genuinely done, never mid-pick.
Captures only identity, not run progress: class, final ability scores (post point-buy +
background, read straight off `player_stats` at that moment), race + variant + prof-ability,
`known_weapon_masteries`, and (Wizard only) `caster.known_spells` + `special_slot_spell_id`.
`retry_same_character() -> bool` (called by `scripts/ui/game_over.gd`'s "Try Again" button) replays
those onto a brand-new `start_new_run()` (fresh seed, floor 1, starting items) via the exact same
functions character creation itself uses (`apply_class_defaults()`, `apply_point_buy_scores()`,
`give_class_starting_items()`, `choose_race()`, `choose_cantrip()`/`choose_starting_spell()` with
`silent=true`), then sets `class_selected = true` and re-emits `class_chosen` — same finish-line
shape as a normal character creation, so `SaveManager`'s `class_chosen` hook and
`character_select.gd`'s own `class_selected`-already-true self-free both handle it for free
without any special-casing. Falls back to a plain `start_new_run()` (full character-creation UI)
if no snapshot was ever captured (returns `false`) — `game_over.gd` only shows the "Try Again"
button when a snapshot exists, so this fallback is a defensive no-op in practice, not a real path.
Deliberately NOT a `to_dict()`/`from_dict()` replay (that would drag in run progress — level,
floor, inventory beyond starting gear, RNG stream — the opposite of what a fresh retry wants).

**Rest system**: `advance_floor()` is floor bookkeeping ONLY (floor number, terrain AC reset) — it does not restore anything. `GameState.long_rest()` is the single chokepoint for every long-rest-gated resource: full HP heal, cleared status effects, `rage_uses_remaining`, `hunters_mark_uses_remaining` (Ranger, see `scripts/entities/CLAUDE.md`'s "Ranger class"), `hit_dice = character_level`, `short_rests_remaining = max_short_rests`, Natural Sleeper form lock-in, Zealot `zealot_blessed_charges`/`zealot_zp_charges`, companion heal, `_sync_ability_uses()` (One with Nature charge). Triggered explicitly by the player via the Alt-menu's Long Rest tab (`scripts/ui/short_rest_panel.gd`), never automatically. **Any new "per long rest" resource must be refilled in `long_rest()` and nowhere else** — `advance_floor()` must never regain restore logic. `GameState.total_food_value() -> int` sums `Item.food_value × quantity` across quickbar+bag; `can_long_rest() -> bool` (always true when `invincible`) gates the button; `_consume_food_value(amount)` spends cheapest-value FOOD items first, skipped entirely while `invincible` (so God Mode long rests cost nothing). `long_rest_pending: bool` tells the shared short-rest turn-countdown in `player.gd._on_turn_started()` to call `long_rest()` instead of the short-rest heal when the countdown reaches 0; `rest_interrupt_panel.gd`'s abort path also clears it. Level-up via `gain_exp()` only grants `+1 talent_points_available` and emits `player_leveled_up` — it does NOT reset resources or heal the player.

**Level-up max HP tooltip**: `GameState.gain_exp()`'s "Level up!" chat line wraps the `+N max HP` text in an `[url=hplvl:...]` tag (`Stats.hp_per_level_breakdown()` supplies `die_sides`/`avg`/`con`/`dwarf`/`total`; the meta also carries `n`, how many level thresholds this one `gain_exp()` call crossed, since a single large XP grant can level up more than once) — hover shows the same additive breakdown (hit-die average + CON mod + Dwarven Toughness) that `dmg:`/`heal:` tooltips use for combat numbers. `TooltipFormatters.fmt_hplvl_tooltip()`, dispatched in `hud.gd._format_tooltip()`.

**Concentration break check**: `take_damage_raw()`'s tail calls `_check_concentration_break(actual_damage)` — if `player_stats.concentration_spell_id != ""`, rolls a CON check vs `DC = max(10, actual_damage)` (Blade Ward's own rule, not 5e's usual half-damage DC) and calls `end_concentration(log_msg)` on a fail. Scoped to `take_damage_raw()` callers only (status-tick/trap damage bypass it) — see `scripts/entities/CLAUDE.md`'s "Blade Ward" section. Logs a hoverable roll breakdown on both outcomes (`"Concentration holds"` / `"Your concentration breaks!"`) via a `conc:die=,mod=,total=,dc=,pass=` meta tag — `TooltipFormatters.fmt_conc_tooltip()` (`scripts/ui/tooltip_formatters.gd`), dispatched in `hud.gd._format_tooltip()`'s `"conc"` case — same d20+CON-mod-vs-DC shape as `fmt_save_tooltip()`.

**`GameState.end_concentration(reason_log: String = "")`**: the single chokepoint for ending whatever the player is currently concentrating on — clears `concentration_spell_id` AND that spell's own duration/target fields (not just the id), so switching to a different concentration spell can never leave a stale spell still ticking. Called by `_check_concentration_break()` on a failed CON check, and by every concentration-granting cast site (Blade Ward/Witch Bolt/Expeditious Retreat/Fog Cloud in `spell_effects.gd`) whenever `concentration_spell_id` is already set to a DIFFERENT spell. See `scripts/entities/CLAUDE.md`'s "Concentration (generic mechanism)" section.

**BUGFIX — combat-transient state survived death into the next character**: `is_raging` (and
`rage_turns_remaining`, `berserker_frenzy_used`/`berserker_turns_since_frenzy`,
`masochist_ac_bonus`, `scarred_warrior_limit_break_used`, `bruiser_revive_used_this_floor`,
`player_was_hit_this_turn`/`player_attacked_this_turn`/`enemy_noticed_player_this_turn`,
`fov_radius_bonus`, `psycho_adv_pending`, `battlefield_adv_pending`/`battlefield_adv_expire_turns`,
`fog_cloud_pos`/`fog_cloud_radius`) all live directly on `GameState`, not on `Stats` — so replacing
`player_stats` with a fresh `Stats.new()` in `start_new_run()` (death → "New Run" restart) never
touched them, and e.g. Rage would still show as active in the status tray for a brand-new
character that never activated it. `start_new_run()` now explicitly resets all of these alongside
the pre-existing Wild Heart/terrain resets.

**Rage DR**: `take_damage_raw(amount, ignore_rage, damage_type: String) -> int` — returns actual damage after DR. Physical types ("Slashing"/"Piercing"/"Bludgeoning") are always reduced 50% while raging (baked-in baseline, no longer talent-gated — see `scripts/entities/CLAUDE.md`'s Barbarian class section). Scarred Warrior's Born in Blood talent applies an additional Bloodied-based modifier afterward. All callers must pass `damage_type`; missing/empty type bypasses DR. **`invincible` still sets `player_was_hit_this_turn`**: the function's `invincible` branch returns 0 without touching HP, but (if the hit was physical) still flips `player_was_hit_this_turn` — every caller (currently only `enemy.gd._attack_player()`, which now always calls this function rather than short-circuiting to 0 itself) is only ever invoked on a connecting hit, so this is safe and keeps turn-based triggers keyed off that flag (e.g. Battlefield Expert R3's free Side Step — `scripts/entities/CLAUDE.md`) working in God Mode instead of silently never firing.

### Death save sequence

`GameState.check_player_death()` is still the single chokepoint every player-damage path funnels
through (`take_damage_raw()`'s tail, plus the handful of direct callers in `dungeon_floor.gd`/
`player_berserker.gd`) — but a 0-HP hit no longer sets `is_game_over` immediately. Bruiser R3's
"refuse to fall" and Orc Relentless Endurance still intercept first, exactly as before (both are
guaranteed 1-HP holds, unaffected by this feature). Past those, `begin_death_save_sequence()` runs
instead of instant death:

- **`GameState.is_dying: bool`** — set `true` for the whole sequence. Threaded into every one of
  `player.gd`'s `is_game_over` input-gate guard chains as `(GameState.is_game_over or
  GameState.is_dying)` (a blanket find/replace across the file — every site that already refused
  input/aborted a chase/OA loop on game-over now does the same the instant HP hits 0, not just
  after the sequence resolves negatively) plus `hud.gd`'s Tab-toggle guard. Since no further
  player action can begin, `TurnManager` never starts another round either — the turn economy
  stalls for free, no `TurnManager` changes needed beyond one extra guard in
  `_advance_round_or_end()` (stops a Slowed-queued 2nd enemy round from still running once the
  player's already down mid-1st). **Known limitation**: an enemy's own decide/execute coroutine
  already IN FLIGHT when the killing blow lands finishes normally rather than being interrupted
  mid-animation (this engine's turn coroutines aren't designed to be preemptible) — the full-screen
  overlay covers it visually either way, and no NEW round can ever start once it's covered.
- **The roll**: `_run_death_save_sequence()` (an async `GameState` function, fired-and-forgotten
  from `begin_death_save_sequence()` — GameState is an autoload `Node`, so `await
  get_tree().create_timer(...)` works the same as anywhere else) rolls a bare, **unmodified**
  `Rng.roll(20)` every ~1.1s (`DEATH_SAVE_ROLL_INTERVAL`, first roll after `DEATH_SAVE_FIRST_DELAY`
  = 0.9s) until the verdict is known: nat 1 → 2 failures, 2-9 → 1 failure, 10-19 → 1 success, nat
  20 → instant revive regardless of the accumulated count. First to 3 (successes or failures) wins
  otherwise. **Deliberately no modifiers** — no ability mod (5e RAW death saves have none by
  default), no Halfling Luck reroll, no Heroic Inspiration, no Exhaustion penalty (see root
  CLAUDE.md's "Exhaustion") — the outcome bands are exact raw-die ranges by design; adding a flat
  modifier would need to shift the DC-10-equivalent split without touching the nat-1/nat-20
  special cases, which RAW itself never does either. `Rng`, not global random, per the project's
  own randomness rule.
- **Resolution**: `_end_death_save_sequence(revived)` clears `is_dying` first (both branches), then
  either sets `current_hp = 1` + logs a survival line (revived, no teleport — same tile, same
  floor, play resumes normally) or runs the exact same `is_game_over = true` / `AudioManager.play`/
  `player_died.emit()` tail `check_player_death()` used to run directly (not revived — the normal
  Game Over flow, `SaveManager`'s permadeath delete-on-`player_died` hook included, fires
  unchanged). **Revival now costs 1 Exhaustion level** (`Stats.exhaustion_level += 1`, see root
  CLAUDE.md's "Exhaustion" / `scripts/entities/CLAUDE.md`'s "Exhaustion" section) — checked BEFORE
  the HP/log/buff lines run, so if this increment would reach level 6 the function instead falls
  straight into the not-revived death tail (no HP-1 set, no Risen from the Dead) — a 6th
  death-save revival kills the character outright, matching 5e 2024's "exhaustion 6 = death" rule.
  Cheat-death holds (Bruiser R3, Orc Relentless Endurance) intercept earlier in
  `check_player_death()` and never reach this function, so they never grant exhaustion.
- **"Risen from the Dead" buff (revived branch only)**: `GameState.risen_from_dead_active = true` —
  total invulnerability (no damage from ANY source: melee/ranged/spell attacks, Opportunity
  Attacks, status-tick DoT, traps, forced-movement wall-slam, even self-inflicted damage like a
  Fireball catching the caster) through the rest of the round the player revives into plus the
  following enemy round, clearing the instant the player's NEXT real round begins.
  `GameState.take_damage_raw()` gates on it exactly like `invincible` (early-return before
  `Stats.take_damage()`, still flips `player_was_hit_this_turn` for turn-based triggers) — this
  alone covers every attack/OA/self-damage/status-tick path, since they all funnel through that one
  chokepoint. The two `dungeon_floor.gd` functions that bypass it entirely (`_apply_trap_damage()`,
  `force_move_entity()`'s wall-slam damage) each carry their own explicit gate. Cleared from
  `player.gd`'s `_on_turn_started()`, inside the `if not came_from_revert:` block — the flag is set
  AFTER the current WAITING_FOR_INPUT round's own `player_turn_started` already fired (death-save
  revival always completes asynchronously, well after `TurnManager` already flipped back to
  WAITING_FOR_INPUT the instant `is_dying` was seen), so the very next real `_on_turn_started()`
  firing genuinely IS "the round after the protected one" and is the correct clear point — not
  serialized, combat-transient like `is_raging`. Status-tray icon `"risen_from_dead"`
  (`hud.gd`/`status_tooltips.gd`).
- **Signals** (`death_save_started`/`death_save_rolled(die, result, successes, failures)`/
  `death_save_finished(revived)`) are the only three GameState exposes for this — `scripts/ui/
  death_save_overlay.gd` (`hud.gd._on_death_save_started()` spawns it, no `.tscn`, built in code
  like `subclass_select.gd`) is their sole listener: full-screen dark dim (screen "greys"), a big
  color-coded rolling d20 number, a BG3-style pulsing "?" placeholder between rolls, and two
  3-pip success/failure rows (green/red filled circles) mirroring a 5e character sheet's own death
  save checkboxes. Frees itself on `death_save_finished` — `player_died` (spawning `game_over.tscn`
  underneath, layer 10 vs. this overlay's layer 30) fires from inside `_end_death_save_sequence()`
  BEFORE `death_save_finished`, so Game Over is already present by the time this overlay clears out
  of its way.

### Equipment slots
`GameState.equipment` dict: keys `"melee"` (Main Hand), `"hand2"` (Off-hand), `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`.
`GameState.equipped_ranged` property returns ranged slot item.
`equip()` auto-routes by `item.is_ranged` (weapons always land in `"melee"`/`"ranged"`, never `"hand2"` — Off-hand is only reachable via explicit drag in `inventory_overlay.gd`). `"hand2"` accepts a Light melee weapon only when Main Hand is also Light — dual-wielding two Light weapons (Handaxe, Dagger) fires a bonus Off-hand attack on every melee swing (`player.gd._try_offhand_attack()`) — see `scripts/items/CLAUDE.md`'s "Dual-wielding". Dragging a stacked durability weapon (`quantity > 1`) onto any equipment slot equips only one unit (`move_item()`'s `_should_split_for_equip()`/`_split_one_unit()`, shared with `equip()`) — see `scripts/items/CLAUDE.md`'s "Dragging a stack".
**Auto-unequip on two-handed equip**: equipping (or drag-dropping) a two-handed weapon into `"melee"` automatically kicks whatever's sitting in `"hand2"` back to the bag first (`GameState._auto_unequip_offhand()`, called from both `equip()` and `move_item()`) — a two-handed Main Hand and an Off-hand item can never coexist anymore, so switching from dual Light weapons to e.g. the Greataxe no longer strands the off-hand weapon equipped.
**Equip is always a free action** — with two exceptions: `equip()`/`unequip()`/`move_item()` never cost a turn (the old `equip_action_taken` signal + `costs_turn` params + `player.gd`'s `_pending_equip_turn` machinery were removed) — swapping gear, including mid-combat, doesn't burn the player's turn. **Shields** are the first exception: a Shield (`Item.is_shield`) entering or leaving `"hand2"` costs 1 turn — see `scripts/items/CLAUDE.md`'s "Shields". **Body armor** (the `"armor"` slot) is the second, much larger exception: equip/unequip/swap takes real multi-turn `GameState.begin_armor_change()` countdown (5/10/15 turns for Light/Medium/Heavy, interruptible like scroll-learning) — see `scripts/items/CLAUDE.md`'s "Body armor".

**Magic item attunement** (`Item.requires_attunement`/`is_attuned`, see `scripts/items/CLAUDE.md`'s "Attunement"): `MAX_ATTUNED_ITEMS` (const, 3), `attunable_items()`, `attuned_count()`, `can_attune(item)`, `attune_item(item) -> bool`, `unattune_item(item)`. `_item_bonus_active(item) -> bool` is the gate `recalculate_stats()` checks before folding a magic item's `bonus_ac`/melee `bonus_damage` in — an unattuned magic item still equips normally, it just contributes neither bonus. Attuning is only ever called from `scripts/ui/attunement_picker.gd`, itself only reachable from the long-rest hub — nothing else may mutate `is_attuned`.

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
TurnManager.get_enemy_list() / set_enemy_list(list)  # read-only snapshot / restore-only rebuild of
                                        # the registered enemy+companion list, in iteration order —
                                        # RewindManager (Phase 2) only; every other caller keeps
                                        # using register_enemy()/unregister_enemy()/clear_enemies()
TurnManager.enemy_actions_this_round    # int, default 1, auto-reset by _process_enemies() — set to 2/0
                                        # right before on_player_action_complete() to grant every enemy
                                        # two actions / zero actions for THIS ONE round (Slowed / a free
                                        # move) without ever calling begin/complete a second time — see
                                        # scripts/entities/CLAUDE.md's "Player movement-speed visual
                                        # consistency". Same "narrow, don't generalize" spirit as
                                        # revert_to_waiting() above.
```

### Signals
`player_turn_started` — phase reaches WAITING_FOR_INPUT (start of a new round, or a reverted free action).
`player_turn_ending` — emitted from `on_player_action_complete()`, right before phase flips to
RESOLVING_ENEMIES — fires once per REAL player action (never for a `revert_to_waiting()` free
action, since that path never calls `on_player_action_complete()` at all). The "end of the
player's turn, before enemies act" hook — used by `player.gd._on_turn_ending()` for Witch Bolt's
per-turn jolt (`scripts/entities/CLAUDE.md`'s "Wizard leveled spells" → Witch Bolt), which needs to
fire at the end of a turn rather than the start of the next one.
`turn_resolved` — after all enemies finish acting, before `_start_player_turn()`.

### Turn sequence
1. Player key → `begin_player_action()` → phase = RESOLVING_PLAYER
2. Action + tween → `on_player_action_complete()` → `player_turn_ending` fires
3. `_process_enemies()` — **decide-then-execute, batched**: calls `decide_turn() -> Dictionary` on
   EVERY registered enemy/companion first, back-to-back, against the identical pre-round world
   state (no movement/attacks/door-opens have happened yet this round) — THEN awaits each one's
   `execute_turn(intent)` sequentially, same order as before. This is what makes the round read as
   simultaneous rather than strictly ordered: an earlier enemy's move (e.g. opening a door) can no
   longer change what a later enemy in the same round was able to see/decide, since that later
   enemy's decision was already locked in. `Enemy`/`Companion.take_turn()` still exists as a thin
   `await execute_turn(decide_turn())` wrapper for any other caller. See `scripts/entities/CLAUDE.md`'s
   "Enemy behavior states" section for `decide_turn()`'s exact contract (reads state + mutates only
   this entity's own fields — never the world). If `enemy_actions_this_round > 1` (Slowed), step 3
   repeats that many times back-to-back via `_process_enemy_round()`/`_advance_round_or_end()`
   before moving on — still inside this same single `_process_enemies()` call, so steps 1/2/4 each
   still happen exactly once no matter how many enemy rounds resolve in between.
4. Phase = WAITING_FOR_INPUT → `player_turn_started` signal fires

Each turn: `Stats.tick_status()` deals status damage. Hunger has been removed — see "Rest system" above.

---

## RewindManager (`rewind_manager.gd`)

"Undo 1 turn" mechanic — **Backspace**, gated on `TurnManager.phase == WAITING_FOR_INPUT` (only
between turns, never mid-resolution). In-memory only, `MAX_SNAPSHOTS = 1` — never touches disk,
unrelated to `SaveManager`'s much coarser floor-entry checkpoint (which is curated and deliberately
excludes most of what a turn-rewind needs — see that section's own "Phase B" note above).

**`RewindManager.seed_baseline()`**: a snapshot pushed OUTSIDE the normal
`TurnManager.player_action_starting` capture point, so Backspace has something to revert to even
before the player's first real (turn-costing) action. **Bugfix**: a free action (drinking a
potion, equipping gear — neither calls `TurnManager.begin_player_action()`, see the "Call-order
rule" bullet below) taken as literally the first thing after entering a floor, or right after a
prior rewind, had nothing to revert to at all — `_snapshots` was empty (only real actions ever
pushed one), so `can_rewind()` correctly refused and logged "Nothing to rewind"; the potion's heal/
consumption, etc. all silently stuck with no way to undo them. Called from two places, both
mirroring `SaveManager.checkpoint()`'s own "everything is set up now" timing and its
`GameState.class_selected` gate (character creation itself mutates `player_stats`/inventory
without ever reloading the floor, so a naive call right after `_load_floor()` alone would capture a
snapshot of the not-yet-finalized default character on floor 1): `DungeonFloor._load_floor()`'s own
tail, right after `SaveManager.checkpoint()`, gated on `class_selected` (skips the pre-
character-creation floor-1 load); and `GameState.class_chosen` (`RewindManager._on_class_chosen()`,
same `class_selected` gate) — covers the moment onboarding genuinely finishes for the Custom path,
where `class_chosen` re-fires from `character_summary.gd`'s confirm exactly when `class_selected`
turns true, same precedent `SaveManager`'s own checkpoint-on-`class_chosen` hook already relies on.
Deliberately NOT hooked to `TurnManager.player_turn_started` — that signal also fires very early
mid-`_load_floor()` (from `TurnManager.reset()`), well before this floor's own player/enemies/props
exist yet, so capturing there would seed garbage. **`rewind()` itself also calls `seed_baseline()`
again right after restoring** (bugfix): popping/restoring the one stored snapshot used to leave
`_snapshots` completely empty until the player's next real action — fine for a single Backspace,
but a second consecutive "free action, then Backspace" (e.g. drink a potion, rewind, drink another,
rewind again) always failed with "Nothing to rewind" even though nothing about the situation had
actually changed. Re-seeding right after a restore keeps Backspace immediately usable again.

### Phase 1 (implemented) — player + TurnManager only
**`Rng`'s gameplay stream position is deliberately NOT captured/restored** (direct owner request,
reversing an earlier version that did) — rewinding and repeating the exact same action (e.g. the
same attack that just missed) now draws a genuinely fresh roll instead of deterministically
replaying the identical miss/damage forever, so rewind can be used as a real "reroll" rather than
being a no-op for outcome purposes. Costs nothing elsewhere: `DungeonFloor._pop_rng` (floor
generation/population) is a wholly separate `RandomNumberGenerator` seeded from `(run_seed,
floor)`, never the `Rng` autoload's own stream, so floor layout/loot stay exactly as reproducible
as before; `SaveManager`'s own serialized `rng_state` is an independent floor-entry checkpoint,
unrelated to this in-memory-only snapshot. `TurnManager.set_enemy_list()` still restores enemy
*iteration order* exactly (load-bearing for who draws which roll first on the next round) — only
the stream's actual position is left wherever it already advanced to.
- **Call-order rule (any turn-costing action)**: `TurnManager.begin_player_action()` must run
  BEFORE the action mutates `player_quickbar`/`player_inventory`/`equipment` — it's what fires the
  `player_action_starting` snapshot this whole mechanism is built on, so anything that mutates
  inventory state before calling it gets that mutation baked into the "before" snapshot instead of
  reverted by it. **Bugfix**: `PlayerThrowTool._throw_weapon()` (`scripts/entities/
  player_throw_tool.gd`) used to split a stacked thrown weapon (quantity > 1 — see
  `scripts/items/CLAUDE.md`'s "Mixed-durability stacking") BEFORE calling `begin_player_action()`
  — the split mutates the ORIGINAL stack's `quantity`/`stack_uses` in place, so for a stack the
  snapshot was already capturing the post-split state and a rewind could never restore the
  un-split stack; throwing the LAST unit of a stack (quantity == 1, no split branch taken at all)
  never hit this and always looked correct, which is what made the bug read as "only works with a
  single copy." Fixed by reordering `begin_player_action()` to the top of the function, before the
  split. `GameState.equip()`/`move_item()`'s own identical stack-split call sites are unaffected —
  neither calls `begin_player_action()` at all for a plain (non-Shield) item, since equip is a
  free action (root `CLAUDE.md`'s "Equip is always a free action"), so their split simply bundles
  into whatever the current undo point already is, same as any other free action.
- **Snapshot point**: `TurnManager.player_action_starting`, a new signal fired from the very top of
  `TurnManager.begin_player_action()` — i.e. right BEFORE any player action (real or a
  `revert_to_waiting()` free action) starts resolving. **Bugfix**: this used to snapshot on
  `player_turn_started` instead, which fires AFTER the action + enemy phase already resolved — by
  the time WAITING_FOR_INPUT comes back around, the "current" state and the just-captured snapshot
  were identical, so pressing Backspace logged its flavor line but visibly changed nothing (no HP
  restored, no position reverted). Capturing pre-action means the snapshot now naturally survives,
  untouched, across the WAITING_FOR_INPUT gap until the player's NEXT action begins — exactly when
  Backspace needs it to still describe "before your last action." A free action's own snapshot
  simply becomes the rewind target for that free action alone once it's the most recent one taken
  (Backspace undoing "just the free action" rather than the whole preceding round is intentional,
  not a gap — see `turn_manager.gd`'s own signal comment).
- **Bugfix — spell slots breaking permanently after a rewind (not fixable even by a long rest)**:
  `StandardSlotPool`/`HalfCasterSlotPool`/`PactSlotPool` (`scripts/items/*_slot_pool.gd`) each hold
  a circular `owner_stats: Stats` back-reference to the ENCLOSING `Stats` object (`Stats -> caster
  -> slot_pool -> owner_stats -> the same Stats`), set once at `apply_class_defaults()`.
  `Resource.duplicate(true)` recursively duplicates every nested Resource it finds, with no
  guarantee it re-links a cycle back to the fresh clone rather than the original/an orphan — after
  the `player_stats.duplicate(true)` + restore round-trip, `owner_stats` could end up wrong or
  null, and `max_slots()`'s `if owner_stats == null: return {}` silently returns an EMPTY slot
  table — which cascades into "no spell slots available" that a long rest can't fix either, since
  `on_long_rest()` just re-derives `remaining` from that same broken `max_slots()`.
  `_restore_snapshot()` now explicitly re-points `restored_stats.caster.slot_pool.owner_stats =
  restored_stats` right after the `player_stats` swap — a cheap, unconditional correctness
  guarantee that doesn't depend on knowing exactly what `duplicate()` did to the cycle.
- **Captured**: `TurnManager.phase`/`enemy_actions_this_round`,
  `GameState.player_stats.duplicate(true)` (a real `Resource.duplicate(true)`, not the curated
  `Stats.to_dict()` — catches every field `to_dict()` deliberately omits, e.g. `witch_bolt_turns`,
  `hex_*`), and `Player.capture_rewind_state()` (grid_pos + the scattered per-turn
  transient fields living directly on `Player`/its composition children — `PlayerBerserker`/
  `PlayerScarredWarrior`/`PlayerZealot`/`PlayerGoliath`/`PlayerHalfling` each expose their own
  `get_rewind_fields()`/`set_rewind_fields()` pair, same "each subclass owns its own field list"
  convention as `to_dict()`; **also captures/restores Rage's own live gate** — `Player._is_raging`/
  `_rage_turns`/`_rage_attacked_this_turn` plus the `$AnimatedSprite2D.modulate` red tint and the
  `GameState.is_raging`/`rage_turns_remaining` UI mirrors, all in one place, since every real
  combat-roll check reads `Player._is_raging`, not the GameState mirror — **bugfix**: rewinding used
  to leave Rage's actual mechanical gate and sprite tint completely untouched regardless of what the
  HUD said), `GameState.player_quickbar`/`player_inventory`/`equipment`
  (each `Item` deep-`duplicate(true)`'d via `RewindManager._dup_item_array()`/`_dup_equipment()` —
  **bugfix**: these three were missing from the original snapshot entirely, so a thrown/consumed
  item correctly vanished off the floor on rewind (props restore covers that) but never came back
  into the quickbar/bag/equipment slot it was thrown/consumed from, and — symmetrically — an item
  freshly picked UP off the floor correctly reappeared on the ground on rewind but also stayed
  duplicated in the quickbar/bag, since nothing had captured their pre-action state at all),
  `GameState.player_ability_bar` (each `Ability` deep-`duplicate(true)`'d via
  `RewindManager._dup_ability_array()`, restored in place by index — **bugfix**: an ability's own
  `uses_remaining`/`is_active` — Rage charges, Hunter's Mark uses, Frenzy's toggle, etc. — used to
  survive a rewind completely unreverted, since nothing captured the ability bar at all),
  `GameState.gold` (**bugfix**: the wallet lives directly on `GameState`, not on `Stats`, so it was
  never covered by the `player_stats.duplicate(true)` capture either — picking up a gold pile and
  rewinding used to put the pile back on the floor while leaving it ALSO already spent into the
  wallet), and a curated list of combat-transient `GameState` fields
  (`RewindManager.REWIND_GAMESTATE_FIELDS` — Berserker/Scarred Warrior/Bruiser one-shot-use flags,
  the `player_was_hit_this_turn`/`player_attacked_this_turn`/`enemy_noticed_player_this_turn`
  per-turn flags, Psycho/Battlefield Expert pending-ADV windows, Wild Heart form state, Zealot
  charges, Fog Cloud/Darkness zone position+radius, Light source position+color, the Special
  quick-cast slot id — **bugfix**: same root cause as Rage above, every one of these lives directly
  on the `GameState` autoload rather than on `Stats`, so none of them were ever touched by a
  rewind even though `root CLAUDE.md`'s own "combat-transient state survived death" bugfix note
  already documented this exact set of fields as GameState-resident, not Stats-resident — captured/
  restored generically via `GameState.get(name)`/`set(name, value)`, no per-field plumbing needed;
  deliberately excludes `player_companion` (owned by `DungeonFloor.restore_rewind_enemies()`'s own
  Companion respawn/despawn handling) and `light_source_item` (a floor `Item` reference invalidated
  by the floor-items wholesale rebuild in `restore_rewind_props()` — a documented minor gap, not a
  crash: a rewound Light cast may just auto-expire on the next `update_fog()` instead of perfectly
  relighting)). Restore mutates `player_quickbar`/`player_inventory`/`equipment`/`player_ability_bar`
  **in place** (loops writing into the existing slots/keys) rather than reassigning
  `GameState.player_quickbar = new_array` — matches `SaveManager`'s own `_dicts_into_item_slots()`
  restore convention, so anything that might hold onto the live container reference (not just
  re-reading `GameState.player_quickbar` fresh every time) still observes the change.
- **Restore policy for live-`Enemy`-reference `Stats` fields** (`hunters_mark_target`,
  `witch_bolt_target`, `ray_of_enfeeblement_target`, `hold_person_target`, `hideous_laughter_target`,
  `hex_target`, `frightened_source`, `ensnaring_strike_target`): ended unconditionally on
  restore — these concentration/targeting effects simply end on rewind, matching existing
  save/load precedent (never serialized either) rather than trying to re-resolve a reference across
  a rewind. **Bugfix**: this used to just null the target reference itself and stop there, leaving
  its matching `_turns` duration counter and `Stats.concentration_spell_id` still pointing at the
  now-target-less spell (e.g. the status tray kept showing a live "Concentrating: Witch Bolt"
  countdown, or the player still read as Frightened via a lingering `frightened_turns > 0`, even
  though the reference backing either effect was already gone) — this is the specific shape of bug
  behind "stavy/debuffy zůstávají stejné jako před rewindem" reports. The 7 concentration-mechanism
  ones (`RewindManager.LIVE_REF_CONCENTRATION_SPELLS`) are now torn down via `GameState.
  end_concentration()` — the exact same function every real cast-a-different-spell/failed-CON-check
  call site already uses — whenever the restored `concentration_spell_id` is one of them, so the
  counter/target/id all clear together; every OTHER concentration spell (Fog Cloud, Darkness, Blade
  Ward, Expeditious Retreat, Detect Magic, Pass Without Trace, Invisibility, Faerie Fire) holds no
  live Enemy reference at all and is deliberately left alone, since its state already round-trips
  correctly through the plain `Stats`/`GameState` field capture. Frightened isn't part of the
  concentration mechanism, so it's handled as its own explicit pair: `frightened_source = null` AND
  `frightened_turns = 0` together.
- **`Player`'s own additional per-turn transient fields** (`_eagle_free_move_used`,
  `_ironwood_bark_bonus_pending`, `_hook_mode_active` [Grip of the Forest arm state],
  `_hunters_mark_mode_active`, `_expeditious_retreat_move_used_this_turn`) are captured/restored
  alongside Rage — same root cause as Rage's own fix above, plain `Player` script fields that
  `player_stats.duplicate(true)` never touches.
- **Floor-scoped**: `DungeonFloor._load_floor()` calls `RewindManager.clear()` at the very top —
  a snapshot can never survive a floor transition.
- Player finds the live `Player` node via `get_tree().get_first_node_in_group("player")` —
  `Player._ready()` calls `add_to_group("player")`, same convention as `DungeonFloor`'s own
  `"dungeon_floor"` group.

### Phase 2 (implemented) — enemies + companions
- `Enemy.to_dict()`/`from_dict()` (`scripts/entities/enemy.gd`) — a hand-written pair mirroring
  `Stats.to_dict()`'s convention, deliberately narrower than a full field dump: `stats.max_hp`/
  `armor_class`/etc are always re-derivable from `_type` (the pool dict, looked up by `enemy_id`)
  + the current floor via `_apply_stats()`, so only `stats.current_hp` is captured, not a cloned
  `Stats`. Live Node references (`escape_from`, `_thrown_weapon_lodged_target`, `frightened_source`)
  are dropped on restore — same "ends on rewind" policy as the player-side live-`Enemy`-reference
  `Stats` fields. `Companion.to_dict()`/`from_dict()` (`scripts/entities/companion.gd`) is a much
  smaller in-place-only pair — **no respawn support**: a Companion that dies during the rewound
  turn stays dead (its identity is tied to Wild Heart's rank-based `WILD_HEART_COMPANION_STATS`,
  not a simple pool lookup like `Enemy.enemy_id` — documented gap, not built this pass).
  **Bugfix**: `Enemy.from_dict()` restored `stats.current_hp` correctly but never called
  `update_hp_bar()` afterward (`Companion.from_dict()` already did) — an enemy's HP data reverted
  correctly on rewind while its visible health bar sprite silently kept showing the pre-rewind,
  post-damage value until something else happened to touch it (e.g. its next turn/hit).
- `DungeonFloor.capture_rewind_enemies()`/`restore_rewind_enemies()` — captures every node in
  `TurnManager.get_enemy_list()` (a new read-only accessor; `TurnManager.set_enemy_list()` is the
  matching restore-only rebuild — **never call either outside a rewind restore**, everywhere else
  keeps using `register_enemy()`/`unregister_enemy()`/`clear_enemies()`), in that exact order —
  load-bearing, since `_process_enemy_round()`'s own iteration order determines `Rng`-stream
  consumption order (see this file's `Rng` section). Restore policy: a snapshot entry whose
  `instance_id` is no longer alive (died this turn) is respawned via `enemy.tscn` +
  `Enemy.configure(pool_entry)` (looked up by `enemy_id`/`boss_id` across `ENEMY_POOL`/
  `BOSS_POOL`) then `from_dict()`'d; a live node not in the snapshot (a mid-turn summon — e.g. Wild
  Heart's own companion, which shares this same `TurnManager` registration path) is despawned;
  everything else is restored in place. `TurnManager.set_enemy_list()` rebuilds the registration
  list to match the snapshot order exactly.

### Phase 3 (implemented) — floor props
`DungeonFloor.capture_rewind_props()`/`restore_rewind_props()` cover `_traps`/`_dispensers`/
`_doors`/`_barrels`/`_webs`/`_burning_grass`/`_floor_items`/`_pending_thrown_weapon_drops`/**grass**.
Sprite/
texture Node references are stripped from the captured dicts (not serializable, not needed —
every prop's own sprite node persists across the turn in the common case) and the surviving
fields are written straight back onto the existing dict entries, with the sprite's own
tint/texture synced manually (bypassing `open_door()`/`lock_door()`/etc's own guard conditions and
audio side effects — this is a silent state rewind, not a replayed player action). **Barrels and
webs that were fully destroyed mid-turn (a direct hit dropping a barrel to 0 HP; a web's STR-check
escape) DO respawn**, reusing the same `_place_barrel()`/`spawn_web()` helpers `_spawn_barrels()`/
`Enemy._execute_cast_web()` already call; a web spawned mid-turn (Spider's Web ability) that isn't
in the snapshot is torn back down via `destroy_web()`. **Floor items are torn down and rebuilt
wholesale** (`remove_floor_item()` for every currently-occupied tile, then `place_item_on_floor()`
per snapshot entry) rather than diffed — pickup/drop genuinely adds/removes stack entries, so a
full rebuild is simpler and safer. `_pending_thrown_weapon_drops` and `_burning_grass` are plain
dict/array data with no Node references, duplicated directly.

**Grass (bugfix — this used to not be captured at all, so a trampled GRASS tile never grew back on
rewind)**: `capture_rewind_props()`'s `"grass"` entry is a plain `Array[Vector2i]` of every tile
that's currently `GRASS` — a full scan of `_data.grid` (cheap, ≤48×48, once per real player
action). `TRAMPLED_GRASS` never spontaneously reverts to `GRASS` on its own in normal gameplay, so
that's the only direction that ever needs tracking: `restore_rewind_props()` calls
`DungeonFloor.restore_grass(pos)` (the exact mirror of `destroy_grass()` — flips `_data.grid` and
the `_grass_layer` tilemap cell back) for every captured position that's since become
`TRAMPLED_GRASS`. Also calls `update_fog(_player.grid_pos)` once at its own tail — grass (like a
door) blocks LOS, and `restore_rewind_enemies()`'s own `update_fog()` call (earlier in
`RewindManager._restore_snapshot()`) already ran against the PRE-restore door/grass state, so a
second recompute here keeps vision correct immediately instead of waiting for the player's next
real turn.

**Door open/close is now also actually undoable (bugfix)**: `player.gd`'s `_try_move()` (WASD) and
`_execute_queued_path()`'s regular queued-path loop both used to call `DungeonFloor.open_door()`/
`unlock_door()` *before* `TurnManager.begin_player_action()` — since that's what fires
`RewindManager`'s snapshot, the door was already open by the time the "before" state was captured,
so a rewind could never put it back to closed. Both call sites now split door handling into a
read-only DECISION phase (locked-door checks, sets `_door_will_open`/`_door_will_unlock` bools, no
mutation) that runs where the old code used to mutate, and a separate MUTATION phase
(`open_door()`/`unlock_door()`, gated on those bools) moved to right after
`begin_player_action()`. The `is_walkable(target)` check in between also gained a `not
_door_will_open` exemption, since a still-genuinely-closed door reads as unwalkable until the
(now-deferred) open actually happens.

**Known gap**: a trap or dispenser DISARMED or LOOTED during the rewound turn is not respawned —
no reusable "build one trap sprite from a `TRAP_POOL` entry" helper exists for the wall/push
(Piston) variant, and this was judged a rare enough edge case (a single deliberate Thief Tools
action within the very same turn being rewound) not to justify factoring one out this pass.
Restoring a trap/dispenser only updates fields on an entry that's still present in `_traps`/
`_dispensers`.
