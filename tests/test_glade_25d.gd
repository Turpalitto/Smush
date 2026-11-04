extends "res://tests/TestSuiteBase.gd"
## PHASE 3 (plan 1.2) 2.5D lab: painted sprites only *display* the real 2D
## gameplay. Covers the sprite set, y-sorting by base line, the arena contract,
## absorption through MassSystem and the lab never touching the saved peak mass.
## Look and phone performance are judged from captures and device runs.


func _init() -> void:
	super("Glade25DSuite")


func run_async(tree: SceneTree) -> void:
	_test_assets()
	await _test_live_scene(tree)


func _test_assets() -> void:
	for prop_name: String in Glade25D.PROPS:
		var def: Array = Glade25D.PROPS[prop_name]
		var tex := load(Glade25D.ART + def[0]) as Texture2D
		assert_true(tex != null, "Sprite exists: " + prop_name)
		if tex != null:
			var img := tex.get_image()
			assert_eq(img.get_pixel(0, 0).a, 0.0, "Sprite corner is transparent (keyed): " + prop_name)
	assert_true(load(Glade25D.GROUND_PATH) is Texture2D, "Ground plate exists")


func _test_live_scene(tree: SceneTree) -> void:
	var lab := Glade25D.new()
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var player := lab.player
	assert_true(player is PlayerSlime, "The real PlayerSlime drives the 2.5D lab")
	assert_true(lab.hero != null and lab.hero.player == player, "The painted hero displays the real PlayerSlime")
	assert_false(player.visual.visible, "The 2D body is hidden: the painted hero only displays it")
	assert_true(lab.hero.get_parent() == lab._props_root, "The hero sorts with the props")
	assert_approx(lab.hero.position.y, player.global_position.y + player.get_radius() * Slime25D.BASE_DROP, 0.5, "Hero base line follows the gameplay body")
	assert_approx(player.peak_mass, MassSystem.MAX_MASS, 0.001, "The lab never raises the persistent peak-mass stat")
	assert_true(lab._props_root.y_sort_enabled, "Props are y-sorted")
	assert_true(player.get_parent() == lab._props_root, "The slime sorts with the props")
	assert_gt(lab._props_root.get_child_count(), 40, "The glade is densely dressed")

	var rect := lab.ground_rect()
	var limited := lab.constrain_player_position(Vector2(9000, -90000), 20.0, false)
	var bounds := lab.play_bounds()
	assert_approx(limited.x, bounds.end.x - 20.0, 0.01, "Slime stays inside the world (x)")
	assert_approx(limited.y, bounds.position.y + 20.0, 0.01, "Slime stays inside the world (y)")
	assert_true(rect.has_point(limited), "The play area lies on the painted ground")

	var before := player.mass
	var f: Dictionary = lab.food[0]
	var gain := 1.4 if f["crystal"] else 0.8
	var old_pos: Vector2 = f["pos"]
	lab._absorb(f)
	assert_approx(player.mass, MassSystem.clamp_mass(before + MassSystem.effective_gain(before, gain)), 0.0001, "Absorption uses MassSystem formulas")
	assert_true((f["pos"] as Vector2) != old_pos, "Absorbed food respawns elsewhere")

	var z_small := lab._zoom_for_mass()
	player.mass = MassSystem.clamp_mass(MassSystem.MAX_MASS)
	player._sync_mass_metrics()
	assert_gt(z_small, lab._zoom_for_mass(), "Camera pulls back as the slime grows")

	lab.queue_free()
	await tree.process_frame
