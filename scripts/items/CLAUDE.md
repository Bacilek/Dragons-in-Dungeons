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
| `heal_amount` | int | potions, plus one FOOD exception: Healing Herb (special-rooms-economy-design.md §4.3, session 7d) is the only FOOD entry with `heal_amount > 0` — `GameState.use_item()`'s FOOD branch checks `heal_amount > 0` first and heals+consumes instead of the normal "saved as fuel" message. Every other FOOD item still has `heal_amount == 0` and keeps that message (see "Rations / long rest" below) |
| `food_value` | int | FOOD items only: value sacrificed toward `GameState.LONG_REST_FOOD_COST` at a long rest |
| `gold_value` | int | base shop price in gold (0 = unpriced/not for sale); for `Type.GOLD` items, the pile size. Set via the `"gold"` pool key (read by `_build_floor_item()`/`_roll_boss_loot_item()`/`debug_panel._on_give_item()`). GOLD items never enter the inventory — `PlayerActions.check_pickup()` routes them into `GameState.add_gold()` (see `scripts/autoloads/CLAUDE.md`'s "Gold economy") |
| `silver_value` | int | sub-gold price remainder in silver pieces (0-9; 10 sp = 1 gp, always normalized at authoring time — e.g. a 2sp item is `gold_value=0, silver_value=2`, never `silver_value=20`). Set via the `"silver"` pool key, same read sites as `gold_value`. Display-only — `WeaponTooltip.format_price()` is the only consumer (`scripts/items/CLAUDE.md`'s "Unified weapon tooltip format"), no shop/spend path reads it |
| `bonus_damage` | int | weapon hit bonus |
| `bonus_ac` | int | armor AC bonus |
| `enhancement_level` | int | Debug-only "Enhance" button counter (F3 → Enhance Item on Slot 1) — how many +1 presses have been applied, purely so the display name can show `"+N"`. See "Enhance debug tool" below |
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
| `armor_category` | `Item.ArmorCategory` | `NONE`/`LIGHT`/`MEDIUM`/`HEAVY` — body armor's weight class; `NONE` = not body armor (every non-armor item, plus the Shield). See "Body armor" below |
| `base_ac` | int | Body armor only: base AC before the DEX bonus. `0` = not a real body-armor item |
| `dex_cap` | int | Body armor only: `-1` = unlimited DEX bonus (Light), `N` = capped at `+N` (Medium), `0` = no DEX bonus at all, even negative (Heavy) |
| `str_requirement` | int | Body armor only: minimum STR score to equip (Heavy armor only); `0` = no requirement |
| `stealth_disadvantage` | bool | Body armor only: imposes Disadvantage on the Stealth-vs-Passive-Perception check while worn |
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
| `is_torch`/`torch_lit`/`torch_burnt`/`torch_turns_remaining` | bool/bool/bool/int | Torch: click-to-light while equipped. See "Torch" below |
| `taught_spell_id` | String | SCROLL items only: spell id taught into the reader's spellbook on use. `""` = not a spell scroll. See "Scroll-taught spells" below |
| `scroll_spell_id` | String | SCROLL items only: spell id for a single one-shot cast baked into this scroll (distinct from `taught_spell_id` — doesn't teach anything). `""` = not a cast-scroll. Castable by any class. See "Scroll of &lt;Spell&gt;" below |
| `requires_attunement` | bool | This is a magic item — its `bonus_ac`/`bonus_damage` only apply once `is_attuned` is true. `false` (default) = a normal item, unaffected by this system. See "Attunement" below |
| `is_attuned` | bool | Whether this specific item is currently one of the player's `GameState.MAX_ATTUNED_ITEMS` (3) attuned items. Only ever set by `GameState.attune_item()`/`unattune_item()`, both only reachable from `scripts/ui/attunement_picker.gd`. Meaningless when `requires_attunement` is `false` |
| `is_flammable` | bool | Whether this item burns to ash instead of landing when thrown onto a Fire Trap — see `scripts/world/CLAUDE.md`'s "Throwing an item onto a trap". Every `Type.SCROLL` item is flammable (set generically off `item_type` in `DungeonFloor._build_floor_item()`/`debug_panel._on_give_item()`, not a per-pool-entry key); every other item defaults `false`. Rotten Meat's Fire-Trap cooking is a separate, older special case, unaffected by this flag |

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
- **Topple** (Maul): on a melee **hit**, the target rolls `Enemy.resist_check(dc, true)` (CON-based) vs `dc = 8 + prof + STR mod` — same DC convention as Push/Grip of the Forest/Branching Strike. On a failed save the enemy is knocked **Prone** (`Enemy.apply_status("prone", 1)`, `scripts/entities/enemy.gd`) — the real 5e condition, not a turn-skip: melee attacks against it get ADV, ranged get DISADV, and it auto-stands at the top of its own next turn (consuming one point of movement) instead of losing the whole turn — see `scripts/entities/CLAUDE.md`'s "Conditions" section. Implemented in `player.gd._try_topple()`, called from the hit branch of `_bump_attack()` only (melee-only, right after the Branching Strike R3 push block). No damage is dealt, so there's no `[url=]` tooltip meta — just a plain colored log line (mirrors Push's "resists the shove" plain-text style for the same reason). Gated the same `weapon.weapon_mastery == "Topple" and stats.knows_mastery("Topple")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- **Sap** (Spear, thrown only): on a **thrown** hit, sets `Enemy.disadv_next_attack = true` — the same flag/consumption point World Tree's Grip of the Forest R3 already uses, so it fires as Disadvantage on the target's very next attack (whichever turn that happens to be next, i.e. its own next turn). Implemented in `PlayerThrowTool._throw_weapon()` (`scripts/entities/player_throw_tool.gd`), gated the same `weapon.weapon_mastery == "Sap" and stats.knows_mastery("Sap")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`). Sap only fires on a throw, never on a normal melee attack with the same Spear.
- **Vex** is also carried by the **Handaxe** (see "Dual-wielding" below) — same trigger/consumption rules as Short Bow/Rapier, just a second weapon that can grant it.
- **Nick** (Dagger): while dual-wielding two Light weapons (see "Dual-wielding" below) with either the Main Hand or the Off-hand weapon carrying Nick, the Off-hand swing is followed by one further attack this same turn — identical rules to the Off-hand swing itself (independent d20 roll, damage drops the ability modifier unless negative) — for a maximum of **3** attacks total (Main Hand, Off-hand, Nick bonus). Implemented as a second call to `player.gd._resolve_offhand_attack()` right after the first, from `_try_offhand_attack()`, gated the same `stats.knows_mastery("Nick")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`). Logged as its own `[color=cyan]Nick:[/color]` chat line (the shared `_resolve_offhand_attack(enemy, weapon, label)` function's `label` param defaults to `"Off-hand"` but is passed `"Nick"` for this second swing) so it's distinguishable from the ordinary Off-hand line even though the roll math is identical.
- **Slow** (Longbow): on a ranged hit that doesn't kill the target, sets `Enemy.slowed_turns = maxi(enemy.slowed_turns, 1)` — the same field/mechanism as stepping into Mud/Water (`enemy.gd`'s difficult-terrain handling): shaves one step off the target's next movement budget, does NOT affect its attack (see `scripts/entities/CLAUDE.md`'s `Enemy.slowed_turns` entry). No save/resist roll, unlike Push/Topple — always applies on a non-lethal hit. Implemented in `PlayerRanged.ranged_attack()` right after the Push `elif` branch, gated the same `weapon.weapon_mastery == "Slow" and stats.knows_mastery("Slow")` way as the others — live once the wielder knows that mastery via the Mastery Picker (`scripts/ui/mastery_picker.gd`).
- New masteries: add the glossary text to `WeaponTooltip.KEYWORD_GLOSSARY` (`scripts/items/weapon_tooltip.gd`, key = mastery name lowercased — shared by both `hud.gd` and `inventory_overlay.gd`, see "Unified weapon tooltip format" below) and implement the effect wherever it naturally hooks into combat (see Cleave for the melee-attack pattern, Vex for the per-turn-flag pattern, Push for the forced-movement pattern, Graze for the miss-damage pattern, Topple for the save-vs-status pattern, Sap for the thrown-attack pattern).

## Unified weapon tooltip format

Every `Item.Type.WEAPON` tooltip — the bottom quickbar (`hud.gd`) and the Inventory/bag overlay
(`inventory_overlay.gd`) — is built by one shared function, `WeaponTooltip.build(item) -> String`
(`scripts/items/weapon_tooltip.gd`, `WeaponTooltip extends RefCounted`, static-func-only), so the
two callers can never drift apart again. Fixed line order, generated purely from `Item` fields —
no per-weapon hand-written tooltip text:

1. **`[b]Name[/b] (Mastery)`** — name is always bold, default color. If the weapon has a
   `weapon_mastery`, it's appended in parens, colored **green** if `Stats.knows_mastery()` is true
   (the wielder currently knows it) or **red** if not — the mastery text itself carries the color,
   never the name. A weapon with no mastery at all (currently only the Torch) shows a bare name,
   no parens.
2. **Requirements** — one comma-joined line of everything the wielder might not meet, each
   individually red if unmet / white (not colored red) if met: `weapon_category` (Simple/Martial
   proficiency) and, for a Heavy weapon, the bare word `Heavy` — **not** `"STR 13+"`/`"DEX 13+"`
   text (direct owner correction: showing the number/stat inline was rejected — the requirement
   line should just name the property, "Heavy," and the exact stat+threshold only surfaces on
   hover). Both link to a glossary popup like every other keyword; Heavy resolves to one of two
   keys, `heavy_str` (melee) or `heavy_dex` (ranged), chosen by `item.is_ranged`, so the popup body
   itself names the specific stat this weapon needs instead of a stat-agnostic generic blurb.
3. **Damage + type** — `1dN[+bonus] [color=gray]Type[/color]`, from `damage_die_max`/`bonus_damage`/
   `damage_type`. (No current weapon has more than one damage-type instance; a future one would be
   `+`-joined here — `build()`'s own comment marks where.)
4. **Range** — `is_ranged` weapons only, bare `"normal/long"` (e.g. `"4/16"`), no extra text — see
   "Ranged weapons (current)" below for what `long_range` actually is. Melee/thrown weapons never
   get this line (their own reach/throw distance shows via the Reach/Thrown Properties tags
   instead).
5. **Properties** — alphabetical, one per line, each a single-token hoverable keyword (never wraps
   — a direct owner requirement; only the trailing free-form `item.description` line, appended by
   the caller after this whole block, is ever allowed to wrap): `Ammo(<ammo type>)`, `Finesse`,
   `Light`, `Reach`, `Thrown`, `Two-handed`, `Versatile(1dN)`. `Ammo(...)` is the one property with
   a value baked into the tag itself; `Versatile(1dN)` is the other — its `1dN` is always the die
   of the *other* (currently inactive) grip, since the active grip's own die already shows on the
   Damage line above (no grip-name text alongside it anymore, unlike the original
   `"Versatile (1dN two/one-handed)"` format). Thrown is a bare tag (no inline range numbers — see
   "Thrown weapons" below for where that number actually lives).

Everything below Properties (`item.description` as gray "additional info", `Uses: X/Y` durability,
Attunement, the gold-price line — `WeaponTooltip.format_price(item)` (`"Xg Ysp"`/`"Xg"`/`"Ysp"`,
`""` if fully unpriced), `#c9a227`, weapon-only for now, right-aligned just above the existing
"Ctrl: inspect" hint) is appended by each caller AFTER `WeaponTooltip.build()` returns, unchanged
from before — those lines are either generic across every item type or already positioned
per-caller, not weapon-tooltip-specific.

**Every weapon's `desc` field was trimmed** to remove information the structured format above now
shows on its own (mastery effect text, category/Heavy requirement text, Versatile/Thrown mechanic
text, durability text) — most melee/ranged weapons now have `desc = ""` (no "additional info" line
at all). The one exception is the **Torch**, whose light/FOV/Fire-bonus/burnout mechanic isn't
representable by any generic property or mastery, so it keeps a real (shortened) description.
`WeaponTooltip.KEYWORD_GLOSSARY` (moved here from the two former per-file duplicate consts) is the
single source of truth for every keyword popup body, including a new `"ammo"` entry.

**Every weapon is now priced** (real 5e PHB gold/silver costs, per the owner): Greataxe 30gp,
Rapier 25gp, Greatsword 50gp, Glaive 20gp, Maul 10gp, Quarterstaff 2sp, Spear 1gp, Handaxe 5gp,
Dagger 2gp, Javelin 5sp, Torch 10gp, Short Bow 50gp, Heavy Crossbow 120gp, Longbow 50gp, Arrow/Bolt
1gp per stack-of-6. Sub-gold prices use the new `Item.silver_value` field (see the field table
above) via the `"silver"` `ITEM_POOL`/`debug_panel.ALL_ITEMS` pool key, mirroring `"gold"`.

**Weapon tiers (implemented; design doc shipped and was deleted, `scripts/world/CLAUDE.md`'s
`ITEM_POOL` table and `scripts/entities/CLAUDE.md`'s "Barbarian class" section are now
authoritative)**: an explicit Tier 0-4 table re-derives every weapon's `fmin`/`fmax` from price +
dice + mastery utility instead of the old per-weapon ad hoc values. Two concrete `fmin` changes:
**Rapier** `1 → 4` (was priced/statted like a Tier-3 weapon — 25gp, Martial, 1d8 finesse — but
gated like a Tier-1 starter) and **Heavy Crossbow** `5 → 6` (cleaner Tier-4 boundary). **Greataxe**
is now a real `ITEM_POOL` Tier-4 entry (`fmin=6, fmax=10`) instead of Barbarian-only unreachable
starting gear — the Barbarian's starter was downgraded to a Tier-1 Spear + 2 thrown Handaxes (§6
option (a)), so the Greataxe is a genuine late-game find now, the only Cleave-mastery weapon in
the game. Enemy weapon drops and boss weapon loot (the doc's §4/§5) remain unbuilt — noted as
natural v2 extensions, not required for the tier table itself.

## Thrown weapons
`Item.is_thrown` + `range` (normal throw range) + `uses_max`/`uses_remaining` (currently only the Spear: Simple, Piercing, Versatile 1d6/1d8, `weapon_mastery="Sap"`, `range=3`, `uses_max=5`). Primed exactly like throwing a food item from the quickbar — **RMB a quickbar slot** (`hud.gd`'s `_on_slot_gui_input()` → `GameState.player_throw_primed`, no item-type filter) then **LMB a target tile** (`PlayerActions`/`player.gd` → `PlayerThrowTool.do_throw()`). `do_throw()` branches on `item.item_type == Item.Type.WEAPON and item.is_thrown` *before* the generic food/item-throw branch, dispatching to `PlayerThrowTool._throw_weapon(weapon, pos)`. Because priming only reads `GameState.player_quickbar` (not the equipment slots), a Spear must be sitting in the quickbar/bag to be thrown — an *equipped* copy in Main Hand is a separate `Item` instance and still attacks normally in melee.

**Attack roll**: uses the wielder's **melee** attack modifier (STR, or `max(STR,DEX)` if `is_finesse`) and melee weapon-proficiency bonus — never a DEX/ranged stat, even though it's thrown. **Range**: `Item.range` is the normal range (full accuracy); beyond that but within `Item.long_range` (a real fixed field — every current thrown weapon sets `long_range = 12`, i.e. `range × 4`, same ratio as the ranged-weapon table above) the throw still works but rolls with Disadvantage, and must be in current FOV (`is_tile_visible()`) — identical convention to ranged weapons' normal/long-range rule (`PlayerRanged.is_ranged_target_in_range()`/`ranged_shot_disadvantage()`), just off the melee modifier instead of DEX. Throwing at an empty tile (no `DungeonFloor.get_enemy_at(pos)`) auto-"misses" (no roll, no use lost) and just lands. The chat log line's roll breakdown uses tooltip meta kind `"thrhit"` (same param shape as melee `"hit"`/`"miss"` — `hud.gd._format_tooltip()`'s `kind` dispatch routes it to the existing `TooltipFormatters.fmt_hit_tooltip(params, false)`, no new formatter needed) and `"dmg"` for the damage breakdown (shared with every other attack type). The **Dagger** is Finesse as well as Thrown/Light — its thrown attack roll uses `max(STR, DEX)` like any other Finesse weapon, same as a normal melee swing with it would.

**Landing** (mirrors "Ammo items" above, with the thrown weapon's own rules): no enemy on the target tile → lands on the ground there as a normal pickupable floor item (`DungeonFloor.place_item_on_floor()`), **no use lost**. A **miss** OR a **non-lethal hit** against an enemy → embeds in the enemy — `Enemy.embedded_items: Array[Item]` (`scripts/entities/enemy.gd`) — instead of landing anywhere (`-1` use, `-2` on a nat-1 fumble miss, `0` on a nat-20 crit hit); no pickup while the enemy is still alive (a miss used to drop it as an immediately-pickable floor item at the enemy's tile — changed to embed-until-death so it behaves like ranged ammo instead of being trivially recoverable mid-fight). Enemy.**die()** is overridden to drop every item in `embedded_items` at its `grid_pos` (100% chance each, not the ranged-ammo 50%) right before freeing — every death call site (`player.gd._finish_kill()`, `companion.gd`, the trap/chasm death sites in `dungeon_floor.gd`) already ends with `enemy.die()`, so this single override covers an embedded Spear being recovered whenever/however that enemy eventually dies, not just from the throw that embedded it. A hit that also kills the enemy in the same throw still embeds first, so the override drops it immediately at the same tile.

**Durability**: `uses_remaining` decrements by 1 per throw, by 2 on a natural-1 critical fumble, and by 0 (no cost) on a natural-20 critical hit — `PlayerThrowTool._consume_throw_use(weapon, uses_lost) -> bool`, guarded by `GameState.invincible` like every other consumption site. Returns `true` (and logs `"Your <name> breaks!"` in the chat log, plus `GameState.remove_item(weapon)`) when durability hits 0 on this throw — in that case the weapon shatters instead of landing/embedding anywhere; callers check the return value before doing any landing/embedding. Ordinary melee attacks with the same weapon never touch `uses_remaining` — only throwing does. Tooltips show current durability as a left-aligned `Uses: X/Y` line (thrown weapons only) just above the "Ctrl: inspect" hint (bottom-left, always the last line), in both `inventory_overlay.gd`'s and `hud.gd`'s item tooltips.

**Mixed-durability stacking**: `GameState.add_item()` merges any weapon with `uses_max > 0` into an existing same-named stack regardless of durability (only `uses_max` itself must match, as a sanity check that it's really the same weapon type) — two Handaxes at different durability now share one inventory slot instead of landing in separate piles. Each unit's own `uses_remaining` is preserved via `Item.stack_uses: Array[int]` (`scripts/items/item.gd`), kept sorted ascending by `GameState._merge_into_stack(ex, incoming)` so index 0 — the **most-damaged unit** — is always "on top": it's what's mirrored into the stack's own `uses_remaining` (and therefore what the `Uses: X/Y` tooltip line shows) and what gets split off first. `Item.get_stack_uses() -> Array` returns one durability value per unit (falls back to repeating `uses_remaining` when `stack_uses` isn't materialized — e.g. a stack where every unit still shares the same durability, or a pre-this-feature save). `GameState.equip(item)`, `GameState.move_item()` (the drag-and-drop path — see "Equipment slots" below), and `PlayerThrowTool._throw_weapon(weapon, pos)` all split the most-damaged unit off a stack (`quantity > 1`) before acting, via the shared `GameState._should_split_for_equip(item)` / `_split_one_unit(item)` helpers (thin
delegators to the actual logic in `ItemStackSplit`, `scripts/items/item_stack_split.gd`) — pops `stack[0]` (lowest `uses_remaining`) into a fresh single-quantity `Item`, decrementing the original stack's `quantity` and re-syncing its `stack_uses`/`uses_remaining` to the next-most-damaged unit. `Item.stack_uses` is serialized in `to_dict()`/`from_dict()` like every other field. **Gotcha**: when rebuilding the remaining `stack_uses` array in `_split_one_unit()`, the "no leftover durability data" branch must assign an explicitly-typed empty `Array[int]` — a bare `[]` ternary literal assigned into the typed `stack_uses` property crashes at runtime (this broke throwing/equipping from any stack of exactly 2 units, since that's precisely when the remainder collapses to a single untyped-vs-typed edge case).

---

## Ranged weapons (current)
Every ranged weapon has two range values — `Item.range` (normal, full accuracy) and `Item.long_range`
(a real fixed field — **not** a per-weapon FOV lookup anymore). Beyond `range` but within
`long_range`, a shot still works but rolls with Disadvantage; beyond `long_range` it can't be taken
at all — the shot must also currently be in FOV (`is_tile_visible()`) to use that extended reach,
so blind-firing through unexplored fog is still impossible. `long_range` is always `range × 4` for
every ranged weapon in the current roster, matching 5e's own normal/long ratio (Short Bow 80/320 ft,
Heavy Crossbow 100/400 ft, Longbow 150/600 ft are all exactly 4×). See
`PlayerRanged.is_ranged_target_in_range()` / `ranged_shot_disadvantage()`
(`scripts/entities/player_ranged.gd`) — a ranged item that doesn't set `long_range` (`0`, none
exist today) falls back to the player's live FOV radius as its cap, the old behavior.
**Thrown weapons** (Spear/Handaxe/Dagger/Torch, `Item.is_thrown`) use the exact same
`range`/`long_range` mechanism for their own throw distance — see "Thrown weapons" below.

| Item | Bonus | Normal range | Long range | Ammo | Stat | Category | Mastery |
|---|---|---|---|---|---|---|---|
| Short Bow | +0 | 4 | 16 | Arrow | DEX | Simple | Vex |
| Heavy Crossbow | +0 | 4 | 16 | Bolt | DEX | Martial | Push |
| Longbow | +0 | 5 | 20 | Arrow | DEX | Martial | Slow |

Heavy Crossbow and Longbow are both also `is_heavy=true` (DEX 13+ or Disadvantage) and `is_two_handed=true` (cosmetic for a ranged weapon — see root `CLAUDE.md`'s note that `is_two_handed` doesn't block the ranged slot).

## Ammo items
`Item.ammo_item_name` on a ranged weapon names a separate stackable `Item` (`Item.Type.TOOL`, no combat stats of its own — currently **Arrow** for the Short Bow and Longbow, `sprites/items/ammo/arrow.png`, **Bolt** for the Heavy Crossbow, `sprites/items/ammo/arrow_gold.png` — a distinct color tier reused as a stand-in bolt sprite since no dedicated bolt art exists yet — and **Buckshot**, `sprites/items/misc/coin_gold.png` placeholder art, for future firearms (muskets etc.) — no gun weapon exists in `ITEM_POOL` yet, this is ammo-only infrastructure ahead of that) consumed 1-per-shot. The flying-projectile VFX during a ranged attack is separate and still uses `sprites/weapons/weapon_arrow.png` (`PlayerRanged.ARROW_SPRITE`) regardless of which ammo item was consumed. Found/looked-up by `item_name` match across the quickbar then bag (`PlayerAmmo.find_ammo_stack()`/`remove_ammo_stack()` in `scripts/entities/player_ammo.gd`) — a weapon with `ammo_item_name == ""` falls back to the legacy `consumes_on_ranged` pattern (decrements the weapon's own `quantity`, e.g. old Throwing Daggers) or fires with infinite ammo.

**Landing resolution** (`PlayerAmmo.resolve_ammo_landing(ammo_item, impact_pos)`, generalized — not arrow-specific):
- **WALL** tile impact → ammo destroyed, no pickup.
- **CHASM** tile impact → not placed on this floor; pushed onto `GameState.pending_chasm_items` and reappears at a random walkable tile on the **next floor down** (drained by `DungeonFloor._spawn_pending_chasm_items()` during `_load_floor()`).
- Any other floor tile → becomes a normal pickupable floor item via `DungeonFloor.place_item_on_floor()` (open-ground/wall shots via `PlayerRanged.ranged_attack_tile()` still call this — a miss into empty space is a genuine floor drop).
- **Miss against a still-alive enemy** → `PlayerRanged.ranged_attack()`'s miss branch rolls a 50% chance (`Rng.chance(0.5)`, matching the killing-hit odds below) to call `resolve_ammo_landing()` at the target's tile — otherwise the ammo is lost with no pickup.
- **Non-lethal hit on an enemy** → ammo is embedded in the (still-alive) enemy — no pickup at all.
- **Killing hit** → handled inside `player.gd._finish_kill(enemy, dropped_ammo)`: 50% chance the ammo drops at the corpse's tile (pickupable), 50% chance it's lost with the kill.

## Weapons (current, game-wide)
The only weapons in the game are the Barbarian's starting **Greataxe** (melee, two-handed, given via `GameState._give_barbarian_starting_items()` — never spawns as floor loot), **Short Bow**, **Heavy Crossbow** above (formerly named "Crossbow" — renamed as the first of a small family of ranged weapons sharing the same normal-range/FOV-long-range rule; 1d10 Piercing, Martial, requires **Bolt** ammo), **Longbow** (ranged, floor loot, 1d8 Piercing, Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Slow"`, normal range 5 (one tile further than Short Bow/Heavy Crossbow's 4), requires **Arrow** ammo (shared with Short Bow); floor loot `fmin`/`fmax` 5–10, sprite `weapons/bow.png` — see "Weapon masteries" above for what Slow does), **Rapier** (melee, 1d8 Piercing, Martial, `is_finesse=true` — attack/damage use `max(STR, DEX)` — `weapon_mastery="Vex"`; not Light, not Two-handed; floor loot `fmin`/`fmax` 1–10, `weapon_arrow.png`-free sprite `weapon_duel_sword.png`), **Greatsword** (melee, floor loot, 2d6 Slashing — approximated as a single `randi_range(2, 12)` roll, same simplified single-die-roll convention every other weapon uses rather than summing two separate d6 rolls — Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Graze"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_knight_sword.png` — no dedicated greatsword sprite exists yet), **Glaive** (melee, floor loot, 1d10 Slashing, Martial, `is_heavy=true`, `is_two_handed=true`, `is_reach=true`, `weapon_mastery="Graze"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_spear.png` — no dedicated polearm sprite exists yet — the first and so far only weapon to set `is_reach`), **Maul** (melee, floor loot, 2d6 Bludgeoning, Martial, `is_heavy=true`, `is_two_handed=true`, `weapon_mastery="Topple"`; floor loot `fmin`/`fmax` 3–10, sprite `weapon_big_hammer.png` — the first weapon with Bludgeoning damage type), and **Quarterstaff** (melee, floor loot, Simple, Bludgeoning, `weapon_mastery="Topple"`; 1d6 one-handed / 1d8 two-handed — `is_versatile=true`, `damage_die_min/max=1/6`, `versatile_die_min/max=1/8` at rest; floor loot `fmin`/`fmax` 1–10, sprite `weapon_green_magic_staff.png` — no dedicated plain-staff sprite exists yet — the first Versatile weapon, see "Versatile weapons" below), **Spear** (melee, floor loot, Simple, Piercing, `weapon_mastery="Sap"`; also Versatile 1d6/1d8 like the Quarterstaff, plus `is_thrown=true`, `range=3` (normal throw range, FOV beyond that at Disadvantage), `uses_max=5`; floor loot `fmin`/`fmax` 1–10, sprite `weapon_spear.png` (shared with Glaive — no dedicated javelin/spear-only sprite exists yet) — the first Thrown weapon, see "Thrown weapons" below), **Handaxe** (melee, floor loot, Simple, Slashing, 1d6, `weapon_mastery="Vex"`, `is_light=true` — the first Light weapon; also `is_thrown=true`, `range=3`, `uses_max=5` like the Spear; floor loot `fmin`/`fmax` 1–10, sprite `weapon_throwing_axe.png` — dual-wielding a second Light weapon in the Off-hand fires a bonus attack each melee swing, see "Dual-wielding" below), **Dagger** (melee, floor loot, Simple, Piercing, 1d4, `is_finesse=true`, `is_light=true`, `weapon_mastery="Nick"`; also `is_thrown=true`, `range=3`, `uses_max=5` like the Handaxe; floor loot `fmin`/`fmax` 1–10, sprite `weapon_knife.png` — see "Weapon masteries" above for what Nick does), **Javelin** (melee, floor loot, Simple, Piercing, 1d6, `weapon_mastery="Slow"`; not Light, not Finesse, not Versatile — a plain Simple melee/thrown weapon; also `is_thrown=true`, `range=3`, `long_range=12`, `uses_max=5` like the other thrown weapons; floor loot `fmin`/`fmax` 1–10, sprite `weapon_spear.png` (shared with Spear/Glaive — no dedicated javelin sprite exists yet); 5sp — the cheapest weapon in the game. Distinct from the same-named `"thrown_weapon"` pool key on Orc Warrior/Ogre's own `ENEMY_POOL`/`BOSS_POOL` entries (`scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema") — that's a separate enemy-attack mechanism building its own dropped `Item` from the enemy schema's own fields, unrelated to this `ITEM_POOL` entry, and the two happening to share a name is coincidental, not a shared code path), and **Torch** (melee, floor loot, Simple, Bludgeoning, 1d4, `is_torch=true`, **not** Light — equippable in Off-hand like a Shield without dual-wielding; also `is_thrown=true`, `range=3`, `uses_max=3` (fewer uses than the other thrown weapons); no mastery; floor loot `fmin`/`fmax` 1–10, sprite `weapon_torch.png` — no dedicated torch sprite exists yet, this is a placeholder path — see "Torch" above for the click-to-light mechanic, the thrown Fire bonus, and the passive light bubble). All physical melee weapons that used to spawn as floor loot (Rusty/Short/Regular/Knight/Golden/Lavish Sword) and **Throwing Daggers** have been removed from `DungeonFloorData.ITEM_POOL`, `debug_panel.ALL_ITEMS`, and boss loot (`dungeon_floor.gd drop_boss_loot()`, now potions-only). Their sprite assets live under `res://sprites/weapons/_unused/` (unused, not deleted) in case they're reintroduced later.

---

## Torch
`Item.is_torch` (currently one item, "Torch" — Simple, 1d4 Bludgeoning, no mastery, **not** Light) starts unlit. **Click (not drag) while equipped** — Main Hand OR Off-hand — lights it: `inventory_overlay.gd._finish_drag()`'s "released back in the same slot it started from" branch (the same click-vs-drag detection Versatile-grip toggling uses, see below) calls `GameState.light_torch(item)` whenever the slot holds an unlit, unburnt Torch, and immediately forces an `update_fog()` call for instant FOV feedback (lighting is a free action, outside the normal per-turn fog refresh). A torch sitting in the quickbar/bag can't be lit — it must be equipped first, mirroring the Versatile toggle's own equipped-slot-only scope.

**Off-hand equipping without dual-wielding**: `inventory_overlay.gd._fits_slot()`'s `"hand2"` branch special-cases `item.is_torch` to always accept it (same treatment as `Item.is_shield` — see "Shields" below), independent of whether Main Hand holds a Light weapon. Deliberately **not** Light (`is_light == false`): `player.gd._try_offhand_attack()`'s bonus-swing gate checks `main_hand.is_light`/`off_hand.is_light` before ever firing the dual-wield Off-hand attack (see "Dual-wielding" below), so a Torch in either hand never triggers it — it occupies a hand (Main or Off) purely for its light/Fire-bonus mechanics, never as a second weapon.

Once lit, `torch_turns_remaining` starts at 100 and ticks down by 1 once per real player turn
(`player.gd._on_turn_started()`, same "100-turn duration" shape as Expeditious Retreat/Fog Cloud/
Invisibility) — **regardless of where the lit Torch currently is**: equipped, sitting in the
quickbar/bag, lying on the floor, or embedded in a live enemy all tick down identically. The
ticker is split across two sweeps run every real turn: `player.gd`'s own block covers
`GameState.equipment["melee"]`/`["hand2"]` + `GameState.player_quickbar`/`player_inventory`
(GameState-only data), and `DungeonFloor.tick_torches()` covers every floor item + every live
enemy's `Enemy.embedded_items` (needs `_floor_items`/`get_all_enemies()`, which live on
`DungeonFloor`). While **equipped and lit**: **+1 FOV** in either hand
(`dungeon_floor.gd`'s FOV formula gains `+ (1 if GameState.has_lit_torch_equipped() else 0)` — see
`scripts/world/CLAUDE.md`'s "FOV" section) and, **only when wielded in Main Hand**, every hit with
`_bump_attack()`'s primary swing also deals a second, independent 1d4 Fire damage instance
(Off-hand/Cleave/Opportunity-Attack swings never get it — a documented scope limit, matching the
project's existing precedent of not extending every bonus to every attack path) — the exact "one
hit, two damage-type instances" shape `scripts/entities/CLAUDE.md`'s damage-stacking rule
documents (mirrors Zealot's Judgement Day). **Unequipping** a lit Torch pauses nothing about its
burn — only the FOV/melee-Fire bonuses stop (both computed live off the equipment slots) — but a
lit Torch lying on the floor or embedded in an enemy instead grants a passive radius-2 light bubble
of its own, see below.

Reaching 0 calls `GameState.burn_out_torch(item)`: `torch_lit = false`, `torch_burnt = true`, and the SAME `Item` instance is renamed `"Burnt Torch"` (no second `ITEM_POOL` entry) — it can never be relit (the click-to-light check gates on `not torch_burnt`).

**Status tray buff**: while any Torch is lit and equipped, `hud.gd._update_status_icons()` adds a `"torch"` entry (icon = the lit torch's own `icon_path`, orange fallback tint) whose hover tooltip (`status_tooltips.gd`) shows turns remaining and whether the Fire bonus applies (Main Hand) — see `scripts/ui/CLAUDE.md`'s status tray section.

**Thrown** (`is_thrown=true`, `range=3`, `uses_max=3` — fewer uses than Spear/Handaxe/Dagger's 5):
primed and thrown exactly like any other thrown weapon (`scripts/items/CLAUDE.md`'s "Thrown
weapons" above) — the attack roll uses the wielder's **melee/STR** modifier (or `max(STR,DEX)` if
ever made Finesse — it isn't), same as every other thrown weapon, no special-casing needed. Base
damage is the normal 1d4 Bludgeoning; **if lit**, a thrown hit also deals a second, independent 1d4
Fire damage instance (`PlayerThrowTool._throw_weapon()`, mirrors the Main-Hand melee Fire bonus
exactly — own `take_typed_damage()` call, own floater, own `dmg:` tooltip segment appended to the
same log line). Thrown at empty ground → lands as a normal floor item (unchanged generic thrown
behavior). Thrown at an enemy, on a miss or non-lethal hit → embeds in `Enemy.embedded_items`
(unchanged generic thrown-weapon embedding — no Torch-specific code needed there at all), dropped
at `grid_pos` when that enemy eventually dies (`Enemy.die()`'s existing override). **A lit torch
embedded in an enemy keeps burning them every round it stays lodged and lit** — `DungeonFloor.
tick_torches()` (`scripts/world/CLAUDE.md`), on top of ticking `torch_turns_remaining` down, rolls
a fresh independent 2d4 Fire hit against that enemy each real turn (same rate as a creature
standing on a burning door — `DungeonFloor.tick_fire_damage_for()`), with the usual floater/log
line/kill handling; stops the moment the torch runs out and burns out. A lit torch merely lying on
the floor does not damage anything standing on its tile — this is specifically about one still
lodged in a living target.

**Passive radius-2 light bubble** (floor/embedded only, distinct from the equipped +1 FOV bonus):
`DungeonFloor._compute_torch_light_tiles()`, called from `update_fog()` every fog recompute (no
persistent light-source registry — see the design note below), sweeps every `_floor_items` tile
and every live enemy's `embedded_items` for a lit-and-unburnt Torch and unions a
`GameState.TORCH_LIGHT_RADIUS` (2) shadowcast into `_visible_tiles`, centered on the torch's own
floor tile or (for an embedded one) its carrying enemy's **current** `grid_pos` — so an embedded
lit Torch's bubble moves with the enemy across turns for free, with zero dedicated tracking state.
`_update_torch_light_glow()` tints every lit tile with a fixed warm-orange tone (a Torch's flame
isn't randomized per-cast the way the Light cantrip's color is), same pooled-`Sprite2D` convention
as `_update_light_source_glow()` but its own sprite pool so the two light sources never contend.
**Deliberately not a generalization of the Light cantrip's single mutable
`light_source_pos`/`light_source_item` slot** — that pattern requires explicit set/clear calls at
every event (cast, pickup, rest, death); a lit Torch's bubble instead needs zero add/remove/cleanup
code anywhere (throw, pickup, drop, die, burnout all "just work") because it's recomputed fresh
from scratch every `update_fog()` call, the same "compute live" philosophy as
`GameState.has_lit_torch_equipped()`.

## Versatile weapons
`Item.is_versatile` + `versatile_die_min/max` (currently only the Quarterstaff, 1d6 one-handed / 1d8 two-handed). Left-clicking the Main Hand (`"melee"`) equipment slot in `inventory_overlay.gd` **without dragging** (press+release inside the same slot, detected in `_finish_drag()`) calls `GameState.toggle_versatile_grip()` when the equipped item is versatile: swaps `damage_die_min/max` with `versatile_die_min/max` (so the "other" grip's die is always sitting in `versatile_die_min/max`), flips `is_two_handed`, and calls `recalculate_stats()` — no turn cost, purely a grip switch. `inventory_overlay.gd._refresh()` gives the Main Hand slot a highlighted gold border (`border_color`/width bumped) while gripped two-handed, and the tooltip's Versatile keyword line shows the current grip and the die you'd get by switching. Flipping `is_two_handed` also drives the existing Off-hand ✕ block indicator for free (same mechanism as any other two-handed weapon).

## Item interaction menu (RMB) / LMB-equip

Unified rule across both the bottom quickbar (`hud.gd`) and the Inventory/bag overlay
(`inventory_overlay.gd`): **LMB (click, not drag)** on an equippable item (`Item.Type.WEAPON` or
`Item.Type.ARMOR` — covers plain weapons, Shields, and the Torch) always **equips** it; Equip is
never offered anywhere else. **RMB** offers every *other* interaction the item has — Throw and
**Drop are universal** (every item can be thrown or dropped), plus Light for an unlit/unburnt
Torch, Read for a Scroll, Drink for a Potion, Prime for Thief Tools/Empty Bottle, and Learn for a
Scroll whose spell a Wizard doesn't yet know (see "Learn (Wizard-only RMB scroll interaction)"
below). `ItemInteractions.get_available_interactions(item) -> Array[String]`
(`scripts/items/item_interactions.gd`, static-func-only helper) computes that list — every item
now returns at least `["throw", "drop"]`, so RMB always spawns `scripts/ui/item_interaction_menu.gd`'s
`ItemInteractionMenu` (a small transient stacked-button popup, not a blocking modal — dismiss by
clicking elsewhere or Esc) anchored near the slot/cursor, and picking an entry dispatches it (the
`interactions.size() == 1` auto-resolve branch in both dispatch call sites is now unreachable dead
code kept only because a future item type could theoretically drop below 2 entries — harmless to
leave). **Food goes through the same system as everything else**: eating Food currently does
nothing useful (see "Rations / long rest" below), so a Food item's RMB menu is just `["throw",
"drop"]` like any other non-specialized item, no hardcoded bypass.

**Throwing a Potion shatters it**: unlike every other thrown item (which lands intact, pickable),
`PlayerThrowTool.do_throw()` special-cases `Item.item_type == Item.Type.POTION` (checked before the
trap-landing branch) to `_shatter_potion(item, pos)` instead of `place_item_on_floor()` — potions
are glass, so a thrown one never survives the landing, on a trap tile or otherwise. Whatever
occupies the target tile takes the effect: a heal-type potion (`heal_dice_count`/`heal_amount` set
— currently Health Potion) heals that target for the same roll a player drinking it would get (no
CON mod — that's specifically a player benefit from `use_item()`); a potion with no applicable
effect (currently Strength Potion — its `str_bonus` has no enemy-side analogue) just shatters
harmlessly. An empty target tile also just shatters, no effect, no item created — there's no floor
loot before OR after a potion shatters (not even an Empty Bottle) — the whole `Item` (one unit off
the stack, `GameState.consume_one()`) is simply gone. Extending this to a future harmful potion
(e.g. Poison) just needs a new branch in `_shatter_potion()` reading that potion's own field(s),
mirroring how `heal_dice_count`/`heal_amount` are read today — no new `Item` field required for
"is this glass," since gating on `item_type == Item.Type.POTION` already covers every potion, present or future.

**Drop** (`"drop"`, `GameState.drop_item(item)`): drops the item's entire stack (whatever
`Item.quantity` currently is — e.g. a stack of 5 Healing Potions drops as one pile, not
one-at-a-time) onto the player's own tile via `DungeonFloor.place_item_on_floor()` **fully intact
— Drop never breaks a Potion**, unlike Throw above; removes it from
the quickbar/bag (`remove_item()`), and costs 1 turn (`TurnManager.begin_player_action()`/
`on_player_action_complete()`, unconditional — unlike the Shield's turn-cost, dropping is never a
free action). Quickbar/bag items only — there is no Drop entry point for an equipped item (RMB on
an equipment slot in `inventory_overlay.gd` still unequips instead, see `_right_click()`'s
`source == "equipment"` branch); unequip first, then Drop from the bag.

`ItemInteractions.needs_world_targeting(id, item) -> bool` flags which resolved interactions arm a
follow-up world click (`"throw"` and `"prime"` always — Thief Tools/Empty Bottle both target an
adjacent tile; `"read"` only when the scroll casts via `Item.scroll_spell_id`, not when it merely
teaches via `taught_spell_id`) — `inventory_overlay.gd._dispatch_item_interaction()` closes the
overlay first whenever this is true, so picking e.g. Throw or Prime from inside the bag drops
straight into "aim at the world" mode instead of resolving invisibly behind a still-open panel.
`hud.gd`'s quickbar dispatcher never needs this (no overlay to close).

Both dispatchers share the same `match id:` body: `"throw"` emits `GameState.player_throw_primed`;
`"light"` calls `GameState.light_torch(item)` + `update_fog()` (works on ANY Torch reference, not
just an equipped one — a deliberate widening past the old equipped-slot-only click gate, consistent
with "Torch burns everywhere"); `"learn"` calls `GameState.begin_scroll_learn(item)` (see below);
every other id (`"read"`/`"drink"`/`"prime"`) falls through to
`GameState.use_item(item)`, which already implements exactly that non-equip primary action for
SCROLL/POTION/TOOL — no duplicated logic. `inventory_overlay.gd._finish_drag()`'s old
click-no-drag-on-an-equipped-slot Torch-light branch was removed (Light moved to the RMB menu); a
new click-no-drag-on-a-**bag**-slot branch calls `GameState.equip(_drag_item)` for any
WEAPON/ARMOR item, mirroring the quickbar's pre-existing LMB-equips-via-`use_item()` behavior
(quickbar LMB needed no changes — `GameState.use_item()`'s `WEAPON`/`ARMOR` branch already just
calls `equip()`). The Main-Hand versatile-grip-toggle click (see "Versatile weapons" above) is
unrelated and unchanged.

## Equipment slots
`GameState.equipment` dict keys: `"melee"`, `"hand2"`, `"ranged"`, `"armor"`, `"boots"`, `"gloves"`, `"head"`, `"trinket"`. `equip()` routes `is_ranged` items automatically to `"ranged"`; melee weapons always go to `"melee"` (Main Hand) — every auto-equip path (pickup, starting gear, debug give-item), not just explicit drag equips. Inventory overlay labels `"melee"`/`"hand2"`/`"ranged"` as Main Hand/Off-hand/Ranged and enforces slot type. `"hand2"` (Off-hand) accepts non-weapon items freely; a weapon is only accepted if it's Light, not ranged, **and** Main Hand also currently holds a Light weapon (`inventory_overlay.gd._fits_slot()`) — dragging a non-Light weapon there, or a Light weapon while Main Hand isn't Light, is rejected — **except** the Torch (`Item.is_torch`), always accepted here regardless of Main Hand, same special-case treatment as a Shield (see "Torch" above). `equip()` never auto-routes here (only explicit drag). See "Dual-wielding" below for what equipping a second Light weapon actually does in combat. When Main Hand holds a two-handed weapon, the Off-hand slot shows a red ✕ overlay (purely visual, `inventory_overlay.gd._refresh()`, does not additionally block the drag — the Light checks above are what actually gate it).

**Dragging a stack**: `GameState.move_item()` (the drag-and-drop path — `inventory_overlay._do_move()` is the only caller) special-cases dropping onto an `"equipment"` destination: if the dragged item is a stacked durability weapon (`_should_split_for_equip()`, currently Handaxe/Dagger/Spear — anything with `uses_max > 0` and `quantity > 1`), only a single unit is equipped (`_split_one_unit()`); the rest of the stack stays exactly where it was instead of the whole pile moving into the slot. Whatever was previously in that equipment slot goes to the first empty quickbar/bag slot (`_add_to_bags_silent()`, same as `equip()`'s replaced-item handling) rather than swapping back into the drag's source slot. This is what makes it comfortable to equip just one Handaxe/Dagger into the Off-hand out of a full stack of 5.

## Attunement

`Item.requires_attunement`/`is_attuned` — a magic item can be equipped/carried completely freely
(no gate on `equip()`, no separate equipment slot) but only contributes its `bonus_ac`/
`bonus_damage` once it's one of the player's `GameState.MAX_ATTUNED_ITEMS` (3) currently attuned
items — `GameState._item_bonus_active(item) -> bool` (`not requires_attunement or is_attuned`,
delegating to `AttunementRules.item_bonus_active()` — `scripts/items/attunement_rules.gd`, which
also holds `MAX_ATTUNED_ITEMS`/`attunable_items()`/`attuned_count()`/`can_attune()`'s actual logic)
is the single chokepoint `recalculate_stats()` checks before folding either bonus in, so an unattuned
magic weapon/armor still occupies its slot and still shows in every UI exactly like a mundane
item, it just doesn't grant its numbers yet. **No concrete magic items ship with this pass** —
every current `ITEM_POOL`/`WEAPON_POOL` entry still has `requires_attunement == false` (the
default), so this is pure infrastructure until a future item sets the flag; a new magic item just
needs `"requires_attunement": true` in its pool entry like any other bool field (see "Adding a new
item" below).

**Changeable only at a long rest** (direct owner request — mirrors the Mastery Picker's own
"reselect after a long rest" gating): `GameState.attune_item(item)`/`unattune_item(item)` are only
ever called from `scripts/ui/attunement_picker.gd`, itself only reachable from the long-rest hub
(`scripts/ui/mastery_reselect_prompt.gd`, spawned by `player.gd` right after `GameState.long_rest()`
completes — see `scripts/ui/CLAUDE.md`'s "Long-rest hub" section). There is no other UI path to
attune/unattune an item — dragging a magic item around the inventory, equipping it, or unequipping
it never touches `is_attuned`.

`GameState.attunable_items() -> Array[Item]` scans quickbar + bag + every equipment slot for
`requires_attunement == true` items (attuned or not — the picker lists both states).
`attuned_count()` sums how many of those are currently `is_attuned`. `can_attune(item) -> bool`
hard-blocks at `MAX_ATTUNED_ITEMS`, same silent-no-op-at-cap feel as `can_select_mastery()`.

**Visual indicator**: an attuned item's slot gets a blue border (`Color(0.3, 0.55, 1.0)`, 3px)
instead of the default gray in both `inventory_overlay.gd` (`_update_slot()`, bag/quickbar/every
equipment slot) and its own dedicated row styling in `attunement_picker.gd`. Item tooltips (both
`inventory_overlay.gd` and `hud.gd`'s quickbar tooltip) show a blue `"Attuned"` or `"Requires
Attunement (set during a Long Rest)"` line right after the item's description whenever
`requires_attunement` is true — the only place a plain unattuned magic item visibly differs from a
mundane one.

## Enhance debug tool (F3 → "Enhance Item (Slot 1)")

`GameState.enhance_quickbar_slot1_item()` — a debug-only "+1 weapon/armor" concept, deliberately
**not** a lootable `ITEM_POOL` variant (direct owner request: this button takes an item the player
already has and enhances it in place, it doesn't author new rare drops). Each press bumps whatever
sits in item-quickbar slot 1 (index 0): a `Item.Type.WEAPON` gets `bonus_damage += 1` (already the
single field that flows into BOTH the attack roll and the weapon's own physical damage instance at
every player attack site — see root `CLAUDE.md`'s combat-roll table and the "damage stacking" rule
above — and is already named "weapon +N"/"Weapon enhancement" in the hit/dmg hover tooltips, so a
+N weapon's bonus is visible on hover with zero new tooltip plumbing); an `Item.Type.ARMOR` item
(covers both real body armor AND the Shield, `Item.is_shield`, since Shield is also `Type.ARMOR`)
gets `bonus_ac += 1` (already folded in generically by `GameState.recalculate_stats()`'s
per-equipment-slot loop). Any other item type logs "can't be enhanced" and is a no-op. **Only ever
touches the weapon's own base physical damage instance** — a secondary same-hit damage instance
with its own distinct type (Torch's Fire, Hunter's Mark's Force, Judgement Day's Radiant) is a
separate `CombatMath.build_damage_instance()` call that never reads `bonus_damage`, so enhancing a
weapon never inflates those. `Item.enhancement_level` (int, persisted) is a display-only counter —
`item_name` is rewritten to `"<base name> +N"` on every press (`GameState._enhancement_base_name()`
strips a prior `" +N"` suffix first, so repeated presses read `+1` → `+2` → `+3` instead of
stacking suffixes).

## Shields
`Item.is_shield` (currently one item, "Shield" — flat `bonus_ac = 2`, `res://sprites/items/shields/wood.png`) is an `Item.Type.ARMOR` item that `GameState.equip()` routes to `"hand2"` (Off-hand) instead of `"armor"` — the only ARMOR-type item that doesn't land in the Armor slot. Its `bonus_ac` flows into AC through `recalculate_stats()`'s existing generic per-slot loop (see root `CLAUDE.md`'s combat-roll table) — no special-cased AC code needed. Gated by `Stats.proficient_shields` (`scripts/entities/CLAUDE.md`'s "Weapon proficiency flags" — Barbarian/Ranger only) via `GameState.can_equip_shield(item) -> bool`, checked at every entry point that can place a Shield into `"hand2"`: `equip()`, `move_item()` (drag), and `inventory_overlay.gd._fits_slot()` (drag preview gate). Lacking proficiency, or having a two-handed Main Hand weapon equipped, blocks equipping outright (unlike weapon proficiency, which just drops a bonus) — `GameState.log_shield_equip_blocked(item)` logs which reason applied. A two-handed Main Hand weapon (via `equip()`/`move_item()`'s existing `_auto_unequip_offhand()`, or `toggle_versatile_grip()` switching to a two-handed grip) auto-kicks an equipped Shield back to the bag, same as it would any other Off-hand item. **Blocks all spellcasting while equipped** — `PlayerSpellcasting._shield_blocks_casting()` gates the top of `begin_cast()`, `cast_direct()`, and `on_scroll_primed()` (`scripts/entities/player_spellcasting.gd`). **Equip/unequip costs 1 turn** (the one exception to "equip is always a free action" — see `scripts/autoloads/CLAUDE.md`'s Equipment slots section): `equip()`/`unequip()`/`move_item()` each wrap the mutation in `TurnManager.begin_player_action()`/`on_player_action_complete()` when a Shield is entering or leaving `"hand2"` (including being displaced by a different item dragged into an occupied slot) AND `TurnManager.phase == WAITING_FOR_INPUT` (guards against double-costing if ever called outside a normal player turn). **Ends Mage Armor**: equipping a Shield clears `Stats.mage_armor_active` exactly like equipping real Armor does — 5e RAW counts a shield as worn armor for this purpose even though it lives in `"hand2"`, not `"armor"` — checked independently in both `equip()` and `move_item()` (see `scripts/entities/CLAUDE.md`'s "Mage Armor").

## Body armor
`Item.armor_category` (`Item.ArmorCategory` enum: `NONE`/`LIGHT`/`MEDIUM`/`HEAVY`) + `base_ac` +
`dex_cap` (`-1` = unlimited/Light, `N` = capped at `+N`/Medium, `0` = none at all, even negative/
Heavy) + `str_requirement` (Heavy only) + `stealth_disadvantage` — a real `Item.Type.ARMOR`,
non-shield item landing in the `"armor"` slot. 12 entries in `ITEM_POOL`/`debug_panel.ALL_ITEMS`:
Light (Padded 11+DEX w/ stealth disadv, Leather 11+DEX, Studded Leather 12+DEX), Medium (Hide
12+DEX≤2, Chain Shirt 13+DEX≤2, Scale Mail 14+DEX≤2 w/ stealth disadv, Breastplate 14+DEX≤2, Half
Plate 15+DEX≤2 w/ stealth disadv), Heavy (Ring Mail 14 w/ stealth disadv, Chain Mail 16/STR 13 w/
stealth disadv, Splint 17/STR 15 w/ stealth disadv, Plate 18/STR 15 w/ stealth disadv) — no
dedicated armor sprites exist yet, every entry placeholder-reuses `materials/plate/iron.png` or
`PlateGold.png`. **`"desc"`/`Item.description` is empty for every armor entry that has nothing to
say beyond what `ArmorTooltip.build()` already renders as its own structured lines** (Type/AC/
Disadvantage-on-Stealth/Don-Doff, `scripts/items/armor_tooltip.gd`) — `hud.gd`'s qbar tooltip and
`inventory_overlay.gd`'s hover both append `item.description` right after `ArmorTooltip.build()`'s
output (guarded on `not item.description.is_empty()`), so a `"desc"` that repeats those same facts
in prose renders the same information twice. Only Chain Mail/Splint/Plate Armor's `"Requires N
STR."` and the Shield's proficiency/two-handed/spellcasting caveat carry real `"desc"` text — both
are facts `ArmorTooltip.build()` never renders itself (STR requirement only ever shows up
reactively in the equip-blocked chat message, `GameState.log_armor_equip_blocked()`). Any new
armor/shield `ITEM_POOL` entry should follow the same rule: leave `"desc"` empty unless it says
something the tooltip's own structured lines don't already cover. `Stats.recalc_ac()` (`scripts/entities/CLAUDE.md`) folds `base_ac`/`dex_cap` in
ahead of every unarmored-defense formula (real body armor always wins over Barbarian/Monk/Mage
Armor while worn). Gated by `GameState.can_equip_armor()` — `Stats.proficient_light_armor`/
`proficient_medium_armor`/`proficient_heavy_armor` (Barbarian/Ranger: Light+Medium only, no class
trains Heavy) and `str_requirement`, both hard blocks (not just a dropped bonus), mirroring
`can_equip_shield()`'s own shape; `GameState.log_armor_equip_blocked()` reports which reason.

**Equip/unequip/swap takes real turns, not a free action**: `GameState.ARMOR_CHANGE_TURNS`
(`NONE`→1, `LIGHT`→5, `MEDIUM`→10, `HEAVY`→15), keyed by the **heavier** of the item entering and
the item leaving the `"armor"` slot (`GameState._armor_change_turns()`) — swapping Leather for
Plate costs 15 turns, not 5. `GameState.begin_armor_change(new_item, old_item)` is the entry point
`equip()`/`unequip()`/`move_item()` all route "armor"-slot mutations through instead of their
normal instant swap; neither item is physically moved yet (mirrors `begin_scroll_learn()`'s "no
consumption until it finishes" precedent) — the slot swap happens in `complete_armor_change()`.
Ticked in `player.gd._on_turn_started()` exactly like scroll-learning: one real turn per tick,
auto-waiting (`PlayerActions.do_rest_wait_turn()`) until `armor_change_turns_remaining` hits 0, and
**interrupted outright** (no Continue/Abort prompt — nothing's changed yet) per `Player._rest_interrupted()`'s
tolerance rule (`scripts/entities/CLAUDE.md`'s "Multi-turn action interrupts" section) —
`GameState.cancel_armor_change(true)`. While `GameState.armor_change_active`, no
second equip/unequip/swap can start (`equip()`/`unequip()`/`move_item()` all early-return). Ending
Mage Armor on real armor landing (see "Mage Armor" in `scripts/entities/CLAUDE.md`) is checked
inside `complete_armor_change()`, at the moment the swap actually resolves.

**Stealth interaction**: `GameState.player_has_stealth_disadvantage()` (reads the currently-
equipped `"armor"` item's `stealth_disadvantage` flag) adds a Disadvantage source to the Stealth-
vs-Passive-Perception check (`Player._resolve_stealth_check()`) alongside the existing ADV sources
(stillness, Zealous Presence, a SLEEPING observer) — net ADV/DISADV cancel per the house rule,
same as every other roll in this codebase. See `scripts/entities/CLAUDE.md`'s "Stealth & Surprise
Attacks".

## Unified armor tooltip format

`ArmorTooltip.build(item) -> String` (`scripts/items/armor_tooltip.gd`, `ArmorTooltip extends
RefCounted`, static-func-only — mirrors `WeaponTooltip`'s shape) is the single shared builder for
both body armor (`Item.armor_category != NONE`) and the Shield (`Item.is_shield`), used identically
by `hud.gd`'s quickbar hover and `inventory_overlay.gd`'s bag/equipment hover.
`ArmorTooltip.is_armor_item(item) -> bool` is the gate both callers check (after the
`Item.Type.WEAPON` branch) before calling `build()` instead of falling through to the bare-name
default. Fixed line order, generated purely from `Item` fields:

1. **`[b]Name[/b]`** — always bold, no mastery-style parenthetical (armor has no mastery system).
2. **Type** — `"Light Armor"`/`"Medium Armor"`/`"Heavy Armor"` (from `armor_category`) or
   `"Shield"` (`is_shield`).
3. **`AC: N`** — body armor shows `base_ac`, plus `" + DEX"` (unlimited, Light) or
   `" + DEX (max +N)"` (`dex_cap > 0`, Medium) or nothing at all (`dex_cap == 0`, Heavy). Shield
   shows `"AC: +N"` off `bonus_ac` instead (a flat bonus, not a base).
4. **`Disadvantage on Stealth`** (orange, hoverable `stealth_disadv` glossary keyword,
   `WeaponTooltip.KEYWORD_GLOSSARY` — glossary is the one shared mechanism, not weapon-specific) —
   only when `stealth_disadvantage` is true.
5. **`Don/Doff: N turn(s)`** (gray) — `GameState.ARMOR_CHANGE_TURNS[armor_category]` for body armor
   (5/10/15 for Light/Medium/Heavy), always `1` for a Shield (its own fixed equip-cost rule, see
   "Shields" above) — the real-turns-not-free-action cost from "Body armor" above, made visible on
   hover instead of only discoverable by actually equipping.

Description, Attunement, price, and the "Ctrl: inspect" hint are appended by the caller AFTER this
block, unchanged from the weapon-tooltip split (`scripts/items/CLAUDE.md`'s "Unified weapon
tooltip format" above) — those lines are generic across every item type, not armor-specific.

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
DungeonFloorData.ITEMS_PATH   = "res://sprites/items/"           # subfolders: food/, potions/health/, potions/mana/, misc/, materials/, shields/, weapons/, etc. — all snake_case
DungeonFloorData.OBJECTS_PATH = "res://sprites/objects/"  # crate.png, doors/leaf_closed.png, doors/leaf_open.png live; everything else unreferenced, under _unused/ (same convention as sprites/items/ below)
```
(`debug_panel.gd` keeps its own local `WEAPONS_PATH`/`ITEMS_PATH` constants — unrelated duplicates used only for its Give Item icon lookups, not part of this refactor.)

**Item sprite naming convention (auto-triage rule):** applies identically to `sprites/objects/`
(props/doors/etc., routed through `OBJECTS_PATH` the same way). Every file under `sprites/items/` is
snake_case, one folder per category. When an item has multiple material/size tiers of the
*same* sprite (e.g. a shield in wood/iron/gold, a potion in small/medium), group them into
their own subfolder and name each file only by its variant — `shields/wood.png`,
`shields/iron.png`, `shields/gold.png`, not `shields/wood_shield.png` etc. Two-tier
base+upgrade families use `iron.png` (base) + `gold.png` (upgrade) unless the actual art is
visibly a different material (check by opening the PNG, don't guess from the filename alone).
Any sprite with **zero current code reference** (nothing in `ITEM_POOL`/`ALL_ITEMS`/`icon_path`
points at it) lives under `sprites/items/_unused/`, mirroring the same category/variant
folder layout — never delete unused item art, and never leave it PascalCase/ungrouped in the
live tree. When you add a new item whose source art doesn't already follow this (freshly
sourced from an asset pack, still PascalCase, wrong folder, etc.), rename and move it into the
right spot as part of wiring up the item — don't leave the raw asset-pack layout in place.

---

## Spellcasting data (`spell.gd`, `spell_db.gd`, `spellcaster_state.gd`, `spell_slot_pool.gd`)

Cantrips (`docs/architecture/spellcasting-design.md`) plus leveled spells + spell slots
(design doc shipped and was deleted from `docs/architecture/`) — see `scripts/entities/CLAUDE.md`'s
"Wizard spellcasting (cantrips)" and "Wizard leveled spells (spell slots)" sections for the full
cast-resolution walkthroughs.

- **`Spell`** (`Resource`) — `spell_id`, `spell_name`, `description`, `icon_path`, `level` (0 =
  cantrip, 1-9 = leveled), `school`, `range_tiles`, `resolution` (enum: `ATTACK_ROLL`/`SAVE`/
  `AUTO_HIT`), `target_kind` (enum: `ENEMY`/`SELF`/`TILE`), `dice_count`, `dice_sides`,
  `damage_type`, `cantrip_tier_scaling: bool` (dice_count × tier at character levels 1/5/11/17),
  `save_stat`/`save_for_half` (SAVE
  resolution only), `shape`/`shape_size` (`""` = single target, `"sphere"` = AoE radius —
  deliberately no cone/line/cube, see the plan doc §7's content-scope cut), `effect_id` (`""` =
  pure generic damage path; else dispatched in `SpellEffects`), `class_list`, `bypasses_los: bool`
  (Magic Missile only today — BG3-style "seeking dart" targeting: skips `has_ranged_los()` entirely
  and requires `DungeonFloor.has_walkable_route_ignoring_chasms()` instead, see
  `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" → Magic Missile entry). Still missing
  concentration/reaction/component fields from the full design doc's `Spell` shape — add if a
  future spell needs them.
- **`SpellDb`** (static factory, `RefCounted`) — `get_spell(id) -> Spell` builds all spells in
  code, same "no `.tres` files" convention as `Talent`/`SpriteFrames`. `CANTRIP_IDS` (8 cantrips:
  the original `fire_bolt`/`ray_of_frost`/`shocking_grasp` plus `toll_the_dead`/`blade_ward`/
  `thunderclap`/`mind_sliver`/`light` — see `scripts/entities/CLAUDE.md`'s "Wizard spellcasting"
  section for all 8, including `SpellcasterState.cantrip_max(stats)` — the known-cantrip cap,
  Wizard 3/4/5 at character levels 1/4/10) + `STARTER_CANTRIP_IDS` (the fixed 3-cantrip round-1 pool `cantrip_select.gd`
  always offers — kept separate from `CANTRIP_IDS` so old saves/the premade Jace's
  `"cantrip": "fire_bolt"` shortcut stay valid) + `LEVELED_SPELL_IDS` (11:
  `magic_missile`/`shield`/`mage_armor`/`misty_step`/`fireball`/`chromatic_orb`/`burning_hands`/
  `witch_bolt`/`expeditious_retreat`/`false_life`/`fog_cloud` — the last 6 added after the initial
  pass, see `scripts/entities/CLAUDE.md`'s "More 1st-level spells" and "More 1st-level non-damage
  spells" sections) + `RANGER_SPELL_IDS` (Ranger's own eligible subset, currently just
  `["fog_cloud"]` — the only `LEVELED_SPELL_IDS` entry whose real 5e/5.5e class list actually
  includes Ranger; every other entry is Sorcerer/Wizard(/Warlock)-only on both rule sets, so it was
  deliberately NOT opened up to Ranger despite reusing the same shared spell pool — a real
  content-thinness gap, not a bug; see `scripts/entities/CLAUDE.md`'s "Ranger class")
  + `CLASS_SPELL_LISTS: Dictionary`
  (`"WIZARD"` → `LEVELED_SPELL_IDS`, `"RANGER"` → `RANGER_SPELL_IDS` — keyed by
  `Stats.CharacterClass` enum-name string, the level-up learn picker's candidate pool; cantrips are
  deliberately excluded from both lists since they're a separate, always-known system Ranger
  doesn't have at all). Each spell's own `class_list` field mirrors this same split (`["WIZARD"]` /
  `["WIZARD", "RANGER"]` per entry) though nothing currently reads `class_list` programmatically —
  see `Spell`'s own field note below.
- **`SpellcasterState`** (`Resource`) — lives on `Stats.caster` (Wizard and Ranger today — see
  `Stats.CLASS_ROLE` in `scripts/entities/stats.gd`, the internal-only FULL_CASTER/HALF_CASTER/
  MARTIAL/THIRD_CASTER categorization that decided this), not `GameState`, so a future enemy/
  companion caster can carry its own instance. `spellcasting_ability: String` ("INT"/"WIS"/"CHA" —
  Wizard: INT, Ranger: WIS), `known_spells: Array[String]` (cantrips AND
  leveled spells — `is_cantrip(id)` distinguishes via `SpellDb.get_spell(id).level == 0`, not by
  a separate array), `prepared_spells: Array[String]` (currently prepared/selected spells — BOTH
  cantrips, capped by `cantrip_max()`, and leveled spells, capped by `prepared_max()`; a spell can
  be known without being prepared, e.g. learned past its kind's cap — see
  `scripts/entities/CLAUDE.md`'s "Cantrip cap" note), `slot_pool: StandardSlotPool` (Wizard) or
  `HalfCasterSlotPool` (Ranger) — same interface, different table, see below.
  `prepared_cantrip_count()`/`prepared_leveled_count()` split the one array by kind for cap checks.
  `spell_attack_bonus(stats)` / `spell_save_dc(stats)`
  are computed **live, never cached** (`proficiency_bonus + ability_mod`,
  `8 + proficiency_bonus + ability_mod`) — mirrors `Stats.mastery_cap()`'s "recompute every time"
  convention, and deliberately does NOT derive from `character_class` (keeps a future multiclass
  caster sane — see the design doc §10.3). `prepared_max(stats) -> int` branches on
  `character_class`: `stats.character_level` for Wizard (leveled-spells-and-slots-plan.md §1 —
  supersedes the framework doc's `ability_mod + caster_level` formula), or the real 2024
  half-caster formula `max(1, WIS mod + character_level / 2)` for Ranger.
- **`StandardSlotPool`** (`Resource`, `scripts/items/spell_slot_pool.gd`) — Wizard's full-caster
  bookkeeper, the real D&D 2024 full-caster 1–20 slot table (`SLOT_TABLE` const), long-rest-only
  recharge (`on_short_rest()` is a no-op). `available_level(spell) -> int` returns `spell.level` if
  that EXACT slot level currently has an unspent slot, else `-1` — **no upcasting**: a spell locked
  out of its own slot level never falls back to a higher still-available one (was
  `lowest_available_level()`, which searched upward and could silently auto-upcast — removed per
  direct owner correction; upcasting was never requested and produced surprising results, e.g.
  Chromatic Orb auto-casting at a 5th-level slot). `grant_new_slots_on_levelup(old_max)` tops up
  newly-grown slot levels immediately after a level-up instead of leaving them empty until the
  next long rest (see `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" for why).
- **`HalfCasterSlotPool`** (`Resource`, `scripts/items/half_caster_slot_pool.gd`) — Ranger's own
  bookkeeper, same exact interface as `StandardSlotPool` above (`max_slots()`/`available_level()`/
  `can_cast()`/`consume()`/`on_long_rest()`/`grant_new_slots_on_levelup()`/`ui_summary()`) but its
  own `SLOT_TABLE`: the real D&D 2024 half-caster progression — slots from character level 1 (2024
  rules moved this earlier than the 2014 rules' level-2 start), max spell level 5 at character
  level 17. A deliberate duplicate implementation rather than a shared base class — same
  "duplicate rather than force a premature abstraction" call `StandardSlotPool`'s own comment used
  to justify staying singular, now that a genuine second table exists; add a real `SpellSlotPool`
  base class back only if a THIRD distinct progression (e.g. a Pact Magic-style pool) shows up.

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
then crumbles. **Castable by any class**, not just Wizard — the point of this item type. 20 exist
in `ITEM_POOL`/`debug_panel.ALL_ITEMS` today, one per `SpellDb` spell (`Scroll of Fire Bolt`,
`Ray of Frost`, `Shocking Grasp`, `Toll the Dead`, `Blade Ward`, `Thunderclap`, `Mind Sliver`,
`Light`, `Magic Missile`, `Shield`, `Mage Armor`, `Misty Step`, `Fireball`, `Chromatic Orb`,
`Burning Hands`, `Witch Bolt`, `Expeditious Retreat`, `False Life`, `Fog Cloud`, `Invisibility`); icon reuses the
spell's own `Spell.icon_path` (`"src": "spells"` pool key) — `DungeonFloor._build_floor_item()`
and `debug_panel._on_give_item()` both resolve it via `SpellDb.get_spell(item.scroll_spell_id).
icon_path` rather than reconstructing a flat path from the `ITEM_POOL` entry's own `"icon"` key,
since real spell art lives nested by level (`res://icons/spells/<level>/<id>.png` — see
`scripts/entities/CLAUDE.md`'s "Wizard spellcasting" section) and reusing the spell's own path
keeps the two from drifting out of sync. No dedicated scroll-item sprite exists — every scroll
just shows its spell's icon.

**Floor-loot level gate**: `DungeonFloorData.is_scroll_level_eligible(entry, character_level) ->
bool` — an entry carrying `"scroll_spell"` is only eligible to spawn once the player could
actually LEARN a spell of that level themselves (`StandardSlotPool.highest_accessible_level()`,
the standard 5e level→highest-slot-level table: 1-2→1st, 3-4→2nd, 5-6→3rd, ...); non-scroll
entries are unaffected. Applied alongside the existing `fmin`/`fmax` floor-range check at all
three `ITEM_POOL` eligibility filters in `dungeon_floor.gd` (`_spawn_items()`, `_spawn_treasure()`,
`_spawn_locked_doors()`) — a level-1 character can never find a scroll of a 2nd-level-or-higher
spell, regardless of what floor it's tuned to spawn on.

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
`SpellEffects.cast_spell()`/`cast_leveled_self()`/`cast_leveled_at_tile()`/`cast_magic_missile()`
all take an added `from_scroll: bool = false` param threaded down to `_consume_slot()`, which
early-returns when true instead of touching `player.stats.caster.slot_pool`. A Scroll of Magic
Missile goes through the same multi-target dart collection as the ability-bar cast (see
`scripts/entities/CLAUDE.md`'s Magic Missile entry) — `on_scroll_primed()` intercepts it before
arming the normal single-click flow.

**"Learn" (Wizard-only RMB scroll interaction)**: a Wizard (any character with `Stats.caster !=
null`) who doesn't yet know a scroll's spell gets a third RMB menu option, **Learn**, alongside
Read/Throw (`ItemInteractions.get_available_interactions()`'s
`GameState.can_learn_scroll_spell(item)` check — works on either scroll flavor, `scroll_spell_id`
or `taught_spell_id`). Unlike Read, Learn does **not** cast the spell — it studies the scroll into
the permanent spellbook instead, then the scroll is consumed. A cantrip (`Spell.level == 0`) is
learned instantly (`GameState.begin_scroll_learn()` calls `learn_spell()` + `remove_item()`
directly, no delay); a leveled spell takes **2 real turns per spell level** (a 5th-level spell
takes 10 turns) — `GameState.scroll_learn_active`/`scroll_learn_turns_remaining`/
`scroll_learn_item`/`scroll_learn_spell_id` (`scripts/autoloads/CLAUDE.md`), ticked in
`player.gd._on_turn_started()` right after the short-rest block, same auto-wait shape as a rest
(`PlayerActions.do_rest_wait_turn()` every real turn until the counter hits 0) but its own
independent flag, not a rest. **Interrupted outright** (no Continue/Abort prompt, unlike
short/long rest) per `Player._rest_interrupted()`'s tolerance rule (`scripts/entities/CLAUDE.md`'s
"Multi-turn action interrupts" section) — `GameState.cancel_scroll_learn(true)` — since nothing
has been consumed yet, the player just re-issues Learn once it's safe. On completion,
`GameState.complete_scroll_learn()` calls `learn_spell(spell_id)`
(which logs "You add X to your spellbook.") then `remove_item()` on the scroll — the scroll is
only ever destroyed on a successful finish, never on an interrupt.

## WeaponForge (Blacksmith random-weapon crafting)

`scripts/items/weapon_forge.gd`, `WeaponForge extends RefCounted`, static-func-only (same shape as
`WeaponTooltip`). `WeaponForge.generate_random_weapon() -> Item` is the only entry point — pure
data construction, no new combat/attack code needed anywhere (every field it sets is already
interpreted correctly by existing `Item`-reading code). Called by `scripts/ui/blacksmith_panel.gd`
on a successful forge; see `scripts/world/CLAUDE.md`'s "Blacksmith prop" and `scripts/ui/CLAUDE.md`'s
"Blacksmith panel" for the room/UI this feeds.

Generation order (each step's output can gate a later one):
1. **Damage die** — `Rng.pick()` of `[(1,4),(1,6),(1,8),(1,10),(1,12),(2,12)]`, the exact shapes
   every real weapon in the game already uses (`(2,12)` approximates 2d6 like Greatsword/Maul).
2. **Requirements (1-2, no replacement)** — `Rng.range_i(1,2)` count, drawn from
   `["Heavy","Two-handed","Martial","Ammo"]`. `Martial`/absence sets `weapon_category`
   (`"Martial"`/`"Simple"`). **`Ammo` is what makes the weapon ranged**: `is_ranged = true`,
   `ammo_item_name = Rng.pick(["Arrow","Bolt","Buckshot"])`, `range = Rng.range_i(3,5)`,
   `long_range = range * 4`. Not drawing `Ammo` means a plain melee weapon that never touches
   ammo at all. `Martial` and `Ammo` are independent — a ranged weapon can absolutely also roll
   Martial (both requirements can be drawn together, e.g. mirroring the Heavy Crossbow's real
   Martial+Ammo shape).
3. **Properties (1-2, no replacement)** — pool `["Finesse","Reach","Thrown","Versatile"]`
   (4 items — `Rng.range_i(1,2)` picks how many, so a crafted weapon usually has 2-3 excluded, not
   always just 1). Deliberately excludes `Light` and `Two-handed` (no
   dual-wield/off-hand complexity for a crafted weapon). **A weapon that rolled `Ammo` (is_ranged)
   can never also roll `Reach`** — Reach is a melee-only +1-tile-range concept that makes no sense
   on a bow/crossbow-shaped result, so `Reach` is stripped from the property pool before the
   count/pick happens whenever step 2 made the weapon ranged (`prop_count`'s own `Rng.range_i`
   upper bound also drops to the shrunk pool's size so it never asks for 2 out of a 1-item pool).
   `Finesse` → `is_finesse = true` (this is
   the whole "primary stat" story — `max(STR,DEX)` via the existing `CombatMath.
   finesse_modifier()` if rolled, else pure STR/DEX per whatever `is_ranged` already decided; no
   per-class stat table, no WIS/INT/CHA weapon-damage plumbing — none exists in this codebase and
   none was added). `Thrown` → `is_thrown = true`, `uses_max = Rng.range_i(3,6)`,
   `uses_remaining = uses_max`; if the weapon is already `is_ranged` (its range was rolled in step
   2), Thrown **reuses that same `range`/`long_range`** instead of re-rolling (the two mechanics
   share one field pair, so a Ranged+Thrown result never collides/overwrites) — otherwise Thrown
   rolls its own `range = Rng.range_i(2,4)`. `Versatile` → second random die pair into
   `versatile_die_min/max`; if the weapon is also `is_ranged`, this property is a "dead" cosmetic
   (the grip-toggle click only lives on the Main Hand *melee* equip slot — see "Versatile weapons"
   above), same accepted class as a mismatched mastery below.
4. **Weapon mastery** — `Rng.pick(Stats.ALL_WEAPON_MASTERIES)`, always assigned. Masteries are
   generic (gated on `weapon.weapon_mastery == "X" and stats.knows_mastery("X")` at each trigger
   site, never on item name — see "Weapon masteries" above), so a mismatched roll (e.g. `Sap` on a
   non-thrown result) simply never fires — intentional chaos, not a bug.
5. **Damage type** — weighted: 70% Physical (Slashing/Piercing/Bludgeoning, uniform), 25%
   Elemental (Fire/Cold/Acid/Poison/Thunder/Lightning, uniform), 5% Magical (Force/Necrotic/
   Psychic/Radiant, uniform) — `_random_damage_type()`, a manual `Rng.roll(100)` threshold check
   (named constants, easy to retune).
6. **Icon** — `_pick_icon(item)`, a priority-ordered heuristic reusing existing weapon sprites
   based on the rolled shape (`is_ranged`/`is_two_handed`+`is_heavy`/`is_versatile`/`is_thrown` →
   Short Bow/Crossbow/Maul/Quarterstaff/Handaxe-shaped art, default Rapier-shaped) — no "unknown
   weapon" icon exists anywhere in this codebase, so reusing real art is the established pattern.
7. **Name** — `_random_name()`: `Rng.range_i(5,8)` random lowercase letters, capitalized (e.g.
   `"Xqlvt"`) — deliberately absurdist, no naming table. Mastery still shows separately in parens
   via `WeaponTooltip.build()`'s existing name line regardless of the base name.
8. `gold_value = GOLD_VALUE` (10), `silver_value = 0` — fixed, not random. Distinct from the
   Blacksmith's own 50g craft *cost* (`blacksmith_panel.gd`'s `BLACKSMITH_GOLD_COST`) — two
   unrelated numbers.

**No new `Item` fields** — every field `generate_random_weapon()` touches already exists and is
already covered by `Item.to_dict()`/`from_dict()`, so a crafted weapon round-trips through
save/load for free.

## Mold
New `ITEM_POOL`/`debug_panel.ALL_ITEMS` entry, `Type.TOOL`, icon placeholder-reused from
`Materials/plate/iron.png` (no dedicated art exists). Sentinel `fmin`/`fmax = 99` (same convention
as Healing Herb) keeps it out of every generic floor-loot roll — its only spawn path is
`DungeonFloor._spawn_mold()`'s guaranteed once-per-run placement on `GameState.mold_target_floor`
(`scripts/world/CLAUDE.md`, `scripts/autoloads/CLAUDE.md`). Consumed 1-per-craft by
`blacksmith_panel.gd`.
