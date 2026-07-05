# Spellcasting System — Design Doc

Status: **design only, nothing implemented.** This document specifies the framework a future
implementation session will follow. No code files ship with it.

Scope: a full D&D 5.5e (2024) spellcasting framework for the game — spell data model, spell
slots (long-rest, pact-magic, and enemy-cooldown variants behind one interface), prepared vs.
known spell lists, upcasting, concentration, BG3-style reactions, AoE targeting on the tile
grid, enemy casters, and the UI surfaces for all of it. Content depth is deliberately thin:
the framework plus **three worked example spells** (Fire Bolt / Magic Missile / Fireball) that
prove the data model. Full spell lists are future work.

All file paths, function names, and signals below were verified against the working tree at
time of writing (`player.gd`, `game_state.gd`, `turn_manager.gd`, `stats.gd`,
`player_ranged.gd`, `enemy.gd`, `dungeon_floor.gd`, sub-directory CLAUDE.md files). Re-verify
line-level details before editing, but the names and structure are authoritative.

Owner decisions listed in §1.1 are **fixed requirements** — this doc designs around them, it
does not re-litigate them.

---

## 1. Overview / goals

The game has four classes today (`Stats.CharacterClass`: BARBARIAN, RANGER, WIZARD, MONK) and
zero spells. The Wizard exists as a stat block only — d6 HD, INT 16 / DEX 14 / WIS 12,
INT+WIS check proficiency (`stats.gd apply_class_defaults()`), no abilities, no combat
identity. **Wizard is the first real integration target** of this system.

The framework must eventually cover: **full casters** (Bard, Cleric, Druid, Sorcerer, Wizard),
**half casters** (Paladin, Ranger), **pact-magic casters** (Warlock), and third-caster
subclasses of martials (Eldritch Knight / Arcane Trickster analogues). None of those besides
Wizard and Ranger exist yet — the point of designing the abstraction now is that adding them
later is data + a class-defaults branch, not a rewrite.

### 1.1 Fixed owner decisions

1. Framework + 2–3 example spells only; no full spell list.
2. The "alternate resource" caster archetype (Warlock pact magic: short-rest recharge, one
   shared slot level scaling with class level) is designed now as a reusable pattern even
   though no Warlock class exists.
3. Prepared vs. known spell lists are a real, load-bearing distinction in the data model
   (§4.4). Prepared-caster daily list size = spellcasting ability modifier + caster level
   (half-caster equivalent for Paladin/Ranger).
4. Every spell effect resolves from a `cast_at_level: int` parameter, never from the spell's
   base level (§5.2) — upcasting is first-class.
5. Concentration is implemented in full now (§7): one concentration spell per caster, CON
   save DC `max(10, damage/2)` on taking damage, break on failure, instant drop on
   death/incapacitation, UI indicator.
6. Action economy v1: spells are either a **full Action** or **free** (no separate
   bonus-action phase). Spells that are bonus actions in 5.5e are annotated as such in data
   but mechanically map to "free" or "action" per-spell. **Reactions ARE in scope**,
   BG3-style prompt-and-pause (§8).
7. Enemy casters can use either a full slot-tracking model or a simplified per-spell-cooldown
   model, chosen per-enemy via pool config; both share the same `cast_spell()` resolution
   path (§9).
8. AoE shapes (cone, sphere, line, cube) get concrete tile-grid algorithms now, with preview
   UI, reusing the existing ranged-targeting conventions (§6).
9. Half casters start casting at **level 2**, slots per the 5.5e half-caster progression,
   round up (owner decision — the doc does not revisit the 2024-PHB level-1 change).

### 1.2 Design principles (from repo conventions)

- **Spells are data + a thin dispatch, like abilities.** The existing pattern —
  `Ability.ability_id` dispatched in `player.gd._use_ability_slot()`, granted via
  `GameState.add_ability()` — is the template. Spells reuse the ability bar as their UI
  surface (§5.4) instead of inventing a parallel bar.
- **One resolution API, many bookkeepers.** `SpellEffects.cast_spell()` never knows whether
  the slot it consumed came from a Wizard's long-rest pool, a Warlock's pact pool, or an
  enemy cooldown timer — that lives behind `SpellSlotPool` (§4.3).
- **No second status system.** Spell-imposed conditions map onto the existing `Stats` status
  fields and `Enemy.prone_turns`/`rooted_turns`/`slowed_turns`/`disadv_next_attack` (§10.5).
- **Every damage number gets a tooltip meta** (`[url=kind:...]` + `fmt_kind_tooltip()`), and
  multi-source damage is summed before one `take_damage()` call — both root-CLAUDE.md RULEs
  apply unchanged to spell damage.
- **Every consumption site guards on `GameState.invincible`** — slot consumption included.
- **`TurnManager` stays untouched** except for the reaction await points (§8.3), which use
  GDScript's natural await-propagation through `take_turn()` rather than new phases.

---

## 2. Non-Goals / Explicitly Deferred to Later

- **Full spell lists** for any class. Three example spells only (§12).
- **Bonus Action as a turn-phase/resource.** Annotated in data (`is_bonus_action_in_5e`),
  not mechanical. Revisit when/if Extra Attack or a broader action-economy pass happens.
- **Ritual casting** — cut for v1 (§10.2 has the rationale and a future path).
- **Material component tracking / component pouches / free-hand Somatic checks** — cut for
  v1; annotation-only fields reserved (§10.1).
- **Multiclassing** — no dual-class characters exist or are planned near-term. §10.8 records
  how the slot table must combine when it happens, so the abstraction doesn't paint us into
  a corner, but no multiclass code ships.
- **Sorcery points / metamagic / ki** as implemented resources. §10.7 decides the pattern
  they should use (NOT `SpellSlotPool`) so the abstraction isn't over-built now.
- **Spell scrolls, spell learning via loot, spellbook-copying costs** — the Wizard's
  `known_spells` array is the spellbook and can be appended to by any future loot system;
  the loot system itself is out of scope.
- **Counterspell itself** — the reaction trigger `enemy_casts_spell` is designed and wired
  (§8.2) so Counterspell is a pure data+effect addition later, but the spell doesn't ship
  in v1 (no enemy casters exist yet to counter).
- **Summoning spells** — `Companion` exists and would be the vehicle, but summon spells
  interact with the one-companion assumption (`GameState.player_companion` is a single
  reference) and are deferred.
- **Warlock class itself** — only the `PactSlotPool` pattern ships; the class, its class
  select entry, invocations, etc. are future work.
- **Enemy reactions** (enemy Shield/Counterspell) — the broker auto-declines for AI in v1
  (§8.4); per-enemy reaction logic is a later balance pass.

---

## 3. Vocabulary & 5.5e reference tables (as adapted)

- **Caster level** — for a single-class character, just `Stats.character_level` (full
  casters) or `ceil(character_level / 2.0)` from level 2 (half casters, round up, owner
  decision). Exposed as `SpellcasterState.caster_level()` so multiclass can change one
  function later (§10.8).
- **Spell save DC** = `8 + proficiency_bonus + spellcasting ability modifier`.
- **Spell attack bonus** = `proficiency_bonus + spellcasting ability modifier`.
  Both computed live (never cached), mirroring `Stats.proficiency_bonus` /
  `Stats.mastery_cap()` precedent.
- **Standard slot table** (full caster; the game currently ends at floor 10 / roughly level
  12, so levels 1–12 are the practical range — table includes them all):

| Caster lvl | 1st | 2nd | 3rd | 4th | 5th | 6th |
|---|---|---|---|---|---|---|
| 1 | 2 | – | – | – | – | – |
| 2 | 3 | – | – | – | – | – |
| 3 | 4 | 2 | – | – | – | – |
| 4 | 4 | 3 | – | – | – | – |
| 5 | 4 | 3 | 2 | – | – | – |
| 6 | 4 | 3 | 3 | – | – | – |
| 7 | 4 | 3 | 3 | 1 | – | – |
| 8 | 4 | 3 | 3 | 2 | – | – |
| 9 | 4 | 3 | 3 | 3 | 1 | – |
| 10 | 4 | 3 | 3 | 3 | 2 | – |
| 11–12 | 4 | 3 | 3 | 3 | 2 | 1 |

- **Half caster**: slots as if a full caster of level `ceil(class_level / 2)`, starting at
  class level 2 (level 1 = no slots).
- **Pact magic table** (Warlock, per 5.5e):

| Class lvl | Slots | Slot level |
|---|---|---|
| 1 | 1 | 1 |
| 2 | 2 | 1 |
| 3–4 | 2 | 2 |
| 5–6 | 2 | 3 |
| 7–8 | 2 | 4 |
| 9–10 | 2 | 5 |
| 11–12 | 3 | 5 |

  All pact slots share ONE level; they refill on **short rest and long rest**.
- **Cantrip damage scaling** (character level, not caster level — matters for future
  third-caster subclasses): dice count 1 / 2 / 3 / 4 at character levels 1 / 5 / 11 / 17.
- **Tile scale**: 1 tile = 5 ft. So Fire Bolt's 120 ft ≈ 24 tiles — far beyond
  `FOV_RADIUS = 7`. **Rule: no spell range ever exceeds the caster's live FOV** (same
  philosophy as ranged weapons' "long range is your FOV" rule in
  `scripts/items/CLAUDE.md`). Book ranges are re-tuned per spell to roguelike-sensible
  tile counts; the doc's example spells show the convention.

---

## 4. Data model

Five new Resource/helper classes. Directory placement follows existing precedent:
data resources beside `ability.gd`/`talent.gd` in `scripts/items/`, combat/static helpers in
`scripts/entities/` beside `combat_math.gd`.

```
scripts/items/spell.gd              Spell            (Resource — one spell definition)
scripts/items/spell_db.gd           SpellDb          (static helper — id → Spell factory, like DungeonFloorData)
scripts/items/spellcaster_state.gd  SpellcasterState (Resource — per-caster casting state)
scripts/items/spell_slot_pool.gd    SpellSlotPool + StandardSlotPool + PactSlotPool + CooldownSlotPool
scripts/entities/spell_shapes.gd    SpellShapes      (static helper — AoE tile math, §6.2)
scripts/entities/spell_effects.gd   SpellEffects     (static helper — cast_spell() resolution, §5)
scripts/entities/player_spellcasting.gd  PlayerSpellcasting (composition child-node, §5.4)
```

### 4.1 `Spell` (Resource)

```gdscript
class_name Spell
extends Resource

@export var spell_id: String = ""          # stable machine id, e.g. "fire_bolt"
@export var spell_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""         # res://icons/spells/<spell_id>.png (ResourceLoader.exists guard, mastery-picker precedent)
@export var level: int = 0                 # 0 = cantrip
@export var school: String = ""            # flavor only in v1 ("Evocation", ...)

# ── Action economy ───────────────────────────────────────────────
# "action"   → costs the turn (begin_player_action / on_player_action_complete)
# "free"     → no turn cost (Rage-activation precedent); used for 5.5e bonus-action spells in v1
# "reaction" → castable only via the ReactionBroker prompt (§8); reaction_trigger names when
@export var casting_time: String = "action"
@export var reaction_trigger: String = ""  # "about_to_be_hit", "falling_into_chasm", "enemy_casts_spell", "enemy_leaves_reach"
@export var is_bonus_action_in_5e: bool = false   # annotation only — future action-economy pass

# ── Duration / concentration ─────────────────────────────────────
@export var concentration: bool = false
@export var duration_turns: int = 0       # 0 = instantaneous; >0 = tracked ActiveSpellEffect (§4.6)

# ── Targeting ────────────────────────────────────────────────────
enum TargetKind { SELF, ENEMY, ALLY, TILE, DIRECTION }
@export var target_kind: TargetKind = TargetKind.ENEMY
@export var range_tiles: int = 1           # 0 = self only, 1 = touch/adjacent; ALWAYS additionally clamped to live FOV (§3)

# ── AoE (NONE for single-target) ─────────────────────────────────
enum Shape { NONE, SPHERE, CONE, LINE, CUBE }
@export var shape: Shape = Shape.NONE
@export var shape_size: int = 0            # sphere: radius; cone/line: length; cube: side
@export var shape_width: int = 1           # line only (tiles); cone arc is fixed 90° in v1
@export var hits_allies: bool = true       # false = enemies-only AoE (rare; most AoE is honest friendly-fire)

# ── Resolution ───────────────────────────────────────────────────
enum Resolution { ATTACK_ROLL, SAVE, AUTO_HIT }
@export var resolution: Resolution = Resolution.AUTO_HIT
@export var save_stat: String = ""         # "STR"/"DEX"/"CON"/"INT"/"WIS"/"CHA" (SAVE only)
@export var save_for_half: bool = false    # true → failed save full dmg, passed save half

# ── Generic damage/heal payload (covers most spells without custom code) ──
@export var dice_count: int = 0
@export var dice_sides: int = 0
@export var flat_bonus: int = 0
@export var damage_type: String = ""       # "" + dice_count>0 + is_heal → heal
@export var is_heal: bool = false
@export var upcast_dice_per_level: int = 0 # extra dice per slot level above `level`
@export var cantrip_tier_scaling: bool = false  # dice_count multiplied by the 1/5/11/17 tier (§3)

# ── Escape hatch for everything the generic payload can't express ──
@export var effect_id: String = ""         # "" = generic path; else dispatched in SpellEffects (§5.3)
@export var status_effect: String = ""     # applied on hit / failed save (maps per §10.5)
@export var status_turns: int = 0

# ── Class availability + v1-inert annotations ────────────────────
@export var class_list: Array[String] = [] # ["WIZARD", "SORCERER", ...] — filters learnable lists
@export var is_ritual: bool = false        # annotation only in v1 (§10.2)
@export var comp_verbal: bool = true       # annotation only in v1 (§10.1)
@export var comp_somatic: bool = true
@export var comp_material: String = ""     # human-readable; never consumed in v1
```

Rationale notes:

- **Generic payload first, `effect_id` second.** Fire Bolt and Fireball need zero custom
  code — pure data through the generic ATTACK_ROLL/SAVE + dice path. Magic Missile's
  multi-dart behavior is what `effect_id` exists for. This mirrors how `Talent.ranks` holds
  designer-chosen keys "only read by `_apply_talent_rank`" — data shapes are free-form where
  one dispatcher owns them.
- **`shape_width`/fixed 90° cone**: configurable arc was considered and rejected for v1 —
  no 5.5e cone is anything but the standard spread, and a tunable arc doubles the preview
  test matrix. The cone algorithm (§6.2) takes an arc parameter internally so widening later
  is a constant change.
- Spell definitions live in `SpellDb.get_spell(id) -> Spell` (static factory building the
  resource in code — same "no `.tres` files" convention as `SpriteFrames` and every Talent).
  A `SpellDb.CLASS_SPELL_LISTS: Dictionary` (class name → Array[spell_id]) is the "full class
  list" prepared casters prepare from.

### 4.2 `SpellcasterState` (Resource) — per-caster state

One instance per caster, stored as **`Stats.caster: SpellcasterState`** (default `null` =
non-caster). On `Stats` rather than `GameState` because enemies and (later) companions cast
too — exactly the reasoning that put `zealous_presence_turns` on `Stats` "so both Player and
Companion can carry it independently" (`scripts/entities/CLAUDE.md`).

```gdscript
class_name SpellcasterState
extends Resource

enum CastingType { NONE, FULL, HALF, PACT }
enum PrepMode { KNOWN, PREPARED }

@export var casting_type: CastingType = CastingType.NONE
@export var prep_mode: PrepMode = PrepMode.KNOWN
@export var spellcasting_ability: String = "INT"   # "INT"/"WIS"/"CHA"

# KNOWN casters: known_spells is the whole castable list; prepared_spells unused.
# PREPARED casters: known_spells = accessible list (Wizard: the spellbook; Cleric/Druid:
#   the full class list, kept as a copy here so the query API is uniform), prepared_spells
#   = today's castable subset.
@export var known_spells: Array[String] = []
@export var prepared_spells: Array[String] = []

var slot_pool: SpellSlotPool = null        # StandardSlotPool / PactSlotPool / CooldownSlotPool

# Concentration (§7)
var concentration_spell_id: String = ""    # "" = not concentrating
var concentration_cast_level: int = 0
var concentration_effect: ActiveSpellEffect = null   # back-ref for clean teardown

# Duration-tracked non-instant effects (§4.6). Concentration effects also live here;
# the concentration fields above are just the "which one is the concentration one" marker.
var active_effects: Array = []             # Array[ActiveSpellEffect]

func castable_spells() -> Array[String]:
    return prepared_spells if prep_mode == PrepMode.PREPARED else known_spells

func prepared_max(stats: Stats) -> int:    # owner decision: ability mod + caster level
    return maxi(1, _ability_mod(stats) + caster_level(stats))

func caster_level(stats: Stats) -> int:
    match casting_type:
        CastingType.FULL: return stats.character_level
        CastingType.HALF: return 0 if stats.character_level < 2 else ceili(stats.character_level / 2.0)
        CastingType.PACT: return stats.character_level   # pact uses its own table, not this
        _: return 0

func spell_save_dc(stats: Stats) -> int:
    return 8 + stats.proficiency_bonus + _ability_mod(stats)

func spell_attack_bonus(stats: Stats) -> int:
    return stats.proficiency_bonus + _ability_mod(stats)
```

- `spell_save_dc()` / `spell_attack_bonus()` / `prepared_max()` are **functions computed
  live**, never cached fields — the `mastery_cap()` lesson (a cached cap is a stale-cache
  trap across level-ups).
- The **prepared-list mutation UI** reuses the Mastery Picker pattern end-to-end: a
  "Prepare Spells" picker (layer-25 CanvasLayer, `GameState.spell_prep_open` input-block
  flag twin of `mastery_picker_open`) opens after class selection for prepared casters and
  is offered again after every completed long rest via the existing
  `mastery_reselect_prompt.gd`-style Yes/No confirm. Known-casters never see it; their list
  only changes on level-up. This is deliberately a copy of a proven flow, not shared code
  (two pickers is still below the extraction threshold noted in the mastery design doc §6;
  a third picker justifies extracting a base overlay class).

### 4.3 `SpellSlotPool` — the pluggable resource bookkeeper

The single abstraction owner decision #3 asked for. Base class defines the interface;
`cast_spell()` and all UI query it and never type-check the subclass.

```gdscript
class_name SpellSlotPool
extends Resource

# Which slot levels can pay for casting `spell` right now (already filtered to >= spell.level,
# already filtered to levels with remaining uses). Cantrips → [0] always.
func available_cast_levels(spell: Spell) -> Array[int]: return []
func can_cast(spell: Spell) -> bool: return not available_cast_levels(spell).is_empty()
func consume(cast_level: int) -> void: pass       # caller guards GameState.invincible BEFORE calling
func on_long_rest() -> void: pass
func on_short_rest() -> void: pass
func on_turn_tick() -> void: pass                 # cooldown model only; no-op elsewhere
func ui_summary() -> String: return ""            # "3/4 ● 2/3 ● 1/2" style HUD string
```

**`StandardSlotPool`** (full + half casters, long-rest recharge):

```gdscript
var owner_stats: Stats                    # to read character_level live
var casting_type: int                     # FULL or HALF — picks the caster_level formula
var remaining: Dictionary = {}            # slot_level:int → remaining:int

func _max_slots() -> Dictionary:          # computed LIVE from the §3 table + caster level
func available_cast_levels(spell) -> Array[int]:
    if spell.level == 0: return [0]
    var out: Array[int] = []
    for lv: int in _max_slots():
        if lv >= spell.level and remaining.get(lv, 0) > 0: out.append(lv)
    return out
func consume(cast_level): remaining[cast_level] -= 1
func on_long_rest():   remaining = _max_slots()   # full refill
func on_short_rest():  pass                       # standard slots do NOT short-rest recharge
```

`_max_slots()` computed live from the table + `caster_level()` means level-ups silently grow
maximums with zero sync code; only `remaining` is stored state. New slots gained on level-up
arrive **empty** and fill at the next long rest (consistent with the game's "level-up grants
only a talent point, never resources" rule in `gain_exp()`).

**`PactSlotPool`** (Warlock pattern — ships now, unused until a Warlock exists):

```gdscript
var owner_stats: Stats
var remaining: int = 0

func pact_slot_level() -> int:            # §3 pact table, computed live from character_level
func pact_slot_count() -> int:            # ditto
func available_cast_levels(spell) -> Array[int]:
    if spell.level == 0: return [0]
    if remaining > 0 and pact_slot_level() >= spell.level: return [pact_slot_level()]
    return []                             # pact slots ALWAYS cast at pact_slot_level — auto-upcast
func consume(_cast_level): remaining -= 1
func on_long_rest():  remaining = pact_slot_count()
func on_short_rest(): remaining = pact_slot_count()   # the pact-magic difference
```

Note what falls out for free: a Warlock's every leveled cast is automatically at max slot
level (`available_cast_levels` returns exactly one entry), so the upcast-selection UI (§5.4)
naturally shows no picker — no special-casing anywhere.

**`CooldownSlotPool`** (enemy simplified model, §9):

```gdscript
var cooldowns: Dictionary = {}            # spell_id → turns until ready (0 = ready)
var cooldown_max: Dictionary = {}         # spell_id → configured cooldown

func available_cast_levels(spell) -> Array[int]:
    return [spell.level] if cooldowns.get(spell.spell_id, 0) <= 0 else []
func consume_for(spell: Spell) -> void:   # cooldown pools key on spell, not level
    cooldowns[spell.spell_id] = cooldown_max.get(spell.spell_id, 3)
func on_turn_tick():
    for id in cooldowns: cooldowns[id] = maxi(0, cooldowns[id] - 1)
```

(Small API wart, acknowledged: cooldown consumption needs the spell id, not a level. Solution:
`consume(cast_level)` stays the shared signature and `SpellEffects.cast_spell()` calls a
wrapper `pool.consume_cast(spell, cast_level)` on the base class, which subclasses route to
whichever key they care about. One virtual method, no type checks at call sites.)

**Rest wiring**: `GameState.long_rest()` gains one line —
`if player_stats.caster != null: player_stats.caster.slot_pool.on_long_rest()` — inside the
existing single long-rest chokepoint, per the hard rule in `scripts/autoloads/CLAUDE.md`
("any new per-long-rest resource must be refilled in `long_rest()` and nowhere else").
Short-rest recharge hooks into `GameState._on_short_rest_completed()` (the same function that
already refreshes One with Nature) with the matching `on_short_rest()` call — a no-op for
standard pools, the full refill for pact pools.

### 4.4 Prepared vs. known — how the modes actually differ

| | KNOWN (Sorcerer/Bard/Ranger/Warlock) | PREPARED (Wizard/Cleric/Druid/Paladin) |
|---|---|---|
| `known_spells` | the castable list | the accessible list (Wizard: spellbook — grows only via level-up/scroll-study; Cleric/Druid/Paladin: a copy of `SpellDb.CLASS_SPELL_LISTS[class]`) |
| `prepared_spells` | unused (empty) | today's castable subset, size ≤ `prepared_max()` |
| Changes when | level-up only (learn N new, optionally swap 1 — level-up flow) | any long rest (Prepare Spells picker, §4.2), plus level-up growth of `known_spells` |
| `castable_spells()` | returns `known_spells` | returns `prepared_spells` |

One spell definition, one storage shape, one query function — the modes differ only in which
array `castable_spells()` returns and which UI mutates it. No spell data is ever duplicated
between the lists (they hold `spell_id` strings, resolved through `SpellDb`).

Wizard specifics: `known_spells` starts with 6 level-1 spells + 3 cantrips at class select
(cantrips are always castable and exempt from preparation — implementation: cantrips known
are auto-included in `castable_spells()`'s PREPARED branch, the one special case in that
function). "Learning from scrolls" later = `caster.known_spells.append(id)` from whatever
loot flow adds it; nothing here needs changing.

### 4.5 Concentration state

Lives on `SpellcasterState` (§4.2 fields). Full mechanics in §7. Deliberately NOT on
`GameState` — enemies concentrate too (a future enemy Bless-caster must be breakable by
focusing fire, which is the entire tactical point of concentration).

### 4.6 `ActiveSpellEffect` — duration-tracked effects

A plain inner class (RefCounted) — not worth a file:

```gdscript
class ActiveSpellEffect:
    var spell_id: String
    var cast_level: int
    var remaining_turns: int      # -1 = until-rest/until-dispelled (Mage Armor)
    var is_concentration: bool
    var data: Dictionary = {}     # effect-specific (e.g. {"ac_bonus": 3} for Mage Armor)
```

- Stored in `SpellcasterState.active_effects` **of the caster** (the caster maintains the
  spell; a buff placed on the companion still ticks on the caster's clock — matching 5e,
  and simpler than per-target tracking. Deviation from the `zealous_presence_turns`
  per-target precedent, justified: concentration teardown must find every effect of a
  broken spell instantly, which per-target storage makes O(all entities)).
- **Tick point**: player effects decrement in `player.gd._on_turn_started()` inside the
  existing `if not came_from_revert:` real-turn block (the same place Vex/Frenzy/per-round
  flags reset — an effect must not burn a turn on a Rager free-action chain). Enemy caster
  effects decrement at the top of that enemy's `take_turn()`.
- On expiry (or concentration break / dispel): `SpellEffects.end_effect(caster_stats, fx)`
  dispatches teardown by `spell_id` (remove AC bonus → `GameState.recalculate_stats()`,
  clear status, etc.) and erases it from `active_effects`.
- **Stat-modifying effects integrate through `recalculate_stats()`**, never by mutating
  `armor_class` directly: `GameState.recalculate_stats()` (which already rebuilds AC from
  equipment + `terrain_ac_bonus`) additionally sums
  `player_stats.caster.active_effect_ac_bonus()` — same pattern as `terrain_ac_bonus`.
  This is what makes Mage Armor / Shield of Faith analogues safe against every other AC
  writer in the game.

---

## 5. Casting flow & resolution API

### 5.1 The one entry point

```gdscript
# scripts/entities/spell_effects.gd  (static helper, CombatMath/TooltipFormatters pattern)
static func cast_spell(
    caster: Node,                 # Player, Enemy, or (later) Companion — needs .stats and .grid_pos
    spell: Spell,
    cast_at_level: int,           # ALWAYS explicit, even for cantrips (0) — owner decision #4
    target: Dictionary,           # {"pos": Vector2i} and/or {"entity": Node}; {} for SELF
    floor: DungeonFloor
) -> void
```

Resolution sequence (each step names its exact integration point):

1. **Reaction window — "enemy casts a spell"** (§8.2): if the caster is an Enemy,
   `await ReactionBroker.offer({"kind": "enemy_casts_spell", "caster": caster, "spell": spell})`.
   A future Counterspell resolves here and can abort the cast (slot still spent — 5e rule).
2. **Consume the slot**: `if not GameState.invincible: pool.consume_cast(spell, cast_at_level)`
   (invincible guard = root-CLAUDE.md consumption rule; enemy pools consume unconditionally).
3. **Concentration handover** (§7.3): if `spell.concentration`, end the caster's current
   concentration effect first (log line: `"You let <old> fade."`), then register the new one.
4. **Gather affected targets**:
   - `Shape.NONE` → the single `target.entity`.
   - AoE → `SpellShapes.affected_tiles(...)` (§6.2) → collect `floor.get_enemy_at(tile)`,
     plus the player/companion if `spell.hits_allies` and they stand in a tile (friendly
     fire is real — it's a roguelike).
5. **Per-target resolution** (§5.2): attack roll / save / auto-hit, damage/heal, status.
6. **Duration registration** (§4.6) if `duration_turns != 0`.
7. **Turn cost**: for the player, the caller (`PlayerSpellcasting`) wraps the whole thing in
   `TurnManager.begin_player_action()` … `update_fog(grid_pos)` …
   `player._handle_post_attack_turn()` when `casting_time == "action"` — identical envelope
   to `PlayerRanged.ranged_attack()`, including the Rager-R3 free-action interaction for
   free. `casting_time == "free"` skips the envelope entirely (Rage-activation precedent).
   Reactions never touch TurnManager at all (Retaliation/OA inline-resolution precedent).

### 5.2 Per-target resolution & upcasting

All dice math takes `cast_at_level`:

```gdscript
static func rolled_dice(spell: Spell, cast_at_level: int, caster_stats: Stats) -> Dictionary:
    var count: int = spell.dice_count
    if spell.cantrip_tier_scaling:               # character-level tiers 1/5/11/17
        count *= _cantrip_tier(caster_stats.character_level)
    elif cast_at_level > spell.level:
        count += spell.upcast_dice_per_level * (cast_at_level - spell.level)
    var total: int = spell.flat_bonus
    var rolls: Array[int] = []
    for _i: int in count:
        var r: int = randi_range(1, spell.dice_sides)
        rolls.append(r); total += r
    return {"total": total, "rolls": rolls, "count": count}
```

**ATTACK_ROLL** targets: reuse `CombatMath.roll_with_adv_disadv(adv_count, disadv_count)` with
the same ADV sources the ranged path counts (`player._vfx.has_advantage(enemy)` sleeping/door
surprise, `zealous_presence_turns`, Vex if the caster somehow has it) and the same
melee-range-DISADV rule for ranged spells (Chebyshev 1 → +1 disadv — a Fire Bolt at melee
range should feel like a bow at melee range). Attack bonus =
`caster.stats.caster.spell_attack_bonus(caster.stats)`. Nat 20 = crit (double the damage
dice roll, same `pre_crit *= 2` convention as `ranged_attack()`), nat 1 = auto-miss +
crit-fail banner. Tooltip meta: a new kind **`sphit`** with the same field shape as
`rhit` (`die,d1,d2,mod,prof,total,ac,adv,disadv,n20,n1`) — one new
`TooltipFormatters.fmt_sphit_tooltip()` that relabels "DEX" to the spellcasting ability.

**SAVE** targets: enemies roll `Enemy.resist_check_detailed(dc, ...)` — the exact machinery
Topple/Push already use — vs `spell_save_dc()`. `resist_check_detailed` currently only
supports STR/CON; it grows an optional `stat: String` parameter (default preserves current
behavior) reading the enemy's other ability mods (pool entries gain optional
`"dex_mod"`/`"wis_mod"` keys beside the existing `"str_mod"`/`"con_mod"` —
`_apply_stats()` already converts those two, the pattern extends 1:1). The detailed dict
feeds the existing `save:` tooltip meta via `fmt_save_tooltip()` (Topple precedent,
including `prof_label=Floor`). The **player** saving against enemy spells rolls
`d20 + modifier(stat) + (proficiency if check_prof_<stat>)` — the game's "no separate
saving-throw system, all defensive rolls are checks" rule, unchanged.
`save_for_half` → `dmg = total / 2` on a passed save (floor, min per damage-stacking rules).

**AUTO_HIT**: straight to damage/heal.

**Damage application** — per target, per the two root-CLAUDE.md RULEs:
- vs enemy: sum every component into ONE `enemy.stats.take_damage(total)` + one
  `floor.show_damage()` + one log line whose number carries a `dmg:` meta (the existing
  formatter — spell damage reuses `dmg:` with `bonus=` sources via
  `CombatMath.encode_bonus_sources()`, e.g. a future Empowered-metamagic bonus gets a named
  entry with zero formatter changes).
- vs player: `GameState.take_damage_raw(amount, false, spell.damage_type)` — never
  `player_stats.take_damage()` directly — so Rage DR / Bear-form magical DR apply exactly
  as they already do for typed damage. (Bear form's magical-DR check keys off "type not
  physical and not empty" — Fire/Force/Necrotic spell types slot straight in.)
- Heals: `GameState.heal(total)` for the player, with the existing `heal:` tooltip meta.
- Statuses: `GameState.apply_player_status(type, turns)` (the mandatory chokepoint — Rager
  R1 negation applies to spell debuffs automatically) for the player; the §10.5 mapping
  table for enemies.
- Kill handling: player-caster kills route through `player._finish_kill(enemy)` (exp, boss
  loot, undead meat — all preserved). AoE multi-kill: iterate targets, `_finish_kill` each
  dead one after all damage is applied (the "a source gated on `is_dead()` can silently
  fail" footnote in the damage-stacking rule is why damage-all-then-reap is the order).

### 5.3 `effect_id` dispatch — the escape hatch

```gdscript
# inside cast_spell(), replacing steps 4–5 when effect_id is set:
match spell.effect_id:
    "magic_missile": _fx_magic_missile(caster, spell, cast_at_level, target, floor)
    "shield_reaction": _fx_shield(caster)
    _: push_warning("Unknown spell effect_id: " + spell.effect_id)
```

Same shape as `player.gd._use_ability_slot()`'s `ability_id` match — one dispatcher, effects
are plain static functions with full access to the generic helpers (`rolled_dice`, the
resolution helpers), so a custom effect only writes what's actually custom.

### 5.4 Player-side UX: `PlayerSpellcasting` composition node

New composition child-node on `Player` (registered in `player.gd._ready()` beside `_ranged`,
`_zealot`, etc. — the established split-out-module pattern, back-reference `player: Player`).

**Spells surface on the existing ability bar.** When a spell becomes castable (learned +
prepared), `GameState` wraps it in an `Ability` with `ability_id = "spell:" + spell_id`,
`uses_max = 0` (slot state lives in the pool, NOT in `uses_remaining` — one source of truth;
the HUD use-count badge instead renders the pool via `ui_summary()`, see below) and places it
via the existing `GameState.add_ability()`. `player.gd._use_ability_slot()` gains one guard
before its `match`:

```gdscript
if ab.ability_id.begins_with("spell:"):
    _spellcasting.begin_cast(ab.ability_id.trim_prefix("spell:"))
    return
```

Nine ability slots will not hold a real caster's list forever — v1 accepts this (a Wizard's
prepared list at the game's level range fits; `add_ability()` already logs "Ability bar is
full!"). A paged bar / spellbook overlay is a known future need, flagged in §13.

**`begin_cast(spell_id)` flow**:

1. Validate: `caster.castable_spells()` contains it; `pool.can_cast(spell)` (else gray log
   line "No slot available.", no turn).
2. **Slot-level choice**: `pool.available_cast_levels(spell)` — if exactly one entry (all
   cantrips, all pact casts, mono-level pools), skip straight on. If several, show a small
   horizontal picker strip above the ability bar (row of buttons "1st ●●○ | 2nd ●○", built
   like the rest-panel tab headers, `FOCUS_NONE`, Esc cancels) — click picks
   `cast_at_level`. This is deliberately lightweight, not a modal: upcasting should cost
   one extra click, not a dialog.
3. **Targeting mode**: sets `_spell_targeting_active = true` on the player — the exact
   priming pattern of `_hook_mode_active` (Grip of the Forest) / throw mode: Esc cancels
   (add one branch beside the existing `_hook_mode_active` Esc handling at
   `player.gd _unhandled_input()`), movement keys cancel, LMB confirms. While active,
   the AoE preview (§6.3) follows the mouse.
4. LMB on a valid target → `SpellEffects.cast_spell(player, spell, lvl, target, floor)`
   wrapped in the §5.1 step-7 turn envelope.
   - `SELF` spells skip targeting entirely (cast on activation).
   - Validity: `target.pos` within `min(spell.range_tiles, live FOV)` — i.e.
     `floor.is_tile_visible(pos)` AND Euclidean `dist_sq <= range²` — and
     `floor.has_ranged_los(player.grid_pos, pos)` (the permissive WALL/VOID-only LOS,
     matching ranged attacks; spells don't thread walls but do cross grass/doors/chasms).

**HUD**: the ability-bar slot for a spell shows the spell icon; the existing per-slot
use-count badge (`_slot_use_labels` in `hud.gd`) renders the pool summary for spell slots —
for v1, the count of remaining slots of the spell's minimum castable level (simple, glanceable;
the tooltip shows the full `ui_summary()` breakdown). Slot changes emit a new
`GameState.spell_slots_changed` signal → HUD refresh (never polled — UI-signals rule).

---

## 6. AoE targeting on the tile grid

### 6.1 Conventions

- Positions are `Vector2i` grid coords; `DungeonData.grid[y][x]`; `TILE_SIZE = 16`.
- **Distance metric: squared Euclidean** (`d.x*d.x + d.y*d.y <= r*r`) for spell range and
  sphere membership — matching `PlayerRanged.is_ranged_target_in_range()` and the FOV-radius
  convention, and giving round-looking circles. Chebyshev remains the melee/adjacency metric;
  spells never use it except where noted.
- **LOS primitive**: `DungeonFloor.has_ranged_los(p1, p2)` (blocks WALL/VOID only). The
  strict `has_line_of_sight()` is enemy-AI vision — spells use the permissive one, same as
  arrows.

### 6.2 `SpellShapes` (static helper) — algorithms

Single entry:

```gdscript
static func affected_tiles(shape: int, origin: Vector2i, target: Vector2i,
        size: int, width: int, floor: DungeonFloor) -> Array[Vector2i]
```

`origin` = caster tile for CONE/LINE (they emanate from the caster), the chosen impact tile
for SPHERE/CUBE (they detonate at a point). `target` supplies direction for CONE/LINE.

**SPHERE (radius r = size), e.g. Fireball:**

```
for y in (origin.y - r) .. (origin.y + r):
    for x in (origin.x - r) .. (origin.x + r):
        p = Vector2i(x, y)
        d = p - origin
        if d.x*d.x + d.y*d.y > r*r: continue          # Euclidean disc
        if not _tile_affectable(p, floor): continue    # in-bounds, not WALL/VOID
        if not floor.has_ranged_los(origin, p): continue   # blast does not wrap corners
        out.append(p)
```

Wall interaction — **decision: the blast does NOT spread around corners** (5e RAW Fireball
does; we deviate). Justification: (a) the preview must show exactly what will be hit, and
"spreads around corners" either needs a flood-fill-with-budget algorithm whose previews
confuse more than they inform, or lies; (b) corner-safety gives the player real tactical
cover play, which suits a tile roguelike; (c) it is one `has_ranged_los` call — the
flood-fill variant can replace `_tile_affectable`+LOS later without touching any caller.

**CONE (length L = size, 90° arc), e.g. Burning Hands analogue:**

```
dir = Vector2(target - origin).normalized()      # float direction toward the aim point
for each tile p with Euclidean dist(origin, p) <= L, p != origin:
    v = Vector2(p - origin).normalized()
    if dir.dot(v) < cos(deg_to_rad(45)): continue    # within ±45° of aim = 90° cone
    if not floor.has_ranged_los(origin, p): continue # cone stops at walls, no wrap
    out.append(p)
```

Aiming: the player hovers ANY tile; only the direction from the caster matters (the hovered
tile need not be in range). Eight-way and every angle between fall out of the dot product —
no snap-to-octant needed, and the preview makes the actual footprint unambiguous. Origin tile
(caster) is never included. Wall rule: same LOS gate — a wall casts a "shadow" through the
cone, which reads correctly in the preview.

**LINE (length L = size, width W = shape_width), e.g. Lightning Bolt analogue:**

```
# Center line: Bresenham from origin toward target, extended/truncated to L tiles.
end = origin + (unit-direction toward target, scaled to L, rounded)
center = bresenham(origin, end)                 # reuse the floor's existing Bresenham walker
for p in center (excluding origin):
    if grid[p] == WALL or VOID: break           # a wall STOPS the line — no continuation behind
    out.append(p)
# W > 1: repeat for parallel Bresenhams offset perpendicular (rounded normal), each
# stopping independently at its own first wall.
```

Wall rule — **decision: a wall truncates the line and everything behind it** (unlike sphere's
per-tile shadow, the line is sequential so "stops dead" is the honest model). The existing
Bresenham lives inside `has_line_of_sight()`; extract the raw walker into a shared
`bresenham_tiles(p1, p2) -> Array[Vector2i]` on `DungeonFloor` (pure refactor, LOS then uses
it too).

**CUBE (side N = size), e.g. a thunder-burst analogue:**

```
half = N / 2                                     # N odd → centered on target tile
rect = Rect2i(target - Vector2i(half, half), Vector2i(N, N))
for p in rect:
    if not _tile_affectable(p, floor): continue
    if not floor.has_ranged_los(target, p): continue   # LOS from the cube's center
    out.append(p)
```

Even N is disallowed in v1 (data validation in `SpellDb`) — an even cube has no center tile
and needs an anchor-corner UI; no launch spell needs it.

Caster-inclusion rule (all shapes): the caster's own tile is included when the geometry says
so (SPHERE/CUBE centered nearby) — standing next to your own Fireball hurts. CONE/LINE
exclude the origin tile by construction.

### 6.3 Preview UI

New lightweight overlay owned by `DungeonFloor` (it owns fog and all other tile overlays):
`_aoe_preview: Node2D` with `z_index` between fog (2) and player (3), holding a pool of
16×16 `ColorRect`s (semi-transparent). API:

```gdscript
dungeon_floor.show_aoe_preview(tiles: Array[Vector2i], enemies_hit: Array[Vector2i])
dungeon_floor.clear_aoe_preview()
```

- Affected tiles tint orange (`Color(1.0, 0.55, 0.1, 0.35)`); tiles containing a target that
  will be hit tint red (`0.45` alpha); if the player/companion stands in the area, their tile
  tints red too — friendly fire must be visible before confirming.
- While `_spell_targeting_active`, `PlayerSpellcasting` recomputes
  `SpellShapes.affected_tiles()` on mouse-tile change (mouse-move only, never `_process`
  polling of GameState — but tile-under-mouse tracking itself follows how throw mode already
  tracks the hovered tile) and re-calls `show_aoe_preview()`. Esc / cast / cancel →
  `clear_aoe_preview()`.
- Out-of-range hover: preview renders gray instead of orange and LMB is rejected with a
  quiet log line — matching the existing ranged "not in range" feel.
- Single-target spells preview too: just the hovered enemy's tile in red (consistency —
  every cast shows its consequences the same way).

---

## 7. Concentration

### 7.1 State & rules

- `SpellcasterState.concentration_spell_id` / `_cast_level` / `_effect` (§4.2).
- **Casting a concentration spell while concentrating** ends the old effect first —
  `SpellEffects.end_effect()` teardown, gray log line — then registers the new one. No
  prompt for ordinary casts (the player initiated it; the §8.5 reaction case DOES prompt).
- **Drop instantly** on: death (`check_player_death()` path / `Enemy.die()`),
  incapacitation-class statuses (of the current status table: none — poison/burning/bleeding
  /slowed don't break concentration; a future paralyzed/stunned mapping (§10.5) must call
  the drop hook — noted at the mapping table), and voluntarily (clicking the ability-bar
  slot of the concentrated spell while it's active offers "Drop concentration?" — cheap and
  discoverable).

### 7.2 The damage hook — no spell knowledge in combat code

**Decision: a signal on `Stats`.** `Stats` (a Resource — Godot Resources emit signals fine)
gains:

```gdscript
signal damage_taken(amount: int)     # emitted at the end of take_damage() with the post-DR, post-temp-HP amount actually dealt
```

`Stats.take_damage()` appends one `damage_taken.emit(clamped)` line. That is the entire
footprint on generic combat code — no concentration logic, no spell imports, and every
damage path in the game (enemy melee via `take_damage_raw`, traps, status ticks via
`tick_status`'s caller, spell damage, retaliation vs enemies) converges on `take_damage()`
already, so nothing is missed and no call site changes.

The listener: when a caster gains a concentration effect, `SpellEffects` connects
`caster.stats.damage_taken` to a concentration-check closure; disconnects on drop. The check:

```gdscript
func _on_conc_damage(amount: int, caster_stats: Stats) -> void:
    if caster_stats.caster.concentration_spell_id == "": return
    var dc: int = maxi(10, amount / 2)
    # Player: CON check, proficiency if check_prof_con (Wizard: no; future Warlock/Sorc: no —
    #   War-Caster-style talents can add ADV later via the same adv-count house rule).
    # Enemy caster: resist_check_detailed(dc, true).
    var die: int = randi_range(1, 20)
    var total: int = die + caster_stats.con_modifier() \
        + (caster_stats.proficiency_bonus if caster_stats.check_prof_con else 0)
    # log with the existing save:/check: tooltip meta (fmt_save_tooltip — Topple precedent)
    if total < dc: break_concentration(caster_stats)   # teardown + "[color=red]Concentration broken![/color]"
```

Ordering note: the signal fires synchronously inside `take_damage()`, i.e. mid-way through an
attacker's damage/log sequence. The check itself only logs and tears down state (no awaits,
no turn interaction), so inline synchronous resolution is safe — the Retaliation precedent
(spawned from inside `enemy._attack_player()`) already established this shape.

Rapid multi-hit turns (three goblins) roll three separate checks — correct per 5e.

### 7.3 UI indicator

Two surfaces, both following existing conventions:

1. **HUD status-dot row**: a new concentration icon beside the poison/burning/bleeding/slowed
   dots — built with `hud.gd._make_status_icon_rect()` (which already sets
   `ignore_texture_size = true`, the mandatory TextureRect rule), a small violet swirl (or
   tinted placeholder until art exists — `ResourceLoader.exists` guard). Hover tooltip: spell
   name + remaining turns. Refresh driven by `GameState.player_status_changed` (the signal
   the dot row already consumes) — `SpellEffects` emits it on concentration start/stop.
2. **Ability-bar slot**: the concentrated spell's slot gets a gold border while active —
   the exact `StyleBoxFlat` border treatment the inventory's versatile-grip highlight uses
   (`inventory_overlay.gd _refresh()` precedent), refreshed off `ability_bar_changed`.

---

## 8. Reactions (BG3-style prompt)

### 8.1 The broker

**New small autoload: `ReactionBroker`** (`scripts/autoloads/reaction_broker.gd`).
Judgment call, flagged: the repo is conservative about autoloads, but reaction triggers fire
from `enemy.gd`, `player.gd`, `dungeon_floor.gd` (chasm), and `spell_effects.gd`, and every
trigger site must be able to `await` a shared arbiter that can also spawn UI — an autoload is
the only thing all four can await without threading references everywhere. It carries almost
no state (a busy flag + the prompt scene path).

```gdscript
# Returns a result dict; awaits the player's modal answer when a reaction is eligible,
# returns immediately otherwise. AI reactors auto-decline in v1 (§8.4).
func offer(trigger: Dictionary) -> Dictionary:
    # trigger: {"kind": String, ...context: attacker, roll_total, target_ac, spell, pos...}
```

Eligibility for the player, checked before any UI: not dead, `_reaction_used_this_round`
false, has at least one castable (`pool.can_cast`) reaction spell whose `reaction_trigger`
matches `trigger.kind`, and — for sight-gated triggers like `enemy_casts_spell` — the
trigger source is visible (`is_tile_visible`). If nothing is eligible: return
`{"taken": false}` **without awaiting** — the common case costs a dictionary and a few
lookups per trigger, no frame delay.

If eligible: spawn `reaction_prompt.gd` (CanvasLayer, **layer 26** — above the layer-25
overlays, matching `mastery_reselect_prompt`'s layering), a compact modal: trigger
description ("Goblin Archer's arrow is about to hit you — 17 vs your AC 15"), one button per
eligible reaction spell (+ slot cost), and "Pass \[Esc\]". `await` its `answered` signal.
On a taken reaction: set the player's `_reaction_used_this_round = true`, run
`SpellEffects.cast_spell(player, spell, lvl, ...)` with **no turn envelope** (reactions are
turn-free — the OA/Retaliation inline-resolution model), return
`{"taken": true, "spell": ...}` so the trigger site can re-evaluate (Shield: recheck the
hit).

**Reaction budget unification**: `_reaction_used_this_round` is a NEW player flag that
Opportunity Attacks also start consuming — `player.gd resolve_opportunity_attack()` currently
gates on `_oa_used_this_round`; that flag is renamed/absorbed into the shared reaction flag
(one reaction per round covers OA *or* a reaction spell, per 5e). Reset point: unchanged —
`_on_turn_started()`'s `if not came_from_revert:` block, exactly where `_oa_used_this_round`
resets today. Enemy `oa_used_this_round` likewise becomes the enemy's generic reaction flag
(no behavior change until enemies get reaction spells).

### 8.2 Trigger hook points (exact sites)

| Trigger kind | Hook site | Timing | Example spell |
|---|---|---|---|
| `about_to_be_hit` | `enemy.gd._attack_player()` — after the d20 total vs player AC is computed and would HIT, before damage | pre-damage; on `{"taken": true}` recompute `hit = total >= player AC` (Shield's +5 already applied via `recalculate_stats()`) | Shield (+5 AC until your next turn — an `ActiveSpellEffect`, `remaining_turns = 1`, `data = {"ac_bonus": 5}`) |
| `falling_into_chasm` | the player-chasm-death site in `dungeon_floor.gd` / `player.gd`'s chasm handling (where Owl-form `_owl_override` already branches) | before the fall resolves; taken → hover-land on the last safe tile | Feather Fall analogue |
| `enemy_leaves_reach` | the existing OA hooks — `enemy.gd._check_opportunity_attacks_on_move()` already implements this trigger; a reaction *spell* with this trigger would slot into the same site | as today | (OA itself; future war-caster-style cast-instead-of-swing) |
| `enemy_casts_spell` | `SpellEffects.cast_spell()` step 1 | before any resolution; taken + counter effect → abort cast (slot stays spent) | Counterspell (future) |

Each hook is one awaited call:

```gdscript
# enemy.gd._attack_player(), in the hit branch, before take_damage_raw:
var reaction: Dictionary = await ReactionBroker.offer({
    "kind": "about_to_be_hit", "attacker": self, "total": roll_total, "target": player})
if reaction.get("taken", false) and roll_total < GameState.player_stats.armor_class:
    # Shield turned the hit into a miss — log the deflection, skip damage
```

### 8.3 TurnManager interaction — why no phase changes

Triggers fire either (a) inside an enemy's `take_turn()` (attack, movement) or (b) inside the
player's own resolving action (enemy_casts_spell can't in v1 since enemies are the only spell
*sources* for it; chasm falls happen during player movement). In case (a),
`TurnManager._run_single_enemy()` already `await enemy.take_turn()` — an inner
`await ReactionBroker.offer(...)` simply extends that await. The phase stays
`RESOLVING_ENEMIES` while the modal is up; player *game* input is dead by the existing phase
gate, and the modal's own buttons/Esc live on a CanvasLayer processing normally. **Zero
TurnManager edits.** Same logic for case (b) under `RESOLVING_PLAYER`. This is the same
mechanism that lets `resolve_push()` await tweens mid-attack today.

One real constraint to document for the implementer: while the prompt is up,
`get_tree().create_timer` and tweens elsewhere keep running (they're independent), but no
other turn logic can interleave because everything is sequential awaits — which is exactly
the "queue" semantics §8.4 needs.

### 8.4 Simultaneity, ordering, AI

- **Sequencing**: simultaneous-in-fiction triggers (two enemies both stepping out of reach,
  an AoE hitting player + companion) are already serialized by the engine's sequential
  resolution order — enemies act one at a time, AoE targets iterate in array order. Rule:
  **triggers resolve in encounter order, each `offer()` fully resolves (modal answered)
  before the next fires.** The broker's busy flag asserts this (a second `offer()` while one
  is pending is a bug → `push_error`, auto-decline).
- **Budget interaction**: once `_reaction_used_this_round` is set, subsequent triggers that
  round short-circuit to auto-decline — so a queue of eligible triggers naturally collapses
  after the first taken one.
- **AI**: `offer()` checks reactor type; non-player reactors auto-decline in v1
  (`{"taken": false}`), with the seam being a future `enemy.consider_reaction(trigger)`
  virtual — per-enemy logic when enemy reaction spells exist.

### 8.5 Reactions × concentration

A reaction spell that is itself a concentration spell (rare in 5.5e, but the data model
allows it) goes through the same §7.1 handover: casting it drops the current concentration.
Because that trade can be terrible (drop Hold-Monster to Shield — n/a in v1 but the shape
matters), **the prompt button for a concentration reaction shows a warning suffix**:
"(ends <current spell>)" in red — the player consents with the same click, no second modal.
Non-concentration reactions (Shield, Feather Fall) never touch concentration — being hit
while concentrating triggers the §7.2 CON check *after* Shield fails to prevent the hit,
in natural sequence (Shield window → damage → concentration check).

---

## 9. Enemy / AI spellcasting

Per-enemy caster config rides the existing pool-data pattern (`attack_profile` precedent —
absent key = non-caster, zero change to existing entries):

```gdscript
# DungeonFloorData.ENEMY_POOL entry (illustrative):
"caster": {
    "model": "cooldown",              # "cooldown" | "slots"
    "ability": "INT",                 # spell save DC / attack bonus source
    "ability_mod": 3,                 # flat mod, same style as "str_mod"/"con_mod" keys
    "spells": ["fire_bolt", "burning_hands"],
    "cooldowns": {"burning_hands": 4},        # cooldown model only
    "caster_level": 5,                        # slots model only → StandardSlotPool table row
},
```

`Enemy.configure()` reads it: builds a `SpellcasterState` on `stats.caster` with either a
`CooldownSlotPool` or a `StandardSlotPool` — **and that is the entire difference between the
two models.** Spell selection, targeting, and resolution all go through the same
`SpellEffects.cast_spell(self, spell, lvl, target, floor)`; switching a tuned enemy from
cooldowns to real slots (or back) is a one-key pool-config edit that cannot change any
spell-effect behavior.

AI decision integration: the `_decide_action()` / `_execute_action()` seam
(`docs/architecture/ENEMY_SYSTEM_ARCHITECTURE.md` §1) is where casting slots in —
`_decide_action()` may return `{"type": "cast", "spell_id": ..., "target": ...}` when a spell
is ready (`pool.can_cast`), target in range+LOS; `_execute_action()`'s new `"cast"` case
awaits the cast (which awaits its own VFX — satisfying the "every path must await something
real" rule). Cooldown ticking: `pool.on_turn_tick()` at the top of `take_turn()` beside the
prone/slowed decrements. v1 selection policy is simple greedy ("cast the highest-level ready
spell if a target qualifies, else behave as the base FSM") — boss-phase casting logic is the
architecture doc's problem, not this one's.

Enemy save DCs vs the player: `8 + ability_mod + floor_num / 3` (the enemy's existing
floor-scaling bonus standing in for proficiency, matching `_resolve_attack_roll()`'s
convention); the player's defensive roll and its `save:` tooltip use `prof_label=Floor` as
Topple already does.

Enemy concentration: works via the same `Stats.damage_taken` hook (§7.2) with
`resist_check_detailed(dc, true)` — killing or pounding the enemy caster to break its buff
becomes real tactics with zero extra machinery.

---

## 10. D&D-to-digital adaptation pitfalls (each with a decision)

### 10.1 Spell components (V/S/M)

**Cut mechanically for v1.** `comp_verbal/somatic/material` are annotation fields only
(§4.1), shown as flavor in the spell tooltip. Rationale: Somatic free-hand rules interact
with the dual-wielding/versatile-grip/two-handed system in ways that generate constant
micro-friction ("unequip your off-hand dagger to Shield?") for near-zero tactical depth at
this game's granularity; material costs matter for exactly a handful of high-level spells
none of which are in scope. The fields existing in data means a later "components matter"
pass is a rules change, not a schema migration. Explicitly: no component pouch item, no
free-hand checks, no consumed materials in v1.

### 10.2 Ritual casting

**Cut for v1.** A ritual is "spend 10 minutes to save a slot" — in this game's clock that is
~10–100 turns of standing still, which is either free (cleared floor → no cost at all, purely
a UI chore) or suicidal (enemies active). Neither is a decision, so the mechanic adds a menu
and no gameplay. The honest adaptation, when wanted, is to make ritual-tagged spells castable
slot-free **during a rest** — hooking the existing rest-panel/interruptible-countdown
machinery (`short_rest_panel.gd`, `long_rest_pending` pattern) — which is a clean future
feature. `is_ritual` stays as annotation so that feature is data-ready.

### 10.3 Save DC / attack bonus & the multiclass-ability ambiguity

Formulas fixed in §3, computed on `SpellcasterState` (§4.2) — the state object, not the
class, owns `spellcasting_ability`. That placement is the whole fix for the classic
multiclass ambiguity: in 5.5e each *spell* uses the DC of the *class it was learned from*.
When multiclassing arrives (§10.8), `SpellcasterState` becomes per-class-instance (an array),
and each known spell records which state it belongs to — DC per spell falls out. Single-class
v1 has exactly one state and never notices. **Do not** put `spellcasting_ability` on `Stats`
or derive it from `character_class` in a match — that's the version that breaks later.

### 10.4 Counterspell / dispel-style spell-vs-spell

Composes with §8's `enemy_casts_spell` trigger: Counterspell is a reaction spell
(`reaction_trigger = "enemy_casts_spell"`, `effect_id = "counterspell"`) whose effect sets
`{"countered": true}` in the broker result; `cast_spell()` step 1 aborts on it (slot spent,
log line, no effect). Dispel Magic is NOT a reaction — it's an action targeting an entity,
whose effect walks the target's `SpellcasterState.active_effects` and `end_effect()`s
qualifying entries (the §4.6 registry is precisely what makes dispel implementable at all —
without a central active-effect list, dispel means hunting scattered flags). Neither ships
in v1; both are pure data+effect additions on the shipped hooks. Level-contest math
(counter a higher-level cast → check) uses the ordinary check machinery when implemented.

### 10.5 Spell-imposed conditions → the existing status system

**Rule: no new status framework.** Mapping table (the implementer extends
`apply_player_status()` and the enemy fields — never adds a parallel tracker):

| 5.5e condition | Player side | Enemy side | Notes |
|---|---|---|---|
| Restrained | `slowed_turns` + (new) `disadv_attacks_turns` | `rooted_turns` + `disadv_next_attack` | closest existing composite |
| Paralyzed / Stunned / Hold | (defer for player — brutal; needs a design pass) | `prone_turns`-style full-turn skip (`prone_turns = N`) | enemy side is literally Topple's mechanism |
| Prone | n/a v1 | `prone_turns` | already exists |
| Frightened | new `Stats.frightened_turns`: DISADV on attacks while source visible | new enemy field mirroring `disadv_next_attack` but duration-based | first genuinely new status; follows the `*_turns` int-field pattern + HUD dot |
| Charmed | defer entirely | defer | AI-target-override complexity; not v1 |
| Poisoned (condition) | existing `poison_turns` | (enemies have no status intake today — see risk §13) | |

Any mapping that stuns/incapacitates **must call the concentration-drop hook** (§7.1) — noted
here so the future paralyzed implementation doesn't miss it. All player-side applications go
through `GameState.apply_player_status()` (Rager R1 negation and the status-changed signal
come free); the function's `match` grows cases alongside any new `Stats` field.

### 10.6 Passive/duration spells vs. instantaneous

Solved structurally by `ActiveSpellEffect` (§4.6): instantaneous = `duration_turns == 0`,
nothing registered; duration non-concentration (Mage Armor: `duration_turns = -1`
until-long-rest; Shield: `1`) and concentration effects share the registry, differing only in
the `is_concentration` flag and what ends them. AC-style stat mods integrate exclusively via
`recalculate_stats()` (§4.6) — the one AC rebuild chokepoint the game already trusts.
Long-rest expiry of `-1` effects: `GameState.long_rest()` sweeps
`active_effects` for `remaining_turns == -1` entries and ends them (Mage Armor re-cast after
rest, per 8-hour duration ≈ one long-rest cycle).

### 10.7 Metamagic / sorcery points / ki — NOT `SpellSlotPool`

Decision: point-pools that *modify* casts are a different animal from pools that *pay for*
casts, and forcing them behind `SpellSlotPool` would bloat the interface every caster
touches. Pattern ruling: sorcery-point-style resources follow the **Zealot charge pattern**
(`zealot_blessed_charges` — plain int refilled in `long_rest()`, gated on
talent/class rank) until a *third* such resource exists, at which point the CLAUDE.md's own
guidance ("if a third such resource appears, consider extracting a shared helper") triggers a
`PointPool` extraction. Metamagic application point is already reserved: modifiers are extra
entries in the `cast_spell()` damage's `bonus=` sources and adv-count adjustments — no
resolution-path changes. Flexible-casting (points ↔ slots conversion) would be a method pair
on `StandardSlotPool` + the point holder, also deferred.

### 10.8 Multiclass slot math (future-proofing note only)

Per 5.5e multiclass rules a dual-class caster sums: full-caster levels + `floor(half-caster
levels / 2)` (note: multiclass **rounds down** where the single-class half-caster table
effectively rounds up — a real trap; our single-class `caster_level()` uses `ceil` per owner
decision, and the future multiclass combiner must NOT reuse it) → one combined level into the
shared slot table; **pact slots stay entirely separate** and coexist. What this doc's
abstraction already guarantees for that future: (a) `StandardSlotPool` reads its level via a
function that can become "combined caster level"; (b) `PactSlotPool` is a sibling, not a mode
flag, so Sorlock = one character with two pools, and `available_cast_levels()` results just
concatenate in the picker UI; (c) per-spell DC follows §10.3. Nothing else ships now.

### 10.9 Upcast display honesty

Small but bites every digital port: the slot picker (§5.4) must show the *effect* of the
level choice, not just the level ("2nd — 4 darts", "4th — 9d6"), or players upcast blind.
`Spell` gets a `func upcast_summary(cast_at_level) -> String` used by the picker buttons —
one formatting function per generic payload, `effect_id` spells override via `SpellDb`.

---

## 11. Integration points (exact files/functions)

| Area | File / function | Change |
|---|---|---|
| Caster state | `scripts/entities/stats.gd` | `var caster: SpellcasterState = null`; `signal damage_taken(amount)` emitted at end of `take_damage()`; WIZARD branch of `apply_class_defaults()` builds a FULL/INT/PREPARED state + `StandardSlotPool` |
| Starting spells | `game_state.gd give_class_starting_items()` → new `_give_wizard_starting_items()` | starting spell list into `caster.known_spells`/`prepared_spells`, spell Abilities onto the bar, `equipment_changed.emit()` at end per convention |
| Ability bar | `game_state.gd add_ability()` (unchanged) + `player.gd._use_ability_slot()` | one `begins_with("spell:")` guard before the match (§5.4) |
| Long rest | `game_state.gd long_rest()` | `slot_pool.on_long_rest()`; sweep `-1`-duration effects; (prepared casters) offer the Prepare Spells picker via the existing `mastery_reselect_prompt` flow in `player.gd`'s post-long-rest hook |
| Short rest | `game_state.gd _on_short_rest_completed()` | `slot_pool.on_short_rest()` (pact refill; no-op standard) |
| Turn tick | `player.gd _on_turn_started()`, inside `if not came_from_revert:` | decrement player `active_effects`, expire via `SpellEffects.end_effect()` |
| Enemy turn | `enemy.gd take_turn()` top | `pool.on_turn_tick()`; effect decrement for enemy casters |
| Enemy AI | `enemy.gd _decide_action()` / `_execute_action()` | `"cast"` intent (§9), reading the pool entry's `"caster"` key in `configure()` |
| Reactions | new autoload `reaction_broker.gd` + `scripts/ui/reaction_prompt.gd` (layer 26); hook sites per §8.2 table (`enemy.gd _attack_player()`, chasm site, `SpellEffects.cast_spell()` step 1) | `_oa_used_this_round` absorbed into shared `_reaction_used_this_round` (player) — reset point unchanged |
| Targeting | `player.gd _unhandled_input()` | `_spell_targeting_active` branch beside `_hook_mode_active` (Esc cancel at :489/:632 region, LMB confirm in the click dispatch) |
| AoE preview | `dungeon_floor.gd` | `show_aoe_preview()` / `clear_aoe_preview()` (§6.3); extract `bresenham_tiles()` from `has_line_of_sight()` |
| Saves | `enemy.gd resist_check_detailed()` | optional `stat: String` param + pool `"dex_mod"`/`"wis_mod"` keys through `_apply_stats()` |
| Damage/heal | existing: `enemy.stats.take_damage()` (one summed call), `GameState.take_damage_raw()` (typed), `GameState.heal()`, `player._finish_kill()` | no changes — spells are callers |
| Tooltips | `scripts/ui/tooltip_formatters.gd` + `hud.gd _format_tooltip()` | new `fmt_sphit_tooltip()` (kind `sphit`); reuse `dmg`/`save`/`heal` metas; every spell damage number tagged (root RULE) |
| HUD | `hud.gd` | slot-count badge on spell slots via `ui_summary()`, refreshed off new `GameState.spell_slots_changed` signal; concentration status dot via `_make_status_icon_rect()` (§7.3) |
| Input flags | `player.gd:469` master gate, `game_state.gd` run-reset block | new `spell_prep_open` flag twin of `mastery_picker_open` (if the Prepare picker ships in the same pass) |
| Invincible | every `pool.consume_cast()` call site | `if not GameState.invincible:` guard |
| Docs | `scripts/autoloads/CLAUDE.md`, `scripts/entities/CLAUDE.md`, `scripts/items/CLAUDE.md`, `scripts/ui/CLAUDE.md`, root `CLAUDE.md` | per the maintenance rule, updated in the implementing session |

Explicitly unchanged: `turn_manager.gd` (§8.3), the combat roll table for weapons,
`apply_player_status()`'s contract (grows cases, keeps shape), fog/FOV.

---

## 12. Example spells — worked end-to-end

### 12.1 Fire Bolt (cantrip, attack roll, single target)

```gdscript
# SpellDb entry
var s := Spell.new()
s.spell_id = "fire_bolt"; s.spell_name = "Fire Bolt"; s.level = 0; s.school = "Evocation"
s.casting_time = "action"
s.target_kind = Spell.TargetKind.ENEMY; s.range_tiles = 6        # book 120ft re-tuned per §3
s.resolution = Spell.Resolution.ATTACK_ROLL
s.dice_count = 1; s.dice_sides = 10; s.damage_type = "Fire"
s.cantrip_tier_scaling = true                                     # 1d10 → 2d10 @L5 → 3d10 @L11
s.class_list = ["WIZARD"]
```

Cast walkthrough (level-6 Wizard, INT 16): ability-bar slot 2 pressed →
`begin_cast("fire_bolt")` → cantrip, `available_cast_levels` = `[0]`, no picker → targeting
mode, hovered goblin tile previews red → LMB. `cast_spell(player, s, 0, {"entity": goblin},
floor)`: no slot consumed (cantrip `consume_cast` no-ops for level 0); attack =
`roll_with_adv_disadv()` d20 + spell_attack_bonus (3 prof + 3 INT = +6) vs goblin AC;
`sphit:` meta on the log verb. Hit → `rolled_dice`: tier 2 (level 6 ≥ 5) → 2d10, say 11;
crit would double the dice roll first. One `goblin.stats.take_damage(11)`, one floater, one
log line `You [url=sphit:...]scorch[/url] Goblin for [url=dmg:...]11[/url] Fire dmg.`; dead →
`_finish_kill()`. Turn ends via `_handle_post_attack_turn()`. Total custom code: zero —
pure generic path.

### 12.2 Magic Missile (1st level, auto-hit, upcast-scaling, `effect_id`)

```gdscript
s.spell_id = "magic_missile"; s.level = 1
s.casting_time = "action"; s.target_kind = Spell.TargetKind.ENEMY; s.range_tiles = 7
s.resolution = Spell.Resolution.AUTO_HIT
s.effect_id = "magic_missile"                    # multi-dart needs custom code
s.damage_type = "Force"
s.class_list = ["WIZARD"]
# generic dice fields unused; the effect owns its math:

static func _fx_magic_missile(caster, spell, cast_at_level, target, floor) -> void:
    var darts: int = 3 + (cast_at_level - 1)     # cast_at_level drives it — decision #6
    var total: int = 0
    var rolls: Array[int] = []
    for _i: int in darts:
        var r: int = randi_range(1, 4) + 1       # 1d4+1 per dart
        rolls.append(r); total += r
    # v1: all darts strike the chosen target — splitting among targets is a targeting-UI
    # feature deferred (flagged §13); damage-stacking RULE: one take_damage, one floater:
    var actual: int = target.entity.stats.take_damage(total)
    ...one log line; dmg: meta carries darts count + per-dart rolls in bonus= sources...
```

Cast at 2nd level from the slot picker ("1st — 3 darts ●●●○ | 2nd — 4 darts ●●○", §10.9's
`upcast_summary`): `consume_cast(spell, 2)` decrements the 2nd-level pool; 4 darts,
`4×(1d4+1)`, auto-hit (no roll, no `sphit` meta — the log verb is plain), one combined
number. On a hypothetical Warlock: `available_cast_levels` returns `[pact_slot_level()]`
only — at class level 5 that's `[3]` → 5 darts, no picker shown. Same data, same effect
function, different pool: the abstraction earning its keep.

### 12.3 Fireball (3rd level, DEX save for half, sphere AoE, friendly fire)

```gdscript
s.spell_id = "fireball"; s.level = 3
s.casting_time = "action"; s.target_kind = Spell.TargetKind.TILE; s.range_tiles = 7
s.shape = Spell.Shape.SPHERE; s.shape_size = 3   # book 20ft/4-tile radius tuned down — FOV is 7
s.hits_allies = true
s.resolution = Spell.Resolution.SAVE; s.save_stat = "DEX"; s.save_for_half = true
s.dice_count = 8; s.dice_sides = 6; s.damage_type = "Fire"
s.upcast_dice_per_level = 1
s.class_list = ["WIZARD"]
```

Walkthrough: targeting mode — every mouse move recomputes
`SpellShapes.affected_tiles(SPHERE, hover, hover, 3, 1, floor)` (origin = impact tile);
preview paints the Euclidean disc orange, LOS-shadowed tiles behind a pillar stay unpainted
(§6.2 sphere decision), the two goblins inside red — and the player's own tile red if they
aimed too close. LMB on a tile 5 tiles away (≤ range 7, visible, `has_ranged_los` from the
player): `consume_cast(spell, 3)`; `rolled_dice` → 8d6, say 27. Per target:
`goblin.resist_check_detailed(dc = 8 + 3 + 3 = 14, stat = "DEX")` → fail = 27, pass = 13;
each enemy gets ONE `take_damage` + floater + log line with `save:` meta on the roll and
`dmg:` on the number. Companion in the blast: DEX check via its stats, damage direct.
Player in the blast: player DEX check (`check_prof_dex` if any), then
`GameState.take_damage_raw(dmg, false, "Fire")` — Bear-form magical DR would apply, which is
correct and free. After all damage: reap dead enemies via `_finish_kill()` each. Cast at 4th:
9d6, from the picker ("3rd — 8d6 | 4th — 9d6"). No custom effect code.

Concentration bonus check on the caster: if the Wizard was concentrating (say a future Bless)
and a goblin's readied arrow hit them earlier that round for 9, the §7.2 hook already rolled
`CON check vs max(10, 4)` = DC 10 at that moment — Fireball itself, being instantaneous,
never touches concentration.

---

## 13. Open questions / risks

1. **Ability-bar capacity** (§5.4): 9 slots hold an early Wizard, not a level-10 one with
   scrolled extras. Options: pages on the ability bar, or a spellbook overlay (I-key
   sibling) with drag-to-bar. Needs an owner call before content outgrows it — the data
   model doesn't care, only the HUD does. **This is the one I'd most want a decision on
   early**, because it shapes whether spells-as-Abilities is the permanent surface or a v1
   bridge.
2. **Enemy status intake** (§10.5): enemies today have bespoke fields (`prone_turns`,
   `rooted_turns`, `slowed_turns`, `disadv_next_attack`) and no poison/burn tick — a
   damage-over-time spell vs enemies needs either enemy `Stats` gaining tick fields (they
   already own a `Stats` resource, so `tick_status()` mostly works) or staying out of v1
   spell content. Recommend: give enemies `tick_status()` processing at `take_turn()` top
   in the same pass; small, unlocks a whole spell category.
3. **Reaction prompt fatigue**: a Shield-carrying Wizard gets a modal on *every* would-hit
   attack. BG3 solves it with per-spell "ask/always/never" toggles. Recommend shipping v1
   with the modal plus a "Don't ask again this floor" checkbox, and watching feel — flagged
   rather than designed because the right ergonomics need play data.
4. **Balance of re-tuned ranges/radii** (§3): FOV 7 makes book geometry meaningless;
   the per-spell tile numbers in §12 are first guesses. Pure data tuning, but someone must
   own the pass.
5. **`Stats.damage_taken` signal ordering** (§7.2): emitting from inside `take_damage()`
   means the concentration-break log line can print *before* the attack's own damage log
   line (which is composed after the damage call at most sites). Cosmetic, but log order
   matters in this game. If it reads badly, the fallback is emitting via `call_deferred` —
   decide during implementation with real log output in front of you.
6. **Magic Missile dart-splitting UI** (§12.2): deferred to single-target v1; a
   multi-target picker is a genuinely new targeting mode (click N times?). Fine to defer,
   ugly to improvise — design it when a second multi-target spell appears.
7. **Judgment calls made without sign-off** (flagging per house style): `ReactionBroker` as
   a new autoload (§8.1); OA absorbed into the shared reaction budget (§8.1); sphere
   no-corner-wrap / line-truncation wall rules (§6.2); spells never exceed FOV (§3);
   caster-side (not target-side) storage of `ActiveSpellEffect`s (§4.6); Prepare-Spells
   picker as a mastery-picker copy rather than shared code (§4.2).

---

## 14. Implementation checklist (suggested commit breakdown)

1. **Data layer**: `spell.gd`, `spell_db.gd` (3 example spells), `spellcaster_state.gd`,
   `spell_slot_pool.gd` (base + Standard + Pact + Cooldown); `Stats.caster` field +
   `damage_taken` signal; Wizard `apply_class_defaults()` wiring; `long_rest()` /
   `_on_short_rest_completed()` pool hooks. Commit.
2. **Shapes + preview**: `spell_shapes.gd` with unit-style debug validation (God-Mode
   overlay that paints each shape), `bresenham_tiles()` extraction,
   `show_aoe_preview()`/`clear_aoe_preview()`. Commit.
3. **Resolution + player casting**: `spell_effects.gd` (generic path + magic_missile
   effect), `player_spellcasting.gd`, ability-bar `spell:` dispatch, slot picker strip,
   `sphit` formatter, HUD slot badge + `spell_slots_changed`. Fire Bolt + Magic Missile +
   Fireball playable as a Wizard. Commit.
4. **Concentration**: state, damage-hook listener, teardown, HUD dot + slot border,
   `recalculate_stats()` effect-AC integration, `ActiveSpellEffect` ticking. Commit.
5. **Reactions**: `reaction_broker.gd`, `reaction_prompt.gd`, the §8.2 hook sites, reaction
   budget unification with OA. (Shield as the proving reaction spell.) Commit.
6. **Enemy casting**: pool `"caster"` key, `configure()` wiring, `"cast"` intent, one
   reference caster enemy (e.g. "Goblin Shaman", cooldown model). Commit.
7. **Docs**: sub-directory CLAUDE.md updates (autoloads: broker + signals + rest hooks;
   entities: caster state, concentration, reaction budget; items: Spell/pool resources;
   ui: preview, prompt, badges) + root pointer lines. Commit.

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without
asking. Don't squash into one giant commit.
