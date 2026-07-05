extends CanvasLayer

# Shown once right after a completed long rest — see GameState.long_rest() and
# player.gd's short_rest_active completion branch. Sets GameState.mastery_picker_open
# (blocking input) for the duration of this Yes/No decision; "Yes" hands off to
# mastery_picker.gd, which keeps the flag set on its own _ready().

func _ready() -> void:
	layer = 26
	_build_ui()

func _build_ui() -> void:
	var panel := Panel.new()
	panel.size = Vector2(360.0, 130.0)
	var vp := get_viewport().get_visible_rect().size
	panel.position = (vp - panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var title := Label.new()
	title.text = "Change your weapon masteries?"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(320.0, 40.0)
	title.position = Vector2(20.0, 16.0)
	panel.add_child(title)

	var yes_btn := Button.new()
	yes_btn.text = "Yes  [Y]"
	yes_btn.size = Vector2(150.0, 44.0)
	yes_btn.position = Vector2(20.0, 66.0)
	yes_btn.focus_mode = Control.FOCUS_NONE
	yes_btn.pressed.connect(_on_yes)
	panel.add_child(yes_btn)

	var no_btn := Button.new()
	no_btn.text = "No  [Esc]"
	no_btn.size = Vector2(150.0, 44.0)
	no_btn.position = Vector2(190.0, 66.0)
	no_btn.focus_mode = Control.FOCUS_NONE
	no_btn.pressed.connect(_on_no)
	panel.add_child(no_btn)

func _on_yes() -> void:
	queue_free()
	var picker = load("res://scripts/ui/mastery_picker.gd").new()
	get_tree().root.add_child(picker)

func _on_no() -> void:
	GameState.mastery_picker_open = false
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_Y:
			get_viewport().set_input_as_handled()
			_on_yes()
		KEY_ESCAPE, KEY_N:
			get_viewport().set_input_as_handled()
			_on_no()
