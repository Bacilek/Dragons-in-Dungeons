extends CanvasLayer

func _ready() -> void:
	layer = 26
	_build_ui()

func _build_ui() -> void:
	var panel := Panel.new()
	panel.size = Vector2(260.0, 96.0)
	var vp := get_viewport().get_visible_rect().size
	panel.position = (vp - panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.12, 0.06, 0.06, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.30, 0.30)
	sbox.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var title := Label.new()
	title.text = "Enemy spotted!"
	title.add_theme_font_size_override("font_size", 12)
	title.add_theme_color_override("font_color", Color(0.95, 0.40, 0.40))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(260.0, 20.0)
	title.position = Vector2(0.0, 8.0)
	panel.add_child(title)

	var body := Label.new()
	body.text = "Continue resting (risky) or abort?"
	body.add_theme_font_size_override("font_size", 9)
	body.add_theme_color_override("font_color", Color(0.80, 0.80, 0.80))
	body.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	body.size = Vector2(260.0, 14.0)
	body.position = Vector2(0.0, 32.0)
	panel.add_child(body)

	var continue_btn := Button.new()
	continue_btn.text = "Continue"
	continue_btn.size = Vector2(108.0, 28.0)
	continue_btn.position = Vector2(14.0, 56.0)
	continue_btn.pressed.connect(_on_continue)
	panel.add_child(continue_btn)

	var abort_btn := Button.new()
	abort_btn.text = "Abort (lose HP)"
	abort_btn.size = Vector2(120.0, 28.0)
	abort_btn.position = Vector2(128.0, 56.0)
	var sbox_abort := StyleBoxFlat.new()
	sbox_abort.bg_color = Color(0.28, 0.10, 0.10, 1.0)
	sbox_abort.set_border_width_all(1)
	sbox_abort.border_color = Color(0.70, 0.25, 0.25)
	sbox_abort.set_corner_radius_all(4)
	abort_btn.add_theme_stylebox_override("normal", sbox_abort)
	abort_btn.pressed.connect(_on_abort)
	panel.add_child(abort_btn)

func _on_continue() -> void:
	GameState.short_rest_open = false
	queue_free()
	GameState.player_action_requested.emit("short_rest_begin")

func _on_abort() -> void:
	GameState.short_rest_active = false
	GameState.short_rest_pending_heal = 0
	GameState.short_rest_open = false
	GameState.short_rest_changed.emit()
	GameState.game_log("[color=orange]You abandon your rest. The hit dice were spent.[/color]")
	queue_free()
