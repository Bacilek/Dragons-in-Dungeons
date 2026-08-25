class_name PlayerZealot
extends Node

# Zealot Tier 2: Zealot Strike activation + Judgement Day / Overheal Shield / Never Back Down
# talents. Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
# Spec: markdowns/zealot.md.

var player: Player

# Armed by activate_zealot_strike(); consumed (or silently dropped) on the player's next melee
# attack this turn. Cleared at turn start if never consumed — matches spec: "if the turn ends
# without a melee attack, the toggle deactivates with no effect (Hit Die is NOT consumed)".
var zealot_strike_armed: bool = false
# Judgement Day: set true when a Zealot Strike heal resolves; consumed by the NEXT attack
# (not the same attack that triggered the heal) — mirrors Ironwood Bark R3's pending-bonus pattern.
var judgement_day_pending: bool = false

## Rewind snapshot — see scripts/autoloads/rewind_manager.gd.
func get_rewind_fields() -> Dictionary:
	return {"zealot_strike_armed": zealot_strike_armed, "judgement_day_pending": judgement_day_pending}

func set_rewind_fields(d: Dictionary) -> void:
	zealot_strike_armed = bool(d.get("zealot_strike_armed", false))
	judgement_day_pending = bool(d.get("judgement_day_pending", false))

func activate_zealot_strike(ab: Ability) -> void:
	if GameState.hit_dice <= 0:
		return
	if GameState.bonus_action_used and not GameState.invincible:
		GameState.game_log("[color=gray]Already used your bonus action this turn.[/color]")
		return
	if not GameState.invincible:
		GameState.bonus_action_used = true
		GameState.ability_bar_changed.emit()
	zealot_strike_armed = true
	GameState.game_log("[color=gold]Zealot Strike armed — your next melee attack this turn heals you.[/color]")
	# Free action — does NOT consume the turn.

# Called right before the hit/miss check in _bump_attack() (melee only — see markdowns/zealot.md:
# "your next melee attack"). Heals regardless of hit or miss, consumes 1 Hit Die.
func resolve_zealot_strike_heal() -> void:
	if not zealot_strike_armed:
		return
	zealot_strike_armed = false
	if not GameState.invincible:
		GameState.hit_dice -= 1
	var raw_roll: int = Rng.roll(GameState.hit_die_sides())
	var con_mod: int = player.stats.con_modifier()
	var heal_roll: int = maxi(1, raw_roll + con_mod)
	var before: int = player.stats.current_hp
	var overheal: int = maxi(0, (before + heal_roll) - player.stats.max_hp)
	var bruiser_bonus: int = GameState.heal(heal_roll)
	var healed: int = player.stats.current_hp - before
	if healed > 0:
		var bonus_sources: String = CombatMath.encode_bonus_sources([{"name": "Bruiser", "amount": bruiser_bonus, "color": "cyan"}])
		var _hm: String = "heal:dice=1,sides=%d,con=%d,roll=%d,bonus=%s,total=%d" % [GameState.hit_die_sides(), con_mod, raw_roll, bonus_sources, healed]
		GameState.game_log("[color=lime]Zealot Strike mends your wounds ([url=%s]+%d HP[/url]).[/color]" % [_hm, healed])

	var shield_rank: int = GameState.get_talent_rank("overheal_shield")
	if shield_rank >= 1:
		var thp: int = 0
		match shield_rank:
			1: thp = overheal
			2: thp = heal_roll
			3: thp = heal_roll + overheal
		if thp > 0:
			player.stats.temp_hp = thp  # replace, not stack
			GameState.player_hp_changed.emit(player.stats.current_hp, player.stats.max_hp)
			GameState.game_log("[color=cyan]Overheal Shield: %d temp HP.[/color]" % thp)

	if GameState.get_talent_rank("judgement_day") >= 1:
		judgement_day_pending = true

# Radiant vs Necrotic — the full Morale/NPC-reputation system described in markdowns/zealot.md
# is out of scope for this pass; defaults to Radiant (see GameState._build_judgement_day_bonus()).
func judgement_day_damage_type() -> String:
	return "Radiant"
