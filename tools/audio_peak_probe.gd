extends Node
## Stress probe for the Master limiter, used to answer one question with a measurement
## rather than an argument: can the collection chimes push the mix over the ceiling?
##
## The automated playthrough records the boss window, which is a good test of the loud
## sources (music, boss telegraphs, damage) but a poor test of the chimes, because
## whether an orb happens to be swallowed during that window is chance. This probe
## fires everything at once on purpose: the boss theme at full level, all eight chimes
## as fast as the ladder allows, evolution bells and the loud one-shots.
##
## Headless cannot be used - AudioManager returns before touching a player when there
## is no audio device - so this scene must be run with a real window.
##
##   AUDIO_PROBE_OUT   output JSON path (optional; prints to stdout regardless)

const OUT_ENV := "AUDIO_PROBE_OUT"
const SR_EXPECTED := 48000

## The probe needs a loud bed, so it turns the music and SFX sliders up. Those
## settings live in the player's real save, so every run of this tool used to
## leave the game with music and SFX at 100 % — a diagnostic quietly editing the
## thing it was measuring. The previous values are captured here and put back
## before the process exits.
const TOUCHED_SETTINGS := ["music_enabled", "music_volume", "sfx_volume"]

var _prev_settings: Dictionary = {}


func _ready() -> void:
	await get_tree().process_frame
	var master_idx := AudioServer.get_bus_index("Master")
	Audio._ensure_master_limiter()
	# A tap BEFORE the limiter as well as after it. The post-limiter peak alone says
	# only that the ceiling held; it cannot say how much harder the limiter had to
	# work to hold it, and a continuous layer can cost headroom without ever moving
	# that number. The difference between the two peaks is the gain reduction.
	var pre_rec := AudioEffectRecord.new()
	AudioServer.add_bus_effect(master_idx, pre_rec, 0)
	var rec := Audio.create_post_limiter_recorder()
	var lim_info := Audio.get_master_limiter_info()

	# A real bed under the stress, so the chimes are summed with something loud rather
	# than measured in silence.
	for key in TOUCHED_SETTINGS:
		_prev_settings[key] = SaveData.get_setting(key, null)
	SaveData.set_setting("music_enabled", true)
	SaveData.set_setting("music_volume", 1.0)
	SaveData.set_setting("sfx_volume", 1.0)
	Events.settings_changed.emit()
	Audio.play_music("boss", 0.05)

	# The grove bed at full growth, and settled immediately rather than after its
	# usual 12 s swell. Unlike a one-shot this layer is present for the whole
	# recording, so it is the only source in the mix that reduces headroom for
	# everything else simply by existing. AUDIO_PROBE_GROVE=0 runs the same stress
	# without it, which is the only way to price the layer.
	var grove_on := OS.get_environment("AUDIO_PROBE_GROVE") != "0"
	if grove_on:
		Audio._start_grove()
		Audio._grove_env = 1.0
		Audio._advance_grove(30.0)

	rec.set_recording_active(true)
	pre_rec.set_recording_active(true)
	await get_tree().create_timer(0.4).timeout

	# Everything at once. 120 events over 1.6 s is far denser than a player can
	# physically collect, which is the point: this is the worst case, not the average.
	for i in range(120):
		# The wonder chord is in the rotation on purpose. It is the loudest non-combat
		# event in the game (-6 dB, against the chime's -9.5) and it fires a two-second
		# bell triad, so if anything is going to push the limiter it is this summed with
		# the boss theme. 24 of them in 1.6 s is absurd — a real run meets a handful —
		# which is the point: the probe measures the worst case, not the average.
		match i % 5:
			0:
				Audio.play_orb_chime()
			1:
				Audio.play_sfx("absorb", 1.35)
			2:
				Audio.play_evolution((i % EvolutionStages.COUNT) + 1)
			3:
				Audio.play_wonder_chime(i % Audio.WONDER_CHIME_COUNT)
			_:
				Audio.play_sfx("hurt", 1.0)
		await get_tree().create_timer(0.013).timeout

	await get_tree().create_timer(0.6).timeout
	rec.set_recording_active(false)
	pre_rec.set_recording_active(false)

	var stream := rec.get_recording()
	var pre_stream := pre_rec.get_recording()
	var result := {
		"limiter_ceiling_db": float(lim_info.get("ceiling_db", 0.0)),
		"limiter_present": int(lim_info.get("limiter_effect_index", -1)) >= 0,
		"mix_rate_hz": int(lim_info.get("mix_rate_hz", 0)),
		"recorded_sec": 0.0,
		"peak_dbfs": 0.0,
		"clipped_samples": 0,
		"samples": 0,
		"chime_window_step": Audio.chime_step(),
		"grove_on": grove_on,
		"grove_db": snappedf(Audio.grove_db(), 0.001),
		"grove_env": snappedf(Audio.grove_env(), 0.001),
	}
	var post := _peak_of(stream)
	var pre := _peak_of(pre_stream)
	result["samples"] = int(post["samples"])
	result["clipped_samples"] = int(post["clipped"])
	result["recorded_sec"] = snappedf(float(int(post["samples"])) / float(maxi(1, SR_EXPECTED)), 0.001)
	result["peak_dbfs"] = post["dbfs"]
	result["pre_limiter_peak_dbfs"] = pre["dbfs"]
	result["limiter_gain_reduction_db"] = snappedf(float(pre["dbfs"]) - float(post["dbfs"]), 0.001)
	result["pre_limiter_rms_dbfs"] = pre["rms_dbfs"]
	result["post_limiter_rms_dbfs"] = post["rms_dbfs"]

	Audio.stop_music(0.05)
	_restore_settings()
	var json := JSON.stringify(result, "  ")
	print("AUDIO_PEAK_PROBE " + json)
	var out_path := OS.get_environment(OUT_ENV)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(json + "\n")
			f.close()
	get_tree().quit(0)


func _restore_settings() -> void:
	## Put the player's audio settings back exactly as they were.
	##
	## `null` means the key was absent, and writing `null` back would leave a
	## literal null in the save, so an absent key is erased instead. This runs on
	## the way out as well as from `_exit_tree`, because a probe that quits early
	## must not be the reason the game suddenly plays at full volume.
	for key in TOUCHED_SETTINGS:
		if not _prev_settings.has(key):
			continue
		var prev: Variant = _prev_settings[key]
		if prev == null:
			var s: Dictionary = SaveData.data.get("settings", {})
			s.erase(key)
		else:
			SaveData.set_setting(key, prev)
	_prev_settings.clear()
	SaveData.save_to_disk()
	Events.settings_changed.emit()


func _exit_tree() -> void:
	if not _prev_settings.is_empty():
		_restore_settings()


func _peak_of(stream: AudioStreamWAV) -> Dictionary:
	## Peak, full-scale hits and RMS of one 16-bit recording.
	##
	## RMS is here because the peak cannot price a continuous layer: a pre-limiter
	## capture is 16-bit, so anything above full scale is already clipped in the
	## buffer and the peak saturates at 0 dBFS. The average does not clip, so the
	## energy the bed adds shows up there even when every peak is pinned.
	if stream == null:
		return {"samples": 0, "clipped": 0, "dbfs": -120.0, "rms_dbfs": -120.0}
	var data := stream.data
	var count := data.size() / 2
	var peak := 0
	var clipped := 0
	var sum_sq := 0.0
	for i in range(count):
		var lo := data[i * 2]
		var hi := data[i * 2 + 1]
		var v := (hi << 8) | lo
		if v >= 32768:
			v -= 65536
		var a := absi(v)
		sum_sq += float(v) * float(v)
		if a > peak:
			peak = a
		# The limiter's job is that nothing reaches full scale. Count the samples that
		# actually hit it, not the ones that merely got close.
		if a >= 32767:
			clipped += 1
	var dbfs := -120.0
	if peak > 0:
		dbfs = snappedf(linear_to_db(float(peak) / 32768.0), 0.001)
	var rms := 0.0
	if count > 0:
		rms = snappedf(linear_to_db(sqrt(sum_sq / float(count)) / 32768.0), 0.001)
	return {"samples": count, "clipped": clipped, "dbfs": dbfs, "rms_dbfs": rms}
