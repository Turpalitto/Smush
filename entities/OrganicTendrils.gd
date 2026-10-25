class_name OrganicTendrils
extends Node2D
## EXPERIMENTAL organic variant of the ranged_absorb tendrils (GLM visual lab).
##
## The base SlimeVisual draws a fixed-width polyline per target. This node draws a
## pseudopod instead: a tapered organic limb that grows out of an anchor bump on the
## membrane, extends to the prey with a travelling stretch wave, grips it with a
## sucker, and reels the tip back toward the body. The motion is phase-driven, so
## the lab can freeze or slow it like the rest of the organic anatomy.
##
## Owns no gameplay logic: targets are fed in local space by the owner (in the lab by
## the demo driver; in a future game integration by ArenaController.process_ranged_tendrils
## exactly as the base tendrils are fed today).

## Per-target reel state, advanced by `advance()`: 0..1 out-and-back envelope plus
## an extension ease, so a tentacle reaches, holds, and returns on its own cycle.
class Reel:
	var phase: float = 0.0
	var speed: float = 0.9
	var target_local: Vector2 = Vector2.ZERO

var _reels: Array[Reel] = []
var _acc: Color = Color(0.76, 0.48, 1.0)
var _edge: Color = Color(0.30, 0.14, 0.48)
var _lit: Color = Color(0.95, 0.80, 1.0)
var _time: float = 0.0
var _radius: float = 25.0
var _alpha: float = 1.0
var level: int = 1

## Set each frame by the owner (mirrors SlimeVisual.active_tendril_targets).
func set_targets(local_points: Array[Vector2], body_radius: float, time: float, alpha: float) -> void:
	_radius = body_radius
	_time = time
	_alpha = alpha
	if _reels.size() != local_points.size():
		_reels.clear()
		for p in local_points:
			var r := Reel.new()
			# Start mid-extension: in the game the reel begins the tick the target is
			# acquired, so a pseudopod growing from zero would still be a stub while
			# the prey is already halfway in.
			r.phase = 0.30
			r.speed = randf_range(0.8, 1.05)
			r.target_local = p
			_reels.append(r)
	for i in range(local_points.size()):
		_reels[i].target_local = local_points[i]
	queue_redraw()


func advance(delta: float, anim_speed: float) -> void:
	for r in _reels:
		r.phase = fposmod(r.phase + delta * anim_speed * r.speed, 1.0)
	if not _reels.is_empty():
		queue_redraw()


func _draw() -> void:
	if _reels.is_empty() or _alpha <= 0.01:
		return
	# Gold-per-vampirism accent swap stays consistent with the base tendrils.
	var vampirism := false
	var owner_node := get_parent()
	if owner_node != null and "active_synergies" in owner_node:
		vampirism = bool(owner_node.active_synergies.get("bio_vampirism", false))
	var body_col := Color(1.0, 0.30, 0.58) if vampirism else _acc
	var edge_col := Color(0.55, 0.10, 0.28) if vampirism else _edge
	var lit_col := Color(1.0, 0.85, 0.92) if vampirism else _lit

	for r in _reels:
		_draw_pseudopod(r, body_col, edge_col, lit_col)


func _draw_pseudopod(r: Reel, body_col: Color, edge_col: Color, lit_col: Color) -> void:
	var target := r.target_local
	var max_span := target.length()
	if max_span < _radius * 0.4:
		return
	var dir := target / max_span
	# Out-and-back envelope: 0 -> reach (0.55) -> hold -> retract. The eased value
	# `ext` is the fraction of the span the tip currently covers.
	var p := r.phase
	var ext := 0.0
	if p < 0.42:
		ext = smoothstep(0.0, 0.42, p)
	elif p < 0.62:
		ext = 1.0
	else:
		ext = 1.0 - smoothstep(0.62, 1.0, p)
	var reach := maxf(_radius * 0.9, max_span * clampf(ext, 0.05, 1.0))

	# Anchor bump on the membrane: the pseudopod does not start from a point, it
	# squeezes out of a small dome of the body itself.
	var anchor := dir * (_radius * 0.86)
	var bump := 5.0 + 2.5 * ext
	draw_circle(anchor, bump * 1.5, Color(edge_col.r, edge_col.g, edge_col.b, 0.35 * _alpha))
	draw_circle(anchor, bump, Color(body_col.r, body_col.g, body_col.b, 0.8 * _alpha))

	# Centre spine with a travelling stretch wave: the limb thickens where the wave
	# crest is, like muscle contraction passing down a pseudopod.
	var tip := dir * reach
	var segs := 10
	var pts := PackedVector2Array()
	var half_w := PackedFloat32Array()
	for i in range(segs + 1):
		var t := float(i) / float(segs)
		var pt := anchor.lerp(tip, t)
		# Perpendicular sway + travelling bulge.
		var sway := dir.orthogonal() * (sin(t * 4.5 - _time * 6.0 + r.phase * TAU) * (3.2 + 2.4 * (1.0 - ext)))
		pt += sway * t
		pts.append(pt)
		var taper := sin(clampf(t, 0.0, 1.0) * PI) * 0.65 + 0.35
		var bulge := 1.0 + 0.55 * exp(-pow((t - fposmod(_time * 1.6 + r.phase, 1.0)) * 4.0, 2.0))
		half_w.append((4.6 * taper * bulge) * clampf(0.55 + 0.45 * ext, 0.4, 1.0))

	# Body fill as a quad strip: a dark contour pass underneath (the regalia rule —
	# a form needs an edge darker than its body or it vanishes at phone size), then
	# the body, then the highlight crest.
	for i in range(segs):
		var a := pts[i]
		var b := pts[i + 1]
		var wa := half_w[i]
		var wb := half_w[i + 1]
		var seg_dir := (b - a).normalized()
		if seg_dir.length_squared() < 0.0001:
			continue
		var n := seg_dir.orthogonal()
		draw_colored_polygon(PackedVector2Array([
			a + n * (wa + 2.4), b + n * (wb + 2.4), b - n * (wb + 2.4), a - n * (wa + 2.4),
		]), Color(edge_col.r, edge_col.g, edge_col.b, 0.55 * _alpha))
		draw_colored_polygon(PackedVector2Array([
			a + n * wa, b + n * wb, b - n * wb, a - n * wa,
		]), Color(body_col.r, body_col.g, body_col.b, 0.92 * _alpha))
	# Rounded tip + contour lines along both sides.
	draw_circle(tip, half_w[segs], Color(body_col.r, body_col.g, body_col.b, 0.9 * _alpha))
	draw_polyline(pts, Color(edge_col.r, edge_col.g, edge_col.b, 0.65 * _alpha), 1.4)
	var pts_low := PackedVector2Array()
	for i in range(segs + 1):
		pts_low.append(pts[i] + dir.orthogonal() * half_w[i] * -1.0)
	# Highlight crest along the upper edge: the cheapest "cylinder" cue.
	var hi := PackedVector2Array()
	for i in range(segs + 1):
		var off := dir.orthogonal() * (half_w[i] * 0.42 - 1.0)
		hi.append(pts[i] + off)
	draw_polyline(hi, Color(lit_col.r, lit_col.g, lit_col.b, 0.5 * _alpha), 1.2)

	# Sucker at the tip: a ring with a bright core, gripping while extended.
	var grip := clampf(ext * 1.4, 0.35, 1.0)
	draw_circle(tip, 5.6 * grip + 1.2, Color(edge_col.r, edge_col.g, edge_col.b, 0.5 * _alpha))
	draw_circle(tip, 3.6 * grip + 0.8, Color(body_col.r, body_col.g, body_col.b, 0.95 * _alpha))
	draw_circle(tip - dir * 0.6, 1.7 * grip + 0.4, Color(lit_col.r, lit_col.g, lit_col.b, 0.85 * _alpha))
