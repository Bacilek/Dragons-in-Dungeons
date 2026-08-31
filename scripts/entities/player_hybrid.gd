class_name PlayerHybrid
extends Node

# Composition child-node on Player (`_hybrid`), same pattern as PlayerOrc / PlayerMonk.
# Owns arming / targeting for the Hybrid class's ability kit; HybridEffects does the resolution.
# docs/architecture/hybrid-class-design.md

var player: Player

# Click-targeting mode (enemy / tile / sphere abilities) - armed ability id, "" = inactive.
var targeting_id: String = ""
# Direction-dash mode (emberstep) - armed ability id, "" = inactive.
var dash_id: String = ""
var _armed_ab: Ability = null

func get_rewind_fields() -> Dictionary:
	return {"targeting_id": targeting_id, "dash_id": dash_id}

func set_rewind_fields(d: Dictionary) -> void:
	targeting_id = str(d.get("targeting_id", ""))
	dash_id = str(d.get("dash_id", ""))

func is_targeting() -> bool:
	return targeting_id != "" or dash_id != ""

func cancel() -> void:
	if is_targeting():
		GameState.game_log("[color=gray]%s cancelled.[/color]" % HybridAbilityDb.get_def(_armed_id()).get("name", "Ability"))
	targeting_id = ""
	dash_id = ""
	_armed_ab = null

func _armed_id() -> String:
	return targeting_id if targeting_id != "" else dash_id

# ── activation (from player.gd._use_ability_slot dispatch) ───────────────────
func activate(ab: Ability) -> void:
	var def: Dictionary = HybridAbilityDb.get_def(ab.ability_id)
	if def.is_empty():
		return
	if str(def.get("power_type", "")) == "passive":
		GameState.game_log("[color=gray]%s is passive.[/color]" % def.get("name", ab.ability_name))
		return
	# re-arming the same ability toggles targeting off (always allowed)
	if is_targeting() and _armed_id() == ab.ability_id:
		cancel()
		return
	if not GameState.is_ability_usable(ab):
		GameState.game_log("[color=gray]%s: %s.[/color]" % [def.get("name", ab.ability_name), GameState.ability_unusable_reason(ab)])
		return
	_armed_ab = ab
	match str(def.get("target", "self")):
		"self":
			_pay(ab)
			# no self-target ability shipped yet - placeholder
			GameState.game_log("[color=gray]%s has no effect yet.[/color]" % def.get("name", ""))
		"direction":
			dash_id = ab.ability_id
			GameState.game_log("[color=cyan]%s armed - press a direction or click a tile.[/color]" % def.get("name", ""))
		_:
			targeting_id = ab.ability_id
			GameState.game_log("[color=cyan]%s armed - click a target.[/color]" % def.get("name", ""))

# ── click resolution (from player.gd mouse-release handler) ─────────────────
func resolve_click(clicked: Vector2i) -> void:
	var id: String = targeting_id if targeting_id != "" else dash_id
	var ab: Ability = _armed_ab
	targeting_id = ""
	dash_id = ""
	_armed_ab = null
	if id == "" or ab == null or player._dungeon_floor == null:
		return
	var def: Dictionary = HybridAbilityDb.get_def(id)
	var df: Node = player._dungeon_floor
	var reach: int = int(def.get("range", 4))
	var d: Vector2i = clicked - player.grid_pos

	match str(def.get("effect", "")):
		"spark":
			var e: Enemy = df.get_targetable_enemy_at(clicked)
			if e == null:
				GameState.game_log("[color=gray]Spark: no target there.[/color]")
				return
			if maxi(absi(d.x), absi(d.y)) > reach or not df.has_ranged_los(player.grid_pos, clicked):
				GameState.game_log("[color=gray]Spark: target out of range.[/color]")
				return
			_pay(ab)
			await HybridEffects.spark(player, def, e, df)
		"tide":
			if maxi(absi(d.x), absi(d.y)) > reach:
				GameState.game_log("[color=gray]Tide: too far.[/color]")
				return
			_pay(ab)
			await HybridEffects.tide(player, def, clicked, df)
		"arc":
			if maxi(absi(d.x), absi(d.y)) > reach:
				GameState.game_log("[color=gray]Arc: too far.[/color]")
				return
			_pay(ab)
			await HybridEffects.arc(player, def, clicked, df)
		"emberstep":
			_pay(ab)
			await HybridEffects.emberstep(player, def, clicked, df)

func resolve_dash(dir_tile: Vector2i) -> void:
	# dir_tile is an adjacent tile (WASD-derived); project it to the ability's full range.
	var id: String = dash_id
	var ab: Ability = _armed_ab
	dash_id = ""
	_armed_ab = null
	if id == "" or ab == null or player._dungeon_floor == null:
		return
	var def: Dictionary = HybridAbilityDb.get_def(id)
	var step: Vector2i = dir_tile - player.grid_pos
	var far: Vector2i = player.grid_pos + step * int(def.get("range", 3))
	_pay(ab)
	await HybridEffects.emberstep(player, def, far, player._dungeon_floor)

# ── resource payment ──────────────────────────────────────────────────────────
func _pay(ab: Ability) -> void:
	if GameState.invincible:
		return
	var def: Dictionary = HybridAbilityDb.get_def(ab.ability_id)
	if int(def.get("essence_cost", 0)) > 0:
		GameState.spend_hybrid_essence(int(def["essence_cost"]))
	if int(def.get("cooldown", 0)) > 0:
		ab.cooldown_remaining = int(def["cooldown"])
		# Don't let this turn's own _on_turn_ending() tick immediately count down the cooldown.
		if not player._hybrid_cd_skip_this_turn.has(ab.ability_id):
			player._hybrid_cd_skip_this_turn.append(ab.ability_id)
	GameState.ability_bar_changed.emit()
