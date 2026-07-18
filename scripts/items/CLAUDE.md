# scripts/items

`item.gd` — data class for all items. All item instances are `Item` resources (no nodes).

## Maintenance rule
When adding fields to `Item` or new entries to `ITEM_POOL` / `WEAPON_POOL`, **immediately update this file, `debug_panel.ALL_ITEMS`, `Item.to_dict()`/`Item.from_dict()` (save serialization — see below), and root `CLAUDE.md`** — without waiting to be asked.

## Save serialization (`to_dict()` / `from_dict()`)
`Item.to_dict() -> Dictionary` and `static Item.from_dict(d) -> Item` (Save/Load Phase A, `docs/architecture/SAVE_LOAD_ARCHITECTURE.md` §4.4) are a mechanical, hand-written listing of **every** field in the table below — flat primitives only, no `store_var()`/Resource serialization ever. **Any new `Item` field must be added to both functions or it will silently reset to its default on load.** Used by `GameState.to_dict()/from_dict()` for quickbar/bag (positional arrays, null slots preserved), equipment dict, and `pending_chasm_items`.

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
| `heal_amount` | int | potions only — FOOD items no longer use this (see "Rations / long rest" below) |
| `food_value` | int | FOOD items only: value sacrificed toward `GameState.LONG_REST_FOOD_COST` at a long rest |
| `gold_value` | int | base shop price in gold (0 = unpriced/not for sale); for `Type.GOLD` items, the pile size. Set via the `"gold"` pool key (read by `_build_floor_item()`/`_roll_boss_loot_item()`/`debug_panel._on_give_item()`). GOLD items never enter the inventory — `PlayerActions.check_pickup()` routes them into `GameState.add_gold()` (see `scripts/autoloads/CLAUDE.md`'s "Gold economy") |
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
| `is_shield` | bool | ARMOR-type item that routes to `"hand2"` (Off-hand) instead of `"armor"` on `equip()`; see "Shields" below |
| `is_heavy` | bool | Heavy weapon: melee attack with STR < 13, or ranged attack with DEX < 13, imposes Disadvantage; shown as hoverable "Heavy" keyword in tooltip |
| `is_versatile` | bool | Versatile weapon (currently only Quarterstaff). World Tree's Branching Strike keys off `is_heavy or is_versatile` for reach/push. Also gates the click-to-toggle two-handed grip in `inventory_overlay.gd` — see "Versatile weapons" below |
| `versatile_die_min`/`versatile_die_max` | int | Versatile weapons only: the damage die used in the *other* grip. `GameState.toggle_versatile_grip()` swaps these with `damage_die_min/max` and flips `is_two_handed` each time the Main Hand slot is clicked. `0`/`0` = not versatile |
| `is_finesse` | bool | Finesse weapon: attack roll and damage roll use `max(STR mod, DEX mod)` instead of always STR — `CombatMath.finesse_modifier()`, applied in `player.gd._bump_attack()`. Shown as hoverable "Finesse" keyword in tooltips |
| `is_light` | bool | Light weapon: the only kind of weapon (besides non-weapon items) allowed in the Off-hand (`"hand2"`) equipment slot, and only when Main Hand also holds a Light weapon — `inventory_overlay.gd._fits_slot()`. Shown as hoverable "Light" keyword in tooltips. Dual-wielding two Light weapons fires a bonus Off-hand attack on every melee swing — see "Equipment slots" and "Dual-wielding" below |
| `is_reach` | bool | Reach weapon: +1 tile melee range, folded into `CombatMath.melee_reach(weapon, branching_strike_rank)` alongside Branching Strike's own reach bonus (additive, unlike Branching Strike's own ranks which replace each other) — used by the chase-to-attack range check in `player.gd._execute_queued_path()` and `_try_cleave()`'s target-gathering radius. Shown as hoverable "Reach" keyword in tooltips; melee tooltip's "range: N tile(s)" line reflects it |
| `weapon_mastery` | String | One signature effect per weapon (e.g. "Cleave"); `""` = none. Shown as `(Mastery)` next to the item name in tooltips, hoverable via the same keyword-glossary popup (lowercased mastery name as the key) |
| `weapon_category` | String | "Simple", "Martial", or `""` = n/a. Gates whether `Stats.proficient_simple_weapons`/`proficient_martial_weapons` grants the proficiency bonus on the attack roll (`CombatMath.weapon_prof_bonus()` in `scripts/entities/combat_math.gd`); shown right under the damage line in tooltips, red when the class lacks that proficiency |
| `ammo_item_name` | String | Name of the Item this ranged weapon consumes per shot (e.g. `"Arrow"`); `""` = no named ammo (falls back to `consumes_on_ranged` on the weapon's own stack, or infinite). See "Ammo items" below |
| `is_thrown` | bool | Thrown weapon (currently only Spear): can be primed via RMB (same UX as quickbar food throw) then thrown at a tile with LMB — see "Thrown weapons" below |
| `uses_max`/`uses_remaining` | int | Thrown weapons only: durability. `uses_remaining` starts at `uses_max` and ticks down per throw (see "Thrown weapons"); reaching 0 breaks the weapon |
| `stack_uses` | Array[int] | Thrown weapons only: per-unit durability when stacked (`quantity > 1`) — see "Mixed-durability stacking" below |
| `taught_spell_id` | String | SCROLL items only: spell id taught into the reader's spellbook on use. `""` = not a spell scroll. See "Scroll-taught spells" below |
| `scroll_spell_id` | String | SCROLL items only: spell id for a single one-shot cast baked into this scroll (distinct from `taught_spell_id` — doesn't teach anything). `""` = not a cast-scroll. Castable by any class. See "Scroll of &lt;Spell&gt;" below |

## Rations / long rest
FOOD items (`Ration`, `Mystery Meat`, `Rotten Meat`, `Cooked Meat`) are no longer directly edible — `GameState.use_item()`'s `FOOD` branch just logs a hint and consumes nothing. Their only purpose is `Item.food_value`, sacrificed toward `GameState.LONG_REST_FOOD_COST` (100) when the player completes a long rest (`scripts/ui/short_rest_panel.gd`'s Long Rest tab, see `scripts/autoloads/CLAUDE.md`'s "Rest system"). Current values: Ration 50, Cooked Meat 75, Mystery Meat 25, Rotten Meat 10 (tune here if rebalancing). `GameState.total_food_value()` sums `food_value × quantity` across quickbar+bag; `GameState._consume_food_value(amount)` spends the cheapest-value items first and is skipped entirely while `invincible` (God Mode long rests cost nothing). Rotten Meat can still be thrown into a revealed Fire Trap to cook into Cooked Meat (`DungeonFloor.cook_rotten_meat()`) — unrelated to the eating mechanic, which no longer exists for any food item.

## Damage type categories (documentation only — no enum)
- **Physical**: Slashing, Piercing, Bludgeoning
- **Elemental**: Fire, Cold, Acid, Poison, Thunder, Lightning
- **Magical**: Force, Necrotic, Psychic, Radiant

`Item.damage_type` is a free-form String set to one of the above (or `""` = unknown). No code currently branches on the category (Physical/Elemental/Magical) itself — only Rage's `take_damage_raw()` special-cases the three Physical type strings by name. Introduce a real category grouping only if a second consumer needs it.

## Weapon masteries
`Item.weapon_mastery` names one signature effect per weapon, but it only fires if the wielder actually **knows** that mastery — gated by `Stats.knows_mastery(name) -> bool` (checks `Stats.known_weapon_masteries: Array[String]`, `scripts/entities/stats.gd`). Populated by the Mastery Picker (`scripts/ui/mastery_picker.gd`, shown after class selection — see `scripts/ui/CLAUDE.md`), which lets the player choose up to `Stats.mastery_cap()` of the 8 masteries (`Stats.ALL_WEAPON_MASTERIES`) to know. Gated at `player.gd._try_cleave()` (Cleave) and `PlayerRanged.ranged_attack()`'s Vex-set line (`scripts/entities/player_ranged.gd`) — both check `weapon.weapon_mastery == "X" and stats.knows_mastery("X")` before applying the effect. Currently implemented:
- **Cleave** (Greataxe): on any melee attack (hit or miss), if 2+ distinct visible enemies are within melee reach (`CombatMath.melee_reach(weapon, rank)` tiles, Chebyshev — folds in a Reach weapon's own bonus, though no weapon currently carries both Cleave and Reach), the swing also rolls a fully independent attack + damage roll against the enemy closest to the primary target. Implemented in `player.gd._try_cleave()` / `_resolve_cleave_attack()`, called from both the hit and miss paths of `_bump_attack()` (not ranged attacks — melee-only). Does **not** re-trigger per-turn-once bonuses (Frenzy/Ironwood Bark/Divine Fury) since those flags are already consumed by the primary attack that turn; the cleave hit is logged as its own separate `[color=cyan]Cleave:[/color]` chat line with its own `hit`/`dmg` tooltip metadata (not folded into the primary attack's numbers — this is a second swing, not a bonus source on the same swing, so the "damage stacking" rule in `scripts/entities/CLAUDE.md` doesn't apply here).
- **Vex** (Short Bow, Rapier): after a Vex-mastery hit (any hit, including crits — not on a miss), the attacker gains Advantage on their very next attack THIS ROUND against that exact same enemy — any attack type (melee, cleave, ranged), consumed on the next attack attempt regardless of hit/miss. Implemented as `player.gd._vex_adv_target: Enemy`, set both in `player.gd._bump_attack()`'s melee hit branch (Rapier) and `PlayerRanged.ranged_attack()`'s hit branch (Short Bow), checked/consumed as an ADV source in `_bump_attack()`, `_resolve_cleave_attack()`, and `PlayerRanged.ranged_attack()`. Cleared in `_on_turn_started()`'s `if not came_from_revert:` reset block, so it survives a `revert_to_waiting()` free-action chain (e.g. Rager) within the same round but clears at a real new round — see `_reverted_this_round` in `scripts/entities/CLAUDE.md`.
- **Push** (Heavy Crossbow): on a ranged hit that doesn't kill the target, the enemy rolls `Enemy.resist_check(dc, true)` (CON-based) vs `dc = 8 + prof + DEX mod` — same DC convention as World Tree's Grip of the Forest/Branching Strike (see `scripts/entities/CLAUDE.md`). On a failed save the target is shoved exactly 1 tile directly away from the player via `DungeonFloor.resolve_push(enemy, direction)` (`scripts/world/dungeon_floor.gd`) — a dedicated resolver, **not** `force_move_entity()`, because it needs non-generic per-tile outcomes: WALL → 1d4 Bludgeoning damage, no movement; a trap tile → moves the enemy there and calls `trigger_trap()`; CHASM → the enemy is removed entirely (counts as a kill for exp), and if it was a boss its rolled loot item is appended to `GameState.pending_chasm_items` to appear on the next floor down (see "Ammo items" chasm handling below — same drain mechanism, reused as-is). Implemented in `PlayerRanged.ranged_attack()` (`scripts/entities/player_ranged.gd`), gated the same `weapon.weapon_mastery == "Push" and stats.knows_mastery("Push")` way as Cleave/Vex — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- **Graze** (Greatsword, Glaive): on a melee **miss** (including a nat-1 critical fail), the attack still deals damage equal to the ability modifier used for that attack roll (STR for both — neither weapon is Finesse, `min 0`) — a fully separate damage instance, not folded into the (nonexistent) hit damage of the same swing. Implemented in `player.gd._try_graze()`, called from the miss branch of `_bump_attack()` only (melee-only, mirrors Cleave's miss-path call site); logged as its own `[color=cyan]Graze:[/color]` chat line with its own `grz` tooltip meta (`TooltipFormatters.fmt_grz_tooltip()`). Gated the same `weapon.weapon_mastery == "Graze" and stats.knows_mastery("Graze")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- **Topple** (Maul): on a melee **hit**, the target rolls `Enemy.resist_check(dc, true)` (CON-based) vs `dc = 8 + prof + STR mod` — same DC convention as Push/Grip of the Forest/Branching Strike. On a failed save the enemy is set `prone_turns = 1` (`scripts/entities/enemy.gd`), which makes it skip its entire next turn (no movement, no attack) — checked at the very top of `Enemy.take_turn()`, before the `slowed_turns` check. Implemented in `player.gd._try_topple()`, called from the hit branch of `_bump_attack()` only (melee-only, right after the Branching Strike R3 push block). No damage is dealt, so there's no `[url=]` tooltip meta — just a plain colored log line (mirrors Push's "resists the shove" plain-text style for the same reason). Gated the same `weapon.weapon_mastery == "Topple" and stats.knows_mastery("Topple")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- **Sap** (Spear, thrown only): on a **thrown** hit, sets `Enemy.disadv_next_attack = true` — the same flag/consumption point World Tree's Grip of the Forest R3 already uses, so it fires as Disadvantage on the target's very next attack (whichever turn that happens to be next, i.e. its own next turn). Implemented in `PlayerThrowTool._throw_weapon()` (`scripts/entities/player_throw_tool.gd`), gated the same `weapon.weapon_mastery == "Sap" and stats.knows_mastery("Sap")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`). Sap only fires on a throw, never on a normal melee attack with the same Spear.
- **Vex** is also carried by the **Handaxe** (see "Dual-wielding" below) — same trigger/consumption rules as Short Bow/Rapier, just a second weapon that can grant it.
- **Nick** (Dagger): while dual-wielding two Light weapons (see "Dual-wielding" below) with either the Main Hand or the Off-hand weapon carrying Nick, the Off-hand swing is followed by one further attack this same turn — identical rules to the Off-hand swing itself (independent d20 roll, damage drops the ability modifier unless negative) — for a maximum of **3** attacks total (Main Hand, Off-hand, Nick bonus). Implemented as a second call to `player.gd._resolve_offhand_attack()` right after the first, from `_try_offhand_attack()`, gated the same `stats.knows_mastery("Nick")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`). Logged as its own `[color=cyan]Nick:[/color]` chat line (the shared `_resolve_offhand_attack(enemy, weapon, label)` function's `label` param defaults to `"Off-hand"` but is passed `"Nick"` for this second swing) so it's distinguishable from the ordinary Off-hand line even though the roll math is identical.
- **Slow** (Longbow): on a ranged hit that doesn't kill the target, sets `Enemy.slowed_turns = maxi(enemy.slowed_turns, 1)` — the same field/mechanism as stepping into Mud/Water (`enemy.gd`'s difficult-terrain handling), which makes the enemy skip its entire next turn (checked at the top of `Enemy.take_turn()`, right after `prone_turns`). No save/resist roll, unlike Push/Topple — always applies on a non-lethal hit. Implemented in `PlayerRanged.ranged_attack()` right after the Push `elif` branch, gated the same `weapon.weapon_mastery == "Slow" and stats.knows_mastery("Slow")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- New masteries: add the glossary text to `KEYWORD_GLOSSARY` in both `hud.gd` and `inventory_overlay.gd` (key = mastery name lowercased) and implement the effect wherever it naturally hooks into combat (see Cleave for the melee-attack pattern, Vex for the per-turn-flag pattern, Push for the forced-movement pattern, Graze for the miss-damage pattern, Topple for the save-vs-status pattern, Sap for the thrown-attack pattern).

## Thrown weapons
`Item.is_thrown` + `range` (normal throw range) + `uses_max`/`uses_remaining` (currently only the Spear: Simple, Piercing, Versatile 1d6/1d8, `weapon_mastery="Sap"`, `range=3`, `uses_max=5`). Primed exactly like throwing a food item from the quickbar — **RMB a quickbar slot** (`hud.gd`'s `_on_slot_gui_input()` → `GameState.player_throw_primed`, no item-type filter) then **LMB a target tile** (`PlayerActions`/`player.gd` → `PlayerThrowTool.do_throw()`). `do_throw()` branches on `item.item_type == Item.Type.WEAPON and item.is_thrown` *before* the generic food/item-throw branch, dispatching to `PlayerThrowTool._throw_weapon(weapon, pos)`. Because priming only reads `GameState.player_quickbar` (not the equipment slots), a Spear must be sitting in the quickbar/bag to be thrown — an *equipped* copy in Main Hand is a separate `Item` instance and still attacks normally in melee.

**Attack roll**: uses the wielder's **melee** attack modifier (STR, or `max(STR,DEX)` if `is_finesse`) and melee weapon-proficiency bonus — never a DEX/ranged stat, even though it's thrown. **Range**: `Item.range` is the normal range (full accuracy); beyond that but within the player's live FOV (`DungeonFloor.FOV_RADIUS`, `is_tile_visible()`-gated) the throw still works but rolls with Disadvantage — identical convention to ranged weapons' normal/long-range rule (`PlayerRanged.is_ranged_target_in_range()`/`ranged_shot_disadvantage()`), just off the melee modifier instead of DEX. Throwing at an empty tile (no `DungeonFloor.get_enemy_at(pos)`) auto-"misses" (no roll, no use lost) and just lands. The chat log line's roll breakdown uses tooltip meta kind `"thrhit"` (same param shape as melee `"hit"`/`"miss"` — `hud.gd._format_tooltip()`'s `kind` dispatch routes it to the existing `TooltipFormatters.fmt_hit_tooltip(params, false)`, no new formatter needed) and `"dmg"` for the damage breakdown (shared with every other attack type). The **Dagger** is Finesse as well as Thrown/Light — its thrown attack roll uses `max(STR, DEX)` like any other Finesse weapon, same as a normal melee swing with it would.

**Landing** (mirrors "Ammo items" above, with the thrown weapon's own rules): no enemy on the target tile → lands on the ground there as a normal pickupable floor item (`DungeonFloor.place_item_on_floor()`), **no use lost**. A **miss** OR a **non-lethal hit** against an enemy → embeds in the enemy — `Enemy.embedded_items: Array[Item]` (`scripts/entities/enemy.gd`) — instead of landing anywhere (`-1` use, `-2` on a nat-1 fumble miss, `0` on a nat-20 crit hit); no pickup while the enemy is still alive (a miss used to drop it as an immediately-pickable floor item at the enemy's tile — changed to embed-until-death so it behaves like ranged ammo instead of being trivially recoverable mid-fight). Enemy.**die()** is overridden to drop every item in `embedded_items` at its `grid_pos` (100% chance each, not the ranged-ammo 50%) right before freeing — every death call site (`player.gd._finish_kill()`, `companion.gd`, the trap/chasm death sites in `dungeon_floor.gd`) already ends with `enemy.die()`, so this single override covers an embedded Spear being recovered whenever/however that enemy eventually dies, not just from the throw that embedded it. A hit that also kills the enemy in the same throw still embeds first, so the override drops it immediately at the same tile.

**Durability**: `uses_remaining` decrements by 1 per throw, by 2 on a natural-1 critical fumble, and by 0 (no cost) on a natural-20 critical hit — `PlayerThrowTool._consume_throw_use(weapon, uses_lost) -> bool`, guarded by `GameState.invincible` like every other consumption site. Returns `true` (and logs `"Your <name> breaks!"` in the chat log, plus `GameState.remove_item(weapon)`) when durability hits 0 on this throw — in that case the weapon shatters instead of landing/embedding anywhere; callers check the return value before doing any landing/embedding. Ordinary melee attacks with the same weapon never touch `uses_remaining` — only throwing does. Tooltips show current durability as a right-aligned `Uses: X/Y` line (thrown weapons only) just above the "Ctrl: inspect" hint, in both `inventory_overlay.gd`'s and `hud.gd`'s item tooltips.

**Mixed-durability stacking**: `GameState.add_item()` merges any weapon with `uses_max > 0` into an existing same-named stack regardless of durability (only `uses_max` itself must match, as a sanity check that it's really the same weapon type) — two Handaxes at different durability now share one inventory slot instead of landing in separate piles. Each unit's own `uses_remaining` is preserved via `Item.stack_uses: Array[int]` (`scripts/items/item.gd`), kept sorted ascending by `GameState._merge_into_stack(ex, incoming)` so index 0 — the **most-damaged unit** — is always "on top": it's what's mirrored into the stack's own `uses_remaining` (and therefore what the `Uses: X/Y` tooltip line shows) and what gets split off first. `Item.get_stack_uses() -> Array` returns one durability value per unit (falls back to repeating `uses_remaining` when `stack_uses` isn't materialized — e.g. a stack where every unit still shares the same durability, or a pre-this-feature save). `GameState.equip(item)`, `GameState.move_item()` (the drag-and-drop path — see "Equipment slots" below), and `PlayerThrowTool._throw_weapon(weapon, pos)` all split the most-damaged unit off a stack (`quantity > 1`) before acting, via the shared `GameState._should_split_for_equip(item)` / `_split_one_unit(item)` helpers — pops `stack[0]` (lowest `uses_remaining`) into a fresh single-quantity `Item`, decrementing the original stack's `quantity` and re-syncing its `stack_uses`/`uses_remaining` to the next-most-damaged unit. `Item.stack_uses` is serialized in `to_dict()`/`from_dict()` like every other field. **Gotcha**: when rebuilding the remaining `stack_uses` array in `_split_one_unit()`, the "no leftover durability data" branch must assign an explicitly-typed empty `Array[int]` — a bare `[]` ternary literal assigned into the typed `stack_uses` property crashes at runtime (this broke throwing/equipping from any stack of exactly 2 units, since that's precisely when the remainder collapses to a single untyped-vs-typed edge case).

---

## Ranged weapons (current)
Every ranged weapon has just one range value — `Item.range`, the "normal" range at full accuracy. **Long range is NOT a per-weapon field**: every ranged weapon can additionally fire anywhere within the player's live FOV (`DungeonFloor.FOV_RADIUS`, gated by actual `is_tile_visible()` — not just distance, so shots around corners don't count), but a shot beyond `range` rolls with Disadvantage. See `PlayerRanged.is_ranged_target_in_range()` / `ranged_shot_disadvantage()` (`scripts/entities/player_ranged.gd`).

| Item | Bonus | Normal range | Ammo | Stat | Category | Mastery |
|---|---|---|---|---|---|---|
| Short Bow | +0 | 4 | Arrow | DEX | Simple | Vex |
| Heavy Crossbow | +0 | 4 | Bolt | DEX | Martial | Push |
| Longbow | +0 | 5 | Arrow | DEX | Martial | Slow |

Heavy Crossbow and Longbow are both also `is_heavy=true` (DEX 13+ or Disadvantage) and `is_two_handed=true` (cosmetic for a ranged weapon — see root `CLAUDE.md`'s note that `is_two_handed` doesn't block the ranged slot).

## Ammo items
`Item.ammo_item_name` on a ranged weapon names a separate stackable `Item` (`Item.Type.TOOL`, no combat stats of its own — currently **Arrow** for the Short Bow and Longbow, and **Bolt** for the Heavy Crossbow, both reusing `weapon_arrow.png` since no dedicated bolt sprite exists yet) consumed 1-per-shot. Found/looked-up by `item_name` match across the quickbar then bag (`PlayerAmmo.find_ammo_stack()`/`remove_ammo_stack()` in `scripts/entities/player_ammo.gd`) — a weapon with `ammo_item_name == ""` falls back to the legacy `consumes_on_ranged` pattern (decrements the weapon's own `quantity`, e.g. old Throwing Daggers) or fires with infinite ammo.

**Landing resolution** (`PlayerAmmo.resolve_ammo_landing(ammo_item, impact_pos)`, generalized — not arrow-specific):
- **WALL** tile impact → ammo destroyed, no pickup.
- **CHASM** tile impact → not placed on this floor; pushed onto `GameState.pending_chasm_items` and reappears at a random walkable tile on the **next floor down** (drained by `DungeonFloor._spawn_pending_chasm_items()` during `_load_floor()`).
- Any other floor tile → becomes a normal pickupable floor item via `DungeonFloor.place_item_on_floor()` (open-ground/wall shots via `PlayerRanged.ranged_attack_tile()` still call this — a miss into empty space is a genuine floor drop).
- **Miss against a still-alive enemy** → `PlayerRanged.ranged_attack()`'s miss branch does **not** call `resolve_ammo_landing()` at all — the ammo stays lodged in the enemy with no floor pickup, identically to a non-lethal hit.
- **Non-lethal hit on an enemy** → ammo is embedded in the (still-alive) enemy — no pickup at all.
- **Killing hit** → handled inside `player.gd._finish_kill(enemy, dropped_ammo)`: 50% chance the ammo drops at the corpse's tile (pickupable), 50% chance it's lost with the kill.

## Weapons (current, game-wide)
The only weapons in the game are the Barbarian's starting **Greataxe** (melee, two-handed, given via `GameState._give_barbarian_starting_items()` — never spawns as floor loot), **Short Bow**, **Heavy Crossbow** above (formerly named "Crossbow" — renamed as the first of a small family of ranged weapons sharing the same normal-range/FOV-long-range rule; 1d10 Piercing, Martial, requires **Bolt** ammo), **Longbow** (ranged, floor loot, 1d8 Piercing, Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Slow"`, normal range 5 (one tile further than Short Bow/Heavy Crossbow's 4), requires **Arrow** ammo (shared with Short Bow); floor loot `fmin`/`fmax` 5–10, sprite `Weapons/Bow.png` — see "Weapon masteries" above for what Slow does), **Rapier** (melee, 1d8 Piercing, Martial, `is_finesse=true` — attack/damage use `max(STR, DEX)` — `weapon_mastery="Vex"`; not Light, not Two-handed; floor loot `fmin`/`fmax` 1–10, `weapon_arrow.png`-free sprite `weapon_duel_sword.png`), **Greatsword** (melee, floor loot, 2d6 Slashing — approximated as a single `randi_range(2, 12)` roll, same simplified single-die-roll convention every other weapon uses rather than summing two separate d6 rolls — Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Graze"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_knight_sword.png` — no dedicated greatsword sprite exists yet), **Glaive** (melee, floor loot, 1d10 Slashing, Martial, `is_heavy=true`, `is_two_handed=true`, `is_reach=true`, `weapon_mastery="Graze"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_spear.png` — no dedicated polearm sprite exists yet — the first and so far only weapon to set `is_reach`), **Maul** (melee, floor loot, 2d6 Bludgeoning, Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Topple"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_big_hammer.png` — the first weapon with Bludgeoning damage type), and **Quarterstaff** (melee, floor loot, Simple, Bludgeoning, `weapon_mastery="Topple"`; 1d6 one-handed / 1d8 two-handed — `is_versatile=true`, `damage_die_min/max=1/6`, `versatile_die_min/max=1/8` at rest; floor loot `fmin`/`fmax` 1–10, sprite `weapon_green_magic_staff.png` — no dedicated plain-staff sprite exists yet — the first Versatile weapon, see "Versatile weapons" below), **Spear** (melee, floor loot, Simple, Piercing, `weapon_mastery="Sap"`; also Versatile 1d6/1d8 like the Quarterstaff, plus `is_thrown=true`, `range=3` (normal throw range, FOV beyond that at Disadvantage), `uses_max=5`; floor loot `fmin`/`fmax` 1–10, sprite `weapon_spear.png` (shared with Glaive — no dedicated javelin/spear-only sprite exists yet) — the first and so far only Thrown weapon, see "Thrown weapons" below), **Handaxe** (melee, floor loot, Simple, Slashing, 1d6, `weapon_mastery="Vex"`, `is_light=true` — the first Light weapon; also `is_thrown=true`, `range=3`, `uses_max=5` like the Spear; floor loot `fmin`/`fmax` 1–10, sprite `weapon_throwing_axe.png` — dual-wielding a second Light weapon in the Off-hand fires a bonus attack each melee swing, see "Dual-wielding" below), and **Dagger** (melee, floor loot, Simple, Piercing, 1d4, `is_finesse=true`, `is_light=true`, `weapon_mastery="Nick"`; also `is_thrown=true`, `range=3`, `uses_max=5` like the Handaxe; floor loot `fmin`/`fmax` 1–10, sprite `weapon_knife.png` — see "Weapon masteries" above for what Nick does). All physical melee weapons that used to spawn as floor loot (Rusty/Short/Regular/Knight/Golden/Lavish Sword) and **Throwing Daggers** have been removed from `DungeonFloorData.ITEM_POOL`, `debug_panel.ALL_ITEMS`, and boss loot (`dungeon_floor.gd drop_boss_loot()`, now potions-only). Their sprite assets under `res://sprites/weapons/` are untouched (unused, not deleted) in case they're reintroduced later.

---

## Versatile weapons
`Item.is_versatile` + `versatile_die_min/max` (currently only the Quarterstaff, 1d6 one-handed / 1d8 two-handed). Left-clicking the Main Hand (`"melee"`) equipment slot in `inventory_overlay.gd` **without dragging** (press+release inside the same slot, detected in `_finish_drag()`) calls `GameState.toggle_versatile_grip()` when the equipped item is versatile: swaps `damage_die_min/max` with `versatile_die_min/max` (so the "other" grip's die is always sitting in `versatile_die_min/max`), flips `is_two_handed`, and calls `recalculate_stats()` — no turn cost, purely a grip switch. `inventory_overlay.gd._refresh()` gives the Main Hand slot a highlighted gold border (`border_color`/width bumped) while gripped two-handed, and the tooltip's Versatile keyword line shows the current grip and the die you'd get by switching. Flipping `is_two_handed` also drives the existing Off-hand ✕ block indicator for free (same mechanism as any other two-handed weapon).

## Equipment slots
`GameState.equipment` dict keys: `"melee"`, `"hand2"`, `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`. `equip()` routes `is_ranged` items automatically to `"ranged"`; melee weapons always go to `"melee"` (Main Hand) — every auto-equip path (pickup, starting gear, debug give-item), not just explicit drag equips. Inventory overlay labels `"melee"`/`"hand2"`/`"ranged"` as Main Hand/Off-hand/Ranged and enforces slot type. `"hand2"` (Off-hand) accepts non-weapon items freely; a weapon is only accepted if it's Light, not ranged, **and** Main Hand also currently holds a Light weapon (`inventory_overlay.gd._fits_slot()`) — dragging a non-Light weapon there, or a Light weapon while Main Hand isn't Light, is rejected. `equip()` never auto-routes here (only explicit drag). See "Dual-wielding" below for what equipping a second Light weapon actually does in combat. When Main Hand holds a two-handed weapon, the Off-hand slot shows a red ✕ overlay (purely visual, `inventory_overlay.gd._refresh()`, does not additionally block the drag — the Light checks above are what actually gate it).

**Dragging a stack**: `GameState.move_item()` (the drag-and-drop path — `inventory_overlay._do_move()` is the only caller) special-cases dropping onto an `"equipment"` destination: if the dragged item is a stacked durability weapon (`_should_split_for_equip()`, currently Handaxe/Dagger/Spear — anything with `uses_max > 0` and `quantity > 1`), only a single unit is equipped (`_split_one_unit()`); the rest of the stack stays exactly where it was instead of the whole pile moving into the slot. Whatever was previously in that equipment slot goes to the first empty quickbar/bag slot (`_add_to_bags_silent()`, same as `equip()`'s replaced-item handling) rather than swapping back into the drag's source slot. This is what makes it comfortable to equip just one Handaxe/Dagger into the Off-hand out of a full stack of 5.

## Shields
`Item.is_shield` (currently one item, "Shield" — flat `bonus_ac = 2`, `res://sprites/items/Shields/Shield1.png`) is an `Item.Type.ARMOR` item that `GameState.equip()` routes to `"hand2"` (Off-hand) instead of `"armor"` — the only ARMOR-type item that doesn't land in the Armor slot. Its `bonus_ac` flows into AC through `recalculate_stats()`'s existing generic per-slot loop (see root `CLAUDE.md`'s combat-roll table) — no special-cased AC code needed. Gated by `Stats.proficient_shields` (`scripts/entities/CLAUDE.md`'s "Weapon proficiency flags" — Barbarian/Ranger only) via `GameState.can_equip_shield(item) -> bool`, checked at every entry point that can place a Shield into `"hand2"`: `equip()`, `move_item()` (drag), and `inventory_overlay.gd._fits_slot()` (drag preview gate). Lacking proficiency, or having a two-handed Main Hand weapon equipped, blocks equipping outright (unlike weapon proficiency, which just drops a bonus) — `GameState.log_shield_equip_blocked(item)` logs which reason applied. A two-handed Main Hand weapon (via `equip()`/`move_item()`'s existing `_auto_unequip_offhand()`, or `toggle_versatile_grip()` switching to a two-handed grip) auto-kicks an equipped Shield back to the bag, same as it would any other Off-hand item. **Blocks all spellcasting while equipped** — `PlayerSpellcasting._shield_blocks_casting()` gates the top of `begin_cast()`, `cast_direct()`, and `on_scroll_primed()` (`scripts/entities/player_spellcasting.gd`). **Equip/unequip costs 1 turn** (the one exception to "equip is always a free action" — see `scripts/autoloads/CLAUDE.md`'s Equipment slots section): `equip()`/`unequip()`/`move_item()` each wrap the mutation in `TurnManager.begin_player_action()`/`on_player_action_complete()` when a Shield is entering or leaving `"hand2"` (including being displaced by a different item dragged into an occupied slot) AND `TurnManager.phase == WAITING_FOR_INPUT` (guards against double-costing if ever called outside a normal player turn). **Ends Mage Armor**: equipping a Shield clears `Stats.mage_armor_active` exactly like equipping real Armor does — 5e RAW counts a shield as worn armor for this purpose even though it lives in `"hand2"`, not `"armor"` — checked independently in both `equip()` and `move_item()` (see `scripts/entities/CLAUDE.md`'s "Mage Armor").

## Dual-wielding
When Main Hand (`"melee"`) and Off-hand (`"hand2"`) both hold a Light melee weapon (currently only the **Handaxe** — the first and so far only Light weapon), every melee attack also swings the Off-hand weapon at the same target: a fully independent d20 roll + damage roll, fired regardless of whether the primary Main Hand attack hit or missed (same "always fires" pattern as Cleave). Implemented in `player.gd._try_offhand_attack()` / `_resolve_offhand_attack()`, called from both the hit and miss paths of `_bump_attack()` right after `_try_cleave()`. Gated on `is_str_weapon` (Main Hand must be an equipped melee weapon, not unarmed/ranged) — Monk unarmed and ranged weapons never trigger it.

**House rule (5e Two-Weapon Fighting)**: the attack roll still adds the normal STR/finesse ability modifier (needed to hit), but the **damage roll drops the ability modifier entirely unless it's negative**, in which case the negative modifier is always applied — `mini(attack_mod, 0)` in `_resolve_offhand_attack()`. The Off-hand weapon's own `bonus_damage`, Rage bonus damage, and crit doubling still apply normally; Frenzy/Ironwood Bark/Divine Fury (once-per-turn bonuses already consumed by the primary swing) do not re-trigger — same reasoning as Cleave. A Vex-mastery Off-hand hit still sets `_vex_adv_target` like any other Vex weapon. Logged as its own `[color=cyan]Off-hand:[/color]` chat line with its own `hit`/`dmg` tooltip metadata (not folded into the primary attack's numbers — a second swing, not a bonus source on the same swing, so the "damage stacking" rule in `scripts/entities/CLAUDE.md` doesn't apply here). `_resolve_offhand_attack(enemy, weapon, label)` takes an optional `label` (default `"Off-hand"`) purely for this log-line prefix — see **Nick** below for the second caller.

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

---

## Spellcasting data (`spell.gd`, `spell_db.gd`, `spellcaster_state.gd`, `spell_slot_pool.gd`)

Cantrips (`docs/architecture/spellcasting-design.md`) plus leveled spells + spell slots
(`docs/architecture/leveled-spells-and-slots-plan.md`) — see `scripts/entities/CLAUDE.md`'s
"Wizard spellcasting (cantrips)" and "Wizard leveled spells (spell slots)" sections for the full
cast-resolution walkthroughs.

- **`Spell`** (`Resource`) — `spell_id`, `spell_name`, `description`, `icon_path`, `level` (0 =
  cantrip, 1-9 = leveled), `school`, `range_tiles`, `resolution` (enum: `ATTACK_ROLL`/`SAVE`/
  `AUTO_HIT`), `target_kind` (enum: `ENEMY`/`SELF`/`TILE`), `dice_count`, `dice_sides`,
  `damage_type`, `cantrip_tier_scaling: bool` (dice_count × tier at character levels 1/5/11/17),
  `save_stat`/`save_for_half` (SAVE
  resolution only), `shape`/`shape_size` (`""` = single target, `"sphere"` = AoE radius —
  deliberately no cone/line/cube, see the plan doc §7's content-scope cut), `effect_id` (`""` =
  pure generic damage path; else dispatched in `SpellEffects`), `class_list`. Still missing
  concentration/reaction/component fields from the full design doc's `Spell` shape — add if a
  future spell needs them.
- **`SpellDb`** (static factory, `RefCounted`) — `get_spell(id) -> Spell` builds all spells in
  code, same "no `.tres` files" convention as `Talent`/`SpriteFrames`. `CANTRIP_IDS` (8 cantrips:
  the original `fire_bolt`/`ray_of_frost`/`shocking_grasp` plus `toll_the_dead`/`blade_ward`/
  `thunderclap`/`mind_sliver`/`light` — see `scripts/entities/CLAUDE.md`'s "Wizard spellcasting"
  section for all 8) + `STARTER_CANTRIP_IDS` (the fixed 3-cantrip round-1 pool `cantrip_select.gd`
  always offers — kept separate from `CANTRIP_IDS` so old saves/the premade Jace's
  `"cantrip": "fire_bolt"` shortcut stay valid) + `LEVELED_SPELL_IDS` (11:
  `magic_missile`/`shield`/`mage_armor`/`misty_step`/`fireball`/`chromatic_orb`/`burning_hands`/
  `witch_bolt`/`expeditious_retreat`/`false_life`/`fog_cloud` — the last 6 added after the initial
  pass, see `scripts/entities/CLAUDE.md`'s "More 1st-level spells" and "More 1st-level non-damage
  spells" sections) + `CLASS_SPELL_LISTS: Dictionary`
  (`"WIZARD"` → `LEVELED_SPELL_IDS`, the level-up learn picker's candidate pool — cantrips are
  deliberately excluded from this list since they're a separate, always-known system).
- **`SpellcasterState`** (`Resource`) — lives on `Stats.caster` (null for every class but Wizard),
  not `GameState`, so a future enemy/companion caster can carry its own instance.
  `spellcasting_ability: String` ("INT"/"WIS"/"CHA"), `known_spells: Array[String]` (cantrips AND
  leveled spells — `is_cantrip(id)` distinguishes via `SpellDb.get_spell(id).level == 0`, not by
  a separate array), `prepared_spells: Array[String]` (today's prepared leveled spells, never
  cantrips), `slot_pool: StandardSlotPool`. `spell_attack_bonus(stats)` / `spell_save_dc(stats)`
  are computed **live, never cached** (`proficiency_bonus + ability_mod`,
  `8 + proficiency_bonus + ability_mod`) — mirrors `Stats.mastery_cap()`'s "recompute every time"
  convention, and deliberately does NOT derive from `character_class` (keeps a future multiclass
  caster sane — see the design doc §10.3). `prepared_max(stats) -> int` returns
  `stats.character_level` (leveled-spells-and-slots-plan.md §1 — supersedes the framework doc's
  `ability_mod + caster_level` formula for Wizard).
- **`StandardSlotPool`** (`Resource`, `scripts/items/spell_slot_pool.gd`) — the real D&D 2024
  full-caster 1–20 slot table (`SLOT_TABLE` const), long-rest-only recharge
  (`on_short_rest()` is a no-op). `available_level(spell) -> int` returns `spell.level` if that
  EXACT slot level currently has an unspent slot, else `-1` — **no upcasting**: a spell locked out
  of its own slot level never falls back to a higher still-available one (was
  `lowest_available_level()`, which searched upward and could silently auto-upcast — removed per
  direct owner correction; upcasting was never requested and produced surprising results, e.g.
  Chromatic Orb auto-casting at a 5th-level slot). `grant_new_slots_on_levelup(old_max)` tops up
  newly-grown slot levels immediately after a level-up instead of leaving them empty until the
  next long rest (see `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" for why). Deliberately
  **not** a `SpellSlotPool` base class + subclass hierarchy — only one caster type exists, so a
  pluggable-pool abstraction for Pact/Cooldown pools that don't exist yet would be speculative;
  add the base class back when a second caster archetype needs different pool behavior.

## Scroll-taught spells

`Item.taught_spell_id: String` (`""` = not a spell scroll — every pre-existing SCROLL item stays
a no-op). `GameState.use_item()`'s `SCROLL` branch calls `learn_spell(taught_spell_id)` and
consumes the scroll, unless the reader already knows that spell (logs "You already know this
spell." instead). No scroll items use this mechanism in any loot pool yet — see "Scroll of
&lt;Spell&gt; (single-use cast scrolls)" below for the SCROLL items that DO exist today.

## Scroll of &lt;Spell&gt; (single-use cast scrolls)

`Item.scroll_spell_id: String` (`""` = not this kind of scroll) — a SCROLL item with one spell
cast baked in, distinct from (and independent of) `taught_spell_id` above: reading it does NOT
teach the spell, it just casts it once at the spell's base level (no upcasting, no slot spent)
then crumbles. **Castable by any class**, not just Wizard — the point of this item type. 19 exist
in `ITEM_POOL`/`debug_panel.ALL_ITEMS` today, one per `SpellDb` spell (`Scroll of Fire Bolt`,
`Ray of Frost`, `Shocking Grasp`, `Toll the Dead`, `Blade Ward`, `Thunderclap`, `Mind Sliver`,
`Light`, `Magic Missile`, `Shield`, `Mage Armor`, `Misty Step`, `Fireball`, `Chromatic Orb`,
`Burning Hands`, `Witch Bolt`, `Expeditious Retreat`, `False Life`, `Fog Cloud`); icon reuses the
spell's own `Spell.icon_path` (`"src": "spells"` pool key) — `DungeonFloor._build_floor_item()`
and `debug_panel._on_give_item()` both resolve it via `SpellDb.get_spell(item.scroll_spell_id).
icon_path` rather than reconstructing a flat path from the `ITEM_POOL` entry's own `"icon"` key,
since real spell art lives nested by level (`res://icons/spells/<level>/<id>.png` — see
`scripts/entities/CLAUDE.md`'s "Wizard spellcasting" section) and reusing the spell's own path
keeps the two from drifting out of sync. No dedicated scroll-item sprite exists — every scroll
just shows its spell's icon.

**Casting math without a caster**: `SpellEffects._attack_bonus()`/`_save_dc()`/`_cast_ability_mod()`
(`scripts/entities/spell_effects.gd`) are caster-optional — if `Stats.caster` exists (Wizard) they
defer to `SpellcasterState`'s own ability as before; otherwise they fall back to
`proficiency_bonus + INT modifier` (root `CLAUDE.md`'s "every non-caster uses INT" rule). Every
formerly-`caster.spell_attack_bonus(stats)`/`caster.spell_save_dc(stats)` call site in
`spell_effects.gd` now goes through these three helpers instead, so casting math Just Works for
any class reading a scroll — no per-call from_scroll branching needed for the math itself.

**Activation flow**: `GameState.use_item()`'s `SCROLL` branch emits `player_scroll_primed(item)`
when `scroll_spell_id != ""` (checked before the `taught_spell_id` branch — the two are mutually
exclusive per item). `player.gd` connects it to `PlayerSpellcasting.on_scroll_primed(item)`, which
reuses the exact same `spell_targeting_active`/`_armed_spell_id` arm-then-LMB-resolve flow as a
normal ability-bar spell (`begin_cast()`/`try_cast_at()`) — Esc-cancel, AoE preview (Fireball), and
range/LOS checks all come along for free. Two internal-only fields (`_casting_from_scroll`,
`_armed_scroll_item`) tell `try_cast_at()`/`_cast_self()` to skip the spell-slot-availability
check/consumption (a scroll never touches `SpellcasterState.slot_pool`, even for a Wizard reading
their own known spell) and to consume the scroll item itself instead, via `_consume_scroll()`
(skipped while `GameState.invincible`) — fired the instant the cast actually resolves (after the
range/LOS check passes), so a scroll is spent even on a miss, same as a real D&D scroll.
`SpellEffects.cast_spell()`/`cast_leveled_self()`/`cast_leveled_at_tile()`/`cast_leveled_at_enemy()`
all take an added `from_scroll: bool = false` param threaded down to `_consume_slot()`, which
early-returns when true instead of touching `player.stats.caster.slot_pool`.
