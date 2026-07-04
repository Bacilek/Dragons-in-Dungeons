# TEMPORARY verification script for the Phase 1 dungeon-generation refactor.
# Run:  Godot_v4.6.3..._console.exe --headless --path <project> --script res://scripts/dungeon/_verify/dump_gen.gd
# Dumps grid/rooms/player_start/stairs_pos/boss_room for fixed (seed, floor) pairs
# so pre- and post-refactor output can be diffed byte-for-byte.
# DELETE THIS FOLDER after verification.
extends SceneTree

func _init() -> void:
	# Phase 2: the formerly-unseeded dirs4.shuffle() calls are fixed (RngUtil.shuffle
	# with the seeded rng), so the global RNG is deliberately NOT seeded here anymore —
	# two consecutive runs producing identical dumps now proves generation is fully
	# seeded, with no hidden global-RNG dependence.
	randomize()
	var out: String = ""
	for pair: Array in [[12345, 1], [12345, 3], [12345, 5], [98765, 7], [555, 10], [-42, 2]]:
		var s: int = pair[0]
		var f: int = pair[1]
		var d: DungeonData = DungeonGenerator.generate(s, f)
		out += "seed=%d floor=%d feeling=%s\n" % [s, f, d.feeling]
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
