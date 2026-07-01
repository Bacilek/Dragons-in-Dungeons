# scripts/items

`item.gd` — data class for all items. All item instances are `Item` resources (no nodes).

## Maintenance rule
When adding fields to `Item` or new entries to `ITEM_POOL` / `WEAPON_POOL`, **immediately update this file, `debug_panel.ALL_ITEMS`, and root `CLAUDE.md`** — without waiting to be asked.

---

## Item.Type enum
```
WEAPON = 0
ARMOR  = 1
POTION = 2
SCROLL = 3
FOOD   = 4
GOLD   = 5
KEY    = 6
TOOL   = 7
```

## All fields
| Field | Type | Notes |
|---|---|---|
| `item_name` | String | display name |
| `item_type` | Type | enum above |
| `quantity` | int | stackable; `get_display_name()` appends `×N` when > 1 |
| `icon_path` | String | full `res://` path |
| `heal_amount` | int | potions / food |
| `bonus_damage` | int | weapon hit bonus |
| `bonus_ac` | int | armor AC bonus |
| `str_bonus` | int | ability score bonus |
| `is_ranged` | bool | if true → routes to `"ranged"` equipment slot |
| `range` | int | max range in tiles (ranged weapons only) |
| `consumes_on_ranged` | bool | decrement qty (and unequip at 0) on each ranged use |
| `damage_type` | String | "Slashing", "Piercing", "Bludgeoning", "" = unknown; shown in attack log |
| `heal_dice_count` | int | if > 0, use_item rolls N×d(heal_dice_sides)+CON instead of heal_amount |
| `heal_dice_sides` | int | die sides for dice-based healing (e.g. 4 for d4) |
| `damage_die_min/max` | int | weapon-specific damage dice; override base_min/max_damage when > 0 |
| `is_two_handed` | bool | cosmetic flag; shown as "Two-handed" in weapon tooltip |
| `is_heavy_armor` | bool | ends Barbarian Rage on equip |
| `is_heavy` | bool | Heavy weapon: attacking with STR < 13 imposes Disadvantage; shown as hoverable "Heavy" keyword in tooltip |
| `is_versatile` | bool | Versatile weapon; no weapon currently sets it. World Tree's Branching Strike keys off `is_heavy or is_versatile` for reach/push |

---

## Ranged weapons (current)
| Item | Bonus | Range | Stat | Infinite |
|---|---|---|---|---|
| Short Bow | +1 | 6 | DEX | yes |
| Crossbow | +3 | 8 | DEX | yes |
| Throwing Daggers | +0 | 4 | DEX | no (qty 3) |

`consumes_on_ranged = true` on Throwing Daggers → unequips when qty hits 0.

---

## Adding a new item
1. Add entry to `ITEM_POOL` (or `WEAPON_POOL`) in `dungeon_floor.gd`
2. **Mirror** in `debug_panel.ALL_ITEMS` with all relevant fields
3. If new `Item` fields introduced, update `_on_give_item()` in `debug_panel.gd`
4. Set `"src"` in the pool entry: `"weapons"` → `WEAPONS_PATH`, `"items"` → `ITEMS_PATH`, anything else → `OBJECTS_PATH`

## Sprite paths
```gdscript
WEAPONS_PATH = "res://sprites/weapons/"
ITEMS_PATH   = "res://sprites/items/"           # subfolders: Food/, Potions/, Misc/, etc.
OBJECTS_PATH = "res://sprites/objects/"
```
