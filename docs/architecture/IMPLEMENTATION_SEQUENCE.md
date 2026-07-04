# Implementation Sequence

How to turn the five architecture docs (`TALENT_SYSTEM_ARCHITECTURE.md`, `REST_SYSTEM_IMPLEMENTATION.md`, `SAVE_LOAD_ARCHITECTURE.md`, `ENEMY_SYSTEM_ARCHITECTURE.md`, `DUNGEON_GENERATION_ARCHITECTURE.md`) into a sequence of Claude Code sessions, each small enough to stay well inside a session's productive context budget. This doc is itself a spec — a future Claude Code session should be able to read only this file plus the one doc it's currently implementing, and know exactly what to do and what NOT to touch yet.

---

## 1. Dependency graph (why this order)

```
Rest system ─────────────┐
                          ├─→ Talent boss-gate + subclass select (needs long_rest() chokepoint
Seeded floor population ──┤    for Zealous Presence/Blessed Warrior charge refill timing)
                          │
                          ├─→ Save/Load Phase A (needs seeded population for reproducible
                          │    floor reload; needs rest system's resource fields finalized
                          │    before writing to_dict/from_dict for them)
                          │
Dungeon pipeline ─────────┘ (independent of the above three, but Save/Load Phase B and the
                              Rng retrofit both want the pipeline's builders to already be
                              seeded/deterministic — sequence it before Phase B, not before Phase A)

Enemy decide/execute split ─→ independent of everything above; can happen anytime, but doing
                               it before Phase B saves makes "floor_state" serialization
                               (Enemy doc's decide/execute seam) cheaper to write correctly.

Tier 3/4 talents, Phase B saves, project-wide Rng retrofit — all explicitly LAST, because each
depends on infrastructure only fully proven once the above sessions have shipped and soaked.
```

**Recommended order:**
1. Rest system (small, unblocks Natural Sleeper retarget + gives Save doc concrete fields)
2. Seeded floor population (tiny, unblocks Save Phase A + is prerequisite for Dungeon pipeline's builder retry logic)
3. Save/Load Phase A
4. Talent boss-gate + subclass-select overlay (Tier 2 unlock machinery — the parts of the Talent doc not already implemented)
5. Dungeon pipeline, step-by-step per the Dungeon doc's own §8 migration path (wrap-BSP commit first)
6. Enemy decide/execute split + attack-resolver extraction
7. Last, in any order once the above have soaked: Tier 3/4 multiclass talents, Save/Load Phase B, project-wide Rng retrofit

---

## 2. Session sizing

Each numbered item above is **one Claude Code session**, further split if it touches more than ~5-6 files. Concrete breakdown:

| # | Item | Files touched | Notes |
|---|---|---|---|
| 1 | Rest system | `game_state.gd`, `item.gd` (ration item), `hud.gd` or short-rest panel script, `player_actions.gd` | Remove hunger dead code in the SAME session (per REST doc) — don't leave both systems live even briefly |
| 2 | Seeded floor population | `dungeon_floor.gd` only (thread one seeded `RandomNumberGenerator` through `_spawn_*()`) | Zero risk, purely mechanical, no behavior change to observe besides reproducibility |
| 3a | Save/Load skeleton | new `save_manager.gd`, `project.godot` (autoload registration) | Atomic write/backup + delete-on-death, no game-state serialization yet |
| 3b | Save/Load to_dict/from_dict | `stats.gd`, `item.gd`, `game_state.gd` (talent replay load path) | Split from 3a because it's the part most likely to need iteration once real fields are seen |
| 3c | Save/Load Continue flow | main menu / class-select script, `dungeon_floor.gd` load-into-floor path, lifecycle notification root node | UI wiring, separate from data-layer work in 3b |
| 4a | Talent boss-gate + pending points | `game_state.gd` (points-per-tier dict, `tier_unlocked()`) | Per Talent doc — mostly additive to existing tier scaffolding |
| 4b | Subclass-select UI | new/extended talent picker overlay script | Depends on 4a's state existing |
| 5a | Dungeon: wrap-BSP pipeline commit | new `room_type.gd`, `floor_planner.gd`, `builders/bsp_builder.gd`, `level_painter.gd`, `dungeon_generator.gd` (becomes thin orchestration) | Must byte-diff against pre-migration output before merging (Dungeon doc §8 step 1) |
| 5b | Dungeon: TrapRoom + feelings | `floor_feeling.gd`, `TrapRoom`/room-pool wiring | |
| 5c | Dungeon: LoopBuilder + retry/fallback | `builders/loop_builder.gd`, orchestration retry logic | |
| 6 | Enemy decide/execute split | `enemy.gd` only | Behavior-preserving refactor, verify by playtest before adding archetypes |

Sessions 5d+ (Shop/Treasure/Garden/Secret room content) and the Enemy doc's archetype/ability/phase layers are **content sessions**, sized and scheduled whenever that specific content is actually being designed — not pre-scheduled here.

---

## 3. Risk ranking

**Highest risk (most likely to need architectural revision after seeing real code):**
- **Dungeon Build phase** (`LoopBuilder` specifically) — room-graph loop generation is the one piece of this whole set that doesn't yet have a working reference implementation in this codebase (unlike BSP, which already exists and is just being wrapped). Expect the first `LoopBuilder` session to reveal edge cases (retry budget, corridor overlap with existing rooms) not fully specced in the Dungeon doc.
- **Save/Load Phase B** (mid-floor serialization) — depends on every other system (enemies, doors, traps, floor items) already exposing itself in a serializable shape; the Save doc flags this as the reason Phase A intentionally excludes it. Don't start Phase B until Phase A has run for real and the "per-floor mutable state lives in Vector2i-keyed dicts" invariant (§4 below) has actually been followed by every intervening session.

**Lowest risk (safe to implement early, unlikely to need revisiting):**
- Hunger removal / rest system — self-contained, well-understood D&D mechanic, no unresolved design questions.
- Seeded floor population — mechanical RNG threading, behavior-preserving by construction (verify via reproducibility test, not guesswork).
- Talent boss-gate/pending-points — the hard design decisions were already made in the original brief; this is translation into the existing tier-scaffolding pattern, not new design.

---

## 4. Architectural invariants (future sessions must never violate)

Additive to the existing root `CLAUDE.md` conventions (`game_log()`, explicit typing, signals-not-polling, `ALL_ITEMS` mirror, "1 action = 1 turn" / no generalizing `revert_to_waiting()`, checks-not-saving-throws, damage-stacking-one-call-site rule, `apply_player_status()` chokepoint, invincible-mode consumption guards — all of these still apply unchanged):

1. **`GameState.long_rest()` is the only resource-refill site.** `advance_floor()` never restores HP/charges/hit-dice directly — it calls `long_rest()` if the player has rations, per the Rest doc. Any new long-rest-gated resource (future spell slots, new subclass charges) hooks into `long_rest()`, never into `advance_floor()` directly.
2. **Abilities are derived state, never serialized directly.** Save/load rebuilds `Ability` objects by replaying `_apply_talent_rank()`, per the Save doc §4.3. A future talent must not require saving anything beyond `talent_investments` + a small per-ability `{uses_remaining, is_active}` map.
3. **Every serialized class uses hand-written `to_dict()`/`from_dict()`.** Never `store_var()` a Resource or object. `Vector2i` → `[x, y]` arrays via the shared helper in `SaveManager`.
4. **Multiclass Tier-3 talent ids use the `mc_<class>_` namespace** (e.g. `mc_ranger_hunters_mark`) to avoid colliding with that class's own Tier-1 talent ids when a Barbarian takes a Ranger-flavored Tier-3 talent.
5. **Room placeholder = inherit `StandardRoom`, don't override `paint()`.** Never write an `if not room.has_content(): fallback()` runtime check — the fallback is structural (inheritance), not conditional.
6. **Builders are duck-typed drop-ins**: `build(rooms: Array[Room], rng: RandomNumberGenerator) -> DungeonData`, return `null` on failure, never partially mutate a returned `DungeonData` that the caller might keep.
7. **`DungeonData`'s existing public fields never break.** New fields (`feeling`, `room_metadata`) are additive; `grid`/`rooms`/`player_start`/`stairs_pos`/`boss_room`/`start_room`/`width`/`height` and their current semantics are permanent load-bearing API for `DungeonFloor`.
8. **New gameplay-affecting randomness goes through the shared `Rng` service once it exists** (post project-wide retrofit) — cosmetic randomness (tween jitter, particle offsets, animation timing) stays on the global unseeded RNG deliberately and is never migrated.
9. **New per-floor mutable state lives in `Vector2i`-keyed dictionaries on `DungeonFloor`** (mirroring `_doors`/`_traps`/`_floor_items`), never as loose per-node-only state — this is what makes Save/Load Phase B possible later without another audit sweep.
10. **`Enemy` gains archetypes/abilities/phases via pool data + the `_decide_action()`/`_execute_action()` seam, never via subclassing.** A new enemy type is a new `ENEMY_POOL`/`BOSS_POOL` entry, not a new `.gd` file extending `Enemy` (that path stays reserved for genuinely novel movement/rendering, which none of the currently planned content needs).
