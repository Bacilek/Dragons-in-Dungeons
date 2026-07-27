extends CanvasLayer

# Blacksmith crafting overlay — give up 1 Mold + BLACKSMITH_GOLD_COST gold, get a fully random
# WeaponForge.generate_random_weapon() result. Modeled on attunement_picker.gd/short_rest_panel.gd
# (dim overlay + centered bordered Panel, focus_mode = FOCUS_NONE everywhere). Only ever reachable
# by bumping/RMB-interacting the Blacksmith prop tile (scripts/world/CLAUDE.md's
# "_spawn_blacksmith"/PlayerActions.open_blacksmith_panel()).

const PANEL_W: float = 640.0
const BLACKSMITH_GOLD_COST: int = 50

var _panel: Panel
var _mold_label: Label
var _gold_label: Label
var _forge_btn: Button
var _reveal_rtl: RichTextLabel

func _ready() -> void:
	layer = 25
	GameState.blacksmith_panel_open = true
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
	_panel.size = Vector2(PANEL_W, 340.0)
	_panel.position = (vp - _panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.10, 0.07, 0.05, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.75, 0.5, 0.25)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Blacksmith"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.9, 0.7, 0.4))
	title.position = Vector2(20.0, 14.0)
	title.size = Vector2(380.0, 34.0)
	_panel.add_child(title)

	var close_btn := Button.new()
	close_btn.text = "✕  Close  [Esc]"
	close_btn.size = Vector2(140.0, 34.0)
	close_btn.position = Vector2(PANEL_W - 156.0, 14.0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 14)
	_style_btn(close_btn, Color(0.22, 0.10, 0.10), Color(0.65, 0.28, 0.28))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 60.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	var desc := Label.new()
	desc.text = "Give up a Mold and %d gold to forge a completely random weapon.\nNo skill involved — pure chaos." % BLACKSMITH_GOLD_COST
	desc.add_theme_font_size_override("font_size", 14)
	desc.add_theme_color_override("font_color", Color(0.75, 0.75, 0.75))
	desc.position = Vector2(20.0, 76.0)
	desc.size = Vector2(PANEL_W - 40.0, 44.0)
	desc.autowrap_mode = TextServer.AUTOWRAP_WORD
	_panel.add_child(desc)

	_mold_label = Label.new()
	_mold_label.add_theme_font_size_override("font_size", 16)
	_mold_label.position = Vector2(20.0, 130.0)
	_mold_label.size = Vector2(PANEL_W - 40.0, 24.0)
	_panel.add_child(_mold_label)

	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 16)
	_gold_label.position = Vector2(20.0, 156.0)
	_gold_label.size = Vector2(PANEL_W - 40.0, 24.0)
	_panel.add_child(_gold_label)

	_forge_btn = Button.new()
	_forge_btn.text = "Forge Weapon"
	_forge_btn.size = Vector2(200.0, 40.0)
	_forge_btn.position = Vector2(20.0, 190.0)
	_forge_btn.focus_mode = Control.FOCUS_NONE
	_forge_btn.add_theme_font_size_override("font_size", 16)
	_style_btn(_forge_btn, Color(0.22, 0.14, 0.06), Color(0.75, 0.5, 0.25))
	_forge_btn.pressed.connect(_on_forge)
	_panel.add_child(_forge_btn)

	_reveal_rtl = RichTextLabel.new()
	_reveal_rtl.bbcode_enabled = true
	_reveal_rtl.fit_content = false
	_reveal_rtl.scroll_active = false
	_reveal_rtl.position = Vector2(20.0, 242.0)
	_reveal_rtl.size = Vector2(PANEL_W - 40.0, 84.0)
	_reveal_rtl.add_theme_font_size_override("normal_font_size", 14)
	_panel.add_child(_reveal_rtl)

	_refresh()

func _find_mold() -> Item:
	for it: Item in GameState.player_quickbar:
		if it != null and it.item_name == "Mold":
			return it
	for it: Item in GameState.player_inventory:
		if it != null and it.item_name == "Mold":
			return it
	return null

func _refresh() -> void:
	var mold: Item = _find_mold()
	var mold_count: int = mold.quantity if mold != null else 0
	_mold_label.text = "Mold: %d" % mold_count
	_mold_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5) if mold_count >= 1 else Color(0.8, 0.55, 0.3))
	_gold_label.text = "Gold: %d / %d" % [GameState.gold, BLACKSMITH_GOLD_COST]
	_gold_label.add_theme_color_override("font_color", Color(0.5, 0.85, 0.5) if GameState.gold >= BLACKSMITH_GOLD_COST else Color(0.8, 0.55, 0.3))
	_forge_btn.disabled = mold_count < 1 or GameState.gold < BLACKSMITH_GOLD_COST

func _on_forge() -> void:
	var mold: Item = _find_mold()
	if mold == null or GameState.gold < BLACKSMITH_GOLD_COST:
		return
	if not GameState.spend_gold(BLACKSMITH_GOLD_COST):
		return
	GameState.consume_one(mold)
	var weapon: Item = WeaponForge.generate_random_weapon()
	GameState.add_item(weapon)
	GameState.game_log("[color=orange]The Blacksmith forges you a [b]%s[/b].[/color]" % weapon.item_name)
	_reveal_rtl.text = WeaponTooltip.build(weapon)
	_refresh()

func _close() -> void:
	GameState.blacksmith_panel_open = false
	queue_free()

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
	var disabled := StyleBoxFlat.new()
	disabled.bg_color = Color(0.15, 0.15, 0.15)
	disabled.set_border_width_all(1)
	disabled.border_color = Color(0.3, 0.3, 0.3)
	disabled.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("disabled", disabled)

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
