# scripts/world

`dungeon_floor.gd` — master scene node for one dungeon floor. Owns TileMapLayer, Entities node, fog overlay, and all subsystem dictionaries.

`dungeon_floor_data.gd` (`DungeonFloorData`, static-const-only helper, `extends RefCounted`) — pure data pulled out of `dungeon_floor.gd`: `ENEMY_POOL`, `BOSS_POOL`, `TRAP_POOL`, `ITEM_POOL`, and the `WEAPONS_PATH`/`OBJECTS_PATH`/`ITEMS_PATH` sprite-folder constants. `dungeon_floor.gd` references these as `DungeonFloorData.ENEMY_POOL` etc. `scripts/ui/debug_panel.gd`'s Give Item / Spawn Enemy pickers also read `DungeonFloorData.ITEM_POOL`/`ENEMY_POOL`/`BOSS_POOL` directly (no more `load("res://scripts/world/dungeon_floor.gd")` indirection — `class_name` makes it globally addressable).

## Maintenance rule
When adding a new trap type, subsystem, or floor event, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

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
```gdscript
dungeon_floor.place_item_on_floor(pos: Vector2i, item: Item)
dungeon_floor.pick_up_item(pos: Vector2i) -> Item
dungeon_floor.cook_rotten_meat(trap_pos: Vector2i) -> Item  # erases Fire Trap, returns Cooked Meat (heal=150)
```
`cook_rotten_meat` only called from `_do_throw()` in `player.gd` when `trap["revealed"] == true`. `place_item_on_floor` is also called from `player.gd`'s ranged-ammo landing resolver (`_resolve_ammo_landing()`) — see "Ammo items" in `scripts/items/CLAUDE.md`.

---

## Spawning
```gdscript
_spawn_enemies()        # pulls from DungeonFloorData.ENEMY_POOL filtered by floor range, registers with TurnManager
_spawn_boss()           # floor % 5 == 0 → picks from DungeonFloorData.BOSS_POOL
_spawn_items()          # 2-3 random items from DungeonFloorData.ITEM_POOL; calls _build_floor_item()
_spawn_traps()          # places traps by type
_spawn_locked_doors()   # locks 1 door/floor that doesn't block spawn→stairs; places 2-3 rewards inside
_spawn_pending_chasm_items()  # drains GameState.pending_chasm_items (ammo that fell into a chasm on the PREVIOUS floor) onto random walkable tiles of this floor; called after _spawn_locked_doors(), before _setup_fog()
```
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
