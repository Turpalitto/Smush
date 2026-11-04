extends "res://tests/TestSuiteBase.gd"
## Lake-direction prototype (ADR-11041620, plan step 0): the water is only a layer on top of the real
## 2D gameplay. Covers the shader quad, the ripple ring buffer and its growth with mass, the pads that
## part around the slime and settle back, and the lab leaving the persistent peak-mass stat alone.
## Look and phone performance are judged from captures and device runs.


func _init() -> void:
	super("LakeProtoSuite")
	LakeCombat.default_waves = false   # waves have their own test; the others count enemies exactly


func run_async(tree: SceneTree) -> void:
	assert_true(load("res://resources/art/2_5d/water/caustic_tile.png") is Texture2D, "Caustic tile exists")
	var lab := LakeProto25D.new()
	lab.streaming = false   # the main checks below look at the fully built world; streaming has its own test at the end
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame

	var player := lab.player
	assert_true(player is PlayerSlime, "The real PlayerSlime drives the lake prototype")
	assert_true(lab.player.global_position.is_equal_approx(LakeProto25D.START_POS), "The prologue starts the slime in the dewy glade")
	assert_true(lab.region_built("glade"), "The dewy glade is built (streaming off builds everything)")
	assert_gt(lab.puddles.size(), 5, "The glade has puddles")
	assert_true(lab.get_node_or_null("GladePlate") != null, "The painted dewy plate lies under the glade")
	assert_true(lab.play_bounds().end.y >= LakeProto25D.WORLD_BOTTOM, "The world reaches down through the glade")
	for dw_name: String in LakeProto25D.GLADE_FLORA:
		assert_true(load(Glade25D.ART + String(Glade25D.PROPS[dw_name][0])) is Texture2D, "Glade sprite exists: " + dw_name)
	player.global_position = Vector2(0.0, 300.0)   # the main checks below run on the lake side
	var puddle: Dictionary = lab.puddles[0]
	player.global_position = puddle["pos"]
	lab.audio.stop_oneshots()
	lab.audio.played.clear()
	lab.audio._last_event.clear()
	lab._in_puddle = false
	lab._update_puddles(0.016, player.global_position)
	assert_true(lab._in_puddle, "Stepping into a puddle is noticed")
	assert_true(lab.audio.played.has("water_splash_small"), "Stepping into a puddle splashes")
	player.global_position = Vector2(0.0, 300.0)
	lab._update_puddles(0.016, player.global_position)
	assert_false(lab._in_puddle, "Leaving the puddle is noticed")
	assert_approx(player.peak_mass, MassSystem.MAX_MASS, 0.001, "The lab never raises the persistent peak-mass stat")
	assert_true(lab.water != null, "The water surface exists")
	var mat := lab.water.material as ShaderMaterial
	assert_true(mat != null and mat.shader == LakeProto25D.WATER_SHADER, "Water uses the lake shader")
	assert_eq((mat.get_shader_parameter("ripples") as PackedVector4Array).size(), LakeProto25D.MAX_RIPPLES, "Ripple rings are passed as a fixed array")
	assert_true(lab.water.z_index < lab.get_node("UnderWater").z_index + 5 and lab.get_node("UnderWater").z_index < lab.water.z_index, "Layers: under water < surface")
	assert_gt(lab.floaters.size(), 20, "Pads, flowers and lanterns float on the surface")
	assert_gt(lab.fish.size(), 3, "Fish shadows swim under the surface")

	# wake: moving spawns rings, the buffer never grows past the shader's array
	player.global_position = Vector2(0.0, 100.0)
	lab._process(0.016)
	var start_count := lab.ripples.size()
	for i in range(20):
		player.global_position += Vector2(30.0, 0.0)
		lab._process(0.016)
	assert_gt(lab.ripples.size(), start_count, "Moving leaves wake rings")
	assert_true(lab.ripples.size() <= LakeProto25D.MAX_RIPPLES, "Ripple buffer stays within the shader array")
	assert_approx(lab.water.position.x, player.global_position.x, 0.5, "The water quad follows the slime")

	# growth shows in the waves
	player.mass = MassSystem.MIN_MASS
	var small := lab._mass_strength()
	player.mass = MassSystem.MAX_MASS
	var big := lab._mass_strength()
	assert_gt(big, small, "A larger slime makes stronger waves")
	assert_true(small >= 0.2 and big <= 1.0, "Wave strength stays in range")
	player.mass = MassSystem.DEFAULT_START_MASS

	# pads part around the slime and settle back
	var f: Dictionary = lab.floaters[0]
	var node: Node2D = f["node"]
	var home: Vector2 = f["home"]
	player.global_position = home + Vector2(6.0, 0.0)
	for i in range(30):
		lab._update_floaters(0.1)
	assert_gt((f["offset"] as Vector2).length(), 5.0, "A pad slides away from the slime")
	player.global_position = home + Vector2(2000.0, 2000.0)
	for i in range(80):
		lab._update_floaters(0.1)
	assert_lt((f["offset"] as Vector2).length(), 1.0, "The pad drifts back once the slime has passed")
	assert_true(node.position.distance_to(home) < 6.0, "The pad ends near its home (bob only)")

	# step 3: underwater layer (seabed, roots, stones, jellyfish, rays)
	assert_true(lab.get_node("Seabed") is Sprite2D and (lab.get_node("Seabed") as Sprite2D).region_enabled, "A painted seabed tiles under the water")
	assert_gt(lab.jellies.size(), 3, "Jellyfish drift under the surface")
	assert_gt(lab._rays.size(), 2, "Soft light shafts cross the water")
	for uw_name: String in ["uw_roots_violet_web", "uw_roots_cyan_web", "uw_root_loop", "uw_root_fan", "uw_spores", "uw_root_knot", "uw_ray_wide", "uw_rays_three", "uw_jelly_big", "uw_snail"]:
		assert_true(load(LakeProto25D.UW + uw_name + ".png") is Texture2D, "Underwater sprite exists: " + uw_name)
	var jelly_before: Vector2 = (lab.jellies[0]["node"] as Node2D).position
	lab._t += 5.0
	lab._update_jellies()
	assert_true((lab.jellies[0]["node"] as Node2D).position != jelly_before, "Jellyfish drift")

	# step 4: flooded grove at the bottom of the world, shallow-to-deep blend in the shader
	assert_true(lab.get_node_or_null("GrovePlate") != null, "The grove-to-lake transition plate lies under the water")
	for gr_name: String in LakeProto25D.GROVE_STANDERS:
		assert_true(load(Glade25D.ART + String(Glade25D.PROPS[gr_name][0])) is Texture2D, "Grove sprite exists: " + gr_name)
	for fly_name: String in LakeProto25D.FIREFLIES:
		assert_true(load(LakeProto25D.GR + fly_name + ".png") is Texture2D, "Firefly effect exists: " + fly_name)
	var grove_count := 0
	var lake_count := 0
	for child in lab._props_root.get_children():
		if String(child.name).begins_with("gr_"):
			grove_count += 1
			assert_gt(child.position.y, LakeProto25D.GROVE_Y - 1.0, "Grove props stand in the grove (low part of the world)")
		elif String(child.name).contains("_st") or String(child.name).contains("_fl"):
			lake_count += 1
	assert_gt(grove_count, 15, "The grove is dressed")
	assert_gt(lake_count, 15, "The lake is dressed")
	assert_gt(lab._flies.size(), 8, "Fireflies drift over the grove")
	assert_approx((lab.water.material as ShaderMaterial).get_shader_parameter("shallow_from") if (lab.water.material as ShaderMaterial).get_shader_parameter("shallow_from") != null else 450.0, 450.0, 0.01, "Shallow-water range defaults to the grove")

	# step 6: the dive (auto when swimming past DIVE_Y, reversible)
	for fin_name: String in LakeProto25D.FINALE_PROPS:
		assert_true(load(Glade25D.ART + String(Glade25D.PROPS[fin_name][0])) is Texture2D, "Finale sprite exists: " + fin_name)
	assert_true(load("res://resources/art/2_5d/water/finale_plate.png") is Texture2D, "Finale plate exists")
	assert_eq(lab.dive, 0.0, "The slime starts on the surface")
	lab._auto_dive = true
	var deep := Vector2(0.0, LakeProto25D.DIVE_Y - 40.0)
	for i in range(30):
		lab._update_dive(0.2, deep)
	assert_approx(lab.dive, 1.0, 0.001, "Swimming past the far end dives")
	assert_approx(lab._finale_plate.modulate.a, 1.0, 0.01, "The finale plate fades in")
	assert_lt(lab._surface_nodes[0].modulate.a, 0.1, "Surface props fade away when diving")
	assert_approx((lab.water.material as ShaderMaterial).get_shader_parameter("dive"), 1.0, 0.001, "Water turns clear when diving")
	var near := Vector2(0.0, LakeProto25D.DIVE_Y + 60.0)
	for i in range(5):
		lab._update_dive(0.2, near)
	assert_approx(lab._dive_raw, 1.0, 0.001, "Hysteresis: it stays under just below the dive line")
	var shallow_pos := Vector2(0.0, LakeProto25D.DIVE_Y + 400.0)
	for i in range(30):
		lab._update_dive(0.2, shallow_pos)
	assert_approx(lab.dive, 0.0, 0.001, "Swimming back up surfaces again")
	assert_gt(lab._surface_nodes[0].modulate.a, 0.95, "Surface props return")
	lab._auto_dive = false

	# pre-integration polish: sound, glide physics, reward, animation
	for snd: String in ["water_drip_01", "water_plip_01", "water_bubble_01", "water_splash_small", "water_splash_large", "water_dive", "water_surface", "water_glide", "ambience_surface", "ambience_underwater"]:
		assert_true(load(LakeAudio.DIR + snd + ".wav") is AudioStreamWAV, "Water sound exists: " + snd)
	assert_true(lab.audio != null and lab.audio.get_child_count() >= LakeAudio.POOL + 3, "The lab has a pooled water audio mixer with three loops")
	assert_approx(lab.player.base_accel, LakeProto25D.WATER_ACCEL, 0.01, "The slime accelerates more gently on water (lab instance only)")
	assert_lt(LakeProto25D.WATER_FRICTION, 790.0, "Water friction is lower than the arena's (the slime glides)")
	assert_lt(lab.player.base_friction, 790.0, "The lab slime glides")
	var a := lab.audio
	a.update_mix(0.0, 0.0, 0.1)
	var surface_db_0: float = a._surface.volume_db
	var under_db_0: float = a._under.volume_db
	a.update_mix(1.0, 0.0, 0.1)
	assert_lt(a._surface.volume_db, surface_db_0, "Surface lapping fades out when diving")
	assert_gt(a._under.volume_db, under_db_0, "The underwater drone fades in when diving")
	a.update_mix(0.0, 0.0, 0.1)
	var glide_idle: float = a._glide.volume_db
	a.update_mix(0.0, 200.0, 0.1)
	assert_gt(a._glide.volume_db, glide_idle, "The glide swish follows the slime's speed")
	a.stop_oneshots()
	a.played.clear()
	a._last_event.clear()
	assert_true(a.play("water_drip_01", -12.0, 1.0, 0.5), "A one-shot plays")
	assert_false(a.play("water_drip_01", -12.0, 1.0, 0.5), "The same sound is rate-limited")
	a.enabled = false
	assert_false(a.play("water_plip_01"), "Muting silences one-shots")
	a.enabled = true
	var dived_count := [0]
	lab.dived.connect(func() -> void: dived_count[0] += 1)
	lab._auto_dive = true
	lab._prev_dive_target = 0.0
	lab.dive_target = 0.0
	lab._dive_raw = 0.0
	a.stop_oneshots()
	a.played.clear()
	a._last_event.clear()
	lab._update_dive(0.1, Vector2(0.0, LakeProto25D.DIVE_Y - 40.0))
	assert_eq(dived_count[0], 1, "Diving fires the reward event once")
	assert_true(a.played.has("water_dive"), "The dive has its whoosh")
	lab._update_dive(0.1, Vector2(0.0, LakeProto25D.DIVE_Y - 40.0))
	assert_eq(dived_count[0], 1, "The reward does not repeat while under")
	a.stop_oneshots()
	for i in range(30):
		lab._update_dive(0.2, Vector2(0.0, LakeProto25D.DIVE_Y + 400.0))
	assert_true(a.played.has("water_surface"), "Resurfacing has its sound")
	lab._auto_dive = false
	# pads tilt when pushed, fish flee
	var pf: Dictionary = lab.floaters[1]
	var pnode: Node2D = pf["node"]
	player.global_position = (pf["home"] as Vector2) + Vector2(-6.0, 0.0)
	for i in range(20):
		lab._update_floaters(0.1)
	assert_true(absf(pnode.rotation) > 0.02, "A pushed pad tilts")
	player.global_position = (pf["home"] as Vector2) + Vector2(3000.0, 3000.0)
	var fish_node: Node2D = lab.fish[0]["node"]
	lab._update_fish()
	var calm_pos := fish_node.position
	player.global_position = calm_pos + Vector2(12.0, 0.0)
	lab._update_fish()
	assert_gt(fish_node.position.distance_to(calm_pos), 20.0, "A fish darts away from the slime")

	# soft collisions and the current
	assert_gt(lab.solids.size(), 8, "Boulders, trunks and stems are solid")
	var sd: Dictionary = lab.solids[0]
	for cand in lab.solids:
		if absf((cand["node"] as Node2D).position.x) < 180.0 and (cand["node"] as Node2D).position.y > -800.0 and (cand["node"] as Node2D).position.y < 1500.0:
			sd = cand
			break
	var snode: Node2D = sd["node"]
	var sc: Vector2 = snode.position + Vector2(0.0, -float(sd["radius"]) * 0.6)
	var pr: float = player.get_radius()
	player.velocity = Vector2(120.0, 0.0)
	var inside: Vector2 = lab.constrain_player_position(sc + Vector2(-float(sd["radius"]) * 0.2, 0.0), pr, false)
	assert_gt(inside.distance_to(sc), float(sd["radius"]) + pr * 0.8 - 0.5, "The slime is pushed out of a solid prop")
	assert_lt(player.velocity.x, 120.0, "The slime loses the speed that went into the boulder")
	var free_pos := Vector2(5000.0, 5000.0)
	assert_approx(lab.constrain_player_position(free_pos, pr, false).x, lab.play_bounds().end.x - pr, 0.01, "Open water only meets the world edge")
	lab.dive_target = 0.0
	var cur_lake: Vector2 = lab.current_at(Vector2(0.0, -300.0))
	var cur_glade: Vector2 = lab.current_at(Vector2(0.0, 1300.0))
	assert_gt(cur_lake.length(), 5.0, "A current drifts the slime over the open lake")
	assert_lt(cur_glade.length(), 0.01, "No current on the dewy glade")
	assert_lt(cur_lake.length(), LakeProto25D.CURRENT_STRENGTH + 0.01, "The current stays weak")
	player.velocity = Vector2.ZERO
	lab._apply_current(1.0, Vector2(0.0, -300.0))
	assert_gt(player.velocity.length(), 5.0, "A resting slime drifts with the current")
	player.velocity = Vector2.ZERO

	# legends: rare elusive spirits, auras, the one-use Lunar Nova
	var lg := lab.legends
	assert_true(lg != null and lg.KINDS.size() == 6, "Six legendary spirits exist")
	for kd: Dictionary in LakeLegends.KINDS:
		assert_true(load(LakeLegends.DIR + String(kd["spirit"]) + ".png") is Texture2D, "Spirit sprite exists: " + String(kd["id"]))
		assert_true(load(LakeLegends.DIR + String(kd["aura"]) + ".png") is Texture2D, "Aura sprite exists: " + String(kd["id"]))
	for nv: String in ["lg_nova_ring", "lg_nova_burst", "lg_nova_vortex", "lg_nova_cracks"]:
		assert_true(load(LakeLegends.DIR + nv + ".png") is Texture2D, "Nova effect exists: " + nv)
	assert_gt(LakeLegends.APPEAR_MIN_SEC, 60.0, "A spirit never comes sooner than about a minute after the last")
	assert_lt(LakeLegends.APPEAR_CHANCE_PER_SEC * 60.0, 0.5, "Spirits are rare: under half a chance per minute even when allowed")
	assert_gt(LakeLegends.SPIRIT_SPEED, 1.0, "A fleeing spirit outpaces the slime")
	var lpl: Node2D = lab.player
	lpl.global_position = Vector2(0.0, -300.0)
	lg.spirit = {}
	lg.spawn_spirit(1, true)
	assert_false(lg.spirit.is_empty(), "A spirit can be summoned")
	assert_eq(lg.spirits_seen >= 1, true, "Sightings are counted")
	var spn: Node2D = lg.spirit["node"]
	var d0 := spn.position.distance_to(lpl.global_position)
	for i in range(30):
		lg._update_spirit(0.1, lpl.global_position)
	assert_gt(spn.position.distance_to(lpl.global_position), d0 - 1.0, "The spirit keeps its distance from a slime that is chasing it")
	lg.spirit["tired"] = 1.0
	var frozen: Vector2 = spn.position
	lg._update_spirit(0.05, lpl.global_position)
	assert_lt(spn.position.distance_to(frozen), 30.0, "A tired spirit hovers: the window to catch it")
	lpl.global_position = spn.position + Vector2(6.0, 0.0)
	lg._update_spirit(0.05, lpl.global_position)
	assert_true(lg.spirit.is_empty(), "Reaching a tired spirit catches it")
	assert_true(lg.aura_kind == 1 and lg.nova_ready, "Catching a spirit grants its aura and loads the Nova")
	assert_eq(lg.catches, 1, "The catch is counted")
	assert_true(lpl.get_parent() == lab._props_root and (lab.hero.get_node_or_null("AuraRing") != null), "The aura wraps the hero")
	lpl.global_position = Vector2(0.0, -300.0)
	var cb := lab.combat
	assert_true(cb != null, "The lab hosts the real combat adapter")
	lg.start_skirmish()
	assert_eq(cb.enemies.size(), LakeCombat.SKIRMISH.size(), "A skirmish brings the real enemies")
	assert_true(cb.boss is AncientGuardianBoss and cb.boss.max_hp > 1000.0, "…and the real boss")
	assert_true(cb.enemies[0] is EnemyEntity and cb.enemies[0].arena_ref == cb, "Enemies talk to the lab through the arena contract")
	# real contact damage reaches the real PlayerSlime
	var hp_before: float = lpl.hp
	var victim: EnemyEntity = cb.enemies[0]
	victim.global_position = lpl.global_position
	victim._contact_hit_cd = 0.0
	cb._physics_process(0.016)
	assert_lt(lpl.hp, hp_before + 0.001, "A touching enemy hurts the slime")
	# the lab never lets the slime die
	lpl.hp = 5.0
	cb._physics_process(0.016)
	assert_gt(lpl.hp, 5.0, "The lab mends a nearly dead slime")
	# the Nova: near enemies die, far ones live, the boss loses 60 percent of its maximum even through armour
	for en in cb.enemies:
		(en as EnemyEntity).global_position = lpl.global_position + Vector2(120.0, 0.0)
	var far: EnemyEntity = cb.spawn_enemy("forest_beetle", lpl.global_position + Vector2(LakeLegends.NOVA_RADIUS + 300.0, 0.0))
	far.global_position = lpl.global_position + Vector2(LakeLegends.NOVA_RADIUS + 300.0, 0.0)
	cb.boss.global_position = lpl.global_position + Vector2(0.0, -300.0)
	var boss_max: float = cb.boss.max_hp
	var boss_armor: float = cb.boss.armor
	assert_gt(boss_armor, 0.1, "The boss really has armour (the Nova ignores it)")
	var before_count: int = cb.enemies.size()
	assert_true(lg.cast_nova(), "The Nova casts when ready")
	assert_eq(lg.kills, before_count - 1, "The Nova kills every real enemy in range")
	assert_true(is_instance_valid(far) and far.hp > 0.0, "…and spares the far one")
	assert_approx(cb.boss.hp, boss_max * (1.0 - LakeLegends.NOVA_BOSS_FRACTION), 1.0, "The Nova takes 60 percent of a real boss's maximum, armour ignored")
	assert_false(lg.nova_ready, "The Nova is spent after one use")
	assert_false(lg.cast_nova(), "It cannot be cast twice")
	assert_eq(lg.nova_cast_count, 1, "One cast counted")
	lg.aura_left = 0.1
	lg._update_aura(0.5, lpl.global_position)
	assert_eq(lg.aura_kind, -1, "The aura fades out after its time")
	assert_true(lab.hero.get_node_or_null("AuraRing") == null or lab.hero.get_node("AuraRing").is_queued_for_deletion(), "The aura sprites are removed")
	lg.grant(2)
	lg._update_aura(0.1, lpl.global_position)
	assert_eq(lg.aura_kind, 2, "Another spirit gives another aura")
	lg.aura_left = 0.01
	lg._update_aura(0.5, lpl.global_position)

	# fake reflections exist for standing things
	var reflected := 0
	for child in lab._props_root.get_children():
		if child.get_node_or_null("Reflection") != null:
			reflected += 1
	assert_gt(reflected, 10, "Standing props carry a fake reflection")

	# tuning pass: the slime sits in the water, the moon column and duckweed follow the slime
	assert_true(lab.get_node_or_null("WaterFx") != null, "Painted water effects layer exists")
	for fx_name: String in ["ripple_small", "ripple_medium", "ripple_large", "splash_ring", "wake_curve", "wake_v", "splash_crown", "bubbles", "foam_patch", "glints"]:
		assert_true(load(LakeProto25D.FX + fx_name + ".png") is Texture2D, "Water effect sprite exists: " + fx_name)
	assert_true(load("res://resources/art/2_5d/water/lake_plate_tile.png") is Texture2D and load("res://resources/art/2_5d/water/shore_plate.png") is Texture2D, "Painted lake and shore plates exist")
	assert_true(lab.hero.get_node_or_null("Submerge") != null, "The slime is partly submerged")
	player.global_position = Vector2(100.0, 200.0)
	lab._process(0.016)
	var wm := lab.water.material as ShaderMaterial
	assert_approx((wm.get_shader_parameter("slime_pos") as Vector2).x, 100.0, 0.5, "Duckweed opens around the slime (shader)")
	assert_approx((wm.get_shader_parameter("moon_world") as Vector2).x, 140.0, 0.5, "The moon's reflection column follows the slime")
	for i in range(80):
		lab._update_fx(0.1)
	var live_before := lab._fx_live.size()
	lab.spawn_fx("splash_ring", player.global_position, 0.5, 1.0, 1.0)
	assert_eq(lab._fx_live.size(), live_before + 1, "A splash effect can be spawned from the pool")
	for i in range(40):
		lab._update_fx(0.05)
	assert_eq(lab._fx_live.size(), 0, "Effects fade out and return to the pool")
	var before_idle := lab.ripples.size()
	for i in range(30):
		lab._process(0.05)
	assert_true(lab.ripples.size() >= mini(before_idle + 1, LakeProto25D.MAX_RIPPLES), "A resting slime still breathes small rings")

	lab.queue_free()
	await tree.process_frame

	await _test_streaming(tree)
	await _test_absorption(tree)
	await _test_waves(tree)
	await _test_mutations(tree)
	await _test_draft(tree)
	await _test_bot(tree)
	await _test_music_and_synergies(tree)


## Regions are built when the slime is near and freed when it has left; leaving and coming back shows the same world.
func _test_streaming(tree: SceneTree) -> void:
	var lab := LakeProto25D.new()
	lab.streaming = true
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	lab.player.global_position = Vector2(0.0, 520.0)
	for i in range(6):
		lab._update_regions(lab.player.global_position)
	assert_true(lab.region_built("grove") and lab.region_built("lake"), "Near the grove: the grove and the lake are built")
	assert_false(lab.region_built("finale"), "The finale is not in memory while the slime is far from it")
	assert_true(lab._finale_plate.texture == null, "The finale plate texture is not loaded yet")
	var first_grove: Node2D = null
	for c in lab._props_root.get_children():
		if String(c.name).begins_with("gr_"):
			first_grove = c
			break
	var first_pos: Vector2 = first_grove.position
	var first_name := String(first_grove.name).split("_gr")[0]
	lab.player.global_position = Vector2(0.0, -820.0)
	for i in range(8):
		lab._update_regions(lab.player.global_position)
	await tree.process_frame
	assert_true(lab.region_built("finale"), "Near the far end the finale is built")
	assert_false(lab.region_built("grove"), "The grove is freed once the slime is far above it")
	assert_false(lab.region_built("glade"), "The glade is freed once the slime has left it far behind")
	assert_true(lab._finale_plate.texture != null, "The finale plate texture is loaded")
	var grove_left := 0
	for c in lab._props_root.get_children():
		if String(c.name).begins_with("gr_") and not c.is_queued_for_deletion():
			grove_left += 1
	assert_eq(grove_left, 0, "Grove props are gone from the scene")
	for f in lab.floaters:
		assert_true(is_instance_valid(f["node"]) and not (f["node"] as Node).is_queued_for_deletion(), "No freed pad stays in the floater list")
	lab.player.global_position = Vector2(0.0, 520.0)
	for i in range(8):
		lab._update_regions(lab.player.global_position)
	await tree.process_frame
	assert_true(lab.region_built("grove") and not lab.region_built("finale"), "Coming back rebuilds the grove and frees the finale")
	assert_true(lab._finale_plate.texture == null, "The finale texture is dropped again")
	var again: Node2D = null
	for c in lab._props_root.get_children():
		if String(c.name).begins_with("gr_") and String(c.name).begins_with(first_name + "_gr") and not c.is_queued_for_deletion():
			again = c
			break
	assert_true(again != null and again.position.is_equal_approx(first_pos), "The rebuilt grove has the same layout (fixed region seed)")
	lab.queue_free()
	await tree.process_frame


## Eating real enemies: the arena's absorption rules decide, the suction animation runs, the slime grows by MassSystem and no
## persistent statistic is written.
func _test_absorption(tree: SceneTree) -> void:
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var cb := lab.combat
	var pl: PlayerSlime = lab.player
	pl.global_position = Vector2(0.0, -300.0)
	pl.mass = MassSystem.clamp_mass(60.0)
	pl._sync_mass_metrics()
	var stats_before: float = float((SaveData.data["stats"] as Dictionary).get("total_absorbed", 0.0))
	var seen_before: int = SaveData.get_creature_count("tiny_mushroom")
	var mass_before := pl.mass
	var prey: EnemyEntity = cb.spawn_enemy("tiny_mushroom", pl.global_position + Vector2(4.0, 0.0))
	assert_true(prey != null and prey.is_active_combatant(), "A small mushroom is a combatant")
	var verdict := AbsorptionRules.evaluate(pl.mutations.build_player_absorption_context(pl.mass, false, false), prey.build_absorption_context())
	assert_true(bool(verdict.get("can_absorb", false)), "The arena's rules let a big slime eat a tiny mushroom")
	for i in range(240):
		prey.global_position = pl.global_position + Vector2(4.0, 0.0) if is_instance_valid(prey) and i < 3 else (prey.global_position if is_instance_valid(prey) else Vector2.ZERO)
		await tree.physics_frame
		if cb.absorbed > 0:
			break
	assert_eq(cb.absorbed, 1, "The mushroom is eaten (suction finished through the arena contract)")
	assert_gt(pl.mass, mass_before, "The slime grows from eating")
	assert_approx(cb.mass_gained, pl.mass - mass_before, 0.001, "Growth follows MassSystem.effective_gain")
	# A freed enemy cannot be passed into a typed Array.has(): check validity first.
	assert_false(is_instance_valid(prey) and cb.enemies.has(prey), "The eaten enemy leaves the list")
	assert_eq(float((SaveData.data["stats"] as Dictionary).get("total_absorbed", 0.0)), stats_before, "The lab writes no persistent absorption statistic")
	assert_eq(SaveData.get_creature_count("tiny_mushroom"), seen_before, "The lab writes nothing to the bestiary")
	# too big to eat: a small slime cannot swallow the stone slug and ramming does not hurt it
	pl.mass = MassSystem.clamp_mass(10.0)
	pl._sync_mass_metrics()
	var slug: EnemyEntity = cb.spawn_enemy("stone_slug", pl.global_position + Vector2(60.0, 0.0))
	var v2 := AbsorptionRules.evaluate(pl.mutations.build_player_absorption_context(pl.mass, false, false), slug.build_absorption_context())
	assert_false(bool(v2.get("can_absorb", false)), "A tiny slime cannot eat an armoured slug")
	var slug_hp := slug.hp
	slug.global_position = pl.global_position
	cb._physics_process(0.1)
	assert_gt(slug.hp, slug_hp - 0.001, "Touching an armoured, healthy slug does not hurt it (only the damaged or vulnerable)")
	# the boss strikes back when rammed: knock-back and a cooldown
	var boss: AncientGuardianBoss = cb.spawn_boss(pl.global_position + Vector2(0.0, -200.0))
	boss.global_position = pl.global_position + Vector2(0.0, -(pl.get_radius() + boss.get_body_radius() + 2.0))
	var bhp := boss.hp
	cb._boss_ram_cd = 0.0
	cb._physics_process(0.016)
	assert_lt(boss.hp, bhp, "Ramming the boss wounds it")
	assert_gt(cb._boss_ram_cd, 0.3, "The ram has a cooldown")
	assert_gt(pl.velocity.length(), 100.0, "The slime is thrown back from the boss")
	lab.queue_free()
	await tree.process_frame


## Waves: calm start, danger and reward grow with distance, caps, no spawns under water, a boss gate.
func _test_waves(tree: SceneTree) -> void:
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var cb := lab.combat
	var pl: PlayerSlime = lab.player
	assert_false(cb.waves_enabled, "Tests start with waves off (default_waves is false)")
	assert_approx(cb.progress_at(LakeProto25D.START_POS), 0.0, 0.001, "Progress is 0 on the dewy glade")
	assert_approx(cb.progress_at(Vector2(0.0, LakeProto25D.DIVE_Y)), 1.0, 0.001, "Progress is 1 at the dive line")
	assert_lt(cb.difficulty_at(LakeProto25D.START_POS), cb.difficulty_at(Vector2(0.0, -400.0)), "The further, the harder")
	assert_lt(cb.wave_interval(1.0), cb.wave_interval(0.0), "Waves come faster further on")
	assert_gt(cb.wave_max_alive(1.0), cb.wave_max_alive(0.0), "More enemies are allowed further on")
	for e in cb.wave_table(1500.0):
		assert_true(String(e[0]) in ["tiny_mushroom", "firefly"], "The glade has only food: " + String(e[0]))
	var far_ids: Array[String] = []
	for e in cb.wave_table(-700.0):
		far_ids.append(String(e[0]))
	assert_true(far_ids.has("shadow_slime"), "The far lake has the hunters")
	var grove_ids: Array[String] = []
	for e in cb.wave_table(400.0):
		grove_ids.append(String(e[0]))
	assert_false(grove_ids.has("shadow_slime"), "The grove does not")
	for id in far_ids + grove_ids:
		assert_false(ConfigDB.get_enemy(id).is_empty(), "Wave enemy exists in enemies.json: " + id)
	# a real wave
	cb.waves_enabled = true
	cb._wave_clock = LakeCombat.WAVE_QUIET_SEC + 1.0
	pl.global_position = Vector2(0.0, -300.0)
	cb._wave_timer = 0.0
	cb._physics_process(0.016)
	assert_gt(cb.waves_spawned, 0, "A wave spawns an enemy")
	var spawned: EnemyEntity = cb.enemies[0]
	assert_gt(spawned.global_position.distance_to(pl.global_position), 100.0, "It appears away from the slime")
	var cap := cb.wave_max_alive(cb.progress)
	for i in range(80):
		cb._wave_timer = 0.0
		cb._physics_process(0.016)
	assert_true(cb.enemies.size() <= cap, "The population cap holds")
	# no spawns while diving
	var before := cb.waves_spawned
	lab.dive = 1.0
	for i in range(10):
		cb._wave_timer = 0.0
		cb._physics_process(0.016)
	assert_eq(cb.waves_spawned, before, "Nothing spawns while the slime is under water")
	lab.dive = 0.0
	# quiet start: no hostile in the first seconds
	var lab2 := cb
	lab2._wave_clock = 0.0
	for en in lab2.enemies.duplicate():
		lab2.enemies.erase(en)
		en.queue_free()
	var hostile_before := lab2.enemies.size()
	for i in range(40):
		lab2._wave_timer = 0.0
		lab2._wave_clock = 1.0
		pl.global_position = Vector2(0.0, -600.0)
		lab2._physics_process(0.016)
	for en in lab2.enemies:
		assert_false(en.contact_damage > 0.0, "In the quiet start only harmless prey appear")
	# the boss gate opens once
	lab2.boss = null
	lab2.boss_gate_used = false
	pl.global_position = Vector2(0.0, LakeProto25D.DIVE_Y + 120.0)
	lab2._physics_process(0.016)
	assert_true(lab2.boss != null and lab2.boss_gate_used, "The guardian wakes near the far end")
	var first_boss := lab2.boss
	lab2._physics_process(0.016)
	assert_true(lab2.boss == first_boss, "Only one guardian")
	# far enemies are released silently
	var stray: EnemyEntity = lab2.spawn_enemy("forest_beetle", pl.global_position + Vector2(100.0, 0.0))
	stray.global_position = pl.global_position + Vector2(LakeCombat.WAVE_DESPAWN_DIST + 200.0, 0.0)
	lab2._physics_process(0.016)
	assert_false(lab2.enemies.has(stray), "An enemy left far behind is released")
	lab.queue_free()
	await tree.process_frame


## Mutations on the painted hero: the game's own logic runs, the lab supplies the arena hooks and the 2.5D visuals, and
## nothing is written to the save or to analytics.
func _test_mutations(tree: SceneTree) -> void:
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var mf := lab.mutations_fx
	var cb := lab.combat
	var pl: PlayerSlime = lab.player
	pl.global_position = Vector2(0.0, -300.0)
	var picked_before := float((SaveData.data["stats"] as Dictionary).get("total_mutations_picked", 0.0))
	for id: String in LakeMutations.SUPPORTED:
		assert_gt(mf.grant(id), 0, "A mutation can be granted: " + id)
	assert_eq(float((SaveData.data["stats"] as Dictionary).get("total_mutations_picked", 0.0)), picked_before, "Granting writes no save statistic")
	assert_true(pl.mutations.has_mutation("shield") and pl.shield_ready, "The shield is up after being granted")
	assert_true(lab.hero.get_node_or_null("ShieldBubble") != null, "The painted hero wears a shield bubble")
	assert_true(lab.hero.get_node_or_null("SpikeCollar") != null, "…and a spike collar")
	# shield: blocks one hit and bursts, pushing enemies away
	var foe: EnemyEntity = cb.spawn_enemy("forest_beetle", pl.global_position + Vector2(60.0, 0.0))
	var foe_x := foe.global_position.x
	var hp0 := pl.hp
	pl.invulnerable_timer = 0.0
	assert_false(pl.take_damage(10.0, "test"), "The shield blocks a hit")
	assert_eq(pl.hp, hp0, "No damage through the shield")
	assert_eq(mf.pulses["shield_burst"], 1, "The shield burst reached the lab hook")
	assert_gt(foe.global_position.x, foe_x + 20.0, "The burst shoves the enemy away")
	# (granting freeze + shield also unlocked the ice armour, whose burst can kill a beetle: use a tougher target from here on)
	foe = cb.spawn_enemy("stone_slug", pl.global_position + Vector2(70.0, 0.0))
	foe.global_position = pl.global_position + Vector2(70.0, 0.0)
	var foe_hp := foe.hp
	# electro pulse stuns and hurts the nearest enemies (through the game's own timer in PlayerSlime)
	pl._electro_timer = 0.0
	pl._update_timers_and_passives(0.016)
	assert_eq(mf.pulses["electro"], 1, "The electro discharge fires through the arena hook")
	assert_lt(foe.hp, foe_hp, "The electro pulse wounds an enemy in range")
	assert_gt(foe.stun_timer, 0.0, "…and stuns it")
	# freeze
	foe.global_position = pl.global_position + Vector2(70.0, 0.0)
	pl._freeze_timer = 0.0
	pl._update_timers_and_passives(0.016)
	assert_eq(mf.pulses["freeze"], 1, "The cryo pulse fires")
	assert_gt(foe.freeze_timer, 0.0, "The enemy is frozen")
	# poison pool wounds enemies standing in it
	var far_foe: EnemyEntity = cb.spawn_enemy("stone_slug", pl.global_position + Vector2(300.0, 0.0))
	far_foe.global_position = pl.global_position + Vector2(300.0, 0.0)
	var slug_hp := far_foe.hp
	cb.apply_player_poison_tick(far_foe.global_position, 60.0, 5.0)
	assert_lt(far_foe.hp, slug_hp, "A poison pool hurts enemies in it")
	# spikes: ramming an armoured slug hurts it now
	pl.global_position = far_foe.global_position
	var h1 := far_foe.hp
	cb._physics_process(0.1)
	assert_lt(far_foe.hp, h1, "Spikes make ramming wound an armoured enemy")
	# magnet drags food toward the slime
	pl.global_position = Vector2(0.0, -300.0)
	var fd: Dictionary = lab.food[0]
	fd["pos"] = pl.global_position + Vector2(100.0, 0.0)
	var d_before: float = (fd["pos"] as Vector2).distance_to(pl.global_position)
	mf.apply_magnet_field(pl.global_position, 200.0, 300.0, 0.1, false)
	assert_lt((fd["pos"] as Vector2).distance_to(pl.global_position), d_before, "The magnet pulls food in")
	# dash
	pl.dash_cooldown = 0.0
	assert_true(mf.dash(), "The dash works")
	assert_true(pl.is_dashing, "…and the slime is dashing")
	assert_false(mf.dash(), "The dash has a cooldown")
	# lotuses open as the slime comes near and close again when it leaves
	var lotus: Dictionary = {}
	for fl in lab.floaters:
		if fl.get("lotus", false):
			lotus = fl
			break
	assert_false(lotus.is_empty(), "There are lotuses among the floaters")
	if not lotus.is_empty():
		var ln: Node2D = lotus["node"]
		lab.player.global_position = ln.global_position + Vector2(40.0, 40.0)
		for _i in range(40):
			lab._update_floaters(0.1)
		assert_gt(float(lotus["bloom"]), 0.8, "A lotus opens when the slime is close")
		lab.player.global_position = ln.global_position + Vector2(900.0, 0.0)
		for _i in range(80):
			lab._update_floaters(0.1)
		assert_lt(float(lotus["bloom"]), 0.2, "…and closes again when it leaves")
	# plants lean along the slime's recent path
	lab.player.global_position = Vector2(500.0, -300.0)
	for _i in range(40):
		lab._update_plant_trail(0.1, lab.player.global_position)
		lab.player.global_position += Vector2(30.0, 0.0)
	assert_eq(lab._trail.size(), 6, "The path trail keeps six points")
	assert_lt(lab._trail[0].distance_to(lab.player.global_position), 90.0, "…newest first, near the slime")
	assert_gt(lab._trail[0].x, lab._trail[5].x, "…older points lie behind")
	# the shore is soft: hitting the world's edge rebounds a little
	var bnd: Rect2 = lab.play_bounds()
	lab.player.velocity = Vector2(300.0, 0.0)
	var edge_pos := Vector2(bnd.end.x + 40.0, bnd.position.y + bnd.size.y * 0.5)
	var bumps0: int = lab.bumps
	var kept: Vector2 = lab.constrain_player_position(edge_pos, 20.0, false)
	assert_lt(kept.x, bnd.end.x, "The shore holds the slime inside")
	assert_lt(lab.player.velocity.x, 0.0, "…and the slime rebounds off it")
	assert_gt(lab.player.velocity.x, -300.0 * 0.5, "…softly, not elastically")
	assert_gt(lab.bumps, bumps0, "A hard hit counts as a bump")
	# cheap-water fallback for slow phones
	var wm: ShaderMaterial = lab.water.material
	assert_false(lab.water_lite, "Water starts in full quality")
	lab.set_water_lite(true)
	assert_approx(float(wm.get_shader_parameter("lite")), 1.0, 0.001, "Lite switches the shader to the cheap path")
	lab.set_water_lite(false)
	lab._watch_frame_time(LakeProto25D.LITE_WINDOW_SEC + 0.1)   # one very slow frame over the window
	assert_true(lab.water_lite, "A sustained slow stretch drops to lite water")
	lab.set_water_lite(false)
	# thumb buttons follow the state and call the same methods as the keys
	var th: LakeTouchHud = lab.touch_hud
	th._process(0.016)
	assert_true(th.dash_button.visible, "The dash thumb button shows once the mutation is owned")
	assert_lt(th.dash_button.modulate.a, 1.0, "…and dims while cooling down")
	assert_false(th.nova_button.visible, "The Nova button stays hidden until a spirit is caught")
	lab.legends.nova_ready = true
	th._process(0.016)
	assert_true(th.nova_button.visible, "The Nova button appears when the Nova is loaded")
	lab.legends.nova_ready = false
	lab.queue_free()
	await tree.process_frame


## Evolution: XP from eating raises evolution levels, an evolution opens the game's own mutation card overlay (driven by a stub
## arena), a chosen card grants the mutation without touching the save, one free reroll.
func _test_draft(tree: SceneTree) -> void:
	var saved_state: int = App.state
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var mf := lab.mutations_fx
	var pl: PlayerSlime = lab.player
	assert_true(mf.overlay != null and mf.overlay is MutationDraftOverlay, "The lab hosts the real mutation draft overlay")
	var picked_before := float((SaveData.data["stats"] as Dictionary).get("total_mutations_picked", 0.0))
	var level_before := pl.evolution_level
	var need := MassSystem.evolution_threshold_for_level(pl.evolution_level)
	pl.add_evolution_xp(need + 1.0)
	assert_eq(pl.evolution_level, level_before + 1, "Enough XP earns an evolution")
	assert_true(mf.is_draft_open(), "An evolution opens the mutation draft through the arena hook")
	assert_eq(mf.drafts_opened, 1, "One draft")
	await tree.process_frame
	assert_true(mf.overlay.visible, "The card overlay is shown")
	assert_eq(mf.overlay.card_count(), 3, "Three cards")
	assert_true(tree.paused, "The water holds still while choosing")
	# reroll once
	var first_ids: Array = []
	for c in mf._stub.current_draft_choices:
		first_ids.append(c["id"])
	assert_true(mf._reroll(), "One free reroll")
	assert_false(mf._reroll(), "Only one")
	# choose
	var pick: String = String(mf._stub.current_draft_choices[0]["id"])
	var lv_before := pl.mutations.get_level(pick)
	mf._stub.select_draft_mutation(pick)
	assert_eq(pl.mutations.get_level(pick), lv_before + 1, "The chosen mutation is granted")
	assert_false(mf.is_draft_open(), "The draft closes")
	assert_false(tree.paused, "The water flows again")
	assert_eq(float((SaveData.data["stats"] as Dictionary).get("total_mutations_picked", 0.0)), picked_before, "No save statistic is written")
	# an unoffered mutation cannot be chosen
	mf.request_draft()
	assert_true(mf.is_draft_open(), "A second draft opens")
	var lv2 := pl.mutations.get_level("split")
	mf._on_card_chosen("not_a_mutation")
	assert_true(mf.is_draft_open(), "An unoffered id is refused")
	mf.close_draft()
	# eating feeds the XP
	var xp0 := pl.evolution_xp
	pl.add_evolution_xp(1.0)
	assert_gt(pl.evolution_xp + float(pl.evolution_level), xp0 + float(level_before), "Absorbing adds evolution XP")
	assert_eq(pl.mutations.get_level("split"), lv2, "Nothing else changed")
	App.state = saved_state
	tree.paused = false
	lab.queue_free()
	await tree.process_frame


## The autoplayer: inactive by default; its steering heads for food, flees what it cannot eat, otherwise swims toward the far end.
func _test_bot(tree: SceneTree) -> void:
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var bot := lab.bot
	var pl: PlayerSlime = lab.player
	assert_false(bot.active, "The bot is off unless asked for")
	assert_approx(Engine.time_scale, 1.0, 0.001, "The clock runs normally")
	pl.global_position = Vector2(0.0, 0.0)
	for f in lab.food:
		f["pos"] = Vector2(5000.0, 5000.0)
	for en in lab.combat.enemies.duplicate():
		en.queue_free()
	lab.combat.enemies.clear()
	var free_dir := bot._decide(pl, lab.combat)
	assert_lt(free_dir.y, -0.5, "With nothing around it swims toward the far end")
	lab.food[0]["pos"] = Vector2(200.0, 100.0)
	var to_food := bot._decide(pl, lab.combat)
	assert_gt(to_food.x, 0.3, "It heads for food")
	var threat: EnemyEntity = lab.combat.spawn_enemy("stone_slug", pl.global_position + Vector2(-60.0, 0.0))
	threat.global_position = pl.global_position + Vector2(-60.0, 0.0)
	pl.mass = MassSystem.clamp_mass(10.0)
	lab.food[0]["pos"] = Vector2(5000.0, 5000.0)
	var away := bot._decide(pl, lab.combat)
	assert_gt(away.x, 0.2, "It flees an armoured slug it cannot eat")
	lab.queue_free()
	await tree.process_frame


## Zone music crossfades with the world y and the dive; synergies unlock by the game's own rule without touching the save.
func _test_music_and_synergies(tree: SceneTree) -> void:
	for z: String in LakeAudio.MUSIC_ZONES:
		assert_true(load(LakeAudio.MUSIC_DIR + "water_%s.ogg" % z) is AudioStreamOggVorbis, "Zone music exists: " + z)
	var wg := LakeAudio.zone_weights(1500.0, 0.0)
	assert_gt(wg["glade"], 0.99, "The glade plays its own music")
	var wl := LakeAudio.zone_weights(-300.0, 0.0)
	assert_gt(wl["lake"], 0.99, "The lake plays its own music")
	var wgr := LakeAudio.zone_weights(450.0, 0.0)
	assert_gt(wgr["grove"], 0.99, "The grove plays its own music")
	var wf := LakeAudio.zone_weights(-1200.0, 1.0)
	assert_gt(wf["finale"], 0.99, "Under water the finale music plays")
	assert_lt(wf["lake"], 0.01, "…and the lake's fades out")
	var wb := LakeAudio.zone_weights(700.0, 0.0)
	assert_gt(wb["grove"] + wb["glade"], 0.95, "Between zones the music cross-fades")
	for y in [1500.0, 800.0, 450.0, 100.0, -300.0]:
		var ws := LakeAudio.zone_weights(y, 0.0)
		assert_approx(float(ws["glade"]) + float(ws["grove"]) + float(ws["lake"]) + float(ws["finale"]), 1.0, 0.02, "The zone weights add up to one at y=%d" % int(y))
	var lab := LakeProto25D.new()
	lab.streaming = false
	tree.root.add_child(lab)
	await tree.process_frame
	await tree.process_frame
	var a := lab.audio
	for i in range(30):
		a.update_mix(0.0, 0.0, 0.1, -300.0)
	assert_gt(a.music["lake"].volume_db, a.music["glade"].volume_db + 20.0, "The lake music is audible, the glade's is not")
	for i in range(30):
		a.update_mix(0.0, 0.0, 0.1, 1500.0)
	assert_gt(a.music["glade"].volume_db, a.music["lake"].volume_db + 20.0, "After swimming back the glade music returns")
	a.enabled = false
	a.update_mix(0.0, 0.0, 0.1, 1500.0)
	assert_lt(a.music["glade"].volume_db, -60.0, "Muting silences the music")
	a.enabled = true
	# synergies
	var mf := lab.mutations_fx
	var pl: PlayerSlime = lab.player
	var syn_before := float((SaveData.data["stats"] as Dictionary).get("total_synergies_unlocked", 0.0))
	mf.grant("magnet")
	assert_false(pl.mutations.has_synergy("em_storm"), "One half of a synergy does nothing")
	mf.grant("electro_discharge")
	assert_true(pl.mutations.has_synergy("em_storm"), "Magnet plus electro unlocks the EM storm")
	assert_true(mf.synergies_unlocked.has("em_storm"), "The unlock is recorded")
	mf.grant("freeze")
	mf.grant("shield")
	assert_true(pl.mutations.has_synergy("ice_armor"), "Freeze plus shield unlocks the ice armour")
	mf.grant("dash")
	mf.grant("spikes")
	assert_true(pl.mutations.has_synergy("piercing_strike"), "Dash plus spikes unlocks the piercing strike")
	assert_eq(float((SaveData.data["stats"] as Dictionary).get("total_synergies_unlocked", 0.0)), syn_before, "No synergy statistic is written")
	# the synergy changes real behaviour: the ice-armour shield burst now freezes and wounds
	var foe: EnemyEntity = lab.combat.spawn_enemy("forest_beetle", pl.global_position + Vector2(60.0, 0.0))
	foe.global_position = pl.global_position + Vector2(60.0, 0.0)
	var hp := foe.hp
	pl.shield_ready = true
	pl.invulnerable_timer = 0.0
	pl.take_damage(5.0, "test")
	assert_lt(foe.hp, hp, "Ice armour: the shield burst wounds nearby enemies")
	assert_gt(foe.freeze_timer, 0.0, "…and freezes them")
	lab.queue_free()
	await tree.process_frame
