class_name TreasureRoom
extends StandardRoom
# Structural placeholder stub (special-rooms-economy-design.md §4.2, session 7b).
# Inherits StandardRoom's min_size()/max_size()/max_connections()/paint() defaults —
# the vault-specific overrides (dead-end 5x5–7x7 room) and content land in session 7c.
# Never add a has_content()/fallback runtime check: the fallback IS this inheritance.


func _init() -> void:
	type_id = "treasure"
