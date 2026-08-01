extends CanvasLayer

# Starting-spell pick, shared by Wizard AND Ranger (both non-MARTIAL per Stats.CLASS_ROLE — see
# scripts/entities/CLAUDE.md's "Ranger class"/"Wizard spellcasting" sections). Modeled on
# mastery_picker.gd's overlay/panel styling, but card-click commits immediately
# (subclass_select.gd's style) since there's no multi-select within a round.
#
# **Wizard** (FULL_CASTER, mastery_cap() == 0 — spawned by race_select.gd right after race
# confirm, in place of the Mastery Picker): TWO rounds (owner-requested: one cantrip AND one
# level-1 spell, not two cantrips). Round 1 "pick 1 of 3" always offers the fixed cantrip trio
# (SpellDb.STARTER_CANTRIP_IDS — unchanged so the premade Jace's "cantrip": "fire_bolt" shortcut
# and old saves stay valid) via GameState.choose_cantrip(), which also auto-assigns the pick into
# the Special quick-cast slot; on that pick, this same script re-builds itself for round 2,
# "pick 1 of 2" from the fixed level-1 starting pair (Magic Missile, Shield) via
# GameState.choose_starting_spell(). Round 2's pick closes the picker for good.
#
# **Ranger** (HALF_CASTER, mastery_cap() == 2 > 0 — spawned by mastery_picker.gd's _close() right
# after its own mastery pick, since Ranger needs both onboarding steps and mastery selection
# already claims the "Wizard's cantrip-slot substitute" branch in race_select.gd): a single round,
# "pick 1 of up to 3" random level-1 candidates from SpellDb.RANGER_SPELL_IDS (no cantrip round —
# Rangers get none, see cantrip_max()) via GameState.choose_starting_spell() directly. `_round`
# uses the sentinel value RANGER_ROUND so `_build_ui()`/`_on_chosen()`/`_on_back()` can each tell
# it apart from Wizard's rounds 1/2 with one added branch, rather than a whole second parallel
# script. **Content-count caveat**: `RANGER_SPELL_IDS` only has ONE entry today (Fog Cloud — every
# other implemented spell's real class list is Sorcerer/Wizard(/Warlock), not Ranger; see that
# const's own comment in spell_db.gd), so this "pick 1 of 3" in practice renders a single card
# until more Ranger-eligible spell content exists — `_roll_ranger_candidates()` already handles any
# candidate count from 0 upward gracefully, no special-casing needed here.

const TILE_SIZE: float = 168.0
const TILE_GAP: float = 16.0
const ICON_SIZE: float = 96.0
const COLS: int = 3
const MARGIN: float = 24.0
const STARTING_SPELL_IDS: Array[String] = ["magic_missile", "shield"]
const RANGER_ROUND: int = 3   # sentinel _round value — see header comment above

var _panel: Panel
var _round: int = 1
var _candidates: Array[String] = []
var _back_btn: Button
var _is_ranger: bool = false
# Warlock (FULL_CASTER, mastery_cap() == 0 like Wizard — spawned by the same race_select.gd
# branch): a single round, "pick 1 of 3" from SpellDb.WARLOCK_STARTER_CANTRIP_IDS via
# GameState.choose_cantrip(), then closes straight to the summary screen — no round-2 level-1
# spell pick (Warlock's leveled spells grow via the normal level-up spell-learn picker instead,
# same as Ranger — see scripts/entities/CLAUDE.md's "Warlock class").
var _is_warlock: bool = false

func _ready() -> void:
	layer = 25
	GameState.cantrip_picker_open = true
	_is_ranger = GameState.player_stats.character_class == Stats.CharacterClass.RANGER
	_is_warlock = GameState.player_stats.character_class == Stats.CharacterClass.WARLOCK
	# Wipes any previous cantrip/starting-spell pick from an earlier pass through this screen —
	# covers both being re-opened fresh via character_summary.gd's "Take me back" and this
	# instance's own round-2-back-to-round-1 rebuild (see _on_back()). No-op on a truly first-ever
	# visit (nothing granted yet). Without this, re-picking here would leave the OLD pick known
	# alongside the new one, since choose_cantrip()/choose_starting_spell() only ever append.
	GameState.reset_wizard_onboarding_picks()
	if _is_ranger:
		_round = RANGER_ROUND
		_candidates = _roll_ranger_candidates()
	elif _is_warlock:
		_candidates = SpellDb.WARLOCK_STARTER_CANTRIP_IDS.duplicate()
	else:
		_candidates = SpellDb.STARTER_CANTRIP_IDS.duplicate()
	_build_ui()

# 3 random level-1 candidates from Ranger's shared spell pool (SpellDb.RANGER_SPELL_IDS) — mirrors
# the "pick 1 of 3" shape of Wizard's own round 1, just drawn randomly instead of a fixed trio
# since Ranger has no small hand-picked starter set of its own.
func _roll_ranger_candidates() -> Array[String]:
	var level1: Array[String] = []
	for sid: String in SpellDb.RANGER_SPELL_IDS:
		var s: Spell = SpellDb.get_spell(sid)
		if s != null and s.level == 1:
			level1.append(sid)
	Rng.shuffle(level1)
	return level1.slice(0, mini(3, level1.size()))

func _build_ui() -> void:
	var vp := get_viewport().get_visible_rect().size
	var cols: int = mini(COLS, maxi(1, _candidates.size()))
	var rows: int = ceili(float(_candidates.size()) / float(cols))
	var panel_w: float = MARGIN * 2.0 + cols * TILE_SIZE + (cols - 1) * TILE_GAP

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

	var title := Label.new()
	title.text = "Choose Your Starting Cantrip" if _round == 1 else "Choose Your Starting Spell"
	title.add_theme_font_size_override("font_size", 26)
	title.add_theme_color_override("font_color", Color(1.0, 0.82, 0.22))
	title.position = Vector2(MARGIN, 14.0)
	title.size = Vector2(panel_w - MARGIN * 2.0, 34.0)
	_panel.add_child(title)

	_back_btn = Button.new()
	_back_btn.text = "← Back"
	_back_btn.size = Vector2(90.0, 28.0)
	_back_btn.position = Vector2(panel_w - MARGIN - 90.0, 16.0)
	_back_btn.focus_mode = Control.FOCUS_NONE
	_back_btn.add_theme_font_size_override("font_size", 13)
	var back_normal := StyleBoxFlat.new()
	back_normal.bg_color = Color(0.14, 0.12, 0.10)
	back_normal.set_border_width_all(1)
	back_normal.border_color = Color(0.5, 0.45, 0.35)
	back_normal.set_corner_radius_all(3)
	_back_btn.add_theme_stylebox_override("normal", back_normal)
	var back_hover := StyleBoxFlat.new()
	back_hover.bg_color = Color(0.14, 0.12, 0.10).lightened(0.12)
	back_hover.set_corner_radius_all(3)
	_back_btn.add_theme_stylebox_override("hover", back_hover)
	_back_btn.pressed.connect(_on_back)
	_panel.add_child(_back_btn)

	var hint := Label.new()
	hint.text = "This choice is permanent. Hover a tile for details."
	hint.add_theme_font_size_override("font_size", 14)
	hint.add_theme_color_override("font_color", Color(0.65, 0.65, 0.70))
	hint.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	hint.position = Vector2(MARGIN, 50.0)
	hint.size = Vector2(panel_w - MARGIN * 2.0, 24.0)
	_panel.add_child(hint)

	var sep := HSeparator.new()
	sep.position = Vector2(12.0, 80.0)
	sep.size = Vector2(panel_w - 24.0, 2.0)
	_panel.add_child(sep)

	var y0: float = 92.0
	for i: int in _candidates.size():
		var spell: Spell = SpellDb.get_spell(_candidates[i])
		var col: int = i % cols
		var row: int = i / cols
		var pos := Vector2(MARGIN + col * (TILE_SIZE + TILE_GAP), y0 + row * (TILE_SIZE + TILE_GAP))
		_build_tile(spell, pos)

	var panel_h: float = y0 + rows * (TILE_SIZE + TILE_GAP) - TILE_GAP + 20.0
	_panel.size = Vector2(panel_w, panel_h)
	_panel.position = Vector2((vp.x - panel_w) * 0.5, (vp.y - panel_h) * 0.5)

func _build_tile(spell: Spell, pos: Vector2) -> void:
	var tile := Button.new()
	tile.position = pos
	tile.size = Vector2(TILE_SIZE, TILE_SIZE)
	tile.focus_mode = Control.FOCUS_NONE
	tile.tooltip_text = SpellTooltip.build_plain(spell)
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
	tile.pressed.connect(func() -> void: _on_chosen(spell.spell_id))
	_panel.add_child(tile)

	var icon := TextureRect.new()
	icon.ignore_texture_size = true
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	icon.position = Vector2((TILE_SIZE - ICON_SIZE) * 0.5, 12.0)
	icon.size = Vector2(ICON_SIZE, ICON_SIZE)
	if ResourceLoader.exists(spell.icon_path):
		icon.texture = load(spell.icon_path)
	tile.add_child(icon)

	var name_lbl := Label.new()
	name_lbl.text = spell.spell_name
	name_lbl.add_theme_font_size_override("font_size", 15)
	name_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_TOP
	name_lbl.autowrap_mode = TextServer.AUTOWRAP_WORD_SMART
	name_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	name_lbl.position = Vector2(6.0, ICON_SIZE + 18.0)
	name_lbl.size = Vector2(TILE_SIZE - 12.0, TILE_SIZE - ICON_SIZE - 26.0)
	tile.add_child(name_lbl)

func _on_chosen(spell_id: String) -> void:
	if _round == 1 and not _is_warlock:
		GameState.choose_cantrip(spell_id)
		# Round 2: the fixed level-1 starting pair — reuse this same script/scene rather than a
		# second file, just re-seed round/_candidates and rebuild.
		_round = 2
		_candidates = STARTING_SPELL_IDS.duplicate()
		# queue_free() (not free()) — this runs from inside a card Button's own "pressed" signal,
		# so the old nodes must be torn down deferred, not synchronously. Hide immediately so the
		# freshly-built round-2 panel doesn't render on top of a visible stale round-1 one for a frame.
		for child: Node in get_children():
			if child is CanvasItem:
				(child as CanvasItem).visible = false
			child.queue_free()
		_panel = null
		_build_ui()
		return
	if _is_warlock:
		GameState.choose_cantrip(spell_id)
	else:
		GameState.choose_starting_spell(spell_id)
	GameState.cantrip_picker_open = false
	GameState.pending_summary_return_scene = "res://scripts/ui/cantrip_select.gd"
	var summary = load("res://scripts/ui/character_summary.gd").new()
	get_tree().root.call_deferred("add_child", summary)
	queue_free()

func _on_back() -> void:
	if _round == 2:
		# Undo round 1's cantrip pick before letting the player redo it — same queue_free/rebuild
		# pattern _on_chosen() already uses for the forward round-1-to-round-2 transition.
		GameState.reset_wizard_onboarding_picks()
		_round = 1
		_candidates = SpellDb.STARTER_CANTRIP_IDS.duplicate()
		for child: Node in get_children():
			if child is CanvasItem:
				(child as CanvasItem).visible = false
			child.queue_free()
		_panel = null
		_build_ui()
		return
	GameState.cantrip_picker_open = false
	if _is_ranger:
		# Ranger reached this screen from mastery_picker.gd (not race_select.gd directly — see
		# this file's header comment), so Back has to return there, not to race select.
		GameState.reset_wizard_onboarding_picks()
		var mastery = load("res://scripts/ui/mastery_picker.gd").new()
		mastery.character_creation_mode = true
		get_tree().root.call_deferred("add_child", mastery)
		queue_free()
		return
	var race_picker = load("res://scripts/ui/race_select.gd").new()
	get_tree().root.call_deferred("add_child", race_picker)
	queue_free()

func _unhandled_input(event: InputEvent) -> void:
	# Mandatory one-time choice — swallow all key input (no Esc close).
	if event is InputEventKey:
		get_viewport().set_input_as_handled()
