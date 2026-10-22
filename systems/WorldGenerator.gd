class_name WorldGenerator
extends Node2D
## Procedural Enchanted Forest ("Зачарованный лес") generator with passability validation,
## central safe spawn clearing, boss clearing, living flora, and narrow tactical passages.

const ARENA_HALF_SIZE: float = 1280.0
const SAFE_SPAWN_RADIUS: float = 270.0
const MIN_OBSTACLE_CLEARANCE: float = 175.0

var obstacles: Array[Dictionary] = [] # {pos: Vector2, radius: float, kind: String}
var narrow_gates: Array[Dictionary] = [] # {center: Vector2, axis: Vector2, half_gap: float}
var decor_flora: Array[Dictionary] = []
var ambient_spores: Array[Dictionary] = []

var _rng: RandomNumberGenerator = RandomNumberGenerator.new()
var _anim_time: float = 0.0
var _obstacle_root: Node2D


func generate_world(seed_val: int = 0) -> void:
	if seed_val != 0:
		_rng.seed = seed_val
	else:
		_rng.randomize()

	obstacles.clear()
	narrow_gates.clear()
	decor_flora.clear()
	ambient_spores.clear()

	if _obstacle_root != null:
		_obstacle_root.queue_free()
	_obstacle_root = Node2D.new()
	_obstacle_root.name = "StaticObstacles"
	add_child(_obstacle_root)

	# 1. Place 4 tactical Narrow Root Passages at cardinal mid-ring positions (r ~ 560 px)
	var gate_dirs: Array[Vector2] = [Vector2.RIGHT, Vector2.LEFT, Vector2.UP, Vector2.DOWN]
	for gdir: Vector2 in gate_dirs:
		var gate_center: Vector2 = gdir * 560.0
		var perp: Vector2 = gdir.orthogonal()
		var half_gap: float = 30.0 # Passable up to radius 30 (or ~38 while Dashing!)
		var pillar_r: float = 34.0
		var p1: Vector2 = gate_center + perp * (half_gap + pillar_r)
		var p2: Vector2 = gate_center - perp * (half_gap + pillar_r)
		_add_static_pillar(p1, pillar_r, "root_pillar")
		_add_static_pillar(p2, pillar_r, "root_pillar")
		narrow_gates.append({
			"center": gate_center,
			"half_gap": half_gap,
			"radius": 38.0
		})

	# 2. Place validated Rune Stones & Mana Crystals with strict passability checks
	var target_obstacles: int = 22
	var attempts: int = 0
	while obstacles.size() < target_obstacles + 8 and attempts < 260:
		attempts += 1
		var pos := Vector2(
			_rng.randf_range(-ARENA_HALF_SIZE + 160.0, ARENA_HALF_SIZE - 160.0),
			_rng.randf_range(-ARENA_HALF_SIZE + 160.0, ARENA_HALF_SIZE - 160.0)
		)
		# Keep spawn clearing (0,0) and boss northern shrine (0, -480) open and passable!
		if pos.length() < SAFE_SPAWN_RADIUS:
			continue
		if pos.distance_to(Vector2(0.0, -480.0)) < 210.0:
			continue
		var r := _rng.randf_range(26.0, 44.0)
		if not _has_clearance(pos, r):
			continue
		var kind := "mana_crystal" if (_rng.randf() < 0.45) else "rune_stone"
		_add_static_pillar(pos, r, kind)

	# 3. Decorative living forest flora (glowing mushrooms, moss rings, fern tufts — non-blocking)
	for _i in range(68):
		var fpos := Vector2(
			_rng.randf_range(-ARENA_HALF_SIZE + 60.0, ARENA_HALF_SIZE - 60.0),
			_rng.randf_range(-ARENA_HALF_SIZE + 60.0, ARENA_HALF_SIZE - 60.0)
		)
		decor_flora.append({
			"pos": fpos,
			"scale": _rng.randf_range(0.7, 1.35),
			"kind": _rng.randi() % 3,
			"phase": _rng.randf() * TAU,
			"hue": _rng.randf_range(0.36, 0.56)
		})

	# 4. Drifting bioluminescent air spores
	for _i in range(36):
		ambient_spores.append({
			"pos": Vector2(_rng.randf_range(-ARENA_HALF_SIZE, ARENA_HALF_SIZE), _rng.randf_range(-ARENA_HALF_SIZE, ARENA_HALF_SIZE)),
			"vel": Vector2(_rng.randf_range(-14.0, 14.0), _rng.randf_range(-18.0, -6.0)),
			"size": _rng.randf_range(2.0, 4.4),
			"phase": _rng.randf() * TAU
		})

	queue_redraw()


func _has_clearance(candidate: Vector2, r: float) -> bool:
	for ob: Dictionary in obstacles:
		var opos: Vector2 = ob["pos"]
		var orad: float = float(ob["radius"])
		if candidate.distance_to(opos) < (r + orad + MIN_OBSTACLE_CLEARANCE * 0.55):
			return false
	for gate: Dictionary in narrow_gates:
		var gpos: Vector2 = gate["center"]
		if candidate.distance_to(gpos) < 150.0:
			return false
	return true


func _add_static_pillar(pos: Vector2, r: float, kind: String) -> void:
	obstacles.append({"pos": pos, "radius": r, "kind": kind})
	var sb := StaticBody2D.new()
	sb.collision_layer = 4
	sb.collision_mask = 0
	sb.position = pos
	var cs := CollisionShape2D.new()
	var shape := CircleShape2D.new()
	shape.radius = r * 0.92
	cs.shape = shape
	sb.add_child(cs)
	_obstacle_root.add_child(sb)


func is_safe_spawn_point(pos: Vector2, entity_radius: float = 24.0) -> bool:
	if absf(pos.x) > ARENA_HALF_SIZE - entity_radius - 20.0 or absf(pos.y) > ARENA_HALF_SIZE - entity_radius - 20.0:
		return false
	for ob: Dictionary in obstacles:
		var opos: Vector2 = ob["pos"]
		var orad: float = float(ob["radius"])
		if pos.distance_to(opos) < (orad + entity_radius + 18.0):
			return false
	return true


func pick_valid_spawn_point(avoid_pos: Vector2, min_dist_from_avoid: float, max_dist_from_avoid: float) -> Vector2:
	for _attempt in range(30):
		var ang := _rng.randf() * TAU
		var d := _rng.randf_range(min_dist_from_avoid, max_dist_from_avoid)
		var cand := avoid_pos + Vector2.from_angle(ang) * d
		cand.x = clampf(cand.x, -ARENA_HALF_SIZE + 80.0, ARENA_HALF_SIZE - 80.0)
		cand.y = clampf(cand.y, -ARENA_HALF_SIZE + 80.0, ARENA_HALF_SIZE - 80.0)
		if is_safe_spawn_point(cand, 28.0):
			return cand
	return Vector2(clampf(avoid_pos.x + 280.0, -1000.0, 1000.0), clampf(avoid_pos.y, -1000.0, 1000.0))


func _process(delta: float) -> void:
	_anim_time += delta
	for sp: Dictionary in ambient_spores:
		var p: Vector2 = sp["pos"] + (sp["vel"] as Vector2) * delta
		if p.y < -ARENA_HALF_SIZE:
			p.y = ARENA_HALF_SIZE
		sp["pos"] = p
	queue_redraw()


func _draw() -> void:
	# Arena enchanted border hedge & rune boundary
	var border_rect := Rect2(-ARENA_HALF_SIZE, -ARENA_HALF_SIZE, ARENA_HALF_SIZE * 2.0, ARENA_HALF_SIZE * 2.0)
	draw_rect(border_rect, Color(0.24, 0.78, 0.62, 0.45), false, 8.0)
	draw_rect(border_rect.grow(16.0), Color(0.04, 0.09, 0.11, 0.85), false, 24.0)

	# Central sanctuary moss ring
	draw_arc(Vector2.ZERO, SAFE_SPAWN_RADIUS * 0.75, 0.0, TAU, 48, Color(0.32, 0.85, 0.68, 0.16), 4.0)

	# Decorative flora (soft colors, glowing mushrooms, fern clusters)
	for fl: Dictionary in decor_flora:
		var p: Vector2 = fl["pos"]
		var sc: float = float(fl["scale"])
		var ph: float = float(fl["phase"])
		var sway := sin(_anim_time * 1.8 + ph) * 2.5
		var kind: int = int(fl["kind"])
		if kind == 0:
			# Glowing mushroom cluster
			var glow_a := 0.18 + 0.07 * sin(_anim_time * 2.6 + ph)
			var mcol := Color.from_hsv(float(fl["hue"]), 0.58, 0.98, 0.85)
			draw_circle(p, 18.0 * sc, Color(mcol.r, mcol.g, mcol.b, glow_a))
			draw_circle(p + Vector2(sway * 0.4, -3.0), 7.5 * sc, mcol)
			draw_circle(p + Vector2(6.0 * sc, 4.0 * sc), 5.0 * sc, mcol)
		elif kind == 1:
			# Soft mossy pad
			draw_circle(p, 22.0 * sc, Color(0.14, 0.34, 0.28, 0.38))
		else:
			# Swaying enchanted fern
			for leaf_i in range(4):
				var la := float(leaf_i) * (PI * 0.5) + 0.4 + sway * 0.04
				draw_line(p, p + Vector2.from_angle(la) * (14.0 * sc), Color(0.25, 0.68, 0.48, 0.55), 3.0)

	# Narrow passage floor rune markers
	for gate: Dictionary in narrow_gates:
		var gc: Vector2 = gate["center"]
		draw_circle(gc, 24.0, Color(0.45, 0.95, 0.82, 0.14))
		draw_arc(gc, 24.0, 0.0, TAU, 20, Color(0.55, 1.0, 0.88, 0.35), 2.0)

	# Physical Obstacles (Rune Stones, Mana Crystals, Root Pillars)
	for ob: Dictionary in obstacles:
		var p: Vector2 = ob["pos"]
		var r: float = float(ob["radius"])
		var okind: String = str(ob["kind"])
		draw_circle(p + Vector2(0, r * 0.32), r * 0.95, Color(0, 0, 0, 0.34))
		if okind == "mana_crystal":
			var glow := 0.22 + 0.08 * sin(_anim_time * 2.4 + p.x * 0.02)
			draw_circle(p, r * 1.35, Color(0.35, 0.88, 1.0, glow))
			var poly := PackedVector2Array([
				p + Vector2(0, -r * 1.08),
				p + Vector2(r * 0.88, -r * 0.22),
				p + Vector2(r * 0.62, r * 0.88),
				p + Vector2(-r * 0.62, r * 0.88),
				p + Vector2(-r * 0.88, -r * 0.22)
			])
			draw_colored_polygon(poly, Color(0.28, 0.76, 0.94, 0.95))
			draw_circle(p + Vector2(-r * 0.22, -r * 0.28), r * 0.22, Color(0.85, 0.98, 1.0, 0.78))
		elif okind == "root_pillar":
			draw_circle(p, r, Color(0.24, 0.42, 0.32, 0.98))
			draw_arc(p, r * 0.72, 0.0, TAU, 18, Color(0.48, 0.92, 0.68, 0.55), 3.0)
		else:
			draw_circle(p, r, Color(0.26, 0.33, 0.38, 0.98))
			draw_arc(p, r * 0.58, 0.0, TAU, 16, Color(0.45, 0.95, 0.82, 0.62), 2.5)

	# Drifting ambient bioluminescent spores
	if str(SaveData.get_setting("fx_quality", "high")) != "low":
		for sp: Dictionary in ambient_spores:
			var sp_pos: Vector2 = sp["pos"]
			var a := 0.35 + 0.25 * sin(_anim_time * 2.5 + float(sp["phase"]))
			draw_circle(sp_pos, float(sp["size"]), Color(0.68, 1.0, 0.85, a))
