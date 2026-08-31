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
**Sprite**: a single static `Sprite2D` (not `AnimatedSprite2D` — no idle/run states), built in
`_ready()`. Checks `res://sprites/characters/enemies/<animal_name>/idle_1.png` first (real art,
shown at natural colors — animals live under `enemies/`, see root CLAUDE.md's Sprite Assets
section) and falls back to `classes/Wizard/idle_1.png` tinted green (`Color(0.5, 1.2, 0.5)`,
"friendly but no dedicated sprite yet") when that folder doesn't exist. Currently only **Bear**
(Wild Heart's Companion R3, `sprites/characters/enemies/Bear/`) has real art — Squirrel/Boar (R1/R2) still
render as the green-tinted Wizard placeholder until their own folders show up; no code change
needed when they do; a future "Bear" `ENEMY_POOL` stat block could reuse the same folder.

---

## Adding a new enemy
1. Extend `Entity`, implement `take_turn()` and `_setup_animations()`
2. `TurnManager.register_enemy(self)` in `_ready()` (not in `configure()`)
3. Add entry to `DungeonFloorData.ENEMY_POOL` (`scripts/world/dungeon_floor_data.gd`); add `idle_fmt`/`run_fmt` keys if sprite naming is non-standard
4. If boss: add to `DungeonFloorData.BOSS_POOL`, set `is_boss = true`

**Sprite sheets + random color variant** (`giant_rat`, first/only user): only `"idle"`/`"run"` are
ever played for any enemy — no engine plumbing exists for an attack/death/hurt/sniff animation
clip today (those events are represented by log lines, damage floaters, and a modulate-flash tween
instead), so a new enemy's art only needs those two states wired up regardless of what else the
source asset ships. If the art is a **sprite sheet** (all frames of one state baked into a single
PNG, sliced via `Rect2` regions) rather than Wogol's one-file-per-frame convention, and/or the
enemy should randomly pick one of several cosmetic recolors at spawn, author these opt-in
`ENEMY_POOL` keys instead of `idle_fmt`/`run_fmt` (absent = today's unaffected per-frame-file path):
`"sprite_variants": ["Gray","Brown","White"]` (capitalized color names — matched against a
lowercase `{folder}/{variant}/` subfolder holding plain `{state}.png` sheet files, e.g.
`Rat/gray/idle.png` — see `Enemy._setup_sheet_animations()`), `"sprite_frame_size": {"w","h"}` (per-frame px size within the
sheet, default 64×64), `"sprite_scale"` (float, default `1.0` — most other enemies' native frame
size already matches the 16px tile grid, so a larger-native-resolution sheet needs scaling down;
`giant_rat` uses `0.35` for its 64×64 frames), `"sprite_offset"` (`{"x","y"}`, default the existing
`(0,-8)`). The variant is picked with **plain global `randi()`, not `Rng`** — which color renders
is purely cosmetic and must never perturb the seeded `Rng`/`_pop_rng` streams other systems rely on
for reproducible runs (`scripts/autoloads/CLAUDE.md`'s "cosmetic jitter stays global" rule).
`Enemy._setup_sheet_animations()`/`_add_anim_sheet()` (`enemy.gd`) is the generic implementation —
reusable for any future recolor-variant enemy, not Rat-specific code.

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
| `"cr"` | float | Challenge rating. **Drives CR-budgeted spawning** (`DungeonFloor._pick_cr_budgeted_enemies()`, see `scripts/world/CLAUDE.md`'s "Spawning" section and `docs/architecture/cr-budgeted-spawning-design.md`) — floor-linear scaling in `_apply_stats()` is still unchanged and still the only within-band difficulty knob; CR only decides which enemies spawn together, not how strong each one is. Default `0.25` when absent. |
| `"creature_type"` | string | `"Undead"`/`"Fiend"`/`"Beast"`/... flavor tag, stored on `Enemy.creature_type`. No mechanical effect by itself (reserved for a future type-conditional damage rule or talent synergy). |
| `"size_category"` | string | D&D size CATEGORY — `"Tiny"`/`"Small"`/`"Medium"`/`"Large"`/`"Huge"`/`"Gargantuan"`, stored on `Enemy.creature_size`. Distinct from the physical `"size":{"w","h"}` footprint below — a 1x1-footprint enemy can still be authored as any category (`PlayerHalfling.is_larger_than_halfling()` also treats footprint > 1 tile as large regardless of this key, so Ogre/Spider work even before/without it). Default `"Medium"` when absent. Sole consumer today: Halfling's Nimbleness ability (`scripts/entities/player_halfling.gd`), which treats any enemy ranked strictly above Small (i.e. Medium+) as a valid slip-through target. **Authored so far** (direct owner dictation): `quasit` Tiny Fiend, `imp` Tiny Fiend, `goblin_minion`/`goblin_warrior`/`goblin_archer` Small Fey, `giant_rat` Small Beast, `orc_warrior`/`orc_shaman`/`masked_orc` Medium Humanoid, `skeleton` Medium Undead, `ogre`/`spider` Large (alongside their real 2x2 footprint), `big_demon`/Bearded Devil Medium Fiend (see "Bearded Devil" below). **Still unauthored, running on the "Medium" default** (not yet dictated — owner's own words: "zbytek uděláme až budou mít statblocky"): `necromancer`, `zombie`, `wogol`, `pumpkin_dude`. |
| `"mods"` | `{"str":0,"dex":0,"con":0,"int":0,"wis":0,"cha":0}` | Real ability-score modifiers. **Presence of this key switches the enemy's attack roll AND every `resist_check_detailed()` call to the mod+proficiency formula, replacing the legacy `floor_num/3` bonus — never both.** Absent = 100% unchanged legacy behavior (also true of the older `str_mod`/`con_mod`/`dex_mod`/`wis_mod`/`int_mod` single-stat keys, which still work as a fallback and do NOT trigger the mods formula). |
| `"prof_bonus"` | int | Only read when `"mods"` is present. Default derived from `cr`: `2 + max(0, ceil(cr)-1)/4`. |
| `"check_profs"` | `["str","con",...]` | Only read when `"mods"` is present — which of the 6 stats add `prof_bonus` to `resist_check_detailed()` (contested checks: Topple, Push, Grip of the Forest, SAVE cantrips/spells). |
| `"attack_prof"` | bool | Only read when `"mods"` is present. Whether `prof_bonus` applies to the attack roll too. Default `true`. |
| `"damage_resistances"` / `"damage_immunities"` / `"damage_vulnerabilities"` | `Array[String]` | ×0.5 / ×0 / ×2, priority immunity > vulnerability > resistance, applied in `Enemy.take_typed_damage()`. Legacy `"resist"`/`"vuln"` keys still work as a fallback for `damage_resistances`/`damage_vulnerabilities` (no immunity equivalent existed before). |
| `"condition_immunities"` | `Array[String]` | A **separate axis** from damage immunity — blocks the status COUNTER from ever being set. Vocabulary: `"slowed"`/`"rooted"`/`"prone"`/`"forced_move"`/`"poisoned_condition"`/`"incapacitated"` (real, wired — see `Enemy.apply_status()`, `DungeonFloor.force_move_entity()`/`resolve_push()`, and "Conditions" below); `"poisoned"`/`"burning"`/`"bleeding"` (reserved — `apply_status()` sets the matching `Stats` counter but nothing ticks it for enemies yet, since no current effect poisons/burns/bleeds an enemy). |
| `"senses": {"sight_bonus": N}` | dict | Offset **relative to** `Enemy.FOV_RADIUS` (default 5), applied in `_sight_range()` — e.g. `+1` for darkvision (6 total), `+2` for superior darkvision (7 total), `-1` for weak sight. Absent = `0` (flat `FOV_RADIUS`). Deliberately relative, not absolute, so changing the base `FOV_RADIUS` later doesn't require re-touching every authored enemy. `darkvision`/`blindsight` sub-keys are reserved, not read. |
| `"speed"` | `{"moves": N, "per": M}` | Movement-speed scaling (see "Movement speed scaling" note below the table) — how many of every `per` real turns this enemy actually gets to move. Absent = `{"moves": 1, "per": 1}`, i.e. today's unconditional 1-move-every-turn, unchanged for every entry that doesn't author it. `Enemy._tick_speed_gate()` (called every real turn from `take_turn()`, a Bresenham-style integer accumulator, no floats) sets `_moves_this_turn`; `_decide_action()` treats `_moves_this_turn <= 0` exactly like `rooted_turns` (skip movement, still attack if already adjacent), and `_act_toward()` loops `maxi(1, _moves_this_turn)` steps for a `moves > per` (above-baseline speed) entry, re-checking attack range after every step. Reference: Zombie's 20 ft speed → `{"moves": 2, "per": 3}` (below baseline); Ogre's 40 ft speed → `{"moves": 4, "per": 3}` (above baseline — the same mechanism works in either direction). |
| `"multiattack"` | `[{"name","count","dmg_min","dmg_max","damage_type"}, ...]` | Each sub-attack resolves as its own independent roll/floater/log line via `_attack_player()`/`_attack_companion()`'s `sub` param — same one-log-line-per-swing convention as the player's Off-hand/Nick bonus attacks. Absent = today's single top-level-stats attack. |
| `"abilities"` | `[{"id","cooldown"\|"uses_max"\|"recharge","range","long_range","dmg_min","dmg_max","damage_type","status","turns"}, ...]` | Ranged damage(+optional status) ability, picked in `_decide_action()` over melee approach whenever ready, in range, LOS'd, AND the target isn't already melee-adjacent (snipe-then-melee, matching the Skeleton worked example in the design doc). Timer is exactly one of `cooldown` (flat turn counter), `uses_max` (per-life budget), or `recharge` (d6 roll ≥ N re-arms it, D&D "Recharge 5-6" style) — combining two on one ability is an authoring error. Optional `long_range` extends how far the ability can be picked from at all (`_pick_ready_ability()`'s reach check uses `long_range` if present, else falls back to `range`); a shot landing beyond `range` but within `long_range` rolls with Disadvantage (`Enemy._ability_is_long_shot()` → the `long_shot` param threaded through `_execute_ability()` → `_attack_player()`/`_attack_companion()` → `_resolve_attack_roll()`'s `extra_disadv`), the same weapon-style normal/long split as `PlayerRanged.ranged_shot_disadvantage()`. Absent `long_range` = flat cutoff at `range`, unchanged old behavior (e.g. Goblin Archer's plain `attack_profile`, not this key at all). Execution reuses `_attack_player()`/`_attack_companion()` wholesale (abilities and multiattack sub-attacks share the exact same damage shape) plus an optional `GameState.apply_player_status()` call if `"status"` is set. No per-ability custom code needed for this generic ranged-damage shape; a truly bespoke ability (summon, aura) still needs a `match ability_id:` special case added to `Enemy._execute_ability()`. Reference: Skeleton's Shortbow (`range: 8`, `long_range: 32`). |
| `"traits"` | `[{"id":"regeneration","amount":N,"shutoff_types":[...]}]` or `[{"id":"undead_fortitude","dc_base":N}]` | The two traits the design doc specs in full are implemented generically: **regeneration** heals `amount` HP at the top of a real turn unless a `shutoff_types` damage type hit last round (`Enemy._tick_regeneration()`, hooked from `take_turn()`); **undead_fortitude** intercepts a would-be-lethal hit with a CON check vs `dc_base + damage`, once per life, surviving at 1 HP (`Enemy.take_typed_damage()`'s death branch) — **except** when the killing blow's damage type is `"Radiant"` or it was a critical hit, matching the real D&D trait text exactly (`Enemy.take_typed_damage(amount, damage_type, is_crit: bool = false)`'s 3rd param, threaded through from every attack-roll call site that has a local `is_crit` — melee/cleave/off-hand/OA in `player.gd`, ranged in `player_ranged.gd`, the two ATTACK_ROLL cantrip/spell paths in `spell_effects.gd`; SAVE-resolution and auto-hit spells have no crit concept and pass the default `false`). A third `"id"`, **aggressive** (no payload — `Enemy._has_trait(id)` is a bare presence check, not a per-trait dispatch table entry), grants +1 movement step on any turn where the enemy can see its target: wired at `_execute_action()`'s `"act_toward"` case (`bonus_moves = 1 if (intent.can_see and _has_trait("aggressive")) else 0`, passed into `_act_toward(target, bonus_moves)`) rather than through `_tick_speed_gate()`/`"speed"`, since it's conditional on visibility, not a flat per-turn ratio — it stacks on top of whatever `"speed"` already grants. Never adds a second attack (D&D's own text only grants the movement, not another swing) — `_act_toward()` re-checks attack range after every step of a multi-step turn and attacks (and stops moving) the instant it's in range, so "move + attack" falls out for free, and "attack + move"/"just attack" (already adjacent at decision time) never call `_act_toward()` at all, going straight through the normal `_act_toward_or_ability()` → attack dispatch with no extra movement spent. A fourth `"id"`, **nimble_escape** (no payload), triggers off a landed MELEE hit rather than off a trait check: `Enemy.on_melee_hit(attacker)` (called only from the melee-only player attack sites — `_bump_attack()`/`_resolve_cleave_attack()`/`_resolve_offhand_attack()`/`resolve_opportunity_attack()` in `player.gd`, guarded on `actual > 0` — NOT ranged/thrown/spell hits) rolls `escape_turns = Rng.range_i(1, 5)`, stores `escape_from = attacker`, and immediately `await`s a single `_flee_from(attacker)` step right there as a reaction — still within the attacker's own turn, before `TurnManager` ever hands control to this enemy — so the goblin visibly flinches one tile away from the very swing that hurt it instead of standing still to eat a follow-up hit on the same beat its escape starts. Reuses `_flee_from()` completely as-is (same no-OA-provoked step, `provokes_oa=false`); if it's cornered (wall/blocked tile behind it) `_flee_from()` just returns `false` without moving — no separate handling needed, it stays put for this reaction and still starts its normal (possibly cornered-fight) flee on its own next turn. **Only fires on this enemy's very first damage instance this life**: `Enemy._hits_taken` (incremented in `take_typed_damage()` on every `actual > 0` instance, any source — melee, ranged, spell, DoT tick) is already at its post-this-hit value by the time `on_melee_hit()` runs (damage is always applied before the `on_melee_hit()` call at every site above), so `_hits_taken > 1` means this melee hit landed on an already-damaged goblin and `on_melee_hit()` no-ops instead of arming the flee — direct owner request: a goblin already proven vulnerable to ranged (e.g. shot once before closing to melee) gains nothing by fleeing melee range, since the player can just shoot it while it runs. `_decide_action()` checks `escape_turns > 0` before every other behavior branch (including an adjacent target — a fleeing goblin doesn't stop to swing): decrements the counter and returns a `{"type": "flee", "target": escape_from}` intent for every decrement that leaves `escape_turns > 0` — EXCEPT the turn the decrement brings it to exactly `0` (the flee just wore off): on that turn, if the pool's own `"thrown_weapon"` dict sets `"flee_only": true`, that weapon hasn't been used yet, and the flee target is still 2+ tiles away and within throw range/LOS, a one-shot `"throw_weapon"` intent (a parting shot, NOT thrown mid-flee) is returned instead of falling through to the normal chase/attack decision (Goblin Minion's Dagger — see the `"thrown_weapon"` row below; deliberately does NOT fire off a ranged/spell hit, only off this same melee-triggered `escape_turns` state, so a Fire Bolt hit never makes it throw). If the target IS adjacent by then, or the throw doesn't line up, this same "just wore off" turn instead falls straight through to the ordinary decision logic below (chase/attack — no wasted turn). Every other tick with `escape_turns > 0` still resolves via `_flee_from()` — a single greedy step directly away from the attacker (`_preferred_steps()` on the negated delta, no BFS fallback), returning whether it actually moved. If cornered (no walkable tile directly away — wall or blocked), `_execute_action()`'s `"flee"` case has it attack the fled-from entity instead of idling, but only if still in range (a trapped animal turning to fight rather than pathing the long way around). Its own `_move_step()` call passes `provokes_oa = false` (a new 3rd param, default `true` for every other caller) so fleeing never triggers the player's/companion's Opportunity Attack hook, matching the trait's own "doesn't provoke opportunity attacks" text. Any other `"id"` is inert (no dispatch exists yet — add one to `take_typed_damage()`/`_tick_regeneration()`/`_has_trait()`-style check/a new hook when a concrete monster needs it). A fifth `"id"`, **pack_tactics** (no payload), grants Advantage on this enemy's own attack roll whenever another enemy (any `Enemy`, not just the same species) is within 5 ft (Chebyshev 1 tile) of the target AND that other enemy is awake (`behavior != Behavior.SLEEPING` — the closest analogue this engine has to 5e's "incapacitated"; no other enemy status here, e.g. `rooted_turns`, maps to a real incapacitating condition, so SLEEPING is the only exclusion). Checked inline in both `_attack_player()` and `_attack_companion()` right where the existing `fog_adv` local is computed, OR'd into the same `extra_adv` param passed to `_resolve_attack_roll()` — no schema or signature changes needed, same "small conditional local, computed at the call site" shape as `fog_adv`/`terrain_disadv`. Reference: `giant_rat`'s Pack Tactics. References: `zombie`'s Undead Fortitude (`dc_base: 5`), `orc_warrior`'s Aggressive, `goblin_warrior`/`goblin_archer`'s Nimble Escape. |
| `"legendary_resistances"` | int (BOSS_POOL only) | Per-life counter (`Enemy.legendary_resistances_remaining`) consumed inside `resist_check_detailed()`: a roll that would fail is forced to pass instead, logged gray. Not currently authored on any `BOSS_POOL` entry — the floor-5 boss (`big_demon`/Bearded Devil, see "Bearded Devil" below) doesn't have Legendary Resistance in its real stat block. |
| `"on_hit_save"` (nested inside a `"multiattack"` sub-entry) | `{"stat","dc","status","turns"}` | A landed hit rolls a player save (`"stat"`: `"con"`/`"wis"`) vs `"dc"` BEFORE applying `"status"`/`"turns"` (via `GameState.apply_player_status(status, turns, dc)`) — a fail-only version of the plain `"status"`/`"status_turns"` row below, which applies unconditionally. First user: Bearded Devil's Beard (see "Bearded Devil" below). Player-only (no Companion equivalent). |
| `"infernal_wound"` (nested inside a `"multiattack"` sub-entry) | `{"dc"}` | Bearded Devil's Glaive only — see "Bearded Devil" below for the full escalating-DoT mechanism (`Stats.infernal_wound_active`/`infernal_wound_dice`). |
| `"passive_perception"` | int | **Implemented** — the Stealth-vs-Passive-Perception check's static DC (see "Stealth & Surprise Attacks" below). Authored value always wins; absent, `Enemy._apply_stats()` derives `10 + stats.wis_modifier()` from the now-resolved WIS score, so every enemy has a usable value even before the full bestiary is annotated. Currently authored on `goblin_minion`/`goblin_warrior`/`goblin_archer` (all 9, shared goblin-family WIS 8), `skeleton` (9, WIS 8), `zombie` (8, WIS 6), `orc_warrior` (10, WIS 11), and `ogre` (8, WIS 7); every other pool entry runs on the derived default (WIS 10 → PP 10) until annotated for flavor — safe/playable either way. |
| `"thrown_weapon"` / `"unarmed_fallback"` | `{"name","dmg_min","dmg_max","damage_type","range","icon","drop_die_min","drop_die_max","weapon_category","is_finesse","is_light","weapon_mastery","drop_uses_max","drop_chance","random_uses","flee_only"}` / `{"name","dmg_min","dmg_max","damage_type"}`, optionally + `"attack_stat"` | A **generic, reusable pair** — originally authored for Goblin Minion's Dagger, now also used by Orc Warrior's and Ogre's Javelins (same underlying code, different pool values; Ogre's Javelin reuses Orc Warrior's own `"range": 3` verbatim). Two mutually-exclusive trigger modes, selected by the optional `"flee_only"` key (default `false`): **opener mode** (Orc Warrior's Javelin, `"flee_only"` absent) — once NOT escaping (see Nimble Escape below), the enemy is actively pursuing (`behavior in [CHASING, SEARCHING]` — an unaware SLEEPING/STATIONARY/ROAMING enemy never throws, it has to have noticed the target first), and the target is 2+ tiles away (not adjacent) and within `"range"` (default 4), `_decide_action()` returns a one-shot `"throw_weapon"` intent instead of the normal chase-then-melee dispatch. **Flee-only mode** (Goblin Minion's Dagger, `"flee_only": true`) — the opener check above is skipped entirely; instead the throw is offered only on the single turn Nimble Escape's flee state (`escape_turns`, itself only ever triggered by a landed MELEE hit) WEARS OFF (decrements to exactly `0`), as a one-time parting shot — NOT on any turn while still actively fleeing, and only if the target still isn't adjacent by then (adjacent = it just stabs instead via the normal fall-through decision logic). A Goblin never throws its dagger unless it was hit in melee first (a ranged/spell hit like Fire Bolt never sets `escape_turns`, so it never reaches this branch at all) — see the `"traits"` row's `nimble_escape` entry above for the exact condition. Either way, once triggered — `Enemy._execute_thrown_weapon_attack()` resolves it via `_attack_player()`/`_attack_companion()` with `long_shot=true` forcing Disadvantage (reusing that param purely for its Disadvantage side effect, not its normal normal/long-range meaning), sets `Enemy._thrown_weapon_used = true` (a per-life one-shot flag), and — regardless of whether the throw actually landed, matching the original Goblin Minion behavior — registers the target with `DungeonFloor.queue_thrown_weapon_drop(target, item, chance)` for a per-entry `"drop_chance"` (default `0.5`). `"unarmed_fallback"`: once `_thrown_weapon_used` is true, `_attack_target()` dispatches every subsequent attack here instead of the pool's `"multiattack"` — but **only when the thrown weapon and the melee weapon are the same item** (compared by `"name"`: `thrown_weapon.name == multiattack[0].name`). Goblin Minion's Dagger is both its thrown AND its only melee weapon, so losing it really does mean bare-fisted forever. Orc Warrior's Javelin and Ogre's Javelin are each a SEPARATE weapon from their Greataxe/Greatclub — once thrown, `_attack_target()` finds the names don't match and keeps dispatching to the normal `"multiattack"` entry in melee, exactly as if the Javelin had never been thrown. (Bugfix: this used to check only `_thrown_weapon_used`, so an Orc/Ogre that had already thrown its Javelin punched with Fists forever even once adjacent with its Greataxe/Greatclub still notionally in hand — nonsensical, since throwing a side weapon shouldn't disarm the main one. Fixed by adding the same-weapon-name comparison.) Its optional `"attack_stat"` key (both enemies' Fists use `"str"` regardless of their own attack-stat default) is a per-sub-attack override read by `Enemy._attack_bonus_for(sub)`, which every `_attack_player()`/`_attack_companion()` call now threads into `_resolve_attack_roll()`'s `attack_bonus_override` instead of always passing `-9999`/falling back to the enemy-wide `attack_profile.attack_stat` default — falls back to the normal `_attack_bonus()` for every pre-existing multiattack/ability entry that doesn't set it. **The dropped `Item`** is built generically by `Enemy._build_thrown_weapon_item(wpn)` from the `"thrown_weapon"` dict's own fields (`"icon"`, `"drop_die_min"`/`"drop_die_max"` — the raw weapon's die, distinct from `dmg_min`/`dmg_max`, which are the enemy's already-ability-mod-inflated attack numbers — `"weapon_category"`, `"is_finesse"`, `"is_light"`, `"weapon_mastery"`, `"drop_uses_max"`), every field defaulting to whatever the original hardcoded Dagger builder used (so Goblin Minion's pool entry, which sets none of these, reproduces its exact original output) — a new consumer is expected to set them all explicitly. `"random_uses"` (default `false`) picks between an already-full drop (Goblin's Dagger) and a randomly-worn-down one (`Rng.range_i(1, drop_uses_max)` — Orc's Javelin, "already used"). **Recovering the thrown weapon**: `DungeonFloor._pending_thrown_weapon_drops`/`_resolve_pending_thrown_weapon_drops()` (`scripts/world/CLAUDE.md`) — checked once on the player's next real turn after the thrower dies (`Enemy.die()` queues it with its own `_thrown_weapon_lodged_chance`, `TurnManager.player_turn_started` resolves it), to drop a normal pickupable `Item` at wherever the throw's target currently stands. Unconditional on the throw actually having landed — `_attack_player()`/`_attack_companion()` don't return their hit result, so gating strictly on a hit would need a broader refactor; documented simplification, still true for both enemies using this mechanic today. **Dropping the weapon unused**: if an **opener-mode** thrower (`"flee_only"` absent — Orc Warrior/Ogre, not Goblin Minion's flee-only Dagger) dies with `_thrown_weapon_used` still `false` — killed before it ever got an opening to throw, or the target was already adjacent the very first time it could act, so the opener's own "2+ tiles away" condition never fired and it went straight to melee — `Enemy.die()` drops the Javelin at the death tile anyway, guaranteed (no `drop_chance` roll, no next-turn delay, unlike the lodged-in-target recovery above, since this copy never left the enemy's hand), but with only 2 of its `drop_uses_max` uses rather than a fresh full stack (same "already seen some wear" convention as `random_uses`'s dropped-weapon uses). |
| `"speed_ground"` / `"speed_flying"` | both `{"moves","per"}` | Imp-only pair: `_tick_speed_gate()` picks `"speed_flying"` while CHASING/SEARCHING (pursuing) and `"speed_ground"` otherwise, instead of a single flat `"speed"`. Requires BOTH keys to be present — an entry with only one, or neither, falls back to the legacy single `"speed"` key (or the `{1,1}` default) unaffected. |
| `"extra"` (nested inside a `"multiattack"` sub-entry) | `{"dmg_min","dmg_max","damage_type"}` | A second, independent typed damage instance dealt on the SAME hit as its parent sub-entry (one attack roll, two damage numbers/floaters/log segments) — Imp's Sting (1d6+3 Piercing weapon dmg + 2d6 Poison venom). Mirrors the player-side Judgement Day/Fireball-friendly-fire "one hit, multiple damage types" convention. `_attack_player()` gives it its own `edmg:` tooltip segment; `_attack_companion()` folds it into the one flat damage number instead (Companion has no per-type tooltip system at all, pre-existing simplification). |
| `"invisibility"` | `{"cooldown","duration"}` | Imp-only. While pursuing (CHASING/SEARCHING) and not yet adjacent, with the cooldown ready and not already invisible, `_decide_action()` returns a one-shot `"cast_invisibility"` intent (costs the turn) instead of closing distance. See "Invisibility" below — shared mechanism with the player-castable level-2 spell of the same name. |
| `"web"` | `{"cooldown","range","save_dc"}` | Spider-only, Player-only target. Ranged, non-damage, SAVE-based restraint — see the "Spider" section below for the full mechanism. |
| `"scare"` | `{"range","save_dc"}` | Quasit-only, Player-only target. Ranged, non-damage, WIS-SAVE-based fear effect, 1/life (no `"cooldown"` — see the "Quasit" section below for the full mechanism, including the real Frightened condition it applies). |

**Traits `"magic_resistance"` / `"shape_shift"`** (presence-only like `"aggressive"`; `magic_resistance` is Imp/Quasit today, `shape_shift` is generalized — any entry can opt in with its own form list):
- **`magic_resistance`**: Advantage on saving throws against spells — `Enemy.resist_check_detailed()` gained a `magical: bool = false` param; when true AND this trait is present, the d20 is rolled with Advantage (max of two rolls). Threaded through every SAVE-resolution spell's enemy-facing call in `spell_effects.gd` (Ray of Frost, Toll the Dead, Mind Sliver's own save, Thunderclap, Fireball) — **not** weapon-mastery saves (Push/Topple/Grip of the Forest/Branching Strike), which aren't spells and never pass `magical=true`.
- **`shape_shift`**: while CHASING and unseen by the player THIS turn (out of FOV, or the enemy is Invisible — `_tick_shape_shift()`'s `unseen` check), 50% chance per eligible turn to secretly transform into a random small-critter form — no turn cost, and a further 50% chance to already be shape-shifted at spawn (`_ready()`). **Form list is per-entry**: `Enemy._shape_shift_forms()` reads the pool's own `"shape_shift_forms"` array if authored, else falls back to `Enemy.SHAPE_SHIFT_FORMS = ["rat","raven","spider"]` (Imp's original set) — Quasit authors its own `["bat","centipede","toad"]` (see "Quasit" section below). Tracked in `_shifted_form`. Reverts to the true form instantly on taking any actual damage (`take_typed_damage()`'s revert check — an immune 0-damage hit does NOT revert it). **Visually wired for Rat and Spider** — every `_shifted_form` change (spawn roll, `_tick_shape_shift()`'s mid-chase roll, or the damage-revert back to `""`) calls `Enemy._refresh_shape_shift_visual()`, which swaps `$AnimatedSprite2D.sprite_frames` to the `Enemy.SHAPE_SHIFT_SPRITES[form]` entry (Rat: reuses `sprites/characters/enemies/Rat/<Gray|Brown|White>/{idle,run}.png`, same random-recolor convention as Giant Rat's own `sprite_variants`; Spider: `sprites/characters/enemies/Spider/{idle,run}.png`, sliced from the single `Cave Spider Spritesheet.png` — row 0 = idle, row 1 = run, 32×32 frames, the attack/hurt/death rows in that sheet are unused) and reverting rebuilds the true form's sprite via the normal `_setup_animations()` path. **A form with no `SHAPE_SHIFT_SPRITES` entry** (Raven; Quasit's Bat/Centipede/Toad — no art authored for any of them yet) — `_refresh_shape_shift_visual()` no-ops, leaving whichever sprite was already showing, so those "shifts" are still mechanics-only asset debt. **Speed while shifted** is also per-entry: `_tick_speed_gate()` uses pool `"shape_shift_speed"` if authored, else falls back to Imp's original hardcoded mundane `{"moves":2,"per":3}` ground speed (regardless of the true form's own `"speed_ground"`/`"speed_flying"` pair — none of Imp's three animals can fly). Quasit instead authors `"shape_shift_speed": {"moves":4,"per":3}` (its own normal speed) since none of its forms are meant to be slower than its true form.

## Bearded Devil

`dungeon_floor_data.gd`'s `BOSS_POOL` `big_demon` entry (identity/art kept from the old "Big Demon"
it replaced — see root `CLAUDE.md`'s Sprite Assets section; `boss_id` stays `"big_demon"` since
`GameState.TIER2_GATING_BOSS_ID` and every save key off it) is the real 5e Bearded Devil stat
block, given directly by the project owner — Medium Fiend (lawful evil), CR 3, HP 52, AC 13
(engine's own floor-scaling term still adds `+floor/5` on top, same as every other enemy — see
"Enemy stat scaling" below, not part of the monster's own stat block), STR 16(+3)/DEX 15(+2)/
CON 15(+2)/INT 9(-1)/WIS 11(+0)/CHA 11(+0), superior darkvision (`"senses": {"sight_bonus": 2}`),
resist Cold/Bludgeoning/Piercing/Slashing (the real text's "from nonmagical/non-silvered weapons"
qualifier isn't modeled — same documented simplification Skeleton's own unqualified Piercing
resistance already uses), immune Fire/Poison damage and the Poisoned condition, Magic Resistance
(shared trait, see above), plus three new/reused mechanisms:

- **Devil's Sight** (trait `"devils_sight"`, real text: "magical darkness doesn't impede its
  vision"): this engine's only source of "magical darkness" is the Fog Cloud/Darkness spell zone
  `GameState.is_blinded()` checks, so `Enemy._sight_range()` simply exempts a `devils_sight`
  enemy from that zone's sight-collapse-to-1 penalty — real mechanical teeth, not flavor-only,
  since a player hiding in their own Darkness spell no longer blinds this boss the way it would
  every other enemy.
- **Steadfast** (trait `"steadfast"`, real text: "can't be frightened while a friendly creature is
  within 5 feet of it"): `Enemy.apply_status()` checks this before the `"frightened"` branch —
  blocks the condition outright (same gray "unaffected"-style log line as `condition_immunities`)
  whenever another living `Enemy` is within Chebyshev 1. No in-game concept of "friendly to a
  devil" exists beyond "another enemy" — same "any other enemy counts as an ally" simplification
  Pack Tactics' own adjacency check already uses.
- **Beard** (`"multiattack"` sub-entry, 1d8+2 Piercing, `"on_hit_save"`): a landed hit rolls a
  player CON save (DC 12, via the new generic `"on_hit_save": {"stat","dc","status","turns"}`
  schema key, `Enemy._attack_player()`) — a fail applies the real Poisoned condition for 10 turns
  AND sets `Stats.poisoned_condition_save_dc = 12`, which (a) grants a repeated end-of-turn CON
  save to end it early (`Player._on_turn_started()`, mirrors Frightened's own repeated-save shape)
  and (b) blocks `GameState.heal()` entirely while active (the real text's "can't regain any HPs
  while poisoned" clause) — see "Conditions"'s Poisoned row above. A plain Poisoned source that
  never sets this DC (Tripwire, Quasit's Rend) is completely unaffected by either addition.
- **Glaive** (`"multiattack"` sub-entry, reach 2 — via the existing "reach" mechanism other
  entries already use, 1d10+3 Slashing, `"infernal_wound": {"dc"}`): a landed hit only rolls a CON
  save (DC 12) the FIRST time — a fail arms `Stats.infernal_wound_active`/`infernal_wound_dice = 1`
  (an escalating DoT, `infernal_wound_dice` d10 Necrotic dealt at the start of every real player
  turn, `player.gd._on_turn_started()`). Every SUBSEQUENT Glaive hit while already wounded adds
  another die UNCONDITIONALLY (no repeat save — matches the real text: "each time the devil hits
  the wounded creature... the damage increases by 1d10"). Ends the instant ANY healing lands
  (`GameState.heal()`'s tail clears both fields) — approximates "closes automatically after
  receiving magical healing" (simplified to "any healing", not just magical). **Not implemented**:
  the real text's "any creature can take an action to stanch the wound with a DC 12 Wisdom
  (Medicine) check" — no generic "spend your action on a check" verb exists in this engine to hang
  it on, a documented gap same tier as Elf's Fey Ancestry/Dwarf's Poisoned-check half above.

## Spider

`dungeon_floor_data.gd`'s `spider` entry — Large Beast, CR 1, HP 26, AC 14, a 2x2 footprint (same
mechanism as Ogre, see "Multi-tile footprint" below), Bite (1d8+3 Piercing + 2d6 Poison on the same
hit, `"extra"` — same convention as Imp's Sting) plus two authored traits and a bespoke ranged
ability:

- **`"ignore_terrain_slow"`** (Spider Climb — "can go through difficult surfaces without being
  slowed"): `Enemy._move_step()`'s generic Water/Mud → `apply_status("slowed", 1)` call is skipped
  outright whenever this trait is present — every other enemy still gets slowed by difficult
  terrain, only an enemy that opts into this trait is exempt.
- **`"web_walker"`** (Web Walker / Web Sense — "ignores movement restrictions caused by webbing and
  knows the location of any creature in contact with the same web"): implemented as the half that
  actually matters for a single spider — `Enemy._can_see_entity()` short-circuits to `true` for a
  target currently Restrained by `Stats.web_restrained`, regardless of distance/LOS, mirroring the
  Invisibility short-circuit just in the opposite direction (never-lost instead of never-seen). The
  "ignores its own web" half is a documented no-op (nothing in this engine ever makes an enemy walk
  into a web).
- **Web ability** (pool `"web": {"cooldown","range","save_dc"}`, `Enemy._decide_action()`/
  `_execute_cast_web()`): a ranged, non-damage, SAVE-based restraint, Player-only (the only entity
  with a Restrained/escape mechanic today). Priority-wise it sits in the exact same slot Imp's
  Invisibility occupies — while already aware of the target (`CHASING`/`SEARCHING`, **never** on a
  fresh notice, matching the direct owner's own framing: a Spider that hasn't noticed the hero yet
  never webs blind), not yet adjacent, the target isn't already stuck in an earlier web, off its
  10-turn cooldown, in range, and nothing blocks the shot (`DungeonFloor.has_clear_shot()`, same
  obstruction gate every other ranged ability/thrown-weapon check already uses — "can only spit
  it if nobody/nothing stands in the way"), Web is picked over closing the distance. On cast: a DEX
  saving throw rolled the identical `d20 + DEX mod + (proficiency if Stats.check_prof_dex)` shape
  the player's own DEX save vs a friendly-fire Fireball already uses (`spell_effects.gd`'s
  `cast_leveled_at_area()`). Failure sets `Stats.web_restrained = true` (+ `Stats.web_escape_dc`)
  and calls `DungeonFloor.spawn_web(target.grid_pos)` — a lightweight destructible-terrain dict
  (`_webs`, same shape as `_barrels`, AC 10 / HP 5 / vulnerable to Fire / immune to Poison and
  Psychic per the real spell's text, **no art yet** — `WEB_TEX_PATH` guarded exactly like
  `BARREL_TEX_PATH`, mechanically wired but visually a no-op until a sprite is authored). Restrained
  blocks ALL player movement: `player.gd._try_move()` redirects every directional key press into
  `_attempt_web_escape()` instead (a STR check vs `web_escape_dc` — the D&D-alternate escape route,
  since this engine has no attack-a-structure system to support the "deal 5+ slashing/fire damage to
  the web" route; documented simplification, not an oversight). Success clears
  `web_restrained`/destroys the web at the player's current tile (guaranteed still underfoot, since
  Restrained blocks movement entirely); failure just costs the turn.
- **Sprite**: reuses the same sliced `Spider/{idle,run}.png` sheet (32×32 frames, scale 0.5, 6
  frames each) already authored for Imp's Shape Shift form above — `Enemy._setup_animations()`
  gained a `_type.has("sprite_frame_size")` branch (no `sprite_variants` needed) that calls
  `_setup_sheet_animations([])`, and `_setup_sheet_animations()` itself now handles an empty
  `variants` array by skipping the per-color subfolder entirely (same branch
  `_refresh_shape_shift_visual()` already used for this exact asset) — a reusable path for any
  future sheet-sliced enemy with no cosmetic recolor.

## Spiderling

`dungeon_floor_data.gd`'s `spiderling` entry — a plain 1x1-footprint Small Beast, CR 1/4, HP 9,
AC 12 (natural armor, baked straight into `"ac"`), STR 9(-1)/DEX 12(+1)/CON 11(+0)/INT 13(+1)/
WIS 8(-1)/CHA 13(+1), darkvision (`"senses": {"sight_bonus": 1}"`), resist Fire, immune Poison
damage, floors 1-4 — the low-CR "baby Spider" companion entry to the Large `spider` above, reusing
zero new mechanics: Bite is a plain `"multiattack"` sub-entry (1d6+1 Piercing, `"on_hit_save"`,
the same generic mechanism Bearded Devil's Beard already established — see "Bearded Devil" above)
— a landed hit rolls a DC 10 CON check, a fail applies the real Poisoned condition for 10 turns
("1 minute" at 6s/round). **"Fails the check by 5 or more → also Paralyzed while poisoned" is now
implemented too** — `on_hit_save`'s optional `"paralyze_margin"` key (Spiderling sets `5`):
`Enemy._attack_player()`'s `on_hit_save` block checks `(dc - total) >= paralyze_margin` on the SAME
failed save (no second roll) and calls `GameState.apply_player_paralyzed(turns, dc, stat)` — the
first real player-side Paralyzed condition in this engine (built for this clause specifically, see
"Conditions" below's Paralyzed row for the full player-side mechanism it introduced).
**Sprite**: reuses `Spider/{idle,run}.png` at the exact same scale (`0.5`) Imp's Shape Shift
"spider" form already uses (`Enemy.SHAPE_SHIFT_SPRITES["spider"]`) — same sheet, same 32x32 frame
size, just rendered smaller, so it visibly reads as a baby version of the full-size Spider rather
than needing a separate asset. Also immune to Exhaustion/Paralyzed/Unconscious per its own real
stat block, but none of the three currently has any mechanism that could ever target an enemy
(Exhaustion is player-only; Paralyzed's only source, Hold Person, is Humanoid-only and this is a
Beast; Unconscious isn't a modeled condition at all) — same "granted but nothing to hook into"
precedent as several race traits in this file, so no `"condition_immunities"` pool key was needed
for any of the three.

## Quasit

`dungeon_floor_data.gd`'s `quasit` entry (art/identity renamed from the earlier "Chort" sprite —
see root `CLAUDE.md`'s Sprite Assets section) — Tiny Fiend, CE, CR 1, HP 25, AC 13 (natural
armor), STR 5/DEX 17/CON 10/INT 7/WIS 10/CHA 10, superior darkvision (`"senses": {"sight_bonus":
2}`), resist Cold/Fire/Lightning, immune Poison damage and the poisoned condition, Rend (1d4+3
Slashing, `"multiattack"`), Magic Resistance (shared trait with Imp, see above), Invisibility
(identical mechanism to Imp's own, same pool key), and two more mechanisms:

- **Shape Shift, Quasit's own form list**: reuses Imp's `"shape_shift"` trait but authors
  `"shape_shift_forms": ["bat","centipede","toad"]` (`Enemy._shape_shift_forms()` — see the
  `"traits"` row above) instead of Imp's rat/raven/spider, and `"shape_shift_speed":
  {"moves":4,"per":3}` so none of its forms are slower than its own true-form speed (Imp's forms
  deliberately downgrade to a shared mundane ground speed since none of them can fly; Quasit's
  Bat/Centipede/Toad don't need that penalty). **Toad additionally swims freely**: `Enemy.
  _move_step()`'s generic Water/Mud → `apply_status("slowed", 1)` call now also skips WATER
  specifically (not Mud) whenever `_shifted_form == "toad"`, alongside the pre-existing
  `"ignore_terrain_slow"` trait check (Spider Climb) — a narrower, form-scoped exemption rather
  than a blanket trait, since only the Toad form is meant to ignore water, not Quasit's true form
  or its other two forms. No art authored yet for Bat/Centipede/Toad (asset debt, same precedent
  as Imp's own unwired Raven) — `_refresh_shape_shift_visual()` no-ops for all three, leaving the
  true Quasit sprite showing.
- **Scare ability** (pool `"scare": {"range","save_dc"}`, `Enemy._decide_action()`/
  `_execute_cast_scare()`): a ranged, non-damage, WIS-SAVE-based fear effect, Player-only, 1/life
  (the real stat block is "1/Day" — enemies don't rest, same "N/day = N/life" precedent as
  Legendary Resistance — tracked via a plain `_scare_used: bool` flag rather than a cooldown
  counter). Same decision priority/gating shape as Spider's Web above: while already aware of the
  target (`CHASING`/`SEARCHING`, never on a fresh notice), not yet adjacent, in range (default 2
  tiles), and nothing blocks the shot (`DungeonFloor.has_clear_shot()`), Scare is picked over
  closing the distance. On cast: a WIS saving throw, `d20 + WIS mod + (proficiency if
  Stats.check_prof_wis)` vs the pool's `"save_dc"` (10) — same roll shape as Web's own DEX save,
  just WIS instead — logged via the same `save:` tooltip meta format as every other resist check
  ("frozen with fear"/"hold your nerve"). On a failed save, applies the real Frightened condition
  (`GameState.apply_player_frightened(self, SCARE_FRIGHTENED_TURNS, dc)`, `SCARE_FRIGHTENED_TURNS
  = 10`) — see "Conditions" above for the full mechanic.

**Race-granted ability icons**: `res://icons/races/<race>/<ability_id>.png`, one folder per race,
mirroring `icons/classes/<class>/`'s convention (root `CLAUDE.md`'s Sprite Assets section) — every
`GameState._build_*_ability()` racial-ability builder below sets `Ability.icon_path` directly to
its own file (no shared resolver like `talent_icon_path()`, since each race grants a fixed, small
set of abilities with no rank-gradient icons to resolve). Goliath's Giant Ancestry is the one
multi-icon case: `GameState._giant_ancestry_icon_path(variant)` maps `Stats.GiantAncestry` to
`icons/races/goliath/giant_ancestry/{cloud,fire,frost,hill,stone,storm}.png`. Each race folder
also holds a `portrait.png` (a race-representative bust, distinct from any ability icon) — the
one file shared by `race_select.gd`'s tile grid (`scripts/ui/CLAUDE.md`'s "Race select") and the
HUD's always-on `race_bonus` status-tray icon (`StatusTooltips.race_portrait_icon_path()`,
`scripts/ui/status_tooltips.gd`), so both surfaces show the identical art.

**Race tooltip format** (same structured-tooltip pass as spells — `scripts/items/CLAUDE.md`'s
"Unified spell tooltip format"): hovering the HUD's `race_bonus` status-tray icon shows
`RaceTooltip.build(stats)`
(`scripts/entities/race_tooltip.gd`) instead of the old flat prose block:
```
[b]Race Name[/b]
Creature Type: X
Size: X
Speed: X
Darkvision: None/Normal/Superior

<trait name>          — one hoverable [url=race_trait:id] line per trait
<trait name>
...
```
Trait data (`RaceDb.build(stats)`, `scripts/entities/race_db.gd`) is built fresh from the live
`Stats` instance every call (variant-dependent traits — Elf sub-race, Tiefling legacy, Dragonborn
ancestry, Gnome lineage, Goliath ancestry — read `stats.race_variant`/`darkvision_bonus` directly,
same "no separate cache to keep in sync" precedent as `SpellDb.get_spell()`). Hovering a trait name
opens a level-1 glossary popup with its own terse description (`RaceTooltip.build_trait_detail()`)
— status/condition names inside that description (Frightened, Charmed, etc.) are themselves
hoverable via the shared `WeaponTooltip.linkify_conditions()` helper (moved there from
`SpellTooltip` once race traits needed the identical behavior — see `scripts/items/CLAUDE.md`).
Hovering one of THOSE condition keywords (not just a `race_sub:` sub-option link) also opens the
level-2 popup — `hud.gd._on_glossary_meta_hover_started()` handles both link kinds a trait
description can contain (e.g. Halfling's Brave links "Frightened" this way, with no sub-options at
all).

**A trait with sub-options gets a real second hover level**, not a flat inline list — currently
only Aasimar's Celestial Revelation (Heavenly Wings/Inner Radiance/Necrotic Shroud). The level-1
popup's own description ends with each sub-option as a further `[url=race_sub:trait_id:sub_id]`
link; hovering one opens a level-2 popup (`RaceTooltip.build_sub_detail()`) with that sub-option's
own description — a genuine nested hover chain, not the flat single-level glossary every other
keyword uses. This required `hud.gd`'s `_glossary_popup`/`_glossary_rtl` (previously a plain,
non-interactive display panel) to become interactive itself — `STOP`/`PASS`+`bbcode`+`meta_hover`
wiring, same shape as the top-level qbar tooltip — plus a brand-new terminal `_glossary_popup2`/
`_glossary_rtl2` pair for the level-2 popup. Hiding the chain is NOT driven by `meta_hover_ended`
(that fires the instant the cursor leaves the trigger link, even when heading INTO the popup it
just opened) — `hud.gd._process()` instead hides `_glossary_popup`/`_glossary_popup2` (and the base
qbar tooltip itself) once the mouse is outside every rect in the chain (source icon ∪ qbar tooltip
∪ glossary popup ∪ glossary popup2), checked every frame — no Ctrl needed anywhere, the whole chain
is always live-hoverable (see `scripts/ui/CLAUDE.md`'s "Tooltip hover chain (no Ctrl-freeze)").
Adding a new nested trait: give it `subs: Array[{id,name,desc}]` in its `RaceDb.build()` entry —
`RaceTooltip.build_trait_detail()`/the hud.gd popup chain need no changes, they're already generic
over any trait's `subs` list.

## Dragonborn

Humanoid, Medium (5-7 ft), Speed 1 tile/turn (baseline).

Composition child-node `player_dragonborn.gd` (`PlayerDragonborn`), instantiated as `_dragonborn`
in `player.gd._ready()` — same pattern as `PlayerZealot`/`PlayerBerserker`. Two race abilities,
both granted by `GameState.give_race_starting_items()` (idempotent — safe to re-run; `choose_race()`
calls it once at the actual race pick, `from_dict()` calls the parallel `_restore_race_ability_bar()`
after `Stats.from_dict()` restores `character_race`/`character_level`/the two uses fields, without
re-rolling starting uses — see `scripts/autoloads/CLAUDE.md`).

- **Breath Weapon** (ability_id `"breath_weapon"`, granted immediately at level 1): a Cone or Line
  AoE dealing the character's own `Stats.DRAGONBORN_DAMAGE_TYPE[race_variant]` damage type (same
  table `apply_race_defaults()` uses for the passive resistance — Black/Copper Acid,
  Blue/Bronze Lightning, Brass/Gold/Red Fire, Green Poison, Silver/White Cold — matching real 5e
  2024 exactly). **Arm-toggle-cancel targeting** (`_use_ability_slot()`'s `"breath_weapon"` case →
  `PlayerDragonborn.activate_breath_weapon()`): 1st press arms a 2-tile Cone
  (`PlayerDragonborn.BREATH_CONE_LENGTH`), a 2nd press on the SAME slot switches the armed shape to
  a 3-tile Line (`BREATH_LINE_LENGTH`) instead of firing, a 3rd press cancels — one more toggle
  step than every other armed ability in this codebase (which all cancel on the 2nd same-slot
  press), since there's a shape choice to cycle through first. Any world click then fires in that
  direction (`resolve_breath_weapon(aim_tile)`, dispatched from `player.gd`'s mouse-release
  handler right after Grip of the Forest's own block) — the clicked tile only supplies a direction,
  it need not itself be in range, same convention as Burning Hands' cone. Esc and any WASD
  movement key cancel an armed-but-not-yet-fired breath exactly like every other armed
  targeting mode (`PlayerDragonborn.cancel_breath_weapon()`, wired into both cancel chokepoints).
  **Cone** reuses `SpellEffects.cone_tiles()` verbatim (continuous aim angle, narrowing triangle).
  **Line** is a new `PlayerDragonborn._line_tiles()` static helper — snaps the aim direction to the
  nearest of 8 fixed directions (unlike the cone's continuous angle) and walks a straight 1-wide
  ray for `length` tiles, stopping at the first LOS break, matching 5e's own fixed-width line AoE
  shape rather than a widening triangle. **Damage**: `Stats.breath_weapon_dice_count()` — 1d10
  base, +1d10 at character levels 5/11/17 (5e 2024's own progression) — vs a DEX save at
  `8 + CON mod + proficiency_bonus` (`Enemy.resist_check_detailed(dc, false, true, false, false,
  false)` — non-magical, so Imp/Quasit's Magic Resistance trait does NOT grant Advantage against
  it, per 5e RAW "this isn't a spell"), half damage (floored) on a save — same resolution shape as
  Burning Hands' `_resolve_cone_aoe()`, reused nearly verbatim. Fire-type breaths also ignite
  GRASS/flammable props in the blast, mirroring Fire Bolt/Burning Hands. **Uses**:
  `Stats.breath_weapon_uses_remaining`, max = `proficiency_bonus` (5e 2024's own cap) — refilled to
  max in `GameState.long_rest()`; a level-up that raises `proficiency_bonus` (levels 5/9/13/17)
  grants the delta as an immediate CURRENT use too, not just a higher cap (mirrors Rage's own
  grant-now treatment in `gain_exp()`), via `_sync_ability_uses()`'s new `"breath_weapon"` case.
- **Draconic Flight** (ability_id `"draconic_flight"`, granted the instant `character_level`
  reaches 5 — `gain_exp()`'s `old_level < 5 and character_level >= 5` check calls
  `give_race_starting_items()` again, which is a no-op for the already-granted Breath Weapon):
  free action (does not cost a turn), 1/long rest (`Stats.draconic_flight_used`, reset in
  `long_rest()`; gated in `GameState.is_ability_usable()`'s `"draconic_flight"` case, same pattern
  as Frenzy/Limit Break), sets `Stats.draconic_flight_turns = 100`, ticked down once per real turn
  in `player.gd._on_turn_started()` alongside Invisibility's own identical-shaped duration. While
  `draconic_flight_turns > 0`: **CHASM tiles are walkable** (`_try_move()`'s `_owl_override` local
  now also true for Draconic Flight, not just Natural Sleeper's Owl form — same WASD-only scope
  limitation Owl already has, since the click-to-path pathfinder never routes through a tile
  `is_walkable()` reports false for, regardless of either override); **GRASS never tramples to
  TRAMPLED_GRASS** and **traps never trigger** (all 3 player movement code paths — direct
  `_try_move()`, the chase-to-target loop, and the queued-path loop — each gained a local
  `_flying`/`_flying_c`/`_flying_p` bool gating their existing `destroy_grass()`/`trigger_trap()`
  calls); **immune to standing-on-fire damage** (`DungeonFloor.tick_fire_damage_for()`'s `Player`
  branch returns early) — covers "grass burning underneath you doesn't ignite you". **WATER/MUD
  never apply the difficult-terrain `slowed` status** (bugfix — all 3 movement code paths only
  checked Trailblazer/Natural-Sleeper-form bypasses before, so flying still got bogged down
  wading through water/mud despite the CHASM/grass/trap bypasses above already existing) and
  **grass no longer blocks the player's own FOV/LOS while flying** — `DungeonFloor._blocks_los()`
  gained a `_ignore_grass_los` bool, set true only during the player's OWN `update_fog()`
  shadowcast while `draconic_flight_turns > 0` (mirrors `_ignore_magical_darkness`'s exact
  set-before/reset-after-the-shadowcast-call pattern) — an enemy's own LOS check is a separate
  shadowcast call that never sets this flag, so grass still blocks an enemy's sight of the player
  normally; only the flying player's own vision sees over it. **Known simplification**:
  ground-effect immunity doesn't extend to Spider's Web structure (a Restrained player can still be
  caught mid-flight) — not wired, since Web's own movement-block path (`player.gd`'s `_try_move()`
  WASD-redirect into `_attempt_web_escape()`) is a separate mechanism from the walkability/grass/
  trap checks above and wasn't in scope for this pass.

**Breath Weapon targeting preview** (bugfix — it used to arm with zero visual feedback, the only
armed ability-bar action with none): `player.gd._update_breath_weapon_preview()`, dispatched from
`_update_spell_aoe_preview()`'s own `spell == null` branch whenever `_dragonborn.
breath_weapon_mode_active` (so it reuses the same per-frame call site, FOV-bonus-overlay
suppression, and pooled-`Sprite2D` preview layers every spell already uses — no parallel `_process`
hookup needed). Mirrors Burning Hands' own cone preview exactly: a blue max-reach backdrop unioning
`SpellEffects.cone_tiles()` (Cone shape) or `PlayerDragonborn._line_tiles()` (Line shape) over all 8
`SpellEffects.DIR8` directions (`DungeonFloor.show_spell_range_preview_tiles()`), plus a purple/red
exact-footprint highlight at the currently-hovered aim direction (`DungeonFloor.
show_cone_preview()` for Cone, reusing the existing function verbatim; a new `DungeonFloor.
show_line_preview(tiles)` — a thin pass-through to the shared `_paint_aoe_preview_tiles()` — for
Line, since no line-shaped preview existed before). Both shapes read `PlayerDragonborn.
BREATH_CONE_LENGTH`/`BREATH_LINE_LENGTH` directly rather than a `Spell` resource, since Breath
Weapon isn't cast through the spell system at all.

**Breath Weapon hover tooltip** mirrors the `SpellTooltip.build()` fixed-line format (Casting
Time / Range: Self / Area: N-tile Cone or M-tile Line / Duration: Instantaneous, nbsp-glued so it
never word-wraps) — built in `GameState._build_breath_weapon_ability()`'s `Ability.description`.
`hud.gd`'s ability-bar tooltip has a generic branch (alongside the `spell:`-prefixed one) that
widens the popup box to fit any ability whose description contains an nbsp fixed-line block.

## Dwarf

Humanoid, Medium (4-5 ft), Speed 1 tile/turn (baseline).

Composition child-node `player_dwarf.gd` (`PlayerDwarf`), instantiated as `_dwarf` in
`player.gd._ready()` — same pattern as `PlayerDragonborn`. Two race features, on top of the
pre-existing superior darkvision (+2) and Dwarven Toughness (+1 max HP/level, including level 1):

- **Dwarven Resilience** (passive): `apply_race_defaults()`'s `DWARF` branch appends `"Poison"` to
  `Stats.damage_resistances`. **Bugfix while wiring this in**: `Stats.damage_resistances` was set
  by Dragonborn's own branch but never actually READ anywhere — `GameState.take_damage_raw()` now
  applies a flat ×0.5 (floored) reduction whenever `damage_type in player_stats.damage_resistances`,
  fixing Dragonborn's passive resistance too (previously a no-op). **Scope limit**: only covers
  direct typed Poison damage (an enemy attack/ability with `damage_type == "Poison"`) — the
  `"poison"` status-tick DoT (`Stats.tick_status()`) sums poison/burning/bleeding into one untyped
  int before it ever reaches `take_damage_raw()`, so it can't resist by type today; a documented
  simplification, not an oversight. **The "Advantage on checks to avoid or end the Poisoned
  condition" half is deferred** — no save/check exists anywhere in this engine for gaining/ending
  the Poisoned CONDITION (`poisoned_condition_turns` — Tripwire trap and Quasit's Rend both apply
  it unconditionally, no roll) — direct owner decision: wire it in once a real mechanic that rolls
  against Poisoned actually exists, rather than inventing a save just to hang Advantage on it.
- **Stonecunning** (ability_id `"stonecunning"`, granted immediately at level 1): free action,
  uses = `proficiency_bonus` (refilled on long rest, +1 CURRENT use the instant a level-up raises
  `proficiency_bonus` — identical `give_race_starting_items()`/`_sync_ability_uses()`/`gain_exp()`
  wiring as Breath Weapon, see "Dragonborn" above). Activating (`PlayerDwarf.
  activate_stonecunning()`) sets `Stats.tremorsense_turns = 100`, ticked down once per real turn in
  `player.gd._on_turn_started()` alongside every other 100-turn buff. While active: **Tremorsense**
  — `DungeonFloor._update_tremor_markers()` (called every `update_fog()`, same pooled-`Sprite2D`
  convention as `_update_burning_tiles_glow()`) shows a small pulsing red dot
  (`_build_tremor_marker_texture()`, a procedurally-drawn 10px filled circle, no art asset) on
  every living `Enemy` within `Stats.STONECUNNING_RANGE` (6 tiles, Chebyshev, a flat constant — NOT
  fed through the `/20`/`/10` ranged-scaling divisors, since this is a sense, not an attack) that
  is standing on the **exact same `DungeonData.TileType`** as the player right now (Floor-on-Floor,
  Grass-on-Grass, etc. — a deliberate stricter reading than 5e's own looser "both touching the
  ground" text, direct owner decision) and isn't already plainly visible this FOV update
  (`_visible_tiles.has(enemy.grid_pos) and not enemy.is_hidden_from_player()` — no redundant ping
  over an already-seen sprite). **Sight-independent**: the check never reads `_visible_tiles` or
  `GameState.is_blinded()` for the SENSING half, so it works exactly the same whether the player
  can see normally, is in a dark unlit room, or is standing inside a Fog Cloud (Heavily Obscured/
  Blinded) — the dot only ever tells you SOMETHING living is there, never what. **No new targeting
  code was needed**: `DungeonFloor.get_targetable_enemy_at()` was already FOV-independent (gated
  only on `Enemy.is_hidden_from_player()`, i.e. Invisibility — see "Invisibility" below), so a
  tremor-pinged enemy was already clickable/attackable before this feature; Tremorsense's entire
  contribution is the dot that tells you WHERE to click in the first place. **ADV/DISADV when
  fighting blind falls out for free from the existing Fog Cloud mechanism** — no new combat-roll
  code was needed here either: `GameState.is_blinded(pos)` is already purely positional/symmetric
  (see "Fog Cloud" below), so attacking a tremor-sensed target while both attacker and target are
  in the SAME cloud already nets a normal roll (ADV-for-attacking-a-Blinded-target cancels
  DISADV-for-being-Blinded-yourself), attacking one INSIDE the cloud from OUTSIDE it already nets
  pure ADV (target Blinded, attacker isn't), and attacking OUT of the cloud at a target outside it
  already nets pure DISADV (attacker Blinded, target isn't) — exactly the three cases the direct
  owner described, all pre-existing behavior once Tremorsense makes the target visible at all.

## Elf

Humanoid, Medium (5-6 ft), Speed 1 tile/turn (baseline).

3 traits, always on, plus the sub-race's own Elven Lineage. `Stats.apply_race_defaults()`'s ELF
branch:

- **Keen Senses** (passive): WIS check proficiency (`check_prof_wis = true` — shares the underlying
  bool with Wizard's own INT+WIS class checks, harmless overlap since it's a flat flag).
- **Fey Ancestry** (passive): ADV on checks to avoid/end the Charmed condition. **Deliberately
  inert today** — no Charmed condition (or any check against one) exists anywhere in this engine
  yet, same "granted but nothing to hook into" precedent as Dwarf's own Dwarven Resilience
  ADV-vs-Poisoned-condition half (see "Dwarf" above). Wire in once a real Charmed source/check
  exists rather than inventing one just to hang this on.
- **Trance**: `GameState.long_rest_turns_needed()` halves `LONG_REST_TURNS` for an Elf — shorter
  long rests, no other mechanical effect.
- **Superior darkvision for Drow specifically**: `darkvision_bonus = 2 if race_variant ==
  ElfSubrace.DROW else 1` — every other Elf sub-race gets the normal `1`.

**Elven Lineage**: the chosen sub-race (`Stats.ElfSubrace` — DROW/HIGH_ELF/WOOD_ELF, picked at
race select same as today) grants a passive/mechanical benefit immediately (character level 1) and
one spell each at character level 3 and 5 — `GameState.gain_exp()`'s level-up block calls
`_grant_elf_lineage_spell(_elf_lineage_spell_for(race_variant, threshold_level))` the instant
either threshold is crossed (`old_level < N and character_level >= N`, same pattern as
Dragonborn's Draconic Flight/Breath Weapon proficiency-bonus grants). A lineage spell is
**always prepared** — granted straight onto the ability bar via `GameState._build_spell_ability()`
+ `add_ability()`, entirely outside the normal `known_spells`/`prepared_spells`/
`SpellcasterState` bookkeeping, so it never counts against a caster's known-cantrip or
prepared-spell cap (and exists even for a non-caster class, e.g. a Barbarian Elf) —
`Stats.elf_lineage_spell_ids: Array[String]` is the list of spell ids granted this way, serialized
in `to_dict()`/`from_dict()`; `GameState._restore_race_ability_bar()` re-adds their ability-bar
entries on save/load replay.

**Free cast economy**: each lineage spell grants exactly **1** free cast per long rest —
`Stats.elf_lineage_free_casts_remaining: Dictionary` (spell_id → int, refilled to `1` in
`GameState.long_rest()`; briefly scaled to `proficiency_bonus`, same counter shape as Gnomish
Lineage's own `gnome_lineage_free_casts_remaining` below, before a direct owner correction reverted
it to a flat 1 — a leveled lineage spell genuinely falls back to a real spell slot once its free
use is spent, unlike Gnomish Lineage's 3 cantrip grants, which have no slot fallback at all and so
keep the `proficiency_bonus` counter — shown on the ability-bar slot's use-count badge —
`hud.gd`'s `_refresh_ability_bar()`, same `"X/Y"` treatment as Hunter's Mark/Rage) +
`Stats.is_lineage_free_cast_available(spell_id)` (checks BOTH
`elf_lineage_free_casts_remaining` and `tiefling_legacy_free_casts_remaining` — a single shared
gate, since a Tiefling Fiendish Legacy spell is mechanically identical to an Elf lineage one; a
non-caster class, e.g. a Barbarian Tiefling, has no other way to ever cast its own legacy spell,
so this gate missing the Tiefling half used to mean "no spell slot available" forever), checked
BEFORE ever touching a
real spell slot at every relevant chokepoint: `PlayerSpellcasting.begin_cast()`/`cast_direct()`'s
slot-availability gate, `_cast_level_for()` (also guards a `null` `Stats.caster` — a non-caster
class has no `SpellcasterState`/`slot_pool` at all, so the free uses are the ONLY casts available
to them), and `SpellEffects._consume_slot()` (now takes the `Spell`, not just a level int, so it
can check the lineage-free-cast condition before falling through to `caster.slot_pool.consume()` —
**bugfix**: this used to always decrement `elf_lineage_free_casts_remaining` whenever EITHER pool
said "available", so a Tiefling-only spell's own counter — e.g. Infernal's level-5 Darkness — never
actually decremented and was castable free forever; it now decrements whichever pool's array
actually contains the spell_id). Beyond the free uses, a further cast needs a real spell slot of
the spell's own level (Wizard/
Ranger only) — a non-caster simply has no further casts once the free one is spent, a documented
simplification (same "narrow case, not the full system" precedent as Scroll of &lt;Spell&gt;
casting for a non-caster).

**Dedup against a spell already learned normally**: a Ranger who already picked this exact spell
from the level-up spell-learn picker (`SpellDb.RANGER_SPELL_IDS` includes `pass_without_trace` and
`fog_cloud`, so this is a real, common overlap with Wood Elf's own level-5 grant, not a hypothetical
one) used to end up with the spell tracked by BOTH systems at once — the normal
`known_spells`/`prepared_spells` bookkeeping AND the lineage's own always-prepared grant — which
could leave it duplicated on the ability bar. Two-sided fix: (1) `GameState.
_migrate_spell_out_of_known_bookkeeping(spell_id)` — called at the top of both
`_grant_elf_lineage_spell()` and `_grant_tiefling_legacy_spell()` — pulls the spell out of
`known_spells`/`prepared_spells` and clears any existing `"spell:"` ability-bar entry FIRST (covers
the "learned via the picker, THEN lineage-granted" order), so the lineage grant always ends up the
sole owner of that spell_id going forward (a single ability-bar entry, governed only by the
free-cast counter above, no longer selectable/toggleable from the Spellbook). (2) The reverse order
(lineage-granted first, then the level-up picker/a scroll tries to teach the SAME spell_id again)
is closed at both the offer side — `_roll_spell_learn_choices()`/`can_learn_scroll_spell()` never
offer/allow a spell already in `elf_lineage_spell_ids`/`tiefling_legacy_spell_ids` — and as a
generic backstop, `GameState.add_ability()` itself now refuses to place a second `Ability` sharing
an `ability_id` already on the bar (returns `true`/no-op instead), so no future double-grant path
of any kind can duplicate a bar slot.

**Per sub-race** (`GameState._elf_lineage_spell_for(subrace, threshold_level)`):

| Sub-race | Level 1 (immediate) | Level 3 spell | Level 5 spell |
|---|---|---|---|
| Drow | Superior darkvision (see above) | Faerie Fire | Darkness |
| High Elf | Long-rest cantrip swap (below) | Detect Magic | Misty Step (reuses the existing Wizard/Ranger level-2 spell verbatim) |
| Wood Elf | 35 ft speed (below) | Longstrider | Pass Without Trace |

- **Faerie Fire** (`spell_db.gd`'s `_faerie_fire()`, real 5e class list Bard/Druid, level 1, range
  3, TILE target, **`shape = "cube"`, shape_size 2** — `shape_size` is a literal SIDE LENGTH here
  (2 = a real 2x2 block, corner-anchored at the impact tile), NOT a centered Chebyshev radius
  (`Spell.shape`'s third value, alongside `""`/`"sphere"`/`"cone"`; threaded through the generic
  AoE preview system exactly like `cone_tiles()` is shared between resolver and preview —
  `DungeonFloor.show_aoe_preview()`'s `"cube"` branch gathers the identical corner-anchored NxN
  block `SpellEffects._resolve_faerie_fire()` does, so the preview can never diverge from the real
  footprint), SAVE/DEX, Concentration, no damage. **Bugfix (twice over)**: this used to be a
  Euclidean sphere approximation (excluded the cube's own corner tiles); then briefly a *centered*
  Chebyshev-radius square (`shape_size=2` → a 5x5 area, far larger than the real spell's small
  2-tile cube) before being corrected to the literal 2x2 side-length interpretation.
  `SpellEffects._resolve_faerie_fire()` — one random color (blue/green/
  violet, `SpellEffects.FAERIE_FIRE_COLORS`, `Rng.pick()`) is rolled ONCE per cast and shared by
  every creature outlined that same cast (`Enemy.faerie_fire_color`) — "outlined in a random color,
  all the same." Every enemy within the 2x2 block (LOS'd from the impact tile) rolls a DEX
  save; on a fail, `Enemy.
  faerie_fire_turns = 10` (the caster's own Concentration duration is a separate field,
  `Stats.faerie_fire_turns`, ticked in `player.gd`'s per-turn block alongside Darkness). **Ending
  concentration DOES retroactively un-outline every currently-outlined enemy** — `GameState.
  end_concentration()`'s `"faerie_fire"` branch, on top of clearing the caster's own field, looks
  up the live `DungeonFloor` (`get_tree().get_first_node_in_group("dungeon_floor")`, since
  `GameState` holds no floor reference of its own) and zeroes every enemy's own `faerie_fire_turns`
  + calls `_refresh_faerie_fire_visual()` (bugfix — this used to only clear the caster's own
  counter, so an enemy's outline/debuff could silently outlive the concentration that was
  supposedly sustaining it). Shown on Ctrl-Inspect (`PlayerActions.do_inspect()`'s enemy status
  suffix — "Outlined"). Three effects while outlined:
  - **Advantage on attacks against it, but only if the attacker can see it**: `PlayerVfx.
    has_advantage()`'s Faerie Fire branch now additionally requires
    `player._dungeon_floor.is_tile_visible(enemy.grid_pos)` — an outlined enemy sitting somewhere
    the player currently can't see into (behind a wall corner) grants no Advantage just because
    it's lit up off-screen.
  - **Emanates its own small light**: `DungeonFloor.update_fog()` unions a
    `GameState.TORCH_BURN_LIGHT_RADIUS` (1) shadowcast around every outlined enemy's current
    position into `_visible_tiles` (mechanical FOV push-back only — no dedicated glow tint is
    painted, unlike the Torch/Light glows, a documented scope cut).
  - **Can't be invisible**: `Enemy.is_hidden_from_player()` returns `false` whenever
    `faerie_fire_turns > 0`, even if `_invis_turns > 0` — `Enemy.is_outlined_while_invisible()` is
    the companion query `DungeonFloor._update_enemy_visibility()` reads to render that specific
    case at `modulate.a = 0.4` (forced visible, translucent) instead of the normal fully-opaque
    outlined look — same tint convention as the player's own `Player._update_invisibility_visual()`.
  - **Also targets the PLAYER, not just enemies**: `_resolve_faerie_fire()`'s footprint check runs
    against the player too (own DEX save, same shape/LOS gate) — if caught (e.g. casting it on
    your own tile), sets `Stats.faerie_fire_outlined_turns`/`faerie_fire_outlined_color` (a field
    deliberately SEPARATE from `Stats.faerie_fire_turns`, which is always the CASTER's own
    Concentration countdown regardless of who ends up outlined — the two would otherwise collide
    if you outline yourself while also being the caster). Grants enemies Advantage attacking the
    player while set, symmetric to the enemy-side Advantage-against-an-outlined-enemy rule above —
    `Enemy._attack_player()`'s `faerie_fire_adv` local, gated on `is_tile_visible(player.grid_pos)`.
    Ticked alongside `faerie_fire_turns` in `player.gd`'s per-turn block. No enemy-side caster of
    this spell exists yet, so this only matters for a self-cast or a future enemy source — a
    documented scope note, not a current gameplay path. **Visual feedback** (bugfix — this was
    silent/invisible at first): a status-tray entry (`"faerie_fire_outlined"`, no art yet — flat
    color-tinted placeholder square using the same random cast color) plus a small above-character
    `✦` sparkle (`Player._faerie_fire_indicator`/`_refresh_faerie_fire_visual()`, a direct mirror of
    `Enemy`'s own identical indicator) both show while outlined. `GameState.end_concentration()`'s
    `"faerie_fire"` branch also clears the player's own `faerie_fire_outlined_turns` (via
    `DungeonFloor.get_player()`) alongside every outlined enemy's, so losing concentration ends the
    self-outline too, not just enemies'.

  A small `✦` sparkle (`Enemy._faerie_fire_indicator`, tinted `faerie_fire_color`) shows above an
  outlined enemy while active, toggled by `Enemy._refresh_faerie_fire_visual()` (called on cast and
  on the enemy's own `decide_turn()` tick reaching 0). Objects in the cube are cosmetic-only per
  the real spell text and are NOT implemented — this engine has no generic prop-outline system to
  hang a persistent tint on (documented scope cut, not an oversight).
- **Darkness** (`_darkness()`, Evocation, level 2, range 3, TILE, sphere shape_size 2, AUTO_HIT,
  Concentration up to 100 turns): a second, independent Heavily Obscured zone —
  `GameState.darkness_pos`/`darkness_radius` mirror `fog_cloud_pos`/`fog_cloud_radius` exactly, and
  `is_heavily_obscured(pos)` now checks both zones (`is_in_fog_cloud or is_in_darkness`) so Fog
  Cloud's entire existing ADV/DISADV/`effective_fov_radius()`/cant-see-through-it mechanism (see
  "Concentration"/Fog Cloud sections below) applies verbatim — no new combat-roll code needed.
  Concentration id `"darkness"`, `Stats.darkness_turns` (100, ticked like Fog Cloud). Visual reuses
  `DungeonFloor._update_fog_cloud_visual()`, generalized to paint both zones' tiles into the same
  pooled-sprite set — **each zone gets its own tint** (`DungeonFloor.DARKNESS_TINT`, the original
  near-black `Color(0.10, 0.10, 0.13, 0.80)`, vs. `DungeonFloor.FOG_CLOUD_TINT`, a lighter genuine
  gray `Color(0.55, 0.55, 0.58, 0.72)`) so the two zones are visually distinguishable even though
  they're mechanically identical Heavily Obscured terrain; a tile inside both renders with
  Darkness's tint (drawn second in the shared `tile_colors` dict).
  **Real, independently-learnable spell, not lineage-only anymore**: `"darkness"` is now also a
  `SpellDb.LEVELED_SPELL_IDS` entry (`class_list = ["WIZARD"]` — real 5e/5.5e list is
  Sorcerer/Warlock/Wizard, but this codebase only has a Wizard caster) — learnable via the normal
  level-up spellbook-growth picker, castable from real spell slots, and has its own
  `Scroll of Darkness` (`scripts/items/CLAUDE.md`'s "Scroll of &lt;Spell&gt;"). It's listed in
  BOTH `LEVELED_SPELL_IDS` and `ELF_LINEAGE_SPELL_IDS` — Drow's own level-5 lineage grant and the
  normal learn/slot-cast path are independent and both work regardless of how the spell was
  acquired, same "no separate copy needed" precedent as High Elf's Misty Step/Tiefling's Fire
  Bolt reuse.
  **Casting on an object**: 5e RAW lets Darkness be cast on an unattended object instead of a bare
  point, ending early if that object is picked up. `GameState.darkness_item` (mirrors the Light
  cantrip's own `light_source_item` tracking) records the specific unattended floor `Item` at
  `darkness_pos` at cast time (`dungeon_floor.get_item_at(center)`, null for a bare-point cast or
  one on a worn/equipped/carried item, since those never show up there) — `DungeonFloor.
  update_fog()` checks every recompute whether that exact item is still at `darkness_pos` and
  calls `GameState.clear_darkness()` (+ ends Concentration) the instant it isn't, same cadence and
  mechanism as the Light cantrip's own auto-expiry. **Still doesn't follow the object if merely
  moved elsewhere on the same floor** (only "picked up" is covered, not "relocated") — a smaller,
  documented scope cut than before, not the full RAW "follows the object" behavior.
  **Dispels overlapping light**: `SpellEffects._darkness_dispel_overlapping_light()` (called from
  `_resolve_darkness()` right after the zone is placed) checks whether the new Darkness zone's
  circle overlaps the Light cantrip's own glow (`GameState.light_source_pos`,
  `GameState.LIGHT_SOURCE_RADIUS`) — a level-0 spell, i.e. "level 2 or lower" per Darkness's own
  text — and calls `GameState.clear_light_source()` if so. A lit Torch's passive glow is NOT a
  spell and is therefore untouched by this check.
- **Detect Magic** (`_detect_magic()`, Divination, level 1, Ritual, SELF, AUTO_HIT, Concentration
  up to 100 turns, `shape_size` reused as a flat Chebyshev radius of 3): now a real, independently-
  learnable `SpellDb.LEVELED_SPELL_IDS` entry too (`class_list = ["WIZARD"]` — real 5e/5.5e list is
  Bard/Cleric/Druid/Paladin/Ranger/Sorcerer/Warlock/Wizard), not just a High Elf lineage-only spell
  — a real `Scroll of Detect Magic` exists now that it's a normal `LEVELED_SPELL_IDS` entry.
  **No longer a one-shot instant read** (that version's own item-qualifying rule —
  `Item.requires_attunement`, or a nonzero `bonus_ac`/`bonus_damage` — is unchanged, just reused
  continuously instead of once): `SpellEffects._resolve_detect_magic()` sets `stats.
  concentration_spell_id = "detect_magic"` and `Stats.detect_magic_turns = 100`, ticked in
  `player.gd`'s per-turn block alongside Fog Cloud/Darkness. While active,
  `DungeonFloor._update_detect_magic_markers()` (called from `update_fog()`, same pooled-`Sprite2D`
  convention as Dwarf Stonecunning's tremorsense ping — see "Dwarf" above) shows a pulsing **blue**
  dot over every qualifying magic item within `DETECT_MAGIC_RANGE` (3) tiles of the player,
  sight-independent exactly like Tremorsense (works through walls/Blinded — never checks
  `_visible_tiles`/`is_blinded()`).
  **Ritual casting**: `Spell.is_ritual` (`scripts/items/spell.gd`) — cast for free, no spell slot
  spent, PROVIDED no enemy is currently hunting the caster (`Player.is_being_pursued()`, checks
  every live enemy on the floor for `behavior in [CHASING, SEARCHING]`, not just those in FOV);
  costs a real slot the instant one is. Real 5e ritual casting also takes 10 extra minutes — this
  engine has no clock to hang that on, so it's simplified to just the "no slot, unless pursued"
  half. Checked at three chokepoints: `PlayerSpellcasting.begin_cast()`/`cast_direct()` (skip the
  slot-availability gate entirely so casting is never blocked by an empty slot pool while
  ritual-free) and `_cast_level_for()` (returns `spell.level` without touching `slot_pool`) —
  `SpellEffects._consume_slot()` also short-circuits before ever touching a slot when
  `spell.is_ritual and not player.is_being_pursued()`, mirroring the Elf/Tiefling/Gnome
  free-cast-per-long-rest checks' own "check first, before ever touching `caster.slot_pool`" shape.
- **Misty Step**: no new code — High Elf's level-5 grant is the exact same spell id
  (`"misty_step"`) Wizard/Ranger already cast, just delivered via the lineage-grant path instead of
  learning it normally.
- **High Elf's long-rest cantrip swap** (level-1 benefit, Wizard-only in practice — see below):
  `GameState.is_high_elf_caster()` / `high_elf_known_cantrips()` / `high_elf_learnable_cantrips()` /
  `swap_high_elf_cantrip(old_id, new_id)` — erases a known+prepared cantrip and its ability-bar
  entry, learns a new one from `SpellDb.CANTRIP_IDS` not yet known, re-preparing it if the old one
  was prepared (updates the Special slot too if it pointed at the swapped-out cantrip). UI:
  `scripts/ui/high_elf_cantrip_swap.gd` (two-round card picker, modeled on `cantrip_select.gd`),
  reachable only from the long-rest hub (`scripts/ui/CLAUDE.md`'s "Long-rest hub" section) — an
  extra "High Elf Cantrip Swap" option shown only when `is_high_elf_caster()`. A non-caster High
  Elf has nothing to swap (cantrips don't exist for any other class) — the option simply never
  appears, a documented no-op rather than a dead button.
- **Wood Elf's 35 ft speed** (level-1 benefit): approximated as a duty cycle rather than a
  distance, same reasoning as an `Enemy`'s own `"speed"` pool key (see "Movement speed scaling"
  below) — `Player._consume_duty_cycle("wood_elf", 1, 6)` (backed by the shared
  `Player._speed_gate_accum` dict, see that section) fires every 6th real move, at which point it
  doesn't cost the turn (`_try_move()`'s free-move check, alongside Expeditious Retreat/Longstrider
  — see the next entry). **Scope limitation**: only wired into `_try_move()` (single-step WASD
  movement), same documented gap as Expeditious Retreat/Battlefield Expert R3 — the
  queued-path/chase-to-target movement functions don't check it.
- **Longstrider** (`_longstrider()`, Transmutation, level 1, touch (`range_tiles = 1`, arm-then-
  any-click-confirms-on-yourself — same "no ally-buff targeting exists" self-only scope as Mage
  Armor/Invisibility), AUTO_HIT, NOT Concentration): now a real, independently-learnable
  `SpellDb.LEVELED_SPELL_IDS` entry too (`class_list = ["WIZARD"]` — real 5e/5.5e list is
  Bard/Druid/Ranger/Wizard), not just a Wood Elf lineage-only spell — a real
  `Scroll of Longstrider` exists now. RAW is a flat +10 ft speed buff (+1/3 over the 30 ft
  baseline), so — unlike Expeditious Retreat, which is genuinely a Dash-as-bonus-action double
  move — it uses the same duty-cycle mechanism as Wood Elf's 35 ft speed / Goliath's Large Form
  +1/3 movement: `Player._consume_duty_cycle("longstrider", 1, 3)` fires every 3rd real move while
  `longstrider_turns > 0`, at which point it's free (`_try_move()`'s free-move check, its own
  branch alongside — not sharing a flag with — Expeditious Retreat/Wood Elf's own counters).
  **Bugfix**: this used to incorrectly share Expeditious Retreat's "first move each turn is free"
  mechanism, which granted far more than +1/3 (effectively doubling movement on any turn the
  player moved on consecutive real turns). Shown in the HUD status tray (`"longstrider"` entry,
  `scripts/ui/CLAUDE.md`) with a hover tooltip naming the +1/3 effect and turns remaining.
  `Stats.longstrider_turns` (600 — 5e RAW's "1 hour", was 100 before this spell was
  promoted to a real learnable entry — ticked in `player.gd`'s per-real-turn block, NOT serialized
  — mid-floor buff state, same precedent as `expeditious_retreat_turns`).
- **Pass Without Trace** (`_pass_without_trace()`, Abjuration, level 2, SELF, AUTO_HIT,
  Concentration id `"pass_without_trace"`): now a real, independently-learnable
  `SpellDb.LEVELED_SPELL_IDS`/`RANGER_SPELL_IDS` entry too (`class_list = ["RANGER"]` — real
  5e/5.5e list is Druid/Ranger; Druid isn't a playable class in this engine yet), not just a Wood
  Elf lineage-only spell. RAW is a 3-tile emanation granting +10 Stealth to every friendly
  creature inside it; this engine only has a Stealth-vs-Passive-Perception check for the player,
  so the emanation/multi-creature text is flavor only — `Stats.pass_without_trace_turns` (600 —
  was 100 before this spell was promoted to a real learnable entry, same "was 100, promoted to a
  real RAW-duration entry" pattern as Longstrider above) grants a flat
  `Stats.PASS_WITHOUT_TRACE_BONUS` (+10) to the Stealth-vs-Passive-Perception roll's `total` in
  `Player._resolve_stealth_check()` while active.

## Orc

Humanoid, Medium (6-7 ft), Speed 1 tile/turn (baseline). Two traits, `Stats.apply_race_defaults()`'s
ORC branch:

- **Superior darkvision** (passive): `darkvision_bonus = 2`.
- **Relentless Endurance** (passive): no ability-bar entry, just a plain check in
  `GameState.check_player_death()` — a hit that would drop the player to 0 HP instead drops them
  to 1 HP, once per long rest (`Stats.relentless_endurance_used`, reset in `long_rest()`). Checked
  after Bruiser R3 (Barbarian talent) — if both are active, Bruiser's own check runs first and
  claims the save.
- **Adrenaline Rush** (ability_id `"adrenaline_rush"`, granted immediately at level 1 via
  `GameState.give_race_starting_items()`/`_restore_race_ability_bar()`, same composition-child-node
  pattern as Dwarf/Dragonborn/Human — `scripts/entities/player_orc.gd`, `PlayerOrc`): free action,
  `proficiency_bonus` uses. **Unlike every other race charge in this file, refills on BOTH a
  completed short rest AND a long rest** (`GameState._on_short_rest_completed()`/`long_rest()`,
  each topping `Stats.adrenaline_rush_uses_remaining` back to `proficiency_bonus` — direct owner
  correction, since real 5e Adrenaline Rush is normally long-rest-only). Activating
  (`PlayerOrc.activate_adrenaline_rush()`) sets `Stats.temp_hp = proficiency_bonus` (flat replace,
  not additive, matching every other temp-HP grant's convention — Natural Sleeper R2, Overheal
  Shield, Ironwood Bark) and arms `PlayerOrc.dash_mode_active` — **reworked, direct owner request**:
  this used to arm a one-shot `Stats.adrenaline_rush_move_free_pending` flag consumed by the
  player's next WASD move (via `TurnManager.revert_to_waiting()`, same free-action pattern as
  Battlefield Expert R3's side-step); it's now an arm-then-click one-tile dash instead, the same
  family as Cloud Giant's Jaunt (`PlayerGoliath.cloud_teleport_mode_active`/
  `resolve_cloud_teleport()`, see "Goliath" below) but clamped to `PlayerOrc.DASH_RANGE` (1 tile):
  clicking an adjacent, visible, walkable, unoccupied tile plays a normal `Entity.move_to()`
  slide-animation onto it (not an instant teleport like Cloud's Jaunt — the visible motion is what
  reads as "you get one move for free," matching the ability's own flavor), entirely outside the
  turn pipeline (no `TurnManager.begin_player_action()`/`revert_to_waiting()` call at all, since
  there's no real move to make free — the dash never touches the turn economy in the first place).
  **Direction can be picked two ways**: a mouse click (arm-then-click, same as Cloud's Jaunt) OR a
  WASD/arrow key press — direct owner request, mirroring how Thief Tools primed lets a directional
  bump complete the action instead of just moving. `_try_move(dir)` checks
  `_orc.dash_mode_active` right after computing its own `target` tile and, if armed, consumes the
  flag and resolves the dash there instead of a normal move (same "the primed mode owns this
  direction press, not a plain move" pattern the pre-existing Thief-Tools-primed-bump branch a few
  lines below it already uses) — the movement-key handler's own cancel-on-move sweep explicitly
  skips `dash_mode_active` for the same reason it already skips a primed Thief Tools item, leaving
  `_try_move()` as the sole place that consumes or resolves it for a keyboard press. Cancels for
  free (nothing spent) via Esc or clicking anywhere invalid — same "charge only spent on a
  confirmed resolution" convention as Cloud's Jaunt/Halfling Nimbleness.
  `PlayerOrc.get_rewind_fields()`/`set_rewind_fields()` capture the armed state for Backspace, same
  as `PlayerGoliath`'s own `cloud_teleport_mode_active`. Proficiency-bonus level-up crossings
  (5/9/13/17) grant +1 CURRENT use immediately, mirroring Breath Weapon/Stonecunning's identical
  treatment.

## Aasimar

Humanoid, Small or Medium (2-7 ft), Speed 1 tile/turn (baseline). `Stats.apply_race_defaults()`'s
AASIMAR branch:

- **Celestial Resistance** (passive): `damage_resistances = ["Necrotic", "Radiant"]` —
  unconditional, no `race_variant` choice (unlike Tiefling's legacy-picked single resistance).
- **Darkvision +1** (passive).
- **Light Bearer** (passive grant, not an ability): the Light cantrip (`SpellDb`'s existing
  `"light"` entry, unchanged — see "Wizard spellcasting" above) is granted directly onto the
  ability bar at race select (`GameState.give_race_starting_items()`'s AASIMAR branch,
  `_build_spell_ability("light")`) — works for any class, even a non-caster, same "spell ability
  outside the normal known_spells/prepared_spells bookkeeping" shape every other race-granted
  spell in this file uses.
- **Healing Hands** (ability_id `"healing_hands"`, granted immediately at level 1): unlike every
  other race ability in this file, **costs the player's action** (not a free action) — 1 use,
  refilled on long rest. Arm-then-click targeting (`scripts/entities/player_aasimar.gd`,
  `PlayerAasimar`): since no general ally-targeting system exists in this engine (only two valid
  touch targets exist — the player themselves, or the Wild Heart Companion — same "narrow case,
  not the full system" limitation as Mage Armor/Invisibility's own touch-self-only scope), the
  click's only job is picking between them: clicking the Companion's own tile heals it, any other
  click heals the player. Heals `proficiency_bonus`d4 HP — `proficiency_bonus` SEPARATE d4 dice
  rolled and summed (e.g. 2d4 or 3d4), **not** one d4 roll scaled by the multiplier (**bugfix**:
  the original implementation read "d4 × proficiency bonus" as a single 1-4 roll multiplied by the
  bonus, a much smaller expected value and much narrower variance than the real dice pool it's
  meant to represent — `PlayerAasimar.resolve_healing_hands()` now calls `Rng.roll_dice(prof, 4)`
  and sums every roll, same shape as any other multi-die damage/heal roll in this codebase).
- **Celestial Revelation** (ability_id `"celestial_revelation"`, granted the instant
  `character_level` reaches 3 — `gain_exp()`'s `old_level < 3 and character_level >= 3` check
  re-runs `give_race_starting_items()`, idempotent, same pattern as Dragonborn's Draconic Flight
  unlocking at level 5): free action, 1 use per long rest. **Opens a 3-option click-to-choose
  picker overlay** (`scripts/ui/celestial_revelation_picker.gd`, `GameState.mastery_picker_open` as
  its input-blocking flag, same reused-shared-modal-gate precedent as `high_elf_cantrip_swap.gd`/
  `attunement_picker.gd`) — **bugfix/redesign, direct owner request**: the original
  arm-cycle-cancel-then-click-anywhere flow (1st press arms Heavenly Wings, 2nd press cycles to
  Inner Radiance, 3rd to Necrotic Shroud, 4th cancels, any world click confirms whichever was
  currently selected) silently rotated through the 3 choices with nothing on screen ever showing
  what was even on offer. The picker shows all 3 as plain text cards (no icon art yet — each
  card's full description is a native `Control.tooltip_text`, hover to read, same "i-badge"
  convention `class_select.gd`'s info icon uses) side by side; clicking one calls
  `PlayerAasimar.resolve_celestial_revelation_choice(transform_idx)` directly and the picker frees
  itself — Esc cancels for free (nothing is spent — the long-rest use/turns/transform are only set
  inside `resolve_celestial_revelation_choice()`, called only from a card click). On confirm:
  `Stats.celestial_revelation_turns = 10`,
  `Stats.celestial_revelation_transform` records the choice (`Stats.AasimarTransformation` —
  **not** stored in `race_variant`, which is fixed at race select; this is chosen fresh every
  activation), `Stats.celestial_revelation_bonus_used_this_turn = false`.
  - **"First damage each turn" bonus**: `player.gd._bump_attack()` gained a `cr_actual`/`cr_inst`
    block mirroring Judgement Day/Torch/Hunter's Mark's own "second, independent same-hit damage
    instance" shape (see "Damage types / resistances" above) — while
    `celestial_revelation_turns > 0` and `not celestial_revelation_bonus_used_this_turn`, the flag
    is consumed and a flat `proficiency_bonus` bonus instance (Radiant, or Necrotic for Necrotic
    Shroud) is dealt alongside the primary hit, with its own floater/tooltip/log segment. Reset to
    unconsumed every real player turn in `_on_turn_started()` (10-turn duration ticked the same
    "100-turn buff" way as `draconic_flight_turns`/`invisibility_turns`, just a shorter window) —
    so it's genuinely per-turn, not a one-shot pending flag like Judgement Day. **Scope
    limitation**: only wired into this primary melee hit, same documented gap Ironwood
    Bark/Judgement Day/Torch's own Fire bonus already have (not ranged/spell/off-hand/cleave).
  - **Heavenly Wings**: sets `Stats.draconic_flight_turns = maxi(draconic_flight_turns, 10)` —
    **reuses Dragonborn's own field/mechanism outright** rather than a separate copy (chasm
    crossing, no grass trample, no trap trigger, immune to standing-fire damage, ticked by the
    same `draconic_flight_turns` countdown in `player.gd`'s `_on_turn_started()`) — the "no
    separate copy needed" precedent High Elf's own Misty Step reuse already established.
  - **Inner Radiance**: on activation, deals `proficiency_bonus` Radiant damage to every enemy
    within 2 tiles (Chebyshev, via `Enemy.min_dist_to()`) — a self-centered instant burst, mirrors
    Thunderclap's shape. **Re-bursts at the end of every subsequent turn, not just once on
    activation** (`PlayerAasimar.tick_inner_radiance()`, called from `player.gd`'s
    `_on_turn_started()` tick block right after `celestial_revelation_turns` decrements, guarded on
    `celestial_revelation_transform == INNER_RADIANCE` — **bugfix/redesign, direct owner request**:
    the burst used to fire only once, at the moment of activation, so 9 of the 10 turns of "Inner
    Radiance" delivered no actual passive damage at all). **Also grants +2 FOV radius for the full
    10-turn duration** —
    `GameState.celestial_radiance_fov_bonus()`, folded into `effective_fov_radius()` **before**
    `darkvision_bonus` in the sum (same "own light source" conceptual slot the equipped-Torch
    bonus occupies) — see `scripts/world/CLAUDE.md`'s "FOV" section for the ring-visual ordering
    (`base → torch → celestial → darkvision`, each its own tinted ring,
    `DungeonFloor._update_celestial_fov_ring_glow()` — a bright celestial gold/yellow, warmer and
    brighter than the torch ring's pale yellow).
  - **Necrotic Shroud**: on activation, every enemy within 2 tiles rolls a CHA check
    (`8 + CHA mod + proficiency_bonus`) — the first Aasimar-specific check stat this engine has
    needed: `Enemy.resist_check_detailed()` gained a `use_cha: bool = false` 7th param (CHA slots
    into the existing DEX > WIS > INT > ... priority chain, now `DEX > WIS > INT > CHA > CON >
    STR`) — a failed check applies `Enemy.frightened_turns` (new field, `apply_status("frightened",
    turns)`, `Enemy.frightened_source = player`). **Now a real mirror of player-side Frightened**
    (see "Conditions" below): DISADV on the enemy's own attack rolls AND checks, but ONLY while
    `frightened_source` is in LOS (`Enemy._frightened_active()`), plus a genuine
    can't-willingly-move-closer-to-the-source movement block (`Enemy._frightened_blocks_step()`,
    wired into `_act_toward_single_step()`'s greedy+BFS stepping). **Still simplified vs. RAW** in
    one respect: fixed 2-turn duration, not RAW's "until the end of your next turn" and no repeated
    save — same documented-simplification precedent as Mind Sliver's penalty die. Ticked once per
    real enemy turn in `decide_turn()` alongside `enfeeble_turns`/`faerie_fire_turns`
    (`frightened_source` is cleared the instant the counter reaches 0).

## Tiefling

Humanoid, Small or Medium (3-7 ft), Speed 1 tile/turn (baseline). `Stats.apply_race_defaults()`'s
TIEFLING branch:

- **Darkvision +1** (passive): `darkvision_bonus = 1`.
- **Fiendish Legacy**: at race select the player picks one of three legacies
  (`Stats.TieflingLegacy` — ABYSSAL/CHTHONIC/INFERNAL, stored in `race_variant` like
  `ElfSubrace`/`DragonbornAncestry`), which grants a damage resistance (`Stats.
  TIEFLING_LEGACY_RESIST[legacy]` — Poison/Necrotic/Fire) plus one spell each at character levels
  1, 3, and 5:

  | Legacy | Resistance | Level 1 (cantrip) | Level 3 | Level 5 |
  |---|---|---|---|---|
  | Abyssal | Poison | Poison Spray | Ray of Sickness | Hold Person |
  | Chthonic | Necrotic | Chill Touch | False Life | Ray of Enfeeblement |
  | Infernal | Fire | Fire Bolt | Hellish Rebuke | Darkness |

  Fire Bolt (the existing Wizard cantrip), False Life (existing Wizard leveled spell), and
  Darkness (the existing Drow Elf lineage spell, see "Elf" above) are reused verbatim — no
  separate copy, same "no separate copy needed" precedent as High Elf's own Misty Step reuse. The
  other five (Poison Spray, Chill Touch, Ray of Sickness, Hold Person, Ray of Enfeeblement,
  Hellish Rebuke) are new `SpellDb` entries, `TIEFLING_LEGACY_SPELL_IDS`
  (`scripts/items/CLAUDE.md`'s spellcasting-data section).

  **Mechanism is a direct clone of Elf's Elven Lineage** (see "Elf" above) — same ALWAYS-PREPARED
  ability-bar grant outside `known_spells`/`prepared_spells`/`SpellcasterState` bookkeeping (works
  even for a non-caster class, e.g. a Tiefling Barbarian), same 1-free-cast-per-long-rest counter
  economy (`Stats.tiefling_legacy_spell_ids`/`tiefling_legacy_free_casts_remaining`/
  `is_tiefling_legacy_free_cast_available()`, checked in `SpellEffects._consume_slot()` right
  alongside the Elf check, refilled to `1` in `GameState.long_rest()`), and the same dedup-against-
  an-already-learned-spell migration (`GameState._migrate_spell_out_of_known_bookkeeping()`, see
  "Elf" above's "Dedup against a spell already learned normally" note) — same three-threshold grant timing
  except the level-1 cantrip is handed out immediately at race select
  (`GameState.give_race_starting_items()`'s TIEFLING branch) rather than waiting for a level-up —
  levels 3 and 5 are granted from `gain_exp()`'s level-up block exactly like Elf's own level-3/5
  grants. `GameState._tiefling_legacy_spell_for(legacy, threshold_level)` / `_grant_tiefling_legacy_spell(spell_id)`
  mirror `_elf_lineage_spell_for()`/`_grant_elf_lineage_spell()` line for line.
  **Casting ability**: every Fiendish Legacy spell is cast using **whichever of INT/WIS/CHA is
  highest** (`Stats.tiefling_best_ability_mod()`), never the character's own class
  `spellcasting_ability` (a Tiefling Barbarian has none at all; a Tiefling Wizard's own INT might
  not even be the best of the three) — `SpellEffects._attack_bonus()`/`_save_dc()`/
  `_cast_ability_mod()` all gained an optional `spell: Spell = null` parameter (every call site
  already had `spell` in local scope) checked before the normal `stats.caster`/INT-fallback path:
  whenever `spell.spell_id in stats.tiefling_legacy_spell_ids`, the Tiefling override wins.
  **Hellish Rebuke is the one exception** to the normal on-demand-cast shape every other Fiendish
  Legacy spell uses — see its own bullet below.

- **Hellish Rebuke is a toggle-armed REACTION, not a normal on-demand cast**: RAW is cast the
  instant a creature you can see hits you, using your reaction; this engine has no
  reaction-casting framework, so `_grant_tiefling_legacy_spell()` special-cases it to grant a
  distinct `"hellish_rebuke_toggle"` ability (`GameState._build_hellish_rebuke_ability()`) instead
  of the usual `"spell:hellish_rebuke"` on-demand-cast ability every other legacy grant gets — now
  shared verbatim with a Warlock who's simply learned the spell normally (`_build_spell_ability()`
  itself special-cases the id, see the "Warlock class" section above). `PlayerTiefling` is
  class-agnostic despite its name — it only ever reads `player.stats` directly, so a non-Tiefling
  Warlock routes through the exact same code.
  Activating it (`PlayerTiefling.activate_hellish_rebuke()`, `scripts/entities/player_tiefling.gd`)
  toggles `Stats.hellish_rebuke_armed` — the exact same "arm now, spend the charge only when it
  actually procs" shape as Storm Giant Ancestry's own toggle (see "Goliath" above). **Can't be
  armed with nothing to fuel it**: `PlayerTiefling.can_activate_hellish_rebuke()` (bugfix — arming
  used to have no gate at all, so toggling it on with zero free casts AND zero available spell
  slots left it lit forever, since `trigger_hellish_rebuke()` would just log "no charge left" every
  time an attack tried to fire it) requires either a free Fiendish Legacy cast still remaining
  this long rest (Tiefling only) OR the caster's own `slot_pool.can_cast(spell)` — **bugfix**: this
  used to hardcode `caster.slot_pool.remaining.get(1, 0) > 0`, which only works for a slot pool
  that keys level 1 by the literal key `1` (true for Wizard/Ranger, but a Warlock's `PactSlotPool`
  only ever has ONE key — the CURRENT pact slot level, which climbs well past 1 — so this silently
  read as "never any charge" for any Warlock past their first pact-level bump); `can_cast()` is the
  correct, pool-agnostic query every other slot check already uses. Checked only when ARMING
  (turning it OFF is always allowed for free); `GameState.is_ability_usable()`'s
  `"hellish_rebuke_toggle"` case grays the ability-bar slot the same way (same `can_cast()` fix
  applied there too). **`trigger_hellish_rebuke()` itself has the matching fix on the consume side**:
  it now reads `caster.slot_pool.available_level(spell)` for the actual level to
  consume/upcast-scale from, rather than hardcoding `spell.level` (1) into `consume()` — the same
  wrong-key bug the arming checks had, just on the spend path; Pact Magic's own upcast (see this
  file's "Spell upcasting" section) applies to this reaction exactly like any other Warlock cast.
  While armed,
  `enemy.gd._attack_player()` checks right after a landed hit lands (`actual > 0`): if the
  attacker is within the spell's own `range_tiles` (3) and currently visible
  (`DungeonFloor.has_line_of_sight()` — a live geometry check, not the cached `is_tile_visible()`
  fog snapshot, which is only refreshed by the player's own actions and can be stale for an enemy
  that moved into sight and attacked in the same round; bugfix, see below), the armed flag disarms
  and `SpellEffects.
  trigger_hellish_rebuke(player, attacker, dungeon_floor)` fires — no attack roll of its own, just
  a DEX save (`resist_check_detailed(dc, ..., use_dex=true, magical=true)`) at the same Tiefling
  best-ability-mod DC every other legacy spell uses, dealing 2d10 Fire (half on a success) to the
  attacker via `take_typed_damage()`. Consumes the same free-cast-per-long-rest counter economy as
  any other Fiendish Legacy spell (`Stats.is_tiefling_legacy_free_cast_available()`, decrementing
  `tiefling_legacy_free_casts_remaining["hellish_rebuke"]`, falling back to a
  real spell slot for a Wizard/Ranger caster once spent) — if neither is available the reaction
  just can't fire yet and stays armed for the next opportunity (though the arm-time gate above
  makes this rare in practice — it can still happen if a slot gets spent on something else between
  arming and the reaction firing). Not serialized
  (`hellish_rebuke_armed`, combat-transient, same tier as `giant_ancestry_armed`). **Trigger gate**
  is `"hellish_rebuke" in tiefling_legacy_spell_ids` alone — that array only ever contains it via
  `_grant_tiefling_legacy_spell()`, a Tiefling-only grant in normal play, so it's already the
  correct, sufficient check. **Bugfix**: a redundant `character_race == TIEFLING` clause used to
  also be required, which silently blocked it from ever firing once the debug panel's Give Spell
  (`scripts/ui/CLAUDE.md`'s "Debug panel") made it grantable to a non-Tiefling test character —
  removed.

- **New spell mechanics introduced for this race** (documented simplifications, matching this
  codebase's established "narrow case, not the full system" precedent):
  - **`SpellEffects.cast_leveled_save_at_enemy()`** — a new shared resolver, the leveled
    counterpart to `cast_cantrip_save_at_enemy()` (single-target SAVE resolution + real spell-slot
    consumption; no such leveled shape existed before Hold Person needed it — Hellish Rebuke no
    longer goes through this resolver at all, see its own bullet above).
    `Spell.dice_count <= 0` (Hold Person) is a pure debuff with no damage roll at all; a future
    damage-dealing `ENEMY`/`SAVE` leveled spell would deal damage halved on a successful save
    (`spell.save_for_half`) through the same resolver — no current spell exercises that branch
    (Hellish Rebuke used to, before it became a reaction; see above). Wired into
    `PlayerSpellcasting.try_cast_at()`'s `ENEMY`/`SAVE` branch.
  - **Poison Spray and Chill Touch are now ALSO real, independently-learnable `SpellDb.CANTRIP_IDS`
    entries** (`class_list = ["WIZARD"]`), not just Tiefling-lineage-only — same "promoted to a
    real learnable entry" pattern as Darkness/Detect Magic/Longstrider/Pass Without Trace under
    "Elf" above; both are still ALSO listed in `TIEFLING_LEGACY_SPELL_IDS`, the sub-race's own
    free grant and the normal known-cantrip/Special-slot path are independent and both work
    regardless of how the cantrip was acquired. Reworked off their original spec to a real
    "ranged/melee spell attack" per direct owner correction — **Poison Spray** is now
    `Resolution.ATTACK_ROLL` (was `SAVE`/CON), range 2 (was briefly 3, corrected back to 2),
    otherwise unchanged (1d12 Poison, tier-scaling, no `effect_id` — a plain generic-damage-path
    cantrip, same shape as Fire Bolt).
    **Chill Touch** is now range 1 (touch, was 6) and 1d10 (was 1d8); `effect_id = "chill_touch"`
    is a new dispatch case in `SpellEffects.cast_spell()` (the shared ATTACK_ROLL cantrip
    resolver) — on a hit, sets `target._regen_blocked_this_round = true`, reusing the exact same
    flag `take_typed_damage()`'s `"regeneration"`-trait shutoff check already writes (see the
    schema's `"traits"` row above) so the target's next `_tick_regeneration()` tick is skipped —
    the "can't regenerate any HP until your next turn" clause, for the one concrete regen
    mechanism this engine has. Doesn't block healing from any OTHER source (potions, Zealot
    Strike, an enemy trait not modeled as `"regeneration"`) — documented simplification, same tier
    as the pre-existing "no Undead-matchup bonus" note. `PlayerSpellcasting.try_cast_at()`'s
    level-0 dispatch generalizes off `spell.resolution == Spell.Resolution.SAVE`/`ATTACK_ROLL`
    rather than a hardcoded id list, so both reworked cantrips route correctly with no dispatch
    changes needed.
  - **Ray of Sickness** (`cast_leveled_attack_at_enemy()`'s `"ray_of_sickness"` effect_id case,
    range 3): ATTACK_ROLL + 2d8 Poison damage exactly like Chromatic Orb; on a non-lethal hit the
    target is automatically Poisoned — **no save** — approximated as a fixed 2-turn duration (RAW:
    "until the end of your next turn", same simplification precedent as Mind Sliver's own penalty
    die). Reworked from an earlier version that gated the Poisoned application behind a secondary
    CON save — the poison is now unconditional on a hit, per direct owner correction. Shown on
    Ctrl-Inspect (`PlayerActions.do_inspect()`'s enemy status suffix — bugfix: `enemy.
    poisoned_condition_turns > 0` used to be missing from that suffix list entirely, so an enemy
    poisoned by this or any other `poisoned_condition` source showed no debuff at all on Inspect).
  - **Ray of Enfeeblement** (`cast_leveled_save_at_enemy()`'s `"ray_of_enfeeblement"` effect_id
    case, range 3): fully reworked from an ATTACK_ROLL-plus-flat-halving spell into a real
    SAVE/CON, Concentration (up to 10 turns, `Stats.ray_of_enfeeblement_turns`/`_target`, same
    generic mechanism as Witch Bolt) debuff with **no direct damage roll at all**
    (`Spell.dice_count = 0`, same "pure debuff" shape as Hold Person). On a successful initial
    save, the target only suffers a minor one-shot Disadvantage on its own next attack roll
    (`Enemy.disadv_next_attack = true`, reused from Grip of the Forest R3) and the spell ends
    there — no Concentration is started. On a failed save, `Enemy.enfeeble_turns = 10` +
    `Enemy.enfeeble_save_dc = dc` arm the full effect: DISADV on the enemy's own STR-based d20
    tests (both its attack roll, in `_attack_player()`'s disadvantage aggregation, and any
    `resist_check_detailed()` call whose resolved stat is STR — both approximated as unconditional
    since this engine doesn't track per-attack ability-score usage for enemies) and `-1d8` (min 0)
    subtracted from every damage roll the enemy makes (`_attack_player()`, replacing the old flat
    "physical damage halved" rule — applies to all damage types now, not just physical).
    **Repeats a CON save at the end of each of the enemy's own turns** (`Enemy.decide_turn()`, vs
    `enfeeble_save_dc`) — a pass zeroes `enfeeble_turns` immediately and ends concentration early
    (no re-application of the initial-success minor disadv); a fail just decrements toward the
    outer 10-turn Concentration backstop ticked on the caster's side
    (`player.gd._on_turn_started()`).
  - **Hold Person** (`cast_leveled_save_at_enemy()`'s `"hold_person"` effect_id case, range 3):
    **Humanoid creature_type only** (5e RAW) — checked at the very top of
    `cast_leveled_save_at_enemy()`, before any turn/slot/animation is spent, since this is a
    targeting restriction (a Fiend/Undead/etc was never a legal target at all), not a resisted
    effect like `condition_immunities` (still legally targeted, just no status applied) — an
    illegal target gets a gray "is unaffected" log line and the cast is a true no-op. A
    failed WIS save, Concentration (up to 10 turns, `Stats.hold_person_turns`/`_target`), sets
    `Enemy.paralyzed_turns = 10` + `Enemy.paralyze_save_dc = dc` — a real, dedicated **Paralyzed**
    condition, distinct from Incapacitated (an earlier version approximated Paralyzed as
    Incapacitated; this rework gives it its own field and its own effect table): skips the enemy's
    entire turn (`decide_turn()`, same shape as `incapacitated_turns`), auto-fails its own
    STR/DEX checks (`resist_check_detailed()` forces `passed = false` outright whenever
    `stat_key in ["str","dex"]`, though Legendary Resistance can still override afterward),
    grants Advantage to every attack made against it (`PlayerVfx.has_advantage()`), and turns any
    HIT made from within 1 tile into an automatic critical hit (`player.gd._bump_attack()` — melee
    is always within 1 tile of its target, so this fires unconditionally there; a natural-1 miss
    still misses, the condition only upgrades an actual hit). **Repeats a WIS save at the end of
    each of the enemy's own turns** (`decide_turn()`, vs `paralyze_save_dc`) — a pass zeroes
    `paralyzed_turns` and ends concentration early; a fail keeps it paralyzed and decrements
    toward the outer 10-turn Concentration backstop, same shape as Ray of Enfeeblement above.
  - **Hellish Rebuke** (`cast_leveled_save_at_enemy()`, damage branch, range 3 — reduced from an
    earlier 6): RAW is a reaction cast the instant a creature hits you; this engine has no
    reaction-casting framework (only Opportunity Attacks/Retaliation exist), so it's a normal
    on-demand cast instead — same simplification Shield's own same-turn manual self-cast already
    established for a spell that's RAW a reaction.

## Gnome

Small, Speed 1 tile/turn, Darkvision +1. `Stats.apply_race_defaults()`'s GNOME branch:

- **Gnomish Cunning**: real 5e text grants ADV on ALL THREE of INT/WIS/CHA saves unconditionally —
  deliberately narrowed to **one** stat, chosen at race select (direct owner decision: all three
  would be too strong, see the design conversation this feature shipped from). Reuses Human's own
  `race_prof_ability` field (STR=0..CHA=5 index) purely as a transport — no new serialized field —
  `Stats.gnomish_cunning_stat: String` ("int"/"wis"/"cha") is re-derived from it in
  `apply_race_defaults()` exactly like `darkvision_bonus` (idempotent, never saved directly).
  `Stats.gnomish_cunning_grants_adv(stat) -> bool` is the single check every save site adds
  alongside its existing Halfling-Brave-style ADV term. **This codebase still has no real "saves
  vs. checks" distinction** (root CLAUDE.md: "all defensive rolls are checks") — rather than build
  one, this trait is scoped to the two existing player-side rolls that already ARE conceptually
  saves (both currently WIS): the repeated end-of-turn Frightened save (`Player._on_turn_started()`)
  and Quasit's Scare save (`Enemy._execute_cast_scare()`) — both already had a Halfling-only ADV
  term, now `or stats.gnomish_cunning_grants_adv("wis")`. Picking INT or CHA is currently dormant
  (no player-side INT/CHA save exists yet, same "granted but nothing to hook into" precedent as
  Elf's Fey Ancestry/Dwarf's Poisoned-check half) — wire in the same `gnomish_cunning_grants_adv()`
  check the moment a real INT/CHA save is added, rather than inventing one just to hang this on.
  Deliberately does NOT touch `search_action()`/`passive_trap_check()` (`player_actions.gd`) even
  though both are WIS-based d20 rolls — those are ability CHECKS (Perception-flavored), not saves,
  and buffing them would be exactly the "too strong" overreach the single-stat restriction was
  meant to avoid.
- **Gnomish Lineage**: the chosen sub-race (`Stats.GnomeLineage` — FOREST/ROCK, picked at race
  select alongside the Cunning stat, both packed into ONE `race_select.gd` sub-choice grid of 6
  combined options — "Forest (INT)".."Rock (CHA)" — since a race with two independent picks had no
  existing UI pattern; see `scripts/ui/CLAUDE.md`'s "Race select" section) grants cantrips
  immediately at race select (unlike Elf/Tiefling's level-3/5 staggering — Gnomish Lineage doesn't
  scale with character level at all): Forest Gnome gets Minor Illusion + Speak with Animals, Rock
  Gnome gets Mending. All three are always-prepared ability-bar grants outside the normal
  `known_spells`/`prepared_spells`/`SpellcasterState` bookkeeping — same mechanism as Elven
  Lineage/Fiendish Legacy (`Stats.gnome_lineage_spell_ids`, `GameState._grant_gnome_lineage_spells()`/
  `_gnome_lineage_spells_for()`, `_restore_race_ability_bar()`'s GNOME branch for save/load replay).
  **Free-cast economy differs from Elf/Tiefling's single free-use bool**: each Gnomish Lineage
  spell is castable **`proficiency_bonus` times per long rest**, not just once (direct owner
  request — a flat "once" felt too weak for a cantrip-tier grant, all-three-unlimited felt too
  strong) — `Stats.gnome_lineage_free_casts_remaining: Dictionary` (spell_id → int, refilled to
  `proficiency_bonus` in `GameState.long_rest()`), `Stats.is_gnome_lineage_free_cast_available(id)`.
  Since all three are cantrips (level 0), there's no real-spell-slot fallback once the counter hits
  0 — `PlayerSpellcasting.begin_cast()` hard-blocks the cast outright (gray log line) rather than
  falling through to a slot check the way a leveled Elf/Tiefling lineage spell would;
  `SpellEffects._consume_slot()` decrements the counter alongside the existing Elf/Tiefling
  free-cast checks. All three resolve via `SpellEffects.cast_leveled_self()`'s SELF/AUTO_HIT branch
  (same shape as Blade Ward/Longstrider):
  - **Minor Illusion**: `Stats.minor_illusion_turns` (10, NOT Concentration) grants a flat
    `Stats.MINOR_ILLUSION_BONUS` (+5) to the Stealth-vs-Passive-Perception roll — a smaller,
    shorter-lived cousin of Wood Elf's Pass Without Trace (+10, 600 turns), ticked the same way in
    `player.gd._on_turn_started()`/read in `_resolve_stealth_check()`.
  - **Speak with Animals**: flavor-only, no mechanical effect (this engine has no animal-dialogue
    system to hook into — same documented-simplification precedent as Elf's inert Fey Ancestry).
  - **Mending**: restores the equipped Main Hand weapon's `uses_remaining` to `uses_max` if it has
    any (a limited-use thrown weapon like a Spear/Handaxe/Dagger) — approximates the real spell's
    "repair a single break/tear" text, since this engine has no separate object-HP system to mend.
    Logs a gray "nothing to mend" line if Main Hand has no `uses_max` or is already full.
  No Scroll of &lt;Spell&gt; exists for any of the three (`SpellDb.GNOME_LINEAGE_SPELL_IDS`) — same
  documented scope cut as the Elf lineage set.

## Goliath

Humanoid, Medium (7-8 ft), Speed 1 tile/turn baseline (flavor text only, like every other race —
see "Movement speed scaling" below the table; only Large Form's own bonus is mechanized). No
darkvision. Composition child-node `player_goliath.gd` (`PlayerGoliath`), instantiated as
`_goliath` in `player.gd._ready()` — same pattern as `PlayerDwarf`/`PlayerDragonborn`. Powerful
Build (ADV to end the Grappled condition) has no hook — no Grappled condition exists anywhere in
this engine, same "granted but nothing to hook into" precedent as Elf's Fey Ancestry.

- **Large Form** (ability_id `"large_form"`, granted the instant `character_level` reaches 5 —
  same level-gate/idempotent-re-grant pattern as Dragonborn's Draconic Flight): free action, up to
  100 turns, 1/long rest (`Stats.large_form_turns`/`large_form_used`). Activating
  (`PlayerGoliath.activate_large_form()`) requires the 2x2 block anchored at the player's current
  tile to be entirely open floor and enemy-free (`_footprint_free()` — terrain via
  `DungeonFloor.is_walkable()`, occupancy via `get_enemy_at()`); refusing with a gray log line if
  not. On success sets `player.size = Vector2i(2, 2)` — **the first time the PLAYER, not just an
  enemy, ever sets `Entity.size` above `(1,1)`** (see "Multi-tile footprint" below). **Click again
  while active ends it early** (`activate_large_form()`'s own re-entry check, rather than a
  separate cancel path — no "arm" phase exists since this is an instant self-buff, same shape
  Draconic Flight would need if it ever gained an early-cancel). While active:
  - **ADV on STR checks**: the only player-side STR check that exists today, the Spider's Web
    escape attempt (`player.gd._attempt_web_escape()`), reads
    `PlayerGoliath.has_large_form_str_adv()` alongside its existing Poisoned/Frightened DISADV
    check, netting ADV/DISADV/flat per the normal cancel rule.
  - **+1/3 movement speed**: reuses Wood Elf's own duty-cycle mechanism (see "Elf" above) via the
    same shared `CombatMath.tick_duty_cycle()` math — `PlayerGoliath._large_form_move_counter`
    (kept local to `PlayerGoliath` rather than folded into `Player._speed_gate_accum`, since it's a
    single implementation, not a duplicate) fires every 3rd real move, at which point it's free
    (`_try_move()`'s free-move check, alongside Expeditious Retreat/Longstrider/Wood Elf's own
    counters). Same scope limitation as those three: only wired into `_try_move()` (single-step
    WASD movement).
  - **Collision (full footprint audit)**: `DungeonFloor.is_walkable_for_enemy()`/
    `is_walkable_for_companion()`/`get_blocking_body_on_line()`/`close_door()`/
    `force_move_entity()`/`resolve_push()` all check `_player.occupies(pos)` instead of
    `_player.grid_pos == pos`, so nothing can walk onto ANY of the 4 tiles a Large-Form player
    occupies. `Enemy._chebyshev_to()`/`_in_attack_range()` and the OA reach check in
    `_check_opportunity_attacks_on_move()` route through the new `Entity.min_dist_to_entity()`
    (checks every occupied tile on BOTH sides) instead of a bare `min_dist_to(e.grid_pos)`, so an
    enemy's attack-range/OA-reach math against a Large-Form player is correct from whichever tile
    is actually closest. **The player's own movement while Large** is validated by
    `PlayerGoliath.blocks_large_form_move(target)`, called from `_try_move()` right after `target`
    is computed (before the existing single-tile enemy-bump/walkability checks) — verifies the 3
    NEW tiles a step into `target` would cover (the 4th, `target` itself, still goes through the
    normal bump-attack/walkability logic unchanged) are open and enemy-free, silently blocking the
    move (like a wall bump) otherwise. **Known simplification, matching this codebase's own
    "documented gap, not a bug" precedent for Ogre's Large footprint**: the queued-path/
    chase-to-target movement functions and `_resolve_enemy_opportunity_attacks()`'s own
    `min_dist_to(prev)`/`min_dist_to(next)` calls still measure against the player's single
    `grid_pos` corner rather than the full footprint mid-move — same "not exhaustively wired"
    scope cut Companion's own AI targeting has against a Large enemy.
- **Giant Ancestry** (ability_id `"giant_ancestry"`, granted immediately at level 1): the player
  chooses one of `Stats.GiantAncestry` (CLOUD/FIRE/FROST/HILL/STONE/STORM) at race select, stored
  in `race_variant` like every other race's sub-choice. `proficiency_bonus` uses per long rest
  (`Stats.giant_ancestry_uses_remaining`) — same grant/restore/sync/level-up-crossing wiring as
  Dwarf's Stonecunning. `GameState._giant_ancestry_name()`/`_giant_ancestry_description()` build
  the ability's flavor text per variant. **Shared "arm now, spend the charge only when it actually
  triggers" shape** for Fire/Frost/Hill/Storm/**Stone** (Stone joined this shape in a redesign, see
  its own bullet below) — activating (`PlayerGoliath.
  activate_giant_ancestry()`) just toggles `Stats.giant_ancestry_armed` on/off, no charge spent yet
  (a second press disarms for free, and the armed toggle persists across as many rounds as it takes
  to actually trigger — it is NOT a one-round window); the charge is only deducted at the moment
  the effect actually fires, so an unused arm — or Fire Giant's own explicit "if it misses, doesn't
  reduce charges" rule — never wastes one. Cloud Giant doesn't fit that shape (it's a one-shot
  instant effect, not something that "triggers" later).
  - **Cloud Giant** (`Cloud's Jaunt`): free action, instant teleport up to 3 tiles to a visible,
    unoccupied, walkable tile — arm-then-click targeting (`PlayerGoliath.
    cloud_teleport_mode_active`, same "hook mode" pattern as Grip of the Forest, wired into
    `player.gd`'s mouse-release handler, Esc/movement-key cancel chokepoints). **The charge is
    spent only on a CONFIRMED teleport** — `resolve_cloud_teleport()` validates range/visibility/
    walkability/occupancy (and, if Large Form is also active, the destination footprint via
    `blocks_large_form_move()`) BEFORE deducting a charge; cancelling (Esc, a movement key, or an
    invalid click) costs nothing. Uses `Entity.set_grid_pos()` (no tween, instant) like Misty Step.
    **Targeting preview** (bugfix — this used to have none at all, same gap Breath Weapon had
    before its own preview was added): `player.gd._update_cloud_teleport_preview()`, hooked into
    `_update_spell_aoe_preview()`'s own `spell == null` fallback chain alongside Breath Weapon/
    Nimbleness — a blue max-3-tile backdrop (`DungeonFloor.show_spell_range_preview()`) plus a
    purple/gray exact-tile highlight on the hovered tile (`DungeonFloor.
    show_touch_target_preview()`, valid only when in range, visible, walkable, and unoccupied) —
    the exact same visual shape Misty Step's own TILE-target preview uses, just fed from
    `PlayerGoliath`'s own armed state instead of a `Spell` resource, since Cloud's Jaunt isn't cast
    through the spell system at all.
  - **Fire Giant** (`Fire's Burn`): armed, the next attack that HITS also deals a second,
    independent 1d10 Fire damage instance — same "one hit, two damage types" shape as Torch/
    Hunter's Mark (`player.gd._bump_attack()`'s `gol_actual`/`gol_inst` block, right after the
    Aasimar Celestial Revelation block). `PlayerGoliath.consume_giant_ancestry_on_hit(enemy)`
    (called only when `actual > 0`, i.e. never on a miss) returns `"Fire"` and consumes the charge
    when this variant is active/armed, else `""` (no-op for every other variant/race). **Melee,
    ranged, and spell attack rolls all trigger it** — `player.gd._bump_attack()`,
    `PlayerRanged.ranged_attack()`, `SpellEffects.cast_spell()` (cantrips), and
    `SpellEffects._resolve_spell_attack_bolt()` (leveled ATTACK_ROLL spells — Chromatic Orb/Witch
    Bolt, primary bolt only, not the leap re-roll) each call `consume_giant_ancestry_on_hit()`
    independently right after their own primary hit lands, same duplicated-per-site pattern as
    Hunter's Mark's own bonus-instance hook. **Skipped outright if the target is already dead by
    the time this check runs** (`not enemy.stats.is_dead()`/`not target.stats.is_dead()`, direct
    owner request) — the primary hit itself, or an earlier same-hit bonus instance already stacked
    on top of it (Judgement Day/Torch/Hunter's Mark/Celestial Revelation, all resolved before this
    block at every call site), can already have killed the target, and there's no point rolling
    bonus Fire/Cold damage — or, worse, knocking a corpse Prone — on something already dead; the
    charge stays unspent in that case (a kill "for free" doesn't cost a Giant Ancestry use). Still
    not wired into Off-hand/Cleave/Opportunity Attacks, same documented scope limitation as
    Torch/Hunter's Mark/Ironwood Bark/Judgement Day/Celestial Revelation's own bonus-instance hooks.
  - **Frost Giant** (`Frost's Chill`): same trigger shape as Fire Giant (melee/ranged/spell alike)
    — armed, the next attack that HITS deals a second, independent **1d6 Cold** damage instance
    (`consume_giant_ancestry_on_hit()` returns `"Cold"`, each call site's own `gol_actual`/
    `gol_inst` block picks a 6- vs 10-sided die off the returned type) **and** applies
    `enemy.apply_status("slowed", 3)` — reuses
    the EXACT same Mud/Water Slowed mechanism every enemy already has (see "Enemy resist checks"
    above's `Enemy.slowed_turns` entry) rather than inventing a new "reduce speed by 1/3" system: a
    slowed enemy sheds roughly one movement step every few turns instead of being stunned outright,
    which is what "1/3 slower" actually means in a 1-tile-per-turn grid. **Bugfix**: this used to
    apply ONLY the Slowed status with no damage instance at all — the real trait text ("the target
    takes 1d6 cold damage and its speed is reduced") was only half-implemented. **Correct
    chronological order**: the Cold damage instance is folded into the main hit line (same segment
    as the primary weapon damage, exactly like Fire Giant's own bonus instance); the "Frost's Chill
    slows X" flavor line is logged separately by `player.gd._bump_attack()` right AFTER that
    combined hit line (`gol_type == "Cold"` check) — damage first, then the slow flavor line.
  - **Hill Giant** (`Hill's Tumble`): same trigger shape, applies the real Prone condition
    (`enemy.apply_status("prone", 1)`, see "Conditions" above) instead of damage — gated on
    `enemy.size.x * enemy.size.y <= 4` ("Large or smaller"; every enemy in this game today is
    Medium or Large-2x2 at most, so this is unconditional in practice, kept for correctness
    against a future Huge+ enemy). See "Conditions" above's Prone row for exactly what the
    condition itself does (melee ADV/ranged DISADV against the target, can't move without standing
    up first, no full-turn skip). **Reordered, direct owner request**: `consume_giant_ancestry_on_hit()`
    applies the Prone status silently (no log) and returns `"Prone"`; every call site's own
    "Hill's Tumble knocks X Prone." flavor line is logged AFTER its primary hit line (same
    `gol_type ==` dispatch pattern as Frost's flavor line above, sitting right next to it as an
    `elif`) — a bonus/reaction effect must never read as having happened before the attack that
    triggered it. **Bugfix**: this line used to log from inside `consume_giant_ancestry_on_hit()`,
    which every call site invokes BEFORE building its own primary hit line — so "X knocked Prone"
    used to print before "You strike X for N dmg," backwards.
  - **Fire/Frost/Hill's own charge-spend timing** — **redesigned, direct owner request**: all three
    now spend the charge (and clear the toggle) only AFTER their own bonus effect has actually
    resolved, matching Stone/Storm's own "effect first, then spend" order — **bugfix**: all three
    used to disarm + decrement the charge BEFORE their bonus effect ran; for Fire/Frost specifically
    that meant the charge was gone before the bonus damage number had even been rolled. All three
    variants' actual effect (Fire/Frost's damage instance, Hill's Prone status) is applied/rolled by
    the CALLER (`player.gd._bump_attack()`/`PlayerRanged.ranged_attack()`/`SpellEffects.cast_spell()`/
    `_resolve_spell_attack_bolt()`, which need the returned type to pick a 1d10-vs-1d6 die and route
    it through `Enemy.take_typed_damage()`, or just to know Hill fired at all), so
    `consume_giant_ancestry_on_hit()` itself never spends anything — the caller calls
    `PlayerGoliath.finish_giant_ancestry_bonus_damage()` right after the bonus damage has actually
    been applied/logged/floater-shown (Fire/Frost) or right after the Prone status is applied
    (Hill, its own flavor line still pending until after the hit line) — that's what actually spends
    the charge and clears `Stats.giant_ancestry_armed`.
  - **Stone Giant** (`Stone's Endurance`) — **redesigned, direct owner request**: now a plain
    toggle, same "arm now, roll/spend only on trigger" shape as Fire/Frost/Hill/Storm, not a
    one-shot arm-and-roll-immediately. Activating just flips `Stats.giant_ancestry_armed` — no roll
    happens yet, so the player genuinely doesn't know the reduction amount until it's actually
    needed. The `1d12 + CON modifier` roll now happens **live, inside
    `GameState.take_damage_raw()`'s own Stone Giant block** (right before the "DR can reduce to 0"
    check), at the exact moment the very next instance of damage lands — only then does it subtract
    from that damage, floor at 0, disarm, and spend the charge. Toggling the ability back OFF
    manually before it ever triggers costs nothing (no charge, no wasted roll) — same free-cancel
    behavior every other armed Giant Ancestry already had. **Bugfix**: the old version rolled (and
    committed to) the reduction amount the instant the toggle was armed, well before any damage was
    taken — contradicting "I don't know how much until it actually happens." **Hoverable roll
    breakdown**: the log line's damage NUMBER itself (not just the "Stone's Endurance" label) now
    wraps in a `[url=stonedr:die=,con=,total=]` tag (`TooltipFormatters.fmt_stonedr_tooltip()`,
    `scripts/ui/hud.gd`'s `_format_tooltip()` dispatch) showing the die roll + CON mod breakdown on
    hover — it used to be a bare, non-hoverable number (and a first pass at this wrapped the LABEL
    text instead of the number, inconsistent with every other hoverable damage number in this
    codebase, which always wraps the number itself — corrected). **Reordered, direct owner
    request**: `take_damage_raw()` no longer logs the "absorbs N damage" line itself — it can't,
    since it's invoked from INSIDE whatever attack resolver is still assembling its own "X hits you
    for N dmg" line (that line hasn't been printed yet), so logging there always printed Stone's
    reaction BEFORE the hit it reacted to, same class of bug Storm's Thunder/Hellish Rebuke used to
    have. The message is now stashed in `GameState._pending_stone_endurance_log` and only actually
    printed by `GameState.flush_stone_endurance_log()`, which every `take_damage_raw()` caller that
    builds its own hit line must call immediately after logging that line — `enemy.gd
    ._attack_player()` (right before the Storm Giant block, so the read order is hit line → Stone
    absorb → Storm reflect), `player_berserker.gd`'s two Frenzy self-damage branches, `spell_effects
    .gd`'s Fireball self-catch, `dungeon_floor.gd`'s standing-in-fire tick, and `player.gd`'s
    status-tick block (no hit line there, so this one flushes immediately, same position it always
    logged from).
  - **Storm Giant** (`Storm's Thunder`): a toggle — `enemy.gd._attack_player()`
    checks `Stats.giant_ancestry_armed` right after damage lands (`actual > 0`), **now also gated
    on the attacker being within 3 tiles** (`min_dist_to(_player.grid_pos) <= 3` — bugfix/redesign,
    direct owner request: this used to fire against "any attacker" at any distance, including a
    ranged/thrown hit from clear across the room, which doesn't read as "lashing back" at all):
    if armed, in range, and this is a Goliath with the Storm ancestry, the ATTACKING enemy takes
    `1d8` Thunder back (`Enemy.take_typed_damage()`), the toggle clears, and a charge is spent — a
    charge that never triggers (no hit lands within range while armed) is never wasted, same
    "spend only on trigger" shape as the other armed variants; the toggle persists across as many
    rounds as it takes. **Correct chronological order** (bugfix/redesign, direct owner request):
    the reflect used to be logged BEFORE the "X hits you for N dmg" line it was reacting to — the
    whole hit-resolution block in `_attack_player()` was reordered so the primary hit/damage log
    (and any `"extra"` second-type instance, e.g. Imp's Sting) always logs FIRST, with the Storm
    Giant reflect (and Hellish Rebuke's own reactive trigger, moved for the same reason) logged
    strictly afterward — "you take the hit, THEN the thunder lashes back," not the reverse.
    **Hoverable roll breakdown**: the reflect damage now goes through the same
    `CombatMath.build_damage_instance()`/`encode_damage_instance()` pipeline every other typed
    damage instance uses (a real `dmg:` meta, `[url=]`-wrapped, hover shows the 1d8 roll + final)
    instead of a bare plain-text number. A killing reflect calls `die()` directly (with its own
    gray-exp-grant/log line, mirroring `DungeonFloor.resolve_push()`'s own inline kill handling)
    rather than routing through `player.gd._finish_kill()`, since the player didn't initiate this
    kill.

## Human

Humanoid, Small or Medium, Speed 1 tile/turn (baseline), no darkvision. Three traits,
`Stats.apply_race_defaults()`'s HUMAN branch:

- **Skillful** (passive): bonus check proficiency in one ability score of the player's choosing,
  picked at race select (`Stats.race_prof_ability`, `Stats._grant_ability_proficiency()`) — a
  Human-only sub-choice on `race_select.gd`'s card, same pattern as Elf's sub-race/Dragonborn's
  ancestry picker.
- **Versatile** (passive): gain an Origin feat — **not implemented**, no feat system exists
  anywhere in this codebase (documented gap, same "sourced trait, no hook to grab onto yet"
  precedent as Elf's Fey Ancestry).
- **Resourceful — Heroic Inspiration** (ability_id `"heroic_inspiration"`, granted immediately at
  level 1 via `GameState.give_race_starting_items()`/`_restore_race_ability_bar()`, same
  composition-child-node pattern as Dwarf/Dragonborn — `scripts/entities/player_human.gd`,
  `PlayerHuman`): free action, 1 use, refilled on long rest
  (`Stats.heroic_inspiration_available`, already-existing field). Activating
  (`PlayerHuman.activate_heroic_inspiration()`) arms `GameState.heroic_inspiration_pending` — the
  player's very **next** d20 roll (attack roll, ability check, or save) is forced to a natural 20,
  guaranteeing a critical success/auto-pass, then the flag is consumed. **Guaranteed even under
  Disadvantage**: every hook site overrides the roll's `die` to `20` AFTER Advantage/Disadvantage
  has already resolved its own min/max pick, not by forcing one component die — forcing a
  component alone would still lose to a lower second roll under Disadvantage (direct owner
  correction). Three hook sites cover every player-rolled d20 in the game:
  - `CombatMath.roll_with_adv_disadv()` (`combat_math.gd`) — the single chokepoint shared by all 6
    player attack-roll sites (melee/cleave/off-hand/OA/ranged/thrown), every cantrip/leveled-spell
    ATTACK_ROLL cast (`spell_effects.gd`), and the player's own repeated Frightened save
    (`player.gd._on_turn_started()`) and initial Scare save (`enemy.gd._execute_cast_scare()`) —
    `CombatMath.consume_heroic_inspiration()` is called once inside it, after `die` is already
    resolved, forcing `die = 20` when it fires. Returns a `"heroic"` key alongside the existing
    `"lucky"` (Halfling Luck) one.
  - `Player._resolve_stealth_check()` — consumed once per check (not per-observer, since the roll
    is "rolled once, reused against every observer" per that function's own convention), forcing
    every observer's resolved `die` to 20 so the player stays hidden from all of them at once.
  - `PlayerThiefTools.attempt_disarm()` — same override on its own hand-rolled final `die`.
  Deliberately does NOT hook Spider's Web save (`enemy.gd._execute_cast_web()`, a bare
  `Rng.roll(20)` not routed through any shared d20 helper) — a pre-existing gap Halfling Brave
  doesn't cover either, not new scope for this feature. A forced natural 20 on an attack roll
  falls through to the existing crit-on-nat-20 handling for free (`CombatMath.is_critical_hit()`);
  on a check/save it just reads as an unbeatable roll — no separate "critical success" concept
  exists for checks in this engine, "guaranteed to pass" is the practical equivalent.

## Halfling

Creature type Humanoid, Size Small, Speed 1 tile/turn (same baseline every entity already moves
at — Small doesn't change movement rate in 5e, only Nimbleness below cares about size at all).
Three traits, `Stats.apply_race_defaults()`'s HALFLING branch (`darkvision_bonus = 0` — the only
race with no darkvision):

- **Luck** (passive, formerly labeled "Halfling Lucky"): see "Halfling Luck" above (the
  ADV/DISADV section) — automatic, must-use reroll of a natural 1 on any player d20 roll.
- **Brave** (passive): Advantage on saves to avoid or end the Frightened condition. Two call
  sites, both a plain `d20 + WIS mod + (proficiency if check_prof_wis)` check that now rolls
  through `CombatMath.roll_with_adv_disadv(1, 0)` (ADV forced on) instead of a bare `Rng.roll(20)`
  when `character_race == HALFLING`: the repeated end-of-turn save in `Player._on_turn_started()`
  ("end" — ticks `Stats.frightened_turns` down early on a pass) and the initial save in
  `Enemy._execute_cast_scare()` (Quasit's Scare, "avoid" — the only source of Frightened today, see
  "Conditions" above and Quasit's own section). Any future Frightened source that rolls its own
  save should route through the same `roll_with_adv_disadv(1 if HALFLING else 0, 0)` pattern rather
  than a bare roll, to stay covered by Brave automatically. **Bugfix**: both sites' `save:` tooltip
  meta used to omit `d1`/`d2`/`adv`/`disadv`/`lucky1`/`lucky2` entirely, so hovering the roll always
  rendered a plain "d20 = N" line with no way to see Advantage actually applying — the roll itself
  was correct, it just wasn't visible. The repeated end-of-turn save also had no hoverable tooltip
  or fail-case log line at all before this fix (only a bare success message); it now logs and wraps
  a `[url=]` breakdown on both outcomes, matching every other repeated-save convention (e.g. Hold
  Person's "remains paralyzed").
- **Halfling Nimbleness** (`"you can move through the space of any creature that is a size larger
  than you"`): **implemented, as an activated ability rather than a move-executor rule** — direct
  owner request. Uses a real D&D size-CATEGORY comparison, not just the physical footprint: every
  `Enemy` now carries `creature_size` (pool key `"size_category"`, see the schema table's own row —
  default `"Medium"` when an entry doesn't set one, since an ordinary 1x1 enemy is exactly as big as
  the Player and therefore already one full category above a Small Halfling; Quasit is the one
  enemy authored as `"Tiny"`, Ogre/Spider `"Large"`). `PlayerHalfling.is_larger_than_halfling(enemy)`
  qualifies anything ranked strictly above Small (Medium/Large/Huge/Gargantuan) OR with a physical
  footprint > 1 tile (belt-and-suspenders in case a future Large+ entry forgets to also set
  `"size_category"`) — so in practice this covers essentially every enemy in the game except Quasit,
  not just the 2x2-footprint pair. Ability id `"halfling_nimbleness"`, granted immediately at
  race select (`GameState.give_race_starting_items()`'s HALFLING branch); composition child-node
  `scripts/entities/player_halfling.gd` (`PlayerHalfling`, `_halfling` on `player.gd`), same pattern
  as `PlayerDwarf`/`PlayerGoliath`. Free action, capped at once per real round
  (`PlayerHalfling.used_this_turn`, reset from `player.gd._on_turn_started()`'s
  `if not came_from_revert:` block — not rest-gated, so `Ability.uses_max` stays 0/infinite; the
  ability bar still greys for this per-round cap via `GameState.halfling_nimbleness_used_this_turn`,
  a mirrored bool `is_ability_usable()` reads, same precedent as Grip of the Forest's own
  `GameState.grip_of_the_forest_used_this_turn`). Activating arms `nimbleness_mode_active` (arm-then-click, same family as
  Grip of the Forest's hook mode/Cloud Giant's Jaunt) and shows a blue backdrop over the 8 tiles
  directly adjacent to the player (`PlayerHalfling.adjacent_tiles()`,
  `player.gd._update_nimbleness_preview()` → `DungeonFloor.show_spell_range_preview_tiles()`) with
  a red highlight on the hovered tile whenever it holds a targetable enemy that qualifies as
  larger (`show_single_target_preview()`, same red-means-valid-target convention every spell
  preview uses). Clicking a qualifying tile (`PlayerHalfling.resolve_nimbleness()`) walks out along
  the same direction from the player through the target's own `occupied_tiles()` until clear, then
  teleports the player there (`Entity.set_grid_pos()`, no tween, same instant-move convention as
  Misty Step/Cloud Giant's Jaunt) if that landing tile is walkable and unoccupied — otherwise logs
  "no room to come out the other side" and spends nothing (the per-round flag, like Cloud Giant's
  charge, is only consumed on a CONFIRMED slip-through). Esc, any movement key, and re-pressing the
  ability slot all cancel the armed mode for free, same chokepoints as every other arm-then-click
  ability. Genuine RAW movement-integration ("move through as part of a normal step, no separate
  activation") is still not implemented — this ability is the whole feature as shipped, not a
  partial stand-in for a later full rework.

**D&D 2024 size categories** (reference table — `Enemy.creature_size`/pool `"size_category"` now
implements the category names themselves, see Halfling Nimbleness above and the schema table's own
row; this table's area-multiplier column is still unwired to any code, kept for whenever a more
precise footprint system than the current raw w/h `Entity.size` is needed): space/area multiplier
relative to a Medium creature's 1 tile —

| Size | Area multiplier |
|---|---|
| Tiny | 1/4 |
| Small | 1 |
| Medium | 1 |
| Large | 4 |
| Huge | 9 |
| Gargantuan | 16+ |

(Quasit is Tiny, Player/most enemies are Medium, Ogre/Spider are Large 2×2 — matches the `4`
multiplier above.)

## Multi-tile footprint (Large enemies)

`Entity.size: Vector2i` (default `ONE`) gives an entity a real WxH footprint instead of a single
tile — `grid_pos` is always the **top-left** corner. Only `Enemy` (pool `"size": {"w","h"}`, read
in `Enemy._apply_stats()`) and, since Goliath's Large Form, the **Player** (temporarily, while
`large_form_turns > 0` — see "Goliath" above) ever set it above `(1,1)`; Companion stays 1x1
forever. `Entity.min_dist_to_entity(other: Entity) -> int` (new) generalizes `min_dist_to()` to
correctly measure between two POSSIBLY-large footprints (checks every occupied tile on both
sides) — `Enemy._chebyshev_to()` uses it whenever its target `is Entity`, so an enemy's attack-
range/OA-reach math against a Large-Form player is correct regardless of which side of either
footprint is actually closest. First enemy user: `ogre` (2x2, `dungeon_floor_data.gd`).

**Entity API** (`entity.gd`, generic — usable on any `Entity` reference):
- `occupied_tiles() -> Array[Vector2i]` — every tile the footprint covers, top-left first.
- `occupies(pos) -> bool` — is `pos` anywhere inside the footprint.
- `min_dist_to(pos) -> int` — Chebyshev distance from `pos` to the NEAREST occupied tile. The
  generic replacement for "distance to `grid_pos`" everywhere adjacency/range is checked against
  an entity that might be Large — melee/ranged/spell range checks, Opportunity Attack trigger
  radius, and Grip of the Forest's pull-until-adjacent loop all call this instead of hand-rolled
  `maxi(absi(...))` against `.grid_pos` now.
- `nearest_occupied_tile(pos) -> Vector2i` — the specific occupied tile closest to `pos`, used as
  the concrete LOS ray/pathing origin once `min_dist_to()` says "close enough" (e.g. `Enemy._can_see_entity()`'s
  `has_line_of_sight()` origin, `PlayerRanged.is_in_ranged_range()`'s LOS/range target, the
  player's enemy-chase click pathing to whichever side of the footprint is nearest instead of
  always circling to the top-left corner).
- `_tile_center(pos)` (already existed) now centers on the WxH block anchored at `pos`, so a Large
  enemy's sprite renders centered on its own footprint, not offset toward one corner.

**Collision/targeting** (`dungeon_floor.gd`): `is_walkable_for_enemy(pos, excluding)` and
`get_enemy_at(pos)`/`get_targetable_enemy_at(pos)`/`is_walkable_for_companion(pos)` all check
`enemy.occupies(pos)` instead of `enemy.grid_pos == pos` — so a click, bump-attack, or companion
avoidance check on ANY of the 4 tiles resolves to the Large enemy. `excluding` (new optional param
on `is_walkable_for_enemy`) lets a mover's own current tiles never falsely block its next step.
`is_area_walkable_for_enemy(top_left, size, excluding)` is the multi-tile counterpart — every tile
of a WxH block must independently pass `is_walkable_for_enemy`; `Enemy._footprint_walkable(pos)`
wraps it with the enemy's own `size`/self-exclusion and is what every movement decision site
(`_act_toward_single_step`, `_bfs_to`, `_do_roam_walk`, `_do_random_step`, `_flee_from`,
`_pick_roam_target`) now calls instead of the old single-tile `is_walkable_for_enemy()` — a no-op
change in behavior for every 1x1 enemy.

**Spawn placement** (`DungeonFloor._spawn_enemies()`): a Large pool entry (footprint ≠ `(1,1)`,
read via `_enemy_pool_footprint()`) must find a candidate tile where the **entire** footprint is
still-free single-tile-eligible ground (`_footprint_fits()` against the same eligibility set every
1x1 spawn already draws from — not start/stairs-adjacent, not the boss room). A straight 1-wide
corridor can never contain a 2x2+ block of floor tiles, so this alone is what keeps a Large enemy
from ever spawning in one — no separate corridor-detection code needed. If no fit exists this
floor, that spawn slot is skipped outright rather than falling back to a 1-tile placement.
Non-Large spawns are completely unaffected (same shuffled-candidate consumption order as before).

**Forced movement**: `force_move_entity()` and the Heavy Crossbow Push mastery's `resolve_push()`
both branch on `entity.size != Vector2i.ONE` — a Large mover validates its whole footprint via
`is_area_walkable_for_enemy()` at every step instead of the single-tile wall/occupant checks.
`resolve_push()` specifically: the wall-bump-damage and chasm-death special cases are authored for
a single destination tile and don't generalize to a straddling 2x2 block, so a Large target instead
just needs its whole destination footprint to be plain open floor — otherwise the push is a no-op
(too bulky to shove into a wall corner or half over a chasm edge). No enemy uses Push resistance
today, so this hasn't been exercised beyond Ogre.

**Known simplifications** (documented gaps, not bugs): `Companion`'s own AI targeting
(`companion.gd`) still measures distance/adjacency against `enemy.grid_pos` directly, not
footprint-aware — a companion may take one extra approach step against a Large enemy before it's
actually able to attack. `Enemy._move_step()`'s post-move trap/water/grass tile check only looks
at `grid_pos` (the top-left tile), not the full footprint. Sprite `z_index`/HP-bar/notice-mark
vertical offsets are unchanged constants, tuned for 1-tile art — a Large enemy's HP bar sits lower
relative to its (taller) sprite than a normal enemy's. **Player-as-Large (Goliath's Large Form,
see "Goliath" above)**: `DungeonFloor`'s own collision checks (`is_walkable_for_enemy()`/
`is_walkable_for_companion()`/`get_blocking_body_on_line()`/door-close/forced-movement) and
`Enemy._chebyshev_to()`/`_check_opportunity_attacks_on_move()` are all footprint-aware; the
queued-path/chase-to-target movement functions and `Player._resolve_enemy_opportunity_attacks()`
are NOT (still measure against the player's single `grid_pos` corner) — same "not exhaustively
wired" scope cut as Companion's own AI targeting against a Large enemy above.

## Invisibility

Implemented both as an enemy-side ability (Imp, pool key `"invisibility"` above) and the real
player-castable level-2 Illusion spell of the same name (`SpellDb._invisibility()`,
`spell_effects.gd`'s `cast_leveled_self()` `"invisibility"` branch) — both share the exact same
underlying mechanism, described once here.

- **Duration field**: `Stats.invisibility_turns` (player) / `Enemy._invis_turns` (enemy) — up to
  600 turns (5e RAW's "1 hour", at 6 seconds/round). The PLAYER's own Invisibility **is a real
  Concentration effect** (`concentration_spell_id == "invisibility"`) — mutually exclusive with any
  other concentration spell (casting one breaks the other, same guard every concentration-granter
  opens with in `spell_effects.gd`) and breakable by taking damage via the normal
  `GameState._check_concentration_break()` CON-check chokepoint, exactly like Blade Ward/Witch
  Bolt/Fog Cloud/Darkness/etc. **Bugfix / reversed design decision**: this codebase used to
  deliberately deviate from 5e RAW here (Invisibility genuinely IS Concentration in 5e) to avoid a
  damage-based break — that deviation was reversed on direct request, so a random hit can now end
  it early just like any other concentration spell. `GameState.end_concentration()`'s
  `"invisibility"` branch clears `invisibility_turns`; the natural-expiry and attack/cast-ending
  tick sites (`player.gd`) also clear `concentration_spell_id` back to `""` once the effect is
  actually gone. The enemy side (`Enemy._invis_turns`) has no analogous Concentration mechanic —
  only the player's own casting is affected by this. **Bugfix**: `Player._update_invisibility_visual()`
  (the sprite's translucent-tint toggle) is now called unconditionally once every real turn from
  `_on_turn_started()`, not just from the branches that decrement `invisibility_turns` directly —
  a damage-triggered CON-check break (`GameState._check_concentration_break()`) or a different
  concentration spell's own end-the-old-one guard both correctly zero `invisibility_turns`/clear
  `concentration_spell_id` from `GameState`, which has no `Player` node reference to refresh the
  visual from directly, so the player used to stay visually translucent even after Invisibility
  had mechanically ended.
- **Ending early on attack/cast** (still an ADDITIONAL end condition on top of Concentration, per
  5e RAW's own text): the player's own end-check reuses the Stealth system's existing
  `GameState.stealth_check_skip` flag (already set `true` by every attack/spell-cast call site
  right before its own `begin_player_action()`) — `Player._resolve_stealth_check()` checks it
  first, before the flag is used for its own stealth purpose, and zeroes `invisibility_turns` if
  set. `Stats.invisibility_just_cast` (set by the cast itself) skips this check exactly once so
  casting Invisibility doesn't immediately end itself on its own casting turn — same "just_cast"
  pattern as `witch_bolt_just_cast`. The enemy side's equivalent is simpler: `Enemy._attack_target()`
  checks `_invis_turns > 0` and calls `_end_invisibility()` before dispatching the attack.
- **Not invincible, just unseen**: an invisible creature can still be hit by AoE spells
  (Fireball/Thunderclap — these never target by click, so they're unaffected either way), but NOT
  by bumping into it — walking (WASD or a queued click-path) into an invisible enemy's tile reads
  as a wall bump: `_try_move()` and the queued-path loop in `player.gd` both check
  `Enemy.is_hidden_from_player()` on the raw `DungeonFloor.get_enemy_at()` result and, if hidden,
  silently stop there (no move, no attack, no turn spent, no slash VFX/damage floater to give away
  the tile) instead of falling into the normal bump-attack. This mirrors `is_walkable_for_enemy()`
  always blocking an enemy from landing ON the (possibly invisible) player's tile — invisibility is
  symmetric now: neither side can attack-by-bumping into a tile they can't see is occupied. Every
  DIRECT click-based target resolution was already blocked before this: `DungeonFloor.
  get_targetable_enemy_at()` (returns `null` for an Invisible enemy) is the chokepoint every
  click-to-chase, Frenzy/Limit Break click, Grip of the Forest hook click, spell Ctrl/LMB click, and
  thrown-weapon click goes through instead of the raw `get_enemy_at()`. Net effect: an Invisible
  enemy can now only be damaged by AoE.
- **Enemies losing track of an invisible player**: `Enemy._can_see_entity()` returns `false`
  outright for a target with `GameState.player_stats.invisibility_turns > 0`, regardless of
  distance/LOS — per direct owner design, an unaware pursuer doesn't "try" to track it, it's simply
  gone. This reuses the EXISTING CHASING → reaches `last_known_target_pos` (last spot it was seen)
  → SEARCHING → (gives up after 7 turns) → ROAMING flow with zero new state — the "goes to where it
  vanished, searches briefly, then leaves" behavior the owner asked for falls out for free.
  **Opportunity Attacks and invisibility**: an unseen mover can't provoke a reactive attack from
  someone who has no idea where it is — `Enemy._check_opportunity_attacks_on_move()` (enemy moves)
  returns immediately if `_invis_turns > 0` **or** if `GameState.player_stats.invisibility_turns > 0`
  (the invisible player doesn't get a free reactive swing either — they have no business reacting to
  a fleeing enemy they can't see any better than it can see them), and
  `Player._resolve_enemy_opportunity_attacks()` (player moves) skips the actual attack for every
  enemy whenever `GameState.player_stats.invisibility_turns > 0` (Battlefield Expert's Side Step
  *detection* still runs even while invisible — that's the player's own movement-pattern trigger,
  not an enemy reaction, so it's unaffected).
  **Adjacent-attack suppression**: being unseen also blocks a plain (non-reactive) melee/ranged/
  thrown attack against the invisible player, not just OAs — `Enemy._target_is_untouchable(target)`
  (true for a Player target with `invisibility_turns > 0`) gates `_in_attack_range()` (the chokepoint
  `_act_toward()`'s already-adjacent swing and the cornered-flee counterattack both go through) plus
  the three movement-restricted branches that check adjacency directly instead of via
  `_in_attack_range()` (`rooted_turns`/`frozen_feet_turns`/zero-movement-credit) and the one-shot
  `thrown_weapon` ranged branch. Movement itself already can never land ON the player's tile
  (`is_walkable_for_enemy()` always blocks it regardless of visibility), so an already-CHASING enemy
  that ends up adjacent to an invisible player now just stands there unable to act on it — same
  "lost the trail" feel as `_can_see_entity()`'s false return, extended to cover "stumbled directly
  into them" too.
  **Known gap**: `_select_target()`'s "already-adjacent wins outright" and SLEEPING's true-adjacency
  free-wake in `_decide_action()` still don't go through `_can_see_entity()`/`_target_is_untouchable()`
  — an invisible player standing directly adjacent to an enemy can still be picked as the enemy's
  notional target and can still free-wake a SLEEPING enemy (it just can't be hit — see above), a
  documented simplification rather than an oversight, since covering it would mean threading an
  invisibility check through more unrelated call sites for a corner case (standing right next to a
  hostile enemy while invisible) that's easy for the player to just avoid.
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
its own future design doc). CR-budgeted floor spawning **is** implemented — see the `"cr"` schema
row above and `scripts/world/CLAUDE.md`'s "Spawning" section.

**Ranged distance scaling convention (PERMANENT RULE, locked in)**: converting a D&D 2024 distance
(feet, 5 ft/square) into tiles uses **three separate divisors by content type**, not one universal
ratio — all steeper than a straight D&D-ratio conversion because our grid only grants **1 tile of
movement per turn** (no D&D-style 30 ft move-per-round budget), so anything looser would dwarf how
far a target can actually close distance in a reasonable number of turns and make ranged combat
trivially safe. **Always round UP (`ceili(...)`), never down/nearest**, for every divisor below —
so a short RAW range never collapses below the content type's own floor and loses its identity.

- **Ranged weapons** (`Item.range`/`Item.long_range` — Short Bow/Heavy Crossbow/Longbow — and an
  `"abilities"` pool entry's `range`/`long_range`, see the schema table above) AND **ranged
  spells** (`Spell.range_tiles`, `scripts/items/CLAUDE.md`'s spellcasting-data section) both use
  **`/20`**. This divisor is deliberately anchored close to `Enemy.FOV_RADIUS`/the player's own
  default FOV radius (5, no torch/darkvision/Light/Eagle bonus) — a good ranged weapon's normal
  range should sit right around that number, so the long-range/DISADV tier (weapons only — see
  below) almost never triggers for a character with no vision-extending bonus, but triggers
  immediately the moment they gain one. `long_range` itself is **hand-tuned per weapon, not a
  fixed multiplier of `range`** (current roster: Short Bow 4/16, Heavy Crossbow 5/20, Longbow
  8/30) — pick a value that feels right, don't auto-derive it from a ratio. **`PlayerRanged.
  is_ranged_target_in_range()` has no visibility/FOV requirement at all (direct owner ruling,
  permanent) — a shot is legal purely by distance, out to the weapon's `long_range`; Disadvantage
  (`ranged_shot_disadvantage()`) is the only penalty for a beyond-normal-range shot, same as
  `PlayerRanged.ranged_attack_tile()` already allowed for an untargeted empty tile.** (An earlier
  pass required `is_tile_visible(target_pos)` for any beyond-normal-range shot — "no blind long
  shots into unexplored fog" — but that broke down against Fog Cloud/Darkness obscurement, which
  strips a tile from `_visible_tiles` for anyone not standing inside the cloud regardless of
  actual terrain, silently turning a perfectly legal long shot into an impossible one the instant
  distance ticked past normal range. Removed outright rather than patched around per-case.)
- **Thrown weapons** (Spear/Handaxe/Dagger/Javelin/Torch, same `Item.range`/`Item.long_range`
  fields as ranged weapons, mechanically) use a gentler **`/10`** instead — a thrown weapon swings
  off a melee stat (STR, or `max(STR,DEX)` if Finesse), not a dedicated ranged weapon, so its reach
  is deliberately shorter-scaled than a bow's. Current roster: Spear/Handaxe/Dagger 2/6, Javelin
  3/12, Torch 2/4 (also hand-tuned per weapon, not a fixed ratio).
- **Spell shape/area** (`Spell.shape_size` — Fireball's blast radius, Burning Hands' cone length,
  Fog Cloud's radius) stays **`/10`** for now (Fireball's 20 ft radius → 2 tiles, unaffected by
  this pass) — **not locked in** the way the two divisors above are; re-check with the user before
  assuming `/10` is final when authoring a new AoE spell's `shape_size`, since the same "grid only
  grants 1 tile/turn" argument that already pulled ranged-weapon/spell range down to `/20` could
  eventually pull this down too.

**Single-target reach is always Chebyshev, never Euclidean (bugfix)**: every single-target
max-range gate — ranged weapons (`PlayerRanged.is_ranged_target_in_range()`/
`ranged_shot_disadvantage()`), thrown weapons (`PlayerThrowTool._throw_weapon()`), and Hunter's
Mark (`PlayerRangerTalents.commit_mark()`, plus its own targeting-preview duplicate in
`player.gd._update_hunters_mark_preview()`) used to gate range with squared-Euclidean distance
(`dx*dx+dy*dy <= r*r`) — a circle on the square movement grid, which under-reaches diagonally
versus a cardinal shot at the same tile count (a diagonal step costs the same 1 tile of movement as
a cardinal one everywhere else in this engine). Spells already got this right
(`player_spellcasting.gd`'s `_effective_range()`/`try_cast_at()`, Chebyshev — see that file's own
`dist_cheb` comment) but weapons/Hunter's Mark never got the same treatment. Fixed to Chebyshev
(`maxi(absi(dx), absi(dy)) <= r`) everywhere above, plus their matching preview backdrops
(`DungeonFloor.show_ranged_range_preview()`) — matches `show_spell_range_preview()`'s own
Chebyshev convention. **AoE/zone shapes are intentionally unaffected** — Fireball/Burning
Hands-cone/Faerie Fire/Fog Cloud/Darkness really are D&D spheres/circles by design (see
`DungeonFloor`'s AoE-preview section comment and `scripts/world/CLAUDE.md`'s own note on it) and
still use Euclidean distance on purpose; only single-target max-reach gates were in scope.

**Spells deliberately have NO long-range/DISADV tier** (direct owner decision) — `Spell.range_tiles`
is a single flat number under the `/20` rule above, with no `long_range`/Disadvantage-at-extended-
range mechanic at all. The long-range-then-DISADV D&D flavor stays a weapons-only feature (thrown
weapons included — `Item.range`/`Item.long_range`, `PlayerRanged.ranged_shot_disadvantage()`/
`PlayerThrowTool._throw_weapon()`'s own long-throw check) — don't add an equivalent `long_range`
field to `Spell` or any spell-casting call site.

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

**Player movement-speed visual consistency (PERMANENT RULE)**: whatever affects the PLAYER's own
movement speed (difficult terrain/Slowed → slower, Expeditious Retreat/Longstrider/Wood Elf/Monk
Unarmored Movement/Large Form/Battlefield Expert's free side-step → faster) must NEVER change the visual
tween itself — `Entity.move_to()` is always the same fixed duration regardless of speed status.
The only thing allowed to differ is the turn economy: how many actions the environment (enemies)
gets for that one player move. `TurnManager.enemy_actions_this_round: int` (default 1, always
consumed/reset back to 1 at the top of `_process_enemies()`) is the single knob — set it to `2`
right before the move's own `on_player_action_complete()` call for a Slowed move (enemies get two
full decide-then-execute rounds inside that ONE cycle, via `_process_enemy_round()`/
`_advance_round_or_end()`), or skip `on_player_action_complete()` entirely via
`TurnManager.revert_to_waiting()` for a free move (enemies get zero). **Never call
`begin_player_action()`/`on_player_action_complete()` a second time for the same move** — that
used to be how Slowed was implemented (an extra full begin/complete pair after the first), which
double-fired `player_turn_ending` (double Witch Bolt tick, double Stealth-vs-Passive-Perception
roll on a single slowed step) and visibly flashed the phase back to `WAITING_FOR_INPUT` mid-move,
reading as the player's own character stuttering/freezing rather than "the environment moved
twice." `Player._take_free_move_beat()` (`FREE_MOVE_BEAT_SEC`, 0.08s) is awaited before every
free-move `revert_to_waiting()` for the opposite reason — skipping the enemy phase entirely means
the very next input is available almost instantly, and several free moves in a row without this
beat would visibly warp/jitter across multiple tiles instead of reading as a normally-paced walk
with an invisible opponent. Both `_try_move()` (WASD) and `_execute_queued_path()` (click-to-move
+ enemy-chase, via the shared `_apply_queued_step_speed(next_pos)` helper) apply the Slowed half of
this consistently; the free-move half (Expeditious Retreat etc.) is still `_try_move()`-only, same
pre-existing scope limitation as those talents' own entries above.

**No free-move/Slowed/Exhaustion duty-cycle bookkeeping once the floor has no live enemy, but WASD
walking speed itself stays constant** (reworked — direct owner request reversed the original
bugfix below): every duty-cycle/free-move mechanism above exists solely to change turn ECONOMY
relative to the environment/enemies — with `TurnManager.has_any_enemy() == false` (floor cleared),
there is no environment to race against, so granting a free move (skip enemy phase) or a
Slowed/Exhaustion penalty (double enemy phase) accomplishes nothing except advancing duty-cycle
counters for no reason. Both `_try_move()` and `_apply_queued_step_speed()` check `TurnManager.
has_any_enemy()` first and, if false, skip the ENTIRE free-move/Slowed/Exhaustion block outright —
neither touches `_free_sidestep`/Wood Elf/Longstrider/Monk Unarmored Movement/Large Form/Expeditious Retreat's own
duty-cycle consumption, so their counters don't advance while there's nothing to spend a free move
on. Once a new enemy is registered (`TurnManager.register_enemy()`, e.g. entering a room with
sleepers), every duty cycle resumes exactly where it left off — nothing is reset, just paused.

**The Slowed/Exhaustion `enemy_actions_this_round = 2` penalty is additionally narrowed to "an
enemy is actually pursuing"** (`Player.is_being_pursued()` — any live enemy `CHASING`/`SEARCHING`),
on top of the `has_any_enemy()` gate above. A floor with only unaware (SLEEPING/STATIONARY/ROAMING)
enemies still counts as "has an enemy," so the old code spent the extra enemy round anyway — which
changed nothing the player could observe EXCEPT an irregular hitch in held-WASD walking on every
Nth step (the duty-cycle penalty landing every `1/6 × exhaustion_level` moves), the exact "every
5th step gets stuck" jitter reported for Exhaustion (same class of visual bug the `FREE_MOVE_BEAT_SEC`
beat fixed for the sped-up/free-move case). Now the penalty (and the `_exhaustion_move_penalizes()`
call that consumes the shared duty-cycle accumulator) only fires while a pursuer is racing the
player — during real combat it applies fully and reads as intentional tension; an unthreatened
slowed/exhausted walk paces identically to a normal one. The duty-cycle counter pauses (doesn't
desync) while unthreatened, same "resumes where it left off" behaviour as the `has_any_enemy()`
pause. Both `_try_move()` and `_apply_queued_step_speed()` carry this guard.

**`_try_move()`'s no-enemy branch still pays the `FREE_MOVE_BEAT_SEC` (0.08s) pacing beat** before
completing the round (`await get_tree().create_timer(FREE_MOVE_BEAT_SEC).timeout` right before
`TurnManager.on_player_action_complete()`) — direct owner correction to an earlier version of this
same bugfix, which skipped straight to `on_player_action_complete()` with no beat at all: since
`TurnManager._process_enemies()` resolves synchronously with zero enemies, that made holding WASD
visibly speed up the instant the last enemy on a floor died (no enemy-round overhead left to wait
on), which reads as "the player got faster," not "the environment stopped being in the way." The
added beat keeps WASD's per-tile pace identical whether or not the floor still has enemies on it.
**`_execute_queued_path()` (click-to-move / enemy-chase) deliberately does NOT pay this beat** —
its own per-step body calls `TurnManager.on_player_action_complete()` directly, with no equivalent
check or beat at all, so a cleared floor's click-to-move genuinely does move faster than WASD
(chains at the tween's own 0.08s per tile, back-to-back) — that asymmetry is the intended
"fast only when you click somewhere" behavior, not an oversight to fix.

---

## Stats (`stats.gd`)
`modifier(score) -> int` = `floor((score - 10) / 2)`.
`apply_class_defaults()` sets all six ability scores and derives `max_hp` and `armor_class`.
**Point buy** (Custom character-creation path, `scripts/ui/point_buy_select.gd`): `apply_point_buy_scores(scores: Dictionary)` overrides the six scores set by `apply_class_defaults()` and re-derives `max_hp`/`current_hp`/`armor_class` the same way — called strictly after `apply_class_defaults()`, before `apply_background_bonus()`/`apply_race_defaults()` (race never touches base scores, so ordering vs. race is safe either way). Cost table `POINT_BUY_COST`, budget `POINT_BUY_BUDGET` (27), range `POINT_BUY_MIN`/`POINT_BUY_MAX` (8/15) — standard 5e point-buy costs (14/15 cost 2 points/step, others 1). See root `CLAUDE.md`'s "Point buy" section.

**Background ability score increase** (Custom character-creation path, `scripts/ui/background_select.gd`, D&D 2024 rules — a background, not race, grants the ASI): `apply_background_bonus(bonuses: Dictionary)` **adds** to (never overrides) the six scores point buy already set, then re-derives `max_hp`/`current_hp`/`armor_class` the same way — called strictly after `apply_point_buy_scores()`, before `apply_race_defaults()`. `BACKGROUND_POINTS` (3) total, `BACKGROUND_MAX_PER_STAT` (2) per score, no cap on the resulting final score. See root `CLAUDE.md`'s "Background ability score increase" section.
`GameState.hit_die_sides() -> int` (NOT a `Stats` method, despite living right next to other class-derived queries): Barbarian 12, Ranger 10, Monk 8, Wizard 6 — reads `player_stats.character_class`. `Stats.point_buy_hit_die_base()` is the `Stats`-side equivalent (same table, used internally by `apply_point_buy_scores()`/`apply_background_bonus()`'s own HP re-derivation) — prefer `GameState.hit_die_sides()` from UI code that already has a `GameState` reference, `point_buy_hit_die_base()` when only a bare `Stats` instance is in scope (e.g. a not-yet-committed preview).
`_hp_per_level()`: class HP gain per level-up.
`to_dict()`/`from_dict(d)` (Save/Load Phase A): hand-written serialization of every mutable field (scores, class, level/XP, HP, base damage, rage uses, temp HP, status turns, `known_weapon_masteries`). Computed properties and class-set flags are never saved — `from_dict()` calls `apply_class_defaults()` first, then overwrites with saved values; `armor_class`/`min/max_damage` are re-derived by `GameState.recalculate_stats()` after load. **Any new mutable Stats field must be added to both functions** — see `scripts/autoloads/CLAUDE.md`'s SaveManager section.

**Check proficiency flags** (formerly "save_prof"): `check_prof_str/con/dex/int/wis/cha`. Used for traps, lockpick, disarm. No separate saving throw system — all defensive rolls are "checks". Barbarian: STR+CON. Ranger/Monk: STR+DEX. Wizard: INT+WIS.

**Weapon mastery ownership**: `Stats.known_weapon_masteries: Array[String]` (default empty) + `Stats.knows_mastery(name) -> bool`. A weapon's `Item.weapon_mastery` only triggers its effect if the wielder knows that mastery. `Stats.ALL_WEAPON_MASTERIES` (const, alphabetical, all 8) and `Stats.mastery_cap() -> int` (computed live from `character_class` + `character_level`, never cached) back the Mastery Picker (`scripts/ui/mastery_picker.gd`) — see `scripts/ui/CLAUDE.md`'s "Mastery picker" section. The picker fires once right after class selection, and again after any completed long rest if the player opts into it from the long-rest hub (see `scripts/ui/CLAUDE.md`'s "Long-rest hub" section). See `scripts/items/CLAUDE.md`'s "Weapon masteries" section for gating call sites.

**Shield proficiency flag**: `Stats.proficient_shields: bool` (default `false`, set per-class in `apply_class_defaults()` — Barbarian and Ranger only). Gates `GameState.can_equip_shield()`: lacking it blocks equipping a Shield outright (unlike weapon proficiency below, which just drops a bonus) — see `scripts/items/CLAUDE.md`'s "Shields".

**Body armor proficiency flags**: `Stats.proficient_light_armor`/`proficient_medium_armor`/`proficient_heavy_armor: bool` (all default `false`; Barbarian/Ranger set Light+Medium true in `apply_class_defaults()` — neither trains Heavy; Fighter is the one real playable class with all three, including Heavy). Gates `GameState.can_equip_armor()` the same hard-block way as Shield proficiency, plus a real body-armor item's own `str_requirement` (Heavy only). `Stats.recalc_ac(has_armor_equipped, armor_item)` takes the equipped `"armor"` slot `Item` directly: when it's real body armor (`armor_item.base_ac > 0`), AC = `base_ac + DEX bonus` (capped per `armor_item.dex_cap` — see `scripts/items/CLAUDE.md`'s "Body armor") and this always wins over Barbarian/Monk unarmored defense or Mage Armor. Equip/unequip/swap of body armor is NOT a free action (unlike every other equip except Shield) — see `scripts/items/CLAUDE.md`'s "Body armor" for `GameState.begin_armor_change()`'s multi-turn mechanism.

**Weapon proficiency flags**: `Stats.proficient_simple_weapons: bool`, `Stats.proficient_martial_weapons: bool` (both default `false`, set per-class in `apply_class_defaults()`), plus `Stats.martial_weapon_restriction: String` (`""` = none; `"light"` = Martial weapons with the Light property only, Monk's own case) for a class that gets a restricted subset of Martial rather than none-or-all. `Item.weapon_category` ("Simple"/"Martial"/`""`) determines which flag gates a given weapon. `Stats.is_weapon_proficient(item) -> bool` is the single chokepoint folding all three together (unarmed/`null` always proficient; Simple checks `proficient_simple_weapons`; Martial checks `proficient_martial_weapons`, falling back to `martial_weapon_restriction`'s match if that's false) — both `EquipRequirements.can_equip_weapon(item, stats)` (hard-blocks equipping) and `CombatMath.weapon_prof_bonus(weapon, proficiency_bonus, stats) -> int` (`scripts/entities/combat_math.gd`, moved from the old `player.gd._weapon_prof_bonus()` — see "Split-out modules" below) call it, so equip-gating and the attack-roll bonus can never disagree. Used for `prof` in `player.gd._bump_attack()`/`_resolve_cleave_attack()` and `PlayerRanged.ranged_attack()` — lacking proficiency (and no restriction match) blocks equipping the weapon outright via `EquipRequirements`, so `weapon_prof_bonus()`'s own "attack roll, not equip, is gated" comment only matters for weapons somehow already equipped when proficiency changes. Weapon tooltips (`hud.gd`, `inventory_overlay.gd`) show the category right under the damage line, colored red when the equipped class lacks that proficiency (`_is_weapon_category_proficient()` in each file).

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
- **ADV**: attacking a SLEEPING/STATIONARY/ROAMING enemy (unaware defender — see "Stealth & Surprise Attacks" below); attacking an enemy whose `surprise_available == true` (a CHASING/SEARCHING enemy's own turn just re-established sight it had lost — door ambush, mid-chase obstacle break, Invisibility ending; consumed one-shot after check)
- **DISADV**: ranged attack at Chebyshev distance 1 (melee range); melee with a `is_heavy` weapon when STR < 13; ranged with a `is_heavy` weapon when DEX < 13; ranged shot beyond the weapon's normal range but within its own fixed `Item.long_range` (`PlayerRanged.ranged_shot_disadvantage()` — see `scripts/items/CLAUDE.md`'s "Ranged weapons (current)"); a Thrown weapon (Spear/Handaxe/Dagger/Torch) thrown at Chebyshev distance 1, and a thrown weapon's own long-throw equivalent (same `Item.long_range` mechanism), both applied in `PlayerThrowTool._throw_weapon()` (`scripts/entities/player_throw_tool.gd`); a ranged spell attack roll (`spell.range_tiles > 1`) cast at Chebyshev distance 1, applied in `SpellEffects.cast_spell()` (cantrips) and `SpellEffects._resolve_spell_attack_bolt()` (leveled ATTACK_ROLL spells — Chromatic Orb/Witch Bolt) in `scripts/entities/spell_effects.gd`. **Exemption**: the "melee-range" DISADV (ranged, thrown, AND spell) is skipped outright when the target is genuinely unaware — `PlayerVfx.is_target_unaware(enemy)` (`scripts/entities/player_vfx.gd`): `behavior in [SLEEPING, STATIONARY, ROAMING]` or `surprise_available` — 5e RAW exempts an incapacitated nearby creature from this "distracted by a hostile at melee range" penalty, and this engine's closest equivalent is an unaware enemy; without the exemption a point-blank surprise shot/throw/cast always cancelled its own surprise-attack ADV back to a flat roll (`PlayerRanged.ranged_attack()`, `PlayerThrowTool._throw_weapon()`, `SpellEffects.cast_spell()`/`_resolve_spell_attack_bolt()`). **Deliberately NARROWER than `PlayerVfx.has_advantage()`** (bugfix — they used to share one result via `was_surprised`, so Paralyzed/Incapacitated/Faerie Fire/Blinded's own ADV sources — none of which mean "hasn't reacted to you" — silently ALSO exempted the melee-range DISADV, leaving a point-blank ranged spell attack on a Paralyzed enemy at pure ADV instead of the correct netted-to-flat roll): `is_target_unaware()` only covers the two genuine-unawareness cases above, both read/captured **before** `has_advantage()`/`on_disturbed()` run (both mutate `surprise_available`/`behavior`) — every call site computes `target_was_unaware` from `is_target_unaware()` and `was_surprised` from `has_advantage()` as two independent locals now, not one reused value.
- ADV + DISADV cancel → 1d20
- Yellow "!" floats above enemy on ADV surprise attacks
- Enemy attack log lines (`enemy.gd._attack_player()`) never name the specific talent/ability that granted ADV/DISADV — that context lives only in the `ehit` tooltip roll breakdown, not the log line.
- **Halfling Luck**: `CombatMath.roll_with_adv_disadv()` runs every individually-rolled d20 through `CombatMath.halfling_reroll(die)` — a natural 1 (Halfling only) is automatically rerolled and the new value MUST be used (single reroll, even if the reroll is also a 1). Baked into the one shared roll function, so it covers all 6 player attack-roll sites (melee/cleave/off-hand/OA/ranged/thrown) for free; `player_thief_tools.gd`'s `attempt_disarm()` calls `halfling_reroll()` directly for the trap-disarm check. `CombatMath.wrap_halfling_luck(text, lucky)` wraps the finished chat-log line in dark green + a ☘ marker; the `lucky1`/`lucky2` fields on `hit_meta`/`check_meta` drive a struck-through "☘ Halfling Luck: ~~1~~ → N" tooltip line in `fmt_hit_tooltip()`/`fmt_save_tooltip()` (`scripts/ui/tooltip_formatters.gd`). Never applies to enemy rolls. See "Halfling" below for the race's other traits.

### Damage types / resistances / per-die breakdown (typed damage instances)
Every main attack path (`player.gd._bump_attack()`/`_resolve_cleave_attack()`/`_resolve_offhand_attack()`/`resolve_opportunity_attack()`, `PlayerRanged.ranged_attack()`, cantrips/Fireball/Magic Missile in `spell_effects.gd`) builds a **typed damage instance** via `CombatMath.build_damage_instance(rolls: Array[int], sides: int, flat_mods: Array, crit: bool, damage_type: String) -> Dictionary` instead of a bare int. `rolls` is every individual die result (from `Rng.roll_dice(count, sides)` — weapon dice are stored as a flat range on `Item`, `CombatMath.dice_notation(dmin, dmax) -> Vector2i` recovers `(count, sides)` since every weapon pool entry constructs that range as an exact `NdM`), `flat_mods` is the same `{name, amount, color}` shape `encode_bonus_sources()` always took (weapon enhancement, ability mod, Rage bonus, Frenzy, Ironwood Bark — same-type sources that fold into ONE instance). The instance sums dice + flat mods, then doubles on crit (**multiplication always happens last** — never double a partial subtotal and tack bonuses on after).

**One instance per damage type, not one instance per attack**: a bonus source with its OWN distinct damage type (Zealot's Judgement Day — Radiant, on top of the weapon's own type) becomes a SECOND, independent `build_damage_instance()` call rather than folding into the first. Each instance is applied via `Enemy.take_typed_damage(amount, damage_type) -> Dictionary` (below) and gets its own `DungeonFloor.show_damage()` floater (`stack_index` param offsets the second floater's spawn x so they don't overlap) and its own `[url=dmg:...]` segment in the SAME chat-log line/`game_log()` call (`"... for [url=]N[/url] Slashing and [url=]M[/url] Radiant dmg."` — never a second `game_log()` call). The original damage-stacking rule still holds **per instance**: never call `take_typed_damage()`/`show_damage()` twice for what should be one instance, and always resolve every bonus-trigger flag (Judgement Day pending, etc.) to a plain number BEFORE either instance's `take_typed_damage()` call, so a source gated on `not enemy.stats.is_dead()` can't silently skip because an earlier instance already killed the enemy.

**Enemy resist/immune/vuln**: `Enemy.damage_resistances`/`damage_immunities`/`damage_vulnerabilities: Array[String]` (populated from `"damage_resistances"`/`"damage_immunities"`/`"damage_vulnerabilities"` pool keys — `"resist"`/`"vuln"` still work as a fallback for the first/third, e.g. Skeleton resists Piercing/is vulnerable to Bludgeoning, Imp/Quasit resist Fire). `Enemy.take_typed_damage(amount, damage_type) -> {actual, mul}` applies ×0 (immune) / ×2.0 (vuln) / ×0.5 (resist), **priority in that order, no stacking** (a type in two lists is an authoring error) — BEFORE `Stats.take_damage()`'s flat floor-at-1 clamp. Single chokepoint every attack site calls instead of `enemy.stats.take_damage()` directly. Also hooks the `"regeneration"`/`"undead_fortitude"` traits (see `scripts/entities/CLAUDE.md`'s "Enemy D&D stat-block schema"). Separate from the player's own per-type DR in `GameState.take_damage_raw()` (Rage/Bear-form) — that system is unchanged.

**Undead Fortitude's own check-visibility**: a would-be-lethal, non-Radiant, non-crit hit against an enemy with the `"undead_fortitude"` trait rolls a CON save (DC `dc_base` + damage dealt) via `resist_check_detailed()` — a pass drops it to 1 HP and always logs (`"<Enemy>'s [url=save:...]Undead Fortitude[/url] keeps it standing!"`, hover shows the die/mod/DC breakdown via `TooltipFormatters.fmt_save_tooltip()`). A **fail** is silent by default (the enemy just dies normally) unless `GameState.debug_show_all_checks` is on, in which case it also prints a gray `"<Enemy>'s Undead Fortitude check fails."` line with the same `save:` tooltip — same "silent unless a real event, debug flag reveals every roll" pattern as the Stealth-vs-Passive-Perception check above (both now share the one `debug_show_all_checks` flag/"All Checks" F3 checkbox, renamed from the Stealth-only `debug_show_stealth_checks` once it grew a second consumer).

**Per-die tooltip breakdown**: `CombatMath.encode_damage_instance(inst)` packs the instance into a `dmg:` meta string with a `rolls=` field (pipe-joined individual die results) and `sides=`/`dtype=`/`rmul=` (the resist/vuln multiplier actually applied) alongside the existing `bonus=`/`crit=`/`final=` fields. `TooltipFormatters.fmt_dmg_tooltip()` renders a `"NdS: r1 + r2 + ... = total"` line when `rolls=` is present (falls back to the old single `"1d%d"` line for the handful of call sites not migrated — Frenzy, thrown weapons, enemy-attacks-player — so nothing broke), a `"÷ 2 (Resistance)"`/`"× 2 (Vulnerability)"` line when `rmul != 1.0`, and appends the damage type to the final line.

**Multiplication always happens last**: a critical hit doubles the FULL summed total (dice + flat mods) of EACH instance independently, never a partial subtotal computed before some sources are added in.

**Lethal-hit log lines fold the kill in**: `Player._finish_kill(enemy)` no longer logs its own "X dies." message — every player attack call site (all 6 attack-roll sites plus Frenzy/Limit Break/thrown/ranged) captures `is_dead()`/`is_lethal` right after damage is applied (after BOTH instances if there are two), appends `CombatMath.death_suffix(is_lethal)` (`scripts/entities/combat_math.gd`, renders `" and died."`) to its own hit/damage log string, and only then checks that same lethality bool before calling `_finish_kill()`. Adding a new attack path that can kill an enemy must follow this pattern — never log a bare "dies" line from inside a kill-handling function.

**Rage's damage tooltip tag**: `enemy.gd._attack_player()`'s `edmg:` meta carries a `rage=%d` field (set whenever `GameState.is_raging` was true for that hit — enemies always deal `"Bludgeoning"`, which is physical, so Rage's 50% DR in `take_damage_raw()` was live). `TooltipFormatters.fmt_edmg_tooltip()` renders a `"÷ 2  (Rage)"` line (alongside the existing crit `"× 2"` line) whenever that flag is set, so the player can see Rage's DR reflected in the hover breakdown, not just as a smaller final number.

**Enemy damage tooltip shows a real die, not a raw min–max span (PERMANENT RULE)**: enemy attacks are authored as a flat `dmg_min`/`dmg_max` range (pool data), not `NdM` dice notation like player weapons — the `edmg:` tooltip must NEVER render that raw range verbatim (e.g. `"4–9 = 6"`, which reads as meaningless noise, not a roll). `CombatMath.roll_flat_range(min_d, max_d)` (`scripts/entities/combat_math.gd`) decomposes the range into `{sides, flat, die, total}` — `sides = max-min+1`, `flat = min-1`, `die = Rng.roll(sides)` — the exact same uniform distribution over `[min, max]` as the old `Rng.range_i()` call, just rolled/shown as a genuine `1dS[+flat]` die face + bonus instead of an opaque span. `Enemy._attack_player()`'s main hit AND its `"extra"` second-typed-damage instance (e.g. Imp's Sting Poison) both go through this and encode `sides=/flat=/die=` (not `min=/max=/roll=`) into the `edmg:` meta; `TooltipFormatters.fmt_edmg_tooltip()` renders `"1dS = die"` (or `"damage = die"` when `sides <= 1`) plus a separate `"+flat (bonus)"` line, mirroring how `fmt_hit_tooltip()`/`fmt_dmg_tooltip()` already show every player-side roll component. **Any new enemy-damage call site (a new multiattack/ability/thrown-weapon sub-entry, a new "extra" second instance) must roll through `roll_flat_range()` and encode these three fields — never re-introduce a bare `Rng.range_i(min,max)` roll feeding straight into an `edmg:` tooltip.** `Enemy._attack_companion()` is the one exception — Companion has no per-hit tooltip system at all (folds straight into one flat number), so it still rolls the plain range directly; if a Companion tooltip is ever added, route it through the same helper.

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
| Burning | orange | *(no current source — see below)* | damage/turn |
| Bleeding | red | Spike Trap (5t) | damage/turn |
| Slowed | brown | Bear Trap (20t), mud, water | movement costs 2 turns |

**Fire Trap no longer applies the Burning status** — direct owner correction: the old
`burning_turns = 4` DoT dealt `character_level` damage per tick (`Stats.tick_status()`), which
spiraled into an absurd total at higher levels (12+ damage at level 1, 28+ at level 5, on top of
the trap's own flat hit). `dungeon_floor.gd`'s `trigger_trap()` now deals a flat, one-shot **2d4
Fire** hit instead (`Rng.roll_dice(2, 4)`, same roll shape as `_roll_fire_tick_damage()`'s burning-
prop tick) and, separately, burns one random Scroll out of the player's own quickbar+bag
(`GameState.burn_random_scroll()` — decrements `quantity` if stacked, else removes it outright,
logged as its own line) as the trap's real punishment instead of a lingering DoT. `Stats.
burning_turns`/`tick_status()`'s burning branch are unchanged and still exist — they're just
currently dead scaffolding with no live call site setting `burning_turns` for the player anymore
(a future fire source, e.g. standing in flames, could still use it) — same "granted but nothing to
hook into" precedent as several race traits in this file.

**Water extinguishes burning**: stepping onto (or ending a move on) a WATER tile zeroes
`burning_turns` to 0 — `player.gd`'s `_try_move()`/`_execute_queued_path()` for the player,
`Enemy._move_step()` for enemies (see `scripts/world/CLAUDE.md`'s "Water terrain"). No current
call site ever sets `Enemy.stats.burning_turns` above 0 (burning is still a reserved/no-op status
for enemies per the `"condition_immunities"` schema row above), so the enemy side of this is inert
today — added so the interaction is already correct once a burning-enemy source exists, without
needing a second pass through every water-tile-entry call site.

**Status-tray display vs. the underlying `slowed_turns` counter**: `slowed_turns` is shared by Bear
Trap's real 20-turn debuff AND every Mud/Water step (`apply_player_status("slowed", maxi(1,
slowed_turns))`, `player.gd`'s `_try_move()`/`_execute_queued_path()`) — both still drive the
"next move costs 2 turns" penalty off this one field, unchanged. But `Stats.tick_status()` decays
it once per real turn (`player.gd._on_turn_started()`), and terrain only ever (re-)applies it
during the move itself — so a bare `slowed_turns > 0` status-tray icon would tick back to 0 before
the player's next turn even started, flickering for roughly one frame per terrain step instead of
staying lit the whole time the player stood on the tile. `GameState.player_on_difficult_terrain`
(separate `bool`, not serialized) fixes this: it's recomputed from-scratch every `_on_turn_started()`
call (moved or waited, real or reverted) purely from the CURRENT tile at `grid_pos` plus the same
Trailblazer R1 / Natural Sleeper Panther-Salmon bypass checks `_try_move()` already runs — so it
reads as "am I standing in Mud/Water right now", never as a decaying counter, and can't flicker.
`hud.gd._update_status_icons()` shows it as its own `"difficult_terrain"` status-tray entry
(`StatusTooltips`'s `"Difficult Terrain"` title/description). **`"slowed"` is suppressed whenever
`player_on_difficult_terrain` is already true** (`s.slowed_turns > 0 and not GameState.
player_on_difficult_terrain`) — the two entries render with the identical icon/color, so showing
both is an indistinguishable duplicate rather than "two distinct debuffs". This also fixed a real
flicker: re-stepping into Mud/Water while already standing in it re-applies `slowed_turns` (real
gameplay effect, drives the 2-turn move cost) via `GameState.apply_player_status()`, which used to
unconditionally emit `player_status_changed` — for one rendered frame both entries were active at
once, at the exact moment `player_on_difficult_terrain` was already `true` from the previous tile.
`apply_player_status()` itself was also tightened to only emit when a counter-based status'
value actually increases (harmless general cleanup, not what fixed the visible bug — the tray
suppression above is what does). A genuine Bear Trap debuff picked up while also standing in
Mud/Water now shows only the `difficult_terrain` icon while both are active (not two overlapping
copies of the same-looking icon) — once the player leaves the terrain, `slowed_turns` alone
(still ticking down from the trap) takes over showing the `"slowed"` icon.

## Conditions (Poisoned / Prone / Restrained / Incapacitated / Blinded / Frightened / Paralyzed)
Seven real 5e-style conditions. The first four are bidirectional (player via `Stats`, enemy via
`Enemy`'s own fields — same "duplicate implementation, not a unified refactor" convention the DoT
statuses above already use) and deliberately kept SEPARATE from any same-named damage-over-time
status — a source that inflicts one doesn't have to inflict the other (Rend inflicts only the
Poisoned condition, a Poison Potion inflicts only the DoT). Blinded is purely positional/symmetric
(see "Fog Cloud" below). Frightened is player-only today (its only source, Quasit's Scare, only
ever targets the player). Paralyzed is enemy-only today (its only source, Hold Person, only ever
targets an enemy).

| Condition | Player field | Enemy field | Effect |
|---|---|---|---|
| Poisoned | `Stats.poisoned_condition_turns` | `Enemy.poisoned_condition_turns` | DISADV on the condition-holder's OWN attack rolls and ability checks (NOT saving throws — 5e RAW only restricts checks/attacks). Does not stack with Prone/Restrained's own-attack DISADV (`Stats.has_disadvantage_condition()`). **Player-side only**, a source may additionally set `Stats.poisoned_condition_save_dc` (> 0) — see "Bearded Devil" below — granting a repeated end-of-turn CON save to end it early (`Player._on_turn_started()`) and blocking `GameState.heal()` entirely while active; a plain source that never sets this (Tripwire, Quasit's Rend) leaves both effects off, unaffected. |
| Prone | `Stats.prone` (not turn-counted) | `Enemy.prone` (not turn-counted) | Melee attacks against the prone creature get ADV, ranged attacks get DISADV (threaded via an `is_ranged: bool` param on `Enemy._attack_player()`/`_attack_companion()`, and a `spell.range_tiles` check for player-cast spells). Can't move — any direction key press instead stands up (ends the condition), costing the turn without moving. An enemy auto-stands at the very top of its own `decide_turn()` instead, consuming ONE point of that turn's movement budget (`_moves_this_turn -= 1`) rather than the whole turn, then falls straight through to its normal decision logic — an enemy with spare movement budget (Aggressive's bonus step, an above-baseline `"speed"` entry) can still close distance and/or attack the same turn it stands. |
| Restrained | `Stats.web_restrained` (persists until the web is destroyed — Spider's Web is still its only source, see "Spider" below) | `Enemy.restrained_turns`/`restrain_save_dc` — Ensnaring Strike only, see "Ranger class" below | Speed 0 (player: already blocked movement pre-conditions-system; enemy: `decide_turn()`'s movement gate, same shape as `rooted_turns` — skips movement, still attacks if adjacent). ADV on attacks against the restrained creature (any kind, melee or ranged — unlike Prone's kind-split; enemy-side added inline at the two primary melee/ranged attack-roll sites, same Prone-precedent pattern, not folded into `PlayerVfx.has_advantage()`). DISADV on the restrained creature's own attacks (player: folds into `has_disadvantage_condition()`/`poisoned_condition_turns>0`; enemy: folds into the same disadv pool as `poisoned_condition_turns`/`enfeeble_turns` in `_attack_player()`/`_attack_companion()`) and DEX checks specifically (`PlayerThiefTools.attempt_disarm()`, the only player-side DEX check today — no enemy-side DEX-check equivalent exists to extend this to). The enemy-side source (Ensnaring Strike) additionally deals 1d6 Piercing at the start of the restrained enemy's own turns and repeats a STR save each turn to break free early, ending the caster's Concentration on a success — see "Ranger class" below for the full mechanism; Spider's Web has no analogous DoT/repeated-save shape (a structure-destroying escape route instead). |
| Incapacitated | `Stats.incapacitated_turns` | `Enemy.incapacitated_turns` | "Can't take actions" — blocks player movement/bump-attack (`player.gd._try_move()`) and ability/spell activation (`_use_ability_slot()`); **partial coverage** — mouse-click attacks and item/tool use aren't gated (no current trigger source exists for either side, so this wasn't exhaustively wired; extend these two gates if a future ability actually inflicts it). Breaks Concentration immediately (`GameState.apply_player_status()`'s `"incapacitated"` case calls `end_concentration()`). On the enemy side: skips its entire turn (`decide_turn()`'s very first check, same shape Prone used to have before this rework) AND makes every player attack against it a Surprise Attack (`PlayerVfx.has_advantage()`), since "every attack against it is a Surprise Attack" is 5e's own Incapacitated text and this engine's Surprise Attack mechanism already IS exactly that (flat +1 ADV). |
| Blinded | `GameState.is_blinded(pos)` (positional, no Stats field — see "Fog Cloud" below) | same query, symmetric | ADV on attacks against a Blinded creature, DISADV on its own attacks (both sides, player and enemy). Vision collapses to a flat 1-tile radius (`GameState.effective_fov_radius()`), overriding every other bonus including darkvision — a real 3×3 block (Chebyshev), all 8 neighbors including diagonals, NOT just the 4 cardinals (bugfix: `DungeonFloor._cast_light()`/`get_visible_enemies()`'s shared Euclidean radius-bound check, `dx²+j² <= r²`, mathematically excludes a true diagonal neighbor at `radius=1` since its distance² is 2 > 1 — both now special-case Chebyshev whenever the effective radius is ≤1). **The enemy side is symmetric too**: `Enemy._sight_range()` now also collapses to 1 while the enemy itself stands in a Fog Cloud/Darkness zone (previously it never checked `is_blinded()` at all, so a blinded enemy kept its full normal sight radius), and `Enemy._can_see_entity()`'s own distance check gets the same Chebyshev-at-radius-1 fix. **A Blinded attacker's own reach also collapses to 1 tile (Chebyshev)** for ranged weapons (`PlayerRanged.is_ranged_target_in_range()`), thrown weapons (`PlayerThrowTool._throw_weapon()`), spells (`PlayerSpellcasting._effective_range()`), and the enemy-side mirrors (`Enemy._in_attack_range()`'s `"ranged"` branch, `Enemy._pick_ready_ability()`'s `max_reach`) — a weapon/spell's own longer range is simply unreachable while fighting blind; melee is unaffected (already 1 tile). "Auto-fails sight-based checks" is NOT implemented (no concrete "sight check" mechanic exists in this engine to gate). |
| Frightened | `Stats.frightened_source: Enemy`/`frightened_turns`/`frightened_save_dc` (live ref, NOT serialized — same precedent as `hunters_mark_target`/`witch_bolt_target`) — only Quasit's Scare inflicts it, always targeting the player | `Enemy.frightened_turns`/`frightened_source: Player` (live ref, NOT serialized, same precedent) — only Aasimar's Necrotic Shroud (Celestial Revelation transformation, see "Aasimar" above) inflicts it, always the player | **Now a real bidirectional mirror on both sides** (`Player._frightened_active()`/`_frightened_blocks_move_to()` and `Enemy._frightened_active()`/`_frightened_blocks_step()`, same shape): DISADV on the holder's own attacks/checks ONLY while the source is in LOS — NOT unconditional like the other conditions, hence its own helper rather than folding into `has_disadvantage_condition()` (enemy-side: also threaded into `resist_check_detailed()`'s own ADV/DISADV netting, not just the attack-roll aggregation, so it covers the enemy's own checks too, e.g. a frightened enemy resisting Grip of the Forest's pull). Can't willingly move closer to the source via voluntary movement — player: `Player._frightened_blocks_move_to()`, checked in both `_try_move()` and the queued-path executor; enemy: `Enemy._frightened_blocks_step()`, checked in `_act_toward_single_step()`'s greedy-preferred-step loop AND its BFS fallback (both skip/reject a candidate step that would close distance, same "only wired into the chase-toward movement" scope limit as the player's own `_try_move()`/queued-path-only coverage) — forced movement like Push/a chasm shove is unaffected on either side since it never calls either helper. Player-side repeats a WIS save once per real turn (`Player._on_turn_started()`, vs `frightened_save_dc`) — success ends it early, a fail ticks toward the outer ~10-turn "1 minute" cap; auto-clears if the source dies (`Enemy.die()`). **Enemy-side still has no repeated save** — fixed 2-turn duration only (documented simplification, unchanged) — and `frightened_source` is cleared the instant `frightened_turns` ticks to 0 (`decide_turn()`). |
| Paralyzed | `Stats.paralyzed_turns`/`paralyze_save_dc`/`paralyze_save_stat` (live only, NOT serialized — same mid-floor-only precedent as `poisoned_condition_turns`/`frightened_turns`) — first source: Spiderling's Bite (see "Spiderling" above), via `GameState.apply_player_paralyzed(turns, dc, stat)`/`clear_player_paralyzed()` | `Enemy.paralyzed_turns`/`paralyze_save_dc` — Hold Person only, **Humanoid targets only** (Abyssal Tiefling lineage spell, see "Wizard leveled spells" above); its own dedicated condition, NOT an alias of Incapacitated (an earlier version approximated it that way) | **Now a real bidirectional mirror on both sides**, direct owner request ("player side conditions should work the same as enemy-side"). Both: implies Incapacitated (full action lock — a player with `paralyzed_turns > 0` hits the exact same guard as `incapacitated_turns > 0` in `Player._try_move()`/`_use_ability_slot()`, same "partial coverage" caveat as Incapacitated's own row above — mouse-click attacks/item-tool use aren't separately gated either; enemy: skips the enemy's ENTIRE turn in `decide_turn()`, same shape as Incapacitated). Every attack made against a paralyzed creature has Advantage — player-side: `Enemy._attack_player()`'s `condition_adv` term (same unconditional-of-kind treatment as Restrained, not kind-split like Prone); enemy-side: `PlayerVfx.has_advantage()`. Any HIT made from within 1 tile is an automatic critical hit — player-side: `Enemy._attack_player()` upgrades `is_crit` right after the roll resolves (mirrors `player.gd._bump_attack()`'s own identical check against a paralyzed enemy); enemy-side: `player.gd._bump_attack()` — melee is always within 1 tile so this fires unconditionally there; ranged/thrown/spell attacks from further away are unaffected either side (RAW's own "within 5 feet" text), and a natural-1 miss still misses (only upgrades a landed hit). Repeats a save at the end of each side's own turn to end early: player-side (`Player._on_turn_started()`, vs `paralyze_save_stat`/`paralyze_save_dc` — generic over all 6 abilities via a `match`, not hardcoded to one stat like Frightened's WIS/Hold Person's WIS, since Spiderling's own poison save is CON) mirrors Frightened's repeated-save shape exactly, just as its own top-level check (deliberately NOT nested under the Frightened branch — see the bugfix note on that nesting below); enemy-side (`decide_turn()`, vs `paralyze_save_dc`, WIS) — success ends it early (+ ends Concentration on the enemy side, `Stats.hold_person_turns`/`_target`); a fail ticks toward the outer duration backstop (10-turn Concentration for Hold Person, or Spiderling's own `turns` value for the player side, tied 1:1 to how long the SAME hit's Poisoned condition lasts, since the real stat block says "paralyzed while it remains poisoned this way"). **Not mirrored for the player**: auto-failing STR/DEX checks (enemy-side only, `resist_check_detailed()` — no generic "auto-fail a player check" chokepoint exists to hang it on, same tier as several other player-side gaps in this file) and the animation freeze (`Enemy._refresh_paralyzed_visual()`'s `speed_scale = 0.0` — the player has no equivalent "freeze the sprite" hook; a documented, cosmetic-only gap). **BUGFIX found while adding the player-side repeated save (now fixed)**: `Player._on_turn_started()`'s Bearded-Devil-Beard-Poisoned repeated-save block AND its Infernal Wound damage-tick block used to be accidentally nested INSIDE the `if stats.frightened_turns > 0 and stats.frightened_source != null:` body (3-tab indentation matching that `if`'s own children, not the 2-tab sibling level) — so a poisoned-but-not-frightened player never got the early-end CON save (fell back to the plain `tick_status()` decay only) and a Glaive-wounded-but-not-frightened player never took the Infernal Wound tick at all. Found via raw-tab inspection while placing the new Paralyzed repeated-save block as its own top-level (2-tab) sibling check (deliberately, so it wouldn't inherit the same bug) — both blocks are now dedented to that same top-level sibling position, unconditional on Frightened. |

**Apply a condition** (mirrors the DoT-status shape above): `GameState.apply_player_status("poisoned_condition"|"prone"|"incapacitated", turns)` (player) or `Enemy.apply_status("prone"|"poisoned_condition"|"incapacitated"|"frightened", turns)` (enemy) — Restrained has no generic apply path since Web sets `web_restrained`/`web_escape_dc` directly (a persistent flag + escape DC, not a turn counter, so it doesn't fit the shared `turns` shape); Frightened has its own dedicated `GameState.apply_player_frightened(source, turns, save_dc)`/`clear_player_frightened()` (needs a live source reference the generic shape can't carry); Paralyzed likewise has its own dedicated `GameState.apply_player_paralyzed(turns, save_dc, stat)`/`clear_player_paralyzed()` (player side, needs the DC + repeat-save stat alongside the turn count) — Hold Person still sets `Enemy.paralyzed_turns`/`paralyze_save_dc` directly on the enemy side, same reason Frightened bypasses the shared shape — and Blinded has no apply path at all (purely derived from position, see `is_heavily_obscured()`/`is_blinded()`). `"turns"` is ignored for Prone (bool, not counted).

**On-hit condition via `"multiattack"`**: a sub-entry's optional `"status"`/`"status_turns"` keys (mirrors the pre-existing `"abilities"` array's own `ab.has("status")` shape) apply generically on a landed hit — `Enemy._attack_player()`'s tail, after the Orc Shaman poison hardcode. First user: Quasit's Rend (`"status": "poisoned_condition", "status_turns": 1`) — see `scripts/world/CLAUDE.md`'s Quasit entry / `dungeon_floor_data.gd`.

**Glossary**: `WeaponTooltip.KEYWORD_GLOSSARY` (`scripts/items/weapon_tooltip.gd`) carries a `[url=keyword:X]`-linkable entry for every condition here plus `"heavily_obscured"` — despite the class name, this is the game's one general keyword glossary, not weapon-mastery-only (see that file's own header comment).

---

## Enemy resist checks (World Tree)
`Enemy.resist_check(dc: int, use_con: bool = false) -> bool` — rolls `d20 + bonus + (con_modifier or str_modifier)` vs `dc`; true = enemy resists. **`bonus` is `floor/3` for a legacy entry, or `prof_bonus` (if that stat is in `"check_profs"`) for an entry with a `"mods"` stat block — see "Enemy D&D stat-block schema" above** — gated purely on whether the pool entry supplies `"mods"`, never both formulas at once. Legacy backing stats: `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL` entries may set optional `"str_mod"`/`"con_mod"` int keys (default 0); `_apply_stats()` converts them to `Stats.strength/constitution` (`10 + mod * 2`) when `"mods"` is absent. Used by Grip of the Forest's pull (STR) and Branching Strike R3's push (CON), both vs DC `8 + player STR mod + proficiency`; by the Heavy Crossbow's **Push** weapon mastery (CON) vs DC `8 + player DEX mod + proficiency`, resolved via `DungeonFloor.resolve_push()`; and by the Maul's **Topple** weapon mastery (CON) vs DC `8 + player STR mod + proficiency`, resolved via `Enemy.apply_status("prone", 1)` — see `scripts/world/CLAUDE.md`'s "Forced movement" section and `scripts/items/CLAUDE.md`'s "Weapon masteries". A boss with `"legendary_resistances"` set may force a failing roll to pass instead (§15 of the schema doc), consuming a per-life charge.
`Enemy.resist_check_detailed(dc, use_con = false, use_dex = false, use_wis = false, use_int = false) -> Dictionary` — same roll as `resist_check()`, but returns `{die, mod, floor_bonus, prof_label, dc, total, pass, stat, sliver_penalty, legendary_used}` so a caller can log a hover-tooltip roll breakdown instead of just the bool (`floor_bonus` is the numeric bonus actually applied — floor-scaling OR proficiency, whichever formula the entry uses; `prof_label` is `"Floor"` or `"Proficiency"` to match). `resist_check()` is now a one-line wrapper (`return resist_check_detailed(dc, use_con)["pass"]`). Consumed by Topple's `player.gd._try_topple()` (below) and by every enemy-side SAVE cantrip in `spell_effects.gd` (Ray of Frost, Toll the Dead, Mind Sliver, Thunderclap, Fireball) — Grip of the Forest / Branching Strike R3 / Heavy Crossbow Push still call the plain bool form since their logs don't show a roll breakdown. Priority when multiple `use_*` are somehow true: DEX > WIS > INT > CON > STR (every real call site only sets one). `wis_mod`/`int_mod` optional pool keys (default 0) mirror `str_mod`/`con_mod`/`dex_mod` — see "Enemy stat scaling" above (all five are the fallback path when `"mods"` isn't supplied). **Mind Sliver's penalty**: `Enemy.mind_sliver_penalty_die: bool` — if set, the very next `resist_check_detailed()` call (any stat, on any of the sites above) rolls `-1d4` (consumed regardless of which stat that particular check happens to use) and reports it via the `sliver_penalty` key — every one of those sites folds it into its `save:` meta's `sliver=%d` field, so the hover tooltip shows it as its own `"-N (Mind Sliver)"` line rather than silently vanishing into the total.
**Topple's contest-roll tooltip**: `_try_topple()` builds a `"save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d"` meta (reusing the existing `TooltipFormatters.fmt_save_tooltip()`/`hud.gd`'s `"save"`/`"check"` dispatch, `prof_label` read live off `save["prof_label"]`) and wraps "is knocked"/"resists" in `[url=%s]` so hovering the Topple log line shows the enemy's CON-save roll, same as hovering a player attack shows the hit roll. `fmt_save_tooltip()` reads the `prof_label` meta field (defaults to `"Proficiency"` if absent) to relabel the tooltip's second modifier line — `"Floor"` for a legacy floor-scaling enemy, `"Proficiency"` for a `"mods"`-based one.
`Enemy.rooted_turns: int` — Grip of the Forest R2. Checked at the top of `take_turn()`: decrements, skips movement, still attacks if already adjacent.
`Enemy.disadv_next_attack: bool` — Grip of the Forest R3. Consumed in `_attack_player()`'s roll (adds a Disadvantage source, resolved via the same net-ADV/DISADV house rule as the player's own attacks).
`Enemy.prone: bool` — Maul's **Topple** weapon mastery, the real Prone condition (see "Conditions" above, not a turn-skip like `rooted_turns`).
`Enemy.slowed_turns: int` — Mud/Water, set to 1 by `_move_step()` whenever the enemy's own move lands it on one of those tiles (`Enemy.apply_status("slowed", 1)`). **Deliberately NOT a full-turn skip** (reworked from an earlier `idle_tick`-on-decide version per direct owner correction — "slow by nemělo mít nic společného s útokem", i.e. Slowed must never affect the attack itself): `decide_turn()` ticks it down once and threads a `"slowed": bool` flag through whatever intent `_decide_action()` returns instead of short-circuiting. Every voluntary-movement executor that consumes the flag (`_act_toward()` — chase/search-toward, `_do_roam_walk()`, `_flee_from()` — Nimble Escape) shaves exactly ONE step off that round's own movement budget, never gates the attack/flee-fallback check: `_act_toward()`'s per-iteration `_in_attack_range()` check still fires on every iteration regardless of remaining movement budget (`move_budget`, separate from the loop's `total_steps`), so an enemy already adjacent when its turn starts attacks immediately whether or not it's slowed — only an enemy that still needs to close distance actually loses a step. Net effect: a plain 1-move-per-turn enemy that isn't already adjacent effectively takes 2 real rounds to cover 1 tile (this round's already-1 movement budget drops to 0), while Orc Warrior's Aggressive trait (2 steps via `bonus_moves`) or an above-baseline `"speed"` entry only loses one of its two steps, not both; a below-baseline `"speed"` entry's own off-cycle round (already 0 movement credit, handled earlier in `_decide_action()`'s `_moves_this_turn <= 0` branch, which never reaches `_act_toward()` at all) is untouched by Slowed since there was nothing to reduce that round anyway. `_do_roam_walk()`/`_flee_from()` only ever have a 1-step budget to begin with, so for them "slowed" just skips that round's single step outright (still awaits real time — see the `_i >= move_budget` / zero-total-steps notes on each function for why, matching the "every decide/execute path must await something real" rule below). The `"search"` intent's own inline BFS-step in `_execute_action()` follows the same rule (skip this round's step, still real time, does not burn the 7-turn search countdown that round).

`Enemy.embedded_items: Array[Item]` + `Enemy.die()` override — thrown weapons (Spear) embedded by a non-lethal hit (`PlayerThrowTool._throw_weapon()`, `scripts/items/CLAUDE.md`'s "Thrown weapons") sit here until the enemy dies. `die()` overrides `Entity.die()`: drops every embedded item at `grid_pos` (100% chance each) via `DungeonFloor.place_item_on_floor()`, then calls `super.die()`. Every death call site already ends with `enemy.die()` (`player.gd._finish_kill()`, `companion.gd`, the trap/chasm death sites in `dungeon_floor.gd`), so this one override recovers an embedded Spear regardless of which of those actually killed the enemy or how many turns later.

## Opportunity Attacks

Full design doc: `docs/architecture/opportunity-attacks-design.md`. Core rule (5e-style): when an entity's single grid-movement step takes it from a tile **inside** an attacker's threat range to a tile **outside** it (Chebyshev), the threatened entity gets one free, turn-free reactive melee attack — at most once per round per attacker. Moving within reach, or approaching, never provokes. **Forced movement never provokes** — `DungeonFloor.force_move_entity()` and `resolve_push()` intentionally do not call either hook (see the comment at each function).

**Resolution model** — same precedent as Retaliation (`player.gd.try_retaliation()`): OA resolves *inline, synchronously*, with no phase change, no `begin_player_action()`/`revert_to_waiting()`, no turn cost. `TurnManager` has zero OA-related changes.

**Threat range**: player = `CombatMath.melee_reach(GameState.equipped_weapon, GameState.get_talent_rank("branching_strike"))` (same formula the chase-to-attack and Cleave range checks use — a Glaive Barbarian with Branching Strike R2 threatens 4 tiles). Enemy = `Enemy.melee_reach() -> int` (pool key `"reach"`, default 1 — flat for all current enemies, one-line pool entry for a future reach enemy). Companion = flat 1.

**Two hooks, one per moving side**:
- **Enemy moves → player/companion may OA**: `enemy.gd._check_opportunity_attacks_on_move(prev_pos, next_pos)`, called at the top of `_move_step()` (the single chokepoint for ALL enemy voluntary movement — chase/roam/random-step/search). Gates on `_dungeon_floor.is_tile_visible(prev_pos)`, the attacker's per-round flag, and (for the player) `not player.stats.is_dead()`. If it provokes, resolves the attack (`player.resolve_opportunity_attack(enemy)` or `Companion._attack_enemy(enemy)`), then aborts the move (`if not is_instance_valid(self) or stats.is_dead(): return`) if the OA killed the mover.
- **Player moves → each threatening enemy may OA**: `player.gd._resolve_enemy_opportunity_attacks(prev, next)`, called from `_try_move()` and both `_execute_queued_path()` move bodies (chase-step and regular queued-path step) right before `TurnManager.begin_player_action()`/the tween. Skips entirely on `GameState.noclip`. Skips a given enemy if `SLEEPING`/`STATIONARY`/`ROAMING` (hasn't detected the player at all — only `CHASING`/`SEARCHING` qualifies, matching "Stealth & Surprise Attacks" below: a creature with no idea anything is there can't react to it leaving reach), already used its reaction this round, or lacks LOS to `prev`. **Bugfix**: this used to only exclude `SLEEPING`, so an idle `ROAMING`/`STATIONARY` enemy that had never spotted the player (still failing its Stealth-vs-Passive-Perception check every turn) could still land a free reactive Opportunity Attack the instant the player stepped out of its threat range. Calls `enemy._attack_player(self)` directly (already turn-free, routes through `take_damage_raw` so Rage DR/Reckless/Orc-Shaman-poison/Retaliation all apply exactly as a normal enemy attack would). Checks `GameState.is_game_over` after each swing and bails the move if the player died.

**Once-per-round reaction flags** (never on `GameState` — per-entity combat state, same tier as `just_crossed_door`/`rooted_turns`):
| Attacker | Field | Reset point |
|---|---|---|
| Player | `_oa_used_this_round` | `_on_turn_started()`'s `if not came_from_revert:` block — survives `revert_to_waiting()` chains, only clears after enemies actually take a round |
| Enemy | `oa_used_this_round` | Top of `take_turn()`, unconditionally (before the prone/slowed/rooted early-returns — a slowed enemy still refreshes its reaction) |
| Companion | `oa_used_this_round` | Top of `take_turn()` |

**Two independent evasion flags, ORed together** in `_resolve_enemy_opportunity_attacks()`'s `evading` check — kept separate on purpose so nothing can stomp the other:
- **`GameState.player_evades_opportunity_attacks`** — Wild Heart Eagle form's own flag, kept in sync with `active_rager_form` by `_apply_active_rager_form_effects()` (true for as long as Eagle is the active form, see "Wild Heart Tier 2 talents" below) — NOT turn-scoped, never reset on a turn boundary.
- **`GameState.monk_disengage_this_round`** — Monk's Patient Defense and Step of the Wind (`player_monk.gd`, see "Monk class" below and "Bonus Action economy" above) each set this true on activation, folding a genuine Disengage into their existing effect. Reset every REAL turn start in `player.gd`'s `_on_turn_started()` (`if not came_from_revert:` block) — a Monk-only per-round buff, unlike Eagle's persistent form state, hence the separate flag rather than reusing `player_evades_opportunity_attacks` (reusing it would mean this same per-turn reset silently interrupts an active Eagle form).

While either flag is true, `_resolve_enemy_opportunity_attacks()` never lets an enemy actually swing (auto-evade, not "OA with disadvantage") but still logs a single gray flavor line if it prevented at least one attacker's OA that move. Neither flag has any effect on the player's own OAs against enemies.

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
- **Roll**: `d20 (Halfling-reroll-aware) + DEX mod + (proficiency_bonus if check_prof_dex)`, plus a
  flat `Stats.PASS_WITHOUT_TRACE_BONUS` (+10, while `pass_without_trace_turns > 0`) and/or
  `Stats.MINOR_ILLUSION_BONUS` (+5, while `minor_illusion_turns > 0`) — both folded into `total`
  and now also carried into the `stealth:` tooltip meta as `stbonus`/`stbonusid`, rendered by
  `TooltipFormatters.fmt_stealth_tooltip()` as its own `"+N (Pass Without Trace)"` line.
  **Bugfix**: these two bonuses used to only affect the roll total with no corresponding tooltip
  line — hovering the check showed `die + dex + prof` not summing to the displayed `total`, with no
  visible explanation for the gap.
  Rolled **once**, reused against every qualifying observer (5e group-stealth style) — but
  ADV/DISADV is evaluated **per observer**, and the baseline (no other modifier active) against an
  awake-but-unaware observer (`STATIONARY`/`ROAMING`) is a **plain, un-modified roll** — ADV only
  ever comes from an explicit source (stillness bonus, Zealous Presence, or `SLEEPING`'s own +1 —
  a sleeping guard is easier to sneak past than baseline), DISADV only from an explicit source
  (`GameState.player_has_stealth_disadvantage()` — the equipped body armor's
  `Item.stealth_disadvantage` flag, see `scripts/items/CLAUDE.md`'s "Body armor"). `STATIONARY`/
  `ROAMING` no longer carries its own flat DISADV term — the distance-to-DC bonus below is what
  makes an awake, nearby observer hard to sneak past, not a baked-in disadvantage on the roll
  itself. A second d20 is only rolled for an observer whose own net ADV/DISADV differs from 0 (max
  of two rolls if net > 0, min of two if net < 0), so two observers in the same turn (one asleep,
  one on stillness-ADV) can net different outcomes from what reads as "the same roll".
  **Distance-to-DC bonus**: each
  observer's effective passive perception is bumped by `max(0, observer.sight_range() -
  observer.min_dist_to(player))` (Chebyshev; `Enemy.sight_range()` is the public wrapper around
  the same per-enemy `_sight_range()`, darkvision bonus included, that already gates its FOV)
  **before** the compare — the closer you are relative to that observer's own max sight range, the
  harder the check gets, capping out (not auto-succeeding) at true adjacency — this is what
  replaced the old flat true-adjacency auto-notice (see "Enemy behavior states" below). Enemy
  notices iff `stealth_total < effective_pp` (ties favor the player — stays hidden).
  **`STATIONARY`/`ROAMING` have no other detection path against the Player** — `_decide_action()`'s
  own `can_see` branch for those two states is gated on `target is Player` (see below): vs the
  Player it's this check alone (no adjacency backstop anymore — the distance-to-DC bonus already
  covers it, same as `SLEEPING`); vs the Companion (no stealth-check equivalent exists for it) it's
  unchanged, immediate `can_see` → notice, adjacency backstop included.
- **`Enemy.passive_perception`**: static DC, see the schema table's `"passive_perception"` row
  above for the authored-vs-derived rule.
- **On detection**: `enemy._notice_target(player.grid_pos)` (wakes SLEEPING/STATIONARY/ROAMING →
  CHASING, sets `last_known_target_pos`, AND sets `just_noticed`/shows the "?" marker — see
  "Notice freeze" below) + a log line (`"<Enemy> [url=stealth:...]notices[/url] you!"`, `stealth:`
  meta, `TooltipFormatters.fmt_stealth_tooltip()`). **Silent on a non-detection** by default — no
  floater, no log spam for walking past sleepers. `GameState.debug_show_all_checks` (F3 debug
  panel checkbox, "All Checks" — same flag also covers Undead Fortitude, see `Enemy.
  take_typed_damage()`'s "Traits" section below) makes every roll — pass or fail — print a gray
  log line with the same tooltip; toggling it never changes the roll or its outcome, visibility
  only. `GameState.god_mode` appends a gray `(Stealth X vs PP Y)` suffix to either log line.
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
  `cast_magic_missile()`, `_resolve_spell_attack_bolt()` — covers both Chromatic Orb/Witch
  Bolt's primary AND leap target — and the per-target loop inside every AoE resolver:
  `_resolve_thunderclap()`, `_resolve_cone_aoe()`, `_resolve_sphere_aoe()`). Net effect: surprise
  ADV (Part B) only ever applies to the first attack of an engagement, and casting a spell/cantrip
  at (or catching in an AoE) an unaware enemy wakes it exactly like a melee/ranged/thrown attack —
  no "?" freeze, hit or miss.
- **Notice freeze — the golden "?"** (Shattered Pixel Dungeon-style): every transition from
  unaware (SLEEPING/STATIONARY/ROAMING) to CHASING that happens via *noticing* rather than *being
  attacked* — the stealth-check detection above (including at true adjacency vs. the Player, now
  folded into that same check via its distance-to-DC bonus, see below) and the Companion's own
  true-adjacency backstop for SLEEPING — all go through the shared
  `Enemy._notice_target(pos)` helper — sets `just_noticed = true` and shows a golden `"?"` label
  (`_notice_label`, `_show_notice_mark()`/`_hide_notice_mark()`, same per-enemy-child-Label pattern
  as `_zzz_label`). `_decide_action()` checks `just_noticed` first, before anything else: if set,
  it's consumed (cleared) and the enemy's ENTIRE round is spent on a `{"type": "notice"}` intent —
  no movement, no attack, marker stays up — so a freshly-noticed enemy always gets exactly one free
  round before it can act, regardless of distance (a far-off ROAMING enemy that spots you across a
  room also just notices that round rather than immediately closing distance). `_execute_action()`
  hides the marker the instant any OTHER intent type runs (the following round, when the enemy
  actually moves/attacks/etc.) — so the "?" is visible for exactly the one round between noticing
  and acting (it can still visually span two of the *player's* own turns, since it appears mid-
  round-N and only clears during round N+1's enemy phase — that's expected timing, not a second
  freeze round). **`SLEEPING`/`STATIONARY`/`ROAMING` vs. the Player have no LOS-based OR
  adjacency-based auto-notice anymore** — all three rely purely on the stealth-check roll above,
  whose distance-to-DC bonus already makes true adjacency (Chebyshev ≤ 1) an extremely hard (not
  automatic) check rather than a hard-coded free notice; `_decide_action()`'s `target is Player`
  branches for all three states simply `return {"type": "wait"}` now. **Vs. the Companion** (no
  stealth-check equivalent exists for it), all three keep their original, unchanged immediate
  `can_see`-or-adjacency → `_notice_target()` wake — this asymmetry is intentional, not a gap:
  removing the Companion's only detection path would make those enemies never react to it.

**Part B — Surprise-attack Advantage**: `PlayerVfx.has_advantage(enemy)` (`player.gd:1196`,
`player_ranged.gd`'s ranged call site) returns true iff the defender is unaware at the moment of
the attack roll: `Enemy.surprise_available` (one-shot, see below) OR Fog Cloud's Blinded clause OR
`behavior in [SLEEPING, STATIONARY, ROAMING]`.

**`Enemy.surprise_available` — SPD-style re-triggering surprise** (replaces the old
`door_ambush`, and the old rule that surprise was "purely a function of `behavior`, never
re-evaluated against live FOV" — a deliberate reversal, matching Shattered Pixel Dungeon's own
live-sight tracking instead of a coarse state gate). The crux distinction: **surprise persists to
the player's next attack only when the enemy's OWN turn is what re-establishes sight of an
already-noticed target** — a stealth-check-driven notice (the *player's* turn causing an enemy to
spot them) never sets this flag, because the enemy still gets its own notice-round turn before the
player can act again, so by then it's no longer surprised (covered instead by the plain
`behavior in [SLEEPING, STATIONARY, ROAMING]` check above, unchanged). Concretely, `surprise_available`
is set only inside `_decide_action()`'s `CHASING`/`SEARCHING` branches, when this enemy's own
per-turn LOS check (`can_see`) flips from false to true (tracked via `_had_los_to_player`) — one
general mechanism covering three distinct scenarios: a door-camping ambush (enemy was chasing
blind toward `last_known_target_pos`, a closed door blocked LOS, then it crosses the door and
regains sight on its own turn), a mid-chase obstacle break (the SPD "ring around the rosie" tech —
circling a single vision-blocking obstacle so a chasing enemy repeatedly loses/regains sight, each
regain re-arming a surprise window; the Opportunity Attack a player takes for stepping out of the
enemy's threat range mid-circle is the intended balancing friction, unchanged by this system), and
the target's Invisibility ending while still being actively hunted. **Unlike a fresh
SLEEPING/STATIONARY/ROAMING→CHASING notice, this regain does NOT freeze the round** — no
`_notice_target()` call, no golden "?", no `"notice"` intent; the enemy was already actively
hunting the player (CHASING/SEARCHING is itself proof of prior awareness), so re-establishing sight
isn't a fresh discovery and the enemy acts immediately (moves/attacks) the same turn it regains LOS.
This was a deliberate fix: freezing every LOS regain mid-chase (e.g. a slower enemy losing sight of
a fleeing player for a moment, then re-acquiring it through a doorway) played as the enemy
"forgetting" the player and re-discovering them from scratch, which reads as absurd once you've
already been spotted and are actively being hunted — the surprise-ADV window is the correct reward
for a door-camping ambush, a full wasted round is not. **`surprise_available` never grants an enemy a bonus against the player** — it is read
only by `PlayerVfx.has_advantage()` (player-attacks-enemy), never by any enemy-attack-roll path;
this holds even for an enemy that momentarily loses/regains sight of an invisible player itself —
there is no symmetric mechanic and none should ever be added.
Lifetime: set true either by the regain-branch above or (implicitly, transitively) never by
`_notice_target()`/`on_disturbed()` themselves (both only set `_had_los_to_player = true`, to
prevent the very next CHASING check from spuriously re-firing a regain the round right after any
notice). Expires — cleared in `_execute_action()`'s expiry guard — the moment this enemy completes
one further REAL action (non-`"notice"` intent) without the player having consumed it via
`has_advantage()`, so the window is exactly "one round after the regain event, or until the enemy
next acts, whichever the player misses first."
**BUGFIX (`_surprise_before_decide`)**: the expiry guard used to snapshot `surprise_available`
at the *top of `_execute_action()`* — but `decide_turn()` (which can set the flag true on a fresh
regain) always runs immediately before `execute_turn()`/`_execute_action()` for the same enemy in
the same round (`take_turn()` = `execute_turn(decide_turn())`), so the snapshot always saw the
flag as "already true," and the guard wiped it back to false in the very same round it was set —
before the player ever got a turn to attack with it. A door-camping ambush (or any other regain)
was therefore silently never rewarding the surprise-ADV it was supposed to. Fixed by snapshotting
`surprise_available` into `_surprise_before_decide` at the very TOP of `decide_turn()` (before that
call can mutate it) and having the expiry guard read that snapshot instead of the live,
already-mutated value — only a flag that was already true going into decide_turn() (i.e. survived
a full round unconsumed) expires; a flag freshly set this round survives into the player's next
turn as intended.
**BUGFIX (regain-check hoisted to the top of `_decide_action()`)**: the `_had_los_to_player`/
`surprise_available` bookkeeping used to live only inside the `CHASING`/`SEARCHING` arms of
`_decide_action()`'s `match behavior:` block — but several early-return branches evaluated BEFORE
that match block (one-shot `thrown_weapon`, Imp's `invisibility`, Spider's `web`, Quasit's `scare`,
each gated on `behavior in [CHASING, SEARCHING]` and its own `has_clear_shot()`/range check) could
return an intent without ever reaching it. Concretely: an Orc Warrior chasing blind toward a closed
door, regaining LOS by crossing it, in Javelin range of the player — fell into the `thrown_weapon`
branch and threw immediately, `surprise_available` never got set, and the door-ambush granted no
ADV at all on the player's next attack, for any enemy with one of those four pool keys. Fixed by
moving the exact same regain check (`can_see` → `_had_los_to_player` false→true → set
`surprise_available`/update `last_known_target_pos`/`_search_heading`) to run unconditionally right
after target selection, before any early-return branch; the match block's own `CHASING`/`SEARCHING`
arms now only handle behavior transition + acting, not the surprise bookkeeping itself.
**Call-order rule (BUGFIX — this used to be dead code)**: every attack site must read
`has_advantage(enemy)` (and any `enemy.behavior`-based DISADV exemption, e.g. the ranged/thrown
melee-range penalty's "unaware target" carve-out) **before** calling `enemy.on_disturbed(...)` —
`on_disturbed()` immediately flips a SLEEPING/STATIONARY/ROAMING defender to `CHASING`, so reading
either afterward always sees an already-awake target and silently loses the surprise. The pattern
at every one of the six attack-roll call sites (`_bump_attack()`, `_resolve_cleave_attack()`,
`resolve_opportunity_attack()`, `PlayerRanged.ranged_attack()`, `PlayerThrowTool._throw_weapon()`,
`SpellEffects.cast_spell()`/`_resolve_spell_attack_bolt()`) is: capture `has_advantage(enemy)`
into a local `was_surprised` as the very first thing, THEN call `on_disturbed()`, THEN use the
captured value later in the roll — the ranged/thrown/spell sites ALSO capture `PlayerVfx.
is_target_unaware(enemy)` into a separate `target_was_unaware` local before `on_disturbed()`, for
the melee-range DISADV exemption (see the "Advantage / Disadvantage" table's own Exemption note —
`is_target_unaware()` is deliberately narrower than `has_advantage()`, so this is a second,
independent capture, not a reuse of `was_surprised`).
`_resolve_offhand_attack()` is the one deliberate exception — it always fires in the same player
turn right after the main-hand swing already consumed the surprise, so the target is already
`CHASING` by the time it runs (correct: only the first attack of an engagement surprises).

## Exhaustion

D&D 2024's simplified Exhaustion track — `Stats.exhaustion_level: int` (0-6, serialized) — is
implemented as a debuff scaffold: every mechanical consequence works, and one real source now
grants it. It exists so a future exhaustion source (a starvation mechanic, a boss curse, a
specific trap) only needs to write the field — every consequence below already fires
automatically.

- **Source: death-save revival**. `GameState._end_death_save_sequence(true)`
  (`scripts/autoloads/game_state.gd`, root CLAUDE.md's "Death saves") increments
  `exhaustion_level` by 1 every time the player claws back from 0 HP via a successful death-save
  sequence. If that increment reaches **level 6, the revival is aborted** — the function instead
  runs the normal death tail (`is_game_over = true`, `player_died.emit()`) instead of setting
  `current_hp = 1`, i.e. a 6th death-save revival is fatal on the spot, matching 5e 2024's own
  "exhaustion 6 = death" rule. Cheat-death holds (Bruiser R3's "refuse to fall", Orc Relentless
  Endurance) intercept `check_player_death()` **before** `begin_death_save_sequence()` ever runs —
  neither grants exhaustion, only an actual death-save revival does.
- **Visible in the status tray**: `hud.gd._update_status_icons()` appends an `"exhaustion"` entry
  (`res://icons/status/exhaustion.png`, no real art yet — renders as a tinted placeholder square
  like every other art-less tray entry) whenever `exhaustion_level > 0`; hover text
  (`status_tooltips.gd`) reports the current level, its flat d20 penalty, movement fraction, and
  the long-rest-removes-1/level-6-is-fatal rules.

- **-2 to every player d20 test per level**: `CombatMath.exhaustion_penalty() -> int` (`-2 *
  exhaustion_level`) is a flat modifier added into the caller's own bonus-total sum at every
  identified player d20 roll site — **never** folded into `CombatMath.roll_with_adv_disadv()`'s
  returned `die` itself, since `die` also drives nat-20 crit / nat-1 fumble detection at every one
  of those sites; corrupting it would silently break crit detection under exhaustion. Wired into
  all 6 player attack-roll sites (melee/cleave/off-hand/OA in `player.gd`, ranged in
  `player_ranged.gd`, thrown in `player_throw_tool.gd`), both cantrip/leveled-spell ATTACK_ROLL
  casts (`spell_effects.gd`), the two Stealth-vs-Passive-Perception-check-adjacent player saves in
  `player.gd`'s `_on_turn_started()` (Frightened, the Bearded Devil Poisoned-condition-end save),
  Quasit's Scare save (`enemy.gd._execute_cast_scare()`, a player save despite living in `enemy.gd`),
  the Stealth check itself (`player.gd._resolve_stealth_check()`), and Thief Tools' disarm/lock-pick
  checks (`player_thief_tools.gd`). `roll_with_adv_disadv()` also returns the penalty value as its
  own `"exhaustion_penalty"` dict key (self-documenting for any future call site) for callers that
  already destructure the returned dict rather than calling `CombatMath.exhaustion_penalty()`
  directly. **Visible in every affected roll's own hover tooltip, not just the status tray**: each
  of the 16 call sites above now also threads its captured penalty value into that roll's `[url=]`
  meta string as its own `exh=` field, and `TooltipFormatters.fmt_hit_tooltip()`/`fmt_sphit_tooltip()`/
  `fmt_save_tooltip()`/`fmt_stealth_tooltip()` (`scripts/ui/tooltip_formatters.gd`) each render a
  `[color=cyan]-N[/color]  (Exhaustion)` line whenever `exh != 0` — so a hit/save/check breakdown
  taken while exhausted now visibly itemizes the penalty instead of silently folding it into the
  final total (see `scripts/ui/CLAUDE.md`'s "Roll tooltips must stay complete" convention).
- **-1/6 movement speed per level**: reuses the exact same `TurnManager.enemy_actions_this_round =
  2` knob Slowed (Mud/Water) already drives — see root `CLAUDE.md`'s "Player movement-speed visual
  consistency" permanent rule: the move tween itself never changes, only how many actions the
  environment gets for that one move. `Player._exhaustion_move_penalizes()` calls
  `Player._consume_duty_cycle("exhaustion", exhaustion_level, 6)` (the shared
  `Player._speed_gate_accum` dict + `CombatMath.tick_duty_cycle()` accumulator — see "Movement
  speed scaling" below), which fires true for exactly `exhaustion_level` out of every 6 real moves,
  spread evenly across the cycle rather than front-loaded (level 3 penalizes 3 of every 6 moves =
  50% slower, matching -15 ft of the 30 ft baseline exactly). **Bugfix**: this used to be a plain
  `counter % 6 < exhaustion_level` check, which is actually front-loaded (always the first N of
  every 6 moves) despite this same claim of an even spread already being the intent — now genuinely
  evenly spread via the shared accumulator (e.g. level 2 fires on moves 3 and 6, not 1 and 2). Wired
  into both `_try_move()` (WASD) and
  `_apply_queued_step_speed()` (click-to-move/enemy-chase), alongside their existing Slowed checks
  — same "both movement paths" coverage Slowed itself has, and (like Slowed) now also gated on
  `Player.is_being_pursued()` so an unthreatened exhausted walk doesn't hitch every Nth step (see
  "No free-move/Slowed/Exhaustion duty-cycle bookkeeping" above). A free move (Expeditious
  Retreat/Longstrider/Wood Elf/Battlefield Expert's side-step) returns before
  reaching this check, so it doesn't advance the duty-cycle counter either — a documented
  simplification, not a bug (matches every other per-round-cap field's own reset-on-revert
  precedent).
- **Removal**: `GameState.long_rest()` decrements `exhaustion_level` by exactly 1 (floored at 0) —
  matches D&D 2024's own "long rest removes 1 level" rule. No other removal path exists.
  **Level 6 is not actually reachable as a standing state** — the death-save source above checks
  for it at the moment of the would-be 6th increment and kills the character instead of ever
  setting the field to 6, so `exhaustion_level` tops out at 5 in practice.

## Bonus Action economy

`GameState.bonus_action_used: bool` — a single shared once-per-real-round gate over every
formerly-unlimited "free action" (`TurnManager.revert_to_waiting()`) ability that could otherwise
be chained infinitely in one round before the player's real action (direct owner request — the
old model let a Barbarian activate Rage, arm Zealot Strike, execute Frenzy, cast Blade Ward, and
more, all before spending their one real action, with nothing gating how many "free" abilities
stacked in a single round). Reset in `player.gd`'s `_on_turn_started()`'s `if not came_from_revert:`
block, alongside `grip_of_the_forest_used_this_turn` etc. Captured in `RewindManager.
REWIND_GAMESTATE_FIELDS` so Backspace can't be used to refresh it for free. `invincible` (God
Mode) skips consumption entirely at every gated site, same "skip all consumption" convention as
every other resource — see root `CLAUDE.md`'s "Invincible mode" rule.

**Gated abilities** (each checks `GameState.bonus_action_used` before spending its own resource,
refuses with a gray "Already used your bonus action this turn." log line if already spent, and
sets `bonus_action_used = true` only on confirmed activation/resolution — matching whatever
"spend only on confirmed use" convention that ability already followed):
- **Rage** — `player.gd._activate_rage()`.
- **Frenzy** — `player_berserker.gd.execute_frenzy()`.
- **Zealot Strike** — `player_zealot.gd.activate_zealot_strike()` (gated on arming).
- **Flurry of Blows** — `player_monk.gd.activate_flurry_of_blows()`.
- **Step of the Wind** — `player_monk.gd.activate_step_of_wind()` (its own pre-existing
  `step_of_wind_used_this_turn` per-turn cap is unaffected, both gates must pass). Also sets
  `GameState.monk_disengage_this_round = true` on arm (Disengage-for-the-round, see the "Monk
  class" section above and the "Opportunity Attacks" section's "Two independent evasion flags").
- **Patient Defense** — `player_monk.gd.activate_patient_defense()` (its own pre-existing
  `PlayerMonk.is_engaged()` gate is unaffected, both checks must pass). **Reworked from a
  turn-costing action to a genuine Bonus Action** (D&D 2024 PHB text, direct owner correction) —
  used to call `TurnManager.begin_player_action()`/`on_player_action_complete()` like a Dodge
  action substitute; now takes the same free-action shape as Flurry of Blows (no `TurnManager`
  envelope at all). Also sets `GameState.monk_disengage_this_round = true` alongside
  `Stats.dodge_turns = 1` (Disengage folded into the same activation, see the "Monk class" section
  above).
- **Halfling Nimbleness** — `player_halfling.gd.resolve_nimbleness()` (gated on confirmed
  resolution, alongside its own `used_this_turn` cap).
- **Cloud Giant's Jaunt** — `player_goliath.gd.resolve_cloud_teleport()` (gated on confirmed
  resolution, alongside its own charge spend).
- **Orc Adrenaline Rush** — `player_orc.gd.activate_adrenaline_rush()`.
- **Human Heroic Inspiration** — `player_human.gd.activate_heroic_inspiration()`.
- **Blade Ward** — `spell_effects.gd.cast_leveled_self()`'s `"blade_ward"` branch. **Reworked to
  match 5e RAW's own bonus-action casting time**: this cantrip used to cost the player's full
  turn like any other `cast_leveled_self()` spell; it's now gated BEFORE the turn/slot are ever
  touched (a top-of-function early check on `spell.effect_id == "blade_ward"`, since every other
  spell dispatched through this shared function still costs a normal turn) and, once cast, takes
  the same `player._reverted_this_round = true; TurnManager.revert_to_waiting()` free-action exit
  Shield's own branch already uses — Blade Ward no longer ends the player's turn at all, it just
  spends the Bonus Action. `Spell.casting_time` updated to `"Bonus Action"` (`spell_db.gd`).
- **Grip of the Forest** — `player.gd._activate_grip_of_the_forest()` (gated on
  activation/arming, alongside its own `grip_of_the_forest_used_this_turn` cap).
- **Aasimar Celestial Revelation** — `player_aasimar.gd.activate_celestial_revelation()` (checked
  before the picker even opens, so an already-spent bonus action never wastes the click) AND
  `resolve_celestial_revelation_choice()` (the actual commit point, defense-in-depth).
- **Dragonborn Draconic Flight** — `player_dragonborn.gd.activate_draconic_flight()`.
- **Dwarf Stonecunning** — `player_dwarf.gd.activate_stonecunning()`.
- **Goliath Large Form** — `player_goliath.gd.activate_large_form()`, **activation only** — the
  same function's "second press while already active ends it early" branch (`end_large_form()`)
  returns before ever reaching the gate, so ending the form stays a genuinely free action.
- **Warlock Hex** — `spell_effects.gd.cast_leveled_auto_hit_at_enemy()`'s top-of-function check
  (before the turn/slot are touched) covers BOTH a fresh manual cast and a manual re-cast off
  Bloodhound-style free-recast-on-kill (`Stats.hex_free_recast_pending`, consumed inside
  `_resolve_hex()`, which only ever runs through this same entry point — there is no automatic-
  reflex path for Hex, unlike Ranger's Bloodhound R3 below). `Spell.casting_time` updated to
  `"Bonus Action"`.
- **Ranger Hunter's Mark** — `player_ranger_talents.gd.commit_mark()` (the manual arm-then-click
  cast/re-cast path — this spell's casting time was already "free," i.e. never called
  `TurnManager.begin_player_action()` at all, so it's exactly the kind of ability this whole
  feature targets). **Also gates the AUTOMATIC Bloodhound R3 remark**
  (`try_bloodhound_remark()`, called unconditionally from `Enemy.die()` when the Marked target
  dies) — a genuinely automatic trigger, not a player click: if the Bonus Action is already spent
  when the kill happens, R3's auto-remark does NOT fire; it falls through to the same
  `hunters_mark_free_recast_pending` fallback the sub-R3 case already uses (a gray "mark a new
  target for free on your next turn" line — the player can still manually re-mark once the Bonus
  Action refreshes, no double penalty). If the Bonus Action IS available, the auto-remark fires
  and consumes it. The non-Bloodhound "free re-mark window" itself (`hunters_mark_free_recast_
  pending` → `_available`, consumed by a normal manual `commit_mark()` re-click) needs no separate
  handling — it's just another `commit_mark()` call, already covered by that function's own gate.
- **Misty Step** — `spell_effects.gd.cast_leveled_at_tile()`'s `"misty_step"` branch. Same rework
  as Blade Ward — used to cost the player's full turn like every other `cast_leveled_at_tile()`
  spell; now gated at the top of the function (before turn/slot) and exits via
  `revert_to_waiting()` instead of falling through to `_handle_post_attack_turn()`.
  `Spell.casting_time` → `"Bonus Action"`.
- **Barkskin** — `spell_effects.gd.cast_leveled_self()`'s `"barkskin"` branch. Same rework —
  `Spell.casting_time` was already (incorrectly) labeled `"Free"` in `spell_db.gd` despite the
  code costing a full turn; the code now matches the label. `casting_time` → `"Bonus Action"`.
- **Expeditious Retreat** — `spell_effects.gd.cast_leveled_self()`'s `"expeditious_retreat"`
  branch. Same rework and same pre-existing label mismatch as Barkskin (was `"Free"` in
  `spell_db.gd`, actually cost a full turn in code) — now genuinely free via
  `revert_to_waiting()`, gated, `casting_time` → `"Bonus Action"`. **Not to be confused with the
  spell's own EFFECT** (its buff grants one free move per turn while active, `Player._try_move()`'s
  duty-cycle-free-move check) — that's a separate, pre-existing mechanic and is completely
  untouched by this rework; only the CAST itself changed from turn-costing to Bonus-Action-costing.
- **Hail of Thorns** / **Ensnaring Strike** (toggle-arm reactions) —
  `player_ranger_talents.gd.activate_hail_of_thorns()`/`activate_ensnaring_strike()`. Both were
  ALREADY free actions (never called `TurnManager.begin_player_action()` at all — same shape as
  Hellish Rebuke's toggle) so no turn-cost rework was needed, just the gate — and **only on
  arming**: `if not <armed> and GameState.bonus_action_used: refuse`. Disarming (pressing again
  while already armed) stays free with no check at all, matching Hellish Rebuke's own "turning it
  off is always allowed" precedent. `Spell.casting_time` → `"Bonus Action"` for both (was `"Free"`).

**Witch Bolt's initial cast is deliberately NOT gated** — user confirmed it stays a normal,
turn-costing action, unchanged. **Its recurring per-turn jolt tick IS gated**, as an automatic
trigger (same "automatic BA consumption at turn end, silently skips if unavailable" shape as the
Rage leftover-extend and Monk Bonus Unarmed Strike mechanics): `player.gd._on_turn_ending()`, right
after the `witch_bolt_just_cast` check — if `GameState.bonus_action_used` is already true, the tick
is skipped entirely for that round (`return` before touching `witch_bolt_turns`/dealing damage) —
**no damage, but the duration/Concentration backstop is untouched too**, so a missed tick never
ends the spell early, it just tries again at the end of the player's next turn. If available, it's
consumed (`bonus_action_used = true`) and the jolt fires exactly as before. Ordering note: this
check runs AFTER the Rage leftover-extend check earlier in the same function, so if both Rage and
Witch Bolt are active in the same turn, Rage's own extend claims the bonus action first.

**Deliberately NOT gated**: Shield (spell) — stays a free action; it simulates a 5e Reaction,
which this engine has no framework for, and the direct owner decided against folding it into this
system. Goliath's Fire/Frost/Hill/Storm/Stone Giant Ancestry variants — only Cloud's Jaunt is
gated; the other five stay free since they're "arm now, trigger later on a hit" reactions, not
proactive actions. Wild Heart's Animal Form cycling (Bear/Eagle/Wolf toggle) — stays free, it's a
Barbarian subclass mechanic, not a race/species feature, and the owner wants form-switching itself
to never cost anything. Equip/unequip/drop/torch-lighting/Inspect/the Versatile-grip toggle, and
Monk's auto-granted Extra Attack window (an automatic side effect of an attack, not a standalone
player choice) are untouched — administrative/passive actions were never in scope.

**Monk's Bonus Unarmed Strike is now genuinely gated too** (`player_monk.gd.
try_bonus_unarmed_strike()`, called from both the hit and miss tails of `_bump_attack()`) — a real
behavior change, not just a check: this used to be an unconditional free extra attack whenever
Martial Arts was active. Two cases:
- **Flurry of Blows NOT pending**: right before firing, checks `GameState.bonus_action_used` — if
  already spent, the strike doesn't fire at all (silent no-op, no log spam); if available, consumes
  it and fires exactly ONE bonus strike, same as before.
- **Flurry of Blows pending** (`flurry_pending == true`): Flurry's own activation already spent
  the Bonus Action when it was armed (see the gated-abilities list above) — this trigger bypasses
  the check/consumption entirely and just resolves the doubled-strike loop as normal.
Net result: "2 attacks for 1 Bonus Action" when Flurry fires, "1 attack for 1 Bonus Action" when it
doesn't, "0 attacks" if the Bonus Action was already spent on something else this round (and Flurry
wasn't what spent it).

**Rage house-rule (on top of 5e 2024, direct owner request)**: a leftover, UNUSED Bonus Action at
the end of a real player turn automatically extends Rage — `player.gd._on_turn_ending()` (fires
once per real turn, `TurnManager.player_turn_ending`'s own contract, so no extra revert guard is
needed): `if _is_raging and not GameState.bonus_action_used:` sets `_rage_attacked_this_turn =
true` and `GameState.bonus_action_used = true`, logging a gray "Your leftover bonus action keeps
the Rage going." line. This reuses the exact `combat_last_turn` check `_on_turn_started()`'s
rage-tick block already reads at the top of the FOLLOWING turn — it's an additional trigger for
Rage's existing "refreshed to 1 turn" rule, alongside (not replacing) the pre-existing "attack or
be attacked last turn" trigger.

**HUD indicator**: NOT a status-tray icon — direct owner correction (it's a per-round resource
gauge, not a buff/debuff on the player). `hud.gd`'s `_bonus_action_label` is a BG3-style single
filled/empty-circle pip (`_update_bonus_action_indicator()`), built the same way as the short-rest
pip row and placed on the same row next to it (`$StatsPanel`, right of the portrait column) —
green filled while available this round, gray hollow once `bonus_action_used` is true, native
`tooltip_text` on hover. Refreshed via the same chokepoints the old status-tray entry used
(`TurnManager.player_turn_started`, `GameState.ability_bar_changed` — every gated site above emits
`ability_bar_changed` right after flipping the flag).

**Ability-bar greying + red reason text**: `GameState._bonus_action_blocks(ab) -> bool` is the
single shared check `is_ability_usable(ab)`/`ability_unusable_reason(ab)` both call — an ADDITIONAL
condition layered on top of each ability's own existing gate, never a replacement.
`GameState.BONUS_ACTION_ABILITY_IDS` (a flat `PackedStringArray`) lists every plainly-identified
gated ability_id (Rage, Frenzy, Zealot Strike, Flurry of Blows, Step of the Wind, Halfling
Nimbleness, Adrenaline Rush, Draconic Flight, Stonecunning, Large Form,
Celestial Revelation, Hunter's Mark, Grip of the Forest — Human's Heroic Inspiration is
deliberately NOT in this list, a direct owner correction: it's a real free action per 5e RAW, not a
Bonus Action spend, see this file's "Human" section); Cloud's Jaunt (`ability_id ==
"giant_ancestry"`, shared by all 6 Giant Ancestry variants — only greyed when
`race_variant == Stats.GiantAncestry.CLOUD`), the 7 gated spell abilities (`ability_id.begins_with
("spell:")` — Blade Ward/Hex/Misty Step/Expeditious Retreat/Barkskin — checked by spell id since a
spell ability's id is prefixed), and Hail of Thorns/Ensnaring Strike (`"hail_of_thorns_toggle"`/
`"ensnaring_strike_toggle"` — only blocked while NOT yet armed, since disarming must always stay
free; each checks its own `Stats.hail_of_thorns_armed`/`ensnaring_strike_armed` directly) are all
handled as separate branches inside `_bonus_action_blocks()` since their bare ability_id doesn't
uniquely identify the gated case (or, for the two toggles, needs armed-state awareness the flat id
list can't express). `ability_unusable_reason()` shows a red `"No Bonus Action"` line ONLY when no other
ability-specific reason (e.g. `"No Rage"`, `"Not Engaged"`) is ALSO true — every gated ability's
own `match` arm falls through (doesn't `return`) when its own condition is satisfied, so the
generic Bonus-Action check right after the `match` block is what actually supplies the reason in
that case.

## Multi-turn action interrupts (short rest / armor change / scroll learn)

`Player._rest_interrupted()` (`scripts/entities/player.gd`) is the single interrupt check shared
by all three multi-turn player actions (`GameState.short_rest_active`, `armor_change_active`,
`scroll_learn_active` — see `scripts/autoloads/CLAUDE.md` and `scripts/items/CLAUDE.md`'s "Body
armor"/"Scroll of &lt;Spell&gt;" sections), called every real turn from `_on_turn_started()`
alongside each action's own countdown. **Not** a flat "any enemy in FOV" check (that used to
interrupt on a sleeper you'd already knowingly walked past to start resting) — it tolerates an
enemy you were already aware of when the action began, matching SPD's "you knew that sleeper was
there" feel:

- **`_interrupt_baseline: Dictionary`** (`Enemy` node → `grid_pos`) snapshots every enemy visible
  (`_fov_this_turn`) the first turn any of the three actions is active (`_interrupt_baseline_set`
  gates the one-time capture; both are cleared the instant none of the three actions are active,
  so the next one starts a fresh baseline). Captured right after `_fov_this_turn` is refreshed in
  `_on_turn_started()`, before any of the three action blocks run.
- **`_rest_interrupted()`** returns true iff any currently-visible enemy either: is currently
  `CHASING`/`SEARCHING` (an active hunter always interrupts, whether it was already hunting at
  baseline or just noticed — a fresh notice flips behavior to `CHASING` the same turn
  `_resolve_stealth_check()` catches it, so this alone covers "the sleeper woke up" with no
  separate behavior-change tracking needed); OR isn't in `_interrupt_baseline` at all (a genuinely
  new arrival since the action started); OR IS in the baseline but its `grid_pos` has changed
  (a `ROAMING` enemy that wandered since, even while still nominally unaware). A `SLEEPING`/
  `STATIONARY` enemy that was already visible and hasn't moved never interrupts on its own.
- Short rest additionally gates on `not _rest_interrupt_shown` (shows `rest_interrupt_panel.gd`
  once, not spam every tick); armor change / scroll learn have no such prompt (interrupt outright,
  no state consumed yet, see their own docs) — both compare identically via `_rest_interrupted()`.

## Enemy behavior states
`SLEEPING → STATIONARY → ROAMING → CHASING → SEARCHING`

**SLEEPING**: shows zzz label. Vs. the Player: no free wake of any kind anymore (neither LOS- nor adjacency-based) — detection is entirely the Stealth-vs-Passive-Perception check's job, see "Stealth & Surprise Attacks" below. Vs. the Companion: true adjacency (Chebyshev ≤ 1) in `_decide_action()` still routes through `_notice_target()` (golden "?", one-round freeze) instead of attacking immediately.
**ROAMING**: waypoint BFS. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks tile at Chebyshev ≥ 4. Follows `_roam_path: Array[Vector2i]` via `_bfs_to()`. Falls back to `_do_random_step()` if blocked. Vs. the Player: no free wake, same as SLEEPING above. Vs. the Companion: spotting it (`can_see`) still routes through `_notice_target()` — a one-round freeze before it starts actually chasing.
**CHASING**: follows the selected target directly. Tracks `_had_los_to_player` each decision — the false→true edge (this enemy's own turn regaining sight it had lost, e.g. crossing a door or rounding an obstacle) sets `surprise_available = true` and acts the same turn (no freeze — see "Stealth & Surprise Attacks" above for why a mid-chase regain doesn't burn a round like a fresh notice does). Records `_search_heading` (direction toward target) each turn target is visible.
**SEARCHING**: entered when a CHASING enemy reaches `last_known_target_pos` without LOS. Searches for 7 turns in `_search_heading` direction (BFS to `_search_target = last_known_pos + heading * 5`). If the target is spotted → CHASING (same no-freeze LOS-regain rule as CHASING above). After 7 turns → ROAMING. Fields: `_search_heading: Vector2i`, `_search_turns_remaining: int`, `_search_target: Vector2i`, `_search_path: Array[Vector2i]`.

`_roam_path` and `_roam_target` are cleared on state transitions.

**Every `_decide_action()`/`_execute_action()` path must await something real** (a move tween or the idle timer) — a branch that returns with zero elapsed time makes `TurnManager._process_enemies()` burn through that enemy's turn instantly, which can make a live-but-stuck floor feel empty/cleared even with `TurnManager.fast_mode == false`. Two branches previously fell through without awaiting: `_act_toward()`'s BFS-fallback failure (both an empty BFS path and a BFS path whose first step turns out unwalkable) and `_execute_action()`'s `"search"` case's SEARCHING→ROAMING transition (turns exhausted) — both now explicitly `await get_tree().create_timer(0.04 if TurnManager.fast_mode else 0.08).timeout` before returning.

### `take_turn()` split: decide vs execute
Per `docs/architecture/enemy_system_architecture.md` §1: `take_turn()` is now a thin
`await execute_turn(decide_turn())` wrapper. `decide_turn()` (public — `TurnManager._process_enemies()`
calls it directly, see `scripts/autoloads/CLAUDE.md`'s "Turn sequence") does the per-turn ticks
(`_tick_abilities`/`_tick_regeneration`/`_tick_speed_gate`/`_tick_invisibility`/`_tick_shape_shift`)
and the prone/slowed early-return turns, then calls `_decide_action() -> Dictionary` (reads state,
picks a target, advances the FSM, returns an intent like `{"type": "act_toward", "target": ...,
"can_see": ...}`) — **never** awaits, opens a door, moves, or attacks; only this enemy's own
fields (behavior/FSM/search state) are mutated. `execute_turn(intent)` (also public) is
`await _execute_action(intent)` (all tweens/animation/movement/door-opens/attacks/logging,
dispatched on `intent.type`: `attack`/`act_toward`/`roam`/`search`/`wait`/... ). **Round
simultaneity**: `TurnManager._process_enemies()` calls `decide_turn()` on every enemy first
(identical pre-round world state for all of them), THEN `execute_turn()` on each in the existing
sequential order — so an earlier enemy's door-open/move this round can never leak into a later
enemy's own decision for that same round (the concrete bug this fixed: a melee enemy opening a
closed door mid-round no longer grants a ranged enemy standing behind it same-round
line-of-sight to shoot through — the ranged enemy already decided, against the door-still-closed
state, before the melee enemy's door-open executes). `Companion.decide_turn()`/`execute_turn()`
mirror this exact split (`companion.gd`) since companions share the same enemy phase. This seam is
also where every future need (archetypes, boss phases, Phase-2 determinism) hangs — see the
architecture doc for why.

**BUGFIX — plain enemies were getting a free attack after closing distance**: the July 2026
decide/execute-split refactor (`62a1039`) rewrote `_act_toward()` into a step-budget loop (to
support the `"aggressive"` trait's +1 step and above-baseline `"speed"` movers) but left an
unconditional `if _in_attack_range(target): _attack_target(target)` check AFTER the loop — so even
a plain 1-move enemy (`total_steps == 1`, no extra budget) would move one step and then, if that
step happened to land it adjacent, attack in that same turn. This contradicted both this project's
long-standing design rule (default enemy = move OR attack, never both in one turn — only an
enemy with spare step budget, like Aggressive Orc Warrior, can spend a step closing distance and
still attack with a remaining step) and the architecture doc's own stated intent ("melee (default):
today's logic unchanged — adjacent → attack, else step toward target"). Fixed by deleting the
post-loop check entirely: the in-range check that already sits at the TOP of each loop iteration
is sufficient on its own — it naturally re-fires only when a LATER iteration exists (i.e. the
enemy had spare step budget), which is exactly the Aggressive/fast-mover case. A plain enemy that
spends its one-and-only step closing distance now correctly ends its turn without attacking, even
if that step lands it adjacent.

### Targeting: player + companion
`_decide_action()` no longer hardcodes the player as the target. `_get_target_candidates()` returns every live `is_friendly` entity currently relevant — `[player, GameState.player_companion]`, skipping either if null/dead. `_select_target(candidates)` picks: whichever candidate is already adjacent (Chebyshev 1) wins outright — "first to reach range" — tie-broken by lower current HP if both are adjacent; otherwise the nearer candidate by squared distance. No target-lock field: every turn re-asks "who's closest / who's adjacent" from current positions (see architecture doc §5 for why a lock was rejected). `_act_toward(target: Node)` and `_attack_target(target: Node)` work against either a `Player` or a `Companion` — attack dispatch is `if target is Player: _attack_player(target) elif target is Companion: _attack_companion(target)`. `Companion.take_damage_from_enemy()` is the damage-intake path for the latter (already existed on `Companion`, just never had an enemy-side caller before).

### Attack profiles (ranged enemies)
Pool entries may set `"attack_profile": {"kind": "ranged", "range": N, "projectile": "..."}` (absent = implicit melee, zero change for existing entries). `Enemy._in_attack_range(target)` reads `_type.get("attack_profile", {})`: melee requires Chebyshev == 1; ranged requires Chebyshev ≤ `range` AND `_dungeon_floor.has_clear_shot()`. `_act_toward()` calls `_attack_target()` once in range, otherwise steps toward the target exactly like melee (reuses the same BFS/greedy stepping — approaching until in range, not until adjacent).

**No shooting through a blocking body — or through grass it can't see through**: `DungeonFloor.has_clear_shot(from, to)` (`scripts/world/CLAUDE.md`) is `has_line_of_sight()` (terrain/doors/**GRASS**) **plus** `get_blocking_body_on_line()==null` (no Enemy/Player/Companion on an intermediate tile of the ray). Deliberately uses the stricter `has_line_of_sight()`, not the permissive `has_ranged_los()` the player's own ranged/spell targeting uses — an aware/CHASING enemy tracking a target's last-seen position must lose its shot the instant grass actually breaks sight, not keep sniping through foliage it can't see into (bugfix: an Orc Warrior was throwing its Javelin at a player hidden behind grass it had no LOS to). Every enemy-side "can I take this shot" check — `_in_attack_range()`'s ranged branch, `_pick_ready_ability()` (the generic ranged-ability dispatch), and both `"thrown_weapon"` range checks (opener + flee-only parting shot) — uses `has_clear_shot()` instead of the bare terrain check, so an enemy whose own ally (or the player's companion) stands between it and its target treats the shot as "not in range" and falls back to approaching instead of firing through the blocker. The **player's** own ranged shot is handled the opposite way — see `PlayerRanged.ranged_attack()` below: it's never simply refused, it redirects to whichever body is actually in the way. A generic ranged-ability dispatch (cooldown/uses_max/recharge, damage+optional status) now exists — see "Enemy D&D stat-block schema" above's `"abilities"` row — for a caster-style enemy that picks between melee approach and a ranged ability; a true multi-spell caster archetype (choosing between several abilities by trigger condition) still doesn't exist beyond that single-generic-shape dispatch. Reference pool entry for plain ranged attack_profile: `"Goblin Archer"` (`enemy_id: "goblin_archer"`, `DungeonFloorData.ENEMY_POOL`).

### Shared attack resolver
`Enemy._resolve_attack_roll(target_ac: int, attack_bonus_override: int = -1, roll_penalty: int = 0) -> Dictionary` is the one d20-vs-AC roll (Reckless Attack ADV/flat bonus, Grip of the Forest R3 disadvantage, crit-on-nat-20, Blade Ward's `roll_penalty`) shared by every enemy attack — melee or ranged, vs player or vs companion. `_attack_player()` and `_attack_companion()` both call it, then handle their own damage application/logging (player routes through `take_damage_raw` for rage DR/poison/Retaliation; companion calls `Companion.take_damage_from_enemy()`, which has no such hooks — those are player-only systems). `_attack_player()` is the only caller that ever passes a nonzero `roll_penalty` (Blade Ward, player-only buff) — subtracted from the roll AFTER ADV/DISADV resolves, before the AC comparison; never reduces a natural-20 crit.

### Enemy/boss pool ids
`DungeonFloorData.ENEMY_POOL` entries carry an `"enemy_id"` key, `BOSS_POOL` entries an `"boss_id"` key (e.g. `"orc_warrior"`, `"big_demon"`) — stable machine ids, unlike `display_name` which is UI text and shouldn't be load-bearing. `Enemy.enemy_id: String` is populated from either key in `configure()`. No behavior depends on these yet; they exist so future systems (boss-phase gating, per-enemy talent interactions) can key off a stable id instead of string-matching `display_name`.

---

## Player-specific (`player.gd`)
- `_trap_alert: bool` — set by `PlayerActions.passive_trap_check()` the instant it reveals a trap
  (see that function's own entry above). `_process()`'s hold-movement-repeat interrupt check
  (the same branch that already stops a held WASD key the moment `_fov_this_turn` gains a visible
  enemy) now also fires on `_trap_alert`, then clears it — so discovering a trap mid-hold stops
  the player exactly like spotting an enemy does, instead of silently walking onward. Also cleared
  whenever no movement key is held at all (`dir == Vector2i.ZERO`), so a stale alert from a
  single-tap move (too short-lived to ever reach the interrupt check) can't leak into and
  incorrectly interrupt a later, unrelated key press.
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
- `player_thief_tools.gd` (`PlayerThiefTools`) — disarm trap / lock / pick-lock door actions, plus `show_float_text()` (its only caller). `player.gd._try_move()`'s Thief-Tools-primed bump path and `PlayerActions.interact_action()` call into this. **The chat log shows only the pass/fail result** — the `N vs DC M` roll breakdown (and any `(Disadvantage)`/`(Zealous Presence)` tag) is appended only while `GameState.debug_show_all_checks` is on, same debug-gated visibility as the Stealth check.
- `player_vfx.gd` (`PlayerVfx`) — blood trail, hit-flash tween, sword-slash arc, surprise-mark "!" floater, screen shake, the ADV surprise-attack check (`has_advantage()`). `GameState.screen_shake` connects directly to `_vfx.screen_shake`.
- `player_actions.gd` (`PlayerActions`) — short rest / talent picker openers, wait, search/inspect, passive trap perception, floor-item pickup, door/trap interact dispatch. Owns `_last_search_request` (was a player.gd field) and `_inspect_panel` (the live `InspectPanel` instance — see below). **Passive trap perception** (`passive_trap_check()`, called every real player turn from BOTH `_try_move()` (WASD) and `_execute_queued_path()`'s two per-step move bodies (click-to-move and enemy-chase)): rolls `d20 + WIS mod` vs a flat `DC 15` (no longer floor-scaled) against every unrevealed trap within Chebyshev 2 of the player **that is also currently in FOV** (`DungeonFloor.is_tile_visible(trap_pos)`, checked after that step's own `update_fog()` call so it reflects the player's just-updated position — a trap within range but behind a wall/closed door, or otherwise out of line of sight, is silently skipped, never rolled against) — **re-rolled every single turn** the player stays in range (no "already checked this trap" memory), not just on first entering range. Revealing a trap sets `Player._trap_alert = true` and, when a queued path/enemy-chase was active, clears it itself with its own "stop cautiously" log line (the function's own `player._queued_path.size() > 0` branch) — `_execute_queued_path()`'s own step body additionally checks `_trap_alert` right after the call and clears/breaks out of the move loop so a long automated run genuinely halts on the discovery, not just the very next queued step. `_process()`'s hold-movement-repeat interrupt check (see "Player-specific" below) also consumes the flag the next frame — a freshly-discovered trap stops a held WASD key exactly like a freshly-visible enemy does, instead of the player walking straight past it. `do_inspect(pos)` opens a full-value `InspectPanel` (`scripts/ui/CLAUDE.md`'s "Inspect Panel") instead of the old plain chat-log line — an enemy target's status-icon row is built by `EnemyInspect.status_entries()`/`build_bbcode()` (`enemy_inspect.gd`, same directory), a static helper mirroring `status_tooltips.gd`'s pattern generalized to read an `Enemy`'s own fields directly. **`interact_tenebrous()`** (Tenebrous prop, `scripts/world/CLAUDE.md`'s "Tenebrous prop"): a turn-costing, panel-free interaction — grants one random Major Arcana card via `DungeonFloor.build_item_from_pool()` the first time ever, then permanently flips `GameState.tenebrous_card_given`; dispatched from `player.gd._try_move()`'s bump-to-interact branch and `interact_action()`'s Priority 1.65.
- `combat_math.gd` (`CombatMath`, static-func-only helper, `extends RefCounted`, mirrors `scripts/ui/tooltip_formatters.gd`'s pattern) — the ADV/DISADV d20-roll resolution shared verbatim by melee/cleave/ranged (`roll_with_adv_disadv()`), weapon proficiency bonus (`weapon_prof_bonus()` — was `player.gd._weapon_prof_bonus()`, see "Weapon proficiency flags" above), `melee_reach_bonus()` (Branching Strike's talent-rank reach) and `melee_reach(weapon, rank)` (total melee range = `1 + melee_reach_bonus(rank) + 1 if weapon.is_reach`, additive — used by the chase-to-attack range check and Cleave's target-gathering radius), `finesse_modifier(str_mod, dex_mod, is_finesse) -> int` (returns `max(str_mod, dex_mod)` when `is_finesse`, else `str_mod` — used for both the attack roll and damage roll in `player.gd._bump_attack()` when `GameState.equipped_weapon.is_finesse`), and `encode_bonus_sources()`/`decode_bonus_sources()` (generic bonus-damage tooltip encoding — see "Bonus damage stacking" below). The bonus-damage STACKING sequence itself (Ironwood Bark/Judgement Day summation) and the full hit/miss/log flow stay in `player.gd._bump_attack()`/`PlayerRanged.ranged_attack()` — see "Bonus damage stacking" above.
- `player_ranged.gd` (`PlayerRanged`) — the full ranged-combat body: range/LOS checks (`is_ranged_target_in_range()`, `ranged_shot_disadvantage()`, `is_in_ranged_range()`), the ranged attack roll (`ranged_attack()`), projectile VFX (`show_projectile()`), and ranged-at-tile (`ranged_attack_tile()`). Mirrors `_bump_attack()`'s ADV/DISADV/crit/Divine-Fury-stacking structure closely — kept as one function per the same "don't split stateful stacking logic" reasoning as melee (see "Bonus damage stacking" above). **`ranged_attack(enemy)` redirects to a blocking body**: before anything else, it calls `DungeonFloor.get_blocking_body_on_line(player.grid_pos, enemy.nearest_occupied_tile(...))` — if another `Enemy` occupies an intermediate tile of the shot, the local `enemy` parameter is reassigned to that blocker and the entire rest of the function (on_disturbed, roll, damage, log, Hunter's Mark, kill handling) resolves against it instead of whoever was actually clicked. Matches the "the arrow hits the first thing in its path" rule — see `scripts/world/CLAUDE.md`'s `has_clear_shot()`/`get_blocking_body_on_line()`.
- `player_monk.gd` (`PlayerMonk`) — Martial Arts (Dextrous Attacks/Martial Arts Die/Bonus Unarmed Strike), Unarmored Movement, and Monk's Focus (Flurry of Blows/Patient Defense/Step of the Wind). See "Monk class" below.
- `player_fighter.gd` (`PlayerFighter`) — Second Wind. See "Fighter class" below.

---

## Barbarian class
`Stats.proficiency_bonus` is a computed property scaling per D&D 5e (+2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.). `Stats.rage_uses_max` is a computed property scaling by Barbarian level: 2/3/4/5 at levels 1/4/6/12 (cap 5 at 17+). `Stats.rage_bonus_damage` is a computed property: +2 at levels 1–8, +3 at 9–15, +4 at 16+. Level-up grants the extra use immediately when crossing a threshold. **Barbarian unarmored defense**: `Stats.recalc_ac(has_armor_equipped)` — if BARBARIAN and no armor, AC = 10 + DEX + CON.

Tier 1 (levels 1–6): earns 5 talent points, spent across 3 talents — Psycho, Bruiser, Battlefield Expert (max 3 ranks each = 9 total possible cost → a run can max at most two, or spread points across all three). Points are granted on the level-up transitions into 2/3/4/5/6 (`GameState.TIER_LEVEL_RANGES[1] = [1, 6]`) — level 1 itself grants nothing (no level-up fires), so the 5th and last Tier 1 point lands at level 6, not level 5. These base talents (added per `markdowns/barbarian_base.md`) are shared by every subclass and grant no ability-bar entry — they're pure passive/reactive hooks read directly via `GameState.get_talent_rank()` at point of use. (Reckless Attack and Danger Sense were removed — vestigial, unused talents; nothing reads their old talent ids anymore.) Starting equipment given in `GameState.give_class_starting_items()` → `_give_barbarian_starting_items()`:
- **Spear** (main hand) — 1d6/1d8 versatile, Piercing, `weapon_mastery="Sap"`, `weapon_category="Simple"`, thrown (5 uses) — plus **2 Handaxes** (`weapon_mastery="Vex"`, Slashing, light, thrown, 5 uses each) given straight into the bag for RMB-throw. Tier-1 starter (`weapon-tiers-design.md` §6, option (a)) — the Greataxe (1d12 Slashing, `weapon_mastery="Cleave"`, the only Cleave-mastery weapon in the game) moved to a real `ITEM_POOL` Tier-4 floor-loot entry (`fmin=6`) instead of guaranteed starting gear, so a fresh Barbarian no longer starts with what should be an end-game find — accepted tradeoff: no guaranteed way to actually trigger a picked Cleave mastery rank until one drops. Barbarian has both `proficient_simple_weapons` and `proficient_martial_weapons` set, so the Martial tag never shows red for this class.
- **Rage** (ability_id `"rage"`) — in slot 0. Uses and bonus damage scale by level (see computed properties above). **Baked-in baseline (no longer talent-gated, per `markdowns/barbarian_base.md`)**: lasts 1 turn, refreshed to 1 turn whenever the player attacks (hit or miss) or is attacked (hit or miss) — `player.gd._on_turn_started()`'s rage-tick block reads `_rage_attacked_this_turn` (set in `_bump_attack()` and `PlayerBerserker.execute_frenzy()`) or `GameState.player_attacked_this_turn` (set in `enemy.gd._attack_player()` on any attack roll, hit or miss — distinct from `GameState.player_was_hit_this_turn`, which specifically means damage landed and is what Battlefield Expert R3 reads). The whole rage-tick block is gated on `not came_from_revert` — it only runs on a REAL turn (after enemies actually act), never on a reverted/free-action turn (Frenzy, Battlefield Expert's free side-step), so using a free action doesn't silently burn down Rage's duration. Always grants 50% physical damage reduction (Slashing/Piercing/Bludgeoning) while active — `GameState.take_damage_raw(amount, ignore_rage, damage_type)` applies it unconditionally. Activation is a **free action**. Red sprite tint. Rage ends if heavy armor equipped (`item.is_heavy_armor`). Masochist Monster R3 (Berserker) can override the per-turn decrement — see below.

**Barbarian Tier 1 talents** (levels 1–5, no fixed level-up unlocks — all are point-gated):
- **Psycho** (`talent_id: "psycho"`, max 3): Composition module `player_base_talents.gd` (`PlayerBaseTalents`, `_base_talents`). R1: after a kill (`_finish_kill()`, hooked once — covers every kill call site including subclass finishers like Frenzy/Limit Break — via `_base_talents.on_kill()`), the next attack (any type) is made with Advantage — `GameState.psycho_adv_pending: bool` (lives on `GameState`, not on `PlayerBaseTalents`, so the HUD status tray can read it — see `scripts/ui/CLAUDE.md`), persists across turns until consumed, added into `adv_count` at all 6 player attack-roll sites (`_bump_attack`, `_resolve_cleave_attack`, `_resolve_offhand_attack`, `resolve_opportunity_attack`, `PlayerRanged.ranged_attack`, `PlayerThrowTool`'s throw resolution) via `_base_talents.consume_psycho_or_battlefield_adv()` (shared with Battlefield Expert R1's identical pending-ADV pattern — each independently contributes, see the function). R2: a critical hit *also* triggers the same pending-Advantage window — `_base_talents.on_crit()`, hooked at the same 6 attack-roll sites whenever `is_crit` is true (R1's kill trigger stays active at R2; the two are additive, not replaced). R3: crit range widens to 19-20 while attacking with Advantage — `CombatMath.is_critical_hit(die, adv) -> bool`, replaces the `die == 20` check at all 6 sites uniformly. (Psycho R2 no longer adds a flat STR-modifier damage bonus — that behavior was removed and replaced by the crit trigger above.)
- **Bruiser** (`talent_id: "bruiser"`, max 3): Uses the shared `Stats.is_bloodied()` mechanic (below 50% max HP). R1: `GameState.heal(amount) -> int` — the single chokepoint for short-rest healing, potions, and Zealot Strike — adds `+1d4` to the amount whenever the player is Bloodied at heal time (does not apply to Temp HP grants, which don't call `heal()`) and **returns the rolled bonus** so every call site can name it as its own `"Bruiser"` source in the heal chat tooltip (`heal:` meta's `bonus=` field, `CombatMath.encode_bonus_sources()` — same generic mechanism `dmg:` tooltips use) instead of it silently vanishing into the total. R2: `+1 AC` while Bloodied, folded into `recalculate_stats()` alongside `terrain_ac_bonus`/`masochist_ac_bonus`; both `take_damage_raw()` and `heal()` call `recalculate_stats()` on every HP change **only if** rank ≥ 2 (avoids the extra work for characters who haven't invested). R3: once per floor (`GameState.bruiser_revive_used_this_floor`, reset in `advance_floor()`), if a hit while Raging would drop the player to 0 HP, `check_player_death()` intercepts before setting `is_game_over`: sets `current_hp = 1`, emits `GameState.force_rage_end` (a signal `player.gd._ready()` connects directly to `_end_rage()`, since Rage state lives on `Player` not `GameState`), and returns instead of ending the run.
- **Battlefield Expert** (`talent_id: "battlefield_expert"`, max 3): Same composition module as Psycho. **Side-step** = a player move that stays within a given enemy's melee reach on both the previous and next tile AND is a genuine diagonal pivot around the enemy (`d_prev <= reach and d_next <= reach and prev != next and absi(next.x - prev.x) == 1 and absi(next.y - prev.y) == 1`) — a pure lateral slide that stays adjacent along one side of the enemy (e.g. NW→N) does NOT count, only a true corner-to-corner move around it does. This condition sits right alongside the existing no-Opportunity-Attack branch in `_resolve_enemy_opportunity_attacks(prev, next)` (see "Opportunity Attacks" below — the OA-suppression branch itself is unchanged, only the Battlefield Expert trigger got the extra diagonal check): `_base_talents.on_sidestep(e)`. Triggering it (rank ≥ 1) logs a chat message and grants the **Tactician** buff. R1: next attack (any type) gets Advantage — `GameState.battlefield_adv_pending` (lives on `GameState`, same reasoning as `psycho_adv_pending` above), same drain mechanism as Psycho's pending-ADV (`consume_psycho_or_battlefield_adv()`); shown in the HUD status tray as `tactician` while pending (`scripts/ui/CLAUDE.md`). **Unlike Psycho's pending-ADV, Tactician expires if unused**: `GameState.battlefield_adv_expire_turns` (set to 2 in `on_sidestep()`) ticks down by 1 only on a REAL player turn-start (`PlayerBaseTalents.tick_battlefield_adv_expiry()`, called from `_on_turn_started()`'s `if not came_from_revert:` block, alongside `tick_free_sidestep()`) and clears `battlefield_adv_pending` when it hits 0; `consume_battlefield_adv()` resets the counter to 0 on use. Net effect: the buff survives through the end of the turn immediately following the side-step, then disappears if the player never attacked with it — and since R3's free side-step doesn't end the current turn at all (see below), it's also still usable in that very same turn before the countdown starts ticking. R2: the side-stepped enemy's `Enemy.disadv_next_attack = true` (existing field, also used by Grip of the Forest R3). R3: `GameState.player_was_hit_this_turn` (the same flag Rage's duration check reads) is read — but not cleared — in `_on_turn_started()`'s per-round-reset block via `_base_talents.tick_free_sidestep()`, then cleared once, unconditionally, after the rage-tick block (so Rage's own read isn't disturbed by this addition and non-Raging Barbarians don't leak the flag forever). If set, the player's first side-step this turn is free: `_try_move()` captures `_base_talents.consume_free_sidestep()` right after the OA-resolution call (which is where `sidestep_detected_this_move` gets set) and, if true, calls `TurnManager.revert_to_waiting()` instead of `on_player_action_complete()` at the end of the move — same free-action pattern the removed Rager talent used. **Scope limitation**: only wired into `_try_move()` (single-step WASD movement); the queued-path/chase-to-target movement functions don't check for free side-steps. **Works in God Mode**: `GameState.take_damage_raw()`'s `invincible` branch still sets `player_was_hit_this_turn` on a physical hit (before returning 0) — the flag reflects "an attack connected", not "HP actually changed", so this R3 charge (and anything else keyed off the flag) isn't silently dead while invincible.

**Barbarian Tier 2 subclasses** (points at levels 7–12; unlocked by defeating the floor-5 boss). Full source specs (superseding the earlier `barbarian-tier1-rework-v2-prompt.md` design): `markdowns/barbarian_base.md`, `markdowns/berserker.md`, `markdowns/scarred_warrior.md`, `markdowns/wild_heart.md`, `markdowns/zealot.md`.
- Level-point schedule (`GameState.TIER_LEVEL_RANGES`): levels 1–6 grant Tier 1 points (5 points total, at the level-up transitions into 2/3/4/5/6). Levels 7–12 grant Tier 2 points into `GameState.talent_points[2]` — they sit pending until the gating boss (`GameState.TIER2_GATING_BOSS_ID`, the floor-5 Bearded Devil) is killed. Levels 13+ grant nothing until Tier 3.
- `GameState.tier2_unlocked: bool` — set by `unlock_tier2()` (boss-gated via `boss_defeated` — see `scripts/autoloads/CLAUDE.md`). `_setup_barbarian_tier2_talents()` appends 3 `Talent` objects to `_class_talents`.
- `GameState.TIER2_SUBCLASSES: PackedStringArray` = `["Berserker", "Scarred Warrior", "Wild Heart", "Zealot", "World Tree"]`. `active_tier2_subclass: String` tracks current. `debug_switch_subclass(direction)` cycles subclasses and calls `_setup_tier2_for_active_subclass()` — routes to Berserker, Scarred Warrior, Wild Heart, World Tree, or Zealot setup (all five are implemented). Arrows ◀ / ▶ appear in the talent picker Tier 2 header when God Mode is active.
- **Free base activation ability pattern**: Berserker (Frenzy), Scarred Warrior (Limit Break), Wild Heart (Animal Form), and Zealot (Zealot Strike) each grant one activation ability directly at subclass selection, via `GameState._grant_tier2_base_ability(id, name, description)` — **not** gated by any talent rank/investment. Their three Tier 2 talents only upgrade/enhance that base ability (never grant their own ability-bar entry) — see each subclass's `_apply_talent_rank()` case, which just refreshes the base ability's description. `GameState.TIER2_BASE_ABILITY_ID: Dictionary` maps subclass name → that ability's id; `debug_switch_subclass()` strips the previous subclass's base ability using this map (in addition to its 3 talent-bar entries) before granting the new subclass's. World Tree has no such base ability — all three of its Tier 2 talents remain individually rank-1-gated (unchanged, pre-existing pattern).
- `GameState.apply_player_status(type, turns) -> bool` — single chokepoint for all player status/debuff application. All trap, enemy, terrain, and rotten-meat status calls use this function.

**Wild Heart Tier 2 talents** (**experimental** — balance changes expected):
- State vars on GameState: `natural_rager_form: String = "Bear"` (the TARGET Animal Form just selected), `active_rager_form: String = "Bear"` (the form actually granting effects right now), `ANIMAL_FORM_SWITCH_TURNS: int = 1` (const), `rager_form_switch_turns_remaining: int` (counts down to 0, at which point `active_rager_form` snaps to `natural_rager_form`), `natural_sleeper_form: String = "Owl"` (last-rolled form, unrelated talent, see below), `active_sleeper_form: String = "Owl"` (both randomly re-rolled together on every long rest — not locked in at floor descent), `wild_heart_sleeper_active: bool`, `player_evades_opportunity_attacks: bool`, `fov_radius_bonus: int`, `player_companion: Variant`, `terrain_ac_bonus: int`. (Internal var names keep their pre-rework identifiers — only ability/talent ids and display names changed.)
- **Animal Form** (ability_id `"animal_form"`, free base ability — no talent rank required): Toggle ability cycles Bear/Eagle/Wolf (`player_wild_heart.gd.cycle_animal_form()`) **freely, any time — NOT rest-gated** (that's the unrelated Natural Sleeper talent below — Animal Form and Natural Sleeper look similar but work on entirely different timers, don't conflate them). There's no way to pick a form directly — each press steps to the next form in the Bear→Eagle→Wolf→Bear cycle (`GameState.start_animal_form_switch(form)`, `form` always the adjacent one), which retargets `natural_rager_form` and (re)starts an `ANIMAL_FORM_SWITCH_TURNS` (1) real-turn countdown (`rager_form_switch_turns_remaining`) — so reaching the form 2 steps away (e.g. Bear→Wolf) costs 2 presses/turns, one per intermediate step, not a single flat wait. Re-pressing mid-transition just retargets and restarts the count. `GameState._tick_animal_form_transition()`, called once per REAL player turn (never on an Eagle-style reverted/free-action turn) from `player.gd._on_turn_started()`, decrements the counter; hitting 0 snaps `active_rager_form = natural_rager_form` and applies its effects. The currently active form keeps working throughout the wait — there's no "form-less" gap. `_apply_active_rager_form_effects()` is the single place that pushes `active_rager_form` into the always-on Eagle knobs (`player_evades_opportunity_attacks`, `fov_radius_bonus`) — called when a transition completes, at subclass grant (`_setup_wild_heart_tier2_talents()`, which activates the starting form immediately with no wait), and by `from_dict()` restore. Bear: **while Raging only** (Bear is the one form whose effect is Rage-gated — Eagle/Wolf stay always-on once active), 25% resistance to elemental damage (Fire/Cold/Lightning/Thunder/Acid/Poison), checked live against `active_rager_form` + `is_raging` in `take_damage_raw()`. Eagle: enemies never gain Opportunity Attacks against you. Wolf: ADV on STR attacks when 4+ enemies are visible (`_bump_attack()`, checks `active_rager_form`). `player.gd`'s turn-tick calls `_dungeon_floor.update_fog(grid_pos)` once a transition completes, since Eagle's FOV bonus may have just changed.
- **Enhanced Forms** (`talent_id: "enhanced_forms"`, max 3): Upgrades the base 3 forms — refreshes Animal Form's description only, no separate ability. Bear: R1 also resists magical damage (Radiant/Necrotic/Force); R2 33% total; R3 50% total. Eagle: R1 +1 FOV radius (`GameState.fov_radius_bonus`, threaded into `DungeonFloor._compute_shadowcast()`/`get_visible_enemies()`); R2 ranged attacks against you get -2 to hit *(not yet wired into enemy ranged-attack resolution — flagged as a gap, see below)*; R3 ranged enemies get Disadvantage *(same gap)*. Wolf: threshold drops 4→3→2 enemies; R3 also grants ADV at 1 enemy + 1 friendly (companion) in FOV.
- **Expanded Forms** (`talent_id: "expanded_forms"`, max 3): Passive ability slot, no activation — pressing it just logs a flavor line (`player.gd`'s `_use_ability_slot()`). Form is **randomly rolled every long rest** (`GameState.long_rest()`: `natural_sleeper_form = Rng.pick(["Owl","Panther","Salmon"]); active_sleeper_form = natural_sleeper_form` — matches the source spec's original "random form per long rest" design; the earlier player-chosen-cycling version, `PlayerWildHeart.cycle_natural_sleeper_form()`, was removed per direct owner request to simplify/ease the game). Not player-choosable, not on short rest, not on floor descent. Terrain effects check `active_sleeper_form` in `_try_move()` and `_on_turn_started()`. Owl: chasm passthrough. Panther: mud not difficult. Salmon: water not difficult. R2: roll 2d6 THP at the **start of each real turn** while standing in form's terrain — THP replaces (not stacks) existing THP. R3: +2 AC (`GameState.terrain_ac_bonus` → `recalculate_stats()`; cleared between floors, updated on every move in `_try_move()`).
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
- **Grip of the Forest** (`talent_id: "grip_of_the_forest"`, max 3): Active ability added to bar at rank 1 — activating (`player.gd._activate_grip_of_the_forest()`) requires `GameState.is_raging` and not `GameState.grip_of_the_forest_used_this_turn` (reset in `_on_turn_started()`, also greys the ability-bar slot via `is_ability_usable()`), then arms `_hook_mode_active` (modeled on throw-mode priming, not a toggle). Next LMB click on an enemy within range (R1=3/R2=4/R3=5 tiles, Chebyshev, `has_ranged_los()`) resolves `_execute_hook()`, which costs the turn like a normal action. Enemy rolls `Enemy.resist_check(dc)` (STR-based) vs `dc = 8 + player STR mod + proficiency` (see "Enemy resist checks" above). On success, pulls the enemy toward the player one tile at a time via `DungeonFloor.force_move_entity()`, stopping once adjacent. R2: sets `enemy.rooted_turns = 1`. R3: sets `enemy.disadv_next_attack = true`.
- **Branching Strike** (`talent_id: "branching_strike"`, max 3): Passive ability added to bar at rank 1. R1/R2: reach bonus for `Item.is_heavy or Item.is_versatile` melee weapons (`player.gd._melee_reach_bonus()` — R1 = +1 tile, R2 = +2 tiles, **replaces** R1, not additive). Applied at the chase-resolution chokepoint in `_execute_queued_path()` (`chase_path.size() <= 1 + _melee_reach_bonus()` instead of the old `== 1`). R3: on a successful hit with a heavy/versatile weapon, pushes the target 1 tile directly away from the player via `force_move_entity()` — target rolls `Enemy.resist_check(dc, true)` (CON-based) vs the same DC convention as Grip of the Forest.
- **Shared forced-movement hook**: `DungeonFloor.force_move_entity()` — see `scripts/world/CLAUDE.md`.

**Zealot Tier 2 talents** (max 3 ranks each). Composition module: `scripts/entities/player_zealot.gd` (`PlayerZealot`, `_zealot`) — reused from the pre-rework file, gutted and rewritten.
- **Zealot Strike** (ability_id `"zealot_strike"`, free base ability — no talent rank required): Toggle (free action, doesn't cost the turn itself). Arms `_zealot.zealot_strike_armed`; the player's **next melee attack this turn** (hit or miss — checked in `_bump_attack()` right before the miss branch, mirroring the old Blessed Warrior call site; **ranged attacks never trigger it**, per spec) resolves `_zealot.resolve_zealot_strike_heal()`: consumes 1 Hit Die (`GameState.hit_dice -= 1`), heals `1d[hit_die_sides] + CON mod`. If the turn ends without a melee attack, `zealot_strike_armed` is cleared in `_on_turn_started()` with **no** Hit Die consumed (matches spec exactly).
- **Judgement Day** (`talent_id: "judgement_day"`, max 3): After a Zealot Strike heal resolves, sets `_zealot.judgement_day_pending = true`; consumed by the **next** attack (not the same attack that triggered the heal, mirroring Ironwood Bark R3's pending-bonus pattern) for `N × rage_bonus_damage × 1d6` bonus damage. Damage type comes from `_zealot.judgement_day_damage_type()`, currently a stub always returning `"Radiant"` — the source spec's full Morale (NPC-reputation) system that would flip it to `"Necrotic"` on low Morale is **not implemented** (out of scope for this pass; flagged as a follow-up).
- **Overheal Shield** (`talent_id: "overheal_shield"`, max 3): When a Zealot Strike heal resolves, grants Temporary HP (replace, not stack) based on rank: R1 = overheal amount only (`max(0, (pre-heal HP + heal roll) - max HP)`); R2 = the entire heal roll; R3 = heal roll + overheal. Scoped to Zealot Strike's own heal only (the source spec left "applies to all healing?" as an open question — this pass keeps it Zealot-Strike-only, the narrower/safer reading).
- **Never Back Down** (`talent_id: "never_back_down"`, max 3): +1/+2/+4 max Hit Dice by rank (**non-cumulative** — higher rank replaces, doesn't stack with, the previous rank's bonus; matches every other Barbarian talent's rank-replaces convention). `GameState.max_hit_dice() -> int` returns `character_level + bonus_by_rank`, used by `long_rest()`'s `hit_dice` refill and `short_rest_panel.gd`'s displayed cap instead of the raw level.

## Ranger class

Level-1 baseline: **Hunter's Mark** (ability_id `"hunters_mark"`, granted directly at character
creation like Rage, not talent-gated) — arm-then-click targeting (same UX as Grip of the Forest's
hook mode), marks one enemy within `Stats.HUNTERS_MARK_RANGE` (5 tiles, checked in
`PlayerRangerTalents.commit_mark()`). **Casting time is free** — `commit_mark()` never calls
`TurnManager.begin_player_action()`/`on_player_action_complete()`, so marking (or re-marking)
doesn't cost a turn. **Duration**: Concentration, up to `Stats.HUNTERS_MARK_DURATION` (600 turns —
5e RAW's "1 hour", at 6 seconds/round —
`Stats.hunters_mark_turns`, ticked once per real turn in `player.gd._on_turn_started()` alongside
Blade Ward/Expeditious Retreat/Fog Cloud) — uses the generic `Stats.concentration_spell_id`
mechanism (`"hunters_mark"`), so a CON-check failure on taking damage
(`GameState._check_concentration_break()`) or casting a different Concentration spell ends it
early via `GameState.end_concentration()`. Every hit against the marked target — **any weapon,
including Off-hand and Nick bonus attacks, unconditionally** — deals a second, independent +1d6
Force damage instance (`PlayerRangerTalents.hunters_mark_bonus_die()`; this used to require Twin
Fang R1, see that talent's entry below for the now-dead rank). `Stats.hunters_mark_target`/
`hunters_mark_fresh` (not serialized, same precedent as `witch_bolt_target`) +
`Stats.hunters_mark_uses_remaining`/`HUNTERS_MARK_USES_MAX` (3, serialized, refilled in
`long_rest()`) — a use is spent every time the mark moves onto a DIFFERENT enemy than the one
currently marked (re-clicking the SAME already-marked target is the only free case, just refreshing
the duration); moving the mark to a different LIVING enemy is not otherwise free — direct owner
correction, this used to treat any retarget as free ("5e move Hunter's Mark for free"), which isn't
actually RAW (5e's own free retarget is death-triggered only — see "Free re-mark on kill" below, the
one real free case). **Once free uses run out**, marking a new target automatically spends a real
1st-level Ranger spell slot instead (Hunter's Mark is a real 1st-level spell in 5e —
`commit_mark()` checks `Stats.caster.slot_pool.remaining.get(1, 0)` directly and calls
`slot_pool.consume(1)`, same as any other leveled-spell cast); with neither a free use nor a slot
available, marking is blocked with a chat-log message. **One cast per round**: `Stats.
hunters_mark_cast_this_round` — set the instant `commit_mark()` actually resolves a mark (any
resource: free use, spell slot, or the free-recast window below), refuses a second cast with a gray
log line while set, cleared every real round in `player.gd._on_turn_started()`'s
`if not came_from_revert:` block — matches 5e's own "Hunter's Mark is a bonus action, only one per
turn" rule (direct owner correction; nothing previously stopped spamming re-marks within the same
round, since casting itself never costs a turn). **The Marked target dying ALWAYS ends Hunter's
Mark's concentration immediately** (`stats.hunters_mark_turns = 0`, `concentration_spell_id = ""`
— it used to just null the target and otherwise decay naturally over the rest of
`hunters_mark_turns`, direct owner correction). **Free re-mark on kill**: in exchange, if the Marked
target dies while Concentration is still active, `PlayerRangerTalents.try_bloodhound_remark()`
(called unconditionally from `Enemy.die()`, not just for Bloodhound) arms
`Stats.hunters_mark_free_recast_pending` — the following `_on_turn_started()` promotes it to
`hunters_mark_free_recast_available` for exactly that one real turn (consumed for free by
`commit_mark()` if used, otherwise cleared as expired at the NEXT `_on_turn_started()`) — "next
turn only, never later" per direct owner spec. Bloodhound R3 (see below) supersedes this baseline
entirely: it re-marks the nearest visible enemy instantly instead of arming the window — its own
re-mark now also restarts `hunters_mark_turns`/`concentration_spell_id` to a genuine fresh cast
(bugfix: it used to leave both cleared/at-zero from the death above, so the "instant re-mark" was
mechanically already-expired concentration). **UI staleness bugfix**: `commit_mark()` and
`try_bloodhound_remark()` now explicitly emit `GameState.ability_bar_changed` after mutating
`hunters_mark_uses_remaining`/the free-recast flags — neither used to emit anything on the
free-use-spent path, so the ability-bar use-count badge only visibly updated whenever some
unrelated action happened to trigger a HUD refresh, which read as "uses only decrement at the end
of the round" and let the spell-slots row (which DOES emit its own `spell_slots_changed` on the
slot-fallback path) appear to update before the uses badge did. **Not yet
implemented**: the 5e "Advantage on a Wisdom (Perception/Survival) check to find the Marked
target" clause — this codebase has no player-side "find a creature" WIS-check mechanic to hook it
into (`player_actions.gd`'s `search_action()` is for traps/secret doors and already always rolls
with Advantage for everyone; the closest analog, `_resolve_stealth_check()`, is the opposite
direction — enemy Stealth vs. player Passive Perception). **Targeting preview** (bugfix — this used
to have none at all, same gap Breath Weapon/Cloud Giant's Jaunt had before their own previews were
added): `player.gd._update_hunters_mark_preview()`, dispatched from `_update_spell_aoe_preview()`'s
own fallback chain while `_hunters_mark_mode_active` — a blue max-range backdrop
(`Stats.HUNTERS_MARK_RANGE`) plus a red highlight on the hovered tile whenever it holds a
targetable enemy in range, reusing `DungeonFloor.show_spell_range_preview()`/
`show_single_target_preview()` verbatim, same shape every other single-target spell/ability gets.
Shown as a `X/3` use-count badge on the
ability bar slot (`hud.gd`'s `_refresh_ability_bar()`, same special-cased-`Ability` convention as
Rage — `Stats.hunters_mark_uses_remaining` is read directly since the `Ability` resource's own
`uses_remaining`/`uses_max` stay 0/0). Direction to the marked target shows on-screen even outside
FOV/LOS via `scripts/ui/hunters_mark_indicator.gd` (mirrors `compass.gd`'s pattern). **In-world
marker**: the marked `Enemy` itself also shows a small red "▼" above its sprite whenever it's
currently `Stats.hunters_mark_target` — `Enemy._mark_indicator` (`enemy.gd`, same
per-enemy-child-`Label` pattern as `_zzz_label`/`_notice_label`), toggled every frame in a new
`Enemy._process()` (the first `_process()` override on this class) rather than wired to a signal,
since the mark can move to a different enemy or clear at several call sites
(`player_ranger_talents.gd`) without a single common chokepoint to hook. Bobs up/down continuously
while shown (`_start_mark_bob()`/`_stop_mark_bob()`, a looping sine-eased `position:y` tween —
same `create_tween().set_loops()` convention as `_zzz_tween`) so it reads as a floating marker, not
a static icon. Composition module:
`scripts/entities/player_ranger_talents.gd` (`PlayerRangerTalents`, `_ranger_talents`). Full spec:
`markdowns/ranger_base.md`.

**Starting gear** (`GameState._give_ranger_starting_items()`): two Daggers (Main Hand + Off-hand
— immediate dual-wield melee is a fully "correct" build, not a fallback) plus a Short Bow + 20
Arrows in the ranged slot. `Stats.apply_class_defaults()`'s RANGER branch also sets
`proficient_simple_weapons`/`proficient_martial_weapons` true (previously unset — every Ranger
weapon would've shown "not proficient").

**Ranger spellcasting (half-caster)**: Ranger is `Stats.CLASS_ROLE["RANGER"] == "HALF_CASTER"` (see
that dict's own header comment in `scripts/entities/stats.gd` — a purely internal, never-shown-in-
UI categorization of the full 5e class roster: MARTIAL = Barbarian/Fighter/Monk/Rogue, FULL_CASTER
= Bard/Cleric/Druid/Sorcerer/Warlock/Wizard, HALF_CASTER = Ranger/Paladin, THIRD_CASTER = a
subclass-only role — Eldritch Knight, Arcane Trickster — not a base-class row at all. Only the
implemented classes actually do anything with this; it exists so a future class's role is decided
consistently). `Stats.apply_class_defaults()`'s RANGER branch grants `Stats.caster =
SpellcasterState.new()` (WIS-based, matching real 5e) with a `HalfCasterSlotPool`
(`scripts/items/half_caster_slot_pool.gd`) instead of Wizard's `StandardSlotPool` — same interface
(`max_slots()`/`available_level()`/`can_cast()`/`consume()`/`on_long_rest()`/
`grant_new_slots_on_levelup()`), its own 2024-rules half-caster table (slots from character level 1,
not level 2 like the 2014 rules — max spell level 5, reached at level 17). No cantrips
(`SpellcasterState.cantrip_max()` stays 0 for every non-Wizard class — matches 2024 Ranger, which
genuinely has none). **Prepared count**: `SpellcasterState.prepared_max()` branches on
`character_class` — Ranger uses the real half-caster formula `max(1, WIS mod + character_level /
2)` instead of Wizard's flat `character_level`.

**Spell list**: Ranger draws from the same shared `SpellDb` pool as Wizard, but ONLY the subset
actually on Ranger's real 5e/5.5e (2024) spell list — `SpellDb.RANGER_SPELL_IDS` deliberately does
NOT just open every `LEVELED_SPELL_IDS` entry up to Ranger; each spell's own `class_list` was
checked against its actual RAW class list (direct owner correction after an earlier pass got this
wrong). Of the `LEVELED_SPELL_IDS` entries, **Fog Cloud** (Druid/Ranger/Sorcerer/Wizard) is the
only one also genuinely on Ranger's real list — every other `LEVELED_SPELL_IDS` entry (Magic
Missile, Shield, Mage Armor, Misty Step, Fireball, Chromatic Orb, Burning Hands, Witch Bolt,
Expeditious Retreat, False Life, Invisibility, Darkness, Longstrider, Detect Magic) is
Sorcerer/Wizard(/Warlock) only on both 2014 and 2024 rules. `RANGER_SPELL_IDS` is
`["fog_cloud", "pass_without_trace", "cure_wounds", "aid", "barkskin", "hail_of_thorns",
"ensnaring_strike"]` today:
**Pass Without Trace** (Druid/Ranger, `class_list = ["RANGER"]` only — never opened to Wizard's
own list, see "Elf"'s Wood Elf lineage grant), **Cure Wounds** (`SpellDb._cure_wounds()`,
Abjuration, 1st level, real class list Bard/Cleric/Druid/Paladin/Ranger — only Ranger has
spellcasting of any kind here, so `class_list = ["RANGER"]` only, never added to
`LEVELED_SPELL_IDS`/Wizard's own list), **Aid** (`SpellDb._aid()`, Abjuration, 2nd level, real
class list Bard/Cleric/Druid/Paladin/Ranger, same `class_list = ["RANGER"]`-only treatment),
**Barkskin** (`SpellDb._barkskin()`, Transmutation, 2nd level, real class list Druid/Ranger, same
`class_list = ["RANGER"]`-only treatment), **Hail of Thorns** (`SpellDb._hail_of_thorns()`,
Conjuration, 1st level, real class list Ranger-only, same `class_list = ["RANGER"]`-only
treatment), and **Ensnaring Strike** (`SpellDb._ensnaring_strike()`, Conjuration, 1st level, real
class list Ranger-only, same `class_list = ["RANGER"]`-only treatment) are all six Ranger-exclusive
spells, never offered to Wizard's own level-up picker.
Cure Wounds is
`resolution = AUTO_HIT`, `target_kind = SELF`, touch range (`range_tiles = 1`) — same "self, or the
Companion" touch-target click scope as Healing Hands/Longstrider (no general ally-targeting system
exists): clicking the Companion's own tile heals it, any other click heals the caster. Heals
2d8 + spellcasting ability modifier (WIS for Ranger), `upcast_dice_count = 2` (+2d8 per slot level
above 1st — Warlock Pact Magic auto-upcast only, a no-op for Ranger's own non-upcasting
`HalfCasterSlotPool`). `SpellEffects._resolve_cure_wounds()` resolves it via `GameState.heal()`
(Bruiser R1's own +1d4-while-Bloodied bonus applies for free) for a self-cast, or a direct
`Companion.stats.current_hp` bump for a Companion cast — same `heal:` tooltip format short rest/
Zealot Strike/Healing Hands already use.

**Aid**: `resolution = AUTO_HIT`, `target_kind = SELF`, `range_tiles = 2`, same touch-click scope
as Cure Wounds — but unlike Cure Wounds' either/or click, it always buffs the caster AND
additionally buffs the Companion too when the click lands on its tile (RAW genuinely targets
multiple creatures with one cast; this engine's "self, or the Companion" scope caps the real
"up to 3 creatures" text at 2 rather than 3, a documented simplification). Raises max HP AND
current HP by a flat 5 (`+5` per extra spell level above 2nd via `upcast_flat_amount`, applied to
each target independently — Warlock Pact Magic auto-upcast only, a no-op for Ranger's own
`HalfCasterSlotPool`) for every creature it actually reaches. **Not a turn-ticked duration** — RAW
"until you finish a long rest," so it's tracked via `Stats.aid_bonus_hp` (the exact amount granted,
serialized) rather than a countdown; `GameState.long_rest()` subtracts it back out of `max_hp`
(both the player's and, independently, the Companion's own `Stats.aid_bonus_hp`) before the normal
full-heal-to-max-HP line runs, same "persists until long rest" precedent as `mage_armor_active`.
`SpellEffects._resolve_aid()` is the resolver, dispatched from `cast_leveled_self()`'s
`effect_id == "aid"` case. **Status-tray icon**: `hud.gd._update_status_icons()` shows an `"aid"`
entry (spell's own icon, light-green fallback tint) whenever `s.aid_bonus_hp > 0` — same
"icon reuses the spell's own art" convention as `concentration`/`torch`/`longstrider` — since a
flat max-HP bump is otherwise invisible at a glance beyond the HP bar quietly getting wider.

**Barkskin**: `resolution = AUTO_HIT`, `target_kind = SELF`, `range_tiles = 1`, same "self, or the
Companion" touch-click scope as Cure Wounds/Aid — but only ONE of the two is ever affected per
cast (`Stats.barkskin_on_companion` tracks which), unlike Aid's simultaneous self+Companion.
**Deliberately NOT Concentration** — real 5e Barkskin is Concentration up to 1 hour, but this
codebase's own stat block (direct owner dictation) omits it, so it's a flat 600-turn duration
instead (`Stats.barkskin_turns`, ticked in `player.gd`'s per-real-turn block exactly like
`longstrider_turns` — same "flat duration, no concentration" shape, NOT the generic
`concentration_spell_id` mechanism every other 600-turn buff in this file uses). "AC can be no
less than 17" is a floor applied on top of whatever AC would otherwise be, not a replacement — for
the player, `Stats.recalc_ac()`'s own tail clamps the computed `armor_class` up to 17 whenever
`barkskin_turns > 0`, BEFORE `GameState.recalculate_stats()` adds equipment/terrain/Bruiser bonuses
on top (so a Shield's +2 still stacks above the 17 floor, matching RAW). The Companion has no live
AC-recompute system like the player's own `recalc_ac()`, so a Companion-targeted cast floors its
`Stats.armor_class` directly at cast time (`Stats.barkskin_pre_ac` snapshots the pre-floor value)
and `player.gd`'s turn-tick restores that exact snapshot when the duration runs out. **Status-tray
icon**: since this ISN'T Concentration, it doesn't ride the generic `concentration` tray entry the
way Blade Ward/Witch Bolt/etc. do — `hud.gd._update_status_icons()` shows its own `"barkskin"`
entry (spell's own icon, brown/bark fallback tint) whenever `s.barkskin_turns > 0 and not
s.barkskin_on_companion` (the icon only ever reflects the PLAYER's own buff state, matching the
AC floor's own scope). `SpellEffects._resolve_barkskin()` is the resolver, dispatched from
`cast_leveled_self()`'s `effect_id == "barkskin"` case.

**Hail of Thorns**: **a toggle-armed REACTION, not a normal on-demand cast** — RAW is "the first
time you hit a creature with a ranged weapon attack while the spell is active," and this engine
has no reaction-casting framework, so it's implemented as the exact offensive mirror of Hellish
Rebuke's own toggle-armed shape (see "Tiefling" above) rather than going through the normal
arm-then-click spell-targeting flow at all — `_build_spell_ability()`/`_spell_ability_id()`/
`_spell_id_from_ability_id()` all special-case `spell_id == "hail_of_thorns"` to build/route a
fixed `"hail_of_thorns_toggle"` ability id exactly like they already do for `"hellish_rebuke"`.
Toggling it (`PlayerRangerTalents.activate_hail_of_thorns()`/`can_activate_hail_of_thorns()`,
`scripts/entities/player_ranger_talents.gd` — same "can't arm with nothing to fuel it" gate
Hellish Rebuke's own activation has) flips `Stats.hail_of_thorns_armed`. **Triggered from
`PlayerRanged.ranged_attack()`'s own hit branch** (not an enemy-side hook like Hellish Rebuke) —
the instant a ranged shot lands, the caller clears the armed flag and calls
`SpellEffects.trigger_hail_of_thorns()`, same "disarm BEFORE the trigger resolves" convention as
enemy.gd's own Hellish Rebuke call site. **Thrown weapons don't trigger it** — a documented scope
limit, only wired into the one equipped-ranged-weapon attack site. On trigger: the shot's own
target (if it survived the weapon hit — a shot that already killed it outright leaves nothing for
the thorns to catch) plus every OTHER living enemy within Chebyshev 1 of its tile (5e RAW's "5
feet") each roll an independent DEX save (`magical = true`, so Imp/Quasit's Magic Resistance
grants Advantage against it like any other spell save) — a fail takes the full `1d10` Piercing
roll (`+1d10` per slot level above 1st via `upcast_dice_count` — Warlock Pact Magic auto-upcast
only, a no-op for Ranger's own non-upcasting `HalfCasterSlotPool`), a pass takes half. **No status-
tray icon** — same precedent as Hellish Rebuke, whose own armed-toggle state also isn't reflected
in the ability-bar's orange-highlight convention today (a pre-existing gap in both, not something
this spell newly introduces). **No Scroll of Hail of Thorns exists** — same deliberate holdout as
Hellish Rebuke, for the identical reason: a toggle-armed reaction can't go through the generic
`on_scroll_primed()`/`begin_cast()` cast-immediately flow every other scroll uses.
`SpellEffects.trigger_hail_of_thorns()` is the resolver.

**Ensnaring Strike**: same toggle-armed-REACTION shape as Hail of Thorns/Hellish Rebuke — arming
(`PlayerRangerTalents.activate_ensnaring_strike()`/`can_activate_ensnaring_strike()`) and the
`_build_spell_ability()`/`_spell_ability_id()`/`_spell_id_from_ability_id()` special-casing all
mirror those two exactly (fixed `"ensnaring_strike_toggle"` ability id). **The one real
difference: "hits with a weapon" is broader than Hail of Thorns' "ranged weapon"** — wired into
BOTH the primary melee hit branch (`player.gd._bump_attack()`) and the primary ranged hit branch
(`PlayerRanged.ranged_attack()`), not just one; Off-hand/Cleave/OA/thrown still don't trigger it,
same documented scope limit as every other "primary hit only" bonus effect in this file. Skipped
outright (armed flag left untouched, not consumed) on a killing blow — nothing left to restrain —
same "a kill 'for free' doesn't cost a charge" precedent as Goliath's Fire/Frost/Hill Giant
Ancestry.

Unlike Hail of Thorns/Hellish Rebuke's one-shot burst, a failed save here starts a genuine ongoing
**Concentration** effect (`Stats.concentration_spell_id == "ensnaring_strike"`, up to
`Spell.duration_turns` = 10 turns, ticked in `player.gd`'s per-real-turn block alongside Ray of
Enfeeblement/Hold Person — same "repeated save usually ends it early, this is just the outer
backstop" shape). `SpellEffects.trigger_ensnaring_strike()`: consumes a real spell slot (or free
while invincible/God Mode), rolls the target's STR save (`resist_check_detailed()`'s `magical`
param true, `force_adv` true whenever the target is Large or bigger — `creature_size in
["Large","Huge","Gargantuan"]` or a footprint > 1 tile, same "big creature" check Halfling
Nimbleness uses — a house-rule addition on top of real 5e's own Ensnaring Strike text, per the
owner's own stat block). A passed save fizzles the cast entirely (no Concentration started, no
target array populated) — same "on an initial-save success, nothing lingers" precedent as Ray of
Enfeeblement's own minor-effect-only branch. A failed save sets `Enemy.restrained_turns`/
`restrain_save_dc` — the first real implementation of the enemy-side Restrained condition (see
"Conditions" above's table, previously a documented gap) — and `Stats.ensnaring_strike_target`/
`ensnaring_strike_dice_count` (the DoT's own die count, `+1d6` per slot level above 1st via
`upcast_dice_count`).

**The Restrained condition itself** (`Enemy.restrained_turns`): speed 0 in `_decide_action()` (same
shape as `rooted_turns` — skips movement, still attacks if already adjacent; doesn't decrement the
counter itself, since `decide_turn()`'s own tick below already does), ADV on attacks against it
added inline at the two primary melee/ranged attack-roll sites (`player.gd._bump_attack()`/
`PlayerRanged.ranged_attack()` — any kind, not folded into `PlayerVfx.has_advantage()`, same
Prone-precedent pattern), DISADV on its own attack rolls folded into the existing disadv pool in
`_attack_player()`/`_attack_companion()` alongside `poisoned_condition_turns`/`enfeeble_turns`.
**`decide_turn()`'s own tick** (right after the Paralyzed/Hold Person block): rolls
`Stats.ensnaring_strike_dice_count`d6 Piercing — this ALWAYS lands regardless of the save outcome
(5e RAW: the save only ever tries to break free, it never stops the thorns from biting that same
turn) — with its own kill-handling tail (`GameState.gain_exp(exp_reward/2)` + `remove_enemy()` +
`die()`, same "environment, not a direct player swing, landed the kill" shape
`DungeonFloor.tick_fire_damage_for()` already uses) if the DoT itself is lethal. If the enemy
survives the tick, it then repeats the STR save vs `restrain_save_dc` — a pass clears
`restrained_turns` and ends the caster's Concentration (`GameState.end_concentration()`) via the
same `"ensnaring_strike"` case `end_concentration()`'s own exhaustive match gained; a fail just
decrements `restrained_turns` (cosmetic/redundant — the REAL end trigger is either a save success
or the outer `Stats.ensnaring_strike_turns` backstop reaching 0 on the player's own turn). Shown on
Ctrl-Inspect (`EnemyInspect.status_entries()`'s new `"restrained"` entry). **No status-tray icon
and no Scroll of Ensnaring Strike** — same precedents as Hail of Thorns, for the identical reasons.

Longstrider/Detect Magic are still NOT opened up to
Ranger — a deliberately narrow scope cut, not an oversight (extend `RANGER_SPELL_IDS` further in a
future pass if Ranger's spell list gets another content pass) — a real content gap (this codebase
has little other nature-flavored spell content of its own, e.g. the real 2024 Ranger list's
Ensnaring Strike/Goodberry/Zephyr Strike/etc.), not a bug; the starting-spell picker below already
degrades gracefully to fewer than 3 cards when the eligible pool is this thin.
`SpellDb.CLASS_SPELL_LISTS["RANGER"]` feeds the level-up spell-learn picker exactly like Wizard's
own entry — `GameState._roll_spell_learn_choices()` was generalized to look up
`Stats.CharacterClass.keys()[character_class]` instead of a hardcoded `"WIZARD"` string, and
`gain_exp()`'s call site dropped its `character_class == WIZARD` gate in favor of a bare
`caster != null` check, so a Ranger level-up now offers the exact same "pick 1 of up to 3" mandatory
growth picker (`spell_learn_picker.gd`) Wizard already had.

**Onboarding**: a Custom-path Ranger reaches the Mastery Picker after race select (its
`mastery_cap()` is 2, unlike Wizard's 0) — `mastery_picker.gd`'s `_close()` was extended so that,
in character-creation mode, if the class has a `caster` (Ranger today), it spawns
`cantrip_select.gd` (generalized — see that file's own header comment for the Wizard-vs-Ranger
branch split) for a single "pick 1 of 3" random level-1-spell round via
`GameState.choose_starting_spell()`, in place of going straight to `character_summary.gd`; that
picker's own confirm/Back then continues on to the summary screen / back to the Mastery Picker
respectively. Premade Tish (Wood Elf Ranger, `character_select.gd`) carries a fixed `"spell1":
"misty_step"` key, applied via the same `choose_starting_spell()` call every premade hero's fixed
spell picks already use — no separate code path needed.

**Everything else Wizard's leveled-spell system already built is caster-generic, not
Wizard-specific, and needed zero changes for Ranger to inherit it for free**: the Spellbook
overlay (`O` key, gated on `player_stats.caster != null`), the Special quick-cast slot + Alt+click
cast, `Scroll of <Spell>` casting (already used INT for a non-caster and the caster's own ability
otherwise — Ranger's WIS flows through the same `SpellcasterState.spell_attack_bonus()`/
`spell_save_dc()` unchanged), the always-visible spell-slots HUD row, and save/load
(`Stats.to_dict()`/`from_dict()`'s `caster_known_spells`/`caster_prepared_spells`/
`caster_slot_remaining` fields were already keyed off `caster != null`, never a class check) all
just work. See `scripts/items/CLAUDE.md`'s spellcasting-data section for `HalfCasterSlotPool`'s
own field-level detail.

**Tier 1 talents** (levels 1–5, point-gated, same schedule as Barbarian's — see
`GameState._setup_ranger_talents()`), all three deliberately weapon-agnostic (none require a
ranged weapon to be useful):
- **Trailblazer** (`talent_id: "trailblazer"`, max 3): R1 ignores Mud/Water's difficult-terrain
  penalty (`player.gd._try_move()`/`_execute_queued_path()`, new bypass flag alongside the
  existing Wild Heart Panther/Salmon ones). R2 gives enemies standing in Mud/Water Disadvantage
  when attacking the player (`Enemy._attack_player()`'s `extra_disadv`). R3 (passive wider trap
  detection radius) is **not yet wired** — `player_actions.gd`'s passive trap-perception mechanism
  needs review first; investing the rank is safe, just currently inert.
- **Bloodhound** (`talent_id: "bloodhound"`, max 3): R1 grants Advantage on the first attack
  against a freshly-marked target (`Stats.hunters_mark_fresh`, consumed on that first attempt
  regardless of hit/miss/rank — wired into all 4 player.gd melee attack-roll sites plus ranged/
  thrown). R2 debuffs the Marked target's effective Passive Perception by `BLOODHOUND_R2_PP_DEBUFF`
  (2) against the player only, in `player.gd._resolve_stealth_check()`. R3: when the Marked target
  dies, `Enemy.die()` calls `PlayerRangerTalents.try_bloodhound_remark()` to re-mark the nearest
  visible enemy for free (no use spent).
- **Twin Fang** (`talent_id: "twin_fang"`, max 3): R1 is a **dead rank** — Hunter's Mark's bonus
  die extending to Off-hand/Nick swings used to be R1's effect; that's now baseline (see "Ranger
  class" above / `docs/TODO.md`'s "Twin Fang R1 redesign") and no longer reads
  `get_talent_rank("twin_fang")` at all. R2 keeps the Off-hand attack's full ability modifier
  against the Marked target specifically (`_resolve_offhand_attack()`'s `dmg_mod`, skipping the
  usual dual-wield penalty). R3: the Marked target can never gain Advantage on its attacks against
  the player (`Enemy._attack_player()` suppresses the Fog-Cloud ADV source when the attacker IS
  the mark — the only enemy-side ADV source that exists today).

## Warlock class

The 5th real playable class (previously locked art only). `Stats.apply_class_defaults()`'s
WARLOCK branch: CHA 16/CON 14/DEX 12/WIS 10/INT 10/STR 8, d8 HD, WIS+CHA check proficiency, Simple
weapons, Light armor. Starting gear (`GameState._give_warlock_starting_items()`): a Dagger (Main
Hand) + Leather Armor. Character-select entry: `scripts/ui/class_select.gd`'s `CLASS_DATA` (index
`Stats.CharacterClass.WARLOCK` = 11) — Warlock was removed from `LOCKED_CLASSES`.

**Pact Magic** (`caster.slot_pool` is a `PactSlotPool`, `scripts/items/pact_slot_pool.gd`,
`spellcasting_ability = "CHA"`) — the THIRD distinct spell-slot progression alongside Wizard's
`StandardSlotPool`/Ranger's `HalfCasterSlotPool` (see `scripts/items/CLAUDE.md`'s spellcasting
section for the shared interface). Real 5e Pact Magic shape: very few slots, but ALWAYS at the
highest available level, refreshing on a SHORT rest instead of long rest:

| Character level | Slot count | Slot level |
|---|---|---|
| 1 | 1 | 1 |
| 2 | 2 | 1 |
| 3 | 2 | 2 |
| 5 | 2 | 3 |
| 7 | 2 | 4 |
| 9 | 2 | 5 |
| 11 | 3 | 5 |
| 17 | 4 | 5 |

`PactSlotPool.max_slots()` always returns exactly ONE key (unlike the other two pools' multi-level
dicts). **Automatic upcast**: `available_level(spell)` returns the CURRENT pact slot level (not
`spell.level`) whenever a known spell's own level is at or below it and a charge remains — every
Pact Magic spell is always cast at the single current slot level. This reintroduces auto-upcast,
which Wizard's own `StandardSlotPool` explicitly rejected (see that file's comment) — Warlock is a
correctly-isolated pool class, so that rejection doesn't carry over; no other file needed to
change, since `PlayerSpellcasting._cast_level_for()` already just forwards whatever
`available_level()` returns straight into `SpellEffects.cast_*()`. **Recharge**: `on_short_rest()`
(a method the other two pools don't implement) is the real recharge path, called from
`GameState._on_short_rest_completed()`; `on_long_rest()` is kept as a harmless full-refill
fallback (a long rest also grants everything a short rest would).

**Spell list** (`SpellDb.WARLOCK_SPELL_IDS`, real 5e 2024 Warlock overlap with the shared
`SpellDb` pool — all genuinely on Warlock's actual class list, no reflavoring): `witch_bolt`,
`expeditious_retreat`, `darkness`, `hold_person`, `invisibility`, `misty_step`,
`ray_of_enfeeblement`, `hideous_laughter`, `hellish_rebuke`, `hex` — the first 7 already existed as Wizard
entries, zero new spell content needed; **Hellish Rebuke** was promoted from a Tiefling-legacy-only
grant to a real, independently-learnable entry (`class_list = ["WARLOCK"]`, deliberately NOT also
in `LEVELED_SPELL_IDS`/Wizard's own list — real 5e/2024 Hellish Rebuke is Warlock-only) — see its
own bullet further down for the mechanism, which is identical either way it's acquired (still a
toggle-armed reaction, not a normal on-demand cast — `_build_spell_ability()` special-cases
`spell_id == "hellish_rebuke"` to build the toggle ability regardless of the acquisition path); a
Tiefling of any class still gets it free via Fiendish Legacy too, same "two independent paths to
the same spell" pattern every other promoted lineage/legacy spell in this codebase uses;
**Hex** (`class_list = ["WARLOCK"]` only — real 5e/2024 Hex has no Wizard/Sorcerer access either)
is a genuinely new 1st-level Enchantment/AUTO_HIT/ENEMY spell — see its own "Hex" section further
down for the full curse/bonus-damage/disadvantage/free-recast-on-kill mechanism; **Tasha's
Hideous Laughter** (`class_list = ["WARLOCK", "WIZARD"]`,
also real on Bard's list — not listed there since Bard isn't a playable class) is a genuinely new
1st-level Enchantment/SAVE/WIS spell, 2-tile range, Concentration up to 10 turns: a failed save
knocks the target Prone AND Incapacitated (`Enemy.apply_status("prone", 1)` +
`Enemy.incapacitated_turns = 10`, dispatched via `SpellEffects.cast_leveled_save_at_enemy()`'s
`"hideous_laughter"` case, same `dice_count <= 0` pure-debuff shape as Hold Person/Ray of
Enfeeblement above). The target repeats the WIS save at the end of each of its own turns
(`Enemy.decide_turn()`, no Advantage) AND again, with Advantage, on every landed damage instance
(`Enemy.take_typed_damage()`) — both routed through the shared `Enemy._resolve_hideous_laughter_save(with_adv)`
resolver (`resist_check_detailed()` gained a generic `force_adv: bool` param for this one-off ADV
source). A pass ends the Incapacitated half early (and the caster's Concentration with it, via
`Stats.hideous_laughter_target`/`hideous_laughter_turns`, same live-reference-array-not-serialized
precedent as `hold_person_target` — both `Array[Enemy]`, not a single `Enemy`) — **Prone is
deliberately left untouched either way**, per the spell's own text; it clears itself normally the
next time the target's own turn lets it stand up.
**Documented simplification**: a single grouped damage instance (e.g. Magic Missile's 3 darts
landing on the same target, which sum into ONE `take_typed_damage()` call — see
`scripts/entities/CLAUDE.md`'s Magic Missile entry) only triggers one on-hit repeat, not one per
die, unlike separately-resolved hits (Eldritch Blast's independent beams) which each trigger their
own. **Upcast (+1 target per spell slot level above 1st) IS implemented** — a Warlock casting this
above its base level (Pact Magic auto-upcast) can pick additional ENEMY targets, each with its own
save, via the generalized multi-target click flow — see this file's own "Spell upcasting" section
below for the full mechanism (`Stats.hideous_laughter_target` being an `Array` is exactly what this
needed).
**Cantrips**: starter pick 1 of 3 (`SpellDb.WARLOCK_STARTER_CANTRIP_IDS` — `eldritch_blast`
(new), `chill_touch`, `poison_spray`) via the generalized `cantrip_select.gd` (see below).
`SpellcasterState.cantrip_max()` gained a `WARLOCK` case reusing Wizard's exact numbers (3/4/5
known cantrips at levels 1/4/10 — real 5e Warlock cap differs slightly, 2/3/4, but this project
already takes this "reuse Wizard's shape" liberty elsewhere). `prepared_max()` needed no Warlock
branch — its existing default (`character_level`) already covers any non-Ranger class.

**Eldritch Blast** (`SpellDb._eldritch_blast()`, cantrip, Evocation): real 5e multi-beam/
multi-target — 1d10 Force per beam, `Spell.multi_beam_scaling = true` instead of
`cantrip_tier_scaling` (which grows dice count on a single roll; this instead grows beam COUNT,
each beam its own independent attack roll, at the same tier-1/5/11/17 breakpoints — 1/2/3/4
beams). Reuses Magic Missile's click-to-pick-a-target-per-instance multi-target collection flow
(`PlayerSpellcasting._uses_multi_target_flow()`/`_multi_target_beam_count()`/
`_begin_multi_target()`/`_handle_multi_target_click()`, `scripts/entities/player_spellcasting.gd`)
generalized to also handle an ATTACK_ROLL cantrip, not just Magic Missile's AUTO_HIT darts:
`_mm_enemies_only` restricts beam targets to real enemies (no barrel/door — those have no AC),
`_mm_count` replaces the old hardcoded literal `3`. Each beam can be aimed at a different enemy
(same "click the same target again to focus more onto it" UX as darts). While `_mm_count == 1`
(character level < 5, a single beam), `_begin_multi_target()` logs NO instruction line — a
single-beam cast behaves exactly like a plain single-target cantrip, so the multi-target "choose N
targets" tip would just spam the chat log every time this at-will attack cantrip is fired. Resolution:
`SpellEffects.cast_multi_beam_cantrip()` calls a shared per-target helper,
`SpellEffects._resolve_cantrip_hit()` (factored out of `cast_spell()`, which now just wraps it for
the single-target case) once per collected beam — so Agonizing Blast's +CHA-mod-per-hit and
Repelling Blast's 1-tile push (both Eldritch Invocations, gated `spell.spell_id ==
"eldritch_blast"` inside the helper) correctly apply independently to EACH beam that hits, not
once for the whole cast.

**Onboarding**: `race_select.gd`'s confirm branch (`mastery_cap() > 0` → Mastery Picker, elif
class is WIZARD or WARLOCK → `cantrip_select.gd`) now includes Warlock alongside Wizard.
`cantrip_select.gd` gained an `_is_warlock: bool` branch (mirrors the existing `_is_ranger`
branch): a SINGLE round, "pick 1 of 3" from `WARLOCK_STARTER_CANTRIP_IDS` via
`GameState.choose_cantrip()` — no round-2 level-1-spell pick (Warlock's leveled spellbook grows
via the normal level-up spell-learn picker instead, `SpellDb.CLASS_SPELL_LISTS["WARLOCK"] =
WARLOCK_SPELL_IDS`, same mechanism Ranger already uses).

### Spell upcasting (Warlock Pact Magic only)

Real per-spell upcast benefits are implemented, but the mechanism that makes them ever actually
apply is `PactSlotPool.available_level()`'s own auto-upcast rule (`scripts/items/CLAUDE.md`) —
Wizard's `StandardSlotPool` and Ranger's `HalfCasterSlotPool` both explicitly never upcast a cast
above the spell's own level, so `cast_level == spell.level` always for those two, and every upcast
field below is silently a no-op for them. Only a Warlock casting a known spell while their single
current pact slot level is higher than that spell's own level ever produces `cast_level >
spell.level` — at which point every extra slot level above base applies the spell's own upcast
benefit that many times (D&D 2024's "for each slot level above Nth" convention — casting a 1st-
level spell with a 3rd-level pact slot applies the bonus **twice**, not once).

Three generic `Spell` fields (`scripts/items/spell.gd`) drive this — `SpellEffects.
_upcast_extra_levels(spell, cast_level) -> int` (`maxi(0, cast_level - spell.level)`) is read at
every cast entry point (`cast_leveled_attack_at_enemy()`, `cast_leveled_self()`,
`cast_leveled_at_tile()`) and multiplied by whichever field the spell sets:

- **`upcast_dice_count`** — extra dice (of the spell's own `dice_sides`) per extra level, added
  straight into `spell.dice_count` before the roll (the `Spell` instance is fresh-built per cast
  by `SpellDb.get_spell()`, so mutating it in place is safe — nothing else holds a reference).
  Chromatic Orb (+1d8), Burning Hands (+1d6), Witch Bolt (+1d12 — **only the initial attack roll**,
  never `SpellEffects.tick_witch_bolt()`'s own separate flat-1d12-per-turn tick, which reads no
  `Spell` field at all), Ray of Sickness (+1d8), Fireball (+1d6), Hellish Rebuke (+1d10 — field set
  for consistency, but dead in practice: Hellish Rebuke is only ever granted via Tiefling's fixed-
  level free lineage grant, `trigger_hellish_rebuke()`, which always consumes exactly
  `spell.level`, never a higher slot).
- **`upcast_flat_amount`** — a flat number per extra level, meaning is per-`effect_id`: False Life
  (+5 Temp HP, folded into `cast_leveled_self()`'s roll-total base) and Fog Cloud (+2 tile radius,
  `_resolve_fog_cloud(player, spell, center, extra_levels)`'s own new 4th param).
- **`upcast_extra_targets`** — see the two shapes below, since "an extra target" means something
  structurally different for an ENEMY/SAVE spell than for a SELF/touch spell.

**Chromatic Orb's leap count** doesn't use any of the three fields above — it's `cast_level`
directly (RAW: "the orb can leap a maximum number of times equal to the level of the slot
expended, and a creature can be targeted only once by each casting"). `cast_leveled_attack_at_enemy()`'s
`"chromatic_orb"` case now loops (`leaps_done < max_leaps`, `max_leaps = cast_level`) instead of
firing at most one leap, tracking every enemy already hit this cast (`used_targets: Array[Enemy]`)
so `_pick_chromatic_orb_leap_target()` never re-targets one of them.

**Extra ENEMY targets (Hold Person, Hideous Laughter)** — real multi-target collection, reusing
Magic Missile/Eldritch Blast's existing click-to-pick-a-target-per-instance flow
(`PlayerSpellcasting._begin_multi_target()`/`_handle_multi_target_click()`,
`scripts/entities/CLAUDE.md`'s Magic Missile entry), generalized with a third dispatch kind:
`_uses_multi_target_flow(spell, from_scroll)` now also returns true for a SAVE-resolution ENEMY
spell with `upcast_extra_targets > 0` currently castable ABOVE its own base level (never true for a
Scroll of `<Spell>` — `from_scroll` short-circuits it, since a scroll always casts at the spell's
own base level regardless of the reader's own live pact slot) — `_multi_target_beam_count()` then
collects `1 + upcast_extra_targets × extra_levels` targets instead of Magic Missile's fixed 3 or
Eldritch Blast's tier count. **`[Space]` resolves early** with fewer than the max
(`PlayerSpellcasting.finish_multi_target_early()`, wired in `player.gd`'s key-input handler ahead
of the normal Space-key-waits binding, gated on `is_collecting_multi_target()`) — casting Hold
Person with a 3rd-level pact slot offers up to 2 targets, but pressing Space after locking in just
1 casts immediately with only that one, since the base cast is always a legal single target on its
own. `SpellEffects.cast_leveled_save_at_enemy()` gained a 6th param, `also_targets: Array[Enemy]`
(empty for every pre-existing single-target call site, so the base spell is unchanged) — every
target (primary + extras) rolls its own independent save under ONE shared turn/slot/animation; the
Concentration switch-check (breaking a currently-different concentration spell) fires at most ONCE
for the whole cast, and only if at least one target's save actually fails, matching the original
single-target "a whiffed cast never disturbs an unrelated concentration effect" behavior.
`Stats.hold_person_target`/`hideous_laughter_target` are `Array[Enemy]`, not a single `Enemy`, for
exactly this reason — a target that saves off early is removed individually
(`GameState.remove_hold_person_target(enemy)`/`remove_hideous_laughter_target(enemy)`, called from
`Enemy.decide_turn()`'s repeated-save branch and `_resolve_hideous_laughter_save()`), and the whole
spell (Concentration) only actually ends once the array empties out; `GameState.end_concentration()`
and `player.gd`'s own duration-backstop tick both loop the array instead of clearing one reference.

**Touch-target upcast (Invisibility, Longstrider)** — both are SELF-target touch spells with no
general ally-targeting system (`scripts/entities/CLAUDE.md`'s "Wizard leveled spells" → Mage
Armor's own "No ally-buff targeting exists" note); their upcast ("+1 creature you touch") is scoped
to the one other valid touch target this engine has, the Companion — same "self, or the Companion"
click pattern `PlayerAasimar.resolve_healing_hands()` already established for Healing Hands.
`PlayerSpellcasting._cast_self(spell, from_scroll, clicked)` gained a 3rd param (default sentinel
`Vector2i(-1,-1)`, threaded from `try_cast_at()`/`cast_direct()`'s own `clicked`) forwarded to
`SpellEffects.cast_leveled_self(..., clicked)` — the base self-cast is completely unaffected by
where you click (any click still confirms on yourself, unchanged), but if `extra_levels > 0` and
the click landed exactly on the Companion's own tile, the upcast ALSO reaches it:
- **Invisibility**: `Companion.invisibility_turns` (new field — `Enemy._can_see_entity()`/
  `_target_is_untouchable()` both already had a "or a future invisible companion" comment
  anticipating exactly this; both now check it identically to `Stats.invisibility_turns`). Shares
  the caster's own Concentration/duration — `player.gd`'s per-turn tick and
  `GameState.end_concentration()`'s `"invisibility"` branch both clear it the instant the caster's
  own invisibility ends, for any reason (natural expiry, a broken concentration check, casting a
  different concentration spell).
- **Longstrider**: flavor-only log line, no mechanical speed bonus — this engine has no movement-
  speed-scaling concept for `Companion` at all (no per-round "extra move" hook exists the way
  `Player._speed_gate_accum`'s duty cycle has for the player), a documented scope cut
  rather than a half-built mechanic, same tier as Speak with Animals' own flavor-only cantrip.

**No upcast benefit is intentionally set** for Misty Step, Expeditious Retreat, Darkness, and Ray
of Enfeeblement — all four genuinely have no "At Higher Levels" text in real 5e/2024 rules, so
their `Spell` entries simply leave every upcast field at its `0` default; a Warlock upcasting one
of these still gets the automatic Pact Magic slot-level bump (nothing wasted — the higher slot is
still spent), just no extra mechanical effect from it, matching RAW exactly.

### Hex

Real Warlock-only 1st-level Enchantment (`SpellDb._hex()`, `class_list = ["WARLOCK"]`, never added
to `LEVELED_SPELL_IDS`/Wizard's own class list — same "each spell's actual RAW class list matters"
discipline as Hellish Rebuke). `resolution = AUTO_HIT`, `target_kind = ENEMY` — the ONE leveled
spell besides Magic Missile with this shape, and unlike Magic Missile it's genuinely single-target
(no multi-target collection flow), so `PlayerSpellcasting.try_cast_at()`'s `ENEMY` dispatch gained
a real `Resolution.AUTO_HIT` branch (previously dead code — every AUTO_HIT ENEMY cast used to be
Magic Missile, always intercepted earlier) routing to a new `SpellEffects.
cast_leveled_auto_hit_at_enemy()`. **Free casting time** (RAW: bonus action) — ends via the same
`player._reverted_this_round = true; TurnManager.revert_to_waiting()` free-action pattern Shield
uses, instead of `player._handle_post_attack_turn()`.

`SpellEffects._resolve_hex()` places the curse: sets `Stats.concentration_spell_id = "hex"`,
`Stats.hex_target = target` (single `Enemy`, not an `Array` — no `upcast_extra_targets`, see
below), `Stats.hex_turns = 600 + upcast_flat_amount × extra_levels` (the upcast is a **duration**
bump, +600 turns/level — the one spell whose upcast shape is neither dice nor targets), and rolls
`Stats.hex_ability` — one of `"str"/"dex"/"con"/"int"/"wis"/"cha"`, uniform random
(`SpellEffects.HEX_ABILITIES`, `Rng.pick()`) — fresh on every cast, including a recast on the same
target.

Three ongoing effects while the curse holds:
- **+1d6 Necrotic on every landed attack** — `PlayerWarlock.hex_bonus_die(enemy)`
  (`scripts/entities/player_warlock.gd`, a new always-instantiated composition child-node, `_warlock`
  on `player.gd`) returns a fresh `Rng.roll(6)` whenever `enemy == Stats.hex_target`, else `0`. Per
  the spell's own "weapon, cantrip, or spell attack" text, this is wired into **every** ATTACK_ROLL
  damage site, not just weapons like Hunter's Mark (`scripts/entities/CLAUDE.md`'s Ranger section)
  — `player.gd._bump_attack()` (primary melee) and `_resolve_offhand_attack()` (Off-hand/Nick),
  `PlayerRanged.ranged_attack()`, `PlayerThrowTool._throw_weapon()`, `SpellEffects.
  _resolve_cantrip_hit()` (cantrip attack rolls — Fire Bolt, Eldritch Blast, etc.), and
  `SpellEffects._resolve_spell_attack_bolt()` (leveled ATTACK_ROLL spells — Chromatic Orb, Witch
  Bolt, Ray of Sickness, including Chromatic Orb's own leap re-roll). Each site follows the exact
  "second, independent same-hit damage instance" shape the damage-stacking rule requires (own
  `take_typed_damage()` call, own floater with a stack-index offset past whatever other bonus
  instances already fired that hit, own `dmg:`-tagged segment folded into the SAME log line) —
  never wired into Cleave/Opportunity Attacks, matching Hunter's Mark's own documented scope limit.
- **Disadvantage on checks using the cursed ability** — `Enemy.resist_check_detailed()` gained a
  `hex_disadv` term (`GameState.player_stats.hex_target == self and ...hex_ability == stat_key`),
  netted into `disadv_sources` alongside `enfeeble_str_disadv`/`frightened_disadv` like every other
  DISADV source in that function. Since this codebase has no separate saves-vs-checks distinction
  (root `CLAUDE.md`: "all defensive rolls are checks"), this is a deliberate approximation that also
  reaches SAVE-resolution spell resistance checks (Ray of Frost, Fireball, etc.) when the stat
  matches — not just genuine ability checks (Push/Topple/Grip of the Forest) — accepted as the most
  faithful implementation available given the engine's own unified-roll convention. Enemy attack
  ROLLS are untouched (the spell's own "attacks don't count" carve-out) — this term only ever feeds
  `resist_check_detailed()`, never `_resolve_attack_roll()`.
- **Free recast on kill**: `Enemy.die()` — if the dying enemy was `Stats.hex_target`, clears the
  reference and, if the curse's Concentration was still active, arms
  `Stats.hex_free_recast_pending`. `SpellEffects._resolve_hex()` checks and consumes this flag
  BEFORE the generic `_consume_slot()` chokepoint on its very next Hex cast (any target, not just
  a re-cast on a new enemy) — no spell slot spent that time. Mirrors Hunter's Mark/Bloodhound's own
  "target died, don't waste it" economy, just a flat free-cast instead of a re-mark. The curse's own
  Concentration is NOT force-ended by the kill (matching Hunter's Mark's identical choice — see that
  section) — it keeps ticking down `hex_turns` in a targetless state until it naturally expires, a
  damage-based concentration check fails, or a different concentration spell is cast; only THOSE
  three ways of losing the curse forfeit it for real — a kill is explicitly compensated by the free
  recast per the spell's own design intent.

`Stats.hex_target`/`hex_turns`/`hex_ability`/`hex_free_recast_pending` are all deliberately NOT
serialized (live `Enemy` reference, same precedent as `witch_bolt_target`/`hunters_mark_target`).
No art sourced yet (`icon_path` points at `res://icons/spells/1/hex.png`, renders blank until
added, same precedent as Fog Cloud/False Life when they first shipped). No Scroll of Hex exists
yet — a documented gap, not a deliberate holdout like Hellish Rebuke's reaction shape.

### Eldritch Invocations

A growing pool of feat-like picks, permanent once taken (no respec — matches talent investment
permanence). `scripts/items/eldritch_invocation.gd`'s `EldritchInvocation` is a simpler, pick-once
cousin of `Talent` (no ranks): `invocation_id`, `invocation_name`, `description`, `min_level`,
`requires_invocation` (unused by any of the 8 entries shipped this pass). Built in code via
`GameState.eldritch_invocation_list()` (static func, not a const — a `Resource.new()` isn't a
valid const expression), same "build fresh every call" convention as `SpellDb.get_spell()`.

**Cumulative known-count schedule** (`GameState.WARLOCK_INVOCATION_SCHEDULE`, direct owner spec):
level 1→1, 2→3, 5→5, 7→6, 9→7, 12→8, 15→9, 18→10. `GameState.warlock_invocation_slots_pending`
tracks unfilled slots; `GameState._grant_invocation_slots_for_level(old, new)` (called from
`gain_exp()`'s level-up block) diffs the schedule's highest-threshold-crossed value and adds the
delta — same `old_level < N and new >= N` threshold-crossing shape Elf/Tiefling lineage spells use.
The level-1 grant is a special case: `gain_exp()`'s threshold-crossing check never fires for a
character's OWN starting level (no level-up ever crosses "old < 1, new >= 1"), so
`_give_warlock_starting_items()` grants it directly and idempotently. **Schedule slots beyond the
8 designed invocations (levels 12/15/18) sit pending with nothing yet to spend them on** — same
Tier-2-pending precedent as `talent_points`; a natural place for more Invocations later, including
**Pact of the Blade/Chain/Tome** — 2024/5.5e rules (this project's ruleset, see root `CLAUDE.md`'s
opening line) folded the old 2014 5e "separate Pact Boon step" into three ordinary,
level-3-unlocked Invocations, so they'll simply be 3 more entries in `eldritch_invocation_list()`
whenever they're built, not a parallel character-creation step. Deliberately not implemented yet
(more invocation content is planned incrementally, per direct owner request) — do not build a
separate Pact Boon picker/field for these.

**8 invocations shipped this pass** (`GameState.eldritch_invocation_list()`):
- **Agonizing Blast** (lvl 1) — Eldritch Blast hits add CHA mod damage. Folded into
  `SpellEffects.cast_spell()`'s `flat_mods` array (same-type stacking, per the damage-stacking
  rule) via a `spell.spell_id == "eldritch_blast" and GameState.knows_invocation("agonizing_blast")`
  check right before `build_damage_instance()`.
- **Repelling Blast** (lvl 1) — a non-lethal Eldritch Blast hit pushes the target 1 tile directly
  away **on a failed CON save** (`resist_check_detailed(dc, use_con=true, magical=true)` vs the
  spell save DC, `_save_dc(stats, spell)`) — reuses `DungeonFloor.resolve_push()` verbatim, called
  per-beam from `_resolve_cantrip_hit()`'s effect-dispatch tail. **Deviates from 5e RAW on
  purpose** (real Repelling Blast has no save — the 10 ft push is a fraction of a 30 ft move): on a
  1-tile grid a guaranteed 1-tile shove per beam costs the target a full turn of movement, so it's
  gated behind a save the same CON-based way the Heavy Crossbow's Push weapon mastery and the
  Maul's Topple already are (the established "resist forced movement / knockdown" stat in this
  codebase). Logs a hoverable `save:` roll breakdown on both outcomes.
- **Armor of Shadows** (lvl 1) — Mage Armor castable at will, no spell slot.
- **Fiendish Vigor** (lvl 1) — False Life castable at will, no spell slot.
- **Eldritch Sight** (lvl 1) — Detect Magic castable at will, no spell slot.
- **Devil's Sight** (lvl 5) — ignores the vision-collapse-to-1 penalty from standing inside a Fog
  Cloud/Darkness zone (`GameState.effective_fov_radius()`'s Blinded branch checks
  `not knows_invocation("devils_sight")`) — every other Blinded effect (ADV/DISADV on attack
  rolls) still applies normally.
- **Beguiling Defenses** (lvl 5) — Advantage on saves to avoid/end Frightened — reflavored from
  RAW's Charm immunity (no Charmed condition exists in this engine, same gap as Elf's Fey
  Ancestry); mirrors Halfling Brave's own ADV term exactly, added to both Frightened-save sites
  (`Player._on_turn_started()`'s repeated end-of-turn save, `Enemy._execute_cast_scare()`'s
  initial save).
- **Ascendant Step** (lvl 9) — Misty Step castable at will, no spell slot.

**At-will free-cast mechanism** (Armor of Shadows/Fiendish Vigor/Eldritch Sight/Ascendant Step):
`GameState.WARLOCK_INVOCATION_SPELL_GRANT` maps spell_id → invocation_id;
`GameState.warlock_invocation_free_cast(spell_id) -> bool` is checked at every chokepoint the
Elf/Tiefling lineage free-cast check already is —
`PlayerSpellcasting.begin_cast()`'s slot-availability gate, `_cast_level_for()`, and
`SpellEffects._consume_slot()` — genuinely unlimited (no counter to decrement, unlike the lineage
spells' `proficiency_bonus`-per-long-rest counter). Learning one of these four invocations
(`GameState.learn_invocation()`) grants an always-available ability-bar entry via
`_build_invocation_spell_ability()` → `_build_spell_ability()` + `add_ability()`, same "always
prepared, outside `known_spells`/`prepared_spells` bookkeeping" shape as an Elf/Tiefling lineage
spell. The other four invocations (Agonizing Blast/Repelling Blast/Devil's Sight/Beguiling
Defenses) grant no ability at all — pure passive flags read via `knows_invocation()` at their
trigger site.

**Picker UI**: `scripts/ui/invocation_picker.gd` — a fork of `subclass_select.gd`'s pattern
(non-dismissible dim overlay + centered bordered `Panel`, `GameState.invocation_picker_open` input-
block flag added to every input-gate chain in `player.gd`) rather than `talent_picker.gd` — no
ranks/points to spend, just "pick one from the currently-eligible list"
(`GameState.eldritch_invocations_eligible()`, filtered on `min_level` + not already known).
Icon-focused tile grid, up to 3 per row — same convention as `cantrip_select.gd`/
`spell_learn_picker.gd`, see `scripts/ui/CLAUDE.md`'s own section on it; `EldritchInvocation.
icon_path` exists but no art has been sourced for any invocation yet, so every tile currently
renders with a blank icon area. Tile-click commits immediately and calls `GameState.learn_invocation(id)`; if
`warlock_invocation_slots_pending` is still > 0 after the pick (multiple slots opened on one
level-up, e.g. level 2's +2), the picker re-spawns itself for the next pick. If no invocation is
currently eligible (pending slots outrunning designed content), shows a "no eligible invocations"
message with a Continue button that closes WITHOUT respawning — respawning-on-empty would loop
forever. Spawned by `hud.gd._on_invocation_choice_required()` on `GameState.
invocation_choice_required` — guarded on `GameState.class_selected` (the level-1 grant fires
mid-character-creation, well before that flag is set) and re-checked from `_on_class_chosen()`
(which `class_chosen` re-fires from `character_summary.gd`'s final confirm, the first safe point
to actually open it for a fresh character).

**Not implemented this pass** (documented scope cuts, matching this codebase's own "narrow case,
not the full system" precedent): **Pact of the Blade/Chain/Tome** (3 more Invocation entries to
add later, NOT a separate Pact Boon step — see the schedule note above); true 5e multi-beam/
multi-target Eldritch Blast; player-chosen upcast slot level (Pact Magic's own upcast is
automatic-to-max only, no picker); Invocations beyond the 8 above (levels 12/15/18's schedule
slots sit pending, meant to absorb Pact of the Blade/Chain/Tome and future additions).

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
  currently visible, without a second redundant cap (Fire Bolt's nominal 6-tile range is real, not
  silently capped to the FOV radius of 5). Esc cancels (branch beside `_hook_mode_active`'s in
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
  - **Fire Bolt** — 6 tiles, 1d10 Fire. No `effect_id` (pure generic damage path) — if the target
    stands on a `GRASS` tile, the hit also calls `DungeonFloor.ignite_grass()` (one round of
    burning, long enough to spread and burn whoever's standing there, before it converts to
    TRAMPLED_GRASS); otherwise it calls `DungeonFloor.ignite_flammable()`, which sets a Barrel or
    (unlocked) Door alight for an HP-based burn-down (2d4 Fire/round off its own HP, not a flat
    turn timer) — see `scripts/world/CLAUDE.md`'s "Barrels + flammable props". Fireball and Burning
    Hands' AoE resolvers (below) ignite every flammable tile they pass through the same way.
  - **Ray of Frost** — 3 tiles, 1d8 Cold. `effect_id = "ray_of_frost"`: on a hit, the target rolls
    a STR save (`resist_check_detailed()`, `dc = SpellcasterState.spell_save_dc()`) — logged to
    chat with a hoverable `save:` tooltip **either way** (pass or fail, Topple's
    `prof_label=Floor` convention — this is the enemy's floor-scaling bonus, not a proficiency
    bonus), not just on a fail; on a fail, applies the real Slowed status
    (`target.apply_status("slowed", 3)`) — the same duty-cycle "shave one movement step per turn"
    mechanism Mud/Water/Goliath's Frost Giant ancestry already use (see "Enemy resist checks"
    above's `Enemy.slowed_turns` entry and "Goliath" below), not a full movement-skip like
    `rooted_turns` — matches the real spell's "speed reduced by 10 ft" text far better than an
    earlier version of this spell's own bespoke `frozen_feet_turns` field (a rooted-style full skip)
    did; that field was removed once this shared mechanism replaced it.
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
- **Toll the Dead** (Necromancy, `effect_id: "toll_the_dead"`, SAVE/WIS, ENEMY, 3 tiles): target
  WIS-saves or takes `1d8` Necrotic — `1d12` instead if the target is already missing HP (checked
  at resolve time via `target.stats.current_hp < target.stats.max_hp`), same cantrip-tier dice-
  count scaling as the original three. `SpellEffects.cast_cantrip_save_at_enemy()` is the shared
  resolver for this and Mind Sliver below — no attack roll, just `Enemy.resist_check_detailed()`
  with the matching `use_wis`/`use_int` flag (see below) and a hoverable `save:` tooltip either way.
- **Mind Sliver** (Enchantment, `effect_id: "mind_sliver"`, SAVE/INT, ENEMY, 3 tiles): target
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
- **Light** (Evocation, `effect_id: "light"`, AUTO_HIT, TILE, touch range 1): touch almost
  anything except bare terrain/walls or a living creature and it becomes a **real light source**,
  not cosmetic. `SpellEffects.cast_light_at_tile()` checks the target tile in priority order — a
  floor item (`dungeon_floor.get_item_at(tile_pos) != null`, never a worn/carried one), else a
  door (`has_door_at()`), else a GRASS tile (`get_tile_type() == GRASS`), else a barrel
  (`has_barrel_at()`), else a **trap** (`not get_trap_at(tile_pos).is_empty()`) — and rejects the
  cast (gray log line, no turn-consuming side effect beyond the swing animation) if none match;
  **Mud/Water and every other bare terrain tile are deliberately excluded**, same as any wall/void
  tile. **Targeting an unrevealed trap reveals it** (`dungeon_floor.reveal_trap(tile_pos)`, called
  right when the "trap" branch matches) — bugfix: casting Light directly at a trap tile (e.g. a
  still-hidden Bear Trap) used to always reject with "You must touch an object, door, patch of
  grass, or barrel," since a trap wasn't one of the checked target kinds at all; shining a light
  right on the mechanism now sensibly both reveals AND lights it. `GameState.set_light_source(pos,
  color, item, kind)` (random color from a fixed palette; `kind` is `"item"`/`"door"`/`"grass"`/
  `"barrel"`/`"trap"`, `item` only meaningful for the `"item"` kind — kept so the light can tell
  when it's gone) is read every `DungeonFloor.update_fog()` call, which unions its own
  `_compute_shadowcast(pos, LIGHT_SOURCE_RADIUS=4)` into the player's visible-tiles set (walls
  still block it — same shadowcast algorithm as the player's own FOV) — see
  `scripts/world/CLAUDE.md`'s "FOV" section. Only one Light source active at a time (recasting
  replaces it outright); ends on a completed rest (short or long —
  `_on_short_rest_completed()`/`long_rest()` both call `GameState.clear_light_source()`), on floor
  descent (`advance_floor()` — the lit thing is left behind on the previous floor; this codebase's
  own reinterpretation of the spell's RAW "1 hour" duration, since there's no real-time clock to
  hang that off of), **or the instant the lit thing itself is gone** — checked every `update_fog()`
  call via a `light_source_kind`-branched validity check (item: still present at
  `get_items_at(light_source_pos)`; door: `has_door_at()` still true, i.e. not burnt away; grass:
  tile is still GRASS, i.e. not destroyed/trampled by fire; barrel: `has_barrel_at()` still true,
  i.e. not burnt down). `DungeonFloor._update_light_source_glow()` tints every tile the light's own
  shadowcast actually reaches with `GameState.light_source_color` (not just a single square over
  the source tile) so the player can see both where it is and how far it reaches.

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
concentration_spell_id != ""` (unconditionally now, not just when switching to a DIFFERENT spell —
bugfix: recasting the exact SAME concentration spell used to skip this call entirely since the id
already matched, so a fresh Faerie Fire cast elsewhere left the PREVIOUS cast's outlined enemies
permanently debuffed/advantaged with nothing left to ever clear them; every site now always calls
`end_concentration()` first, passing an empty `reason_log` — no "breaks your concentration" message
— when recasting itself, and the real message only when actually switching to a different spell),
logging "Casting X breaks your concentration." Fixed bug:
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
The tooltip body also appends a turns-remaining line via `Stats.concentration_turns_remaining()`
— a `match concentration_spell_id` mirroring `end_concentration()`'s own exhaustive match of every
concentration spell's duration field; any new concentration-granting spell must add itself to
both.

See "Blade Ward" above and "Witch Bolt" below for each spell's own mechanism. Concentration spells
today: Blade Ward, Witch Bolt, Expeditious Retreat, Fog Cloud, Darkness, Detect Magic, Pass Without
Trace, Hunter's Mark, Ray of Enfeeblement, Hold Person, Faerie Fire, and **Invisibility** (see its
own section below — a real Concentration effect, including breaking on damage).

## Wizard leveled spells (spell slots)

Implements the leveled-spells-and-slots plan (design doc shipped and was deleted from
`docs/architecture/` — this section is now authoritative) on top of the cantrip slice
above. **Simplifications vs. the original plan** (time-boxed for the first implementation pass, flagged
here rather than silently diverging): **no upcasting at all for Wizard** — a spell only ever casts
using a slot that matches its own `level` exactly (`StandardSlotPool.available_level()`); if that
specific slot level has none remaining, the cast fails outright (`"No spell slot available for
X."`), even if a higher slot level is free. (An earlier version auto-promoted to the lowest
available slot ABOVE the spell's own level, which produced unrequested/surprising upcasts — e.g.
Chromatic Orb silently casting at a 5th-level slot with bonus dice — and was removed along with
every `Spell.upcast_dice_per_level`/extra-dice code path per direct owner correction at the time.
**Real upcasting was reintroduced later, Warlock-only** — `Spell.upcast_dice_count`/
`upcast_extra_targets`/`upcast_flat_amount`, exercised only by `PactSlotPool`'s own genuine
auto-upcast, see this file's "Spell upcasting" section — `StandardSlotPool.available_level()`'s own
no-upcasting rule for Wizard is completely unaffected by that later addition.) AoE is
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
**Alt+click Special-slot cast**: `cast_direct()` resolves in the same frame it's clicked, so it
never arms `spell_targeting_active` long enough for `get_armed_spell()` to see it — instead,
`_update_spell_aoe_preview()` falls back to `GameState.special_slot_spell_id` (via
`SpellDb.get_spell()`) whenever Alt is held and no spell is otherwise armed, so holding Alt and
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
  `give_class_starting_items()`, same dispatch as `_give_barbarian_starting_items()`) only seeds
  the level-1 spell-slot pool — no spells are auto-known anymore (owner-requested: a starting
  Wizard now picks exactly 1 cantrip and 1 level-1 spell, not 2+2). The same function also equips
  an already-**lit** Torch in the Off-hand (`torch_lit = true`, `torch_turns_remaining = 600`) —
  every Wizard starts a run with +1 FOV and the Main-Hand Fire-on-hit bonus inactive (it's sitting
  in Off-hand, not Main Hand) until it burns out or is manually moved — see
  `scripts/items/CLAUDE.md`'s "Torch" section for the mechanic itself. `scripts/ui/cantrip_select.gd`
  (Custom path, spawned by `race_select.gd`) runs two "pick 1 of N" rounds: round 1 offers
  `SpellDb.STARTER_CANTRIP_IDS` (3) via `GameState.choose_cantrip()` — which also auto-assigns the
  pick into the Special quick-cast slot (`set_special_slot()`) so it's immediately Alt+click-able
  — round 2 offers the fixed level-1 pair (Magic Missile, Shield) via
  `GameState.choose_starting_spell()`, which learns AND prepares it in one call (prepared cap is 1
  at level 1, so there's nothing else to contend with). Premade heroes bypass both pickers: `Jace`
  in `character_select.gd`'s `PREMADE` const carries fixed `"cantrip": "fire_bolt"` /
  `"spell1": "magic_missile"` keys, applied the same way (`choose_cantrip()` +
  `choose_starting_spell()`) directly on card click.
- **Level-up spell-learn picker**: `GameState.gain_exp()`'s level-up block, WIZARD only, calls
  `_roll_spell_learn_choices()` — rolls up to 3 random candidates from `SpellDb.CLASS_SPELL_LISTS`
  filtered to spells the character can currently slot-cast and not already known, sets
  `spell_learn_pending`/`spell_learn_choices`. `hud.gd._on_player_leveled_up()` spawns
  `scripts/ui/spell_learn_picker.gd` (mandatory, one card commits via `GameState.learn_spell(id)`)
  whenever `spell_learn_pending` is true. With only 4 example spells this often finds zero
  eligible candidates a few levels in — expected, logs a gray "No new spells available to learn."
  line instead of blocking (see the plan doc §7's content-count caveat).
- **Learning auto-slots the ability bar (owner request)**: `GameState.learn_spell(id)` — the single
  chokepoint for the level-up picker AND scroll-taught spells (see "Scrolls" below) — no longer
  just appends to `known_spells`. A newly learned spell — cantrip OR leveled — auto-prepares via
  `set_spell_prepared(id, true)`, which itself silently no-ops past that kind's own cap
  (`cantrip_max()` for a cantrip, `prepared_max()` for a leveled spell) — so learning past the
  relevant cap still adds the spell to your spellbook, it just doesn't jump onto the ability bar
  until you free a slot and prepare it manually from the Spellbook overlay.
- **Cantrip cap governs SELECTION, not learning**: `SpellcasterState.cantrip_max(stats) -> int` —
  Wizard-only today (0 for every other class, extend with a new `match` branch when another
  caster class ships): 3 known cantrips at character level < 4, 4 at levels 4–9, 5 at level 10+.
  A Wizard can freely LEARN a cantrip beyond this cap (via scroll "Learn" or, hypothetically, a
  future level-up growth pick) — it's added to `known_spells` unconditionally — but it only
  becomes an actual usable ability-bar entry (added to `SpellcasterState.prepared_spells`, counted
  by `prepared_cantrip_count()` against the same `cantrip_max()` cap) if there's room; otherwise
  it just sits known-but-unselected in the spellbook, same "known but not selected" shape a
  leveled spell already had past `prepared_max()`. `can_learn_scroll_spell()` only blocks Learn
  when the spell is ALREADY known — the cap no longer hides the option. The Spellbook overlay's
  Cantrips tab shows a real `"X / Y prepared"` counter (no more static "Always ready" text) and
  clicking a cantrip tile toggles it prepared/unprepared exactly like a leveled spell — a
  deliberate simplification of D&D 2024's real rule (cantrips can normally only be swapped on a
  class level-up, not freely at will) per direct owner request, so a cantrip learned past the cap
  isn't otherwise permanently unusable. The one-time character-creation starter pick
  (`choose_cantrip()`) still bypasses any cap check entirely — it only ever grants 1 cantrip,
  always under it, and marks it prepared directly. `SpellcasterState.known_cantrip_count()` (all
  known cantrips, cap or no cap) is now unused by any cap check but kept as a general query.
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
  `cast_leveled_at_tile()`, `cast_leveled_attack_at_enemy()` (Magic Missile is intercepted earlier
  and resolves via its own `cast_magic_missile()`, see below) — each consuming a slot via
  `_consume_slot()` (guarded by `GameState.invincible`, same as every other consumption site)
  before resolving.
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
  whenever **Alt** is held on the click — a deliberate, precision-proof way to center a sphere
  AoE (or resolve a touch SELF spell, see Mage Armor above) on yourself without needing to click
  exactly on your own sprite (which sits under the camera-follow crosshair and can be fiddly to
  hit with a plain click, though a plain click on your own tile has always worked too).
- **Shield**: `Stats.shield_ac_bonus` (+5, folded into `recalc_ac()`), cleared at the start of the
  caster's next real turn in `player.gd._on_turn_started()`'s `if not came_from_revert:` block.
  **Free action, not a normal turn-costing cast** (direct owner rework — unlike RAW's reaction,
  this version is cast on your own turn, so the tradeoff is it can't be triggered reactively at
  the exact moment an attack lands, but it IS live for the rest of the casting turn itself, e.g.
  right before deliberately provoking an Opportunity Attack): `SpellEffects.cast_leveled_self()`'s
  `"shield"` branch sets the buff/logs/updates fog, then returns early via
  `player._reverted_this_round = true; TurnManager.revert_to_waiting()` instead of falling through
  to the function's normal `_handle_post_attack_turn()` tail — same free-action pattern as
  Battlefield Expert R3's side-step / Berserker's Frenzy. The spell slot is still consumed
  normally (`_consume_slot()` runs before the free-action branch). **Magic Missile interaction**
  (spec'd, not implemented): if an enemy casts Magic Missile at a Shield-protected player, the
  missiles should fail to strike but still consume the caster's own spell slot — no enemy Magic
  Missile caster exists in this codebase yet to exercise this against (same "granted but nothing
  to hook into yet" precedent as Elf's Fey Ancestry), documented on `Spell.description` for
  whenever one does.
- **Mage Armor**: SELF-target, touch range (`range_tiles = 1`), AUTO_HIT — `SpellEffects.
  cast_leveled_self()`'s `"mage_armor"` branch. **Touch buffs don't self-cast on activation** the
  way Shield (range 0) does: `PlayerSpellcasting.begin_cast()`'s SELF branch only instant-casts
  when `spell.range_tiles <= 0`; any SELF spell with `range_tiles > 0` instead arms
  `spell_targeting_active` exactly like an ENEMY/TILE spell — a bare hotkey/ability-bar press
  can't silently burn a slot on a buff the player didn't mean to cast yet. **No ally-buff
  targeting exists** (only the caster's own tile is ever a valid touch target — a future
  ally-targetable touch spell would need `cast_leveled_self()`, or a new resolver, to accept a
  target other than `player`), so `try_cast_at()`'s `SELF` branch doesn't bother validating the
  click position at all: ANY click (or Alt+click, or a same-slot double-press — see below)
  confirms the cast on yourself, short-circuiting before the range/LOS check block entirely.
  Requiring the click to land pixel-perfectly on your own tile (an earlier iteration of this
  logic) was needless friction for a spell that can't target anything else anyway. Three ways to
  confirm the arm-then-cast:
  - **Any LMB click**, anywhere in the game world, while armed.
  - **Alt+click from the Special quick-cast slot** — `cast_direct()` self-casts any SELF-target
    spell immediately regardless of `range_tiles`, bypassing the arm step entirely. **Fixed
    footgun**: `player.gd`'s mouse-release handler used to check `pending == grid_pos` (the
    "clicking where you already stand is a no-op move" guard) *before* the Alt+Special-slot
    dispatch — since Alt+clicking a touch self-buff naturally means clicking your own tile, that
    guard silently ate the cast every time. The Alt+Special-slot check now runs first.
  - **Double-press the same ability-bar/quickbar slot** within `Player.DOUBLE_TAP_WINDOW_SEC`
    (0.4s) — `_use_ability_slot()` tracks `_last_ability_slot_idx`/`_last_ability_slot_press_msec`;
    a second press of the same slot on a SELF-target spell cancels any pending arm state and calls
    `cast_direct()` directly, resolving on yourself with no mouse click needed at all. Only
    SELF-target spells trigger this.

  **Cancelling an armed cast**: besides Esc, an armed spell/scroll cast (`spell_targeting_active`)
  is now also cancelled by (1) **any WASD/arrow movement key press** — `player.gd`'s `_process()`
  movement block cancels it right alongside the pre-existing Throw/Thief-Tools cancels, before
  `_try_move(dir)` runs — and (2) **pressing the SAME ability-bar slot again** for a non-SELF
  spell: `_use_ability_slot()` compares `PlayerSpellcasting.get_armed_spell().spell_id` (by id, not
  Resource identity — `SpellDb.get_spell()` builds a fresh `Spell` instance every call) against the
  freshly-pressed slot's spell id and calls `cancel()` if they match, regardless of the double-tap
  timing window. (A SELF-target spell never reaches this branch — the double-tap-resolves case
  above claims it first.)
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
  (`scripts/ui/CLAUDE.md`), cast with **Alt+click** — a direct, one-motion resolve mirroring
  Shift+Ranged rather than the ability bar's two-step arm-then-click. `PlayerSpellcasting.
  cast_direct(spell_id, clicked)` (`scripts/entities/player_spellcasting.gd`) is the dedicated
  entry point: SELF-target spells (Shield) ignore `clicked` and self-cast immediately (same branch
  `begin_cast()` uses); every other target kind sets `_armed_spell_id` directly and calls the
  existing `try_cast_at()` — reuses 100% of the normal cast's range/LOS/slot-consumption logic,
  no duplicated resolution code. Dispatched from `player.gd`'s mouse-release handler, as an `elif`
  alongside the Shift+Ranged branch (`Input.is_key_pressed(KEY_ALT) and GameState.
  special_slot_spell_id != ""`).
- **Ctrl+click (world)** is a separate, unrelated binding — instant Inspect on whatever's
  clicked (tile/entity/item), the same info RMB Inspect shows. Takes priority over every other
  LMB click mode (movement, attack, spell/tool targeting) and never costs a turn — see
  `PlayerActions.do_inspect()`.
- **Hover indicator over enemies** (`player.gd._update_hover_indicator()`): the small icon shown
  above a moused-over enemy reflects whichever action a click would actually perform, checked in
  the same priority order as the click handler above — Alt-held (Special-slot spell icon, if one
  is assigned) beats Shift-held (equipped ranged weapon icon) beats the default (equipped melee
  weapon icon). **Only shown when the enemy is actually in FOV** — gated on
  `DungeonFloor.is_tile_visible()` for at least one of the enemy's `occupied_tiles()` (not just
  `get_targetable_enemy_at()` finding an entity at the tile, which also succeeds through walls/fog
  since it's the same lookup blind-fire clicks rely on) — otherwise hovering an unseen tile would
  reveal a hidden enemy's exact position via the icon alone. Blind-firing a ranged attack/spell at
  an enemy through a wall or into an unlit tile is still intentionally allowed by the click
  handlers themselves; only the icon's visibility is FOV-gated, not the action. **Icon size is
  normalized, not a flat scale**: a spell icon's source PNG (`res://icons/spells/`) is thousands of
  px across versus melee/ranged weapon art's ~16px tile-sized source, so a flat `Sprite2D.scale`
  would render a spell hover icon far larger on-screen than the weapon one — `scale` is instead
  recomputed per texture as `HOVER_ICON_TARGET_PX / longest_source_side` (same longest-side-uniform
  approach as `DungeonFloor.place_item_on_floor()`, `scripts/world/CLAUDE.md`'s "Floor items"),
  giving every icon kind the same on-screen footprint.
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
- **Magic Missile — BG3-style "seeking dart" targeting, fixed 12-tile range**: `Spell.range_tiles
  = 12` (a plain fixed number now — the earlier `Spell.range_is_fov`-driven "range = live FOV
  radius" mechanic was replaced per direct owner correction; `range_is_fov` itself still exists on
  `Spell` and still works for any future spell that wants it, magic_missile just no longer sets
  it). `Spell.bypasses_los: bool` (`scripts/items/spell.gd`) is the new mechanic: when true,
  `PlayerSpellcasting.try_cast_at()` skips the normal `has_ranged_los()` check entirely and
  requires `DungeonFloor.has_walkable_route_ignoring_chasms(caster_pos, clicked)` instead — the
  target doesn't need to be SEEN (behind a wall corner, through grass, past a closed door all
  still hit), it just needs a route a walking character could physically take to reach it, with
  one deliberate exception: **chasms don't block this route** (`_is_walkable_ignoring_chasm()`
  blocks only WALL/VOID/barrel-blacksmith-shopkeeper props — every other tile type, CHASM
  included, passes — the dart flies over a chasm a real character on foot couldn't cross). 8-
  directional BFS, same shape as the existing click-to-move `find_path()` otherwise, but
  deliberately NOT gated on `_explored` (a spell can blind-cast into unseen fog like any other
  spell/ranged attack in this codebase — only real click-to-move pathing requires
  explored tiles). The Shift/spell-targeting tile-tint preview (`scripts/world/CLAUDE.md`'s "AoE
  targeting preview") also runs this same path check before allowing an enemy to tint red for a
  `bypasses_los` spell — never shows red on an enemy the dart genuinely couldn't reach, even if
  it's within the flat 12-tile range. Out-of-range still rejects with the normal
  "Target out of range" message; failing the path check (in range, but no route) rejects with
  "No path to the target." instead of "No clear line to target."
- **Magic Missile's detailed damage tooltip**: a dedicated `mmdmg:` meta (`darts`, `rolls`
  `|`-joined per-dart totals, `total`, `final`) replaces the generic `dmg:` meta for this spell —
  `TooltipFormatters.fmt_mmdmg_tooltip()` (`scripts/ui/tooltip_formatters.gd`, dispatched in
  `hud.gd._format_tooltip()`) lists each dart's individual 1d4+1 roll before the summed total.
  **Damage-only, deliberately** — "always hits"/"ignores LOS" do NOT belong on a damage-number
  tooltip (per direct owner correction); that context lives on the spell's own ability-bar hover
  tooltip instead (`Spell.description`, `SpellDb._magic_missile()`), which already states both.
- **Magic Missile — 3 independently-targeted darts, not one 3-dart hit on a single target**:
  casting it arms `spell_targeting_active` exactly like any other spell, but instead of resolving
  on the first click it collects exactly **3 dart-target picks**, one per click (repeats freely
  allowed — clicking the same target twice/three times focuses that many darts' damage onto it),
  before the cast actually resolves — `PlayerSpellcasting._begin_multi_target()` /
  `_handle_multi_target_click()` / `_mm_active`/`_mm_targets` (`scripts/entities/
  player_spellcasting.gd`), intercepted before the normal single-click ENEMY dispatch in
  `begin_cast()`/`cast_direct()`/`on_scroll_primed()` (checked via `Spell.effect_id ==
  "magic_missile"`, so the ability-bar cast, the Special-slot Alt+click one-motion cast, AND a
  Scroll of Magic Missile all go through the same multi-target collection). Each click is
  range/path-validated exactly like a normal single-target cast (Chebyshev range +
  `bypasses_los`'s walkable-route check, see above) before being accepted — an invalid click just
  logs why and lets the player try again, it does not cancel the whole cast. **Esc (`cancel()`) at
  any point cancels the entire cast with nothing spent** — the spell slot and the turn are only
  consumed once all 3 picks are in (`SpellEffects.cast_magic_missile()`'s own
  `TurnManager.begin_player_action()`/`_consume_slot()` envelope), same "nothing happens until it
  actually resolves" precedent as every other arm-then-click spell. **RMB undoes the single most
  recent pick** instead of cancelling everything (`PlayerSpellcasting.
  is_collecting_multi_target()`/`undo_last_multi_target_pick()`, checked first in `player.gd`'s
  RMB handler, ahead of Inspect/tool-complete/the normal RMB dispatch) — pops the last entry off
  `_mm_targets` and re-prompts for that many darts again; a no-op if nothing's been picked yet.
  **Valid targets beyond enemies**: a click can also land on a barrel or a (non-hidden) door
  (`PlayerSpellcasting._resolve_multi_target_at()` — `DungeonFloor.has_barrel_at()`/
  `has_door_at()`, checked after `get_targetable_enemy_at()` finds nothing) — neither has an
  HP/AC system yet (see "Enemy D&D stat-block schema" above, which still only covers `Enemy`), so a
  dart aimed at one just visibly streaks in and "shatters harmlessly against it," logged but with
  no mechanical effect — a forward-compatible slot for once destructible props exist, not a no-op
  bug. **Resolution** (`SpellEffects.cast_magic_missile()`, replacing the old single-target
  `cast_leveled_at_enemy()`, which is now dead and was deleted): the 3 picks are grouped by unique
  target (`_mm_target_key()` — an `Enemy`'s instance id, or a prop's kind+position) before
  resolving, so 2 or 3 darts aimed at the same enemy sum into one `take_typed_damage()` call/one
  floater/one log line (still each individually rolled 1d4+1 first, per-dart rolls preserved in the
  `mmdmg:` tooltip) rather than resolving as separate hits. Distinct targets each get their own
  independent damage instance/log line in the same cast.

### More 1st-level spells (Chromatic Orb, Burning Hands, Witch Bolt)

Three more `LEVELED_SPELL_IDS` entries added on top of the original 5-spell pass above — each
introduces one new mechanic not needed by any earlier spell.

- **Chromatic Orb** (Evocation, `effect_id: "chromatic_orb"`, ATTACK_ROLL, ENEMY, 5 tiles): the
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
  to look like a cone rather than a genuine wedge. **Aim is snapped to the nearest of 8 fixed
  compass directions** (`SpellEffects.DIR8`, same convention as Dragonborn's Breath Weapon Line's
  own `_line_tiles()` snap) rather than a continuous freely-rotating angle — direct owner request:
  the cone's orientation should only change when the mouse crosses into a genuinely different one
  of the 8 adjacent tiles, not flicker/reorient continuously as the cursor drifts. `DIR8` is an
  exact 8-entry unit-vector lookup table, NOT `Vector2(cos(snapped), sin(snapped))` — **bugfix**:
  East (angle 0) is the only one of the 8 snapped angles where `cos()`/`sin()` evaluate to exactly
  `(1,0)`; every other direction (multiples of `PI/2`/`PI/4`) picks up ~1e-16 floating-point
  residue in the component that should be exactly 0, which was just barely enough to flip the
  `lateral <= forward*0.5` boundary comparison at the cone's far edge — the cone was missing one
  tile at max range for every direction except aiming due East.
  **Second bugfix (`forward` was Euclidean, not grid, distance)**: `forward` used to be the
  continuous dot product `v.dot(dir_v)` (`dir_v` a unit vector) — a diagonal grid step measures as
  `sqrt(2)` under that projection versus a cardinal step's exact `1`, so at a fixed integer
  `length` (a tile-COUNT range, e.g. `BREATH_CONE_LENGTH = 2`) a diagonally-aimed cone's own grid
  points (e.g. `(2,1)` relative to a SE aim) exceeded `forward > length` well before they were
  actually `length` tiles out — squeezing a diagonal-aimed cone down to a single tile
  (`(1,1)`) while the same-length cardinal aim correctly produced its full 4-tile widening shape.
  `forward` is now `float(maxi(absi(dx), absi(dy)))` — Chebyshev (grid) distance, matching how
  this engine's own diagonal movement already counts a diagonal step as costing exactly 1 tile —
  `v.dot(dir_v)`'s sign is still checked (separately, `<= 0.0` continue) purely to keep the
  "roughly in front of the aim direction" gate, not to measure range. Fixes both the Dragonborn
  Breath Weapon's diagonal Cone aim (`PlayerDragonborn`, see "Dragonborn" below) and Burning
  Hands' diagonal aim identically, since both share this one `cone_tiles()` function.
  called by both the resolver (`_resolve_cone_aoe()`, dispatched from `cast_leveled_at_tile()`) and
  the live preview (`DungeonFloor.show_cone_preview()`, mirroring `show_aoe_preview()`'s pooled-
  Sprite2D convention — see `scripts/world/CLAUDE.md`). Because only the *direction* to the clicked
  tile matters, `PlayerSpellcasting.try_cast_at()` special-cases `spell.shape == "cone"` to skip
  the normal range/LOS gate on the clicked tile entirely (the click can land anywhere, even out of
  range or behind a wall — only its direction from the caster is used). **Never damages the
  caster** (unlike Fireball's sphere) and, matching `_resolve_sphere_aoe()`'s own existing scope,
  doesn't hit a companion either — enemies only. Ignites every `GRASS` tile the cone passes
  through (`DungeonFloor.ignite_grass()`), mirroring Fire Bolt/Thunderclap's flammable-terrain
  side effect.
- **Witch Bolt** (Evocation, `effect_id: "witch_bolt"`, ATTACK_ROLL, ENEMY, 3 tiles, 2d12
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
  `shape_size: 2`, range 6 tiles, **Concentration**, up to 600 turns — 5e RAW's "1 hour", at 6
  seconds/round): the fourth concentration
  spell, `"fog_cloud"`. Unlike Blade Ward/Witch Bolt (a self-buff / a live Enemy reference), the
  cloud is a bare **position + radius** — `GameState.fog_cloud_pos: Vector2i`/
  `fog_cloud_radius: int` (`(-1,-1)` = none active), since it needs to make whoever is standing in
  it Heavily Obscured, player or enemy, not a single caster/target pair. `SpellEffects.
  _resolve_fog_cloud()` (dispatched from `cast_leveled_at_tile()`, intercepting before the generic
  `shape == "sphere"` damage path so it never routes into `_resolve_sphere_aoe()`) sets `stats.
  concentration_spell_id = "fog_cloud"`, `stats.fog_cloud_turns = 600`, `GameState.fog_cloud_pos =
  center`, `fog_cloud_radius = spell.shape_size` — no damage, no save roll.

  **Heavily Obscured / Blinded** (generic conditions, not Fog-Cloud-specific — see "Conditions"
  above): `GameState.is_heavily_obscured(pos) -> bool` (today just `is_in_fog_cloud(pos)` — a
  future obscurement source would extend this one function instead of every caller checking
  multiple zones by hand) grants `GameState.is_blinded(pos) -> bool` to whoever stands there,
  purely positional/symmetric (player or enemy). Three effects, all keyed off `is_blinded()`:
  - **Attacks against a Blinded creature have Advantage / its own attacks have Disadvantage**:
    `PlayerVfx.has_advantage(enemy)` (ADV, backs all player attack-roll sites for free) and a
    `disadv_count`/`has_disadvantage_condition()`-style inline check at every player attack-roll
    site (DISADV) cover the player's half; `Enemy._resolve_attack_roll()`'s `extra_adv`/
    `extra_disadv` params, fed `is_blinded(target.grid_pos)`/`is_blinded(grid_pos)` from
    `_attack_player()`/`_attack_companion()`, cover the enemy's half symmetrically.
  - **Vision collapses to 1 tile while Blinded, ignoring every bonus including darkvision**:
    `GameState.effective_fov_radius(pos) -> int` is the single chokepoint both `DungeonFloor.
    update_fog()` (real fog-of-war) and `get_visible_enemies()` (targeting/Cleave-candidate
    search) call instead of computing the `FOV_RADIUS + fov_radius_bonus + darkvision_bonus + ...`
    formula themselves — returns a flat `1` whenever `is_blinded(pos)`, so a player standing in
    Fog Cloud genuinely can't see or target past an adjacent tile, and the fog-of-war itself
    shrinks to match (not just a combat-roll penalty with the map still fully visible).
  - **NOT implemented** (documented simplification, matching Mind Sliver's "no separate turn-
    expiry timer" precedent): "automatically fails checks that require sight" — there's no single
    concrete mechanic in this codebase that maps onto "a sight check" the way ADV/DISADV on attack
    rolls does, so this clause is still a no-op. "Ends early if a strong wind disperses it" — no
    such spell/ability exists yet to trigger it.
  **Can't be seen into from outside, even at the edge** — heavily obscured tiles block sight like
  a wall for every viewer without `Stats.sees_through_magical_darkness` (not granted by anything
  today — darkvision does NOT bypass this), including enemy AI's own `has_line_of_sight()`; full
  mechanism in `scripts/world/CLAUDE.md`'s "Fog Cloud spell zone" section.
  Duration ticks in `_on_turn_started()` like Blade Ward, but ALSO calls `GameState.
  clear_fog_cloud()` at 0 (unlike Blade Ward/Witch Bolt, which have nothing beyond their own Stats
  field to clear). **Explicitly cleared on floor descent** (`GameState.advance_floor()`) — unlike
  Light (whose lit `Item` reference) or Witch Bolt (whose target `Enemy` reference) naturally
  invalidate themselves when the floor reloads, a bare position has nothing that would otherwise
  stop it from silently blinding whoever stands at those same coordinates on the next floor.
  **Visual**: `DungeonFloor._update_fog_cloud_visual()` (`scripts/world/dungeon_floor.gd`, called
  every `update_fog()`) tints the cloud's tiles with a persistent **dark** overlay (`Color(0.10,
  0.10, 0.13, 0.80)` — deliberately dark, not a light haze, to read as genuinely Heavily Obscured
  rather than cosmetic mist) — pooled `Sprite2D`s + shared 1×1 white texture, same convention as
  the Light glow (see `scripts/world/CLAUDE.md`). Not LOS-filtered (a raw disc, matching
  `is_in_fog_cloud()`'s own check exactly) and does NOT itself union into `_visible_tiles` the way
  Light does — the FOV-shrink effect above happens entirely through `effective_fov_radius()`
  capping the shadowcast radius, not through a separate visibility union.

## Monk class
Stats: DEX=16, WIS=14, CON=12, STR=10 (d8 HD, 8+CON HP). Check proficiencies: STR + DEX. Weapon proficiency: Simple weapons (`proficient_simple_weapons = true`) plus Martial weapons with the Light property only, via `Stats.martial_weapon_restriction = "light"` — `Stats.is_weapon_proficient(item)` is the single check both `EquipRequirements.can_equip_weapon()` (hard-blocks equipping a non-Light Martial weapon) and `CombatMath.weapon_prof_bonus()` (attack-roll proficiency bonus) call, so a Monk equipping e.g. a Handaxe (Martial+Light) works and gets the bonus, while a Greataxe (Martial, not Light) is blocked outright. No armor training (any armor → DISADV on STR/DEX checks/saves + DISADV on attacks; TODO: enforce). Starting abilities (slot 0–1 of ability bar):
- **Unarmored Defense** (passive, ability_id `"unarmored_defense_monk"`): AC = 10 + DEX + WIS while wearing no armor AND wielding no shield (5e RAW: unlike Barbarian's own Unarmored Defense, a shield voids Monk's version entirely rather than stacking with it). Handled in `Stats.recalc_ac(has_armor_equipped, armor_item, has_shield_equipped)` — `GameState.recalculate_stats()` passes `has_shield_equipped` from the `"hand2"` slot's `Item.is_shield`. In practice a Monk can never equip a Shield to begin with (`Stats.proficient_shields` is false for Monk, hard-blocked by `EquipRequirements.can_equip_shield()`), so `has_shield_equipped` exists for correctness/documentation rather than because the case is reachable today.
- **Martial Arts** (passive, ability_id `"martial_arts"`, `PlayerMonk`/`_monk`, `scripts/entities/player_monk.gd`): active whenever `PlayerMonk.martial_arts_active(main_hand)` is true — Monk class, no armor (`GameState.equipment["armor"] == null`), no shield (`hand2` item's `is_shield` false), and Main Hand is unarmed or a Monk weapon (`PlayerMonk.is_monk_weapon()`: Simple, or Martial+Light — exactly `Stats.martial_weapon_restriction`'s own `"light"` definition, see "Weapon proficiency flags" above). Three effects, all gated on that one check:
  - **Dextrous Attacks**: DEX instead of STR for both the attack roll and the damage roll (`monk_ma_active` in `player.gd._bump_attack()`/`resolve_opportunity_attack()`, same override point Finesse weapons use).
  - **Martial Arts Die**: `PlayerMonk.damage_die(main_hand)` returns `Stats.martial_arts_die_sides` (1d6 → 1d8 at lvl 5 → 1d10 at lvl 11 → 1d12 at lvl 17) in place of the weapon's own die whenever it would roll higher — unarmed always uses it (no weapon die to compare against); wielding a Monk weapon compares `martial_arts_die_sides` against the weapon's own `damage_die_max` and keeps whichever is bigger. Damage TYPE still follows the weapon (Piercing for a Dagger, etc.) or Bludgeoning when genuinely unarmed.
  - **Bonus Unarmed Strike**: `PlayerMonk.try_bonus_unarmed_strike(enemy)` — called from both the hit and miss tails of `_bump_attack()`, right alongside `_try_offhand_attack()` — resolves one free additional unarmed attack (full DEX mod on both rolls, `martial_arts_die_sides` damage, Bludgeoning, its own `[color=cyan]Bonus Unarmed Strike:[/color]` log line) after the main swing lands or misses. Deliberately excludes `resolve_opportunity_attack()` (an OA is meant to stay a single self-contained swing, same reasoning Vex/Frenzy/Ironwood-Bark are excluded from OAs) and skips entirely if the dual-wield Off-hand bonus attack (`_try_offhand_attack()`) already fired this swing — a Monk dual-wielding two Light Monk weapons gets one bonus attack, not two.
- **Unarmored Movement** (passive from level 2, no ability-bar entry — same "pure background passive" treatment as Wood Elf's own speed trait): while unarmored and shield-free (`PlayerMonk.unarmored_movement_active()`, the same armor/shield half of the gate Martial Arts uses, factored out into `PlayerMonk._unarmored_and_unshielded()`), extra movement speed scaling by character level — +1/3 at level 2, +1/2 at 6, +2/3 at 10, +5/6 at 14, a full extra move (every move is free) at 18 (`PlayerMonk.unarmored_movement_numerator(level)`, a numerator out of a fixed denominator of 6). Reuses the exact same Bresenham-style duty-cycle machinery as Longstrider's own +1/3 speed and Wood Elf's +1/6 (`Player._consume_duty_cycle()`/`CombatMath.tick_duty_cycle()`, see "Movement speed scaling" above) — wired into `_try_move()`'s free-step `elif` chain as `_monk_um_free_step`, same `_try_move()`-only scope limitation (not `_execute_queued_path()`) and same no-live-enemy skip as Longstrider/Wood Elf.

**Monk's Focus** (D&D 2024's rename of "Ki", `Stats.monk_focus_points`/`monk_focus_points_max` —
the max scales 1:1 with `character_level`, granted starting level 2): regains to max on **both** a
completed short AND long rest (`GameState._on_short_rest_completed()`/`long_rest()`) — the one
per-rest resource in this codebase that isn't long-rest-only. Spent via
`GameState.spend_monk_focus(amount) -> bool` (same `invincible`-skips-consumption convention as
`spend_gold()`). `Stats.monk_save_dc` (`8 + proficiency_bonus + WIS modifier`, the real D&D 2024
formula) exists for forward compatibility only — none of the three level-2 features below actually
roll against it. Four abilities granted at level 2 (`GameState._grant_monk_focus_abilities()`,
called from `_apply_monk_level_features(level)`'s `2:` case) and living in `player_monk.gd` — the
first three cost 1 Focus Point each, the fourth (Uncanny Metabolism) is Focus-independent:
- **Flurry of Blows** (`"flurry_of_blows"`, `PlayerMonk.activate_flurry_of_blows()`): a free action
  (no turn cost) — requires Martial Arts currently active (same gear/armor/shield gate as the
  Bonus Unarmed Strike it doubles); silently no-ops instead of double-spending Focus if already
  armed. Sets `PlayerMonk.flurry_pending`, consumed by the very next `try_bonus_unarmed_strike()`
  trigger: that single strike resolves TWICE instead of once (a `for` loop, breaking early if the
  first swing kills the target), logging its own `"Flurry of Blows!"` line before the doubled
  strikes. Not serialized (mid-combat transient), captured/restored via
  `PlayerMonk.get_rewind_fields()`/`set_rewind_fields()` (`player.gd`'s `_monk` entry in
  `capture_rewind_state()`/`restore_rewind_state()`).
- **Patient Defense** (`"patient_defense"`, `PlayerMonk.activate_patient_defense()`): only
  activatable while **engaged** (`PlayerMonk.is_engaged()` — adjacent, via `Enemy.min_dist_to()`,
  to a live visible enemy; static, group-looks-up `"dungeon_floor"` so
  `GameState.is_ability_usable()` can call it without a live `Player` reference) — greys out
  otherwise with a red "Not Engaged" tooltip reason (`GameState.ability_unusable_reason()`). A
  **Bonus Action** (D&D 2024 PHB text, corrected from an earlier turn-costing implementation), so
  it's in `GameState.BONUS_ACTION_ABILITY_IDS` and gates/spends `bonus_action_used` exactly like
  Flurry of Blows/Step of the Wind. Two effects, both "until the start of your next turn": sets
  `Stats.dodge_turns = 1` — every enemy attack roll against the player gets DISADV while it's > 0
  (`enemy.gd`'s `_attack_player()` disadv expression) — AND sets
  `GameState.monk_disengage_this_round = true` (Disengage folded into the same activation) so none
  of the player's own movement this round provokes an Opportunity Attack either — a flag separate
  from Wild Heart Eagle form's own `player_evades_opportunity_attacks` (see "Opportunity Attacks"
  section's "Two independent evasion flags"), so this reset can never interrupt an active Eagle
  form. Both tick down/clear together, ticked by `Stats.tick_status()` (`dodge_turns`) and reset in
  `player.gd`'s `_on_turn_started()` (`monk_disengage_this_round`, alongside the other
  once-per-round flags) — so both naturally last through the following enemy round and clear right
  before the player's own next turn. `dodge_turns` is serialized (`Stats.to_dict()`/`from_dict()`,
  same tier as `slowed_turns`/`blade_ward_turns`); `monk_disengage_this_round` is combat-transient
  (GameState-resident, captured/restored by `RewindManager.REWIND_GAMESTATE_FIELDS` like Rage's
  own flags, never serialized to a save).
- **Step of the Wind** (`"step_of_wind"`, `PlayerMonk.activate_step_of_wind()`/
  `resolve_step_of_wind()`/`cancel_step_of_wind()`): a free 1-tile dash, **directly modeled on
  Orc's Adrenaline Rush** (`player_orc.gd`'s `dash_mode_active`/`resolve_dash()` — same
  arm-then-click-or-WASD-direction pattern, same 4 wiring points in `player.gd`: the range/target
  preview, LMB tile-click resolve, WASD-direction resolve, and Esc-cancel) but Focus-gated instead
  of a per-rest counter, no temp HP grant, and limited to **once per turn**
  (`GameState.step_of_wind_used_this_turn`, reset in `player.gd`'s `_on_turn_started()` alongside
  Grip of the Forest/Halfling Nimbleness's own once-per-turn flags — same precedent, so
  `is_ability_usable()` can read it without a `Player` reference). Also a **Bonus Action** (D&D
  2024 PHB text): on activation (same moment the Focus Point and Bonus Action are spent, not on a
  successful dash landing) also sets `GameState.monk_disengage_this_round = true` — same
  Disengage-for-the-round flag Patient Defense uses above, so it's not just the dash tile itself
  that's protected, ANY of the player's movement for the rest of the round is. The Focus Point is
  spent on arm, not on a successful landing (matches Adrenaline Rush's own convention) — a
  cancelled/out-of-range/blocked attempt doesn't refund it, but also doesn't burn the once-per-turn
  flag (only a genuinely completed dash does); the Disengage flag, however, is already granted the
  instant the ability arms, same as the Bonus Action spend it's bundled with.
- **Uncanny Metabolism** (`"uncanny_metabolism"`, `PlayerMonk.activate_uncanny_metabolism()`): a
  free action, 1/long rest (`Stats.uncanny_metabolism_used`, reset in `GameState.long_rest()`) —
  does NOT spend a Focus Point itself (unlike the three above). Rolls
  `Stats.martial_arts_die_sides + character_level` and heals that many HP via `GameState.heal()`
  (so Bruiser R1's +1d4-while-Bloodied bonus applies for free, named as its own bonus source in
  the `heal:` tooltip alongside "Monk Level"), and separately sets
  `player.stats.monk_focus_points = player.stats.monk_focus_points_max` — a full refresh to max,
  not just adding the rolled amount (direct owner correction to an earlier draft that added the
  roll to the current pool instead).

The first three abilities keep `Ability.uses_max == 0` (the free-base-ability convention, same as
Rage/Hunter's Mark) since the shared Focus pool, not a per-ability use count, is what actually
gates them — `hud.gd`'s ability-bar use-count badge shows the live `monk_focus_points`/
`monk_focus_points_max` count on their slots instead of a normal `X/Y` per-ability counter (same
"read a Stats field directly, checked before the generic `uses_max == 0` branch" pattern Hunter's
Mark/Hellish Rebuke/lineage spells already use — see `scripts/ui/CLAUDE.md`'s "Ability bar
greying"). Uncanny Metabolism's own badge instead shows a flat `X/1` off `Stats.
uncanny_metabolism_used`, the same shape every other 1/long-rest ability-bar bool uses.

**Deflect Attacks** (passive from level 3, ability_id `"deflect_attacks"` — granted an ability-bar
entry purely for discoverability, same "clicking it just logs a passive-reminder line" treatment
as Unarmored Defense/Martial Arts, no player activation): the first time each turn the player
takes Slashing/Piercing/Bludgeoning damage, automatically reduces it by `1d10 + DEX modifier +
character_level` — implemented directly in `GameState.take_damage_raw()`, right after the Stone
Giant ancestry block (same "roll at the moment damage actually lands, not when some toggle was
armed" shape — there's no toggle here at all, it's unconditional once the level/class gate is
met). `GameState.deflect_attacks_used_this_turn` is the once-per-turn gate, reset in `player.gd`'s
`_on_turn_started()` alongside Grip of the Forest/Halfling Nimbleness/Step of the Wind's own
once-per-turn flags (and captured in `RewindManager.REWIND_GAMESTATE_FIELDS`). Since it hooks
`take_damage_raw()` directly, it only ever fires on the same damage paths Rage's own 50% physical
DR does — **not** on trap damage, which `DungeonFloor._apply_trap_damage()` applies straight to
`Stats.take_damage()`, bypassing `take_damage_raw()` entirely (a pre-existing, documented gap
shared with Rage DR, not something this feature changes). **Deferred-log shape, mirroring Stone's
Endurance**: `take_damage_raw()` can't log the "reduces the damage by N" line itself (it runs
INSIDE whatever attack resolver is still building its own "X hits you for N dmg" line), so the
message is stashed in `GameState._pending_deflect_attacks_log` and only printed by
`GameState.flush_deflect_attacks_log()` — every `take_damage_raw()` caller that builds its own hit
line calls this immediately after logging it, the exact same call sites as
`flush_stone_endurance_log()` (`enemy.gd._attack_player()`, `player_berserker.gd`'s two Frenzy
self-damage branches, `spell_effects.gd`'s Fireball self-catch, `dungeon_floor.gd`'s
standing-in-fire tick, and `player.gd`'s status-tick block — harmless no-ops at the non-physical-
damage sites, since `is_physical` already gates whether anything was ever stashed to flush).
Hoverable roll breakdown via a `[url=deflect:die=,dex=,lvl=,total=]` tag
(`TooltipFormatters.fmt_deflect_tooltip()`, `hud.gd`'s `_format_tooltip()` dispatch), same pattern
as Stone's Endurance's own `stonedr:` tag.

**Slow Fall** (level 4, ability_id `"slow_fall"`) — **PLACEHOLDER ONLY, per direct owner request**:
grants an ability-bar entry (`is_passive = true`, click just logs "isn't implemented yet") so the
level-up reads as a real feature, but the mechanic itself does nothing. This game has no
fall-damage system anywhere to hook into — a chasm removes/kills an entity outright
(`scripts/world/CLAUDE.md`'s forced-movement/Push-mastery chasm handling), it never rolls damage —
so there's currently nothing for "reduce fall damage" to reduce. Revisit if/when a real
fall-damage mechanic is ever added; until then this is intentionally inert, same "the resource/slot
exists, nothing consumes it yet" shape as Tier 3/4 talent scaffolding
(`scripts/autoloads/CLAUDE.md`'s "Tier scaffolding" section).

**Extra Attack** (level 5+, ability_id `"extra_attack"`, passive/no player activation — click just
logs a reminder like Martial Arts): the first primary melee attack of a real player turn — the
single chokepoint every `_bump_attack()` call (hit AND miss branch) funnels through,
`player.gd._handle_post_attack_turn()` — grants a second attack instead of ending the turn.
Mechanism: `GameState.monk_extra_attack_used_this_turn` (once-per-real-turn gate, reset in
`_on_turn_started()`'s per-round block) decides whether to grant; on grant,
`GameState.monk_extra_attack_pending = true` and `_reverted_this_round = true` is set BEFORE
`TurnManager.revert_to_waiting()` (same "free action, enemies don't get a round" primitive
Adrenaline Rush/Step of the Wind/Battlefield Expert's free side-step all reuse — critically, setting
`_reverted_this_round` first means `_on_turn_started()`'s reset block is skipped for this firing,
so `monk_extra_attack_used_this_turn` does NOT get cleared before the second attack, which would
otherwise let the window re-grant itself forever). Landing the second attack (`_handle_post_attack_turn()`
seeing `monk_extra_attack_pending == true`) clears the flag and ends the turn normally via
`TurnManager.on_player_action_complete()`. **While the window is open, nothing but that second
attack or forfeiting can happen** (5e RAW: Extra Attack grants more attacks, never more movement) —
three separate guards, all logging the same "attack again, or wait to end your turn." line:
`_try_move()` (placed right after the enemy-bump branch, which already returned — so a bump INTO
an adjacent enemy is never blocked, only a genuine empty-tile move is), the LMB mouse-click handler
(only an already-adjacent, targetable enemy with no Shift/Alt modifier held resolves — an empty
tile, a distant enemy that would need chasing, or a ranged/spell modifier are all refused), and
`_use_quickbar_slot()` (blocks every item/ability activation outright; `GameState.is_ability_usable()`
also unconditionally greys every ability-bar slot while pending, for the matching visual). **Wait
(Space/./Numpad5) forfeits the window** — `PlayerActions.wait_action()` checks
`monk_extra_attack_pending` first and, if set, clears it and logs "Extra Attack forfeited."
instead of the normal "You skipped a turn." line, then ends the turn as usual. Both
`monk_extra_attack_pending`/`monk_extra_attack_used_this_turn` are captured in
`RewindManager.REWIND_GAMESTATE_FIELDS`. **Known gap, not fixed by this feature**: a Monk's Bonus
Unarmed Strike (Martial Arts, level 2+) has no once-per-turn cap of its own, so if Extra Attack's
second swing also triggers it, the player nets TWO Bonus Unarmed Strikes that turn — real 5e 2024
text grants exactly one Bonus Unarmed Strike per Attack action regardless of how many attacks
Extra Attack packs into it, so this is a minor homebrew-favorable divergence, not a crash; add a
`monk_bonus_strike_used_this_turn`-style gate to `PlayerMonk.try_bonus_unarmed_strike()` if this
needs tightening later. **No Extra Attack precedent exists elsewhere in this codebase** (Barbarian/
Ranger do not have it) — despite root `CLAUDE.md`'s Controls line mentioning "wait... also forfeits
Extra Attack" (written for a Monk that gains it, this section), an unrelated abandoned worktree
(`action-economy`) explored a much larger token-pool action-economy rewrite that was never merged;
this implementation is a self-contained, narrowly-scoped addition to the existing turn/phase model
instead, not a reuse of that worktree's code.

**Monk level-up features** (applied in `GameState._apply_monk_level_features(level)`, called alongside `_apply_barbarian_level_features()` from `gain_exp()`):
- **Level 2 — Monk's Focus + Unarmored Movement unlock**: `_grant_monk_focus_abilities()` adds
  Flurry of Blows/Patient Defense/Step of the Wind/Uncanny Metabolism to the ability bar; Unarmored Movement needs no
  explicit hook (`PlayerMonk.unarmored_movement_numerator()` reads `character_level` directly, so
  it just starts returning non-zero once level 2 is reached). `gain_exp()` also grants the extra
  Focus Point immediately on any level-up crossing a Focus-max threshold (every level, since
  `monk_focus_points_max` scales 1:1), same "on the triggering level-up, not only after the next
  rest" treatment `rage_uses_remaining` already gets.
- **Level 3 — Deflect Attacks unlocks**: grants the `"deflect_attacks"` ability-bar entry; the
  reduction math itself needs no explicit hook (`take_damage_raw()` reads `character_level >= 3`
  directly).
- **Level 4 — DEX +2 + Slow Fall (placeholder)**: `player_stats.dexterity += 2`,
  `recalculate_stats()` applied; grants the inert `"slow_fall"` ability-bar entry, see above.
- **Level 5 — Extra Attack + Martial Arts die upgrade**: grants the `"extra_attack"` ability-bar
  entry (mechanism above); also the first of the 5/11/17 die-upgrade thresholds.
- **Levels 11/17 — Martial Arts die upgrade**: updates `martial_arts` ability description; die is auto-computed by `Stats.martial_arts_die_sides`.
- **Levels 6/10/14/18 — Unarmored Movement scaling**: no explicit hook needed, same reasoning as level 2 above.

## Fighter class

No premade hero uses Fighter, so unlike every other real class `Stats.apply_class_defaults()`'s
`FIGHTER` branch sets **no ability-score baseline at all** — `Stats`'s own Resource field defaults
(10 across the board) are a safe placeholder for the brief window before the Custom path's point
buy screen sets real numbers, matching the "just fine, nothing ever reads it" reasoning
`markdowns/` classes don't need either. Check proficiencies: STR + CON. Weapon proficiency: Simple
+ Martial (full, no `martial_weapon_restriction` carve-out like Monk/Rogue). Armor: Light + Medium
+ **Heavy** + Shield (the only real playable class with Heavy armor training). `Stats.mastery_cap()`:
3 at level 1, 4 at level 4, 5 at level 10, 6 at level 16 (Fighter is the other Weapon-Mastery class alongside
Barbarian/Ranger — its own schedule, not shared with either). d10 HD (`GameState.hit_die_sides()`).
Starting gear (`GameState._give_fighter_starting_items()`): Spear (Simple, Versatile 1d6/1d8,
Piercing, `weapon_mastery="Sap"`, also Thrown) in Main Hand, Shield in Off-hand, Chain Shirt
(Medium, no STR requirement) in the Armor slot — a build-agnostic "sword and board" default that
works whether the eventual point-buy/Fighting Style pick leans STR or DEX.

**Fighting Style** (level 1, ability_id `"fighting_style"` — a passive, ability-bar-entry-purely-
for-the-tooltip like Barbarian's Unarmored Defense; click just logs the current pick):
`Stats.fighting_style: String` (`""` = none yet), one of `Stats.ALL_FIGHTING_STYLES` (10 ids —
`Stats.FIGHTING_STYLE_NAMES`/`FIGHTING_STYLE_DESCRIPTIONS` hold the display text). Picked via
`scripts/ui/fighting_style_picker.gd` (row-list layout, no icon art — modeled on
`attunement_picker.gd`'s shape rather than the spell pickers' icon-tile-grid, since there's nothing
to show an icon for). **Mandatory at level 1**: spawned in `character_creation_mode = true`
(no Esc) right after `mastery_picker.gd`'s own Learn-mode "pick 3 masteries" round finishes for a
Fighter (`_finish_learn()`'s new branch, same "route onward instead of just closing" shape Ranger's
own cantrip pick uses) — its own pick calls `GameState.snapshot_character_creation()` itself, since
it's now the true last step of onboarding for this class. **Reselectable on every level-up**
(`hud.gd._on_player_leveled_up()`, `level > 1` — a direct owner house rule, real 5e RAW does NOT
allow freely swapping Fighting Style outside specific class features/feats): spawns the same picker
in reselect mode (`character_creation_mode = false`, default), which has a "Keep Current" button
and accepts Esc — purely optional, unlike the level-1 pick. Both modes reuse
`GameState.mastery_picker_open` as their input-block flag (same no-dedicated-flag precedent as
`high_elf_cantrip_swap.gd`/`attunement_picker.gd`) and call `GameState.set_fighting_style(id)` (sets
`Stats.fighting_style`, re-runs `recalculate_stats()` so a swap into/out of Defense updates AC
immediately, logs the change). Serialized (`Stats.to_dict()`/`from_dict()`'s `fighting_style` key)
and captured in the character-creation "Try Again" snapshot
(`GameState.snapshot_character_creation()`/`retry_same_character()`, Fighter-only branch).

Per-style mechanism (all gate on `Stats.fighting_style == "<id>"`, all Fighter-only in practice
since no other class can select one):
- **Archery**: `+2` folded directly into `PlayerRanged.ranged_attack()`'s existing aggregate
  `weapon_bonus` local (the same var `weapon.bonus_damage`/`prof` already share on the `wpn=`
  tooltip field — not worth a dedicated tooltip line for one more flat add).
- **Blind Fighting**: blindsight 1 tile, fully implemented on both sides — `GameState.
  blind_fighting_ignores(enemy) -> bool` (`fighting_style == "blind_fighting" and
  enemy.min_dist_to(player_grid_pos) <= 1`, footprint-aware) is the single chokepoint every
  consumer calls, so the ADV/DISADV/Invisibility halves can never drift out of sync:
  - `Enemy.is_hidden_from_player()` returns `false` (ignoring Invisibility) for a qualifying enemy.
  - Every player attack-roll site's `GameState.is_blinded(grid_pos)` DISADV check (`_bump_attack()`/
    `_resolve_cleave_attack()`/`_resolve_offhand_attack()`/`resolve_opportunity_attack()` in
    `player.gd`, `PlayerRanged.ranged_attack()`, `PlayerThrowTool._throw_weapon()`,
    `SpellEffects`' two ATTACK_ROLL cast sites) additionally requires
    `not GameState.blind_fighting_ignores(<target>)` — so attacking a target within 1 tile while
    standing in Fog Cloud/Darkness no longer imposes the usual DISADV.
  - `enemy.gd._attack_player()`'s own `fog_adv` (the ADV an attacker gets for attacking a blinded
    player) is denied the same way (`and not GameState.blind_fighting_ignores(self)`, `self`
    being the attacking `Enemy`) — an adjacent attacker gets no free ADV either.
  Darkvision/truesight-style "see in the dark" (`Stats.darkvision_bonus`/
  `sees_through_magical_darkness`) is a separate, unrelated FOV/exploration mechanic — this is
  purely about the ADV/DISADV a Heavily Obscured zone imposes on a roll.
- **Defense**: `+1` AC, folded into `Stats.recalc_ac()`'s real-body-armor branch only (never the
  unarmored-defense ones) — gated on `armor_item.base_ac > 0`, so it only applies while genuinely
  wearing light/medium/heavy armor, matching the style's own text.
- **Dueling**: `+2` melee damage, computed in `_bump_attack()` and folded into `raw_mods` as its own
  named "Dueling" tooltip source — gated on a one-handed weapon (`not weapon_item_ref.is_two_handed`)
  with no weapon in Off-hand.
- **Great Weapon Fighting**: rerolls (treats as `3`) any `1`/`2` on the raw dice array right after
  `Rng.roll_dice()` in `_bump_attack()`, before `CombatMath.build_damage_instance()` ever sees it —
  so crit doubling/tooltip breakdown both read the already-adjusted values transparently. Gated on
  `weapon_item_ref.is_two_handed` (true for a naturally two-handed weapon OR a Versatile weapon
  currently gripped two-handed via `toggle_versatile_grip()` — both set the same flag).
- **Interception**: `enemy.gd._attack_companion()` (the player's Wild Heart Companion is the only
  real ally this engine has to protect — real 5e text covers any adjacent creature) reduces the
  landed hit by `1d10 + proficiency_bonus`, gated on the player wielding a Shield or a Simple/
  Martial weapon and being Chebyshev-1 adjacent to the Companion.
- **Protection**: same `_attack_companion()` call, gated on the player holding a Shield and being
  adjacent — folds a DISADV source into that one attack roll. Real 5e text extends this to every
  attack against that target for the rest of the turn; scope-limited here to just the triggering
  attack (no "already protected this target this turn" cross-attack tracking exists).
- **Thrown Weapon Fighting**: `+2` damage, added directly into `PlayerThrowTool._throw_weapon()`'s
  `pre_crit` sum (so it doubles on a crit, matching this function's existing "whole sum doubles"
  convention — unlike `_bump_attack()`'s per-source `build_damage_instance()` tooltip breakdown, a
  thrown attack's damage line has no per-source list to fold a named entry into).
- **Two-Weapon Fighting**: `_resolve_offhand_attack()`'s `dmg_mod` keeps the full (not
  `mini(attack_mod, 0)`-clamped) ability modifier whenever this style is active — same override
  point Twin Fang R2 (Ranger) already uses for the identical "keep the full mod on this swing" case.
- **Unarmed Fighting**: `_bump_attack()`'s unarmed damage-die block gets a new branch (checked
  before the generic `stats.base_min_damage`/`max_damage` fallback): `1d6` normally, `1d8` when
  Off-hand is ALSO empty of any weapon/Shield (both hands genuinely empty). Damage type already
  falls out as Bludgeoning via the existing `is_unarmed` branch in `dmg_type`'s own ternary — no
  change needed there. **The "1d4 Bludgeoning to a grappled creature at the start of your turn"
  clause is NOT implemented** — this codebase has no grapple mechanic at all to hook it into.

**Second Wind** (level 1, ability_id `"second_wind"`, D&D 2024 Bonus Action):
`Stats.second_wind_uses_remaining`/`second_wind_uses_max` (2 at level 1, 3 at level 4, 4 at level
10 — Fighter's own schedule, a direct owner house-rule number, not RAW's flat 2) — regains
`1d10 + character_level` HP via `PlayerFighter.activate_second_wind()`
(`scripts/entities/player_fighter.gd`, a new composition child-node with no armed/pending state of
its own, unlike Zealot Strike — the heal resolves immediately on activation). Gated through the
shared Bonus Action economy like every other free-action ability (`"second_wind"` added to
`GameState.BONUS_ACTION_ABILITY_IDS`, see "Bonus Action economy" above) — greys out and shows the
generic "No Bonus Action" reason once `bonus_action_used` is true, on top of its own
`uses_remaining > 0` check (`Ability.has_uses()`'s existing generic gate, since `uses_max` here is
a real charge count, not the `0`/free-base-ability convention Fighting Style uses). Refills to max
on a completed LONG rest ONLY (`GameState.long_rest()` — a direct owner house rule; real 5e 2024
text refills on either a short or long rest) — `GameState._sync_ability_uses()`'s `"second_wind"`
branch keeps the ability-bar badge in sync with `Stats.second_wind_uses_remaining`/`_max` the same
way Rage's own badge does. `gain_exp()` grants the extra use immediately on the triggering
level-up crossing the 4/10 threshold, same "on the level-up, not only after the next rest"
treatment `rage_uses_remaining`/`monk_focus_points` already get. Heal tooltip:
`heal:dice=1,sides=10,con=0,roll=,bonus=,total=` — the level bonus and any Bruiser R1 bonus both
ride the generic `CombatMath.encode_bonus_sources()` mechanism as named sources (same shape Zealot
Strike's own heal tooltip uses), rather than trying to force the level bonus into the `con=` slot.

**Action Surge** (level 2+, ability_id `"action_surge"`, D&D 2024 — no action cost to activate at
all): `Stats.action_surge_uses_remaining`/`action_surge_uses_max` (1 at level 2, 2 at level 17).
`PlayerFighter.activate_action_surge()` (`scripts/entities/player_fighter.gd`) spends a charge and
sets `GameState.action_surge_pending = true` — deliberately does NOT call
`TurnManager.begin_player_action()`/`on_player_action_complete()` at all (same "arm and return, no
turn cost" shape Zealot Strike's own activation uses), and is NOT gated by the shared Bonus Action
economy (5e RAW: Action Surge itself costs no action to use, unlike Second Wind above). **Grants
one additional non-magical action** (a move or an attack — melee/ranged/thrown, NOT a spell cast),
consumed at the two chokepoints every such action already funnels through:
- `Player._handle_post_attack_turn()` — the shared tail every melee/ranged/thrown attack AND every
  spell cast calls (`spell_effects.gd`'s ~11 call sites all pass `is_spell = true`; every attack
  call site keeps the default `is_spell = false`). Its own check,
  `if not is_spell and GameState.action_surge_pending:`, reverts to waiting (no enemy round)
  instead of ending the turn — placed AFTER Monk's Extra Attack checks in the same function (the
  two can never both apply to one character, since Extra Attack is Monk-only and Action Surge is
  Fighter-only, but the ordering keeps the function's own "which free-continuation mechanic fires"
  logic linear). **A spell cast does NOT consume or extend the window** — it just falls through to
  the normal `TurnManager.on_player_action_complete()` below, ending the turn exactly as if Action
  Surge had never been activated; if the player still has the charge conceptually "unused" at that
  point, it's simply wasted (spent on activation, not refunded) — matching the direct owner's
  "spell action still ends your turn" requirement.
- `Player._try_move()`'s own tail — a NEW `elif GameState.action_surge_pending:` branch in the
  same free-step chain as Longstrider/Wood Elf/Monk's Unarmored Movement (reached only for a
  genuine move; a bump-attack into an adjacent enemy already returned earlier in the function,
  via `_bump_attack()` → `_handle_post_attack_turn()` above) — consumes the flag and
  `revert_to_waiting()`s the same way. **Scope limitation, matching every other free-move
  mechanic's own documented gap**: only `_try_move()` (WASD), not `_execute_queued_path()`
  (click-to-move/chase) — a chase that ends in an attack still resolves through
  `_handle_post_attack_turn()` normally (fully covered), only a chase that ends in pure walking
  isn't.
Refills on EITHER a completed short or long rest (`GameState.long_rest()`/
`_on_short_rest_completed()`, same "short OR long" shape as Monk's Focus — unlike Second Wind's
long-rest-only refill). `gain_exp()` grants the extra use immediately at level 17, and updates the
ability's own `uses_max`/description text, same "on the level-up, not only after the next rest"
treatment every other scaling resource gets. **Left unconsumed by end of turn** (activated, then
spent on an item/ability/Wait instead of a qualifying move/attack) **simply lapses with no
refund** at the start of the player's next real turn (`player.gd`'s `_on_turn_started()`, alongside
the other once-per-turn flags) — matches 5e's own "unused extra action just evaporates" rule.
`GameState.action_surge_pending` is captured in `RewindManager.REWIND_GAMESTATE_FIELDS`.

**Fighter level-up features** (applied in `GameState._apply_fighter_level_features(level)`, called
alongside `_apply_monk_level_features()` from `gain_exp()`):
- **Level 2 — Action Surge unlocks**: grants the `"action_surge"` ability-bar entry, 1 use.
- **Level 17 — Action Surge's 2nd use**: updates the ability's own `uses_max`/description text and
  grants the extra use immediately (same "on the level-up, not only after the next rest" treatment
  every other scaling resource gets).

## Hybrid class

The one class that runs OFF the D&D spell/rest model - a testbed for a cooldown + nova-resource
economy (`docs/architecture/hybrid-class-design.md`, which has the full rationale and the
ability-authoring template). `Stats.CharacterClass.HYBRID` (enum value 12), `CLASS_ROLE` =
`"MARTIAL"` (so nothing grants it a `caster`). Selectable on the Custom path only
(`class_select.gd`'s `CLASS_DATA`, `"cls": 12`); no premade hero. d10 HD, INT 16 / DEX 14 / CON
14, DEX+INT check prof, Simple weapons + Light armor. Starting gear
(`GameState._give_hybrid_starting_items()`): Dagger + Leather Armor. **Placeholder art** - the
`sprites/characters/classes/Hybrid/` folder is a copy of the Wizard set (`player.gd
._setup_animations()` maps HYBRID → `"Hybrid"` and adds it to `has_real_hit_art`).

**Cooldown model** (`Ability.cooldown_max` / `cooldown_remaining` / `essence_cost`, new
`@export`s on `scripts/items/ability.gd`): an ability is COOLDOWN xor ESSENCE xor passive.
`cooldown_remaining` ticks down once per real turn in `player.gd._on_turn_started()`'s
`if not came_from_revert:` block; `GameState.is_ability_usable()` / `ability_unusable_reason()`
gained a generic gate (`"CD N"` / `"No Essence"`) checked right after `_bonus_action_blocks()`.
Set on a confirmed resolution (`PlayerHybrid._pay()`), skipped while `GameState.invincible`.
Cleared on a long rest. Not serialized (mid-floor transient); `RewindManager`'s existing
`_dup_ability_array()` deep-dup already snapshots the fields, no rewind change needed.

**Essence** (`Stats.hybrid_essence` / `hybrid_essence_max` - 2/3/4 at levels 1/6/12, serialized):
+1 per floor descent (`GameState.advance_floor()` → `grant_hybrid_essence(1)`), full refill on a
long rest, spent via `GameState.spend_hybrid_essence()` (same invincible-skips convention as
`spend_monk_focus()`). **Not** granted for landing surface combos (owner decision). HUD: a
`◆`/`◇` pip row on `$StatsPanel` (`hud.gd._update_essence_indicator()`), Hybrid-only.
`Stats.hybrid_power_dc` = `8 + prof + INT mod`, `hybrid_attack_bonus` = `prof + INT mod` (computed
live) - and since `SpellEffects._attack_bonus(stats)` / `_save_dc(stats)` already fall back to
exactly that for a null caster, `HybridEffects` reuses those helpers directly.

**Surface reactions** (`docs/architecture/hybrid-class-design.md` §3, Phase 1 only): reuses the
existing fire/water/grass sim + two new lightweight element tags on BOTH `Stats` and `Enemy`
(mirrored, ticked in `tick_status()` / `decide_turn()`):
- **`wet_turns`** - set by ending a move on a WATER tile (`Enemy._move_step()`) or by Tide. A wet
  target takes ×2 Lightning and ×0.5 Fire (`Enemy.take_typed_damage()`, folded into `mul` before
  the resist clamp), and can't burn.
- **`shocked_turns`** - shaves one movement step, reusing the `slowed_turns` step-budget path
  (`Enemy.decide_turn()` ORs it into `_slowed_this_turn`).
`Enemy.apply_status()` gained `"wet"` / `"shocked"` cases. `DungeonFloor.douse_tile(pos)` puts
out one burning-grass tile without trampling it (Tide).

**Abilities** are data in `HybridAbilityDb.DEFS` (`scripts/items/hybrid_ability_db.gd`, static
factory, no `.tres` - same as `SpellDb`), resolved by `HybridEffects` (`scripts/entities/
hybrid_effects.gd`, static, owns its own `TurnManager.begin_player_action()` …
`player._handle_post_attack_turn()` envelope like `SpellEffects`). Targeting / arming lives in
`PlayerHybrid` (`scripts/entities/player_hybrid.gd`, `_hybrid` composition child on `Player`,
same pattern as `PlayerOrc`): `player.gd._use_ability_slot()`'s `_:` arm routes any
`HybridAbilityDb.is_hybrid_ability(id)` to `_hybrid.activate(ab)`; the mouse-release handler and
the WASD handler each got a `_hybrid.is_targeting()` / `_hybrid.dash_id` branch next to Orc's
dash; Esc and the move-cancel sweep call `_hybrid.cancel()`. Rewind fields
(`targeting_id` / `dash_id`) wired into `Player.capture_rewind_state()` like `_orc`.

**No growth picker yet** - `GameState._grant_hybrid_abilities_for_level()` auto-grants every
ability whose `min_level` the character has reached (called from `_give_hybrid_starting_items()`,
`gain_exp()`'s level-up block, and `from_dict()` - abilities are derived from class+level, never
serialized). 5 seed abilities shipped (Spark / Tide / Grounded / Arc / Emberstep) - the owner
iterates the kit by editing `HybridAbilityDb.DEFS`. Simplifications this pass: attack/save rolls
have no ADV/DISADV/tooltip fidelity beyond a plain `dmg:` instance + a bare hit/miss line (no
`sphit:` hover breakdown); electrified spread is a radius-2 check between conductive enemies, not
a real flood-fill; a blocked Emberstep still spends its cooldown.

## Locked classes — base D&D stat blocks only

`Stats.CharacterClass` gained 8 new enum entries — `BARD`, `CLERIC`, `DRUID`, `FIGHTER`,
`PALADIN`, `ROGUE`, `SORCERER`, `WARLOCK` (WARLOCK and, since this pass, FIGHTER have both been
fully implemented — see "Warlock class" above and "Fighter class" below — this section now covers
the remaining 6: Bard/Cleric/Druid/Paladin/Rogue/Sorcerer) — each with a real
`apply_class_defaults()` branch
(ability scores, HP via hit die + CON mod, `check_prof_*` flags, `proficient_simple_weapons`/
`proficient_martial_weapons`, `proficient_shields`, `proficient_light_armor`/`medium`/`heavy`) plus
matching `point_buy_hit_die_base()` and `hp_per_level_breakdown()` entries. **Not selectable or
playable yet** — same "sourced art, no mechanics" status as their locked character-select tiles
(root `CLAUDE.md`'s "Locked-class art"): no `class_select.gd`/`character_select.gd` wiring, no
`give_class_starting_items()` branch, no spellcasting (`caster` stays `null` even for the
FULL_CASTER/HALF_CASTER roles `Stats.CLASS_ROLE` already lists them under), no class-specific
abilities (e.g. Bard's starting instrument tool proficiency isn't implemented). `ROGUE` has a real
5e proficiency gap **left deliberately unfixed**: true Rogue weapon proficiency is Simple + only
the Martial weapons that are Finesse or Light — `Stats.martial_weapon_restriction` (added to fix
this exact gap for `MONK`, see "Monk class" above: `"light"` = Martial-Light-only) only has the
one `"light"` restriction value today, not a `"finesse_or_light"` one, so Rogue still leaves
`proficient_martial_weapons = false` (a conservative default) with the real restriction documented
as a comment at its `apply_class_defaults()` branch — adding a `"finesse_or_light"` case to
`Stats.is_weapon_proficient()`'s match block is now a small, well-precedented fix whenever Rogue
itself gets implemented. Five of the six remaining locked classes (Bard/Cleric/Druid/
Paladin/Sorcerer... Sorcerer actually has no armor/shield at all, see its own branch) have full
Simple-or-Simple+Martial proficiency and need no such carve-out.
Stat-block source (given directly by the project owner,
not derived from 5e SRD text verbatim): `check_prof_*`/weapon-and-armor proficiency columns are
exact; the ability scores themselves are this codebase's own invention, following the existing
classes' established pattern (primary stat 16, a secondary support stat 14, a tertiary 12, two 10s,
one dump stat 8) since only primary-ability/hit-die/proficiency data was specified, not a full
ability array — **FIGHTER is the one exception**: it deliberately has NO hardcoded ability-score
baseline at all (see "Fighter class" below), removed once the class became real, since it has no
premade hero to ever read the pre-point-buy default. `GameState.hit_die_sides()`
(`scripts/autoloads/CLAUDE.md`) got matching explicit entries for `FIGHTER`/`PALADIN` (d10) and
`SORCERER` (d6) — its old default branch already happened to return the right d8 for the rest.
