extends Node

enum State { LOADING, MAIN_MENU, IN_GAME, PAUSED }

var current_state: State = State.LOADING
var loading_progress: float = 0.0
var world_seed: int = 1337

signal state_changed(new_state)

func change_state(new_state: State):
	current_state = new_state
	state_changed.emit(new_state)
