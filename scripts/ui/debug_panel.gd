extends CanvasLayer

const PANEL_W:    int = 280
const PANEL_H:    int = 358
const FLOOR_SW:   int = 234
const FLOOR_SH:   int = 96
const ITEMS_SW:   int = 390
const ITEMS_SH:   int = 370
const SPAWN_SW:   int = 320
const SPAWN_SH:   int = 380
const TALENT_SW:  int = 310
const TALENT_SH:  int = 380
const SPELLS_SW:  int = 340
const SPELLS_SH:  int = 340

const WEAPONS_PATH := "res://sprites/weapons/"
const ITEMS_PATH   := "res://sprites/items/"

const ALL_ITEMS: Array = [
	{"name": "Health Potion",   "type": 2, "src": "items",   "icon": "Potions/Health/HealthPotionMedium.png", "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Restores 2d4+CON HP", "heal_dice": 2, "heal_sides": 4, "gold": 30},
	{"name": "Strength Potion", "type": 2, "src": "items",   "icon": "Potions/Mana/ManaPotionMedium.png",     "bonus_dmg": 0, "heal": 0,   "str_bonus": 2, "desc": "+2 ATK (permanent)", "gold": 80},
	{"name": "Ration",          "type": 4, "src": "items",   "icon": "Food/MeatCooked.png",                   "bonus_dmg": 0, "heal": 0, "food_value": 50, "str_bonus": 0, "desc": "Required for a long rest.", "gold": 15},
	{"name": "Cooked Meat",     "type": 4, "src": "items",   "icon": "Food/MeatCooked.png",                   "bonus_dmg": 0, "heal": 0, "food_value": 75, "str_bonus": 0, "desc": "Roasted over a fire trap. Required for a long rest."},
	{"name": "Mystery Meat",    "type": 4, "src": "items",   "icon": "Food/Meat.png",                         "bonus_dmg": 0, "heal": 0, "food_value": 25, "str_bonus": 0, "desc": "Required for a long rest.", "gold": 8},
	{"name": "Rotten Meat",     "type": 4, "src": "items",   "icon": "Food/Meat.png",                         "bonus_dmg": 0, "heal": 0, "food_value": 10, "str_bonus": 0, "desc": "Throw into fire to cook into Cooked Meat."},
	{"name": "Thief Tools",      "type": 7, "src": "items",   "icon": "Misc/KeyIron.png",                         "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Disarm traps",               "qty": 3, "gold": 25},
	{"name": "Shield",           "type": 1, "src": "items",   "icon": "Shields/Shield1.png",                      "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Off-hand. +2 AC. Requires shield proficiency; can't be worn with a two-handed Main Hand weapon, and blocks spellcasting while equipped. Equip/unequip takes 1 turn.", "bonus_ac": 2, "is_shield": true, "gold": 40},
	{"name": "Short Bow",        "type": 0, "src": "items",   "icon": "Weapons/BowArrow.png",                     "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "is_ranged": true, "range": 4, "category": "Simple", "die_min": 1, "die_max": 6, "dmg_type": "Piercing", "mastery": "Vex", "ammo": "Arrow", "gold": 50},
	{"name": "Heavy Crossbow",   "type": 0, "src": "items",   "icon": "Weapons/BowArrowGold.png",                 "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "is_ranged": true, "range": 4, "category": "Martial", "dmg_type": "Piercing", "die_min": 1, "die_max": 10, "mastery": "Push", "ammo": "Bolt", "heavy": true, "two_handed": true, "gold": 120},
	{"name": "Longbow",          "type": 0, "src": "items",   "icon": "Weapons/Bow.png",                          "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "is_ranged": true, "range": 5, "category": "Martial", "dmg_type": "Piercing", "die_min": 1, "die_max": 8, "mastery": "Slow", "ammo": "Arrow", "heavy": true, "two_handed": true},
	{"name": "Arrow",            "type": 7, "src": "weapons", "icon": "weapon_arrow.png",                         "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Ammunition for the Short Bow and Longbow.", "qty": 6, "gold": 1},
	{"name": "Bolt",             "type": 7, "src": "weapons", "icon": "weapon_arrow.png",                         "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Ammunition for the Heavy Crossbow.", "qty": 6},
	{"name": "Empty Bottle",    "type": 7, "src": "items",   "icon": "Materials/BottleSmall.png",                "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Fill from water or mud"},
	{"name": "Bottle of Water", "type": 7, "src": "items",   "icon": "Materials/BottleMedium.png",               "bonus_dmg": 0, "heal": 0,  "str_bonus": 0, "desc": "Fresh water. Not required for anything yet."},
	{"name": "Bottle of Mud",   "type": 7, "src": "items",   "icon": "Materials/BottleSmall.png",               "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "Foul mud. Maybe useful."},
	{"name": "Greataxe",        "type": 0, "src": "weapons", "icon": "weapon_double_axe.png",                   "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "two_handed": true, "heavy": true, "die_min": 1, "die_max": 12, "dmg_type": "Slashing", "mastery": "Cleave", "category": "Martial"},
	{"name": "Rapier",          "type": 0, "src": "weapons", "icon": "weapon_duel_sword.png",                   "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "die_min": 1, "die_max": 8, "dmg_type": "Piercing", "mastery": "Vex", "category": "Martial", "finesse": true},
	{"name": "Greatsword",      "type": 0, "src": "weapons", "icon": "weapon_knight_sword.png",                "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "two_handed": true, "heavy": true, "die_min": 2, "die_max": 12, "dmg_type": "Slashing", "mastery": "Graze", "category": "Martial"},
	{"name": "Glaive",          "type": 0, "src": "weapons", "icon": "weapon_spear.png",                       "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "two_handed": true, "heavy": true, "reach": true, "die_min": 1, "die_max": 10, "dmg_type": "Slashing", "mastery": "Graze", "category": "Martial"},
	{"name": "Maul",            "type": 0, "src": "weapons", "icon": "weapon_big_hammer.png",                  "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "two_handed": true, "heavy": true, "die_min": 2, "die_max": 12, "dmg_type": "Bludgeoning", "mastery": "Topple", "category": "Martial"},
	{"name": "Quarterstaff",    "type": 0, "src": "weapons", "icon": "weapon_green_magic_staff.png",           "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "versatile": true, "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "dmg_type": "Bludgeoning", "mastery": "Topple", "category": "Simple"},
	{"name": "Spear",           "type": 0, "src": "weapons", "icon": "weapon_spear.png",                       "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "versatile": true, "die_min": 1, "die_max": 6, "vmin": 1, "vmax": 8, "dmg_type": "Piercing", "mastery": "Sap", "category": "Simple", "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Handaxe",         "type": 0, "src": "weapons", "icon": "weapon_throwing_axe.png",               "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "light": true, "die_min": 1, "die_max": 6, "dmg_type": "Slashing", "mastery": "Vex", "category": "Simple", "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Dagger",          "type": 0, "src": "weapons", "icon": "weapon_knife.png",                      "bonus_dmg": 0, "heal": 0,   "str_bonus": 0, "desc": "", "finesse": true, "light": true, "die_min": 1, "die_max": 4, "dmg_type": "Piercing", "mastery": "Nick", "category": "Simple", "thrown": true, "range": 3, "uses_max": 5},
	{"name": "Scroll of Fire Bolt",     "type": 3, "src": "spells", "icon": "fire_bolt.png",      "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Fire Bolt once, then it crumbles to dust.", "scroll_spell": "fire_bolt", "gold": 25},
	{"name": "Scroll of Ray of Frost",  "type": 3, "src": "spells", "icon": "ray_of_frost.png",   "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Ray of Frost once, then it crumbles to dust.", "scroll_spell": "ray_of_frost", "gold": 25},
	{"name": "Scroll of Shocking Grasp","type": 3, "src": "spells", "icon": "shocking_grasp.png", "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Shocking Grasp once, then it crumbles to dust.", "scroll_spell": "shocking_grasp", "gold": 25},
	{"name": "Scroll of Magic Missile", "type": 3, "src": "spells", "icon": "magic_missile.png",  "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Magic Missile once, then it crumbles to dust.", "scroll_spell": "magic_missile", "gold": 60},
	{"name": "Scroll of Shield",        "type": 3, "src": "spells", "icon": "shield.png",         "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Shield once, then it crumbles to dust.", "scroll_spell": "shield", "gold": 60},
	{"name": "Scroll of Mage Armor",    "type": 3, "src": "spells", "icon": "mage_armor.png",     "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Mage Armor once, then it crumbles to dust.", "scroll_spell": "mage_armor", "gold": 60},
	{"name": "Scroll of Misty Step",    "type": 3, "src": "spells", "icon": "misty_step.png",     "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Misty Step once, then it crumbles to dust.", "scroll_spell": "misty_step", "gold": 100},
	{"name": "Scroll of Fireball",      "type": 3, "src": "spells", "icon": "fireball.png",       "bonus_dmg": 0, "heal": 0, "str_bonus": 0, "desc": "Reading this casts Fireball once, then it crumbles to dust.", "scroll_spell": "fireball", "gold": 180},
]

var _main_panel:    Panel
var _floor_sub:     Panel
var _items_sub:     Panel
var _spawn_sub:     Panel
var _talent_sub:    Panel
var _spells_sub:    Panel
var _talent_vbox:   VBoxContainer
var _talent_rank_labels: Dictionary = {}   # talent_id -> Label
var _god_check:     CheckBox
var _mute_btn:      Button

func _ready() -> void:
	layer = 25
	_build_main_panel()
	_build_floor_sub()
	_build_items_sub()
	_build_spawn_sub()
	_build_talent_sub()
	_build_spells_sub()
	call_deferred("_reposition")

# ── Positioning ───────────────────────────────────────────────────────────────

func _reposition() -> void:
	var vp_w: float = get_viewport().get_visible_rect().size.x
	_main_panel.position  = Vector2(vp_w - PANEL_W - 4.0, 4.0)
	_floor_sub.position   = Vector2(vp_w - PANEL_W - FLOOR_SW - 8.0, 4.0)
	_items_sub.position   = Vector2(vp_w - PANEL_W - ITEMS_SW - 8.0, 4.0)
	_spawn_sub.position   = Vector2(vp_w - PANEL_W - SPAWN_SW - 8.0, 4.0)
	_talent_sub.position  = Vector2(vp_w - PANEL_W - TALENT_SW - 8.0, 4.0)
	_spells_sub.position  = Vector2(vp_w - PANEL_W - SPELLS_SW - 8.0, 4.0)

# ── Panel builders ────────────────────────────────────────────────────────────

func _build_main_panel() -> void:
	_main_panel = Panel.new()
	_main_panel.visible = true
	_main_panel.size = Vector2(PANEL_W, PANEL_H)
	_main_panel.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_main_panel, Color(0.07, 0.06, 0.06, 0.96), Color(0.85, 0.20, 0.20))
	add_child(_main_panel)

	_add_label(_main_panel, "DEBUG  [F3]", 8, 6, 12, Color(1.0, 0.35, 0.35))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 24.0)
	sep.size = Vector2(PANEL_W - 12.0, 4.0)
	_main_panel.add_child(sep)

	# God Mode (activates invincible + noclip + see all + god-mode visibility)
	_god_check = CheckBox.new()
	_god_check.text = "God Mode"
	_god_check.position = Vector2(6.0, 30.0)
	_god_check.size = Vector2(PANEL_W - 12.0, 32.0)
	_god_check.add_theme_font_size_override("font_size", 13)
	_god_check.add_theme_color_override("font_color", Color(1.0, 0.8, 0.2))
	_god_check.focus_mode = Control.FOCUS_NONE
	_god_check.toggled.connect(_on_god_mode_toggled)
	_main_panel.add_child(_god_check)

	var sep2 := HSeparator.new()
	sep2.position = Vector2(6.0, 66.0)
	sep2.size = Vector2(PANEL_W - 12.0, 4.0)
	_main_panel.add_child(sep2)

	var jump_btn := _make_btn("Jump to Floor...", Color(0.25, 0.60, 1.0))
	jump_btn.position = Vector2(6.0, 72.0)
	jump_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	jump_btn.pressed.connect(_on_jump_pressed)
	_main_panel.add_child(jump_btn)

	var items_btn := _make_btn("Give Item...", Color(0.35, 0.80, 0.35))
	items_btn.position = Vector2(6.0, 108.0)
	items_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	items_btn.pressed.connect(_on_items_pressed)
	_main_panel.add_child(items_btn)

	var spawn_btn := _make_btn("Spawn Enemy...", Color(0.80, 0.35, 0.70))
	spawn_btn.position = Vector2(6.0, 144.0)
	spawn_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	spawn_btn.pressed.connect(_on_spawn_pressed)
	_main_panel.add_child(spawn_btn)

	var lvlup_btn := _make_btn("Level Up", Color(1.0, 0.75, 0.10))
	lvlup_btn.position = Vector2(6.0, 180.0)
	lvlup_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	lvlup_btn.pressed.connect(_on_level_up_pressed)
	_main_panel.add_child(lvlup_btn)

	var talent_btn := _make_btn("Talents...", Color(0.30, 0.75, 0.30))
	talent_btn.position = Vector2(6.0, 215.0)
	talent_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	talent_btn.pressed.connect(_on_talents_pressed)
	_main_panel.add_child(talent_btn)

	var gold_btn := _make_btn("Give 100 Gold", Color(1.0, 0.84, 0.30))
	gold_btn.position = Vector2(6.0, 250.0)
	gold_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	gold_btn.pressed.connect(_on_give_gold_pressed)
	_main_panel.add_child(gold_btn)

	var spells_btn := _make_btn("Give Spell...", Color(0.65, 0.45, 0.95))
	spells_btn.position = Vector2(6.0, 286.0)
	spells_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	spells_btn.pressed.connect(_on_spells_pressed)
	_main_panel.add_child(spells_btn)

	# Mute — mirrors the HUD's top-right MuteButton (scenes/ui/hud.tscn), just easier to find.
	_mute_btn = _make_btn("", Color(0.55, 0.75, 1.0))
	_mute_btn.position = Vector2(6.0, 322.0)
	_mute_btn.size = Vector2(PANEL_W - 12.0, 30.0)
	_mute_btn.pressed.connect(_on_mute_pressed)
	_main_panel.add_child(_mute_btn)
	AudioManager.mute_changed.connect(_on_mute_changed)
	_on_mute_changed(AudioManager.is_muted)

func _build_floor_sub() -> void:
	_floor_sub = Panel.new()
	_floor_sub.visible = false
	_floor_sub.size = Vector2(FLOOR_SW, FLOOR_SH)
	_floor_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_floor_sub, Color(0.07, 0.07, 0.10, 0.97), Color(0.25, 0.60, 1.0))
	add_child(_floor_sub)

	_add_label(_floor_sub, "Jump to Floor", 8, 5, 10, Color(0.50, 0.80, 1.0))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(FLOOR_SW - 12.0, 4.0)
	_floor_sub.add_child(sep)

	for i: int in 10:
		var fl: int = i + 1
		var is_boss: bool = fl % 5 == 0
		var col: Color = Color(1.0, 0.55, 0.10) if is_boss else Color(0.40, 0.75, 0.40)
		var lbl: String = "F%d%s" % [fl, "★" if is_boss else ""]
		var btn := _make_btn(lbl, col)
		btn.position = Vector2(6.0 + (i % 5) * 44.0, 28.0 + (i / 5) * 30.0)
		btn.size = Vector2(40.0, 24.0)
		btn.pressed.connect(_on_floor_selected.bind(fl))
		_floor_sub.add_child(btn)

func _build_items_sub() -> void:
	_items_sub = Panel.new()
	_items_sub.visible = false
	_items_sub.size = Vector2(ITEMS_SW, ITEMS_SH)
	_items_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_items_sub, Color(0.07, 0.07, 0.10, 0.97), Color(0.30, 0.85, 0.30))
	add_child(_items_sub)

	_add_label(_items_sub, "Item Browser  —  click Give to receive ×1", 8, 5, 10, Color(0.40, 1.0, 0.40))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(ITEMS_SW - 12.0, 4.0)
	_items_sub.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(ITEMS_SW - 12.0, ITEMS_SH - 38.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_items_sub.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	for d: Dictionary in ALL_ITEMS:
		vbox.add_child(_make_item_row(d))

func _build_spawn_sub() -> void:
	_spawn_sub = Panel.new()
	_spawn_sub.visible = false
	_spawn_sub.size = Vector2(SPAWN_SW, SPAWN_SH)
	_spawn_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_spawn_sub, Color(0.07, 0.05, 0.09, 0.97), Color(0.80, 0.35, 0.70))
	add_child(_spawn_sub)

	_add_label(_spawn_sub, "Spawn Enemy  —  spawns adjacent to player", 8, 5, 10, Color(0.90, 0.60, 0.90))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(SPAWN_SW - 12.0, 4.0)
	_spawn_sub.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(SPAWN_SW - 12.0, SPAWN_SH - 38.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_spawn_sub.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	# Regular enemies
	var enemy_pool: Array = DungeonFloorData.ENEMY_POOL
	var boss_pool: Array  = DungeonFloorData.BOSS_POOL
	for entry: Dictionary in enemy_pool:
		vbox.add_child(_make_spawn_row(entry, false))
	for entry: Dictionary in boss_pool:
		vbox.add_child(_make_spawn_row(entry, true))

func _build_talent_sub() -> void:
	_talent_sub = Panel.new()
	_talent_sub.visible = false
	_talent_sub.size = Vector2(TALENT_SW, TALENT_SH)
	_talent_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_talent_sub, Color(0.05, 0.09, 0.06, 0.97), Color(0.25, 0.70, 0.30))
	add_child(_talent_sub)

	_add_label(_talent_sub, "Talent Debug", 8, 5, 10, Color(0.40, 1.0, 0.45))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(TALENT_SW - 12.0, 4.0)
	_talent_sub.add_child(sep)

	# Clicking "Talents…" auto-unlocks all tiers and gives 99pts — no sub-buttons needed here.

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(TALENT_SW - 12.0, TALENT_SH - 36.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_talent_sub.add_child(scroll)

	_talent_vbox = VBoxContainer.new()
	_talent_vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_talent_vbox.add_theme_constant_override("separation", 2)
	scroll.add_child(_talent_vbox)

func _build_spells_sub() -> void:
	_spells_sub = Panel.new()
	_spells_sub.visible = false
	_spells_sub.size = Vector2(SPELLS_SW, SPELLS_SH)
	_spells_sub.mouse_filter = Control.MOUSE_FILTER_STOP
	_style_panel(_spells_sub, Color(0.09, 0.06, 0.12, 0.97), Color(0.65, 0.45, 0.95))
	add_child(_spells_sub)

	_add_label(_spells_sub, "Spellbook — click Give to learn/prepare", 8, 5, 10, Color(0.80, 0.65, 1.0))

	var sep := HSeparator.new()
	sep.position = Vector2(6.0, 22.0)
	sep.size = Vector2(SPELLS_SW - 12.0, 4.0)
	_spells_sub.add_child(sep)

	var scroll := ScrollContainer.new()
	scroll.position = Vector2(6.0, 30.0)
	scroll.size = Vector2(SPELLS_SW - 12.0, SPELLS_SH - 38.0)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	_spells_sub.add_child(scroll)

	var vbox := VBoxContainer.new()
	vbox.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	vbox.add_theme_constant_override("separation", 3)
	scroll.add_child(vbox)

	for spell_id: String in (SpellDb.CANTRIP_IDS + SpellDb.LEVELED_SPELL_IDS):
		vbox.add_child(_make_spell_row(spell_id))

func _rebuild_talent_rows() -> void:
	for child: Node in _talent_vbox.get_children():
		child.queue_free()
	_talent_rank_labels.clear()
	if GameState._class_talents.is_empty():
		var lbl := Label.new()
		lbl.text = "No class selected — pick a class first."
		lbl.add_theme_font_size_override("font_size", 10)
		lbl.add_theme_color_override("font_color", Color(0.45, 0.45, 0.45))
		_talent_vbox.add_child(lbl)
		return
	var last_tier: int = -1
	for t: Talent in GameState._class_talents:
		if t.tier != last_tier:
			last_tier = t.tier
			var header := Label.new()
			header.text = "── TIER %d ──" % t.tier
			header.add_theme_font_size_override("font_size", 10)
			header.add_theme_color_override("font_color", Color(0.78, 0.55, 0.22))
			var margin := MarginContainer.new()
			margin.add_theme_constant_override("margin_top", 4)
			margin.add_theme_constant_override("margin_left", 4)
			margin.add_child(header)
			_talent_vbox.add_child(margin)
		_talent_vbox.add_child(_make_talent_row(t))

func _make_talent_row(t: Talent) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 4)
	row.custom_minimum_size = Vector2(0.0, 28.0)

	var name_lbl := Label.new()
	name_lbl.text = t.talent_name
	name_lbl.add_theme_font_size_override("font_size", 11)
	name_lbl.add_theme_color_override("font_color", Color(0.85, 0.82, 0.75))
	name_lbl.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	name_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	row.add_child(name_lbl)

	var rank_lbl := Label.new()
	rank_lbl.text = "%d/%d" % [GameState.get_talent_rank(t.talent_id), t.max_rank]
	rank_lbl.add_theme_font_size_override("font_size", 11)
	rank_lbl.add_theme_color_override("font_color", Color(0.40, 0.85, 0.50))
	rank_lbl.custom_minimum_size = Vector2(36.0, 0.0)
	rank_lbl.horizontal_alignment = HORIZONTAL_ALIGNMENT_CENTER
	rank_lbl.vertical_alignment = VERTICAL_ALIGNMENT_CENTER
	_talent_rank_labels[t.talent_id] = rank_lbl
	row.add_child(rank_lbl)

	var tid: String = t.talent_id
	var minus_btn := _make_btn("-", Color(0.80, 0.25, 0.25))
	minus_btn.custom_minimum_size = Vector2(28.0, 24.0)
	minus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	minus_btn.pressed.connect(_on_talent_minus.bind(tid))
	row.add_child(minus_btn)

	var plus_btn := _make_btn("+", Color(0.25, 0.70, 0.30))
	plus_btn.custom_minimum_size = Vector2(28.0, 24.0)
	plus_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	plus_btn.pressed.connect(_on_talent_plus.bind(tid))
	row.add_child(plus_btn)

	var margin := MarginContainer.new()
	margin.add_theme_constant_override("margin_left", 4)
	margin.add_theme_constant_override("margin_right", 4)
	margin.add_child(row)
	return margin

# ── Row builders ──────────────────────────────────────────────────────────────

func _make_item_row(d: Dictionary) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, 38.0)

	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	var icon_path: String = ""
	match d["src"]:
		"weapons": icon_path = WEAPONS_PATH + d["icon"]
		"items":   icon_path = ITEMS_PATH   + d["icon"]
	if icon_path != "" and ResourceLoader.exists(icon_path):
		icon.texture = load(icon_path)
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = d["name"]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.95, 0.90, 0.70))
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = d["desc"]
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	info.add_child(desc_lbl)

	var give_btn := _make_btn("Give", Color(0.40, 0.80, 0.40))
	give_btn.custom_minimum_size = Vector2(54.0, 0.0)
	give_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	give_btn.pressed.connect(_on_give_item.bind(d))
	row.add_child(give_btn)

	return row

func _make_spell_row(spell_id: String) -> Control:
	var spell: Spell = SpellDb.get_spell(spell_id)
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, 38.0)

	var icon := TextureRect.new()
	icon.stretch_mode = TextureRect.STRETCH_KEEP_ASPECT_CENTERED
	icon.texture_filter = CanvasItem.TEXTURE_FILTER_NEAREST
	icon.custom_minimum_size = Vector2(34.0, 34.0)
	icon.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	if spell != null and spell.icon_path != "" and ResourceLoader.exists(spell.icon_path):
		icon.texture = load(spell.icon_path)
	row.add_child(icon)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(info)

	var name_lbl := Label.new()
	name_lbl.text = "%s  [%s]" % [spell.spell_name if spell != null else spell_id, SpellDb.ordinal(spell.level if spell != null else 0)]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", Color(0.90, 0.80, 1.0))
	info.add_child(name_lbl)

	var desc_lbl := Label.new()
	desc_lbl.text = spell.description if spell != null else ""
	desc_lbl.add_theme_font_size_override("font_size", 8)
	desc_lbl.add_theme_color_override("font_color", Color(0.55, 0.55, 0.60))
	desc_lbl.clip_text = true
	desc_lbl.custom_minimum_size = Vector2(SPELLS_SW - 130.0, 0.0)
	info.add_child(desc_lbl)

	var give_btn := _make_btn("Give", Color(0.65, 0.45, 0.95))
	give_btn.custom_minimum_size = Vector2(54.0, 0.0)
	give_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	give_btn.pressed.connect(_on_give_spell.bind(spell_id))
	row.add_child(give_btn)

	return row

func _make_spawn_row(d: Dictionary, is_boss: bool) -> Control:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.custom_minimum_size = Vector2(0.0, 34.0)

	var info := VBoxContainer.new()
	info.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	info.size_flags_vertical   = Control.SIZE_SHRINK_CENTER
	row.add_child(info)

	var name_color: Color = Color(1.0, 0.55, 0.25) if is_boss else Color(0.95, 0.80, 0.90)
	var name_lbl := Label.new()
	var floors_str: String = "F%d" % d.get("floor", 0) if is_boss else "F%d–%d" % [d.get("floor_min", 1), d.get("floor_max", 10)]
	name_lbl.text = "%s  [%s]" % [d.get("display_name", "?"), floors_str]
	name_lbl.add_theme_font_size_override("font_size", 10)
	name_lbl.add_theme_color_override("font_color", name_color)
	info.add_child(name_lbl)

	var stat_lbl := Label.new()
	stat_lbl.text = "HP %d  Dmg %d–%d  AC %d" % [d.get("hp", 0), d.get("dmg_min", 0), d.get("dmg_max", 0), d.get("ac", 10)]
	stat_lbl.add_theme_font_size_override("font_size", 8)
	stat_lbl.add_theme_color_override("font_color", Color(0.55, 0.50, 0.58))
	info.add_child(stat_lbl)

	var spawn_col: Color = Color(1.0, 0.40, 0.20) if is_boss else Color(0.80, 0.35, 0.70)
	var spawn_btn := _make_btn("Spawn", spawn_col)
	spawn_btn.custom_minimum_size = Vector2(58.0, 0.0)
	spawn_btn.size_flags_vertical = Control.SIZE_SHRINK_CENTER
	spawn_btn.pressed.connect(_on_spawn_enemy.bind(d))
	row.add_child(spawn_btn)

	return row

# ── Helpers ───────────────────────────────────────────────────────────────────

func _style_panel(p: Panel, bg: Color, border: Color) -> void:
	var s := StyleBoxFlat.new()
	s.bg_color = bg
	s.set_border_width_all(2)
	s.border_color = border
	s.set_corner_radius_all(4)
	p.add_theme_stylebox_override("panel", s)

func _add_label(parent: Control, text: String, x: float, y: float,
				font_size: int, color: Color) -> void:
	var lbl := Label.new()
	lbl.text = text
	lbl.position = Vector2(x, y)
	lbl.add_theme_font_size_override("font_size", font_size)
	lbl.add_theme_color_override("font_color", color)
	lbl.mouse_filter = Control.MOUSE_FILTER_IGNORE
	parent.add_child(lbl)

func _make_btn(text: String, col: Color) -> Button:
	var btn := Button.new()
	btn.text = text
	btn.add_theme_font_size_override("font_size", 12)
	var n := StyleBoxFlat.new()
	n.bg_color = col * 0.28
	n.set_border_width_all(1)
	n.border_color = col * 0.70
	n.set_corner_radius_all(3)
	var h := StyleBoxFlat.new()
	h.bg_color = col * 0.48
	h.set_border_width_all(1)
	h.border_color = col
	h.set_corner_radius_all(3)
	btn.add_theme_stylebox_override("normal", n)
	btn.add_theme_stylebox_override("hover",  h)
	btn.add_theme_color_override("font_color", Color.WHITE)
	btn.focus_mode = Control.FOCUS_NONE
	return btn

# ── Input ─────────────────────────────────────────────────────────────────────

func _input(event: InputEvent) -> void:
	if not (event is InputEventKey):
		return
	var key := event as InputEventKey
	if key.pressed and not key.echo and key.physical_keycode == KEY_F3:
		get_viewport().set_input_as_handled()
		_main_panel.visible = not _main_panel.visible
		if not _main_panel.visible:
			_floor_sub.visible = false
			_items_sub.visible = false
			_spawn_sub.visible = false
			_talent_sub.visible = false
			_spells_sub.visible = false

# ── Callbacks ─────────────────────────────────────────────────────────────────

func _on_god_mode_toggled(pressed: bool) -> void:
	GameState.god_mode    = pressed
	GameState.invincible  = pressed
	GameState.noclip      = pressed
	GameState.debug_see_all.emit(pressed)
	GameState.game_log("[color=%s][DEBUG] God Mode %s[/color]" % [
		"gold" if pressed else "gray", "ON — all-knowing, untouchable" if pressed else "OFF"])

func _on_jump_pressed() -> void:
	_floor_sub.visible = not _floor_sub.visible
	if _floor_sub.visible:
		_items_sub.visible = false
		_spawn_sub.visible = false
		_spells_sub.visible = false

func _on_items_pressed() -> void:
	_items_sub.visible = not _items_sub.visible
	if _items_sub.visible:
		_floor_sub.visible = false
		_spawn_sub.visible = false
		_spells_sub.visible = false

func _on_spawn_pressed() -> void:
	_spawn_sub.visible = not _spawn_sub.visible
	if _spawn_sub.visible:
		_floor_sub.visible = false
		_items_sub.visible = false
		_spells_sub.visible = false

func _on_spells_pressed() -> void:
	_spells_sub.visible = not _spells_sub.visible
	if _spells_sub.visible:
		_floor_sub.visible = false
		_items_sub.visible = false
		_spawn_sub.visible = false

func _on_level_up_pressed() -> void:
	GameState.debug_level_up()
	GameState.game_log("[color=gold][DEBUG] Level Up! Now level %d.[/color]" % GameState.player_stats.character_level)

func _on_talents_pressed() -> void:
	# Auto: unlock all tiers + give 99 pts so the debug panel is immediately usable
	GameState.unlock_tier2()
	GameState.talent_points[1] = 99
	GameState.talent_points[2] = 99
	GameState.talent_points_changed.emit(GameState.talent_points_available)
	_talent_sub.visible = not _talent_sub.visible
	if _talent_sub.visible:
		_rebuild_talent_rows()
		_floor_sub.visible = false
		_items_sub.visible = false
		_spawn_sub.visible = false
		_spells_sub.visible = false

func _on_give_99_points() -> void:
	GameState.talent_points[1] = 99
	GameState.talent_points[2] = 99
	GameState.talent_points_changed.emit(GameState.talent_points_available)
	GameState.game_log("[color=green][DEBUG] 99 talent points granted to each tier.[/color]")

func _on_unlock_all_tiers() -> void:
	GameState.unlock_tier2()
	_rebuild_talent_rows()
	GameState.game_log("[color=purple][DEBUG] All talent tiers unlocked.[/color]")

func _on_talent_plus(id: String) -> void:
	var talent: Talent = GameState._find_talent(id)
	if talent != null:
		if GameState.talent_points.get(talent.tier, 0) <= 0:
			GameState.talent_points[talent.tier] = 1
	GameState.invest_talent(id)
	_refresh_rank_label(id)

func _on_talent_minus(id: String) -> void:
	GameState.debug_set_talent_rank(id, GameState.get_talent_rank(id) - 1)
	_refresh_rank_label(id)

func _refresh_rank_label(id: String) -> void:
	if not _talent_rank_labels.has(id):
		return
	var t: Talent = GameState._find_talent(id)
	_talent_rank_labels[id].text = "%d/%d" % [GameState.get_talent_rank(id), t.max_rank if t != null else 3]

func _on_floor_selected(floor_num: int) -> void:
	_floor_sub.visible = false
	GameState.game_log("[color=cyan][DEBUG] Jumping to floor %d…[/color]" % floor_num)
	GameState.debug_jump_to_floor(floor_num)

func _on_spawn_enemy(type_data: Dictionary) -> void:
	var dungeon_floor: Node = get_tree().get_first_node_in_group("dungeon_floor")
	if dungeon_floor == null:
		GameState.game_log("[color=red][DEBUG] No dungeon floor found[/color]")
		return
	dungeon_floor.debug_spawn_enemy(type_data)

func _on_give_gold_pressed() -> void:
	GameState.add_gold(100)
	GameState.game_log("[color=gold][DEBUG] +100 gold (now %d).[/color]" % GameState.gold)

func _on_mute_pressed() -> void:
	AudioManager.toggle_mute()

func _on_mute_changed(muted: bool) -> void:
	_mute_btn.text = "🔇 Unmute" if muted else "🔊 Mute"

func _on_give_spell(spell_id: String) -> void:
	if GameState.player_stats.caster == null:
		GameState.game_log("[color=red][DEBUG] Current class has no spellcasting.[/color]")
		return
	var spell: Spell = SpellDb.get_spell(spell_id)
	if spell == null:
		return
	if spell.level == 0:
		GameState.choose_cantrip(spell_id)   # idempotent — already has()-guarded
	else:
		if not GameState.player_stats.caster.known_spells.has(spell_id):
			GameState.learn_spell(spell_id)
		GameState.set_spell_prepared(spell_id, true)   # silently no-ops past prepared_max() cap
	GameState.game_log("[color=lime][DEBUG] Given: %s[/color]" % spell.spell_name)

func _on_give_item(d: Dictionary) -> void:
	var item := Item.new()
	item.item_name   = d["name"]
	item.item_type   = d["type"] as Item.Type
	item.bonus_damage = d["bonus_dmg"]
	item.heal_amount        = d["heal"]
	item.food_value         = d.get("food_value", 0)
	item.gold_value         = d.get("gold", 0)
	item.heal_dice_count    = d.get("heal_dice", 0)
	item.heal_dice_sides    = d.get("heal_sides", 0)
	item.str_bonus          = d.get("str_bonus", 0)
	item.is_ranged          = d.get("is_ranged", false)
	item.range              = d.get("range", 0)
	item.consumes_on_ranged = d.get("consumes", false)
	item.is_two_handed      = d.get("two_handed", false)
	item.is_heavy_armor     = d.get("heavy_armor", false)
	item.bonus_ac           = d.get("bonus_ac", 0)
	item.is_shield          = d.get("is_shield", false)
	item.is_heavy           = d.get("heavy", false)
	item.is_finesse         = d.get("finesse", false)
	item.is_light           = d.get("light", false)
	item.is_reach           = d.get("reach", false)
	item.is_versatile       = d.get("versatile", false)
	item.versatile_die_min  = d.get("vmin", 0)
	item.versatile_die_max  = d.get("vmax", 0)
	item.is_thrown          = d.get("thrown", false)
	item.uses_max           = d.get("uses_max", 0)
	item.uses_remaining     = item.uses_max
	item.damage_die_min     = d.get("die_min", 0)
	item.damage_die_max     = d.get("die_max", 0)
	item.damage_type        = d.get("dmg_type", "")
	item.weapon_mastery     = d.get("mastery", "")
	item.weapon_category    = d.get("category", "")
	item.ammo_item_name     = d.get("ammo", "")
	item.taught_spell_id    = d.get("taught_spell", "")
	item.scroll_spell_id    = d.get("scroll_spell", "")
	item.description = d["desc"]
	match d["src"]:
		"weapons": item.icon_path = WEAPONS_PATH + d["icon"]
		"items":   item.icon_path = ITEMS_PATH   + d["icon"]
		"spells":  item.icon_path = "res://icons/spells/" + d["icon"]
	item.quantity = d.get("qty", 1)
	if not GameState.add_item(item):
		GameState.game_log("[color=red][DEBUG] Inventory full — cannot give %s[/color]" % d["name"])
	else:
		GameState.game_log("[color=lime][DEBUG] Given: %s[/color]" % d["name"])
