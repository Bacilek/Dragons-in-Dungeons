extends CanvasLayer

# Magic item Attunement overlay — see scripts/items/CLAUDE.md's "Attunement" section.
# Modeled on mastery_picker.gd (dim overlay + centered bordered Panel, click-to-toggle,
# hard-blocked at a cap). Only ever reachable from the long-rest hub
# (scripts/ui/mastery_reselect_prompt.gd) — attunement is only changeable at a long rest.
# Lists every Item.requires_attunement item currently in the quickbar/bag/equipment
# (GameState.attunable_items()) whether or not it's already attuned.

const PANEL_W: float = 640.0
const ROW_H: float = 64.0

var _panel: Panel
var _rows_container: Control
var _counter_rtl: RichTextLabel
var _empty_label: Label

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
	_panel.size = Vector2(PANEL_W, 200.0)  # resized in _refresh()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.3, 0.55, 1.0)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Attunement"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.55, 0.75, 1.0))
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

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 60.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	_empty_label = Label.new()
	_empty_label.text = "No magic items requiring attunement in your inventory."
	_empty_label.add_theme_font_size_override("font_size", 15)
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.position = Vector2(20.0, 76.0)
	_empty_label.size = Vector2(PANEL_W - 40.0, 30.0)
	_panel.add_child(_empty_label)

	_rows_container = Control.new()
	_rows_container.position = Vector2(20.0, 76.0)
	_rows_container.size = Vector2(PANEL_W - 40.0, 0.0)
	_panel.add_child(_rows_container)

	_refresh()

func _refresh() -> void:
	for c: Node in _rows_container.get_children():
		c.queue_free()

	var items: Array[Item] = GameState.attunable_items()
	_empty_label.visible = items.is_empty()

	var y: float = 0.0
	for it: Item in items:
		_add_row(it, y)
		y += ROW_H
	_rows_container.size = Vector2(PANEL_W - 40.0, y)

	var count: int = GameState.attuned_count()
	var count_color: String = "#e05050" if count > GameState.MAX_ATTUNED_ITEMS else "#4aa3ff"
	_counter_rtl.text = "[right][color=%s]%d / %d[/color][/right]" % [count_color, count, GameState.MAX_ATTUNED_ITEMS]

	var panel_h: float = maxf(76.0 + maxf(y, 40.0) + 16.0, 160.0)
	_panel.size = Vector2(PANEL_W, panel_h)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _add_row(item: Item, y: float) -> void:
	var frame := Panel.new()
	frame.position = Vector2(0.0, y)
	frame.size = Vector2(PANEL_W - 40.0, ROW_H - 8.0)
	var fbox := StyleBoxFlat.new()
	fbox.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	fbox.set_border_width_all(2)
	fbox.border_color = Color(0.3, 0.55, 1.0) if item.is_attuned else Color(0.35, 0.35, 0.35)
	fbox.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", fbox)
	_rows_container.add_child(frame)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(6.0, 6.0)
	icon.size = Vector2(ROW_H - 20.0, ROW_H - 20.0)
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		icon.texture = load(item.icon_path)
	frame.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = item.item_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	name_lbl.position = Vector2(ROW_H + 4.0, 6.0)
	name_lbl.size = Vector2(PANEL_W - 40.0 - ROW_H - 140.0, 24.0)
	frame.add_child(name_lbl)

	var status_lbl := Label.new()
	status_lbl.text = "Attuned" if item.is_attuned else "Not attuned"
	status_lbl.add_theme_font_size_override("font_size", 12)
	status_lbl.add_theme_color_override("font_color", Color(0.4, 0.75, 1.0) if item.is_attuned else Color(0.55, 0.55, 0.55))
	status_lbl.position = Vector2(ROW_H + 4.0, 32.0)
	status_lbl.size = Vector2(PANEL_W - 40.0 - ROW_H - 140.0, 20.0)
	frame.add_child(status_lbl)

	var toggle_btn := Button.new()
	toggle_btn.size = Vector2(120.0, ROW_H - 20.0)
	toggle_btn.position = Vector2(frame.size.x - 130.0, 4.0)
	toggle_btn.focus_mode = Control.FOCUS_NONE
	toggle_btn.add_theme_font_size_override("font_size", 14)
	var at_cap: bool = GameState.attuned_count() >= GameState.MAX_ATTUNED_ITEMS
	if item.is_attuned:
		toggle_btn.text = "Unattune"
		_style_btn(toggle_btn, Color(0.22, 0.10, 0.10), Color(0.65, 0.28, 0.28))
	else:
		toggle_btn.text = "Attune"
		toggle_btn.disabled = at_cap
		_style_btn(toggle_btn, Color(0.10, 0.16, 0.22), Color(0.28, 0.5, 0.65))
	toggle_btn.pressed.connect(func() -> void: _on_toggle(item))
	frame.add_child(toggle_btn)

func _on_toggle(item: Item) -> void:
	if item.is_attuned:
		GameState.unattune_item(item)
	else:
		GameState.attune_item(item)  # silent no-op at cap, same feel as the Mastery Picker
	_refresh()

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
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.15, 0.15, 0.15)
	disabled.set_border_width_all(1)
	disabled.border_color = Color(0.3, 0.3, 0.3)
	disabled.set_corner_radius_all(3)
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
