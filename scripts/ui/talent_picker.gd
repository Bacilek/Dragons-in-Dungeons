extends CanvasLayer

const PANEL_W: float = 500.0
const ICON_SIZE: float = 48.0

var _selected_id: String = ""
var _talent_btns: Dictionary = {}   # talent_id → TextureButton
var _dot_labels: Dictionary = {}    # talent_id → Label
var _star_rtls: Dictionary = {}     # tier (int) → RichTextLabel
var _detail_name: Label
var _detail_desc: RichTextLabel
var _upgrade_btn: Button
var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.talent_picker_open = true
	_build_ui()
	if not GameState._class_talents.is_empty():
		_select_talent(GameState._class_talents[0].talent_id)

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, 600.0)  # resized at end
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	# ── Title bar ────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "Talents"
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(14.0, 10.0)
	title.size = Vector2(260.0, 26.0)
	_panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕  [Esc/T]"
	close_btn.size = Vector2(90.0, 28.0)
	close_btn.position = Vector2(PANEL_W - 102.0, 10.0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 12)
	_style_btn(close_btn, Color(0.22, 0.10, 0.10), Color(0.60, 0.25, 0.25))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(8.0, 46.0)
	sep1.size = Vector2(PANEL_W - 16.0, 2.0)
	_panel.add_child(sep1)

	# ── Tier sections ─────────────────────────────────────────────────────────────
	var y: float = 54.0
	y = _build_tier_section(1, y)
	y += 10.0
	y = _build_tier_section(2, y)
	y += 8.0

	# ── Detail separator ──────────────────────────────────────────────────────────
	var sep2 := HSeparator.new()
	sep2.position = Vector2(8.0, y)
	sep2.size = Vector2(PANEL_W - 16.0, 2.0)
	_panel.add_child(sep2)
	y += 8.0

	# ── Detail section ────────────────────────────────────────────────────────────
	_build_detail_section(y)

	# Resize panel to actual content height
	var panel_h: float = y + 28.0 + 120.0 + 34.0 + 16.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

	_refresh()

func _build_tier_section(tier: int, y: float) -> float:
	var active: bool = (tier == 1) or GameState.tier2_unlocked
	var label_color := Color(0.78, 0.55, 0.22) if active else Color(0.38, 0.38, 0.38)

	# "Tier N" label
	var tier_lbl := Label.new()
	tier_lbl.text = "Tier %d" % tier
	tier_lbl.add_theme_font_size_override("font_size", 13)
	tier_lbl.add_theme_color_override("font_color", label_color)
	tier_lbl.position = Vector2(14.0, y + 4.0)
	tier_lbl.size = Vector2(60.0, 20.0)
	_panel.add_child(tier_lbl)

	# Star bar (right side, colored ★ chars via bbcode)
	var star_rtl := RichTextLabel.new()
	star_rtl.bbcode_enabled = true
	star_rtl.fit_content = false
	star_rtl.scroll_active = false
	star_rtl.position = Vector2(PANEL_W - 144.0, y + 2.0)
	star_rtl.size = Vector2(132.0, 24.0)
	star_rtl.add_theme_font_size_override("normal_font_size", 15)
	_panel.add_child(star_rtl)
	_star_rtls[tier] = star_rtl

	y += 30.0

	# Collect talents for this tier
	var tier_talents: Array[Talent] = []
	for t: Talent in GameState._class_talents:
		if t.tier == tier:
			tier_talents.append(t)

	if tier == 2 and not GameState.tier2_unlocked:
		var locked_lbl := Label.new()
		locked_lbl.text = "Tier 2  —  unlocks at level 7"
		locked_lbl.add_theme_font_size_override("font_size", 12)
		locked_lbl.add_theme_color_override("font_color", Color(0.33, 0.33, 0.33))
		locked_lbl.position = Vector2(14.0, y + 8.0)
		locked_lbl.size = Vector2(PANEL_W - 28.0, 24.0)
		_panel.add_child(locked_lbl)
		y += 36.0
	else:
		var n: int = tier_talents.size()
		if n > 0:
			var slot_w: float = (PANEL_W - 28.0) / n
			for i: int in n:
				var t: Talent = tier_talents[i]
				var icon_x: float = 14.0 + i * slot_w + (slot_w - ICON_SIZE) * 0.5
				_add_talent_icon(t, Vector2(icon_x, y))
		y += ICON_SIZE + 26.0  # 48 icon + 4 gap + 22 dot label + 2 breathing room
	return y

func _add_talent_icon(t: Talent, pos: Vector2) -> void:
	var btn := TextureButton.new()
	btn.size = Vector2(ICON_SIZE, ICON_SIZE)
	btn.position = pos
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	if t.icon_path != "" and ResourceLoader.exists(t.icon_path):
		btn.texture_normal = load(t.icon_path)
	btn.focus_mode = Control.FOCUS_NONE
	_talent_btns[t.talent_id] = btn
	var tid: String = t.talent_id
	btn.pressed.connect(func() -> void: _select_talent(tid))
	_panel.add_child(btn)

	var dot_lbl := Label.new()
	dot_lbl.add_theme_font_size_override("font_size", 14)
	dot_lbl.add_theme_color_override("font_color", Color(0.50, 0.80, 0.50))
	dot_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	dot_lbl.position = Vector2(pos.x - 8.0, pos.y + ICON_SIZE + 4.0)
	dot_lbl.size = Vector2(ICON_SIZE + 16.0, 20.0)
	_dot_labels[t.talent_id] = dot_lbl
	_panel.add_child(dot_lbl)

func _build_detail_section(y: float) -> void:
	_detail_name = Label.new()
	_detail_name.text = "— select a talent —"
	_detail_name.add_theme_font_size_override("font_size", 14)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_detail_name.position = Vector2(14.0, y)
	_detail_name.size = Vector2(PANEL_W - 28.0, 26.0)
	_panel.add_child(_detail_name)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = false
	_detail_desc.scroll_active = false
	_detail_desc.position = Vector2(14.0, y + 30.0)
	_detail_desc.size = Vector2(PANEL_W - 28.0, 120.0)
	_detail_desc.add_theme_font_size_override("normal_font_size", 12)
	_panel.add_child(_detail_desc)

	_upgrade_btn = Button.new()
	_upgrade_btn.text = "Upgrade Talent  ▲"
	_upgrade_btn.size = Vector2(182.0, 34.0)
	_upgrade_btn.position = Vector2(PANEL_W - 196.0, y + 154.0)
	_upgrade_btn.add_theme_font_size_override("font_size", 13)
	_upgrade_btn.focus_mode = Control.FOCUS_NONE
	_upgrade_btn.disabled = true
	var dis_sbox := StyleBoxFlat.new()
	dis_sbox.bg_color = Color(0.10, 0.10, 0.10, 0.5)
	dis_sbox.set_border_width_all(1)
	dis_sbox.border_color = Color(0.22, 0.22, 0.22)
	_upgrade_btn.add_theme_stylebox_override("disabled", dis_sbox)
	_style_btn(_upgrade_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	_upgrade_btn.pressed.connect(_on_upgrade)
	_panel.add_child(_upgrade_btn)

# ── Selection ─────────────────────────────────────────────────────────────────

func _select_talent(id: String) -> void:
	# Remove previous highlight
	if _selected_id != "" and _talent_btns.has(_selected_id):
		_talent_btns[_selected_id].modulate = Color(1.0, 1.0, 1.0)
	_selected_id = id
	# Apply gold-orange tint to selected icon
	if _talent_btns.has(id):
		_talent_btns[id].modulate = Color(1.4, 1.1, 0.4)
	_update_detail(id)
	_upgrade_btn.disabled = not GameState.can_invest_talent(id)

func _update_detail(id: String) -> void:
	var t: Talent = _find_talent(id)
	if t == null:
		_detail_name.text = "— select a talent —"
		_detail_desc.text = ""
		return
	var rank: int = GameState.get_talent_rank(id)
	_detail_name.text = "%s   (Rank %d / %d)" % [t.talent_name, rank, t.max_rank]
	var desc: String = ""
	for r: int in t.max_rank:
		var rn: int = r + 1
		if rn < rank + 1:
			# Already unlocked (below current rank)
			desc += "[color=#45a545]Rank %d:[/color] [color=#a0d0a0]%s[/color]\n" % [rn, t.rank_description(rn)]
		elif rn == rank + 1:
			# Next rank (upgrade target)
			desc += "[color=#c89040]Rank %d:[/color] [color=#e0c880]%s[/color]\n" % [rn, t.rank_description(rn)]
		else:
			# Locked rank
			desc += "[color=#484850]Rank %d:[/color] [color=#484850]%s[/color]\n" % [rn, t.rank_description(rn)]
	_detail_desc.text = desc.strip_edges()

# ── Refresh all visuals ───────────────────────────────────────────────────────

func _refresh() -> void:
	# Star bars
	for tier: int in _star_rtls:
		_star_rtls[tier].text = _star_bar(tier)
	# Dot rows
	for t: Talent in GameState._class_talents:
		if not _dot_labels.has(t.talent_id):
			continue
		var rank: int = GameState.get_talent_rank(t.talent_id)
		var dots: String = ""
		for r: int in t.max_rank:
			dots += "●" if r < rank else "○"
		_dot_labels[t.talent_id].text = dots
	# Upgrade button
	if _selected_id != "":
		_upgrade_btn.disabled = not GameState.can_invest_talent(_selected_id)

func _on_upgrade() -> void:
	if _selected_id.is_empty() or not GameState.can_invest_talent(_selected_id):
		return
	GameState.invest_talent(_selected_id)
	_select_talent(_selected_id)  # re-apply highlight + re-read rank
	_refresh()

func _close() -> void:
	GameState.talent_picker_open = false
	queue_free()

# ── Star bar ──────────────────────────────────────────────────────────────────

func _star_bar(tier: int) -> String:
	var max_pts: int = 5 if tier == 1 else 6
	var available: int = GameState.tier1_talent_points if tier == 1 else GameState.tier2_talent_points
	var spent: int = _compute_spent(tier)
	var shown_spent: int     = min(spent, max_pts)
	var shown_available: int = min(available, max_pts - shown_spent)
	var shown_locked: int    = max_pts - shown_spent - shown_available
	return "[right][color=#888888]%s[/color][color=#FFD700]%s[/color][color=#444444]%s[/color][/right]" % [
		"★".repeat(shown_spent), "★".repeat(shown_available), "★".repeat(shown_locked)]

func _compute_spent(tier: int) -> int:
	var total: int = 0
	for t: Talent in GameState._class_talents:
		if t.tier == tier:
			total += GameState.get_talent_rank(t.talent_id)
	return total

func _find_talent(id: String) -> Talent:
	for t: Talent in GameState._class_talents:
		if t.talent_id == id:
			return t
	return null

# ── Style helpers ─────────────────────────────────────────────────────────────

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
	if key.physical_keycode == KEY_ESCAPE or key.physical_keycode == KEY_T:
		get_viewport().set_input_as_handled()
		_close()
