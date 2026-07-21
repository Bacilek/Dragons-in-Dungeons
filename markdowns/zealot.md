# Zealot — Subclass Implementation Spec

## Overview
A subclass built around trading HP for power and then recovering it. Core identity: reckless offense backed by divine resilience. Uses Hit Dice as an in-combat healing resource.

---

## Shared Mechanic — Morale
Used by Judgement Day talent. Morale is a **new global mechanic** (not Zealot-exclusive).

- Morale reflects how the player has treated NPCs throughout the run.
- Two states for Zealot purposes: **High Morale** (benevolent/positive NPC interactions) → Radiant damage; **Low Morale** (hostile/negative) → Necrotic damage.
- Exact morale thresholds and tracking are out of scope for this spec — implement a `PlayerMorale` enum or value and expose `GetDamageType() → DamageType` helper.

---

## Shared Mechanic — Overheal
Used by Talent 2.

- **Overheal** = healing received when already at max HP, or the portion of a heal that exceeds max HP.
- `OverhealAmount = Max(0, (CurrentHP + HealAmount) - MaxHP)`
- Track for the duration of the heal resolution.

---

## Activation Ability — Zealot Strike (name TBD)

- **Type:** Active Toggle (costs no turn by itself)
- **Effect:** Your **next melee attack this turn** (regardless of hit or miss) consumes **1 Hit Die** and heals you for the rolled amount.
- Hit Die roll: `1d[HitDieSize] + CON modifier` (standard 5e Hit Die recovery formula).
- The attack still resolves normally (roll to hit, deal damage as usual); the heal is a separate effect triggered on attack execution.
- If the turn ends without a melee attack, the toggle deactivates with no effect (Hit Die is NOT consumed).

**State to track:**
```
ZealotStrikeArmed: bool    // set true on activation, consumed or cancelled on turn end
```

**Implementation notes:**
- Consuming a Hit Die: decrement `HitDiceRemaining`. If 0, ability cannot be activated.
- Hit Die size is determined by class (Barbarian = d12).

---

## Talent 1 — Judgement Day
*After healing from Zealot Strike, your next attack deals bonus Radiant or Necrotic damage.*

| Rank | Bonus Damage |
|---|---|
| 1 | 1 × RageBonus × 1d6 |
| 2 | 2 × RageBonus × 1d6 |
| 3 | 3 × RageBonus × 1d6 |

**Implementation notes:**
- Buff triggers when the Zealot Strike heal resolves.
- Damage type: Radiant if High Morale, Necrotic if Low Morale (see Morale above).
- The buff applies to the **next attack** after the heal — not the same attack that triggered the heal.
- Buff expires at end of turn or on next attack, whichever comes first.
- Damage rolls: `N × RageBonus × 1d6` — roll 1d6 once, multiply by (N × RageBonus). ⚠️ **Confirm formula interpretation** — alternatively: roll Nd6 and multiply sum by RageBonus.

---

## Talent 2 — Overheal Shield
*Overhealing generates Temporary HP.*

| Rank | THP Gained |
|---|---|
| 1 | Overheal amount only |
| 2 | The entire heal amount |
| 3 | Entire heal amount + overheal amount |

**Example (MaxHP 50, CurrentHP 45, Heal 10 → Overheal 5):**

| Rank | THP |
|---|---|
| 1 | 5 |
| 2 | 10 |
| 3 | 15 |

**Implementation notes:**
- ⚠️ **Balance note:** Rank 3 is effectively doubling the heal value as THP when overhealing. At max HP + large Hit Die roll this can grant substantial THP. Intentional?
- THP replaces existing THP (standard rules) or stacks? Apply your global THP rule.
- Applies to all healing, or Zealot Strike only? ⚠️ **Confirm scope.**

---

## Talent 3 — Never Back Down
*Gain additional Hit Dice.*

| Rank | Bonus Hit Dice |
|---|---|
| 1 | +1 |
| 2 | +2 |
| 3 | +4 |

- Bonus is added to the player's **max Hit Dice pool**.
- Resets with long rest like normal Hit Dice.
- Note: ranks are cumulative (rank 3 total = +4 from rank 3 only, not +1+2+4). ⚠️ **Confirm: is rank 3 total +4, or does it stack to +1+2+4 = +7?**

---

## Talent Synergy Notes
- Judgement Day + Never Back Down: more Hit Dice → more Zealot Strike activations per long rest → more Judgement Day procs.
- Overheal Shield is most valuable when you're near or at max HP — rewards staying healthy rather than playing low HP like Scarred Warrior. Opposite design intent; pair carefully if player mixes through respec.
- Radiant vs Necrotic split via Morale adds a roleplay-to-gameplay feedback loop — reward players for consistent NPC behavior.
