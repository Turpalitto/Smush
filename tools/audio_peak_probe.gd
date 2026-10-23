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


func _ready() -> void:
	await get_tree().process_frame
	var master_idx := AudioServer.get_bus_index("Master")
	Audio._ensure_master_limiter()
	var rec := Audio.create_post_limiter_recorder()
	var lim_info := Audio.get_master_limiter_info()

	# A real bed under the stress, so the chimes are summed with something loud rather
	# than measured in silence.
	SaveData.set_setting("music_enabled", true)
	SaveData.set_setting("music_volume", 1.0)
	SaveData.set_setting("sfx_volume", 1.0)
	Events.settings_changed.emit()
	Audio.play_music("boss", 0.05)

	rec.set_recording_active(true)
	await get_tree().create_timer(0.4).timeout

	# Everything at once. 120 events over 1.6 s is far denser than a player can
	# physically collect, which is the point: this is the worst case, not the average.
	for i in range(120):
		match i % 4:
			0:
				Audio.play_orb_chime()
			1:
				Audio.play_sfx("absorb", 1.35)
			2:
				Audio.play_evolution((i % EvolutionStages.COUNT) + 1)
			_:
				Audio.play_sfx("hurt", 1.0)
		await get_tree().create_timer(0.013).timeout

	await get_tree().create_timer(0.6).timeout
	rec.set_recording_active(false)

	var stream := rec.get_recording()
	var result := {
		"limiter_ceiling_db": float(lim_info.get("ceiling_db", 0.0)),
		"limiter_present": int(lim_info.get("limiter_effect_index", -1)) >= 0,
		"mix_rate_hz": int(lim_info.get("mix_rate_hz", 0)),
		"recorded_sec": 0.0,
		"peak_dbfs": 0.0,
		"clipped_samples": 0,
		"samples": 0,
		"chime_window_step": Audio.chime_step(),
	}
	if stream != null:
		var data := stream.data
		var count := data.size() / 2
		var peak := 0
		var clipped := 0
		for i in range(count):
			var lo := data[i * 2]
			var hi := data[i * 2 + 1]
			var v := (hi << 8) | lo
			if v >= 32768:
				v -= 65536
			var a := absi(v)
			if a > peak:
				peak = a
			# The limiter's job is that nothing reaches full scale. Count the samples
			# that actually hit it, not the ones that merely got close.
			if a >= 32767:
				clipped += 1
		result["samples"] = count
		result["clipped_samples"] = clipped
		result["recorded_sec"] = snappedf(float(count) / float(maxi(1, stream.mix_rate)), 0.001)
		if peak > 0:
			result["peak_dbfs"] = snappedf(linear_to_db(float(peak) / 32768.0), 0.001)

	Audio.stop_music(0.05)
	var json := JSON.stringify(result, "  ")
	print("AUDIO_PEAK_PROBE " + json)
	var out_path := OS.get_environment(OUT_ENV)
	if not out_path.is_empty():
		var f := FileAccess.open(out_path, FileAccess.WRITE)
		if f != null:
			f.store_string(json + "\n")
			f.close()
	get_tree().quit(0)
