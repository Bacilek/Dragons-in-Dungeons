class_name PlayerAasimar
extends Node

# Aasimar race abilities: Healing Hands + Celestial Revelation. Composition child-node split out
# of player.gd — see scripts/entities/CLAUDE.md's "Aasimar" section. Celestial Resistance/
# Darkvision are plain Stats.apply_race_defaults() fields; Light Bearer is just a granted "light"
# cantrip ability (GameState.give_race_starting_items()) — no code lives here for either.

var player: Player

var healing_hands_mode_active: bool = false

const TRANSFORM_NAMES: Array[String] = ["Heavenly Wings", "Inner Radiance", "Necrotic Shroud"]
const TRANSFORM_DESCRIPTIONS: Array[String] = [
	"Sprout wings and take to the air for 10 turns — cross chasms freely, no grass trample, no traps triggered, immune to standing-fire damage.",
	"Radiant light bursts from you, dealing proficiency-bonus Radiant damage to every enemy within 2 tiles — and bursts again at the end of every one of your turns for 10 turns. +2 FOV radius while active.",
	"A shroud of graveyard shadow wreathes you — every enemy within 2 tiles must succeed a CHA save or become Frightened of you for 2 turns.",
]

# ── Healing Hands ──────────────────────────────────────────────────────────────────
# Arm-then-click targeting (same shape as Grip of the Forest's hook mode). Only two valid touch
# targets exist in this engine (self, or the Companion) — no general ally-targeting system exists
# (see Mage Armor/Invisibility's own "touch yourself only" precedent) — so the click's ONLY job is
# picking between them: clicking the Companion's own tile heals it, any other click heals the
# player. Costs the player's action (unlike every other race ability in this file, which are free).
func activate_healing_hands() -> void:
	if healing_hands_mode_active:
		cancel_healing_hands()
		return
	if not player.stats.aasimar_healing_hands_available and not GameState.invincible:
		return
	healing_hands_mode_active = true
	GameState.game_log("[color=lime]Healing Hands armed — click your companion to heal it, or click anywhere else to heal yourself. Costs your action.[/color]")

func cancel_healing_hands() -> void:
	if healing_hands_mode_active:
		healing_hands_mode_active = false
		GameState.game_log("[color=gray]Healing Hands cancelled.[/color]")

func resolve_healing_hands(clicked: Vector2i) -> void:
	healing_hands_mode_active = false
	var companion: Companion = GameState.player_companion
	var heal_companion: bool = companion != null and is_instance_valid(companion) and companion.grid_pos == clicked
	TurnManager.begin_player_action()
	if not GameState.invincible:
		player.stats.aasimar_healing_hands_available = false
	GameState._sync_ability_uses()
	# "d4 × proficiency bonus" reads as proficiency_bonus SEPARATE d4 dice summed (e.g. 2d4/3d4),
	# not one d4 roll multiplied by the bonus — bugfix, was the latter (a single 1-4 roll scaled up,
	# which is both a much smaller expected total and a much narrower variance than the real dice
	# pool it's meant to represent).
	var prof: int = player.stats.proficiency_bonus
	var rolls: Array[int] = Rng.roll_dice(prof, 4)
	var amount: int = 0
	for r: int in rolls:
		amount += r
	var rolls_str: String = "+".join(rolls.map(func(r: int) -> String: return str(r)))
	if heal_companion:
		companion.stats.current_hp = mini(companion.stats.max_hp, companion.stats.current_hp + amount)
		GameState.game_log("[color=lime]Healing Hands: %s is healed for %d (%dd4: %s) HP.[/color]" % [
			companion.animal_name, amount, prof, rolls_str])
	else:
		GameState.heal(amount)
		GameState.game_log("[color=lime]Healing Hands: you are healed for %d (%dd4: %s) HP.[/color]" % [
			amount, prof, rolls_str])
	player._handle_post_attack_turn()

# ── Celestial Revelation ───────────────────────────────────────────────────────────
# Opens a 3-option click-to-choose picker overlay (celestial_revelation_picker.gd) instead of the
# old arm-cycle-cancel-then-click-anywhere flow (bugfix/redesign, direct owner request — the old
# flow just silently rotated through choices with no visible list of what was even on offer).
func activate_celestial_revelation() -> void:
	if player.stats.character_level < 3:
		return
	if player.stats.aasimar_celestial_revelation_used and not GameState.invincible:
		return
	var picker: Node = load("res://scripts/ui/celestial_revelation_picker.gd").new()
	picker.aasimar = self
	player.get_tree().root.add_child(picker)

func resolve_celestial_revelation_choice(transform: int) -> void:
	if not GameState.invincible:
		player.stats.aasimar_celestial_revelation_used = true
	GameState._sync_ability_uses()
	player.stats.celestial_revelation_turns = 10
	player.stats.celestial_revelation_transform = transform
	player.stats.celestial_revelation_bonus_used_this_turn = false
	var dtype: String = "Necrotic" if transform == Stats.AasimarTransformation.NECROTIC_SHROUD else "Radiant"
	GameState.game_log("[color=#ffe9a8]Celestial Revelation: %s! For 10 turns, the first damage you deal each turn is boosted by %d %s.[/color]" % [
		TRANSFORM_NAMES[transform], player.stats.proficiency_bonus, dtype])
	match transform:
		Stats.AasimarTransformation.HEAVENLY_WINGS:
			# Reuses Draconic Flight's own field/mechanism outright (chasm crossing, no grass
			# trample, no trap trigger, immune to standing-fire damage, ticked by the same
			# draconic_flight_turns countdown in player.gd's _on_turn_started()) — "no separate
			# copy needed" precedent, same as High Elf reusing Misty Step.
			player.stats.draconic_flight_turns = maxi(player.stats.draconic_flight_turns, 10)
			GameState.game_log("[color=cyan]Heavenly Wings unfurl — you take to the air.[/color]")
		Stats.AasimarTransformation.INNER_RADIANCE:
			_burst_inner_radiance()
		Stats.AasimarTransformation.NECROTIC_SHROUD:
			_burst_necrotic_shroud()
	GameState.player_status_changed.emit()
	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)

## Called once per real player turn from player.gd's _on_turn_started() tick block, right after
## celestial_revelation_turns decrements — re-bursts Inner Radiance at the end of every turn while
## it's still the active transformation, not just once on activation (bugfix/redesign, direct
## owner request: "the passive damage from this choice should proc at the end of ALL my turns
## while Celestial Revelation lasts, not just the first"). No-ops for the other two
## transformations and once the effect has fully expired.
func tick_inner_radiance() -> void:
	if player.stats.celestial_revelation_turns <= 0:
		return
	if player.stats.celestial_revelation_transform != Stats.AasimarTransformation.INNER_RADIANCE:
		return
	_burst_inner_radiance()

# Inner Radiance: proficiency-bonus Radiant damage to every enemy within 2 tiles — fires once on
# activation AND again at the end of every subsequent turn while Inner Radiance stays the active
# transformation (see tick_inner_radiance() above), mirrors Thunderclap's self-centered burst shape.
func _burst_inner_radiance() -> void:
	var dungeon_floor: Node = player._dungeon_floor
	if dungeon_floor == null:
		return
	var prof: int = player.stats.proficiency_bonus
	GameState.game_log("[color=#ffe9a8]Radiant light bursts from you![/color]")
	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if e.min_dist_to(player.grid_pos) > 2:
			continue
		e.on_disturbed(player.grid_pos)
		var result: Dictionary = e.take_typed_damage(prof, "Radiant")
		var actual: int = result["actual"]
		e.update_hp_bar()
		dungeon_floor.show_damage(e.position, actual, false, CombatMath.damage_type_color("Radiant"))
		var is_lethal: bool = e.stats.is_dead()
		GameState.game_log("%s is seared by radiant light for [color=yellow]%d[/color] dmg.%s" % [e.display_name, actual, CombatMath.death_suffix(is_lethal)])
		if is_lethal:
			player._finish_kill(e)

# Necrotic Shroud: every enemy within 2 tiles rolls a CHA check (8 + CHA mod + prof) or becomes
# Frightened. Simplified vs. RAW "until the end of your next turn" — fixed 2-turn duration instead
# (see Enemy.frightened_turns' own comment, same precedent as Mind Sliver's penalty die).
func _burst_necrotic_shroud() -> void:
	var dungeon_floor: Node = player._dungeon_floor
	if dungeon_floor == null:
		return
	var dc: int = 8 + player.stats.cha_modifier() + player.stats.proficiency_bonus
	GameState.game_log("[color=#8b5ea8]A shroud of graveyard shadow wreathes you![/color]")
	for e: Enemy in dungeon_floor.get_all_enemies():
		if not is_instance_valid(e) or e.stats.is_dead():
			continue
		if e.min_dist_to(player.grid_pos) > 2:
			continue
		e.on_disturbed(player.grid_pos)
		var save: Dictionary = e.resist_check_detailed(dc, false, false, false, false, false, true)
		var save_meta: String = "save:die=%d,mod=%d,prof=%d,prof_label=%s,total=%d,dc=%d,stat=%s,pass=%d,sliver=%d" % [
			save["die"], save["mod"], save["floor_bonus"], save["prof_label"], save["total"], save["dc"], save["stat"], int(save["pass"]), save["sliver_penalty"]]
		if save["pass"]:
			GameState.game_log("%s [url=%s]resists[/url] your necrotic shroud." % [e.display_name, save_meta])
		else:
			e.apply_status("frightened", 2)
			e.frightened_source = player
			GameState.game_log("%s is [url=%s]frightened[/url] by your necrotic shroud!" % [e.display_name, save_meta])
