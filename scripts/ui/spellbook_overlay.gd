extends CanvasLayer

# Wizard Spellbook overlay (R key) — docs/architecture/leveled-spells-and-slots-plan.md §5.
# Modeled on mastery_picker.gd's structure (dim overlay + centered bordered Panel, hover detail
# panel, bottom-right "X / Y" counter) with level tabs added. Casting itself still happens on the
# ability bar exactly as cantrips already do — this overlay only manages what's prepared.

const PANEL_W: float = 760.0
const PANEL_H: float = 620.0
const ROW_H: float = 56.0
const DRAG_THRESHOLD: float = 8.0

var _panel: Panel
var _tab_buttons: Array[Button] = []
var _row_container: Control
var _detail_name: Label
var _detail_desc: RichTextLabel
var _counter_rtl: RichTextLabel
var _selected_level: int = 1
var _max_level: int = 0
var _prev_bar_mode_was_ability: bool = false
const ACTION_BAR_HEIGHT: float = 140.0   # matches hud.tscn's ActionBar (offset_top = -135.0) + a small margin

# Drag state (press-and-hold on a row, release over an ability-bar slot — see §5.4)
var _dragging: bool = false
var _drag_spell_id: String = ""
var _drag_start_pos: Vector2 = Vector2.ZERO
var _drag_icon: TextureRect = null

func _ready() -> void:
	layer = 25
	GameState.spellbook_open = true
	var caster: SpellcasterState = GameState.player_stats.caster
	if caster != null and caster.slot_pool != null:
		for lv: int in caster.slot_pool.max_slots():
			_max_level = maxi(_max_level, lv)
	_selected_level = 1 if _max_level == 0 else mini(_selected_level, _max_level)
	if _max_level == 0:
		_selected_level = 0
	# The ActionBar is the only valid drag-and-drop target (§5.4) — force it visible/active for
	# the overlay's whole lifetime, restoring whichever mode was showing before on close. Also
	# fixes the drag being impossible to aim at all when the item quickbar happened to be showing.
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null:
		_prev_bar_mode_was_ability = hud.is_ability_bar_showing()
		hud.set_ability_bar_mode(true)
	_build_ui()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	# Deliberately does NOT cover the bottom ActionBar strip — it's the only valid drag-and-drop
	# target (§5.4), so it must stay fully visible AND clickable while the book is open, instead
	# of being hidden/blocked under the dim overlay like every other blocking picker's full-screen
	# dim would do.
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.offset_bottom = -ACTION_BAR_HEIGHT
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, PANEL_H)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - PANEL_H) * 0.5)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.55, 0.35, 0.85)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Spellbook"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	title.position = Vector2(20.0, 14.0)
	title.size = Vector2(380.0, 34.0)
	_panel.add_child(title)

	_counter_rtl = RichTextLabel.new()
	_counter_rtl.bbcode_enabled = true
	_counter_rtl.fit_content = false
	_counter_rtl.scroll_active = false
	_counter_rtl.position = Vector2(PANEL_W - 240.0, 18.0)
	_counter_rtl.size = Vector2(100.0, 30.0)
	_counter_rtl.add_theme_font_size_override("normal_font_size", 19)
	_panel.add_child(_counter_rtl)

	var done_btn := Button.new()
	done_btn.text = "✓  Done  [R/Esc]"
	done_btn.size = Vector2(150.0, 34.0)
	done_btn.position = Vector2(PANEL_W - 166.0, 14.0)
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.add_theme_font_size_override("font_size", 14)
	_style_btn(done_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	done_btn.pressed.connect(_close)
	_panel.add_child(done_btn)

	var sep1 := HSeparator.new()
	sep1.position = Vector2(12.0, 60.0)
	sep1.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep1)

	# ── Level tabs ──────────────────────────────────────────────────────────────
	var tab_y: float = 72.0
	var tab_w: float = 64.0
	if _max_level == 0:
		var no_lv := Label.new()
		no_lv.text = "No leveled-spell slots yet."
		no_lv.add_theme_font_size_override("font_size", 14)
		no_lv.add_theme_color_override("font_color", Color(0.6, 0.6, 0.6))
		no_lv.position = Vector2(20.0, tab_y)
		_panel.add_child(no_lv)
	else:
		for lv: int in range(1, _max_level + 1):
			var tab := Button.new()
			tab.text = _ordinal(lv)
			tab.size = Vector2(tab_w, 32.0)
			tab.position = Vector2(20.0 + (lv - 1) * (tab_w + 6.0), tab_y)
			tab.focus_mode = Control.FOCUS_NONE
			tab.toggle_mode = true
			tab.pressed.connect(func() -> void: _select_level(lv))
			_panel.add_child(tab)
			_tab_buttons.append(tab)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, tab_y + 40.0)
	sep2.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep2)

	# ── Spell rows ──────────────────────────────────────────────────────────────
	_row_container = Control.new()
	_row_container.position = Vector2(20.0, tab_y + 52.0)
	_row_container.size = Vector2(PANEL_W - 40.0, 240.0)
	_panel.add_child(_row_container)

	var detail_y: float = tab_y + 52.0 + 240.0 + 12.0
	var sep3 := HSeparator.new()
	sep3.position = Vector2(12.0, detail_y)
	sep3.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep3)
	detail_y += 8.0

	# Caption so the panel's purpose is obvious at a glance, not just inferred from behavior.
	var caption := Label.new()
	caption.text = "SPELL DETAILS"
	caption.add_theme_font_size_override("font_size", 11)
	caption.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	caption.position = Vector2(20.0, detail_y)
	caption.size = Vector2(PANEL_W - 40.0, 16.0)
	_panel.add_child(caption)
	detail_y += 18.0

	_detail_name = Label.new()
	_detail_name.text = "Hover a spell above to read its description here."
	_detail_name.add_theme_font_size_override("font_size", 17)
	_detail_name.add_theme_color_override("font_color", Color(0.75, 0.55, 1.0))
	_detail_name.position = Vector2(20.0, detail_y)
	_detail_name.size = Vector2(PANEL_W - 40.0, 26.0)
	_panel.add_child(_detail_name)

	_detail_desc = RichTextLabel.new()
	_detail_desc.bbcode_enabled = true
	_detail_desc.fit_content = false
	_detail_desc.scroll_active = false
	_detail_desc.position = Vector2(20.0, detail_y + 30.0)
	_detail_desc.size = Vector2(PANEL_W - 40.0, 70.0)
	_detail_desc.add_theme_font_size_override("normal_font_size", 14)
	_panel.add_child(_detail_desc)

	var hint := Label.new()
	hint.text = "Click a spell to prepare/unprepare it. Drag it onto the ability bar below to place it in a specific slot."
	hint.add_theme_font_size_override("font_size", 12)
	hint.add_theme_color_override("font_color", Color(0.5, 0.5, 0.55))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(20.0, detail_y + 30.0 + 70.0 + 6.0)
	hint.size = Vector2(PANEL_W - 40.0, 32.0)
	_panel.add_child(hint)

	_refresh()

func _ordinal(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n

func _select_level(lv: int) -> void:
	_selected_level = lv
	_refresh()

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_border_width_all(1)
	normal.border_color = border
	normal.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.12)
	hover.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("hover", hover)

func _refresh() -> void:
	var caster: SpellcasterState = GameState.player_stats.caster
	if caster == null:
		return
	for tab: Button in _tab_buttons:
		tab.button_pressed = false
	if _selected_level > 0 and _selected_level - 1 < _tab_buttons.size():
		_tab_buttons[_selected_level - 1].button_pressed = true

	for c in _row_container.get_children():
		c.queue_free()

	var known_at_level: Array[String] = []
	for sid: String in caster.known_spells:
		var s: Spell = SpellDb.get_spell(sid)
		if s != null and s.level == _selected_level:
			known_at_level.append(sid)

	var y: float = 0.0
	for sid: String in known_at_level:
		_build_row(sid, y)
		y += ROW_H
	if known_at_level.is_empty():
		var empty_lbl := Label.new()
		empty_lbl.text = "No known spells at this level yet."
		empty_lbl.add_theme_font_size_override("font_size", 14)
		empty_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.55))
		empty_lbl.position = Vector2(0.0, 4.0)
		_row_container.add_child(empty_lbl)

	var cap: int = caster.prepared_max(GameState.player_stats)
	var count: int = caster.prepared_spells.size()
	var count_color: String = "#FFD700"
	if count > cap:
		count_color = "#e05050"
	elif count >= cap:
		count_color = "#888888"
	_counter_rtl.text = "[right][color=%s]%d / %d prepared[/color][/right]" % [count_color, count, cap]

func _build_row(spell_id: String, y: float) -> void:
	var caster: SpellcasterState = GameState.player_stats.caster
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	var prepared: bool = caster.prepared_spells.has(spell_id)

	var row := Button.new()
	row.position = Vector2(0.0, y)
	row.size = Vector2(PANEL_W - 40.0, ROW_H - 6.0)
	row.focus_mode = Control.FOCUS_NONE
	row.text = ""
	var nbox := StyleBoxFlat.new()
	nbox.bg_color = Color(0.16, 0.14, 0.05, 0.85) if prepared else Color(0.12, 0.12, 0.16, 0.9)
	nbox.set_border_width_all(2 if not prepared else 3)
	nbox.border_color = Color(0.95, 0.72, 0.28) if prepared else Color(0.35, 0.35, 0.35)
	nbox.set_corner_radius_all(4)
	row.add_theme_stylebox_override("normal", nbox)
	row.add_theme_stylebox_override("hover", nbox)
	_row_container.add_child(row)

	var icon := TextureRect.new()
	icon.size = Vector2(40.0, 40.0)
	icon.position = Vector2(6.0, (ROW_H - 6.0 - 40.0) * 0.5)
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spell.icon_path != "" and ResourceLoader.exists(spell.icon_path):
		icon.texture = load(spell.icon_path)
	row.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = spell.spell_name + ("  [PREPARED]" if prepared else "")
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.position = Vector2(54.0, (ROW_H - 6.0 - 20.0) * 0.5)
	name_lbl.size = Vector2(PANEL_W - 100.0, 22.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if prepared:
		name_lbl.add_theme_color_override("font_color", Color(1.0, 0.85, 0.3))
	row.add_child(name_lbl)

	row.mouse_entered.connect(_on_row_hover.bind(spell))
	# Only the press is handled here (per-row) — motion/release are polled in _process() (below)
	# so the drag keeps tracking once the mouse leaves the row's rect, matching
	# inventory_overlay.gd's proven whole-screen-drag pattern (Input.is_mouse_button_pressed()
	# polling) rather than relying on a per-Control gui_input capture that may not survive leaving
	# the control's bounds or may swallow the release event before a sibling ever sees it.
	row.gui_input.connect(_on_row_press.bind(spell_id))

func _on_row_hover(spell: Spell) -> void:
	_detail_name.text = spell.spell_name
	_detail_desc.text = spell.description

func _on_row_press(event: InputEvent, spell_id: String) -> void:
	if event is InputEventMouseButton and (event as InputEventMouseButton).button_index == MOUSE_BUTTON_LEFT and (event as InputEventMouseButton).pressed:
		_dragging = false
		_drag_spell_id = spell_id
		_drag_start_pos = get_viewport().get_mouse_position()

func _start_drag(spell_id: String) -> void:
	_dragging = true
	var spell: Spell = SpellDb.get_spell(spell_id)
	_drag_icon = TextureRect.new()
	_drag_icon.size = Vector2(48.0, 48.0)
	_drag_icon.ignore_texture_size = true
	_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if spell != null and spell.icon_path != "" and ResourceLoader.exists(spell.icon_path):
		_drag_icon.texture = load(spell.icon_path)
	_drag_icon.position = get_viewport().get_mouse_position() - _drag_icon.size * 0.5
	add_child(_drag_icon)

# §5.4: valid drop targets are ability-bar slots ONLY — the item quickbar (page 1) and the
# inventory overlay are always rejected, regardless of screen position, since they share the
# same physical Button rects the ability bar uses (Tab toggles which one is showing).
func _finish_drag() -> void:
	_dragging = false
	if _drag_icon != null:
		_drag_icon.queue_free()
		_drag_icon = null
	var hud = get_tree().get_first_node_in_group("hud")
	if hud == null or not hud.is_ability_bar_showing():
		GameState.game_log("[color=gray]Spells can only be placed on the ability bar.[/color]")
		return
	var mouse_pos: Vector2 = get_viewport().get_mouse_position()
	for i: int in GameState.ABILITY_BAR_SIZE:
		if hud.get_action_slot_global_rect(i).has_point(mouse_pos):
			GameState.place_spell_in_slot(_drag_spell_id, i)
			_refresh()
			return

func _close() -> void:
	GameState.spellbook_open = false
	var hud = get_tree().get_first_node_in_group("hud")
	if hud != null and not _prev_bar_mode_was_ability:
		hud.set_ability_bar_mode(false)
	queue_free()

# Drag/click resolution is polled here (not via _unhandled_input's mouse-button-up event) —
# matches inventory_overlay.gd's proven pattern: a Button's own gui_input can swallow the release
# event before a sibling's _unhandled_input ever sees it, so polling Input.is_mouse_button_pressed()
# every frame is the reliable way to detect "the drag ended" regardless of which Control the mouse
# is currently over.
func _process(_delta: float) -> void:
	if _drag_spell_id == "":
		return
	if not _dragging and get_viewport().get_mouse_position().distance_to(_drag_start_pos) > DRAG_THRESHOLD:
		_start_drag(_drag_spell_id)
	if _dragging and _drag_icon != null:
		_drag_icon.position = get_viewport().get_mouse_position() - _drag_icon.size * 0.5
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _dragging:
			_finish_drag()
		else:
			GameState.set_spell_prepared(_drag_spell_id, not GameState.player_stats.caster.prepared_spells.has(_drag_spell_id))
			_refresh()
		_drag_spell_id = ""

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE or key.physical_keycode == KEY_R:
		get_viewport().set_input_as_handled()
		_close()
