extends CanvasLayer

# Long-rest adjustments hub — shown once right after a completed long rest (see GameState.long_rest()
# and player.gd's short_rest_active completion branch). Originally a plain Yes/No "reselect
# masteries?" prompt; now a small hub offering every long-rest-gated adjustment the player might
# want to make in one place: Weapon Masteries, Attunement, and (casters only) the Spellbook.
# Reuses GameState.mastery_picker_open as the generic "a long-rest picker is open" input-blocking
# flag for the hub's own lifetime — opening a sub-picker hides this panel (not queue_free — the hub
# stays alive so "Done" from a sub-picker returns here instead of closing everything at once) and
# re-shows it once that sub-picker's tree_exited fires. Each sub-picker still owns its own
# GameState.*_open flag independently (mastery_picker.gd/attunement_picker.gd both also set
# mastery_picker_open themselves — redundant but harmless; spellbook_overlay.gd uses its own
# spellbook_open flag, untouched by this hub).
#
# Weapon Masteries reselect is limited to ONE per long-rest cycle (direct owner request): once
# mastery_picker.gd's Swap mode completes a single discard+pick round, it sets
# GameState.mastery_reselect_used_this_long_rest = true and closes straight back to this hub
# instead of looping for another swap. `_build_ui()` greys out the "Weapon Masteries" button
# (label gains " (used)") whenever that flag is set; GameState.long_rest() resets it to false.

var _panel: Panel

func _ready() -> void:
	layer = 26
	GameState.mastery_picker_open = true
	_build_ui()

func _build_ui() -> void:
	_panel = Panel.new()
	_panel.size = Vector2(360.0, 230.0)
	var vp := get_viewport().get_visible_rect().size
	_panel.position = (vp - _panel.size) * 0.5
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(2)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(6)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	var title := Label.new()
	title.text = "Adjust your character?"
	title.autowrap_mode = TextServer.AUTOWRAP_WORD
	title.add_theme_font_size_override("font_size", 18)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	title.size = Vector2(320.0, 30.0)
	title.position = Vector2(20.0, 14.0)
	_panel.add_child(title)

	var y: float = 54.0
	if GameState.player_stats.mastery_cap() > 0:
		var masteries_used: bool = GameState.mastery_reselect_used_this_long_rest
		var masteries_label: String = "Weapon Masteries" + (" (used)" if masteries_used else "")
		_add_option_btn(masteries_label, y, _open_masteries, masteries_used)
		y += 46.0
	_add_option_btn("Attunement", y, _open_attunements)
	y += 46.0
	if GameState.player_stats.caster != null:
		_add_option_btn("Spellbook", y, _open_spellbook)
		y += 46.0
	if GameState.is_high_elf_caster():
		_add_option_btn("High Elf Cantrip Swap", y, _open_high_elf_swap)
		y += 46.0
	y += 8.0

	var done_btn := Button.new()
	done_btn.text = "Done  [Esc]"
	done_btn.size = Vector2(320.0, 40.0)
	done_btn.position = Vector2(20.0, y)
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.pressed.connect(_on_done)
	_panel.add_child(done_btn)
	y += 40.0 + 16.0

	_panel.size = Vector2(360.0, y)
	_panel.position = (vp - _panel.size) * 0.5

func _add_option_btn(text: String, y: float, callback: Callable, disabled: bool = false) -> void:
	var btn := Button.new()
	btn.text = text
	btn.size = Vector2(320.0, 40.0)
	btn.position = Vector2(20.0, y)
	btn.focus_mode = Control.FOCUS_NONE
	btn.disabled = disabled
	btn.pressed.connect(callback)
	_panel.add_child(btn)

func _open_masteries() -> void:
	_open_subpicker(load("res://scripts/ui/mastery_picker.gd").new())

func _open_attunements() -> void:
	_open_subpicker(load("res://scripts/ui/attunement_picker.gd").new())

func _open_spellbook() -> void:
	_open_subpicker(load("res://scripts/ui/spellbook_overlay.gd").new())

func _open_high_elf_swap() -> void:
	_open_subpicker(load("res://scripts/ui/high_elf_cantrip_swap.gd").new())

func _open_subpicker(sub: Node) -> void:
	_panel.visible = false
	get_tree().root.add_child(sub)
	sub.tree_exited.connect(_on_subpicker_closed)

func _on_subpicker_closed() -> void:
	if not is_inside_tree():
		return  # the hub itself was freed (e.g. Done clicked while a sub-picker was open)
	# The sub-picker's own _close() just cleared this flag on its way out — restore it since the
	# hub is still up and should keep blocking input until its own Done/Esc is pressed.
	GameState.mastery_picker_open = true
	# Rebuild (not just re-show) — a mastery swap may have just flipped
	# mastery_reselect_used_this_long_rest, and the button's disabled state needs to reflect that
	# the instant we're back, not only on the hub's next fresh spawn.
	_panel.queue_free()
	_build_ui()

func _on_done() -> void:
	GameState.mastery_picker_open = false
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	if not _panel.visible:
		return  # a sub-picker is open and owns input right now
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_on_done()
