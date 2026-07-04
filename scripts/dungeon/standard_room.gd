class_name StandardRoom
extends Room
# Plain floor room. paint() is inherited as a no-op — BSP already carved plain
# floor during Build. Future special room types (TrapRoom, ShopRoom, ...) extend
# this class; placeholder types simply don't override paint() (architecture §3).


func _init() -> void:
	type_id = "standard"
