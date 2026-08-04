extends Node

enum Phase { WAITING_FOR_INPUT, RESOLVING_PLAYER, RESOLVING_ENEMIES }

signal player_turn_started()
signal player_turn_ending()  # fired once per real (non-reverted) player action, right before enemies act
signal turn_resolved()

var phase: Phase = Phase.WAITING_FOR_INPUT
var fast_mode: bool = false

# Movement-speed turn economy: set by the mover (player.gd) BEFORE calling
# on_player_action_complete() for a move whose speed differs from baseline — always consumed
# (reset to 1) at the top of _process_enemies() so it only ever affects the ONE round it was set
# for. 0 = this round grants every enemy zero actions (a "free"/no-cost move — difficult terrain's
# opposite); 2 = this round grants every enemy two actions back-to-back (difficult terrain/Slowed).
# The point: a speed effect NEVER changes how many times on_player_action_complete()/
# begin_player_action() get called (always exactly once per real move) or how many times
# player_turn_ending fires (always exactly once) — only how many times _process_enemies() lets
# enemies act inside that one cycle. See scripts/entities/CLAUDE.md's "Movement speed scaling".
# Deliberately narrow, not a general action-economy system — same spirit as revert_to_waiting()'s
# own comment below.
var enemy_actions_this_round: int = 1

var _enemies: Array = []
var _remaining_enemies: int = 0
var _rounds_remaining: int = 0

func _ready() -> void:
	call_deferred("_start_player_turn")

func register_enemy(enemy: Node) -> void:
	_enemies.append(enemy)

func unregister_enemy(enemy: Node) -> void:
	_enemies.erase(enemy)

func clear_enemies() -> void:
	_enemies.clear()

func has_any_enemy() -> bool:
	for e in _enemies:
		if is_instance_valid(e):
			return true
	return false

func begin_player_action() -> void:
	phase = Phase.RESOLVING_PLAYER

func on_player_action_complete() -> void:
	if phase != Phase.RESOLVING_PLAYER:
		return
	player_turn_ending.emit()
	phase = Phase.RESOLVING_ENEMIES
	_process_enemies()

# Rager talent: grants a free action by skipping enemy phase and returning to player input.
# Intentionally narrow — do NOT generalize this into a general action-economy system.
func revert_to_waiting() -> void:
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()

func _process_enemies() -> void:
	var rounds: int = enemy_actions_this_round
	enemy_actions_this_round = 1
	if rounds <= 0:
		_end_turn()
		return
	_rounds_remaining = rounds
	_process_enemy_round()

# One full decide-then-execute pass over every enemy. Called once for a normal move; called AGAIN
# (from _run_single_enemy()'s completion, never nested/overlapping) by _advance_round_or_end()
# when enemy_actions_this_round asked for more than one round — e.g. Slowed's "opponents get 2
# actions for my 1 move." Deliberately does NOT re-enter begin_player_action()/
# on_player_action_complete()/player_turn_ending between rounds — those fire exactly once per real
# move regardless of how many enemy rounds resolve inside it (see enemy_actions_this_round's own
# comment for why: a stray extra player_turn_ending used to double-fire Witch Bolt's tick and the
# Stealth-vs-Passive-Perception check on a single slowed move).
func _process_enemy_round() -> void:
	var valid: Array = []
	for e in _enemies:
		if is_instance_valid(e):
			valid.append(e)
	if valid.is_empty():
		_advance_round_or_end()
		return
	# Decide-then-execute split (see Enemy.decide_turn()/execute_turn()): every enemy's decision is
	# made FIRST, back-to-back, against the identical pre-round world state, before any of them
	# actually moves/attacks/opens a door — so the round reads as simultaneous rather than as a
	# strict sequence where an earlier enemy's move can change what a later enemy is able to see
	# and act on THIS SAME round (e.g. a melee enemy opening a door mid-round granting a ranged
	# enemy behind it same-round line-of-sight to shoot through).
	var pending: Array = []
	for e in valid:
		if not is_instance_valid(e):
			continue
		pending.append([e, e.decide_turn()])
	_remaining_enemies = pending.size()
	if _remaining_enemies == 0:
		_advance_round_or_end()
		return
	for pair: Array in pending:
		_run_single_enemy(pair[0], pair[1])

func _advance_round_or_end() -> void:
	_rounds_remaining -= 1
	# Death save sequence (Slowed's "opponents get 2 actions for my 1 move" can queue a 2nd
	# enemy round that would otherwise still run after the player's already gone down mid-1st —
	# see GameState.begin_death_save_sequence()'s own "known limitation" comment).
	if _rounds_remaining > 0 and not GameState.is_dying and not GameState.is_game_over:
		_process_enemy_round()
	else:
		_end_turn()

func reset() -> void:
	_remaining_enemies = 0
	_rounds_remaining = 0
	enemy_actions_this_round = 1
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()

func _run_single_enemy(enemy: Node, intent: Dictionary) -> void:
	if is_instance_valid(enemy) and not enemy.stats.is_dead():
		await enemy.execute_turn(intent)
	if _remaining_enemies <= 0:
		return
	_remaining_enemies -= 1
	if _remaining_enemies <= 0:
		_advance_round_or_end()

func _end_turn() -> void:
	turn_resolved.emit()
	_start_player_turn()

func _start_player_turn() -> void:
	phase = Phase.WAITING_FOR_INPUT
	player_turn_started.emit()
