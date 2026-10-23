class_name MassSystem
extends RefCounted
## Non-linear slime mass -> size curve and tactical high-mass trade-offs.

const MIN_MASS: float = 8.0
const DEFAULT_START_MASS: float = 10.0
const SOFT_CAP_MASS: float = 78.0
const MAX_MASS: float = 220.0

const MIN_RADIUS: float = 18.0
const MAX_RADIUS: float = 58.0


static func clamp_mass(mass: float) -> float:
	return clampf(mass, MIN_MASS, MAX_MASS)


static func radius_from_mass(mass: float) -> float:
	var m := clamp_mass(mass)
	var excess := maxf(m - 5.0, 0.0)
	var damping := 1.0 + maxf(m - 10.0, 0.0) / 260.0
	var r := 15.0 + (5.2 * pow(excess, 0.46)) / damping
	return clampf(r, MIN_RADIUS, MAX_RADIUS)


static func effective_gain(current_mass: float, raw_gain: float) -> float:
	if raw_gain <= 0.0:
		return 0.0
	var m := clamp_mass(current_mass)
	# Smooth diminishing returns above soft cap so mass stays meaningful without runaway growth
	var taper := 1.0
	if m > SOFT_CAP_MASS:
		taper = 1.0 / (1.0 + (m - SOFT_CAP_MASS) * 0.025)
	return raw_gain * taper


static func maneuverability_multiplier(mass: float) -> float:
	# Small slime is agile (~1.02x), huge slime turns/accelerates slower (~0.74x)
	var m := clamp_mass(mass)
	var norm := clampf((m - MIN_MASS) / (MAX_MASS - MIN_MASS), 0.0, 1.0)
	return lerpf(1.02, 0.74, pow(norm, 0.75))


static func visibility_multiplier(mass: float) -> float:
	# Larger slimes are spotted from much further away by predators & fleeing prey
	var m := clamp_mass(mass)
	var norm := clampf((m - MIN_MASS) / (MAX_MASS - MIN_MASS), 0.0, 1.0)
	return lerpf(0.90, 1.48, pow(norm, 0.80))


static func aoe_vulnerability_multiplier(mass: float) -> float:
	# High mass exposes larger membrane area to ground poison pools & electric arcs
	var m := clamp_mass(mass)
	var norm := clampf((m - MIN_MASS) / (MAX_MASS - MIN_MASS), 0.0, 1.0)
	return lerpf(0.95, 1.45, norm)


static func can_fit_narrow_passage(mass: float, passage_half_width: float, is_dashing: bool = false) -> bool:
	var r := radius_from_mass(mass)
	if is_dashing:
		# Hydro-jet dash compresses membrane width by 22%, letting mid-sized slimes squeeze through!
		r *= 0.78
	return r <= passage_half_width


static func evolution_threshold_for_level(level: int) -> float:
	# Fast first mutations (within first 15-35s!), smooth escalation to Lv 8-11 across 5-7 min run
	var lv := maxi(0, level)
	if lv <= 3:
		return roundf(32.0 + float(lv) * 24.0 + pow(float(lv), 1.55) * 9.0)
	return roundf(32.0 + float(lv) * 28.0 + pow(float(lv), 1.65) * 11.0)
