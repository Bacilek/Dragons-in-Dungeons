class_name PlayerRangerTalents
extends Node

# Ranger base-class level-1 ability (Hunter's Mark) + Tier 1 talents shared by every Ranger:
# Trailblazer, Bloodhound, Twin Fang. Composition child-node split out of player.gd — same
# convention as PlayerBaseTalents (Barbarian). Spec: markdowns/ranger_base.md.

var player: Player

# ── Hunter's Mark (baseline, granted at char creation — see GameState._give_ranger_starting_items()) ──
# Arms targeting mode; player.gd's LMB handler resolves the click into commit_mark(). A use is
# spent only when establishing a mark on a target from having none — retargeting an already-active
# mark is free (5e "move Hunter's Mark for free").

func activate_hunters_mark() -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT or player._path_executing:
		return
	player._hunters_mark_mode_active = true
	GameState.game_log("[color=cyan]Hunter's Mark: choose a target.[/color]")

func commit_mark(enemy: Enemy) -> void:
	if enemy == null or not is_instance_valid(enemy):
		return
	var stats: Stats = GameState.player_stats
	var establishing: bool = stats.hunters_mark_target == null or not is_instance_valid(stats.hunters_mark_target)
	if establishing and stats.hunters_mark_uses_remaining <= 0:
		GameState.game_log("[color=gray]Hunter's Mark: no uses remaining until your next long rest.[/color]")
		return
	TurnManager.begin_player_action()
	if establishing and not GameState.invincible:
		stats.hunters_mark_uses_remaining -= 1
	stats.hunters_mark_target = enemy
	stats.hunters_mark_fresh = true
	GameState.game_log("[color=cyan]You mark %s as your quarry.[/color]" % enemy.display_name)
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# Rolls Hunter's Mark's bonus Force damage die for a hit against the marked target — a SECOND,
# independent damage instance (Judgement-Day pattern, scripts/entities/CLAUDE.md's damage-stacking
# rule — Force is a distinct type from the weapon's own, so it never folds into the same instance).
# `is_primary` = the swing that started this turn's attack (Main Hand melee/ranged/thrown); every
# OTHER sub-attack (Off-hand, Nick) only gets the bonus once Twin Fang R1 is invested. Returns 0
# (no bonus) if the target isn't marked or (for a non-primary swing) Twin Fang R1 isn't invested.
func hunters_mark_bonus_die(enemy: Enemy, is_primary: bool) -> int:
	if enemy == null or GameState.player_stats.hunters_mark_target != enemy:
		return 0
	if not is_primary and GameState.get_talent_rank("twin_fang") < 1:
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
func try_bloodhound_remark(dead_enemy: Enemy) -> void:
	var stats: Stats = GameState.player_stats
	if stats.hunters_mark_target != dead_enemy:
		return
	stats.hunters_mark_target = null
	stats.hunters_mark_fresh = false
	if GameState.get_talent_rank("bloodhound") < 3 or player == null or player._dungeon_floor == null:
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
