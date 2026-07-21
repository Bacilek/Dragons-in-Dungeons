# Wild Heart — Subclass Implementation Spec

## Overview
A subclass built around shapeshifting and environmental mastery. Core identity: fluid adaptability — change form to match the situation, and leverage terrain that would hinder anyone else.

---

## Activation Ability — Animal Form (Toggle)

- **Type:** Toggle (switch between forms; switching costs no turn — confirm)
- **Available forms at base:** Bear, Eagle, Wolf
- Each form provides a passive bonus while active. Only one form active at a time.

### Bear Form
- **Effect:** 25% resistance to **elemental damage** (Fire, Cold, Lightning, Thunder, Acid, Poison — define your elemental damage types list).

### Eagle Form
- **Effect:** Enemies do **not** gain Attacks of Opportunity against you.

### Wolf Form
- **Condition:** At least **4 enemies** within Field of View (FOV)
- **Effect:** Gain **Advantage** on all your attacks.
- If the condition drops below 4 enemies mid-turn, advantage is lost immediately or at start of next turn. ⚠️ **Confirm timing.**

**State to track:**
```
ActiveForm: AnimalForm    // enum: None, Bear, Eagle, Wolf, Owl, Panther, Salmon
```

---

## Talent 1 — Expanded Forms (Long Rest Reward)
*After each long rest, gain one random additional form from the Expanded pool.*

**Expanded forms pool:** Owl, Panther, Salmon

| Rank | Form Effect |
|---|---|
| 1 | Owl: traverse **chasms** freely. Panther: move through **mud** tiles without spending extra movement. Salmon: move through **water** tiles without spending extra movement. |
| 2 | Gain **THP** equal to RageBonus at the start of each turn while standing on the corresponding terrain tile (Owl → chasm, Panther → mud, Salmon → water). |
| 3 | Gain **+2 AC** while standing on the corresponding terrain tile. |

**Implementation notes:**
- "Random" form: roll or pick randomly from {Owl, Panther, Salmon} each long rest. Can the same form be granted multiple days in a row? Is there a rotation? ⚠️ **Define randomness rules.**
- Terrain traversal (rank 1): implement as passability flags per tile type per active form. Chasm/mud/water tiles are normally impassable or costly.
- THP (rank 2) and AC (rank 3) check active form AND current tile type at turn start.
- Ranks are cumulative: rank 3 includes rank 1 and rank 2 effects.

---

## Talent 2 — Enhanced Forms
*Upgrades the base three forms (Bear, Eagle, Wolf).*

| Rank | Bear | Eagle | Wolf |
|---|---|---|---|
| 1 | Resistance also includes **magical damage** (Radiant, Necrotic, Force) | +1 **FOV** radius | Condition reduced to **3 enemies** |
| 2 | Resistance increased to **33%** | Ranged attacks against you have **-2 to hit** | Condition reduced to **2 enemies** |
| 3 | Resistance increased to **50%** | Ranged enemies have **Disadvantage** to hit you | Condition: **1 enemy + 1 friendly** in FOV |

**Implementation notes:**
- Bear: elemental res stacks with magical res additively at rank 1 (combined pool). At rank 2/3, the percentage applies to the full combined pool. Or: track elemental and magical separately? ⚠️ **Confirm resistance model.**
- Eagle rank 2: flat -2 to incoming ranged attack rolls (before resolution).
- Eagle rank 3: Disadvantage supersedes -2 penalty (apply whichever is more impactful, or both — ⚠️ confirm stacking).
- Wolf rank 3 condition: **1 enemy AND at least 1 friendly entity in FOV**. Note: this is a fundamentally different condition from the original 4-enemy requirement. ⚠️ **Confirm design intent** — this could activate Wolf nearly always in party-adjacent or companion scenarios.

---

## Talent 3 — Wild Companion (Long Rest Summon)
*After each long rest, summon an animal companion.*

| Rank | Companion |
|---|---|
| 1 | Squirrel |
| 2 | Boar |
| 3 | Bear |

**Implementation notes:**
- Each companion is a separate entity on the map with its own stats, AI, and turn.
- Define stat blocks separately per companion (out of scope for this spec).
- Only one companion at a time. If the previous companion is alive, does summoning replace it? ⚠️ **Confirm.**
- Companion is tied to the long rest summon — if it dies before the next long rest, it's gone until then.
- ⚠️ **Balance note:** A summoned Bear companion at rank 3 is a powerful tank/damage dealer added to every encounter. Ensure Bear companion stats are balanced against encounter difficulty.

---

## Terrain Tile Types to Implement
Required for Talent 1:

| Tile | Normal behavior | Wild Heart override |
|---|---|---|
| Chasm | Impassable / instant death | Owl form: passable |
| Mud | Movement costs extra turn | Panther form: no cost |
| Water | Movement costs extra turn | Salmon form: no cost |

---

## Talent Synergy Notes
- Wolf form rank 3 (1 enemy + 1 friendly) + Talent 3 companion: your companion counts as the "1 friendly" — effectively Wolf advantage is always available in solo play once companion is summoned.
- Bear form + Enhanced Forms rank 3 (50% res to elemental + magical) makes Wild Heart the most damage-resistant Barbarian subclass against non-physical damage.
- Expanded Forms terrain THP (rank 2) + Rage: terrain becomes a defensive resource, incentivizing tactical positioning.
