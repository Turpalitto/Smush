class_name CollectibleOrb
extends Node2D
## Pooled nutrient spore / Forest Essence crystal pickup with suction animation.

var orb_type: String = "spore" # "spore" or "essence"
var mass_value: float = 0.85
var xp_value: float = 5.0
var essence_value: int = 0
var orb_color: Color = Color(0.45, 1.0, 0.78, 0.95)
var being_pulled_by: Node2D = null
var _pull_time: float = 0.0
var _bob_phase: float = 0.0


func setup(p_pos: Vector2, p_type: String, p_mass: float, p_xp: float, p_essence: int = 0) -> void:
	global_position = p_pos
	orb_type = p_type
	mass_value = p_mass
	xp_value = p_xp
	essence_value = p_essence
	being_pulled_by = null
	_pull_time = 0.0
	_bob_phase = randf() * TAU
	scale = Vector2.ONE
	if orb_type == "essence":
		orb_color = Color(0.40, 0.98, 0.85, 1.0)
	else:
		orb_color = Color.from_hsv(randf_range(0.32, 0.55), 0.65, 1.0, 0.92)
	queue_redraw()


func start_suction(target: Node2D) -> void:
	if being_pulled_by == null:
		being_pulled_by = target
		_pull_time = 0.0


func _process(delta: float) -> void:
	_bob_phase += delta * 4.0
	if being_pulled_by != null and is_instance_valid(being_pulled_by):
		_pull_time += delta
		var speed := 420.0 + _pull_time * 950.0
		global_position = global_position.move_toward(being_pulled_by.global_position, speed * delta)
		var shrink := clampf(1.0 - _pull_time * 2.4, 0.25, 1.0)
		scale = Vector2.ONE * shrink
	queue_redraw()


func _draw() -> void:
	var pulse := 1.0 + 0.12 * sin(_bob_phase)
	if orb_type == "essence":
		draw_circle(Vector2.ZERO, 13.0 * pulse, Color(orb_color.r, orb_color.g, orb_color.b, 0.24))
		var pts := PackedVector2Array([
			Vector2(0, -10.0 * pulse),
			Vector2(8.0 * pulse, -2.0),
			Vector2(5.5 * pulse, 9.5 * pulse),
			Vector2(-5.5 * pulse, 9.5 * pulse),
			Vector2(-8.0 * pulse, -2.0)
		])
		draw_colored_polygon(pts, orb_color)
		draw_circle(Vector2(-2, -3), 2.5, Color(1, 1, 1, 0.85))
	else:
		draw_circle(Vector2.ZERO, 9.5 * pulse, Color(orb_color.r, orb_color.g, orb_color.b, 0.22))
		draw_circle(Vector2.ZERO, 5.8 * pulse, orb_color)
		draw_circle(Vector2(-1.6, -1.8), 2.0, Color(1, 1, 1, 0.8))
