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

const BAR_W: float    = 174.0
const HP_BAR_H: float = 15.0
const EXP_BAR_H: float = 12.0
const SLOT_COUNT: int = 5

var _item_slots: Array[Button] = []
var _log_messages: Array[String] = []
const MAX_LOG_MESSAGES: int = 15

func _ready() -> void:
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_exp_changed.connect(_on_player_exp_changed)
	GameState.player_leveled_up.connect(_on_player_leveled_up)
	GameState.player_died.connect(_on_player_died)
	GameState.player_won.connect(_on_player_won)
	GameState.combat_message.connect(_on_combat_message)
	GameState.inventory_changed.connect(_refresh_inventory)
	portrait.pressed.connect(_on_portrait_pressed)
	wait_button.pressed.connect(_on_wait_pressed)
	search_button.pressed.connect(_on_search_pressed)

	for i: int in SLOT_COUNT:
		var slot: Button = get_node("ActionBar/ItemSlot%d" % i)
		_item_slots.append(slot)
		slot.pressed.connect(_on_slot_pressed.bind(i))
	_apply_slot_styles()

	var s: Stats = GameState.player_stats
	floor_label.text = "Floor: %d" % GameState.current_floor
	_update_hp_bar(s.current_hp, s.max_hp)
	_update_exp_bar(s.experience, s.exp_to_next(), s.character_level)
	_refresh_inventory()

	# Inventory overlay — add as sibling CanvasLayer so it floats above HUD
	var overlay_script = load("res://scripts/ui/inventory_overlay.gd")
	get_tree().root.call_deferred("add_child", overlay_script.new())

	# Class select screen — shown once per run before the first move
	var cs_script = load("res://scripts/ui/class_select.gd")
	get_tree().root.call_deferred("add_child", cs_script.new())

# ── Signal handlers ───────────────────────────────────────────────────────────

func _on_floor_changed(new_floor: int) -> void:
	floor_label.text = "Floor: %d" % new_floor
	_log_messages.clear()
	log_label.text = ""

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

func _on_wait_pressed() -> void:
	GameState.player_action_requested.emit("wait")

func _on_search_pressed() -> void:
	GameState.player_action_requested.emit("search")

func _on_slot_pressed(slot_index: int) -> void:
	var raw = GameState.player_quickbar[slot_index]
	if raw == null:
		return
	GameState.use_item(raw as Item)

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
		if raw == null:
			slot.text = ""
			slot.icon = null
		else:
			var it := raw as Item
			slot.text = it.get_display_name()
			if it.icon_path != "":
				slot.icon = load(it.icon_path)
				slot.expand_icon = true

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
