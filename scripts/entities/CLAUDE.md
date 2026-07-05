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
`Entity.is_friendly: bool` (default false) — true on `Player` and `Companion`. Added for Zealot's Zealous Presence AOE targeting ("friendly entities in FOV"); reusable by any future ally-scoped system (e.g. Phase 2 multiplayer) without per-class type checks.

## Companion (`companion.gd`)
Extends Entity. Same configure-before-add_child pattern as Enemy (fields set in `configure()`, Stats created in `_ready()`). Key fields: `animal_name`, `armor_class`, `die_count`, `die_sides`. `DungeonFloor.spawn_companion(companion, pos)` sets `_dungeon_floor` and registers via TurnManager. Enemies ignore companions (MVP). On death: sets `GameState.player_companion = null`, unregisters, calls `queue_free()`. `heal_to_max()` called on rest via `GameState._on_short_rest_completed()` and `advance_floor()`. Attack rolls: d20 + `player_stats.proficiency_bonus` vs `enemy.stats.armor_class`.
World pos = `grid_pos * TILE_SIZE + Vector2i(8, 8)`. `TILE_SIZE = 16`.
Z-index: enemies = 1, player = 3.

---

## Adding a new enemy
1. Extend `Entity`, implement `take_turn()` and `_setup_animations()`
2. `TurnManager.register_enemy(self)` in `_ready()` (not in `configure()`)
3. Add entry to `DungeonFloorData.ENEMY_POOL` (`scripts/world/dungeon_floor_data.gd`); add `idle_fmt`/`run_fmt` keys if sprite naming is non-standard
4. If boss: add to `DungeonFloorData.BOSS_POOL`, set `is_boss = true`

---

## Stats (`stats.gd`)
`modifier(score) -> int` = `floor((score - 10) / 2)`.
`apply_class_defaults()` sets all six ability scores and derives `max_hp` and `armor_class`.
`hit_die_sides() -> int`: Barbarian 12, Ranger 10, Monk 8, Wizard 6.
`_hp_per_level()`: class HP gain per level-up.

**Check proficiency flags** (formerly "save_prof"): `check_prof_str/con/dex/int/wis/cha`. Used for traps, lockpick, disarm. No separate saving throw system — all defensive rolls are "checks". Barbarian: STR+CON. Ranger/Monk: STR+DEX. Wizard: INT+WIS.

**Weapon mastery ownership**: `Stats.known_weapon_masteries: Array[String]` (default empty) + `Stats.knows_mastery(name) -> bool`. A weapon's `Item.weapon_mastery` only triggers its effect if the wielder knows that mastery — nothing currently grants entries to this array, so mastery weapons (Greataxe/Cleave, Short Bow/Vex, Handaxe/Vex) have no mastery effect yet. See `scripts/items/CLAUDE.md`'s "Weapon masteries" section for gating call sites.

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

### Advantage / Disadvantage
- **ADV**: attacking a SLEEPING enemy; attacking enemy whose `just_crossed_door == true` (consumed one-shot after check)
- **DISADV**: ranged attack at Chebyshev distance 1 (melee range); melee with a `is_heavy` weapon when STR < 13; ranged with a `is_heavy` weapon when DEX < 13; ranged shot beyond the weapon's normal range but within FOV (`player.gd._ranged_shot_disadvantage()` — every ranged weapon's "long range" is the player's live FOV, not a per-weapon field, see `scripts/items/CLAUDE.md`)
- ADV + DISADV cancel → 1d20
- Yellow "!" floats above enemy on ADV surprise attacks
- Enemy attack log lines (`enemy.gd._attack_player()`) never name the specific talent/ability that granted ADV/DISADV (e.g. no `"(Reckless)"` text) — that context lives only in the `ehit` tooltip roll breakdown, not the log line.

### Bonus damage stacking (Frenzy / Ironwood Bark / Divine Fury, etc.)
When more than one bonus damage source can trigger on the same attack, compute all of them **before** the single `Stats.take_damage()` / `DungeonFloor.show_damage()` call and add them into the base damage total — one number, one floater, one chat log line. Never call `take_damage()`/`show_damage()` once per source — besides producing a confusing multi-part log line, a source gated on `not enemy.stats.is_dead()` can silently fail to trigger if an earlier source already killed the enemy. Each source still gets a **named** field in the `dmg_meta` string (`frenzy=`, `ironwood=`, `divine=`+`divtype=`) purely for the hover tooltip (`TooltipFormatters.fmt_dmg_tooltip()` in `scripts/ui/tooltip_formatters.gd`) — the visible chat log line itself carries no per-source text or amounts (no `(+N Frenzy)`, no God-Mode `[HP/HP]` suffix), only the combined number + damage type. See `player.gd._bump_attack()` / `PlayerRanged.ranged_attack()` (`scripts/entities/player_ranged.gd`) for the reference implementation (Frenzy + Ironwood Bark + Divine Fury summed into `bonus_dmg` before `enemy.stats.take_damage(pre_crit + bonus_dmg)`).

---

## Temp HP
`Stats.temp_hp: int = 0`. Set by Natural Sleeper R2 (2d6 THP per round while starting a turn on the active form's terrain — replaces existing THP, doesn't stack) and by World Tree's Ironwood Bark (`1d6 × rage_bonus_damage` on Rage activation, and again at turn start while Raging if temp HP is 0 — see `player.gd._on_turn_started()`). `take_damage()` absorbs temp HP before regular HP — if fully absorbed, returns 0. Displayed in HUD as a light-blue strip above the HP bar (`_temp_hp_fill` in hud.gd), proportional to `temp_hp / max_hp`.

## Zealous Presence buff (Zealot)
`Stats.zealous_presence_turns: int = 0` — on the shared `Stats` resource so both `Player` and `Companion` can carry it independently. While > 0, grants Advantage on that entity's attack rolls (`_bump_attack()`, `_ranged_attack()`, `Companion._attack_enemy()`) and on the player's DEX checks (trap disarm, lock picking, trap trigger — same call sites Danger Sense already grants Advantage at). Decrements by 1 at the start of **that entity's own turn** (player: `player.gd._on_turn_started()`, real turns only; companion: top of `Companion.take_turn()`) — not the caster's turn, so a buffed ally's duration ticks down on its own schedule. Set by `player.gd._activate_zealous_presence()` on both `stats` (self) and `GameState.player_companion.stats` (if alive) at cast time only — entities that enter FOV after the cast are not retroactively buffed.

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
`Enemy.resist_check(dc: int, use_con: bool = false) -> bool` — rolls `d20 + floor/3 + (con_modifier or str_modifier)` vs `dc`; true = enemy resists. Backing stats: `DungeonFloorData.ENEMY_POOL`/`BOSS_POOL` entries may set optional `"str_mod"`/`"con_mod"` int keys (default 0); `_apply_stats()` converts them to `Stats.strength/constitution` (`10 + mod * 2`). Used by Grip of the Forest's pull (STR) and Branching Strike R3's push (CON), both vs DC `8 + player STR mod + proficiency`; by the Heavy Crossbow's **Push** weapon mastery (CON) vs DC `8 + player DEX mod + proficiency`, resolved via `DungeonFloor.resolve_push()`; and by the Maul's **Topple** weapon mastery (CON) vs DC `8 + player STR mod + proficiency`, resolved by setting `Enemy.prone_turns = 1` directly — see `scripts/world/CLAUDE.md`'s "Forced movement" section and `scripts/items/CLAUDE.md`'s "Weapon masteries".
`Enemy.rooted_turns: int` — Grip of the Forest R2. Checked at the top of `take_turn()`: decrements, skips movement, still attacks if already adjacent.
`Enemy.disadv_next_attack: bool` — Grip of the Forest R3. Consumed in `_attack_player()`'s roll (adds a Disadvantage source, combined with Reckless Attack's Advantage via the same net-ADV/DISADV house rule as the player's own attacks).
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

`resolve_opportunity_attack(enemy: Enemy)` on `player.gd` is modeled on `_resolve_cleave_attack()` — self-contained roll+damage+log, no per-turn talent effects wired in (Reckless/Vex/Frenzy/Divine-Fury/Ironwood-Bark deliberately excluded, since those are per-turn action effects and OA fires on someone else's turn). Reuses the existing `hit:`/`dmg:` tooltip metas (no new formatter needed) with an "Opportunity attack:" log prefix.

## Enemy behavior states
`SLEEPING → STATIONARY → ROAMING → CHASING → SEARCHING`

**SLEEPING**: shows zzz label. Wakes when the selected target is within `WAKE_RADIUS_SQ = 4` (2-tile adjacency).
**ROAMING**: waypoint BFS. `_pick_roam_target()` shuffles `DungeonFloor.get_room_centers()`, picks tile at Chebyshev ≥ 4. Follows `_roam_path: Array[Vector2i]` via `_bfs_to()`. Falls back to `_do_random_step()` if blocked.
**CHASING**: follows the selected target directly. Opens doors (sets `just_crossed_door = true` when stepping onto door tile). Records `_search_heading` (direction toward target) each turn target is visible.
**SEARCHING**: entered when a CHASING enemy reaches `last_known_target_pos` without LOS. Searches for 7 turns in `_search_heading` direction (BFS to `_search_target = last_known_pos + heading * 5`). If the target is spotted → CHASING. After 7 turns → ROAMING. Fields: `_search_heading: Vector2i`, `_search_turns_remaining: int`, `_search_target: Vector2i`, `_search_path: Array[Vector2i]`.

`_roam_path` and `_roam_target` are cleared on state transitions.

### `take_turn()` split: decide vs execute
Per `docs/architecture/enemy_system_architecture.md` §1: `take_turn()` handles only the prone/slowed early-return turns, then calls `_decide_action() -> Dictionary` (reads state, picks a target, advances the FSM, returns an intent like `{"type": "act_toward", "target": ..., "can_see": ...}` — does not await or touch visuals) followed by `await _execute_action(intent)` (all tweens/animation/logging, dispatched on `intent.type`: `attack`/`act_toward`/`roam`/`search`/`wait`). This is the seam every future need (archetypes, boss phases, Phase-2 determinism) hangs off of — see the architecture doc for why.

### Targeting: player + companion
`_decide_action()` no longer hardcodes the player as the target. `_get_target_candidates()` returns every live `is_friendly` entity currently relevant — `[player, GameState.player_companion]`, skipping either if null/dead. `_select_target(candidates)` picks: whichever candidate is already adjacent (Chebyshev 1) wins outright — "first to reach range" — tie-broken by lower current HP if both are adjacent; otherwise the nearer candidate by squared distance. No target-lock field: every turn re-asks "who's closest / who's adjacent" from current positions (see architecture doc §5 for why a lock was rejected). `_act_toward(target: Node)` and `_attack_target(target: Node)` work against either a `Player` or a `Companion` — attack dispatch is `if target is Player: _attack_player(target) elif target is Companion: _attack_companion(target)`. `Companion.take_damage_from_enemy()` is the damage-intake path for the latter (already existed on `Companion`, just never had an enemy-side caller before).

### Attack profiles (ranged enemies)
Pool entries may set `"attack_profile": {"kind": "ranged", "range": N, "projectile": "..."}` (absent = implicit melee, zero change for existing entries). `Enemy._in_attack_range(target)` reads `_type.get("attack_profile", {})`: melee requires Chebyshev == 1; ranged requires Chebyshev ≤ `range` AND `_dungeon_floor.has_ranged_los()`. `_act_toward()` calls `_attack_target()` once in range, otherwise steps toward the target exactly like melee (reuses the same BFS/greedy stepping — approaching until in range, not until adjacent). No caster archetype/enemy-ability machinery exists yet (deliberately not built speculatively — see architecture doc §3/§7 step 6); add it only when a concrete caster enemy needs it. Reference pool entry: `"Goblin Archer"` (`enemy_id: "goblin_archer"`, `DungeonFloorData.ENEMY_POOL`).

### Shared attack resolver
`Enemy._resolve_attack_roll(target_ac: int, attack_bonus_override: int = -1) -> Dictionary` is the one d20-vs-AC roll (Reckless Attack ADV/flat bonus, Grip of the Forest R3 disadvantage, crit-on-nat-20) shared by every enemy attack — melee or ranged, vs player or vs companion. `_attack_player()` and `_attack_companion()` both call it, then handle their own damage application/logging (player routes through `take_damage_raw` for rage DR/poison/Retaliation; companion calls `Companion.take_damage_from_enemy()`, which has no such hooks — those are player-only systems).

### Enemy/boss pool ids
`DungeonFloorData.ENEMY_POOL` entries carry an `"enemy_id"` key, `BOSS_POOL` entries an `"boss_id"` key (e.g. `"orc_warrior"`, `"big_demon"`) — stable machine ids, unlike `display_name` which is UI text and shouldn't be load-bearing. `Enemy.enemy_id: String` is populated from either key in `configure()`. No behavior depends on these yet; they exist so future systems (boss-phase gating, per-enemy talent interactions) can key off a stable id instead of string-matching `display_name`.

---

## Player-specific (`player.gd`)
- `_click_start_screen_pos`: recorded on LMB press; drag > 8 px cancels `_queued_path`
- `_fov_prev_turn` / `_fov_this_turn`: maintained per turn (no longer grant ADV on their own)
- Throw mode entered via `GameState.player_throw_primed` signal; Esc cancels
- All input gated on `TurnManager.phase == WAITING_FOR_INPUT` AND `GameState.short_rest_open == false` AND `GameState.talent_picker_open == false`
- `_vex_adv_target: Enemy` — Vex mastery's per-turn ADV-vs-target flag (Short Bow). Consumed on the next attack attempt (any type) against that enemy; reset in `_on_turn_started()`'s `if not came_from_revert:` block alongside `_frenzy_triggered_this_turn` etc. — survives a `revert_to_waiting()` free-action chain within the same round, clears on a real new round.
- `_finish_kill(enemy: Enemy, dropped_ammo: Item = null)` — optional second param used only by `PlayerRanged.ranged_attack()`'s kill path (the ammo item consumed by the killing shot); rolls a 50% chance to drop it at the corpse's tile via `PlayerAmmo.resolve_ammo_landing()`. Other call sites (`_resolve_cleave_attack`, `try_retaliation`) pass no second arg.
- `_try_offhand_attack(enemy, is_str_weapon)` / `_resolve_offhand_attack(enemy, weapon)` — dual-wielding's bonus Off-hand swing, called from both the hit and miss paths of `_bump_attack()` right after `_try_cleave()`. See `scripts/items/CLAUDE.md`'s "Dual-wielding".

**Split-out modules** (pure refactor, same behavior — GDScript has no partial classes, so these use composition/static-helper patterns instead, same convention as `scripts/ui/*.gd` — see `scripts/ui/CLAUDE.md`'s "Split-out modules"). Each composition child-node holds a `player: Player` back-reference and is instantiated once in `player.gd._ready()`:
- `player_wild_heart.gd` (`PlayerWildHeart`, composition child-node, `extends Node`) — One with Nature (companion summon/dismiss), Natural Rager form cycling, Natural Sleeper form cycling (was `player.gd._activate_one_with_nature()` etc.). `player.gd._use_ability_slot()` routes matching ability_ids to `_wild_heart`.
- `player_zealot.gd` (`PlayerZealot`) — Divine Fury toggle, Blessed Warrior activation + heal resolution, Zealous Presence activation. Owns `blessed_warrior_used_this_turn` (was a player.gd field) — `player.gd._on_turn_started()` resets it via `_zealot.blessed_warrior_used_this_turn = false`.
- `player_ammo.gd` (`PlayerAmmo`) — named-ammo stack lookup/consumption + ammo-landing resolution (floor pickup / chasm / wall-destroyed). Called from `PlayerRanged` and `player.gd._finish_kill()`.
- `player_throw_tool.gd` (`PlayerThrowTool`) — throw-mode and tool-priming activation, bottle fill/creation, and the Thrown-weapon attack (`_throw_weapon()` — see `scripts/items/CLAUDE.md`'s "Thrown weapons"). `_throw_item`/`_tool_item` fields deliberately stay on `Player` itself (read from ~10 other input/movement call sites to cancel on move/Esc) — only the functions moved here, mutating the fields via the `player` back-reference. `do_throw()` branches to `_throw_weapon()` before the generic food/item-throw path whenever the primed item is `Item.Type.WEAPON` with `is_thrown == true`.
- `player_thief_tools.gd` (`PlayerThiefTools`) — disarm trap / lock / pick-lock door actions, plus `show_float_text()` (its only caller). `player.gd._try_move()`'s Thief-Tools-primed bump path and `PlayerActions.interact_action()` call into this.
- `player_vfx.gd` (`PlayerVfx`) — blood trail, hit-flash tween, sword-slash arc, surprise-mark "!" floater, screen shake, the ADV surprise-attack check (`has_advantage()`). `GameState.screen_shake` connects directly to `_vfx.screen_shake`.
- `player_actions.gd` (`PlayerActions`) — short rest / talent picker openers, wait, search/inspect, passive trap perception, floor-item pickup, door/trap interact dispatch. Owns `_last_search_request`/`_traps_in_proximity` (were player.gd fields).
- `combat_math.gd` (`CombatMath`, static-func-only helper, `extends RefCounted`, mirrors `scripts/ui/tooltip_formatters.gd`'s pattern) — the ADV/DISADV d20-roll resolution shared verbatim by melee/cleave/ranged (`roll_with_adv_disadv()`), weapon proficiency bonus (`weapon_prof_bonus()` — was `player.gd._weapon_prof_bonus()`, see "Weapon proficiency flags" above), `melee_reach_bonus()` (Branching Strike's talent-rank reach) and `melee_reach(weapon, rank)` (total melee range = `1 + melee_reach_bonus(rank) + 1 if weapon.is_reach`, additive — used by the chase-to-attack range check and Cleave's target-gathering radius), `divine_fury_flat_bonus()`, `finesse_modifier(str_mod, dex_mod, is_finesse) -> int` (returns `max(str_mod, dex_mod)` when `is_finesse`, else `str_mod` — used for both the attack roll and damage roll in `player.gd._bump_attack()` when `GameState.equipped_weapon.is_finesse`). The bonus-damage STACKING sequence itself (Frenzy/Ironwood/Divine Fury summation) and the full hit/miss/log flow stay in `player.gd._bump_attack()`/`PlayerRanged.ranged_attack()` — see "Bonus damage stacking" above.
- `player_ranged.gd` (`PlayerRanged`) — the full ranged-combat body: range/LOS checks (`is_ranged_target_in_range()`, `ranged_shot_disadvantage()`, `is_in_ranged_range()`), the ranged attack roll (`ranged_attack()`), projectile VFX (`show_projectile()`), and ranged-at-tile (`ranged_attack_tile()`). Mirrors `_bump_attack()`'s ADV/DISADV/crit/Divine-Fury-stacking structure closely — kept as one function per the same "don't split stateful stacking logic" reasoning as melee (see "Bonus damage stacking" above).

---

## Barbarian class
`Stats.proficiency_bonus` is a computed property scaling per D&D 5e (+2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.). `Stats.rage_uses_max` is a computed property scaling by Barbarian level: 2/3/4/5 at levels 1/4/6/12 (cap 5 at 17+). `Stats.rage_bonus_damage` is a computed property: +2 at levels 1–8, +3 at 9–15, +4 at 16+. Level-up grants the extra use immediately when crossing a threshold. **Barbarian unarmored defense**: `Stats.recalc_ac(has_armor_equipped)` — if BARBARIAN and no armor, AC = 10 + DEX + CON.

Tier 1 (levels 1–5): earns 5 talent points, spent across 3 talents (max 3 ranks each = 9 total cost → no run can max all three). Starting equipment given in `GameState.give_class_starting_items()` → `_give_barbarian_starting_items()`:
- **Greataxe** — 1d12 Slashing, `is_two_handed=true`, `is_heavy=true`, `weapon_mastery="Cleave"`, `weapon_category="Martial"`. `damage_die_min/max` on Item define dice; `recalculate_stats()` applies them. Two-handed blocks the ranged slot. Barbarian has both `proficient_simple_weapons` and `proficient_martial_weapons` set, so the Martial tag never shows red for this class.
- **Rage** (ability_id `"rage"`) — in slot 0. Uses and bonus damage scale by level (see computed properties above). 10-turn countdown; no DR at rank 0. Activation is a **free action**. Red sprite tint. Rage ends if heavy armor equipped (`item.is_heavy_armor`). **Rage talent** upgrades (no uses change — uses are level-gated): R1 countdown pauses when player attacked or was hit last turn; R2 25% physical DR (Slashing/Piercing/Bludgeoning only); R3 50% physical DR. DR applied in `take_damage_raw(amount, ignore_rage, damage_type: String)` — status and trap damage pass `""` and bypass DR.

**Barbarian Tier 1 talents** (levels 1–5, no fixed level-up unlocks — all are point-gated):
- **Rage** (`talent_id: "rage"`, max 3): Rage ability already in bar at game start. Talent affects countdown and DR only — uses are level-scaled, not talent-scaled. R1: countdown pauses in active combat. R2: 25% physical DR. R3: 50% physical DR.
- **Reckless Attack** (`talent_id: "reckless_attack"`, max 3): Talent rank 1 = ability added to bar. Toggle (free action), `reckless_attack_active = true`. R1: flat +2 to first STR attack, enemies get flat +2. R2: ADV on first STR attack, enemies get ADV. R3: ADV on all STR attacks (forward-compat for Extra Attack). After first reckless attack of the turn: `reckless_locked_this_turn = true` (blocks further ADV bonus; cleared in `_on_turn_started()`).
- **Danger Sense** (`talent_id: "danger_sense"`, max 3): Talent rank 1 = passive ability added to bar. R1: ADV on DEX checks (traps, lockpick, disarm). R2: for DEX/WIS/CHA checks use `max(base_mod, STR_mod)`. R3: STR+2. Checked via `GameState.get_talent_rank("danger_sense")` in `dungeon_floor.trigger_trap()` and `player._attempt_disarm*()`.

**Barbarian Tier 2 subclasses** (levels 7–12, auto-unlocks at level 7):
- Level-point schedule: levels 1–5 grant Tier 1 points. Level 6 grants nothing. Levels 7–12 grant Tier 2 points; `unlock_tier2()` is called automatically at level 7 if not yet unlocked. Levels 13+ grant nothing until Tier 3.
- `GameState.tier2_unlocked: bool` — set by `unlock_tier2()` (auto at level 7). `_setup_barbarian_tier2_talents()` appends 3 `Talent` objects to `_class_talents`.
- `GameState.TIER2_SUBCLASSES: PackedStringArray` = `["Berserker", "Zealot", "World Tree", "Wild Heart"]`. `active_tier2_subclass: String` tracks current. `debug_switch_subclass(direction)` cycles subclasses and calls `_setup_tier2_for_active_subclass()` — routes to Berserker, Wild Heart, World Tree, or Zealot setup (all four are fully implemented). Arrows ◀ / ▶ appear in the talent picker Tier 2 header when God Mode is active.
- `GameState.apply_player_status(type, turns) -> bool` — single chokepoint for all player status/debuff application. Rager R1 intercepts here with a % chance to negate. Returns false if negated (caller should skip the log). All trap, enemy, terrain, and rotten-meat status calls use this function.

**Wild Heart Tier 2 talents** (**experimental** — balance changes expected; design intentionally deviates from standard talent pattern):
- State vars on GameState: `natural_rager_form: String = "Bear"`, `natural_sleeper_form: String = "Owl"` (preview — chosen form for next rest), `active_sleeper_form: String = "Owl"` (locked in at floor descent), `wild_heart_sleeper_active: bool`, `player_evades_opportunity_attacks: bool`, `player_companion: Variant`, `terrain_ac_bonus: int`.
- **One with Nature** (`talent_id: "one_with_nature"`, max 3): Active ability (1 charge/rest). Summons animal companion at nearest free adjacent tile. R1=Squirrel(AC12,HP10,1d6), R2=Boar(AC14,HP20,2d6), R3=Bear(AC16,HP30,3d6). Re-activate while companion alive = dismiss+resummon. Charge restores on short rest OR floor descent (long rest). Companion entity: `scripts/entities/companion.gd` — see "Companion" section above. `GameState.player_companion` = live reference or null.
- **Natural Rager** (`talent_id: "natural_rager"`, max 3): Toggle ability cycles Bear/Eagle/Wolf; effects active while Raging. Rank 1 grants ALL 3 forms (non-standard: 1 rank = 3 effects). Bear: R1 −25% / R2 −50% magical DR / R3 +50% celestial (Necrotic/Radiant/Psychic) in `take_damage_raw()`. Eagle: R1 50% chance / R2 guaranteed free-move (max **1×/round** via `_eagle_free_move_used` flag — NOT reset on `revert_to_waiting()`, only on real new turns); R3 sets `GameState.player_evades_opportunity_attacks = true` while Raging in Eagle form (`_activate_rage()`/`_end_rage()`; form can't be switched while Raging, so no other write site is needed) — see "Opportunity Attacks" below for what this actually does now. Wolf: ADV on STR attacks when 4+/3+/2+ enemies visible (`_bump_attack()`).
- **Natural Sleeper** (`talent_id: "natural_sleeper"`, max 3): Toggle cycles Owl/Panther/Salmon. **Form locking**: cycling mid-floor updates only `natural_sleeper_form` (preview); the effects use `active_sleeper_form` which locks in at `advance_floor()` (`active_sleeper_form = natural_sleeper_form`). Terrain effects check `active_sleeper_form` in `_try_move()` and `_on_turn_started()`. Owl: chasm passthrough (`_owl_override`). Panther: mud not difficult. Salmon: water not difficult. R2: roll 2d6 THP at the **start of each real turn** while standing in form's terrain — THP replaces (not stacks) existing THP; fires in `_on_turn_started()`. R3: +2 AC (`GameState.terrain_ac_bonus` → `recalculate_stats()`; cleared between floors, updated on every move in `_try_move()`).
- **`_reverted_this_round: bool`** in player.gd — set to `true` before every `revert_to_waiting()` call (Rager move/attack, Eagle). `_on_turn_started()` reads and clears it; when true, skips resetting per-round caps (`_eagle_free_move_used`, `_rager_move_triggered`, `_rager_attack_triggered`, `_frenzy_triggered_this_turn`, `reckless_locked_this_turn`). Ensures all per-round caps survive `revert_to_waiting()` and only reset after enemies actually go.

**Berserker Tier 2 talents** (max 3 ranks each):
- **Rager** (`talent_id: "rager"`, max 3): Passive ability added to bar at rank 1. Chance = `rage_bonus_damage * 10` % (20%/30%/40% at levels 1-8/9-15/16+). All 3 ranks share the same % — rank unlocks new trigger types, not higher chance. R1: negate incoming status/debuff while raging (handled in `apply_player_status()`). R2: after moving, % chance the move didn't cost a turn (Rager free action via `TurnManager.revert_to_waiting()`; `_rager_move_triggered` flag prevents repeat; only fires in `_try_move()` not queued-path). R3: after attacking, same % chance the attack didn't cost a turn (`_rager_attack_triggered` flag, independent of R2; fires in `_handle_post_attack_turn()`). Both flags reset in `_on_turn_started()`. `revert_to_waiting()` is intentionally scoped to Rager — do NOT generalize it as a general action-economy system.
- **Frenzy** (`talent_id: "frenzy"`, max 3): Passive ability added to bar at rank 1. First STR attack each turn while raging deals bonus damage: R1 1d4 × rage_bonus_damage, R2 1d6 ×, R3 1d8 ×. Fires in `_bump_attack()` after the main damage log, before `is_dead()` check. `_frenzy_triggered_this_turn` flag (reset in `_on_turn_started()`). Does NOT go through `take_damage_raw()` — not subject to enemy rage DR. Monk unarmed attacks do not trigger Frenzy (`is_str_weapon` must be true).
- **Retaliation** (`talent_id: "retaliation"`, max 3): Passive ability added to bar at rank 1. When hit by adjacent melee while raging: R1 deal `rage_bonus_damage` back (rage only), R2 deal weapon damage back (NO rage bonus — intentional non-monotonic design), R3 weapon damage + rage_bonus + STR modifier. `try_retaliation(attacker: Enemy)` in player.gd; called from `enemy.gd._attack_player()` after `actual > 0` when `GameState.is_raging`. If Retaliation kills the attacker, calls `_finish_kill()`.

**World Tree Tier 2 talents** (max 3 ranks each):
- **Ironwood Bark** (`talent_id: "ironwood_bark"`, max 3): Passive ability added to bar at rank 1 (no activation — triggers automatically). R1: activating Rage (`player.gd._activate_rage()`) grants `1d6 × rage_bonus_damage` temp HP. R2/R3: evaluated together in `_on_turn_started()`, gated on `not came_from_revert` (real turns only) — **critical evaluation-order rule**: both ranks read the SAME pre-turn `temp_hp` snapshot taken before either mutates it. If snapshot is 0 and rank ≥ 2: refresh temp HP (`1d6 × rage_bonus_damage`, replace not stack). Else if snapshot > 0 and rank ≥ 3: set `_ironwood_bark_bonus_pending = snapshot`. This keeps R2/R3 mutually exclusive each turn — R2's refresh this tick can never also trigger R3 this same tick. `_ironwood_bark_bonus_pending` is consumed once in `_bump_attack()` (added as bonus damage on the next attack, tagged `(+N Ironwood Bark)`, then zeroed) — mirrors the Frenzy bonus-damage pattern exactly.
- **Grip of the Forest** (`talent_id: "grip_of_the_forest"`, max 3): Active ability added to bar at rank 1 — activating (`player.gd._activate_grip_of_the_forest()`) requires `GameState.is_raging` and not `_grip_used_this_turn` (reset in `_on_turn_started()`), then arms `_hook_mode_active` (modeled on throw-mode priming, not a toggle). Next LMB click on an enemy within range (R1=3/R2=4/R3=5 tiles, Chebyshev, `has_ranged_los()`) resolves `_execute_hook()`, which costs the turn like a normal action. Enemy rolls `Enemy.resist_check(dc)` (STR-based) vs `dc = 8 + player STR mod + proficiency` (see "Enemy resist checks" above). On success, pulls the enemy toward the player one tile at a time via `DungeonFloor.force_move_entity()`, stopping once adjacent. R2: sets `enemy.rooted_turns = 1`. R3: sets `enemy.disadv_next_attack = true`.
- **Branching Strike** (`talent_id: "branching_strike"`, max 3): Passive ability added to bar at rank 1. R1/R2: reach bonus for `Item.is_heavy or Item.is_versatile` melee weapons (`player.gd._melee_reach_bonus()` — R1 = +1 tile, R2 = +2 tiles, **replaces** R1, not additive). Applied at the chase-resolution chokepoint in `_execute_queued_path()` (`chase_path.size() <= 1 + _melee_reach_bonus()` instead of the old `== 1`). R3: on a successful hit with a heavy/versatile weapon, pushes the target 1 tile directly away from the player via `force_move_entity()` — target rolls `Enemy.resist_check(dc, true)` (CON-based) vs the same DC convention as Grip of the Forest.
- **Shared forced-movement hook**: `DungeonFloor.force_move_entity()` — see `scripts/world/CLAUDE.md`.

**Zealot Tier 2 talents** (max 3 ranks each):
- **Divine Fury** (`talent_id: "divine_fury"`, max 3): Passive-ish ability added to bar at rank 1 — no activation cost, but clicking it toggles `GameState.zealot_divine_fury_type` between `"Radiant"`/`"Necrotic"` (`player.gd._toggle_divine_fury()`). The toggle only changes the damage type of the bonus, never the amount or trigger — it is always active and cannot be turned off, and unlike other toggles it **persists between turns** (not reset per-turn). Does **not** require Rage — the only Barbarian Tier 2 talent that works independently of Rage state. Bonus fires on the player's first attack each turn (melee via `_bump_attack()` and ranged via `_ranged_attack()` both check the same per-turn flag `_divine_fury_triggered_this_turn`, reset in `_on_turn_started()` on real turns only). R1: `1d6`. R2: `1d6 + floor(level/4)` (replaces R1's formula). R3: `1d6 + floor(level/2)` (replaces R2's). Formula lives in `player.gd._divine_fury_flat_bonus(rank)`.
- **Blessed Warrior** (`talent_id: "blessed_warrior"`, max 3): Active ability added to bar at rank 1. `GameState.zealot_blessed_charges` is a long-rest-recharged resource pool sized by rank via `GameState.BLESSED_WARRIOR_MAX_CHARGES = [0, 2, 4, 6]`. Activating (`player.gd._activate_blessed_warrior()`, max once/turn via `_blessed_warrior_used_this_turn`) consumes 1 charge immediately and sets `GameState.zealot_blessed_heal_queued = true`. The queued heal (1d12, no CON mod) resolves on the player's **next attack this turn regardless of hit or miss** — `player.gd._resolve_blessed_warrior_heal()` is called right before the miss-check in both `_bump_attack()` and `_ranged_attack()`. **Rank-up mid-run**: new pool = new rank's max minus charges already spent this long-rest cycle.
- **Zealous Presence** (`talent_id: "zealous_presence"`, max 3): Active ability added to bar at rank 1. Grants Advantage on **all** attack rolls and checks to the player and all `is_friendly` entities in FOV **at the moment of casting** for R1=1/R2=3/R3=5 turns (`player.gd._activate_zealous_presence()`). **Dual-resource fallback**: `GameState.zealot_zp_charges` (1/long rest) is checked first; only if 0 does activation fall back to consuming 1 charge from `player_stats.rage_uses_remaining`. Priority order is fixed and silent: **ZP charge → Rage charge → unavailable**. See "Zealous Presence buff" section above for the `Stats.zealous_presence_turns` mechanism.
- **Long-rest-recharged resource pattern**: Blessed Warrior's charge pool and Zealous Presence's ZP charge are both simple `int` fields on `GameState` (`zealot_blessed_charges`, `zealot_zp_charges`) refilled in `advance_floor()` (long rest) gated on `get_talent_rank(id) >= 1` — mirrors how `rage_uses_remaining` already refills. No generic "resource" class exists yet; if a third such resource appears, consider extracting a shared helper.

## Monk class
Stats: DEX=16, WIS=14, CON=12, STR=10 (d8 HD, 8+CON HP). Check proficiencies: STR + DEX. Weapon proficiency: intended to be simple weapons + martial weapons with the light property, but `Stats.proficient_simple_weapons`/`proficient_martial_weapons` are not yet set in `apply_class_defaults()` for Monk (TODO — currently only wired up for Barbarian). No armor training (any armor → DISADV on STR/DEX checks/saves + DISADV on attacks; TODO: enforce). Starting abilities (slot 0–1 of ability bar):
- **Unarmored Defense** (passive, ability_id `"unarmored_defense_monk"`): AC = 10 + DEX + WIS while wearing no armor. Handled in `Stats.recalc_ac(has_armor_equipped)`.
- **Martial Arts** (passive, ability_id `"martial_arts"`): Unarmed strikes use DEX for attack AND damage. Damage die = `Stats.martial_arts_die_sides` (1d6 → 1d8 at lvl 5 → 1d10 at lvl 11 → 1d12 at lvl 17). Each unarmed attack ends the turn normally. Both main attack uses `_bump_attack()` with `is_monk_unarmed = true`.

**Monk level-up features** (applied in `GameState._apply_monk_level_features(level)`, called alongside `_apply_barbarian_level_features()` from `gain_exp()`):
- **Level 4 — DEX +2**: `player_stats.dexterity += 2`, `recalculate_stats()` applied.
- **Levels 5/11/17 — Martial Arts die upgrade**: updates `martial_arts` ability description; die is auto-computed by `Stats.martial_arts_die_sides`.
