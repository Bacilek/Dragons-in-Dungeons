# Status/Buff/Debuff Icon Tray — Design Doc

Status: **design only, not implemented.** No code ships with this doc. It plans reworking the
HUD's ad hoc status dots into a proper, generic, clickable status/buff/debuff icon tray under
the player portrait.

All file:line references below were verified against the working tree at time of writing.
Re-verify before editing, but function/field names and structure are authoritative.

---

## 1. Goal

Any active effect on the player — passive status (poisoned, burning, slowed…), a buff (Raging,
temp HP), or a toggled ability (Reckless Attack active) — should show as a small icon in a
**horizontal row directly under the character portrait**. Clicking (or hovering — see §6) an
icon reveals a tooltip explaining exactly what the effect currently does. This must be **generic**
enough that new talents (including the ones planned in
`barbarian-tier1-rework-v2-prompt.md` — Blood-Crazed's pending-Advantage window, Scarred
Juggernaut's per-floor charge, Unstoppable Force's free-side-step window) can register a status
icon without hand-writing new HUD code per effect.

---

## 2. Current state (what this doc reworks)

A first version of this already exists, but it's narrow and mispositioned:

- `hud.gd:200-211` builds 5 small nodes, all positioned as offsets from `portrait.position`
  (`portrait` is `$StatsPanel/Portrait`, a 64×78 `TextureButton` at `(4,4)-(68,82)` inside
  `StatsPanel`, `scenes/ui/hud.tscn:17-25`): a poison/burning/bleeding/slowed dot at x=2/16/30/44,
  y=2 (`_make_status_dot()`, `hud.gd:333-339` — plain 12×12 `ColorRect`, no texture, no tooltip),
  plus a Rage icon at x=58 (`_make_status_icon_rect()`, `hud.gd:341-349` — a real `TextureRect`
  using the existing rage talent icon path, `hud.gd:328-331`).
- Because these offsets are relative to `StatsPanel` (portrait's parent) and the portrait itself
  starts at x=4, the row sits at x≈6-72, y≈6-18 — **overlapping the portrait's own left edge**,
  not below it. "Below the portrait" (y > 82) is unclaimed space today, except
  `_hit_dice_label` at roughly `(4,106)-(68,120)` (`hud.gd:253`) and the panel's own bottom edge
  at y=110-114 (`StatsPanel` is only 110px tall).
- **No tooltip exists on any of these 5 nodes today** — no `mouse_entered`/`mouse_exited`
  connected, no click handler. Only the ability bar/quickbar slots (`_item_slots[i]`) have hover
  tooltips (`_on_qbar_slot_hover`, `hud.gd:715-782`).
- Only 5 effects are represented; there is no generic "list of currently active effects" model —
  each is a hand-placed node read directly off a specific field in `_update_status_icons()`.

This doc's job: turn this into a data-driven row (any number of icons, not 5 fixed slots),
relocate it to sit cleanly under the portrait, and add the missing tooltip.

---

## 3. Data model — `StatusEffectEntry`

Rather than one hardcoded node per effect (today's pattern), introduce a small descriptor the
tray renders generically:

```gdscript
# conceptual shape, not a Resource necessarily — a plain Dictionary is fine, matching this
# project's general preference for data-driven lists over one-class-per-item
{
    "id": "poisoned",              # stable id, used for the tooltip lookup (§6) and node pooling
    "icon_path": "res://icons/status/poisoned.png",   # or "" to fall back to a colored dot
    "fallback_color": Color(0.4, 0.8, 0.2),           # used only if icon_path doesn't exist yet
    "kind": "debuff",               # "buff" | "debuff" | "neutral" — drives a colored border/tint
    "stacks_or_turns": 4,           # optional numeric badge (turns remaining, stack count, etc.)
}
```

A single function, e.g. `HUD._collect_active_status_entries() -> Array`, builds this list fresh
every refresh (§7) by checking each known source in turn — this is the one place that knows
"what counts as a currently-active effect," mirroring how `_update_status_icons()` already reads
several fields today, just generalized into data instead of five bespoke node updates.

### 3.1 Effect sources to cover at launch (inventory from current codebase)

| id | Source | Kind |
|---|---|---|
| `poisoned` | `Stats.poison_turns > 0` | debuff |
| `burning` | `Stats.burning_turns > 0` | debuff |
| `bleeding` | `Stats.bleeding_turns > 0` | debuff |
| `slowed` | `Stats.slowed_turns > 0` | debuff |
| `raging` | `GameState.is_raging` | buff |
| `temp_hp` | `Stats.temp_hp > 0` | buff (numeric badge = amount) |
| `reckless_attack` | `GameState.reckless_attack_active` | buff (high-risk, arguably neutral — see §8) |
| *(subclass-specific)* | e.g. `GameState.player_evades_opportunity_attacks` (Eagle+Natural Rager R3) | buff |

Talent-driven pending-effect windows planned in the Barbarian Tier 1 rework doc (Blood-Crazed's
pending-ADV flag, Unstoppable Force's free-side-step flag, Scarred Juggernaut's per-floor-charge
"available" state) should each register one more row here once implemented — this doc's data
model is what makes that a one-line addition instead of new bespoke HUD nodes each time.

### 3.2 What does NOT belong in the tray

- `natural_rager_form` (Bear/Eagle/Wolf) — not turn-limited, it's a standing mode selection, not
  a buff/debuff in the "temporary effect" sense. Recommend a different, permanent HUD indicator
  if the owner wants this visible at all (out of scope here).
- Rest-state flags (`short_rest_active`, `long_rest_pending`) — these already have their own
  dedicated rest-panel UI; showing them again in the tray would be redundant.

---

## 4. Layout — where exactly under the portrait

`StatsPanel` (`scenes/ui/hud.tscn:10-15`) is currently `(4,4)-(400,114)`, i.e. 110px tall.
Portrait bottom edge is at local y=82 (relative to StatsPanel, since portrait itself sits at
`(4,4)` within it — confirm exact nesting, `portrait.position` needs to be re-read as
`StatsPanel`-relative, not viewport-relative, when placing the tray). `_hit_dice_label` currently
occupies `(4,106)-(68,120)`, which **already overflows StatsPanel's own 114px height** — so the
panel's bottom edge is already tight before this feature adds anything.

Proposed layout: a new row directly below the portrait, e.g. `(4, 84)` to `(68, 100)` — a 16px
band immediately under the portrait's bottom edge (y=82), using small (14×14 or 16×16) icons
packed left-to-right with 2px gutters, wrapping to a second row if more than ~4 effects are active
simultaneously (unlikely early game, increasingly likely once several Tier 1/2 talents can be
active at once). This pushes `_hit_dice_label` down by ~16-18px, which likely requires growing
`StatsPanel`'s own height in `hud.tscn` — flagged as **open question #1**: confirm whether
`StatsPanel` should grow taller (safest, least layout risk) or whether the hit-dice label should
move elsewhere (e.g. next to the HP bar) to make room without growing the panel.

Recommend building this as its own composition child-node, following the existing
`crit_banner.gd`/`compass.gd` pattern documented in `scripts/ui/CLAUDE.md` (a small
`extends Node`/`extends Panel` class instantiated once in `hud.gd._ready()`, not more inline
code jammed directly into `hud.gd`) — e.g. `scripts/ui/status_tray.gd`, owning its own icon pool
and refresh function, exposing one method `hud.gd` calls (`status_tray.refresh(entries)`).

---

## 5. Icon assets

No dedicated status-icon folder exists yet — poison/burning/bleeding/slowed are currently plain
`ColorRect` dots with no texture at all (`_make_status_dot()`, `hud.gd:333-339`); only Rage reuses
an existing talent-icon texture. Recommend a new `res://icons/status/<id>.png` folder (e.g.
`icons/status/poisoned.png`, `icons/status/raging.png`, `icons/status/reckless_attack.png` — the
last one could instead just point at the existing ability-bar icon path already used for that
Ability, avoiding art duplication for anything that's already a real ability with its own icon).

Follow the same **placeholder-until-supplied** convention already established by the mastery
picker (`docs/architecture/weapon-mastery-selection-design.md` §4.2) and this project's general
`ResourceLoader.exists()` guard: build each tray icon as a `TextureRect` with no texture assigned
at construction time, and at refresh only assign `texture` if `ResourceLoader.exists(icon_path)`
— otherwise fall back to the existing colored-`ColorRect`-dot look (`fallback_color` in the
descriptor, §3) so the tray is fully functional (readable, if not pretty) before any new art
exists. **Mandatory**: every `TextureRect` icon must set `ignore_texture_size = true`
(`scripts/ui/CLAUDE.md`'s documented gotcha — talent icon source PNGs are 2048×2048; skipping
this makes a tiny status icon render at full native resolution, the exact "giant icon" bug this
project has hit before) and an explicit `.size = Vector2(ICON_SIZE, ICON_SIZE)` (StatsPanel is a
plain `Panel`, not a `Container` — `custom_minimum_size` alone does not set `.size` on a
non-Container parent, another documented `scripts/ui/CLAUDE.md` gotcha).

---

## 6. Tooltip — reuse the qbar-tooltip pattern, not the chat-log meta system

Root `CLAUDE.md`'s "`[url=meta]` → `hud.gd._format_tooltip(meta)`" rule is specific to the **chat
log** (`log_label.meta_hover_started`, `hud.gd:868-878`) — it is not the mechanism ability-bar/
quickbar icons use. The correct precedent to copy is the **qbar tooltip**
(`_setup_quickbar_tooltip()`, `hud.gd:659-706`; `_on_qbar_slot_hover(idx)`, `hud.gd:715-782`): a
dedicated `Panel`/`RichTextLabel` pair that follows the mouse, shown on `mouse_entered` and hidden
on `mouse_exited`, text built ad hoc per-slot rather than through `tooltip_formatters.gd`.

For the status tray:
- Each tray icon gets its own `mouse_entered`/`mouse_exited` connection (mirroring
  `_item_slots[i].mouse_entered.connect(_on_qbar_slot_hover.bind(i))`,
  `hud.gd:704-706`), reusing the **same** `_qbar_tooltip`/`_qbar_tooltip_rtl` nodes (no need for a
  third tooltip Panel — one shared floating tooltip, whichever hoverable element triggered it
  last wins) — or a new sibling tooltip pair if the tray needs to be visible/hoverable
  simultaneously with the ability bar (unlikely given they're in different screen regions, but
  flagged as **open question #2**).
- Tooltip body text: a new small dictionary of static description strings, one per `id`
  (`"poisoned" -> "Taking 1 + (turns remaining / 3) damage per turn."`, `"raging" -> "..."`, etc.)
  — recommend a new `scripts/ui/status_tooltips.gd` (mirroring `tooltip_formatters.gd`'s
  "static-func helper" composition pattern) rather than inlining strings in `status_tray.gd`,
  since this is exactly the kind of "UI copy, not game data" content `tooltip_formatters.gd`
  already models for combat-log tooltips.
- The user's request says **"clickable"**, not just hoverable — this is a deliberate deviation
  from the qbar-tooltip's hover-only convention (`scripts/ui/CLAUDE.md`'s documented pattern).
  Recommend: **click pins the tooltip open** (stays visible until the player clicks elsewhere or
  clicks the same icon again), reusing the existing `_qbar_tooltip_frozen` Ctrl-freeze mechanism's
  *shape* (`hud.gd:635-657`) but triggered by a left-click instead of the Ctrl modifier — this
  keeps hover-preview working for a quick glance while still satisfying "rozkliknutelné" for a
  player who wants to read the full explanation without holding a key down. Flagged as **open
  question #3**: confirm click-to-pin vs. plain hover-only (simpler, but doesn't literally satisfy
  "clickable") vs. click reserved for something else entirely on toggle-able entries (§8).

---

## 7. Refresh timing

No new signal infrastructure is strictly required — `_update_status_icons()` (referenced at
`hud.gd:139,295-296,313-314`) is already the de facto "recompute all status display" entry point,
wired to `TurnManager.player_turn_started`, `GameState.player_status_changed`, and
`GameState.ability_bar_changed`. Extend this same function (or have it call a new
`status_tray.refresh(_collect_active_status_entries())` at its end) rather than adding parallel
signal wiring — this matches the existing "signals only, refreshed wholesale" convention instead
of introducing per-effect push signals.

**Recommended improvement, not required**: `GameState.is_raging` currently has no dedicated
`rage_started`/`rage_ended` signal — the tray only picks up rage state because
`_update_status_icons()` happens to also run on every `player_turn_started` (i.e. up to a
half-a-turn's visible delay on rage ending, since `_end_rage()` itself doesn't directly push a
refresh). Since a buff/debuff tray is exactly the kind of feature where "icon disappears the
instant the effect ends" matters for readability, consider adding a `rage_changed` signal emitted
from both `_start_rage()` (`player.gd:1092`) and `_end_rage()` (`player.gd:1162`) and connecting
the tray refresh to it directly — flagged as **open question #4** (nice-to-have, not blocking).

---

## 8. Toggle-ability entries: does clicking the tray icon also toggle the ability?

Reckless Attack is both an ability-bar slot (toggled by clicking the ability bar icon,
`_on_slot_pressed()`, `hud.gd:418-431`) **and** would appear in the new tray while active. If tray
clicks are click-to-pin-tooltip (§6), does clicking the Reckless Attack tray icon *also* turn it
off (duplicating the ability-bar button's function), or does the tray remain strictly
read-only/informational, with toggling only ever happening via the ability bar? Recommend
**tray is read-only** — it's a status *display*, the ability bar already owns activation/
deactivation, and having two different icons both capable of turning off the same toggle
invites confusing double-duty controls. Flagged as **open question #5** for confirmation, since
"clickable" in the request could be read either way.

---

## 9. What must NOT change

- `Stats.poison_turns`/`burning_turns`/`bleeding_turns`/`slowed_turns`/`tick_status()` — this doc
  only changes how these are *displayed*, not how they're applied or ticked.
- `GameState.apply_player_status()` chokepoint — untouched; the tray reads state, it never writes
  it.
- The qbar-tooltip mechanism itself — reused, not modified (unless the shared-vs-separate-Panel
  question in §6 is answered "separate," in which case only a new sibling pair is added, the
  existing one is untouched either way).
- Ability bar activation/deactivation logic (`_on_slot_pressed()`) — untouched per §8's
  recommendation.

---

## 10. Open questions (owner sign-off needed before implementation)

1. **`StatsPanel` height**: grow the panel to make room under the portrait (recommended, least
   layout risk), or relocate `_hit_dice_label` elsewhere to free the space (§4)?
2. **Shared vs. separate tooltip Panel**: reuse `_qbar_tooltip` for tray hovers, or give the tray
   its own tooltip pair (§6)?
3. **Click behavior**: click-to-pin (recommended), hover-only despite the "clickable" wording, or
   something else entirely (§6)?
4. **`rage_changed` signal**: worth adding for instant tray refresh on rage start/end, or is the
   existing turn-start-refresh latency acceptable (§7)?
5. **Reckless Attack tray icon**: read-only display (recommended) or also clickable-to-toggle,
   duplicating the ability bar's own button (§8)?
6. **Icon art timeline**: ship with colored-dot fallbacks for everything until real `icons/status/`
   art exists (matches the mastery-picker precedent), or does the owner want to supply art before
   this ships?

---

## 11. Implementation checklist (suggested commit breakdown)

1. **Data layer**: `HUD._collect_active_status_entries() -> Array` (or wherever it ends up
   living, see §4's composition-node recommendation), covering the §3.1 inventory. Commit.
2. **`scripts/ui/status_tray.gd`**: new composition child-node (mirrors `crit_banner.gd`/
   `compass.gd`), icon pooling, layout under the portrait (§4, pending open question 1),
   placeholder-icon fallback (§5). Commit.
3. **Tooltip**: `scripts/ui/status_tooltips.gd` static description strings; hover wiring reusing
   or extending the qbar-tooltip pattern (§6, pending open questions 2-3). Commit.
4. **Refresh wiring**: hook into `_update_status_icons()`; optional `rage_changed` signal (§7,
   pending open question 4). Commit.
5. **Retire the old 5 hardcoded nodes** (`hud.gd:200-211`, `_make_status_dot()`,
   `_make_status_icon_rect()`) once the generic tray covers the same ground — don't leave both
   running in parallel. Commit.
6. **Docs**: update `scripts/ui/CLAUDE.md` (new status-tray section, tooltip pattern used,
   `StatsPanel` layout change) and root `CLAUDE.md` pointer. Commit.

## Commit convention

`git add` / `git commit` / `git push origin HEAD:main` after each completed step, without
asking. Don't squash into one giant commit.
