extends Node
## Master automated test runner scene script for SLIME RUSH: EVOLUTION.
## Run via: godot4 --headless --path /home/user/Smush res://tests/TestRunner.tscn

const MassSuite = preload("res://tests/test_mass_and_absorption.gd")
const MutationSuite = preload("res://tests/test_mutations_and_synergies.gd")
const SaveSuite = preload("res://tests/test_save_and_progression.gd")
const DifficultySuite = preload("res://tests/test_difficulty_and_records.gd")
const MonetizationSuite = preload("res://tests/test_monetization_and_analytics.gd")
const IntegrationSuite = preload("res://tests/test_full_game_integration.gd")
const GrowthSuite = preload("res://tests/test_growth_ladder.gd")
const ModesSuite = preload("res://tests/test_modes.gd")
const ChimesSuite = preload("res://tests/test_audio_chimes.gd")
const VisualLabSuite = preload("res://tests/test_visual_lab.gd")
const RenderSpikeSuite = preload("res://tests/test_render_spike.gd")
const Glade25DSuite = preload("res://tests/test_glade_25d.gd")
const LakeProtoSuite = preload("res://tests/test_lake_proto.gd")
const TestSuiteBase = preload("res://tests/TestSuiteBase.gd")


func _ready() -> void:
	process_mode = Node.PROCESS_MODE_ALWAYS
	call_deferred("_execute_all")


func _execute_all() -> void:
	print("============================================================")
	print(" SLIME RUSH: EVOLUTION — AUTOMATED QA & INTEGRATION SUITE")
	print("============================================================")

	var suites: Array[TestSuiteBase] = []

	var s1 := MassSuite.new()
	s1.run()
	suites.append(s1)

	var s2 := MutationSuite.new()
	s2.run()
	suites.append(s2)

	var s3 := SaveSuite.new()
	s3.run()
	suites.append(s3)

	var s4 := MonetizationSuite.new()
	s4.run()
	suites.append(s4)

	var s4b := DifficultySuite.new()
	s4b.run()
	suites.append(s4b)

	var s4c := GrowthSuite.new()
	s4c.run()
	suites.append(s4c)

	var s4d := ModesSuite.new()
	s4d.run()
	suites.append(s4d)

	var s4e := ChimesSuite.new()
	s4e.run()
	suites.append(s4e)

	var s5 := IntegrationSuite.new()
	await s5.run_async(get_tree())
	suites.append(s5)

	var s6 := VisualLabSuite.new()
	await s6.run_async(get_tree())
	suites.append(s6)

	var s7 := RenderSpikeSuite.new()
	await s7.run_async(get_tree())
	suites.append(s7)

	var s8 := Glade25DSuite.new()
	await s8.run_async(get_tree())
	suites.append(s8)

	var s9 := LakeProtoSuite.new()
	await s9.run_async(get_tree())
	suites.append(s9)

	var total_pass: int = 0
	var total_fail: int = 0
	for s in suites:
		total_pass += s.assertions_passed
		total_fail += s.assertions_failed
		print("  [%s] %s -> %d passed, %d failed" % [
			"PASS" if s.assertions_failed == 0 else "FAIL",
			s.suite_name,
			s.assertions_passed,
			s.assertions_failed
		])

	print("------------------------------------------------------------")
	print(" TOTAL ASSERTIONS: %d PASSED, %d FAILED" % [total_pass, total_fail])
	print("============================================================")

	get_tree().quit(0 if total_fail == 0 else 1)
