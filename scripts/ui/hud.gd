extends CanvasLayer

@onready var floor_label: Label       = $StatsPanel/FloorLabel
@onready var hp_fill: ColorRect       = $StatsPanel/HPFill
@onready var hp_label: Label          = $StatsPanel/HPLabel
@onready var exp_fill: ColorRect      = $StatsPanel/EXPFill
@onready var exp_label: Label         = $StatsPanel/EXPLabel
@onready var level_label: Label       = $StatsPanel/LevelLabel
@onready var portrait: TextureButton  = $StatsPanel/Portrait
@onready var log_label: RichTextLabel = $LogPanel/LogLabel
@onready var stats_popup: Panel       = $StatsPopup
@onready var wait_button: Button      = $ActionBar/WaitButton
@onready var search_button: Button    = $ActionBar/SearchButton
@onready var interact_button: Button  = $ActionBar/InteractButton
@onready var mute_button: Button      = $MuteButton

const BAR_W: float    = 320.0
const HP_BAR_H: float = 38.0
const THP_BAR_H: float = 6.0   # temp HP bar above HP fill
const EXP_BAR_H: float = 24.0
const SLOT_COUNT: int = 9

var _item_slots: Array[Button] = []
var _slot_qty_labels: Array[Label] = []
var _slot_num_labels: Array[Label] = []  # 1-9 hotkey number, top-left corner of each slot
var _log_messages: Array[String] = []
const MAX_LOG_MESSAGES: int = 25
var _food_value_label: Label  # shows total FOOD food_value (long rest fuel), see GameState.total_food_value()
var _temp_hp_fill: ColorRect  # light-blue temp HP bar above the HP fill
var _status_tray: StatusTray  # status/buff/debuff/passive icon row under the portrait
var _inventory_overlay_ref: Node = null
var _debug_panel_ref: Node = null
var _hit_dice_label: Label
var _short_rest_label: RichTextLabel  # BG3-style pip row: short rests remaining this long-rest cycle
var _gold_label: Label        # gold counter (coin icon + amount), wired to GameState.gold_changed
var _spell_slots_label: RichTextLabel  # always-visible per-level spell slot remaining/max (Wizard only)

# ── In-bar reorder drag (item quickbar OR ability bar, no overlay needed) ─────────────────────
# Press-and-drag an ActionBar slot onto another slot of the SAME bar to move it there — e.g. drag
# slot 1 onto slot 5. Independent of spellbook_overlay.gd's own drag (which targets these same
# Button rects from a different CanvasLayer); disabled while the Spellbook is open to avoid the
# two systems fighting over the same press.
const BAR_DRAG_THRESHOLD: float = 8.0
var _bar_drag_from: int = -1
var _bar_dragging: bool = false
var _bar_drag_start_pos: Vector2 = Vector2.ZERO
var _bar_drag_icon: TextureRect = null
var _compass: Compass
var _hunters_mark_indicator: HuntersMarkIndicator
var _crit_banner: CritBanner

# ── Ability bar toggle ────────────────────────────────────────────────────────
var _ability_bar_mode: bool = false  # false = items, true = abilities
var _bar_mode_label: Label           # shows "ITEMS" / "ABILITIES [Tab]"
var _slot_use_labels: Array[Label] = []  # ability uses remaining badges

# ── Log tooltip ───────────────────────────────────────────────────────────────
var _log_tooltip: Panel = null
var _log_tooltip_rtl: RichTextLabel = null
var _log_tooltip_visible: bool = false

# ── Quickbar slot hover tooltip ────────────────────────────────────────────────
var _qbar_tooltip: Panel = null
var _qbar_tooltip_rtl: RichTextLabel = null
# Global-space rect of whatever slot/icon is currently showing _qbar_tooltip — the tooltip is
# anchored to this (computed once at hover-start), not the mouse; hovering this rect keeps the
# whole popup chain alive. See "Quickbar hover tooltip" section near _setup_quickbar_tooltip().
var _qbar_hover_source_rect: Rect2 = Rect2()
var _glossary_popup: Panel = null
var _glossary_rtl: RichTextLabel = null
var _glossary_popup2: Panel = null
var _glossary_rtl2: RichTextLabel = null
# Grace period (seconds) the hover chain below tolerates the mouse being outside every rect in the
# chain before actually hiding anything — without this, a single frame spent crossing the visual
# gap between a trigger icon and its tooltip box (e.g. the status tray, whose icons sit right above
# a tooltip that opens a few px below them) reads as "left the chain" and closes it, making it feel
# like the tooltip can never be reached on the first try. Reset to 0 the instant the mouse re-enters
# any part of the chain; only once it's been continuously outside for longer than this does the
# chain actually hide.
const _HOVER_CHAIN_HIDE_GRACE_SEC: float = 0.2
var _hover_chain_outside_time: float = 0.0

# ── Extra popup labels (added programmatically to expand the stats popup) ─────
var _popup_prof_label: Label = null
var _popup_int_label: Label = null
var _popup_wis_label: Label = null
var _popup_cha_label: Label = null

# ── Always-visible AC label in StatsPanel ────────────────────────────────────
var _ac_label: Label = null

const CLASS_PORTRAIT: Dictionary = {
	Stats.CharacterClass.BARBARIAN: "res://sprites/characters/classes/Barbarian/idle_1.png",
	Stats.CharacterClass.RANGER:    "res://sprites/characters/classes/Ranger/idle_1.png",
	Stats.CharacterClass.WIZARD:    "res://sprites/characters/classes/Wizard/idle_1.png",
	Stats.CharacterClass.MONK:      "res://sprites/characters/classes/Monk/idle_1.png",
	# BUGFIX: Warlock was missing here entirely — _on_class_chosen()'s CLASS_PORTRAIT.get(cls, ...)
	# silently fell back to the Barbarian portrait default for every Warlock, even though
	# player.gd._setup_animations() already had a correct WARLOCK case for the actual in-world
	# sprite (this dict is the separate HUD-portrait mapping, not shared code).
	Stats.CharacterClass.WARLOCK:   "res://sprites/characters/classes/Warlock/idle_1.png",
}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
			if not GameState.is_game_over and not GameState.is_dying and GameState.class_selected and not GameState.mastery_picker_open \
					and not GameState.subclass_picker_open and not GameState.race_picker_open \
					and not GameState.point_buy_open and not GameState.background_select_open:
				_toggle_ability_bar()
				get_viewport().set_input_as_handled()

func _toggle_ability_bar() -> void:
	_ability_bar_mode = not _ability_bar_mode
	_update_bar_mode_label()
	_refresh_inventory()
	# Notify player.gd so 1–9 hotkeys route to ability bar
	GameState.player_action_requested.emit("toggle_ability_bar")

func _update_bar_mode_label() -> void:
	if _bar_mode_label == null:
		return
	if _ability_bar_mode:
		_bar_mode_label.text = "[TAB] ABILITIES"
		_bar_mode_label.add_theme_color_override("font_color", Color(1.0, 0.6, 0.2))
	else:
		_bar_mode_label.text = "[TAB] ITEMS"
		_bar_mode_label.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))

## Whether the ActionBar is currently showing the ability bar (vs. the item quickbar). Read by
## spellbook_overlay.gd's drag-and-drop so a drop is only ever accepted onto an actual ability-bar
## slot, never the item quickbar sharing the same physical buttons — see
## docs/architecture/leveled-spells-and-slots-plan.md §5.4.
func is_ability_bar_showing() -> bool:
	return _ability_bar_mode

## Forces a specific bar mode (used by spellbook_overlay.gd so the ability bar — its only valid
## drag-and-drop target — is guaranteed visible/correct for the overlay's whole lifetime,
## regardless of whichever mode the player happened to have showing when they pressed R). No-op
## if already in that mode (so it never fights a mid-session Tab press).
func set_ability_bar_mode(active: bool) -> void:
	if _ability_bar_mode == active:
		return
	_ability_bar_mode = active
	_update_bar_mode_label()
	_refresh_inventory()
	GameState.player_action_requested.emit("toggle_ability_bar")

## Global-space rect of ActionBar slot `i` (0..SLOT_COUNT-1) — for the Spellbook overlay's drag
## hit-testing (a different CanvasLayer, so it can't just read local `.position`).
func get_action_slot_global_rect(i: int) -> Rect2:
	if i < 0 or i >= _item_slots.size():
		return Rect2()
	var slot: Button = _item_slots[i]
	return Rect2(slot.global_position, slot.size)

func _ready() -> void:
	add_to_group("hud")
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_exp_changed.connect(_on_player_exp_changed)
	GameState.player_leveled_up.connect(_on_player_leveled_up)
	GameState.subclass_choice_required.connect(_on_subclass_choice_required)
	GameState.invocation_choice_required.connect(_on_invocation_choice_required)
	GameState.player_died.connect(_on_player_died)
	GameState.death_save_started.connect(_on_death_save_started)
	GameState.player_won.connect(_on_player_won)
	GameState.combat_message.connect(_on_combat_message)
	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.ability_bar_changed.connect(_refresh_inventory)
	GameState.inventory_changed.connect(_update_food_value_label)
	GameState.player_status_changed.connect(_on_status_changed)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.short_rest_changed.connect(_update_hit_dice_label)
	_compass = Compass.new()
	add_child(_compass)
	_hunters_mark_indicator = HuntersMarkIndicator.new()
	add_child(_hunters_mark_indicator)
	_crit_banner = CritBanner.new()
	add_child(_crit_banner)
	GameState.stairs_discovered.connect(_compass.on_stairs_discovered)
	GameState.crit_banner.connect(_crit_banner.show_banner)
	TurnManager.player_turn_started.connect(_compass.update_display)
	TurnManager.player_turn_started.connect(_hunters_mark_indicator.update_display)
	TurnManager.player_turn_started.connect(_update_status_icons)
	GameState.known_masteries_changed.connect(_update_status_icons)
	portrait.pressed.connect(_on_portrait_pressed)
	portrait.focus_mode      = Control.FOCUS_NONE
	wait_button.focus_mode   = Control.FOCUS_NONE
	search_button.focus_mode = Control.FOCUS_NONE
	interact_button.focus_mode = Control.FOCUS_NONE
	wait_button.pressed.connect(_on_wait_pressed)
	search_button.pressed.connect(_on_search_pressed)
	interact_button.pressed.connect(_on_interact_pressed)
	mute_button.focus_mode = Control.FOCUS_NONE
	mute_button.pressed.connect(_on_mute_pressed)
	AudioManager.mute_changed.connect(_on_mute_changed)
	_on_mute_changed(AudioManager.is_muted)

	for i: int in SLOT_COUNT:
		var slot: Button = get_node("ActionBar/ItemSlot%d" % i)
		_item_slots.append(slot)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		slot.focus_mode = Control.FOCUS_NONE
		# Small quantity badge in bottom-right corner
		var qty_lbl := Label.new()
		qty_lbl.add_theme_font_size_override("font_size", 16)
		qty_lbl.add_theme_color_override("font_color", Color.WHITE)
		qty_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		qty_lbl.add_theme_constant_override("shadow_offset_x", 1)
		qty_lbl.add_theme_constant_override("shadow_offset_y", 1)
		qty_lbl.text = ""
		qty_lbl.anchor_left = 1.0
		qty_lbl.anchor_right = 1.0
		qty_lbl.anchor_top = 1.0
		qty_lbl.anchor_bottom = 1.0
		qty_lbl.offset_left = -48.0
		qty_lbl.offset_top = -27.0
		qty_lbl.offset_right = -3.0
		qty_lbl.offset_bottom = -1.0
		qty_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(qty_lbl)
		_slot_qty_labels.append(qty_lbl)
		# Hotkey number badge, top-left corner (1-9, matches KEY_1..KEY_9 -> slot i).
		var num_lbl := Label.new()
		num_lbl.add_theme_font_size_override("font_size", 14)
		num_lbl.add_theme_color_override("font_color", Color(0.85, 0.85, 0.85, 0.85))
		num_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		num_lbl.add_theme_constant_override("shadow_offset_x", 1)
		num_lbl.add_theme_constant_override("shadow_offset_y", 1)
		num_lbl.text = str(i + 1)
		num_lbl.anchor_left = 0.0
		num_lbl.anchor_right = 0.0
		num_lbl.anchor_top = 0.0
		num_lbl.anchor_bottom = 0.0
		num_lbl.offset_left = 3.0
		num_lbl.offset_top = 1.0
		num_lbl.offset_right = 20.0
		num_lbl.offset_bottom = 18.0
		num_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		slot.add_child(num_lbl)
		_slot_num_labels.append(num_lbl)
	_apply_slot_styles()

	var s: Stats = GameState.player_stats
	floor_label.text = "Floor: %d" % GameState.current_floor
	_update_hp_bar(s.current_hp, s.max_hp)
	_update_exp_bar(s.experience, s.exp_to_next(), s.character_level)
	_refresh_inventory()

	# Temp HP bar — light blue strip above the HP fill, visible only when temp_hp > 0
	_temp_hp_fill = ColorRect.new()
	_temp_hp_fill.color = Color(0.4, 0.8, 1.0, 0.9)
	_temp_hp_fill.size = Vector2(0.0, THP_BAR_H)
	_temp_hp_fill.position = hp_fill.position + Vector2(0.0, -THP_BAR_H - 1.0)
	_temp_hp_fill.visible = false
	_temp_hp_fill.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatsPanel.add_child(_temp_hp_fill)

	# Food value label — created programmatically below the HP bar
	_food_value_label = Label.new()
	_food_value_label.add_theme_font_size_override("font_size", 12)
	_food_value_label.add_theme_color_override("font_color", Color(0.65, 0.65, 0.55))
	_food_value_label.position = hp_fill.position + Vector2(0.0, HP_BAR_H + 1.0)
	_food_value_label.size = Vector2(BAR_W, 14.0)
	$StatsPanel.add_child(_food_value_label)
	_update_food_value_label()

	# Status/buff/debuff/passive icon tray — a data-driven row directly below the portrait+level
	# +hit-dice column (see status_tray.gd / docs/architecture/status-icon-tray-design.md).
	_status_tray = StatusTray.new()
	_status_tray.position = Vector2(4.0, 138.0)
	_status_tray.size = Vector2(388.0, 32.0)
	$StatsPanel.add_child(_status_tray)
	_status_tray.icon_hovered.connect(_on_status_tray_icon_hovered)
	_status_tray.icon_unhovered.connect(_on_qbar_slot_hover_end)
	_update_status_icons()

	# Bar mode label — anchored to bottom, just above the action bar (which sits at bottom -135px)
	_bar_mode_label = Label.new()
	_bar_mode_label.add_theme_font_size_override("font_size", 10)
	_bar_mode_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_bar_mode_label.anchor_left = 0.0
	_bar_mode_label.anchor_right = 1.0
	_bar_mode_label.anchor_top = 1.0
	_bar_mode_label.anchor_bottom = 1.0
	_bar_mode_label.offset_top = -156.0   # ActionBar top is at -135; label sits 21px above that
	_bar_mode_label.offset_bottom = -135.0
	_bar_mode_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_LEFT
	add_child(_bar_mode_label)
	_update_bar_mode_label()

	# Use-count badges for ability slots (separate from item qty labels)
	for _i: int in SLOT_COUNT:
		var use_lbl := Label.new()
		use_lbl.add_theme_font_size_override("font_size", 16)
		use_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2))
		use_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		use_lbl.add_theme_constant_override("shadow_offset_x", 1)
		use_lbl.add_theme_constant_override("shadow_offset_y", 1)
		use_lbl.text = ""
		use_lbl.anchor_left = 1.0
		use_lbl.anchor_right = 1.0
		use_lbl.anchor_top = 1.0
		use_lbl.anchor_bottom = 1.0
		use_lbl.offset_left = -48.0
		use_lbl.offset_top = -27.0
		use_lbl.offset_right = -3.0
		use_lbl.offset_bottom = -1.0
		use_lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
		use_lbl.visible = false
		_item_slots[_i].add_child(use_lbl)
		_slot_use_labels.append(use_lbl)

	# Hit dice label below level label
	_hit_dice_label = Label.new()
	_hit_dice_label.add_theme_font_size_override("font_size", 11)
	_hit_dice_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_hit_dice_label.position = Vector2(4.0, 106.0)
	_hit_dice_label.size = Vector2(64.0, 14.0)
	_hit_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$StatsPanel.add_child(_hit_dice_label)
	_update_hit_dice_label()

	# Short rest pip row (BG3-style) — filled/empty circles showing short_rests_remaining vs
	# max_short_rests for this long-rest cycle, right below the hit-dice line in the portrait
	# column, so it's visible at a glance without opening the Alt rest menu.
	_short_rest_label = RichTextLabel.new()
	_short_rest_label.bbcode_enabled = true
	_short_rest_label.fit_content = false
	_short_rest_label.scroll_active = false
	_short_rest_label.position = Vector2(4.0, 120.0)
	_short_rest_label.size = Vector2(64.0, 16.0)
	_short_rest_label.add_theme_font_size_override("normal_font_size", 13)
	_short_rest_label.mouse_filter = Control.MOUSE_FILTER_STOP
	_short_rest_label.tooltip_text = "Short Rests remaining (refills on Long Rest)"
	$StatsPanel.add_child(_short_rest_label)
	GameState.short_rest_changed.connect(_update_short_rest_pips)
	_update_short_rest_pips()

	# AC label — always visible to the right of the LevelLabel row
	_ac_label = Label.new()
	_ac_label.add_theme_font_size_override("font_size", 12)
	_ac_label.add_theme_color_override("font_color", Color(0.70, 0.90, 1.0))
	_ac_label.position = Vector2(72.0, 92.0)
	_ac_label.size = Vector2(120.0, 16.0)
	_ac_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatsPanel.add_child(_ac_label)
	_update_ac_label()

	# Gold counter — coin icon + amount, next to the hit-dice label. Wired to
	# GameState.gold_changed (signals only, never polled).
	var coin_icon := TextureRect.new()
	coin_icon.ignore_texture_size = true  # small fixed-size icon rule (scripts/ui/CLAUDE.md)
	coin_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	coin_icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	coin_icon.position = Vector2(72.0, 107.0)
	coin_icon.size = Vector2(12.0, 12.0)
	coin_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var coin_path: String = "res://sprites/items/misc/coin_gold.png"
	if ResourceLoader.exists(coin_path):
		coin_icon.texture = load(coin_path)
	$StatsPanel.add_child(coin_icon)
	_gold_label = Label.new()
	_gold_label.add_theme_font_size_override("font_size", 12)
	_gold_label.add_theme_color_override("font_color", Color(1.0, 0.84, 0.30))
	_gold_label.position = Vector2(87.0, 105.0)
	_gold_label.size = Vector2(105.0, 16.0)
	_gold_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatsPanel.add_child(_gold_label)
	GameState.gold_changed.connect(_on_gold_changed)
	_on_gold_changed(GameState.gold)

	# Spell slots row (leveled-spells-and-slots-plan.md) — always-visible remaining/max per level,
	# right under the status tray. Wizard-only; hidden text for every other class.
	_spell_slots_label = RichTextLabel.new()
	_spell_slots_label.bbcode_enabled = true
	_spell_slots_label.fit_content = false
	_spell_slots_label.scroll_active = false
	_spell_slots_label.position = Vector2(4.0, 174.0)
	_spell_slots_label.size = Vector2(388.0, 38.0)
	_spell_slots_label.add_theme_font_size_override("normal_font_size", 13)
	_spell_slots_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatsPanel.add_child(_spell_slots_label)
	GameState.spell_slots_changed.connect(_update_spell_slots_label)
	GameState.player_leveled_up.connect(func(_lv: int) -> void: _update_spell_slots_label())
	GameState.class_chosen.connect(func(_c) -> void: _update_spell_slots_label())
	_update_spell_slots_label()

	# If a class was already chosen before this HUD existed (e.g. "Try Again" retry — GameState.
	# retry_same_character() emits class_chosen and reloads the scene in the same call, so a fresh
	# HUD's class_chosen connection above always misses that emit), sync the class-driven UI
	# (portrait, hit-dice label) from current state directly instead of waiting for a signal that
	# already fired.
	if GameState.class_selected:
		_on_class_chosen(s.character_class)

	# Inventory overlay — add as sibling CanvasLayer so it floats above HUD
	var overlay_script = load("res://scripts/ui/inventory_overlay.gd")
	_inventory_overlay_ref = overlay_script.new()
	get_tree().root.call_deferred("add_child", _inventory_overlay_ref)

	# Character select screen — shown once per run before the first move
	var cs_script = load("res://scripts/ui/character_select.gd")
	get_tree().root.call_deferred("add_child", cs_script.new())

	# Debug panel
	var dbg_script = load("res://scripts/ui/debug_panel.gd")
	_debug_panel_ref = dbg_script.new()
	get_tree().root.call_deferred("add_child", _debug_panel_ref)

	# Log tooltip — hover over [url=...]...[/url] tags to see combat breakdowns
	_setup_log_tooltip()
	log_label.mouse_filter = Control.MOUSE_FILTER_PASS  # allow hover events while passing clicks through
	log_label.meta_hover_started.connect(_on_log_meta_hover_started)
	log_label.meta_hover_ended.connect(_on_log_meta_hover_ended)
	# Quickbar slot hover tooltips
	_setup_quickbar_tooltip()

	# Extra stat popup labels (expand panel height, add rows for prof/dmg/rage)
	_init_popup_extra_labels()

	# Refresh popup every turn so AC, rage status, etc. stay live
	TurnManager.player_turn_started.connect(func(): _refresh_popup(); _update_ac_label(); _update_status_icons())
	GameState.ability_bar_changed.connect(_update_status_icons)
	GameState.equipment_changed.connect(func(): _refresh_popup(); _update_ac_label())
	GameState.player_status_changed.connect(func(): _refresh_popup(); _update_ac_label())

func _exit_tree() -> void:
	if _inventory_overlay_ref != null and is_instance_valid(_inventory_overlay_ref):
		_inventory_overlay_ref.queue_free()
	if _debug_panel_ref != null and is_instance_valid(_debug_panel_ref):
		_debug_panel_ref.queue_free()

# ── Signal handlers ───────────────────────────────────────────────────────────

func _update_food_value_label() -> void:
	if _food_value_label == null:
		return
	_food_value_label.text = "Food: %d / %d" % [GameState.total_food_value(), GameState.LONG_REST_FOOD_COST]

func _on_status_changed() -> void:
	_update_status_icons()

func _update_status_icons() -> void:
	if _status_tray == null:
		return
	var s: Stats = GameState.player_stats
	var entries: Array = []
	# Race Bonus — always shown first, for the whole run, regardless of race (a permanent
	# at-a-glance reference for every trait the player's chosen race grants). Unlike every other
	# tray entry this one is never conditional on a live game-state flag.
	entries.append({"id": "race_bonus", "icon_path": StatusTooltips.race_portrait_icon_path(GameState.player_stats), "fallback_color": Color(0.85, 0.70, 0.35)})
	if s.poison_turns > 0:
		entries.append({"id": "poisoned", "icon_path": "res://icons/status/poisoned.png", "fallback_color": Color(0.20, 0.85, 0.35)})
	if s.burning_turns > 0:
		entries.append({"id": "burning", "icon_path": "res://icons/status/burning.png", "fallback_color": Color(1.00, 0.45, 0.10)})
	if s.bleeding_turns > 0:
		entries.append({"id": "bleeding", "icon_path": "res://icons/status/bleeding.png", "fallback_color": Color(0.80, 0.0, 0.0)})
	# Skip "slowed" whenever difficult_terrain already covers it — they render with the identical
	# icon/color, so showing both is an indistinguishable duplicate, not two "distinct" debuffs.
	# Re-stepping into Mud/Water while already standing in it re-applies slowed_turns (real gameplay
	# effect, drives the 2-turn move cost) at a moment player_on_difficult_terrain is already true,
	# which used to flash a second identical icon for a frame — see scripts/entities/CLAUDE.md's
	# status-tray note.
	if s.slowed_turns > 0 and not GameState.player_on_difficult_terrain:
		entries.append({"id": "slowed", "icon_path": "res://icons/status/slowed.png", "fallback_color": Color(0.55, 0.35, 0.10)})
	if s.poisoned_condition_turns > 0:
		entries.append({"id": "poisoned_condition", "icon_path": "res://icons/status/poisoned_condition.png", "fallback_color": Color(0.10, 0.55, 0.20)})
	if s.prone:
		entries.append({"id": "prone", "icon_path": "res://icons/status/prone.png", "fallback_color": Color(0.60, 0.55, 0.20)})
	if s.web_restrained:
		entries.append({"id": "restrained", "icon_path": "res://icons/status/restrained.png", "fallback_color": Color(0.45, 0.45, 0.45)})
	if s.incapacitated_turns > 0:
		entries.append({"id": "incapacitated", "icon_path": "res://icons/status/incapacitated.png", "fallback_color": Color(0.75, 0.10, 0.10)})
	if s.paralyzed_turns > 0:
		entries.append({"id": "paralyzed", "icon_path": "res://icons/status/paralyzed.png", "fallback_color": Color(0.55, 0.05, 0.05)})
	if GameState.is_blinded(GameState.player_grid_pos):
		entries.append({"id": "blinded", "icon_path": "res://icons/status/blinded.png", "fallback_color": Color(0.08, 0.08, 0.10)})
	if s.frightened_turns > 0:
		entries.append({"id": "frightened", "icon_path": "res://icons/status/frightened.png", "fallback_color": Color(0.55, 0.20, 0.65)})
	if GameState.player_on_difficult_terrain:
		entries.append({"id": "difficult_terrain", "icon_path": "res://icons/status/slowed.png", "fallback_color": Color(0.55, 0.35, 0.10)})
	if GameState.is_raging:
		entries.append({"id": "raging", "icon_path": GameState.talent_icon_path("rage", 3), "fallback_color": Color(0.85, 0.15, 0.05)})
	if GameState.risen_from_dead_active:
		entries.append({"id": "risen_from_dead", "icon_path": "res://icons/status/risen_from_dead.png", "fallback_color": Color(0.2, 0.9, 0.9)})
	if s.exhaustion_level > 0:
		entries.append({"id": "exhaustion", "icon_path": "res://icons/status/exhaustion.png", "fallback_color": Color(0.5, 0.4, 0.3)})
	if s.temp_hp > 0:
		entries.append({"id": "temp_hp", "icon_path": "res://icons/status/temp_hp.png", "fallback_color": Color(0.4, 0.8, 1.0)})
	if s.concentration_spell_id != "":
		var _conc_spell: Spell = SpellDb.get_spell(s.concentration_spell_id)
		entries.append({"id": "concentration", "icon_path": _conc_spell.icon_path if _conc_spell != null else "", "fallback_color": Color(0.65, 0.45, 1.0)})
	if (s.character_class == Stats.CharacterClass.BARBARIAN or s.character_class == Stats.CharacterClass.MONK) \
			and (GameState.equipment.get("armor") as Item) == null:
		entries.append({"id": "unarmored_defense", "icon_path": GameState.talent_icon_path("unarmored_defense", 1), "fallback_color": Color(0.70, 0.90, 1.0)})
	if GameState.battlefield_adv_pending:
		entries.append({"id": "tactician", "icon_path": GameState.talent_icon_path("battlefield_expert", maxi(1, GameState.get_talent_rank("battlefield_expert"))), "fallback_color": Color(0.3, 0.9, 0.9)})
	if GameState.psycho_adv_pending:
		entries.append({"id": "psycho_adv", "icon_path": GameState.talent_icon_path("psycho", maxi(1, GameState.get_talent_rank("psycho"))), "fallback_color": Color(0.9, 0.3, 0.3)})
	if s.hunters_mark_free_recast_available:
		entries.append({"id": "hunters_mark_free_recast", "icon_path": GameState.talent_icon_path("hunters_mark", 1), "fallback_color": Color(0.3, 0.9, 0.5)})
	var _lit_torch: Item = GameState.lit_torch_item()
	if _lit_torch != null:
		entries.append({"id": "torch", "icon_path": _lit_torch.icon_path, "fallback_color": Color(1.0, 0.55, 0.1)})
	if s.longstrider_turns > 0:
		var _ls_spell: Spell = SpellDb.get_spell("longstrider")
		entries.append({"id": "longstrider", "icon_path": _ls_spell.icon_path if _ls_spell != null else "", "fallback_color": Color(0.55, 0.85, 0.45)})
	if s.aid_bonus_hp > 0:
		var _aid_spell: Spell = SpellDb.get_spell("aid")
		entries.append({"id": "aid", "icon_path": _aid_spell.icon_path if _aid_spell != null else "", "fallback_color": Color(0.5, 0.9, 0.6)})
	if s.barkskin_turns > 0 and not s.barkskin_on_companion:
		var _bk_spell: Spell = SpellDb.get_spell("barkskin")
		entries.append({"id": "barkskin", "icon_path": _bk_spell.icon_path if _bk_spell != null else "", "fallback_color": Color(0.55, 0.40, 0.20)})
	if s.faerie_fire_outlined_turns > 0:
		entries.append({"id": "faerie_fire_outlined", "icon_path": "", "fallback_color": s.faerie_fire_outlined_color})
	if s.mastery_cap() > 0 and s.known_weapon_masteries.size() > 0:
		entries.append({"id": "weapon_mastery", "icon_path": "res://icons/status/weapon_mastery.png", "fallback_color": Color(0.80, 0.65, 0.20)})
	_status_tray.refresh(entries)

func _on_status_tray_icon_hovered(id: String, rect: Rect2) -> void:
	if _qbar_tooltip == null:
		return
	_qbar_hover_source_rect = rect
	if id == "race_bonus":
		var text: String = RaceTooltip.build(GameState.player_stats)
		if text.is_empty():
			return
		_qbar_tooltip_rtl.text = text
		_qbar_tooltip_rtl.size = Vector2(220.0, 0)
		_qbar_tooltip.size = Vector2(228.0, 60)
		_qbar_tooltip.visible = true
		_position_qbar_tooltip_near(rect)
		return
	var text: String = StatusTooltips.build_bbcode(id)
	if text.is_empty():
		return
	_qbar_tooltip_rtl.text = text
	_qbar_tooltip_rtl.size = Vector2(172.0, 0)
	_qbar_tooltip.size = Vector2(180.0, 60)
	_qbar_tooltip.visible = true
	_position_qbar_tooltip_near(rect)

func _on_class_chosen(cls: Stats.CharacterClass) -> void:
	var path: String = CLASS_PORTRAIT.get(cls, "res://sprites/characters/classes/Barbarian/idle_1.png")
	portrait.texture_normal = load(path)
	_update_hit_dice_label()
	_update_short_rest_pips()
	# class_chosen re-fires from character_summary.gd's final confirm, right after class_selected
	# is set true — this is the first point in the Custom-path onboarding chain it's safe to spawn
	# the Invocation picker for a fresh Warlock's level-1 grant (see _on_invocation_choice_required).
	_on_invocation_choice_required()

func _on_gold_changed(new_amount: int) -> void:
	if _gold_label == null:
		return
	_gold_label.text = str(new_amount)

## Always-visible "1st 2/2  2nd 1/1  ..." row — leveled-spells-and-slots-plan.md follow-up:
## previously slot counts were only visible inside the R-key Spellbook overlay. Wired to
## GameState.spell_slots_changed (slot consume/refill/level-up-grant/prepare-toggle),
## player_leveled_up, and class_chosen. Empty for every non-caster class.
func _update_spell_slots_label() -> void:
	if _spell_slots_label == null:
		return
	var caster: SpellcasterState = GameState.player_stats.caster if GameState.class_selected else null
	if caster == null or caster.slot_pool == null:
		_spell_slots_label.text = ""
		return
	var mx: Dictionary = caster.slot_pool.max_slots()
	var levels: Array = mx.keys()
	levels.sort()
	var parts: PackedStringArray = []
	for lv: int in levels:
		var remaining: int = caster.slot_pool.remaining.get(lv, 0)
		var total: int = mx[lv]
		var color: String = "#8fd3ff" if remaining > 0 else "#555560"
		parts.append("[color=%s]%s %d/%d[/color]" % [color, _ordinal_level(lv), remaining, total])
	_spell_slots_label.text = "[b]Slots:[/b]  " + "   ".join(parts) if not parts.is_empty() else "[color=#666]No spell slots yet.[/color]"

func _ordinal_level(n: int) -> String:
	match n:
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % n

func _update_hit_dice_label() -> void:
	if _hit_dice_label == null:
		return
	var sides: int = GameState.hit_die_sides()
	var available: int = GameState.hit_dice
	_hit_dice_label.text = "d%d:%d" % [sides, available]

## BG3-style filled/empty pip row for GameState.short_rests_remaining / max_short_rests.
func _update_short_rest_pips() -> void:
	if _short_rest_label == null:
		return
	var remaining: int = GameState.short_rests_remaining
	var mx: int = GameState.max_short_rests
	var pips: PackedStringArray = []
	for i: int in mx:
		if i < remaining:
			pips.append("[color=#ffd24d]●[/color]")
		else:
			pips.append("[color=#555560]○[/color]")
	_short_rest_label.text = " ".join(pips)

func _on_floor_changed(new_floor: int) -> void:
	floor_label.text = "Floor: %d" % new_floor
	_log_messages.clear()
	log_label.text = ""
	_update_hit_dice_label()
	_compass.reset_for_new_floor()
	_hunters_mark_indicator.reset_for_new_floor()
	GameState.player_stats.hunters_mark_target = null

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	_update_hp_bar(current_hp, max_hp)
	_refresh_popup()

func _on_player_exp_changed(exp: int, exp_needed: int, level: int) -> void:
	_update_exp_bar(exp, exp_needed, level)
	_refresh_popup()

func _on_player_leveled_up(level: int) -> void:
	level_label.text = "Lv.%d" % level
	# leveled-spells-and-slots-plan.md §4.1: Wizard level-up spell-learn picker.
	if GameState.spell_learn_pending and not GameState.spell_learn_picker_open:
		var picker = load("res://scripts/ui/spell_learn_picker.gd").new()
		get_tree().root.add_child(picker)
	# Mastery cap grew this level-up (e.g. Barbarian hitting level 4/10) — let the player pick
	# the new slot immediately, same "instant pick" treatment as hit dice/spell slots.
	if GameState.mastery_learn_pending and not GameState.mastery_picker_open:
		GameState.mastery_learn_pending = false
		var mastery_picker = load("res://scripts/ui/mastery_picker.gd").new()
		get_tree().root.add_child(mastery_picker)

func _on_death_save_started() -> void:
	# 0-HP hit that isn't caught by Bruiser R3 / Relentless Endurance — see
	# GameState.begin_death_save_sequence(). The overlay drives its own lifetime entirely off
	# GameState.death_save_rolled/death_save_finished, so nothing else needs wiring here.
	var overlay = load("res://scripts/ui/death_save_overlay.gd").new()
	get_tree().root.add_child(overlay)

func _on_subclass_choice_required() -> void:
	# One-time Tier 2 subclass choice (gating boss defeated) — spawn the blocking overlay.
	if GameState.subclass_picker_open:
		return
	var picker = load("res://scripts/ui/subclass_select.gd").new()
	get_tree().root.add_child(picker)

func _on_invocation_choice_required() -> void:
	# Warlock Eldritch Invocation slot(s) opened (level 1 grant, or a later level-up threshold).
	# Guarded on class_selected — the level-1 grant fires from _give_warlock_starting_items()
	# mid-character-creation, well before the Custom-path onboarding chain (point buy/background/
	# race/cantrip/summary) finishes; spawning here immediately would collide with those blocking
	# overlays. character_summary.gd's final confirm re-emits class_chosen right after setting
	# class_selected = true, which is what actually triggers the first pick for a fresh character —
	# see the class_chosen connection below.
	if not GameState.class_selected:
		return
	if GameState.warlock_invocation_slots_pending <= 0:
		return
	if GameState.invocation_picker_open:
		return
	var picker = load("res://scripts/ui/invocation_picker.gd").new()
	get_tree().root.add_child(picker)

func _on_player_died() -> void:
	var game_over: PackedScene = preload("res://scenes/ui/game_over.tscn")
	get_tree().root.add_child(game_over.instantiate())

func _on_player_won() -> void:
	var win_screen: PackedScene = preload("res://scenes/ui/win.tscn")
	get_tree().root.add_child(win_screen.instantiate())

func _on_combat_message(msg: String) -> void:
	_log_messages.push_back(msg)
	if _log_messages.size() > MAX_LOG_MESSAGES:
		_log_messages.remove_at(0)
	log_label.text = "\n".join(_log_messages)

func _on_portrait_pressed() -> void:
	stats_popup.visible = not stats_popup.visible
	if stats_popup.visible:
		_refresh_popup()
	GameState.camera_recenter_requested.emit()

func _on_wait_pressed() -> void:
	GameState.player_action_requested.emit("wait")

func _on_search_pressed() -> void:
	GameState.player_action_requested.emit("search")

func _on_interact_pressed() -> void:
	GameState.player_action_requested.emit("interact")

func _on_mute_pressed() -> void:
	AudioManager.toggle_mute()

func _on_mute_changed(muted: bool) -> void:
	mute_button.text = "🔇" if muted else "🔊"

func _on_slot_pressed(slot_index: int) -> void:
	if TurnManager.phase != TurnManager.Phase.WAITING_FOR_INPUT:
		return
	if _ability_bar_mode:
		var raw = GameState.player_ability_bar[slot_index]
		if raw == null:
			return
		# Delegate actual use to player.gd via action_requested mechanism
		GameState.player_action_requested.emit("use_ability_%d" % slot_index)
		return
	var raw = GameState.player_quickbar[slot_index]
	if raw == null:
		return
	GameState.use_item(raw as Item)

func _dispatch_item_interaction(item: Item, id: String) -> void:
	match id:
		"throw":
			GameState.player_throw_primed.emit(item)
		"light":
			GameState.light_torch(item)
			var df: Node = get_tree().get_first_node_in_group("dungeon_floor")
			if df != null:
				df.update_fog(GameState.player_grid_pos)
		"learn":
			GameState.begin_scroll_learn(item)
		"drop":
			GameState.drop_item(item)
		_:
			GameState.use_item(item)  # read / drink / prime

func _on_slot_gui_input(event: InputEvent, slot_index: int) -> void:
	if not (event is InputEventMouseButton):
		return
	var mb := event as InputEventMouseButton
	if mb.button_index == MOUSE_BUTTON_RIGHT and mb.pressed:
		get_viewport().set_input_as_handled()
		if _ability_bar_mode:
			return  # no RMB action for ability slots
		var raw = GameState.player_quickbar[slot_index]
		if raw == null:
			return
		var it := raw as Item
		var interactions: Array[String] = ItemInteractions.get_available_interactions(it)
		if interactions.size() == 1:
			_dispatch_item_interaction(it, interactions[0])
		else:
			var m := ItemInteractionMenu.new()
			add_child(m)
			m.open(get_viewport().get_mouse_position(), interactions, func(id: String): _dispatch_item_interaction(it, id))
		return
	# LMB press: only *records* the drag-start candidate — does NOT consume the event, so the
	# Button's own `pressed` signal (→ _on_slot_pressed, use/cast) still fires normally for a
	# plain click. Motion/release are polled in _process() below (same reasoning as
	# spellbook_overlay.gd's drag: a release outside the pressed Button's bounds never reaches it).
	# Allowed even while the Spellbook is open — its own drag starts from a Spellbook row (a
	# different source), never from an ActionBar slot, so the two never actually contend for the
	# same press despite both being able to drop onto the ability bar.
	if mb.button_index == MOUSE_BUTTON_LEFT and mb.pressed:
		if (_ability_bar_mode and GameState.player_ability_bar[slot_index] != null) \
				or (not _ability_bar_mode and GameState.player_quickbar[slot_index] != null):
			_bar_drag_from = slot_index
			_bar_dragging = false
			_bar_drag_start_pos = get_viewport().get_mouse_position()

func _process_bar_drag(mp: Vector2) -> void:
	if _bar_drag_from == -1:
		return
	if not _bar_dragging and mp.distance_to(_bar_drag_start_pos) > BAR_DRAG_THRESHOLD:
		_bar_dragging = true
		_bar_drag_icon = TextureRect.new()
		_bar_drag_icon.size = Vector2(48.0, 48.0)
		_bar_drag_icon.ignore_texture_size = true
		_bar_drag_icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
		_bar_drag_icon.mouse_filter = Control.MOUSE_FILTER_IGNORE
		var src_btn: Button = _item_slots[_bar_drag_from]
		if src_btn.icon != null:
			_bar_drag_icon.texture = src_btn.icon
		add_child(_bar_drag_icon)
	if _bar_dragging and _bar_drag_icon != null:
		_bar_drag_icon.position = mp - _bar_drag_icon.size * 0.5
	if not Input.is_mouse_button_pressed(MOUSE_BUTTON_LEFT):
		if _bar_dragging:
			var dropped_on_special: bool = false
			if _ability_bar_mode and GameState.spellbook_open:
				var overlay = get_tree().get_first_node_in_group("spellbook_overlay")
				if overlay != null and overlay.get_special_slot_global_rect().has_point(mp):
					dropped_on_special = true
					var ab: Ability = GameState.player_ability_bar[_bar_drag_from] as Ability
					if ab != null and ab.ability_id.begins_with("spell:"):
						GameState.set_special_slot(ab.ability_id.trim_prefix("spell:"))
						overlay.refresh_after_external_change()
			if not dropped_on_special:
				for i: int in SLOT_COUNT:
					if i != _bar_drag_from and Rect2(_item_slots[i].global_position, _item_slots[i].size).has_point(mp):
						if _ability_bar_mode:
							GameState.swap_ability_slots(_bar_drag_from, i)
						else:
							GameState.move_item("quickbar", _bar_drag_from, "", "quickbar", i, "")
						break
			if _bar_drag_icon != null:
				_bar_drag_icon.queue_free()
				_bar_drag_icon = null
		_bar_drag_from = -1
		_bar_dragging = false

# ── Bar updates ───────────────────────────────────────────────────────────────

func _update_hp_bar(current_hp: int, max_hp: int) -> void:
	var ratio: float = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size = Vector2(BAR_W * ratio, HP_BAR_H)
	hp_label.text = "%d / %d" % [current_hp, max_hp]
	# Temp HP bar: light blue fill proportional to temp_hp / max_hp, above the HP fill.
	if _temp_hp_fill != null:
		var temp: int = 0
		if GameState.player_stats != null:
			temp = GameState.player_stats.temp_hp
		if temp > 0 and max_hp > 0:
			var temp_ratio: float = clampf(float(temp) / float(max_hp), 0.0, 1.0)
			_temp_hp_fill.size = Vector2(BAR_W * temp_ratio, THP_BAR_H)
			_temp_hp_fill.visible = true
		else:
			_temp_hp_fill.visible = false

func _update_exp_bar(exp: int, exp_needed: int, level: int) -> void:
	var ratio: float = clampf(float(exp) / float(exp_needed), 0.0, 1.0)
	exp_fill.size = Vector2(BAR_W * ratio, EXP_BAR_H)
	exp_label.text = "%d / %d XP" % [exp, exp_needed]
	level_label.text = "Lv.%d" % level

# ── Inventory ─────────────────────────────────────────────────────────────────

func _refresh_inventory() -> void:
	if _ability_bar_mode:
		_refresh_ability_bar()
	else:
		_refresh_item_bar()

func _refresh_item_bar() -> void:
	for i: int in SLOT_COUNT:
		var raw = GameState.player_quickbar[i]
		var slot: Button = _item_slots[i]
		var qty_lbl: Label = _slot_qty_labels[i]
		slot.modulate = Color(1.0, 1.0, 1.0)  # reset tint from ability bar (e.g. active-toggle orange)
		if _slot_use_labels.size() > i:
			_slot_use_labels[i].visible = false
		if raw == null:
			slot.text = ""
			slot.icon = null
			qty_lbl.text = ""
		else:
			var it := raw as Item
			slot.text = ""
			if it.icon_path != "" and ResourceLoader.exists(it.icon_path):
				slot.icon = load(it.icon_path)
				slot.expand_icon = true
			else:
				slot.icon = null
			qty_lbl.text = "×%d" % it.quantity if it.quantity > 1 else ""

## Returns the free-casts-remaining counter for a spell_id granted by Elven Lineage, Fiendish
## Legacy, or Gnomish Lineage — or null if spell_id belongs to none of the three (a normal known/
## prepared Wizard/Ranger spell, which has no such counter) OR is a cantrip granted by Elven
## Lineage/Fiendish Legacy specifically (genuinely infinite, no badge — Gnomish Lineage's own
## cantrips are the deliberate exception, see this function's body). Used by
## _refresh_ability_bar()'s racial-lineage badge branch above.
func _racial_lineage_spell_counter(spell_id: String) -> Variant:
	var stats: Stats = GameState.player_stats
	# Cantrips (level 0) granted by Elven Lineage/Fiendish Legacy are genuinely infinite — the
	# free-cast counter only matters for a LEVELED lineage spell, which falls back to a real spell
	# slot once its counter runs out (Stats.is_lineage_free_cast_available()); a cantrip has no
	# such fallback and PlayerSpellcasting._cast_level_for()/begin_cast() never even consult the
	# counter for one (both gate on spell.level > 0), so showing a "X/Y" badge on it is misleading
	# — it implies the cantrip stops working once exhausted, which it never does. BUGFIX: no badge
	# at all for a level-0 Elf/Tiefling grant (e.g. Tiefling's own level-1 cantrip — Poison Spray/
	# Chill Touch/Fire Bolt). Gnomish Lineage is the one deliberate exception — all three of its
	# grants are cantrips too, but the owner explicitly wants THOSE capped per long rest (see
	# scripts/entities/CLAUDE.md's "Gnome" section) — its own branch below is untouched.
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell != null and spell.level == 0 and (spell_id in stats.elf_lineage_spell_ids or spell_id in stats.tiefling_legacy_spell_ids):
		return null
	if spell_id in stats.elf_lineage_spell_ids:
		return stats.elf_lineage_free_casts_remaining.get(spell_id, 0)
	if spell_id in stats.tiefling_legacy_spell_ids:
		return stats.tiefling_legacy_free_casts_remaining.get(spell_id, 0)
	if spell_id in stats.gnome_lineage_spell_ids:
		return stats.gnome_lineage_free_casts_remaining.get(spell_id, 0)
	return null

func _refresh_ability_bar() -> void:
	for i: int in SLOT_COUNT:
		var raw = GameState.player_ability_bar[i]
		var slot: Button = _item_slots[i]
		var qty_lbl: Label = _slot_qty_labels[i]
		qty_lbl.text = ""
		if _slot_use_labels.size() > i:
			_slot_use_labels[i].visible = false
		if raw == null:
			slot.text = ""
			slot.icon = null
		else:
			var ab := raw as Ability
			slot.text = ""
			if ab.icon_path != "" and ResourceLoader.exists(ab.icon_path):
				slot.icon = load(ab.icon_path)
				slot.expand_icon = true
			else:
				slot.icon = null
				slot.text = ab.ability_name.left(4)
			var frenzy_cooldown_turns: int = -1
			if ab.ability_id == "frenzy" and GameState.berserker_frenzy_used and GameState.get_talent_rank("frenzied_killer") >= 3:
				frenzy_cooldown_turns = maxi(0, 3 - GameState.berserker_turns_since_frenzy)
			# Hunter's Mark's own one-cast-per-round cooldown (5e: bonus action) — same big-number
			# countdown treatment as Frenzy's above, since it's the same "can't use this again yet"
			# shape: 1 turn left until it clears (it's a flat 1-round cooldown, never counts past 1).
			if ab.ability_id == "hunters_mark" and GameState.player_stats.hunters_mark_cast_this_round:
				frenzy_cooldown_turns = 1
			if _slot_use_labels.size() > i:
				var use_lbl: Label = _slot_use_labels[i]
				use_lbl.visible = true
				if frenzy_cooldown_turns >= 0:
					# Frenzied Killer R3: visible countdown until Frenzy auto-refreshes. Hunter's
					# Mark's own cooldown shows just the bare number, no "t" suffix (direct owner
					# request) — it's always exactly 1, so the unit would be redundant noise.
					use_lbl.text = "%d" % frenzy_cooldown_turns if ab.ability_id == "hunters_mark" else "%dt" % frenzy_cooldown_turns
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
				elif ab.ability_id == "hunters_mark":
					# Uses live on Stats.hunters_mark_uses_remaining, not the Ability itself
					# (uses_max stays 0/0, same free-base-ability convention as Rage — see
					# game_state.gd's _give_ranger_starting_items()) — checked before the generic
					# uses_max == 0 branch below, which would otherwise blank this out.
					var hm_remaining: int = GameState.player_stats.hunters_mark_uses_remaining
					use_lbl.text = "%d/%d" % [hm_remaining, Stats.HUNTERS_MARK_USES_MAX]
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2) if hm_remaining > 0 else Color(0.5, 0.5, 0.5))
				elif ab.ability_id == "hellish_rebuke_toggle" and "hellish_rebuke" in GameState.player_stats.tiefling_legacy_spell_ids:
					# Hellish Rebuke's free-cast counter lives on Stats.tiefling_legacy_free_casts_remaining
					# ("hellish_rebuke" key), not the Ability itself (uses_max stays 0/0, same
					# free-base-ability convention as Hunter's Mark above) — max is a flat 1 (a
					# Fiendish Legacy spell gets exactly 1 free cast per long rest, then falls back
					# to a real spell slot — see _grant_tiefling_legacy_spell()'s own comment).
					# Tiefling only — a Warlock who simply LEARNED this spell normally has no such
					# counter at all (real spell slots are the only resource, same as every other
					# spell ability), so it falls through to the blank uses_max==0 branch below
					# instead, exactly like any other spell.
					var hr_remaining: int = GameState.player_stats.tiefling_legacy_free_casts_remaining.get("hellish_rebuke", 0)
					use_lbl.text = "%d/%d" % [hr_remaining, 1]
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2) if hr_remaining > 0 else Color(0.5, 0.5, 0.5))
				elif ab.ability_id.begins_with("spell:") and _racial_lineage_spell_counter(ab.ability_id.substr(6)) != null:
					# Elven Lineage / Fiendish Legacy spells each get exactly 1 free cast per long
					# rest (Stats.elf_lineage_free_casts_remaining / tiefling_legacy_free_casts_remaining,
					# spell_id -> int) before falling back to a real spell slot of the spell's own
					# level (Wizard/Ranger only). Gnomish Lineage spells (Stats.
					# gnome_lineage_free_casts_remaining) are the one exception still on the
					# proficiency_bonus counter — they're cantrips with no spell-slot fallback at
					# all, so a flat 1 would make them nearly unusable. Same free-base-ability
					# convention as Hunter's Mark/Hellish Rebuke above (Ability.uses_max stays 0/0).
					var sid: String = ab.ability_id.substr(6)
					var lin_remaining: int = _racial_lineage_spell_counter(sid)
					var lin_max: int = GameState.player_stats.proficiency_bonus if sid in GameState.player_stats.gnome_lineage_spell_ids else 1
					use_lbl.text = "%d/%d" % [lin_remaining, lin_max]
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.7, 0.2) if lin_remaining > 0 else Color(0.5, 0.5, 0.5))
				elif ab.uses_max == 0:
					# Passive / infinite uses.
					use_lbl.text = ""
				elif ab.ability_id == "rage" and GameState.is_raging:
					# While raging: show remaining turns instead of use count.
					use_lbl.text = "%dt" % GameState.rage_turns_remaining
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
				else:
					use_lbl.text = "%d/%d" % [ab.uses_remaining, ab.uses_max]
					var clr: Color = Color(1.0, 0.7, 0.2) if ab.uses_remaining > 0 else Color(0.5, 0.5, 0.5)
					use_lbl.add_theme_color_override("font_color", clr)
			# Modulate: active toggle = orange; unusable (exhausted / requirement not met) = gray; else white
			if ab.is_active:
				slot.modulate = Color(1.0, 0.55, 0.1)
			elif GameState.is_ability_usable(ab):
				slot.modulate = Color(1.0, 1.0, 1.0)
			else:
				slot.modulate = Color(0.45, 0.45, 0.45)

func _apply_slot_styles() -> void:
	for slot: Button in _item_slots:
		var normal := StyleBoxFlat.new()
		normal.bg_color = Color(0.1, 0.1, 0.12, 0.9)
		normal.set_border_width_all(1)
		normal.border_color = Color(0.4, 0.4, 0.4)
		normal.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("normal", normal)

		var hover := StyleBoxFlat.new()
		hover.bg_color = Color(0.22, 0.22, 0.28, 0.9)
		hover.set_border_width_all(1)
		hover.border_color = Color(0.65, 0.65, 0.7)
		hover.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("hover", hover)

		var pressed := StyleBoxFlat.new()
		pressed.bg_color = Color(0.28, 0.28, 0.36, 0.9)
		pressed.set_border_width_all(1)
		pressed.border_color = Color(0.8, 0.8, 0.9)
		pressed.set_corner_radius_all(2)
		slot.add_theme_stylebox_override("pressed", pressed)

# ── Stats popup ───────────────────────────────────────────────────────────────

func _init_popup_extra_labels() -> void:
	# Compact layout: remove dead space above STR (HPStatLabel is hidden but
	# occupied y=32–52, leaving a 30px gap). Move fixed nodes up, pack all 6
	# stats tightly, add a separator, then Prof. Total height ≈ 202px.
	stats_popup.offset_bottom = 320.0  # was 338+26=364; shrink to 320 → height 202px
	# Reposition fixed scene labels (STR/DEX/CON) to eliminate the top margin
	$StatsPopup/StrengthLabel.offset_top = 32.0; $StatsPopup/StrengthLabel.offset_bottom = 52.0
	$StatsPopup/DexLabel.offset_top      = 54.0; $StatsPopup/DexLabel.offset_bottom      = 74.0
	$StatsPopup/ConLabel.offset_top      = 76.0; $StatsPopup/ConLabel.offset_bottom      = 96.0
	# INT / WIS / CHA immediately after CON
	_popup_int_label = _make_popup_label(98.0)
	_popup_wis_label = _make_popup_label(120.0)
	_popup_cha_label = _make_popup_label(142.0)
	# Thin separator before proficiency
	var sep := HSeparator.new()
	sep.position = Vector2(10.0, 166.0)
	sep.size = Vector2(280.0, 4.0)
	sep.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_popup.add_child(sep)
	# Proficiency bonus
	_popup_prof_label = _make_popup_label(172.0)

func _make_popup_label(y: float) -> Label:
	var lbl := Label.new()
	lbl.offset_left = 10.0
	lbl.offset_top = y
	lbl.offset_right = 300.0
	lbl.offset_bottom = y + 20.0
	lbl.add_theme_font_size_override("font_size", 13)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	stats_popup.add_child(lbl)
	return lbl

func _update_ac_label() -> void:
	if _ac_label != null:
		_ac_label.text = "AC: %d" % GameState.player_stats.armor_class

func _refresh_popup() -> void:
	if not stats_popup.visible:
		return
	var s: Stats = GameState.player_stats
	# These rows are already visible in HUD bars — hide them in the popup.
	$StatsPopup/HPStatLabel.visible    = false
	$StatsPopup/LevelStatLabel.visible = false
	$StatsPopup/ExpStatLabel.visible   = false
	$StatsPopup/ACLabel.visible        = false
	# Core ability scores (STR/DEX/CON fixed nodes; INT/WIS/CHA are dynamic labels)
	$StatsPopup/StrengthLabel.text = "STR: %d (%+d)" % [s.strength, s.str_modifier()]
	$StatsPopup/DexLabel.text      = "DEX: %d (%+d)" % [s.dexterity, s.dex_modifier()]
	$StatsPopup/ConLabel.text      = "CON: %d (%+d)" % [s.constitution, s.con_modifier()]
	if _popup_int_label != null:
		_popup_int_label.text = "INT: %d (%+d)" % [s.intelligence, s.int_modifier()]
	if _popup_wis_label != null:
		_popup_wis_label.text = "WIS: %d (%+d)" % [s.wisdom, s.wis_modifier()]
	if _popup_cha_label != null:
		_popup_cha_label.text = "CHA: %d (%+d)" % [s.charisma, s.cha_modifier()]
	# Proficiency bonus (compact, no level range)
	if _popup_prof_label != null:
		_popup_prof_label.text = "Prof: +%d" % s.proficiency_bonus

# ── Quickbar hover tooltip ─────────────────────────────────────────────────────
# No Ctrl-freeze (direct owner request, 2026-08-01) — the tooltip is always interactive and
# anchored to whatever triggered it (_qbar_hover_source_rect), never following the mouse. Hiding
# is driven entirely by _process()'s per-frame hover-chain rect check (see the bottom of
# _process()), never an explicit call — see "Race trait hover (nested glossary)" below for the
# full mechanism this shares with the race-trait popups, and inventory_overlay.gd's identical
# (simpler, one-level) chain.

func _setup_quickbar_tooltip() -> void:
	_qbar_tooltip = Panel.new()
	_qbar_tooltip.visible = false
	_qbar_tooltip.z_index = 30
	_qbar_tooltip.mouse_filter = Control.MOUSE_FILTER_STOP
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.50, 0.35)
	sb.set_corner_radius_all(3)
	_qbar_tooltip.add_theme_stylebox_override("panel", sb)
	_qbar_tooltip_rtl = RichTextLabel.new()
	_qbar_tooltip_rtl.bbcode_enabled = true
	_qbar_tooltip_rtl.fit_content = true
	_qbar_tooltip_rtl.offset_left = 8.0
	_qbar_tooltip_rtl.offset_top = 6.0
	_qbar_tooltip_rtl.offset_right = -8.0
	_qbar_tooltip_rtl.offset_bottom = -6.0
	_qbar_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	_qbar_tooltip_rtl.meta_hover_started.connect(_on_qbar_meta_hover_started)
	_qbar_tooltip_rtl.meta_hover_ended.connect(_on_qbar_meta_hover_ended)
	_qbar_tooltip.add_child(_qbar_tooltip_rtl)
	add_child(_qbar_tooltip)
	# Keyword glossary popup (shared by qbar tooltip). Level 1 of the nested-hover chain — see
	# "Race trait hover (nested glossary)" below: interactive (STOP on the panel, PASS+bbcode+
	# meta_hover on the RichTextLabel) so a race-trait popup's own [url=race_sub:...] links can be
	# hovered in turn, opening a level-2 popup (_glossary_popup2). Plain weapon-mastery keyword
	# popups never contain further links, so this is a no-op for them.
	_glossary_popup = Panel.new()
	_glossary_popup.visible = false
	_glossary_popup.z_index = 32
	_glossary_popup.mouse_filter = Control.MOUSE_FILTER_STOP
	var gsb := StyleBoxFlat.new()
	gsb.bg_color = Color(0.08, 0.07, 0.04, 0.97)
	gsb.set_border_width_all(1)
	gsb.border_color = Color(0.75, 0.65, 0.20)
	gsb.set_corner_radius_all(3)
	_glossary_popup.add_theme_stylebox_override("panel", gsb)
	_glossary_rtl = RichTextLabel.new()
	_glossary_rtl.bbcode_enabled = true
	_glossary_rtl.fit_content = true
	_glossary_rtl.offset_left = 8.0
	_glossary_rtl.offset_top = 6.0
	_glossary_rtl.offset_right = -8.0
	_glossary_rtl.offset_bottom = -6.0
	_glossary_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
	_glossary_rtl.meta_hover_started.connect(_on_glossary_meta_hover_started)
	_glossary_rtl.meta_hover_ended.connect(_on_glossary_meta_hover_ended)
	_glossary_popup.add_child(_glossary_rtl)
	add_child(_glossary_popup)
	# Level 2 of the nested-hover chain — a sub-option's own description (e.g. Heavenly Wings under
	# Celestial Revelation). Terminal: no further links, so its RichTextLabel needs no meta_hover.
	_glossary_popup2 = Panel.new()
	_glossary_popup2.visible = false
	_glossary_popup2.z_index = 33
	_glossary_popup2.mouse_filter = Control.MOUSE_FILTER_STOP
	var gsb2 := StyleBoxFlat.new()
	gsb2.bg_color = Color(0.08, 0.07, 0.04, 0.97)
	gsb2.set_border_width_all(1)
	gsb2.border_color = Color(0.75, 0.65, 0.20)
	gsb2.set_corner_radius_all(3)
	_glossary_popup2.add_theme_stylebox_override("panel", gsb2)
	_glossary_rtl2 = RichTextLabel.new()
	_glossary_rtl2.bbcode_enabled = true
	_glossary_rtl2.fit_content = true
	_glossary_rtl2.offset_left = 8.0
	_glossary_rtl2.offset_top = 6.0
	_glossary_rtl2.offset_right = -8.0
	_glossary_rtl2.offset_bottom = -6.0
	_glossary_rtl2.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glossary_popup2.add_child(_glossary_rtl2)
	add_child(_glossary_popup2)
	# Connect hover signals on each item slot
	for i: int in SLOT_COUNT:
		_item_slots[i].mouse_entered.connect(_on_qbar_slot_hover.bind(i))
		_item_slots[i].mouse_exited.connect(_on_qbar_slot_hover_end)

## Anchors _qbar_tooltip beside `rect` (above by default, below if there's no room) instead of
## following the mouse — see the "Quickbar hover tooltip" section comment above.
func _position_qbar_tooltip_near(rect: Rect2) -> void:
	var vp: Vector2 = get_viewport().get_visible_rect().size
	var tw: float = _qbar_tooltip.size.x
	var th: float = maxf(_qbar_tooltip.size.y, _qbar_tooltip_rtl.get_content_height() + 14.0)
	var tx: float = clampf(rect.position.x, 4.0, vp.x - tw - 4.0)
	var ty: float = rect.position.y - th - 6.0
	if ty < 4.0:
		ty = rect.position.y + rect.size.y + 6.0
	_qbar_tooltip.position = Vector2(tx, ty)

func _on_qbar_slot_hover(idx: int) -> void:
	if _qbar_tooltip == null:
		return
	_qbar_hover_source_rect = get_action_slot_global_rect(idx)
	var bar: Array = GameState.player_ability_bar if _ability_bar_mode else GameState.player_quickbar
	var item_or_ability: Variant = bar[idx] if idx < bar.size() else null
	# Thrown-item range preview: hovering a thrown weapon in the item bar shows its range/
	# long_range as a world-space backdrop (player.gd._update_ranged_range_preview()'s
	# quickbar-hover branch), same visual as Shift-hovering an equipped ranged weapon.
	var hover_thrown: Item = item_or_ability as Item if not _ability_bar_mode else null
	GameState.quickbar_hover_thrown_item = hover_thrown if (hover_thrown != null and hover_thrown.item_type == Item.Type.WEAPON and hover_thrown.is_thrown) else null
	if item_or_ability == null:
		return
	var text: String = ""
	if _ability_bar_mode:
		var ab := item_or_ability as Ability
		if ab == null:
			return
		# Spell-backed abilities already carry the full structured SpellTooltip.build() output
		# (name/school/range/etc.) in their own description — see GameState._build_spell_ability()/
		# _build_hellish_rebuke_ability() — so they skip the generic "[b]Name[/b]\n" wrap here to
		# avoid double-printing the name.
		if ab.ability_id.begins_with("spell:") or ab.ability_id == "hellish_rebuke_toggle":
			text = ab.description
			if not ab.is_active and not GameState.is_ability_usable(ab):
				var spell_unusable_reason: String = GameState.ability_unusable_reason(ab)
				if spell_unusable_reason != "":
					text = "[color=#ff4c4c]%s[/color]\n%s" % [spell_unusable_reason, text]
		else:
			text = "[b]%s[/b]\n%s" % [ab.ability_name, ab.description]
			if not ab.is_active and not GameState.is_ability_usable(ab):
				var unusable_reason: String = GameState.ability_unusable_reason(ab)
				if unusable_reason != "":
					text = "[color=#ff4c4c]%s[/color]\n%s" % [unusable_reason, text]
	else:
		var item := item_or_ability as Item
		if item == null:
			return
		if item.item_type == Item.Type.WEAPON:
			text = WeaponTooltip.build(item)
		elif ArmorTooltip.is_armor_item(item):
			text = ArmorTooltip.build(item)
		else:
			text = "[b]%s[/b]" % item.item_name
		if not item.description.is_empty():
			text += "\n[color=gray]%s[/color]" % item.description
		if item.requires_attunement:
			if item.is_attuned:
				text += "\n[color=#4aa3ff]Attuned[/color]"
			else:
				text += "\n[color=#4aa3ff]Requires Attunement[/color] [color=gray](set during a Long Rest)[/color]"
	if not _ability_bar_mode:
		var thrown_item := item_or_ability as Item
		if thrown_item != null and thrown_item.item_type == Item.Type.WEAPON and thrown_item.is_thrown:
			text += "\n[color=#999][font_size=11][left]Uses: %d/%d[/left][/font_size][/color]" % [thrown_item.uses_remaining, thrown_item.uses_max]
		var priced_item := item_or_ability as Item
		if priced_item != null and priced_item.item_type == Item.Type.WEAPON:
			var price_str: String = WeaponTooltip.format_price(priced_item)
			if not price_str.is_empty():
				text += "\n[color=#c9a227][font_size=11][right]%s[/right][/font_size][/color]" % price_str
	text += "\n[color=#555][font_size=9][left]Ctrl: inspect[/left][/font_size][/color]"
	_qbar_tooltip_rtl.text = text
	var hover_item: Item = item_or_ability as Item if not _ability_bar_mode else null
	var is_weapon_tooltip: bool = hover_item != null and (hover_item.item_type == Item.Type.WEAPON or ArmorTooltip.is_armor_item(hover_item))
	var qtw: float = 210.0 if is_weapon_tooltip else 172.0
	if _ability_bar_mode:
		var hover_ab := item_or_ability as Ability
		if hover_ab != null and (hover_ab.ability_id.begins_with("spell:") or hover_ab.ability_id == "hellish_rebuke_toggle"):
			var hover_sid: String = hover_ab.ability_id.trim_prefix("spell:") if hover_ab.ability_id.begins_with("spell:") else "hellish_rebuke"
			var hover_spell: Spell = SpellDb.get_spell(hover_sid)
			if hover_spell != null:
				qtw = maxf(qtw, SpellTooltip.required_width(hover_spell, 15))
	_qbar_tooltip_rtl.size = Vector2(qtw, 0)
	_qbar_tooltip.size = Vector2(qtw + 8.0, 60)
	_qbar_tooltip.visible = true
	_position_qbar_tooltip_near(_qbar_hover_source_rect)

## Hiding is driven entirely by _process()'s hover-chain rect check now — this stays connected to
## mouse_exited only to clear the unrelated thrown-item range preview.
func _on_qbar_slot_hover_end() -> void:
	GameState.quickbar_hover_thrown_item = null

## Race trait hover (nested glossary): a "race_trait:<id>" link (RaceTooltip.build()'s per-trait
## line, only shown by the "race_bonus" status-tray icon — see _on_status_tray_icon_hovered())
## opens this SAME level-1 popup a plain weapon-mastery "keyword:" link already uses, just with
## RaceTooltip.build_trait_detail()'s body instead of a flat KEYWORD_GLOSSARY string. That body may
## itself contain further [url=race_sub:...] links (Celestial Revelation's 3 forms) — the popup's
## own RichTextLabel is interactive (PASS+meta_hover, set up in _ready()) precisely so hovering one
## of THOSE opens a level-2 popup via _on_glossary_meta_hover_started() below. Hiding is NOT done
## here on meta_hover_ended (that would fire the instant the cursor leaves the trigger link, even
## if heading toward the popup itself) — see _process()'s rect-containment check instead.
func _on_qbar_meta_hover_started(meta: Variant) -> void:
	var m: String = str(meta)
	if m.begins_with("keyword:") and _glossary_popup != null:
		var kw: String = m.substr(8)
		if WeaponTooltip.KEYWORD_GLOSSARY.has(kw):
			_glossary_rtl.text = WeaponTooltip.KEYWORD_GLOSSARY[kw]
			_glossary_rtl.size = Vector2(160.0, 0)
			_glossary_popup.size = Vector2(168.0, 60)
			_glossary_popup.visible = true
	elif m.begins_with("race_trait:") and _glossary_popup != null:
		var trait_id: String = m.substr(11)
		var t: Dictionary = RaceTooltip.find_trait(GameState.player_stats, trait_id)
		if not t.is_empty():
			_glossary_rtl.text = RaceTooltip.build_trait_detail(t)
			_glossary_rtl.size = Vector2(190.0, 0)
			_glossary_popup.size = Vector2(198.0, 60)
			_glossary_popup.visible = true

func _on_qbar_meta_hover_ended(_meta: Variant) -> void:
	pass

## Level-2 popup: a link inside the level-1 glossary popup's own RichTextLabel opens this
## terminal popup — either a "race_sub:<trait_id>:<sub_id>" link (e.g. "Heavenly Wings" under
## Celestial Revelation) OR a plain "keyword:<id>" condition link (e.g. "Frightened" inside
## Halfling's Brave description, auto-linkified by WeaponTooltip.linkify_conditions()) — a trait
## description can contain either kind, sometimes both in different traits, so this must handle
## both instead of only the race_sub case (bugfix: it used to silently no-op on a plain keyword
## link, e.g. hovering "Frightened" inside Brave's popup showed nothing).
func _on_glossary_meta_hover_started(meta: Variant) -> void:
	var m: String = str(meta)
	if _glossary_popup2 == null:
		return
	if m.begins_with("keyword:"):
		var kw: String = m.substr(8)
		if not WeaponTooltip.KEYWORD_GLOSSARY.has(kw):
			return
		_glossary_rtl2.text = WeaponTooltip.KEYWORD_GLOSSARY[kw]
		_glossary_rtl2.size = Vector2(160.0, 0)
		_glossary_popup2.size = Vector2(168.0, 60)
		_glossary_popup2.visible = true
		return
	if not m.begins_with("race_sub:"):
		return
	var parts: PackedStringArray = m.substr(9).split(":", true, 1)
	if parts.size() != 2:
		return
	var sub: Dictionary = RaceTooltip.find_sub(GameState.player_stats, parts[0], parts[1])
	if sub.is_empty():
		return
	_glossary_rtl2.text = RaceTooltip.build_sub_detail(sub)
	_glossary_rtl2.size = Vector2(190.0, 0)
	_glossary_popup2.size = Vector2(198.0, 60)
	_glossary_popup2.visible = true

func _on_glossary_meta_hover_ended(_meta: Variant) -> void:
	pass

# ── Log tooltip ───────────────────────────────────────────────────────────────

func _setup_log_tooltip() -> void:
	_log_tooltip = Panel.new()
	_log_tooltip.visible = false
	_log_tooltip.z_index = 30
	_log_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.05, 0.05, 0.09, 0.97)
	sb.set_border_width_all(1)
	sb.border_color = Color(0.55, 0.50, 0.35)
	sb.set_corner_radius_all(3)
	_log_tooltip.add_theme_stylebox_override("panel", sb)
	_log_tooltip_rtl = RichTextLabel.new()
	_log_tooltip_rtl.bbcode_enabled = true
	_log_tooltip_rtl.fit_content = true
	_log_tooltip_rtl.offset_left = 8.0
	_log_tooltip_rtl.offset_top = 6.0
	_log_tooltip_rtl.offset_right = -8.0
	_log_tooltip_rtl.offset_bottom = -6.0
	_log_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_log_tooltip_rtl.add_theme_font_size_override("font_size", 12)
	_log_tooltip.add_child(_log_tooltip_rtl)
	add_child(_log_tooltip)

const _TOOLTIP_W: float = 220.0

func _process(delta: float) -> void:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport().get_visible_rect().size
	_process_bar_drag(mp)
	# Log tooltip positioning
	if _log_tooltip != null and _log_tooltip_visible:
		var content_h: float = _log_tooltip_rtl.get_content_height()
		_log_tooltip_rtl.size = Vector2(_TOOLTIP_W - 16.0, content_h)
		_log_tooltip.size = Vector2(_TOOLTIP_W, content_h + 14.0)
		var th: float = _log_tooltip.size.y
		var tx: float = clampf(mp.x - _TOOLTIP_W * 0.5, 4.0, vp.x - _TOOLTIP_W - 4.0)
		var ty: float = mp.y - th - 14.0
		if ty < 4.0:
			ty = mp.y + 18.0
		_log_tooltip.position = Vector2(tx, ty)
	# Quickbar tooltip positioning — always anchored to _qbar_hover_source_rect (the slot/icon that
	# triggered it), never the mouse, so the mouse can travel onto it to hover keyword links
	# without the box drifting away. Recomputed every frame (idempotent, since the source rect
	# doesn't change) purely to track content-height changes (a live use-count, etc.).
	if _qbar_tooltip != null and _qbar_tooltip.visible:
		var qw: float = _qbar_tooltip.size.x
		var qh: float = _qbar_tooltip_rtl.get_content_height() + 14.0
		_qbar_tooltip_rtl.size = Vector2(qw - 16.0, qh - 14.0)
		_qbar_tooltip.size = Vector2(qw, qh)
		_position_qbar_tooltip_near(_qbar_hover_source_rect)
	# Glossary popup positioning (appears beside qbar tooltip)
	if _glossary_popup != null and _glossary_popup.visible:
		var gw: float = _glossary_popup.size.x
		var gh: float = _glossary_rtl.get_content_height() + 14.0
		_glossary_rtl.size = Vector2(gw - 16.0, gh - 14.0)
		_glossary_popup.size = Vector2(gw, gh)
		var qpos: Vector2 = _qbar_tooltip.position if _qbar_tooltip != null and _qbar_tooltip.visible else mp
		var gx: float = clampf(qpos.x + _qbar_tooltip.size.x + 4.0, 4.0, vp.x - gw - 4.0)
		_glossary_popup.position = Vector2(gx, qpos.y)
	# Level-2 glossary popup (race-trait sub-option, e.g. Celestial Revelation's 3 forms) —
	# appears beside the level-1 popup that opened it.
	if _glossary_popup2 != null and _glossary_popup2.visible and _glossary_popup != null:
		var gw2: float = _glossary_popup2.size.x
		var gh2: float = _glossary_rtl2.get_content_height() + 14.0
		_glossary_rtl2.size = Vector2(gw2 - 16.0, gh2 - 14.0)
		_glossary_popup2.size = Vector2(gw2, gh2)
		var gx2: float = clampf(_glossary_popup.position.x + _glossary_popup.size.x + 4.0, 4.0, vp.x - gw2 - 4.0)
		_glossary_popup2.position = Vector2(gx2, _glossary_popup.position.y)
	# Hover chain (source slot/icon → qbar tooltip → glossary popup → glossary popup2) hides one
	# level at a time as the mouse backs out, closing everything once it leaves the whole chain —
	# meta_hover_ended/mouse_exited alone can't drive this, since moving from a trigger INTO the
	# popup/level it opened must not hide it. Each level stays open while the mouse is over itself
	# or anything nested deeper than it; the outermost (the tooltip) additionally stays open while
	# the mouse is back on the original source trigger.
	var _over_source: bool = _qbar_hover_source_rect.has_point(mp)
	var _over_qbar: bool = _qbar_tooltip != null and _qbar_tooltip.visible and Rect2(_qbar_tooltip.position, _qbar_tooltip.size).has_point(mp)
	var _over_glossary: bool = _glossary_popup != null and _glossary_popup.visible and Rect2(_glossary_popup.position, _glossary_popup.size).has_point(mp)
	var _over_glossary2: bool = _glossary_popup2 != null and _glossary_popup2.visible and Rect2(_glossary_popup2.position, _glossary_popup2.size).has_point(mp)
	var _over_any_chain: bool = _over_source or _over_qbar or _over_glossary or _over_glossary2
	if _over_any_chain:
		_hover_chain_outside_time = 0.0
	else:
		_hover_chain_outside_time += delta
	var _chain_grace_expired: bool = _hover_chain_outside_time > _HOVER_CHAIN_HIDE_GRACE_SEC
	if _glossary_popup2 != null and _glossary_popup2.visible and not _over_glossary and not _over_glossary2 and _chain_grace_expired:
		_glossary_popup2.visible = false
	if _glossary_popup != null and _glossary_popup.visible and not _over_qbar and not _over_glossary and not _over_glossary2 and _chain_grace_expired:
		_glossary_popup.visible = false
	if _qbar_tooltip != null and _qbar_tooltip.visible and not _over_source and not _over_qbar and not _over_glossary and not _over_glossary2 and _chain_grace_expired:
		_qbar_tooltip.visible = false

func _on_log_meta_hover_started(meta: Variant) -> void:
	if _log_tooltip == null:
		return
	var tooltip_text: String = _format_tooltip(str(meta))
	if tooltip_text.is_empty():
		return
	_log_tooltip_rtl.text = tooltip_text
	_log_tooltip_rtl.size = Vector2(_TOOLTIP_W - 16.0, 0)
	_log_tooltip.size = Vector2(_TOOLTIP_W, 60)
	_log_tooltip_visible = true
	_log_tooltip.visible = true

func _on_log_meta_hover_ended(_meta: Variant) -> void:
	_log_tooltip_visible = false
	if _log_tooltip != null:
		_log_tooltip.visible = false

func _format_tooltip(meta: String) -> String:
	var colon: int = meta.find(":")
	if colon < 0:
		return ""
	var kind: String = meta.substr(0, colon)
	var params: Dictionary = {}
	for kv: String in meta.substr(colon + 1).split(","):
		var eq: int = kv.find("=")
		if eq >= 0:
			params[kv.substr(0, eq)] = kv.substr(eq + 1)
	match kind:
		"hit", "miss":   return TooltipFormatters.fmt_hit_tooltip(params, false)
		"rhit", "rmiss": return TooltipFormatters.fmt_hit_tooltip(params, true)
		"sphit":         return TooltipFormatters.fmt_sphit_tooltip(params)
		"thrhit":        return TooltipFormatters.fmt_hit_tooltip(params, false)
		"dmg":           return TooltipFormatters.fmt_dmg_tooltip(params)
		"mmdmg":         return TooltipFormatters.fmt_mmdmg_tooltip(params)
		"heal":          return TooltipFormatters.fmt_heal_tooltip(params)
		"hplvl":         return TooltipFormatters.fmt_hplvl_tooltip(params)
		"save", "check": return TooltipFormatters.fmt_save_tooltip(params)
		"stealth":       return TooltipFormatters.fmt_stealth_tooltip(params)
		"ehit":          return TooltipFormatters.fmt_ehit_tooltip(params)
		"edmg":          return TooltipFormatters.fmt_edmg_tooltip(params)
		"ret":           return TooltipFormatters.fmt_ret_tooltip(params)
		"catk":          return TooltipFormatters.fmt_catk_tooltip(params)
		"grz":           return TooltipFormatters.fmt_grz_tooltip(params)
		"frzhit":        return TooltipFormatters.fmt_frenzy_hit_tooltip(params)
		"frzdmg":        return TooltipFormatters.fmt_frenzy_dmg_tooltip(params)
		"msn":           return TooltipFormatters.fmt_masochist_tooltip(params)
		"conc":          return TooltipFormatters.fmt_conc_tooltip(params)
		"stonedr":       return TooltipFormatters.fmt_stonedr_tooltip(params)
	return ""
