class_name SlimeVisual
extends Node2D
## Procedural + Shader 2D visual representation of the main Slime character.
## Implements squash & stretch, absorption bulge, core pulsation, movement trail,
## expressive eyes, damage flash, death dissolve, evolution aura, and visual attachments
## for all 12 mutations and 5 synergies.

var radius: float = 25.0
var look_dir: Vector2 = Vector2.DOWN
var velocity_vec: Vector2 = Vector2.ZERO
var squash_stretch: Vector2 = Vector2.ONE
var gulp_bulge: float = 0.0
var hurt_flash: float = 0.0
var evolution_flash: float = 0.0
var stealth_alpha: float = 1.0
var shield_active: bool = false
var is_dashing: bool = false
var is_dying: bool = false
var death_progress: float = 0.0

var mutation_levels: Dictionary = {}
var active_synergies: Dictionary = {}
var active_tendril_targets: Array[Vector2] = []

var _jelly_rect: ColorRect
var _shader_mat: ShaderMaterial
var _trail_points: Array[Vector2] = []
var _trail_accum: float = 0.0
var _blink_timer: float = 2.8
var _blink_open: float = 1.0
var _anim_time: float = 0.0

var _body_color: Color = Color("#22d0a8")
var _core_color: Color = Color("#fff080")
var _rim_color: Color = Color("#a5ffe8")
var _trail_color: Color = Color("#5ef5c8")


func _ready() -> void:
	_jelly_rect = ColorRect.new()
	_jelly_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load("res://shaders/slime_body.gdshader") as Shader
	if shader != null:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
		_jelly_rect.material = _shader_mat
	add_child(_jelly_rect)
	apply_cosmetics()
	Events.slime_form_changed.connect(func(_fid: String) -> void: apply_cosmetics())


func apply_cosmetics() -> void:
	var form_id: String = str(SaveData.data.get("selected_form", "forest_drop"))
	var fcfg: Dictionary = ConfigDB.slime_forms.get(form_id, {})
	if not fcfg.is_empty():
		_body_color = Color(str(fcfg.get("body_color", "#22d0a8")))
		_body_color.a = 0.90
		_core_color = Color(str(fcfg.get("core_color", "#fff080")))
		_rim_color = Color(str(fcfg.get("rim_color", "#a5ffe8")))

	var trail_id: String = str(SaveData.data.get("selected_trail", "default_gel"))
	var tcfg: Dictionary = ConfigDB.trail_fx.get(trail_id, {})
	if not tcfg.is_empty():
		_trail_color = Color(str(tcfg.get("color", "#5ef5c8")))

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("body_color", _body_color)
		_shader_mat.set_shader_parameter("core_color", _core_color)
		_shader_mat.set_shader_parameter("rim_color", _rim_color)


func trigger_gulp() -> void:
	gulp_bulge = 0.28


func trigger_hurt() -> void:
	hurt_flash = 1.0
	squash_stretch = Vector2(1.28, 0.76)


func trigger_evolution() -> void:
	evolution_flash = 1.0
	gulp_bulge = 0.35


func trigger_wall_bump(normal: Vector2) -> void:
	if absf(normal.x) > absf(normal.y):
		squash_stretch = Vector2(0.76, 1.24)
	else:
		squash_stretch = Vector2(1.24, 0.76)


func _process(delta: float) -> void:
	_anim_time += delta
	gulp_bulge = move_toward(gulp_bulge, 0.0, delta * 1.4)
	hurt_flash = move_toward(hurt_flash, 0.0, delta * 3.2)
	evolution_flash = move_toward(evolution_flash, 0.0, delta * 1.6)

	# Compute target squash & stretch from velocity
	var speed := velocity_vec.length()
	var stretch_amt := clampf(speed / 420.0, 0.0, 0.26)
	if is_dashing:
		stretch_amt = 0.36
	var target_ss := Vector2(1.0 + stretch_amt, 1.0 - stretch_amt * 0.62)
	squash_stretch = squash_stretch.lerp(target_ss, 1.0 - exp(-14.0 * delta))

	# Blinking eyes
	_blink_timer -= delta
	if _blink_timer <= 0.0:
		_blink_timer = randf_range(2.4, 4.8)
	_blink_open = 0.12 if _blink_timer < 0.11 else 1.0

	# Update movement trail points in world space
	_trail_accum += delta
	if _trail_accum >= 0.045 and speed > 28.0 and not is_dying:
		_trail_accum = 0.0
		_trail_points.push_front(global_position)
		if _trail_points.size() > 12:
			_trail_points.pop_back()
	elif speed <= 28.0 and not _trail_points.is_empty() and _trail_accum >= 0.08:
		_trail_accum = 0.0
		_trail_points.pop_back()

	# Size & orient jelly shader rect
	var eff_r := radius * (1.0 + gulp_bulge * 0.25)
	if is_dying:
		eff_r *= (1.0 + death_progress * 0.45)
	if _jelly_rect != null:
		var box := eff_r * 2.25
		_jelly_rect.size = Vector2(box, box)
		_jelly_rect.position = -Vector2(box, box) * 0.5
		_jelly_rect.pivot_offset = Vector2(box, box) * 0.5
		_jelly_rect.rotation = velocity_vec.angle() if speed > 15.0 else 0.0
		_jelly_rect.scale = squash_stretch

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("hurt_flash", hurt_flash)
		var eff_alpha := stealth_alpha * (1.0 - death_progress)
		_shader_mat.set_shader_parameter("stealth_alpha", clampf(eff_alpha, 0.05, 1.0))
		_shader_mat.set_shader_parameter("evolution_glow", evolution_flash)

	queue_redraw()


func _draw() -> void:
	var eff_r := radius * (1.0 + gulp_bulge * 0.22)
	var alpha_mult := stealth_alpha * (1.0 - death_progress)

	# 1. Movement trail behind slime
	for i in range(_trail_points.size()):
		var local_p := to_local(_trail_points[i])
		var t := 1.0 - float(i) / float(maxi(1, _trail_points.size()))
		var tr := eff_r * 0.48 * t
		draw_circle(local_p, tr, Color(_trail_color.r, _trail_color.g, _trail_color.b, 0.26 * t * alpha_mult))

	# 2. 2.5D angled ground shadow
	draw_circle(Vector2(0.0, eff_r * 0.42), eff_r * 0.88, Color(0.02, 0.05, 0.07, 0.34 * alpha_mult))

	# 3. Behind-body / perimeter Mutation visuals
	if int(mutation_levels.get("magnet", 0)) > 0:
		var mag_col := Color(0.35, 0.88, 1.0, 0.28 * alpha_mult)
		if bool(active_synergies.get("em_storm", false)):
			mag_col = Color(1.0, 0.92, 0.35, 0.45 * alpha_mult)
		draw_arc(Vector2.ZERO, eff_r * 1.45, _anim_time * 2.0, _anim_time * 2.0 + PI * 1.3, 24, mag_col, 2.2)
		draw_arc(Vector2.ZERO, eff_r * 1.25, -_anim_time * 2.4, -_anim_time * 2.4 + PI * 1.1, 20, mag_col, 1.8)

	if int(mutation_levels.get("speed_boost", 0)) > 0:
		var back_ang := (velocity_vec.angle() + PI) if velocity_vec.length() > 15.0 else -PI * 0.5
		for side in [-0.55, 0.55]:
			var fin_dir := Vector2.from_angle(back_ang + side)
			var p1 := fin_dir * (eff_r * 0.78)
			var p2 := fin_dir * (eff_r * 1.32)
			var perp := fin_dir.orthogonal() * (eff_r * 0.22)
			draw_colored_polygon(PackedVector2Array([p1 + perp, p2, p1 - perp]), Color(0.55, 1.0, 0.88, 0.65 * alpha_mult))

	if int(mutation_levels.get("spikes", 0)) > 0:
		var spike_cnt: int = 6 + int(mutation_levels.get("spikes", 1))
		var sp_col := Color(1.0, 0.42, 0.52, 0.92 * alpha_mult)
		if bool(active_synergies.get("piercing_strike", false)):
			sp_col = Color(1.0, 0.85, 0.38, 0.95 * alpha_mult)
		for i in range(spike_cnt):
			var a := (TAU / float(spike_cnt)) * float(i) + _anim_time * 0.9
			var dir := Vector2.from_angle(a)
			var tang := dir.orthogonal() * (eff_r * 0.14)
			var base := dir * (eff_r * 0.86)
			var tip := dir * (eff_r * 1.26)
			draw_colored_polygon(PackedVector2Array([base - tang, tip, base + tang]), sp_col)

	if int(mutation_levels.get("dash", 0)) > 0 and is_dashing:
		var jet_dir := (-velocity_vec.normalized()) if velocity_vec.length() > 1.0 else Vector2.UP
		draw_circle(jet_dir * eff_r * 1.05, eff_r * 0.45, Color(1.0, 0.78, 0.32, 0.72))

	# 4. Ranged Absorb tendrils reaching out to prey
	if not active_tendril_targets.is_empty():
		var t_col := Color(0.86, 0.42, 1.0, 0.82) if not bool(active_synergies.get("bio_vampirism", false)) else Color(1.0, 0.28, 0.55, 0.90)
		for world_t in active_tendril_targets:
			var lp := to_local(world_t)
			var mid := lp * 0.5 + lp.orthogonal() * 0.14 * sin(_anim_time * 10.0)
			draw_polyline(PackedVector2Array([Vector2.ZERO, mid, lp]), t_col, 4.0)
			draw_circle(lp, 5.5, t_col)

	# 5. Internal & crown Mutation visuals (drawn on top of jelly shader)
	if int(mutation_levels.get("regeneration", 0)) > 0:
		for i in range(3):
			var oa := _anim_time * 1.6 + float(i) * (TAU / 3.0)
			var op := Vector2.from_angle(oa) * (eff_r * 0.42)
			draw_circle(op, 3.8, Color(0.55, 1.0, 0.52, 0.85 * alpha_mult))

	if int(mutation_levels.get("poison_trail", 0)) > 0:
		for i in range(4):
			var pa := -_anim_time * 1.4 + float(i) * (TAU / 4.0)
			var pp := Vector2.from_angle(pa) * (eff_r * 0.68)
			draw_circle(pp, 3.6, Color(0.68, 1.0, 0.25, 0.78 * alpha_mult))

	if int(mutation_levels.get("split", 0)) > 0:
		var sa := _anim_time * 2.8
		var sp := Vector2.from_angle(sa) * (eff_r * 0.52)
		draw_circle(sp, eff_r * 0.20, Color(1.0, 0.98, 0.68, 0.88 * alpha_mult))

	if int(mutation_levels.get("electro_discharge", 0)) > 0:
		for i in range(3):
			var ea := _anim_time * 6.5 + float(i) * 2.1
			var p_a := Vector2.from_angle(ea) * (eff_r * 0.72)
			var p_b := Vector2.from_angle(ea + 0.35) * (eff_r * 1.06)
			draw_line(p_a, p_b, Color(1.0, 0.95, 0.42, 0.90 * alpha_mult), 2.2)

	if int(mutation_levels.get("freeze", 0)) > 0:
		for i in range(4):
			var fa := _anim_time * 1.2 + float(i) * (PI * 0.5)
			var fp := Vector2.from_angle(fa) * (eff_r * 1.12)
			draw_circle(fp, 3.5, Color(0.78, 0.96, 1.0, 0.85 * alpha_mult))

	if int(mutation_levels.get("mimicry", 0)) > 0:
		var top := Vector2(0.0, -eff_r * 0.94)
		var leaf := PackedVector2Array([
			top,
			top + Vector2(-9.0, -10.0),
			top + Vector2(0.0, -18.0),
			top + Vector2(9.0, -10.0)
		])
		draw_colored_polygon(leaf, Color(0.48, 0.96, 0.55, 0.92 * alpha_mult))

	# 6. Expressive Eyes (drawn over cytoplasm!)
	if not is_dying:
		var look_off := look_dir.normalized() * (eff_r * 0.14)
		var eye_sep := eff_r * 0.34
		var eye_y := -eff_r * 0.10
		var eye_r := clampf(eff_r * 0.17, 3.5, 8.5)
		for side in [-1.0, 1.0]:
			var ep := Vector2(side * eye_sep, eye_y) + look_off
			if hurt_flash > 0.35:
				# Hurt squint (> <)
				draw_line(ep + Vector2(-eye_r, -eye_r * 0.6), ep + Vector2(eye_r * 0.5, 0), Color(0.08, 0.12, 0.18, alpha_mult), 2.4)
				draw_line(ep + Vector2(-eye_r, eye_r * 0.6), ep + Vector2(eye_r * 0.5, 0), Color(0.08, 0.12, 0.18, alpha_mult), 2.4)
			elif _blink_open < 0.3:
				draw_line(ep + Vector2(-eye_r, 0), ep + Vector2(eye_r, 0), Color(0.06, 0.12, 0.16, alpha_mult), 2.2)
			else:
				draw_circle(ep, eye_r, Color(0.06, 0.12, 0.17, alpha_mult))
				draw_circle(ep + Vector2(-eye_r * 0.28, -eye_r * 0.28), eye_r * 0.36, Color(1.0, 1.0, 1.0, alpha_mult))

	# 7. Shield dome & Evolution burst ring
	if shield_active:
		var sh_col := Color(0.45, 0.85, 1.0, 0.72 * alpha_mult)
		if bool(active_synergies.get("ice_armor", false)):
			sh_col = Color(0.78, 0.97, 1.0, 0.88 * alpha_mult)
		draw_circle(Vector2.ZERO, eff_r * 1.18, Color(sh_col.r, sh_col.g, sh_col.b, 0.14))
		draw_arc(Vector2.ZERO, eff_r * 1.18, 0.0, TAU, 32, sh_col, 2.8)

	if evolution_flash > 0.02:
		var er := eff_r * (1.1 + (1.0 - evolution_flash) * 1.4)
		draw_arc(Vector2.ZERO, er, 0.0, TAU, 36, Color(0.55, 1.0, 0.82, evolution_flash), 3.5)
