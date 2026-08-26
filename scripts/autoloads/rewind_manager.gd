extends Node

# RewindManager — Phase 1 of the "undo 1 turn" feature (docs/architecture plan, see root
# CLAUDE.md's maintenance-rule pointer). Captures an in-memory snapshot at the start of every
# REAL player turn and can restore the most recent one on demand. Never touches disk (unrelated
# to SaveManager's floor-entry checkpoint, which is a much coarser, curated snapshot).
#
# Phase 1+2+3, all implemented: player position/Stats/TurnManager round state (plus the scattered
# per-turn transient fields on Player/its composition children), every live Enemy/Companion
# (positions/HP/AI state, respawning ones that died this turn, despawning ones summoned mid-turn —
# see DungeonFloor.capture_rewind_enemies()/restore_rewind_enemies()), and floor prop state
# (traps/dispensers/doors/barrels/webs/burning grass/floor items/pending thrown-weapon drops —
# see DungeonFloor.capture_rewind_props()/restore_rewind_props()). One documented gap: a
# trap/dispenser disarmed or looted during the rewound turn is not respawned — see that function's
# own doc comment. **Deliberately NOT restored: `Rng`'s gameplay stream position** — see
# _restore_snapshot()'s own comment for why (direct owner request: rewind should let a repeated
# action reroll for a different outcome, not deterministically replay the exact same miss/damage
# every time).
#
# Snapshot point: TurnManager.player_action_starting, fired from the top of begin_player_action()
# — i.e. right BEFORE any player action (real or a revert_to_waiting() free action) resolves.
# Deliberately NOT player_turn_started: that signal fires AFTER the action + enemy phase already
# resolved, at which point the "current" state and the "about to snapshot" state are identical —
# rewinding from a player_turn_started-taken snapshot was a no-op (bugfix, this used to be the
# snapshot point). Capturing pre-action means the snapshot naturally survives untouched across the
# WAITING_FOR_INPUT gap until the player's NEXT action begins, which is exactly when Backspace
# needs it. A free action's own snapshot simply becomes the rewind target for that free action
# alone (nothing wrong with that — undoing a free action is a well-defined, useful thing to do).

const MAX_SNAPSHOTS: int = 1

## Combat-transient GameState fields that live directly on the autoload rather than on
## GameState.player_stats (which already gets a full Resource.duplicate(true) — see
## _capture_snapshot()) or on Player (which owns its own is_raging/rage mirror, see
## Player.capture_rewind_state()). Every one of these is a plain value type (bool/int/String/
## Vector2i/Color), so a generic GameState.get(name)/set(name, value) round-trip is enough — no
## per-field plumbing needed. Pulled from this same file's/root CLAUDE.md's own "combat-transient
## state" bugfix note (GameState.start_new_run()'s reset list) plus the Wild Heart/Zealot/Fog
## Cloud/Darkness/Light fields documented alongside it. Deliberately excludes GameState.
## player_companion (owned by DungeonFloor.restore_rewind_enemies()'s own Companion respawn/
## despawn handling — reassigning it here could race that) and GameState.light_source_item (a
## floor Item reference invalidated by the floor-items wholesale rebuild in
## DungeonFloor.restore_rewind_props() — restoring light_source_pos/color without it just means a
## rewound Light cast may auto-expire on the next update_fog() instead of perfectly relighting,
## a documented minor gap, not a crash).
const REWIND_GAMESTATE_FIELDS: Array[String] = [
	"berserker_frenzy_used", "berserker_turns_since_frenzy",
	"masochist_ac_bonus", "scarred_warrior_limit_break_used", "bruiser_revive_used_this_floor",
	"player_was_hit_this_turn", "player_attacked_this_turn", "enemy_noticed_player_this_turn",
	"fov_radius_bonus", "psycho_adv_pending", "battlefield_adv_pending", "battlefield_adv_expire_turns",
	"grip_of_the_forest_used_this_turn", "halfling_nimbleness_used_this_turn",
	"step_of_wind_used_this_turn", "deflect_attacks_used_this_turn",
	"monk_extra_attack_pending", "monk_extra_attack_used_this_turn",
	"action_surge_pending",
	"bonus_action_used",
	"risen_from_dead_active", "player_on_difficult_terrain", "terrain_ac_bonus",
	"natural_rager_form", "active_rager_form", "rager_form_switch_turns_remaining",
	"wild_heart_sleeper_active", "player_evades_opportunity_attacks", "monk_disengage_this_round",
	"zealot_divine_fury_type", "zealot_blessed_charges", "zealot_blessed_heal_queued", "zealot_zp_charges",
	"special_slot_spell_id",
	"fog_cloud_pos", "fog_cloud_radius", "darkness_pos", "darkness_radius",
	"light_source_pos", "light_source_color",
]

## Concentration spells whose ongoing effect is anchored to a live Enemy-node reference
## (`Stats.hunters_mark_target` etc.) rather than pure position/counter data — see
## _restore_snapshot()'s own comment for why these specifically get force-ended on rewind (Fog
## Cloud/Darkness/Blade Ward/Expeditious Retreat/Detect Magic/Pass Without Trace/Invisibility/
## Faerie Fire hold no live Enemy reference and are deliberately NOT in this list — their state
## already round-trips correctly through the plain Stats/GameState field capture above).
const LIVE_REF_CONCENTRATION_SPELLS: Array[String] = [
	"hunters_mark", "witch_bolt", "ray_of_enfeeblement", "hold_person", "hideous_laughter",
	"hex", "ensnaring_strike",
]

var _snapshots: Array[Dictionary] = []
var _rewind_in_progress: bool = false


func _ready() -> void:
	TurnManager.player_action_starting.connect(_on_player_action_starting)
	# Floor 1 loads BEFORE character creation even starts, so _load_floor()'s own seed_baseline()
	# call is gated on GameState.class_selected and no-ops that first time (see DungeonFloor.
	# _load_floor()'s own comment) — this covers the moment onboarding genuinely finishes instead,
	# same "class_chosen re-fires once class_selected is finally true" precedent SaveManager's own
	# checkpoint-on-class_chosen hook relies on.
	GameState.class_chosen.connect(_on_class_chosen)


func _on_class_chosen(_chosen_class: Stats.CharacterClass) -> void:
	if GameState.class_selected:
		seed_baseline()


func _get_player() -> Player:
	return get_tree().get_first_node_in_group("player") as Player


func _get_floor() -> DungeonFloor:
	return get_tree().get_first_node_in_group("dungeon_floor") as DungeonFloor


func _on_player_action_starting() -> void:
	if _rewind_in_progress:
		return
	var player: Player = _get_player()
	if player == null:
		return
	_push(_capture_snapshot(player))


func can_rewind() -> bool:
	return _snapshots.size() > 0 and not _rewind_in_progress \
		and TurnManager.phase == TurnManager.Phase.WAITING_FOR_INPUT


func rewind() -> bool:
	if not can_rewind():
		return false
	var snap: Dictionary = _snapshots.pop_back()
	_rewind_in_progress = true
	_restore_snapshot(snap)
	_rewind_in_progress = false
	# Bugfix: rewind() used to leave _snapshots completely empty right after popping/restoring —
	# fine for the FIRST Backspace, but the very next free action (drinking a potion, equipping
	# gear) had nothing to revert to again until the player's next real turn-costing action, so a
	# second consecutive "free action then Backspace" always failed with "Nothing to rewind" even
	# though nothing about the situation actually changed. Re-seed a fresh baseline of the
	# just-restored state — same helper/reasoning as the floor-entry baseline (seed_baseline()'s
	# own doc comment) — so rewind is immediately usable again.
	seed_baseline()
	return true


## Called from the floor-load path so a stale snapshot can never survive a floor transition —
## rewind is explicitly scoped to "within the same floor" (see the plan's non-goals).
func clear() -> void:
	_snapshots.clear()


## Seeds a baseline "floor entry" snapshot so Backspace has something to rewind to even before the
## player's first REAL (turn-costing) action on a fresh floor. Bugfix: a free action — drinking a
## potion, equipping gear, filling a bottle's not-turn-costing branch, etc, none of which call
## TurnManager.begin_player_action() — taken as literally the very first thing after entering a
## floor (or after a prior rewind) had nothing to revert to at all: `_snapshots` was empty (only
## real actions push a snapshot), so can_rewind() correctly refused and "Nothing to rewind" logged
## — the potion's heal, item consumption, etc. all silently stuck. Called once by
## DungeonFloor._load_floor(), right after the floor is fully populated (SaveManager.checkpoint()'s
## own "everything is set up now" timing) — deliberately NOT on TurnManager.player_turn_started,
## which fires far too early mid-load (from TurnManager.reset(), before this floor's own
## player/enemies/props exist yet) to capture anything meaningful.
func seed_baseline() -> void:
	var player: Player = _get_player()
	if player != null:
		_push(_capture_snapshot(player))


func _push(snap: Dictionary) -> void:
	_snapshots.push_back(snap)
	if _snapshots.size() > MAX_SNAPSHOTS:
		_snapshots.pop_front()


## Deep-duplicates an Array of possibly-null Item resources (quickbar/bag slots) — null entries
## (empty slots) pass through unchanged, everything else gets a real Resource.duplicate(true) so
## a later mutation (uses_remaining ticking down, quantity changing) never touches the snapshot.
func _dup_item_array(arr: Array) -> Array:
	var out: Array = []
	for it in arr:
		out.append((it as Item).duplicate(true) if it != null else null)
	return out


func _dup_equipment(eq: Dictionary) -> Dictionary:
	var out: Dictionary = {}
	for key: String in eq:
		var it: Item = eq[key]
		out[key] = it.duplicate(true) if it != null else null
	return out


## Same shape as _dup_item_array() but for Ability resources (GameState.player_ability_bar) — a
## deep duplicate.true() so each ability's own uses_remaining/is_active is snapshotted before any
## activation this action might spend, and restoring later never touches the still-live originals.
func _dup_ability_array(arr: Array) -> Array:
	var out: Array = []
	for ab in arr:
		out.append((ab as Ability).duplicate(true) if ab != null else null)
	return out


func _capture_gs_fields() -> Dictionary:
	var out: Dictionary = {}
	for f: String in REWIND_GAMESTATE_FIELDS:
		out[f] = GameState.get(f)
	return out


func _restore_gs_fields(fields: Dictionary) -> void:
	for f: String in fields:
		GameState.set(f, fields[f])


func _capture_snapshot(player: Player) -> Dictionary:
	var floor: DungeonFloor = _get_floor()
	return {
		"turn_phase": TurnManager.phase,
		"enemy_actions_this_round": TurnManager.enemy_actions_this_round,
		"player_stats": GameState.player_stats.duplicate(true),
		"player_state": player.capture_rewind_state(),
		"quickbar": _dup_item_array(GameState.player_quickbar),
		"bag": _dup_item_array(GameState.player_inventory),
		"equipment": _dup_equipment(GameState.equipment),
		"ability_bar": _dup_ability_array(GameState.player_ability_bar),
		"gold": GameState.gold,
		"gs_fields": _capture_gs_fields(),
		"enemies": floor.capture_rewind_enemies() if floor != null else [],
		"props": floor.capture_rewind_props() if floor != null else {},
		"floor_ref": weakref(floor) if floor != null else null,
	}


func _restore_snapshot(snap: Dictionary) -> void:
	var player: Player = _get_player()
	var current_floor: DungeonFloor = _get_floor()
	if player == null or current_floor == null:
		return
	var floor_ref: WeakRef = snap.get("floor_ref")
	if floor_ref == null or floor_ref.get_ref() != current_floor:
		# Snapshot belongs to a floor that's no longer current (shouldn't normally happen —
		# clear() already runs on every floor load — but this is the defensive backstop the
		# plan calls for).
		GameState.game_log("[color=gray]Cannot rewind across a floor change.[/color]")
		clear()
		return

	# Deliberately does NOT restore Rng's stream position (used to, via a captured "rng_state" —
	# removed). Direct owner request: rewind should let a repeated action re-roll for a different
	# outcome, not deterministically reproduce the exact same miss/damage every single time. This
	# costs nothing elsewhere — DungeonFloor's own floor-generation/population RNG (_pop_rng) is a
	# completely separate RandomNumberGenerator instance seeded from (run_seed, floor), never the
	# Rng autoload's gameplay stream, so floor layout/loot stay exactly as reproducible as before;
	# SaveManager's own "rng_state" is an independent floor-entry checkpoint, unrelated to rewind's
	# in-memory-only snapshot. TurnManager.set_enemy_list() below still restores enemy ITERATION
	# ORDER exactly (load-bearing for who draws which Rng roll on the NEXT round) — only the actual
	# stream POSITION is left wherever it already advanced to, so the next roll off it is a genuine
	# fresh one rather than a replay of the undone action's own roll.

	current_floor.restore_rewind_enemies(snap.get("enemies", []))
	current_floor.restore_rewind_props(snap.get("props", {}))

	var restored_stats: Stats = snap.get("player_stats") as Stats
	if restored_stats != null:
		GameState.player_stats = restored_stats
		player.stats = restored_stats
		# Bugfix: StandardSlotPool/HalfCasterSlotPool/PactSlotPool (scripts/items/*_slot_pool.gd)
		# each hold a `owner_stats: Stats` back-reference to the ENCLOSING Stats object, set once
		# at apply_class_defaults() (`caster.slot_pool.owner_stats = self`) — a genuine circular
		# reference (Stats -> caster -> slot_pool -> owner_stats -> the same Stats). Resource.
		# duplicate(true) recursively duplicates every nested Resource it finds, and there's no
		# guarantee it re-links a cycle back to the FRESH clone rather than the original/an orphan
		# — if `owner_stats` ends up wrong (or null) after the duplicate/restore round-trip,
		# max_slots() silently returns an EMPTY dict (`if owner_stats == null: return {}`), which
		# cascades into "no spell slots available" that not even a long rest can fix (on_long_rest()
		# just re-derives `remaining` from that same broken max_slots()). Explicitly re-pointing it
		# at the just-restored Stats object here is a cheap, unconditional correctness guarantee
		# regardless of what duplicate() actually did with the cycle.
		if restored_stats.caster != null and restored_stats.caster.slot_pool != null:
			restored_stats.caster.slot_pool.owner_stats = restored_stats
		# Live Enemy-reference concentration/target fields (Hunter's Mark, Witch Bolt, etc.) end
		# on rewind unconditionally — matches existing save/load precedent (see root CLAUDE.md's
		# "Wizard leveled spells" / Ranger sections, "not serialized, live reference"): the
		# referenced Enemy node may no longer be the same instance after the enemies-array restore
		# just above (a dead one respawns as a NEW node, a mid-turn-summoned one despawns), so the
		# reference can't be trusted regardless of which spell it belonged to.
		# **Bugfix**: this used to only null the target reference itself, leaving its matching
		# `_turns` counter and `concentration_spell_id` still pointing at the "ended" spell — e.g.
		# the status tray kept showing "Concentrating: Witch Bolt" with a live countdown even
		# though the target reference backing it was already gone. Routed through the same
		# GameState.end_concentration() every real cast-a-different-spell/CON-check-fail call site
		# already uses, so the counter/target/concentration_spell_id all clear together, exactly
		# like a genuine mid-game concentration break — but ONLY when the restored
		# concentration_spell_id is actually one of the live-ref spells (LIVE_REF_CONCENTRATION_
		# SPELLS); every other concentration spell (Fog Cloud, Blade Ward, ...) has no live
		# reference to invalidate and is left alone, restored correctly by the plain field capture.
		if restored_stats.concentration_spell_id in LIVE_REF_CONCENTRATION_SPELLS:
			GameState.end_concentration()
		# Frightened isn't part of the concentration mechanism at all, but frightened_source is
		# the exact same kind of live Enemy reference — ends unconditionally for the same reason,
		# and (bugfix, same shape as above) frightened_turns is zeroed alongside it so the status
		# tray/DISADV checks don't keep reading "still frightened" off a source-less counter.
		restored_stats.frightened_source = null
		restored_stats.frightened_turns = 0

	player.restore_rewind_state(snap.get("player_state", {}))

	# Mutated IN PLACE rather than reassigning GameState.player_quickbar/player_inventory/equipment
	# to a new Array/Dictionary instance — same convention SaveManager's own restore
	# (_dicts_into_item_slots()) already uses, so anything holding a reference to the live
	# container (not just re-reading GameState.player_quickbar fresh every time) still sees the
	# update. The snapshot dict is popped and discarded right after this restore (see rewind()),
	# so these Item resources can be handed over directly — no need to duplicate them again.
	if snap.has("quickbar"):
		var qb: Array = snap["quickbar"]
		for i: int in mini(qb.size(), GameState.player_quickbar.size()):
			GameState.player_quickbar[i] = qb[i]
	if snap.has("bag"):
		var bag: Array = snap["bag"]
		for i: int in mini(bag.size(), GameState.player_inventory.size()):
			GameState.player_inventory[i] = bag[i]
	if snap.has("equipment"):
		var eq: Dictionary = snap["equipment"]
		for key: String in eq:
			GameState.equipment[key] = eq[key]
	if snap.has("ability_bar"):
		# Ability count/order doesn't change mid-action in normal play, so a same-index in-place
		# restore is enough (matches quickbar/bag above) — a mismatched size (an ability somehow
		# added/removed by the very action being undone) just restores whatever indices overlap.
		var ab_bar: Array = snap["ability_bar"]
		for i: int in mini(ab_bar.size(), GameState.player_ability_bar.size()):
			GameState.player_ability_bar[i] = ab_bar[i]
	if snap.has("gold"):
		GameState.gold = int(snap["gold"])
	if snap.has("gs_fields"):
		_restore_gs_fields(snap["gs_fields"])

	TurnManager.enemy_actions_this_round = int(snap.get("enemy_actions_this_round", 1))
	TurnManager.phase = snap.get("turn_phase", TurnManager.Phase.WAITING_FOR_INPUT)

	GameState.player_hp_changed.emit(GameState.player_stats.current_hp, GameState.player_stats.max_hp)
	GameState.equipment_changed.emit()
	GameState.inventory_changed.emit()
	GameState.ability_bar_changed.emit()
	GameState.player_status_changed.emit()
	GameState.gold_changed.emit(GameState.gold)
	GameState.game_log("[color=gray]You rewind time to the start of the turn.[/color]")
