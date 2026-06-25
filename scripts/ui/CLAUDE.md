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

## Short rest panel (`short_rest_panel.gd`)
CanvasLayer, layer = 25. Spawned by `player.gd._open_short_rest()`.

Keyboard bindings: ←/A/KP4 = minus dice, →/D/KP6 = plus dice, Enter = rest, Esc = close.
On Rest: rolls `_dice_to_spend × hit_die_sides() + CON mod` (min 1 per die), heals player, decrements `GameState.hit_dice` and `GameState.short_rests_remaining`.
Sets `GameState.short_rest_open = true` on open → blocks all player input until closed.

---

## Debug panel (`debug_panel.gd`)
F3 toggle. CanvasLayer, layer = 25.
Features: Invincible, Noclip, Jump to Floor, Give Item, See All.

**Item sync rule**: any new entry in `dungeon_floor.ITEM_POOL` must also appear in `debug_panel.ALL_ITEMS` with all relevant fields mirrored (`is_ranged`, `range`, `consumes_on_ranged`, `qty`, etc.).
If new `Item` fields are added, also update `_on_give_item()` in this file.

---

## Inventory overlay (`inventory_overlay.gd`)
Equipment slot labels: **Melee** / **Ranged** (keys `"melee"` / `"ranged"` in `GameState.equipment`).
Slot type enforced: melee slot rejects ranged items and vice versa.
Quickbar: 9 slots (indices 0–8). Bag: 24 slots.

---

## Class select (`class_select.gd`)
Shown at game start. Emits `GameState.class_chosen` when player selects a class.
