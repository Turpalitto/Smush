class_name HazardZone
extends Node2D
## Pooled ground hazard / AoE telegraph zone (player poison trail, toad acid, volt shock, boss slam).

enum Kind {
	PLAYER_POISON,
	ENEMY_POISON,
	ENEMY_TELEGRAPH_BLAST,
	BOSS_TELEGRAPH_SLAM
}

var kind: Kind = Kind.PLAYER_POISON
var radius: float = 44.0
var duration: float = 3.0
var elapsed: float = 0.0
var dps_or_burst: float = 15.0
var weaken_enemies: bool = false
var detonate_delay: float = 0.0
var _detonated: bool = false
var _tick_accum: float = 0.0
var arena_ref: Node = null


func setup(p_pos: Vector2, p_kind: Kind, p_radius: float, p_duration: float, p_damage: float, p_arena: Node, p_delay: float = 0.0) -> void:
	global_position = p_pos
	kind = p_kind
	radius = p_radius
	duration = p_duration
	dps_or_burst = p_damage
	arena_ref = p_arena
	detonate_delay = p_delay
	elapsed = 0.0
	_detonated = false
	_tick_accum = 0.0
	weaken_enemies = (p_kind == Kind.PLAYER_POISON)
	queue_redraw()


func is_expired() -> bool:
	return elapsed >= duration


func _process(delta: float) -> void:
	elapsed += delta
	if kind == Kind.ENEMY_TELEGRAPH_BLAST or kind == Kind.BOSS_TELEGRAPH_SLAM:
		if not _detonated and elapsed >= detonate_delay:
			_detonated = true
			if arena_ref != null and arena_ref.has_method("apply_enemy_aoe_burst"):
				arena_ref.call("apply_enemy_aoe_burst", global_position, radius, dps_or_burst, kind == Kind.BOSS_TELEGRAPH_SLAM)
	else:
		_tick_accum += delta
		if _tick_accum >= 0.25:
			var dt := _tick_accum
			_tick_accum = 0.0
			if arena_ref != null:
				if kind == Kind.PLAYER_POISON and arena_ref.has_method("apply_player_poison_tick"):
					arena_ref.call("apply_player_poison_tick", global_position, radius, dps_or_burst * dt)
				elif kind == Kind.ENEMY_POISON and arena_ref.has_method("apply_enemy_poison_tick"):
					arena_ref.call("apply_enemy_poison_tick", global_position, radius, dps_or_burst * dt)
	queue_redraw()


func _draw() -> void:
	var life_left := clampf(1.0 - elapsed / maxf(0.01, duration), 0.0, 1.0)
	match kind:
		Kind.PLAYER_POISON:
			var c := Color(0.48, 0.96, 0.32, 0.34 * life_left)
			draw_circle(Vector2.ZERO, radius, c)
			draw_arc(Vector2.ZERO, radius * 0.88, 0.0, TAU, 24, Color(0.75, 1.0, 0.45, 0.55 * life_left), 2.0)
		Kind.ENEMY_POISON:
			var c2 := Color(0.68, 0.24, 0.86, 0.38 * life_left)
			draw_circle(Vector2.ZERO, radius, c2)
			draw_arc(Vector2.ZERO, radius * 0.92, 0.0, TAU, 24, Color(0.92, 0.40, 1.0, 0.65 * life_left), 2.5)
		Kind.ENEMY_TELEGRAPH_BLAST:
			if not _detonated:
				var prog := clampf(elapsed / maxf(0.05, detonate_delay), 0.0, 1.0)
				var base_col := Color(1.0, 0.62, 0.12, 0.18 + 0.10 * prog)
				var ring_col := Color(1.0, 0.76, 0.18, 0.94).lerp(Color(1.0, 0.36, 0.18, 0.98), prog * 0.65)
				draw_circle(Vector2.ZERO, radius, base_col)
				draw_circle(Vector2.ZERO, radius * prog, Color(1.0, 0.72, 0.16, 0.30))
				draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, ring_col, 3.4)
				for k in range(8):
					var ta := float(k) * (TAU / 8.0) + prog * 0.45
					var d_vec := Vector2.from_angle(ta)
					draw_line(d_vec * (radius * 0.84), d_vec * (radius * 1.04), ring_col, 2.4)
			else:
				var flash_e := clampf(1.0 - (elapsed - detonate_delay) / 0.28, 0.0, 1.0)
				draw_circle(Vector2.ZERO, radius * (1.0 + (1.0 - flash_e) * 0.14), Color(1.0, 0.84, 0.32, 0.62 * flash_e))
		Kind.BOSS_TELEGRAPH_SLAM:
			if not _detonated:
				var prog_b := clampf(elapsed / maxf(0.05, detonate_delay), 0.0, 1.0)
				var base_b := Color(1.0, 0.20, 0.32, 0.22 + 0.10 * prog_b)
				var ring_b := Color(1.0, 0.32, 0.40, 0.95)
				draw_circle(Vector2.ZERO, radius, base_b)
				draw_circle(Vector2.ZERO, radius * prog_b, Color(1.0, 0.34, 0.40, 0.32))
				draw_arc(Vector2.ZERO, radius, 0.0, TAU, 36, ring_b, 3.6)
				draw_arc(Vector2.ZERO, radius * 0.92, 0.0, TAU * prog_b, 28, Color(1.0, 0.86, 0.48, 0.85), 2.2)
			else:
				var flash := clampf(1.0 - (elapsed - detonate_delay) / 0.28, 0.0, 1.0)
				draw_circle(Vector2.ZERO, radius * (1.0 + (1.0 - flash) * 0.12), Color(1.0, 0.86, 0.48, 0.58 * flash))
