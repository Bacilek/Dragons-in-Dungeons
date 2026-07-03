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
| `is_finesse` | bool | Finesse weapon: attack roll and damage roll use `max(STR mod, DEX mod)` instead of always STR — `CombatMath.finesse_modifier()`, applied in `player.gd._bump_attack()`. Shown as hoverable "Finesse" keyword in tooltips |
| `is_light` | bool | Light weapon: the only kind of weapon (besides non-weapon items) allowed in the Off-hand (`"hand2"`) equipment slot — `inventory_overlay.gd._fits_slot()`. Shown as hoverable "Light" keyword in tooltips. No weapon currently equips a second attack from the Off-hand — see "Equipment slots" below |
| `weapon_mastery` | String | One signature effect per weapon (e.g. "Cleave"); `""` = none. Shown as `(Mastery)` next to the item name in tooltips, hoverable via the same keyword-glossary popup (lowercased mastery name as the key) |
| `weapon_category` | String | "Simple", "Martial", or `""` = n/a. Gates whether `Stats.proficient_simple_weapons`/`proficient_martial_weapons` grants the proficiency bonus on the attack roll (`CombatMath.weapon_prof_bonus()` in `scripts/entities/combat_math.gd`); shown right under the damage line in tooltips, red when the class lacks that proficiency |
| `ammo_item_name` | String | Name of the Item this ranged weapon consumes per shot (e.g. `"Arrow"`); `""` = no named ammo (falls back to `consumes_on_ranged` on the weapon's own stack, or infinite). See "Ammo items" below |

## Damage type categories (documentation only — no enum)
- **Physical**: Slashing, Piercing, Bludgeoning
- **Elemental**: Fire, Cold, Acid, Poison, Thunder, Lightning
- **Magical**: Force, Necrotic, Psychic, Radiant

`Item.damage_type` is a free-form String set to one of the above (or `""` = unknown). No code currently branches on the category (Physical/Elemental/Magical) itself — only Rage's `take_damage_raw()` special-cases the three Physical type strings by name. Introduce a real category grouping only if a second consumer needs it.

## Weapon masteries
`Item.weapon_mastery` names one signature effect per weapon, but it only fires if the wielder actually **knows** that mastery — gated by `Stats.knows_mastery(name) -> bool` (checks `Stats.known_weapon_masteries: Array[String]`, `scripts/entities/stats.gd`). Nothing currently grants entries to this array — no class/talent has been wired up yet — so equipping a mastery weapon has **no** mastery effect for anyone right now; treat this as intentional until a future talent/class explicitly populates it. Gated at `player.gd._try_cleave()` (Cleave) and `PlayerRanged.ranged_attack()`'s Vex-set line (`scripts/entities/player_ranged.gd`) — both check `weapon.weapon_mastery == "X" and stats.knows_mastery("X")` before applying the effect. Currently implemented:
- **Cleave** (Greataxe): on any melee attack (hit or miss), if 2+ distinct visible enemies are within melee reach (`1 + CombatMath.melee_reach_bonus(rank)` tiles, Chebyshev), the swing also rolls a fully independent attack + damage roll against the enemy closest to the primary target. Implemented in `player.gd._try_cleave()` / `_resolve_cleave_attack()`, called from both the hit and miss paths of `_bump_attack()` (not ranged attacks — melee-only). Does **not** re-trigger per-turn-once bonuses (Frenzy/Ironwood Bark/Divine Fury) since those flags are already consumed by the primary attack that turn; the cleave hit is logged as its own separate `[color=cyan]Cleave:[/color]` chat line with its own `hit`/`dmg` tooltip metadata (not folded into the primary attack's numbers — this is a second swing, not a bonus source on the same swing, so the "damage stacking" rule in `scripts/entities/CLAUDE.md` doesn't apply here).
- **Vex** (Short Bow, Rapier): after a Vex-mastery hit (any hit, including crits — not on a miss), the attacker gains Advantage on their very next attack THIS ROUND against that exact same enemy — any attack type (melee, cleave, ranged), consumed on the next attack attempt regardless of hit/miss. Implemented as `player.gd._vex_adv_target: Enemy`, set both in `player.gd._bump_attack()`'s melee hit branch (Rapier) and `PlayerRanged.ranged_attack()`'s hit branch (Short Bow), checked/consumed as an ADV source in `_bump_attack()`, `_resolve_cleave_attack()`, and `PlayerRanged.ranged_attack()`. Cleared in `_on_turn_started()`'s `if not came_from_revert:` reset block, so it survives a `revert_to_waiting()` free-action chain (e.g. Rager) within the same round but clears at a real new round — see `_reverted_this_round` in `scripts/entities/CLAUDE.md`.
- **Push** (Heavy Crossbow): on a ranged hit that doesn't kill the target, the enemy rolls `Enemy.resist_check(dc, true)` (CON-based) vs `dc = 8 + prof + DEX mod` — same DC convention as World Tree's Grip of the Forest/Branching Strike (see `scripts/entities/CLAUDE.md`). On a failed save the target is shoved exactly 1 tile directly away from the player via `DungeonFloor.resolve_push(enemy, direction)` (`scripts/world/dungeon_floor.gd`) — a dedicated resolver, **not** `force_move_entity()`, because it needs non-generic per-tile outcomes: WALL → 1d4 Bludgeoning damage, no movement; a trap tile → moves the enemy there and calls `trigger_trap()`; CHASM → the enemy is removed entirely (counts as a kill for exp), and if it was a boss its rolled loot item is appended to `GameState.pending_chasm_items` to appear on the next floor down (see "Ammo items" chasm handling below — same drain mechanism, reused as-is). Implemented in `PlayerRanged.ranged_attack()` (`scripts/entities/player_ranged.gd`), gated the same `weapon.weapon_mastery == "Push" and stats.knows_mastery("Push")` way as Cleave/Vex — currently dormant for the same reason (nothing grants `known_weapon_masteries` entries yet).
- New masteries: add the glossary text to `KEYWORD_GLOSSARY` in both `hud.gd` and `inventory_overlay.gd` (key = mastery name lowercased) and implement the effect wherever it naturally hooks into combat (see Cleave for the melee-attack pattern, Vex for the per-turn-flag pattern, Push for the forced-movement pattern).

---

## Ranged weapons (current)
Every ranged weapon has just one range value — `Item.range`, the "normal" range at full accuracy. **Long range is NOT a per-weapon field**: every ranged weapon can additionally fire anywhere within the player's live FOV (`DungeonFloor.FOV_RADIUS`, gated by actual `is_tile_visible()` — not just distance, so shots around corners don't count), but a shot beyond `range` rolls with Disadvantage. See `PlayerRanged.is_ranged_target_in_range()` / `ranged_shot_disadvantage()` (`scripts/entities/player_ranged.gd`).

| Item | Bonus | Normal range | Ammo | Stat | Category | Mastery |
|---|---|---|---|---|---|---|
| Short Bow | +0 | 4 | Arrow | DEX | Simple | Vex |
| Heavy Crossbow | +0 | 4 | Bolt | DEX | Martial | Push |

Heavy Crossbow is also `is_heavy=true` (DEX 13+ or Disadvantage) and `is_two_handed=true` (cosmetic for a ranged weapon — see root `CLAUDE.md`'s note that `is_two_handed` doesn't block the ranged slot).

## Ammo items
`Item.ammo_item_name` on a ranged weapon names a separate stackable `Item` (`Item.Type.TOOL`, no combat stats of its own — currently **Arrow** for the Short Bow and **Bolt** for the Heavy Crossbow, both reusing `weapon_arrow.png` since no dedicated bolt sprite exists yet) consumed 1-per-shot. Found/looked-up by `item_name` match across the quickbar then bag (`PlayerAmmo.find_ammo_stack()`/`remove_ammo_stack()` in `scripts/entities/player_ammo.gd`) — a weapon with `ammo_item_name == ""` falls back to the legacy `consumes_on_ranged` pattern (decrements the weapon's own `quantity`, e.g. old Throwing Daggers) or fires with infinite ammo.

**Landing resolution** (`PlayerAmmo.resolve_ammo_landing(ammo_item, impact_pos)`, generalized — not arrow-specific):
- **WALL** tile impact → ammo destroyed, no pickup.
- **CHASM** tile impact → not placed on this floor; pushed onto `GameState.pending_chasm_items` and reappears at a random walkable tile on the **next floor down** (drained by `DungeonFloor._spawn_pending_chasm_items()` during `_load_floor()`).
- Any other floor tile → becomes a normal pickupable floor item via `DungeonFloor.place_item_on_floor()`.
- **Miss against an enemy** → ammo lands at the enemy's tile (pickupable), same as any open-ground miss.
- **Non-lethal hit on an enemy** → ammo is embedded in the (still-alive) enemy — no pickup at all.
- **Killing hit** → handled inside `player.gd._finish_kill(enemy, dropped_ammo)`: 50% chance the ammo drops at the corpse's tile (pickupable), 50% chance it's lost with the kill.

## Weapons (current, game-wide)
The only weapons in the game are the Barbarian's starting **Greataxe** (melee, two-handed, given via `GameState._give_barbarian_starting_items()` — never spawns as floor loot), **Short Bow**, **Heavy Crossbow** above (formerly named "Crossbow" — renamed as the first of a small family of future ranged weapons, e.g. Longbow, sharing the same normal-range/FOV-long-range rule; now 1d10 Piercing, Martial, requires **Bolt** ammo instead of firing for free), and **Rapier** (melee, 1d8 Piercing, Martial, `is_finesse=true` — attack/damage use `max(STR, DEX)` — `weapon_mastery="Vex"`; not Light, not Two-handed; floor loot `fmin`/`fmax` 1–10, `weapon_arrow.png`-free sprite `weapon_duel_sword.png`). All physical melee weapons that used to spawn as floor loot (Rusty/Short/Regular/Knight/Golden/Lavish Sword) and **Throwing Daggers** have been removed from `DungeonFloorData.ITEM_POOL`, `debug_panel.ALL_ITEMS`, and boss loot (`dungeon_floor.gd drop_boss_loot()`, now potions-only). Their sprite assets under `res://sprites/weapons/` are untouched (unused, not deleted) in case they're reintroduced later.

---

## Equipment slots
`GameState.equipment` dict keys: `"melee"`, `"hand2"`, `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`. `equip()` routes `is_ranged` items automatically to `"ranged"`; melee weapons always go to `"melee"` (Main Hand) — every auto-equip path (pickup, starting gear, debug give-item), not just explicit drag equips. Inventory overlay labels `"melee"`/`"hand2"`/`"ranged"` as Main Hand/Off-hand/Ranged and enforces slot type. `"hand2"` (Off-hand) accepts non-weapon items freely, and weapons only if `Item.is_light == true` and not ranged (`inventory_overlay.gd._fits_slot()`) — dragging a non-Light weapon there is rejected. This is **slot-fit only**: nothing currently equips a second attack, applies a dual-wield attack bonus, or grants Off-hand ability uses — `equip()` never auto-routes here (only explicit drag), and combat code doesn't read `equipment["hand2"]` at all. When Main Hand holds a two-handed weapon, the Off-hand slot shows a red ✕ overlay (purely visual, `inventory_overlay.gd._refresh()`, does not additionally block the drag — the `is_light` check above is what actually gates it).

## Ranged attack flow
Shift+click enemy or floor tile → fires ranged weapon if `equipped_ranged` exists and target is in range (normal range full accuracy, or anywhere in FOV at Disadvantage — see "Ranged weapons" above). LMB on enemy within ranged range+LOS → `PlayerRanged.ranged_attack()` (`scripts/entities/player_ranged.gd`, DEX-based, projectile VFX). Shift+click any tile (not just enemies) → `PlayerRanged.ranged_attack_tile()` for VFX + ammo consumption without requiring an enemy target. Chase always ends in melee (no auto-ranged-when-chasing). **LOS for ranged**: `has_ranged_los()` in `dungeon_floor.gd` — blocks only WALL/VOID, passes through grass/doors/chasms (more permissive than `has_line_of_sight()`). **Hover indicator**: weapon icon shown above hovered enemy — melee icon normally, ranged icon when Shift held and ranged weapon equipped.

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
