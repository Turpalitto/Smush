extends Node
## Sound event manager (Autoload: Audio).
## Supports pooled polyphonic SFX and optional ambient music (disabled by default per spec).

const SFX_POOL_SIZE: int = 10
const SFX_PATHS: Dictionary = {
	"move": "res://audio/sfx/move_pulse.wav",
	"absorb": "res://audio/sfx/absorb.wav",
	"evolution": "res://audio/sfx/evolution.wav",
	"mutation_pick": "res://audio/sfx/mutation_pick.wav",
	"attack": "res://audio/sfx/attack.wav",
	"hurt": "res://audio/sfx/hurt.wav",
	"victory": "res://audio/sfx/victory.wav",
	"defeat": "res://audio/sfx/defeat.wav",
	"button_click": "res://audio/sfx/button_click.wav",
	"boss_warning": "res://audio/sfx/boss_warning.wav",
	"shield_break": "res://audio/sfx/shield_break.wav"
}
const EVENT_DB_OFFSETS: Dictionary = {
	"move": -14.5,
	"absorb": -4.2,
	"orb_chime": -9.5,
	"attack": -2.2,
	"button_click": -1.5,
	"mutation_pick": 0.0,
	"shield_break": 0.0,
	"evolution": 0.5,
	"hurt": 0.5,
	"boss_warning": 0.8,
	"victory": 0.0,
	"defeat": 0.0
}
const PRIORITY_EVENTS: Dictionary = {
	"hurt": true,
	"boss_warning": true,
	"evolution": true,
	"shield_break": true,
	"mutation_pick": true,
	"victory": true,
	"defeat": true
}
## Three composed loops (see tools/generate_music.py). Menu / exploration / boss, so the
## soundtrack reacts to what the player is doing instead of looping one 6-second placeholder.
const MUSIC_TRACKS: Dictionary = {
	"menu": "res://audio/music/theme_menu.ogg",
	"run": "res://audio/music/theme_run.ogg",
	"boss": "res://audio/music/theme_boss.ogg",
	"zen": "res://audio/music/theme_zen.ogg"
}
const MUSIC_FADE_SEC: float = 1.6
const MUSIC_SILENT_DB: float = -60.0

## Collection chimes (audio/sfx/orb_chime_01..08.wav, built by
## tools/generate_orb_chimes.py). Notes are played as a rising pentatonic line while
## the player keeps collecting: consecutive pickups inside the window step up the
## scale, a pause of longer than the window restarts it at the bottom. That turns a
## fast sweep over a spore field into a phrase instead of the same blip forty times.
const ORB_CHIME_COUNT: int = 8
const ORB_CHIME_PATH: String = "res://audio/sfx/orb_chime_%02d.wav"
const ORB_CHIME_WINDOW_SEC: float = 1.8

var _sfx_players: Array[AudioStreamPlayer] = []
var _player_events: Array[String] = []
var _music_players: Array[AudioStreamPlayer] = []
var _music_target_db: Array[float] = []
var _music_db_per_sec: Array[float] = []
var _music_id: String = ""
var _next_idx: int = 0
var _move_cooldown: float = 0.0
var _event_cooldowns: Dictionary = {}
var last_played_event: String = ""
## Position in the chime ladder and the time left in the window that keeps it going.
var _chime_step: int = 0
## Mode of the live run, so a PLAYING state change picks the same track the run
## started with. Without it the zen bed would be replaced by the run theme on the
## first pause/resume, because `run_started` fires before the state change.
var _run_mode: String = "standard"
var _chime_window: float = 0.0


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_master_limiter()
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_players.append(p)
		_player_events.append("")

	_music_players.clear()
	_music_target_db.clear()
	_music_db_per_sec.clear()
	for i in range(2):
		var m := AudioStreamPlayer.new()
		m.name = "Music_%d" % i
		m.volume_db = MUSIC_SILENT_DB
		add_child(m)
		_music_players.append(m)
		_music_target_db.append(MUSIC_SILENT_DB)
		_music_db_per_sec.append(120.0)

	Events.settings_changed.connect(_sync_volumes)
	Events.game_state_changed.connect(_on_game_state_changed)
	Events.run_started.connect(_on_run_started)
	Events.run_finished.connect(_on_run_finished)
	Events.boss_spawned.connect(_on_boss_spawned)
	_sync_volumes()


func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown -= delta
	if _chime_window > 0.0:
		_chime_window = maxf(0.0, _chime_window - delta)
	for k in _event_cooldowns.keys():
		var rem := float(_event_cooldowns[k]) - delta
		if rem <= 0.0:
			_event_cooldowns.erase(k)
		else:
			_event_cooldowns[k] = rem
	_advance_music_fades(delta)


func _advance_music_fades(delta: float) -> void:
	for i in range(_music_players.size()):
		var p := _music_players[i]
		var target := _music_target_db[i]
		var step := _music_db_per_sec[i] * delta
		if absf(p.volume_db - target) <= step:
			p.volume_db = target
		else:
			p.volume_db = move_toward(p.volume_db, target, step)
		# A player that faded out is stopped so it does not keep decoding the loop.
		if p.volume_db <= MUSIC_SILENT_DB + 0.05 and target <= MUSIC_SILENT_DB + 0.05 and p.playing:
			p.stop()


## Plays a track from MUSIC_TRACKS, crossfading from whatever is already playing.
## Calling it again with the same id is a no-op, so state changes can be chatty.
func play_music(track_id: String, fade_sec: float = MUSIC_FADE_SEC) -> void:
	if not MUSIC_TRACKS.has(track_id):
		return
	if track_id == _music_id and _music_active_player() != null:
		return
	if DisplayServer.get_name() == "headless":
		_music_id = track_id
		return

	var stream := AssetRegistry.get_audio_stream(str(MUSIC_TRACKS[track_id]), true)
	if stream == null:
		return

	var next_idx := 0
	if not _music_players.is_empty() and _music_players[0].playing:
		next_idx = 1
	var player := _music_players[next_idx]
	player.stream = stream
	player.volume_db = MUSIC_SILENT_DB
	player.play()

	var target := _music_volume_db()
	_music_target_db[next_idx] = target
	_music_db_per_sec[next_idx] = maxf(6.0, absf(target - MUSIC_SILENT_DB) / maxf(0.1, fade_sec))

	for i in range(_music_players.size()):
		if i == next_idx:
			continue
		_music_target_db[i] = MUSIC_SILENT_DB
		_music_db_per_sec[i] = maxf(6.0, absf(_music_players[i].volume_db - MUSIC_SILENT_DB) / maxf(0.1, fade_sec))

	_music_id = track_id


func stop_music(fade_sec: float = MUSIC_FADE_SEC) -> void:
	_music_id = ""
	for i in range(_music_players.size()):
		_music_target_db[i] = MUSIC_SILENT_DB
		_music_db_per_sec[i] = maxf(6.0, absf(_music_players[i].volume_db - MUSIC_SILENT_DB) / maxf(0.1, fade_sec))


func current_music_id() -> String:
	return _music_id


func is_music_playing() -> bool:
	return _music_active_player() != null


func _music_active_player() -> AudioStreamPlayer:
	for p in _music_players:
		if p.playing and p.volume_db > MUSIC_SILENT_DB + 0.5:
			return p
	return null


func _music_volume_db() -> float:
	if not bool(SaveData.get_setting("music_enabled", true)):
		return MUSIC_SILENT_DB
	return _linear_to_db_safe(float(SaveData.get_setting("music_volume", 0.55)))


# --- music follows the app state -------------------------------------------------


func _on_game_state_changed(_old_state: int, new_state: int) -> void:
	match new_state:
		App.State.MAIN_MENU, App.State.MODE_SELECT, App.State.VICTORY, App.State.DEFEAT:
			play_music("menu")
		App.State.PLAYING:
			# The boss keeps its own theme until the run ends.
			if _music_id != "boss":
				play_music(GameModes.music_for(_run_mode))
		_:
			pass


func _on_run_started(mode_id: String) -> void:
	# Zen gets its own beatless ambient bed; every other mode keeps the run theme.
	_run_mode = GameModes.normalize(mode_id)
	play_music(GameModes.music_for(_run_mode))


func _on_run_finished(_victory: bool, _summary: Dictionary) -> void:
	stop_music(2.2)


func _on_boss_spawned(_boss_id: String, _max_hp: float) -> void:
	play_music("boss", 2.4)


func _linear_to_db_safe(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _sync_volumes() -> void:
	var sfx_vol: float = float(SaveData.get_setting("sfx_volume", 0.85))
	var music_on: bool = bool(SaveData.get_setting("music_enabled", true))

	var sfx_db := _linear_to_db_safe(sfx_vol)
	for p in _sfx_players:
		p.volume_db = sfx_db

	var target := _music_volume_db()
	if not music_on:
		stop_music(0.6)
		return
	if _music_id.is_empty():
		# First enable (or the very first boot): the menu theme is the safe default.
		play_music("menu", 2.0)
		return
	# A volume slider move should not restart the track, only re-aim the fade.
	for i in range(_music_players.size()):
		if _music_target_db[i] > MUSIC_SILENT_DB + 0.5:
			_music_target_db[i] = target


func _ensure_master_limiter() -> void:
	var master_idx := AudioServer.get_bus_index("Master")
	if master_idx < 0:
		return
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		if AudioServer.get_bus_effect(master_idx, i) is AudioEffectHardLimiter:
			return
	var lim := AudioEffectHardLimiter.new()
	lim.ceiling_db = -1.2
	lim.pre_gain_db = 0.0
	AudioServer.add_bus_effect(master_idx, lim, 0)


func create_post_limiter_recorder() -> AudioEffectRecord:
	_ensure_master_limiter()
	var master_idx := AudioServer.get_bus_index("Master")
	var rec := AudioEffectRecord.new()
	# Append at the end of Master FX chain so capture occurs AFTER AudioEffectHardLimiter
	AudioServer.add_bus_effect(master_idx, rec, AudioServer.get_bus_effect_count(master_idx))
	return rec


func get_master_limiter_info() -> Dictionary:
	var master_idx := AudioServer.get_bus_index("Master")
	var info := {
		"bus": "Master",
		"bus_volume_db": AudioServer.get_bus_volume_db(master_idx) if master_idx >= 0 else 0.0,
		"mix_rate_hz": AudioServer.get_mix_rate(),
		"limiter_effect_index": -1,
		"ceiling_db": 0.0,
		"pre_gain_db": 0.0,
		"release_sec": 0.0,
		"bus_effects": []
	}
	if master_idx < 0:
		return info
	var fx_list: Array[String] = []
	for i in range(AudioServer.get_bus_effect_count(master_idx)):
		var eff := AudioServer.get_bus_effect(master_idx, i)
		fx_list.append("%d:%s" % [i, eff.get_class()])
		if eff is AudioEffectHardLimiter and int(info["limiter_effect_index"]) < 0:
			var h := eff as AudioEffectHardLimiter
			info["limiter_effect_index"] = i
			info["ceiling_db"] = h.ceiling_db
			info["pre_gain_db"] = h.pre_gain_db
			info["release_sec"] = h.release
	info["bus_effects"] = fx_list
	return info


func _select_voice_index(is_priority: bool = false) -> int:
	var n := _sfx_players.size()
	for offset in range(n):
		var idx := (_next_idx + offset) % n
		if not _sfx_players[idx].playing:
			_next_idx = (idx + 1) % n
			return idx
	for offset in range(n):
		var idx := (_next_idx + offset) % n
		if not PRIORITY_EVENTS.has(_player_events[idx]):
			_next_idx = (idx + 1) % n
			return idx
	if not is_priority:
		return -1
	var fallback := _next_idx
	_next_idx = (_next_idx + 1) % n
	return fallback


func play_sfx(event_name: String, pitch_scale: float = 1.0) -> void:
	if event_name == "move":
		if _move_cooldown > 0.0:
			return
		_move_cooldown = 1.25
	elif _event_cooldowns.has(event_name):
		return
	else:
		if event_name == "absorb":
			_event_cooldowns[event_name] = 0.085
		elif event_name == "attack":
			_event_cooldowns[event_name] = 0.085
		elif event_name == "hurt":
			_event_cooldowns[event_name] = 0.12

	if not SFX_PATHS.has(event_name):
		return
	_emit(event_name, str(SFX_PATHS[event_name]), pitch_scale)


## The evolution reward, per stage.
##
## There are fifteen bells (audio/sfx/evo_01.wav .. evo_15.wav, built by
## tools/generate_evolution_bells.py) walking the C major pentatonic from C3 to A5,
## opening up in timbre and tail as the stage rises. The old code played one bell
## pitched by stage, which silently stopped working halfway up the ladder: play_sfx
## clamps pitch_scale to 1.75, and (stage-1)*1.5 semitones reaches that clamp at
## stage 10, so stages 10-15 all sounded identical.
##
## Falls back to the shared bell if a stage file is missing, so a partial asset set
## can never make the reward silent.
func play_evolution(stage: int) -> void:
	var s := clampi(stage, 1, EvolutionStages.COUNT)
	var path := "res://audio/sfx/evo_%02d.wav" % s
	if not ResourceLoader.exists(path) and not FileAccess.file_exists(path):
		_emit("evolution", str(SFX_PATHS["evolution"]), 1.0)
		return
	_emit("evolution", path, 1.0)


func _emit(event_name: String, path: String, pitch_scale: float) -> void:
	last_played_event = event_name

	var sfx_vol: float = float(SaveData.get_setting("sfx_volume", 0.85))
	if sfx_vol <= 0.001 or _sfx_players.is_empty():
		return

	# Skip actual audio playback when running with Dummy audio driver in headless CI,
	# after recording last_played_event for test verification.
	if DisplayServer.get_name() == "headless":
		return

	var stream := AssetRegistry.get_wav_stream(path, false)
	if stream == null:
		return

	var v_idx := _select_voice_index(PRIORITY_EVENTS.has(event_name))
	if v_idx < 0:
		return
	var player := _sfx_players[v_idx]
	_player_events[v_idx] = event_name
	player.stream = stream
	var base_db := _linear_to_db_safe(sfx_vol)
	var offset_db := float(EVENT_DB_OFFSETS.get(event_name, 0.0))
	player.volume_db = base_db + offset_db
	var jitter := randf_range(0.94, 1.07) if event_name in ["move", "absorb", "attack"] else 1.0
	player.pitch_scale = clampf(pitch_scale * jitter, 0.55, 1.75)
	player.play()


## One note of the collection ladder. Called for every orb the slime swallows.
##
## The ladder advances only while the player keeps collecting: a gap longer than
## ORB_CHIME_WINDOW_SEC restarts it at the bottom of the scale. Stepping up on every
## single pickup regardless of timing would climb to the top of the scale in eight
## orbs and then sit there, which is exactly the "same blip forever" it replaces.
func play_orb_chime() -> void:
	if _chime_window <= 0.0:
		_chime_step = 0
	else:
		_chime_step = (_chime_step + 1) % ORB_CHIME_COUNT
	_chime_window = ORB_CHIME_WINDOW_SEC
	var path := ORB_CHIME_PATH % (_chime_step + 1)
	if not FileAccess.file_exists(path):
		# A partial asset set must not make collection silent: fall back to the
		# generic absorb blip the game shipped with.
		_emit("absorb", str(SFX_PATHS["absorb"]), 1.1)
		return
	_emit("orb_chime", path, 1.0)


## Test seam: where the ladder currently stands (0-based).
func chime_step() -> int:
	return _chime_step
