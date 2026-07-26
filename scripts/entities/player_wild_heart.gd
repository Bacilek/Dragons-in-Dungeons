class_name PlayerWildHeart
extends Node

# Wild Heart Tier 2 talents: One with Nature (companion), Natural Rager, Natural Sleeper.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.

const _CompanionClass = preload("res://scripts/entities/companion.gd")

var player: Player

func activate_one_with_nature(ab: Ability) -> void:
	var rank: int = GameState.get_talent_rank("wild_companion")
	if ab.uses_remaining <= 0:
		GameState.game_log("[color=gray]One with Nature: no charge available (rest to restore).[/color]")
		return
	if GameState.player_companion != null and is_instance_valid(GameState.player_companion):
		dismiss_companion()
	summon_companion(rank)
	if not GameState.invincible:
		ab.uses_remaining = 0
	GameState.ability_bar_changed.emit()

func summon_companion(rank: int) -> void:
	if player._dungeon_floor == null:
		return
	var stats_data: Dictionary = GameState.WILD_HEART_COMPANION_STATS.get(rank, {})
	var companion: Companion = _CompanionClass.new()
	companion.configure(stats_data)
	var spawn_pos: Vector2i = find_free_adjacent()
	if spawn_pos == Vector2i(-1, -1):
		GameState.game_log("[color=gray]No room to summon companion![/color]")
		return
	player._dungeon_floor.spawn_companion(companion, spawn_pos)
	GameState.player_companion = companion
	GameState.game_log("[color=lime]You summon a %s to fight by your side![/color]" % companion.animal_name)

func dismiss_companion() -> void:
	var comp = GameState.player_companion
	if comp == null or not is_instance_valid(comp):
		GameState.player_companion = null
		return
	if player._dungeon_floor != null:
		player._dungeon_floor.remove_companion(comp)
	TurnManager.unregister_enemy(comp)
	GameState.game_log("[color=gray]%s is dismissed.[/color]" % comp.animal_name)
	comp.queue_free()
	GameState.player_companion = null

func find_free_adjacent() -> Vector2i:
	if player._dungeon_floor == null:
		return Vector2i(-1, -1)
	var dirs: Array[Vector2i] = [
		Vector2i(1, 0), Vector2i(-1, 0), Vector2i(0, 1), Vector2i(0, -1),
		Vector2i(1, 1), Vector2i(-1, 1), Vector2i(1, -1), Vector2i(-1, -1),
	]
	for d: Vector2i in dirs:
		var p: Vector2i = player.grid_pos + d
		if player._dungeon_floor.is_walkable_for_companion(p):
			return p
	return Vector2i(-1, -1)

func cycle_animal_form(ab: Ability) -> void:
	# Free to press any time, no rest required — one press steps to the next form in the
	# Bear→Eagle→Wolf→Bear cycle, taking GameState.ANIMAL_FORM_SWITCH_TURNS (1) real turn to take
	# effect (start_animal_form_switch()). Since you can't jump directly to the 3rd form, going
	# e.g. Bear→Wolf takes 2 presses/turns (one per intermediate step). Re-pressing mid-transition
	# just retargets and restarts the count.
	var forms: PackedStringArray = ["Bear", "Eagle", "Wolf"]
	var idx: int = forms.find(GameState.natural_rager_form)
	var next_form: String = forms[(idx + 1) % forms.size()]
	GameState.start_animal_form_switch(next_form)
	ab.description = GameState._build_natural_rager_description()
	ab.icon_path = GameState.talent_icon_path("animal_form", 0)
	GameState.ability_bar_changed.emit()
	var t: int = GameState.rager_form_switch_turns_remaining
	if t > 0:
		GameState.game_log("[color=orange]Animal Form: shifting into %s Form (%d turn%s).[/color]" % [next_form, t, "s" if t != 1 else ""])
	else:
		GameState.game_log("[color=orange]Animal Form: switched to %s Form.[/color]" % next_form)

func cycle_natural_sleeper_form(ab: Ability) -> void:
	# "" is the initial state (never chosen), not part of the cycle.
	# First press: find("") = -1 → (-1+1)%3 = 0 → "Owl". After that: Owl→Panther→Salmon→Owl.
	var forms: PackedStringArray = ["Owl", "Panther", "Salmon"]
	var idx: int = forms.find(GameState.natural_sleeper_form)
	GameState.natural_sleeper_form = forms[(idx + 1) % forms.size()]
	ab.description = GameState._build_natural_sleeper_description()
	ab.icon_path = GameState.talent_icon_path("expanded_forms", 0)
	GameState.ability_bar_changed.emit()
	var chosen: String = GameState.natural_sleeper_form
	if GameState.wild_heart_sleeper_active and GameState.active_sleeper_form != chosen:
		GameState.game_log("[color=cyan]Natural Sleeper: %s Form chosen — activates next rest.[/color]" % chosen)
	else:
		GameState.game_log("[color=cyan]Natural Sleeper: switched to %s Form.[/color]" % chosen)
