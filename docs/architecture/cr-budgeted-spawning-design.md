# CR-Budgeted Enemy Spawning — Design Doc

**Status: §1-5 and §7 (the v1 scope) are implemented** — `DungeonFloor._pick_cr_budgeted_enemies()`/
`_cr_budget()` in `scripts/world/dungeon_floor.gd` are live; see `scripts/world/CLAUDE.md`'s
"Spawning" section, which is now authoritative for the mechanism itself. This doc stays for the
calibration table (§2), the deferred-scope list (§6), and the reasoning behind the constants —
still useful as the field-by-field rationale reference. §6's deferred items remain design-only.
Every
`ENEMY_POOL`/`BOSS_POOL` entry already carries a `"cr"` field (D&D Challenge Rating) — see
`scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema" table — but no code reads it for
balancing today; floor difficulty is 100% the `floor_min`/`floor_max` band plus a flat
`ENEMY_COUNT_MIN..ENEMY_COUNT_MAX` (3–5) random count. This doc turns `"cr"` into the knob that
decides *which combination* of enemies a floor gets, without touching how strong any individual
enemy already is.

Function/field names below were verified against the working tree at time of writing
(`scripts/world/dungeon_floor.gd`, `scripts/world/dungeon_floor_data.gd`) — re-verify line numbers
before implementing, but the structural shape is authoritative. Mirrors the format of
`special-rooms-economy-design.md` (numbered sections, "already in place vs. greenfield",
code-snippet-driven).

---

## 1. Current state — what exists, what is greenfield

**Already in place, reused as-is:**
- **`"cr"` field** — authored on every current `ENEMY_POOL` entry (12) and both `BOSS_POOL` entries,
  a plain `float`. D&D fractional CRs (`0.125`, `0.25`, `0.5`, `1`, `2`, `5`, `8`) are used verbatim.
- **`_pop_rng`** — seeded population RNG (`run_seed ^ (floor * POPULATION_SEED_MIX)`, re-created in
  `_load_floor()`), the single stream every `_spawn_*()` function draws from
  (`scripts/world/CLAUDE.md`'s "Spawning" section). Any new randomness this feature adds MUST go
  through it, never global `randi`/`Array.pick_random()`.
- **`_spawn_enemies()`** (`dungeon_floor.gd:974`) — candidate-tile shuffling, the `eligible`
  floor-band filter, Large-footprint fitting (`_footprint_fits()`/`_enemy_pool_footprint()`,
  `scripts/entities/CLAUDE.md`'s "Multi-tile footprint" section), behavior-roll assignment, and
  `TurnManager.register_enemy()` registration are all untouched by this design — only the piece that
  decides *how many of what* changes.
- **`_spawn_boss()`** (`dungeon_floor.gd:1065`) — unconditional on boss floors (`floor % 5 == 0`),
  reads `BOSS_POOL` by exact `floor` match, spawns at room center. Untouched.
- **The floor-linear stat-scaling formula** (`Enemy._apply_stats()`) — hp/ac/dmg drift within a
  band. Per `enemy-stat-block-design.md` §3's already-settled recommendation, **this design does not
  touch that formula.** CR informs *which* monsters spawn together; the existing formula still
  handles *how strong* each one is within its own `floor_min..floor_max` band.

**Greenfield:**
- No notion of a per-floor "encounter budget."
- No selection algorithm that sums CR against a budget — today's loop just picks `count` uniformly
  random `eligible` entries with no running total of anything.
- No boss-floor-aware scaling of the *regular* (non-boss) spawn budget.

---

## 2. Budget formula

```gdscript
# dungeon_floor.gd, near ENEMY_COUNT_MIN/MAX
const CR_BUDGET_BASE: float = 1.0
const CR_BUDGET_PER_FLOOR: float = 0.35

func _cr_budget(floor_num: int) -> float:
    return CR_BUDGET_BASE + floor_num * CR_BUDGET_PER_FLOOR
```

Plain linear formula, matching the schema doc's own suggested shape (`base + floor_num * k`).
The two constants aren't picked from nothing — they're calibrated against what today's system
*already* spends on average, so the switch to budget-based spawning doesn't silently reshape early
floors:

| Floor | Eligible pool (by `floor_min/max`) | Avg CR | Today's budget @ count=4 | Proposed `_cr_budget()` |
|---|---|---|---|---|
| 1 | goblin_minion, orc_warrior | 0.31 | 1.25 | 1.35 |
| 2 | + goblin_warrior, goblin_archer | 0.28 | 1.13 | 1.70 |
| 3 | (drops goblin_minion) + orc_shaman, zombie | 0.27 | 1.08 | 2.05 |
| 4 | + masked_orc, skeleton (drops none) | 0.29 | 1.14 | 2.40 |
| 5 | (drops orc_warrior) + wogol | 0.31 | 1.25 | 2.75 |
| 6 | (drops goblin_warrior, orc_shaman) + imp | 0.38 | 1.50 | 3.10 |
| 7 | (drops masked_orc, skeleton, zombie, goblin_archer) + chort | 0.43 | 1.71 | 3.45 |
| 8 | (drops wogol) + pumpkin_dude, ogre | 1.00 | 4.00 | 3.80 |
| 9 | (drops imp) | 1.13 | 4.50 | 4.15 |
| 10 | (drops imp, stays: chort, pumpkin_dude, ogre) | 1.17 | 4.67 | 4.50 |

Floors 1–7 track reasonably close to today's implied average; floors 8–10 (where Ogre's CR 2 enters
the pool) land a bit under today's naive count-based average, which is *intended* — those floors are
exactly where "fewer, scarier enemies" (the Ogre pair-down effect) should start happening rather than
still averaging 4–5 spawns. **These two constants are a starting point for playtesting, not locked
math** — tune `CR_BUDGET_PER_FLOOR` first if early floors feel too sparse/crowded once implemented.

**Missing `"cr"`:** every current pool entry already authors it (no live gap), but the read site
must still have a fallback for future entries that forget it — default **`0.25`**, per
`enemy-stat-block-design.md` §3's own prior recommendation (not a new decision, just honoring the
existing one so `"cr"` doesn't get two different defaults in two docs).

---

## 3. Selection algorithm

Replaces only the `count`-then-uniform-pick block inside `_spawn_enemies()` — everything before
(candidate shuffling) and after (footprint placement, behavior roll, registration) is reused
unmodified per enemy chosen.

```gdscript
var budget: float = _cr_budget(GameState.current_floor)
if is_boss_floor:
    budget *= BOSS_FLOOR_BUDGET_SCALE   # see §4

var to_spawn: Array[Dictionary] = []
var safety_cap: int = 12   # hard ceiling, independent of budget math
while to_spawn.size() < safety_cap:
    var affordable: Array = []
    for entry in eligible:
        if float(entry.get("cr", 0.25)) <= budget:
            affordable.append(entry)
    if affordable.is_empty():
        break
    var pick: Dictionary = affordable[_pop_rng.randi_range(0, affordable.size() - 1)]
    to_spawn.append(pick)
    budget -= float(pick.get("cr", 0.25))
```

`to_spawn` then drives the existing per-enemy loop (footprint fit / candidate consumption / behavior
roll / registration), one iteration per entry instead of one iteration per `count`.

Key properties:
- **Uniform-random pick from the affordable subset**, not cheapest-first or most-expensive-first —
  this is what keeps floor population varied run-to-run (which entries are "affordable" shifts every
  iteration as budget drains, so the exact combination is never fixed even for the same floor number
  across different seeds).
- **No forced minimum count.** A floor whose eligible band happens to be all relatively expensive
  entries (e.g. floor 8: wogol/imp/chort/pumpkin_dude/ogre) may legitimately spawn just 2–3 enemies
  instead of today's flat 3–5 — this is the "1 Ogre vs. 4 goblins" tradeoff CR was introduced for,
  per `enemy-stat-block-design.md` §3.
- **`safety_cap`** exists purely to bound worst-case spawn count if a future low-CR entry (e.g. a
  0.125 mob on a high-budget late floor) would otherwise let the loop run dozens of times — not
  expected to bind with the current bestiary, just a defensive ceiling.
- `_pop_rng` draw *count* becomes budget-dependent (variable) instead of the old fixed `count` — see
  §5 for why that's not a reproducibility problem.

---

## 4. Boss floors

`_spawn_boss()` is untouched: unconditional spawn, boss's own `"cr"` is **never** deducted from
anything — a boss isn't "bought" out of a shared pool, it's guaranteed content for that floor number.

What changes: on a boss floor, the **regular** encounter budget computed in §3 is scaled down before
the selection loop runs:

```gdscript
const BOSS_FLOOR_BUDGET_SCALE: float = 0.4

# inside _spawn_enemies(), before the §3 loop:
var is_boss_floor: bool = GameState.current_floor % 5 == 0 and _data.boss_room.has_area()
var budget: float = _cr_budget(GameState.current_floor)
if is_boss_floor:
    budget *= BOSS_FLOOR_BUDGET_SCALE
```

Rationale: a floor-5 Big Demon (CR 5) or floor-10 Necromancer (CR 8) is already the floor's main
threat — stacking a full-budget crowd of regular spawns alongside it would be a spike, not a curve.
`0.4` is a starting guess (leaves room for a small 1–2-enemy retinue around the boss rather than
either zero support or a full mob) — tune alongside the base budget constants during playtesting.

---

## 5. Save/load reproducibility risk

**Claim: no new risk category.** `_pop_rng`'s invariant (`scripts/world/CLAUDE.md`: *"the spawn call
order and the number of draws inside each function are load-bearing for reproducibility"*) is about
the algorithm being deterministic given a fixed seed+floor+code-version — **not** about the number of
draws being frozen across feature additions. Every prior population feature (gold piles, treasure
rooms, locked doors) already changed how many `_pop_rng` draws happen without breaking anything,
because determinism only requires "same inputs → same outputs," and the inputs here are still just
`(run_seed, floor_num)`.

This feature's loop is fully `_pop_rng`-sourced (the `affordable.size()` random-index pick is the
only new randomness site) and its iteration count is a pure function of `(budget, eligible)`, both of
which are themselves pure functions of `floor_num`. So: same seed + same floor + same code ⇒ same
`to_spawn` list, every time.

**What to actually test** (once implemented):
1. Debug panel "Jump to Floor" to the same floor twice under one run seed — diff the spawned
   `enemy_id` list, must match exactly both times.
2. `SaveManager.reload_from_save()` round-trip on both a regular floor and a boss floor — the
   regenerated population (post-save, post-reload) must match what was there pre-save. This is the
   existing Phase-A save invariant (`scripts/autoloads/CLAUDE.md`'s SaveManager section) — exercised
   the same way any other population-affecting change already is. No new save-format field is
   needed since enemies are still regenerated from seed, never serialized as a list.
3. No `_pop_rng` draws should occur *inside* the `float(entry.get("cr", ...))` fallback-default path
   itself — only the `affordable.randi_range()` pick draws — so a floor whose pool happens to include
   a `"cr"`-less future entry still stays deterministic (the missing-key default is pure data, not a
   roll).

---

## 6. Scope: v1 vs. deferred

**In scope for v1 (fully specced above):**
- `_cr_budget(floor_num)` linear formula + calibration table.
- Affordable-random selection loop replacing the flat count loop.
- Boss-floor budget scaling (`BOSS_FLOOR_BUDGET_SCALE`).
- Missing-`"cr"` default (`0.25`).

**Explicitly deferred (noted here, not designed further — don't build unless asked):**
- **Per-room CR distribution** — spreading the budget across individual rooms instead of pooling it
  floor-wide (would matter more once room-level encounter design is a goal; today's spawn placement
  is already floor-wide candidate-tile shuffling, so per-room budgeting is a bigger structural change
  than this pass warrants).
- **Elite/pack variants** (a cheap CR discount for spawning 3 of the same weak enemy as a "pack," a
  D&D DMG concept) — not needed with only 12 pool entries.
- **CR-derived `exp`** — already flagged as its own separate follow-up in
  `enemy-stat-block-design.md` §3 (`exp = round(cr_to_xp(cr) * scale)`); left alone here on purpose
  to avoid bundling two unrelated CR-consuming features into one pass.
- **Dynamic mid-floor rebalancing** (e.g. re-rolling budget after early kills) — the engine has no
  precedent for population changing after `_load_floor()` completes; out of scope.
- **Boss-adjacent curated guard lists** (e.g. "only spawn Undead near the Necromancer," thematic
  coherence beyond pure CR math) — a real idea, but a distinct concern from budget accounting; note
  it as a possible v2, don't design it now.

---

## 7. Estimated implementation size

Small — one net-new function (`_cr_budget()`), one loop replacing another loop inside
`_spawn_enemies()` (same call site, no new function signature needed elsewhere), two new tunable
constants, and a `BOSS_FLOOR_BUDGET_SCALE` multiplier applied before that loop. No changes to `Enemy`,
`Stats`, `TurnManager`, or the save system. Expect this to be a single focused session once approved,
followed by a short playtest pass to tune the two budget constants and the boss-floor scale.
