class_name TooltipFormatters
extends RefCounted

static func fmt_hit_tooltip(p: Dictionary, is_ranged: bool) -> String:
	var die: int    = int(p.get("die", "0"))
	var d1: int     = int(p.get("d1", str(die)))
	var d2: int     = int(p.get("d2", str(die)))
	# Ranged uses dex=; melee uses str=; Monk unarmed melee also uses dex= (no str= key).
	var use_dex: bool = is_ranged or p.has("dex")
	var stat_mod: int = int(p.get("dex" if use_dex else "str", "0"))
	var prof: int   = int(p.get("prof", "0"))
	var wpn: int    = int(p.get("wpn", "0"))
	var total: int  = int(p.get("total", "0"))
	var ac: int     = int(p.get("ac", "0"))
	var adv: bool   = p.get("adv", "0") == "1"
	var disadv: bool = p.get("disadv", "0") == "1"
	var n20: bool   = p.get("n20", "0") == "1"
	var n1: bool    = p.get("n1", "0") == "1"
	var lucky1: bool = p.get("lucky1", "0") == "1"
	var lucky2: bool = p.get("lucky2", "0") == "1"
	var stat_name: String = "DEX" if use_dex else "STR"
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if n20 else ("  [color=red]✕ FAIL[/color]" if n1 else "")
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	else:
		lines.append("d20 = [color=yellow]%d[/color]%s" % [die, die_suffix])
	if lucky1:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d1)
	if lucky2:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d2)
	if stat_mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (%s mod)" % [stat_mod, stat_name])
	if prof != 0:
		lines.append("[color=lightblue]+%d[/color]  (Proficiency)" % prof)
	if wpn != 0:
		lines.append("[color=lightblue]%+d[/color]  (weapon +%d)" % [wpn, wpn])
	lines.append("─────────────────")
	var vs: String
	if n20:
		vs = "[color=gold]CRITICAL HIT[/color]"
	elif n1:
		vs = "[color=red]CRITICAL FAIL[/color]"
	elif total >= ac:
		vs = "[color=green]HIT[/color]"
	else:
		vs = "[color=red]MISS[/color]"
	lines.append("= [color=yellow]%d[/color] vs AC %d  →  %s" % [total, ac, vs])
	return "\n".join(lines)

# Wizard cantrip spell attack roll — same shape as fmt_hit_tooltip but always labels the ability
# mod "INT" (the only spellcasting_ability Wizard uses in this slice — see
# scripts/items/spellcaster_state.gd). Kept as its own small function rather than threading a
# third stat-label mode through fmt_hit_tooltip.
static func fmt_sphit_tooltip(p: Dictionary) -> String:
	var die: int    = int(p.get("die", "0"))
	var d1: int     = int(p.get("d1", str(die)))
	var d2: int     = int(p.get("d2", str(die)))
	var stat_mod: int = int(p.get("int", "0"))
	var prof: int   = int(p.get("prof", "0"))
	var total: int  = int(p.get("total", "0"))
	var ac: int     = int(p.get("ac", "0"))
	var adv: bool   = p.get("adv", "0") == "1"
	var disadv: bool = p.get("disadv", "0") == "1"
	var n20: bool   = p.get("n20", "0") == "1"
	var n1: bool    = p.get("n1", "0") == "1"
	var lucky1: bool = p.get("lucky1", "0") == "1"
	var lucky2: bool = p.get("lucky2", "0") == "1"
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if n20 else ("  [color=red]✕ FAIL[/color]" if n1 else "")
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	else:
		lines.append("d20 = [color=yellow]%d[/color]%s" % [die, die_suffix])
	if lucky1:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d1)
	if lucky2:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d2)
	if stat_mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (INT mod)" % stat_mod)
	if prof != 0:
		lines.append("[color=lightblue]+%d[/color]  (Proficiency)" % prof)
	lines.append("─────────────────")
	var vs: String
	if n20:
		vs = "[color=gold]CRITICAL HIT[/color]"
	elif n1:
		vs = "[color=red]CRITICAL FAIL[/color]"
	elif total >= ac:
		vs = "[color=green]HIT[/color]"
	else:
		vs = "[color=red]MISS[/color]"
	lines.append("= [color=yellow]%d[/color] vs AC %d  →  %s" % [total, ac, vs])
	return "\n".join(lines)

static func fmt_dmg_tooltip(p: Dictionary) -> String:
	var roll: int  = int(p.get("roll", "0"))
	var dmax: int  = int(p.get("dmax", "0"))
	var wpn: int   = int(p.get("wpn", "0"))
	var str_mod: int = int(p.get("str", "0"))
	var dex_mod: int = int(p.get("dex", "0"))
	var crit: bool = p.get("crit", "0") == "1"
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	if dmax > 0:
		lines.append("1d%d = [color=yellow]%d[/color]" % [dmax, roll])
	else:
		lines.append("damage = [color=yellow]%d[/color]" % roll)
	if wpn != 0:
		lines.append("[color=lightblue]%+d[/color]  (weapon bonus)" % wpn)
	if str_mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (STR mod)" % str_mod)
	if dex_mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (DEX mod)" % dex_mod)
	# Generic bonus-damage sources (Rage, Frenzy, Ironwood Bark, Divine Fury, ...) — see
	# CombatMath.encode_bonus_sources()/decode_bonus_sources() in scripts/entities/combat_math.gd.
	# A future damage source only needs to be added to the encode call site, never here.
	for src: Dictionary in CombatMath.decode_bonus_sources(p.get("bonus", "")):
		lines.append("[color=%s]+%d[/color]  (%s)" % [src["color"], src["amount"], src["name"]])
	lines.append("─────────────────")
	# Multiplication always happens LAST — every source above is summed first, then doubled.
	if crit:
		lines.append("[color=gold]× 2[/color]  (Critical Hit!)")
	lines.append("= [color=yellow]%d[/color] dmg" % final_dmg)
	return "\n".join(lines)

static func fmt_grz_tooltip(p: Dictionary) -> String:
	var mod: int = int(p.get("mod", "0"))
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	lines.append("Graze: miss still deals")
	lines.append("[color=lightblue]%d[/color]  (ability mod)" % mod)
	lines.append("─────────────────")
	lines.append("= [color=yellow]%d[/color] dmg" % final_dmg)
	return "\n".join(lines)

# Frenzy (Berserker) — the attack roll and the damage roll are shown as two SEPARATE hover
# tooltips (mirrors every normal attack's hit:/dmg: split), since Frenzy's resolution is
# unusual enough (plain d20, no AC) that folding both into one number was confusing.

# "frzhit" — what the plain d20 roll means. No AC comparison, no attack modifier: nat 1 always
# misses (self-damage only), nat 20 always crits (double enemy damage, no self-damage), anything
# else is a shared hit.
static func fmt_frenzy_hit_tooltip(p: Dictionary) -> String:
	var die: int = int(p.get("die", "0"))
	var outcome: String = p.get("outcome", "hit")
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if outcome == "crit" else ("  [color=red]✕ FAIL[/color]" if outcome == "miss" else "")
	lines.append("d20 = [color=yellow]%d[/color]%s  (no modifier, no AC)" % [die, die_suffix])
	lines.append("─────────────────")
	match outcome:
		"miss": lines.append("Nat 1: you take the damage instead — target unharmed.")
		"crit": lines.append("Nat 20: target takes double damage — you take none.")
		_: lines.append("2–19: you and the target take the same damage.")
	return "\n".join(lines)

# "frzdmg" — the weapon-dice + STR/Rage modifier + Sadist Monster + crit-doubling breakdown for
# one of Frenzy's two damage numbers (the enemy's or the player's self-damage — same formula,
# just with sadist/crit zeroed out for the self-damage number).
static func fmt_frenzy_dmg_tooltip(p: Dictionary) -> String:
	var dmax: int   = int(p.get("dmax", "0"))
	var roll: int   = int(p.get("roll", "0"))
	var mod: int    = int(p.get("mod", "0"))
	var sadist: int = int(p.get("sadist", "0"))
	var crit: bool  = p.get("crit", "0") == "1"
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	lines.append("1d%d = [color=yellow]%d[/color]" % [dmax, roll])
	if mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (STR mod + Rage bonus)" % mod)
	if sadist != 0:
		lines.append("[color=red]+%d[/color]  (Sadist Monster)" % sadist)
	lines.append("─────────────────")
	if crit:
		lines.append("[color=gold]× 2[/color]  (Critical Hit!)")
	lines.append("= [color=yellow]%d[/color] dmg" % final_dmg)
	return "\n".join(lines)

# Masochist Monster R2 — rage bonus x 1d4 temp HP breakdown.
static func fmt_masochist_tooltip(p: Dictionary) -> String:
	var rage: int = int(p.get("rage", "0"))
	var rolls_str: String = String(p.get("rolls", ""))
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	lines.append("[color=lightblue]%d[/color]d4  (Rage bonus dice)" % rage)
	if not rolls_str.is_empty():
		var rolls: PackedStringArray = rolls_str.split("|")
		lines.append("[color=yellow]%s[/color]" % " + ".join(rolls))
	lines.append("─────────────────")
	lines.append("= [color=yellow]%d[/color] temp HP" % final_dmg)
	return "\n".join(lines)

static func fmt_heal_tooltip(p: Dictionary) -> String:
	var dice: int  = int(p.get("dice", "0"))
	var sides: int = int(p.get("sides", "0"))
	var con: int   = int(p.get("con", "0"))
	var total: int = int(p.get("total", "0"))
	var lines: PackedStringArray = []
	var uncapped: int = 0
	if dice > 0 and sides > 0:
		var roll: int = int(p.get("roll", "0"))
		lines.append("%dd%d = [color=lime]%d[/color]" % [dice, sides, roll])
		uncapped += roll
	if con != 0:
		lines.append("[color=lightblue]%+d[/color]  (CON mod)" % con)
		uncapped += con
	# Generic bonus-heal sources (Bruiser R1, ...) — see CombatMath.encode_bonus_sources()/
	# decode_bonus_sources(). A future bonus-heal source only needs to be added at the call site.
	for src: Dictionary in CombatMath.decode_bonus_sources(p.get("bonus", "")):
		lines.append("[color=%s]+%d[/color]  (%s)" % [src["color"], src["amount"], src["name"]])
		uncapped += src["amount"]
	lines.append("─────────────────")
	uncapped = maxi(1, uncapped)
	if total < uncapped:
		lines.append("= [color=gray]+%d HP[/color]  →  [color=lime]+%d HP[/color] healed" % [uncapped, total])
	else:
		lines.append("= [color=lime]+%d HP[/color]" % total)
	return "\n".join(lines)

# Level-up max HP gain breakdown — see Stats.hp_per_level_breakdown()/GameState.gain_exp()'s
# "hplvl:" meta. avg is the fixed per-class hit-die average (not rolled); n is how many level
# thresholds this single gain_exp() call crossed (usually 1 — the per-component lines below are
# per-level and get scaled by n so a multi-level XP grant still adds up).
static func fmt_hplvl_tooltip(p: Dictionary) -> String:
	var die: int   = int(p.get("die", "0"))
	var avg: int   = int(p.get("avg", "0"))
	var con: int   = int(p.get("con", "0"))
	var dwarf: int = int(p.get("dwarf", "0"))
	var n: int     = maxi(1, int(p.get("n", "1")))
	var total: int = int(p.get("total", "0"))
	var lines: PackedStringArray = []
	var lvl_tag: String = " × %d levels" % n if n > 1 else ""
	lines.append("d%d avg = [color=yellow]%d[/color]%s" % [die, avg * n, lvl_tag])
	if con != 0:
		lines.append("[color=lightblue]%+d[/color]  (CON mod%s)" % [con * n, lvl_tag])
	if dwarf != 0:
		lines.append("[color=lightblue]+%d[/color]  (Dwarven Toughness%s)" % [dwarf * n, lvl_tag])
	lines.append("─────────────────")
	lines.append("= [color=yellow]+%d[/color] max HP" % total)
	return "\n".join(lines)

static func fmt_save_tooltip(p: Dictionary) -> String:
	var die: int   = int(p.get("die", "0"))
	var d1: int    = int(p.get("d1", str(die)))
	var d2: int    = int(p.get("d2", str(die)))
	var mod: int   = int(p.get("mod", "0"))
	var prof: int  = int(p.get("prof", "0"))
	var total: int = int(p.get("total", "0"))
	var dc: int    = int(p.get("dc", "0"))
	var stat: String = p.get("stat", "DEX")
	var passed: bool = p.get("pass", "0") == "1"
	var adv: bool  = p.get("adv", "0") == "1"
	var disadv: bool = p.get("disadv", "0") == "1"
	var lucky1: bool = p.get("lucky1", "0") == "1"
	var lucky2: bool = p.get("lucky2", "0") == "1"
	var lines: PackedStringArray = []
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]" % [d1, d2, die])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]" % [d1, d2, die])
	else:
		lines.append("d20 = [color=yellow]%d[/color]" % die)
	if lucky1:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d1)
	if lucky2:
		lines.append("[color=#2e8b3d]☘ Halfling Luck: [s]1[/s] → %d[/color]" % d2)
	if mod != 0:
		lines.append("[color=lightblue]%+d[/color]  (%s mod)" % [mod, stat])
	if prof != 0:
		var prof_label: String = p.get("prof_label", "Proficiency")
		lines.append("[color=lightblue]+%d[/color]  (%s, %s check)" % [prof, prof_label, stat])
	lines.append("─────────────────")
	var result: String = "[color=green]SUCCESS[/color]" if passed else "[color=red]FAIL[/color]"
	lines.append("= [color=yellow]%d[/color] vs DC %d  →  %s" % [total, dc, result])
	return "\n".join(lines)

static func fmt_ehit_tooltip(p: Dictionary) -> String:
	var die: int    = int(p.get("die", "0"))
	var d1: int     = int(p.get("d1", str(die)))
	var d2: int     = int(p.get("d2", str(die)))
	var bonus: int  = int(p.get("bonus", "0"))
	var total: int  = int(p.get("total", "0"))
	var ac: int     = int(p.get("ac", "0"))
	var crit: bool  = p.get("crit", "0") == "1"
	var adv: bool   = p.get("adv", "0") == "1"
	var disadv: bool = p.get("disadv", "0") == "1"
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if crit else ""
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	else:
		lines.append("d20 = [color=yellow]%d[/color]%s" % [die, die_suffix])
	if bonus != 0:
		lines.append("[color=lightblue]%+d[/color]  (attack bonus)" % bonus)
	lines.append("─────────────────")
	var vs: String
	if crit:
		vs = "[color=gold]CRITICAL HIT[/color]"
	elif total >= ac:
		vs = "[color=tomato]HIT[/color]"
	else:
		vs = "[color=gray]MISS[/color]"
	lines.append("= [color=yellow]%d[/color] vs AC %d  →  %s" % [total, ac, vs])
	return "\n".join(lines)

static func fmt_edmg_tooltip(p: Dictionary) -> String:
	var roll: int  = int(p.get("roll", "0"))
	var dmin: int  = int(p.get("min", "0"))
	var dmax: int  = int(p.get("max", "0"))
	var crit: bool = p.get("crit", "0") == "1"
	var rage: bool = p.get("rage", "0") == "1"
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	if dmax > 0:
		lines.append("%d–%d = [color=yellow]%d[/color]" % [dmin, dmax, roll])
	else:
		lines.append("damage = [color=yellow]%d[/color]" % roll)
	if crit:
		lines.append("[color=gold]× 2[/color]  (Critical Hit!)")
	if rage:
		lines.append("[color=lightgreen]÷ 2[/color]  (Rage)")
	lines.append("─────────────────")
	lines.append("= [color=yellow]%d[/color] dmg" % final_dmg)
	return "\n".join(lines)

static func fmt_catk_tooltip(p: Dictionary) -> String:
	var die: int   = int(p.get("die", "0"))
	var prof: int  = int(p.get("prof", "0"))
	var roll: int  = int(p.get("roll", "0"))
	var ac: int    = int(p.get("ac", "0"))
	var dmg: int   = int(p.get("dmg", "0"))
	var crit: bool = p.get("crit", "0") == "1"
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if crit else ""
	lines.append("d20 = [color=yellow]%d[/color]%s" % [die, die_suffix])
	if prof != 0:
		lines.append("[color=lightblue]%+d[/color]  (proficiency)" % prof)
	lines.append("─────────────────")
	var vs: String
	if crit or roll >= ac:
		vs = "[color=tomato]HIT[/color]"
	else:
		vs = "[color=gray]MISS[/color]"
	lines.append("= [color=yellow]%d[/color] vs AC %d  →  %s" % [roll, ac, vs])
	if dmg > 0:
		lines.append("damage = [color=yellow]%d[/color]%s" % [dmg, "  ×2 (crit)" if crit else ""])
	return "\n".join(lines)

static func fmt_ret_tooltip(p: Dictionary) -> String:
	var rank: int      = int(p.get("rank", "0"))
	var wpn_roll: int  = int(p.get("wpn_roll", "0"))
	var wpn_bonus: int = int(p.get("wpn_bonus", "0"))
	var rage: int      = int(p.get("rage", "0"))
	var str_mod: int   = int(p.get("str", "0"))
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	lines.append("[color=orange]Retaliation[/color]  (Rank %d)" % rank)
	match rank:
		1:
			lines.append("[color=red]+%d[/color]  (Rage bonus)" % rage)
		2:
			lines.append("weapon roll = [color=yellow]%d[/color]" % wpn_roll)
			if wpn_bonus != 0:
				lines.append("[color=lightblue]%+d[/color]  (weapon bonus)" % wpn_bonus)
		3:
			lines.append("weapon roll = [color=yellow]%d[/color]" % wpn_roll)
			if wpn_bonus != 0:
				lines.append("[color=lightblue]%+d[/color]  (weapon bonus)" % wpn_bonus)
			if rage != 0:
				lines.append("[color=red]+%d[/color]  (Rage bonus)" % rage)
			if str_mod != 0:
				lines.append("[color=lightblue]%+d[/color]  (STR mod)" % str_mod)
	lines.append("─────────────────")
	lines.append("= [color=yellow]%d[/color] dmg" % final_dmg)
	return "\n".join(lines)
