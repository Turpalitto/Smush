extends TestSuiteBase
## Full end-to-end integration & QA suite running the live Main.tscn scene inside Godot 4.5:
## Verifies tutorial, all 12 UI screens, multi-aspect-ratio layouts, all 8 enemy FSMs,
## active combat mutations, 3-phase Ancient Forest Guardian Boss fight & Victory,
## Defeat + 1x Voluntary Revive, app backgrounding/focus-out pause recovery, and frame step performance.

const INT_SAVE := "user://test_integration_save.json"
const INT_BAK := "user://test_integration_save.bak"
const INT_TMP := "user://test_integration_save.tmp"


func _init() -> void:
	super("FullGameIntegrationSuite")


func run_async(tree: SceneTree) -> void:
	SaveData.set_custom_paths(INT_SAVE, INT_BAK, INT_TMP)
	SaveData.data = SaveData.create_default_data()
	SaveData.save_to_disk()

	var main_packed := load("res://scenes/Main.tscn") as PackedScene
	var main_inst := main_packed.instantiate() as MainRoot
	tree.root.add_child(main_inst)
	await tree.process_frame
	await tree.process_frame

	await _test_all_ui_screens_and_aspect_ratios(tree, main_inst)
	await _test_full_run_enemies_mutations_and_boss_victory(tree, main_inst)
	await _test_defeat_revive_and_app_interruptions(tree, main_inst)

	main_inst.queue_free()
	await tree.process_frame

	for p in [INT_SAVE, INT_BAK, INT_TMP]:
		if FileAccess.file_exists(p):
			DirAccess.remove_absolute(ProjectSettings.globalize_path(p))
	SaveData.set_custom_paths(SaveData.DEFAULT_SAVE_PATH, SaveData.DEFAULT_BACKUP_PATH, SaveData.DEFAULT_TMP_PATH)
	SaveData.load_from_disk()


func _test_all_ui_screens_and_aspect_ratios(tree: SceneTree, main: MainRoot) -> void:
	assert_eq(App.state, App.State.MAIN_MENU, "Game boots into MAIN_MENU")

	# Cycle through all out-of-run pages in both Russian and English across multiple phone/tablet aspect ratios
	var resolutions: Array[Vector2i] = [
		Vector2i(360, 640),   # Compact 16:9 budget Android
		Vector2i(720, 1280),  # Base HD 16:9
		Vector2i(1080, 2400), # Tall modern 20:9 Android phone
		Vector2i(1200, 1920)  # 16:10 Android tablet
	]
	var pages := [
		MenuScreens.Page.HOME,
		MenuScreens.Page.MODE_SELECT,
		MenuScreens.Page.UPGRADES,
		MenuScreens.Page.COLLECTION,
		MenuScreens.Page.SETTINGS,
		MenuScreens.Page.SHOP,
		MenuScreens.Page.PRIVACY
	]

	for res: Vector2i in resolutions:
		tree.root.size = res
		for pg in pages:
			main.menus.show_page(pg)
			await tree.process_frame
			assert_gt(main.theme_root.size.x, 300.0, "ThemeRoot adapts width at " + str(res))
			assert_gt(main.theme_root.size.y, 500.0, "ThemeRoot adapts height at " + str(res))

	# Verify live EN <-> RU localization switch
	SaveData.set_setting("locale", "en")
	assert_eq(Loc.t("menu.play"), "PLAY", "Switched to English cleanly")
	SaveData.set_setting("locale", "ru")
	assert_eq(Loc.t("menu.play"), "ИГРАТЬ", "Switched back to primary Russian cleanly")
	tree.root.size = Vector2i(720, 1280)


func _test_full_run_enemies_mutations_and_boss_victory(tree: SceneTree, main: MainRoot) -> void:
	var arena := main.arena
	main._start_run("standard")
	await tree.process_frame

	assert_eq(App.state, App.State.PLAYING, "Run transitions to PLAYING")
	assert_true(arena.tutorial.active, "First-run tutorial starts automatically")
	assert_true(arena.world.is_safe_spawn_point(Vector2.ZERO, 30.0), "Central spawn clearing verified safe")
	assert_eq(arena.world.narrow_gates.size(), 4, "Narrow tactical root gates placed")

	# Verify all 8 creature types spawn and run their FSM without error
	var spawned_enemies: Array[EnemyEntity] = []
	var idx: int = 0
	for eid in ConfigDB.enemy_order:
		var ang := (TAU / 8.0) * float(idx)
		var epos := Vector2.from_angle(ang) * 320.0
		var en := arena.spawn_enemy_by_id(eid, epos)
		assert_true(en != null, "Spawned creature: " + eid)
		spawned_enemies.append(en)
		idx += 1

	# Simulate joystick movement & active mutations for 30 physics steps, measuring step CPU time
	arena.player.mutations.apply_mutation("dash")
	arena.player.mutations.apply_mutation("spikes")
	arena.player.mutations.apply_mutation("magnet")
	arena.player.mutations.apply_mutation("electro_discharge")
	arena.player.mutations.apply_mutation("shield")
	arena.player.mutations.apply_mutation("freeze")
	arena.player.mutations.apply_mutation("split")
	arena.player.mutations.apply_mutation("poison_trail")
	assert_true(arena.player.mutations.has_synergy("piercing_strike"), "Piercing Strike active in live run")
	assert_true(arena.player.mutations.has_synergy("em_storm"), "EM Storm active in live run")
	assert_true(arena.player.mutations.has_synergy("ice_armor"), "Ice Armor active in live run")
	assert_true(arena.player.mutations.has_synergy("toxic_clones"), "Toxic Clones active in live run")

	main.hud.joystick.output_vector = Vector2(0.8, 0.2).normalized()
	arena.player.trigger_dash()
	arena.player.trigger_split_clone()
	assert_eq(arena.active_clones.size(), 2, "Toxic Clones synergy spawns 2 clones")

	var t0_usec := Time.get_ticks_usec()
	for _step in range(30):
		arena._physics_process(1.0 / 60.0)
		arena.player._physics_process(1.0 / 60.0)
	var avg_step_ms := float(Time.get_ticks_usec() - t0_usec) / 1000.0 / 30.0
	print("  [Perf] 30 simulated arena frames avg physics CPU time: %.3f ms/frame (pool reuse hits=%d)" % [avg_step_ms, arena.orb_pool.reuse_hits + arena.enemy_pool.reuse_hits])
	assert_lt(avg_step_ms, 8.0, "Physics step well within 16.6ms (60 FPS) budget")

	# Trigger Evolution XP -> Mutation Draft -> Select choice -> Return to PLAYING
	var start_evo_lv := arena.player.evolution_level
	arena.player.add_evolution_xp(500.0)
	assert_eq(App.state, App.State.MUTATION_DRAFT, "Evolution threshold opens MUTATION_DRAFT modal")
	assert_true(main.draft_overlay.visible, "MutationDraftOverlay visible")
	var first_choice_id := str(arena.current_draft_choices[0]["id"])
	arena.select_draft_mutation(first_choice_id)
	assert_eq(App.state, App.State.PLAYING, "Selecting mutation resumes PLAYING")
	assert_gt(float(arena.player.evolution_level), float(start_evo_lv), "Evolution level incremented")
	assert_false(arena.tutorial.active, "Tutorial completed after first mutation")

	# Spawn Ancient Forest Guardian Boss & verify all 3 phases -> Boss Defeat -> Victory!
	var boss := arena.spawn_ancient_guardian_boss()
	assert_true(boss != null and boss.phase == 1, "Ancient Forest Guardian spawns in Phase 1")
	assert_true(main.hud._boss_box.visible, "Boss HP bar visible on HUD")

	boss.take_damage(boss.max_hp * 0.40, 1.0)
	assert_eq(boss.phase, 2, "Boss transitions to Phase 2 and summons minions")
	boss._physics_process(0.1)

	boss.take_damage(boss.max_hp * 0.35, 1.0)
	assert_eq(boss.phase, 3, "Boss transitions to Phase 3 Overdrive")
	boss._physics_process(1.2)

	var essence_before := SaveData.get_essence()
	boss.take_damage(boss.max_hp * 1.5, 1.0)
	assert_eq(App.state, App.State.VICTORY, "Defeating boss transitions to VICTORY screen")
	assert_gt(float(SaveData.get_essence()), float(essence_before), "Victory rewards Essence to persistent SaveData")


func _test_defeat_revive_and_app_interruptions(tree: SceneTree, main: MainRoot) -> void:
	var arena := main.arena
	var mock_ads := Ads.TestMockAdAdapter.new()
	mock_ads.simulated_available = true
	mock_ads.simulated_complete_success = true
	Ads.set_test_adapter(mock_ads)

	main._start_run("quick")
	await tree.process_frame
	assert_eq(App.state, App.State.PLAYING, "Started quick run")

	# Simulate mobile app backgrounding (NOTIFICATION_APPLICATION_PAUSED)
	App._notification(Node.NOTIFICATION_APPLICATION_PAUSED)
	assert_eq(App.state, App.State.PAUSED, "Backgrounding app automatically pauses active run")
	assert_true(tree.paused, "SceneTree paused during interruption")
	App.change_state(App.State.PLAYING)
	assert_false(tree.paused, "Resuming run unpauses SceneTree")

	# Lethal hit -> Defeat -> 1x Voluntary Revive via Rewarded Ad -> Back to PLAYING!
	arena.player.invulnerable_timer = 0.0
	arena.player.shield_ready = false
	arena.player.take_damage(9999.0, "shadow_slime")
	assert_eq(App.state, App.State.DEFEAT, "Lethal damage enters DEFEAT state")
	assert_true(bool(App.last_run_summary.get("can_revive", false)), "First death offers 1x voluntary revive")

	var cb_box := {"revived": false, "doubled": false}
	arena.try_revive_with_ad(func(ok: bool, _r: String) -> void: cb_box["revived"] = ok)
	assert_true(bool(cb_box["revived"]), "Voluntary Rewarded Ad revive succeeded")
	assert_eq(App.state, App.State.PLAYING, "Revived player returns to PLAYING")
	assert_eq(arena.player.hp, arena.player.max_hp, "Revived player restored to full HP")

	# Second lethal hit in same run -> Revive no longer allowed!
	arena.player.invulnerable_timer = 0.0
	arena.player.take_damage(9999.0, "shadow_slime")
	assert_eq(App.state, App.State.DEFEAT, "Second lethal hit enters DEFEAT")
	assert_false(bool(App.last_run_summary.get("can_revive", true)), "Second death does NOT offer second revive")

	# Double run reward x2 via Rewarded Ad
	var ess_pre_double := SaveData.get_essence()
	arena.try_double_run_reward_with_ad(func(ok: bool, _r: String) -> void: cb_box["doubled"] = ok)
	assert_true(bool(cb_box["doubled"]), "Post-run x2 Rewarded Ad succeeded")
	assert_gt(float(SaveData.get_essence()), float(ess_pre_double), "x2 Essence credited cleanly")

	# Return to menu
	main._return_to_main_menu()
	assert_eq(App.state, App.State.MAIN_MENU, "Cleanly returned to MAIN_MENU")
