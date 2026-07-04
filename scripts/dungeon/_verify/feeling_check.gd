# TEMPORARY Phase 2 verification: feeling distribution + water_mult scaling.
# Run: Godot_..._console.exe --headless --path <project> --script res://scripts/dungeon/_verify/feeling_check.gd
# DELETE with the rest of _verify/ after migration.
extends SceneTree

func _init() -> void:
	randomize()

	# (b)/(c) distribution: roll like the orchestrator does across many floors.
	var counts: Dictionary = {}
	var seed_val: int = 12345
	for floor_num: int in range(1, 401):
		var rng := RandomNumberGenerator.new()
		rng.seed = seed_val ^ (floor_num * 0x9e3779b9)
		var f: String = "" if floor_num % 5 == 0 else FloorFeeling.roll(rng)
		if floor_num % 5 == 0 and f != "":
			print("FAIL: boss floor ", floor_num, " got feeling ", f)
		counts[f] = int(counts.get(f, 0)) + 1
	print("distribution over 400 floors (80 boss): ", counts)

	# (d) water_mult: same seeded stream, paint with "" vs "water", count WATER tiles.
	for trial: int in 3:
		var results: Array = []
		for feeling: String in ["", "water"]:
			var rng := RandomNumberGenerator.new()
			rng.seed = 777 + trial
			var rooms: Array = FloorPlanner.plan(1, feeling, rng)
			var data: DungeonData = BspBuilder.build(rooms, rng)
			data.player_start = Vector2i(1, 1)
			data.stairs_pos = Vector2i(2, 2)
			LevelPainter.paint(data, rooms, rng, feeling)
			var water: int = 0
			for y: int in data.height:
				for x: int in data.width:
					if data.grid[y][x] == DungeonData.TileType.WATER:
						water += 1
			results.append(water)
		print("trial ", trial, ": water tiles no-feeling=", results[0], " water-feeling=", results[1])
	quit()
