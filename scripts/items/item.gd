class_name Item
extends Resource

enum Type { WEAPON, ARMOR, POTION, SCROLL, FOOD, GOLD, KEY, TOOL }

@export var item_name: String = ""
@export var item_type: Type = Type.POTION
@export var quantity: int = 1
@export var description: String = ""
@export var icon_path: String = ""
@export var bonus_damage: int = 0
@export var bonus_ac: int = 0
@export var heal_amount: int = 0
# FOOD items only: value sacrificed toward GameState.LONG_REST_FOOD_COST at a long rest.
@export var food_value: int = 0
# Base shop price in gold (0 = unpriced / not for sale). For Type.GOLD items, the pile size —
# picked up into GameState.gold, never into the inventory (see PlayerActions.check_pickup()).
@export var gold_value: int = 0
@export var str_bonus: int = 0
@export var floor_min: int = 1
@export var floor_max: int = 10
@export var is_ranged: bool = false
@export var range: int = 0
@export var consumes_on_ranged: bool = false
@export var is_two_handed: bool = false
@export var is_heavy_armor: bool = false  # ends Barbarian Rage immediately on equip
# Shield: an ARMOR-type item that routes to the "hand2" (Off-hand) slot instead of "armor" —
# see GameState.equip()/can_equip_shield(). Requires Stats.proficient_shields, can't be equipped
# alongside a two-handed Main Hand weapon, blocks spellcasting while equipped, and costs 1 turn
# to equip/unequip. bonus_ac (usually 2) applies the same way any other equipment slot's AC bonus
# does — via the generic per-slot loop in GameState.recalculate_stats().
@export var is_shield: bool = false
@export var is_heavy: bool = false        # Heavy: attacking with STR < 13 imposes Disadvantage
@export var is_versatile: bool = false    # Versatile: World Tree's Branching Strike keys off it alongside is_heavy; also toggles two-handed grip (see versatile_die_min/max)
# Versatile weapons only: damage die used while gripped two-handed (toggled via Main Hand slot
# click in inventory_overlay.gd, which also flips is_two_handed). 0 = not versatile / no alt die.
@export var versatile_die_min: int = 0
@export var versatile_die_max: int = 0
@export var is_finesse: bool = false      # Finesse: attack/damage modifier uses max(STR, DEX) instead of STR — see CombatMath.finesse_modifier()
@export var is_light: bool = false        # Light: pairs with a Light Main Hand weapon in the Off-hand slot to attack with both — see player.gd._try_offhand_attack()
@export var is_reach: bool = false        # Reach: +1 tile melee range — see CombatMath.melee_reach()
# Torch: click-to-light while equipped (Main Hand or Off-hand) — see GameState.light_torch(). Once
# lit, burns for 100 turns (torch_turns_remaining), granting +1 FOV in either hand and +1d4 Fire
# damage on the standard melee swing only while wielded in Main Hand. Reaching 0 permanently sets
# torch_burnt = true and renames the item "Burnt Torch" — it can never be relit.
@export var is_torch: bool = false
@export var torch_lit: bool = false
@export var torch_burnt: bool = false
@export var torch_turns_remaining: int = 0
# If > 0, overrides Stats.base_min/max_damage when this weapon is equipped (e.g. 1d12 Greataxe).
# recalculate_stats() in GameState applies these instead of base_min/max_damage when non-zero.
@export var damage_die_min: int = 0
@export var damage_die_max: int = 0
# Damage type categories (for reference — no enum, just documentation):
#   Physical:  "Slashing", "Piercing", "Bludgeoning"
#   Elemental: "Fire", "Cold", "Acid", "Poison", "Thunder", "Lightning"
#   Magical:   "Force", "Necrotic", "Psychic", "Radiant"
# "" = unknown/unset.
@export var damage_type: String = ""
@export var heal_dice_count: int = 0   # if > 0, roll N dice of heal_dice_sides + CON instead of heal_amount
@export var heal_dice_sides: int = 0
# Weapon mastery — one signature effect per weapon, keyed by name (e.g. "Cleave").
# "" = no mastery. WeaponProperties.MASTERY_GLOSSARY holds the tooltip description.
@export var weapon_mastery: String = ""
# Weapon category — "Simple" or "Martial" ("" = n/a, e.g. non-weapon items). Determines
# whether Stats.proficient_simple_weapons/proficient_martial_weapons grants the attack
# roll's proficiency bonus (see Stats and player.gd._weapon_prof_bonus()).
@export var weapon_category: String = ""
# Name of the Item this ranged weapon consumes as ammo per shot (e.g. "Arrow"). "" = no named
# ammo required (falls back to consumes_on_ranged on the weapon's own stack, e.g. the legacy
# Throwing-Dagger pattern, or infinite ammo). Long range for ranged weapons is NOT a per-item
# field — it's always the player's live FOV (DungeonFloor.FOV_RADIUS), only the "normal" range
# (`range` above) differs per weapon; see player.gd._is_ranged_target_in_range().
@export var ammo_item_name: String = ""
# Thrown: can be primed via RMB (same UX as quickbar food throw) then thrown at a tile with LMB.
# Uses the wielder's MELEE attack modifier (STR, or max(STR,DEX) if is_finesse) even though it's
# thrown — not a separate ranged stat. `range` (above) is the thrown weapon's normal range; beyond
# that but within the player's live FOV the throw still works but rolls with Disadvantage — same
# normal/FOV-long-range convention as ranged weapons (see PlayerRanged.is_ranged_target_in_range()).
@export var is_thrown: bool = false
# Thrown weapons only: durability. uses_remaining starts at uses_max and decrements by 1 per throw
# (0 on a natural-20 critical hit, 2 on a natural-1 critical fumble). Reaching 0 breaks the weapon
# (GameState.remove_item()). Not consumed by ordinary melee attacks — only by throwing.
@export var uses_max: int = 0
@export var uses_remaining: int = 0
# Thrown weapons only: per-unit durability when `quantity > 1` (same-named thrown weapons of
# DIFFERENT durability now merge into one stack instead of separate piles). Sorted ascending —
# index 0 (lowest uses_remaining, most-damaged unit) is always "on top": it's what's displayed
# (mirrored into uses_remaining) and what gets thrown/equipped first. Empty = not yet
# materialized (fresh single unit, or a stack where every unit shares uses_remaining) — see
# get_stack_uses(). Populated/kept in sync by GameState._merge_into_stack()/_split_one_unit().
@export var stack_uses: Array[int] = []
# SCROLL items only: spell_id taught into the reader's spellbook on use (classic D&D
# scroll-copying — see docs/architecture/leveled-spells-and-slots-plan.md §4.2). "" = not a spell
# scroll — every pre-existing SCROLL item stays a no-op.
@export var taught_spell_id: String = ""
# SCROLL items only: spell_id baked into this scroll for a SINGLE one-shot cast (distinct from
# taught_spell_id above — reading this scroll does NOT teach the spell permanently, it just casts
# it once then crumbles, always at the spell's base level — no upcasting, no slot spent). "" = not
# a cast-scroll. Castable by ANY class regardless of Stats.caster — see SpellEffects' caster-
# optional attack-bonus/save-DC helpers, which use the reader's own spellcasting ability if they
# have one (a caster class), or fall back to proficiency_bonus + INT modifier otherwise.
@export var scroll_spell_id: String = ""
# Magic item attunement (D&D-style, max GameState.MAX_ATTUNED_ITEMS at once). A magic item can
# still be equipped/carried freely with requires_attunement=true and is_attuned=false — it just
# sits inert: GameState.recalculate_stats() skips its bonus_ac/bonus_damage contribution via
# _item_bonus_active() until is_attuned flips true. Attuning/unattuning is only ever done through
# scripts/ui/attunement_picker.gd (GameState.attune_item()/unattune_item()), itself only reachable
# from the long-rest hub (scripts/ui/mastery_reselect_prompt.gd) — see scripts/items/CLAUDE.md's
# "Attunement" section. requires_attunement=false (the default) means the item's bonuses always
# apply, exactly like before this system existed — every pre-existing item is unaffected.
@export var requires_attunement: bool = false
@export var is_attuned: bool = false

# Returns one durability value per unit in the stack (size == quantity). Falls back to repeating
# `uses_remaining` when stack_uses hasn't been materialized (fresh item, or every unit identical).
func get_stack_uses() -> Array:
	if stack_uses.size() == quantity and quantity > 0:
		return stack_uses.duplicate()
	var arr: Array = []
	for _i: int in maxi(quantity, 1):
		arr.append(uses_remaining)
	return arr

func get_display_name() -> String:
	if quantity > 1:
		return "%s ×%d" % [item_name, quantity]
	return item_name

# ── Save/load (Phase A — docs/architecture/SAVE_LOAD_ARCHITECTURE.md §4.4) ──────
# Every field above is a flat primitive, so the pair below is a mechanical listing.
# When adding a new Item field, add it to BOTH functions (and see scripts/items/CLAUDE.md).

func to_dict() -> Dictionary:
	return {
		"item_name": item_name,
		"item_type": int(item_type),
		"quantity": quantity,
		"description": description,
		"icon_path": icon_path,
		"bonus_damage": bonus_damage,
		"bonus_ac": bonus_ac,
		"heal_amount": heal_amount,
		"food_value": food_value,
		"gold_value": gold_value,
		"str_bonus": str_bonus,
		"floor_min": floor_min,
		"floor_max": floor_max,
		"is_ranged": is_ranged,
		"range": range,
		"consumes_on_ranged": consumes_on_ranged,
		"is_two_handed": is_two_handed,
		"is_heavy_armor": is_heavy_armor,
		"is_shield": is_shield,
		"is_heavy": is_heavy,
		"is_versatile": is_versatile,
		"versatile_die_min": versatile_die_min,
		"versatile_die_max": versatile_die_max,
		"is_finesse": is_finesse,
		"is_light": is_light,
		"is_reach": is_reach,
		"is_torch": is_torch,
		"torch_lit": torch_lit,
		"torch_burnt": torch_burnt,
		"torch_turns_remaining": torch_turns_remaining,
		"damage_die_min": damage_die_min,
		"damage_die_max": damage_die_max,
		"damage_type": damage_type,
		"heal_dice_count": heal_dice_count,
		"heal_dice_sides": heal_dice_sides,
		"weapon_mastery": weapon_mastery,
		"weapon_category": weapon_category,
		"ammo_item_name": ammo_item_name,
		"is_thrown": is_thrown,
		"uses_max": uses_max,
		"uses_remaining": uses_remaining,
		"stack_uses": stack_uses,
		"taught_spell_id": taught_spell_id,
		"scroll_spell_id": scroll_spell_id,
		"requires_attunement": requires_attunement,
		"is_attuned": is_attuned,
	}

static func from_dict(d: Dictionary) -> Item:
	var it := Item.new()
	it.item_name = String(d.get("item_name", ""))
	it.item_type = int(d.get("item_type", Type.POTION)) as Type
	it.quantity = int(d.get("quantity", 1))
	it.description = String(d.get("description", ""))
	it.icon_path = String(d.get("icon_path", ""))
	it.bonus_damage = int(d.get("bonus_damage", 0))
	it.bonus_ac = int(d.get("bonus_ac", 0))
	it.heal_amount = int(d.get("heal_amount", 0))
	it.food_value = int(d.get("food_value", 0))
	it.gold_value = int(d.get("gold_value", 0))
	it.str_bonus = int(d.get("str_bonus", 0))
	it.floor_min = int(d.get("floor_min", 1))
	it.floor_max = int(d.get("floor_max", 10))
	it.is_ranged = bool(d.get("is_ranged", false))
	it.range = int(d.get("range", 0))
	it.consumes_on_ranged = bool(d.get("consumes_on_ranged", false))
	it.is_two_handed = bool(d.get("is_two_handed", false))
	it.is_heavy_armor = bool(d.get("is_heavy_armor", false))
	it.is_shield = bool(d.get("is_shield", false))
	it.is_heavy = bool(d.get("is_heavy", false))
	it.is_versatile = bool(d.get("is_versatile", false))
	it.versatile_die_min = int(d.get("versatile_die_min", 0))
	it.versatile_die_max = int(d.get("versatile_die_max", 0))
	it.is_finesse = bool(d.get("is_finesse", false))
	it.is_light = bool(d.get("is_light", false))
	it.is_reach = bool(d.get("is_reach", false))
	it.is_torch = bool(d.get("is_torch", false))
	it.torch_lit = bool(d.get("torch_lit", false))
	it.torch_burnt = bool(d.get("torch_burnt", false))
	it.torch_turns_remaining = int(d.get("torch_turns_remaining", 0))
	it.damage_die_min = int(d.get("damage_die_min", 0))
	it.damage_die_max = int(d.get("damage_die_max", 0))
	it.damage_type = String(d.get("damage_type", ""))
	it.heal_dice_count = int(d.get("heal_dice_count", 0))
	it.heal_dice_sides = int(d.get("heal_dice_sides", 0))
	it.weapon_mastery = String(d.get("weapon_mastery", ""))
	it.weapon_category = String(d.get("weapon_category", ""))
	it.ammo_item_name = String(d.get("ammo_item_name", ""))
	it.is_thrown = bool(d.get("is_thrown", false))
	it.uses_max = int(d.get("uses_max", 0))
	it.uses_remaining = int(d.get("uses_remaining", 0))
	var su: Array = d.get("stack_uses", [])
	var su_typed: Array[int] = []
	for v: Variant in su:
		su_typed.append(int(v))
	it.stack_uses = su_typed
	it.taught_spell_id = String(d.get("taught_spell_id", ""))
	it.scroll_spell_id = String(d.get("scroll_spell_id", ""))
	it.requires_attunement = bool(d.get("requires_attunement", false))
	it.is_attuned = bool(d.get("is_attuned", false))
	return it
