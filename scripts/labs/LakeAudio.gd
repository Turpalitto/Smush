class_name LakeAudio
extends Node
## Water sound for the lake prototype (ADR-11041620). Synthesised files in audio/sfx/water (tools/generate_water_sfx.py).
## Three loops are mixed from the slime's state: surface lapping fades out and the underwater drone fades in as the
## dive progresses, and a soft glide swish follows the slime's speed. One-shots are pooled and rate-limited so a fast
## sweep over lily pads stays a gentle patter, never a machine gun. Levels are conservative (relaxation game).
## Lab only: the shipped Audio autoload (systems/AudioManager.gd) is not modified until integration is approved.

const DIR := "res://audio/sfx/water/"
const SILENT_DB := -70.0
const POOL := 12

var enabled := true
var _pool: Array[AudioStreamPlayer] = []
var _streams: Dictionary = {}
var _surface: AudioStreamPlayer
var _under: AudioStreamPlayer
var _glide: AudioStreamPlayer
var _last_event: Dictionary = {}
var _clock := 0.0
const MUSIC_DIR := "res://audio/music/water/"
const MUSIC_ZONES := ["glade", "grove", "lake", "finale"]
const MUSIC_DB := -15.0
var music: Dictionary = {}              ## zone -> AudioStreamPlayer
var music_weight: Dictionary = {}       ## zone -> current 0..1 weight (smoothed)
var music_enabled := true
var played: Array[String] = []   ## names of one-shots started, for tests and debugging
var _bus := "Master"


func _ready() -> void:
	if AudioServer.get_bus_index("SFX") != -1:
		_bus = "SFX"
	for i in range(POOL):
		_pool.append(_make_player())
	_surface = _make_loop("ambience_surface", -24.0)
	_under = _make_loop("ambience_underwater", SILENT_DB)
	_glide = _make_loop("water_glide", SILENT_DB)
	for z: String in MUSIC_ZONES:
		var path: String = MUSIC_DIR + "water_%s.ogg" % z
		var p := _make_player()
		p.bus = _bus
		if ResourceLoader.exists(path):
			var st := load(path) as AudioStreamOggVorbis
			if st != null:
				st = st.duplicate() as AudioStreamOggVorbis
				st.loop = true
				p.stream = st
		p.volume_db = SILENT_DB
		if p.stream != null:
			p.play()
		music[z] = p
		music_weight[z] = 0.0


func _make_player() -> AudioStreamPlayer:
	var p := AudioStreamPlayer.new()
	p.bus = _bus
	add_child(p)
	return p


func _stream(stream_name: String) -> AudioStream:
	if not _streams.has(stream_name):
		_streams[stream_name] = load(DIR + stream_name + ".wav")
	return _streams[stream_name]


func _make_loop(stream_name: String, db: float) -> AudioStreamPlayer:
	var p := _make_player()
	var s := (_stream(stream_name) as AudioStreamWAV).duplicate() as AudioStreamWAV
	s.loop_mode = AudioStreamWAV.LOOP_FORWARD
	s.loop_begin = 0
	s.loop_end = s.data.size() / (2 if s.format == AudioStreamWAV.FORMAT_16_BITS else 1)
	p.stream = s
	p.volume_db = db
	p.play()
	return p


## Loops follow the dive (0..1) and the slime's speed (px/s); called every frame by the lab.
## Zone weights for the music from the slime's world y and the dive (0..1 each, they sum to about 1).
static func zone_weights(y: float, dive: float) -> Dictionary:
	var glade := smoothstep(680.0, 880.0, y)
	var lake := smoothstep(150.0, -50.0, y)
	var grove := clampf(1.0 - glade - lake, 0.0, 1.0)
	var under := clampf(dive, 0.0, 1.0)
	return {"glade": glade * (1.0 - under), "grove": grove * (1.0 - under), "lake": lake * (1.0 - under), "finale": under}


func update_mix(dive: float, speed: float, delta: float, pos_y: float = 0.0) -> void:
	_clock += delta
	var zw := zone_weights(pos_y, dive)
	for z: String in MUSIC_ZONES:
		var w: float = lerpf(float(music_weight[z]), float(zw[z]), minf(1.0, delta * 0.8))   # about a second of crossfade
		music_weight[z] = w
		var pl: AudioStreamPlayer = music[z]
		pl.volume_db = SILENT_DB if (not enabled or not music_enabled or w < 0.003) else lerpf(SILENT_DB, MUSIC_DB, sqrt(w))
	if not enabled:
		_surface.volume_db = SILENT_DB
		_under.volume_db = SILENT_DB
		_glide.volume_db = SILENT_DB
		return
	_surface.volume_db = lerpf(-24.0, SILENT_DB, clampf(dive * 1.6, 0.0, 1.0))
	_under.volume_db = lerpf(SILENT_DB, -19.0, smoothstep(0.0, 0.8, dive))
	var glide_k := clampf(speed / 220.0, 0.0, 1.0)
	_glide.volume_db = lerpf(SILENT_DB, -26.0 + 6.0 * (1.0 - dive), pow(glide_k, 0.8))
	_glide.pitch_scale = lerpf(0.85, 1.25, glide_k)


## One-shot with a minimum gap per sound (seconds), so busy moments stay soft.
func play(sound: String, db: float = -12.0, pitch: float = 1.0, min_gap: float = 0.0) -> bool:
	if not enabled:
		return false
	if min_gap > 0.0 and _clock - float(_last_event.get(sound, -99.0)) < min_gap:
		return false
	_last_event[sound] = _clock
	for p in _pool:
		if not p.playing:
			p.stream = _stream(sound)
			p.volume_db = db
			p.pitch_scale = pitch
			p.play()
			played.append(sound)
			return true
	return false


## Stop every one-shot (the loops keep playing); handy for tests and for scene changes.
func stop_oneshots() -> void:
	for p in _pool:
		p.stop()


func plip(strength: float) -> void:
	play("water_plip_%02d" % (1 + randi() % 3), -17.0 + 4.0 * strength, randf_range(0.92, 1.08), 0.12)


func drip() -> void:
	play("water_drip_%02d" % (1 + randi() % 3), -15.0, randf_range(0.9, 1.1), 0.35)


func bubble() -> void:
	play("water_bubble_%02d" % (1 + randi() % 3), -17.0, randf_range(0.9, 1.15), 0.18)


## Absorbing food: a splash whose size follows the slime's wave strength, plus a drip.
func absorb(strength: float) -> void:
	if strength > 0.55:
		play("water_splash_large", -9.0, randf_range(0.95, 1.05), 0.2)
	else:
		play("water_splash_small", -10.0 + 3.0 * strength, randf_range(0.95, 1.1), 0.1)
	drip()


func dive() -> void:
	play("water_dive", -8.0, 1.0)


func surface() -> void:
	play("water_surface", -9.0, 1.0)
