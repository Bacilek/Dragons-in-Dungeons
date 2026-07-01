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

---

## HUD (`hud.gd`)
Connects to `GameState` signals only — never poll `GameState` in `_process()`.

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
Hidden at floor start. Appears at **top-center** of screen only when stairs tile enters FOV (`_on_stairs_discovered()` sets `_stairs_found_this_floor = true` and shows panel). Resets (hides) on every floor change.
`_update_compass()` early-returns until flag is true. Arrow character picked from 8 Unicode directions; shows Chebyshev distance.
Triggered by `GameState.stairs_discovered` signal (emitted by `DungeonFloor.update_fog()` or See All debug).

---

## Talent picker (`talent_picker.gd`)
CanvasLayer, layer = 25. Opened by `player.gd._open_talent_picker()` via **T key** (bypasses phase gate). Does NOT auto-open on level-up.
Sets `GameState.talent_picker_open = true` → blocks all player keyboard input. Esc or T closes.
Pixel Dungeon style: tier header with star bar (gray=spent / yellow=available / dark=locked) + icon row with dot rank indicators + bottom detail panel showing all rank descriptions + "Upgrade Talent ▲" button.
**Sizing**: `PANEL_W = 720.0`, `ICON_SIZE = 64.0` (bumped up from the original 500/48 for legibility — panel height auto-computed from content and re-centered on the 1920×1080 viewport in `_build_ui()`). All other offsets/paddings/font sizes in the file scale off these two constants or are hand-tuned alongside them; if you change either constant, re-check the hardcoded subclass-arrow positions in `_build_tier_section()` (only rendered in God Mode) since those aren't formula-driven.
**Subclass arrows** (Tier 2 header only, visible in God Mode): ◀ `active_tier2_subclass` ▶ arrows call `GameState.debug_switch_subclass(±1)` then close+reopen the picker. Berserker, Wild Heart, World Tree, and Zealot are all implemented.

**Rank-gradient talent icons**: `_add_talent_icon()` no longer sets a texture at creation time — `_refresh()` (called on build and after every upgrade) loads `GameState.talent_icon_path(t.talent_id, max(rank,1))` into `btn.texture_normal` each time, so the icon art changes as the player invests ranks (falls back to `t.icon_path` if unmapped). Icons dim to alpha 0.5 while unranked.

## Short rest panel (`short_rest_panel.gd`)
CanvasLayer, layer = 25. Spawned by `player.gd._open_short_rest()`.

Keyboard bindings: ←/A/KP4 = minus dice, →/D/KP6 = plus dice, **Space = rest**, Esc = close.
On Rest: rolls `_dice_to_spend × hit_die_sides() + CON mod` (min 1 per die), heals player, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`.
Sets `GameState.short_rest_open = true` on open → blocks all player input until closed.
**Important ordering in `_on_rest()`**: `GameState.short_rest_open = false` and `queue_free()` must be called **before** emitting `player_action_requested("short_rest_begin")` because the signal is synchronous — `_on_turn_started` fires inside the chain and checks `short_rest_open`.

---

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: **God Mode** (checkbox — activates invincible + noclip + see_all + exposes enemy rolls/HP in chat log), Invincible, Noclip, Jump to Floor, Give Item, **Spawn Enemy** (sub-panel listing all ENEMY_POOL + BOSS_POOL, spawns adjacent to player via `dungeon_floor.debug_spawn_enemy()`), **Level Up** (`GameState.debug_level_up()`), See All.

DungeonFloor registers itself in group `"dungeon_floor"` in `_ready()` so the debug panel can locate it via `get_tree().get_first_node_in_group("dungeon_floor")`.

**Item sync rule**: any new entry in `dungeon_floor.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, `two_handed`, `heavy_armor`, `die_min`, `die_max`, `dmg_type`, `heal_dice`, `heal_sides`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
Equipment slot labels: **Melee** / **Ranged** (keys `"melee"` / `"ranged"` in `GameState.equipment`).
Slot type enforced: melee slot rejects ranged items and vice versa.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

**Ctrl-freeze tooltip**: pressing Ctrl while hovering an item (tooltip visible) freezes the tooltip in place and switches `_inv_tooltip.mouse_filter = MOUSE_FILTER_STOP` + `_inv_tooltip_rtl.mouse_filter = MOUSE_FILTER_PASS`. This allows `meta_hover_started` to fire for `[url=keyword:X]` links (e.g. "Heavy"), showing the glossary popup. Ctrl again or closing inventory unfreezes. `_unfreeze_tooltip()` helper restores MOUSE_FILTER_IGNORE on both AND hides the tooltip. `_on_slot_hover()` returns early when `_tooltip_frozen` so moving mouse to other slots does not overwrite the frozen tooltip. Same Ctrl-freeze feature also implemented for the qbar tooltip in `hud.gd` (`_qbar_tooltip_frozen`, `_unfreeze_qbar_tooltip()`, `_input()` handler). All item tooltips show a small gray "Ctrl: inspect" hint in the bottom-right corner.

---

## Class select (`class_select.gd`)
Shown at game start. Emits `GameState.class_chosen` when player selects a class.
