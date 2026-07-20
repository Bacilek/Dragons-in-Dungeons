class_name PlayerBerserker
extends Node

# Berserker Tier 2: Frenzy activation ability + Sadist Monster / Masochist Monster / Frenzied
# Killer talents. Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
# Spec: markdowns/berserker.md.

var player: Player

# Click-to-target arming, mirrors Grip of the Forest's _hook_mode_active pattern (World Tree).
var frenzy_mode_active: bool = false

func activate_frenzy() -> void:
	if not GameState.is_raging:
		GameState.game_log("[color=gray]Frenzy requires Raging.[/color]")
		return
	if GameState.berserker_frenzy_used:
		GameState.game_log("[color=gray]Frenzy: already used (resets on short/long rest).[/color]")
		return
	frenzy_mode_active = true
	GameState.game_log("[color=red]Frenzy — move into or click an adjacent enemy. [Esc] to cancel.[/color]")

func execute_frenzy(enemy: Enemy) -> void:
	if not GameState.invincible:
		GameState.berserker_frenzy_used = true
	GameState.berserker_turns_since_frenzy = 0
	GameState.stealth_check_skip = true
	TurnManager.begin_player_action()
	# Frenzy is an attack — it must refresh Rage's duration just like a normal attack does,
	# regardless of hit/miss (see player.gd._on_turn_started()'s rage tick).
	player._rage_attacked_this_turn = true

	var stats: Stats = player.stats
	var melee: Item = GameState.equipped_weapon
	var is_unarmed: bool = melee == null
	var is_str_weapon: bool = not is_unarmed and not melee.is_ranged
	var str_mod: int = stats.str_modifier()
	var dex_mod: int = stats.dex_modifier()
	var is_finesse_weapon: bool = not is_unarmed and melee.is_finesse
	var dmg_mod: int = CombatMath.finesse_modifier(str_mod, dex_mod, is_finesse_weapon)
	var prof: int = CombatMath.weapon_prof_bonus(melee, stats.proficiency_bonus, stats.proficient_simple_weapons, stats.proficient_martial_weapons)
	var w_dmin: int = stats.base_min_damage
	var w_dmax: int = stats.base_max_damage
	var w_enh: int = 0
	if melee != null:
		w_enh = melee.bonus_damage
		if melee.damage_die_min > 0:
			w_dmin = melee.damage_die_min
			w_dmax = melee.damage_die_max
	var dmg_type: String = melee.damage_type if melee != null and not melee.damage_type.is_empty() else "Bludgeoning"
	var type_tag: String = " [color=gray]%s[/color]" % dmg_type
	var rage_bonus: int = stats.rage_bonus_damage
	var sadist_rank: int = GameState.get_talent_rank("sadist_monster")
	var sadist_bonus: int = 0
	if sadist_rank >= 1:
		for i: int in sadist_rank:
			sadist_bonus += Rng.roll(6)

	var die_roll: int = Rng.roll(20)
	var weapon_dice: int = Rng.range_i(w_dmin, w_dmax)
	# Shared base damage now mirrors a normal attack's formula exactly (dice + weapon
	# enhancement + Rage bonus + STR/finesse mod) instead of the old flat "weapon dice + STR
	# + Rage" shortcut — see scripts/entities/CLAUDE.md's "Frenzy" bullet.
	var base_dmg: int = weapon_dice + w_enh + rage_bonus + dmg_mod
	var bonus_sources_self: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
	])
	var bonus_sources_enemy: String = CombatMath.encode_bonus_sources([
		{"name": "Rage bonus", "amount": rage_bonus, "color": "red"},
		{"name": "Sadist Monster", "amount": sadist_bonus, "color": "red"},
	])

	# The attack roll (d20 outcome: miss/hit/crit) and the damage roll are two separate numbers
	# with their own hover tooltips — "frzhit" explains what the d20 result means, the damage
	# numbers now reuse the standard "dmg:" tooltip format (same as a normal attack) since the
	# damage calculation mirrors _bump_attack()'s formula exactly. Weapon masteries the wielded
	# weapon carries (Cleave/Vex/Graze/Topple/Nick) fire the same as they would off a normal
	# attack — see scripts/entities/CLAUDE.md's "Frenzy" bullet.
	if die_roll == 1:
		var attack_meta: String = "frzhit:die=%d,outcome=miss" % die_roll
		# Self-damage routes through the single damage-intake chokepoint so Rage's 50% physical
		# DR (and any other take_damage_raw hook) applies exactly like it would to enemy damage.
		var self_dmg: int = GameState.take_damage_raw(base_dmg, false, dmg_type)
		var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,str=%d,bonus=%s,crit=0,final=%d" % [
			weapon_dice, w_dmin, w_dmax, w_enh, dmg_mod, bonus_sources_self, self_dmg]
		GameState.game_log("[color=red][url=%s]Frenzy misses![/url] You tear into yourself for [url=%s][color=orange]%d[/color][/url]%s damage.[/color]" % [attack_meta, dmg_meta, self_dmg, type_tag])
		_note_self_damage()
		GameState.check_player_death()
		player._try_graze(enemy, is_str_weapon, dmg_mod)
		player._try_cleave(enemy, is_str_weapon)
		player._try_offhand_attack(enemy, is_str_weapon)
	elif die_roll == 20:
		var attack_meta: String = "frzhit:die=%d,outcome=crit" % die_roll
		var total: int = base_dmg * 2 + sadist_bonus * 2
		var actual: int = enemy.stats.take_damage(total)
		enemy.update_hp_bar()
		if player._dungeon_floor != null:
			player._dungeon_floor.show_damage(enemy.position, actual, true)
		var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,str=%d,bonus=%s,crit=1,final=%d" % [
			weapon_dice, w_dmin, w_dmax, w_enh, dmg_mod, bonus_sources_enemy, actual]
		var is_lethal: bool = enemy.stats.is_dead()
		GameState.game_log("[color=gold][url=%s]FRENZY CRIT![/url] %s takes [url=%s][color=yellow]%d[/color][/url]%s damage — you feel nothing.%s[/color]" % [attack_meta, enemy.display_name, dmg_meta, actual, type_tag, CombatMath.death_suffix(is_lethal)])
		_refresh_frenzy_on("crit")
		if melee != null and melee.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
			player._vex_adv_target = enemy
		if not is_lethal:
			player._try_topple(enemy, is_str_weapon, prof, str_mod)
		if is_lethal:
			player._finish_kill(enemy)
			_refresh_frenzy_on("kill")
		player._try_cleave(enemy, is_str_weapon)
		player._try_offhand_attack(enemy, is_str_weapon)
	else:
		var attack_meta: String = "frzhit:die=%d,outcome=hit" % die_roll
		var self_dmg2: int = GameState.take_damage_raw(base_dmg, false, dmg_type)
		var total2: int = base_dmg + sadist_bonus
		var actual2: int = enemy.stats.take_damage(total2)
		enemy.update_hp_bar()
		if player._dungeon_floor != null:
			player._dungeon_floor.show_damage(enemy.position, actual2, false)
		var dmg_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,str=%d,bonus=%s,crit=0,final=%d" % [
			weapon_dice, w_dmin, w_dmax, w_enh, dmg_mod, bonus_sources_enemy, actual2]
		var self_meta: String = "dmg:roll=%d,dmin=%d,dmax=%d,wpn=%d,str=%d,bonus=%s,crit=0,final=%d" % [
			weapon_dice, w_dmin, w_dmax, w_enh, dmg_mod, bonus_sources_self, self_dmg2]
		var is_lethal: bool = enemy.stats.is_dead()
		GameState.game_log("[color=red][url=%s]Frenzy![/url] %s takes [url=%s][color=orange]%d[/color][/url]%s damage — you take [url=%s][color=orange]%d[/color][/url]%s back.%s[/color]" % [attack_meta, enemy.display_name, dmg_meta, actual2, type_tag, self_meta, self_dmg2, type_tag, CombatMath.death_suffix(is_lethal)])
		_note_self_damage()
		GameState.check_player_death()
		if melee != null and melee.weapon_mastery == "Vex" and stats.knows_mastery("Vex"):
			player._vex_adv_target = enemy
		if not is_lethal:
			player._try_topple(enemy, is_str_weapon, prof, str_mod)
		if is_lethal:
			player._finish_kill(enemy)
			_refresh_frenzy_on("kill")
		player._try_cleave(enemy, is_str_weapon)
		player._try_offhand_attack(enemy, is_str_weapon)

	if player._dungeon_floor != null:
		player._dungeon_floor.update_fog(player.grid_pos)
	# Frenzy is a free action — doesn't cost the turn (per spec).
	player._reverted_this_round = true
	TurnManager.revert_to_waiting()

# Frenzied Killer R2: refreshes on ANY critical hit the player lands this turn — normal attack,
# cleave, ranged, thrown, or Frenzy's own crit — not scoped to Frenzy's own crit like R1's kill
# trigger is. Hooked alongside PlayerBaseTalents.on_crit() at every player attack-roll site
# (Frenzy's own nat-20 branch calls _refresh_frenzy_on("crit") directly instead, since it isn't
# one of those shared sites).
func refresh_on_any_crit() -> void:
	_refresh_frenzy_on("crit")

func _refresh_frenzy_on(trigger: String) -> void:
	var rank: int = GameState.get_talent_rank("frenzied_killer")
	var refreshes: bool = (rank >= 1 and trigger == "kill") or (rank >= 2 and trigger == "crit")
	if refreshes and GameState.berserker_frenzy_used:
		GameState.berserker_frenzy_used = false
		GameState.berserker_turns_since_frenzy = 0
		GameState.game_log("[color=lime]Frenzied Killer: Frenzy's use refreshes![/color]")

# Frenzied Killer R3: every 3 turns since last use, refresh automatically. Called from
# player.gd._on_turn_started() on real turns only.
func tick_frenzied_killer() -> void:
	if GameState.get_talent_rank("frenzied_killer") < 3 or not GameState.berserker_frenzy_used:
		return
	GameState.berserker_turns_since_frenzy += 1
	if GameState.berserker_turns_since_frenzy >= 3:
		GameState.berserker_frenzy_used = false
		GameState.berserker_turns_since_frenzy = 0
		GameState.game_log("[color=lime]Frenzied Killer: Frenzy's use refreshes![/color]")

# Masochist Monster R1/R2: called whenever the player takes damage on their own turn (Frenzy
# self-damage counts — intentional synergy per spec). R1 grants +1 AC until next turn start;
# R2 also grants (Rage bonus damage) separate d4 rolls, summed, as temp HP.
func _note_self_damage() -> void:
	var rank: int = GameState.get_talent_rank("masochist_monster")
	if rank < 1:
		return
	if GameState.masochist_ac_bonus == 0:
		GameState.masochist_ac_bonus = 1
		GameState.recalculate_stats()
	if rank >= 2:
		# Rolls one d4 PER point of Rage bonus damage (2/3/4 separate dice by level), summed —
		# not a single d4 multiplied by the rage bonus.
		var rage_bonus: int = GameState.player_stats.rage_bonus_damage
		var roll_strs: PackedStringArray = []
		var thp: int = 0
		for _i: int in rage_bonus:
			var die: int = Rng.roll(4)
			roll_strs.append(str(die))
			thp += die
		GameState.player_stats.temp_hp = thp
		GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
		var rolls_str: String = "|".join(roll_strs)
		var meta: String = "msn:rage=%d,rolls=%s,final=%d" % [rage_bonus, rolls_str, thp]
		GameState.game_log("[color=cyan][url=%s]Masochist Monster: %d temp HP.[/url][/color]" % [meta, thp])

# Called externally (enemy hit resolution) so Masochist Monster also triggers on ordinary damage
# taken during the player's own turn (e.g. Retaliation is gone, but reactive/terrain damage still
# counts) — kept as a small public wrapper so non-Frenzy damage sources can opt in later.
func note_damage_taken_on_turn() -> void:
	_note_self_damage()

func clear_turn_start_ac_bonus() -> void:
	if GameState.masochist_ac_bonus != 0:
		GameState.masochist_ac_bonus = 0
		GameState.recalculate_stats()
