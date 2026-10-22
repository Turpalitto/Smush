class_name BurstFX
extends Node2D
## Pooled lightweight absorption / evolution / hit particle burst & floating label.

var _particles: Array[Dictionary] = []
var _elapsed: float = 0.0
var _duration: float = 0.55
var _color: Color = Color(0.4, 1.0, 0.8)
var _ring_radius: float = 0.0


func setup(p_pos: Vector2, p_color: Color, count: int = 8, p_ring_radius: float = 0.0) -> void:
	global_position = p_pos
	_color = p_color
	_elapsed = 0.0
	_duration = 0.52
	_ring_radius = p_ring_radius
	_particles.clear()
	var capped := clampi(count, 3, 18)
	for i in range(capped):
		var ang := (TAU / float(capped)) * float(i) + randf_range(-0.25, 0.25)
		var spd := randf_range(55.0, 165.0)
		_particles.append({
			"vel": Vector2.from_angle(ang) * spd,
			"size": randf_range(3.0, 6.8)
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
	if _ring_radius > 0.0:
		draw_arc(Vector2.ZERO, _ring_radius * (0.35 + t * 0.85), 0.0, TAU, 32, Color(_color.r, _color.g, _color.b, alpha * 0.85), 3.0)
	for p: Dictionary in _particles:
		var vel: Vector2 = p["vel"]
		var pos := vel * (_elapsed * (1.0 - t * 0.35))
		var sz: float = float(p["size"]) * (1.0 - t * 0.65)
		draw_circle(pos, sz, Color(_color.r, _color.g, _color.b, alpha))
