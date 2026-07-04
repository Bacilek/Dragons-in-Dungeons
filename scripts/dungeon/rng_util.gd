class_name RngUtil
extends RefCounted
# Static-func-only helper (same pattern as CombatMath / TooltipFormatters).
# Godot's Array.shuffle() only uses the GLOBAL RNG — there is no built-in seeded
# array shuffle — so every shuffle inside seeded generation code must go through
# this instead (SEEDED_FLOOR_POPULATION.md §3). Lives in scripts/dungeon/ because
# generation code must not depend on scene-tree scripts.


static func shuffle(arr: Array, rng: RandomNumberGenerator) -> void:
	for i: int in range(arr.size() - 1, 0, -1):
		var j: int = rng.randi_range(0, i)
		var tmp: Variant = arr[i]
		arr[i] = arr[j]
		arr[j] = tmp
