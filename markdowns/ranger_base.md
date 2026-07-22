# Ranger — Base Class Implementation Spec

## Overview
Ranger's level-1 baseline ability is **Hunter's Mark**, granted directly at character creation
(same "not talent-gated" pattern as Barbarian's Rage). Three Tier 0 talents — Trailblazer,
Bloodhound, Twin Fang — each build on Hunter's Mark from a different angle (terrain mastery,
ambush/tracking, weapon-agnostic combat), but deliberately do **not** assume the player is using
a bow: a Ranger who equips two Daggers and never touches a ranged weapon is an equally "correct"
build, not a fallback. Implemented in `scripts/entities/player_ranger_talents.gd`
(`PlayerRangerTalents`, composition child-node — see `scripts/entities/CLAUDE.md`'s "Split-out
modules").

---

## Hunter's Mark (Level 1, Active)

- **Type:** Arm-then-click targeting mode (same UX pattern as World Tree's Grip of the Forest
  hook mode) — activating the ability bar slot arms `Player._hunters_mark_mode_active`; the next
  LMB click on a visible enemy resolves via `PlayerRangerTalents.commit_mark(enemy)`.
- **Uses:** `Stats.hunters_mark_uses_remaining` (`Stats.HUNTERS_MARK_USES_MAX` = 3), refilled at
  `GameState.long_rest()`. A use is spent **only** when establishing a mark from having none —
  retargeting an already-active mark (clicking a different enemy while one is marked) is free,
  mirroring 5e's "move Hunter's Mark for free" rule.
- **Effect:** every hit against `Stats.hunters_mark_target` (any weapon — melee, Off-hand, Nick,
  ranged, thrown) deals a second, independent **+1d6 Force** damage instance
  (`PlayerRangerTalents.hunters_mark_bonus_die()`), the same "one hit, two damage types" shape as
  Zealot's Judgement Day / the lit Torch's Fire bonus (`scripts/entities/CLAUDE.md`'s
  damage-stacking rule) — Force is a distinct type from the weapon's own, so it's never folded
  into the same instance. The Off-hand/Nick swings only get the bonus once **Twin Fang R1** is
  invested (see below) — the baseline ability alone only guarantees it on the turn's primary
  attack (melee/ranged/thrown).
- **Tracking:** while a target is marked, `scripts/ui/hunters_mark_indicator.gd` shows its
  direction on-screen even outside FOV/LOS (mirrors `compass.gd`'s arrow-glyph pattern verbatim,
  visibility driven by "is a target currently marked" instead of a one-shot discovery flag).
- **Ends:** the marked target dies (`Stats.hunters_mark_target = null`, unless **Bloodhound R3**
  re-attaches it for free — see below), or the player marks a different target. `hunters_mark_target`
  is deliberately **not serialized** (`to_dict()`/`from_dict()`) — a live `Enemy` node reference
  can't survive save/load, same precedent as `witch_bolt_target` (mid-floor state, ends silently
  on load).

**State tracked** (`stats.gd`):
```
hunters_mark_target: Enemy       # not serialized
hunters_mark_fresh: bool         # not serialized — Bloodhound R1's one-shot flag
hunters_mark_uses_remaining: int # serialized
```

---

## Talent — Trailblazer
*You move through the wild like it isn't even there.*

**Rank 1:** Mud and Water no longer slow you down — you move through difficult terrain at full
speed.

**Rank 2:** Enemies standing in Mud or Water have Disadvantage on attacks against you.

**Rank 3:** Passively detect traps in a wider radius around you as you move.

**Implementation notes:**
- R1: `player.gd._try_move()` and `_execute_queued_path()` both gate the "slowed" terrain status
  behind `GameState.get_talent_rank("trailblazer") < 1` (mirrors the existing Wild Heart
  Panther/Salmon bypass flags in `_try_move()` — `_execute_queued_path()` had NO such bypass
  mechanism before this talent, added fresh).
- R2: `Enemy._attack_player()` checks whether the attacking enemy's own `grid_pos` is Mud/Water
  and folds that into `_resolve_attack_roll()`'s `extra_disadv` param.
- R3 is not yet wired to an actual detection-radius change — `player_actions.gd`'s passive trap
  perception mechanism needs review before this rank does anything; currently inert (rank invests
  fine, no crash, just no effect yet). Flagged as a known follow-up.

---

## Talent — Bloodhound
*Once you've marked something, it's already dead — it just doesn't know it yet.*

**Rank 1:** Your first attack against a freshly-marked target is made with Advantage.

**Rank 2:** Your Marked target is easier for you to sneak up on (reduced effective Passive
Perception vs. you only).

**Rank 3:** When your Marked target dies, Hunter's Mark instantly and freely re-attaches to the
nearest visible enemy.

**Implementation notes:**
- R1: `Stats.hunters_mark_fresh` is set `true` by `commit_mark()`; consumed (cleared) by
  `PlayerRangerTalents.consume_bloodhound_fresh_adv(enemy)` on the FIRST attack-roll attempt
  against that target regardless of hit/miss/rank — same one-shot "consumed on next attack"
  pattern as Psycho's kill/crit buff. Wired into all 4 player.gd melee attack-roll sites
  (`_bump_attack`/`_resolve_cleave_attack`/`_resolve_offhand_attack`/`resolve_opportunity_attack`)
  plus `player_ranged.gd`/`player_throw_tool.gd`.
- R2: `player.gd._resolve_stealth_check()` computes an `effective_pp` (passive perception minus
  `BLOODHOUND_R2_PP_DEBUFF` = 2) for the marked target only, comparing the stealth roll against
  that instead of the enemy's raw `passive_perception`.
- R3: `Enemy.die()` calls `PlayerRangerTalents.try_bloodhound_remark(self)` — if the dying enemy
  was the mark, it re-attaches (rank-gated, no use spent, sets `hunters_mark_fresh = true` again)
  to the nearest still-alive enemy in `DungeonFloor.get_visible_enemies()`.

---

## Talent — Twin Fang
*Bow, blade, it makes no difference to the hunt.*

**Rank 1:** Hunter's Mark's bonus damage also applies to your Off-hand and Nick bonus attacks
against the mark (not just the turn's primary attack).

**Rank 2:** Your Off-hand attack against the Marked target keeps its full ability modifier (skips
the usual dual-wield "drop the mod unless negative" house rule) — only vs. the mark.

**Rank 3:** The Marked target can never gain Advantage on attacks against you.

**Implementation notes:**
- R1: `hunters_mark_bonus_die(enemy, is_primary)` returns 0 for a non-primary swing unless
  `get_talent_rank("twin_fang") >= 1` — the primary attack (melee/ranged/thrown) always gets the
  bonus regardless of rank (that's the baseline ability itself, not this talent).
- R2: `player.gd._resolve_offhand_attack()`'s `dmg_mod` line checks
  `PlayerRangerTalents.twin_fang_r2_active(enemy)` before applying the usual `mini(attack_mod, 0)`
  clamp.
- R3: `Enemy._attack_player()` computes `twin_fang_blocks_adv` and forces `fog_adv = false`
  (suppressing the Fog-Cloud-grants-ADV-vs-Blinded-target source) whenever this enemy IS the
  Hunter's Mark target and the rank is ≥ 3 — a narrow, single-source suppression (doesn't touch
  any other future ADV source an enemy might gain), acceptable since Fog Cloud is the only enemy
  side ADV source that exists today.

---

## Starting gear (`GameState._give_ranger_starting_items()`)

Two Daggers (Main Hand + Off-hand — immediate dual-wield melee is a fully "correct" build from
turn 1) **and** a Short Bow + 20 Arrows in the ranged slot — the player picks whichever fits the
moment, neither path is mechanically favored. Also sets `proficient_simple_weapons` AND
`proficient_martial_weapons` true (`Stats.apply_class_defaults()`'s RANGER branch previously set
neither — a pre-existing gap fixed alongside this feature, since every Ranger weapon would
otherwise show as "not proficient" in tooltips).

## Icons
No Ranger icon art exists yet (`GameState.RANGER_TALENT_ICON_FLAT`, resolving under
`res://icons/classes/ranger/...`) — every Ranger ability/talent renders via the existing
`ResourceLoader.exists()` fallback (name-text instead of an icon), same asset-debt precedent as
the Imp's shape-shift forms. Not a blocker.
