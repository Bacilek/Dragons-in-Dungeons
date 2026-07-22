class_name ItemInteractions
extends RefCounted

# Which non-Equip interactions an item currently offers for the RMB menu (see root CLAUDE.md's
# maintenance rule / scripts/ui/CLAUDE.md's "Item interaction menu" section). Equip is never
# included here — it's LMB's exclusive job (see hud.gd/inventory_overlay.gd). Food is never
# passed through this helper at all; both call sites special-case it and keep their prior
# unconditional-throw / use_item() behavior untouched.

const LABELS := {
	"light": "Light",
	"read": "Read",
	"learn": "Learn",
	"drink": "Drink",
	"prime": "Prime",
	"throw": "Throw",
}

static func get_available_interactions(item: Item) -> Array[String]:
	var out: Array[String] = []
	if item.is_torch and not item.torch_lit and not item.torch_burnt:
		out.append("light")
	if item.item_type == Item.Type.SCROLL and (item.scroll_spell_id != "" or item.taught_spell_id != ""):
		out.append("read")
	if item.item_type == Item.Type.SCROLL and GameState.can_learn_scroll_spell(item):
		out.append("learn")
	if item.item_type == Item.Type.POTION:
		out.append("drink")
	if item.item_type == Item.Type.TOOL:
		out.append("prime")
	out.append("throw")
	return out

# True when resolving this interaction arms a follow-up world click (throw target tile, tool
# prime's adjacent-tile interaction, or a scroll that casts a spell) — callers in an overlay
# context should close the overlay first so the player lands in "aim at the world" mode.
static func needs_world_targeting(id: String, item: Item) -> bool:
	match id:
		"throw", "prime":
			return true
		"read":
			return item.scroll_spell_id != ""
		_:
			return false
