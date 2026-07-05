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

const BAR_W: float    = 320.0
const HP_BAR_H: float = 38.0
const THP_BAR_H: float = 6.0   # temp HP bar above HP fill
const EXP_BAR_H: float = 24.0
const SLOT_COUNT: int = 9

var _item_slots: Array[Button] = []
var _slot_qty_labels: Array[Label] = []
var _log_messages: Array[String] = []
const MAX_LOG_MESSAGES: int = 25
var _hunger_label: Label
var _temp_hp_fill: ColorRect  # light-blue temp HP bar above the HP fill
var _poison_icon: ColorRect
var _burning_icon: ColorRect
var _bleeding_icon: ColorRect
var _slowed_icon: ColorRect
var _rage_icon: TextureRect      # Primal Fury icon (rank-gradient) shown while raging
var _inventory_overlay_ref: Node = null
var _debug_panel_ref: Node = null
var _hit_dice_label: Label
var _compass: Compass
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
var _qbar_tooltip_frozen: bool = false
var _glossary_popup: Panel = null
var _glossary_rtl: RichTextLabel = null
const KEYWORD_GLOSSARY: Dictionary = {
	"heavy": "Heavy weapon.\nMelee: requires STR 13+.\nRanged: requires DEX 13+.\nAttacking without enough\nStrength/Dexterity imposes\nDisadvantage.",
	"two_handed": "Two-handed weapon.\nOccupies Main Hand.\nOff-hand cannot be used\nwhile equipped.",
	"cleave": "Mastery: Cleave.\nIf 2+ enemies are within\nmelee reach, this attack\nalso strikes the one closest\nto your primary target —\nwith its own attack roll\nand damage roll.",
	"simple": "Simple weapon.\nEasy to use — most\ncharacters are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"martial": "Martial weapon.\nRequires training — only\nsome classes are proficient.\nRed text means your class\nlacks this proficiency: you\ncan still attack with it,\nbut lose your proficiency\nbonus on the attack roll.",
	"vex": "Mastery: Vex.\nOn a hit, gain Advantage\non your next attack this\nround against the same\ntarget (any attack type).",
	"push": "Mastery: Push.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ DEX) or is shoved 1 tile\ndirectly away from you.\nHitting a wall deals 1d4\nBludgeoning instead of\nmoving; falling into a\nchasm removes it (loot,\nif any, appears a floor\ndown).",
	"finesse": "Finesse weapon.\nUse either STR or DEX\n(whichever is higher) for\nboth the attack roll and\nthe damage roll.",
	"light": "Light weapon.\nPair another Light weapon\nin the Off-hand to attack\nwith both. The Off-hand\nswing skips your ability\nmodifier on damage, unless\nit's negative.",
	"graze": "Mastery: Graze.\nOn a miss, still deal\ndamage equal to the\nability modifier used\nfor the attack (min 0).",
	"reach": "Reach weapon.\n+1 tile melee range —\ncan attack (and chase-\nattack) from 2 tiles away\ninstead of 1.",
	"topple": "Mastery: Topple.\nOn a hit, the target rolls\na CON save (DC 8 + Prof\n+ STR) or is knocked Prone,\nskipping its entire next turn.",
	"versatile": "Versatile weapon.\nClick the Main Hand slot\nto switch grip: one-handed\nuses the die shown, two-\nhanded uses the die listed\nhere instead.",
	"thrown": "Thrown weapon.\nRight-click to prime a\nthrow, then left-click a\ntarget tile — uses your\nmelee attack modifier.\nNormal range shown; beyond\nit (still within FOV) rolls\nwith Disadvantage. Has\nlimited uses before it\nbreaks.",
	"sap": "Mastery: Sap.\nOn a hit, the target has\nDisadvantage on its very\nnext attack, next turn.",
	"nick": "Mastery: Nick.\nWhile dual-wielding two\nLight weapons, make one\nfurther attack this turn —\nsame rules as the Off-hand\nswing (max 3 attacks total)."
}

# ── Extra popup labels (added programmatically to expand the stats popup) ─────
var _popup_prof_label: Label = null
var _popup_int_label: Label = null
var _popup_wis_label: Label = null
var _popup_cha_label: Label = null

# ── Always-visible AC label in StatsPanel ────────────────────────────────────
var _ac_label: Label = null

const CLASS_PORTRAIT: Dictionary = {
	Stats.CharacterClass.BARBARIAN: "res://sprites/characters/knight_m_idle_anim_f0.png",
	Stats.CharacterClass.RANGER:    "res://sprites/characters/elf_m_idle_anim_f0.png",
	Stats.CharacterClass.WIZARD:    "res://sprites/characters/wizzard_m_idle_anim_f0.png",
	Stats.CharacterClass.MONK:      "res://sprites/characters/dwarf_m_idle_anim_f0.png",
}

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey:
		var key := event as InputEventKey
		if key.pressed and not key.echo and key.physical_keycode == KEY_TAB:
			if not GameState.is_game_over and GameState.class_selected:
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

func _ready() -> void:
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_exp_changed.connect(_on_player_exp_changed)
	GameState.player_leveled_up.connect(_on_player_leveled_up)
	GameState.player_died.connect(_on_player_died)
	GameState.player_won.connect(_on_player_won)
	GameState.combat_message.connect(_on_combat_message)
	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.ability_bar_changed.connect(_refresh_inventory)
	GameState.hunger_changed.connect(_on_hunger_changed)
	GameState.player_status_changed.connect(_on_status_changed)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.short_rest_changed.connect(_update_hit_dice_label)
	_compass = Compass.new()
	add_child(_compass)
	_crit_banner = CritBanner.new()
	add_child(_crit_banner)
	GameState.stairs_discovered.connect(_compass.on_stairs_discovered)
	GameState.crit_banner.connect(_crit_banner.show_banner)
	TurnManager.player_turn_started.connect(_compass.update_display)
	TurnManager.player_turn_started.connect(_update_status_icons)
	portrait.pressed.connect(_on_portrait_pressed)
	portrait.focus_mode      = Control.FOCUS_NONE
	wait_button.focus_mode   = Control.FOCUS_NONE
	search_button.focus_mode = Control.FOCUS_NONE
	interact_button.focus_mode = Control.FOCUS_NONE
	wait_button.pressed.connect(_on_wait_pressed)
	search_button.pressed.connect(_on_search_pressed)
	interact_button.pressed.connect(_on_interact_pressed)

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

	# Hunger label — created programmatically below the HP bar
	_hunger_label = Label.new()
	_hunger_label.add_theme_font_size_override("font_size", 12)
	_hunger_label.position = hp_fill.position + Vector2(0.0, HP_BAR_H + 1.0)
	_hunger_label.size = Vector2(BAR_W, 14.0)
	$StatsPanel.add_child(_hunger_label)
	_update_hunger_label()

	# Status icons (poison=green, burning=orange, bleeding=red, slowed=brown, rage=crimson) below portrait
	_poison_icon   = _make_status_dot(Color(0.20, 0.85, 0.35), Vector2(2.0,  2.0))
	_burning_icon  = _make_status_dot(Color(1.00, 0.45, 0.10), Vector2(16.0, 2.0))
	_bleeding_icon = _make_status_dot(Color(0.80, 0.0,  0.0),  Vector2(30.0, 2.0))
	_slowed_icon   = _make_status_dot(Color(0.55, 0.35, 0.10), Vector2(44.0, 2.0))
	_rage_icon     = _make_status_icon_rect(Vector2(58.0, 2.0))
	$StatsPanel.add_child(_poison_icon)
	$StatsPanel.add_child(_burning_icon)
	$StatsPanel.add_child(_bleeding_icon)
	$StatsPanel.add_child(_slowed_icon)
	$StatsPanel.add_child(_rage_icon)
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

	# AC label — always visible to the right of the LevelLabel row
	_ac_label = Label.new()
	_ac_label.add_theme_font_size_override("font_size", 12)
	_ac_label.add_theme_color_override("font_color", Color(0.70, 0.90, 1.0))
	_ac_label.position = Vector2(72.0, 92.0)
	_ac_label.size = Vector2(120.0, 16.0)
	_ac_label.mouse_filter = Control.MOUSE_FILTER_IGNORE
	$StatsPanel.add_child(_ac_label)
	_update_ac_label()

	# Inventory overlay — add as sibling CanvasLayer so it floats above HUD
	var overlay_script = load("res://scripts/ui/inventory_overlay.gd")
	_inventory_overlay_ref = overlay_script.new()
	get_tree().root.call_deferred("add_child", _inventory_overlay_ref)

	# Class select screen — shown once per run before the first move
	var cs_script = load("res://scripts/ui/class_select.gd")
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

func _on_hunger_changed(_value: int) -> void:
	_update_hunger_label()

func _on_status_changed() -> void:
	_update_status_icons()

func _update_status_icons() -> void:
	if _poison_icon != null:
		_poison_icon.visible = GameState.player_stats.poison_turns > 0
	if _burning_icon != null:
		_burning_icon.visible = GameState.player_stats.burning_turns > 0
	if _bleeding_icon != null:
		_bleeding_icon.visible = GameState.player_stats.bleeding_turns > 0
	if _slowed_icon != null:
		_slowed_icon.visible = GameState.player_stats.slowed_turns > 0
	if _rage_icon != null:
		_rage_icon.visible = GameState.is_raging
		if GameState.is_raging:
			var rage_rank: int = maxi(GameState.get_talent_rank("rage"), 1)
			var icon_path: String = GameState.talent_icon_path("rage", rage_rank)
			if icon_path != "" and ResourceLoader.exists(icon_path):
				_rage_icon.texture = load(icon_path)

func _make_status_dot(color: Color, offset: Vector2) -> ColorRect:
	var dot := ColorRect.new()
	dot.color = color
	dot.size = Vector2(12.0, 12.0)
	dot.position = portrait.position + offset
	dot.visible = false
	return dot

func _make_status_icon_rect(offset: Vector2) -> TextureRect:
	var rect := TextureRect.new()
	rect.size = Vector2(12.0, 12.0)
	rect.position = portrait.position + offset
	rect.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	rect.ignore_texture_size = true  # without this, assigning a texture forces the control to its native pixel size (talent icons are 2048x2048)
	rect.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	rect.visible = false
	return rect

func _update_hunger_label() -> void:
	if _hunger_label == null:
		return
	match GameState.hunger_state:
		GameState.HungerState.SATIATED:
			_hunger_label.text = ""
		GameState.HungerState.HUNGRY:
			_hunger_label.text = "Hungry"
			_hunger_label.add_theme_color_override("font_color", Color(1.0, 0.80, 0.15))
		GameState.HungerState.STARVING:
			_hunger_label.text = "Starving!"
			_hunger_label.add_theme_color_override("font_color", Color(1.0, 0.20, 0.20))

func _on_class_chosen(cls: Stats.CharacterClass) -> void:
	var path: String = CLASS_PORTRAIT.get(cls, "res://sprites/characters/knight_m_idle_anim_f0.png")
	portrait.texture_normal = load(path)
	_update_hit_dice_label()

func _update_hit_dice_label() -> void:
	if _hit_dice_label == null:
		return
	var sides: int = GameState.hit_die_sides()
	var available: int = GameState.hit_dice
	_hit_dice_label.text = "d%d:%d" % [sides, available]

func _on_floor_changed(new_floor: int) -> void:
	floor_label.text = "Floor: %d" % new_floor
	_log_messages.clear()
	log_label.text = ""
	_update_hit_dice_label()
	_compass.reset_for_new_floor()

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	_update_hp_bar(current_hp, max_hp)
	_refresh_popup()

func _on_player_exp_changed(exp: int, exp_needed: int, level: int) -> void:
	_update_exp_bar(exp, exp_needed, level)
	_refresh_popup()

func _on_player_leveled_up(level: int) -> void:
	level_label.text = "Lv.%d" % level

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
		GameState.player_throw_primed.emit(it)

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
		slot.modulate = Color(1.0, 1.0, 1.0)  # reset tint from ability bar (e.g. reckless orange)
		if _slot_use_labels.size() > i:
			_slot_use_labels[i].visible = false
		if raw == null:
			slot.text = ""
			slot.icon = null
			qty_lbl.text = ""
		else:
			var it := raw as Item
			slot.text = ""
			if it.icon_path != "":
				slot.icon = load(it.icon_path)
				slot.expand_icon = true
			qty_lbl.text = "×%d" % it.quantity if it.quantity > 1 else ""

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
			if ab.icon_path != "":
				slot.icon = load(ab.icon_path)
				slot.expand_icon = true
			else:
				slot.text = ab.ability_name.left(4)
			if _slot_use_labels.size() > i:
				var use_lbl: Label = _slot_use_labels[i]
				use_lbl.visible = true
				if ab.uses_max == 0:
					# Passive / infinite uses.
					match ab.ability_id:
						"danger_sense":
							use_lbl.text = "passive"
							use_lbl.add_theme_color_override("font_color", Color(0.5, 0.5, 0.5))
						_:
							use_lbl.text = ""
				elif ab.ability_id == "rage" and GameState.is_raging:
					# While raging: show remaining turns instead of use count.
					use_lbl.text = "%dt" % GameState.rage_turns_remaining
					use_lbl.add_theme_color_override("font_color", Color(1.0, 0.35, 0.25))
				else:
					use_lbl.text = "%d/%d" % [ab.uses_remaining, ab.uses_max]
					var clr: Color = Color(1.0, 0.7, 0.2) if ab.uses_remaining > 0 else Color(0.5, 0.5, 0.5)
					use_lbl.add_theme_color_override("font_color", clr)
			# Modulate: locked-reckless = darker gray; active toggle = orange; exhausted = gray; else white
			var reckless_locked: bool = ab.ability_id == "reckless_attack" and GameState.reckless_locked_this_turn
			if reckless_locked:
				slot.modulate = Color(0.45, 0.45, 0.45)
			elif ab.is_active:
				slot.modulate = Color(1.0, 0.55, 0.1)
			elif ab.uses_remaining > 0 or ab.uses_max == 0:
				slot.modulate = Color(1.0, 1.0, 1.0)
			else:
				slot.modulate = Color(0.5, 0.5, 0.5)

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

func _unfreeze_qbar_tooltip() -> void:
	_qbar_tooltip_frozen = false
	if _qbar_tooltip != null:
		_qbar_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
		_qbar_tooltip.visible = false
	if _qbar_tooltip_rtl != null:
		_qbar_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	if _glossary_popup != null:
		_glossary_popup.visible = false

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_CTRL:
		if _qbar_tooltip_frozen:
			_unfreeze_qbar_tooltip()
			get_viewport().set_input_as_handled()
		elif _qbar_tooltip != null and _qbar_tooltip.visible:
			_qbar_tooltip_frozen = true
			_qbar_tooltip.mouse_filter     = Control.MOUSE_FILTER_STOP
			_qbar_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_PASS
			get_viewport().set_input_as_handled()

func _setup_quickbar_tooltip() -> void:
	_qbar_tooltip = Panel.new()
	_qbar_tooltip.visible = false
	_qbar_tooltip.z_index = 30
	_qbar_tooltip.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_qbar_tooltip_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_qbar_tooltip_rtl.meta_hover_started.connect(_on_qbar_meta_hover_started)
	_qbar_tooltip_rtl.meta_hover_ended.connect(_on_qbar_meta_hover_ended)
	_qbar_tooltip.add_child(_qbar_tooltip_rtl)
	add_child(_qbar_tooltip)
	# Keyword glossary popup (shared by qbar tooltip)
	_glossary_popup = Panel.new()
	_glossary_popup.visible = false
	_glossary_popup.z_index = 32
	_glossary_popup.mouse_filter = Control.MOUSE_FILTER_IGNORE
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
	_glossary_rtl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_glossary_popup.add_child(_glossary_rtl)
	add_child(_glossary_popup)
	# Connect hover signals on each item slot
	for i: int in SLOT_COUNT:
		_item_slots[i].mouse_entered.connect(_on_qbar_slot_hover.bind(i))
		_item_slots[i].mouse_exited.connect(_on_qbar_slot_hover_end)

func _is_weapon_category_proficient(category: String) -> bool:
	var s: Stats = GameState.player_stats
	match category:
		"Simple":  return s.proficient_simple_weapons
		"Martial": return s.proficient_martial_weapons
		_: return true

func _on_qbar_slot_hover(idx: int) -> void:
	if _qbar_tooltip_frozen:
		return
	if _qbar_tooltip == null:
		return
	var bar: Array = GameState.player_ability_bar if _ability_bar_mode else GameState.player_quickbar
	var item_or_ability: Variant = bar[idx] if idx < bar.size() else null
	if item_or_ability == null:
		return
	var text: String = ""
	if _ability_bar_mode:
		var ab := item_or_ability as Ability
		if ab == null:
			return
		text = "[b]%s[/b]\n%s" % [ab.ability_name, ab.description]
	else:
		var item := item_or_ability as Item
		if item == null:
			return
		text = "[b]%s[/b]" % item.item_name
		if item.item_type == Item.Type.WEAPON:
			if not item.weapon_mastery.is_empty():
				text += " [url=keyword:%s](%s)[/url]" % [item.weapon_mastery.to_lower(), item.weapon_mastery]
			var die_max: int = item.damage_die_max if item.damage_die_max > 0 else 0
			var die_str: String = "1d%d" % die_max if die_max > 0 else ""
			var bonus_str: String = "+%d" % item.bonus_damage if item.bonus_damage > 0 else ""
			var sep: String = " " if not die_str.is_empty() and not bonus_str.is_empty() else ""
			var type_str: String = " [color=gray]%s[/color]" % item.damage_type if not item.damage_type.is_empty() else ""
			if not die_str.is_empty() or not bonus_str.is_empty():
				text += "\n%s%s%s%s" % [die_str, sep, bonus_str, type_str]
			if not item.weapon_category.is_empty():
				var cat_color: String = "white" if _is_weapon_category_proficient(item.weapon_category) else "red"
				text += "\n[color=%s][url=keyword:%s]%s[/url][/color]" % [cat_color, item.weapon_category.to_lower(), item.weapon_category]
			if item.is_ranged:
				text += "\nrange: %d tiles [color=gray](long: FOV, DISADV)[/color]" % item.range
				if not item.ammo_item_name.is_empty():
					text += "\n[color=gray]Requires: %s[/color]" % item.ammo_item_name
			else:
				text += "\nrange: %d tile%s" % [2 if item.is_reach else 1, "s" if item.is_reach else ""]
			var props: Array[String] = []
			if item.is_two_handed:
				props.append("[url=keyword:two_handed]Two-handed[/url]")
			if item.is_heavy:
				props.append("[url=keyword:heavy]Heavy[/url]")
			if item.is_finesse:
				props.append("[url=keyword:finesse]Finesse[/url]")
			if item.is_light:
				props.append("[url=keyword:light]Light[/url]")
			if item.is_reach:
				props.append("[url=keyword:reach]Reach[/url]")
			if item.is_versatile:
				var grip_str: String = "two" if item.is_two_handed else "one"
				props.append("[url=keyword:versatile]Versatile (1d%d %s-handed)[/url]" % [item.versatile_die_max, grip_str])
			if item.is_thrown:
				props.append("[url=keyword:thrown]Thrown (%d/FOV)[/url]" % item.range)
			if not props.is_empty():
				text += "\n%s" % ", ".join(props)
		if not item.description.is_empty():
			text += "\n[color=gray]%s[/color]" % item.description
	if not _ability_bar_mode:
		var thrown_item := item_or_ability as Item
		if thrown_item != null and thrown_item.item_type == Item.Type.WEAPON and thrown_item.is_thrown:
			text += "\n[color=#999][font_size=11][right]Uses: %d/%d[/right][/font_size][/color]" % [thrown_item.uses_remaining, thrown_item.uses_max]
	text += "\n[color=#555][font_size=9][right]Ctrl: inspect[/right][/font_size][/color]"
	_qbar_tooltip_rtl.text = text
	_qbar_tooltip_rtl.size = Vector2(172.0, 0)
	_qbar_tooltip.size = Vector2(180.0, 60)
	_qbar_tooltip.visible = true

func _on_qbar_slot_hover_end() -> void:
	if _qbar_tooltip_frozen:
		return
	if _qbar_tooltip != null:
		_qbar_tooltip.visible = false
	if _glossary_popup != null:
		_glossary_popup.visible = false

func _on_qbar_meta_hover_started(meta: Variant) -> void:
	var m: String = str(meta)
	if m.begins_with("keyword:") and _glossary_popup != null:
		var kw: String = m.substr(8)
		if KEYWORD_GLOSSARY.has(kw):
			_glossary_rtl.text = KEYWORD_GLOSSARY[kw]
			_glossary_rtl.size = Vector2(160.0, 0)
			_glossary_popup.size = Vector2(168.0, 60)
			_glossary_popup.visible = true

func _on_qbar_meta_hover_ended(_meta: Variant) -> void:
	if _glossary_popup != null:
		_glossary_popup.visible = false

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

func _process(_delta: float) -> void:
	var mp: Vector2 = get_viewport().get_mouse_position()
	var vp: Vector2 = get_viewport().get_visible_rect().size
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
	# Quickbar tooltip positioning
	if _qbar_tooltip != null and _qbar_tooltip.visible:
		var qw: float = _qbar_tooltip.size.x
		var qh: float = _qbar_tooltip_rtl.get_content_height() + 14.0
		_qbar_tooltip_rtl.size = Vector2(qw - 16.0, qh - 14.0)
		_qbar_tooltip.size = Vector2(qw, qh)
		var tx: float = clampf(mp.x - qw * 0.5, 4.0, vp.x - qw - 4.0)
		var ty: float = mp.y - qh - 14.0
		if ty < 4.0:
			ty = mp.y + 18.0
		_qbar_tooltip.position = Vector2(tx, ty)
	# Glossary popup positioning (appears beside qbar tooltip)
	if _glossary_popup != null and _glossary_popup.visible:
		var gw: float = _glossary_popup.size.x
		var gh: float = _glossary_rtl.get_content_height() + 14.0
		_glossary_rtl.size = Vector2(gw - 16.0, gh - 14.0)
		_glossary_popup.size = Vector2(gw, gh)
		var qpos: Vector2 = _qbar_tooltip.position if _qbar_tooltip != null and _qbar_tooltip.visible else mp
		var gx: float = clampf(qpos.x + _qbar_tooltip.size.x + 4.0, 4.0, vp.x - gw - 4.0)
		_glossary_popup.position = Vector2(gx, qpos.y)

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
		"thrhit":        return TooltipFormatters.fmt_hit_tooltip(params, false)
		"dmg":           return TooltipFormatters.fmt_dmg_tooltip(params)
		"heal":          return TooltipFormatters.fmt_heal_tooltip(params)
		"save", "check": return TooltipFormatters.fmt_save_tooltip(params)
		"ehit":          return TooltipFormatters.fmt_ehit_tooltip(params)
		"edmg":          return TooltipFormatters.fmt_edmg_tooltip(params)
		"ret":           return TooltipFormatters.fmt_ret_tooltip(params)
		"catk":          return TooltipFormatters.fmt_catk_tooltip(params)
		"grz":           return TooltipFormatters.fmt_grz_tooltip(params)
	return ""
