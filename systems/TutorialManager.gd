class_name TutorialManager
extends Node
## Non-intrusive 4-step contextual tutorial for first-time players.
## Fires tutorial_started and tutorial_completed analytics events.

var active: bool = false
var step: int = 0
var _step_timer: float = 0.0
var _text_prefix: String = "tut.step"


func _ready() -> void:
	Events.evolution_progress_changed.connect(func(_xp: float, _thresh: float, lv: int) -> void:
		if active and lv >= 1 and step < 4:
			step = 4
			_step_timer = 0.0
			_show_step()
	)


func begin_if_needed(mode: String = "standard") -> void:
	_text_prefix = "tut.zen.step" if mode == "zen" else "tut.step"
	var done: bool = bool(SaveData.data.get("stats", {}).get("tutorial_completed", false))
	if done:
		active = false
		return
	active = true
	step = 1
	_step_timer = 0.0
	Analytics.track("tutorial_started")
	_show_step()


func _show_step() -> void:
	Events.tutorial_step_shown.emit(step, _text_prefix + str(step))


func notify_player_moved() -> void:
	if active and step == 1 and _step_timer >= 1.4:
		step = 2
		_step_timer = 0.0
		_show_step()


func notify_entity_absorbed() -> void:
	if active and step == 2 and _step_timer >= 2.2:
		step = 3
		_step_timer = 0.0
		_show_step()


func notify_mutation_picked() -> void:
	if active and step >= 1:
		complete_tutorial()


func _process(delta: float) -> void:
	if not active:
		return
	_step_timer += delta
	if step == 3 and _step_timer >= 6.5:
		step = 4
		_step_timer = 0.0
		_show_step()
	elif step == 4 and _step_timer >= 13.0:
		complete_tutorial()


func complete_tutorial() -> void:
	if not active:
		return
	active = false
	SaveData.data["stats"]["tutorial_completed"] = true
	SaveData.save_to_disk()
	Analytics.track("tutorial_completed")
	Events.tutorial_completed.emit()
