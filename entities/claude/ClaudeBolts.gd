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


func fire(targets: Array[Vector2], r0: float, level: int) -> void:
	_r0 = r0
	var list: Array[Vector2] = targets.duplicate()
	if list.is_empty():
		# Nothing to hit: a short crown of arcs shows the discharge happened.
		var base := _rng.randf() * TAU
		for i in range(3 + mini(level, 3)):
			list.append(Vector2.from_angle(base + TAU * float(i) / float(3 + mini(level, 3)) + _rng.randf_range(-0.25, 0.25)) * r0 * _rng.randf_range(2.0, 2.6))
	for t in list:
		if _bolts.size() >= 8:
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
		draw_polyline(pts, Color(0.30, 0.62, 1.0, 0.16 * f), w * 5.0, true)
		draw_polyline(pts, Color(0.50, 0.86, 1.0, 0.45 * f), w * 2.2, true)
		draw_polyline(pts, Color(0.92, 1.0, 1.0, 0.95 * f), w, true)
		if fork.size() > 1:
			draw_polyline(fork, Color(0.50, 0.86, 1.0, 0.35 * f), w * 1.4, true)
			draw_polyline(fork, Color(0.95, 1.0, 1.0, 0.8 * f), w * 0.6, true)
		var from: Vector2 = b["from"]
		draw_circle(from, _r0 * 0.20, Color(0.45, 0.80, 1.0, 0.22 * f))
		draw_circle(from, _r0 * 0.09, Color(0.95, 1.0, 1.0, 0.7 * f))
		var to: Vector2 = b["to"]
		draw_circle(to, _r0 * 0.15, Color(0.45, 0.80, 1.0, 0.25 * f))
		draw_circle(to, _r0 * 0.055, Color(1.0, 1.0, 1.0, 0.8 * f))
