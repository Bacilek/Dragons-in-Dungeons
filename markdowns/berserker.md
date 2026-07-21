# Berserker — Subclass Implementation Spec

## Overview
A high-risk, high-reward subclass built around self-damaging attacks and masochistic combat loops. Core identity: hurting yourself to hurt enemies harder.

---

## Activation Ability — Frenzy

- **Type:** Active (free action — does NOT cost a turn)
- **Prerequisite:** Rage must be active
- **Uses:** Once per **short rest** (also resets on long rest)
- **Timing:** Can be used on player's turn only

### Resolution
Roll to hit (d20 + attack modifier):

| Roll | Effect |
|---|---|
| Nat 1 | Miss — only YOU take damage (weapon damage roll, no bonus) |
| 2–19 | Hit — deal weapon damage to enemy AND take the same amount yourself |
| Nat 20 | Critical — deal double damage to enemy, you take **zero** damage |

- Damage dealt to enemy and damage taken by self are **the same roll** (roll once, apply to both) unless modified by talents.
- Sadist Monster talent modifies **enemy damage only** — self-damage stays at base.
- Self-damage from Frenzy bypasses Rage's 50% physical damage reduction (design intent: you're hurting yourself deliberately). ⚠️ **Confirm with design.**

**State to track:**
```
FrenzyUsedThisShortRest: bool    // reset on short rest and long rest
```

---

## Talent 1 — Sadist Monster
*Frenzy deals bonus damage to the enemy only (not to self).*

| Rank | Bonus Damage |
|---|---|
| 1 | +1d6 |
| 2 | +2d6 |
| 3 | +3d6 |

- Bonus damage is added **after** the shared damage roll, applied to enemy only.
- On Nat 20: bonus damage is also doubled (it's part of the crit). ⚠️ **Confirm crit rules for bonus dice.**

---

## Talent 2 — Masochist Monster
*Being hurt on your turn fuels your defense.*

**Rank 1:** If you take any damage on your turn → gain **+1 AC** until the start of your next turn.

**Rank 2:** Additionally → gain Temporary HP equal to `RageBonus * 1d4` roll.

**Rank 3:** Rage does **not** end while at least 1 enemy is within your Field of View (FOV).

**Implementation notes:**
- "Take damage on your turn" includes Frenzy self-damage — intentional synergy.
- AC bonus is temporary; remove at the start of the player's next turn.
- Rank 3: override Rage expiry check — if `EnemiesInFOV > 0`, skip decrement/deactivation of Rage.
- Rank 3 does NOT grant unlimited Rage uses — only prevents expiry by time; uses are still consumed on activation.

**State to track:**
```
TookDamageThisTurn: bool         // reset at turn start
MasochistACBonus: int            // 0 or 1, removed next turn start
```

---

## Talent 3 — Frenzied Killer
*Frenzy refreshes its use more frequently.*

**Rank 1:** Refreshes after a **kill** (killing blow on any enemy).

**Rank 2:** Also refreshes after landing a **critical hit**.

**Rank 3:** Also refreshes every **3 turns**.

**Implementation notes:**
- Refresh = set `FrenzyUsedThisShortRest = false`.
- Rank 3 turn counter resets when Frenzy is used, not when it refreshes. Track `TurnsSinceLastFrenzyUse: int`.
- ⚠️ **Balance note:** Rank 3 enables effectively unlimited Frenzy in sustained combat. Consider whether this is intentional or if a secondary cap is needed (e.g. max 3 refreshes per combat encounter).

**State to track:**
```
TurnsSinceLastFrenzyUse: int     // increments each turn, resets on Frenzy use
```

---

## Talent Synergy Notes
- Masochist Monster rank 1/2 synergizes directly with Frenzy self-damage — every Frenzy use also triggers the AC/THP bonus.
- Sadist Monster + Frenzied Killer: more Frenzy uses → more burst damage without extra self-damage penalty.
