class_name Stats
extends Resource

enum CharacterClass {
	BARBARIAN, RANGER, WIZARD, MONK,
	BARD, CLERIC, DRUID, FIGHTER, PALADIN, ROGUE, SORCERER, WARLOCK
}

# Internal-only D&D-role categorization — never shown in any UI, purely a filter this codebase's
# own authors use when deciding "should class X get spellcasting / which slot table / etc." Keyed
# by plain class-name string rather than the CharacterClass enum above, since most of the 5e roster
# isn't implemented as a selectable class at all yet (see root CLAUDE.md's "Locked-class art") —
# this dict still names all of them so the categorization is complete even for classes that only
# exist as a locked character-select tile today.
#   MARTIAL      — no spellcasting: Barbarian, Fighter, Monk, Rogue
#   FULL_CASTER  — full spell-slot progression (Wizard's StandardSlotPool table): Bard, Cleric,
#                  Druid, Sorcerer, Warlock, Wizard
#   HALF_CASTER  — half spell-slot progression (HalfCasterSlotPool table, slots from level 1 per
#                  this project's 2024-rules convention): Ranger, Paladin
#   THIRD_CASTER — subclass-specific (e.g. Fighter's Eldritch Knight, Rogue's Arcane Trickster) —
#                  not a base-class role at all, so no third-caster row is implemented; noted here
#                  only so the categorization itself is complete.
# The only thing that currently CONSUMES this dict's information is `apply_class_defaults()`
# below, which grants a `caster` to every non-MARTIAL implemented class by hand (Wizard: FULL_CASTER,
# Ranger: HALF_CASTER) — nothing reads CLASS_ROLE programmatically yet, it's documentation of the
# decision, not a live gate. Extend this table (and the matching `apply_class_defaults()` branch)
# the moment a new class — Bard, Paladin, etc. — actually gets implemented.
const CLASS_ROLE: Dictionary = {
	"BARBARIAN": "MARTIAL",
	"FIGHTER":   "MARTIAL",
	"MONK":      "MARTIAL",
	"ROGUE":     "MARTIAL",
	"BARD":      "FULL_CASTER",
	"CLERIC":    "FULL_CASTER",
	"DRUID":     "FULL_CASTER",
	"SORCERER":  "FULL_CASTER",
	"WARLOCK":   "FULL_CASTER",
	"WIZARD":    "FULL_CASTER",
	"RANGER":    "HALF_CASTER",
	"PALADIN":   "HALF_CASTER",
}
enum CharacterRace { ORC, HUMAN, HALFLING, DWARF, ELF, DRAGONBORN, TIEFLING, AASIMAR, GNOME, GOLIATH }
enum ElfSubrace { DROW, HIGH_ELF, WOOD_ELF }          # only meaningful when character_race == ELF
enum DragonbornAncestry { BLACK, BLUE, BRASS, BRONZE, COPPER, GOLD, GREEN, RED, SILVER, WHITE }
enum TieflingLegacy { ABYSSAL, CHTHONIC, INFERNAL }   # only meaningful when character_race == TIEFLING; stored in race_variant like ElfSubrace/DragonbornAncestry
enum GnomeLineage { FOREST, ROCK }                    # only meaningful when character_race == GNOME; stored in race_variant like ElfSubrace/DragonbornAncestry/TieflingLegacy
enum GiantAncestry { CLOUD, FIRE, FROST, HILL, STONE, STORM }  # only meaningful when character_race == GOLIATH; stored in race_variant like ElfSubrace/DragonbornAncestry
enum AasimarTransformation { HEAVENLY_WINGS, INNER_RADIANCE, NECROTIC_SHROUD }  # Celestial Revelation's chosen form — NOT stored in race_variant (chosen fresh on each activation, not at race select), see Stats.celestial_revelation_transform below

const DRAGONBORN_DAMAGE_TYPE: Array[String] = [
	"Acid", "Lightning", "Fire", "Lightning", "Acid", "Fire", "Poison", "Fire", "Cold", "Cold"
]
const TIEFLING_LEGACY_RESIST: Array[String] = ["Poison", "Necrotic", "Fire"]  # indexed by TieflingLegacy

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
# Not granted by anything yet (future hook — e.g. a Warlock Devil's Sight-style feature). While
# false (always, today), heavily obscured terrain (Fog Cloud) blocks vision INTO it from outside —
# not even darkvision/truesight bypasses this, per 5e RAW; only this flag would.
var sees_through_magical_darkness: bool = false
var damage_resistances: Array[String] = []

# Gnome only: which of INT/WIS/CHA Gnomish Cunning grants Advantage on saves with — always
# re-derived from race_prof_ability in apply_race_defaults() (same "never saved directly" pattern
# as darkvision_bonus above), NOT a separate serialized field. race_prof_ability reuses the same
# STR=0..CHA=5 index Human's own ability-proficiency pick uses: 3=INT, 4=WIS, 5=CHA — see
# scripts/entities/CLAUDE.md's "Gnome" section for why only one stat is chosen (not all three).
var gnomish_cunning_stat: String = ""  # "" / "int" / "wis" / "cha"

func gnomish_cunning_grants_adv(stat: String) -> bool:
	return character_race == CharacterRace.GNOME and gnomish_cunning_stat == stat

# Per-long-rest race charge trackers — reset in GameState.long_rest(), same chokepoint as
# rage_uses_remaining/hit_dice.
var relentless_endurance_used: bool = false     # Orc
var heroic_inspiration_available: bool = false  # Human

# Orc Adrenaline Rush: proficiency_bonus uses, refilled on BOTH short rest AND long rest (unlike
# every other race charge above, which is long-rest-only) — see GameState._on_short_rest_completed()/
# long_rest() and scripts/entities/CLAUDE.md's "Orc" section.
var adrenaline_rush_uses_remaining: int = 0
# One-shot flag: the player's very next WASD move doesn't cost a turn. Not serialized — mid-floor
# buff state, same precedent as expeditious_retreat_turns/longstrider_turns.
var adrenaline_rush_move_free_pending: bool = false

# ── Elf: Elven Lineage ────────────────────────────────────────────────────────────
# Each of the 3 sub-races (ElfSubrace) grants two spells, at character levels 3 and 5
# (GameState.gain_exp()'s level-up block calls _grant_elf_lineage_spell() the instant either
# threshold is crossed — see scripts/entities/CLAUDE.md's "Elf" section). A lineage spell is
# ALWAYS PREPARED — granted straight onto the ability bar via GameState._build_spell_ability(),
# outside the normal known_spells/prepared_spells/SpellcasterState bookkeeping entirely, so it
# never counts against a caster's known-cantrip or prepared-spell cap (and exists even for a
# non-caster class, e.g. a Barbarian Elf). Each grants exactly one free cast per long rest
# (elf_lineage_free_cast_used, cleared in GameState.long_rest()) — SpellEffects._consume_slot()
# checks Stats.is_lineage_free_cast_available() before ever touching a real spell slot. Beyond
# the free use, a further cast needs a real spell slot of the spell's own level (Wizard/Ranger
# only) — a non-caster simply has no further casts available once the free one is spent, a
# documented simplification (same "non-caster gets the narrow case, not the full system" precedent
# as Scroll of <Spell> casting).
var elf_lineage_spell_ids: Array[String] = []
var elf_lineage_free_cast_used: Dictionary = {}

func is_lineage_free_cast_available(spell_id: String) -> bool:
	return spell_id in elf_lineage_spell_ids and not elf_lineage_free_cast_used.get(spell_id, false)

# ── Tiefling: Fiendish Legacy ─────────────────────────────────────────────────────
# Exact same shape as Elven Lineage above, just three thresholds instead of two (character levels
# 1/3/5, not 3/5 — the level-1 grant is handed out immediately at race select via
# GameState.give_race_starting_items(), not waiting for a level-up). Each of the 3 legacies
# (TieflingLegacy) grants a cantrip at level 1, a 1st-level spell at level 3, a 2nd-level spell at
# level 5 — always prepared, outside known_spells/prepared_spells bookkeeping, one free cast per
# long rest before falling back to a real spell slot (leveled spells only — a cantrip is already
# unlimited, so the free-cast tracking is a harmless no-op for the level-1 grant). See
# scripts/entities/CLAUDE.md's "Tiefling" section for the full spell table.
var tiefling_legacy_spell_ids: Array[String] = []
var tiefling_legacy_free_cast_used: Dictionary = {}

func is_tiefling_legacy_free_cast_available(spell_id: String) -> bool:
	return spell_id in tiefling_legacy_spell_ids and not tiefling_legacy_free_cast_used.get(spell_id, false)

# Hellish Rebuke (Infernal Tiefling's level-3 legacy grant) is implemented as a toggle-armed
# REACTION instead of a normal on-demand cast — RAW casts it as a reaction to being hit, and this
# engine has no reaction-casting framework, so arming it via the ability bar (PlayerTiefling.
# activate_hellish_rebuke(), scripts/entities/player_tiefling.gd) and letting enemy.gd's own
# _attack_player() trigger the actual cast is the closest analogue, same "arm now, spend the charge
# only when it actually procs" shape as Storm Giant Ancestry's own toggle (player_goliath.gd). Not
# serialized — combat-transient, same tier as giant_ancestry_armed.
var hellish_rebuke_armed: bool = false

# Fiendish Legacy spells are cast using "whichever of INT/WIS/CHA is highest" — not the character's
# own class spellcasting_ability (a Tiefling Barbarian has no caster ability at all; a Tiefling
# Wizard's own INT might not even be the best of the three). Checked by SpellEffects._attack_bonus()/
# _save_dc()/_cast_ability_mod() whenever the spell being cast is one of tiefling_legacy_spell_ids.
func tiefling_best_ability_mod() -> int:
	return maxi(int_modifier(), maxi(wis_modifier(), cha_modifier()))

# ── Gnome: Gnomish Lineage ────────────────────────────────────────────────────────
# Unlike Elf/Tiefling's single free-cast-per-long-rest bool, Gnomish Lineage spells are each
# castable proficiency_bonus times for free per long rest (direct owner request — a flat "once"
# felt too weak for a cantrip-tier grant, but all three unlimited felt too strong, hence a real
# counter instead of a bool). Granted immediately at race select (GameState.give_race_starting_items()),
# not staggered by character level like Elf/Tiefling — see scripts/entities/CLAUDE.md's "Gnome"
# section. Always prepared, outside known_spells/prepared_spells/SpellcasterState bookkeeping,
# same as Elven Lineage/Fiendish Legacy above.
var gnome_lineage_spell_ids: Array[String] = []
var gnome_lineage_free_casts_remaining: Dictionary = {}  # spell_id -> int, refilled in GameState.long_rest()

func is_gnome_lineage_free_cast_available(spell_id: String) -> bool:
	return spell_id in gnome_lineage_spell_ids and gnome_lineage_free_casts_remaining.get(spell_id, 0) > 0

# ── Aasimar ────────────────────────────────────────────────────────────────────────
# Healing Hands: proficiency-bonus-scaled touch heal, 1/long rest — see
# scripts/entities/player_aasimar.gd / scripts/entities/CLAUDE.md's "Aasimar" section.
var aasimar_healing_hands_available: bool = false
# Celestial Revelation: unlocked at character level 3 (GameState.give_race_starting_items()'s
# level-gate, same "granted the instant character_level reaches N" pattern as Dragonborn's Draconic
# Flight), 1/long rest. celestial_revelation_transform is chosen FRESH each activation (NOT stored
# in race_variant, which is fixed at race select) — so none of these three fields are serialized as
# "mid-floor buff state" except celestial_revelation_used, which genuinely needs to survive a
# save/load (it's a real once-per-long-rest resource, not a transient turn-counter).
var aasimar_celestial_revelation_used: bool = false
var celestial_revelation_turns: int = 0             # not serialized — mid-floor buff, same precedent as expeditious_retreat_turns
var celestial_revelation_transform: int = -1         # -1 = none active; else Stats.AasimarTransformation
var celestial_revelation_bonus_used_this_turn: bool = false  # resets every real turn while active — "the FIRST damage you deal each turn"

# ── Goliath ────────────────────────────────────────────────────────────────────────
# Large Form (unlocked at character level 5, same level-gate shape as Dragonborn's Draconic
# Flight): free action, up to 100 turns, 1/long rest. Turns the player into a real 2x2 footprint
# (Entity.size — see scripts/entities/CLAUDE.md's "Multi-tile footprint" section; this is the
# first time PLAYER, not just an enemy, ever sets it above (1,1)). Grants ADV on the one player
# STR check that currently exists (the Web escape check, PlayerThiefTools) and a Wood-Elf-style
# duty-cycle +1/3 movement bonus (every 3rd move is free) — see player_goliath.gd. Not serialized
# (mid-floor buff state, same precedent as draconic_flight_turns).
var large_form_turns: int = 0
var large_form_used: bool = false
# Giant Ancestry: proficiency_bonus uses per long rest, same shape as Dwarf's Stonecunning. Which
# one of Cloud/Fire/Frost/Hill/Stone/Storm is chosen lives in race_variant (Stats.GiantAncestry).
var giant_ancestry_uses_remaining: int = 0
# Fire/Frost/Stone/Storm Giant all share one "arm now, spend the charge only when it actually
# triggers" shape (a miss/no-trigger never wastes a charge) — this single pending flag is enough
# since only one Giant Ancestry is ever active per character. Cloud Giant (instant teleport) and
# Hill Giant (passive on-hit) don't use it. Not serialized — mid-floor pending state.
var giant_ancestry_armed: bool = false
# Stone Giant's armed reduction, consumed by the next instance of damage taken (GameState.
# take_damage_raw()) — rolled at ARM time (not at the moment damage lands), per the "arm now"
# shape above sharing one `giant_ancestry_armed` flag with Fire/Frost/Storm.
var stone_ancestry_reduction_pending: int = 0

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

# Dragonborn Breath Weapon uses (Dragonborn only) — baseline level-1 ability, granted directly
# like Rage/Hunter's Mark above. Max uses = proficiency_bonus (5e 2024 rule); refilled to max in
# GameState.long_rest(), and bumped by +1 CURRENT use the instant a level-up raises proficiency_bonus
# (levels 5/9/13/17 — see GameState.gain_exp()). Damage dice scale separately via
# breath_weapon_dice_count() below (1d10 base, +1d10 at levels 5/11/17 — 5e 2024's own progression).
var breath_weapon_uses_remaining: int = 0

func breath_weapon_dice_count() -> int:
	var n: int = 1
	if character_level >= 5:  n += 1
	if character_level >= 11: n += 1
	if character_level >= 17: n += 1
	return n

# Stonecunning (Dwarf only) — baseline level-1 ability, same granted-directly shape as Breath
# Weapon above. Max uses = proficiency_bonus, refilled to max in GameState.long_rest(), bumped by
# +1 CURRENT use the instant a level-up raises proficiency_bonus. Free action (does not cost a
# turn), range STONECUNNING_RANGE (6 tiles, flat — not fed through the /20 or /10 ranged-scaling
# divisors, since this is a sense, not an attack), grants Tremorsense for up to 100 turns.
var stonecunning_uses_remaining: int = 0
var tremorsense_turns: int = 0
const STONECUNNING_RANGE: int = 6

# Draconic Flight (Dragonborn only, unlocked at level 5) — up to 100 turns of "flight": crosses
# CHASM tiles freely, never tramples GRASS, never triggers traps, and is immune to standing-on-fire
# damage (see DungeonFloor.tick_fire_damage_for()'s Player branch). 1/long rest — draconic_flight_
# used resets in GameState.long_rest(). Free action (does not cost a turn to activate).
var draconic_flight_turns: int = 0
var draconic_flight_used: bool = false

# Hunter's Mark uses (Ranger only) — baseline level-1 ability, not talent-gated, same
# "granted directly, resource-limited" shape as Rage. A use is spent only when establishing a
# mark on a target from having none (retargeting an already-active mark is free — 5e "move
# Hunter's Mark for free"); refilled to max in GameState.long_rest(). Flat, doesn't scale by
# level (unlike Rage) — simple to start, tune later.
var hunters_mark_uses_remaining: int = 0
const HUNTERS_MARK_USES_MAX: int = 3
const HUNTERS_MARK_RANGE: int = 5
const HUNTERS_MARK_DURATION: int = 600

# The currently marked enemy (Hunter's Mark). Deliberately NOT serialized in to_dict()/from_dict()
# — a live Enemy node reference can't survive save/load, same precedent as witch_bolt_target
# above: the mark simply ends silently on load, no cleanup needed.
var hunters_mark_target: Enemy = null
# Set true the moment a mark is (re)established, cleared on the marked target's first taken hit —
# drives Bloodhound R1's "first attack against a fresh mark gets Advantage".
var hunters_mark_fresh: bool = false
# Concentration duration (100 turns, ticked once per real player turn like Blade Ward/Fog Cloud/
# Expeditious Retreat) — 0 = not currently marking. Not serialized (mid-floor concentration state,
# same precedent as witch_bolt_turns/expeditious_retreat_turns).
var hunters_mark_turns: int = 0
# Free-recast window (markdowns/ranger_base.md): if the Marked target dies while concentration is
# still active, the player gets ONE free re-mark (no use spent) — but only during their very next
# real turn, never later. `_pending` is armed the instant the target dies; the following
# `_on_turn_started()` promotes it to `_available` for that single turn, then clears it at the turn
# after that if unused. Both transient, not serialized.
var hunters_mark_free_recast_pending: bool = false
var hunters_mark_free_recast_available: bool = false

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

## Turns remaining on whichever spell concentration_spell_id currently names, for the status tray
## tooltip (scripts/ui/status_tooltips.gd) — mirrors GameState.end_concentration()'s own exhaustive
## match of every concentration spell's duration field. Returns 0 when not concentrating, or for a
## (should-never-happen) unmatched id. Any new concentration-granting spell must add itself here
## too, same maintenance burden as end_concentration().
func concentration_turns_remaining() -> int:
	match concentration_spell_id:
		"blade_ward": return blade_ward_turns
		"witch_bolt": return witch_bolt_turns
		"expeditious_retreat": return expeditious_retreat_turns
		"fog_cloud": return fog_cloud_turns
		"darkness": return darkness_turns
		"detect_magic": return detect_magic_turns
		"pass_without_trace": return pass_without_trace_turns
		"hunters_mark": return hunters_mark_turns
		"ray_of_enfeeblement": return ray_of_enfeeblement_turns
		"hold_person": return hold_person_turns
		"faerie_fire": return faerie_fire_turns
		"invisibility": return invisibility_turns
		_: return 0
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

# Darkness (Drow lineage spell, level 5) — same generic concentration_spell_id mechanism
# ("darkness") and the same GameState-side position/radius split as Fog Cloud (darkness_pos/
# darkness_radius) — reuses the exact same Heavily Obscured/Blinded mechanism (see
# scripts/entities/CLAUDE.md's "Fog Cloud" section); the only difference is a second, independent
# zone so both spells can be active at once. Deliberately NOT serialized, same as fog_cloud_turns.
var darkness_turns: int = 0

# Faerie Fire (Drow lineage spell, level 1) — same generic concentration_spell_id mechanism
# ("faerie_fire"), just the caster's own duration counter (the affected-enemy side of the
# duration is tracked independently, per-enemy, on Enemy.faerie_fire_turns — see
# scripts/entities/CLAUDE.md's "Elf" section). Deliberately NOT serialized, same as
# darkness_turns/fog_cloud_turns above.
var faerie_fire_turns: int = 0
# Whether the PLAYER THEMSELVES is currently outlined by a (self- or otherwise-)cast Faerie Fire —
# a separate field from faerie_fire_turns above (that one is always the CASTER's own concentration
# countdown, regardless of who ends up outlined; this one is "am I, the player, currently lit up").
# Faerie Fire can catch the caster in their own 2x2 blast just like any other creature there, so the
# two must never collide/overwrite each other. Mirrors Enemy.faerie_fire_turns/faerie_fire_color.
# Grants enemies Advantage on attacks against the player while set (enemy.gd's _attack_player()),
# same rule as the enemy-side "Advantage on attacks against it, if the attacker can see it."
var faerie_fire_outlined_turns: int = 0
var faerie_fire_outlined_color: Color = Color.WHITE

# Ray of Enfeeblement (Chthonic Tiefling lineage spell, level 2) — same generic
# concentration_spell_id mechanism ("ray_of_enfeeblement") + live target reference as Witch Bolt,
# since the ongoing effect (Enemy.enfeeble_turns' full debuff) is per-target, not a self-buff.
# Deliberately NOT serialized, same precedent as witch_bolt_target/witch_bolt_turns above.
var ray_of_enfeeblement_target: Enemy = null
var ray_of_enfeeblement_turns: int = 0

# Hold Person (Abyssal Tiefling lineage spell, level 2) — same generic concentration_spell_id
# mechanism ("hold_person") + live target reference as Ray of Enfeeblement/Witch Bolt (the ongoing
# Paralyzed condition lives on Enemy.paralyzed_turns, per-target). Deliberately NOT serialized,
# same precedent as witch_bolt_target/witch_bolt_turns above.
var hold_person_target: Enemy = null
var hold_person_turns: int = 0

# Longstrider (Wood Elf lineage spell, level 3) — NOT Concentration (5e RAW). +1/3 movement speed
# via the same duty-cycle mechanism as Wood Elf's 35ft speed / Goliath's Large Form (Player.
# _longstrider_move_counter — every 3rd real move is free) — NOT Expeditious Retreat's "first
# move each turn is free" mechanism, which is a genuine double-move and was a bug when Longstrider
# used to share it. See scripts/entities/CLAUDE.md's "Elf" section. Deliberately NOT serialized,
# same mid-floor-only simplification as expeditious_retreat_turns.
var longstrider_turns: int = 0

# Detect Magic (level-1 spell, Ritual, SELF) — same generic concentration_spell_id mechanism
# ("detect_magic") as Fog Cloud/Darkness. While active, DungeonFloor._update_detect_magic_markers()
# shows a blue tremorsense-style ping over every magic item within Spell.shape_size (3) tiles of
# the player — see scripts/entities/CLAUDE.md's "Elf" section (High Elf grant) and
# scripts/entities/spell_effects.gd's _resolve_detect_magic(). Deliberately NOT serialized, same
# mid-floor-only simplification as fog_cloud_turns/darkness_turns above.
var detect_magic_turns: int = 0

# Pass Without Trace (Wood Elf lineage spell, level 5) — same generic concentration_spell_id
# mechanism ("pass_without_trace"). Grants a flat bonus to the Stealth-vs-Passive-Perception roll
# (Player._resolve_stealth_check()) while active. Deliberately NOT serialized, same as
# fog_cloud_turns above.
var pass_without_trace_turns: int = 0
const PASS_WITHOUT_TRACE_BONUS: int = 10

# Minor Illusion (Forest Gnome's Gnomish Lineage cantrip) — a much smaller, shorter-lived version
# of Pass Without Trace's own stealth bonus (a minor visual/sound distraction, not true invisibility
# to sound and sight), same "flat bonus to the Stealth-vs-Passive-Perception roll" mechanism.
# Deliberately NOT Concentration (5e RAW: Minor Illusion has no concentration tag). Not serialized,
# same mid-floor-only simplification as pass_without_trace_turns above.
var minor_illusion_turns: int = 0
const MINOR_ILLUSION_BONUS: int = 5

# Invisibility (level-2 spell, touch/self) — a real Concentration effect (concentration_spell_id
# == "invisibility"), same mutual-exclusion + damage-based CON-check break as every other
# concentration spell (GameState._check_concentration_break(), via take_damage_raw()'s tail). Also
# still ends early on attacking/casting a spell (5e RAW's OWN additional end condition, on top of
# concentration) via Player._resolve_stealth_check() reading GameState.stealth_check_skip (the
# same "this turn was an attack/spell-cast" flag the Stealth-vs-Passive-Perception system already
# sets at every attack/cast call site — see scripts/entities/CLAUDE.md's "Invisibility" section).
# Ticked in player.gd's per-real-turn block. Deliberately NOT serialized, same mid-floor-only
# simplification as witch_bolt_turns/fog_cloud_turns above.
var invisibility_turns: int = 0
# Set true on cast, consumed (cleared) the first time _resolve_stealth_check() runs afterward —
# skips ending Invisibility on its OWN casting turn (cast_leveled_self() sets stealth_check_skip
# unconditionally, same as every other spell), same "just_cast" pattern as witch_bolt_just_cast.
var invisibility_just_cast: bool = false

# Spider's Web ability (enemy pool "web") — a persistent Restrained condition, NOT a turn-counter
# status like slowed/poisoned/etc.: it lasts until the web structure is destroyed, not for N turns,
# so it can't reuse tick_status()'s countdown shape. `web_escape_dc` is the DC the DEX save that
# webbed you rolled against (stashed here so the escape-attempt STR check in player.gd uses the
# same DC without needing a second authored number). Cleared by Player._attempt_web_escape() on a
# successful STR check, which also calls DungeonFloor.destroy_web(grid_pos) — safe to assume the
# web is still directly underfoot since being Restrained blocks all movement (see player.gd's
# _try_move()). Deliberately NOT serialized, same mid-floor-only simplification as
# witch_bolt_turns/fog_cloud_turns/invisibility_turns above.
var web_restrained: bool = false
var web_escape_dc: int = 13

# ── Conditions (Poisoned/Prone/Restrained/Incapacitated) ─────────────────────────
# Restrained is `web_restrained` above (Spider's Web is still its only source). The three below
# are turn-counter conditions, same tick_status() shape as poison_turns/burning_turns/etc., but
# kept as SEPARATE fields from those — poisoned_condition_turns is the real 5e Poisoned condition
# (DISADV on attacks/checks) and is deliberately independent of poison_turns (the pre-existing
# damage-over-time counter every potion/Rend/etc. already sets): a source that inflicts one
# doesn't have to inflict the other (Rend inflicts ONLY the condition, no poison damage; a
# Poison Potion still deals ONLY damage, no condition) — see GameState.apply_player_status().
# Deliberately NOT serialized, same mid-floor-only simplification as web_restrained/
# invisibility_turns/fog_cloud_turns above — combat conditions simply end on save/load.
var poisoned_condition_turns: int = 0
var prone: bool = false                # persists until stood up (Player._try_move()'s redirect), not turn-counted
var incapacitated_turns: int = 0

# Frightened — unlike the three above, tied to a SPECIFIC source creature (5e: "DISADV on checks/
# attacks while the source is in sight" + "can't willingly move closer to it"), not a bare turn
# counter, so it doesn't fit apply_player_status()'s generic (type, turns) shape — set via the
# dedicated GameState.apply_player_frightened(source, turns)/clear_player_frightened(). A live
# Enemy reference, same "NOT serialized, mid-floor-only" precedent as hunters_mark_target/
# witch_bolt_target — simply ends silently on save/load. `frightened_turns` is the outer 5e "1
# minute" cap (~10 real turns here); ends earlier on a successful repeated WIS save, ticked
# alongside it in Player._on_turn_started() rather than Stats.tick_status() (which only deals
# damage, never rolls a check).
var frightened_source: Enemy = null
var frightened_turns: int = 0
var frightened_save_dc: int = 10  # the WIS save DC the repeated end-of-turn check rolls against (stashed here same as web_escape_dc, rather than hardcoding Scare's own DC)

# True while any condition that imposes a blanket DISADV on attack rolls/ability checks is active
# (5e: Poisoned, Prone [attacks only], Restrained). Multiple conditions never stack disadvantage
# (5e has no "double disadvantage") — every attack/check call site adds at most 1 to its
# disadv_count from this single helper instead of checking each field separately.
func has_disadvantage_condition() -> bool:
	return poisoned_condition_turns > 0 or prone or web_restrained

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
		CharacterClass.BARD:      avg = 5  # d8 avg = 5
		CharacterClass.CLERIC:    avg = 5  # d8 avg = 5
		CharacterClass.DRUID:     avg = 5  # d8 avg = 5
		CharacterClass.FIGHTER:   avg = 6  # d10 avg = 6
		CharacterClass.PALADIN:   avg = 6  # d10 avg = 6
		CharacterClass.ROGUE:     avg = 5  # d8 avg = 5
		CharacterClass.SORCERER:  avg = 4  # d6 avg = 4
		CharacterClass.WARLOCK:   avg = 5  # d8 avg = 5
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
	if poisoned_condition_turns > 0:
		poisoned_condition_turns -= 1
	if incapacitated_turns > 0:
		incapacitated_turns -= 1
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
		"adrenaline_rush_uses_remaining": adrenaline_rush_uses_remaining,
		"experience": experience,
		"max_hp": max_hp,
		"current_hp": current_hp,
		"base_min_damage": base_min_damage,
		"base_max_damage": base_max_damage,
		"rage_uses_remaining": rage_uses_remaining,
		"hunters_mark_uses_remaining": hunters_mark_uses_remaining,
		"breath_weapon_uses_remaining": breath_weapon_uses_remaining,
		"draconic_flight_used": draconic_flight_used,
		"stonecunning_uses_remaining": stonecunning_uses_remaining,
		"large_form_used": large_form_used,
		"giant_ancestry_uses_remaining": giant_ancestry_uses_remaining,
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
		"elf_lineage_spell_ids": elf_lineage_spell_ids.duplicate(),
		"elf_lineage_free_cast_used": elf_lineage_free_cast_used.duplicate(),
		"tiefling_legacy_spell_ids": tiefling_legacy_spell_ids.duplicate(),
		"tiefling_legacy_free_cast_used": tiefling_legacy_free_cast_used.duplicate(),
		"gnome_lineage_spell_ids": gnome_lineage_spell_ids.duplicate(),
		"gnome_lineage_free_casts_remaining": gnome_lineage_free_casts_remaining.duplicate(),
		"aasimar_healing_hands_available": aasimar_healing_hands_available,
		"aasimar_celestial_revelation_used": aasimar_celestial_revelation_used,
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
	adrenaline_rush_uses_remaining = int(d.get("adrenaline_rush_uses_remaining", 0))
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
	breath_weapon_uses_remaining = int(d.get("breath_weapon_uses_remaining", 0))
	draconic_flight_used = bool(d.get("draconic_flight_used", false))
	stonecunning_uses_remaining = int(d.get("stonecunning_uses_remaining", 0))
	large_form_used = bool(d.get("large_form_used", false))
	giant_ancestry_uses_remaining = int(d.get("giant_ancestry_uses_remaining", 0))
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
	elf_lineage_spell_ids.clear()
	for sid: Variant in (d.get("elf_lineage_spell_ids", []) as Array):
		elf_lineage_spell_ids.append(String(sid))
	elf_lineage_free_cast_used = (d.get("elf_lineage_free_cast_used", {}) as Dictionary).duplicate()
	tiefling_legacy_spell_ids.clear()
	for tsid: Variant in (d.get("tiefling_legacy_spell_ids", []) as Array):
		tiefling_legacy_spell_ids.append(String(tsid))
	tiefling_legacy_free_cast_used = (d.get("tiefling_legacy_free_cast_used", {}) as Dictionary).duplicate()
	gnome_lineage_spell_ids.clear()
	for gsid: Variant in (d.get("gnome_lineage_spell_ids", []) as Array):
		gnome_lineage_spell_ids.append(String(gsid))
	gnome_lineage_free_casts_remaining = (d.get("gnome_lineage_free_casts_remaining", {}) as Dictionary).duplicate()
	aasimar_healing_hands_available = bool(d.get("aasimar_healing_hands_available", true))
	aasimar_celestial_revelation_used = bool(d.get("aasimar_celestial_revelation_used", false))
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
		CharacterClass.BARD: return 8
		CharacterClass.CLERIC: return 8
		CharacterClass.DRUID: return 8
		CharacterClass.FIGHTER: return 10
		CharacterClass.PALADIN: return 10
		CharacterClass.ROGUE: return 8
		CharacterClass.SORCERER: return 6
		CharacterClass.WARLOCK: return 8
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
			# Half-caster (CLASS_ROLE above) — WIS-based, HalfCasterSlotPool (slots from level 1,
			# 2024-rules half-caster table, max spell level 5). No cantrips (cantrip_max() stays 0
			# for every non-Wizard class) — see scripts/entities/CLAUDE.md's "Ranger class".
			caster = SpellcasterState.new()
			caster.spellcasting_ability = "WIS"
			caster.slot_pool = HalfCasterSlotPool.new()
			caster.slot_pool.owner_stats = self
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
			# Weapon profs intentionally NOT set — real Monk proficiency is Simple + only the
			# Martial weapons with the Light property, a finer grain than the flat
			# proficient_simple_weapons/proficient_martial_weapons bools support (same
			# pre-existing TODO noted in scripts/entities/CLAUDE.md's "Monk class" section).
			# No armor training (any armor gives DISADV on STR/DEX checks/attacks — not enforced).
		# ── Base D&D stat blocks only (root CLAUDE.md's "Locked-class art") — none of these 8
		# are selectable in character creation or class_select.gd/character_select.gd yet, and
		# none get starting items/abilities/spellcasting here. This just gives Stats a real,
		# usable ability-score/HP/proficiency baseline for whenever each one is wired up for real.
		CharacterClass.BARD:
			charisma = 16; dexterity = 14; constitution = 12
			wisdom = 10; intelligence = 10; strength = 8
			max_hp = 8 + modifier(constitution)    # Bard HD d8
			check_prof_dex = true
			check_prof_cha = true
			proficient_simple_weapons = true
			proficient_light_armor = true
		CharacterClass.CLERIC:
			wisdom = 16; constitution = 14; charisma = 12
			strength = 10; dexterity = 10; intelligence = 8
			max_hp = 8 + modifier(constitution)    # Cleric HD d8
			check_prof_wis = true
			check_prof_cha = true
			proficient_simple_weapons = true
			proficient_shields = true
			proficient_light_armor = true
			proficient_medium_armor = true
		CharacterClass.DRUID:
			wisdom = 16; constitution = 14; dexterity = 12
			intelligence = 10; strength = 10; charisma = 8
			max_hp = 8 + modifier(constitution)    # Druid HD d8
			check_prof_int = true
			check_prof_wis = true
			proficient_simple_weapons = true
			proficient_shields = true
			proficient_light_armor = true
		CharacterClass.FIGHTER:
			strength = 16; constitution = 14; dexterity = 12
			wisdom = 10; intelligence = 10; charisma = 8
			max_hp = 10 + modifier(constitution)   # Fighter HD d10
			check_prof_str = true
			check_prof_con = true
			proficient_simple_weapons = true
			proficient_martial_weapons = true
			proficient_shields = true
			proficient_light_armor = true
			proficient_medium_armor = true
			proficient_heavy_armor = true
		CharacterClass.PALADIN:
			strength = 16; charisma = 14; constitution = 12
			wisdom = 10; dexterity = 10; intelligence = 8
			max_hp = 10 + modifier(constitution)   # Paladin HD d10
			check_prof_wis = true
			check_prof_cha = true
			proficient_simple_weapons = true
			proficient_martial_weapons = true
			proficient_shields = true
			proficient_light_armor = true
			proficient_medium_armor = true
			proficient_heavy_armor = true
		CharacterClass.ROGUE:
			dexterity = 16; intelligence = 14; constitution = 12
			wisdom = 10; charisma = 10; strength = 8
			max_hp = 8 + modifier(constitution)    # Rogue HD d8
			check_prof_dex = true
			check_prof_int = true
			proficient_simple_weapons = true
			# proficient_martial_weapons intentionally NOT set — real Rogue proficiency is Simple
			# + only the Martial weapons that are Finesse or Light, same finer-grain gap as Monk
			# above (no per-property weapon-proficiency field exists yet).
			proficient_light_armor = true
		CharacterClass.SORCERER:
			charisma = 16; constitution = 14; dexterity = 12
			wisdom = 10; intelligence = 10; strength = 8
			max_hp = 6 + modifier(constitution)    # Sorcerer HD d6
			check_prof_con = true
			check_prof_cha = true
			proficient_simple_weapons = true
			# No armor/shield proficiency at all — matches real 5e Sorcerer.
		CharacterClass.WARLOCK:
			charisma = 16; constitution = 14; dexterity = 12
			wisdom = 10; intelligence = 10; strength = 8
			max_hp = 8 + modifier(constitution)    # Warlock HD d8
			check_prof_wis = true
			check_prof_cha = true
			proficient_simple_weapons = true
			proficient_light_armor = true
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
	gnomish_cunning_stat = ""
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
			# Dwarven Resilience: Poison damage resistance. The "advantage on checks to avoid or
			# end the Poisoned condition" half is deferred — no save/check exists anywhere in this
			# engine for gaining/ending Poisoned yet (Tripwire trap / Quasit's Rend both apply it
			# unconditionally), so there's nothing to grant Advantage on. Wire it in once such a
			# check exists (direct owner decision — see scripts/entities/CLAUDE.md's "Dwarf" section).
			damage_resistances.append("Poison")
		CharacterRace.ELF:
			# Keen Senses: WIS proficiency (shared underlying flag with Wizard's own INT+WIS class
			# checks — harmless overlap, not a stacking bonus, since check_prof_wis is a bool).
			darkvision_bonus = 2 if race_variant == ElfSubrace.DROW else 1  # Drow: superior darkvision
			check_prof_wis = true
			# Fey Ancestry: ADV on checks to avoid/end the Charmed condition. Deliberately inert
			# today — no Charmed condition (or any check against it) exists anywhere in this engine
			# yet, same "granted but nothing to hook into" precedent as Dwarf's own Dwarven
			# Resilience ADV-vs-Poisoned-condition half (see this file's DWARF branch above). Wire
			# in once a real Charmed source/check exists rather than inventing one just to hang
			# this on.
		CharacterRace.DRAGONBORN:
			darkvision_bonus = 1
			var dmg_type: String = DRAGONBORN_DAMAGE_TYPE[clampi(race_variant, 0, DRAGONBORN_DAMAGE_TYPE.size() - 1)]
			damage_resistances = [dmg_type]
		CharacterRace.TIEFLING:
			darkvision_bonus = 1
			# Fiendish Legacy's resistance is baked into the chosen legacy (Abyssal/Chthonic/
			# Infernal → Poison/Necrotic/Fire) — the spells themselves are granted separately, see
			# GameState.give_race_starting_items()/gain_exp() and scripts/entities/CLAUDE.md's
			# "Tiefling" section.
			var legacy_dmg_type: String = TIEFLING_LEGACY_RESIST[clampi(race_variant, 0, TIEFLING_LEGACY_RESIST.size() - 1)]
			damage_resistances = [legacy_dmg_type]
		CharacterRace.AASIMAR:
			darkvision_bonus = 1
			# Celestial Resistance: both Necrotic and Radiant, unconditionally (no race_variant
			# choice — unlike Tiefling's legacy-picked single resistance).
			damage_resistances = ["Necrotic", "Radiant"]
		CharacterRace.GNOME:
			darkvision_bonus = 1
			# Gnomish Cunning: ADV on saves with ONE of INT/WIS/CHA (player's choice at race
			# select, not all three — see scripts/entities/CLAUDE.md's "Gnome" section for why).
			# race_prof_ability reuses Human's own STR=0..CHA=5 index; only 3/4/5 (INT/WIS/CHA)
			# are ever set for a Gnome.
			if race_prof_ability >= 3:
				gnomish_cunning_stat = ["int", "wis", "cha"][race_prof_ability - 3]
		CharacterRace.GOLIATH:
			darkvision_bonus = 0
			# Giant Ancestry's resistance/passive (if any) is folded into the ability itself rather
			# than a passive damage_resistances entry — unlike Dragonborn/Tiefling/Aasimar, none of
			# the 6 Giant Ancestries grant an unconditional passive resistance; each is purely an
			# activatable (see player_goliath.gd / scripts/entities/CLAUDE.md's "Goliath" section).

func _grant_ability_proficiency(idx: int) -> void:
	match idx:
		0: check_prof_str = true
		1: check_prof_dex = true
		2: check_prof_con = true
		3: check_prof_int = true
		4: check_prof_wis = true
		5: check_prof_cha = true
