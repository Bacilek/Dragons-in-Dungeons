extends CanvasLayer

const CARD_W: int = 200
const CARD_H: int = 500
const CARD_GAP: int = 24
const CHAR_PATH := "res://sprites/characters/"

const CLASS_DATA: Array = [
	{
		"cls":    0,  # Stats.CharacterClass.BARBARIAN
		"name":   "Barbarian",
		"sprite": CHAR_PATH + "knight_m_idle_anim_f0.png",
		"hd":     "d12 HD",
		"hp":     "14 HP",
		"desc":   "Raging warrior of\nimmense strength.\nHighest HP, hits hardest.",
		"color":  Color(0.90, 0.60, 0.20),
	},
	{
		"cls":    1,  # Stats.CharacterClass.RANGER
		"name":   "Ranger",
		"sprite": CHAR_PATH + "elf_m_idle_anim_f0.png",
		"hd":     "d10 HD",
		"hp":     "11 HP",
		"desc":   "Swift hunter of the wilds.\nHigh DEX grants the\nbest Armor Class.",
		"color":  Color(0.50, 0.85, 0.50),
	},
	{
		"cls":    2,  # Stats.CharacterClass.WIZARD
		"name":   "Wizard",
		"sprite": CHAR_PATH + "wizzard_m_idle_anim_f0.png",
		"hd":     "d6 HD",
		"hp":     "6 HP",
		"desc":   "Frail but brilliant.\nBenefits most from\nscrolls and wands.",
		"color":  Color(0.50, 0.65, 1.00),
	},
	{
		"cls":    3,  # Stats.CharacterClass.CLERIC
		"name":   "Cleric",
		"sprite": CHAR_PATH + "dwarf_m_idle_anim_f0.png",
		"hd":     "d8 HD",
		"hp":     "10 HP",
		"desc":   "Blessed by the gods.\nHigh WIS and steady\nHP regeneration.",
		"color":  Color(1.00, 0.80, 0.40),
	},
]

func _ready() -> void:
	layer = 20
	if GameState.class_selected:
		queue_free()
		return
	_build_ui()

func _build_ui() -> void:
	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.88)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var total_w: float = CLASS_DATA.size() * CARD_W + (CLASS_DATA.size() - 1) * CARD_GAP
	var origin_x: float = (vp.x - total_w) / 2.0
	var origin_y: float = (vp.y - CARD_H) / 2.0

	var title := Label.new()
	title.text = "Choose Your Class"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, origin_y - 64.0)
	title.size = Vector2(vp.x, 36.0)
	add_child(title)

	var sub := Label.new()
	sub.text = "Click a card to begin your descent"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.44))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, origin_y - 28.0)
	sub.size = Vector2(vp.x, 18.0)
	add_child(sub)

	for i: int in CLASS_DATA.size():
		_build_card(CLASS_DATA[i], Vector2(origin_x + i * (CARD_W + CARD_GAP), origin_y))

func _build_card(data: Dictionary, pos: Vector2) -> void:
	var card := Panel.new()
	card.position = pos
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.09, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = (data["color"] as Color) * 0.7
	sbox.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sbox)
	add_child(card)

	var icon := TextureRect.new()
	var sprite_path: String = data["sprite"]
	if ResourceLoader.exists(sprite_path):
		icon.texture = load(sprite_path)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(float(CARD_W) / 2.0 - 50.0, 18.0)
	icon.size = Vector2(100.0, 100.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", data["color"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0.0, 124.0)
	name_lbl.size = Vector2(CARD_W, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var hd_lbl := Label.new()
	hd_lbl.text = "%s  •  %s" % [data["hd"], data["hp"]]
	hd_lbl.add_theme_font_size_override("font_size", 12)
	hd_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	hd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd_lbl.position = Vector2(0.0, 156.0)
	hd_lbl.size = Vector2(CARD_W, 18.0)
	hd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hd_lbl)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 180.0)
	sep.size = Vector2(CARD_W - 24.0, 2.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 12)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(10.0, 186.0)
	desc_lbl.size = Vector2(CARD_W - 20.0, 80.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, 272.0)
	sep2.size = Vector2(CARD_W - 24.0, 2.0)
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep2)

	var s: Stats = _make_class_stats(data["cls"] as int)
	var stat_rows: Array = [
		["STR", s.strength,     s.str_modifier()],
		["DEX", s.dexterity,    s.dex_modifier()],
		["CON", s.constitution, s.con_modifier()],
		["INT", s.intelligence, s.int_modifier()],
		["WIS", s.wisdom,       s.wis_modifier()],
		["CHA", s.charisma,     s.cha_modifier()],
	]
	for i: int in stat_rows.size():
		_add_stat_row(card, 278.0 + i * 20.0, stat_rows[i][0], stat_rows[i][1], stat_rows[i][2])

	var sep3 := HSeparator.new()
	sep3.position = Vector2(12.0, 402.0)
	sep3.size = Vector2(CARD_W - 24.0, 2.0)
	sep3.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep3)

	var ac_lbl := Label.new()
	ac_lbl.text = "AC"
	ac_lbl.position = Vector2(18.0, 408.0)
	ac_lbl.size = Vector2(38.0, 18.0)
	ac_lbl.add_theme_font_size_override("font_size", 13)
	ac_lbl.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	ac_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ac_lbl)

	var ac_val := Label.new()
	ac_val.text = str(s.armor_class)
	ac_val.position = Vector2(62.0, 408.0)
	ac_val.size = Vector2(30.0, 18.0)
	ac_val.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	ac_val.add_theme_font_size_override("font_size", 13)
	ac_val.add_theme_color_override("font_color", Color(0.60, 0.85, 1.00))
	ac_val.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ac_val)

	var ac_note := Label.new()
	var ac_formula: String
	if (data["cls"] as int) == 0:  # Barbarian: unarmored defense
		ac_formula = "(10+DEX+CON)"
	else:
		ac_formula = "(10+DEX)"
	ac_note.text = ac_formula
	ac_note.position = Vector2(98.0, 408.0)
	ac_note.size = Vector2(82.0, 18.0)
	ac_note.add_theme_font_size_override("font_size", 11)
	ac_note.add_theme_color_override("font_color", Color(0.45, 0.45, 0.50))
	ac_note.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(ac_note)

	var btn := Button.new()
	btn.text = "Select"
	btn.position = Vector2(26.0, 456.0)
	btn.size = Vector2(CARD_W - 52.0, 32.0)
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = (data["color"] as Color) * 0.35
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = (data["color"] as Color) * 0.8
	btn_normal.set_corner_radius_all(4)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = (data["color"] as Color) * 0.55
	btn_hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover",  btn_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_font_size_override("font_size", 13)
	btn.pressed.connect(_on_class_selected.bind(data["cls"] as int))
	card.add_child(btn)

func _make_class_stats(cls_idx: int) -> Stats:
	var s := Stats.new()
	s.character_class = cls_idx as Stats.CharacterClass
	s.apply_class_defaults()
	return s

func _add_stat_row(parent: Control, y: float, stat_name: String, score: int, mod_val: int) -> void:
	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.position = Vector2(18.0, y)
	name_lbl.size = Vector2(40.0, 18.0)
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(name_lbl)

	var score_lbl := Label.new()
	score_lbl.text = str(score)
	score_lbl.position = Vector2(68.0, y)
	score_lbl.size = Vector2(30.0, 18.0)
	score_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	score_lbl.add_theme_font_size_override("font_size", 13)
	score_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	score_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(score_lbl)

	var mod_lbl := Label.new()
	mod_lbl.text = "(%+d)" % mod_val
	mod_lbl.position = Vector2(106.0, y)
	mod_lbl.size = Vector2(70.0, 18.0)
	mod_lbl.add_theme_font_size_override("font_size", 13)
	var mod_color: Color
	if mod_val > 0:   mod_color = Color(0.40, 0.85, 0.45)
	elif mod_val < 0: mod_color = Color(0.85, 0.38, 0.32)
	else:             mod_color = Color(0.50, 0.50, 0.55)
	mod_lbl.add_theme_color_override("font_color", mod_color)
	mod_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(mod_lbl)

func _on_class_selected(cls_idx: int) -> void:
	GameState.player_stats.character_class = cls_idx as Stats.CharacterClass
	GameState.player_stats.apply_class_defaults()
	GameState.give_class_starting_items()
	GameState.class_selected = true
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.class_chosen.emit(GameState.player_stats.character_class)
	queue_free()
