extends CanvasLayer

var _dice_to_spend: int = 0

var _dice_label: Label
var _preview_label: Label
var _rests_label: Label
var _dice_avail_label: Label
var _rest_btn: Button

func _ready() -> void:
	layer = 25
	_dice_to_spend = mini(1, GameState.hit_dice)
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.48)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton:
			var mb := ev as InputEventMouseButton
			if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
				_close())
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(400.0, 260.0)
	var vp := get_viewport().get_visible_rect().size
	panel.position = (vp - panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.35, 0.45, 0.78)
	sbox.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var title := Label.new()
	title.text = "Short Rest  [Alt]"
	title.add_theme_font_size_override("font_size", 16)
	title.add_theme_color_override("font_color", Color(0.72, 0.80, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(400.0, 28.0)
	title.position = Vector2(0.0, 12.0)
	panel.add_child(title)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(12.0, 44.0)
	sep1.size = Vector2(376.0, 2.0)
	panel.add_child(sep1)

	_rests_label = Label.new()
	_rests_label.add_theme_font_size_override("font_size", 11)
	_rests_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.68))
	_rests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rests_label.size = Vector2(400.0, 16.0)
	_rests_label.position = Vector2(0.0, 50.0)
	panel.add_child(_rests_label)

	_dice_avail_label = Label.new()
	_dice_avail_label.add_theme_font_size_override("font_size", 11)
	_dice_avail_label.add_theme_color_override("font_color", Color(0.50, 0.78, 0.50))
	_dice_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_avail_label.size = Vector2(400.0, 16.0)
	_dice_avail_label.position = Vector2(0.0, 70.0)
	panel.add_child(_dice_avail_label)

	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.size = Vector2(50.0, 50.0)
	minus_btn.position = Vector2(60.0, 94.0)
	_style_btn(minus_btn, 20)
	minus_btn.pressed.connect(_on_minus)
	panel.add_child(minus_btn)

	_dice_label = Label.new()
	_dice_label.add_theme_font_size_override("font_size", 40)
	_dice_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_label.size = Vector2(160.0, 58.0)
	_dice_label.position = Vector2(120.0, 90.0)
	panel.add_child(_dice_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size = Vector2(50.0, 50.0)
	plus_btn.position = Vector2(290.0, 94.0)
	_style_btn(plus_btn, 20)
	plus_btn.pressed.connect(_on_plus)
	panel.add_child(plus_btn)

	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 10)
	_preview_label.add_theme_color_override("font_color", Color(0.42, 0.82, 0.42))
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.size = Vector2(400.0, 16.0)
	_preview_label.position = Vector2(0.0, 156.0)
	panel.add_child(_preview_label)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, 178.0)
	sep2.size = Vector2(376.0, 2.0)
	panel.add_child(sep2)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel  [Esc]"
	cancel_btn.size = Vector2(160.0, 36.0)
	cancel_btn.position = Vector2(18.0, 188.0)
	cancel_btn.add_theme_font_size_override("font_size", 12)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(_close)
	panel.add_child(cancel_btn)

	_rest_btn = Button.new()
	_rest_btn.text = "Rest  [Enter]"
	_rest_btn.size = Vector2(160.0, 36.0)
	_rest_btn.position = Vector2(222.0, 188.0)
	_rest_btn.add_theme_font_size_override("font_size", 12)
	_rest_btn.pressed.connect(_on_rest)
	_style_rest_btn()
	panel.add_child(_rest_btn)

	_refresh()

func _style_btn(btn: Button, font_size: int = 12) -> void:
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
	btn.add_theme_font_size_override("font_size", font_size)
	btn.focus_mode = Control.FOCUS_NONE

func _style_rest_btn() -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.28, 0.14, 1.0)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.28, 0.65, 0.32)
	normal.set_corner_radius_all(4)
	_rest_btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.40, 0.20, 1.0)
	hover.set_corner_radius_all(4)
	_rest_btn.add_theme_stylebox_override("hover", hover)

func _refresh() -> void:
	var sides: int = GameState.hit_die_sides()
	var con_mod: int = GameState.player_stats.con_modifier()
	var level: int = GameState.player_stats.character_level
	_rests_label.text = "Short rests remaining this floor: %d / %d" % [GameState.short_rests_remaining, GameState.max_short_rests]
	_dice_avail_label.text = "Hit dice available: %d / %d   (d%d)" % [GameState.hit_dice, level, sides]
	_dice_label.text = str(_dice_to_spend)

	if _dice_to_spend == 0 or GameState.hit_dice == 0:
		_preview_label.text = "Select dice above to rest."
		_rest_btn.disabled = true
	else:
		var total_con: int = con_mod * _dice_to_spend
		var min_heal: int = maxi(_dice_to_spend, _dice_to_spend + total_con)
		var max_heal: int = maxi(_dice_to_spend, _dice_to_spend * sides + total_con)
		if con_mod != 0:
			_preview_label.text = "Heal: %d–%d HP  (%d×d%d  %+d CON per die)" % [min_heal, max_heal, _dice_to_spend, sides, con_mod]
		else:
			_preview_label.text = "Heal: %d–%d HP  (%d×d%d)" % [min_heal, max_heal, _dice_to_spend, sides]
		_rest_btn.disabled = false

func _on_minus() -> void:
	_dice_to_spend = maxi(0, _dice_to_spend - 1)
	_refresh()

func _on_plus() -> void:
	_dice_to_spend = mini(GameState.hit_dice, _dice_to_spend + 1)
	_refresh()

func _on_rest() -> void:
	if _dice_to_spend <= 0 or GameState.hit_dice <= 0:
		return
	var sides: int = GameState.hit_die_sides()
	var con_mod: int = GameState.player_stats.con_modifier()
	var total_heal: int = 0
	for _i: int in _dice_to_spend:
		total_heal += maxi(1, randi_range(1, sides) + con_mod)
	GameState.hit_dice -= _dice_to_spend
	GameState.short_rests_remaining -= 1
	GameState.short_rest_pending_heal = total_heal
	GameState.short_rest_active = true
	GameState.short_rest_turns_remaining = 5
	GameState.game_log("[color=cyan]You settle in for a short rest... (5 turns)[/color]")
	GameState.short_rest_changed.emit()
	GameState.player_action_requested.emit("short_rest_begin")
	_close()

func _close() -> void:
	GameState.short_rest_open = false
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	match key.physical_keycode:
		KEY_ESCAPE, KEY_ALT:
			get_viewport().set_input_as_handled()
			_close()
		KEY_LEFT, KEY_A, KEY_KP_4:
			get_viewport().set_input_as_handled()
			_on_minus()
		KEY_RIGHT, KEY_D, KEY_KP_6:
			get_viewport().set_input_as_handled()
			_on_plus()
		KEY_ENTER, KEY_KP_ENTER:
			if not _rest_btn.disabled:
				get_viewport().set_input_as_handled()
				_on_rest()
