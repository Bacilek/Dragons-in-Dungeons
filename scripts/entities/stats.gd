class_name Stats
extends Resource

enum CharacterClass { BARBARIAN, RANGER, WIZARD, MONK }
enum CharacterRace { ORC, HUMAN, HALFLING, DWARF, ELF, DRAGONBORN }
enum ElfSubrace { DROW, HIGH_ELF, WOOD_ELF }          # only meaningful when character_race == ELF
enum DragonbornAncestry { BLACK, BLUE, BRASS, BRONZE, COPPER, GOLD, GREEN, RED, SILVER, WHITE }

const DRAGONBORN_DAMAGE_TYPE: Array[String] = [
	"Acid", "Lightning", "Fire", "Fire", "Acid", "Fire", "Poison", "Fire", "Lightning", "Cold"
]

# Check proficiency flags — which ability checks the class rolls with proficiency bonus.
# Barbarian: STR + CON. Ranger: STR + DEX. Wizard: INT + WIS. Monk: STR + DEX.
# Monk also has proficiency with simple weapons + martial weapons with light property (TODO: enforce).
var check_prof_str: bool = false
var check_prof_con: bool = false
var check_prof_dex: bool = false
var check_prof_int: bool = false
var check_prof_wis: bool = false
var check_prof_cha: bool = false

# Weapon proficiency — whether the class adds proficiency_bonus to attack rolls with
# Simple/Martial weapons (Item.weapon_category). Lacking proficiency still lets the
# character use the weapon; it just skips the proficiency bonus on the attack roll.
var proficient_simple_weapons: bool = false
var proficient_martial_weapons: bool = false

# Shield proficiency — whether the class may equip a Shield (Item.is_shield) at all. Lacking it
# blocks equipping outright (unlike weapon proficiency, which just drops a bonus) — see
# GameState.can_equip_shield(). Barbarian/Ranger only; Wizard/Monk never train with shields
# (Monk also loses Unarmored Defense in any armor — see the class's "No armor training" note).
var proficient_shields: bool = false

# Armor proficiency — whether the class may equip a given weight class of body armor
# (Item.armor_category) at all. Lacking it blocks equipping outright, same as proficient_shields
# above — see GameState.can_equip_armor(). Barbarian/Ranger: Light + Medium (5e RAW — neither
# trains with Heavy armor). Wizard/Monk: none (Monk's Unarmored Defense is strictly better anyway).
var proficient_light_armor: bool = false
var proficient_medium_armor: bool = false
var proficient_heavy_armor: bool = false

# Weapon mastery ownership — a weapon's Item.weapon_mastery (e.g. "Cleave", "Vex") only
# triggers its effect if the character actually knows that mastery. Populated by the Mastery
# Picker (scripts/ui/mastery_picker.gd, via GameState.toggle_mastery()) — see mastery_cap()
# below for the per-class/level selection limit.
var known_weapon_masteries: Array[String] = []

func knows_mastery(mastery_name: String) -> bool:
	return mastery_name in known_weapon_masteries

# Canonical mastery vocabulary shown by the Mastery Picker (scripts/ui/mastery_picker.gd) —
# see docs/architecture/weapon-mastery-selection-design.md. Alphabetical, stable render order.
const ALL_WEAPON_MASTERIES: Array[String] = [
	"Cleave", "Graze", "Nick", "Push", "Sap", "Slow", "Topple", "Vex"
]

# How many masteries this character may know at once. Computed live (never cached) so a
# level-up silently raises the cap with no stale value — see design doc decision #4.
func mastery_cap() -> int:
	match character_class:
		CharacterClass.BARBARIAN:
			if character_level >= 10: return 4
			if character_level >= 4:  return 3
			return 2
		CharacterClass.RANGER:
			return 2
		_:
			return 0   # WIZARD, MONK

@export var strength: int = 10
@export var dexterity: int = 10
@export var constitution: int = 10
@export var intelligence: int = 10
@export var wisdom: int = 10
@export var charisma: int = 10

@export var character_class: CharacterClass = CharacterClass.BARBARIAN
@export var character_level: int = 1

@export var character_race: CharacterRace = CharacterRace.HUMAN
@export var race_variant: int = 0        # ElfSubrace or DragonbornAncestry ordinal; unused otherwise
@export var race_prof_ability: int = -1  # Human only: which of STR..CHA got proficiency; -1 = unset

# Always re-derived by apply_race_defaults() — never saved directly (mirrors check_prof_* above).
var darkvision_bonus: int = 0            # 0 = none, 1 = standard (+1 FOV tile), 2 = superior (+2)
var damage_resistances: Array[String] = []

# Per-long-rest race charge trackers — reset in GameState.long_rest(), same chokepoint as
# rage_uses_remaining/hit_dice.
var relentless_endurance_used: bool = false     # Orc
var heroic_inspiration_available: bool = false  # Human

@export var max_hp: int = 10
@export var current_hp: int = 10
@export var armor_class: int = 10

# Proficiency bonus scales per D&D 5e: +2 at levels 1–4, +3 at 5–8, +4 at 9–12, etc.
var proficiency_bonus: int:
	get: return 2 + (character_level - 1) / 4

@export var base_min_damage: int = 1
@export var base_max_damage: int = 4
@export var min_damage: int = 1
@export var max_damage: int = 4
@export var armor: int = 0

@export var experience: int = 0

# Rage uses (Barbarian only). rage_uses_max scales by level; reset to max on floor descent.
var rage_uses_remaining: int = 0
var rage_uses_max: int:
	get:
		if character_class != CharacterClass.BARBARIAN: return 0
		if character_level >= 17: return 5
		if character_level >= 12: return 5
		if character_level >= 6:  return 4
		if character_level >= 4:  return 3
		return 2

# Rage bonus damage scales with Barbarian level (+2 / +3 / +4).
var rage_bonus_damage: int:
	get:
		if character_class != CharacterClass.BARBARIAN: return 0
		if character_level >= 16: return 4
		if character_level >= 9:  return 3
		return 2

# Hunter's Mark uses (Ranger only) — baseline level-1 ability, not talent-gated, same
# "granted directly, resource-limited" shape as Rage. A use is spent only when establishing a
# mark on a target from having none (retargeting an already-active mark is free — 5e "move
# Hunter's Mark for free"); refilled to max in GameState.long_rest(). Flat, doesn't scale by
# level (unlike Rage) — simple to start, tune later.
var hunters_mark_uses_remaining: int = 0
const HUNTERS_MARK_USES_MAX: int = 3

# The currently marked enemy (Hunter's Mark). Deliberately NOT serialized in to_dict()/from_dict()
# — a live Enemy node reference can't survive save/load, same precedent as witch_bolt_target
# above: the mark simply ends silently on load, no cleanup needed.
var hunters_mark_target: Enemy = null
# Set true the moment a mark is (re)established, cleared on the marked target's first taken hit —
# drives Bloodhound R1's "first attack against a fresh mark gets Advantage".
var hunters_mark_fresh: bool = false

var poison_turns: int = 0
var burning_turns: int = 0
var bleeding_turns: int = 0
var slowed_turns: int = 0
var temp_hp: int = 0  # Natural Sleeper R2 — consumed before regular HP damage
var zealous_presence_turns: int = 0  # Zealot Zealous Presence — Advantage on attacks/checks while > 0

# Blade Ward cantrip — see scripts/entities/CLAUDE.md's "Wizard spellcasting (cantrips)" section.
# `concentration_spell_id`: generic single-slot concentration tracker ("" = not concentrating).
# Only Blade Ward uses it today, but the field/mechanism is spell-agnostic — a future concentration
# spell reuses it, breaking whatever the caster was already concentrating on (5e: only one
# concentration effect at a time).
var concentration_spell_id: String = ""
# Blade Ward's own duration — ticks down once per real player turn (player.gd _on_turn_started(),
# same "if not came_from_revert" block as shield_ac_bonus); reaching 0 ends the effect and clears
# concentration_spell_id. Also cleared early if a CON concentration-check fails on taking damage
# (GameState.take_damage_raw()) or another concentration spell is cast.
var blade_ward_turns: int = 0

# Witch Bolt — same generic concentration_spell_id mechanism as Blade Ward ("witch_bolt"), but
# also needs a live target reference since its ongoing effect is a per-turn damage tick against a
# specific enemy, not a self-buff. `witch_bolt_target` is deliberately NOT serialized in
# to_dict()/from_dict() — a live Enemy node reference can't survive a save/load anyway (mid-floor
# entities aren't Phase-A save-safe — see scripts/autoloads/CLAUDE.md), so the bolt simply ends
# silently on load like other mid-floor state.
var witch_bolt_target: Enemy = null
var witch_bolt_turns: int = 0
# Set on cast, consumed (cleared) the first time TurnManager.player_turn_ending fires afterward —
# skips the jolt tick for the casting turn itself, so the first automatic 1d12 lands at the end of
# the turn AFTER the one Witch Bolt was cast on, not the same turn.
var witch_bolt_just_cast: bool = false

# Expeditious Retreat — same generic concentration_spell_id mechanism as Blade Ward
# ("expeditious_retreat"). No live reference of its own (the effect is read directly off this
# counter at the top of Player._try_move() — see scripts/entities/CLAUDE.md); deliberately NOT
# serialized, same simplification as witch_bolt_turns above (mid-floor concentration state, ends
# silently on save/load).
var expeditious_retreat_turns: int = 0

# Fog Cloud — same generic concentration_spell_id mechanism ("fog_cloud"). The cloud's actual
# position/radius live on GameState (fog_cloud_pos/fog_cloud_radius), not here, since both the
# player's AND every enemy's attack rolls need to query it, not just this caster's own turn tick.
# Deliberately NOT serialized, same as witch_bolt_turns above.
var fog_cloud_turns: int = 0

# Invisibility (level-2 spell, touch/self) — NOT a concentration effect (5e RAW: it ends on
# attacking or casting a spell, not on taking damage, so it doesn't use concentration_spell_id at
# all). Ticked in player.gd's per-real-turn block; ended early via Player._resolve_stealth_check()
# reading GameState.stealth_check_skip (the same "this turn was an attack/spell-cast" flag the
# Stealth-vs-Passive-Perception system already sets at every attack/cast call site — see
# scripts/entities/CLAUDE.md's "Invisibility" section). Deliberately NOT serialized, same
# mid-floor-only simplification as witch_bolt_turns/fog_cloud_turns above.
var invisibility_turns: int = 0
# Set true on cast, consumed (cleared) the first time _resolve_stealth_check() runs afterward —
# skips ending Invisibility on its OWN casting turn (cast_leveled_self() sets stealth_check_skip
# unconditionally, same as every other spell), same "just_cast" pattern as witch_bolt_just_cast.
var invisibility_just_cast: bool = false

# Wizard spellcasting (cantrips per docs/architecture/spellcasting-design.md, leveled spells +
# slots per docs/architecture/leveled-spells-and-slots-plan.md). Built in
# apply_class_defaults()'s WIZARD branch; null for every other class. See
# scripts/items/spellcaster_state.gd.
var caster: SpellcasterState = null

# Shield spell's +5 AC — leveled-spells-and-slots-plan.md §7: shipped as a same-turn buff, not
# the framework doc's general ActiveSpellEffect registry (out of scope for this pass). Decremented
# to 0 at the start of the caster's next turn (player.gd _on_turn_started()).
var shield_ac_bonus: int = 0

# Mage Armor — sets AC to 13 + DEX while unarmored, overriding the flat 10 + DEX baseline
# (never overrides a class's own unarmored-defense formula — Barbarian/Monk). Ends when Armor is
# equipped (GameState.equip()) or at the next long rest (GameState.long_rest()) — see recalc_ac().
var mage_armor_active: bool = false


# Monk: Martial Arts die scales with level. Global default 1d4 is used by all other classes.
var martial_arts_die_sides: int:
	get:
		if character_class == CharacterClass.MONK:
			if character_level >= 17: return 12
			if character_level >= 11: return 10
			if character_level >= 5:  return 8
			return 6
		return 4  # global default: 1d4 for unarmed

func exp_for_level(lv: int) -> int:
	return lv * 10

func exp_to_next() -> int:
	return exp_for_level(character_level)

func gain_exp(amount: int) -> bool:
	experience += amount
	var leveled := false
	while experience >= exp_for_level(character_level):
		experience -= exp_for_level(character_level)
		character_level += 1
		var hp_gain: int = _hp_per_level()
		max_hp += hp_gain
		current_hp = mini(current_hp + hp_gain, max_hp)
		leveled = true
	return leveled

# Per-level HP gain, broken out into its components for the level-up chat tooltip
# (GameState.gain_exp()'s "hplvl:" meta / TooltipFormatters.fmt_hplvl_tooltip()) — same
# "never log a bare number" convention the combat damage/heal tooltips follow.
# {die_sides, avg, con, dwarf, total} — avg is the fixed per-class hit-die average (not rolled).
func hp_per_level_breakdown() -> Dictionary:
	var die_sides: int = point_buy_hit_die_base()
	var avg: int
	match character_class:
		CharacterClass.BARBARIAN: avg = 7
		CharacterClass.RANGER:    avg = 6
		CharacterClass.WIZARD:    avg = 4
		CharacterClass.MONK:      avg = 5  # d8 avg = 5
		_:                        avg = 5
	var con: int = con_modifier()
	var dwarf: int = 1 if character_race == CharacterRace.DWARF else 0
	return {"die_sides": die_sides, "avg": avg, "con": con, "dwarf": dwarf, "total": avg + con + dwarf}

func _hp_per_level() -> int:
	return hp_per_level_breakdown()["total"]

func modifier(score: int) -> int:
	return floori((score - 10) / 2.0)

func str_modifier() -> int: return modifier(strength)
func dex_modifier() -> int: return modifier(dexterity)
func con_modifier() -> int: return modifier(constitution)
func int_modifier() -> int: return modifier(intelligence)
func wis_modifier() -> int: return modifier(wisdom)
func cha_modifier() -> int: return modifier(charisma)

func ability_check(score: int, proficient: bool, dc: int) -> bool:
	var roll: int = Rng.roll(20)
	var bonus: int = modifier(score) + (proficiency_bonus if proficient else 0)
	return (roll + bonus) >= dc

func roll_damage() -> int:
	return Rng.range_i(min_damage, max_damage)

func take_damage(amount: int) -> int:
	var clamped: int = maxi(1, amount)
	# Temp HP (from Natural Sleeper R2) absorbs damage first
	if temp_hp > 0:
		var absorbed: int = mini(temp_hp, clamped)
		temp_hp -= absorbed
		clamped -= absorbed
		if clamped <= 0:
			return 0  # fully absorbed
	current_hp -= clamped
	return clamped

func is_dead() -> bool:
	return current_hp <= 0

# Shared "Bloodied" mechanic (Scarred Warrior and any future consumer) — see markdowns/scarred_warrior.md.
# Below 50% max HP (integer division, round down), recomputed live from current/max HP.
func is_bloodied() -> bool:
	return current_hp < max_hp / 2

func tick_status() -> int:
	var dmg: int = 0
	if poison_turns > 0:
		dmg += 1 + poison_turns / 3
		poison_turns -= 1
	if burning_turns > 0:
		dmg += character_level
		burning_turns -= 1
	if bleeding_turns > 0:
		dmg += 1
		bleeding_turns -= 1
	if slowed_turns > 0:
		slowed_turns -= 1
	return dmg

# Recalculates armor_class based on what is equipped.
# Called externally by GameState.recalculate_stats().
# Barbarian unarmored defense: AC = 10 + DEX + CON when no armor.
# Monk unarmored defense:     AC = 10 + DEX + WIS when no armor.
# `armor_item`: the equipped body-armor Item (Type.ARMOR, not a Shield), or null if unarmored —
# real body armor (armor_item.base_ac > 0) always wins over every unarmored-defense formula below
# (5e RAW: unarmored defense only applies while wearing no armor at all).
func recalc_ac(has_armor_equipped: bool, armor_item: Item = null) -> void:
	if armor_item != null and armor_item.base_ac > 0:
		var dex_bonus: int
		if armor_item.dex_cap == 0:
			dex_bonus = 0  # Heavy: no DEX bonus at all, not even a negative one
		elif armor_item.dex_cap > 0:
			dex_bonus = mini(dex_modifier(), armor_item.dex_cap)  # Medium: capped from above only
		else:
			dex_bonus = dex_modifier()  # Light: unlimited
		armor_class = armor_item.base_ac + dex_bonus
	elif character_class == CharacterClass.BARBARIAN and not has_armor_equipped:
		armor_class = 10 + dex_modifier() + con_modifier()
	elif character_class == CharacterClass.MONK and not has_armor_equipped:
		armor_class = 10 + dex_modifier() + wis_modifier()
	elif mage_armor_active and not has_armor_equipped:
		armor_class = 13 + dex_modifier()
	else:
		armor_class = 10 + dex_modifier()
	armor_class += shield_ac_bonus

# ── Save/load (Phase A — docs/architecture/SAVE_LOAD_ARCHITECTURE.md §4.1) ──────
# Persist mutable state only. Computed properties (proficiency_bonus, rage_uses_max,
# martial_arts_die_sides) and class-set flags (check_prof_*, weapon proficiency) are
# never saved — from_dict() re-derives them via apply_class_defaults().

func to_dict() -> Dictionary:
	return {
		"strength": strength,
		"dexterity": dexterity,
		"constitution": constitution,
		"intelligence": intelligence,
		"wisdom": wisdom,
		"charisma": charisma,
		"character_class": int(character_class),
		"character_level": character_level,
		"character_race": int(character_race),
		"race_variant": race_variant,
		"race_prof_ability": race_prof_ability,
		"relentless_endurance_used": relentless_endurance_used,
		"heroic_inspiration_available": heroic_inspiration_available,
		"experience": experience,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"base_min_damage": base_min_damage,
		"base_max_damage": base_max_damage,
		"rage_uses_remaining": rage_uses_remaining,
		"hunters_mark_uses_remaining": hunters_mark_uses_remaining,
		"temp_hp": temp_hp,
		"poison_turns": poison_turns,
		"burning_turns": burning_turns,
		"bleeding_turns": bleeding_turns,
		"slowed_turns": slowed_turns,
		"zealous_presence_turns": zealous_presence_turns,
		"mage_armor_active": mage_armor_active,
		"concentration_spell_id": concentration_spell_id,
		"blade_ward_turns": blade_ward_turns,
		"known_weapon_masteries": known_weapon_masteries.duplicate(),
		"caster_known_spells": caster.known_spells.duplicate() if caster != null else [],
		"caster_prepared_spells": caster.prepared_spells.duplicate() if caster != null else [],
		"caster_slot_remaining": caster.slot_pool.remaining.duplicate() if caster != null and caster.slot_pool != null else {},
	}

# Order matters (doc §4.1): apply_class_defaults() first (resets scores/HP/flags),
# THEN saved values overwrite. armor_class and min/max_damage are not restored here —
# GameState.recalculate_stats() recomputes both from equipment after the full load.
func from_dict(d: Dictionary) -> void:
	character_class = int(d.get("character_class", CharacterClass.BARBARIAN)) as CharacterClass
	apply_class_defaults()
	character_race = int(d.get("character_race", CharacterRace.HUMAN)) as CharacterRace
	race_variant = int(d.get("race_variant", 0))
	race_prof_ability = int(d.get("race_prof_ability", -1))
	apply_race_defaults()
	relentless_endurance_used = bool(d.get("relentless_endurance_used", false))
	heroic_inspiration_available = bool(d.get("heroic_inspiration_available", true))
	strength = int(d.get("strength", strength))
	dexterity = int(d.get("dexterity", dexterity))
	constitution = int(d.get("constitution", constitution))
	intelligence = int(d.get("intelligence", intelligence))
	wisdom = int(d.get("wisdom", wisdom))
	charisma = int(d.get("charisma", charisma))
	character_level = int(d.get("character_level", 1))
	experience = int(d.get("experience", 0))
	max_hp = int(d.get("max_hp", max_hp))
	current_hp = int(d.get("current_hp", max_hp))
	base_min_damage = int(d.get("base_min_damage", base_min_damage))
	base_max_damage = int(d.get("base_max_damage", base_max_damage))
	rage_uses_remaining = int(d.get("rage_uses_remaining", 0))
	hunters_mark_uses_remaining = int(d.get("hunters_mark_uses_remaining", 0))
	temp_hp = int(d.get("temp_hp", 0))
	poison_turns = int(d.get("poison_turns", 0))
	burning_turns = int(d.get("burning_turns", 0))
	bleeding_turns = int(d.get("bleeding_turns", 0))
	slowed_turns = int(d.get("slowed_turns", 0))
	zealous_presence_turns = int(d.get("zealous_presence_turns", 0))
	mage_armor_active = bool(d.get("mage_armor_active", false))
	concentration_spell_id = String(d.get("concentration_spell_id", ""))
	blade_ward_turns = int(d.get("blade_ward_turns", 0))
	known_weapon_masteries.clear()
	for m: Variant in (d.get("known_weapon_masteries", []) as Array):
		known_weapon_masteries.append(String(m))
	if caster != null:
		caster.known_spells.clear()
		for sid: Variant in (d.get("caster_known_spells", []) as Array):
			caster.known_spells.append(String(sid))
		caster.prepared_spells.clear()
		for sid2: Variant in (d.get("caster_prepared_spells", []) as Array):
			caster.prepared_spells.append(String(sid2))
		if caster.slot_pool != null:
			caster.slot_pool.remaining.clear()
			var saved_slots: Dictionary = d.get("caster_slot_remaining", {})
			for lv: Variant in saved_slots:
				caster.slot_pool.remaining[int(lv)] = int(saved_slots[lv])

# ── Point buy (custom character creation, scripts/ui/point_buy_select.gd) ──────
# D&D 2024 point-buy costs: 8-13 cost 1 point per step, 14 and 15 cost 2 points per step.
const POINT_BUY_COST: Dictionary = {8: 0, 9: 1, 10: 2, 11: 3, 12: 4, 13: 5, 14: 7, 15: 9}
const POINT_BUY_BUDGET: int = 27
const POINT_BUY_MIN: int = 8
const POINT_BUY_MAX: int = 15

func point_buy_hit_die_base() -> int:
	match character_class:
		CharacterClass.BARBARIAN: return 12
		CharacterClass.RANGER: return 10
		CharacterClass.WIZARD: return 6
		CharacterClass.MONK: return 8
	return 8

# Overrides the six base ability scores with a player-allocated point-buy result, then
# re-derives max_hp/current_hp/armor_class exactly like the tail of apply_class_defaults()
# (called strictly after apply_class_defaults() — see class_select.gd/point_buy_select.gd —
# so class-set flags like check_prof_*/rage_uses_remaining are already in place and untouched).
func apply_point_buy_scores(scores: Dictionary) -> void:
	strength = int(scores.get("str", POINT_BUY_MIN))
	dexterity = int(scores.get("dex", POINT_BUY_MIN))
	constitution = int(scores.get("con", POINT_BUY_MIN))
	intelligence = int(scores.get("int", POINT_BUY_MIN))
	wisdom = int(scores.get("wis", POINT_BUY_MIN))
	charisma = int(scores.get("cha", POINT_BUY_MIN))
	max_hp = point_buy_hit_die_base() + modifier(constitution)
	current_hp = max_hp
	recalc_ac(false)

# ── Background ability score bonus (D&D 2024 backgrounds, scripts/ui/background_select.gd) ──
# Replaces 5e's racial ability-score bonuses — race grants none (see apply_race_defaults()).
# 3 points to distribute after point buy, max 2 into any single score, no cap on the resulting
# total (a point-buy 15 can become a background 17).
const BACKGROUND_POINTS: int = 3
const BACKGROUND_MAX_PER_STAT: int = 2

# Adds (never overrides) a background bonus on top of the already-applied point-buy scores, then
# re-derives max_hp/current_hp/armor_class exactly like apply_point_buy_scores()'s own tail —
# called strictly after apply_point_buy_scores(), before apply_race_defaults().
func apply_background_bonus(bonuses: Dictionary) -> void:
	strength += int(bonuses.get("str", 0))
	dexterity += int(bonuses.get("dex", 0))
	constitution += int(bonuses.get("con", 0))
	intelligence += int(bonuses.get("int", 0))
	wisdom += int(bonuses.get("wis", 0))
	charisma += int(bonuses.get("cha", 0))
	max_hp = point_buy_hit_die_base() + modifier(constitution)
	current_hp = max_hp
	recalc_ac(false)

func apply_class_defaults() -> void:
	match character_class:
		CharacterClass.BARBARIAN:
			strength = 16; constitution = 14; dexterity = 12
			intelligence = 8; wisdom = 10; charisma = 10
			max_hp = 12 + modifier(constitution)   # Barbarian HD d12
			rage_uses_remaining = rage_uses_max    # = 2 at level 1
			check_prof_str = true
			check_prof_con = true
			proficient_simple_weapons = true
			proficient_martial_weapons = true
			proficient_shields = true
			proficient_light_armor = true
			proficient_medium_armor = true
		CharacterClass.RANGER:
			dexterity = 16; wisdom = 14; constitution = 12
			strength = 10; intelligence = 10; charisma = 8
			max_hp = 10 + modifier(constitution)   # Ranger HD d10
			hunters_mark_uses_remaining = HUNTERS_MARK_USES_MAX
			check_prof_str = true
			check_prof_dex = true
			proficient_simple_weapons = true
			proficient_martial_weapons = true
			proficient_shields = true
			proficient_light_armor = true
			proficient_medium_armor = true
		CharacterClass.WIZARD:
			intelligence = 16; dexterity = 14; wisdom = 12
			constitution = 10; strength = 8; charisma = 10
			max_hp = 6 + modifier(constitution)    # Wizard HD d6
			check_prof_int = true
			check_prof_wis = true
			proficient_simple_weapons = true        # simple weapons only — no martial, no armor training
			caster = SpellcasterState.new()
			caster.spellcasting_ability = "INT"
			caster.slot_pool = StandardSlotPool.new()
			caster.slot_pool.owner_stats = self
		CharacterClass.MONK:
			dexterity = 16; wisdom = 14; constitution = 12
			strength = 10; intelligence = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Monk HD d8
			rage_uses_remaining = 0               # Monk never rages (rage_uses_max computed = 0)
			check_prof_str = true
			check_prof_dex = true
	current_hp = max_hp
	# Barbarian and Monk start unarmored — apply unarmored defense formulas.
	recalc_ac(false)

# Race defaults apply strictly AFTER class defaults, additively, and never touch the base
# ability scores — none of the six races grant a raw ability-score bonus (see
# docs/architecture/race-selection-design.md §2.3). Always fully re-derives darkvision_bonus/
# damage_resistances from character_race/race_variant (idempotent — safe to call again on respec
# or from_dict()).
func apply_race_defaults() -> void:
	darkvision_bonus = 0
	damage_resistances.clear()
	match character_race:
		CharacterRace.ORC:
			darkvision_bonus = 2
		CharacterRace.HUMAN:
			darkvision_bonus = 0
			heroic_inspiration_available = true
			if race_prof_ability >= 0:
				_grant_ability_proficiency(race_prof_ability)
		CharacterRace.HALFLING:
			darkvision_bonus = 0
		CharacterRace.DWARF:
			darkvision_bonus = 2
			# Dwarven Toughness: +1 HP per level, including level 1. _hp_per_level() already adds
			# +1 on every level-up gain, but that formula never runs for the character's starting
			# HP (set by apply_class_defaults()/apply_point_buy_scores() before race is chosen) —
			# so level 1 was silently missing its +1. Safe to apply unconditionally here: this
			# function always runs immediately after apply_class_defaults() (choose_race() during
			# onboarding, or from_dict()'s class-then-race replay, where max_hp is overwritten by
			# the saved value right after anyway) — never twice in a row without max_hp having
			# been freshly reset first.
			max_hp += 1
			current_hp += 1
		CharacterRace.ELF:
			darkvision_bonus = 1
			check_prof_wis = true
		CharacterRace.DRAGONBORN:
			darkvision_bonus = 1
			var dmg_type: String = DRAGONBORN_DAMAGE_TYPE[clampi(race_variant, 0, DRAGONBORN_DAMAGE_TYPE.size() - 1)]
			damage_resistances = [dmg_type]

func _grant_ability_proficiency(idx: int) -> void:
	match idx:
		0: check_prof_str = true
		1: check_prof_dex = true
		2: check_prof_con = true
		3: check_prof_int = true
		4: check_prof_wis = true
		5: check_prof_cha = true
