# Enemy System Architecture

Current enemies (`scripts/entities/enemy.gd`, 413 lines) are a single `Enemy` class extending `Entity`, driven by a `Behavior` FSM (`SLEEPING → STATIONARY/ROAMING → CHASING → SEARCHING`) and configured entirely from `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL` dictionaries. This works well and should **not** be rewritten. This doc specs the minimal refactor that unlocks archetypes, boss phases, enemy abilities, and Phase-2 determinism without a rewrite.

---

## 1. Core decision: keep the FSM, split decide/execute

**Rejected: behavior trees / utility AI.** This is a solo-dev project with ~5-10 enemy types; a BT framework is pure overhead for what a 5-state enum with pool-driven stats already does cleanly. The FSM stays exactly as documented in `scripts/entities/CLAUDE.md`'s "Enemy behavior states" section.

**The one refactor to do now:** split `take_turn()` into two functions:

```gdscript
func _decide_action() -> Dictionary:
    # Pure(ish) — reads self/dungeon_floor/player state, returns intent, does NOT await or mutate visuals.
    # { "type": "attack"|"move"|"wait"|"ability", "target": Player/Enemy, "dir": Vector2i, "next_pos": Vector2i, "ability_id": String }
    ...

func _execute_action(intent: Dictionary) -> void:
    # All the current tween/animation/await/log code, dispatched on intent.type.
    ...

func take_turn() -> void:
    var intent := _decide_action()
    await _execute_action(intent)
```

Why this split and not a bigger rewrite: every current branch in `take_turn()`/`_act_toward()` already *computes* a decision (attack vs. step direction vs. random step) before doing anything visual — the awaits and tween calls are interleaved with the decision logic today, but they don't have to be. Pulling the decision out into a pure function that returns a `Dictionary` is a mechanical extraction, not new design. This is the single seam every future need (determinism, archetypes, boss phases) hangs off of:
- **Determinism (Phase 2):** a pure `_decide_action()` — given a snapshot of game state and an `Rng` — is the thing that must produce identical results across clients. `_execute_action()` stays purely cosmetic (tweens, `await get_tree().create_timer(...)`, sprite flips) and never affects gameplay outcome, so it can differ per-client (fast_mode, animation speed) without breaking sync.
- **Boss phases:** a phase override changes what `_decide_action()` considers (e.g. add an `"ability"` option to a melee boss's decision), not how `_execute_action()` animates a move.
- **Archetypes:** ranged/caster enemies only need a different `_decide_action()` branch (shoot vs. approach) reusing the exact same `_execute_action()` move/wait paths.

Do this split before anything else in this doc — it's low-risk (behavior-preserving), touches only `enemy.gd`, and every later item builds on it.

---

## 2. Archetypes: pool data, not subclasses

**Rejected: `RangedEnemy extends Enemy`, `CasterEnemy extends Enemy` subclasses.** The project's whole enemy-configuration philosophy is "one class, data-driven pool dict" (mirrors items/talents). Subclassing per archetype would fork `_decide_action()` N ways and fight the pool system's `configure(type_data)` pattern.

Instead, add an `attack_profile` key to pool entries (default absent = current melee-adjacent-only behavior, zero change for existing entries):

```gdscript
# DungeonFloorData.ENEMY_POOL entry examples:
{"display_name": "Orc Warrior", ...}                                   # unchanged — implicit melee
{"display_name": "Goblin Archer", "attack_profile": {"kind": "ranged", "range": 5, "projectile": "arrow"}}
{"display_name": "Necromancer", "attack_profile": {"kind": "caster", "abilities": ["summon_skeleton", "slow_bolt"]}}
```

`_decide_action()` reads `_type.get("attack_profile", {}).get("kind", "melee")` and branches:
- **melee** (default): today's logic unchanged — adjacent → attack, else step toward target.
- **ranged**: if `has_ranged_los(grid_pos, player.grid_pos)` and Chebyshev distance ≤ `range` → intent `{"type": "attack", "attack_profile": "ranged"}`; else step toward player until in range (reuse `_act_toward`'s stepping, just gate the "attack if adjacent" check on range instead of `== 1`).
- **caster**: picks an ability from `abilities` whose cooldown (tracked per-instance, see §3) is ready and whose trigger condition holds (e.g. `slow_bolt` wants LOS + range; `summon_skeleton` wants no allies nearby) → intent `{"type": "ability", "ability_id": ...}`; else falls back to melee-style approach.

**Shared attack resolver.** `_attack_player()`'s body (roll d20 + bonus, ADV/DISADV net, crit/miss, damage, `take_damage_raw`, log with `ehit`/`edmg` tooltip tags) is currently melee-only-shaped but has nothing melee-specific in it except being called only when adjacent. Extract the roll-and-resolve body into `_resolve_attack_roll(attack_bonus_override: int = -1, damage_type: String = "Bludgeoning") -> void` so ranged/caster attacks call the *same* resolver (same tooltip format, same crit banner, same Retaliation hook) instead of duplicating combat math. This is the enemy-side mirror of the player's "one call site, one floater" damage-stacking rule (`scripts/entities/CLAUDE.md`).

---

## 3. Enemy abilities: mirror the player talent philosophy exactly

Player talents already establish the pattern this project uses for "data describes the knob, code dispatches the effect" (`scripts/items/talent.gd` + `GameState._apply_talent_rank()`). Enemy abilities should reuse the *same* shape, not invent a parallel one:

```gdscript
# Pool entry:
"abilities": [
    {"id": "slow_bolt", "cooldown": 4, "range": 6, "dmg_min": 2, "dmg_max": 5},
    {"id": "summon_skeleton", "cooldown": 8},
]
```

- **State:** `Enemy._ability_cooldowns: Dictionary = {}` (`ability_id -> turns_remaining`), decremented once per `take_turn()` regardless of what action was taken this turn.
- **Dispatch:** one `match ability_id:` block in `_execute_action()` (mirrors `player.gd._use_ability_slot()`'s dispatch-by-id pattern) that calls into existing chokepoints wherever possible instead of inventing new ones:
  - status/debuff application → `GameState.apply_player_status(type, turns)` (already the single chokepoint, already handles Rager R1 negation)
  - forced movement → `DungeonFloor.force_move_entity()`
  - resisted effects → `Enemy.resist_check(dc, use_con)` (already generic, already used by World Tree talents against enemies — symmetric reuse)
  - summoning → same node-instancing path `_spawn_enemies()` already uses, just triggered at runtime instead of floor-load time
- **No new "enemy ability" resource class needed.** Unlike player abilities (which need `uses_remaining`/`icon_path`/ability-bar UI), enemy abilities have no UI surface — a plain pool dict + cooldown int is sufficient. Do not build an `EnemyAbility` Resource class; that's the over-engineering trap for something with no UI to serve.

---

## 4. Boss multi-phase behavior

Add to `BOSS_POOL` entries only (never touches the base `Enemy` class):

```gdscript
"phases": [
    {"hp_pct": 100, "attack_profile": {...}, "abilities": [...]},
    {"hp_pct": 50,  "attack_profile": {...}, "abilities": [...]},   # e.g. adds a new ability at half HP
    {"hp_pct": 20,  "enrage_dmg_mult": 1.5},
]
```

`_current_phase() -> Dictionary` computes `stats.current_hp / stats.max_hp * 100`, returns the highest-threshold phase entry whose `hp_pct` the boss is at-or-below. Called at the top of `_decide_action()` each turn; phase data merges over the base `_type` dict for that turn's decision only (never mutates `_type` itself, so phase transitions are naturally reversible if HP is later restored — e.g. by a future healer minion — without extra bookkeeping). **No base-class change**: this is purely a richer `_decide_action()` read, exactly the seam §1 created. Add `boss_id: String` to `BOSS_POOL` entries (also required by the Talent doc's boss-gate — `"eye_boss"`/`"big_demon"`/`"necromancer"` — so both systems key off the same id instead of matching on `display_name` strings, which are UI text and shouldn't be load-bearing).

---

## 5. Targeting: player and companion are both valid targets (owner decision, 2026-07)

The owner decided: enemies must be able to target `Companion` (Wild Heart summon), not just the player, and the rule is **whoever first gets into the enemy's attack range wins the fight** — not "whoever was spotted first." This turns out to need **no new state at all**, which is why it's the right rule for this project (simplest option that is also correct):

- `_decide_action()`'s target selection stops hardcoding `player` and instead considers every `is_friendly` entity currently visible (`Entity.is_friendly` already exists — added for Zealous Presence AOE targeting, reused here verbatim): today that's `[player, GameState.player_companion]` (skip the companion if null/dead).
- **Adjacency check comes first, over both candidates.** If either candidate is already adjacent (Chebyshev 1) this turn, attack it — this is the literal "first to arrive in range" rule: whichever entity reaches melee range first is the one that gets hit that turn, full stop, no memory of who was seen earlier. If both happen to be adjacent simultaneously (rare — both flanking), tie-break by picking the lower current HP target (makes the enemy feel like it's finishing a kill, costs one extra comparison) — arbitrary but deterministic; a simpler `player`-first tie-break is equally fine if that one line of nuance isn't wanted.
- **If nothing is adjacent, step toward the nearer visible candidate** (Chebyshev/Manhattan distance — reuse whatever `_act_toward` already computes for the player, just compute it for both and take the min). No `current_target` field, no lock, no "don't switch target mid-chase" logic — every turn simply re-asks "who's closest / who's adjacent" from current positions.
- **Why no target-lock instead:** a lock (remember whoever triggered the wake, stick to them until dead/lost) was the other option on the table and was rejected — it needs a new persisted field (`current_target: Entity`, nil-checked on death/despawn) and extra transition logic (when to drop the lock, what happens if the locked target leaves FOV vs. the other one is now adjacent) for a behavior difference that's barely noticeable in play: in the vast majority of encounters the nearest visible entity *is* the one that gets there first anyway. The no-state version is strictly less code for a rule the owner explicitly asked for ("first to reach range"), so it wins even though a lock is a defensible alternative.
- **Ranged/caster archetypes (§2) reuse the same candidate list** — "step toward nearer candidate" becomes "attack whichever candidate is in range and LOS, preferring the closer one if both qualify," no new concept.
- **Minor cosmetic wrinkle, not a bug:** because target is re-evaluated every turn from raw distance, an enemy mid-approach can be seen to "flicker" which entity it's angling toward if the player and companion are near-equal distance and both moving. This never affects who actually gets attacked (that's still decided purely by adjacency), so it's cosmetic only — do not add hysteresis/lock to fix it unless it's visibly bad in playtesting.
- **Companion doc note:** `Companion.take_damage_from_enemy()` already exists and is the correct intake path — this section only changes who enemies choose to walk toward/swing at, not how damage lands on `Companion` once chosen.

---

## 6. Determinism constraints for Phase 2

Current non-deterministic call sites in `enemy.gd`: `randi_range()` in `resist_check()`/`_attack_player()`, `.shuffle()` in `_pick_roam_target()`/`_do_random_step()` — all use the global unseeded RNG (consistent with the rest of the codebase per the SAVE doc §6).

**Do not retrofit these now.** Per the SAVE_LOAD doc's Rng-service plan, this is one mechanical sweep done once, project-wide, right before Phase 2 (or before Phase-B mid-floor saves, whichever lands first) — retrofitting `enemy.gd` alone ahead of that sweep just creates two RNG conventions to keep straight. What **does** matter now, cheaply:
- Keep enemy turn iteration in registration order (`TurnManager` already does this — don't introduce a Dictionary iteration anywhere in the enemy turn loop, since Dictionary key order is insertion-order today but is not a documented guarantee to lean on further).
- Keep all `await get_tree().create_timer(...)` calls purely cosmetic pacing (they already are) — never let a timer duration or `fast_mode` flag influence a decision, only how fast it's drawn.
- When `_decide_action()` lands (§1), it becomes the single function whose output must be reproducible from `(dungeon_floor state, player state, Rng)` — this is a useful invariant to hold in mind while writing it even though the actual Rng-threading happens later.

---

## 7. Immediate next steps (in order, this is the whole scope — no bigger rewrite)

1. **Split `take_turn()` → `_decide_action()` + `_execute_action()`** (§1). `enemy.gd` only. Verify: existing behavior identical (manual playtest — sleeping/roaming/chasing/searching enemies all act the same).
2. **Extract `_resolve_attack_roll()`** from `_attack_player()` (§2). `enemy.gd` only.
3. **Generalize targeting to player + companion** (§5) — same session as step 1, since it changes the shape of `_decide_action()`'s target-selection block anyway; doing it separately would mean touching that block twice. `enemy.gd` only (reads `GameState.player_companion`, no `Companion` changes needed).
4. **Add `attack_profile` support** to `_decide_action()`/`_execute_action()`, starting with `"ranged"` only (no caster enemies exist yet — build that branch when the first caster is actually added, not speculatively). `enemy.gd` + one new `DungeonFloorData.ENEMY_POOL` entry to prove it out.
5. **Add `boss_id` + `enemy_id` string keys** to pool entries (`dungeon_floor_data.gd`) — needed by both this doc's boss-gate and the Talent doc's boss-gate. No behavior change by itself.
6. Stop here. Ability-cooldown dict (§3) and phase computation (§4) are cheap additions layered on top of steps 1-5 whenever the first caster/boss-phase content actually needs them — do not build the ability/phase machinery speculatively ahead of a concrete enemy that uses it.
