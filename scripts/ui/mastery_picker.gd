extends CanvasLayer

# Weapon Mastery Selection overlay — see docs/architecture/weapon-mastery-selection-design.md.
# Modeled directly on talent_picker.gd (same overlay/icon-grid/refresh patterns).

const PANEL_W: float = 720.0
const ICON_SIZE: float = 64.0
const MASTERY_ICON_FOLDER := "res://icons/masteries/"

const MASTERY_DESCRIPTIONS: Dictionary = {
	"Cleave": "If 2+ enemies are within melee reach, this attack also strikes the one closest to your primary target — with its own attack roll and damage roll.",
	"Graze": "On a miss, still deal damage equal to the ability modifier used for the attack (min 0).",
	"Nick": "While dual-wielding two Light weapons, make one further attack this turn — same rules as the Off-hand swing (max 3 attacks total).",
	"Push": "On a hit, the target rolls a CON save (DC 8 + Prof + DEX) or is shoved 1 tile directly away from you.",
	"Sap": "On a thrown hit, the target has Disadvantage on its very next attack, next turn.",
	"Slow": "On a hit, the target is Slowed — its next turn is skipped entirely, same as stepping into mud/water.",
	"Topple": "On a hit, the target rolls a CON save (DC 8 + Prof + STR) or is knocked Prone, skipping its entire next turn.",
	"Vex": "On a hit, gain Advantage on your next attack this round against the same target (any attack type).",
}

var _mastery_btns: Dictionary = {}    # mastery_name -> TextureButton
var _slot_frames: Dictionary = {}     # mastery_name -> Panel
var _name_labels: Dictionary = {}     # mastery_name -> Label
var _counter_rtl: RichTextLabel
var _detail_name: Label
var _detail_desc: RichTextLabel
var _selected_id: String = ""
var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.mastery_picker_open = true
	_build_ui()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, 500.0)  # resized at end
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	# ── Title bar ────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "Weapon Masteries"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(20.0, 14.0)
	title.size = Vector2(380.0, 34.0)
	_panel.add_child(title)

	_counter_rtl = RichTextLabel.new()
	_counter_rtl.bbcode_enabled = true
	_counter_rtl.fit_content = false
	_counter_rtl.scroll_active = false
	_counter_rtl.position = Vector2(PANEL_W - 240.0, 18.0)
	_counter_rtl.size = Vector2(100.0, 30.0)
	_counter_rtl.add_theme_font_size_override("normal_font_size", 19)
	_panel.add_child(_counter_rtl)

	var done_btn := Button.new()
	done_btn.text = "✓  Done  [Esc]"
	done_btn.size = Vector2(128.0, 34.0)
	done_btn.position = Vector2(PANEL_W - 144.0, 14.0)
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.add_theme_font_size_override("font_size", 14)
	_style_btn(done_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	done_btn.pressed.connect(_close)
	_panel.add_child(done_btn)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(12.0, 60.0)
	sep1.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep1)

	# ── Mastery grid: 4 columns x 2 rows ──────────────────────────────────────────
	var y: float = 76.0
	var cols: int = 4
	var rows: int = 2
	var slot_w: float = (PANEL_W - 40.0) / cols
	for i: int in Stats.ALL_WEAPON_MASTERIES.size():
		var name: String = Stats.ALL_WEAPON_MASTERIES[i]
		var col: int = i % cols
		var row: int = i / cols
		var icon_x: float = 20.0 + col * slot_w + (slot_w - ICON_SIZE) * 0.5
		var icon_y: float = y + row * (ICON_SIZE + 46.0)
		_add_mastery_slot(name, Vector2(icon_x, icon_y))
	y += rows * (ICON_SIZE + 46.0) + 6.0

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, y)
	sep2.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep2)
	y += 12.0

	# ── Detail section ────────────────────────────────────────────────────────────
	_detail_name = Label.new()
	_detail_name.text = "— select a mastery —"
	_detail_name.add_theme_font_size_override("font_size", 17)
	_detail_name.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_detail_name.position = Vector2(20.0, y)
	_detail_name.size = Vector2(PANEL_W - 40.0, 26.0)
	_panel.add_child(_detail_name)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = false
	_detail_desc.scroll_active = false
	_detail_desc.position = Vector2(20.0, y + 30.0)
	_detail_desc.size = Vector2(PANEL_W - 40.0, 60.0)
	_detail_desc.add_theme_font_size_override("normal_font_size", 14)
	_panel.add_child(_detail_desc)
	y += 30.0 + 60.0 + 16.0

	_panel.size = Vector2(PANEL_W, y)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - y) * 0.5)

	_refresh()

func _add_mastery_slot(name: String, pos: Vector2) -> void:
	var frame := Panel.new()
	frame.size = Vector2(ICON_SIZE, ICON_SIZE)
	frame.position = pos
	var fbox := StyleBoxFlat.new()
	fbox.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	fbox.set_border_width_all(2)
	fbox.border_color = Color(0.35, 0.35, 0.35)
	fbox.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", fbox)
	_panel.add_child(frame)
	_slot_frames[name] = frame

	var btn := TextureButton.new()
	btn.size = Vector2(ICON_SIZE, ICON_SIZE)
	btn.position = pos
	btn.ignore_texture_size = true
	btn.stretch_mode = TextureButton.STRETCH_KEEP_ASPECT_CENTERED
	btn.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	btn.focus_mode = Control.FOCUS_NONE
	var icon_path: String = MASTERY_ICON_FOLDER + name.to_lower() + ".png"
	if ResourceLoader.exists(icon_path):
		btn.texture_normal = load(icon_path)
	btn.pressed.connect(func() -> void: _on_slot_pressed(name))
	_panel.add_child(btn)
	_mastery_btns[name] = btn

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(pos.x - 12.0, pos.y + ICON_SIZE + 4.0)
	name_lbl.size = Vector2(ICON_SIZE + 24.0, 22.0)
	_panel.add_child(name_lbl)
	_name_labels[name] = name_lbl

func _on_slot_pressed(name: String) -> void:
	_selected_id = name
	GameState.toggle_mastery(name)
	_refresh()

# ── Refresh all visuals ───────────────────────────────────────────────────────

func _refresh() -> void:
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	var cap: int = GameState.player_stats.mastery_cap()
	var at_cap: bool = known.size() >= cap

	for name: String in Stats.ALL_WEAPON_MASTERIES:
		var btn: TextureButton = _mastery_btns[name]
		var frame: Panel = _slot_frames[name]
		var known_here: bool = name in known
		var fbox: StyleBoxFlat = frame.get_theme_stylebox("panel") as StyleBoxFlat
		if known_here:
			btn.modulate = Color(1.4, 1.1, 0.4)
			fbox.border_color = Color(0.78, 0.55, 0.22)
		elif at_cap:
			btn.modulate = Color(1.0, 1.0, 1.0, 0.5)
			fbox.border_color = Color(0.35, 0.35, 0.35)
		else:
			btn.modulate = Color(1.0, 1.0, 1.0)
			fbox.border_color = Color(0.35, 0.35, 0.35)

	var count_color: String = "#FFD700"
	if known.size() > cap:
		count_color = "#e05050"
	elif at_cap:
		count_color = "#888888"
	_counter_rtl.text = "[right][color=%s]%d / %d[/color][/right]" % [count_color, known.size(), cap]

	if _selected_id != "":
		_detail_name.text = _selected_id
		_detail_desc.text = MASTERY_DESCRIPTIONS.get(_selected_id, "")

func _close() -> void:
	GameState.mastery_picker_open = false
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

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
