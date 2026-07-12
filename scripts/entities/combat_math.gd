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

# Halfling Lucky: rolling a natural 1 on a d20 (attack roll or ability check) triggers an
# automatic reroll that MUST be used, even if the new roll is also a 1 (single reroll only,
# per 5e Lucky). Centralized here so every player d20 roll goes through the same rule — never
# applies to enemy rolls (GameState.player_stats is the player's own Stats). Returns
# {value, lucky} — value is the die result callers should actually use downstream.
static func halfling_reroll(die: int) -> Dictionary:
	if die == 1 and GameState.player_stats != null and GameState.player_stats.character_race == Stats.CharacterRace.HALFLING:
		return {"value": Rng.roll(20), "lucky": true}
	return {"value": die, "lucky": false}

# Wraps a finished chat-log line in dark green + a shamrock marker whenever Halfling Luck fired
# on this roll — the "Saint Patrick's luck" visual cue.
static func wrap_halfling_luck(text: String, lucky: bool) -> String:
	return "[color=#2e8b3d]☘ %s[/color]" % text if lucky else text

# ADV/DISADV house rule: sources are counted (adv_count, disadv_count); net = adv_count -
# disadv_count decides the outcome (>0 ADV, <0 DISADV, ==0 normal). die2 is ALWAYS rolled
# independently when ADV/DISADV is active — nat 1 on die1 does NOT skip it. Each d20 individually
# goes through halfling_reroll() (a Halfling attacking with Advantage can get BOTH dice rerolled
# if both come up 1).
# Returns {die1, die2, die, adv, disadv, lucky1, lucky2, lucky} — die1/die2 are the (post-reroll)
# rolls, die is the resolved value (max for ADV, min for DISADV, die1 otherwise), adv/disadv are
# the resolved booleans, lucky1/lucky2 flag which die (if any) was Halfling-rerolled, lucky is
# their OR (convenience for callers that don't care which die).
static func roll_with_adv_disadv(adv_count: int, disadv_count: int) -> Dictionary:
	var net: int = adv_count - disadv_count
	var adv: bool = net > 0
	var disadv: bool = net < 0
	var r1: Dictionary = halfling_reroll(Rng.roll(20))
	var die1: int = r1["value"]
	var lucky1: bool = r1["lucky"]
	var die2: int = die1
	var lucky2: bool = false
	var die: int = die1
	if adv and not disadv:
		var r2: Dictionary = halfling_reroll(Rng.roll(20))
		die2 = r2["value"]
		lucky2 = r2["lucky"]
		die = maxi(die1, die2)
	elif disadv and not adv:
		var r2: Dictionary = halfling_reroll(Rng.roll(20))
		die2 = r2["value"]
		lucky2 = r2["lucky"]
		die = mini(die1, die2)
	return {"die1": die1, "die2": die2, "die": die, "adv": adv, "disadv": disadv,
		"lucky1": lucky1, "lucky2": lucky2, "lucky": lucky1 or lucky2}

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

# Total melee range in tiles: base 1 + Branching Strike's talent bonus + a Reach weapon's own +1
# (e.g. Glaive). These two sources are additive (unlike Branching Strike's own ranks, which replace).
static func melee_reach(weapon: Item, branching_strike_rank: int) -> int:
	var bonus: int = melee_reach_bonus(branching_strike_rank)
	if weapon != null and weapon.is_reach:
		bonus += 1
	return 1 + bonus

# Psycho R3 (Barbarian Tier 1): while attacking with Advantage, crit range widens to 19-20.
# Shared by every player attack-roll site (melee, cleave, off-hand, ranged, thrown, OA) instead
# of duplicating the one-line condition — see markdowns/barbarian_base.md.
static func is_critical_hit(die: int, adv: bool) -> bool:
	if die == 20:
		return true
	return adv and die == 19 and GameState.get_talent_rank("psycho") >= 3

# Divine Fury: rank 3 replaces rank 2's formula (not additive) — always exactly one formula per rank.
static func divine_fury_flat_bonus(rank: int, level: int) -> int:
	match rank:
		2: return level / 4
		3: return level / 2
	return 0

# Encodes a list of {name, amount, color} bonus-damage-source dicts into one dmg_meta field
# ("bonus="), dropping zero-amount entries. Lets tooltip_formatters.gd render any number of
# named bonus-damage lines (Rage, Frenzy, Ironwood Bark, Divine Fury, ...) generically — a
# future damage source only needs to append a dict here, never a matching tooltip_formatters.gd
# edit. Fields are "|"-joined and entries ";"-joined since dmg_meta itself splits on "," and "=".
static func encode_bonus_sources(sources: Array) -> String:
	var parts: PackedStringArray = []
	for s: Dictionary in sources:
		var amount: int = s.get("amount", 0)
		if amount == 0:
			continue
		parts.append("%s|%d|%s" % [s.get("name", ""), amount, s.get("color", "red")])
	return ";".join(parts)

# Inverse of encode_bonus_sources() — returns Array[Dictionary] of {name, amount, color}.
static func decode_bonus_sources(encoded: String) -> Array:
	var result: Array = []
	if encoded.is_empty():
		return result
	for part: String in encoded.split(";"):
		var fields: PackedStringArray = part.split("|")
		if fields.size() == 3:
			result.append({"name": fields[0], "amount": int(fields[1]), "color": fields[2]})
	return result
