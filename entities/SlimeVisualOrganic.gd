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
	var dt := maxf(delta, 0.0001)
	_u_time += delta

	# Inertial contents: one EMA of velocity covers both reactions — accelerating
	# leaves the lag pointing backwards, braking throws it forwards.
	_vel_lag = _vel_lag.lerp(velocity_vec, 1.0 - exp(-dt / 0.16))
	var lag := (velocity_vec - _vel_lag) * 0.004
	if lag.length() > 0.30:
		lag = lag.normalized() * 0.30

	_absorb_pulse = maxf(0.0, _absorb_pulse - delta * 1.5)
	_electro_flash_v = maxf(0.0, _electro_flash_v - delta * 3.4)

	var eff_r := radius * (1.0 + gulp_bulge * 0.25)
	_anatomy = anatomy_at(growth_t)
	var lv := clampf(float(mutation_levels.get("electro_discharge", 0)) / 5.0, 0.0, 1.0)
	# Internal charge builds on the same rhythm the mutation discharges on (~3.4 s
	# base). Flash only fires when someone calls trigger_electro_flash().
	if lv > 0.0 and _electro_flash_v <= 0.0:
		_electro_cycle = fposmod(_electro_cycle + delta, 3.4)
	var charge := (_electro_cycle / 3.4) if lv > 0.0 else 0.0

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("u_time", _u_time)
		_shader_mat.set_shader_parameter("quality", quality)
		_shader_mat.set_shader_parameter("lag_vec", lag)
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
	var alpha_mult := stealth_alpha * (1.0 - death_progress)
	# Ghosts of swallowed prey drift from the entry point to the nucleus and fade
	# out — the "brief movement inside the body" beat of the absorption sequence.
	for g in _swallowed:
		var t := float(g["t"])
		var from := g["from"] as Vector2
		var target := Vector2(0.0, radius * 0.16)
		var pos := from.lerp(target, smoothstep(0.0, 1.0, t))
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
		if t > 0.6:
			# Dissolving: the outline breaks into a few motes on the way out.
			for i in range(3):
				var ma := TAU * float(i) / 3.0 + _u_time * 3.0
				var mp := pos + Vector2.from_angle(ma) * (sz * (1.4 + t))
				_fg_overlay.draw_circle(mp, sz * 0.16, Color(pc.r, pc.g, pc.b, a * 0.7))
