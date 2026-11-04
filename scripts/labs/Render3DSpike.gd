class_name Render3DSpike
extends Node3D
## PHASE 2 (master plan 1.1) render spike: can the "Moonlit Mycelium" look run
## as real 3D on a phone? Gameplay stays 2D: a real PlayerSlime moves on the
## plane with the game's own movement code, mass grows through MassSystem, and
## this node only *displays* that state in 3D under a fixed tilted camera.
## Lab only: the arena, saves and gameplay formulas are untouched.
##
## Three display modes are compared in the same scene:
##   FULL_3D   — real-time sun with shadows, per-pixel props, bloom optional.
##   HYBRID    — no real-time shadows; per-vertex props and blob shadows, i.e.
##               the cost profile of baked lighting (a true LightmapGI bake is
##               editor-only and is evaluated in PHASE 3 with Blender assets).
##   PRERENDER — props rendered once to textures at the camera angle and shown
##               as flat sprites (stand-in for Blender 3D-to-2D prerender).
## The slime itself is always 3D: it must deform and react.

enum Mode { FULL_3D, HYBRID, PRERENDER }
const MODE_NAMES: Array[String] = ["3D", "Гибрид", "Пререндер"]

## 2D gameplay pixels -> 3D metres. The 2D y axis (down) maps to +Z (towards
## the camera), so "up" on the old 2D screen stays "up" on the phone.
const PX_TO_M := 0.01
const GLADE_RADIUS_PX := 430.0
const CAMERA_PITCH_DEG := 48.0
const CAMERA_HFOV_DEG := 40.0
const CAMERA_BASE_DIST := 4.4
const FOOD_COUNT := 24
const FOOD_RADIUS_PX := 8.0
const FOOD_SPORE := 1
const FOOD_MINERAL := 2
const DOME_HEIGHT := 1.3
const IMPOSTOR_SIZE := 256

const BENCH_WARMUP := 3.0
const BENCH_MEASURE := 15.0
const BENCH_PLAN: Array[Vector2i] = [
	Vector2i(Mode.FULL_3D, 1), Vector2i(Mode.HYBRID, 1), Vector2i(Mode.PRERENDER, 1),
	Vector2i(Mode.FULL_3D, 3), Vector2i(Mode.HYBRID, 3), Vector2i(Mode.PRERENDER, 3),
]
const RESULTS_PATH := "user://render_spike_results.csv"

const PROP_TYPES: Array[String] = ["stone", "stone_b", "moss", "mushroom_violet", "mushroom_big", "mushroom_cyan", "fern", "leaf", "stump", "pool"]

## PHASE 3: Blender models (art_sources/3d/blender/smush_moonlit_grove.blend).
## A missing file falls back to the PHASE 2 primitive of the same type.
const ASSET_DIR := "res://resources/art/3d/moonlit/"
const PROP_ASSETS := {
	"stump": "stump", "stone": "stone_a", "stone_b": "stone_b", "moss": "moss_cushion",
	"mushroom_violet": "mushroom_cluster_violet", "mushroom_big": "mushroom_big",
	"mushroom_cyan": "mushroom_cluster_cyan", "fern": "fern", "leaf": "leaf_big",
	"tree": "tree_trunk", "branch": "foliage_branch",
}
const CLOVER_COUNT := 260
const GRASS_COUNT := 900

var mode: int = Mode.FULL_3D
var density: int = 1
var bloom: bool = true
var player: PlayerSlime
var food: Array[Dictionary] = []
var food_echo: GroveStudy.FoodEcho
var auto_steer: bool = false
var impostors_ready: bool = false
var hero_from_model: bool = false

var _logic_root: Node2D
var _camera: Camera3D
var _sun: DirectionalLight3D
var _env: Environment
var _ground_mat: ShaderMaterial
var _props_root: Node3D
var _impostor_root: Node3D
var _blob_root: Node3D
var _slime: Node3D
var _jelly_mat: ShaderMaterial
var _core: MeshInstance3D
var _core_mat: StandardMaterial3D
var _eyes: Array[Node3D] = []
var _echo_nodes: Array[MeshInstance3D] = []
var _impostor_tex: Dictionary = {}
var _meshes: Dictionary = {}
var _mats: Dictionary = {}
var _layout: Array[Dictionary] = []
var _rng := RandomNumberGenerator.new()

var _prev_pos := Vector2.ZERO
var _cur_pos := Vector2.ZERO
var _stretch := 0.0
var _gulp := 0.0
var _blink_t := 3.0
var _clock := 0.0
var _touching := false
var _touch_screen := Vector2.ZERO
var _auto_angle := 0.0

var _hud: Label
var _mode_btn: Button
var _density_btn: Button
var _bloom_btn: Button
var _bench_btn: Button
var _frame_ms := PackedFloat32Array()
var _gpu_ms := PackedFloat32Array()
var _cpu_ms := PackedFloat32Array()
var _bench_index := -1
var _bench_clock := 0.0
var _bench_samples: Dictionary = {}


static func to_world(p: Vector2) -> Vector3:
	return Vector3(p.x * PX_TO_M, 0.0, p.y * PX_TO_M)


static func to_plane(w: Vector3) -> Vector2:
	return Vector2(w.x, w.z) / PX_TO_M


static func camera_basis() -> Basis:
	return Basis(Vector3.RIGHT, deg_to_rad(-CAMERA_PITCH_DEG))


static func camera_distance(radius_px: float) -> float:
	return CAMERA_BASE_DIST * pow(maxf(radius_px, MassSystem.MIN_RADIUS) / MassSystem.MIN_RADIUS, 0.55)


static func percentile(values: PackedFloat32Array, q: float) -> float:
	if values.is_empty():
		return 0.0
	var sorted := values.duplicate()
	sorted.sort()
	return sorted[clampi(int(round(q * float(sorted.size() - 1))), 0, sorted.size() - 1)]


func _ready() -> void:
	_rng.seed = 20261103
	food_echo = GroveStudy.FoodEcho.new()
	_build_logic()
	_build_world()
	_build_slime()
	_build_food()
	_build_hud()
	_apply_mode()
	RenderingServer.viewport_set_measure_render_time(get_viewport().get_viewport_rid(), true)
	if OS.has_feature("render_spike") or OS.get_cmdline_user_args().has("--spike-bench"):
		get_tree().create_timer(4.0).timeout.connect(start_bench)
	_apply_capture_args()


## Desktop capture: -- --spike-mode=1 --spike-bloom=0 --spike-mass=60
## --spike-move --spike-shot=/tmp/a.png --spike-at=3
func _apply_capture_args() -> void:
	var args := {}
	for a in OS.get_cmdline_user_args():
		var kv := a.trim_prefix("--").split("=", true, 1)
		args[kv[0]] = kv[1] if kv.size() > 1 else ""
	if args.has("spike-mass"):
		player.mass = MassSystem.clamp_mass(float(args["spike-mass"]))
		player._sync_mass_metrics()
	if args.has("spike-bloom"):
		set_bloom(args["spike-bloom"] != "0")
	if args.has("spike-mode"):
		set_mode(int(args["spike-mode"]))
	if args.has("spike-move"):
		auto_steer = true
	if args.has("spike-unshaded"):
		for child in _props_root.get_children():
			if String(child.name).begins_with(args["spike-unshaded"]):
				for mi: MeshInstance3D in child.find_children("*", "MeshInstance3D", true, false):
					for s in range(mi.mesh.get_surface_count()):
						var m := mi.get_active_material(s).duplicate() as BaseMaterial3D
						m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
						mi.set_surface_override_material(s, m)
	if args.has("spike-hide"):
		for child in _props_root.get_children():
			if String(child.name).begins_with(args["spike-hide"]):
				child.visible = false
	if args.has("spike-novsync"):
		# Relative desktop cost comparison only; phones keep vsync.
		DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	if args.has("spike-shot"):
		var at := float(args.get("spike-at", "3"))
		await get_tree().create_timer(at).timeout
		await RenderingServer.frame_post_draw
		get_viewport().get_texture().get_image().save_png(args["spike-shot"])
		print("SPIKE_SHOT ", args["spike-shot"])
		quit_cleanly()


## Same exit path as ClaudeVisualLab: release Vorbis streams before quitting so
## a standalone run ends without leaked resources.
func quit_cleanly() -> void:
	Audio.set_process(false)
	for child in Audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	for _i in range(8):
		await get_tree().process_frame
	get_tree().quit()


func _exit_tree() -> void:
	if food_echo != null:
		food_echo.free()
		food_echo = null


## --- 2D gameplay layer -------------------------------------------------------

func _build_logic() -> void:
	_logic_root = Node2D.new()
	_logic_root.name = "Logic2D"
	_logic_root.visible = false
	add_child(_logic_root)
	player = PlayerSlime.new()
	_logic_root.add_child(player)
	player.initialize_for_run(self)
	# Peak mass is a persistent save stat; the lab must not write it.
	player.peak_mass = MassSystem.MAX_MASS
	if player.visual != null:
		player.visual.visible = false
		player.visual.process_mode = Node.PROCESS_MODE_DISABLED
	_cur_pos = player.global_position
	_prev_pos = _cur_pos


## Arena contract used by PlayerSlime: keep the slime inside the glade.
func constrain_player_position(pos: Vector2, radius: float, _dashing: bool) -> Vector2:
	var limit := GLADE_RADIUS_PX - radius
	return pos.limit_length(limit)


func _physics_process(_delta: float) -> void:
	_steer()
	_prev_pos = _cur_pos
	_cur_pos = player.global_position
	_check_food()


func _steer() -> void:
	if _touching and _camera != null:
		var target := screen_to_plane(_touch_screen)
		var to := target - player.global_position
		player.move_input = to.normalized() * clampf(to.length() / 80.0, 0.0, 1.0) if to.length() > 4.0 else Vector2.ZERO
	elif auto_steer:
		_auto_angle += get_physics_process_delta_time() * 0.55
		var goal := Vector2.from_angle(_auto_angle) * GLADE_RADIUS_PX * 0.55
		player.move_input = (goal - player.global_position).normalized()
	else:
		player.move_input = Vector2.ZERO


func screen_to_plane(screen_pos: Vector2) -> Vector2:
	var origin := _camera.project_ray_origin(screen_pos)
	var dir := _camera.project_ray_normal(screen_pos)
	if absf(dir.y) < 0.0001:
		return player.global_position
	var t := -origin.y / dir.y
	return to_plane(origin + dir * t)


func plane_to_screen(p: Vector2) -> Vector2:
	return _camera.unproject_position(to_world(p))


func _check_food() -> void:
	var reach := player.get_radius() + FOOD_RADIUS_PX
	for i in range(food.size()):
		if player.global_position.distance_to(food[i]["pos"]) < reach:
			absorb_food(i)


func absorb_food(i: int) -> void:
	var f: Dictionary = food[i]
	var kind: int = f["kind"]
	var gain := 0.8 if kind == FOOD_SPORE else 1.4
	player.mass = MassSystem.clamp_mass(player.mass + MassSystem.effective_gain(player.mass, gain))
	player._sync_mass_metrics()
	food_echo.remember(kind)
	_gulp = 1.0
	var local: Vector2 = (f["pos"] as Vector2) - player.global_position
	_jelly_mat.set_shader_parameter("gulp_dir", Vector3(local.x, 0.35 * local.length(), local.y).normalized())
	if kind == FOOD_SPORE:
		Audio.play_orb_chime()
	else:
		Audio.play_sfx("absorb", 0.94 + 0.05 * float(Audio.chime_step() % 5))
	_place_food(f)


func _place_food(f: Dictionary) -> void:
	for _attempt in range(12):
		var p := Vector2.from_angle(_rng.randf() * TAU) * sqrt(_rng.randf()) * (GLADE_RADIUS_PX - 60.0)
		if player == null or p.distance_to(player.global_position) > 160.0:
			f["pos"] = p
			break
	var node: Node3D = f["node"]
	node.position = to_world(f["pos"])


## --- 3D world ----------------------------------------------------------------

func _build_world() -> void:
	var we := WorldEnvironment.new()
	_env = Environment.new()
	_env.background_mode = Environment.BG_COLOR
	_env.background_color = Color(0.17, 0.18, 0.38)
	_env.ambient_light_source = Environment.AMBIENT_SOURCE_COLOR
	_env.ambient_light_color = Color(0.46, 0.55, 0.66)
	# Concept lighting: a dim moonlit base so the glowing mushrooms, mycelium
	# and food read as accents instead of everything being evenly lit.
	_env.ambient_light_energy = 0.32
	_env.tonemap_mode = Environment.TONE_MAPPER_FILMIC
	_env.glow_intensity = 0.8
	_env.glow_hdr_threshold = 0.95
	_env.glow_bloom = 0.05
	_env.fog_enabled = true
	_env.fog_light_color = Color(0.17, 0.18, 0.38)
	# Depth fog melts the far ground into the violet distance (concept top band)
	# without veiling the play area around the slime.
	_env.fog_mode = Environment.FOG_MODE_DEPTH
	_env.fog_depth_begin = 5.0
	_env.fog_depth_end = 15.0
	_env.fog_density = 1.0
	we.environment = _env
	add_child(we)

	_sun = DirectionalLight3D.new()
	_sun.light_color = Color(0.78, 0.86, 0.96)
	_sun.light_energy = 0.85
	_sun.rotation_degrees = Vector3(-55.0, 160.0, 0.0)
	_sun.directional_shadow_mode = DirectionalLight3D.SHADOW_ORTHOGONAL
	_sun.directional_shadow_max_distance = 14.0
	add_child(_sun)

	_camera = Camera3D.new()
	_camera.keep_aspect = Camera3D.KEEP_WIDTH
	_camera.fov = CAMERA_HFOV_DEG
	_camera.near = 0.1
	_camera.far = 40.0
	_camera.basis = camera_basis()
	add_child(_camera)
	_camera.make_current()

	var ground := MeshInstance3D.new()
	var plane := PlaneMesh.new()
	plane.size = Vector2.ONE * 60.0
	ground.mesh = plane
	_ground_mat = ShaderMaterial.new()
	_ground_mat.shader = load("res://shaders/spike/ground_mycelium.gdshader")
	var noise := FastNoiseLite.new()
	noise.seed = 11
	noise.frequency = 0.012
	noise.fractal_octaves = 3
	var tex := NoiseTexture2D.new()
	tex.width = 256
	tex.height = 256
	tex.seamless = true
	tex.generate_mipmaps = true
	tex.noise = noise
	_ground_mat.set_shader_parameter("noise_tex", tex)
	_ground_mat.set_shader_parameter("glade_radius", GLADE_RADIUS_PX * PX_TO_M)
	ground.material_override = _ground_mat
	ground.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(ground)

	_props_root = Node3D.new()
	_props_root.name = "Props3D"
	add_child(_props_root)
	_impostor_root = Node3D.new()
	_impostor_root.name = "PropsPrerender"
	add_child(_impostor_root)
	_blob_root = Node3D.new()
	_blob_root.name = "BlobShadows"
	add_child(_blob_root)
	_rebuild_props()
	_build_clover()
	_build_light_rays()


## Hand-placed composition after the approved concept (B_open_glade): landmark
## stump up the screen, moonlit pool on the right, mushrooms and a fern framing
## the corners, big leaves at the bottom edge, centre left open for movement.
## Positions in gameplay px (2D +y = towards the camera / down the screen).
func _layout_composed() -> Array[Dictionary]:
	var c: Array[Dictionary] = []
	# v2: the concept frames the open centre tightly, so decor is larger and sits
	# right at the visible edges (half-width ~145 px at the slime, ~175 px up top).
	# v3: tree and foliage frame the top corner; mushrooms grow on the stump
	# (optional 5th value: height above the ground in metres).
	for e: Array in [
		["stump", Vector2(40, -280), 1.05, 0.4], ["pool", Vector2(150, -105), 0.5, 0.0],
		["tree", Vector2(-215, -370), 0.75, 0.6], ["branch", Vector2(-120, -330), 1.3, -0.4, 1.5],
		["branch", Vector2(-205, -250), 1.1, 0.5, 0.9], ["branch", Vector2(-200, 310), 0.9, 0.3, 0.12],
		["branch", Vector2(195, 320), 0.85, 2.8, 0.1],
		["mushroom_violet", Vector2(5, -300), 0.45, 0.2, 0.95], ["mushroom_cyan", Vector2(80, -262), 0.35, 1.0, 0.85],
		["mushroom_violet", Vector2(95, -230), 0.6, 2.2],
		["mushroom_violet", Vector2(-35, -205), 0.95, 1.1], ["mushroom_cyan", Vector2(115, -195), 0.9, 0.3],
		["mushroom_violet", Vector2(130, -275), 0.8, 2.4], ["stone_b", Vector2(165, -235), 0.8, 0.3],
		["leaf", Vector2(-165, -265), 1.4, 1.2], ["moss", Vector2(-150, -190), 0.8, 0.0],
		["stone", Vector2(-140, -70), 0.95, 0.5], ["moss", Vector2(-160, -115), 0.7, 1.0],
		["mushroom_violet", Vector2(-135, 25), 0.95, 0.7], ["fern", Vector2(160, 35), 1.0, 1.4],
		["stone_b", Vector2(150, 95), 0.75, 2.0], ["moss", Vector2(-150, 125), 0.95, 2.0],
		["fern", Vector2(-120, 190), 1.45, 0.2], ["mushroom_big", Vector2(110, 175), 1.4, 0.0],
		["mushroom_violet", Vector2(55, 215), 0.8, 2.0], ["stone", Vector2(135, 245), 1.25, 1.0],
		["stone_b", Vector2(-95, 255), 1.0, 1.7], ["leaf", Vector2(-145, 265), 1.6, -0.5],
		["leaf", Vector2(-55, 285), 1.2, 0.3], ["leaf", Vector2(155, 285), 1.5, 2.6],
		["mushroom_cyan", Vector2(-100, -150), 0.8, 1.9],
	]:
		c.append({"type": e[0], "pos": e[1], "s": e[2], "rot": e[3], "h": e[4] if e.size() > 4 else 0.0})
	return c


## Decor ring beyond the composed frame (density stress multiplies it).
func _layout_for(dens: int) -> Array[Dictionary]:
	var rng := RandomNumberGenerator.new()
	rng.seed = 7
	var out: Array[Dictionary] = _layout_composed()
	var kinds: Array[String] = ["stone", "stone_b", "moss", "moss", "mushroom_violet", "mushroom_cyan", "fern", "leaf"]
	var clusters := 6 * dens
	for c in range(clusters):
		var ang := TAU * float(c) / float(clusters) + rng.randf_range(-0.2, 0.2)
		var center := Vector2.from_angle(ang) * rng.randf_range(330.0, 430.0)
		for _k in range(3):
			var p := center + Vector2(rng.randf_range(-70.0, 70.0), rng.randf_range(-70.0, 70.0))
			out.append({"type": kinds[rng.randi() % kinds.size()], "pos": p, "s": rng.randf_range(0.55, 0.95), "rot": rng.randf() * TAU})
	return out


func _rebuild_props() -> void:
	for root: Node3D in [_props_root, _impostor_root, _blob_root]:
		for child in root.get_children():
			child.queue_free()
	_layout = _layout_for(density)
	for spec in _layout:
		var node := _build_prop(spec["type"])
		node.position = to_world(spec["pos"]) + Vector3.UP * float(spec.get("h", 0.0))
		node.rotation.y = spec["rot"]
		node.scale = Vector3.ONE * float(spec["s"])
		_props_root.add_child(node)
		if spec["type"] != "pool":
			_blob_root.add_child(_make_blob(to_world(spec["pos"]), _blob_radius(spec["type"]) * float(spec["s"])))
	_refresh_impostor_sprites()


func _blob_radius(type: String) -> float:
	match type:
		"stump": return 0.95
		"stone": return 0.42
		"stone_b": return 0.3
		"moss": return 0.45
		"fern": return 0.35
		"leaf", "branch": return 0.0
		"tree": return 1.3
		"mushroom_big": return 0.28
	return 0.22


func _asset(asset_name: String) -> Node3D:
	if asset_name.is_empty():
		return null
	var path := ASSET_DIR + asset_name + ".glb"
	if ResourceLoader.exists(path):
		return (load(path) as PackedScene).instantiate() as Node3D
	# Raw source pack (tools/build_pck.py) has no imported scenes: read the glb
	# directly, as AssetRegistry does for PNGs.
	if not FileAccess.file_exists(path):
		return null
	var doc := GLTFDocument.new()
	var state := GLTFState.new()
	if doc.append_from_buffer(FileAccess.get_file_as_bytes(path), "", state) != OK:
		return null
	return doc.generate_scene(state) as Node3D


## glTF exports Blender materials double-sided; on the thin mushroom lip the
## back faces render as a red/yellow fringe. Cull them (shared per material).
func _single_sided(model: Node3D) -> void:
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		for s in range(mi.mesh.get_surface_count()):
			var key := "single_" + str(mi.mesh.surface_get_material(s).get_instance_id())
			if not _mats.has(key):
				var m := mi.mesh.surface_get_material(s).duplicate() as BaseMaterial3D
				m.cull_mode = BaseMaterial3D.CULL_BACK
				m.roughness = maxf(m.roughness, 0.55)
				m.metallic_specular = 0.25
				_mats[key] = m
			mi.set_surface_override_material(s, _mats[key])


func _first_mesh(n: Node) -> Mesh:
	if n is MeshInstance3D:
		return (n as MeshInstance3D).mesh
	for child in n.get_children():
		var m := _first_mesh(child)
		if m != null:
			return m
	return null


## Ground cover: Blender clover rosettes and grass tufts, one MultiMesh each
## (a single draw call per kind). Grass thickens away from the open centre.
func _build_clover() -> void:
	_scatter("clover", "Clover", CLOVER_COUNT, 31, 70.0, 0.7, 1.5, 0.0)
	_scatter("grass_tuft", "Grass", GRASS_COUNT, 47, 40.0, 0.8, 1.9, 1.6)
	# Glowing mycelium threads running over the ground between the decor: a soft
	# cyan accent (the Blender emission blooms to white at this density).
	_scatter("mycelium_patch", "Mycelium", 24, 53, 110.0, 1.0, 1.6, 0.8)
	var myc := get_node_or_null("Mycelium") as MultiMeshInstance3D
	if myc != null:
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.22, 0.62, 0.62)
		m.emission_enabled = true
		m.emission = Color(0.3, 0.9, 0.85)
		m.emission_energy_multiplier = 0.35
		myc.material_override = m


func _scatter(asset_name: String, node_name: String, count: int, seed: int, inner_px: float, s_min: float, s_max: float, edge_bias: float) -> void:
	var src := _asset(asset_name)
	if src == null:
		return
	var mm := MultiMesh.new()
	mm.transform_format = MultiMesh.TRANSFORM_3D
	mm.mesh = _first_mesh(src)
	src.free()
	mm.instance_count = count
	var rng := RandomNumberGenerator.new()
	rng.seed = seed
	for i in range(count):
		var t := pow(rng.randf(), 1.0 / (2.0 + edge_bias))
		var p := Vector2.from_angle(rng.randf() * TAU) * lerpf(inner_px, GLADE_RADIUS_PX, t)
		var s := rng.randf_range(s_min, s_max)
		mm.set_instance_transform(i, Transform3D(Basis(Vector3.UP, rng.randf() * TAU).scaled(Vector3.ONE * s), to_world(p)))
	var mmi := MultiMeshInstance3D.new()
	mmi.name = node_name
	mmi.multimesh = mm
	mmi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	add_child(mmi)


## Soft moonbeams far up the screen (concept top band): a few additive cards.
func _build_light_rays() -> void:
	var grad := Gradient.new()
	grad.set_color(0, Color(0.7, 0.75, 1.0, 0.0))
	grad.add_point(0.35, Color(0.7, 0.75, 1.0, 0.22))
	grad.set_color(grad.get_point_count() - 1, Color(0.7, 0.75, 1.0, 0.0))
	var gt := GradientTexture2D.new()
	gt.gradient = grad
	gt.fill_from = Vector2(0.5, 0.0)
	gt.fill_to = Vector2(0.5, 1.0)
	var m := StandardMaterial3D.new()
	m.albedo_texture = gt
	m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	m.blend_mode = BaseMaterial3D.BLEND_MODE_ADD
	m.cull_mode = BaseMaterial3D.CULL_DISABLED
	m.no_depth_test = false
	var q := QuadMesh.new()
	q.size = Vector2(0.9, 6.0)
	for i in range(4):
		var mi := MeshInstance3D.new()
		mi.mesh = q
		mi.material_override = m
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		mi.position = Vector3(-2.2 + i * 0.9, 2.4, -5.5 - i * 0.4)
		mi.rotation = Vector3(0.0, 0.0, deg_to_rad(-22.0))
		mi.name = "Moonbeam%d" % i
		add_child(mi)


func prop_count() -> int:
	return _layout.size()


func _sphere(radius: float, radial: int = 16, rings: int = 8, hemi: bool = false) -> SphereMesh:
	var key := "s%.3f_%d_%d_%s" % [radius, radial, rings, hemi]
	if not _meshes.has(key):
		var m := SphereMesh.new()
		m.radius = radius
		m.height = radius * (1.0 if hemi else 2.0)
		m.radial_segments = radial
		m.rings = rings
		m.is_hemisphere = hemi
		_meshes[key] = m
	return _meshes[key]


func _stem_mesh() -> CylinderMesh:
	if not _meshes.has("stem"):
		var stem := CylinderMesh.new()
		stem.top_radius = 0.035
		stem.bottom_radius = 0.05
		stem.height = 1.0
		stem.radial_segments = 8
		stem.rings = 1
		_meshes["stem"] = stem
	return _meshes["stem"]


func _mat(key: String) -> StandardMaterial3D:
	if _mats.has(key):
		return _mats[key]
	var m := StandardMaterial3D.new()
	match key:
		"stone":
			m.albedo_color = Color(0.17, 0.24, 0.33)
			m.roughness = 0.75
		"moss":
			m.albedo_color = Color(0.15, 0.23, 0.16)
			m.roughness = 1.0
			m.emission_enabled = true
			m.emission = Color(0.2, 0.75, 0.7)
			m.emission_energy_multiplier = 0.03
		"cap_violet", "cap_cyan":
			m.albedo_color = Color(0.63, 0.48, 1.0) if key == "cap_violet" else Color(0.43, 0.88, 1.0)
			m.emission_enabled = true
			m.emission = m.albedo_color
			m.emission_energy_multiplier = 0.9
			m.roughness = 0.35
			m.rim_enabled = true
			m.rim = 0.6
		"stem":
			m.albedo_color = Color(0.80, 0.84, 1.0)
			m.emission_enabled = true
			m.emission = Color(0.7, 0.8, 1.0)
			m.emission_energy_multiplier = 0.25
		"fern":
			m.albedo_color = Color(0.18, 0.34, 0.27)
			m.roughness = 0.9
		"leaf":
			m.albedo_color = Color(0.20, 0.21, 0.48)
			m.roughness = 0.3
		"bark":
			m.albedo_color = Color(0.29, 0.26, 0.31)
			m.roughness = 0.95
		"hollow":
			m.albedo_color = Color(0.06, 0.05, 0.09)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		"mycelium":
			m.albedo_color = Color(0.37, 0.94, 0.88)
			m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
			m.emission_enabled = true
			m.emission = Color(0.37, 0.94, 0.88)
			m.emission_energy_multiplier = 1.2
	_mats[key] = m
	return m


func _mesh(parent: Node3D, mesh: Mesh, mat: Material, pos: Vector3, scl: Vector3 = Vector3.ONE, rot: Vector3 = Vector3.ZERO) -> MeshInstance3D:
	var mi := MeshInstance3D.new()
	mi.mesh = mesh
	mi.material_override = mat
	mi.position = pos
	mi.scale = scl
	mi.rotation = rot
	parent.add_child(mi)
	return mi


func _build_prop(type: String) -> Node3D:
	var model := _asset(PROP_ASSETS.get(type, ""))
	if model != null:
		model.name = type
		if type.begins_with("mushroom"):
			_single_sided(model)
		return model
	var n := Node3D.new()
	n.name = type
	match type:
		"stone":
			_mesh(n, _sphere(0.36), _mat("stone"), Vector3(0, 0.1, 0), Vector3(1.0, 0.62, 0.85))
			_mesh(n, _sphere(0.36), _mat("stone"), Vector3(0.32, 0.04, 0.12), Vector3(0.45, 0.3, 0.4))
		"moss":
			_mesh(n, _sphere(0.4), _mat("moss"), Vector3(0, 0.0, 0), Vector3(1.0, 0.45, 0.9))
			_mesh(n, _sphere(0.4), _mat("moss"), Vector3(0.3, 0.0, -0.18), Vector3(0.6, 0.35, 0.6))
		"mushroom_violet", "mushroom_cyan":
			var cap := _mat("cap_violet" if type == "mushroom_violet" else "cap_cyan")
			for j in range(3):
				var off := Vector3(cos(j * 2.1) * 0.12, 0, sin(j * 2.1) * 0.12) * (0.0 if j == 0 else 1.0)
				var h := 0.3 if j == 0 else 0.17
				_mesh(n, _stem_mesh(), _mat("stem"), off + Vector3(0, h * 0.5, 0), Vector3(1, h, 1))
				_mesh(n, _sphere(0.14, 16, 6, true), cap, off + Vector3(0, h - 0.02, 0), Vector3.ONE * (1.0 if j == 0 else 0.62))
		"fern":
			for j in range(5):
				var a := -0.9 + j * 0.45
				_mesh(n, _sphere(0.2, 8, 4), _mat("fern"), Vector3(sin(a) * 0.17, 0.05, -cos(a) * 0.17), Vector3(0.22, 0.12, 1.0), Vector3(0.25, a, 0))
		"leaf":
			_mesh(n, _sphere(0.16, 8, 4), _mat("leaf"), Vector3(0, 0.012, 0), Vector3(0.6, 0.08, 1.0))
		"stump":
			var trunk := CylinderMesh.new()
			trunk.top_radius = 0.52
			trunk.bottom_radius = 0.7
			trunk.height = 0.9
			trunk.radial_segments = 14
			trunk.rings = 1
			_mesh(n, trunk, _mat("bark"), Vector3(0, 0.45, 0))
			var hole := CylinderMesh.new()
			hole.top_radius = 0.4
			hole.bottom_radius = 0.4
			hole.height = 0.02
			hole.radial_segments = 14
			_mesh(n, hole, _mat("hollow"), Vector3(0, 0.905, 0))
			var ring := TorusMesh.new()
			ring.inner_radius = 0.74
			ring.outer_radius = 0.79
			ring.rings = 24
			ring.ring_segments = 4
			_mesh(n, ring, _mat("mycelium"), Vector3(0, 0.03, 0))
			for j in range(8):
				var a := TAU * j / 8.0
				_mesh(n, _sphere(0.14, 16, 6, true), _mat("cap_violet"), Vector3(cos(a) * 0.82, 0.05, sin(a) * 0.82), Vector3.ONE * 0.45)
		"pool":
			var water := MeshInstance3D.new()
			var plane := PlaneMesh.new()
			plane.size = Vector2(2, 2)
			water.mesh = plane
			var wm := ShaderMaterial.new()
			wm.shader = load("res://shaders/spike/water_3d.gdshader")
			water.material_override = wm
			water.scale = Vector3(1.15, 1, 0.9)
			water.position.y = 0.012
			water.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
			n.add_child(water)
			for j in range(7):
				var a := TAU * j / 7.0 + 0.3
				_mesh(n, _sphere(0.36), _mat("stone"), Vector3(cos(a) * 1.2, 0.05, sin(a) * 0.98), Vector3(0.5, 0.32, 0.42))
	return n


func _make_blob(pos: Vector3, radius: float) -> MeshInstance3D:
	if not _mats.has("blob"):
		var grad := Gradient.new()
		grad.set_color(0, Color(0, 0, 0.05, 0.5))
		grad.set_color(1, Color(0, 0, 0.05, 0.0))
		var gt := GradientTexture2D.new()
		gt.gradient = grad
		gt.fill = GradientTexture2D.FILL_RADIAL
		gt.fill_from = Vector2(0.5, 0.5)
		gt.fill_to = Vector2(0.5, 0.0)
		gt.width = 64
		gt.height = 64
		var m := StandardMaterial3D.new()
		m.albedo_texture = gt
		m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		_mats["blob"] = m
		var q := QuadMesh.new()
		q.size = Vector2(2, 2)
		q.orientation = PlaneMesh.FACE_Y
		_meshes["blob"] = q
	var mi := MeshInstance3D.new()
	mi.mesh = _meshes["blob"]
	mi.material_override = _mats["blob"]
	mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
	mi.position = pos + Vector3(0, 0.006, 0)
	mi.scale = Vector3.ONE * maxf(radius, 0.001)
	mi.visible = radius > 0.0
	return mi


## --- prerender (impostor) props ----------------------------------------------

func _node_aabb(n: Node3D) -> AABB:
	var box := AABB()
	var first := true
	for child in n.get_children():
		if child is MeshInstance3D:
			var mi: MeshInstance3D = child
			var b: AABB = mi.transform * mi.get_aabb()
			box = b if first else box.merge(b)
			first = false
	return box


func bake_impostors() -> void:
	if impostors_ready:
		return
	if DisplayServer.get_name() == "headless":
		# Nothing is drawn headless (frame_post_draw never fires): cards stay
		# empty and only the mode wiring is exercised.
		impostors_ready = true
		return
	for type in PROP_TYPES:
		if type == "pool":
			continue
		var vp := SubViewport.new()
		vp.own_world_3d = true
		vp.transparent_bg = true
		vp.size = Vector2i(IMPOSTOR_SIZE, IMPOSTOR_SIZE)
		vp.render_target_update_mode = SubViewport.UPDATE_ONCE
		add_child(vp)
		var proto := _build_prop(type)
		vp.add_child(proto)
		var we := WorldEnvironment.new()
		var env := _env.duplicate() as Environment
		env.background_mode = Environment.BG_CLEAR_COLOR
		env.fog_enabled = false
		env.glow_enabled = false
		we.environment = env
		vp.add_child(we)
		var light := _sun.duplicate() as DirectionalLight3D
		light.shadow_enabled = true
		vp.add_child(light)
		var box := _node_aabb(proto)
		var cam := Camera3D.new()
		cam.projection = Camera3D.PROJECTION_ORTHOGONAL
		cam.size = box.get_longest_axis_size() * 1.25
		cam.basis = camera_basis()
		cam.position = box.get_center() + cam.basis.z * 10.0
		vp.add_child(cam)
		cam.make_current()
		await RenderingServer.frame_post_draw
		await RenderingServer.frame_post_draw
		var img := vp.get_texture().get_image()
		if img != null and not img.is_empty():
			_impostor_tex[type] = {"tex": ImageTexture.create_from_image(img), "size": cam.size, "center": box.get_center()}
		vp.queue_free()
	impostors_ready = true
	_refresh_impostor_sprites()


func _refresh_impostor_sprites() -> void:
	if not impostors_ready:
		return
	for child in _impostor_root.get_children():
		child.queue_free()
	for spec in _layout:
		var info: Dictionary = _impostor_tex.get(spec["type"], {})
		if info.is_empty():
			if spec["type"] == "pool":
				var pool := _build_prop("pool")
				pool.position = to_world(spec["pos"])
				_impostor_root.add_child(pool)
			continue
		var s := float(spec["s"])
		var spr := Sprite3D.new()
		spr.texture = info["tex"]
		spr.pixel_size = float(info["size"]) / float(IMPOSTOR_SIZE) * s
		spr.shaded = false
		spr.alpha_cut = SpriteBase3D.ALPHA_CUT_DISCARD
		spr.basis = camera_basis()
		# Slide the card towards the camera along the view axis so its lower half
		# is not buried in the ground plane; on screen it stays in place, and the
		# perspective enlargement is compensated for the current camera distance.
		var slide := float(info["size"]) * s * 0.45
		var dist := camera_distance(player.get_radius() if player != null else MassSystem.MIN_RADIUS)
		spr.pixel_size *= maxf(0.2, (dist - slide) / dist)
		spr.position = to_world(spec["pos"]) + (info["center"] as Vector3) * s + spr.basis.z * slide
		spr.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		_impostor_root.add_child(spr)


## --- hero slime ----------------------------------------------------------------

func _build_slime() -> void:
	_slime = Node3D.new()
	_slime.name = "Slime3D"
	add_child(_slime)
	_jelly_mat = ShaderMaterial.new()
	_jelly_mat.shader = load("res://shaders/spike/jelly_3d.gdshader")
	if not _build_slime_model():
		_build_slime_primitive()
	for i in range(GroveStudy.FoodEcho.MAX_ECHOES):
		var fleck := _mesh(_slime, _sphere(0.08, 8, 4), _food_mat(FOOD_SPORE), Vector3.ZERO)
		fleck.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		fleck.visible = false
		_echo_nodes.append(fleck)
	_blob_root.add_child(_make_blob(Vector3.ZERO, 1.0))
	_slime.set_meta("blob", _blob_root.get_child(_blob_root.get_child_count() - 1))


## Blender hero (slime.glb): the body gets the jelly shader; face parts are
## drawn after the translucent body so it never veils them; the core and the
## inner spores stay opaque inside and show through the jelly.
func _build_slime_model() -> bool:
	var model := _asset("slime")
	if model == null:
		return false
	model.name = "Jelly"
	_slime.add_child(model)
	hero_from_model = true
	for mi: MeshInstance3D in model.find_children("*", "MeshInstance3D", true, false):
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		var n := String(mi.name)
		if n == "Body":
			mi.material_override = _jelly_mat
			continue
		var src := mi.get_active_material(0) as StandardMaterial3D
		if src == null:
			continue
		var m := src.duplicate() as StandardMaterial3D
		if n.begins_with("Eye") or n == "Mouth" or n.begins_with("Blush"):
			m.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
			m.render_priority = 11 if n.begins_with("EyeHL") else (9 if n.begins_with("Blush") else 10)
		if n == "Core":
			_core = mi
			_core_mat = m
			mi.set_meta("base_scale", mi.scale)
		if n == "Eye_L" or n == "Eye_R" or n.begins_with("EyeHL"):
			mi.set_meta("base_scale", mi.scale)
			_eyes.append(mi)
		mi.material_override = m
	return true


func _build_slime_primitive() -> void:
	var jelly := MeshInstance3D.new()
	jelly.mesh = _sphere(1.0, 48, 24, true)
	_jelly_mat.set_shader_parameter("model_height", 1.0)
	jelly.material_override = _jelly_mat
	jelly.name = "Jelly"
	_slime.add_child(jelly)

	_core_mat = StandardMaterial3D.new()
	_core_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	_core_mat.albedo_color = Color(0.9, 1.0, 1.0)
	_core = _mesh(_slime, _sphere(0.26, 16, 8), _core_mat, Vector3(0, 0.5, 0.05))
	_core.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF

	# Eyes are drawn after the translucent jelly (transparent pass, higher
	# priority) so the body never veils them: eyes must always read.
	var eye_mat := StandardMaterial3D.new()
	eye_mat.albedo_color = Color(0.09, 0.10, 0.32)
	eye_mat.roughness = 0.15
	eye_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	eye_mat.render_priority = 10
	var hl_mat := StandardMaterial3D.new()
	hl_mat.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
	hl_mat.albedo_color = Color.WHITE
	hl_mat.transparency = BaseMaterial3D.TRANSPARENCY_ALPHA
	hl_mat.render_priority = 11
	for side in [-1.0, 1.0]:
		var eye := Node3D.new()
		_slime.add_child(eye)
		var ball := _mesh(eye, _sphere(0.24, 16, 8), eye_mat, Vector3.ZERO, Vector3(0.85, 1.15, 0.5))
		var hl := _mesh(eye, _sphere(0.075, 8, 4), hl_mat, Vector3(-0.06 * side, 0.1, 0.1))
		ball.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		hl.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		eye.set_meta("side", side)
		_eyes.append(eye)


func _food_mat(kind: int) -> StandardMaterial3D:
	var key := "food%d" % kind
	if not _mats.has(key):
		var m := StandardMaterial3D.new()
		m.shading_mode = BaseMaterial3D.SHADING_MODE_UNSHADED
		m.albedo_color = Color(0.45, 0.95, 1.0) if kind == FOOD_SPORE else Color(0.72, 0.5, 1.0)
		_mats[key] = m
	return _mats[key]


func _build_food() -> void:
	var models := {}
	for kind: int in [FOOD_SPORE, FOOD_MINERAL]:
		var src := _asset("food_spore" if kind == FOOD_SPORE else "food_mineral")
		if src != null:
			models[kind] = _first_mesh(src)
			src.free()
	for i in range(FOOD_COUNT):
		var kind := FOOD_SPORE if i % 3 != 0 else FOOD_MINERAL
		var node := Node3D.new()
		var mi: MeshInstance3D
		if models.has(kind):
			mi = _mesh(node, models[kind], null, Vector3(0, 0.03, 0))
		else:
			var mesh := _sphere(0.07, 12, 6) if kind == FOOD_SPORE else _sphere(0.08, 6, 2)
			mi = _mesh(node, mesh, _food_mat(kind), Vector3(0, 0.1, 0))
		mi.cast_shadow = GeometryInstance3D.SHADOW_CASTING_SETTING_OFF
		add_child(node)
		var f := {"kind": kind, "pos": Vector2.ZERO, "node": node, "phase": float(i) * 1.7}
		food.append(f)
		_place_food(f)


func _process(delta: float) -> void:
	_clock += delta
	_record_frame(delta)
	var frac := Engine.get_physics_interpolation_fraction()
	var pos2d := _prev_pos.lerp(_cur_pos, frac)
	var r_px := player.get_radius()
	var r := r_px * PX_TO_M
	_slime.position = to_world(pos2d)
	var jelly: Node3D = _slime.get_node("Jelly")
	jelly.scale = Vector3.ONE * r if hero_from_model else Vector3(r, r * DOME_HEIGHT, r)

	var vel := player.velocity
	var speed01 := clampf(vel.length() / player.base_move_speed, 0.0, 1.0)
	_stretch = lerpf(_stretch, speed01 * 0.34, 1.0 - exp(-8.0 * delta))
	if vel.length() > 5.0:
		_jelly_mat.set_shader_parameter("stretch_dir", vel.normalized())
	_jelly_mat.set_shader_parameter("stretch", _stretch)
	_gulp = move_toward(_gulp, 0.0, delta * 1.6)
	_jelly_mat.set_shader_parameter("gulp", _gulp)

	var growth := clampf((player.mass - MassSystem.DEFAULT_START_MASS) / 90.0, 0.0, 1.0)
	var core_energy := 1.0 + 0.8 * growth + 0.6 * _gulp
	if hero_from_model:
		_core.scale = (_core.get_meta("base_scale") as Vector3) * (1.0 + 0.25 * _gulp)
		_core_mat.emission_energy_multiplier = 2.0 * core_energy
	else:
		_core.scale = Vector3.ONE * r * (1.0 + 0.25 * _gulp)
		_core.position = Vector3(0, 0.5 * r * DOME_HEIGHT * 0.8, 0.05 * r)
		_core_mat.albedo_color = Color(0.85 * core_energy, core_energy, core_energy)
	_jelly_mat.set_shader_parameter("glow", 0.22 + 0.25 * growth)

	_blink_t -= delta
	var blink := 1.0
	if _blink_t < 0.12:
		blink = 0.12
		if _blink_t < 0.0:
			_blink_t = _rng.randf_range(2.8, 5.2)
	if hero_from_model:
		for eye in _eyes:
			var base: Vector3 = eye.get_meta("base_scale")
			eye.scale = Vector3(base.x, base.y * blink, base.z)
	else:
		var lead := Vector3(vel.x, 0, vel.y).normalized() * _stretch * 0.35 if vel.length() > 5.0 else Vector3.ZERO
		for eye in _eyes:
			var side: float = eye.get_meta("side")
			var d := Vector3(0.34 * side, 0.72, 0.6).normalized()
			eye.position = (Vector3(d.x, d.y * DOME_HEIGHT, d.z) * 1.02 + lead) * r
			eye.scale = Vector3(r, r * blink, r)

	food_echo.advance(delta)
	for i in range(_echo_nodes.size()):
		var fleck := _echo_nodes[i]
		if i >= food_echo.echoes.size():
			fleck.visible = false
			continue
		var echo: Dictionary = food_echo.echoes[i]
		var age: float = echo["age"]
		var phase: float = echo["phase"]
		var fade := smoothstep(0.0, 0.6, age) * (1.0 - smoothstep(10.0, GroveStudy.FoodEcho.LIFETIME, age))
		fleck.visible = fade > 0.02
		fleck.material_override = _food_mat(echo["kind"])
		fleck.position = Vector3(sin(phase + _clock * 0.23) * 0.45, 0.28 + cos(phase + _clock * 0.27) * 0.08, 0.1) * r
		fleck.scale = Vector3.ONE * r * fade

	var blob: MeshInstance3D = _slime.get_meta("blob")
	blob.position = _slime.position + Vector3(0, 0.006, 0)
	blob.scale = Vector3.ONE * r * 1.35

	for f in food:
		var node: Node3D = f["node"]
		node.position.y = 0.02 * sin(_clock * 2.0 + float(f["phase"]))

	_camera.position = _slime.position + _camera.basis.z * camera_distance(r_px)
	# Frame by the short screen side so a landscape desktop window shows the
	# same world as a portrait phone instead of zooming in 3-4x.
	var vp_size := get_viewport().get_visible_rect().size
	_camera.keep_aspect = Camera3D.KEEP_WIDTH if vp_size.x <= vp_size.y else Camera3D.KEEP_HEIGHT
	_tick_bench(delta)
	_refresh_hud()


## --- modes ---------------------------------------------------------------------

func set_mode(m: int) -> void:
	mode = clampi(m, 0, Mode.size() - 1)
	_apply_mode()
	if mode == Mode.PRERENDER and not impostors_ready:
		bake_impostors()


func set_density(d: int) -> void:
	density = maxi(1, d)
	_rebuild_props()
	_slime.set_meta("blob", _make_blob(Vector3.ZERO, 1.0))
	_blob_root.add_child(_slime.get_meta("blob"))
	_apply_mode()


func set_bloom(on: bool) -> void:
	bloom = on
	_apply_mode()


func _apply_mode() -> void:
	_sun.shadow_enabled = mode == Mode.FULL_3D
	_env.glow_enabled = bloom
	_props_root.visible = mode != Mode.PRERENDER
	_impostor_root.visible = mode == Mode.PRERENDER
	for child in _blob_root.get_children():
		var mi := child as MeshInstance3D
		if mi != null and mi != _slime_blob():
			mi.visible = mode != Mode.FULL_3D and mi.scale.x > 0.002
	var shading := BaseMaterial3D.SHADING_MODE_PER_PIXEL if mode == Mode.FULL_3D else BaseMaterial3D.SHADING_MODE_PER_VERTEX
	for key in ["stone", "moss", "fern", "leaf", "bark", "stem", "cap_violet", "cap_cyan"]:
		if _mats.has(key):
			(_mats[key] as StandardMaterial3D).shading_mode = shading
	_ground_mat.set_shader_parameter("vein_strength", 0.0)
	if _mode_btn != null:
		_mode_btn.text = "Режим: " + MODE_NAMES[mode]
		_density_btn.text = "Объекты ×%d" % density
		_bloom_btn.text = "Свечение: " + ("вкл" if bloom else "выкл")


func _slime_blob() -> MeshInstance3D:
	return _slime.get_meta("blob") if _slime != null and _slime.has_meta("blob") else null


## --- measurement -----------------------------------------------------------------

func _record_frame(delta: float) -> void:
	var rid := get_viewport().get_viewport_rid()
	_push(_frame_ms, delta * 1000.0)
	_push(_gpu_ms, RenderingServer.viewport_get_measured_render_time_gpu(rid))
	_push(_cpu_ms, RenderingServer.viewport_get_measured_render_time_cpu(rid) + Performance.get_monitor(Performance.TIME_PROCESS) * 1000.0)


func _push(arr: PackedFloat32Array, v: float) -> void:
	arr.append(v)
	if arr.size() > 240:
		arr.remove_at(0)


func _stats(arr: PackedFloat32Array) -> Dictionary:
	var sum := 0.0
	var mx := 0.0
	for v in arr:
		sum += v
		mx = maxf(mx, v)
	var avg := sum / maxf(1.0, float(arr.size()))
	return {"avg": avg, "p95": percentile(arr, 0.95), "p99": percentile(arr, 0.99), "max": mx}


func _render_info() -> Dictionary:
	return {
		"draw_calls": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_DRAW_CALLS_IN_FRAME),
		"primitives": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_TOTAL_PRIMITIVES_IN_FRAME),
		"vmem_mb": RenderingServer.get_rendering_info(RenderingServer.RENDERING_INFO_VIDEO_MEM_USED) / 1048576.0,
	}


func _refresh_hud() -> void:
	if _hud == null or Engine.get_process_frames() % 10 != 0:
		return
	var f := _stats(_frame_ms)
	var g := _stats(_gpu_ms)
	var info := _render_info()
	var lines := [
		"%s · объекты ×%d (%d) · свечение %s" % [MODE_NAMES[mode], density, prop_count(), "вкл" if bloom else "выкл"],
		"FPS %.0f · кадр %.1f мс (p95 %.1f, max %.1f)" % [1000.0 / maxf(0.01, f["avg"]), f["avg"], f["p95"], f["max"]],
		"GPU %.2f мс (p95 %.2f) · draw calls %d · tris %dk" % [g["avg"], g["p95"], info["draw_calls"], int(info["primitives"]) / 1000],
		"VRAM %.0f МБ · RAM %.0f МБ · масса %.1f" % [info["vmem_mb"], OS.get_static_memory_usage() / 1048576.0, player.mass],
	]
	if _bench_index >= 0:
		lines.append("Бенч %d/%d …" % [_bench_index + 1, BENCH_PLAN.size()])
	_hud.text = "\n".join(lines)


func start_bench() -> void:
	if _bench_index >= 0:
		return
	if not impostors_ready:
		await bake_impostors()
	auto_steer = true
	_bench_index = 0
	_begin_bench_step()
	var f := FileAccess.open(RESULTS_PATH, FileAccess.WRITE)
	if f != null:
		f.store_line("renderer,device,mode,density,props,fps_avg,frame_ms_avg,frame_ms_p95,frame_ms_p99,frame_ms_max,gpu_ms_avg,gpu_ms_p95,cpu_ms_avg,draw_calls,primitives,vmem_mb,static_mem_mb")
		f.close()


func _begin_bench_step() -> void:
	var step := BENCH_PLAN[_bench_index]
	if density != step.y:
		set_density(step.y)
	set_mode(step.x)
	_bench_clock = 0.0
	_bench_samples = {"frame": PackedFloat32Array(), "gpu": PackedFloat32Array(), "cpu": PackedFloat32Array(), "dc": 0.0, "prim": 0.0, "n": 0}


func _tick_bench(delta: float) -> void:
	if _bench_index < 0:
		return
	_bench_clock += delta
	if _bench_clock < BENCH_WARMUP:
		return
	# Packed arrays are values: append to a local copy and store it back.
	for key: String in ["frame", "gpu", "cpu"]:
		var arr: PackedFloat32Array = _bench_samples[key]
		match key:
			"frame": arr.append(delta * 1000.0)
			"gpu": arr.append(_gpu_ms[_gpu_ms.size() - 1])
			"cpu": arr.append(_cpu_ms[_cpu_ms.size() - 1])
		_bench_samples[key] = arr
	var info := _render_info()
	_bench_samples["dc"] = float(_bench_samples["dc"]) + float(info["draw_calls"])
	_bench_samples["prim"] = float(_bench_samples["prim"]) + float(info["primitives"])
	_bench_samples["n"] = int(_bench_samples["n"]) + 1
	if _bench_clock < BENCH_WARMUP + BENCH_MEASURE:
		return
	_finish_bench_step()


func _finish_bench_step() -> void:
	var step := BENCH_PLAN[_bench_index]
	var fr := _stats(_bench_samples["frame"])
	var gp := _stats(_bench_samples["gpu"])
	var cp := _stats(_bench_samples["cpu"])
	var n := maxf(1.0, float(_bench_samples["n"]))
	var info := _render_info()
	var row := "%s,%s,%s,%d,%d,%.1f,%.2f,%.2f,%.2f,%.2f,%.3f,%.3f,%.3f,%.0f,%.0f,%.1f,%.1f" % [
		RenderingServer.get_current_rendering_method(), OS.get_model_name().replace(",", " "), MODE_NAMES[step.x], step.y, prop_count(),
		1000.0 / maxf(0.01, fr["avg"]), fr["avg"], fr["p95"], fr["p99"], fr["max"],
		gp["avg"], gp["p95"], cp["avg"], float(_bench_samples["dc"]) / n, float(_bench_samples["prim"]) / n,
		info["vmem_mb"], OS.get_static_memory_usage() / 1048576.0]
	print("SPIKE_RESULT ", row)
	var f := FileAccess.open(RESULTS_PATH, FileAccess.READ_WRITE)
	if f != null:
		f.seek_end()
		f.store_line(row)
		f.close()
	_bench_index += 1
	if _bench_index >= BENCH_PLAN.size():
		_bench_index = -1
		auto_steer = false
		print("SPIKE_BENCH_DONE ", ProjectSettings.globalize_path(RESULTS_PATH))
		if OS.get_cmdline_user_args().has("--spike-quit"):
			quit_cleanly()
		return
	_begin_bench_step()


## --- UI ---------------------------------------------------------------------------

func _build_hud() -> void:
	var layer := CanvasLayer.new()
	add_child(layer)
	var panel := PanelContainer.new()
	var style := StyleBoxFlat.new()
	style.bg_color = Color(0.05, 0.06, 0.14, 0.6)
	style.set_content_margin_all(10)
	style.set_corner_radius_all(10)
	panel.add_theme_stylebox_override("panel", style)
	panel.position = Vector2(12, 12)
	layer.add_child(panel)
	_hud = Label.new()
	_hud.add_theme_font_size_override("font_size", 18)
	panel.add_child(_hud)

	var bar := HBoxContainer.new()
	bar.anchor_left = 0.0
	bar.anchor_right = 1.0
	bar.anchor_top = 1.0
	bar.anchor_bottom = 1.0
	bar.offset_top = -96
	bar.offset_bottom = -16
	bar.offset_left = 12
	bar.offset_right = -12
	bar.alignment = BoxContainer.ALIGNMENT_CENTER
	bar.add_theme_constant_override("separation", 8)
	layer.add_child(bar)
	_mode_btn = _button(bar, func() -> void: set_mode((mode + 1) % Mode.size()))
	_density_btn = _button(bar, func() -> void: set_density(3 if density == 1 else 1))
	_bloom_btn = _button(bar, func() -> void: set_bloom(not bloom))
	_bench_btn = _button(bar, start_bench)
	_bench_btn.text = "Бенч"
	_apply_mode()


func _button(parent: Control, cb: Callable) -> Button:
	var b := Button.new()
	b.custom_minimum_size = Vector2(160, 72)
	b.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	b.add_theme_font_size_override("font_size", 20)
	b.focus_mode = Control.FOCUS_NONE
	b.pressed.connect(cb)
	parent.add_child(b)
	return b


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touching = event.pressed
		_touch_screen = event.position
	elif event is InputEventScreenDrag:
		_touch_screen = event.position
