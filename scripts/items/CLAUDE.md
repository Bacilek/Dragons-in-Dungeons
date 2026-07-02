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
| `is_heavy` | bool | Heavy weapon: melee attack with STR < 13, or ranged attack with DEX < 13, imposes Disadvantage; shown as hoverable "Heavy" keyword in tooltip |
| `is_versatile` | bool | Versatile weapon; no weapon currently sets it. World Tree's Branching Strike keys off `is_heavy or is_versatile` for reach/push |
| `weapon_mastery` | String | One signature effect per weapon (e.g. "Cleave"); `""` = none. Shown as `(Mastery)` next to the item name in tooltips, hoverable via the same keyword-glossary popup (lowercased mastery name as the key) |
| `weapon_category` | String | "Simple", "Martial", or `""` = n/a. Gates whether `Stats.proficient_simple_weapons`/`proficient_martial_weapons` grants the proficiency bonus on the attack roll (`player.gd._weapon_prof_bonus()`); shown right under the damage line in tooltips, red when the class lacks that proficiency |

## Damage type categories (documentation only — no enum)
- **Physical**: Slashing, Piercing, Bludgeoning
- **Elemental**: Fire, Cold, Acid, Poison, Thunder, Lightning
- **Magical**: Force, Necrotic, Psychic, Radiant

`Item.damage_type` is a free-form String set to one of the above (or `""` = unknown). No code currently branches on the category (Physical/Elemental/Magical) itself — only Rage's `take_damage_raw()` special-cases the three Physical type strings by name. Introduce a real category grouping only if a second consumer needs it.

## Weapon masteries
`Item.weapon_mastery` names one signature effect per weapon. Currently implemented:
- **Cleave** (Greataxe): on any melee attack (hit or miss), if 2+ distinct visible enemies are within melee reach (`1 + player._melee_reach_bonus()` tiles, Chebyshev), the swing also rolls a fully independent attack + damage roll against the enemy closest to the primary target. Implemented in `player.gd._try_cleave()` / `_resolve_cleave_attack()`, called from both the hit and miss paths of `_bump_attack()` (not ranged attacks — melee-only). Does **not** re-trigger per-turn-once bonuses (Frenzy/Ironwood Bark/Divine Fury) since those flags are already consumed by the primary attack that turn; the cleave hit is logged as its own separate `[color=cyan]Cleave:[/color]` chat line with its own `hit`/`dmg` tooltip metadata (not folded into the primary attack's numbers — this is a second swing, not a bonus source on the same swing, so the "damage stacking" rule in `scripts/entities/CLAUDE.md` doesn't apply here).
- New masteries: add the glossary text to `KEYWORD_GLOSSARY` in both `hud.gd` and `inventory_overlay.gd` (key = mastery name lowercased) and implement the effect wherever it naturally hooks into combat (see Cleave for the melee-attack pattern).

---

## Ranged weapons (current)
| Item | Bonus | Range | Stat | Infinite | Category |
|---|---|---|---|---|---|
| Short Bow | +1 | 6 | DEX | yes | Simple |
| Crossbow | +3 | 8 | DEX | yes | Martial |

## Weapons (current, game-wide)
The only weapons in the game are the Barbarian's starting **Greataxe** (melee, two-handed, given via `GameState._give_barbarian_starting_items()` — never spawns as floor loot) plus **Short Bow** and **Crossbow** above. All physical melee weapons that used to spawn as floor loot (Rusty/Short/Regular/Knight/Golden/Lavish Sword) and **Throwing Daggers** have been removed from `DungeonFloorData.ITEM_POOL`, `debug_panel.ALL_ITEMS`, and boss loot (`dungeon_floor.gd drop_boss_loot()`, now potions-only). Their sprite assets under `res://sprites/weapons/` are untouched (unused, not deleted) in case they're reintroduced later.

---

## Adding a new item
1. Add entry to `DungeonFloorData.ITEM_POOL` (or `WEAPON_POOL`) in `scripts/world/dungeon_floor_data.gd`
2. **Mirror** in `debug_panel.ALL_ITEMS` with all relevant fields
3. If new `Item` fields introduced, update `_on_give_item()` in `debug_panel.gd`
4. Set `"src"` in the pool entry: `"weapons"` → `WEAPONS_PATH`, `"items"` → `ITEMS_PATH`, anything else → `OBJECTS_PATH`

## Sprite paths
```gdscript
DungeonFloorData.WEAPONS_PATH = "res://sprites/weapons/"
DungeonFloorData.ITEMS_PATH   = "res://sprites/items/"           # subfolders: Food/, Potions/, Misc/, etc.
DungeonFloorData.OBJECTS_PATH = "res://sprites/objects/"
```
(`debug_panel.gd` keeps its own local `WEAPONS_PATH`/`ITEMS_PATH` constants — unrelated duplicates used only for its Give Item icon lookups, not part of this refactor.)
