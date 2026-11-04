extends "res://tests/TestSuiteBase.gd"
## PHASE 2 render spike: the 3D layer must only *display* the 2D gameplay.
## Covers the plane<->world mapping, the screen round trip through the tilted
## camera (no false misses or hits), the visible footprint matching the
## gameplay radius, absorption through MassSystem, and mode switching. Visual
## quality and phone performance are judged from captures and device runs.


func _init() -> void:
	super("RenderSpikeSuite")


func run_async(tree: SceneTree) -> void:
	_test_mapping()
	await _test_live_scene(tree)


func _test_mapping() -> void:
	var p := Vector2(123.0, -456.0)
	var w := Render3DSpike.to_world(p)
	assert_approx(w.y, 0.0, 0.0001, "Gameplay plane maps to the ground (y = 0)")
	assert_approx(w.z, -4.56, 0.0001, "2D up maps to 3D forward (-Z)")
	assert_true(Render3DSpike.to_plane(w).distance_to(p) < 0.001, "Plane -> world -> plane round trip is exact")
	assert_gt(Render3DSpike.camera_distance(MassSystem.MAX_RADIUS), Render3DSpike.camera_distance(MassSystem.MIN_RADIUS), "Camera pulls back as the slime grows")
	assert_approx(Render3DSpike.percentile(PackedFloat32Array([1.0, 2.0, 3.0, 4.0, 5.0]), 0.5), 3.0, 0.0001, "Percentile helper is correct")


func _test_live_scene(tree: SceneTree) -> void:
	var spike := Render3DSpike.new()
	tree.root.add_child(spike)
	await tree.process_frame
	await tree.process_frame
	var player := spike.player
	assert_true(player is PlayerSlime, "The real PlayerSlime drives the spike")
	assert_false(spike._logic_root.visible, "The 2D layer is hidden: 3D only displays it")
	assert_approx(player.peak_mass, MassSystem.MAX_MASS, 0.001, "The lab never raises the persistent peak-mass stat")

	assert_true(spike.hero_from_model, "PHASE 3 hero comes from the Blender model (slime.glb)")
	var stump := spike._props_root.get_node_or_null("stump")
	assert_true(stump != null and stump.get_node_or_null("Stump") is MeshInstance3D, "Decor uses the Blender models, not primitives")
	assert_true(spike.get_node_or_null("Clover") is MultiMeshInstance3D, "Clover ground cover is one MultiMesh")
	var jelly: Node3D = spike._slime.get_node("Jelly")
	assert_approx(jelly.scale.x, player.get_radius() * Render3DSpike.PX_TO_M, 0.0005, "Visible footprint equals the gameplay radius")

	var worst := 0.0
	for p: Vector2 in [Vector2.ZERO, Vector2(150, 0), Vector2(-120, 90), Vector2(60, -180), Vector2(-40, 140)]:
		var screen := spike.plane_to_screen(player.global_position + p)
		worst = maxf(worst, spike.screen_to_plane(screen).distance_to(player.global_position + p))
	assert_true(worst < 1.0, "Screen <-> plane round trip under the tilted camera stays below 1 px (got %.3f)" % worst)

	var limited := spike.constrain_player_position(Vector2(5000, 0), 20.0, false)
	assert_approx(limited.length(), Render3DSpike.GLADE_RADIUS_PX - 20.0, 0.01, "Slime stays inside the glade")

	var before := player.mass
	var f: Dictionary = spike.food[0]
	var gain := 0.8 if int(f["kind"]) == Render3DSpike.FOOD_SPORE else 1.4
	var old_pos: Vector2 = f["pos"]
	spike.absorb_food(0)
	assert_approx(player.mass, MassSystem.clamp_mass(before + MassSystem.effective_gain(before, gain)), 0.0001, "Absorption uses MassSystem formulas")
	assert_eq(spike.food_echo.echoes.size(), 1, "Absorbed food leaves an inner echo")
	assert_true((spike.food[0]["pos"] as Vector2) != old_pos, "Eaten food respawns elsewhere")
	await tree.process_frame
	assert_approx(jelly.scale.x, player.get_radius() * Render3DSpike.PX_TO_M, 0.0005, "Footprint follows growth")

	spike.set_mode(Render3DSpike.Mode.FULL_3D)
	assert_true(spike._sun.shadow_enabled, "3D mode uses real-time shadows")
	spike.set_mode(Render3DSpike.Mode.HYBRID)
	assert_false(spike._sun.shadow_enabled, "Hybrid mode has no real-time shadows")
	spike.set_mode(Render3DSpike.Mode.PRERENDER)
	for _i in range(60):
		if spike.impostors_ready:
			break
		await tree.process_frame
	assert_true(spike.impostors_ready, "Prerender pass completes")
	assert_false(spike._props_root.visible, "Prerender mode hides the 3D props")
	assert_true(spike._impostor_root.visible, "Prerender mode shows the prop cards")

	var base_count := spike.prop_count()
	spike.set_density(3)
	assert_gt(float(spike.prop_count()), float(base_count) * 1.6, "Density x3 adds a much larger decor ring for the stress run")
	assert_approx(player.mass, MassSystem.clamp_mass(before + MassSystem.effective_gain(before, gain)), 0.0001, "Display settings never change mass")
	spike.free()
	await tree.process_frame
