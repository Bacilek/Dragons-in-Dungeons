extends CanvasLayer

# Background ability-score bonus — Custom character creation path only, D&D 2024 rules (a
# background's ability-score increase replaces 5e's racial ASI; race never touches base scores —
# Stats.apply_race_defaults()). Spawned by point_buy_select.gd._on_confirm() right after point
# buy confirms, before race_select.gd. 3 points to distribute across the six scores, max 2 into
# any single score — a point-buy 15 can freely become 17, or two different 15s can each become
# 16. Modeled directly on point_buy_select.gd's conventions (dim overlay + centered bordered
# Panel, focus_mode = FOCUS_NONE everywhere, GameState.background_select_open input-gate flag,
# non-dismissible — no close button, Esc ignored).

const PANEL_W: float = 620.0
const MARGIN: float = 24.0
const ROW_H: float = 40.0
const STEP_BTN_SIZE: float = 32.0

const ORDER: Array[String] = ["str", "dex", "con", "int", "wis", "cha"]
const LABELS: Dictionary = {
	"str": "Strength", "dex": "Dexterity", "con": "Constitution",
	"int": "Intelligence", "wis": "Wisdom", "cha": "Charisma",
}

var _base_scores: Dictionary = {}    # key -> int, snapshot of scores right after point buy
var _bonus: Dictionary = {"str": 0, "dex": 0, "con": 0, "int": 0, "wis": 0, "cha": 0}
var _value_labels: Dictionary = {}   # key -> Label
var _minus_btns: Dictionary = {}     # key -> Button
var _plus_btns: Dictionary = {}      # key -> Button
var _points_label: Label
var _confirm_btn: Button
var _panel: Panel

func _ready() -> void:
	layer = 22
	GameState.background_select_open = true
	for key: String in ORDER:
		_base_scores[key] = GameState.player_stats.get(_stat_field(key))
	_build_ui()
	_refresh()

func _stat_field(key: String) -> String:
	match key:
		"str": return "strength"
		"dex": return "dexterity"
		"con": return "constitution"
		"int": return "intelligence"
		"wis": return "wisdom"
		_: return "charisma"

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
	title.text = "Background: Ability Score Increase"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "Your background grants 3 ability score points — put them anywhere, no more than 2 into the same score."
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
	name_lbl.size = Vector2(130.0, 28.0)
	_panel.add_child(name_lbl)

	var minus_btn := Button.new()
	minus_btn.text = "-"
	minus_btn.size = Vector2(STEP_BTN_SIZE, STEP_BTN_SIZE)
	minus_btn.position = pos + Vector2(194.0, 0.0)
	minus_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(minus_btn, Color(0.18, 0.10, 0.10), Color(0.55, 0.28, 0.28))
	minus_btn.pressed.connect(_on_minus.bind(key))
	_panel.add_child(minus_btn)
	_minus_btns[key] = minus_btn

	var value_lbl := Label.new()
	value_lbl.add_theme_font_size_override("font_size", 17)
	value_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	value_lbl.position = pos + Vector2(232.0, 3.0)
	value_lbl.size = Vector2(160.0, 28.0)
	_panel.add_child(value_lbl)
	_value_labels[key] = value_lbl

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size = Vector2(STEP_BTN_SIZE, STEP_BTN_SIZE)
	plus_btn.position = pos + Vector2(398.0, 0.0)
	plus_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(plus_btn, Color(0.10, 0.18, 0.10), Color(0.28, 0.55, 0.28))
	plus_btn.pressed.connect(_on_plus.bind(key))
	_panel.add_child(plus_btn)
	_plus_btns[key] = plus_btn

func _points_spent() -> int:
	var total: int = 0
	for key: String in ORDER:
		total += int(_bonus[key])
	return total

func _points_remaining() -> int:
	return Stats.BACKGROUND_POINTS - _points_spent()

func _on_plus(key: String) -> void:
	if int(_bonus[key]) >= Stats.BACKGROUND_MAX_PER_STAT:
		return
	if _points_remaining() <= 0:
		return
	_bonus[key] = int(_bonus[key]) + 1
	_refresh()

func _on_minus(key: String) -> void:
	if int(_bonus[key]) <= 0:
		return
	_bonus[key] = int(_bonus[key]) - 1
	_refresh()

func _refresh() -> void:
	for key: String in ORDER:
		var base: int = int(_base_scores[key])
		var bonus: int = int(_bonus[key])
		var final_score: int = base + bonus
		var mod: int = floori((final_score - 10) / 2.0)
		var mod_str: String = ("+%d" % mod) if mod >= 0 else str(mod)
		var bonus_str: String = (" (+%d)" % bonus) if bonus > 0 else ""
		(_value_labels[key] as Label).text = "%d%s -> %d (%s)" % [base, bonus_str, final_score, mod_str]
		var at_min: bool = bonus <= 0
		var at_max: bool = bonus >= Stats.BACKGROUND_MAX_PER_STAT or _points_remaining() <= 0
		(_minus_btns[key] as Button).disabled = at_min
		(_plus_btns[key] as Button).disabled = at_max

	var remaining: int = _points_remaining()
	_points_label.text = "Points remaining: %d / %d" % [remaining, Stats.BACKGROUND_POINTS]
	_points_label.add_theme_color_override("font_color",
			Color(1.0, 0.82, 0.22) if remaining > 0 else Color(0.6, 0.85, 0.6))
	_confirm_btn.disabled = remaining > 0

func _on_confirm() -> void:
	GameState.player_stats.apply_background_bonus(_bonus)
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.background_select_open = false
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
