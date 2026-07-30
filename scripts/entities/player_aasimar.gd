class_name PlayerAasimar
extends Node

# Aasimar race abilities: Healing Hands + Celestial Revelation. Composition child-node split out
# of player.gd — see scripts/entities/CLAUDE.md's "Aasimar" section. Celestial Resistance/
# Darkvision are plain Stats.apply_race_defaults() fields; Light Bearer is just a granted "light"
# cantrip ability (GameState.give_race_starting_items()) — no code lives here for either.

var player: Player

var healing_hands_mode_active: bool = false
var celestial_revelation_mode_active: bool = false
var celestial_revelation_pending_transform: int = Stats.AasimarTransformation.HEAVENLY_WINGS

const TRANSFORM_NAMES: Array[String] = ["Heavenly Wings", "Inner Radiance", "Necrotic Shroud"]

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
		GameState.game_log("[color=gray]Healing Hands: no use remaining (long rest to recover).[/color]")
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
	var die: int = Rng.roll(4)
	var amount: int = die * player.stats.proficiency_bonus
	if heal_companion:
		companion.stats.current_hp = mini(companion.stats.max_hp, companion.stats.current_hp + amount)
		GameState.game_log("[color=lime]Healing Hands: %s is healed for %d (1d4=%d × prof %d) HP.[/color]" % [
			companion.animal_name, amount, die, player.stats.proficiency_bonus])
	else:
		GameState.heal(amount)
		GameState.game_log("[color=lime]Healing Hands: you are healed for %d (1d4=%d × prof %d) HP.[/color]" % [
			amount, die, player.stats.proficiency_bonus])
	player._handle_post_attack_turn()

# ── Celestial Revelation ───────────────────────────────────────────────────────────
# Arm-cycle-cancel targeting, one step further than Breath Weapon's own Cone<->Line toggle since
# there are 3 choices instead of 2: 1st press arms Heavenly Wings, 2nd press (same slot) cycles to
# Inner Radiance, 3rd to Necrotic Shroud, 4th cancels. ANY world click confirms/activates whichever
# choice is currently selected (Mage Armor's "any click confirms a self-cast" convention — there's
# nothing to aim, the click is purely a confirm gesture).
func activate_celestial_revelation() -> void:
	if celestial_revelation_mode_active:
		celestial_revelation_pending_transform += 1
		if celestial_revelation_pending_transform > Stats.AasimarTransformation.NECROTIC_SHROUD:
			celestial_revelation_mode_active = false
			GameState.game_log("[color=gray]Celestial Revelation cancelled.[/color]")
			return
		GameState.game_log("[color=lime]Celestial Revelation: %s selected. Click again to cycle, click anywhere to activate.[/color]" % TRANSFORM_NAMES[celestial_revelation_pending_transform])
		return
	if player.stats.character_level < 3:
		return
	if player.stats.aasimar_celestial_revelation_used and not GameState.invincible:
		GameState.game_log("[color=gray]Celestial Revelation: already used this long rest.[/color]")
		return
	celestial_revelation_mode_active = true
	celestial_revelation_pending_transform = Stats.AasimarTransformation.HEAVENLY_WINGS
	GameState.game_log("[color=lime]Celestial Revelation armed — %s selected. Click again to cycle choice, click anywhere to activate.[/color]" % TRANSFORM_NAMES[0])

func cancel_celestial_revelation() -> void:
	if celestial_revelation_mode_active:
		celestial_revelation_mode_active = false
		GameState.game_log("[color=gray]Celestial Revelation cancelled.[/color]")

func resolve_celestial_revelation() -> void:
	celestial_revelation_mode_active = false
	var transform: int = celestial_revelation_pending_transform
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

# Inner Radiance: instant proficiency-bonus Radiant damage to every enemy within 2 tiles (once, on
# activation) — mirrors Thunderclap's self-centered burst shape.
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
			GameState.game_log("%s is [url=%s]frightened[/url] by your necrotic shroud!" % [e.display_name, save_meta])
