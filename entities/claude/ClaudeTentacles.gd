class_name ClaudeTentacles
extends Node2D
## ranged_absorb, as anatomy: elastic tentacles that grow out of the membrane toward
## the prey the game already selected (SlimeVisual.active_tendril_targets).
##
## Each tentacle is a damped spring on its TIP (so it overshoots and settles, which is
## what makes it read as muscle and not as a line), plus a travelling body wave that
## calms as the tentacle comes under tension. The root is hidden under the jelly body
## (this node sits below it), and SlimeVisualClaude raises a membrane bulge at the
## anchor angle so the root looks grown, not attached.
##
## Pure presentation: range, reel speed and targets come from the unchanged mutation.

const MAX_SLOTS: int = 4
const TIP_STIFFNESS: float = 210.0
const TIP_DAMPING: float = 9.5

var quality: int = 2

var _slots: Array[Dictionary] = []
var _r0: float = 25.0
var _time: float = 0.0
var _alpha: float = 1.0
var _body: Color = Color(0.56, 0.55, 1.0)
var _accent: Color = Color(1.0, 1.0, 1.0)
var _level: int = 0
var _vampire: bool = false


func _init() -> void:
	z_index = 0


func slot_info() -> Array[Dictionary]:
	var out: Array[Dictionary] = []
	for s in _slots:
		out.append({"angle": s["angle"], "ext": smoothstep(0.0, 1.0, float(s["ext"]))})
	return out


func update_state(targets: Array[Vector2], r0: float, time: float, dt: float, alpha: float,
		body: Color, accent: Color, level: int, vampire: bool) -> void:
	_r0 = r0
	_time = time
	_alpha = alpha
	_body = body
	_accent = accent
	_level = level
	_vampire = vampire
	var count := mini(targets.size(), MAX_SLOTS)
	while _slots.size() < count:
		var a := (targets[_slots.size()]).angle()
		_slots.append({
			"tip": Vector2.from_angle(a) * r0 * 0.8,
			"tip_v": Vector2.ZERO,
			"ext": 0.0,
			"angle": a,
			"target": targets[_slots.size()],
			"active": true,
			"phase": randf() * TAU,
		})
	for i in range(_slots.size()):
		var s := _slots[i]
		if i < count:
			s["active"] = true
			s["target"] = targets[i]
			s["angle"] = lerp_angle(float(s["angle"]), (targets[i]).angle(), 1.0 - exp(-14.0 * dt))
		else:
			s["active"] = false
		var want := 1.0 if bool(s["active"]) else 0.0
		var ext := float(s["ext"])
		# Grows quickly, withdraws a little faster.
		ext = move_toward(ext, want, dt * (3.4 if want > ext else 4.6))
		s["ext"] = ext
		var anchor := Vector2.from_angle(float(s["angle"])) * r0 * 0.80
		var tgt: Vector2 = s["target"]
		var goal := anchor.lerp(tgt, smoothstep(0.0, 1.0, ext))
		var tip: Vector2 = s["tip"]
		var tv: Vector2 = s["tip_v"]
		var slices := clampi(ceili(dt / (1.0 / 120.0)), 1, 6)
		var h := minf(dt, 0.05) / float(slices)
		for _k in range(slices):
			tv += ((goal - tip) * TIP_STIFFNESS - tv * TIP_DAMPING) * h
			tip += tv * h
		s["tip"] = tip
		s["tip_v"] = tv
	# Drop fully retracted tentacles.
	var keep: Array[Dictionary] = []
	for s in _slots:
		if bool(s["active"]) or float(s["ext"]) > 0.001:
			keep.append(s)
	_slots = keep
	queue_redraw()


func _draw() -> void:
	if _slots.is_empty():
		return
	var base := _body.lerp(Color(0.80, 0.52, 1.0), 0.45).lightened(0.10)
	var accent := Color(1.0, 0.40, 0.62) if _vampire else Color(1.0, 0.80, 0.95)
	var segs := 14 if quality >= 1 else 8
	for si in range(_slots.size()):
		_draw_one(_slots[si], si, base, accent, segs)


func _draw_one(s: Dictionary, idx: int, base: Color, accent: Color, segs: int) -> void:
	var ext := smoothstep(0.0, 1.0, float(s["ext"]))
	if ext <= 0.002:
		return
	var angle := float(s["angle"])
	var anchor := Vector2.from_angle(angle) * _r0 * 0.80
	var tip: Vector2 = s["tip"]
	var tip_v: Vector2 = s["tip_v"]
	var span := tip - anchor
	var length := maxf(span.length(), 1.0)
	var dir := span / length
	var perp := dir.orthogonal()
	var phase := float(s["phase"])
	var taut := clampf(ext, 0.0, 1.0)
	var amp := length * (0.075 + 0.20 * (1.0 - taut) * (1.0 - taut))
	var drag := tip_v.dot(perp) * 0.020

	var centre := PackedVector2Array()
	var widths := PackedFloat32Array()
	for i in range(segs + 1):
		var u := float(i) / float(segs)
		var p := anchor + span * u
		var wave := sin(u * 4.6 - _time * 8.0 + phase) * sin(u * PI) * amp * (0.35 + 0.65 * u)
		var sag := sin(u * PI) * drag * length * 0.35 * u
		p += perp * (wave + sag)
		centre.append(p)
		var w := _r0 * lerpf(0.185, 0.040, pow(u, 0.72))
		w *= 1.0 + 0.65 * exp(-u * 7.0)
		w *= lerpf(0.55, 1.0, minf(ext * 1.4, 1.0))
		widths.append(w)

	var left := PackedVector2Array()
	var right := PackedVector2Array()
	for i in range(segs + 1):
		var t_dir: Vector2
		if i == 0:
			t_dir = centre[1] - centre[0]
		elif i == segs:
			t_dir = centre[i] - centre[i - 1]
		else:
			t_dir = centre[i + 1] - centre[i - 1]
		var nrm := t_dir.normalized().orthogonal()
		left.append(centre[i] + nrm * widths[i])
		right.append(centre[i] - nrm * widths[i])

	var a := _alpha

	# Draw the tentacle as thick polylines instead of polygons to avoid
	# self-intersection errors with Godot's polygon triangulator.

	# 1. Dark contour — wide background stroke
	var contour_w := widths[0] * 2.56 + 2.2  # matches old out_expand * 2 + out_pad * 2
	draw_polyline(centre, Color(0.07, 0.04, 0.22, 0.60 * a), contour_w, true)

	# 2. Jelly fill — gradient from root to tip using overlapping polylines
	#    (a single polyline can only have one color, so we draw segments)
	for i in range(segs):
		var u_a := float(i) / float(segs)
		var ca := base.lerp(accent, pow(u_a, 1.8) * 0.65)
		ca.a = lerpf(0.96, 0.82, u_a) * a
		var seg_w := (widths[i] + widths[i + 1])  # avg width * 2
		draw_line(centre[i], centre[i + 1], ca, seg_w, true)

	# 3. lit edge (key light is top-left)
	var hl := PackedVector2Array()
	for i in range(segs + 1):
		var nrm4 := (left[i] - centre[i]).normalized()
		var toward_light := nrm4.dot(Vector2(-0.45, -0.65).normalized()) > 0.0
		var side := nrm4 if toward_light else -nrm4
		hl.append(centre[i] + side * widths[i] * 0.52)
	draw_polyline(hl, Color(1.0, 0.98, 1.0, 0.38 * a), maxf(_r0 * 0.045, 1.2), true)

	# 4. inner vein with nutrients travelling toward the body
	draw_polyline(centre, Color(1.0, 0.88, 0.72, 0.30 * a), maxf(_r0 * 0.05, 1.3), true)
	for k in range(3):
		var bu := 1.0 - fposmod(_time * 0.85 + float(k) / 3.0 + phase * 0.1, 1.0)
		var bi := clampi(int(bu * float(segs)), 0, segs)
		var fade := sin(bu * PI)
		draw_circle(centre[bi], widths[bi] * 0.55, Color(1.0, 0.93, 0.78, 0.70 * a * fade))

	# 5. sucker tip
	var tr := _r0 * 0.085
	draw_circle(tip, tr * 1.9, Color(accent.r, accent.g, accent.b, 0.20 * a * ext))
	draw_circle(tip, tr * 1.22, Color(0.10, 0.04, 0.24, 0.65 * a * ext))
	draw_circle(tip, tr, Color(accent.r, accent.g, accent.b, 0.95 * a * ext))
	draw_circle(tip, tr * 0.46, Color(1.0, 1.0, 1.0, 0.85 * a * ext))
	draw_circle(tip + Vector2(-tr * 0.34, -tr * 0.38), tr * 0.22, Color(1.0, 1.0, 1.0, 0.9 * a * ext))
	if idx < 0:
		return
