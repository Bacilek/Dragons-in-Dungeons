class_name CritBanner
extends Node

func show_banner(text: String, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.add_theme_font_size_override("font_size", 48)
	lbl.add_theme_color_override("font_color", color)
	lbl.add_theme_color_override("font_shadow_color", Color(0, 0, 0, 0.8))
	lbl.add_theme_constant_override("shadow_offset_x", 2)
	lbl.add_theme_constant_override("shadow_offset_y", 2)
	lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	lbl.anchor_left = 0.0
	lbl.anchor_right = 1.0
	lbl.anchor_top = 0.35
	lbl.anchor_bottom = 0.65
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var _vp := get_viewport().get_visible_rect().size
	lbl.pivot_offset = Vector2(_vp.x * 0.5, _vp.y * 0.15)
	add_child(lbl)
	var t := create_tween()
	lbl.scale = Vector2(1.6, 1.6)
	lbl.modulate.a = 0.0
	t.tween_property(lbl, "scale", Vector2(1.0, 1.0), 0.25).set_ease(Tween.EASE_OUT)
	t.parallel().tween_property(lbl, "modulate:a", 1.0, 0.15)
	t.tween_interval(0.5)
	t.tween_property(lbl, "modulate:a", 0.0, 0.4)
	t.tween_callback(lbl.queue_free)
