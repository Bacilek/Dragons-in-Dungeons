# Seeded Floor Population

**Status: IMPLEMENTED** (`_pop_rng` in `dungeon_floor.gd`, shipped alongside the 2026-07 Rng retrofit; the generator-side `RngUtil` fixes landed earlier). Spec kept as the reference for the mechanism.

Small, one-session, implementation-ready spec: make everything that *populates* a floor (enemies, traps, doors, locked doors, items) draw from a seeded `RandomNumberGenerator` derived from `run_seed` + `current_floor`, so that generating the same floor of the same run twice produces identical contents. This is the "Seeded floor population" session from `IMPLEMENTATION_SEQUENCE.md` (item 2) and the pre-work `SAVE_LOAD_ARCHITECTURE.md` §3 requires before Phase A saves can work.

**Why this matters even without multiplayer:** the Phase-A save checkpoint deliberately serializes *no* per-floor world state — it stores only `run_seed` + `current_floor` and trusts that reloading regenerates the identical floor. Today that trust is misplaced: tiles reproduce (mostly — see §2.1), but monsters, trap positions, door placement, and loot are re-rolled from the global unseeded RNG on every `_load_floor()`. Without this fix, quitting and continuing would silently hand the player a different floor than the one they left — different enemies next to them, different loot behind the locked door. That is the entire justification for this work; no multiplayer argument is needed or used.

**Scope note — SUPERSEDED (2026-07).** An earlier version of this note declared the project-wide `Rng` retrofit "dormant unless multiplayer is revisited". That reasoning no longer applies: the project owner explicitly requested **fully seeded, reproducible runs** (Isaac-style seed sharing — same seed + same inputs → identical playthrough), and the project-wide Rng retrofit (`IMPLEMENTATION_SEQUENCE.md` item 7, SAVE_LOAD_ARCHITECTURE.md §6) **has been implemented for that reason** — not for multiplayer, which remains ruled out. Combat rolls, status-effect rolls, enemy AI decision rolls (`resist_check`, roam shuffles, random steps), trap-trigger checks, boss-loot rolls at kill time, and `resolve_push()` wall damage now all draw from the **`Rng` autoload** (`scripts/autoloads/rng.gd` — API, save-state persistence, and the gameplay-vs-cosmetic rule are documented in `scripts/autoloads/CLAUDE.md`). The `Rng` gameplay stream is deliberately separate from this doc's per-floor `_pop_rng` population stream: population must stay a pure function of `(run_seed, floor)` so a reloaded save regenerates the identical floor no matter how many gameplay rolls were consumed before saving. The rest of this doc remains the authoritative spec for *floor-load-time population*.

---

## 1. Exact call sites to convert (from a 2026-07 read of the code, not the docs)

All in `scripts/world/dungeon_floor.gd`, all executed during `_load_floor()`:

| Function | Unseeded calls today |
|---|---|
| `_spawn_enemies()` | `candidates.shuffle()` (line ~620); `randi_range(ENEMY_COUNT_MIN, ENEMY_COUNT_MAX)` (~631); `eligible[randi() % eligible.size()]` per enemy (~636). **Already has a locally seeded rng** (`run_seed ^ (current_floor * 0x1234ABCD)`, ~632) but uses it *only* for the initial-behavior roll — a half-finished version of exactly this spec. |
| `_spawn_boss()` | none — fully deterministic already (pool lookup by floor, fixed placement fallbacks). No change. |
| `_spawn_traps()` | `floor_cands.shuffle()` / `wall_cands.shuffle()` (~753–754); `randi_range(TRAP_COUNT_MIN, TRAP_COUNT_MAX)` (~766); `floor_pool[randi() % ...]` (~768); `randi_range(2, 3)` push-trap count (~794); `wall_pool[randi() % ...]` (~797). |
| `_spawn_doors()` | `randf() > 0.65` per door candidate (~1185). Candidate *collection* is a deterministic grid/room scan — only the probability roll needs converting. |
| `_spawn_items()` | `candidates.shuffle()` (~1347); `randi_range(2, 3)` (~1349); `eligible[randi() % ...]` (~1351). |
| `_spawn_locked_doors()` | `door_positions.shuffle()` (~1391); `reward_candidates.shuffle()` (~1431); `randi_range(2, 3)` (~1432); `eligible[randi() % ...]` (~1434). Note `_doors.keys()` iteration order is insertion order, which is itself deterministic once `_spawn_doors()` is seeded — no extra work needed. |
| `_spawn_pending_chasm_items()` | `candidates.shuffle()` (~1374). Its *input* (`GameState.pending_chasm_items`) is runtime state, not seed-derived — that's fine: Phase A serializes `pending_chasm_items` (SAVE doc §4.4), so given the same saved list plus this seeded shuffle, drop positions reproduce. |

Explicitly **NOT** converted to `_pop_rng` (runtime, not load-time): the trap-trigger DEX-check dice, `_roll_boss_loot_item()` (rolled at boss-kill time), `resolve_push()` wall-slam damage, and the trap reveal/disarm paths — likewise everything in `player.gd`, `enemy.gd`, `companion.gd`, `stats.gd`. Those are gameplay-time rolls and (since the 2026-07 retrofit — see the superseded-scope note above) draw from the **`Rng` autoload's** persistent run stream instead.

### 1.1 Also fix: two unseeded calls inside the "pure" generator

`scripts/dungeon/dungeon_generator.gd` is documented (root CLAUDE.md, SAVE doc §3) as fully seeded — **it isn't quite**. Two `dirs4.shuffle()` calls use the global RNG:
- `_place_water_mud()` (~line 360)
- `_place_grass_clusters()` (~line 399)

So water/mud/grass cluster *shapes* differ between two generations of the same seed+floor today. Same-session fix: replace both with the shared seeded shuffle helper (§3), passing the `rng` those functions already receive. This corrects the SAVE doc §3 claim that "tiles/rooms reproduce exactly" — they will after this fix.

---

## 2. Seed formula and where the RNG lives

```gdscript
# dungeon_floor.gd
const POPULATION_SEED_MIX: int = 0x1234ABCD   # already the constant used by _spawn_enemies' partial rng — keep it
var _pop_rng: RandomNumberGenerator           # valid only during _load_floor(); do not use elsewhere

# in _load_floor(), immediately after `_data = DungeonGenerator.generate(...)`:
_pop_rng = RandomNumberGenerator.new()
_pop_rng.seed = GameState.run_seed ^ (GameState.current_floor * POPULATION_SEED_MIX)
```

- **Different XOR constant than tile-gen** (`0x9e3779b9` in `DungeonGenerator.generate()`), so population and tile-gen streams don't correlate. `0x1234ABCD` is already in the file for exactly this purpose — reuse it rather than introducing a third constant. Delete the local `rng` inside `_spawn_enemies()`; it's replaced by `_pop_rng`.
- **Field, not parameter.** All six `_spawn_*()` functions are zero-argument methods that already read shared state (`_data`, `GameState.current_floor`, `_traps`, `_doors`); threading an `rng` parameter through six signatures buys nothing here and breaks that house style. A field assigned at the top of the spawn block in `_load_floor()` is the minimal change. It is re-created every `_load_floor()`, so no state leaks across floors.
- **One stream, fixed consumption order.** All spawn functions draw from the single `_pop_rng` in the existing call order: `_spawn_enemies()` → `_spawn_traps()` → `_spawn_doors()` → `_spawn_items()` → `_spawn_locked_doors()` → `_spawn_pending_chasm_items()`. **This order (and the count of draws inside each) is now load-bearing for reproducibility — add a comment saying so at the call site in `_load_floor()`.** Reordering or inserting a draw changes everything downstream, which is acceptable: saves only need *same-build* reproducibility, and the SAVE doc's migration policy (§7) already permits discarding saves across versions during development. If cross-version floor stability is ever wanted, the fallback is per-subsystem sub-seeds (`seed ^ hash("traps")` etc.) — do not build that now.

Every `randi()`/`randi_range()`/`randf()` in §1's table becomes `_pop_rng.randi()`/`_pop_rng.randi_range()`/`_pop_rng.randf()`. Every `.shuffle()` becomes the helper below.

---

## 3. Shared Fisher-Yates helper

Godot's `Array.shuffle()` only uses the global RNG; there is no built-in seeded array shuffle. `dungeon_generator.gd` already inlines seeded Fisher-Yates in at least `_place_pillars()` and `_place_chasms()`. Per SAVE doc §3, extract it once:

**New file: `scripts/dungeon/rng_util.gd`** (chosen over putting it on `DungeonGenerator` because the Dungeon doc will dissolve that file into a pipeline, and over `dungeon_floor.gd` because generation code must not depend on a scene-tree script — `scripts/dungeon/` is the "pure, no node/GameState dependencies" home per `scripts/dungeon/CLAUDE.md`):

```gdscript
class_name RngUtil
extends RefCounted
# Static-func-only helper, same pattern as CombatMath / TooltipFormatters.

static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
    for i: int in range(arr.size() - 1, 0, -1):
        var j: int = rng.randi_range(0, i)
        var tmp: Variant = arr[i]
        arr[i] = arr[j]
        arr[j] = tmp
```

Callers: all `.shuffle()` sites in §1's table (`RngUtil.shuffle(candidates, _pop_rng)`), the two `dirs4.shuffle()` fixes in §1.1, and the existing inline Fisher-Yates loops in `dungeon_generator.gd` (replace them — one implementation, not three). Enemy AI shuffles (`_pick_roam_target()`, `_do_random_step()` in `enemy.gd`) stay on plain `.shuffle()` — out of scope per the framing above.

---

## 4. Verification — do this, don't invent a test

Reproducibility can be verified without any seed-entry UI, because Jump-to-Floor regenerates a floor within the same run (same `run_seed`):

1. Add a debug helper `DungeonFloor.debug_floor_fingerprint() -> String` (keep it — it's ~15 lines and permanently useful): concatenate, in sorted-by-position order, (a) every enemy's `display_name + str(grid_pos) + str(initial_behavior)`, (b) every `_traps` key + trap `name`, (c) every `_doors` key + `locked` flag, (d) every `_floor_items` key + each item's `item_name`; return `str(hash(s))` and `game_log` it. Wire a button (or just call it from `_load_floor()` when God Mode is on) in `debug_panel.gd`.
2. Run the game, F3 → God Mode, note the fingerprint logged for floor 1.
3. F3 → Jump to Floor 2, then Jump to Floor 1 again. The floor regenerates from the same `run_seed`+`current_floor`. **The fingerprint must be identical to step 2's.**
4. Repeat for a boss floor (5) and a late floor (8). Also jump back and forth to the *same* floor 3–4 times — any drift means a stray global-RNG call remains (grep `dungeon_floor.gd` for `randi\|randf\|\.shuffle()` and check every hit is either `_pop_rng.` / `RngUtil.shuffle` or in the §1 "explicitly NOT converted" runtime list).
5. Caveat: do the back-and-forth test with no pending chasm items in flight (`GameState.pending_chasm_items` drains on first load, so a floor loaded right after shooting ammo into a chasm legitimately differs from its reload — that input state is serialized by the save system, not by the seed).
6. Separately verify §1.1: with a hardcoded `run_seed` (temporarily set in `start_new_run()`), restart the game twice and diff two floor-1 fingerprints *plus* eyeball that grass/water patches match. This catches the `dirs4.shuffle()` fix.

## 5. Session checklist

1. New `scripts/dungeon/rng_util.gd`.
2. `dungeon_generator.gd`: replace inline Fisher-Yates loops + the two `dirs4.shuffle()` calls with `RngUtil.shuffle(..., rng)`.
3. `dungeon_floor.gd`: add `_pop_rng` field + seeding in `_load_floor()`; convert every call in §1's table; delete `_spawn_enemies()`'s local rng; add the consumption-order comment.
4. Verify per §4. No behavior change is expected beyond reproducibility (distributions are identical, only the source of randomness changes).
5. Update `scripts/world/CLAUDE.md` (Spawning section: note `_pop_rng` + the order-is-load-bearing rule), `scripts/dungeon/CLAUDE.md` (RngUtil), and root CLAUDE.md (one line). Commit and push.
