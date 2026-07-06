# Race Selection — Design Doc

Status: **design only, not implemented.** No code ships with this doc. It plans the addition of
a second onboarding gate — race selection — inserted between class selection and the moment the
player actually gains control, plus the six race mechanics the owner has specified.

All line numbers below are as reported by a fresh read of the working tree at time of writing.
Re-verify before editing (per this repo's usual convention), but function names, signal names,
and structural shape are authoritative — mirror `docs/architecture/weapon-mastery-selection-design.md`
and `subclass_select.gd`'s patterns rather than inventing new ones.

Owner decisions below are **fixed requirements** — this doc designs around them, it does not
re-litigate them.

---

## 1. Overview / goals

Current onboarding: `class_select.gd` overlay (spawned over an already-loaded floor 1) → player
picks class → `GameState.class_selected = true` → mastery picker (if cap > 0) → overlay frees →
player has control.

New onboarding: **class select → race select → (mastery picker, unchanged) → player has control.**
Race select is a second one-time blocking overlay, spawned the moment class selection completes,
mirroring how `subclass_select.gd` is spawned as a one-time blocking overlay later in the run
(boss-gated). Nothing about *when* floor 1 loads changes — it's still loaded before either
overlay appears, per the existing "floor 1 loads before class pick, class pick is the run-start
checkpoint" model (`scripts/autoloads/CLAUDE.md`). Race pick becomes a second, immediately-following
checkpoint.

Owner-specified races (6, one with 3 sub-races):

| Race | Core traits |
|---|---|
| Orc | Relentless Endurance (drop to 1 HP instead of 0, 1×/long rest); momentum→temp HP combo; superior darkvision (+2 FOV) |
| Human | Heroic Inspiration (reroll a miss, popup-driven, 1×/long rest); player-chosen ability proficiency; no darkvision |
| Halfling | Reroll a natural 1, keep the new roll (no double-reroll); no darkvision |
| Dwarf | +1 max HP per level; superior darkvision (+2 FOV) |
| Elf | WIS proficiency; shorter rests; darkvision (+1 FOV); 3 sub-races (Drow/High Elf/Wood Elf), each granting one unique spell-like ability |
| Dragonborn | Chosen ancestry color → elemental resistance + breath damage type; darkvision (+1 FOV) |

---

## 2. Data model

### 2.1 Race (and sub-race) enums — new, on `Stats`

```gdscript
# stats.gd — next to CharacterClass (line 4)
enum CharacterRace { ORC, HUMAN, HALFLING, DWARF, ELF, DRAGONBORN }
enum ElfSubrace { DROW, HIGH_ELF, WOOD_ELF }          # only meaningful when race == ELF
enum DragonbornAncestry { BLACK, BLUE, BRASS, BRONZE, COPPER, GOLD, GREEN, RED, SILVER, WHITE }
```

Lives on `Stats` for the same reason `character_class` does — it's per-run character data,
serialized alongside ability scores. `ElfSubrace`/`DragonbornAncestry` are separate enums (not
folded into `CharacterRace`) because only one race branches into sub-choices each; a single
`race_variant: int` field (untyped, reused across whichever enum applies) keeps the schema from
growing a field per race — see §2.2.

### 2.2 New `Stats` fields

```gdscript
# stats.gd — new @export block near character_class
@export var character_race: CharacterRace = CharacterRace.HUMAN
@export var race_variant: int = 0   # ElfSubrace or DragonbornAncestry ordinal; unused otherwise
@export var race_prof_ability: int = -1   # Human only: which of STR..CHA got proficiency; -1 = unset

# new: darkvision / FOV bonus (nothing on Stats reads FOV today — dungeon_floor.gd owns the constant)
var darkvision_bonus: int = 0   # 0 = no darkvision, 1 = standard (+1 tile), 2 = superior (+2 tiles)

# new: damage resistance (nothing like this exists today — needed for Dragonborn)
var damage_resistances: Array[String] = []   # e.g. ["fire"] — matches Stats/Enemy damage_type strings

# new: per-long-rest charge trackers (same shape as existing rage_uses_remaining / zealot_zp_charges)
var relentless_endurance_used: bool = false     # Orc — resets false on long_rest()
var heroic_inspiration_available: bool = false  # Human — true after long_rest(), consumed on use
```

- `darkvision_bonus` and `damage_resistances` are **not** `@export` — they are always fully
  re-derived from `character_race`/`race_variant` by `apply_race_defaults()` (see §2.3), same
  reasoning as `check_prof_*` not being independently saved (stats.gd's existing save-comment:
  "class-set flags are never saved — `from_dict()` re-derives them").
- `race_prof_ability` **is** exported/saved — it's a one-time player choice (Human), not derived
  from anything.
- `race_variant` **is** exported/saved — it's a one-time player choice (Elf sub-race, Dragonborn
  ancestry color), not derived.

### 2.3 `Stats.apply_race_defaults()` — mirrors `apply_class_defaults()`

```gdscript
# stats.gd — new function, called after apply_class_defaults()
func apply_race_defaults() -> void:
    darkvision_bonus = 0
    damage_resistances.clear()
    match character_race:
        CharacterRace.ORC:
            darkvision_bonus = 2
        CharacterRace.HUMAN:
            darkvision_bonus = 0
            if race_prof_ability >= 0:
                _grant_ability_proficiency(race_prof_ability)
        CharacterRace.HALFLING:
            darkvision_bonus = 0
        CharacterRace.DWARF:
            darkvision_bonus = 2
        CharacterRace.ELF:
            darkvision_bonus = 1
            check_prof_wis = true
        CharacterRace.DRAGONBORN:
            darkvision_bonus = 1
            damage_resistances = [_ancestry_damage_type(race_variant)]
```

**Ordering decision (owner sign-off needed, flagged as open question #1):** class defaults
currently *overwrite* the full six-ability-score sextet (`apply_class_defaults()`'s `match`
block). None of the six races above grant flat ability-score bonuses (the owner's list only
grants proficiency flags, HP, darkvision, resistance, and reroll mechanics — no "+2 STR" style
bonus), so for this doc **race defaults apply strictly after class defaults, additively, and
never touch the base ability scores.** If a future race *does* grant a raw ability bonus, it
must be applied as a delta on top of whatever `apply_class_defaults()` set, not by re-running the
class match — call order stays `apply_class_defaults()` → `apply_race_defaults()`, never reversed.

Dwarf's "+1 max HP per level" is **not** set in `apply_race_defaults()` (that function only fires
once, at selection) — see §2.4, it hooks the existing per-level-up path instead.

### 2.4 Dwarf: +1 max HP per level

`Stats._hp_per_level()` is the existing per-level HP gain function (called from `gain_exp()`).
Add a race check inline:

```gdscript
func _hp_per_level() -> int:
    var gain: int = ... # existing HD-based roll/average
    if character_race == CharacterRace.DWARF:
        gain += 1
    return gain
```

No new field needed — this is a one-line addition to an existing function, not a new system.

### 2.5 `race_prof_ability` — Human's chosen proficiency

Human picks **one** of STR/DEX/CON/INT/WIS/CHA to be proficient in (the game's "check
proficiency" flags — `check_prof_str` etc., stats.gd lines 9-14 — are the closest existing
analog to a saving-throw proficiency, since there's no separate save system per
`scripts/entities/CLAUDE.md`: "No separate saving throw system — all defensive rolls are
checks"). `_grant_ability_proficiency(idx: int)` just sets the matching `check_prof_*` flag:

```gdscript
func _grant_ability_proficiency(idx: int) -> void:
    match idx:
        0: check_prof_str = true
        1: check_prof_dex = true
        2: check_prof_con = true
        3: check_prof_int = true
        4: check_prof_wis = true
        5: check_prof_cha = true
```

The race-select UI collects `race_prof_ability` via a 6-button sub-picker shown only when Human
is selected (§4.3) — this is the one race trait requiring extra UI beyond "pick a card."

### 2.6 Elf sub-races and Dragonborn ancestry — extra picker step

Both Elf and Dragonborn require a **second choice** after picking the race card:

- Elf → pick Drow / High Elf / Wood Elf (sets `race_variant` to the `ElfSubrace` ordinal).
- Dragonborn → pick one of the 10 ancestry colors (sets `race_variant` to the
  `DragonbornAncestry` ordinal; `_ancestry_damage_type()` and `_ancestry_breath_shape()` are pure
  lookup tables keyed by this ordinal — see §3.6).

This mirrors Human's extra proficiency-choice step (§2.5) — the race-select UI needs a generic
"this race has a sub-step" branch, not three different one-off code paths. See §4.3.

---

## 3. Race mechanics — one section per race

### 3.1 Orc — Relentless Endurance + Momentum temp HP + superior darkvision

**Relentless Endurance** (drop-to-1-instead-of-0, 1×/long rest): hooks `Stats.take_damage()`
(stats.gd, existing function that already handles temp-HP absorption and HP subtraction). Add a
guard immediately after the HP subtraction, before whatever currently happens on `current_hp <= 0`
(likely a `player_died` signal emit or similar — verify call site, probably in `player.gd` or
`entity.gd`, not `stats.gd` itself, since HP-reaching-0 death handling looks like an
entity-level concern; `take_damage()` on `Stats` returns/mutates the HP value and the caller
checks it):

```gdscript
# take_damage() or its caller, wherever current_hp <= 0 is currently checked for death
if current_hp <= 0 and character_race == CharacterRace.ORC and not relentless_endurance_used:
    current_hp = 1
    relentless_endurance_used = true
    GameState.game_log("[url=race:relentless]Relentless Endurance holds you at 1 HP![/url]")
    return  # skip the normal death path this one time
```

- `relentless_endurance_used` resets to `false` in `GameState.long_rest()`, alongside
  `rage_uses_remaining`/`hit_dice` — same chokepoint, per the root CLAUDE.md rule ("any new 'per
  long rest' resource must be refilled in `long_rest()` and nowhere else").
- **Tooltip tag required** per root CLAUDE.md's chat-log rule: a `[url=race:relentless]` tag
  needs a matching `fmt_race_relentless_tooltip()`-style handler in
  `scripts/ui/tooltip_formatters.gd`.
- Exact hook site (whether death-check lives in `stats.gd`, `player.gd`, or `entity.gd`) needs
  verification during implementation — flagged as open question #2.

**Momentum → temp HP** ("when it moved and it didn't cost him the whole turn, combo with some
abilities, he gets proficiency × temp HP"): this reads as an Orc trait that triggers when the
player performs a *bonus-action-style* move (an action that doesn't consume the full turn —
this codebase's closest existing analog is the Monk's bonus-action strike, or any ability
flagged as not ending the turn). Because the "combo with some abilities" phrasing is vague,
recommend implementing this as a **new signal-driven hook** rather than hardcoding it into any
one ability:

```gdscript
# GameState — new signal, emitted by any action that both (a) is a move and (b) doesn't end turn
signal orc_momentum_triggered

# in whatever ability code already knows "this move didn't cost the full turn"
if GameState.player_stats.character_race == Stats.CharacterRace.ORC:
    GameState.orc_momentum_triggered.emit()

# GameState — listener (connected once, e.g. in _ready())
func _on_orc_momentum_triggered() -> void:
    player_stats.temp_hp += player_stats.proficiency_bonus
    game_log("[url=race:momentum]Orc resilience grants you %d temporary HP![/url]" % player_stats.proficiency_bonus)
```

- Uses the **existing** `Stats.temp_hp` field and its existing absorb-first behavior in
  `take_damage()` — zero new HP plumbing (per research point 6: temp_hp already exists and is
  consumed correctly).
- Flagged as open question #3: **which abilities currently grant a "free" move that doesn't cost
  the turn?** Needs a concrete list before this can be wired up — this doc identifies the pattern
  (signal-driven, reuses temp_hp) but the actual emit-sites depend on move/ability code not yet
  audited for this feature.

**Superior darkvision (+2 FOV)**: `darkvision_bonus = 2`, set in `apply_race_defaults()` (§2.3).
See §5.1 for the shared FOV hook all darkvision races use.

### 3.2 Human — Heroic Inspiration + chosen proficiency + no darkvision

**Heroic Inspiration** (reroll a miss, BG3-style reaction popup, 1×/long rest): the hook point is
`player.gd._bump_attack()` (and its mirrors: `player_ranged.gd.ranged_attack()`,
`_resolve_cleave_attack()`, `_resolve_offhand_attack()`, `resolve_opportunity_attack()` — see
research point 5) at the exact spot the miss branch is determined:

```gdscript
# player.gd._bump_attack(), right after the existing miss check (~line 1273)
if not is_crit and (is_nat_one or roll < enemy.stats.armor_class):
    if player_stats.character_race == Stats.CharacterRace.HUMAN \
            and player_stats.heroic_inspiration_available:
        var reroll: bool = await _show_heroic_inspiration_popup()
        if reroll:
            player_stats.heroic_inspiration_available = false
            r = CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
            # re-derive die/roll/is_crit/is_nat_one from the new r, then re-check hit/miss
        else:
            # fall through to the existing miss branch
    # existing miss branch continues here if not rerolled or reroll still misses
```

- Requires a small new popup UI (`scripts/ui/heroic_inspiration_popup.gd`), styled like a BG3
  reaction prompt — a compact non-blocking-to-the-rest-of-the-game modal, but *combat itself*
  must pause on the `await` until the player answers (Yes/No) or a short auto-decline timeout
  elapses. This is the single trickiest integration point in the whole doc because it must be
  duplicated at **every** attack-roll call site (melee, ranged, cleave, offhand, opportunity
  attack) rather than centralized in `CombatMath` — the miss/hit decision itself lives in each
  caller, not in `CombatMath.roll_with_adv_disadv()`. **Recommendation:** factor the "was this
  roll a miss, and if so, offer the human a reroll" logic into one shared helper (e.g.
  `CombatMath.maybe_offer_human_reroll(stats, roll_result, ac) -> Dictionary`) that every call
  site invokes right after computing `roll`/`is_crit`/`is_nat_one`, so the popup logic and the
  "already used this rest" gate exist exactly once. Flagged as open question #4 — worth an
  explicit design pass on `CombatMath` before implementation, since this is the same
  "reroll a d20 result" shape Halfling also needs (§3.3) and the two should likely share
  plumbing.
- `heroic_inspiration_available` set `true` at end of `GameState.long_rest()` (and once at game
  start / race selection, since the first "long rest" hasn't happened yet — set it `true` in
  `apply_race_defaults()` too, or in the race-select confirm handler).
- **Chosen ability proficiency**: see §2.5 — extra UI step in race select.
- **No darkvision**: `darkvision_bonus = 0` (explicit, matches the default anyway — written for
  clarity in §2.3's match block).

### 3.3 Halfling — reroll a natural 1, keep the new roll

Same `CombatMath`/`_bump_attack()` family of call sites as Human, but simpler: no popup, no
resource charge, no cap — it's an automatic unconditional reroll-once whenever `die == 1`, and
critically **the second roll is never itself rerolled even if it's also a 1** ("keep the new
roll" — no double-reroll).

```gdscript
# right after CombatMath.roll_with_adv_disadv() produces `r` / `die`, before any hit/miss logic
if die == 1 and player_stats.character_race == Stats.CharacterRace.HALFLING:
    r = CombatMath.roll_with_adv_disadv(adv_count, disadv_count)
    die = r.die
    # recompute roll/is_crit/is_nat_one from the new r; no further reroll regardless of new die value
```

- Cleanest implementation: a `CombatMath` helper `CombatMath.apply_halfling_luck(stats, r, adv_count, disadv_count) -> Dictionary`
  that internally does exactly the reroll-once check above and returns the (possibly replaced)
  roll dictionary — called once per attack site immediately after
  `roll_with_adv_disadv()`, mirroring how Human's helper (§3.2) would slot into the same spot.
  Recommend designing both as thin wrappers around `CombatMath.roll_with_adv_disadv()` so the
  five attack call sites each gain exactly one extra line, not five copies of race-conditional
  logic.
- No long-rest resource, no popup, no `Stats` field beyond `character_race` itself — the simplest
  of the six races to implement.

### 3.4 Dwarf — +1 max HP/level + superior darkvision

Both already covered: HP in §2.4, darkvision in §2.3 (`darkvision_bonus = 2`, same value as Orc).
No other mechanics specified by the owner — the simplest race, no combat-roll hook, no
long-rest resource.

### 3.5 Elf — WIS proficiency, shorter rests, darkvision(+1), 3 sub-races

**WIS proficiency**: `check_prof_wis = true` in `apply_race_defaults()` (§2.3) — same flag Human
could also independently choose (§2.5); no conflict, they're just both `bool` fields.

**Shorter rests**: the existing rest system (`scripts/ui/short_rest_panel.gd`,
`GameState.LONG_REST_TURNS` = 20) is the target. "Shorter" most plausibly means the long rest's
interruptible turn-count is reduced for Elf specifically:

```gdscript
# wherever LONG_REST_TURNS is consumed (short_rest_panel.gd or GameState.long_rest() setup)
var turns_needed: int = GameState.LONG_REST_TURNS
if GameState.player_stats.character_race == Stats.CharacterRace.ELF:
    turns_needed = int(turns_needed * 0.5)   # exact ratio is an owner call — flagged open question #5
```

Flagged as **open question #5**: the owner should confirm (a) the exact reduction (5e's Elf
"Trance" is 4 hours vs. a human's 8, i.e. half — used as the default above) and (b) whether this
also shortens the short-rest side (`short_rests_remaining` cadence) or only the long rest. This
doc assumes long-rest-only until told otherwise, since only long rest has an explicit turn-count
today.

**Darkvision +1**: `darkvision_bonus = 1` (§2.3).

**3 sub-races, one unique ability each** — each is a spell-like effect, none of which exist in
this codebase yet (`docs/architecture/spellcasting-design.md` is explicitly "design only, not yet
implemented"). Recommend treating each sub-race grant as an `Ability` resource added to
`player_ability_bar` via the existing `GameState.add_ability()` (the same mechanism talents use,
per research point 5's dispatch-pattern note) rather than blocking race selection on the whole
spellcasting system landing first:

| Sub-race | Ability | Suggested minimal implementation (no spellcasting system needed) |
|---|---|---|
| Drow | *Darkness* | A toggle ability that dims/removes the player's own light radius over an area for N turns — simplest version: temporarily reduces the FOV of any **enemy** entities in the affected tiles (a debuff, not a player buff), reusing the `Enemy` behavior-state gates already in the entity hierarchy. Full spell-shape (targeted AoE, duration) is out of scope until spellcasting lands — recommend an ability-bar item with a flat charge count (`uses_max`) and a hardcoded small radius, not a general spell. |
| High Elf | *Misty Step* | Short-range teleport — closest existing analog is a instant `move_to()` to a target tile within N range, bypassing normal pathing/turn cost rules the way a dash/teleport ability would. Simplest version: consumes the player's turn, teleports to any visible, unoccupied floor tile within N tiles (Chebyshev distance), no line-of-sight requirement beyond "currently fogged-in visible." |
| Wood Elf | *Pass Without Trace* | Stealth buff — simplest version: while active, sets a temporary flag that Enemy AI's `ROAMING`/`SEARCHING` detection radius (wherever that check lives in `enemy.gd`'s `take_turn()`) treats the player as further away / undetectable for N turns, i.e. a stealth-buff flag consumed the same way a status effect ticks down (`Stats.tick_status()`). |

Each of these needs its own small design pass at implementation time — this doc intentionally
scopes them to "one ability-bar charge-limited ability, granted at race selection, using
patterns that already exist (add_ability, status-effect ticking, teleport-via-move_to)" so race
selection isn't blocked on spellcasting. Flagged as **open question #6**: confirm these
minimal shapes are acceptable substitutes, or whether the owner wants to wait for real
spellcasting infrastructure before Elf sub-race abilities are functional (in which case race
selection could still ship with the sub-race *choice* recorded on `Stats.race_variant`, with the
ability itself granted as a stub/no-op until spellcasting lands).

### 3.6 Dragonborn — ancestry color, elemental resistance, breath weapon

**Ancestry choice**: `race_variant` holds a `DragonbornAncestry` ordinal (§2.1), chosen via the
extra sub-picker step (§2.6, §4.3).

**Elemental resistance**: `damage_resistances = [_ancestry_damage_type(race_variant)]`, set in
`apply_race_defaults()` (§2.3). This requires the **new** `Stats.damage_resistances: Array[String]`
field (§2.2) to actually be *read* somewhere — currently nothing in combat code checks resistance
at all (research point 3 confirms no resistance/immunity fields exist today). The consuming side
(wherever enemy or player `take_damage()` applies incoming damage) needs a new check:

```gdscript
# Stats.take_damage(amount: int, damage_type: String = "") -> the function needs a damage_type param added
func take_damage(amount: int, damage_type: String = "") -> void:
    var final_amount: int = amount
    if damage_type != "" and damage_resistances.has(damage_type):
        final_amount = final_amount / 2   # 5e resistance = half damage, rounded down
    # ... existing temp_hp absorption + current_hp subtraction, using final_amount
```

This is a **signature change** to an existing, widely-called function — flagged as **open
question #7**, the single largest ripple effect in this whole doc. Every call site of
`take_damage()` (player attacks on enemies, enemy attacks on player, trap damage, status-effect
tick damage) would need to start passing a `damage_type` string for resistance to ever apply.
Given `docs/architecture/enemy-stat-block-design.md` already designs (unimplemented) a full
`resist/immune/vuln` system for enemies with the same shape, **recommend deferring Dragonborn's
resistance mechanic until that design is implemented**, or scoping this doc's Dragonborn
resistance narrowly to only the couple of damage sources that already carry a `damage_type`
string today (research needed: which damage sources currently tag a type at all — weapon
`damage_type` field exists per root CLAUDE.md's Items section, so at minimum weapon-damage
resistance is feasible without the full enemy stat-block system landing first).

**Breath weapon** (damage type is ancestry-determined, per 5e rules also implies a shape/save —
not explicitly requested by the owner beyond "breath damage type"): recommend implementing as a
new Ability (same `add_ability()` pattern as talents/sub-race abilities), a limited-use
(`uses_max` per long rest) single-target or small-AoE attack whose damage type and amount come
from `_ancestry_damage_type(race_variant)` and a flat formula (e.g. `character_level`d6, no
attack roll, target makes a... this game has no save system, so recommend a flat DC-style
`Rng.chance()` check or simply guaranteed damage, consistent with "no separate saving throw
system" per `scripts/entities/CLAUDE.md`). Flagged as **open question #8**: confirm whether
breath weapon is in scope for this doc's implementation pass at all, since the owner's prompt
only mentions "determines... breath damage type," implying the breath attack itself might be a
separate, later feature and this pass only needs to *record* the ancestry choice + resistance.

**Darkvision +1**: `darkvision_bonus = 1` (§2.3), same value as Elf.

---

## 4. UI — `scripts/ui/race_select.gd`

New script, no `.tscn`, modeled directly on `subclass_select.gd` (full-screen blocking overlay,
non-dismissible — the choice is permanent, same as subclass) rather than `class_select.gd`
(which allows a "Continue Saved Run" skip path — race select has no such skip, it always follows
a fresh class pick).

### 4.1 Structure (mirrors `subclass_select.gd`)

- `extends CanvasLayer`, `layer = 25` (same layer as subclass/mastery pickers — they never
  overlap in time, so layer collision is a non-issue).
- `_ready()`: `GameState.race_picker_open = true` (new blocking flag, §5.3), build UI.
- Full-screen dim `ColorRect` (`MOUSE_FILTER_STOP`) + centered bordered `Panel` (same
  `StyleBoxFlat` gold-border convention).
- 6 race cards in a grid (2 rows × 3, or 3×2 — layout detail, not load-bearing) built from a
  local `const RACES` data array, same shape as `subclass_select.gd`'s `SUBCLASSES` array:
  `{id, name, icon_path, description}`.
- Card click → `_select(race_id)`, restyle cards, enable Confirm.
- **Human and Elf and Dragonborn require a sub-step** before Confirm is enabled — see §4.3.
- Confirm → `_on_confirm()`: `GameState.race_picker_open = false`,
  `GameState.choose_race(_selected, _sub_selected)` (new GameState mutator, mirrors
  `choose_subclass()`), `queue_free()`.
- `_unhandled_input` swallows all `InputEventKey` (no Esc dismiss) — permanent choice, same as
  subclass select.
- All buttons `focus_mode = FOCUS_NONE` (repo-wide overlay convention).

### 4.2 Spawn site — `class_select.gd._on_class_selected()`

Currently ends: give starting items → `class_selected = true` → emit `class_chosen` → spawn
mastery picker (if cap > 0) → `queue_free()`. Insert race select **before** the mastery picker,
so ordering becomes: class chosen → race select (blocking) → race confirmed → mastery picker (if
cap > 0) → both overlays gone, player has control.

```gdscript
# class_select.gd, _on_class_selected(), replacing the direct mastery-picker spawn
GameState.class_selected = true
GameState.player_hp_changed.emit(...)
GameState.class_chosen.emit(GameState.player_stats.character_class)
var race_picker = load("res://scripts/ui/race_select.gd").new()
get_tree().root.call_deferred("add_child", race_picker)
queue_free()
```

The mastery-picker spawn call **moves** into `race_select.gd`'s `_on_confirm()` (after
`GameState.choose_race(...)`), rather than staying in `class_select.gd` — because it must fire
*after* race is chosen, not before. This is the one existing integration point this doc changes.

### 4.3 Sub-step handling (Human proficiency, Elf sub-race, Dragonborn ancestry)

Three of six race cards need a second choice before Confirm unlocks. Recommend a single
generic mechanism rather than three special cases:

```gdscript
const RACE_SUBCHOICES := {
    "human": {"kind": "ability_score", "options": ["STR","DEX","CON","INT","WIS","CHA"]},
    "elf": {"kind": "subrace", "options": ["Drow","High Elf","Wood Elf"]},
    "dragonborn": {"kind": "ancestry", "options": [10 color names]},
}
```

On selecting a card whose id is a key in `RACE_SUBCHOICES`, reveal a second row of small buttons
(same card-button styling, smaller) populated from `options`; Confirm stays disabled until both
the race card and (if applicable) the sub-choice are selected. Orc/Halfling/Dwarf skip straight
to Confirm-enabled on card click alone.

### 4.4 `GameState.choose_race()` — mirrors `choose_subclass()`

```gdscript
# game_state.gd
signal race_chosen(race: Stats.CharacterRace)

func choose_race(race: Stats.CharacterRace, variant: int = 0, prof_ability: int = -1) -> void:
    player_stats.character_race = race
    player_stats.race_variant = variant
    player_stats.race_prof_ability = prof_ability
    player_stats.apply_race_defaults()
    give_race_starting_items()   # if any race grants starting gear/abilities — likely just Elf sub-race abilities + Dragonborn breath weapon (§3.5, §3.6)
    race_chosen.emit(race)
```

`give_race_starting_items()` mirrors `give_class_starting_items()`'s idempotency-guard pattern
(research point 5) since it will also need to replay correctly on save-load (§6).

---

## 5. Shared systems — hooks touched by more than one race

### 5.1 Darkvision → FOV radius

`dungeon_floor.gd`'s `FOV_RADIUS` is currently a hardcoded `const int = 7`, threaded as a plain
parameter through `_compute_shadowcast()` → `_cast_light()`, with a second independent use at
line ~648 (a squared-radius distance check — needs the same substitution). Converting to a
race-aware value:

```gdscript
# dungeon_floor.gd — const becomes a computed value (or the two call sites read a shared helper)
func _current_fov_radius() -> int:
    return FOV_BASE_RADIUS + GameState.player_stats.darkvision_bonus

const FOV_BASE_RADIUS: int = 7   # renamed from FOV_RADIUS; base is unaffected by any race
```

Both call sites (`_compute_shadowcast()`'s `_cast_light(..., FOV_RADIUS, ...)` and the line-648
squared-radius check) switch to `_current_fov_radius()` (or `_current_fov_radius() ** 2` for the
squared one). This is additive and race-agnostic — Human/Halfling get `+0` (no field change from
today's behavior), Elf/Dragonborn `+1`, Orc/Dwarf `+2`.

### 5.2 d20 reroll mechanics (Human's miss-reroll, Halfling's nat-1-reroll)

Both hook the same five attack-roll call sites (`player.gd._bump_attack()`,
`player_ranged.gd.ranged_attack()`, `_resolve_cleave_attack()`, `_resolve_offhand_attack()`,
`resolve_opportunity_attack()` — research point 5). Recommend two new `CombatMath` helpers
(§3.2, §3.3) rather than five duplicated inline race checks per site — this is the doc's
strongest recommendation for centralization, since the five call sites already share
`roll_with_adv_disadv()` as their single roll source and should share the reroll wrapper the
same way.

### 5.3 New `GameState` blocking flag: `race_picker_open`

Needs the identical treatment `mastery_picker_open` got when it was added (research + the
mastery-selection design doc's §5.3 table) — every site gating player input on
`talent_picker_open`/`mastery_picker_open`/`subclass_picker_open` needs a `race_picker_open`
twin: the T-key talent-open gate, the master keyboard gate in `player.gd`, the I-key inventory
gate, the Tab bar-toggle in `hud.gd`, and the run-reset block in `game_state.gd`. Since race
select fires immediately after class select (before the player has ever had control), most of
these gates are moot in practice (nothing else can be open yet) — but the flag should still be
added for consistency and because `SaveManager`'s autosave-on-checkpoint logic (§6) may fire
during this window.

---

## 6. Save/load

`Stats.to_dict()`/`from_dict()` already serialize `character_class`; race needs identical
treatment:

```gdscript
# Stats.to_dict()
d["character_race"] = int(character_race)
d["race_variant"] = race_variant
d["race_prof_ability"] = race_prof_ability
# darkvision_bonus, damage_resistances: NOT saved — re-derived by apply_race_defaults()

# Stats.from_dict()
character_race = int(d.get("character_race", CharacterRace.HUMAN)) as CharacterRace
race_variant = int(d.get("race_variant", 0))
race_prof_ability = int(d.get("race_prof_ability", -1))
apply_race_defaults()   # called right after apply_class_defaults(), same ordering as §2.3
```

`GameState.from_dict()` needs `give_race_starting_items()` called alongside the existing
`give_class_starting_items()` replay call (research point 7's line ~1805), same idempotency
requirement.

**Checkpoint timing**: `scripts/autoloads/CLAUDE.md` documents the floor-1-load / class-pick
checkpoint via `class_chosen`. Since race select now sits between class pick and actual control,
the autosave checkpoint should move to fire on the **new** `race_chosen` signal instead of (or
in addition to) `class_chosen` — otherwise a save taken between class-pick and race-pick would
resume mid-race-select with no way to reopen the overlay. Flagged as **open question #9**: verify
exactly how `SaveManager` currently subscribes to `class_chosen` and shift/duplicate that
subscription to `race_chosen`.

**Continue-flow (`class_select.gd._on_continue_pressed()`)**: unaffected — a continued run has
already recorded race in the save, `from_dict()` restores it, race select never spawns.

---

## 7. What must NOT change

- `Stats.CharacterClass`, `apply_class_defaults()`'s existing match arms, class-select's
  starting-item dispatch — zero edits beyond the race-picker spawn-site swap (§4.2).
- `CombatMath.roll_with_adv_disadv()` itself — reroll wrappers (§5.2) call it, they don't modify
  it.
- `TurnManager` — race select, like all onboarding overlays, is turn-free modal UI.
- The mastery picker's own logic — only its *spawn site* moves (from `class_select.gd` into
  `race_select.gd`'s confirm handler, §4.2); nothing about cap/toggle logic changes.

---

## 8. Open questions (owner sign-off needed before implementation)

1. **Class-then-race defaults ordering** (§2.3): confirmed no race grants raw ability-score
   bonuses today — flag if that changes later, since ordering matters the moment one does.
2. **Exact death-check hook site for Orc's Relentless Endurance** (§3.1) — needs a fresh grep at
   implementation time to find where `current_hp <= 0` currently triggers death.
3. **Which abilities count as "didn't cost the whole turn" for Orc's momentum trait** (§3.1) —
   needs a concrete list; this doc only specifies the signal-driven pattern, not the emit sites.
4. **Human/Halfling reroll centralization** (§3.2, §3.3, §5.2) — recommend new shared
   `CombatMath` helpers; confirm this is preferred over five inline per-site checks.
5. **Elf's exact rest-shortening ratio and scope** (§3.5) — long-rest-only vs. also short rest;
   this doc defaults to halving `LONG_REST_TURNS` only.
6. **Elf sub-race ability minimal-implementation shapes** (§3.5) — confirm the
   stub/reduced-scope versions (debuff-radius Darkness, teleport Misty Step, detection-radius
   Pass Without Trace) are acceptable ahead of real spellcasting, or defer sub-race abilities
   (keep just the choice recorded) until spellcasting lands.
7. **Dragonborn resistance requires a `take_damage()` signature change with wide ripple** (§3.6)
   — recommend deferring to align with the already-designed (unimplemented) enemy stat-block
   resist/immune/vuln system, or scoping narrowly to weapon-damage-type sources only.
8. **Is the Dragonborn breath weapon in scope for this pass at all**, or just the ancestry
   choice + resistance (§3.6)?
9. **SaveManager checkpoint timing shift from `class_chosen` to `race_chosen`** (§6) — needs
   verification of current subscription code before deciding whether to move or duplicate it.

---

## 9. Out of scope (explicitly)

- Real icon/portrait assets for race cards — placeholder-until-supplied, same convention as the
  mastery picker (`ResourceLoader.exists()` guard).
- Full 5e-accurate breath-weapon shapes (cone/line save-based AoE) — this game has no save
  system or AoE targeting yet (`docs/architecture/spellcasting-design.md` covers that
  separately, unimplemented).
- A general damage-resistance/immunity/vulnerability system for enemies — already designed
  separately in `docs/architecture/enemy-stat-block-design.md`; Dragonborn resistance either
  waits for it or ships narrowly scoped (§8, open question 7).
- Multiclass/race-respec — not requested; `apply_race_defaults()` is written idempotently
  (always fully re-derives from `character_race`/`race_variant`) so a future respec feature could
  call it again safely, but no UI for that is in scope here.

---

## 10. Implementation checklist (suggested commit breakdown)

1. **Data layer**: `Stats.CharacterRace`/`ElfSubrace`/`DragonbornAncestry` enums, new fields
   (§2.2), `apply_race_defaults()` (§2.3), Dwarf's `_hp_per_level()` hook (§2.4),
   `_grant_ability_proficiency()` (§2.5). Commit.
2. **FOV hook**: `dungeon_floor.gd`'s `FOV_RADIUS` → `FOV_BASE_RADIUS` + `_current_fov_radius()`
   at both call sites (§5.1). Commit — independently testable (darkvision_bonus manually set via
   debug panel) before any UI exists.
3. **Race select UI**: `scripts/ui/race_select.gd` (§4.1), sub-choice mechanism (§4.3),
   `GameState.choose_race()`/`race_picker_open`/`race_chosen` (§4.4, §5.3). Commit.
4. **Integration**: spawn-site swap in `class_select.gd` (§4.2), input-gate additions for
   `race_picker_open` (§5.3). Commit.
5. **Reroll mechanics**: `CombatMath` helpers for Human/Halfling (§5.2), wired into all five
   attack call sites. Commit — the trickiest piece, do it after the rest of the flow is
   confirmed working.
6. **Orc mechanics**: Relentless Endurance hook (§3.1, pending open question 2) +
   `long_rest()` reset; momentum→temp-HP signal (§3.1, pending open question 3, may ship as a
   stub/no-op until the trigger list is confirmed). Commit.
7. **Elf sub-race abilities**: pending open question 6 — either minimal stub implementations or
   choice-recorded-only. Commit.
8. **Dragonborn**: ancestry choice + `damage_resistances` field, deferred/narrowly-scoped
   resistance application pending open question 7; breath weapon pending open question 8.
   Commit.
9. **Save/load**: `Stats.to_dict()`/`from_dict()` race fields (§6), `GameState.from_dict()`
   replay call, `SaveManager` checkpoint shift (§6, pending open question 9). Commit.
10. **Docs**: new "Race system" section in `scripts/entities/CLAUDE.md` (Stats fields, race
    mechanics table), `scripts/ui/CLAUDE.md` (race_select.gd pattern), `scripts/autoloads/CLAUDE.md`
    (new flag/signal, FOV hook, long-rest resource additions), pointer line in root `CLAUDE.md`.
    Commit.

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without
asking. Don't squash into one giant commit.
