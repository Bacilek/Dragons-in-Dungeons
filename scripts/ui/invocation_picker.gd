extends CanvasLayer

# Warlock Eldritch Invocation picker — one-time-per-slot, mandatory, permanent (no respec).
# Spawned by hud.gd on GameState.invocation_choice_required. Structurally a fork of
# subclass_select.gd (non-dismissible dim overlay + centered bordered Panel) rather than
# talent_picker.gd — there are no ranks/points to spend, just "pick one from the eligible list."
# Re-spawns itself (via GameState.invocation_choice_required, re-checked in _ready()) if more than
# one slot opened at once (e.g. level 2's +2) — each pick is its own instance of this scene.
# See scripts/entities/CLAUDE.md's "Warlock class".

const PANEL_W: float = 760.0
const CARD_H: float = 110.0
const CARD_GAP: float = 14.0
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
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "%d invocation slot(s) pending. This choice is permanent." % GameState.warlock_invocation_slots_pending
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(PANEL_W - MARGIN * 2.0, 24.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 80.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 92.0
	if _eligible.is_empty():
		var none_lbl := Label.new()
		none_lbl.text = "No eligible invocations left to learn at your current level."
		none_lbl.add_theme_font_size_override("font_size", 15)
		none_lbl.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
		none_lbl.position = Vector2(MARGIN, y0)
		none_lbl.size = Vector2(PANEL_W - MARGIN * 2.0, 30.0)
		_panel.add_child(none_lbl)
		var skip_btn := Button.new()
		skip_btn.text = "Continue"
		skip_btn.size = Vector2(200.0, 40.0)
		skip_btn.position = Vector2((PANEL_W - 200.0) * 0.5, y0 + 40.0)
		skip_btn.focus_mode = Control.FOCUS_NONE
		skip_btn.pressed.connect(_on_skip)
		_panel.add_child(skip_btn)
		var panel_h_empty: float = y0 + 40.0 + 40.0 + 20.0
		_panel.size = Vector2(PANEL_W, panel_h_empty)
		_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h_empty) * 0.5)
		return

	for i: int in _eligible.size():
		var pos := Vector2(MARGIN, y0 + i * (CARD_H + CARD_GAP))
		_build_card(_eligible[i], pos, Vector2(PANEL_W - MARGIN * 2.0, CARD_H))

	var panel_h: float = y0 + _eligible.size() * (CARD_H + CARD_GAP) - CARD_GAP + 20.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

func _build_card(inv: EldritchInvocation, pos: Vector2, card_size: Vector2) -> void:
	var card := Button.new()
	card.position = pos
	card.size = card_size
	card.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.11, 0.17)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.30, 0.30, 0.38)
	normal.set_corner_radius_all(6)
	card.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.10, 0.11, 0.17).lightened(0.08)
	hover.set_border_width_all(3)
	hover.border_color = Color(0.80, 0.60, 1.0)
	hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("hover", hover)
	card.pressed.connect(func() -> void: _on_chosen(inv.invocation_id))
	_panel.add_child(card)

	var name_lbl := Label.new()
	name_lbl.text = "%s (lvl %d)" % [inv.invocation_name, inv.min_level]
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(0.80, 0.60, 1.0))
	name_lbl.position = Vector2(14.0, 10.0)
	name_lbl.size = Vector2(card_size.x - 28.0, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var blurb_lbl := Label.new()
	blurb_lbl.text = inv.description
	blurb_lbl.add_theme_font_size_override("font_size", 13)
	blurb_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.76))
	blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb_lbl.position = Vector2(14.0, 42.0)
	blurb_lbl.size = Vector2(card_size.x - 28.0, card_size.y - 56.0)
	blurb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(blurb_lbl)

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
