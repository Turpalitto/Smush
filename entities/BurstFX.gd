class_name BurstFX
extends Node2D
## Pooled lightweight absorption / evolution / hit particle burst & floating label.

var _particles: Array[Dictionary] = []
var _elapsed: float = 0.0
var _duration: float = 0.55
var _color: Color = Color(0.4, 1.0, 0.8)
var _ring_radius: float = 0.0
var _callout_text: String = ""


func setup(p_pos: Vector2, p_color: Color, count: int = 8, p_ring_radius: float = 0.0, p_callout: String = "") -> void:
	global_position = p_pos
	_color = p_color
	_elapsed = 0.0
	_duration = 0.72 if not p_callout.is_empty() else 0.52
	_ring_radius = p_ring_radius
	_callout_text = p_callout
	_particles.clear()
	var capped := clampi(count, 2, 18)
	for i in range(capped):
		var ang := (TAU / float(capped)) * float(i) + randf_range(-0.25, 0.25)
		var spd := randf_range(50.0, 160.0)
		_particles.append({
			"vel": Vector2.from_angle(ang) * spd,
			"size": randf_range(3.2, 7.0),
			"is_star": (i % 2 == 0) or randf() < 0.45,
			"rot_spd": randf_range(-4.5, 4.5),
			"flutter": randf_range(0.0, TAU)
		})
	queue_redraw()


func is_expired() -> bool:
	return _elapsed >= _duration


func _process(delta: float) -> void:
	_elapsed += delta
	queue_redraw()


func _draw() -> void:
	var t := clampf(_elapsed / _duration, 0.0, 1.0)
	var alpha := 1.0 - t
	# A soft additive bloom at the origin, wider and fainter than the particles.
	var bloom_r := maxf(18.0, _ring_radius * 0.55)
	draw_circle(Vector2.ZERO, bloom_r * (0.55 + t * 0.75),
		Color(_color.r, _color.g, _color.b, alpha * alpha * 0.16), true, -1.0, true)
	if _ring_radius > 0.0:
		var rr := _ring_radius * (0.35 + t * 0.85)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32,
			Color(_color.r, _color.g, _color.b, alpha * 0.22), 7.0, true)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32,
			Color(_color.r, _color.g, _color.b, alpha * 0.42), 3.5, true)
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 32,
			Color(_color.r, _color.g, _color.b, alpha * 0.85), 1.6, true)

	var col_outer := Color(_color.r, _color.g, _color.b, alpha * alpha)
	var col_core := Color(lerpf(_color.r, 1.0, 0.75), lerpf(_color.g, 1.0, 0.75), lerpf(_color.b, 1.0, 0.75), alpha * alpha * 0.95)

	for p: Dictionary in _particles:
		var vel: Vector2 = p["vel"]
		var flutter: float = float(p.get("flutter", 0.0))
		# Particle position with gentle upward fairy-drift & subtle sine wave flutter
		var upward_lift := -20.0 * t * t
		var lateral_sway := sin(_elapsed * 6.0 + flutter) * 5.0 * t
		var pos := vel * (_elapsed * (1.0 - t * 0.35)) + Vector2(lateral_sway, upward_lift)
		var sz: float = float(p["size"]) * (1.0 - t * 0.60)
		var is_star: bool = bool(p.get("is_star", false))

		if is_star and sz > 1.8:
			var rot_spd: float = float(p.get("rot_spd", 0.0))
			var rot := rot_spd * _elapsed
			var ray_len := sz * (1.5 + 0.4 * sin(_elapsed * 10.0 + flutter))
			var d1 := Vector2.from_angle(rot) * ray_len
			var d2 := Vector2.from_angle(rot + PI * 0.5) * ray_len
			draw_line(pos - d1, pos + d1, col_outer, 1.6, true)
			draw_line(pos - d2, pos + d2, col_outer, 1.6, true)
			draw_line(pos - d1 * 0.55, pos + d1 * 0.55, col_core, 1.0, true)
			draw_line(pos - d2 * 0.55, pos + d2 * 0.55, col_core, 1.0, true)
			draw_circle(pos, sz * 0.4, col_core, true, -1.0, true)
		else:
			draw_circle(pos, sz, col_outer, true, -1.0, true)
			draw_circle(pos, sz * 0.45, col_core, true, -1.0, true)
	if not _callout_text.is_empty():
		var font := AssetRegistry.get_ui_font()
		if font != null:
			var y_off := -18.0 - t * 28.0
			var text_a := clampf(1.25 - t * 1.35, 0.0, 1.0)
			draw_string_outline(font, Vector2(-70.0, y_off), _callout_text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 15, 4, Color(0.03, 0.07, 0.09, text_a * 0.92))
			draw_string(font, Vector2(-70.0, y_off), _callout_text, HORIZONTAL_ALIGNMENT_CENTER, 140.0, 15, Color(_color.r, _color.g, _color.b, text_a))
