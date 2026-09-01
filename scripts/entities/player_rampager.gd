class_name PlayerRampager
extends Node

# Composition child-node on Player (`_rampager`), mirrors PlayerHybrid exactly — the Rampager runs
# on the same cooldown + nova economy (Fury in place of Essence).
# docs/architecture/rampager-class-design.md

var player: Player

var targeting_id: String = ""   # tile / sphere abilities (shockwave)
var dash_id: String = ""        # direction-dash abilities (overrun)
var _armed_ab: Ability = null

func get_rewind_fields() -> Dictionary:
	return {"targeting_id": targeting_id, "dash_id": dash_id}

func set_rewind_fields(d: Dictionary) -> void:
	targeting_id = str(d.get("targeting_id", ""))
	dash_id = str(d.get("dash_id", ""))

func is_targeting() -> bool:
	return targeting_id != "" or dash_id != ""

func _armed_id() -> String:
	return targeting_id if targeting_id != "" else dash_id

func cancel() -> void:
	if is_targeting():
		GameState.game_log("[color=gray]%s cancelled.[/color]" % RampagerAbilityDb.get_def(_armed_id()).get("name", "Ability"))
	targeting_id = ""
	dash_id = ""
	_armed_ab = null

# ── activation (from player.gd._use_ability_slot dispatch) ───────────────────
func activate(ab: Ability) -> void:
	var def: Dictionary = RampagerAbilityDb.get_def(ab.ability_id)
	if def.is_empty():
		return
	if str(def.get("power_type", "")) == "passive":
		GameState.game_log("[color=gray]%s is passive.[/color]" % def.get("name", ab.ability_name))
		return
	if is_targeting() and _armed_id() == ab.ability_id:
		cancel()
		return
	if not GameState.is_ability_usable(ab):
		GameState.game_log("[color=gray]%s: %s.[/color]" % [def.get("name", ab.ability_name), GameState.ability_unusable_reason(ab)])
		return
	_armed_ab = ab
	match str(def.get("target", "self")):
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
	var def: Dictionary = RampagerAbilityDb.get_def(id)
	var df: Node = player._dungeon_floor
	var reach: int = int(def.get("range", 4))
	var d: Vector2i = clicked - player.grid_pos

	match str(def.get("effect", "")):
		"overrun":
			var step: Vector2i = Vector2i(signi(d.x), signi(d.y))
			if step == Vector2i.ZERO:
				return
			var far: Vector2i = player.grid_pos + step * reach
			_pay(ab)
			await RampagerEffects.overrun(player, def, far, df)
		"shockwave":
			if maxi(absi(d.x), absi(d.y)) > reach:
				GameState.game_log("[color=gray]Shockwave: too far.[/color]")
				return
			_pay(ab)
			await RampagerEffects.shockwave(player, def, clicked, df)

func resolve_dash(dir_tile: Vector2i) -> void:
	var id: String = dash_id
	var ab: Ability = _armed_ab
	dash_id = ""
	_armed_ab = null
	if id == "" or ab == null or player._dungeon_floor == null:
		return
	var def: Dictionary = RampagerAbilityDb.get_def(id)
	var step: Vector2i = dir_tile - player.grid_pos
	var far: Vector2i = player.grid_pos + step * int(def.get("range", 4))
	_pay(ab)
	await RampagerEffects.overrun(player, def, far, player._dungeon_floor)

# ── resource payment (mirrors PlayerHybrid._pay) ────────────────────────────
func _pay(ab: Ability) -> void:
	if GameState.invincible:
		return
	var def: Dictionary = RampagerAbilityDb.get_def(ab.ability_id)
	if int(def.get("fury_cost", 0)) > 0:
		GameState.spend_rampager_fury(int(def["fury_cost"]))
	if int(def.get("cooldown", 0)) > 0:
		ab.cooldown_remaining = int(def["cooldown"])
		if not player._hybrid_cd_skip_this_turn.has(ab.ability_id):
			player._hybrid_cd_skip_this_turn.append(ab.ability_id)
	GameState.ability_bar_changed.emit()
