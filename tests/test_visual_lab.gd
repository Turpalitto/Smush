extends "res://tests/TestSuiteBase.gd"
## GLM visual-lab suite: the organic style must be additive and reversible.
## Covers the pure logic (mass<->stage inversion, six-phase anatomy) and a live
## instantiation of the lab scene with style switching, mutation wiring, the
## absorb demo and the Engine.time_scale contract. Rendering quality itself is
## judged from screenshots (see docs/glm/04_TEST_RESULTS.md), not here.

var _lab_script: GDScript = null


func _init() -> void:
	super("VisualLabSuite")


func run_async(tree: SceneTree) -> void:
	_lab_script = load("res://scripts/labs/EvolutionVisualLab.gd") as GDScript
	_test_mass_stage_roundtrip()
	_test_phase_mapping()
	_test_anatomy_table()
	_test_shaders_load()
	_test_base_visual_untouched()
	await _test_lab_scene(tree)
	await _test_grove_food_study(tree)


func _test_grove_food_study(tree: SceneTree) -> void:
	var echo := GroveStudy.FoodEcho.new()
	for i in range(40):
		echo.remember(i % 3)
	assert_eq(echo.echoes.size(), GroveStudy.FoodEcho.MAX_ECHOES, "Food echoes stay bounded during repeated feeding")
	echo.remember(-1)
	echo.remember(3)
	assert_eq(echo.echoes.size(), GroveStudy.FoodEcho.MAX_ECHOES, "Unknown food is ignored")
	echo.advance(GroveStudy.FoodEcho.LIFETIME)
	assert_true(echo.echoes.is_empty(), "Food recollection fades completely without permanent clutter")
	echo.free()
	var lab := ClaudeVisualLab.new()
	tree.root.add_child(lab)
	await tree.process_frame
	assert_false(lab._grove.visible, "Original lab background remains the default")
	var initial_mass := lab.mass
	for kind in range(3):
		lab._set_grove(kind)
		assert_eq(lab._grove.mood, kind, "Each grove mood is selectable")
		var prey := lab.spawn_prey(lab.subjects[0], Vector2.RIGHT * 30.0, ClaudeVisualLab.LabPrey.PState.HOME)
		prey.food_kind = kind
		lab.prey_absorbed(prey)
		prey.free()
	assert_eq(lab.subjects[0].food_echo.echoes.size(), 3, "All three foods leave an echo after absorption")
	assert_approx(lab.mass, initial_mass, 0.001, "Art study never changes gameplay mass")
	lab._set_grove(-1)
	assert_true(lab._floor_node.visible, "Original background can be restored")
	assert_false(lab._grove._layer.visible, "Study floor is hidden on return to baseline")
	lab.free()
	await tree.process_frame


func _test_mass_stage_roundtrip() -> void:
	assert_eq(EvolutionStages.COUNT, 15, "the ladder is 15 stages")
	for t: float in [1.0, 1.5, 2.5, 5.0, 8.5, 12.0, 14.5, 15.0]:
		var m := EvolutionVisualLab.mass_for_growth_t(t)
		var back := EvolutionStages.t_for_mass(m)
		assert_approx(back, t, 0.02, "mass<->stage roundtrip at t=%f" % t)
	# Integer stages land exactly on the real mass thresholds.
	for k in range(EvolutionStages.COUNT):
		var stage_mass := EvolutionVisualLab.mass_for_growth_t(float(k + 1))
		assert_approx(stage_mass, EvolutionStages.MASS_KEYS[k], 0.001,
			"stage %d keeps its original mass threshold" % (k + 1))


func _test_phase_mapping() -> void:
	var expected := {1: 1, 2: 1, 3: 2, 4: 2, 5: 2, 6: 3, 7: 3, 8: 3,
		9: 4, 10: 4, 11: 4, 12: 5, 13: 5, 14: 5, 15: 6}
	for stage: int in expected:
		assert_eq(SlimeVisualOrganic.phase_of_stage(stage), expected[stage],
			"stage %d maps to phase %d" % [stage, expected[stage]])
	assert_eq(SlimeVisualOrganic.PHASE_NAMES_RU.size(), 6, "six phase names")


func _test_anatomy_table() -> void:
	assert_eq(SlimeVisualOrganic.ANATOMY.size(), 15, "anatomy row per stage")
	var keys: Array[String] = ["organelles", "membrane", "nucleus", "veins", "flow", "glow", "silhouette"]
	for k in keys:
		var prev := -1.0
		for i in range(SlimeVisualOrganic.ANATOMY.size()):
			var v: float = float(SlimeVisualOrganic.ANATOMY[i][k])
			assert_gte(v, 0.0, "%s row %d within range" % [k, i + 1])
			assert_lte(v, 1.0, "%s row %d within range" % [k, i + 1])
			assert_gte(v, prev, "%s never regresses across the ladder (row %d)" % [k, i + 1])
			prev = v
	# Continuity: anatomy_at at an integer position equals that row.
	var at5 := SlimeVisualOrganic.anatomy_at(5.0)
	assert_approx(at5["organelles"], float(SlimeVisualOrganic.ANATOMY[4]["organelles"]), 0.001,
		"anatomy_at snaps to the row at integer t")
	var at15 := SlimeVisualOrganic.anatomy_at(15.0)
	assert_approx(at15["glow"], 1.0, 0.001, "perfect form glows fully")
	var mid := SlimeVisualOrganic.anatomy_at(2.5)
	var expect_mid: float = lerpf(float(SlimeVisualOrganic.ANATOMY[1]["organelles"]),
		float(SlimeVisualOrganic.ANATOMY[2]["organelles"]), 0.5)
	assert_approx(mid["organelles"], expect_mid, 0.001, "anatomy_at lerps between rows")


func _test_shaders_load() -> void:
	assert_true(load("res://shaders/slime_body.gdshader") is Shader, "original body shader loads")
	assert_true(load("res://shaders/slime_body_organic.gdshader") is Shader, "organic body shader loads")
	assert_true(load("res://shaders/organic_shield.gdshader") is Shader, "organic shield shader loads")


func _test_base_visual_untouched() -> void:
	var base := SlimeVisual.new()
	assert_false(base.organic_tendrils, "base tendril switch defaults off")
	assert_false(base.organic_shield, "base shield switch defaults off")
	assert_false(base.organic_electro, "base electro switch defaults off")
	base.free()


func _test_lab_scene(tree: SceneTree) -> void:
	var packed := load("res://scenes/labs/EvolutionVisualLab.tscn") as PackedScene
	assert_true(packed != null, "lab scene loads")
	if packed == null:
		return
	var lab = packed.instantiate()
	tree.root.add_child(lab)
	for _i in range(4):
		await tree.process_frame

	assert_true(lab.visual is SlimeVisualOrganic, "lab boots in the organic style")
	assert_true(lab.visual.organic_tendrils and lab.visual.organic_shield and lab.visual.organic_electro,
		"organic visual owns the three experimental visuals")
	assert_true(lab.visual.get_node_or_null("OrganicTendrils") is OrganicTendrils, "organic tendrils node exists")
	assert_true(lab.visual.get_node_or_null("OrganicShield") is OrganicShield, "organic shield node exists")
	assert_true(lab.visual.get_node_or_null("OrganicElectro") is OrganicElectro, "organic electro node exists")

	# Stage slider path drives the real ladder.
	lab.apply_mass(EvolutionVisualLab.mass_for_growth_t(8.0), true)
	await tree.process_frame
	assert_eq(lab.visual.stage, 8, "stage 8 reachable through the mass path")
	lab.apply_mass(EvolutionVisualLab.mass_for_growth_t(1.0), true)
	await tree.process_frame
	assert_eq(lab.visual.stage, 1, "stage 1 reachable through the mass path")

	# Quality plumbing into the organic shader.
	var org := lab.visual as SlimeVisualOrganic
	org.set_quality(0)
	assert_eq(int(org._shader_mat.get_shader_parameter("quality")), 0, "quality Low reaches the shader")
	org.set_quality(2)

	# Mutation wiring (no save writes: levels live only in the lab dictionary).
	lab._on_mutation_toggled(true, "shield")
	lab._on_mutation_toggled(true, "ranged_absorb")
	lab._on_mutation_toggled(true, "electro_discharge")
	await tree.process_frame
	assert_eq(int(lab.visual.mutation_levels.get("shield", 0)), 3, "shield level set")
	assert_true(lab.visual.shield_active, "shield demo is active when checked")

	# Style switch to the original preset and back.
	lab._spawn_visual(false)
	await tree.process_frame
	assert_true(lab.visual is SlimeVisual and not (lab.visual is SlimeVisualOrganic),
		"original style uses the untouched base visual")
	assert_false(lab.visual.organic_shield, "original style keeps base switches off")
	assert_true(load("res://shaders/slime_body.gdshader") == (lab.visual._shader_mat.shader),
		"original style binds the original shader")
	lab._spawn_visual(true)
	await tree.process_frame
	assert_true(lab.visual is SlimeVisualOrganic, "organic style switches back")

	# Absorb demo: a prey pushed across the membrane raises mass and fires the
	# visual swallow (ghost) without touching the save or the game loop.
	var mass_before: float = lab.mass
	var prey = lab.LabPrey.new()
	prey.lab = lab
	prey.global_position = lab.slime_root.global_position + Vector2(40.0, 0.0)
	lab.prey_container.add_child(prey)
	lab.finish_absorb(prey)
	await tree.process_frame
	assert_gt(lab.mass, mass_before, "absorb demo raises mass")
	var organic_after := lab.visual as SlimeVisualOrganic
	assert_eq(organic_after._swallowed.size(), 1, "swallowed ghost spawned")
	assert_gt(organic_after._absorb_pulse, 0.0, "absorb ripple envelope armed")
	prey.queue_free()

	# Rule-gated rejection still works through the lab (prey flees, no mass).
	var prey2 = lab.LabPrey.new()
	prey2.lab = lab
	prey2.mass_value = 4.0
	prey2.category = "miniboss"
	prey2.global_position = lab.slime_root.global_position + Vector2(120.0, 0.0)
	lab.prey_container.add_child(prey2)
	var mass2: float = lab.mass
	lab.reject_prey(prey2)
	assert_eq(prey2.state, lab.LabPrey.PState.FLEE, "rejected prey flees")
	assert_approx(lab.mass, mass2, 0.0001, "rejected prey grants no mass")
	prey2.queue_free()

	# time_scale contract: stop freezes, leaving the scene restores the clock.
	lab._on_stop_toggled(true)
	assert_eq(Engine.time_scale, 0.0, "Stop freezes the clock")
	lab._on_stop_toggled(false)
	assert_approx(Engine.time_scale, 1.0, 0.001, "un-stopping restores the speed slider")
	lab._on_stop_toggled(true)
	lab.queue_free()
	await tree.process_frame
	await tree.process_frame
	assert_approx(Engine.time_scale, 1.0, 0.001, "leaving the lab restores Engine.time_scale")
