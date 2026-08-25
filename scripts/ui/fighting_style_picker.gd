extends CanvasLayer

# Fighter's level-1 Fighting Style picker — see scripts/entities/CLAUDE.md's "Fighter class"
# section for the full per-style mechanism/hook-site table. Modeled on attunement_picker.gd's
# row-list layout (no icon art exists for any style, so a tile-grid+hover-tooltip shape like the
# spell pickers would be pure overhead here — a plain scrollable list of 10 named rows with their
# description inline reads better with zero art).
#
# Two modes:
# - character_creation_mode (set on the instance before add_child, default false): the mandatory
#   level-1 pick — spawned right after mastery_picker.gd's own Learn mode finishes for a Fighter
#   (see mastery_picker.gd's _finish_learn()). No Esc/Done — a style MUST be picked.
# - Reselect mode (character_creation_mode == false, the default): spawned on every subsequent
#   Fighter level-up (a direct owner house rule — real 5e RAW doesn't allow freely re-picking a
#   Fighting Style; this project deliberately does, every level). Optional — "Keep Current" button
#   and Esc both close without changing anything.

const PANEL_W: float = 720.0
const ROW_H: float = 76.0

var character_creation_mode: bool = false

var _panel: Panel
var _rows_container: Control

func _ready() -> void:
	layer = 25
	GameState.mastery_picker_open = true  # reuses the shared input-block flag, same precedent as
	                                       # high_elf_cantrip_swap.gd/attunement_picker.gd
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
	_panel.size = Vector2(PANEL_W, 200.0)  # resized in _refresh()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.85, 0.55, 0.25)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Choose Your Fighting Style" if character_creation_mode else "Change Fighting Style?"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.95, 0.75, 0.45))
	title.position = Vector2(20.0, 14.0)
	title.size = Vector2(460.0, 34.0)
	_panel.add_child(title)

	if not character_creation_mode:
		var keep_btn := Button.new()
		keep_btn.text = "Keep Current  [Esc]"
		keep_btn.size = Vector2(180.0, 34.0)
		keep_btn.position = Vector2(PANEL_W - 196.0, 14.0)
		keep_btn.focus_mode = Control.FOCUS_NONE
		keep_btn.add_theme_font_size_override("font_size", 14)
		_style_btn(keep_btn, Color(0.10, 0.10, 0.12), Color(0.4, 0.4, 0.4))
		keep_btn.pressed.connect(_close)
		_panel.add_child(keep_btn)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 56.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(20.0, 68.0)
	scroll.size = Vector2(PANEL_W - 40.0, 560.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_panel.add_child(scroll)

	_rows_container = Control.new()
	_rows_container.size = Vector2(PANEL_W - 56.0, 0.0)
	scroll.add_child(_rows_container)

	_refresh()

	_panel.position = (vp - _panel.size) * 0.5

func _refresh() -> void:
	for c: Node in _rows_container.get_children():
		c.queue_free()
	var y: float = 0.0
	for id: String in Stats.ALL_FIGHTING_STYLES:
		_add_row(id, y)
		y += ROW_H
	_rows_container.size = Vector2(_rows_container.size.x, y)

func _add_row(id: String, y: float) -> void:
	var current: bool = GameState.player_stats.fighting_style == id
	var frame := Panel.new()
	frame.position = Vector2(0.0, y)
	frame.size = Vector2(_rows_container.size.x, ROW_H - 8.0)
	var fbox := StyleBoxFlat.new()
	fbox.bg_color = Color(0.14, 0.12, 0.09, 0.9) if current else Color(0.12, 0.12, 0.16, 0.9)
	fbox.set_border_width_all(2)
	fbox.border_color = Color(0.85, 0.55, 0.25) if current else Color(0.35, 0.35, 0.35)
	fbox.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", fbox)
	_rows_container.add_child(frame)

	var name_lbl := Label.new()
	name_lbl.text = Stats.FIGHTING_STYLE_NAMES.get(id, id) + ("  (current)" if current else "")
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.85, 0.6) if current else Color(0.9, 0.9, 0.95))
	name_lbl.position = Vector2(10.0, 6.0)
	name_lbl.size = Vector2(frame.size.x - 20.0, 22.0)
	frame.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = Stats.FIGHTING_STYLE_DESCRIPTIONS.get(id, "")
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.65, 0.65, 0.7))
	desc_lbl.position = Vector2(10.0, 30.0)
	desc_lbl.size = Vector2(frame.size.x - 20.0, ROW_H - 40.0)
	frame.add_child(desc_lbl)

	var click_btn := Button.new()
	click_btn.flat = true
	click_btn.size = frame.size
	click_btn.focus_mode = Control.FOCUS_NONE
	click_btn.pressed.connect(func() -> void: _on_pick(id))
	frame.add_child(click_btn)

func _on_pick(id: String) -> void:
	GameState.set_fighting_style(id)
	if character_creation_mode:
		# The whole onboarding chain is done at this point (character_summary.gd + mastery_picker.gd
		# both already ran) — snapshot for "Try Again", same tail every other last-step-of-creation
		# picker calls (mastery_picker.gd/cantrip_select.gd).
		GameState.snapshot_character_creation()
	_close()

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
	if character_creation_mode:
		return  # mandatory pick — no Esc
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
