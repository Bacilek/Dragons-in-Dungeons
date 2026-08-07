extends CanvasLayer

# Warlock Eldritch Invocation picker — one-time-per-slot, mandatory, permanent (no respec).
# Spawned by hud.gd on GameState.invocation_choice_required. Icon-focused tile grid, 3 per row —
# same "pick one" convention as spell_learn_picker.gd/cantrip_select.gd (direct owner request):
# the tile only shows the icon + name, and hovering shows a styled BBCode popup (same panel/border
# convention as SpellTooltip's own readouts elsewhere in the game — not a native tooltip_text,
# which reads too faint/plain to be legible) anchored ABOVE the tile. No icon art exists for any
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
const TOOLTIP_W: float = 240.0

var _panel: Panel
var _eligible: Array[EldritchInvocation] = []
var _tooltip: Panel
var _tooltip_rtl: RichTextLabel
var _hover_source_rect: Rect2 = Rect2()   # last-shown tile's global rect, for _process()'s hover-chain check
# Grace period before the hover chain hides — see hud.gd's identical `_HOVER_CHAIN_HIDE_GRACE_SEC`
# for why: a single frame crossing the gap between a tile and its tooltip otherwise reads as "left
# the chain" and closes it before the mouse can ever reach the tooltip.
const _HOVER_CHAIN_HIDE_GRACE_SEC: float = 0.2
var _hover_chain_outside_time: float = 0.0

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
	title.position = Vector2(MARGIN, 16.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 36.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "%d invocation slot(s) pending. This choice is permanent. Hover a tile for details." % GameState.warlock_invocation_slots_pending
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 56.0)
	hint.size = Vector2(panel_w - MARGIN * 2.0, 28.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 96.0)
	sep.size = Vector2(panel_w - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 110.0
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
		var panel_h_empty: float = y0 + 40.0 + 40.0 + 28.0
		_panel.size = Vector2(panel_w, panel_h_empty)
		_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h_empty) * 0.5)
		return

	var rows: int = ceili(float(_eligible.size()) / float(cols))
	for i: int in _eligible.size():
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_build_tile(_eligible[i], pos)

	var panel_h: float = y0 + rows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 28.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)
	_setup_tooltip()

func _build_tile(inv: EldritchInvocation, pos: Vector2) -> void:
	var tile := Button.new()
	tile.position = pos
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.focus_mode = Control.FOCUS_NONE
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
	var tooltip_text: String = "[b]%s[/b] [color=gray](lvl %d)[/color]\n%s" % [inv.invocation_name, inv.min_level, inv.description]
	tile.mouse_entered.connect(func() -> void: _show_tooltip(tooltip_text, tile))
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

# ── Hover tooltip (reuses the same styled panel every other spell readout in the game uses,
# hud.gd's _setup_quickbar_tooltip()'s own bg/border convention — not a native tooltip_text) ──

func _setup_tooltip() -> void:
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.z_index = 30
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.50, 0.35)
	sb.set_corner_radius_all(3)
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip_rtl = RichTextLabel.new()
	_tooltip_rtl.bbcode_enabled = true
	_tooltip_rtl.fit_content = true
	_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_rtl.offset_left = 8.0
	_tooltip_rtl.offset_top = 6.0
	_tooltip_rtl.offset_right = -8.0
	_tooltip_rtl.offset_bottom = -6.0
	_tooltip.add_child(_tooltip_rtl)
	add_child(_tooltip)

func _show_tooltip(text: String, tile: Control) -> void:
	_tooltip_rtl.text = text
	var w: float = TOOLTIP_W
	_tooltip_rtl.size = Vector2(w, 0)
	_hover_source_rect = Rect2(tile.global_position, tile.size)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# BUGFIX: th was computed for the position calc below but never actually applied to
	# _tooltip.size — the panel stayed pinned at its 60px placeholder height regardless of how
	# tall the text actually was, so a long description visibly overflowed/got clipped by its own
	# background box.
	var th: float = maxf(60.0, _tooltip_rtl.get_content_height() + 12.0)
	_tooltip.size = Vector2(w + 16.0, th)
	_tooltip.visible = true
	var tx: float = clampf(_hover_source_rect.position.x, 4.0, vp.x - (w + 16.0) - 4.0)
	# Anchored ABOVE the tile — direct owner request (tooltips used to spawn below the icon).
	var ty: float = _hover_source_rect.position.y - th - 8.0
	if ty < 4.0:
		ty = _hover_source_rect.position.y + _hover_source_rect.size.y + 8.0
	_tooltip.position = Vector2(tx, ty)

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

## Hiding is driven entirely by this per-frame hover-chain check, not mouse_exited — a tile's own
## mouse_exited fires the instant the cursor leaves it, even when heading straight up INTO the
## tooltip that sits just above it, which used to make the popup disappear before the mouse could
## ever reach it. Keeping it open while the mouse is over either the source tile OR the tooltip
## itself (same "hover chain" convention as hud.gd's own qbar tooltip) also means a longer
## description that needs scanning won't vanish out from under the cursor.
func _process(delta: float) -> void:
	if _tooltip == null or not _tooltip.visible:
		return
	var mp: Vector2 = get_viewport().get_mouse_position()
	var over_tooltip := Rect2(_tooltip.global_position, _tooltip.size).has_point(mp)
	if _hover_source_rect.has_point(mp) or over_tooltip:
		_hover_chain_outside_time = 0.0
	else:
		_hover_chain_outside_time += delta
	if _hover_chain_outside_time > _HOVER_CHAIN_HIDE_GRACE_SEC:
		_tooltip.visible = false

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
