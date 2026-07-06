extends CanvasLayer

# Subclass-select overlay — one-time, mandatory Tier 2 subclass choice, triggered when the
# gating boss (GameState.TIER2_GATING_BOSS_ID, floor 5) is defeated. Spawned by hud.gd on
# GameState.subclass_choice_required (emitted from GameState._on_boss_defeated()).
# Modeled on talent_picker.gd / mastery_picker.gd conventions: dim overlay + centered
# bordered Panel, focus_mode = FOCUS_NONE everywhere, blocks input via a GameState flag.
# NOT dismissible (no close button, Esc ignored) — the choice is permanent; confirm calls
# GameState.choose_subclass(), which routes through the same unlock_tier2() machinery the
# God-Mode debug arrows use.

const PANEL_W: float = 920.0
const MARGIN: float = 24.0
const CARD_GAP: float = 16.0
const ICON_SIZE: float = 44.0
const ROW_H: float = 60.0

# Card data. Talent names/blurbs are reused verbatim from the Talent definitions in
# GameState._setup_X_tier2_talents() — do not invent new lore here.
const SUBCLASSES: Array[Dictionary] = [
	{
		"name": "Berserker",
		"talents": [
			{"id": "rager", "name": "Rager", "blurb": "Berserker fury bends the flow of combat while Raging."},
			{"id": "frenzy", "name": "Frenzy", "blurb": "First attack each turn deals bonus Rage-scaled damage while Raging."},
			{"id": "retaliation", "name": "Retaliation", "blurb": "Strike back at enemies who hit you in melee."},
		],
	},
	{
		"name": "Zealot",
		"talents": [
			{"id": "divine_fury", "name": "Divine Fury", "blurb": "Your first attack each turn is charged with Radiant or Necrotic power."},
			{"id": "blessed_warrior", "name": "Blessed Warrior", "blurb": "A pool of divine healing charges you can call on mid-fight."},
			{"id": "zealous_presence", "name": "Zealous Presence", "blurb": "Rally yourself and nearby allies with Advantage on all rolls."},
		],
	},
	{
		"name": "World Tree",
		"talents": [
			{"id": "ironwood_bark", "name": "Ironwood Bark", "blurb": "Bark-like temporary HP fueled by Rage, with a damage payoff at rank 3."},
			{"id": "grip_of_the_forest", "name": "Grip of the Forest", "blurb": "While Raging, once per turn, pull a distant enemy into melee range."},
			{"id": "branching_strike", "name": "Branching Strike", "blurb": "Extend your reach with heavy/versatile melee weapons, and push foes back."},
		],
	},
	{
		"name": "Wild Heart",
		"talents": [
			{"id": "one_with_nature", "name": "One with Nature", "blurb": "Summon an animal companion that fights alongside you."},
			{"id": "natural_rager", "name": "Natural Rager", "blurb": "Unlock Bear/Eagle/Wolf forms while Raging. 1 rank grants all 3 forms."},
			{"id": "natural_sleeper", "name": "Natural Sleeper", "blurb": "Unlock Owl/Panther/Salmon terrain forms. Activate on floor entry."},
		],
	},
]

var _selected: String = ""
var _card_btns: Dictionary = {}   # subclass name → Button
var _confirm_btn: Button
var _panel: Panel

func _ready() -> void:
	layer = 25
	GameState.subclass_picker_open = true
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

	# ── Title ────────────────────────────────────────────────────────────────────
	var title := Label.new()
	title.text = "Choose Your Subclass"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(PANEL_W - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "The floor-5 boss has fallen — pick one of the four paths below. This choice is permanent."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(PANEL_W - MARGIN * 2.0, 24.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 80.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	# ── 2×2 card grid ─────────────────────────────────────────────────────────────
	var card_w: float = (PANEL_W - MARGIN * 2.0 - CARD_GAP) * 0.5
	var card_h: float = 46.0 + 3.0 * ROW_H + 8.0
	var y0: float = 92.0
	for i: int in SUBCLASSES.size():
		var col: int = i % 2
		var row: int = floori(i / 2.0)
		var pos := Vector2(MARGIN + col * (card_w + CARD_GAP), y0 + row * (card_h + CARD_GAP))
		_build_card(SUBCLASSES[i], pos, Vector2(card_w, card_h))

	var grid_h: float = 2.0 * card_h + CARD_GAP

	# ── Confirm button ────────────────────────────────────────────────────────────
	var confirm_y: float = y0 + grid_h + 18.0
	_confirm_btn = Button.new()
	_confirm_btn.text = "Choose a path…"
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
	var sub_name: String = data["name"]
	var card := Button.new()
	card.position = pos
	card.size = card_size
	card.focus_mode = Control.FOCUS_NONE
	_apply_card_style(card, false)
	card.pressed.connect(func() -> void: _select(sub_name))
	_card_btns[sub_name] = card
	_panel.add_child(card)

	var name_lbl := Label.new()
	name_lbl.text = sub_name
	name_lbl.add_theme_font_size_override("font_size", 19)
	name_lbl.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	name_lbl.position = Vector2(14.0, 10.0)
	name_lbl.size = Vector2(card_size.x - 28.0, 28.0)
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	card.add_child(name_lbl)

	var talents: Array = data["talents"]
	for i: int in talents.size():
		var t: Dictionary = talents[i]
		var ry: float = 46.0 + i * ROW_H

		var icon := TextureRect.new()
		icon.size = Vector2(ICON_SIZE, ICON_SIZE)
		icon.position = Vector2(14.0, ry)
		icon.ignore_texture_size = true  # REQUIRED — talent PNGs are 2048×2048 (see scripts/ui/CLAUDE.md)
		icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
		icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var icon_path: String = GameState.talent_icon_path(t["id"], 1)
		if icon_path != "" and ResourceLoader.exists(icon_path):
			icon.texture = load(icon_path)
		card.add_child(icon)

		var t_name := Label.new()
		t_name.text = t["name"]
		t_name.add_theme_font_size_override("font_size", 14)
		t_name.add_theme_color_override("font_color", Color(0.85, 0.75, 0.50))
		t_name.position = Vector2(14.0 + ICON_SIZE + 10.0, ry)
		t_name.size = Vector2(card_size.x - ICON_SIZE - 38.0, 20.0)
		t_name.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(t_name)

		var t_blurb := Label.new()
		t_blurb.text = t["blurb"]
		t_blurb.add_theme_font_size_override("font_size", 11)
		t_blurb.add_theme_color_override("font_color", Color(0.62, 0.62, 0.66))
		t_blurb.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
		t_blurb.position = Vector2(14.0 + ICON_SIZE + 10.0, ry + 20.0)
		t_blurb.size = Vector2(card_size.x - ICON_SIZE - 38.0, ROW_H - 22.0)
		t_blurb.mouse_filter = Control.MOUSE_FILTER_IGNORE
		card.add_child(t_blurb)

func _select(sub_name: String) -> void:
	_selected = sub_name
	for n: String in _card_btns:
		_apply_card_style(_card_btns[n], n == sub_name)
	_confirm_btn.disabled = false
	_confirm_btn.text = "Choose %s" % sub_name

func _on_confirm() -> void:
	if _selected == "":
		return
	GameState.subclass_picker_open = false
	GameState.choose_subclass(_selected)
	queue_free()

# ── Style helpers ─────────────────────────────────────────────────────────────

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
