# Save/Load System Architecture

No save system exists today (closing the game loses the run). This spec defines a permadeath-respecting, corruption-resistant, Phase-2-(multiplayer)-aware save system in phases, starting with a small MVP.

---

## 1. Core decisions (made here, do not relitigate per session)

### 1.1 Format: versioned JSON via hand-written `to_dict()/from_dict()`

- **JSON** (`JSON.stringify(dict, "\t")` / `JSON.parse_string`), one top-level Dictionary with `save_version: int` as the first key.
- **Rejected — `FileAccess.store_var(full_objects=true)` / saving `Resource` (.tres):** both deserialize arbitrary embedded scripts → code-execution risk on tampered files, and both are brittle across refactors (renaming a field or class breaks old saves opaquely). Binary `store_var` without objects loses nothing over JSON except a few KB.
- **Why JSON wins for this project:** human-readable (debuggable by a solo dev with a text editor), trivially versionable/migratable, diffable in bug reports, and directly reusable as the Phase-2 network sync payload shape.
- **Rule:** every serialized class gets explicit `to_dict() -> Dictionary` / `static from_dict(d: Dictionary)` pairs. Never serialize a Godot object generically. Ints/Strings/bools/Arrays/Dictionaries only; `Vector2i` encoded as `[x, y]` (JSON has no Vector2i; write tiny helpers `_v2i_to_arr` / `_arr_to_v2i` once, in the SaveManager).

### 1.2 Files and location

- `user://save/run.json` — the active run. `user://save/run.json.bak` — previous good save.
- `user://` maps to the app-private dir on Android and `%APPDATA%/Godot/app_userdata/...` on Windows; no per-platform code needed. Steam Cloud (later) is configured to sync the `save/` folder — another reason for a small, single-file format.
- Later (not MVP): `user://save/profile.json` for meta-progression/stats/settings that survive death.

### 1.3 Corruption resistance: atomic write + backup

```gdscript
# SaveManager._write_atomically(path, text):
1. write to path + ".tmp"; FileAccess.flush(); close
2. if path exists: DirAccess.rename_absolute(path, path + ".bak")
3. DirAccess.rename_absolute(path + ".tmp", path)
```
On load: parse `run.json`; if missing/unparseable/`save_version` unknown → try `.bak`; if that fails → no run (main menu). Never crash on a bad file. Android process death mid-write is the main real-world threat; this handles it.

### 1.4 Permadeath

- Save file is **deleted on `player_died`** (connect SaveManager to the signal) and on `player_won`.
- Autosave points overwrite the single slot; there is no manual "save slot" UI — only "Continue" on the main/class-select screen when a valid `run.json` exists.
- Save-scumming via OS file copy is possible and **explicitly not defended against** (solo-dev pragmatism; SPD doesn't either). Do not add checksums/encryption unless the user asks.

### 1.5 New autoload: `SaveManager` (`scripts/autoloads/save_manager.gd`)

Pure orchestration: `has_save() -> bool`, `save_run()`, `load_run() -> bool`, `delete_save()`. It reads/writes GameState and asks other systems for their dicts. GameState does NOT gain file I/O. Register in project.godot after GameState. Update `scripts/autoloads/CLAUDE.md` when added.

---

## 2. When to save (phased)

**Phase A (MVP): checkpoint = floor entry.** Save once inside `_load_floor()` completion (after spawns), plus on app lifecycle events (`NOTIFICATION_WM_CLOSE_REQUEST` and `NOTIFICATION_APPLICATION_PAUSED` — the latter is the Android "user switched apps" event and is mandatory for mobile). Phase A saves **only floor-entry state**; loading always restarts the current floor from its top. Mid-floor progress (position, kills, pickups since entry) is lost on load. This is an accepted, documented MVP limitation — it makes the entire per-floor world state (enemies, doors, traps, fog, floor items) NOT serialized, cutting the MVP surface by ~70%.
  - To make this honest, snapshot the save data **at floor entry into memory** and have `save_run()` write that snapshot (plus nothing newer). Otherwise quitting mid-floor would persist mid-floor player HP/inventory against a fresh floor = dupe/loss bugs.
- **Phase B: mid-floor saves** (see §5). Only start after Phase A has soaked.

## 3. Blocker: floor regeneration is only half-deterministic

`DungeonGenerator.generate(seed, floor)` is pure and seeded — tiles/rooms reproduce exactly. **But floor population is not:** `DungeonFloor._spawn_enemies()` shuffles candidates with the global RNG and mixes `randi()`/a locally seeded rng; `_spawn_items()`, `_spawn_traps()`, `_spawn_doors()` (65% `randf()` per candidate), `_spawn_locked_doors()` all use unseeded global RNG. Reloading a Phase-A checkpoint would produce a *different-populated* floor than the one the player quit — same walls, different monsters/doors.

**Required pre-work (small, do first):** thread one `RandomNumberGenerator` seeded with `run_seed ^ (floor * K)` through all `_spawn_*()` functions in `dungeon_floor.gd` (replace `.shuffle()` with a seeded Fisher-Yates helper — one already exists in `dungeon_generator.gd`, extract it to a shared static). After this, "load floor N of run R" reproduces the identical floor, and the save file needs only `run_seed` + `current_floor` for the whole world. This is also step 0 of the Phase-2 determinism story (§6).

---

## 4. What gets serialized (Phase A schema)

Top-level:
```json
{
  "save_version": 1,
  "run_seed": 123456789,
  "current_floor": 4,
  "player_stats": { ... },        // §4.1
  "talents": { ... },             // §4.2
  "inventory": { ... },           // §4.4
  "rest": { ... },                // §4.5
  "misc": { ... }                 // §4.6
}
```

### 4.1 `Stats.to_dict()` — persist, don't recompute
`strength..charisma, character_class, character_level, experience, max_hp, current_hp, base_min/max_damage, rage_uses_remaining, temp_hp, poison/burning/bleeding/slowed_turns, zealous_presence_turns, known_weapon_masteries`. Computed properties (proficiency, rage_uses_max, martial_arts_die) and class-set flags (check_prof_*, weapon proficiency) are NOT saved — `from_dict` calls `apply_class_defaults()` first, then overwrites with saved values (order matters: apply_class_defaults resets scores/hp).

### 4.2 Talents — save investments, replay effects
Persist: `talent_investments`, `talent_points` (per-tier dict — see TALENT doc §4), `tier2_unlocked`, `subclass_chosen`, `active_tier2_subclass`, `tier3_offered_classes`, `tier3_selected_class`, plus Wild Heart/Zealot state: `natural_rager_form`, `natural_sleeper_form`, `active_sleeper_form`, `wild_heart_sleeper_active`, `zealot_divine_fury_type`, `zealot_blessed_charges`, `zealot_zp_charges`.

### 4.3 Abilities are DERIVED state — do not serialize Ability objects
Load order: `apply_class_defaults()` → `give_class_starting_items()`-equivalent rebuild → `_setup_*_talents()` per saved class/subclass → replay `_apply_talent_rank(id, r)` for each invested id, rank 1..saved (exactly what `debug_set_talent_rank()` already does — reuse its replay loop) → finally restore per-ability `uses_remaining` from a small saved map `{ability_id: uses_remaining}` and toggle state `{ability_id: is_active}`. This keeps descriptions/icons/passives always consistent with code, and makes save migration across balance patches free.
**Caveat:** replaying Danger Sense R3 re-applies `strength += 2`; since §4.1 saves the already-buffed strength, the replay must skip stat-mutating one-shots — add a `silent: bool = false` arg to `_apply_talent_rank()` (or restore stats AFTER the replay, which is simpler: replay first, then apply the saved Stats dict last). **Restore-stats-last is the chosen rule.**

### 4.4 Inventory / equipment — `Item.to_dict()`
All `Item` fields are flat primitives (see `scripts/items/CLAUDE.md` field table) → mechanical to_dict/from_dict listing every field. Serialize `player_quickbar`, `player_inventory` (null slots as JSON null to preserve positions), `equipment` (dict of slot→item-dict/null), and `pending_chasm_items`. Companion: persist `{alive: bool, current_hp: int}` only — rebuild the node from `WILD_HEART_COMPANION_STATS[rank]` on floor load, spawn adjacent to player start.

### 4.5 Rest (after REST doc lands)
`hit_dice, short_rests_remaining` (+ nothing for rations — they're Items). Never persist `short_rest_open/active` mid-flags (Phase A saves at floor entry; these are always false there).

### 4.6 Misc
`is_game_over` (always false in a valid save), god/debug flags deliberately NOT saved (a loaded run starts clean). `player_grid_pos` NOT saved in Phase A (always floor start).

---

## 5. Phase B — mid-floor saves (later; design constraints now)

Adds a `"floor_state"` section: enemy list (`type name/boss_id, grid_pos, current_hp, behavior, slowed/rooted_turns`), door states (`pos → {is_open, locked, player_locked}`), traps (`pos → {revealed, triggered}`), floor items (`pos → [item dicts]`), `_explored` keys (PackedInt32Array-style flat list for size), grass→trampled diffs, player `grid_pos`, TurnManager phase is always WAITING_FOR_INPUT at save time (only save between turns — enforce by deferring `save_run()` until `player_turn_started`).
Constraint this places on new world features **now**: any new per-floor mutable state must live in a queryable structure on DungeonFloor (dicts keyed by Vector2i, like `_doors`/`_traps`), never in loose Sprite2D-only state — otherwise Phase B has nothing to read.

## 6. Determinism & Phase 2 multiplayer constraints

Current combat rolls use the **global, unseeded RNG** (`randi_range` in player.gd, enemy.gd, stats.gd) plus `Array.shuffle()` — fine for singleplayer, unusable for lockstep sync or replay-verification.

Rules for future code (write into CLAUDE.md when SaveManager lands):
1. **New systems** route gameplay randomness through one service — recommended: `Rng` autoload wrapping a single `RandomNumberGenerator` with `Rng.roll(sides)`, `Rng.pick(arr)`, `Rng.shuffle(arr)`; seeded from `run_seed` at run start; its `state` (int64) is saved/restored in the save file. Cosmetic randomness (tween jitter, particle offsets) stays on the global RNG deliberately.
2. **Do not retrofit** existing combat call sites yet — it's a mechanical sweep best done as its own session right before Phase 2 work (or Phase B saves, whichever comes first), because save-format stability depends on it.
3. Determinism also requires: stable iteration order (enemy turns already run in registration order — keep it; never iterate a Dictionary where order affects gameplay), no decisions from wall-clock/frame timing (current `await timer` usages are cosmetic pacing only — keep it that way), and all AI decisions computable from (game state, Rng) — see ENEMY doc §5.

## 7. Migration strategy

- `save_version` int, bumped on ANY schema change.
- Loader: `while data.save_version < CURRENT: data = _migrate[data.save_version].call(data)` — a Dictionary of `Callable` upgraders, each doing one version step.
- **Pragmatic policy while in development:** runs are short (~10 floors); until v1.0 it is acceptable for a migrator to be "delete save, log 'save from older version discarded'". Never crash, never load-and-corrupt. Post-release (Steam/Play), real migrators become mandatory — the versioned-dict shape makes them cheap.

## 8. Implementation plan (sessions)

1. **Seeded floor population** (§3) — `dungeon_floor.gd` only. Independent, zero-risk, also needed by DUNGEON doc. Verify: same seed+floor twice → identical doors/enemies/items.
2. **to_dict/from_dict** on Stats and Item + `SaveManager` skeleton with atomic write/backup + delete-on-death. Files: `stats.gd`, `item.gd`, new `save_manager.gd`, `project.godot`.
3. **Full Phase-A snapshot + Continue button** — `game_state.gd` (talent replay load path), `class_select.gd`/main menu, `dungeon_floor.gd` (load-into-floor path), lifecycle notifications in a root node.
4. CLAUDE.md updates (root + autoloads).
Phase B and the Rng retrofit are separate, later sessions.
