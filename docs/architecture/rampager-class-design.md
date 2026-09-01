# Rampager Class - Momentum + Collision Design

**Status:** DESIGN + STATS SCAFFOLD (2026-09-01). "Our version of the Barbarian" - same reckless
melee-bruiser fantasy, but OFF the D&D per-rest model (no `rage_uses_max`, no long-rest gating),
exactly like the Hybrid is off the spell/rest model (`docs/architecture/hybrid-class-design.md`).
This doc is the analog of the Hybrid one: it defines the systems + the class skeleton; ability
numbers are first-pass and the owner tunes them.

Shipped this pass: `Stats.CharacterClass.RAMPAGER`, `CLASS_ROLE`, `apply_class_defaults()` branch,
d12 HD entries, the `momentum` field + `rampager_tier()` + serialization. NOT yet built:
`class_select.gd` card, starting gear, the Momentum build/decay turn hooks, the HUD gauge,
`RampagerAbilityDb` / `RampagerEffects` / `PlayerRampager`, base talents, subclass.

Created 2026-09-01.

---

## 1. Purpose and scope

A **second testbed for a non-Vancian economy**, deliberately different from both the D&D rest model
AND the Hybrid's cooldown+Essence model:

1. **Momentum** - a 0-100 combat gauge (SPD Berserker's rage-bar lineage) that *builds* from dealing
   and taking melee damage and *bleeds* when you stop fighting. It is the whole offensive economy -
   there is no per-rest resource on this class at all.
2. **Passive thresholds** - crossing 25 / 50 / 75 / 100 Momentum grants escalating combat perks
   with zero activation. The class gets stronger the longer a fight stays hot.
3. **Collision combos** - abilities that shove/hurl/slam enemies into walls, each other, and
   hazards, leaning on the forced-movement + wall-slam sim the game **already** has
   (`DungeonFloor.resolve_push()` / `force_move_entity()`'s wall-slam damage / `ignite_flammable()`
   for props / chasm-removal). This is the Rampager's equivalent of the Hybrid's surface reactions:
   reuse an existing simulation instead of building a new one.

Walled off like the Hybrid: `Stats.caster` stays `null`, no spell system, its own gauge instead of
`rage_uses_max`. Reuses the shared talent + `subclass_choice_required` infrastructure as-is (see
sections 6-7).

**Explicitly NOT in scope for the first pass:** enemy Rampagers, Momentum-fueled reactions,
rubble/terrain-destruction beyond what `resolve_push()` already does, multiclass, respec.

---

## 2. Resource model - Momentum

### 2.1 The gauge

**`Stats` fields:**

| Field | Type | Meaning |
|---|---|---|
| `momentum` | int | current gauge, `0..momentum_cap` (serialized, same as `hybrid_essence`) |
| `momentum_cap` | int (computed) | `100` at L1, `125` at L6, `150` at L12 - a computed property off `character_level`, never cached, mirrors `hybrid_essence_max` |
| `rampage_turns_remaining` | int | Rampage burst window countdown (serialized) |

`Stats.rampager_tier() -> int` (computed live): `0` below 25, `1` at 25-49, `2` at 50-74, `3` at
75-99, `4` at `>= momentum_cap` (Rampage-ready). Every threshold perk and the HUD read this.

### 2.2 Build

All in `player.gd` (needs combat context the `Stats` object doesn't have). Per real player turn:

- **+8** when you land a melee attack (once per turn regardless of how many swings connect).
- **+6** each time you take damage (`GameState.take_damage_raw()`'s tail, physical or not).
- **+4** on a kill by your hand.
- **+3** when you charge through / destroy a barrel or unlocked door (an Overrun/Warpath dash).
- **x1.5** on every one of the above while **Bloodied** (`current_hp <= max_hp / 2`) - the
  low-HP-payoff hook, baked into the L1 passive (section 5).

Numbers are first-pass; tune in one place (`PlayerRampager` constants).

### 2.3 Decay

Also `player.gd`, at the end of each real player turn (`_on_turn_ending()`, same hook the Hybrid
cooldown tick uses):

- **-0** if you dealt or took damage this turn (the turn kept the fight hot).
- **-6** if you didn't, and an enemy is visible.
- **-15** if you didn't and no enemy is visible (out of combat bleeds fast - Momentum is not a
  between-fights bank).
- Never decays while `rampage_turns_remaining > 0`.

`RewindManager` snapshots `momentum` / `rampage_turns_remaining` via the normal `Stats`
`duplicate(true)` capture - no rewind change needed (same as `hybrid_essence`).

### 2.4 Passive thresholds (no activation)

| Tier | Momentum | Perk (cumulative) |
|---|---|---|
| 1 Heated | >= 25 | +1 melee damage; footstep dust VFX |
| 2 Furious | >= 50 | melee crits on 19-20; +1 weapon damage die |
| 3 Unbridled | >= 75 | your melee attacks can't be rolled with Disadvantage; resist physical 50% (the Rage DR, ported to a threshold) |
| 4 Rampage-ready | full | the Rampage activation lights up (section 2.5) |

Tier 2's crit-range widening and Tier 3's Disadvantage-immunity + physical DR are the Rampager's
whole "Rage" - there is no separate Rage ability, exactly as the Hybrid has no separate "cast a
spell" button.

### 2.5 Rampage (the spend, baked-in baseline)

At tier 4, a baked-in **Rampage** ability (granted flat at L1, greyed until the gauge is full,
same as Frenzy's gate) becomes usable: **consumes the entire gauge** and sets
`rampage_turns_remaining = 3`. During Rampage:

- one **extra melee attack** per turn (reuses the Extra Attack path).
- immune to Frightened and Prone; auto-stands for free.
- Momentum is **locked at 0** and does not build or decay.
- when it ends, normal build/decay resumes from 0.

This is the only thing that *spends* Momentum by default. Section 5 abilities that cost Momentum
are the picked ones.

### 2.6 Coexistence with the rest system

HP / potions / hit dice / short+long rest all work unchanged, for **healing and status cleanup
only**. `long_rest()` does NOT touch `momentum` (it's a live combat gauge, not a per-rest
resource - starting a long rest with a full gauge and losing it is correct, and it'll be empty
by the time the rest finishes anyway thanks to out-of-combat decay). Attrition tension sits on
HP + potions, same as the Hybrid.

---

## 3. Collision system (the DOS2-style hook)

### 3.1 Existing sim reused as-is

- `DungeonFloor.resolve_push(enemy, direction)` - the Heavy Crossbow / World Tree push resolver:
  WALL -> 1d4 Bludgeoning + no move; trap tile -> move + `trigger_trap()`; CHASM -> enemy removed
  (counts as a kill, boss loot deferred to next floor). **Already does everything the Rampager
  needs for "shove into terrain".**
- `DungeonFloor.force_move_entity()` + its wall-slam damage.
- `DungeonFloor.ignite_flammable()` / barrel + door destruction.
- `Enemy.apply_status("prone", 1)` - the real Prone condition (Maul's Topple already uses it).

### 3.2 New: collision-into-a-creature

The one genuinely new resolver, `RampagerEffects._resolve_collision(a, b_tile, dungeon_floor)`:
when a shoved/hurled enemy's path is blocked by **another enemy**, both take a Bludgeoning
instance (scaled by the throw distance / thrower's tier) and both are knocked Prone. If the far
tile is a WALL, it's the existing wall-slam plus Prone. Mirrors `resolve_push()`'s "non-generic
per-tile outcome" shape - a dedicated resolver, not a generic helper.

### 3.3 Reaction matrix (Phase 1)

| Trigger | Condition | Result |
|---|---|---|
| Shove / Hurl ends on a WALL | - | wall-slam Bludgeoning (existing) + Prone |
| Shove / Hurl blocked by an enemy | - | `_resolve_collision()` - both hit + Prone |
| Shove / Hurl ends on a trap tile | - | existing `resolve_push()` trap path |
| Shove / Hurl ends on a CHASM | - | existing `resolve_push()` chasm-removal |
| Dash (Overrun / Warpath) crosses a barrel / unlocked door | - | prop destroyed, **+3 Momentum** |
| Any collision while the Rampager is tier 3+ | - | +50% collision Bludgeoning |

**Phase 2+ (deferred):** rubble tiles (a slammed WALL becomes difficult terrain), knocking
enemies off ledges you're standing next to, chain collisions.

---

## 4. The Rampager class

### 4.1 D&D-style base stat block

`Stats.CharacterClass.RAMPAGER` (new enum entry, appended last). `apply_class_defaults()` branch:

| Field | Value |
|---|---|
| Ability scores | STR 16, CON 15, DEX 12, WIS 10, INT 8, CHA 8 (point-buy overrides) |
| Hit die | d12 (`point_buy_hit_die_base()` / `hp_per_level_breakdown()` avg 7 - identical to Barbarian) |
| `check_prof_*` | STR + CON |
| Weapons | Simple + Martial (`proficient_simple_weapons` + `proficient_martial_weapons`) |
| Armor | Light + Medium + Shields (no Heavy) - same as Barbarian |
| `Stats.CLASS_ROLE` | `"MARTIAL"` (so nothing grants a `caster`) |
| `Stats.caster` | stays `null` |
| `Stats.mastery_cap()` | keep the Barbarian value (Rampager *does* swing real weapons, unlike the Hybrid) - the weapon-mastery picker stays |
| unarmored defense | **none** - Rampager wears Medium armor + Shield, it's not an unarmored-defense class |

**Starting gear** (`GameState._give_rampager_starting_items()`): mirror the Barbarian's current
starter - a Spear (Main Hand) + 2 thrown Handaxes (`markdowns/barbarian_base.md` option (a)) + no
armor (buy/find it). Add `equipment_changed.emit()` at the end.

### 4.2 Power math

Rampage / ability saves use `Stats.rampager_power_dc = 8 + proficiency_bonus + STR modifier` and
`rampager_attack_bonus = proficiency_bonus + STR modifier` (computed live, mirrors
`hybrid_power_dc` / `monk_save_dc`). Collision damage scales off `rampager_tier()` and throw
distance, not a DC.

### 4.3 Progression skeleton (mirrors the revised Hybrid, section 4.3 of that doc)

| Level | Grant |
|---|---|
| 1 | 1 passive (**Bloodrush** - the Momentum reminder + Bloodied x1.5 build) + 1 activation (pick-1-of-3) + the baked-in **Rampage** baseline (greyed until full) |
| 2 | base talent point #1 |
| 3 | activation #2 (pick-1-of-3) |
| 4 | base talent point #2 |
| 5 | **subclass** (boss-gated) - grants its signature activation free, in place of this level's activation |
| 6 | Momentum cap 100 -> 125 + base talent point #3 |
| 7 | activation #3 |
| 8+ | activations on odd levels, base talent points on even levels |

Same `HybridAbilityDb`-style `"kind"` (`"passive"` / `"activation"`) tagging; same auto-grant-by-
`min_level` first pass, then a `spell_learn_picker.gd`-backed pick-1-of-3 as the second slice.

### 4.4 Onboarding + growth

**Custom path:** class select -> point buy -> background ASI -> race select -> character summary
-> **Rampager starter pick** -> game starts. Reuse `spell_learn_picker.gd`'s card layout over the
`kind == "activation"`, `min_level <= 1` pool. Commit via `GameState.choose_rampager_ability(id)`.

**Level-up growth:** odd levels from 3 up (5 is the subclass), `gain_exp()` sets
`rampager_ability_pick_pending` + rolls up to 3 activation candidates. Save/load: serialize
`known_rampager_ability_ids: Array[String]`, rebuild in `_rebuild_rampager_ability_bar()`.

**Premade hero:** add a Rampager premade with a fixed `"rampager_ability": "<id>"` key.

---

## 5. Ability kit (`RampagerAbilityDb`, first-pass - owner tunes)

Same data-dict shape as `HybridAbilityDb.DEFS` (`id`, `name`, `description`, `icon`, `min_level`,
`kind`, `power_type`, `cooldown` / `momentum_cost`, `target`, `range`, `shape_size`, `resolution`,
`dice`, `damage_type`, `effect`). `power_type` is `"cooldown"` xor `"momentum"` xor `"passive"` -
the Rampager's spend-resource is **Momentum itself** (not a separate Essence pool), so a
`"momentum"` ability both *needs* `momentum >= cost` and *subtracts* it on use.

| id | kind | min_lvl | power | effect |
|---|---|---|---|---|
| `rmp_bloodrush` | passive | 1 | passive | Reminder entry. While Bloodied, all Momentum gains are x1.5. |
| `rmp_overrun` | activation | 1 | cooldown 2 | Charge in a straight line up to 4 tiles; ram the first enemy hit - melee attack + shove 1 tile (`resolve_push`, wall-slam / collision / trap / chasm all apply). Destroys barrels/doors crossed (+3 Momentum each). |
| `rmp_hurl` | activation | 3 | momentum 25 | Grab an adjacent enemy and throw them up to 3 tiles at a target tile - `_resolve_collision()` on whatever they hit (wall / enemy / trap / chasm), both ends knocked Prone. |
| `rmp_seismic_slam` | activation | 5 | momentum 40 | Smash the ground: radius-1 Bludgeoning (STR save or Prone) around you; pops adjacent barrels/doors. |
| `rmp_warpath` | activation | 7 | cooldown 3 | Move up to 3 tiles; make one free melee attack against **every** enemy you end a step adjacent to (reuses the Cleave attack-resolution pattern). |
| `rmp_rampage` | (baseline) | 1 | full gauge | The section 2.5 burst - granted flat, not picked. |

**Design guidance (same spirit as the Hybrid doc's section 5):**
- COOLDOWN abilities: your every-turn tools (2-3 turn cooldowns), most of the picked kit.
- MOMENTUM abilities: the finishers - they trade your accumulated gauge for a big collision play,
  so using one drops you back down a threshold tier. Losing a fight should feel like "I dumped my
  Momentum on a Hurl and now I'm tier 0 and low HP".
- Lean on the collision matrix: an ability that just deals flat damage and doesn't move anyone is
  a wasted slot on this class.
- PASSIVE entries are discoverability parity (like Monk's Unarmored Defense bar entry).

---

## 6. Base talents (`RampagerTalentDb`) - general, never bolted to one ability

Same rule as the Hybrid (section 4.5 there): the base talents are **general**, about the Momentum
economy + collisions, never tied to a specific picked activation (which is a random draw). Flat
list, `tier = 1`, `class_id = "RAMPAGER"`, pick 1 per even level; a talent with `ranks` re-picks
to rank up. First-pass pool (numbers untuned):

| id | effect |
|---|---|
| `rmp_adrenaline` | Momentum decays half as fast (R2: doesn't decay at all while an enemy is visible). |
| `rmp_concussive` | Collision / wall-slam Bludgeoning +1d6 and always knocks Prone (R2 +2d6). |
| `rmp_thick_hide` | The tier-3 physical DR kicks in one tier early (from >= 50). R2: from >= 25. |
| `rmp_headlong` | First melee attack each turn after moving 2+ tiles has Advantage. |
| `rmp_unstoppable` | Ignore difficult terrain; your movement never provokes Opportunity Attacks. |
| `rmp_last_stand` | Once per floor, dropping to 0 Momentum on purpose (a bar-click) heals `proficiency_bonus x character_level` HP. |
| `rmp_hardened` | +2 max HP per level (R1-R3) - the boring-but-safe pick. |

**Implementation:** `scripts/items/rampager_talent_db.gd` (data dicts, no `.tres`);
`_apply_talent_rank()` gains a `RAMPAGER` dispatch branch; `_class_talents` /
`_build_class_talents()` gains a `RAMPAGER` case; `gain_exp()` grants `talent_points[1]` on even
levels for a Rampager. Save/load: replayed through the existing talent-replay path, no new
serialization.

---

## 7. Subclass (level 5, boss-gated) - reuse the Barbarian mechanism

`TIER2_GATING_BOSS_ID` kill -> `subclass_choice_required` -> `subclass_select.gd` ->
`choose_subclass()` -> `unlock_tier2()` -> `_setup_tier2_for_active_subclass()`. Tier-2 points
earned levels 7-12 pend until that kill.

**2 leanings** (not five):
- **Juggernaut** - terrain / prop destruction. Signature activation **Demolish**: charge through
  walls, props, and enemies in a straight line, destroying everything in the path and gaining
  Momentum per object smashed. Tier-2 talents: longer charge, slammed walls leave rubble
  (difficult terrain), Demolish knocks a wide cone Prone.
- **Feral** - low-HP payoff (distinct from Barbarian's "Berserker" name). Signature activation
  **Death Wish**: for 3 turns you take +50% damage but every threshold counts as +1 tier and every
  Momentum gain doubles. Tier-2 talents: Death Wish also heals on a kill, longer duration, can't
  drop below 1 HP during it.

Each grants **one free signature activation** at selection (like Frenzy / Limit Break - see
`TIER2_BASE_ABILITY_ID`); the 3 tier-2 talents only upgrade it. Since this is a per-class subclass
set, `TIER2_SUBCLASSES` / `subclass_select.gd` must be made class-aware (today hardcoded to the 5
Barbarian names) - a shared prerequisite with the Hybrid's own subclass slice.

---

## 8. Codebase integration checklist

1. `scripts/entities/stats.gd` - `CharacterClass.RAMPAGER`, `CLASS_ROLE["RAMPAGER"] = "MARTIAL"`,
   `apply_class_defaults()` branch, `momentum` / `momentum_cap` / `rampage_turns_remaining`,
   `rampager_tier()`, `rampager_power_dc` / `rampager_attack_bonus`, d12 entries in
   `point_buy_hit_die_base()` / `hp_per_level_breakdown()` (avg 7), `to_dict()`/`from_dict()`:
   `momentum`, `rampage_turns_remaining`, `known_rampager_ability_ids`. **(DONE this pass except
   the ability-ids array.)**
2. `GameState` - `_give_rampager_starting_items()`, `_grant_rampager_abilities_for_level()`,
   `choose_/learn_rampager_ability()`, `_rebuild_rampager_ability_bar()`,
   `rampager_ability_pick_pending` + growth roll in `gain_exp()`, `talent_points[1]` grant on even
   levels, `is_ability_usable()` / `ability_unusable_reason()` branch (`"Momentum N"` /
   `"Not Rampage-ready"`).
3. `scripts/items/rampager_ability_db.gd` - static factory (owner fills the list).
4. `scripts/items/rampager_talent_db.gd` - static factory (section 6).
5. `scripts/entities/rampager_effects.gd` - ability resolvers + `_resolve_collision()`, each owning
   its own `TurnManager.begin_player_action()` ... `player._handle_post_attack_turn()` envelope
   (copy `HybridEffects`'s structure).
6. `scripts/entities/player_rampager.gd` - `_rampager` composition child on `Player` (copy
   `PlayerHybrid`): targeting / arming for the dash + hurl abilities, the Momentum build hooks
   (melee-hit / take-damage / kill), the decay in `_on_turn_ending()`, Rampage window countdown +
   Extra Attack grant, rewind fields.
7. `player.gd` - `_use_ability_slot()` dispatch for `RampagerAbilityDb.is_rampager_ability(id)`;
   threshold perks in the combat-roll path (crit range, Disadvantage immunity, physical DR - fold
   into the existing Barbarian Rage checks in `CombatMath` / `GameState.take_damage_raw()`, gated
   on `rampager_tier()` instead of `is_raging`).
8. `hud.gd` - a Momentum gauge on `$StatsPanel` (a horizontal fill bar with tier ticks at
   25/50/75, glows at full) - Rampager-only, same "resource gauge not status icon" call the
   Essence pip row got. Cooldown darken+number on the bar (already generic from the Hybrid pass).
9. `RewindManager` - nothing (momentum rides the `Stats` `duplicate(true)` capture).
10. `scripts/ui/class_select.gd` - Rampager card (`"rampager": true` on the D&D roster, OR its own
    roster toggle entry - owner's call). `character_select.gd` premade (optional).
11. Sprites: `sprites/characters/classes/Rampager/` (idle/run; no hit art -> `has_real_hit_art`
    stays `["Wizard","Monk"]`, plays a static idle frame on attack, same as Barbarian/Hybrid).
    `player.gd._setup_animations()` maps `RAMPAGER -> "Rampager"`.
12. Subclass: make `TIER2_SUBCLASSES` / `subclass_select.gd` class-aware (shared with Hybrid);
    `_setup_tier2_for_active_subclass()` `Juggernaut` / `Feral` cases; `TIER2_BASE_ABILITY_ID`
    entries.
13. Docs: `scripts/entities/CLAUDE.md` "Rampager class" section, `scripts/items/CLAUDE.md` ability
    notes, root `CLAUDE.md` pointer lines. Delete this doc once fully shipped and the sub-docs
    cover it (repo doc-cleanup rule).

---

## 9. Deferred / out of scope for the first pass

- Rubble tiles / real terrain destruction beyond `resolve_push()`.
- Enemy Rampagers / Momentum-fueled reactions.
- Chain collisions, knock-off-ledge.
- Multiclass, respec.
- Porting the Momentum gauge to other classes - decide only after this one plays well.
- Momentum-on-crit, per-ability cost scaling by level - add only if an ability actually needs it.
