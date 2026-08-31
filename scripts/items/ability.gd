class_name Ability
extends Resource

# Unique string ID used by player.gd to dispatch activation logic.
@export var ability_id: String = ""
@export var ability_name: String = ""
@export var description: String = ""
@export var icon_path: String = ""
@export var uses_remaining: int = 0
@export var uses_max: int = 0
# Cooldown model (Hybrid class — docs/architecture/hybrid-class-design.md). cooldown_max == 0
# means "not a cooldown ability" (every existing ability). cooldown_remaining ticks down once per
# real player turn in player.gd._on_turn_started(); GameState.is_ability_usable() gates on it.
# Never serialized (mid-floor transient); RewindManager snapshots it.
@export var cooldown_max: int = 0
@export var cooldown_remaining: int = 0
# Essence cost (Hybrid nova abilities). 0 = free / cooldown-based. Mutually exclusive with
# cooldown_max > 0 (authoring error to set both).
@export var essence_cost: int = 0
# For toggle abilities (e.g. Reckless Attack): true while toggled on.
@export var is_active: bool = false
# Passive abilities are shown only in the talent screen, never placed in the ability bar.
@export var is_passive: bool = false

func get_display_name() -> String:
	return ability_name

func has_uses() -> bool:
	return uses_max == 0 or uses_remaining > 0  # uses_max == 0 means infinite

func is_on_cooldown() -> bool:
	return cooldown_remaining > 0
