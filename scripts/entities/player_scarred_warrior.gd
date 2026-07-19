class_name PlayerScarredWarrior
extends Node

# Scarred Warrior Tier 2: Limit Break activation + Born in Blood / Enough is Enough /
# Bloodied Regen talents. Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md. Spec: markdowns/scarred_warrior.md.

var player: Player

# Click-to-target arming, mirrors Grip of the Forest's _hook_mode_active pattern.
var limit_break_mode_active: bool = false

func activate_limit_break() -> void:
	if GameState.scarred_warrior_limit_break_used:
		GameState.game_log("[color=gray]Limit Break: already used (resets on long rest).[/color]")
		return
	limit_break_mode_active = true
	var rank: int = GameState.get_talent_rank("enough_is_enough")
	var range_note: String = " within 5 tiles (piercing line)" if rank >= 3 else "an adjacent"
	GameState.game_log("[color=gold]Limit Break — move into or click %s enemy. [Esc] to cancel.[/color]" % range_note)

func execute_limit_break(primary: Enemy) -> void:
	if not GameState.invincible:
		GameState.scarred_warrior_limit_break_used = true
	TurnManager.begin_player_action()
	var missing_hp: int = player.stats.max_hp - player.stats.current_hp
	var rank: int = GameState.get_talent_rank("enough_is_enough")
	var targets: Array[Enemy] = [primary]

	if rank >= 3 and player._dungeon_floor != null:
		# Ranged + piercing line: gather every enemy between the player and the primary target.
		var dir: Vector2i = Vector2i(sign(primary.grid_pos.x - player.grid_pos.x), sign(primary.grid_pos.y - player.grid_pos.y))
		var pos: Vector2i = player.grid_pos
		var guard: int = 0
		while pos != primary.grid_pos and guard < 10:
			guard += 1
			pos += dir
			var e: Enemy = player._dungeon_floor.get_enemy_at(pos)
			if e != null and e != primary and not targets.has(e):
				targets.append(e)

	if rank >= 2 and player._dungeon_floor != null:
		for off_x: int in range(-1, 2):
			for off_y: int in range(-1, 2):
				if off_x == 0 and off_y == 0:
					continue
				var adj_e: Enemy = player._dungeon_floor.get_enemy_at(primary.grid_pos + Vector2i(off_x, off_y))
				if adj_e != null and not targets.has(adj_e):
					targets.append(adj_e)

	for target: Enemy in targets:
		var actual: int = target.stats.take_damage(missing_hp)
		target.update_hp_bar()
		if player._dungeon_floor != null:
			player._dungeon_floor.show_damage(target.position, actual, false)
		var is_lethal: bool = target.stats.is_dead()
		GameState.game_log("[color=gold]Limit Break! %s takes [color=yellow]%d[/color] damage.%s[/color]" % [target.display_name, actual, CombatMath.death_suffix(is_lethal)])
		if rank >= 1:
			_apply_weapon_mastery_effect(target)
		if is_lethal:
			player._finish_kill(target)

	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# Enough is Enough R1: applies a representative effect for the equipped weapon's known mastery.
# Not every mastery has a meaningful non-roll equivalent (Vex/Nick/Graze need an attack roll to
# hook into) — those are silently skipped rather than faked.
func _apply_weapon_mastery_effect(target: Enemy) -> void:
	var weapon: Item = GameState.equipped_weapon
	if weapon == null or not player.stats.knows_mastery(weapon.weapon_mastery):
		return
	match weapon.weapon_mastery:
		"Topple":
			if target.apply_status("prone", 1):
				GameState.game_log("[color=gray]%s is knocked prone![/color]" % target.display_name)
		"Slow":
			if target.apply_status("slowed", 2):
				GameState.game_log("[color=gray]%s is slowed![/color]" % target.display_name)
		"Push":
			if player._dungeon_floor != null:
				var dir: Vector2i = Vector2i(sign(target.grid_pos.x - player.grid_pos.x), sign(target.grid_pos.y - player.grid_pos.y))
				player._dungeon_floor.force_move_entity(target, dir, 1, false)
		_:
			pass

# Bloodied Regen: called from player.gd._on_turn_started() on real turns only, while Bloodied.
func tick_bloodied_regen() -> void:
	var rank: int = GameState.get_talent_rank("bloodied_regen")
	if rank < 1 or not player.stats.is_bloodied():
		return
	var thp: int = rank * GameState.player_stats.rage_bonus_damage
	GameState.player_stats.temp_hp = thp  # replace, not stack — matches Ironwood Bark/Natural Sleeper convention
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.game_log("[color=cyan]Spite: %d temp HP (Bloodied).[/color]" % thp)
