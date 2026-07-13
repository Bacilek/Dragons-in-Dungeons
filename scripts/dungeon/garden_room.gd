class_name GardenRoom
extends StandardRoom
# Structural placeholder stub (special-rooms-economy-design.md §4.3, session 7b).
# Inherits StandardRoom's min_size()/max_size()/max_connections()/paint() defaults —
# the grass/water paint() body and Healing Herb content land in session 7d.
# Never add a has_content()/fallback runtime check: the fallback IS this inheritance.


func _init() -> void:
	type_id = "garden"
