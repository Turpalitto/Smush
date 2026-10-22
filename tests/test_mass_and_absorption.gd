extends TestSuiteBase
## Unit tests for non-linear MassSystem math, high-mass trade-offs, and multi-factor AbsorptionRules.


func _init() -> void:
	super("MassAndAbsorptionSuite")


func run() -> void:
	_test_nonlinear_growth_and_caps()
	_test_mass_tradeoffs_and_narrow_passages()
	_test_multifactor_absorption_thresholds()


func _test_nonlinear_growth_and_caps() -> void:
	var r10 := MassSystem.radius_from_mass(10.0)
	var r30 := MassSystem.radius_from_mass(30.0)
	var r80 := MassSystem.radius_from_mass(80.0)
	var r500 := MassSystem.radius_from_mass(500.0)

	assert_gt(r30, r10, "Radius increases with mass")
	assert_gt(r80, r30, "Radius continues growing smoothly")
	# Non-linearity check: delta(10->30) per unit mass > delta(30->80) per unit mass
	var slope_early := (r30 - r10) / 20.0
	var slope_late := (r80 - r30) / 50.0
	assert_gt(slope_early, slope_late, "Radius growth follows sublinear diminishing curve")
	assert_lte(r500, MassSystem.MAX_RADIUS, "Radius never exceeds MAX_RADIUS hard cap")
	assert_eq(MassSystem.clamp_mass(9999.0), MassSystem.MAX_MASS, "Mass clamped at MAX_MASS")

	# Soft-cap diminishing gain
	var g_low := MassSystem.effective_gain(15.0, 5.0)
	var g_high := MassSystem.effective_gain(180.0, 5.0)
	assert_eq(g_low, 5.0, "Full mass gain below soft cap")
	assert_lt(g_high, g_low, "Tapered mass gain above soft cap")


func _test_mass_tradeoffs_and_narrow_passages() -> void:
	assert_gt(MassSystem.maneuverability_multiplier(10.0), MassSystem.maneuverability_multiplier(140.0), "High mass reduces maneuverability")
	assert_lt(MassSystem.visibility_multiplier(10.0), MassSystem.visibility_multiplier(140.0), "High mass increases enemy detection visibility")
	assert_lt(MassSystem.aoe_vulnerability_multiplier(10.0), MassSystem.aoe_vulnerability_multiplier(140.0), "High mass increases AoE vulnerability")

	# Narrow root gate half_width = 30.0 px
	assert_true(MassSystem.can_fit_narrow_passage(10.0, 30.0, false), "Small slime fits narrow passage")
	assert_false(MassSystem.can_fit_narrow_passage(45.0, 30.0, false), "Bulky slime blocked by narrow passage")
	assert_true(MassSystem.can_fit_narrow_passage(32.0, 30.0, true), "Mid-size slime squeezes through narrow passage using Jet Dash!")


func _test_multifactor_absorption_thresholds() -> void:
	var base_player := {
		"mass": 18.0,
		"spikes_level": 0,
		"ranged_absorb_level": 0,
		"has_piercing_strike": false,
		"has_bio_vampirism": false,
		"is_dashing": false,
		"mimicry_ambush_ready": false,
		"temp_absorb_bonus": 0.0
	}

	# 1. Passive tiny mushroom is easily absorbed
	var shroom := {"category": "flora", "mass": 6.0, "armor": 0.0, "shell_active": false, "hp_ratio": 1.0}
	var res_shroom := AbsorptionRules.evaluate(base_player, shroom)
	assert_true(bool(res_shroom["can_absorb"]), "Player (18) absorbs Tiny Mushroom (6)")

	# 2. Stone Slug with equal/smaller mass (16) but ACTIVE SHELL resists naive mass rule!
	var slug_shelled := {
		"category": "armored",
		"mass": 16.0,
		"armor": 0.65,
		"shell_active": true,
		"is_frozen": false,
		"is_stunned": false,
		"is_poisoned": false,
		"is_vulnerable": false,
		"hp_ratio": 1.0
	}
	var res_blocked := AbsorptionRules.evaluate(base_player, slug_shelled)
	assert_false(bool(res_blocked["can_absorb"]), "Active Stone Slug shell blocks slightly larger slime without armor-piercing")
	assert_eq(str(res_blocked["reason"]), "armored_shell", "Reason identifies armored_shell")

	# 3. Freezing + Spikes + Ambush overcomes the exact same Stone Slug!
	var tactical_player := base_player.duplicate()
	tactical_player["spikes_level"] = 2
	tactical_player["mimicry_ambush_ready"] = true
	var slug_chilled := slug_shelled.duplicate()
	slug_chilled["is_frozen"] = true
	var res_cracked := AbsorptionRules.evaluate(tactical_player, slug_chilled)
	assert_true(bool(res_cracked["cracks_shell"]), "Spikes Lv2 + Freeze cracks Stone Slug shell")
	assert_true(bool(res_cracked["can_absorb"]), "Tactical player absorbs chilled Stone Slug")

	# 4. Miniboss and Boss cannot be gulped at full HP even by huge mass; only below execution thresholds
	var giant_player := base_player.duplicate()
	giant_player["mass"] = 220.0
	var mb_healthy := {"category": "miniboss", "mass": 48.0, "hp_ratio": 0.85}
	var mb_critical := {"category": "miniboss", "mass": 48.0, "hp_ratio": 0.18}
	assert_false(bool(AbsorptionRules.evaluate(giant_player, mb_healthy)["can_absorb"]), "Healthy miniboss resists instant high-mass gulp")
	assert_true(bool(AbsorptionRules.evaluate(giant_player, mb_critical)["can_absorb"]), "Weakened <=22% HP miniboss can be gulped")

	var boss_healthy := {"category": "boss", "mass": 85.0, "hp_ratio": 0.50}
	var boss_critical := {"category": "boss", "mass": 85.0, "hp_ratio": 0.04}
	assert_false(bool(AbsorptionRules.evaluate(giant_player, boss_healthy)["can_absorb"]), "Healthy boss immune to instant gulp")
	assert_true(bool(AbsorptionRules.evaluate(giant_player, boss_critical)["can_absorb"]), "Critical <=6% HP boss can be executed/absorbed")
