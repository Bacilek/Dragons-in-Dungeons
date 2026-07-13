class_name ShopRoom
extends StandardRoom
# Structural placeholder stub (special-rooms-economy-design.md §4.1, session 7b).
# Inherits StandardRoom's min_size()/max_size()/max_connections()/paint() defaults —
# the shop-specific overrides (dead-end 5x5–7x7 room) and content land in session 7e.
# Never add a has_content()/fallback runtime check: the fallback IS this inheritance.


func _init() -> void:
	type_id = "shop"
