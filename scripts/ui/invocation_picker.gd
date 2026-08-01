extends CanvasLayer

# Warlock Eldritch Invocation picker — one-time-per-slot, mandatory, permanent (no respec).
# Spawned by hud.gd on GameState.invocation_choice_required. Icon-focused tile grid, 3 per row —
# same "pick one" convention as spell_learn_picker.gd/cantrip_select.gd (direct owner request):
# the tile only shows the icon + name, the full description is a native hover tooltip
# (Control.tooltip_text) instead of always-visible card text. No icon art exists for any
# invocation yet (EldritchInvocation.icon_path stays "" until sourced) — tiles render with a blank
# icon area, same asset-debt precedent as mastery_picker.gd's icon slots.
# Re-spawns itself (via GameState.invocation_choice_required, re-checked in _ready()) if more than
# one slot opened at once (e.g. level 2's +2) — each pick is its own instance of this scene.
# See scripts/entities/CLAUDE.md's "Warlock class".

const TILE_SIZE: float = 168.0
const TILE_GAP: float = 16.0
const ICON_SIZE: float = 96.0
const COLS: int = 3
const MARGIN: float = 24.0

var _panel: Panel
var _eligible: Array[EldritchInvocation] = []

func _ready() -> void:
	layer = 25
	GameState.invocation_picker_open = true
	_eligible = GameState.eldritch_invocations_eligible()
	_build_ui()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var cols: int = mini(COLS, maxi(1, _eligible.size()))
	var panel_w: float = MARGIN * 2.0 + cols * TILE_SIZE + (cols - 1) * TILE_GAP

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.65, 0.35, 0.85)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Choose an Eldritch Invocation"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.80, 0.60, 1.0))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "%d invocation slot(s) pending. This choice is permanent. Hover a tile for details." % GameState.warlock_invocation_slots_pending
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(panel_w - MARGIN * 2.0, 24.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 80.0)
	sep.size = Vector2(panel_w - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 92.0
	if _eligible.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No eligible invocations left to learn at your current level."
		none_lbl.add_theme_font_size_override("font_size", 15)
		none_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
		none_lbl.position = Vector2(MARGIN, y0)
		none_lbl.size = Vector2(panel_w - MARGIN * 2.0, 30.0)
		_panel.add_child(none_lbl)
		var skip_btn := Button.new()
		skip_btn.text = "Continue"
		skip_btn.size = Vector2(200.0, 40.0)
		skip_btn.position = Vector2((panel_w - 200.0) * 0.5, y0 + 40.0)
		skip_btn.focus_mode = Control.FOCUS_NONE
		skip_btn.pressed.connect(_on_skip)
		_panel.add_child(skip_btn)
		var panel_h_empty: float = y0 + 40.0 + 40.0 + 20.0
		_panel.size = Vector2(panel_w, panel_h_empty)
		_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h_empty) * 0.5)
		return

	var rows: int = ceili(float(_eligible.size()) / float(cols))
	for i: int in _eligible.size():
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_build_tile(_eligible[i], pos)

	var panel_h: float = y0 + rows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 20.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)

func _build_tile(inv: EldritchInvocation, pos: Vector2) -> void:
	var tile := Button.new()
	tile.position = pos
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = "%s (lvl %d)\n\n%s" % [inv.invocation_name, inv.min_level, inv.description]
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.11, 0.17)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.30, 0.30, 0.38)
	normal.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.10, 0.11, 0.17).lightened(0.08)
	hover.set_border_width_all(3)
	hover.border_color = Color(0.80, 0.60, 1.0)
	hover.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("hover", hover)
	tile.pressed.connect(func() -> void: _on_chosen(inv.invocation_id))
	_panel.add_child(tile)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((TILE_SIZE - ICON_SIZE) * 0.5, 12.0)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	if inv.icon_path != "" and ResourceLoader.exists(inv.icon_path):
		icon.texture = load(inv.icon_path)
	tile.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = "%s (lvl %d)" % [inv.invocation_name, inv.min_level]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position = Vector2(6.0, ICON_SIZE + 18.0)
	name_lbl.size = Vector2(TILE_SIZE - 12.0, TILE_SIZE - ICON_SIZE - 26.0)
	tile.add_child(name_lbl)

func _on_chosen(id: String) -> void:
	GameState.learn_invocation(id)
	_close_and_maybe_respawn()

func _on_skip() -> void:
	# No eligible invocation to pick — close WITHOUT respawning (unlike _on_chosen()), otherwise
	# a pending count that has nothing eligible to spend on (e.g. levels 12/15/18 before more
	# invocation content exists) would spawn an empty picker in an infinite loop. The pending
	# count itself is untouched — it stays pending until content or a level-up opens more, same
	# as Tier 2's own pending-points precedent.
	GameState.invocation_picker_open = false
	queue_free()

func _close_and_maybe_respawn() -> void:
	GameState.invocation_picker_open = false
	if GameState.warlock_invocation_slots_pending > 0:
		var next = load("res://scripts/ui/invocation_picker.gd").new()
		get_tree().root.call_deferred("add_child", next)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time choice — swallow all key input (no Esc close).
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
