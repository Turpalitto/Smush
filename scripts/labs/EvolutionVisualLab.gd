class_name EvolutionVisualLab
extends Node2D
## EVOLUTION VISUAL LAB — isolated test scene for the slime's visual evolution
## (GLM organic-visual prototype). Runs fully standalone: `godot --path . res://scenes/labs/EvolutionVisualLab.tscn`.
##
## It never touches the run loop, the save, the ads or the analytics: the demo slime
## is a bare Node2D hosting a SlimeVisual (original) or SlimeVisualOrganic
## (experimental), prey are lab-only critters, and no gameplay call goes through
## PlayerSlime/complete_absorption — so save stats stay clean.
##
## Controls (also visible on-screen):
##   Stage / mass sliders  — drive the 15-stage ladder through the real
##                           EvolutionStages mapping; mass thresholds untouched.
##   Style                 — Original (slime_body.gdshader) / Organic
##                           (slime_body_organic.gdshader + organic anatomy).
##   Mutation checkboxes   — set visual.mutation_levels directly (no save writes);
##                           the level slider applies to everything checked.
##   Move / Absorb / Hurt  — demos: autonomous swimming, the full absorb sequence
##                           (contact → membrane deform → reel → inside → dissolve
##                           → smooth size change, gated by the real AbsorptionRules),
##                           and a damage hit (shield dent when shield is on).
##   Stop / speed          — Engine.time_scale 0 (or 0.25..1.5); UI stays interactive.
##   Quality               — Low / Medium / High plumbs into the organic shader and
##                           the organic nodes (lattice layers, refraction, detail).
##
## Headless-ish automation hooks (used by tools and docs):
##   LAB_SHOT=<png> LAB_STAGE=<1..15> LAB_STYLE=original|organic LAB_MUT=a,b,c
##   LAB_MLEVEL=<1..5> LAB_QUALITY=0|1|2 LAB_MASS=<float> LAB_WAIT=<sec>
##   LAB_SEQ=absorb LAB_PREY=<n>   → configure, wait, save a screenshot, quit.
##   LAB_PERF=1                    → measure avg frame ms for style×quality grid
##                                   (vsync disabled for the run), print, quit.

const PREY_RECT_HALF := Vector2(200.0, 240.0)
const DEMO_ZOOM := 1.6 # presentation zoom: judge anatomy at a phone-comparable size
const START_MASS := MassSystem.DEFAULT_START_MASS
const TOP_MASS := 121.0 # stage 15 at 96 + headroom for ascension stars

var slime_root: Node2D
var visual: SlimeVisual = null
var organic: bool = true
var mass: float = START_MASS
var display_mass: float = START_MASS
var demo_move: bool = false
var time_stopped: bool = false
var quality: int = 2
var mut_level: int = 3
var auto_prey: bool = true

var prey_container: Node2D
var _prey_spawn_timer: float = 1.2
var _tendril_tick: float = 0.0
var _electro_cd: float = 2.0
var _u_time: float = 0.0
var _ui_tick: float = 0.0
var _prev_saved_scale: float = 1.0

var mutation_levels: Dictionary = {}
var _mut_checks: Dictionary = {}

var _info_label: Label
var _stage_value: Label
var _mass_value: Label
var _stage_slider: HSlider
var _mass_slider: HSlider
var _style_opt: OptionButton
var _quality_opt: OptionButton
var _move_chk: CheckButton
var _stop_chk: CheckButton
var _speed_slider: HSlider

var _home: Vector2
var _move_phase: float = 0.0
var _fps_smooth: float = 60.0


func _ready() -> void:
	RenderingServer.set_default_clear_color(Color("#101c1a"))
	add_child(_build_ui())

	var backdrop := Backdrop.new()
	backdrop.name = "Backdrop"
	add_child(backdrop)

	prey_container = Node2D.new()
	prey_container.name = "Prey"
	add_child(prey_container)

	slime_root = Node2D.new()
	slime_root.name = "LabSlime"
	add_child(slime_root)
	_home = Vector2(360.0, 470.0)
	slime_root.position = _home
	_spawn_visual(organic)
	apply_mass(START_MASS, true)

	# Presentation camera: zoomed so the anatomy is judged at a size comparable to
	# in-game close play. +150 in world Y lifts the slime to the upper part of the
	# screen, clear of the control panel; the UI layer is unaffected.
	var cam := Camera2D.new()
	cam.name = "LabCamera"
	cam.position = _home + Vector2(0.0, 150.0)
	cam.zoom = Vector2(DEMO_ZOOM, DEMO_ZOOM)
	# The project runs with physics interpolation on, so a Camera2D left on the idle
	# callback gets force-switched to physics by the engine and prints a warning every
	# run. Ask for physics explicitly: same behaviour, no warning, and the camera still
	# tracks the slime that moves in _physics_process.
	cam.process_callback = Camera2D.CAMERA2D_PROCESS_PHYSICS
	cam.enabled = true
	add_child(cam)

	_handle_env()


func _exit_tree() -> void:
	# The lab owns Engine.time_scale while it lives; never leak a stopped clock
	# into whatever scene runs after it.
	Engine.time_scale = _prev_saved_scale


## --- visual host -----------------------------------------------------------

func _spawn_visual(p_organic: bool) -> void:
	if visual != null and is_instance_valid(visual):
		# Free immediately, not queue_free: a deferred free leaves the old node
		# named "SlimeVisual" in the tree for a frame, and Godot auto-renames the
		# new one on collision, breaking every child lookup downstream.
		visual.free()
	organic = p_organic
	if p_organic:
		visual = SlimeVisualOrganic.new()
	else:
		visual = SlimeVisual.new()
	visual.name = "SlimeVisual"
	slime_root.add_child(visual)
	visual.mutation_levels = mutation_levels.duplicate()
	visual.radius = MassSystem.radius_from_mass(display_mass)
	visual.set_growth(display_mass)
	if visual is SlimeVisualOrganic:
		(visual as SlimeVisualOrganic).set_quality(quality)
	# A shielded demo keeps the membrane up; impact reaction plays on Hurt.
	visual.shield_active = mutation_levels.get("shield", 0) > 0


func apply_mass(m: float, instant: bool = false) -> void:
	mass = clampf(m, MassSystem.MIN_MASS, TOP_MASS)
	if instant:
		display_mass = mass


## Mass for a continuous ladder position — the exact inverse of EvolutionStages
## .t_for_mass over MASS_KEYS, so the stage slider cannot drift off the real thresholds.
static func mass_for_growth_t(t: float) -> float:
	var keys := EvolutionStages.MASS_KEYS
	var tt := clampf(t, 1.0, float(EvolutionStages.COUNT))
	if tt >= float(EvolutionStages.COUNT):
		return keys[EvolutionStages.COUNT - 1]
	var i := int(floorf(tt)) - 1
	var w := tt - floorf(tt)
	return lerpf(keys[i], keys[i + 1], w)


## --- per-frame --------------------------------------------------------------

func _process(delta: float) -> void:
	_u_time += delta
	_fps_smooth = lerpf(_fps_smooth, 1.0 / maxf(delta, 0.0001), 0.05)

	if visual != null and is_instance_valid(visual):
		# Smooth displayed growth: mass math stays instant (as in the game), only the
		# visible radius eases toward it — the "smooth size change" beat.
		display_mass = lerpf(display_mass, mass, 1.0 - exp(-delta * 5.0))
		if absf(display_mass - mass) < 0.02:
			display_mass = mass
		visual.radius = MassSystem.radius_from_mass(display_mass)
		visual.set_growth(display_mass)
		visual.shield_active = mutation_levels.get("shield", 0) > 0

	# Autonomous swimming: a slow lissajous around home, velocity fed to the visual
	# so squash/stretch, trail and the organic lag all react like in a real run.
	if demo_move and visual != null:
		_move_phase += delta * 0.9
		var next := _home + Vector2(
			sin(_move_phase) * 190.0 + sin(_move_phase * 2.3) * 60.0,
			cos(_move_phase * 1.4) * 150.0)
		var vel := (next - slime_root.position) / maxf(delta, 0.0001)
		slime_root.position = slime_root.position.lerp(next, 1.0 - exp(-delta * 2.2))
		visual.velocity_vec = vel.limit_length(420.0)
		if vel.length() > 10.0:
			visual.look_dir = vel.normalized()
	else:
		visual.velocity_vec = visual.velocity_vec.move_toward(Vector2.ZERO, delta * 640.0) if visual != null else Vector2.ZERO

	_tick_demos(delta)
	_prey_housekeeping(delta)

	_ui_tick += delta
	if _ui_tick >= 0.25:
		_ui_tick = 0.0
		_refresh_info()


func _tick_demos(delta: float) -> void:
	if visual == null or not is_instance_valid(visual):
		return

	# ranged_absorb: organic-style elastic reel of the nearest prey. In the original
	# style the base polyline tendrils still draw (comparison!), and the reel is
	# shared, exactly mirroring what ArenaController.process_ranged_tendrils does.
	var rng_lv := int(mutation_levels.get("ranged_absorb", 0))
	if rng_lv > 0:
		_tendril_tick -= delta
		if _tendril_tick <= 0.0:
			_tendril_tick = 0.10
			var reach := 155.0 + 28.0 * float(rng_lv - 1)
			var pts: Array[Vector2] = []
			for prey in prey_container.get_children():
				var pr := prey as LabPrey
				if pr == null or pr.state == LabPrey.PState.DISSOLVE or pr.state == LabPrey.PState.FLEE:
					continue
				if pr.state == LabPrey.PState.SWIM:
					if pr.global_position.distance_to(slime_root.global_position) <= reach + pr.body_radius():
						pr.state = LabPrey.PState.REEL
				# Reeling prey must stay in the list every tick: an earlier version
				# skipped non-SWIM prey, which cleared the targets 0.1 s after the
				# grab and made the pseudopod blink out mid-pull.
				if pr.state == LabPrey.PState.REEL:
					pts.append(pr.global_position)
			visual.active_tendril_targets = pts

	# electro_discharge (organic style): charge builds in the body shader; every
	# interval the discharge arcs jump to up to two nearby prey.
	var el_lv := int(mutation_levels.get("electro_discharge", 0))
	if el_lv > 0 and organic and visual is SlimeVisualOrganic:
		_electro_cd -= delta
		if _electro_cd <= 0.0:
			_electro_cd = maxf(1.1, 3.4 - 0.32 * float(el_lv - 1))
			var targets: Array[Vector2] = []
			for prey in prey_container.get_children():
				var pr := prey as LabPrey
				if pr == null or pr.state == LabPrey.PState.DISSOLVE:
					continue
				if pr.global_position.distance_to(slime_root.global_position) < 320.0:
					targets.append(pr.global_position - slime_root.global_position)
				if targets.size() >= 2 + 2:
					break
			if not targets.is_empty():
				(visual as SlimeVisualOrganic).trigger_electro_flash()
				var node := visual.get_node_or_null("OrganicElectro")
				if node is OrganicElectro:
					(node as OrganicElectro).fire_discharge(targets)
				for prey in prey_container.get_children():
					var pr2 := prey as LabPrey
					if pr2 != null:
						pr2.flinch()


func _prey_housekeeping(delta: float) -> void:
	# Mass is applied exactly once, inside finish_absorb when the prey crosses the
	# membrane. (An earlier version applied pending_mass_gain here too and the demo
	# slime doubled every meal.)
	if auto_prey:
		_prey_spawn_timer -= delta
		if _prey_spawn_timer <= 0.0 and prey_container.get_child_count() < 5:
			_prey_spawn_timer = randf_range(1.6, 2.6)
			spawn_prey()


## --- demo actions -----------------------------------------------------------

func action_absorb() -> void:
	# Guarantee a target, then let the reel+rules do the rest this frame.
	if _live_prey_count() == 0:
		spawn_prey()


func action_hurt() -> void:
	if visual == null:
		return
	var shield_on: bool = int(mutation_levels.get("shield", 0)) > 0
	if shield_on and visual.shield_active:
		# Blocked by the membrane: the organic shield dents and recovers; the
		# original style shows its static dome (no impact anim exists there).
		if organic and visual is SlimeVisualOrganic:
			(visual as SlimeVisualOrganic).trigger_shield_impact(Vector2(randf_range(-1.0, 1.0), 1.0).normalized())
		visual.trigger_hurt()
	else:
		visual.trigger_hurt()
	# Electro demo also fires a manual discharge on hurt, so the burst is reachable
	# without waiting for the interval.
	if organic and el_on() and visual is SlimeVisualOrganic:
		(visual as SlimeVisualOrganic).trigger_electro_flash()
		var node := visual.get_node_or_null("OrganicElectro")
		if node is OrganicElectro:
			var targets: Array[Vector2] = []
			for i in range(mini(2, _live_prey_count())):
				targets.append(Vector2(120.0 + 60.0 * float(i), -90.0 + 45.0 * float(i)))
			if not targets.is_empty():
				(node as OrganicElectro).fire_discharge(targets)


func el_on() -> bool:
	return mutation_levels.get("electro_discharge", 0) > 0


func _live_prey_count() -> int:
	var n := 0
	for prey in prey_container.get_children():
		var pr := prey as LabPrey
		if pr != null and pr.state != LabPrey.PState.DISSOLVE:
			n += 1
	return n


func spawn_prey() -> void:
	var prey := LabPrey.new()
	prey.lab = self
	prey.global_position = slime_root.global_position + Vector2(
		randf_range(-PREY_RECT_HALF.x, PREY_RECT_HALF.x),
		randf_range(-PREY_RECT_HALF.y, PREY_RECT_HALF.y))
	prey_container.add_child(prey)


## Called by prey when it crosses the membrane (rules already accepted it).
func finish_absorb(prey: LabPrey) -> void:
	if visual == null or not is_instance_valid(visual):
		return
	var entry := prey.global_position - slime_root.global_position
	if organic and visual is SlimeVisualOrganic:
		(visual as SlimeVisualOrganic).trigger_swallow(entry, prey.body_color, prey.body_radius() * 0.8)
	else:
		visual.trigger_gulp()
	apply_mass(mass + prey.mass_value, false)


## Called when the real AbsorptionRules REJECT a prey (too strong): it darts away.
func reject_prey(prey: LabPrey) -> void:
	prey.flee()


## --- UI ----------------------------------------------------------------------

func _build_ui() -> CanvasLayer:
	var layer := CanvasLayer.new()
	layer.name = "UILayer"
	var root := Control.new()
	root.name = "UIRoot"
	root.set_anchors_preset(Control.PRESET_FULL_RECT)
	root.mouse_filter = Control.MOUSE_FILTER_IGNORE
	root.theme = UIThemeBuilder.build_theme()
	layer.add_child(root)

	_info_label = Label.new()
	_info_label.position = Vector2(16, 12)
	_info_label.text = "EVOLUTION VISUAL LAB"
	_info_label.add_theme_font_size_override("font_size", 22)
	root.add_child(_info_label)

	var panel := PanelContainer.new()
	panel.name = "ControlPanel"
	panel.set_anchors_preset(Control.PRESET_BOTTOM_WIDE)
	panel.anchor_top = 0.52
	panel.grow_vertical = Control.GROW_DIRECTION_BEGIN
	root.add_child(panel)

	var box := VBoxContainer.new()
	box.add_theme_constant_override("separation", 6)
	panel.add_child(box)

	# Stage + mass rows.
	var stage_row := HBoxContainer.new()
	var stage_lbl := Label.new()
	stage_lbl.text = "Стадия"
	stage_lbl.custom_minimum_size = Vector2(96, 0)
	stage_row.add_child(stage_lbl)
	_stage_slider = HSlider.new()
	_stage_slider.min_value = 1.0
	_stage_slider.max_value = 15.0
	_stage_slider.step = 0.05
	_stage_slider.value = 1.0
	_stage_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_stage_slider.value_changed.connect(_on_stage_slider)
	stage_row.add_child(_stage_slider)
	_stage_value = Label.new()
	_stage_value.custom_minimum_size = Vector2(64, 0)
	stage_row.add_child(_stage_value)
	box.add_child(stage_row)

	var mass_row := HBoxContainer.new()
	var mass_lbl := Label.new()
	mass_lbl.text = "Масса"
	mass_lbl.custom_minimum_size = Vector2(96, 0)
	mass_row.add_child(mass_lbl)
	_mass_slider = HSlider.new()
	_mass_slider.min_value = START_MASS
	_mass_slider.max_value = TOP_MASS
	_mass_slider.step = 0.5
	_mass_slider.value = START_MASS
	_mass_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	_mass_slider.value_changed.connect(_on_mass_slider)
	mass_row.add_child(_mass_slider)
	_mass_value = Label.new()
	_mass_value.custom_minimum_size = Vector2(64, 0)
	mass_row.add_child(_mass_value)
	box.add_child(mass_row)

	# Style + quality.
	var style_row := HBoxContainer.new()
	var style_lbl := Label.new()
	style_lbl.text = "Стиль"
	style_lbl.custom_minimum_size = Vector2(96, 0)
	style_row.add_child(style_lbl)
	_style_opt = OptionButton.new()
	_style_opt.add_item("Исходный", 0)
	_style_opt.add_item("Органический", 1)
	_style_opt.select(1)
	_style_opt.item_selected.connect(func(idx: int) -> void: _spawn_visual(idx == 1); _refresh_info())
	_style_opt.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	style_row.add_child(_style_opt)
	var q_lbl := Label.new()
	q_lbl.text = "Кач-во"
	style_row.add_child(q_lbl)
	_quality_opt = OptionButton.new()
	_quality_opt.add_item("Low", 0)
	_quality_opt.add_item("Med", 1)
	_quality_opt.add_item("High", 2)
	_quality_opt.select(2)
	_quality_opt.item_selected.connect(_on_quality)
	style_row.add_child(_quality_opt)
	box.add_child(style_row)

	# Demo row.
	var demo_row := HBoxContainer.new()
	_move_chk = CheckButton.new()
	_move_chk.text = "Движение"
	_move_chk.toggled.connect(func(on: bool) -> void: demo_move = on)
	demo_row.add_child(_move_chk)
	var absorb_btn := Button.new()
	absorb_btn.text = "Поглотить"
	absorb_btn.pressed.connect(action_absorb)
	demo_row.add_child(absorb_btn)
	var hurt_btn := Button.new()
	hurt_btn.text = "Урон"
	hurt_btn.pressed.connect(action_hurt)
	demo_row.add_child(hurt_btn)
	_stop_chk = CheckButton.new()
	_stop_chk.text = "Стоп"
	_stop_chk.toggled.connect(_on_stop_toggled)
	demo_row.add_child(_stop_chk)
	var spd_lbl := Label.new()
	spd_lbl.text = "×"
	demo_row.add_child(spd_lbl)
	_speed_slider = HSlider.new()
	_speed_slider.min_value = 0.25
	_speed_slider.max_value = 1.5
	_speed_slider.step = 0.05
	_speed_slider.value = 1.0
	_speed_slider.custom_minimum_size = Vector2(110, 0)
	_speed_slider.value_changed.connect(func(v: float) -> void:
		if not time_stopped:
			Engine.time_scale = v)
	demo_row.add_child(_speed_slider)
	box.add_child(demo_row)

	# Mutation level + grid.
	var mlvl_row := HBoxContainer.new()
	var mlvl_lbl := Label.new()
	mlvl_lbl.text = "Ур. мутаций"
	mlvl_lbl.custom_minimum_size = Vector2(130, 0)
	mlvl_row.add_child(mlvl_lbl)
	var mlvl_slider := HSlider.new()
	mlvl_slider.min_value = 1
	mlvl_slider.max_value = 5
	mlvl_slider.step = 1
	mlvl_slider.value = mut_level
	mlvl_slider.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	mlvl_slider.value_changed.connect(_on_mut_level)
	mlvl_row.add_child(mlvl_slider)
	box.add_child(mlvl_row)

	var scroll := ScrollContainer.new()
	scroll.custom_minimum_size = Vector2(0, 128)
	scroll.horizontal_scroll_mode = ScrollContainer.SCROLL_MODE_DISABLED
	box.add_child(scroll)
	var grid := GridContainer.new()
	grid.columns = 3
	grid.add_theme_constant_override("h_separation", 4)
	grid.add_theme_constant_override("v_separation", 0)
	scroll.add_child(grid)
	for mid: String in ConfigDB.mutation_order:
		var cfg := ConfigDB.get_mutation(mid)
		var chk := CheckButton.new()
		var label := mid
		var key := str(cfg.get("name_key", ""))
		if not key.is_empty():
			label = Loc.t(key)
		chk.text = label
		chk.tooltip_text = mid
		chk.toggled.connect(_on_mutation_toggled.bind(mid))
		grid.add_child(chk)
		_mut_checks[mid] = chk

	return layer


func _on_stage_slider(v: float) -> void:
	apply_mass(mass_for_growth_t(v), true)
	if _mass_slider != null:
		_mass_slider.set_value_no_signal(mass)


func _on_mass_slider(v: float) -> void:
	apply_mass(v, true)
	if _stage_slider != null:
		_stage_slider.set_value_no_signal(EvolutionStages.t_for_mass(mass))


func _on_quality(idx: int) -> void:
	quality = idx
	if visual is SlimeVisualOrganic:
		(visual as SlimeVisualOrganic).set_quality(idx)


func _on_stop_toggled(on: bool) -> void:
	time_stopped = on
	Engine.time_scale = 0.0 if on else _speed_slider.value


func _on_mutation_toggled(on: bool, mid: String) -> void:
	if on:
		mutation_levels[mid] = mut_level
	else:
		mutation_levels.erase(mid)
	if visual != null and is_instance_valid(visual):
		visual.mutation_levels = mutation_levels.duplicate()
		visual.shield_active = mutation_levels.get("shield", 0) > 0


func _on_mut_level(v: float) -> void:
	mut_level = int(v)
	for mid in mutation_levels.keys():
		mutation_levels[mid] = mut_level
	if visual != null and is_instance_valid(visual):
		visual.mutation_levels = mutation_levels.duplicate()


func _refresh_info() -> void:
	if visual == null:
		return
	var stage_name := Loc.t(EvolutionStages.name_key_for_stage(visual.stage))
	var phase := 0
	if organic:
		phase = SlimeVisualOrganic.phase_of_stage(visual.stage)
	var phase_txt := " · %s" % SlimeVisualOrganic.PHASE_NAMES_RU[phase - 1] if phase > 0 else ""
	_info_label.text = "Стадия %d/15 · %s%s · масса %.1f · %.0f FPS" % [
		visual.stage, stage_name, phase_txt, display_mass, _fps_smooth]
	_stage_value.text = "%d/15" % visual.stage
	_mass_value.text = "%.1f" % display_mass


## --- env automation (screenshots + perf, see header) --------------------------

func _handle_env() -> void:
	var shot := OS.get_environment("LAB_SHOT")
	var perf := OS.get_environment("LAB_PERF")
	if shot.is_empty() and perf.is_empty():
		return

	var size_env := OS.get_environment("LAB_SIZE")
	if not size_env.is_empty():
		var parts := size_env.split("x")
		if parts.size() == 2:
			DisplayServer.window_set_size(Vector2i(int(parts[0]), int(parts[1])))

	var stage_env := OS.get_environment("LAB_STAGE")
	if not stage_env.is_empty():
		var t := float(stage_env)
		apply_mass(mass_for_growth_t(t), true)
		_stage_slider.set_value_no_signal(t)
		_mass_slider.set_value_no_signal(mass)
	var mass_env := OS.get_environment("LAB_MASS")
	if not mass_env.is_empty():
		apply_mass(float(mass_env), true)
		_mass_slider.set_value_no_signal(mass)
		_stage_slider.set_value_no_signal(EvolutionStages.t_for_mass(mass))
	var style_env := OS.get_environment("LAB_STYLE")
	if not style_env.is_empty():
		var want_org := style_env == "organic"
		_spawn_visual(want_org)
		_style_opt.select(1 if want_org else 0)
	var mut_env := OS.get_environment("LAB_MUT")
	if not mut_env.is_empty():
		for mid in mut_env.split(","):
			var id := mid.strip_edges()
			if _mut_checks.has(id):
				(_mut_checks[id] as CheckButton).button_pressed = true
	var ml_env := OS.get_environment("LAB_MLEVEL")
	if not ml_env.is_empty():
		mut_level = clampi(int(ml_env), 1, 5)
		_on_mut_level(float(mut_level))
	var q_env := OS.get_environment("LAB_QUALITY")
	if not q_env.is_empty():
		quality = clampi(int(q_env), 0, 2)
		_quality_opt.select(quality)
		_on_quality(quality)
	var prey_env := OS.get_environment("LAB_PREY")
	if not prey_env.is_empty():
		for i in range(clampi(int(prey_env), 0, 8)):
			spawn_prey()
	if OS.get_environment("LAB_MOVE") == "1":
		demo_move = true
		_move_chk.button_pressed = true

	if not perf.is_empty():
		_run_perf()
		return

	# Screenshot mode: optional mid-wait absorb demo, then capture and quit.
	var wait := 0.9
	var wait_env := OS.get_environment("LAB_WAIT")
	if not wait_env.is_empty():
		wait = float(wait_env)
	if OS.get_environment("LAB_SEQ") == "absorb":
		for i in range(3):
			spawn_prey()
		action_absorb()
	# tendril: one prey at a fixed in-reach spot, so the reel is deterministic and a
	# screenshot catches the pseudopod mid-pull (prey reeled at ~300 px/s from 190 px).
	var seq := OS.get_environment("LAB_SEQ")
	if seq == "tendril":
		if int(mutation_levels.get("ranged_absorb", 0)) == 0:
			_on_mutation_toggled(true, "ranged_absorb")
		var fixed := LabPrey.new()
		fixed.lab = self
		fixed.global_position = slime_root.global_position + Vector2(190.0, -40.0)
		prey_container.add_child(fixed)
	if seq == "electro" or seq == "absorb" or seq == "hurt":
		await get_tree().create_timer(maxf(0.15, wait - 0.35)).timeout
		if seq == "electro":
			if not el_on():
				_on_mutation_toggled(true, "electro_discharge")
			if organic and visual is SlimeVisualOrganic:
				(visual as SlimeVisualOrganic).trigger_electro_flash()
			var el_node := visual.get_node_or_null("OrganicElectro")
			if el_node is OrganicElectro:
				var targets: Array[Vector2] = [Vector2(170.0, -60.0), Vector2(-150.0, 40.0)]
				(el_node as OrganicElectro).fire_discharge(targets)
			else:
				push_warning("LAB_SEQ=electro: OrganicElectro node not found")
		elif seq == "hurt":
			action_hurt()
		await get_tree().create_timer(0.12).timeout
	else:
		await get_tree().create_timer(wait).timeout
	for _i in range(3):
		await get_tree().process_frame
	if OS.get_environment("LAB_SEQ") == "tendril":
		for prey in prey_container.get_children():
			var pr := prey as LabPrey
			if pr != null:
				print("LAB_DEBUG prey state=%d pos=%s scale=%s visible=%s tendril_targets=%d mass=%.1f" % [
					pr.state, str(pr.global_position - slime_root.global_position),
					str(pr.scale), str(pr.visible), visual.active_tendril_targets.size(), display_mass])
	var img := get_viewport().get_texture().get_image()
	if img == null or img.is_empty():
		push_error("LAB_SHOT: capture produced no image")
		get_tree().quit(3)
		return
	var err := img.save_png(shot)
	print("LAB_SHOT %s %dx%d style=%s stage=%s mass=%.1f err=%d" % [
		shot, img.get_width(), img.get_height(),
		"organic" if organic else "original",
		OS.get_environment("LAB_STAGE"), display_mass, err])
	get_tree().quit(0 if err == OK else 4)


func _run_perf() -> void:
	# vsync off: with it on, every style would flatten to the refresh interval and
	# the comparison would measure the compositor, not the shader.
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_DISABLED)
	demo_move = true
	_move_chk.button_pressed = true
	print("LAB_PERF BEGIN (CPU frame time, vsync off; NOT a device GPU measurement)")
	for style in [0, 1]:
		for q in range(3):
			_spawn_visual(style == 1)
			_style_opt.select(style)
			if style == 1:
				_on_quality(q)
				_quality_opt.select(q)
			else:
				quality = q
			for _w in range(30):
				await get_tree().process_frame
			var samples: Array[float] = []
			for _f in range(180):
				var t0 := Time.get_ticks_usec()
				await get_tree().process_frame
				samples.append(float(Time.get_ticks_usec() - t0) / 1000.0)
			var sum := 0.0
			var mn := INF
			var mx := 0.0
			for s in samples:
				sum += s
				mn = minf(mn, s)
				mx = maxf(mx, s)
			print("LAB_PERF style=%s quality=%d frames=%d avg_ms=%.3f min_ms=%.3f max_ms=%.3f" % [
				"organic" if style == 1 else "original", q, samples.size(), sum / float(samples.size()), mn, mx])
	# Restore the default presentation for any further use.
	_spawn_visual(true)
	_on_quality(2)
	DisplayServer.window_set_vsync_mode(DisplayServer.VSYNC_ENABLED)
	print("LAB_PERF END")
	get_tree().quit(0)


## --- keyboard conveniences ----------------------------------------------------

func _unhandled_input(event: InputEvent) -> void:
	if event is InputEventKey and event.pressed and not event.echo:
		match (event as InputEventKey).keycode:
			KEY_SPACE:
				action_absorb()
			KEY_X:
				action_hurt()
			KEY_P:
				_stop_chk.button_pressed = not _stop_chk.button_pressed
			KEY_M:
				_move_chk.button_pressed = not _move_chk.button_pressed


## --- prey ----------------------------------------------------------------------

class LabPrey extends Node2D:
	## A lab-only critter. swims, gets reeled (teardrop shrink mirroring
	## EnemyEntity.BEING_ABSORBED), dissolves after crossing the membrane, or flees
	## when AbsorptionRules rejects it. Draws itself: a soft body, contour, eyes.
	enum PState { SWIM, REEL, INSIDE, FLEE, DISSOLVE }

	var lab: Node2D = null
	var state: PState = PState.SWIM
	var mass_value: float = 4.0
	var category: String = "insect"
	var body_color: Color = Color(0.94, 0.53, 0.65)
	var accent_color: Color = Color(1.0, 0.92, 0.82)
	var pending_mass_gain: float = 0.0

	var _wander_target: Vector2 = Vector2.ZERO
	var _wander_timer: float = 0.0
	var _flee_t: float = 0.0
	var _dissolve_t: float = 0.0
	var _flinch_t: float = 0.0
	var _phase: float = 0.0
	var _reel_t: float = 0.0
	var _reel_from: float = 1.0

	func _init() -> void:
		mass_value = randf_range(2.5, 6.5)
		category = "insect" if randf() < 0.7 else "flora"
		var hue := randf_range(0.0, 1.0)
		body_color = Color.from_hsv(hue, 0.55, 0.95)
		accent_color = Color.from_hsv(fposmod(hue + 0.12, 1.0), 0.35, 1.0)
		_phase = randf() * TAU

	func body_radius() -> float:
		return 5.0 + mass_value * 1.1

	func flinch() -> void:
		_flinch_t = 0.3

	func flee() -> void:
		if state == PState.SWIM or state == PState.REEL:
			state = PState.FLEE
			_flee_t = 0.8

	func _process(delta: float) -> void:
		_phase += delta * 5.0
		_flinch_t = maxf(0.0, _flinch_t - delta)
		match state:
			PState.SWIM:
				_wander_timer -= delta
				if _wander_timer <= 0.0:
					_wander_timer = randf_range(1.2, 2.6)
					_wander_target = global_position + Vector2(randf_range(-170.0, 170.0), randf_range(-200.0, 200.0))
				global_position = global_position.move_toward(_wander_target, 55.0 * delta)
				position.y += sin(_phase) * 6.0 * delta
			PState.REEL:
				_reel_t += delta
				var target := Vector2.ZERO
				if lab != null and lab.slime_root != null:
					target = lab.slime_root.global_position
				var d := global_position.distance_to(target)
				# 170 px/s instead of the game's ~310: the lab demo pulls from a fixed
				# 190 px and must stay on screen long enough for the pseudopod pull to
				# be readable (and photographable). In-game reel speed is untouched.
				global_position = global_position.move_toward(target, 170.0 * delta)
				# Teardrop fluid elongation toward the mouth, like the game's own
				# BEING_ABSORBED state — but scaled by REMAINING DISTANCE, not by
				# time: a distance-based shrink was needed because the lab pull is
				# ~1 s long and a fixed 4.2/s rate shrank the prey to a speck while
				# it was still visibly mid-pull.
				if _reel_from <= 1.0:
					_reel_from = d
				var shrink := clampf(0.35 + 0.65 * (d / maxf(_reel_from, 1.0)), 0.35, 1.0)
				var to_mouth := target - global_position
				if to_mouth.length() > 2.0:
					scale = Vector2(shrink * 1.26, shrink * 0.74).rotated(to_mouth.angle())
				else:
					scale = Vector2.ONE * shrink
				var slime_r := 25.0
				if lab != null and lab.visual != null:
					slime_r = lab.visual.radius
				if d <= slime_r * 0.72:
					# Membrane crossed: the visual swallow fires (ripple + ghost in
					# organic style, gulp in the original) and mass applies instantly —
					# the animation never gates the numbers.
					if lab != null and lab.has_method("finish_absorb"):
						pending_mass_gain = mass_value
						lab.call("finish_absorb", self)
					state = PState.DISSOLVE
					_dissolve_t = 0.0
			PState.FLEE:
				_flee_t -= delta
				global_position += (global_position - _wander_target).normalized() * 340.0 * delta
				if _flee_t <= 0.0:
					state = PState.SWIM
			PState.DISSOLVE:
				_dissolve_t += delta
				if _dissolve_t > 0.55:
					queue_free()
		queue_redraw()

	func _draw() -> void:
		var r := body_radius()
		var alpha := 1.0
		if state == PState.DISSOLVE:
			# Dissolve at the membrane: the body itself is gone (the organic ghost
			# drifts inside, or the gulp burst fired), only escape motes remain.
			alpha = clampf(1.0 - _dissolve_t / 0.55, 0.0, 1.0)
			for i in range(4):
				var a := TAU * float(i) / 4.0 + _dissolve_t * 6.0
				var mp := Vector2.from_angle(a) * (r * (1.2 + _dissolve_t * 2.2))
				draw_circle(mp, r * 0.22, Color(body_color.r, body_color.g, body_color.b, alpha * 0.7))
			return
		var bob := 1.0 + 0.06 * sin(_phase)
		# Body: soft ellipse with a darker contour and a lit cap.
		draw_circle(Vector2(0, r * 0.15), r * 1.1, Color(0.02, 0.06, 0.05, 0.25 * alpha))
		draw_set_transform(Vector2.ZERO, 0.0, Vector2(1.05, bob * 0.92))
		draw_circle(Vector2.ZERO, r, Color(body_color.r, body_color.g, body_color.b, alpha))
		draw_circle(Vector2(-r * 0.2, -r * 0.25), r * 0.55, Color(accent_color.r, accent_color.g, accent_color.b, 0.55 * alpha))
		draw_arc(Vector2.ZERO, r, 0.0, TAU, 20, Color(0.06, 0.10, 0.09, 0.7 * alpha), 1.6)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		# Eyes (two dots) unless dissolving.
		if state != PState.DISSOLVE:
			for sx in [-1.0, 1.0]:
				var ep := Vector2(sx * r * 0.34, -r * 0.12)
				draw_circle(ep, r * 0.2, Color(0.05, 0.08, 0.10, alpha))
				draw_circle(ep + Vector2(-r * 0.06, -r * 0.06), r * 0.08, Color(1, 1, 1, alpha))
		if _flinch_t > 0.0:
			draw_arc(Vector2.ZERO, r * 1.7, 0.0, TAU, 18,
				Color(1.0, 0.9, 0.5, _flinch_t * 2.2), 2.0)


## --- backdrop -------------------------------------------------------------------

class Backdrop extends Node2D:
	## A quiet stand-in environment: dark gradient plus faint concentric rings and a
	## horizon line. The rings exist so translucency and refraction have something
	## honest to bend; a flat colour would hide both.
	func _draw() -> void:
		var vp := get_viewport_rect().size
		# Vertical gradient via stacked translucent bands (no texture dependency).
		var bands := 24
		for i in range(bands):
			var t := float(i) / float(bands - 1)
			var c := Color(0.055 + 0.05 * t, 0.10 + 0.09 * t, 0.095 + 0.075 * t, 1.0)
			draw_rect(Rect2(0.0, vp.y * t, vp.x, vp.y / float(bands) + 1.0), c)
		var centre := Vector2(vp.x * 0.5, vp.y * 0.37)
		for i in range(7):
			var rr := 60.0 + 90.0 * float(i)
			draw_arc(centre, rr, 0.0, TAU, 64, Color(0.55, 0.95, 0.85, 0.05), 1.5)
		draw_line(Vector2(0, vp.y * 0.70), Vector2(vp.x, vp.y * 0.70), Color(0.5, 0.9, 0.8, 0.07), 2.0)
		# A few faint "spores" so the absorb demo has motion reference points.
		var rng := RandomNumberGenerator.new()
		rng.seed = 7
		for i in range(26):
			var p := Vector2(rng.randf_range(0, vp.x), rng.randf_range(0, vp.y * 0.66))
			draw_circle(p, rng.randf_range(1.0, 2.6), Color(0.7, 1.0, 0.9, rng.randf_range(0.04, 0.10)))
