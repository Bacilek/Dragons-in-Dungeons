# Weapon Mastery Selection ("Mastery Picker") — Design Doc

Status: **implemented, partially** — data layer, UI, and the class-selection spawn (§5.1) are
live. The long-rest spawn (§5.2) is **deliberately not wired up yet**, per explicit instruction:
this repo's "long rest" is still just `advance_floor()`/new-floor-descent, not a distinct rest
system, and the owner does not want the picker firing on every floor change. When long rest
becomes its own real trigger, add the `hud.gd` spawn call this doc already specs — zero other
changes needed.

Scope: a full-screen picker overlay where the player chooses which weapon masteries they
currently *know* (the entries in `Stats.known_weapon_masteries`), shown once after class
selection and again at every long rest, with a per-class (and, for Barbarian, per-level)
selection cap.

All line numbers verified against the working tree at time of writing. Re-verify before
editing, but function names and structure are authoritative.

Owner decisions below are **fixed requirements** — this doc designs around them, it does not
re-litigate them.

---

## 1. Overview / goals

The mastery-effect plumbing already exists end-to-end: `Item.weapon_mastery: String`
(`scripts/items/item.gd:45`) names a weapon's mastery, and every mastery effect in combat is
gated on `Stats.knows_mastery(name)` (`scripts/entities/stats.gd:28-29`), which reads
`Stats.known_weapon_masteries: Array[String]` (`stats.gd:26`). Nothing ever populates that
array today, so all mastery effects are dormant. This feature adds the *only missing piece*:
a UI + GameState mutator that populates the array.

Fixed owner decisions:

1. All 8 masteries are always shown and selectable to every class — no per-class filtering.
   Only the **cap** differs per class.
2. Caps: Barbarian 2 (levels 1–3) / 3 (4–9) / 4 (10–20); Ranger flat 2; Wizard and Monk
   flat 0. Barbarian's cap is computed **live from current level**, never cached.
3. The picker opens exactly twice per "cycle": once right after class selection
   (`class_select.gd._on_class_selected()`, lines 267–274), and again at every long rest —
   currently `GameState.advance_floor()` (`scripts/autoloads/game_state.gd:326-357`), the
   existing long-rest stand-in.
4. Barbarian level-up cap increases do **not** open the picker at level-up. The cap silently
   grows; the player fills the new slot at the next long rest.
5. Selections persist and appear pre-toggled when the picker reopens; the player may swap
   picks but can never exceed the cap, even transiently (must deselect before selecting a
   replacement when at cap).
6. No icon assets yet — icon slots are placeholders until the owner supplies art.

Known masteries auto-apply to whatever equipped weapon carries that mastery string — there is
no per-weapon binding step. That is already exactly what `knows_mastery()` semantics give us;
no combat code changes at all.

---

## 2. The 8 masteries and their implementation status

7 of 8 already have weapon fields + effect code, all gated behind `knows_mastery()` (prior
research on this repo, verified):

| Mastery | Weapons | Effect code |
|---|---|---|
| Cleave | Greataxe | `player.gd:1402` (`_try_cleave()`) |
| Graze | Greatsword, Glaive | `player.gd:1371` (`_try_graze()`) |
| Nick | Dagger | `player.gd:1488-1489` |
| Push | Heavy Crossbow | `player_ranged.gd:178` |
| Sap | Spear (thrown) | `player_throw_tool.gd:250` |
| Slow | Longbow | `player_ranged.gd` (`ranged_attack()`, Slow `elif` branch right after Push) |
| Topple | Maul, Quarterstaff | `player.gd:1386` (`_try_topple()`) |
| Vex | Short Bow, Rapier, Handaxe | `player.gd:1284`, `:1525`, `player_ranged.gd:137` |

### 2.1 The Slow caveat (resolved)

Update: Slow now has a backing weapon and effect (Longbow, added after this doc was written —
see `scripts/items/CLAUDE.md`'s "Weapon masteries" section). On a non-lethal ranged hit it sets
`Enemy.slowed_turns = maxi(enemy.slowed_turns, 1)`, the same field Mud/Water difficult terrain
uses, making the enemy skip its entire next turn. No resist/save roll, unlike Push/Topple. All
8 masteries are therefore now data-complete; the picker still must not hardcode this
assumption anywhere (a future 9th mastery could just as easily launch mid-cycle inert).

---

## 3. Data model

### 3.1 Canonical mastery list — `Stats.ALL_WEAPON_MASTERIES`

```gdscript
# stats.gd — next to known_weapon_masteries (line 26)
const ALL_WEAPON_MASTERIES: Array[String] = [
    "Cleave", "Graze", "Nick", "Push", "Sap", "Slow", "Topple", "Vex"
]
```

- Lives on `Stats` because that's where `known_weapon_masteries` and `knows_mastery()`
  already live — one owner for the whole mastery vocabulary.
- Alphabetical order; the picker renders in this order (stable, no per-class reordering).
- Strings must match `Item.weapon_mastery` values exactly (they are the existing free-form
  strings — `"Cleave"`, `"Vex"`, etc.).

### 3.2 Cap — `Stats.mastery_cap() -> int` (computed, never cached)

```gdscript
# stats.gd — next to knows_mastery()
func mastery_cap() -> int:
    match character_class:
        CharacterClass.BARBARIAN:
            if character_level >= 10: return 4
            if character_level >= 4:  return 3
            return 2
        CharacterClass.RANGER:
            return 2
        _:
            return 0   # WIZARD, MONK
```

- A **function, not a field**, deliberately: owner decision #4 says level-up must silently
  raise the cap with no picker interrupt and no stale value. Computing from
  `character_class` + `character_level` at call time makes staleness impossible — mirrors
  how `proficiency_bonus` / `rage_uses_max` are already computed properties (`stats.gd:46`,
  `:59`).
- Do **not** add a cap field to `apply_class_defaults()` — there is nothing to set. (It was
  considered as the natural place per the class-defaults pattern, but a stored field is
  exactly the stale-cache trap decision #4 forbids.)

### 3.3 GameState mutators + flag + signal

Mirroring the talent system's `can_invest_talent()` / `invest_talent()` /
`talent_picker_open` / `talent_invested` quartet:

```gdscript
# game_state.gd
signal known_masteries_changed
var mastery_picker_open: bool = false   # blocks ALL player input while picker visible

func can_select_mastery(mastery_name: String) -> bool:
    if player_stats.knows_mastery(mastery_name):
        return true   # deselection is always allowed
    return player_stats.known_weapon_masteries.size() < player_stats.mastery_cap()

func toggle_mastery(mastery_name: String) -> bool:
    if player_stats.knows_mastery(mastery_name):
        player_stats.known_weapon_masteries.erase(mastery_name)
        known_masteries_changed.emit()
        return true
    if not can_select_mastery(mastery_name):
        return false   # hard-block at cap — caller may flash the counter, no log spam
    player_stats.known_weapon_masteries.append(mastery_name)
    known_masteries_changed.emit()
    return true
```

- `can_select_mastery()` is the single gate, checked by the mutator itself (defense in
  depth) **and** by the UI to disable/dim icons — same pattern as `can_invest_talent()`
  gating both `invest_talent()` and the Upgrade button (`talent_picker.gd:240`, `:291`).
- Every click commits immediately via the mutator — no modal confirm step, exactly like
  `invest_talent()`. Closing the picker with fewer than cap selected is allowed (the player
  simply knows fewer masteries; nothing forces a full loadout).
- The state itself stays on `Stats.known_weapon_masteries` — **no parallel copy on
  GameState**. The array is already the single source of truth every combat gate reads.
- Reset: `GameState`'s run-reset block (`game_state.gd:181-185`, where `class_selected` and
  `talent_picker_open` reset) must also do `mastery_picker_open = false` and
  `player_stats.known_weapon_masteries.clear()` (a fresh `Stats` may make the clear
  redundant — verify, but the flag reset is mandatory).
- `known_masteries_changed` has no required consumer today (the picker refreshes itself
  synchronously after each toggle); it exists for future HUD/tooltip surfaces, matching the
  "UI connects to GameState signals only" convention.
- Nothing here consumes a resource, so **no `GameState.invincible` guard is needed**.

---

## 4. UI — `scripts/ui/mastery_picker.gd`

New script, no `.tscn` (all overlay UIs here are code-built). Modeled directly on
`talent_picker.gd` — reuse its patterns verbatim rather than inventing new ones:

- `extends CanvasLayer`, `layer = 25`.
- `_ready()`: set `GameState.mastery_picker_open = true`, build UI (mirrors
  `talent_picker.gd:15-20`).
- Full-screen dim `ColorRect` (`Color(0,0,0,0.55)`, `MOUSE_FILTER_STOP`) + centered `Panel`
  with the standard `StyleBoxFlat` (bg `Color(0.07,0.08,0.13,0.97)`, 3px gold border
  `Color(0.78,0.55,0.22)`, corner radius 8) — copy `talent_picker.gd:25-40`.
- All buttons `focus_mode = FOCUS_NONE` (repo-wide overlay rule, `scripts/ui/CLAUDE.md`).

### 4.1 Node tree / layout

```
MasteryPicker (CanvasLayer, layer 25)
├── Dim (ColorRect, full-screen, MOUSE_FILTER_STOP)
└── Panel (StyleBoxFlat, centered; PANEL_W = 720.0)
    ├── Title Label        "Weapon Masteries"           (top-left, 26pt gold)
    ├── Counter RichTextLabel  e.g. "2 / 3"             (top-right — the star-bar position,
    │                                                     talent_picker.gd:135-142)
    ├── Done Button         "✓  Done  [Esc]"            (below counter or bottom-right)
    ├── HSeparator
    ├── 8 × mastery slot (positions computed, 4 columns × 2 rows):
    │   ├── SlotFrame (Panel, thin StyleBoxFlat border — visible even with no icon art)
    │   ├── Icon (TextureButton, ICON_SIZE = 64, ignore_texture_size = true,
    │   │         STRETCH_KEEP_ASPECT_CENTERED, TEXTURE_FILTER_NEAREST, FOCUS_NONE)
    │   └── Name Label (17pt, centered, under the icon — same geometry as the talent
    │                   picker's dot labels, talent_picker.gd:186-193)
    ├── HSeparator
    └── Detail RichTextLabel (optional but recommended — see §4.4)
```

- Grid math mirrors `_build_tier_section()`'s slot-pitch formula (`talent_picker.gd:163-170`)
  with `n = 4` per row and two rows. Panel height auto-computed from content and re-centered
  on the viewport, exactly like `_build_ui()`'s tail (`talent_picker.gd:83-86`).
- Keep a `Dictionary` of `mastery_name -> TextureButton` (and one for the slot frames /
  labels) for refresh-time tinting — same as `_talent_btns` (`talent_picker.gd:7`).

### 4.2 Placeholder icons (owner decision #6)

Codebase convention for a missing icon (from `talent_picker.gd._refresh()`, lines 279-285):
build the `TextureButton` with **no texture at creation time**, and at refresh only assign
`texture_normal` if `ResourceLoader.exists(icon_path)` — otherwise leave it null, which
renders as an empty (but still clickable, correctly-sized) button. Adopt exactly that:

- Define `const MASTERY_ICON_FOLDER := "res://icons/masteries/"` and derive
  `MASTERY_ICON_FOLDER + mastery_name.to_lower() + ".png"` per slot (parallel to
  `GameState.TALENT_ICON_FOLDER` naming). None of these files exist yet — the
  `ResourceLoader.exists()` guard means the picker works today and lights up automatically
  when the owner drops the PNGs in.
- The `SlotFrame` bordered Panel behind each button is what makes an icon-less slot visible
  and obviously clickable in the meantime. The name label carries the identification load.

### 4.3 Selection states and the cap hard-block

Refresh-driven, recomputed after every click (one `_refresh()` walking all 8 slots — the
talent picker's model):

| State | Visual | Click behavior |
|---|---|---|
| Selected (known) | Gold tint `modulate = Color(1.4, 1.1, 0.4)` on the button + gold frame border (the talent picker's selected tint, `talent_picker.gd:238`) | Click → deselect (always allowed) |
| Unselected, under cap | Normal white modulate, gray frame | Click → select |
| Unselected, **at cap** | Dimmed `modulate.a = 0.5` (the picker's "unranked" dim, `talent_picker.gd:285`), gray frame | Click → **ignored** (`toggle_mastery()` returns false; optionally flash the counter red for feedback) |

- The hard-block lives in `GameState.toggle_mastery()` (§3.3), not only in the UI —
  identical defense-in-depth to `can_invest_talent()` being checked in both
  `talent_picker.gd:291` and inside `invest_talent()` itself.
- The counter RTL shows `"%d / %d" % [known.size(), player_stats.mastery_cap()]`, calling
  `mastery_cap()` **live at every refresh** (decision #4 — the cap may have grown since the
  picker last opened, e.g. Barbarian hit level 4 mid-floor; the long-rest reopen must show
  "2 / 3", not "2 / 2"). Tint it gold while slots remain, gray at cap, red if over cap
  (§7.3).
- Swapping at cap: at cap all unselected icons are dead until the player deselects one —
  which is precisely owner decision #5's "must deselect before selecting a replacement".
  No extra code needed; it falls out of the gate.

### 4.4 Detail panel (recommended, small)

A bottom `RichTextLabel` showing the hovered/last-clicked mastery's name + one-line rules
text (e.g. Cleave: "On a melee hit, make a free attack against a second enemy within reach"),
mirroring the talent picker's detail section (`talent_picker.gd:195-227`, minus the Upgrade
button). Descriptions are a `const Dictionary` in the picker script — they are UI copy, not
game data. Slow's entry reads its intended 5.5e text ("…reduce the target's speed") even
though no effect exists yet; this is acceptable placeholder copy per §2.1. If the
implementer wants to cut scope, the detail panel is the one omittable piece.

### 4.5 Input / closing

- Esc (and the Done button) → `_close()`: `GameState.mastery_picker_open = false`,
  `queue_free()` — verbatim `talent_picker.gd:303-305` + the `_unhandled_input` Esc handler
  (`talent_picker.gd:346-354`). No dedicated reopen hotkey (unlike T for talents): the picker
  is event-driven only (class select + long rest), per owner decision #3. If the player
  closes early with unfilled slots, the slots simply wait for the next long rest.
- No selection state to roll back on close — every toggle already committed via the mutator.

---

## 5. Integration points

### 5.1 After class selection

`class_select.gd._on_class_selected()` (lines 267–274) currently: set class → apply defaults
→ give starting items → `class_selected = true` → emit signals → `queue_free()`. Insert the
picker at the end, gated on cap:

```gdscript
# class_select.gd, _on_class_selected(), just before queue_free()
if GameState.player_stats.mastery_cap() > 0:
    var picker = load("res://scripts/ui/mastery_picker.gd").new()
    get_tree().root.call_deferred("add_child", picker)
queue_free()
```

- `class_select` spawns it directly (it is the onboarding sequence owner); `call_deferred`
  avoids adding a node during the button-press callback while this node is freeing.
- The cap gate means Wizard/Monk never see it (§7.1).
- Ordering: after `give_class_starting_items()` and `class_selected = true`, so the picker
  opens over the already-live dungeon exactly like the talent picker does. Because
  `mastery_picker_open` blocks all input (§5.3), the player can't act until they close it —
  no TurnManager interaction needed (the picker is turn-free UI, same as the talent picker).

### 5.2 At long rest (`advance_floor()`) — NOT YET WIRED UP

Deferred on purpose (see Status header above) — this section is kept as the spec for when it
happens, not a description of current behavior.

`GameState.advance_floor()` (`game_state.gd:326-357`) is the current long-rest stand-in — it
already refills the long-rest resource pools (`rage_uses_remaining`, `hit_dice`,
`zealot_blessed_charges`, `zealot_zp_charges`). GameState is an autoload and should not spawn
UI; follow the existing "hud spawns overlays off GameState signals" pattern (hud.gd spawns
`talent_picker` from `player_leveled_up`, `hud.gd:119`):

- `hud.gd._on_floor_changed()` (already connected to `GameState.floor_changed`, which
  `advance_floor()` emits at line 355): append

  ```gdscript
  if GameState.class_selected and GameState.player_stats.mastery_cap() > 0 \
          and not GameState.mastery_picker_open:
      var picker = load("res://scripts/ui/mastery_picker.gd").new()
      get_tree().root.call_deferred("add_child", picker)
  ```

- No change inside `advance_floor()` itself — the signal it already emits is the hook. This
  is deliberately the loosest possible coupling: when long rest becomes its own explicit
  system (see `docs/architecture/REST_SYSTEM_IMPLEMENTATION.md` and §9), the spawn call
  moves to whatever signal that system emits, with zero changes to the picker.
- The `class_selected` guard keeps it from firing on any pre-class floor setup;
  `floor_changed` is not emitted during initial game load today (only `advance_floor()` and
  debug jump emit it), but the guard is cheap insurance. Decide during implementation whether
  the **debug Jump-to-Floor** path (which also runs `advance_floor()` semantics) should open
  it — recommendation: yes, it's a long rest in every mechanical sense and debug users can
  Esc instantly.
- Note the reopen shows current picks pre-toggled for free: the picker renders straight from
  `Stats.known_weapon_masteries`, which persists across floors (owner decision #5 — no code
  needed).

### 5.3 The `mastery_picker_open` input-blocking flag

New flag needs the **identical treatment** as `talent_picker_open`. Complete list of current
`talent_picker_open` sites (grep-verified) — each needs a `mastery_picker_open` twin:

| Site | Current check | Change |
|---|---|---|
| `player.gd:464-465` (T-key open-talent gate) | `... and not GameState.talent_picker_open` | add `and not GameState.mastery_picker_open` (can't open talents over the mastery picker) |
| `player.gd:469` (master keyboard gate) | `if GameState.inventory_open or GameState.short_rest_open or GameState.short_rest_active or GameState.talent_picker_open: return` | add `or GameState.mastery_picker_open` |
| `game_state.gd:185` (run reset) | `talent_picker_open = false` | add `mastery_picker_open = false` beside it |
| `talent_picker.gd:17` / `:304` (set/clear) | — | the equivalent set/clear lives in `mastery_picker.gd` `_ready()`/`_close()` |

One **deliberate deviation** from talent-picker parity: also gate the I-key inventory toggle
(`player.gd:458-459`, currently only checks `short_rest_open`) on
`not GameState.mastery_picker_open`. The talent picker tolerates inventory opening over it;
the mastery picker is a mandatory onboarding step at game start and stacking the inventory
overlay over it would be confusing. Same for the Tab bar-mode toggle in
`hud.gd:90-96` — add `and not GameState.mastery_picker_open` (harmless at game start, tidy).
Mouse input needs nothing extra: the full-screen dim `ColorRect` with `MOUSE_FILTER_STOP`
already swallows world clicks (talent-picker precedent).

Also update the docs that enumerate input gates when implementing:
`scripts/entities/CLAUDE.md:169` ("All input gated on …") and `scripts/autoloads/CLAUDE.md`'s
key-state-fields block.

---

## 6. What must NOT change

- `Stats.knows_mastery()` and every combat-side gate call (§2 table) — zero edits. The whole
  point of this design is that populating the array is sufficient.
- `Item.weapon_mastery` and all weapon definitions — untouched.
- `TurnManager` — zero edits. The picker is turn-free modal UI.
- `advance_floor()`'s body — the hook is the `floor_changed` signal it already emits (§5.2).
- The talent picker — nothing is shared by inheritance; patterns are copied, not extracted
  into a base class (two files is below the extraction threshold; revisit if a third
  full-screen picker appears).

---

## 7. Edge cases

### 7.1 Wizard / Monk (cap 0): skip the picker entirely

**Decision: 0-cap classes never see the picker** — both spawn sites gate on
`mastery_cap() > 0` (§5.1, §5.2). Rationale over the "show it locked at 0/0" alternative: a
modal that can only be dismissed teaches nothing and would fire at *every floor descent* for
the whole run — pure friction. When Wizard/Monk eventually get masteries (or a Tier-N talent
grants cap), the gate opens by itself because the cap function is the single source of truth.

### 7.2 Closing with unfilled slots

Allowed (Esc or Done at any count ≤ cap). Unspent slots are not banked or lost — the cap is
re-derived every open, so the player can fill them at the next long rest. No nag prompt.

### 7.3 `known_weapon_masteries` over cap on open (future respec / multiclass / debug)

**Decision: persist, never silently trim.** If the picker opens and
`known.size() > mastery_cap()` (can't happen today — the cap only ever grows within a class —
but a future respec, multiclass, or debug class-switch could produce it):

- Nothing is auto-removed. Silently deleting player choices (which one? alphabetical-last?)
  is worse than any visual oddity, and combat working with a briefly-over-cap array is
  harmless — `knows_mastery()` doesn't care about the cap.
- The counter renders red (e.g. "3 / 2"), all unselected icons are dead (the existing at-cap
  gate already does this — `size() < cap` is false), and only deselection is possible until
  the count is ≤ cap. Self-healing, zero extra code beyond the counter color.

### 7.4 Barbarian levels 4/10 mid-floor (cap grows between rests)

Nothing happens at level-up (owner decision #4 — no popup, no auto-open). The next picker
open computes `mastery_cap()` live and simply shows more headroom. Implementation guard:
never store the cap on the picker instance across refreshes — call the function each
`_refresh()` (§4.3).

### 7.5 Selecting Slow

Update: Slow is now backed by the Longbow (§2.1) — selecting it behaves exactly like any
other mastery, no special-casing needed. (Originally written when Slow was inert; kept as a
worked example of "a mastery can launch mid-cycle with no backing weapon" for future entries.)

### 7.6 Invincible / god mode

No interaction — nothing is consumed by selection, so no `GameState.invincible` guard
(root-CLAUDE.md consumption rule does not apply).

---

## 8. Open questions (small — owner decisions covered almost everything)

1. **Debug Jump-to-Floor** also routes through floor advancement — should it open the picker
   like a real descent? Recommended yes (§5.2); confirm if it feels spammy during debugging.
2. **Detail-panel rules text** (§4.4): fine to ship with paraphrased 5.5e one-liners, or
   should the copy come from the owner? (Cut the panel entirely if unwanted.)
3. **Icon file naming**: `res://icons/masteries/<name_lowercase>.png` proposed (§4.2) —
   confirm before the owner produces art, so the `ResourceLoader.exists()` auto-light-up
   works without a code change.

Judgment calls already made in this doc (flagging per instructions, no sign-off strictly
needed): skip-picker-entirely for 0-cap classes (§7.1), persist-don't-trim when over cap
(§7.3), hud-spawns-on-`floor_changed` rather than GameState spawning UI (§5.2), the I-key/Tab
gating deviation from talent-picker parity (§5.3), alphabetical mastery order (§3.1).

---

## 9. Out of scope (explicitly)

- **Real icon assets** — owner supplies later; placeholder frames until then (§4.2).
- **Long rest as a standalone system** — this design hooks the current stand-in
  (`advance_floor()` via `floor_changed`); when an explicit long-rest trigger lands, only
  the one spawn call in `hud.gd` moves (§5.2).
- **Per-class mastery filtering, per-weapon mastery binding, mastery-granting talents** —
  none requested; the flat known-list + live cap function accommodates all of them later
  without schema changes.

---

## 10. Implementation checklist (suggested commit breakdown)

1. **Data layer**: `Stats.ALL_WEAPON_MASTERIES`, `Stats.mastery_cap()`;
   `GameState.mastery_picker_open`, `can_select_mastery()`, `toggle_mastery()`,
   `known_masteries_changed`, run-reset additions. Commit.
2. **Picker UI**: `scripts/ui/mastery_picker.gd` (layer 25, dim + panel, 4×2 slot grid with
   frames/labels/counter/Done, `_refresh()` tint/dim logic, Esc close). Commit.
3. **Integration**: spawn call in `class_select.gd._on_class_selected()`; spawn call in
   `hud.gd._on_floor_changed()`; input-gate additions in `player.gd` (:458, :465, :469) and
   `hud.gd` Tab handler. Commit.
4. **Docs**: new "Mastery picker" section in `scripts/ui/CLAUDE.md`; update
   `scripts/entities/CLAUDE.md` (the now-stale "nothing grants masteries yet" text at its
   Stats section and `:169`'s input-gate list) and `scripts/autoloads/CLAUDE.md` (new flag,
   signal, mutators); pointer line in root `CLAUDE.md`. Commit.

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without
asking. Don't squash into one giant commit.
