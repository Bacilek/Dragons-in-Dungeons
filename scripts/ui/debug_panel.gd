extends CanvasLayer

const PANEL_W: int = 200
const PANEL_H: int = 122

const WEAPONS_PATH := "res://sprites/weapons/"
const ITEMS_PATH   := "res://sprites/items/Sprites trial/"

const ALL_ITEMS: Array = [
	{"name": "Rusty Sword",     "type": 0, "src": "weapons", "icon": "weapon_rusty_sword.png",                    "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "desc": "+1 damage"},
	{"name": "Short Sword",     "type": 0, "src": "weapons", "icon": "weapon_knife.png",                          "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "desc": "+1 damage"},
	{"name": "Sword",           "type": 0, "src": "weapons", "icon": "weapon_regular_sword.png",                  "bonus_dmg": 2, "heal": 0,   "str_bonus": 0, "desc": "+2 damage"},
	{"name": "Knight Sword",    "type": 0, "src": "weapons", "icon": "weapon_knight_sword.png",                   "bonus_dmg": 3, "heal": 0,   "str_bonus": 0, "desc": "+3 damage"},
	{"name": "Golden Sword",    "type": 0, "src": "weapons", "icon": "weapon_golden_sword.png",                   "bonus_dmg": 4, "heal": 0,   "str_bonus": 0, "desc": "+4 damage"},
	{"name": "Lavish Sword",    "type": 0, "src": "weapons", "icon": "weapon_lavish_sword.png",                   "bonus_dmg": 5, "heal": 0,   "str_bonus": 0, "desc": "+5 damage"},
	{"name": "Health Potion",   "type": 2, "src": "items",   "icon": "Potions/Health/HealthPotionMedium.png",     "bonus_dmg": 0, "heal": 10,  "str_bonus": 0, "desc": "Restores 10 HP"},
	{"name": "Strength Potion", "type": 2, "src": "items",   "icon": "Potions/Mana/ManaPotionMedium.png",         "bonus_dmg": 0, "heal": 0,   "str_bonus": 2, "desc": "+2 ATK (permanent)"},
	{"name": "Ration",          "type": 4, "src": "items",   "icon": "Food/MeatCooked.png",                       "bonus_dmg": 0, "heal": 200, "str_bonus": 0, "desc": "Fills you up"},
	{"name": "Mystery Meat",    "type": 4, "src": "items",   "icon": "Food/Meat.png",                             "bonus_dmg": 0, "heal": 120, "str_bonus": 0, "desc": "Better than nothing"},
	{"name": "Rotten Meat",     "type": 4, "src": "items",   "icon": "Food/Meat.png",                             "bonus_dmg": 0, "heal": 20,  "str_bonus": 0, "desc": "Throw into fire to cook"},
	{"name": "Thief Tools",     "type": 7, "src": "items",   "icon": "Misc/KeyIron.png",                          "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Disarm traps"},
]

var _main_panel: Panel
var _invincible_check: CheckBox
var _floor_sub: Panel
var _items_sub: Panel

func _ready() -> void:
	layer = 25
	_build_ui()

func _build_ui() -> void:
	_main_panel = Panel.new()
	_main_panel.anchor_left   = 1.0
	_main_panel.anchor_right  = 1.0
	_main_panel.anchor_top    = 0.0
	_main_panel.anchor_bottom = 0.0
	_main_panel.offset_left   = float(-PANEL_W - 4)
	_main_panel.offset_right  = -4.0
	_main_panel.offset_top    = 4.0
	_main_panel.offset_bottom = float(PANEL_H + 4)
	_main_panel.visible = false
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.06, 0.06, 0.96)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.85, 0.20, 0.20)
	ps.set_corner_radius_all(4)
	_main_panel.add_theme_stylebox_override("panel", ps)
	add_child(_main_panel)

	var title := Label.new()
	title.text = "DEBUG  [F3]"
	title.add_theme_font_size_override("font_size", 10)
	title.add_theme_color_override("font_color", Color(1.0, 0.35, 0.35))
	title.position = Vector2(8.0, 6.0)
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_main_panel.add_child(title)

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 24.0)
	sep.size = Vector2(PANEL_W - 12.0, 2.0)
	_main_panel.add_child(sep)

	_invincible_check = CheckBox.new()
	_invincible_check.text = "Invincible"
	_invincible_check.button_pressed = false
	_invincible_check.position = Vector2(8.0, 30.0)
	_invincible_check.add_theme_font_size_override("font_size", 11)
	_invincible_check.add_theme_color_override("font_color", Color(0.9, 0.9, 0.9))
	_invincible_check.toggled.connect(_on_invincible_toggled)
	_main_panel.add_child(_invincible_check)

	var jump_btn := _make_btn("Jump to Floor...", Color(0.25, 0.60, 1.0))
	jump_btn.position = Vector2(8.0, 62.0)
	jump_btn.size = Vector2(PANEL_W - 16.0, 24.0)
	jump_btn.pressed.connect(_on_jump_pressed)
	_main_panel.add_child(jump_btn)

	var items_btn := _make_btn("Give Item...", Color(0.35, 0.80, 0.35))
	items_btn.position = Vector2(8.0, 90.0)
	items_btn.size = Vector2(PANEL_W - 16.0, 24.0)
	items_btn.pressed.connect(_on_items_pressed)
	_main_panel.add_child(items_btn)

	_build_floor_sub()
	_build_items_sub()

func _make_btn(text: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 10)
	var n := StyleBoxFlat.new()
	n.bg_color = col * 0.28
	n.set_border_width_all(1)
	n.border_color = col * 0.70
	n.set_corner_radius_all(3)
	var h := StyleBoxFlat.new()
	h.bg_color = col * 0.48
	h.set_border_width_all(1)
	h.border_color = col
	h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover", h)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

func _build_floor_sub() -> void:
	const SW: int = 228
	const SH: int = 90
	_floor_sub = Panel.new()
	_floor_sub.anchor_left   = 1.0
	_floor_sub.anchor_right  = 1.0
	_floor_sub.anchor_top    = 0.0
	_floor_sub.anchor_bottom = 0.0
	_floor_sub.offset_left   = float(-PANEL_W - SW - 8)
	_floor_sub.offset_right  = float(-PANEL_W - 8)
	_floor_sub.offset_top    = 4.0
	_floor_sub.offset_bottom = float(SH + 4)
	_floor_sub.visible = false
	_floor_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.07, 0.10, 0.97)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.25, 0.60, 1.0)
	ps.set_corner_radius_all(4)
	_floor_sub.add_theme_stylebox_override("panel", ps)
	add_child(_floor_sub)

	var lbl := Label.new()
	lbl.text = "Jump to Floor"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.50, 0.80, 1.0))
	lbl.position = Vector2(8.0, 6.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_floor_sub.add_child(lbl)

	for i: int in 10:
		var fl: int = i + 1
		var is_boss: bool = fl % 5 == 0
		var col: Color = Color(1.0, 0.55, 0.10) if is_boss else Color(0.40, 0.75, 0.40)
		var btn := _make_btn("F%d%s" % [fl, "★" if is_boss else ""], col)
		btn.position = Vector2(6.0 + (i % 5) * 43.0, 26.0 + (i / 5) * 28.0)
		btn.size = Vector2(39.0, 22.0)
		btn.pressed.connect(_on_floor_selected.bind(fl))
		_floor_sub.add_child(btn)

func _build_items_sub() -> void:
	const SW: int = 390
	const SH: int = 370
	_items_sub = Panel.new()
	_items_sub.anchor_left   = 1.0
	_items_sub.anchor_right  = 1.0
	_items_sub.anchor_top    = 0.0
	_items_sub.anchor_bottom = 0.0
	_items_sub.offset_left   = float(-PANEL_W - SW - 8)
	_items_sub.offset_right  = float(-PANEL_W - 8)
	_items_sub.offset_top    = 4.0
	_items_sub.offset_bottom = float(SH + 4)
	_items_sub.visible = false
	_items_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.07, 0.07, 0.10, 0.97)
	ps.set_border_width_all(2)
	ps.border_color = Color(0.30, 0.85, 0.30)
	ps.set_corner_radius_all(4)
	_items_sub.add_theme_stylebox_override("panel", ps)
	add_child(_items_sub)

	var lbl := Label.new()
	lbl.text = "Item Browser  —  left-click to give ×1"
	lbl.add_theme_font_size_override("font_size", 10)
	lbl.add_theme_color_override("font_color", Color(0.40, 1.0, 0.40))
	lbl.position = Vector2(8.0, 6.0)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_items_sub.add_child(lbl)

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 24.0)
	sep.size = Vector2(SW - 12.0, 2.0)
	_items_sub.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(SW - 12.0, SH - 38.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_sub.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 3)
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	scroll.add_child(vbox)

	for d: Dictionary in ALL_ITEMS:
		vbox.add_child(_make_item_row(d))

func _make_item_row(d: Dictionary) -> Control:
	var row := Panel.new()
	row.custom_minimum_size = Vector2(0.0, 38.0)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	var rs := StyleBoxFlat.new()
	rs.bg_color = Color(0.10, 0.10, 0.14, 0.85)
	rs.set_border_width_all(1)
	rs.border_color = Color(0.24, 0.24, 0.30)
	rs.set_corner_radius_all(2)
	row.add_theme_stylebox_override("panel", rs)

	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(4.0, 4.0)
	icon.size = Vector2(30.0, 30.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var icon_path: String = ""
	match d["src"]:
		"weapons": icon_path = WEAPONS_PATH + d["icon"]
		"items":   icon_path = ITEMS_PATH + d["icon"]
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	row.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = d["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	name_lbl.position = Vector2(40.0, 4.0)
	name_lbl.size = Vector2(220.0, 15.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = d["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	desc_lbl.position = Vector2(40.0, 21.0)
	desc_lbl.size = Vector2(220.0, 13.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	row.add_child(desc_lbl)

	var give_btn := _make_btn("Give", Color(0.40, 0.80, 0.40))
	give_btn.position = Vector2(272.0, 7.0)
	give_btn.size = Vector2(52.0, 24.0)
	give_btn.pressed.connect(_on_give_item.bind(d))
	row.add_child(give_btn)

	return row

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		get_viewport().set_input_as_handled()
		_main_panel.visible = not _main_panel.visible
		if not _main_panel.visible:
			_floor_sub.visible = false
			_items_sub.visible = false

func _on_invincible_toggled(pressed: bool) -> void:
	GameState.invincible = pressed
	if pressed:
		GameState.game_log("[color=red][DEBUG] Invincible ON[/color]")
	else:
		GameState.game_log("[color=gray][DEBUG] Invincible OFF[/color]")

func _on_jump_pressed() -> void:
	_floor_sub.visible = not _floor_sub.visible
	if _floor_sub.visible:
		_items_sub.visible = false

func _on_items_pressed() -> void:
	_items_sub.visible = not _items_sub.visible
	if _items_sub.visible:
		_floor_sub.visible = false

func _on_floor_selected(floor_num: int) -> void:
	_floor_sub.visible = false
	_main_panel.visible = false
	GameState.game_log("[color=cyan][DEBUG] Jumping to floor %d…[/color]" % floor_num)
	GameState.debug_jump_to_floor(floor_num)

func _on_give_item(d: Dictionary) -> void:
	var item := Item.new()
	item.item_name = d["name"]
	item.item_type = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.str_bonus = d.get("str_bonus", 0)
	item.description = d["desc"]
	match d["src"]:
		"weapons": item.icon_path = WEAPONS_PATH + d["icon"]
		"items":   item.icon_path = ITEMS_PATH + d["icon"]
	item.quantity = 3 if d["name"] == "Thief Tools" else 1
	if not GameState.add_item(item):
		GameState.game_log("[color=red][DEBUG] Inventory full — cannot give %s[/color]" % d["name"])
	else:
		GameState.game_log("[color=lime][DEBUG] Given: %s[/color]" % d["name"])
