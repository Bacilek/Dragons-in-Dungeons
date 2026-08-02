class_name SpellDb
extends RefCounted

# Static factory for spell definitions — same "no .tres files" convention as Talent/SpriteFrames.
# Cantrips are the framework's original slice (docs/architecture/spellcasting-design.md); the 4
# leveled spells below are the worked examples from
# docs/architecture/leveled-spells-and-slots-plan.md §7 (Burning Hands/cone AoE was cut from the
# doc's original 5-spell list to keep SpellShapes to sphere-only for this pass — see that doc's
# §7 caveat and CLAUDE.md). Full class spell lists remain future content work.

const CANTRIP_IDS: Array[String] = ["fire_bolt", "ray_of_frost", "shocking_grasp", "toll_the_dead", "blade_ward", "thunderclap", "mind_sliver", "light", "poison_spray", "chill_touch", "eldritch_blast"]
# The Wizard's fixed round-1 starting choice (cantrip_select.gd) — unchanged by the 5 additions
# above so the premade Jace's "cantrip": "fire_bolt" shortcut and existing save data stay valid.
const STARTER_CANTRIP_IDS: Array[String] = ["fire_bolt", "ray_of_frost", "shocking_grasp"]
# Warlock's own round-1 starting-cantrip choice (see scripts/entities/CLAUDE.md's "Warlock class").
# Eldritch Blast is Warlock's signature attack cantrip — real 5e multi-beam/multi-target: 1d10
# Force per beam, one beam at level 1, +1 independently-targetable beam at levels 5/11/17
# (Spell.multi_beam_scaling, resolved via the generalized multi-target flow — see
# PlayerSpellcasting._multi_target_beam_count()/SpellEffects.cast_multi_beam_cantrip() — the same
# click-to-pick-a-target-per-instance UX Magic Missile's darts already used). See
# _eldritch_blast() below.
const WARLOCK_STARTER_CANTRIP_IDS: Array[String] = ["eldritch_blast", "chill_touch", "poison_spray"]
const LEVELED_SPELL_IDS: Array[String] = ["magic_missile", "shield", "mage_armor", "misty_step", "fireball", "chromatic_orb", "burning_hands", "witch_bolt", "expeditious_retreat", "false_life", "fog_cloud", "invisibility", "darkness", "longstrider", "detect_magic", "pass_without_trace", "faerie_fire", "ray_of_sickness", "ray_of_enfeeblement", "hold_person", "hideous_laughter"]
# Ranger (half-caster, scripts/entities/CLAUDE.md's "Ranger class") draws from the same shared
# `SpellDb` pool as Wizard, but ONLY the subset actually on Ranger's real 5e/5.5e (2024) spell
# list — direct owner correction: don't just open every `LEVELED_SPELL_IDS` entry up to Ranger
# "for consistency", each spell's actual RAW class list matters. Of these 13, Fog Cloud and Pass
# Without Trace are genuinely Druid/Ranger(/Sorcerer/Wizard); every arcane blast/utility spell here
# (Magic Missile, Shield, Mage Armor, Misty Step, Fireball, Chromatic Orb, Burning Hands, Witch
# Bolt, Expeditious Retreat, False Life, Invisibility) is Sorcerer/Wizard(/Warlock) only on both
# rule sets — see each spell's own `class_list` comment above. This makes Ranger's actual castable
# pool thin today (a real content gap, not a bug — this codebase has zero other nature-flavored
# spell content of its own, e.g. Ensnaring Strike/Goodberry/Hunter's Mark-as-a-spell/Zephyr Strike
# from the real 2024 Ranger list). No cantrips for Ranger either way (`cantrip_max()` stays 0 for
# every non-Wizard class, matching both rule sets — Rangers don't get cantrips).
const RANGER_SPELL_IDS: Array[String] = ["fog_cloud", "pass_without_trace"]
# Warlock's real 5e/2024 Pact Magic list overlap with the shared SpellDb pool (scripts/entities/
# CLAUDE.md's "Warlock class") — all seven are genuinely on Warlock's actual class list, no
# reflavoring needed, unlike Ranger's thinner/approximated subset above.
const WARLOCK_SPELL_IDS: Array[String] = ["witch_bolt", "expeditious_retreat", "darkness", "hold_person", "invisibility", "misty_step", "ray_of_enfeeblement", "hideous_laughter"]
const CLASS_SPELL_LISTS: Dictionary = {"WIZARD": LEVELED_SPELL_IDS, "RANGER": RANGER_SPELL_IDS, "WARLOCK": WARLOCK_SPELL_IDS}   # cantrips excluded — never offered by the level-up picker

# Elf lineage-only spells (see scripts/entities/CLAUDE.md's "Elf" section) — granted exclusively by
# GameState._grant_elf_lineage_spell(). Originally none of these were learnable via the level-up
# spellbook-growth picker or any class's known-spell list; that's no longer true for ALL FIVE —
# "darkness" (Drow, level 5), "longstrider" (Wood Elf, level 3), "detect_magic" (High
# Elf, level 3), "pass_without_trace" (Wood Elf, level 5), and now "faerie_fire" (Drow, level 3)
# too are ALSO real, independently-learnable LEVELED_SPELL_IDS entries (their real 5e/5.5e class
# lists include several classes this codebase doesn't have, so class_list is `["WIZARD"]` for all
# five except Pass Without Trace's `["RANGER"]`, its one implemented real-list class) — they're
# listed here too only because their sub-race also grants them for free at the matching level via
# the same lineage mechanism. The free-cast-per-long-rest economy and the
# LEVELED_SPELL_IDS/level-up-picker/slot-casting paths are independent of each other and both work
# regardless of how a spell was acquired. A Scroll of Faerie Fire now exists too (full
# spell-coverage pass, scripts/items/CLAUDE.md's "Scroll of <Spell>") — every ELF_LINEAGE_SPELL_IDS
# entry has a scroll now, not just the four that were already real LEVELED_SPELL_IDS entries.
const ELF_LINEAGE_SPELL_IDS: Array[String] = ["faerie_fire", "darkness", "detect_magic", "longstrider", "pass_without_trace"]

# Tiefling Fiendish Legacy-only spells (see scripts/entities/CLAUDE.md's "Tiefling" section) —
# granted exclusively by GameState._grant_tiefling_legacy_spell(), same "never in the level-up
# picker or any class's known-spell list" exclusion as ELF_LINEAGE_SPELL_IDS above (Fire Bolt
# (Infernal, level 1), False Life (Chthonic, level 3), and Darkness (Infernal, level 5) reuse the
# existing Wizard cantrip/Wizard-leveled/Elf-lineage spells verbatim — not listed here). THREE of
# the six (`ray_of_sickness`, `ray_of_enfeeblement`, `hold_person`) are now ALSO real,
# independently-learnable LEVELED_SPELL_IDS entries — same "promoted, sub-race grant is just one
# of two independent acquisition paths" pattern as the Elf lineage spells above (`class_list =
# ["WIZARD"]`). `poison_spray`/`chill_touch` were already promoted earlier (they're cantrips, see
# CANTRIP_IDS). `hellish_rebuke` is the one deliberate holdout — it's a reaction-toggle ability
# (`GameState._build_hellish_rebuke_ability()`), not a normal on-demand cast, so it doesn't fit the
# level-up-learn/slot-cast shape the other five use.
const TIEFLING_LEGACY_SPELL_IDS: Array[String] = ["poison_spray", "chill_touch", "ray_of_sickness", "hold_person", "ray_of_enfeeblement", "hellish_rebuke"]

# Gnome Gnomish Lineage-only spells (see scripts/entities/CLAUDE.md's "Gnome" section) — granted
# exclusively by GameState._grant_gnome_lineage_spells(), same "never in the level-up picker or any
# class's known-spell list" exclusion as ELF_LINEAGE_SPELL_IDS/TIEFLING_LEGACY_SPELL_IDS above. All
# three got a Scroll of <Spell> in the full spell-coverage pass (scripts/items/CLAUDE.md's
# "Scroll of <Spell>") despite never being learnable/slot-castable otherwise.
const GNOME_LINEAGE_SPELL_IDS: Array[String] = ["minor_illusion", "speak_with_animals", "mending"]

## Shared level-name formatter — "Cantrips" for level 0, "1st"/"2nd"/"3rd"/"Nth" otherwise.
## Reused by spellbook_overlay.gd's tab labels and debug_panel.gd's Give Spell level badge.
static func ordinal(lv: int) -> String:
	match lv:
		0: return "Cantrips"
		1: return "1st"
		2: return "2nd"
		3: return "3rd"
		_: return "%dth" % lv

static func get_spell(id: String) -> Spell:
	match id:
		"fire_bolt": return _fire_bolt()
		"ray_of_frost": return _ray_of_frost()
		"shocking_grasp": return _shocking_grasp()
		"toll_the_dead": return _toll_the_dead()
		"blade_ward": return _blade_ward()
		"thunderclap": return _thunderclap()
		"mind_sliver": return _mind_sliver()
		"light": return _light()
		"eldritch_blast": return _eldritch_blast()
		"magic_missile": return _magic_missile()
		"shield": return _shield()
		"mage_armor": return _mage_armor()
		"misty_step": return _misty_step()
		"fireball": return _fireball()
		"chromatic_orb": return _chromatic_orb()
		"burning_hands": return _burning_hands()
		"witch_bolt": return _witch_bolt()
		"expeditious_retreat": return _expeditious_retreat()
		"false_life": return _false_life()
		"fog_cloud": return _fog_cloud()
		"invisibility": return _invisibility()
		"faerie_fire": return _faerie_fire()
		"darkness": return _darkness()
		"detect_magic": return _detect_magic()
		"longstrider": return _longstrider()
		"pass_without_trace": return _pass_without_trace()
		"poison_spray": return _poison_spray()
		"chill_touch": return _chill_touch()
		"ray_of_sickness": return _ray_of_sickness()
		"hold_person": return _hold_person()
		"hideous_laughter": return _hideous_laughter()
		"ray_of_enfeeblement": return _ray_of_enfeeblement()
		"hellish_rebuke": return _hellish_rebuke()
		"minor_illusion": return _minor_illusion()
		"speak_with_animals": return _speak_with_animals()
		"mending": return _mending()
	return null

static func _fire_bolt() -> Spell:
	var s := Spell.new()
	s.spell_id = "fire_bolt"
	s.spell_name = "Fire Bolt"
	s.description = "Ranged spell attack, deals 1d10 Fire damage. Flammable terrain ignites."
	s.icon_path = "res://icons/spells/0/fire_bolt.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 6
	s.dice_count = 1
	s.dice_sides = 10
	s.damage_type = "Fire"
	s.cantrip_tier_scaling = true
	s.effect_id = ""
	s.class_list = ["WIZARD"]
	return s

static func _eldritch_blast() -> Spell:
	var s := Spell.new()
	s.spell_id = "eldritch_blast"
	s.spell_name = "Eldritch Blast"
	s.description = "Ranged spell attack, deals 1d10 Force damage."
	s.icon_path = "res://icons/spells/0/eldritch_blast.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 6
	s.dice_count = 1
	s.dice_sides = 10
	s.damage_type = "Force"
	s.multi_beam_scaling = true
	s.effect_id = ""
	s.class_list = ["WARLOCK"]
	return s

static func _ray_of_frost() -> Spell:
	var s := Spell.new()
	s.spell_id = "ray_of_frost"
	s.spell_name = "Ray of Frost"
	s.description = "Ranged spell attack, deals 1d8 Cold damage. On a hit, target makes a STR save or is frozen in place for a turn."
	s.icon_path = "res://icons/spells/0/ray_of_frost.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 3
	s.dice_count = 1
	s.dice_sides = 8
	s.damage_type = "Cold"
	s.cantrip_tier_scaling = true
	s.effect_id = "ray_of_frost"
	s.class_list = ["WIZARD"]
	return s

static func _shocking_grasp() -> Spell:
	var s := Spell.new()
	s.spell_id = "shocking_grasp"
	s.spell_name = "Shocking Grasp"
	s.description = "Melee spell attack, deals 1d8 Lightning damage. On a hit, target is Shocked."
	s.icon_path = "res://icons/spells/0/shocking_grasp.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 1
	s.dice_count = 1
	s.dice_sides = 8
	s.damage_type = "Lightning"
	s.cantrip_tier_scaling = true
	s.effect_id = "shocking_grasp"
	s.class_list = ["WIZARD"]
	return s

static func _toll_the_dead() -> Spell:
	var s := Spell.new()
	s.spell_id = "toll_the_dead"
	s.spell_name = "Toll the Dead"
	s.description = "WIS save or take 1d8 Necrotic damage — 1d12 instead if the target is already missing HP."
	s.icon_path = "res://icons/spells/0/toll_the_dead.png"
	s.school = "Necromancy"
	s.casting_time = "Action"
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "WIS"
	s.save_for_half = false
	s.dice_count = 1
	s.dice_sides = 8
	s.damage_type = "Necrotic"
	s.cantrip_tier_scaling = true
	s.effect_id = "toll_the_dead"
	s.class_list = ["WIZARD"]
	return s

static func _blade_ward() -> Spell:
	var s := Spell.new()
	s.spell_id = "blade_ward"
	s.spell_name = "Blade Ward"
	s.description = "Every attack roll against you rolls with -1d4. Breaks if you fail a CON check (DC = damage taken, min 10) when hit."
	s.icon_path = "res://icons/spells/0/blade_ward.png"
	s.school = "Abjuration"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "blade_ward"
	s.class_list = ["WIZARD"]
	return s

static func _thunderclap() -> Spell:
	var s := Spell.new()
	s.spell_id = "thunderclap"
	s.spell_name = "Thunderclap"
	s.description = "CON save or take 1d6 Thunder damage."
	s.icon_path = "res://icons/spells/0/thunderclap.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "CON"
	s.shape = "sphere"
	s.shape_size = 1
	s.dice_count = 1
	s.dice_sides = 6
	s.damage_type = "Thunder"
	s.cantrip_tier_scaling = true
	s.effect_id = "thunderclap"
	s.class_list = ["WIZARD"]
	return s

static func _mind_sliver() -> Spell:
	var s := Spell.new()
	s.spell_id = "mind_sliver"
	s.spell_name = "Mind Sliver"
	s.description = "INT save or take 1d6 Psychic damage and roll their next check with -1d4."
	s.icon_path = "res://icons/spells/0/mind_sliver.png"
	s.school = "Enchantment"
	s.casting_time = "Action"
	s.duration_turns = 1
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "INT"
	s.dice_count = 1
	s.dice_sides = 6
	s.damage_type = "Psychic"
	s.cantrip_tier_scaling = true
	s.effect_id = "mind_sliver"
	s.class_list = ["WIZARD"]
	return s

static func _light() -> Spell:
	var s := Spell.new()
	s.spell_id = "light"
	s.spell_name = "Light"
	s.description = "Lights a floor object, radius 4, random color, until your next rest, floor change, or recast. Only one Light active at a time."
	s.icon_path = "res://icons/spells/0/light.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.range_tiles = 1
	s.target_kind = Spell.TargetKind.TILE
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "light"
	s.class_list = ["WIZARD"]
	return s

static func _magic_missile() -> Spell:
	var s := Spell.new()
	s.spell_id = "magic_missile"
	s.spell_name = "Magic Missile"
	s.description = "Auto-hits, no attack roll. 3 darts, 1d4+1 Force damage each. Seeks the target through walls/grass/doors if a walkable path exists (chasms don't block it) — no path, no hit, no matter how close."
	s.icon_path = "res://icons/spells/1/arcane_missiles.png"  # icon pack names this spell's art "arcane_missiles"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.level = 1
	s.range_tiles = 6
	s.bypasses_los = true
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.AUTO_HIT
	s.damage_type = "Force"
	s.effect_id = "magic_missile"
	s.class_list = ["WIZARD"]   # real 5e list: Sorcerer/Wizard — not Ranger
	return s

static func _shield() -> Spell:
	var s := Spell.new()
	s.spell_id = "shield"
	s.spell_name = "Shield"
	s.description = "+5 AC — unlike RAW, this isn't a reaction, so it's live during your own turn too (e.g. before provoking an Opportunity Attack). If an enemy tries to cast Magic Missile at you, the missiles simply fail to strike but the caster's spell slot is still spent (Magic Missile itself always hits and ignores AC, but this codebase has no enemy Magic Missile caster yet to exercise that rule against)."
	s.icon_path = "res://icons/spells/1/shield.png"
	s.school = "Abjuration"
	s.casting_time = "Free"
	s.duration_turns = 1
	s.level = 1
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "shield"
	s.class_list = ["WIZARD"]   # real 5e list: Sorcerer/Wizard — not Ranger
	return s

static func _mage_armor() -> Spell:
	var s := Spell.new()
	s.spell_id = "mage_armor"
	s.spell_name = "Mage Armor"
	s.description = "Target's AC becomes 13 + DEX until they don armor or you finish a long rest."
	s.icon_path = "res://icons/spells/1/mage_armor.png"
	s.school = "Abjuration"
	s.casting_time = "Action"
	s.level = 1
	s.range_tiles = 1
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "mage_armor"
	s.class_list = ["WIZARD"]   # real 5e list: Sorcerer/Wizard — not Ranger
	return s

static func _misty_step() -> Spell:
	var s := Spell.new()
	s.spell_id = "misty_step"
	s.spell_name = "Misty Step"
	s.description = "Teleport to a visible tile."
	s.icon_path = "res://icons/spells/2/misty_step.png"
	s.school = "Conjuration"
	s.casting_time = "Action"
	s.level = 2
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.TILE
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "misty_step"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Sorcerer/Warlock/Wizard — not Ranger. Also in WARLOCK_SPELL_IDS — BUGFIX: class_list was missing WARLOCK despite the spell already being castable/learnable by one
	return s

static func _fireball() -> Spell:
	var s := Spell.new()
	s.spell_id = "fireball"
	s.spell_name = "Fireball"
	s.description = "DEX save or take 8d6 Fire damage, half on a save. Damages everything in the blast, friend or foe."
	s.icon_path = "res://icons/spells/3/fireball.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.level = 3
	s.range_tiles = 8
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "sphere"
	s.shape_size = 2
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "DEX"
	s.save_for_half = true
	s.dice_count = 8
	s.dice_sides = 6
	s.damage_type = "Fire"
	s.class_list = ["WIZARD"]   # real 5e list: Sorcerer/Wizard — not Ranger
	return s

static func _chromatic_orb() -> Spell:
	var s := Spell.new()
	s.spell_id = "chromatic_orb"
	s.spell_name = "Chromatic Orb"
	s.description = "Ranged spell attack, deals 3d8 damage of a random type (Acid/Cold/Fire/Lightning/Poison/Thunder). If 2+ of the 3 dice match, leaps to another visible target with a fresh attack of the same type."
	s.icon_path = "res://icons/spells/1/chromatic_orb.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.level = 1
	s.range_tiles = 5
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.ATTACK_ROLL
	s.dice_count = 3
	s.dice_sides = 8
	s.damage_type = ""   # rolled per-cast from SpellEffects.CHROMATIC_ORB_TYPES — see effect_id
	s.effect_id = "chromatic_orb"
	s.class_list = ["WIZARD"]   # real 5e/5.5e list: Sorcerer/Wizard — not Ranger
	return s

static func _burning_hands() -> Spell:
	var s := Spell.new()
	s.spell_id = "burning_hands"
	s.spell_name = "Burning Hands"
	s.description = "DEX save or take 3d6 Fire damage, half on a save. Flammable terrain in the cone ignites. Never harms you."
	s.icon_path = "res://icons/spells/1/burning_hands.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.level = 1
	s.range_tiles = 3   # display-only hint text; the actual click only supplies an aim direction
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "cone"
	s.shape_size = 3
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "DEX"
	s.save_for_half = true
	s.dice_count = 3
	s.dice_sides = 6
	s.damage_type = "Fire"
	s.effect_id = "burning_hands"
	s.class_list = ["WIZARD"]   # real 5e/5.5e list: Sorcerer/Wizard — not Ranger
	return s

static func _witch_bolt() -> Spell:
	var s := Spell.new()
	s.spell_id = "witch_bolt"
	s.spell_name = "Witch Bolt"
	s.description = "Ranged spell attack, deals 2d12 Lightning damage and begins Concentration. Target is Jolted while you concentrate."
	s.icon_path = "res://icons/spells/1/witch_bolt.png"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.ATTACK_ROLL
	s.dice_count = 2
	s.dice_sides = 12
	s.damage_type = "Lightning"
	s.effect_id = "witch_bolt"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e/5.5e list: Sorcerer/Warlock/Wizard — not Ranger. BUGFIX: class_list (and this comment) omitted Warlock even though the spell is already in WARLOCK_SPELL_IDS
	return s

# ── More 1st-level non-damage spells (Expeditious Retreat, False Life, Fog Cloud) ────────────
# Real 5e/5.5e class list for these three is Sorcerer/Warlock/Wizard, Sorcerer/Wizard, and
# Druid/Ranger/Sorcerer/Wizard respectively — Fog Cloud is the ONE genuinely on the Ranger list
# (both 2014 and 2024 rules); Expeditious Retreat/False Life stay Wizard-only, matching their real
# lists (direct owner correction — Ranger's spell access must respect each spell's actual RAW class
# list, not just "open everything up for consistency" — see LEVELED_SPELL_IDS/CLASS_SPELL_LISTS's
# note above and scripts/entities/CLAUDE.md's "Ranger class").

static func _expeditious_retreat() -> Spell:
	var s := Spell.new()
	s.spell_id = "expeditious_retreat"
	s.spell_name = "Expeditious Retreat"
	s.description = "Once per turn, your first move doesn't cost you your turn — you can still act (or move again) afterward."
	s.icon_path = "res://icons/spells/1/expeditious_retreat.png"
	s.school = "Transmutation"
	s.casting_time = "Free"
	s.duration_turns = 100
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "expeditious_retreat"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e/5.5e list: Sorcerer/Warlock/Wizard — not Ranger. BUGFIX: class_list was missing WARLOCK despite the spell already being in WARLOCK_SPELL_IDS
	return s

static func _false_life() -> Spell:
	var s := Spell.new()
	s.spell_id = "false_life"
	s.spell_name = "False Life"
	s.description = "Gain 2d4 + 4 Temporary HP."
	s.icon_path = "res://icons/spells/1/false_life.png"
	s.school = "Necromancy"
	s.casting_time = "Action"
	s.level = 1
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.dice_count = 2
	s.dice_sides = 4
	s.effect_id = "false_life"
	s.class_list = ["WIZARD"]   # real 5e/5.5e list: Sorcerer/Wizard — not Ranger
	return s

static func _fog_cloud() -> Spell:
	var s := Spell.new()
	s.spell_id = "fog_cloud"
	s.spell_name = "Fog Cloud"
	s.description = "Anyone inside — you or an enemy — is Blinded."
	s.icon_path = "res://icons/spells/1/fog_cloud.png"
	s.school = "Conjuration"
	s.casting_time = "Action"
	s.duration_turns = 100
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 6
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "sphere"
	s.shape_size = 2
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "fog_cloud"
	s.class_list = ["WIZARD", "RANGER"]   # real 5e/5.5e list: Druid/Ranger/Sorcerer/Wizard
	return s

# Real 5e class list is Bard/Druid/Sorcerer/Warlock/Wizard — this codebase only has a Wizard
# caster, so class_list stays ["WIZARD"] like every other spell (see LEVELED_SPELL_IDS's note).
# TargetKind.SELF + range_tiles=1 (touch), same "arm-then-any-click-confirms-on-yourself" pattern
# as Mage Armor — genuine touch-any-creature targeting doesn't exist in this engine (no ally-
# targetable touch spell has ever needed it, see Mage Armor's own "No ally-buff targeting exists"
# note), so both the Imp's own use and the player's are self-only in practice, matching how the
# owner described intended usage ("mostly will use it on themselves anyway").
static func _invisibility() -> Spell:
	var s := Spell.new()
	s.spell_id = "invisibility"
	s.spell_name = "Invisibility"
	s.description = "You turn invisible — enemies lose track of you, heading to your last known position instead. Ends early if you attack or cast. AoE spells and bumping into you still work."
	s.icon_path = "res://icons/spells/2/invisibility.png"
	s.school = "Illusion"
	s.casting_time = "Action"
	s.duration_turns = 100
	s.level = 2
	s.range_tiles = 1
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "invisibility"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Sorcerer/Warlock/Wizard. BUGFIX: class_list was missing WARLOCK despite the spell already being in WARLOCK_SPELL_IDS
	return s

# ── Elf lineage spells (Drow/High Elf/Wood Elf) — see scripts/entities/CLAUDE.md's "Elf" section
# and ELF_LINEAGE_SPELL_IDS's own comment above. class_list is left empty ("") rather than a real
# class name — these are never offered by any class's known-spell list or the level-up picker, only
# ever granted directly by GameState._grant_elf_lineage_spell().

static func _faerie_fire() -> Spell:
	var s := Spell.new()
	s.spell_id = "faerie_fire"
	s.spell_name = "Faerie Fire"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "cube"
	s.shape_size = 2
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "DEX"
	# Real 5e class list: Bard/Druid — not represented in class_list since neither is playable here.
	s.description = "DEX save or is Outlined. No damage. Drow lineage spell."
	s.icon_path = "res://icons/spells/1/faerie_fire.png"
	s.effect_id = "faerie_fire"
	s.class_list = ["WIZARD"]
	return s

static func _darkness() -> Spell:
	var s := Spell.new()
	s.spell_id = "darkness"
	s.spell_name = "Darkness"
	s.school = "Evocation"
	s.casting_time = "Action"
	s.duration_turns = 100
	s.is_concentration = true
	s.level = 2
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "sphere"
	s.shape_size = 2
	s.resolution = Spell.Resolution.AUTO_HIT
	# Real 5e/5.5e class list: Sorcerer/Warlock/Wizard.
	s.description = "Anyone inside, you or an enemy, is Blinded. Can target a floor object instead of a bare point — the darkness follows it. Snuffs out an overlapping Light cantrip."
	s.icon_path = "res://icons/spells/2/darkness.png"
	s.effect_id = "darkness"
	s.class_list = ["WARLOCK", "WIZARD"]   # BUGFIX: class_list was missing WARLOCK despite the spell already being in WARLOCK_SPELL_IDS and its own comment above naming Warlock
	return s

static func _detect_magic() -> Spell:
	var s := Spell.new()
	s.spell_id = "detect_magic"
	s.spell_name = "Detect Magic"
	s.school = "Divination"
	s.casting_time = "Action"
	s.duration_turns = 100
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 0
	s.shape = "sphere"
	s.shape_size = 3
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.is_ritual = true
	# Real 5e/5.5e class list: Bard/Cleric/Druid/Paladin/Ranger/Sorcerer/Warlock/Wizard.
	s.description = "Nearby magic items on the floor show as a pulsing blue dot. Castable as a Ritual — free unless an enemy is hunting you."
	s.icon_path = "res://icons/spells/1/detect_magic.png"
	s.effect_id = "detect_magic"
	s.class_list = ["WIZARD"]
	return s

static func _longstrider() -> Spell:
	var s := Spell.new()
	s.spell_id = "longstrider"
	s.spell_name = "Longstrider"
	s.school = "Transmutation"
	s.casting_time = "Action"
	s.duration_turns = 600
	s.level = 1
	s.range_tiles = 1
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	# Real 5e/5.5e class list: Bard/Druid/Ranger/Wizard.
	s.description = "Your speed increases by 1/3 — once per turn, your first move doesn't cost your turn."
	s.icon_path = "res://icons/spells/1/longstrider.png"
	s.effect_id = "longstrider"
	s.class_list = ["WIZARD"]
	return s

static func _pass_without_trace() -> Spell:
	var s := Spell.new()
	s.spell_id = "pass_without_trace"
	s.spell_name = "Pass Without Trace"
	s.school = "Abjuration"
	s.casting_time = "Action"
	s.duration_turns = 600
	s.is_concentration = true
	s.level = 2
	s.range_tiles = 0
	s.shape = "sphere"
	s.shape_size = 3
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	# Real 5e/5.5e class list: Druid/Ranger (Druid isn't a playable class in this engine yet, so
	# Ranger is the only class that can learn it today).
	s.description = "You get +10 to your Stealth-vs-Passive-Perception roll. Also the Wood Elf lineage's own free grant."
	s.icon_path = "res://icons/spells/2/pass_without_trace.png"
	s.effect_id = "pass_without_trace"
	s.class_list = ["RANGER"]
	return s

# ── Tiefling Fiendish Legacy spells (Abyssal/Chthonic/Infernal) — see
# scripts/entities/CLAUDE.md's "Tiefling" section and TIEFLING_LEGACY_SPELL_IDS's own comment
# above. class_list is left empty, same convention as the Elf lineage spells above — these are
# never offered by any class's known-spell list or the level-up picker, only ever granted directly
# by GameState._grant_tiefling_legacy_spell().

static func _poison_spray() -> Spell:
	var s := Spell.new()
	s.spell_id = "poison_spray"
	s.spell_name = "Poison Spray"
	s.school = "Conjuration"
	s.casting_time = "Action"
	s.range_tiles = 2
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.ATTACK_ROLL
	s.dice_count = 1
	s.dice_sides = 12
	s.damage_type = "Poison"
	s.cantrip_tier_scaling = true
	s.description = "Ranged spell attack, deals 1d12 Poison damage. Also an Abyssal Tiefling lineage cantrip."
	s.icon_path = "res://icons/spells/0/poison_spray.png"
	s.effect_id = ""
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Druid/Sorcerer/Warlock/Wizard. Also WARLOCK_STARTER_CANTRIP_IDS — BUGFIX: class_list was missing WARLOCK despite being one of Warlock's own starter cantrip choices
	return s

static func _chill_touch() -> Spell:
	var s := Spell.new()
	s.spell_id = "chill_touch"
	s.spell_name = "Chill Touch"
	s.school = "Necromancy"
	s.casting_time = "Action"
	s.duration_turns = 1
	s.range_tiles = 1
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.ATTACK_ROLL
	s.dice_count = 1
	s.dice_sides = 10
	s.damage_type = "Necrotic"
	s.cantrip_tier_scaling = true
	s.description = "Melee spell attack, deals 1d10 Necrotic damage. On a hit, target can't regenerate any HP. Also a Chthonic Tiefling lineage cantrip."
	s.icon_path = "res://icons/spells/0/chill_touch.png"
	s.effect_id = "chill_touch"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Sorcerer/Warlock/Wizard (Sorcerer left off, not a playable class here). Also WARLOCK_STARTER_CANTRIP_IDS — BUGFIX: class_list was missing WARLOCK despite being one of Warlock's own starter cantrip choices
	return s

static func _ray_of_sickness() -> Spell:
	var s := Spell.new()
	s.spell_id = "ray_of_sickness"
	s.spell_name = "Ray of Sickness"
	s.school = "Necromancy"
	s.casting_time = "Action"
	s.duration_turns = 2
	s.level = 1
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.ATTACK_ROLL
	s.dice_count = 2
	s.dice_sides = 8
	s.damage_type = "Poison"
	s.description = "Ranged spell attack, deals 2d8 Poison damage. On a hit, target is also Poisoned (no save). Abyssal Tiefling lineage spell."
	s.icon_path = "res://icons/spells/1/ray_of_sickness.png"
	s.effect_id = "ray_of_sickness"
	s.class_list = ["WIZARD"]
	return s

static func _hold_person() -> Spell:
	var s := Spell.new()
	s.spell_id = "hold_person"
	s.spell_name = "Hold Person"
	s.school = "Enchantment"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.level = 2
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "WIS"
	s.dice_count = 0
	s.description = "WIS save or is Paralyzed. Repeats the save each turn, ending early on a success. Abyssal Tiefling lineage spell."
	s.icon_path = "res://icons/spells/2/hold_person.png"
	s.effect_id = "hold_person"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Bard/Cleric/Druid/Sorcerer/Warlock/Wizard. BUGFIX: class_list was missing WARLOCK despite the spell already being in WARLOCK_SPELL_IDS
	return s

static func _hideous_laughter() -> Spell:
	var s := Spell.new()
	s.spell_id = "hideous_laughter"
	s.spell_name = "Tasha's Hideous Laughter"
	s.school = "Enchantment"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.level = 1
	s.range_tiles = 2
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "WIS"
	s.dice_count = 0
	# Upcast (1 additional target per spell slot level above 1st) is not implemented — this
	# codebase has no upcasting at all (see "Wizard leveled spells"'s own "no upcasting"
	# permanent simplification), so casting always affects a single target regardless of which
	# slot level it's cast at.
	s.description = "WIS save or is knocked Prone and Incapacitated. Repeats the save at the end of its turns, and again with Advantage whenever it takes damage (multiple hits from the same spell each get their own throw). A success ends the Incapacitated half; Prone lingers until it stands up normally. Upcast: +1 target per spell slot level above 1st (not yet implemented — always single-target)."
	s.icon_path = "res://icons/spells/1/hideous_laughter.png"
	s.effect_id = "hideous_laughter"
	s.class_list = ["WARLOCK", "WIZARD"]
	return s

static func _ray_of_enfeeblement() -> Spell:
	var s := Spell.new()
	s.spell_id = "ray_of_enfeeblement"
	s.spell_name = "Ray of Enfeeblement"
	s.school = "Necromancy"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.is_concentration = true
	s.level = 2
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "CON"
	s.dice_count = 0
	s.description = "CON save: success — Disadvantage on next attack only. Failure — Disadvantage on STR checks, -1d8 damage rolls. Repeats each turn, ends on a success. Chthonic Tiefling lineage spell."
	s.icon_path = "res://icons/spells/2/ray_of_enfeeblement.png"
	s.effect_id = "ray_of_enfeeblement"
	s.class_list = ["WARLOCK", "WIZARD"]   # real 5e list: Warlock/Wizard. BUGFIX: class_list was missing WARLOCK despite the spell already being in WARLOCK_SPELL_IDS
	return s

static func _hellish_rebuke() -> Spell:
	var s := Spell.new()
	s.spell_id = "hellish_rebuke"
	s.spell_name = "Hellish Rebuke"
	s.school = "Evocation"
	# RAW casting time is a Reaction — this engine only models Action/Free, so it's approximated
	# as Free (an armed toggle, not costing the real turn) rather than either real option.
	s.casting_time = "Free"
	s.level = 1
	s.range_tiles = 3
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "DEX"
	s.save_for_half = true
	s.dice_count = 2
	s.dice_sides = 10
	s.damage_type = "Fire"
	s.description = "Toggle to arm — the next enemy that damages you takes 2d10 Fire (DEX save for half). Infernal Tiefling lineage spell."
	s.icon_path = "res://icons/spells/1/hellish_rebuke.png"
	s.effect_id = "hellish_rebuke"
	s.class_list = []
	return s

# ── Gnome Gnomish Lineage spells (Forest/Rock) — see scripts/entities/CLAUDE.md's "Gnome" section
# and GNOME_LINEAGE_SPELL_IDS's own comment above. class_list is left empty, same convention as the
# Elf/Tiefling lineage spells above — these are never offered by any class's known-spell list or
# the level-up picker, only ever granted directly by GameState._grant_gnome_lineage_spells(). All
# three are cantrips (level 0) — Gnomish Lineage's own scarcity comes from the proficiency-bonus-
# per-long-rest free-cast counter (Stats.gnome_lineage_free_casts_remaining), not from spell level.

static func _minor_illusion() -> Spell:
	var s := Spell.new()
	s.spell_id = "minor_illusion"
	s.spell_name = "Minor Illusion"
	s.school = "Illusion"
	s.casting_time = "Action"
	s.duration_turns = 10
	s.level = 0
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.description = "A minor sound-or-image distraction grants +5 to your Stealth-vs-Passive-Perception roll. Forest Gnome lineage cantrip."
	s.icon_path = "res://icons/spells/0/minor_illusion.png"
	s.effect_id = "minor_illusion"
	s.class_list = []
	return s

static func _speak_with_animals() -> Spell:
	var s := Spell.new()
	s.spell_id = "speak_with_animals"
	s.spell_name = "Speak with Animals"
	s.school = "Divination"
	s.casting_time = "Action"
	s.level = 0
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.description = "Communicate with beasts for a short while — flavor only, no gameplay effect. Forest Gnome lineage cantrip."
	s.icon_path = "res://icons/spells/0/speak_with_animals.png"
	s.effect_id = "speak_with_animals"
	s.class_list = []
	return s

static func _mending() -> Spell:
	var s := Spell.new()
	s.spell_id = "mending"
	s.spell_name = "Mending"
	s.school = "Transmutation"
	s.casting_time = "Action"
	s.level = 0
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.description = "Repairs your equipped Main Hand weapon's durability back to full. Rock Gnome lineage cantrip."
	s.icon_path = "res://icons/spells/0/mending.png"
	s.effect_id = "mending"
	s.class_list = []
	return s
