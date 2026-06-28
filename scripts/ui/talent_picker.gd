extends CanvasLayer

const PANEL_W: float = 500.0
const ICON_SIZE: float = 36.0
const ROW_H: float = 50.0
const RANK_ROW_H: float = 46.0
const TIER_LABEL_H: float = 28.0

# Roman numerals for rank labels
const ROMAN: Array[String] = ["I", "II", "III", "IV", "V"]

var _expanded_id: String = ""
var _talent_row_nodes: Dictionary = {}  # talent_id -> {btn, rank_panel, invest_btn, pip_lbl}
var _points_label: Label
var _panel: Panel
var _vbox: VBoxContainer

func _ready() -> void:
	layer = 25
	GameState.talent_picker_open = true
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.62)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, 600.0)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - 600.0) * 0.5)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	# ── Header ──
	var title := Label.new()
	title.text = "TALENTS"
	title.add_theme_font_size_override("font_size", 20)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(PANEL_W, 30.0)
	title.position = Vector2(0.0, 10.0)
	_panel.add_child(title)

	_points_label = Label.new()
	_points_label.add_theme_font_size_override("font_size", 13)
	_points_label.add_theme_color_override("font_color", Color(0.65, 0.75, 0.65))
	_points_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_points_label.size = Vector2(PANEL_W, 20.0)
	_points_label.position = Vector2(0.0, 42.0)
	_panel.add_child(_points_label)

	var sep_top := _make_hsep(64.0)
	_panel.add_child(sep_top)

	# ── Scrollable content ──
	var scroll := ScrollContainer.new()
	scroll.position = Vector2(4.0, 70.0)
	scroll.size = Vector2(PANEL_W - 8.0, 480.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_vbox = VBoxContainer.new()
	_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_vbox.add_theme_constant_override("separation", 0)
	scroll.add_child(_vbox)

	# Tier 1 — always active
	_add_tier_header("TIER 1  ·  Levels 1–5", true)
	for t: Talent in GameState._class_talents:
		if t.tier == 1:
			_add_talent_row(t)

	# Tier 2 — Berserker (unlocked on Necromancer kill)
	if GameState.tier2_unlocked:
		_add_tier_header("TIER 2  ·  Berserker  ·  Levels 7–12", true)
		for t: Talent in GameState._class_talents:
			if t.tier == 2:
				_add_talent_row(t)
	else:
		_add_tier_header("TIER 2  ·  Berserker  ·  Levels 7–12", false)
		_add_locked_placeholder("Defeat the Necromancer (floor 10) to unlock")

	# Tiers 3–4 — locked placeholders
	var locked_tiers := [
		["TIER 3  ·  Levels 13–17", "Unlocks at Tier 3"],
		["TIER 4  ·  Levels 18–20", "Unlocks at Tier 4"],
	]
	for entry: Array in locked_tiers:
		_add_tier_header(entry[0], false)
		_add_locked_placeholder(entry[1])

	# ── Footer ──
	var sep_bot := _make_hsep(554.0)
	_panel.add_child(sep_bot)

	var skip_btn := Button.new()
	skip_btn.text = "Close  [Esc]"
	skip_btn.size = Vector2(160.0, 36.0)
	skip_btn.position = Vector2((PANEL_W - 160.0) * 0.5, 562.0)
	skip_btn.add_theme_font_size_override("font_size", 14)
	skip_btn.focus_mode = Control.FOCUS_NONE
	skip_btn.pressed.connect(_close)
	_style_btn(skip_btn, Color(0.14, 0.14, 0.22), Color(0.38, 0.38, 0.55))
	_panel.add_child(skip_btn)

	_refresh_all()

# ── Tier header ──────────────────────────────────────────────────────────────

func _add_tier_header(text: String, active: bool) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 12)
	var col: Color = Color(0.78, 0.55, 0.22) if active else Color(0.35, 0.35, 0.35)
	lbl.add_theme_color_override("font_color", col)
	lbl.custom_minimum_size = Vector2(PANEL_W - 20.0, TIER_LABEL_H)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var hb := HBoxContainer.new()
	hb.custom_minimum_size = Vector2(PANEL_W - 20.0, TIER_LABEL_H + 4.0)
	hb.add_theme_constant_override("separation", 6)
	var left_line := ColorRect.new()
	left_line.color = col
	left_line.custom_minimum_size = Vector2(3.0, 12.0)
	left_line.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	hb.add_child(left_line)
	hb.add_child(lbl)
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_top", 4)
	margin.add_child(hb)
	_vbox.add_child(margin)

func _add_locked_placeholder(reason: String) -> void:
	var lbl := Label.new()
	lbl.text = reason
	lbl.add_theme_font_size_override("font_size", 11)
	lbl.add_theme_color_override("font_color", Color(0.28, 0.28, 0.28))
	lbl.custom_minimum_size = Vector2(PANEL_W - 36.0, 28.0)
	lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 20)
	margin.add_theme_constant_override("margin_bottom", 6)
	margin.add_child(lbl)
	_vbox.add_child(margin)

# ── Talent row ───────────────────────────────────────────────────────────────

func _add_talent_row(t: Talent) -> void:
	var container := VBoxContainer.new()
	container.add_theme_constant_override("separation", 0)
	container.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# ── Collapsed header row (clickable) ──
	var row_btn := Button.new()
	row_btn.custom_minimum_size = Vector2(PANEL_W - 20.0, ROW_H)
	row_btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_btn.focus_mode = Control.FOCUS_NONE
	row_btn.mouse_default_cursor_shape = Control.CURSOR_POINTING_HAND
	_style_talent_row_btn(row_btn)

	# Icon inside row
	var icon_tex := TextureRect.new()
	if t.icon_path != "":
		var tex := load(t.icon_path) as Texture2D
		if tex != null:
			icon_tex.texture = tex
	icon_tex.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	icon_tex.expand_mode = TextureRect.EXPAND_FIT_WIDTH_PROPORTIONAL
	icon_tex.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED

	var name_lbl := Label.new()
	name_lbl.text = t.talent_name
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.85, 0.7))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var pip_lbl := Label.new()
	pip_lbl.add_theme_font_size_override("font_size", 13)
	pip_lbl.add_theme_color_override("font_color", Color(0.6, 0.85, 0.6))
	pip_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	pip_lbl.custom_minimum_size = Vector2(70.0, 0.0)
	pip_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT

	var arrow_lbl := Label.new()
	arrow_lbl.text = "▶"
	arrow_lbl.add_theme_font_size_override("font_size", 10)
	arrow_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
	arrow_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	arrow_lbl.custom_minimum_size = Vector2(18.0, 0.0)

	var row_hb := HBoxContainer.new()
	row_hb.add_theme_constant_override("separation", 8)
	row_hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	row_hb.add_child(icon_tex)
	row_hb.add_child(name_lbl)
	row_hb.add_child(pip_lbl)
	row_hb.add_child(arrow_lbl)
	row_btn.add_child(row_hb)
	row_hb.position = Vector2(8.0, 0.0)
	row_hb.size = Vector2(PANEL_W - 36.0, ROW_H)

	# ── Expanded rank detail panel (hidden by default) ──
	var rank_panel := VBoxContainer.new()
	rank_panel.visible = false
	rank_panel.add_theme_constant_override("separation", 2)
	rank_panel.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	# Rank rows
	for r: int in t.max_rank:
		var rank_num: int = r + 1
		var rank_row := _make_rank_row(t, rank_num)
		rank_panel.add_child(rank_row)

	# Invest button row
	var invest_row := HBoxContainer.new()
	invest_row.add_theme_constant_override("separation", 0)
	var spacer := Control.new()
	spacer.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var invest_btn := Button.new()
	invest_btn.text = "Invest Point"
	invest_btn.custom_minimum_size = Vector2(140.0, 32.0)
	invest_btn.add_theme_font_size_override("font_size", 13)
	invest_btn.focus_mode = Control.FOCUS_NONE
	_style_btn(invest_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	var disabled_sbox := StyleBoxFlat.new()
	disabled_sbox.bg_color = Color(0.10, 0.10, 0.10, 0.5)
	disabled_sbox.set_border_width_all(1)
	disabled_sbox.border_color = Color(0.22, 0.22, 0.22)
	invest_btn.add_theme_stylebox_override("disabled", disabled_sbox)
	var tid: String = t.talent_id
	invest_btn.pressed.connect(func() -> void: _on_invest(tid))
	invest_row.add_child(spacer)
	invest_row.add_child(invest_btn)
	var invest_margin := MarginContainer.new()
	invest_margin.add_theme_constant_override("margin_right", 12)
	invest_margin.add_theme_constant_override("margin_top", 4)
	invest_margin.add_theme_constant_override("margin_bottom", 6)
	invest_margin.add_child(invest_row)
	rank_panel.add_child(invest_margin)

	container.add_child(row_btn)
	container.add_child(rank_panel)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 8)
	margin.add_theme_constant_override("margin_right", 8)
	margin.add_theme_constant_override("margin_bottom", 2)
	margin.add_child(container)
	_vbox.add_child(margin)

	_talent_row_nodes[t.talent_id] = {
		"btn": row_btn,
		"rank_panel": rank_panel,
		"invest_btn": invest_btn,
		"pip_lbl": pip_lbl,
		"arrow_lbl": arrow_lbl,
	}

	var talent_id: String = t.talent_id
	row_btn.pressed.connect(func() -> void: _toggle_expand(talent_id))

func _make_rank_row(t: Talent, rank_num: int) -> Control:
	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 12)
	margin.add_theme_constant_override("margin_right", 12)
	margin.add_theme_constant_override("margin_top", 2)
	margin.add_theme_constant_override("margin_bottom", 2)

	var bg := PanelContainer.new()
	bg.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var hb := HBoxContainer.new()
	hb.add_theme_constant_override("separation", 8)
	hb.size_flags_horizontal = Control.SIZE_EXPAND_FILL

	var roman_lbl := Label.new()
	roman_lbl.text = ROMAN[rank_num - 1]
	roman_lbl.add_theme_font_size_override("font_size", 13)
	roman_lbl.custom_minimum_size = Vector2(22.0, 0.0)
	roman_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	roman_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER

	var desc_lbl := RichTextLabel.new()
	desc_lbl.bbcode_enabled = true
	desc_lbl.fit_content = true
	desc_lbl.scroll_active = false
	desc_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	desc_lbl.add_theme_font_size_override("normal_font_size", 12)
	desc_lbl.text = t.rank_description(rank_num)

	hb.add_child(roman_lbl)
	hb.add_child(desc_lbl)

	var inner_margin := MarginContainer.new()
	inner_margin.add_theme_constant_override("margin_left", 8)
	inner_margin.add_theme_constant_override("margin_right", 8)
	inner_margin.add_theme_constant_override("margin_top", 5)
	inner_margin.add_theme_constant_override("margin_bottom", 5)
	inner_margin.add_child(hb)
	bg.add_child(inner_margin)

	# Store references so _refresh can tint them
	bg.set_meta("roman_lbl", roman_lbl)
	bg.set_meta("desc_lbl", desc_lbl)
	bg.set_meta("rank_num", rank_num)
	bg.set_meta("talent_id", t.talent_id)

	margin.add_child(bg)
	return margin

# ── Toggle expand/collapse ───────────────────────────────────────────────────

func _toggle_expand(talent_id: String) -> void:
	if _expanded_id == talent_id:
		_set_expanded("")
	else:
		_set_expanded(talent_id)

func _set_expanded(talent_id: String) -> void:
	_expanded_id = talent_id
	for tid: String in _talent_row_nodes:
		var nodes: Dictionary = _talent_row_nodes[tid]
		var is_open: bool = tid == talent_id
		nodes["rank_panel"].visible = is_open
		nodes["arrow_lbl"].text = "▼" if is_open else "▶"
	_refresh_all()

# ── Refresh visuals ──────────────────────────────────────────────────────────

func _refresh_all() -> void:
	_points_label.text = "Points available: %d" % GameState.talent_points_available

	for tid: String in _talent_row_nodes:
		var nodes: Dictionary = _talent_row_nodes[tid]
		var current: int = GameState.get_talent_rank(tid)
		var talent: Talent = _find_talent(tid)
		if talent == null:
			continue

		# Pip string e.g. "●●○"
		var pips: String = ""
		for r: int in talent.max_rank:
			pips += "●" if r < current else "○"
		nodes["pip_lbl"].text = pips

		# Invest button
		nodes["invest_btn"].disabled = not GameState.can_invest_talent(tid)

		# Tint each rank row
		var rank_panel: VBoxContainer = nodes["rank_panel"]
		for child: Node in rank_panel.get_children():
			_tint_rank_row(child, current)

func _tint_rank_row(node: Node, current_rank: int) -> void:
	# Walk into MarginContainer → PanelContainer
	var bg: PanelContainer = null
	if node is MarginContainer and node.get_child_count() > 0:
		bg = node.get_child(0) as PanelContainer
	if bg == null:
		return
	if not bg.has_meta("rank_num"):
		return
	var rank_num: int = bg.get_meta("rank_num")
	var roman_lbl: Label = bg.get_meta("roman_lbl")
	var desc_lbl: RichTextLabel = bg.get_meta("desc_lbl")

	# Style the background
	var sbox := StyleBoxFlat.new()
	if rank_num == current_rank:
		# Current rank — gold highlight
		sbox.bg_color = Color(0.20, 0.16, 0.04, 1.0)
		sbox.set_border_width_all(1)
		sbox.border_color = Color(0.78, 0.55, 0.22)
		roman_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.25))
		desc_lbl.add_theme_color_override("default_color", Color(1.0, 0.90, 0.45))
	elif rank_num < current_rank:
		# Already invested (below current)
		sbox.bg_color = Color(0.08, 0.12, 0.08, 1.0)
		sbox.set_border_width_all(1)
		sbox.border_color = Color(0.22, 0.38, 0.22)
		roman_lbl.add_theme_color_override("font_color", Color(0.45, 0.65, 0.45))
		desc_lbl.add_theme_color_override("default_color", Color(0.45, 0.65, 0.45))
	else:
		# Not yet reached
		sbox.bg_color = Color(0.09, 0.09, 0.14, 1.0)
		sbox.set_border_width_all(1)
		sbox.border_color = Color(0.22, 0.22, 0.30)
		roman_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.48))
		desc_lbl.add_theme_color_override("default_color", Color(0.38, 0.38, 0.48))
	bg.add_theme_stylebox_override("panel", sbox)

# ── Invest ───────────────────────────────────────────────────────────────────

func _on_invest(talent_id: String) -> void:
	if not GameState.can_invest_talent(talent_id):
		return
	GameState.invest_talent(talent_id)
	_refresh_all()
	if GameState.talent_points_available <= 0:
		_close()

func _close() -> void:
	GameState.talent_picker_open = false
	queue_free()

# ── Helpers ──────────────────────────────────────────────────────────────────

func _find_talent(tid: String) -> Talent:
	for t: Talent in GameState._class_talents:
		if t.talent_id == tid:
			return t
	return null

func _make_hsep(y: float) -> HSeparator:
	var sep := HSeparator.new()
	sep.position = Vector2(10.0, y)
	sep.size = Vector2(PANEL_W - 20.0, 2.0)
	return sep

func _style_talent_row_btn(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.11, 0.17, 1.0)
	normal.set_border_width_all(0)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.17, 0.18, 0.26, 1.0)
	btn.add_theme_stylebox_override("hover", hover)
	var pressed_sbox := StyleBoxFlat.new()
	pressed_sbox.bg_color = Color(0.13, 0.14, 0.20, 1.0)
	btn.add_theme_stylebox_override("pressed", pressed_sbox)

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

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
