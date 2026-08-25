extends CanvasLayer

const TILE_SIZE: int = 170
const TILE_GAP: int = 18
const GRID_COLUMNS: int = 6
const CHAR_PATH := "res://sprites/characters/classes/"

const CLASS_DATA: Array = [
	{
		"cls":    0,  # Stats.CharacterClass.BARBARIAN
		"name":   "Barbarian",
		"sprite": CHAR_PATH + "Barbarian/idle_1.png",
		"hd":     "d12 Hit Die",
		"desc":   "Raging warrior of\nimmense strength.",
		"color":  Color(0.90, 0.60, 0.20),
		"info": {
			"primary_ability": "STR",
			"hit_die": "d12",
			"check_profs": "STR, CON",
			"weapon_profs": "Simple, Martial",
			"armor_training": "Light, Medium, Shields",
			"starting_equipment": "",
		},
	},
	{
		"cls":    1,  # Stats.CharacterClass.RANGER
		"name":   "Ranger",
		"sprite": CHAR_PATH + "Ranger/idle_1.png",
		"hd":     "d10 Hit Die",
		"desc":   "Swift hunter\nof the wilds.",
		"color":  Color(0.50, 0.85, 0.50),
		"info": {
			"primary_ability": "DEX",
			"hit_die": "d10",
			"check_profs": "STR, DEX",
			"weapon_profs": "Simple, Martial",
			"armor_training": "Light, Medium, Shields",
			"starting_equipment": "",
		},
	},
	{
		"cls":    2,  # Stats.CharacterClass.WIZARD
		"name":   "Wizard",
		"sprite": CHAR_PATH + "Wizard/idle_1.png",
		"hd":     "d6 Hit Die",
		"desc":   "Frail but\nbrilliant.",
		"color":  Color(0.50, 0.65, 1.00),
		"info": {
			"primary_ability": "INT",
			"hit_die": "d6",
			"check_profs": "INT, WIS",
			"weapon_profs": "Simple",
			"armor_training": "None",
			"starting_equipment": "",
		},
	},
	{
		"cls":    3,  # Stats.CharacterClass.MONK
		"name":   "Monk",
		"sprite": CHAR_PATH + "Monk/idle_1.png",
		"hd":     "d8 Hit Die",
		"desc":   "Master of\nmartial arts.",
		"color":  Color(0.60, 0.90, 1.00),
		"info": {
			"primary_ability": "DEX",
			"hit_die": "d8",
			"check_profs": "STR, DEX",
			"weapon_profs": "Simple, Martial (Light)",
			"armor_training": "None",
			"starting_equipment": "",
		},
	},
	{
		"cls":    11,  # Stats.CharacterClass.WARLOCK
		"name":   "Warlock",
		"sprite": CHAR_PATH + "Warlock/idle_1.png",
		"hd":     "d8 Hit Die",
		"desc":   "Wields eldritch\npower through a pact.",
		"color":  Color(0.65, 0.35, 0.85),
		"info": {
			"primary_ability": "CHA",
			"hit_die": "d8",
			"check_profs": "WIS, CHA",
			"weapon_profs": "Simple",
			"armor_training": "Light",
			"starting_equipment": "",
		},
	},
	{
		"cls":    7,  # Stats.CharacterClass.FIGHTER
		"name":   "Fighter",
		"sprite": CHAR_PATH + "Fighter/idle_1.png",
		"hd":     "d10 Hit Die",
		"desc":   "Versatile master\nof weapons and armor.",
		"color":  Color(0.75, 0.75, 0.80),
		"info": {
			"primary_ability": "STR or DEX",
			"hit_die": "d10",
			"check_profs": "STR, CON",
			"weapon_profs": "Simple, Martial",
			"armor_training": "Light, Medium, Heavy, Shields",
			"starting_equipment": "",
		},
	},
]

# Classes with no implementation yet — shown as locked silhouette tiles so the
# grid reads as the full 5e class roster and new classes can slot in later.
const LOCKED_CLASSES: Array = [
	"Bard", "Cleric", "Druid",
	"Paladin", "Rogue", "Sorcerer",
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
	var total_count: int = CLASS_DATA.size() + 1 + LOCKED_CLASSES.size()  # +1 for the Random tile
	var rows: int = ceili(float(total_count) / float(GRID_COLUMNS))
	var total_w: float = GRID_COLUMNS * TILE_SIZE + (GRID_COLUMNS - 1) * TILE_GAP
	var total_h: float = rows * TILE_SIZE + (rows - 1) * TILE_GAP
	var origin_x: float = (vp.x - total_w) / 2.0
	var origin_y: float = (vp.y - total_h) / 2.0

	var title := Label.new()
	title.text = "Choose Your Class"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, origin_y - 64.0)
	title.size = Vector2(vp.x, 36.0)
	add_child(title)

	var sub := Label.new()
	sub.text = "Click a tile to begin your descent"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.44))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, origin_y - 28.0)
	sub.size = Vector2(vp.x, 18.0)
	add_child(sub)

	var idx: int = 0
	for data: Dictionary in CLASS_DATA:
		var col: int = idx % GRID_COLUMNS
		var row: int = idx / GRID_COLUMNS
		var pos := Vector2(origin_x + col * (TILE_SIZE + TILE_GAP), origin_y + row * (TILE_SIZE + TILE_GAP))
		_build_card(data, pos)
		idx += 1
	var random_pos := Vector2(origin_x + (idx % GRID_COLUMNS) * (TILE_SIZE + TILE_GAP), origin_y + (idx / GRID_COLUMNS) * (TILE_SIZE + TILE_GAP))
	_build_random_card(random_pos)
	idx += 1
	for locked_name: String in LOCKED_CLASSES:
		var col: int = idx % GRID_COLUMNS
		var row: int = idx / GRID_COLUMNS
		var pos := Vector2(origin_x + col * (TILE_SIZE + TILE_GAP), origin_y + row * (TILE_SIZE + TILE_GAP))
		_build_locked_card(locked_name, pos)
		idx += 1

func _build_card(data: Dictionary, pos: Vector2) -> void:
	var card := Button.new()
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.position = pos
	card.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	card.size = Vector2(TILE_SIZE, TILE_SIZE)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.09, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = (data["color"] as Color) * 0.7
	sbox.set_corner_radius_all(6)
	var sbox_hover := StyleBoxFlat.new()
	sbox_hover.bg_color = Color(0.13, 0.13, 0.18, 0.97)
	sbox_hover.set_border_width_all(2)
	sbox_hover.border_color = data["color"] as Color
	sbox_hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("normal", sbox)
	card.add_theme_stylebox_override("hover", sbox_hover)
	card.add_theme_stylebox_override("pressed", sbox_hover)
	card.pressed.connect(_on_class_selected.bind(data["cls"] as int))
	add_child(card)

	var icon := TextureRect.new()
	var sprite_path: String = data["sprite"]
	if ResourceLoader.exists(sprite_path):
		icon.texture = load(sprite_path)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.ignore_texture_size = true
	icon.position = Vector2(float(TILE_SIZE) / 2.0 - 32.0, 12.0)
	icon.size = Vector2(64.0, 64.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", data["color"])
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(4.0, 80.0)
	name_lbl.size = Vector2(TILE_SIZE - 8.0, 20.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var hd_lbl := Label.new()
	hd_lbl.text = data["hd"]
	hd_lbl.add_theme_font_size_override("font_size", 11)
	hd_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	hd_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	hd_lbl.position = Vector2(4.0, 100.0)
	hd_lbl.size = Vector2(TILE_SIZE - 8.0, 16.0)
	hd_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(hd_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(8.0, 122.0)
	desc_lbl.size = Vector2(TILE_SIZE - 16.0, 42.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	if data.has("info"):
		_build_info_icon(card, data["info"] as Dictionary)

const INFO_ICON_SIZE: float = 20.0

# Small "i" badge, top-right corner of a class tile — hovering shows the class's proficiency
# block via Godot's built-in Control tooltip (plain text, "\n"-separated, no custom popup code
# needed). mouse_filter = STOP (Godot's Control default) is deliberate here, unlike every other
# decorative child on the tile (which use MOUSE_FILTER_IGNORE to let clicks fall through to the
# card Button underneath) — this one both enables hover-tooltip detection AND intentionally
# swallows a click so tapping the icon can never accidentally select the class.
func _build_info_icon(card: Control, info: Dictionary) -> void:
	var icon := Button.new()
	icon.text = "i"
	icon.focus_mode = Control.FOCUS_NONE
	icon.position = Vector2(TILE_SIZE - INFO_ICON_SIZE - 4.0, 4.0)
	icon.size = Vector2(INFO_ICON_SIZE, INFO_ICON_SIZE)
	icon.add_theme_font_size_override("font_size", 13)
	icon.tooltip_text = _format_class_info_tooltip(info)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.15, 0.15, 0.20, 0.9)
	sbox.set_border_width_all(1)
	sbox.border_color = Color(0.55, 0.55, 0.62)
	sbox.set_corner_radius_all(int(INFO_ICON_SIZE / 2.0))
	icon.add_theme_stylebox_override("normal", sbox)
	var sbox_hover := StyleBoxFlat.new()
	sbox_hover.bg_color = Color(0.25, 0.25, 0.32, 0.95)
	sbox_hover.set_border_width_all(1)
	sbox_hover.border_color = Color(0.85, 0.85, 0.92)
	sbox_hover.set_corner_radius_all(int(INFO_ICON_SIZE / 2.0))
	icon.add_theme_stylebox_override("hover", sbox_hover)
	icon.add_theme_stylebox_override("pressed", sbox_hover)
	card.add_child(icon)

func _format_class_info_tooltip(info: Dictionary) -> String:
	var starting_equipment: String = info.get("starting_equipment", "")
	if starting_equipment == "":
		starting_equipment = "TBD"
	return "Primary Ability: %s\nHit Point Die: %s\nCheck Proficiencies: %s\nWeapon Proficiencies: %s\nArmor Training: %s\nStarting Equipment: %s" % [
		info.get("primary_ability", "?"),
		info.get("hit_die", "?"),
		info.get("check_profs", "?"),
		info.get("weapon_profs", "?"),
		info.get("armor_training", "?"),
		starting_equipment,
	]

const RANDOM_COLOR := Color(0.75, 0.55, 0.90)

# A real, clickable tile (not a locked placeholder) that rolls a random class from CLASS_DATA
# and feeds it straight into the exact same _on_class_selected() every normal tile uses — so
# picking Random still walks the full point-buy/background/race/mastery Custom flow, it just
# skips having to click a specific class tile first (per direct owner correction: Random must
# NOT bypass those screens the way a premade hero on character_select.gd does).
func _build_random_card(pos: Vector2) -> void:
	var card := Button.new()
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.position = pos
	card.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	card.size = Vector2(TILE_SIZE, TILE_SIZE)
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.09, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = RANDOM_COLOR * 0.7
	sbox.set_corner_radius_all(6)
	var sbox_hover := StyleBoxFlat.new()
	sbox_hover.bg_color = Color(0.13, 0.13, 0.18, 0.97)
	sbox_hover.set_border_width_all(2)
	sbox_hover.border_color = RANDOM_COLOR
	sbox_hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("normal", sbox)
	card.add_theme_stylebox_override("hover", sbox_hover)
	card.add_theme_stylebox_override("pressed", sbox_hover)
	card.pressed.connect(_on_random_selected)
	add_child(card)

	var icon_lbl := Label.new()
	icon_lbl.text = "🎲"
	icon_lbl.add_theme_font_size_override("font_size", 40)
	icon_lbl.add_theme_color_override("font_color", RANDOM_COLOR)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(float(TILE_SIZE) / 2.0 - 32.0, 8.0)
	icon_lbl.size = Vector2(64.0, 68.0)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = "Random"
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", RANDOM_COLOR)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(4.0, 80.0)
	name_lbl.size = Vector2(TILE_SIZE - 8.0, 20.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "Roll a random class,\nthen build the rest\nyourself as usual."
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(8.0, 100.0)
	desc_lbl.size = Vector2(TILE_SIZE - 16.0, 64.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

func _on_random_selected() -> void:
	var picked: Dictionary = CLASS_DATA[randi() % CLASS_DATA.size()]
	_on_class_selected(picked["cls"] as int)

func _build_locked_card(class_name_str: String, pos: Vector2) -> void:
	var card := Panel.new()
	card.position = pos
	card.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	card.size = Vector2(TILE_SIZE, TILE_SIZE)
	card.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.07, 0.08, 0.85)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.28, 0.28, 0.30)
	sbox.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sbox)
	add_child(card)

	# A locked class with art already sourced (folder matches class_name_str, see root CLAUDE.md's
	# Sprite Assets naming convention) shows a dimmed portrait instead of the "?" glyph — still
	# non-interactive/"Coming Soon", just reads as "art ready, mechanics aren't" rather than fully
	# empty. Falls back to "?" for any locked class with no folder yet (currently Paladin, Sorcerer).
	var sprite_path: String = CHAR_PATH + class_name_str + "/idle_1.png"
	if ResourceLoader.exists(sprite_path):
		var portrait := TextureRect.new()
		portrait.texture = load(sprite_path)
		portrait.ignore_texture_size = true
		portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		portrait.position = Vector2(float(TILE_SIZE) / 2.0 - 32.0, 8.0)
		portrait.size = Vector2(64.0, 68.0)
		portrait.modulate = Color(0.55, 0.55, 0.55, 0.85)
		portrait.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(portrait)
	else:
		var silhouette := Label.new()
		silhouette.text = "?"
		silhouette.add_theme_font_size_override("font_size", 40)
		silhouette.add_theme_color_override("font_color", Color(0.30, 0.30, 0.32))
		silhouette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		silhouette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		silhouette.position = Vector2(float(TILE_SIZE) / 2.0 - 32.0, 8.0)
		silhouette.size = Vector2(64.0, 68.0)
		silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(silhouette)

	var name_lbl := Label.new()
	name_lbl.text = class_name_str
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.47))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(4.0, 80.0)
	name_lbl.size = Vector2(TILE_SIZE - 8.0, 20.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var soon_lbl := Label.new()
	soon_lbl.text = "Coming Soon"
	soon_lbl.add_theme_font_size_override("font_size", 11)
	soon_lbl.add_theme_color_override("font_color", Color(0.38, 0.38, 0.40))
	soon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	soon_lbl.position = Vector2(4.0, 100.0)
	soon_lbl.size = Vector2(TILE_SIZE - 8.0, 16.0)
	soon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(soon_lbl)

func _on_class_selected(cls_idx: int) -> void:
	# reset_for_class_reselect() wipes any gear/abilities/talents from a PREVIOUS class pick this
	# same Custom flow (Back navigation lets the player return here and pick a different class) —
	# see scripts/autoloads/CLAUDE.md. Safe/idempotent on a first-ever pick too.
	GameState.reset_for_class_reselect()
	GameState.player_stats.character_class = cls_idx as Stats.CharacterClass
	GameState.player_stats.apply_class_defaults()
	GameState.give_class_starting_items()
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	# class_selected is NOT set here anymore — the Custom flow keeps player input blocked until
	# character_summary.gd's final "Yes" confirm. class_chosen still fires so the HUD portrait/
	# sprite previews correctly during onboarding (SaveManager's checkpoint on this signal is a
	# no-op while class_selected is false, so nothing saves prematurely).
	GameState.class_chosen.emit(GameState.player_stats.character_class)
	var point_buy_picker = load("res://scripts/ui/point_buy_select.gd").new()
	get_tree().root.call_deferred("add_child", point_buy_picker)
	queue_free()
