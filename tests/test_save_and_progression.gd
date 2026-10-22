extends TestSuiteBase
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

	_cleanup_files()
	SaveData.set_custom_paths(SaveData.DEFAULT_SAVE_PATH, SaveData.DEFAULT_BACKUP_PATH, SaveData.DEFAULT_TMP_PATH)
	SaveData.load_from_disk()


func _cleanup_files() -> void:
	for p in [TEST_SAVE, TEST_BAK, TEST_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))


func _test_save_load_and_upgrades() -> void:
	SaveData.data = SaveData.create_default_data()
	assert_eq(SaveData.get_setting("music_enabled", true), false, "Music is OFF by default per spec")
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
