class_name InspectPanel
extends CanvasLayer

# Full-value Inspect Panel — SPD-style "what am I looking at" summary shown on Ctrl+LMB / RMB
# Inspect (PlayerActions.do_inspect(), scripts/entities/CLAUDE.md's Player-specific section).
# Replaces the old plain chat-log line for every inspect target (enemy/trap/floor item/tile).
#
# Deliberately NON-blocking (no GameState.*_open input-gate flag, no full-screen dim) — it's a
# read-only glance, not a decision the player needs to make, so gameplay keeps running underneath.
# Closes on Esc, the Close button, or automatically the next time the player takes any real or
# free action (TurnManager.player_turn_started fires on both — see turn_manager.gd).
#
# Enemy view: portrait + HP bar + AC + auto-generated "<Size> <Type>, CR <n>" line + a live status
# icon row (reuses status_tray.gd verbatim — same hover-emits-id contract as the HUD's own tray;
# hover copy comes from EnemyInspect.build_bbcode(), scripts/entities/enemy_inspect.gd).
# Simple view (trap/floor item/tile): title + subtitle + a description line, no portrait/HP/status.

const PANEL_W: float = 420.0
const PORTRAIT_SIZE: float = 96.0

var _panel: Panel
var _title_lbl: Label
var _subtitle_lbl: Label
var _desc_rtl: RichTextLabel
var _portrait: TextureRect
var _hp_bg: ColorRect
var _hp_fill: ColorRect
var _hp_lbl: Label
var _status_tray: StatusTray
var _status_tooltip_rtl: RichTextLabel

func _ready() -> void:
	layer = 25
	TurnManager.player_turn_started.connect(_on_player_turn_started)
	_build_skeleton()

func _build_skeleton() -> void:
	_panel = Panel.new()
	_panel.size = Vector2(PANEL_W, 120.0)  # resized once content is known
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.85, 0.6, 0.2)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(_panel)

	var close_btn := Button.new()
	close_btn.text = "✕"
	close_btn.size = Vector2(28.0, 28.0)
	close_btn.position = Vector2(PANEL_W - 38.0, 10.0)
	close_btn.focus_mode = Control.FOCUS_NONE
	close_btn.add_theme_font_size_override("font_size", 16)
	close_btn.pressed.connect(_close)
	_panel.add_child(close_btn)

	_title_lbl = Label.new()
	_title_lbl.position = Vector2(20.0, 12.0)
	_title_lbl.size = Vector2(PANEL_W - 70.0, 30.0)
	_title_lbl.add_theme_font_size_override("font_size", 22)
	_title_lbl.add_theme_color_override("font_color", Color(1.0, 0.75, 0.35))
	_panel.add_child(_title_lbl)

	_subtitle_lbl = Label.new()
	_subtitle_lbl.position = Vector2(20.0, 42.0)
	_subtitle_lbl.size = Vector2(PANEL_W - 40.0, 22.0)
	_subtitle_lbl.add_theme_font_size_override("font_size", 14)
	_subtitle_lbl.add_theme_color_override("font_color", Color(0.7, 0.7, 0.75))
	_panel.add_child(_subtitle_lbl)

	_portrait = TextureRect.new()
	_portrait.ignore_texture_size = true
	_portrait.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	_portrait.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	_portrait.position = Vector2(20.0, 74.0)
	_portrait.size = Vector2(PORTRAIT_SIZE, PORTRAIT_SIZE)
	_portrait.visible = false
	_panel.add_child(_portrait)

	var hp_x: float = 20.0 + PORTRAIT_SIZE + 16.0
	_hp_bg = ColorRect.new()
	_hp_bg.color = Color(0.15, 0.05, 0.05)
	_hp_bg.position = Vector2(hp_x, 78.0)
	_hp_bg.size = Vector2(PANEL_W - hp_x - 20.0, 18.0)
	_hp_bg.visible = false
	_panel.add_child(_hp_bg)

	_hp_fill = ColorRect.new()
	_hp_fill.color = Color(0.2, 0.75, 0.2)
	_hp_fill.position = _hp_bg.position
	_hp_fill.size = Vector2(0.0, 18.0)
	_hp_fill.visible = false
	_panel.add_child(_hp_fill)

	_hp_lbl = Label.new()
	_hp_lbl.position = Vector2(hp_x, 100.0)
	_hp_lbl.size = Vector2(PANEL_W - hp_x - 20.0, 40.0)
	_hp_lbl.add_theme_font_size_override("font_size", 14)
	_hp_lbl.add_theme_color_override("font_color", Color(0.9, 0.9, 0.95))
	_hp_lbl.visible = false
	_panel.add_child(_hp_lbl)

	_status_tray = StatusTray.new()
	_status_tray.position = Vector2(20.0, 74.0 + PORTRAIT_SIZE + 10.0)
	_status_tray.size = Vector2(PANEL_W - 40.0, StatusTray.ICON_SIZE)
	_status_tray.visible = false
	_status_tray.icon_hovered.connect(_on_status_icon_hovered)
	_status_tray.icon_unhovered.connect(_on_status_icon_unhovered)
	_panel.add_child(_status_tray)

	_desc_rtl = RichTextLabel.new()
	_desc_rtl.bbcode_enabled = true
	_desc_rtl.fit_content = true
	_desc_rtl.scroll_active = false
	_desc_rtl.position = Vector2(20.0, 74.0)
	_desc_rtl.size = Vector2(PANEL_W - 40.0, 20.0)
	_desc_rtl.add_theme_font_size_override("normal_font_size", 14)
	_panel.add_child(_desc_rtl)

	_status_tooltip_rtl = RichTextLabel.new()
	_status_tooltip_rtl.bbcode_enabled = true
	_status_tooltip_rtl.fit_content = true
	_status_tooltip_rtl.scroll_active = false
	_status_tooltip_rtl.size = Vector2(260.0, 10.0)
	_status_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_status_tooltip_rtl.add_theme_font_size_override("normal_font_size", 13)
	_status_tooltip_rtl.visible = false
	var tt_bg := StyleBoxFlat.new()
	tt_bg.bg_color = Color(0.05, 0.05, 0.08, 0.97)
	tt_bg.set_border_width_all(1)
	tt_bg.border_color = Color(0.5, 0.5, 0.55)
	tt_bg.content_margin_left = 8.0
	tt_bg.content_margin_right = 8.0
	tt_bg.content_margin_top = 6.0
	tt_bg.content_margin_bottom = 6.0
	_status_tooltip_rtl.add_theme_stylebox_override("normal", tt_bg)
	add_child(_status_tooltip_rtl)

func open_enemy(enemy: Enemy) -> void:
	_title_lbl.text = enemy.display_name + ("  [BOSS]" if enemy.is_boss else "")
	_subtitle_lbl.text = "AC %d" % enemy.stats.armor_class

	var idle_tex: Texture2D = null
	var sprite: AnimatedSprite2D = enemy.get_node_or_null("AnimatedSprite2D") as AnimatedSprite2D
	if sprite != null and sprite.sprite_frames != null and sprite.sprite_frames.has_animation("idle") \
			and sprite.sprite_frames.get_frame_count("idle") > 0:
		idle_tex = sprite.sprite_frames.get_frame_texture("idle", 0)
	_portrait.texture = idle_tex
	_portrait.visible = idle_tex != null

	var hp_x: float = 20.0 + PORTRAIT_SIZE + 16.0
	var ratio: float = clampf(float(enemy.stats.current_hp) / maxf(1.0, float(enemy.stats.max_hp)), 0.0, 1.0)
	var fill_color: Color = Color(0.2, 0.75, 0.2)
	if ratio < 0.25:
		fill_color = Color(0.8, 0.2, 0.2)
	elif ratio < 0.5:
		fill_color = Color(0.85, 0.7, 0.2)
	_hp_fill.color = fill_color
	var bar_w: float = _hp_bg.size.x
	_hp_fill.size = Vector2(bar_w * ratio, 18.0)
	_hp_lbl.text = "HP: %d / %d" % [enemy.stats.current_hp, enemy.stats.max_hp]
	_hp_bg.visible = true
	_hp_fill.visible = true
	_hp_lbl.visible = true

	_desc_rtl.position = Vector2(20.0, 74.0 + PORTRAIT_SIZE + 10.0)
	_desc_rtl.text = "[color=#b0b0b8]%s[/color]" % EnemyInspect.description_line(enemy)

	var entries: Array[Dictionary] = EnemyInspect.status_entries(enemy)
	_status_tray.position.y = _desc_rtl.position.y + 24.0
	_status_tray.visible = not entries.is_empty()
	_status_tray.refresh(entries)

	var content_bottom: float = _status_tray.position.y + (StatusTray.ICON_SIZE + 12.0 if not entries.is_empty() else 10.0)
	_finish_layout(content_bottom)

func open_simple(title: String, subtitle: String, desc: String) -> void:
	_title_lbl.text = title
	_subtitle_lbl.text = subtitle
	_portrait.visible = false
	_hp_bg.visible = false
	_hp_fill.visible = false
	_hp_lbl.visible = false
	_status_tray.visible = false
	_status_tray.refresh([])

	_desc_rtl.position = Vector2(20.0, 68.0)
	_desc_rtl.size = Vector2(PANEL_W - 40.0, 20.0)
	_desc_rtl.text = ("[color=#c8c8cf]%s[/color]" % desc) if desc != "" else ""
	# fit_content's real height needs a layout pass to settle — estimate line count from
	# character length instead of trusting get_content_height() right after setting .text.
	var est_lines: int = maxi(1, ceili(desc.length() / 55.0)) if desc != "" else 0
	_finish_layout(_desc_rtl.position.y + est_lines * 20.0 + 10.0)

func _finish_layout(content_bottom: float) -> void:
	var panel_h: float = maxf(content_bottom + 16.0, 110.0)
	_panel.size = Vector2(PANEL_W, panel_h)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_panel.position = Vector2((vp.x - PANEL_W) * 0.5, vp.y * 0.22)
	_status_tooltip_rtl.visible = false

func _on_status_icon_hovered(id: String) -> void:
	_status_tooltip_rtl.text = EnemyInspect.build_bbcode(id)
	_status_tooltip_rtl.visible = true
	var local_x: float = 0.0
	for node: Control in _status_tray.get_children():
		if node.has_meta("status_id") and str(node.get_meta("status_id")) == id:
			local_x = node.position.x
			break
	_status_tooltip_rtl.position = _panel.position + _status_tray.position + Vector2(local_x, StatusTray.ICON_SIZE + 4.0)

func _on_status_icon_unhovered() -> void:
	_status_tooltip_rtl.visible = false

func _on_player_turn_started() -> void:
	_close()

func _close() -> void:
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
