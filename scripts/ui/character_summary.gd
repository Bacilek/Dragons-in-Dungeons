extends CanvasLayer

# Final confirmation screen of the Custom character-creation flow (class select -> point buy ->
# background ASI -> race select -> mastery/cantrip picker -> HERE). Spawned by whichever of
# mastery_picker.gd/cantrip_select.gd/race_select.gd was the player's last class-specific
# onboarding step (see each file's own comment) — that spawner also sets
# GameState.pending_summary_return_scene so "Take me back" knows exactly where to reopen.
# GameState.class_selected is NOT set true until "Yes" is pressed here — the player has been
# unable to touch the game world (input is hard-gated on class_selected) for the entire Custom
# flow up to this point, so any amount of back-and-forth before this screen is invisible/harmless.

const PANEL_W: float = 720.0
const MARGIN: float = 24.0
const CHAR_PATH := "res://sprites/characters/classes/"

const CLASS_SPRITE: Dictionary = {
	Stats.CharacterClass.BARBARIAN: CHAR_PATH + "Barbarian/idle_1.png",
	Stats.CharacterClass.RANGER: CHAR_PATH + "Ranger/idle_1.png",
	Stats.CharacterClass.WIZARD: CHAR_PATH + "Wizard/idle_1.png",
	Stats.CharacterClass.MONK: CHAR_PATH + "Monk/idle_1.png",
}
const CLASS_NAMES: Dictionary = {
	Stats.CharacterClass.BARBARIAN: "Barbarian",
	Stats.CharacterClass.RANGER: "Ranger",
	Stats.CharacterClass.WIZARD: "Wizard",
	Stats.CharacterClass.MONK: "Monk",
}
const RACE_NAMES: Dictionary = {
	Stats.CharacterRace.ORC: "Orc",
	Stats.CharacterRace.HUMAN: "Human",
	Stats.CharacterRace.HALFLING: "Halfling",
	Stats.CharacterRace.DWARF: "Dwarf",
	Stats.CharacterRace.ELF: "Elf",
	Stats.CharacterRace.DRAGONBORN: "Dragonborn",
}
const ABILITY_SCORE_NAMES: Dictionary = {
	Stats.CharacterRace.HUMAN: ["STR", "DEX", "CON", "INT", "WIS", "CHA"],
}
const ELF_SUBRACES: Array = ["Drow", "High Elf", "Wood Elf"]
const DRAGONBORN_ANCESTRIES: Array = [
	"Black", "Blue", "Brass", "Bronze", "Copper", "Gold", "Green", "Red", "Silver", "White",
]

var _panel: Panel

func _ready() -> void:
	layer = 26
	GameState.character_summary_open = true
	_build_ui()

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var stats: Stats = GameState.player_stats

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.7)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.98)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Are You Ready?"
	title.add_theme_font_size_override("font_size", 28)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 36.0)
	_panel.add_child(title)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 56.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	# ── Portrait + headline (class/race) ────────────────────────────────────────
	var portrait := TextureRect.new()
	var sprite_path: String = CLASS_SPRITE.get(stats.character_class, "")
	if sprite_path != "" and ResourceLoader.exists(sprite_path):
		portrait.texture = load(sprite_path)
	portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	portrait.ignore_texture_size = true
	portrait.position = Vector2(MARGIN, 74.0)
	portrait.size = Vector2(110.0, 110.0)
	_panel.add_child(portrait)

	var headline := Label.new()
	headline.text = "%s %s" % [_race_display_name(stats), CLASS_NAMES.get(stats.character_class, "?")]
	headline.add_theme_font_size_override("font_size", 22)
	headline.add_theme_color_override("font_color", Color(0.95, 0.90, 0.75))
	headline.position = Vector2(MARGIN + 126.0, 84.0)
	headline.size = Vector2(PANEL_W - MARGIN * 2.0 - 126.0, 30.0)
	_panel.add_child(headline)

	var hd_hp_ac := Label.new()
	hd_hp_ac.text = "%s   •   HP %d/%d   •   AC %d" % [
		"d%d Hit Die" % GameState.hit_die_sides(), stats.current_hp, stats.max_hp, stats.armor_class,
	]
	hd_hp_ac.add_theme_font_size_override("font_size", 14)
	hd_hp_ac.add_theme_color_override("font_color", Color(0.62, 0.82, 0.62))
	hd_hp_ac.position = Vector2(MARGIN + 126.0, 116.0)
	hd_hp_ac.size = Vector2(PANEL_W - MARGIN * 2.0 - 126.0, 22.0)
	_panel.add_child(hd_hp_ac)

	# ── Ability scores row ───────────────────────────────────────────────────────
	var scores: Array = [
		["STR", stats.strength, stats.str_modifier()],
		["DEX", stats.dexterity, stats.dex_modifier()],
		["CON", stats.constitution, stats.con_modifier()],
		["INT", stats.intelligence, stats.int_modifier()],
		["WIS", stats.wisdom, stats.wis_modifier()],
		["CHA", stats.charisma, stats.cha_modifier()],
	]
	var score_y: float = 150.0
	var score_w: float = (PANEL_W - MARGIN * 2.0) / 6.0
	for i: int in scores.size():
		_build_score_cell(scores[i], Vector2(MARGIN + i * score_w, score_y), score_w)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(12.0, score_y + 56.0)
	sep2.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep2)

	var y: float = score_y + 68.0

	# ── Weapon masteries (if any) ────────────────────────────────────────────────
	if stats.mastery_cap() > 0:
		var mastery_lbl := Label.new()
		var known: Array[String] = stats.known_weapon_masteries
		mastery_lbl.text = "Weapon Masteries: %s" % (", ".join(known) if known.size() > 0 else "none chosen")
		mastery_lbl.add_theme_font_size_override("font_size", 14)
		mastery_lbl.add_theme_color_override("font_color", Color(0.80, 0.80, 0.85))
		mastery_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		mastery_lbl.position = Vector2(MARGIN, y)
		mastery_lbl.size = Vector2(PANEL_W - MARGIN * 2.0, 24.0)
		_panel.add_child(mastery_lbl)
		y += 28.0

	# ── Known spells (if a caster) ───────────────────────────────────────────────
	if stats.caster != null:
		var cantrips: Array[String] = []
		var prepared: Array[String] = []
		for id: String in stats.caster.known_spells:
			var spell: Spell = SpellDb.get_spell(id)
			var label_name: String = spell.spell_name if spell != null else id
			if spell != null and spell.level == 0:
				cantrips.append(label_name)
			else:
				prepared.append(label_name)
		var spell_lbl := Label.new()
		spell_lbl.text = "Cantrips: %s\nPrepared Spells: %s" % [
			(", ".join(cantrips) if cantrips.size() > 0 else "none"),
			(", ".join(prepared) if prepared.size() > 0 else "none"),
		]
		spell_lbl.add_theme_font_size_override("font_size", 14)
		spell_lbl.add_theme_color_override("font_color", Color(0.70, 0.80, 1.0))
		spell_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		spell_lbl.position = Vector2(MARGIN, y)
		spell_lbl.size = Vector2(PANEL_W - MARGIN * 2.0, 44.0)
		_panel.add_child(spell_lbl)
		y += 52.0

	# ── Buttons ──────────────────────────────────────────────────────────────────
	y += 12.0
	var yes_btn := Button.new()
	yes_btn.text = "Yes, I'm Ready!"
	yes_btn.size = Vector2(260.0, 46.0)
	yes_btn.position = Vector2(PANEL_W * 0.5 - 270.0, y)
	yes_btn.focus_mode = Control.FOCUS_NONE
	yes_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(yes_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	yes_btn.pressed.connect(_on_confirm)
	_panel.add_child(yes_btn)

	var back_btn := Button.new()
	back_btn.text = "Take Me Back"
	back_btn.size = Vector2(260.0, 46.0)
	back_btn.position = Vector2(PANEL_W * 0.5 + 10.0, y)
	back_btn.focus_mode = Control.FOCUS_NONE
	back_btn.add_theme_font_size_override("font_size", 17)
	_style_btn(back_btn, Color(0.18, 0.14, 0.08), Color(0.55, 0.45, 0.25))
	back_btn.pressed.connect(_on_back)
	_panel.add_child(back_btn)

	var panel_h: float = y + 46.0 + 20.0
	_panel.size = Vector2(PANEL_W, panel_h)
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, (vp.y - panel_h) * 0.5)

func _build_score_cell(entry: Array, pos: Vector2, w: float) -> void:
	var name_lbl := Label.new()
	name_lbl.text = entry[0]
	name_lbl.add_theme_font_size_override("font_size", 13)
	name_lbl.add_theme_color_override("font_color", Color(0.62, 0.60, 0.56))
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.position = pos
	name_lbl.size = Vector2(w, 18.0)
	_panel.add_child(name_lbl)

	var mod: int = entry[2]
	var mod_str: String = "+%d" % mod if mod >= 0 else str(mod)
	var val_lbl := Label.new()
	val_lbl.text = "%d (%s)" % [entry[1], mod_str]
	val_lbl.add_theme_font_size_override("font_size", 16)
	val_lbl.add_theme_color_override("font_color", Color(0.92, 0.88, 0.72))
	val_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	val_lbl.position = pos + Vector2(0.0, 20.0)
	val_lbl.size = Vector2(w, 24.0)
	_panel.add_child(val_lbl)

func _race_display_name(stats: Stats) -> String:
	var base_name: String = RACE_NAMES.get(stats.character_race, "")
	match stats.character_race:
		Stats.CharacterRace.ELF:
			var idx: int = stats.race_variant
			if idx >= 0 and idx < ELF_SUBRACES.size():
				return "%s (%s)" % [base_name, ELF_SUBRACES[idx]]
		Stats.CharacterRace.DRAGONBORN:
			var idx2: int = stats.race_variant
			if idx2 >= 0 and idx2 < DRAGONBORN_ANCESTRIES.size():
				return "%s %s" % [DRAGONBORN_ANCESTRIES[idx2], base_name]
	return base_name

func _on_confirm() -> void:
	GameState.character_summary_open = false
	GameState.class_selected = true
	# The Custom flow's earlier class_chosen.emit() (class_select.gd) fired while class_selected
	# was still false, so SaveManager's checkpoint-on-class_chosen hook was a no-op then — re-emit
	# now that the character is actually finished so the run gets its very first checkpoint.
	GameState.class_chosen.emit(GameState.player_stats.character_class)
	queue_free()

func _on_back() -> void:
	GameState.character_summary_open = false
	var scene_path: String = GameState.pending_summary_return_scene
	if scene_path == "":
		scene_path = "res://scripts/ui/race_select.gd"
	var screen = load(scene_path).new()
	if scene_path == "res://scripts/ui/mastery_picker.gd":
		screen.character_creation_mode = true
	get_tree().root.call_deferred("add_child", screen)
	queue_free()

func _style_btn(btn: Button, bg: Color, border: Color) -> void:
	var normal := StyleBoxFlat.new()
	normal.bg_color = bg
	normal.set_border_width_all(2)
	normal.border_color = border
	normal.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = bg.lightened(0.12)
	hover.set_border_width_all(2)
	hover.border_color = border.lightened(0.15)
	hover.set_corner_radius_all(4)
	btn.add_theme_stylebox_override("hover", hover)

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory final confirmation — swallow all key input (no Esc close) so nothing leaks to
	# gameplay handlers underneath (input is already hard-gated on class_selected anyway, this
	# just matches every other onboarding screen's convention).
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
