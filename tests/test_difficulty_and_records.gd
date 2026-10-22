extends TestSuiteBase
## Verifies the difficulty layer (config, save migration, arena multipliers) and the
## per-mode/per-difficulty personal record table, plus the localization keys the new UI needs.

const DIFF_SAVE := "user://test_difficulty_save.json"
const DIFF_BAK := "user://test_difficulty_save.bak"
const DIFF_TMP := "user://test_difficulty_save.tmp"

const EXPECTED_ORDER: Array[String] = ["normal", "hunter", "nightmare"]


func _init() -> void:
	super("DifficultyAndRecordsSuite")


func run() -> void:
	SaveData.set_custom_paths(DIFF_SAVE, DIFF_BAK, DIFF_TMP)
	_cleanup_files()
	SaveData.data = SaveData.create_default_data()

	_test_config_shape()
	_test_save_migration_and_validation()
	_test_record_table()
	_test_record_sanitization()
	_test_difficulty_achievements()
	_test_localization_keys()

	_cleanup_files()
	SaveData.set_custom_paths(SaveData.DEFAULT_SAVE_PATH, SaveData.DEFAULT_BACKUP_PATH, SaveData.DEFAULT_TMP_PATH)
	SaveData.data = SaveData.create_default_data()
	SaveData.load_from_disk()


func _cleanup_files() -> void:
	for p in [DIFF_SAVE, DIFF_BAK, DIFF_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


# --- Config -----------------------------------------------------------------

func _test_config_shape() -> void:
	assert_eq(ConfigDB.difficulty_order, EXPECTED_ORDER, "Three difficulties declared in order")
	assert_eq(ConfigDB.get_default_difficulty_id(), "normal", "Default difficulty is 'normal'")

	var normal := ConfigDB.get_difficulty("normal")
	for key in ["essence_mult", "enemy_hp_mult", "enemy_damage_mult", "boss_hp_mult", "spawn_rate_mult"]:
		assert_eq(float(normal.get(key, -1.0)), 1.0, "Normal difficulty keeps %s at 1.0" % key)

	var hunter := ConfigDB.get_difficulty("hunter")
	var nightmare := ConfigDB.get_difficulty("nightmare")
	for key in ["essence_mult", "enemy_hp_mult", "enemy_damage_mult", "boss_hp_mult", "spawn_rate_mult"]:
		assert_gt(float(hunter.get(key, 0.0)), 1.0, "Hunter raises %s above baseline" % key)
		assert_gt(float(nightmare.get(key, 0.0)), float(hunter.get(key, 0.0)), "Nightmare exceeds Hunter on %s" % key)

	assert_eq(ConfigDB.get_difficulty("does_not_exist").get("id"), "normal", "Unknown difficulty falls back to default")
	assert_eq(ConfigDB.get_difficulty("").get("id"), "normal", "Empty difficulty falls back to default")

	# Accent colors are parsed from JSON strings and must be visible, not transparent black.
	for did in ConfigDB.difficulty_order:
		var accent := Color(str(ConfigDB.difficulties[did].get("accent", "#00000000")))
		assert_gt(accent.a, 0.9, "Accent colour of %s is opaque" % did)
		assert_true(accent.r + accent.g + accent.b > 0.3, "Accent colour of %s is not black" % did)


# --- Save integration -------------------------------------------------------

func _test_save_migration_and_validation() -> void:
	SaveData.data = SaveData.create_default_data()
	assert_eq(SaveData.get_difficulty_id(), "normal", "Fresh profile starts on Normal")
	assert_eq(SaveData.get_setting("difficulty"), "normal", "Difficulty lives in settings for persistence")

	assert_true(SaveData.set_difficulty("nightmare"), "Selecting Nightmare succeeds")
	assert_eq(SaveData.get_difficulty_id(), "nightmare", "Selection is stored")
	assert_false(SaveData.set_difficulty("impossible"), "Unknown difficulty id is rejected")
	assert_eq(SaveData.get_difficulty_id(), "nightmare", "Rejected selection does not change state")

	SaveData.save_to_disk()
	SaveData.data = {}
	SaveData.load_from_disk()
	assert_eq(SaveData.get_difficulty_id(), "nightmare", "Difficulty survives a save/load roundtrip")

	# A save written by an older client has no difficulty and no records at all.
	var legacy := SaveData.sanitize_save({"essence": 10, "settings": {"locale": "ru"}})
	assert_eq(legacy["settings"]["difficulty"], "normal", "Legacy save without difficulty defaults to Normal")
	assert_true((legacy["records"] as Dictionary).is_empty(), "Legacy save without records gets an empty table")

	var tampered := SaveData.sanitize_save({"settings": {"difficulty": "godmode"}})
	assert_eq(tampered["settings"]["difficulty"], "normal", "Tampered difficulty id is repaired")

	var wrong_type := SaveData.sanitize_save({"settings": {"difficulty": 42}})
	assert_eq(wrong_type["settings"]["difficulty"], "normal", "Non-string difficulty is repaired")

	SaveData.data = SaveData.create_default_data()


# --- Records ----------------------------------------------------------------

func _test_record_table() -> void:
	SaveData.data = SaveData.create_default_data()
	var empty := SaveData.get_record("standard", "normal")
	assert_eq(empty["best_time"], 0.0, "No record yet means no best time")
	assert_eq(empty["runs"], 0, "No record yet means zero runs")

	# A defeat still counts a run and can set mass/essence records, but never a best time.
	var defeat := SaveData.submit_run_record({
		"mode": "standard", "difficulty": "normal", "victory": false,
		"duration_sec": 95.0, "peak_mass": 40.0, "base_essence": 22
	})
	assert_eq(int(defeat["runs"]), 1, "Defeat increments the run counter")
	assert_false(bool(defeat["is_new_best_time"]), "Defeat never sets a best time")
	assert_true(bool(defeat["is_new_best_mass"]), "Defeat can set a mass record")
	assert_true(bool(defeat["is_new_best_essence"]), "Defeat can set an essence record")

	# First victory becomes the best time.
	var win1 := SaveData.submit_run_record({
		"mode": "standard", "difficulty": "normal", "victory": true,
		"duration_sec": 300.0, "peak_mass": 90.0, "base_essence": 120
	})
	assert_true(bool(win1["is_new_best_time"]), "First victory sets the best time")
	assert_true(bool(win1["first_victory"]), "First victory is flagged")
	assert_eq(float(win1["best_time"]), 300.0, "Best time stored")
	assert_eq(int(win1["victories"]), 1, "Victory counter increments")

	# Slower victory must not overwrite the record.
	var win2 := SaveData.submit_run_record({
		"mode": "standard", "difficulty": "normal", "victory": true,
		"duration_sec": 420.0, "peak_mass": 70.0, "base_essence": 80
	})
	assert_false(bool(win2["is_new_best_time"]), "Slower victory keeps the previous best")
	assert_false(bool(win2["first_victory"]), "Second victory is not a first victory")
	assert_eq(float(win2["best_time"]), 300.0, "Best time unchanged after a slower run")
	assert_eq(int(win2["victories"]), 2, "Victory counter keeps counting")

	# Faster victory overwrites it.
	var win3 := SaveData.submit_run_record({
		"mode": "standard", "difficulty": "normal", "victory": true,
		"duration_sec": 240.5, "peak_mass": 95.0, "base_essence": 130
	})
	assert_true(bool(win3["is_new_best_time"]), "Faster victory becomes the new best")
	assert_eq(float(win3["best_time"]), 240.5, "Best time updated")
	assert_eq(float(win3["best_mass"]), 95.0, "Best mass updated")
	assert_eq(int(win3["best_essence"]), 130, "Best essence updated")

	# Records are separated by difficulty and by mode.
	assert_eq(float(SaveData.get_record("standard", "hunter")["best_time"]), 0.0, "Hunter has its own empty record")
	SaveData.submit_run_record({
		"mode": "standard", "difficulty": "hunter", "victory": true,
		"duration_sec": 500.0, "peak_mass": 50.0, "base_essence": 200
	})
	assert_eq(float(SaveData.get_record("standard", "hunter")["best_time"]), 500.0, "Hunter record stored separately")
	assert_eq(float(SaveData.get_record("standard", "normal")["best_time"]), 240.5, "Normal record untouched by Hunter run")

	SaveData.submit_run_record({
		"mode": "quick", "difficulty": "normal", "victory": true,
		"duration_sec": 100.0, "peak_mass": 60.0, "base_essence": 90
	})
	assert_eq(float(SaveData.get_record("quick", "normal")["best_time"]), 100.0, "Quick mode has its own record")
	assert_eq(float(SaveData.get_record("standard", "normal")["best_time"]), 240.5, "Standard record untouched by Quick run")

	# Records survive a save/load roundtrip.
	SaveData.save_to_disk()
	SaveData.data = {}
	SaveData.load_from_disk()
	assert_eq(float(SaveData.get_record("standard", "normal")["best_time"]), 240.5, "Records persist across reload")
	assert_eq(int(SaveData.get_record("standard", "normal")["runs"]), 4, "Run counter persists across reload")
	assert_eq(int(SaveData.get_record("standard", "hunter")["runs"]), 1, "Per-difficulty run counter persists")


func _test_record_sanitization() -> void:
	# Records are keyed by dynamic ids, so they get their own validator.
	var clean := SaveData.sanitize_save({
		"records": {
			"standard": {
				"normal": {"best_time": -5.0, "best_mass": -1.0, "best_essence": -3, "victories": -2, "runs": -1},
				"hacker": {"best_time": 12.0},
				"nightmare": {"best_time": 88.0, "best_mass": 44.0, "best_essence": 55, "victories": 1, "runs": 2}
			},
			"unknown_mode": {"normal": {"best_time": 10.0}},
			"quick": "not_a_dictionary"
		}
	})
	var records: Dictionary = clean["records"]
	assert_true(records.has("standard"), "Known mode preserved")
	assert_false((records["standard"] as Dictionary).has("hacker"), "Unknown difficulty removed")
	assert_false(records.has("unknown_mode"), "Unknown mode removed")
	assert_false(records.has("quick"), "Wrong-typed mode container removed")
	var norm: Dictionary = records["standard"]["normal"]
	assert_eq(float(norm["best_time"]), 0.0, "Negative best time clamped")
	assert_eq(float(norm["best_mass"]), 0.0, "Negative best mass clamped")
	assert_eq(int(norm["best_essence"]), 0, "Negative essence clamped")
	assert_eq(int(norm["runs"]), 0, "Negative run count clamped")
	var nm: Dictionary = records["standard"]["nightmare"]
	assert_eq(float(nm["best_time"]), 88.0, "Valid nightmare record preserved")
	assert_eq(int(nm["runs"]), 2, "Valid run count preserved")

	assert_true((SaveData.sanitize_save({"records": "garbage"})["records"] as Dictionary).is_empty(), "Wrong-typed records container dropped")
	assert_true((SaveData.sanitize_save({"records": {"standard": []}})["records"] as Dictionary).is_empty(), "Empty mode table dropped")


func _test_difficulty_achievements() -> void:
	SaveData.data = SaveData.create_default_data()
	assert_eq(int(SaveData.data["stats"]["hunter_victories"]), 0, "Hunter clear counter starts at zero")
	assert_eq(int(SaveData.data["stats"]["nightmare_victories"]), 0, "Nightmare clear counter starts at zero")

	# Clearing the default difficulty must not count towards the harder clears.
	SaveData.submit_run_record({
		"mode": "standard", "difficulty": "normal", "victory": true,
		"duration_sec": 200.0, "peak_mass": 30.0, "base_essence": 50
	})
	assert_eq(int(SaveData.data["stats"]["hunter_victories"]), 0, "Normal clear does not count as a Hunter clear")
	assert_false((SaveData.data["achievements"] as Array).has("hunter_clear"), "Hunter achievement still locked")

	SaveData.submit_run_record({
		"mode": "standard", "difficulty": "hunter", "victory": true,
		"duration_sec": 300.0, "peak_mass": 30.0, "base_essence": 50
	})
	assert_eq(int(SaveData.data["stats"]["hunter_victories"]), 1, "Hunter clear counted")
	assert_true((SaveData.data["achievements"] as Array).has("hunter_clear"), "Hunter clear unlocks its achievement")

	# A defeat on Nightmare must not count as a clear.
	SaveData.submit_run_record({
		"mode": "standard", "difficulty": "nightmare", "victory": false,
		"duration_sec": 120.0, "peak_mass": 20.0, "base_essence": 30
	})
	assert_eq(int(SaveData.data["stats"]["nightmare_victories"]), 0, "Nightmare defeat is not a clear")
	assert_false((SaveData.data["achievements"] as Array).has("nightmare_clear"), "Nightmare achievement still locked")

	SaveData.submit_run_record({
		"mode": "standard", "difficulty": "nightmare", "victory": true,
		"duration_sec": 400.0, "peak_mass": 40.0, "base_essence": 60
	})
	assert_true((SaveData.data["achievements"] as Array).has("nightmare_clear"), "Nightmare clear unlocks its achievement")

	# The new stat keys must survive save sanitization, otherwise achievements regress on reload.
	var reloaded := SaveData.sanitize_save(SaveData.data)
	assert_eq(int(reloaded["stats"]["hunter_victories"]), 1, "Hunter clear counter survives sanitization")
	assert_eq(int(reloaded["stats"]["nightmare_victories"]), 1, "Nightmare clear counter survives sanitization")


# --- Localization -----------------------------------------------------------

func _test_localization_keys() -> void:
	var previous := str(SaveData.get_setting("locale", "ru"))
	var keys: Array[String] = [
		"difficulty.title",
		"difficulty.normal.name", "difficulty.normal.desc",
		"difficulty.hunter.name", "difficulty.hunter.desc",
		"difficulty.nightmare.name", "difficulty.nightmare.desc",
		"difficulty.essence_bonus", "difficulty.record_line", "difficulty.no_record",
		"result.difficulty", "result.record_line", "result.new_record", "result.new_best_mass",
		"ach.hunter_clear.name", "ach.hunter_clear.desc",
		"ach.nightmare_clear.name", "ach.nightmare_clear.desc"
	]
	for loc_code in ["ru", "en"]:
		SaveData.set_setting("locale", loc_code)
		for key in keys:
			assert_true(Loc.t(key) != key, "%s has a translation for '%s'" % [loc_code.to_upper(), key])
		for did in ConfigDB.difficulty_order:
			var nk := str(ConfigDB.difficulties[did].get("name_key", ""))
			assert_true(Loc.t(nk) != nk, "%s names difficulty '%s'" % [loc_code.to_upper(), did])

	SaveData.set_setting("locale", previous)
	assert_eq(Loc.t("difficulty.essence_bonus", {"mult": "×1.4"}), "Эссенция ×1.4" if previous == "ru" else "Essence ×1.4",
		"Essence multiplier placeholder is substituted")
