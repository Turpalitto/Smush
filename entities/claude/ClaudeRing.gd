class_name ClaudeRing
extends RefCounted
## Radial spring-damper ring that gives the Claude slime a membrane with real inertia.
##
## N nodes sit at angles (i / N - 0.5) * TAU. Each node holds a radial offset x (in
## body-radius units), a velocity v, and is pulled toward a drive target by a spring
## while its neighbours pull on it (so a poke travels around the body as a wave).
##
##   accelerate  → the membrane lags the motion: the trailing side bulges, the leading
##                 side flattens, and it rings out when the acceleration stops.
##   impulse     → instantaneous kick (absorb cup, hit dent, evolution swell).
##   rest bumps  → static offsets (mutation buds, tentacle roots).
##
## No frame-rate dependence: stepping is sub-divided into <= 1/120 s slices.

const N: int = 16
const MAX_SUBSTEPS: int = 8

var stiffness: float = 78.0
var damping: float = 4.6
var coupling: float = 62.0
var _asym_offsets: PackedFloat32Array = PackedFloat32Array()
var _asym_strength: float = 0.0

var x: PackedFloat32Array = PackedFloat32Array()
var v: PackedFloat32Array = PackedFloat32Array()
var bumps: PackedFloat32Array = PackedFloat32Array()
var _drive: PackedFloat32Array = PackedFloat32Array()
var _out: PackedFloat32Array = PackedFloat32Array()


func _init() -> void:
	x.resize(N)
	v.resize(N)
	bumps.resize(N)
	_drive.resize(N)
	_out.resize(N)
	_asym_offsets.resize(N)
	# Pseudo-random per-node asymmetry (seeded deterministically so it's stable)
	for i in range(N):
		_asym_offsets[i] = sin(float(i) * 2.39996 + 1.7) * 0.6 + cos(float(i) * 3.14 + 0.5) * 0.4


## Adjust spring dynamics based on evolution stage.
## growth_t: 1.0 (baby) to 15.0 (apex).
## Baby: high damping, low stiffness → wobbly, soft.
## Apex: lower damping, higher stiffness + coupling → confident, cohesive.
func set_evolution(growth_t: float) -> void:
	var t01 := clampf((growth_t - 1.0) / 14.0, 0.0, 1.0)
	stiffness = lerpf(55.0, 92.0, smoothstep(0.0, 0.8, t01))
	damping = lerpf(6.5, 4.0, smoothstep(0.0, 0.7, t01))
	coupling = lerpf(48.0, 72.0, smoothstep(0.1, 0.9, t01))
	_asym_strength = smoothstep(0.25, 0.85, t01) * 0.018


static func angle_of(i: int) -> float:
	return (float(i) / float(N) - 0.5) * TAU


## Fractional node index of a world angle (radians, any range).
static func index_of(angle: float) -> float:
	return (wrapf(angle, -PI, PI) / TAU + 0.5) * float(N)


## Circular distance, in nodes, between node i and a fractional index.
static func node_dist(i: int, f: float) -> float:
	var d := absf(float(i) - f)
	return minf(d, float(N) - d)


func impulse(angle: float, amount: float, width_nodes: float = 1.7) -> void:
	var f := index_of(angle)
	for i in range(N):
		var d := node_dist(i, f)
		v[i] += amount * exp(-(d * d) / (2.0 * width_nodes * width_nodes))


func push(angle: float, amount: float, width_nodes: float = 1.7) -> void:
	var f := index_of(angle)
	for i in range(N):
		var d := node_dist(i, f)
		x[i] += amount * exp(-(d * d) / (2.0 * width_nodes * width_nodes))


func impulse_all(amount: float) -> void:
	for i in range(N):
		v[i] += amount


func set_bump(angle: float, amount: float, width_nodes: float = 1.3) -> void:
	## Adds to the static rest offsets for this frame (call clear_bumps() first).
	var f := index_of(angle)
	for i in range(N):
		var d := node_dist(i, f)
		bumps[i] += amount * exp(-(d * d) / (2.0 * width_nodes * width_nodes))


func clear_bumps() -> void:
	for i in range(N):
		bumps[i] = 0.0


## accel_world: acceleration already scaled to body-radius units (|a| ~ 0..1).
## swim: 0..1 how hard the body is swimming (drives a faint travelling ripple).
func step(delta: float, accel_world: Vector2, swim: float, t: float) -> void:
	if delta <= 0.0:
		return
	var slices := clampi(ceili(delta / (1.0 / 120.0)), 1, MAX_SUBSTEPS)
	var h := minf(delta, float(MAX_SUBSTEPS) / 120.0) / float(slices)
	for i in range(N):
		var a := angle_of(i)
		var dir := Vector2(cos(a), sin(a))
		# The shell moves with the push; the contents lag. In the shell's frame the
		# trailing side is where mass piles up, so the drive is opposite the accel.
		_drive[i] = -accel_world.dot(dir) * 0.21 + swim * 0.012 * sin(a * 3.0 - t * 5.0)
	for _s in range(slices):
		for i in range(N):
			var xl := x[(i + N - 1) % N]
			var xr := x[(i + 1) % N]
			var acc := stiffness * (_drive[i] - x[i]) - damping * v[i] + coupling * (xl + xr - 2.0 * x[i])
			v[i] += acc * h
		for i in range(N):
			x[i] += v[i] * h
			x[i] = clampf(x[i], -0.30, 0.34)


## Offsets ready for the shader: dynamic + rest bumps + uniform swell + organic asymmetry.
func output(swell: float) -> PackedFloat32Array:
	for i in range(N):
		_out[i] = x[i] + bumps[i] + swell + _asym_offsets[i] * _asym_strength
	return _out
