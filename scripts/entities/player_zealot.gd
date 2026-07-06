class_name PlayerZealot
extends Node

# Zealot Tier 2 talents: Divine Fury toggle, Blessed Warrior, Zealous Presence.
# Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.

var player: Player

# "max once per turn" activation cap. Reset by player.gd._on_turn_started(). The charge pool
# itself lives on GameState (zealot_blessed_charges) since it's a long-rest resource.
var blessed_warrior_used_this_turn: bool = false

func toggle_divine_fury(ab: Ability) -> void:
	GameState.zealot_divine_fury_type = "Necrotic" if GameState.zealot_divine_fury_type == "Radiant" else "Radiant"
	ab.description = GameState._build_divine_fury_description()
	GameState.ability_bar_changed.emit()
	GameState.game_log("[color=cyan]Divine Fury: switched to %s.[/color]" % GameState.zealot_divine_fury_type)
	# Free action — persists between turns, does NOT consume the turn.

func activate_blessed_warrior(ab: Ability) -> void:
	if blessed_warrior_used_this_turn:
		GameState.game_log("[color=gray]Blessed Warrior: already used this turn.[/color]")
		return
	if GameState.zealot_blessed_charges <= 0:
		GameState.game_log("[color=gray]Blessed Warrior: no charges remaining (recovers on long rest).[/color]")
		return
	blessed_warrior_used_this_turn = true
	if not GameState.invincible:
		GameState.zealot_blessed_charges -= 1
	GameState.zealot_blessed_heal_queued = true
	ab.uses_remaining = GameState.zealot_blessed_charges
	ab.description = GameState._build_blessed_warrior_description()
	GameState.ability_bar_changed.emit()
	GameState.game_log("[color=cyan]Blessed Warrior: readied — your next successful hit this turn heals 1d12. (%d charge%s left)[/color]" % [GameState.zealot_blessed_charges, "" if GameState.zealot_blessed_charges == 1 else "s"])
	# Free action — does NOT consume the turn.

func resolve_blessed_warrior_heal() -> void:
	if not GameState.zealot_blessed_heal_queued:
		return
	GameState.zealot_blessed_heal_queued = false
	var heal_roll: int = Rng.roll(12)
	var before: int = player.stats.current_hp
	GameState.heal(heal_roll)
	var healed: int = player.stats.current_hp - before
	if healed > 0:
		GameState.game_log("[color=lime]Blessed Warrior: divine vigor mends your wounds (+%d HP).[/color]" % healed)

func activate_zealous_presence(ab: Ability) -> void:
	var rank: int = GameState.get_talent_rank("zealous_presence")
	if rank <= 0:
		return
	var use_zp: bool = GameState.zealot_zp_charges > 0
	var use_rage: bool = not use_zp and GameState.player_stats.rage_uses_remaining > 0
	if not use_zp and not use_rage:
		GameState.game_log("[color=gray]Zealous Presence: no charges available (needs a Zealous Presence or Rage charge).[/color]")
		return
	if not GameState.invincible:
		if use_zp:
			GameState.zealot_zp_charges -= 1
		else:
			GameState.player_stats.rage_uses_remaining -= 1
			var rage_ab: Ability = player._find_ability("rage")
			if rage_ab != null:
				rage_ab.uses_remaining = GameState.player_stats.rage_uses_remaining
	var duration: int = [0, 1, 3, 5][mini(rank, 3)]
	player.stats.zealous_presence_turns = maxi(player.stats.zealous_presence_turns, duration)
	var comp = GameState.player_companion
	if comp != null and is_instance_valid(comp):
		comp.stats.zealous_presence_turns = maxi(comp.stats.zealous_presence_turns, duration)
	ab.uses_remaining = GameState.zealot_zp_charges
	ab.description = GameState._build_zealous_presence_description()
	GameState.ability_bar_changed.emit()
	var source_note: String = "" if use_zp else " [color=orange](no ZP charge left — consumed a Rage charge instead)[/color]"
	GameState.game_log("[color=gold]Zealous Presence! You and nearby allies gain Advantage for %d turn(s).%s[/color]" % [duration, source_note])
	# Free action — does NOT consume the turn.
