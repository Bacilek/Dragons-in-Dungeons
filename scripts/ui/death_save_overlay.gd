extends CanvasLayer

# Death save overlay — full-screen dramatic BG3-style roll animation, spawned by
# hud.gd._on_death_save_started() on GameState.death_save_started, driven entirely off
# GameState.death_save_rolled/death_save_finished (see GameState.begin_death_save_sequence()).
# layer = 30 — above every other overlay in the game (Debug Panel/short rest/talent picker all
# sit at 25, Game Over at 10) so it genuinely reads as "everything else stopped." No .tscn — built
# entirely in code, same convention as subclass_select.gd/mastery_picker.gd.

const OUTCOME_TEXT: Dictionary = {
	"critfail": "CRITICAL FAILURE",
	"fail": "FAILURE",
	"success": "SUCCESS",
	"critsuccess": "CRITICAL SUCCESS",
}
const OUTCOME_COLOR: Dictionary = {
	"critfail": Color(1.0, 0.2, 0.2),
	"fail": Color(0.85, 0.4, 0.3),
	"success": Color(0.5, 0.9, 0.6),
	"critsuccess": Color(0.4, 1.0, 0.5),
}

var _die_label: RichTextLabel
var _outcome_label: RichTextLabel
var _success_pips: RichTextLabel
var _failure_pips: RichTextLabel
var _verdict_label: RichTextLabel
var _rolling_tween: Tween

func _ready() -> void:
	layer = 30
	_build_ui()
	GameState.death_save_rolled.connect(_on_rolled)
	GameState.death_save_finished.connect(_on_finished)
	_show_rolling()

func _build_ui() -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size

	var dim := ColorRect.new()
	dim.color = Color(0.03, 0.03, 0.03, 0.85)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	var title := RichTextLabel.new()
	title.bbcode_enabled = true
	title.fit_content = true
	title.scroll_active = false
	title.mouse_filter = Control.MOUSE_FILTER_IGNORE
	title.text = "[center][color=#c94a4a][b]DEATH SAVING THROW[/b][/color][/center]"
	title.add_theme_font_size_override("normal_font_size", 30)
	title.add_theme_font_size_override("bold_font_size", 30)
	title.position = Vector2(vp.x / 2.0 - 260, vp.y / 2.0 - 220)
	title.size = Vector2(520, 44)
	add_child(title)

	_die_label = RichTextLabel.new()
	_die_label.bbcode_enabled = true
	_die_label.fit_content = true
	_die_label.scroll_active = false
	_die_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_die_label.add_theme_font_size_override("normal_font_size", 110)
	_die_label.add_theme_font_size_override("bold_font_size", 110)
	_die_label.position = Vector2(vp.x / 2.0 - 150, vp.y / 2.0 - 150)
	_die_label.size = Vector2(300, 150)
	add_child(_die_label)

	_outcome_label = RichTextLabel.new()
	_outcome_label.bbcode_enabled = true
	_outcome_label.fit_content = true
	_outcome_label.scroll_active = false
	_outcome_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_outcome_label.add_theme_font_size_override("normal_font_size", 22)
	_outcome_label.add_theme_font_size_override("bold_font_size", 22)
	_outcome_label.position = Vector2(vp.x / 2.0 - 260, vp.y / 2.0 + 6)
	_outcome_label.size = Vector2(520, 34)
	add_child(_outcome_label)

	_success_pips = RichTextLabel.new()
	_success_pips.bbcode_enabled = true
	_success_pips.fit_content = true
	_success_pips.scroll_active = false
	_success_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_success_pips.add_theme_font_size_override("normal_font_size", 26)
	_success_pips.position = Vector2(vp.x / 2.0 - 260, vp.y / 2.0 + 60)
	_success_pips.size = Vector2(520, 36)
	add_child(_success_pips)

	_failure_pips = RichTextLabel.new()
	_failure_pips.bbcode_enabled = true
	_failure_pips.fit_content = true
	_failure_pips.scroll_active = false
	_failure_pips.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_failure_pips.add_theme_font_size_override("normal_font_size", 26)
	_failure_pips.position = Vector2(vp.x / 2.0 - 260, vp.y / 2.0 + 100)
	_failure_pips.size = Vector2(520, 36)
	add_child(_failure_pips)

	_verdict_label = RichTextLabel.new()
	_verdict_label.bbcode_enabled = true
	_verdict_label.fit_content = true
	_verdict_label.scroll_active = false
	_verdict_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_verdict_label.add_theme_font_size_override("normal_font_size", 26)
	_verdict_label.add_theme_font_size_override("bold_font_size", 26)
	_verdict_label.position = Vector2(vp.x / 2.0 - 260, vp.y / 2.0 + 150)
	_verdict_label.size = Vector2(520, 40)
	add_child(_verdict_label)

	_refresh_pips(0, 0)

func _refresh_pips(successes: int, failures: int) -> void:
	var succ_pips: String = ""
	for i: int in range(3):
		succ_pips += "[color=#5ee87a]●[/color] " if i < successes else "[color=#3a3a3a]○[/color] "
	var fail_pips: String = ""
	for i: int in range(3):
		fail_pips += "[color=#e85e5e]●[/color] " if i < failures else "[color=#3a3a3a]○[/color] "
	_success_pips.text = "[center][color=#aaaaaa]Successes[/color]  %s[/center]" % succ_pips
	_failure_pips.text = "[center][color=#aaaaaa]Failures[/color]  %s[/center]" % fail_pips

func _show_rolling() -> void:
	_outcome_label.text = ""
	if _rolling_tween != null and _rolling_tween.is_valid():
		_rolling_tween.kill()
	_die_label.modulate.a = 1.0
	_die_label.text = "[center][color=#888888]?[/color][/center]"
	_rolling_tween = create_tween().set_loops()
	_rolling_tween.tween_property(_die_label, "modulate:a", 0.35, 0.4)
	_rolling_tween.tween_property(_die_label, "modulate:a", 1.0, 0.4)

func _on_rolled(die: int, result: String, successes: int, failures: int) -> void:
	if _rolling_tween != null and _rolling_tween.is_valid():
		_rolling_tween.kill()
	_die_label.modulate.a = 1.0
	var color: Color = OUTCOME_COLOR.get(result, Color.WHITE)
	_die_label.text = "[center][color=#%s][b]%d[/b][/color][/center]" % [color.to_html(false), die]
	_outcome_label.text = "[center][color=#%s][b]%s[/b][/color][/center]" % [color.to_html(false), OUTCOME_TEXT.get(result, "")]
	_refresh_pips(successes, failures)
	var sequence_over: bool = result == "critsuccess" or successes >= 3 or failures >= 3
	if sequence_over:
		if result == "critsuccess" or successes >= 3:
			_verdict_label.text = "[center][color=#5ee87a][b]Stabilizing...[/b][/color][/center]"
		else:
			_verdict_label.text = "[center][color=#e85e5e][b]Your journey ends here.[/b][/color][/center]"
	else:
		_verdict_label.text = ""
		# Another roll is coming — resume the pulsing "?" placeholder after a brief beat so the
		# just-rolled number/outcome has time to actually be read before it's replaced.
		await get_tree().create_timer(0.5).timeout
		if is_instance_valid(self) and GameState.is_dying:
			_show_rolling()

func _on_finished(_revived: bool) -> void:
	queue_free()
