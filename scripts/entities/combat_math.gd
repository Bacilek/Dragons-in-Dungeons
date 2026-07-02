class_name CombatMath
extends RefCounted

# Pure ADV/DISADV roll resolution and weapon-proficiency math shared by melee/cleave/ranged
# attacks. Static-func-only helper (same pattern as scripts/ui/tooltip_formatters.gd) split
# out of player.gd — see scripts/entities/CLAUDE.md.
#
# The bonus-damage STACKING sequence (Frenzy/Ironwood Bark/Divine Fury summation) and the full
# hit/miss/log flow are inherently stateful (they read/write per-turn talent flags interleaved
# with early returns) and deliberately stay in player.gd's _bump_attack()/_ranged_attack() —
# see the "Bonus damage stacking" rule in scripts/entities/CLAUDE.md.

# ADV/DISADV house rule: sources are counted (adv_count, disadv_count); net = adv_count -
# disadv_count decides the outcome (>0 ADV, <0 DISADV, ==0 normal). die2 is ALWAYS rolled
# independently when ADV/DISADV is active — nat 1 on die1 does NOT skip it.
# Returns {die1, die2, die, adv, disadv} — die1/die2 are the raw rolls, die is the resolved
# value (max for ADV, min for DISADV, die1 otherwise), adv/disadv are the resolved booleans.
static func roll_with_adv_disadv(adv_count: int, disadv_count: int) -> Dictionary:
	var net: int = adv_count - disadv_count
	var adv: bool = net > 0
	var disadv: bool = net < 0
	var die1: int = randi_range(1, 20)
	var die2: int = die1
	var die: int = die1
	if adv and not disadv:
		die2 = randi_range(1, 20)
		die = maxi(die1, die2)
	elif disadv and not adv:
		die2 = randi_range(1, 20)
		die = mini(die1, die2)
	return {"die1": die1, "die2": die2, "die": die, "adv": adv, "disadv": disadv}

# Weapon proficiency: unarmed strikes are always proficient. A Simple/Martial weapon only adds
# proficiency_bonus to the attack roll if the matching proficiency flag is set — lacking
# proficiency doesn't block using the weapon, it just drops this bonus.
static func weapon_prof_bonus(weapon: Item, proficiency_bonus: int, proficient_simple: bool, proficient_martial: bool) -> int:
	if weapon == null:
		return proficiency_bonus
	var proficient: bool = true
	match weapon.weapon_category:
		"Simple":  proficient = proficient_simple
		"Martial": proficient = proficient_martial
	return proficiency_bonus if proficient else 0

# Branching Strike: reach bonus (in tiles) for Heavy/Versatile melee weapons. R2 replaces R1 (not additive).
static func melee_reach_bonus(rank: int) -> int:
	if rank >= 2: return 2
	if rank >= 1: return 1
	return 0

# Divine Fury: rank 3 replaces rank 2's formula (not additive) — always exactly one formula per rank.
static func divine_fury_flat_bonus(rank: int, level: int) -> int:
	match rank:
		2: return level / 4
		3: return level / 2
	return 0
