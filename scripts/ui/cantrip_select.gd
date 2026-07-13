extends CanvasLayer

# Wizard's one-time cantrip pick — spawned by race_select.gd right after race confirm, in place
# of the Mastery Picker (Wizard's mastery_cap() is already 0). Modeled on mastery_picker.gd's
# overlay/panel styling, but card-click commits immediately (subclass_select.gd's style) since
# there's no multi-select here — a single irreversible pick.

const PANEL_W: float = 760.0
const CARD_H: float = 160.0
const CARD_GAP: float = 16.0
const MARGIN: float = 24.0

var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.cantrip_picker_open = true
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
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Choose Your Starting Cantrip"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "This choice is permanent."
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
	for i: int in SpellDb.CANTRIP_IDS.size():
		var spell: Spell = SpellDb.get_spell(SpellDb.CANTRIP_IDS[i])
		var pos := Vector2(MARGIN, y0 + i * (CARD_H + CARD_GAP))
		_build_card(spell, pos, Vector2(PANEL_W - MARGIN * 2.0, CARD_H))

	var panel_h: float = y0 + SpellDb.CANTRIP_IDS.size() * (CARD_H + CARD_GAP) - CARD_GAP + 20.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

func _build_card(spell: Spell, pos: Vector2, card_size: Vector2) -> void:
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
	hover.border_color = Color(1.0, 0.82, 0.22)
	hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("hover", hover)
	card.pressed.connect(func() -> void: _on_chosen(spell.spell_id))
	_panel.add_child(card)

	var name_lbl := Label.new()
	name_lbl.text = spell.spell_name
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	name_lbl.position = Vector2(14.0, 10.0)
	name_lbl.size = Vector2(card_size.x - 28.0, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var blurb_lbl := Label.new()
	blurb_lbl.text = spell.description
	blurb_lbl.add_theme_font_size_override("font_size", 13)
	blurb_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.76))
	blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb_lbl.position = Vector2(14.0, 42.0)
	blurb_lbl.size = Vector2(card_size.x - 28.0, card_size.y - 56.0)
	blurb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(blurb_lbl)

func _on_chosen(spell_id: String) -> void:
	GameState.cantrip_picker_open = false
	GameState.choose_cantrip(spell_id)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time choice — swallow all key input (no Esc close).
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
