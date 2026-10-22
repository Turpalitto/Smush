class_name EnemyFSM
extends RefCounted
## Explicit Finite State Machine driving all 8 creature behaviors in SLIME RUSH: EVOLUTION.

enum State {
	IDLE,
	WANDER,
	FLEE,
	CHASE,
	AMBUSH_HIDE,
	TELEGRAPH,
	ATTACK,
	RECOVER,
	STUNNED,
	BEING_ABSORBED,
	DEAD
}

var state: State = State.IDLE
var state_timer: float = 0.0


func transition_to(new_state: State, duration: float = 0.0) -> void:
	state = new_state
	state_timer = duration


func tick(delta: float) -> bool:
	if state_timer > 0.0:
		state_timer -= delta
		if state_timer <= 0.0:
			state_timer = 0.0
			return true
	return false
