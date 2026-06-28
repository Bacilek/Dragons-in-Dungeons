extends CanvasLayer

const PANEL_W: float = 580.0
const ROW_H: float = 90.0
const ROW_PAD: float = 12.0

var _invest_btns: Array[Button] = []
var _rank_labels: Array[Label] = []
var _next_desc_labels: Array[RichTextLabel] = []
var _points_label: Label

func _ready() -> void:
	layer = 25
	GameState.talent_picker_open = true
	_build_ui()

func _build_ui() -> void:
	var talents: Array[Talent] = _get_class_talents()
	var n: int = talents.size()
	var header_h: float = 80.0
	var footer_h: float = 64.0
	var panel_h: float = header_h + n * (ROW_H + ROW_PAD) + footer_h

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(PANEL_W, panel_h)
	var vp := get_viewport().get_visible_rect().size
	panel.position = (vp - panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	# Title
	var title := Label.new()
	title.text = "Level Up! Choose a Talent"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(PANEL_W, 34.0)
	title.position = Vector2(0.0, 12.0)
	panel.add_child(title)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 14)
	_points_label.add_theme_color_override("font_color", Color(0.6, 0.7, 0.6))
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.size = Vector2(PANEL_W, 22.0)
	_points_label.position = Vector2(0.0, 48.0)
	panel.add_child(_points_label)

	var sep := HSeparator.new()
	sep.position = Vector2(14.0, 74.0)
	sep.size = Vector2(PANEL_W - 28.0, 2.0)
	panel.add_child(sep)

	# Talent rows
	for i: int in n:
		var t: Talent = talents[i]
		var row_y: float = header_h + i * (ROW_H + ROW_PAD)
		_build_talent_row(panel, t, i, row_y)

	# Footer
	var sep2 := HSeparator.new()
	sep2.position = Vector2(14.0, header_h + n * (ROW_H + ROW_PAD))
	sep2.size = Vector2(PANEL_W - 28.0, 2.0)
	panel.add_child(sep2)

	var skip_btn := Button.new()
	skip_btn.text = "Skip  [Esc]"
	skip_btn.size = Vector2(180.0, 44.0)
	skip_btn.position = Vector2((PANEL_W - 180.0) * 0.5, header_h + n * (ROW_H + ROW_PAD) + 10.0)
	skip_btn.add_theme_font_size_override("font_size", 15)
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.pressed.connect(_close)
	_style_btn(skip_btn)
	panel.add_child(skip_btn)

	_refresh()

func _build_talent_row(parent: Control, t: Talent, idx: int, row_y: float) -> void:
	# Icon
	var icon := TextureRect.new()
	if t.icon_path != "":
		var tex := load(t.icon_path) as Texture2D
		if tex != null:
			icon.texture = tex
	icon.size = Vector2(48.0, 48.0)
	icon.position = Vector2(14.0, row_y + (ROW_H - 48.0) * 0.5)
	icon.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	parent.add_child(icon)

	# Name + rank pips
	var name_lbl := Label.new()
	name_lbl.text = t.talent_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	name_lbl.position = Vector2(72.0, row_y + 4.0)
	name_lbl.size = Vector2(250.0, 24.0)
	parent.add_child(name_lbl)

	# Rank pips label (e.g. "● ● ○" for rank 2/3)
	var rank_lbl := Label.new()
	rank_lbl.add_theme_font_size_override("font_size", 14)
	rank_lbl.add_theme_color_override("font_color", Color(0.6, 0.8, 0.6))
	rank_lbl.position = Vector2(72.0, row_y + 30.0)
	rank_lbl.size = Vector2(200.0, 22.0)
	parent.add_child(rank_lbl)
	_rank_labels.append(rank_lbl)

	# Next rank description (what you'd get)
	var desc := RichTextLabel.new()
	desc.bbcode_enabled = true
	desc.fit_content = true
	desc.scroll_active = false
	desc.add_theme_font_size_override("normal_font_size", 12)
	desc.add_theme_color_override("default_color", Color(0.55, 0.65, 0.55))
	desc.size = Vector2(270.0, ROW_H - 8.0)
	desc.position = Vector2(72.0, row_y + 54.0)
	parent.add_child(desc)
	_next_desc_labels.append(desc)

	# Invest button
	var btn := Button.new()
	btn.text = "Invest"
	btn.size = Vector2(110.0, 48.0)
	btn.position = Vector2(PANEL_W - 130.0, row_y + (ROW_H - 48.0) * 0.5)
	btn.add_theme_font_size_override("font_size", 15)
	btn.focus_mode = Control.FOCUS_NONE
	var talent_id: String = t.talent_id
	btn.pressed.connect(func() -> void: _on_invest(talent_id))
	_style_invest_btn(btn)
	parent.add_child(btn)
	_invest_btns.append(btn)

func _refresh() -> void:
	_points_label.text = "Talent points: %d remaining" % GameState.talent_points_available
	var talents: Array[Talent] = _get_class_talents()
	for i: int in talents.size():
		var t: Talent = talents[i]
		var current: int = GameState.get_talent_rank(t.talent_id)
		# Rank pips
		var pip_str: String = ""
		for r: int in t.max_rank:
			pip_str += ("●" if r < current else "○")
			if r < t.max_rank - 1:
				pip_str += " "
		_rank_labels[i].text = "Rank %d / %d  %s" % [current, t.max_rank, pip_str]
		# Next rank description
		if current < t.max_rank:
			var next_rank_data: String = t.rank_description(current + 1)
			_next_desc_labels[i].text = "[color=gray]Next:[/color] " + next_rank_data
		else:
			_next_desc_labels[i].text = "[color=gray]Maxed out.[/color]"
		# Invest button enabled only if can invest
		_invest_btns[i].disabled = not GameState.can_invest_talent(t.talent_id)

func _on_invest(talent_id: String) -> void:
	if not GameState.can_invest_talent(talent_id):
		return
	GameState.invest_talent(talent_id)
	_refresh()
	if GameState.talent_points_available <= 0:
		_close()

func _close() -> void:
	GameState.talent_picker_open = false
	queue_free()

func _get_class_talents() -> Array[Talent]:
	return GameState._class_talents

func _style_btn(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.14, 0.14, 0.22, 1.0)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.38, 0.38, 0.55)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.24, 0.24, 0.38, 1.0)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)

func _style_invest_btn(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.22, 0.12, 1.0)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.28, 0.65, 0.28)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.36, 0.18, 1.0)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.12, 0.12, 0.12, 0.5)
	disabled.set_border_width_all(1)
	disabled.border_color = Color(0.25, 0.25, 0.25)
	disabled.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("disabled", disabled)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
