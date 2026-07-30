class_name PlayerRangerTalents
extends Node

# Ranger base-class level-1 ability (Hunter's Mark) + Tier 1 talents shared by every Ranger:
# Trailblazer, Bloodhound, Twin Fang. Composition child-node split out of player.gd — same
# convention as PlayerBaseTalents (Barbarian). Spec: markdowns/ranger_base.md.

var player: Player

# ── Hunter's Mark (baseline, granted at char creation — see GameState._give_ranger_starting_items()) ──
# Arms targeting mode; player.gd's LMB handler resolves the click into commit_mark(). Real 5e-2024
# shape now: free casting time (never costs a turn — no TurnManager.begin/on_player_action_complete
# here), range 9 tiles, Concentration up to 100 turns (Stats.hunters_mark_turns, ticked in
# player.gd's _on_turn_started() alongside Blade Ward/Expeditious Retreat/Fog Cloud). A use is spent
# only when ESTABLISHING a mark on a target from having none — retargeting an already-active mark is
# free (5e "move Hunter's Mark for free"). Once HUNTERS_MARK_USES_MAX free uses run out, establishing
# a new mark automatically spends a real 1st-level Ranger spell slot instead (Hunter's Mark IS a real
# 1st-level spell in 5e) — see the fallback in commit_mark() below.

func activate_hunters_mark() -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._hunters_mark_mode_active = true
	GameState.game_log("[color=cyan]Hunter's Mark: choose a target within %d tiles.[/color]" % Stats.HUNTERS_MARK_RANGE)

func commit_mark(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	var stats: Stats = GameState.player_stats
	var diff: Vector2i = enemy.grid_pos - player.grid_pos
	var dist_sq: int = diff.x * diff.x + diff.y * diff.y
	if dist_sq > Stats.HUNTERS_MARK_RANGE * Stats.HUNTERS_MARK_RANGE:
		GameState.game_log("[color=gray]Hunter's Mark: target is out of range (%d tiles).[/color]" % Stats.HUNTERS_MARK_RANGE)
		return
	var establishing: bool = stats.hunters_mark_target == null or not is_instance_valid(stats.hunters_mark_target)
	if establishing:
		if stats.hunters_mark_free_recast_available:
			# Baseline free-recast window: the previous mark's target died while concentration was
			# still active, and this is the very next real turn — no use/slot spent.
			stats.hunters_mark_free_recast_available = false
		elif stats.hunters_mark_uses_remaining > 0:
			if not GameState.invincible:
				stats.hunters_mark_uses_remaining -= 1
		else:
			var slot_pool = stats.caster.slot_pool if stats.caster != null else null
			var has_slot: bool = slot_pool != null and slot_pool.remaining.get(1, 0) > 0
			if not has_slot:
				GameState.game_log("[color=gray]Hunter's Mark: no free uses or 1st-level spell slots remaining.[/color]")
				return
			if not GameState.invincible:
				slot_pool.consume(1)
			GameState.spell_slots_changed.emit()
			GameState.game_log("[color=cyan]Hunter's Mark: cast using a 1st-level spell slot (no free uses left).[/color]")
	if stats.concentration_spell_id != "" and stats.concentration_spell_id != "hunters_mark":
		GameState.end_concentration("[color=gray]Casting Hunter's Mark breaks your concentration.[/color]")
	stats.concentration_spell_id = "hunters_mark"
	stats.hunters_mark_turns = Stats.HUNTERS_MARK_DURATION
	stats.hunters_mark_target = enemy
	stats.hunters_mark_fresh = true
	GameState.game_log("[color=cyan]You mark %s as your quarry.[/color]" % enemy.display_name)
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)

# Rolls Hunter's Mark's bonus Force damage die for a hit against the marked target — a SECOND,
# independent damage instance (Judgement-Day pattern, scripts/entities/CLAUDE.md's damage-stacking
# rule — Force is a distinct type from the weapon's own, so it never folds into the same instance).
# Applies to EVERY hit against the mark (Main Hand melee/ranged/thrown, Off-hand, and Nick) as part
# of the baseline ability — `is_primary` is kept as a param (unused today) since Off-hand/Nick call
# sites already pass it. Twin Fang R1 used to gate the Off-hand/Nick case; that's now baseline (see
# docs/TODO.md — R1 is a dead rank until it's redesigned). Returns 0 only if the target isn't marked.
func hunters_mark_bonus_die(enemy: Enemy, is_primary: bool) -> int:
	if enemy == null or GameState.player_stats.hunters_mark_target != enemy:
		return 0
	return Rng.roll(6)

# Bloodhound R1: the first attack attempt against a freshly-marked target gets Advantage. The
# freshness flag itself clears on this FIRST attempt regardless of rank/hit/miss — same "one-shot,
# consumed on next attack" shape as Psycho's kill/crit buff (scripts/entities/player_base_talents.gd).
func consume_bloodhound_fresh_adv(enemy: Enemy) -> int:
	var stats: Stats = GameState.player_stats
	if enemy == null or stats.hunters_mark_target != enemy or not stats.hunters_mark_fresh:
		return 0
	stats.hunters_mark_fresh = false
	return 1 if GameState.get_talent_rank("bloodhound") >= 1 else 0

# Twin Fang R2: the Off-hand attack against the Marked target keeps its full ability modifier
# (skips the usual "drop the mod unless negative" dual-wield house rule) — see player.gd's
# _resolve_offhand_attack().
func twin_fang_r2_active(enemy: Enemy) -> bool:
	return enemy != null and GameState.player_stats.hunters_mark_target == enemy \
		and GameState.get_talent_rank("twin_fang") >= 2

# Bloodhound R3: when the Marked target dies, Hunter's Mark instantly and freely re-attaches to
# the nearest visible enemy (no use spent). Called from Enemy.die() — see scripts/entities/CLAUDE.md.
# Baseline (no talent needed): if concentration is still active and R3 doesn't auto-remark, arm a
# one-turn free-recast window (Stats.hunters_mark_free_recast_pending) — see markdowns/ranger_base.md.
func try_bloodhound_remark(dead_enemy: Enemy) -> void:
	var stats: Stats = GameState.player_stats
	if stats.hunters_mark_target != dead_enemy:
		return
	stats.hunters_mark_target = null
	stats.hunters_mark_fresh = false
	if GameState.get_talent_rank("bloodhound") < 3 or player == null or player._dungeon_floor == null:
		if stats.hunters_mark_turns > 0 and stats.concentration_spell_id == "hunters_mark":
			stats.hunters_mark_free_recast_pending = true
			GameState.game_log("[color=cyan]Hunter's Mark: your quarry has fallen — mark a new target for free on your next turn.[/color]")
		return
	var best: Enemy = null
	var best_dist_sq: int = -1
	for e: Enemy in player._dungeon_floor.get_visible_enemies():
		if e == dead_enemy or not is_instance_valid(e) or e.stats.is_dead():
			continue
		var d: Vector2i = e.grid_pos - player.grid_pos
		var dist_sq: int = d.x * d.x + d.y * d.y
		if best == null or dist_sq < best_dist_sq:
			best = e
			best_dist_sq = dist_sq
	if best != null:
		stats.hunters_mark_target = best
		stats.hunters_mark_fresh = true
		GameState.game_log("[color=cyan]Bloodhound: Hunter's Mark shifts to %s.[/color]" % best.display_name)
