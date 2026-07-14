# Leveled Spells & Spell Slots — Implementation Plan (Wizard)

Status: **design only, nothing implemented.** Narrow, actionable follow-up to
`docs/architecture/spellcasting-design.md` (the "framework doc" below) — that doc specced the
full D&D 5.5e casting framework (concentration, AoE, reactions, enemy casters, multiclass
future-proofing) and is still the reference for all of that. **This doc supersedes exactly two
parts of it for the Wizard's leveled-spell implementation:**

- Framework doc §4.2's `prepared_max() = ability_mod + caster_level` formula — replaced by §2
  below (`prepared_max = character_level`, cantrips excluded, decided directly with the project
  owner).
- Framework doc §5.4's "no spellbook overlay, ability-bar auto-paging only" decision (also
  recorded as resolved in its §13.1) — this doc adds a dedicated Spellbook overlay (§5) for
  choosing what's prepared, while **casting itself still happens on the ability bar exactly as
  the framework doc designed** (auto-paging included) — nothing about the casting UX changes.

Everything else in the framework doc — `Spell`/`SpellSlotPool`/`ActiveSpellEffect` shapes,
`SpellEffects.cast_spell()`'s resolution sequence, concentration, AoE tile math, reactions,
enemy casters, the D&D-adaptation decisions in its §10 — stands unchanged and this doc builds on
top of it. Read that doc first; this one only fills in the pieces it deliberately left as
"future work": actual spell slots, prepared-spell management, and how a Wizard's spellbook
grows.

Scope fixed with the project owner (Q&A, recorded here as this doc's own "fixed owner
decisions" the same way the framework doc has its §1.1):

1. **Wizard only.** No half-caster/pact-caster table work in this doc — the framework doc's §3
   tables cover those for whenever a second caster class exists. Don't build
   `StandardSlotPool`/`SpellSlotPool` as an abstract hierarchy speculatively for casters that
   don't exist; reuse the framework doc's base-class shape (§4.3) exactly since it already
   isolates the "how a slot pool works" question behind one interface — the abstraction from
   that doc is already exactly the right size, just implement `StandardSlotPool` for real
   (`PactSlotPool`/`CooldownSlotPool` stay unimplemented until a class needs them).
2. **Slot table**: the standard D&D 2024 full-caster progression, levels 1–20 (§1 below).
   **Recharge: long rest only**, full refill — matches `StandardSlotPool.on_long_rest()` /
   `on_short_rest() = pass` in the framework doc §4.3 exactly, no deviation.
3. **Prepared count**: `character_level` leveled (non-cantrip) spells, period — level 1 → 1
   prepared, level 20 → 20 prepared. Cantrips never count against this (separate system,
   untouched, already free/always-castable). Changes only on a completed long rest.
4. **Known spells (spellbook) growth — overrides the framework doc's simpler model**:
   - **Every single level-up** (levels 2 through 20, not just even levels) offers the Wizard a
     choice of **3 random spells** from the Wizard class list (candidates restricted to spell
     levels the character can currently prepare — see §4.1) and the player picks **1** to add
     to the known spellbook. Blocking one-time picker, same trigger point as the talent picker.
   - **Scrolls**: using a Scroll item that matches a known spell ID teaches it directly into the
     spellbook (classic D&D scroll-copying), independent of the level-up picker. Scroll item
     content itself is out of scope for this doc (existing `Item.Type.SCROLL` items don't yet
     carry a `taught_spell_id` field — see §6).
   - **Level 1 starting spellbook**: 3 fixed level-1 spells (not player-chosen — the level-up
     picker is the "choice" mechanic; level 1 needs *something* prepared and prepared cap is
     only 1, so a small fixed set is enough to make that one choice meaningful without needing
     a character-creation picker of its own). See §4.4.
   - Known spellbook has no cap beyond what the class spell list contains at each level;
     prepared is the sole constraint.
5. **UI**: **R** opens a Spellbook overlay (§5) — level tabs, hover-for-description, click to
   toggle prepared, bottom-right "X / Y prepared" counter (mastery-picker visual precedent).
   The level-up spell choice is a **separate** one-time blocking picker (§4.1), modeled on
   `talent_picker.gd`'s post-level-up spawn — not the same overlay as the Spellbook. Additionally,
   a known spell row can be **dragged directly from the Spellbook onto a specific ability-bar
   slot** (§5.5) for convenient placement — but **only onto an ability-bar page (the player's
   "2nd–4th quickbar"). The item quickbar (page 1) and the inventory bag are always invalid drop
   targets**, rejected outright with no state change.
6. **Casting surface unchanged**: prepared spells appear on the existing ability bar exactly
   like cantrips already do (`ability_id = "spell:" + spell_id`, framework doc §5.4's
   `PlayerSpellcasting.begin_cast()` flow, already implemented for cantrips — see
   `scripts/entities/player_spellcasting.gd`). Toggling prepared in the Spellbook
   adds/removes the ability-bar entry (§5.3); it does not add a second way to cast.
7. **Content scope**: 5 example leveled spells (levels 1–3) to prove the slot/upcast/prepared
   loop end-to-end — not a full class list. Framework doc §12.2/§12.3 already worked Magic
   Missile (1st) and Fireball (3rd) in full; this doc adds 3 more small level-1/2 examples so
   the level-up picker and the Spellbook's per-level tabs have enough real data to be
   meaningfully testable (a 1-spell-per-level list makes every level-up choice a non-choice).
   Full spell list (dozens of spells across 9 levels) is explicitly deferred (§8).

---

## 1. The verified D&D 2024 full-caster spell slot table (levels 1–20)

Standard Player's Handbook (2024) full-caster (Wizard/Cleric/Druid/Bard/Sorcerer) slot
progression. This is the real published table, not an approximation:

| Lvl | 1st | 2nd | 3rd | 4th | 5th | 6th | 7th | 8th | 9th |
|---|---|---|---|---|---|---|---|---|---|
| 1  | 2 | – | – | – | – | – | – | – | – |
| 2  | 3 | – | – | – | – | – | – | – | – |
| 3  | 4 | 2 | – | – | – | – | – | – | – |
| 4  | 4 | 3 | – | – | – | – | – | – | – |
| 5  | 4 | 3 | 2 | – | – | – | – | – | – |
| 6  | 4 | 3 | 3 | – | – | – | – | – | – |
| 7  | 4 | 3 | 3 | 1 | – | – | – | – | – |
| 8  | 4 | 3 | 3 | 2 | – | – | – | – | – |
| 9  | 4 | 3 | 3 | 3 | 1 | – | – | – | – |
| 10 | 4 | 3 | 3 | 3 | 2 | – | – | – | – |
| 11 | 4 | 3 | 3 | 3 | 2 | 1 | – | – | – |
| 12 | 4 | 3 | 3 | 3 | 2 | 1 | – | – | – |
| 13 | 4 | 3 | 3 | 3 | 2 | 1 | 1 | – | – |
| 14 | 4 | 3 | 3 | 3 | 2 | 1 | 1 | – | – |
| 15 | 4 | 3 | 3 | 3 | 2 | 1 | 1 | 1 | – |
| 16 | 4 | 3 | 3 | 3 | 2 | 1 | 1 | 1 | – |
| 17 | 4 | 3 | 3 | 3 | 2 | 1 | 1 | 1 | 1 |
| 18 | 4 | 3 | 3 | 3 | 3 | 1 | 1 | 1 | 1 |
| 19 | 4 | 3 | 3 | 3 | 3 | 2 | 1 | 1 | 1 |
| 20 | 4 | 3 | 3 | 3 | 3 | 2 | 2 | 1 | 1 |

Confirms the pattern the owner independently restated: a new spell-level tier's first slot
unlocks at odd character levels 3/5/7/9/11/13/15/17 (2nd through 9th level spells
respectively) — exactly this table, no adjustment needed.

The game's level curve is uncapped in code (`Stats.exp_for_level(lv) = lv * 10`, no ceiling —
see `scripts/entities/stats.gd`), but no content currently goes past floor 10 (~character level
12 per root `CLAUDE.md`). **Decision: implement the full 1–20 table anyway** (it's the same
`Dictionary` either way, costs nothing extra) so nothing needs revisiting if the level curve or
floor count grows later; levels beyond 20 hold at the level-20 row (`mini(character_level, 20)`
lookup).

---

## 2. `StandardSlotPool` — the real implementation

The framework doc's §4.3 already specced this class's interface and behavior; this section
just nails down the table source and confirms every method as described there applies verbatim
(long-rest-only refill, live-computed max, no short-rest recharge).

```gdscript
# scripts/items/spell_slot_pool.gd
class_name SpellSlotPool
extends Resource

func available_cast_levels(spell: Spell) -> Array[int]: return []
func can_cast(spell: Spell) -> bool: return not available_cast_levels(spell).is_empty()
func consume(cast_level: int) -> void: pass
func on_long_rest() -> void: pass
func on_short_rest() -> void: pass
func ui_summary() -> String: return ""


class_name StandardSlotPool
extends SpellSlotPool

const SLOT_TABLE: Dictionary = {
    1: {1: 2},
    2: {1: 3},
    3: {1: 4, 2: 2},
    4: {1: 4, 2: 3},
    5: {1: 4, 2: 3, 3: 2},
    6: {1: 4, 2: 3, 3: 3},
    7: {1: 4, 2: 3, 3: 3, 4: 1},
    8: {1: 4, 2: 3, 3: 3, 4: 2},
    9: {1: 4, 2: 3, 3: 3, 4: 3, 5: 1},
    10: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2},
    11: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1},
    12: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1},
    13: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1},
    14: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1},
    15: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1},
    16: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1},
    17: {1: 4, 2: 3, 3: 3, 4: 3, 5: 2, 6: 1, 7: 1, 8: 1, 9: 1},
    18: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 1, 7: 1, 8: 1, 9: 1},
    19: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 2, 7: 1, 8: 1, 9: 1},
    20: {1: 4, 2: 3, 3: 3, 4: 3, 5: 3, 6: 2, 7: 2, 8: 1, 9: 1},
}

var owner_stats: Stats
var remaining: Dictionary = {}   # slot_level:int -> remaining:int

func _max_slots() -> Dictionary:
    var lv: int = mini(owner_stats.character_level, 20)
    return SLOT_TABLE.get(lv, {})

func available_cast_levels(spell: Spell) -> Array[int]:
    if spell.level == 0:
        return [0]   # cantrips never touch this pool — PlayerSpellcasting short-circuits before calling
    var out: Array[int] = []
    for lv: int in _max_slots():
        if lv >= spell.level and remaining.get(lv, 0) > 0:
            out.append(lv)
    out.sort()
    return out

func consume(cast_level: int) -> void:
    remaining[cast_level] = remaining.get(cast_level, 0) - 1

func on_long_rest() -> void:
    remaining = _max_slots().duplicate()   # full refill; new slots from a level-up arrive already full here (long rest is the only refill point, so "arrives empty" from the framework doc doesn't apply the same way — see note below)

func on_short_rest() -> void:
    pass   # standard slots never recharge on short rest — owner decision #2

func ui_summary() -> String:
    var parts: PackedStringArray = []
    for lv: int in _max_slots():
        parts.append("%d/%d" % [remaining.get(lv, 0), _max_slots()[lv]])
    return " ● ".join(parts)
```

**Deviation from the framework doc's "new slots arrive empty" note (§4.3)**: that note assumed
short-rest recharge existed for *some* pool types, so an empty-on-grant slot wouldn't strand the
player until a long rest that might be far off. Here, **every** slot only ever refills on long
rest, so if a level-up's new slot arrived empty the player couldn't use it until the *next* long
rest even though they just gained it — clearly wrong. **Decision: `_max_slots()` is always
computed live and `remaining` is topped up (not reset) whenever the max grows outside of
`on_long_rest()`** — i.e. `GameState.gain_exp()`'s level-up path (mirroring how it already tops
up `hit_dice` and `rage_uses_remaining` on level-up, see `scripts/autoloads/game_state.gd:750-763`)
calls a new `player_stats.caster.slot_pool.grant_new_slots_on_levelup()`:

```gdscript
func grant_new_slots_on_levelup(old_max: Dictionary) -> void:
    var new_max: Dictionary = _max_slots()
    for lv: int in new_max:
        var delta: int = new_max[lv] - old_max.get(lv, 0)
        if delta > 0:
            remaining[lv] = remaining.get(lv, 0) + delta
```

Concretely: `GameState.gain_exp()` snapshots `old_slot_max := caster.slot_pool._max_slots()`
before calling `player_stats.gain_exp(amount)` (same pattern as its existing
`old_rage_max`/`old_max_hit_dice` snapshots), then after the level applies, calls
`caster.slot_pool.grant_new_slots_on_levelup(old_slot_max)` — so a freshly unlocked 3rd-level
slot at level 5 is immediately castable, not stuck empty until the next long rest. This is a
small, deliberate deviation from the framework doc's generic-pool wording, justified because
Wizard has only one pool type and no short-rest recharge to fall back on.

---

## 3. `SpellcasterState` additions

The implemented cantrip-only `SpellcasterState` (`scripts/items/spellcaster_state.gd`) has just
`spellcasting_ability` + `known_spells`. It needs the framework doc's prepared/known split
(§4.2) plus the pool:

```gdscript
# scripts/items/spellcaster_state.gd — additions
@export var known_spells: Array[String] = []      # existing field — now holds ALL known spells:
                                                    # cantrips (unlimited, always castable) AND
                                                    # leveled spells (spellbook, subset prepared)
@export var prepared_spells: Array[String] = []    # NEW — today's prepared leveled spells (never cantrips)

var slot_pool: StandardSlotPool = null             # NEW — null until Wizard's caster init grants one

func prepared_max(stats: Stats) -> int:            # NEW — supersedes framework doc §4.2's formula
    return stats.character_level

func castable_leveled_spells() -> Array[String]:   # NEW
    return prepared_spells

func is_cantrip(spell_id: String) -> bool:         # NEW — SpellDb.get_spell(id).level == 0
    var s: Spell = SpellDb.get_spell(spell_id)
    return s != null and s.level == 0
```

`known_spells` staying one array for both cantrips and leveled spells keeps `choose_cantrip()`
untouched (it already just appends to `known_spells`) — the "is this a cantrip" question is
answered by looking up `Spell.level`, not by which array it lives in. `prepared_spells` is the
new array; cantrips never enter it (they're unconditionally castable, same as today — see §5.3
for exactly where this distinction is enforced in the ability-bar sync).

---

## 4. Spellbook growth

### 4.1 Level-up spell-choice picker

New file `scripts/ui/spell_learn_picker.gd`, one-time blocking overlay, same tier/pattern as
`scripts/ui/talent_picker.gd`'s post-level-up spawn (`hud.gd._on_player_leveled_up()` — that
function already exists and currently only checks `talent_points_available > 0`; it gains a
second, independent check).

**Trigger**: `GameState.gain_exp()`'s level-up block (`scripts/autoloads/game_state.gd:738-779`)
gains, alongside its existing tier-point/hit-dice/rage grants: if
`player_stats.character_class == Stats.CharacterClass.WIZARD`, roll 3 random spell IDs via
`SpellDb.CLASS_SPELL_LISTS["WIZARD"]` (new const, §6) filtered to `spell.level > 0 and
spell.level <= _max_prepareable_level(new character_level)` (i.e. only offer spells whose level
the slot table actually grants a slot for at this level — no point offering a 4th-level spell at
character level 5) and NOT already in `known_spells`; set `GameState.spell_learn_pending = true`
and store the 3 rolled IDs in `GameState.spell_learn_choices: Array[String]`. `hud.gd`'s
existing `_on_player_leveled_up()` handler spawns `spell_learn_picker.gd` when
`GameState.spell_learn_pending` is true (in addition to, not instead of, the existing talent
picker spawn — both can be pending after one level-up; picker order: talent picker first if
both are pending, mirroring "highest-cost UI first" — exact ordering is an implementation
judgment call, not load-bearing).

If fewer than 3 eligible spells remain (small class list, §7), show however many are available
(1 or 2); if zero remain, skip the picker entirely and log a gray "No new spells available to
learn." line instead of blocking on an empty choice.

**Picker UI**: CanvasLayer (same layer as `talent_picker.gd`), 3 spell cards (name, level,
one-line description, `Spell.icon_path` via the same `ResourceLoader.exists()` guard cantrips
already use in `hud.gd._refresh_ability_bar()`). Click a card → `GameState.learn_spell(id)`
(appends to `caster.known_spells`, clears `spell_learn_pending`, closes picker, logs
`"You add <name> to your spellbook."`). No "skip" option — matches the owner's framing of this
as a mandatory level-up choice, same rigidity as the talent picker.

**GameState additions**:
```gdscript
var spell_learn_pending: bool = false
var spell_learn_choices: Array[String] = []
var spell_learn_picker_open: bool = false   # input-block flag, added to the same guard chains
                                              # `mastery_picker_open` already sits in — see player.gd:455-473

func learn_spell(spell_id: String) -> void:
    if player_stats.caster == null:
        return
    if not player_stats.caster.known_spells.has(spell_id):
        player_stats.caster.known_spells.append(spell_id)
    spell_learn_pending = false
    spell_learn_choices.clear()
    var s: Spell = SpellDb.get_spell(spell_id)
    if s != null:
        game_log("[color=lime]You add %s to your spellbook.[/color]" % s.spell_name)
```

### 4.2 Scroll-taught spells

`Item` gains one new field: `taught_spell_id: String = ""` (empty = not a spell scroll — every
existing SCROLL item stays a no-op). Mirrors the "add field → update `to_dict()`/`from_dict()` +
`debug_panel.ALL_ITEMS`" rule in `scripts/items/CLAUDE.md`. `GameState.use_item()`'s SCROLL
branch (currently unimplemented/stubbed per that file, "no combat stats of its own" precedent
for TOOL items — verify current behavior before wiring) gains: if
`item.taught_spell_id != "" and player_stats.caster != null`, call
`learn_spell(item.taught_spell_id)` and consume the scroll item; if the spell is already known,
log "You already know this spell." and do not consume it (matches typical D&D scroll-of-a-known-
spell handling — no benefit, no waste). Actual Scroll item content (which spells get scrolls,
where they spawn) is deferred (§8) — this section only specs the mechanism.

### 4.3 Starting spellbook (level 1)

Wizard's `_give_wizard_starting_items()` (new function, sibling to
`_give_barbarian_starting_items()`/`_give_monk_starting_items()` in `game_state.gd`) sets
`caster.known_spells` to 3 fixed level-1 spell IDs from §7's example list (not player-chosen —
consistent with how the framework doc's original 6-cantrip-adjacent number was itself a fixed
starting set) and `caster.prepared_spells` to 1 of those 3 (also fixed, since `prepared_max()`
at level 1 is exactly 1 — pick whichever is most illustrative, e.g. Magic Missile). The player
can immediately open the Spellbook (§5) and swap which of the 3 known spells is prepared even
before their first long rest, since nothing in §5's UI gates "can I change prepared" on having
completed a rest — see §5.5 for why that's fine.

### 4.4 Persistence

`Stats.to_dict()`/`from_dict()` (see `scripts/entities/CLAUDE.md`'s Stats section) needs a new
`"caster"` sub-dict when `caster != null`: `{"known_spells": [...], "prepared_spells": [...],
"slot_remaining": {"1": 2, "2": 0, ...}}`. `from_dict()` rebuilds `caster` the same way
`apply_class_defaults()` already does for a fresh Wizard, then overwrites `known_spells`/
`prepared_spells`/`slot_pool.remaining` from the saved dict — same "computed fields re-derived,
mutable fields restored" split every other `to_dict()`/`from_dict()` pair in this codebase
follows (see `scripts/autoloads/CLAUDE.md`'s SaveManager section). `slot_pool._max_slots()` is
never serialized (it's computed live from `character_level`, already restored by the time this
runs) — only `remaining` (the mutable part) is saved.

---

## 5. Spellbook overlay (`R` key)

New file `scripts/ui/spellbook_overlay.gd`. Verified: `R` is not bound anywhere else in
`player.gd`/`hud.gd` at time of writing.

### 5.1 Trigger & input gating

`player.gd`'s `_unhandled_input()` gains a case beside the existing `KEY_I`/`KEY_T` regardless-
of-phase handlers (`:454-469`): `KEY_R` opens the Spellbook if `player_stats.caster != null`
(non-Wizards: no-op, no error) and none of the other blocking overlays are open (reuse the
exact guard list at `player.gd:462-466`, plus the new `spell_learn_picker_open` from §4.1) —
`GameState.spellbook_open = true`, spawn `scripts/ui/spellbook_overlay.gd`. The overlay's own
`_close()` sets it back to `false`. This flag also needs adding to the master input-gate
conjunction at `player.gd:470-474` (blocks movement/attack input while the book is open) exactly
where `mastery_picker_open` etc. already sit.

### 5.2 Layout (mirrors `mastery_picker.gd` / `short_rest_panel.gd` precedent)

- **CanvasLayer**, same layer tier as the mastery picker.
- **Level tabs** across the top: one tab per spell level from 1 up to
  `_max_slots().keys().max()` at the player's current character level (i.e. only show tabs for
  levels the character actually has slots for — a level-3 Wizard sees tabs "1st, 2nd", not
  "1st..9th" with 7 empty ones). No cantrip tab — cantrips stay purely on the ability bar,
  untouched by this overlay. Tab click filters the list below to `known_spells` of that level.
- **Spell list** (selected tab): one row per known spell of that level — icon, name, a
  prepared/unprepared toggle indicator (checkbox-style, same visual language as the mastery
  picker's slot buttons — filled/highlighted when prepared).
- **Hover** a row → description panel updates (reuses `mastery_picker.gd`'s `_detail_name`/
  `_detail_desc` pattern verbatim — that picker already shows a name+description panel on
  hover, not a `[url=]` tooltip; follow that exact precedent here for consistency, since both
  pickers are the same "browse and pick" interaction shape).
- **Click a row** → toggle prepared: if already prepared, unprepare it (always allowed). If not
  prepared and `prepared_spells.size() < prepared_max()`, prepare it. If not prepared and at
  cap, do nothing but flash the counter red for a beat (same "click at cap" feedback
  `mastery_picker.gd` gives — verify exact mechanism there and mirror it, likely just a
  momentary color change on `_counter_rtl`, no error dialog).
- **Bottom-right counter**: `RichTextLabel`, "X / Y prepared" — identical control/positioning
  pattern to `mastery_picker.gd`'s `_counter_rtl` (`_counter_rtl.text = "[right][color=%s]%d /
  %d[/color][/right]" % [...]`, `scripts/ui/mastery_picker.gd:206`).
- **No confirm/close button needed to "commit"** — see §5.5 for why every toggle applies
  immediately. A plain Esc-to-close (or a small ✕) suffices, matching `_unhandled_input()`
  patterns in the other pickers.

### 5.3 `GameState.set_spell_prepared()` — the ability-bar sync point

```gdscript
func set_spell_prepared(spell_id: String, prepared: bool) -> bool:
    var caster: SpellcasterState = player_stats.caster
    if caster == null or not caster.known_spells.has(spell_id):
        return false
    if prepared:
        if caster.prepared_spells.has(spell_id):
            return true
        if caster.prepared_spells.size() >= caster.prepared_max(player_stats):
            return false
        caster.prepared_spells.append(spell_id)
        var s: Spell = SpellDb.get_spell(spell_id)
        var ab := Ability.new()
        ab.ability_id = "spell:" + spell_id
        ab.ability_name = s.spell_name
        ab.description = s.description
        ab.icon_path = s.icon_path
        ab.uses_max = 0   # slot state lives in slot_pool, not uses_remaining — framework doc §5.4
        add_ability(ab)
    else:
        caster.prepared_spells.erase(spell_id)
        _remove_ability_by_id("spell:" + spell_id)   # NEW helper — see below
    return true
```

`_find_ability_by_id()` already exists (`game_state.gd:486`) but there is currently **no**
`remove_ability()`/equivalent anywhere in the codebase — every existing ability-bar entry is
either permanent (Rage, weapon passives) or persists for the run once granted (Tier 2 base
abilities are only stripped by the God-Mode-only `debug_switch_subclass()`, which does its own
manual `player_ability_bar[i] = null` + `ability_bar_changed.emit()`). **New function needed**:

```gdscript
func _remove_ability_by_id(id: String) -> void:
    for i: int in ABILITY_BAR_SIZE:
        var slot: Ability = player_ability_bar[i] as Ability
        if slot != null and slot.ability_id == id:
            player_ability_bar[i] = null
            ability_bar_changed.emit()
            return
```

(If `player_ability_bar` has already become `Array[Array]` per the framework doc's auto-paging
decision by the time this is implemented, this loop needs to walk pages — same change
`_find_ability_by_id()`/`add_ability()` themselves will need; not this doc's concern, just note
the coupling.)

### 5.4 Drag & drop from the Spellbook into the ability quickbar

Added per explicit follow-up from the project owner: clicking a Spellbook row to toggle prepared
(§5.2) still works and still auto-places into the first empty ability-bar slot via `add_ability()`
(§5.3) — but the player should also be able to **drag** a known spell row straight onto a chosen
ability-bar slot for convenient, deliberate placement, restricted to ability-bar pages only.

**Why this needs new plumbing, not just reuse**: `inventory_overlay.gd`'s existing drag system
(`_finish_drag()`/`_do_move()`, `scripts/ui/inventory_overlay.gd:375-406`) is entirely
`Item`-based — it drags `Item` resources between quickbar/bag/equipment slots via
`GameState.move_item(src, src_idx, src_sname, dest_src, dest_idx, dest_sname)`. Abilities
(`player_ability_bar`) have **no drag system at all today** — every existing ability-bar entry is
placed exclusively by `add_ability()` auto-filling the first empty slot (§5.3), and nothing in the
codebase currently supports manually repositioning or targeting a specific ability-bar slot. This
is new capability, not a reuse of the item-drag path.

**Mechanism** (mirrors the *shape* of `inventory_overlay.gd`'s press/release drag — floating icon
under the cursor, rect hit-testing on release — but is its own implementation, since source rows
live in `spellbook_overlay.gd`, a different CanvasLayer than the HUD's ability bar):

1. Press-and-hold on a known-spell row in the Spellbook (§5.2's list) starts a drag: spawn a
   floating `TextureRect` of the spell's icon following the mouse, same visual as
   `inventory_overlay.gd._finish_drag()`'s `_drag_icon` (`custom_minimum_size`/`stretch_mode`/
   `texture_filter` copied verbatim for consistency). Record the dragged `spell_id`.
2. On release, hit-test against the **HUD's ability-bar slot Controls** (`hud.gd`'s existing
   ability-bar slot array, whichever page is currently visible per the framework doc's
   auto-paging — framework doc §5.4's Tab-toggle/page-flip UI). The Spellbook overlay sits above the HUD
   (`spellbook_overlay.gd`'s CanvasLayer must render above the HUD's, or hit-testing needs to
   read HUD slot screen-rects directly — same cross-CanvasLayer concern `hud.gd`'s existing drag
   already has to solve for its own slots, no new pattern needed here).
3. **Valid drop target**: any ability-bar slot on any ability-bar page. **Invalid drop targets**
   (rejected — icon snaps back to the Spellbook row, no state change, no error dialog, just a
   quiet miss): the item quickbar (page 1 — `hud.gd`'s `_bar_mode_label` "ITEMS" mode), any
   inventory-overlay slot (bag/equipment), and dropping outside any slot entirely. This is a
   **hard rule**, not a UX nicety — the item quickbar's slot semantics (`Item` resources, `Item`-
   typed drag payload) are incompatible with placing an `Ability`/spell there; the check is a
   simple `dest is HUD ability-bar slot` type/source gate, mirroring `_do_move()`'s existing
   `dest_src == "equipment"` gate pattern.
4. On a valid drop: `GameState.place_spell_in_slot(spell_id, page: int, index: int)` (new
   function):
   ```gdscript
   func place_spell_in_slot(spell_id: String, page: int, index: int) -> bool:
       var caster: SpellcasterState = player_stats.caster
       if caster == null or not caster.known_spells.has(spell_id):
           return false
       if not caster.prepared_spells.has(spell_id):
           if caster.prepared_spells.size() >= caster.prepared_max(player_stats):
               return false   # not prepared and no room to prepare it — reject the drop
           caster.prepared_spells.append(spell_id)
       # Build (or find, if already placed elsewhere from a prior prepare) the Ability, then
       # either move it or place it fresh directly into the target slot — swap with whatever
       # already occupies that slot (mirrors GameState.move_item()'s bag-to-bag swap behavior)
       # rather than rejecting an occupied target.
       var existing: Ability = _find_ability_by_id("spell:" + spell_id)
       var displaced: Ability = player_ability_bar[page][index]   # once Array[Array] per framework doc §5.4
       if existing != null:
           _remove_ability_by_id("spell:" + spell_id)   # §5.3
       else:
           existing = _build_spell_ability(spell_id)     # factored out of set_spell_prepared()'s inline Ability construction
       player_ability_bar[page][index] = existing
       if displaced != null and existing != displaced:
           add_ability(displaced)   # bumped entry re-homes to the first empty slot, doesn't vanish
       ability_bar_changed.emit()
       return true
   ```
   Dropping an **already-prepared** spell onto a different slot is a pure reposition (no
   `prepared_spells` change, `existing != null` branch). Dropping a **not-yet-prepared** spell
   directly onto a chosen slot both prepares it and places it there in one motion — a genuine
   shortcut over "click to prepare (auto-placed) then no way to move it," which is the whole
   point of adding drag support.
5. Dropping onto an **occupied** ability-bar slot swaps the displaced entry back into the bar via
   the existing `add_ability()` auto-placement (first empty slot) rather than discarding it —
   consistent with "abilities are never silently lost" (nothing in the current codebase ever
   deletes an ability except explicit unprepare, §5.3).

**Not in scope for this section**: reordering *non-spell* abilities (Rage, weapon passives, Tier
2 base abilities) via drag — those still only ever land via their own grant call sites. This
drag mechanism is Spellbook-row-sourced only; it doesn't retrofit general ability-bar
drag-and-drop for everything else. If that's wanted later, `place_spell_in_slot()`'s swap logic
is the template to generalize.

### 5.5 Why no "commit" step / no long-rest gating on changes

The framework doc's original Prepare-Spells picker (§4.2) only opens after a long rest,
mirroring real D&D's "prepare spells during a long rest" flavor. **Decision for this
implementation: skip that gating.** The Spellbook can be opened and prepared spells changed
**any time** outside of combat-blocking overlays, not just post-long-rest. Reasoning: (a) the
owner's requirements describe pressing R to open the book at will, with no mention of a
rest-gated reselection prompt (unlike the Mastery Picker's `mastery_reselect_prompt.gd`, which
*is* explicitly rest-gated); (b) `prepared_max()` itself only changes on level-up, and slots
only refill on long rest, so there's no exploit — swapping which spells are prepared mid-floor
doesn't grant extra resources, it only changes which of your already-known spells your ability
bar currently exposes; (c) it's strictly simpler to implement (no reselection-prompt overlay,
no "pending swap" state to track). If this turns out to feel wrong in play (e.g. players
constantly tabbing the book open mid-fight to reconfigure), the fix is adding a
`spellbook_open` cooldown or copying the mastery-reselect-prompt gating pattern — flagged as a
balance call for the implementing session, not a blocker.

---

## 6. `SpellDb` / `Spell` additions

The cantrip-only `Spell` (`scripts/items/spell.gd`) is missing every field a leveled spell
needs: no `level` beyond 0 in practice, no `Resolution.SAVE`/`AUTO_HIT` (only `ATTACK_ROLL`
exists), no upcast fields, no AoE/target-kind fields. **This doc does not re-derive those** —
the framework doc's full `Spell` shape (§4.1) is the target; extending the trimmed cantrip
`Spell` to that full shape is a mechanical superset change (add the missing `@export` fields,
widen the `Resolution` enum, wire `resolution == SAVE`/`AUTO_HIT` into
`SpellEffects.cast_spell()` alongside the existing `ATTACK_ROLL` path). Concretely needed for
the 5 example spells in §7: `Resolution.AUTO_HIT` (Magic Missile), `Resolution.SAVE` +
`save_stat`/`save_for_half` (Burning Hands-style), `upcast_dice_per_level`, `target_kind`/
`shape`/`shape_size` (at minimum `TargetKind.SELF` and `TargetKind.TILE`+`Shape.CONE` for one
AoE example — full AoE tile math per framework doc §6 is a prerequisite for that one spell, not
optional).

`SpellDb` gains:
```gdscript
const LEVELED_SPELL_IDS: Array[String] = ["magic_missile", "shield", "burning_hands", "misty_step", "scorching_ray"]
const CLASS_SPELL_LISTS: Dictionary = {"WIZARD": CANTRIP_IDS + LEVELED_SPELL_IDS}  # cantrips harmless to include; §4.1's level-up roll already filters by spell.level > 0
```

(`CLASS_SPELL_LISTS["WIZARD"]` including cantrip IDs is fine — §4.1's level-up roll excludes
anything already in `known_spells`, and the starting cantrip is already there by level 2's
first roll — but the roll also hard-filters `spell.level > 0` defensively, since a second
unchosen cantrip could otherwise theoretically surface. Note this filter explicitly in the
implementation, don't rely on the "already known" exclusion alone.)

---

## 7. Example spells (levels 1–3, proving the model)

Per owner decision #7 — 5 examples, reusing the framework doc's own worked spells where they
already exist rather than re-deriving:

1. **Magic Missile** (1st, auto-hit, upcast dart count) — **already fully worked** in framework
   doc §12.2, verbatim reusable.
2. **Fireball** (3rd, SAVE, sphere AoE, friendly fire, upcast dice) — **already fully worked**
   in framework doc §12.3, verbatim reusable. (Included here as a 3rd-level example even though
   it's the higher end of this doc's level-1–3 range — deliberately kept since it's the one
   spell in the framework doc that proves the AoE+SAVE+upcast combination together; re-deriving
   a different 3rd-level spell would duplicate that proof for no benefit.)
3. **Shield** (1st, SELF target, reaction OR just a same-turn free action in v1 — **decision:
   ship as a same-turn manual cast for this doc's scope, not a reaction**, since the framework
   doc's reaction broker (§8) is explicitly out of scope here; +5 AC until start of next turn,
   `ActiveSpellEffect` with `remaining_turns = 1`, `data = {"ac_bonus": 5}`, integrates via
   `recalculate_stats()` per framework doc §4.6/§10.6). Proves `TargetKind.SELF` +
   `ActiveSpellEffect` without requiring the reaction system.
4. **Burning Hands** (1st, SAVE for half, CONE AoE, `shape_size` tuned to ~2 tiles per the
   FOV-rescaling convention in framework doc §3/§12.3) — proves `Shape.CONE` (framework doc §6.2)
   as a second AoE shape distinct from Fireball's sphere.
5. **Misty Step** (2nd, no attack roll, no damage, `effect_id = "misty_step"` — teleports the
   caster to a chosen visible tile within `range_tiles`, `has_ranged_los()`-gated, walkable-tile
   check same as any forced-movement landing) — proves the `effect_id` escape hatch (framework
   doc §5.3) for a spell that's neither damage nor a status effect, and gives the level-2 tab a
   second occupant besides nothing (Magic Missile alone would make the level-1 tab crowded and
   level-2 empty, which makes the level-up picker's "3 random choices" degenerate at low
   levels — see the next paragraph).

**Content-count caveat, called out explicitly**: 5 spells across 3 levels means the level-up
picker (§4.1) runs out of eligible candidates almost immediately — by the 4th or 5th level-up
there may be 0–1 unlearned spells left to offer, which is a legitimate content gap, not a bug.
The picker's "show fewer than 3 if fewer are eligible" / "skip if zero eligible" fallback (§4.1)
exists specifically to degrade gracefully here. This is explicitly acceptable for this pass —
the mechanic proves itself with 5 spells and 1–2 real level-up choices; a full class list (§8's
non-goal) is what makes the level-up picker actually meaningful across a full run.

---

## 8. Non-goals / explicitly deferred

Mirrors the framework doc's own §2 style — everything below is out of scope for this
implementation pass:

- **Full Wizard spell list.** 5 examples only (§7); expanding to a real 1st–9th-level class list
  (dozens of spells) is future content work, not a systems change — the data model already
  supports it.
- **Half-casters, pact casters, multiclassing.** Framework doc §3/§10.8 already reserve the
  design space; this doc's `StandardSlotPool` is Wizard-only.
- **Concentration, AoE reactions, enemy spellcasting, Counterspell/Dispel.** Untouched — still
  exactly as designed (or deferred) in the framework doc §7–§10.4. The 5 example spells (§7)
  deliberately avoid needing concentration or reactions.
- **Scroll item content** (which spells get scrolls, where/how often they spawn as floor loot).
  Only the mechanism (`Item.taught_spell_id`, §4.2) is specced.
- **Rest-gated Spellbook access / reselection prompts.** Explicitly decided against in §5.5 —
  the book is always open-able.
- **General ability-bar drag-and-drop** for non-spell abilities (Rage, weapon passives, Tier 2
  base abilities). §5.4 only adds drag support for Spellbook rows; nothing else on the ability
  bar becomes draggable in this pass.
- **Spell components, ritual casting, metamagic-equivalents.** Framework doc §10.1/§10.2/§10.7
  already deferred these; unchanged here.
- **Upcast display polish beyond the framework doc's `upcast_summary()` (§10.9).** Reused as-is
  when the slot-level picker strip (framework doc §5.4 step 2) is wired up for leveled spells —
  cantrips never trigger it (`available_cast_levels` always `[0]`), leveled spells will now
  actually exercise that codepath for the first time.

---

## 9. Implementation sequence

Follows the framework doc §14's "suggested commit breakdown" convention — ordered so each step
leaves the game in a playable state:

1. **Data layer**: extend `Spell` (§6) to the full framework-doc shape (level/resolution/
   upcast/target/shape fields); add the 5 example spells to `SpellDb` (§7); add
   `SpellcasterState.prepared_spells`/`prepared_max()`/`slot_pool` (§3); write
   `SpellSlotPool`/`StandardSlotPool` (§2) including the level-up top-up method; wire
   `_give_wizard_starting_items()` (§4.3). Commit.
2. **Slot consumption + upcast picker**: extend `SpellEffects.cast_spell()` (already exists for
   cantrips) to consume `slot_pool` for `spell.level > 0`, add the framework doc §5.4 slot-level
   picker strip, `sphit`-family tooltip support for SAVE/AUTO_HIT resolutions (framework doc
   §5.2). Magic Missile + Shield playable via direct `add_ability()` calls (no picker UI yet —
   hardcode them prepared for testing). Commit.
3. **AoE**: `SpellShapes` (framework doc §6.2) — sphere + cone only (this doc's spells don't
   need line/cube), `show_aoe_preview()`. Fireball + Burning Hands playable. Commit.
4. **Level-up spell-choice picker**: `spell_learn_picker.gd`, `GameState.learn_spell()` +
   `spell_learn_pending` wiring in `gain_exp()` (§4.1). Commit.
5. **Spellbook overlay**: `spellbook_overlay.gd`, `GameState.set_spell_prepared()` +
   `_remove_ability_by_id()` (§5.3), `R` key wiring + input-gate additions in `player.gd`. Full
   loop now playable end-to-end: level up → learn a spell → open book → prepare it → cast it.
   Commit. Drag-and-drop placement (§5.4, `GameState.place_spell_in_slot()` + the Spellbook-row
   drag source) can land as a follow-up commit within this same step or its own — click-to-
   prepare (§5.2/§5.3) is the functional minimum, drag is the convenience layer on top.
6. **Scrolls**: `Item.taught_spell_id` field + `to_dict()`/`from_dict()`/`debug_panel.ALL_ITEMS`
   updates, `use_item()` SCROLL branch (§4.2). Commit.
7. **Persistence**: `Stats.to_dict()`/`from_dict()` `"caster"` sub-dict (§4.4), including
   `slot_pool.remaining` and the level-up top-up replay concern (verify a loaded save's slots
   match what a fresh level-up sequence would have produced — likely fine since `remaining` is
   saved directly rather than replayed, unlike talent investments). Commit.
8. **Docs**: update `scripts/items/CLAUDE.md` (Spell/SpellDb/SpellcasterState — supersede the
   "cantrip-only slice" framing), `scripts/entities/CLAUDE.md` ("Wizard spellcasting" section —
   add a "leveled spells" subsection), `scripts/ui/CLAUDE.md` (Spellbook overlay, spell-learn
   picker), `scripts/autoloads/CLAUDE.md` (new GameState fields/functions, `R` key in the
   Controls line of root `CLAUDE.md`), root `CLAUDE.md` pointer line. Commit.

## Commit convention

Same as the framework doc: `git add` / `git commit` / `git push origin HEAD:main` after each
completed step, without asking, no squashing into one giant commit.
