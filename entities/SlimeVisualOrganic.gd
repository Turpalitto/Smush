class_name SlimeVisualOrganic
extends SlimeVisual
## EXPERIMENTAL organic body style (GLM visual prototype). Drop-in replacement for
## SlimeVisual inside the visual lab; the shipped game keeps instantiating the base
## class, so nothing here affects the current look unless the owner opts in later.
##
## What it adds on top of the base:
##   * swaps the body shader to shaders/slime_body_organic.gdshader (same uniform
##     contract, so palettes and growth still come from EvolutionStages unchanged);
##   * a six-phase anatomy driven by the SAME 15 stages (below): organelles, nucleus,
##     dendritic veins, internal currents, membrane definition, self-glow and
##     silhouette waviness all grow along the ladder, grouped into
##     Primordial Drop / Awakening / Adaptation / Predator / Apex / Perfect Form;
##   * inertial contents: the interior lags behind acceleration and overshoots on
##     braking, from one velocity-EMA signal;
##   * an absorption ripple + a swallowed-prey ghost that drifts toward the nucleus
##     and dissolves (visual only — mass math stays instant in the game);
##   * organic variants of ranged_absorb / shield / electro_discharge drawn by
##     OrganicTendrils / OrganicShield / OrganicElectro (base switches flagged off).

## Anatomy weights per stage, 0..1. Ordered exactly like EvolutionStages.STAGES so
## `anatomy_at` can lerp between rows with the same fractional growth_t. These are
## the six phases required by the design brief:
##   1-2 Primordial Drop · 3-5 Awakening · 6-8 Adaptation · 9-11 Predator ·
##   12-14 Apex Mutation · 15 Perfect Form.
## Keys: organelles, membrane, nucleus, veins, flow, glow, silhouette.
const ANATOMY: Array[Dictionary] = [
	{"organelles": 0.06, "membrane": 0.10, "nucleus": 0.14, "veins": 0.00, "flow": 0.14, "glow": 0.22, "silhouette": 0.04},
	{"organelles": 0.12, "membrane": 0.18, "nucleus": 0.22, "veins": 0.00, "flow": 0.22, "glow": 0.30, "silhouette": 0.08},
	{"organelles": 0.22, "membrane": 0.26, "nucleus": 0.34, "veins": 0.06, "flow": 0.34, "glow": 0.38, "silhouette": 0.14},
	{"organelles": 0.30, "membrane": 0.34, "nucleus": 0.44, "veins": 0.12, "flow": 0.42, "glow": 0.45, "silhouette": 0.18},
	{"organelles": 0.40, "membrane": 0.44, "nucleus": 0.54, "veins": 0.20, "flow": 0.50, "glow": 0.52, "silhouette": 0.24},
	{"organelles": 0.48, "membrane": 0.52, "nucleus": 0.60, "veins": 0.28, "flow": 0.56, "glow": 0.56, "silhouette": 0.30},
	{"organelles": 0.56, "membrane": 0.60, "nucleus": 0.68, "veins": 0.36, "flow": 0.62, "glow": 0.62, "silhouette": 0.35},
	{"organelles": 0.64, "membrane": 0.68, "nucleus": 0.74, "veins": 0.44, "flow": 0.68, "glow": 0.68, "silhouette": 0.40},
	{"organelles": 0.72, "membrane": 0.74, "nucleus": 0.80, "veins": 0.52, "flow": 0.74, "glow": 0.72, "silhouette": 0.46},
	{"organelles": 0.78, "membrane": 0.79, "nucleus": 0.85, "veins": 0.60, "flow": 0.79, "glow": 0.77, "silhouette": 0.50},
	{"organelles": 0.84, "membrane": 0.84, "nucleus": 0.90, "veins": 0.68, "flow": 0.84, "glow": 0.82, "silhouette": 0.55},
	{"organelles": 0.90, "membrane": 0.90, "nucleus": 0.94, "veins": 0.76, "flow": 0.88, "glow": 0.85, "silhouette": 0.60},
	{"organelles": 0.95, "membrane": 0.95, "nucleus": 0.97, "veins": 0.83, "flow": 0.93, "glow": 0.89, "silhouette": 0.65},
	{"organelles": 1.00, "membrane": 1.00, "nucleus": 1.00, "veins": 0.90, "flow": 1.00, "glow": 0.93, "silhouette": 0.70},
	{"organelles": 1.00, "membrane": 1.00, "nucleus": 1.00, "veins": 1.00, "flow": 1.00, "glow": 1.00, "silhouette": 0.78},
]

const PHASE_NAMES_RU: Array[String] = [
	"Первородная капля", "Пробуждение", "Адаптация",
	"Хищник", "Апекс-мутация", "Совершенная форма",
]

var quality: int = 2

var _u_time: float = 0.0
var _vel_lag: Vector2 = Vector2.ZERO

# Secondary Motion Hierarchy states (membrane, nucleus, organelles):
var _prev_vel: Vector2 = Vector2.ZERO
var _accel: Vector2 = Vector2.ZERO
var _since_vel_change: float = 0.0
const ACCEL_REF: float = 1200.0

var _lag_membrane: Vector2 = Vector2.ZERO
var _lag_membrane_v: Vector2 = Vector2.ZERO

var _lag_nucleus: Vector2 = Vector2.ZERO
var _lag_nucleus_v: Vector2 = Vector2.ZERO

var _lag_organelles: Vector2 = Vector2.ZERO
var _lag_organelles_v: Vector2 = Vector2.ZERO

var _absorb_pulse: float = 0.0
var _absorb_dir: Vector2 = Vector2(0.0, 1.0)
var _electro_cycle: float = 0.0
var _electro_flash_v: float = 0.0
var _tendrils: OrganicTendrils
var _shield_node: OrganicShield
var _electro_node: OrganicElectro
var _swallowed: Array[Dictionary] = []
var _anatomy: Dictionary = {}


func _ready() -> void:
	super._ready()
	organic_tendrils = true
	organic_shield = true
	organic_electro = true
	var shader := load("res://shaders/slime_body_organic.gdshader") as Shader
	if shader != null and _shader_mat != null:
		_shader_mat.shader = shader
	_tendrils = OrganicTendrils.new()
	_tendrils.name = "OrganicTendrils"
	add_child(_tendrils)
	_shield_node = OrganicShield.new()
	_shield_node.name = "OrganicShield"
	add_child(_shield_node)
	_electro_node = OrganicElectro.new()
	_electro_node.name = "OrganicElectro"
	add_child(_electro_node)


## Phase index 1..6 for an integer stage — the only place the grouping lives.
static func phase_of_stage(stage: int) -> int:
	if stage >= 15:
		return 6
	if stage >= 12:
		return 5
	if stage >= 9:
		return 4
	if stage >= 6:
		return 3
	if stage >= 3:
		return 2
	return 1


## Continuous anatomy at a fractional ladder position, lerped exactly like
## EvolutionStages.look_at lerps the palette.
static func anatomy_at(growth_t: float) -> Dictionary:
	var tt := clampf(growth_t, 1.0, 15.0)
	var i := clampi(int(floorf(tt)) - 1, 0, ANATOMY.size() - 1)
	var j := mini(i + 1, ANATOMY.size() - 1)
	var w := tt - floorf(tt)
	var a := ANATOMY[i]
	var b := ANATOMY[j]
	var out := {}
	for k: String in ["organelles", "membrane", "nucleus", "veins", "flow", "glow", "silhouette"]:
		out[k] = lerpf(float(a[k]), float(b[k]), w)
	return out


## Visual-only swallow: ripple + ghost. The game's complete_absorption keeps doing
## the real mass/XP work instantly; this never gates it.
func trigger_swallow(local_entry: Vector2, prey_color: Color, prey_size: float) -> void:
	_absorb_pulse = 1.0
	_absorb_dir = local_entry.normalized() if local_entry.length_squared() > 0.001 else Vector2(0.0, 1.0)
	trigger_gulp()
	_swallowed.append({
		"from": local_entry.limit_length(radius * 0.85),
		"t": 0.0,
		"color": prey_color,
		"size": clampf(prey_size, 2.0, radius * 0.30),
	})
	if _swallowed.size() > 4:
		_swallowed.pop_front()


func trigger_shield_impact(local_dir: Vector2) -> void:
	if _shield_node != null:
		_shield_node.trigger_impact(local_dir)


func trigger_electro_flash() -> void:
	_electro_flash_v = 1.0
	_electro_cycle = 0.0


func set_quality(q: int) -> void:
	quality = clampi(q, 0, 2)
	# Write through immediately: the lab's capture/perf modes read the uniform in
	# the same frame they set it, and _process only flushes once per frame.
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("quality", quality)
	if _shield_node != null:
		_shield_node.quality = quality


func _process(delta: float) -> void:
	super._process(delta)
	var dt := clampf(delta, 0.0001, 0.05)
	_u_time += dt

	# Secondary Motion Hierarchy: sample acceleration from velocity changes
	_since_vel_change += dt
	if not velocity_vec.is_equal_approx(_prev_vel):
		var raw_a := (velocity_vec - _prev_vel) / maxf(_since_vel_change, 0.008)
		_accel = _accel.lerp(raw_a, 0.60)
		_prev_vel = velocity_vec
		_since_vel_change = 0.0
	elif _since_vel_change > 0.10:
		_accel = _accel.lerp(Vector2.ZERO, 1.0 - exp(-dt / 0.08))

	var a_n := (_accel / ACCEL_REF).limit_length(1.2)

	# 1. Membrane spring: fast, elastic, responsive with crisp overshoot on braking
	var target_m := -a_n * 0.22
	var force_m := (target_m - _lag_membrane) * 220.0 - _lag_membrane_v * 16.0
	_lag_membrane_v += force_m * dt
	_lag_membrane += _lag_membrane_v * dt
	_lag_membrane = _lag_membrane.limit_length(0.32)

	# 2. Nucleus spring: heavy viscoelastic inner organ (low frequency, strong damping)
	var target_n := -a_n * 0.22
	var force_n := (target_n - _lag_nucleus) * 65.0 - _lag_nucleus_v * 14.0
	_lag_nucleus_v += force_n * dt
	_lag_nucleus += _lag_nucleus_v * dt
	_lag_nucleus = _lag_nucleus.limit_length(0.20)

	# 3. Organelle spring: intermediate lattice lag with subtle phase difference
	var target_o := -a_n * 0.24
	var force_o := (target_o - _lag_organelles) * 120.0 - _lag_organelles_v * 14.0
	_lag_organelles_v += force_o * dt
	_lag_organelles += _lag_organelles_v * dt
	_lag_organelles = _lag_organelles.limit_length(0.28)

	# Compatibility blended lag vector
	_vel_lag = _lag_membrane * 0.5 + _lag_nucleus * 0.5

	_absorb_pulse = maxf(0.0, _absorb_pulse - delta * 1.5)
	_electro_flash_v = maxf(0.0, _electro_flash_v - delta * 3.4)

	var eff_r := radius * (1.0 + gulp_bulge * 0.25)
	_anatomy = anatomy_at(growth_t)
	var lv := clampf(float(mutation_levels.get("electro_discharge", 0)) / 5.0, 0.0, 1.0)
	if lv > 0.0 and _electro_flash_v <= 0.0:
		_electro_cycle = fposmod(_electro_cycle + delta, 3.4)
	var charge := (_electro_cycle / 3.4) if lv > 0.0 else 0.0

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("u_time", _u_time)
		_shader_mat.set_shader_parameter("quality", quality)
		_shader_mat.set_shader_parameter("lag_vec", _vel_lag)
		_shader_mat.set_shader_parameter("lag_membrane", _lag_membrane)
		_shader_mat.set_shader_parameter("lag_nucleus", _lag_nucleus)
		_shader_mat.set_shader_parameter("lag_organelles", _lag_organelles)
		_shader_mat.set_shader_parameter("absorb_pulse", _absorb_pulse)
		_shader_mat.set_shader_parameter("absorb_dir", _absorb_dir)
		_shader_mat.set_shader_parameter("organelles", float(_anatomy.get("organelles", 0.0)))
		_shader_mat.set_shader_parameter("membrane_w", float(_anatomy.get("membrane", 0.0)))
		_shader_mat.set_shader_parameter("nucleus_w", float(_anatomy.get("nucleus", 0.0)))
		_shader_mat.set_shader_parameter("veins_w", float(_anatomy.get("veins", 0.0)))
		_shader_mat.set_shader_parameter("flow_w", float(_anatomy.get("flow", 0.0)))
		_shader_mat.set_shader_parameter("inner_glow", float(_anatomy.get("glow", 0.0)))
		_shader_mat.set_shader_parameter("silhouette_w", float(_anatomy.get("silhouette", 0.0)))
		_shader_mat.set_shader_parameter("electro_level", lv)
		_shader_mat.set_shader_parameter("electro_charge", charge)
		_shader_mat.set_shader_parameter("electro_flash", _electro_flash_v)

	# Organic sub-visuals.
	if _tendrils != null:
		var local_pts: Array[Vector2] = []
		for w in active_tendril_targets:
			local_pts.append(to_local(w))
		_tendrils.set_targets(local_pts, eff_r, _anim_time, stealth_alpha * (1.0 - death_progress))
		_tendrils.advance(delta, 1.0)
		_tendrils.level = int(mutation_levels.get("ranged_absorb", 0))
	if _shield_node != null:
		_shield_node.quality = quality
		_shield_node.set_radius(eff_r * 1.18)
		_shield_node.active = shield_active
	if _electro_node != null:
		_electro_node.level = int(mutation_levels.get("electro_discharge", 0))

	# Swallowed ghosts dissolve toward the nucleus.
	var alive: Array[Dictionary] = []
	for g in _swallowed:
		g["t"] = float(g["t"]) + delta * 1.7
		if float(g["t"]) < 1.0:
			alive.append(g)
	_swallowed = alive


func _draw_foreground() -> void:
	super._draw_foreground()
	if _fg_overlay == null or _swallowed.is_empty():
		return
	var eff_r := radius * (1.0 + gulp_bulge * 0.25)
	var alpha_mult := stealth_alpha * (1.0 - death_progress)
	# Ghosts of swallowed prey drift from the entry point to the nucleus and fade
	# out — the "brief movement inside the body" beat of the absorption sequence.
	for g in _swallowed:
		var t := float(g["t"])
		var from := g["from"] as Vector2
		var target := Vector2(0.0, radius * 0.40) + _lag_nucleus * (radius * 0.28)
		# Steer around eyes if entry point is in upper center face zone
		var eye_avoid := Vector2.ZERO
		if from.y < radius * 0.10 and absf(from.x) < radius * 0.36:
			var side_sign := 1.0 if from.x >= 0.0 else -1.0
			eye_avoid = Vector2(side_sign * radius * 0.32 * sin(t * PI), 0.0)
		var curve_ortho := from.orthogonal().normalized() * (radius * 0.08 * sin(t * PI))
		var pos := from.lerp(target, smoothstep(0.0, 1.0, t)) + curve_ortho + eye_avoid
		var sz: float = (g["size"] as float) * (1.0 - 0.75 * t)
		var pc: Color = g["color"]
		var a := (1.0 - t) * 0.55 * alpha_mult
		if a <= 0.01:
			continue
		var dark := pc.darkened(0.35)
		_fg_overlay.draw_circle(pos, sz * 1.25, Color(dark.r, dark.g, dark.b, a * 0.4))
		_fg_overlay.draw_circle(pos, sz, Color(pc.r, pc.g, pc.b, a))
		_fg_overlay.draw_circle(pos - Vector2(sz * 0.25, sz * 0.25), sz * 0.32,
			Color(1.0, 1.0, 1.0, a * 0.5))
		if t > 0.55:
			# Biological dissolution: soft halo and radiating motes into the cytoplasm
			var diss := (t - 0.55) / 0.45
			var halo_r := sz * (1.2 + diss * 1.5)
			var halo_a := (1.0 - diss) * a * 0.5
			_fg_overlay.draw_circle(pos, halo_r, Color(pc.r, pc.g, pc.b, halo_a * 0.35))
			for i in range(4):
				var ma := TAU * float(i) / 4.0 + _u_time * 2.8
				var mp := pos + Vector2.from_angle(ma) * (sz * (1.1 + diss * 2.0))
				_fg_overlay.draw_circle(mp, maxf(1.0, sz * 0.22 * (1.0 - diss)), Color(pc.r, pc.g, pc.b, halo_a * 0.8))

	# Re-draw face on top so eyes and catchlights are NEVER occluded by internal ghosts
	_draw_face(eff_r, alpha_mult)
