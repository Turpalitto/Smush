class_name ClaudeVisualLab
extends Node2D
## CLAUDE VISUAL CHALLENGE V8 — isolated lab for the "Lunar Jelly" Stage 8 slime.
##
## Run:  godot --path . res://scenes/labs/ClaudeVisualLab.tscn
## Never touches the run loop, the save, ads or analytics: subjects are bare Node2D
## hosts for a SlimeVisual, prey are lab-only critters, mass is fixed unless you move
## the stage slider (so every comparison uses the same mass, camera, floor and light).
##
## Interactive: bottom panel (style / quality / stage / events / three mutations /
## Showcase). Keyboard: 1 old · 2 claude · 3 glm-organic · 4 compare old|claude ·
## SPACE absorb · X hurt · E evolve · V showcase · A kick · B brake · P freeze.
##
## Automation (env, used by tools/claude_capture.sh):
##   CL_SHOT=<png>       capture a frame and quit
##   CL_STYLE=old|claude|glm|compare     (default claude)
##   CL_SCENE=idle|motion|absorb|tentacles|shield|electro|hurt|evolve|showcase
##   CL_AT=<sec>         capture when the scenario clock reaches this time
##   CL_AFTER=<event>:<sec>   capture <sec> after absorb|impact|discharge|hurt|evolve
##   CL_QUALITY=0|1|2    CL_STAGE=1..15 (default 8)   CL_UI=0|1 (default 0 when CL_SHOT)
##   CL_SIZE=WxH         CL_QUIT_AT=<sec> quit after that scenario time (movie mode)
##   CL_PERF=1           frame-time grid over style x quality, then quit
##   CL_GROVE=moss|amber|dusk  opt-in calm-world art study (baseline by default)
##   CL_FOOD=0|1|2        light / spores / minerals; CL_SCENE=food for a feed demo
##   Determinism: run with --fixed-fps 60 so the scenario clock advances 1/60 per frame.

enum Style { OLD, CLAUDE, GLM, COMPARE }

const ZOOM_GAME_AT_STAGE := 0.95   # ArenaController: lerp(1.04, 0.80, (mass-10)/110) at mass 52
const SUBJECT_GAP := 128.0
const KICK_RESPONSE := 7.0
const FLOOR_PATH := "res://resources/art/environment/forest_floor.png"

class Subject extends RefCounted:
	var root: Node2D
	var visual: SlimeVisual
	var prey: Node2D
	var style: int = 0
	var vel: Vector2 = Vector2.ZERO
	var target_vel: Vector2 = Vector2.ZERO
	var shield_ready: bool = true
	var shield_timer: float = -1.0
	var electro_cd: float = 2.0
	var tendril_tick: float = 0.0
	var label: String = ""
	var food_echo: GroveStudy.FoodEcho

var style: int = Style.CLAUDE
var quality: int = 2
var stage_t: float = 8.0
var mass: float = 52.0
var mut_level: int = 3
var mutations_on: Dictionary = {}

var subjects: Array[Subject] = []
var cam_pos: Vector2 = Vector2.ZERO
var zoom: float = ZOOM_GAME_AT_STAGE
var sim_t: float = 0.0
var frozen: bool = false
var showcase_on: bool = false
var showcase_t: float = 0.0
var showcase_idx: int = 0
var autopilot: bool = false

var last_event_t: Dictionary = {"absorb": -99.0, "impact": -99.0, "discharge": -99.0, "hurt": -99.0, "evolve": -99.0}

var _floor_tex: Texture2D
var _floor_node: Node2D
var _ui_root: Control
var _info: Label
var _fps_smooth: float = 60.0
var _info_tick: float = 0.0
var _scene_events: Array[Dictionary] = []
var _scene_idx: int = 0
var _scene_t: float = 0.0
var _capture_path: String = ""
var _capture_at: float = -1.0
var _capture_after: String = ""
var _capture_after_t: float = 0.0
var _quit_at: float = -1.0
var _captured: bool = false

var _style_opt: OptionButton
var _quality_opt: OptionButton
var _stage_slider: HSlider
var _stage_lbl: Label
var _mut_checks: Dictionary = {}
var _grove: GroveStudy
var _food_kind: int = 0
var _grove_choice: OptionButton


func _ready() -> void:
	seed(20261025)
	RenderingServer.set_default_clear_color(Color("#0d1714"))
	_floor_tex = AssetRegistry.get_texture(FLOOR_PATH)
	_floor_node = Node2D.new()
	_floor_node.name = "Floor"
	_floor_node.draw.connect(_draw_floor)
	add_child(_floor_node)
	_grove = GroveStudy.new()
	add_child(_grove)
	_set_grove(-1)

	var headless_cap := not OS.get_environment("CL_SHOT").is_empty() or not OS.get_environment("CL_PERF").is_empty() or not OS.get_environment("CL_QUIT_AT").is_empty()
	var ui_env := OS.get_environment("CL_UI")
	var show_ui := (ui_env == "1") or (ui_env.is_empty() and not headless_cap)
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	add_child(layer)
	_ui_root = _build_ui()
	layer.add_child(_ui_root)
	_ui_root.visible = show_ui

	_apply_env_early()
	_rebuild_subjects()
	_apply_env_late()


func _exit_tree() -> void:
	Engine.time_scale = 1.0


## --- subjects -----------------------------------------------------------------------

func _rebuild_subjects() -> void:
	for s in subjects:
		if s.root != null and is_instance_valid(s.root):
			s.root.free()
	subjects.clear()
	var styles: Array[int] = []
	match style:
		Style.COMPARE:
			styles = [Style.OLD, Style.CLAUDE]
		_:
			styles = [style]
	var n := styles.size()
	for i in range(n):
		var sub := Subject.new()
		sub.style = styles[i]
		sub.root = Node2D.new()
		sub.root.name = "Subject%d" % i
		sub.root.position = Vector2((float(i) - (float(n) - 1.0) * 0.5) * SUBJECT_GAP * 2.0, 0.0)
		add_child(sub.root)
		sub.prey = Node2D.new()
		sub.prey.name = "Prey"
		add_child(sub.prey)
		match sub.style:
			Style.OLD:
				sub.visual = SlimeVisual.new()
				sub.label = "OLD"
			Style.GLM:
				sub.visual = SlimeVisualOrganic.new()
				sub.label = "GLM"
			_:
				sub.visual = SlimeVisualClaude.new()
				sub.label = "CLAUDE"
		sub.visual.name = "SlimeVisual"
		sub.root.add_child(sub.visual)
		if sub.visual is SlimeVisualClaude:
			sub.food_echo = GroveStudy.FoodEcho.new()
			sub.food_echo.visual = sub.visual as SlimeVisualClaude
			sub.visual.add_child(sub.food_echo)
			sub.visual.move_child(sub.food_echo, (sub.visual as SlimeVisualClaude)._eyes_rect.get_index())
		subjects.append(sub)
	for s in subjects:
		_configure_subject(s)
	cam_pos = _anchor()
	_update_camera(1.0)


func _configure_subject(s: Subject) -> void:
	var v := s.visual
	v.radius = MassSystem.radius_from_mass(mass)
	v.set_growth(mass)
	v.mutation_levels = mutations_on.duplicate()
	# Same state for every style: eyes open on the first frame, same blink phase.
	v._blink_timer = 3.4
	if v is SlimeVisualClaude:
		(v as SlimeVisualClaude).set_quality(quality)
	elif v is SlimeVisualOrganic:
		(v as SlimeVisualOrganic).set_quality(quality)


func _anchor() -> Vector2:
	if subjects.is_empty():
		return Vector2.ZERO
	var sum := Vector2.ZERO
	for s in subjects:
		sum += s.root.position
	return sum / float(subjects.size())


func _update_camera(weight: float) -> void:
	cam_pos = cam_pos.lerp(_anchor(), weight)
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var z := zoom
	var xf := Transform2D(0.0, Vector2(z, z), 0.0, Vector2.ZERO)
	xf.origin = size * 0.5 - cam_pos * z
	vp.canvas_transform = xf


func set_mass_from_stage(t: float) -> void:
	stage_t = t
	var keys := EvolutionStages.MASS_KEYS
	var tt := clampf(t, 1.0, float(EvolutionStages.COUNT))
	if tt >= float(EvolutionStages.COUNT):
		mass = keys[EvolutionStages.COUNT - 1]
	else:
		var i := int(floorf(tt)) - 1
		mass = lerpf(keys[i], keys[i + 1], tt - floorf(tt))
	# The game zooms out with mass; keep the lab honest about it. CL_ZOOM_MUL is only
	# for detail crops (equivalent to a denser screen, since the shaders are resolution
	# independent); every comparison frame uses the game zoom.
	zoom = lerpf(1.04, 0.80, clampf((mass - 10.0) / 110.0, 0.0, 1.0))
	var zm := OS.get_environment("CL_ZOOM_MUL")
	if not zm.is_empty():
		zoom *= float(zm)
	for s in subjects:
		s.visual.radius = MassSystem.radius_from_mass(mass)
		s.visual.set_growth(mass)


## --- frame loop -----------------------------------------------------------------------

func _process(delta: float) -> void:
	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)
	if frozen:
		_update_camera(1.0)
		return
	sim_t += delta
	_tick_script(delta)
	for s in subjects:
		_tick_subject(s, delta)
	_update_camera(1.0 - exp(-6.0 * delta))
	_floor_node.queue_redraw()
	if _grove.visible:
		_grove.update_view(cam_pos, zoom, EvolutionStages.env_for_mass(mass), sim_t)
	_check_capture()

	_info_tick += delta
	if _info_tick > 0.25 and _info != null:
		_info_tick = 0.0
		_refresh_info()


func _tick_subject(s: Subject, delta: float) -> void:
	var v := s.visual
	if s.food_echo != null:
		s.food_echo.advance(delta)
	s.vel = s.vel.lerp(s.target_vel, 1.0 - exp(-KICK_RESPONSE * delta))
	if s.target_vel == Vector2.ZERO and s.vel.length() < 3.0:
		s.vel = Vector2.ZERO
	s.root.position += s.vel * delta
	v.velocity_vec = s.vel
	if s.vel.length() > 12.0:
		v.look_dir = s.vel.normalized()
	v.is_dashing = false

	# Shield: ready state is the game's own concept (PlayerSlime.shield_ready).
	if mutations_on.has("shield"):
		if s.shield_timer >= 0.0:
			s.shield_timer -= delta
			if s.shield_timer <= 0.0:
				s.shield_timer = -1.0
				s.shield_ready = true
		v.shield_active = s.shield_ready
	else:
		v.shield_active = false

	# ranged_absorb: pick prey in reach and reel them, mirroring PlayerSlime.
	if mutations_on.has("ranged_absorb"):
		s.tendril_tick -= delta
		if s.tendril_tick <= 0.0:
			s.tendril_tick = 0.10
			var reach := 155.0 + 28.0 * float(int(mutations_on["ranged_absorb"]) - 1)
			var pts: Array[Vector2] = []
			for p in s.prey.get_children():
				var pr := p as LabPrey
				if pr == null:
					continue
				if pr.state == LabPrey.PState.SWIM and not pr.is_target_dummy:
					if pr.global_position.distance_to(s.root.global_position) <= reach:
						pr.state = LabPrey.PState.REEL
				if pr.state == LabPrey.PState.REEL:
					pts.append(pr.global_position)
			v.active_tendril_targets = pts
	elif not v.active_tendril_targets.is_empty():
		v.active_tendril_targets = []

	# electro_discharge: charge in the body, fire on the mutation's own cadence.
	if mutations_on.has("electro_discharge") and (autopilot or showcase_on or not OS.get_environment("CL_SHOT").is_empty() or true):
		s.electro_cd -= delta
		if s.electro_cd <= 0.0 and _auto_electro:
			s.electro_cd = maxf(1.1, 3.4 - 0.32 * float(int(mutations_on["electro_discharge"]) - 1))
			fire_electro(s)


var _auto_electro: bool = false


func fire_electro(s: Subject) -> void:
	var targets: Array[Vector2] = []
	for p in s.prey.get_children():
		var pr := p as LabPrey
		if pr != null and pr.state != LabPrey.PState.DONE:
			var rel := pr.global_position - s.root.global_position
			if rel.length() < 330.0:
				targets.append(rel)
		if targets.size() >= 3:
			break
	if s.visual is SlimeVisualClaude:
		(s.visual as SlimeVisualClaude).trigger_electro_discharge(targets)
	last_event_t["discharge"] = sim_t
	for p in s.prey.get_children():
		var pr2 := p as LabPrey
		if pr2 != null:
			pr2.flinch()


func spawn_prey(s: Subject, offset: Vector2, mode: int, col: Color = Color(1.0, 0.55, 0.62), px: float = 9.0, dummy: bool = false) -> LabPrey:
	var pr := LabPrey.new()
	pr.lab = self
	pr.subject = s
	pr.body_color = col
	pr.radius_px = px
	pr.state = mode
	pr.is_target_dummy = dummy
	pr.global_position = s.root.global_position + offset
	s.prey.add_child(pr)
	return pr


func prey_absorbed(pr: LabPrey) -> void:
	var s := pr.subject
	var entry := pr.global_position - s.root.global_position
	if s.visual is SlimeVisualClaude:
		(s.visual as SlimeVisualClaude).trigger_swallow(entry, pr.body_color, pr.radius_px * 0.8)
	elif s.visual is SlimeVisualOrganic:
		(s.visual as SlimeVisualOrganic).trigger_swallow(entry, pr.body_color, pr.radius_px * 0.8)
	else:
		s.visual.trigger_gulp()
	last_event_t["absorb"] = sim_t
	if pr.food_kind >= 0 and s.food_echo != null:
		s.food_echo.remember(pr.food_kind)


## --- demo actions (shared by UI, keys and scripted scenes) ------------------------------

func act_absorb(big: bool = false) -> void:
	for s in subjects:
		var side := 1.0 if (randi() % 2 == 0) else -1.0
		var r := s.visual.radius
		var col := Color(1.0, 0.55, 0.62) if not big else Color(0.98, 0.82, 0.40)
		spawn_prey(s, Vector2(side * (r + 62.0), randf_range(-24.0, 24.0)), LabPrey.PState.HOME, col, 14.0 if big else 9.0)


func act_feed(kind: int) -> void:
	for s in subjects:
		var pr := spawn_prey(s, Vector2(s.visual.radius + 62.0, 18.0), LabPrey.PState.HOME,
			GroveStudy.FOOD_COLORS[kind], 8.0)
		pr.food_kind = kind


func _set_grove(index: int) -> void:
	_grove.visible = index >= 0
	_grove._layer.visible = index >= 0
	_floor_node.visible = index < 0
	if _grove_choice != null:
		_grove_choice.select(index + 1)
	if index >= 0:
		_grove.set_mood(index)


func act_hurt() -> void:
	for s in subjects:
		var dir := Vector2(1.0, 0.45).normalized()
		if mutations_on.has("shield") and s.shield_ready:
			if s.visual is SlimeVisualClaude:
				(s.visual as SlimeVisualClaude).trigger_shield_impact(dir)
			last_event_t["impact"] = sim_t
			s.shield_timer = -1.0
			# the game consumes the shield on a block; it re-forms after a pause
			get_tree().create_timer(0.55).timeout.connect(func() -> void:
				s.shield_ready = false
				s.shield_timer = 1.8)
		else:
			s.visual.trigger_hurt()
			last_event_t["hurt"] = sim_t


func act_evolve() -> void:
	for s in subjects:
		s.visual.trigger_evolution()
	last_event_t["evolve"] = sim_t


func act_kick(v: Vector2) -> void:
	for s in subjects:
		s.target_vel = v


func act_dummies() -> void:
	for s in subjects:
		spawn_prey(s, Vector2(165.0, -55.0), LabPrey.PState.SWIM, Color(0.62, 0.86, 1.0), 11.0, true)
		spawn_prey(s, Vector2(-150.0, 38.0), LabPrey.PState.SWIM, Color(0.62, 0.86, 1.0), 11.0, true)


func set_mutation(id: String, on: bool) -> void:
	if on:
		mutations_on[id] = mut_level
	else:
		mutations_on.erase(id)
	for s in subjects:
		s.visual.mutation_levels = mutations_on.duplicate()
		if id == "shield" and on:
			s.shield_ready = true
			s.shield_timer = -1.0
	if id == "electro_discharge":
		_auto_electro = on


func clear_prey() -> void:
	for s in subjects:
		if s.food_echo != null:
			s.food_echo.echoes.clear()
		for p in s.prey.get_children():
			p.queue_free()


## --- scripted scenes ---------------------------------------------------------------------

func _tick_script(delta: float) -> void:
	if showcase_on:
		showcase_t += delta
		while showcase_idx < SHOWCASE.size() and showcase_t >= float(SHOWCASE[showcase_idx]["t"]):
			_run_event(SHOWCASE[showcase_idx])
			showcase_idx += 1
		if showcase_idx >= SHOWCASE.size() and showcase_t > float(SHOWCASE[SHOWCASE.size() - 1]["t"]) + 2.0:
			showcase_on = false
	_scene_t += delta
	while _scene_idx < _scene_events.size() and _scene_t >= float(_scene_events[_scene_idx]["t"]):
		_run_event(_scene_events[_scene_idx])
		_scene_idx += 1


func _run_event(e: Dictionary) -> void:
	match str(e["do"]):
		"vel":
			act_kick(e["v"] as Vector2)
		"absorb":
			act_absorb(bool(e.get("big", false)))
		"food":
			act_feed(_food_kind)
		"hurt":
			act_hurt()
		"evolve":
			act_evolve()
		"mut_on":
			set_mutation(str(e["id"]), true)
		"mut_off":
			set_mutation(str(e["id"]), false)
		"dummies":
			act_dummies()
		"dash_start":
			for s in subjects:
				s.visual.is_dashing = true
		"prey_near":
			for s in subjects:
				spawn_prey(s, e["at"] as Vector2, LabPrey.PState.SWIM, Color(1.0, 0.55, 0.62), 10.0)
		"electro":
			for s in subjects:
				fire_electro(s)
		"clear":
			clear_prey()
		"shield_rearm":
			for s in subjects:
				s.shield_ready = true
				s.shield_timer = -1.0


## Showcase: ~20 s of every behaviour the brief asks for, in a fixed order.
const SHOWCASE: Array[Dictionary] = [
	{"t": 0.0, "do": "vel", "v": Vector2.ZERO},
	{"t": 2.2, "do": "vel", "v": Vector2(300, 0)},
	{"t": 3.6, "do": "vel", "v": Vector2.ZERO},
	{"t": 4.6, "do": "vel", "v": Vector2(0, -280)},
	{"t": 5.5, "do": "vel", "v": Vector2(-270, 40)},
	{"t": 6.6, "do": "vel", "v": Vector2.ZERO},
	{"t": 7.4, "do": "absorb"},
	{"t": 9.2, "do": "absorb", "big": true},
	{"t": 11.0, "do": "hurt"},
	{"t": 12.2, "do": "evolve"},
	{"t": 13.8, "do": "mut_on", "id": "shield"},
	{"t": 15.0, "do": "hurt"},
	{"t": 17.4, "do": "mut_off", "id": "shield"},
	{"t": 17.5, "do": "mut_on", "id": "ranged_absorb"},
	{"t": 17.8, "do": "prey_near", "at": Vector2(175, -40)},
	{"t": 18.0, "do": "prey_near", "at": Vector2(-150, 70)},
	{"t": 21.0, "do": "mut_off", "id": "ranged_absorb"},
	{"t": 21.1, "do": "clear"},
	{"t": 21.2, "do": "mut_on", "id": "electro_discharge"},
	{"t": 21.3, "do": "dummies"},
	{"t": 22.4, "do": "electro"},
	{"t": 24.6, "do": "electro"},
	{"t": 26.5, "do": "mut_off", "id": "electro_discharge"},
]


func start_showcase() -> void:
	clear_prey()
	for k in mutations_on.keys():
		set_mutation(str(k), false)
	showcase_t = 0.0
	showcase_idx = 0
	showcase_on = true


func _scene_script(name: String) -> Array[Dictionary]:
	var ev: Array[Dictionary] = []
	match name:
		"food":
			ev = [{"t": 0.2, "do": "food"}, {"t": 1.8, "do": "food"}, {"t": 3.4, "do": "food"}]
		"motion":
			ev = [{"t": 0.3, "do": "vel", "v": Vector2(330, 0)}]
		"absorb":
			ev = [{"t": 0.2, "do": "absorb"}]
		"tentacles":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "ranged_absorb"},
				{"t": 0.1, "do": "prey_near", "at": Vector2(160, -50)},
				{"t": 0.1, "do": "prey_near", "at": Vector2(-140, 60)},
			]
		"shield":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "shield"},
				{"t": 1.4, "do": "hurt"},
			]
		"electro":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "electro_discharge"},
				{"t": 0.0, "do": "dummies"},
				{"t": 1.2, "do": "electro"},
			]
		"hurt":
			ev = [{"t": 0.8, "do": "hurt"}]
		"evolve":
			ev = [{"t": 0.8, "do": "evolve"}]
		"spikes":
			ev = [{"t": 0.0, "do": "mut_on", "id": "spikes"}]
		"dash":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "dash"},
				{"t": 0.5, "do": "dash_start"},
				{"t": 0.5, "do": "vel", "v": Vector2(400, 0)},
			]
		"regeneration":
			ev = [{"t": 0.0, "do": "mut_on", "id": "regeneration"}]
		"poison_trail":
			ev = [{"t": 0.0, "do": "mut_on", "id": "poison_trail"}]
		"split":
			ev = [{"t": 0.0, "do": "mut_on", "id": "split"}]
		"freeze":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "freeze"},
				{"t": 0.1, "do": "dummies"},
			]
		"mimicry":
			ev = [{"t": 0.0, "do": "mut_on", "id": "mimicry"}]
		"magnet":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "magnet"},
				{"t": 0.1, "do": "dummies"},
			]
		"speed_boost":
			ev = [
				{"t": 0.0, "do": "mut_on", "id": "speed_boost"},
				{"t": 0.5, "do": "vel", "v": Vector2(300, 0)},
			]
	return ev


## --- capture / automation ---------------------------------------------------------------

func _apply_env_early() -> void:
	var st := OS.get_environment("CL_STYLE")
	if not st.is_empty():
		style = {"old": Style.OLD, "claude": Style.CLAUDE, "glm": Style.GLM, "compare": Style.COMPARE}.get(st, Style.CLAUDE)
		if _style_opt != null:
			_style_opt.select(style)
	var q := OS.get_environment("CL_QUALITY")
	if not q.is_empty():
		quality = clampi(int(q), 0, 2)
		_quality_opt.select(quality)
	var sg := OS.get_environment("CL_STAGE")
	if not sg.is_empty():
		stage_t = float(sg)
	var sz := OS.get_environment("CL_SIZE")
	if not sz.is_empty():
		var parts := sz.split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))
	set_mass_from_stage(stage_t)
	var ml := OS.get_environment("CL_MLEVEL")
	if not ml.is_empty():
		mut_level = clampi(int(ml), 1, 5)


func _apply_env_late() -> void:
	var grove_id := OS.get_environment("CL_GROVE")
	if grove_id in ["moss", "amber", "dusk"]:
		_set_grove(["moss", "amber", "dusk"].find(grove_id))
	_food_kind = clampi(int(OS.get_environment("CL_FOOD")), 0, 2)
	set_mass_from_stage(stage_t)
	_stage_slider.set_value_no_signal(stage_t)
	_stage_lbl.text = "%.1f" % stage_t
	_capture_path = OS.get_environment("CL_SHOT")
	var at := OS.get_environment("CL_AT")
	if not at.is_empty():
		_capture_at = float(at)
	var after := OS.get_environment("CL_AFTER")
	if not after.is_empty():
		var p := after.split(":")
		_capture_after = p[0]
		_capture_after_t = float(p[1]) if p.size() > 1 else 0.12
	var qa := OS.get_environment("CL_QUIT_AT")
	if not qa.is_empty():
		_quit_at = float(qa)
	var scene := OS.get_environment("CL_SCENE")
	if scene == "showcase":
		start_showcase()
	elif not scene.is_empty():
		_scene_events = _scene_script(scene)
		_scene_idx = 0
		_scene_t = 0.0
	if not OS.get_environment("CL_PERF").is_empty():
		_run_perf()
	if scene == "electro" or scene == "showcase":
		_auto_electro = false


func _check_capture() -> void:
	if _captured:
		return
	if _quit_at >= 0.0 and sim_t >= _quit_at and _capture_path.is_empty():
		_captured = true
		_finish_capture(0)
		return
	if _capture_path.is_empty() or _captured:
		return
	var due := false
	if not _capture_after.is_empty():
		due = (sim_t - float(last_event_t.get(_capture_after, -99.0))) >= _capture_after_t and float(last_event_t.get(_capture_after, -99.0)) > 0.0
	elif _capture_at >= 0.0:
		due = sim_t >= _capture_at
	else:
		due = sim_t >= 2.0
	if sim_t > 25.0 and not due:
		push_error("CL_SHOT: capture condition never met")
		get_tree().quit(6)
		return
	if not due:
		return
	_captured = true
	# Let this frame finish rendering before reading the viewport.
	await RenderingServer.frame_post_draw
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("CL_SHOT: capture produced no image")
		get_tree().quit(3)
		return
	var err := img.save_png(_capture_path)
	print("CL_SHOT %s %dx%d style=%s stage=%.1f mass=%.1f quality=%d t=%.3f err=%d" % [
		_capture_path, img.get_width(), img.get_height(), str(style), stage_t, mass, quality, sim_t, err])
	_finish_capture(0 if err == OK else 4)


func _finish_capture(code: int) -> void:
	# Allow the audio thread to release active Vorbis streams before standalone exit.
	Audio.set_process(false)
	for child in Audio.get_children():
		if child is AudioStreamPlayer:
			child.stop()
			child.stream = null
	for _i in range(8):
		await get_tree().process_frame
	get_tree().quit(code)


func _run_perf() -> void:
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	print("CL_PERF BEGIN (desktop CPU frame time incl. GPU sync, vsync off; NOT an Android measurement)")
	for sty in [Style.OLD, Style.CLAUDE, Style.GLM]:
		for q in range(3):
			style = sty
			quality = q
			_rebuild_subjects()
			set_mutation("shield", true)
			set_mutation("ranged_absorb", true)
			set_mutation("electro_discharge", true)
			_auto_electro = true
			act_dummies()
			start_showcase()
			for _w in range(40):
				await get_tree().process_frame
			var samples: Array[float] = []
			for _f in range(240):
				var t0 := Time.get_ticks_usec()
				await get_tree().process_frame
				samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
			samples.sort()
			var sum := 0.0
			for x in samples:
				sum += x
			print("CL_PERF style=%s quality=%d frames=%d avg_ms=%.3f p50_ms=%.3f p95_ms=%.3f max_ms=%.3f" % [
				["old", "claude", "glm", "compare"][sty], q, samples.size(), sum / float(samples.size()),
				samples[samples.size() / 2], samples[int(float(samples.size()) * 0.95)], samples[samples.size() - 1]])
			showcase_on = false
			clear_prey()
	print("CL_PERF END")
	get_tree().quit(0)


## --- floor ------------------------------------------------------------------------------------

func _draw_floor() -> void:
	var vp := get_viewport()
	var size := vp.get_visible_rect().size
	var inv := vp.canvas_transform.affine_inverse()
	var top_left := inv * Vector2.ZERO
	var bottom_right := inv * size
	if _floor_tex == null:
		_floor_node.draw_rect(Rect2(top_left, bottom_right - top_left), Color(0.07, 0.12, 0.10))
		return
	var tile := 1024.0
	var x0 := floorf(top_left.x / tile) * tile
	var y0 := floorf(top_left.y / tile) * tile
	var tint := Color(0.50, 0.68, 0.58, 1.0)
	var y := y0
	while y < bottom_right.y:
		var x := x0
		while x < bottom_right.x:
			_floor_node.draw_texture_rect(_floor_tex, Rect2(x, y, tile, tile), false, tint)
			x += tile
		y += tile


## --- UI -----------------------------------------------------------------------------------------

func _build_ui() -> Control:
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIThemeBuilder.build_theme()

	_info = Label.new()
	_info.position = Vector2(14, 10)
	_info.add_theme_font_size_override("font_size", 20)
	root.add_child(_info)

	var panel := PanelContainer.new()
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_top = 0.60
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)
	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	var row1 := HBoxContainer.new()
	_style_opt = OptionButton.new()
	_style_opt.add_item("Исходный", Style.OLD)
	_style_opt.add_item("Claude Stage 8", Style.CLAUDE)
	_style_opt.add_item("GLM organic", Style.GLM)
	_style_opt.add_item("Сравнение: исходный | Claude", Style.COMPARE)
	_style_opt.select(style)
	_style_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_style_opt.item_selected.connect(func(i: int) -> void:
		style = i
		_rebuild_subjects()
		_reapply_mutations())
	row1.add_child(_style_opt)
	_quality_opt = OptionButton.new()
	_quality_opt.add_item("Low", 0)
	_quality_opt.add_item("Medium", 1)
	_quality_opt.add_item("High", 2)
	_quality_opt.select(quality)
	_quality_opt.item_selected.connect(func(i: int) -> void:
		quality = i
		for s in subjects:
			_configure_subject(s))
	row1.add_child(_quality_opt)
	box.add_child(row1)

	var row2 := HBoxContainer.new()
	var sl := Label.new()
	sl.text = "Стадия"
	row2.add_child(sl)
	_stage_slider = HSlider.new()
	_stage_slider.min_value = 1.0
	_stage_slider.max_value = 15.0
	_stage_slider.step = 0.05
	_stage_slider.value = stage_t
	_stage_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_slider.value_changed.connect(func(v: float) -> void:
		set_mass_from_stage(v)
		_stage_lbl.text = "%.1f" % v)
	row2.add_child(_stage_slider)
	_stage_lbl = Label.new()
	_stage_lbl.custom_minimum_size = Vector2(48, 0)
	row2.add_child(_stage_lbl)
	box.add_child(row2)

	var row3 := HBoxContainer.new()
	for spec in [["Поглотить", func() -> void: act_absorb(false)], ["Крупная", func() -> void: act_absorb(true)],
			["Урон", act_hurt], ["Эволюция", act_evolve]]:
		var b := Button.new()
		b.text = spec[0]
		b.pressed.connect(spec[1])
		row3.add_child(b)
	box.add_child(row3)

	var row4 := HBoxContainer.new()
	for spec in [["Разгон →", func() -> void: act_kick(Vector2(300, 0))], ["Тормоз", func() -> void: act_kick(Vector2.ZERO)],
			["Вверх", func() -> void: act_kick(Vector2(0, -260))], ["Влево", func() -> void: act_kick(Vector2(-260, 0))]]:
		var b2 := Button.new()
		b2.text = spec[0]
		b2.pressed.connect(spec[1])
		row4.add_child(b2)
	box.add_child(row4)

	var row5 := HBoxContainer.new()
	for spec in [["Щупальца", "ranged_absorb"], ["Щит", "shield"], ["Электро", "electro_discharge"]]:
		var chk := CheckButton.new()
		chk.text = spec[0]
		var mid: String = spec[1]
		chk.toggled.connect(func(on: bool) -> void:
			set_mutation(mid, on)
			if mid == "ranged_absorb" and on:
				act_absorb(false)
			if mid == "electro_discharge" and on:
				act_dummies())
		_mut_checks[mid] = chk
		row5.add_child(chk)
	box.add_child(row5)

	var row6 := HBoxContainer.new()
	var sc := Button.new()
	sc.text = "Showcase 27 с"
	sc.pressed.connect(start_showcase)
	row6.add_child(sc)
	var fz := CheckButton.new()
	fz.text = "Стоп"
	fz.toggled.connect(func(on: bool) -> void: frozen = on)
	row6.add_child(fz)
	var cp := Button.new()
	cp.text = "Очистить"
	cp.pressed.connect(clear_prey)
	row6.add_child(cp)
	box.add_child(row6)
	var grove_row := HBoxContainer.new()
	_grove_choice = OptionButton.new()
	_grove_choice.add_item("Исходный фон")
	for title in GroveStudy.NAMES:
		_grove_choice.add_item(title)
	_grove_choice.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_grove_choice.item_selected.connect(func(i: int) -> void: _set_grove(i - 1))
	grove_row.add_child(_grove_choice)
	box.add_child(grove_row)
	var food_row := HBoxContainer.new()
	for i in range(GroveStudy.FOOD_NAMES.size()):
		var feed := Button.new()
		feed.text = GroveStudy.FOOD_NAMES[i]
		feed.add_theme_font_size_override("font_size", 16)
		feed.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		var kind := i
		feed.pressed.connect(func() -> void: act_feed(kind))
		food_row.add_child(feed)
	box.add_child(food_row)
	return root


func _reapply_mutations() -> void:
	for s in subjects:
		s.visual.mutation_levels = mutations_on.duplicate()


func _refresh_info() -> void:
	if subjects.is_empty():
		return
	var v := subjects[0].visual
	var names := []
	for s in subjects:
		names.append(s.label)
	_info.text = "%s · стадия %d · масса %.1f · r=%.1f · q%d · %.0f FPS" % [
		" | ".join(names), v.stage, mass, v.radius, quality, _fps_smooth]


func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_1:
				_set_style(Style.OLD)
			KEY_2:
				_set_style(Style.CLAUDE)
			KEY_3:
				_set_style(Style.GLM)
			KEY_4:
				_set_style(Style.COMPARE)
			KEY_SPACE:
				act_absorb(false)
			KEY_X:
				act_hurt()
			KEY_E:
				act_evolve()
			KEY_V:
				start_showcase()
			KEY_A:
				act_kick(Vector2(300, 0))
			KEY_B:
				act_kick(Vector2.ZERO)
			KEY_P:
				frozen = not frozen


func _set_style(st: int) -> void:
	style = st
	_style_opt.select(st)
	_rebuild_subjects()
	_reapply_mutations()


## --- prey -----------------------------------------------------------------------------------------

class LabPrey extends Node2D:
	## Lab-only critter: drifts toward the slime (HOME), or is reeled by a tentacle
	## (REEL), and is consumed when it crosses the membrane. DONE = consumed/idle.
	enum PState { SWIM, HOME, REEL, DONE }
	var lab: ClaudeVisualLab
	var subject: Subject
	var state: int = PState.HOME
	var body_color: Color = Color(1.0, 0.55, 0.62)
	var radius_px: float = 9.0
	var food_kind: int = -1
	var is_target_dummy: bool = false
	var _phase: float = 0.0
	var _flinch: float = 0.0
	var _reel_from: float = -1.0
	var _wander: Vector2 = Vector2.ZERO

	func _init() -> void:
		_phase = randf() * TAU

	func flinch() -> void:
		_flinch = 0.3

	func _process(delta: float) -> void:
		if lab == null or lab.frozen or subject == null:
			return
		_phase += delta * 5.0
		_flinch = maxf(0.0, _flinch - delta)
		var target := subject.root.global_position
		var d := global_position.distance_to(target)
		var r := subject.visual.radius
		match state:
			PState.SWIM:
				_wander += Vector2(sin(_phase * 0.7), cos(_phase * 0.9)) * delta * 4.0
				global_position += _wander * delta * 2.0
			PState.HOME:
				global_position = global_position.move_toward(target, 85.0 * delta)
				scale = Vector2.ONE
				if d <= r * 0.84:
					state = PState.DONE
					lab.prey_absorbed(self)
					queue_free()
			PState.REEL:
				if _reel_from < 0.0:
					_reel_from = d
				global_position = global_position.move_toward(target, 175.0 * delta)
				var shrink := clampf(0.40 + 0.60 * (d / maxf(_reel_from, 1.0)), 0.4, 1.0)
				var to_mouth := target - global_position
				scale = Vector2(shrink * 1.24, shrink * 0.78).rotated(to_mouth.angle()) if to_mouth.length() > 2.0 else Vector2.ONE * shrink
				if d <= r * 0.84:
					state = PState.DONE
					lab.prey_absorbed(self)
					queue_free()
		queue_redraw()

	func _draw() -> void:
		var r := radius_px
		var c := body_color
		draw_circle(Vector2(0.0, r * 0.35), r * 1.05, Color(0.02, 0.05, 0.04, 0.28))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.05, 0.94 + 0.05 * sin(_phase)))
		draw_circle(Vector2.ZERO, r, c)
		draw_circle(Vector2(-r * 0.25, -r * 0.30), r * 0.55, c.lightened(0.35) * Color(1, 1, 1, 0.55))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 22, c.darkened(0.45) * Color(1, 1, 1, 0.8), 1.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		for sx in [-1.0, 1.0]:
			var ep := Vector2(sx * r * 0.36, -r * 0.12)
			draw_circle(ep, r * 0.21, Color(0.05, 0.07, 0.10))
			draw_circle(ep + Vector2(-r * 0.06, -r * 0.07), r * 0.08, Color.WHITE)
		if _flinch > 0.0:
			draw_arc(Vector2.ZERO, r * 1.7, 0.0, TAU, 18, Color(1.0, 0.95, 0.55, _flinch * 2.4), 2.0)
