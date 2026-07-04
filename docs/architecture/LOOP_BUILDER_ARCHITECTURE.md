# LoopBuilder Architecture

`DUNGEON_GENERATION_ARCHITECTURE.md` §7 deliberately deferred the internals of `LoopBuilder` — the SPD-style, room-graph builder that produces floors with *multiple paths between areas* instead of the single-path-plus-a-few-shortcuts topology that BSP's tree structure forces. This doc closes that gap: it is the complete algorithm design for `scripts/dungeon/builders/loop_builder.gd`, concrete enough that the implementing session (IMPLEMENTATION_SEQUENCE.md session **5c**) makes zero algorithm-design decisions of its own. It assumes migration steps 1–3 of the Dungeon doc §8 have already shipped: `BspBuilder` wraps the old code, `FloorPlanner.plan()` emits typed `Room` lists, `LevelPainter` owns the overlay painters, and `DungeonGenerator.generate(seed, floor_num)` is thin orchestration.

Everything here honors the Build-phase contract from the Dungeon doc §2.2 and IMPLEMENTATION_SEQUENCE.md invariant 6:

```gdscript
static func build(rooms: Array[Room], rng: RandomNumberGenerator) -> DungeonData
# returns null on failure; never returns a partial DungeonData
```

and produces output shape-identical to `BspBuilder`'s: 48×48 `grid` of `WALL`/`FLOOR` (+ one `STAIRS_DOWN` tile), `rooms: Array[Rect2i]` of axis-aligned rectangles, `player_start`, `stairs_pos`, `start_room`, `width`, `height` all set. `boss_room` stays an orchestration concern (§5). Grid conventions, `TileType` values, and the 1-tile outer wall border (`Rect2i(1, 1, 46, 46)` usable area) are unchanged from `scripts/dungeon/dungeon_generator.gd`.

---

## 1. Room placement — rejection-sampled scatter

**Recommended approach: pure rejection sampling** ("throw the rect at the grid, keep it if it fits, retry if not"), with rooms placed in a deliberate order. No relaxation, no cell grid.

- **Rejected: scatter-and-relax** (place overlapping, then iteratively push rooms apart). It converges non-deterministically in iteration count, needs a termination heuristic, and its only advantage — packing *many* rooms densely — doesn't apply: this game plans ~8–15 rooms of 5–11 tiles on a 46×46 usable area (≈2116 tiles vs ≈900–1500 tiles of room footprint including separation padding). Rejection sampling at this density succeeds in a handful of attempts per room.
- **Rejected: coarse cell grid with jitter** (e.g. 4×4 cells, one room per cell). It is *more* reliable than scatter, but it caps room count at the cell count, produces visibly grid-aligned layouts — which is exactly the BSP look `LoopBuilder` exists to escape — and adds a second spatial-partition concept to the codebase for no capability gain.

### 1.1 Placement order

Sort the planned `rooms` list before placing: **`required == true` first** (Entrance, Exit), then remaining rooms **by `max_size()` area descending**. Big rooms are the hardest to fit, so they go while the grid is empty; required rooms go first of all so a placement failure on them is detected immediately (and because §4's farthest-pair swap wants them placed unconditionally). Sorting is deterministic (stable sort on `(required desc, area desc, original index asc)`) so identical seeds give identical layouts.

### 1.2 Size and position roll

For each room, up to `PLACE_ATTEMPTS_PER_ROOM = 40` tries:

```gdscript
var w: int = rng.randi_range(room.min_size().x, room.max_size().x)
var h: int = rng.randi_range(room.min_size().y, room.max_size().y)
var x: int = rng.randi_range(1, GRID_WIDTH - 1 - w)    # respect 1-tile outer wall border
var y: int = rng.randi_range(1, GRID_HEIGHT - 1 - h)
var candidate := Rect2i(x, y, w, h)
```

Size ranges come from the room's own `min_size()`/`max_size()` overrides per the `Room` base class (Dungeon doc §3) — `LoopBuilder` never hardcodes 5/11; those are just the base-class defaults.

### 1.3 Overlap rule (explicit)

**A candidate is accepted iff `candidate.grow(2)` intersects no already-placed room rect.** This guarantees **≥2 wall tiles between any two rooms**.

Why 2 and not 1: with a single shared wall column, an L-corridor carving along that seam turns two rooms into one visually-continuous blob — which breaks the player's mental model, confuses the runtime door detector (`_spawn_doors()` scans room perimeters), and undermines `_place_pillars`' "inner zone is ≥2 from every room edge, avoiding corridor mouths" assumption. A 2-tile gap means a 1-wide corridor passing between two rooms always leaves at least one wall tile on each side. (BSP gets a similar guarantee for free from its leaf margins; scatter has to buy it explicitly.)

If a room exhausts its 40 attempts, the **whole layout attempt** fails — see §6 for restart/null semantics. **Rejected: silently dropping unplaceable optional rooms** — it would break the Initialize/Build phase boundary ("Initialize commits to identity and count", Dungeon doc §2.1): `max_per_floor` caps and feeling-scaled room budgets would become lies the planner told. Failure is binary; the retry/fallback ladder (§6) absorbs it.

### 1.4 No room extensions

`BspBuilder` carries `_add_room_extensions()` (40%-chance rectangular nubs) verbatim because byte-identity demanded it. `LoopBuilder` **does not reuse it**: extensions carve floor rects that are *not* registered in `data.rooms`, which is tolerated by the painters but muddies the room-rect ⇄ grid correspondence this builder's own verification (§8) relies on, and the loop topology already provides the visual variety extensions were compensating for. Rooms stay pure rects. This is a deliberate output difference from `BspBuilder`, not an oversight.

---

## 2. Graph connectivity — MST spanning skeleton + loop edges

Rooms are graph nodes identified by their **index** in the placed-room array. The graph lives in a hand-rolled adjacency structure — no helper class:

```gdscript
var adjacency: Dictionary = {}   # int (room index) -> Array[int] (neighbor indices)
var edge_keys: Dictionary = {}   # dedup, reuses the existing _pair_key(a_center, b_center) pattern
```

(**Rejected: a `RoomGraph` class file.** For ≤15 nodes and two consumers — edge selection and the §8 BFS check — a Dictionary-of-Arrays is idiomatic here and consistent with `bsp_pairs: Dictionary` in the existing generator. A class earns its file when a third consumer appears.)

### 2.1 Spanning skeleton: Prim's MST over Manhattan center distance

Guaranteed connectivity first. Hand-rolled Prim's, O(N²), trivial at N ≤ 15:

```gdscript
# in_tree starts as {0: true}; repeat N-1 times:
#   among all (in-tree i, out-of-tree j) pairs, pick the one minimizing
#   manhattan(center(i), center(j)), ties broken by lowest j then lowest i
#   add edge i–j, mark j in-tree
```

Deterministic tie-breaking (index order) matters for seed reproducibility — no rng involved in the MST itself. **Rejected: reusing BSP's tree-of-splits connection logic** — there are no splits; the tree would have to be invented from the scatter anyway, and MST-over-centers *is* that invention, minus the detour. **Rejected: Kruskal + union-find** — same output class, but Prim's needs no union-find helper; less code.

MST edges **ignore `max_connections()`**: spanning connectivity is non-negotiable, and with Manhattan-distance MSTs over ≤15 scattered nodes, a degree above 4 is rare enough that enforcing the cap here would just be another failure mode for no gameplay benefit. The cap is enforced on loop edges only (§2.3). Flagged explicitly: `Room.max_connections()` is therefore a *soft* limit under `LoopBuilder`, hard only for discretionary edges. If a future room type genuinely cannot tolerate >N openings (a vault with one guarded door), that's a `paint()`/door-placement concern for its own session, not a graph constraint to retrofit here.

### 2.2 Loop edge count (the tunable)

```gdscript
const LOOP_DIVISOR: int = 4
var num_loops: int = clampi(placed.size() / LOOP_DIVISOR, 1, 3)
```

8–11 rooms → 2 loops; 12–15 → 3; tiny floors → 1. This intentionally lands in the same 2–3 band as today's `_add_extra_corridors()`, which is the existing informal version of this exact idea — player-facing corridor density stays familiar. `LOOP_DIVISOR` is the one knob to turn if playtesting wants loopier floors.

### 2.3 Candidate edge selection and disqualification

Enumerate all non-MST room pairs, **sort by Manhattan center distance ascending** (shortest first — least carving, lowest crossing risk, and short loops between nearby-but-not-tree-adjacent rooms are the SPD aesthetic), then accept greedily until `num_loops` are placed. A candidate pair (i, j) is **disqualified** if any of:

1. **Edge already exists** — `edge_keys.has(_pair_key(center_i, center_j))`.
2. **Degree cap** — either room already has `max_connections()` entries in `adjacency`.
3. **Too long** — Manhattan center distance > `MAX_LOOP_DIST = 20`. Longer shortcuts carve corridor across half the 48-grid and almost always trip rule 5.
4. **Trivial cycle** — BFS hop distance between i and j in the current graph is < `MIN_LOOP_HOPS = 3`. A loop edge between rooms already 2 hops apart closes a triangle that barely changes routing; ≥3 hops guarantees a cycle of length ≥4 — a *real* alternate route around a room the player might want to avoid. (BFS over the adjacency Dictionary, ~15 nodes: free.)
5. **Crosses a third room** — the candidate's L-corridor path (both elbow variants, see §3) would pass through the rect of any room other than i and j. Test is cheap: an L-path is two 1-wide `Rect2i` strips; `strip.intersects(other_room.rect)` for each placed room. If one elbow variant passes and the other doesn't, the passing variant is *recorded* as the mandatory elbow for this edge; if both cross, disqualify.

Rule 5 applies to **loop edges only**. MST edges are allowed to punch through intervening rooms — today's BSP corridors already do this routinely, the runtime tolerates it, and refusing it for the spanning skeleton would be a new failure mode on the one structure that must always succeed. For discretionary loop edges, though, crossing a third room silently merges "alternate route" into "extra door in an unrelated room," defeating the purpose — so there it disqualifies.

Every accepted edge (MST and loop alike) is recorded symmetrically: `room_i.connections.append(room_j)` and vice versa on the `Room` objects, plus the adjacency Dictionary and `edge_keys`. If fewer than `num_loops` candidates survive disqualification, that is **not** a failure — the floor ships with fewer loops (an MST-only floor is still a valid, fully-connected floor; it just plays like BSP). Failure is reserved for placement/connectivity problems (§6).

---

## 3. Corridor carving — existing L-shapes, rng-chosen elbow

**Concrete call: 1-wide L-shaped corridors, center-to-center, are good enough — reuse the existing `_carve_corridor()` logic** (turning only `WALL → FLOOR`, exactly as today), with one addition: **the elbow direction (horizontal-first vs vertical-first) is chosen per-edge by `rng.randi() % 2`**, the way `_add_extra_corridors()` already does with its explicit corner point, rather than always horizontal-first like `_connect_bsp()`.

Why not something fancier for loop layouts:
- **Rejected: A*/weighted path carving** (routing corridors around rooms organically). It produces prettier corridors but requires a cost-grid, tie-breaking policy, and diagonal-adjacency rules — three new design surfaces — while the L-shape's failure mode (occasionally clipping a room) is already handled: rule 5 in §2.3 disqualifies loop edges that would cross, and MST crossings are explicitly tolerated (as they are today).
- **Rejected: 2-wide corridors for loop edges** ("make loops read as major routes"). The runtime door detector expects 1-wide openings in room perimeters; a 2-wide mouth spawns door pairs or none. Not worth touching `dungeon_floor.gd` for.

**The "two corridors read as one wide room" concern, resolved:** two 1-wide L-corridors that *cross* at a point read fine (a T or + junction — good, that's texture). The bad case is two corridors running *parallel and adjacent* for several tiles, reading as a 2-wide hall or a smeared room. Mitigations already in this design make it rare rather than impossible: rooms are ≥2 apart (§1.3) so seam-hugging pairs can't form along room edges; loop edges are few (≤3) and shortest-first; elbow randomization decorrelates paths between nearby pairs. **Accepted residual risk**: it can still occasionally happen mid-grid, exactly as it already can in today's `_add_extra_corridors()` output, and nobody has ever filed it as a bug. Do not add a corridor-adjacency rejection pass for a cosmetic non-problem (**rejected** on over-engineering grounds; revisit only if playtest screenshots actually show it).

Carving order: all MST edges first, then loop edges (using the elbow variant recorded by §2.3 rule 5 where one was mandated). Dedup via `edge_keys` means no pair is ever carved twice.

---

## 4. Entrance/Exit placement — farthest-pair assignment after scatter

Today's generator picks player start = smallest room, stairs = room farthest from start. Under `LoopBuilder`, "farthest apart" is preserved by making Entrance/Exit an **assignment** problem instead of a placement problem:

1. Place *all* rooms per §1 (Entrance/Exit are placed first but at rng positions like everyone else — their initial rects are not special).
2. After placement, compute the **pair of placed rects with maximum pairwise Manhattan center distance** (O(N²), N ≤ 15).
3. **Swap rect assignments** so `EntranceRoom` holds one rect of that pair and `ExitRoom` the other — with a compatibility guard: a swap between room A and room B is legal only if each room's *new* rect satisfies its *own* `min_size()`/`max_size()`. In MVP this always succeeds (Entrance/Exit/Standard all share the default 5×5–11×11 range, and the pool is mostly Standard); if a future exotic pool makes the max-distance pair incompatible, fall back to the **farthest compatible pair** (iterate pairs in descending distance until both swaps are legal — Entrance and Exit are themselves always compatible with each other's rects as a last resort, since they share size overrides or defaults).
4. Then: `player_start` = Entrance rect center (same `clampi` guard as today), `start_room` = Entrance rect, `stairs_pos` = Exit rect center, and `grid[stairs_pos.y][stairs_pos.x] = TileType.STAIRS_DOWN` — set by `LoopBuilder` itself, matching what the wrapped `BspBuilder` does (that logic moved into the builder at migration step 1, since the build contract is what produces `player_start`/`stairs_pos`).

The swap runs **before** graph construction (§2), so the MST and loop edges are built over final room identities and `connections` end up on the right `Room` objects.

Deliberate flavor change, flagged: the "start in the *smallest* room" heuristic is dropped — max-distance pairing is the pacing guarantee that matters (longest forced traversal per floor), and coupling it with a size constraint would sometimes force a *shorter* run. `BspBuilder` keeps the old behavior; the two builders are allowed to feel different — that's the point of having two.

---

## 5. Boss-room compatibility — orchestration's job, unchanged

The build contract `build(rooms, rng)` **does not receive `floor_num`**, so no builder except `FixedBuilder` (which owns its hand-authored layouts, Dungeon doc §2.2) can know it's a boss floor. This was already true for the wrapped `BspBuilder` at migration step 1 — the `if floor_num % 5 == 0: boss_room = farthest_room` line necessarily moved out of the builder and into `DungeonGenerator.generate()` orchestration at that point.

**Concrete rule, works identically for `BspBuilder` and `LoopBuilder` output:**

```gdscript
# dungeon_generator.gd orchestration, after build() returns non-null:
if floor_num % 5 == 0 and data.boss_room == Rect2i():   # FixedBuilder sets its own
    for r: Rect2i in data.rooms:
        if r.has_point(data.stairs_pos):
            data.boss_room = r
            break
```

"Room containing the stairs" is exactly what `farthest_room` meant in the old code, expressed without assuming how the builder chose it. `LoopBuilder` needs **no boss special-casing at all**, and boss floors do **not** route around `LoopBuilder` while `FixedBuilder` doesn't exist yet — a 5×5 exit room hosting a boss is already possible under today's BSP (its farthest room can also bottom out at 5×5), so this is no regression. When `FixedBuilder` ships, boss floors stop reaching `LoopBuilder` entirely and this paragraph becomes moot.

---

## 6. Failure/retry contract — internal restarts, orchestrated retries, Bsp fallback

Three failure layers, from inside out:

**Layer 1 — per-room placement attempts** (`PLACE_ATTEMPTS_PER_ROOM = 40`, §1.2): exhausting them fails the current layout attempt.

**Layer 2 — internal layout restarts inside `build()`**: on a failed layout attempt, `LoopBuilder` throws away all placed rects (and resets every `room.rect = Rect2i()` and `room.connections.clear()` — the `Room` objects are reused across attempts, so stale state must be scrubbed) and re-scatters from scratch, **up to `INTERNAL_RESTARTS = 3` layout attempts total**, continuing to consume the same `rng` stream (deterministic: same seed → same sequence of attempts → same final layout). A layout attempt can also fail *after* carving, at the §8 self-check (BFS from `player_start` must reach every room center) — this should be unreachable given MST-guaranteed connectivity, but it's cheap insurance against carve clipping at grid borders, and treating it as "failed attempt, restart" beats shipping a broken floor. After 3 failed attempts, `build()` returns `null` — never a partial `DungeonData` (invariant 6).

**Layer 3 — orchestration retries then fallback** (this is the "retry-then-fallback" wiring from Dungeon doc §2.2 that session 5c also implements):

```gdscript
const BUILDER_RETRIES: int = 3   # total build() calls before fallback
for attempt: int in BUILDER_RETRIES:
    var sub_rng := RandomNumberGenerator.new()
    sub_rng.seed = floor_seed + (attempt * 0x1000193)   # fresh deterministic substream per attempt
    data = LoopBuilder.build(rooms, sub_rng)
    if data != null:
        break
if data == null:
    data = BspBuilder.build(rooms, bsp_rng)   # guaranteed success (Dungeon doc §7)
```

So the worst case is 3 × 3 = 9 scatter attempts before Bsp fallback — with §1's density math, reaching fallback at all should be well under 1% of floors (§8 measures this; if it measures higher, the fix is lowering `FloorPlanner`'s room budget or `MAX_ROOM_DIM`, not raising retry counts).

**The fallback edge case, resolved concretely: `BspBuilder` receives the *same* `rooms` list `LoopBuilder` failed on — no re-plan, no lower feeling tier.** Rationale: `BspBuilder` cannot fail (Dungeon doc §7 — it's the always-succeeds algorithm), and its room-assignment behavior (map planned `Room`s onto whatever BSP leaves emerge; leaf count is dictated by the splits, not the plan) already tolerates any planned list including one that was too crowded to scatter — BSP *forces* rooms into leaf margins rather than needing free space between them. Re-planning at a lower feeling multiplier would (a) create a second orchestration path to maintain for a <1% event, (b) make feeling effects silently seed-dependent ("large" floors that aren't large, with no visibility into why), and (c) still need the no-re-plan path anyway as *its* fallback. **Rejected** accordingly. Consequence, stated plainly: `BspBuilder` needs **zero LoopBuilder-specific changes** — it never knows it's being used as a fallback.

---

## 7. Compatibility with existing overlay painters — confirmed, two flags

The `LevelPainter` overlays (`_place_pillars` / `_place_chasms` / `_place_water_mud` / `_place_grass_clusters`, inherited verbatim per Dungeon doc §2.3) consume exactly two things: `data.rooms: Array[Rect2i]` and the `data.grid` FLOOR/WALL field, plus `player_start`/`stairs_pos` exclusion points and the `_is_connected()` BFS. `LoopBuilder` populates all of these in the same shape `BspBuilder` does. Point-by-point:

| Painter assumption | LoopBuilder output | Verdict |
|---|---|---|
| `_place_pillars`: rooms are `Rect2i`, skips rooms <7×7, inner zone = ≥2 from room edge avoids corridor mouths | Rooms are pure rects (no extensions, §1.4); corridors enter at room centers so mouths are on perimeters, ≥2-inset inner zone still clears them | ✅ works unmodified |
| `_place_pillars`/`_place_chasms`: revert-if-`_is_connected()`-fails, BFS `player_start → stairs_pos` | Both endpoints set (§4); graph is connected pre-paint, so the BFS semantics are identical | ✅ |
| `_place_chasms`: "large rooms" = ≥7×7 from `data.rooms` | Same field, same shape; note scatter's uniform 5–11 size roll yields somewhat fewer ≥7×7 rooms than BSP's margin-derived sizes — chasm floors get slightly rarer under LoopBuilder, acceptable drift, tune room size weights later if it matters | ✅ (flagged, cosmetic) |
| `_place_water_mud`/`_place_grass_clusters`: operate on all FLOOR tiles grid-wide, no room knowledge | Grid is grid | ✅ |
| Runtime `_spawn_doors()` perimeter scan (not a painter, but same class of consumer) | 1-wide corridor mouths in rect perimeters, ≥2-tile room separation prevents seam-merged openings (§1.3) | ✅ |

**Flag 1 (behavioral, intended):** `_is_connected()` only certifies the `player_start → stairs_pos` path. On a loop layout, a pillar/chasm revert-check can pass while having severed one *arm* of a loop (the other arm still connects start to stairs). That's fine — the floor stays fully traversable because every room still reaches the BFS-connected component through its MST edges' carved corridors, which chasms can't fully sever without failing the check... *unless* a chasm cluster lands exactly on a corridor tile. Chasm seeds are restricted to ≥2 inside large rooms, never corridors, so corridor severance is impossible; pillar placement is likewise room-interior-only. No painter change needed. If a future painter starts editing corridor tiles destructively, upgrade `_is_connected()` to "BFS reaches every room center" *then* — not now.

**Flag 2 (drift, accepted):** no `_add_room_extensions()` under LoopBuilder (§1.4) means all carved floor outside corridors belongs to a registered room rect — this is *stronger* than what painters assume today (they already tolerate unregistered extension floor), so it can't break anything, but grid-diff-based tests must not expect extension nubs on LoopBuilder floors.

---

## 8. Verification — what the implementing session actually runs

Add a temporary debug harness (a `@tool`-free static function callable from the debug panel or a scratch scene script — same pattern as the step-1 grid-diff script) that generates **200 floors** (seeds 1–20 × floors 1–10) via `LoopBuilder.build()` directly and asserts, per floor:

1. **Determinism**: building twice with the same seed yields identical `grid` (row-by-row compare) and identical `rooms` arrays.
2. **No overlaps / separation**: for every room pair, `a.grow(2).intersects(b)` is false (this is §1.3's invariant, checked post-hoc).
3. **Full connectivity**: BFS over walkable tiles from `player_start` reaches every room's center tile and `stairs_pos`. (Stricter than the runtime `_is_connected()` on purpose — this is the builder's own §6 self-check, re-verified externally.)
4. **Connections ⇄ corridors**: `connections` is symmetric (`b in a.connections ⟺ a in b.connections`); edge count = (N−1) MST edges + accepted loop edges; every edge's pair key appears exactly once in the carve dedup dict.
5. **Loops actually exist**: for floors with ≥8 rooms, edge count > N−1 (at least one loop survived §2.3's filters). If this fires frequently, `MAX_LOOP_DIST`/`MIN_LOOP_HOPS` are tuned too tight — that's the knob to inspect, not the algorithm.
6. **Entrance/Exit pacing**: the Entrance/Exit rect pair's center distance equals the max over all compatible pairs (recompute independently in the test).
7. **Boss floors** (floor 5, 10 per seed): after orchestration, `data.boss_room != Rect2i()` and `data.boss_room.has_point(data.stairs_pos)`.
8. **Fallback rate**: count `build()` nulls across the 200-floor sweep and print it. Expected: 0–1. If >4 (2%), reduce `FloorPlanner`'s room budget for LoopBuilder floors before shipping — do not silently raise `INTERNAL_RESTARTS`.

Then the human check: F5, F3 debug panel → Jump to Floor a few times, and *walk a loop* — confirm at least one floor lets you reach the stairs by two visibly distinct routes, doors spawn sanely at corridor mouths, and pillars/water/grass look like they always did. That last item is the real acceptance test; the 8 assertions just make regressions cheap to localize forever after.

---

## 9. Session sizing

This is **one Claude Code session** (IMPLEMENTATION_SEQUENCE.md 5c), comfortably under the ≤5-6 file rule:

| File | Change |
|---|---|
| `scripts/dungeon/builders/loop_builder.gd` | **new** — everything in §1–§4, §6 layers 1–2 (~250 lines incl. the Prim's and candidate-filter helpers) |
| `scripts/dungeon/dungeon_generator.gd` | orchestration only: builder selection, §6 layer-3 retry loop, §5 boss_room assignment (if not already extracted at step 1) |
| debug harness (scratch script or a `debug_panel.gd` button) | §8 assertions; deletable or kept behind F3 |

No new helper class files: the adjacency structure is two local Dictionaries (§2), and no `Room`/`DungeonData`/`FloorPlanner`/`LevelPainter`/`BspBuilder` file is touched at all — which is itself a design goal this doc meets: `LoopBuilder` is a pure drop-in behind the duck-typed build contract. Update `scripts/dungeon/CLAUDE.md` and the root `CLAUDE.md` dungeon pointer in the same session per the maintenance rule.

**Assumptions this doc makes explicit** (verify at implementation time, revise here if wrong): (a) migration step 1 already moved `boss_room`/`player_start`/`stairs` logic per §4–§5's split — if the step-1 session made a different call, follow *its* call and amend this doc; (b) `BspBuilder`'s planned-rooms-onto-leaves mapping tolerates arbitrary room lists (it must, per Dungeon doc §7's "guaranteed success" — if it turns out to have a failure mode, that's a step-1 bug to fix there, not something LoopBuilder's fallback path should paper over); (c) `FloorPlanner`'s room budget for 48×48 stays ≤15 — if a future "large" feeling pushes it past ~18, revisit §1's density math before blaming the retry counters.
