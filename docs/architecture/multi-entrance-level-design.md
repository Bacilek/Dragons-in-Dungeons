# Multi-Entrance Level Connectivity — Design Doc

Status: **design only, not implemented.** No code ships with this doc.

Floors today guarantee reachability (start → stairs has *some* path) but nothing guarantees more
than one. Pixel Dungeon's defining "you can always go around" feel requires the Entrance room to
have ≥2 distinct connections to *different* rooms/corridors, and the Exit room (the room holding
`stairs_pos`) likewise ≥2 distinct incoming connections — usually exactly 2, occasionally more,
never two doors into the same neighbor. Root cause of the gap: `LoopBuilder._assign_farthest_pair()`
(`scripts/dungeon/builders/loop_builder.gd:260-298`) deliberately assigns Entrance/Exit to the
Manhattan-farthest room pair, which makes Prim's MST (`loop_builder.gd:128-157`) overwhelmingly
likely to attach each of them as a degree-1 leaf — and the floor-wide loop-edge budget
(`num_loops = clampi(n / LOOP_DIVISOR, 1, 3)`, line 160) has zero bias toward covering them. Nothing
in the pipeline measures or enforces a minimum degree for any room today.

Function/field names and line numbers cited below were verified against the working tree at time
of writing; re-verify line-level details before editing, but structural shape is authoritative.
This doc is orthogonal to `special-rooms-economy-design.md` (room *content/economy*, not
connectivity) but touches the same `Room.max_connections()` family and Build pipeline — cross-
referenced where relevant, not merged, since the two tracks are independently shippable (that
doc's sessions 7c–7f are still pending and this feature does not depend on them).

---

## 1. Current state — what exists, what is greenfield

**Greenfield:**
- **No `min_connections()` concept.** `Room` (`scripts/dungeon/room_type.gd:26-27`) has only a
  `max_connections() -> int` ceiling (default 4), no floor.
- **No per-room degree check anywhere.** `_all_rooms_reachable()`
  (`loop_builder.gd:358-375`) is a single-source tile BFS proving every room center + stairs is
  *reachable*, not that any room has more than one edge.
- **BspBuilder has no room-adjacency graph and no Entrance/Exit identity during Build.**
  `BspBuilder.build()` (`scripts/dungeon/builders/bsp_builder.gd:23-46`) never touches
  `Room.connections` (LoopBuilder is the only builder that populates it, per the header comment
  at `loop_builder.gd:24`). `player_start`/`stairs_pos` are chosen afterward by the orchestrator —
  `player_start` = smallest room, `stairs_pos` = Manhattan-farthest room from start
  (`scripts/dungeon/dungeon_generator.gd:57-83`) — on the *finished* grid, after
  `_add_extra_corridors()` has already run.

**Already in place, reused as-is:**
- LoopBuilder's loop-edge machinery: candidate enumeration (`loop_builder.gd:161-173`), the 5
  disqualification rules (lines 181-199), `_record_edge()` (lines 250-256), `_l_path_clear()`
  (lines 328-345). §4's forced pass is a re-parameterized run of this exact loop, not new
  machinery.
- `MIN_LOOP_HOPS = 3` (rule 4, line 37, `_bfs_hops()` lines 314-325) already encodes precisely the
  "not a trivial parallel path" semantics needed for "distinct route" (§2 Tier B).
- Retry/fallback orchestration: LoopBuilder returning `null` already cascades through
  `INTERNAL_RESTARTS` (line 30) → `BUILDER_RETRIES` (`dungeon_generator.gd:23`) → BspBuilder. The
  new guarantee plugs into failure semantics that already exist — no new plumbing.
- `LoopBuilder.last_stats` (`loop_builder.gd:41`, consumed only by `_verify/loop_check.gd`) — the
  natural home for degree telemetry (§6).
- `_spawn_doors()`'s narrow-junction perimeter scan (`scripts/world/dungeon_floor.gd:1252-1290`)
  and its Chebyshev-distance-2 declutter rule (lines 1281-1287) — the algorithmic template for the
  grid-level "corridor mouth count" check used to validate the BSP path (§6), and precedent that
  geometric crowding is already handled as a decorative-layer concern, not a generation-layer one
  (§2).

---

## 2. What "two distinct connections" means

Three tiers, decreasing strength:

- **Tier A (graph degree).** Entrance and Exit each have ≥2 edges in the room-connection graph, to
  *different* neighbor rooms. (`edge_keys` dedup, rule 1, already makes a double-edge to the same
  neighbor impossible in LoopBuilder.)
- **Tier B (cycle membership).** The second edge closes a cycle of hop-length ≥ `MIN_LOOP_HOPS`
  through the room — the two exits lead to genuinely different paths, not two branches of the same
  dead-end subtree. Falls out for free by reusing rule 4 unchanged in the forced pass (§4).
- **Tier C (global 2-connectivity).** Two edge-disjoint room-graph paths from Entrance to Exit
  (Menger's theorem sense). Degree ≥2 at both ends is necessary but **not** sufficient — both
  routes could still funnel through one bridge room mid-map.

**Decision: guarantee Tier A+B, measure Tier C.** Tier A+B is a local, cheap, O(candidates) check
that reuses existing rules verbatim. Tier C needs a max-flow/bridge computation; on ≤13-room graphs
it is trivial to *compute*, but *enforcing* it means a general "find and reinforce arbitrary
bridges anywhere in the graph" pass — a much larger blast radius on layout success rate for a
requirement the user's request doesn't actually demand (they asked for 2 doors out of start/into
stairs, not a full 2-edge-connected map). Ship A+B as the hard guarantee; emit a Tier C boolean in
`last_stats` (§6) and promote it to a hard requirement in a follow-up session only if measurement
shows it fails often in practice.

**Rejected: geometric perimeter separation** (e.g. "the two corridors must leave via non-adjacent
room edges"). All corridors are carved center-to-center (`_carve_l`, `loop_builder.gd:349-355`);
mouth position on the room perimeter is an emergent property of carving, not controllable at
edge-selection time without rewriting the carver. The existing Chebyshev-distance-2 door declutter
rule (§1) is precedent that geometric crowding is already handled downstream, as decoration. One
cheap mitigation is kept: when several forced-edge candidates tie on distance, prefer the one whose
direction from the room center diverges most (lowest dot-product) from the room's existing edge
direction, so the two corridors tend to leave opposite-ish sides. Residual risk (two corridors
sharing an initial carved tile) is accepted — see §9.

---

## 3. `Room.min_connections()`

**Accepted — a `min_connections() -> int` virtual on `Room`, default 1, overridden to 2 in
`EntranceRoom`/`ExitRoom`.** Mirrors `max_connections()` exactly; builders read it generically,
never special-case on `type_id` (the same invariant `FloorPlanner.plan()` already follows per
`scripts/dungeon/CLAUDE.md`). "Usually exactly 2, occasionally more" needs **zero** dedicated
logic: the forced pass (§4) tops a room up to exactly `min_connections()`, and the pre-existing
general loop-edge pass may then incidentally add a 3rd/4th edge subject to `max_connections()` —
"occasionally more" falls out of the existing budget for free, no new randomness needed.

```gdscript
# room_type.gd — next to max_connections()
func min_connections() -> int:
    return 1

# entrance_room.gd
func min_connections() -> int:
    return 2

# exit_room.gd
func min_connections() -> int:
    return 2
```

Invariant to hold for every room type: `min_connections() <= max_connections()`. Note the interplay
with `special-rooms-economy-design.md` §4's planned dead-end specials (`max_connections() = 1`):
that's a *ceiling* on an unrelated room type, this is a *floor* on Entrance/Exit — the two never
apply to the same room, and rule 2's existing degree cap already excludes a `max_connections()=1`
room from being picked as anyone's second connection once it already has one (§9).

---

## 4. LoopBuilder — forced-edge pass

Where the hard guarantee lives. Inserted between MST construction (`loop_builder.gd:157`) and the
existing general loop-edge selection (line 159):

```gdscript
# after MST, before the existing §2.2/§2.3 loop pass:
# for each room r (by index) where adjacency[r].size() < placed[r].min_connections():
#   walk the SAME sorted candidate list (loop_builder.gd:161-173), filtered to
#   edges incident to r, applying rules 1-5 unchanged — rule 4's MIN_LOOP_HOPS
#   is what delivers Tier B for free;
#   among equal-distance survivors, tiebreak by direction-divergence (§2);
#   _record_edge() the winner; repeat until r's degree meets its floor.
# relaxation ladder if a room still can't reach its floor:
#   pass 2: MIN_LOOP_HOPS 3 -> 2
#   pass 3: MAX_LOOP_DIST 26 -> 34
# still unmet -> return null from _try_layout (existing INTERNAL_RESTARTS /
# BUILDER_RETRIES / BspBuilder cascade absorbs it; no new failure plumbing)
```

Decisions to hold:

- **Forced edges do not consume the `num_loops` budget.** They are a correctness floor, not
  flavor — charging them against the existing 1-3 budget would starve genuinely optional mid-map
  loops on small floors, changing floor "feel" as an unintended side effect. The general pass keeps
  its own budget exactly as today.
- **Deterministic candidate selection, same as today.** Only the carving elbow choice draws rng
  (one draw per added edge, identical to the existing loop-edge carve at line 212) — so this is a
  **documented RNG FOOTPRINT change** (edge count → carving draw count changes), same precedent
  class as Phase 3 and session 7b (`scripts/dungeon/CLAUDE.md`).
- **Rule 2 already protects future dead-end specials.** A `max_connections()=1` special room
  already attached to the MST is automatically skipped as a far-end candidate by the existing
  degree-cap check (`loop_builder.gd:185-188`) — zero new code needed, call it out explicitly since
  it's the natural first question when the dead-end-rooms doc eventually ships (§9).
- **Often a no-op.** If the MST already gave Entrance or Exit degree ≥2 (i.e. it landed mid-tree
  rather than as a true leaf), the forced pass adds nothing for that room.

---

## 5. BspBuilder — the timing mismatch and the reinforcement pass

The structural problem to name explicitly: `BspBuilder.build()` carves geometry with **no**
Entrance/Exit identity available (Phase 1 note at `bsp_builder.gd:19-22`: the planned room list is
not consumed as a constraint). The orchestrator only decides *which* carved room is "start" and
"stairs" afterward, on the finished grid, **after** `_add_extra_corridors()` has already run
(`dungeon_generator.gd:44, 56-91`). You cannot bias `_add_extra_corridors()` toward rooms that
don't exist as identities yet.

- **Rejected: move start/exit selection earlier, into BspBuilder.** The "smallest room / farthest
  room" heuristic's position in this legacy fallback path was a Phase-1 byte-identical-output
  acceptance criterion; relocating it is a large blast radius for a rarely-exercised fallback.
- **Rejected: run `_add_extra_corridors()` a second time.** A second blind random pass still has no
  concept of which rooms are start/exit — it just adds more corridors, doesn't target the ones that
  need it.
- **Accepted — a post-selection reinforcement pass in the orchestrator.** After
  `dungeon_generator.gd` resolves `player_start`/`stairs_pos` (line 61/79) and **before**
  `LevelPainter.paint()` (line 118) — carving after painting would slice fresh corridors through
  already-placed water/grass/pillar overlays, so this ordering is load-bearing — call a new
  `BspBuilder.reinforce_min_degree(data, room_rect, rng)` once for `start_room` and once for the
  farthest/exit room: measure the room's *corridor-mouth count* directly on the tile grid (perimeter
  scan for FLOOR openings in the surrounding wall ring, merging adjacent open tiles into one mouth
  — the same narrow-junction idea `_spawn_doors()` already uses, §1), and if it's below 2, carve one
  extra L-corridor (`_carve_corridor`) from the room center to another room ≥12 tiles away not
  already directly connected — reusing `_add_extra_corridors()`'s own reject rules and 8-attempt
  retry loop (`bsp_builder.gd:198-220`) nearly verbatim, just re-targeted at a specific room instead
  of a random pair.
- **Best-effort, never fails.** BspBuilder is the guaranteed-success fallback and must keep that
  contract — if the 8 attempts fail to find a valid target, ship the floor as-is. This asymmetry
  (LoopBuilder = hard guarantee, BSP fallback = best effort) is deliberate and must be stated
  plainly; whether it matters in practice is exactly what §6's fallback-rate measurement is for.

---

## 6. Validation and instrumentation

- **Build-time enforcement** on the happy path is the LoopBuilder `null` return itself (§4) — no
  separate assertion needed.
- **`last_stats` additions**: `entrance_degree`, `exit_degree`, `forced_edges`,
  `edge_disjoint_start_exit: bool` (Tier C measurement — trivial on ≤13 nodes: remove each edge of
  one BFS path between Entrance and Exit in turn, re-BFS, see if still connected). Same "gameplay
  code must never read this" rule as the existing `last_stats` (`loop_builder.gd:39-41`).
- **Grid-level, builder-agnostic check** for the harness and for validating the BspBuilder path:
  the §5 corridor-mouth-count scan on the Entrance/Exit rect perimeter. Weaker than the graph-level
  check (two mouths belonging to one merged/adjacent corridor can fool it) but works without a
  `connections` graph, so it applies to both builders uniformly.
- **Harness**: extend the existing `_verify/` pattern (`dump_gen.gd` / a new `loop_check.gd`-style
  script per `scripts/dungeon/CLAUDE.md`) with an N-seed sweep that asserts degree ≥2 on all
  LoopBuilder floors, and — the metric that actually decides whether §5's asymmetry is acceptable —
  tracks LoopBuilder success rate before vs. after this change. A regression here is not cosmetic:
  BSP-fallback floors silently drop special rooms (`room_metadata` stays empty by design, per
  `dungeon_generator.gd:110-115`), so every extra fallback erases shop/treasure/garden/secret
  content for that floor. Acceptance bar: fallback rate must not measurably rise across the seed
  sweep — same spirit as the existing `MAX_LOOP_DIST` 20→26 tuning note (`loop_builder.gd:32-36`).

---

## 7. Doors — explicitly out of scope for the hard guarantee

**Decision: the guarantee lives at the connection-graph/corridor level; door sprites are out of
scope.** Doors in this game never gate routing on their own — they auto-open on step-in
(`scripts/world/CLAUDE.md`), and the one blocking variant (`_spawn_locked_doors()`) already
verifies via `_bfs_reachable()` that it never severs start→stairs. A room with 2 corridors and 0
door sprites already has 2 real routes; that satisfies the user's actual request ("multiple viable
paths"), independent of whether a door object happens to render at either mouth. Door count today
is a fully decoupled decorative layer (65% spawn-skip, 2-candidate-per-room cap,
`dungeon_floor.gd:1292-1301`) with no relationship to actual connection count, and aligning it buys
atmosphere, not gameplay.

Consequence: `Room.connections` does **not** need to be threaded into `DungeonData`/`DungeonFloor`.
It stays Build-internal (as it already is today — LoopBuilder populates it, nobody downstream reads
it) and continues to be discarded after Build. Revisit only if the §7 stretch item below ships.

**Optional stretch (session d, not required for the core feature)**: exempt the Entrance/Exit
rooms' door candidates from `_spawn_doors()`'s 65% skip, so both mouths of the start room visually
read as doorways. Independent `_pop_rng`-footprint change in `dungeon_floor.gd`, fully separable
from generation-layer work.

---

## 8. Sessions + dependency graph

```
   8a (min_connections + LoopBuilder forced pass)
        |
        v
   8b (harness + fallback-rate measurement) -----> gates whether 8c matters
        |
        v
   8c (BspBuilder reinforcement + orchestrator wiring)

   8d (stretch: door-spawn alignment) — independent, can land any time after 8a
```

(Session numbering provisional — assign the next free epic letter at implementation time. The
special-rooms-economy-design.md sessions 7c–7f are unrelated and unblocked by this work.)

| # | Item | Files touched | Notes |
|---|---|---|---|
| 8a | `min_connections()` virtual + `EntranceRoom`/`ExitRoom` overrides + LoopBuilder forced-edge pass + relaxation ladder + `last_stats` keys | `room_type.gd`, `entrance_room.gd`, `exit_room.gd`, `builders/loop_builder.gd` | The hard guarantee. Documented RNG-footprint change (§4). |
| 8b | Harness assertions (degree ≥2 seed sweep) + LoopBuilder success-rate before/after measurement | `scripts/dungeon/_verify/*` | Deliberately before 8c — sizes how much the BSP fallback path even matters post-8a. |
| 8c | `BspBuilder.reinforce_min_degree()` + orchestrator wiring (post-selection, pre-paint) | `builders/bsp_builder.gd`, `dungeon_generator.gd` | Best-effort; preserves the never-fails contract (§5). |
| 8d | (stretch) door-spawn alignment for entrance/exit mouths | `scripts/world/dungeon_floor.gd` | Cosmetic; independent; separate `_pop_rng` footprint change. |

---

## 9. Risks

- **Highest risk — LoopBuilder success-rate regression.** Forcing degree-2 on the farthest-apart
  room pair (i.e. rooms typically near opposite grid corners, exactly where `MAX_LOOP_DIST=26` and
  rule 5's crossing check bite hardest) can exhaust candidates and null out a layout attempt more
  often, cascading to BSP fallback — which silently deletes special-room content for that floor.
  Mitigated by the relaxation ladder (§4) plus the §6 measurement gate; the doc sets the acceptance
  bar as "fallback rate must not measurably rise."
- **Tier A+B ≠ Tier C.** A mid-map bridge room can still funnel both of Entrance's/Exit's routes
  into a single shared corridor further along. Deliberately measured, not enforced (§2); a
  promotion path to a hard Tier C requirement is defined if telemetry warrants it.
- **Corridor tile overlap.** Two graph edges can share their initial carved tiles and read
  visually as one physical mouth even though they're two graph edges. Mitigated by the
  direction-divergence tiebreak (§2); residual risk accepted since the guarantee is defined at
  graph level, not pixel level.
- **Future dead-end specials** (`max_connections()=1`, cross-ref `special-rooms-economy-design.md`
  §4, not yet implemented). Already excluded as a forced-edge target by the existing degree-cap
  rule 2 — zero new code required, but call this out since it's the first question anyone will ask
  once that doc ships. A seed where the *only* geometrically viable second target for
  Entrance/Exit is a dead-end special will simply fail that layout attempt and retry (folded into
  the §6 fallback-rate measurement, not a separate risk).
- **Lowest risk — the `min_connections()` API itself.** Purely additive virtual with a default of
  1 and no existing caller before 8a lands; cannot regress anything on its own.

---

## 10. Open questions / explicitly out of scope

- **Door-count alignment.** Out of scope for the core guarantee (§7); at most an independent
  stretch session (8d).
- **Tier C (2-edge-connected Entrance↔Exit) as a hard guarantee.** Deferred pending 8b telemetry —
  enforcing it means a general bridge-reinforcement pass over the whole graph with unknown cost to
  layout success rate; not something the user's stated requirement (2 doors in, 2 doors out)
  actually demands.
- **`min_connections()` for other room types** (e.g. guaranteeing a "hub" room's degree). No
  requirement today; the virtual makes it a one-line future change if a use case appears.
- **Threading `Room.connections` into `DungeonData`.** Not needed while doors stay out of scope
  (§7); revisit only if 8d ships and needs it.
- **A hard guarantee for the BspBuilder fallback path.** Deliberately kept best-effort (§5) —
  upgrading it to guaranteed would either break the "never fails" contract or require BspBuilder to
  actually consume the planned room list (a separate, larger roadmap item noted at
  `bsp_builder.gd:19-22`, "Phase 2+ work").

---

## Critical files for implementation

- `scripts/dungeon/builders/loop_builder.gd` — forced-edge pass (§4)
- `scripts/dungeon/builders/bsp_builder.gd` — reinforcement pass (§5)
- `scripts/dungeon/room_type.gd`, `scripts/dungeon/entrance_room.gd`, `scripts/dungeon/exit_room.gd` — `min_connections()` (§3)
- `scripts/dungeon/dungeon_generator.gd` — orchestrator wiring for §5's post-selection/pre-paint reinforcement call
- `docs/architecture/special-rooms-economy-design.md` — cross-referenced for `max_connections()` precedent and the planned dead-end-room interaction (§3, §9)
