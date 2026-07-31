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
dungeon_floor.has_ranged_los(p1, p2) -> bool                # blocks WALL/VOID and closed doors (not GRASS, unlike has_line_of_sight) — TERRAIN only, ignores bodies standing in the way
dungeon_floor.get_blocking_body_on_line(p1, p2) -> Node     # first Enemy/Player/Companion on an INTERMEDIATE tile of the p1→p2 ray (endpoints excluded), or null
dungeon_floor.has_clear_shot(p1, p2) -> bool                # has_line_of_sight(p1,p2) (blocks GRASS too, unlike has_ranged_los) AND no blocking body — the gate enemy-side ranged attacks/abilities/thrown weapons check (see scripts/entities/CLAUDE.md's "Attack profiles")
dungeon_floor.find_path(from, to) -> Array[Vector2i]        # click-to-move pathing — 8-dir BFS, requires `to` explored, closed doors passable (open on arrival)
dungeon_floor.has_walkable_route_ignoring_chasms(from, to) -> bool  # Magic Missile's "seeking dart" targeting (Spell.bypasses_los) — same 8-dir BFS as find_path() but NOT gated on _explored, and CHASM tiles are passable (the one deliberate difference — see scripts/entities/CLAUDE.md's Magic Missile entry); still blocked by WALL/VOID/barrel/blacksmith/shopkeeper props
dungeon_floor.get_room_centers() -> Array[Vector2i]         # for enemy roam targets
dungeon_floor.get_visible_enemies() -> Array[Enemy]         # enemies in current FOV
dungeon_floor.get_all_enemies() -> Array[Enemy]             # all enemies (for companion targeting)
dungeon_floor.get_enemy_at(pos) -> Enemy                    # unfiltered — bump-into-move detection must keep using this one
dungeon_floor.get_targetable_enemy_at(pos) -> Enemy         # null for an Invisible enemy — every DIRECT click-target resolution uses this instead (see scripts/entities/CLAUDE.md's "Invisibility")
# Companion system:
dungeon_floor.spawn_companion(companion: Companion, pos: Vector2i)
dungeon_floor.remove_companion(companion: Companion)
dungeon_floor.is_walkable_for_companion(pos: Vector2i) -> bool  # walkable + not blocked by player/enemies/companions
```

## FOV
`FOV_RADIUS = 5`. Algorithm: recursive shadowcasting (`_compute_shadowcast`, 8 octants, Roguebasin multiplier tables). Result stored in `_visible_tiles: Dictionary`. Both `update_fog()`'s own `_compute_shadowcast()` call and `get_visible_enemies()`'s radius check go through `GameState.effective_fov_radius(pos) -> int` — normally `FOV_RADIUS + fov_radius_bonus + GameState.celestial_radiance_fov_bonus() + player_stats.darkvision_bonus + (1 if has_lit_torch_equipped() else 0)` (the torch term is a lit Torch equipped in either hand, `scripts/items/CLAUDE.md`'s "Torch", computed live so it can't drift out of sync with equip/light/burnout state; `celestial_radiance_fov_bonus()` is Aasimar's Inner Radiance transformation, `scripts/entities/CLAUDE.md`'s "Aasimar" section — +2 while active, deliberately summed BEFORE darkvision, same conceptual "own light source" slot the torch bonus occupies), but flattens to `1` — ignoring every bonus, darkvision included — whenever `GameState.is_blinded(pos)` (see `scripts/entities/CLAUDE.md`'s "Conditions"/"Fog Cloud" sections). A single shared function so the two call sites can never compute a different radius from each other.

**FOV-bonus ring visuals stack in the same order the terms are summed**: `base → torch → celestial
→ darkvision`, each ring computed as the tile-diff between two progressively larger shadowcasts
(`update_fog()`) and painted by its own dedicated glow function — `_update_torch_fov_ring_glow()`
(pale yellow), `_update_celestial_fov_ring_glow()` (bright celestial gold, Aasimar Inner Radiance),
`_update_darkvision_ring_glow()` (dim desaturated gray, always the outermost ring) — so each bonus
source visibly occupies its own band around the player rather than all blending into one tint.

**Torch light bubble (floor/embedded, separate from the equipped FOV bonus above)**:
`update_fog()` also unions `_compute_torch_light_tiles()` into `_visible_tiles` and paints it via
`_update_torch_light_glow()` — a sweep of every lit-and-unburnt Torch currently lying on
`_floor_items` (contributing a `GameState.TORCH_LIGHT_RADIUS` (2) shadowcast centered on its floor
tile) or embedded in a live enemy's `Enemy.embedded_items` (a smaller `GameState.
TORCH_BURN_LIGHT_RADIUS` (1) shadowcast centered on its carrying enemy's current `grid_pos` — a
torch stuck in a burning creature lights less than one lying in the open) — recomputed from
scratch every call, same "Light cantrip"
union pattern (`_compute_shadowcast` + a pooled-`Sprite2D` glow, see below) but with **zero**
persistent registry: an embedded torch's bubble moves with its enemy for free, and a burnt-out or
picked-up-and-relit torch just stops/starts contributing on the next recompute with no cleanup
code needed anywhere. See `scripts/items/CLAUDE.md`'s "Torch" section.

**Rule**: after every player action, call `_dungeon_floor.update_fog(grid_pos)` **before** `TurnManager.on_player_action_complete()`.

**Light cantrip — a second light emitter**: `update_fog()` unions a SECOND `_compute_shadowcast()`
call (same algorithm, walls still block it) centered on `GameState.light_source_pos` (radius
`GameState.LIGHT_SOURCE_RADIUS = 4`) into `_visible_tiles` whenever a Light source is active
(`light_source_pos != Vector2i(-1,-1)`) — a real light source, not a cosmetic effect, so tiles near
the lit object become visible/explored even far from the player. The exact same shadowcast result
(`lit_tiles`, computed once and passed straight into `_update_light_source_glow(lit_tiles)`) also
drives the visual glow: every tile the light actually reaches gets tinted with
`GameState.light_source_color` (pooled `Sprite2D`s + a shared 1×1 white texture, same
grow-only-pool convention as `show_aoe_preview()` — not a single decorative square over the source
tile). **Ends automatically the instant the lit object leaves its floor tile** (picked up, or
otherwise removed) — checked at the top of every `update_fog()` call via
`get_items_at(light_source_pos).has(GameState.light_source_item)` (the specific `Item` reference
touched at cast time, stored on `GameState.light_source_item` — not just "is *any* item still
there", so a stack sharing that tile doesn't falsely keep the light alive once the lit item itself
is gone). This auto-expiry mutates `GameState.light_source_pos`/`light_source_item` directly
(**not** via `GameState.clear_light_source()`) specifically to avoid re-entering `update_fog()`:
`light_source_changed`'s only listener is this same file's `_ready()` connection back to
`update_fog()` (see below), and this call is already mid-update, so re-emitting here would recurse
one level deep and risk double-firing `stairs_discovered`. `GameState.
light_source_changed` (emitted by `set_light_source()`/`clear_light_source()`, i.e. every OTHER
end condition — recast, rest, floor descent) is connected in `_ready()` to force an immediate
`update_fog()` call, so the light ending early hides the glow/pulls back the extra visibility right
away instead of waiting for the player's next move. See `scripts/entities/CLAUDE.md`'s "Wizard
spellcasting" section for the spell itself.

## Fog Cloud spell zone (Heavily Obscured terrain)
**Darkness** (Drow lineage spell, `scripts/entities/CLAUDE.md`'s "Elf" section) is a second,
independent Heavily Obscured zone — `GameState.darkness_pos`/`darkness_radius` mirror
`fog_cloud_pos`/`fog_cloud_radius` exactly, and `is_heavily_obscured(pos)` now checks both zones,
so everything below applies to Darkness too, not just Fog Cloud.

`_update_fog_cloud_visual()` (called every `update_fog()`, alongside the Light glow) tints
`GameState.fog_cloud_pos`/`fog_cloud_radius`'s tiles (and, generalized, `darkness_pos`/
`darkness_radius`'s) with a persistent overlay — pooled `Sprite2D`s + shared 1×1 white texture,
same convention as `_update_light_source_glow()`. **Each zone gets its own tint** so the two read
as visually distinct despite being mechanically identical Heavily Obscured terrain:
`DungeonFloor.DARKNESS_TINT` (`Color(0.10, 0.10, 0.13, 0.80)` — near-black, "true" magical
darkness) for Darkness, `DungeonFloor.FOG_CLOUD_TINT` (`Color(0.55, 0.55, 0.58, 0.72)` — a lighter
genuine gray) for Fog Cloud; a tile inside both zones renders with Darkness's tint (it's drawn
second into the shared `tile_colors` dict `_update_fog_cloud_visual()` builds). A raw Euclidean
disc per zone, deliberately **NOT LOS-filtered** — a brief attempt at LOS-filtering this visual was
tried and reverted per direct owner request: the full footprint should render whenever it's within
the player's own explored/FOV range, not disappear behind a wall the moment part of the zone dips
out of view. The actual "can't see into/out of it" blocking lives entirely in `update_fog()`'s
`_visible_tiles` stripping + dimmed-memory suppression (below), not in this visual paint. **WALL
tiles are excluded** from the painted set (`_data.get_tile(t.x, t.y) != DungeonData.TileType.WALL`)
so the cloud never paints over/hides a wall tile — the map geometry stays visible exactly where it
is, the cloud's own rendered footprint just ends up smaller wherever it overlaps a wall. Doesn't
itself union into `_visible_tiles`
the way Light does — the FOV shrink for a player standing INSIDE the cloud happens through the
shadowcast radius instead, not a separate visibility union. See `scripts/entities/CLAUDE.md`'s
"Conditions"/"Fog Cloud" sections for the full mechanic: `GameState.is_heavily_obscured(pos)`/
`is_blinded(pos)` are the canonical queries every ADV/DISADV combat site reads (Fog Cloud is
currently the only source of Heavily Obscured terrain), and `GameState.effective_fov_radius(pos)`
— read by this file's own `update_fog()`/`get_visible_enemies()` — collapses to a flat `1` for a
Blinded player regardless of every other FOV bonus, including darkvision.

**Can't see INTO a heavily-obscured area from outside it, even standing right at the edge** —
`_blocks_los(bx, by)` treats a heavily-obscured tile as opaque exactly like a WALL/GRASS tile
(gated on `not _ignore_magical_darkness and GameState.is_heavily_obscured(pos)`), so it's shared
by every consumer of that function: the player's own FOV shadowcast, the Torch/Light-cantrip
shadowcasts, AND `has_line_of_sight()` (enemy AI/search — symmetric, an enemy on the far side of
a cloud can't see the player through it either, matching Blinded's existing symmetric design).
Blocking propagation alone isn't quite enough — `_cast_light()`'s tile-marking happens BEFORE the
block check, so the very first fog tile along a ray would otherwise still read as "visible" (same
as how you can see a wall's own face). `update_fog()` additionally strips every
`GameState.is_heavily_obscured()` tile out of `_visible_tiles` whenever the player themselves
isn't inside the cloud (`not GameState.is_blinded(player_pos)`) and lacks
`GameState.player_stats.sees_through_magical_darkness` (see below) — so nothing inside a cloud,
not even its boundary tile, is ever revealed to an outside viewer, while a player already standing
inside it is unaffected (their own radius is already collapsed to 1 by `effective_fov_radius()`,
and `_cast_light()`'s unconditional tile-marking still lets them see their own immediate
neighbors — now correctly all 8 of them, diagonals included, not just the 4 cardinals; see
`scripts/entities/CLAUDE.md`'s Blinded condition entry for the Euclidean-vs-Chebyshev bugfix).
**The dimmed "remembered map" fog-of-war view is ALSO suppressed per-zone, not just for the
viewer's own blinded status**: `update_fog()`'s final per-tile render loop forces any tile inside
`GameState.is_heavily_obscured(tile_pos)` fully opaque (ignoring `_explored`) whenever the viewer
isn't themselves blinded and lacks `sees_through_magical_darkness` — bugfix: previously only the
viewer's OWN blinded status suppressed this dimming, so a tile inside a cloud that had been
explored before the cloud appeared there still rendered as a dimmed remembered floor plan when
viewed from outside, contradicting "can't see into a heavily-obscured area at all." `_explored`
itself is left untouched by this branch, so the tile renders normally again once the cloud ends.
**WALL tiles are excluded from this branch too** (`_data.get_tile(x, y) != DungeonData.TileType.
WALL`) — the spell doesn't affect solid rock, so a wall tile that happens to fall within the
zone's raw radius (its Euclidean disc doesn't know about walls) keeps rendering via the normal
explored/dimmed logic instead of suddenly going fully black (bugfix — a remembered wall shape used
to visibly "vanish" into solid black the instant a cloud's radius overlapped it; doors are NOT
excluded, they're still meant to be affected).
`DungeonFloor._ignore_magical_darkness: bool` — set true only around the player's own
`_compute_shadowcast()` call inside `update_fog()` when `Stats.sees_through_magical_darkness` is
true, reset immediately after — is the one bypass hook; nothing grants that flag today (a stub for
a future Warlock Devil's Sight-style feature, see `scripts/entities/stats.gd`) — **darkvision and
a hypothetical truesight bonus do NOT bypass this**, per 5e RAW, only that flag would.

**Blinded suppresses the dimmed "remembered map" fog-of-war view too**: normally a tile that's
been explored but isn't currently visible renders at partial fog alpha (0.65 — a dim memory of the
layout) instead of fully opaque. `update_fog()`'s final per-tile loop now additionally checks
`GameState.is_blinded(player_pos)` and, while true, renders every non-currently-visible tile fully
opaque (alpha 1.0) regardless of whether it was previously explored — so standing inside a Fog
Cloud/Darkness zone genuinely collapses vision down to just the flattened 1-tile shadowcast
`effective_fov_radius()` grants, not "can't see anything new, but can still see the remembered
room layout around me." Explored tiles are still marked (`_explored[tile_pos] = true`) so the
normal dimmed view returns immediately once the player leaves the cloud.

## AoE targeting preview
**Grid-bounds clipping**: every disc-shaped preview below (blue max-reach backdrop, purple/red
sphere footprint, two-tone ranged backdrop) is a raw Euclidean/Chebyshev disc computed from the
caster's position with **no wall/LOS filtering by design** — but that also meant, unfiltered, a
caster standing near the map's edge would paint tint tiles past `DungeonData.width`/`height`
(VOID). **The blue max-reach backdrop (`show_spell_range_preview()`) uses Chebyshev, not
Euclidean, for every non-cone spell** — it must match `try_cast_at()`'s own range check exactly
(`dist_cheb <= _effective_range(spell)`), or a diagonal tile at radius 1 (a touch spell like Mage
Armor/Shocking Grasp) rendered as visually "out of range" despite being a perfectly valid,
actually-castable target (bugfix — it used to share the sphere-footprint's Euclidean formula,
which is correct only for that footprint since `_resolve_sphere_aoe()`'s actual blast really is a
Euclidean circle, not the single-target range gate). **A cone (Burning Hands) is the one
exception, and no longer an approximated disc at all**: since the cone's aim is now snapped to
only 8 fixed directions (`SpellEffects.DIR8`), its true max-reach envelope is finite and exactly
computable — `player.gd._update_spell_aoe_preview()` unions `SpellEffects.cone_tiles()` over all 8
directions and calls `DungeonFloor.show_spell_range_preview_tiles(tiles)` (a sibling of
`show_spell_range_preview()`, same pooled-`Sprite2D`/texture, painting an exact tile list instead
of computing a disc) rather than approximating with a circle. **Bugfix history**: this backdrop
first always used Chebyshev (a square whose corners the cone could never reach), then a Euclidean
disc of radius `shape_size` (still under-representing the wedge's real width at its tip — a corner
tile at `forward=length,lateral=1` sits at Euclidean distance `sqrt(length²+1) > length`); both
approximations are now moot since 8-direction snapping makes the exact envelope cheap to compute
directly. The purple/red sphere footprint (`show_aoe_preview()`) and
the Fog Cloud visual stay Euclidean on purpose — both mirror a real Euclidean-distance game
mechanic (`_resolve_sphere_aoe()`, `is_heavily_obscured()`), not a Chebyshev range gate.
`DungeonFloor._in_grid_bounds(pos) -> bool` is the one bounds check `show_aoe_preview()`,
`show_spell_range_preview()`, and `show_ranged_range_preview()` each filter their generated tile
list through — a coordinate check only (`x/y` within `0..width`/`0..height`), never a
walkability/LOS filter, so it doesn't change the previews' own deliberate "ignores walls" shape,
just stops them rendering off the actual level. `show_cone_preview()` needed no change — its tiles
already come from `SpellEffects.cone_tiles()`, which per-tile-gates on `has_ranged_los()` and
therefore already excludes VOID/out-of-bounds tiles for free (VOID blocks `has_ranged_los()`).
`show_aoe_preview(center: Vector2i, radius: int)` / `show_cone_preview(origin: Vector2i, aim: Vector2i, length: int)` / `hide_aoe_preview()` — a small pooled-`Sprite2D` purple tint (1×1 white texture tinted via `modulate`, `z_index = 2`, same layer as the fog sprite — Node2D-world convention, not a Control), both funneling into a shared `_paint_aoe_preview_tiles(key, tiles)` helper. Sphere: every tile within `radius` (Euclidean, no LOS filtering — see `scripts/entities/CLAUDE.md`'s "Wizard leveled spells" for why) of `center`. Cone (Burning Hands): `SpellEffects.cone_tiles(origin, aim, length, self)` — the same LOS-gated 90°-arc tile-gather the actual cast resolver uses, so the preview always matches the real blast exactly (see `scripts/entities/CLAUDE.md`'s "More 1st-level spells"). Driven every frame by `player.gd._update_spell_aoe_preview()` while a sphere- or cone-shaped spell is armed for targeting. Each rebuild is cache-keyed on its own params so repeated calls with the same hovered tile are near-free. **Every** footprint tile with a known, non-invisible, currently-VISIBLE enemy standing on it (`is_tile_visible(t) and get_targetable_enemy_at(t) != null`) tints **red** (`AOE_PREVIEW_ENEMY_TINT`) instead of the default purple (`AOE_PREVIEW_TINT`) — a splash spell (Burning Hands, Fireball) hitting several enemies shows all of them red at once, not just the single tile the player is precisely aiming at; every other footprint tile stays purple. **The `is_tile_visible(t)` check is what keeps an enemy standing in a Heavily Obscured Fog Cloud tile from tinting red** when hovered/splashed from outside the cloud — that tile is still a mechanically valid blind-cast target (nothing about casting requires seeing the target — Magic Missile-style blind fire into unseen fog is intentional elsewhere, see `scripts/entities/CLAUDE.md`'s "Conditions"/"Fog Cloud"), but the preview must never reveal an enemy's exact position through a tile the caster can't actually see into; that tile just renders as plain purple footprint instead.

**Single-target ENEMY spells** (Fire Bolt, Shocking Grasp, Ray of Frost, Toll the Dead, Mind Sliver, Chromatic Orb, Witch Bolt — anything with `Spell.target_kind == ENEMY`, no AoE shape at all): `show_single_target_preview(tile: Vector2i, in_range: bool = true)`, also driven every frame from `player.gd._update_spell_aoe_preview()`. There's no footprint to paint here, so it only ever shows anything when the hovered tile actually has a known, targetable enemy on it, that tile is currently visible (`is_tile_visible(tile)` — same Fog Cloud exclusion as above), AND `in_range` is true — in that case it reuses the same single-tile `_paint_aoe_preview_tiles()` path, which tints red via the same generic enemy check above; an empty hovered tile, one beyond max range, or one the caster can't currently see into (Fog Cloud) hides the preview outright rather than showing an empty purple square or implying an out-of-range/unseen enemy would be hit.

**Enemies never tint red when outside the attack's actual max range** — a shared `in_range`/`center_in_range`/`allow_enemy_tint` gate threaded through every preview function above, computed by the caller (`player.gd`) as the same Chebyshev-distance-vs-spell-range check `try_cast_at()` itself enforces for spells (`PlayerSpellcasting._effective_range(spell)`), or `PlayerRanged.is_ranged_target_in_range()` for the Shift ranged preview. `show_single_target_preview()` hides outright when the hovered enemy is out of range; `show_aoe_preview()`'s `center_in_range` param (threaded into `_paint_aoe_preview_tiles()`'s `allow_enemy_tint`) still paints the purple splash footprint even when the aimed tile itself is out of range, but suppresses every red enemy tint in that footprint — **except** the one case that's supposed to still work: a splash spell aimed at the LAST tile actually within range (`center_in_range == true`) legitimately shows red for any enemy caught in the blast's natural overhang beyond that range circle, since the impact point itself is a valid cast target and the blast radius is centered on it, not gated per-tile. `show_cone_preview()` never gates on range at all — a cone is self-centered/direction-only (its own reach is a fixed length from the caster, see `try_cast_at()`'s cone exemption), so there's no "aim point out of range" concept for it. **A `Spell.bypasses_los` spell (Magic Missile) folds a real path check into this same `in_range` bool** — `player.gd._update_spell_aoe_preview()` additionally requires `DungeonFloor.has_walkable_route_ignoring_chasms(grid_pos, tile)` before allowing red, so the preview never lies about an enemy behind an unreachable wall/prop being hittable just because it's within the flat 12-tile range — see `scripts/entities/CLAUDE.md`'s Magic Missile entry.

**Shift+hover ranged-weapon preview**: `show_ranged_range_preview(center: Vector2i, normal_radius: int, long_radius: int)` / `hide_ranged_range_preview()` — its own independent pooled-`Sprite2D` set (`_ranged_range_rects`, `z_index = 1`, same layer as the spell blue backdrop but a separate pool so both can exist without stepping on each other), driven every frame by `player.gd._update_ranged_range_preview()` while **Shift** is held, a ranged weapon is equipped, and no spell is currently armed for targeting. The same function ALSO shows this preview (no Shift/equipped-weapon needed, checked first) whenever `GameState.quickbar_hover_thrown_item` is set — `hud.gd`'s `_on_qbar_slot_hover()`/`_on_qbar_slot_hover_end()` set/clear this transient field to the hovered item bar (item-bar-mode only, not ability-bar) slot's `Item` whenever it's a thrown weapon (`Item.Type.WEAPON` + `is_thrown`), so mousing over a Spear/Handaxe/Dagger/Javelin/Torch in the quickbar previews its range exactly like Shift-hovering it equipped would, and mousing off hides it again. This branch skips the world-tile enemy-highlight half (`show_single_target_preview()`) since the mouse is over UI, not a game-world tile. Two-tone, not flat: every tile within `normal_radius` (the weapon's `Item.range` — full accuracy) tints `RANGED_NORMAL_TINT` (light blue); every tile beyond that but within `long_radius` (`Item.long_range`, or the live FOV radius as a fallback for a weapon that doesn't set one — same fallback `PlayerRanged.is_ranged_target_in_range()` uses) tints `RANGED_LONG_TINT` (darker blue) — the same normal/long split that decides Disadvantage on the actual shot. The hovered tile's own red enemy highlight reuses `show_single_target_preview()` verbatim (shared with single-target spells, not a separate implementation) — so a targetable enemy under the cursor reads red exactly like it would for Fire Bolt, on top of whichever blue band that tile falls in.

**FOV-bonus overlays are suppressed while any of the above previews is showing** — `DungeonFloor.fov_bonus_overlay_suppressed: bool` / `set_fov_bonus_overlay_suppressed(v: bool)`, toggled once per frame from `player.gd._process()` (`spell_preview_active or ranged_preview_active`, the bools `_update_spell_aoe_preview()`/`_update_ranged_range_preview()` now return). Without this, the Torch's warm-yellow light-bubble glow and darkvision's dim-gray FOV-ring glow (both painted by `update_fog()`, see "Torch light bubble"/"Darkvision"'s own sections) would visually blend with the preview's blue/purple/red — three colors stacked on one tile instead of a clean single tint, e.g. a ranged Shift-preview tile that also happened to sit in the darkvision ring. `_update_torch_light_glow()`/`_update_darkvision_ring_glow()` both check the flag first and force every one of their own pooled sprites invisible, regardless of their own tile set, whenever it's true. Turning suppression back off immediately calls `update_fog(_player.grid_pos)` once to restore the correct glow state (rather than waiting for the next real player action to naturally recompute it).

**Blue "maximum reach" preview**: `show_spell_range_preview(center: Vector2i, radius: int)` / `hide_spell_range_preview()` — a second, independent pooled-`Sprite2D` overlay (`SPELL_RANGE_TINT`, a low-alpha blue, `z_index = 1` — one layer below the purple/red exact-footprint preview so the two compose correctly when both are visible), same cache-keyed convention. Shows a static disc around the caster covering every tile the currently-armed spell could conceivably hit, for **any** armed spell — not just AoE shapes; a plain single-target spell (Fire Bolt) gets one too. Driven from the same `player.gd._update_spell_aoe_preview()` call, computed per spell: cone (Burning Hands) → radius = `shape_size` (the cone's own length, since it always originates at the caster); sphere (Fireball) → radius = `range_tiles + shape_size` (the blast's center can land at the edge of range and still splash further out); everything else (single-target ENEMY/TILE spells) → radius = `range_tiles`.

---

## Traps (`_traps: Dictionary[Vector2i, Dictionary]`)
Value keys: `name, damage, msg, sprite_node, revealed, triggered, is_push, reusable, push_dir, wall_pos`

| Trap | Reusable | Effect | Notes |
|---|---|---|---|
| Spike | yes | bleeding 5 turns | — |
| Bear | no | slowed 20 turns | — |
| Fire | no | burning 4 turns | can cook Rotten Meat |
| Piston | no | push + damage | detectable only from push side |
| Tripwire | no | 3-6 Piercing + Poisoned (6 turns) to whoever's downrange | see "Tripwire trap" below — the one type NOT drawn from `TRAP_POOL` |

```gdscript
dungeon_floor.trigger_trap(pos)
dungeon_floor.reveal_trap(pos)
dungeon_floor.disarm_trap(pos)
dungeon_floor.search_around(pos) -> int   # returns number of traps revealed
```

Piston: `search_around` only detects from the `-push_dir` side.

**Throwing an item onto a trap** (`DungeonFloor.throw_item_onto_trap(pos, item) -> Vector2i`,
called from `PlayerThrowTool.do_throw()` whenever the target tile has ANY trap, before the generic
"drop it on the ground" path): activates the trap — reveals it and, for Fire/Bear, consumes its
single use exactly like an entity triggering it — but there's no dodge check and no damage/status
applied (an item can't dodge or bleed). Piston shoves the item exactly as far as it would shove an
entity (same 2-tile/wall-stop rule as `force_move_entity()`, reimplemented inline without a tween
since there's no `Entity` to move) — the returned landing tile differs from `pos` in this case.
Pit Spikes are inert against a thrown item (no reveal, no trigger — it just lands on top). A
flammable item (`Item.is_flammable` — every Scroll, set generically in `_build_floor_item()`/
`debug_panel._on_give_item()` off `item_type`) landing on a Fire Trap burns to ash instead of
landing anywhere (`Vector2i(-1, -1)` sentinel return) — Rotten Meat is a separate, pre-existing
special case (`cook_rotten_meat()`, checked first in `do_throw()`) that still cooks into Cooked
Meat regardless of this flag. See `scripts/items/CLAUDE.md`'s `Item.is_flammable` entry.

## Tripwire trap (`_dispensers: Dictionary[Vector2i, Dictionary]`)
A rope stretched wall-to-wall across a straight, genuinely 1-tile-wide corridor cell (or a
corridor's own entrance/exit into a room — detected by the identical check) + a hidden poison-dart
dispenser one tile further along the same corridor, **disguised as plain, unremarkable floor** (no
sprite, no `_data.grid` change — the "never touch the grid, only the cosmetic layer" rule from
"Hidden doors" above applies here too, just without even a tilemap-cell swap since there's nothing
to disguise: the tile was always ordinary floor). The one type placed by its own dedicated spawn
function, **not** drawn from `TRAP_POOL`/the generic per-tile `_spawn_traps()` loop, since it needs
narrow-corridor detection + a paired dispenser tile that no other trap type needs.

**Detection** (`DungeonFloor._spawn_tripwire_traps()`, called right after `_spawn_traps()`): for
every FLOOR tile, checks both axes for "FLOOR-FLOOR through this tile, WALL-WALL perpendicular" —
the same shape `_spawn_traps()`'s own Piston-trap `is_narrow` check already uses, just checked on
BOTH sides of the axis instead of one (a Piston only cares about the wall it's embedded in; a
Tripwire needs the full through-corridor). One of the two ends becomes the dispenser (`_pop_rng`-
shuffled, so which side isn't fixed), placed exactly one tile past the rope — no `*2` offset needed
since the axis-adjacent tile is already guaranteed FLOOR by the detection check itself. Up to
`TRIPWIRE_COUNT_MAX` (1) per floor, candidates reservation-checked against every other prop dict
(`_traps`/`_doors`/`_barrels`/`_floor_items`/`_blacksmiths`/`_shopkeepers`) exactly like every other
prop spawner. **Deliberately skips the "alternate path exists" bypass check** every other floor trap
uses — the whole point is that a straight 1-wide corridor usually has no alternate path, and that's
what makes a Tripwire dangerous rather than trivially avoidable.

**The rope itself lives in `_traps`** as an ordinary entry with an extra `"tripwire": true` marker
plus `"dispenser_pos"`/`"fire_dir"` (`Vector2i`s — where the dart comes from, and which direction it
travels) — this is deliberate, not an oversight: it means the rope gets the exact same passive/
active detection every other trap already has for free (`PlayerActions`' passive trap-proximity
sensing, Ctrl-Search's `reveal_trap()` loop in `search_around()`) with zero new detection code.
`_place_tripwire_trap()` builds its own rope sprite procedurally (`Image`/`ImageTexture`, a thin
brown stripe drawn perpendicular to `fire_dir` — no art asset exists or is needed), alpha-faded
until revealed exactly like every other trap's sprite.

**Trigger — walking onto it, or "shooting the rope"**: `trigger_trap()` branches to
`_trigger_tripwire()` before any of the normal push/DEX-dodge/damage logic runs (a Tripwire has no
dodge check of its own — the dodge, if any, is really "don't be standing in the dart's path", not a
roll). Per direct owner design, deliberately shootable/throwable/castable at from a DISTANCE too,
not just steppable-on: `DungeonFloor.try_shoot_tripwire(pos)` is called from every empty-tile attack
resolver — `PlayerRanged.ranged_attack_tile()`, `SpellEffects.cast_spell_at_tile()`/
`cast_leveled_at_tile()` — and `throw_item_onto_trap()` (already the generic "any thrown item hits
any trap tile" chokepoint) gained its own tripwire branch calling the same `_trigger_tripwire()`.
None of these roll anything special for "did the shot land on the rope" — landing an attack ON that
tile IS the trigger, exactly like walking onto it.

**The dart itself** (`_fire_dispenser_arrow()`): fires from `dispenser_pos`, stepping through
`fire_dir` up to `TRIPWIRE_ARROW_RANGE` (14) tiles — starting at the dispenser and immediately
passing through the rope's own tile and beyond, so a player who just walked onto the rope (already
standing there) is the very first thing checked and gets hit; a player who instead shot the rope
from further down the same corridor is, geometrically, usually also standing somewhere along that
same straight line (a 1-wide corridor has no "safe angle"), so shooting it from range is a real
gamble, not a guaranteed-safe disarm — direct owner design, confirmed: "if nobody/nothing is
standing in the path, nothing happens" is the whole rule, no separate dodge chance layered on top.
Stops at the first WALL/VOID/closed-door tile or the first Player/Enemy found; hits nothing if the
path is clear the whole way (harmless flavor line instead). A hit rolls a flat 3-6 Piercing
(`TRIPWIRE_DMG_MIN`/`MAX`) via the shared `_apply_trap_damage()` (same function every other trap
already uses — Player and Enemy targets both just work) plus applies the real Poisoned condition
(`"poisoned_condition"`, `TRIPWIRE_POISON_TURNS` = 6 turns — see `scripts/entities/CLAUDE.md`'s
"Conditions" table) via `GameState.apply_player_status()` / `Enemy.apply_status()`. **Single dart,
single use** — the dispenser's own `_dispensers[pos]["spent"]` flag is set the instant it fires
(or the instant it's looted, see below), and a second trigger on an already-spent dispenser just
logs "The dispenser is empty" with zero effect, matching the direct owner's 1-use-only answer.

**Looting instead of springing it**: once found via Search (`reveal_dispenser()`, hooked into
`search_around()`'s existing radius+LOS loop alongside the trap/hidden-door reveals — same
detection mechanism, separate dict since a dispenser isn't keyed by `_traps`), the dispenser can be
RMB-interacted (`PlayerActions.interact_action()`'s Priority 1.7, same exact-tile-vs-scan-8-
neighbors split as every other prop priority) to pry out its one **Poisoned Arrow** — a real,
single-use thrown `Item` (`scripts/items/CLAUDE.md`) — instead of ever triggering the trap. Looting
also sets `"spent": true`, so the rope becomes permanently harmless (walking across it afterward
just reveals an already-triggered-looking rope with an empty dispenser) — this is the reward for
finding it BEFORE walking into it, per the direct owner's own framing of the whole feature.

```gdscript
dungeon_floor.has_tripwire_at(pos) -> bool        # true only for a still-armed (unspent) Tripwire
dungeon_floor.try_shoot_tripwire(pos) -> bool      # ranged/thrown/spell empty-tile hook, see above
dungeon_floor.has_dispenser_at(pos) -> bool
dungeon_floor.get_dispenser_at(pos) -> Dictionary  # {revealed, spent, tripwire_pos}
dungeon_floor.reveal_dispenser(pos) -> bool        # called from search_around()
dungeon_floor.loot_dispenser(pos) -> Item          # null if not found yet or already spent
```

## Forced movement (`force_move_entity`)
```gdscript
dungeon_floor.force_move_entity(entity: Node2D, direction: Vector2i, max_distance: int, deal_damage: bool = false, trap_sprite: Sprite2D = null) -> int
```
Generalized from the old piston-trap-only `_push_entity`. Walks `entity` step-by-step in `direction`, stopping early on wall/occupant collision; returns tiles actually moved. `deal_damage=true` reproduces the original piston-trap splash damage (piston traps still pass `true`). World Tree's Grip of the Forest (pull toward player, recomputing direction each step so off-axis targets still land adjacent) and Branching Strike R3 (push 1 tile away) both pass `deal_damage=false`. Reuse this for any future forced-movement talent/trap instead of writing a new mover.

**`resolve_push(enemy: Enemy, direction: Vector2i) -> void`** — a separate 1-tile-only pusher used by the Heavy Crossbow's **Push** weapon mastery (`scripts/items/CLAUDE.md`), *not* built on `force_move_entity()` because it needs non-generic per-destination-tile outcomes: WALL → flat 1d4 Bludgeoning damage, no movement (instead of the piston splash formula); a trap tile → moves the enemy there then calls `trigger_trap(dest, enemy)`; **CHASM** → `force_move_entity()` treats CHASM as blocking (not walkable) so it can't be reused here — `resolve_push()` instead removes the enemy outright (counts as a kill for exp) and, if it was a boss, appends a freshly-rolled loot item (`_roll_boss_loot_item()`, factored out of `drop_boss_loot()`) to `GameState.pending_chasm_items` and emits `GameState.boss_defeated(enemy.enemy_id)` (this chasm path is a boss death too — the Tier 2 gate must still fire) so the loot surfaces on the next floor down via the existing `_spawn_pending_chasm_items()` drain (see "Spawning" below — that mechanism was already generalized past ammo, so no changes were needed there). Called from `PlayerRanged.ranged_attack()` after a non-lethal Push-mastery hit.

---

## Barrels + flammable props (`_barrels: Dictionary[Vector2i, Dictionary]`)
Value keys: `sprite: Sprite2D, burning: bool, material: String, ac: int, hp: int, max_hp: int`. A
solid obstacle prop (1-3 per floor, `_spawn_barrels()`) that blocks movement —
`is_walkable()`/`is_walkable_for_enemy()`/`is_walkable_for_companion()` all treat an unburnt
barrel tile as blocked, **regardless of `burning`** — until it's actually destroyed (HP hits 0),
at which point it disappears. Modeled on Shattered Pixel Dungeon's Sewer-level Barrel (a
`Terrain.FLAMABLE` tile, not its own entity/class, that resolves to an empty tile once burnt down).
**Placement is confined to room interiors** — candidates are gathered per
`_data.rooms` rect (corridors are carved outside every room rect, so this alone keeps barrels out
of them), with rect-corner tiles preferred over other room floor tiles (`RngUtil.shuffle`'d
separately, corners first) so clustering 2-3 in one room's corners is the common case. Every
candidate is placement-checked with `_bfs_reachable(player_start, stairs_pos, exclude)` (same
connectivity guard `_spawn_locked_doors()` uses, `exclude` growing with each barrel already placed
this floor) and skipped if placing it there would disconnect player_start from stairs_pos — a
barrel can never be the thing that blocks the only path.

`dungeon_floor.has_barrel_at(pos) -> bool`

**Material/AC/HP**: `MaterialTable.ac_for(material)` (`scripts/items/material_table.gd`, a generic
material-name → AC lookup — Cloth/Paper/Rope 11, Crystal/Glass/Ice 13, Wood/Bone 15, Stone 17,
Iron/Steel 19, Mithral 21, Adamantine 23) resolves each prop's `ac` from its `material` field at
spawn time. Both Barrels (`BARREL_MATERIAL = "wood"`, `BARREL_MAX_HP = 5`) and Doors
(`DOOR_MATERIAL = "wood"`, `DOOR_MAX_HP = 10`) are Wood. **Physical damage (not just fire)**: `DungeonFloor.damage_prop_at(pos, amount) -> Dictionary`
(`{"hit","kind","destroyed","damage"}`) is the generic chokepoint for a Barrel or closed (locked
or unlocked) Door taking a direct hit — no attack roll (a stationary prop can't dodge, same
convention fire already used), always applies `amount` to its `hp`, destroys it at 0 exactly like
`tick_burning_props()`'s own burn-down (frees the sprite/lock-icon, erases the dict entry, calls
`update_fog()`). Two call sites today: `PlayerRanged.ranged_attack_tile()` (a ranged shot aimed at
an empty tile — `_roll_prop_damage()` rolls the equipped weapon's normal damage dice) and
`PlayerThrowTool._throw_weapon()`'s no-enemy branch (a thrown weapon landing on the tile instead of
an enemy). `ac` is still unread by either (stored for a possible future "roll to hit a prop"
refinement) — today the shot always lands, mirroring fire's own unconditional per-tick damage.

**Ignition is generic** — `dungeon_floor.ignite_flammable(pos: Vector2i) -> bool` is the single
chokepoint every fire source calls: a barrel OR an OPEN/CLOSED (not locked) door both count as
flammable (mirrors SPD's `Terrain.FLAMABLE` flag, which covers ordinary doors alongside
grass/barrels but excludes locked/crystal doors). No-ops if the tile has neither, or is already
burning. Call sites: Fire Bolt/Fireball/Burning Hands hitting a tile (`spell_effects.gd`, same
call sites as the existing grass-ignite hook — see `scripts/entities/CLAUDE.md`'s "Wizard
spellcasting"/"More 1st-level spells"), a thrown **lit** Torch landing on an empty tile
(`player_throw_tool.gd._throw_weapon()`), and fire spreading from an adjacent burning entity (see
below).

**Burn damage (HP-based, not a flat turn timer)**: `tick_burning_props()` — called directly from
`player.gd`'s `_on_turn_started()` (alongside `tick_torches()`), NOT via a `TurnManager` signal —
rolls `DungeonFloor._roll_fire_tick_damage()` (2d4) once per burning prop each tick and subtracts
it from that prop's own `hp` — a Barrel (5 HP) typically burns down in 1-2 ticks, a Door (10 HP)
in 2-3, rather than always exactly 3 turns. At 0 HP the prop is destroyed outright — sprite (+ a
door's lock icon) freed, dict entry erased, `update_fog()` called once if anything burned this
tick. A burnt door is **gone permanently** (unlike `close_door()`, which just re-closes it —
burning removes the door from `_doors` entirely, so the tile stays passable forever, matching
SPD's door-burns-to-EMBERS terrain change). While burning, the Barrel/Door's own sprite is tinted
`FIRE_TINT` (orange). This is a round-level tick (props aren't turn-having entities), fired once at
the start of the player's own turn — i.e. "the start of the round," not tied to any one creature's
action.

**Visual "this is on fire" indicator**: `_update_burning_tiles_glow()` (`DungeonFloor`, called
every `update_fog()`, same pooled-`Sprite2D` convention as the Light/Fog-Cloud/Torch glows above) —
a translucent red overlay over every currently-burning Barrel, Door, and burning GRASS tile
(`_burning_grass`, see below). Grass has no sprite of its own to tint (a `TileMapLayer` cell can't
be modulated per-instance the way a `Sprite2D` can), so this overlay is its only visual cue; for a
Barrel/Door it layers on top of the existing `FIRE_TINT` sprite tint. Not suppressed by
`fov_bonus_overlay_suppressed` (that flag is specifically for FOV-bonus rings — Torch/darkvision —
clashing with a spell-targeting preview; this is a different kind of indicator, same as the Fog
Cloud/Light glows, which also ignore that flag). **Gated on `is_tile_visible(pos)`** — bugfix: this
used to show unconditionally regardless of visibility, so an outside viewer could tell something
was burning deep inside a Fog Cloud/Darkness zone they had no actual sight into; `_visible_tiles`
already correctly excludes anything inside such a zone from an outside viewer (per `is_blinded()`'s
symmetric rule) while still including the player's own immediate neighbors when they're the one
standing inside the cloud, so gating on it here covers both cases for free.

**Standing on a burning prop burns the occupant — at the start of THAT creature's own turn, not a
single global tick**: `DungeonFloor.is_tile_on_fire(pos)` / `tick_fire_damage_for(entity: Entity)`
are called individually by each entity right at the top of ITS OWN turn —
`Player._on_turn_started()`, `Enemy.decide_turn()`, `Companion.decide_turn()` — rather than being
swept once for everyone from a single round-level tick (direct owner request: the damage should
land "at the start of their own turn," not at whatever moment a global tick happens to fire
relative to that entity). `tick_fire_damage_for()` checks `entity.occupied_tiles()` (footprint-
aware — matches a Large enemy's multi-tile occupancy) against `is_tile_on_fire()` (true for a
burning DOOR **or** a currently-burning GRASS tile, `_burning_grass` — see below), rolls its own
independent 2d4 Fire hit via `_roll_fire_damage_instance()` (a real `CombatMath.
build_damage_instance()`/`encode_damage_instance()` roundtrip — NOT the bare-int
`_roll_fire_tick_damage()` a prop's own HP-loss roll uses, since this roll's number IS shown to the
player: every displayed damage number needs a hoverable `dmg:` tooltip per root CLAUDE.md's
chat-log-tooltip rule, reusing the existing generic `fmt_dmg_tooltip()` handler — no new
formatter needed), and handles the normal floater/log line/kill path (an enemy killed this
way grants half `exp_reward` via `GameState.gain_exp()`, same reduced-reward precedent as a trap
kill; a killed Enemy's `decide_turn()` returns a harmless `{"type": "wait"}` immediately afterward
— `TurnManager._run_single_enemy()` already guards on `not stats.is_dead()` before calling
`execute_turn()`, so bailing out early here is safe). **Barrels can never trigger this** —
`is_walkable()`'s unconditional `_barrels.has(pos)` block means nothing can ever stand on one,
burning or not. **Ordering bugfix**: `player.gd._on_turn_started()` calls `tick_fire_damage_for(self)`
**before** `tick_burning_props()` (below) — the latter can destroy the very door/finish the very
grass tile the player is standing on this same tick (its own HP-loss roll, or a grass tile's
one-round expiry), which would silently rob the player of their last tick of damage if checked
afterward.

**Grass burning is a real, spreadable, one-round state — not an instant conversion**:
`DungeonFloor._burning_grass: Dictionary[Vector2i, bool]` (a GRASS tile mid-burn) +
`ignite_grass(pos) -> bool` (starts it — no-ops if not GRASS or already burning) +
`_tick_burning_grass(pre_tick_snapshot)` (converts every tile that was ALREADY in `_burning_grass`
before this round's own spread step to `TRAMPLED_GRASS` via `destroy_grass()`). Grass deliberately
has **no HP pool** (direct owner design, unlike Barrel/Door) — it's a one-round transient flag: a
tile ignited THIS tick survives untouched into `_burning_grass` (added after the pre-tick snapshot
was taken), so it gets one full round to burn its occupant and spread to its neighbors (see below)
before the FOLLOWING round's `_tick_burning_grass()` call finally converts it. Every fire source
that ignites a GRASS tile — Fire Bolt/Fireball/Burning Hands hitting a tile (`spell_effects.gd`), a
thrown lit Torch landing on grass (`player_throw_tool.gd`), and prop-to-grass/grass-to-grass spread
below — calls `ignite_grass()` instead of `destroy_grass()` directly; `destroy_grass()` itself is
now only ever called from `_tick_burning_grass()`, plus the unrelated "walking tramples grass
underfoot" call sites in `player.gd`/`enemy.gd` (movement, nothing to do with fire).

**Fire spreads from a burning entity standing adjacent** (Chebyshev 1) to an unlit barrel/door —
`_check_burning_ignition_sources()`, called at the end of every `tick_burning_props()` tick, checks
`GameState.player_stats.burning_turns > 0` only (enemies don't carry a burning status yet — see
`scripts/entities/CLAUDE.md`'s "Status effects" table). Covers e.g. a player who caught fire from a
Fire Trap walking next to a barrel.

**Fire also spreads between adjacent flammable PROPS/GRASS themselves, at the start of every
round** (direct owner request, independent of the player-adjacency check above) —
`_spread_fire_between_props()`, called right after it from the same `tick_burning_props()` tick,
right before `_tick_burning_grass()` finalizes anything: any currently-burning Barrel or Door
ignites a not-yet-burning Barrel/Door **or GRASS tile** within Chebyshev 1 (8 directions — same as
before); any currently-burning GRASS tile spreads only along the **4 cardinal directions**
(`GRASS_SPREAD_DIRS` — N/S/E/W only, direct owner request: "should spread in the four main
directions," an orthogonal wildfire rather than a diagonal blob) to its own grass/barrel/door
neighbors, via `ignite_grass()`/`ignite_flammable()`. This is what makes a lit patch of grass
actually travel outward one ring per round instead of just vanishing on the spot. Web/pavučina
isn't flammable yet (no `"burning"` field on `_webs`) — extend this function once it is.

## Blacksmith prop (`_blacksmiths: Dictionary[Vector2i, Dictionary]`)
Value keys: `sprite: Sprite2D`. Same dict-of-tile convention as `_barrels`/`_traps`/`_doors`, but no
burn/state of its own — a solid, impassable landmark tile (blocked in `is_walkable()`/
`is_walkable_for_enemy()`/`is_walkable_for_companion()`, same treatment as `_barrels`) placed by
`_spawn_blacksmith(rect)` (`BlacksmithRoom` content, guaranteed on floor 4 — see
`scripts/dungeon/CLAUDE.md`). Reuses `crate.png` with a distinct tint (`BLACKSMITH_TINT`) as a
placeholder — no dedicated anvil/blacksmith art exists yet. `has_blacksmith_at(pos) -> bool`.
`_load_floor()`'s floor-unload cleanup block frees the sprite and clears `_blacksmiths` alongside
`_traps`/`_doors`/`_barrels`/`_floor_items` (previously missing — a stale entry would leak the
sprite and keep blocking that tile as impassable on a freshly regenerated floor).

**Interaction**: bump-to-open (`player.gd._try_move()` intercepts a move into a blacksmith tile
before the walkability check and calls `PlayerActions.open_blacksmith_panel()` instead of blocking
pointlessly) and RMB (`PlayerActions.interact_action()`'s Priority 1.5, same exact-tile-vs-
scan-8-neighbors split as the trap/door priorities). Both open `scripts/ui/blacksmith_panel.gd` —
see `scripts/ui/CLAUDE.md` and `scripts/items/CLAUDE.md`'s "WeaponForge" section for what it does.

## Shopkeeper prop (`_shopkeepers: Dictionary[Vector2i, Dictionary]`)
Value keys: `sprite: Sprite2D, stock: Array[Item]`. Same solid-impassable-landmark-tile treatment as
`_blacksmiths` (blocked in `is_walkable()`/`is_walkable_for_enemy()`/`is_walkable_for_companion()`)
placed by `_spawn_shop(rect)` (ShopRoom content, `scripts/dungeon/CLAUDE.md`). No dedicated NPC
sprite exists yet (`sprites/characters/npcs/` is reserved but empty — root CLAUDE.md's Sprite
Assets) — tries `SHOPKEEPER_TEX_PATH` (`res://sprites/characters/npcs/dwarf_m/idle_1.png`) first
via `ResourceLoader.exists()`, falling back to the same `crate.png` placeholder Blacksmith uses,
distinguished by its own `SHOPKEEPER_TINT`.

**Stock generation**: filters `ITEM_POOL` to entries with `gold > 0` and floor/level eligibility
(same `fmin`/`fmax`/`is_scroll_level_eligible()` gate `_spawn_items()` uses), shuffles on `_pop_rng`,
takes 4-6 distinct entries (`SHOP_STOCK_MIN`/`SHOP_STOCK_MAX`), guarantees at least one FOOD entry
(falls back to "Ration" by name if none of the random picks were food) — built via
`_build_item_from_pool(d)` (the item-construction half of `_build_floor_item()`, factored out so
shop stock can build real `Item`s without ever calling `place_item_on_floor()`). **Stock is
overlay-only** — never laid on the floor, no restock, discarded when the floor unloads (not
serialized, not regenerated on revisit).

```gdscript
dungeon_floor.has_shopkeeper_at(pos) -> bool
dungeon_floor.get_shopkeeper_stock(pos) -> Array[Item]   # LIVE array — shop_panel.gd mutates it directly on Buy
```

**Interaction**: bump-to-open (`player.gd._try_move()`, same pre-walkability-check intercept as
the Blacksmith prop) and RMB (`PlayerActions.interact_action()`'s Priority 1.6, same exact-tile-
vs-scan-8-neighbors split). Both open `scripts/ui/shop_panel.gd` — see `scripts/ui/CLAUDE.md` and
`scripts/autoloads/CLAUDE.md`'s gold economy section.

## Mold (guaranteed once-per-run placement)
`DungeonFloor._spawn_mold()`, called right after `_spawn_special_rooms()` in `_load_floor()`:
no-ops unless `GameState.current_floor == GameState.mold_target_floor` (rolled once via
`Rng.range_i(1,4)` at run start, see `scripts/autoloads/CLAUDE.md`) and `not GameState.
mold_spawned`. Places one `ITEM_POOL` "Mold" item (looked up by name, sentinel `fmin`/`fmax = 99`
keeps it out of the generic floor-loot roll — same pattern as Healing Herb) on a random walkable
tile via `_build_floor_item()`, then sets `mold_spawned = true`. Guarantees exactly one Mold —
and therefore one Blacksmith craft opportunity — per run at this pass; adding Mold to the regular
floor-loot pool for extra copies is a documented, not-yet-done follow-up.

## Spider Web (`_webs: Dictionary[Vector2i, Dictionary]`)
Value keys: `sprite: Sprite2D, hp: int, ac: int`. A lightweight destructible-terrain dict, same
shape/convention as `_barrels` above but with no burn-tick timer — a web only ever goes away via
`Player._attempt_web_escape()`'s successful STR check, never on its own. Never pre-seeded at
generation time (unlike Barrels/Traps) — placed only by `Enemy._execute_cast_web()` the instant a
Spider's Web ability lands (DEX save failed), always at the restrained target's OWN tile, matching
the real spell's "web appears at the target's square" text. See `scripts/entities/CLAUDE.md`'s
"Spider" section for the full ability/condition mechanism (the Restrained condition itself lives on
`Stats.web_restrained`/`web_escape_dc`, not here).

```gdscript
dungeon_floor.spawn_web(pos: Vector2i)     # no-op if pos already has a web
dungeon_floor.destroy_web(pos: Vector2i)   # frees the sprite, erases the dict entry
dungeon_floor.has_web_at(pos: Vector2i) -> bool
```

`ac`/`hp` (10 / 5, matching the real spell's stat block, vulnerable to Fire / immune to Poison and
Psychic per its text) are currently pure flavor data — this engine has no attack-a-structure system
yet, so nothing can actually deal damage to a web directly; the STR-check escape route in
`player.gd` is the only thing that ever removes one today. **No art yet** — `WEB_TEX_PATH` is
guarded with `ResourceLoader.exists()` exactly like `BARREL_TEX_PATH` above, so `spawn_web()` is
fully wired mechanically but renders no visible sprite until one is authored.

## Doors (`_doors: Dictionary[Vector2i, Dictionary]`)
Value keys: `is_open: bool, locked: bool, sprite: Sprite2D, tex_open, tex_closed, material: String, ac: int, hp: int, max_hp: int, lock_icon?: Sprite2D, burning?: bool` — `material`/`ac`/`hp`/`max_hp` are set at spawn time (Wood, AC 15, 10 HP — see "Barrels + flammable props" above); `lock_icon`/`burning` only appear once locked/`ignite_flammable()` has set the door alight respectively.

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

**Taking physical damage**: a closed door (locked or not) can be shot/thrown at like a Barrel — see
`DungeonFloor.damage_prop_at()` in "Barrels + flammable props" above. Deliberately excludes a
still-hidden SecretRoom door (`"hidden": true`, see below) — it reads as a plain wall to this
chokepoint too, so blind-shooting a wall tile can never damage/reveal one before it's found.

**Generation-time locking**: `_spawn_locked_doors()` runs after `_spawn_items()`. Picks 1 door per floor whose removal doesn't disconnect spawn from stairs (`_bfs_reachable` validation). Places 2–3 reward items from `DungeonFloorData.ITEM_POOL` in the room behind the locked door. Uses `_bfs_collect()` to find tiles unreachable without that door. **Skips entirely if the floor rolled a TreasureRoom** (`_data.room_metadata` has a `"treasure"` entry) — one gated-loot room per floor, and the TreasureRoom already is it (special-rooms-economy-design.md §4.2).
**Player locking**: F key on adjacent CLOSED UNLOCKED door with Thief Tools → DC 10 DEX Sleight of Hand. Fail consumes Thief Tools.
**Unlocking**: Player walks into locked door → auto-unlock (free). Or F on locked door → unlock+open (spends action).

## Hidden doors (SecretRoom, session 7f)
A hidden door is an ordinary `_doors` entry with `"hidden": true` — not a separate `TileType` or
dict. Its walkability/LOS-blocking already fall out for free from the existing "closed door"
checks every one of those functions already has (`is_walkable()`/`is_walkable_for_enemy()`/
`is_walkable_for_companion()`'s `_doors.has(pos) and not is_open` branch, `_blocks_los()`/
`_blocks_projectile()`'s identical check) — a hidden door is simply always `is_open == false`. The
only things session 7f actually adds:

- **`has_door_at(pos)`** returns `false` while `_doors[pos].get("hidden", false)` — the single
  chokepoint every door-interaction path reads (bump-open in `player.gd`, F/RMB Priority 2 in
  `PlayerActions.interact_action()`, enemy door-opening, `ignite_flammable()`,
  `_spawn_locked_doors()`'s candidate scan) — so none of them ever notice a still-undiscovered
  secret door. `search_around()` is the one place that reads the **raw** `_doors` dict directly,
  bypassing this filter.
- **Visual**: `_spawn_secret_room(rect)` swaps the door tile's `TileMapLayer` cell to
  `SOURCE_WALL` (`tilemap.set_cell(pos, SOURCE_WALL, ATLAS_ORIGIN)`) and hides its `Sprite2D`
  (`visible = false`) — same one-tile-mutation pattern `destroy_grass()` uses. `_data.grid` itself
  is never touched (stays FLOOR) — walkability/LOS already come from the `_doors` dict, so this is
  purely cosmetic, restored on reveal.
- **`_spawn_secret_room(rect)`**: finds the room's one connecting door on its perimeter ring (same
  `rect.grow(1)` scan `_spawn_treasure()`'s door-lock loop uses), marks it hidden, then spawns a
  reward inside the room — 2-3 `ITEM_POOL` rolls (one biased to the **top half by `gold_value`**,
  a rarity proxy — sorted copy of the eligible list, slice the first half, roll one from there)
  plus a guaranteed `_pop_rng.randi_range(20, 30) + 2 * current_floor` gold pile — "strictly
  better than a locked-door room" since finding it costs deliberate search turns. If
  `_spawn_doors()`'s 65%-probabilistic roll missed this room's one junction (no door object
  exists there at all), the whole reward is skipped outright — stricter than TreasureRoom's own
  "loot still spawns, just undefended" degrade, since an unguarded top-tier reward is worse than
  none.
- **`_reveal_secret_door(pos)`**: called only from `search_around()`'s new second loop (over a
  `_doors.keys()` snapshot, same radius+LOS gate the trap-reveal loop already uses). Un-hides the
  sprite, restores the tilemap cell to `SOURCE_FLOOR`, logs
  `"You discover a hidden door!"` directly — kept separate from the trap-count summary
  `PlayerActions.search_action()` builds from `search_around()`'s returned int, so that call site
  needed no changes.
- **`ignite_flammable(pos)`**'s door branch gates on `not _doors[pos].get("hidden", false)` too —
  a Fire Bolt hitting what looks like a plain wall can't accidentally ignite/out a secret door.
- **`_spawn_locked_doors()`** skips a floor with a `"secret"` `room_metadata` entry (same
  treatment as `"treasure"`) — it runs before `_spawn_special_rooms()`, so without this it could
  lock-and-reward the SecretRoom's own sole door before `_spawn_secret_room()` hides it.

No new interaction, no new key — Ctrl-search (`PlayerActions.search_action()` →
`search_around()`) already existed for traps; this just gives it a second thing to find.

---

## Floor items (`_floor_items`, `_floor_item_sprites`)
`_floor_items: Dictionary[Vector2i, Array[Item]]` — **tiles stack**: multiple items can occupy the same position (oldest first in the array). `_floor_item_sprites` holds exactly one `Sprite2D` per occupied tile, always showing the newest (last-appended) item's icon — `place_item_on_floor()` swaps the existing sprite's texture in place rather than spawning a second sprite or bumping the drop to an adjacent tile. This is what lets a volley of arrows shot at the same spot all pile up on one tile instead of scattering.

**Sprite2D scale rule**: `place_item_on_floor()` clamps the texture's longest side to `FLOOR_ICON_MAX_PX` (24px, 1.5x `TILE_SIZE`) with a **uniform** scale (`min(1.0, FLOOR_ICON_MAX_PX / max(tex_w, tex_h))` applied to both axes) — a `Sprite2D` has no `ignore_texture_size`-style flag like `TextureRect` (see `scripts/ui/CLAUDE.md`'s TextureRect rule), so without an explicit scale it renders at the source PNG's native resolution. Scale never exceeds 1.0 (never upscales), so already-tile-sized art (`sprites/items/`/`sprites/weapons/`, ~16px, weapons often tall/thin like 10x37) is untouched and can still poke past the tile edge same as always. `res://icons/spells/` PNGs (Scroll of &lt;Spell&gt; floor drops) are thousands of px across and get scaled down to fit. **Do not scale non-uniformly** (independent x/y factors) — that squashes non-square art like weapon sprites wide-and-short; always derive one scalar from the longest side and apply it to both axes. Any other code path that puts a `Sprite2D` on the floor/world from a variable-resolution source texture needs the same treatment.
```gdscript
dungeon_floor.place_item_on_floor(pos: Vector2i, item: Item)   # appends to the stack at pos
dungeon_floor.get_item_at(pos: Vector2i) -> Item                # topmost/newest item only (for tooltips/inspect)
dungeon_floor.get_items_at(pos: Vector2i) -> Array[Item]         # full stack, oldest first
dungeon_floor.remove_floor_item(pos: Vector2i)                   # clears the whole stack + sprite at pos
dungeon_floor.cook_rotten_meat(trap_pos: Vector2i) -> Item  # erases Fire Trap, returns Cooked Meat (food_value=75)
```
`cook_rotten_meat` only called from `PlayerThrowTool.do_throw()` (`scripts/entities/player_throw_tool.gd`) when `trap["revealed"] == true`. `place_item_on_floor` is also called from `PlayerAmmo`'s ranged-ammo landing resolver (`resolve_ammo_landing()`) — see "Ammo items" in `scripts/items/CLAUDE.md`.

**Never lands on an unwalkable tile**: `place_item_on_floor(pos, item)` first runs `pos` through
`_resolve_item_drop_pos(pos)` — a no-op when `is_walkable(pos)` is already true, otherwise a
ring-search (Chebyshev radius 1..5) for the nearest tile that is, redirecting the drop there
instead. Fixes a real bug: a ranged miss or thrown-item throw landing exactly on a Barrel/
Blacksmith/Shopkeeper/closed-door tile used to become permanently unreachable (the player can
never stand on that tile to pick it up) — every caller of `place_item_on_floor` gets this for free,
no per-call-site change needed.
**Pickup**: `PlayerActions.check_pickup()` (`scripts/entities/player_actions.gd`) calls `get_items_at()` + `remove_floor_item()` to grab the entire stack on the player's tile in one step (walking onto a pile of arrows returns all of them at once), collapsing same-named items into one `"xN"` log line.

---

## Spawning
Order matters — every terrain PROP (trap/door/barrel/floor item/blacksmith) is placed **before**
`_spawn_enemies()` runs, and `_spawn_enemies()`'s candidate filter excludes every tile already
claimed by `_traps`/`_doors`/`_barrels`/`_floor_items`/`_blacksmiths` on top of its existing
start-room/boss-room/player_start/stairs_pos exclusions. This is why the call order below puts
enemies near the end, not first — the old first-in-line ordering let an enemy claim a tile that a
door/barrel/blacksmith placed moments later would then coexist on (an enemy standing in a doorway,
or directly under the Blacksmith prop), since nothing downstream re-checked occupied enemy tiles.
Props themselves already cross-check each other correctly in their existing relative order
(barrels/blacksmith both skip `_doors`/`_traps`/`_floor_items` tiles; blacksmith also skips
`_barrels`) — the only missing direction was enemies vs. everything placed after them, fixed by
moving `_spawn_enemies()` to run after all of it instead of adding one-off enemy-occupancy checks
to every prop spawner.
```gdscript
_spawn_traps()          # places traps by type
_spawn_tripwire_traps() # up to 1 Tripwire + hidden dispenser per floor, see "Tripwire trap" above
_spawn_doors()          # see "Doors" below
_spawn_barrels()        # 1-3 flammable obstacle props/floor on plain FLOOR tiles, see "Barrels + flammable props" above; runs right after _spawn_doors()
_spawn_items()          # 2-3 random items from DungeonFloorData.ITEM_POOL; calls _build_floor_item()
_spawn_locked_doors()   # locks 1 door/floor that doesn't block spawn→stairs; places 2-3 rewards inside
_spawn_special_rooms()  # dispatcher: matches _data.room_metadata's type_id ("shop"/"treasure"/"garden"/"secret"/"blacksmith") — the ONE place a type_id string is matched. All five are live: _spawn_treasure()/_spawn_garden_items()/_spawn_blacksmith()/_spawn_shop()/_spawn_secret_room()
_spawn_treasure(rect)   # session 7c: 3 guaranteed ITEM_POOL rolls + 1 gold pile (15-25 + 2×floor) inside rect; locks the room's one connecting door (manual lock, no AudioManager at gen time — mirrors _spawn_locked_doors()); floor >= 4 also gets 1-2 non-wall TRAP_POOL traps via the shared _place_floor_trap() helper. No-ops if rect is empty (BSP-fallback floor) or the room has no candidate tiles
_spawn_garden_items(rect)  # session 7d: 1-2 "Healing Herb" ITEM_POOL entries (looked up by name, fmin/fmax=99 sentinel keeps it out of every generic filter) on the GRASS tiles GardenRoom.paint() already carved. No-ops if rect is empty
_spawn_blacksmith(rect) # one impassable prop tile (see "Blacksmith prop" below) guaranteed on floor 4's BlacksmithRoom. No-ops if rect is empty
_spawn_shop(rect)       # session 7e: one impassable shopkeeper prop tile + generated 4-6-item Buy/Sell stock (see "Shopkeeper prop" below). No-ops if rect is empty or the room has no candidate tile
_spawn_secret_room(rect) # session 7f: hides the room's one connecting door + spawns a biased 2-3-item reward + gold pile (see "Hidden doors" below). No-ops if rect is empty or no door found on its perimeter
_spawn_mold()           # guaranteed once-per-run Mold placement (see "Mold" below), called right after _spawn_special_rooms()
_spawn_enemies()        # pulls from DungeonFloorData.ENEMY_POOL filtered by floor range, then CR-budgeted (see below), registers with TurnManager. Candidate tiles exclude every trap/door/barrel/floor-item/blacksmith tile placed above (see note above) in addition to start-room/boss-room. A Large-footprint entry (pool "size", scripts/entities/CLAUDE.md's "Multi-tile footprint") requires an entire free WxH block of eligible floor tiles (_footprint_fits()) — guarantees it never spawns in a 1-wide corridor; skips the slot outright if this floor's layout has no room for it
_spawn_boss()            # floor % 5 == 0 → picks from DungeonFloorData.BOSS_POOL; called from inside _spawn_enemies()
_spawn_pending_chasm_items()  # drains GameState.pending_chasm_items (ammo that fell into a chasm on the PREVIOUS floor) onto random walkable tiles of this floor; runs after _spawn_enemies(), before _setup_fog()
_spawn_gold_piles()     # 1-2 Type.GOLD piles of randi_range(5,10)+floor gold on random walkable tiles; appended after _spawn_pending_chasm_items() so every pre-existing _pop_rng draw keeps its position
```
**Seeded population (`_pop_rng`)**: all `_spawn_*()` randomness draws from `_pop_rng`, a `RandomNumberGenerator` re-created in `_load_floor()` with seed `run_seed ^ (current_floor * POPULATION_SEED_MIX)` — same run seed + floor always produces the identical population, which Phase-A save reloads depend on. Shuffles use `RngUtil.shuffle(arr, _pop_rng)`. **The spawn call order and the number of draws inside each function are load-bearing for reproducibility** — this is about determinism given fixed inputs, not a frozen draw *count*; every population feature added so far (this one included) legitimately changes how many draws happen. `_pop_rng` is load-time only — runtime rolls (trap triggers, boss loot at kill time, `resolve_push()` damage) use the `Rng` autoload's gameplay stream instead; never mix the two.

**CR-budgeted enemy spawning** (`DungeonFloor._pick_cr_budgeted_enemies()`, replacing the old flat `ENEMY_COUNT_MIN..MAX` random count): `_cr_budget(floor_num) = CR_BUDGET_BASE + floor_num * CR_BUDGET_PER_FLOOR` gives each floor an encounter budget; the picker repeatedly builds the subset of `eligible` (already floor-band-filtered) entries whose `"cr"` still fits the remaining budget and takes a uniformly-random one from it (not cheapest/priciest-first, so the exact combination still varies run to run), until nothing affordable is left or `CR_BUDGET_SAFETY_CAP` (12) is hit. A pool entry missing `"cr"` defaults to `CR_BUDGET_DEFAULT_CR` (0.25). No forced minimum count — a floor whose eligible band skews expensive (e.g. floor 8+'s Ogre) legitimately spawns fewer, stronger enemies instead of always 3-5. On boss floors the regular budget is scaled by `BOSS_FLOOR_BUDGET_SCALE` (0.4) before the loop runs; the boss itself (`_spawn_boss()`) always spawns unconditionally and never spends from this budget. The floor-linear stat-scaling formula in `Enemy._apply_stats()` is untouched — CR decides *which* enemies spawn together, not how strong any one of them is within its own band. Full rationale, calibration table, and deferred scope (per-room CR distribution, elite/pack variants, CR-derived `exp`): `docs/architecture/cr-budgeted-spawning-design.md`.
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
Gold piles are ordinary floor items of `Item.Type.GOLD` whose `gold_value` IS the pile size, built by `_make_gold_item(amount)` (name "Gold", icon `misc/coin_gold.png`). Three sources:
- **Floor scatter** — `_spawn_gold_piles()` (see spawn list above, `_pop_rng`).
- **Enemy drops** — `maybe_drop_enemy_gold(enemy)`: 30% chance (`Rng.chance`, gameplay stream — kill-time randomness, same split as `_roll_boss_loot_item()`) of `Rng.range_i(1,4) + floor/2` gold at the death tile. Called from `Enemy.die()` (the single chokepoint every death site ends with, same reasoning as `embedded_items`); no-ops for bosses.
- **Boss kill** — `drop_boss_loot()` additionally places a guaranteed `20 + 5 × floor` pile alongside the potion.

## Pending thrown-weapon drops (Goblin Minion, Orc Warrior)
`DungeonFloor._pending_thrown_weapon_drops: Array[Dictionary]` (`{"target": Node, "item": Item, "chance": float}`) + `queue_thrown_weapon_drop(target, item, chance: float = 0.5)` + `_resolve_pending_thrown_weapon_drops()` (connected to `TurnManager.player_turn_started` in `_ready()`). A generic mechanism (`scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema" — `"thrown_weapon"`/`"unarmed_fallback"` pool keys), used by both Goblin Minion's one-shot thrown Dagger and Orc Warrior's one-shot thrown Javelin: queues an entry in `Enemy.die()` when that enemy had a weapon lodged near a target; resolved on the player's very next turn — a per-enemy chance (`Rng.chance`, gameplay stream — both currently default to 50%) to drop a normal pickupable `Item` at the target's current tile, then the queue is cleared regardless of outcome (one-shot check, not a retry-every-turn poll).
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
`TileType.WATER` (=5) is fully rendered and implemented (atlas sample point in `_setup_tileset()`
was fixed from `(32,0)` — a brown dirt-blob edge pixel that was silently rendering as plain floor
— to `(64,16)`, a clean interior tile of the actual blue water blob in `water_rock_dirt.png`).
Stepping into water: costs 2 turns (difficult terrain, same as mud) AND extinguishes burning
(`burning_turns = 0`, logged in cyan). Both `player.gd _try_move()` and `_execute_queued_path()`
handle this for the player; `Enemy._move_step()` mirrors it for enemies (currently dead in
practice since nothing sets `Enemy.stats.burning_turns` yet — see `scripts/entities/CLAUDE.md`'s
"Status effects" — but wired so the interaction is correct the moment something does). **Nothing
flammable can ignite while standing on water**: `ignite_flammable(pos)` refuses outright (returns
`false`, no barrel/door catches fire) when `pos` is a WATER tile — purely defensive today since
barrels/doors never spawn on water anyway, but keeps the rule centralized at the one chokepoint
rather than relying on that spawn-placement accident. A thrown **lit** Torch landing on a WATER
tile (`PlayerThrowTool._throw_weapon()`'s no-enemy-target landing branch) is doused instead of
igniting anything — `torch_lit = false`, logged in cyan — rather than calling `ignite_flammable()`
at all.

## Empty bottle mechanic
Drinking any POTION adds an `Empty Bottle` (TOOL type, `sprites/items/materials/bottle/small.png`) to inventory via `potion_drunk` signal → `GameState.add_item()`. **Fill is manual**: use the bottle from quickbar/inventory (enters tool mode via `player_tool_primed`), then LMB or RMB on an adjacent WATER tile → `Bottle of Water` (TOOL, medium sprite); adjacent MUD → `Bottle of Mud` (TOOL, small sprite). Neither is FOOD-typed or contributes to long rest food value. Fill costs 1 turn. `PlayerThrowTool.try_fill_bottle(bottle, target)` (`scripts/entities/player_throw_tool.gd`) checks adjacency and tile type. **Nat-1 roll on fill**: rolling 1 on a d20 shatters the bottle (consumed, no fill). LMB tool routing checks item name before dispatching: "Empty Bottle" → `_throw_tool.try_fill_bottle()`; other tools → `_actions.interact_action()` (`scripts/entities/player_actions.gd`).

## Throw mechanic
Right-click food item in HUD quickbar → `GameState.player_throw_primed.emit(item)` → player enters throw mode. Left-click target tile → `_do_throw(pos)`. Rotten Meat + Fire Trap = Cooked Meat (see "Floor items" above). Throwing any other item onto a trap tile activates it instead of just dropping — see "Traps" above's `throw_item_onto_trap()`. Esc cancels.

## Boss floors
`DungeonData.boss_room: Rect2i` set on floors divisible by 5. `_spawn_boss()` spawns from `DungeonFloorData.BOSS_POOL`. Floor 5: Big Demon (hp=80). Floor 10: Necromancer (hp=120). Boss dies → `drop_boss_loot(pos)`. `enemy.is_boss: bool`. `ENEMY_POOL`/`BOSS_POOL` entries carry stable `"enemy_id"`/`"boss_id"` keys (see `scripts/entities/CLAUDE.md`'s "Enemy/boss pool ids") and may carry an `"attack_profile"` key for ranged enemies (see that file's "Attack profiles" section) — both are read generically by `Enemy`, no `dungeon_floor.gd` changes needed.
