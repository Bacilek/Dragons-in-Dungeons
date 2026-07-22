**Implementation status (update this line, don't rewrite the doc): steps 1-7 of §20 are DONE** —
`mods`/`prof_bonus`/`check_profs` (§4), the three damage R/I/V lists + `condition_immunities`
(§5/§6), `cr`/`creature_type` annotation (§3/§7), `senses.sight` (§10), `multiattack` (§12), generic
`abilities` cooldown/uses_max/recharge dispatch (§12, reusing the multiattack sub-attack shape —
no per-ability custom code needed for a plain ranged-damage(+status) ability), `regeneration`/
`undead_fortitude` traits (§11), and Legendary Resistance on `big_demon` (§15) are all live in
`scripts/entities/enemy.gd` — see that file's CLAUDE.md "Enemy D&D stat-block schema" section for
the authoring-facing field table. **Still design-only** (step 8/9, deliberately deferred): size/
multi-tile occupancy (§8), reactions beyond Opportunity Attacks (§13), conditional triggers (§14),
Legendary Actions (§15).

# Enemy Stat Block — Data Schema Design

Enemies today are one `Enemy` class (`scripts/entities/enemy.gd`) configured entirely from plain
Dictionary entries in `DungeonFloorData.ENEMY_POOL` / `BOSS_POOL` (`scripts/world/dungeon_floor_data.gd`).
That philosophy — "data describes the knob, code dispatches the effect" — stays. This doc specs the
**target Dictionary schema** for a near-1:1 D&D 5.5e-style monster stat block (HP/AC/CR, ability
scores, check bonuses, resist/immune/vuln, condition immunities, creature type, size, movement modes,
proficiency, senses, traits, actions/multiattack, limited-use resources, reactions, conditional
triggers, legendary resistance) so future sessions can implement real monsters against one consistent
structure.

**This is a skeleton/spec, not an implementation.** It complements — does not replace —
`docs/architecture/ENEMY_SYSTEM_ARCHITECTURE.md`: that doc covers the *behavior* refactor
(decide/execute split §1, archetypes §2, ability cooldowns §3, boss phases §4, targeting §5). This doc
covers the *data* schema those mechanisms read from. Where the two overlap (abilities, attack
profiles), this doc defers to that one and only extends it.

Owner-set fidelity dial: as close to real 5e stat blocks as the pool-dict philosophy allows, **except
movement-speed granularity and bonus actions**, which stay deliberately simple (see §9 and §12).

---

## 1. Core decision: extend the pool dict, do not introduce a Resource class

**Rejected: `EnemyStatBlock` as a `Resource` (`.tres`/`.gd` class).** The project already rejected an
`EnemyAbility` Resource in `ENEMY_SYSTEM_ARCHITECTURE.md` §3 for the same reason that applies here:
Resources earn their keep when something needs editor tooling, serialization identity, or a UI surface
(player `Ability`/`Talent` have icons, bars, pickers). An enemy stat block has none of that — it is
read once in `Enemy.configure(type_data)` / `_apply_stats()` and never shown in any UI beyond derived
numbers. A typed Resource would also fork the pool system: `ENEMY_POOL` is an `Array[Dictionary]`
today, and items/talents/floor-feelings all follow the same pattern. One convention, kept.

**Rejected: per-monster subclasses** (`SkeletonEnemy extends Enemy`) — already rejected in
`ENEMY_SYSTEM_ARCHITECTURE.md` §2; nothing in a stat block needs code-per-monster, only
data-per-monster plus shared dispatch code.

**The rule: every new stat-block field is an *optional* pool key with a safe default** equal to
today's behavior. An entry that adds none of the new keys behaves exactly as it does now — zero
migration cost, and the schema can be adopted one monster at a time.

---

## 2. Schema overview

Full target shape of a pool entry, grouped by concern. Every group is optional except the ones that
exist today (marked *current*). Field-by-field detail in the sections that follow.

```gdscript
{
    # ── Identity / presentation (current) ──────────────────────────────
    "enemy_id": "skeleton", "display_name": "Skeleton", "sprite": "skelet",
    "idle_frames": 4, "run_frames": 4,
    "floor_min": 4, "floor_max": 7, "exp": 9,

    # ── Defense (current) ───────────────────────────────────────────────
    "hp": 9, "hp_per_floor": 2, "ac": 12, "armor": 1,

    # ── Offense (current) ───────────────────────────────────────────────
    "dmg_min": 3, "dmg_max": 6, "reach": 1,
    "attack_profile": {...},                    # per ENEMY_SYSTEM_ARCHITECTURE.md §2

    # ── NEW: Challenge Rating (§3) ──────────────────────────────────────
    "cr": 0.25,                                 # float; 0.125 / 0.25 / 0.5 / 1 / 2 ...

    # ── NEW: Ability scores as modifiers (§4) ───────────────────────────
    # Generalizes today's ad-hoc "str_mod"/"con_mod". Absent key = modifier 0.
    "mods": {"str": 2, "dex": 0, "con": 1, "int": -2, "wis": 0, "cha": -3},

    # ── NEW: Proficiency + check proficiencies (§4) ─────────────────────
    "prof_bonus": 2,                            # default: derived from CR (see §4)
    "check_profs": ["str", "con"],              # which of the 6 abilities add prof_bonus to checks
    "attack_prof": true,                        # prof_bonus added to attack rolls (default true)

    # ── NEW: Damage resist / immune / vuln (§5) ─────────────────────────
    "damage_resistances":     ["Slashing", "Piercing"],   # ×0.5
    "damage_immunities":      ["Poison"],                 # ×0.0
    "damage_vulnerabilities": ["Bludgeoning"],            # ×2.0

    # ── NEW: Condition immunities — a separate axis (§6) ────────────────
    "condition_immunities": ["poisoned", "prone"],

    # ── NEW: Creature type (§7) ─────────────────────────────────────────
    "creature_type": "Undead",

    # ── NEW: Size (§8 — footprint > 1×1 is future work) ─────────────────
    "size": "Medium",                           # "Small"/"Medium"=1×1, "Large"=2×2, "Huge"=3×3

    # ── NEW: Movement modes (§9 — deliberately minimal) ─────────────────
    "movement": {"fly": false, "swim": false},

    # ── NEW: Senses (§10) ───────────────────────────────────────────────
    "senses": {"sight": 8, "darkvision": true, "blindsight": 0},

    # ── NEW: Traits — passive, always-on (§11) ──────────────────────────
    "traits": [ {"id": "undead_fortitude", "dc_base": 5} ],

    # ── Actions / multiattack / limited-use abilities (§12; ability shape
    #    owned by ENEMY_SYSTEM_ARCHITECTURE.md §3 — cooldown dicts) ──────
    "multiattack": [
        {"name": "Claw", "count": 2, "dmg_min": 1, "dmg_max": 4, "damage_type": "Slashing"},
        {"name": "Bite", "count": 1, "dmg_min": 2, "dmg_max": 6, "damage_type": "Piercing"},
    ],
    "abilities": [
        {"id": "bone_shard_volley", "cooldown": 4, "range": 5, "dmg_min": 2, "dmg_max": 5,
         "damage_type": "Piercing"},
        {"id": "dread_shriek", "uses_max": 1},       # per-life limited use
        {"id": "fire_breath", "recharge": 5},        # d6 recharge 5-6, alternative timer
    ],

    # ── NEW: Reactions (§13) ────────────────────────────────────────────
    "reactions": [ {"id": "bony_counter", "trigger": "melee_missed_by_adjacent"} ],

    # ── NEW: Conditional triggers (§14) ─────────────────────────────────
    "triggers": [ {"when": "hp_below_pct", "pct": 30, "do": "flee"} ],

    # ── NEW: Boss-tier fields (§15, BOSS_POOL only) ─────────────────────
    "legendary_resistances": 3,
    "magic_resistance": true,                   # reserved, see §15
}
```

Naming conventions: damage types are the same free-form capitalized strings the combat log already
uses (`"Slashing"`, `"Piercing"`, `"Bludgeoning"`, `"Poison"`, `"Fire"`, `"Necrotic"`, `"Radiant"`,
`"Psychic"` — see `scripts/items/CLAUDE.md`'s damage-type note). Condition names are lowercase and
match the game's own status vocabulary (§6). Ability keys inside `mods`/`check_profs` are lowercase
3-letter (`"str"`, `"dex"`, `"con"`, `"int"`, `"wis"`, `"cha"`).

---

## 3. CR vs. the floor-linear scaling formula

Today difficulty is entirely the floor-scaling formula in `Enemy._apply_stats()`:

```
max_hp      = type["hp"]      + (floor_num - 1) * type["hp_per_floor"]
armor_class = type["ac"]      + floor_num / 5
min_damage  = type["dmg_min"] + (floor_num - 1) / 3
max_damage  = type["dmg_max"] + (floor_num - 1) / 2
```

plus `floor_min`/`floor_max` spawn bands. There is no CR. The owner wants CR as a real concept for
encounter/floor difficulty.

**Recommendation: CR *informs spawning*, floor scaling *stays* (for now) as the within-band knob.
CR does not replace the formula.** Concretely:

- `"cr"` is an authored per-entry field describing the monster's strength *at its authored baseline
  stats* (its `floor_min`, roughly). D&D fractional CRs are fine (`0.125`, `0.25`, `0.5`, `1`, …).
- **Floor population** becomes CR-budgeted: each floor gets an encounter budget (e.g.
  `budget = base + floor_num * k`, tuned constants) and the spawner picks enemies whose summed CR
  fits the budget, instead of (or layered on) today's pure count-based spawn. This is where CR earns
  its existence: it lets a future "1 ogre vs. 4 goblins" tradeoff be a data decision, and gives
  boss/elite variants a principled cost.
- **The floor-linear stat formula is kept unchanged** as the within-band scaler so a floor-5 Orc
  Warrior stays scarier than a floor-1 one. CR describes the *baseline*; the formula handles drift
  inside the `floor_min..floor_max` band, which is narrow (3–5 floors) so the drift never invalidates
  the CR ordering between monsters.

**Rejected: CR replaces floor scaling** (pure static stat blocks, difficulty only via which monsters
spawn). That's the D&D-pure answer, but it forces authoring many more monster entries to fill a
smooth difficulty curve (a 10+ floor game needs a dense CR ladder), and it invalidates every current
pool entry's tuning at once. Not worth it while the bestiary is ~12 entries. Revisit if/when the
bestiary is large enough that per-floor bands can be narrow and densely populated — at that point
shrink `hp_per_floor` etc. toward 0 per-entry rather than deleting the formula.

**Rejected: deriving CR automatically from hp/ac/dmg.** Tempting (no new field to author), but CR is
exactly the place where a designer overrides math — a low-HP enemy with a nasty ability (Orc Shaman
poison) is worth more than its numbers. Authored field, sanity-checked by eye.

Default when absent: treat as `"cr": 0.25` (or simply exclude the entry from CR-budgeted logic until
all entries are annotated — annotate all ~12 in one sweep when the budget spawner lands, it's a
15-minute task).

**`exp` becomes CR-derived (owner-decided).** Today `exp` is authored by hand per entry, independently
of anything else — a second difficulty number that can silently drift from CR once both exist.
Once `cr` is annotated, derive `exp` from it instead of hand-tuning both:
`exp = round(cr_to_xp(cr) * scale)`, using 5e's own CR→XP table as the base curve (CR 1/4 → 50 XP,
CR 1/2 → 100, CR 1 → 200, CR 2 → 450, …) and one project-wide `scale` constant chosen so CR 0.25 lands
near today's ~8 XP (i.e. `scale ≈ 8/50 = 0.16`) — tune `scale` once against the existing ~12 entries'
current `exp` values, then let CR drive every entry going forward. Author `cr`, stop authoring `exp`
by hand. Existing hand-authored `exp` values are the calibration data for picking `scale`, not values
to preserve exactly — small per-entry drift when the sweep lands is expected and fine.

---

## 4. Ability scores, checks, and proficiency

The project convention is **checks, not saving throws** — the player has `check_prof_str/con/...`
flags on `Stats`, and enemy-side resistance to effects is already `Enemy.resist_check(dc, use_con)`
(`d20 + floor/3 + str_or_con_modifier` vs DC — see `scripts/entities/CLAUDE.md` "Enemy resist
checks"). The stat block generalizes what feeds that roll; it does **not** invent a parallel check
system.

- **`"mods"`: Dictionary of the 6 ability modifiers** (not raw scores). Replaces the ad-hoc top-level
  `"str_mod"`/`"con_mod"` keys, which stay supported as a fallback read during migration
  (`mods.get("str", type.get("str_mod", 0))`). We store modifiers, not scores, because nothing
  enemy-side ever reads a raw score — `_apply_stats()`'s current `10 + mod * 2` reverse-conversion
  into `Stats.strength/constitution` exists only so `Stats.modifier()` can round-trip it. With a
  `mods` dict, `resist_check_detailed()` can read the modifier directly. Absent key = 0.
- **`"prof_bonus"`: int.** Default derived from CR, D&D-style: `2 + max(0, ceil(cr) - 1) / 4`
  (CR 1–4 → +2, 5–8 → +3, …), so most entries never need to write it. This *replaces* the current
  implicit `floor_num / 3` bonus in `resist_check()` and `_attack_player()` for entries that opt in —
  see the migration note below.
- **`"check_profs"`: Array of ability keys** that add `prof_bonus` to that ability's checks — the
  exact mirror of the player's `check_prof_*` flags, expressed as data. `resist_check_detailed()`
  becomes: `d20 + mods[stat] + (prof_bonus if stat in check_profs else 0)` vs DC, and its returned
  breakdown dict keeps working with the existing Topple-style `save:` tooltip (the `prof_label`
  param already exists for relabeling the bonus line — label it `"Proficiency"` for entries with real
  `prof_bonus`, `"Floor"` for legacy entries still on `floor/3`). `resist_check()` also grows a
  `stat: String` param (default keeps today's STR/CON pair working) so future effects can contest
  DEX/WIS/etc. without a new function.
- **`"attack_prof"`: bool, default `true`** — whether `prof_bonus` applies to attack rolls. Enemy
  attack rolls today are `d20 + floor_num / 3`; a stat-block entry's roll becomes
  `d20 + mods[attack_stat] + prof_bonus`, where `attack_stat` comes from the `attack_profile`
  (`"str"` default melee, `"dex"` for ranged) — resolved inside the shared `_resolve_attack_roll()`
  extraction that `ENEMY_SYSTEM_ARCHITECTURE.md` §2 already mandates.

**Migration note (important):** `floor/3` (attack) and `floor/3` (resist) are the legacy stand-ins
for "modifier + proficiency". An entry that supplies `"mods"`/`"prof_bonus"` switches to the real
formula **instead of** the floor bonus — never both, or every migrated enemy silently gets stronger.
Gate on key presence: `if type.has("mods"): new formula else: legacy floor formula`. This is the same
opt-in-per-entry pattern as `attack_profile`.

**Rejected: named skill bonuses (Perception, Stealth, Intimidation…).** Considered for 1:1 fidelity
and deliberately not included: the game has no enemy-side skill rolls today, and every 5e monster
skill bonus is just "ability modifier + proficiency (sometimes doubled)" — which `mods` +
`check_profs` already expresses for everything the game actually rolls. If a future stealth mechanic
needs enemy Perception, add a `"skills": {"perception": 4}` flat-bonus dict then, not now.

---

## 5. Damage resistances, immunities, vulnerabilities

**Naming (owner-decided):** these are `"damage_resistances"` / `"damage_immunities"` /
`"damage_vulnerabilities"` — the `damage_` prefix disambiguates them from `"condition_immunities"`
(§6), which gates a completely different thing (a status, not a damage type). This was open question
6; it's settled now, before any real entry ships, per the "pick once, before the annotation sweep"
rule below.

House rule (owner decision): **resist = ×0.5, vulnerability = ×2.0, immunity = ×0** — explicit
multipliers, not 5e's halve-only model. This system currently does not exist on the enemy side at all
(Rage DR is player-side only, inside `GameState.take_damage_raw()`).

Schema: three optional flat arrays of damage-type strings — `"damage_resistances"`,
`"damage_immunities"`, `"damage_vulnerabilities"`. A type appearing in more than one list is an
authoring error; resolve immunity > vulnerability > resistance and push a warning at configure time.

**Where the multiplier applies — the chokepoint decision.** Player-side damage funnels through
`GameState.take_damage_raw(amount, ignore_rage, damage_type)`; the enemy side has no equivalent —
call sites (player `_bump_attack()`, cleave/off-hand/OA resolvers, `PlayerRanged.ranged_attack()`,
thrown weapons, companion, traps) each call `enemy.stats.take_damage(total)` directly, after summing
all bonus sources per the damage-stacking rule (one number, one floater, one log line).

**Decision: add one enemy-side mirror of `take_damage_raw` —
`Enemy.take_typed_damage(amount: int, damage_type: String) -> Dictionary`** — returning
`{ "dealt": int, "mult": float }`, which:

1. looks up the multiplier from the three lists (default ×1.0; empty/unknown `damage_type` = ×1.0,
   mirroring how `take_damage_raw` bypasses Rage DR on missing type);
2. applies it **once, to the already-summed total** — i.e. *after* the call site has folded Frenzy /
   Ironwood Bark / Divine Fury / crit into one number. This preserves the damage-stacking rule
   verbatim: still exactly one `stats.take_damage()` call, one floater, one log line, and the
   multiplier can never double-apply to a bonus source;
3. returns the multiplier so the call site can annotate the **tooltip** (a `mult=0.5` field on the
   existing `dmg:` meta → one extra line "Resisted (Slashing): ×0.5" in `fmt_dmg_tooltip()`), while
   the visible log line stays terse per the no-per-source-text rule. Immunity (`dealt == 0`) may log
   a distinct gray "It is unharmed." line instead of a `0` floater — the one carve-out, since a zero
   damage number is more confusing than informative.

Call sites migrate mechanically: `enemy.stats.take_damage(total)` →
`enemy.take_typed_damage(total, damage_type)`. Every player attack call site already knows its
damage type (it logs it).

**Interaction with `Stats.take_damage`'s `maxi(1, dmg)` floor:** the minimum-1 rule must not defeat
immunity. `take_typed_damage` handles ×0 by returning early without calling `stats.take_damage()` at
all; resist rounding is `maxi(1, int(amount * 0.5))` for nonzero multipliers, so resistance never
fully negates.

**Weapon-property-gated resistance (future extension, specced not built):** 5e's "resistant to
Slashing from nonmagical/non-silvered attacks" becomes, when the game has magic/silvered weapons, a
qualifier suffix on the list entry — `"damage_resistances": ["Slashing/nonmagical"]` — parsed at lookup time
and waived when the incoming attack's weapon carries the matching property (an `Item` bool, mirroring
`is_heavy`/`is_finesse`). No code until the first magic weapon exists; noted so the list format has a
forward-compatible convention and typically pairs with `creature_type` (§7) for authoring guidance.

**Rejected: multiplier inside `Stats.take_damage()` itself.** `Stats` is shared by player, enemy, and
companion; the player's typed-damage logic already lives in `GameState.take_damage_raw` and moving
both into `Stats` would tangle Rage DR (player-only) with R/I/V (enemy-only) in one function.
Symmetric wrappers per side, dumb shared `Stats.take_damage` underneath.

---

## 6. Condition immunities — a separate axis from damage immunity

These sound similar but gate different things, and D&D keeps them separate for good reason:

- **Damage immunity** (`"damage_immunities": ["Poison"]`, §5) multiplies incoming *damage* of that
  type by ×0 in `take_typed_damage()`.
- **Condition immunity** (`"condition_immunities": ["poisoned"]`) blocks the *status counter* from
  ever being set — the Skeleton never gains `poison_turns`, never ticks poison damage, never shows
  the green HUD dot, no matter what applied it (thrown flask, trap, future spell).

A monster can have one without the other (a Fire Elemental is immune to Fire damage but can still be
Poisoned; a construct might tick poison damage from a cloud yet be immune to the *poisoned* status in
some 5e blocks). In practice most entries set both — but the schema never auto-derives one from the
other.

Condition names are lowercase and match the game's own status vocabulary, which is the authoritative
list — not 5e's 15-condition list: `"poisoned"`, `"burning"`, `"bleeding"`, `"slowed"` (the four
`Stats` counters ticked by `tick_status()`), plus the enemy-side control fields `"prone"`
(`Enemy.prone_turns`, Topple), `"rooted"` (`Enemy.rooted_turns`, Grip of the Forest), and
`"forced_move"` (Push mastery / Branching Strike push — expressed as a condition immunity so a
gelatinous boss can simply not be shovable, independent of winning the contest roll).

**Chokepoint:** enemy status application is scattered today (call sites set `enemy.stats.poison_turns`
/ `enemy.prone_turns` directly). Add the enemy-side mirror of `GameState.apply_player_status()` —
`Enemy.apply_status(condition: String, turns: int) -> bool` — that checks `condition_immunities`,
returns whether it stuck, and logs a gray "It is unaffected." line on immunity. Call sites migrate
mechanically, same pattern as §5's damage chokepoint. Contest rolls stay upstream: Topple still rolls
`resist_check()` first; immunity is checked only when the effect would actually land (an immune
enemy's tooltip shows the roll, then "unaffected" — or skip the roll entirely when immune, simpler
and recommended).

**Rejected: adopting 5e's full condition list** (charmed, frightened, grappled, restrained, stunned,
paralyzed…). Each 5e condition only means something once a game mechanic implements it. The list
above is exactly the conditions this game *has*; new conditions join the vocabulary when their
mechanic lands.

---

## 7. Creature type

```gdscript
"creature_type": "Undead"
```

One plain capitalized string tag per entry, from the 5e vocabulary: `Aberration`, `Beast`,
`Celestial`, `Construct`, `Dragon`, `Elemental`, `Fey`, `Fiend`, `Giant`, `Humanoid`, `Monstrosity`,
`Ooze`, `Plant`, `Undead`. Default absent = untyped (treated as `Humanoid` by any consumer that must
pick something).

The tag does **nothing by itself** — it exists to be cheap to author now and consumed later:

- **Type-conditional damage rules** — the §5 weapon-property-gated resistances, and future effects
  like "Radiant deals ×2 to Undead" (a one-line check in `take_typed_damage()` when such an effect
  exists).
- **Class-talent synergies** — a future Paladin-vs-Fiend or Ranger favored-enemy style talent gates
  on `enemy._type.get("creature_type", "")`, exactly how boss-gated talents key off `boss_id` today.
- **Authoring guidance** — Undead usually get `"condition_immunities": ["poisoned"]` and Poison
  damage immunity; the doc records this as a *convention for humans*, never auto-derived in code.

**Rejected: deriving immunities/traits from creature type in code** (e.g. "all Undead are
auto-immune to poison"). Hidden rules that don't appear in the entry make stat blocks lie; every
effect a monster has must be readable from its dict. **Rejected: multiple tags / subtype arrays**
(`["Humanoid", "Goblinoid"]`) — one string until a mechanic needs a second tag.

---

## 8. Size — schema now, multi-tile occupancy later

```gdscript
"size": "Large"        # "Tiny"/"Small"/"Medium" = 1×1, "Large" = 2×2, "Huge" = 3×3
```

Default absent = `"Medium"`. The field is specced now so bestiary authoring is stable, but be clear
about the two very different costs hiding in it:

- **Cheap, immediate consumers (fine to build anytime):** sprite scale; forced-movement resistance
  flavor (a `Large+` enemy could get Advantage on Push/Topple contest rolls — one line in
  `resist_check_detailed()`, reusing the net-ADV/DISADV house rule); CR-budget weighting.
- **Expensive, explicitly future work: actual N×N grid occupancy.** A 2×2 boss touches nearly every
  spatial assumption in the codebase: `DungeonFloor` occupancy queries and `grid_pos` being a single
  tile, BFS pathfinding (a 2×2 body needs 2×2-wide corridors or wall-sliding rules), reach and
  adjacency (Chebyshev distance to *which* of the four tiles?), Opportunity-Attack threat range from
  a footprint instead of a point, fog/LOS anchor, forced movement of a multi-tile body, and spawn
  placement. **That is its own design doc when the first Large boss is actually wanted** — this doc
  only reserves the field and the N×N mapping. Until then, `size` above Medium renders a bigger
  sprite on a single tile (exactly what Big Demon does today) and nothing else.

---

## 9. Movement modes (deliberately minimal — owner's call)

The owner explicitly wants movement kept simple: no per-mode speeds, no speed stat at all (everything
moves 1 tile/turn). Just capability flags that let terrain stop mattering:

```gdscript
"movement": {"fly": true, "swim": false, "burrow": false}
```

- `"fly"`: ignores `CHASM`, `WATER`, and `MUD` movement penalties/blocking — a flying enemy path­finds
  over chasms the player must walk around.
- `"swim"`: ignores the `WATER` slow penalty only.
- `"burrow"`: reserved, no consumer (no dig-through-walls mechanic exists; do not implement until a
  monster concept needs it).

Implementation is a flag check at the existing terrain-cost/passability chokepoints in the enemy
movement path — the same chokepoints the player's Natural Sleeper forms already special-case
(Owl ignores chasm, Salmon ignores water, Panther ignores mud — see `scripts/entities/CLAUDE.md`).
This is the enemy-side mirror of that precedent: same checks, read from the pool dict instead of the
active form. No new pathfinding algorithm; BFS just treats the tile as normal floor for that enemy.

**Rejected: 5e speed values (30 ft walk, 60 ft fly) / multi-tile-per-turn movement.** A speed stat
implies enemies moving 2+ tiles per turn, which changes the entire approach/kite balance of a
1-tile-per-turn roguelike. `slowed_turns` (half speed) and the flags above cover the design space the
game actually plays in. Owner-confirmed low priority.

---

## 10. Senses

The shared floor FOV/fog system (`DungeonFloor.update_fog()`, `is_tile_visible()`,
`has_ranged_los()`) is the *player's* view of the world and stays untouched. Stat-block "senses" are
the individual enemy's perception parameters, layered on top — today these are hardcoded
(`WAKE_RADIUS_SQ = 4` for waking; chasing uses effectively unlimited LOS).

```gdscript
"senses": {"sight": 8, "darkvision": true, "blindsight": 0}
```

- `"sight"`: int, max Chebyshev distance at which this enemy can *notice* a target (gates the
  ROAMING/STATIONARY → CHASING transition; LOS still required via the existing raycast). Default:
  a project-wide constant matching current behavior, so absent = no change.
- `"darkvision"`: bool — reserved. The game has no light-level system yet; the field is specced now
  only so bestiary authoring doesn't need a schema change later. **No code reads it until a light
  system exists** (same "no speculative machinery" rule as ENEMY_SYSTEM_ARCHITECTURE.md §7 step 6).
- `"blindsight"`: int, radius within which the enemy senses targets **without LOS** (blind ooze,
  bat). Implementation: in target selection, a candidate within `blindsight` range counts as visible
  even if the LOS raycast fails. Default 0 = off.

Wake-from-sleep keeps its own tighter radius (`WAKE_RADIUS_SQ`) — sleeping is "can be snuck past",
not a sense.

**Rejected: tremorsense, truesight, passive Perception.** Each is a mechanic the game doesn't have;
add a key when the first monster needs it.

---

## 11. Traits (passive, always-on)

Traits are info/passive entries: auras, always-on effects, death riders, regeneration. Same dispatch
philosophy as everything else — the dict names the trait, code implements it:

```gdscript
"traits": [
    {"id": "undead_fortitude", "dc_base": 5},        # on lethal damage: CON check vs 5+dmg, survive at 1 HP
    {"id": "stench_aura", "radius": 1, "status": "poisoned", "turns": 2},
    {"id": "death_burst", "dmg_min": 3, "dmg_max": 6, "damage_type": "Fire", "radius": 1},
    {"id": "regeneration", "amount": 3, "shutoff_types": ["Fire", "Radiant"]},
]
```

- **State:** none by default. A trait needing per-instance state keeps it as a plain field on
  `Enemy`, same tier as `rooted_turns`/`oa_used_this_round` (e.g. once-per-life Undead Fortitude →
  one bool; regeneration → one `_regen_blocked_this_round` bool).
- **Dispatch points:** traits hook existing chokepoints, never new phases — aura ticks in
  `take_turn()` (before decide), on-death riders in the `Enemy.die()` override (which already exists
  for embedded thrown weapons), on-damaged hooks in `take_typed_damage()` (§5).
- **Regeneration (Troll-style), specced fully since the owner asked:** at the top of `take_turn()`,
  if `_regen_blocked_this_round` is false and HP < max, heal `amount` (green floater, one gray log
  line); then clear the flag. `take_typed_damage()` sets the flag whenever `damage_type` is in
  `shutoff_types`. Net effect: hit it with Fire this round and it skips next turn's heal — the exact
  5e loop, expressed with one bool and two hooks.
- Traits are **not** listed in `abilities` because they have no cooldown/decision component — the
  `_decide_action()` loop never considers them; they fire from their hook unconditionally.

There is no trait UI; if a future bestiary/examine screen wants to show them, `"id"` plus a
lookup-table description string is enough — do not add per-trait description fields to the pool until
that screen exists.

---

## 12. Actions: multiattack, limited-use, recharge, "spells"

**Ability shape is owned by `ENEMY_SYSTEM_ARCHITECTURE.md` §3 — this doc changes nothing about it.**
Actions are the `"abilities"` array of plain dicts, cooldowns tracked in `Enemy._ability_cooldowns:
Dictionary`, dispatched by one `match ability_id:` in `_execute_action()`, calling existing
chokepoints (`GameState.apply_player_status()`, `DungeonFloor.force_move_entity()`,
`resist_check()`, the spawn path). The default melee attack is *not* an entry in `abilities` — it
remains the implicit fallback action, as today.

### Multiattack

Enemies currently make exactly one attack per turn. 5e monsters routinely make several, possibly
different, attacks:

```gdscript
"multiattack": [
    {"name": "Claw", "count": 2, "dmg_min": 1, "dmg_max": 4, "damage_type": "Slashing"},
    {"name": "Bite", "count": 1, "dmg_min": 2, "dmg_max": 6, "damage_type": "Piercing"},
]
```

Absent = one attack using the top-level `dmg_min`/`dmg_max` (today's behavior). When present, the
`"attack"` intent's execution loops the sub-attacks in order and calls the **same shared
`_resolve_attack_roll()`** once per swing — separate roll, separate floater, separate log line per
swing (each swing is its own attack, so the one-log-line rule applies per attack, not per turn; this
mirrors how the player's Off-hand/Nick bonus attacks already log). **Do not write a second
attack-roll function.** Stop the loop immediately if the target dies or the game ends mid-sequence.
Sub-attack `"name"` appears in the log line ("The Bugbear's Bite hits you…") — flavor text, not a
mechanic name, so it doesn't violate the no-mechanic-names log rule. Optional per-sub-attack keys:
`"reach"`, `"attack_stat"`, on-hit `"status"`+`"turns"` (routed through §6's `apply_status`).

**Bonus actions — deliberately not modeled (owner's call).** 5e's action/bonus-action/movement
economy doesn't exist in a one-action-per-turn roguelike. A monster whose 5e block says "bonus
action: X" is authored here as either a multiattack entry or an ability — same result, no new
turn-economy concept.

### Limited-use and recharge — three timer types, one dict

All three reuse the `_ability_cooldowns`-style per-instance Dictionary; they differ only in how the
gate re-opens:

- **`"cooldown"`: int** — flat counter, decrements every `take_turn()` (already specced in
  ENEMY_SYSTEM_ARCHITECTURE.md §3, unchanged).
- **`"uses_max"`: int** — per-life budget ("innate spellcasting 3/day"), tracked in a parallel
  `Enemy._ability_uses` Dictionary initialized at `configure()`. Enemies don't rest, so per-day /
  per-encounter / per-life all collapse into this one counter — no rest-recharge machinery.
- **`"recharge"`: int** — the D&D "Recharge 5–6" die: after use the ability is spent; at the start of
  each `take_turn()` roll d6, and on `>= recharge` it re-arms. Same dict, the stored value just means
  "spent, re-rolling" instead of "counting down". An *alternative* timer to `cooldown`, not a
  replacement — an ability may combine `recharge` with `uses_max`, but `cooldown` + `recharge`
  together is an authoring error.

### "Spells" / innate spellcasting

Deliberately collapsed into the abilities list — a 5e "Innate Spellcasting: 3/day each: *hold
person*, *misty step*" block is authored as ordinary abilities with `"uses_max": 3`. No spell-slot
levels, no components, no concentration: none of those exist as game mechanics, and the abilities
list already covers targeting, cooldown, damage, and status application. If a player spellcasting
system ever introduces shared concepts (spell levels, counterspell), revisit; until then a "spell"
is an ability with flavor. (`slow_bolt`, `summon_skeleton` in the architecture doc are already spells
in all but name.)

### Legendary Actions — explicitly deferred, not designed

True legendary actions (a shared per-round action-point pool spent *between other combatants' turns*)
are the one thing per-ability cooldown dicts can't express — a shared resource across actions *and*
a turn-economy change. See §15 for the sketch and why it's future work.

---

## 13. Reactions

The precedent is Opportunity Attacks (`scripts/entities/CLAUDE.md` "Opportunity Attacks" — note its
referenced `docs/architecture/opportunity-attacks-design.md` is not currently present in the repo;
the CLAUDE.md section is authoritative). The OA model to mirror exactly:

- **inline, synchronous resolution** at the moment of the trigger — no `TurnManager` phase change,
  no turn cost (same as `try_retaliation()`);
- **once per round**, via a per-entity flag reset at top of `take_turn()`
  (`Enemy.oa_used_this_round` already exists — reactions share it: **one reaction per round total**,
  OA included, matching D&D's single-reaction economy and avoiding a second flag).

Schema:

```gdscript
"reactions": [
    {"id": "bony_counter", "trigger": "melee_missed_by_adjacent"},
    {"id": "shield_parry", "trigger": "hit_by_ranged", "cooldown": 3},
]
```

- `"trigger"` is an enum-by-convention string; each trigger has exactly one hook site in existing
  code, added when the first monster uses it:
  - `"target_leaves_reach"` — this is OA itself; every melee enemy has it implicitly today
    (hardcoded in `player.gd._resolve_enemy_opportunity_attacks()`). Making it data would let a
    sluggish zombie *not* get OAs — worth doing only if such a monster is designed; until then OA
    stays implicit and the schema documents it as reserved.
  - `"melee_missed_by_adjacent"` — hook in the player-attack miss branch.
  - `"hit_by_ranged"` / `"damaged"` — hook in `take_typed_damage()` (§5).
- Reaction *effects* dispatch through the same `match id:` pattern as abilities.

**Rejected: a generic trigger→effect scripting mini-language** (`"when": {...}, "effect": {...}`
composable trees). Two-field dicts + one hook per trigger string is the talent-system pattern and is
enough for a bestiary of this size; a rules engine is the classic solo-dev tarpit.

---

## 14. Conditional triggers ("if X then Y" behavior)

Distinct from reactions (which interrupt someone else's action): triggers modify the enemy's **own
decision** in `_decide_action()` — exactly the seam `ENEMY_SYSTEM_ARCHITECTURE.md` §1 built and §4
(boss phases) already exploits. Boss `"phases"` are in fact the first trigger type
(`hp_below_pct` → merge overrides); this section generalizes the read for non-boss enemies without
adding machinery:

```gdscript
"triggers": [
    {"when": "hp_below_pct", "pct": 30, "do": "flee"},            # cowardly goblin
    {"when": "ally_died_in_sight", "do": "enrage", "dmg_bonus": 2},
    {"when": "player_adjacent_count", "at_least": 2, "do": "use_ability", "ability_id": "whirlwind"},
]
```

- Evaluated at the top of `_decide_action()`, after phase merge, before target selection. A matched
  trigger either **overrides the intent** (`"flee"`, `"use_ability"`) or **merges stat overrides**
  for this turn's decision (same non-mutating merge-over-`_type` trick as boss phases).
- `"do"` values are, again, dispatch-by-string with one implementation each. Start with `"flee"`
  (step away from target — the inverse of `_act_toward`) since it's the most commonly wanted.
- Keep triggers **stateless** where possible (recompute from current HP/positions each turn); a
  trigger needing memory (`ally_died_in_sight`) gets one bool on `Enemy`, set at the observing
  moment, same tier as `just_crossed_door`.

---

## 15. Boss-tier: Legendary Resistance, Legendary Actions, Magic Resistance

`BOSS_POOL`-only fields (nothing stops an elite regular from using them, but that's the intent):

- **Legendary Resistance — cheap, design it now, and owner-confirmed for a near-term boss:**
  `"legendary_resistances": 3`. Consumed inside `resist_check_detailed()`: if the roll *fails* and
  the counter is > 0, decrement and force a pass. Per-life counter (enemies don't rest, so "3/day" =
  3/life), one int field on `Enemy`, initialized at `configure()`. The existing `save:` tooltip gains
  a line ("Legendary Resistance: forced success") and the log shows a gray "It shrugs off the
  effect." — the failed die roll stays visible in the tooltip so the player learns the counter is
  being burned, which is the entire fun of the mechanic in 5e.
  **Target: `big_demon`** (`BOSS_POOL`, floor 5) — the only current boss it makes sense to try it on
  first: it's the earlier/simpler of the two existing bosses (`necromancer` at floor 10 is the other
  candidate, but Legendary Resistance is more interesting once the boss also has forced-movement or
  resist-check-contested talents attacking it — Grip of the Forest, Branching Strike push, Topple —
  all of which are already live by floor 5). Add `"legendary_resistances": 3` to `big_demon`'s pool
  entry in the same pass that lands step 2 below (§4's `mods`/`prof_bonus` work) — it needs nothing
  else from this doc's schema to function standalone.
- **Legendary Actions — sketch only, deliberately future work:** a shared per-round pool
  (`"legendary_actions": {"per_round": 3, "options": [{"id": ..., "cost": 1}, ...]}`) spent between
  other combatants' turns. This is the one stat-block concept that genuinely doesn't fit the
  per-ability cooldown dict (shared resource across actions) *and* needs a turn-economy hook —
  something like an inline "after each friendly entity's action, let the boss spend a point"
  callback, modeled on the OA precedent (inline resolution, no `TurnManager` phase change) but not
  identical to it. Per the "no speculative machinery" rule, this gets its **own design doc when the
  first legendary boss is designed** — same deferral as multi-tile size (§8). Boss phases + reactions
  cover most of the feel until then.
- **Magic Resistance — reserved bool, one paragraph on purpose:** `"magic_resistance": true` would
  mean Advantage on checks against spells/magical effects. The game has no player spellcasting yet,
  so there is nothing to resist; when spells land, implementation is one line in
  `resist_check_detailed()` (add an Advantage source when the incoming effect is flagged magical),
  reusing the net-ADV/DISADV house rule. Field reserved, no code, deliberately not designed further.

---

## 16. Considered and deliberately out of scope

For the record — these 5e stat-block sections were evaluated and dropped, not missed:

- **Alignment** — no morality/faction mechanics; pure flavor text with no consumer.
- **Languages / telepathy** — no dialogue or communication system.
- **Environment / habitat** — `floor_min`/`floor_max` bands plus Floor Feelings already are the
  habitat system.
- **Swarm trait** — no sub-entity model; a "swarm of rats" here is just one monster with a swarm
  sprite and flavor.
- **Mythic actions, lair actions, regional effects** — boss phases (`ENEMY_SYSTEM_ARCHITECTURE.md`
  §4) and Floor Feelings already occupy this design space; a "lair action" is a boss-room trap/hazard
  authored with existing floor machinery.
- **Speed values / bonus actions** — owner-directed simplifications, see §9 and §12.

---

## 17. Worked example A — `orc_warrior`, before → after

Before (today, unchanged from `dungeon_floor_data.gd`):

```gdscript
{"enemy_id": "orc_warrior", "display_name": "Orc Warrior", "sprite": "orc_warrior",
 "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,
 "hp": 8, "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 11, "exp": 8}
```

After (full stat block — note the diff is purely additive):

```gdscript
{"enemy_id": "orc_warrior", "display_name": "Orc Warrior", "sprite": "orc_warrior",
 "idle_frames": 4, "run_frames": 4, "floor_min": 1, "floor_max": 5,
 "hp": 8, "hp_per_floor": 2, "dmg_min": 1, "dmg_max": 4, "armor": 0, "ac": 11, "exp": 8,
 "cr": 0.25,
 "creature_type": "Humanoid",
 "mods": {"str": 2, "dex": 1, "con": 2, "int": -1, "wis": 0, "cha": 0},
 "prof_bonus": 2,
 "check_profs": ["str"],
 "senses": {"sight": 8, "darkvision": true}}
```

What changed at runtime: its attack roll becomes `d20 + 2 (STR) + 2 (prof)` instead of
`d20 + floor/3`; Grip of the Forest's pull now contests `d20 + 2 + 2` (STR is proficient) instead of
`d20 + floor/3 + str_mod`; it notices the player at 8 tiles instead of the global default. No
resist/trait/action keys — a plain melee grunt stays a five-second authoring job.

## 18. Worked example B — `skeleton`, exercising the whole schema

```gdscript
{"enemy_id": "skeleton", "display_name": "Skeleton", "sprite": "skelet",
 "idle_frames": 4, "run_frames": 4, "floor_min": 4, "floor_max": 7,
 "hp": 9, "hp_per_floor": 2, "dmg_min": 3, "dmg_max": 6, "armor": 1, "ac": 12, "exp": 9,
 "cr": 0.25,
 "creature_type": "Undead",
 "size": "Medium",
 "mods": {"str": 0, "dex": 2, "con": 2, "int": -2, "wis": -1, "cha": -3},
 "prof_bonus": 2,
 "check_profs": ["con"],                       # hard to knock down / push (Topple, Push mastery)
 "damage_vulnerabilities": ["Bludgeoning"],    # maces smash bones: ×2.0
 "damage_immunities": ["Poison"],              # poison damage: ×0
 "damage_resistances": ["Piercing"],           # arrows rattle through ribs: ×0.5
 "condition_immunities": ["poisoned"],         # the status never sticks either (separate axis, §6)
 "senses": {"sight": 8, "darkvision": true},
 "traits": [ {"id": "undead_fortitude", "dc_base": 5} ],
 "abilities": [
     {"id": "bone_shard_volley", "cooldown": 4, "range": 5,
      "dmg_min": 2, "dmg_max": 5, "damage_type": "Piercing"},
 ],
 "reactions": [ {"id": "bony_counter", "trigger": "melee_missed_by_adjacent"} ]}
```

Walkthrough of one fight against it:
- Player hits with a Maul (Bludgeoning) for a summed 7 (base + Frenzy): call site invokes
  `take_typed_damage(7, "Bludgeoning")` → ×2.0 → 14 dealt, one floater "14", one log line "… for
  **14** Bludgeoning damage", tooltip shows the Frenzy line *and* "Vulnerable (Bludgeoning): ×2.0".
- Maul's Topple mastery: skeleton contests with `d20 + 2 (CON) + 2 (prof, CON proficient)` — the
  existing `save:` tooltip shows the breakdown with `prof_label="Proficiency"`.
- Lethal hit → Undead Fortitude trait fires in `take_typed_damage()`'s death branch: CON check vs
  `5 + damage_dealt`; on success it survives at 1 HP (once per life — one bool on `Enemy`).
- Player *misses* in melee → `bony_counter` reaction: one free counter-swing, inline, consuming its
  shared once-per-round reaction (so it cannot also OA that round).
- At range 5 with LOS and cooldown ready, `_decide_action()` may pick `bone_shard_volley` (Piercing,
  resolved through the shared `_resolve_attack_roll()`), else it approaches as a normal melee enemy.
- A poison source: damage side ×0 (`damage_immunities`), and the *poisoned status* is separately
  blocked by `condition_immunities` via `Enemy.apply_status()` — gray "It is unaffected." line. Both
  axes fire independently, which is exactly why they're two lists.

A third mini-example for multiattack + regeneration + recharge (a future "Cave Troll" boss):

```gdscript
{"boss_id": "cave_troll", "display_name": "Cave Troll", ..., "cr": 5,
 "creature_type": "Giant", "size": "Large",            # Large = big sprite only, until §8's future doc
 "mods": {"str": 4, "dex": 1, "con": 5, "int": -2, "wis": 0, "cha": -2},
 "check_profs": ["str", "con"],
 "multiattack": [
     {"name": "Claw", "count": 2, "dmg_min": 2, "dmg_max": 6, "damage_type": "Slashing"},
     {"name": "Bite", "count": 1, "dmg_min": 3, "dmg_max": 8, "damage_type": "Piercing"},
 ],
 "traits": [ {"id": "regeneration", "amount": 5, "shutoff_types": ["Fire"]} ],
 "abilities": [ {"id": "boulder_toss", "recharge": 5, "range": 6,
                 "dmg_min": 6, "dmg_max": 12, "damage_type": "Bludgeoning"} ],
 "legendary_resistances": 2}
```

---

## 19. Open questions (decide when the first consumer lands, not now)

1. **Player-side R/I/V symmetry** — should the player ever gain typed resistances beyond Rage DR
   (e.g. a Ring of Fire Resistance)? If yes, `GameState.take_damage_raw()` grows the same
   three-list lookup. Out of scope here; noted so both sides converge on the same ×0.5/×0/×2 rule.
2. ~~Does `exp` become CR-derived?~~ — **decided: yes** (see §3's updated recommendation). Formula
   and rounding are the only remaining detail, settled in the same sweep that annotates CR.
3. **Multiattack vs. floor damage scaling** — per-sub-attack dice bypass the top-level
   `dmg_min`/`dmg_max` floor-scaling lines; decide whether sub-attacks scale the same way
   (recommended: yes, apply the same `(floor-1)/3` and `(floor-1)/2` adders per sub-attack) when the
   first multiattacker lands.
4. **Encounter-budget formula constants** — pure tuning, playtest-driven; the schema only needs the
   `cr` field to exist.
5. **Examine/bestiary UI** — none of this schema is player-visible today. If an "inspect enemy"
   panel is ever wanted, the stat block is already the single source to render from — and would be
   the first consumer that makes `creature_type`/`size` player-facing.
6. ~~Renaming the damage trio~~ — **decided:** `"damage_resistances"` / `"damage_immunities"` /
   `"damage_vulnerabilities"` (§5), disambiguated from `"condition_immunities"` (§6). Applied
   throughout this doc; no further action needed before the first entry ships.

---

## 20. Immediate next steps (in order — no speculative machinery)

1. **Prerequisite check:** `ENEMY_SYSTEM_ARCHITECTURE.md` §7 steps 1–2 (decide/execute split,
   `_resolve_attack_roll()` extraction) should land first — §12–§15 here all assume those seams.
2. **`mods` + `prof_bonus` + `check_profs`** (§4): generalize `resist_check_detailed()` and the
   enemy attack roll, opt-in per entry via key presence, legacy `floor/3` path kept for unannotated
   entries. Migrate the entries already using `str_mod`/`con_mod`. `enemy.gd` +
   `dungeon_floor_data.gd` only.
3. **`take_typed_damage()` + the three damage R/I/V lists** (§5, keys `damage_resistances` /
   `damage_immunities` / `damage_vulnerabilities` — naming already settled, no decision needed here)
   **and `apply_status()` + `condition_immunities`** (§6) in the same session — both are "add one
   enemy-side chokepoint, migrate call sites mechanically" changes and share the tooltip/log
   conventions. Prove with one enemy (Skeleton: Bludgeoning vulnerability + poisoned immunity are the
   most player-visible pair).
4. **`cr` + `creature_type` annotation sweep + CR-derived `exp` + CR-budgeted spawning** (§3, §7):
   annotate all ~12 pool entries with `cr`/`creature_type` in one pass, pick the `exp = cr_to_xp(cr) *
   scale` constant against today's hand-authored `exp` values (§3), stop hand-authoring `exp` from
   then on, then convert floor population to a CR budget. Keep the stat-scaling formula untouched.
5. **`senses.sight`** (§10): replace the hardcoded notice range with the pool key + default constant.
6. **`multiattack`** (§12): the loop over `_resolve_attack_roll()` — small, but only when the first
   multiattacking monster is designed.
7. **Legendary Resistance on `big_demon`** (§15): `"legendary_resistances": 3` plus the
   `resist_check_detailed()` consume-on-fail branch — ~15 lines once step 2 (`mods`/`prof_bonus`)
   exists, and the owner has already picked the target boss, so this can land as soon as step 2 does
   rather than waiting for "first boss that wants it."
8. **On concrete need only, otherwise:** movement flags (§9, first flyer), traits incl. regeneration
   (§11), `uses_max`/`recharge` (§12), reactions (§13), triggers (§14).
9. **Explicitly separate future design docs, not steps on this list:** multi-tile Large/Huge
   occupancy (§8) and Legendary Actions (§15). Do not start either without its own doc.
