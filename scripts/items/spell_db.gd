class_name SpellDb
extends RefCounted

# Static factory for spell definitions — same "no .tres files" convention as Talent/SpriteFrames.
# Only the three starting Wizard cantrips exist so far; see docs/architecture/spellcasting-design.md
# for the full framework this is a deliberately-trimmed slice of.

const CANTRIP_IDS: Array[String] = ["fire_bolt", "ray_of_frost", "shocking_grasp"]

static func get_spell(id: String) -> Spell:
	match id:
		"fire_bolt": return _fire_bolt()
		"ray_of_frost": return _ray_of_frost()
		"shocking_grasp": return _shocking_grasp()
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
