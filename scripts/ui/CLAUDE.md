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

**ActionBar (bottom quickbar/ability bar) scale**: `scenes/ui/hud.tscn`'s `ActionBar` panel and its 9 `ItemSlotN` buttons + Wait/Search/Interact buttons are sized 1.5× the original layout (`ActionBar` height 90→135, slot size 76→114px, pitch 80→120px). Item/ability icons use `Button.icon` + `expand_icon = true` so they auto-scale with the button — no separate icon-size code to touch. The per-slot quantity badge (`_slot_qty_labels`) and ability use-count badge (`_slot_use_labels`) offsets/font sizes in `hud.gd` scale alongside (`-32/-18/11pt` → `-48/-27/16pt`). `_bar_mode_label` offsets are pinned to `ActionBar`'s new top (`-135`), not the old `-90`.

**Split-out modules** (pure refactor, same behavior — GDScript has no partial classes, so these use composition/static-helper patterns instead):
- `tooltip_formatters.gd` (`TooltipFormatters`, static-func-only helper) — the 8 combat tooltip formatters (`fmt_hit_tooltip`, `fmt_dmg_tooltip`, `fmt_heal_tooltip`, `fmt_save_tooltip`, `fmt_ehit_tooltip`, `fmt_edmg_tooltip`, `fmt_catk_tooltip`, `fmt_ret_tooltip`). Each takes only a `Dictionary` and returns a `String`. `hud.gd._format_tooltip()` still owns the `kind` dispatch match and calls into these.
- `crit_banner.gd` (`CritBanner`, composition child-node, `extends Node`) — `show_banner(text, color)` (was `hud.gd._show_crit_banner`). Instantiated once in `hud.gd._ready()` (`_crit_banner`), added as a child, and `GameState.crit_banner` connects directly to `_crit_banner.show_banner`.
- `compass.gd` (`Compass`, composition child-node, `extends Panel`) — owns the top-center stairs compass UI and its `_stairs_found_this_floor` state internally. Public methods: `on_stairs_discovered()`, `update_display()`, `reset_for_new_floor()`. Instantiated once in `hud.gd._ready()` (`_compass`); `GameState.stairs_discovered` connects to `on_stairs_discovered`, `TurnManager.player_turn_started` connects to `update_display`, and `hud.gd._on_floor_changed()` calls `reset_for_new_floor()`.

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
Pixel Dungeon style: tier header with star bar (gray=spent / yellow=available / dark=locked) + icon row with dot rank indicators + bottom detail panel showing all rank descriptions + "Upgrade Talent ▲" button.
**Sizing**: `PANEL_W = 720.0`, `ICON_SIZE = 64.0` (bumped up from the original 500/48 for legibility — panel height auto-computed from content and re-centered on the 1920×1080 viewport in `_build_ui()`). All other offsets/paddings/font sizes in the file scale off these two constants or are hand-tuned alongside them; if you change either constant, re-check the hardcoded subclass-arrow positions in `_build_tier_section()` (only rendered in God Mode) since those aren't formula-driven.
**Subclass arrows** (Tier 2 header only, visible in God Mode): ◀ `active_tier2_subclass` ▶ arrows call `GameState.debug_switch_subclass(±1)` then close+reopen the picker. Berserker, Wild Heart, World Tree, and Zealot are all implemented.

**Rank-gradient talent icons**: `_add_talent_icon()` no longer sets a texture at creation time — `_refresh()` (called on build and after every upgrade) loads `GameState.talent_icon_path(t.talent_id, max(rank,1))` into `btn.texture_normal` each time, so the icon art changes as the player invests ranks (falls back to `t.icon_path` if unmapped). Icons dim to alpha 0.5 while unranked.

## Short rest panel (`short_rest_panel.gd`)
CanvasLayer, layer = 25. Spawned by `PlayerActions.open_short_rest()` (`scripts/entities/player_actions.gd`).

Keyboard bindings: ←/A/KP4 = minus dice, →/D/KP6 = plus dice, **Space = rest**, Esc = close.
On Rest: rolls `_dice_to_spend × hit_die_sides() + CON mod` (min 1 per die), heals player, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`.
Sets `GameState.short_rest_open = true` on open → blocks all player input until closed.
**Important ordering in `_on_rest()`**: `GameState.short_rest_open = false` and `queue_free()` must be called **before** emitting `player_action_requested("short_rest_begin")` because the signal is synchronous — `_on_turn_started` fires inside the chain and checks `short_rest_open`.

---

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: **God Mode** (checkbox — activates invincible + noclip + see_all + exposes enemy rolls/HP in chat log), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel listing all `DungeonFloorData.ENEMY_POOL` + `BOSS_POOL`, spawns adjacent to player via `dungeon_floor.debug_spawn_enemy()`), **Level Up** (`GameState.debug_level_up()`), See All.

DungeonFloor registers itself in group `"dungeon_floor"` in `_ready()` so the debug panel can locate it via `get_tree().get_first_node_in_group("dungeon_floor")`. Pool data (`ENEMY_POOL`/`BOSS_POOL`/`ITEM_POOL`) is read directly off `DungeonFloorData` (`scripts/world/dungeon_floor_data.gd`, global via `class_name`) — no `load()` of `dungeon_floor.gd` needed.

**Item sync rule**: any new entry in `DungeonFloorData.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
**Scale**: `SLOT_SIZE = 90`, `SLOT_GAP = 6` (`STEP = 96`), `PANEL_W = 1020`, `PANEL_H = 690` — 1.5× the original 60/4/820/460 values (bumped for legibility; keep the whole overlay's fonts/paddings/offsets scaling off these two constants if you touch them again).
Equipment slot labels: **Main Hand** (key `"melee"`) / **Off-hand** (key `"hand2"`) / **Ranged** (key `"ranged"`) in `GameState.equipment`.
**Equipment grid layout** (`_build_equipment_section()`, positions relative to `EQUIPMENT_ORIGIN`): Headgear top-center (above Armor), Ranged top-right (centered above the gap between Main Hand and Off-hand), middle row is Gloves / Armor / Main Hand / Off-hand left→right, Boots bottom-center (below Armor). `"trinket"` still exists as a dead key in `GameState.equipment` but is not rendered in this grid (unrequested/unused).
Slot type enforced via `_fits_slot()`: Main Hand (`"melee"`) rejects ranged items and vice versa; `"hand2"` (Off-hand) accepts any non-weapon item, or a melee weapon with `Item.is_light == true` (e.g. future Light weapons — nothing currently sets it) — rejects non-Light weapons and ranged weapons. `equip()` always routes non-ranged weapons to `"melee"` regardless of how they're equipped (pickup, starting gear, debug give-item, or explicit equip) — Off-hand is never auto-populated, only reachable via explicit drag. Still not wired into combat — see `scripts/items/CLAUDE.md`'s "Equipment slots".
**Two-handed cross indicator**: each `"hand2"` slot gets a hidden `BlockedMark` Label (red "✕", built in `_make_slot()`) toggled in `_refresh()` — visible whenever `GameState.equipment.get("melee")` is non-null and `Item.is_two_handed`, signalling the off-hand is unusable while a two-handed weapon is equipped. Purely visual; `is_two_handed` still doesn't block anything else (e.g. the ranged slot) — see root `CLAUDE.md`.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

**Ctrl-freeze tooltip**: pressing Ctrl while hovering an item (tooltip visible) freezes the tooltip in place and switches `_inv_tooltip.mouse_filter = MOUSE_FILTER_STOP` + `_inv_tooltip_rtl.mouse_filter = MOUSE_FILTER_PASS`. This allows `meta_hover_started` to fire for `[url=keyword:X]` links (e.g. "Heavy"), showing the glossary popup. Ctrl again or closing inventory unfreezes. `_unfreeze_tooltip()` helper restores MOUSE_FILTER_IGNORE on both AND hides the tooltip. `_on_slot_hover()` returns early when `_tooltip_frozen` so moving mouse to other slots does not overwrite the frozen tooltip. Same Ctrl-freeze feature also implemented for the qbar tooltip in `hud.gd` (`_qbar_tooltip_frozen`, `_unfreeze_qbar_tooltip()`, `_input()` handler). All item tooltips show a small gray "Ctrl: inspect" hint in the bottom-right corner.

---

## Class select (`class_select.gd`)
Shown at game start. Emits `GameState.class_chosen` when player selects a class.
