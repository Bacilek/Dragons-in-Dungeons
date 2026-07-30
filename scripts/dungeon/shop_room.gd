class_name ShopRoom
extends StandardRoom
# Dead-end vault-style room (special-rooms-economy-design.md §4.1, session 7e). Same shape as
# TreasureRoom (5x5-7x7, max_connections() = 1) so the one connecting corridor reads as a clear
# "shop nook" off the main path; paint() stays a no-op guard — a shop is plain floor, its content
# is the runtime Shopkeeper prop. Runtime content — the shopkeeper prop + generated stock — is
# DungeonFloor._spawn_shop() (scripts/world/CLAUDE.md).


func _init() -> void:
	type_id = "shop"


func min_size() -> Vector2i:
	return Vector2i(5, 5)


func max_size() -> Vector2i:
	return Vector2i(7, 7)


func max_connections() -> int:
	return 1


func paint(_data: DungeonData, _rng: RandomNumberGenerator) -> void:
	if rect == Rect2i():
		return
	# No tile changes — a shop is plain floor; the override exists only for the guard/symmetry.
