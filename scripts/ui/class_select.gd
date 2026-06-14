extends CanvasLayer

const CARD_W: int = 148
const CARD_H: int = 230
const CARD_GAP: int = 18
const CHAR_PATH := "res://sprites/characters/"

const CLASS_DATA: Array = [
	{
		"cls":    0,  # Stats.CharacterClass.FIGHTER
		"name":   "Fighter",
		"sprite": CHAR_PATH + "knight_m_idle_anim_f0.png",
		"hd":     "d10 HD",
		"hp":     "12 HP",
		"desc":   "A warrior hardened by\nbattle. High HP and\nsteady damage output.",
		"color":  Color(0.90, 0.60, 0.20),
	},
	{
		"cls":    1,  # Stats.CharacterClass.ROGUE
		"name":   "Rogue",
		"sprite": CHAR_PATH + "elf_m_idle_anim_f0.png",
		"hd":     "d8 HD",
		"hp":     "9 HP",
		"desc":   "Swift and cunning.\nHigh DEX grants better\nArmor Class.",
		"color":  Color(0.50, 0.85, 0.50),
	},
	{
		"cls":    2,  # Stats.CharacterClass.WIZARD
		"name":   "Wizard",
		"sprite": CHAR_PATH + "wizzard_m_idle_anim_f0.png",
		"hd":     "d6 HD",
		"hp":     "7 HP",
		"desc":   "Frail but intelligent.\nBenefits most from\nscrolls and wands.",
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

	var title := Label.new()
	title.text = "Choose Your Class"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, 72.0)
	title.size = Vector2(1280.0, 36.0)
	add_child(title)

	var sub := Label.new()
	sub.text = "Click a card to begin your descent"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.44))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, 104.0)
	sub.size = Vector2(1280.0, 18.0)
	add_child(sub)

	var total_w: float = CLASS_DATA.size() * CARD_W + (CLASS_DATA.size() - 1) * CARD_GAP
	var origin_x: float = (1280.0 - total_w) / 2.0
	var origin_y: float = 136.0

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
	icon.position = Vector2(float(CARD_W) / 2.0 - 36.0, 14.0)
	icon.size = Vector2(72.0, 72.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 14)
	name_lbl.add_theme_color_override("font_color", data["color"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0.0, 92.0)
	name_lbl.size = Vector2(CARD_W, 22.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var hd_lbl := Label.new()
	hd_lbl.text = "%s  •  %s" % [data["hd"], data["hp"]]
	hd_lbl.add_theme_font_size_override("font_size", 9)
	hd_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	hd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd_lbl.position = Vector2(0.0, 116.0)
	hd_lbl.size = Vector2(CARD_W, 14.0)
	hd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hd_lbl)

	var sep := HSeparator.new()
	sep.position = Vector2(10.0, 136.0)
	sep.size = Vector2(CARD_W - 20.0, 2.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 9)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(8.0, 142.0)
	desc_lbl.size = Vector2(CARD_W - 16.0, 56.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = "Select"
	btn.position = Vector2(22.0, 196.0)
	btn.size = Vector2(CARD_W - 44.0, 26.0)
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
	btn.add_theme_font_size_override("font_size", 10)
	btn.pressed.connect(_on_class_selected.bind(data["cls"] as int))
	card.add_child(btn)

func _on_class_selected(cls_idx: int) -> void:
	GameState.player_stats.character_class = cls_idx as Stats.CharacterClass
	GameState.player_stats.apply_class_defaults()
	GameState.class_selected = true
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.class_chosen.emit(GameState.player_stats.character_class)
	queue_free()
