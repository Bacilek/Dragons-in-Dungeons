class_name PlayerThiefTools
extends Node

# Thief Tools mechanics: find tools, disarm traps, lock/pick doors. Composition child-node
# split out of player.gd — see scripts/entities/CLAUDE.md.

var player: Player

func find_thief_tools() -> Item:
	for i: int in GameState.QUICKBAR_SIZE:
		var it: Item = GameState.player_quickbar[i] as Item
		if it != null and it.item_name == "Thief Tools":
			return it
	for i: int in GameState.INVENTORY_SIZE:
		var it: Item = GameState.player_inventory[i] as Item
		if it != null and it.item_name == "Thief Tools":
			return it
	return null

func attempt_disarm(trap_pos: Vector2i) -> void:
	var tools: Item = find_thief_tools()
	if tools == null:
		GameState.game_log("[color=red]You need Thief Tools to disarm traps![/color]")
		return

	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var s: Stats = GameState.player_stats
	var dex_mod: int = s.dex_modifier()
	var effective_stat: String = "DEX"
	var has_prof: bool = s.check_prof_dex
	var prof_bonus: int = s.proficiency_bonus if has_prof else 0
	var has_adv: bool = s.zealous_presence_turns > 0
	var lr1: Dictionary = CombatMath.halfling_reroll(Rng.roll(20))
	var die1: int = lr1["value"]
	var lucky1: bool = lr1["lucky"]
	var die2: int = die1
	var lucky2: bool = false
	if has_adv:
		var lr2: Dictionary = CombatMath.halfling_reroll(Rng.roll(20))
		die2 = lr2["value"]
		lucky2 = lr2["lucky"]
	var die: int = maxi(die1, die2)
	var lucky: bool = lucky1 or lucky2
	var total: int = die + dex_mod + prof_bonus
	const DC: int = 10
	var trap: Dictionary = player._dungeon_floor.get_trap_at(trap_pos)
	var trap_name: String = trap.get("name", "trap")
	var adv_tag: String = " [color=gray](Zealous Presence)[/color]" if has_adv else ""
	var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d,lucky1=%d,lucky2=%d" % [effective_stat, die, die1, die2, dex_mod, prof_bonus, total, DC, 1 if total >= DC else 0, 1 if has_adv else 0, 1 if lucky1 else 0, 1 if lucky2 else 0]

	if total >= DC:
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=green]Disarmed [b]%s[/b]!%s [url=%s]%d vs DC %d[/url][/color]" % [trap_name, adv_tag, check_meta, total, DC], lucky))
		player._dungeon_floor.disarm_trap(trap_pos)
	else:
		GameState.game_log(CombatMath.wrap_halfling_luck("[color=red]Failed to disarm [b]%s[/b]!%s [url=%s]%d vs DC %d[/url]%s[/color]" % [trap_name, adv_tag, check_meta, total, DC, " — Thief Tools lost!" if not GameState.invincible else ""], lucky))
		if not GameState.invincible:
			GameState.consume_one(tools)

	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

func attempt_lock_door(door_pos: Vector2i) -> void:
	var tools: Item = find_thief_tools()
	if tools == null:
		GameState.game_log("[color=gray]You need Thief Tools to lock a door.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var dex_mod: int = player.stats.dex_modifier()
	var die: int = Rng.roll(20)
	var total: int = die + dex_mod
	const LOCK_DC: int = 10
	var door_world: Vector2 = Vector2(door_pos * Entity.TILE_SIZE) + Vector2(Entity.TILE_SIZE * 0.5, Entity.TILE_SIZE * 0.5)
	var check_meta: String = "check:stat=DEX,die=%d,mod=%d,prof=0,total=%d,dc=%d,pass=%d" % [die, dex_mod, total, LOCK_DC, 1 if total >= LOCK_DC else 0]
	if total >= LOCK_DC:
		player._dungeon_floor.lock_door(door_pos, true)  # by_player=true
		GameState.game_log("[color=green]You lock the door! [url=%s]%d vs DC %d[/url][/color]" % [check_meta, total, LOCK_DC])
		show_float_text(door_world, "LOCKED!", Color(0.7, 0.4, 1.0))
	else:
		GameState.game_log("[color=red]Failed to lock the door [url=%s]%d vs DC %d[/url]%s[/color]" % [check_meta, total, LOCK_DC, " — Thief Tools lost!" if not GameState.invincible else ""])
		if not GameState.invincible:
			GameState.consume_one(tools)
		show_float_text(door_world, "FAIL!", Color(1.0, 0.3, 0.3))
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

# Attempt to pick a dungeon-locked door with Thief Tools (DEX check, prof only for DEX-check-proficient classes)
func attempt_disarm_lock(door_pos: Vector2i) -> void:
	var tools: Item = find_thief_tools()
	if tools == null:
		GameState.game_log("[color=red]You need Thief Tools to pick this lock.[/color]")
		return
	TurnManager.begin_player_action()
	AudioManager.play("lockpick")
	var s: Stats = GameState.player_stats
	var dex_mod: int = s.dex_modifier()
	var effective_stat: String = "DEX"
	var has_prof: bool = s.check_prof_dex
	var prof_bonus: int = s.proficiency_bonus if has_prof else 0
	var has_adv: bool = s.zealous_presence_turns > 0
	var die1: int = Rng.roll(20)
	var die2: int = die1
	if has_adv:
		die2 = Rng.roll(20)
	var die: int = maxi(die1, die2)
	var total: int = die + dex_mod + prof_bonus
	var dc: int = 10 + GameState.current_floor / 3
	var adv_tag: String = " [color=gray](Zealous Presence)[/color]" if has_adv else ""
	var check_meta: String = "check:stat=%s,die=%d,d1=%d,d2=%d,mod=%d,prof=%d,total=%d,dc=%d,pass=%d,adv=%d" % [effective_stat, die, die1, die2, dex_mod, prof_bonus, total, dc, 1 if total >= dc else 0, 1 if has_adv else 0]
	var door_world: Vector2 = Vector2(door_pos * Entity.TILE_SIZE) + Vector2(Entity.TILE_SIZE * 0.5, Entity.TILE_SIZE * 0.5)
	if total >= dc:
		player._dungeon_floor.unlock_door(door_pos)
		player._dungeon_floor.open_door(door_pos)
		GameState.game_log("[color=green]You pick the lock!%s [url=%s]%d vs DC %d[/url][/color]" % [adv_tag, check_meta, total, dc])
		show_float_text(door_world, "UNLOCKED!", Color(0.4, 1.0, 0.5))
	else:
		GameState.game_log("[color=red]Failed to pick the lock%s [url=%s]%d vs DC %d[/url]%s[/color]" % [adv_tag, check_meta, total, dc, " — Thief Tools lost!" if not GameState.invincible else ""])
		if not GameState.invincible:
			GameState.consume_one(tools)
		show_float_text(door_world, "FAIL!", Color(1.0, 0.3, 0.3))
	player._dungeon_floor.update_fog(player.grid_pos)
	TurnManager.on_player_action_complete()

func show_float_text(world_pos: Vector2, text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = world_pos + Vector2(-16.0, -20.0)
	lbl.z_index = 10
	player.get_parent().add_child(lbl)
	var tw := lbl.create_tween()
	tw.tween_property(lbl, "position:y", lbl.position.y - 14.0, 0.9)
	tw.parallel().tween_property(lbl, "modulate:a", 0.0, 0.9).set_delay(0.35)
	tw.tween_callback(lbl.queue_free)
