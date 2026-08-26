class_name PlayerFighter
extends Node

# Fighter's Second Wind (level 1, D&D 2024, Bonus Action) and Action Surge (level 2+) —
# Composition child-node split out of player.gd, see scripts/entities/CLAUDE.md's "Fighter class"
# section for the full mechanism. Neither activation function keeps state ON THIS NODE (Action
# Surge's own pending flag lives on GameState.action_surge_pending, not here, since player.gd's
# _try_move()/_handle_post_attack_turn() need to read/consume it without a PlayerFighter
# reference) — so this module needs no get_rewind_fields()/set_rewind_fields() pair; the only
# mutable state (Stats.second_wind_uses_remaining/action_surge_uses_remaining) already round-trips
# via the full player_stats.duplicate(true) rewind snapshot, and action_surge_pending is captured
# in RewindManager.REWIND_GAMESTATE_FIELDS like every other GameState-resident combat-transient
# flag.

var player: Player

func activate_second_wind() -> void:
	if player.stats.second_wind_uses_remaining <= 0 and not GameState.invincible:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.invincible:
		player.stats.second_wind_uses_remaining -= 1
		GameState.bonus_action_used = true
	GameState._sync_ability_uses()
	GameState.ability_bar_changed.emit()
	var raw_roll: int = Rng.roll(10)
	var lvl_bonus: int = player.stats.character_level
	var heal_roll: int = raw_roll + lvl_bonus
	var before: int = player.stats.current_hp
	var bruiser_bonus: int = GameState.heal(heal_roll)
	var healed: int = player.stats.current_hp - before
	if healed > 0:
		var bonus_sources: String = CombatMath.encode_bonus_sources([
			{"name": "Fighter level", "amount": lvl_bonus, "color": "lightblue"},
			{"name": "Bruiser", "amount": bruiser_bonus, "color": "cyan"},
		])
		var heal_meta: String = "heal:dice=1,sides=10,con=0,roll=%d,bonus=%s,total=%d" % [raw_roll, bonus_sources, healed]
		GameState.game_log("[color=lime]Second Wind mends your wounds ([url=%s]+%d HP[/url]).[/color]" % [heal_meta, healed])
	else:
		GameState.game_log("[color=gray]Second Wind: already at full health.[/color]")

# Action Surge (level 2+): instant, no action cost at all — deliberately does NOT call
# TurnManager.begin_player_action()/on_player_action_complete(), same "arm and return" shape as
# Zealot Strike's own activation. NOT gated by the Bonus Action economy (5e RAW: Action Surge
# costs no action of its own to use, unlike Second Wind). Sets GameState.action_surge_pending,
# consumed by the player's very next move (Player._try_move()'s tail) or attack (melee/ranged/
# thrown — Player._handle_post_attack_turn()'s `is_spell == false` branch), which reverts to
# waiting instead of ending the turn. A spell cast explicitly does NOT consume/extend it.
func activate_action_surge() -> void:
	if player.stats.action_surge_uses_remaining <= 0 and not GameState.invincible:
		return
	if not GameState.invincible:
		player.stats.action_surge_uses_remaining -= 1
	GameState._sync_ability_uses()
	GameState.ability_bar_changed.emit()
	GameState.action_surge_pending = true
	GameState.game_log("[color=cyan]Action Surge: take one more move or attack this turn (a spell still ends it).[/color]")
