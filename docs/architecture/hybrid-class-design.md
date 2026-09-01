# Hybrid Class - Cooldown + Essence + Surface-Combo Design

**Status:** FIRST PASS IMPLEMENTED (2026-08-31); progression model REVISED 2026-09-01 (sections
4.3-4.6 below - talents + subclass are back in, the "ability bar is the whole kit" first pass was
too thin). Working title "Hybrid" (rename freely). Shipped so far: the class is selectable (Custom
path), the cooldown + Essence economy, the `wet`/`shocked` element tags + electrified-water spread,
and the 5 seed abilities (Spark / Tide / Grounded / Arc / Emberstep). As of 2026-09-01 those 5 are
retagged to the new cadence (`HybridAbilityDb` `"kind"` field + retuned `min_level`s: Grounded
passive + Spark activation at L1, Tide L3, Arc L5, Emberstep L7) and still auto-grant by level.
NOT yet done: the pick-1-of-3 growth picker (section 4.4), the **base-talent list (section 4.5)**,
the **subclass (section 4.6)**, the Essence Shard item, a premade hero, real ability art, and
Phase-2 surfaces (section 8). `scripts/entities/CLAUDE.md`'s "Hybrid class" section is the
maintenance reference.

**Recommended build order** (section 4.3+): (1) ship the level cadence - done as data, picker
still pending; (2) add the flat base-talent list; (3) add the subclass last. Don't build tier
plumbing the Hybrid doesn't need - it reuses the existing `talent_investments` / `talent_points`
/ `subclass_choice_required` infrastructure as-is.
**Author's note:** this doc defines the *systems and the class skeleton*. The ability list
itself is deliberately left for the owner to fill in - see section 5 (authoring template)
and section 6 (seed examples showing each archetype).

Created 2026-08-31.

---

## 1. Purpose and scope

This is a **testbed for a different resource economy** than the rest of the game. Every
existing class runs on D&D's Vancian / per-rest model (spell slots, `rage_uses_max`,
`monk_focus_points`, `X/long rest` charges). The Hybrid instead runs on:

1. **Cooldowns** - bread-and-butter abilities that always come back after N turns.
2. **Essence** - a small, slowly-refilling nova pool for the big abilities.
3. **Surface combos** - abilities that lay down / detonate elemental surfaces (DOS2-style),
   leaning on the fire/water/grass simulation the game *already* has.

The Hybrid is walled off from the spell system (`Stats.caster` stays `null`), the talent-tier
system, and the per-rest economy. If the model plays well on this one class we consider porting
it; if it doesn't, nothing else is touched. See the design conversation this came from for the
"we over-scoped vs Pixel Dungeon" framing.

**Explicitly NOT in scope for the first pass** (section 8 has the full list): oil / ice / poison-
cloud / steam surfaces, generalised obscurement zones, enemy Hybrids, multiclass.

---

## 2. Resource model

### 2.1 Cooldowns

**`Ability` schema change** (`scripts/items/ability.gd`) - two new fields:

| Field | Type | Meaning |
|---|---|---|
| `cooldown_max` | int | turns between uses; `0` = not a cooldown ability (unchanged default) |
| `cooldown_remaining` | int | live counter; `0` = ready |

An ability is **either** `cooldown_max > 0` **or** `essence_cost > 0` **or** neither (passive) -
never two at once. This mirrors the enemy stat-block rule that combining `cooldown` / `uses_max` /
`recharge` on one ability is an authoring error (`scripts/entities/CLAUDE.md`).

**Tick** - in `player.gd._on_turn_ending()` (fires exactly once per real, non-reverted player
turn, **right before enemies act** - so the countdown visibly moves on the player's own turn,
never during the enemy phase): for every `Ability` on `GameState.player_ability_bar` with
`cooldown_remaining > 0` **that is not in `Player._hybrid_cd_skip_this_turn`**, decrement by 1,
and log "<name> is ready." at 0. The skip list holds every ability activated this turn
(populated by `PlayerHybrid._pay()`, cleared in `_on_turn_started()`) so an ability never burns a
turn of its own cooldown on the turn it's cast. Net: `cooldown N` = unavailable for your next N
turns, usable on the (N+1)th. A free action / revert never ticks a cooldown.

**Set** - when an ability resolves, its dispatch case in `player.gd._use_ability_slot()` (or the
ability's own resolver, matching whatever "spend only on confirmed use" convention that ability
follows) sets `cooldown_remaining = cooldown_max`. **Skipped entirely while `GameState.invincible`**
(God Mode), per the "Invincible mode" rule in root `CLAUDE.md`.

**Gate** - `GameState.is_ability_usable(ab)` returns false while `cooldown_remaining > 0`;
`GameState.ability_unusable_reason(ab)` returns `"On cooldown (N)"`. Same shape as the existing
`"No Rage"` / `"Not Engaged"` reasons.

**HUD** - `hud.gd._refresh_ability_bar()`: while `cooldown_remaining > 0`, darken the slot and
draw the number centred (reuse the use-count-badge label; a radial sweep is a nice-to-have, not
required). Refresh chokepoints: `TurnManager.player_turn_started`, `GameState.ability_bar_changed`.

**Rewind** - `RewindManager` must snapshot each bar ability's `cooldown_remaining` (add to the
per-ability capture alongside `uses_remaining`). Backspace otherwise refunds cooldowns for free.

**Save/load** - **not serialized** (mid-floor transient, same precedent as `witch_bolt_turns`).
Abilities are rebuilt on load via the growth-pick replay (section 4.4); cooldowns come back at 0.
Acceptable - loading a save is already a soft reset of mid-floor state.

### 2.2 Essence (the nova pool)

**`Stats` fields** (both serialized, same as `monk_focus_points`):

| Field | Type | Meaning |
|---|---|---|
| `hybrid_essence` | int | current pool |
| `hybrid_essence_max` | int | cap - `2` at L1, `3` at L6, `4` at L12 (computed property off `character_level`, never cached, mirrors `rage_uses_max`) |

**Gained:**
- **+1 on floor descent** - `GameState.advance_floor()`, capped at max. The main drip.
- **Full refill on a completed long rest** - `GameState.long_rest()`. (Long rest already costs 100
  food value + 20 turns, so this isn't free nova-spam; short rest grants nothing.)
- **"Essence Shard" item** - `Type.TOOL`, `use()` grants +1 (capped), consumed. Rare floor loot,
  ~1 per 2-3 floors (`fmin`/`fmax` tuned low-frequency; mirror in `debug_panel.ALL_ITEMS`).

Essence is **not** granted for using terrain / landing surface combos (owner decision) - the
surface reactions are their own reward (bigger damage), not an economy feedback loop.

**Spent:** `GameState.spend_hybrid_essence(n) -> bool` - returns false (and the ability refuses
with a gray log line) if `hybrid_essence < n`; skips consumption entirely while `invincible`.
Same shape as `GameState.spend_monk_focus()` / `spend_gold()`.

**HUD** - a pip row (filled / hollow diamonds), built like the short-rest pip row and the
Bonus Action pip. Placed on `$StatsPanel` next to them. NOT a status-tray icon (it's a resource
gauge, same call the Bonus Action indicator got).

**Power DC / attack bonus** - `Stats.hybrid_power_dc` = `8 + proficiency_bonus + INT modifier`
and `Stats.hybrid_attack_bonus` = `proficiency_bonus + INT modifier` (computed live, never
cached - mirrors `SpellcasterState.spell_save_dc()` and `Stats.monk_save_dc`). ATTACK_ROLL
abilities roll `d20 + hybrid_attack_bonus` vs AC (ADV/DISADV house rule, nat-20/nat-1 as
everywhere); SAVE abilities have the target roll `Enemy.resist_check_detailed(dc, ...)` vs
`hybrid_power_dc` and log a hoverable `save:` breakdown either way.

### 2.3 Coexistence with the existing rest system

The Hybrid still uses HP, potions, hit dice, short/long rest for **healing and status
cleanup** - none of that changes. Only its *offensive/utility resource* moves off per-rest.
Attrition tension therefore shifts onto HP + potions + the slow Essence drip, which is the
intended trade (see the design conversation). Nothing about `GameState.long_rest()` or the food
economy changes except the one Essence-refill line.

---

## 3. Surface and reaction system

### 3.1 Existing surfaces reused as-is

- `GRASS` / `TRAMPLED_GRASS` tiles, `DungeonFloor.ignite_grass()` - burning grass, spreads,
  converts to trampled. Fire ticks (`tick_fire_damage_for()`).
- `WATER` tiles - extinguish `burning_turns` on entry (player + enemy), difficult terrain.
- `MUD` tiles - difficult terrain.
- Burning props (`ignite_flammable()`), webs (`_webs`, Restrained), barrels (`_barrels`).
- `DungeonFloor._update_burning_tiles_glow()` / `_update_fog_cloud_visual()` - the pooled-
  `Sprite2D` tile-overlay convention every new surface visual copies.

### 3.2 New: hazard fields + entity element tags

**Hazard field** - a transient per-tile dict on `DungeonFloor`, same shape as `_webs` / `_barrels`:
```
_hazards: Dictionary  # Vector2i -> {"kind": String, "turns": int, "source": String}
```
`kind` for the first pass: **`"shock"`** only (fire is already the grass/prop system; water is
already a tile type). Ticked down each real turn; rendered as a tinted overlay via a new
`_update_hazard_glow()` (own sprite pool, per the "never contend" rule the torch glow follows).

**Entity element tags** - lightweight counters on both `Stats` (player) and `Enemy` (mirrored,
same "duplicate not unified" convention as Conditions):

| Tag | Field | Set by | Effect |
|---|---|---|---|
| Wet | `wet_turns` | standing in/entering WATER; a "douse" ability | +100% damage taken from `"Lightning"`; -50% from `"Fire"`; cannot be `burning` |
| Burning | `burning_turns` | **already exists as dead scaffolding** (`scripts/entities/CLAUDE.md` status table) - wire it live here | damage/turn (its existing `tick_status()` branch); cleared by WATER (already wired) |
| Shocked | `shocked_turns` | electrified water; a "shock" ability | loses next movement step (reuse the `slowed`/`rooted` step-budget mechanism, NOT a full turn skip) |

`burning_turns` already has a full `Stats.tick_status()` branch and a water-extinguish hook - it
is *literally* documented as "dead scaffolding with no live call site". The Hybrid is that call
site.

### 3.3 Reaction matrix (phased)

**Phase 1 (first implementation pass) - fire / water / shock only:**

| Trigger | Condition | Result |
|---|---|---|
| Fire ability hits a tile | tile is `GRASS` | `ignite_grass()` (existing) |
| Fire ability / burning grass | entity on tile, not `wet` | `burning_turns = N` |
| Fire ability | entity is `wet` | half fire damage, consumes 1 `wet_turns`, no `burning` |
| Fire ability | tile is `WATER` or adjacent burning grass over water | fire fizzles, brief steam puff (cosmetic only in P1) |
| Shock ability / `"shock"` hazard | tile is `WATER`, OR any entity on the tile is `wet` | **electrified**: flood-fill connected WATER tiles + all `wet` entities standing anywhere; every entity in that set takes the shock damage roll again and gains `shocked_turns` |
| Shock ability | dry, non-wet target | normal single-target shock damage, no spread |
| Any "douse" / water ability | target tile / entity | sets `wet_turns`; extinguishes `burning_turns`; if the tile was burning grass, puts it out |

**Phase 2+ (deferred, section 8):** oil tiles (`is_flammable` puddle -> fire = bigger burn),
ice (WATER + cold -> frozen difficult-terrain tile), poison clouds (+ fire -> detonation),
real steam zones (needs generalised obscurement, see 3.5).

### 3.4 Detonation

A "detonation" = an ability (or a fire hit on a poison cloud, in Phase 2) that consumes a surface
to produce a burst. In Phase 1 the only detonation is **electrified water** (a shock ability
spent on a water/wet cluster): the shock damage roll re-applies to every entity in the connected
WATER + `wet` set, each gains `shocked_turns`. The reward is the spread damage itself, nothing
else. Core loop: set up wet -> shock the cluster -> big multi-target hit.

### 3.5 Known dependency

Real steam / expanded obscurement needs `GameState.fog_cloud_pos` (single-slot) generalised to a
list of zones, the same way `is_heavily_obscured()` was written to anticipate. Phase 1 avoids
this by making steam cosmetic. Do the generalisation when Phase 2 lands, not before.

---

## 4. The Hybrid class

### 4.1 D&D-style base stat block

`Stats.CharacterClass.HYBRID` (new enum entry). `Stats.apply_class_defaults()`'s HYBRID branch:

| Field | Value |
|---|---|
| Ability scores | STR 10, DEX 14, CON 14, INT 16, WIS 10, CHA 8 (custom-path point buy overrides these) |
| Hit die | d10 (`GameState.hit_die_sides()` + `Stats.point_buy_hit_die_base()` entries) |
| `check_prof_*` | DEX + INT |
| Weapon proficiency | Simple weapons (`proficient_simple_weapons = true`) |
| Armor | Light armor only (`proficient_light_armor = true`); no medium/heavy, no shield |
| `Stats.CLASS_ROLE` | new value `"HYBRID"` (not caster, not martial - its own row) |
| `Stats.caster` | stays `null` |
| `Stats.mastery_cap()` | `0` (no weapon-mastery picker - the kit is the abilities) |

**Starting gear** (`GameState._give_hybrid_starting_items()`): a Dagger (Main Hand) + Leather
Armor. No focus item.

### 4.2 Power math

`Stats.hybrid_power_dc` / `hybrid_attack_bonus` as defined in 2.2. Add a `race_bonus`-style
status-tray hover later if useful; not required for the first pass.

### 4.3 Progression skeleton (REVISED 2026-09-01)

The original "no talents, no subclass, abilities only" model was too thin. The Hybrid now gets
three interleaved things as it levels, one grant per level-up so no level feels empty:

| Level | Grant |
|---|---|
| 1 | 1 passive (always-on identity) + 1 activation (pick-1-of-3, the core cooldown tool) |
| 2 | base talent point #1 |
| 3 | activation #2 (pick-1-of-3) |
| 4 | base talent point #2 |
| 5 | **subclass** (boss-gated, section 4.6) - grants its signature activation free, in place of this level's normal activation |
| 6 | Essence max 2->3 (already in `hybrid_essence_max`) + base talent point #3 |
| 7 | activation #3 |
| 8+ | keep alternating: activations on odd character levels, base talent points on even ones |

Rules of thumb: activations land on **odd** character levels, base talent points on **even** ones.
Tier-2 (subclass) talent points still follow the existing levels-7-12 boss-pending schedule
(`talent_points[2]`), unchanged from Barbarian.

`HybridAbilityDb` entries carry a `"kind"` (`"passive"` / `"activation"`) so the picker / cadence
logic can tell the two tracks apart. Today `_grant_hybrid_abilities_for_level()` still auto-grants
by `min_level` (the passive + activations at 1/3/5/7); the picker (4.4) and talents (4.5) are the
next slices.

### 4.4 Onboarding + growth

**Custom path:** class select -> point buy -> background ASI -> race select -> character summary
-> **Hybrid starter pick** -> game starts. The starter pick is one round of "pick 1 of 3" over
the level-1-eligible ability pool, reusing `spell_learn_picker.gd`'s card layout (it is already
generic over a candidate id list; feed it Hybrid ability ids instead of spell ids). Commit via a
new `GameState.choose_hybrid_ability(id)` that builds the `Ability` and calls `add_ability()`.

**Premade hero:** add a Hybrid premade to `character_select.gd`'s `PREMADE` with a fixed
`"hybrid_ability": "<id>"` key, applied the same way every premade's fixed picks are.

**Level-up growth:** on each **odd** character level from 3 up (3, 7, 9, 11, ... - level 5 is the
subclass instead, section 4.6), `GameState.gain_exp()`'s level-up block sets
`hybrid_ability_pick_pending` + rolls up to 3 `kind == "activation"` candidates filtered to
`min_level <= character_level` and not already known. `hud.gd._on_player_leveled_up()` spawns the
same picker (mandatory, one card commits via `GameState.learn_hybrid_ability(id)` ->
`add_ability()`). Degrades to fewer than 3 cards when the pool runs thin (same graceful fallback
as the Wizard spell-learn picker). Replayed on save/load: serialize `known_hybrid_ability_ids:
Array[String]` and rebuild the bar in a `_rebuild_hybrid_ability_bar()` call after
`Stats.from_dict()`, mirroring `_rebuild_spell_ability_bar()`. The L1 passive is not a pick - it's
granted flat alongside the starter activation.

### 4.5 Base talents - general, never bolted to one activation

The starter/base talents are **general** and never modify a specific activation. Reasoning (the
Pixel Dungeon / SPD model): activations come from a random pick-1-of-3, so a talent bolted to one
ability is a feel-bad draw whenever you didn't pick that ability. In SPD the base/starter talents
are generic and the ability-specific power lives in the later "armor" talents once you actually own
the ability - for the Hybrid, that ability-specific depth lives in the **subclass** tier (4.6).

"General" here means the surface / Essence economy that IS the class identity, not flat "+2 HP".
First-pass candidate pool (flat list, no tiers; pick 1 per even level from those not yet taken; a
talent with `ranks` can be re-picked to rank it up - numbers untuned, owner tunes):

| id | effect |
|---|---|
| `hb_conduction` | Wet / in-water enemies you hit take +1 Lightning (R2 +2, R3 +3). |
| `hb_priming` | The first surface you create each floor has +1 radius and skips its cooldown. |
| `hb_sure_footed` | Ignore difficult terrain from Mud / Water; you are immune to your own `shocked`. |
| `hb_reservoir` | While standing on your own surface (`wet` tile / `shock` hazard), your cooldowns tick twice per turn. |
| `hb_overload` | Once per floor, an Essence ability may be cast with 0 Essence in the pool. |
| `hb_hardened` | +2 max HP per level (R1-R3) - the deliberate boring-but-safe pick. |
| `hb_reflexes` | +1 AC while `hybrid_essence == 0` (R2 +2). |

**Implementation:** new `HybridTalentDb` (data dicts, same shape as `HybridAbilityDb` /
`SpellDb` - no `.tres`), Hybrid talents are `tier = 1`, `class_id = "HYBRID"`. Reuse the existing
`talent_investments` / `talent_points` / `talent_picker.gd` infrastructure verbatim; add a
`_apply_hybrid_talent_rank(id, rank)` branch to `_apply_talent_rank()`'s dispatch. `gain_exp()`
grants `talent_points[1]` on even levels for a Hybrid (mirrors the Barbarian tier-1 grant).
`_build_class_talents()` / the `_class_talents` assignment gets a `HYBRID` case feeding
`HybridTalentDb`. Save/load: replayed through the existing talent-replay path in `from_dict()`,
no new serialization.

### 4.6 Subclass (level 5, boss-gated)

Reuses the **exact Barbarian mechanism** with zero new plumbing: the `TIER2_GATING_BOSS_ID`
("big_demon", floor 5) kill emits `subclass_choice_required`, `hud.gd` spawns `subclass_select.gd`,
its confirm calls `choose_subclass()` -> `unlock_tier2()` -> `_setup_tier2_for_active_subclass()`.
Tier-2 points earned at levels 7-12 pend until that kill, same as Barbarian.

**2-3 elemental leanings, NOT five.** First pass:
- **Storm** - lightning / wet-payoff. Signature activation: a chain-lightning nova that always
  triggers electrified-water spread. 3 tier-2 talents deepen it (bigger chain, `shocked` on every
  hit, refund Essence on a multi-target hit).
- **Pyre** - fire / grass. Signature activation: a fire dash (Emberstep on steroids) that ignites
  every tile crossed and leaves a burning wake. 3 tier-2 talents deepen it (longer dash, burning
  wake lasts longer, ignites adjacent barrels/doors).
- **Frost** - deferred until Phase-2 surfaces (ice tiles) exist (section 8).

Each subclass grants **one free signature activation** at selection (like Frenzy / Limit Break /
Zealot Strike - see `TIER2_BASE_ABILITY_ID`), never gated by a talent rank; the 3 tier-2 talents
only upgrade it. Add: a `match` case in `_setup_tier2_for_active_subclass()`, a
`_setup_hybrid_<sub>_tier2_talents()` per subclass, `TIER2_BASE_ABILITY_ID` entries, and cards in
`subclass_select.gd`'s `SUBCLASSES` - all following the existing Barbarian-subclass pattern. This
is a per-class-conditional subclass set, so `subclass_select.gd` / `TIER2_SUBCLASSES` need to be
made class-aware (today they're hardcoded to the 5 Barbarian names).

No respec (matches talent/invocation permanence).

---

## 5. Ability authoring template (owner fills this in)

Each Hybrid ability is a plain data dict in a new `HybridAbilityDb` (static factory, builds
`Ability` resources in code - same "no .tres" convention as `SpellDb` / `Talent`). Fill in:

```
id:            snake_case unique
name:          display
description:   lead with the mechanic (roll / save / effect), then secondary effects.
               Name surfaces/tags as keywords ("target is Wet"), don't restate what they do.
min_level:     when it enters the growth picker (1, 3, 5, ...)

power_type:    COOLDOWN | ESSENCE | PASSIVE
cooldown_max:  turns        (COOLDOWN only)
essence_cost:  1 | 2 | 3    (ESSENCE only)

target:        SELF | ENEMY | TILE | DIRECTION | CONE | SPHERE
range_tiles:   int          (Chebyshev; single-target reach is Chebyshev everywhere in this engine)
shape_size:    int          (CONE length / SPHERE radius; /10-ceil convention, re-check with owner)

resolution:    ATTACK_ROLL (d20 + hybrid_attack_bonus vs AC)
             | SAVE  (target rolls vs hybrid_power_dc; set save_stat, save_for_half)
             | AUTO  (no roll)
damage_dice:   "NdM"        (scales how? flat, or per-tier at levels 5/11/17 - owner decides per ability)
damage_type:   "Fire" | "Lightning" | "Cold" | ... (drives the reaction matrix)

creates_surface: none | {kind: "shock", radius: N, turns: N}
detonates:       none | ["shock", ...]      (which surfaces this ability consumes for a burst)
applies_tag:     none | {tag: "wet"|"burning"|"shocked", turns: N}

notes:         anything the fields above can't express
```

**Design guidance for the owner:**
- COOLDOWN abilities: your every-turn tools. 2-6 turn cooldowns. These should be *most* of the
  kit. A pure attack, a mobility dash, a surface-layer, a small self-buff.
- ESSENCE abilities: 2-4 total, each `essence_cost` 1-3. Big AoE, a detonation-ampl, a panic
  button. Losing a fight should feel like "I'm out of Essence and low HP", the way a Wizard out
  of slots feels now.
- Lean on the matrix: the interesting abilities are the ones that *set up* (lay water/wet) and
  the ones that *pay off* (shock a wet cluster, ignite grass under a group). A flat damage
  ability that ignores surfaces is a wasted slot on this class.
- PASSIVE abilities exist for discoverability parity (like Monk's Unarmored Defense bar entry) -
  click just logs a reminder.

---

## 6. Seed abilities (PLACEHOLDER - illustrative, owner will replace)

Just enough to show one of each archetype and prove the plumbing. Numbers untuned.

**`spark` - COOLDOWN attack**
`min_level 1`, `power_type COOLDOWN`, `cooldown_max 2`, `target ENEMY`, `range 4`,
`resolution ATTACK_ROLL`, `damage 1d8 Lightning`. `detonates ["shock"]`, and if the target is
`wet` or on WATER -> electrified-water spread (3.3). Baseline poke that becomes a nuke on a
watered target.

**`tide` - COOLDOWN surface-layer**
`min_level 1`, `power_type COOLDOWN`, `cooldown_max 4`, `target TILE`, `range 5`,
`resolution AUTO`. Douses a radius-1 area: sets `wet_turns` on entities, extinguishes `burning`,
puts out burning grass. No damage. The setup half of the combo.

**`arc` - ESSENCE nova**
`min_level 3`, `power_type ESSENCE`, `essence_cost 2`, `target SPHERE`, `range 6`,
`shape_size 2`, `resolution SAVE` (DEX, half), `damage 4d8 Lightning`. `detonates ["shock"]`.
Any WATER / `wet` entity in the blast triggers full electrified spread. The payoff.

**`emberstep` - COOLDOWN mobility**
`min_level 5`, `power_type COOLDOWN`, `cooldown_max 3`, `target DIRECTION`, `range 3`,
`resolution AUTO`. Dash up to 3 tiles (arm-then-click / WASD, model on Cloud Giant's Jaunt);
leaves burning grass on each tile crossed that is `GRASS`.

**`ground` - PASSIVE**
`min_level 1`, `power_type PASSIVE`. While standing on WATER the Hybrid is immune to its own
electrified-water spread. Bar entry logs a reminder on click.

---

## 7. Codebase integration checklist

1. `scripts/items/ability.gd` - add `cooldown_max` / `cooldown_remaining`.
2. `scripts/entities/stats.gd` - `CharacterClass.HYBRID`, `CLASS_ROLE["HYBRID"]`,
   `apply_class_defaults()` branch, `hybrid_essence` / `_max`, `hybrid_power_dc` /
   `hybrid_attack_bonus`, `wet_turns` / `shocked_turns` + `tick_status()` branches, wire
   `burning_turns` live. `to_dict()`/`from_dict()`: `hybrid_essence`, `known_hybrid_ability_ids`.
3. `GameState` - `spend_hybrid_essence()`, essence grant in `advance_floor()` + `long_rest()`,
   `is_ability_usable()` / `ability_unusable_reason()` cooldown branch,
   `choose_/learn_hybrid_ability()`, `_give_hybrid_starting_items()`, `_rebuild_hybrid_ability_bar()`,
   `hybrid_ability_pick_pending` + growth roll in `gain_exp()`.
4. `scripts/items/hybrid_ability_db.gd` - new static factory (owner fills the list).
5. `scripts/entities/spell_effects.gd` sibling or new `scripts/entities/hybrid_effects.gd` -
   ability resolvers + the reaction matrix (`_resolve_electrified_water()` flood-fill, etc.).
6. `player.gd._use_ability_slot()` - dispatch Hybrid ability ids; `_on_turn_started()` - cooldown
   tick.
7. `scripts/world/dungeon_floor.gd` - `_hazards` dict, `_update_hazard_glow()`, tick in the
   per-turn sweep; electrified-water flood-fill helper over WATER tiles.
8. `hud.gd` - cooldown darken+number on the bar; Essence pip row on `$StatsPanel`.
9. `RewindManager` - snapshot `cooldown_remaining` per bar ability; `hybrid_essence` handled via
   the normal `Stats` snapshot.
10. `scripts/ui/class_select.gd` / `character_select.gd` - Hybrid card + premade;
    `scripts/ui/spell_learn_picker.gd` - generalise candidate source (or fork).
11. Sprites: `sprites/characters/classes/Hybrid/` (idle/run; no hit art -> `has_real_hit_art`
    stays `["Wizard","Monk"]`, Hybrid plays a static idle frame on attack).
12. `Stats.hit_die_sides()` / `point_buy_hit_die_base()` / `hp_per_level_breakdown()` - d10 entry.
13. **Progression cadence (section 4.3):** `HybridAbilityDb` `"kind"` field + retuned `min_level`s
    (DONE 2026-09-01). Next: `hybrid_ability_pick_pending` growth roll on odd levels in
    `gain_exp()` + reuse `spell_learn_picker.gd` for the pick-1-of-3.
14. **Base talents (section 4.5):** `scripts/items/hybrid_talent_db.gd` (new); `_apply_talent_rank()`
    `HYBRID` dispatch branch; `_class_talents` / `_build_class_talents()` `HYBRID` case;
    `gain_exp()` grants `talent_points[1]` on even levels for a Hybrid.
15. **Subclass (section 4.6):** make `TIER2_SUBCLASSES` / `subclass_select.gd` class-aware;
    `_setup_tier2_for_active_subclass()` `Storm` / `Pyre` cases + `_setup_hybrid_*_tier2_talents()`;
    `TIER2_BASE_ABILITY_ID` entries for the two signature activations.
16. Docs: `scripts/entities/CLAUDE.md` "Hybrid class" section, `scripts/items/CLAUDE.md` ability/
    surface notes, root `CLAUDE.md` pointer lines. Delete this design doc once fully shipped and
    the sub-docs cover it (repo doc-cleanup rule).

---

## 8. Deferred / out of scope for the first pass

- Oil, ice/frozen, poison-cloud, real steam surfaces (Phase 2 - section 3.3).
- Generalised multi-zone obscurement (`fog_cloud_pos` -> list) - needed only by steam.
- Enemy Hybrids / enemy cooldown abilities beyond the existing `"abilities"` schema.
- Multiclass, respec.
- Porting cooldowns/Essence to the other classes - decide only after this one plays well.
- Cooldown reduction effects, Essence-on-crit, per-ability cooldown scaling by level - add only
  if an ability actually needs it (same "narrow case, not the full system" discipline as the rest
  of the codebase).
