# scripts/entities

Entity hierarchy, combat mechanics, D&D stats, status effects, enemy AI.

## Maintenance rule
When adding a new entity type, status effect, or changing combat rules, **immediately update this file and root `CLAUDE.md`** — without waiting to be asked.

---

## Entity hierarchy
```
Entity (CharacterBody2D)   grid_pos: Vector2i, move_to() 0.08 s tween, _tile_center(), is_friendly: bool
  ├── Player               input handling, quickbar, throw mode, blood trail (is_friendly = true)
  ├── Enemy                take_turn(), Behavior enum, hp bar, zzz label (is_friendly = false, default)
  └── Companion            Wild Heart ally — auto-attacks nearest enemy, shares enemy phase (is_friendly = true)
```
`Entity.is_friendly: bool` (default false) — true on `Player` and `Companion`. Originally added for the since-removed Zealous Presence talent's AOE targeting ("friendly entities in FOV"); now also used by Wild Heart's Enhanced Forms R3 (Wolf ADV at 1 enemy + 1 friendly) — reusable by any future ally-scoped system (e.g. Phase 2 multiplayer) without per-class type checks.

## Companion (`companion.gd`)
Extends Entity. Same configure-before-add_child pattern as Enemy (fields set in `configure()`, Stats created in `_ready()`). Key fields: `animal_name`, `armor_class`, `die_count`, `die_sides`. `DungeonFloor.spawn_companion(companion, pos)` sets `_dungeon_floor` and registers via TurnManager. Enemies ignore companions (MVP). On death: sets `GameState.player_companion = null`, unregisters, calls `queue_free()`. `heal_to_max()` called on rest via `GameState._on_short_rest_completed()` and `GameState.long_rest()`. Attack rolls: bare d20 (no proficiency bonus — animal instinct, not trained combat) vs `enemy.stats.armor_class`.
World pos = `grid_pos * TILE_SIZE + Vector2i(8, 8)`. `TILE_SIZE = 16`.
Z-index: enemies = 1, player = 3.

---

## Adding a new enemy
1. Extend `Entity`, implement `take_turn()` and `_setup_animations()`
2. `TurnManager.register_enemy(self)` in `_ready()` (not in `configure()`)
3. Add entry to `DungeonFloorData.ENEMY_POOL` (`scripts/world/dungeon_floor_data.gd`); add `idle_fmt`/`run_fmt` keys if sprite naming is non-standard
4. If boss: add to `DungeonFloorData.BOSS_POOL`, set `is_boss = true`

To author a full D&D-style monster instead of a plain melee grunt, add any of the optional pool
keys below to the `ENEMY_POOL`/`BOSS_POOL` dict entry — nothing else needs to change in code. See
"Enemy D&D stat-block schema" below for the full field table.

---

## Enemy D&D stat-block schema

Every field below is an **optional** `ENEMY_POOL`/`BOSS_POOL` pool key with a safe default equal
to the old plain-melee behavior — a new enemy is still just "add a dict entry"; these keys only
add fidelity when you write them. Read once in `Enemy._apply_stats()`/`configure()`, no typed
Resource class (same "data describes the knob, code dispatches the effect" philosophy as
items/talents). Full rationale/worked examples: `docs/architecture/enemy-stat-block-design.md`
(the schema doc this table implements) and `docs/architecture/ENEMY_SYSTEM_ARCHITECTURE.md` (the
behavior refactor — decide/execute split, `attack_profile`, targeting — this schema builds on;
**fully implemented**, not just specced).

| Key | Shape | Effect |
|---|---|---|
| `"cr"` | float | Challenge rating, pure data today (no CR-budgeted spawner yet — floor-linear scaling in `_apply_stats()` is unchanged and still the only difficulty knob). Default `0.25`. |
| `"creature_type"` | string | `"Undead"`/`"Fiend"`/`"Beast"`/... flavor tag, stored on `Enemy.creature_type`. No mechanical effect by itself (reserved for a future type-conditional damage rule or talent synergy). |
| `"mods"` | `{"str":0,"dex":0,"con":0,"int":0,"wis":0,"cha":0}` | Real ability-score modifiers. **Presence of this key switches the enemy's attack roll AND every `resist_check_detailed()` call to the mod+proficiency formula, replacing the legacy `floor_num/3` bonus — never both.** Absent = 100% unchanged legacy behavior (also true of the older `str_mod`/`con_mod`/`dex_mod`/`wis_mod`/`int_mod` single-stat keys, which still work as a fallback and do NOT trigger the mods formula). |
| `"prof_bonus"` | int | Only read when `"mods"` is present. Default derived from `cr`: `2 + max(0, ceil(cr)-1)/4`. |
| `"check_profs"` | `["str","con",...]` | Only read when `"mods"` is present — which of the 6 stats add `prof_bonus` to `resist_check_detailed()` (contested checks: Topple, Push, Grip of the Forest, SAVE cantrips/spells). |
| `"attack_prof"` | bool | Only read when `"mods"` is present. Whether `prof_bonus` applies to the attack roll too. Default `true`. |
| `"damage_resistances"` / `"damage_immunities"` / `"damage_vulnerabilities"` | `Array[String]` | ×0.5 / ×0 / ×2, priority immunity > vulnerability > resistance, applied in `Enemy.take_typed_damage()`. Legacy `"resist"`/`"vuln"` keys still work as a fallback for `damage_resistances`/`damage_vulnerabilities` (no immunity equivalent existed before). |
| `"condition_immunities"` | `Array[String]` | A **separate axis** from damage immunity — blocks the status COUNTER from ever being set. Vocabulary: `"slowed"`/`"rooted"`/`"prone"`/`"forced_move"` (real, wired — see `Enemy.apply_status()` and `DungeonFloor.force_move_entity()`/`resolve_push()`); `"poisoned"`/`"burning"`/`"bleeding"` (reserved — `apply_status()` sets the matching `Stats` counter but nothing ticks it for enemies yet, since no current effect poisons/burns/bleeds an enemy). |
| `"senses": {"sight_bonus": N}` | dict | Offset **relative to** `Enemy.FOV_RADIUS` (default 6), applied in `_sight_range()` — e.g. `+1` for darkvision (7 total), `+2` for superior darkvision, `-1` for weak sight. Absent = `0` (flat `FOV_RADIUS`). Deliberately relative, not absolute, so changing the base `FOV_RADIUS` later doesn't require re-touching every authored enemy. `darkvision`/`blindsight` sub-keys are reserved, not read. |
| `"speed"` | `{"moves": N, "per": M}` | Movement-speed scaling (see "Movement speed scaling" note below the table) — how many of every `per` real turns this enemy actually gets to move. Absent = `{"moves": 1, "per": 1}`, i.e. today's unconditional 1-move-every-turn, unchanged for every entry that doesn't author it. `Enemy._tick_speed_gate()` (called every real turn from `take_turn()`, a Bresenham-style integer accumulator, no floats) sets `_moves_this_turn`; `_decide_action()` treats `_moves_this_turn <= 0` exactly like `rooted_turns` (skip movement, still attack if already adjacent), and `_act_toward()` loops `maxi(1, _moves_this_turn)` steps for a `moves > per` (above-baseline speed) entry, re-checking attack range after every step. Reference: Zombie's 20 ft speed → `{"moves": 2, "per": 3}`. |
| `"multiattack"` | `[{"name","count","dmg_min","dmg_max","damage_type"}, ...]` | Each sub-attack resolves as its own independent roll/floater/log line via `_attack_player()`/`_attack_companion()`'s `sub` param — same one-log-line-per-swing convention as the player's Off-hand/Nick bonus attacks. Absent = today's single top-level-stats attack. |
| `"abilities"` | `[{"id","cooldown"\|"uses_max"\|"recharge","range","long_range","dmg_min","dmg_max","damage_type","status","turns"}, ...]` | Ranged damage(+optional status) ability, picked in `_decide_action()` over melee approach whenever ready, in range, LOS'd, AND the target isn't already melee-adjacent (snipe-then-melee, matching the Skeleton worked example in the design doc). Timer is exactly one of `cooldown` (flat turn counter), `uses_max` (per-life budget), or `recharge` (d6 roll ≥ N re-arms it, D&D "Recharge 5-6" style) — combining two on one ability is an authoring error. Optional `long_range` extends how far the ability can be picked from at all (`_pick_ready_ability()`'s reach check uses `long_range` if present, else falls back to `range`); a shot landing beyond `range` but within `long_range` rolls with Disadvantage (`Enemy._ability_is_long_shot()` → the `long_shot` param threaded through `_execute_ability()` → `_attack_player()`/`_attack_companion()` → `_resolve_attack_roll()`'s `extra_disadv`), the same weapon-style normal/long split as `PlayerRanged.ranged_shot_disadvantage()`. Absent `long_range` = flat cutoff at `range`, unchanged old behavior (e.g. Goblin Archer's plain `attack_profile`, not this key at all). Execution reuses `_attack_player()`/`_attack_companion()` wholesale (abilities and multiattack sub-attacks share the exact same damage shape) plus an optional `GameState.apply_player_status()` call if `"status"` is set. No per-ability custom code needed for this generic ranged-damage shape; a truly bespoke ability (summon, aura) still needs a `match ability_id:` special case added to `Enemy._execute_ability()`. Reference: Skeleton's Shortbow (`range: 8`, `long_range: 32`). |
| `"traits"` | `[{"id":"regeneration","amount":N,"shutoff_types":[...]}]` or `[{"id":"undead_fortitude","dc_base":N}]` | The two traits the design doc specs in full are implemented generically: **regeneration** heals `amount` HP at the top of a real turn unless a `shutoff_types` damage type hit last round (`Enemy._tick_regeneration()`, hooked from `take_turn()`); **undead_fortitude** intercepts a would-be-lethal hit with a CON check vs `dc_base + damage`, once per life, surviving at 1 HP (`Enemy.take_typed_damage()`'s death branch) — **except** when the killing blow's damage type is `"Radiant"` or it was a critical hit, matching the real D&D trait text exactly (`Enemy.take_typed_damage(amount, damage_type, is_crit: bool = false)`'s 3rd param, threaded through from every attack-roll call site that has a local `is_crit` — melee/cleave/off-hand/OA in `player.gd`, ranged in `player_ranged.gd`, the two ATTACK_ROLL cantrip/spell paths in `spell_effects.gd`; SAVE-resolution and auto-hit spells have no crit concept and pass the default `false`). A third `"id"`, **aggressive** (no payload — `Enemy._has_trait(id)` is a bare presence check, not a per-trait dispatch table entry), grants +1 movement step on any turn where the enemy can see its target: wired at `_execute_action()`'s `"act_toward"` case (`bonus_moves = 1 if (intent.can_see and _has_trait("aggressive")) else 0`, passed into `_act_toward(target, bonus_moves)`) rather than through `_tick_speed_gate()`/`"speed"`, since it's conditional on visibility, not a flat per-turn ratio — it stacks on top of whatever `"speed"` already grants. Never adds a second attack (D&D's own text only grants the movement, not another swing) — `_act_toward()` re-checks attack range after every step of a multi-step turn and attacks (and stops moving) the instant it's in range, so "move + attack" falls out for free, and "attack + move"/"just attack" (already adjacent at decision time) never call `_act_toward()` at all, going straight through the normal `_act_toward_or_ability()` → attack dispatch with no extra movement spent. A fourth `"id"`, **nimble_escape** (no payload), triggers off a landed MELEE hit rather than off a trait check: `Enemy.on_melee_hit(attacker)` (called only from the melee-only player attack sites — `_bump_attack()`/`_resolve_cleave_attack()`/`_resolve_offhand_attack()`/`resolve_opportunity_attack()` in `player.gd`, guarded on `actual > 0` — NOT ranged/thrown/spell hits) rolls `escape_turns = Rng.range_i(1, 5)` and stores `escape_from = attacker`. `_decide_action()` checks `escape_turns > 0` before every other behavior branch (including an adjacent target — a fleeing goblin doesn't stop to swing): decrements the counter and returns a `{"type": "flee", "target": escape_from}` intent, resolved by `_flee_from()` — a single greedy step directly away from the attacker (`_preferred_steps()` on the negated delta, no BFS fallback), returning whether it actually moved. If cornered (no walkable tile directly away — wall or blocked), `_execute_action()`'s `"flee"` case has it attack the fled-from entity instead of idling, but only if still in range (a trapped animal turning to fight rather than pathing the long way around). Its own `_move_step()` call passes `provokes_oa = false` (a new 3rd param, default `true` for every other caller) so fleeing never triggers the player's/companion's Opportunity Attack hook, matching the trait's own "doesn't provoke opportunity attacks" text. Any other `"id"` is inert (no dispatch exists yet — add one to `take_typed_damage()`/`_tick_regeneration()`/`_has_trait()`-style check/a new hook when a concrete monster needs it). References: `zombie`'s Undead Fortitude (`dc_base: 5`), `orc_warrior`'s Aggressive, `goblin_warrior`/`goblin_archer`'s Nimble Escape. |
| `"legendary_resistances"` | int (BOSS_POOL only) | Per-life counter (`Enemy.legendary_resistances_remaining`) consumed inside `resist_check_detailed()`: a roll that would fail is forced to pass instead, logged gray. `big_demon` ships with 3, per the design doc's target-boss recommendation. |
| `"passive_perception"` | int | **Implemented** — the Stealth-vs-Passive-Perception check's static DC (see "Stealth & Surprise Attacks" below). Authored value always wins; absent, `Enemy._apply_stats()` derives `10 + stats.wis_modifier()` from the now-resolved WIS score, so every enemy has a usable value even before the full bestiary is annotated. Currently authored on `goblin_minion`/`goblin_warrior`/`goblin_archer` (all 9, shared goblin-family WIS 8), `skeleton` (9, WIS 8), `zombie` (8, WIS 6), and `orc_warrior` (10, WIS 11); every other pool entry runs on the derived default (WIS 10 → PP 10) until annotated for flavor — safe/playable either way. |
| `"thrown_weapon"` / `"unarmed_fallback"` | `{"name","dmg_min","dmg_max","damage_type","range","icon","drop_die_min","drop_die_max","weapon_category","is_finesse","is_light","weapon_mastery","drop_uses_max","drop_chance","random_uses"}` / `{"name","dmg_min","dmg_max","damage_type"}`, optionally + `"attack_stat"` | A **generic, reusable pair** — originally authored for Goblin Minion's Dagger, now also used by Orc Warrior's Javelin (same underlying code, different pool values). `"thrown_weapon"`: once NOT escaping (see Nimble Escape below), the enemy is actively pursuing (`behavior in [CHASING, SEARCHING]` — an unaware SLEEPING/STATIONARY/ROAMING enemy never throws, it has to have noticed the target first), and the target is 2+ tiles away (not adjacent) and within `"range"` (default 4), `_decide_action()` returns a one-shot `"throw_weapon"` intent instead of the normal chase-then-melee dispatch — `Enemy._execute_thrown_weapon_attack()` resolves it via `_attack_player()`/`_attack_companion()` with `long_shot=true` forcing Disadvantage (reusing that param purely for its Disadvantage side effect, not its normal normal/long-range meaning), sets `Enemy._thrown_weapon_used = true` (a per-life one-shot flag), and — regardless of whether the throw actually landed, matching the original Goblin Minion behavior — registers the target with `DungeonFloor.queue_thrown_weapon_drop(target, item, chance)` for a per-entry `"drop_chance"` (default `0.5`). `"unarmed_fallback"`: once `_thrown_weapon_used` is true, `_attack_target()` dispatches every subsequent attack here instead of the pool's `"multiattack"` — the weapon is gone, thrown away (both Goblin Minion and Orc Warrior author this key, so both go bare-fisted afterward). Its optional `"attack_stat"` key (both enemies' Fists use `"str"` regardless of their own attack-stat default) is a per-sub-attack override read by `Enemy._attack_bonus_for(sub)`, which every `_attack_player()`/`_attack_companion()` call now threads into `_resolve_attack_roll()`'s `attack_bonus_override` instead of always passing `-9999`/falling back to the enemy-wide `attack_profile.attack_stat` default — falls back to the normal `_attack_bonus()` for every pre-existing multiattack/ability entry that doesn't set it. **The dropped `Item`** is built generically by `Enemy._build_thrown_weapon_item(wpn)` from the `"thrown_weapon"` dict's own fields (`"icon"`, `"drop_die_min"`/`"drop_die_max"` — the raw weapon's die, distinct from `dmg_min`/`dmg_max`, which are the enemy's already-ability-mod-inflated attack numbers — `"weapon_category"`, `"is_finesse"`, `"is_light"`, `"weapon_mastery"`, `"drop_uses_max"`), every field defaulting to whatever the original hardcoded Dagger builder used (so Goblin Minion's pool entry, which sets none of these, reproduces its exact original output) — a new consumer is expected to set them all explicitly. `"random_uses"` (default `false`) picks between an already-full drop (Goblin's Dagger) and a randomly-worn-down one (`Rng.range_i(1, drop_uses_max)` — Orc's Javelin, "already used"). **Recovering the thrown weapon**: `DungeonFloor._pending_thrown_weapon_drops`/`_resolve_pending_thrown_weapon_drops()` (`scripts/world/CLAUDE.md`) — checked once on the player's next real turn after the thrower dies (`Enemy.die()` queues it with its own `_thrown_weapon_lodged_chance`, `TurnManager.player_turn_started` resolves it), to drop a normal pickupable `Item` at wherever the throw's target currently stands. Unconditional on the throw actually having landed — `_attack_player()`/`_attack_companion()` don't return their hit result, so gating strictly on a hit would need a broader refactor; documented simplification, still true for both enemies using this mechanic today. |
| `"speed_ground"` / `"speed_flying"` | both `{"moves","per"}` | Imp-only pair: `_tick_speed_gate()` picks `"speed_flying"` while CHASING/SEARCHING (pursuing) and `"speed_ground"` otherwise, instead of a single flat `"speed"`. Requires BOTH keys to be present — an entry with only one, or neither, falls back to the legacy single `"speed"` key (or the `{1,1}` default) unaffected. |
| `"extra"` (nested inside a `"multiattack"` sub-entry) | `{"dmg_min","dmg_max","damage_type"}` | A second, independent typed damage instance dealt on the SAME hit as its parent sub-entry (one attack roll, two damage numbers/floaters/log segments) — Imp's Sting (1d6+3 Piercing weapon dmg + 2d6 Poison venom). Mirrors the player-side Judgement Day/Fireball-friendly-fire "one hit, multiple damage types" convention. `_attack_player()` gives it its own `edmg:` tooltip segment; `_attack_companion()` folds it into the one flat damage number instead (Companion has no per-type tooltip system at all, pre-existing simplification). |
| `"invisibility"` | `{"cooldown","duration"}` | Imp-only. While pursuing (CHASING/SEARCHING) and not yet adjacent, with the cooldown ready and not already invisible, `_decide_action()` returns a one-shot `"cast_invisibility"` intent (costs the turn) instead of closing distance. See "Invisibility" below — shared mechanism with the player-castable level-2 spell of the same name. |

**Traits `"magic_resistance"` / `"shape_shift"`** (both Imp-only today, presence-only like `"aggressive"`):
- **`magic_resistance`**: Advantage on saving throws against spells — `Enemy.resist_check_detailed()` gained a `magical: bool = false` param; when true AND this trait is present, the d20 is rolled with Advantage (max of two rolls). Threaded through every SAVE-resolution spell's enemy-facing call in `spell_effects.gd` (Ray of Frost, Toll the Dead, Mind Sliver's own save, Thunderclap, Fireball) — **not** weapon-mastery saves (Push/Topple/Grip of the Forest/Branching Strike), which aren't spells and never pass `magical=true`.
- **`shape_shift`**: while CHASING and unseen by the player THIS turn (out of FOV, or the enemy is Invisible — `_tick_shape_shift()`'s `unseen` check), 50% chance per eligible turn to secretly transform into a random small-critter form (`Enemy.SHAPE_SHIFT_FORMS = ["rat","raven","spider"]`, tracked in `_shifted_form`) — no turn cost, and a further 50% chance to already be shape-shifted at spawn (`_ready()`). Reverts to the true form instantly on taking any actual damage (`take_typed_damage()`'s revert check — an immune 0-damage hit does NOT revert it). **Mechanically wired, visually a no-op**: no `rat`/`raven`/`spider` sprites exist yet (checked `sprites/characters/`) — per direct owner decision this is asset debt, not a missing feature; swap in real sprites via `_setup_animations()`'s sprite-prefix lookup once art exists. The one real mechanical effect today: while shape-shifted, `_tick_speed_gate()` forces the shared mundane `{"moves":2,"per":3}` ground speed regardless of the true form's own `"speed_ground"`/`"speed_flying"` pair (none of the three animals can fly).

## Invisibility

Implemented both as an enemy-side ability (Imp, pool key `"invisibility"` above) and the real
player-castable level-2 Illusion spell of the same name (`SpellDb._invisibility()`,
`spell_effects.gd`'s `cast_leveled_self()` `"invisibility"` branch) — both share the exact same
underlying mechanism, described once here.

- **Duration field**: `Stats.invisibility_turns` (player) / `Enemy._invis_turns` (enemy) — up to
  100 turns, NOT a Concentration effect (5e RAW: Invisibility ends on attacking or casting a
  spell, not on taking damage, so it deliberately doesn't touch `concentration_spell_id`).
- **Ending early on attack/cast**: the player's own end-check reuses the Stealth system's existing
  `GameState.stealth_check_skip` flag (already set `true` by every attack/spell-cast call site
  right before its own `begin_player_action()`) — `Player._resolve_stealth_check()` checks it
  first, before the flag is used for its own stealth purpose, and zeroes `invisibility_turns` if
  set. `Stats.invisibility_just_cast` (set by the cast itself) skips this check exactly once so
  casting Invisibility doesn't immediately end itself on its own casting turn — same "just_cast"
  pattern as `witch_bolt_just_cast`. The enemy side's equivalent is simpler: `Enemy._attack_target()`
  checks `_invis_turns > 0` and calls `_end_invisibility()` before dispatching the attack.
- **Not invincible, just unseen**: an invisible creature can still be hit by AoE spells
  (Fireball/Thunderclap — these never target by click, so they're unaffected either way) or by
  bumping into it (walking into its tile — `_try_move()`'s WASD bump-attack path deliberately keeps
  calling `DungeonFloor.get_enemy_at()` directly, unfiltered). What it blocks is every DIRECT
  click-based target resolution — `DungeonFloor.get_targetable_enemy_at()` (returns `null` for an
  Invisible enemy) is the chokepoint every click-to-chase, Frenzy/Limit Break click, Grip of the
  Forest hook click, spell Ctrl/LMB click, and thrown-weapon click now goes through instead of the
  raw `get_enemy_at()`.
- **Enemies losing track of an invisible player**: `Enemy._can_see_entity()` returns `false`
  outright for a target with `GameState.player_stats.invisibility_turns > 0`, regardless of
  distance/LOS — per direct owner design, an unaware pursuer doesn't "try" to track it, it's simply
  gone. This reuses the EXISTING CHASING → reaches `last_known_target_pos` (last spot it was seen)
  → SEARCHING → (gives up after 7 turns) → ROAMING flow with zero new state — the "goes to where it
  vanished, searches briefly, then leaves" behavior the owner asked for falls out for free.
  **Opportunity Attacks and invisibility**: an unseen mover can't provoke a reactive attack from
  someone who has no idea where it is — `Enemy._check_opportunity_attacks_on_move()` (enemy moves)
  returns immediately if `_invis_turns > 0`, and `Player._resolve_enemy_opportunity_attacks()`
  (player moves) skips the actual attack for every enemy whenever
  `GameState.player_stats.invisibility_turns > 0` (Battlefield Expert's Side Step *detection* still
  runs even while invisible — that's the player's own movement-pattern trigger, not an enemy
  reaction, so it's unaffected).
  **Known gap**: a few OTHER adjacency-based checks still don't go through `_can_see_entity()`
  (`_select_target()`'s "already-adjacent wins outright" and SLEEPING's true-adjacency free-wake in
  `_decide_action()`) — an invisible player standing directly adjacent to an enemy may still
  trigger these, a documented simplification rather than an oversight, since covering it would mean
  threading an invisibility check through more unrelated call sites for a corner case (standing
  right next to a hostile enemy while invisible) that's easy for the player to just avoid.
- **Visuals**: an invisible enemy's sprite (and HP bar/zzz label, hidden along with the parent
  node) goes to `visible = false` immediately on casting and is also re-derived generically every
  `DungeonFloor.update_fog()` via `_update_enemy_visibility()`'s `and not enemy.is_hidden_from_player()`
  clause, so it composes correctly with the normal FOV-based hide/show. The invisible PLAYER gets a
  purely cosmetic translucent tint (`Player._update_invisibility_visual()`, `modulate.a = 0.4`) —
  the actual "can't be seen" mechanic is `_can_see_entity()`'s check above, not this.
- **Touch-self-only, not true ally targeting**: `Spell.target_kind = SELF`, `range_tiles = 1`
  (touch) — same "arm targeting, ANY click confirms a self-cast" pattern as Mage Armor. Genuine
  touch-any-creature targeting doesn't exist in this engine (see Mage Armor's own "No ally-buff
  targeting exists" note in "Wizard leveled spells" below) and wasn't built for this pass either —
  both the Imp's own use and the player's are self-only in practice, matching how the feature was
  actually requested ("mostly will use it on themselves anyway").
- **Scroll of Invisibility** exists per the usual one-scroll-per-spell convention
  (`scripts/items/CLAUDE.md`).

**Deliberately not implemented** (see the design doc's own "explicitly out of scope"/"future design
doc" calls): multi-tile Large/Huge occupancy (size above Medium still just renders a bigger sprite
on one tile), reactions beyond Opportunity Attacks (`"reactions"` key is unread), conditional
triggers (`"triggers"` key is unread — no flee/enrage-on-ally-death behavior), Legendary Actions
(shared action-point pool spent between other combatants' turns — a genuine turn-economy change,
its own future design doc), and CR-budgeted floor spawning (population is still pure
`floor_min`/`floor_max` band + count, `cr` is authored but unread by the spawner).

**Ranged distance scaling convention (still settling)**: converting a D&D 2024 distance (feet,
5 ft/square) into tiles is not necessarily one universal divisor. What's decided so far: shooting
ranges (ranged weapons' `Item.range`, and an `"abilities"` pool entry's `range`/`long_range` — see
the table above) divide by **20** (Shortbow's 80/320 ft → 4/16 tiles, not 8/32) — steeper than a
straight D&D-ratio conversion because our grid only grants **1 tile of movement per turn** (no
D&D-style 30 ft move-per-round budget), so anything looser would dwarf how far a target can
actually close distance in a reasonable number of turns and make ranged combat trivially safe.
Spell `range_tiles` (`scripts/items/CLAUDE.md`'s spellcasting-data section, currently dividing by
10 — e.g. Fire Bolt's 120 ft → 12 tiles) is **not locked in** — the same 1-tile-per-turn argument
may end up pulling spell ranges down to /20 too; re-check with the user before assuming /10 is
final when authoring a new spell's range.

**Movement speed scaling**: D&D 2024's default creature speed is 30 ft — our engine's baseline of
exactly 1 tile of movement per turn. A pool `"speed": {"moves": N, "per": M}` entry (see the
schema table above) reproduces anything off that baseline as a duty cycle rather than a distance:
a speed below 30 ft (e.g. Zombie's 20 ft) moves on only `moves` out of every `per` turns — 20 ft →
`{"moves": 2, "per": 3}`, skipping movement roughly 1 turn in 3 (still attacks if already
adjacent, exactly like being `rooted_turns`-locked for that one turn); a speed above 30 ft would
use `moves > per` (e.g. 40 ft → `{"moves": 4, "per": 3}`) and get an extra movement step on
roughly 1 turn in 3 instead. No monster has needed the above-baseline case yet, but
`Enemy._tick_speed_gate()`/`_act_toward()` already handle it generically. This is a distinct axis
from Orc Warrior's Aggressive trait (a flat +1-step bonus gated on target visibility, not a duty
cycle) — the two stack rather than reusing one mechanism, since Aggressive is conditional and
`"speed"` isn't.

---

## Stats (`stats.gd`)
`modifier(score) -> int` = `floor((score - 10) / 2)`.
`apply_class_defaults()` sets all six ability scores and derives `max_hp` and `armor_class`.
**Point buy** (Custom character-creation path, `scripts/ui/point_buy_select.gd`): `apply_point_buy_scores(scores: Dictionary)` overrides the six scores set by `apply_class_defaults()` and re-derives `max_hp`/`current_hp`/`armor_class` the same way — called strictly after `apply_class_defaults()`, before `apply_race_defaults()` (race never touches base scores, so ordering vs. race is safe either way). Cost table `POINT_BUY_COST`, budget `POINT_BUY_BUDGET` (27), range `POINT_BUY_MIN`/`POINT_BUY_MAX` (8/15) — standard 5e point-buy costs (14/15 cost 2 points/step, others 1). See root `CLAUDE.md`'s "Point buy" section.
`hit_die_sides() -> int`: Barbarian 12, Ranger 10, Monk 8, Wizard 6.
`_hp_per_level()`: class HP gain per level-up.
`to_dict()`/`from_dict(d)` (Save/Load Phase A): hand-written serialization of every mutable field (scores, class, level/XP, HP, base damage, rage uses, temp HP, status turns, `known_weapon_masteries`). Computed properties and class-set flags are never saved — `from_dict()` calls `apply_class_defaults()` first, then overwrites with saved values; `armor_class`/`min/max_damage` are re-derived by `GameState.recalculate_stats()` after load. **Any new mutable Stats field must be added to both functions** — see `scripts/autoloads/CLAUDE.md`'s SaveManager section.

**Check proficiency flags** (formerly "save_prof"): `check_prof_str/con/dex/int/wis/cha`. Used for traps, lockpick, disarm. No separate saving throw system — all defensive rolls are "checks". Barbarian: STR+CON. Ranger/Monk: STR+DEX. Wizard: INT+WIS.

**Weapon mastery ownership**: `Stats.known_weapon_masteries: Array[String]` (default empty) + `Stats.knows_mastery(name) -> bool`. A weapon's `Item.weapon_mastery` only triggers its effect if the wielder knows that mastery. `Stats.ALL_WEAPON_MASTERIES` (const, alphabetical, all 8) and `Stats.mastery_cap() -> int` (computed live from `character_class` + `character_level`, never cached) back the Mastery Picker (`scripts/ui/mastery_picker.gd`) — see `scripts/ui/CLAUDE.md`'s "Mastery picker" section. The picker fires once right after class selection, and again after any completed long rest if the player opts in via `mastery_reselect_prompt.gd` (see `scripts/ui/CLAUDE.md`'s "Mastery reselect prompt" section). See `scripts/items/CLAUDE.md`'s "Weapon masteries" section for gating call sites.

**Shield proficiency flag**: `Stats.proficient_shields: bool` (default `false`, set per-class in `apply_class_defaults()` — Barbarian and Ranger only). Gates `GameState.can_equip_shield()`: lacking it blocks equipping a Shield outright (unlike weapon proficiency below, which just drops a bonus) — see `scripts/items/CLAUDE.md`'s "Shields".

**Weapon proficiency flags**: `Stats.proficient_simple_weapons: bool`, `Stats.proficient_martial_weapons: bool` (both default `false`, set per-class in `apply_class_defaults()`). Only Barbarian currently has both `true`. `Item.weapon_category` ("Simple"/"Martial"/`""`) determines which flag gates a given weapon. `CombatMath.weapon_prof_bonus(weapon, proficiency_bonus, proficient_simple, proficient_martial) -> int` (`scripts/entities/combat_math.gd`, moved from the old `player.gd._weapon_prof_bonus()` — see "Split-out modules" below) is the single chokepoint: unarmed (`weapon == null`) is always proficient; otherwise returns the proficiency bonus if the matching flag is set, else `0`. Used for `prof` in `player.gd._bump_attack()`/`_resolve_cleave_attack()` and `PlayerRanged.ranged_attack()` — lacking proficiency does not block using the weapon, it only drops the proficiency bonus from the attack roll (damage is unaffected). Weapon tooltips (`hud.gd`, `inventory_overlay.gd`) show the category right under the damage line, colored red when the equipped class lacks that proficiency (`_is_weapon_category_proficient()` in each file).

### Enemy stat scaling (in `_apply_stats()`)
```gdscript
max_hp      = type["hp"]      + (floor_num - 1) * type["hp_per_floor"]
armor_class = type["ac"]      + floor_num / 5
min_damage  = type["dmg_min"] + (floor_num - 1) / 3
max_damage  = type["dmg_max"] + (floor_num - 1) / 2
```

---

## Combat rolls
| Roll | Formula |
|---|---|
| Player attack | d20 + STR mod + `weapon.bonus_damage` vs enemy `armor_class` |
| Enemy attack | d20 + `floor_num / 3` vs player `armor_class` |
| Player AC | 10 + DEX mod + equipped armor `bonus_ac` (recalc via `GameState.recalculate_stats()`) |
| Enemy AC | type `"ac"` + type `"armor"` + `floor_num / 5` (pool `"armor"` folded into AC, not DR) |
| Critical hit | Natural 20 → auto-hit + 2× damage (both sides) |
| Fumble | Natural 1 → always misses |
| Ranged (DEX) | Same formula but uses DEX mod instead of STR |
| Finesse (e.g. Rapier) | Same formula but uses `max(STR mod, DEX mod)` — `CombatMath.finesse_modifier()`, gated on `Item.is_finesse` |

`Stats.take_damage(dmg) = maxi(1, dmg)` — no damage reduction. `stats.armor` is always 0.

**RNG source rule**: every roll in this table — and every other gameplay-affecting random draw in entity code (damage dice, resist checks, talent proc chances, enemy roam/wander shuffles, loot rolled at kill time) — goes through the **`Rng` autoload** (`Rng.roll(20)`, `Rng.range_i(min,max)`, `Rng.chance(p)`, `Rng.shuffle(arr)`), never global `randi_range`/`randf`/`Array.shuffle()`. Seeded from `run_seed` for reproducible runs; see `scripts/autoloads/CLAUDE.md`. Cosmetic jitter (camera shake in `player_vfx.gd`) deliberately stays on the global RNG.

### Advantage / Disadvantage
- **ADV**: attacking a SLEEPING/STATIONARY/ROAMING enemy (unaware defender — see "Stealth & Surprise Attacks" below); attacking an enemy whose `door_ambush == true` (consumed one-shot after check)
- **DISADV**: ranged attack at Chebyshev distance 1 (melee range); melee with a `is_heavy` weapon when STR < 13; ranged with a `is_heavy` weapon when DEX < 13; ranged shot beyond the weapon's normal range but within FOV (`player.gd._ranged_shot_disadvantage()` — every ranged weapon's "long range" is the player's live FOV, not a per-weapon field, see `scripts/items/CLAUDE.md`); a Thrown weapon (Spear/Handaxe/Dagger) thrown at Chebyshev distance 1, and a thrown weapon's own long-throw equivalent, both applied in `PlayerThrowTool._throw_weapon()` (`scripts/entities/player_throw_tool.gd`)
- ADV + DISADV cancel → 1d20
- Yellow "!" floats above enemy on ADV surprise attacks
- Enemy attack log lines (`enemy.gd._attack_player()`) never name the specific talent/ability that granted ADV/DISADV — that context lives only in the `ehit` tooltip roll breakdown, not the log line.
- **Halfling Lucky**: `CombatMath.roll_with_adv_disadv()` runs every individually-rolled d20 through `CombatMath.halfling_reroll(die)` — a natural 1 (Halfling only) is automatically rerolled and the new value MUST be used (single reroll, even if the reroll is also a 1). Baked into the one shared roll function, so it covers all 6 player attack-roll sites (melee/cleave/off-hand/OA/ranged/thrown) for free; `player_thief_tools.gd`'s `attempt_disarm()` calls `halfling_reroll()` directly for the trap-disarm check. `CombatMath.wrap_halfling_luck(text, lucky)` wraps the finished chat-log line in dark green + a ☘ marker; the `lucky1`/`lucky2` fields on `hit_meta`/`check_meta` drive a struck-through "☘ Halfling Luck: ~~1~~ → N" tooltip line in `fmt_hit_tooltip()`/`fmt_save_tooltip()` (`scripts/ui/tooltip_formatters.gd`). Never applies to enemy rolls.

### Damage types / resistances / per-die breakdown (typed damage instances)
Every main attack path (`player.gd._bump_attack()`/`_resolve_cleave_attack()`/`_resolve_offhand_attack()`/`resolve_opportunity_attack()`, `PlayerRanged.ranged_attack()`, cantrips/Fireball/Magic Missile in `spell_effects.gd`) builds a **typed damage instance** via `CombatMath.build_damage_instance(rolls: Array[int], sides: int, flat_mods: Array, crit: bool, damage_type: String) -> Dictionary` instead of a bare int. `rolls` is every individual die result (from `Rng.roll_dice(count, sides)` — weapon dice are stored as a flat range on `Item`, `CombatMath.dice_notation(dmin, dmax) -> Vector2i` recovers `(count, sides)` since every weapon pool entry constructs that range as an exact `NdM`), `flat_mods` is the same `{name, amount, color}` shape `encode_bonus_sources()` always took (weapon enhancement, ability mod, Rage bonus, Frenzy, Ironwood Bark — same-type sources that fold into ONE instance). The instance sums dice + flat mods, then doubles on crit (**multiplication always happens last** — never double a partial subtotal and tack bonuses on after).

**One instance per damage type, not one instance per attack**: a bonus source with its OWN distinct damage type (Zealot's Judgement Day — Radiant, on top of the weapon's own type) becomes a SECOND, independent `build_damage_instance()` call rather than folding into the first. Each instance is applied via `Enemy.take_typed_damage(amount, damage_type) -> Dictionary` (below) and gets its own `DungeonFloor.show_damage()` floater (`stack_index` param offsets the second floater's spawn x so they don't overlap) and its own `[url=dmg:...]` segment in the SAME chat-log line/`game_log()` call (`"... for [url=]N[/url] Slashing and [url=]M[/url] Radiant dmg."` — never a second `game_log()` call). The original damage-stacking rule still holds **per instance**: never call `take_typed_damage()`/`show_damage()` twice for what should be one instance, and always resolve every bonus-trigger flag (Judgement Day pending, etc.) to a plain number BEFORE either instance's `take_typed_damage()` call, so a source gated on `not enemy.stats.is_dead()` can't silently skip because an earlier instance already killed the enemy.

**Enemy resist/immune/vuln**: `Enemy.damage_resistances`/`damage_immunities`/`damage_vulnerabilities: Array[String]` (populated from `"damage_resistances"`/`"damage_immunities"`/`"damage_vulnerabilities"` pool keys — `"resist"`/`"vuln"` still work as a fallback for the first/third, e.g. Skeleton resists Piercing/is vulnerable to Bludgeoning, Imp/Chort resist Fire). `Enemy.take_typed_damage(amount, damage_type) -> {actual, mul}` applies ×0 (immune) / ×2.0 (vuln) / ×0.5 (resist), **priority in that order, no stacking** (a type in two lists is an authoring error) — BEFORE `Stats.take_damage()`'s flat floor-at-1 clamp. Single chokepoint every attack site calls instead of `enemy.stats.take_damage()` directly. Also hooks the `"regeneration"`/`"undead_fortitude"` traits (see `scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema"). Separate from the player's own per-type DR in `GameState.take_damage_raw()` (Rage/Bear-form) — that system is unchanged.

**Per-die tooltip breakdown**: `CombatMath.encode_damage_instance(inst)` packs the instance into a `dmg:` meta string with a `rolls=` field (pipe-joined individual die results) and `sides=`/`dtype=`/`rmul=` (the resist/vuln multiplier actually applied) alongside the existing `bonus=`/`crit=`/`final=` fields. `TooltipFormatters.fmt_dmg_tooltip()` renders a `"NdS: r1 + r2 + ... = total"` line when `rolls=` is present (falls back to the old single `"1d%d"` line for the handful of call sites not migrated — Frenzy, thrown weapons, enemy-attacks-player — so nothing broke), a `"÷ 2 (Resistance)"`/`"× 2 (Vulnerability)"` line when `rmul != 1.0`, and appends the damage type to the final line.

**Multiplication always happens last**: a critical hit doubles the FULL summed total (dice + flat mods) of EACH instance independently, never a partial subtotal computed before some sources are added in.

**Lethal-hit log lines fold the kill in**: `Player._finish_kill(enemy)` no longer logs its own "X dies." message — every player attack call site (all 6 attack-roll sites plus Frenzy/Limit Break/thrown/ranged) captures `is_dead()`/`is_lethal` right after damage is applied (after BOTH instances if there are two), appends `CombatMath.death_suffix(is_lethal)` (`scripts/entities/combat_math.gd`, renders `" and died."`) to its own hit/damage log string, and only then checks that same lethality bool before calling `_finish_kill()`. Adding a new attack path that can kill an enemy must follow this pattern — never log a bare "dies" line from inside a kill-handling function.

**Rage's damage tooltip tag**: `enemy.gd._attack_player()`'s `edmg:` meta carries a `rage=%d` field (set whenever `GameState.is_raging` was true for that hit — enemies always deal `"Bludgeoning"`, which is physical, so Rage's 50% DR in `take_damage_raw()` was live). `TooltipFormatters.fmt_edmg_tooltip()` renders a `"÷ 2  (Rage)"` line (alongside the existing crit `"× 2"` line) whenever that flag is set, so the player can see Rage's DR reflected in the hover breakdown, not just as a smaller final number.

**Generic bonus-source tooltip encoding**: `CombatMath.encode_bonus_sources(sources: Array)` (`scripts/entities/combat_math.gd`) takes an `Array[Dictionary]` of `{name, amount, color}` (zero-`amount` entries are dropped automatically) and packs it into one `bonus=` field (`"|"`-joined within an entry, `";"`-joined between entries — `dmg_meta` itself splits on `,`/`=`, so neither character can appear in a name); this is exactly the `flat_mods` array passed into `build_damage_instance()`. `TooltipFormatters.fmt_dmg_tooltip()` calls `CombatMath.decode_bonus_sources()` and renders one tooltip line per entry generically. **Adding a new same-type bonus damage source never requires touching `tooltip_formatters.gd`** — just append `{"name": ..., "amount": ..., "color": ...}` to the `flat_mods` array at the call site. The visible chat log line itself still carries no per-source text or amounts (no `(+N Frenzy)`, no God-Mode `[HP/HP]` suffix) — only the combined number(s) + damage type(s). **Berserker's Frenzy and Scarred Warrior's Limit Break are their own standalone actions** (`player_berserker.gd`/`player_scarred_warrior.gd`, still on the legacy single-total `dmg:` format) rather than per-attack bonuses, so they don't participate in this stack — same for thrown weapons and enemy-attacks-player, all documented follow-ups for a future pass.

---

## Temp HP
`Stats.temp_hp: int = 0`. Set by Natural Sleeper R2 (2d6 THP per round while starting a turn on the active form's terrain — replaces existing THP, doesn't stack) and by World Tree's Ironwood Bark (`1d6 × rage_bonus_damage` on Rage activation, and again at turn start while Raging if temp HP is 0 — see `player.gd._on_turn_started()`). `take_damage()` absorbs temp HP before regular HP — if fully absorbed, returns 0. Displayed in HUD as a light-blue strip above the HP bar (`_temp_hp_fill` in hud.gd), proportional to `temp_hp / max_hp`.

## Zealous Presence buff (legacy field, no longer set)
`Stats.zealous_presence_turns: int = 0` — was Zealot's Zealous Presence talent buff (removed in the Zealot rework, see "Zealot Tier 2 talents" below). The field, its read sites (`_bump_attack()`, `_ranged_attack()`, `Companion._attack_enemy()`, trap-check ADV), and its `_on_turn_started()`/`Companion.take_turn()` decrement are all still present but permanently inert (nothing writes a nonzero value anymore) — left in place rather than ripped out across every read site for a dead value that's always 0.

## Status effects
Fields on `Stats`: `poison_turns`, `burning_turns`, `bleeding_turns`, `slowed_turns`.
`tick_status() -> int` decrements all counters and returns total damage dealt (slowed = 0 damage, only movement penalty).

Apply a status:
```gdscript
GameState.player_stats.bleeding_turns = 5
GameState.player_status_changed.emit()
```

| Status | HUD dot | Source | Effect |
|---|---|---|---|
| Poison | green | potions, enemies | damage/turn |
| Burning | orange | Fire Trap | damage/turn |
| Bleeding | red | Spike Trap (5t) | damage/turn |
| Slowed | brown | Bear Trap (20t), mud, water | movement costs 2 turns |

---

## Enemy resist checks (World Tree)
`Enemy.resist_check(dc: int, use_con: bool = false) -> bool` — rolls `d20 + bonus + (con_modifier or str_modifier)` vs `dc`; true = enemy resists. **`bonus` is `floor/3` for a legacy entry, or `prof_bonus` (if that stat is in `"check_profs"`) for an entry with a `"mods"` stat block — see "Enemy D&D stat-block schema" above** — gated purely on whether the pool entry supplies `"mods"`, never both formulas at once. Legacy backing stats: `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL` entries may set optional `"str_mod"`/`"con_mod"` int keys (default 0); `_apply_stats()` converts them to `Stats.strength/constitution` (`10 + mod * 2`) when `"mods"` is absent. Used by Grip of the Forest's pull (STR) and Branching Strike R3's push (CON), both vs DC `8 + player STR mod + proficiency`; by the Heavy Crossbow's **Push** weapon mastery (CON) vs DC `8 + player DEX mod + proficiency`, resolved via `DungeonFloor.resolve_push()`; and by the Maul's **Topple** weapon mastery (CON) vs DC `8 + player STR mod + proficiency`, resolved via `Enemy.apply_status("prone", 1)` — see `scripts/world/CLAUDE.md`'s "Forced movement" section and `scripts/items/CLAUDE.md`'s "Weapon masteries". A boss with `"legendary_resistances"` set may force a failing roll to pass instead (§15 of the schema doc), consuming a per-life charge.
`Enemy.resist_check_detailed(dc, use_con = false, use_dex = false, use_wis = false, use_int = false) -> Dictionary` — same roll as `resist_check()`, but returns `{die, mod, floor_bonus, prof_label, dc, total, pass, stat, sliver_penalty, legendary_used}` so a caller can log a hover-tooltip roll breakdown instead of just the bool (`floor_bonus` is the numeric bonus actually applied — floor-scaling OR proficiency, whichever formula the entry uses; `prof_label` is `"Floor"` or `"Proficiency"` to match). `resist_check()` is now a one-line wrapper (`return resist_check_detailed(dc, use_con)["pass"]`). Consumed by Topple's `player.gd._try_topple()` (below) and by every enemy-side SAVE cantrip in `spell_effects.gd` (Ray of Frost, Toll the Dead, Mind Sliver, Thunderclap, Fireball) — Grip of the Forest / Branching Strike R3 / Heavy Crossbow Push still call the plain bool form since their logs don't show a roll breakdown. Priority when multiple `use_*` are somehow true: DEX > WIS > INT > CON > STR (every real call site only sets one). `wis_mod`/`int_mod` optional pool keys (default 0) mirror `str_mod`/`con_mod`/`dex_mod` — see "Enemy stat scaling" above (all five are the fallback path when `"mods"` isn't supplied). **Mind Sliver's penalty**: `Enemy.mind_sliver_penalty_die: bool` — if set, the very next `resist_check_detailed()` call (any stat, on any of the sites above) rolls `-1d4` (consumed regardless of which stat that particular check happens to use) and reports it via the `sliver_penalty` key — every one of those sites folds it into its `save:` meta's `sliver=%d` field, so the hover tooltip shows it as its own `"-N (Mind Sliver)"` line rather than silently vanishing into the total.
**Topple's contest-roll tooltip**: `_try_topple()` builds a `"save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d"` meta (reusing the existing `TooltipFormatters.fmt_save_tooltip()`/`hud.gd`'s `"save"`/`"check"` dispatch, `prof_label` read live off `save["prof_label"]`) and wraps "is knocked"/"resists" in `[url=%s]` so hovering the Topple log line shows the enemy's CON-save roll, same as hovering a player attack shows the hit roll. `fmt_save_tooltip()` reads the `prof_label` meta field (defaults to `"Proficiency"` if absent) to relabel the tooltip's second modifier line — `"Floor"` for a legacy floor-scaling enemy, `"Proficiency"` for a `"mods"`-based one.
`Enemy.rooted_turns: int` — Grip of the Forest R2. Checked at the top of `take_turn()`: decrements, skips movement, still attacks if already adjacent.
`Enemy.disadv_next_attack: bool` — Grip of the Forest R3. Consumed in `_attack_player()`'s roll (adds a Disadvantage source, resolved via the same net-ADV/DISADV house rule as the player's own attacks).
`Enemy.prone_turns: int` — Maul's **Topple** weapon mastery. Checked at the very top of `take_turn()` (before `slowed_turns`): decrements and returns immediately, skipping the enemy's entire turn (no movement, no attack) — unlike `rooted_turns`, which still allows an attack if already adjacent.

`Enemy.embedded_items: Array[Item]` + `Enemy.die()` override — thrown weapons (Spear) embedded by a non-lethal hit (`PlayerThrowTool._throw_weapon()`, `scripts/items/CLAUDE.md`'s "Thrown weapons") sit here until the enemy dies. `die()` overrides `Entity.die()`: drops every embedded item at `grid_pos` (100% chance each) via `DungeonFloor.place_item_on_floor()`, then calls `super.die()`. Every death call site already ends with `enemy.die()` (`player.gd._finish_kill()`, `companion.gd`, the trap/chasm death sites in `dungeon_floor.gd`), so this one override recovers an embedded Spear regardless of which of those actually killed the enemy or how many turns later.

## Opportunity Attacks

Full design doc: `docs/architecture/opportunity-attacks-design.md`. Core rule (5e-style): when an entity's single grid-movement step takes it from a tile **inside** an attacker's threat range to a tile **outside** it (Chebyshev), the threatened entity gets one free, turn-free reactive melee attack — at most once per round per attacker. Moving within reach, or approaching, never provokes. **Forced movement never provokes** — `DungeonFloor.force_move_entity()` and `resolve_push()` intentionally do not call either hook (see the comment at each function).

**Resolution model** — same precedent as Retaliation (`player.gd.try_retaliation()`): OA resolves *inline, synchronously*, with no phase change, no `begin_player_action()`/`revert_to_waiting()`, no turn cost. `TurnManager` has zero OA-related changes.

**Threat range**: player = `CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike"))` (same formula the chase-to-attack and Cleave range checks use — a Glaive Barbarian with Branching Strike R2 threatens 4 tiles). Enemy = `Enemy.melee_reach() -> int` (pool key `"reach"`, default 1 — flat for all current enemies, one-line pool entry for a future reach enemy). Companion = flat 1.

**Two hooks, one per moving side**:
- **Enemy moves → player/companion may OA**: `enemy.gd._check_opportunity_attacks_on_move(prev_pos, next_pos)`, called at the top of `_move_step()` (the single chokepoint for ALL enemy voluntary movement — chase/roam/random-step/search). Gates on `_dungeon_floor.is_tile_visible(prev_pos)`, the attacker's per-round flag, and (for the player) `not player.stats.is_dead()`. If it provokes, resolves the attack (`player.resolve_opportunity_attack(enemy)` or `Companion._attack_enemy(enemy)`), then aborts the move (`if not is_instance_valid(self) or stats.is_dead(): return`) if the OA killed the mover.
- **Player moves → each threatening enemy may OA**: `player.gd._resolve_enemy_opportunity_attacks(prev, next)`, called from `_try_move()` and both `_execute_queued_path()` move bodies (chase-step and regular queued-path step) right before `TurnManager.begin_player_action()`/the tween. Skips entirely on `GameState.noclip`. Skips a given enemy if `SLEEPING`, already used its reaction this round, or lacks LOS to `prev`. Calls `enemy._attack_player(self)` directly (already turn-free, routes through `take_damage_raw` so Rage DR/Reckless/Orc-Shaman-poison/Retaliation all apply exactly as a normal enemy attack would). Checks `GameState.is_game_over` after each swing and bails the move if the player died.

**Once-per-round reaction flags** (never on `GameState` — per-entity combat state, same tier as `just_crossed_door`/`rooted_turns`):
| Attacker | Field | Reset point |
|---|---|---|
| Player | `_oa_used_this_round` | `_on_turn_started()`'s `if not came_from_revert:` block — survives `revert_to_waiting()` chains, only clears after enemies actually take a round |
| Enemy | `oa_used_this_round` | Top of `take_turn()`, unconditionally (before the prone/slowed/rooted early-returns — a slowed enemy still refreshes its reaction) |
| Companion | `oa_used_this_round` | Top of `take_turn()` |

**Eagle R3 flag** (`GameState.player_evades_opportunity_attacks`, on `GameState`, not per-entity — it's a player-only debuff-immunity toggle, not reaction state): while true, `_resolve_enemy_opportunity_attacks()` never lets an enemy actually swing (auto-evade, not "OA with disadvantage") but still logs a single gray flavor line if it prevented at least one attacker's OA that move ("Eagle Form: you slip past their reach."). It has **no effect on the player's own OAs against enemies**. Set in `_activate_rage()` (`get_talent_rank("natural_rager") >= 3 and natural_rager_form == "Eagle"`) and cleared in `_end_rage()`; form can't be switched mid-Rage so no other write site is needed.

`resolve_opportunity_attack(enemy: Enemy)` on `player.gd` is modeled on `_resolve_cleave_attack()` — self-contained roll+damage+log, no per-turn talent effects wired in (Vex/Frenzy/Divine-Fury/Ironwood-Bark deliberately excluded, since those are per-turn action effects and OA fires on someone else's turn). Reuses the existing `hit:`/`dmg:` tooltip metas (no new formatter needed) with an "Opportunity attack:" log prefix.

## Stealth & Surprise Attacks

Implemented; design doc shipped and was deleted — this section is now the authoritative
reference (was `docs/architecture/stealth-and-surprise-attacks-design.md` +
`stealth-surprise-attacks-prompt.md`, both removed once implemented).

**Part A — Stealth check vs Passive Perception**: a 5e-style static-DC check (no enemy roll)
deciding whether an unaware enemy notices the player. Applies to every enemy currently
`SLEEPING`/`STATIONARY`/`ROAMING` (not yet `CHASING`/`SEARCHING`) that has the player in FOV —
same sight metric `take_turn()` uses internally (`Enemy.can_see(target)`, a thin public wrapper
around `_can_see_entity()`). Rolled **once per real player turn** from `Player._resolve_stealth_check()`
(called at the top of `_on_turn_ending()`, which fires from `TurnManager.player_turn_ending` —
exactly once per non-reverted action, never for a free action like Rager/Eagle/Battlefield
Expert's side-step).

- **Trigger classification** — `GameState.stealth_check_skip`/`stealth_check_stillness`: two
  transient bools, set by the specific action's own call site right before its
  `TurnManager.begin_player_action()`, consumed and reset to `false` inside
  `_resolve_stealth_check()`. Neither set = "movement" (the default/untouched case — check fires,
  no stillness ADV). `stealth_check_skip = true` (attack/spell turns: `_bump_attack()`,
  `_resolve_cleave_attack()`, `_resolve_offhand_attack()`, `PlayerRanged.ranged_attack()`/
  `ranged_attack_tile()`, `PlayerThrowTool._throw_weapon()`, Frenzy/Limit Break execution, every
  `SpellEffects.cast_*()`) skips the check entirely that turn — the attacked enemy already got
  `on_disturbed()` at the same call site, so a second roll against it is pointless.
  `stealth_check_stillness = true` (wait, rest tick, search, door interact/lock/unlock, Thief
  Tools disarm/lock/pick, non-weapon item throw, bottle fill, Grip of the Forest, Shield
  equip/unequip/drag) grants +1 ADV on the roll (on top of whatever else applies) but the check
  still fires — it doesn't gate whether the check happens, only its ADV input.
- **Roll**: `d20 (Halfling-reroll-aware) + DEX mod + (proficiency_bonus if check_prof_dex)`.
  Rolled **once**, reused against every qualifying observer (5e group-stealth style) — but ADV is
  evaluated **per observer**: a base ADV count (stillness bonus + Zealous Presence) plus +1 more
  if that specific observer is `SLEEPING`. A second d20 is only rolled for an observer whose own
  net ADV differs from 0, so two observers in the same turn (one asleep, one awake-unaware) can
  net different outcomes from what reads as "the same roll". Enemy notices iff
  `stealth_total < enemy.passive_perception` (ties favor the player — stays hidden).
- **`Enemy.passive_perception`**: static DC, see the schema table's `"passive_perception"` row
  above for the authored-vs-derived rule.
- **On detection**: `enemy._notice_target(player.grid_pos)` (wakes SLEEPING/STATIONARY/ROAMING →
  CHASING, sets `last_known_target_pos`, AND sets `just_noticed`/shows the "?" marker — see
  "Notice freeze" below) + a log line (`"<Enemy> [url=stealth:...]notices[/url] you!"`, `stealth:`
  meta, `TooltipFormatters.fmt_stealth_tooltip()`). **Silent on a non-detection** by default — no
  floater, no log spam for walking past sleepers. `GameState.debug_show_stealth_checks` (F3 debug
  panel checkbox, "Show Stealth Checks") makes every roll — pass or fail — print a gray log line
  with the same tooltip; toggling it never changes the roll or its outcome, visibility only.
  `GameState.god_mode` appends a gray `(Stealth X vs PP Y)` suffix to either log line.
- **Wake-on-attacked**: `Enemy.on_disturbed(source_pos)` — if `SLEEPING`/`STATIONARY`/`ROAMING`,
  wakes + records `last_known_target_pos`, **without** the notice freeze below (being struck is a
  much bigger tell than merely being spotted — the enemy can retaliate on its very next turn).
  **Also unconditionally cancels an already-pending notice freeze** (`just_noticed`/the "?"
  marker) even if it was set one or more ROUNDS ago and the enemy was still sitting on its freebie
  freeze round — a direct attack always overrides "merely noticed", regardless of timing. Called
  after every player-side attack against that enemy, **hit or miss**, from `_bump_attack()`,
  `resolve_opportunity_attack()`, `_resolve_cleave_attack()`, `_resolve_offhand_attack()`,
  `PlayerRanged.ranged_attack()`, `PlayerThrowTool._throw_weapon()`, `Companion._attack_enemy()`,
  and every enemy-targeting cast in `spell_effects.gd` (`cast_spell()`, `cast_cantrip_save_at_enemy()`,
  `cast_leveled_at_enemy()`, `_resolve_spell_attack_bolt()` — covers both Chromatic Orb/Witch
  Bolt's primary AND leap target — and the per-target loop inside every AoE resolver:
  `_resolve_thunderclap()`, `_resolve_cone_aoe()`, `_resolve_sphere_aoe()`). Net effect: surprise
  ADV (Part B) only ever applies to the first attack of an engagement, and casting a spell/cantrip
  at (or catching in an AoE) an unaware enemy wakes it exactly like a melee/ranged/thrown attack —
  no "?" freeze, hit or miss.
- **Notice freeze — the golden "?"** (Shattered Pixel Dungeon-style): every transition from
  unaware (SLEEPING/STATIONARY/ROAMING) to CHASING that happens via *noticing* rather than *being
  attacked* — the stealth-check detection above, SLEEPING's true-adjacency backstop, and
  STATIONARY/ROAMING's can-see wake, all three now go through the shared `Enemy._notice_target(pos)`
  helper — sets `just_noticed = true` and shows a golden `"?"` label (`_notice_label`,
  `_show_notice_mark()`/`_hide_notice_mark()`, same per-enemy-child-Label pattern as `_zzz_label`).
  `_decide_action()` checks `just_noticed` first, before anything else: if set, it's consumed
  (cleared) and the enemy's ENTIRE round is spent on a `{"type": "notice"}` intent — no movement,
  no attack, marker stays up — so a freshly-noticed enemy always gets exactly one free round
  before it can act, regardless of distance (a far-off ROAMING enemy that spots you across a room
  also just notices that round rather than immediately closing distance). `_execute_action()`
  hides the marker the instant any OTHER intent type runs (the following round, when the enemy
  actually moves/attacks/etc.) — so the "?" is visible for exactly the one round between noticing
  and acting. SLEEPING's true-adjacency backstop (Chebyshev ≤ 1 in `_decide_action()`, still the
  final catch-all for "player stayed hidden vs. the stealth roll but is standing right next to a
  sleeper on ITS turn") now also routes through `_notice_target()` + `"notice"` instead of
  attacking immediately.

**Part B — Surprise-attack Advantage**: `PlayerVfx.has_advantage(enemy)` (`player.gd:1196`,
`player_ranged.gd`'s ranged call site) returns true iff the defender is unaware at the moment of
the attack roll: `door_ambush` (one-shot, see below) OR Fog Cloud's Blinded clause OR
`behavior in [SLEEPING, STATIONARY, ROAMING]`. `CHASING`/`SEARCHING` never grant it otherwise — a
fully aware hunter, even one momentarily out of FOV, is **not** surprised (deliberate: surprise is
purely a function of `behavior`, never re-evaluated against live FOV at attack time).

**`Enemy.door_ambush`** (replaces the old, buggy `just_crossed_door`): set in `_move_step()` only
when the enemy steps onto a door tile AND had **no** LOS to the player from its pre-step tile
(`_had_los_to_player_from(prev_pos)`) — so a CHASING enemy that already sees you opening a door
mid-pursuit does NOT get this (it's already covered by the CHASING-is-never-surprised rule
above); only a genuine door-camping ambush does. Expires unconditionally at the top of the
enemy's own next `take_turn()` (lifetime = exactly the round it happened) and is also consumed
one-shot on read by `has_advantage()`.

## Enemy behavior states
`SLEEPING → STATIONARY → ROAMING → CHASING → SEARCHING`

**SLEEPING**: shows zzz label. No LOS-based wake of its own anymore — see "Stealth & Surprise Attacks" below. Only free-wake tier: true adjacency (Chebyshev ≤ 1) in `_decide_action()` — now routes through `_notice_target()` (golden "?", one-round freeze) instead of attacking immediately.
**ROAMING**: waypoint BFS. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks tile at Chebyshev ≥ 4. Follows `_roam_path: Array[Vector2i]` via `_bfs_to()`. Falls back to `_do_random_step()` if blocked. Spotting the target (`can_see`) also routes through `_notice_target()` — a one-round freeze before it starts actually chasing.
**CHASING**: follows the selected target directly. Opens doors (sets `door_ambush = true` when stepping onto a door tile it had no prior LOS to the player from — see "Stealth & Surprise Attacks" below). Records `_search_heading` (direction toward target) each turn target is visible.
**SEARCHING**: entered when a CHASING enemy reaches `last_known_target_pos` without LOS. Searches for 7 turns in `_search_heading` direction (BFS to `_search_target = last_known_pos + heading * 5`). If the target is spotted → CHASING. After 7 turns → ROAMING. Fields: `_search_heading: Vector2i`, `_search_turns_remaining: int`, `_search_target: Vector2i`, `_search_path: Array[Vector2i]`.

`_roam_path` and `_roam_target` are cleared on state transitions.

**Every `_decide_action()`/`_execute_action()` path must await something real** (a move tween or the idle timer) — a branch that returns with zero elapsed time makes `TurnManager._process_enemies()` burn through that enemy's turn instantly, which can make a live-but-stuck floor feel empty/cleared even with `TurnManager.fast_mode == false`. Two branches previously fell through without awaiting: `_act_toward()`'s BFS-fallback failure (both an empty BFS path and a BFS path whose first step turns out unwalkable) and `_execute_action()`'s `"search"` case's SEARCHING→ROAMING transition (turns exhausted) — both now explicitly `await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout` before returning.

### `take_turn()` split: decide vs execute
Per `docs/architecture/enemy_system_architecture.md` §1: `take_turn()` handles only the prone/slowed early-return turns, then calls `_decide_action() -> Dictionary` (reads state, picks a target, advances the FSM, returns an intent like `{"type": "act_toward", "target": ..., "can_see": ...}` — does not await or touch visuals) followed by `await _execute_action(intent)` (all tweens/animation/logging, dispatched on `intent.type`: `attack`/`act_toward`/`roam`/`search`/`wait`). This is the seam every future need (archetypes, boss phases, Phase-2 determinism) hangs off of — see the architecture doc for why.

### Targeting: player + companion
`_decide_action()` no longer hardcodes the player as the target. `_get_target_candidates()` returns every live `is_friendly` entity currently relevant — `[player, GameState.player_companion]`, skipping either if null/dead. `_select_target(candidates)` picks: whichever candidate is already adjacent (Chebyshev 1) wins outright — "first to reach range" — tie-broken by lower current HP if both are adjacent; otherwise the nearer candidate by squared distance. No target-lock field: every turn re-asks "who's closest / who's adjacent" from current positions (see architecture doc §5 for why a lock was rejected). `_act_toward(target: Node)` and `_attack_target(target: Node)` work against either a `Player` or a `Companion` — attack dispatch is `if target is Player: _attack_player(target) elif target is Companion: _attack_companion(target)`. `Companion.take_damage_from_enemy()` is the damage-intake path for the latter (already existed on `Companion`, just never had an enemy-side caller before).

### Attack profiles (ranged enemies)
Pool entries may set `"attack_profile": {"kind": "ranged", "range": N, "projectile": "..."}` (absent = implicit melee, zero change for existing entries). `Enemy._in_attack_range(target)` reads `_type.get("attack_profile", {})`: melee requires Chebyshev == 1; ranged requires Chebyshev ≤ `range` AND `_dungeon_floor.has_ranged_los()`. `_act_toward()` calls `_attack_target()` once in range, otherwise steps toward the target exactly like melee (reuses the same BFS/greedy stepping — approaching until in range, not until adjacent). A generic ranged-ability dispatch (cooldown/uses_max/recharge, damage+optional status) now exists — see "Enemy D&D stat-block schema" above's `"abilities"` row — for a caster-style enemy that picks between melee approach and a ranged ability; a true multi-spell caster archetype (choosing between several abilities by trigger condition) still doesn't exist beyond that single-generic-shape dispatch. Reference pool entry for plain ranged attack_profile: `"Goblin Archer"` (`enemy_id: "goblin_archer"`, `DungeonFloorData.ENEMY_POOL`).

### Shared attack resolver
`Enemy._resolve_attack_roll(target_ac: int, attack_bonus_override: int = -1, roll_penalty: int = 0) -> Dictionary` is the one d20-vs-AC roll (Reckless Attack ADV/flat bonus, Grip of the Forest R3 disadvantage, crit-on-nat-20, Blade Ward's `roll_penalty`) shared by every enemy attack — melee or ranged, vs player or vs companion. `_attack_player()` and `_attack_companion()` both call it, then handle their own damage application/logging (player routes through `take_damage_raw` for rage DR/poison/Retaliation; companion calls `Companion.take_damage_from_enemy()`, which has no such hooks — those are player-only systems). `_attack_player()` is the only caller that ever passes a nonzero `roll_penalty` (Blade Ward, player-only buff) — subtracted from the roll AFTER ADV/DISADV resolves, before the AC comparison; never reduces a natural-20 crit.

### Enemy/boss pool ids
`DungeonFloorData.ENEMY_POOL` entries carry an `"enemy_id"` key, `BOSS_POOL` entries an `"boss_id"` key (e.g. `"orc_warrior"`, `"big_demon"`) — stable machine ids, unlike `display_name` which is UI text and shouldn't be load-bearing. `Enemy.enemy_id: String` is populated from either key in `configure()`. No behavior depends on these yet; they exist so future systems (boss-phase gating, per-enemy talent interactions) can key off a stable id instead of string-matching `display_name`.

---

## Player-specific (`player.gd`)
- `_click_start_screen_pos`: recorded on LMB press; drag > 8 px cancels `_queued_path`
- `_lmb_press_over_ui: bool` — set in `_input()`'s LMB-press branch via
  `get_viewport().gui_get_hovered_control() != null` (any Control under the cursor at the moment
  of the press — a Spellbook row, an ActionBar slot, any overlay). Gates the camera-pan-on-drag
  detector in `_input()`'s mouse-motion branch: a drag that STARTS over UI never pans the camera,
  regardless of where it later travels; a drag starting on bare game world still pans normally.
  General fix for "dragging a UI element also drags the background/level" — `_input()` fires
  before any Control's `gui_input`, so per-overlay-flag checks (`spellbook_open` etc., still kept
  as defense-in-depth) can never fully cover every UI drag source one at a time; this covers all
  of them uniformly, including the in-bar reorder drag (`hud.gd`'s `_process_bar_drag()`, see
  `scripts/ui/CLAUDE.md`'s "In-bar reorder drag") which has no overlay open at all.
- `_fov_prev_turn` / `_fov_this_turn`: maintained per turn (no longer grant ADV on their own)
- Throw mode entered via `GameState.player_throw_primed` signal; Esc cancels
- All input gated on `TurnManager.phase == WAITING_FOR_INPUT` AND `GameState.short_rest_open == false` AND `GameState.talent_picker_open == false` AND `GameState.mastery_picker_open == false` AND `GameState.subclass_picker_open == false`
- `_vex_adv_target: Enemy` — Vex mastery's per-turn ADV-vs-target flag (Short Bow). Consumed on the next attack attempt (any type) against that enemy; reset in `_on_turn_started()`'s `if not came_from_revert:` block alongside `_frenzy_triggered_this_turn` etc. — survives a `revert_to_waiting()` free-action chain within the same round, clears on a real new round.
- `_finish_kill(enemy: Enemy, dropped_ammo: Item = null)` — optional second param used only by `PlayerRanged.ranged_attack()`'s kill path (the ammo item consumed by the killing shot); rolls a 50% chance to drop it at the corpse's tile via `PlayerAmmo.resolve_ammo_landing()`. Other call sites (`_resolve_cleave_attack`, `try_retaliation`) pass no second arg.
- `_try_offhand_attack(enemy, is_str_weapon)` / `_resolve_offhand_attack(enemy, weapon, label = "Off-hand")` — dual-wielding's bonus Off-hand swing, called from both the hit and miss paths of `_bump_attack()` right after `_try_cleave()`. Also fires a second, `"Nick"`-labeled call to `_resolve_offhand_attack()` when either equipped Light weapon carries the Nick mastery. See `scripts/items/CLAUDE.md`'s "Dual-wielding" and "Weapon masteries" (Nick).
- **Chase-to-attack interrupt on enemy notice/attack**: clicking a distant enemy sets `_target_enemy` and `_execute_queued_path()` auto-walks toward it each real turn (see "Enemy-chase mode" in that function). If the chased enemy — or any other enemy — notices the player (`Enemy._notice_target()`, e.g. a failed Stealth check, or the SLEEPING/STATIONARY/ROAMING wake) or actually swings at the player (hit or miss, `enemy.gd._attack_player()`) during the enemy phase that just resolved, the chase is cancelled and the player must re-issue the command — prevents a fast/ranged enemy from getting several free swings in while the player is mid-sprint and can't react in time. Mechanism: `GameState.enemy_noticed_player_this_turn`/`player_attacked_this_turn` (both per-turn transient flags, reset every real turn) are snapshotted into `Player._enemy_noticed_last_round`/`_enemy_attacked_last_round` at the TOP of `_on_turn_started()`'s `if not came_from_revert:` block, before that same block clears the source flags — required because `_on_turn_started` (connected in `_ready()`) always runs before `_execute_queued_path()`'s own `await TurnManager.player_turn_started` resumes, so reading the raw `GameState` flags directly from the chase loop would always see them already cleared. Both snapshot fields are reset to `false` at the moment a new chase target is clicked, so a stale notice/attack from before the click can't immediately abort the very first step.

**Split-out modules** (pure refactor, same behavior — GDScript has no partial classes, so these use composition/static-helper patterns instead, same convention as `scripts/ui/*.gd` — see `scripts/ui/CLAUDE.md`'s "Split-out modules"). Each composition child-node holds a `player: Player` back-reference and is instantiated once in `player.gd._ready()`:
- `player_wild_heart.gd` (`PlayerWildHeart`, composition child-node, `extends Node`) — One with Nature (companion summon/dismiss), Natural Rager form cycling, Natural Sleeper form cycling (was `player.gd._activate_one_with_nature()` etc.). `player.gd._use_ability_slot()` routes matching ability_ids to `_wild_heart`.
- `player_zealot.gd` (`PlayerZealot`) — Zealot Strike activation + heal resolution, Judgement Day pending-bonus flag, Overheal Shield. See "Zealot Tier 2 talents" below.
- `player_berserker.gd` (`PlayerBerserker`) — Frenzy activation + resolution, Masochist Monster's AC/temp-HP hooks, Frenzied Killer's refresh triggers. See "Berserker Tier 2 talents" below.
- `player_scarred_warrior.gd` (`PlayerScarredWarrior`) — Limit Break activation + resolution (splash/piercing-line targeting), Bloodied Regen's per-turn temp HP. See "Scarred Warrior Tier 2 talents" below.
- `player_base_talents.gd` (`PlayerBaseTalents`) — Psycho/Bruiser/Battlefield Expert (Barbarian Tier 1, shared by every subclass). See "Barbarian Tier 1 talents" below.
- `player_ammo.gd` (`PlayerAmmo`) — named-ammo stack lookup/consumption + ammo-landing resolution (floor pickup / chasm / wall-destroyed). Called from `PlayerRanged` and `player.gd._finish_kill()`.
- `player_throw_tool.gd` (`PlayerThrowTool`) — throw-mode and tool-priming activation, bottle fill/creation, and the Thrown-weapon attack (`_throw_weapon()` — see `scripts/items/CLAUDE.md`'s "Thrown weapons"). `_throw_item`/`_tool_item` fields deliberately stay on `Player` itself (read from ~10 other input/movement call sites to cancel on move/Esc) — only the functions moved here, mutating the fields via the `player` back-reference. `do_throw()` branches to `_throw_weapon()` before the generic food/item-throw path whenever the primed item is `Item.Type.WEAPON` with `is_thrown == true`.
- `player_thief_tools.gd` (`PlayerThiefTools`) — disarm trap / lock / pick-lock door actions, plus `show_float_text()` (its only caller). `player.gd._try_move()`'s Thief-Tools-primed bump path and `PlayerActions.interact_action()` call into this.
- `player_vfx.gd` (`PlayerVfx`) — blood trail, hit-flash tween, sword-slash arc, surprise-mark "!" floater, screen shake, the ADV surprise-attack check (`has_advantage()`). `GameState.screen_shake` connects directly to `_vfx.screen_shake`.
- `player_actions.gd` (`PlayerActions`) — short rest / talent picker openers, wait, search/inspect, passive trap perception, floor-item pickup, door/trap interact dispatch. Owns `_last_search_request`/`_traps_in_proximity` (were player.gd fields).
- `combat_math.gd` (`CombatMath`, static-func-only helper, `extends RefCounted`, mirrors `scripts/ui/tooltip_formatters.gd`'s pattern) — the ADV/DISADV d20-roll resolution shared verbatim by melee/cleave/ranged (`roll_with_adv_disadv()`), weapon proficiency bonus (`weapon_prof_bonus()` — was `player.gd._weapon_prof_bonus()`, see "Weapon proficiency flags" above), `melee_reach_bonus()` (Branching Strike's talent-rank reach) and `melee_reach(weapon, rank)` (total melee range = `1 + melee_reach_bonus(rank) + 1 if weapon.is_reach`, additive — used by the chase-to-attack range check and Cleave's target-gathering radius), `finesse_modifier(str_mod, dex_mod, is_finesse) -> int` (returns `max(str_mod, dex_mod)` when `is_finesse`, else `str_mod` — used for both the attack roll and damage roll in `player.gd._bump_attack()` when `GameState.equipped_weapon.is_finesse`), and `encode_bonus_sources()`/`decode_bonus_sources()` (generic bonus-damage tooltip encoding — see "Bonus damage stacking" below). The bonus-damage STACKING sequence itself (Ironwood Bark/Judgement Day summation) and the full hit/miss/log flow stay in `player.gd._bump_attack()`/`PlayerRanged.ranged_attack()` — see "Bonus damage stacking" above.
- `player_ranged.gd` (`PlayerRanged`) — the full ranged-combat body: range/LOS checks (`is_ranged_target_in_range()`, `ranged_shot_disadvantage()`, `is_in_ranged_range()`), the ranged attack roll (`ranged_attack()`), projectile VFX (`show_projectile()`), and ranged-at-tile (`ranged_attack_tile()`). Mirrors `_bump_attack()`'s ADV/DISADV/crit/Divine-Fury-stacking structure closely — kept as one function per the same "don't split stateful stacking logic" reasoning as melee (see "Bonus damage stacking" above).

---

## Barbarian class
`Stats.proficiency_bonus` is a computed property scaling per D&D 5e (+2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.). `Stats.rage_uses_max` is a computed property scaling by Barbarian level: 2/3/4/5 at levels 1/4/6/12 (cap 5 at 17+). `Stats.rage_bonus_damage` is a computed property: +2 at levels 1–8, +3 at 9–15, +4 at 16+. Level-up grants the extra use immediately when crossing a threshold. **Barbarian unarmored defense**: `Stats.recalc_ac(has_armor_equipped)` — if BARBARIAN and no armor, AC = 10 + DEX + CON.

Tier 1 (levels 1–6): earns 5 talent points, spent across 3 talents — Psycho, Bruiser, Battlefield Expert (max 3 ranks each = 9 total possible cost → a run can max at most two, or spread points across all three). Points are granted on the level-up transitions into 2/3/4/5/6 (`GameState.TIER_LEVEL_RANGES[1] = [1, 6]`) — level 1 itself grants nothing (no level-up fires), so the 5th and last Tier 1 point lands at level 6, not level 5. These base talents (added per `markdowns/barbarian_base.md`) are shared by every subclass and grant no ability-bar entry — they're pure passive/reactive hooks read directly via `GameState.get_talent_rank()` at point of use. (Reckless Attack and Danger Sense were removed — vestigial, unused talents; nothing reads their old talent ids anymore.) Starting equipment given in `GameState.give_class_starting_items()` → `_give_barbarian_starting_items()`:
- **Greataxe** — 1d12 Slashing, `is_two_handed=true`, `is_heavy=true`, `weapon_mastery="Cleave"`, `weapon_category="Martial"`. `damage_die_min/max` on Item define dice; `recalculate_stats()` applies them. Two-handed blocks the ranged slot. Barbarian has both `proficient_simple_weapons` and `proficient_martial_weapons` set, so the Martial tag never shows red for this class.
- **Rage** (ability_id `"rage"`) — in slot 0. Uses and bonus damage scale by level (see computed properties above). **Baked-in baseline (no longer talent-gated, per `markdowns/barbarian_base.md`)**: lasts 1 turn, refreshed to 1 turn whenever the player attacks (hit or miss) or is attacked (hit or miss) — `player.gd._on_turn_started()`'s rage-tick block reads `_rage_attacked_this_turn` (set in `_bump_attack()` and `PlayerBerserker.execute_frenzy()`) or `GameState.player_attacked_this_turn` (set in `enemy.gd._attack_player()` on any attack roll, hit or miss — distinct from `GameState.player_was_hit_this_turn`, which specifically means damage landed and is what Battlefield Expert R3 reads). The whole rage-tick block is gated on `not came_from_revert` — it only runs on a REAL turn (after enemies actually act), never on a reverted/free-action turn (Frenzy, Battlefield Expert's free side-step), so using a free action doesn't silently burn down Rage's duration. Always grants 50% physical damage reduction (Slashing/Piercing/Bludgeoning) while active — `GameState.take_damage_raw(amount, ignore_rage, damage_type)` applies it unconditionally. Activation is a **free action**. Red sprite tint. Rage ends if heavy armor equipped (`item.is_heavy_armor`). Masochist Monster R3 (Berserker) can override the per-turn decrement — see below.

**Barbarian Tier 1 talents** (levels 1–5, no fixed level-up unlocks — all are point-gated):
- **Psycho** (`talent_id: "psycho"`, max 3): Composition module `player_base_talents.gd` (`PlayerBaseTalents`, `_base_talents`). R1: after a kill (`_finish_kill()`, hooked once — covers every kill call site including subclass finishers like Frenzy/Limit Break — via `_base_talents.on_kill()`), the next attack (any type) is made with Advantage — `GameState.psycho_adv_pending: bool` (lives on `GameState`, not on `PlayerBaseTalents`, so the HUD status tray can read it — see `scripts/ui/CLAUDE.md`), persists across turns until consumed, added into `adv_count` at all 6 player attack-roll sites (`_bump_attack`, `_resolve_cleave_attack`, `_resolve_offhand_attack`, `resolve_opportunity_attack`, `PlayerRanged.ranged_attack`, `PlayerThrowTool`'s throw resolution) via `_base_talents.consume_psycho_or_battlefield_adv()` (shared with Battlefield Expert R1's identical pending-ADV pattern — each independently contributes, see the function). R2: a critical hit *also* triggers the same pending-Advantage window — `_base_talents.on_crit()`, hooked at the same 6 attack-roll sites whenever `is_crit` is true (R1's kill trigger stays active at R2; the two are additive, not replaced). R3: crit range widens to 19-20 while attacking with Advantage — `CombatMath.is_critical_hit(die, adv) -> bool`, replaces the `die == 20` check at all 6 sites uniformly. (Psycho R2 no longer adds a flat STR-modifier damage bonus — that behavior was removed and replaced by the crit trigger above.)
- **Bruiser** (`talent_id: "bruiser"`, max 3): Uses the shared `Stats.is_bloodied()` mechanic (below 50% max HP). R1: `GameState.heal(amount) -> int` — the single chokepoint for short-rest healing, potions, and Zealot Strike — adds `+1d4` to the amount whenever the player is Bloodied at heal time (does not apply to Temp HP grants, which don't call `heal()`) and **returns the rolled bonus** so every call site can name it as its own `"Bruiser"` source in the heal chat tooltip (`heal:` meta's `bonus=` field, `CombatMath.encode_bonus_sources()` — same generic mechanism `dmg:` tooltips use) instead of it silently vanishing into the total. R2: `+1 AC` while Bloodied, folded into `recalculate_stats()` alongside `terrain_ac_bonus`/`masochist_ac_bonus`; both `take_damage_raw()` and `heal()` call `recalculate_stats()` on every HP change **only if** rank ≥ 2 (avoids the extra work for characters who haven't invested). R3: once per floor (`GameState.bruiser_revive_used_this_floor`, reset in `advance_floor()`), if a hit while Raging would drop the player to 0 HP, `check_player_death()` intercepts before setting `is_game_over`: sets `current_hp = 1`, emits `GameState.force_rage_end` (a signal `player.gd._ready()` connects directly to `_end_rage()`, since Rage state lives on `Player` not `GameState`), and returns instead of ending the run.
- **Battlefield Expert** (`talent_id: "battlefield_expert"`, max 3): Same composition module as Psycho. **Side-step** = a player move that stays within a given enemy's melee reach on both the previous and next tile AND is a genuine diagonal pivot around the enemy (`d_prev <= reach and d_next <= reach and prev != next and absi(next.x - prev.x) == 1 and absi(next.y - prev.y) == 1`) — a pure lateral slide that stays adjacent along one side of the enemy (e.g. NW→N) does NOT count, only a true corner-to-corner move around it does. This condition sits right alongside the existing no-Opportunity-Attack branch in `_resolve_enemy_opportunity_attacks(prev, next)` (see "Opportunity Attacks" below — the OA-suppression branch itself is unchanged, only the Battlefield Expert trigger got the extra diagonal check): `_base_talents.on_sidestep(e)`. Triggering it (rank ≥ 1) logs a chat message and grants the **Tactician** buff. R1: next attack (any type) gets Advantage — `GameState.battlefield_adv_pending` (lives on `GameState`, same reasoning as `psycho_adv_pending` above), same drain mechanism as Psycho's pending-ADV (`consume_psycho_or_battlefield_adv()`); shown in the HUD status tray as `tactician` while pending (`scripts/ui/CLAUDE.md`). **Unlike Psycho's pending-ADV, Tactician expires if unused**: `GameState.battlefield_adv_expire_turns` (set to 2 in `on_sidestep()`) ticks down by 1 only on a REAL player turn-start (`PlayerBaseTalents.tick_battlefield_adv_expiry()`, called from `_on_turn_started()`'s `if not came_from_revert:` block, alongside `tick_free_sidestep()`) and clears `battlefield_adv_pending` when it hits 0; `consume_battlefield_adv()` resets the counter to 0 on use. Net effect: the buff survives through the end of the turn immediately following the side-step, then disappears if the player never attacked with it — and since R3's free side-step doesn't end the current turn at all (see below), it's also still usable in that very same turn before the countdown starts ticking. R2: the side-stepped enemy's `Enemy.disadv_next_attack = true` (existing field, also used by Grip of the Forest R3). R3: `GameState.player_was_hit_this_turn` (the same flag Rage's duration check reads) is read — but not cleared — in `_on_turn_started()`'s per-round-reset block via `_base_talents.tick_free_sidestep()`, then cleared once, unconditionally, after the rage-tick block (so Rage's own read isn't disturbed by this addition and non-Raging Barbarians don't leak the flag forever). If set, the player's first side-step this turn is free: `_try_move()` captures `_base_talents.consume_free_sidestep()` right after the OA-resolution call (which is where `sidestep_detected_this_move` gets set) and, if true, calls `TurnManager.revert_to_waiting()` instead of `on_player_action_complete()` at the end of the move — same free-action pattern the removed Rager talent used. **Scope limitation**: only wired into `_try_move()` (single-step WASD movement); the queued-path/chase-to-target movement functions don't check for free side-steps. **Works in God Mode**: `GameState.take_damage_raw()`'s `invincible` branch still sets `player_was_hit_this_turn` on a physical hit (before returning 0) — the flag reflects "an attack connected", not "HP actually changed", so this R3 charge (and anything else keyed off the flag) isn't silently dead while invincible.

**Barbarian Tier 2 subclasses** (points at levels 7–12; unlocked by defeating the floor-5 boss). Full source specs (superseding the earlier `barbarian-tier1-rework-v2-prompt.md` design): `markdowns/barbarian_base.md`, `markdowns/berserker.md`, `markdowns/scarred_warrior.md`, `markdowns/wild_heart.md`, `markdowns/zealot.md`.
- Level-point schedule (`GameState.TIER_LEVEL_RANGES`): levels 1–6 grant Tier 1 points (5 points total, at the level-up transitions into 2/3/4/5/6). Levels 7–12 grant Tier 2 points into `GameState.talent_points[2]` — they sit pending until the gating boss (`GameState.TIER2_GATING_BOSS_ID`, the floor-5 Big Demon) is killed. Levels 13+ grant nothing until Tier 3.
- `GameState.tier2_unlocked: bool` — set by `unlock_tier2()` (boss-gated via `boss_defeated` — see `scripts/autoloads/CLAUDE.md`). `_setup_barbarian_tier2_talents()` appends 3 `Talent` objects to `_class_talents`.
- `GameState.TIER2_SUBCLASSES: PackedStringArray` = `["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]`. `active_tier2_subclass: String` tracks current. `debug_switch_subclass(direction)` cycles subclasses and calls `_setup_tier2_for_active_subclass()` — routes to Berserker, Scarred Warrior, Wild Heart, World Tree, or Zealot setup (all five are implemented). Arrows ◀ / ▶ appear in the talent picker Tier 2 header when God Mode is active.
- **Free base activation ability pattern**: Berserker (Frenzy), Scarred Warrior (Limit Break), Wild Heart (Animal Form), and Zealot (Zealot Strike) each grant one activation ability directly at subclass selection, via `GameState._grant_tier2_base_ability(id, name, description)` — **not** gated by any talent rank/investment. Their three Tier 2 talents only upgrade/enhance that base ability (never grant their own ability-bar entry) — see each subclass's `_apply_talent_rank()` case, which just refreshes the base ability's description. `GameState.TIER2_BASE_ABILITY_ID: Dictionary` maps subclass name → that ability's id; `debug_switch_subclass()` strips the previous subclass's base ability using this map (in addition to its 3 talent-bar entries) before granting the new subclass's. World Tree has no such base ability — all three of its Tier 2 talents remain individually rank-1-gated (unchanged, pre-existing pattern).
- `GameState.apply_player_status(type, turns) -> bool` — single chokepoint for all player status/debuff application. All trap, enemy, terrain, and rotten-meat status calls use this function.

**Wild Heart Tier 2 talents** (**experimental** — balance changes expected):
- State vars on GameState: `natural_rager_form: String = "Bear"` (current Animal Form), `natural_sleeper_form: String = "Owl"` (preview — chosen form for next rest), `active_sleeper_form: String = "Owl"` (locked in at floor descent), `wild_heart_sleeper_active: bool`, `player_evades_opportunity_attacks: bool`, `fov_radius_bonus: int`, `player_companion: Variant`, `terrain_ac_bonus: int`. (Internal var names keep their pre-rework identifiers — only ability/talent ids and display names changed.)
- **Animal Form** (ability_id `"animal_form"`, free base ability — no talent rank required): Toggle ability cycles Bear/Eagle/Wolf (`player_wild_heart.gd.cycle_animal_form()`); effects are always active, **no Rage requirement** (this differs from the pre-rework "Natural Rager", whose effects only applied while Raging). Bear: 25% resistance to elemental damage (Fire/Cold/Lightning/Thunder/Acid/Poison) in `take_damage_raw()`. Eagle: enemies never gain Opportunity Attacks against you (`GameState.player_evades_opportunity_attacks`, set on cycling and at subclass grant — see "Opportunity Attacks" below). Wolf: ADV on STR attacks when 4+ enemies are visible (`_bump_attack()`).
- **Enhanced Forms** (`talent_id: "enhanced_forms"`, max 3): Upgrades the base 3 forms — refreshes Animal Form's description only, no separate ability. Bear: R1 also resists magical damage (Radiant/Necrotic/Force); R2 33% total; R3 50% total. Eagle: R1 +1 FOV radius (`GameState.fov_radius_bonus`, threaded into `DungeonFloor._compute_shadowcast()`/`get_visible_enemies()`); R2 ranged attacks against you get -2 to hit *(not yet wired into enemy ranged-attack resolution — flagged as a gap, see below)*; R3 ranged enemies get Disadvantage *(same gap)*. Wolf: threshold drops 4→3→2 enemies; R3 also grants ADV at 1 enemy + 1 friendly (companion) in FOV.
- **Expanded Forms** (`talent_id: "expanded_forms"`, max 3): Toggle cycles Owl/Panther/Salmon (`cycle_natural_sleeper_form()`; simplified from the source spec's "random form per long rest" to player-chosen cycling, matching every other Wild Heart form toggle). **Form locking**: cycling mid-floor updates only `natural_sleeper_form` (preview); the effects use `active_sleeper_form`, which locks in ONLY on a completed long rest (`GameState.long_rest()`: `active_sleeper_form = natural_sleeper_form`) — not on short rest, not on floor descent. Terrain effects check `active_sleeper_form` in `_try_move()` and `_on_turn_started()`. Owl: chasm passthrough. Panther: mud not difficult. Salmon: water not difficult. R2: roll 2d6 THP at the **start of each real turn** while standing in form's terrain — THP replaces (not stacks) existing THP. R3: +2 AC (`GameState.terrain_ac_bonus` → `recalculate_stats()`; cleared between floors, updated on every move in `_try_move()`).
- **Wild Companion** (`talent_id: "wild_companion"`, max 3, ability_id `"wild_companion"`): Active ability (1 charge/rest). Summons animal companion at nearest free adjacent tile. R1=Squirrel(AC12,HP10,1d6), R2=Boar(AC14,HP20,2d6), R3=Bear(AC16,HP30,3d6). Re-activate while companion alive = dismiss+resummon. Charge restores on short rest OR long rest (`GameState.long_rest()` — NOT floor descent). Companion entity: `scripts/entities/companion.gd` — see "Companion" section above. `GameState.player_companion` = live reference or null.
- **`_reverted_this_round: bool`** in player.gd — set to `true` before every `revert_to_waiting()` call (Eagle's own free-move mechanic was removed in this rework; the flag now only guards `_eagle_free_move_used`). `_on_turn_started()` reads and clears it; when true, skips resetting per-round caps. Ensures per-round caps survive `revert_to_waiting()` and only reset after enemies actually go.

**Berserker Tier 2 talents** (max 3 ranks each). Composition module: `scripts/entities/player_berserker.gd` (`PlayerBerserker`, `_berserker`).
- **Frenzy** (ability_id `"frenzy"`, free base ability — no talent rank required): Requires `GameState.is_raging`. Hotkey activation arms `_berserker.frenzy_mode_active` (modeled on Grip of the Forest's `_hook_mode_active`) rather than auto-firing — the player must then either bump-move into an adjacent enemy (checked at the top of `player.gd._try_move()`'s `enemy != null` branch, same feel as a normal melee attack) or LMB-click an adjacent enemy (existing click handler); neither input auto-selects a target on its own. Either path calls `_berserker.execute_frenzy()`, which is a **free action** — it does not cost the turn (`player._reverted_this_round = true; TurnManager.revert_to_waiting()`, same free-action pattern as Battlefield Expert's side-step) and sets `player._rage_attacked_this_turn = true` so it refreshes Rage's duration exactly like a normal attack. **Outcome mechanic is a plain d20, unaffected by this section's changes** (no AC comparison, no ADV/DISADV, no attack modifier — intentional per spec): **Nat 1** = miss, only the player takes the damage; **2–19** = hit, enemy AND player take the *same* damage roll (+ any Sadist Monster bonus to the enemy only); **Nat 20** = enemy takes double damage (+ Sadist Monster, also doubled), player takes none. **Damage calculation and weapon-mastery triggering now mirror a normal attack exactly**: the shared damage roll is `weapon dice + weapon.bonus_damage + Rage bonus + STR/finesse mod` (same formula `_bump_attack()` uses, computed via `CombatMath.finesse_modifier()`/`weapon_prof_bonus()`), and the equipped weapon's `weapon_mastery` (if known) fires exactly as it would off a normal swing — Cleave (`player._try_cleave()`) and Nick/Off-hand (`player._try_offhand_attack()`) on every branch (each resolving its own independent to-hit roll, not Frenzy's damage-back mechanic), Vex (`player._vex_adv_target = enemy`) and Topple (`player._try_topple()`) on the hit/crit branches, Graze (`player._try_graze()`) on the miss branch. Both the enemy damage and the player's self-damage use the wielded weapon's actual `damage_type` (fallback `"Bludgeoning"` if unarmed) — **self-damage now routes through `GameState.take_damage_raw(amount, false, damage_type)`** (the same chokepoint every other source of damage to the player uses) instead of bypassing it, so physical self-damage gets Rage's unconditional 50% DR exactly like enemy damage taken normally would. Once per short rest (`GameState.berserker_frenzy_used`, reset in `_on_short_rest_completed()` and `GameState.long_rest()`). The attack roll and damage roll are two separate hover tooltips — `frzhit:` (what the d20 outcome means, `TooltipFormatters.fmt_frenzy_hit_tooltip()`) and the standard `dmg:` format (`TooltipFormatters.fmt_dmg_tooltip()`, same as a normal attack's damage tooltip — Rage bonus/Sadist Monster encoded via `CombatMath.encode_bonus_sources()`), one per damage number shown (enemy damage and self-damage each get their own `dmg:` meta).
- **Sadist Monster** (`talent_id: "sadist_monster"`, max 3): Frenzy's hit adds +Nd6 bonus damage to the enemy only (self-damage unaffected) — rolled per rank (R1=1 die, R2=2 dice, R3=3 dice) inside `execute_frenzy()`.
- **Masochist Monster** (`talent_id: "masochist_monster"`, max 3): R1: any damage taken on the player's own turn (including Frenzy self-damage, via `_berserker._note_self_damage()`) grants +1 AC until the start of the player's next turn — `GameState.masochist_ac_bonus`, folded into `recalculate_stats()` alongside `terrain_ac_bonus`, cleared in `_on_turn_started()` via `_berserker.clear_turn_start_ac_bonus()`. **Silent** — no chat log line (only the AC bonus itself, applied quietly). R2: also grants temp HP on the same trigger equal to `rage_bonus_damage` **separate** d4 rolls summed (2/3/4 individual dice by level, not one d4 roll multiplied by the rage bonus) — this one DOES log, with an `msn:` hover tooltip (`TooltipFormatters.fmt_masochist_tooltip()`) listing each roll and the summed total. R3: Rage's per-turn decrement is skipped entirely while at least 1 enemy is in FOV (checked in `player.gd._on_turn_started()`'s rage-tick block) — does NOT grant extra Rage uses, only prevents time-based expiry.
- **Frenzied Killer** (`talent_id: "frenzied_killer"`, max 3): Refreshes `berserker_frenzy_used` early. R1: whenever **Frenzy itself** (not any attack) lands the killing blow — scoped to `execute_frenzy()`'s own kill branches only, via `_berserker._refresh_frenzy_on("kill")`. R2: also whenever the player lands a critical hit with **any** attack — normal melee, cleave, off-hand, ranged, thrown, opportunity attack, or Frenzy's own crit — via `_berserker.refresh_on_any_crit()`, hooked alongside `PlayerBaseTalents.on_crit_or_kill()` at every one of those attack-roll sites (Frenzy's own nat-20 branch calls `_refresh_frenzy_on("crit")` directly since it isn't one of the shared sites). R3: also automatically every 3 real turns since last use (`GameState.berserker_turns_since_frenzy`, ticked in `_berserker.tick_frenzied_killer()` from `_on_turn_started()`).

**Scarred Warrior Tier 2 talents** (max 3 ranks each) — 5th subclass, replaces no prior slot. Composition module: `scripts/entities/player_scarred_warrior.gd` (`PlayerScarredWarrior`, `_scarred_warrior`). Shared "Bloodied" mechanic (below 50% max HP, integer division) lives on `Stats.is_bloodied()` — deliberately class-agnostic per spec, reusable by any future consumer.
- **Limit Break** (ability_id `"limit_break"`, free base ability — no talent rank required): Hotkey activation arms `_scarred_warrior.limit_break_mode_active` rather than auto-firing — bump-move into an adjacent enemy (checked in `player.gd._try_move()` alongside Frenzy's same check) or LMB-click resolves it; range is 1 tile (adjacent, bump-reachable) at talent rank 0, or 5 tiles piercing-line at Enough is Enough R3 (click-only, out of bump range). Deals flat damage equal to the player's missing HP (`max_hp - current_hp`) to the target — **no roll to hit, no damage roll**. Still costs the turn (unlike Frenzy). Once per long rest (`GameState.scarred_warrior_limit_break_used`).
- **Born in Blood** (`talent_id: "born_in_blood"`, max 3): Modifies ALL incoming physical/magical damage (applied in `GameState.take_damage_raw()`, after Rage/Bear DR): not Bloodied → +N×`rage_bonus_damage` incoming damage; Bloodied → -N×`rage_bonus_damage` (floored at 0). Does not affect Limit Break's own damage (Limit Break damage is dealt, not received).
- **Enough is Enough** (`talent_id: "enough_is_enough"`, max 3): Upgrades Limit Break (refreshes its description only). R1: automatically applies a representative effect for the equipped weapon's known mastery to the target (`_scarred_warrior._apply_weapon_mastery_effect()` — currently handles Topple/Slow/Push; masteries that need an attack roll to hook into, e.g. Vex/Nick/Graze, are silently skipped rather than faked). R2: also deals full (unreduced) damage to every entity adjacent to the primary target. R3: becomes ranged (5 tiles) and pierces — hits every entity on the line to the target (ranks are additive: R3 includes R1+R2's effects).
- **Spite** (`talent_id: "bloodied_regen"`, talent name "Spite" per spec's naming suggestion, max 3): While Bloodied, grants `N × rage_bonus_damage` temp HP (replace, not stack) at the start of every real turn — `_scarred_warrior.tick_bloodied_regen()`, called from `_on_turn_started()`.

**World Tree Tier 2 talents** (max 3 ranks each, unchanged by this rework):
- **Ironwood Bark** (`talent_id: "ironwood_bark"`, max 3): Passive ability added to bar at rank 1 (no activation — triggers automatically). R1: activating Rage (`player.gd._activate_rage()`) grants `1d6 × rage_bonus_damage` temp HP. R2/R3: evaluated together in `_on_turn_started()`, gated on `not came_from_revert` (real turns only) — **critical evaluation-order rule**: both ranks read the SAME pre-turn `temp_hp` snapshot taken before either mutates it. If snapshot is 0 and rank ≥ 2: refresh temp HP (`1d6 × rage_bonus_damage`, replace not stack). Else if snapshot > 0 and rank ≥ 3: set `_ironwood_bark_bonus_pending = snapshot`. This keeps R2/R3 mutually exclusive each turn — R2's refresh this tick can never also trigger R3 this same tick. `_ironwood_bark_bonus_pending` is consumed once in `_bump_attack()` (added as bonus damage on the next attack, tagged `(+N Ironwood Bark)`, then zeroed) — mirrors the Frenzy bonus-damage pattern exactly.
- **Grip of the Forest** (`talent_id: "grip_of_the_forest"`, max 3): Active ability added to bar at rank 1 — activating (`player.gd._activate_grip_of_the_forest()`) requires `GameState.is_raging` and not `_grip_used_this_turn` (reset in `_on_turn_started()`), then arms `_hook_mode_active` (modeled on throw-mode priming, not a toggle). Next LMB click on an enemy within range (R1=3/R2=4/R3=5 tiles, Chebyshev, `has_ranged_los()`) resolves `_execute_hook()`, which costs the turn like a normal action. Enemy rolls `Enemy.resist_check(dc)` (STR-based) vs `dc = 8 + player STR mod + proficiency` (see "Enemy resist checks" above). On success, pulls the enemy toward the player one tile at a time via `DungeonFloor.force_move_entity()`, stopping once adjacent. R2: sets `enemy.rooted_turns = 1`. R3: sets `enemy.disadv_next_attack = true`.
- **Branching Strike** (`talent_id: "branching_strike"`, max 3): Passive ability added to bar at rank 1. R1/R2: reach bonus for `Item.is_heavy or Item.is_versatile` melee weapons (`player.gd._melee_reach_bonus()` — R1 = +1 tile, R2 = +2 tiles, **replaces** R1, not additive). Applied at the chase-resolution chokepoint in `_execute_queued_path()` (`chase_path.size() <= 1 + _melee_reach_bonus()` instead of the old `== 1`). R3: on a successful hit with a heavy/versatile weapon, pushes the target 1 tile directly away from the player via `force_move_entity()` — target rolls `Enemy.resist_check(dc, true)` (CON-based) vs the same DC convention as Grip of the Forest.
- **Shared forced-movement hook**: `DungeonFloor.force_move_entity()` — see `scripts/world/CLAUDE.md`.

**Zealot Tier 2 talents** (max 3 ranks each). Composition module: `scripts/entities/player_zealot.gd` (`PlayerZealot`, `_zealot`) — reused from the pre-rework file, gutted and rewritten.
- **Zealot Strike** (ability_id `"zealot_strike"`, free base ability — no talent rank required): Toggle (free action, doesn't cost the turn itself). Arms `_zealot.zealot_strike_armed`; the player's **next melee attack this turn** (hit or miss — checked in `_bump_attack()` right before the miss branch, mirroring the old Blessed Warrior call site; **ranged attacks never trigger it**, per spec) resolves `_zealot.resolve_zealot_strike_heal()`: consumes 1 Hit Die (`GameState.hit_dice -= 1`), heals `1d[hit_die_sides] + CON mod`. If the turn ends without a melee attack, `zealot_strike_armed` is cleared in `_on_turn_started()` with **no** Hit Die consumed (matches spec exactly).
- **Judgement Day** (`talent_id: "judgement_day"`, max 3): After a Zealot Strike heal resolves, sets `_zealot.judgement_day_pending = true`; consumed by the **next** attack (not the same attack that triggered the heal, mirroring Ironwood Bark R3's pending-bonus pattern) for `N × rage_bonus_damage × 1d6` bonus damage. Damage type comes from `_zealot.judgement_day_damage_type()`, currently a stub always returning `"Radiant"` — the source spec's full Morale (NPC-reputation) system that would flip it to `"Necrotic"` on low Morale is **not implemented** (out of scope for this pass; flagged as a follow-up).
- **Overheal Shield** (`talent_id: "overheal_shield"`, max 3): When a Zealot Strike heal resolves, grants Temporary HP (replace, not stack) based on rank: R1 = overheal amount only (`max(0, (pre-heal HP + heal roll) - max HP)`); R2 = the entire heal roll; R3 = heal roll + overheal. Scoped to Zealot Strike's own heal only (the source spec left "applies to all healing?" as an open question — this pass keeps it Zealot-Strike-only, the narrower/safer reading).
- **Never Back Down** (`talent_id: "never_back_down"`, max 3): +1/+2/+4 max Hit Dice by rank (**non-cumulative** — higher rank replaces, doesn't stack with, the previous rank's bonus; matches every other Barbarian talent's rank-replaces convention). `GameState.max_hit_dice() -> int` returns `character_level + bonus_by_rank`, used by `long_rest()`'s `hit_dice` refill and `short_rest_panel.gd`'s displayed cap instead of the raw level.

## Wizard spellcasting (cantrips)

A deliberately-scoped slice of `docs/architecture/spellcasting-design.md`: at-will, free-to-cast
cantrips (attack-roll, single-target SAVE, and self-cast/self-AoE resolutions) — no spell slots,
and only one lightweight concentration mechanism (Blade Ward, below) rather than the full design
doc's reaction/concentration framework. Leveled spells (with
real spell slots and a sphere-AoE example) are implemented on top of this (the plan doc that
speced them shipped and was deleted from `docs/architecture/` — the "Wizard leveled spells"
section below is now authoritative). Data classes (`Spell`, `SpellDb`, `SpellcasterState`, `StandardSlotPool`) live in
`scripts/items/` — see `scripts/items/CLAUDE.md`.

- **Wizard class defaults** (`Stats.apply_class_defaults()`): `proficient_simple_weapons = true`
  (martial stays false — simple weapons only, no armor training enforced yet, same pre-existing
  gap as Monk's TODO). Builds `Stats.caster = SpellcasterState.new()` with
  `spellcasting_ability = "INT"`.
- **Onboarding**: right after race select confirms (`scripts/ui/race_select.gd`, in the same slot
  the Mastery Picker would occupy — Wizard's `mastery_cap()` is already 0, so the two are mutually
  exclusive), a Wizard spawns `scripts/ui/cantrip_select.gd` for **two** "pick 1 of 3" rounds
  (owner-requested — a full caster starts with 2 cantrips, not 1). Round 1 always offers the
  original fixed trio (`SpellDb.STARTER_CANTRIP_IDS` — Fire Bolt / Ray of Frost / Shocking Grasp,
  unchanged so the premade Jace's `"cantrip": "fire_bolt"` shortcut and old saves stay valid);
  picking one immediately re-builds the same overlay for round 2, offering 3 candidates picked at
  random (`Rng`, gameplay stream) from every cantrip in `SpellDb.CANTRIP_IDS` except the one just
  chosen (could include the two unchosen starters or any of the 5 newer cantrips below). Each
  round's card-click commits immediately. Confirm calls `GameState.choose_cantrip(spell_id)`, which sets
  `Stats.caster.known_spells` (appends — never overwrites, since a Wizard's leveled starting
  spellbook is already populated by `_give_wizard_starting_items()` before this runs) and wraps
  the spell in an `Ability` (`ability_id = "spell:" + spell_id`, `uses_max = 0` — infinite/free)
  placed on the ability bar via `GameState._build_spell_ability()` + `add_ability()`. Persisted as
  part of `Stats.to_dict()`'s `"caster_known_spells"`/`"caster_prepared_spells"` arrays (see
  "Wizard leveled spells" below) — save/load rebuilds every spell's ability-bar entry via
  `GameState._rebuild_spell_ability_bar()`, called once after `Stats.from_dict()` restores the
  final known/prepared lists (mirrors talent replay's "derive abilities, don't serialize them"
  convention). The premade Jace (Halfling Wizard, `character_select.gd`'s `PREMADE` list) bypasses
  the picker like every other premade hero: a `"cantrip": "fire_bolt"` key in her entry makes
  `_on_premade_selected()` call `GameState.choose_cantrip("fire_bolt")` directly.
- **Icon assets**: real art exists under `res://icons/spells/<level>/<spell_id>.png` for most
  spells (8 cantrips in `0/`, most level-1/2/3 leveled spells in `1/`/`2/`/`3/` — `Spell.icon_path`
  in `spell_db.gd` points each spell at its own file; `magic_missile` maps to the pack's
  `1/arcane_missiles.png` since that's how the art is named; `expeditious_retreat`/`false_life`/
  `fog_cloud` have no art yet and render blank until added). `hud.gd._refresh_ability_bar()` still
  guards the ability-bar icon load with `ResourceLoader.exists()` (same guard the design doc calls
  for) and falls back to the ability name's first 4 letters as slot text whenever a spell's icon is
  missing, so a spell ability is never silently invisible in the bar. The same `icon_path` value
  is what every other spell-facing UI surface renders too — Spellbook tiles/drag icon, the
  Special-slot display in both the Spellbook and Inventory overlays, `Scroll of &lt;Spell&gt;`
  floor/debug-given items (`dungeon_floor.gd._build_floor_item()`/`debug_panel._on_give_item()`
  both resolve a scroll's icon via `SpellDb.get_spell(scroll_spell_id).icon_path` rather than
  reconstructing a flat path from the `ITEM_POOL` entry's own `"icon"` key), and the Concentration
  status-tray entry (`scripts/ui/CLAUDE.md`) — one source of truth, no separate icon wiring
  per surface.
- **Casting UX**: `player.gd._use_ability_slot()` has one guard — `ability_id.begins_with("spell:")`
  routes to `PlayerSpellcasting.begin_cast()` (`scripts/entities/player_spellcasting.gd`, a
  composition child-node registered in `player.gd._ready()` alongside `_ranged`/`_zealot`/etc.).
  Arms `spell_targeting_active` exactly like Grip of the Forest's `_hook_mode_active` hook-mode
  (single-target, no picker, no AoE preview needed): next LMB click resolves the cast if within
  `spell.range_tiles` — **Chebyshev distance** (diagonal counts as 1, matching melee-reach
  convention elsewhere — NOT the ranged-weapon-style squared-Euclidean check), `has_ranged_los()`-
  gated, no long-range-disadvantage tier unlike weapons. Range is deliberately **not** additionally
  clamped to the player's live FOV radius — visibility (`has_ranged_los`/fog) already governs what's
  actually clickable, so a spell whose range exceeds the FOV radius just can't reach further than
  currently visible, without a second redundant cap (Fire Bolt's nominal 12-tile range is real, not
  silently capped to the FOV radius of 7). Esc cancels (branch beside `_hook_mode_active`'s in
  `_unhandled_input()`). **Clicking an empty tile** (no enemy there) still costs the turn but skips
  the attack roll entirely — `SpellEffects.cast_spell_at_tile()` — nothing happens unless the tile
  itself is flammable (Fire Bolt's grass-ignite side effect below).
- **Cast resolution** (`scripts/entities/spell_effects.gd`, `SpellEffects.cast_spell()`, static —
  self-contained like `PlayerRanged.ranged_attack()`, owns its own `TurnManager.begin_player_action()`
  … `_handle_post_attack_turn()` turn envelope): attack roll = `d20 + SpellcasterState.
  spell_attack_bonus()` (`proficiency_bonus + INT mod`, computed live — never cached, never
  derived from `character_class`, per the design doc's multiclass-safety warning) vs target AC,
  same ADV/DISADV house rule and nat-20/nat-1 crit/fumble handling as `PlayerRanged`. Damage dice
  scale by cantrip tier (`SpellEffects._cantrip_tier()`: ×1/2/3/4 at character levels 1/5/11/17,
  the same D&D cantrip-scaling table as weapon dice would use). New `sphit:` tooltip meta
  (`TooltipFormatters.fmt_sphit_tooltip()`, dispatched in `hud.gd._format_tooltip()`) — same shape
  as `fmt_hit_tooltip()` but always labels the ability mod "INT".
- **The original three cantrips** (`SpellDb`, `scripts/items/spell_db.gd`), all Evocation, 1
  action, tier-scaling dice:
  - **Fire Bolt** — 12 tiles, 1d10 Fire. No `effect_id` (pure generic damage path) — if the target
    stands on a `GRASS` tile, the hit also calls `DungeonFloor.destroy_grass()`; otherwise it calls
    `DungeonFloor.ignite_flammable()`, which sets a Barrel or (unlocked) Door alight for a real
    3-turn burn-down timer — see `scripts/world/CLAUDE.md`'s "Barrels + flammable props". Fireball
    and Burning Hands' AoE resolvers (below) ignite every flammable tile they pass through the same
    way.
  - **Ray of Frost** — 6 tiles, 1d8 Cold. `effect_id = "ray_of_frost"`: on a hit, the target rolls
    a STR save (`resist_check_detailed()`, `dc = SpellcasterState.spell_save_dc()`) — logged to
    chat with a hoverable `save:` tooltip **either way** (pass or fail, Topple's
    `prof_label=Floor` convention — this is the enemy's floor-scaling bonus, not a proficiency
    bonus), not just on a fail; on a fail, `Enemy.frozen_feet_turns` is set — checked in
    `Enemy._decide_action()` right after the existing `rooted_turns` block, same shape (skip
    movement, still attack if already adjacent). Kept as its own field rather than reusing
    `rooted_turns` so the inspect line can name it "Frozen Feet" distinctly from Grip of the
    Forest's root.
  - **Shocking Grasp** — 1 tile (touch), 1d8 Lightning. `effect_id = "shocking_grasp"`: on a hit,
    sets `Enemy.shocked_no_oa = true` — checked at the very top of
    `Enemy._check_opportunity_attacks_on_move()` (before either the player or companion OA check):
    if true, consumes it and returns, blocking this enemy's next Opportunity-Attack exposure
    whenever it next happens (per spec, "doesn't matter when").
- **Casting at an empty tile** (`SpellEffects.cast_spell_at_tile()`): still costs the turn (same
  convention as `PlayerRanged.ranged_attack_tile()`), but skips the attack roll entirely — only
  Fire Bolt's grass-ignite side effect can still fire (`spell.effect_id == ""` check), everything
  else is a silent no-op.
- **Inspect** (`PlayerActions.do_inspect()`): the enemy info line gains a status suffix —
  `Frozen Feet` / `Shocked` — whenever either field is active (inspect previously showed no status
  effects at all; this is new, not a change to prior text).

**Five more cantrips** (all Wizard-castable, `CANTRIP_IDS` in `scripts/items/spell_db.gd`; also
each has a Scroll of &lt;Spell&gt; — see `scripts/items/CLAUDE.md`). These introduce two new
resolution shapes beyond the original three's attack-roll: single-target **SAVE** (no attack
roll, the target just makes a save) and **SELF** cantrips (instant self-buff or self-centered
AoE, dispatched through the same `SpellEffects.cast_leveled_self()` leveled spells already use —
level 0 spells skip `_consume_slot()`'s actual consumption since `cast_level` is 0, so nothing
extra was needed there).
- **Toll the Dead** (Necromancy, `effect_id: "toll_the_dead"`, SAVE/WIS, ENEMY, 6 tiles): target
  WIS-saves or takes `1d8` Necrotic — `1d12` instead if the target is already missing HP (checked
  at resolve time via `target.stats.current_hp < target.stats.max_hp`), same cantrip-tier dice-
  count scaling as the original three. `SpellEffects.cast_cantrip_save_at_enemy()` is the shared
  resolver for this and Mind Sliver below — no attack roll, just `Enemy.resist_check_detailed()`
  with the matching `use_wis`/`use_int` flag (see below) and a hoverable `save:` tooltip either way.
- **Mind Sliver** (Enchantment, `effect_id: "mind_sliver"`, SAVE/INT, ENEMY, 6 tiles): target
  INT-saves or takes `1d6` Psychic and sets `Enemy.mind_sliver_penalty_die = true` — consumed by
  that enemy's very next `resist_check_detailed()` call (any stat), rolling with `-1d4`.
  **Simplification**: RAW this lasts "until the end of your next turn"; this codebase instead
  consumes it on the enemy's next check regardless of timing, since enemy checks are rare enough
  (Push/Topple/Grip of the Forest saves) that a real turn-expiry timer wasn't worth a second
  mechanism — documented on the field itself in `enemy.gd`. The penalty is visible in the hover
  tooltip of whichever check consumes it: every `save:` meta built from a `resist_check_detailed()`
  result (Ray of Frost, Toll the Dead/Mind Sliver's own save, Thunderclap, Fireball, Topple) carries
  a `sliver=%d` field (`save["sliver_penalty"]`, 0 when not consumed), rendered by
  `TooltipFormatters.fmt_save_tooltip()` as a `"-N (Mind Sliver)"` line — not just silently folded
  into the roll total.
- **Thunderclap** (Evocation, `effect_id: "thunderclap"`, SAVE/CON, SELF, instant, radius 1):
  every enemy within 1 tile of the CASTER (not an impact point — `SpellEffects._resolve_thunderclap()`,
  a self-centered sibling of Fireball's `_resolve_sphere_aoe()`) CON-saves or takes `1d6` Thunder,
  tier-scaling. No friendly fire (the caster is the origin, never a target, unlike Fireball).
- **Blade Ward** (Abjuration, `effect_id: "blade_ward"`, AUTO_HIT, SELF, instant, **Concentration**):
  a real, if minimal, concentration mechanic — `Stats.concentration_spell_id`/`blade_ward_turns`
  (10-turn duration, ticked in `player.gd._on_turn_started()`'s `if not came_from_revert:` block
  alongside `shield_ac_bonus`). While active, every enemy attack roll against the player rolls a
  bonus `1d4` and subtracts it from the roll before the AC comparison — `Enemy._resolve_attack_roll()`
  gained a `roll_penalty` param, `_attack_player()` rolls it whenever `blade_ward_turns > 0` (never
  reduces a natural-20 crit). Breaks on taking damage via `GameState._check_concentration_break()`
  (called from `take_damage_raw()`'s tail): a CON check vs `DC = max(10, damage taken)` — **not**
  5e's usual half-damage DC, per the spell's own text — failure clears `concentration_spell_id`
  and `blade_ward_turns` immediately, logged. **Scope**: only `take_damage_raw()` callers
  (melee/ranged/enemy attacks, Fireball's own blast) trigger a concentration check — status-tick
  damage (poison/burning/bleeding) and trap damage bypass this chokepoint and don't break it, a
  documented simplification rather than an oversight. `concentration_spell_id` is a generic
  single-slot field (only Blade Ward uses it today, but casting a second, different concentration
  spell would break this one first — the chokepoint already exists in `cast_leveled_self()`'s
  `"blade_ward"` branch for whenever a second one is added).
- **Light** (Evocation, `effect_id: "light"`, AUTO_HIT, TILE, touch range 1): touch an object
  resting on the ground (a floor item — `dungeon_floor.get_item_at(tile_pos) != null`, never a
  worn/carried one) and it becomes a **real light source**, not cosmetic: `GameState.
  set_light_source(pos, color, item)` (random color from a fixed palette; `item` is the specific
  `Item` reference touched — kept so the light can tell when it's gone, see below) is read every
  `DungeonFloor.update_fog()` call, which unions its own `_compute_shadowcast(pos,
  LIGHT_SOURCE_RADIUS=4)` into the player's visible-tiles set (walls still block it — same
  shadowcast algorithm as the player's own FOV) — see `scripts/world/CLAUDE.md`'s "FOV" section.
  Only one Light source active at a time (recasting replaces it outright); ends on a completed rest
  (short or long — `_on_short_rest_completed()`/`long_rest()` both call
  `GameState.clear_light_source()`), on floor descent (`advance_floor()` — the lit object is left
  behind on the previous floor; this codebase's own reinterpretation of the spell's RAW "1 hour"
  duration, since there's no real-time clock to hang that off of), **or the instant the lit object
  leaves its floor tile** — picked up by the player, or otherwise removed — checked every
  `update_fog()` call via `GameState.light_source_item`'s presence in
  `get_items_at(light_source_pos)`. `DungeonFloor._update_light_source_glow()` tints every tile the
  light's own shadowcast actually reaches with `GameState.light_source_color` (not just a single
  square over the source tile) so the player can see both where it is and how far it reaches.

## Concentration (generic mechanism)
`Stats.concentration_spell_id: String` (`""` = not concentrating) + one duration field per
concentration spell (`blade_ward_turns`, `witch_bolt_turns`, `expeditious_retreat_turns`,
`fog_cloud_turns`). Not a full framework (no reaction-spell integration, no
multiple-effects-per-concentration) — just enough plumbing for each spell's own duration + break-
on-damage rule to be real rather than hand-waved.

**Only one concentration effect at a time**: `GameState.end_concentration(reason_log: String = "")`
is the single chokepoint for ending whatever the player currently concentrates on — clears
`concentration_spell_id` **and** that spell's own duration/target/just-cast fields (not just the
id). Every cast site that grants concentration (`SpellEffects.cast_leveled_self()`'s
`"blade_ward"`/`"expeditious_retreat"` branches, `cast_leveled_attack_at_enemy()`'s `"witch_bolt"`
branch, `_resolve_fog_cloud()`) calls it first whenever `concentration_spell_id != "" and
concentration_spell_id != <this spell>`, logging "Casting X breaks your concentration." Fixed bug:
previously each site only overwrote `concentration_spell_id` and left the OLD spell's own turn
counter untouched, so e.g. casting Blade Ward while Witch Bolt was active silently kept ticking
Witch Bolt's jolt damage forever (its tick only ever checked `witch_bolt_turns`, never
`concentration_spell_id`) even though the status/HUD said "concentrating on Blade Ward."
`GameState._check_concentration_break()`'s CON-check-failure path (below) also routes through
`end_concentration()` now instead of duplicating the per-spell clear logic.

**Status icon**: `hud.gd._update_status_icons()` appends a `"concentration"` entry to the
status tray (`scripts/ui/CLAUDE.md`) whenever `concentration_spell_id != ""`, using that spell's
own `SpellDb.get_spell(id).icon_path` (purple fallback tint) — so the icon and its hover tooltip
always reflect whichever spell is actually being concentrated on, not a generic fixed icon.
`StatusTooltips.build_bbcode("concentration")` special-cases the title to read "Concentrating:
&lt;Spell Name&gt;" by looking up `concentration_spell_id` live, rather than a static `TITLES` entry.

See "Blade Ward" above and "Witch Bolt" below for each spell's own mechanism.

## Wizard leveled spells (spell slots)

Implements the leveled-spells-and-slots plan (design doc shipped and was deleted from
`docs/architecture/` — this section is now authoritative) on top of the cantrip slice
above. **Simplifications vs. the original plan** (time-boxed for the first implementation pass, flagged
here rather than silently diverging): **no upcasting at all** — a spell only ever casts using a
slot that matches its own `level` exactly (`StandardSlotPool.available_level()`); if that specific
slot level has none remaining, the cast fails outright (`"No spell slot available for X."`), even
if a higher slot level is free. (An earlier version auto-promoted to the lowest available slot
ABOVE the spell's own level, which produced unrequested/surprising upcasts — e.g. Chromatic Orb
silently casting at a 5th-level slot with bonus dice — and was removed along with every
`Spell.upcast_dice_per_level`/extra-dice code path per direct owner correction.) AoE is
**sphere or cone only**, no line/cube. `LEVELED_SPELL_IDS` (8): Magic Missile, Shield, Mage Armor,
Misty Step, Fireball, Chromatic Orb, Burning Hands, Witch Bolt (the last 3 added after the initial
pass — see "More 1st-level spells" below, including Burning Hands' cone AoE, originally cut from
the doc's example list). Shield ships as a same-turn manual self-cast, not a
reaction (the reaction broker is out of scope). Drag-and-drop from the Spellbook targets the single
existing 9-slot ability bar (multi-page auto-paging from the framework doc isn't implemented
either) — see `scripts/ui/CLAUDE.md`'s "Spellbook overlay" section.

**AoE tile-preview overlay**: while a `TILE`-target, `shape == "sphere"` spell (currently only
Fireball) is armed via `PlayerSpellcasting.begin_cast()` (the ability-bar arm-then-click flow),
`player.gd._update_spell_aoe_preview()` runs every `_process()` frame (sibling call to
`_update_hover_indicator()`, same input-enabled gate, same mouse→tile conversion) and calls
`DungeonFloor.show_aoe_preview(hovered_tile, spell.shape_size)` /
`hide_aoe_preview()`. `PlayerSpellcasting.get_armed_spell()` is the read-only accessor that lets
`player.gd` see the armed spell's shape without touching the private `_armed_spell_id` field.
**Ctrl+click Special-slot cast**: `cast_direct()` resolves in the same frame it's clicked, so it
never arms `spell_targeting_active` long enough for `get_armed_spell()` to see it — instead,
`_update_spell_aoe_preview()` falls back to `GameState.special_slot_spell_id` (via
`SpellDb.get_spell()`) whenever Ctrl is held and no spell is otherwise armed, so holding Ctrl and
hovering with a sphere spell in the Special slot previews it exactly like the ability-bar flow.
`dungeon_floor.gd`'s implementation is a small pooled-`Sprite2D` overlay (1×1 white texture tinted
`Color(0.65, 0.25, 0.85, 0.35)` via `modulate`, `z_index = 2` — same layer as the fog sprite,
Node2D-world convention rather than a Control), rebuilt only when
the hovered tile/radius actually changes (`_aoe_preview_last_key` cache). **Deliberately not
LOS-filtered** — it shows the full raw Euclidean circle around the hovered tile (matching
`_resolve_sphere_aoe()`'s own distance check exactly, just without that function's *additional*
per-target LOS gate), since a Fireball's blast is meant to fill its radius around a corner from the
impact point rather than stop at the first wall it can't directly see through.

- **`StandardSlotPool`** (`scripts/items/spell_slot_pool.gd`) — the real D&D 2024 full-caster
  1–20 slot table (long-rest-only recharge, `on_short_rest()` is a no-op). Built and owned by
  `Stats.apply_class_defaults()`'s WIZARD branch (`caster.slot_pool = StandardSlotPool.new();
  caster.slot_pool.owner_stats = self`). `GameState.gain_exp()` snapshots `slot_pool.max_slots()`
  before applying a level-up and calls `slot_pool.grant_new_slots_on_levelup(old_max)` after —
  newly unlocked/grown slots are immediately usable instead of sitting empty until the next long
  rest (documented deviation from the framework doc's "new slots arrive empty" note — Wizard has
  no short-rest recharge to fall back on).
- **`SpellcasterState.prepared_spells`/`prepared_max(stats)`** — prepared count is
  `character_level` (cantrips never count against it), superseding the framework doc's
  `ability_mod + caster_level` formula. `known_spells` holds BOTH cantrips and leveled spells now
  (the "is this a cantrip" question is answered by `Spell.level == 0`, not by which array it's
  in) — `SpellcasterState.is_cantrip(id)`.
- **Starting spellbook**: `GameState._give_wizard_starting_items()` (called from
  `give_class_starting_items()`, same dispatch as `_give_barbarian_starting_items()`) seeds 2
  fixed level-1 spells (Magic Missile, Shield — the doc's plan for "3 fixed spells" predates the
  content list being trimmed to 4 total), Magic Missile prepared by default.
- **Level-up spell-learn picker**: `GameState.gain_exp()`'s level-up block, WIZARD only, calls
  `_roll_spell_learn_choices()` — rolls up to 3 random candidates from `SpellDb.CLASS_SPELL_LISTS`
  filtered to spells the character can currently slot-cast and not already known, sets
  `spell_learn_pending`/`spell_learn_choices`. `hud.gd._on_player_leveled_up()` spawns
  `scripts/ui/spell_learn_picker.gd` (mandatory, one card commits via `GameState.learn_spell(id)`)
  whenever `spell_learn_pending` is true. With only 4 example spells this often finds zero
  eligible candidates a few levels in — expected, logs a gray "No new spells available to learn."
  line instead of blocking (see the plan doc §7's content-count caveat).
- **Scrolls**: `Item.taught_spell_id` (empty = not a spell scroll). `GameState.use_item()`'s
  SCROLL branch calls `learn_spell()` and consumes the scroll if the spell isn't already known.
  No scroll items use this teaching mechanism in any loot pool yet.
- **Scroll of &lt;Spell&gt; (single-use cast scrolls, any class)**: `Item.scroll_spell_id` — a
  separate SCROLL mechanism from the teaching one above; reading it casts the baked-in spell once
  (base level, no slot spent) instead of teaching it. Castable by every class, not just Wizard —
  non-casters (no `Stats.caster`) use `proficiency_bonus + INT modifier` for the attack
  bonus/save DC via `SpellEffects._attack_bonus()`/`_save_dc()`/`_cast_ability_mod()`, which every
  spell-resolution function in `spell_effects.gd` now calls instead of reaching into
  `stats.caster` directly. Activation: `GameState.use_item()` emits `player_scroll_primed(item)` →
  `PlayerSpellcasting.on_scroll_primed()` (reuses the normal arm-then-LMB-click targeting flow,
  skips the spell-slot check/consumption, consumes the scroll itself on cast). Full walkthrough:
  `scripts/items/CLAUDE.md`'s "Scroll of &lt;Spell&gt;" section.
- **Spellbook overlay (`R` key)**: `scripts/ui/spellbook_overlay.gd` — see `scripts/ui/CLAUDE.md`.
  `GameState.set_spell_prepared(id, bool)` (click toggle) and `place_spell_in_slot(id, index)`
  (drag-and-drop onto a specific ability-bar slot) both add/remove the "spell:"-prefixed `Ability`
  via `GameState._build_spell_ability()`/`_remove_ability_by_id()`. No long-rest gating — the book
  can be opened and prepared spells changed any time outside of other blocking overlays (doc §5.5).
- **Casting a leveled spell**: `PlayerSpellcasting.begin_cast()` checks
  `caster.slot_pool.can_cast(spell)` before arming targeting (SELF spells like Shield skip
  targeting and cast immediately) — **skipped entirely while `GameState.invincible`** (God Mode),
  so a slot never needs to exist to cast, not just never gets spent; `try_cast_at()` dispatches on
  `Spell.target_kind` to one of three new `SpellEffects` functions — `cast_leveled_self()`,
  `cast_leveled_at_tile()`, `cast_leveled_at_enemy()` — each consuming a slot via `_consume_slot()`
  (guarded by `GameState.invincible`, same as every other consumption site) before resolving.
  `PlayerSpellcasting._cast_level_for(spell)` is the one chokepoint every arm/cast/direct-cast path
  reads: returns `spell.level` immediately when `invincible` (no slot lookup at all), else
  `caster.slot_pool.available_level(spell)` — the EXACT slot for that spell's own level, or `-1` if
  none remain (**no upcasting** — see "Wizard leveled spells" above). Fireball's AoE
  (`_resolve_sphere_aoe()`) hits every enemy AND the player within `shape_size` tiles (Euclidean)
  with LOS from the impact tile — real friendly fire, one `take_damage()`/`show_damage()` call per
  target per the damage-stacking RULE. Its DEX save (a "check" against `spell_save_dc` per this
  codebase's no-saving-throws house rule) is mechanically resolved via
  `Enemy.resist_check_detailed(dc, false, true)` — the third `use_dex` param rolls
  `d20 + floor_bonus + DEX mod` (enemy `dexterity` populated from an optional `"dex_mod"` pool
  key, same convention as `"str_mod"`/`"con_mod"`, default 0) and takes priority over `use_con`.
  **The player's own catch-in-blast hit now gets the same hoverable save breakdown the enemy
  targets do** — previously "You are caught in your own blast for N Fire dmg" had no `[url=]`
  tooltip at all, so there was no way to see your own DEX-check roll or whether you passed (half)
  or failed (full); it's now wrapped exactly like the enemy lines (`"caught"`/`"singed"` links to
  a `save:` meta). **Reductions the player's own hit takes are now called out in plain text**:
  `GameState.take_damage_raw()` can shave the landed amount below the post-save roll via Rage/Bear
  DR or temp-HP absorption, none of which is representable as the `dmg:` tooltip's `rmul` field
  (that's enemy-only, from `Enemy.take_typed_damage()`'s clean multiplier) — rather than leave a
  silent "31 rolled, only 25 landed" gap, the log line appends a gray `"(N before your own
  reductions)"` note whenever the landed amount differs from the post-save roll. **Guaranteed self-targeting**: `player.gd`'s
  spell-targeting click handler now resolves at `player.grid_pos` instead of the raw clicked tile
  whenever **Ctrl** is held on the click — a deliberate, precision-proof way to center a sphere
  AoE (or resolve a touch SELF spell, see Mage Armor above) on yourself without needing to click
  exactly on your own sprite (which sits under the camera-follow crosshair and can be fiddly to
  hit with a plain click, though a plain click on your own tile has always worked too).
- **Shield**: `Stats.shield_ac_bonus` (+5, folded into `recalc_ac()`), cleared at the start of the
  caster's next real turn in `player.gd._on_turn_started()`'s `if not came_from_revert:` block.
- **Mage Armor**: SELF-target, touch range (`range_tiles = 1`), AUTO_HIT — `SpellEffects.
  cast_leveled_self()`'s `"mage_armor"` branch. **Touch buffs don't self-cast on activation** the
  way Shield (range 0) does: `PlayerSpellcasting.begin_cast()`'s SELF branch only instant-casts
  when `spell.range_tiles <= 0`; any SELF spell with `range_tiles > 0` instead arms
  `spell_targeting_active` exactly like an ENEMY/TILE spell — a bare hotkey/ability-bar press
  can't silently burn a slot on a buff the player didn't mean to cast yet. **No ally-buff
  targeting exists** (only the caster's own tile is ever a valid touch target — a future
  ally-targetable touch spell would need `cast_leveled_self()`, or a new resolver, to accept a
  target other than `player`), so `try_cast_at()`'s `SELF` branch doesn't bother validating the
  click position at all: ANY click (or Ctrl+click, or a same-slot double-press — see below)
  confirms the cast on yourself, short-circuiting before the range/LOS check block entirely.
  Requiring the click to land pixel-perfectly on your own tile (an earlier iteration of this
  logic) was needless friction for a spell that can't target anything else anyway. Three ways to
  confirm the arm-then-cast:
  - **Any LMB click**, anywhere in the game world, while armed.
  - **Ctrl+click from the Special quick-cast slot** — `cast_direct()` self-casts any SELF-target
    spell immediately regardless of `range_tiles`, bypassing the arm step entirely. **Fixed
    footgun**: `player.gd`'s mouse-release handler used to check `pending == grid_pos` (the
    "clicking where you already stand is a no-op move" guard) *before* the Ctrl+Special-slot
    dispatch — since Ctrl+clicking a touch self-buff naturally means clicking your own tile, that
    guard silently ate the cast every time. The Ctrl+Special-slot check now runs first.
  - **Double-press the same ability-bar/quickbar slot** within `Player.DOUBLE_TAP_WINDOW_SEC`
    (0.4s) — `_use_ability_slot()` tracks `_last_ability_slot_idx`/`_last_ability_slot_press_msec`;
    a second press of the same slot on a SELF-target spell cancels any pending arm state and calls
    `cast_direct()` directly, resolving on yourself with no mouse click needed at all. Only
    SELF-target spells trigger this — a double-press on any other spell just re-arms normally
    (`begin_cast()` is idempotent to call twice).
  Sets `Stats.mage_armor_active`, which `recalc_ac()` reads: while true and
  no armor is equipped, AC becomes `13 + DEX` — but only as a fallback below Barbarian/Monk's own
  unarmored-defense formulas (those always win if the character has one). If the caster is
  currently wearing Armor, casting fizzles (slot is still spent, RAW) with a gray log line instead
  of setting the flag. Ends three ways: equipping something into the `"armor"` slot (robes/clothes
  aren't a distinct item type in this codebase, so any Armor-type item ends it) OR equipping a
  Shield (`Item.is_shield` — a Shield lives in `"hand2"`, not `"armor"`, but 5e RAW still counts it
  as worn armor for this purpose — see `scripts/items/CLAUDE.md`'s "Shields"); `GameState.
  long_rest()` also clears it unconditionally. **Both `GameState.equip()` and `move_item()`
  (the drag-and-drop path) carry this check independently** — Armor/Shield items are never
  auto-equipped on pickup (only weapons are), so `move_item()` is the path that actually matters in
  normal play; `equip()`'s own copy exists for the rarer explicit-call cases. All three call
  `recalculate_stats()` afterward. Persisted in `Stats.to_dict()`/`from_dict()`'s
  `"mage_armor_active"` key.
- **Special quick-cast slot**: a single spell (cantrip or leveled), assigned from inside the
  Spellbook overlay (`GameState.special_slot_spell_id`/`set_special_slot()`/`clear_special_slot()`,
  see `scripts/autoloads/CLAUDE.md`), displayed read-only next to Ranged in the Inventory overlay
  (`scripts/ui/CLAUDE.md`), cast with **Ctrl+click** — a direct, one-motion resolve mirroring
  Shift+Ranged rather than the ability bar's two-step arm-then-click. `PlayerSpellcasting.
  cast_direct(spell_id, clicked)` (`scripts/entities/player_spellcasting.gd`) is the dedicated
  entry point: SELF-target spells (Shield) ignore `clicked` and self-cast immediately (same branch
  `begin_cast()` uses); every other target kind sets `_armed_spell_id` directly and calls the
  existing `try_cast_at()` — reuses 100% of the normal cast's range/LOS/slot-consumption logic,
  no duplicated resolution code. Dispatched from `player.gd`'s mouse-release handler, as an `elif`
  alongside the Shift+Ranged branch (`Input.is_key_pressed(KEY_CTRL) and GameState.
  special_slot_spell_id != ""`).
- **Misty Step**: instant teleport via `Entity.set_grid_pos()` (no tween) to a clicked visible
  tile within range.
- **Persistence**: `Stats.to_dict()`/`from_dict()` gained `caster_known_spells`,
  `caster_prepared_spells`, `caster_slot_remaining` (replaces the old single `known_cantrip`
  field). `GameState.from_dict()` calls `_rebuild_spell_ability_bar()` right after
  `player_stats.from_dict()` to reconcile the ability bar against the restored lists.
- **BUGFIX — starting slots were zero**: `StandardSlotPool.remaining` is otherwise only ever
  populated by `on_long_rest()` or a level-up grant — a level-1 Wizard had **zero** spell slots
  from character creation until their first long rest or level-up, contradicting the agreed "2×
  1st-level slots at level 1". `_give_wizard_starting_items()` now seeds `remaining` from
  `max_slots()` directly, same population `on_long_rest()` does.
- **Magic Missile's range is the caster's LIVE field of view, not a fixed tile number**:
  `Spell.range_is_fov: bool` (when true, `PlayerSpellcasting._effective_range()` returns
  `DungeonFloor.FOV_RADIUS + GameState.fov_radius_bonus + GameState.player_stats.darkvision_bonus`
  instead of `spell.range_tiles` — the exact same live formula `dungeon_floor.gd`'s own FOV
  computation uses, so Wild Heart Eagle's +1 FOV radius or Orc/Dwarf darkvision genuinely extend
  how far the spell reaches). Set on `magic_missile` only; every other spell still uses a fixed
  `range_tiles`. `begin_cast()`'s targeting-prompt log line and the out-of-range rejection message
  both read the live value too, not a hardcoded "7 tiles".
- **Magic Missile's detailed damage tooltip**: a dedicated `mmdmg:` meta (`darts`, `rolls`
  `|`-joined per-dart totals, `total`, `final`) replaces the generic `dmg:` meta for this spell —
  `TooltipFormatters.fmt_mmdmg_tooltip()` (`scripts/ui/tooltip_formatters.gd`, dispatched in
  `hud.gd._format_tooltip()`) lists each dart's individual 1d4+1 roll before the summed total.
  **Damage-only, deliberately** — "always hits"/"range = full FOV" do NOT belong on a damage-
  number tooltip (per direct owner correction); that context lives on the spell's own ability-bar
  hover tooltip instead (`Spell.description`, `SpellDb._magic_missile()`), which already states
  both.

### More 1st-level spells (Chromatic Orb, Burning Hands, Witch Bolt)

Three more `LEVELED_SPELL_IDS` entries added on top of the original 5-spell pass above — each
introduces one new mechanic not needed by any earlier spell.

- **Chromatic Orb** (Evocation, `effect_id: "chromatic_orb"`, ATTACK_ROLL, ENEMY, 9 tiles): the
  first **leveled** ATTACK_ROLL spell (every earlier leveled spell was AUTO_HIT or SAVE) — routed
  through a new `SpellEffects.cast_leveled_attack_at_enemy()` / `_resolve_spell_attack_bolt()` pair
  that mirrors `cast_spell()`'s cantrip attack-roll math but also consumes a spell slot.
  `PlayerSpellcasting.try_cast_at()`'s `ENEMY` branch now checks
  `spell.resolution == ATTACK_ROLL` to pick this path over the existing AUTO_HIT
  `cast_leveled_at_enemy()`. Damage type is rolled once per cast from `SpellEffects.
  CHROMATIC_ORB_TYPES` (Acid/Cold/Fire/Lightning/Poison/Thunder) — **not** a fixed `Spell.
  damage_type` (left `""`). **Leap**: if the 3d8 damage roll contains any repeated die value (a
  "doubles" check over the raw `rolls` array `_resolve_spell_attack_bolt()` returns), the orb
  leaps once to a random OTHER alive enemy in the player's current FOV
  (`_pick_chromatic_orb_leap_target()`, `dungeon_floor.get_visible_enemies()` — never the player,
  a companion, or the original target), rolling a completely fresh attack + damage roll of the
  *same* damage type via a second `_resolve_spell_attack_bolt(..., is_leap=true)` call. Leaps only
  once, even if the leap's own damage also rolls doubles — the caller only checks the primary
  bolt's `rolls`, never the leap's. A killing primary hit skips the leap check entirely (no leap
  off a dead target).
- **Burning Hands** (Evocation, `effect_id: "burning_hands"`, SAVE/DEX, TILE, `shape: "cone"`,
  `shape_size: 3`): the first (and so far only) **cone** AoE shape — `Spell.shape` gained a third
  value alongside `""`/`"sphere"`. The cone is self-centered on the caster and only ever
  *aimed* by the clicked/hovered tile — `SpellEffects.cone_tiles(origin, aim_tile, length,
  dungeon_floor)` is the single shared tile-gather. Matches 5e PHB's own cone definition ("the
  cone's width at a given point along its length is equal to that point's distance from you") — a
  true narrowing triangle from the origin, computed via forward/lateral projection onto the aim
  direction (`lateral <= forward * 0.5`), LOS-gated per-tile from the caster — **not** the original
  90°-pie-slice dot-product-angle test (`angle <= 45°`, equivalent to `lateral <= forward`, i.e.
  full width = 2× the point's distance) that this used at first, which read as too wide/blob-shaped
  to look like a cone rather than a genuine wedge.
  called by both the resolver (`_resolve_cone_aoe()`, dispatched from `cast_leveled_at_tile()`) and
  the live preview (`DungeonFloor.show_cone_preview()`, mirroring `show_aoe_preview()`'s pooled-
  Sprite2D convention — see `scripts/world/CLAUDE.md`). Because only the *direction* to the clicked
  tile matters, `PlayerSpellcasting.try_cast_at()` special-cases `spell.shape == "cone"` to skip
  the normal range/LOS gate on the clicked tile entirely (the click can land anywhere, even out of
  range or behind a wall — only its direction from the caster is used). **Never damages the
  caster** (unlike Fireball's sphere) and, matching `_resolve_sphere_aoe()`'s own existing scope,
  doesn't hit a companion either — enemies only. Ignites every `GRASS` tile the cone passes
  through (`DungeonFloor.destroy_grass()`), mirroring Fire Bolt/Thunderclap's flammable-terrain
  side effect.
- **Witch Bolt** (Evocation, `effect_id: "witch_bolt"`, ATTACK_ROLL, ENEMY, 6 tiles, 2d12
  Lightning initial hit): a second concentration spell alongside Blade Ward — casting it while a
  DIFFERENT concentration spell is active calls `GameState.end_concentration()` first (see
  "Concentration (generic mechanism)" above), same recast-refreshes-its-own-duration rule as the
  others. Three `Stats` fields carry the ongoing effect: `witch_bolt_target: Enemy`,
  `witch_bolt_turns: int`, and `witch_bolt_just_cast: bool` (all deliberately **not** serialized in
  `to_dict()`/`from_dict()` — a live `Enemy` node reference can't survive save/load anyway, so the
  bolt just silently ends on load like other mid-floor state). On a non-lethal initial hit,
  `cast_leveled_attack_at_enemy()`'s effect dispatch sets `concentration_spell_id = "witch_bolt"`,
  `witch_bolt_target = target`, `witch_bolt_turns = 10`, `witch_bolt_just_cast = true`. **Tick
  timing (end of turn, not start)**: `player.gd._on_turn_ending()`, connected to
  `TurnManager.player_turn_ending` (emitted from `on_player_action_complete()`, right before the
  enemy phase runs) — fires once per real player action, i.e. at the END of the player's turn, not
  the start of the next one. `witch_bolt_just_cast` makes the very first firing (the casting
  action's own turn-ending event) a no-op instead of ticking, so the first automatic 1d12 lands at
  the end of the turn AFTER the casting turn, matching the intended "the bolt strikes again at the
  end of your later turns" framing rather than immediately at the start of the next round. Each
  real tick calls `SpellEffects.tick_witch_bolt()` — an automatic 1d12 Lightning hit against
  `witch_bolt_target` with **no** attack roll and **no** slot consumption (only the initial cast
  rolls to hit). Ends (clearing all three fields + `concentration_spell_id`) when `witch_bolt_turns`
  reaches 0, the target dies (from the tick itself or otherwise), or `GameState.
  _check_concentration_break()`'s CON check fails on the player taking damage (routes through
  `end_concentration()`, see above). `PlayerActions.do_inspect()`'s enemy status suffix gained a
  `Jolted` entry (`GameState.player_stats.witch_bolt_turns > 0 and witch_bolt_target == enemy`),
  alongside the existing `Frozen Feet`/`Shocked` checks.
- **Scrolls**: all 3 get a `Scroll of <Spell>` cast-scroll (`Item.scroll_spell_id`) per the
  existing "one scroll per spell" convention — see `scripts/items/CLAUDE.md`.

### More 1st-level non-damage spells (Expeditious Retreat, False Life, Fog Cloud)

Three more `LEVELED_SPELL_IDS` entries, all non-damage. 5e's real class list for these is
Sorcerer/Warlock/Wizard, Sorcerer/Wizard, and Druid/Ranger/Sorcerer/Wizard respectively — this
codebase only has a Wizard caster, so `class_list` stays `["WIZARD"]` like every other spell.

- **Expeditious Retreat** (Transmutation, `effect_id: "expeditious_retreat"`, AUTO_HIT, SELF,
  free action, **Concentration**, up to 100 turns): a third concentration spell alongside Blade
  Ward/Witch Bolt, reusing `Stats.concentration_spell_id` (`"expeditious_retreat"`) — casting it
  while a different concentration spell is active breaks that one first, same recast-refreshes-
  its-own-duration rule as the other two. **Effect**: once per real turn, the player's first move
  doesn't cost the turn — `Player._try_move()`'s free-action revert pattern (same mechanism
  Battlefield Expert R3's free side-step uses: `_reverted_this_round = true;
  TurnManager.revert_to_waiting()` instead of `on_player_action_complete()`), gated on
  `stats.expeditious_retreat_turns > 0 and not _expeditious_retreat_move_used_this_turn`.
  `_expeditious_retreat_move_used_this_turn: bool` resets in `_on_turn_started()`'s
  `if not came_from_revert:` block alongside every other per-round cap. **Scope limitation**: only
  wired into `_try_move()` (single-step WASD movement), same documented gap as Battlefield
  Expert R3 — the queued-path/chase-to-target movement functions don't check it. Duration ticks
  in `_on_turn_started()` exactly like Blade Ward's `blade_ward_turns` (100-turn counter, clears
  `concentration_spell_id` at 0).
- **False Life** (Necromancy, `effect_id: "false_life"`, AUTO_HIT, SELF, action, instantaneous):
  `SpellEffects.cast_leveled_self()`'s `"false_life"` branch rolls `spell.dice_count`d`spell.
  dice_sides` (2d4) `+ 4` and sets `Stats.temp_hp = maxi(temp_hp, total)` — **replace, not
  stack**, matching 5e RAW (a False Life recast only helps if the new roll is bigger) and this
  codebase's existing temp-HP convention (Natural Sleeper R2, Overheal Shield). Emits
  `GameState.player_hp_changed` directly (needed for the HUD's temp-HP strip to refresh — no
  other signal covers a temp_hp-only change).
- **Fog Cloud** (Conjuration, `effect_id: "fog_cloud"`, AUTO_HIT, TILE, `shape: "sphere"`,
  `shape_size: 2`, range 12 tiles, **Concentration**, up to 100 turns): the fourth concentration
  spell, `"fog_cloud"`. Unlike Blade Ward/Witch Bolt (a self-buff / a live Enemy reference), the
  cloud is a bare **position + radius** — `GameState.fog_cloud_pos: Vector2i`/
  `fog_cloud_radius: int` (`(-1,-1)` = none active), since it needs to Blind whoever is standing
  in it, player or enemy, not a single caster/target pair. `SpellEffects._resolve_fog_cloud()`
  (dispatched from `cast_leveled_at_tile()`, intercepting before the generic `shape == "sphere"`
  damage path so it never routes into `_resolve_sphere_aoe()`) sets `stats.concentration_spell_id
  = "fog_cloud"`, `stats.fog_cloud_turns = 100`, `GameState.fog_cloud_pos = center`,
  `fog_cloud_radius = spell.shape_size` — no damage, no save roll. `GameState.
  is_in_fog_cloud(pos) -> bool` (Euclidean disc, same distance check `_resolve_sphere_aoe()`/
  `show_aoe_preview()` use) is the single query every ADV/DISADV chokepoint reads:
  - **Attacks against a Blinded creature have Advantage**: `PlayerVfx.has_advantage(enemy)`
    (`scripts/entities/player_vfx.gd`) gained an `is_in_fog_cloud(enemy.grid_pos)` branch — since
    this one function already backs ADV at all 6 player attack-roll sites (melee/cleave/
    offhand/OA/ranged/spell cantrip — see "Combat rolls" above), this single edit covers "player
    attacks a blinded enemy" everywhere for free. Symmetrically, `Enemy._resolve_attack_roll()`
    gained `extra_adv`/`extra_disadv` params (defaults `false`, so every pre-existing call site is
    unaffected); `_attack_player()`/`_attack_companion()` pass `is_in_fog_cloud(target.grid_pos)`
    as `extra_adv` — an enemy attacking a Blinded player/companion also gets Advantage.
  - **A Blinded creature's own attacks have Disadvantage**: the player's own
    `is_in_fog_cloud(grid_pos)` check was added inline to the `disadv_count` block at all 8 player
    attack-roll sites that build one (`player.gd`'s `_bump_attack()`/`_resolve_cleave_attack()`/
    `_resolve_offhand_attack()`/`resolve_opportunity_attack()`, `PlayerRanged.ranged_attack()`,
    both `spell_effects.gd` attack-roll resolvers — cantrip `cast_spell()` and leveled
    `_resolve_spell_attack_bolt()`, and `PlayerThrowTool._throw_weapon()`) — no shared
    disadvantage chokepoint exists the way `has_advantage()` covers ADV, so each site got its own
    one-line addition. Symmetrically, `Enemy._resolve_attack_roll()`'s `extra_disadv` param is fed
    `is_in_fog_cloud(grid_pos)` (the ATTACKING enemy's own position) from both `_attack_player()`
    and `_attack_companion()` — a Blinded enemy's own attacks also suffer Disadvantage.
  - **NOT implemented** (documented simplification, matching Mind Sliver's "no separate turn-
    expiry timer" precedent): "automatically fails checks that require sight" — there's no single
    concrete mechanic in this codebase that maps onto "a sight check" the way ADV/DISADV on attack
    rolls does, so this clause of the Blinded condition is a no-op. "Ends early if a strong wind
    disperses it" — no such spell/ability exists yet to trigger it.
  Duration ticks in `_on_turn_started()` like Blade Ward, but ALSO calls `GameState.
  clear_fog_cloud()` at 0 (unlike Blade Ward/Witch Bolt, which have nothing beyond their own Stats
  field to clear). **Explicitly cleared on floor descent** (`GameState.advance_floor()`) — unlike
  Light (whose lit `Item` reference) or Witch Bolt (whose target `Enemy` reference) naturally
  invalidate themselves when the floor reloads, a bare position has nothing that would otherwise
  stop it from silently blinding whoever stands at those same coordinates on the next floor.
  **Visual**: `DungeonFloor._update_fog_cloud_visual()` (`scripts/world/dungeon_floor.gd`, called
  every `update_fog()`) tints the cloud's tiles with a persistent gray overlay — pooled `Sprite2D`s
  + shared 1×1 white texture, same convention as the Light glow (see `scripts/world/CLAUDE.md`).
  Not LOS-filtered (a raw disc, matching `is_in_fog_cloud()`'s own check exactly) and does NOT
  affect FOV/visibility (no shadowcast union into `_visible_tiles`, unlike Light) — it's a status
  zone, not a light source.

## Monk class
Stats: DEX=16, WIS=14, CON=12, STR=10 (d8 HD, 8+CON HP). Check proficiencies: STR + DEX. Weapon proficiency: intended to be simple weapons + martial weapons with the light property, but `Stats.proficient_simple_weapons`/`proficient_martial_weapons` are not yet set in `apply_class_defaults()` for Monk (TODO — currently only wired up for Barbarian). No armor training (any armor → DISADV on STR/DEX checks/saves + DISADV on attacks; TODO: enforce). Starting abilities (slot 0–1 of ability bar):
- **Unarmored Defense** (passive, ability_id `"unarmored_defense_monk"`): AC = 10 + DEX + WIS while wearing no armor. Handled in `Stats.recalc_ac(has_armor_equipped)`.
- **Martial Arts** (passive, ability_id `"martial_arts"`): Unarmed strikes use DEX for attack AND damage. Damage die = `Stats.martial_arts_die_sides` (1d6 → 1d8 at lvl 5 → 1d10 at lvl 11 → 1d12 at lvl 17). Each unarmed attack ends the turn normally. Both main attack uses `_bump_attack()` with `is_monk_unarmed = true`.

**Monk level-up features** (applied in `GameState._apply_monk_level_features(level)`, called alongside `_apply_barbarian_level_features()` from `gain_exp()`):
- **Level 4 — DEX +2**: `player_stats.dexterity += 2`, `recalculate_stats()` applied.
- **Levels 5/11/17 — Martial Arts die upgrade**: updates `martial_arts` ability description; die is auto-computed by `Stats.martial_arts_die_sides`.
