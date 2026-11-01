class_name ClaudeBolts
extends Node2D
## electro_discharge, outward half: jagged bolts that leave the membrane where the
## internal channels reach it and arc to the targets the game already chose. Three
## stacked additive strokes (halo, body, hot core) so they read as light, and a short
## re-jitter so they crackle instead of sitting still. The damage, radius and cadence
## are the unchanged mutation; this node only draws.

const LIFE: float = 0.30
const JITTER_PERIOD: float = 0.045

var _bolts: Array[Dictionary] = []
var _r0: float = 25.0
var _rng: RandomNumberGenerator = RandomNumberGenerator.new()


func _init() -> void:
	z_index = 3
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	material = mat
	_rng.randomize()


func set_radius(r0: float) -> void:
	_r0 = r0


func fire(targets: Array[Vector2], r0: float, level: int, em_storm: bool = false) -> void:
	_r0 = r0
	var list: Array[Vector2] = targets.duplicate()
	if list.is_empty():
		# Nothing to hit: a short crown of arcs shows the discharge happened.
		var base := _rng.randf() * TAU
		var arc_count := (4 + mini(level, 4)) if em_storm else (3 + mini(level, 3))
		for i in range(arc_count):
			var spread := (TAU * float(i) / float(arc_count)) + _rng.randf_range(-0.25, 0.25)
			var reach_mult := _rng.randf_range(2.4, 3.2) if em_storm else _rng.randf_range(2.0, 2.6)
			list.append(Vector2.from_angle(base + spread) * r0 * reach_mult)
	var max_bolts := 12 if em_storm else 8
	for t in list:
		if _bolts.size() >= max_bolts:
			break
		var dir := t.normalized() if t.length_squared() > 0.01 else Vector2.RIGHT
		_bolts.append({
			"from": dir * r0 * 0.96,
			"to": t,
			"age": 0.0,
			"jit": 0.0,
			"seed": _rng.randi(),
			"pts": PackedVector2Array(),
			"branch": PackedVector2Array(),
			"is_em": em_storm,
		})
		_rebuild(_bolts[_bolts.size() - 1])


func _rebuild(b: Dictionary) -> void:
	_rng.seed = int(b["seed"]) + int(float(b["age"]) / JITTER_PERIOD) * 7919
	var a: Vector2 = b["from"]
	var z: Vector2 = b["to"]
	var pts := PackedVector2Array([a, z])
	var disp := a.distance_to(z) * 0.20
	for _lvl in range(4):
		var next := PackedVector2Array()
		for i in range(pts.size() - 1):
			var p0 := pts[i]
			var p1 := pts[i + 1]
			var mid := (p0 + p1) * 0.5
			var nrm := (p1 - p0).orthogonal().normalized()
			mid += nrm * _rng.randf_range(-disp, disp)
			next.append(p0)
			next.append(mid)
		next.append(pts[pts.size() - 1])
		pts = next
		disp *= 0.52
	b["pts"] = pts
	# one fork from the middle third
	var bi := clampi(int(pts.size() * _rng.randf_range(0.30, 0.55)), 1, pts.size() - 2)
	var fork_dir := (z - a).normalized().rotated(_rng.randf_range(-0.9, 0.9))
	var fork := PackedVector2Array([pts[bi]])
	var fp := pts[bi]
	var step := a.distance_to(z) * 0.07
	for _j in range(4):
		fp += fork_dir.rotated(_rng.randf_range(-0.5, 0.5)) * step
		fork.append(fp)
		step *= 0.8
	b["branch"] = fork


func _process(delta: float) -> void:
	if _bolts.is_empty():
		return
	var keep: Array[Dictionary] = []
	for b in _bolts:
		b["age"] = float(b["age"]) + delta
		b["jit"] = float(b["jit"]) + delta
		if float(b["jit"]) >= JITTER_PERIOD:
			b["jit"] = 0.0
			_rebuild(b)
		if float(b["age"]) < LIFE:
			keep.append(b)
	_bolts = keep
	queue_redraw()


func _draw() -> void:
	for b in _bolts:
		var k := float(b["age"]) / LIFE
		var fade := (1.0 - k) * (1.0 - k)
		var flick := 0.75 + 0.25 * sin(float(b["age"]) * 90.0)
		var f := fade * flick
		var pts: PackedVector2Array = b["pts"]
		var fork: PackedVector2Array = b["branch"]
		var w := maxf(_r0 * 0.05, 1.4)
		var is_em: bool = bool(b.get("is_em", false))

		# Colors: EM storm uses blazing solar-amber core with blue magnetic fringe
		var col_halo := Color(1.0, 0.75, 0.20, 0.22 * f) if is_em else Color(0.30, 0.62, 1.0, 0.16 * f)
		var col_body := Color(1.0, 0.90, 0.40, 0.60 * f) if is_em else Color(0.50, 0.86, 1.0, 0.45 * f)
		var col_core := Color(1.0, 1.0, 0.85, 0.98 * f) if is_em else Color(0.92, 1.0, 1.0, 0.95 * f)

		draw_polyline(pts, col_halo, w * 5.0, true)
		draw_polyline(pts, col_body, w * 2.2, true)
		draw_polyline(pts, col_core, w, true)
		if fork.size() > 1:
			draw_polyline(fork, col_body * 0.8, w * 1.4, true)
			draw_polyline(fork, col_core, w * 0.6, true)
		var from: Vector2 = b["from"]
		draw_circle(from, _r0 * 0.20, col_halo)
		draw_circle(from, _r0 * 0.09, col_core * 0.8)
		if is_em:
			# Magnetic field pulse ring at bolt emission point
			draw_arc(from, _r0 * (0.25 + 0.35 * (1.0 - fade)), 0.0, TAU, 16, Color(1.0, 0.85, 0.35, 0.40 * f), 1.2)
		var to: Vector2 = b["to"]
		draw_circle(to, _r0 * 0.15, col_halo)
		draw_circle(to, _r0 * 0.055, col_core)
