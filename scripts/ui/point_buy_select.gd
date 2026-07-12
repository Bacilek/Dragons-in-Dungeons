extends CanvasLayer

# Point-buy ability score allocation — Custom character creation path only (premade heroes
# bypass class_select.gd entirely and never reach this screen). Spawned by
# class_select.gd._on_class_selected() right after apply_class_defaults()/class_chosen, before
# race_select.gd. D&D 2024 rules: no racial ability-score bonuses (race is chosen after this
# screen and never touches base scores — Stats.apply_race_defaults()), so this is the only
# ability-score input in the whole onboarding flow. Modeled on race_select.gd's conventions:
# dim overlay + centered bordered Panel, focus_mode = FOCUS_NONE everywhere, blocks input via
# GameState.point_buy_open, non-dismissible (no close button, Esc ignored).

const PANEL_W: float = 520.0
const MARGIN: float = 24.0
const ROW_H: float = 40.0
const STEP_BTN_SIZE: float = 32.0

const ORDER: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const LABELS: Dictionary = {
	"str": "Strength", "dex": "Dexterity", "con": "Constitution",
	"int": "Intelligence", "wis": "Wisdom", "cha": "Charisma",
}

var _scores: Dictionary = {"str": 8, "dex": 8, "con": 8, "int": 8, "wis": 8, "cha": 8}
var _value_labels: Dictionary = {}   # key -> Label
var _minus_btns: Dictionary = {}     # key -> Button
var _plus_btns: Dictionary = {}      # key -> Button
var _points_label: Label
var _confirm_btn: Button
var _panel: Panel

func _ready() -> void:
	layer = 22
	GameState.point_buy_open = true
	_build_ui()
	_refresh()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Allocate Ability Scores"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "Point buy — 27 points, scores range 8-15. 14 and 15 cost 2 points per step."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 90.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 102.0
	for i: int in ORDER.size():
		_build_row(ORDER[i], Vector2(MARGIN, y0 + float(i) * ROW_H))

	var rows_h: float = float(ORDER.size()) * ROW_H

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 16)
	_points_label.position = Vector2(MARGIN, y0 + rows_h + 10.0)
	_points_label.size = Vector2(PANEL_W - MARGIN * 2.0, 26.0)
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_panel.add_child(_points_label)

	var confirm_y: float = y0 + rows_h + 44.0
	_confirm_btn = Button.new()
	_confirm_btn.text = "Confirm"
	_confirm_btn.size = Vector2(220.0, 44.0)
	_confirm_btn.position = Vector2((PANEL_W - 220.0) * 0.5, confirm_y)
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.add_theme_font_size_override("font_size", 16)
	_style_btn(_confirm_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	_confirm_btn.pressed.connect(_on_confirm)
	_panel.add_child(_confirm_btn)

	var panel_h: float = confirm_y + 44.0 + 20.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

func _build_row(key: String, pos: Vector2) -> void:
	var name_lbl := Label.new()
	name_lbl.text = LABELS[key]
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.90, 0.94))
	name_lbl.position = pos + Vector2(0.0, 4.0)
	name_lbl.size = Vector2(150.0, 28.0)
	_panel.add_child(name_lbl)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.size = Vector2(STEP_BTN_SIZE, STEP_BTN_SIZE)
	minus_btn.position = pos + Vector2(170.0, 0.0)
	minus_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(minus_btn, Color(0.18, 0.10, 0.10), Color(0.55, 0.28, 0.28))
	minus_btn.pressed.connect(_on_minus.bind(key))
	_panel.add_child(minus_btn)
	_minus_btns[key] = minus_btn

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 17)
	value_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.position = pos + Vector2(210.0, 3.0)
	value_lbl.size = Vector2(110.0, 28.0)
	_panel.add_child(value_lbl)
	_value_labels[key] = value_lbl

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size = Vector2(STEP_BTN_SIZE, STEP_BTN_SIZE)
	plus_btn.position = pos + Vector2(328.0, 0.0)
	plus_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(plus_btn, Color(0.10, 0.18, 0.10), Color(0.28, 0.55, 0.28))
	plus_btn.pressed.connect(_on_plus.bind(key))
	_panel.add_child(plus_btn)
	_plus_btns[key] = plus_btn

func _points_spent() -> int:
	var total: int = 0
	for key: String in ORDER:
		total += Stats.POINT_BUY_COST[_scores[key]]
	return total

func _points_remaining() -> int:
	return Stats.POINT_BUY_BUDGET - _points_spent()

func _on_plus(key: String) -> void:
	var score: int = _scores[key]
	if score >= Stats.POINT_BUY_MAX:
		return
	var step_cost: int = Stats.POINT_BUY_COST[score + 1] - Stats.POINT_BUY_COST[score]
	if _points_remaining() < step_cost:
		return
	_scores[key] = score + 1
	_refresh()

func _on_minus(key: String) -> void:
	var score: int = _scores[key]
	if score <= Stats.POINT_BUY_MIN:
		return
	_scores[key] = score - 1
	_refresh()

func _refresh() -> void:
	for key: String in ORDER:
		var score: int = _scores[key]
		var mod: int = floori((score - 10) / 2.0)
		var mod_str: String = ("+%d" % mod) if mod >= 0 else str(mod)
		(_value_labels[key] as Label).text = "%d (%s)" % [score, mod_str]
		(_minus_btns[key] as Button).disabled = score <= Stats.POINT_BUY_MIN
		var next_cost: int = 0
		if score < Stats.POINT_BUY_MAX:
			next_cost = Stats.POINT_BUY_COST[score + 1] - Stats.POINT_BUY_COST[score]
		(_plus_btns[key] as Button).disabled = score >= Stats.POINT_BUY_MAX or _points_remaining() < next_cost

	var remaining: int = _points_remaining()
	_points_label.text = "Points remaining: %d / %d" % [remaining, Stats.POINT_BUY_BUDGET]
	_points_label.add_theme_color_override("font_color",
			Color(1.0, 0.82, 0.22) if remaining > 0 else Color(0.6, 0.85, 0.6))

func _on_confirm() -> void:
	GameState.player_stats.apply_point_buy_scores(_scores)
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.point_buy_open = false
	var race_picker = load("res://scripts/ui/race_select.gd").new()
	get_tree().root.call_deferred("add_child", race_picker)
	queue_free()

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_border_width_all(1)
	normal.border_color = border
	normal.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.12)
	hover.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", hover)
	var dis_sbox := StyleBoxFlat.new()
	dis_sbox.bg_color = Color(0.10, 0.10, 0.10, 0.5)
	dis_sbox.set_border_width_all(1)
	dis_sbox.border_color = Color(0.22, 0.22, 0.22)
	btn.add_theme_stylebox_override("disabled", dis_sbox)

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time allocation — swallow all key input (no Esc close) so nothing
	# leaks to gameplay handlers underneath.
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
