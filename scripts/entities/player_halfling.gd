class_name PlayerHalfling
extends Node

# Halfling race feature: Nimbleness ("you can move through the space of any creature that is a
# size larger than you"). Composition child-node split out of player.gd — see
# scripts/entities/CLAUDE.md's "Halfling" section. Implemented as a free, arm-then-click activated
# ability rather than a move-executor rule (direct owner request) — activating shows a blue,
# range-1/8-direction preview around the player (same tile-tint convention as a touch spell); if a
# tile holds an enemy LARGER than the Halfling — a real D&D size-category comparison
# (Enemy.creature_size, pool key "size_category", default "Medium" — every ordinary 1x1 enemy
# outsizes a Small Halfling, not just a physically-2x2-footprint one like Ogre/Spider — see root
# CLAUDE.md's "Multi-tile footprint" and Enemy.creature_size's own comment), clicking it teleports
# the player to the tile directly on the far side of that creature. Free action (no turn cost, same
# as Cloud Giant's Jaunt), capped at once per real round (`used_this_turn`, reset by player.gd's
# _on_turn_started()).

var player: Player
var nimbleness_mode_active: bool = false
var used_this_turn: bool = false

# 8 offsets around the player, E/SE/S/SW/W/NW/N/NE (Godot's +Y is down) — each already a unit
# Vector2i step, since every one of these tiles is by definition Chebyshev distance 1.
const DIR8: Array[Vector2i] = [
	Vector2i(1, 0), Vector2i(1, 1), Vector2i(0, 1), Vector2i(-1, 1),
	Vector2i(-1, 0), Vector2i(-1, -1), Vector2i(0, -1), Vector2i(1, -1),
]

func reset_turn() -> void:
	used_this_turn = false

func adjacent_tiles() -> Array[Vector2i]:
	var out: Array[Vector2i] = []
	for d: Vector2i in DIR8:
		out.append(player.grid_pos + d)
	return out

func activate_nimbleness() -> void:
	if used_this_turn and not GameState.invincible:
		GameState.game_log("[color=gray]Nimbleness: already used this round (free once per round).[/color]")
		return
	if nimbleness_mode_active:
		nimbleness_mode_active = false
		GameState.game_log("[color=gray]Nimbleness cancelled.[/color]")
		return
	nimbleness_mode_active = true
	GameState.game_log("[color=cyan]Nimbleness: click a larger creature next to you to slip past it.[/color]")

func cancel() -> void:
	nimbleness_mode_active = false

# D&D size-category rank, smallest to largest — a Halfling is Small (rank 1); Nimbleness applies
# to anything strictly larger. A footprint > 1 tile (Ogre/Spider) always counts as larger too, even
# on the off chance a future Large+ entry forgets to also set "size_category" explicitly.
const SIZE_RANK: Dictionary = {
	"Tiny": 0, "Small": 1, "Medium": 2, "Large": 3, "Huge": 4, "Gargantuan": 5,
}
const HALFLING_SIZE_RANK: int = 1  # Small

static func is_larger_than_halfling(enemy: Enemy) -> bool:
	if enemy.size.x * enemy.size.y > 1:
		return true
	return int(SIZE_RANK.get(enemy.creature_size, 2)) > HALFLING_SIZE_RANK

func resolve_nimbleness(clicked: Vector2i) -> void:
	if player._dungeon_floor == null:
		return
	var d: Vector2i = clicked - player.grid_pos
	if maxi(absi(d.x), absi(d.y)) != 1:
		GameState.game_log("[color=gray]Nimbleness: pick one of the tiles right next to you.[/color]")
		return
	var target: Enemy = player._dungeon_floor.get_targetable_enemy_at(clicked)
	if target == null or not is_larger_than_halfling(target):
		GameState.game_log("[color=gray]Nimbleness: no larger creature there.[/color]")
		return
	# Walk out along the same direction until we clear the creature's whole footprint (at most a
	# couple of steps — every Large enemy in this game today is a 2x2 block, root CLAUDE.md's
	# "Multi-tile footprint"), landing on the first tile past it.
	var landing: Vector2i = clicked
	var steps: int = 0
	while target.occupies(landing) and steps < 8:
		landing += d
		steps += 1
	if not player._dungeon_floor.is_walkable(landing) or player._dungeon_floor.get_enemy_at(landing) != null:
		GameState.game_log("[color=gray]Nimbleness: no room to come out the other side.[/color]")
		return
	if not GameState.invincible:
		used_this_turn = true
	var prev: Vector2i = player.grid_pos
	player.set_grid_pos(landing)
	GameState.game_log("[color=cyan]Halfling Nimbleness: you slip through %s's space.[/color]" % target.display_name)
	if player._dungeon_floor.has_door_at(prev):
		player._dungeon_floor.close_door(prev)
	player._dungeon_floor.update_fog(player.grid_pos)
