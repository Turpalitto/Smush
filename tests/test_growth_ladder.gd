extends "res://tests/TestSuiteBase.gd"
## Unit tests for the fifteen-stage growth ladder (systems/EvolutionStages.gd).
##
## The ladder is the thing the player is supposed to *feel*: fifteen visible changes
## to the character and to the forest, spread over one run. Every one of those
## claims is checked here rather than eyeballed in a screenshot, because the two
## failure modes that actually happened during development were both invisible at a
## glance: a stage that was a copy of its neighbour (growth stalls for a while) and
## a stage whose hue jumped backwards, which made the arc read as noise instead of
## as progression.


func _init() -> void:
	super("GrowthLadderSuite")


func run() -> void:
	_test_ladder_shape()
	_test_every_stage_is_distinct()
	_test_hue_arc_is_monotonic()
	_test_growth_is_continuous()
	_test_environment_follows_growth()
	_test_names_are_localised()
	_test_each_stage_has_its_own_bell()


func _test_ladder_shape() -> void:
	assert_eq(EvolutionStages.COUNT, 15, "Ladder has fifteen stages")
	assert_eq(EvolutionStages.MASS_KEYS.size(), 15, "One mass threshold per stage")
	assert_eq(EvolutionStages.STAGES.size(), 15, "One look per stage")

	# Thresholds must be strictly increasing, otherwise a stage can never be reached.
	var strictly_rising := true
	for i in range(1, EvolutionStages.MASS_KEYS.size()):
		if EvolutionStages.MASS_KEYS[i] <= EvolutionStages.MASS_KEYS[i - 1]:
			strictly_rising = false
	assert_true(strictly_rising, "Mass thresholds are strictly increasing")

	# Every stage must be reachable inside a normal run. This assertion used to read
	# "<= 128" against a comment claiming runs peak at 105-130, and it passed while
	# the top stage was in fact a lottery: four winning runs peaked at 102.4, 108.8,
	# 111.5 and 121.4, so a threshold of 104 was missed by the weakest of them. The
	# bound is now the lowest measured peak with a little room, so retuning the
	# ladder upwards fails here instead of shipping a crown nobody sees.
	assert_eq(EvolutionStages.MASS_KEYS[0], 10.0, "Stage 1 starts at the spawn mass")
	assert_lte(EvolutionStages.MASS_KEYS[14], 100.0, "Stage 15 sits under the weakest measured run")
	assert_gte(EvolutionStages.MASS_KEYS[14], 85.0, "Stage 15 is not handed out in the first minute")

	# stage_for_mass must actually walk all fifteen rungs.
	var seen := {}
	for m in range(0, 141):
		seen[EvolutionStages.stage_for_mass(float(m))] = true
	assert_eq(seen.size(), 15, "A 0..140 mass sweep visits every stage")
	assert_eq(EvolutionStages.stage_for_mass(5.0), 1, "Mass below spawn clamps to stage 1")
	assert_eq(EvolutionStages.stage_for_mass(999.0), 15, "Huge mass clamps to stage 15")


func _test_every_stage_is_distinct() -> void:
	## Two independent measures of "the character changed":
	##  - the ornament vector (what is drawn around the body), and
	##  - the body colour (what the body is made of).
	## A stage has to move at least one of them meaningfully, and no two adjacent
	## stages may be identical.
	const ORNAMENTS := ["glow", "sigil", "crown", "halo", "wings", "horns", "motes", "petals"]
	for i in range(EvolutionStages.COUNT - 1):
		var a: Dictionary = EvolutionStages.STAGES[i]
		var b: Dictionary = EvolutionStages.STAGES[i + 1]
		var orn_delta := 0.0
		for k: String in ORNAMENTS:
			orn_delta += absf(float(a[k]) - float(b[k]))
		var col_delta := _col_dist(Color(str(a["body"])), Color(str(b["body"])))
		var total := orn_delta + col_delta * 3.0
		assert_gt(total, 0.10, "Stage %d -> %d changes the character" % [i + 1, i + 2])

	# And the ladder as a whole must end somewhere completely different from spawn.
	var first: Dictionary = EvolutionStages.look_at(1.0)
	var last: Dictionary = EvolutionStages.look_at(15.0)
	assert_gt(_col_dist(first["body_c"] as Color, last["body_c"] as Color), 0.25,
		"Stage 15 body colour is far from stage 1")
	assert_gt(float(last["glow"]) - float(first["glow"]), 0.5, "Stage 15 glows much more than stage 1")
	assert_gt(float(last["sigil"]) - float(first["sigil"]), 0.8, "The sigil only appears late in the ladder")


func _test_hue_arc_is_monotonic() -> void:
	## The ladder is a hue arc: green -> aqua -> blue -> violet -> magenta -> gold.
	## Adjacent stages must not jump more than a quarter turn, which is what a
	## stray palette entry looks like. This test exists because stage 9 was once a
	## saturated green sitting between two violets.
	var prev_h := -1.0
	for i in range(EvolutionStages.COUNT):
		var c := Color(str(EvolutionStages.STAGES[i]["body"]))
		var h := c.h
		if prev_h >= 0.0:
			var d := absf(h - prev_h)
			d = minf(d, 1.0 - d)
			assert_lt(d, 0.26, "Hue step %d -> %d is a smooth step, not a jump" % [i, i + 1])
		prev_h = h


func _test_growth_is_continuous() -> void:
	## `growth_t` is what the visuals interpolate on. It must never move by more
	## than a fraction of a stage for a small mass step, otherwise growth would pop.
	var prev := EvolutionStages.t_for_mass(10.0)
	assert_eq(prev, 1.0, "Spawn mass is exactly stage 1")
	var max_jump := 0.0
	var m := 10.0
	while m <= 128.0:
		var t := EvolutionStages.t_for_mass(m)
		assert_gte(t, prev - 0.0001, "growth_t never goes backwards")
		max_jump = maxf(max_jump, t - prev)
		prev = t
		m += 0.25
	assert_lt(max_jump, 0.20, "growth_t advances smoothly with mass")
	assert_eq(EvolutionStages.t_for_mass(128.0), 15.0, "Top mass is exactly stage 15")
	assert_eq(EvolutionStages.t_for_mass(500.0), 15.0, "growth_t clamps at the top")

	# The HUD ring value stays in 0..1 for every mass.
	var ring_ok := true
	for mm in range(5, 200):
		var p := EvolutionStages.progress_to_next(float(mm))
		if p < 0.0 or p > 1.0:
			ring_ok = false
	assert_true(ring_ok, "Stage progress stays within 0..1")
	# At the top of the ladder the bar must read full, not empty: t clamps to COUNT,
	# so the old implementation returned 0 at mass 104+ while the label said 15/15.
	var top_mass: float = EvolutionStages.MASS_KEYS[EvolutionStages.COUNT - 1]
	assert_approx(EvolutionStages.progress_to_next(top_mass), 1.0, 0.001,
		"Final stage shows a full growth bar")
	assert_approx(EvolutionStages.progress_to_next(top_mass + 40.0), 1.0, 0.001,
		"Growth bar stays full past the last threshold")


func _test_environment_follows_growth() -> void:
	## The forest has to react to the same number the body does.
	var prev := -1.0
	var monotonic := true
	for mm in range(10, 130):
		var e := EvolutionStages.env_for_mass(float(mm))
		if e < prev - 0.0001:
			monotonic = false
		prev = e
	assert_true(monotonic, "World bloom never goes backwards as the slime grows")
	assert_eq(EvolutionStages.env_for_mass(10.0), 0.0, "The forest starts cold")
	assert_eq(EvolutionStages.env_for_mass(128.0), 1.0, "The forest is fully awake at stage 15")


func _test_names_are_localised() -> void:
	## Loc.t() falls back to the key, so a missing stage name shows up in the HUD as
	## "stage.7" rather than as an error. Check the actual JSON, not the key format.
	var ru := _load_strings("res://resources/localization/ru.json")
	var en := _load_strings("res://resources/localization/en.json")
	for i in range(1, EvolutionStages.COUNT + 1):
		var key := "stage.%d" % i
		assert_true(ru.has(key) and not str(ru[key]).is_empty(), "ru.json has %s" % key)
		assert_true(en.has(key) and not str(en[key]).is_empty(), "en.json has %s" % key)
		assert_eq(EvolutionStages.name_key_for_stage(i), key, "Stage %d reports its own name key" % i)


func _test_each_stage_has_its_own_bell() -> void:
	## Every rung is a reward, so every rung needs its own sound.
	##
	## This guards a real regression: the evolution sound used to be one file played
	## at `0.82 * 2^((stage-1)*1.5/12)`, and AudioManager clamps pitch_scale to 1.75,
	## which that curve reaches at stage 10 - so stages 10-15 were audibly identical
	## while the code read as if it were rising. The bells are generated by
	## tools/generate_evolution_bells.py; the tail grows with the stage, so a
	## generator that wrote the same file fifteen times fails here.
	var lengths: Array[float] = []
	for i in range(1, EvolutionStages.COUNT + 1):
		var path := "res://audio/sfx/evo_%02d.wav" % i
		assert_true(FileAccess.file_exists(path), "Stage %d has its own bell (%s)" % [i, path])
		var stream := AssetRegistry.get_wav_stream(path, false)
		assert_true(stream != null, "Stage %d bell loads as audio" % i)
		lengths.append(0.0 if stream == null else stream.get_length())

	var rising := true
	for i in range(1, lengths.size()):
		if lengths[i] <= lengths[i - 1]:
			rising = false
	assert_true(rising, "Each bell rings longer than the one before it")
	assert_gt(lengths[EvolutionStages.COUNT - 1], 1.0, "The final bell has a real tail")


func _col_dist(a: Color, b: Color) -> float:
	## Godot's Color has no distance_to(); this is the straight RGB distance.
	return Vector3(a.r - b.r, a.g - b.g, a.b - b.b).length()


func _load_strings(path: String) -> Dictionary:
	var f := FileAccess.open(path, FileAccess.READ)
	if f == null:
		return {}
	var parsed: Variant = JSON.parse_string(f.get_as_text())
	if typeof(parsed) != TYPE_DICTIONARY:
		return {}
	var out: Dictionary = parsed.get("strings", {})
	return out
