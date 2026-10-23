extends Node
## Persistent local save & progression manager (Autoload: SaveData).
## Features atomic writes, .bak backup mirror, SHA-256 integrity verification,
## and automatic recovery from corrupted or truncated save files.

const SAVE_VERSION: int = 1
const DEFAULT_SAVE_PATH: String = "user://slime_rush_save.json"
const DEFAULT_BACKUP_PATH: String = "user://slime_rush_save.bak"
const DEFAULT_TMP_PATH: String = "user://slime_rush_save.tmp"
const INTEGRITY_SALT: String = "SlimeRushEvo_v1_Integrity"

var save_path: String = DEFAULT_SAVE_PATH
var backup_path: String = DEFAULT_BACKUP_PATH
var tmp_path: String = DEFAULT_TMP_PATH

var data: Dictionary = {}
var recovered_from_corruption: bool = false


func _ready() -> void:
	ConfigDB.load_all()
	load_from_disk()


func create_default_data() -> Dictionary:
	var default_mutations: Array[String] = []
	for mid in ConfigDB.mutation_order:
		var mcfg: Dictionary = ConfigDB.mutations[mid]
		if bool(mcfg.get("unlocked_by_default", true)):
			default_mutations.append(mid)

	var upg_levels: Dictionary = {}
	for uid in ConfigDB.upgrade_order:
		upg_levels[uid] = 0

	var now_unix: int = int(Time.get_unix_time_from_system())
	return {
		"version": SAVE_VERSION,
		"essence": 0,
		"upgrades": upg_levels,
		"unlocked_mutations": default_mutations,
		"bestiary": {},
		"unlocked_forms": ["forest_drop"],
		"selected_form": "forest_drop",
		"unlocked_trails": ["default_gel"],
		"selected_trail": "default_gel",
		"achievements": [],
		"owned_skus": [],
		"no_ads": false,
		"records": {},
		"stats": {
			"total_runs": 0,
			"victories": 0,
			"bosses_defeated": 0,
			"boss_encounters": 0,
			"total_absorbed": 0,
			"total_mutations_picked": 0,
			"total_synergies_unlocked": 0,
			"armored_defeated": 0,
			"hunter_victories": 0,
			"nightmare_victories": 0,
			"peak_mass": 10.0,
			"total_playtime_sec": 0.0,
			"session_count": 0,
			"session_time_sec": 0.0,
			"finished_run_count": 0,
			"finished_run_time_sec": 0.0,
			"tutorial_starts": 0,
			"tutorial_completions": 0,
			"rewarded_started": 0,
			"revenue_verified": false,
			"tutorial_completed": false,
			"first_launch_recorded": false,
			"first_launch_unix": now_unix,
			"active_days": [int(now_unix / 86400)],
			"rewarded_offered": 0,
			"rewarded_completed": 0,
			"revenue_usd_total": 0.0
		},
		"settings": {
			"sfx_volume": 0.85,
			"music_volume": 0.55,
			"music_enabled": true,
			"joystick_mode": "floating",
			"auto_absorb": true,
			"haptics_enabled": true,
			"fx_quality": "high",
			"locale": "ru",
			"difficulty": "normal",
			"analytics_consent": false
		}
	}


func set_custom_paths(primary: String, backup: String, tmp: String) -> void:
	save_path = primary
	backup_path = backup
	tmp_path = tmp


func _compute_checksum(payload_json: String) -> String:
	return (payload_json + "|" + INTEGRITY_SALT).sha256_text()


func save_to_disk() -> bool:
	if data.is_empty():
		data = create_default_data()
	var payload_json := JSON.stringify(data)
	var envelope := {
		"schema": SAVE_VERSION,
		"checksum": _compute_checksum(payload_json),
		"payload": payload_json
	}
	var raw_out := JSON.stringify(envelope, "\t")

	var f := FileAccess.open(tmp_path, FileAccess.WRITE)
	if f == null:
		return false
	f.store_string(raw_out)
	f.flush()
	f.close()

	# Copy previous valid primary save to backup before replacing
	if FileAccess.file_exists(save_path):
		var prev := FileAccess.get_file_as_string(save_path)
		if _parse_and_verify(prev) != null:
			var bf := FileAccess.open(backup_path, FileAccess.WRITE)
			if bf != null:
				bf.store_string(prev)
				bf.flush()
				bf.close()

	# Replace the primary only after the complete temporary file is flushed.
	if DirAccess.rename_absolute(tmp_path, save_path) != OK:
		return false

	# Update backup if none exists yet
	if not FileAccess.file_exists(backup_path):
		var bf2 := FileAccess.open(backup_path, FileAccess.WRITE)
		if bf2 != null:
			bf2.store_string(raw_out)
			bf2.flush()
			bf2.close()
	return true


func _parse_and_verify(raw_text: String) -> Variant:
	if raw_text.strip_edges().is_empty():
		return null
	var env_parser := JSON.new()
	if env_parser.parse(raw_text) != OK:
		return null
	var env: Variant = env_parser.data
	if typeof(env) != TYPE_DICTIONARY:
		return null
	var envelope: Dictionary = env
	if not envelope.has("payload") or not envelope.has("checksum"):
		return null
	var payload_str: String = str(envelope["payload"])
	var expected_hash: String = str(envelope["checksum"])
	if _compute_checksum(payload_str) != expected_hash:
		return null
	var payload_parser := JSON.new()
	if payload_parser.parse(payload_str) != OK:
		return null
	var parsed_payload: Variant = payload_parser.data
	if typeof(parsed_payload) != TYPE_DICTIONARY:
		return null
	return parsed_payload


func load_from_disk() -> void:
	recovered_from_corruption = false
	var loaded_dict: Variant = null

	if FileAccess.file_exists(save_path):
		var raw_primary := FileAccess.get_file_as_string(save_path)
		loaded_dict = _parse_and_verify(raw_primary)
		if loaded_dict == null:
			recovered_from_corruption = true

	if loaded_dict == null and FileAccess.file_exists(backup_path):
		var raw_backup := FileAccess.get_file_as_string(backup_path)
		loaded_dict = _parse_and_verify(raw_backup)
		if loaded_dict != null:
			recovered_from_corruption = true

	var defaults := create_default_data()
	if loaded_dict != null and typeof(loaded_dict) == TYPE_DICTIONARY:
		data = sanitize_save(loaded_dict as Dictionary)
	else:
		data = defaults

	if recovered_from_corruption:
		save_to_disk()

	_apply_loaded_settings()


# Borrowed from the browser profile repair approach: a valid checksum does not
# imply valid field types. Repair partial/older payloads before gameplay reads them.
func _repair_value(fallback: Variant, value: Variant) -> Variant:
	match typeof(fallback):
		TYPE_DICTIONARY:
			var result: Dictionary = fallback.duplicate(true)
			if typeof(value) == TYPE_DICTIONARY:
				for key in result.keys():
					if value.has(key):
						result[key] = _repair_value(result[key], value[key])
			return result
		TYPE_INT, TYPE_FLOAT:
			if (typeof(value) == TYPE_INT or typeof(value) == TYPE_FLOAT) and is_finite(float(value)) and float(value) >= 0.0:
				return int(value) if typeof(fallback) == TYPE_INT else float(value)
		TYPE_ARRAY:
			if typeof(value) == TYPE_ARRAY:
				return value.duplicate(true)
		_:
			if typeof(value) == typeof(fallback):
				return value
	return fallback


func _known_ids(value: Variant, allowed: Array, required: Array = []) -> Array:
	var result: Array = required.duplicate()
	if typeof(value) == TYPE_ARRAY:
		for item in value:
			if typeof(item) == TYPE_STRING and allowed.has(item) and not result.has(item):
				result.append(item)
	return result


func sanitize_save(loaded: Dictionary) -> Dictionary:
	var defaults := create_default_data()
	var result: Dictionary = _repair_value(defaults, loaded)
	result["version"] = SAVE_VERSION
	var settings: Dictionary = result["settings"]
	for volume in ["sfx_volume", "music_volume"]:
		settings[volume] = clampf(float(settings[volume]), 0.0, 1.0)
	var allowed: Dictionary = {"locale": ["ru", "en"], "joystick_mode": ["fixed", "floating"], "fx_quality": ["low", "medium", "high"], "difficulty": ConfigDB.difficulty_order}
	for field in allowed:
		if not allowed[field].has(settings[field]):
			settings[field] = defaults["settings"][field]
	for uid in ConfigDB.upgrade_order:
		result["upgrades"][uid] = mini(int(result["upgrades"][uid]), int(ConfigDB.upgrades[uid].get("max_level", 8)))
	result["unlocked_mutations"] = _known_ids(result["unlocked_mutations"], ConfigDB.mutation_order, defaults["unlocked_mutations"])
	result["unlocked_forms"] = _known_ids(result["unlocked_forms"], ConfigDB.form_order, defaults["unlocked_forms"])
	result["unlocked_trails"] = _known_ids(result["unlocked_trails"], ConfigDB.trail_fx.keys(), defaults["unlocked_trails"])
	result["achievements"] = _known_ids(result["achievements"], ConfigDB.achievement_order)
	result["owned_skus"] = _known_ids(result["owned_skus"], ConfigDB.store_catalog.keys())
	for field in ["form", "trail"]:
		if not result["unlocked_" + field + "s"].has(result["selected_" + field]):
			result["selected_" + field] = defaults["selected_" + field]
	# Bestiary has dynamic creature IDs; validate its values separately.
	var bestiary: Dictionary = {}
	var raw_bestiary: Variant = loaded.get("bestiary", {})
	if typeof(raw_bestiary) == TYPE_DICTIONARY:
		for cid in raw_bestiary:
			if ConfigDB.enemies.has(cid) or ConfigDB.special_encounters.has(cid):
				bestiary[cid] = _repair_value(0, raw_bestiary[cid])
	result["bestiary"] = bestiary
	result["records"] = _sanitize_records(loaded.get("records", {}))
	var days: Array = []
	for day in result["stats"]["active_days"]:
		if (typeof(day) == TYPE_INT or typeof(day) == TYPE_FLOAT) and is_finite(float(day)) and float(day) >= 0.0 and not days.has(int(day)):
			days.append(int(day))
	result["stats"]["active_days"] = days
	return result


func _sanitize_records(raw: Variant) -> Dictionary:
	## Records are keyed by dynamic ids (mode -> difficulty), so _repair_value cannot
	## handle them; every field is validated explicitly. Old saves simply yield {}.
	var out: Dictionary = {}
	if typeof(raw) != TYPE_DICTIONARY:
		return out
	# Read from the mode table rather than a second literal list: a mode added there
	# but forgotten here would silently lose its records on the next load.
	var allowed_modes: Array = GameModes.ORDER.duplicate()
	for mode_key in raw:
		var mode_id := str(mode_key)
		if not allowed_modes.has(mode_id):
			continue
		var by_mode: Variant = raw[mode_key]
		if typeof(by_mode) != TYPE_DICTIONARY:
			continue
		var clean_modes: Dictionary = {}
		for diff_key in by_mode:
			var diff_id := str(diff_key)
			if not ConfigDB.difficulty_order.has(diff_id):
				continue
			var rec: Variant = by_mode[diff_key]
			if typeof(rec) != TYPE_DICTIONARY:
				continue
			clean_modes[diff_id] = {
				"best_time": maxf(0.0, float(rec.get("best_time", 0.0))),
				"best_mass": maxf(0.0, float(rec.get("best_mass", 0.0))),
				"best_essence": maxi(0, int(rec.get("best_essence", 0))),
				"victories": maxi(0, int(rec.get("victories", 0))),
				"runs": maxi(0, int(rec.get("runs", 0)))
			}
		if not clean_modes.is_empty():
			out[mode_id] = clean_modes
	return out


func _apply_loaded_settings() -> void:
	var settings: Dictionary = data.get("settings", {})
	var loc_code: String = str(settings.get("locale", "ru"))
	Loc.set_locale(loc_code)


# --- Progression Helpers ---

func get_essence() -> int:
	return int(data.get("essence", 0))


func add_essence(amount: int) -> void:
	if amount <= 0:
		return
	data["essence"] = get_essence() + amount
	save_to_disk()


func spend_essence(amount: int) -> bool:
	if amount < 0 or get_essence() < amount:
		return false
	data["essence"] = get_essence() - amount
	save_to_disk()
	return true


func get_upgrade_level(upgrade_id: String) -> int:
	var upgs: Dictionary = data.get("upgrades", {})
	return int(upgs.get(upgrade_id, 0))


func buy_upgrade(upgrade_id: String) -> bool:
	var cfg: Dictionary = ConfigDB.upgrades.get(upgrade_id, {})
	if cfg.is_empty():
		return false
	var cur_lv := get_upgrade_level(upgrade_id)
	var max_lv: int = int(cfg.get("max_level", 8))
	if cur_lv >= max_lv:
		return false
	var cost := ConfigDB.get_upgrade_cost(upgrade_id, cur_lv)
	if not spend_essence(cost):
		return false
	data["upgrades"][upgrade_id] = cur_lv + 1
	save_to_disk()
	Events.upgrade_purchased.emit(upgrade_id, cur_lv + 1)
	return true


func get_upgrade_bonus(upgrade_id: String) -> float:
	var cfg: Dictionary = ConfigDB.upgrades.get(upgrade_id, {})
	if cfg.is_empty():
		return 0.0
	return float(get_upgrade_level(upgrade_id)) * float(cfg.get("bonus_per_level", 0.0))


func is_mutation_unlocked(mutation_id: String) -> bool:
	var arr: Array = data.get("unlocked_mutations", [])
	return arr.has(mutation_id)


func unlock_mutation(mutation_id: String) -> bool:
	if is_mutation_unlocked(mutation_id):
		return false
	var cfg := ConfigDB.get_mutation(mutation_id)
	if cfg.is_empty():
		return false
	var cost: int = int(cfg.get("unlock_cost", 0))
	if not spend_essence(cost):
		return false
	(data["unlocked_mutations"] as Array).append(mutation_id)
	save_to_disk()
	Events.mutation_unlocked_permanently.emit(mutation_id)
	return true


func record_creature_seen(creature_id: String, count_add: int = 1) -> void:
	var bestiary: Dictionary = data["bestiary"]
	var is_new := not bestiary.has(creature_id)
	bestiary[creature_id] = int(bestiary.get(creature_id, 0)) + count_add
	if is_new:
		Events.creature_discovered.emit(creature_id)


func get_creature_count(creature_id: String) -> int:
	var bestiary: Dictionary = data.get("bestiary", {})
	return int(bestiary.get(creature_id, 0))


func increment_stat(stat_key: String, delta_val: float) -> void:
	var st: Dictionary = data["stats"]
	if stat_key == "peak_mass":
		st["peak_mass"] = maxf(float(st.get("peak_mass", 10.0)), delta_val)
	else:
		st[stat_key] = float(st.get(stat_key, 0.0)) + delta_val
	_evaluate_achievements()


func _evaluate_achievements() -> void:
	var unlocked_ach: Array = data["achievements"]
	var st: Dictionary = data["stats"]
	for aid in ConfigDB.achievement_order:
		if unlocked_ach.has(aid):
			continue
		var acfg: Dictionary = ConfigDB.achievements[aid]
		var metric: String = str(acfg.get("metric", ""))
		var target: float = float(acfg.get("target", 1.0))
		if float(st.get(metric, 0.0)) >= target:
			unlocked_ach.append(aid)
			var reward: int = int(acfg.get("reward_essence", 0))
			data["essence"] = get_essence() + reward
			# Check form unlocks tied to achievements
			for fid in ConfigDB.form_order:
				var fcfg: Dictionary = ConfigDB.slime_forms[fid]
				if str(fcfg.get("unlock_type", "")) == "achievement" and str(fcfg.get("achievement_id", "")) == aid:
					if not (data["unlocked_forms"] as Array).has(fid):
						(data["unlocked_forms"] as Array).append(fid)
			Events.achievement_unlocked.emit(aid, reward)


func unlock_form_with_essence(form_id: String) -> bool:
	var fcfg: Dictionary = ConfigDB.slime_forms.get(form_id, {})
	if fcfg.is_empty() or (data["unlocked_forms"] as Array).has(form_id):
		return false
	if str(fcfg.get("unlock_type", "")) != "essence":
		return false
	var cost: int = int(fcfg.get("essence_cost", 999))
	if not spend_essence(cost):
		return false
	(data["unlocked_forms"] as Array).append(form_id)
	save_to_disk()
	return true


func select_form(form_id: String) -> bool:
	if not (data["unlocked_forms"] as Array).has(form_id):
		return false
	data["selected_form"] = form_id
	save_to_disk()
	Events.slime_form_changed.emit(form_id)
	return true


func select_trail(trail_id: String) -> bool:
	if not (data["unlocked_trails"] as Array).has(trail_id):
		return false
	data["selected_trail"] = trail_id
	save_to_disk()
	return true


func apply_sku_entitlement(sku: String) -> void:
	var owned: Array = data["owned_skus"]
	if not owned.has(sku):
		owned.append(sku)
	var item: Dictionary = ConfigDB.store_catalog.get(sku, {})
	var grants: Dictionary = item.get("grants", {})
	if bool(grants.get("no_ads", false)):
		data["no_ads"] = true
	if grants.has("slime_form"):
		var fid: String = str(grants["slime_form"])
		if not (data["unlocked_forms"] as Array).has(fid):
			(data["unlocked_forms"] as Array).append(fid)
	if grants.has("trail_fx"):
		var tid: String = str(grants["trail_fx"])
		if not (data["unlocked_trails"] as Array).has(tid):
			(data["unlocked_trails"] as Array).append(tid)
	save_to_disk()


func has_no_ads() -> bool:
	return bool(data.get("no_ads", false))


func get_setting(key: String, default_val: Variant = null) -> Variant:
	var s: Dictionary = data.get("settings", {})
	return s.get(key, default_val)


func set_setting(key: String, val: Variant) -> void:
	data["settings"][key] = val
	if key == "locale":
		Loc.set_locale(str(val))
	save_to_disk()
	Events.settings_changed.emit()


# --- Difficulty & Records ---

func get_difficulty_id() -> String:
	var did := str(get_setting("difficulty", ConfigDB.get_default_difficulty_id()))
	if not ConfigDB.difficulty_order.has(did):
		return ConfigDB.get_default_difficulty_id()
	return did


func set_difficulty(difficulty_id: String) -> bool:
	if not ConfigDB.difficulty_order.has(difficulty_id):
		return false
	set_setting("difficulty", difficulty_id)
	return true


func get_record(mode_id: String, difficulty_id: String) -> Dictionary:
	var empty := {
		"best_time": 0.0,
		"best_mass": 0.0,
		"best_essence": 0,
		"victories": 0,
		"runs": 0
	}
	var records: Variant = data.get("records", {})
	if typeof(records) != TYPE_DICTIONARY:
		return empty
	var by_mode: Variant = records.get(mode_id, {})
	if typeof(by_mode) != TYPE_DICTIONARY:
		return empty
	var rec: Variant = by_mode.get(difficulty_id, {})
	if typeof(rec) != TYPE_DICTIONARY:
		return empty
	return {
		"best_time": float(rec.get("best_time", 0.0)),
		"best_mass": float(rec.get("best_mass", 0.0)),
		"best_essence": int(rec.get("best_essence", 0)),
		"victories": int(rec.get("victories", 0)),
		"runs": int(rec.get("runs", 0))
	}


func submit_run_record(summary: Dictionary) -> Dictionary:
	## Stores a finished run into the per-mode/per-difficulty record table and reports
	## which personal bests improved. Best time only counts victorious runs.
	var mode_id: String = str(summary.get("mode", "standard"))
	var diff_id: String = str(summary.get("difficulty", ConfigDB.get_default_difficulty_id()))
	if not ConfigDB.difficulty_order.has(diff_id):
		diff_id = ConfigDB.get_default_difficulty_id()
	var victory := bool(summary.get("victory", false))
	var duration := maxf(0.0, float(summary.get("duration_sec", 0.0)))
	var peak_mass := maxf(0.0, float(summary.get("peak_mass", 0.0)))
	var essence := maxi(0, int(summary.get("base_essence", 0)))

	var prev := get_record(mode_id, diff_id)
	var out := {
		"mode": mode_id,
		"difficulty": diff_id,
		"is_new_best_time": false,
		"is_new_best_mass": false,
		"is_new_best_essence": false,
		"first_victory": false,
		"previous_best_time": float(prev["best_time"]),
		"best_time": float(prev["best_time"]),
		"best_mass": float(prev["best_mass"]),
		"best_essence": int(prev["best_essence"]),
		"victories": int(prev["victories"]),
		"runs": int(prev["runs"]) + 1
	}
	if victory:
		if float(prev["best_time"]) <= 0.0 or duration < float(prev["best_time"]):
			out["is_new_best_time"] = true
			out["best_time"] = duration
		out["first_victory"] = int(prev["victories"]) <= 0
		out["victories"] = int(prev["victories"]) + 1
	if peak_mass > float(prev["best_mass"]):
		out["is_new_best_mass"] = true
		out["best_mass"] = peak_mass
	if essence > int(prev["best_essence"]):
		out["is_new_best_essence"] = true
		out["best_essence"] = essence

	var records: Dictionary = data.get("records", {})
	if typeof(records) != TYPE_DICTIONARY:
		records = {}
	var by_mode: Dictionary = records.get(mode_id, {})
	if typeof(by_mode) != TYPE_DICTIONARY:
		by_mode = {}
	by_mode[diff_id] = {
		"best_time": out["best_time"],
		"best_mass": out["best_mass"],
		"best_essence": out["best_essence"],
		"victories": out["victories"],
		"runs": out["runs"]
	}
	records[mode_id] = by_mode
	data["records"] = records
	# Difficulty-clear achievements read flat stat keys, so the counter is named after
	# the difficulty id. Only non-default clears are counted: the default difficulty
	# already has its own "defeat_guardian" achievement.
	if victory and diff_id != ConfigDB.get_default_difficulty_id():
		increment_stat(diff_id + "_victories", 1)
	save_to_disk()
	return out
