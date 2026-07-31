extends CanvasLayer

# Aasimar's Celestial Revelation — a 3-option click-to-choose picker (Heavenly Wings / Inner
# Radiance / Necrotic Shroud), replacing the old arm-cycle-cancel-then-click-anywhere flow (direct
# owner request — that flow silently rotated through choices with nothing on screen showing what
# was even on offer). Modeled on subclass_select.gd's card-grid conventions (dim overlay + centered
# bordered Panel, focus_mode = FOCUS_NONE everywhere) but non-mandatory: Esc cancels for free since
# nothing has been spent yet (the long-rest use/turns/transform are only set on PlayerAasimar.
# resolve_celestial_revelation_choice(), called from a card click). Reuses GameState.
# mastery_picker_open as its input-blocking flag — same "no dedicated flag, reuse the shared modal
# gate" precedent as high_elf_cantrip_swap.gd/attunement_picker.gd.
# No icon art exists yet for any of the 3 choices — each card is a plain text button with its full
# description as a native Control.tooltip_text (hover to read), same "i-badge" convention
# class_select.gd's info icon uses.

var aasimar: PlayerAasimar

const CARD_W: float = 260.0
const CARD_H: float = 160.0
const CARD_GAP: float = 20.0
const PANEL_PAD: float = 24.0

func _ready() -> void:
	layer = 25
	GameState.mastery_picker_open = true
	_build_ui()

func _build_ui() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var panel_w: float = PANEL_PAD * 2.0 + CARD_W * 3.0 + CARD_GAP * 2.0
	var panel_h: float = PANEL_PAD * 2.0 + CARD_H + 56.0
	var panel := Panel.new()
	panel.size = Vector2(panel_w, panel_h)
	panel.position = (vp - panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.06, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.85, 0.75, 0.5)
	sbox.set_corner_radius_all(8)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var title := Label.new()
	title.text = "Celestial Revelation — choose a transformation"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(1.0, 0.92, 0.66))
	title.position = Vector2(PANEL_PAD, 14.0)
	title.size = Vector2(panel_w - PANEL_PAD * 2.0, 30.0)
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	panel.add_child(title)

	for i: int in 3:
		_add_card(panel, i, PANEL_PAD + i * (CARD_W + CARD_GAP), 56.0)

func _add_card(panel: Panel, transform_idx: int, x: float, y: float) -> void:
	var btn := Button.new()
	btn.position = Vector2(x, y)
	btn.size = Vector2(CARD_W, CARD_H)
	btn.focus_mode = Control.FOCUS_NONE
	btn.text = "\n%s" % PlayerAasimar.TRANSFORM_NAMES[transform_idx]
	btn.add_theme_font_size_override("font_size", 18)
	btn.autowrap_mode = TextServer.AUTOWRAP_WORD
	btn.tooltip_text = PlayerAasimar.TRANSFORM_DESCRIPTIONS[transform_idx]
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.11, 0.18)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.6, 0.55, 0.35)
	normal.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.2, 0.18, 0.28)
	hover.set_border_width_all(2)
	hover.border_color = Color(1.0, 0.92, 0.66)
	hover.set_corner_radius_all(6)
	btn.add_theme_stylebox_override("hover", hover)
	btn.pressed.connect(func() -> void: _on_pick(transform_idx))
	panel.add_child(btn)

func _on_pick(transform_idx: int) -> void:
	aasimar.resolve_celestial_revelation_choice(transform_idx)
	_close()

func _close() -> void:
	GameState.mastery_picker_open = false
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
