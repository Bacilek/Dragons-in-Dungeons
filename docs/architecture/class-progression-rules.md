# Class Progression Rules - the shared budget every class must fit

**Status:** RULE DOC (created 2026-09-02). Not a feature design - this is the *constraint* every
class/race/talent design gets checked against, including the ones already shipped. Most of the
scaffolding it describes already exists (`TalentTiers.TIER_LEVEL_RANGES`, per-level talent points,
`GameState.bonus_action_used`); what this doc adds is the *rule* those numbers were chosen to
serve, plus the two concrete caps that are currently missing (§5) and the Tier 3/4 content that is
still empty (§8).

Read this before designing a new class, a new subclass, a new race, or a new talent tree. When a
design fights the rule, the rule wins unless it is explicitly grandfathered in §8.

---

## 1. The one invariant

> **Progression almost never adds a button.**

That is the whole doc in one line. Everything below derives from it.

The game's identity is D&D flavored, but the *feel* target is Pixel Dungeon / Shattered PD: a turn
should take a couple of seconds, not a couple of minutes. Shattered PD runs to hero level 30 and
hands out a talent point nearly every level, and it still plays fast - because those ~29 points buy
small modifiers, not new abilities. The action bar looks roughly the same at level 30 as at level 5.

That is the model. Long progression is fine. Wide progression is fine. **Growing the number of
live options on screen is not.**

### 1.1 What the constraint actually is

The action economy is already solved: `GameState.bonus_action_used` gates the player to one bonus
action per real round no matter how many abilities they own. Owning six abilities does not mean
taking six actions.

So the thing being protected here is **cognitive load, not action economy**. The cost of an extra
ability is the time the player spends scanning the bar deciding, every single turn, for the rest of
the run. That cost is paid once per turn forever, which is why it is worth being strict about.

### 1.2 The validation metric

Not a feeling - a count. Play a run to the level cap and count the turns where deciding took more
than ~5 seconds.

- Under ~10% of turns: pacing is fine, ship it.
- Around ~30%: something is over budget. The count tells you *which* turns, so the fix is targeted
  instead of guessed.

Run this before concluding that a progression change "feels" too slow or too thin.

---

## 2. Active ability budget

Abilities reach the player from six sources. Only three of them are allowed to hand out an active
button.

| Source | Active abilities | Notes |
|---|---|---|
| Class baseline (L1) | **1** | Rage, Flurry of Blows, Hunter's Mark, Spark |
| Subclass (boss-gated) | **1** | The subclass *is* the new-ability moment |
| Race | **1** | Breath Weapon, Adrenaline Rush, Large Form, ... |
| Talents | **0** | Passives and upgrades only - see §3 |
| Spells | ability bar | Caster parallel track - see §5 |
| Items | quickbar | Separate bar, separate Tab |

**Ceiling: 3 non-spell active abilities, at every level from 1 to 20.** Level 20 does not mean 20
buttons. It means the same 3 buttons, deeper.

Passive class features (unarmored defense, resistances, proficiency growth, mastery slots, HP)
are unbudgeted - they change numbers, not decisions, so they cost nothing per turn. Spend
progression there freely.

### 2.1 Corollary: the subclass is the only new-ability moment

Past level 1, choosing a subclass is the **only** thing in the entire game that grants a new active
ability. This is what makes the subclass choice feel like an event rather than one talent among
many, and it is what keeps talents free to be small (§3).

---

## 3. Talent rules

### 3.1 Magnitude, not count

**Do not limit how many talent points the player gets. Limit how big one rank is.**

This is the single most important rule in the talent system, and it inverts the intuitive worry
("if the player cannot max everything, every talent will feel weak"). Shattered PD's talents are
individually weak on purpose and the system works, because identity comes from *concentrating* weak
ranks in one direction, not from any single rank being strong.

**Sanity test for one rank:** if the player skipped this rank by accident, would the run break? If
yes, the rank is too big. A rank should be barely perceptible alone and clearly felt at 3.

Because magnitude is what controls power, the run length does not. That is why a level 20 cap is
safe here and would not be in D&D.

### 3.2 Composition per tier

Each tier holds 3 talents. Target composition:

- **2 pure passives** - change a stat, a threshold, or a rule. No new UI, no new button.
- **1 signature upgrade** - modifies the class/subclass active ability the player already has.
- **0 new abilities** - see §2.1.

A passive still expands character identity as long as it is *attached to the signature ability*
("Rage also does X") rather than free-floating ("+1 AC"). Prefer attached passives; that is where
the "talents feel generic" complaint comes from, not from them being passive.

### 3.3 Capacity vs points

Capacity should exceed the points on offer by roughly 2x. 4 tiers x 3 talents x 3 ranks = **36
capacity** against **19 points** (§4). The player maxes about 6 of 12 talents.

Not being able to max everything is the feature, not a problem to be tuned away.

---

## 4. Level 1-20 schedule

Level cap is **20**. Target floor count is **~15**, bosses on 5 / 10 / 15, which keeps the existing
floor-5 boss as the Tier 2 gate unchanged.

| Lvl | Chassis (every class) | Talent point | Caster track |
|---|---|---|---|
| 1 | signature active #1, baseline passives | - (T1 open) | 3 cantrips, 1st-level slots |
| 2 | - | +1 T1 | - |
| 3 | passive feature | +1 T1 | - |
| 4 | - | +1 T1 | 4 cantrips |
| 5 | - | +1 T1 | 3rd-level slots |
| 6 | - | +1 T1 | - |
| 7 | **SUBCLASS: active #2** (boss-gated, floor 5) | +1 T2 | - |
| 8 | passive feature | +1 T2 | - |
| 9 | - | +1 T2 | 5th-level slots (the cap) |
| 10 | - | +1 T2 | 5 cantrips |
| 11 | - | +1 T2 | slots widen only |
| 12 | passive feature | +1 T2 | - |
| 13 | **Tier 3 opens** (specialization) | +1 T3 | - |
| 14 | - | +1 T3 | - |
| 15 | - | +1 T3 | - |
| 16 | passive feature | +1 T3 | - |
| 17 | - | +1 T3 | - |
| 18 | **Tier 4 opens** (capstone) | +1 T4 | - |
| 19 | - | +1 T4 | - |
| 20 | capstone passive | +1 T4 | - |

**19 talent points total** (L2-L20). Matches the shipped `TalentTiers.TIER_LEVEL_RANGES` and
`GameState.gain_exp()`'s one-point-per-level grant exactly - no code change needed for the
schedule itself.

**Landmarks:** L1, L7 (subclass), L13 (Tier 3), L18 (Tier 4). Four deliberate spikes; every other
level is flat by design. People need orientation points, but they do not need twenty of them.

---

## 5. Caster track

Casters get a parallel spell track that does **not** draw from the talent budget. Two caps apply.

### 5.1 Slots grow wide, not tall

> **Maximum spell level is 5. Never 6th through 9th.**

Levels beyond the point where 5th-level slots arrive add *more low-level slots*, not new tiers.
This is the flat-curve rule applied to casters, and it has a nice side effect: Fireball stays
impressive for the entire run instead of becoming filler by level 13.

`StandardSlotPool.SLOT_TABLE` (`scripts/items/spell_slot_pool.gd`) currently runs the real D&D 2024
full-caster table all the way to 9th-level slots. **Levels 1-10 already match this rule and need no
change**; levels 11-20 do. Proposed replacement for those rows:

```
11: {1:5, 2:3, 3:3, 4:3, 5:2}
12: {1:5, 2:4, 3:3, 4:3, 5:2}
13: {1:5, 2:4, 3:4, 4:3, 5:2}
14: {1:5, 2:4, 3:4, 4:3, 5:3}
15: {1:6, 2:4, 3:4, 4:3, 5:3}
16: {1:6, 2:5, 3:4, 4:3, 5:3}
17: {1:6, 2:5, 3:4, 4:4, 5:3}
18: {1:6, 2:5, 3:5, 4:4, 5:3}
19: {1:7, 2:5, 3:5, 4:4, 5:4}
20: {1:7, 2:6, 3:5, 4:4, 5:4}
```

`HalfCasterSlotPool` already tops out at 5th level and needs no change. `PactSlotPool` also tops out
at 5 and needs no change.

### 5.2 Prepared count is capped

`SpellcasterState.prepared_max()` currently returns `character_level` for Wizard, i.e. **20
prepared spells at level 20**. That is the single largest violation of §1 in the codebase.

> **Wizard prepared cap: `min(character_level, 6)`.**

Ranger's half-caster formula (`max(1, WIS mod + level/2)`) already lands in a sane range and needs
no change.

Known spells are deliberately uncapped - the spellbook can grow as large as it likes. What is
capped is how many are live at once. Swapping happens at a long rest, which is exactly where a
slow, considered decision belongs.

### 5.3 Open question: ability bar pressure

The ability bar is 9 slots. At level 10+ a Wizard carries 3 non-spell actives (§2) plus 5 cantrips
(`cantrip_max()`), which is 8 of 9 before a single leveled spell is placed.

The bar, not `prepared_max()`, is the real binding constraint on a caster's turn. This is not
resolved by this doc. Two candidate directions when it becomes a problem:

- Cantrips move off the bar into the Spellbook / Special quick-cast slot, leaving the bar for
  leveled spells and class actives.
- The cantrip cap stops at 3 or 4 rather than growing to 5.

Do not paper over this by growing the bar past 9 slots - that is §1 in reverse.

---

## 6. Resource economy

### 6.1 There is one economy, not two

Spell slots, `rage_uses_max`, `monk_focus_points`, `hunters_mark_uses_remaining`, race charges - all
of these are the same mechanic: **rest-gated charges**. The only difference is whether the pool has
a level dimension.

Cooldowns are not a second economy. They are a different *axis of tension*:

| | Where tension lives | What it asks the player |
|---|---|---|
| Rest-gated charges | between fights (attrition) | "Do I spend this now or save it?" |
| Cooldowns | inside one fight (rotation) | "What order do I press these in?" |

A roguelike lives on attrition. The long rest already costs 100 combined `food_value` and 20 turns,
which makes it a genuinely scarce resource - so the attrition layer is real and worth protecting.

> **Default: rest-gated charges. Cooldowns are a deliberate class identity, not an alternative
> system.**

### 6.2 Cooldown classes are a minority

Hybrid and Rampager run on cooldown + nova (Essence / Fury) on purpose. Their fantasy is
"never needs to rest", which is a legitimate and sellable class pitch, and it is why they sit off
the D&D rest model entirely (`Stats.caster` stays null, no tier plumbing).

This must stay a minority - roughly 2 of N classes. If every martial class moved to cooldowns, the
attrition layer disappears and the game stops being a roguelike. When a new class is proposed on
cooldowns, the question to answer is "is 'this class never rests' actually its identity?" If the
answer is no, it uses charges.

---

## 7. D&D fidelity test

The game is D&D 2024 flavored, but turn economy, reactions, movement, and conditions already
diverge. The brand value is not in the numbers.

> **Names and resource shapes come from D&D. Numbers and triggers are ours.**

Rage is called Rage, recharges on a long rest, and grants damage plus resistance - a D&D player
recognizes it instantly. What exactly Bruiser rank 3 does to it is entirely ours to invent.

Practical test for any mechanic: **would a D&D player recognize this by name and expect roughly
this shape?** If yes, keep the name and approximate the shape. If the mechanic has no engine
support here (reactions beyond OAs, ritual components, ...), invent freely - nobody is checking the
PHB against this game, and the parts that already diverge have cost nothing.

---

## 8. Current state vs this rule

Audit of what is shipped. Items marked **fix** violate the rule; items marked **grandfathered** are
accepted exceptions that should not become precedent.

### Already conforms

- `TalentTiers.TIER_LEVEL_RANGES = {1:[1,6], 2:[7,12], 3:[13,17], 4:[18,20]}` - 4 tiers, cap 20,
  exactly §4.
- `GameState.gain_exp()` grants 1 point per level into the level's tier pool - exactly §4.
- `GameState.bonus_action_used` - the action-economy half of §1.1 is already solved.
- Barbarian Tier 1 (Psycho / Bruiser / Battlefield Expert): passive-shaped, no new buttons.
- Subclass grants exactly one free ability (Frenzy / Limit Break / Animal Form / Zealot Strike) and
  its Tier 2 talents only upgrade it - this is §2.1 and §3.2 working correctly. Use this as the
  reference shape.
- `HalfCasterSlotPool` / `PactSlotPool` already cap at 5th-level spells (§5.1).

### fix - Wizard prepared count

`SpellcasterState.prepared_max()` returns `character_level` (20 at cap). Change to
`min(character_level, 6)`. See §5.2. Highest-value single change in this list.

### fix - full-caster slot table

`StandardSlotPool.SLOT_TABLE` grants 6th-9th level slots at levels 11+. Replace rows 11-20 per
§5.1. Rows 1-10 stay as they are.

### fix - Wild Heart talents grant active abilities

Wild Heart's Natural Sleeper and Wild Companion are talents that hand out active abilities, which
violates §2 (talents grant 0 actives) and §2.1 (subclass is the only new-ability moment). Animal
Form, the free subclass ability, is correct.

Options, in preference order:
1. Fold both into Animal Form as form-driven upgrades (keeps the flavor, removes two buttons).
2. Grandfather Wild Heart explicitly as "the deliberately complex subclass" and never repeat it.

### fix - races with two active abilities

§2 budgets one active per race. Currently over budget:
- **Goliath**: Large Form + Giant Ancestry
- **Aasimar**: Healing Hands + Celestial Revelation
- **Dragonborn**: Breath Weapon + Draconic Flight (level 5)

For each, one of the pair should become a passive or a triggered effect rather than a button. Races
already at budget and correct: Orc (Adrenaline Rush active, Relentless Endurance passive), Human,
Halfling, Dwarf.

### Not implemented - Tier 3 and Tier 4 content

`tier_unlocked()` handles tiers 3 and 4, but no class has any Tier 3/4 talents. Levels 13-20
currently accumulate points into empty pools.

Tier 3 additionally gates on `tier3_selected_class != -1`, a multiclass stub that does not exist.
Either build that gate or drop it to a plain level check like Tier 4 uses - do not leave a tier
gated on a feature that was never designed.

This is the largest single content gap between the shipped game and a level 20 cap.

---

## 9. Recommended order of work

1. **Ship the two caps** (§5.1, §5.2). Small, mechanical, immediately removes the worst §1
   violation.
2. **Resolve the audit items** in §8 - decide fix or grandfather for each, and write the decision
   down here. Deciding is the work; not all of them need code.
3. **Run the metric** (§1.2) on a Barbarian to the cap. Do not design Tier 3/4 content against a
   guess about pacing.
4. **Make Barbarian the reference class.** It is the most built-out (5 subclasses, full tier 1/2
   trees) and the strongest D&D anchor. Get it correct at L1-L20 against this doc first.
5. **Fill Tier 3 and Tier 4** using Barbarian as the template.
6. **Only then add classes.** With a reference class, a new class is one question ("does it have
   the same shape as Barbarian?") instead of fifteen design decisions.

Do not add new classes before step 4. There are already 8 playable and 7 with stat blocks; every
additional one widens the surface that steps 1-5 have to be applied to.

---

## 10. Checklist for a new class / subclass / race

- [ ] Exactly 1 active ability from the class baseline at level 1
- [ ] Exactly 1 active ability from the subclass, granted at selection, boss-gated
- [ ] At most 1 active ability from the race
- [ ] 0 talents that grant an active ability
- [ ] Each tier: ~2 passives + ~1 signature upgrade
- [ ] Each talent rank passes the §3.1 sanity test (skipping one rank does not break the run)
- [ ] Rest-gated charges unless "never needs to rest" is genuinely this class's identity (§6.2)
- [ ] Every D&D-derived mechanic keeps its D&D name and resource shape (§7)
- [ ] Caster: no spell above 5th level, prepared cap respected (§5)
- [ ] Sub-directory `CLAUDE.md` updated (root `CLAUDE.md`'s maintenance rule)
