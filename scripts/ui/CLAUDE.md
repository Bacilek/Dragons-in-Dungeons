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

**Split-out modules** (pure refactor, same behavior — GDScript has no partial classes, so these use composition/static-helper patterns instead):
- `tooltip_formatters.gd` (`TooltipFormatters`, static-func-only helper) — the 8 combat tooltip formatters (`fmt_hit_tooltip`, `fmt_dmg_tooltip`, `fmt_heal_tooltip`, `fmt_save_tooltip`, `fmt_ehit_tooltip`, `fmt_edmg_tooltip`, `fmt_catk_tooltip`, `fmt_ret_tooltip`). Each takes only a `Dictionary` and returns a `String`. `hud.gd._format_tooltip()` still owns the `kind` dispatch match and calls into these.
- `crit_banner.gd` (`CritBanner`, composition child-node, `extends Node`) — `show_banner(text, color)` (was `hud.gd._show_crit_banner`). Instantiated once in `hud.gd._ready()` (`_crit_banner`), added as a child, and `GameState.crit_banner` connects directly to `_crit_banner.show_banner`.
- `compass.gd` (`Compass`, composition child-node, `extends Panel`) — owns the top-center stairs compass UI and its `_stairs_found_this_floor` state internally. Public methods: `on_stairs_discovered()`, `update_display()`, `reset_for_new_floor()`. Instantiated once in `hud.gd._ready()` (`_compass`); `GameState.stairs_discovered` connects to `on_stairs_discovered`, `TurnManager.player_turn_started` connects to `update_display`, and `hud.gd._on_floor_changed()` calls `reset_for_new_floor()`.
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
(`GameState.psycho_adv_pending`, Psycho's identical pending-Advantage window). Both pending-ADV
flags live on `GameState` (not on `PlayerBaseTalents`, where they used to live) specifically so
this tray can read them without a live `Player` node reference — matches "HUD only reads
GameState" above. No `icons/status/` art exists yet — every entry currently renders as a tinted
placeholder square until real icons are supplied (`unarmored_defense`/`tactician`/`psycho_adv`
already reuse existing talent icons, so those three render properly today). Open questions
resolved: hover-only tooltip, shared tooltip panel, grow-panel layout.

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

## Mastery reselect prompt (`mastery_reselect_prompt.gd`)
CanvasLayer, layer = 26. Spawned by `player.gd` right after `GameState.long_rest()` completes — a simple Yes/No confirm ("Change your weapon masteries?"). Sets `GameState.mastery_picker_open = true` for its own duration (blocking input like the picker itself); "Yes" hands off to `mastery_picker.gd` (which keeps the flag set via its own `_ready()`), "No" clears the flag. Never shown after a short rest, only a completed long rest.

---

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: **God Mode** (checkbox — activates invincible + noclip + see_all + exposes enemy rolls/HP in chat log), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel listing all `DungeonFloorData.ENEMY_POOL` + `BOSS_POOL`, spawns adjacent to player via `dungeon_floor.debug_spawn_enemy()`), **Level Up** (`GameState.debug_level_up()`), **Give 100 Gold** (`GameState.add_gold(100)`), See All, **Mute** (bottom of the main panel, below Give 100 Gold — calls `AudioManager.toggle_mute()`, label swaps 🔊/🔇 in sync with `AudioManager.mute_changed`, same signal the HUD's own top-right `MuteButton` listens to; added as a more-discoverable second entry point since that corner button is easy to miss).

DungeonFloor registers itself in group `"dungeon_floor"` in `_ready()` so the debug panel can locate it via `get_tree().get_first_node_in_group("dungeon_floor")`. Pool data (`ENEMY_POOL`/`BOSS_POOL`/`ITEM_POOL`) is read directly off `DungeonFloorData` (`scripts/world/dungeon_floor_data.gd`, global via `class_name`) — no `load()` of `dungeon_floor.gd` needed.

**Item sync rule**: any new entry in `DungeonFloorData.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
**Scale**: `SLOT_SIZE = 90`, `SLOT_GAP = 6` (`STEP = 96`), `PANEL_W = 1020`, `PANEL_H = 690` — 1.5× the original 60/4/820/460 values (bumped for legibility; keep the whole overlay's fonts/paddings/offsets scaling off these two constants if you touch them again).
Equipment slot labels: **Main Hand** (key `"melee"`) / **Off-hand** (key `"hand2"`) / **Ranged** (key `"ranged"`) in `GameState.equipment`.
**Equipment grid layout** (`_build_equipment_section()`, positions relative to `EQUIPMENT_ORIGIN`): Headgear top-center (above Armor), Ranged top-right (centered above the gap between Main Hand and Off-hand), middle row is Gloves / Armor / Main Hand / Off-hand left→right, Boots bottom-center (below Armor). `"trinket"` still exists as a dead key in `GameState.equipment` but is not rendered in this grid (unrequested/unused).
Slot type enforced via `_fits_slot()`: Main Hand (`"melee"`) rejects ranged items and vice versa; `"hand2"` (Off-hand) accepts any non-weapon item, or a Light melee weapon (e.g. the Handaxe) — but only when Main Hand is *also* currently Light — rejecting non-Light weapons, ranged weapons, and a Light weapon whenever Main Hand isn't Light. `equip()` always routes non-ranged weapons to `"melee"` regardless of how they're equipped (pickup, starting gear, debug give-item, or explicit equip) — Off-hand is never auto-populated, only reachable via explicit drag. Dual-wielding two Light weapons now fires a real bonus Off-hand attack — see `scripts/items/CLAUDE.md`'s "Dual-wielding".
**Two-handed cross indicator**: each `"hand2"` slot gets a hidden `BlockedMark` Label (red "✕", built in `_make_slot()`) toggled in `_refresh()` — visible whenever `GameState.equipment.get("melee")` is non-null and `Item.is_two_handed`, signalling the off-hand is unusable while a two-handed weapon is equipped. Purely visual; `is_two_handed` still doesn't block anything else (e.g. the ranged slot) — see root `CLAUDE.md`.

**Versatile grip toggle**: clicking the Main Hand slot without dragging (press+release inside the same slot, detected in `_finish_drag()` when `dest == null` but the release point is still inside `_drag_src_ctrl`) calls `GameState.toggle_versatile_grip()` if the equipped item's `is_versatile == true` (currently Quarterstaff and Spear — see `scripts/items/CLAUDE.md`'s "Versatile weapons"). `_refresh()` gives the Main Hand slot's `StyleBoxFlat` a gold border + thicker width while gripped two-handed (`main_hand.is_versatile and main_hand.is_two_handed`), gray/thin otherwise.

**Thrown weapon durability**: item tooltips (both here and `hud.gd`'s quickbar tooltip) show a right-aligned `Uses: X/Y` line for any `Item.Type.WEAPON` with `is_thrown == true` (currently only the Spear — see `scripts/items/CLAUDE.md`'s "Thrown weapons"), placed just above the existing "Ctrl: inspect" hint.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

**Ctrl-freeze tooltip**: pressing Ctrl while hovering an item (tooltip visible) freezes the tooltip in place and switches `_inv_tooltip.mouse_filter = MOUSE_FILTER_STOP` + `_inv_tooltip_rtl.mouse_filter = MOUSE_FILTER_PASS`. This allows `meta_hover_started` to fire for `[url=keyword:X]` links (e.g. "Heavy"), showing the glossary popup. Ctrl again or closing inventory unfreezes. `_unfreeze_tooltip()` helper restores MOUSE_FILTER_IGNORE on both AND hides the tooltip. `_on_slot_hover()` returns early when `_tooltip_frozen` so moving mouse to other slots does not overwrite the frozen tooltip. Same Ctrl-freeze feature also implemented for the qbar tooltip in `hud.gd` (`_qbar_tooltip_frozen`, `_unfreeze_qbar_tooltip()`, `_input()` handler). All item tooltips show a small gray "Ctrl: inspect" hint in the bottom-right corner.

---

## Character select (`character_select.gd`)
CanvasLayer, layer = 20. **The actual first screen of a new run** — `hud.gd._ready()` now spawns
this instead of `class_select.gd` directly. Shows 5 cards side by side: 4 premade characters
(`PREMADE` const — Garrem Ogar/Orc Barbarian/Cleave+Graze, Tish/Wood Elf Ranger/Slow+Nick, Grok
the White/White Dragonborn Monk, Jace/Halfling Wizard) plus a 5th "Custom" card. Clicking a
premade card (`_on_premade_selected()`) applies class + `GameState.give_class_starting_items()` +
`GameState.choose_race(race, variant, prof_ability)` + (for Barbarian/Ranger) directly populates
`Stats.known_weapon_masteries` and emits `known_masteries_changed` — bypassing class_select/
point_buy_select/race_select/mastery_picker entirely and dropping straight into the already-loaded
floor 1 (premade heroes use `apply_class_defaults()`'s fixed scores, no point buy). Clicking
"Custom" (`_on_custom_selected()`) spawns `class_select.gd` unchanged, preserving the full
**class select → point buy → race select → mastery picker** chain for a from-scratch build. Also
owns the "Continue Saved Run" button (moved here from `class_select.gd` since this is now the true
entry point) — same behavior as before, see `scripts/autoloads/CLAUDE.md`'s SaveManager
"Continue flow" section.

## Class select (`class_select.gd`)
The **Custom** path only now (see `character_select.gd` above) — no longer spawned directly by
`hud.gd`. Emits `GameState.class_chosen` when player selects a class, then spawns
`point_buy_select.gd` (below) and `queue_free()`s itself — point buy owns spawning race select,
which in turn owns spawning the Mastery Picker, not this script. No longer has its own
Continue-Saved-Run button (that moved to `character_select.gd`, the actual entry point).

## Point buy select (`point_buy_select.gd`)
CanvasLayer, layer = 22. One-time, mandatory ability-score allocation spawned by
`class_select.gd._on_class_selected()` right after `class_chosen` fires, **before** race select
— Custom character-creation path only (premade heroes never reach it). D&D 2024 rules: no race
grants a raw ability-score bonus (`Stats.apply_race_defaults()` never touches base scores), so
this is the only ability-score input point in onboarding, and running it before race select is
safe regardless of ordering. Modeled on `race_select.gd`'s conventions (dim overlay + centered
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
spawns `race_select.gd` itself before `queue_free()`.

## Race select (`race_select.gd`)
CanvasLayer, layer = 25. One-time, mandatory choice spawned by `point_buy_select.gd._on_confirm()`
(Custom path) — see "Point buy select" above. Modeled directly on
`subclass_select.gd`'s conventions (dim overlay + centered bordered `Panel`, `focus_mode =
FOCUS_NONE` everywhere, `race_picker_open` input-gate flag, non-dismissible — no close button,
`_unhandled_input` swallows Esc/keys). 6 race cards (Orc/Human/Halfling/Dwarf/Elf/Dragonborn);
Human/Elf/Dragonborn additionally show an inline sub-choice row (ability-score proficiency /
sub-race / ancestry) that must be picked before Confirm enables. Confirm calls
`GameState.choose_race(race, variant, prof_ability)`, then spawns `mastery_picker.gd` itself
(same `mastery_cap() > 0` gate class_select used to apply) before `queue_free()` — so the full
onboarding order for the Custom path is **class select → point buy → race select → mastery
picker**. The Continue-saved-run flow (`character_select.gd._on_continue_pressed()`) skips all
four; ability scores and race are both restored via `Stats.to_dict()`/`from_dict()`
(`character_race`/`race_variant`/`race_prof_ability` plus the plain score ints) same as any other
stat.

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

**Wired to fire twice**: right after class selection (`class_select.gd._on_class_selected()`),
and again after any completed long rest if the player opts in — `player.gd` spawns
`mastery_reselect_prompt.gd` (a Yes/No confirm) right after `GameState.long_rest()` finishes;
choosing "Yes" spawns this picker fresh, letting the player fully re-pick from scratch (subject
to the same `mastery_cap()`). Never triggered by short rest or floor descent.
