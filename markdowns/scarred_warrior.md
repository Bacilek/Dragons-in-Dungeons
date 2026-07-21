# Scarred Warrior — Subclass Implementation Spec

## Overview
A subclass that turns near-death into power. Core identity: the lower your HP, the more dangerous you become. Reward for playing on the edge.

---

## Shared Mechanic — Bloodied
Used by multiple talents. Define globally (not Scarred Warrior exclusive — other classes may use it later).

- **Bloodied** = entity has **less than 50% of their max HP**
- `IsBloodied = CurrentHP < (MaxHP / 2)` (integer division, round down)
- Recompute on every HP change.

---

## Activation Ability — Limit Break

- **Type:** Active (costs a turn)
- **Uses:** Once per **long rest**
- **Effect:** Deal damage equal to your **missing HP** (`MaxHP - CurrentHP`) to target enemy.
- Missing HP is calculated at the moment of activation (before any other effects resolve).

**Implementation notes:**
- This is a fixed damage value — no roll to hit, no roll for damage (unless modified by talent).
- ⚠️ **Balance note:** At low HP this is enormous burst. A barbarian at 1 HP out of 100 deals 99 damage — potentially the highest single-hit damage in the game. Intentional spike; just document it.
- Apply enemy resistances/AC normally unless otherwise noted by talent.

**State to track:**
```
LimitBreakUsed: bool    // resets on long rest
```

---

## Talent 1 — Born in Blood
*Damage scaling changes based on Bloodied status.*

| Rank | Effect |
|---|---|
| 1 | +/- 1× RageBonus to damage received/dealt |
| 2 | +/- 2× RageBonus |
| 3 | +/- 3× RageBonus |

**Exact behavior:**
- If **NOT Bloodied**: incoming damage +N×RageBonus (you take more)
- If **Bloodied**: incoming damage -N×RageBonus (you take less); minimum 0

**Implementation notes:**
- This modifier applies to physical incoming damage (after Rage's 50% reduction, or before — ⚠️ confirm order with design).
- Does NOT affect Limit Break damage.
- Recompute on Bloodied status change.

---

## Talent 2 — Enough is Enough
*Upgrades Limit Break.*

**Rank 1:** Limit Break applies your **Weapon Mastery** effect automatically (no check or roll required).

**Rank 2:** Limit Break also deals damage to all entities **adjacent** to the primary target (same damage value, full damage — not reduced).

**Rank 3:** Limit Break is now **ranged** (range: 5 tiles). It hits the primary target AND **every entity in a line** between you and the target (like a piercing projectile).

**Implementation notes:**
- Rank 1: look up player's weapon mastery and apply its on-hit effect as if triggered. Define a `WeaponMastery.Apply(target)` method if not already abstracted.
- Rank 2: collect all entities in adjacent tiles (8-directional), apply Limit Break damage to each. Does this include friendlies? ⚠️ **Confirm AoE targeting rules.**
- Rank 3: cast a ray from player to target (5 tile max range). Collect all entities on that line, apply damage to each (including target). Rank 2 splash still applies from each hit entity? ⚠️ **Confirm stacking behavior.**
- Ranks stack — rank 3 includes rank 1 and rank 2 effects.

---

## Talent 3 — Unnamed (Bloodied Regen)
*While Bloodied, regenerate Temporary HP each turn.*

| Rank | THP gained per turn |
|---|---|
| 1 | 1 × RageBonus |
| 2 | 2 × RageBonus |
| 3 | 3 × RageBonus |

**Implementation notes:**
- Triggers at the **start of player's turn** (before any actions).
- Only triggers if player is currently Bloodied.
- THP stacks up to a cap or replaces previous THP depending on your global THP rules.
- ⚠️ Suggest naming this talent. Candidates: *Last Stand*, *Battle Scarred*, *Spite*.

---

## Talent Synergy Notes
- Born in Blood + Limit Break: using Limit Break while Bloodied costs you low HP (to enter Bloodied) but grants damage reduction from Born in Blood — survivability loop.
- Bloodied Regen keeps you alive at low HP while Born in Blood punishes recovery above 50% — incentivizes staying in the Bloodied zone.
- Enough is Enough rank 3 ranged pierce + rank 2 splash could hit a LOT of enemies. Strong in corridor-heavy dungeon layouts.
