extends CanvasLayer

@onready var floor_label: Label = $Panel/VBox/FloorLabel
@onready var new_game_button: Button = $Panel/VBox/NewGameButton

func _ready() -> void:
	floor_label.text = "You reached floor %d" % GameState.current_floor
	new_game_button.pressed.connect(_on_new_game)

func _on_new_game() -> void:
	GameState.start_new_run()
	get_tree().reload_current_scene()
