# Companion AI Architecture

`ENEMY_SYSTEM_ARCHITECTURE.md` covers only the hostile `Enemy` class; this doc covers the friendly side: `Companion` (`scripts/entities/companion.gd`, ~172 lines), currently the Wild Heart One-with-Nature summon and the only ally entity in the game. The headline recommendation is deliberately anticlimactic: **the current implementation is the right size — do almost nothing now.** This doc records why, what the real seams are for later, and the two documentation/design items that do need attention.

Consistent with the project owner's framing: multiplayer is not a goal and this doc does **not** address determinism or sync for companions. Companion attack rolls (`randi_range` in `_attack_enemy()`) stay on the global unseeded RNG indefinitely, same as all combat RNG (see `SEEDED_FLOOR_POPULATION.md`'s scope note narrowing SAVE doc §6).

---

## 1. What Companion does today (from the code, 2026-07)

- **Class shape:** `extends Entity`, `is_friendly = true`. Same configure-before-`add_child` pattern as `Enemy`: `configure(d)` copies `animal`/`ac`/`die_count`/`die_sides` from a plain dict; `Stats` is created in `_ready()` (only `max_hp`/`current_hp`/`armor_class` used). Sprite is a placeholder (green-tinted wizard). Spawned by `PlayerWildHeart` → `DungeonFloor.spawn_companion(companion, pos)` at the nearest free adjacent tile; configured from `GameState.WILD_HEART_COMPANION_STATS[rank]` (Squirrel/Boar/Bear).
- **Turn scheduling:** `TurnManager.register_enemy(self)` in `_ready()` — companions share the enemy phase and act in registration order (after all floor enemies, since it registers at summon time). There is no separate ally phase and none is needed.
- **`take_turn()` is a stateless priority list, not an FSM.** Each turn, in order: (1) decrement own `zealous_presence_turns`; (2) find nearest enemy within `SIGHT_RADIUS = 6` Chebyshev with `has_line_of_sight()` — if adjacent, attack; else BFS one step toward it; (3) no visible enemy → if farther than `FOLLOW_DISTANCE = 3` from the player, step toward the player; else idle. No behavior enum, no memory (`last_known_player_pos`-style fields), no roam/search states. It re-derives everything from current positions every turn.
- **Combat:** `_attack_enemy()` rolls a bare d20 (comment: "no proficiency — animal instinct"), Zealous Presence grants ADV, nat 20 = ×2 crit, kill grants the player `exp_reward / 2` via `GameState.gain_exp()`. Logs with the `catk` tooltip tag (per the chat-log tooltip rule).
- **Damage intake:** enemies never attack it — `take_damage_from_enemy()` exists but its only current callers are non-enemy sources; "Enemies ignore companions (MVP)" per `scripts/entities/CLAUDE.md`. On death: `GameState.player_companion = null`, unregister, `remove_companion()`, `queue_free()`.
- **Lifetime:** does **not** survive floor transitions — `DungeonFloor._load_floor()` frees all companions and nulls `GameState.player_companion` before generating the new floor. The player re-summons using the One with Nature charge, which refreshes on rest. `heal_to_max()` fires on short rest and (currently) `advance_floor()`.
- **Divergence from `Enemy`:** no pool-driven stat *scaling* (companion stats are flat per rank, no per-floor growth), no FSM, no `_attack_player`-style resolver, no sleep/roam. Shared with `Enemy` only via `Entity` (grid_pos, `move_to()` tween) plus two small copied idioms (open-unlocked-door-before-step, the cosmetic `await timer` pacing).

**Stale doc to fix (flagged, not silently worked around):** `scripts/entities/CLAUDE.md`'s Companion section says "Attack rolls: d20 + `player_stats.proficiency_bonus`" — the live code deliberately adds *no* proficiency. The CLAUDE.md line is stale; correct it whenever that file is next touched.

---

## 2. Should Companion get the `_decide_action()` / `_execute_action()` split?

**No — not now.** The Enemy doc's split earns its keep from three consumers: archetypes (ranged/caster branch in decide), boss phases (phase-merged decide input), and Phase-2 determinism. For `Companion`: there are no archetypes (all three ranks are the same melee brain with bigger dice), no phases, and determinism is off the table. `take_turn()` is ~20 lines with one decision branch; extracting a pure decide function would be a seam with zero consumers — exactly the speculative structure every doc in this set rejects.

**Revisit trigger (write it down so it isn't relitigated):** the split becomes worth doing the day a *second companion behavior* actually lands — e.g. a ranged companion (hawk that shoots), a healer summon, or per-animal quirks (Boar charge, Bear taunt). At that point, follow the Enemy doc's pattern exactly: one `Companion` class, a `behavior_profile` key in the stats dict, branch in a then-extracted `_decide_action()` — never subclass per animal (mirrors invariant 10 in `IMPLEMENTATION_SEQUENCE.md`).

Same verdict on a shared `Enemy`/`Companion` base class or mixin: **rejected.** The duplicated code is ~10 lines of door-opening and timer pacing; a shared base would couple the hostile FSM's future churn (decide/execute split, attack profiles) to a class that needs none of it.

## 3. Future companion variety and data shape

`WILD_HEART_COMPANION_STATS` (rank → `{animal, ac, hp, die_count, die_sides}` on GameState) is already the project's pool-dict pattern in miniature, and `configure()` already takes a plain dict — so if a second summon *source* ever appears (the most plausible: a future Wizard/spellcaster summon spell), generalizing is cheap and mechanical: promote the table to a `COMPANION_POOL` keyed by `companion_id` (mirroring `ENEMY_POOL`'s shape, living beside it in `dungeon_floor_data.gd`), and have One with Nature map rank → id. Nothing in `companion.gd` changes.

**Recommendation: do not generalize yet.** Exactly one summon source exists, no second one is designed, and the promotion is a one-session rename whenever it's real. Recording the target shape above is the whole preparation needed.

## 4. Targeting and aggro — is "nearest visible enemy" enough?

**Yes, keep it — do not give Companion the Enemy FSM.** Roam/search states exist so hostile enemies feel alive in a fog-of-war world the player hasn't scouted; a companion is anchored to the player (`FOLLOW_DISTANCE`) and its whole world is the player's vicinity. Nearest-visible + follow + idle covers that. Adding SEARCHING/ROAMING would produce a pet that wanders off-screen — worse behavior for more code.

One real gameplay wrinkle found in the code — **owner decision (2026-07): keep it.** `_find_nearest_visible_enemy()` does not filter on enemy behavior state, so a companion will walk up to and attack a `SLEEPING` enemy within its 6-tile sight. Confirmed as intended ("my bear hunts") — no code change needed here; this section stays as documentation of why the no-filter behavior is deliberate, not an oversight, should it come up again later.

## 5. Interaction with the Enemy doc's planned changes

- **Should enemies ever target the Companion? Owner decision (2026-07): yes.** Rule: whichever of player/companion first reaches the enemy's attack range gets attacked — see `ENEMY_SYSTEM_ARCHITECTURE.md` §5 for the full spec (no target-lock, no new state, just widen the existing adjacent-or-step-toward check from "player" to "nearest visible `is_friendly` entity"). `Companion.take_damage_from_enemy()` is already the correct intake path on this side — nothing in `companion.gd` needs to change for this. Implement alongside the Enemy doc's step 1 (decide/execute split), per that doc's §7 step 3, since it reshapes the same target-selection code the split is already touching.
- **Turn order:** companion acts after all enemies (registration order). Harmless today; if enemies ever target companions, note that a summon made this turn is attackable before it ever acts. Fine — just don't "fix" registration order ad hoc.
- **Zealous Presence** already treats Companion correctly via `Stats.zealous_presence_turns` on its own Stats resource, ticking on its own turn — the reference for any future ally-scoped buff.

## 6. Save/load implications

`SAVE_LOAD_ARCHITECTURE.md` §4.4 plans to persist `{alive, current_hp}` for the companion and rebuild it on load. **Finding from the code: for Phase A this is unnecessary — persist nothing.** Phase A checkpoints at floor entry, and `_load_floor()` has *already* freed the companion and nulled `GameState.player_companion` by then; at every Phase-A save point the companion does not exist. The One with Nature charge is derived ability state, already covered by §4.3's `{ability_id: uses_remaining}` map. So §4.4's companion line is moot until **Phase B** (mid-floor saves), where `{alive, current_hp, grid_pos}` + rebuild-from-stats-table becomes the right (and still adequate) shape. Not a contradiction to rewrite the SAVE doc over — just implement Phase A without companion fields, and fold `grid_pos` into the §4.4 plan when Phase B is specced. Note the REST doc moves the companion heal from `advance_floor()` to `long_rest()`; nothing here conflicts with that.

## 7. What to actually do now (complete list)

1. Nothing structural. `companion.gd` stays as-is.
2. Fix the stale proficiency line in `scripts/entities/CLAUDE.md` (§1) next time that file is edited.
3. Owner decisions queued (no code until answered): sleeping-enemy aggro filter (§4); enemies targeting companions once archetypes land (§5).
4. When Phase A save lands: skip companion serialization per §6.
