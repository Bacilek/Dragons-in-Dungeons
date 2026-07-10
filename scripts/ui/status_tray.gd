class_name StatusTray
extends Control

# Generic status/buff/debuff/passive icon row, shown directly under the player portrait.
# Replaces the old 5 hardcoded dot nodes (hud.gd's former _poison_icon etc.). Data-driven: hud.gd
# builds an Array[Dictionary] of {id, icon_path, fallback_color, kind} entries every refresh and
# hands it to refresh() — new effect sources are a one-line addition at the call site, no new
# node/UI code here. See docs/architecture/status-icon-tray-design.md.

signal icon_hovered(id: String)
signal icon_unhovered()

const ICON_SIZE: float = 16.0
const GUTTER: float = 2.0

var _icon_nodes: Array[Control] = []  # pooled TextureRect/ColorRect, reused across refreshes

func refresh(entries: Array) -> void:
	while _icon_nodes.size() < entries.size():
		_icon_nodes.append(_make_icon_node())
	for i: int in _icon_nodes.size():
		var node: Control = _icon_nodes[i]
		if i >= entries.size():
			node.visible = false
			continue
		var entry: Dictionary = entries[i]
		var icon_path: String = entry.get("icon_path", "")
		node.position = Vector2(i * (ICON_SIZE + GUTTER), 0.0)
		node.visible = true
		node.set_meta("status_id", entry.get("id", ""))
		if node is TextureRect:
			var tr: TextureRect = node
			if not icon_path.is_empty() and ResourceLoader.exists(icon_path):
				tr.texture = load(icon_path)
				tr.modulate = Color.WHITE
			else:
				tr.texture = null
				tr.modulate = entry.get("fallback_color", Color.WHITE)

func _make_icon_node() -> Control:
	var rect := TextureRect.new()
	rect.size = Vector2(ICON_SIZE, ICON_SIZE)
	rect.custom_minimum_size = Vector2(ICON_SIZE, ICON_SIZE)
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.ignore_texture_size = true
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.mouse_filter = Control.MOUSE_FILTER_STOP
	rect.mouse_entered.connect(_on_icon_hover.bind(rect))
	rect.mouse_exited.connect(func() -> void: icon_unhovered.emit())
	add_child(rect)
	return rect

func _on_icon_hover(node: Control) -> void:
	icon_hovered.emit(str(node.get_meta("status_id", "")))
