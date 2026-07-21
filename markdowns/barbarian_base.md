# Barbarian — Base Class Implementation Spec

## Overview
Every Barbarian subclass inherits these abilities. Implement them in `BarbarianBase` or equivalent base class before layering subclass logic on top.

---

## Level 1 Abilities

### Rage (Active Toggle)
- **Type:** Toggle (activate/deactivate)
- **Uses per long rest:** TBD by design (carry over existing value)
- **Duration:** Lasts 1 turn after activation; prolonged by:
  - Attacking (any attack action taken by the player)
  - Being attacked (any incoming hit, hit or miss)
  - Each qualifying event resets the duration to 1 more turn
- **Effect while active:**
  - Receive only **50% of physical damage** (round down)
  - Enables subclass abilities that require Rage as a prerequisite
- **Rage Bonus:** A flat numeric value (define as `RageBonus: int`) used by multiple subclass talents. Set value per level or design doc — referenced throughout subclass specs.

**Implementation notes:**
- Track `RageActive: bool` and `RageTurnsRemaining: int`
- On turn start: decrement `RageTurnsRemaining`; if ≤ 0, deactivate Rage
- On attack or on being attacked: if Rage is active, reset `RageTurnsRemaining = 1`
- Physical damage 50% reduction applies before AC/other reductions (confirm order with design)

---

### Unarmored Defense (Passive)
- **Condition:** Player is wearing **no armor** (clothes are allowed; only armor items are blocked)
- **Effect:** Add CON modifier to AC
- **Implementation notes:**
  - Check equipment slot for armor-type items on every AC calculation
  - Clothes/cosmetic items must be tagged differently from armor
  - Stacks normally with DEX modifier to AC (standard AC formula: 10 + DEX + CON if unarmored)

---

---

## Base Talents (available to all Barbarian subclasses)

### Talent — Psycho
*Momentum: kills and crits feed into your next strike.*

**Rank 1:** After a **kill** or a **critical hit**, your next attack is made with **Advantage**.

**Rank 2:** When attacking with Advantage, add **STR modifier** to damage.

**Rank 3:** When attacking with Advantage, your crit range expands to **19–20** (not just nat 20).

**Implementation notes:**
- "Next attack" buff is consumed on the next attack regardless of hit/miss.
- Buff is not re-granted if the Advantage attack itself is also a crit/kill — it's a one-shot proc. ⚠️ **Confirm: should crit-while-Advantage-active re-trigger Psycho?**
- Rank 2 STR modifier is added as flat bonus damage (no roll); negative STR mod subtracts.
- Rank 3: before rolling d20, check for Advantage; if active, treat any roll of 19 as a crit. Applies only when Advantage is active, not universally.

**State to track:**
```
PsychoAdvantageReady: bool    // set on kill or crit, consumed on next attack
```

---

### Talent — Bruiser
*The lower you fall, the harder you hit back.*

**Rank 1:** While **Bloodied** (< 50% max HP), any healing you receive is improved by **+1d4**.

**Rank 2:** While Bloodied, gain **+1 AC**.

**Rank 3:** Once per **floor** — when Raging and you would be brought **below 1 HP** (lethal hit), instead survive at **1 HP** and Rage ends immediately.

**Implementation notes:**
- Rank 1: roll 1d4 and add to the heal amount before applying to HP. Applies to all incoming healing (Hit Dice, potions, Zealot Strike, etc.) ⚠️ **Confirm: does it apply to Temporary HP grants?**
- Rank 2: +1 AC is a passive modifier active whenever `IsBloodied == true`; recompute on every HP change.
- Rank 3: this is a death prevention hook. Intercept any damage that would reduce HP to 0 or below; if `RageActive && BruiserReviveAvailable`, set `CurrentHP = 1`, set `RageActive = false`, set `BruiserReviveAvailable = false`. Reset `BruiserReviveAvailable` on entering a new floor.
- Rank 3 ends Rage — trigger all Rage-end cleanup (subclass effects, duration reset, etc.).

**State to track:**
```
BruiserReviveAvailable: bool    // resets on new floor
```

---

### Talent — Battlefield Expert
*Use footwork to dictate the fight.*

**Rank 1:** After performing a **sidestep**, your next attack is made with **Advantage**.

**Rank 2:** After performing a sidestep, the sidestepped enemy has **Disadvantage** on their next attack.

**Rank 3:** Once per turn — if you were **hit** during the previous turn, your first sidestep on your current turn is **free** (does not cost a turn).

#### Sidestep Definition
A sidestep occurs when the player moves from a tile that is within 1-tile range of an enemy into another tile that is also within 1-tile range of the **same** enemy — without increasing or decreasing the distance to that enemy. In other words: lateral movement around an adjacent enemy.

**Detection logic:**
```
isSidestep = (
    previousTile.IsAdjacentTo(enemy) &&
    newTile.IsAdjacentTo(enemy) &&
    Distance(previousTile, enemy) == Distance(newTile, enemy)  // same ring
)
```
> For a grid where adjacency = 1 tile (8-directional), this means both tiles are adjacent to the same enemy and neither is the enemy's tile itself.

**Implementation notes:**
- Rank 1 Advantage: consumed on next attack, same as Psycho's Advantage (can they stack? ⚠️ **Confirm stacking rules for multiple Advantage sources**).
- Rank 2 Disadvantage: applied to target enemy as a debuff lasting until their next attack resolves.
- Rank 3 "free sidestep": track `WasHitLastTurn: bool`. On turn start, if true, grant `FreeSidestepAvailable = true`. First sidestep this turn that consumes it is free (movement processed, turn NOT ended). Subsequent sidesteops this turn cost normally.
- If multiple enemies are adjacent, a move may qualify as a sidestep relative to one enemy but not another — apply buff once regardless.

**State to track:**
```
WasHitLastTurn: bool             // set when hit during enemy turn, cleared at own turn start after use
FreeSidestepAvailable: bool      // granted at turn start if WasHitLastTurn, consumed on first free sidestep
```

---

## Shared State to Track (per Barbarian instance)
```
// Base
RageActive: bool
RageTurnsRemaining: int
RageUsesRemaining: int            // resets on long rest
RageBonus: int                    // base value; may scale with level
IsWearingArmor: bool              // recomputed on equipment change

// Psycho talent
PsychoAdvantageReady: bool

// Bruiser talent
BruiserReviveAvailable: bool      // resets on new floor

// Battlefield Expert talent
WasHitLastTurn: bool
FreeSidestepAvailable: bool
```

---

## Notes
- Rage deactivation should trigger cleanup of any subclass effects that require Rage (e.g. Berserker Frenzy becomes unusable, Wild Heart form bonuses that need Rage).
- Short rest resets designated per-short-rest abilities (see subclass specs).
- **Advantage/Disadvantage stacking:** Multiple sources of Advantage do not stack in standard 5e (roll 2d20 take highest, regardless of how many sources). Disadvantage cancels Advantage. Define your stacking model early — referenced by Psycho, Battlefield Expert, and potentially subclass abilities.
