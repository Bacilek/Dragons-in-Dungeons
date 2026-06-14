extends CanvasLayer

const PANEL_W:  int = 200
const PANEL_H:  int = 130
const FLOOR_SW: int = 234
const FLOOR_SH: int = 96
const ITEMS_SW: int = 390
const ITEMS_SH: int = 370

const WEAPONS_PATH := "res://sprites/weapons/"
const ITEMS_PATH   := "res://sprites/items/Sprites trial/"

const ALL_ITEMS: Array = [
	{"name": "Rusty Sword",     "type": 0, "src": "weapons", "icon": "weapon_rusty_sword.png",                "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "desc": "+1 damage"},
	{"name": "Short Sword",     "type": 0, "src": "weapons", "icon": "weapon_knife.png",                      "bonus_dmg": 1, "heal": 0,   "str_bonus": 0, "desc": "+1 damage"},
	{"name": "Sword",           "type": 0, "src": "weapons", "icon": "weapon_regular_sword.png",              "bonus_dmg": 2, "heal": 0,   "str_bonus": 0, "desc": "+2 damage"},
	{"name": "Knight Sword",    "type": 0, "src": "weapons", "icon": "weapon_knight_sword.png",               "bonus_dmg": 3, "heal": 0,   "str_bonus": 0, "desc": "+3 damage"},
	{"name": "Golden Sword",    "type": 0, "src": "weapons", "icon": "weapon_golden_sword.png",               "bonus_dmg": 4, "heal": 0,   "str_bonus": 0, "desc": "+4 damage"},
	{"name": "Lavish Sword",    "type": 0, "src": "weapons", "icon": "weapon_lavish_sword.png",               "bonus_dmg": 5, "heal": 0,   "str_bonus": 0, "desc": "+5 damage"},
	{"name": "Health Potion",   "type": 2, "src": "items",   "icon": "Potions/Health/HealthPotionMedium.png", "bonus_dmg": 0, "heal": 10,  "str_bonus": 0, "desc": "Restores 10 HP"},
	{"name": "Strength Potion", "type": 2, "src": "items",   "icon": "Potions/Mana/ManaPotionMedium.png",     "bonus_dmg": 0, "heal": 0,   "str_bonus": 2, "desc": "+2 ATK (permanent)"},
	{"name": "Ration",          "type": 4, "src": "items",   "icon": "Food/MeatCooked.png",                   "bonus_dmg": 0, "heal": 200, "str_bonus": 0, "desc": "Fills you up"},
	{"name": "Mystery Meat",    "type": 4, "src": "items",   "icon": "Food/Meat.png",                         "bonus_dmg": 0, "heal": 120, "str_bonus": 0, "desc": "Better than nothing"},
	{"name": "Rotten Meat",     "type": 4, "src": "items",   "icon": "Food/Meat.png",                         "bonus_dmg": 0, "heal": 20,  "str_bonus": 0, "desc": "Throw into fire to cook"},
	{"name": "Thief Tools",     "type": 7, "src": "items",   "icon": "Misc/KeyIron.png",                      "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Disarm traps"},
]

var _main_panel:  Panel
var _floor_sub:   Panel
var _items_sub:   Panel
var _inv_check:   CheckBox

func _ready() -> void:
	layer = 25
	_build_main_panel()
	_build_floor_sub()
	_build_items_sub()
	call_deferred("_reposition")

# ── Positioning ───────────────────────────────────────────────────────────────

func _reposition() -> void:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_main_panel.position = Vector2(vp_w - PANEL_W - 4.0, 4.0)
	_floor_sub.position  = Vector2(vp_w - PANEL_W - FLOOR_SW - 8.0, 4.0)
	_items_sub.position  = Vector2(vp_w - PANEL_W - ITEMS_SW - 8.0, 4.0)

# ── Panel builders ────────────────────────────────────────────────────────────

func _build_main_panel() -> void:
	_main_panel = Panel.new()
	_main_panel.visible = true
	_main_panel.size = Vector2(PANEL_W, PANEL_H)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_main_panel, Color(0.07, 0.06, 0.06, 0.96), Color(0.85, 0.20, 0.20))
	add_child(_main_panel)

	_add_label(_main_panel, "DEBUG  [F3]", 8, 6, 10, Color(1.0, 0.35, 0.35))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 24.0)
	sep.size = Vector2(PANEL_W - 12.0, 4.0)
	_main_panel.add_child(sep)

	_inv_check = CheckBox.new()
	_inv_check.text = "Invincible"
	_inv_check.position = Vector2(6.0, 30.0)
	_inv_check.size = Vector2(PANEL_W - 12.0, 28.0)
	_inv_check.add_theme_font_size_override("font_size", 11)
	_inv_check.toggled.connect(_on_invincible_toggled)
	_main_panel.add_child(_inv_check)

	var jump_btn := _make_btn("Jump to Floor...", Color(0.25, 0.60, 1.0))
	jump_btn.position = Vector2(6.0, 62.0)
	jump_btn.size = Vector2(PANEL_W - 12.0, 26.0)
	jump_btn.pressed.connect(_on_jump_pressed)
	_main_panel.add_child(jump_btn)

	var items_btn := _make_btn("Give Item...", Color(0.35, 0.80, 0.35))
	items_btn.position = Vector2(6.0, 92.0)
	items_btn.size = Vector2(PANEL_W - 12.0, 26.0)
	items_btn.pressed.connect(_on_items_pressed)
	_main_panel.add_child(items_btn)

func _build_floor_sub() -> void:
	_floor_sub = Panel.new()
	_floor_sub.visible = false
	_floor_sub.size = Vector2(FLOOR_SW, FLOOR_SH)
	_floor_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_floor_sub, Color(0.07, 0.07, 0.10, 0.97), Color(0.25, 0.60, 1.0))
	add_child(_floor_sub)

	_add_label(_floor_sub, "Jump to Floor", 8, 5, 10, Color(0.50, 0.80, 1.0))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(FLOOR_SW - 12.0, 4.0)
	_floor_sub.add_child(sep)

	for i: int in 10:
		var fl: int = i + 1
		var is_boss: bool = fl % 5 == 0
		var col: Color = Color(1.0, 0.55, 0.10) if is_boss else Color(0.40, 0.75, 0.40)
		var lbl: String = "F%d%s" % [fl, "★" if is_boss else ""]
		var btn := _make_btn(lbl, col)
		btn.position = Vector2(6.0 + (i % 5) * 44.0, 28.0 + (i / 5) * 30.0)
		btn.size = Vector2(40.0, 24.0)
		btn.pressed.connect(_on_floor_selected.bind(fl))
		_floor_sub.add_child(btn)

func _build_items_sub() -> void:
	_items_sub = Panel.new()
	_items_sub.visible = false
	_items_sub.size = Vector2(ITEMS_SW, ITEMS_SH)
	_items_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_items_sub, Color(0.07, 0.07, 0.10, 0.97), Color(0.30, 0.85, 0.30))
	add_child(_items_sub)

	_add_label(_items_sub, "Item Browser  —  click Give to receive ×1", 8, 5, 10, Color(0.40, 1.0, 0.40))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(ITEMS_SW - 12.0, 4.0)
	_items_sub.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(ITEMS_SW - 12.0, ITEMS_SH - 38.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_sub.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	for d: Dictionary in ALL_ITEMS:
		vbox.add_child(_make_item_row(d))

# ── Row builder ───────────────────────────────────────────────────────────────

func _make_item_row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, 38.0)

	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_path: String = ""
	match d["src"]:
		"weapons": icon_path = WEAPONS_PATH + d["icon"]
		"items":   icon_path = ITEMS_PATH   + d["icon"]
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = d["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = d["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	info.add_child(desc_lbl)

	var give_btn := _make_btn("Give", Color(0.40, 0.80, 0.40))
	give_btn.custom_minimum_size = Vector2(54.0, 0.0)
	give_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	give_btn.pressed.connect(_on_give_item.bind(d))
	row.add_child(give_btn)

	return row

# ── Helpers ───────────────────────────────────────────────────────────────────

func _style_panel(p: Panel, bg: Color, border: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", s)

func _add_label(parent: Control, text: String, x: float, y: float,
				font_size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

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
	btn.add_theme_stylebox_override("hover",  h)
	btn.add_theme_color_override("font_color", Color.WHITE)
	return btn

# ── Input ─────────────────────────────────────────────────────────────────────

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

# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_invincible_toggled(pressed: bool) -> void:
	GameState.invincible = pressed
	GameState.game_log("[color=%s][DEBUG] Invincible %s[/color]" % [
		"red" if pressed else "gray", "ON" if pressed else "OFF"])

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
	item.item_name   = d["name"]
	item.item_type   = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount = d["heal"]
	item.str_bonus   = d.get("str_bonus", 0)
	item.description = d["desc"]
	match d["src"]:
		"weapons": item.icon_path = WEAPONS_PATH + d["icon"]
		"items":   item.icon_path = ITEMS_PATH   + d["icon"]
	item.quantity = 3 if d["name"] == "Thief Tools" else 1
	if not GameState.add_item(item):
		GameState.game_log("[color=red][DEBUG] Inventory full — cannot give %s[/color]" % d["name"])
	else:
		GameState.game_log("[color=lime][DEBUG] Given: %s[/color]" % d["name"])
