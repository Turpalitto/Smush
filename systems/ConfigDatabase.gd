extends Node
## Loads and indexes all JSON configuration files (Autoload: ConfigDB).

var mutations: Dictionary = {}
var mutation_order: Array[String] = []
var synergies: Dictionary = {}
var synergy_list: Array[Dictionary] = []
var enemies: Dictionary = {}
var enemy_order: Array[String] = []
var special_encounters: Dictionary = {}
var upgrades: Dictionary = {}
var upgrade_order: Array[String] = []
var slime_forms: Dictionary = {}
var form_order: Array[String] = []
var trail_fx: Dictionary = {}
var achievements: Dictionary = {}
var achievement_order: Array[String] = []
var store_catalog: Dictionary = {}
var store_order: Array[String] = []


func _ready() -> void:
	load_all()


func load_all() -> void:
	if not mutations.is_empty():
		return
	var mut_doc := _read_json("res://resources/data/mutations.json")
	for item: Dictionary in mut_doc.get("mutations", []):
		var mid: String = item["id"]
		mutations[mid] = item
		mutation_order.append(mid)

	var syn_doc := _read_json("res://resources/data/synergies.json")
	for item: Dictionary in syn_doc.get("synergies", []):
		var sid: String = item["id"]
		synergies[sid] = item
		synergy_list.append(item)

	var enemy_doc := _read_json("res://resources/data/enemies.json")
	for item: Dictionary in enemy_doc.get("enemies", []):
		var eid: String = item["id"]
		enemies[eid] = item
		enemy_order.append(eid)
	for item: Dictionary in enemy_doc.get("special_encounters", []):
		special_encounters[item["id"]] = item

	var meta_doc := _read_json("res://resources/data/meta_progression.json")
	for item: Dictionary in meta_doc.get("upgrades", []):
		var uid: String = item["id"]
		upgrades[uid] = item
		upgrade_order.append(uid)
	for item: Dictionary in meta_doc.get("slime_forms", []):
		var fid: String = item["id"]
		slime_forms[fid] = item
		form_order.append(fid)
	for item: Dictionary in meta_doc.get("trail_fx", []):
		trail_fx[item["id"]] = item
	for item: Dictionary in meta_doc.get("achievements", []):
		var aid: String = item["id"]
		achievements[aid] = item
		achievement_order.append(aid)
	for item: Dictionary in meta_doc.get("store_catalog", []):
		var sku: String = item["sku"]
		store_catalog[sku] = item
		store_order.append(sku)


func _read_json(path: String) -> Dictionary:
	if not FileAccess.file_exists(path):
		push_error("Missing config JSON: " + path)
		return {}
	var raw := FileAccess.get_file_as_string(path)
	var parsed: Variant = JSON.parse_string(raw)
	if typeof(parsed) != TYPE_DICTIONARY:
		push_error("Invalid JSON dictionary in: " + path)
		return {}
	return parsed


func get_mutation(mutation_id: String) -> Dictionary:
	return mutations.get(mutation_id, {})


func get_enemy(enemy_id: String) -> Dictionary:
	if enemies.has(enemy_id):
		return enemies[enemy_id]
	return special_encounters.get(enemy_id, {})


func get_upgrade_cost(upgrade_id: String, current_level: int) -> int:
	var cfg: Dictionary = upgrades.get(upgrade_id, {})
	if cfg.is_empty():
		return 999999
	var base_cost: float = float(cfg.get("base_cost", 25))
	var growth: float = float(cfg.get("cost_growth", 1.45))
	return int(round(base_cost * pow(growth, float(current_level))))
