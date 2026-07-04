# TEMPORARY verification script for the Phase 1 dungeon-generation refactor.
# Run:  Godot_v4.6.3..._console.exe --headless --path <project> --script res://scripts/dungeon/_verify/dump_gen.gd
# Dumps grid/rooms/player_start/stairs_pos/boss_room for fixed (seed, floor) pairs
# so pre- and post-refactor output can be diffed byte-for-byte.
# DELETE THIS FOLDER after verification.
extends SceneTree

func _init() -> void:
	# Fix the GLOBAL RNG: dungeon_generator has two unseeded dirs4.shuffle() calls
	# (known Phase 2 bug, deliberately preserved). Seeding the global RNG makes those
	# shuffles reproducible across runs so old-vs-new diffs are meaningful.
	seed(424242)
	var out: String = ""
	for pair: Array in [[12345, 1], [12345, 3], [12345, 5], [98765, 7], [555, 10], [-42, 2]]:
		var s: int = pair[0]
		var f: int = pair[1]
		var d: DungeonData = DungeonGenerator.generate(s, f)
		out += "seed=%d floor=%d\n" % [s, f]
		out += "player_start=%s stairs=%s boss=%s start_room=%s\n" % [d.player_start, d.stairs_pos, d.boss_room, d.start_room]
		out += "rooms=%s\n" % [str(d.rooms)]
		for y: int in d.height:
			var line: String = ""
			for x: int in d.width:
				line += str(d.grid[y][x])
			out += line + "\n"
	var fpath: String = OS.get_environment("DUMP_PATH")
	if fpath == "":
		fpath = "user://gen_dump.txt"
	var fa := FileAccess.open(fpath, FileAccess.WRITE)
	fa.store_string(out)
	fa.close()
	print("dumped to ", fpath)
	quit()
