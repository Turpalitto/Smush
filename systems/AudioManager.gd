extends Node
## Sound event manager (Autoload: Audio).
## Supports pooled polyphonic SFX and optional ambient music (disabled by default per spec).

const SFX_POOL_SIZE: int = 8
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
const MUSIC_PATH: String = "res://audio/music/ambient_forest.wav"

var _sfx_players: Array[AudioStreamPlayer] = []
var _music_player: AudioStreamPlayer
var _next_idx: int = 0
var _move_cooldown: float = 0.0
var last_played_event: String = ""


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	for i in range(SFX_POOL_SIZE):
		var p := AudioStreamPlayer.new()
		p.name = "SFX_%d" % i
		add_child(p)
		_sfx_players.append(p)

	_music_player = AudioStreamPlayer.new()
	_music_player.name = "MusicPlayer"
	add_child(_music_player)

	Events.settings_changed.connect(_sync_volumes)
	_sync_volumes()


func _process(delta: float) -> void:
	if _move_cooldown > 0.0:
		_move_cooldown -= delta


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


func play_sfx(event_name: String, pitch_scale: float = 1.0) -> void:
	if event_name == "move":
		if _move_cooldown > 0.0:
			return
		_move_cooldown = 0.28

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

	var player := _sfx_players[_next_idx]
	_next_idx = (_next_idx + 1) % _sfx_players.size()
	player.stream = stream
	player.pitch_scale = clampf(pitch_scale, 0.55, 1.75)
	player.play()
