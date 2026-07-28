extends CanvasLayer

@onready var floor_label: Label = $Panel/VBox/FloorLabel
@onready var try_again_button: Button = $Panel/VBox/TryAgainButton
@onready var new_game_button: Button = $Panel/VBox/NewGameButton

func _ready() -> void:
	floor_label.text = "You reached floor %d" % GameState.current_floor
	# Only offer "Try Again" when there's an actual character-creation snapshot to rebuild from
	# (see GameState.snapshot_character_creation()) — otherwise it would silently fall back to
	# the full character-creation flow anyway, which is what "New Game" already does.
	try_again_button.visible = not GameState.character_creation_snapshot.is_empty()
	try_again_button.pressed.connect(_on_try_again)
	new_game_button.pressed.connect(_on_new_game)

func _on_try_again() -> void:
	GameState.retry_same_character()
	_reload()

func _on_new_game() -> void:
	GameState.start_new_run()
	_reload()

func _reload() -> void:
	var tree := get_tree()
	get_parent().remove_child(self)
	queue_free()
	tree.reload_current_scene()
