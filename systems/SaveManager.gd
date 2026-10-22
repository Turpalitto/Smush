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
		"stats": {
			"total_runs": 0,
			"victories": 0,
			"bosses_defeated": 0,
			"boss_encounters": 0,
			"total_absorbed": 0,
			"total_mutations_picked": 0,
			"total_synergies_unlocked": 0,
			"armored_defeated": 0,
			"peak_mass": 10.0,
			"total_playtime_sec": 0.0,
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
			"music_enabled": false,
			"joystick_mode": "floating",
			"auto_absorb": true,
			"fx_quality": "high",
			"locale": "ru",
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

	var pf := FileAccess.open(save_path, FileAccess.WRITE)
	if pf == null:
		return false
	pf.store_string(raw_out)
	pf.flush()
	pf.close()

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
		data = _merge_with_defaults(defaults, loaded_dict as Dictionary)
	else:
		data = defaults

	if recovered_from_corruption:
		save_to_disk()

	_apply_loaded_settings()


func _merge_with_defaults(defaults: Dictionary, loaded: Dictionary) -> Dictionary:
	var result := defaults.duplicate(true)
	for k in loaded.keys():
		if result.has(k) and typeof(result[k]) == TYPE_DICTIONARY and typeof(loaded[k]) == TYPE_DICTIONARY:
			var sub_def: Dictionary = result[k]
			var sub_ld: Dictionary = loaded[k]
			for sk in sub_ld.keys():
				sub_def[sk] = sub_ld[sk]
		else:
			result[k] = loaded[k]
	return result


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
