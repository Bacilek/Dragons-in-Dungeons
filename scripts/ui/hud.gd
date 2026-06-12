extends CanvasLayer

@onready var floor_label: Label = $Panel/FloorLabel
@onready var hp_label: Label = $Panel/HPLabel
@onready var log_label: RichTextLabel = $LogPanel/LogLabel

var _log_messages: Array[String] = []
const MAX_LOG_MESSAGES: int = 15

func _ready() -> void:
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	GameState.player_died.connect(_on_player_died)
	GameState.combat_message.connect(_on_combat_message)
	floor_label.text = "Floor: %d" % GameState.current_floor
	var s: Stats = GameState.player_stats
	hp_label.text = "HP: %d / %d" % [s.current_hp, s.max_hp]

func _on_floor_changed(new_floor: int) -> void:
	floor_label.text = "Floor: %d" % new_floor
	_log_messages.clear()
	log_label.text = ""

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	hp_label.text = "HP: %d / %d" % [current_hp, max_hp]

func _on_player_died() -> void:
	var game_over: PackedScene = preload("res://scenes/ui/game_over.tscn")
	get_tree().root.add_child(game_over.instantiate())

func _on_combat_message(msg: String) -> void:
	_log_messages.push_front(msg)
	if _log_messages.size() > MAX_LOG_MESSAGES:
		_log_messages.resize(MAX_LOG_MESSAGES)
	log_label.text = "\n".join(_log_messages)
