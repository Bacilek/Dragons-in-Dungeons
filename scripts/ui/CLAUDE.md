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

**Gold counter**: a small coin icon (`TextureRect`, `Misc/CoinGold.png`, `ignore_texture_size = true` per the rule above) + gold-tinted amount Label (`_gold_label`) in `$StatsPanel` next to the hit-dice label, wired to `GameState.gold_changed` (`_on_gold_changed(new_amount)`). Session-7a minimal UI — visual polish deferred.

**ActionBar (bottom quickbar/ability bar) scale**: `scenes/ui/hud.tscn`'s `ActionBar` panel and its 9 `ItemSlotN` buttons + Wait/Search/Interact buttons are sized 1.5× the original layout (`ActionBar` height 90→135, slot size 76→114px, pitch 80→120px). Item/ability icons use `Button.icon` + `expand_icon = true` so they auto-scale with the button — no separate icon-size code to touch. The per-slot quantity badge (`_slot_qty_labels`) and ability use-count badge (`_slot_use_labels`) offsets/font sizes in `hud.gd` scale alongside (`-32/-18/11pt` → `-48/-27/16pt`). `_bar_mode_label` offsets are pinned to `ActionBar`'s new top (`-135`), not the old `-90`. Each slot also carries a static top-left `_slot_num_labels` badge showing its 1-9 hotkey (slot index `i` → `KEY_(i+1)`, matches `player.gd`'s `_use_quickbar_slot`/`_use_ability_slot` dispatch) — created once in `_ready()`, never toggled, visible in both item and ability bar mode.

**Ability bar greying**: `_refresh_ability_bar()`'s slot `modulate` is gray whenever `not GameState.is_ability_usable(ab)` (see `scripts/autoloads/CLAUDE.md`) — covers plain exhausted charges (Rage) AND infinite-use abilities that are situationally blocked (Frenzy without Rage active, Limit Break already used this long rest, Zealot Strike with 0 Hit Dice, Grip of the Forest without Rage). Orange still means "active toggle" (`ab.is_active`), takes priority over the usability check. **Frenzy cooldown countdown** (Frenzied Killer R3): while `GameState.berserker_frenzy_used` and `get_talent_rank("frenzied_killer") >= 3`, the use-count badge shows `"%dt"` counting down from `3 - GameState.berserker_turns_since_frenzy` (same red tint/format as Rage's own "%dt" remaining-duration display) instead of the normal `uses/max` text — makes the automatic refresh timing visible instead of just guessing.

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
and calls `_status_tray.refresh(entries)`. `StatusTray` pools `TextureRect` icon nodes
(`ignore_texture_size = true` per the rule above), tints them with `fallback_color` when
`icon_path` doesn't resolve via `ResourceLoader.exists()` (no separate `ColorRect` fallback type),
and emits `icon_hovered(id)`/`icon_unhovered()` on mouse enter/exit. `hud.gd` connects these to
reuse the existing qbar-tooltip pair (`_qbar_tooltip`/`_qbar_tooltip_rtl`) via
`_on_status_tray_icon_hovered(id)`, which pulls description text from `status_tooltips.gd`
(`StatusTooltips`, static-func-only helper mirroring `tooltip_formatters.gd`'s pattern — one
`get_text(id)` case per effect id). Sources at launch: `poisoned`/`burning`/`bleeding`/`slowed`
(`Stats.*_turns`), `raging` (`GameState.is_raging`), `temp_hp` (`Stats.temp_hp`),
`unarmored_defense` (Barbarian/Monk with no armor equipped — reads the live AC formula),
`tactician` (`GameState.battlefield_adv_pending`, Battlefield Expert R1's pending-Advantage
window — see `scripts/entities/CLAUDE.md`'s Barbarian Tier 1 talents), `psycho_adv`
(`GameState.psycho_adv_pending`, Psycho's identical pending-Advantage window), `concentration`
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
`scripts/items/CLAUDE.md`'s "Torch"). No `icons/status/` art exists yet — every entry currently renders as a
tinted placeholder square until real icons are supplied (`unarmored_defense`/`tactician`/
`psycho_adv`/`concentration` already reuse existing talent/spell icons, so those render properly
today). Open questions resolved: hover-only tooltip, shared tooltip panel, grow-panel layout.

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

**Short Rest tab** (unchanged mechanics): ←/A/KP4 = minus dice, →/D/KP6 = plus dice, **Space = rest**. Rolls `_dice_to_spend × hit_die_sides() + CON mod` (min 1 per die), heals player, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`, runs for `GameState.SHORT_REST_TURNS` (5) turns.

**Long Rest tab**: shows `GameState.total_food_value() / GameState.LONG_REST_FOOD_COST` and a disabled-reason label when `not GameState.can_long_rest()`. On confirm, sets `GameState.long_rest_pending = true` (instead of computing a pending heal) and runs the same `short_rest_active` countdown for `GameState.LONG_REST_TURNS` (20) turns — reuses the exact short-rest turn-countdown/interrupt machinery in `player.gd._on_turn_started()`, which branches on `long_rest_pending` at completion to call `GameState.long_rest()` instead of applying a short-rest heal, then spawns `mastery_reselect_prompt.gd`. Food is only consumed on successful completion, not on start — an interrupted/aborted long rest costs nothing (`rest_interrupt_panel.gd`'s abort path clears `long_rest_pending`).

Esc always closes/cancels regardless of tab. Sets `GameState.short_rest_open = true` on open → blocks all player input until closed.
**Important ordering in `_on_rest()`/`_on_long_rest()`**: `GameState.short_rest_open = false` and `queue_free()` must be called **before** emitting `player_action_requested("short_rest_begin")` because the signal is synchronous — `_on_turn_started` fires inside the chain and checks `short_rest_open`.

## Long-rest hub (`mastery_reselect_prompt.gd`)
CanvasLayer, layer = 26. Spawned by `player.gd` right after `GameState.long_rest()` completes — was
originally a plain Yes/No "reselect masteries?" confirm, now a small hub offering every
long-rest-gated adjustment in one place: **Weapon Masteries** (only shown when
`player_stats.mastery_cap() > 0`), **Attunement** (always shown), **Spellbook** (only shown when
`player_stats.caster != null`), and **Done**. Sets `GameState.mastery_picker_open = true` for its
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

---

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: **God Mode** (checkbox — activates invincible + noclip + see_all + exposes enemy rolls/HP in chat log), **Show Stealth Checks** (checkbox — `GameState.debug_show_stealth_checks`, logs every per-turn Stealth-vs-Passive-Perception roll pass or fail instead of only real detections; visibility only, never changes the roll — see `scripts/entities/CLAUDE.md`'s "Stealth & Surprise Attacks"), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel listing all `DungeonFloorData.ENEMY_POOL` + `BOSS_POOL`, spawns adjacent to player via `dungeon_floor.debug_spawn_enemy()`), **Level Up** (`GameState.debug_level_up()`), **Give 100 Gold** (`GameState.add_gold(100)`), **Give Spell...** (sub-panel listing every `SpellDb.CANTRIP_IDS + LEVELED_SPELL_IDS` entry — icon, name, `SpellDb.ordinal(level)` badge, description, "Give" button; `_on_give_spell()` calls `GameState.choose_cantrip()` for a level-0 spell or `learn_spell()` + `set_spell_prepared(id, true)` for a leveled one, both idempotent/cap-safe — for testing any spell without playing through level-ups, no quantity control since spells are boolean known/prepared, not stackable), See All, **Mute** (bottom of the main panel, below Give Spell — calls `AudioManager.toggle_mute()`, label swaps 🔊/🔇 in sync with `AudioManager.mute_changed`, same signal the HUD's own top-right `MuteButton` listens to; added as a more-discoverable second entry point since that corner button is easy to miss).

DungeonFloor registers itself in group `"dungeon_floor"` in `_ready()` so the debug panel can locate it via `get_tree().get_first_node_in_group("dungeon_floor")`. Pool data (`ENEMY_POOL`/`BOSS_POOL`/`ITEM_POOL`) is read directly off `DungeonFloorData` (`scripts/world/dungeon_floor_data.gd`, global via `class_name`) — no `load()` of `dungeon_floor.gd` needed.

**Item sync rule**: any new entry in `DungeonFloorData.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
**Scale**: `SLOT_SIZE = 90`, `SLOT_GAP = 6` (`STEP = 96`), `PANEL_W = 1020`, `PANEL_H = 690` — 1.5× the original 60/4/820/460 values (bumped for legibility; keep the whole overlay's fonts/paddings/offsets scaling off these two constants if you touch them again).
Equipment slot labels: **Main Hand** (key `"melee"`) / **Off-hand** (key `"hand2"`) / **Ranged** (key `"ranged"`) in `GameState.equipment`.
**Equipment grid layout** (`_build_equipment_section()`, positions relative to `EQUIPMENT_ORIGIN`): top row is Trinket / Headgear (above Armor) / Ranged (centered above the gap between Main Hand and Off-hand) / **Special** immediately right of Ranged, middle row is Gloves / Armor / Main Hand / Off-hand left→right, Boots bottom-center (below Armor). **Trinket, Headgear, Gloves, and Boots are all display-only today** — `_fits_slot()` has no case for any of them (falls through to its `_` default, `return false`), so nothing can be dragged into any of the four; `equip()`'s auto-routing never targets them either (only `WEAPON`→`melee`/`ranged` and `ARMOR`→`armor`/`hand2`). No item in `ITEM_POOL` targets any of these four slots yet — they're rendered purely so the equipment grid reads as complete, same reasoning as leaving Headgear/Gloves/Boots visible with nothing to put in them.

**Special quick-cast slot** (display-only here — see "Spellbook overlay" below for where it's actually assigned): shows the spell icon for `GameState.special_slot_spell_id` (empty = blank), falling back to the spell name's first 4 letters as text if its `icon_path` doesn't resolve (`_update_special_slot()`'s `has_icon` check). Built with `slot.set_meta("source", "special_display")` instead of `"equipment"` — deliberately NOT part of the Item-shaped equipment drag system (`_do_move()` rejects it outright, `_start_drag()` already no-ops since `_slot_item()` returns null for this source) since it holds a `Spell` reference, not an `Item`. `_update_special_slot()`/`_show_special_slot_tooltip()` are its dedicated render/hover paths (parallel to `_update_slot()`/the generic item tooltip). Right-click calls `GameState.clear_special_slot()`. Cast with **Ctrl+click** in `player.gd` (mirrors Shift+Ranged's one-motion resolve) — see `scripts/entities/CLAUDE.md`'s spellcasting section for `PlayerSpellcasting.cast_direct()`. **Every slot's `Icon` `TextureRect` sets `ignore_texture_size = true`** (`_make_slot()`) — this file was missing it until spell art landed under `res://icons/spells/`; those source PNGs are huge, so without the flag the icon rendered at full native resolution instead of the slot's fixed size, the exact "giant icon" footgun documented in the rule above.
Slot type enforced via `_fits_slot()`: Main Hand (`"melee"`) rejects ranged items and vice versa; `"hand2"` (Off-hand) accepts any non-weapon item, or a Light melee weapon (e.g. the Handaxe) — but only when Main Hand is *also* currently Light — rejecting non-Light weapons, ranged weapons, and a Light weapon whenever Main Hand isn't Light. `equip()` always routes non-ranged weapons to `"melee"` regardless of how they're equipped (pickup, starting gear, debug give-item, or explicit equip) — Off-hand is never auto-populated, only reachable via explicit drag. Dual-wielding two Light weapons now fires a real bonus Off-hand attack — see `scripts/items/CLAUDE.md`'s "Dual-wielding".
**Two-handed cross indicator**: each `"hand2"` slot gets a hidden `BlockedMark` Label (red "✕", built in `_make_slot()`) toggled in `_refresh()` — visible whenever `GameState.equipment.get("melee")` is non-null and `Item.is_two_handed`, signalling the off-hand is unusable while a two-handed weapon is equipped. Purely visual; `is_two_handed` still doesn't block anything else (e.g. the ranged slot) — see root `CLAUDE.md`.

**Versatile grip toggle**: clicking the Main Hand slot without dragging (press+release inside the same slot, detected in `_finish_drag()` when `dest == null` but the release point is still inside `_drag_src_ctrl`) calls `GameState.toggle_versatile_grip()` if the equipped item's `is_versatile == true` (currently Quarterstaff and Spear — see `scripts/items/CLAUDE.md`'s "Versatile weapons"). `_refresh()` gives the Main Hand slot's `StyleBoxFlat` a gold border + thicker width while gripped two-handed (`main_hand.is_versatile and main_hand.is_two_handed`), gray/thin otherwise.

**Thrown weapon durability**: item tooltips (both here and `hud.gd`'s quickbar tooltip) show a right-aligned `Uses: X/Y` line for any `Item.Type.WEAPON` with `is_thrown == true` (currently only the Spear — see `scripts/items/CLAUDE.md`'s "Thrown weapons"), placed just above the existing "Ctrl: inspect" hint.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

**RMB item-interaction menu / LMB-equip**: see `scripts/items/CLAUDE.md`'s "Item interaction menu
(RMB) / LMB-equip" section — `_right_click()`, `_dispatch_item_interaction()`, and the new
click-no-drag-equip branch in `_finish_drag()` all live in this file; the shared `ItemInteractions`
helper (`scripts/items/item_interactions.gd`) and the transient popup Control
(`scripts/ui/item_interaction_menu.gd`, `ItemInteractionMenu`) are both new files this feature
introduced, reused identically by `hud.gd`'s quickbar RMB handler.

**Ctrl-freeze tooltip**: pressing Ctrl while hovering an item (tooltip visible) freezes the tooltip in place and switches `_inv_tooltip.mouse_filter = MOUSE_FILTER_STOP` + `_inv_tooltip_rtl.mouse_filter = MOUSE_FILTER_PASS`. This allows `meta_hover_started` to fire for `[url=keyword:X]` links (e.g. "Heavy"), showing the glossary popup. Ctrl again or closing inventory unfreezes. `_unfreeze_tooltip()` helper restores MOUSE_FILTER_IGNORE on both AND hides the tooltip. `_on_slot_hover()` returns early when `_tooltip_frozen` so moving mouse to other slots does not overwrite the frozen tooltip. Same Ctrl-freeze feature also implemented for the qbar tooltip in `hud.gd` (`_qbar_tooltip_frozen`, `_unfreeze_qbar_tooltip()`, `_input()` handler). All item tooltips show a small gray "Ctrl: inspect" hint in the bottom-right corner.

---

## Character select (`character_select.gd`)
CanvasLayer, layer = 20. **The actual first screen of a new run** — `hud.gd._ready()` now spawns
this instead of `class_select.gd` directly. Shows 5 cards side by side: 4 premade characters
(`PREMADE` const — Garrem Ogar/Orc Barbarian/Cleave+Graze, Tish/Wood Elf Ranger/Slow+Nick, Grok
the White/White Dragonborn Monk, Jace/Halfling Wizard/Fire Bolt) plus a 5th "Custom" card. Clicking a
premade card (`_on_premade_selected()`) applies class + `GameState.give_class_starting_items()` +
`GameState.choose_race(race, variant, prof_ability)` + (for Barbarian/Ranger) directly populates
`Stats.known_weapon_masteries` and emits `known_masteries_changed` + (for Wizard) a `"cantrip"` key
in the `PREMADE` entry calls `GameState.choose_cantrip(id)` directly — bypassing class_select/
point_buy_select/background_select/race_select/mastery_picker/cantrip_select entirely and dropping
straight into the already-loaded floor 1. Each `PREMADE` entry also carries a fixed `"scores"`
dict (`{"str","dex","con","int","wis","cha"}`, applied via `Stats.apply_point_buy_scores()` right
after `apply_class_defaults()` — reusing the same point-buy setter rather than a separate
mechanism) instead of `apply_class_defaults()`'s own generic per-class defaults: Garrem
16/14/16/8/10/10, Tish 8/16/14/10/16/10, Grok 10/16/16/10/14/8, Jace 8/14/16/16/10/10 — no
point buy or background ASI screen either way, just a different fixed stat block per hero.
Clicking
"Custom" (`_on_custom_selected()`) spawns `class_select.gd` unchanged, preserving the full
**class select → point buy → background ASI → race select → mastery picker** chain for a
from-scratch build. Also
owns the "Continue Saved Run" button (moved here from `class_select.gd` since this is now the true
entry point) — same behavior as before, see `scripts/autoloads/CLAUDE.md`'s SaveManager
"Continue flow" section. Jace's card also carries a `"spell1": "magic_missile"` key, applied via
`GameState.choose_starting_spell()` right after the `"cantrip"` key's `choose_cantrip()` call —
premade heroes get their fixed cantrip + level-1 spell without ever seeing `cantrip_select.gd`.

## Class select (`class_select.gd`)
The **Custom** path only now (see `character_select.gd` above) — no longer spawned directly by
`hud.gd`. Emits `GameState.class_chosen` when player selects a class, then spawns
`point_buy_select.gd` (below) and `queue_free()`s itself — point buy owns spawning race select,
which in turn owns spawning the Mastery Picker, not this script. No longer has its own
Continue-Saved-Run button (that moved to `character_select.gd`, the actual entry point).

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
(Custom path) — see "Background select" above. Modeled directly on
`subclass_select.gd`'s conventions (dim overlay + centered bordered `Panel`, `focus_mode =
FOCUS_NONE` everywhere, `race_picker_open` input-gate flag, non-dismissible — no close button,
`_unhandled_input` swallows Esc/keys). 6 race cards (Orc/Human/Halfling/Dwarf/Elf/Dragonborn);
Human/Elf/Dragonborn additionally show an inline sub-choice row (ability-score proficiency /
sub-race / ancestry) that must be picked before Confirm enables. Confirm calls
`GameState.choose_race(race, variant, prof_ability)`, then spawns `mastery_picker.gd` itself
(same `mastery_cap() > 0` gate class_select used to apply) before `queue_free()` — so the full
onboarding order for the Custom path is **class select → point buy → background ASI → race
select → mastery picker**. The Continue-saved-run flow (`character_select.gd._on_continue_pressed()`)
skips all five; ability scores and race are both restored via `Stats.to_dict()`/`from_dict()`
(`character_race`/`race_variant`/`race_prof_ability` plus the plain score ints) same as any other
stat.

## Cantrip / starting-spell picker (`cantrip_select.gd`)
CanvasLayer, layer = 25. Wizard-only, mandatory pick spawned by `race_select.gd._on_confirm()` in
the same slot the Mastery Picker would occupy (Wizard's `mastery_cap()` is already 0, so the two
branches are mutually exclusive — `elif` off of it). Dim overlay + centered bordered `Panel`,
`focus_mode = FOCUS_NONE`, non-dismissible (no close button, `_unhandled_input` swallows all keys
— mirrors `race_select.gd`'s conventions). Unlike the Mastery Picker's toggle-and-Done
multi-select, each card commits immediately on click (`subclass_select.gd`'s card-click-commits
style) since there's no multi-select within a round — but there ARE **two rounds**
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
false` and frees the overlay for good. See `scripts/entities/CLAUDE.md`'s "Wizard spellcasting"
section for what each pick actually grants.

## Spell-learn picker (`spell_learn_picker.gd`)
CanvasLayer, layer = 25. Wizard-only, spawned by `hud.gd._on_player_leveled_up()` whenever
`GameState.spell_learn_pending` is true (set by `GameState._roll_spell_learn_choices()` on every
Wizard level-up, not just even ones — see `scripts/entities/CLAUDE.md`'s "Wizard leveled
spells"). Modeled directly on `cantrip_select.gd`: dim overlay + centered bordered `Panel`,
non-dismissible (`_unhandled_input` swallows all keys, no close button), up to 3 cards
(`GameState.spell_learn_choices`) that commit immediately on click via `GameState.learn_spell(id)`
— no skip option, matches the owner's framing of this as a mandatory level-up choice. Card count
can be 1 or 2 instead of 3 when fewer eligible spells remain; the picker never spawns at all if
zero are eligible (a gray "No new spells available to learn." chat line fires instead) — expected
and common with only 4 example spells in `SpellDb.LEVELED_SPELL_IDS` (see
`docs/architecture/leveled-spells-and-slots-plan.md` §7's content-count caveat).

## Spellbook overlay (`spellbook_overlay.gd`)
CanvasLayer, layer = 25. Wizard-only, opened by pressing **R** (`player.gd._unhandled_input()`,
guarded the same way as every other blocking-overlay key — see the guard chains in
`scripts/entities/CLAUDE.md`'s "Player-specific" section), closed by R or Esc. Sets
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
hover-detail pattern as the Mastery Picker, not a `[url=]` tooltip). **Click** a tile → on a leveled
spell, `GameState.set_spell_prepared(id, bool)` toggles prepared, hard-blocked at
`SpellcasterState.prepared_max()` (clicking an unprepared spell at cap is a silent no-op, same feel
as the Mastery Picker's cap block); on a cantrip the click is a no-op (`_process()`'s click-toggle
branch checks `SpellDb.get_spell(id).level > 0` before calling `set_spell_prepared()`). **Bottom-
right counter**: `"X / Y prepared"` on a leveled-spell tab (identical `RichTextLabel`/color
convention to the Mastery Picker's `_counter_rtl` — gold under cap, gray at cap, red if ever over),
or a static `"Always ready"` on the Cantrips tab. Both `GameState.set_spell_prepared()` and
`place_spell_in_slot()` independently guard against ever adding a cantrip to `prepared_spells` —
see `scripts/autoloads/CLAUDE.md`.

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

## Mastery picker (`mastery_picker.gd`)
CanvasLayer, layer = 25. Modeled directly on the talent picker (dim overlay + centered bordered
`Panel`, `TextureButton` icon grid, `focus_mode = FOCUS_NONE` everywhere). Lets the player choose
which of `Stats.ALL_WEAPON_MASTERIES` (all 8: Cleave/Graze/Nick/Push/Sap/Slow/Topple/Vex) they
currently *know* — populates `Stats.known_weapon_masteries`, the array every weapon-mastery
combat effect already gates on (see `scripts/entities/CLAUDE.md`'s "Weapon mastery ownership").

Sets `GameState.mastery_picker_open = true` on open → blocks all player input (same treatment
as `talent_picker_open`, including the I-key inventory toggle and Tab bar-mode toggle — a
deliberate deviation from talent-picker parity, since this is a mandatory onboarding step).
4×2 icon grid (all 8 masteries, alphabetical, always shown regardless of class — only the
**cap** differs per class/level, `Stats.mastery_cap()`). Click toggles via
`GameState.toggle_mastery(name)`; hard-blocked at cap (icon dims, click ignored) by
`GameState.can_select_mastery()`. Counter shows "`known / cap`", gold normally, gray at cap,
red if ever over cap (never auto-trimmed — see design doc §7.3). No icon assets yet — icons
render blank (`res://icons/masteries/<name>.png`, none exist) until supplied; the bordered slot
frame keeps each button visible/clickable regardless.
**Selected vs. unselected contrast**: `_refresh()` dims every non-selected slot's `TextureButton.modulate` to `Color(0.55,0.55,0.55)` (selectable) or `Color(0.45,0.45,0.45,0.55)` (locked out at cap) so a known mastery's bright gold tint + thick 3px gold border (vs. the dimmed slots' 2px gray border) reads unambiguously at a glance — previously unselected slots rendered full white, which looked visually indistinguishable from "selected" at a glance.

**Wired to fire three ways**: right after class selection (`class_select.gd._on_class_selected()`),
again after any completed long rest if the player opts in — `player.gd` spawns
`mastery_reselect_prompt.gd` (a Yes/No confirm) right after `GameState.long_rest()` finishes;
choosing "Yes" spawns this picker fresh, letting the player fully re-pick from scratch (subject
to the same `mastery_cap()`) — and instantly on any level-up that raises `mastery_cap()` itself
(currently only Barbarian, at levels 4 and 10 — `Stats.mastery_cap()`). `GameState.gain_exp()`
snapshots `mastery_cap()` before applying the level-up and sets `mastery_learn_pending = true` if
it grew; `hud.gd._on_player_leveled_up()` spawns this picker right away when that flag is set
(same "instant pick" treatment as hit dice/spell slots growing on level-up — see root CLAUDE.md's
"Talent system"). Never triggered by short rest or floor descent.
