# TASK: Implement Stealth vs Perception + corrected Surprise Attacks

## Context
Repo: Bacilek/Dragons-in-Dungeons, branch `main`. Godot 4.6 Mono, GDScript only.
Read the existing `CLAUDE.md` files (root + `scripts/entities/`, `scripts/world/`, `scripts/ui/`)
before touching anything. Full reasoning + audit: `docs/architecture/stealth-and-surprise-attacks-design.md`
— this file is the actionable summary of the same decisions. Line numbers were verified against
commit `472a360`; re-verify before editing, but function names/structure are authoritative.

Two deliverables:
1. A contested **Stealth (player DEX) vs Perception (enemy WIS)** check that decides whether a
   SLEEPING enemy notices the player, rolled per player movement step.
2. **Fixed surprise-attack (Advantage) triggers**, Shattered Pixel Dungeon–style: ADV iff the
   defender is unaware at the moment of the attack roll. The current `just_crossed_door`
   mechanic is buggy and gets replaced.

## Bug being fixed (why)
- `enemy.gd:318–319`: `just_crossed_door = true` is set in `_move_step()` for **every** enemy
  door step in **every** behavior state, and nothing ever clears it except consumption in
  `player_vfx.gd:15–19` `has_advantage()`. Result: a fully-aware CHASING enemy — or an enemy
  that roamed through a door 50 turns ago — grants the player ADV on the first attack. This is
  the "surprise fires when it shouldn't" bug.
- `enemy.gd:165`: SLEEPING enemies wake deterministically on their next turn whenever
  `can_see` (dist ≤ FOV_RADIUS 6 + LOS) — there is currently **no stealth mechanic at all**.

## Part 1 — Enemy WIS + Perception roll
- New pool key `"wis_mod"` (int, default 0) in `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL` entries;
  convert in `enemy.gd _apply_stats()`: `stats.wisdom = 10 + _type.get("wis_mod", 0) * 2`
  (exactly mirrors `str_mod`/`con_mod` at lines 62–63). Seed suggestions: beast hunters +2,
  humanoids 0/+1, mindless undead −1, bosses +2.
- New helper beside `resist_check()` (enemy.gd:68–71), same style:
  ```gdscript
  func perception_roll(distance: int) -> int:
      return randi_range(1, 20) + GameState.current_floor / 3 + stats.wis_modifier() - distance
  ```
  `distance` = Chebyshev distance to the player (1–6). The `- distance` term is the SPD
  distance-falloff port — do not drop it.

## Part 2 — Stealth contest on player movement
New `player.gd._resolve_stealth_checks(next: Vector2i) -> void`, called immediately **after**
the existing `_resolve_enemy_opportunity_attacks(...)` calls at all three player-step
chokepoints: `_try_move()` (player.gd:963), `_execute_queued_path()` chase step (:707) and
regular step (:784).

- Skip entirely on `GameState.noclip`.
- Player Stealth total, rolled **once per step** and reused vs all observers:
  `CombatMath.roll_with_adv_disadv(adv, disadv)` d20 + `dex_modifier()` + proficiency_bonus if
  `check_prof_dex`. ADV sources: Danger Sense R1+ (this is a DEX check — same family as
  traps/lockpick/disarm), Zealous Presence. Danger Sense R2: use `max(dex_mod, str_mod)` like
  the other DEX-check sites.
- For each alive enemy with `behavior == Behavior.SLEEPING` that has the destination tile in its
  FOV (reuse enemy.gd:160–161 metric verbatim: Euclidean `dist_sq <= FOV_RADIUS²` AND
  `has_line_of_sight(enemy.grid_pos, next)`): it rolls `perception_roll(chebyshev_dist)`.
  Enemy notices iff its total is **strictly greater** (ties → player stays hidden).
- On detection: `enemy._wake_up()` (already → CHASING + stops zzz, enemy.gd:121–123) and
  `enemy.last_known_player_pos = next`. Inline, synchronous, no TurnManager changes
  (Retaliation/OA precedent).
- **Logging**: NOTHING on silent success. On detection only:
  `"<Enemy> [url=stealth:...]notices[/url] you!"` — new `stealth:` meta carrying both rolls'
  breakdown + matching `fmt_stealth_tooltip()` in `scripts/ui/tooltip_formatters.gd` (root
  CLAUDE.md rule: never a bare number). Optional gray god-mode suffix like enemy.gd:426.

## Part 3 — Rewrite the SLEEPING wake logic (enemy.gd take_turn())
- **Delete** the `can_see` wake clause (line 165) and `WAKE_RADIUS_SQ` (line 8) — replaced by
  the contest above.
- **Keep one free-wake tier**: at the top of the SLEEPING branch, if Chebyshev distance to
  player ≤ 1 → `_wake_up()` (no roll). It lives in `take_turn()`, NOT in the player-step hook —
  this preserves "sneak adjacent, strike first with ADV, then it wakes", while punishing
  lingering next to a sleeper.
- **New `Enemy.on_disturbed(source_pos: Vector2i)`**: if behavior in
  {SLEEPING, STATIONARY, ROAMING} → `_wake_up()` + `last_known_player_pos = source_pos`. Call
  after every player-side attack against that enemy, **hit or miss**: `_bump_attack()`,
  `PlayerRanged.ranged_attack()`, `_resolve_cleave_attack()`,
  `resolve_opportunity_attack()` (player.gd:1475), `companion._attack_enemy()`. Net effect:
  surprise ADV applies to the **first attack of an engagement only**.

## Part 4 — Surprise ADV trigger rework (`player_vfx.gd has_advantage()`)
Replace `just_crossed_door` with `door_ambush`:
- **Set** in `_move_step()` only when `stepping_through_door` (existing local, enemy.gd:311)
  AND the enemy had **no sight of the player from `prev_pos`** (dist_sq > FOV_RADIUS² from
  prev_pos, or no `has_line_of_sight(prev_pos, player.grid_pos)`).
- **Clear unconditionally** at the top of `take_turn()`, next to the `oa_used_this_round = false`
  reset (enemy.gd:131) — lifetime is exactly one round ("the turn it came through the door").
- Keep the consume-on-read clear in `has_advantage()` too (future Extra Attack safety).

New `has_advantage()`:
```gdscript
func has_advantage(enemy: Enemy) -> bool:
    if enemy.door_ambush:
        enemy.door_ambush = false
        return true
    return enemy.behavior in [Enemy.Behavior.SLEEPING, Enemy.Behavior.STATIONARY, Enemy.Behavior.ROAMING]
```
Keep both call sites as-is (`player.gd:1196`, `player_ranged.gd:88` — melee and ranged share the
table). Yellow "!" floater behavior unchanged.

**Definitive trigger table** (defender state at attack-roll time):
| State / situation | ADV? |
|---|---|
| SLEEPING | YES |
| SLEEPING behind a door the player just opened (door auto-opens on step, player.gd:943–955) and stayed asleep through the step's contest | YES — falls out of the SLEEPING row, no special code |
| STATIONARY / ROAMING (haven't spotted you — they flip to CHASING the turn they see you) | YES |
| CHASING | NO — except `door_ambush` set this round (stepped through a door without prior LOS to you) |
| SEARCHING | NO |
| Any second+ attack of an engagement (on_disturbed woke it) | NO |

## What must NOT change
- `TurnManager` — zero edits. All resolution inline (Retaliation/OA precedent).
- `CombatMath.roll_with_adv_disadv()` / net-ADV-DISADV house rule — surprise stays one ADV source.
- The OA hooks and `_resolve_enemy_opportunity_attacks()` (it already skips SLEEPING enemies —
  correct, keep).
- `_bump_attack()`/`ranged_attack()` bonus-damage stacking flow — `on_disturbed()` is appended,
  not woven in.

## Open questions (flag back — don't silently decide)
1. Extend the contest to ROAMING/STATIONARY (player at DISADV) instead of their deterministic
   spot-on-LOS? Recommendation: defer to v2.
2. Combat noise: auto-wake sleepers within 4 tiles of any player attack, no roll?
   Recommendation: yes.
3. `- distance` perception penalty tuning (soften to `- distance / 2` if detection feels rare).
4. SEARCHING enemies stay un-surprisable (deviation from SPD's out-of-FOV clause). Confirm.

## Implementation checklist (commit breakdown)
1. Enemy WIS infra: `wis_mod` pool key, `stats.wisdom` in `_apply_stats()`, `perception_roll()`,
   pool seeding. Commit.
2. Stealth contest: `_resolve_stealth_checks()` + 3 call sites, detection log, `stealth:` meta +
   `fmt_stealth_tooltip()`. Commit.
3. SLEEPING wake rewrite: remove `can_see`/`WAKE_RADIUS_SQ`, adjacency free-wake,
   `on_disturbed()` + all attack call sites. Commit.
4. `just_crossed_door` → `door_ambush` + `has_advantage()` rewrite. Commit.
5. CLAUDE.md updates: `scripts/entities/CLAUDE.md` new "Stealth & Surprise" section (contest
   formula, trigger table, `door_ambush` lifecycle, `on_disturbed()`), `scripts/ui/CLAUDE.md`
   tooltip kind, root `CLAUDE.md` pointer lines + fix the stale "CHASING sets
   `just_crossed_door`" text. Commit.

## Commit convention
`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without asking.
Don't squash into one giant commit.
