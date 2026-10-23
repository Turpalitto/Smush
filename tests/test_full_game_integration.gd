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
	await _test_biomes_undergrowth_and_wonders(tree, main_inst)

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
	# Wonders are sprites in the chunk tree too, and they have no collision body on
	# purpose (a landmark must never be a wall in a flow game), so they are added to
	# the sprite side of the count and not to the body side.
	assert_eq(prop_sprites, arena.world.obstacles.size() + painted_plants + arena.world.wonder_count(),
		"Every prop, every painted plant and every wonder is a real sprite")
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
	#
	# The target is found by *position* against the obstacle list, not by matching
	# `base` against WorldGenerator.PROP_TINT. Since the macro-biomes landed, a prop's
	# base tint is PROP_TINT multiplied by the palette of the region it stands in, so
	# an equality test on the constant finds nothing — which is exactly how this test
	# failed the first time the biomes went in.
	var prop_positions := {}
	for ob in arena.world.obstacles:
		prop_positions[ob["pos"]] = true
	var fog_target: Dictionary = {}
	for f in arena.world._fogged:
		var candidate := f["node"] as Sprite2D
		if candidate != null and prop_positions.has(candidate.position):
			fog_target = f
			break
	assert_false(fog_target.is_empty(), "Props are registered for the distance haze")
	if not fog_target.is_empty():
		var fog_sp := fog_target["node"] as Sprite2D
		var fog_pos := fog_sp.position
		var fog_base: Color = fog_target["base"]
		arena.world._apply_fog(fog_pos + Vector2(WorldGenerator.FOG_END + 200.0, 0.0))
		assert_eq(fog_sp.modulate.a, 0.0, "A prop past the haze end is fully dissolved")
		arena.world._apply_fog(fog_pos)
		assert_eq(fog_sp.modulate.a, 1.0, "A prop at the player is fully opaque again")
		assert_eq(fog_sp.modulate, fog_base, "And it is back to its own tint")

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


func _test_biomes_undergrowth_and_wonders(tree: SceneTree, main: MainRoot) -> void:
	## Block 3 of the flow pass: four macro-biomes, undergrowth that bends away from
	## the slime and springs back, and three Wonders that wake once.
	##
	## Everything here is the kind of feature that fails silently. A biome field that
	## only ever produces one region still renders. A spring that never returns still
	## leans. A wonder that re-heals every time you walk past still looks fine in a
	## screenshot and quietly turns the run into a healing circuit. So the assertions
	## are on the numbers, not on "it looks right".

	await tree.process_frame
	main._start_run("standard", 424242)
	await tree.process_frame
	await tree.process_frame
	var arena: ArenaController = main.arena
	var player: PlayerSlime = arena.player
	var world: WorldGenerator = arena.world
	assert_true(world != null, "The world exists for the biome pass")
	if world == null:
		main._return_to_main_menu()
		return

	# --- the four landmarks are real art -------------------------------------------
	# Same rule as every other texture in the game: real, with alpha, and the right
	# size. A wonder that silently failed to key would be an invisible landmark that
	# still healed, which is worse than no landmark at all.
	for wonder_id in WorldGenerator.WONDER_KINDS:
		var tex := AssetRegistry.get_texture("res://resources/art/props/%s.png" % wonder_id)
		assert_true(tex != null, "Wonder art loads: %s" % wonder_id)
		if tex == null:
			continue
		var img := tex.get_image()
		assert_true(img != null and not img.is_empty(), "Wonder art decodes: %s" % wonder_id)
		if img == null or img.is_empty():
			continue
		if img.is_compressed():
			img.decompress()
		assert_eq(img.get_width(), 256, "Wonder art is 256 px wide: %s" % wonder_id)
		assert_eq(img.get_height(), 256, "Wonder art is square: %s" % wonder_id)
		# Alpha is sampled from the pixels, every second one on each axis: Image has no
		# per-channel histogram in 4.5, and a 128x128 sample of a 256x256 cut-out is
		# well inside the tolerance these thresholds use.
		var total := 0.0
		var opaque := 0.0
		var transparent := 0.0
		for ay in range(0, img.get_height(), 2):
			for ax in range(0, img.get_width(), 2):
				var a := img.get_pixel(ax, ay).a
				total += 1.0
				if a >= 0.78:
					opaque += 1.0
				elif a < 0.03:
					transparent += 1.0
		opaque /= total
		transparent /= total
		# The backdrop has to be gone and the silhouette has to survive the key.
		assert_gt(transparent, 0.25, "Wonder art has a real alpha cut-out: %s" % wonder_id)
		assert_gt(opaque, 0.10, "Wonder art keeps its body: %s" % wonder_id)
		assert_lt(opaque, 0.60, "Wonder art did not keep the backdrop: %s" % wonder_id)

	# --- the biome field ------------------------------------------------------------
	var btex := world.biome_texture()
	assert_true(btex != null, "The biome map exists")
	if btex != null:
		var bimg := btex.get_image()
		assert_true(bimg != null and not bimg.is_empty(), "The biome map decodes")
		if bimg != null and not bimg.is_empty():
			if bimg.is_compressed():
				bimg.decompress()
			var res := bimg.get_width()
			assert_eq(res, WorldGenerator.BIOME_MAP_RES, "Biome map is the size the CPU reads")
			assert_eq(bimg.get_height(), res, "Biome map is square")
			assert_eq(bimg.get_format(), Image.FORMAT_RGBA8,
				"Biome map is RGBA8, so the CPU and the shader read identical texels")

			# Weights: non-negative and summing to 1. If they do not sum to 1 the
			# shader's normalisation hides it, but the CPU-side blend would be wrong
			# and the props would drift away from the floor.
			var worst_sum := 0.0
			var negative := 0
			for y in range(res):
				for x in range(res):
					var c := bimg.get_pixel(x, y)
					var s := c.r + c.g + c.b + c.a
					worst_sum = maxf(worst_sum, absf(s - 1.0))
					if c.r < 0.0 or c.g < 0.0 or c.b < 0.0 or c.a < 0.0:
						negative += 1
			assert_eq(negative, 0, "No biome weight is negative")
			# 8-bit quantisation of four channels that sum to 1 costs at most 2/255.
			assert_lt(worst_sum, 0.012, "Biome weights sum to 1 (worst %.4f)" % worst_sum)

			# Low-frequency, not noise. The maximum texel-to-texel step is NOT the right
			# instrument here and the first version of this test used it: the contrast
			# ramp deliberately steepens each channel by 1/(0.68-0.32), so a legitimate
			# transition between two regions moves most of the weight range in two or
			# three texels. On screen that is a ramp over ~640 world pixels, which is
			# exactly the two-chunk transition the design asks for. What has to be true
			# is that the field is *smooth on average* and that its regions are large.
			var step_sum := 0.0
			var step_n := 0
			var dominant := [0, 0, 0, 0]
			var dom_map := PackedByteArray()
			dom_map.resize(res * res)
			for y in range(res):
				for x in range(res):
					var c := bimg.get_pixel(x, y)
					var vals := [c.r, c.g, c.b, c.a]
					var best := 0
					for i in range(1, 4):
						if vals[i] > vals[best]:
							best = i
					dom_map[y * res + x] = best
					dominant[best] += 1
					if x + 1 < res:
						var n := bimg.get_pixel(x + 1, y)
						step_sum += absf(c.r - n.r) + absf(c.g - n.g) \
							+ absf(c.b - n.b) + absf(c.a - n.a)
						step_n += 1
			var mean_step := step_sum / float(step_n)
			assert_lt(mean_step, 0.30, "The biome field is smooth on average (mean step %.3f)" % mean_step)

			# Regions, not speckle: a texel whose dominant biome differs from all four
			# of its neighbours is a pixel of a different region, which is what a noisy
			# field (or a broken hash) produces.
			var isolated := 0
			for y in range(res):
				for x in range(res):
					var here := dom_map[y * res + x]
					var alone := true
					if x > 0 and dom_map[y * res + x - 1] == here:
						alone = false
					if x + 1 < res and dom_map[y * res + x + 1] == here:
						alone = false
					if y > 0 and dom_map[(y - 1) * res + x] == here:
						alone = false
					if y + 1 < res and dom_map[(y + 1) * res + x] == here:
						alone = false
					if alone:
						isolated += 1
			assert_lt(float(isolated), float(res * res) * 0.01,
				"Biome regions are solid, not speckled (%d isolated texels)" % isolated)

			# ...and the regions are large: a row crosses a handful of regions, not
			# dozens. A field of pure noise would flip on roughly half of all steps.
			var flips := 0
			var steps := 0
			for y in range(res):
				for x in range(res - 1):
					steps += 1
					if dom_map[y * res + x] != dom_map[y * res + x + 1]:
						flips += 1
			var flips_per_row := float(flips) / float(res)
			assert_lt(flips_per_row, 12.0,
				"Biome regions are wide, not a checkerboard (%.1f flips per row)" % flips_per_row)
			assert_gt(flips_per_row, 0.5,
				"Biome regions actually change across the map (%.1f flips per row)" % flips_per_row)

			# All four regions have to actually exist. A field that never crosses its
			# contrast thresholds would ship one biome and call it four.
			for i in range(4):
				assert_gt(float(dominant[i]), float(res * res) * 0.02,
					"Biome %s owns real ground (%d of %d texels)"
					% [WorldGenerator.BIOME_NAMES[i], dominant[i], res * res])

			# Seamless: the wrap edge is adjacent ground, not a discontinuity.
			var seam := 0.0
			for i in range(res):
				var a := bimg.get_pixel(0, i)
				var b := bimg.get_pixel(res - 1, i)
				seam += absf(a.r - b.r) + absf(a.g - b.g) + absf(a.b - b.b) + absf(a.a - b.a)
			seam /= float(res)
			assert_lt(seam, 0.16, "The biome field wraps without a seam (%.4f)" % seam)

	# The CPU and the shader must be looking at the same map.
	assert_eq(world.biome_weights_at(Vector2.ZERO).size(), 4, "Weights are a 4-vector")
	var w_here := world.biome_weights_at(Vector2(1234.0, -567.0))
	var sum_here := w_here[0] + w_here[1] + w_here[2] + w_here[3]
	assert_approx(sum_here, 1.0, 0.02, "Weights sum to 1 at a sample position")
	# Dominance and the blended tint have to agree with the weights, or a region would
	# be announced as one biome and painted as another.
	var dom := world.dominant_biome(Vector2(1234.0, -567.0))
	var max_w := 0.0
	for i in range(4):
		max_w = maxf(max_w, w_here[i])
	assert_approx(w_here[dom], max_w, 0.0001, "The dominant biome is the heaviest weight")
	assert_eq(world.biome_name_at(Vector2(1234.0, -567.0)),
		WorldGenerator.BIOME_NAMES[dom], "The biome name follows the dominant weight")
	var tint := world.biome_tint_at(Vector2(1234.0, -567.0))
	var expect_r := 0.0
	var expect_g := 0.0
	var expect_b := 0.0
	for i in range(4):
		expect_r += WorldGenerator.BIOME_TINTS[i].r * w_here[i]
		expect_g += WorldGenerator.BIOME_TINTS[i].g * w_here[i]
		expect_b += WorldGenerator.BIOME_TINTS[i].b * w_here[i]
	assert_approx(tint.r, expect_r, 0.002, "The blended tint is the weighted palette (r)")
	assert_approx(tint.g, expect_g, 0.002, "The blended tint is the weighted palette (g)")
	assert_approx(tint.b, expect_b, 0.002, "The blended tint is the weighted palette (b)")

	# The palette must not step at a chunk boundary: that is the whole reason it is
	# sampled in world pixels instead of per chunk.
	var edge_a := world.biome_tint_at(Vector2(WorldGenerator.CHUNK_SIZE * 4.0 - 1.0, 200.0))
	var edge_b := world.biome_tint_at(Vector2(WorldGenerator.CHUNK_SIZE * 4.0 + 1.0, 200.0))
	assert_lt(absf(edge_a.r - edge_b.r) + absf(edge_a.g - edge_b.g) + absf(edge_a.b - edge_b.b),
		0.05, "The palette does not step across a chunk boundary")

	# The floor has to be reading the same map.
	if arena.canopy_mat != null:
		var bound: Variant = arena.canopy_mat.get_shader_parameter("biome_map")
		assert_true(bound is Texture2D, "The floor shader has the biome map bound")
		assert_approx(float(arena.canopy_mat.get_shader_parameter("biome_strength")), 1.0,
			0.0001, "The floor shader applies the biome palette")
		assert_approx(float(arena.canopy_mat.get_shader_parameter("biome_tile_px")),
			WorldGenerator.BIOME_TILE_PX, 0.5, "The floor shader tiles the map at the world scale")
		var code: String = arena.canopy_mat.shader.code
		assert_true(code.contains("biome_map"), "The floor shader samples the biome map")
		assert_true(code.contains("biome_c3"), "The floor shader blends all four biomes")

	# --- undergrowth: bend away, spring back ---------------------------------------
	assert_gt(float(world._swayers.size()), 0.0, "There is undergrowth to bend")
	if not world._swayers.is_empty():
		var swayer: Dictionary = world._swayers[0]
		var node := swayer["node"] as Sprite2D
		assert_true(node != null, "The swayer has a sprite")
		if node != null:
			var base_rot := float(swayer["base_rotation"])
			var sway_amp := float(swayer["amount"])
			# The slime standing 40 px to the *right* of the plant. Only the horizontal
			# part of the away vector may produce a lean, so this is the case that has
			# to bend.
			var rel := Vector2(40.0, 0.0)
			var peak := 0.0
			for _f in range(90):
				peak = world._step_bend(swayer, rel, rel.length_squared(), 1.0 / 60.0)
			assert_gt(peak, 0.02, "Undergrowth leans away from the slime")
			assert_gt(float(swayer["bend"]), 0.02, "The lean is stored, not just returned")
			# Lean direction: the plant is to the right of the slime, so the top has to
			# move further right, which is a positive rotation in Godot's y-down frame.
			assert_gt(float(swayer["bend"]), 0.0, "The lean points away, not toward")

			# A slime directly below the plant produces no lean at all: a rotation can
			# only move the tip sideways.
			var below := Vector2(0.0, 90.0)
			for _f in range(120):
				world._step_bend(swayer, below, below.length_squared(), 1.0 / 60.0)
			assert_lt(absf(float(swayer["bend"])), 0.02,
				"A slime directly below a plant does not tilt it sideways")

			# Spring return: with the slime gone the lean has to come back to zero. A
			# critically damped or non-returning version would keep the last angle.
			var far := Vector2(4000.0, 0.0)
			for _f in range(150):
				world._step_bend(swayer, far, far.length_squared(), 1.0 / 60.0)
			assert_lt(absf(float(swayer["bend"])), 0.004,
				"Undergrowth springs back to upright (%.4f rad)" % float(swayer["bend"]))
			assert_eq(float(swayer["bend"]), float(swayer["bend"]),
				"The spring never goes NaN")
			# And the rotation the draw code applies is the base plus the spring.
			assert_approx(node.rotation, base_rot + float(swayer["bend"]),
				2.0 * sway_amp + 0.02, "The sprite rotation carries the spring")

	# --- dust motes ----------------------------------------------------------------
	# 2-3 motes per brushed clump. Emitted by the spring, not by a timer, so a plant
	# that is never touched never sheds anything.
	#
	# The spring has to be *stepped* until it fires: one frame moves the lean by about
	# 0.002 rad, and the trigger is 0.10. The first version of this test called
	# _step_bend once and asserted motes appeared, which measured nothing but the
	# test's own impatience.
	var dust_swayer: Dictionary = {}
	for s: Dictionary in world._swayers:
		if (s["node"] as Sprite2D) != null:
			dust_swayer = s
			break
	if not dust_swayer.is_empty():
		dust_swayer["dust_cd"] = 0.0
		dust_swayer["bend"] = 0.0
		dust_swayer["bend_vel"] = 0.0
		var dust_before := world.dust_count()
		var near := Vector2(45.0, 0.0)
		var fired_after := 0
		for f in range(40):
			world._step_bend(dust_swayer, near, near.length_squared(), 1.0 / 60.0)
			if world.dust_count() > dust_before:
				fired_after = f + 1
				break
		var emitted := world.dust_count() - dust_before
		assert_gt(float(fired_after), 0.0, "A brushed clump sheds motes")
		assert_gte(float(emitted), 2.0, "A brushed clump sheds at least two motes")
		assert_lte(float(emitted), 3.0, "A brushed clump sheds at most three motes")
		# The cooldown is what stops a plant the slime is standing next to from
		# machine-gunning motes for the whole run.
		var again_before := world.dust_count()
		for _f in range(30):
			world._step_bend(dust_swayer, near, near.length_squared(), 1.0 / 60.0)
		assert_eq(world.dust_count(), again_before,
			"A second brush inside the cooldown sheds nothing")
		# And they expire rather than accumulating forever.
		world._update_dust(3.0, world._player_pos())
		assert_eq(world.dust_count(), 0, "Dust motes expire")

	# --- the wonder lattice ---------------------------------------------------------
	# Purity: the same cell twice is the same wonder, because the chunk streamer asks
	# for it from both _is_reserved and _build_chunk.
	var sample_cell := Vector2i(3, -2)
	var w_first := world._wonder_in_cell(sample_cell.x, sample_cell.y)
	var w_second := world._wonder_in_cell(sample_cell.x, sample_cell.y)
	assert_eq(w_first.is_empty(), w_second.is_empty(), "The wonder lattice is a pure function")
	if not w_first.is_empty():
		assert_eq(w_first["pos"], w_second["pos"], "A wonder does not move between calls")

	# Density and spacing over a wide window. Both are what the brief actually asks
	# for: at most one per 7-9 chunks.
	var found: Array[Dictionary] = []
	var cells_checked := 0
	for cy in range(-6, 7):
		for cx in range(-6, 7):
			cells_checked += 1
			var w := world._wonder_in_cell(cx, cy)
			if not w.is_empty():
				found.append(w)
	assert_gt(float(found.size()), 20.0,
		"The lattice places wonders across the world (%d in %d cells)"
		% [found.size(), cells_checked])
	var fill := float(found.size()) / float(cells_checked)
	assert_approx(fill, WorldGenerator.WONDER_CHANCE, 0.14,
		"The lattice fills cells at the configured rate (%.3f)" % fill)
	var min_pair := INF
	for i in range(found.size()):
		for j in range(i + 1, found.size()):
			min_pair = minf(min_pair, (found[i]["pos"] as Vector2).distance_to(found[j]["pos"]))
	# 9 chunks per cell minus two 10 % jitters = 7.2 chunks. This is the guarantee the
	# brief asks for, and it is a property of the lattice, not of a rejection loop.
	assert_gte(min_pair, 7.2 * WorldGenerator.CHUNK_SIZE - 1.0,
		"No two wonders are closer than 7.2 chunks (%.0f px)" % min_pair)
	# All three kinds are reachable.
	var kinds_seen := {}
	for w: Dictionary in found:
		kinds_seen[w["kind"]] = true
	assert_eq(kinds_seen.size(), WorldGenerator.WONDER_KINDS.size(),
		"All three wonder kinds appear in the world")

	# Nothing spawns inside the starting glade or on the shrine.
	for w: Dictionary in found:
		var wpos: Vector2 = w["pos"]
		assert_gt(wpos.length(), WorldGenerator.SAFE_SPAWN_RADIUS,
			"A wonder never stands in the starting glade")
		assert_gt(wpos.distance_to(WorldGenerator.SHRINE_POS),
			WorldGenerator.SHRINE_CLEAR_RADIUS, "A wonder never stands on the shrine")

	# The clearing: a prop may not be placed on a wonder.
	if not found.is_empty():
		var clear_test: Dictionary = found[0]
		var cpos: Vector2 = clear_test["pos"]
		assert_true(world._is_reserved(cpos, 30.0), "A wonder keeps a clearing around itself")
		assert_true(world._is_reserved(cpos + Vector2(120.0, 0.0), 30.0),
			"The clearing is wider than the sprite")
		assert_false(world._is_reserved(cpos + Vector2(400.0, 0.0), 20.0),
			"The clearing ends, so the forest is not empty around a wonder")

	# --- waking one ------------------------------------------------------------------
	# Pick the wonder nearest the origin, walk the player to it, and check every effect
	# of the wake: lit, seen, healed, chime, spores, and the wake ramp.
	var target: Dictionary = {}
	var target_d := INF
	for w: Dictionary in found:
		var d := (w["pos"] as Vector2).length()
		if d < target_d:
			target_d = d
			target = w
	assert_false(target.is_empty(), "There is a wonder to walk to")
	if not target.is_empty():
		var tpos: Vector2 = target["pos"]
		var tcell: Vector2i = target["cell"]
		assert_false(world.wonder_is_seen(tcell), "A wonder starts asleep")
		# Damage the slime first, otherwise a heal at full HP is unmeasurable.
		player.hp = player.max_hp * 0.40
		var hp_before := player.hp
		var dust_before_wake := world.dust_count()

		player.global_position = tpos + Vector2(0.0, 70.0)
		world.stream_around(player.global_position, true)
		world._check_wonders(player.global_position)
		await tree.process_frame

		assert_true(world.wonder_is_seen(tcell), "Walking up to a wonder wakes it")
		assert_gt(player.hp, hp_before, "A wonder heals the slime")
		assert_approx(player.hp - hp_before, player.max_hp * WorldGenerator.WONDER_HEAL_FRACTION,
			0.5, "The heal is the configured fraction of max HP")
		assert_gt(float(world.dust_count()), float(dust_before_wake),
			"A wonder releases a cloud of spores")
		assert_eq(Audio.last_played_event, "wonder_chime", "A wonder chimes a bell chord")

		# The sprite is in the chunk tree, and it is awake.
		assert_gt(float(world.wonder_count()), 0.0, "The wonder is streamed as a node")
		var live: Array[Dictionary] = world.wonder_state()
		var lit_one: Dictionary = {}
		for rec: Dictionary in live:
			if rec["cell"] == tcell:
				lit_one = rec
		assert_false(lit_one.is_empty(), "The live wonder is the one that woke")
		if not lit_one.is_empty():
			assert_true(bool(lit_one["lit"]), "The woken wonder is lit")
			# The ramp: dim at the moment of waking, full after WONDER_WAKE_SEC.
			assert_lt(float(lit_one["wake"]), 1.0, "The wake ramps instead of snapping")
			for _f in range(int(WorldGenerator.WONDER_WAKE_SEC * 60.0) + 20):
				world._advance_wonder_wakes(1.0 / 60.0)
			var settled := 0.0
			for rec2: Dictionary in world.wonder_state():
				if rec2["cell"] == tcell:
					settled = float(rec2["wake"])
			assert_approx(settled, 1.0, 0.001, "The wake completes in WONDER_WAKE_SEC")

		# Only once. Walking away and back must not re-heal, re-chime or re-spore.
		var hp_after := player.hp
		var dust_after := world.dust_count()
		var chime_before := Audio.last_played_event
		player.global_position = tpos + Vector2(600.0, 600.0)
		world._check_wonders(player.global_position)
		player.global_position = tpos + Vector2(0.0, 70.0)
		world._check_wonders(player.global_position)
		assert_eq(player.hp, hp_after, "A wonder does not heal twice")
		assert_eq(world.dust_count(), dust_after, "A wonder does not shed spores twice")
		assert_eq(Audio.last_played_event, chime_before,
			"A wonder does not chime twice")

		# Chunk streaming must not forget it: the seen-set is keyed by cell, not by node.
		world.stream_around(Vector2.ZERO, true)
		await tree.process_frame
		assert_true(world.wonder_is_seen(tcell), "A woken wonder stays woken after streaming out")
		var relit := 0
		for rec3: Dictionary in world.wonder_state():
			if rec3["cell"] == tcell and bool(rec3["lit"]):
				relit += 1
		assert_lte(float(relit), 1.0, "A re-streamed wonder is lit at most once")
		player.global_position = Vector2.ZERO

	# --- the generator stays a pure function of the chunk coordinate ------------------
	# The biome signature added a second rng draw per chunk; if the ordering slipped,
	# a chunk would look different on the second visit.
	var c_a := world._chunk_content(11, -7)
	var c_b := world._chunk_content(11, -7)
	assert_eq((c_a["props"] as Array).size(), (c_b["props"] as Array).size(),
		"Chunk prop count is stable across calls")
	assert_eq((c_a["decor"] as Array).size(), (c_b["decor"] as Array).size(),
		"Chunk decor count is stable across calls")
	var stable := true
	for i in range((c_a["props"] as Array).size()):
		if (c_a["props"][i]["pos"] as Vector2) != (c_b["props"][i]["pos"] as Vector2):
			stable = false
	assert_true(stable, "Chunk prop positions are stable across calls")

	main._return_to_main_menu()
