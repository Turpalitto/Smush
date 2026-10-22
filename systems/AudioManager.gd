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
const MUSIC_PATH: String = "res://audio/music/ambient_forest.wav"

var _sfx_players: Array[AudioStreamPlayer] = []
var _player_events: Array[String] = []
var _music_player: AudioStreamPlayer
var _next_idx: int = 0
var _move_cooldown: float = 0.0
var _event_cooldowns: Dictionary = {}
var last_played_event: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	_ensure_master_limiter()
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_players.append(p)
		_player_events.append("")

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	Events.settings_changed.connect(_sync_volumes)
	_sync_volumes()


func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown -= delta
	for k in _event_cooldowns.keys():
		var rem := float(_event_cooldowns[k]) - delta
		if rem <= 0.0:
			_event_cooldowns.erase(k)
		else:
			_event_cooldowns[k] = rem


func _linear_to_db_safe(linear: float) -> float:
	if linear <= 0.001:
		return -80.0
	return linear_to_db(clampf(linear, 0.0, 1.0))


func _sync_volumes() -> void:
	var sfx_vol: float = float(SaveData.get_setting("sfx_volume", 0.85))
	var music_vol: float = float(SaveData.get_setting("music_volume", 0.55))
	var music_on: bool = bool(SaveData.get_setting("music_enabled", false))

	var sfx_db := _linear_to_db_safe(sfx_vol)
	for p in _sfx_players:
		p.volume_db = sfx_db

	if _music_player != null:
		_music_player.volume_db = _linear_to_db_safe(music_vol)
		if music_on:
			if not _music_player.playing:
				var mstream := AssetRegistry.get_wav_stream(MUSIC_PATH, true)
				if mstream != null:
					_music_player.stream = mstream
					_music_player.play()
		else:
			if _music_player.playing:
				_music_player.stop()


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
	last_played_event = event_name

	var sfx_vol: float = float(SaveData.get_setting("sfx_volume", 0.85))
	if sfx_vol <= 0.001 or _sfx_players.is_empty():
		return

	# Skip actual audio playback when running with Dummy audio driver in headless CI,
	# after recording last_played_event for test verification.
	if DisplayServer.get_name() == "headless":
		return

	var stream := AssetRegistry.get_wav_stream(SFX_PATHS[event_name], false)
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
