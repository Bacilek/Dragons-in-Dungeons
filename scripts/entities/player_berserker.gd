class_name PlayerBerserker
extends Node

# Berserker Tier 2: Frenzy activation ability + Sadist Monster / Masochist Monster / Frenzied
# Killer talents. Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
# Spec: markdowns/berserker.md.

var player: Player

# Click-to-target arming, mirrors Grip of the Forest's _hook_mode_active pattern (World Tree).
var frenzy_mode_active: bool = false

func activate_frenzy() -> void:
	if not GameState.is_raging:
		GameState.game_log("[color=gray]Frenzy requires Raging.[/color]")
		return
	if GameState.berserker_frenzy_used:
		GameState.game_log("[color=gray]Frenzy: already used (resets on short/long rest).[/color]")
		return
	var adjacent: Enemy = _find_single_adjacent_enemy()
	if adjacent != null:
		execute_frenzy(adjacent)
		return
	frenzy_mode_active = true
	GameState.game_log("[color=red]Frenzy — click an adjacent enemy. [Esc] to cancel.[/color]")

# Hotkey convenience: if exactly one enemy is adjacent, hotkey activation bumps straight into it
# (same feel as a normal melee attack) instead of requiring a follow-up click. Ambiguous (0 or 2+
# adjacent enemies) still falls back to click-to-target mode below.
func _find_single_adjacent_enemy() -> Enemy:
	if player._dungeon_floor == null:
		return null
	var found: Enemy = null
	for dx: int in range(-1, 2):
		for dy: int in range(-1, 2):
			if dx == 0 and dy == 0:
				continue
			var e: Enemy = player._dungeon_floor.get_enemy_at(player.grid_pos + Vector2i(dx, dy))
			if e != null:
				if found != null:
					return null
				found = e
	return found

func execute_frenzy(enemy: Enemy) -> void:
	if not GameState.invincible:
		GameState.berserker_frenzy_used = true
	GameState.berserker_turns_since_frenzy = 0
	TurnManager.begin_player_action()

	var die_roll: int = Rng.roll(20)
	var w_dmin: int = player.stats.base_min_damage
	var w_dmax: int = player.stats.base_max_damage
	var melee: Item = GameState.equipped_weapon
	if melee != null and melee.damage_die_min > 0:
		w_dmin = melee.damage_die_min
		w_dmax = melee.damage_die_max
	var dmg_roll: int = Rng.range_i(w_dmin, w_dmax)
	var sadist_rank: int = GameState.get_talent_rank("sadist_monster")
	var sadist_bonus: int = 0
	if sadist_rank >= 1:
		for i: int in sadist_rank:
			sadist_bonus += Rng.roll(6)

	if die_roll == 1:
		var self_dmg: int = player.stats.take_damage(dmg_roll)
		GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
		GameState.game_log("[color=red]Frenzy misses! You tear into yourself for [color=orange]%d[/color] damage.[/color]" % self_dmg)
		_note_self_damage()
		GameState.check_player_death()
	elif die_roll == 20:
		var crit_bonus: int = sadist_bonus * 2
		var total: int = dmg_roll * 2 + crit_bonus
		var actual: int = enemy.stats.take_damage(total)
		enemy.update_hp_bar()
		if player._dungeon_floor != null:
			player._dungeon_floor.show_damage(enemy.position, actual, true)
		GameState.game_log("[color=gold]FRENZY CRIT! %s takes [color=yellow]%d[/color] damage — you feel nothing.[/color]" % [enemy.display_name, actual])
		_refresh_frenzy_on("crit")
		if enemy.stats.is_dead():
			player._finish_kill(enemy)
			_refresh_frenzy_on("kill")
	else:
		var self_dmg2: int = player.stats.take_damage(dmg_roll)
		GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
		var total2: int = dmg_roll + sadist_bonus
		var actual2: int = enemy.stats.take_damage(total2)
		enemy.update_hp_bar()
		if player._dungeon_floor != null:
			player._dungeon_floor.show_damage(enemy.position, actual2, false)
		GameState.game_log("[color=red]Frenzy! %s takes [color=orange]%d[/color] damage — you take [color=orange]%d[/color] back.[/color]" % [enemy.display_name, actual2, self_dmg2])
		_note_self_damage()
		GameState.check_player_death()
		if enemy.stats.is_dead():
			player._finish_kill(enemy)
			_refresh_frenzy_on("kill")

	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	# Frenzy is a free action — doesn't cost the turn (per spec).
	player._reverted_this_round = true
	TurnManager.revert_to_waiting()

func _refresh_frenzy_on(trigger: String) -> void:
	var rank: int = GameState.get_talent_rank("frenzied_killer")
	var refreshes: bool = (rank >= 1 and trigger == "kill") or (rank >= 2 and trigger == "crit")
	if refreshes and GameState.berserker_frenzy_used:
		GameState.berserker_frenzy_used = false
		GameState.berserker_turns_since_frenzy = 0
		GameState.game_log("[color=lime]Frenzied Killer: Frenzy's use refreshes![/color]")

# Frenzied Killer R3: every 3 turns since last use, refresh automatically. Called from
# player.gd._on_turn_started() on real turns only.
func tick_frenzied_killer() -> void:
	if GameState.get_talent_rank("frenzied_killer") < 3 or not GameState.berserker_frenzy_used:
		return
	GameState.berserker_turns_since_frenzy += 1
	if GameState.berserker_turns_since_frenzy >= 3:
		GameState.berserker_frenzy_used = false
		GameState.berserker_turns_since_frenzy = 0
		GameState.game_log("[color=lime]Frenzied Killer: Frenzy's use refreshes![/color]")

# Masochist Monster R1/R2: called whenever the player takes damage on their own turn (Frenzy
# self-damage counts — intentional synergy per spec). R1 grants +1 AC until next turn start;
# R2 also grants Rage-bonus × 1d4 temp HP.
func _note_self_damage() -> void:
	var rank: int = GameState.get_talent_rank("masochist_monster")
	if rank < 1:
		return
	if GameState.masochist_ac_bonus == 0:
		GameState.masochist_ac_bonus = 1
		GameState.recalculate_stats()
		GameState.game_log("[color=cyan]Masochist Monster: +1 AC until your next turn.[/color]")
	if rank >= 2:
		var thp: int = GameState.player_stats.rage_bonus_damage * Rng.roll(4)
		GameState.player_stats.temp_hp = thp
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		GameState.game_log("[color=cyan]Masochist Monster: %d temp HP.[/color]" % thp)

# Called externally (enemy hit resolution) so Masochist Monster also triggers on ordinary damage
# taken during the player's own turn (e.g. Retaliation is gone, but reactive/terrain damage still
# counts) — kept as a small public wrapper so non-Frenzy damage sources can opt in later.
func note_damage_taken_on_turn() -> void:
	_note_self_damage()

func clear_turn_start_ac_bonus() -> void:
	if GameState.masochist_ac_bonus != 0:
		GameState.masochist_ac_bonus = 0
		GameState.recalculate_stats()
