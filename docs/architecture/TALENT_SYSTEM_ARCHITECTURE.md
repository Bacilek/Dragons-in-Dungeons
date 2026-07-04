# Talent System Architecture

**Status of this document:** architectural spec written 2026-07 after a full review of the implemented code. It is the authoritative reference for extending the talent system (boss-gated Tier 2, pending points, subclass selection, Tier 3 multiclass, Tier 4). Read it together with `scripts/entities/CLAUDE.md` (per-talent mechanics) and `scripts/autoloads/CLAUDE.md` (GameState state fields).

---

## 1. What already exists (do NOT rebuild)

A working talent system is **already implemented and shipped**. All of the following exist and function today:

- `Talent` resource (`scripts/items/talent.gd`): `talent_id`, `talent_name`, `description`, `icon_path`, `tier`, `class_id`, `max_rank`, `ranks: Array[Dictionary]` where each rank dict currently carries only `{"description": String}`.
- `Ability` resource (`scripts/items/ability.gd`): `ability_id`, `uses_remaining/uses_max` (0 = infinite), `is_active`, `is_passive` (passives are rejected by `GameState.add_ability()` and never appear in the bar).
- GameState talent state: `tier1_talent_points`, `tier2_talent_points`, computed `talent_points_available`, `talent_investments: Dictionary` (talent_id → rank), `_class_talents: Array[Talent]`, `tier2_unlocked`, `active_tier2_subclass`, `TIER2_SUBCLASSES`.
- Investment flow: `can_invest_talent(id)` → `invest_talent(id)` → `_apply_talent_rank(id, rank)` (a big `match` that creates/updates the Ability and applies one-shot side effects like Danger Sense R3's `strength += 2`) → `talent_invested` signal.
- Rank prerequisites are enforced structurally: `invest_talent()` only ever sets `rank = current + 1`, so ranks cannot be skipped. Keep this.
- Barbarian Tier 1 (Rage / Reckless Attack / Danger Sense) and **all four** Tier 2 subclasses (Berserker, Wild Heart, World Tree, Zealot) are fully implemented, including the hard cases: Rager's free actions (`TurnManager.revert_to_waiting()`), 3-form toggles, Ironwood Bark's snapshot ordering, Zealous Presence's dual resource.
- UI: `talent_picker.gd` (T key), rank-gradient icons via `GameState.talent_icon_path()`, debug subclass cycling arrows in God Mode.

### 1.1 The effect-representation decision (already made — keep it)

Talent **metadata** is data-driven (`Talent` resources, per-rank description dicts). Talent **effects** are code-driven: each effect is implemented at a named chokepoint (`_bump_attack()`, `take_damage_raw()`, `apply_player_status()`, `_on_turn_started()`, etc.) guarded by `GameState.get_talent_rank(id)`.

**Do not build an effect DSL / generic effect interpreter.** The implemented effects range from "flat +2 STR" through "level-scaled % chance a move doesn't end the turn" to "3 mutually exclusive forms with terrain-conditional temp HP". A data language expressive enough for all of these is a scripting language; GDScript already is one. The hybrid model (data for identity/UI, code at chokepoints for behavior) is the correct trade-off for this project size and is the pattern every future talent must follow. The `ranks` dicts MAY carry designer-tunable numbers (dice sizes, thresholds, ranges) that the chokepoint code reads — prefer that over magic numbers in code — but the *logic* stays in code.

### 1.2 Established effect patterns (reuse, never reinvent)

| Pattern | Reference implementation | Notes |
|---|---|---|
| Gated ability (doesn't exist until rank 1) | Reckless Attack in `_apply_talent_rank()` | rank 1 creates the Ability, rank 2+ updates description/icon |
| Per-turn once flag | `_frenzy_triggered_this_turn`, `_divine_fury_triggered_this_turn` | reset in `player.gd._on_turn_started()` only when `not came_from_revert` |
| Per-round cap surviving free actions | `_reverted_this_round` + flag skip block | see `scripts/entities/CLAUDE.md` |
| Free action (turn doesn't end) | `TurnManager.revert_to_waiting()` | **scoped to Rager/Eagle — never generalize** |
| Long-rest-recharged resource | `zealot_blessed_charges`, `zealot_zp_charges` | int on GameState, refilled at the long-rest chokepoint (see REST doc) |
| 3-form toggle | `natural_rager_form` / `natural_sleeper_form` Strings on GameState + description builders | 1 rank = all 3 forms at that rank; form is a String, effects check it at chokepoints |
| Bonus damage stacking | `_bump_attack()` bonus_dmg summation | one `take_damage()` call, named tooltip fields |
| Status negation | `apply_player_status()` interception | the ONLY place statuses are applied |
| Forced movement | `DungeonFloor.force_move_entity()` / `resolve_push()` | |
| Enemy resistance | `Enemy.resist_check(dc, use_con)` vs `8 + mod + prof` | the standard DC convention |

---

## 2. Design brief vs implemented code — CONFLICTS TO RESOLVE WITH THE USER

The design brief (and the five `*-talent-prompt.md` files in the repo root, which are **completed historical task prompts**, all implemented) disagrees with shipped code in these places. Implementation sessions must NOT silently "fix" code to match the brief; these are flagged for the user to arbitrate. Recommended resolutions included.

1. **Tier 2 unlock trigger.** Brief: defeat the "eye boss" (~floor 5), subclass selected at boss kill, points pend until then. Code: `unlock_tier2()` auto-fires at level 7 from `gain_exp()`; subclass defaults to `"Berserker"` and is only switchable via the God-Mode debug arrows; the comment in `_setup_barbarian_tier2_talents()` still says "when Necromancer is defeated" (stale). **This is the main unbuilt work — see §3.** Additional problem: *no "eye boss" enemy exists*. Floor 5 boss is Big Demon, floor 10 is Necromancer. Recommended: gate on "any `is_boss` enemy killed on floor 5" for MVP (reskin to an eye boss later); add a `boss_id` string to `BOSS_POOL` entries so the gate can later name a specific boss.
2. **Rage uses per floor.** Brief: baseline 1 use, Rage talent grants +1 use per rank. Code (and root CLAUDE.md, documented as intentional): uses are **level-scaled** via `Stats.rage_uses_max` (2/3/4/5), the Rage talent only affects countdown-pause and DR. Recommended: keep the implemented level-scaled model — it's documented as a deliberate post-brief design change — and treat the brief's numbers as stale.
3. **Natural Sleeper R2.** Brief: +5 temp HP when *entering* the terrain. Code: 2d6 temp HP at the *start of each turn while standing* on the terrain (replace, not stack). Recommended: keep code (already balanced around turn-start refresh); brief is stale.
4. **Tier level ranges.** Brief: Tier 2 = levels 6–12 (7 points). Code: level 6 grants nothing; Tier 2 points at levels 7–12 (6 points). Recommended: keep code (6 points across 9-cost pool preserves the "can't max everything" tension).
5. **Natural Sleeper activation.** Brief: long rest only. Code: locks form at floor descent AND at short rest completion. When the rest system lands (see REST doc), re-anchor to the real long rest and drop the short-rest lock-in, per brief.

---

## 3. New work A — boss-gated Tier 2, pending points, subclass selection

### 3.1 Pending points (mostly free)

Points are already **tier-locked pools** (`tier1_talent_points` / `tier2_talent_points`), and `can_invest_talent()` checks the tier pool. That means "pending" accumulation almost works already — the only change needed:

- In `gain_exp()`, remove the `if not tier2_unlocked: unlock_tier2()` auto-call. Levels 7–12 keep incrementing `tier2_talent_points` unconditionally.
- In `can_invest_talent()`, add: `if t.tier == 2 and not tier2_unlocked: return false`. (Belt-and-braces: while locked, `_class_talents` contains no tier-2 talents anyway, so `_find_talent` fails — but the explicit guard protects against future ordering changes.)
- Talent picker: when `tier2_talent_points > 0 and not tier2_unlocked`, render the Tier 2 section header in its locked style with a badge: `"N points pending — defeat the floor-5 boss"`.

### 3.2 Boss-kill gate

- Add `boss_id: String` to each `DungeonFloorData.BOSS_POOL` entry (`"big_demon"`, `"necromancer"`).
- Add signal `GameState.boss_defeated(boss_id: String)`. Emit it from the boss-death path (`player.gd._finish_kill()` / wherever `enemy.is_boss` death is handled, next to `drop_boss_loot()`).
- New GameState field `subclass_chosen: bool = false` (reset in `start_new_run()`). On `boss_defeated` with the gating boss id, if `player_stats.character_class` has subclasses and `not subclass_chosen`: open the subclass selection overlay (via a signal the HUD listens to — do not have GameState instantiate UI).
- Constant `TIER2_GATING_BOSS_ID := "big_demon"` on GameState.

### 3.3 Subclass selection overlay (new UI)

New `scripts/ui/subclass_select.gd` — CanvasLayer layer 25, modeled on `talent_picker.gd` conventions (blocks input via a GameState flag; reuse `talent_picker_open` or add `subclass_select_open` and gate player input on it in the same places — grep every `talent_picker_open` check site). Shows the 4 subclasses (name, blurb, the 3 talent names/icons of each pool). On confirm:

```gdscript
GameState.choose_subclass(name: String) -> void:
    active_tier2_subclass = name
    subclass_chosen = true
    unlock_tier2()          # existing function — sets tier2_unlocked, runs _setup_tier2_for_active_subclass()
```

Pending `tier2_talent_points` become spendable instantly (no migration needed — the pool was accumulating all along). Keep `debug_switch_subclass()` untouched; it already clears/rebuilds tier-2 state and its "adding a subclass = one match case" property must be preserved.

**Death-before-boss edge case:** if the player reaches level 13+ without killing the gating boss, Tier 2 points simply stay pending forever this run. Acceptable; no special handling.

### 3.4 What if the player out-levels the boss floor?

Nothing special: gate is the *kill*, not the floor. Killing the floor-5 boss on any later revisit is impossible (floors don't persist), so in practice the player kills it on floor 5 around level 5–7. If the debug Jump-to-Floor skips floor 5, the God-Mode subclass arrows remain the escape hatch.

---

## 4. New work B — generalize the tier scaffolding for Tiers 3 and 4

Do this refactor **before** any Tier 3/4 content. Small, mechanical, high value:

1. Replace the two scalar pools with one dictionary:
   ```gdscript
   var talent_points: Dictionary = {1: 0, 2: 0, 3: 0, 4: 0}   # tier → unspent points
   var talent_points_available: int:
       get:
           var sum: int = 0
           for t: int in talent_points: sum += talent_points[t]
           return sum
   ```
   Update the ~6 touch sites (`start_new_run`, `gain_exp`, `can_invest_talent`, `invest_talent`, picker rendering). Keep the `talent_points_changed(available)` signal signature.
2. Add a single level→tier schedule table (replaces the if-chain in `gain_exp()`):
   ```gdscript
   const TIER_LEVEL_RANGES: Dictionary = {1: [1, 5], 2: [7, 12], 3: [13, 17], 4: [18, 20]}
   func tier_for_level(lv: int) -> int   # returns 0 when the level grants nothing (6, 21+)
   ```
3. Add `func tier_unlocked(tier: int) -> bool`:
   - 1 → always; 2 → `tier2_unlocked`; 3 → `tier3_selected_class != -1` (see below) *and* level ≥ 13; 4 → level ≥ 18. `can_invest_talent()` uses this instead of tier-specific ifs.

### 4.1 Tier 3 (multiclass) — data shape only, content later

- Fields: `tier3_offered_classes: Array[int]` (3 random `Stats.CharacterClass` values ≠ player's class, rolled once at level 13 using the run RNG — see SAVE doc §determinism), `tier3_selected_class: int = -1`.
- At level 13 level-up: roll offers, emit a signal, HUD opens a picker (reuse the subclass_select overlay pattern — it is the same "pick 1 of N pools" UI; build subclass_select with reuse in mind: it takes an Array of {title, blurb, talents} entries, not hardcoded Barbarian data).
- Tier 3 talents are **new, multiclass-friendly variants**, NOT the donor class's actual T1 talents. **Namespace rule (hard invariant):** Tier 3 talent_ids are prefixed `mc_<class>_` (e.g. `mc_monk_flurry`). `talent_investments` is a flat dict keyed by talent_id, and ability_ids equal talent_ids throughout the codebase — an id collision between a Monk player's own talent and a Barbarian's multiclass-Monk talent would silently cross-wire ranks. The prefix makes collision impossible.
- `_setup_tier3_talents(class_id)` mirrors `_setup_tier2_for_active_subclass()`.

### 4.2 Tier 4

Purely level-gated (18–20), own-class/subclass capstones. Needs no new machinery beyond §4's scaffolding: `_setup_tier4_talents()` appends `tier = 4` talents when level 18 is reached (call from `gain_exp()`), keyed on `active_tier2_subclass` if capstones are subclass-specific.

---

## 5. How the UI reads talent state (unchanged contracts)

- Talent picker reads `_class_talents` (add a public accessor `get_class_talents() -> Array[Talent]` instead of touching the underscored field if you touch this area anyway), `get_talent_rank()`, `can_invest_talent()`, per-tier `talent_points`, and now `tier_unlocked()` + pending badges.
- Ability bar: abilities are created/updated exclusively by `_apply_talent_rank()`; HUD re-renders on `ability_bar_changed`. Never poll.
- Tooltips: the `_build_*_description()` functions on GameState regenerate live text (level-scaled numbers). Every new talent needs one; wire it in `_apply_talent_rank()` for both the create and update branches.

---

## 6. Implementation order for a future session

1. §4 scaffolding refactor (points dict, tier schedule, `tier_unlocked`) — touches `game_state.gd`, `talent_picker.gd` only. Verify existing T1/T2 play is unchanged.
2. §3 boss gate + pending UI + `subclass_select.gd` (built generically per §4.1) — touches `game_state.gd`, `dungeon_floor_data.gd`, the boss-death site, `hud.gd`, new UI file.
3. Tier 3/4 content — separate sessions, one pool per session, after content design exists (out of scope now).

**Ability-bar overflow note:** 9 slots; a Barbarian with Rage + 2 gated T1 + 3 T2 actives already uses ~6. Tier 3/4 will overflow. Before Tier 3 content, either promote more talents to `is_passive` (passives never occupy slots) or add a second ability page. Flag to the user when Tier 3 starts; do not decide silently.

**Save/load coupling:** `talent_investments` + points dict + `tier2_unlocked` + `active_tier2_subclass` + `subclass_chosen` + tier-3 fields are the persisted truth; **abilities are derived state** rebuilt by replaying `_apply_talent_rank()` (see SAVE_LOAD_ARCHITECTURE.md §4.3 — this is why `_apply_talent_rank()` must stay idempotent-safe when replayed rank by rank, as `debug_set_talent_rank()` already does).
