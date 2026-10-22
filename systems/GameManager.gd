extends Node
## High-level game state & mobile lifecycle controller (Autoload: App).

enum State {
	BOOT,
	MAIN_MENU,
	MODE_SELECT,
	PLAYING,
	MUTATION_DRAFT,
	PAUSED,
	VICTORY,
	DEFEAT
}

var state: State = State.BOOT
var selected_mode: String = "standard"
var last_run_summary: Dictionary = {}

# Lightweight runtime performance monitor
var avg_fps: float = 60.0
var worst_frame_ms: float = 0.0
var _perf_accum: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	get_tree().set_auto_accept_quit(false)


func _process(delta: float) -> void:
	_perf_accum += delta
	var frame_ms := delta * 1000.0
	if frame_ms > worst_frame_ms and _perf_accum > 1.0:
		worst_frame_ms = frame_ms
	if _perf_accum >= 0.5:
		avg_fps = float(Engine.get_frames_per_second())
		_perf_accum = 0.0


func _notification(what: int) -> void:
	match what:
		NOTIFICATION_APPLICATION_PAUSED, NOTIFICATION_APPLICATION_FOCUS_OUT, NOTIFICATION_WM_WINDOW_FOCUS_OUT:
			# Mobile backgrounding / interruption safety: auto-pause run and flush save immediately
			Analytics.end_session()
			SaveData.save_to_disk()
			if state == State.PLAYING:
				change_state(State.PAUSED)
		NOTIFICATION_APPLICATION_RESUMED, NOTIFICATION_APPLICATION_FOCUS_IN:
			Analytics.start_session()
		NOTIFICATION_WM_GO_BACK_REQUEST:
			handle_back_navigation()
		NOTIFICATION_WM_CLOSE_REQUEST:
			Analytics.end_session()
			SaveData.save_to_disk()
			get_tree().quit()


func handle_back_navigation() -> void:
	match state:
		State.PLAYING:
			change_state(State.PAUSED)
		State.PAUSED:
			change_state(State.PLAYING)
		State.MODE_SELECT:
			change_state(State.MAIN_MENU)


func change_state(new_state: State) -> bool:
	if state == new_state:
		return false
	var old := state
	state = new_state

	match state:
		State.PLAYING:
			get_tree().paused = false
		State.MUTATION_DRAFT, State.PAUSED, State.VICTORY, State.DEFEAT:
			get_tree().paused = true
		State.MAIN_MENU, State.MODE_SELECT:
			get_tree().paused = false

	Events.game_state_changed.emit(old, state)
	return true


func get_fx_particle_budget() -> int:
	var q: String = str(SaveData.get_setting("fx_quality", "high"))
	match q:
		"low":
			return 20
		"medium":
			return 45
		_:
			return 80
