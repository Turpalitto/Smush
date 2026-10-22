class_name SlimeClone
extends Node2D
## Temporary autonomous decoy/gatherer spawned by the 'split' mutation (and 'toxic_clones' synergy).

var owner_slime: Node2D = null
var arena_ref: Node = null
var duration: float = 6.5
var elapsed: float = 0.0
var contact_dps: float = 18.0
var leaves_toxic_trail: bool = false
var speed: float = 215.0
var loaned_mass: float = 1.0
var _trail_timer: float = 0.0
var _attack_tick: float = 0.0
var _wobble: float = 0.0


func setup(p_owner: Node2D, p_arena: Node, pos: Vector2, p_duration: float, p_dps: float, p_toxic: bool, p_loaned_mass: float) -> void:
	owner_slime = p_owner
	arena_ref = p_arena
	global_position = pos
	duration = p_duration
	contact_dps = p_dps
	leaves_toxic_trail = p_toxic
	loaned_mass = p_loaned_mass
	elapsed = 0.0
	_trail_timer = 0.0
	_attack_tick = 0.0
	_wobble = randf() * TAU


func is_expired() -> bool:
	return elapsed >= duration


func _process(delta: float) -> void:
	elapsed += delta
	_wobble += delta * 6.0
	if arena_ref == null or owner_slime == null or not is_instance_valid(owner_slime):
		queue_free()
		return

	# Seek nearest orb or enemy via arena spatial grid
	var target_pos: Vector2 = owner_slime.global_position + Vector2.from_angle(_wobble * 0.4) * 75.0
	if arena_ref.has_method("find_clone_target"):
		var found: Variant = arena_ref.call("find_clone_target", global_position)
		if found is Vector2:
			target_pos = found

	var dir := (target_pos - global_position)
	if dir.length() > 6.0:
		global_position += dir.normalized() * speed * delta

	if leaves_toxic_trail:
		_trail_timer += delta
		if _trail_timer >= 0.48 and arena_ref.has_method("spawn_player_poison_pool"):
			_trail_timer = 0.0
			arena_ref.call("spawn_player_poison_pool", global_position, 32.0, 2.6, contact_dps * 0.8)

	_attack_tick += delta
	if _attack_tick >= 0.22 and arena_ref.has_method("process_clone_contacts"):
		_attack_tick = 0.0
		arena_ref.call("process_clone_contacts", self, global_position, 22.0, contact_dps * 0.22)

	queue_redraw()


func _draw() -> void:
	var r := 15.0 + 1.8 * sin(_wobble)
	var body_c := Color(0.55, 0.98, 0.38, 0.82) if leaves_toxic_trail else Color(0.32, 0.92, 0.88, 0.82)
	draw_circle(Vector2(0, 5), r * 0.85, Color(0, 0, 0, 0.25))
	draw_circle(Vector2.ZERO, r, body_c)
	draw_circle(Vector2.ZERO, r * 0.42, Color(1.0, 0.96, 0.65, 0.92))
	draw_circle(Vector2(-4, -2), 2.4, Color(0.08, 0.12, 0.16))
	draw_circle(Vector2(4, -2), 2.4, Color(0.08, 0.12, 0.16))
