extends "res://tests/TestSuiteBase.gd"
## Unit tests for the four game modes (systems/GameModes.gd) and the way the rest of
## the game reads them.
##
## The reason this exists at all: the mode table is now the single source of truth for
## timings, damage, mass burn, boss presence and save-file record keys. A missing key
## or a drifted literal would not crash anything - it would quietly give `zen` a boss,
## or give `standard` the zen damage multiplier, and the only symptom would be a run
## that feels wrong. So every rule the brief promises is asserted here against the
## table, and the runtime behaviour is asserted in the integration suite where a live
## arena exists.


func _init() -> void:
	super("GameModesSuite")


func run() -> void:
	_test_table_is_complete()
	_test_existing_modes_are_unchanged()
	_test_zen_rules()
	_test_endless_rules()
	_test_unknown_mode_falls_back()
	_test_save_file_keeps_new_modes()
	_test_names_are_localised()


## Every mode must define every key, or a `get()` with a fallback silently invents a
## rule for one mode only.
func _test_table_is_complete() -> void:
	assert_eq(GameModes.ORDER.size(), 4, "Four modes are offered")
	assert_eq(GameModes.ORDER[0], GameModes.STANDARD, "Standard is offered first")
	for mode_id in GameModes.ORDER:
		assert_true(GameModes.is_valid(mode_id), "Mode is valid: " + mode_id)

	var reference: Array = (GameModes.MODES[GameModes.STANDARD] as Dictionary).keys()
	for mode_id in GameModes.ORDER:
		var cfg: Dictionary = GameModes.MODES[mode_id]
		var missing: Array = []
		for key in reference:
			if not cfg.has(key):
				missing.append(key)
		assert_true(missing.is_empty(), "%s defines every key (missing: %s)" % [mode_id, str(missing)])
		assert_eq(cfg.size(), reference.size(), "%s defines no extra keys" % mode_id)

	# A mode that is neither endless nor zen is a timed run and must have a boss timer.
	for mode_id in GameModes.ORDER:
		var cfg: Dictionary = GameModes.MODES[mode_id]
		if not bool(cfg["endless"]) and not bool(cfg["zen"]):
			assert_true(bool(cfg["has_boss"]), "%s has a boss" % mode_id)
			assert_gt(float(cfg["boss_time"]), 0.0, "%s schedules the boss" % mode_id)
			assert_lt(float(cfg["miniboss_time"]), float(cfg["boss_time"]),
				"%s spawns the miniboss before the boss" % mode_id)


## The two modes people already play must be byte-for-byte the old behaviour: these
## are the literals that used to live inline in ArenaController.
func _test_existing_modes_are_unchanged() -> void:
	assert_eq(GameModes.value(GameModes.STANDARD, "miniboss_time"), 165.0, "Standard miniboss at 165 s")
	assert_eq(GameModes.value(GameModes.STANDARD, "boss_time"), 270.0, "Standard boss at 270 s")
	assert_eq(GameModes.time_scale(GameModes.STANDARD), 1.0, "Standard uses unscaled time")
	assert_eq(GameModes.dash_mass_burn(GameModes.STANDARD), 0.015, "Standard keeps the 1.5% dash burn")
	assert_eq(GameModes.damage_mult(GameModes.STANDARD), 1.0, "Standard damage untouched")
	assert_eq(GameModes.hp_floor_frac(GameModes.STANDARD), 0.0, "Standard can still die")

	assert_eq(GameModes.value(GameModes.QUICK, "miniboss_time"), 80.0, "Quick miniboss at 80 s")
	assert_eq(GameModes.value(GameModes.QUICK, "boss_time"), 145.0, "Quick boss at 145 s")
	assert_eq(GameModes.time_scale(GameModes.QUICK), 1.85, "Quick keeps the 1.85x time scale")
	assert_eq(GameModes.dash_mass_burn(GameModes.QUICK), 0.015, "Quick keeps the dash burn")
	assert_eq(GameModes.damage_mult(GameModes.QUICK), 1.0, "Quick damage untouched")

	assert_false(GameModes.is_zen(GameModes.STANDARD), "Standard is not zen")
	assert_false(GameModes.is_endless(GameModes.STANDARD), "Standard is not endless")
	assert_false(GameModes.is_zen(GameModes.QUICK), "Quick is not zen")


func _test_zen_rules() -> void:
	assert_true(GameModes.is_zen(GameModes.ZEN), "Zen mode is zen")
	assert_false(GameModes.is_endless(GameModes.ZEN), "Zen is not the endless mode")

	# The brief: damage down 80%, never below 15% HP, dash costs no mass.
	assert_approx(GameModes.damage_mult(GameModes.ZEN), 0.2, 0.0001, "Zen takes 20% damage")
	assert_approx(GameModes.hp_floor_frac(GameModes.ZEN), 0.15, 0.0001, "Zen floors HP at 15%")
	assert_eq(GameModes.dash_mass_burn(GameModes.ZEN), 0.0, "Zen dash costs no mass")

	# No boss, no miniboss: a timer-driven three-phase fight is the opposite of a
	# contemplative mode, and the player ends the walk themselves.
	assert_false(GameModes.has_boss(GameModes.ZEN), "Zen has no Guardian")
	assert_false(bool(GameModes.MODES[GameModes.ZEN]["has_miniboss"]), "Zen has no miniboss")

	# Peaceful pacing: aggressive enemies arrive less often, orbs more often.
	assert_gt(float(GameModes.MODES[GameModes.ZEN]["enemy_period_mult"]), 1.5,
		"Zen thins out aggressive spawns")
	assert_lt(float(GameModes.MODES[GameModes.ZEN]["orb_period_mult"]), 1.0,
		"Zen offers more peaceful pickups")


func _test_endless_rules() -> void:
	assert_true(GameModes.is_endless(GameModes.ENDLESS), "Endless mode is endless")
	assert_false(GameModes.is_zen(GameModes.ENDLESS), "Endless is not zen")
	# The first loop must be the standard run, or the boss is being fought at a
	# difficulty it was never tuned for.
	assert_eq(GameModes.value(GameModes.ENDLESS, "boss_time"),
		GameModes.value(GameModes.STANDARD, "boss_time"), "Endless keeps the standard first boss")
	assert_eq(GameModes.value(GameModes.ENDLESS, "miniboss_time"),
		GameModes.value(GameModes.STANDARD, "miniboss_time"), "Endless keeps the standard first miniboss")
	assert_true(GameModes.has_boss(GameModes.ENDLESS), "Endless has a boss")
	# Endless is not a difficulty change: damage and mass burn stay standard.
	assert_eq(GameModes.damage_mult(GameModes.ENDLESS), 1.0, "Endless damage untouched")
	assert_eq(GameModes.hp_floor_frac(GameModes.ENDLESS), 0.0, "Endless can still die")


func _test_unknown_mode_falls_back() -> void:
	assert_eq(GameModes.normalize(""), GameModes.STANDARD, "Empty mode id falls back to standard")
	assert_eq(GameModes.normalize("hacker"), GameModes.STANDARD, "Unknown mode id falls back to standard")
	assert_false(GameModes.is_valid("hacker"), "Unknown mode is not valid")
	# And the accessors must not throw on it.
	assert_eq(GameModes.damage_mult("hacker"), 1.0, "Unknown mode reads standard damage")
	assert_false(GameModes.is_zen("hacker"), "Unknown mode is not zen")


## Records are keyed by mode id and the sanitiser used to carry its own literal list,
## so a new mode's records would have been silently dropped on the next load.
func _test_save_file_keeps_new_modes() -> void:
	var raw := {
		"standard": {"normal": {"best_time": 240.0, "best_mass": 90.0, "best_essence": 50, "victories": 1, "runs": 2}},
		"endless": {"normal": {"best_time": 0.0, "best_mass": 210.5, "best_essence": 400, "victories": 0, "runs": 3}},
		"zen": {"normal": {"best_time": 0.0, "best_mass": 130.0, "best_essence": 120, "victories": 0, "runs": 1}},
		"hacker": {"normal": {"best_time": 1.0, "best_mass": 1.0, "best_essence": 1, "victories": 1, "runs": 1}},
	}
	var clean: Dictionary = SaveData.sanitize_save({"records": raw})["records"]
	assert_true(clean.has("standard"), "Standard records survive sanitising")
	assert_true(clean.has("endless"), "Endless records survive sanitising")
	assert_true(clean.has("zen"), "Zen records survive sanitising")
	assert_false(clean.has("hacker"), "Unknown mode records are still dropped")
	assert_approx(float(clean["endless"]["normal"]["best_mass"]), 210.5, 0.001,
		"Endless keeps a mass above the old ladder ceiling")


func _test_names_are_localised() -> void:
	var prev := Loc.current_locale
	for locale in ["ru", "en"]:
		Loc.set_locale(locale)
		for mode_id in GameModes.ORDER:
			var nk := GameModes.name_key(mode_id)
			var dk := GameModes.desc_key(mode_id)
			assert_true(not nk.is_empty(), "%s has a name key" % mode_id)
			# Loc.t returns the key itself when it is missing, so this is a real check.
			assert_true(Loc.t(nk) != nk, "%s name is translated (%s)" % [mode_id, locale])
			assert_true(Loc.t(dk) != dk, "%s description is translated (%s)" % [mode_id, locale])
		# The result screen for a finished walk and the pause button must exist too.
		for key in ["result.walk", "pause.finish_walk", "hud.grove_awakened"]:
			assert_true(Loc.t(key) != key, "%s is translated (%s)" % [key, locale])
	Loc.set_locale(prev)
