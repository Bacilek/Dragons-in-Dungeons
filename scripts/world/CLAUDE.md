# scripts/world

`dungeon_floor.gd` — master scene node for one dungeon floor. Owns TileMapLayer, Entities node, fog overlay, and all subsystem dictionaries.

`dungeon_floor_data.gd` (`DungeonFloorData`, static-const-only helper, `extends RefCounted`) — pure data pulled out of `dungeon_floor.gd`: `ENEMY_POOL`, `BOSS_POOL`, `TRAP_POOL`, `ITEM_POOL`, and the `WEAPONS_PATH`/`OBJECTS_PATH`/`ITEMS_PATH` sprite-folder constants. `dungeon_floor.gd` references these as `DungeonFloorData.ENEMY_POOL` etc. `scripts/ui/debug_panel.gd`'s Give Item / Spawn Enemy pickers also read `DungeonFloorData.ITEM_POOL`/`ENEMY_POOL`/`BOSS_POOL` directly (no more `load("res://scripts/world/dungeon_floor.gd")` indirection — `class_name` makes it globally addressable).

## Maintenance rule
When adding a new trap type, subsystem, or floor event, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Damage floaters
`show_damage(world_pos, amount, is_player_hit, color_override: Color = Color(0,0,0,0), stack_index: int = 0)` — `color_override` (alpha 0 = unset, keeps the old red/yellow default) lets a typed damage source (see `scripts/entities/CLAUDE.md`'s "Damage types / resistances") tint the floater by damage type (`CombatMath.damage_type_color()`); `stack_index` offsets spawn x by 10px per index so two simultaneous instances from one attack (e.g. Slashing + Radiant) don't fully overlap.

## Key query methods
```gdscript
dungeon_floor.is_tile_visible(pos: Vector2i) -> bool        # O(1) dict, use for visibility
dungeon_floor.is_explored(pos: Vector2i) -> bool            # fog-of-war explored
dungeon_floor.has_line_of_sight(p1, p2) -> bool             # Bresenham — enemy AI + search_around
dungeon_floor.has_ranged_los(p1, p2) -> bool                # permissive: blocks WALL/VOID only
dungeon_floor.get_room_centers() -> Array[Vector2i]         # for enemy roam targets
dungeon_floor.get_visible_enemies() -> Array[Enemy]         # enemies in current FOV
dungeon_floor.get_all_enemies() -> Array[Enemy]             # all enemies (for companion targeting)
# Companion system:
dungeon_floor.spawn_companion(companion: Companion, pos: Vector2i)
dungeon_floor.remove_companion(companion: Companion)
dungeon_floor.is_walkable_for_companion(pos: Vector2i) -> bool  # walkable + not blocked by player/enemies/companions
```

## FOV
`FOV_RADIUS = 7`. Algorithm: recursive shadowcasting (`_compute_shadowcast`, 8 octants, Roguebasin multiplier tables). Result stored in `_visible_tiles: Dictionary`.

**Rule**: after every player action, call `_dungeon_floor.update_fog(grid_pos)` **before** `TurnManager.on_player_action_complete()`.

## AoE targeting preview
`show_aoe_preview(center: Vector2i, radius: int)` / `hide_aoe_preview()` — a small pooled-`Sprite2D` purple tint (1×1 white texture tinted via `modulate`, `z_index = 2`, same layer as the fog sprite — Node2D-world convention, not a Control) over every tile within `radius` (Euclidean, no LOS filtering — see `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" for why) of `center`. Driven every frame by `player.gd._update_spell_aoe_preview()` while a sphere-shaped spell (Fireball) is armed for targeting. Rebuild is cached on `"%d,%d,%d" % [center, radius]` so repeated calls with the same hovered tile are near-free.

---

## Traps (`_traps: Dictionary[Vector2i, Dictionary]`)
Value keys: `name, damage, msg, sprite_node, revealed, triggered, is_push, reusable, push_dir, wall_pos`

| Trap | Reusable | Effect | Notes |
|---|---|---|---|
| Spike | yes | bleeding 5 turns | — |
| Bear | no | slowed 20 turns | — |
| Fire | no | burning 4 turns | can cook Rotten Meat |
| Piston | no | push + damage | detectable only from push side |

```gdscript
dungeon_floor.trigger_trap(pos)
dungeon_floor.reveal_trap(pos)
dungeon_floor.disarm_trap(pos)
dungeon_floor.search_around(pos) -> int   # returns number of traps revealed
```

Piston: `search_around` only detects from the `-push_dir` side.

## Forced movement (`force_move_entity`)
```gdscript
dungeon_floor.force_move_entity(entity: Node2D, direction: Vector2i, max_distance: int, deal_damage: bool = false, trap_sprite: Sprite2D = null) -> int
```
Generalized from the old piston-trap-only `_push_entity`. Walks `entity` step-by-step in `direction`, stopping early on wall/occupant collision; returns tiles actually moved. `deal_damage=true` reproduces the original piston-trap splash damage (piston traps still pass `true`). World Tree's Grip of the Forest (pull toward player, recomputing direction each step so off-axis targets still land adjacent) and Branching Strike R3 (push 1 tile away) both pass `deal_damage=false`. Reuse this for any future forced-movement talent/trap instead of writing a new mover.

**`resolve_push(enemy: Enemy, direction: Vector2i) -> void`** — a separate 1-tile-only pusher used by the Heavy Crossbow's **Push** weapon mastery (`scripts/items/CLAUDE.md`), *not* built on `force_move_entity()` because it needs non-generic per-destination-tile outcomes: WALL → flat 1d4 Bludgeoning damage, no movement (instead of the piston splash formula); a trap tile → moves the enemy there then calls `trigger_trap(dest, enemy)`; **CHASM** → `force_move_entity()` treats CHASM as blocking (not walkable) so it can't be reused here — `resolve_push()` instead removes the enemy outright (counts as a kill for exp) and, if it was a boss, appends a freshly-rolled loot item (`_roll_boss_loot_item()`, factored out of `drop_boss_loot()`) to `GameState.pending_chasm_items` and emits `GameState.boss_defeated(enemy.enemy_id)` (this chasm path is a boss death too — the Tier 2 gate must still fire) so the loot surfaces on the next floor down via the existing `_spawn_pending_chasm_items()` drain (see "Spawning" below — that mechanism was already generalized past ammo, so no changes were needed there). Called from `PlayerRanged.ranged_attack()` after a non-lethal Push-mastery hit.

---

## Doors (`_doors: Dictionary[Vector2i, Dictionary]`)
Value keys: `is_open: bool, locked: bool, sprite: Sprite2D, tex_open, tex_closed, lock_icon?: Sprite2D`

Auto-opens when an entity steps on the tile; auto-closes when entity leaves. Enemies open and walk through in the same turn. **Locked doors**: enemies cannot open (blocked); player auto-unlocks by walking through. Purple sprite tint + small key icon = locked.

```gdscript
dungeon_floor.has_door_at(pos) -> bool
dungeon_floor.is_door_open(pos) -> bool    # returns false if locked
dungeon_floor.is_door_locked(pos) -> bool
dungeon_floor.open_door(pos)               # no-op when locked
dungeon_floor.close_door(pos)
dungeon_floor.lock_door(pos)               # purple tint + lock icon; enemy blocked
dungeon_floor.unlock_door(pos)             # restores white tint, removes lock icon
```

**Generation-time locking**: `_spawn_locked_doors()` runs after `_spawn_items()`. Picks 1 door per floor whose removal doesn't disconnect spawn from stairs (`_bfs_reachable` validation). Places 2–3 reward items from `DungeonFloorData.ITEM_POOL` in the room behind the locked door. Uses `_bfs_collect()` to find tiles unreachable without that door.
**Player locking**: F key on adjacent CLOSED UNLOCKED door with Thief Tools → DC 10 DEX Sleight of Hand. Fail consumes Thief Tools.
**Unlocking**: Player walks into locked door → auto-unlock (free). Or F on locked door → unlock+open (spends action).

---

## Floor items (`_floor_items`, `_floor_item_sprites`)
`_floor_items: Dictionary[Vector2i, Array[Item]]` — **tiles stack**: multiple items can occupy the same position (oldest first in the array). `_floor_item_sprites` holds exactly one `Sprite2D` per occupied tile, always showing the newest (last-appended) item's icon — `place_item_on_floor()` swaps the existing sprite's texture in place rather than spawning a second sprite or bumping the drop to an adjacent tile. This is what lets a volley of arrows shot at the same spot all pile up on one tile instead of scattering.
```gdscript
dungeon_floor.place_item_on_floor(pos: Vector2i, item: Item)   # appends to the stack at pos
dungeon_floor.get_item_at(pos: Vector2i) -> Item                # topmost/newest item only (for tooltips/inspect)
dungeon_floor.get_items_at(pos: Vector2i) -> Array[Item]         # full stack, oldest first
dungeon_floor.remove_floor_item(pos: Vector2i)                   # clears the whole stack + sprite at pos
dungeon_floor.cook_rotten_meat(trap_pos: Vector2i) -> Item  # erases Fire Trap, returns Cooked Meat (food_value=75)
```
`cook_rotten_meat` only called from `PlayerThrowTool.do_throw()` (`scripts/entities/player_throw_tool.gd`) when `trap["revealed"] == true`. `place_item_on_floor` is also called from `PlayerAmmo`'s ranged-ammo landing resolver (`resolve_ammo_landing()`) — see "Ammo items" in `scripts/items/CLAUDE.md`.
**Pickup**: `PlayerActions.check_pickup()` (`scripts/entities/player_actions.gd`) calls `get_items_at()` + `remove_floor_item()` to grab the entire stack on the player's tile in one step (walking onto a pile of arrows returns all of them at once), collapsing same-named items into one `"xN"` log line.

---

## Spawning
```gdscript
_spawn_enemies()        # pulls from DungeonFloorData.ENEMY_POOL filtered by floor range, registers with TurnManager
_spawn_boss()           # floor % 5 == 0 → picks from DungeonFloorData.BOSS_POOL
_spawn_items()          # 2-3 random items from DungeonFloorData.ITEM_POOL; calls _build_floor_item()
_spawn_traps()          # places traps by type
_spawn_locked_doors()   # locks 1 door/floor that doesn't block spawn→stairs; places 2-3 rewards inside
_spawn_pending_chasm_items()  # drains GameState.pending_chasm_items (ammo that fell into a chasm on the PREVIOUS floor) onto random walkable tiles of this floor; called after _spawn_locked_doors(), before _setup_fog()
_spawn_gold_piles()     # 1-2 Type.GOLD piles of randi_range(5,10)+floor gold on random walkable tiles; appended after _spawn_pending_chasm_items() so every pre-existing _pop_rng draw keeps its position
_spawn_special_rooms()  # session 7b dispatcher: matches _data.room_metadata's type_id ("shop"/"treasure"/"garden"/"secret") — the ONE place a type_id string is matched. ALL BRANCHES ARE STUBS (pass) pending sessions 7c-7f (_spawn_treasure/_spawn_garden_items/_spawn_shop/_spawn_secret_room don't exist yet). LAST in the spawn order; currently consumes zero _pop_rng draws
```
**Seeded population (`_pop_rng`)**: all `_spawn_*()` randomness draws from `_pop_rng`, a `RandomNumberGenerator` re-created in `_load_floor()` with seed `run_seed ^ (current_floor * POPULATION_SEED_MIX)` — same run seed + floor always produces the identical population, which Phase-A save reloads depend on. Shuffles use `RngUtil.shuffle(arr, _pop_rng)`. **The spawn call order and the number of draws inside each function are load-bearing for reproducibility.** `_pop_rng` is load-time only — runtime rolls (trap triggers, boss loot at kill time, `resolve_push()` damage) use the `Rng` autoload's gameplay stream instead; never mix the two.
Item helper:
```gdscript
_build_floor_item(pos: Vector2i, d: Dictionary)  # shared by _spawn_items() and _spawn_locked_doors(); also reads weapon_mastery/damage_die_min/damage_die_max/ammo_item_name ("mastery"/"die_min"/"die_max"/"ammo" pool keys) — previously only debug_panel._on_give_item read those, so floor-loot weapons with a mastery/die/ammo now match their debug-given equivalents
```
Item spawn path lookup:
```gdscript
match d["src"]:
    "weapons": DungeonFloorData.WEAPONS_PATH
    "items":   DungeonFloorData.ITEMS_PATH
    _:         DungeonFloorData.OBJECTS_PATH
```

## Gold (special-rooms-economy-design.md §2, session 7a)
Gold piles are ordinary floor items of `Item.Type.GOLD` whose `gold_value` IS the pile size, built by `_make_gold_item(amount)` (name "Gold", icon `Misc/CoinGold.png`). Three sources:
- **Floor scatter** — `_spawn_gold_piles()` (see spawn list above, `_pop_rng`).
- **Enemy drops** — `maybe_drop_enemy_gold(enemy)`: 30% chance (`Rng.chance`, gameplay stream — kill-time randomness, same split as `_roll_boss_loot_item()`) of `Rng.range_i(1,4) + floor/2` gold at the death tile. Called from `Enemy.die()` (the single chokepoint every death site ends with, same reasoning as `embedded_items`); no-ops for bosses.
- **Boss kill** — `drop_boss_loot()` additionally places a guaranteed `20 + 5 × floor` pile alongside the potion.
Pickup: `PlayerActions.check_pickup()` routes GOLD items into `GameState.add_gold()` (one coalesced "Picked up N gold." log line per tile stack) — gold never occupies an inventory slot. `_build_floor_item()`/`_roll_boss_loot_item()` also read a `"gold"` pool key into `Item.gold_value` (base shop price for ordinary items — see `scripts/items/CLAUDE.md`).

---

## Floor transitions
```
on_player_reached_stairs() → GameState.advance_floor() → _load_floor()
```
`_explored` dict and fog reset each `_load_floor()`. Call `TurnManager.clear_enemies()` before reload.

---

## Compass (in `hud.gd`, triggered by DungeonFloor)
`stairs_discovered` signal emitted from `update_fog()` (first time stairs tile enters fog). Also emitted when `_on_debug_see_all(true)`. Compass shows "?" until received; then shows direction.

---

## See All (debug, F3)
`_on_debug_see_all(active: bool)` → sets `_see_all_active`, marks all non-VOID tiles as explored (enables click-to-move), emits `stairs_discovered`.

---

## Water terrain
`TileType.WATER` (=5) is fully rendered and implemented. Stepping into water: costs 2 turns (difficult terrain, same as mud) AND extinguishes burning (`burning_turns = 0`, logged in cyan). Both `player.gd _try_move()` and `_execute_queued_path()` handle this.

## Empty bottle mechanic
Drinking any POTION adds an `Empty Bottle` (TOOL type, `sprites/items/Materials/BottleSmall.png`) to inventory via `potion_drunk` signal → `GameState.add_item()`. **Fill is manual**: use the bottle from quickbar/inventory (enters tool mode via `player_tool_primed`), then LMB or RMB on an adjacent WATER tile → `Bottle of Water` (TOOL, BottleMedium sprite); adjacent MUD → `Bottle of Mud` (TOOL, BottleSmall sprite). Neither is FOOD-typed or contributes to long rest food value. Fill costs 1 turn. `PlayerThrowTool.try_fill_bottle(bottle, target)` (`scripts/entities/player_throw_tool.gd`) checks adjacency and tile type. **Nat-1 roll on fill**: rolling 1 on a d20 shatters the bottle (consumed, no fill). LMB tool routing checks item name before dispatching: "Empty Bottle" → `_throw_tool.try_fill_bottle()`; other tools → `_actions.interact_action()` (`scripts/entities/player_actions.gd`).

## Throw mechanic
Right-click food item in HUD quickbar → `GameState.player_throw_primed.emit(item)` → player enters throw mode. Left-click target tile → `_do_throw(pos)`. Rotten Meat + Fire Trap = Cooked Meat (see "Floor items" above). Esc cancels.

## Boss floors
`DungeonData.boss_room: Rect2i` set on floors divisible by 5. `_spawn_boss()` spawns from `DungeonFloorData.BOSS_POOL`. Floor 5: Big Demon (hp=80). Floor 10: Necromancer (hp=120). Boss dies → `drop_boss_loot(pos)`. `enemy.is_boss: bool`. `ENEMY_POOL`/`BOSS_POOL` entries carry stable `"enemy_id"`/`"boss_id"` keys (see `scripts/entities/CLAUDE.md`'s "Enemy/boss pool ids") and may carry an `"attack_profile"` key for ranged enemies (see that file's "Attack profiles" section) — both are read generically by `Enemy`, no `dungeon_floor.gd` changes needed.
