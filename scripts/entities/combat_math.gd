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

# Finesse: attack/damage modifier uses whichever of STR/DEX is higher instead of always STR.
static func finesse_modifier(str_mod: int, dex_mod: int, is_finesse: bool) -> int:
	return maxi(str_mod, dex_mod) if is_finesse else str_mod

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

# Generic bonus-damage-source encoding for the "dmg" tooltip (TooltipFormatters.fmt_dmg_tooltip).
# Lets any new bonus damage source (talent, item effect, etc.) show up in the hover tooltip by
# just appending one {label, color, value} entry here — no matching edit needed in
# tooltip_formatters.gd. Zero-value sources are dropped by the caller before encoding (see
# player.gd._bump_attack()/PlayerRanged.ranged_attack() for the reference call site).
# Encoding avoids "," and "=" (already used by the surrounding key=value,key2=value2 meta string)
# by using "|" to separate a source's fields and ";" to separate sources.
static func encode_bonus_sources(sources: Array) -> String:
	var parts: PackedStringArray = []
	for s: Dictionary in sources:
		parts.append("%s|%s|%d" % [s["label"], s["color"], s["value"]])
	return ";".join(parts)

static func decode_bonus_sources(encoded: String) -> Array:
	var result: Array = []
	if encoded.is_empty():
		return result
	for part: String in encoded.split(";"):
		var fields: PackedStringArray = part.split("|")
		if fields.size() != 3:
			continue
		result.append({"label": fields[0], "color": fields[1], "value": int(fields[2])})
	return result
