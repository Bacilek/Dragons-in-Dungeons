extends CanvasLayer

@onready var floor_label: Label = $Panel/FloorLabel
@onready var hp_label: Label = $Panel/HPLabel

func _ready() -> void:
	GameState.floor_changed.connect(_on_floor_changed)
	GameState.player_hp_changed.connect(_on_player_hp_changed)
	floor_label.text = "Floor: %d" % GameState.current_floor
	var s: Stats = GameState.player_stats
	hp_label.text = "HP: %d / %d" % [s.current_hp, s.max_hp]

func _on_floor_changed(new_floor: int) -> void:
	floor_label.text = "Floor: %d" % new_floor

func _on_player_hp_changed(current_hp: int, max_hp: int) -> void:
	hp_label.text = "HP: %d / %d" % [current_hp, max_hp]
