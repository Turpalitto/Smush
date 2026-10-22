extends TestSuiteBase
## Unit tests for all 12 mutations, draft rules, level caps, and all 5 data-driven synergies.


func _init() -> void:
	super("MutationsAndSynergiesSuite")


func run() -> void:
	_test_catalog_completeness()
	_test_draft_unlocks_and_level_caps()
	_test_all_five_synergies()


func _test_catalog_completeness() -> void:
	assert_gte(float(ConfigDB.mutation_order.size()), 12.0, "At least 12 base mutations configured")
	assert_gte(float(ConfigDB.synergy_list.size()), 5.0, "At least 5 synergy combinations configured")

	var behavioral_count: int = 0
	for mid in ConfigDB.mutation_order:
		var m := ConfigDB.get_mutation(mid)
		assert_false(str(m.get("name_key", "")).is_empty(), "Mutation has name_key: " + mid)
		assert_false(str(m.get("visual_tag", "")).is_empty(), "Mutation has body visual_tag: " + mid)
		assert_false(AssetRegistry.get_texture(str(m.get("icon", ""))) == null, "Mutation icon loads cleanly: " + mid)
		if bool(m.get("behavioral", false)):
			behavioral_count += 1

	assert_gte(float(behavioral_count), 6.0, "At least half of mutations alter player behavior")


func _test_draft_unlocks_and_level_caps() -> void:
	var mgr := MutationManager.new(12345)
	var default_pool := ["magnet", "speed_boost", "spikes", "poison_trail"]

	var choices := mgr.roll_draft_choices(3, default_pool)
	assert_eq(choices.size(), 3, "Draft returns 3 unique choices")
	assert_true(choices[0]["id"] != choices[1]["id"] and choices[1]["id"] != choices[2]["id"], "Draft choices are unique")
	for c: Dictionary in choices:
		assert_true(default_pool.has(str(c["id"])), "Draft respects unlocked pool filter")

	# Level cap enforcement (max_level = 5)
	for _i in range(8):
		mgr.apply_mutation("magnet")
	assert_eq(mgr.get_level("magnet"), 5, "Mutation strictly capped at max_level 5")
	assert_false(mgr.can_upgrade_mutation("magnet", default_pool), "Maxed mutation excluded from further upgrades")

	var post_cap_choices := mgr.roll_draft_choices(3, default_pool)
	for c: Dictionary in post_cap_choices:
		assert_true(str(c["id"]) != "magnet", "Maxed mutation never appears in draft")


func _test_all_five_synergies() -> void:
	var expected_pairs := [
		["em_storm", "magnet", "electro_discharge"],
		["toxic_clones", "poison_trail", "split"],
		["piercing_strike", "dash", "spikes"],
		["ice_armor", "freeze", "shield"],
		["bio_vampirism", "regeneration", "ranged_absorb"]
	]
	for entry in expected_pairs:
		var syn_id: String = entry[0]
		var m1: String = entry[1]
		var m2: String = entry[2]
		var mgr := MutationManager.new(42)
		mgr.apply_mutation(m1)
		assert_false(mgr.has_synergy(syn_id), "Synergy %s inactive with only 1 component" % syn_id)
		assert_eq(mgr.preview_synergy_for_candidate(m2), syn_id, "Draft preview detects %s completion" % syn_id)
		mgr.apply_mutation(m2)
		assert_true(mgr.has_synergy(syn_id), "Synergy %s activates automatically from data config" % syn_id)
