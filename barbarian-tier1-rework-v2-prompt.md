# TASK: Barbarian Tier 1 Rework — Full Baseline Rage + Branching Talents

## Context
Repo: Bacilek/Dragons-in-Dungeons, branch `main`. Godot 4.6 Mono, GDScript only.
Read root `CLAUDE.md` and `scripts/entities/CLAUDE.md`/`scripts/autoloads/CLAUDE.md` before
touching anything. **This task supersedes `barbarian-tier1-talent-prompt.md`** (an older,
already-superseded prompt in this repo root — its "no opportunity attacks" assumption is stale,
OA is now implemented; its Rage/Reckless Attack/Danger Sense talent design is exactly what this
task replaces). Ignore that file except as historical context; do not resurrect its talent
design.

All file:line references below were verified against the working tree at time of writing.
Re-verify before editing, but function/field names and structure are authoritative.

## Why this change
Tier 1 currently makes the Barbarian's three starting talents (`rage`, `reckless_attack`,
`danger_sense`) upgrade paths for three literal D&D abilities — investing points just turns
existing mechanics up a notch. That's flat and doesn't create build diversity. Owner decision:
Rage stops being something you "unlock" via talent investment — it's the character's core
identity and should work at full strength from level 1. The 3 available Tier 1 talent slots get
replaced entirely with three new, mechanically distinct talents (Blood-Crazed, Scarred
Juggernaut, Unstoppable Force) that branch the character into different playstyles instead of
just scaling one ability.

---

## Part 1 — Rage becomes a full, unconditional baseline ability at level 1

### Current state (to be changed)
- `Player._on_turn_started()` (`player.gd:243-257`): Rage's 10-turn countdown only *pauses* while
  the player attacked/was attacked **if** `GameState.get_talent_rank("rage") >= 1`. At rank 0 the
  countdown always ticks down regardless of combat activity.
- `GameState.take_damage_raw()` (`game_state.gd:895-908`): physical damage reduction while raging
  is 0% at talent rank 0/1, 25% at rank 2, 50% at rank 3.
- The `"rage"` Talent resource (`game_state.gd:1480-1493`, tier 1, max_rank 3) exists purely to
  gate these two behaviors rank-by-rank; `_apply_talent_rank()`'s `"rage"` case
  (`game_state.gd:1058-1063`) has no other side effect beyond refreshing the ability's tooltip.
- `rage_uses_max` (`stats.gd:78`, computed from `character_level`: 2/3/4/5 at levels 1/4/6/12)
  and `rage_bonus_damage` (`stats.gd:88`, +2/+3/+4 by level) are **already level-driven, not
  talent-driven** — leave both completely untouched, they are not part of this rework.

### Required change
- **Remove the `"rage"` Talent entirely** from the Tier 1 pool — it is no longer a purchasable
  talent, at any rank. Delete its `Talent` resource construction (`game_state.gd:1480-1493`), its
  `_apply_talent_rank()` case (`:1058-1063`), and its entry in `GameState.TALENT_ICON_FOLDER`.
- **Bake rank-3's behavior in unconditionally**, for every Barbarian regardless of talent
  investment:
  - The turn-countdown pause-while-active-combat logic (`player.gd:243-257`) always applies —
    delete the `if rage_rank >= 1` gate, the pause behavior is now the only behavior.
  - `take_damage_raw()`'s physical-damage reduction while raging is always 50% (physical types:
    Bludgeoning/Piercing/Slashing) — delete the rank-based 0/25/50 branching, hardcode 50%.
- Rage's ability tooltip (wherever it currently reads talent rank to describe its own behavior,
  e.g. `tooltip_formatters.gd`) needs updating to describe the fixed, always-on behavior — no
  more "current rank" branching in the copy.
- **Verify no other code path reads `GameState.get_talent_rank("rage")`** before deleting the
  Talent — grep for `"rage"` rank lookups; if `_sync_ability_uses()` or the debug panel reference
  the rage talent id anywhere, remove those references too.

---

## Part 2 — Retire Reckless Attack and Danger Sense as Tier 1 talents

The `"reckless_attack"` Talent (`game_state.gd:1495-1508`) and `"danger_sense"` Talent
(`game_state.gd:1510-1522`) are both removed from the Tier 1 pool, replaced by the three new
talents in Part 3.

**Open question (flag back before implementing, don't silently decide):** does the *ability*
itself — the Reckless Attack toggle (`player.gd._activate_reckless()`, `_bump_attack()`'s
reckless-resolve block at `player.gd:1205-1235`) and Danger Sense's trap-check advantage /
stat-substitution / flat STR bonus — get **deleted from the game entirely**, or does it get kept
as some other kind of grant (e.g. a subclass talent later, a flavor perk)? This doc assumes full
removal (the mirrored ADV/DISADV toggle and the trap-check/stat-substitution mechanics disappear
along with their talents, since nothing in the request preserves them elsewhere) — confirm before
deleting `_activate_reckless()`, the `reckless_attack_active`/`reckless_locked_this_turn`/
`reckless_rank` GameState fields (`game_state.gd:881-889`), the enemy-side mirror in
`enemy.gd:522-527`, and Danger Sense's trap-check hooks (`scripts/entities/CLAUDE.md:208`) and
its rank-3 STR+2 stat mutation (`game_state.gd:1144-1145`, including the rank-down reversal at
`:1032-1034` if talent respec/debug rank-down exists).

---

## Part 3 — The 3 new Tier 1 talents

Same investment model as today: 1 point/level, levels 1-5, 3 talents × max rank 3 (5 points for
9 possible ranks — can't max everything, must prioritize). Reuse the existing `Talent`/
`_apply_talent_rank()`/`talent_investments` infrastructure — no new generic data structures
needed, this is a content swap, not an architecture change.

### 1. Blood-Crazed (`talent_id: "blood_crazed"`)

| Rank | Effect |
|---|---|
| 1 | After you land a critical hit or land a killing blow, your next attack is made with Advantage. |
| 2 | Whenever you attack with Advantage (from any source, not just this talent's own rank-1 trigger), add your Strength modifier to the damage a second time. |
| 3 | Whenever you attack with Advantage, your crit range widens to 19-20 (instead of only natural 20). |

Implementation notes:
- **Rank 1 trigger tracking**: needs a new flag, e.g. `Player._blood_crazed_adv_pending: bool`,
  set true when an attack resolves as a crit (`is_crit` at any of the 5 roll-resolution sites —
  `player.gd:1244,1458,1534,1604`) or when the target's HP drops to 0/dies as a direct result of
  that attack. Consumed (added as one net +1 ADV source into whatever `adv_count` is passed to
  `CombatMath.roll_with_adv_disadv()`) on the player's next attack roll, then cleared regardless
  of whether that next attack hits or misses. Persists across turns until consumed (a kill on
  turn N should still grant ADV on the attack on turn N+1 if the player didn't attack again same
  turn) — do not reset it in `_on_turn_started()`.
- **Rank 2**: at the point damage is computed for a hit that resolved as `adv == true` (per
  `CombatMath.roll_with_adv_disadv()`'s returned dict), add `player_stats.modifier(player_stats.strength)`
  to the damage total a second time — this is a flat additive damage bonus conditioned on the
  *roll's own* advantage state, not on how that advantage was obtained (works whether the
  advantage came from Blood-Crazed rank 1, a sleeping target, or any other ADV source already in
  the game). Follows the existing damage-stacking rule (root CLAUDE.md): sum into one total
  before calling `take_damage()`, one named field in the `[url=dmg:...]` tooltip meta, log line
  stays terse.
- **Rank 3**: no per-character "crit threshold" field currently exists anywhere in the codebase
  (crit is hardcoded `die == 20` at all 5 sites listed above) — this is the first such widening.
  Recommend a computed check, not a stored field: at each of the 5 `is_crit` computations, change
  `die == 20` to `die == 20 or (r.adv and die == 19 and GameState.get_talent_rank("blood_crazed") >= 3)`
  (guard on `character_race`/class not needed — Danger Sense/Blood-Crazed is Barbarian-only by
  virtue of the Tier 1 pool being class-gated already). Because this must be threaded into 5
  separate call sites, consider factoring a shared `CombatMath.is_critical_hit(die: int, adv: bool) -> bool`
  helper so all 5 sites call one function instead of duplicating the widened-range condition —
  recommended, not mandatory (flag if you'd rather duplicate the one-line condition 5× to avoid
  touching `CombatMath`'s public surface).

### 2. Scarred Juggernaut (`talent_id: "scarred_juggernaut"`)

| Rank | Effect |
|---|---|
| 1 | While below 50% max HP, gain temporary HP equal to your current Rage bonus damage at the start of your turn (only while Raging). |
| 2 | While below 50% max HP, gain +1 AC. |
| 3 | Once per floor: if you die while Raging, instead resurrect at 1 HP and Rage ends. |

Implementation notes:
- **Rank 1**: mirror the existing Ironwood Bark per-turn temp-HP grant pattern
  (`player.gd:222-225`, which already grants temp HP each turn while raging if the pool is at 0)
  — add a Scarred-Juggernaut-gated branch alongside it: if
  `get_talent_rank("scarred_juggernaut") >= 1 and current_hp <= max_hp / 2 and _rage_turns > 0`,
  grant `player_stats.temp_hp += player_stats.rage_bonus_damage` at the top of the player's turn
  (reuse whatever the existing Ironwood Bark grant's exact tick point is, don't invent a second
  per-turn hook). Uses the existing `Stats.temp_hp` field and its existing absorb-first behavior
  in `take_damage()` (`stats.gd:160-162`) — no new HP plumbing needed.
- **Rank 2**: `Stats.armor_class` is a plain stored field, recalculated on demand via
  `recalc_ac()`, but read *live* at hit-resolution time in `enemy.gd:544`
  (`_resolve_attack_roll(GameState.player_stats.armor_class)`). Do **not** try to reactively call
  `recalc_ac()` every time HP changes — instead add a computed accessor, e.g.
  `Stats.effective_ac() -> int` that returns `armor_class + (1 if <rank-2 condition> else 0)`, and
  change the `enemy.gd:544` call site (and any other direct `armor_class` read used for incoming
  attacks — grep for other `.armor_class` reads against the player) to call `effective_ac()`
  instead. This is the cleanest hook point since the field is already read fresh every attack, not
  cached.
- **Rank 3**: this is the **first "resets once per floor" charge** in the codebase — every other
  long-rest-gated resource resets in `GameState.long_rest()` (`game_state.gd:415-447`), and
  `advance_floor()` (`game_state.gd:359-367`) currently only resets `terrain_ac_bonus` and bumps
  the floor number, no precedent for a per-floor charge flag exists yet. Add
  `scarred_juggernaut_used_this_floor: bool = false` on `GameState`, reset it in
  `advance_floor()` alongside the `terrain_ac_bonus` reset, **and also reset it on `long_rest()`**
  if long rest can occur mid-floor (confirm — if long rest is always floor-boundary-adjacent in
  practice this may be moot, but reset in both places defensively since the charge is meant to be
  "once per floor," not "once ever"). Hook into `GameState.check_player_death()`
  (`game_state.gd:482-486`): before setting `is_game_over = true`, check
  `get_talent_rank("scarred_juggernaut") >= 3 and _rage_turns > 0 and not scarred_juggernaut_used_this_floor`
  (the raging-state check needs a GameState-visible way to read `Player._rage_turns > 0` — if
  that's not already exposed to GameState, add a getter or mirror flag, following the existing
  `GameState.rage_turns_remaining` field noted in Part 1's research if one exists, or thread a
  `is_raging: bool` check through `Player`). On success: set `current_hp = 1`,
  `scarred_juggernaut_used_this_floor = true`, force `_end_rage()`, log the save, and **skip** the
  `is_game_over`/`player_died` emit/`SaveManager.delete_save()` path entirely for this one trigger.

### 3. Unstoppable Force (`talent_id: "unstoppable_force"`) — introduces the "side-step" mechanic

**Side-step definition**: the player moves from one tile within melee reach of a given enemy to a
different tile that is *also* within melee reach of that *same* enemy (never leaving its reach
during the move) — "dancing" around an adjacent target rather than disengaging from it.

**Reuse, don't reimplement, the existing reach math.** `player.gd._resolve_enemy_opportunity_attacks(prev, next)`
(`player.gd:868-893`) already computes, per enemy, `d_prev`/`d_next` (Chebyshev distance from
`prev`/`next` to the enemy) against `e.melee_reach()`, and already `continue`s (no OA) exactly
when `d_prev <= reach and d_next <= reach` — i.e. **a side-step against a given enemy already
falls through this function's existing no-OA branch with zero changes needed to OA logic itself.**
This talent only needs to *detect* that same condition (for a specific enemy) at the same call
site and fire its own effect, additively, without touching the OA branching:

```gdscript
# player.gd, inside or right after _resolve_enemy_opportunity_attacks(prev, next)'s per-enemy loop
if d_prev <= reach and d_next <= reach and prev != next:
    _on_sidestep(e, prev, next)   # new hook — the existing `continue` already prevents the OA
```

| Rank | Effect |
|---|---|
| 1 | Whenever you side-step, gain Advantage on your next attack. |
| 2 | Whenever you side-step, the enemy you side-stepped around must make a DEX check (DC `8 + proficiency + your DEX modifier`) or gain Disadvantage on its next attack. |
| 3 | When you take damage, your next side-step is free — it doesn't consume your turn (you may still move and/or attack afterward). |

Implementation notes:
- **Rank 1**: sets a pending-ADV flag consumed on the player's next attack roll (same shape as
  Blood-Crazed rank 1's pending flag, Part 3.1 — consider whether these two "pending advantage"
  flags should share one mechanism, e.g. a small `_pending_adv_sources: int` counter incremented
  by either trigger and drained by one net +1 into `adv_count` on the next attack, rather than two
  parallel bools; flag this as a recommended simplification, not mandatory).
- **Rank 2**: use `Enemy.resist_check(dc, use_con: bool = false)` (per
  `scripts/entities/CLAUDE.md:115`) as the exact DC-check pattern already used by Grip of the
  Forest/Topple/Push — but note the existing helper rolls the enemy's CON or STR modifier, not
  DEX; this talent needs a DEX-based enemy roll, which may require a small variant/parameter
  addition (`use_stat: String` or a third bool) rather than reusing `resist_check()` verbatim —
  confirm `Enemy` stats expose a DEX modifier equivalent before assuming this drops in unchanged.
  On failure, set `Enemy.disadv_next_attack = true` (the exact existing field Grip of the Forest
  R3 already uses — `enemy.gd`'s `_resolve_attack_roll()` reads and clears this at
  lines ~520-521) — do not invent a new enemy status field, this one already exists and is
  already correctly wired into the attack-roll resolution.
- **Rank 3**: this is an **exception to the 1-action-per-turn turn model** (per
  `scripts/autoloads/CLAUDE.md`'s turn-flow: normally every player action calls
  `TurnManager.on_player_action_complete()`, which triggers the enemy phase). "Free" here must
  mean: after being damaged, the player's next successful side-step does **not** call
  `on_player_action_complete()` — the phase stays `WAITING_FOR_INPUT`-equivalent (or is
  immediately restored to it) and the player retains their turn. **Before implementing, find and
  reuse whatever mechanism already lets Rager-style or Monk bonus-action mechanics (if any exist
  today) grant an extra action without ending the turn** — grep for "bonus action" handling in
  `player.gd`/Monk-specific code; if no such precedent exists in the current codebase (the two
  stale root-level prompt files reference a Berserker "Rager" talent with a similar "doesn't end
  the turn" mechanic — confirm whether Rager rank 2/3 actually shipped this way, since if it did,
  **that** is the pattern to copy exactly, not reinvent). Flag back if no precedent exists at all
  — this would be new turn-flow-adjacent code and deserves explicit sign-off given the root
  CLAUDE.md's turn model is otherwise a strict single-action gate.
  - Trigger condition: `Stats.take_damage()` (or its caller) sets
    `Player._free_sidestep_available = true` on any nonzero damage taken. Consumed by the very
    next side-step (Rank-3-gated), which then must **not** end the turn. Clear the flag after one
    use regardless of outcome (only one free side-step banked at a time, doesn't stack from
    multiple hits in the same window — confirm this assumption, the request doesn't specify
    stacking).

---

## Data structure / hookup requirements

- Talent resources: replace the 3 old `Talent.new()` constructions (`game_state.gd:1480-1522`)
  with 3 new ones (`blood_crazed`, `scarred_juggernaut`, `unstoppable_force`), same `tier=1`,
  `max_rank=3`, `class_id` Barbarian shape.
- `_apply_talent_rank()`: 3 new `match` cases replacing the old `"rage"`/`"reckless_attack"`/
  `"danger_sense"` cases. Blood-Crazed and Unstoppable Force rank 1 need to `add_ability()` a
  passive/indicator entry if the project's convention is to surface every talent as an
  ability-bar icon (confirm against how e.g. Danger Sense rank 1 currently does this, since these
  are largely passive/reactive effects, not player-activated toggles — an ability-bar slot may
  not even be appropriate; flag which of the 3 new talents, if any, need an ability-bar presence
  vs. being purely passive with no bar icon).
- Icon assets: `icons/barbarian/base/` currently has `feral_instinct_*`, `primal_fury_*`,
  `reckless_attack_*` (note: working tree already shows `_1.png` modified and `_2.png`/`_3.png`
  deleted for all three — this looks like in-progress asset prep for this exact rework; confirm
  with the owner whether these modified rank-1 files are meant to become the new talents' rank-1
  icons under new filenames, or whether fresh `blood_crazed_*`/`scarred_juggernaut_*`/
  `unstoppable_force_*` assets are still needed). `GameState.TALENT_ICON_FOLDER` and
  `talent_icon_path()` need the 3 new talent_ids mapped once filenames are confirmed.
- Save/load: `talent_investments` is keyed by talent_id string — no schema change needed, old
  saves with `"rage"`/`"reckless_attack"`/`"danger_sense"` keys simply become orphaned/ignored
  once those talents no longer exist in `_class_talents`; confirm `from_dict()`'s talent-replay
  loop tolerates unknown keys gracefully (skip, don't crash) rather than assuming clean saves.

---

## What must NOT change

- `rage_uses_max`/`rage_bonus_damage` level-scaling (`stats.gd:78,88`) — untouched, these are not
  talent-driven and this rework doesn't touch level-based scaling at all.
- `CombatMath.roll_with_adv_disadv()`'s core net-ADV/DISADV math — Blood-Crazed/Unstoppable Force
  add ADV *sources* into the existing `adv_count`, they don't change how ADV/DISADV combine.
- The general 1-action-per-turn turn model, **except** for Unstoppable Force rank 3's explicitly
  scoped, single-talent exception (Part 3.3) — do not generalize a "free action" mechanism beyond
  what that one rank needs.
- Tier 2 Berserker/Zealot/World Tree/Wild Heart talents and their reliance on `rage_bonus_damage`
  — untouched; verify none of them read `get_talent_rank("rage")`/`"reckless_attack"`/
  `"danger_sense")` anywhere (grep before deleting) since a Tier 2 talent silently depending on a
  deleted Tier 1 talent would be a regression.
- Monk, Ranger progression — untouched, out of scope.
- Opportunity Attack resolution itself (`player.gd:868-893`, `enemy.gd`'s move-triggered OA) —
  Unstoppable Force only *observes* the same reach math, it does not modify the OA no-trigger
  condition.

---

## Open questions to flag back before implementing (don't silently decide)

1. **Reckless Attack / Danger Sense fate** (Part 2): full removal from the game, or preserved
   elsewhere? This doc assumes full removal.
2. **Blood-Crazed rank 1's pending-ADV persistence**: does it expire at end of turn if unused, or
   persist indefinitely until the next attack (this doc assumes the latter — persists across
   turns)?
3. **Scarred Juggernaut rank 3**: should the per-floor charge also reset on long rest (in case
   long rest can occur mid-floor), or strictly floor-boundary only? Also: is `_rage_turns`
   (or equivalent "currently raging" state) already readable from `GameState`, or does `Player`
   need a new exposed getter/signal for this check?
4. **Unstoppable Force rank 3's "doesn't end the turn" mechanic**: does any existing bonus-action
   /free-action precedent already exist in the shipped code (the stale `berserker-tier2-talent-prompt.md`
   describes a "Rager" talent with an extremely similar free-action-on-move/attack mechanic —
   confirm whether Rager actually shipped this way; if so, copy its exact implementation pattern
   instead of designing a new one)?
5. **Ability-bar presence**: do any of the 3 new talents need an ability-bar slot/icon, or are
   all three purely passive/reactive with no player-activated toggle?
6. **Icon assets**: confirm whether the already-modified `feral_instinct_1.png`/`primal_fury_1.png`/
   `reckless_attack_1.png` (rank-1 files edited, rank-2/3 deleted, per current working-tree status)
   are meant to be repurposed/renamed for the new talents, or if this is unrelated in-progress
   work and fresh icon files should be created instead.

---

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without asking.
Suggested breakdown: (1) Rage baseline bake-in + removal of the `"rage"` talent, (2) removal of
Reckless Attack/Danger Sense talents (pending open question 1's answer), (3) Blood-Crazed talent,
(4) Scarred Juggernaut talent, (5) Unstoppable Force talent + side-step hook, (6) icon/asset
wiring, (7) CLAUDE.md updates. Don't squash into one giant commit.

## CLAUDE.md update requirement

After implementation, update root `CLAUDE.md` (Talent system section) and
`scripts/entities/CLAUDE.md` (Barbarian talent tables, the "Opportunity Attacks" section to note
the side-step no-OA interaction, and the Rage description) to reflect: Rage as a fixed, always-on
level-1 ability (no talent gating), the 3 new Tier 1 talents replacing Rage/Reckless Attack/
Danger Sense, the side-step mechanic and its relationship to Opportunity Attacks, the new
per-floor charge pattern (first of its kind — document it as a precedent for future per-floor
resources), and the widened-crit-range mechanic (first of its kind).
