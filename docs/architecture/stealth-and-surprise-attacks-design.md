# Stealth & Surprise Attacks — Design Doc

Status: **spec only — no code written**. A future session implements this from
`stealth-surprise-attacks-prompt.md` (repo root), which is the terse actionable version of the
same decisions. This doc is the reasoning + audit record.

Scope: (A) a contested Stealth (player DEX) vs Perception (enemy WIS) system deciding whether an
unaware enemy notices the player; (B) a corrected, Shattered Pixel Dungeon–modeled ruleset for
when a surprise attack (Advantage) does and does not trigger, including the door cases.

All line numbers verified against the working tree at time of writing (post-commit `472a360`).
Re-verify before editing, but function names and structure are authoritative.

---

## 1. Audit of the current implementation (the bugs)

### 1.1 There is no stealth window at all

`enemy.gd` `take_turn()`, `Behavior.SLEEPING` branch (lines 163–171):

```gdscript
Behavior.SLEEPING:
    if can_see or dist_sq <= WAKE_RADIUS_SQ:
        _wake_up()
```

where `can_see` (lines 160–161) is `dist_sq <= FOV_RADIUS * FOV_RADIUS and
_dungeon_floor.has_line_of_sight(...)` with `FOV_RADIUS = 6` (line 7). So a SLEEPING enemy
wakes **deterministically on its very next turn** the moment the player is within 6 tiles with
line of sight — no roll, no stealth stat, nothing the player can influence. `WAKE_RADIUS_SQ = 4`
(line 8, Euclidean-squared, ≈2 cardinal tiles / 1 diagonal tile) is merely the through-walls
fallback. The only reason surprise ADV ever fires today is turn ordering: the player can reach
and hit the enemy before its first `take_turn()` runs. Sneaking is not a mechanic; it's a race.

### 1.2 `just_crossed_door` is backwards, state-agnostic, and never expires

- Declared: `enemy.gd:20` (`var just_crossed_door: bool = false`).
- Set: `enemy.gd:318–319`, inside `_move_step()` — the shared chokepoint for **all** enemy
  voluntary movement (chase, roam, random-step, search):
  ```gdscript
  if stepping_through_door:
      just_crossed_door = true
  ```
  Note: root/entities CLAUDE.md attribute this to the CHASING state, but `_move_step()` is called
  from every state's movement path — a ROAMING enemy idly wandering through a door sets it too.
- Consumed: `player_vfx.gd:15–19` `has_advantage(enemy)` — returns true and clears the flag.
  Called at attack-roll time from `player.gd:1196` (`_bump_attack()`) and `player_ranged.gd:88`.

**Three concrete defects** (this is the confirmed source of "surprise ADV fires when it
shouldn't"):

1. **Wrong direction.** The flag models "an enemy walked through a door", not "the player caught
   an enemy unaware through a door". A CHASING enemy in open pursuit, fully aware of the player,
   grants the player Advantage just because its last step happened to be through a doorway it
   opened itself while hunting you. In SPD the door-surprise belongs to the *unaware defender*
   case (see §2), never to an alert hunter.
2. **No expiry.** Nothing ever clears the flag except consumption at `player_vfx.gd:17`. An enemy
   that roamed through a door 50 turns ago — before the player even entered the room — still
   grants ADV on the first attack ever made against it. The flag silently survives across the
   enemy's turns, state transitions, even SLEEP→CHASE→SEARCH cycles.
3. **No awareness gate.** It is set even when the enemy could plainly see the player before,
   during, and after the door step.

Defect 2 is almost certainly what the player experiences as random, unexplainable Advantage.

### 1.3 What is *not* broken

- Checking surprise fresh at attack-roll time (`has_advantage()` called from the attack body, not
  cached earlier in the turn) is correct and matches SPD, which evaluates `surprisedBy()` per
  attack. No stale-cache race exists on the SLEEPING side: `behavior` only changes inside the
  enemy's own `take_turn()` (or `_wake_up()`), which cannot interleave with the player's attack
  resolution. Keep this evaluation model.
- The net-ADV/DISADV pipeline (`CombatMath.roll_with_adv_disadv()`, surprise contributes at most
  +1 ADV source) — untouched by this design.

### 1.4 Enemy Stats have no WIS

`enemy.gd _apply_stats()` synthesizes only STR/CON from pool keys (lines 62–63):

```gdscript
stats.strength     = 10 + _type.get("str_mod", 0) * 2
stats.constitution = 10 + _type.get("con_mod", 0) * 2
```

`Stats` (`scripts/entities/stats.gd`) already has `wisdom: int = 10` (line 35) and
`wis_modifier()` (line 127) — enemies just never set it, so every enemy currently has WIS 10
(mod 0). Perfect insertion point: a `"wis_mod"` pool key mirroring `str_mod`/`con_mod` exactly.

---

## 2. The Shattered Pixel Dungeon reference model (research summary)

From SPD source (`Mob.java`, 00-Evan/shattered-pixel-dungeon, master):

- **Alertness states**: SLEEPING, WANDERING, HUNTING (+FLEEING/PASSIVE). Maps cleanly onto this
  codebase's `SLEEPING / (STATIONARY, ROAMING) / (CHASING, SEARCHING)`.
- **Per-mob-turn probabilistic noticing**, scaled by distance, against the hero's stealth stat:
  sleeping mobs notice with chance `1 / (distance + heroStealth)` per turn; wandering mobs with
  `1 / (distance/2 + heroStealth)`. Sleeping mobs never notice beyond a short range.
- **Surprise attack condition** (`Mob.surprisedBy(enemy, attacking)`): the attack is a surprise
  iff the attacker is the hero AND (hero is invisible OR `!enemySeen` OR the hero's position is
  outside the mob's current field of view). I.e. **surprise = defender is unaware of you at the
  moment the blow lands** — sleeping, wandering-and-hasn't-noticed, or simply unable to see you.
  It is re-evaluated **per attack**, and since being attacked (and noticing) removes unawareness,
  in practice it applies to the opening attack of an engagement.
- **Doors** are not special-cased in `surprisedBy()`. Both famous door interactions fall out of
  the FOV/awareness clauses:
  - *Player opens a door onto an unaware mob* → mob is sleeping/wandering and hasn't noticed →
    surprise.
  - *Door-camping* (player waits beside a door; a mob steps through) → the mob in the doorway has
    a slit FOV and hasn't seen the hero standing off-axis → surprise.
- SPD expresses surprise as guaranteed-hit + weapon damage multipliers; here it stays **+1 ADV
  source** in the existing net-ADV/DISADV pool. Only the *trigger conditions* are transferred.

Sources: SPD source `Mob.java` (github.com/00-Evan/shattered-pixel-dungeon), Pixel Dungeon wiki
"Shattered PD - Combat" / "Game mechanics/Attacking" (pixeldungeon.fandom.com), Steam community
mechanics threads.

---

## 3. Part A — Stealth vs Perception contested check

### 3.1 Which states are "unaware"?

**Decision: the contested check applies to SLEEPING enemies only (v1).** STATIONARY and ROAMING
enemies are awake and scanning; they keep today's deterministic spot-on-LOS transition to CHASING
in their own `take_turn()` (`enemy.gd:173–189`). Rationale:

- It needs zero new Behavior enum values and zero changes to the STATIONARY/ROAMING branches.
- SPD does run notice-checks for wandering mobs too (`1/(dist/2 + stealth)`), but porting that
  means awake enemies can walk straight past a visible player — a large AI-feel change that
  deserves its own iteration. Flagged as Open Question #1 (recommended v2: same contest for
  ROAMING/STATIONARY with the player's check at DISADV).
- STATIONARY/ROAMING enemies still count as *unaware for surprise-ADV purposes* until they
  actually transition (see Part B) — so sniping a roamer that hasn't seen you still surprises it,
  matching SPD's wandering-surprise, without any stealth roll governing their waking.

### 3.2 The contest — formula

One resolution mechanic exists in this game: the **check** (d20 + modifier vs a target).
`Enemy.resist_check()` (`enemy.gd:68–71`) is the template for the enemy side; player DEX checks
(traps/lockpick/disarm, Danger Sense family) are the template for the player side. This is a
**contested check** (two live rolls), chosen over a static DC because both parties are actors and
it lets Danger Sense / Zealous Presence ADV plug into the player side through the existing
`roll_with_adv_disadv()` path unchanged.

**Player Stealth total** (rolled ONCE per triggering step, reused against every observer — 5e
group-stealth style, avoids N swingy rolls per step):

```
stealth_total = CombatMath.roll_with_adv_disadv(adv, disadv).total
              + player_stats.dex_modifier()
              + (player_stats.proficiency_bonus if player_stats.check_prof_dex else 0)
```

- ADV sources: Danger Sense R1+ (ADV on DEX checks — this is a DEX check, same family as
  traps/lockpick/disarm), Zealous Presence (`zealous_presence_turns > 0`, same call sites Danger
  Sense already covers). DISADV sources: none in v1.
- Danger Sense R2 modifier substitution applies: use `max(dex_modifier, str_modifier)` exactly as
  the other DEX-check sites do.
- Class note: Ranger and Monk have `check_prof_dex = true` (`stats.gd:195–196, 208–209`) — they
  are the "sneaky" classes for free. Barbarian/Wizard roll without proficiency. Intended.

**Enemy Perception total** (each observing enemy rolls its own — new helper on Enemy, placed next
to `resist_check()` and styled identically):

```gdscript
# enemy.gd — new, mirrors resist_check() at lines 68-71
func perception_roll(distance: int) -> int:
    return randi_range(1, 20) + GameState.current_floor / 3 + stats.wis_modifier() - distance
```

- `floor/3` — the same floor-scaling every enemy d20 already uses (`resist_check()`,
  `_attack_player()` line 402). Deeper enemies are more perceptive; no new scaling knob.
- `- distance` (Chebyshev, 1–6): the port of SPD's `1/(dist + stealth)` distance falloff into
  d20 space. Sneaking at range 6 is meaningfully safer than at range 2; without this term a
  fixed ~50/50 contest per step makes any multi-step approach near-certain detection.
- `stats.wis_modifier()`: backed by a new pool key `"wis_mod"` (default 0) converted in
  `_apply_stats()` as `stats.wisdom = 10 + _type.get("wis_mod", 0) * 2` — the exact
  `str_mod`/`con_mod` pattern at lines 62–63. Suggested seeding (balance pass later): perceptive
  hunters (wolves/beasts) +2, standard humanoids 0/+1, mindless undead −1, bosses +2.

**Resolution**: the enemy notices iff `perception_roll(dist) > stealth_total`. **Ties go to the
player** (status quo prevails — the 5e contested-check convention; also mirrors how
`resist_check()`'s `>=` favors the party defending the status quo).

### 3.3 Trigger — where the check hooks into the turn flow

The contest fires on **player grid-movement steps** (movement makes noise; waiting, drinking,
inventory actions are silent — see Open Question #2 for combat noise). There are exactly three
player-movement bodies, and all three already call the Opportunity Attack per-step hook — reuse
that discovery verbatim (see `docs/architecture/opportunity-attacks-design.md`, "Trigger
detection" §2):

| Call site | Existing OA call | New call, immediately after |
|---|---|---|
| `player.gd _try_move()` (func at 885) | line 963 `_resolve_enemy_opportunity_attacks(prev_pos, target)` | `_resolve_stealth_checks(target)` |
| `player.gd _execute_queued_path()` chase step | line 707 | same |
| `player.gd _execute_queued_path()` regular step | line 784 | same |

New helper `player.gd._resolve_stealth_checks(next: Vector2i) -> void`:

1. Skip entirely on `GameState.noclip`.
2. Roll the player's `stealth_total` once (lazily — only if at least one observer qualifies).
3. For each enemy in `_dungeon_floor.get_all_enemies()`: qualify iff alive, `behavior ==
   Behavior.SLEEPING`, inside that enemy's FOV of the player's **destination** tile — reuse the
   enemy's own sight metric verbatim (`enemy.gd:160–161`): Euclidean `dist_sq <= FOV_RADIUS *
   FOV_RADIUS` AND `has_line_of_sight(enemy.grid_pos, next)`.
4. Qualifying enemy rolls `perception_roll(chebyshev_dist)`; on `> stealth_total` → detection:
   call `enemy._wake_up()` (`enemy.gd:121–123` — already transitions straight to CHASING and
   stops the zzz label; **keep that target state**: today's wake already goes directly to
   CHASING, and a creature startled awake by a noise it localized should hunt, not idle) and set
   `enemy.last_known_player_pos = next`.
5. Resolution is synchronous and turn-free — same inline model as OA/Retaliation. No TurnManager
   changes, no phase changes.

Detection happens **before the player's next action**, so a detected player does NOT get surprise
ADV on the now-awake enemy — which is exactly the point of the contest.

### 3.4 What replaces the old wake logic in `take_turn()`

Rewrite the SLEEPING branch (`enemy.gd:163–171`):

- **Delete the `can_see` clause** — deterministic wake-on-LOS is exactly what the contested check
  replaces.
- **Keep a free-wake tier at true adjacency**: `if Chebyshev(enemy, player) <= 1: _wake_up()`.
  Replaces `dist_sq <= WAKE_RADIUS_SQ` (delete the constant, line 8). Justification:
  - It stays in `take_turn()` (evaluated on the *enemy's* turn), not in the player-step hook.
    This deliberately preserves the classic sneak-attack loop: pass contests on approach → step
    adjacent → **attack before the enemy's turn** = surprise ADV; but *lingering* adjacent to a
    sleeping enemy (waiting, fiddling with inventory) costs you the surprise on its next turn.
  - SPD has no free-wake tier (at range 0 detection is still `1/stealth`), but SPD also rolls
    every mob turn even when the hero stands still; since our contest only fires on movement, the
    adjacency tier is the guard against the degenerate "stand next to it forever, it can never
    wake" hole. Layered tier > pure replacement.
- The no-observer idle branch (spend turn doing nothing, lines 169–171) stays.

### 3.5 Wake-on-attacked (new, required)

With the deterministic LOS-wake gone, nothing would wake an enemy that gets *hit*. Add
`Enemy.on_disturbed(source_pos: Vector2i)`: if `behavior` is SLEEPING/STATIONARY/ROAMING →
`_wake_up()` + `last_known_player_pos = source_pos`. Call it after **every** player-side attack
resolution against that enemy, **hit or miss** (you swung steel next to its head): melee
`_bump_attack()`, ranged `PlayerRanged.ranged_attack()`, Cleave secondaries
(`_resolve_cleave_attack()`), player OA (`resolve_opportunity_attack()`, player.gd:1475),
companion attacks (`companion.gd._attack_enemy()`). Consequence: **surprise ADV applies to the
first attack of an engagement only** — the attack itself removes unawareness. This is the SPD
answer to "re-checked per hit or first hit only".

### 3.6 Logging & tooltips (root-CLAUDE.md chat-log rule)

- **Silent successes are not logged.** A 6-step approach past three sleepers must not print 18
  lines. No floaters either.
- **Log on detection only**, one line per detecting enemy:
  `"[color=tomato]Orc Warrior[/color] [url=stealth:...]notices[/url] you!"`
- New meta kind `stealth:` with fields `pdie, padv, pdisadv, pmod, pprof, ptotal, edie, ewis,
  efloor, edist, etotal` and a matching `fmt_stealth_tooltip()` static handler in
  `scripts/ui/tooltip_formatters.gd` showing both sides of the contest — never a bare number,
  same discipline as `hit:`/`ehit:`.
- God Mode (`GameState.god_mode`) may append a gray inline `(Stealth X vs Perception Y)` suffix,
  matching the existing god-suffix convention in `_attack_player()` (enemy.gd:426, 443).

---

## 4. Part B — corrected surprise-attack (Advantage) rules

### 4.1 Core rule

> **Surprise ADV is granted iff the defender is unaware of the player at the moment the attack
> roll is made.** Unaware = has never noticed the player this engagement — expressed entirely
> through the existing Behavior enum plus one corrected door flag. Evaluated fresh per attack in
> `has_advantage()` (keep the call sites: `player.gd:1196`, `player_ranged.gd:88`).

### 4.2 The trigger table (definitive — covers every Behavior value)

| Defender state / situation | Surprise ADV? | Why |
|---|---|---|
| SLEEPING (player passed/never triggered contests) | **YES** | Classic sleeping surprise; SPD `state == SLEEPING`. |
| SLEEPING, adjacent through a door the player just stepped onto/through, still asleep | **YES** | The "player opens a door onto an unaware enemy" case — needs **no special code**; door auto-opens when the player steps on the tile (`player.gd:943–955`, `scripts/world/CLAUDE.md` "Doors"), the step triggers the normal stealth contest (§3.3), and if the enemy stays asleep the next attack hits a SLEEPING defender. Falls out of the core rule, exactly as it falls out of SPD's `surprisedBy()`. |
| STATIONARY (has not yet had a turn with LOS — else it would be CHASING) | **YES** | Awake but hasn't noticed you; SPD `!enemySeen`. |
| ROAMING (same — spots-on-LOS flips it to CHASING) | **YES** | SPD wandering-surprise. |
| CHASING | **NO** (one exception below) | Fully aware hunter. |
| CHASING, and the enemy stepped through a door **this round** without having had LOS to the player from its pre-door tile (`door_ambush`, §4.3) | **YES** | Door-camping, the one legitimate kernel inside today's `just_crossed_door`; SPD equivalent: mob in doorway hasn't seen the off-axis hero (FOV clause). |
| SEARCHING | **NO** | It knows you're nearby and is actively hunting. Deliberate conservative deviation from SPD (whose FOV clause would allow surprising a hunter from out of its sight); revisit with Open Question #4. |
| Any state, second and later attacks of an engagement | **NO** | `on_disturbed()` (§3.5) fired on the first swing → defender is CHASING. |
| Any state, enemy detected the player via a failed stealth contest earlier | **NO** | Detection transitions to CHASING before the player's next action — no stale-SLEEPING race exists. |

Ranged and melee use the identical table (both already funnel through `has_advantage()`).
The yellow "!" surprise floater (`player_vfx.gd show_surprise_mark()`) keeps firing whenever
`has_advantage()` returns true — unchanged.

### 4.3 `just_crossed_door` → `door_ambush` (the fix)

Replace the field (`enemy.gd:20`) and its write site (`enemy.gd:318–319`) with:

- **Set** in `_move_step()` only when ALL of: `stepping_through_door` (existing local, line 311);
  AND the enemy could **not** see the player from `prev_pos` (reuse the sight metric: Euclidean
  `dist_sq > FOV_RADIUS²` from prev_pos, or no `has_line_of_sight(prev_pos, player.grid_pos)`).
  State-agnostic set is fine once the LOS gate exists (a roamer passing a door while unable to
  see you is already ADV-eligible via the ROAMING row anyway).
- **Expire** at the top of the enemy's next `take_turn()` — clear unconditionally right next to
  the `oa_used_this_round = false` reset (`enemy.gd:131`). Lifetime = "the round it came through
  the door", matching SPD's guaranteed hit "on the turn they go through the door" — never 50
  turns later.
- **Consumption on read** (today's `player_vfx.gd:17` clear-on-check) becomes unnecessary but
  harmless; keep the one-shot clear so two attacks in one round (future Extra Attack) don't both
  get door-ADV.

Rewritten `has_advantage()` (`player_vfx.gd`):

```gdscript
func has_advantage(enemy: Enemy) -> bool:
    if enemy.door_ambush:
        enemy.door_ambush = false
        return true
    return enemy.behavior in [Enemy.Behavior.SLEEPING, Enemy.Behavior.STATIONARY, Enemy.Behavior.ROAMING]
```

### 4.4 Interactions audit

- **Opportunity attacks**: `_resolve_enemy_opportunity_attacks()` already skips SLEEPING enemies
  (unaware = no reaction) — consistent, no change. Player OAs against enemies route through
  `resolve_opportunity_attack()` which does NOT call `has_advantage()` (kept minimal per the OA
  design doc) — leave as is; an enemy provoking an OA is by definition moving in your sight.
- **Companion attacks** never get surprise ADV (companion has no ADV pipeline) but DO call
  `on_disturbed()` — a companion mauling a sleeper wakes it.
- **Reckless/Vex/Wolf/Zealous ADV sources**: unchanged; surprise remains one more +1 ADV source
  in the same pool, net rule handles stacking.
- **`GameState.invincible` / noclip**: stealth contest skipped on noclip (§3.3); nothing to
  consume, so no invincible-guard needed.

---

## 5. What must NOT change

- `TurnManager` — zero edits. Stealth contests and wake transitions resolve inline
  (Retaliation/OA precedent).
- `CombatMath.roll_with_adv_disadv()` and the net-ADV/DISADV house rule — surprise stays a single
  ADV source.
- STATIONARY/ROAMING/CHASING/SEARCHING `take_turn()` branches (except the SLEEPING rewrite and
  the two one-line flag changes in `_move_step()`/turn-top).
- The OA hooks at player.gd:707/784/963 — the stealth call is appended after them, not merged in.
- `_bump_attack()`/`ranged_attack()` bonus-damage stacking flow — `on_disturbed()` is a trailing
  call, not a restructure.

---

## 6. Open design questions (need user sign-off — don't silently decide)

1. **Extend the contest to ROAMING/STATIONARY?** v1 keeps deterministic spot-on-LOS for awake
   enemies. Recommendation for v2: same contest with the player's Stealth at DISADV (ports SPD's
   `dist/2` harsher wandering formula). Sign-off needed because it changes how threatening awake
   enemies feel.
2. **Combat noise**: should any player attack (hit or miss) auto-wake SLEEPING enemies within N
   tiles regardless of LOS? Recommendation: yes, N = 4, no roll — prevents silently executing a
   whole dorm room one sleeper at a time. Cheap to add as a radius broadcast at the
   `on_disturbed()` call sites.
3. **Distance-penalty tuning**: `- distance` on the enemy roll is a first guess. If detection
   feels too rare at range 5–6, soften to `- distance / 2` (integer). Balance pass after play.
4. **Surprising a SEARCHING enemy**: SPD's FOV clause would grant surprise against a hunter that
   currently can't see you; v1 says never. Revisit if a future invisibility/hide action lands.
5. **Barbarian stealth identity**: Barbarian lacks `check_prof_dex`, so it's the worst sneak.
   Fine thematically — confirm no talent (Danger Sense aside) is expected to patch this.

---

## 7. Implementation checklist (suggested commit breakdown)

1. **Enemy WIS infrastructure**: `"wis_mod"` pool key → `stats.wisdom` in `_apply_stats()`
   (mirror lines 62–63); `Enemy.perception_roll(distance)` helper beside `resist_check()`; seed
   `wis_mod` values in `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL`. Commit.
2. **Stealth contest**: `player.gd._resolve_stealth_checks(next)` + calls after the three OA
   hooks (707 / 784 / 963); noclip skip; detection log line + `stealth:` meta +
   `fmt_stealth_tooltip()` in `tooltip_formatters.gd`. Commit.
3. **SLEEPING wake rewrite**: delete `can_see` wake and `WAKE_RADIUS_SQ`; adjacency (Chebyshev
   ≤ 1) free-wake in `take_turn()`; `Enemy.on_disturbed()` + calls from `_bump_attack()`,
   `PlayerRanged.ranged_attack()`, `_resolve_cleave_attack()`, `resolve_opportunity_attack()`,
   `companion._attack_enemy()`. Commit.
4. **Surprise trigger rework**: `just_crossed_door` → `door_ambush` (LOS-gated set in
   `_move_step()`, expiry at `take_turn()` top); rewrite `has_advantage()` per §4.3. Commit.
5. **Docs**: update `scripts/entities/CLAUDE.md` (new "Stealth & Surprise" section: contest
   formula, trigger table, `door_ambush` lifecycle, `on_disturbed()`), `scripts/ui/CLAUDE.md`
   (new tooltip kind), pointer lines in root `CLAUDE.md` (also fix the stale "CHASING sets
   `just_crossed_door`" text). Commit.

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without asking.
Don't squash into one giant commit.
