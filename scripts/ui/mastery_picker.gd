extends CanvasLayer

# Weapon Mastery Selection overlay — see docs/architecture/weapon-mastery-selection-design.md.
# Two modes, decided ONCE at open time from known_weapon_masteries.size() vs mastery_cap() (never
# re-derived mid-flow, so finishing Learn mode can never accidentally fall through into Swap mode):
#
# **Learn mode** (known < cap — character creation, or a level-up that raised the cap): sequential
# "pick 1 of 3" random tile rounds, one per missing slot, mandatory (no skip/Esc) — same icon-tile
# grid + styled hover-tooltip popup convention as spell_learn_picker.gd/cantrip_select.gd/
# invocation_picker.gd (direct owner request — make mastery picks "more roguelike" the same way).
#
# **Swap mode** (known == cap — the long-rest hub's "Weapon Masteries" option,
# mastery_reselect_prompt.gd): a grid of the player's OWN known masteries; click one to give it up,
# GameState.reroll_mastery() immediately rolls ONE random unknown replacement (no choice over what
# you get — the roguelike risk/reward beat), an in-panel "Lost X -> Gained Y" reveal line appears
# (blacksmith_panel.gd's own in-place-refresh-and-reveal convention, not a separate screen), and the
# tile grid refreshes so the player can keep swapping or stop via Esc/Done.
#
# character_creation_mode (set on the instance before add_child, default false): this is the
# POST-SPAWN onboarding pick — spawned by character_summary.gd's "Yes, I'm Ready!" once the
# character has already spawned into the run (class_selected == true), specifically so there is no
# "Back" button here to cheaply reroll a bad draw (direct owner request — undoing this rework's
# earlier "mastery pick happens before the final summary/confirm" order, which let a player spam
# Take Me Back -> reconfirm race select to keep re-rolling masteries for free). Learn mode routes
# onward on completion (Wizard/non-caster -> just finishes, Ranger -> cantrip_select.gd) instead of
# spawning character_summary.gd, which has already run by this point.

const TILE_SIZE: float = 168.0
const TILE_GAP: float = 16.0
const ICON_SIZE: float = 96.0
const COLS: int = 3
const MARGIN: float = 24.0
const TOOLTIP_W: float = 240.0
const MASTERY_ICON_FOLDER := "res://icons/masteries/"

const MASTERY_DESCRIPTIONS: Dictionary = {
	"Cleave": "If 2+ enemies are within melee reach, this attack also strikes the one closest to your primary target — with its own attack roll and damage roll.",
	"Graze": "On a miss, still deal damage equal to the ability modifier used for the attack (min 0).",
	"Nick": "While dual-wielding two Light weapons, make one further attack this turn — same rules as the Off-hand swing (max 3 attacks total).",
	"Push": "On a hit, the target rolls a CON save (DC 8 + Prof + DEX) or is shoved 1 tile directly away from you.",
	"Sap": "On a thrown hit, the target has Disadvantage on its very next attack, next turn.",
	"Slow": "On a hit, the target is Slowed — its next turn is skipped entirely, same as stepping into mud/water.",
	"Topple": "On a hit, the target rolls a CON save (DC 8 + Prof + STR) or is knocked Prone, skipping its entire next turn.",
	"Vex": "On a hit, gain Advantage on your next attack this round against the same target (any attack type).",
}

var character_creation_mode: bool = false

var _panel: Panel
var _tooltip: Panel
var _tooltip_rtl: RichTextLabel
var _mode: String = ""          # "learn" or "swap", decided once in _ready()
var _tile_row: Array[Control] = []       # Swap mode's tile row — rebuilt in place after a swap
var _reveal_rtl: RichTextLabel
var _hover_source_rect: Rect2 = Rect2()   # last-shown tile's global rect, for _process()'s hover-chain check

func _ready() -> void:
	layer = 25
	GameState.mastery_picker_open = true
	if character_creation_mode:
		# Defensive: guarantees a genuinely fresh Learn flow even if known_weapon_masteries somehow
		# carried anything over (there's no Back path back into this screen anymore, so this should
		# always be a no-op in practice).
		GameState.player_stats.known_weapon_masteries.clear()
		GameState.known_masteries_changed.emit()
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	_mode = "learn" if known.size() < GameState.player_stats.mastery_cap() else "swap"
	_build_ui()

func _build_ui() -> void:
	# Hidden before queue_free() (deferred) so a Learn-mode round-to-round rebuild never renders
	# the old, about-to-be-freed panel for a stray frame underneath the fresh one — same precedent
	# as cantrip_select.gd's own round-transition teardown.
	for child: Node in get_children():
		if child is CanvasItem:
			(child as CanvasItem).visible = false
		child.queue_free()
	_panel = null
	_tooltip = null
	_tooltip_rtl = null
	_reveal_rtl = null
	_tile_row.clear()

	var dim := ColorRect.new()
	dim.color = Color(0.0, 0.0, 0.0, 0.55)
	dim.anchor_right = 1.0
	dim.anchor_bottom = 1.0
	dim.mouse_filter = Control.MOUSE_FILTER_STOP
	add_child(dim)

	_panel = Panel.new()
	var sbox := StyleBoxFlat.new()
	sbox.bg_color = Color(0.07, 0.08, 0.13, 0.97)
	sbox.set_border_width_all(3)
	sbox.border_color = Color(0.78, 0.55, 0.22)
	sbox.set_corner_radius_all(8)
	_panel.add_theme_stylebox_override("panel", sbox)
	add_child(_panel)

	if _mode == "learn":
		_build_learn_ui()
	else:
		_build_swap_ui()

	_setup_tooltip()

# ── Learn mode ──────────────────────────────────────────────────────────────────────────────

func _build_learn_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	var unknown: Array[String] = []
	for m: String in Stats.ALL_WEAPON_MASTERIES:
		if not known.has(m):
			unknown.append(m)
	var pool: Array[String] = unknown.duplicate()
	Rng.shuffle(pool)
	var candidates: Array[String] = pool.slice(0, mini(COLS, pool.size()))
	var cols: int = mini(COLS, maxi(1, candidates.size()))
	var panel_w: float = MARGIN * 2.0 + cols * TILE_SIZE + (cols - 1) * TILE_GAP

	var title := Label.new()
	title.text = "Choose a Weapon Mastery"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 16.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 36.0)
	_panel.add_child(title)

	var hint := Label.new()
	hint.text = "This choice is permanent. Hover a tile for details."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 56.0)
	hint.size = Vector2(panel_w - MARGIN * 2.0, 28.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 96.0)
	sep.size = Vector2(panel_w - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 110.0
	for i: int in candidates.size():
		var col: int = i % cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0)
		_build_tile(candidates[i], pos, _on_learn_chosen)

	var panel_h: float = y0 + TILE_SIZE + 28.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)

func _on_learn_chosen(name: String) -> void:
	GameState.toggle_mastery(name)
	if GameState.player_stats.known_weapon_masteries.size() >= GameState.player_stats.mastery_cap():
		_finish_learn()
	else:
		_build_ui()

func _finish_learn() -> void:
	GameState.mastery_picker_open = false
	if character_creation_mode:
		# A caster class that also has known weapon masteries (currently only Ranger — Wizard's
		# mastery_cap() is 0, so it never reaches this picker with character_creation_mode set at
		# all) still needs its one-time starting-spell pick — cantrip_select.gd, generalized to
		# support a Ranger-only single-round mode (see that file's own header comment and
		# scripts/entities/CLAUDE.md's "Ranger class"). Otherwise the whole onboarding chain is
		# done (character_summary.gd already ran before this picker even opened) — snapshot the
		# finished character for "Try Again" and finish.
		if GameState.player_stats.caster != null:
			var spell_picker = load("res://scripts/ui/cantrip_select.gd").new()
			get_tree().root.call_deferred("add_child", spell_picker)
			queue_free()
			return
		GameState.snapshot_character_creation()
	queue_free()

# ── Swap mode ───────────────────────────────────────────────────────────────────────────────

func _build_swap_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	var cols: int = mini(COLS, maxi(1, known.size()))
	var rows: int = ceili(float(known.size()) / float(cols))
	var panel_w: float = MARGIN * 2.0 + cols * TILE_SIZE + (cols - 1) * TILE_GAP

	var title := Label.new()
	title.text = "Reselect a Weapon Mastery"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 16.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 36.0)
	_panel.add_child(title)

	var done_btn := Button.new()
	done_btn.text = "✓  Done  [Esc]"
	done_btn.size = Vector2(128.0, 30.0)
	done_btn.position = Vector2(panel_w - MARGIN - 128.0, 18.0)
	done_btn.focus_mode = Control.FOCUS_NONE
	done_btn.add_theme_font_size_override("font_size", 13)
	_style_btn(done_btn, Color(0.10, 0.22, 0.10), Color(0.28, 0.65, 0.28))
	done_btn.pressed.connect(_close)
	_panel.add_child(done_btn)

	var hint := Label.new()
	hint.text = "Pick one to give up — you'll gain a random new one in return. This can't be undone. Hover a tile for details."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 56.0)
	hint.size = Vector2(panel_w - MARGIN * 2.0, 28.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 96.0)
	sep.size = Vector2(panel_w - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 110.0
	_build_swap_tile_row(y0, cols)

	_reveal_rtl = RichTextLabel.new()
	_reveal_rtl.bbcode_enabled = true
	_reveal_rtl.fit_content = false
	_reveal_rtl.scroll_active = false
	_reveal_rtl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_reveal_rtl.add_theme_font_size_override("normal_font_size", 15)
	_reveal_rtl.position = Vector2(MARGIN, y0 + rows * (TILE_SIZE + TILE_GAP))
	_reveal_rtl.size = Vector2(panel_w - MARGIN * 2.0, 30.0)
	_panel.add_child(_reveal_rtl)

	var panel_h: float = y0 + rows * (TILE_SIZE + TILE_GAP) + 30.0 + 28.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)

func _build_swap_tile_row(y0: float, cols: int) -> void:
	for t: Control in _tile_row:
		t.visible = false
		t.queue_free()
	_tile_row.clear()
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	for i: int in known.size():
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_tile_row.append(_build_tile(known[i], pos, _on_discard))

func _on_discard(name: String) -> void:
	var new_name: String = GameState.reroll_mastery(name)
	if new_name == "":
		return
	_hide_tooltip()   # the tile that was just hovered/clicked is about to be freed below
	_reveal_rtl.text = "[color=#e05050]Lost %s[/color] → [color=#f2c94c]Gained %s![/color]" % [name, new_name]
	var known: Array[String] = GameState.player_stats.known_weapon_masteries
	var cols: int = mini(COLS, maxi(1, known.size()))
	var y0: float = 110.0
	_build_swap_tile_row(y0, cols)

func _close() -> void:
	GameState.mastery_picker_open = false
	queue_free()

# ── Shared tile builder (icon + name, hover tooltip) ───────────────────────────────────────

func _build_tile(name: String, pos: Vector2, on_click: Callable) -> Control:
	var tile := Button.new()
	tile.position = pos
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.focus_mode = Control.FOCUS_NONE
	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.10, 0.11, 0.17)
	normal.set_border_width_all(2)
	normal.border_color = Color(0.30, 0.30, 0.38)
	normal.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("normal", normal)
	var hover := StyleBoxFlat.new()
	hover.bg_color = Color(0.10, 0.11, 0.17).lightened(0.08)
	hover.set_border_width_all(3)
	hover.border_color = Color(1.0, 0.82, 0.22)
	hover.set_corner_radius_all(6)
	tile.add_theme_stylebox_override("hover", hover)
	tile.pressed.connect(func() -> void: on_click.call(name))
	var tooltip_text: String = "[b]%s[/b]\n\n%s" % [name, MASTERY_DESCRIPTIONS.get(name, "")]
	tile.mouse_entered.connect(func() -> void: _show_tooltip(tooltip_text, tile))
	_panel.add_child(tile)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((TILE_SIZE - ICON_SIZE) * 0.5, 12.0)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	var icon_path: String = MASTERY_ICON_FOLDER + name.to_lower() + ".png"
	if ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	tile.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = name
	name_lbl.add_theme_font_size_override("font_size", 16)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position = Vector2(6.0, ICON_SIZE + 18.0)
	name_lbl.size = Vector2(TILE_SIZE - 12.0, TILE_SIZE - ICON_SIZE - 26.0)
	tile.add_child(name_lbl)

	return tile

# ── Hover tooltip (reuses the same styled panel every other spell/mastery readout in the game
# uses, hud.gd's _setup_quickbar_tooltip()'s own bg/border convention — not a native tooltip_text).
# Rebuilt every _build_ui() call (Learn mode's round-to-round rebuild tears down the whole tree). ──

func _setup_tooltip() -> void:
	_tooltip = Panel.new()
	_tooltip.visible = false
	_tooltip.z_index = 30
	_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.50, 0.35)
	sb.set_corner_radius_all(3)
	_tooltip.add_theme_stylebox_override("panel", sb)
	_tooltip_rtl = RichTextLabel.new()
	_tooltip_rtl.bbcode_enabled = true
	_tooltip_rtl.fit_content = true
	_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_tooltip_rtl.offset_left = 8.0
	_tooltip_rtl.offset_top = 6.0
	_tooltip_rtl.offset_right = -8.0
	_tooltip_rtl.offset_bottom = -6.0
	_tooltip.add_child(_tooltip_rtl)
	add_child(_tooltip)

func _show_tooltip(text: String, tile: Control) -> void:
	_tooltip_rtl.text = text
	var w: float = TOOLTIP_W
	_tooltip_rtl.size = Vector2(w, 0)
	_hover_source_rect = Rect2(tile.global_position, tile.size)
	var vp: Vector2 = get_viewport().get_visible_rect().size
	# BUGFIX: th was computed for the position calc below but never actually applied to
	# _tooltip.size — the panel stayed pinned at its 60px placeholder height regardless of how
	# tall the text actually was, so a long mastery description visibly overflowed/got clipped by
	# its own background box ("bubble too small for the text").
	var th: float = maxf(60.0, _tooltip_rtl.get_content_height() + 12.0)
	_tooltip.size = Vector2(w + 16.0, th)
	_tooltip.visible = true
	var tx: float = clampf(_hover_source_rect.position.x, 4.0, vp.x - (w + 16.0) - 4.0)
	# Anchored ABOVE the tile — same convention as the spell/invocation pickers.
	var ty: float = _hover_source_rect.position.y - th - 8.0
	if ty < 4.0:
		ty = _hover_source_rect.position.y + _hover_source_rect.size.y + 8.0
	_tooltip.position = Vector2(tx, ty)

func _hide_tooltip() -> void:
	if _tooltip != null:
		_tooltip.visible = false

## Hiding is driven entirely by this per-frame hover-chain check, not mouse_exited — a tile's own
## mouse_exited fires the instant the cursor leaves it, even when heading straight up INTO the
## tooltip that sits just above it, which used to make the popup disappear before the mouse could
## ever reach it. Keeping it open while the mouse is over either the source tile OR the tooltip
## itself (same "hover chain" convention as hud.gd's own qbar tooltip) also means a longer
## description that needs scanning, or a future hoverable keyword inside one, won't vanish out
## from under the cursor.
func _process(_delta: float) -> void:
	if _tooltip == null or not _tooltip.visible:
		return
	var mp: Vector2 = get_viewport().get_mouse_position()
	var over_tooltip := Rect2(_tooltip.global_position, _tooltip.size).has_point(mp)
	if not _hover_source_rect.has_point(mp) and not over_tooltip:
		_tooltip.visible = false

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

func _unhandled_input(event: InputEvent) -> void:
	if _mode == "learn":
		# Mandatory round, same as every spell-pick picker — swallow all key input, no Esc close.
		if event is InputEventKey:
			get_viewport().set_input_as_handled()
		return
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if not key.pressed or key.echo:
		return
	if key.physical_keycode == KEY_ESCAPE:
		get_viewport().set_input_as_handled()
		_close()
