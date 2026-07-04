# TEMPORARY: finds (seed, floor) pairs where LoopBuilder exhausts all retries,
# then runs full DungeonGenerator.generate() on them to prove the BspBuilder
# fallback path produces a valid, connected floor. DELETE with the _verify folder.
extends SceneTree

func _init() -> void:
	randomize()
	var found: int = 0
	for s: int in range(1, 21):
		for f: int in range(1, 11):
			var floor_seed: int = s ^ (f * 0x9e3779b9)
			var rng := RandomNumberGenerator.new()
			rng.seed = floor_seed
			var feeling: String = "" if f % 5 == 0 else FloorFeeling.roll(rng)
			var rooms: Array = FloorPlanner.plan(f, feeling, rng)
			var data: DungeonData = null
			for attempt: int in 3:
				var sub_rng := RandomNumberGenerator.new()
				sub_rng.seed = floor_seed + (attempt * 0x1000193)
				data = LoopBuilder.build(rooms, sub_rng)
				if data != null:
					break
			if data != null:
				continue
			found += 1
			# Full orchestration must fall back to BspBuilder and still be valid.
			var d: DungeonData = DungeonGenerator.generate(s, f)
			var ok: bool = d != null and not d.rooms.is_empty() \
				and d.grid[d.stairs_pos.y][d.stairs_pos.x] == DungeonData.TileType.STAIRS_DOWN
			# connectivity: BFS start -> stairs
			var visited: Dictionary = {d.player_start: true}
			var queue: Array = [d.player_start]
			var reached: bool = false
			var dirs: Array = [Vector2i(0, -1), Vector2i(0, 1), Vector2i(-1, 0), Vector2i(1, 0)]
			while not queue.is_empty():
				var cur: Vector2i = queue.pop_front()
				if cur == d.stairs_pos:
					reached = true
					break
				for dv in dirs:
					var nxt: Vector2i = cur + (dv as Vector2i)
					if not visited.has(nxt) and d.is_walkable(nxt):
						visited[nxt] = true
						queue.append(nxt)
			print("fallback floor seed=%d floor=%d -> valid=%s connected=%s rooms=%d" % [s, f, ok, reached, d.rooms.size()])
	print("fallback floors exercised: %d" % found)
	quit()
