# scripts/world

`dungeon_floor.gd` — master scene node for one dungeon floor. Owns TileMapLayer, Entities node, fog overlay, and all subsystem dictionaries.

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

---

## Doors (`_doors: Dictionary[Vector2i, Dictionary]`)
Value keys: `is_open: bool, sprite: Sprite2D`

Auto-opens when an entity steps on the tile; auto-closes when entity leaves. Enemies open and walk through in the same turn.

```gdscript
dungeon_floor.has_door_at(pos) -> bool
dungeon_floor.is_door_open(pos) -> bool
dungeon_floor.open_door(pos)
dungeon_floor.close_door(pos)
```

---

## Floor items (`_floor_items`, `_floor_item_sprites`)
```gdscript
dungeon_floor.place_item_on_floor(pos: Vector2i, item: Item)
dungeon_floor.pick_up_item(pos: Vector2i) -> Item
dungeon_floor.cook_rotten_meat(trap_pos: Vector2i) -> Item  # erases Fire Trap, returns Cooked Meat (heal=150)
```
`cook_rotten_meat` only called from `_do_throw()` in `player.gd` when `trap["revealed"] == true`.

---

## Spawning
```gdscript
_spawn_enemies()   # pulls from ENEMY_POOL filtered by floor range, registers with TurnManager
_spawn_boss()      # floor % 5 == 0 → picks from BOSS_POOL
_spawn_items()     # pulls from ITEM_POOL
_spawn_traps()     # places traps by type
```
Item spawn path lookup:
```gdscript
match d["src"]:
    "weapons": WEAPONS_PATH
    "items":   ITEMS_PATH
    _:         OBJECTS_PATH
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
