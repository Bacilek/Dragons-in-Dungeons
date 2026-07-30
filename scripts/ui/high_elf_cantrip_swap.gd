extends CanvasLayer

# High Elf lineage's level-1 benefit — see GameState.swap_high_elf_cantrip()'s own doc comment.
# Two-round card picker modeled on cantrip_select.gd: round 1 "pick 1 of your known cantrips to
# replace", round 2 "pick 1 of the Wizard cantrips you don't know yet". Only ever reachable from
# the long-rest hub (mastery_reselect_prompt.gd) — same "changeable only at a long rest" gating as
# Attunement/Weapon Masteries.

const PANEL_W: float = 640.0
const ROW_H: float = 56.0

var _panel: Panel
var _rows_container: Control
var _title: Label
var _round: int = 1
var _old_id: String = ""

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
	_panel.size = Vector2(PANEL_W, 200.0)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.55, 0.8, 0.4)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	_title = Label.new()
	_title.add_theme_font_size_override("font_size", 22)
	_title.add_theme_color_override("font_color", Color(0.65, 0.9, 0.5))
	_title.position = Vector2(20.0, 14.0)
	_title.size = Vector2(PANEL_W - 160.0, 34.0)
	_panel.add_child(_title)

	var done_btn := Button.new()
	done_btn.text = "Skip / Done  [Esc]"
	done_btn.size = Vector2(150.0, 34.0)
	done_btn.position = Vector2(PANEL_W - 166.0, 14.0)
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.add_theme_font_size_override("font_size", 13)
	_style_btn(done_btn, Color(0.12, 0.12, 0.16), Color(0.4, 0.4, 0.4))
	done_btn.pressed.connect(_close)
	_panel.add_child(done_btn)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 56.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	_rows_container = Control.new()
	_rows_container.position = Vector2(20.0, 70.0)
	_rows_container.size = Vector2(PANEL_W - 40.0, 0.0)
	_panel.add_child(_rows_container)

	_refresh()

func _refresh() -> void:
	for c: Node in _rows_container.get_children():
		c.queue_free()

	var ids: Array[String]
	if _round == 1:
		_title.text = "Choose a known cantrip to replace"
		ids = GameState.high_elf_known_cantrips()
	else:
		_title.text = "Choose a new cantrip to learn"
		ids = GameState.high_elf_learnable_cantrips()

	var y: float = 0.0
	for sid: String in ids:
		_add_row(sid, y)
		y += ROW_H
	_rows_container.size = Vector2(PANEL_W - 40.0, y)

	var panel_h: float = maxf(70.0 + maxf(y, 40.0) + 16.0, 160.0)
	_panel.size = Vector2(PANEL_W, panel_h)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _add_row(spell_id: String, y: float) -> void:
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	var btn := Button.new()
	btn.position = Vector2(0.0, y)
	btn.size = Vector2(PANEL_W - 40.0, ROW_H - 8.0)
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "  %s" % spell.spell_name
	btn.add_theme_font_size_override("font_size", 16)
	btn.alignment = HORIZONTAL_ALIGNMENT_LEFT
	_style_btn(btn, Color(0.12, 0.12, 0.16), Color(0.4, 0.55, 0.35))
	btn.pressed.connect(func() -> void: _on_pick(spell_id))
	_rows_container.add_child(btn)

func _on_pick(spell_id: String) -> void:
	if _round == 1:
		_old_id = spell_id
		_round = 2
		_refresh()
	else:
		GameState.swap_high_elf_cantrip(_old_id, spell_id)
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
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
