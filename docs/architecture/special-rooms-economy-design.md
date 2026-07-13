# Special Rooms + Gold Economy — Design Doc

Status: **design only, not implemented.** No code ships with this doc. It specs the content for
the four special room types the (now-implemented and removed) dungeon-generation design doc left
as placeholder-fallback stubs (`ShopRoom`, `TreasureRoom`, `GardenRoom`, `SecretRoom` — see
`scripts/dungeon/CLAUDE.md`), plus the gold currency that makes a shop meaningful. This is the "Pixel Dungeon
half" of the game's identity — risk/reward room choices and an item economy — which is currently
entirely absent: floors today are BSP/Loop-generated standard rooms with no currency, no shops,
no guaranteed-loot rooms, no secret-room discovery play.

Function/field names cited below were verified against the working tree at time of writing;
re-verify line-level details before editing, but structural shape is authoritative. Mirror
existing patterns (`short_rest_panel.gd` for overlays, `_spawn_locked_doors()` for gated loot,
`_pop_rng` for population randomness) rather than inventing new ones.

---

## 1. Current state — what exists, what is greenfield

**Greenfield:**
- **No currency.** `Item.Type.GOLD` (`scripts/items/item.gd:4`) is declared in the enum but
  completely unused — no wallet field anywhere, no `ITEM_POOL` entry creates one, no code path
  branches on it. §2 finally gives it a job.
- **No item price/value concept.** `Item` has no `price`/`gold_value` field; the closest analog
  is `food_value` (FOOD-only int, long-rest fuel). §2.2 adds the price field.
- **No `ROOM_POOL`.** Despite the dungeon doc's §4 sketch, `FloorPlanner.plan()`
  (`scripts/dungeon/floor_planner.gd`) is hardcoded: one rng call for a budget
  (`clampi(roundi(base * mult), 4, 13)`), then `[EntranceRoom, ExitRoom] + (budget-2) ×
  StandardRoom`. No weighting, no `min_depth`, no `max_per_floor`. §3 specs the real mechanism.

**Already in place, reused as-is:**
- **`Room` type classes** (`scripts/dungeon/room_type.gd`, RefCounted, generation-time only):
  `type_id`, `rect: Rect2i`, `connections`, `required`; virtuals `min_size()`/`max_size()`/
  `max_connections()`/`paint(data, rng)`. The placeholder-fallback mechanism is plain
  inheritance (`ShopRoom extends StandardRoom`, don't override `paint()` until content exists) —
  an established repo invariant: never write an `if not room.has_content(): fallback()` runtime
  check, the fallback is structural. This doc writes the four `paint()` bodies; zero new
  room-class architecture is needed.
- **Floor population** (`dungeon_floor.gd`): seeded `_pop_rng` (`run_seed ^ (floor *
  POPULATION_SEED_MIX)`), `_spawn_items()`/`_spawn_traps()`/`_spawn_locked_doors()` with their
  load-bearing call order, `_build_floor_item(pos, d)`, `_floor_items` stacking,
  `place_item_on_floor()`. Boss loot at kill time rolls on the `Rng` gameplay stream
  (`_roll_boss_loot_item()`), not `_pop_rng` — the same load-time-vs-runtime split applies to
  gold drops.
- **Doors** (`_doors: Dictionary[Vector2i, Dictionary]`): open/close/lock/unlock,
  `_spawn_locked_doors()`'s `_bfs_reachable()` critical-path validation and behind-the-door
  reward spawning — the TreasureRoom and SecretRoom both build on this, not beside it.
- **Search** (Ctrl → `search_around(pos) -> int`): reveals hidden traps in radius. SecretRoom
  extends this same verb to hidden doors instead of adding a new interaction.
- **Modal overlay template** (`scripts/ui/short_rest_panel.gd`): CanvasLayer layer=25, dimming
  ColorRect, tabbed sub-panels, a `GameState`-level input-gate bool, Esc-to-close with the
  close-before-emitting-signals ordering rule. The Shop UI reuses this wholesale.

---

## 2. Gold currency

### 2.1 The wallet — `GameState.gold: int`

```gdscript
# game_state.gd — next to hit_dice / short_rests_remaining (plain-int-counter convention)
signal gold_changed(new_amount: int)
var gold: int = 0

func add_gold(amount: int) -> void:
    if amount <= 0:
        return
    gold += amount
    gold_changed.emit(gold)

func spend_gold(amount: int) -> bool:
    if GameState.invincible:          # invariant: invincible skips all consumption
        gold_changed.emit(gold)       # re-emit so UI refreshes anyway
        return true
    if amount > gold:
        return false
    gold -= amount
    gold_changed.emit(gold)
    return true
```

One plain int on the autoload, exactly like `hit_dice` — **rejected: a Currency/Wallet class**
for a single scalar. Reset to 0 in the same place other run state resets on new game.
HUD shows a small gold counter (coin icon + amount) near the stats panel, wired to
`gold_changed` — signals-not-polling per root conventions.

- **Save/load**: one entry in the misc section of `GameState.to_dict()`/`from_dict()`,
  `int(d.get("gold", 0))` — old saves load as 0. Trivial by design.
- **Invincible mode**: *earning* gold is not consumption (unaffected); *spending* is —
  `spend_gold()` succeeds without decrementing while invincible, matching the potion/ammo/hit-die
  guards.

### 2.2 The price field — `Item.gold_value: int`

```gdscript
# item.gd — next to food_value, same pattern
@export var gold_value: int = 0   # base shop price; for Type.GOLD items, the pile size
```

Serialized in `Item.to_dict()`/`from_dict()` like every other field. Set per
`ITEM_POOL`/`WEAPON_POOL` entry via a new `"gold"` pool key (read by `_build_floor_item()` and
mirrored in `debug_panel.ALL_ITEMS` per the item sync rule).

**Decision: flat per-entry field, not derived from `fmin`/`fmax`.** The floor-gating keys encode
*availability window*, not power — Ration and Health Potion are both `fmin 1 / fmax 10` yet are
worth very different amounts, and the Heavy Crossbow's `fmin 5` reflects when it's findable, not
what it costs. Deriving price from floor gating would misprice half the pool and couple two
unrelated concerns; a hand-set int per entry (≈10 entries today) is cheaper than any formula and
matches how `food_value` already works. Initial values (tune in playtest): Ration 15, Mystery
Meat 8, Health Potion 30, Strength Potion 80, Arrows 1/ea, Short Bow 50, Heavy Crossbow 120,
Thief Tools 25.

**Dual role for GOLD-type items**: a gold pile on the floor is an `Item` with
`item_type = Type.GOLD` and `gold_value = pile size`. One field, no separate `gold_amount`.

### 2.3 Earning gold

Three sources, all reusing existing machinery:

1. **Floor scatter** — new `_spawn_gold_piles()` in `dungeon_floor.gd`: 1–2 piles of
   `_pop_rng.randi_range(5, 10) + current_floor` gold on random walkable tiles, same
   candidate-picking pattern as `_spawn_items()`. **Appended to the END of the existing spawn
   call order** (after `_spawn_pending_chasm_items()`) so every `_pop_rng` draw that exists today
   keeps its position — the spawn order and per-function draw counts are load-bearing for
   reproducibility (`scripts/world/CLAUDE.md`).
2. **Enemy drops** — on non-boss enemy death, `Rng.chance(0.3)` → drop a pile of
   `Rng.range_i(1, 4) + current_floor / 2` at the death tile via `place_item_on_floor()`.
   Kill-time randomness → gameplay `Rng` stream, same as `_roll_boss_loot_item()`. Bosses
   additionally drop a guaranteed `20 + 5 × current_floor` pile alongside their existing potion
   loot in `drop_boss_loot()`.
3. **Room grants** — TreasureRoom and SecretRoom each include a guaranteed pile (§4).

**Pickup**: `PlayerActions.check_pickup()` gains one branch — items with
`item_type == Type.GOLD` never enter the inventory; they call `GameState.add_gold(it.gold_value)`
and log `"Picked up N gold."` (gold coalesces into the wallet exactly the way stacked arrows
coalesce into one log line). No quickbar/bag slot is ever occupied by gold — **rejected: gold as
an inventory item** (Pixel Dungeon precedent: gold is a counter, not cargo).

### 2.4 Spending gold

**Shop only.** The shop (§4.1) is the single gold sink in this doc's scope. No pay-to-reroll
talents, no door tolls, no gambling — any additional sink is a separate future design decision,
deliberately excluded so the economy can be balanced against one sink first (§6).

---

## 3. `ROOM_POOL` — growing `FloorPlanner.plan()` from hardcoded fill to a real pool

### 3.1 Pool structure

```gdscript
# floor_planner.gd
const ROOM_POOL: Array[Dictionary] = [
    # chance = independent per-floor spawn probability (see §3.2 for why not weights)
    {"script": TreasureRoom, "chance": 0.30, "min_depth": 2, "max_per_floor": 1},
    {"script": ShopRoom,     "chance": 0.40, "min_depth": 3, "max_per_floor": 1},
    {"script": GardenRoom,   "chance": 0.35, "min_depth": 2, "max_per_floor": 1},
    {"script": SecretRoom,   "chance": 0.30, "min_depth": 4, "max_per_floor": 1},
]
```

`plan()` never special-cases a `type_id` — it reads `chance`/`min_depth`/`max_per_floor`
generically and instantiates `entry["script"].new()`. Adding a room type = one class file + one
pool entry, exactly the extensibility contract the dungeon doc promised.

### 3.2 Selection algorithm — Bernoulli per entry, not weighted draws

```gdscript
static func plan(floor_num: int, feeling: String, rng: RandomNumberGenerator) -> Array:
    var mult: float = FloorFeeling.FEELINGS.get(feeling, {}).get("room_budget_mult", 1.0)
    var base: int = rng.randi_range(7, 9) + mini(floor_num / 3, 2)   # UNCHANGED — call #1
    var budget: int = clampi(roundi(base * mult), MIN_ROOM_BUDGET, MAX_ROOM_BUDGET)

    var specials: Array = []
    if floor_num % 5 != 0:                       # no special rooms on boss floors
        for entry: Dictionary in ROOM_POOL:      # fixed declaration order — load-bearing
            if floor_num < entry["min_depth"]:
                continue                          # ineligible: NO rng consumed
            for _i: int in entry.get("max_per_floor", 1):
                if rng.randf() < entry["chance"]:  # one draw per eligible slot
                    specials.append(entry["script"].new())

    var rooms: Array = []
    rooms.append(EntranceRoom.new())
    rooms.append(ExitRoom.new())
    rooms.append_array(specials)
    var standards: int = maxi(budget - 2 - specials.size(), 2)   # floor: ≥2 standard rooms
    for _i: int in standards:
        rooms.append(StandardRoom.new())
    return rooms
```

**Why per-entry Bernoulli instead of the dungeon doc §4's weighted-draw-per-budget-slot sketch**
(this is a deliberate refinement of that sketch, superseding it):

1. **Deterministic rng footprint.** The number of rng calls depends only on `floor_num`
   (eligibility is depth-gated, not seed-gated), so the seeded stream layout is identical for
   every seed at a given depth — the same property `plan()`'s existing "exactly ONE rng call"
   header comment protects today, generalized. Weighted draws with `max_per_floor` rejection
   would make call counts seed-dependent and the stream unanalyzable.
2. **Directly tunable.** "Shop on ~40% of floors 3+" is a designer sentence that maps 1:1 to a
   pool value; with weights it's an emergent ratio that shifts every time any other weight
   changes.
3. **`max_per_floor` is trivially structural** (the inner loop bound) instead of a
   rejection-sampling special case.

**Determinism / byte-identical preservation:**
- **Floor 1** (below every `min_depth`) and **boss floors** consume zero extra rng calls and emit
  the exact room list today's code emits → byte-identical `DungeonData` for every existing seed.
  This preserves the repo's "same seed+floor → identical output" reproducibility invariant
  (`scripts/dungeon/CLAUDE.md`); verify with the existing `scripts/dungeon/_verify/dump_gen.gd`
  harness on floor 1 before merging.
- **Floors 2+** intentionally change output (extra `rng.randf()` calls shift the stream). This is
  an *intentional generation change*, same precedent as Phase 3's documented "RNG FOOTPRINT
  CHANGE" in `floor_planner.gd`'s header — document it the same way there and in
  `scripts/dungeon/CLAUDE.md`.
- All randomness stays on the seeded `rng` threaded into `plan()` — never global
  `randi_range`/`randf`, per the `Rng`-service rule.

**BSP-fallback floors lose their special rooms — accepted.** `BspBuilder` ignores the planned
room list (its BSP recursion decides count/geometry), so on the <2% of floors where `LoopBuilder`
exhausts retries, planned special rooms get no `rect` and silently don't materialize. Every
special-room `paint()` body therefore opens with `if rect == Rect2i(): return`, and the
metadata bridge (§3.3) only exports rooms with a non-empty rect. No fallback machinery, no crash,
occasional shopless floor — consistent with the structural-placeholder philosophy.

### 3.3 The generation→runtime bridge — `DungeonData.room_metadata`

`paint()` can only mutate `data.grid` (tiles). Shop stock, vendors, guaranteed items, traps, and
hidden doors are all *runtime* state owned by `DungeonFloor`'s Vector2i-keyed dictionaries — the
established pattern mirroring `_doors`/`_traps`/`_floor_items` (`scripts/world/CLAUDE.md`), never
loose per-node-only state, so it stays serializable later without another audit sweep. The bridge
is the additive `DungeonData` field this pattern implies, following `DungeonData`'s existing rule
that new fields (like `feeling`) are additive and never break existing public fields:

```gdscript
# dungeon_data.gd — additive, existing fields untouched
var room_metadata: Array = []   # Array[Dictionary]: {"type_id": String, "rect": Rect2i}
```

`DungeonGenerator.generate()` fills it after Build, before Paint: one entry per planned room
whose `type_id` is not `"standard"`/`"entrance"`/`"exit"` and whose `rect` is non-empty. Then in
`dungeon_floor.gd._load_floor()`, a new dispatcher runs **after all existing `_spawn_*()`
calls** (again: append-only, existing `_pop_rng` sequence untouched when metadata is empty):

```gdscript
func _spawn_special_rooms() -> void:
    for meta: Dictionary in _data.room_metadata:
        match meta["type_id"]:
            "shop":     _spawn_shop(meta["rect"])
            "treasure": _spawn_treasure(meta["rect"])
            "garden":   _spawn_garden_items(meta["rect"])
            "secret":   _spawn_secret_room(meta["rect"])
```

This is the one place a `type_id` string is matched — it dispatches *population*, not
generation, so it doesn't violate the pool's "never special-case a type_id" rule (which governs
`plan()`). `room_metadata` is generation output regenerated from the seed on every
`_load_floor()`, so it needs **no serialization** — Phase-A save reloads rebuild it for free;
mid-floor mutations (items bought, secrets found) are Phase-B state like everything else.

---

## 4. The four room types — full specs

All four extend `StandardRoom` (keeping the structural-placeholder chain intact for any future
fifth type), set their `type_id` in `_init()`, and live one class per file under
`scripts/dungeon/` next to `standard_room.gd`.

### 4.1 ShopRoom

**Generation** (`shop_room.gd`):
- `_init()`: `type_id = "shop"`.
- `max_connections() -> int: return 1` — shops are dead-end rooms so the vendor watches the only
  entrance; also keeps the room off the critical path.
- `min_size()`/`max_size()`: `Vector2i(5, 5)` / `Vector2i(7, 7)` — small, cozy.
- `paint(data, rng)`: `if rect == Rect2i(): return`; otherwise no tile changes (plain floor is
  correct for a shop) — the override exists only for the guard + symmetry; content is runtime.

**Vendor — interact-point object, not an NPC Entity.** The shopkeeper is a static `Sprite2D` on
a tile (an existing character sprite's idle frame, e.g. `necromancer` or `dwarf_m`, rendered
non-animated at enemy z-index 1), stored in a new `_shopkeepers: Dictionary[Vector2i,
Dictionary]` on `DungeonFloor` (invariant 9). **Rejected: `Entity`/`Companion` subclass** — an
Entity implies `TurnManager.register_enemy()`, `take_turn()`, pathing, attackability, and
death handling, none of which a stationary vendor needs; the doors/traps pattern (Vector2i-keyed
dict + sprite + interaction hook) is the established shape for "a thing on a tile you interact
with". Shopkeeper aggro/theft (Pixel Dungeon's fleeing shopkeeper) is explicitly out of scope
(§6). The vendor tile is impassable (movement into it is blocked the way an occupied enemy tile
is).

**Opening the shop**: bump-to-open (moving into the vendor tile opens the panel instead of
moving, costing no turn — mirrors locked-door walk-in ergonomics) and RMB via
`PlayerActions.interact_action(target)` (which already resolves exact-tile interactions when
called from RMB).

**Stock generation** (`_spawn_shop(rect)`, runs at floor load on `_pop_rng`):
- Filter `DungeonFloorData.ITEM_POOL` by the existing `fmin`/`fmax` gate (same eligibility loop
  as `_spawn_items()`), excluding entries with `gold_value == 0` (unpriced = not for sale).
- Draw 4–6 distinct entries (`RngUtil.shuffle(eligible, _pop_rng)`, take first N); build each
  via the same field-mapping as `_build_floor_item()` but into the stock list, not onto the
  floor. Always guarantee one Ration in stock (food is the long-rest bottleneck — the shop's
  core strategic offer).
- Stock lives in the shopkeeper's dict entry: `{"sprite": ..., "stock": Array[Item]}`. Items
  are **not** laid out as floor items — overlay-only stock is theft-proof by construction and
  avoids designing steal mechanics now.
- **No restock**: bought items are gone; stock persists while on the floor and is discarded on
  descent (floors don't persist). On a Phase-A save reload the floor regenerates from seed with
  its *initial* stock — purchases mid-floor are Phase-B state, same accepted wrinkle as every
  other mid-floor mutation (`SAVE_LOAD_ARCHITECTURE.md` stance, unchanged).

**Pricing**: buy price = `item.gold_value`, flat (no depth scaling for v1 — §6). Sell price =
`maxi(1, item.gold_value / 2)`; items with `gold_value == 0` can't be sold (shown grayed).

**UI** (`scripts/ui/shop_panel.gd`) — explicitly **reuse the `short_rest_panel.gd` pattern, do
not design a new modal mechanism**: `CanvasLayer` layer=25, dimming `ColorRect` that closes on
click, centered `Panel`, two tabs (**Buy** / **Sell**) toggled exactly like Short/Long rest
containers, `focus_mode = FOCUS_NONE` on all buttons, and a new `GameState.shop_open: bool`
input gate checked everywhere `short_rest_open` is (player input, WASD polling, hotkeys). Esc
closes; per the established ordering rule, clear `shop_open` and `queue_free()` **before**
emitting anything that could re-enter input handling. Buy tab: one row per stock item (icon —
sized per the `ignore_texture_size = true` rule — name, price, Buy button disabled when
`GameState.gold < price`); buying calls `spend_gold()` then `GameState.add_item()` (inventory
full → refuse with a log line, gold untouched). Sell tab: a slot grid of the player's bag/quickbar
modeled on `inventory_overlay.gd`'s slot conventions (click to sell — no drag needed for v1);
equipped items are not sellable from here. Every transaction logs via `GameState.game_log()`.
Opening the shop takes no turn and can't be interrupted — it's a menu, not an action.

### 4.2 TreasureRoom

**Generation** (`treasure_room.gd`):
- `_init()`: `type_id = "treasure"`.
- `max_connections() -> int: return 1` — dead-end vault, so locking its one door gates it
  cleanly.
- `min_size()`/`max_size()`: `Vector2i(5, 5)` / `Vector2i(7, 7)`.
- `paint(data, rng)`: guard on empty rect; no tile changes (a vault is plain floor; visual
  dressing via props is a polish item, not tiles).

**Runtime content** (`_spawn_treasure(rect)`, on `_pop_rng`):
- **Guaranteed loot**: 3 items rolled from the floor-gated `ITEM_POOL` eligibility list (same
  reward roll `_spawn_locked_doors()` already uses) placed on random floor tiles inside `rect`
  via `_build_floor_item()`, **plus** one guaranteed gold pile of
  `_pop_rng.randi_range(15, 25) + 2 * current_floor`.
- **Guarded, always**: the room's connecting door is locked via the existing `lock_door(pos)`
  mechanic (purple tint + key icon, enemies blocked, player walk-through auto-unlocks —
  identical player experience to today's locked-door rooms, so no new teaching needed). Find the
  door by scanning `_doors` keys on the rect perimeter. Additionally, on floors ≥ 4, place 1–2
  traps from the existing `TRAP_POOL` on tiles inside the rect (reuse `_spawn_traps()`'s
  placement helper) — the "is the vault worth the trap risk" decision is the room's identity.
- **Interaction with `_spawn_locked_doors()`**: on floors where a TreasureRoom spawned, skip the
  generic locked-door pass (early-return if any `room_metadata` entry is `"treasure"`) — one
  gated-loot room per floor, and the TreasureRoom *is* it. Keeps total floor loot from silently
  doubling.
- **One-time**: items picked up are gone; nothing respawns. No repeatable interaction exists to
  gate.

### 4.3 GardenRoom

**Generation** (`garden_room.gd`):
- `_init()`: `type_id = "garden"`.
- Default sizes and `max_connections()` (gardens can be pass-through — they're a rest stop, not
  a gated prize).
- `paint(data, rng)` — the one room type whose content IS mostly tiles, tying into the dungeon
  doc §6's Water/Garden sketch. Uses existing `TileType` values only, no new tiles:

```gdscript
func paint(data: DungeonData, rng: RandomNumberGenerator) -> void:
    if rect == Rect2i(): return
    # 1. Carpet ~60% of interior floor tiles with GRASS (per-tile rng.randf() < 0.6).
    # 2. One small WATER pool: a 2x2-to-3x3 blob at an rng-picked interior anchor,
    #    kept ≥1 tile off the room perimeter so doorways stay dry.
    # Only overwrite FLOOR tiles — never corridors' tiles, pillars, or chasms placed later
    # (LevelPainter's level-wide overlays run AFTER per-room paint and already avoid
    # disconnecting the map; grass/water are walkable so connectivity is never at risk).
```

**Gameplay hook — yes, minimal: a gatherable herb.** Decision and justification: a purely
cosmetic garden would be dead weight (players learn to ignore it, and it spends a special-room
slot teaching nothing), while a heal-on-entry tile means new tile-effect machinery and a new
`TileType`. The middle path costs almost nothing: `_spawn_garden_items(rect)` places 1–2
**Healing Herb** floor items on grass tiles inside the rect. Healing Herb is one new `ITEM_POOL`-
style entry (FOOD type, `food_value: 25`, `heal_amount: 4`, `gold_value: 10`, an icon from
`sprites/items/Sprites trial/Food/`), added to `ITEM_POOL` with `fmin`/`fmax` set so it *only*
spawns via gardens (or given `fmin 99` and referenced directly by the garden spawner — pick at
implementation time), and mirrored in `debug_panel.ALL_ITEMS` per the sync rule. It plugs
straight into the existing long-rest food economy and potion-style eat-to-heal path — zero new
verbs, zero new systems. The WATER pool additionally synergizes with existing mechanics for
free: bottle filling and burning-extinguish already work on any WATER tile.

### 4.4 SecretRoom

**Generation** (`secret_room.gd`):
- `_init()`: `type_id = "secret"`.
- `max_connections() -> int: return 1` — a secret room with two entrances isn't secret.
- `min_size()`/`max_size()`: `Vector2i(5, 5)` / `Vector2i(6, 6)` — smallest of the four (builders
  assume the 5–11 range; staying inside it avoids any builder changes).
- `paint()`: guard on empty rect; no tile changes.

**Discovery — reuse the Ctrl search verb, via a hidden door.** `_spawn_secret_room(rect)` finds
the room's single connecting door in `_doors` and marks it `"hidden": true`: the door sprite is
not shown, and the tile renders as WALL from the outside (swap the TileMapLayer cell to WALL's
atlas source; the underlying `_data.grid` value and `_doors` entry are the truth). A hidden door
is impassable and invisible — to enemies too (enemy pathing already can't open locked doors;
hidden extends the same block). `search_around(pos)` — the existing Ctrl search that reveals
traps — gains one loop over `_doors` entries within the same radius: a hidden door found is
revealed (restore floor tile + door sprite, log
`"You discover a hidden door!"` via `GameState.game_log()`, same beat as trap reveals). **No new
interaction, no new key** — the player already knows Ctrl from trap play; secret rooms make an
existing, currently situational verb globally worth using. Optional free assist, decided now to
avoid re-litigating: walking adjacent to a hidden door does *not* auto-reveal — discovery must be
deliberate (that's the play pattern), but the FOV-visible wall segment may use a subtly cracked
wall sprite later as a soft tell (polish, out of scope).

**Reward tier**: strictly better than a locked-door room, because it costs deliberate search
turns — 2–3 `ITEM_POOL` rolls **with a bias**: one roll is drawn from the eligible list filtered
to the top half by `gold_value` (rarity proxy), plus a guaranteed gold pile of
`_pop_rng.randi_range(20, 30) + 2 * current_floor`. All spawned inside the rect at floor load on
`_pop_rng` — the room's contents exist whether or not it's ever found.

**`min_depth: 4` rationale** (kept from the dungeon doc's sketch): by floor 4 the player has met
trapped floors and locked doors, so "the dungeon hides things; Ctrl finds them" is established
knowledge, and the reward budget (top-half item + large pile) would distort floors 1–3's tight
early economy.

---

## 5. Risk ranking and implementation sequence

Session-numbered 7a–7f (this repo's now-retired roadmap doc had already sequenced items 1–6;
these six pick up where it left off, as the "content sessions" it deferred until design time).

### 5.1 Dependency graph (why this order)

```
Gold economy core (7a) ──────────┐
                                  ├─→ ShopRoom (7e) (needs gold to spend, gold_value prices,
ROOM_POOL + metadata bridge (7b) ─┤    and a room to exist in)
                                  │
                                  ├─→ TreasureRoom (7c) (needs a room + gold piles for its
                                  │    guaranteed pile; zero UI — first content proof)
                                  │
                                  ├─→ GardenRoom (7d) (needs only the room; herb item is
                                  │    independent of gold)
                                  │
                                  └─→ SecretRoom (7f) (needs a room + gold; also touches the
                                       door/search systems — sequenced last so the door-dict
                                       "hidden" key lands after the other rooms have proven
                                       the metadata bridge)
```

7a and 7b are independent of each other and could swap; everything else needs both. TreasureRoom
before ShopRoom deliberately: it exercises the whole pipeline (pool → metadata → runtime spawn →
locked door → loot) with zero new UI, so pipeline bugs surface in the cheap session, not the
expensive one.

### 5.2 Session sizing

| # | Item | Files touched | Notes |
|---|---|---|---|
| 7a | Gold economy core | `item.gd` (`gold_value` + serialization), `game_state.gd` (`gold`, `add_gold`/`spend_gold`, save fields), `player_actions.gd` (GOLD pickup branch), `dungeon_floor.gd` (`_spawn_gold_piles()`, enemy/boss drop hooks), `hud.gd` (gold counter), `debug_panel.gd` (give-gold row) | Fully playable with zero rooms: gold drops, accumulates, displays, saves. `gold_value` pool keys can land here too |
| 7b | ROOM_POOL + metadata bridge | `floor_planner.gd`, `dungeon_generator.gd`, `dungeon_data.gd` (`room_metadata`), 4 new one-liner room class files, `dungeon_floor.gd` (`_spawn_special_rooms()` dispatcher, branches empty) | Rooms spawn as plain-floor rects, visibly tagged only in debug. **Must re-run `dump_gen.gd` on floor 1 and a boss floor to prove byte-identical output** before merging |
| 7c | TreasureRoom | `treasure_room.gd`, `dungeon_floor.gd` (`_spawn_treasure()` + skip-generic-locked-door rule) | First content; no UI. Verify locked-door reuse and the one-gated-room-per-floor rule |
| 7d | GardenRoom + Healing Herb | `garden_room.gd`, `dungeon_floor_data.gd` (herb entry), `dungeon_floor.gd` (`_spawn_garden_items()`), `debug_panel.gd` (ALL_ITEMS mirror) | Smallest session. Verify grass/water paint doesn't fight LevelPainter overlays |
| 7e | ShopRoom + shop panel | `shop_room.gd`, `dungeon_floor.gd` (`_shopkeepers`, `_spawn_shop()`, bump-to-open), new `scripts/ui/shop_panel.gd`, `game_state.gd` (`shop_open` gate), `player.gd`/`player_actions.gd` (input-gate checks + interact hook) | Biggest session; split Buy-tab-only first / Sell tab second if it runs long |
| 7f | SecretRoom + hidden doors | `secret_room.gd`, `dungeon_floor.gd` (`hidden` door key, wall-tile masking, `search_around()` extension, `_spawn_secret_room()`) | Touches door rendering + FOV-adjacent tile display — playtest reveal/re-hide edge cases (fog, See All debug) |

Each session ends with CLAUDE.md updates (root pointer + `scripts/world/`, `scripts/dungeon/`,
`scripts/ui/`, `scripts/items/`, `scripts/autoloads/` as touched) per the maintenance rule.

### 5.3 Risk ranking

**Highest risk:**
- **Shop panel (7e)** — the only genuinely new UI surface. The overlay *pattern* is proven, but
  a two-tab transactional grid with per-row affordability state, inventory-full refusal, and a
  new input gate has the most moving parts and the most footguns from `scripts/ui/CLAUDE.md`
  (mouse filters, slot sizing, `ignore_texture_size`). Also the first place economy *balance*
  becomes observable — expect price-table iteration after playtest.
- **ROOM_POOL determinism (7b)** — the change is small but the failure mode is silent: one
  misplaced rng call shifts every seed's output on floors 2+ in an unintended way, or worse,
  breaks floor-1/boss-floor byte-identity that saves depend on. The `dump_gen.gd` diff gate is
  non-negotiable for this session.

**Lowest risk:**
- **Gold core (7a)** — one int, one signal, pickup branch, drop hooks; every piece mirrors an
  existing pattern (`food_value`, `hit_dice`, boss loot).
- **TreasureRoom (7c)** and **GardenRoom (7d)** — pure recombination of shipped machinery
  (locked doors, trap placement, item spawning, tile painting).

---

## 6. Open questions / explicitly out of scope

Deferred deliberately, with reasons — not a vague future-work list:

- **Shopkeeper aggro / theft** (Pixel Dungeon's fleeing shopkeeper): out of scope. Stock is
  overlay-only, so theft is impossible by construction; adding it later means promoting the
  vendor to something Entity-like, which is exactly the complexity the interact-point decision
  avoided. Revisit only if floor-laid shop stock is ever wanted.
- **Restocking / shop persistence across floors**: no restock, no returning to old floors
  (floors don't persist in this game at all) — nothing to design until floor persistence itself
  is on the table (Phase B and beyond).
- **Price scaling by depth / charisma / reputation**: flat `gold_value` for v1. A single
  multiplier read in `shop_panel.gd`'s price display is a one-line change later; tuning it
  before the base economy has soaked is guesswork. CHA currently does nothing in this game —
  a CHA-based haggle discount is a natural future hook, noted, not designed.
- **Additional gold sinks** (talent respec, door tolls, gambling, upgrade fees): excluded so the
  economy balances against exactly one sink first. Each sink is a small standalone design once
  gold income curves are observed in play.
- **Multi-currency** (gems, keys-as-currency): rejected outright, not just deferred — one
  counter matches the plain-int convention and the game's scale.
- **`LoopBuilder` placement awareness** (e.g. "shop near entrance", "secret room off a dead-end
  corridor"): the builder currently places rooms without type-based preference, and
  `max_connections() = 1` is the only geometric lever this doc pulls. Room-graph-aware placement
  is a `LoopBuilder` enhancement with its own doc if ever needed.
- **Mid-floor persistence of purchases / found secrets / looted vaults** across save reloads:
  Phase B by definition (`SAVE_LOAD_ARCHITECTURE.md`); everything in this doc keeps its mutable
  state in `DungeonFloor` Vector2i-keyed dicts (invariant 9) precisely so Phase B can serialize
  it without another audit.
- **Secret-room soft tells** (cracked-wall sprite variants) and shop/vault prop dressing: art
  polish, listed so it isn't mistaken for a design gap.
- **Open question — guaranteed shop cadence**: pure `chance: 0.40` means a run can roll zero
  shops. Pixel Dungeon guarantees shops at fixed depths. If playtest shows gold piling up with
  nowhere to go, add a pity rule (e.g. force-include ShopRoom if none spawned in the last 3
  eligible floors — needs one extra `GameState` counter, or make it depth-deterministic:
  guaranteed on floors 3/8, chance elsewhere). Left open pending playtest; the pool mechanism
  supports either without structural change.
