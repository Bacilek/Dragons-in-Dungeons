class_name GardenRoom
extends StandardRoom
# Rest-stop room (special-rooms-economy-design.md §4.3, session 7d) — a pass-through room, so
# it inherits StandardRoom's default sizing/max_connections(); only paint() is overridden.
# Runtime content (Healing Herb on the grass) is DungeonFloor._spawn_garden_items().


func _init() -> void:
	type_id = "garden"


# Carpets most of the interior with GRASS and drops one small WATER pool, kept off the
# perimeter so doorways stay dry. Only ever overwrites FLOOR tiles — LevelPainter's level-wide
# overlays (pillars/chasms/water/mud/grass) run AFTER per-room paint and are all walkable, so
# connectivity is never at risk. Consumes rng draws only on floors where this room actually
# spawned (non-empty rect) — an intentional, accepted generation-footprint change, same as every
# other content session in this doc.
func paint(data: DungeonData, rng: RandomNumberGenerator) -> void:
	if rect == Rect2i():
		return

	for y: int in range(rect.position.y, rect.position.y + rect.size.y):
		for x: int in range(rect.position.x, rect.position.x + rect.size.x):
			var pos := Vector2i(x, y)
			if data.get_tile(x, y) != DungeonData.TileType.FLOOR:
				continue
			if pos == data.player_start or pos == data.stairs_pos:
				continue
			if rng.randf() < 0.6:
				data.grid[y][x] = DungeonData.TileType.GRASS

	# One small water pool: flood-fill from an interior anchor, inset 1 tile off every edge.
	var inset: Rect2i = rect.grow(-1)
	if inset.size.x < 1 or inset.size.y < 1:
		return
	var anchor := Vector2i(rng.randi_range(inset.position.x, inset.position.x + inset.size.x - 1),
							rng.randi_range(inset.position.y, inset.position.y + inset.size.y - 1))
	var dirs4: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
	var blob_size: int = rng.randi_range(4, 9)  # roughly a 2x2 to 3x3 blob
	var queue: Array = [anchor]
	var placed: int = 0
	while not queue.is_empty() and placed < blob_size:
		var cur: Vector2i = queue.pop_front()
		if not inset.has_point(cur):
			continue
		if data.get_tile(cur.x, cur.y) != DungeonData.TileType.FLOOR:
			continue
		if cur == data.player_start or cur == data.stairs_pos:
			continue
		data.grid[cur.y][cur.x] = DungeonData.TileType.WATER
		placed += 1
		RngUtil.shuffle(dirs4, rng)
		for d: Vector2i in dirs4:
			queue.append(cur + (d as Vector2i))
