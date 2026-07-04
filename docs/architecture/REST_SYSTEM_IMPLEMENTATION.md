# Rest System Implementation Spec (hunger removal + ration-based long rest)

**Goal:** delete the hunger/starvation system and replace it with: short rest (2× per long-rest cycle, free, already mostly exists) + long rest (consumes rations, restores everything, available anywhere). This spec is complete enough to implement without further architectural decisions.

**Read first:** `scripts/autoloads/CLAUDE.md` (GameState fields/signals, short rest state), `scripts/ui/CLAUDE.md` (short_rest_panel ordering footgun), `scripts/entities/CLAUDE.md` (Natural Sleeper, long-rest-recharged resources).

---

## 1. The single most important change: a `long_rest()` chokepoint

Today, **"long rest" is implicitly `GameState.advance_floor()`** — it refills rage uses, hit dice, short rests, Zealot charges, locks Natural Sleeper's form, heals the companion. Five separate systems hardcode "floor descent = long rest". This coupling must be broken **once, cleanly**:

```gdscript
# game_state.gd
const LONG_REST_RATION_COST: int = 1   # tune later; keep as a named constant

signal long_rest_completed()

func can_long_rest() -> bool:
    return _count_rations() >= LONG_REST_RATION_COST

func long_rest() -> void:
    # Consumes rations (guard: if not invincible) and restores EVERYTHING. See §4 checklist.
```

`advance_floor()` keeps only floor bookkeeping (increment, `floor_changed`, win check, sleeper terrain-AC reset) and **no longer restores resources**. Descending the stairs is no longer a rest.

> **Gameplay consequence to flag to the user (do not decide silently in code):** removing the free rest-on-descent is a real difficulty increase. If playtesting shows it's too harsh, the knob is `LONG_REST_RATION_COST` and ration drop rates — not re-coupling rest to descent.

Everything long-rest-gated must hook `long_rest()` (or its signal) instead of `advance_floor()`. The checklist in §4 enumerates every current site.

---

## 2. Ration data model

Rations already exist as a starting item (`GameState._give_starting_items()`: `"Ration"`, `Item.Type.FOOD`, `heal_amount = 200` interpreted as hunger, qty 3). Changes:

- Keep `item_name = "Ration"`, `Item.Type.FOOD`, stackable via existing `quantity` (no new Item fields needed).
- `heal_amount` becomes meaningless for rations → set 0. Description: `"Required for a long rest."`
- Rations are **not usable directly**: in `GameState.use_item()`, the FOOD branch currently calls `restore_hunger()`. Replace the FOOD branch: for `"Ration"`, log a hint (`"Rations are consumed by long rests (hold Alt)."`) and consume nothing. Other FOOD items (Cooked Meat, Rotten Meat, Apple, etc.): repurpose `heal_amount` as **direct HP healing** at a reduced value (recommended: `heal_amount / 10`, so Cooked Meat's 150 → 15 HP) — this keeps the cook-rotten-meat-on-fire-trap mechanic meaningful. Rotten Meat keeps its poison. Flag the exact numbers as a balance pass for the user.
- Loot: add Ration to `DungeonFloorData.ITEM_POOL` (weighted so ~1–2 drop per floor) **and mirror in `debug_panel.ALL_ITEMS`** (project invariant). While editing ALL_ITEMS, fix stale hunger text: `"Bottle of Water"` desc says "Restores 60 hunger".
- Helpers on GameState: `_count_rations() -> int` (sum quantities across quickbar+bag by `item_name == "Ration"`), `_consume_rations(n)` (reuse `consume_one()` semantics; skip when `invincible` — project invariant: invincible skips all consumption).

---

## 3. Short rest (mostly exists — small retargeting)

Current behavior (keep): Alt opens `short_rest_panel.gd`; player picks hit dice; rest ticks over multiple turns via `short_rest_active` in `player.gd._on_turn_started()`; interruption panel when enemies enter FOV; heals `dice × hit_die_sides + CON` on completion; decrements `hit_dice` and `short_rests_remaining`.

Changes:
- `short_rests_remaining` / `max_short_rests` (2) now reset **in `long_rest()`**, not in `advance_floor()`.
- `hit_dice` refill (`= character_level`) moves to `long_rest()`.
- `_on_short_rest_completed()` keeps: companion heal, One with Nature charge refresh (design: refreshes on *any* rest). **Remove** the Natural Sleeper form lock-in from short rest (it moves to `long_rest()` only, restoring the original design — flagged as drift in TALENT doc §2.5).

---

## 4. Long rest flow

**Trigger UI:** extend `short_rest_panel.gd` with a second button: `"Long Rest (consumes 1 Ration)"`, disabled with a gray reason label when `not can_long_rest()`. Alt remains the single "rest" key; one panel, two options. (A separate key/panel is not worth the input-surface cost.)

**Duration/interruption:** reuse the exact short-rest mechanism — set `short_rest_active` with `short_rest_turns_remaining` (recommended: 10 turns vs short rest's current value) and a new flag `long_rest_pending: bool` so the completion branch in `player.gd._on_turn_started()` knows to call `GameState.long_rest()` instead of applying the short-rest heal. Interruption by enemies uses the existing `rest_interrupt_panel.gd` path unchanged. Rations are consumed **on completion**, not on start (an interrupted long rest costs nothing — simple and player-friendly; flag if the user prefers pay-up-front).

**`long_rest()` restore checklist — every hook, with its current location to move from:**

| System | Current site (to remove from `advance_floor()`) | Action in `long_rest()` |
|---|---|---|
| HP | — (new) | `current_hp = max_hp`, emit `player_hp_changed` |
| Rage uses | `advance_floor()` | `rage_uses_remaining = rage_uses_max` |
| Hit dice | `advance_floor()` | `hit_dice = character_level` |
| Short rests | `advance_floor()` | `short_rests_remaining = 2` |
| Blessed Warrior | `advance_floor()` | `zealot_blessed_charges = BLESSED_WARRIOR_MAX_CHARGES[rank]` if rank ≥ 1 |
| Zealous Presence | `advance_floor()` | `zealot_zp_charges = 1` if rank ≥ 1 |
| One with Nature charge | `_sync_ability_uses()` (called from advance_floor) | keep — call `_sync_ability_uses()` from `long_rest()` |
| Companion heal | `advance_floor()` | move the `heal_to_max()` block |
| Natural Sleeper form lock | `advance_floor()` + `_on_short_rest_completed()` | `wild_heart_sleeper_active = rank>=1`; `active_sleeper_form = natural_sleeper_form`; keep the log lines |
| Status effects | — (new, recommended) | clear `poison/burning/bleeding/slowed_turns`, emit `player_status_changed` |
| Temp HP | — | leave as-is (temp HP persisting through rest is harmless; Ironwood/Sleeper overwrite it anyway) |
| Future spell slots | — | add here when casters land; this function is the one and only refill site |

End with `_sync_ability_uses()`, `short_rest_changed.emit()`, `long_rest_completed.emit()`, `_consume_rations(LONG_REST_RATION_COST)` (guarded by `invincible`), and a log line.

**Invariant for all future sessions:** any new "per long rest" resource is refilled in `long_rest()` and NOWHERE else. `advance_floor()` must never regain restore logic.

---

## 5. Hunger removal — exhaustive dead-code checklist

Grep confirmed the full footprint (2026-07). Delete/edit exactly these:

**`scripts/autoloads/game_state.gd`**
- `signal hunger_changed`, `enum HungerState`, `MAX_HUNGER`, `STARVE_INTERVAL`, `_starvation_tick`, `hunger`, `hunger_state` (lines ~17, 73–77, 146–151)
- `start_new_run()`: `hunger = MAX_HUNGER`, `_starvation_tick = 0`
- `deplete_hunger()`, `restore_hunger()` (lines ~726–749)
- `use_item()` FOOD branch: both `restore_hunger()` calls → replace per §2
- Comment on `player_was_hit_this_turn` mentions "starvation" — reword

**`scripts/entities/player.gd`**
- Line ~278: `GameState.deplete_hunger()` — delete
- HP regen: root CLAUDE.md documents "HP regen every 10 turns (blocked while Starving)". Find the regen site (grep `regen` in player.gd/game_state.gd) and remove the STARVING guard; keep the regen itself.

**`scripts/ui/hud.gd`**
- `_hunger_label` creation/positioning (~181–187), `hunger_changed` connection (~118), `_on_hunger_changed`, `_update_hunger_label` (~297–349). Optionally repurpose the label position for a ration count display (nice-to-have, listen to `inventory_changed`).

**`scripts/ui/debug_panel.gd`** — "Restores 60 hunger"-style descriptions in `ALL_ITEMS`; re-check every FOOD entry against §2's new heal semantics.

**`scripts/autoloads/audio_manager.gd`** — `"hungry"`, `"starving"` SFX names: remove from the list (and from the owed-assets doc if the user maintains one).

**CLAUDE.md updates (project invariant — do in the same session):** root CLAUDE.md ("Hunger, traps, doors, short rest" section, turn-flow line "hunger depletes 1"), `scripts/autoloads/CLAUDE.md` (Hunger thresholds section, signal table, turn sequence line), `scripts/entities/CLAUDE.md` if it mentions hunger, and document the new `long_rest()` chokepoint + `LONG_REST_RATION_COST` + the invariant from §4.

---

## 6. Ordering & session sizing

One session can do this whole spec, but commit in this order so the game is playable at every commit:
1. Add `long_rest()` + move restores out of `advance_floor()` + panel button (game playable; hunger still ticking).
2. Ration model + loot pool + ALL_ITEMS mirror.
3. Hunger removal sweep (§5).
4. CLAUDE.md updates.

**Prerequisite ordering with other systems:** the talent boss-gate work (TALENT doc §3) is independent. Save/load (SAVE doc) should land AFTER this spec, since it removes `hunger` from persisted state and adds ration/rest fields. Natural Sleeper's "long rest only" retargeting happens here, satisfying the old wildheart prompt's prerequisite note.
