class_name HuntersMarkIndicator
extends Panel

# Ranger's Hunter's Mark: always-know-direction-even-out-of-LOS tracking widget. Mirrors
# compass.gd's arrow-glyph pattern exactly, but visibility is driven by "is a target currently
# marked" instead of a one-shot discovery flag — see scripts/entities/player_ranger_talents.gd.

var _arrow_label: Label
var _dist_label: Label

func _ready() -> void:
	anchor_left = 0.5
	anchor_right = 0.5
	offset_left = -180.0
	offset_top = 4.0
	offset_right = -70.0
	offset_bottom = 84.0
	visible = false

	var title_lbl := Label.new()
	title_lbl.text = "Mark"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.8, 0.3, 0.3))
	title_lbl.position = Vector2(0.0, 2.0)
	title_lbl.size = Vector2(110.0, 18.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(title_lbl)

	_arrow_label = Label.new()
	_arrow_label.text = "?"
	_arrow_label.add_theme_font_size_override("font_size", 36)
	_arrow_label.add_theme_color_override("font_color", Color(0.9, 0.4, 0.4))
	_arrow_label.position = Vector2(0.0, 20.0)
	_arrow_label.size = Vector2(110.0, 44.0)
	_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_arrow_label)

	_dist_label = Label.new()
	_dist_label.text = ""
	_dist_label.add_theme_font_size_override("font_size", 11)
	_dist_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_dist_label.position = Vector2(0.0, 64.0)
	_dist_label.size = Vector2(110.0, 14.0)
	_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	add_child(_dist_label)

func update_display() -> void:
	var target: Enemy = GameState.player_stats.hunters_mark_target
	if target == null or not is_instance_valid(target) or target.stats.is_dead():
		visible = false
		return
	visible = true
	var diff: Vector2i = target.grid_pos - GameState.player_grid_pos
	if diff == Vector2i.ZERO:
		_arrow_label.text = "★"
		_dist_label.text = "here!"
		return
	var ax: int = absi(diff.x)
	var ay: int = absi(diff.y)
	var arrow: String
	if ax > ay * 2:
		arrow = "→" if diff.x > 0 else "←"
	elif ay > ax * 2:
		arrow = "↓" if diff.y > 0 else "↑"
	elif diff.x > 0 and diff.y > 0:
		arrow = "↘"
	elif diff.x > 0 and diff.y < 0:
		arrow = "↗"
	elif diff.x < 0 and diff.y > 0:
		arrow = "↙"
	else:
		arrow = "↖"
	_arrow_label.text = arrow
	var dist: int = maxi(ax, ay)
	_dist_label.text = "%d tiles" % dist

func reset_for_new_floor() -> void:
	visible = false
