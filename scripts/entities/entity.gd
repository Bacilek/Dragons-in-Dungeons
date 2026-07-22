class_name Entity
extends CharacterBody2D

const TILE_SIZE: int = 16

signal move_completed

var grid_pos: Vector2i = Vector2i.ZERO
var stats: Stats
var _hp_bar: HealthBarNode
# True for the player and any allied entity (e.g. Wild Heart companion). Enemies leave this false.
# Used by Zealot's Zealous Presence to target "friendly entities in FOV" for its buff.
var is_friendly: bool = false
# Footprint in tiles, grid_pos is always the TOP-LEFT corner. Every entity defaults to 1x1;
# only Enemy ever sets this above (1,1) today (pool "size" key — see scripts/entities/CLAUDE.md's
# "Enemy D&D stat-block schema"). Kept on Entity, not Enemy, so occupied_tiles()/occupies()/
# min_dist_to()/nearest_occupied_tile() are usable generically wherever an Entity reference is on
# hand, and so a 1x1 Player/Companion reduces to exactly today's single-tile behavior for free.
var size: Vector2i = Vector2i.ONE

func _setup_hp_bar() -> void:
	_hp_bar = HealthBarNode.new()
	_hp_bar.position = Vector2(0.0, -20.0)
	_hp_bar.z_index = 10
	_hp_bar.z_as_relative = false
	add_child(_hp_bar)

func update_hp_bar() -> void:
	if _hp_bar != null and stats != null:
		_hp_bar.update_bar(stats.current_hp, stats.max_hp)

func take_turn() -> void:
	pass

func die() -> void:
	queue_free()

func move_to(new_pos: Vector2i, duration: float = 0.08) -> void:
	grid_pos = new_pos
	var tween := create_tween()
	tween.tween_property(self, "position", _tile_center(new_pos), duration)
	await tween.finished
	move_completed.emit()

func set_grid_pos(pos: Vector2i) -> void:
	grid_pos = pos
	position = _tile_center(pos)

# Center of the WxH footprint anchored at `pos` (its top-left corner) — reduces to the plain
# single-tile formula whenever size == ONE, so every pre-existing 1x1 entity is unaffected.
func _tile_center(pos: Vector2i) -> Vector2:
	return Vector2((pos.x + size.x * 0.5) * TILE_SIZE, (pos.y + size.y * 0.5) * TILE_SIZE)

## Every tile this entity's footprint currently covers, top-left first.
func occupied_tiles() -> Array[Vector2i]:
	var tiles: Array[Vector2i] = []
	for dy: int in size.y:
		for dx: int in size.x:
			tiles.append(grid_pos + Vector2i(dx, dy))
	return tiles

func occupies(pos: Vector2i) -> bool:
	return pos.x >= grid_pos.x and pos.x < grid_pos.x + size.x \
		and pos.y >= grid_pos.y and pos.y < grid_pos.y + size.y

## Chebyshev distance from `pos` to the NEAREST tile of this entity's footprint — the generic
## replacement for "distance to grid_pos" everywhere adjacency/range/LOS is checked against an
## entity that might be larger than 1x1 (today: only a Large enemy).
func min_dist_to(pos: Vector2i) -> int:
	var best: int = -1
	for t: Vector2i in occupied_tiles():
		var d: int = maxi(absi(pos.x - t.x), absi(pos.y - t.y))
		if best == -1 or d < best:
			best = d
	return best

## The specific occupied tile closest to `pos` (ties broken by occupied_tiles() iteration order,
## i.e. top-left first) — used as the concrete LOS/pathing origin/destination once min_dist_to()
## says "close enough".
func nearest_occupied_tile(pos: Vector2i) -> Vector2i:
	var best: Vector2i = grid_pos
	var best_d: int = -1
	for t: Vector2i in occupied_tiles():
		var d: int = maxi(absi(pos.x - t.x), absi(pos.y - t.y))
		if best_d == -1 or d < best_d:
			best_d = d
			best = t
	return best
