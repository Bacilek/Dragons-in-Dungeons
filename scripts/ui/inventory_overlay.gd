extends CanvasLayer

const SLOT_SIZE: int = 48
const SLOT_GAP: int  = 3
const STEP:      int = SLOT_SIZE + SLOT_GAP   # 51
const PANEL_W:   int = 700
const PANEL_H:   int = 360

var _panel: Panel
var _bag_slots: Array[Control]    = []
var _qb_slots:  Array[Control]    = []
var _eq_slots:  Dictionary        = {}   # slot_name → Control

# Drag state (manual drag — no Godot built-in drag API)
var _dragging:       bool    = false
var _drag_item:      Item    = null
var _drag_src:       String  = ""
var _drag_src_idx:   int     = -1
var _drag_src_sname: String  = ""
var _drag_src_ctrl:  Control = null
var _drag_icon:      TextureRect = null

func _ready() -> void:
	layer = 15
	visible = false
	_build_ui()
	GameState.inventory_toggle.connect(_on_toggle)
	GameState.inventory_changed.connect(_safe_refresh)
	GameState.equipment_changed.connect(_safe_refresh)

func _on_toggle() -> void:
	visible = not visible
	GameState.inventory_open = visible
	if visible:
		_refresh()

func _safe_refresh() -> void:
	if visible:
		_refresh()

func _unhandled_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo:
			if key.physical_keycode == KEY_I or key.physical_keycode == KEY_ESCAPE:
				visible = false
				GameState.inventory_open = false
				get_viewport().set_input_as_handled()

func _process(_delta: float) -> void:
	if not visible or not _dragging:
		return
	if _drag_icon != null:
		_drag_icon.position = get_viewport().get_mouse_position() - Vector2(16.0, 16.0)
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		_finish_drag()

# ── UI construction ───────────────────────────────────────────────────────────

func _build_ui() -> void:
	# Full-screen dim — clicks outside panel close the overlay
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.72)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	dim.gui_input.connect(func(ev: InputEvent):
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			visible = false
			GameState.inventory_open = false
	)
	add_child(dim)

	# Centered panel
	_panel = Panel.new()
	_panel.anchor_left   = 0.5; _panel.anchor_right  = 0.5
	_panel.anchor_top    = 0.5; _panel.anchor_bottom = 0.5
	_panel.offset_left   = -PANEL_W / 2.0; _panel.offset_right  = PANEL_W / 2.0
	_panel.offset_top    = -PANEL_H / 2.0; _panel.offset_bottom = PANEL_H / 2.0
	_panel.mouse_filter  = Control.MOUSE_FILTER_STOP
	var ps := StyleBoxFlat.new()
	ps.bg_color = Color(0.08, 0.08, 0.10, 0.97)
	ps.set_border_width_all(2); ps.border_color = Color(0.5, 0.44, 0.32)
	ps.set_corner_radius_all(4)
	_panel.add_theme_stylebox_override("panel", ps)
	add_child(_panel)

	_add_label(_panel, "INVENTORY", Vector2(12, 10), 15, Color(0.9, 0.85, 0.6))

	var sep0 := HSeparator.new()
	sep0.position = Vector2(10, 34); sep0.size = Vector2(PANEL_W - 20, 2)
	_panel.add_child(sep0)

	_build_equipment_section()
	_build_bag_section()
	_build_quickbar_section()

	_add_label(_panel, "I / Esc  •  Right-click: use/equip  •  Drag to move",
		Vector2(10, PANEL_H - 16), 9, Color(0.4, 0.4, 0.4))

func _build_equipment_section() -> void:
	_add_label(_panel, "Equipment", Vector2(12, 42), 11, Color(0.7, 0.7, 0.8))
	# 3-column × 4-row silhouette; empty strings = visual gap
	var layout: Array = [
		["head",       1, 0],
		["left_hand",  0, 1], ["armor",   1, 1], ["right_hand", 2, 1],
		["gloves",     0, 2],                    ["boots",      2, 2],
		["trinket",    1, 3],
	]
	var origin := Vector2(12, 58)
	for entry in layout:
		var sn: String = entry[0]; var c: int = entry[1]; var r: int = entry[2]
		var slot := _make_slot(sn)
		slot.position = origin + Vector2(c * STEP, r * STEP)
		slot.set_meta("source", "equipment")
		slot.set_meta("slot_name", sn)
		_panel.add_child(slot)
		_eq_slots[sn] = slot

func _build_bag_section() -> void:
	_add_label(_panel, "Bag  (24)", Vector2(282, 42), 11, Color(0.7, 0.7, 0.8))
	var origin := Vector2(282, 58)
	for i: int in 24:
		var slot := _make_slot()
		slot.position = origin + Vector2((i % 6) * STEP, (i / 6) * STEP)
		slot.set_meta("source", "inventory")
		slot.set_meta("index", i)
		_panel.add_child(slot)
		_bag_slots.append(slot)

func _build_quickbar_section() -> void:
	var sep := HSeparator.new()
	sep.position = Vector2(10, PANEL_H - 88); sep.size = Vector2(PANEL_W - 20, 2)
	_panel.add_child(sep)
	_add_label(_panel, "Quickbar", Vector2(12, PANEL_H - 80), 11, Color(0.7, 0.7, 0.8))
	# 5 slots centered horizontally
	var total_w: int = 5 * STEP - SLOT_GAP
	var origin_x: float = (PANEL_W - total_w) / 2.0
	var origin_y: float = PANEL_H - 65.0
	for i: int in 5:
		var slot := _make_slot()
		slot.position = Vector2(origin_x + i * STEP, origin_y)
		slot.set_meta("source", "quickbar")
		slot.set_meta("index", i)
		_panel.add_child(slot)
		_qb_slots.append(slot)

func _make_slot(eq_type: String = "") -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.mouse_filter = Control.MOUSE_FILTER_STOP
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.11, 0.11, 0.15, 0.95)
	sbox.set_border_width_all(1); sbox.border_color = Color(0.35, 0.34, 0.38)
	sbox.set_corner_radius_all(2)
	slot.add_theme_stylebox_override("panel", sbox)

	if eq_type != "":
		var tl := Label.new()
		tl.name = "TypeLabel"
		tl.text = _eq_display(eq_type)
		tl.add_theme_font_size_override("font_size", 7)
		tl.add_theme_color_override("font_color", Color(0.48, 0.48, 0.56))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, SLOT_SIZE - 12); tl.size = Vector2(SLOT_SIZE, 12)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tl)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(4, 3)
	icon.size = Vector2(SLOT_SIZE - 8, SLOT_SIZE - (15 if eq_type != "" else 6))
	slot.add_child(icon)

	var cnt := Label.new()
	cnt.name = "Count"
	cnt.add_theme_font_size_override("font_size", 8)
	cnt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(1, 2); cnt.size = Vector2(SLOT_SIZE - 2, 11)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cnt)

	slot.gui_input.connect(func(ev: InputEvent): _on_slot_input(ev, slot))
	return slot

func _eq_display(name: String) -> String:
	match name:
		"right_hand": return "R.Hand"
		"left_hand":  return "L.Hand"
		"armor":      return "Armor"
		"gloves":     return "Gloves"
		"boots":      return "Boots"
		"head":       return "Head"
		"trinket":    return "Trinket"
		_:            return name

func _add_label(parent: Control, text: String, pos: Vector2, size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", size)
	lbl.add_theme_color_override("font_color", color)
	lbl.position = pos
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

# ── Input handling ────────────────────────────────────────────────────────────

func _on_slot_input(event: InputEvent, slot: Control) -> void:
	if not event is InputEventMouseButton:
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		_start_drag(slot)
	elif mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		_right_click(slot)

func _start_drag(slot: Control) -> void:
	var item: Item = _slot_item(slot)
	if item == null:
		return
	_dragging      = true
	_drag_item     = item
	_drag_src_ctrl = slot
	_drag_src      = slot.get_meta("source", "")
	_drag_src_idx  = slot.get_meta("index", -1)
	_drag_src_sname = slot.get_meta("slot_name", "")
	# Floating icon (direct child of CanvasLayer → screen-space position)
	_drag_icon = TextureRect.new()
	_drag_icon.custom_minimum_size = Vector2(32, 32)
	_drag_icon.size = Vector2(32, 32)
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		_drag_icon.texture = load(item.icon_path)
	_drag_icon.position = get_viewport().get_mouse_position() - Vector2(16, 16)
	add_child(_drag_icon)

func _finish_drag() -> void:
	_dragging = false
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	var dest: Control = null
	for slot: Control in _all_slots():
		if slot == _drag_src_ctrl:
			continue
		if slot.get_global_rect().has_point(mouse_pos):
			dest = slot
			break
	if dest != null:
		_do_move(dest)
	if _drag_icon != null:
		_drag_icon.queue_free()
		_drag_icon = null
	_drag_item     = null
	_drag_src_ctrl = null

func _do_move(dest: Control) -> void:
	var dest_src:   String = dest.get_meta("source", "")
	var dest_idx:   int    = dest.get_meta("index", -1)
	var dest_sname: String = dest.get_meta("slot_name", "")
	# Equipment slot compatibility check
	if dest_src == "equipment" and not _fits_slot(_drag_item, dest_sname):
		return
	GameState.move_item(_drag_src, _drag_src_idx, _drag_src_sname,
						dest_src,  dest_idx,       dest_sname)

func _fits_slot(item: Item, slot_name: String) -> bool:
	match slot_name:
		"right_hand", "left_hand": return item.item_type == Item.Type.WEAPON
		"armor":                   return item.item_type == Item.Type.ARMOR
		_:                         return false

func _right_click(slot: Control) -> void:
	var source: String = slot.get_meta("source", "")
	if source == "equipment":
		GameState.unequip(slot.get_meta("slot_name", ""))
	else:
		var item: Item = _slot_item(slot)
		if item != null:
			GameState.use_item(item)

func _slot_item(slot: Control) -> Item:
	match slot.get_meta("source", ""):
		"equipment":
			return GameState.equipment.get(slot.get_meta("slot_name", "")) as Item
		"quickbar":
			var i: int = slot.get_meta("index", -1)
			if i >= 0 and i < GameState.player_quickbar.size():
				return GameState.player_quickbar[i] as Item
		"inventory":
			var i: int = slot.get_meta("index", -1)
			if i >= 0 and i < GameState.player_inventory.size():
				return GameState.player_inventory[i] as Item
	return null

func _all_slots() -> Array[Control]:
	var out: Array[Control] = []
	out.append_array(_bag_slots)
	out.append_array(_qb_slots)
	for k: String in _eq_slots:
		out.append(_eq_slots[k] as Control)
	return out

# ── Refresh display ───────────────────────────────────────────────────────────

func _refresh() -> void:
	for i: int in _bag_slots.size():
		var raw = GameState.player_inventory[i] if i < GameState.player_inventory.size() else null
		_update_slot(_bag_slots[i], raw as Item)
	for i: int in _qb_slots.size():
		var raw = GameState.player_quickbar[i] if i < GameState.player_quickbar.size() else null
		_update_slot(_qb_slots[i], raw as Item)
	for sn: String in _eq_slots:
		_update_slot(_eq_slots[sn] as Control, GameState.equipment.get(sn) as Item)

func _update_slot(slot: Control, item: Item) -> void:
	var icon:  TextureRect = slot.get_node_or_null("Icon") as TextureRect
	var count: Label       = slot.get_node_or_null("Count") as Label
	if item == null:
		if icon  != null: icon.texture = null
		if count != null: count.text = ""
		return
	if icon != null:
		icon.texture = load(item.icon_path) if item.icon_path != "" and ResourceLoader.exists(item.icon_path) else null
	if count != null:
		count.text = str(item.quantity) if item.quantity > 1 else ""
