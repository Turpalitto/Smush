class_name OrganicElectro
extends Node2D
## EXPERIMENTAL electro_discharge visual (GLM visual lab), replacing the three static
## spark polylines drawn by SlimeVisual._draw_foreground when `organic_electro` is set.
##
## Two halves:
##   1. Internal conduction channels live in the body shader itself
##      (slime_body_organic.gdshader reads electro_level/electro_charge/electro_flash —
##      the veins of the anatomy become the conductors).
##   2. This node draws the discharge arcs: jagged luminous bolts between the slime
##      and local-space target points, double-stroked (wide faint glow + thin white-hot
##      core) with forked sub-branches and spark tips.
##
## Purely visual. Damage, stun and target selection stay in PlayerSlime/ArenaController.

var level: int = 0

## Bolts live for ~0.22 s. Each holds a polyline plus its own jitter seed so the
## bolt does not re-randomise every frame — only the flicker does.
var _bolts: Array[Dictionary] = []
var _time: float = 0.0
var _alpha: float = 1.0


func fire_discharge(targets_local: Array[Vector2]) -> void:
	for t in targets_local:
		_bolts.append({
			"to": t,
			"life": 0.22,
			"seed": randf() * 100.0,
		})


func _process(delta: float) -> void:
	_time += delta
	var alive: Array[Dictionary] = []
	for b in _bolts:
		b["life"] = float(b["life"]) - delta
		if float(b["life"]) > 0.0:
			alive.append(b)
	_bolts = alive
	queue_redraw()


func _draw() -> void:
	if _bolts.is_empty():
		return
	for b in _bolts:
		_draw_bolt(b["to"] as Vector2, clampf(float(b["life"]) / 0.22, 0.0, 1.0), float(b["seed"]))


func _draw_bolt(to: Vector2, life_t: float, seed_v: float) -> void:
	var from := Vector2.ZERO
	var span := to - from
	if span.length_squared() < 4.0:
		return
	var dir := span.normalized()
	var n := dir.orthogonal()
	var segs := 7
	var pts := PackedVector2Array()
	# Jagged path: two noise octaves on the normal, stronger mid-bolt. Seeded per
	# bolt so the shape holds while it flickers.
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var base := from + span * t
		var envelope := sin(t * PI)
		var j := sin(t * 17.0 + seed_v) * 7.0 + sin(t * 31.0 + seed_v * 1.7) * 3.5
		pts.append(base + n * j * envelope)
	var fade := life_t * (0.75 + 0.25 * sin(_time * 60.0 + seed_v))
	var alpha := fade * clampf(0.45 + 0.11 * float(level), 0.0, 1.0)

	# Wide faint glow pass, then the white-hot core, then forks and sparks.
	draw_polyline(pts, Color(1.0, 0.93, 0.45, 0.22 * alpha), 7.0)
	draw_polyline(pts, Color(1.0, 0.96, 0.62, 0.55 * alpha), 3.2)
	draw_polyline(pts, Color(1.0, 1.0, 0.94, 0.95 * alpha), 1.5)

	# Forks: two short branches off random midpoints.
	for k in range(2):
		var t0 := 0.35 + 0.3 * float(k) + 0.12 * sin(seed_v * 3.1 + float(k))
		var i0 := clampi(int(t0 * float(segs)), 1, segs - 1)
		var branch_dir := (dir.rotated(0.9 - 1.8 * (sin(seed_v + float(k) * 2.3) * 0.5 + 0.5))).normalized()
		var blen := span.length() * 0.16
		var fork := PackedVector2Array()
		for j in range(3):
			var ft := float(j) / 2.0
			fork.append(pts[i0] + branch_dir * blen * ft + n * sin(ft * 9.0 + seed_v) * 2.5)
		draw_polyline(fork, Color(1.0, 0.95, 0.6, 0.4 * alpha), 1.2)

	# Tip spark: a four-point star at the contact point.
	var tip_outer := 6.0 + 3.0 * fade
	var star := PackedVector2Array()
	for i in range(8):
		var a := TAU * float(i) / 8.0 - PI * 0.5
		var rr := tip_outer if (i % 2) == 0 else tip_outer * 0.34
		star.append(to + Vector2(cos(a), sin(a)) * rr)
	draw_colored_polygon(star, Color(1.0, 0.97, 0.75, 0.8 * alpha))
	draw_circle(to, tip_outer * 1.6, Color(1.0, 0.9, 0.5, 0.10 * alpha))
