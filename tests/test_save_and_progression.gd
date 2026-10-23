extends "res://tests/TestSuiteBase.gd"
## Tests persistent upgrades, rewards, save/load roundtrip, and corrupted save auto-recovery.

const TEST_SAVE := "user://test_slime_save.json"
const TEST_BAK := "user://test_slime_save.bak"
const TEST_TMP := "user://test_slime_save.tmp"


func _init() -> void:
	super("SaveAndProgressionSuite")


func run() -> void:
	SaveData.set_custom_paths(TEST_SAVE, TEST_BAK, TEST_TMP)
	_cleanup_files()

	_test_save_load_and_upgrades()
	_test_corrupted_primary_recovery_from_backup()
	_test_total_corruption_graceful_fallback()
	_test_malformed_fields_with_valid_checksum()

	_cleanup_files()
	SaveData.set_custom_paths(SaveData.DEFAULT_SAVE_PATH, SaveData.DEFAULT_BACKUP_PATH, SaveData.DEFAULT_TMP_PATH)
	SaveData.load_from_disk()


func _cleanup_files() -> void:
	for p in [TEST_SAVE, TEST_BAK, TEST_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _test_save_load_and_upgrades() -> void:
	SaveData.data = SaveData.create_default_data()
	assert_eq(SaveData.get_setting("music_enabled", false), true, "Music is ON by default (soundtrack ships with the game)")
	assert_eq(SaveData.get_setting("locale", ""), "ru", "Primary language is Russian ('ru') by default")

	SaveData.add_essence(150)
	assert_eq(SaveData.get_essence(), 150, "Essence credited")

	assert_true(SaveData.buy_upgrade("start_mass"), "Purchased start_mass Lv1")
	assert_eq(SaveData.get_upgrade_level("start_mass"), 1, "start_mass level is 1")
	assert_gt(SaveData.get_upgrade_bonus("start_mass"), 0.0, "start_mass bonus positive")

	assert_false(SaveData.is_mutation_unlocked("split"), "Advanced mutation 'split' starts locked")
	assert_true(SaveData.unlock_mutation("split"), "Unlocked 'split' with Essence")
	assert_true(SaveData.is_mutation_unlocked("split"), "'split' now unlocked")

	SaveData.record_creature_seen("stone_slug", 5)
	SaveData.increment_stat("armored_defeated", 5.0)
	var ach: Array = SaveData.data["achievements"]
	assert_true(ach.has("shell_cracker"), "Achievement 'shell_cracker' unlocked automatically")

	var saved_essence := SaveData.get_essence()
	SaveData.save_to_disk()

	# Wipe in-memory dictionary and reload from disk
	SaveData.data = {}
	SaveData.load_from_disk()
	assert_false(SaveData.recovered_from_corruption, "Clean save loads with zero corruption flag")
	assert_eq(SaveData.get_essence(), saved_essence, "Essence persisted across reload")
	assert_eq(SaveData.get_upgrade_level("start_mass"), 1, "Upgrade persisted across reload")
	assert_true(SaveData.is_mutation_unlocked("split"), "Mutation unlock persisted across reload")


func _test_corrupted_primary_recovery_from_backup() -> void:
	# Ensure backup holds valid state by saving twice
	SaveData.add_essence(25)
	var expected_essence := SaveData.get_essence()
	SaveData.save_to_disk()

	# Corrupt primary save file with truncated garbage JSON!
	var f := FileAccess.open(TEST_SAVE, FileAccess.WRITE)
	f.store_string("{corrupted_json_payload: [[[TRUNCATED")
	f.close()

	SaveData.load_from_disk()
	assert_true(SaveData.recovered_from_corruption, "Detected corrupted primary save")
	assert_eq(SaveData.get_essence(), expected_essence, "Successfully restored progression from .bak backup!")


func _test_total_corruption_graceful_fallback() -> void:
	# Tamper with checksum in both primary and backup
	for p in [TEST_SAVE, TEST_BAK]:
		var f := FileAccess.open(p, FileAccess.WRITE)
		f.store_string('{"schema":1,"checksum":"deadbeef","payload":"{}"}')
		f.close()

	SaveData.load_from_disk()
	assert_true(SaveData.recovered_from_corruption, "Flagged tampered save files")
	assert_eq(SaveData.get_essence(), 0, "Fell back cleanly to safe default profile without crashing")


func _test_malformed_fields_with_valid_checksum() -> void:
	# A valid envelope can still contain malformed fields from an older client.
	SaveData.data = {
		"essence": 42, "settings": {"sfx_volume": 3.0, "locale": "xx", "auto_absorb": "false"},
		"stats": {"victories": -4, "active_days": ["oops", 10, 10, -1]},
		"upgrades": {"start_mass": 999, "move_speed": "broken"},
		"unlocked_mutations": ["freeze", "unknown", 123], "unlocked_forms": "broken",
		"bestiary": {"stone_slug": 3, "tiny_mushroom": "broken", "unknown": 10},
		"selected_form": "not_owned", "achievements": [false]
	}
	assert_true(SaveData.save_to_disk(), "Malformed legacy payload written with valid checksum")
	assert_false(FileAccess.file_exists(TEST_TMP), "Atomic save consumes temporary file")
	SaveData.load_from_disk()
	assert_eq(SaveData.get_essence(), 42, "Valid currency survives field repair")
	assert_eq(SaveData.get_setting("sfx_volume"), 1.0, "Volume clamped to safe range")
	assert_eq(SaveData.get_setting("locale"), "ru", "Unknown locale repaired")
	assert_eq(SaveData.get_setting("auto_absorb"), true, "Wrong boolean type repaired")
	assert_eq(SaveData.data["stats"]["victories"], 0, "Negative stats repaired")
	assert_eq(SaveData.data["stats"]["active_days"], [10], "Malformed and duplicate days removed")
	assert_eq(SaveData.get_upgrade_level("start_mass"), 8, "Upgrade capped at configured max")
	assert_eq(SaveData.get_upgrade_level("move_speed"), 0, "Wrong upgrade type repaired")
	assert_true(SaveData.is_mutation_unlocked("freeze"), "Valid unlocked mutation preserved")
	assert_true(SaveData.is_mutation_unlocked("magnet"), "Starter mutations restored")
	assert_false(SaveData.is_mutation_unlocked("unknown"), "Unknown mutation removed")
	assert_eq(SaveData.get_creature_count("stone_slug"), 3, "Valid bestiary count preserved")
	assert_eq(SaveData.get_creature_count("tiny_mushroom"), 0, "Malformed bestiary count repaired")
	assert_eq(SaveData.data["selected_form"], "forest_drop", "Invalid equipped form repaired")
	assert_eq(SaveData.data["achievements"], [], "Invalid achievement IDs removed")
	var repaired := SaveData.sanitize_save({"settings": null, "stats": [], "upgrades": false})
	assert_eq(repaired["settings"]["locale"], "ru", "Malformed nested containers repaired")
	repaired = SaveData.sanitize_save({"essence": INF, "stats": {"peak_mass": NAN}})
	assert_eq(repaired["essence"], 0, "Non-finite currency repaired")
	assert_eq(repaired["stats"]["peak_mass"], 10.0, "Non-finite mass repaired")
