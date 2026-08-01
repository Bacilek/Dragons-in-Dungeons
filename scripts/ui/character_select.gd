extends CanvasLayer

# Character select overlay — the very first screen of a new run. Shown instead of
# class_select.gd (hud.gd now spawns this one). Offers 5 side-by-side options: 4 premade
# characters (fixed class + race + weapon masteries, spawn straight into the dungeon on
# click) and a 5th "Custom" option that hands off to the existing class_select.gd ->
# race_select.gd -> mastery_picker.gd chain unchanged. (The "Random" option lives one step
# further in, on class_select.gd's own class grid — see that file — since randomizing
# should still walk through the full Custom point-buy/background/race/mastery flow, not
# bypass it like a premade hero does.)

const CARD_W: int = 260
const CARD_H: int = 460
const CARD_GAP: int = 20
const CHAR_PATH := "res://sprites/characters/classes/"

var _continue_btn: Button = null

const PREMADE: Array = [
	{
		"name":    "Garrem Ogar",
		"cls":     Stats.CharacterClass.BARBARIAN,
		"race":    Stats.CharacterRace.ORC,
		"variant": 0,
		"prof":    -1,
		"masteries": ["Cleave", "Graze"],
		"scores":  {"str": 16, "dex": 14, "con": 16, "int": 8, "wis": 10, "cha": 10},
		"sprite":  CHAR_PATH + "Barbarian/idle_1.png",
		"subtitle": "Orc Barbarian",
		"desc":    "A raging orc warrior.\nMasteries: Cleave, Graze.",
		"color":   Color(0.90, 0.60, 0.20),
	},
	{
		"name":    "Tish",
		"cls":     Stats.CharacterClass.RANGER,
		"race":    Stats.CharacterRace.ELF,
		"variant": Stats.ElfSubrace.WOOD_ELF,
		"prof":    -1,
		"masteries": ["Slow", "Nick"],
		"scores":  {"str": 8, "dex": 16, "con": 14, "int": 10, "wis": 16, "cha": 10},
		"spell1":  "fog_cloud",
		"sprite":  CHAR_PATH + "Ranger/idle_1.png",
		"subtitle": "Wood Elf Ranger",
		"desc":    "A swift hunter of the wilds.\nMasteries: Slow, Nick.",
		"color":   Color(0.50, 0.85, 0.50),
	},
	{
		"name":    "Grok the White",
		"cls":     Stats.CharacterClass.MONK,
		"race":    Stats.CharacterRace.DRAGONBORN,
		"variant": Stats.DragonbornAncestry.WHITE,
		"prof":    -1,
		"masteries": [],
		"scores":  {"str": 10, "dex": 16, "con": 16, "int": 8, "wis": 14, "cha": 10},
		"sprite":  CHAR_PATH + "Monk/idle_1.png",
		"subtitle": "White Dragonborn Monk",
		"desc":    "A martial artist with\ncold-resistant scales.",
		"color":   Color(0.60, 0.90, 1.00),
	},
	{
		"name":    "Jace",
		"cls":     Stats.CharacterClass.WIZARD,
		"race":    Stats.CharacterRace.HALFLING,
		"variant": 0,
		"prof":    -1,
		"masteries": [],
		"scores":  {"str": 8, "dex": 14, "con": 16, "int": 16, "wis": 10, "cha": 10},
		"cantrip": "fire_bolt",
		"spell1":  "magic_missile",
		"sprite":  CHAR_PATH + "Wizard/idle_1.png",
		"subtitle": "Halfling Wizard",
		"desc":    "Frail but brilliant,\nlucky in a pinch.",
		"color":   Color(0.50, 0.65, 1.00),
	},
	{
		"name":    "Lil Dorruk",
		"cls":     Stats.CharacterClass.WARLOCK,
		"race":    Stats.CharacterRace.GOLIATH,
		"variant": Stats.GiantAncestry.FIRE,
		"prof":    -1,
		"masteries": [],
		"scores":  {"str": 10, "dex": 14, "con": 16, "int": 8, "wis": 10, "cha": 16},
		"cantrip": "eldritch_blast",
		"spell1":  "mage_armor",
		"sprite":  CHAR_PATH + "Warlock/idle_1.png",
		"subtitle": "Fire Goliath Warlock",
		"desc":    "Small name, big blasts.\nEldritch Blast and a Fire Giant's heart.",
		"color":   Color(0.90, 0.45, 0.25),
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
	var count: int = PREMADE.size() + 1
	var total_w: float = count * CARD_W + (count - 1) * CARD_GAP
	var origin_x: float = (vp.x - total_w) / 2.0
	var origin_y: float = (vp.y - CARD_H) / 2.0

	var title := Label.new()
	title.text = "Choose Your Character"
	title.add_theme_font_size_override("font_size", 22)
	title.add_theme_color_override("font_color", Color(0.95, 0.85, 0.50))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(0.0, origin_y - 64.0)
	title.size = Vector2(vp.x, 36.0)
	add_child(title)

	var sub := Label.new()
	sub.text = "Pick a hero, or build your own"
	sub.add_theme_font_size_override("font_size", 11)
	sub.add_theme_color_override("font_color", Color(0.55, 0.52, 0.44))
	sub.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	sub.position = Vector2(0.0, origin_y - 28.0)
	sub.size = Vector2(vp.x, 18.0)
	add_child(sub)

	for i: int in PREMADE.size():
		_build_premade_card(PREMADE[i], Vector2(origin_x + i * (CARD_W + CARD_GAP), origin_y))

	_build_custom_card(Vector2(origin_x + PREMADE.size() * (CARD_W + CARD_GAP), origin_y))

	if SaveManager.has_save():
		_build_continue_button(vp, origin_y)

func _build_continue_button(vp: Vector2, origin_y: float) -> void:
	var btn := Button.new()
	btn.text = "Continue Saved Run"
	btn.focus_mode = Control.FOCUS_NONE
	btn.position = Vector2(vp.x / 2.0 - 130.0, origin_y + CARD_H + 16.0)
	btn.size = Vector2(260.0, 36.0)
	var gold := Color(0.95, 0.85, 0.50)
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = gold * 0.30
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = gold * 0.8
	btn_normal.set_corner_radius_all(4)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = gold * 0.50
	btn_hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover", btn_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_font_size_override("font_size", 14)
	btn.pressed.connect(_on_continue_pressed)
	add_child(btn)
	_continue_btn = btn

func _on_continue_pressed() -> void:
	if not SaveManager.load_run():
		GameState.game_log("[color=gray]Saved run could not be loaded.[/color]")
		if _continue_btn != null:
			_continue_btn.visible = false
		return
	GameState.class_chosen.emit(GameState.player_stats.character_class)
	var df := get_tree().get_first_node_in_group("dungeon_floor") as DungeonFloor
	if df != null:
		df.reload_from_save()
	queue_free()

func _build_premade_card(data: Dictionary, pos: Vector2) -> void:
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

	var subtitle_lbl := Label.new()
	subtitle_lbl.text = data["subtitle"]
	subtitle_lbl.add_theme_font_size_override("font_size", 13)
	subtitle_lbl.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	subtitle_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	subtitle_lbl.position = Vector2(0.0, 156.0)
	subtitle_lbl.size = Vector2(CARD_W, 18.0)
	subtitle_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(subtitle_lbl)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 182.0)
	sep.size = Vector2(CARD_W - 24.0, 2.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep)

	var desc_lbl := Label.new()
	desc_lbl.text = data["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(10.0, 194.0)
	desc_lbl.size = Vector2(CARD_W - 20.0, 100.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	var s: Stats = _make_stats(data["cls"] as Stats.CharacterClass, data.get("scores") as Dictionary)
	var stat_rows: Array = [
		["STR", s.strength,     s.str_modifier()],
		["DEX", s.dexterity,    s.dex_modifier()],
		["CON", s.constitution, s.con_modifier()],
		["INT", s.intelligence, s.int_modifier()],
		["WIS", s.wisdom,       s.wis_modifier()],
		["CHA", s.charisma,     s.cha_modifier()],
	]
	var grid_top := 300.0
	var col_w := (float(CARD_W) - 24.0) / 2.0
	var row_h := 32.0
	for i: int in stat_rows.size():
		var col: int = i % 2
		var row: int = i / 2
		var pos := Vector2(12.0 + col * col_w, grid_top + row * row_h)
		var size := Vector2(col_w - 6.0, row_h - 6.0)
		_add_stat_chip(card, pos, size, stat_rows[i][0], stat_rows[i][1], stat_rows[i][2], data["color"])

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, grid_top + 3.0 * row_h + 4.0)
	sep2.size = Vector2(CARD_W - 24.0, 2.0)
	sep2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(sep2)

	var btn := Button.new()
	btn.text = "Play " + (data["name"] as String)
	btn.position = Vector2(20.0, grid_top + 3.0 * row_h + 14.0)
	btn.size = Vector2(CARD_W - 40.0, 28.0)
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
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_premade_selected.bind(data))
	card.add_child(btn)

func _build_custom_card(pos: Vector2) -> void:
	var color := Color(0.75, 0.75, 0.80)
	var card := Panel.new()
	card.position = pos
	card.custom_minimum_size = Vector2(CARD_W, CARD_H)
	card.size = Vector2(CARD_W, CARD_H)
	card.mouse_filter = Control.MOUSE_FILTER_STOP
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.09, 0.09, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = color * 0.7
	sbox.set_corner_radius_all(6)
	card.add_theme_stylebox_override("panel", sbox)
	add_child(card)

	var icon_lbl := Label.new()
	icon_lbl.text = "?"
	icon_lbl.add_theme_font_size_override("font_size", 64)
	icon_lbl.add_theme_color_override("font_color", color)
	icon_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	icon_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	icon_lbl.position = Vector2(0.0, 18.0)
	icon_lbl.size = Vector2(CARD_W, 100.0)
	icon_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon_lbl)

	var name_lbl := Label.new()
	name_lbl.text = "Custom"
	name_lbl.add_theme_font_size_override("font_size", 18)
	name_lbl.add_theme_color_override("font_color", color)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(0.0, 124.0)
	name_lbl.size = Vector2(CARD_W, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = "Build your own hero:\nchoose a class, a race,\nand your weapon masteries."
	desc_lbl.add_theme_font_size_override("font_size", 13)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(10.0, 194.0)
	desc_lbl.size = Vector2(CARD_W - 20.0, 200.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	var btn := Button.new()
	btn.text = "Create Custom"
	btn.position = Vector2(20.0, 428.0)
	btn.size = Vector2(CARD_W - 40.0, 28.0)
	var btn_normal := StyleBoxFlat.new()
	btn_normal.bg_color = color * 0.35
	btn_normal.set_border_width_all(1)
	btn_normal.border_color = color * 0.8
	btn_normal.set_corner_radius_all(4)
	var btn_hover := StyleBoxFlat.new()
	btn_hover.bg_color = color * 0.55
	btn_hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", btn_normal)
	btn.add_theme_stylebox_override("hover",  btn_hover)
	btn.add_theme_color_override("font_color", Color(1.0, 1.0, 1.0))
	btn.add_theme_font_size_override("font_size", 13)
	btn.focus_mode = Control.FOCUS_NONE
	btn.pressed.connect(_on_custom_selected)
	card.add_child(btn)

func _make_stats(cls_idx: Stats.CharacterClass, scores: Dictionary) -> Stats:
	var s := Stats.new()
	s.character_class = cls_idx
	s.apply_class_defaults()
	if not scores.is_empty():
		s.apply_point_buy_scores(scores)
	return s

# Single-row "chip": stat abbreviation left-aligned, "score (+mod)" right-aligned, both
# vertically centered inside a faint bordered box — replaces the old single-column stat rows,
# which were unevenly spaced and didn't visually group into anything.
func _add_stat_chip(parent: Control, pos: Vector2, size: Vector2, stat_name: String, score: int, mod_val: int, accent: Color) -> void:
	var chip := Panel.new()
	chip.position = pos
	chip.size = size
	chip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(1.0, 1.0, 1.0, 0.04)
	sbox.set_border_width_all(1)
	sbox.border_color = accent * 0.4
	sbox.set_corner_radius_all(4)
	chip.add_theme_stylebox_override("panel", sbox)
	parent.add_child(chip)

	var name_lbl := Label.new()
	name_lbl.text = stat_name
	name_lbl.position = Vector2(8.0, 0.0)
	name_lbl.size = Vector2(36.0, size.y)
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	name_lbl.add_theme_font_size_override("font_size", 12)
	name_lbl.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(name_lbl)

	var value_lbl := Label.new()
	value_lbl.text = "%d (%+d)" % [score, mod_val]
	value_lbl.position = Vector2(0.0, 0.0)
	value_lbl.size = Vector2(size.x - 8.0, size.y)
	value_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_RIGHT
	value_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	value_lbl.add_theme_font_size_override("font_size", 13)
	var mod_color: Color
	if mod_val > 0:   mod_color = Color(0.40, 0.85, 0.45)
	elif mod_val < 0: mod_color = Color(0.85, 0.38, 0.32)
	else:             mod_color = Color(0.85, 0.83, 0.78)
	value_lbl.add_theme_color_override("font_color", mod_color)
	value_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	chip.add_child(value_lbl)

# Bypasses class_select -> race_select -> mastery_picker entirely: applies class, race, and
# (for Barbarian/Ranger) a fixed weapon-mastery loadout directly, mirroring exactly what each
# of those three screens would otherwise do on confirm.
func _on_premade_selected(data: Dictionary) -> void:
	GameState.player_stats.character_class = data["cls"] as Stats.CharacterClass
	GameState.player_stats.apply_class_defaults()
	var scores: Variant = data.get("scores")
	if scores != null:
		GameState.player_stats.apply_point_buy_scores(scores as Dictionary)
	GameState.give_class_starting_items()
	GameState.class_selected = true
	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.class_chosen.emit(GameState.player_stats.character_class)

	GameState.choose_race(data["race"] as Stats.CharacterRace, data["variant"] as int, data["prof"] as int)

	var masteries: Array = data["masteries"]
	if not masteries.is_empty():
		GameState.player_stats.known_weapon_masteries.clear()
		for m: Variant in masteries:
			GameState.player_stats.known_weapon_masteries.append(String(m))
		GameState.known_masteries_changed.emit()

	var cantrip: String = String(data.get("cantrip", ""))
	if not cantrip.is_empty():
		GameState.choose_cantrip(cantrip)   # also auto-assigns it to the Special quick-cast slot

	var spell1: String = String(data.get("spell1", ""))
	if not spell1.is_empty():
		GameState.choose_starting_spell(spell1)

	GameState.snapshot_character_creation()
	queue_free()

func _on_custom_selected() -> void:
	var cs_picker = load("res://scripts/ui/class_select.gd").new()
	get_tree().root.call_deferred("add_child", cs_picker)
	queue_free()
