class_name CollectibleOrb
extends Node2D
## Pooled nutrient spore / Forest Essence crystal pickup with suction animation.

## Sparks shed behind an orb while it is being pulled in. They are the one visual
## that says "this thing is coming to you" before it arrives; the shrink alone
## reads as a scale tween. Four per shed, short-lived, and capped overall so a
## full orb field stays inside the draw-call budget.
const PULL_SPARKS: int = 4
const SPARK_LIFE: float = 0.34
const SPARK_EVERY: float = 0.055
const SPARK_MAX: int = 14

var orb_type: String = "spore" # "spore", "essence", or "dew"
var mass_value: float = 0.85
var xp_value: float = 5.0
var essence_value: int = 0
var heal_value: float = 1.2
var magnet_charged: bool = false
var orb_color: Color = Color(0.45, 1.0, 0.78, 0.95)
var being_pulled_by: Node2D = null
var _pull_time: float = 0.0
var _bob_phase: float = 0.0
## Each spark is {pos: Vector2 in world space, age: float}. World space, not local:
## the orb itself is moving, and a spark has to stay where it was shed.
var _sparks: Array[Dictionary] = []
var _spark_cd: float = 0.0


func setup(p_pos: Vector2, p_type: String, p_mass: float, p_xp: float, p_essence: int = 0, p_heal: float = -1.0) -> void:
	global_position = p_pos
	orb_type = p_type
	mass_value = p_mass
	xp_value = p_xp
	essence_value = p_essence
	heal_value = p_heal if p_heal >= 0.0 else (10.0 if p_type == "dew" else (2.5 if p_type == "essence" else 1.2))
	magnet_charged = false
	being_pulled_by = null
	_pull_time = 0.0
	_bob_phase = randf() * TAU
	scale = Vector2.ONE
	_sparks.clear()
	_spark_cd = 0.0
	if orb_type == "essence":
		orb_color = Color(0.40, 0.98, 0.85, 1.0)
	elif orb_type == "dew":
		orb_color = Color(0.58, 1.0, 0.52, 1.0)
	else:
		orb_color = Color.from_hsv(randf_range(0.32, 0.55), 0.65, 1.0, 0.92)
	queue_redraw()


func start_suction(target: Node2D) -> void:
	if being_pulled_by == null:
		being_pulled_by = target
		_pull_time = 0.0


func _process(delta: float) -> void:
	_bob_phase += delta * 4.0
	for i in range(_sparks.size() - 1, -1, -1):
		var s: Dictionary = _sparks[i]
		s["age"] = float(s["age"]) + delta
		if float(s["age"]) >= SPARK_LIFE:
			_sparks.remove_at(i)
	if being_pulled_by != null and is_instance_valid(being_pulled_by):
		_pull_time += delta
		var speed := 420.0 + _pull_time * 950.0
		global_position = global_position.move_toward(being_pulled_by.global_position, speed * delta)
		var shrink := clampf(1.0 - _pull_time * 2.4, 0.25, 1.0)
		scale = Vector2.ONE * shrink
		_shed_sparks(delta)
	queue_redraw()


func spark_count() -> int:
	## Test seam.
	return _sparks.size()


func _shed_sparks(delta: float) -> void:
	_spark_cd -= delta
	if _spark_cd > 0.0 or _sparks.size() >= SPARK_MAX:
		return
	_spark_cd = SPARK_EVERY
	# Shed slightly behind the direction of travel, so the sparks read as a wake
	# rather than as an aura.
	var back := Vector2.ZERO
	if being_pulled_by != null and is_instance_valid(being_pulled_by):
		back = (global_position - being_pulled_by.global_position).normalized()
	for _i in range(PULL_SPARKS):
		var spread := Vector2.from_angle(randf() * TAU) * randf_range(1.5, 6.5)
		_sparks.append({
			"pos": global_position + back * randf_range(3.0, 9.0) + spread,
			"age": 0.0,
		})
	while _sparks.size() > SPARK_MAX:
		_sparks.remove_at(0)


func _draw_glow(radius: float, inner_alpha: float) -> void:
	## Two concentric discs instead of one. A single draw_circle is a hard-edged
	## disc, and on a dark floor a hard disc reads as a flat sticker: the eye sees
	## the rim before it sees the light. The outer disc is wide and faint, the inner
	## one tight and strong, which is the cheapest radial falloff available without
	## a shader of its own.
	draw_circle(Vector2.ZERO, radius * 1.55,
		Color(orb_color.r, orb_color.g, orb_color.b, inner_alpha * 0.34), true, -1.0, true)
	draw_circle(Vector2.ZERO, radius,
		Color(orb_color.r, orb_color.g, orb_color.b, inner_alpha), true, -1.0, true)


func _draw_sparks() -> void:
	for s: Dictionary in _sparks:
		var k := clampf(1.0 - float(s["age"]) / SPARK_LIFE, 0.0, 1.0)
		var local: Vector2 = (s["pos"] as Vector2) - global_position
		draw_circle(local, 1.1 + 2.0 * k,
			Color(orb_color.r, orb_color.g, orb_color.b, k * k * 0.85), true, -1.0, true)


func _draw() -> void:
	var pulse := 1.0 + 0.12 * sin(_bob_phase)
	if orb_type == "essence":
		_draw_glow(13.0 * pulse, 0.26)
		var pts := PackedVector2Array([
			Vector2(0, -10.0 * pulse),
			Vector2(8.0 * pulse, -2.0),
			Vector2(5.5 * pulse, 9.5 * pulse),
			Vector2(-5.5 * pulse, 9.5 * pulse),
			Vector2(-8.0 * pulse, -2.0)
		])
		draw_colored_polygon(pts, orb_color)
		draw_circle(Vector2(-2, -3), 2.5, Color(1, 1, 1, 0.85))
	elif orb_type == "dew":
		_draw_glow(13.5 * pulse, 0.30)
		draw_circle(Vector2.ZERO, 7.8 * pulse, orb_color)
		draw_line(Vector2(-3.5, 0.0), Vector2(3.5, 0.0), Color(1.0, 1.0, 0.90, 0.92), 2.0)
		draw_line(Vector2(0.0, -3.5), Vector2(0.0, 3.5), Color(1.0, 1.0, 0.90, 0.92), 2.0)
	else:
		_draw_glow(9.5 * pulse, 0.24)
		draw_circle(Vector2.ZERO, 5.8 * pulse, orb_color)
		draw_circle(Vector2(-1.6, -1.8), 2.0, Color(1, 1, 1, 0.8))
	_draw_sparks()
