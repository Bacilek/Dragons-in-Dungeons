# Rampager Class - Cooldown + Fury Design

**Status:** DESIGN + FIRST-PASS IMPLEMENTATION (2026-09-01). "Our version of the Barbarian" -
same reckless melee-bruiser fantasy, but OFF the D&D per-rest model. **Runs on the exact same
economy as the Hybrid** (`docs/architecture/hybrid-class-design.md`): cooldown abilities for the
bread-and-butter kit + a small nova pool for the big hits. The Hybrid calls that pool Essence; the
Rampager calls it **Fury**. Mechanically a clone - the point is to validate the one alternative
economy on a second class, not to invent a third model. See that design conversation for the
"D&D backbone + ONE sanctioned alternative lane, never per-class bespoke" framing.

The only Rampager-specific hook is the **collision matrix** (section 3) - abilities that shove /
hurl enemies into walls, each other, and hazards, leaning on the forced-movement + wall-slam sim
the game already has (`DungeonFloor.resolve_push()` etc). That is the Rampager's equivalent of the
Hybrid's surface reactions: reuse an existing simulation, don't build a new resource.

Created 2026-09-01.

---

## 1. Resource model - identical to the Hybrid

Everything in `hybrid-class-design.md` sections 2.1 (cooldowns) and 2.2 (the nova pool) applies
verbatim, with `Essence` -> `Fury`:

| Hybrid | Rampager | Notes |
|---|---|---|
| `Ability.cooldown_max` / `cooldown_remaining` | same fields, same tick | already generic - the Hybrid pass built this on `Ability`, no change needed |
| `Stats.hybrid_essence` / `hybrid_essence_max` (2/3/4 at L1/6/12) | `Stats.rampager_fury` / `rampager_fury_max` (2/3/4 at L1/6/12) | identical curve |
| `GameState.spend_hybrid_essence()` | `GameState.spend_rampager_fury()` | same "invincible skips consumption" invariant |
| `GameState.grant_hybrid_essence(1)` on `advance_floor()` | `grant_rampager_fury(1)` on `advance_floor()` | the slow drip - one per floor descent |
| full refill in `long_rest()` | same | one line in `long_rest()` |
| `hybrid_power_dc` = `8 + prof + INT mod` | `rampager_power_dc` = `8 + prof + STR mod` | STR-based (it's a bruiser, not a caster) |
| `hybrid_attack_bonus` = `prof + INT mod` | `rampager_attack_bonus` = `prof + STR mod` | |
| cooldowns clear on long rest | same | |
| `is_ability_usable()` / `ability_unusable_reason()` generic cooldown+nova gate | same, class-aware pool check | `"CD N"` / `"No Fury"` |
| `PlayerHybrid._pay()` | `PlayerRampager._pay()` | spend Fury, set cooldown, add to the per-turn cd-skip list |
| `RewindManager` | nothing - `rampager_fury` rides the `Stats.duplicate(true)` capture | same as `hybrid_essence` |

An ability is **cooldown xor Fury-cost xor passive**, same authoring rule as the Hybrid.

`long_rest()` refills Fury to max (unlike a live gauge it's a per-rest nova pool, exactly like
Essence). `Stats.CLASS_ROLE["RAMPAGER"] = "MARTIAL"` so nothing grants it a `caster`.

---

## 2. The Rampager class

### 2.1 D&D-style base stat block (`Stats.apply_class_defaults()` RAMPAGER branch - DONE)

| Field | Value |
|---|---|
| Ability scores | STR 16, CON 15, DEX 12, WIS 10, INT 8, CHA 8 (point-buy overrides) |
| Hit die | d12 (`point_buy_hit_die_base()` / `hp_per_level_breakdown()` avg 7 - identical to Barbarian) |
| `check_prof_*` | STR + CON |
| Weapons | Simple + Martial |
| Armor | Light + Medium + Shields (no Heavy) - same as Barbarian |
| `Stats.mastery_cap()` | mirrors the Barbarian value (2/3/4 at L1/4/10) - the Rampager swings real weapons, the weapon-mastery picker stays |
| unarmored defense | none - wears Medium + Shield |

**Starting gear** (`GameState._give_rampager_starting_items()`): mirror the Barbarian's current
starter - a Spear (Main Hand) + 2 thrown Handaxes (`markdowns/barbarian_base.md` option (a)). No
armor. `equipment_changed.emit()` at the end.

### 2.2 Progression skeleton (identical shape to the revised Hybrid, section 4.3 there)

| Level | Grant |
|---|---|
| 1 | 1 passive (**Bracer** - the Fury / collision reminder) + 1 activation (pick-1-of-3) |
| 2 | base talent point #1 |
| 3 | activation #2 |
| 4 | base talent point #2 |
| 5 | **subclass** (boss-gated) - grants its signature activation free, in place of this level's activation |
| 6 | Fury max 2 -> 3 (already in `rampager_fury_max`) + base talent point #3 |
| 7 | activation #3 |
| 8+ | activations on odd levels, base talent points on even levels |

`RampagerAbilityDb` entries carry a `"kind"` (`"passive"` / `"activation"`), same as
`HybridAbilityDb`. First pass auto-grants by `min_level`
(`GameState._grant_rampager_abilities_for_level()`); the `spell_learn_picker.gd`-backed
pick-1-of-3 is the next slice, same as the Hybrid.

### 2.3 Onboarding + growth

Same as the Hybrid (that doc's section 4.4). Custom path: ... character summary -> **Rampager
starter pick** -> game starts. `GameState.choose_rampager_ability(id)` /
`learn_rampager_ability(id)`. Save/load: serialize `known_rampager_ability_ids: Array[String]`,
rebuild in `_rebuild_rampager_ability_bar()`. First pass: auto-grant, no picker yet.

---

## 3. Collision matrix (the Rampager-specific hook)

### 3.1 Existing sim reused as-is

- `DungeonFloor.resolve_push(enemy, direction)` - WALL -> 1d4 Bludgeoning + no move; trap tile ->
  move + `trigger_trap()`; CHASM -> enemy removed (counts as a kill); otherwise 1-tile shove.
  **Already does everything "shove into terrain" needs.**
- `DungeonFloor.force_move_entity()` + wall-slam damage.
- `DungeonFloor.ignite_flammable()` / barrel + door destruction.
- `Enemy.apply_status("prone", 1)` - the real Prone condition (Maul's Topple uses it).

### 3.2 New: collision-into-a-creature

`RampagerEffects._resolve_collision(shoved, dest_tile, dungeon_floor)`: when a shoved/hurled
enemy's path is blocked by **another enemy**, both take a Bludgeoning instance (scaled by throw
distance) and both are knocked Prone. WALL at the far tile = the existing wall-slam plus Prone.
Mirrors `resolve_push()`'s "dedicated resolver, non-generic per-tile outcome" shape.

### 3.3 Reaction table (Phase 1)

| Trigger | Result |
|---|---|
| shove / hurl ends on WALL | wall-slam Bludgeoning (existing) + Prone |
| shove / hurl blocked by an enemy | `_resolve_collision()` - both hit + Prone |
| shove / hurl ends on a trap tile | existing `resolve_push()` trap path |
| shove / hurl ends on CHASM | existing `resolve_push()` chasm-removal |
| a dash (Overrun) crosses a barrel / unlocked door | prop destroyed (`ignite_flammable()` path / direct), dash continues |

**Phase 2+ (deferred):** rubble tiles (slammed WALL -> difficult terrain), chain collisions,
knock-off-ledge.

---

## 4. Ability kit (`RampagerAbilityDb`)

Same data-dict shape as `HybridAbilityDb.DEFS`. `power_type` is `"cooldown"` xor `"fury"` xor
`"passive"`; a `"fury"` ability needs `rampager_fury >= fury_cost` and subtracts it on use (the
`fury_cost` key, read the same way `essence_cost` is for the Hybrid).

**First pass (3 entries - owner tunes numbers):**

| id | name | kind | min_lvl | power | effect |
|---|---|---|---|---|---|
| `rmp_bracer` | Bracer | passive | 1 | passive | Reminder entry. Bar click just logs the Fury / collision rules. |
| `rmp_overrun` | Overrun | activation | 1 | cooldown 2 | Charge in a straight line up to 4 tiles; ram the first enemy - a melee attack (`rampager_attack_bonus` vs AC) for `2d6` Bludgeoning + shove them 1 tile via `resolve_push` (wall-slam / collision / trap / chasm all apply). Destroys barrels / unlocked doors crossed. |
| `rmp_shockwave` | Shockwave | activation | 3 | fury 2 | STR save (`rampager_power_dc`) or `3d8` Bludgeoning, half on a save, to every enemy within 2 tiles; anyone who fails is knocked Prone. Mechanically Arc with Bludgeoning + Prone instead of Lightning + electrified spread. |

L5+ activations (a hurl, a warpath sweep) + the subclass signatures come in the next slice - see
sections 2.2 / 5 / 6. `rmp_shockwave` copies `HybridEffects.arc()`'s structure almost line for
line; `rmp_overrun` copies `HybridEffects.emberstep()`'s dash + a melee attack roll.

**Design guidance** (same as the Hybrid doc's section 5): COOLDOWN abilities are the every-turn
tools (2-3 turn cds, most of the picked kit); FURY abilities are the finishers (trade the pool for
a big collision play); PASSIVE entries are discoverability parity. Lean on the collision matrix -
a flat-damage ability that moves no one is a wasted slot on this class.

---

## 5. Base talents (`RampagerTalentDb`) - general, never bolted to one ability

Same rule as the Hybrid (that doc's section 4.5). Flat list, `tier = 1`, `class_id = "RAMPAGER"`,
pick 1 per even level; `ranks` re-picks to rank up. First-pass pool (untuned):

| id | effect |
|---|---|
| `rmp_concussive` | Collision / wall-slam Bludgeoning +1d6 and always knocks Prone (R2 +2d6). |
| `rmp_adrenaline` | Start each floor with +1 Fury (R2: +2, still capped at `rampager_fury_max`). |
| `rmp_headlong` | First melee attack each turn after moving 2+ tiles has Advantage. |
| `rmp_unstoppable` | Ignore difficult terrain; your movement never provokes Opportunity Attacks. |
| `rmp_bloodlust` | On a kill by your hand, your lowest cooldown drops by 1 (R2: by 2). |
| `rmp_hardened` | +2 max HP per level (R1-R3) - the boring-but-safe pick. |

**Implementation:** `scripts/items/rampager_talent_db.gd`; `_apply_talent_rank()` `RAMPAGER`
dispatch branch; `_class_talents` / `_build_class_talents()` `RAMPAGER` case; `gain_exp()` grants
`talent_points[1]` on even levels for a Rampager. Save/load: existing talent-replay path.

---

## 6. Subclass (level 5, boss-gated) - reuse the Barbarian mechanism

`TIER2_GATING_BOSS_ID` kill -> `subclass_choice_required` -> `subclass_select.gd` ->
`choose_subclass()` -> `unlock_tier2()`. Tier-2 points earned levels 7-12 pend until that kill.

**2 leanings** (not five):
- **Juggernaut** - terrain / prop destruction. Signature activation **Demolish**: charge through
  walls, props, and enemies in a line, destroying everything, gaining Fury per object smashed.
  Tier-2 talents: longer charge, slammed walls leave rubble, wide-cone Prone.
- **Feral** - low-HP payoff (name distinct from Barbarian's own "Berserker" subclass). Signature
  activation **Death Wish**: 3 turns of +50% damage taken, +100% damage dealt, and every Fury
  spend refunds 1. Tier-2 talents: heal on a kill during it, longer duration, can't drop below 1 HP.

Each grants **one free signature activation** at selection (like Frenzy - `TIER2_BASE_ABILITY_ID`);
the 3 tier-2 talents only upgrade it. Prereq shared with the Hybrid's own subclass slice: make
`TIER2_SUBCLASSES` / `subclass_select.gd` class-aware (today hardcoded to the 5 Barbarian names).

---

## 7. Codebase integration checklist

1. `scripts/entities/stats.gd` - `CharacterClass.RAMPAGER`, `CLASS_ROLE`, `apply_class_defaults()`,
   `rampager_fury` / `rampager_fury_max` / `rampager_power_dc` / `rampager_attack_bonus`, d12
   tables, `mastery_cap()`, `to_dict()`/`from_dict()`. **DONE** (except `known_rampager_ability_ids`).
2. `scripts/items/ability.gd` - `fury_cost` field (mirrors `essence_cost`).
3. `scripts/items/rampager_ability_db.gd` - static factory (section 4). **First pass.**
4. `scripts/entities/rampager_effects.gd` - resolvers + `_resolve_collision()` (copy `HybridEffects`).
5. `scripts/entities/player_rampager.gd` - `_rampager` composition child on `Player` (copy
   `PlayerHybrid`): arming / targeting, `_pay()`, rewind fields.
6. `GameState` - `spend_rampager_fury()` / `grant_rampager_fury()`, grant in `advance_floor()` +
   refill in `long_rest()`, `_give_rampager_starting_items()`,
   `_grant_rampager_abilities_for_level()` (call sites: give-items, `gain_exp()` level-up,
   `from_dict()`), `_build_rampager_ability()`, `is_ability_usable()` / `ability_unusable_reason()`
   Fury branch, `hit_die_sides()` d12 entry, give-starting-items dispatch.
7. `player.gd` - `_rampager` init in `_ready()`, `_use_ability_slot()` dispatch for
   `RampagerAbilityDb.is_rampager_ability(id)`, the `_hybrid`-parallel sites (cooldown tick reuse
   the same `_hybrid_cd_skip_this_turn` list - rename to `_cd_skip_this_turn`, or add a parallel;
   mouse-release + WASD targeting branches; move-cancel + Esc `cancel()`), `_setup_animations()`
   `RAMPAGER -> "Rampager"`, rewind `capture_rewind_state()` entry.
8. `hud.gd` - a Fury pip row on `$StatsPanel` (copy `_update_essence_indicator()`), Rampager-only.
   Cooldown darken+number on the bar is already generic from the Hybrid pass.
9. `scripts/ui/class_select.gd` - Rampager card in `CLASS_DATA` (`"hybrid": true` puts it under
   the existing non-D&D roster toggle - rename that toggle's label if "Hybrid" reads wrong for a
   2-class roster, owner's call).
10. Sprites: `sprites/characters/classes/Rampager/` (copy the Hybrid/Wizard idle+run set as
    placeholder; `has_real_hit_art` stays `["Wizard","Monk","Hybrid"]` unless a real set lands).
11. Base talents (section 5) + subclass (section 6) - next slices.
12. Docs: `scripts/entities/CLAUDE.md` "Rampager class" section, `scripts/items/CLAUDE.md`,
    root `CLAUDE.md` pointer. Delete this doc once fully shipped and the sub-docs cover it.

---

## 8. Deferred / out of scope for the first pass

- The pick-1-of-3 growth picker (auto-grant first, same as the Hybrid).
- Base talents, subclass, L5+ abilities (hurl, warpath, Demolish, Death Wish).
- Rubble tiles / terrain destruction beyond `resolve_push()`.
- A "Fury Shard" item (Hybrid's Essence Shard equivalent).
- A premade hero.
- Real class art.
- Porting the cooldown+nova model to the D&D classes - decide only after Hybrid + Rampager both
  play well (that's the whole point of two data points).
