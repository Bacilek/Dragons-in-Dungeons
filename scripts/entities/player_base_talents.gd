class_name PlayerBaseTalents
extends Node

# Barbarian base-class Tier 1 talents shared by every subclass: Psycho, Bruiser, Battlefield
# Expert. Composition child-node split out of player.gd — see scripts/entities/CLAUDE.md.
# Spec: markdowns/barbarian_base.md.

var player: Player

# ── Psycho ──────────────────────────────────────────────────────────────────────
# R1: after a kill, the next attack (any type) is made with Advantage. R2: a critical hit also
# triggers it. Persists across turns until consumed — not reset in _on_turn_started().
# Lives on GameState (GameState.psycho_adv_pending), not here, so the status tray (hud.gd, which
# only ever reads GameState per scripts/ui/CLAUDE.md's convention) can display it without a
# live Player node reference.

func on_kill() -> void:
	if GameState.get_talent_rank("psycho") >= 1:
		GameState.psycho_adv_pending = true

func on_crit() -> void:
	if GameState.get_talent_rank("psycho") >= 2:
		GameState.psycho_adv_pending = true

# Called once per attack-roll site right after adv_count is otherwise finalized; returns 1 if
# consumed (caller adds it into their own adv_count), else 0.
func consume_psycho_adv() -> int:
	if not GameState.psycho_adv_pending:
		return 0
	GameState.psycho_adv_pending = false
	return 1

# ── Battlefield Expert ────────────────────────────────────────────────────────────
# R1: after a side-step, next attack (any type) is made with Advantage. Lives on GameState
# (GameState.battlefield_adv_pending) for the same reason as psycho_adv_pending above.
# R3: set at turn start if the player was hit last turn; consumed by the first side-step this turn.
var free_sidestep_available: bool = false
# Set true by on_sidestep() during _resolve_enemy_opportunity_attacks(); read+cleared by
# _try_move() right after that call to decide whether this move qualifies as a free action.
var sidestep_detected_this_move: bool = false

func on_sidestep(enemy: Enemy) -> void:
	var rank: int = GameState.get_talent_rank("battlefield_expert")
	if rank < 1:
		return
	sidestep_detected_this_move = true
	GameState.battlefield_adv_pending = true
	# Expires at the end of the NEXT real turn if unused (2, not 1: a side-step normally ends
	# the current turn, so the first real turn-start after granting is "next turn" — that one
	# doesn't expire it, the one after does. R3's free/reverted side-step doesn't end the turn
	# at all, so the buff is also usable immediately, same turn, before this countdown even
	# starts ticking — see tick_battlefield_adv_expiry()).
	GameState.battlefield_adv_expire_turns = 2
	GameState.game_log("[color=cyan]Battlefield Expert: side-step! You gain Tactician — Advantage on your next attack this turn.[/color]")
	if rank >= 2:
		enemy.disadv_next_attack = true

func consume_psycho_or_battlefield_adv() -> int:
	return consume_psycho_adv() + consume_battlefield_adv()

func consume_battlefield_adv() -> int:
	if not GameState.battlefield_adv_pending:
		return 0
	GameState.battlefield_adv_pending = false
	GameState.battlefield_adv_expire_turns = 0
	return 1

# Called from player.gd._on_turn_started() on real turns only (never on Battlefield Expert R3's
# own free/reverted side-step turn) — counts down the Tactician buff and clears it if the player
# never attacked with it.
func tick_battlefield_adv_expiry() -> void:
	if not GameState.battlefield_adv_pending:
		return
	GameState.battlefield_adv_expire_turns -= 1
	if GameState.battlefield_adv_expire_turns <= 0:
		GameState.battlefield_adv_pending = false
		GameState.battlefield_adv_expire_turns = 0

# Called from _on_turn_started() on real turns only, before GameState.player_was_hit_this_turn
# is cleared for the Rage-duration check.
func tick_free_sidestep(was_hit_last_turn: bool) -> void:
	free_sidestep_available = GameState.get_talent_rank("battlefield_expert") >= 3 and was_hit_last_turn

# Called from _try_move() right after _resolve_enemy_opportunity_attacks(); consumes the R3
# free-sidestep charge if this move qualified. Returns true if the move should NOT cost a turn.
func consume_free_sidestep() -> bool:
	var qualifies: bool = sidestep_detected_this_move and free_sidestep_available
	sidestep_detected_this_move = false
	if qualifies:
		free_sidestep_available = false
	return qualifies
