extends CanvasLayer

# Race-select overlay — one-time, mandatory choice spawned right after class selection
# (class_select.gd._on_class_selected()), before the Mastery Picker. Modeled directly on
# subclass_select.gd's conventions: dim overlay + centered bordered Panel, focus_mode =
# FOCUS_NONE everywhere, blocks input via a GameState flag (race_picker_open), NOT dismissible
# (no close button, Esc ignored) — the choice is permanent.
# See docs/architecture/race-selection-design.md.

const PANEL_W: float = 1200.0
const GRID_COLS: int = 3
const MARGIN: float = 24.0
const CARD_GAP: float = 16.0
const CARD_H: float = 190.0
const SUB_BTN_H: float = 30.0

# id → {name, blurb}. Sub-choice races additionally carry "sub_kind" + "sub_options".
const RACES: Array[Dictionary] = [
	{
		"id": "orc", "name": "Orc",
		"blurb": "Relentless Endurance holds you at 1 HP once per long rest. Superior darkvision.",
	},
	{
		"id": "human", "name": "Human",
		"blurb": "Heroic Inspiration rerolls a miss once per long rest. Choose one bonus ability proficiency. No darkvision.",
		"sub_kind": "ability_score",
		"sub_options": ["STR", "DEX", "CON", "INT", "WIS", "CHA"],
	},
	{
		"id": "halfling", "name": "Halfling",
		"blurb": "Lucky: automatically reroll a natural 1, keeping the new result. No darkvision.",
	},
	{
		"id": "dwarf", "name": "Dwarf",
		"blurb": "+1 max HP every level. Superior darkvision.",
	},
	{
		"id": "elf", "name": "Elf",
		"blurb": "WIS proficiency, shorter long rests, darkvision. Choose a sub-race.",
		"sub_kind": "subrace",
		"sub_options": ["Drow", "High Elf", "Wood Elf"],
	},
	{
		"id": "dragonborn", "name": "Dragonborn",
		"blurb": "Choose an ancestry for elemental resistance. Darkvision.",
		"sub_kind": "ancestry",
		"sub_options": ["Black", "Blue", "Brass", "Bronze", "Copper", "Gold", "Green", "Red", "Silver", "White"],
	},
]

var _selected_id: String = ""
var _selected_sub: int = -1
var _card_btns: Dictionary = {}      # race id → Button
var _sub_rows: Dictionary = {}       # race id → Control (sub-choice row, hidden until selected)
var _sub_btns: Dictionary = {}       # race id → Array[Button]
var _confirm_btn: Button
var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.race_picker_open = true
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
	title.text = "Choose Your Race"
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

	var cols: int = mini(GRID_COLS, RACES.size())
	var rows: int = ceili(float(RACES.size()) / float(cols))
	var card_w: float = (PANEL_W - MARGIN * 2.0 - CARD_GAP * float(cols - 1)) / float(cols)
	var y0: float = 92.0
	for i: int in RACES.size():
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (card_w + CARD_GAP), y0 + row * (CARD_H + CARD_GAP))
		_build_card(RACES[i], pos, Vector2(card_w, CARD_H))

	var grid_h: float = float(rows) * CARD_H + float(rows - 1) * CARD_GAP

	var confirm_y: float = y0 + grid_h + 18.0
	_confirm_btn = Button.new()
	_confirm_btn.text = "Choose a race…"
	_confirm_btn.size = Vector2(280.0, 44.0)
	_confirm_btn.position = Vector2((PANEL_W - 280.0) * 0.5, confirm_y)
	_confirm_btn.focus_mode = Control.FOCUS_NONE
	_confirm_btn.disabled = true
	_confirm_btn.add_theme_font_size_override("font_size", 16)
	var dis_sbox := StyleBoxFlat.new()
	dis_sbox.bg_color = Color(0.10, 0.10, 0.10, 0.5)
	dis_sbox.set_border_width_all(1)
	dis_sbox.border_color = Color(0.22, 0.22, 0.22)
	_confirm_btn.add_theme_stylebox_override("disabled", dis_sbox)
	_style_btn(_confirm_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	_confirm_btn.pressed.connect(_on_confirm)
	_panel.add_child(_confirm_btn)

	var panel_h: float = confirm_y + 44.0 + 20.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

func _build_card(data: Dictionary, pos: Vector2, card_size: Vector2) -> void:
	var race_id: String = data["id"]
	var card := Button.new()
	card.position = pos
	card.size = card_size
	card.focus_mode = Control.FOCUS_NONE
	_apply_card_style(card, false)
	card.pressed.connect(func() -> void: _select(race_id))
	_card_btns[race_id] = card
	_panel.add_child(card)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	name_lbl.position = Vector2(14.0, 10.0)
	name_lbl.size = Vector2(card_size.x - 28.0, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var blurb_lbl := Label.new()
	blurb_lbl.text = data["blurb"]
	blurb_lbl.add_theme_font_size_override("font_size", 12)
	blurb_lbl.add_theme_color_override("font_color", Color(0.72, 0.72, 0.76))
	blurb_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	blurb_lbl.position = Vector2(14.0, 42.0)
	blurb_lbl.size = Vector2(card_size.x - 28.0, 68.0)
	blurb_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(blurb_lbl)

	if data.has("sub_kind"):
		var options: Array = data["sub_options"]
		var row := Control.new()
		row.position = Vector2(10.0, 112.0)
		row.size = Vector2(card_size.x - 20.0, CARD_H - 122.0)
		row.mouse_filter = Control.MOUSE_FILTER_STOP
		row.visible = false
		card.add_child(row)
		_sub_rows[race_id] = row
		var btns: Array[Button] = []
		var per_row: int = 3
		var btn_w: float = (row.size.x - CARD_GAP * float(per_row - 1)) / float(per_row)
		for i: int in options.size():
			var col: int = i % per_row
			var r: int = i / per_row
			var sub_btn := Button.new()
			sub_btn.text = options[i]
			sub_btn.focus_mode = Control.FOCUS_NONE
			sub_btn.size = Vector2(btn_w, SUB_BTN_H)
			sub_btn.position = Vector2(col * (btn_w + CARD_GAP), r * (SUB_BTN_H + 4.0))
			sub_btn.add_theme_font_size_override("font_size", 11)
			_style_btn(sub_btn, Color(0.12, 0.12, 0.18), Color(0.35, 0.35, 0.42))
			sub_btn.pressed.connect(_on_sub_selected.bind(race_id, i))
			row.add_child(sub_btn)
			btns.append(sub_btn)
		_sub_btns[race_id] = btns

func _select(race_id: String) -> void:
	if _selected_id == race_id:
		return
	_selected_id = race_id
	_selected_sub = -1
	for id: String in _card_btns:
		_apply_card_style(_card_btns[id], id == race_id)
		if _sub_rows.has(id):
			(_sub_rows[id] as Control).visible = (id == race_id)
	var data: Dictionary = _race_data(race_id)
	if data.has("sub_kind"):
		_confirm_btn.disabled = true
		_confirm_btn.text = "Choose a %s option…" % [data["sub_kind"]]
	else:
		_confirm_btn.disabled = false
		_confirm_btn.text = "Choose %s" % data["name"]

func _on_sub_selected(race_id: String, idx: int) -> void:
	if _selected_id != race_id:
		return
	_selected_sub = idx
	var btns: Array = _sub_btns.get(race_id, [])
	for i: int in btns.size():
		_apply_sub_btn_style(btns[i], i == idx)
	var data: Dictionary = _race_data(race_id)
	var option_name: String = (data["sub_options"] as Array)[idx]
	_confirm_btn.disabled = false
	_confirm_btn.text = "Choose %s (%s)" % [data["name"], option_name]

func _race_data(race_id: String) -> Dictionary:
	for d: Dictionary in RACES:
		if d["id"] == race_id:
			return d
	return {}

func _on_confirm() -> void:
	if _selected_id == "":
		return
	var data: Dictionary = _race_data(_selected_id)
	if data.has("sub_kind") and _selected_sub < 0:
		return
	var race: Stats.CharacterRace = _race_enum(_selected_id)
	var variant: int = 0
	var prof_ability: int = -1
	match data.get("sub_kind", ""):
		"ability_score": prof_ability = _selected_sub
		"subrace", "ancestry": variant = _selected_sub
	GameState.race_picker_open = false
	GameState.choose_race(race, variant, prof_ability)
	if GameState.player_stats.mastery_cap() > 0:
		var picker = load("res://scripts/ui/mastery_picker.gd").new()
		get_tree().root.call_deferred("add_child", picker)
	elif GameState.player_stats.character_class == Stats.CharacterClass.WIZARD:
		var cantrip_picker = load("res://scripts/ui/cantrip_select.gd").new()
		get_tree().root.call_deferred("add_child", cantrip_picker)
	queue_free()

func _race_enum(race_id: String) -> Stats.CharacterRace:
	match race_id:
		"orc": return Stats.CharacterRace.ORC
		"human": return Stats.CharacterRace.HUMAN
		"halfling": return Stats.CharacterRace.HALFLING
		"dwarf": return Stats.CharacterRace.DWARF
		"elf": return Stats.CharacterRace.ELF
		"dragonborn": return Stats.CharacterRace.DRAGONBORN
	return Stats.CharacterRace.HUMAN

# ── Style helpers (mirrors subclass_select.gd) ─────────────────────────────────────────

func _apply_card_style(card: Button, selected: bool) -> void:
	var bg := Color(0.10, 0.11, 0.17) if not selected else Color(0.14, 0.13, 0.08)
	var border := Color(0.30, 0.30, 0.38) if not selected else Color(1.0, 0.82, 0.22)
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_border_width_all(2 if not selected else 3)
	normal.border_color = border
	normal.set_corner_radius_all(6)
	card.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.06)
	hover.set_border_width_all(2 if not selected else 3)
	hover.border_color = border.lightened(0.15)
	hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("hover", hover)
	var pressed := StyleBoxFlat.new()
	pressed.bg_color = bg.darkened(0.08)
	pressed.set_border_width_all(3)
	pressed.border_color = border
	pressed.set_corner_radius_all(6)
	card.add_theme_stylebox_override("pressed", pressed)

func _apply_sub_btn_style(btn: Button, selected: bool) -> void:
	var bg := Color(0.12, 0.12, 0.18) if not selected else Color(0.16, 0.14, 0.06)
	var border := Color(0.35, 0.35, 0.42) if not selected else Color(1.0, 0.82, 0.22)
	_style_btn(btn, bg, border)

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

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time choice — swallow all key input (no Esc close) so nothing
	# leaks to gameplay handlers underneath.
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
