class_name SlimeVisualClaude
extends SlimeVisual
## CLAUDE VISUAL CHALLENGE V8 — "Lunar Jelly", an experimental organic body for the
## slime. A drop-in subclass of SlimeVisual: same palette contract, same trigger_*
## entry points, nothing in the run loop, balance or save is touched, and the
## original style stays selectable (PlayerSlime keeps instantiating the base class
## unless the owner opts in).
##
## What lives where (the point of the architecture):
##
##   ClaudeRing    CPU spring-damper membrane. Acceleration, braking, hits and
##                 swallows push it, so the silhouette has real inertia and rings
##                 out. The shader never invents motion the player did not cause.
##   body shader   turns that state into pixels (shaders/slime_body_claude.gdshader).
##   eyes shader   analytic face with lids; expression comes from game state.
##   interior lag  a second damped spring moves the core, vesicles and eyes against
##                 the shell, each layer with its own depth factor.
##   tentacles / shield / bolts   the three showcased mutations, each driven by the
##                 SAME fields the game already feeds the base class
##                 (active_tendril_targets, shield_active, mutation_levels).
##
## Physical radius, mass and ability numbers are never read or written here.

const BODY_UNIT: float = 1.04     ## drawn body radius / game radius (old style: ~1.07)
const EXTENT: float = 1.5         ## quad half-size in body radii
const FACE_Y: float = -0.13       ## eye line, in body radii (negative = up)
const EYE_SEP: float = 0.335
const ACCEL_REF: float = 1500.0   ## px/s^2 that counts as "hard" acceleration
const CORE_Y: float = 0.26
const BODY_SHADER := "res://shaders/slime_body_claude.gdshader"
const EYES_SHADER := "res://shaders/slime_eyes_claude.gdshader"

var quality: int = 2

var _ring: ClaudeRing = ClaudeRing.new()
var _u_time: float = 0.0
var _prev_vel: Vector2 = Vector2.ZERO
var _since_vel_change: float = 0.05
var _accel: Vector2 = Vector2.ZERO
var _lag: Vector2 = Vector2.ZERO
var _lag_v: Vector2 = Vector2.ZERO
var _frame_ang: float = 0.0
var _tail_dir: Vector2 = Vector2(0.0, 1.0)
var _core_energy: float = 0.0
var _breath: float = 0.0
var _ripple_a: Vector4 = Vector4(0.0, 0.0, 2.0, 0.0)
var _ripple_h: Vector4 = Vector4(0.0, 0.0, 2.0, 0.0)
var _evo_t: float = -1.0
var _electro_flash: float = 0.0
var _electro_cycle: float = 0.0
var _electro_seed: float = 0.0
var _gulp_eye: float = 0.0
var _blink_amt: float = 0.0
var _wide_amt: float = 0.0
var _swallowed: Array[Dictionary] = []
var _px_per_unit: float = 40.0

var _eyes_rect: ColorRect
var _eyes_mat: ShaderMaterial
var _inner: Node2D
var _tentacles: ClaudeTentacles
var _shield_node: ClaudeShield
var _bolts: ClaudeBolts


func _ready() -> void:
	super._ready()
	custom_face = true
	custom_burst = true
	custom_ground = true
	organic_tendrils = true
	organic_shield = true
	organic_electro = true
	organic_all_mutations = true

	var body_shader := load(BODY_SHADER) as Shader
	if body_shader != null and _shader_mat != null:
		_shader_mat.shader = body_shader

	# Tentacles live UNDER the body so their roots vanish into the membrane.
	_tentacles = ClaudeTentacles.new()
	_tentacles.name = "ClaudeTentacles"
	add_child(_tentacles)
	move_child(_tentacles, _jelly_rect.get_index())

	_inner = Node2D.new()
	_inner.name = "ClaudeInner"
	_inner.draw.connect(_draw_inner)
	add_child(_inner)
	move_child(_inner, _jelly_rect.get_index() + 1)

	_eyes_rect = ColorRect.new()
	_eyes_rect.name = "ClaudeEyes"
	_eyes_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var eyes_shader := load(EYES_SHADER) as Shader
	if eyes_shader != null:
		_eyes_mat = ShaderMaterial.new()
		_eyes_mat.shader = eyes_shader
		_eyes_rect.material = _eyes_mat
	add_child(_eyes_rect)
	move_child(_eyes_rect, _inner.get_index() + 1)

	_shield_node = ClaudeShield.new()
	_shield_node.name = "ClaudeShield"
	add_child(_shield_node)
	move_child(_shield_node, _fg_overlay.get_index() + 1)

	_bolts = ClaudeBolts.new()
	_bolts.name = "ClaudeBolts"
	add_child(_bolts)
	_recompute_look()


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	if _shader_mat != null:
		_shader_mat.set_shader_parameter(&"quality", quality)
	if _shield_node != null:
		_shield_node.quality = quality
	if _tentacles != null:
		_tentacles.quality = quality


## --- events -----------------------------------------------------------------------

func trigger_gulp() -> void:
	super.trigger_gulp()
	_ring.impulse_all(1.1)
	_core_energy = minf(_core_energy + 0.22, 1.2)
	_gulp_eye = 1.0


func trigger_hurt() -> void:
	super.trigger_hurt()
	# A flinch: the whole membrane is driven inward, then recovers with a ripple.
	_ring.impulse_all(-2.6)
	var from := -look_dir.normalized() if look_dir.length_squared() > 0.01 else Vector2.UP
	_ripple_h = Vector4(from.x * 0.9, from.y * 0.9, 0.0, 1.0)
	_ring.impulse(from.angle(), -4.0, 2.0)
	_core_energy = minf(_core_energy + 0.15, 1.2)


func trigger_evolution() -> void:
	super.trigger_evolution()
	_evo_t = 0.0
	_core_energy = 1.2
	_ring.impulse_all(2.4)
	_wide_amt = 1.0


## Visual-only swallow: the membrane cups inward at the contact point, rebounds into a
## bulge, a ripple crosses the interior, and the prey drifts to the core and dissolves.
## The game's complete_absorption still does the real mass work instantly.
func trigger_swallow(local_entry: Vector2, prey_color: Color, prey_size: float) -> void:
	var dir := local_entry.normalized() if local_entry.length_squared() > 0.001 else Vector2.DOWN
	var a := dir.angle()
	_ring.push(a, -0.085, 1.5)
	_ring.impulse(a, 5.5, 1.6)
	_ring.impulse_all(0.6)
	_ripple_a = Vector4(dir.x * 0.95, dir.y * 0.95, 0.0, 1.0)
	_gulp_eye = 1.0
	gulp_bulge = maxf(gulp_bulge, 0.16)
	var r0 := _body_radius()
	_swallowed.append({
		"from": (dir * r0 * 0.88),
		"t": 0.0,
		"color": prey_color,
		"size": clampf(prey_size, 2.5, r0 * 0.30),
		"fed": false,
	})
	if _swallowed.size() > 4:
		_swallowed.pop_front()


func trigger_shield_impact(local_dir: Vector2, strength: float = 1.0) -> void:
	var d := local_dir.normalized() if local_dir.length_squared() > 0.001 else Vector2.DOWN
	if _shield_node != null:
		_shield_node.trigger_impact(d, strength)
	_ring.impulse(d.angle(), -1.4 * strength, 1.8)
	_ripple_h = Vector4(d.x * 0.9, d.y * 0.9, 0.0, 0.55 * strength)


## targets: positions relative to this node, in canvas units (same space as
## `active_tendril_targets` after to_local). Empty = a short omnidirectional burst.
func trigger_electro_discharge(local_targets: Array[Vector2]) -> void:
	_electro_flash = 1.0
	_electro_cycle = 0.0
	_electro_seed = fmod(_electro_seed + 3.17, 40.0)
	_core_energy = minf(_core_energy + 0.45, 1.2)
	_ring.impulse_all(0.9)
	if _bolts != null:
		_bolts.fire(local_targets, _body_radius(), int(mutation_levels.get("electro_discharge", 1)))


## --- per-frame ---------------------------------------------------------------------

func _body_radius() -> float:
	return radius * BODY_UNIT * (1.0 + death_progress * 0.45)


## Shell-frame vector (body radii) -> canvas offset, following the same squash frame
## the shader uses, so face, ghosts and roots stay glued to the deforming body.
func _shell_to_canvas(v: Vector2, r0: float) -> Vector2:
	var q := v.rotated(-_frame_ang) * squash_stretch
	return q.rotated(_frame_ang) * r0


func _process(delta: float) -> void:
	super._process(delta)
	var live := delta > 0.0
	var dt := minf(delta, 0.05)
	_u_time += dt
	var speed := velocity_vec.length()

	# Acceleration, sampled only when the velocity actually changed (the game writes
	# it once per physics tick, so a per-frame difference would be noise).
	if live:
		_since_vel_change += dt
		if not velocity_vec.is_equal_approx(_prev_vel):
			var raw := (velocity_vec - _prev_vel) / maxf(_since_vel_change, 1.0 / 120.0)
			_accel = _accel.lerp(raw, 0.55)
			_prev_vel = velocity_vec
			_since_vel_change = 0.0
		elif _since_vel_change > 0.12:
			_accel = _accel.lerp(Vector2.ZERO, 1.0 - exp(-dt / 0.09))
	var a_n := (_accel / ACCEL_REF).limit_length(1.2)

	# Interior inertia: a damped spring, so contents overshoot when you brake.
	var lag_target := -a_n * 0.20
	var lag_force := (lag_target - _lag) * 64.0 - _lag_v * 5.2
	_lag_v += lag_force * dt
	_lag += _lag_v * dt
	_lag = _lag.limit_length(0.34)

	# Frame angle follows the motion smoothly instead of snapping at 15 px/s.
	if speed > 15.0:
		_frame_ang = lerp_angle(_frame_ang, velocity_vec.angle(), 1.0 - exp(-16.0 * dt))
	else:
		_frame_ang = lerp_angle(_frame_ang, 0.0, 1.0 - exp(-5.0 * dt))
	if speed > 20.0:
		var back := -velocity_vec.normalized()
		_tail_dir = _tail_dir.lerp(back, 1.0 - exp(-9.0 * dt)).normalized()
	var tail := clampf((speed - 40.0) / 360.0, 0.0, 1.0) * 0.85
	if is_dashing:
		tail = 1.0

	# Breathing: amplitude scales with evolution (gentle baby → deep apex)
	var breath_t := clampf((clampf(growth_t, 1.0, 15.0) - 1.0) / 14.0, 0.0, 1.0)
	var breath_amp := lerpf(0.35, 1.0, smoothstep(0.0, 0.6, breath_t))
	_breath = (sin(_u_time * 2.35) * 0.65 + sin(_u_time * 0.9 + 1.3) * 0.35) * breath_amp
	_core_energy = move_toward(_core_energy, 0.0, dt * 0.55)
	# Update ring physics dynamics for current evolution stage
	_ring.set_evolution(growth_t)
	_gulp_eye = move_toward(_gulp_eye, 0.0, dt * 2.6)
	_wide_amt = move_toward(_wide_amt, 0.0, dt * 1.7)
	_electro_flash = move_toward(_electro_flash, 0.0, dt * 3.6)

	var ripple_speed := 1.15
	if _ripple_a.z < 1.0:
		_ripple_a.z += dt * ripple_speed
	if _ripple_h.z < 1.0:
		_ripple_h.z += dt * 1.3
	if _evo_t >= 0.0:
		_evo_t += dt * 0.9
		if _evo_t >= 1.0:
			_evo_t = -1.0

	# Electric channels charge on the mutation's own cadence.
	var el_lv := clampf(float(mutation_levels.get("electro_discharge", 0)) / 5.0, 0.0, 1.0)
	if el_lv > 0.0 and _electro_flash <= 0.0:
		_electro_cycle = fposmod(_electro_cycle + dt, 3.4)
	var charge := (_electro_cycle / 3.4) if el_lv > 0.0 else 0.0

	var r0 := _body_radius()

	# Ring: static buds for ranged_absorb, tentacle roots, then the physics step.
	_ring.clear_bumps()
	var rng_lv := int(mutation_levels.get("ranged_absorb", 0))
	if rng_lv > 0:
		for b in range(3):
			var ba := _u_time * 0.05 + float(b) * TAU / 3.0 + 0.4
			_ring.set_bump(ba, 0.030 + 0.012 * sin(_u_time * 1.7 + float(b) * 2.0), 1.1)
	if _tentacles != null:
		var local_pts: Array[Vector2] = []
		for w in active_tendril_targets:
			local_pts.append(to_local(w))
		_tentacles.update_state(local_pts, r0, _u_time, dt, stealth_alpha * (1.0 - death_progress),
			_body_color, _rim_color, rng_lv, bool(active_synergies.get("bio_vampirism", false)))
		for s in _tentacles.slot_info():
			_ring.set_bump(float(s["angle"]), 0.115 * float(s["ext"]), 1.25)
	var swim := clampf(speed / 300.0, 0.0, 1.0)
	_ring.step(dt, a_n, swim, _u_time)
	var swell := gulp_bulge * 0.10 - death_progress * 0.04

	# Screen scale for refraction strength.
	var vp := get_viewport()
	if vp != null:
		var xf := vp.get_final_transform() * get_global_transform_with_canvas()
		_px_per_unit = maxf(xf.get_scale().x * r0, 8.0)

	# Body quad: world-aligned, never rotated.
	if _jelly_rect != null:
		var box := r0 * EXTENT * 2.0
		_jelly_rect.size = Vector2(box, box)
		_jelly_rect.position = -Vector2(box, box) * 0.5
		_jelly_rect.pivot_offset = Vector2(box, box) * 0.5
		_jelly_rect.rotation = 0.0
		_jelly_rect.scale = Vector2.ONE

	if _shader_mat != null:
		var m := _shader_mat
		m.set_shader_parameter(&"extent", EXTENT)
		m.set_shader_parameter(&"u_time", _u_time)
		m.set_shader_parameter(&"px_per_unit", _px_per_unit)
		m.set_shader_parameter(&"quality", quality)
		m.set_shader_parameter(&"breath", _breath)
		m.set_shader_parameter(&"core_energy", _core_energy)
		m.set_shader_parameter(&"frame_dir", Vector2.from_angle(_frame_ang))
		m.set_shader_parameter(&"squash", squash_stretch)
		m.set_shader_parameter(&"tail_dir", _tail_dir)
		m.set_shader_parameter(&"tail", tail)
		m.set_shader_parameter(&"ring", _ring.output(swell))
		m.set_shader_parameter(&"lag", _lag)
		m.set_shader_parameter(&"ripple_a", _ripple_a)
		m.set_shader_parameter(&"ripple_h", _ripple_h)
		m.set_shader_parameter(&"evo_t", _evo_t)
		var stg := float(stage)
		m.set_shader_parameter(&"core_style", clampf(1.0 - absf(stg - 8.0) / 3.0, 0.0, 1.0))
		m.set_shader_parameter(&"detail", clampf((growth_t - 1.0) / 14.0 + 0.15, 0.0, 1.0))
		m.set_shader_parameter(&"electro_level", el_lv)
		m.set_shader_parameter(&"electro_charge", charge)
		m.set_shader_parameter(&"electro_flash", _electro_flash)
		m.set_shader_parameter(&"electro_seed", _electro_seed)
		# --- evolution structural params (6 artistic chapters from growth_t) ---
		var gt := clampf(growth_t, 1.0, 15.0)
		var t01 := (gt - 1.0) / 14.0  # 0.0 at stage 1, 1.0 at stage 15
		# Chapter 1: Primordial Drop (1-2) — nearly everything at minimum
		# Chapter 2: Awakening (3-5) — first signs of structure
		# Chapter 3: Adaptation (6-8) — the current "sweet spot"
		# Chapter 4: Predator (9-11) — deepening complexity
		# Chapter 5: Apex Mutation (12-14) — approaching peak
		# Chapter 6: Perfect Form (15) — maximum biological beauty
		# Membrane: smooth baby → complex ridged apex
		m.set_shader_parameter(&"evo_membrane", clampf(smoothstep(0.05, 0.85, t01), 0.0, 1.0))
		# Core complexity: simple dot → multi-lobe nucleus
		m.set_shader_parameter(&"evo_core_cx", clampf(smoothstep(0.25, 0.90, t01), 0.0, 1.0))
		# Vesicles: none → full field (onset at stage 3)
		m.set_shader_parameter(&"evo_vesicles", clampf(smoothstep(0.10, 0.70, t01), 0.0, 1.0))
		# Fibrils: none → full network (onset at stage 4)
		m.set_shader_parameter(&"evo_fibrils", clampf(smoothstep(0.15, 0.75, t01), 0.0, 1.0))
		# Bioluminescence: faint → vivid
		m.set_shader_parameter(&"evo_biolum", clampf(smoothstep(0.0, 0.80, t01), 0.0, 1.0))
		# Organelles: none → visible (onset at stage 9)
		m.set_shader_parameter(&"evo_organelles", clampf(smoothstep(0.50, 0.95, t01), 0.0, 1.0))
		# Silhouette asymmetry: round → subtly organic
		m.set_shader_parameter(&"evo_asym", clampf(smoothstep(0.30, 0.90, t01) * 0.25, 0.0, 0.30))
		# Opacity: transparent baby → opaque apex
		m.set_shader_parameter(&"evo_opacity", clampf(lerpf(0.35, 1.0, smoothstep(0.0, 0.70, t01)), 0.35, 1.0))
		# Eye scale: bigger at baby (1.3), normal at apex (1.0)
		m.set_shader_parameter(&"evo_eye_scale", lerpf(1.30, 1.0, smoothstep(0.0, 0.55, t01)))

	_update_face(delta, r0)
	_update_swallowed(dt)
	_update_shield(dt, r0)
	if _bolts != null:
		_bolts.set_radius(r0)

	# Regalia: this style grows organs, not ornaments. The aura keeps ascension stars.
	var alpha_mult := stealth_alpha * (1.0 - death_progress)
	var eff_r := radius * (1.0 + gulp_bulge * 0.25)
	if is_dying:
		eff_r *= 1.0 + death_progress * 0.45
	var slim_look := _look.duplicate()
	for k: String in ["sigil", "crown", "halo", "wings", "horns", "motes", "petals"]:
		slim_look[k] = 0.0
	if _back_aura != null:
		_back_aura.set_look(slim_look, eff_r, _anim_time, alpha_mult)
	if _front_aura != null:
		_front_aura.set_look(slim_look, eff_r, _anim_time, alpha_mult)

	if _inner != null:
		_inner.queue_redraw()


func _update_face(delta: float, r0: float) -> void:
	if _eyes_rect == null or _eyes_mat == null:
		return
	var hurt := clampf(hurt_flash * 1.7, 0.0, 1.0)
	var want_blink := 1.0 if _blink_open < 0.3 else 0.0
	var rate := 16.0 if want_blink > _blink_amt else 9.0
	_blink_amt = move_toward(_blink_amt, want_blink, delta * rate)
	var squeeze := maxf(hurt * 0.86, _gulp_eye * 0.40)
	var closed := clampf(maxf(_blink_amt, squeeze), 0.0, 1.0)
	if is_dying:
		closed = maxf(closed, death_progress)

	var hunting := (not active_tendril_targets.is_empty()) or is_dashing
	var tilt := 0.13 + (0.10 if hunting else 0.0) + hurt * 0.55
	var droop := 0.14 - (0.10 if hunting else 0.0)
	var wide := _wide_amt * 0.7 + (0.18 if hunting else 0.0)

	# Eye size scales with evolution: bigger relative eyes at baby stage (cute factor)
	var eye_scale := lerpf(1.30, 1.0, smoothstep(0.0, 0.55, (clampf(growth_t, 1.0, 15.0) - 1.0) / 14.0))
	var eye_px := clampf(r0 * 0.215 * eye_scale, 4.4, 13.0)
	var rect_sz := Vector2(r0 * 1.8 * eye_scale, r0 * 1.0 * eye_scale)
	var face_c := _shell_to_canvas(Vector2(0.0, FACE_Y), r0)
	# Eyes track look_dir more strongly when hunting (following prey/threat)
	var look_strength := 0.14 + (0.10 if hunting else 0.0)
	var parallax := _lag * r0 * 0.50 + look_dir.normalized() * r0 * look_strength
	var ea := _shell_to_canvas(Vector2(-EYE_SEP, FACE_Y), r0) - face_c + parallax
	var eb := _shell_to_canvas(Vector2(EYE_SEP, FACE_Y), r0) - face_c + parallax
	_eyes_rect.size = rect_sz
	_eyes_rect.position = face_c - rect_sz * 0.5
	_eyes_rect.visible = not is_dying or death_progress < 0.95
	var iris := _core_color.lerp(Color(1.0, 0.78, 0.48), 0.6)
	var look_n := look_dir.normalized() if look_dir.length_squared() > 0.01 else Vector2.DOWN
	_eyes_mat.set_shader_parameter(&"rect_px", rect_sz)
	_eyes_mat.set_shader_parameter(&"eye_a", ea)
	_eyes_mat.set_shader_parameter(&"eye_b", eb)
	_eyes_mat.set_shader_parameter(&"eye_px", eye_px)
	_eyes_mat.set_shader_parameter(&"look", look_n)
	_eyes_mat.set_shader_parameter(&"blink", closed)
	_eyes_mat.set_shader_parameter(&"tilt", tilt)
	_eyes_mat.set_shader_parameter(&"droop", droop)
	_eyes_mat.set_shader_parameter(&"wide", wide)
	_eyes_mat.set_shader_parameter(&"iris_col", iris)
	_eyes_mat.set_shader_parameter(&"lid_col", _body_color.darkened(0.12))
	_eyes_mat.set_shader_parameter(&"alpha", stealth_alpha * (1.0 - death_progress))
	_eyes_mat.set_shader_parameter(&"energy", clampf(_core_energy, 0.0, 1.0))


func _update_swallowed(dt: float) -> void:
	var alive: Array[Dictionary] = []
	for g in _swallowed:
		g["t"] = float(g["t"]) + dt * 0.95
		if float(g["t"]) >= 0.78 and not bool(g["fed"]):
			g["fed"] = true
			_core_energy = minf(_core_energy + 0.55, 1.2)
		if float(g["t"]) < 1.0:
			alive.append(g)
	_swallowed = alive


func _update_shield(dt: float, r0: float) -> void:
	if _shield_node == null:
		return
	var el := _shield_node
	el.quality = quality
	el.update_state(dt, r0, shield_active and not is_dying, _frame_ang, squash_stretch,
		_body_color, stealth_alpha * (1.0 - death_progress), bool(active_synergies.get("ice_armor", false)))


## --- drawing -------------------------------------------------------------------------

func _draw() -> void:
	_draw_ground()
	# Draw organic mutations BEFORE super (which draws flat ones)
	_draw_organic_mutations()
	super._draw()


## Organic mutation visuals that replace the base class's flat geometric draws.
## Each mutation is rendered in the Claude biological style: smooth curves, membrane
## integration, vesicle-like particles, and stage-appropriate glow.
func _draw_organic_mutations() -> void:
	var eff_r := radius * (1.0 + gulp_bulge * 0.22)
	var a := stealth_alpha * (1.0 - death_progress)
	if a < 0.01:
		return
	var t := _u_time

	# --- Spikes: membrane barbs (organic thorns that emerge from folds) ---
	var spike_lv := int(mutation_levels.get("spikes", 0))
	if spike_lv > 0:
		var spike_cnt: int = 6 + spike_lv
		var is_piercing := bool(active_synergies.get("piercing_strike", false))
		# Organic barbs: soft pink/coral base, bright tip, slight curve
		var base_col := Color(1.0, 0.55, 0.65, 0.85 * a) if not is_piercing else Color(1.0, 0.88, 0.42, 0.90 * a)
		var tip_col := Color(1.0, 0.90, 0.95, 0.92 * a) if not is_piercing else Color(1.0, 1.0, 0.85, 0.95 * a)
		for i in range(spike_cnt):
			var ang := (TAU / float(spike_cnt)) * float(i) + t * 0.3
			var dir := Vector2.from_angle(ang)
			var perp := dir.orthogonal()
			# Curved organic barb shape (wider base, tapered tip with subtle bend)
			var barb_len := eff_r * (0.32 + 0.08 * sin(t * 1.5 + float(i) * 1.7))
			var b0 := dir * (eff_r * 0.88) - perp * (eff_r * 0.10)
			var b1 := dir * (eff_r * 0.88) + perp * (eff_r * 0.10)
			var mid := dir * (eff_r * 0.88 + barb_len * 0.55) + perp * (eff_r * 0.03 * sin(t * 2.0 + float(i)))
			var tip := dir * (eff_r * 0.88 + barb_len) + perp * (eff_r * 0.015 * sin(t * 3.0 + float(i) * 2.3))
			# Draw as smooth polyline instead of harsh triangle
			draw_colored_polygon(PackedVector2Array([b0, mid - perp * eff_r * 0.04, tip, mid + perp * eff_r * 0.04, b1]), base_col)
			draw_line(mid, tip, tip_col, 1.8)
			# Glow at base where barb emerges from membrane
			draw_circle(dir * (eff_r * 0.90), eff_r * 0.045, Color(base_col.r, base_col.g, base_col.b, 0.3 * a))

	# --- Dash: bioluminescent thrust bubble trail ---
	if int(mutation_levels.get("dash", 0)) > 0 and is_dashing:
		var jet_dir := (-velocity_vec.normalized()) if velocity_vec.length() > 1.0 else Vector2.UP
		# Instead of one flat circle: trail of luminous bubbles
		for i in range(5):
			var fi := float(i)
			var off := jet_dir * (eff_r * (0.95 + fi * 0.28))
			var bubble_r := eff_r * (0.22 - fi * 0.03)
			var fade := (1.0 - fi * 0.18)
			var col := Color(1.0, 0.82 + fi * 0.03, 0.45 + fi * 0.10, 0.65 * fade * a)
			off += jet_dir.orthogonal() * sin(t * 12.0 + fi * 2.0) * eff_r * 0.06
			draw_circle(off, bubble_r, col)
			# Specular highlight on each bubble
			draw_circle(off - jet_dir * bubble_r * 0.3, bubble_r * 0.25, Color(1.0, 1.0, 0.95, 0.5 * fade * a))

	# --- Magnet: organic field lines emanating from core ---
	if int(mutation_levels.get("magnet", 0)) > 0:
		var is_em := bool(active_synergies.get("em_storm", false))
		var mag_col := Color(0.45, 0.92, 1.0, 0.25 * a) if not is_em else Color(1.0, 0.95, 0.50, 0.40 * a)
		for i in range(8):
			var fi := float(i)
			var ang := (TAU / 8.0) * fi + t * 0.6
			var start_p := Vector2.from_angle(ang) * (eff_r * 0.5)
			var end_p := Vector2.from_angle(ang + 0.15 * sin(t * 2.0 + fi)) * (eff_r * 1.35)
			var mid_p := (start_p + end_p) * 0.5 + Vector2.from_angle(ang).orthogonal() * eff_r * 0.15 * sin(t * 3.0 + fi * 1.5)
			draw_polyline(PackedVector2Array([start_p, mid_p, end_p]), mag_col, 1.6)

	# --- Speed boost: streamlined fin membranes ---
	if int(mutation_levels.get("speed_boost", 0)) > 0:
		var back_ang := (velocity_vec.angle() + PI) if velocity_vec.length() > 15.0 else -PI * 0.5
		var fin_col := Color(0.50, 1.0, 0.90, 0.70 * a) if not slipstream_active else Color(0.60, 1.0, 0.95, 0.85 * a)
		for side_f: float in [-0.50, 0.50]:
			var fin_dir := Vector2.from_angle(back_ang + side_f)
			var perp := fin_dir.orthogonal()
			# Organic membrane fin: curved, translucent
			var p0 := fin_dir * (eff_r * 0.80) + perp * (eff_r * 0.06)
			var p1 := fin_dir * (eff_r * 0.80) - perp * (eff_r * 0.06)
			var pm := fin_dir * (eff_r * 1.10) + perp * (eff_r * 0.18 * sin(t * 4.0 + side_f * 3.0))
			var pt := fin_dir * (eff_r * (1.38 if slipstream_active else 1.26))
			draw_colored_polygon(PackedVector2Array([p0, pm, pt, p1]), fin_col)
			# Translucent membrane vein
			draw_line(fin_dir * (eff_r * 0.82), pt, Color(fin_col.r, fin_col.g, fin_col.b, 0.4 * a), 1.2)
		if slipstream_active:
			# Wake turbulence bubbles
			for i in range(3):
				var fi := float(i)
				var bp := Vector2.from_angle(back_ang + sin(t * 5.0 + fi * 2.0) * 0.3) * (eff_r * (1.20 + fi * 0.15))
				draw_circle(bp, eff_r * 0.05, Color(0.55, 1.0, 0.95, 0.35 * a))

	# --- Regeneration: pulsing emerald organelles + healing aura ---
	if int(mutation_levels.get("regeneration", 0)) > 0:
		var regen_pulse := 0.5 + 0.5 * sin(t * 3.0)
		for i in range(4):
			var fi := float(i)
			var oa := t * 1.2 + fi * (TAU / 4.0)
			var orb := eff_r * (0.38 + 0.06 * sin(t * 1.8 + fi * 2.0))
			var op := Vector2.from_angle(oa) * orb
			var rv := eff_r * (0.055 + 0.015 * regen_pulse)
			# Emerald vesicle with bright center
			draw_circle(op, rv * 1.5, Color(0.35, 0.90, 0.40, 0.20 * a))
			draw_circle(op, rv, Color(0.50, 1.0, 0.55, 0.75 * a))
			draw_circle(op - Vector2(rv * 0.3, rv * 0.3), rv * 0.3, Color(0.85, 1.0, 0.85, 0.55 * a))
		# Healing aura ring
		var aura_a := 0.10 + 0.08 * regen_pulse
		draw_arc(Vector2.ZERO, eff_r * 0.95, 0.0, TAU, 32, Color(0.45, 1.0, 0.55, aura_a * a), 1.5)

	# --- Poison trail: dripping toxic vesicles on membrane underside ---
	if int(mutation_levels.get("poison_trail", 0)) > 0:
		for i in range(5):
			var fi := float(i)
			var pa := fi * (TAU / 5.0) - t * 0.5
			var drip_y := sin(t * 2.5 + fi * 1.7) * 0.1 + 0.08
			var pp := Vector2.from_angle(pa) * (eff_r * 0.72) + Vector2(0, eff_r * drip_y)
			var rv := eff_r * 0.04
			draw_circle(pp, rv * 1.8, Color(0.55, 0.85, 0.15, 0.18 * a))
			draw_circle(pp, rv, Color(0.65, 1.0, 0.20, 0.70 * a))
			# Drip trail
			var drip_end := pp + Vector2(0, eff_r * 0.10 * (0.5 + 0.5 * sin(t * 3.0 + fi)))
			draw_line(pp, drip_end, Color(0.65, 1.0, 0.20, 0.35 * a), 1.2)

	# --- Split: mitotic groove with budding daughter nucleus ---
	if int(mutation_levels.get("split", 0)) > 0:
		var groove_ang := t * 0.4
		var groove_dir := Vector2.from_angle(groove_ang)
		var groove_perp := groove_dir.orthogonal()
		# Constriction groove across body
		var groove_depth := 0.5 + 0.5 * sin(t * 1.5)
		for i in range(8):
			var fi := float(i) / 7.0 - 0.5
			var gp := groove_perp * (eff_r * fi * 1.4)
			var indent := groove_dir * (eff_r * 0.03 * groove_depth * (1.0 - fi * fi * 4.0))
			draw_circle(gp + indent, eff_r * 0.02, Color(0.85, 0.80, 1.0, 0.35 * a * groove_depth))
		# Budding daughter nucleus
		var bud_pos := groove_dir * (eff_r * 0.35)
		var bud_r := eff_r * (0.11 + 0.03 * sin(t * 2.0))
		draw_circle(bud_pos, bud_r * 1.3, Color(1.0, 0.95, 0.80, 0.20 * a))
		draw_circle(bud_pos, bud_r, Color(1.0, 0.98, 0.85, 0.65 * a))

	# --- Freeze: crystalline ice facets on membrane ---
	if int(mutation_levels.get("freeze", 0)) > 0:
		for i in range(6):
			var fi := float(i)
			var fa := fi * (TAU / 6.0) + t * 0.15
			var fp := Vector2.from_angle(fa) * (eff_r * 1.02)
			var fperp := Vector2.from_angle(fa).orthogonal()
			# Hexagonal ice crystal
			var cr := eff_r * (0.06 + 0.02 * sin(t * 0.8 + fi * 1.3))
			var pts := PackedVector2Array()
			for j in range(6):
				var ca := float(j) * (TAU / 6.0) + fa
				pts.append(fp + Vector2.from_angle(ca) * cr)
			draw_colored_polygon(pts, Color(0.82, 0.95, 1.0, 0.55 * a))
			draw_polyline(pts, Color(0.90, 0.98, 1.0, 0.70 * a), 1.0)
			# Inner sparkle
			draw_circle(fp, cr * 0.3, Color(1.0, 1.0, 1.0, 0.45 * a))

	# --- Mimicry: camouflage ripple along membrane ---
	if int(mutation_levels.get("mimicry", 0)) > 0:
		# Adaptive camouflage: subtle rippling pattern
		var camo_a := 0.3 + 0.2 * sin(t * 1.5)
		for i in range(12):
			var fi := float(i)
			var ca := fi * (TAU / 12.0) + sin(t * 0.3 + fi * 0.5) * 0.2
			var cp := Vector2.from_angle(ca) * (eff_r * (0.90 + 0.05 * sin(t * 2.0 + fi * 1.3)))
			var cr := eff_r * (0.04 + 0.02 * sin(t * 1.7 + fi * 2.1))
			# Sampled environment color approximation (shifts through greens/darks)
			var env_hue := 0.33 + 0.08 * sin(t * 0.5 + fi * 0.7)
			var env_col := Color.from_hsv(env_hue, 0.35, 0.45, camo_a * a)
			draw_circle(cp, cr, env_col)


## Contact shadow + coloured light pool. Light is top-left, so shadow falls down-right.
func _draw_ground() -> void:
	var r0 := _body_radius()
	var a := stealth_alpha * (1.0 - death_progress)
	var sq := squash_stretch
	var evo_t01 := clampf((clampf(growth_t, 1.0, 15.0) - 1.0) / 14.0, 0.0, 1.0)
	# Shadow: fewer rings at baby stage (cleaner small look)
	var shadow_strength := lerpf(0.4, 1.0, smoothstep(0.0, 0.4, evo_t01))
	var off := Vector2(0.10, 0.34) * r0
	draw_set_transform(off, 0.0, Vector2(sq.x * 0.98, sq.y * 0.62))
	for i in range(7):
		var f := float(i) / 6.0
		var rr := r0 * lerpf(1.28, 0.70, f)
		draw_circle(Vector2.ZERO, rr, Color(0.02, 0.02, 0.09, (0.045 + 0.035 * f) * a * shadow_strength))
	# Glow pool: scales with bioluminescence evolution
	var glow_evo := smoothstep(0.1, 0.7, evo_t01)
	draw_set_transform(Vector2(0.0, r0 * 0.30), 0.0, Vector2(1.0, 0.70))
	var glow_a := (0.02 + 0.06 * glow_evo + 0.07 * clampf(_core_energy, 0.0, 1.0)) * a
	for i in range(4):
		var f2 := float(i) / 3.0
		draw_circle(Vector2.ZERO, r0 * lerpf(2.0, 1.25, f2),
			Color(_body_color.r, _body_color.g, _body_color.b, glow_a * (0.5 + 0.5 * f2)))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


## Swallowed prey, seen THROUGH the jelly: soft, tinted by the body, drifting to the
## core and dissolving into light.
func _draw_inner() -> void:
	if _swallowed.is_empty():
		return
	var r0 := _body_radius()
	var alpha_mult := stealth_alpha * (1.0 - death_progress)
	var core_pos := _shell_to_canvas(Vector2(0.0, CORE_Y), r0) + _lag * r0
	for g in _swallowed:
		var t := float(g["t"])
		var from := g["from"] as Vector2
		var e := smoothstep(0.0, 1.0, t)
		var pos := from.lerp(core_pos, e)
		# A little sideways wander so it reads as being carried, not slid.
		pos += (core_pos - from).orthogonal().normalized() * sin(t * 7.0) * r0 * 0.06 * (1.0 - t)
		var pc: Color = g["color"]
		var base_sz := float(g["size"])
		var sz := base_sz * (1.0 - 0.80 * t)
		var fade := (1.0 - smoothstep(0.55, 1.0, t))
		var a := fade * 0.80 * alpha_mult
		if a <= 0.01:
			continue
		var tint := pc.lerp(_core_color, smoothstep(0.2, 0.9, t) * 0.7)
		# trail
		for k in range(3):
			var kt := maxf(t - 0.06 * float(k + 1), 0.0)
			var kp := from.lerp(core_pos, smoothstep(0.0, 1.0, kt))
			_inner.draw_circle(kp, sz * (0.8 - 0.18 * float(k)), Color(tint.r, tint.g, tint.b, a * 0.22))
		_inner.draw_circle(pos, sz * 1.5, Color(tint.r, tint.g, tint.b, a * 0.20))
		_inner.draw_circle(pos, sz * 1.12, Color(tint.darkened(0.45).r, tint.darkened(0.45).g, tint.darkened(0.45).b, a * 0.55))
		_inner.draw_circle(pos, sz, Color(tint.r, tint.g, tint.b, a))
		_inner.draw_circle(pos + Vector2(-sz * 0.30, -sz * 0.32), sz * 0.34, Color(1.0, 1.0, 1.0, a * 0.70))
		if t > 0.5:
			for i in range(5):
				var ma := TAU * float(i) / 5.0 + _u_time * 3.1
				var mp := pos + Vector2.from_angle(ma) * sz * (1.3 + (t - 0.5) * 3.0)
				_inner.draw_circle(mp, maxf(sz * 0.14, 0.8), Color(tint.r, tint.g, tint.b, a * 0.8))
