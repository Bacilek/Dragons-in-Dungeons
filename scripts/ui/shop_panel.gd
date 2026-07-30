extends CanvasLayer

# ShopRoom Buy/Sell overlay (special-rooms-economy-design.md §4.1, session 7e). Modeled on
# attunement_picker.gd (dim overlay + centered bordered Panel, focus_mode = FOCUS_NONE
# everywhere, one row per item). Only ever reachable by bumping/RMB-interacting the shopkeeper
# prop tile (scripts/world/CLAUDE.md's "Shopkeeper prop" — PlayerActions.open_shop_panel()).
# Buy pulls from the shopkeeper's own generated stock (DungeonFloor.get_shopkeeper_stock()) —
# stock is overlay-only, no restock, discarded when the floor unloads. Sell lists the player's
# own quickbar+bag items with a nonzero gold_value.

const PANEL_W: float = 640.0
const ROW_H: float = 64.0

var shop_pos: Vector2i = Vector2i(-1, -1)

var _panel: Panel
var _rows_container: Control
var _gold_rtl: RichTextLabel
var _buy_tab_btn: Button
var _sell_tab_btn: Button
var _empty_label: Label
var _mode: String = "buy"  # "buy" | "sell"

func _ready() -> void:
	layer = 25
	GameState.shop_open = true
	GameState.gold_changed.connect(_on_gold_changed)
	_build_ui()

func _dungeon_floor() -> Node:
	return get_tree().get_first_node_in_group("dungeon_floor")

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, 200.0)  # resized in _refresh()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.06, 0.10, 0.08, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.35, 0.7, 0.4)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Shop"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(0.55, 0.9, 0.6))
	title.position = Vector2(20.0, 14.0)
	title.size = Vector2(200.0, 34.0)
	_panel.add_child(title)

	_gold_rtl = RichTextLabel.new()
	_gold_rtl.bbcode_enabled = true
	_gold_rtl.fit_content = false
	_gold_rtl.scroll_active = false
	_gold_rtl.position = Vector2(220.0, 18.0)
	_gold_rtl.size = Vector2(180.0, 30.0)
	_gold_rtl.add_theme_font_size_override("normal_font_size", 18)
	_panel.add_child(_gold_rtl)

	var close_btn := Button.new()
	close_btn.text = "✕  Close  [Esc]"
	close_btn.size = Vector2(140.0, 34.0)
	close_btn.position = Vector2(PANEL_W - 156.0, 14.0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 14)
	_style_btn(close_btn, Color(0.22, 0.10, 0.10), Color(0.65, 0.28, 0.28))
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	_buy_tab_btn = Button.new()
	_buy_tab_btn.text = "Buy"
	_buy_tab_btn.size = Vector2(100.0, 30.0)
	_buy_tab_btn.position = Vector2(20.0, 56.0)
	_buy_tab_btn.focus_mode = Control.FOCUS_NONE
	_buy_tab_btn.add_theme_font_size_override("font_size", 15)
	_buy_tab_btn.pressed.connect(func() -> void: _set_mode("buy"))
	_panel.add_child(_buy_tab_btn)

	_sell_tab_btn = Button.new()
	_sell_tab_btn.text = "Sell"
	_sell_tab_btn.size = Vector2(100.0, 30.0)
	_sell_tab_btn.position = Vector2(128.0, 56.0)
	_sell_tab_btn.focus_mode = Control.FOCUS_NONE
	_sell_tab_btn.add_theme_font_size_override("font_size", 15)
	_sell_tab_btn.pressed.connect(func() -> void: _set_mode("sell"))
	_panel.add_child(_sell_tab_btn)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 94.0)
	sep.size = Vector2(PANEL_W - 24.0, 2.0)
	_panel.add_child(sep)

	_empty_label = Label.new()
	_empty_label.add_theme_font_size_override("font_size", 15)
	_empty_label.add_theme_color_override("font_color", Color(0.6, 0.6, 0.65))
	_empty_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_empty_label.position = Vector2(20.0, 110.0)
	_empty_label.size = Vector2(PANEL_W - 40.0, 30.0)
	_panel.add_child(_empty_label)

	_rows_container = Control.new()
	_rows_container.position = Vector2(20.0, 110.0)
	_rows_container.size = Vector2(PANEL_W - 40.0, 0.0)
	_panel.add_child(_rows_container)

	_refresh()

func _set_mode(mode: String) -> void:
	_mode = mode
	_refresh()

func _on_gold_changed(_amount: int) -> void:
	_refresh()

func _refresh() -> void:
	_gold_rtl.text = "[right][color=gold]%d gold[/color][/right]" % GameState.gold
	_style_tab_btn(_buy_tab_btn, _mode == "buy")
	_style_tab_btn(_sell_tab_btn, _mode == "sell")

	for c: Node in _rows_container.get_children():
		c.queue_free()

	var y: float = 0.0
	if _mode == "buy":
		var stock: Array[Item] = []
		var df: Node = _dungeon_floor()
		if df != null:
			stock = df.get_shopkeeper_stock(shop_pos)
		_empty_label.text = "Sold out."
		_empty_label.visible = stock.is_empty()
		for it: Item in stock:
			_add_buy_row(it, y)
			y += ROW_H
	else:
		var items: Array[Item] = []
		for it: Item in GameState.player_quickbar:
			if it != null and it.gold_value > 0:
				items.append(it)
		for it: Item in GameState.player_inventory:
			if it != null and it.gold_value > 0:
				items.append(it)
		_empty_label.text = "Nothing worth selling in your inventory."
		_empty_label.visible = items.is_empty()
		for it: Item in items:
			_add_sell_row(it, y)
			y += ROW_H

	_rows_container.size = Vector2(PANEL_W - 40.0, y)
	var panel_h: float = maxf(110.0 + maxf(y, 40.0) + 16.0, 220.0)
	_panel.size = Vector2(PANEL_W, panel_h)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5

func _add_row_frame(y: float, item: Item) -> Panel:
	var frame := Panel.new()
	frame.position = Vector2(0.0, y)
	frame.size = Vector2(PANEL_W - 40.0, ROW_H - 8.0)
	var fbox := StyleBoxFlat.new()
	fbox.bg_color = Color(0.12, 0.12, 0.16, 0.9)
	fbox.set_border_width_all(2)
	fbox.border_color = Color(0.35, 0.35, 0.35)
	fbox.set_corner_radius_all(4)
	frame.add_theme_stylebox_override("panel", fbox)
	_rows_container.add_child(frame)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.position = Vector2(6.0, 6.0)
	icon.size = Vector2(ROW_H - 20.0, ROW_H - 20.0)
	if item.icon_path != "" and ResourceLoader.exists(item.icon_path):
		icon.texture = load(item.icon_path)
	frame.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = item.item_name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	name_lbl.position = Vector2(ROW_H + 4.0, 6.0)
	name_lbl.size = Vector2(PANEL_W - 40.0 - ROW_H - 160.0, 24.0)
	frame.add_child(name_lbl)

	return frame

func _add_buy_row(item: Item, y: float) -> void:
	var frame: Panel = _add_row_frame(y, item)

	var price: int = item.gold_value
	var price_lbl := Label.new()
	price_lbl.text = "%d g" % price
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	price_lbl.position = Vector2(ROW_H + 4.0, 32.0)
	price_lbl.size = Vector2(120.0, 20.0)
	frame.add_child(price_lbl)

	var buy_btn := Button.new()
	buy_btn.text = "Buy"
	buy_btn.size = Vector2(110.0, ROW_H - 20.0)
	buy_btn.position = Vector2(frame.size.x - 120.0, 4.0)
	buy_btn.focus_mode = Control.FOCUS_NONE
	buy_btn.add_theme_font_size_override("font_size", 14)
	buy_btn.disabled = GameState.gold < price
	_style_btn(buy_btn, Color(0.10, 0.16, 0.22), Color(0.28, 0.5, 0.65))
	buy_btn.pressed.connect(func() -> void: _on_buy(item))
	frame.add_child(buy_btn)

func _add_sell_row(item: Item, y: float) -> void:
	var frame: Panel = _add_row_frame(y, item)

	var price: int = maxi(1, item.gold_value / 2)
	var price_lbl := Label.new()
	price_lbl.text = "%d g" % price
	price_lbl.add_theme_font_size_override("font_size", 12)
	price_lbl.add_theme_color_override("font_color", Color(0.85, 0.75, 0.35))
	price_lbl.position = Vector2(ROW_H + 4.0, 32.0)
	price_lbl.size = Vector2(120.0, 20.0)
	frame.add_child(price_lbl)

	var sell_btn := Button.new()
	sell_btn.text = "Sell"
	sell_btn.size = Vector2(110.0, ROW_H - 20.0)
	sell_btn.position = Vector2(frame.size.x - 120.0, 4.0)
	sell_btn.focus_mode = Control.FOCUS_NONE
	sell_btn.add_theme_font_size_override("font_size", 14)
	_style_btn(sell_btn, Color(0.22, 0.14, 0.06), Color(0.75, 0.5, 0.25))
	sell_btn.pressed.connect(func() -> void: _on_sell(item))
	frame.add_child(sell_btn)

func _on_buy(item: Item) -> void:
	if GameState.gold < item.gold_value:
		return
	var df: Node = _dungeon_floor()
	if df == null:
		return
	var stock: Array[Item] = df.get_shopkeeper_stock(shop_pos)
	if not stock.has(item):
		return
	if not GameState.add_item(item):
		GameState.game_log("[color=gray]Your inventory is full.[/color]")
		return
	if not GameState.spend_gold(item.gold_value):
		GameState.remove_item(item)
		return
	stock.erase(item)
	GameState.game_log("[color=cyan]Bought [b]%s[/b] for %d gold.[/color]" % [item.item_name, item.gold_value])
	_refresh()

func _on_sell(item: Item) -> void:
	var price: int = maxi(1, item.gold_value / 2)
	GameState.remove_item(item)
	GameState.add_gold(price)
	GameState.game_log("[color=cyan]Sold [b]%s[/b] for %d gold.[/color]" % [item.item_name, price])
	_refresh()

func _close() -> void:
	GameState.shop_open = false
	queue_free()

func _style_tab_btn(btn: Button, active: bool) -> void:
	if active:
		_style_btn(btn, Color(0.10, 0.22, 0.12), Color(0.4, 0.8, 0.45))
	else:
		_style_btn(btn, Color(0.13, 0.13, 0.15), Color(0.35, 0.35, 0.35))

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
