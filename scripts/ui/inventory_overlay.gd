extends CanvasLayer

const SLOT_SIZE: int = 90
const SLOT_GAP: int  = 6
const STEP:      int = SLOT_SIZE + SLOT_GAP   # 96
const PANEL_W:   int = 1068
const PANEL_H:   int = 690

var _panel: Panel
var _bag_slots: Array[Control]    = []
var _qb_slots:  Array[Control]    = []
var _eq_slots:  Dictionary        = {}   # slot_name → Control
var _inv_tooltip: Panel           = null
var _inv_tooltip_rtl: RichTextLabel = null
var _inv_glossary_popup: Panel = null
var _inv_glossary_rtl: RichTextLabel = null
const KEYWORD_GLOSSARY: Dictionary = {
	"heavy": "Heavy weapon.\nMelee: requires STR 13+.\nRanged: requires DEX 13+.\nAttacking without enough\nStrength/Dexterity imposes\nDisadvantage.",
	"two_handed": "Two-handed weapon.\nOccupies Main Hand.\nOff-hand cannot be used\nwhile equipped.",
	"cleave": "Mastery: Cleave.\nIf 2+ enemies are within\nmelee reach, this attack\nalso strikes the one closest\nto your primary target —\nwith its own attack roll\nand damage roll.",
	"simple": "Simple weapon.\nEasy to use — most\ncharacters are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"martial": "Martial weapon.\nRequires training — only\nsome classes are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"vex": "Mastery: Vex.\nOn a hit, gain Advantage\non your next attack this\nround against the same\ntarget (any attack type).",
	"push": "Mastery: Push.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ DEX) or is shoved 1 tile\ndirectly away from you.\nHitting a wall deals 1d4\nBludgeoning instead of\nmoving; falling into a\nchasm removes it (loot,\nif any, appears a floor\ndown).",
	"finesse": "Finesse weapon.\nUse either STR or DEX\n(whichever is higher) for\nboth the attack roll and\nthe damage roll.",
	"light": "Light weapon.\nPair another Light weapon\nin the Off-hand to attack\nwith both. The Off-hand\nswing skips your ability\nmodifier on damage, unless\nit's negative.",
	"graze": "Mastery: Graze.\nOn a miss, still deal\ndamage equal to the\nability modifier used\nfor the attack (min 0).",
	"reach": "Reach weapon.\n+1 tile melee range —\ncan attack (and chase-\nattack) from 2 tiles away\ninstead of 1.",
	"topple": "Mastery: Topple.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ STR) or is knocked Prone,\nskipping its entire next turn.",
	"versatile": "Versatile weapon.\nClick the Main Hand slot\nto switch grip: one-handed\nuses the die shown, two-\nhanded uses the die listed\nhere instead.",
	"thrown": "Thrown weapon.\nRight-click to prime a\nthrow, then left-click a\ntarget tile — uses your\nmelee attack modifier.\nNormal range shown; beyond\nit (still within FOV) rolls\nwith Disadvantage. Has\nlimited uses before it\nbreaks.",
	"sap": "Mastery: Sap.\nOn a hit, the target has\nDisadvantage on its very\nnext attack, next turn.",
	"nick": "Mastery: Nick.\nWhile dual-wielding two\nLight weapons, make one\nfurther attack this turn —\nsame rules as the Off-hand\nswing (max 3 attacks total).",
	"slow": "Mastery: Slow.\nOn a hit, the target is\nSlowed — its next turn is\nskipped entirely, same as\nstepping into mud/water."
}

# Tooltip freeze state (Ctrl to freeze, enabling keyword link hover)
var _tooltip_frozen: bool = false

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
		AudioManager.play("open_inventory")
		_refresh()

func _safe_refresh() -> void:
	if visible:
		_refresh()

func _unfreeze_tooltip() -> void:
	_tooltip_frozen = false
	if _inv_tooltip != null:
		_inv_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_inv_tooltip.visible = false
	if _inv_tooltip_rtl != null: _inv_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _inv_glossary_popup != null: _inv_glossary_popup.visible = false

func _input(event: InputEvent) -> void:
	if not visible:
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo:
		if key.physical_keycode == KEY_CTRL:
			if _tooltip_frozen:
				_unfreeze_tooltip()
			elif _inv_tooltip != null and _inv_tooltip.visible:
				_tooltip_frozen = true
				_inv_tooltip.mouse_filter     = Control.MOUSE_FILTER_STOP
				_inv_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
			get_viewport().set_input_as_handled()
			return
		if key.physical_keycode == KEY_I or key.physical_keycode == KEY_ESCAPE:
			_unfreeze_tooltip()
			get_viewport().set_input_as_handled()
			visible = false
			GameState.inventory_open = false

func _process(_delta: float) -> void:
	if visible and _dragging:
		if _drag_icon != null:
			_drag_icon.position = get_viewport().get_mouse_position() - Vector2(SLOT_SIZE / 2.0, SLOT_SIZE / 2.0)
		if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
			_finish_drag()
	if _inv_tooltip != null and _inv_tooltip.visible:
		var tw: float = _inv_tooltip.size.x
		var th: float = _inv_tooltip_rtl.get_content_height() + 14.0
		_inv_tooltip_rtl.size = Vector2(tw - 16.0, th - 14.0)
		_inv_tooltip.size = Vector2(tw, th)
		var tx: float
		var ty: float
		if not _tooltip_frozen:
			var mp: Vector2 = get_viewport().get_mouse_position()
			var vp: Vector2 = get_viewport().get_visible_rect().size
			tx = clampf(mp.x - tw * 0.5, 4.0, vp.x - tw - 4.0)
			ty = mp.y - th - 14.0
			if ty < 4.0:
				ty = mp.y + 18.0
			_inv_tooltip.position = Vector2(tx, ty)
		else:
			tx = _inv_tooltip.position.x
			ty = _inv_tooltip.position.y
		if _inv_glossary_popup != null and _inv_glossary_popup.visible:
			var vp: Vector2 = get_viewport().get_visible_rect().size
			var gw: float = _inv_glossary_popup.size.x
			var gh: float = _inv_glossary_rtl.get_content_height() + 14.0
			_inv_glossary_rtl.size = Vector2(gw - 16.0, gh - 14.0)
			_inv_glossary_popup.size = Vector2(gw, gh)
			var gx: float = clampf(tx + tw + 4.0, 4.0, vp.x - gw - 4.0)
			_inv_glossary_popup.position = Vector2(gx, ty)

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
			_unfreeze_tooltip()
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

	_add_label(_panel, "INVENTORY", Vector2(21, 15), 27, Color(0.9, 0.85, 0.6))

	var sep0 := HSeparator.new()
	sep0.position = Vector2(15, 51); sep0.size = Vector2(PANEL_W - 30, 3)
	_panel.add_child(sep0)

	_build_equipment_section()
	_build_bag_section()
	_build_quickbar_section()

	_inv_tooltip = Panel.new()
	_inv_tooltip.visible = false
	_inv_tooltip.z_index = 20
	_inv_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var tsb := StyleBoxFlat.new()
	tsb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	tsb.set_border_width_all(1); tsb.border_color = Color(0.55, 0.50, 0.35)
	tsb.set_corner_radius_all(3)
	_inv_tooltip.add_theme_stylebox_override("panel", tsb)
	_inv_tooltip_rtl = RichTextLabel.new()
	_inv_tooltip_rtl.bbcode_enabled = true
	_inv_tooltip_rtl.fit_content = true
	_inv_tooltip_rtl.offset_left = 8.0; _inv_tooltip_rtl.offset_top = 6.0
	_inv_tooltip_rtl.offset_right = -8.0; _inv_tooltip_rtl.offset_bottom = -6.0
	_inv_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_tooltip_rtl.meta_hover_started.connect(_on_inv_meta_hover_started)
	_inv_tooltip_rtl.meta_hover_ended.connect(_on_inv_meta_hover_ended)
	_inv_tooltip.add_child(_inv_tooltip_rtl)
	add_child(_inv_tooltip)
	# Keyword glossary popup
	_inv_glossary_popup = Panel.new()
	_inv_glossary_popup.visible = false
	_inv_glossary_popup.z_index = 22
	_inv_glossary_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var igsb := StyleBoxFlat.new()
	igsb.bg_color = Color(0.08, 0.07, 0.04, 0.97)
	igsb.set_border_width_all(1)
	igsb.border_color = Color(0.75, 0.65, 0.20)
	igsb.set_corner_radius_all(3)
	_inv_glossary_popup.add_theme_stylebox_override("panel", igsb)
	_inv_glossary_rtl = RichTextLabel.new()
	_inv_glossary_rtl.bbcode_enabled = true
	_inv_glossary_rtl.fit_content = true
	_inv_glossary_rtl.offset_left = 8.0; _inv_glossary_rtl.offset_top = 6.0
	_inv_glossary_rtl.offset_right = -8.0; _inv_glossary_rtl.offset_bottom = -6.0
	_inv_glossary_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_inv_glossary_popup.add_child(_inv_glossary_rtl)
	add_child(_inv_glossary_popup)

	_add_label(_panel, "I / Esc  •  Right-click: use/equip  •  Drag to move",
		Vector2(15, PANEL_H - 36), 16, Color(0.4, 0.4, 0.4))

const EQUIPMENT_ORIGIN: Vector2 = Vector2(14, 102)
const BAG_ORIGIN_X: float = 480.0

func _build_equipment_section() -> void:
	_add_label(_panel, "Equipment", Vector2(21, 63), 21, Color(0.7, 0.7, 0.8))
	# Gloves-Armor-Hand1-Hand2 middle row; Headgear above Armor; Boots below Armor;
	# Ranged centered above the gap between Hand 1 and Hand 2.
	var layout: Array = [
		["head",   1.0, 0],                                   ["ranged", 2.5, 0], ["special", 3.5, 0],
		["gloves", 0.0, 1], ["armor", 1.0, 1], ["melee", 2.0, 1], ["hand2", 3.0, 1],
		["boots",  1.0, 2],
	]
	for entry in layout:
		var sn: String = entry[0]; var c: float = entry[1]; var r: int = entry[2]
		var slot := _make_slot(sn)
		slot.position = EQUIPMENT_ORIGIN + Vector2(c * STEP, r * STEP)
		# "special" is a display-only quick-cast slot (holds a Spell reference, not an Item) —
		# assigned from inside the Spellbook overlay (see scripts/ui/CLAUDE.md), never a normal
		# drag-and-drop destination here. Kept out of the "equipment" source so _do_move()/
		# _fits_slot() never treat it as an Item-shaped slot.
		slot.set_meta("source", "special_display" if sn == "special" else "equipment")
		slot.set_meta("slot_name", sn)
		_panel.add_child(slot)
		_eq_slots[sn] = slot

func _build_bag_section() -> void:
	_add_label(_panel, "Bag  (24)", Vector2(BAG_ORIGIN_X, 63), 21, Color(0.7, 0.7, 0.8))
	var origin := Vector2(BAG_ORIGIN_X, 102)
	for i: int in 24:
		var slot := _make_slot()
		slot.position = origin + Vector2((i % 6) * STEP, (i / 6) * STEP)
		slot.set_meta("source", "inventory")
		slot.set_meta("index", i)
		_panel.add_child(slot)
		_bag_slots.append(slot)

func _build_quickbar_section() -> void:
	var sep := HSeparator.new()
	sep.position = Vector2(15, PANEL_H - 162); sep.size = Vector2(PANEL_W - 30, 3)
	_panel.add_child(sep)
	_add_label(_panel, "Quickbar", Vector2(21, PANEL_H - 150), 21, Color(0.7, 0.7, 0.8))
	# 9 slots centered horizontally
	var total_w: int = 9 * STEP - SLOT_GAP
	var origin_x: float = (PANEL_W - total_w) / 2.0
	var origin_y: float = PANEL_H - 123.0
	for i: int in 9:
		var slot := _make_slot()
		slot.position = Vector2(origin_x + i * STEP, origin_y)
		slot.set_meta("source", "quickbar")
		slot.set_meta("index", i)
		_panel.add_child(slot)
		_qb_slots.append(slot)

func _make_slot(eq_type: String = "") -> Control:
	var slot := Panel.new()
	slot.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	slot.size = Vector2(SLOT_SIZE, SLOT_SIZE)
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
		tl.add_theme_font_size_override("font_size", 10)
		tl.add_theme_color_override("font_color", Color(0.48, 0.48, 0.56))
		tl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		tl.position = Vector2(0, SLOT_SIZE - 21); tl.size = Vector2(SLOT_SIZE, 21)
		tl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(tl)

	var icon := TextureRect.new()
	icon.name = "Icon"
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.ignore_texture_size = true  # REQUIRED — spell icon PNGs are huge, see scripts/ui/CLAUDE.md
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2(6, 6)
	icon.size = Vector2(SLOT_SIZE - 12, SLOT_SIZE - (27 if eq_type != "" else 12))
	slot.add_child(icon)

	if eq_type == "special":
		# Text fallback for when the assigned spell has no icon asset (or one that failed to
		# resolve) — mirrors hud.gd's ability bar (ability_name.left(4)) convention.
		var name_lbl := Label.new()
		name_lbl.name = "NameLabel"
		name_lbl.add_theme_font_size_override("font_size", 12)
		name_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 1.0))
		name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		name_lbl.position = Vector2(0, 0); name_lbl.size = Vector2(SLOT_SIZE, SLOT_SIZE - 21)
		name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(name_lbl)

	var cnt := Label.new()
	cnt.name = "Count"
	cnt.add_theme_font_size_override("font_size", 15)
	cnt.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	cnt.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	cnt.position = Vector2(2, 3); cnt.size = Vector2(SLOT_SIZE - 3, 21)
	cnt.mouse_filter = Control.MOUSE_FILTER_IGNORE
	slot.add_child(cnt)

	if eq_type == "hand2":
		var blocked := Label.new()
		blocked.name = "BlockedMark"
		blocked.text = "✕"
		blocked.add_theme_font_size_override("font_size", 32)
		blocked.add_theme_color_override("font_color", Color(0.75, 0.15, 0.15))
		blocked.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		blocked.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		blocked.position = Vector2(0, 0); blocked.size = Vector2(SLOT_SIZE, SLOT_SIZE - 21)
		blocked.mouse_filter = Control.MOUSE_FILTER_IGNORE
		blocked.visible = false
		slot.add_child(blocked)

	slot.gui_input.connect(func(ev: InputEvent): _on_slot_input(ev, slot))
	slot.mouse_entered.connect(func(): _on_slot_hover(slot))
	slot.mouse_exited.connect(func(): _on_slot_hover_end())
	return slot

func _eq_display(name: String) -> String:
	match name:
		"melee":  return "Main Hand"
		"hand2":  return "Off-hand"
		"ranged": return "Ranged"
		"special":    return "Special"
		"armor":      return "Armor"
		"gloves":     return "Gloves"
		"boots":      return "Boots"
		"head":       return "Headgear"
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
	_drag_icon.custom_minimum_size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_drag_icon.size = Vector2(SLOT_SIZE, SLOT_SIZE)
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		_drag_icon.texture = load(item.icon_path)
	_drag_icon.position = get_viewport().get_mouse_position() - Vector2(SLOT_SIZE / 2.0, SLOT_SIZE / 2.0)
	add_child(_drag_icon)

func _finish_drag() -> void:
	_dragging = false
	var local_mouse: Vector2 = _panel.get_local_mouse_position()
	var dest: Control = null
	for slot: Control in _all_slots():
		if slot == _drag_src_ctrl:
			continue
		if Rect2(slot.position, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(local_mouse):
			dest = slot
			break
	if dest != null:
		_do_move(dest)
	elif (_drag_src_sname == "melee" or _drag_src_sname == "hand2") and _drag_src_ctrl != null \
			and Rect2(_drag_src_ctrl.position, Vector2(SLOT_SIZE, SLOT_SIZE)).has_point(local_mouse):
		var slot_item: Item = GameState.equipment.get(_drag_src_sname) as Item
		if slot_item != null:
			if _drag_src_sname == "melee" and slot_item.is_versatile:
				GameState.toggle_versatile_grip()
			elif slot_item.is_torch and not slot_item.torch_lit and not slot_item.torch_burnt:
				GameState.light_torch(slot_item)
				var df: Node = get_tree().get_first_node_in_group("dungeon_floor")
				if df != null:
					df.update_fog(GameState.player_grid_pos)
	if _drag_icon != null:
		_drag_icon.queue_free()
		_drag_icon = null
	_drag_item     = null
	_drag_src_ctrl = null

func _do_move(dest: Control) -> void:
	var dest_src:   String = dest.get_meta("source", "")
	var dest_idx:   int    = dest.get_meta("index", -1)
	var dest_sname: String = dest.get_meta("slot_name", "")
	# The Special slot holds a Spell reference, not an Item — never a normal drag-and-drop
	# destination here (assigned only from inside the Spellbook overlay).
	if dest_src == "special_display":
		return
	# Equipment slot compatibility check
	if dest_src == "equipment" and not _fits_slot(_drag_item, dest_sname):
		if dest_sname == "hand2" and _drag_item != null and _drag_item.is_shield:
			GameState.log_shield_equip_blocked(_drag_item)
		return
	GameState.move_item(_drag_src, _drag_src_idx, _drag_src_sname,
						dest_src,  dest_idx,       dest_sname)

func _fits_slot(item: Item, slot_name: String) -> bool:
	match slot_name:
		"melee":  return item.item_type == Item.Type.WEAPON and not item.is_ranged
		"ranged": return item.item_type == Item.Type.WEAPON and item.is_ranged
		"armor":                   return item.item_type == Item.Type.ARMOR
		# Off-hand: a Light melee weapon may only be dual-wielded here if Main Hand also holds
		# a Light weapon (5e Two-Weapon Fighting rule); non-weapon items are always accepted.
		# A Torch is a special case (like a Shield) — always allowed here regardless of Main
		# Hand, and never fires a bonus Off-hand attack since it isn't Light (see
		# player.gd._try_offhand_attack()'s off_hand.is_light gate).
		"hand2":
			if item.item_type != Item.Type.WEAPON:
				if item.is_shield:
					return GameState.can_equip_shield(item)
				return true
			if item.is_torch:
				return true
			var main_hand: Item = GameState.equipped_weapon
			return not item.is_ranged and item.is_light and main_hand != null and main_hand.is_light
		_:                         return false

func _right_click(slot: Control) -> void:
	var source: String = slot.get_meta("source", "")
	if source == "special_display":
		GameState.clear_special_slot()
	elif source == "equipment":
		GameState.unequip(slot.get_meta("slot_name", ""))  # free action, except a Shield (1 turn)
	else:
		var item: Item = _slot_item(slot)
		if item != null:
			GameState.use_item(item)

func _is_weapon_category_proficient(category: String) -> bool:
	var s: Stats = GameState.player_stats
	match category:
		"Simple":  return s.proficient_simple_weapons
		"Martial": return s.proficient_martial_weapons
		_: return true

func _on_slot_hover(slot: Control) -> void:
	if _tooltip_frozen:
		return
	if _inv_tooltip == null:
		return
	if slot.get_meta("source", "") == "special_display":
		_show_special_slot_tooltip()
		return
	var item: Item = _slot_item(slot)
	if item == null:
		_inv_tooltip.visible = false
		return
	var text: String = "[b]%s[/b]" % item.item_name
	if item.item_type == Item.Type.WEAPON:
		if not item.weapon_mastery.is_empty():
			text += " [url=keyword:%s](%s)[/url]" % [item.weapon_mastery.to_lower(), item.weapon_mastery]
		var die_max: int = item.damage_die_max if item.damage_die_max > 0 else 0
		var die_str: String = "1d%d" % die_max if die_max > 0 else ""
		var bonus_str: String = "+%d" % item.bonus_damage if item.bonus_damage > 0 else ""
		var sep: String = " " if not die_str.is_empty() and not bonus_str.is_empty() else ""
		var type_str: String = " [color=gray]%s[/color]" % item.damage_type if not item.damage_type.is_empty() else ""
		if not die_str.is_empty() or not bonus_str.is_empty():
			text += "\n%s%s%s%s" % [die_str, sep, bonus_str, type_str]
		if not item.weapon_category.is_empty():
			var cat_color: String = "white" if _is_weapon_category_proficient(item.weapon_category) else "red"
			text += "\n[color=%s][url=keyword:%s]%s[/url][/color]" % [cat_color, item.weapon_category.to_lower(), item.weapon_category]
		if item.is_ranged:
			text += "\nrange: %d tiles [color=gray](long: FOV, DISADV)[/color]" % item.range
			if not item.ammo_item_name.is_empty():
				text += "\n[color=gray]Requires: %s[/color]" % item.ammo_item_name
		else:
			text += "\nrange: %d tile%s" % [2 if item.is_reach else 1, "s" if item.is_reach else ""]
		var props: Array[String] = []
		if item.is_two_handed:
			props.append("[url=keyword:two_handed]Two-handed[/url]")
		if item.is_heavy:
			props.append("[url=keyword:heavy]Heavy[/url]")
		if item.is_finesse:
			props.append("[url=keyword:finesse]Finesse[/url]")
		if item.is_light:
			props.append("[url=keyword:light]Light[/url]")
		if item.is_reach:
			props.append("[url=keyword:reach]Reach[/url]")
		if item.is_versatile:
			var grip_str: String = "two" if item.is_two_handed else "one"
			props.append("[url=keyword:versatile]Versatile (1d%d %s-handed)[/url]" % [item.versatile_die_max, grip_str])
		if item.is_thrown:
			props.append("[url=keyword:thrown]Thrown (%d/FOV)[/url]" % item.range)
		if not props.is_empty():
			text += "\n%s" % ", ".join(props)
	elif item.item_type == Item.Type.POTION or item.item_type == Item.Type.FOOD:
		if item.heal_dice_count > 0:
			text += "\n%dd%d+CON HP" % [item.heal_dice_count, item.heal_dice_sides]
		elif item.heal_amount > 0:
			text += "\n+%d HP" % item.heal_amount
	if not item.description.is_empty():
		text += "\n[color=gray]%s[/color]" % item.description
	if item.item_type == Item.Type.WEAPON and item.is_thrown:
		text += "\n[color=#999][font_size=11][right]Uses: %d/%d[/right][/font_size][/color]" % [item.uses_remaining, item.uses_max]
	text += "\n[color=#555][font_size=9][right]Ctrl: inspect[/right][/font_size][/color]"
	_inv_tooltip_rtl.text = text
	_inv_tooltip_rtl.size = Vector2(172.0, 0)
	_inv_tooltip.size = Vector2(180.0, 60)
	_inv_tooltip.visible = true

func _show_special_slot_tooltip() -> void:
	var sid: String = GameState.special_slot_spell_id
	if sid == "":
		_inv_tooltip.visible = false
		return
	var spell: Spell = SpellDb.get_spell(sid)
	if spell == null:
		_inv_tooltip.visible = false
		return
	var text: String = "[b]%s[/b]\n[color=gray]%s[/color]\n[color=#888]Ctrl+click a target to cast. Right-click to clear.[/color]" % [spell.spell_name, spell.description]
	_inv_tooltip_rtl.text = text
	_inv_tooltip_rtl.size = Vector2(172.0, 0)
	_inv_tooltip.size = Vector2(180.0, 60)
	_inv_tooltip.visible = true

func _on_slot_hover_end() -> void:
	if _tooltip_frozen:
		return
	if _inv_tooltip != null:
		_inv_tooltip.visible = false
	if _inv_glossary_popup != null:
		_inv_glossary_popup.visible = false

func _on_inv_meta_hover_started(meta: Variant) -> void:
	var m: String = str(meta)
	if m.begins_with("keyword:") and _inv_glossary_popup != null:
		var kw: String = m.substr(8)
		if KEYWORD_GLOSSARY.has(kw):
			_inv_glossary_rtl.text = KEYWORD_GLOSSARY[kw]
			_inv_glossary_rtl.size = Vector2(160.0, 0)
			_inv_glossary_popup.size = Vector2(168.0, 60)
			_inv_glossary_popup.visible = true

func _on_inv_meta_hover_ended(_meta: Variant) -> void:
	if _inv_glossary_popup != null:
		_inv_glossary_popup.visible = false

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
		if sn == "special":
			_update_special_slot(_eq_slots[sn] as Control)
		else:
			_update_slot(_eq_slots[sn] as Control, GameState.equipment.get(sn) as Item)
	var main_hand: Item = GameState.equipment.get("melee") as Item
	var off_hand_blocked: bool = main_hand != null and main_hand.is_two_handed
	var hand2_slot: Control = _eq_slots.get("hand2") as Control
	if hand2_slot != null:
		var mark: Label = hand2_slot.get_node_or_null("BlockedMark") as Label
		if mark != null:
			mark.visible = off_hand_blocked
	var melee_slot: Control = _eq_slots.get("melee") as Control
	if melee_slot != null:
		var sbox: StyleBoxFlat = melee_slot.get_theme_stylebox("panel") as StyleBoxFlat
		if sbox != null:
			var two_handed_grip: bool = main_hand != null and main_hand.is_versatile and main_hand.is_two_handed
			sbox.border_color = Color(0.95, 0.75, 0.25) if two_handed_grip else Color(0.35, 0.34, 0.38)
			sbox.set_border_width_all(3 if two_handed_grip else 1)

func _update_special_slot(slot: Control) -> void:
	var icon:      TextureRect = slot.get_node_or_null("Icon") as TextureRect
	var count:     Label       = slot.get_node_or_null("Count") as Label
	var name_lbl:  Label       = slot.get_node_or_null("NameLabel") as Label
	if count != null:
		count.text = ""
	var sid: String = GameState.special_slot_spell_id
	var spell: Spell = SpellDb.get_spell(sid) if sid != "" else null
	var has_icon: bool = spell != null and spell.icon_path != "" and ResourceLoader.exists(spell.icon_path)
	if icon != null:
		icon.texture = load(spell.icon_path) if has_icon else null
	if name_lbl != null:
		name_lbl.text = "" if has_icon or spell == null else spell.spell_name.left(4)

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
