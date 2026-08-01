class_name StatusTray
extends Control

# Generic status/buff/debuff/passive icon row, shown directly under the player portrait.
# Replaces the old 5 hardcoded dot nodes (hud.gd's former _poison_icon etc.). Data-driven: hud.gd
# builds an Array[Dictionary] of {id, icon_path, fallback_color, kind} entries every refresh and
# hands it to refresh() — new effect sources are a one-line addition at the call site, no new
# node/UI code here. See docs/architecture/status-icon-tray-design.md.

signal icon_hovered(id: String, rect: Rect2)
signal icon_unhovered()

const ICON_SIZE: float = 28.0
const GUTTER: float = 3.0

var _icon_nodes: Array[Control] = []  # pooled TextureRect/ColorRect, reused across refreshes

# Shared 1x1-white texture for icon-less entries — a TextureRect with texture == null draws
# NOTHING at all regardless of modulate (bugfix: the old fallback path set tr.texture = null and
# relied on modulate alone to show a "tinted placeholder square", which is invisible in practice —
# every id with no icons/status/ art yet, e.g. race_bonus/weapon_mastery/tactician/psycho_adv here
# and every enemy condition in enemy_inspect.gd's Inspect Panel entries, silently rendered as
# nothing). Solid white so modulate's tint is the only thing that shows through.
static var _fallback_tex: ImageTexture

static func _get_fallback_tex() -> ImageTexture:
	if _fallback_tex == null:
		var img := Image.create(8, 8, false, Image.FORMAT_RGBA8)
		img.fill(Color.WHITE)
		_fallback_tex = ImageTexture.create_from_image(img)
	return _fallback_tex

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
				tr.texture = _get_fallback_tex()
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
	icon_hovered.emit(str(node.get_meta("status_id", "")), Rect2(node.global_position, node.size))
