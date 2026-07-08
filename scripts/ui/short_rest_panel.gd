extends CanvasLayer

enum Tab { SHORT, LONG }

const PANEL_SIZE: Vector2 = Vector2(520.0, 400.0)

var _active_tab: int = Tab.SHORT
var _dice_to_spend: int = 0

var _tab_short_btn: Button
var _tab_long_btn: Button

var _short_container: Control
var _long_container: Control

# Short rest widgets
var _dice_label: Label
var _preview_label: Label
var _rests_label: Label
var _dice_avail_label: Label
var _rest_btn: Button

# Long rest widgets
var _food_label: Label
var _duration_label: Label
var _long_reason_label: Label
var _long_rest_btn: Button

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
	panel.size = PANEL_SIZE
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
	title.text = "Rest  [Alt]"
	title.add_theme_font_size_override("font_size", 21)
	title.add_theme_color_override("font_color", Color(0.72, 0.80, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(PANEL_SIZE.x, 32.0)
	title.position = Vector2(0.0, 10.0)
	panel.add_child(title)

	# ── Tab bar ────────────────────────────────────────────────────────────────
	_tab_short_btn = Button.new()
	_tab_short_btn.text = "Short Rest"
	_tab_short_btn.size = Vector2(PANEL_SIZE.x * 0.5 - 16.0, 36.0)
	_tab_short_btn.position = Vector2(14.0, 46.0)
	_tab_short_btn.add_theme_font_size_override("font_size", 15)
	_tab_short_btn.pressed.connect(func() -> void: _set_tab(Tab.SHORT))
	panel.add_child(_tab_short_btn)

	_tab_long_btn = Button.new()
	_tab_long_btn.text = "Long Rest"
	_tab_long_btn.size = Vector2(PANEL_SIZE.x * 0.5 - 16.0, 36.0)
	_tab_long_btn.position = Vector2(PANEL_SIZE.x * 0.5 + 2.0, 46.0)
	_tab_long_btn.add_theme_font_size_override("font_size", 15)
	_tab_long_btn.pressed.connect(func() -> void: _set_tab(Tab.LONG))
	panel.add_child(_tab_long_btn)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(14.0, 90.0)
	sep1.size = Vector2(PANEL_SIZE.x - 28.0, 2.0)
	panel.add_child(sep1)

	_build_short_container(panel)
	_build_long_container(panel)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(14.0, 292.0)
	sep2.size = Vector2(PANEL_SIZE.x - 28.0, 2.0)
	panel.add_child(sep2)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel  [Esc]"
	cancel_btn.size = Vector2(208.0, 48.0)
	cancel_btn.position = Vector2(24.0, 306.0)
	cancel_btn.add_theme_font_size_override("font_size", 16)
	cancel_btn.focus_mode = Control.FOCUS_NONE
	cancel_btn.pressed.connect(_close)
	panel.add_child(cancel_btn)

	_rest_btn = Button.new()
	_rest_btn.text = "Rest  [Space]"
	_rest_btn.size = Vector2(208.0, 48.0)
	_rest_btn.position = Vector2(288.0, 306.0)
	_rest_btn.add_theme_font_size_override("font_size", 16)
	_rest_btn.pressed.connect(_on_rest)
	_style_rest_btn(_rest_btn)
	panel.add_child(_rest_btn)

	_long_rest_btn = Button.new()
	_long_rest_btn.text = "Long Rest  [Space]"
	_long_rest_btn.size = Vector2(208.0, 48.0)
	_long_rest_btn.position = Vector2(288.0, 306.0)
	_long_rest_btn.add_theme_font_size_override("font_size", 16)
	_long_rest_btn.pressed.connect(_on_long_rest)
	_style_rest_btn(_long_rest_btn)
	panel.add_child(_long_rest_btn)

	_set_tab(Tab.SHORT)

func _build_short_container(panel: Panel) -> void:
	_short_container = Control.new()
	_short_container.position = Vector2(0.0, 98.0)
	_short_container.size = Vector2(PANEL_SIZE.x, 190.0)
	panel.add_child(_short_container)

	_rests_label = Label.new()
	_rests_label.add_theme_font_size_override("font_size", 15)
	_rests_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.68))
	_rests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rests_label.size = Vector2(PANEL_SIZE.x, 22.0)
	_rests_label.position = Vector2(0.0, 0.0)
	_short_container.add_child(_rests_label)

	_dice_avail_label = Label.new()
	_dice_avail_label.add_theme_font_size_override("font_size", 15)
	_dice_avail_label.add_theme_color_override("font_color", Color(0.50, 0.78, 0.50))
	_dice_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_avail_label.size = Vector2(PANEL_SIZE.x, 22.0)
	_dice_avail_label.position = Vector2(0.0, 26.0)
	_short_container.add_child(_dice_avail_label)

	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.size = Vector2(65.0, 65.0)
	minus_btn.position = Vector2(70.0, 56.0)
	_style_btn(minus_btn, 26)
	minus_btn.pressed.connect(_on_minus)
	_short_container.add_child(minus_btn)

	_dice_label = Label.new()
	_dice_label.add_theme_font_size_override("font_size", 52)
	_dice_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_label.size = Vector2(210.0, 74.0)
	_dice_label.position = Vector2(155.0, 53.0)
	_short_container.add_child(_dice_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size = Vector2(65.0, 65.0)
	plus_btn.position = Vector2(385.0, 56.0)
	_style_btn(plus_btn, 26)
	plus_btn.pressed.connect(_on_plus)
	_short_container.add_child(plus_btn)

	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 13)
	_preview_label.add_theme_color_override("font_color", Color(0.42, 0.82, 0.42))
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.size = Vector2(PANEL_SIZE.x, 22.0)
	_preview_label.position = Vector2(0.0, 140.0)
	_short_container.add_child(_preview_label)

func _build_long_container(panel: Panel) -> void:
	_long_container = Control.new()
	_long_container.position = Vector2(0.0, 98.0)
	_long_container.size = Vector2(PANEL_SIZE.x, 190.0)
	panel.add_child(_long_container)

	var blurb := Label.new()
	blurb.text = "Fully heals you, restores hit dice/short rests, and refreshes long-rest abilities."
	blurb.autowrap_mode = TextServer.AUTOWRAP_WORD
	blurb.add_theme_font_size_override("font_size", 14)
	blurb.add_theme_color_override("font_color", Color(0.75, 0.75, 0.85))
	blurb.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	blurb.size = Vector2(PANEL_SIZE.x - 60.0, 44.0)
	blurb.position = Vector2(30.0, 6.0)
	_long_container.add_child(blurb)

	_food_label = Label.new()
	_food_label.add_theme_font_size_override("font_size", 17)
	_food_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_food_label.size = Vector2(PANEL_SIZE.x, 26.0)
	_food_label.position = Vector2(0.0, 62.0)
	_long_container.add_child(_food_label)

	_duration_label = Label.new()
	_duration_label.add_theme_font_size_override("font_size", 15)
	_duration_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.68))
	_duration_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_duration_label.size = Vector2(PANEL_SIZE.x, 22.0)
	_duration_label.position = Vector2(0.0, 92.0)
	_duration_label.text = "Takes %d turns to complete (enemies can interrupt)." % GameState.LONG_REST_TURNS
	_long_container.add_child(_duration_label)

	_long_reason_label = Label.new()
	_long_reason_label.add_theme_font_size_override("font_size", 13)
	_long_reason_label.add_theme_color_override("font_color", Color(0.80, 0.42, 0.42))
	_long_reason_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_long_reason_label.size = Vector2(PANEL_SIZE.x, 22.0)
	_long_reason_label.position = Vector2(0.0, 140.0)
	_long_container.add_child(_long_reason_label)

func _set_tab(tab: int) -> void:
	_active_tab = tab
	_short_container.visible = tab == Tab.SHORT
	_long_container.visible = tab == Tab.LONG
	_rest_btn.visible = tab == Tab.SHORT
	_long_rest_btn.visible = tab == Tab.LONG
	_style_tab_btn(_tab_short_btn, tab == Tab.SHORT)
	_style_tab_btn(_tab_long_btn, tab == Tab.LONG)
	_refresh()

func _style_tab_btn(btn: Button, active: bool) -> void:
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.20, 0.24, 0.42, 1.0) if active else Color(0.12, 0.12, 0.18, 1.0)
	sbox.set_border_width_all(1)
	sbox.border_color = Color(0.55, 0.62, 0.90) if active else Color(0.32, 0.32, 0.42)
	sbox.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", sbox)
	btn.add_theme_stylebox_override("hover", sbox)
	btn.add_theme_stylebox_override("pressed", sbox)
	btn.focus_mode = Control.FOCUS_NONE

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

func _style_rest_btn(btn: Button) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.12, 0.28, 0.14, 1.0)
	normal.set_border_width_all(1)
	normal.border_color = Color(0.28, 0.65, 0.32)
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.18, 0.40, 0.20, 1.0)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)
	btn.focus_mode = Control.FOCUS_NONE

func _refresh() -> void:
	if _active_tab == Tab.SHORT:
		_refresh_short()
	else:
		_refresh_long()

func _refresh_short() -> void:
	var sides: int = GameState.hit_die_sides()
	var con_mod: int = GameState.player_stats.con_modifier()
	var level: int = GameState.max_hit_dice()
	_rests_label.text = "Short rests remaining: %d / %d" % [GameState.short_rests_remaining, GameState.max_short_rests]
	_dice_avail_label.text = "Hit dice available: %d / %d   (d%d)" % [GameState.hit_dice, level, sides]
	_dice_label.text = str(_dice_to_spend)

	if GameState.short_rests_remaining <= 0:
		_preview_label.text = "No short rests remaining. A long rest resets them."
		_rest_btn.disabled = true
	elif _dice_to_spend == 0 or GameState.hit_dice == 0:
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

func _refresh_long() -> void:
	var have: int = GameState.total_food_value()
	var need: int = GameState.LONG_REST_FOOD_COST
	_food_label.text = "Food value: %d / %d" % [have, need]
	_food_label.add_theme_color_override("font_color", Color(0.50, 0.78, 0.50) if have >= need else Color(0.80, 0.55, 0.30))
	if GameState.can_long_rest():
		_long_reason_label.text = ""
		_long_rest_btn.disabled = false
	else:
		_long_reason_label.text = "Not enough food — sacrifice FOOD items worth %d total." % need
		_long_rest_btn.disabled = true

func _on_minus() -> void:
	_dice_to_spend = maxi(0, _dice_to_spend - 1)
	_refresh()

func _on_plus() -> void:
	_dice_to_spend = mini(GameState.hit_dice, _dice_to_spend + 1)
	_refresh()

func _on_rest() -> void:
	if _rest_btn.disabled or _dice_to_spend <= 0 or GameState.hit_dice <= 0:
		return
	var sides: int = GameState.hit_die_sides()
	var con_mod: int = GameState.player_stats.con_modifier()
	var total_heal: int = 0
	for _i: int in _dice_to_spend:
		total_heal += maxi(1, Rng.roll(sides) + con_mod)
	if not GameState.invincible:
		GameState.hit_dice -= _dice_to_spend
	GameState.short_rests_remaining -= 1
	GameState.short_rest_pending_heal = total_heal
	GameState.short_rest_active = true
	GameState.short_rest_turns_remaining = GameState.SHORT_REST_TURNS
	GameState.game_log("[color=cyan]You settle in for a short rest... (%d turns)[/color]" % GameState.SHORT_REST_TURNS)
	GameState.short_rest_changed.emit()
	# Close BEFORE emitting "short_rest_begin" — the signal is synchronous and
	# _on_turn_started fires inside the chain; it must see short_rest_open = false
	# or it returns early, making the first rest turn require a manual keypress.
	GameState.short_rest_open = false
	queue_free()
	GameState.player_action_requested.emit("short_rest_begin")

func _on_long_rest() -> void:
	if _long_rest_btn.disabled or not GameState.can_long_rest():
		return
	GameState.long_rest_pending = true
	GameState.short_rest_active = true
	GameState.short_rest_turns_remaining = GameState.LONG_REST_TURNS
	GameState.game_log("[color=cyan]You settle in for a long rest... (%d turns)[/color]" % GameState.LONG_REST_TURNS)
	GameState.short_rest_changed.emit()
	GameState.short_rest_open = false
	queue_free()
	GameState.player_action_requested.emit("short_rest_begin")

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
			if _active_tab == Tab.SHORT:
				get_viewport().set_input_as_handled()
				_on_minus()
		KEY_RIGHT, KEY_D, KEY_KP_6:
			if _active_tab == Tab.SHORT:
				get_viewport().set_input_as_handled()
				_on_plus()
		KEY_TAB:
			get_viewport().set_input_as_handled()
			_set_tab(Tab.LONG if _active_tab == Tab.SHORT else Tab.SHORT)
		KEY_SPACE:
			get_viewport().set_input_as_handled()
			if _active_tab == Tab.SHORT and not _rest_btn.disabled:
				_on_rest()
			elif _active_tab == Tab.LONG and not _long_rest_btn.disabled:
				_on_long_rest()
