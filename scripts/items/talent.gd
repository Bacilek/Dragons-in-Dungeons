class_name Talent
extends Resource

@export var talent_id: String = ""
@export var talent_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var tier: int = 1
@export var class_id: int = -1  # Stats.CharacterClass enum value; -1 = universal
@export var max_rank: int = 3
# ranks[0] = rank-1 effects, ranks[1] = rank-2 effects, etc.
# Each dict uses keys specific to the talent (designer-chosen; only read by _apply_talent_rank).
@export var ranks: Array[Dictionary] = []

func rank_description(rank: int) -> String:
	if rank < 1 or rank > ranks.size():
		return ""
	return ranks[rank - 1].get("description", "")
