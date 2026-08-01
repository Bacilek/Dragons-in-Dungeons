class_name EldritchInvocation
extends Resource

# Warlock's Eldritch Invocations — a simpler cousin of Talent (scripts/items/talent.gd): pick-once,
# no ranks. See scripts/entities/CLAUDE.md's "Warlock class" for the full list and mechanism.

@export var invocation_id: String = ""
@export var invocation_name: String = ""
@export var description: String = ""
@export var min_level: int = 1
@export var requires_invocation: String = ""   # "" = no prerequisite invocation
