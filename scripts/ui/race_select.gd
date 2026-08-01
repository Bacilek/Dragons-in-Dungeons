extends CanvasLayer

# Race-select overlay — one-time, mandatory choice spawned by background_select.gd's confirm
# (Custom path: class select -> point buy -> background ASI -> race select -> mastery picker),
# before the Mastery Picker. Blocks input via a GameState flag (race_picker_open), NOT
# dismissible (no close button, Esc ignored) — the choice is permanent.
# Implemented; design doc shipped and was deleted — root CLAUDE.md's "Race system" and
# scripts/entities/CLAUDE.md's "Dragonborn" section are now authoritative.
#
# Tile-grid layout mirrors class_select.gd: square icon tiles (icons/races/<id>.png) with a name,
# a short one-line flavor blurb, and a hover "i" info badge (top-right, native Control.tooltip_text)
# showing the race's full mechanical rundown. Races with a sub-choice (subrace/ancestry/legacy/
# ability score/gnome lineage+stat/giant ancestry) reveal a shared sub-choice button row BELOW the
# grid once selected — a small tile has no room for inline sub-buttons the way the old wide
# description cards did.

const PANEL_W: float = 962.0
const MARGIN: float = 24.0
const TILE_SIZE: float = 170.0
const TILE_GAP: float = 16.0
const GRID_COLUMNS: int = 5
const SUB_BTN_H: float = 30.0
const SUB_PER_ROW: int = 5
const ICON_PATH := "res://icons/races/"  # portrait at <ICON_PATH><id>/portrait.png

# id → {name, short_desc (2-line tile flavor), blurb (full mechanical rundown, "i" tooltip),
# color}. Sub-choice races additionally carry "sub_kind" + "sub_options".
const RACES: Array[Dictionary] = [
	{
		"id": "orc", "name": "Orc", "color": Color(0.55, 0.78, 0.35),
		"short_desc": "Relentless survivor,\nunstoppable in a rage.",
		"blurb": "Relentless Endurance holds you at 1 HP once per long rest. Adrenaline Rush: temp HP + a free move, proficiency-bonus uses per short/long rest. Superior darkvision.",
	},
	{
		"id": "human", "name": "Human", "color": Color(0.85, 0.75, 0.55),
		"short_desc": "Adaptable and\nheroic under pressure.",
		"blurb": "Heroic Inspiration guarantees your next roll critically succeeds, once per long rest. Choose one bonus ability proficiency. No darkvision.",
		"sub_kind": "ability score", "sub_options": ["STR", "DEX", "CON", "INT", "WIS", "CHA"],
	},
	{
		"id": "halfling", "name": "Halfling", "color": Color(0.95, 0.78, 0.35),
		"short_desc": "Small, lucky,\nand hard to pin down.",
		"blurb": "Small, Speed 1. Luck: automatically reroll a natural 1, keeping the new result. Brave: ADV on saves to avoid/end Frightened. Halfling Nimbleness: can move through a larger creature's space. No darkvision.",
	},
	{
		"id": "dwarf", "name": "Dwarf", "color": Color(0.80, 0.55, 0.30),
		"short_desc": "Sturdy stonekin,\ntough as their homeland.",
		"blurb": "+1 max HP every level. Poison resistance. Stonecunning: Tremorsense buff senses nearby creatures through walls/darkness. Superior darkvision.",
	},
	{
		"id": "elf", "name": "Elf", "color": Color(0.55, 0.85, 0.75),
		"short_desc": "Graceful and keen,\nborn for magic.",
		"blurb": "Keen Senses (WIS proficiency), Fey Ancestry (ADV vs. Charmed), shorter long rests, darkvision. Elven Lineage grants a spell at level 3 and 5 (Drow: Faerie Fire/Darkness. High Elf: Detect Magic/Misty Step + a long-rest cantrip swap. Wood Elf: 35ft speed + Longstrider/Pass Without Trace) — each free once per long rest. Choose a sub-race.",
		"sub_kind": "subrace", "sub_options": ["Drow", "High Elf", "Wood Elf"],
	},
	{
		"id": "dragonborn", "name": "Dragonborn", "color": Color(0.90, 0.40, 0.30),
		"short_desc": "Draconic pride,\nbreathes elemental fury.",
		"blurb": "Choose an ancestry for elemental resistance + a Breath Weapon (Cone/Line, same damage type). Draconic Flight at level 5. Darkvision.",
		"sub_kind": "ancestry", "sub_options": ["Black", "Blue", "Brass", "Bronze", "Copper", "Gold", "Green", "Red", "Silver", "White"],
	},
	{
		"id": "tiefling", "name": "Tiefling", "color": Color(0.75, 0.35, 0.60),
		"short_desc": "Fiendish heritage,\nwields infernal power.",
		"blurb": "Choose a Fiendish Legacy for a damage resistance + a free spell at levels 1/3/5 (cast with your best of INT/WIS/CHA, free once per long rest then via spell slots). Abyssal: Poison resist, Poison Spray/Ray of Sickness/Hold Person. Chthonic: Necrotic resist, Chill Touch/False Life/Ray of Enfeeblement. Infernal: Fire resist, Fire Bolt/Hellish Rebuke/Darkness. Darkvision.",
		"sub_kind": "legacy", "sub_options": ["Abyssal", "Chthonic", "Infernal"],
	},
	{
		"id": "aasimar", "name": "Aasimar", "color": Color(0.95, 0.90, 0.55),
		"short_desc": "Touched by the\ncelestial planes.",
		"blurb": "Celestial Resistance (Necrotic + Radiant). Healing Hands: touch-heal 1d4×prof HP, costs your action, once per long rest. Light Bearer: know the Light cantrip. Celestial Revelation (from level 3): once per long rest, choose Heavenly Wings/Inner Radiance/Necrotic Shroud for 10 turns — first damage each turn deals bonus Radiant/Necrotic. Darkvision.",
	},
	{
		"id": "gnome", "name": "Gnome", "color": Color(0.55, 0.80, 0.95),
		"short_desc": "Small, clever,\nendlessly curious.",
		"blurb": "Gnomish Cunning: ADV on saves with the ONE of INT/WIS/CHA you choose. Gnomish Lineage: Forest Gnome knows Minor Illusion + Speak with Animals; Rock Gnome knows Mending — each castable proficiency-bonus times for free per long rest. Darkvision. Choose a lineage + your Cunning stat.",
		"sub_kind": "gnome", "sub_options": ["Forest (INT)", "Forest (WIS)", "Forest (CHA)", "Rock (INT)", "Rock (WIS)", "Rock (CHA)"],
	},
	{
		"id": "goliath", "name": "Goliath", "color": Color(0.68, 0.68, 0.72),
		"short_desc": "Towering strength\nof mountain-born giants.",
		"blurb": "Large Form (from level 5): grow to a 2x2 giant for up to 100 turns in a big enough space — ADV on STR checks, +1/3 speed — once per long rest. Powerful Build: ADV to end Grappled (not yet wired). Choose a Giant Ancestry for a proficiency-bonus-per-long-rest activatable: Cloud (short teleport), Fire (bonus Fire dmg), Frost (chill/slow on hit), Hill (Prone on hit), Stone (reduce next hit taken), Storm (reflect Thunder dmg). No darkvision.",
		"sub_kind": "giant_ancestry", "sub_options": ["Cloud", "Fire", "Frost", "Hill", "Stone", "Storm"],
	},
]

var _selected_id: String = ""
var _selected_sub: int = -1
var _card_btns: Dictionary = {}         # race id → Button (tile)
var _current_sub_btns: Array[Button] = []
var _sub_label: Label
var _sub_container: Control
var _confirm_btn: Button
var _back_btn: Button
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

	_back_btn = Button.new()
	_back_btn.text = "← Back"
	_back_btn.size = Vector2(90.0, 28.0)
	_back_btn.position = Vector2(PANEL_W - MARGIN - 90.0, 16.0)
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.add_theme_font_size_override("font_size", 13)
	_style_btn(_back_btn, Color(0.14, 0.12, 0.10), Color(0.5, 0.45, 0.35))
	_back_btn.pressed.connect(_on_back)
	_panel.add_child(_back_btn)

	var hint := Label.new()
	hint.text = "This choice is permanent. Hover the (i) badge on a tile for full details."
	hint.add_theme_font_size_override("font_size", 13)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(PANEL_W - MARGIN * 2.0, 24.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 80.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 92.0
	var rows: int = ceili(float(RACES.size()) / float(GRID_COLUMNS))
	for i: int in RACES.size():
		var col: int = i % GRID_COLUMNS
		var row: int = i / GRID_COLUMNS
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_build_tile(RACES[i], pos)
	var grid_h: float = float(rows) * TILE_SIZE + float(rows - 1) * TILE_GAP

	var sub_y: float = y0 + grid_h + 20.0
	_sub_label = Label.new()
	_sub_label.add_theme_font_size_override("font_size", 14)
	_sub_label.add_theme_color_override("font_color", Color(0.85, 0.85, 0.90))
	_sub_label.position = Vector2(MARGIN, sub_y)
	_sub_label.size = Vector2(PANEL_W - MARGIN * 2.0, 22.0)
	_sub_label.visible = false
	_panel.add_child(_sub_label)

	_sub_container = Control.new()
	_sub_container.position = Vector2(MARGIN, sub_y + 26.0)
	_sub_container.size = Vector2(PANEL_W - MARGIN * 2.0, SUB_BTN_H * 2.0 + 6.0)
	_panel.add_child(_sub_container)
	var sub_area_h: float = 26.0 + SUB_BTN_H * 2.0 + 6.0

	var confirm_y: float = sub_y + sub_area_h + 14.0
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

func _build_tile(data: Dictionary, pos: Vector2) -> void:
	var race_id: String = data["id"]
	var accent: Color = data["color"]
	var card := Button.new()
	card.flat = true
	card.focus_mode = Control.FOCUS_NONE
	card.position = pos
	card.custom_minimum_size = Vector2(TILE_SIZE, TILE_SIZE)
	card.size = Vector2(TILE_SIZE, TILE_SIZE)
	_apply_tile_style(card, accent, false)
	card.pressed.connect(func() -> void: _select(race_id))
	_card_btns[race_id] = card
	_panel.add_child(card)

	var icon := TextureRect.new()
	var icon_path: String = ICON_PATH + race_id + "/portrait.png"
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.ignore_texture_size = true
	icon.position = Vector2(TILE_SIZE / 2.0 - 32.0, 10.0)
	icon.size = Vector2(64.0, 64.0)
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(icon)
	if not ResourceLoader.exists(icon_path):
		var silhouette := Label.new()
		silhouette.text = "?"
		silhouette.add_theme_font_size_override("font_size", 34)
		silhouette.add_theme_color_override("font_color", Color(0.30, 0.30, 0.32))
		silhouette.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		silhouette.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
		silhouette.position = Vector2(TILE_SIZE / 2.0 - 32.0, 10.0)
		silhouette.size = Vector2(64.0, 64.0)
		silhouette.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(silhouette)

	var name_lbl := Label.new()
	name_lbl.text = data["name"]
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.add_theme_color_override("font_color", accent)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = Vector2(4.0, 78.0)
	name_lbl.size = Vector2(TILE_SIZE - 8.0, 20.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = data.get("short_desc", "")
	desc_lbl.add_theme_font_size_override("font_size", 11)
	desc_lbl.add_theme_color_override("font_color", Color(0.68, 0.68, 0.68))
	desc_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	desc_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	desc_lbl.position = Vector2(8.0, 100.0)
	desc_lbl.size = Vector2(TILE_SIZE - 16.0, 60.0)
	desc_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(desc_lbl)

	if data.has("sub_kind"):
		var badge := Label.new()
		badge.text = "choose…"
		badge.add_theme_font_size_override("font_size", 10)
		badge.add_theme_color_override("font_color", accent.darkened(0.1))
		badge.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
		badge.position = Vector2(4.0, TILE_SIZE - 18.0)
		badge.size = Vector2(TILE_SIZE - 8.0, 14.0)
		badge.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(badge)

	_build_info_icon(card, data["name"], data["blurb"])

const INFO_ICON_SIZE: float = 20.0

# Small "i" badge, top-right corner of a race tile — hovering shows the race's full mechanical
# rundown via Godot's built-in Control tooltip (plain text, no custom popup code needed).
# mouse_filter = STOP (Godot's Control default) is deliberate — swallows a click so tapping the
# badge can never accidentally select the race, mirrors class_select.gd's own info icon.
#
# BUGFIX: the native Control tooltip's default wrap width rendered these ~300-char blurbs as one
# barely-legible run-on line. Godot's tooltip has no font-size override hook worth fighting, so
# instead the text itself is hard-wrapped (word-wrapped to WRAP_COLS chars/line) before being
# handed to tooltip_text — forces multiple short, readable lines regardless of tooltip theme.
const WRAP_COLS: int = 46

func _build_info_icon(card: Control, race_name: String, blurb: String) -> void:
	var icon := Button.new()
	icon.text = "i"
	icon.focus_mode = Control.FOCUS_NONE
	icon.position = Vector2(TILE_SIZE - INFO_ICON_SIZE - 4.0, 4.0)
	icon.size = Vector2(INFO_ICON_SIZE, INFO_ICON_SIZE)
	icon.add_theme_font_size_override("font_size", 13)
	icon.tooltip_text = "%s\n\n%s" % [race_name, _wrap_text(blurb, WRAP_COLS)]
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

# Greedy word-wrap — breaks `text` into lines no longer than `cols` characters, only ever
# splitting on whitespace (a single word longer than `cols` is left intact, unbroken).
func _wrap_text(text: String, cols: int) -> String:
	var lines: Array[String] = []
	var line: String = ""
	for word: String in text.split(" "):
		if line == "":
			line = word
		elif line.length() + 1 + word.length() <= cols:
			line += " " + word
		else:
			lines.append(line)
			line = word
	if line != "":
		lines.append(line)
	return "\n".join(lines)

func _select(race_id: String) -> void:
	if _selected_id == race_id:
		return
	_selected_id = race_id
	_selected_sub = -1
	for id: String in _card_btns:
		_apply_tile_style(_card_btns[id], _race_data(id)["color"], id == race_id)

	for c: Node in _sub_container.get_children():
		c.queue_free()
	_current_sub_btns = []

	var data: Dictionary = _race_data(race_id)
	if data.has("sub_kind"):
		_sub_label.visible = true
		_sub_label.text = "Choose a %s:" % [data["sub_kind"]]
		var options: Array = data["sub_options"]
		var per_row: int = SUB_PER_ROW
		var btn_w: float = (_sub_container.size.x - TILE_GAP * float(per_row - 1)) / float(per_row)
		for i: int in options.size():
			var col: int = i % per_row
			var r: int = i / per_row
			var sub_btn := Button.new()
			sub_btn.text = options[i]
			sub_btn.focus_mode = Control.FOCUS_NONE
			sub_btn.size = Vector2(btn_w, SUB_BTN_H)
			sub_btn.position = Vector2(col * (btn_w + TILE_GAP), r * (SUB_BTN_H + 6.0))
			sub_btn.add_theme_font_size_override("font_size", 11)
			_style_btn(sub_btn, Color(0.12, 0.12, 0.18), Color(0.35, 0.35, 0.42))
			sub_btn.pressed.connect(_on_sub_selected.bind(race_id, i))
			_sub_container.add_child(sub_btn)
			_current_sub_btns.append(sub_btn)
		_confirm_btn.disabled = true
		_confirm_btn.text = "Choose a %s option…" % [data["sub_kind"]]
	else:
		_sub_label.visible = false
		_confirm_btn.disabled = false
		_confirm_btn.text = "Choose %s" % data["name"]

func _on_sub_selected(race_id: String, idx: int) -> void:
	if _selected_id != race_id:
		return
	_selected_sub = idx
	for i: int in _current_sub_btns.size():
		_apply_sub_btn_style(_current_sub_btns[i], i == idx)
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
		"ability score": prof_ability = _selected_sub
		"subrace", "ancestry", "legacy", "giant_ancestry": variant = _selected_sub
		"gnome":
			# 6 combined options ("Forest (INT)"..."Rock (CHA)") — decode into lineage
			# (Stats.GnomeLineage, 0=Forest/1=Rock) + Gnomish Cunning stat, reusing the same
			# STR=0..CHA=5 race_prof_ability index Human's own ability pick uses (3=INT/4=WIS/5=CHA)
			# rather than adding a second serialized field — see scripts/entities/CLAUDE.md's "Gnome".
			variant = _selected_sub / 3
			prof_ability = 3 + (_selected_sub % 3)
	GameState.race_picker_open = false
	GameState.choose_race(race, variant, prof_ability)
	if GameState.player_stats.mastery_cap() > 0:
		var picker = load("res://scripts/ui/mastery_picker.gd").new()
		picker.character_creation_mode = true
		get_tree().root.call_deferred("add_child", picker)
	elif GameState.player_stats.character_class in [Stats.CharacterClass.WIZARD, Stats.CharacterClass.WARLOCK]:
		var cantrip_picker = load("res://scripts/ui/cantrip_select.gd").new()
		get_tree().root.call_deferred("add_child", cantrip_picker)
	else:
		# No mastery/cantrip step for this class (e.g. Monk) — race select is the last
		# class-specific onboarding screen, so go straight to the final summary/confirm.
		GameState.pending_summary_return_scene = "res://scripts/ui/race_select.gd"
		var summary = load("res://scripts/ui/character_summary.gd").new()
		get_tree().root.call_deferred("add_child", summary)
	queue_free()

func _on_back() -> void:
	GameState.race_picker_open = false
	# Undo any already-applied background bonus before reopening background_select.gd — it reads
	# player_stats' CURRENT scores as its "post-point-buy baseline" snapshot, which must not
	# already include a previously-confirmed bonus (apply_background_bonus() is additive, not an
	# overwrite — re-confirming on top of itself would double the bonus). Resetting to the
	# pure point-buy result here is safe/idempotent even if background was never confirmed yet.
	if not GameState.pending_point_buy_scores.is_empty():
		GameState.player_stats.apply_point_buy_scores(GameState.pending_point_buy_scores)
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	var background_picker = load("res://scripts/ui/background_select.gd").new()
	get_tree().root.call_deferred("add_child", background_picker)
	queue_free()

func _race_enum(race_id: String) -> Stats.CharacterRace:
	match race_id:
		"orc": return Stats.CharacterRace.ORC
		"human": return Stats.CharacterRace.HUMAN
		"halfling": return Stats.CharacterRace.HALFLING
		"dwarf": return Stats.CharacterRace.DWARF
		"elf": return Stats.CharacterRace.ELF
		"dragonborn": return Stats.CharacterRace.DRAGONBORN
		"tiefling": return Stats.CharacterRace.TIEFLING
		"aasimar": return Stats.CharacterRace.AASIMAR
		"gnome": return Stats.CharacterRace.GNOME
		"goliath": return Stats.CharacterRace.GOLIATH
	return Stats.CharacterRace.HUMAN

# ── Style helpers ───────────────────────────────────────────────────────────────────────

func _apply_tile_style(card: Button, accent: Color, selected: bool) -> void:
	var bg := Color(0.09, 0.09, 0.13, 0.97) if not selected else Color(0.14, 0.13, 0.08, 0.97)
	var border := accent * 0.7 if not selected else accent
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_border_width_all(2 if not selected else 3)
	normal.border_color = border
	normal.set_corner_radius_all(6)
	card.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.06)
	hover.set_border_width_all(2 if not selected else 3)
	hover.border_color = accent
	hover.set_corner_radius_all(6)
	card.add_theme_stylebox_override("hover", hover)
	card.add_theme_stylebox_override("pressed", hover)

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
