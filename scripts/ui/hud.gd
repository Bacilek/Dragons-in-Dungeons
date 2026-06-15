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
const HP_BAR_H: float = 28.0
const EXP_BAR_H: float = 20.0
const SLOT_COUNT: int = 9

var _item_slots: Array[Button] = []
var _slot_qty_labels: Array[Label] = []
var _log_messages: Array[String] = []
const MAX_LOG_MESSAGES: int = 25
var _hunger_label: Label
var _poison_icon: ColorRect
var _burning_icon: ColorRect
var _bleeding_icon: ColorRect
var _slowed_icon: ColorRect
var _inventory_overlay_ref: Node = null
var _debug_panel_ref: Node = null
var _hit_dice_label: Label
var _compass_panel: Panel
var _compass_arrow_label: Label
var _compass_dist_label: Label
var _stairs_found_this_floor: bool = false

const CLASS_PORTRAIT: Dictionary = {
	Stats.CharacterClass.BARBARIAN: "res://sprites/characters/knight_m_idle_anim_f0.png",
	Stats.CharacterClass.RANGER:    "res://sprites/characters/elf_m_idle_anim_f0.png",
	Stats.CharacterClass.WIZARD:    "res://sprites/characters/wizzard_m_idle_anim_f0.png",
	Stats.CharacterClass.CLERIC:    "res://sprites/characters/dwarf_m_idle_anim_f0.png",
}

func _ready() -> void:
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_exp_changed.connect(_on_player_exp_changed)
	GameState.player_leveled_up.connect(_on_player_leveled_up)
	GameState.player_died.connect(_on_player_died)
	GameState.player_won.connect(_on_player_won)
	GameState.combat_message.connect(_on_combat_message)
	GameState.inventory_changed.connect(_refresh_inventory)
	GameState.hunger_changed.connect(_on_hunger_changed)
	GameState.player_status_changed.connect(_on_status_changed)
	GameState.class_chosen.connect(_on_class_chosen)
	GameState.short_rest_changed.connect(_update_hit_dice_label)
	GameState.stairs_discovered.connect(_on_stairs_discovered)
	TurnManager.player_turn_started.connect(_update_compass)
	portrait.pressed.connect(_on_portrait_pressed)
	portrait.focus_mode = Control.FOCUS_NONE
	wait_button.pressed.connect(_on_wait_pressed)
	search_button.pressed.connect(_on_search_pressed)
	interact_button.pressed.connect(_on_interact_pressed)

	for i: int in SLOT_COUNT:
		var slot: Button = get_node("ActionBar/ItemSlot%d" % i)
		_item_slots.append(slot)
		slot.pressed.connect(_on_slot_pressed.bind(i))
		slot.gui_input.connect(_on_slot_gui_input.bind(i))
		# Small quantity badge in bottom-right corner
		var qty_lbl := Label.new()
		qty_lbl.add_theme_font_size_override("font_size", 11)
		qty_lbl.add_theme_color_override("font_color", Color.WHITE)
		qty_lbl.add_theme_color_override("font_shadow_color", Color.BLACK)
		qty_lbl.add_theme_constant_override("shadow_offset_x", 1)
		qty_lbl.add_theme_constant_override("shadow_offset_y", 1)
		qty_lbl.text = ""
		qty_lbl.anchor_left = 1.0
		qty_lbl.anchor_right = 1.0
		qty_lbl.anchor_top = 1.0
		qty_lbl.anchor_bottom = 1.0
		qty_lbl.offset_left = -32.0
		qty_lbl.offset_top = -18.0
		qty_lbl.offset_right = -2.0
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

	# Hunger label — created programmatically below the HP bar
	_hunger_label = Label.new()
	_hunger_label.add_theme_font_size_override("font_size", 12)
	_hunger_label.position = hp_fill.position + Vector2(0.0, HP_BAR_H + 1.0)
	_hunger_label.size = Vector2(BAR_W, 14.0)
	$StatsPanel.add_child(_hunger_label)
	_update_hunger_label()

	# Status icons (poison=green, burning=orange, bleeding=red, slowed=brown) below portrait
	_poison_icon   = _make_status_dot(Color(0.20, 0.85, 0.35), Vector2(2.0,  2.0))
	_burning_icon  = _make_status_dot(Color(1.00, 0.45, 0.10), Vector2(16.0, 2.0))
	_bleeding_icon = _make_status_dot(Color(0.80, 0.0,  0.0),  Vector2(30.0, 2.0))
	_slowed_icon   = _make_status_dot(Color(0.55, 0.35, 0.10), Vector2(44.0, 2.0))
	$StatsPanel.add_child(_poison_icon)
	$StatsPanel.add_child(_burning_icon)
	$StatsPanel.add_child(_bleeding_icon)
	$StatsPanel.add_child(_slowed_icon)
	_update_status_icons()

	# Hit dice label below level label
	_hit_dice_label = Label.new()
	_hit_dice_label.add_theme_font_size_override("font_size", 11)
	_hit_dice_label.add_theme_color_override("font_color", Color(0.75, 0.85, 1.0))
	_hit_dice_label.position = Vector2(4.0, 84.0)
	_hit_dice_label.size = Vector2(64.0, 14.0)
	_hit_dice_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	$StatsPanel.add_child(_hit_dice_label)
	_update_hit_dice_label()

	# Stairs compass — top-right corner, hidden until stairs discovered
	_compass_panel = Panel.new()
	_compass_panel.anchor_left = 1.0
	_compass_panel.anchor_right = 1.0
	_compass_panel.offset_left = -114.0
	_compass_panel.offset_top = 4.0
	_compass_panel.offset_right = -4.0
	_compass_panel.offset_bottom = 84.0
	_compass_panel.visible = false
	add_child(_compass_panel)

	var title_lbl := Label.new()
	title_lbl.text = "Stairs"
	title_lbl.add_theme_font_size_override("font_size", 12)
	title_lbl.add_theme_color_override("font_color", Color(0.9, 0.8, 0.4))
	title_lbl.position = Vector2(0.0, 2.0)
	title_lbl.size = Vector2(110.0, 18.0)
	title_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_panel.add_child(title_lbl)

	_compass_arrow_label = Label.new()
	_compass_arrow_label.text = "?"
	_compass_arrow_label.add_theme_font_size_override("font_size", 36)
	_compass_arrow_label.add_theme_color_override("font_color", Color(1.0, 0.9, 0.3))
	_compass_arrow_label.position = Vector2(0.0, 20.0)
	_compass_arrow_label.size = Vector2(110.0, 44.0)
	_compass_arrow_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_panel.add_child(_compass_arrow_label)

	_compass_dist_label = Label.new()
	_compass_dist_label.text = ""
	_compass_dist_label.add_theme_font_size_override("font_size", 11)
	_compass_dist_label.add_theme_color_override("font_color", Color(0.7, 0.7, 0.7))
	_compass_dist_label.position = Vector2(0.0, 64.0)
	_compass_dist_label.size = Vector2(110.0, 14.0)
	_compass_dist_label.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	_compass_panel.add_child(_compass_dist_label)

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

func _on_stairs_discovered() -> void:
	_stairs_found_this_floor = true
	if _compass_panel != null:
		_compass_panel.visible = true
	_update_compass()

func _update_compass() -> void:
	if _compass_panel == null or not _compass_panel.visible:
		return
	if not _stairs_found_this_floor:
		return
	var diff: Vector2i = GameState.current_stairs_pos - GameState.player_grid_pos
	if diff == Vector2i.ZERO:
		_compass_arrow_label.text = "★"
		_compass_dist_label.text = "here!"
		return
	# Pick arrow character from 8 directions (dx/dy sign + which axis dominates)
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
	_compass_arrow_label.text = arrow
	var dist: int = maxi(ax, ay)
	_compass_dist_label.text = "%d tiles" % dist

func _make_status_dot(color: Color, offset: Vector2) -> ColorRect:
	var dot := ColorRect.new()
	dot.color = color
	dot.size = Vector2(12.0, 12.0)
	dot.position = portrait.position + offset
	dot.visible = false
	return dot

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
	_stairs_found_this_floor = false
	if _compass_panel != null:
		_compass_panel.visible = true
		if _compass_arrow_label != null:
			_compass_arrow_label.text = "?"
		if _compass_dist_label != null:
			_compass_dist_label.text = "find it"

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
		var raw = GameState.player_quickbar[slot_index]
		if raw == null:
			return
		var it := raw as Item
		if it.item_type == Item.Type.FOOD:
			GameState.player_throw_primed.emit(it)

# ── Bar updates ───────────────────────────────────────────────────────────────

func _update_hp_bar(current_hp: int, max_hp: int) -> void:
	var ratio: float = clampf(float(current_hp) / float(max_hp), 0.0, 1.0)
	hp_fill.size = Vector2(BAR_W * ratio, HP_BAR_H)
	hp_label.text = "%d / %d" % [current_hp, max_hp]

func _update_exp_bar(exp: int, exp_needed: int, level: int) -> void:
	var ratio: float = clampf(float(exp) / float(exp_needed), 0.0, 1.0)
	exp_fill.size = Vector2(BAR_W * ratio, EXP_BAR_H)
	exp_label.text = "%d / %d XP" % [exp, exp_needed]
	level_label.text = "Lv.%d" % level

# ── Inventory ─────────────────────────────────────────────────────────────────

func _refresh_inventory() -> void:
	for i: int in SLOT_COUNT:
		var raw = GameState.player_quickbar[i]
		var slot: Button = _item_slots[i]
		var qty_lbl: Label = _slot_qty_labels[i]
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

func _refresh_popup() -> void:
	if not stats_popup.visible:
		return
	var s: Stats = GameState.player_stats
	$StatsPopup/HPStatLabel.text    = "HP: %d / %d" % [s.current_hp, s.max_hp]
	$StatsPopup/StrengthLabel.text  = "STR: %d (%+d)" % [s.strength, s.str_modifier()]
	$StatsPopup/DexLabel.text       = "DEX: %d (%+d)" % [s.dexterity, s.dex_modifier()]
	$StatsPopup/ConLabel.text       = "CON: %d (%+d)" % [s.constitution, s.con_modifier()]
	$StatsPopup/ACLabel.text        = "AC: %d" % s.armor_class
	$StatsPopup/LevelStatLabel.text = "Level: %d" % s.character_level
	$StatsPopup/ExpStatLabel.text   = "EXP: %d / %d" % [s.experience, s.exp_to_next()]
