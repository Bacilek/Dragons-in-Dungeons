class_name SecretRoom
extends StandardRoom
# Structural placeholder stub (special-rooms-economy-design.md §4.4, session 7b).
# Inherits StandardRoom's min_size()/max_size()/max_connections()/paint() defaults —
# the secret-specific overrides (dead-end 5x5–6x6 room) and hidden-door content land
# in session 7f. Never add a has_content()/fallback runtime check: the fallback IS
# this inheritance.


func _init() -> void:
	type_id = "secret"
