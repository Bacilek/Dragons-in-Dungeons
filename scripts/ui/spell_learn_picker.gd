extends CanvasLayer

# Wizard's level-up spell-learn picker — docs/architecture/leveled-spells-and-slots-plan.md §4.1.
# Spawned by hud.gd._on_player_leveled_up() whenever GameState.spell_learn_pending is true (up to
# 3 candidates rolled by GameState._roll_spell_learn_choices()). Icon-focused tile grid, 3 per row
# — direct owner request: a "pick one" spell/invocation choice should be a row of icon tiles, not
# a stack of full-text cards; the tile itself only shows the icon + name, the full structured
# SpellTooltip.build_plain() readout is a native hover tooltip (Control.tooltip_text) instead.
# Mandatory (no skip), Esc swallowed — matches cantrip_select.gd's own picker conventions.

const TILE_SIZE: float = 168.0
const TILE_GAP: float = 16.0
const ICON_SIZE: float = 96.0
const COLS: int = 3
const MARGIN: float = 24.0

var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.spell_learn_picker_open = true
	_build_ui()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var choices: Array[String] = GameState.spell_learn_choices
	var cols: int = mini(COLS, maxi(1, choices.size()))
	var rows: int = ceili(float(choices.size()) / float(cols))
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
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "New Spell Learned!"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "Choose one spell to add to your spellbook. This choice is permanent. Hover a tile for details."
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
	for i: int in choices.size():
		var spell: Spell = SpellDb.get_spell(choices[i])
		if spell == null:
			continue
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_build_tile(spell, pos)

	var panel_h: float = y0 + rows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 20.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)

func _build_tile(spell: Spell, pos: Vector2) -> void:
	var tile := Button.new()
	tile.position = pos
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = SpellTooltip.build_plain(spell)
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.11, 0.17)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.30, 0.30, 0.38)
	normal.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.10, 0.11, 0.17).lightened(0.08)
	hover.set_border_width_all(3)
	hover.border_color = Color(1.0, 0.82, 0.22)
	hover.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("hover", hover)
	tile.pressed.connect(func() -> void: _on_chosen(spell.spell_id))
	_panel.add_child(tile)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((TILE_SIZE - ICON_SIZE) * 0.5, 12.0)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	if ResourceLoader.exists(spell.icon_path):
		icon.texture = load(spell.icon_path)
	tile.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = spell.spell_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position = Vector2(6.0, ICON_SIZE + 18.0)
	name_lbl.size = Vector2(TILE_SIZE - 12.0, TILE_SIZE - ICON_SIZE - 26.0)
	tile.add_child(name_lbl)

func _on_chosen(spell_id: String) -> void:
	GameState.spell_learn_picker_open = false
	GameState.learn_spell(spell_id)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time choice — swallow all key input (no Esc close).
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
