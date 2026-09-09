# Class Progression Rules - the shared budget every class must fit

**Status:** RULE DOC (created 2026-09-02, revised 2026-09-09). Not a feature design - this is the
*constraint* every class/subclass/race/talent tree gets checked against, including the ones already
shipped. Some of the scaffolding it describes exists (`TalentTiers.TIER_LEVEL_RANGES`, per-level
talent points, `GameState.bonus_action_used`); what this doc adds is the *rule* those numbers serve,
plus the concrete caps and tier reshape that are still missing (§9).

Read this before designing a new class, a new subclass, a new race, or a new talent tree. When a
design fights the rule, the rule wins unless it is explicitly grandfathered in §9.

---

## 1. The one invariant

> **Progression almost never adds a button.**

That is the whole doc in one line. Everything below derives from it.

The game's identity is D&D flavored, but the *feel* target is Pixel Dungeon / Shattered PD: a turn
should take a couple of seconds, not a couple of minutes. SPD runs long and hands out talent points
constantly, and it still plays fast - because those points buy small modifiers, not new abilities.
The action bar looks roughly the same at the cap as at level 5.

That is the model. Long progression is fine. Wide progression is fine. **Growing the number of live
options on screen is not.**

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

### 2.1 By source

Abilities reach the player from six sources. Only three of them may hand out an active button.

| Source | Active abilities | Notes |
|---|---|---|
| Class baseline (L1) | **1** | Rage, Flurry of Blows, Hunter's Mark, Spark |
| Subclass (boss-gated) | **1** | The subclass *is* the new-ability moment |
| Race | **1** | Breath Weapon, Adrenaline Rush, Large Form, ... |
| Talents | **0** | Passives and upgrades only - see §3 |
| Spells | see §2.2 | Caster parallel track |
| Items | quickbar | Separate bar, separate Tab |

**Ceiling: 3 non-spell active abilities, at every level from 1 to the cap.** Level 20 does not mean
20 buttons. It means the same 3 buttons, deeper.

Passive class features (unarmored defense, resistances, proficiency growth, mastery slots, HP) are
unbudgeted - they change numbers, not decisions, so they cost nothing per turn. Spend progression
there freely.

### 2.2 Total live options, by class role

§2.1 alone is not a budget: it caps buttons per *source* but never the total, so a martial ends at 3
while a full caster runs past 8. The cap that actually matters is on the sum, and it is deliberately
**different per role** - a Wizard *should* have more decisions per turn than a Barbarian. That
asymmetry is the fantasy. It just has to be bounded.

| Role | Non-spell actives | Cantrips on bar | Leveled spells on bar | **Total scanned** |
|---|---|---|---|---|
| Martial (Barbarian, Fighter, Monk, Rampager) | 3 | - | - | **3** |
| Half-caster (Ranger) | 3 | - | 3 | **6** |
| Full caster (Wizard, Warlock) | 3 | 1 | 4 | **8** |

**A cantrip is the caster's basic attack, not an ability.** A martial's basic attack costs zero bar
slots (bump-to-attack). The caster's equivalent should be nearly free too, and the infrastructure
already exists: the **Special quick-cast slot** (`GameState.special_slot_spell_id`, Alt+click). One
cantrip lives there and does **not** count against the budget; a second may sit on the bar for a
situational element. Every further known cantrip lives in the Spellbook and is swapped at a long
rest, exactly like a prepared leveled spell.

The ability bar is 9 slots. Under this budget a full caster uses 8 at the cap and everyone else uses
fewer. **Never widen the bar past 9 to make room** - that is §1 in reverse. If a role needs more
than its row allows, cut something instead.

### 2.3 Corollary: the subclass is the only new-ability moment

Past level 1, choosing a subclass is the **only** thing in the entire game that grants a new active
ability. This is what makes the subclass choice feel like an event rather than one talent among
many, and it is what keeps talents free to be small (§3).

---

## 3. Talent rules

### 3.1 Magnitude, not count

**Do not limit how many talent points the player gets. Limit how big one rank is.**

This is the most important rule in the talent system, and it inverts the intuitive worry ("if the
player cannot max everything, every talent will feel weak"). SPD's talents are individually weak on
purpose and the system works, because identity comes from *concentrating* weak ranks in one
direction, not from any single rank being strong.

**Sanity test for one rank:** if the player skipped this rank by accident, would the run break? If
yes, the rank is too big. A rank should be barely perceptible alone and clearly felt at 3.

Because magnitude is what controls power, run length does not. That is why a level 20 cap is safe
here and would not be in D&D, and why extending to 30 later (§5) changes nothing about balance.

### 3.2 The tier shape

> **Tier = 5 levels = ~5 points = 4 talents x 3 ranks (12 capacity)**

(The final tier gets 4 points rather than 5 - see §4. Talent count and rank count are uniform across
every tier; only that one point count differs.)

This one line is the unit the whole system is built from. Fix the *shape*, not the level cap - see
§5.

**Why 4 talents and not 3.** Width produces choice; depth produces commitment. Putting rank 2 and 3
into the same talent is one decision made once and then repeated, whereas each additional talent
multiplies the distinct shapes a build can take. Counting actual distributions of points makes the
gap concrete:

| Shape | Capacity | Points | Distinct distributions |
|---|---|---|---|
| 3 talents x 3 ranks | 9 | 5 | 12 |
| 4 talents x 2 ranks (SPD-like) | 8 | 4 | 19 |
| **4 talents x 3 ranks** | **12** | **5** | **40** |

**Why 3 ranks and not 2.** Three ranks carry an arc (barely perceptible, felt, build-defining) that
two compress, which is what §3.1 needs. It is also what every shipped talent already uses
(`max_rank = 3` throughout), so keeping 3 makes adding a 4th talent per tier purely additive instead
of a rewrite of every existing rank table.

### 3.3 Talent types - one of each per tier

4 talents per tier is not just more choice, it is exactly the number that lets each tier offer one
talent of each *kind*, so the four options are qualitatively different rather than four different
numbers.

| Slot | Type | What it does | Cognitive cost |
|---|---|---|---|
| 1 | **A. Numeric passive** | +N to a stat, threshold, duration, or charge count | zero |
| 2 | **B. Attached passive** | silently modifies the signature ability ("Rage also ...") | zero |
| 3 | **C. Signature upgrade** | changes *how* the signature ability is used | low |
| 4 | **D. Automatic trigger** | fires on a condition with no button ("when an enemy flees, free attack") | **real** |

**Type D has no button but still costs attention** - the player has to remember it and play around
it. That is why it is capped at **one per tier**, and why a tier should never hold two.

**Type B is the answer to "generic talents do not express the character."** A passive expands
identity as long as it talks about *your* ability rather than floating free. Prefer B over A
whenever the class has a signature ability to attach to.

### 3.4 Capacity vs points

| Scope | Capacity | Points | Spent |
|---|---|---|---|
| One tier (T1-T3) | 12 | 5 | 42% |
| Final tier (T4) | 12 | 4 | 33% |
| Whole run (cap 20) | 48 | 19 | 40% |

The player maxes roughly one talent per tier and spreads the rest. Typical tier distributions:
`3/2/0/0`, `2/2/1/0`, `3/1/1/0`.

Not being able to max everything is the feature, not a problem to be tuned away. Keep spend near
40-50% whenever the cap or tier shape changes.

**Total talents to author: 16 per class** (4 tiers x 4), or 24 if the cap is later extended to 30.

---

## 4. Level 1-20 schedule

Level cap is **20**. **The player starts with zero talent points** (direct owner requirement) - the
first point arrives on the level-up into 2, so total points are **19**, not 20.

Target floor count is **~15**, bosses on 5 / 10 / 15, which keeps the existing floor-5 boss as the
Tier 2 gate.

| Tier | Levels | Points | Opens on |
|---|---|---|---|
| T1 | 1-6 | 5 | always |
| T2 | 7-11 | 5 | floor-5 boss kill (subclass choice) |
| T3 | 12-16 | 5 | level 12 |
| T4 | 17-20 | **4** | level 17 |

| Lvl | Chassis (every class) | Talent point | Caster track |
|---|---|---|---|
| 1 | signature active #1, baseline passives | none | 3 cantrips, 1st-level slots |
| 2-6 | passive feature around L3 | +1 T1 each (5 total) | 4 cantrips at L4, 3rd-level slots at L5 |
| 7 | **SUBCLASS: active #2** (boss-gated) | +1 T2 | - |
| 8-11 | passive feature around L8 | +1 T2 each (5 total w/ L7) | 5th-level slots at L9 (the cap), 5 cantrips at L10 |
| 12 | **Tier 3 opens** (specialization) | +1 T3 | slots widen only from here |
| 13-16 | passive feature around L13 | +1 T3 each (5 total w/ L12) | - |
| 17 | **Tier 4 opens** (capstone) | +1 T4 | - |
| 18-20 | capstone passive at L20 | +1 T4 each (4 total w/ L17) | - |

**19 talent points total.**

**Why T4 gets 4 and not 5:** 19 points do not divide evenly by 4, and granting a point at level 1 was
rejected. Putting the shortfall in the capstone tier is the least harmful place for it - T4 is where
the player spreads rather than maxes anyway, and talent *count* stays uniform at 4 x 3 in every tier,
which is what §3.2 actually fixes.

**Implementation note:** `GameState.gain_exp()` grants points on a level-up *transition*, so a tier's
point count is the number of transitions inside its range, not the range's length. T1's shipped range
`[1, 6]` already yields exactly 5 (transitions into 2, 3, 4, 5, 6) and needs **no change**. Only T2
and T4's boundaries move - see §9.

**Landmarks:** L1, L7 (subclass), L12 (Tier 3), L17 (Tier 4). Four deliberate spikes; every other
level is flat by design. People need orientation points, but not twenty of them.

---

## 5. Level cap is a knob, not an architecture

Fix the **tier shape** (§3.2), not the cap. The cap is then just how many tiers exist:

| Cap | Tiers | Points | Talents/class | Capacity | Spent |
|---|---|---|---|---|---|
| **20** | 4 | 19 | 16 | 48 | 40% |
| 30 | 6 | 29 | 24 | 72 | 40% |

The ratio is identical, so **the cap-20 design literally is the cap-30 design with the first four
tiers**. Extending later is additive: two more keys in `GameState.talent_points`, two more cases in
`TalentTiers.tier_unlocked()`, two more rows in `TIER_LEVEL_RANGES`, and 8 more talents per class.
No refactor.

**Current target is 20.** Reasons: it divides cleanly into 4 uniform tiers, level 20 is *the* D&D
cap (free brand consistency), and the flat-curve goal comes from rank magnitude (§3.1) rather than
level count.

**Before extending to 30, two things must be true:**

1. **Authoring throughput is known.** 16 -> 24 talents per class is +50% across every class and
   subclass tree. Author one class completely through all 4 tiers first and measure how long a tier
   actually takes. This, not any ratio, is the real constraint.
2. **The class has a 5th and 6th distinct direction.** Build diversity comes from the number of
   distinct *mechanical directions* a class has, not the number of talent entries. A Barbarian has
   maybe 4-5 (tank, damage, mobility, control, sustain). More talents make each direction *deeper*,
   not the class *broader*. If tiers 5 and 6 would just be more numbers, 20 is the better cap.

A third consideration, if 30 is ever taken seriously: SPD affords its long ladder because its power
curve runs through **item upgrades**, not levels. This game has that infrastructure
(`GameState.MAX_ATTUNED_ITEMS`, blacksmith, gold, weapon tiers) but **no `ITEM_POOL` entry sets
`requires_attunement` yet**, so the curve currently runs through class features. Filling attunement
with real magic items is worth doing on its own merits, and it is what would make a 30-level ladder
feel like progression instead of noise.

---

## 6. Caster track

Casters get a parallel spell track that does **not** draw from the talent budget. Three caps apply.

### 6.1 Slots grow wide, not tall

> **Maximum spell level is 5. Never 6th through 9th.**

Levels beyond the point where 5th-level slots arrive add *more low-level slots*, not new tiers. This
is the flat-curve rule applied to casters, and it has a nice side effect: Fireball stays impressive
for the entire run instead of becoming filler.

`StandardSlotPool.SLOT_TABLE` (`scripts/items/spell_slot_pool.gd`) currently runs the real D&D 2024
full-caster table all the way to 9th-level slots. **Rows 1-10 already match this rule and need no
change**; rows 11-20 do. Proposed replacement:

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

`HalfCasterSlotPool` and `PactSlotPool` already top out at 5th level and need no change.

### 6.2 Prepared count is capped by role, not by level

`SpellcasterState.prepared_max()` currently returns `character_level` for Wizard, i.e. **20 prepared
spells at level 20**. That is the single largest violation of §1 in the codebase.

> **Full caster: 5. Half-caster: 3.**

These are the §2.2 numbers, not a separate budget - a prepared spell is only castable from the
ability bar, so prepared count *is* bar occupancy. Ranger's existing half-caster formula
(`max(1, WIS mod + level/2)`) reaches 3 quickly and should simply be clamped there.

Known spells stay uncapped - the spellbook can grow as large as it likes. What is capped is how many
are live at once. Swapping happens at a long rest, which is exactly where a slow, considered
decision belongs.

### 6.3 Cantrips are the basic attack

`SpellcasterState.cantrip_max()` (3/4/5 known at levels 1/4/10) stays as the *known* cap. What
changes is how many are **live**: one in the Special quick-cast slot (free, it is the basic attack)
plus at most one on the ability bar. The rest are swapped at a long rest like prepared spells.

Without this, a Wizard at L10 fills 8 of 9 bar slots with 3 actives + 5 cantrips before placing a
single leveled spell, and the bar - not `prepared_max()` - becomes the real constraint on the turn.

---

## 7. Resource economy

### 7.1 There is one economy, not two

Spell slots, `rage_uses_max`, `monk_focus_points`, `hunters_mark_uses_remaining`, race charges - all
the same mechanic: **rest-gated charges**. The only difference is whether the pool has a level
dimension.

Cooldowns are not a second economy. They are a different *axis of tension*:

| | Where tension lives | What it asks the player |
|---|---|---|
| Rest-gated charges | between fights (attrition) | "Do I spend this now or save it?" |
| Cooldowns | inside one fight (rotation) | "What order do I press these in?" |

A roguelike lives on attrition. The long rest already costs 100 combined `food_value` and 20 turns,
which makes it genuinely scarce - so the attrition layer is real and worth protecting.

> **Default: rest-gated charges. Cooldowns are a deliberate class identity, not an alternative
> system.**

### 7.2 Cooldown classes are a minority

Hybrid and Rampager run on cooldown + nova (Essence / Fury) on purpose. Their fantasy is "never
needs to rest", which is a legitimate and sellable class pitch, and it is why they sit off the D&D
rest model entirely (`Stats.caster` stays null, no tier plumbing).

This must stay a minority - roughly 2 of N classes. If every martial class moved to cooldowns, the
attrition layer disappears and the game stops being a roguelike. When a new class is proposed on
cooldowns, the question is "is 'this class never rests' actually its identity?" If no, it uses
charges.

---

## 8. D&D fidelity test

The game is D&D 2024 flavored, but turn economy, reactions, movement, and conditions already
diverge. The brand value is not in the numbers.

> **Names and resource shapes come from D&D. Numbers and triggers are ours.**

Rage is called Rage, recharges on a long rest, and grants damage plus resistance - a D&D player
recognizes it instantly. What exactly Bruiser rank 3 does to it is entirely ours to invent.

Practical test: **would a D&D player recognize this by name and expect roughly this shape?** If yes,
keep the name and approximate the shape. If the mechanic has no engine support here (reactions
beyond OAs, ritual components, ...), invent freely - nobody is checking the PHB against this game,
and the parts that already diverge have cost nothing.

---

## 9. Current state vs this rule

Audit of what is shipped. **fix** = violates the rule. **grandfathered** = accepted exception that
must not become precedent.

### Already conforms

- `GameState.gain_exp()` grants 1 talent point per level into the level's tier pool.
- `GameState.bonus_action_used` - the action-economy half of §1.1 is already solved.
- Subclass grants exactly one free ability (Frenzy / Limit Break / Animal Form / Zealot Strike) and
  its Tier 2 talents only upgrade it - §2.3 and §3.3 working correctly. **Reference shape.**
- Every shipped talent uses `max_rank = 3` (§3.2).
- Barbarian Tier 1 (Psycho / Bruiser / Battlefield Expert): passive-shaped, no new buttons.
- `HalfCasterSlotPool` / `PactSlotPool` already cap at 5th-level spells (§6.1).

### fix - tier level ranges are not uniform

`TalentTiers.TIER_LEVEL_RANGES` is `{1:[1,6], 2:[7,12], 3:[13,17], 4:[18,20]}`, which yields
**5/6/5/3** points (count the level-up transitions inside each range, not the range length). T1 is
already correct; T2 has one too many and T4 two too few.

Change to `{1:[1,6], 2:[7,11], 3:[12,16], 4:[17,20]}` -> **5/5/5/4**, per §4. Two boundaries move, T1
and T3's talent content are unaffected, and no point is granted at level 1.

### fix - level cap is not enforced

`Stats.gain_exp()`'s `while experience >= exp_for_level(character_level)` loop has no upper bound,
so a character can reach level 21+, where `tier_for_level()` returns 0 and `gain_exp()`'s
`if point_tier > 0` guard **silently discards the talent point**. Clamp at 20.

### fix - Tier 3 is unreachable

`TalentTiers.tier_unlocked(3)` requires `tier3_selected_class != -1`, a multiclass stub that does
not exist anywhere. Tier 3 talents would be unreachable even once authored. Change to a plain level
check (like Tier 4) or a floor-10 boss gate (consistent with Tier 2) - do not leave a tier gated on
a feature that was never designed.

### fix - Wizard prepared count

`SpellcasterState.prepared_max()` returns `character_level` (20 at cap). Change to 5 for full
casters, clamp Ranger's formula at 3. See §6.2. Highest-value single change in this list.

### fix - full-caster slot table

`StandardSlotPool.SLOT_TABLE` grants 6th-9th level slots at levels 11+. Replace rows 11-20 per
§6.1. Rows 1-10 stay.

### fix - cantrips occupy the bar

No live-cantrip cap exists; all 5 known cantrips can sit on the bar. Implement §6.3.

### fix - Wild Heart talents grant active abilities

Natural Sleeper and Wild Companion are talents that hand out active abilities, violating §2.1
(talents grant 0) and §2.3 (subclass is the only new-ability moment). Animal Form, the free subclass
ability, is correct.

Options in preference order:
1. Fold both into Animal Form as form-driven upgrades (keeps the flavor, removes two buttons).
2. Grandfather Wild Heart explicitly as "the deliberately complex subclass" and never repeat it.

### fix - races with two active abilities

§2.1 budgets one active per race. Over budget: **Goliath** (Large Form + Giant Ancestry),
**Aasimar** (Healing Hands + Celestial Revelation), **Dragonborn** (Breath Weapon + Draconic
Flight). For each, one of the pair should become a passive or a triggered effect. Already correct:
Orc (Adrenaline Rush active, Relentless Endurance passive), Human, Halfling, Dwarf.

### Content gap - tiers need a 4th talent, and T3/T4 are empty

Every existing tier holds 3 talents and needs a 4th (§3.2): +1 for Barbarian T1, +1 for each of the
5 subclass T2 trees, and likewise for Ranger/Monk/other trees. Existing talents do not change.

Tiers 3 and 4 have **no talents at all** for any class - 8 talents per class from scratch. This is
the largest single gap between the shipped game and a level 20 cap.

### Open - XP curve is untuned against the target

`Stats.exp_for_level(lv) = lv * 10` is linear; cumulative cost to reach L20 is 1900 XP. Enemy `exp`
values run 3-12 (floors 1-3) up to 25-40 (floors 8-10), bosses 100-200. Rough estimate: today's 10
floors yield ~1000-1500 XP, landing a run around L13-15 rather than the cap. This is an **estimate,
not a measurement** (spawns are CR-budgeted, so per-floor counts vary) - measure it per §1.2 before
retuning, and tune the curve against the final floor count, not the reverse.

---

## 10. Recommended order of work

1. **Ship the mechanical fixes**: level cap clamp, T2/T4 tier boundaries, Tier 3 gate,
   `prepared_max()`, slot table rows 11-20, live-cantrip cap. All small, no design decisions left.
2. **Resolve the judgement calls** in §9 - Wild Heart and the three over-budget races. Decide fix or
   grandfather and record the decision here. Deciding is the work; not all need code.
3. **Run the metric** (§1.2) on a Barbarian to the cap, and record the actual end level for the XP
   curve. Do not design Tier 3/4 content against a guess about pacing.
4. **Make Barbarian the reference class.** Most built-out (5 subclasses, full T1/T2 trees) and the
   strongest D&D anchor. Get it correct at L1-L20 against this doc first: add the 4th talent to
   existing tiers, then author T3 and T4.
5. **Then decide cap 20 vs 30** using §5's two preconditions, now that throughput is known.
6. **Only then add classes.** With a reference class, a new class is one question ("does it have the
   same shape as Barbarian?") instead of fifteen design decisions.

Do not add new classes before step 4. There are already 8 playable and 7 with stat blocks; each
additional one widens the surface steps 1-5 must be applied to.

---

## 11. Checklist for a new class / subclass / race

- [ ] Exactly 1 active ability from the class baseline at level 1
- [ ] Exactly 1 active ability from the subclass, granted at selection, boss-gated
- [ ] At most 1 active ability from the race
- [ ] 0 talents that grant an active ability
- [ ] Total live options within the role's §2.2 row (martial 3 / half-caster 6 / full caster 8)
- [ ] Each tier: 4 talents x 3 ranks, one each of types A/B/C/D (§3.3), at most one type D
- [ ] No talent point granted at level 1 (§4)
- [ ] Each talent rank passes the §3.1 sanity test (skipping one rank does not break the run)
- [ ] Rest-gated charges unless "never needs to rest" is genuinely this class's identity (§7.2)
- [ ] Every D&D-derived mechanic keeps its D&D name and resource shape (§8)
- [ ] Caster: no spell above 5th level, prepared cap 5/3, live cantrips capped (§6)
- [ ] Sub-directory `CLAUDE.md` updated (root `CLAUDE.md`'s maintenance rule)
