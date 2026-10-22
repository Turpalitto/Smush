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
	await _test_uncheated_combat_boss_and_high_load(tree, main_inst)
	await _test_defeat_revive_and_app_interruptions(tree, main_inst)
	await _test_evolution_queue_and_restart(tree, main_inst)
	await _test_verified_controls_visual_combat_and_audio_polish(tree, main_inst)

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
			if res == Vector2i(720, 1280):
				assert_true(_verify_panel_single_visible_child(main.menus), "No overlapping multi-child PanelContainer on page " + str(pg))

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
	assert_true(main.hud._dash_btn.visible, "Dash HUD button visible when Dash acquired")
	assert_true(main.hud._split_btn.visible, "Split HUD button visible when Split acquired")
	arena.player.trigger_dash()
	arena.player.trigger_split_clone()
	assert_eq(arena.active_clones.size(), 2, "Toxic Clones synergy spawns 2 clones")
	assert_true(arena.find_nearest_clone_decoy(arena.player.global_position, 220.0) != null, "Clone decoy actively registered for enemy aggro taunt")

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
	# A large XP grant can earn several drafts; finish them before combat resumes.
	var extra_choices := 0
	while App.state == App.State.MUTATION_DRAFT and extra_choices < 20:
		arena.select_draft_mutation(str(arena.current_draft_choices[0]["id"]))
		extra_choices += 1
	assert_eq(App.state, App.State.PLAYING, "Selecting all earned mutations resumes PLAYING")
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

	# Once results are banked, reviving would allow the same run to pay twice.
	main._start_run("quick")
	await tree.process_frame
	arena.player.invulnerable_timer = 0.0
	arena.player.shield_ready = false
	arena.player.take_damage(9999.0, "shadow_slime")
	arena.commit_run_rewards()
	var banked := SaveData.get_essence()
	arena.commit_run_rewards()
	assert_eq(SaveData.get_essence(), banked, "Result reward committed exactly once")
	assert_false(bool(App.last_run_summary["can_revive"]), "Banking reward removes revive offer")
	var denied := {"reason": ""}
	arena.try_revive_with_ad(func(_ok: bool, reason: String) -> void: denied["reason"] = reason)
	assert_eq(denied["reason"], "revive_not_allowed", "Committed run cannot revive and pay again")

	# Return to menu
	main._return_to_main_menu()
	assert_eq(App.state, App.State.MAIN_MENU, "Cleanly returned to MAIN_MENU")


func _test_evolution_queue_and_restart(tree: SceneTree, main: MainRoot) -> void:
	main._start_run("standard")
	await tree.process_frame
	var arena := main.arena
	arena.player.add_evolution_xp(500.0)
	assert_eq(main.draft_overlay._cards_box.get_child_count(), 3, "Draft displays exactly three cards")
	var initial_cards := arena.current_draft_choices.duplicate(true)
	arena.player.add_evolution_xp(1.0)
	assert_eq(arena.current_draft_choices, initial_cards, "Extra XP never replaces open mutation cards")
	assert_eq(arena.player.evolution_level, 1, "Pending evolution waits for current selection")
	arena.select_draft_mutation("not_offered")
	assert_eq(arena.player.mutations.get_total_picks(), 0, "Only offered mutations can be selected")
	assert_eq(App.state, App.State.MUTATION_DRAFT, "Invalid selection keeps draft open")
	var picks := 0
	while App.state == App.State.MUTATION_DRAFT and picks < 10:
		var card := main.draft_overlay._cards_box.get_child(0) as Button
		card.pressed.emit()
		picks += 1
		if App.state == App.State.MUTATION_DRAFT:
			assert_eq(main.draft_overlay._cards_box.get_child_count(), 3, "Chained draft replaces cards immediately")
	assert_eq(picks, 4, "501 XP produces four consecutive choices without another pickup")
	assert_eq(App.state, App.State.PLAYING, "Combat resumes after all earned choices")
	assert_approx(arena.player.evolution_xp, 145.0, 0.01, "Unspent evolution XP preserved")
	main.hud.joystick._begin_drag(0, Vector2(100, 100))
	main.hud.joystick._update_drag(Vector2(160, 100))
	arena.player.move_input = main.hud.joystick.output_vector
	App.change_state(App.State.PAUSED)
	assert_eq(main.hud.joystick.output_vector, Vector2.ZERO, "Pause releases joystick")
	assert_eq(arena.player.move_input, Vector2.ZERO, "Pause clears movement input")
	App.change_state(App.State.PLAYING)
	arena.player._electro_timer = 99.0
	arena.player._freeze_timer = 99.0
	arena.player._combat_quiet_timer = 0.0
	arena._enemy_spawn_timer = 99.0
	arena._orb_spawn_timer = 99.0
	main._start_run("standard")
	assert_eq(arena.player._electro_timer, 1.5, "Restart resets electric ability timing")
	assert_eq(arena.player._freeze_timer, 2.0, "Restart resets freeze timing")
	assert_eq(arena._enemy_spawn_timer, 0.5, "Restart restores opening enemy wave timing")
	assert_eq(arena._orb_spawn_timer, 0.3, "Restart restores early food spawn timing")
	assert_eq(arena.player.mutations.get_total_picks(), 0, "Run mutations do not leak into restart")
	main._return_to_main_menu()


func _verify_panel_single_visible_child(node: Node) -> bool:
	if node is PanelContainer and (node as Control).visible:
		var vis_cnt := 0
		for ch in node.get_children():
			if ch is Control and (ch as Control).visible:
				vis_cnt += 1
		if vis_cnt > 1:
			return false
	for ch in node.get_children():
		if not _verify_panel_single_visible_child(ch):
			return false
	return true


func _test_uncheated_combat_boss_and_high_load(tree: SceneTree, main: MainRoot) -> void:
	# 1. Verify floating joystick dynamic follow eliminates reversal dead-space
	SaveData.set_setting("joystick_mode", "floating")
	main.hud.joystick._begin_drag(0, Vector2(200, 900))
	main.hud.joystick._update_drag(Vector2(360, 900)) # dragged far past max_radius
	main.hud.joystick._update_drag(Vector2(280, 900)) # immediate reversal by 80px crosses center!
	assert_lt(main.hud.joystick.output_vector.x, 0.0, "Floating joystick dynamic follow reverses output immediately")
	main.hud.joystick.reset_stick()

	# 2. Verify Predator Flower ambush lunge covers its detection gap & enters vulnerable RECOVER
	main._start_run("standard")
	await tree.physics_frame
	var arena := main.arena
	arena.enemy_pool.release_all()
	var flower := arena.spawn_enemy_by_id("predator_flower", Vector2(160.0, 0.0))
	var start_x := flower.global_position.x
	for _i in range(72):
		flower._physics_process(1.0 / 60.0)
	assert_lt(flower.global_position.x, start_x - 140.0, "Predator flower lunge crosses 140+ px toward target")
	assert_eq(flower.fsm.state, EnemyFSM.State.RECOVER, "Predator flower enters vulnerable RECOVER after lunge")

	# 3. High-entity / FX load stress check + genuine uncheated combat defeat of Ancient Forest Guardian
	for i in range(32):
		var ang := (TAU / 32.0) * float(i)
		arena.spawn_enemy_by_id(ConfigDB.enemy_order[i % ConfigDB.enemy_order.size()], Vector2.from_angle(ang) * 420.0)
	for i in range(45):
		arena._spawn_orb(Vector2.from_angle(float(i) * 0.4) * 300.0, "spore", 0.4, 5.0, 0)

	var player := arena.player
	player.mass = 92.0
	player._sync_mass_metrics()
	for mid in ["dash", "spikes", "magnet", "electro_discharge", "shield", "freeze", "regeneration"]:
		player.mutations.apply_mutation(mid)
		player.mutations.apply_mutation(mid)

	var boss := arena.spawn_ancient_guardian_boss()
	boss.global_position = Vector2(0.0, -180.0)
	var phases_observed := {1: true}
	var dt := 1.0 / 60.0
	var max_combat_frames := int(65.0 / dt)
	var stress_t0 := Time.get_ticks_usec()

	for step_i in range(max_combat_frames):
		if App.state == App.State.MUTATION_DRAFT:
			arena.select_draft_mutation(str(arena.current_draft_choices[0]["id"]))
			continue
		if App.state == App.State.VICTORY or App.state == App.State.DEFEAT:
			break
		if is_instance_valid(boss):
			phases_observed[boss.phase] = true
			var to_b := boss.global_position - player.global_position
			var bd := maxf(1.0, to_b.length())
			var bdir := to_b / bd
			var steer := Vector2.ZERO
			if boss.action_state == AncientGuardianBoss.ActionState.TELEGRAPH_CHARGE or boss.action_state == AncientGuardianBoss.ActionState.CHARGING:
				steer = boss._charge_dir.orthogonal()
			elif boss.is_vulnerable() or boss.hp / boss.max_hp <= 0.06:
				steer = bdir
				if player.dash_cooldown <= 0.0:
					player.move_input = steer
					player.trigger_dash()
			else:
				var desired := 148.0
				steer = (bdir * clampf((bd - desired) / 60.0, -1.0, 1.0) + bdir.orthogonal() * 0.85).normalized()
				if player.dash_cooldown <= 0.0 and bd < 195.0:
					player.move_input = bdir
					player.trigger_dash()
			for n in arena.hazard_pool.get_active_items():
				var hz := n as HazardZone
				if hz != null and hz.visible and hz.kind != HazardZone.Kind.PLAYER_POISON and not hz._detonated:
					var dv := player.global_position - hz.global_position
					if dv.length() < hz.radius + player.get_radius() + 50.0:
						steer = (steer * 0.3 + dv.normalized() * 1.5).normalized()
			player.move_input = steer

		arena._physics_process(dt)
		player._physics_process(dt)
		for n in arena.enemy_pool.get_active_items():
			var en := n as EnemyEntity
			if en != null and en.visible:
				en._physics_process(dt)
		for n in arena.hazard_pool.get_active_items():
			var hz := n as HazardZone
			if hz != null and hz.visible:
				hz._process(dt)
		for n in arena.orb_pool.get_active_items():
			var ob := n as CollectibleOrb
			if ob != null and ob.visible:
				ob._process(dt)
		if is_instance_valid(boss) and boss.action_state != AncientGuardianBoss.ActionState.DEFEATED:
			boss._physics_process(dt)
		if step_i == 59:
			var avg_high_load_ms := float(Time.get_ticks_usec() - stress_t0) / 1000.0 / 60.0
			assert_lt(avg_high_load_ms, 8.0, "High-entity stress load stays well under 16.6ms frame budget")

	assert_true(phases_observed.has(1) and phases_observed.has(2) and phases_observed.has(3), "Normal uncheated combat traverses all 3 Guardian phases")
	assert_eq(App.state, App.State.VICTORY, "Ancient Forest Guardian defeated through genuine movement and combat mechanics")
	main._return_to_main_menu()


func _test_verified_controls_visual_combat_and_audio_polish(tree: SceneTree, main: MainRoot) -> void:
	# 1. Menu & Gameplay SlimeVisual foreground draw layer ordering above shader ColorRect
	assert_gt(main.menus._hero_slime._fg_overlay.get_index(), main.menus._hero_slime._jelly_rect.get_index(), "Menu slime foreground overlay renders above jelly shader rect")

	main._start_run("standard")
	await tree.process_frame
	await tree.process_frame
	var arena := main.arena
	var player := arena.player
	var hud := main.hud
	var joy := hud.joystick

	assert_gt(player.visual._fg_overlay.get_index(), player.visual._jelly_rect.get_index(), "Gameplay slime foreground overlay renders above jelly shader rect")

	# 2. Joystick excluded_zones prevent stealing touches over Dash/Split action buttons
	player.mutations.apply_mutation("dash")
	player.mutations.apply_mutation("split")
	await tree.process_frame
	hud._sync_joystick_skill_guard()
	var dash_local_center: Vector2 = (hud._dash_btn.global_position - joy.global_position) + hud._dash_btn.size * 0.5
	var touch_on_dash := InputEventScreenTouch.new()
	touch_on_dash.index = 4
	touch_on_dash.pressed = true
	touch_on_dash.position = dash_local_center
	joy._gui_input(touch_on_dash)
	assert_eq(joy._touch_index, -1, "Joystick ignores touch presses inside DashButton exclusion zone")

	# 3. Excursion-safe double-tap: micro-drag stutter (>12 px) never triggers accidental dash
	joy.reset_stick()
	var dtap_box := {"count": 0}
	var dtap_cb := func() -> void: dtap_box["count"] += 1
	joy.quick_double_tapped.connect(dtap_cb)

	var t1_down := InputEventScreenTouch.new()
	t1_down.index = 1
	t1_down.pressed = true
	t1_down.position = Vector2(220.0, 620.0)
	joy._gui_input(t1_down)
	var t1_drag := InputEventScreenDrag.new()
	t1_drag.index = 1
	t1_drag.position = Vector2(246.0, 620.0) # 26 px excursion (> 12 px)
	joy._gui_input(t1_drag)
	var t1_up := InputEventScreenTouch.new()
	t1_up.index = 1
	t1_up.pressed = false
	t1_up.position = Vector2(246.0, 620.0)
	joy._gui_input(t1_up)

	var t2_down := InputEventScreenTouch.new()
	t2_down.index = 1
	t2_down.pressed = true
	t2_down.position = Vector2(224.0, 620.0)
	joy._gui_input(t2_down)
	var t2_up := InputEventScreenTouch.new()
	t2_up.index = 1
	t2_up.pressed = false
	t2_up.position = Vector2(224.0, 620.0)
	joy._gui_input(t2_up)
	assert_eq(int(dtap_box["count"]), 0, "Stutter-step micro-drag followed by tap does not trigger accidental double-tap dash")

	# Genuine stationary quick double-tap DOES emit quick_double_tapped
	joy._last_tap_msec = -9999
	var s1_down := InputEventScreenTouch.new()
	s1_down.index = 2
	s1_down.pressed = true
	s1_down.position = Vector2(220.0, 620.0)
	joy._gui_input(s1_down)
	var s1_up := InputEventScreenTouch.new()
	s1_up.index = 2
	s1_up.pressed = false
	s1_up.position = Vector2(222.0, 620.0)
	joy._gui_input(s1_up)
	var s2_down := InputEventScreenTouch.new()
	s2_down.index = 2
	s2_down.pressed = true
	s2_down.position = Vector2(224.0, 620.0)
	joy._gui_input(s2_down)
	var s2_up := InputEventScreenTouch.new()
	s2_up.index = 2
	s2_up.pressed = false
	s2_up.position = Vector2(224.0, 620.0)
	joy._gui_input(s2_up)
	assert_eq(int(dtap_box["count"]), 1, "Stationary quick double-tap triggers responsive dash signal")
	joy.quick_double_tapped.disconnect(dtap_cb)
	joy.reset_stick()

	# 4. Boss <=6% HP execution bar prompt & transient toast cleanup across transitions
	Events.boss_spawned.emit("ancient_guardian", 100.0)
	Events.boss_updated.emit(5.0, 100.0, 3)
	var expected_cue := "ПОГЛОТИТЬ!" if Loc.current_locale == "ru" else "ABSORB!"
	assert_true(hud._boss_name_lbl.text.contains(expected_cue), "Boss HUD shows explicit ABSORB execution prompt at <=6% HP")
	Events.boss_defeated.emit("ancient_guardian")
	hud.show_toast("Test transient banner", Color.WHITE, 5.0)
	assert_true(hud._toast_panel.visible, "Toast visible when shown during active play")
	App.change_state(App.State.DEFEAT)
	assert_false(hud._toast_panel.visible, "Entering DEFEAT clears stale gameplay toast")
	main._start_run("standard")
	await tree.process_frame
	arena = main.arena
	player = arena.player
	assert_false(hud._toast_panel.visible or hud._toast_timer > 0.0, "Starting new run resets toast state")

	# 5. Miniboss contact hit cooldown + separation pushback prevents multi-hit overlap bursts
	arena.enemy_pool.release_all()
	player.global_position = Vector2.ZERO
	player.move_input = Vector2.ZERO
	player.hp = player.max_hp
	var miniboss := arena.spawn_enemy_by_id("umbral_alpha", Vector2(12.0, 0.0))
	var hits_taken := 0
	var prev_hp := player.hp
	var sep_after_first_hit := 0.0
	for f_idx in range(30):
		player.invulnerable_timer = 0.0 # even without player i-frames, enemy contact cd + pushback protects fairness
		arena._physics_process(1.0 / 60.0)
		if f_idx == 0:
			sep_after_first_hit = player.global_position.distance_to(miniboss.global_position)
		miniboss._physics_process(1.0 / 60.0)
		if player.hp < prev_hp - 0.01:
			hits_taken += 1
			prev_hp = player.hp
	assert_gt(sep_after_first_hit, player.get_radius() + miniboss.get_body_radius(), "Miniboss contact hit immediately separates overlapping bodies")
	assert_eq(hits_taken, 1, "Miniboss contact cooldown prevents multi-hit overlap burst within 0.5s")

	# 6. Audio Master limiter, priority voice-stealing protection, music default OFF & movement SFX gating
	var master_idx := AudioServer.get_bus_index("Master")
	var has_limiter := false
	for eff_i in range(AudioServer.get_bus_effect_count(master_idx)):
		var eff := AudioServer.get_bus_effect(master_idx, eff_i)
		if eff is AudioEffectHardLimiter:
			has_limiter = (eff as AudioEffectHardLimiter).ceiling_db <= -1.0
	assert_true(has_limiter, "Master bus has AudioEffectHardLimiter with ceiling <= -1.0 dB")
	var post_rec := Audio.create_post_limiter_recorder()
	var lim_info := Audio.get_master_limiter_info()
	var rec_idx := -1
	for eff_i in range(AudioServer.get_bus_effect_count(master_idx)):
		if AudioServer.get_bus_effect(master_idx, eff_i) == post_rec:
			rec_idx = eff_i
	assert_gt(rec_idx, int(lim_info["limiter_effect_index"]), "Post-limiter recorder is placed strictly downstream of AudioEffectHardLimiter")
	assert_approx(float(lim_info["bus_volume_db"]), 0.0, 0.01, "Master bus fader stays at 0.0 dB without post-limiter gain boost")
	AudioServer.remove_bus_effect(master_idx, rec_idx)
	assert_false(bool(SaveData.get_setting("music_enabled", false)), "Music remains disabled by default")

	var test_wav := AssetRegistry.get_wav_stream(Audio.SFX_PATHS["boss_warning"], false)
	for v_idx in range(Audio.SFX_POOL_SIZE):
		Audio._sfx_players[v_idx].stream = test_wav
		Audio._sfx_players[v_idx].play()
		Audio._player_events[v_idx] = "boss_warning"
	Audio._player_events[4] = "move"
	Audio._next_idx = 0
	var chosen_idx := Audio._select_voice_index(true)
	assert_eq(chosen_idx, 4, "Voice allocator steals the non-priority voice instead of active priority cues")
	Audio._player_events[4] = "boss_warning"
	assert_eq(Audio._select_voice_index(false), -1, "Non-priority SFX never steals a voice when all voices play priority cues")
	for p_stream in Audio._sfx_players:
		p_stream.stop()

	Audio._move_cooldown = 0.0
	player.move_input = Vector2.RIGHT
	player.velocity = Vector2(180.0, 0.0)
	player._physics_process(1.0 / 60.0) # triggers initial cruise move SFX -> sets _move_cooldown = 1.25s
	assert_gt(Audio._move_cooldown, 1.0, "Cruise movement sets 1.25s anti-drone SFX interval")
	for _s in range(36): # 0.60s straight-line cruise
		Audio._process(1.0 / 60.0)
		player._physics_process(1.0 / 60.0)
	assert_gt(Audio._move_cooldown, 0.5, "Straight-line cruise preserves >0.5s remaining cooldown instead of re-triggering at 0.52s")
	player.move_input = Vector2.LEFT # sharp reversal!
	player._physics_process(1.0 / 60.0)
	assert_lt(Audio._move_cooldown, 0.40, "Sharp direction turn shortens move SFX gate to responsive <=0.38s")
	for p_stream in Audio._sfx_players:
		p_stream.stop()

	main._return_to_main_menu()

