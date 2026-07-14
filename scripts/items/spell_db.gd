class_name SpellDb
extends RefCounted

# Static factory for spell definitions — same "no .tres files" convention as Talent/SpriteFrames.
# Cantrips are the framework's original slice (docs/architecture/spellcasting-design.md); the 4
# leveled spells below are the worked examples from
# docs/architecture/leveled-spells-and-slots-plan.md §7 (Burning Hands/cone AoE was cut from the
# doc's original 5-spell list to keep SpellShapes to sphere-only for this pass — see that doc's
# §7 caveat and CLAUDE.md). Full class spell lists remain future content work.

const CANTRIP_IDS: Array[String] = ["fire_bolt", "ray_of_frost", "shocking_grasp"]
const LEVELED_SPELL_IDS: Array[String] = ["magic_missile", "shield", "misty_step", "fireball"]
const CLASS_SPELL_LISTS: Dictionary = {"WIZARD": LEVELED_SPELL_IDS}   # cantrips excluded — never offered by the level-up picker

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
		"magic_missile": return _magic_missile()
		"shield": return _shield()
		"misty_step": return _misty_step()
		"fireball": return _fireball()
	return null

static func _fire_bolt() -> Spell:
	var s := Spell.new()
	s.spell_id = "fire_bolt"
	s.spell_name = "Fire Bolt"
	s.description = "Hurl a mote of fire at a target within 12 tiles. 1d10 Fire damage; flammable terrain ignites."
	s.icon_path = "res://icons/spells/fire_bolt.png"
	s.school = "Evocation"
	s.range_tiles = 12
	s.dice_count = 1
	s.dice_sides = 10
	s.damage_type = "Fire"
	s.cantrip_tier_scaling = true
	s.effect_id = ""
	s.class_list = ["WIZARD"]
	return s

static func _ray_of_frost() -> Spell:
	var s := Spell.new()
	s.spell_id = "ray_of_frost"
	s.spell_name = "Ray of Frost"
	s.description = "A ray of freezing air at a target within 6 tiles. 1d8 Cold damage; on a hit the target makes a STR save or its feet freeze, unable to move for a turn."
	s.icon_path = "res://icons/spells/ray_of_frost.png"
	s.school = "Evocation"
	s.range_tiles = 6
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
	s.description = "Touch a target with a jolt of lightning. 1d8 Lightning damage; on a hit the target is Shocked, blocking its next Opportunity Attack exposure."
	s.icon_path = "res://icons/spells/shocking_grasp.png"
	s.school = "Evocation"
	s.range_tiles = 1
	s.dice_count = 1
	s.dice_sides = 8
	s.damage_type = "Lightning"
	s.cantrip_tier_scaling = true
	s.effect_id = "shocking_grasp"
	s.class_list = ["WIZARD"]
	return s

static func _magic_missile() -> Spell:
	var s := Spell.new()
	s.spell_id = "magic_missile"
	s.spell_name = "Magic Missile"
	s.description = "3 darts of magical force strike unerringly — always hits, no attack roll. 1d4+1 Force each. +1 dart per slot level above 1st. Range: your full field of view."
	s.icon_path = "res://icons/spells/magic_missile.png"
	s.school = "Evocation"
	s.level = 1
	s.range_is_fov = true
	s.target_kind = Spell.TargetKind.ENEMY
	s.resolution = Spell.Resolution.AUTO_HIT
	s.damage_type = "Force"
	s.effect_id = "magic_missile"
	s.class_list = ["WIZARD"]
	return s

static func _shield() -> Spell:
	var s := Spell.new()
	s.spell_id = "shield"
	s.spell_name = "Shield"
	s.description = "+5 AC until the start of your next turn. leveled-spells-and-slots-plan.md §7: shipped as a same-turn manual cast, not a reaction (the reaction broker is out of scope for this pass)."
	s.icon_path = "res://icons/spells/shield.png"
	s.school = "Abjuration"
	s.level = 1
	s.range_tiles = 0
	s.target_kind = Spell.TargetKind.SELF
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "shield"
	s.class_list = ["WIZARD"]
	return s

static func _misty_step() -> Spell:
	var s := Spell.new()
	s.spell_id = "misty_step"
	s.spell_name = "Misty Step"
	s.description = "Teleport to a visible tile within 6 tiles in a puff of silver mist."
	s.icon_path = "res://icons/spells/misty_step.png"
	s.school = "Conjuration"
	s.level = 2
	s.range_tiles = 6
	s.target_kind = Spell.TargetKind.TILE
	s.resolution = Spell.Resolution.AUTO_HIT
	s.effect_id = "misty_step"
	s.class_list = ["WIZARD"]
	return s

static func _fireball() -> Spell:
	var s := Spell.new()
	s.spell_id = "fireball"
	s.spell_name = "Fireball"
	s.description = "A roaring sphere of fire (radius 2 tiles) erupts at a point you choose. 8d6 Fire damage; DEX save for half. +1d6 per slot level above 3rd. Damages everything in the blast, friend or foe."
	s.icon_path = "res://icons/spells/fireball.png"
	s.school = "Evocation"
	s.level = 3
	s.range_tiles = 6
	s.target_kind = Spell.TargetKind.TILE
	s.shape = "sphere"
	s.shape_size = 2
	s.resolution = Spell.Resolution.SAVE
	s.save_stat = "DEX"
	s.save_for_half = true
	s.dice_count = 8
	s.dice_sides = 6
	s.damage_type = "Fire"
	s.upcast_dice_per_level = 1
	s.class_list = ["WIZARD"]
	return s
