class_name MutationManager
extends RefCounted
## Manages run-scoped mutations (12 base mutations, levels 1..5) and data-driven synergies (5+ combos).

const RARITY_WEIGHTS: Dictionary = {
	"common": 48.0,
	"rare": 34.0,
	"epic": 24.0
}

var levels: Dictionary = {} # mutation_id -> int
var active_synergies: Dictionary = {} # synergy_id -> bool
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()


func reset() -> void:
	levels.clear()
	active_synergies.clear()


func get_level(mutation_id: String) -> int:
	return int(levels.get(mutation_id, 0))


func has_mutation(mutation_id: String) -> bool:
	return get_level(mutation_id) > 0


func has_synergy(synergy_id: String) -> bool:
	return bool(active_synergies.get(synergy_id, false))


func get_total_picks() -> int:
	var sum: int = 0
	for k in levels.keys():
		sum += int(levels[k])
	return sum


func can_upgrade_mutation(mutation_id: String, unlocked_override: Array = []) -> bool:
	var cfg := ConfigDB.get_mutation(mutation_id)
	if cfg.is_empty():
		return false
	var is_unlocked := unlocked_override.has(mutation_id) if not unlocked_override.is_empty() else SaveData.is_mutation_unlocked(mutation_id)
	if not is_unlocked:
		return false
	var max_lv: int = int(cfg.get("max_level", 5))
	return get_level(mutation_id) < max_lv


func apply_mutation(mutation_id: String) -> int:
	var cfg := ConfigDB.get_mutation(mutation_id)
	if cfg.is_empty():
		return 0
	var max_lv: int = int(cfg.get("max_level", 5))
	var cur := get_level(mutation_id)
	if cur >= max_lv:
		return cur
	var next_lv := cur + 1
	levels[mutation_id] = next_lv
	Events.mutation_applied.emit(mutation_id, next_lv)
	Analytics.track("mutation_selected", {"id": mutation_id, "level": next_lv})
	SaveData.increment_stat("total_mutations_picked", 1.0)
	_evaluate_synergies()
	return next_lv


func _evaluate_synergies() -> Array[String]:
	var newly_activated: Array[String] = []
	for syn: Dictionary in ConfigDB.synergy_list:
		var sid: String = str(syn.get("id", ""))
		if sid.is_empty() or has_synergy(sid):
			continue
		var reqs: Array = syn.get("required_mutations", [])
		var min_lv: int = int(syn.get("min_mutation_level", 1))
		if reqs.is_empty():
			continue
		var all_met := true
		for req_id in reqs:
			if get_level(str(req_id)) < min_lv:
				all_met = false
				break
		if all_met:
			active_synergies[sid] = true
			newly_activated.append(sid)
			SaveData.increment_stat("total_synergies_unlocked", 1.0)
			Events.synergy_activated.emit(sid)
	return newly_activated


func preview_synergy_for_candidate(candidate_id: String) -> String:
	for syn: Dictionary in ConfigDB.synergy_list:
		var sid: String = str(syn.get("id", ""))
		if has_synergy(sid):
			continue
		var reqs: Array = syn.get("required_mutations", [])
		if not reqs.has(candidate_id):
			continue
		var min_lv: int = int(syn.get("min_mutation_level", 1))
		var others_ok := true
		for req_id in reqs:
			var r_str := str(req_id)
			var lv_after := (get_level(r_str) + 1) if r_str == candidate_id else get_level(r_str)
			if lv_after < min_lv:
				others_ok = false
				break
		if others_ok:
			return sid
	return ""


func roll_draft_choices(count: int = 3, unlocked_override: Array = []) -> Array[Dictionary]:
	var pool: Array[String] = []
	for mid in ConfigDB.mutation_order:
		if can_upgrade_mutation(mid, unlocked_override):
			pool.append(mid)

	var picked: Array[Dictionary] = []
	var target_count := mini(count, pool.size())

	for _i in range(target_count):
		var total_w: float = 0.0
		var weights: Array[float] = []
		for mid in pool:
			var cfg := ConfigDB.get_mutation(mid)
			var rarity: String = str(cfg.get("rarity", "common"))
			var w: float = float(RARITY_WEIGHTS.get(rarity, 34.0))
			if not preview_synergy_for_candidate(mid).is_empty():
				w += 34.0
			elif get_level(mid) > 0:
				w += 10.0
			weights.append(w)
			total_w += w

		var roll := _rng.randf() * total_w
		var chosen_idx: int = 0
		var accum: float = 0.0
		for idx in range(pool.size()):
			accum += weights[idx]
			if roll <= accum:
				chosen_idx = idx
				break

		var chosen_id := pool[chosen_idx]
		pool.remove_at(chosen_idx)
		var c_cfg := ConfigDB.get_mutation(chosen_id)
		picked.append({
			"id": chosen_id,
			"current_level": get_level(chosen_id),
			"next_level": get_level(chosen_id) + 1,
			"max_level": int(c_cfg.get("max_level", 5)),
			"rarity": str(c_cfg.get("rarity", "common")),
			"completes_synergy": preview_synergy_for_candidate(chosen_id)
		})

	return picked


func get_scaled_param(mutation_id: String, base_key: String, per_level_key: String, default_val: float = 0.0) -> float:
	var lv := get_level(mutation_id)
	if lv <= 0:
		return 0.0
	var cfg := ConfigDB.get_mutation(mutation_id)
	var p: Dictionary = cfg.get("params", {})
	var base_v: float = float(p.get(base_key, default_val))
	var step_v: float = float(p.get(per_level_key, 0.0))
	return base_v + step_v * float(lv - 1)


func build_player_absorption_context(mass: float, is_dashing: bool, ambush_ready: bool) -> Dictionary:
	return {
		"mass": mass,
		"spikes_level": get_level("spikes"),
		"ranged_absorb_level": get_level("ranged_absorb"),
		"has_piercing_strike": has_synergy("piercing_strike"),
		"has_bio_vampirism": has_synergy("bio_vampirism"),
		"is_dashing": is_dashing,
		"mimicry_ambush_ready": ambush_ready,
		"temp_absorb_bonus": 0.0
	}
