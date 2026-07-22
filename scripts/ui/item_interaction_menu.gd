class_name ItemInteractionMenu
extends Control

# Small transient RMB item-interaction popup (e.g. "Light" / "Throw"), used by both hud.gd's
# quickbar and inventory_overlay.gd's bag/quickbar slots — see scripts/ui/CLAUDE.md's "Item
# interaction menu" section. Not a blocking modal: click elsewhere or Esc dismisses it.

const _ROW_W: float = 100.0
const _ROW_H: float = 28.0

var _panel: PanelContainer

func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	anchor_right = 1.0
	anchor_bottom = 1.0
	z_index = 30

func open(anchor_pos: Vector2, interactions: Array[String], on_choice: Callable) -> void:
	# Full-viewport click-catcher: any press outside the buttons closes the menu without acting.
	var catcher := Control.new()
	catcher.anchor_right = 1.0
	catcher.anchor_bottom = 1.0
	catcher.mouse_filter = Control.MOUSE_FILTER_STOP
	catcher.gui_input.connect(func(ev: InputEvent) -> void:
		if ev is InputEventMouseButton and (ev as InputEventMouseButton).pressed:
			queue_free()
	)
	add_child(catcher)

	_panel = PanelContainer.new()
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.50, 0.35)
	sb.set_corner_radius_all(3)
	sb.content_margin_left = 4.0
	sb.content_margin_right = 4.0
	sb.content_margin_top = 4.0
	sb.content_margin_bottom = 4.0
	_panel.add_theme_stylebox_override("panel", sb)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var vbox := VBoxContainer.new()
	vbox.add_theme_constant_override("separation", 2)
	_panel.add_child(vbox)

	for id: String in interactions:
		var btn := Button.new()
		btn.text = ItemInteractions.LABELS.get(id, id.capitalize())
		btn.focus_mode = Control.FOCUS_NONE
		btn.custom_minimum_size = Vector2(_ROW_W, _ROW_H)
		btn.pressed.connect(func() -> void:
			on_choice.call(id)
			queue_free()
		)
		vbox.add_child(btn)

	var vp: Vector2 = get_viewport().get_visible_rect().size
	var panel_h: float = interactions.size() * _ROW_H + (interactions.size() - 1) * 2.0 + 8.0
	var px: float = clampf(anchor_pos.x - _ROW_W * 0.5, 4.0, vp.x - _ROW_W - 8.0 - 4.0)
	var py: float = anchor_pos.y - panel_h - 14.0
	if py < 4.0:
		py = anchor_pos.y + 18.0
	_panel.position = Vector2(px, py)

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and (event as InputEventKey).pressed and (event as InputEventKey).physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		queue_free()
