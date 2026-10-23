extends "res://tests/TestSuiteBase.gd"
## Tests for the collection chimes and the zen bed (tools/generate_orb_chimes.py,
## tools/generate_music.py, systems/AudioManager.gd).
##
## "It plays a rising pentatonic line" is a claim about two different things: the eight
## files must actually be eight different pitches in the right order, and the ladder
## must actually step through them while the player collects and reset when they stop.
## The first is checked by measuring the audio, not by trusting the generator's print
## output; the second by driving the ladder directly.

const CHIME_COUNT := 8
## C major pentatonic, C5 -> E6, matching tools/generate_orb_chimes.py.
const EXPECTED_HZ: Array[float] = [
	523.25, 587.33, 659.25, 783.99, 880.00, 1046.50, 1174.66, 1318.51,
]


func _init() -> void:
	super("AudioChimesSuite")


func run() -> void:
	_test_eight_notes_exist_and_decode()
	_test_notes_are_actually_pitched()
	_test_ladder_steps_and_resets()
	_test_zen_track()


func _chime_path(i: int) -> String:
	return "res://audio/sfx/orb_chime_%02d.wav" % (i + 1)


func _load_mono(path: String) -> PackedFloat32Array:
	## Read with AudioStreamWAV.load_from_file, not through AssetRegistry: the editor
	## import converts these WAVs to QOA (format 3), so the imported resource is
	## compressed and cannot be measured as PCM. The on-disk file is what the
	## generator wrote and what a raw .pck decodes, and that is what has to be in tune.
	var stream := AudioStreamWAV.load_from_file(path)
	var out := PackedFloat32Array()
	if stream == null:
		return out
	var bytes := stream.data
	var count := bytes.size() / 2
	out.resize(count)
	for i in range(count):
		# 16-bit little-endian mono, the format every file in audio/sfx uses.
		var lo := bytes[i * 2]
		var hi := bytes[i * 2 + 1]
		var v := (hi << 8) | lo
		if v >= 32768:
			v -= 65536
		out[i] = float(v) / 32768.0
	return out


func _goertzel(samples: PackedFloat32Array, freq: float, sr: float) -> float:
	## Energy at one frequency. Cheaper and far more precise than a full FFT for the
	## single question "is this file that note".
	var w := TAU * freq / sr
	var c := 2.0 * cos(w)
	var s1 := 0.0
	var s2 := 0.0
	for i in range(samples.size()):
		var s0 := samples[i] + c * s1 - s2
		s2 = s1
		s1 = s0
	var re := s1 - s2 * cos(w)
	var im := s2 * sin(w)
	return sqrt(re * re + im * im)


func _test_eight_notes_exist_and_decode() -> void:
	for i in range(CHIME_COUNT):
		var path := _chime_path(i)
		assert_true(FileAccess.file_exists(path), "Chime file exists: " + path)
		var stream := AssetRegistry.get_wav_stream(path, false)
		assert_true(stream != null, "Chime decodes: %d" % (i + 1))
		if stream == null:
			continue
		# The shipped file must be plain PCM: QOA would be fine for playback but it
		# would mean the on-disk asset is lossy, and these are 27 KB each.
		var raw := AudioStreamWAV.load_from_file(path)
		assert_true(raw != null, "Chime %d reads as a raw WAV" % (i + 1))
		if raw != null:
			assert_eq(raw.format, AudioStreamWAV.FORMAT_16_BITS, "Chime %d is 16-bit PCM" % (i + 1))
			assert_eq(raw.mix_rate, 22050, "Chime %d is 22050 Hz" % (i + 1))
			assert_false(raw.stereo, "Chime %d is mono" % (i + 1))
		# Long enough to have a tail, short enough to fire many times a second.
		assert_gt(stream.get_length(), 0.45, "Chime %d is long enough to hear" % (i + 1))
		assert_lt(stream.get_length(), 1.2, "Chime %d is short enough to overlap" % (i + 1))


func _test_notes_are_actually_pitched() -> void:
	## Each file must be its own note. Checked against the neighbouring semitone in the
	## scale: the energy at the intended pitch has to beat both neighbours by a clear
	## margin, which also catches a file that was accidentally left as a copy.
	for i in range(CHIME_COUNT):
		var samples := _load_mono(_chime_path(i))
		assert_gt(float(samples.size()), 1000.0, "Chime %d has samples" % (i + 1))
		if samples.size() < 1000:
			continue
		var sr := 22050.0
		var target := EXPECTED_HZ[i]
		var at_target := _goertzel(samples, target, sr)
		# Absolute floor: a silent or near-silent file would otherwise pass the
		# neighbour comparisons below by being quiet at every frequency.
		assert_gt(at_target, 100.0, "Chime %d carries real energy at its note" % (i + 1))

		if i > 0:
			var below := _goertzel(samples, EXPECTED_HZ[i - 1], sr)
			assert_gt(at_target, below * 1.15,
				"Chime %d is above the previous note, not a copy of it" % (i + 1))
		if i < CHIME_COUNT - 1:
			var above := _goertzel(samples, EXPECTED_HZ[i + 1], sr)
			assert_gt(at_target, above * 1.15,
				"Chime %d is below the next note, not a copy of it" % (i + 1))


func _test_ladder_steps_and_resets() -> void:
	## The window is what turns eight files into a phrase: inside it the ladder climbs,
	## outside it restarts. Both halves are asserted, because a ladder that never
	## resets would sit on the top note forever after eight pickups.
	Audio._chime_window = 0.0
	Audio._chime_step = 0

	Audio.play_orb_chime()
	assert_eq(Audio.chime_step(), 0, "The first pickup plays the bottom note")

	var steps: Array[int] = []
	for i in range(1, CHIME_COUNT):
		Audio.play_orb_chime()
		steps.append(Audio.chime_step())
	var rising := true
	for i in range(1, steps.size()):
		if steps[i] != steps[i - 1] + 1:
			rising = false
	assert_true(rising, "Consecutive pickups climb the scale one note at a time")
	assert_eq(Audio.chime_step(), CHIME_COUNT - 1, "Seven more pickups reach the top note")

	# One more inside the window wraps to the bottom rather than going out of range.
	Audio.play_orb_chime()
	assert_eq(Audio.chime_step(), 0, "The ladder wraps at the top of the scale")

	# A pause longer than the window restarts the phrase.
	Audio.play_orb_chime()
	Audio.play_orb_chime()
	assert_gt(float(Audio.chime_step()), 0.0, "The ladder is mid-scale before the pause")
	Audio._chime_window = 0.0
	Audio.play_orb_chime()
	assert_eq(Audio.chime_step(), 0, "A pause longer than the window restarts at the bottom")

	# The event is a real, registered sound event with its own level.
	assert_true(Audio.SFX_PATHS.has("absorb"), "The fallback blip still exists")
	assert_true(Audio.EVENT_DB_OFFSETS.has("orb_chime"), "Chimes have their own level")
	assert_approx(float(Audio.EVENT_DB_OFFSETS["orb_chime"]), -9.5, 0.001,
		"Chimes sit at -9.5 dB")


func _test_zen_track() -> void:
	var path := "res://audio/music/theme_zen.ogg"
	assert_true(FileAccess.file_exists(path), "Zen music file exists")
	var stream := AssetRegistry.get_audio_stream(path, true)
	assert_true(stream != null, "Zen music decodes")
	if stream != null:
		# A 32 s loop: long enough that the seam is rare, short enough to ship.
		assert_gt(stream.get_length(), 20.0, "Zen loop is at least 20 s")
		assert_lt(stream.get_length(), 60.0, "Zen loop is not needlessly long")
	assert_eq(GameModes.music_for(GameModes.ZEN), "zen", "Zen mode asks for the zen track")
	assert_eq(GameModes.music_for(GameModes.STANDARD), "run", "Standard mode keeps the run track")
	assert_eq(GameModes.music_for(GameModes.ENDLESS), "run", "Endless mode keeps the run track")
	# Every mode's requested track must actually be a track the manager knows.
	for mode_id in GameModes.ORDER:
		var track := GameModes.music_for(mode_id)
		assert_true(Audio.MUSIC_TRACKS.has(track), "%s resolves to a known track (%s)" % [mode_id, track])
		assert_true(FileAccess.file_exists(str(Audio.MUSIC_TRACKS[track])),
			"%s track file exists (%s)" % [mode_id, track])
