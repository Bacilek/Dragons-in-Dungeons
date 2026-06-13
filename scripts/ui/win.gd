extends CanvasLayer

@onready var play_again_button: Button = $Panel/VBox/PlayAgainButton

func _ready() -> void:
	play_again_button.pressed.connect(_on_play_again)

func _on_play_again() -> void:
	GameState.start_new_run()
	var tree := get_tree()
	get_parent().remove_child(self)
	queue_free()
	tree.reload_current_scene()
