# scripts/ui

All HUD and overlay UI scripts. Several non-obvious conventions here — read before touching UI.

## Maintenance rule
When adding a new panel, overlay, or HUD element, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Critical conventions

### Mouse filters (DO NOT change)
`LogPanel` and `StatsPanel` in `scenes/ui/hud.tscn` use `MOUSE_FILTER_IGNORE`.
**Do not set these back to STOP** — it blocks click-to-move in the lower half of the screen.
Interactive children (buttons, slots) still receive events normally via event propagation.

### Focus mode on all overlay buttons
All buttons in overlays (short rest panel, debug panel, inventory) use `focus_mode = FOCUS_NONE`.
Keyboard input routes through `_unhandled_input`, not button focus — this is intentional.

### Slot sizing in non-Container parents
`custom_minimum_size` does NOT set `size` on non-Container nodes. Always set explicitly:
```gdscript
slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
```

### Drag hit detection
Use `Rect2(slot.position, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(local_mouse)` — not `slot.get_rect()` (unreliable in non-Container parents).

### TextureRect icons — always set `ignore_texture_size = true`
Any `TextureRect` that shows an icon at a small fixed size (status icons, small HUD indicators) MUST set `ignore_texture_size = true`. Without it, assigning `.texture` makes `get_minimum_size()` return the texture's native pixel size, and `Control.size` gets clamped up to that minimum — so a `TextureRect` explicitly sized e.g. 12×12 renders at the source PNG's full resolution instead (talent icons are 2048×2048, so this bug looked like a giant icon covering most of the screen). `_make_status_icon_rect()` in `hud.gd` sets this; `talent_picker.gd`'s `_add_talent_icon()` already did. `TextureButton`'s `icon`/`texture_normal` don't have this footgun the same way, but double-check any new `TextureRect` usage against this rule.

---

## HUD (`hud.gd`)
Connects to `GameState` signals only — never poll `GameState` in `_process()`.

**Short rest pip row**: BG3-style filled/empty circle row (`_short_rest_label`, a `RichTextLabel`
with bbcode `[color=]●/○[/color]` glyphs, no new art asset) directly below the hit-dice label in
the portrait column (`$StatsPanel` local position `(4, 120)`), showing `GameState.
short_rests_remaining` vs `max_short_rests` for the current long-rest cycle at a glance, without
opening the Alt rest menu. Wired to `GameState.short_rest_changed` (fires on both spending a short
rest and `long_rest()`'s refill) plus resynced in `_on_class_chosen()` alongside the hit-dice
label. Hover shows a native `tooltip_text` ("Short Rests remaining..."), so this one `RichTextLabel`
deliberately keeps `mouse_filter = STOP` unlike most decorative StatsPanel children. `StatsPanel`'s
`offset_bottom` grew 200→216 in `scenes/ui/hud.tscn` to make room; the status tray moved
122→138 and the spell-slots row 158→174 to stay below it.

**Gold counter**: a small coin icon (`TextureRect`, `misc/coin_gold.png`, `ignore_texture_size = true` per the rule above) + gold-tinted amount Label (`_gold_label`) in `$StatsPanel` next to the hit-dice label, wired to `GameState.gold_changed` (`_on_gold_changed(new_amount)`). Session-7a minimal UI — visual polish deferred.

**ActionBar (bottom quickbar/ability bar) scale**: `scenes/ui/hud.tscn`'s `ActionBar` panel and its 9 `ItemSlotN` buttons + Wait/Search/Interact buttons are sized 1.5× the original layout (`ActionBar` height 90→135, slot size 76→114px, pitch 80→120px). Item/ability icons use `Button.icon` + `expand_icon = true` so they auto-scale with the button — no separate icon-size code to touch. The per-slot quantity badge (`_slot_qty_labels`) and ability use-count badge (`_slot_use_labels`) offsets/font sizes in `hud.gd` scale alongside (`-32/-18/11pt` → `-48/-27/16pt`). `_bar_mode_label` offsets are pinned to `ActionBar`'s new top (`-135`), not the old `-90`. Each slot also carries a static top-left `_slot_num_labels` badge showing its 1-9 hotkey (slot index `i` → `KEY_(i+1)`, matches `player.gd`'s `_use_quickbar_slot`/`_use_ability_slot` dispatch) — created once in `_ready()`, never toggled, visible in both item and ability bar mode.

**Ability bar greying**: `_refresh_ability_bar()`'s slot `modulate` is gray whenever `not GameState.is_ability_usable(ab)` (see `scripts/autoloads/CLAUDE.md`) — covers plain exhausted charges (Rage) AND infinite-use abilities that are situationally blocked (Frenzy without Rage active, Limit Break already used this long rest, Zealot Strike with 0 Hit Dice, Grip of the Forest without Rage, Hellish Rebuke with no free cast or 1st-level slot left to arm it, Hunter's Mark already cast this round). Orange still means "active toggle" (`ab.is_active`), takes priority over the usability check. **Frenzy cooldown countdown** (Frenzied Killer R3): while `GameState.berserker_frenzy_used` and `get_talent_rank("frenzied_killer") >= 3`, the use-count badge shows `"%dt"` counting down from `3 - GameState.berserker_turns_since_frenzy` (same red tint/format as Rage's own "%dt" remaining-duration display) instead of the normal `uses/max` text — makes the automatic refresh timing visible instead of just guessing. **Any new same-round cooldown should follow this exact pattern** (direct owner convention): grey the slot via a new `is_ability_usable()` case AND show a big red `"%dt"` countdown overlay in place of the normal use-count badge — never just grey it with no explanation, or leave the normal badge showing while the ability is actually blocked. Hunter's Mark's own one-cast-per-round cooldown (`Stats.hunters_mark_cast_this_round`, `scripts/entities/CLAUDE.md`'s "Ranger class") reuses the exact same `frenzy_cooldown_turns` local (set to a flat `1` while on cooldown) rather than inventing a parallel countdown variable, since the display logic is identical either way.

**Racial free-cast counter badges**: Hunter's Mark and Hellish Rebuke (`Stats.hunters_mark_uses_remaining`/`Stats.tiefling_legacy_free_casts_remaining["hellish_rebuke"]`) plus every Elven Lineage/Fiendish Legacy/Gnomish Lineage spell ability (`ability_id` starting `"spell:"`, resolved via `hud.gd._racial_lineage_spell_counter(spell_id)` against `Stats.elf_lineage_free_casts_remaining`/`tiefling_legacy_free_casts_remaining`/`gnome_lineage_free_casts_remaining`) show an `"X/Y"` use-count badge on their ability-bar slot, gold while `X > 0`, gray at `0`. `Y` is `1` for Hellish Rebuke and every Elven Lineage/Fiendish Legacy spell (a leveled spell that falls back to a real spell slot once its one free use is spent), but stays the character's live `proficiency_bonus` for Gnomish Lineage's own 3 cantrip grants, which have no spell-slot fallback at all. These abilities themselves keep `Ability.uses_max == 0` (the free-base-ability convention, same as Rage) — the real counter lives on `Stats`, read directly in `_refresh_ability_bar()` before the generic `ab.uses_max == 0` blank-badge branch, same precedent as Hunter's Mark's own special case. Once the counter hits 0 the spell is still castable (Elf/Tiefling only), it just falls back to a real spell slot of its own level (Wizard/Ranger only) — see `scripts/entities/CLAUDE.md`'s "Elf"/"Tiefling"/"Gnome" sections.

**In-bar reorder drag** (no overlay needed — leveled-spells-and-slots-plan.md follow-up):
press-and-drag any `ItemSlotN` button past `HUD.BAR_DRAG_THRESHOLD` (8px) and drop it on another
slot of the **same** bar (item quickbar or ability bar, whichever is currently showing) to move it
there — e.g. drag slot 1 onto slot 5. `_on_slot_gui_input()` only *records* the LMB press
(`_bar_drag_from`); it does NOT consume the event, so `Button.pressed` (→ `_on_slot_pressed()`,
normal use/cast) still fires unchanged for a plain click. Motion/release are polled every frame in
`_process_bar_drag()` (`Input.is_mouse_button_pressed()`, same reasoning as
`spellbook_overlay.gd`'s drag — a release outside the pressed Button's own bounds never reaches
its `gui_input`). Ability bar: `GameState.swap_ability_slots(a, b)` (plain swap, works for any
ability including spells — doesn't touch known/prepared state). Item quickbar:
`GameState.move_item("quickbar", a, "", "quickbar", b, "")`, the same function
`inventory_overlay.gd` uses for its own quickbar↔quickbar drags. **Works even while the Spellbook
is open** — `spellbook_overlay.gd`'s own drag always starts from a Spellbook row, never from an
ActionBar slot, so the two never actually contend for the same press despite both being able to
drop onto the ability bar. Camera-pan suppression (see `scripts/entities/CLAUDE.md`'s
"Player-specific" section, `_lmb_press_over_ui`) is what stops this drag from also panning the
game world underneath — a real bug during initial playtesting, not a hypothetical.
While the Spellbook is open, `_process_bar_drag()` also treats the Spellbook's Special quick-cast
slot box as a valid drop target (checked before the same-bar slot loop) — see the Spellbook
overlay's "Reverse direction — ActionBar slot → Special slot" note below.

**Split-out modules** (pure refactor, same behavior — GDScript has no partial classes, so these use composition/static-helper patterns instead):
- `tooltip_formatters.gd` (`TooltipFormatters`, static-func-only helper) — the combat tooltip formatters (`fmt_hit_tooltip`, `fmt_dmg_tooltip`, `fmt_heal_tooltip`, `fmt_save_tooltip`, `fmt_stealth_tooltip`, `fmt_ehit_tooltip`, `fmt_edmg_tooltip`, `fmt_catk_tooltip`, `fmt_ret_tooltip`). Each takes only a `Dictionary` and returns a `String`. `hud.gd._format_tooltip()` still owns the `kind` dispatch match and calls into these. **Generic bonus-source lines use `%+d`, never a literal `"+"` + `%d`** — `fmt_dmg_tooltip()`/`fmt_heal_tooltip()`'s `CombatMath.decode_bonus_sources()` loop renders each source's `amount` with `%+d` so a negative source (e.g. a negative STR-mod line on a low-STR melee attacker) renders `-1`, not `+-1`.
- `crit_banner.gd` (`CritBanner`, composition child-node, `extends Node`) — `show_banner(text, color)` (was `hud.gd._show_crit_banner`). Instantiated once in `hud.gd._ready()` (`_crit_banner`), added as a child, and `GameState.crit_banner` connects directly to `_crit_banner.show_banner`.
- `compass.gd` (`Compass`, composition child-node, `extends Panel`) — owns the top-center stairs compass UI and its `_stairs_found_this_floor` state internally. Public methods: `on_stairs_discovered()`, `update_display()`, `reset_for_new_floor()`. Instantiated once in `hud.gd._ready()` (`_compass`); `GameState.stairs_discovered` connects to `on_stairs_discovered`, `TurnManager.player_turn_started` connects to `update_display`, and `hud.gd._on_floor_changed()` calls `reset_for_new_floor()`.
- `hunters_mark_indicator.gd` (`HuntersMarkIndicator`, composition child-node, `extends Panel`) — Ranger's Hunter's Mark direction widget, positioned left of the stairs Compass, same arrow-glyph rendering copied verbatim but driven by `GameState.player_stats.hunters_mark_target` (visible whenever a target is marked, even outside FOV/LOS) instead of a one-shot discovery flag. Instantiated once in `hud.gd._ready()` (`_hunters_mark_indicator`); `TurnManager.player_turn_started` connects to `update_display`, `hud.gd._on_floor_changed()` calls `reset_for_new_floor()` and clears `hunters_mark_target` (a live `Enemy` ref from the previous floor). See `scripts/entities/CLAUDE.md`'s "Ranger class" section.
- `status_tray.gd` (`StatusTray`, composition child-node, `extends Control`) + `status_tooltips.gd` (`StatusTooltips`, static-func-only helper) — the status/buff/debuff/passive icon tray under the portrait. See "Status/buff/debuff/passive icon tray" below.

**Status/buff/debuff/passive icon tray** (`status_tray.gd`, `StatusTray extends Control`,
composition child-node instantiated once in `hud.gd._ready()` as `_status_tray`, added under
`$StatsPanel` at local position `(4, 122)` size `(388, 32)` — `StatsPanel`'s `offset_bottom` was
grown from 114 → 144 → 158 in `scenes/ui/hud.tscn` to make room below the portrait/level/hit-dice
column as the tray's own icon size grew). `StatusTray.ICON_SIZE` is `28.0` (bumped up from the
original `16.0` — the icons were reported hard to see at that size), `GUTTER = 3.0`. Replaces the
old 5 hardcoded dot nodes (formerly `hud.gd:200-211`, `_make_status_dot()`/`_make_status_icon_rect()`).
Fully data-driven: `hud.gd._update_status_icons()` builds a fresh `Array[Dictionary]` of
`{id, icon_path, fallback_color}` every refresh (wired to the same chokepoint as before —
`TurnManager.player_turn_started`, `GameState.player_status_changed`, `GameState.ability_bar_changed`)
and calls `_status_tray.refresh(entries)`. **`race_bonus` is always the FIRST entry appended**,
unconditionally (every other entry is gated on a live game-state flag; this one never is) — a
permanent, always-visible reference icon for the player's chosen race's full trait kit. Its icon
is the same portrait `race_select.gd`'s tile grid shows — `StatusTooltips.
race_portrait_icon_path(stats)` resolves `res://icons/races/<id>/portrait.png` (`id` = the
lowercase `RACE_NAMES` display name), so the HUD buff icon and the onboarding tile are the
identical asset, not two separate files to keep in sync. Hover text is built by
`StatusTooltips.race_bonus_text(stats)`/`race_display_name(stats)` (`status_tooltips.gd`) — a
`match stats.character_race` returning every trait that race grants in plain English (Elf/
Dragonborn branch further on `race_variant` for their sub-race/ancestry-specific lines), title
reads `"Race Bonus: <display name>"` (e.g. `"Race Bonus: High Elf"`, `"Race Bonus: Red
Dragonborn"`) via `build_bbcode()`'s own `id == "race_bonus"` special case (same pattern as
`concentration`'s dynamic spell-name title). See `scripts/entities/CLAUDE.md`'s per-race sections
for the mechanical detail this tooltip text summarizes. `StatusTray` pools `TextureRect` icon nodes
(`ignore_texture_size = true` per the rule above), tints them with `fallback_color` when
`icon_path` doesn't resolve via `ResourceLoader.exists()` (no separate `ColorRect` fallback type —
**bugfix**: the fallback used to set `tr.texture = null`, which draws nothing at all regardless of
`modulate` — a `TextureRect` with no texture has nothing to tint. `StatusTray._get_fallback_tex()`
is a shared 1×1-white `ImageTexture`, built once and reused, so an icon-less entry now actually
renders as a solid tinted square instead of silently nothing; this was invisible for every
still-art-less entry, including every enemy-condition entry the Inspect Panel shows via
`EnemyInspect.status_entries()` — see `scripts/entities/CLAUDE.md`'s "Conditions" section),
and emits `icon_hovered(id, rect)`/`icon_unhovered()` on mouse enter/exit (`rect` is the hovered
icon's own global rect — `hud.gd` anchors the tooltip to it, see "Tooltip hover chain" below).
`hud.gd` connects these to
reuse the existing qbar-tooltip pair (`_qbar_tooltip`/`_qbar_tooltip_rtl`) via
`_on_status_tray_icon_hovered(id, rect)`, which pulls description text from `status_tooltips.gd`
(`StatusTooltips`, static-func-only helper mirroring `tooltip_formatters.gd`'s pattern — one
`get_text(id)` case per effect id). Sources at launch: `poisoned`/`burning`/`bleeding`/`slowed`
(`Stats.*_turns`), `difficult_terrain` (`GameState.player_on_difficult_terrain` — live "standing
on Mud/Water right now" flag, recomputed every turn-start in `player.gd._on_turn_started()`
instead of riding `slowed_turns`' decaying counter, which used to make the icon flicker for about
a frame on every terrain step instead of staying lit the whole time the player stood on the tile —
`_update_status_icons()` also skips the separate `"slowed"` entry entirely whenever
`difficult_terrain` is already showing, since the two render with the identical icon/color and
re-stepping into Mud/Water while already standing in it would otherwise flash both at once for a
frame; see `scripts/entities/CLAUDE.md`'s "Status effects" section), `raging` (`GameState.is_raging`), `temp_hp` (`Stats.temp_hp`),
`unarmored_defense` (Barbarian/Monk with no armor equipped — reads the live AC formula),
`tactician` (`GameState.battlefield_adv_pending`, Battlefield Expert R1's pending-Advantage
window — see `scripts/entities/CLAUDE.md`'s Barbarian Tier 1 talents), `psycho_adv`
(`GameState.psycho_adv_pending`, Psycho's identical pending-Advantage window), `hunters_mark_free_recast` (`Stats.hunters_mark_free_recast_available` — Ranger's Hunter's Mark
death-triggered free-recast window, see `scripts/entities/CLAUDE.md`'s "Ranger class" section;
icon reuses the ability's own `GameState.talent_icon_path("hunters_mark", 1)`), `concentration`
(`Stats.concentration_spell_id != ""` — icon is that spell's OWN `SpellDb.get_spell(id).icon_path`,
not a fixed art asset, since it must reflect whichever of Blade Ward/Witch Bolt/Expeditious
Retreat/Fog Cloud is actually active; `StatusTooltips.build_bbcode("concentration")`
special-cases the title to "Concentrating: &lt;Spell Name&gt;" by reading the id live instead of a
static `TITLES` entry — see `scripts/entities/CLAUDE.md`'s "Concentration (generic mechanism)").
Both pending-ADV flags live on `GameState` (not on `PlayerBaseTalents`, where they used to live)
specifically so this tray can read them without a live `Player` node reference — matches "HUD only
reads GameState" above. `torch` (`GameState.lit_torch_item() != null` — icon is that Torch's own `icon_path`, orange
fallback tint; tooltip text (`status_tooltips.gd`'s `"torch"` case) is dynamic, showing
`torch_turns_remaining` and whether the Fire-damage bonus applies (Main Hand only) — see
`scripts/items/CLAUDE.md`'s "Torch"), `aid` (`Stats.aid_bonus_hp > 0` — Ranger's Aid spell, icon is
that spell's own `icon_path`, light-green fallback tint; tooltip shows the exact flat HP bonus
currently applied and that it lasts until the next long rest — see `scripts/entities/CLAUDE.md`'s
"Ranger class" section), `barkskin` (`Stats.barkskin_turns > 0 and not Stats.barkskin_on_companion`
— Ranger's Barkskin spell, icon is that spell's own `icon_path`, brown/bark fallback tint;
deliberately its own entry rather than riding the generic `concentration` one, since this spell is
NOT Concentration — see `scripts/entities/CLAUDE.md`'s "Ranger class" section), `weapon_mastery` (always-on passive, shown whenever
`Stats.mastery_cap() > 0` — i.e. a martial class, currently Barbarian/Ranger — AND
`Stats.known_weapon_masteries.size() > 0`; no dedicated art yet, `res://icons/status/
weapon_mastery.png` placeholder + bronze fallback tint, real icon still TBD). Hover tooltip
(`status_tooltips.gd`'s `"weapon_mastery"` case) is dynamic, listing the currently known masteries
by name — live off `Stats.known_weapon_masteries`, so it always matches whatever the Mastery
Picker last set. Refreshed via `GameState.known_masteries_changed` (fired by `toggle_mastery()`
and the premade-hero setup path) in addition to the tray's usual chokepoints, so it updates
immediately on a new game, a fresh mastery pick, a level-up cap increase, and a long-rest
reselect — no separate wiring needed since all of those already end in a `toggle_mastery()` call
or that same signal. `exhaustion` (`Stats.exhaustion_level > 0` — see `scripts/entities/CLAUDE.md`'s
"Exhaustion" section for its one real source, death-save revival) shows the current level, flat
d20 penalty, movement fraction, and the level-6-is-fatal rule on hover. No `icons/status/` art
exists yet — every entry currently renders as a tinted placeholder square until real icons are
supplied (`unarmored_defense`/`tactician`/`psycho_adv`/`concentration` already reuse existing
talent/spell icons, so those render properly today). Open questions resolved: hover-only tooltip,
shared tooltip panel, grow-panel layout.

### Z-index reference
| Element | Z |
|---|---|
| Blood decals | 0 |
| Floor items | 1 |
| Enemies | 1 |
| Fog overlay | 2 |
| Player | 3 |
| Damage labels | 10 |
| Short rest panel / Debug panel | 25 |

### Compass
Implemented in `compass.gd` (`Compass` component, see above). Hidden at floor start. Appears at **top-center** of screen only when stairs tile enters FOV (`on_stairs_discovered()` sets its internal `_stairs_found_this_floor = true` and shows itself). Resets (hides) on every floor change via `reset_for_new_floor()`.
`update_display()` early-returns until the flag is true. Arrow character picked from 8 Unicode directions; shows Chebyshev distance.
Triggered by `GameState.stairs_discovered` signal (emitted by `DungeonFloor.update_fog()` or See All debug).

---

## Inspect Panel (`inspect_panel.gd`)
CanvasLayer, layer = 25. `InspectPanel` (`class_name`), spawned by `PlayerActions.
do_inspect()`/`_open_inspect_panel()` (`scripts/entities/player_actions.gd`) on every RMB/Ctrl+LMB
Inspect — replaced the old plain chat-log line for every inspect target (enemy, revealed trap,
floor item, tile). SPD-style full-value summary card, deliberately **non-blocking**: no
`GameState.*_open` input-gate flag, no full-screen dim — it's a read-only glance, not a decision,
so gameplay keeps running underneath. Closes on Esc, its own Close button, or automatically the
next time the player takes any real or free action (`TurnManager.player_turn_started`, which fires
on both — see `scripts/autoloads/CLAUDE.md`). Re-inspecting replaces the currently-open panel
(`PlayerActions._inspect_panel` tracks the live instance, `queue_free()`s the old one first).

**Enemy view** (`open_enemy(enemy)`): name (+ `[BOSS]` tag) header, AC subtitle, a portrait
(the enemy's own `AnimatedSprite2D`'s first `"idle"` frame, blank if none), an HP bar
(green/yellow/red by ratio), an auto-generated one-line description ("Medium Undead, CR 1/4" —
`EnemyInspect.description_line()`, `scripts/entities/enemy_inspect.gd`), and a live status-icon
row that **reuses `status_tray.gd` (`StatusTray`) verbatim** — same pooled-`TextureRect`/
hover-emits-id contract as the HUD's own buff tray, just fed a per-enemy entry list instead of
`GameState.player_stats`. `EnemyInspect.status_entries(enemy)` aggregates every currently-active
enemy-side condition into that entry shape: Shocked (Shocking Grasp), Jolted (Witch Bolt target),
Poisoned (the `poisoned_condition` condition), Outlined (Faerie Fire), Prone, Incapacitated,
Frightened, Paralyzed, and Blinded (`GameState.is_blinded(enemy.grid_pos)`, positional) — see
`scripts/entities/CLAUDE.md`'s "Conditions" section for what each one mechanically does. Hover
text comes from `EnemyInspect.build_bbcode(id)` — a `TITLES`/`get_text()`/`build_bbcode()` static
helper mirroring `status_tooltips.gd`'s own "UI copy, not game data" pattern, generalized to not
require a live `GameState.player_stats` reference (an `Enemy`'s own fields are read directly by
`status_entries()` instead). God Mode appends the old Dmg/EXP numbers as a plain gray chat-log
line alongside opening the panel (kept as text, not worth its own panel field).

**Simple view** (`open_simple(title, subtitle, desc)`): a revealed trap, a floor item stack (name
+ "on the floor (+N more)" + the `Item.description` field), or a tile (name + a short flavor
line) — no portrait/HP bar/status row, just title + subtitle + description text sized to an
estimated line count (character-length heuristic, not `RichTextLabel.get_content_height()`, since
that needs a layout pass to settle and would read stale immediately after setting `.text`).

## Talent picker (`talent_picker.gd`)
CanvasLayer, layer = 25. Opened by `PlayerActions.open_talent_picker()` (`scripts/entities/player_actions.gd`) via **T key** (bypasses phase gate). Does NOT auto-open on level-up.
Sets `GameState.talent_picker_open = true` → blocks all player keyboard input. Esc or T closes.
Pixel Dungeon style: tier header with star bar (gray=spent / yellow=available / dark=locked) + icon row with dot rank indicators + bottom detail panel showing all rank descriptions + "Upgrade Talent ▲" button. **Tier 2 locked state**: while `not GameState.tier2_unlocked`, the Tier 2 section renders a gray "defeat the floor-5 boss to unlock" row, and if `GameState.talent_points[2] > 0` a right-aligned gold badge "N points pending — defeat the floor-5 boss" (points earned at levels 7-12 pend until the boss-kill gate opens).
**Sizing**: `PANEL_W = 720.0`, `ICON_SIZE = 64.0` (bumped up from the original 500/48 for legibility — panel height auto-computed from content and re-centered on the 1920×1080 viewport in `_build_ui()`). All other offsets/paddings/font sizes in the file scale off these two constants or are hand-tuned alongside them; if you change either constant, re-check the hardcoded subclass-arrow positions in `_build_tier_section()` (only rendered in God Mode) since those aren't formula-driven.
**Subclass arrows** (Tier 2 header only, visible in God Mode — a debug-only override, NOT the player path): ◀ `active_tier2_subclass` ▶ arrows call `GameState.debug_switch_subclass(±1)` then close+reopen the picker. Berserker, Scarred Warrior, Wild Heart, Zealot, and World Tree are all implemented. Real players choose their subclass once via `subclass_select.gd` (below).

## Subclass select (`subclass_select.gd`)
CanvasLayer, layer = 25. The player-facing, one-time Tier 2 subclass choice. Spawned by `hud.gd._on_subclass_choice_required()` on the `GameState.subclass_choice_required` signal (emitted from `GameState._on_boss_defeated()` when the Tier 2 gating boss — the floor-5 boss — dies, for classes with subclasses — currently Barbarian only). Modeled on talent_picker/mastery_picker styling (dim overlay + centered gold-bordered `Panel`, `focus_mode = FOCUS_NONE` everywhere). Sets `GameState.subclass_picker_open = true` → blocks all player input (including WASD polling, I/T/Tab keys). **Non-dismissable**: no close button, `_unhandled_input` swallows all key events — the choice is mandatory and permanent. `GRID_COLS`-wide grid of clickable cards (one per `TIER2_SUBCLASSES` entry, currently 5 → 3 columns × 2 rows, computed generically from `SUBCLASSES.size()` — not hardcoded to any specific count), each showing the subclass name plus its 3 talents (rank-1 icon via `GameState.talent_icon_path()`, name, one-line blurb — text reused verbatim from the `_setup_X_tier2_talents()` Talent definitions; keep the `SUBCLASSES` const in sync when talent flavor changes). Selecting a card highlights it and enables the confirm button ("Become a X"), which calls `GameState.choose_subclass(name)` → `unlock_tier2()` and frees the overlay. Card icons are `TextureRect`s — `ignore_texture_size = true` is set per the rule above.

**Rank-gradient talent icons**: `_add_talent_icon()` no longer sets a texture at creation time — `_refresh()` (called on build and after every upgrade) loads `GameState.talent_icon_path(t.talent_id, max(rank,1))` into `btn.texture_normal` each time, so the icon art changes as the player invests ranks (falls back to `t.icon_path` if unmapped). Icons dim to alpha 0.5 while unranked.

## Rest panel (`short_rest_panel.gd`)
CanvasLayer, layer = 25. Spawned by `PlayerActions.open_short_rest()` (`scripts/entities/player_actions.gd`) — no longer gates on `short_rests_remaining` (a long rest may still be available at 0 short rests). Tabbed, browser-style: **Short Rest** (default) and **Long Rest** — `Tab` key or clicking a tab header switches; each tab has its own container (`_short_container`/`_long_container`) toggled `.visible`, sharing one Cancel button and swapping which of `_rest_btn`/`_long_rest_btn` is shown.

**Short Rest tab** (unchanged mechanics): ←/A/KP4 = minus dice, →/D/KP6 = plus dice, **Space = rest**. Rolls `_dice_to_spend × hit_die_sides() + CON mod` (min 1 per die), heals player, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`, runs for `GameState.SHORT_REST_TURNS` (5) turns. Each individual die's raw roll is captured into `GameState.short_rest_pending_heal_rolls` (alongside the existing summed `short_rest_pending_heal`) so the completion log line's `heal:` tooltip can show a per-die breakdown (`"d10: 7 +2 = 9"` per die) instead of just the final total — `TooltipFormatters.fmt_heal_tooltip()` renders this whenever a `rolls=` field is present in the meta, falling back to the old single-line total for every other heal source (potions, Zealot Strike) that doesn't set it.

**Long Rest tab**: shows `GameState.total_food_value() / GameState.LONG_REST_FOOD_COST` and a disabled-reason label when `not GameState.can_long_rest()`. On confirm, sets `GameState.long_rest_pending = true` (instead of computing a pending heal) and runs the same `short_rest_active` countdown for `GameState.LONG_REST_TURNS` (20) turns — reuses the exact short-rest turn-countdown/interrupt machinery in `player.gd._on_turn_started()`, which branches on `long_rest_pending` at completion to call `GameState.long_rest()` instead of applying a short-rest heal, then spawns `mastery_reselect_prompt.gd`. Food is only consumed on successful completion, not on start — an interrupted/aborted long rest costs nothing (`rest_interrupt_panel.gd`'s abort path clears `long_rest_pending`).

Esc always closes/cancels regardless of tab. Sets `GameState.short_rest_open = true` on open → blocks all player input until closed.
**Important ordering in `_on_rest()`/`_on_long_rest()`**: `GameState.short_rest_open = false` and `queue_free()` must be called **before** emitting `player_action_requested("short_rest_begin")` because the signal is synchronous — `_on_turn_started` fires inside the chain and checks `short_rest_open`.

## Long-rest hub (`mastery_reselect_prompt.gd`)
CanvasLayer, layer = 26. Spawned by `player.gd` right after `GameState.long_rest()` completes — was
originally a plain Yes/No "reselect masteries?" confirm, now a small hub offering every
long-rest-gated adjustment in one place: **Weapon Masteries** (only shown when
`player_stats.mastery_cap() > 0`), **Attunement** (always shown), **Spellbook** (only shown when
`player_stats.caster != null`), **High Elf Cantrip Swap** (only shown when `GameState.
is_high_elf_caster()` — see `scripts/entities/CLAUDE.md`'s "Elf" section), and **Done**. Sets `GameState.mastery_picker_open = true` for its
own duration (blocking input like every other long-rest picker — reused deliberately rather than
adding a parallel flag, since every input gate check in `player.gd`/`scripts/entities/CLAUDE.md`
already keys off this one name). Clicking an option hides the hub's own panel (`_panel.visible =
false`, node stays alive) and spawns that sub-picker fresh (`mastery_picker.gd` /
`attunement_picker.gd` / `spellbook_overlay.gd`) — each sub-picker owns its own
`GameState.*_open` flag independently (Spellbook's `spellbook_open`, the other two also set
`mastery_picker_open` themselves, redundant but harmless). `_on_subpicker_closed()` (connected to
the sub-picker's `tree_exited`) re-shows the hub panel and restores `mastery_picker_open = true`
(the sub-picker's own `_close()` just cleared it on its way out) — so the player can visit any
number of the three options before finally pressing Done/Esc, which is what actually frees the hub
and clears the flag for good. Never shown after a short rest, only a completed long rest.

## Attunement picker (`attunement_picker.gd`)
CanvasLayer, layer = 25. Magic item attunement — see `scripts/items/CLAUDE.md`'s "Attunement"
section for the underlying mechanism. Only ever reachable from the long-rest hub above (never
opened directly by a hotkey). Modeled on `mastery_picker.gd`'s conventions (dim overlay + centered
bordered `Panel`, hard-blocked at a cap, `focus_mode = FOCUS_NONE` everywhere) but lists items
instead of a fixed mastery set: one row per `GameState.attunable_items()` entry (every
`Item.requires_attunement` item currently in the quickbar/bag/equipment, attuned or not), each with
an icon, name, "Attuned"/"Not attuned" sublabel, and a toggle button ("Attune"/"Unattune") that
calls `GameState.attune_item()`/`unattune_item()` — the Attune button disables itself (silent
no-op feel, same as the Mastery Picker's cap block) once `attuned_count() >= MAX_ATTUNED_ITEMS`.
Top-right counter shows `"X / 3"`, red if somehow over cap. Shows a plain "No magic items requiring
attunement in your inventory." label instead of an empty list when `attunable_items()` is empty —
expected today, since no `ITEM_POOL` entry sets `requires_attunement` yet (infrastructure-only
pass). Sets `GameState.mastery_picker_open = true`/`false` on open/close like every other picker in
this family. Esc or the Done button closes it, which the parent hub's `tree_exited` hook detects to
re-show itself.

## High Elf Cantrip Swap (`high_elf_cantrip_swap.gd`)
CanvasLayer, layer = 25. High Elf lineage's level-1 benefit (`scripts/entities/CLAUDE.md`'s "Elf"
section) — only ever reachable from the long-rest hub, only shown to a Wizard/caster High Elf.
Two-round card picker modeled on `cantrip_select.gd`: round 1 lists `GameState.
high_elf_known_cantrips()` (pick one to replace), round 2 lists `high_elf_learnable_cantrips()`
(pick the Wizard cantrip you don't know yet to learn instead) — each card commits immediately on
click, "Skip / Done" (or Esc) at either round bails with nothing changed. Confirm calls
`GameState.swap_high_elf_cantrip(old_id, new_id)`.

---

## Celestial Revelation picker (`celestial_revelation_picker.gd`)
CanvasLayer, layer = 25. Aasimar's Celestial Revelation (`scripts/entities/CLAUDE.md`'s "Aasimar"
section) — reachable only from `PlayerAasimar.activate_celestial_revelation()` (the ability-bar
press), never a hotkey. Reuses `GameState.mastery_picker_open` as its input-blocking flag (same
"no dedicated flag" precedent as `high_elf_cantrip_swap.gd`/`attunement_picker.gd`). Shows all 3
transformation choices (Heavenly Wings/Inner Radiance/Necrotic Shroud) as plain text cards side by
side — no icon art yet, each card's full mechanical description is a native `Control.tooltip_text`
(hover to read). Clicking a card calls `PlayerAasimar.resolve_celestial_revelation_choice(idx)`
directly and frees the overlay; Esc cancels for free since nothing is spent until a card is
actually clicked. Replaced an earlier arm-cycle-cancel-then-click-anywhere flow that had no visible
list of the 3 choices on screen at all.

## Blacksmith panel (`blacksmith_panel.gd`)
CanvasLayer, layer = 25. Modeled on `attunement_picker.gd`'s conventions (dim overlay + centered
bordered `Panel`, `focus_mode = FOCUS_NONE` everywhere). Only ever reachable by bumping/RMB-
interacting the Blacksmith prop tile (`scripts/world/CLAUDE.md`'s "Blacksmith prop" —
`PlayerActions.open_blacksmith_panel()`), never a hotkey. Sets `GameState.blacksmith_panel_open =
true` on open (blocks all player input, threaded through the same OR-chains every other overlay
flag lives in) → `false` on close.

Shows: owned Mold count (scans quickbar+bag for an item named "Mold"), `GameState.gold` vs the
flat `BLACKSMITH_GOLD_COST` (50) craft cost, and a "Forge Weapon" button disabled unless the
player has ≥1 Mold **and** enough gold (mirrors `short_rest_panel.gd`'s affordability-disable
pattern). On confirm: `GameState.spend_gold()` + `GameState.consume_one()` on the Mold, then
`WeaponForge.generate_random_weapon()` (`scripts/items/CLAUDE.md`'s "WeaponForge" section) →
`GameState.add_item()` (goes to the first empty quickbar/bag slot, **not** auto-equipped) — the
result is immediately shown via a reveal `RichTextLabel` built from the existing
`WeaponTooltip.build(item)`, no new tooltip-formatting code needed. Esc or the Close button
dismisses without side effects.

## Shop panel (`shop_panel.gd`)
CanvasLayer, layer = 25. ShopRoom's Buy/Sell overlay (special-rooms-economy-design.md §4.1,
session 7e) — modeled on `attunement_picker.gd`'s conventions (dim overlay + centered bordered
`Panel`, `focus_mode = FOCUS_NONE` everywhere, one row per item). Only ever reachable by bumping/
RMB-interacting the shopkeeper prop tile (`scripts/world/CLAUDE.md`'s "Shopkeeper prop" —
`PlayerActions.open_shop_panel(pos)`), never a hotkey. Sets `GameState.shop_open = true` on open
(blocks all player input, threaded through the same OR-chains every other overlay flag lives in)
→ `false` on close.

Two simple mode-toggle buttons (Buy/Sell — plain bool `_mode`, not a real `TabContainer`) switch
which list `_refresh()` builds. **Buy**: lists `DungeonFloor.get_shopkeeper_stock(shop_pos)` (the
shopkeeper's own generated stock — live array, not a copy), price = `item.gold_value` flat, Buy
button disabled when `GameState.gold < item.gold_value`; confirming calls `GameState.add_item()`
first (refuses + logs "inventory full" if it fails, without spending gold), then
`GameState.spend_gold()` (rolling the item back out on the rare race where gold changed between
the button-disable check and the click), then removes the item from the live stock array. **Sell**:
lists every `player_quickbar`/`player_inventory` item with `gold_value > 0`, price =
`maxi(1, gold_value / 2)`; confirming calls `GameState.remove_item()` + `GameState.add_gold()`.
Gold readout top-right, refreshed on `GameState.gold_changed`. Esc or the Close button dismisses.

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: **God Mode** (checkbox — activates invincible + noclip + see_all + exposes enemy rolls/HP in chat log), **All Checks** (checkbox — `GameState.debug_show_all_checks`, logs every per-turn Stealth-vs-Passive-Perception roll AND every Undead Fortitude save, pass or fail, instead of only real events (detections / trait triggers); visibility only, never changes the roll — see `scripts/entities/CLAUDE.md`'s "Stealth & Surprise Attacks" and its "Undead Fortitude's own check-visibility" note), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel listing all `DungeonFloorData.ENEMY_POOL` + `BOSS_POOL`, spawns adjacent to player via `dungeon_floor.debug_spawn_enemy()`), **Level Up** (`GameState.debug_level_up()`), **Give 100 Gold** (`GameState.add_gold(100)`), **Give Spell...** (sub-panel listing every `SpellDb.CANTRIP_IDS + LEVELED_SPELL_IDS` entry — icon, name, `SpellDb.ordinal(level)` badge, description, "Give" button; `_on_give_spell()` calls `GameState.choose_cantrip()` for a level-0 spell or `learn_spell()` + `set_spell_prepared(id, true)` for a leveled one, both idempotent/cap-safe — for testing any spell without playing through level-ups, no quantity control since spells are boolean known/prepared, not stackable), See All, **Enhance Item (Slot 1)** (`GameState.enhance_quickbar_slot1_item()` — +1 per press to whatever sits in item-quickbar slot 1: weapon → `bonus_damage`, Armor/Shield → `bonus_ac`, everything else a no-op; not added to the Give Item pool on purpose — see `scripts/items/CLAUDE.md`'s "Enhance debug tool"), **Mute** (bottom of the main panel, below Give Spell — calls `AudioManager.toggle_mute()`, label swaps 🔊/🔇 in sync with `AudioManager.mute_changed`, same signal the HUD's own top-right `MuteButton` listens to; added as a more-discoverable second entry point since that corner button is easy to miss).

DungeonFloor registers itself in group `"dungeon_floor"` in `_ready()` so the debug panel can locate it via `get_tree().get_first_node_in_group("dungeon_floor")`. Pool data (`ENEMY_POOL`/`BOSS_POOL`/`ITEM_POOL`) is read directly off `DungeonFloorData` (`scripts/world/dungeon_floor_data.gd`, global via `class_name`) — no `load()` of `dungeon_floor.gd` needed.

**Item sync rule**: any new entry in `DungeonFloorData.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
**Scale**: `SLOT_SIZE = 90`, `SLOT_GAP = 6` (`STEP = 96`), `PANEL_W = 1020`, `PANEL_H = 690` — 1.5× the original 60/4/820/460 values (bumped for legibility; keep the whole overlay's fonts/paddings/offsets scaling off these two constants if you touch them again).
Equipment slot labels: **Main Hand** (key `"melee"`) / **Off-hand** (key `"hand2"`) / **Ranged** (key `"ranged"`) in `GameState.equipment`.
**Equipment grid layout** (`_build_equipment_section()`, positions relative to `EQUIPMENT_ORIGIN`): top row is Trinket / Headgear (above Armor) / Ranged (centered above the gap between Main Hand and Off-hand) / **Special** immediately right of Ranged, middle row is Gloves / Armor / Main Hand / Off-hand left→right, Boots bottom-center (below Armor). **Trinket, Headgear, Gloves, and Boots are all display-only today** — `_fits_slot()` has no case for any of them (falls through to its `_` default, `return false`), so nothing can be dragged into any of the four; `equip()`'s auto-routing never targets them either (only `WEAPON`→`melee`/`ranged` and `ARMOR`→`armor`/`hand2`). No item in `ITEM_POOL` targets any of these four slots yet — they're rendered purely so the equipment grid reads as complete, same reasoning as leaving Headgear/Gloves/Boots visible with nothing to put in them.

**Special quick-cast slot** (display-only here — see "Spellbook overlay" below for where it's actually assigned): shows the spell icon for `GameState.special_slot_spell_id` (empty = blank), falling back to the spell name's first 4 letters as text if its `icon_path` doesn't resolve (`_update_special_slot()`'s `has_icon` check). Built with `slot.set_meta("source", "special_display")` instead of `"equipment"` — deliberately NOT part of the Item-shaped equipment drag system (`_do_move()` rejects it outright, `_start_drag()` already no-ops since `_slot_item()` returns null for this source) since it holds a `Spell` reference, not an `Item`. `_update_special_slot()`/`_show_special_slot_tooltip()` are its dedicated render/hover paths (parallel to `_update_slot()`/the generic item tooltip). Right-click calls `GameState.clear_special_slot()`. Cast with **Alt+click** in `player.gd` (mirrors Shift+Ranged's one-motion resolve) — see `scripts/entities/CLAUDE.md`'s spellcasting section for `PlayerSpellcasting.cast_direct()`. **Every slot's `Icon` `TextureRect` sets `ignore_texture_size = true`** (`_make_slot()`) — this file was missing it until spell art landed under `res://icons/spells/`; those source PNGs are huge, so without the flag the icon rendered at full native resolution instead of the slot's fixed size, the exact "giant icon" footgun documented in the rule above.
Slot type enforced via `_fits_slot()`: Main Hand (`"melee"`) rejects ranged items and vice versa; `"hand2"` (Off-hand) accepts any non-weapon item, or a Light melee weapon (e.g. the Handaxe) — but only when Main Hand is *also* currently Light — rejecting non-Light weapons, ranged weapons, and a Light weapon whenever Main Hand isn't Light. `equip()` always routes non-ranged weapons to `"melee"` regardless of how they're equipped (pickup, starting gear, debug give-item, or explicit equip) — Off-hand is never auto-populated, only reachable via explicit drag. Dual-wielding two Light weapons now fires a real bonus Off-hand attack — see `scripts/items/CLAUDE.md`'s "Dual-wielding".
**Two-handed cross indicator**: each `"hand2"` slot gets a hidden `BlockedMark` Label (red "✕", built in `_make_slot()`) toggled in `_refresh()` — visible whenever `GameState.equipment.get("melee")` is non-null and `Item.is_two_handed`, signalling the off-hand is unusable while a two-handed weapon is equipped. Purely visual; `is_two_handed` still doesn't block anything else (e.g. the ranged slot) — see root `CLAUDE.md`.

**Versatile grip toggle**: clicking the Main Hand slot without dragging (press+release inside the same slot, detected in `_finish_drag()` when `dest == null` but the release point is still inside `_drag_src_ctrl`) calls `GameState.toggle_versatile_grip()` if the equipped item's `is_versatile == true` (currently Quarterstaff and Spear — see `scripts/items/CLAUDE.md`'s "Versatile weapons"). `_refresh()` gives the Main Hand slot's `StyleBoxFlat` a gold border + thicker width while gripped two-handed (`main_hand.is_versatile and main_hand.is_two_handed`), gray/thin otherwise.

**Thrown weapon durability**: item tooltips (both here and `hud.gd`'s quickbar tooltip) show a left-aligned `Uses: X/Y` line for any `Item.Type.WEAPON` with `is_thrown == true` (Spear/Handaxe/Dagger/Torch — see `scripts/items/CLAUDE.md`'s "Thrown weapons"), placed just above the "Ctrl: inspect" hint (which is always the last line, bottom-left).

**Weapon tooltip body**: both this overlay's `_on_slot_hover()` and `hud.gd`'s `_on_qbar_slot_hover()` build a `Item.Type.WEAPON` tooltip's whole header-through-Properties block via the single shared `WeaponTooltip.build(item)` (`scripts/items/CLAUDE.md`'s "Unified weapon tooltip format") — never duplicate that logic locally again; only description/Uses/Attunement/price/Ctrl-hint are still appended per-caller since those apply to every item type, not just weapons.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

**RMB item-interaction menu / LMB-equip**: see `scripts/items/CLAUDE.md`'s "Item interaction menu
(RMB) / LMB-equip" section — `_right_click()`, `_dispatch_item_interaction()`, and the new
click-no-drag-equip branch in `_finish_drag()` all live in this file; the shared `ItemInteractions`
helper (`scripts/items/item_interactions.gd`) and the transient popup Control
(`scripts/ui/item_interaction_menu.gd`, `ItemInteractionMenu`) are both new files this feature
introduced, reused identically by `hud.gd`'s quickbar RMB handler.

**Tooltip hover chain (no Ctrl-freeze)** — direct owner request, 2026-08-01, replacing the earlier
Ctrl-to-freeze mechanism: every item/ability/spell/status/race-trait tooltip is **always**
interactive (`STOP`/`PASS`+`bbcode`+`meta_hover` from the moment it's built, never toggled) and
**anchored to whatever slot/icon triggered it** (`_inv_hover_source_rect` in
`inventory_overlay.gd`, `_qbar_hover_source_rect` in `hud.gd` — captured once at hover-start via
`Rect2(slot.global_position, slot.size)`), never following the mouse pixel-by-pixel. This means the
mouse can always travel from the trigger onto the tooltip box, and from there onto a keyword's own
glossary popup, without the box drifting out from under the cursor or the chain closing —
no key press needed anywhere. Each popup level stays open while the mouse is over itself or
anything nested deeper than it; the outermost tooltip additionally stays open while the mouse is
back on the original trigger. Backing out one level (mouse moves from a nested popup back onto its
parent) closes only that nested level; leaving the entire chain (mouse in neither the trigger, the
tooltip, nor any popup) closes everything. Driven by a per-frame rect-containment check in
`_process()` — **not** `meta_hover_ended`/`mouse_exited`, since either fires the instant the cursor
leaves the trigger, even when heading straight into the popup/level it just opened.
`inventory_overlay.gd`'s own chain is one level deep (`_inv_tooltip` → `_inv_glossary_popup`);
`hud.gd`'s is up to three (`_qbar_tooltip` → `_glossary_popup` → `_glossary_popup2`, the last only
ever populated by a race trait with real sub-options — see `scripts/entities/CLAUDE.md`'s "Race
tooltip format"). All item tooltips still show a small gray "Ctrl: inspect" hint in the bottom-left
corner (always the LAST line appended, after Uses/price) — that's the unrelated Ctrl+click
world-Inspect feature (`PlayerActions.do_inspect()`), not this tooltip-freeze mechanism, which no
longer exists.

---

## Death save overlay (`death_save_overlay.gd`)
CanvasLayer, layer = 30 — the highest layer in the game, above Debug Panel/every blocking picker
(25) and Game Over (10), so it genuinely reads as "everything else stopped." No `.tscn` — built
entirely in code (`subclass_select.gd`'s convention), spawned by `hud.gd._on_death_save_started()`
on `GameState.death_save_started` (never a hotkey). Full mechanism, signal contract, and the
`GameState.is_dying` input/turn-freeze it rides on: `scripts/autoloads/CLAUDE.md`'s "Death save
sequence" section. Purely reactive to `GameState.death_save_rolled`/`death_save_finished` — full
dim + a big color-coded rolling d20 number (a pulsing "?" placeholder between rolls) + two 3-pip
success/failure rows (green/red filled circles, 5e character-sheet style). Frees itself on
`death_save_finished` regardless of outcome — `GameState._end_death_save_sequence()` already fires
`player_died` (spawning `game_over.tscn` underneath) BEFORE that signal when the sequence fails.

## Game over (`game_over.gd`)
CanvasLayer, layer = 10. Spawned by `hud.gd._on_player_died()`. Two buttons: **"Try Again"**
(only visible when `GameState.character_creation_snapshot` isn't empty — see
`scripts/autoloads/CLAUDE.md`'s `snapshot_character_creation()`/`retry_same_character()`) calls
`GameState.retry_same_character()` then reloads the scene — rebuilds the exact same
class/race/ability-scores/masteries/known-Wizard-spells at level 1 with starting gear on a fresh
seed/floor 1, skipping the whole character-creation UI chain entirely (`character_select.gd`'s own
`_ready()` self-frees immediately once it sees `class_selected` already true, same short-circuit
the Continue-Saved-Run flow already relies on). **"New Game"** is unchanged — `GameState.
start_new_run()` + reload, which re-shows the full character-creation flow. Both funnel through
the shared `_reload()` (was the old `_on_new_game()` body).

## Character select (`character_select.gd`)
CanvasLayer, layer = 20. **The actual first screen of a new run** — `hud.gd._ready()` now spawns
this instead of `class_select.gd` directly. Shows 6 cards side by side: 5 premade characters
(`PREMADE` const — Garrem Ogar/Orc Barbarian/Cleave+Graze, Tish/Wood Elf Ranger/Slow+Nick, Grok
the White/White Dragonborn Monk, Jace/Halfling Wizard/Fire Bolt, Lil Dorruk/Fire Goliath Warlock/
Eldritch Blast) plus a 6th "Custom" card. Clicking a
premade card (`_on_premade_selected()`) applies class + `GameState.give_class_starting_items()` +
`GameState.choose_race(race, variant, prof_ability)` + (for Barbarian/Ranger) directly populates
`Stats.known_weapon_masteries` and emits `known_masteries_changed` + (for Wizard/Warlock) a
`"cantrip"` key
in the `PREMADE` entry calls `GameState.choose_cantrip(id)` directly — bypassing class_select/
point_buy_select/background_select/race_select/mastery_picker/cantrip_select entirely and dropping
straight into the already-loaded floor 1. Each `PREMADE` entry also carries a fixed `"scores"`
dict (`{"str","dex","con","int","wis","cha"}`, applied via `Stats.apply_point_buy_scores()` right
after `apply_class_defaults()` — reusing the same point-buy setter rather than a separate
mechanism) instead of `apply_class_defaults()`'s own generic per-class defaults: Garrem
16/14/16/8/10/10, Tish 8/16/14/10/16/10, Grok 10/16/16/8/14/10, Jace 8/14/16/16/10/10, Lil Dorruk
10/14/16/8/10/16 — no
point buy or background ASI screen either way, just a different fixed stat block per hero. Each
card's own ability-score display (`_make_stats()`) actually applies this `"scores"` dict on top of
`apply_class_defaults()` via `apply_point_buy_scores()` — it used to silently render the generic
class-default block instead (the `"scores"` dict was only ever applied for real at
`_on_premade_selected()` time, never fed into the preview), so any hand-edit to a premade's
`"scores"` looked like it had no effect until this was fixed. Stats render as a 2-column×3-row grid
of bordered "chip" boxes (`_add_stat_chip()`, STR/DEX/CON left column, INT/WIS/CHA right column;
abbreviation left-aligned, `score (+mod)` right-aligned, vertically centered) instead of the
original unevenly-spaced single-column rows.
Clicking
"Custom" (`_on_custom_selected()`) spawns `class_select.gd` unchanged, preserving the full
**class select → point buy → background ASI → race select → mastery picker** chain for a
from-scratch build. Also
owns the "Continue Saved Run" button (moved here from `class_select.gd` since this is now the true
entry point) — same behavior as before, see `scripts/autoloads/CLAUDE.md`'s SaveManager
"Continue flow" section. Jace's/Lil Dorruk's cards also carry a `"spell1"` key (`"magic_missile"`/
`"hideous_laughter"` respectively — Lil Dorruk's own was originally `"mage_armor"`, corrected once
it was noticed Mage Armor isn't on the real Warlock spell list), applied via
`GameState.choose_starting_spell()` right after the `"cantrip"` key's `choose_cantrip()` call —
premade casters get their fixed cantrip + level-1 spell without ever seeing `cantrip_select.gd`.
**Lil Dorruk** (`Stats.CharacterClass.WARLOCK`, `Stats.CharacterRace.GOLIATH`,
`variant: Stats.GiantAncestry.FIRE`, `prof: -1` — Goliath has no ability-proficiency sub-choice,
same as every non-Human/Gnome race) is the first premade to use a race with a `sub_kind`
(`"giant_ancestry"`) entirely through the fixed `PREMADE` dict — `GameState.choose_race()` takes
the ancestry directly as `variant`, no `race_select.gd` UI involved.

## Class select (`class_select.gd`)
The **Custom** path only now (see `character_select.gd` above) — no longer spawned directly by
`hud.gd`. Emits `GameState.class_chosen` when player selects a class, then spawns
`point_buy_select.gd` (below) and `queue_free()`s itself — point buy owns spawning race select,
which in turn owns spawning the Mastery Picker, not this script. No longer has its own
Continue-Saved-Run button (that moved to `character_select.gd`, the actual entry point).

**Grid-of-square-tiles layout** (deliberate redesign — no AC/ability-scores/HP shown here anymore,
that numeric detail was judged noisy for a first-screen pick): `TILE_SIZE = 170` square tiles laid
out via manual position math (`GRID_COLUMNS = 6`, `TILE_GAP = 18`, row/col from `idx / GRID_COLUMNS`
/ `idx % GRID_COLUMNS`) instead of the old single-row 4-wide layout — designed to keep scaling as
more classes are added without ever needing a redesign. Each real class tile is a flat `Button`
(not a `Panel` + separate click layer) showing only sprite icon, name, hit die, and a 1-2 line
flavor `desc` — `CLASS_DATA` no longer carries an `hp`/stat-block field at all. A **Random** tile
(`_build_random_card()`, purple `RANDOM_COLOR`, dice glyph in place of a sprite) sits right after
the 4 real class tiles, before the locked ones — clicking it rolls `CLASS_DATA[randi() %
CLASS_DATA.size()]` and calls the exact same `_on_class_selected()` a normal tile uses, so it still
walks the entire point-buy/background/race/mastery Custom flow (per direct owner correction: it
must NOT bypass those screens the way a premade hero on `character_select.gd` does — only the
class choice itself is randomized). `LOCKED_CLASSES`
(Bard/Cleric/Druid/Fighter/Paladin/Rogue/Sorcerer/Warlock — the rest of the 5e class list, not yet
implemented) render as non-interactive tiles (`_build_locked_card()`: dark `Panel`, dimmed name,
"Coming Soon" subtitle, `MOUSE_FILTER_IGNORE`) appended after Random in the same grid — purely
cosmetic roster completeness, no selection path exists for them. **Portrait**: `_build_locked_card()`
checks `res://sprites/characters/classes/<class_name>/idle_1.png` and shows a dimmed
(`Color(0.55,0.55,0.55,0.85)`) `TextureRect` portrait when it exists (Bard/Cleric/Druid/Fighter/
Rogue/Warlock all have art now — see root `CLAUDE.md`'s "Locked-class art") instead of the gray "?"
glyph fallback (still used for Paladin/Sorcerer, which have no folder yet) — purely visual, doesn't
make the tile interactive. Adding a real class: append to `CLASS_DATA` and remove its name from
`LOCKED_CLASSES`.

**Info tooltip ("i" badge)**: each real `CLASS_DATA` entry carries an `"info"` dict
(`primary_ability`, `hit_die`, `check_profs`, `weapon_profs`, `armor_training`,
`starting_equipment` — all plain display strings, not derived live from `Stats`, so keep them in
sync by hand if a class's proficiencies change) rendered via a small round "i" `Button` in the
tile's top-right corner (`_build_info_icon()`) using Godot's native `Control.tooltip_text` (plain
`"\n"`-joined text, no custom popup) — hover to read, no click behavior. `starting_equipment` is
intentionally blank (`_format_class_info_tooltip()` shows "TBD") for all 4 classes today — see
`docs/TODO.md`'s "Fill in Starting Equipment" entry. This icon's `mouse_filter` is deliberately
`STOP` (Godot's Control default), unlike every other decorative child on a tile (icon/name/hit-die/
desc labels all use `MOUSE_FILTER_IGNORE` to let the click fall through to the card `Button`) — so
tapping the badge can never accidentally select that class.

## Point buy select (`point_buy_select.gd`)
CanvasLayer, layer = 22. One-time, mandatory ability-score allocation spawned by
`class_select.gd._on_class_selected()` right after `class_chosen` fires, **before** the
background picker — Custom character-creation path only (premade heroes never reach it). D&D
2024 rules: no race grants a raw ability-score bonus (`Stats.apply_race_defaults()` never touches
base scores — a background's ASI fills that role instead, see "Background select" below).
Modeled on `race_select.gd`'s conventions (dim overlay + centered
bordered `Panel`, `focus_mode = FOCUS_NONE` everywhere, `GameState.point_buy_open` input-gate
flag, non-dismissible — no close button, `_unhandled_input` swallows Esc/keys).

All six scores (STR/DEX/CON/INT/WIS/CHA) start at 8; a `Min`/`-`/`+`/`Max` button row per stat
adjusts each within `Stats.POINT_BUY_MIN`(8)`..POINT_BUY_MAX`(15), spending from a shared
`Stats.POINT_BUY_BUDGET`(27) pool. Cost per step comes from `Stats.POINT_BUY_COST` (the standard
D&D point-buy table: 8→13 cost 1 point/step, 14 and 15 cost 2 points/step — reaching 15 from 8
costs 9 total). `+` disables per-row at `POINT_BUY_MAX` or when the next step's cost exceeds
points remaining; `-` disables at `POINT_BUY_MIN`. `Min` jumps the row straight to 8 (always
legal — freeing points never fails); `Max` jumps to `_max_affordable_score()`, the highest score
this row can reach given the points currently tied up in every *other* stat (that row's own
current cost is credited back first, then the highest affordable score ≤ 15 is picked) — so
maxing one stat first, then hitting Max on another, correctly caps at whatever the remaining
budget allows rather than always jumping to 15. `Min`/`Max` share the same disabled condition as
`-`/`+` respectively (already at that extreme). Confirm is always enabled (unspent points are
simply left on the table — not enforced to be fully spent). Confirm calls
`GameState.player_stats.apply_point_buy_scores(_scores)` (`scripts/entities/stats.gd` — overrides
the six base scores set by `apply_class_defaults()` and re-derives `max_hp`/`current_hp`/
`armor_class`, mirroring that function's own tail), re-emits `GameState.player_hp_changed`, then
spawns `background_select.gd` itself before `queue_free()`.

## Background select (`background_select.gd`)
CanvasLayer, layer = 22. One-time, mandatory ability-score-bonus allocation spawned by
`point_buy_select.gd._on_confirm()` — Custom character-creation path only, right after point buy
and before race select. D&D 2024 rules: a character's **background** (not race) grants an ability
score increase — 3 points, max 2 into any single score. Modeled directly on
`point_buy_select.gd`'s layout (dim overlay + centered bordered `Panel`, `focus_mode = FOCUS_NONE`
everywhere, `GameState.background_select_open` input-gate flag, non-dismissible).

Snapshots the six scores right after point buy (`_base_scores`) in `_ready()`, then a `-`/`+`
button row per stat adjusts a separate `_bonus[key]` in `0..Stats.BACKGROUND_MAX_PER_STAT`(2),
spending from a shared `Stats.BACKGROUND_POINTS`(3) pool — unlike point buy, there's no `Min`/`Max`
row (only 3 points total, `Min`/`Max` would be redundant) and, unlike point buy, **Confirm is
disabled until all 3 points are spent** (`_confirm_btn.disabled = remaining > 0`) — a background's
grant isn't optional budget to leave on the table the way point buy's is. Each row's label shows
`"base (+bonus) -> final (mod)"` so the resulting score/modifier is visible before confirming.
Confirm calls `GameState.player_stats.apply_background_bonus(_bonus)`
(`scripts/entities/stats.gd` — **adds** to, never overrides, the six scores point buy already set,
then re-derives `max_hp`/`current_hp`/`armor_class` the same way `apply_point_buy_scores()` does),
re-emits `GameState.player_hp_changed`, then spawns `race_select.gd` itself before `queue_free()`.
Not a full 2024 background system — no named backgrounds, skills, tool proficiencies, origin feat,
or starting-equipment table (none of those systems exist elsewhere in this codebase); scope is
deliberately just the ability-score increase.

## Race select (`race_select.gd`)
CanvasLayer, layer = 25. One-time, mandatory choice spawned by `background_select.gd._on_confirm()`
(Custom path) — see "Background select" above. `race_picker_open` input-gate flag, non-dismissible
(no close button, `_unhandled_input` swallows Esc/keys).

**Tile-grid layout** (mirrors `class_select.gd`'s square-tile convention, redesigned from an
earlier wide-description-card layout — direct owner request to visually match the class-select
screen): 10 square `TILE_SIZE` (170px) tiles in a `GRID_COLUMNS` (5) × 2 grid inside the bordered
`Panel`, each showing a portrait (`icons/races/<id>/portrait.png` — falls back to a gray "?" glyph
if missing, same convention as `class_select.gd`'s locked-class silhouette; same file the HUD's
`race_bonus` status-tray icon reuses, see `scripts/entities/CLAUDE.md`'s "Race-granted ability
icons"), the race name in a per-race accent color, a 2-line flavor blurb (`short_desc`), and a
small "i" info badge (top-right, `_build_info_icon()` — same `mouse_filter = STOP`/native-tooltip
shape as `class_select.gd`'s own info icon, but the blurb text is hard word-wrapped first via
`_wrap_text(text, WRAP_COLS=46)` — **bugfix**: Godot's native `Control.tooltip_text` rendered
these ~300-char blurbs as one barely-legible run-on line with no font-size override worth fighting,
so the string itself is now pre-wrapped into short lines before ever reaching `tooltip_text`)
whose hover tooltip shows the race's full mechanical rundown (the `blurb` field — same text the
old wide cards used to show inline). A race with a `sub_kind` also shows a small "choose…" hint
label at the tile's bottom edge.

**Sub-choice selection** (Human/Elf/Dragonborn/Tiefling/Gnome/Goliath — ability-score proficiency /
sub-race / ancestry / legacy / a combined lineage+stat pick / Giant Ancestry): a small tile has no
room for the old inline sub-choice row, so selecting a race with a `sub_kind` reveals a **shared**
sub-choice button row BELOW the grid (`_sub_label`/`_sub_container`, rebuilt fresh on every
`_select()` call — only ever shows the currently-selected race's own options, not one row per
race) instead of a per-card row. Must be picked before Confirm enables. Goliath's own sub-choice
(`sub_kind: "giant_ancestry"`, 6 flat options — Cloud/Fire/Frost/Hill/Stone/Storm) is the simplest
of the bunch, decoded exactly like Dragonborn's ancestry/Tiefling's legacy (`variant =
_selected_sub` directly, no combined-index decoding needed) — see `scripts/entities/CLAUDE.md`'s
"Goliath" section. **Gnome is the one race with two independent sub-choices** (a Gnomish Lineage
AND a Gnomish Cunning stat, see `scripts/entities/CLAUDE.md`'s "Gnome" section) — rather than build
a second parallel sub-choice UI, its `sub_options` just lists all 6 combinations ("Forest (INT)"/
"Forest (WIS)"/"Forest (CHA)"/"Rock (INT)"/"Rock (WIS)"/"Rock (CHA)") through the exact same
single-`sub_kind` row every other race uses; `_on_confirm()`'s `"gnome"` match arm decodes the
picked index back into `variant = idx / 3` (lineage) and `prof_ability = 3 + idx % 3` (3/4/5 =
INT/WIS/CHA, reusing Human's own ability-index convention instead of adding a second field).
Confirm calls
`GameState.choose_race(race, variant, prof_ability)`, then spawns `mastery_picker.gd` itself
(same `mastery_cap() > 0` gate class_select used to apply) before `queue_free()` — so the full
onboarding order for the Custom path is **class select → point buy → background ASI → race
select → mastery picker**. The Continue-saved-run flow (`character_select.gd._on_continue_pressed()`)
skips all five; ability scores and race are both restored via `Stats.to_dict()`/`from_dict()`
(`character_race`/`race_variant`/`race_prof_ability` plus the plain score ints) same as any other
stat.

## Cantrip / starting-spell picker (`cantrip_select.gd`)
CanvasLayer, layer = 25. Mandatory **post-spawn** pick (`class_selected` already `true` — see
"Custom character creation" above), spawned directly by `character_summary.gd._on_confirm()` for
Wizard/Warlock (in the same slot the Mastery Picker would occupy — their `mastery_cap()` is 0, so
the two branches there are mutually exclusive) or by `mastery_picker.gd._finish_learn()` right
after its own mastery pick for Ranger (which needs both). Dim overlay + centered bordered `Panel`,
`focus_mode = FOCUS_NONE`, non-dismissible (no close button, `_unhandled_input` swallows all keys)
— and deliberately **no Back button anywhere in this file** (direct owner request, same reasoning
as `mastery_picker.gd`'s own post-spawn mode: removes the free "Back → reroll" loop). **Icon-focused tile grid, up to 3 per row**
(`TILE_SIZE`/`TILE_GAP`/`ICON_SIZE`/`COLS` consts, `_build_tile()`) — direct owner request,
replacing an earlier full-text-card-per-row layout: a tile shows only the spell's icon + name,
click commits immediately (`subclass_select.gd`'s card-click-commits style, no multi-select within
a round), and the full structured readout (`SpellTooltip.build(spell, false)`) shows on hover as a
**styled BBCode popup** — a small bordered `Panel`+`RichTextLabel` built by `_setup_tooltip()`/
`_show_tooltip()`/`_hide_tooltip()`, reusing `hud.gd`'s own quickbar-tooltip bg/border convention
(`Color(0.05,0.05,0.09,0.97)` bg, 1px `Color(0.55,0.50,0.35)` border) — **not** a native
`Control.tooltip_text` (direct owner correction: the OS-native tooltip reads too faint/plain-text
to be legible, and the whole point was to reuse the same styled readout the Spellbook/quickbar/
ability-bar hover already show, not reinvent a worse one). Anchored **above** the hovered tile by
default (`_show_tooltip()`'s `ty` calc, falls back to below only if there's no room above — same
shape as `hud.gd._position_qbar_tooltip_near()`) — a second owner correction, the tooltip used to
spawn below the icon. Since round 1→2 tears down and rebuilds the entire node tree
(`_on_chosen()`'s `queue_free()`-everything loop), `_setup_tooltip()` is called fresh
at the end of every `_build_ui()`, not just once in `_ready()`. Same tile/tooltip shape duplicated
(not shared via a common helper — small enough to not force a premature abstraction) by
`spell_learn_picker.gd` and `invocation_picker.gd` below — see those sections. Panel height grew
(`y0`/separator/title/hint offsets all bumped) so the title/hint text has real breathing room above
the separator line instead of crowding it. There ARE **two rounds**
(owner-requested: a starting Wizard picks exactly **one cantrip and one level-1 spell**, not
two of either): round 1 (`_round = 1`) is "pick 1 of 3" from the fixed `SpellDb.STARTER_CANTRIP_IDS`
trio (Fire Bolt / Ray of Frost / Shocking Grasp — unchanged pool, so the premade Jace's
`"cantrip": "fire_bolt"` shortcut and old saves stay valid); its `_on_chosen()` calls
`GameState.choose_cantrip()` (which also auto-assigns the pick into the Special quick-cast slot —
see `scripts/autoloads/CLAUDE.md`), then re-seeds `_round = 2` and `_candidates` to the fixed
`STARTING_SPELL_IDS` pair (Magic Missile, Shield — "pick 1 of 2"), tears down the old panel
(`queue_free()` — deferred, since this runs inside the pressed card's own signal handler; hidden
via `visible = false` first so the new round-2 panel doesn't render on top of a still-visible
stale one for a frame) and calls `_build_ui()` again on the SAME script instance (title swaps to
"Choose Your Starting Level-1 Spell"). Round 2's pick calls `GameState.choose_starting_spell()`
(learns AND prepares it — prepared cap is 1 at level 1) then sets `GameState.cantrip_picker_open =
false`, calls `GameState.snapshot_character_creation()` (the whole onboarding chain is done at this
point — see "Try Again" in `scripts/autoloads/CLAUDE.md`), and frees the overlay for good. Ranger's
single round and Warlock's single round do the same snapshot-then-free on their own pick. See
`scripts/entities/CLAUDE.md`'s "Wizard spellcasting" section for what each pick actually grants.

## Spell-learn picker (`spell_learn_picker.gd`)
CanvasLayer, layer = 25. Wizard-only, spawned by `hud.gd._on_player_leveled_up()` whenever
`GameState.spell_learn_pending` is true (set by `GameState._roll_spell_learn_choices()` on every
Wizard level-up, not just even ones — see `scripts/entities/CLAUDE.md`'s "Wizard leveled
spells"). Modeled directly on `cantrip_select.gd`: dim overlay + centered bordered `Panel`,
non-dismissible (`_unhandled_input` swallows all keys, no close button), same icon-tile grid + own
`_setup_tooltip()`/`_show_tooltip()`/`_hide_tooltip()` styled-BBCode-popup-above-the-tile
(up to 3 per row — see `cantrip_select.gd`'s own section above) — up to 3 tiles
(`GameState.spell_learn_choices`) that commit immediately on
click via `GameState.learn_spell(id)` — no skip option, matches the owner's framing of this as a
mandatory level-up choice. Tile count can be 1 or 2 instead of 3 when fewer eligible spells
remain; the picker never spawns at all if zero are eligible (a gray "No new spells available to
learn." chat line fires instead) — expected and common with only 4 example spells in
`SpellDb.LEVELED_SPELL_IDS` (see `docs/architecture/leveled-spells-and-slots-plan.md` §7's
content-count caveat).

## Eldritch Invocation picker (`invocation_picker.gd`)
CanvasLayer, layer = 25. Warlock-only, mandatory-per-slot, spawned by `hud.gd` on
`GameState.invocation_choice_required` — see `scripts/entities/CLAUDE.md`'s "Warlock class"
section for the slot schedule and grant mechanism. Same icon-tile grid + styled-BBCode-hover-popup
convention as `cantrip_select.gd`/`spell_learn_picker.gd` above (up to 3 per row, `_build_tile()`,
hover shows bold name + level + description in the same popup panel, anchored above the tile) —
no icon art exists for any invocation yet
(`EldritchInvocation.icon_path` stays `""` until sourced), so every tile currently renders with a
blank icon area, same asset-debt precedent as `mastery_picker.gd`'s icon slots. Click commits
immediately (`GameState.learn_invocation(id)`), then re-spawns itself if another slot is still
pending (`GameState.warlock_invocation_slots_pending > 0` — e.g. level 2's +2). If nothing is
currently eligible (pending slots outrunning designed content), shows a plain message + "Continue"
button that closes WITHOUT respawning instead — respawning on an empty eligible list would loop
forever.

## Spellbook overlay (`spellbook_overlay.gd`)
CanvasLayer, layer = 25. Wizard-only, opened by pressing **O** (`player.gd._unhandled_input()`,
guarded the same way as every other blocking-overlay key — see the guard chains in
`scripts/entities/CLAUDE.md`'s "Player-specific" section), closed by O or Esc. Sets
`GameState.spellbook_open = true` → blocks all player input (same treatment as
`mastery_picker_open` etc.) — but unlike the Mastery Picker, this overlay can be opened **any
time**, not just post-level-up/post-long-rest (`docs/architecture/leveled-spells-and-slots-plan.md`
§5.5 — deliberate deviation from the framework doc's rest-gated Prepare-Spells picker).

Modeled on `mastery_picker.gd`'s structure (dim overlay + centered bordered `Panel`, hover-detail
panel, bottom-right "X / Y" counter) with level tabs added across the top: an always-present
**Cantrips** tab (level 0 — not gated on slot progress, since a Wizard always knows their 3
cantrips) followed by one tab per level in `_known_levels` — every leveled-slot level the character
currently has (`StandardSlotPool.max_slots()`'s keys) **plus** the level of any spell already in
`known_spells` even if slot progress hasn't reached it yet (covers the debug panel's "Give
Spell..." granting a spell above the character's current level — see "Debug panel" below — it must
still get a tab to appear in, non-contiguous levels included, not just `range(1, max_level+1)`).
`_tab_buttons` is a `Dictionary[int, Button]` keyed by level (was a `-1`-indexed `Array`, switched
when level 0 was added to avoid fragile index math).
Selecting a tab lists the Wizard's known spells of that level as square tiles (icon on top, name
label below, gold border/tint when prepared or a cantrip — `_build_row()`'s `is_cantrip` branch
always renders a cantrip in the same gold "always ready" style as a prepared leveled spell; no text
suffix, the gold border/name color alone communicates prepared state), **sorted alphabetically by
spell name**. Tiles are laid out in a `GridContainer` (`TILE_W`/`TILE_H`/`TILE_GAP` constants,
columns computed from the available width) inside a `ScrollContainer` (vertical-only) so a level
holding more spells than fit in the visible area (e.g. many cantrips) scrolls instead of
overflowing the panel.
**Hover** a tile → the detail panel below shows its full description (same "browse and pick"
hover-detail pattern as the Mastery Picker, not a `[url=]` tooltip). **Click** a tile → toggles
prepared/selected via `GameState.set_spell_prepared(id, bool)` for either kind of spell (cantrip
OR leveled) — hard-blocked at that kind's own cap (`SpellcasterState.cantrip_max()` for a cantrip,
`prepared_max()` for a leveled spell; clicking an unprepared spell at cap is a silent no-op, same
feel as the Mastery Picker's cap block). **Bottom-right counter**: `"X / Y prepared"` on BOTH the
Cantrips tab and every leveled-spell tab now (identical `RichTextLabel`/color convention to the
Mastery Picker's `_counter_rtl` — gold under cap, gray at cap, red if ever over) — a cantrip
Learned past `cantrip_max()` (e.g. via scroll "Learn") sits known-but-unprepared until a slot frees
up, same "known but not selected" shape a leveled spell already had past `prepared_max()`; no more
static "Always ready" text. `GameState.set_spell_prepared()` and `place_spell_in_slot()` both check
the clicked/dropped spell's own kind (`Spell.level == 0`) to pick which cap/count applies —
`SpellcasterState.prepared_cantrip_count()`/`prepared_leveled_count()` — see
`scripts/autoloads/CLAUDE.md` and `scripts/entities/CLAUDE.md`'s "Cantrip cap" note.

**Special quick-cast slot** (assignment point — see `inventory_overlay.gd`'s "Special quick-cast
slot" above for the read-only display): a small bordered box below the drag-and-drop hint text,
built in `_build_ui()` (`_special_slot_box`). Any known spell (cantrip or leveled) dragged here —
same press-and-hold-then-release drag mechanism as dragging onto the ability bar — calls
`GameState.set_special_slot(spell_id)` instead of `place_spell_in_slot()`; checked in
`_finish_drag()` as one more candidate rect alongside the existing 9 ability-bar slots, ahead of
that loop. Exists here rather than in `inventory_overlay.gd` because the Inventory and Spellbook
overlays are mutually exclusive (`player.gd`'s R/I key guards) — there is never a frame where both
are open, so a drag spanning the two overlays is impossible; the Inventory-side box is
consequently display-only (see above).

**Reverse direction — ActionBar slot → Special slot**: while the Spellbook is open, a spell can
also be dragged the other way, straight off an already-placed ability-bar slot onto the Special
box, reusing `hud.gd`'s own in-bar reorder drag (see "In-bar reorder drag" above) rather than this
overlay's row-drag. `spellbook_overlay.gd` exposes `get_special_slot_global_rect()` (empty `Rect2`
if the box isn't built yet) and `refresh_after_external_change()` (thin public wrapper around
`_refresh()`) via `add_to_group("spellbook_overlay")`; `hud.gd._process_bar_drag()`'s release
branch checks that rect first (when `_ability_bar_mode and GameState.spellbook_open`), and on a hit
reads `GameState.player_ability_bar[_bar_drag_from]`, accepting only if its `ability_id` starts
with `"spell:"` (rejects non-spell abilities like Rage/Frenzy), then calls
`GameState.set_special_slot(spell_id)` and the overlay's refresh — skipping the normal same-bar
slot-swap for that release. No camera-pan risk: `player.gd`'s `_input()` motion handler already
unconditionally suppresses panning whenever `GameState.spellbook_open` is true.

**Drag-and-drop** (leveled-spells-and-slots-plan.md §5.4): press-and-hold a row past
`DRAG_THRESHOLD` (8px) spawns a floating icon and arms a drag; release resolves via
`_process()` polling `Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT)` — **not** a mouse-button-up
event — because a `Button`'s own `gui_input` can swallow the release before a sibling's
`_unhandled_input` ever sees it (`inventory_overlay.gd`'s proven pattern, reused here rather than
invented fresh). A drop is only accepted when `hud.gd.is_ability_bar_showing()` is true (the HUD's
`_ability_bar_mode` flag — Tab toggles the *same physical* `ActionBar` buttons between the item
quickbar and the ability bar, so this check is what makes "never onto the item quickbar" correct
without needing a second, separate ability-bar surface) AND the mouse is over one of
`hud.get_action_slot_global_rect(i)`'s rects (both new small `hud.gd` accessors added for this,
plus `add_to_group("hud")` in its `_ready()` so a different CanvasLayer script can find the live
instance) — otherwise the drop is silently rejected with a gray log line, icon snaps away. On a
valid drop, `GameState.place_spell_in_slot(spell_id, index)` prepares (if not already) and places
the spell's `Ability` directly into that slot index, bumping whatever was there back on via
`add_ability()`'s normal first-empty-slot placement rather than discarding it. **Not implemented**:
the framework doc's multi-page ability-bar auto-paging (still a single 9-slot
`GameState.player_ability_bar`) — drag targets that one bar, not a specific "2nd–4th quickbar"
page, since no such paging exists yet in this codebase.

**Bugfixes from initial playtesting**: (1) the overlay's dim `ColorRect` used to cover the ENTIRE
screen (`mouse_filter = STOP`) — since it's a higher CanvasLayer `layer` than the HUD, this
visually hid AND input-blocked the ActionBar the whole time the book was open, making its own drag
target impossible to see or hit. The dim now stops `ACTION_BAR_HEIGHT` (140px) above the bottom
edge, leaving the strip fully visible/clickable. (2) if the item quickbar happened to be showing
(not ability mode) when `R` was pressed, every drop was silently rejected with nothing visible to
aim at anyway. `_ready()`/`_close()` now call the new `hud.gd` `set_ability_bar_mode(bool)` to
force ability-bar mode for the overlay's whole lifetime, restoring whichever mode was showing
before on close. (3) `player.gd`'s `_input()` camera-pan detector (fires before any Control's
`gui_input`, so it's independent of this overlay's own drag logic) only excluded
`GameState.inventory_open`, not `spellbook_open`/`spell_learn_picker_open` — holding LMB and
dragging a spell row also panned the game world/camera underneath the whole time. Fixed at the
source in `player.gd` (see `scripts/entities/CLAUDE.md`'s "Player-specific" section), not here.

**Always-visible spell-slots row**: a small `RichTextLabel` (`hud.gd`'s `_spell_slots_label`, in
`$StatsPanel` right under the status tray — `StatsPanel.offset_bottom` grown 158→200 in
`hud.tscn`) shows `"1st X/Y   2nd X/Y   ..."` per slot level at all times, not just while the
Spellbook is open — addresses the original playtesting feedback that slot counts were otherwise
invisible outside `R`. Blue when slots remain, dimmed gray at 0. Wired to
`GameState.spell_slots_changed` (consume/refill/level-up-grant/prepare-toggle),
`player_leveled_up`, and `class_chosen`; empty string for every non-caster class.

## Custom character creation: Back navigation + summary screen

The full Custom-path chain is now **class select → point buy → background ASI → race select →
character_summary.gd (review/confirm) → mastery/cantrip/spell picker (post-spawn) → game begins**.
Every screen through `race_select.gd` supports going backward; `character_summary.gd` is the final
review/confirm before the run genuinely starts. Key structural change: `GameState.class_selected`
is **no longer set `true` inside class_select.gd** — it stays `false` for the ENTIRE class-select
→ race-select span (player input is hard-gated on it in `player.gd`, so the player literally cannot
touch the already-loaded floor 1 underneath no matter how much back-and-forth happens) and is only
set at `character_summary.gd`'s final "Yes" confirm, which also re-emits `class_chosen` so
`SaveManager`'s checkpoint-on-that-signal hook (previously a no-op the whole time, since it's gated
on `class_selected`) finally fires.

**Deliberate ordering change (direct owner request)**: weapon masteries and starting cantrips/
spells used to be picked BEFORE `character_summary.gd`, which meant hitting "Take Me Back" and
reconfirming race select was a free way to keep re-rolling a bad mastery/spell draw (masteries/
cantrips were wiped and re-rolled fresh on every re-entry). They're now picked AFTER "Yes, I'm
Ready!" — once `class_selected` is already `true` and the character has genuinely spawned into the
run — specifically so that loophole is gone: `mastery_picker.gd`/`cantrip_select.gd` have **no Back
button at all** in this post-spawn mode, the pick is final the instant it's made. This also means
`character_summary.gd` can no longer show the actual chosen masteries/spells (they don't exist yet
at that point) — it shows a one-line "you'll choose your X once you begin" heads-up instead.

**Every screen through race_select gained a "← Back" button** (top-right corner, muted-gold style)
that tears down the current overlay and spawns the previous one:
`point_buy_select` → `class_select` → `background_select` → `point_buy_select` →
`race_select` → `background_select` → `character_summary` → `race_select`. `class_select.gd` itself
has no Back (it's the first step); `character_summary.gd`'s "Take Me Back" always reopens
`race_select.gd` (nothing class-specific has run yet at that point, so there's nothing else to
undo). Once past `character_summary.gd`'s confirm, there's no Back anywhere in the remaining
mastery/cantrip/spell chain — see above.

**Re-picking a class mid-flow**: `class_select.gd._on_class_selected()` now calls
`GameState.reset_for_class_reselect()` (`scripts/autoloads/CLAUDE.md`) before applying the new
class — wipes equipment/ability-bar/quickbar/bag/talents/masteries back to empty and re-grants the
generic starting Ration/Thief-Tools, then re-derives everything from scratch. Without this,
`give_class_starting_items()`'s own idempotency guard (`equipment.melee != null` check) would
silently no-op on a second call, leaving the OLD class's gear/abilities equipped after picking a
different one via Back.

**Point buy / background prefill on Back**: `GameState.pending_point_buy_scores` /
`pending_background_bonus` (both `Dictionary`, empty = "no confirmed allocation yet") are written
by each screen's own Confirm and read by that screen's `_ready()` to restore the last-confirmed
allocation when re-opened via Back — so bouncing back one step and returning doesn't force
re-spending every point from scratch. `reset_for_class_reselect()` clears both (a fresh class pick
always restarts allocation at the flat 8-baseline). **`race_select.gd`'s own Back button must undo
an already-applied background bonus** before reopening `background_select.gd`: that screen snapshots
its "pre-bonus" base scores from `GameState.player_stats`'s CURRENT scores at `_ready()`, and
`apply_background_bonus()` is additive, not an overwrite — re-confirming on top of an
already-applied bonus would double it. `race_select._on_back()` calls
`player_stats.apply_point_buy_scores(pending_point_buy_scores)` first to reset to the pure
post-point-buy baseline. `background_select.gd`'s OWN Back (→ point buy) needs no such undo, since
`apply_background_bonus()` only ever runs from that screen's own Confirm, never before Back can be
pressed. Race picks have no analogous prefill (re-opening loses the prior pick) — race re-selection
is cheap/idempotent (`apply_race_defaults()`).

**`mastery_picker.gd`'s `character_creation_mode: bool`** (set on the instance before `add_child`,
default `false`): spawned only from `character_summary.gd._on_confirm()` — see "Mastery picker"
below for its post-spawn, no-Back behavior. Left `false` (unchanged behavior) for the long-rest
reselect flow (`mastery_reselect_prompt.gd`), which never sees this mode or the summary screen.

**`character_summary.gd`** (`layer = 26`, `GameState.character_summary_open` input-gate flag,
non-dismissible like every other onboarding screen): the review/confirm step, reached right after
`race_select.gd`. Shows a portrait (same per-class sprite path table as `class_select.gd`'s
`CLASS_DATA`), class + race (+ sub-race/ancestry) headline, hit die/HP/AC line, all six ability
scores + modifiers, and — if the class has a mastery cap and/or is a caster — a one-line "you'll
choose your weapon masteries/starting spells once you begin" heads-up (those picks don't exist yet
at this point in the flow, see above) — everything else read live off `GameState.player_stats`, no
separate draft/snapshot object. Two buttons: **"Yes, I'm Ready!"** → `class_selected = true` +
re-emits `class_chosen`, then spawns whichever of `mastery_picker.gd`/`cantrip_select.gd` this
class needs (or, for a class with neither, e.g. Monk, calls `GameState.snapshot_character_creation()`
directly) before freeing itself — the run genuinely begins here, with the mastery/cantrip/spell
chain running on top of an already-spawned character. **"Take Me Back"** → always reopens
`race_select.gd`.

## Mastery picker (`mastery_picker.gd`)
CanvasLayer, layer = 25. Lets the player build up `Stats.known_weapon_masteries` (the array every
weapon-mastery combat effect already gates on — see `scripts/entities/CLAUDE.md`'s "Weapon mastery
ownership") out of `Stats.ALL_WEAPON_MASTERIES` (all 8: Cleave/Graze/Nick/Push/Sap/Slow/Topple/
Vex), up to `Stats.mastery_cap()` (per class/level). Sets `GameState.mastery_picker_open = true` on
open → blocks all player input (same treatment as `talent_picker_open`).

**Two modes, decided ONCE at open time** in `_ready()` from `known_weapon_masteries.size()` vs
`mastery_cap()` (never re-derived mid-flow, so finishing Learn mode can never accidentally fall
through into Swap mode) — direct owner request to make mastery picks "more roguelike," same
tile+hover-tooltip treatment as `spell_learn_picker.gd`/`cantrip_select.gd`/`invocation_picker.gd`
above:

- **Learn mode** (`known < cap` — character creation, or a level-up that raised the cap):
  sequential "pick 1 of 3" random tile rounds (`TILE_SIZE`/`TILE_GAP`/`ICON_SIZE`/`COLS` consts,
  same shape as the spell pickers), one round per missing slot, **mandatory** — no skip, Esc
  swallowed. Each round's 3 candidates are drawn via `Rng.shuffle()` (seeded gameplay stream, never
  `randi()`) from every currently-unknown mastery. A tile click calls `GameState.toggle_mastery(name)`
  (guaranteed the "add" branch — under cap, not already known) and either rebuilds for the next
  round or, once `known.size() >= cap()`, calls `_finish_learn()`.
- **Swap mode** (`known == cap` — reached only from the long-rest hub's "Weapon Masteries" option,
  `mastery_reselect_prompt.gd`): **two steps**, tracked by `_swap_step` (`"discard"`/`"pick"`) —
  reworked from an earlier "click one, get one random replacement" design that a direct owner
  correction called out as conceptually broken (an unlimited-use blind reroll, since nothing
  actually stopped repeating it). **Step 1 ("discard")**: a grid of the player's OWN known
  masteries, plus the always-visible "Done"/Esc — nothing is spent by opening the picker or just
  looking. Clicking one calls `GameState.discard_mastery(old_name)` (removes it, no replacement
  rolled yet) and advances to step 2. **Step 2 ("pick")**: a mandatory "pick 1 of 3" tile round —
  same shape/mechanism as Learn mode (`Rng.shuffle()`, no skip, Esc swallowed by
  `_unhandled_input()`'s `_swap_step == "pick"` branch) — drawn from every mastery that is neither
  the one just discarded nor still known, so the discarded mastery can never reappear as its own
  replacement and an already-known one can never be picked twice. Clicking a candidate calls
  `GameState.toggle_mastery(new_name)` (always the "add" branch here, since discarding first
  guarantees `known.size() < cap()`), shows an in-panel "Lost X → Gained Y" reveal line
  (`blacksmith_panel.gd`'s own reveal-line convention; `_last_reveal_text` persists it across the
  full `_build_ui()` rebuild back to step 1, since — unlike the old design — every step transition
  now tears down and rebuilds the whole panel rather than patching one tile row in place), and
  returns to step 1 so the player can keep swapping or stop via Done/Esc.

Both modes share one `_build_tile(name, pos, on_click)` (icon + name label, hover → the same
styled BBCode tooltip popup anchored above the tile as the spell pickers use — `MASTERY_DESCRIPTIONS`
dict supplies each mastery's one-line body). No icon assets exist yet — icons render blank
(`res://icons/masteries/<name>.png`, none exist) until supplied; the bordered tile frame keeps
each button visible/clickable regardless, same asset-debt precedent as before this rework.

**`character_creation_mode: bool`** (set on the instance before `add_child`, default `false`): the
**POST-SPAWN** onboarding pick — spawned only by `character_summary.gd._on_confirm()`, after
`class_selected` is already `true`. Deliberately has **no Back button anywhere in Learn mode** —
direct owner request, removing the earlier "Back → reconfirm race select → reroll" cheese that
existed when this picker ran before the final summary/confirm. Once Learn mode finishes, it routes
onward instead of just closing — a caster class (Ranger) spawns `cantrip_select.gd` for its own
starting-spell pick; everyone else calls `GameState.snapshot_character_creation()` (the onboarding
chain is now genuinely done — see "Try Again" in `scripts/autoloads/CLAUDE.md`) and just closes.
`_ready()` still unconditionally clears `known_weapon_masteries` in creation mode as a defensive
no-op (there's no Back path back into this screen anymore, so it should never actually find
anything to clear).

**Wired to fire three ways**: from `character_summary.gd._on_confirm()` (`character_creation_mode
= true`) once the character has spawned, instantly on any level-up that raises `mastery_cap()`
itself (currently only Barbarian, at levels 4 and 10) — `GameState.gain_exp()` snapshots
`mastery_cap()` before applying the level-up and sets `mastery_learn_pending = true` if it grew,
`hud.gd._on_player_leveled_up()` spawns this picker right away when that flag is set (same
"instant pick" treatment as hit dice/spell slots growing on level-up — see root CLAUDE.md's
"Talent system"), naturally landing in Learn mode since `known < cap` right after the cap just
grew — and from the long-rest hub's "Weapon Masteries" option (`mastery_reselect_prompt.gd`, see
"Long-rest hub" above), naturally landing in Swap mode since masteries are already at cap by then.
Never triggered by short rest or floor descent.
