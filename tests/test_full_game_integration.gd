extends "res://tests/TestSuiteBase.gd"
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
	await _test_difficulty_multipliers(tree, main_inst)
	await _test_miniboss_dismissed_by_boss(tree, main_inst)
	await _test_endless_and_zen_modes(tree, main_inst)
	await _test_moss_trail_and_caustics(tree, main_inst)

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

	# --- Environment art: painted props + the seamless floor tile -----------------
	# The props replaced drawn primitives, so the thing worth asserting is that the
	# sprite actually exists for every obstacle (a missing texture would silently
	# fall back to a flat circle and the arena would look like placeholder art again).
	for prop_id in ["root_pillar", "rune_stone", "mana_crystal", "mushroom_cluster", "fern_cluster"]:
		var prop_path: String = "res://resources/art/props/%s.png" % prop_id
		# Through AssetRegistry, because that is what the generator uses. Asserting
		# ResourceLoader.exists() here tested the editor import cache rather than the
		# game: it passed on a developer machine and failed in the packed QA build,
		# where the same PNG is present but has no .import remap.
		var prop_tex := AssetRegistry.get_texture(prop_path)
		assert_true(prop_tex != null, "Prop art loads: " + prop_id)
		if prop_tex != null:
			assert_eq(prop_tex.get_width(), 256, "Prop art is 256 px wide: " + prop_id)

	# --- Endless world: chunks instead of an arena ---------------------------------
	# The world used to be a 2560 px box with a drawn rim and a hedge along it. The
	# thing worth asserting now is the opposite: that nothing marks an edge, that the
	# forest is streamed around wherever the player is, and that it is the *same*
	# forest when they walk away and come back.
	var chunk_root := arena.world.get_node_or_null("Chunks") as Node2D
	assert_true(chunk_root != null, "Chunk root exists")
	assert_true(arena.world.get_node_or_null("BorderHedge") == null,
		"No border hedge: the world has no edge to draw")
	assert_gt(float(arena.camera.limit_right), 1000000.0,
		"Camera is not clamped to an arena")

	var chunk_count := 0
	var prop_sprites := 0
	var bodies := 0
	if chunk_root != null:
		for chunk in chunk_root.get_children():
			chunk_count += 1
			for ch in chunk.get_children():
				if ch is Sprite2D:
					prop_sprites += 1
				elif ch is StaticBody2D:
					bodies += 1

	assert_gt(float(chunk_count), 40.0, "A ring of chunks is built around the player")
	assert_eq(arena.world.streamed_chunk_count(), chunk_count, "Chunk registry matches the node tree")
	assert_gt(float(arena.world.obstacles.size()), 40.0, "The forest has props in every direction")
	assert_eq(bodies, arena.world.obstacles.size(),
		"Every obstacle has a collision body, not just a sprite")

	var painted_plants := 0
	var swaying_plants := 0
	for d in arena.world.decor_flora:
		var dk := int(d["kind"])
		if dk == 1:
			continue
		painted_plants += 1
		if float(WorldGenerator.DECOR_KINDS[dk].get("sway", 0.0)) > 0.0:
			swaying_plants += 1
	assert_eq(prop_sprites, arena.world.obstacles.size() + painted_plants,
		"Every prop and every painted plant is a real sprite")
	assert_eq(arena.world._swayers.size(), swaying_plants,
		"Every plant that should move with the spores does (and only those)")
	# The floor shader hazes out with distance, and ArenaController says in so many
	# words that props recede with it. They did not: props were never registered for
	# the haze, so the big silhouettes stayed at full brightness on a greying floor.
	# Set membership, not a count: the haze list also holds the four root gates,
	# which live outside the chunk tree on purpose (they are not streamed).
	var fogged_nodes := {}
	for f in arena.world._fogged:
		fogged_nodes[f["node"]] = true
	var unfogged := 0
	if chunk_root != null:
		for chunk in chunk_root.get_children():
			for ch in chunk.get_children():
				if ch is Sprite2D and not fogged_nodes.has(ch):
					unfogged += 1
	assert_eq(unfogged, 0, "Every world sprite is registered for the distance haze")

	# ...and the fade actually runs. Pixel diffs cannot show this: two runs differ by
	# more from random entities than from the haze, so the check is on the sprite.
	var fog_target: Dictionary = {}
	for f in arena.world._fogged:
		if f["base"] == WorldGenerator.PROP_TINT:
			fog_target = f
			break
	assert_false(fog_target.is_empty(), "Props are registered for the distance haze")
	if not fog_target.is_empty():
		var fog_sp := fog_target["node"] as Sprite2D
		var fog_pos := fog_sp.position
		arena.world._apply_fog(fog_pos + Vector2(WorldGenerator.FOG_END + 200.0, 0.0))
		assert_eq(fog_sp.modulate.a, 0.0, "A prop past the haze end is fully dissolved")
		arena.world._apply_fog(fog_pos)
		assert_eq(fog_sp.modulate.a, 1.0, "A prop at the player is fully opaque again")
		assert_eq(fog_sp.modulate, WorldGenerator.PROP_TINT, "And it is back to its own tint")

	# The undergrowth set is what stops one fern sprite from repeating hundreds of
	# times per screen. If any of these goes missing the world quietly falls back to
	# a single silhouette everywhere, which is exactly what it looked like before.
	for under_id in ["broadleaf_clump", "grass_tuft", "fallen_branch", "glow_shrooms", "root_cluster"]:
		var under_path: String = "res://resources/art/props/%s.png" % under_id
		var under_tex := AssetRegistry.get_texture(under_path)
		assert_true(under_tex != null, "Undergrowth art loads: " + under_id)
		if under_tex != null:
			assert_eq(under_tex.get_width(), 256, "Undergrowth art is 256 px wide: " + under_id)

	# Walking 4 km east and back must not change what grows at the origin.
	var sig_before := ""
	for ob in arena.world.obstacles:
		if ob.get("chunk") == Vector2i.ZERO:
			var bp: Vector2 = ob["pos"]
			sig_before += "%.1f,%.1f;" % [bp.x, bp.y]
	arena.world.stream_around(Vector2(4096.0, 4096.0), true)
	assert_gt(float(arena.world.streamed_chunk_count()), 40.0,
		"The forest streams in around a point far from the spawn")
	var strays := 0
	# FREE_RADIUS chunks survive the move (hysteresis: a chunk is never freed in the
	# same step that builds its replacement), so the honest bound is that ring, not
	# the stream radius.
	var leash := float(WorldGenerator.FREE_RADIUS + 2) * WorldGenerator.CHUNK_SIZE
	for ob in arena.world.obstacles:
		var op: Vector2 = ob["pos"]
		if op.distance_to(Vector2(4096.0, 4096.0)) > leash:
			strays += 1
	assert_eq(strays, 0, "Streamed props stay around the player")
	arena.world.stream_around(Vector2.ZERO, true)
	var sig_after := ""
	for ob in arena.world.obstacles:
		if ob.get("chunk") == Vector2i.ZERO:
			var ap: Vector2 = ob["pos"]
			sig_after += "%.1f,%.1f;" % [ap.x, ap.y]
	assert_eq(sig_after, sig_before, "The forest is identical when you walk away and come back")

	# Nothing clamps the player to a box any more.
	var far_point := Vector2(9000.0, -7000.0)
	assert_true(arena.constrain_player_position(far_point, 24.0, false).is_equal_approx(far_point),
		"A point 11 km out is a legal position: there is no wall")

	# Floor tile: seamless by construction, but a replaced or re-exported PNG could
	# still reintroduce a grid, so the wrap step is compared against the interior.
	var floor_tex := AssetRegistry.get_texture(ArenaController.FLOOR_TEXTURE_PATH)
	assert_true(floor_tex != null, "Floor tile loads")
	if floor_tex != null:
		assert_eq(floor_tex.get_width(), 1024, "Floor tile is 1024 px")
		var fimg := floor_tex.get_image()
		assert_true(fimg != null and not fimg.is_empty(), "Floor tile has readable pixels")
		if fimg != null and not fimg.is_empty():
			var fw := fimg.get_width()
			var seam := 0.0
			var interior := 0.0
			for fy in range(fw):
				seam += absf(fimg.get_pixel(0, fy).get_luminance() - fimg.get_pixel(fw - 1, fy).get_luminance())
				var mid := fw / 2
				interior += absf(fimg.get_pixel(mid, fy).get_luminance() - fimg.get_pixel(mid + 1, fy).get_luminance())
			seam /= float(fw)
			interior /= float(fw)
			assert_lte(seam, interior * 3.0 + 0.01,
				"Floor tile wrap seam (%.4f) is no worse than an interior step (%.4f)" % [seam, interior])

	assert_true(arena.canopy_mat != null, "Canopy material exists")
	if arena.canopy_mat != null:
		assert_true(arena.canopy_mat.get_shader_parameter("floor_tex") != null,
			"Arena background received the floor tile")
		# Checked for null first: float(null) is a script error, not a failed assert,
		# and it used to mask the real message ("the material never got the tile").
		var strength: Variant = arena.canopy_mat.get_shader_parameter("floor_strength")
		assert_true(strength != null and float(strength) > 0.5,
			"Floor tile actually modulates the arena background")

	# Relief and occlusion: both are separate maps derived from the same height
	# field, both are optional in the shader, so a silent loss of either would go
	# unnoticed until someone looked at the floor.
	var normal_tex := AssetRegistry.get_texture(ArenaController.FLOOR_NORMAL_PATH)
	assert_true(normal_tex != null, "Floor normal map loads")
	if normal_tex != null:
		assert_eq(normal_tex.get_width(), 1024, "Floor normal map is 1024 px")
		var nimg := normal_tex.get_image()
		# A tangent-space normal map of a mostly-flat surface sits near (0.5, 0.5, 1):
		# blue close to 1 and the red/green centred on 0.5 with a little spread.
		var bsum := 0.0
		var xyspread := 0.0
		var ncount := 0
		for ny in range(0, nimg.get_height(), 8):
			for nx in range(0, nimg.get_width(), 8):
				var c := nimg.get_pixel(nx, ny)
				bsum += c.b
				xyspread += absf(c.r - 0.5) + absf(c.g - 0.5)
				ncount += 1
		var bmean := bsum / float(maxi(1, ncount))
		var xymean := xyspread / float(maxi(1, ncount))
		assert_gt(bmean, 0.80, "Normal map blue channel is mostly up (%.2f)" % bmean)
		assert_gt(xymean, 0.02, "Normal map has real slopes (%.3f)" % xymean)
	var ao_tex := AssetRegistry.get_texture(ArenaController.FLOOR_AO_PATH)
	assert_true(ao_tex != null, "Floor AO map loads")
	if ao_tex != null:
		assert_eq(ao_tex.get_width(), 1024, "Floor AO map is 1024 px")
		var aimg := ao_tex.get_image()
		# A failed bake would come back flat; real occlusion always has spread.
		var amin := 1.0
		var amax := 0.0
		var asum := 0.0
		var acount := 0
		for ay in range(0, aimg.get_height(), 8):
			for ax in range(0, aimg.get_width(), 8):
				var v := aimg.get_pixel(ax, ay).r
				amin = minf(amin, v)
				amax = maxf(amax, v)
				asum += v
				acount += 1
		var amean := asum / float(maxi(1, acount))
		assert_gt(amax - amin, 0.35, "AO map has real contrast (%.2f)" % (amax - amin))
		assert_true(amean > 0.45 and amean < 0.90,
			"AO map mean is in a sane range (%.2f)" % amean)
	# Canopy light: the fourth map, and the only one that is not the floor itself.
	var light_tex := AssetRegistry.get_texture(ArenaController.FLOOR_LIGHT_PATH)
	assert_true(light_tex != null, "Canopy light map loads")
	if light_tex != null:
		assert_eq(light_tex.get_width(), 1024, "Canopy light map is 1024 px")
		var limg := light_tex.get_image()
		var lmin := 1.0
		var lmax := 0.0
		var lsum := 0.0
		var lcount := 0
		for ly in range(0, limg.get_height(), 8):
			for lx in range(0, limg.get_width(), 8):
				var v := limg.get_pixel(lx, ly).r
				lmin = minf(lmin, v)
				lmax = maxf(lmax, v)
				lsum += v
				lcount += 1
		var lmean := lsum / float(maxi(1, lcount))
		assert_gt(lmax - lmin, 0.70, "Canopy light has full range (%.2f)" % (lmax - lmin))
		# A canopy that is too dense bakes nearly black, too sparse nearly white.
		assert_true(lmean > 0.30 and lmean < 0.72,
			"Canopy light is dappled, not solid or empty (%.2f)" % lmean)
		# The tile has to repeat: the border must not be a step. Sampled the same way
		# the bake script measures it, against the interior step.
		var seam := 0.0
		var interior := 0.0
		for ly in range(limg.get_height()):
			seam += absf(limg.get_pixel(0, ly).r - limg.get_pixel(limg.get_width() - 1, ly).r)
			var mid := limg.get_width() / 2
			interior += absf(limg.get_pixel(mid, ly).r - limg.get_pixel(mid + 1, ly).r)
		seam /= float(limg.get_height())
		interior /= float(limg.get_height())
		assert_lte(seam, interior * 3.0 + 0.02,
			"Canopy light wrap seam (%.4f) is no worse than an interior step (%.4f)" % [seam, interior])
	if arena.canopy_mat != null:
		assert_true(arena.canopy_mat.get_shader_parameter("floor_normal") != null,
			"Arena background received the normal map")
		assert_gt(float(arena.canopy_mat.get_shader_parameter("floor_relief")), 0.5,
			"Relief is switched on")
		assert_true(arena.canopy_mat.get_shader_parameter("floor_ao") != null,
			"Arena background received the AO map")
		assert_gt(float(arena.canopy_mat.get_shader_parameter("floor_occlusion")), 0.1,
			"Occlusion is switched on")
		assert_true(arena.canopy_mat.get_shader_parameter("floor_light") != null,
			"Arena background received the canopy light")
		assert_gt(float(arena.canopy_mat.get_shader_parameter("floor_dapple")), 0.1,
			"Canopy light modulates the arena")
		assert_gt(float(arena.canopy_mat.get_shader_parameter("floor_mist")), 0.1,
			"Shade haze is switched on")

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

	# 5b. Game feel: shake decays to rest, hit-stop restores, low-HP vignette reacts
	arena.camera.offset = Vector2.ZERO
	arena._shake_time = 0.0
	arena.add_shake(18.0, 0.3)
	assert_eq(arena._shake_strength, 18.0, "add_shake records the requested strength")
	arena._update_game_feel(1.0 / 60.0)
	assert_gt(arena.camera.offset.length(), 0.5, "Shake displaces the camera on the first frame")
	for _f in range(30):
		arena._update_game_feel(1.0 / 60.0)
	assert_true(arena.camera.offset.length() < 0.01, "Shake returns the camera to rest after its duration")

	arena.add_shake(30.0, 0.5)
	arena.add_shake(4.0, 0.1)
	assert_eq(arena._shake_strength, 30.0, "Overlapping shakes keep the strongest value instead of stacking")

	Engine.time_scale = 1.0
	arena.add_hitstop(0.09, 0.12)
	assert_true(Engine.time_scale < 0.2, "Hit-stop slows the engine clock")
	arena._end_hitstop()
	assert_eq(Engine.time_scale, 1.0, "Hit-stop timer restores Engine.time_scale to 1.0")

	var saved_hp := player.hp
	player.hp = player.max_hp * 0.1
	for _f in range(20):
		arena._update_game_feel(1.0 / 60.0)
	assert_gt(arena._vignette_alpha, 0.05, "Low HP raises the vignette alpha")
	player.hp = player.max_hp
	for _f in range(60):
		arena._update_game_feel(1.0 / 60.0)
	assert_true(arena._vignette_alpha < 0.02, "Healing back to full clears the vignette")
	player.hp = saved_hp

	# 6. Audio Master limiter, priority voice-stealing protection, music default ON & movement SFX gating
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
	assert_true(bool(SaveData.get_setting("music_enabled", false)), "Music is ON by default (the game ships a soundtrack)")

	# 6b. Soundtrack: four composed loops load, loop, and the director switches between them
	assert_eq(Audio.MUSIC_TRACKS.size(), 4, "Soundtrack ships four tracks (menu / run / boss / zen)")
	var expected_lengths := {"menu": 26.7, "run": 38.4, "boss": 30.5, "zen": 32.0}
	var seen_streams: Array[AudioStream] = []
	for track_id in Audio.MUSIC_TRACKS.keys():
		var path := str(Audio.MUSIC_TRACKS[track_id])
		assert_true(FileAccess.file_exists(path), "Music file exists: " + path)
		var stream := AssetRegistry.get_audio_stream(path, true)
		assert_true(stream != null, "Music stream decodes: " + str(track_id))
		if stream == null:
			continue
		assert_approx(stream.get_length(), float(expected_lengths[track_id]), 1.5,
			"Track length matches the composed loop: " + str(track_id))
		var ogg := stream as AudioStreamOggVorbis
		assert_true(ogg != null and ogg.loop, "Music stream is set to loop: " + str(track_id))
		assert_false(seen_streams.has(stream), "Each music track is a distinct stream")
		seen_streams.append(stream)
		assert_true(AssetRegistry.get_audio_stream(path, true) == stream, "Music streams are cached, not re-decoded")

	Audio.play_music("run")
	assert_eq(Audio.current_music_id(), "run", "Director switches to the exploration track on a run")
	Audio.play_music("boss")
	assert_eq(Audio.current_music_id(), "boss", "Director switches to the boss track when the boss spawns")
	Audio.play_music("does_not_exist")
	assert_eq(Audio.current_music_id(), "boss", "Unknown track ids are ignored instead of silencing the music")
	Audio.stop_music(0.1)
	assert_eq(Audio.current_music_id(), "", "stop_music clears the current track id")

	# 6c. Haptics: gated off-device, and the tables stay inside sensible ranges
	assert_false(Haptics.is_supported(), "Haptics are gated to mobile platforms (desktop has no vibrator)")
	SaveData.set_setting("haptics_enabled", true)
	assert_false(Haptics.is_enabled(), "Haptics stay disabled on desktop even when the setting is on")
	Haptics.play("damage")
	Haptics.reset_for_tests()
	assert_eq(Haptics.DURATION_MS.size(), Haptics.MIN_GAP_MS.size(), "Every haptic kind has both a duration and a gap")
	for kind in Haptics.DURATION_MS.keys():
		assert_true(Haptics.MIN_GAP_MS.has(kind), "Haptic gap defined for kind: " + str(kind))
		var dur := int(Haptics.DURATION_MS[kind])
		assert_true(dur >= 10 and dur <= 130, "Haptic pulse length is perceptible but not a rattle: " + str(kind))
		assert_true(int(Haptics.MIN_GAP_MS[kind]) >= dur, "Haptic gap is at least as long as the pulse: " + str(kind))
	SaveData.set_setting("haptics_enabled", true)

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



func _test_difficulty_multipliers(tree: SceneTree, main: MainRoot) -> void:
	# Difficulty is applied at spawn time on top of the existing time-based scaling.
	# Both runs below are spawned at the same run_elapsed (0), so the only difference
	# between them is the difficulty snapshot taken by start_new_run.
	var arena := main.arena

	SaveData.set_difficulty("normal")
	main._start_run("standard")
	await tree.process_frame
	assert_eq(str(arena.difficulty_cfg.get("id", "")), "normal", "Run snapshots the selected difficulty")
	var base_enemy := arena.spawn_enemy_by_id("forest_beetle", Vector2(120.0, 0.0))
	assert_true(base_enemy != null, "Baseline enemy spawned")
	var base_hp := base_enemy.max_hp
	var base_dmg := base_enemy.contact_damage
	var base_boss := arena.spawn_ancient_guardian_boss()
	assert_true(base_boss != null, "Baseline boss spawned")
	var base_boss_hp := base_boss.max_hp
	var base_boss_dmg := base_boss.contact_damage

	SaveData.set_difficulty("hunter")
	main._start_run("standard")
	await tree.process_frame
	var hard_enemy := arena.spawn_enemy_by_id("forest_beetle", Vector2(120.0, 0.0))
	# The enemy pool recycles nodes between runs, so the reference is reused by the next
	# spawn; the value must be captured now or the comparison below reads itself.
	var hard_hp := hard_enemy.max_hp
	var hard_boss := arena.spawn_ancient_guardian_boss()
	assert_approx(hard_enemy.max_hp / base_hp, 1.25, 0.02, "Hunter raises enemy HP by its multiplier")
	assert_approx(hard_enemy.hp, hard_enemy.max_hp, 0.01, "Scaled enemy spawns at full HP")
	assert_approx(hard_enemy.contact_damage / base_dmg, 1.2, 0.02, "Hunter raises enemy contact damage")
	assert_approx(hard_boss.max_hp / base_boss_hp, 1.2, 0.02, "Hunter raises boss HP by its own multiplier")
	assert_approx(hard_boss.contact_damage / base_boss_dmg, 1.2, 0.02, "Hunter raises boss contact damage")

	SaveData.set_difficulty("nightmare")
	main._start_run("standard")
	await tree.process_frame
	var nm_enemy := arena.spawn_enemy_by_id("forest_beetle", Vector2(120.0, 0.0))
	assert_approx(nm_enemy.max_hp / base_hp, 1.5, 0.02, "Nightmare raises enemy HP by its multiplier")
	assert_gt(nm_enemy.max_hp, hard_hp, "Nightmare enemies are tougher than Hunter ones")

	# The run-level snapshot must not follow a later settings change mid-run.
	SaveData.set_difficulty("normal")
	await tree.process_frame
	assert_eq(str(arena.difficulty_cfg.get("id", "")), "nightmare", "Mid-run difficulty change does not affect a live run")

	SaveData.set_difficulty("normal")
	main._return_to_main_menu()
	await tree.process_frame
	# The boss spawned for this check is not owned by a finished run, so free it here.
	if is_instance_valid(arena.active_boss):
		arena.active_boss.queue_free()
		arena.active_boss = null
	await tree.process_frame
	assert_eq(App.state, App.State.MAIN_MENU, "Returned to menu after difficulty checks")


## The Guardian arrives alone. A live miniboss would keep landing 20-damage contacts in
## the middle of the phase telegraphs: the automated run lost 60 HP that way at 281/298/
## 300 s while the boss was charging, which makes a fair fight unreadable.
func _test_miniboss_dismissed_by_boss(tree: SceneTree, main: MainRoot) -> void:
	main._start_run("standard")
	await tree.process_frame
	var arena := main.arena
	arena.miniboss_spawned = false
	arena.miniboss_spawn_time = 0.0
	arena._process_spawning_and_waves(0.016)
	var mb := arena._tracked_miniboss
	assert_true(mb != null and mb.is_active_combatant(), "Miniboss spawns and is tracked before the boss")
	if mb == null:
		main._return_to_main_menu()
		await tree.process_frame
		return

	var boss := arena.spawn_ancient_guardian_boss()
	assert_true(boss != null, "Boss still spawns when the miniboss is alive")
	assert_true(arena._tracked_miniboss == null, "Boss spawn clears the tracked miniboss")
	# Releasing to the pool is what removes an enemy from play; the FSM state is left
	# alone, so the assertion has to look at the pool and the node, not at the state.
	assert_false(arena.enemy_pool.get_active_items().has(mb), "Miniboss leaves the active enemy pool")
	assert_false(mb.visible, "Miniboss is hidden, so it cannot fight beside the Guardian")

	if is_instance_valid(boss):
		boss.queue_free()
		arena.active_boss = null
	main._return_to_main_menu()
	await tree.process_frame
	assert_eq(App.state, App.State.MAIN_MENU, "Returned to menu after the miniboss dismissal check")


func _test_endless_and_zen_modes(tree: SceneTree, main: MainRoot) -> void:
	## Runtime behaviour of the two new modes. The unit suite checks the rule table;
	## this checks that a live arena actually obeys it, because the failure mode here
	## is a rule that exists but is never read.
	var arena := main.arena

	# --- endless: the Guardian falls, the grove wakes, the run goes on -------------
	main._start_run("endless")
	await tree.process_frame
	assert_eq(arena.mode_id, "endless", "Endless run started")
	assert_eq(arena.ascension_loop, 0, "A fresh endless run starts at loop 0")
	assert_eq(App.state, App.State.PLAYING, "Endless run is playing")

	arena.player.hp = arena.player.max_hp * 0.30
	# Essence from an awakening goes into the run's pool, not straight into the save:
	# it is committed with the rest of the run, so the pool is what must grow here.
	var run_essence_before := arena.run_essence_earned
	var boss1 := arena.spawn_ancient_guardian_boss()
	assert_true(boss1 != null, "Guardian spawns in endless mode")
	boss1.take_damage(boss1.max_hp * 1.5, 1.0)
	await tree.process_frame

	assert_eq(App.state, App.State.PLAYING,
		"Defeating the Guardian in endless mode does NOT end the run")
	assert_eq(arena.ascension_loop, 1, "Ascension loop incremented to 1")
	assert_gt(float(arena.run_essence_earned), float(run_essence_before),
		"Awakening grants essence to the run pool")
	assert_gt(arena.player.hp, arena.player.max_hp * 0.30, "Awakening heals the player")
	assert_false(arena.boss_spawned, "The next Guardian is scheduled, not left spawned")
	assert_approx(arena.boss_spawn_time, arena.run_elapsed + 270.0, 1.0,
		"Next Guardian is 270 s after the awakening")

	# The next loop must actually be able to spawn a boss again.
	var boss2 := arena.spawn_ancient_guardian_boss()
	assert_true(boss2 != null, "A second Guardian can spawn in the next loop")
	boss2.take_damage(boss2.max_hp * 1.5, 1.0)
	await tree.process_frame
	assert_eq(arena.ascension_loop, 2, "Second Guardian takes the loop to 2")
	assert_eq(App.state, App.State.PLAYING, "Run still continues after the second Guardian")

	# --- zen: no boss, no death, no dash cost --------------------------------------
	main._start_run("zen")
	await tree.process_frame
	assert_true(arena.is_zen(), "Zen run reports itself as zen")
	assert_eq(App.state, App.State.PLAYING, "Zen run is playing")

	# Time passes far beyond the boss timer and nothing hostile arrives.
	arena.run_elapsed = 600.0
	arena._process_spawning_and_waves(0.1)
	assert_true(arena.active_boss == null, "No Guardian appears in zen, ever")
	assert_true(arena.boss_spawned, "The boss flag starts set so the timer branch is inert")

	# Damage is reduced and can never kill.
	arena.player.hp = arena.player.max_hp
	arena.player.invulnerable_timer = 0.0
	arena.player.shield_ready = false
	arena.player.take_damage(arena.player.max_hp * 10.0, "shadow_slime")
	assert_false(arena.player.is_dead, "Zen damage cannot kill the player")
	assert_approx(arena.player.hp, arena.player.max_hp * 0.15, 0.5,
		"Zen damage floors HP at 15%")
	assert_eq(App.state, App.State.PLAYING, "Zen stays in PLAYING after a huge hit")

	# The low-HP vignette must stay off: it would be an alarm the mode can never honour.
	arena._update_game_feel(0.5)
	assert_approx(arena._vignette_alpha, 0.0, 0.02, "Zen shows no red low-HP vignette")

	# Dashing costs no mass in zen.
	arena.player.mutations.apply_mutation("dash")
	arena.player.mass = 40.0
	arena.player.dash_cooldown = 0.0
	arena.player.is_dashing = false
	var mass_before := arena.player.mass
	arena.player.trigger_dash()
	assert_approx(arena.player.mass, mass_before, 0.001, "Zen dash burns no mass")

	# ...while the same dash still burns mass in standard, so the rule is a mode rule
	# and not a change to dashing itself.
	main._start_run("standard")
	await tree.process_frame
	arena.player.mutations.apply_mutation("dash")
	arena.player.mass = 40.0
	arena.player.dash_cooldown = 0.0
	arena.player.is_dashing = false
	var std_before := arena.player.mass
	arena.player.trigger_dash()
	assert_lt(arena.player.mass, std_before, "Standard dash still burns mass")

	# --- zen walk ending -----------------------------------------------------------
	main._start_run("zen")
	await tree.process_frame
	arena.add_run_essence(50)
	var ess_pre_walk := SaveData.get_essence()
	arena.end_zen_walk()
	await tree.process_frame
	assert_eq(App.state, App.State.VICTORY, "Finishing a zen walk shows the result screen")
	assert_false(bool(App.last_run_summary.get("victory", true)),
		"A finished walk is not recorded as a victory")
	assert_eq(str(App.last_run_summary.get("outcome", "")), "walk", "Outcome is reported as a walk")
	assert_gt(float(SaveData.get_essence()), float(ess_pre_walk),
		"Finishing a walk commits everything collected")


func _test_moss_trail_and_caustics(tree: SceneTree, main: MainRoot) -> void:
	## Block 2 of the flow pass: the baked caustics tile and the bioluminescent moss
	## trail. Both are "invisible if broken" features — a missing sampler just leaves
	## the floor a little flatter and a missing ring buffer just leaves no glow — so
	## every number the shader depends on is asserted here rather than eyeballed.

	# --- the caustics tile ---------------------------------------------------------
	var caustic_tex := AssetRegistry.get_texture(ArenaController.FLOOR_CAUSTICS_PATH)
	assert_true(caustic_tex != null, "Caustics tile loads through AssetRegistry")
	if caustic_tex != null:
		var img := caustic_tex.get_image()
		assert_true(img != null and not img.is_empty(), "Caustics tile decodes to an image")
		if img != null and not img.is_empty():
			if img.is_compressed():
				img.decompress()
			var w := img.get_width()
			var h := img.get_height()
			assert_eq(w, h, "Caustics tile is square")
			assert_gte(float(w), 256.0, "Caustics tile is at least 256 px wide")
			# Sampled every 3rd texel: the whole image is 262k pixels and this suite
			# runs in the same frame budget as the boss fight.
			var min_a := 1.0
			var lum_sum := 0.0
			var lum_min := 1.0
			var lum_max := 0.0
			var lit := 0
			var n := 0
			for y in range(0, h, 3):
				for x in range(0, w, 3):
					var c := img.get_pixel(x, y)
					min_a = minf(min_a, c.a)
					var l := (c.r + c.g + c.b) / 3.0
					lum_sum += l
					lum_min = minf(lum_min, l)
					lum_max = maxf(lum_max, l)
					if l > 0.5:
						lit += 1
					n += 1
			var mean_l := lum_sum / float(n)
			var lit_frac := float(lit) / float(n)
			# The layer is ADDED by the shader, so a transparent tile would silently
			# darken the floor wherever the shader assumes it is sampling light.
			assert_eq(min_a, 1.0, "Caustics tile is fully opaque")
			assert_gt(mean_l, 0.15, "Caustics tile is a light field, not a black square")
			assert_lt(mean_l, 0.60, "Caustics tile is not a white square")
			assert_gt(lum_max - lum_min, 0.50, "Caustics tile carries real contrast")
			assert_gt(lit_frac, 0.10, "Caustics tile has filaments, not just cells")
			assert_lt(lit_frac, 0.80, "Caustics tile is a net, not a flood fill")
			# Seamless: the wrapped edge has to be no worse than a normal interior
			# step, otherwise the repeat prints a visible grid on the floor.
			var seam_h := 0.0
			var seam_v := 0.0
			for i in range(0, w, 2):
				seam_h += absf(img.get_pixel(0, i).r - img.get_pixel(w - 1, i).r)
				seam_v += absf(img.get_pixel(i, 0).r - img.get_pixel(i, h - 1).r)
			seam_h /= float(range(0, w, 2).size())
			seam_v /= float(range(0, h, 2).size())
			assert_lt(seam_h, 0.15, "Caustics tile wraps horizontally (seam %.3f)" % seam_h)
			assert_lt(seam_v, 0.15, "Caustics tile wraps vertically (seam %.3f)" % seam_v)

	# --- the material actually receives it -----------------------------------------
	var mat := ShaderMaterial.new()
	mat.shader = load("res://shaders/forest_canopy.gdshader") as Shader
	assert_true(ArenaController.apply_floor_texture(mat, 1.0), "Floor material accepts the art set")
	assert_true(mat.get_shader_parameter("floor_caustics") != null, "Caustics sampler is bound")
	assert_approx(float(mat.get_shader_parameter("floor_caustics_amount")),
		ArenaController.FLOOR_CAUSTICS_COLD, 0.0001, "Caustics start at the cold amount")
	assert_approx(float(mat.get_shader_parameter("floor_caustics_scale")),
		ArenaController.FLOOR_CAUSTICS_SCALE, 0.0001, "Caustics use the shipped repeat scale")

	# --- the moss trail ------------------------------------------------------------
	main._start_run("standard")
	await tree.process_frame
	var arena := main.arena
	var player := arena.player
	# One sample is expected, not zero: the first physics frame after a run starts
	# always writes the slime's spawn point, which is the anchor the rest of the path
	# is measured from. What must not survive is the previous run's path.
	assert_lte(float(arena.trail_point_count()), 1.0, "A new run starts with at most its first sample")
	assert_eq(arena._trail_pts.size(), ArenaController.TRAIL_COUNT, "Trail buffer holds 16 points")

	# Driven directly rather than through the input pipeline: the producer is what is
	# under test, and the frame rate of a headless run is not a clock.
	var seeded := arena.trail_point_count()
	var origin := player.global_position
	for i in range(6):
		player.global_position = origin + Vector2(26.0 * float(i + 1), 0.0)
		for _f in range(11):
			arena._update_trail(1.0 / 60.0)
	assert_eq(arena.trail_point_count(), seeded + 6, "Six samples of 0.16 s are live on the moss")

	var pts: Variant = arena.canopy_mat.get_shader_parameter("trail_points")
	var wts: Variant = arena.canopy_mat.get_shader_parameter("trail_weights")
	assert_true(pts is PackedVector2Array, "Trail points reach the shader as a packed vec2 array")
	assert_true(wts is PackedFloat32Array, "Trail weights reach the shader as a packed float array")
	if pts is PackedVector2Array:
		assert_eq((pts as PackedVector2Array).size(), ArenaController.TRAIL_COUNT,
			"Shader receives all 16 trail points")
	if wts is PackedFloat32Array:
		var weights := wts as PackedFloat32Array
		assert_eq(weights.size(), ArenaController.TRAIL_COUNT, "Shader receives all 16 weights")
		var head := arena.trail_head_index()
		assert_gt(weights[head], 0.90, "The newest trail sample is nearly full weight")
		# The oldest live sample is a second old at this point, so it must be dimmer
		# than the newest one and still visible. Found by scan: the ring wraps, so
		# "head + 1" is the next free slot, not the oldest occupied one.
		var dimmest := 1.0
		for v in weights:
			if v > 0.0:
				dimmest = minf(dimmest, v)
		assert_lt(dimmest, weights[head], "Older trail samples are dimmer")
		assert_gt(dimmest, 0.4, "A one-second-old sample is still visible")

	assert_approx(float(arena.canopy_mat.get_shader_parameter("trail_radius")),
		clampf(player.get_radius() * 1.15, 24.0, 74.0), 0.5, "Trail radius follows the body")
	assert_approx(float(arena.canopy_mat.get_shader_parameter("trail_strength")),
		ArenaController.TRAIL_STRENGTH, 0.0001, "Trail strength is pushed every frame")

	# Standing still must not stack samples on one spot: the moss should cool off.
	var before_stand := arena.trail_point_count()
	for _f in range(60):
		arena._update_trail(1.0 / 60.0)
	assert_eq(arena.trail_point_count(), before_stand, "Standing still adds no samples")
	for _f in range(170):
		arena._update_trail(1.0 / 60.0)
	# And it stays dark. Keying the first write off "the buffer is empty" made a
	# stationary slime re-light a spot every 2.5 s; this is the assertion that keeps
	# that from coming back.
	assert_eq(arena.trail_point_count(), 0, "The trail fades out and stays out in 2.5 s")
	for _f in range(60):
		arena._update_trail(1.0 / 60.0)
	assert_eq(arena.trail_point_count(), 0, "A stationary slime does not re-ignite the moss")

	# --- orb sparks ----------------------------------------------------------------
	var orb := CollectibleOrb.new()
	tree.root.add_child(orb)
	orb.setup(player.global_position + Vector2(120.0, 0.0), "spore", 0.85, 5.0)
	assert_eq(orb.spark_count(), 0, "A fresh orb sheds no sparks")
	orb.start_suction(player)
	for _f in range(30):
		orb._process(1.0 / 60.0)
	assert_gt(float(orb.spark_count()), 0.0, "A pulled orb sheds sparks")
	assert_lte(float(orb.spark_count()), float(CollectibleOrb.SPARK_MAX), "Sparks stay capped")
	orb.being_pulled_by = null
	for _f in range(30):
		orb._process(1.0 / 60.0)
	assert_eq(orb.spark_count(), 0, "Sparks expire after their life")
	orb.queue_free()
	await tree.process_frame

	main._return_to_main_menu()
