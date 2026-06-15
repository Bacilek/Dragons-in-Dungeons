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
	add_child(dim)

	var panel := Panel.new()
	panel.size = Vector2(274.0, 192.0)
	panel.position = Vector2(640.0 - 137.0, 360.0 - 96.0)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.35, 0.45, 0.78)
	sbox.set_corner_radius_all(6)
	panel.add_theme_stylebox_override("panel", sbox)
	add_child(panel)

	var title := Label.new()
	title.text = "Short Rest  [Alt]"
	title.add_theme_font_size_override("font_size", 14)
	title.add_theme_color_override("font_color", Color(0.72, 0.80, 1.0))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(274.0, 22.0)
	title.position = Vector2(0.0, 10.0)
	panel.add_child(title)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(12.0, 36.0)
	sep1.size = Vector2(250.0, 2.0)
	panel.add_child(sep1)

	_rests_label = Label.new()
	_rests_label.add_theme_font_size_override("font_size", 9)
	_rests_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.68))
	_rests_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_rests_label.size = Vector2(274.0, 13.0)
	_rests_label.position = Vector2(0.0, 42.0)
	panel.add_child(_rests_label)

	_dice_avail_label = Label.new()
	_dice_avail_label.add_theme_font_size_override("font_size", 9)
	_dice_avail_label.add_theme_color_override("font_color", Color(0.50, 0.78, 0.50))
	_dice_avail_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_avail_label.size = Vector2(274.0, 13.0)
	_dice_avail_label.position = Vector2(0.0, 57.0)
	panel.add_child(_dice_avail_label)

	var minus_btn := Button.new()
	minus_btn.text = "−"
	minus_btn.size = Vector2(36.0, 36.0)
	minus_btn.position = Vector2(50.0, 78.0)
	_style_btn(minus_btn)
	minus_btn.pressed.connect(_on_minus)
	panel.add_child(minus_btn)

	_dice_label = Label.new()
	_dice_label.add_theme_font_size_override("font_size", 32)
	_dice_label.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_dice_label.size = Vector2(102.0, 40.0)
	_dice_label.position = Vector2(86.0, 76.0)
	panel.add_child(_dice_label)

	var plus_btn := Button.new()
	plus_btn.text = "+"
	plus_btn.size = Vector2(36.0, 36.0)
	plus_btn.position = Vector2(188.0, 78.0)
	_style_btn(plus_btn)
	plus_btn.pressed.connect(_on_plus)
	panel.add_child(plus_btn)

	_preview_label = Label.new()
	_preview_label.add_theme_font_size_override("font_size", 9)
	_preview_label.add_theme_color_override("font_color", Color(0.42, 0.82, 0.42))
	_preview_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_preview_label.size = Vector2(274.0, 13.0)
	_preview_label.position = Vector2(0.0, 124.0)
	panel.add_child(_preview_label)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, 144.0)
	sep2.size = Vector2(250.0, 2.0)
	panel.add_child(sep2)

	var cancel_btn := Button.new()
	cancel_btn.text = "Cancel  [Esc]"
	cancel_btn.size = Vector2(106.0, 28.0)
	cancel_btn.position = Vector2(18.0, 152.0)
	cancel_btn.pressed.connect(_close)
	panel.add_child(cancel_btn)

	_rest_btn = Button.new()
	_rest_btn.text = "Rest"
	_rest_btn.size = Vector2(106.0, 28.0)
	_rest_btn.position = Vector2(150.0, 152.0)
	_rest_btn.pressed.connect(_on_rest)
	_style_rest_btn()
	panel.add_child(_rest_btn)

	_refresh()

func _style_btn(btn: Button) -> void:
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
	_rests_label.text = "Short rests remaining this floor: %d / 2" % GameState.short_rests_remaining
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
	var before_hp: int = GameState.player_stats.current_hp
	GameState.heal(total_heal)
	var actual: int = GameState.player_stats.current_hp - before_hp
	var rests_left: int = GameState.short_rests_remaining
	GameState.game_log("[color=cyan]Short rest: spent %d d%d — healed [b]+%d HP[/b]. (%d rest%s left this floor)[/color]" % [
		_dice_to_spend, sides, actual,
		rests_left, "s" if rests_left != 1 else "",
	])
	GameState.short_rest_changed.emit()
	_close()

func _close() -> void:
	GameState.short_rest_open = false
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_ESCAPE:
			get_viewport().set_input_as_handled()
			_close()
