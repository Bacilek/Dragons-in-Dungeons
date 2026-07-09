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
	var stat_name: String = "DEX" if use_dex else "STR"
	var lines: PackedStringArray = []
	var die_suffix: String = "  [color=gold]★ CRIT[/color]" if n20 else ("  [color=red]✕ FAIL[/color]" if n1 else "")
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]%s" % [d1, d2, die, die_suffix])
	else:
		lines.append("d20 = [color=yellow]%d[/color]%s" % [die, die_suffix])
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
	if crit:
		lines.append("[color=gold]× 2[/color]  (Critical Hit!)")
	# Generic bonus-damage sources (Rage, Frenzy, Ironwood Bark, Divine Fury, ...) — see
	# CombatMath.encode_bonus_sources()/decode_bonus_sources() in scripts/entities/combat_math.gd.
	# A future damage source only needs to be added to the encode call site, never here.
	for src: Dictionary in CombatMath.decode_bonus_sources(p.get("bonus", "")):
		lines.append("[color=%s]+%d[/color]  (%s)" % [src["color"], src["amount"], src["name"]])
	lines.append("─────────────────")
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

static func fmt_heal_tooltip(p: Dictionary) -> String:
	var dice: int  = int(p.get("dice", "0"))
	var sides: int = int(p.get("sides", "0"))
	var con: int   = int(p.get("con", "0"))
	var total: int = int(p.get("total", "0"))
	var lines: PackedStringArray = []
	if dice > 0 and sides > 0:
		var roll: int = int(p.get("roll", "0"))
		lines.append("%dd%d = [color=lime]%d[/color]" % [dice, sides, roll])
		if con != 0:
			lines.append("[color=lightblue]%+d[/color]  (CON mod)" % con)
		lines.append("─────────────────")
		var uncapped: int = maxi(1, roll + con)
		if total < uncapped:
			lines.append("= [color=gray]+%d HP[/color]  →  [color=lime]+%d HP[/color] healed" % [uncapped, total])
		else:
			lines.append("= [color=lime]+%d HP[/color]" % total)
	else:
		if con != 0:
			lines.append("[color=lightblue]%+d[/color]  (CON mod)" % con)
			lines.append("─────────────────")
		lines.append("= [color=lime]+%d HP[/color]" % total)
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
	var lines: PackedStringArray = []
	if adv and d1 != d2:
		lines.append("d20 (adv):  %d, %d  → [color=yellow]%d[/color]" % [d1, d2, die])
	elif disadv and d1 != d2:
		lines.append("d20 (disadv):  %d, %d  → [color=yellow]%d[/color]" % [d1, d2, die])
	else:
		lines.append("d20 = [color=yellow]%d[/color]" % die)
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
	var final_dmg: int = int(p.get("final", "0"))
	var lines: PackedStringArray = []
	if dmax > 0:
		lines.append("%d–%d = [color=yellow]%d[/color]" % [dmin, dmax, roll])
	else:
		lines.append("damage = [color=yellow]%d[/color]" % roll)
	if crit:
		lines.append("[color=gold]× 2[/color]  (Critical Hit!)")
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
