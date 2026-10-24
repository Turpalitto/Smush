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
var slipstream_active: bool = false
var compass_dir: Vector2 = Vector2.ZERO
var compass_color: Color = Color(1.0, 0.84, 0.36)
var is_dashing: bool = false
var is_dying: bool = false
var death_progress: float = 0.0

var mutation_levels: Dictionary = {}
var active_synergies: Dictionary = {}
var active_tendril_targets: Array[Vector2] = []

var _jelly_rect: ColorRect
var _fg_overlay: Node2D
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

## Growth ladder (see EvolutionStages). `growth_t` is continuous 1..15, `stage` is
## its integer part, and `_look` is the blended palette + ornament weights for the
## current position. The body colour is the stage colour pulled toward the chosen
## cosmetic form, so skins still read while the body evolves.
var growth_t: float = 1.0
## Current mass, kept only so the ascension stars can count past stage 15. `growth_t`
## clamps at 15 by design, so it cannot express "another 25 tonnes".
var mass: float = 10.0
## Companion stars lit by growth above the top of the ladder (0..7).
var ascension_stars: int = 0
var stage: int = 1
var _look: Dictionary = {}
var _form_body: Color = Color("#22d0a8")
var _form_core: Color = Color("#fff080")
var _form_rim: Color = Color("#a5ffe8")
var _form_trail: Color = Color("#5ef5c8")
var _back_aura: SlimeAura
var _front_aura: SlimeAura


func _ready() -> void:
	# Behind the body: the ground sigil, the wings and the petal skirt.
	_back_aura = SlimeAura.new()
	_back_aura.name = "GrowthAuraBack"
	_back_aura.front = false
	add_child(_back_aura)

	_jelly_rect = ColorRect.new()
	_jelly_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load("res://shaders/slime_body.gdshader") as Shader
	if shader != null:
		_shader_mat = ShaderMaterial.new()
		_shader_mat.shader = shader
		_jelly_rect.material = _shader_mat
	add_child(_jelly_rect)
	_fg_overlay = Node2D.new()
	_fg_overlay.name = "ForegroundOverlay"
	_fg_overlay.draw.connect(_draw_foreground)
	add_child(_fg_overlay)

	# In front of the body: crown, antlers, halo, orbiting motes.
	_front_aura = SlimeAura.new()
	_front_aura.name = "GrowthAuraFront"
	_front_aura.front = true
	add_child(_front_aura)

	apply_cosmetics()
	Events.slime_form_changed.connect(func(_fid: String) -> void: apply_cosmetics())


func apply_cosmetics() -> void:
	var form_id: String = str(SaveData.data.get("selected_form", "forest_drop"))
	var fcfg: Dictionary = ConfigDB.slime_forms.get(form_id, {})
	if not fcfg.is_empty():
		_form_body = Color(str(fcfg.get("body_color", "#22d0a8")))
		_form_core = Color(str(fcfg.get("core_color", "#fff080")))
		_form_rim = Color(str(fcfg.get("rim_color", "#a5ffe8")))

	var trail_id: String = str(SaveData.data.get("selected_trail", "default_gel"))
	var tcfg: Dictionary = ConfigDB.trail_fx.get(trail_id, {})
	if not tcfg.is_empty():
		_form_trail = Color(str(tcfg.get("color", "#5ef5c8")))

	_recompute_look()


func set_growth(p_mass: float) -> void:
	## Called by the player whenever mass changes. Cheap enough to run on every
	## absorption: it only does arithmetic and touches the shader when the palette
	## actually moved.
	mass = p_mass
	growth_t = EvolutionStages.t_for_mass(p_mass)
	ascension_stars = EvolutionStages.ascension_stars_for_mass(p_mass)
	var new_stage := clampi(int(floorf(growth_t)), 1, EvolutionStages.COUNT)
	_recompute_look()
	if new_stage != stage:
		var rising := new_stage > stage
		stage = new_stage
		if rising:
			trigger_evolution()
			Events.growth_stage_changed.emit(stage, EvolutionStages.name_key_for_stage(stage))


func _recompute_look() -> void:
	_look = EvolutionStages.look_at(growth_t)
	# The stage owns the hue; the cosmetic skin pulls it back toward the form the
	# player chose. The pull is strong at the start of the ladder — so the skin you
	# picked is the slime you meet — and fades as the body grows, because by stage
	# 10 the slime has visibly outgrown the skin. A flat 0.45 was tested first and
	# it flattened the top of the ladder into mud: stage 13's orange came out
	# olive and stage 15's pearl came out mint.
	var w := clampf((growth_t - 1.0) / float(EvolutionStages.COUNT - 1), 0.0, 1.0)
	var k := lerpf(0.45, 0.10, w)
	_body_color = (_look["body_c"] as Color).lerp(_form_body, k)
	_core_color = (_look["core_c"] as Color).lerp(_form_core, k * 0.6)
	_rim_color = (_look["rim_c"] as Color).lerp(_form_rim, k * 0.6)
	_trail_color = (_look["trail_c"] as Color).lerp(_form_trail, k * 0.5)
	_body_color.a = 0.90
	if _shader_mat != null:
		_shader_mat.set_shader_parameter("body_color", _body_color)
		_shader_mat.set_shader_parameter("core_color", _core_color)
		_shader_mat.set_shader_parameter("rim_color", _rim_color)
		_shader_mat.set_shader_parameter("stage_glow", float(_look.get("glow", 0.0)))
		_shader_mat.set_shader_parameter("stage_t", growth_t / float(EvolutionStages.COUNT))
		# A bigger jelly is a heavier jelly: the surface moves in slower, longer
		# waves. This is the one part of growth the silhouette itself carries, and
		# it costs two uniform writes.
		var gt := clampf((growth_t - 1.0) / float(EvolutionStages.COUNT - 1), 0.0, 1.0)
		_shader_mat.set_shader_parameter("wobble_amount", lerpf(0.032, 0.052, gt))
		_shader_mat.set_shader_parameter("wobble_speed", lerpf(4.2, 2.6, gt))


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

	# Computed here (not inside _draw) because the regalia pass needs it too.
	var alpha_mult := stealth_alpha * (1.0 - death_progress)

	if _shader_mat != null:
		_shader_mat.set_shader_parameter("hurt_flash", hurt_flash)
		_shader_mat.set_shader_parameter("stealth_alpha", clampf(alpha_mult, 0.05, 1.0))
		_shader_mat.set_shader_parameter("evolution_glow", evolution_flash)

	if _back_aura != null:
		_back_aura.set_ascension_stars(ascension_stars)
		_back_aura.set_look(_look, eff_r, _anim_time, alpha_mult)
	if _front_aura != null:
		_front_aura.set_ascension_stars(ascension_stars)
		_front_aura.set_look(_look, eff_r, _anim_time, alpha_mult)

	queue_redraw()
	if _fg_overlay != null:
		_fg_overlay.queue_redraw()


func _draw() -> void:
	var eff_r := radius * (1.0 + gulp_bulge * 0.22)
	var alpha_mult := stealth_alpha * (1.0 - death_progress)

	# 1. Movement trail behind slime
	for i in range(_trail_points.size()):
		var local_p := to_local(_trail_points[i])
		var t := 1.0 - float(i) / float(maxi(1, _trail_points.size()))
		var tr := eff_r * 0.48 * t
		draw_circle(local_p, tr, Color(_trail_color.r, _trail_color.g, _trail_color.b, 0.26 * t * alpha_mult))

	# 2. 2.5D angled ground shadow + bioluminescent ground light pool
	var sh_rot := velocity_vec.angle() if velocity_vec.length() > 15.0 else 0.0
	draw_set_transform(Vector2(0.0, eff_r * 0.40), sh_rot, Vector2(squash_stretch.x * 0.92, squash_stretch.y * 0.74))
	draw_circle(Vector2.ZERO, eff_r * 1.42, Color(_body_color.r, _body_color.g, _body_color.b, 0.085 * alpha_mult))
	draw_circle(Vector2.ZERO, eff_r * 1.14, Color(0.01, 0.04, 0.06, 0.18 * alpha_mult))
	draw_circle(Vector2.ZERO, eff_r * 0.92, Color(0.01, 0.04, 0.06, 0.30 * alpha_mult))
	draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	# 3. Behind-body / perimeter Mutation visuals
	if int(mutation_levels.get("magnet", 0)) > 0:
		var mag_col := Color(0.35, 0.88, 1.0, 0.30 * alpha_mult)
		if bool(active_synergies.get("em_storm", false)):
			mag_col = Color(1.0, 0.92, 0.35, 0.48 * alpha_mult)
		draw_arc(Vector2.ZERO, eff_r * 1.45, _anim_time * 2.0, _anim_time * 2.0 + PI * 1.3, 24, mag_col, 2.2)
		draw_arc(Vector2.ZERO, eff_r * 1.25, -_anim_time * 2.4, -_anim_time * 2.4 + PI * 1.1, 20, mag_col, 1.8)

	if int(mutation_levels.get("speed_boost", 0)) > 0:
		var back_ang := (velocity_vec.angle() + PI) if velocity_vec.length() > 15.0 else -PI * 0.5
		var fin_col := Color(0.45, 1.0, 0.94, 0.88 * alpha_mult) if slipstream_active else Color(0.55, 1.0, 0.88, 0.68 * alpha_mult)
		for side: float in [-0.55, 0.55]:
			var fin_dir := Vector2.from_angle(back_ang + side)
			var p1 := fin_dir * (eff_r * 0.78)
			var p2 := fin_dir * (eff_r * (1.44 if slipstream_active else 1.32))
			var perp := fin_dir.orthogonal() * (eff_r * 0.22)
			draw_colored_polygon(PackedVector2Array([p1 + perp, p2, p1 - perp]), fin_col)
		if slipstream_active:
			draw_arc(Vector2.ZERO, eff_r * 1.15, back_ang + PI - 0.85, back_ang + PI + 0.85, 16, Color(0.55, 1.0, 0.95, 0.72 * alpha_mult), 2.6)

	if int(mutation_levels.get("spikes", 0)) > 0:
		var spike_cnt: int = 6 + int(mutation_levels.get("spikes", 1))
		var sp_col := Color(1.0, 0.42, 0.52, 0.94 * alpha_mult)
		var tip_col := Color(1.0, 0.82, 0.88, 0.96 * alpha_mult)
		if bool(active_synergies.get("piercing_strike", false)):
			sp_col = Color(1.0, 0.85, 0.38, 0.96 * alpha_mult)
			tip_col = Color(1.0, 0.98, 0.80, 0.98 * alpha_mult)
		for i in range(spike_cnt):
			var a := (TAU / float(spike_cnt)) * float(i) + _anim_time * 0.9
			var dir := Vector2.from_angle(a)
			var tang := dir.orthogonal() * (eff_r * 0.15)
			var base := dir * (eff_r * 0.84)
			var tip := dir * (eff_r * 1.30)
			draw_colored_polygon(PackedVector2Array([base - tang, tip, base + tang]), sp_col)
			draw_line(base, tip, tip_col, 1.4)

	if int(mutation_levels.get("dash", 0)) > 0 and is_dashing:
		var jet_dir := (-velocity_vec.normalized()) if velocity_vec.length() > 1.0 else Vector2.UP
		draw_circle(jet_dir * eff_r * 1.05, eff_r * 0.45, Color(1.0, 0.78, 0.32, 0.72))

	# 4. Ranged Absorb pseudopod tendrils anchored on outer membrane (never crossing eyes)
	if not active_tendril_targets.is_empty():
		var t_col := Color(0.76, 0.48, 1.0, 0.84) if not bool(active_synergies.get("bio_vampirism", false)) else Color(1.0, 0.30, 0.58, 0.90)
		var idx := 0
		for world_t in active_tendril_targets:
			var lp := to_local(world_t)
			var dist := lp.length()
			if dist > eff_r * 0.9:
				var dir := lp / dist
				var start_p := dir * (eff_r * 0.84)
				var span := lp - start_p
				var ortho := dir.orthogonal() * (10.0 * sin(_anim_time * 9.0 + float(idx) * 2.1))
				var q1 := start_p + span * 0.33 + ortho
				var q2 := start_p + span * 0.68 - ortho * 0.65
				draw_polyline(PackedVector2Array([start_p, q1, q2, lp]), t_col, 3.8)
				draw_circle(lp, 5.2, t_col)
				draw_circle(lp, 2.5, Color(1.0, 0.94, 1.0, 0.85))
			idx += 1


func _draw_foreground() -> void:
	if _fg_overlay == null:
		return
	var eff_r := radius * (1.0 + gulp_bulge * 0.22)
	var alpha_mult := stealth_alpha * (1.0 - death_progress)

	# 5. Internal & crown Mutation visuals rendered cleanly above jelly shader
	if int(mutation_levels.get("regeneration", 0)) > 0:
		for i in range(3):
			var oa := _anim_time * 1.6 + float(i) * (TAU / 3.0)
			var op := Vector2.from_angle(oa) * (eff_r * 0.44)
			_fg_overlay.draw_circle(op, 3.8, Color(0.58, 1.0, 0.56, 0.88 * alpha_mult))

	if int(mutation_levels.get("poison_trail", 0)) > 0:
		for i in range(4):
			var pa := -_anim_time * 1.4 + float(i) * (TAU / 4.0)
			var pp := Vector2.from_angle(pa) * (eff_r * 0.68)
			_fg_overlay.draw_circle(pp, 3.6, Color(0.72, 1.0, 0.28, 0.82 * alpha_mult))

	if int(mutation_levels.get("split", 0)) > 0:
		var sa := _anim_time * 2.8
		var sp := Vector2.from_angle(sa) * (eff_r * 0.52)
		_fg_overlay.draw_circle(sp, eff_r * 0.19, Color(1.0, 0.98, 0.72, 0.90 * alpha_mult))

	if int(mutation_levels.get("electro_discharge", 0)) > 0:
		for i in range(3):
			var ea := _anim_time * 6.5 + float(i) * 2.1
			var p_a := Vector2.from_angle(ea) * (eff_r * 0.74)
			var p_m := Vector2.from_angle(ea + 0.18) * (eff_r * 0.96)
			var p_b := Vector2.from_angle(ea + 0.36) * (eff_r * 1.10)
			_fg_overlay.draw_polyline(PackedVector2Array([p_a, p_m, p_b]), Color(1.0, 0.95, 0.42, 0.92 * alpha_mult), 2.2)

	if int(mutation_levels.get("freeze", 0)) > 0:
		for i in range(4):
			var fa := _anim_time * 1.2 + float(i) * (PI * 0.5)
			var fp := Vector2.from_angle(fa) * (eff_r * 1.12)
			_fg_overlay.draw_circle(fp, 3.6, Color(0.80, 0.97, 1.0, 0.88 * alpha_mult))

	if int(mutation_levels.get("mimicry", 0)) > 0:
		var top := Vector2(0.0, -eff_r * 0.90)
		var leaf := PackedVector2Array([
			top,
			top + Vector2(-9.5, -10.0),
			top + Vector2(0.0, -19.0),
			top + Vector2(9.5, -10.0)
		])
		_fg_overlay.draw_colored_polygon(leaf, Color(0.46, 0.96, 0.54, 0.95 * alpha_mult))
		_fg_overlay.draw_line(top, top + Vector2(0.0, -16.0), Color(0.85, 1.0, 0.82, 0.85 * alpha_mult), 1.6)

	# 6. Expressive High-Contrast Eyes & Specular Catchlights (drawn crisp over cytoplasm!)
	if not is_dying:
		var look_off := look_dir.normalized() * (eff_r * 0.16)
		var eye_sep := eff_r * 0.33
		var eye_y := -eff_r * 0.10
		var eye_r := clampf(eff_r * 0.18, 4.0, 8.8)
		for side: float in [-1.0, 1.0]:
			var ep := Vector2(side * eye_sep, eye_y) + look_off
			if hurt_flash > 0.35:
				var sx := -side * eye_r * 0.55
				_fg_overlay.draw_line(ep + Vector2(-sx, -eye_r * 0.65), ep + Vector2(sx, 0.0), Color(0.05, 0.10, 0.15, alpha_mult), 2.6)
				_fg_overlay.draw_line(ep + Vector2(-sx, eye_r * 0.65), ep + Vector2(sx, 0.0), Color(0.05, 0.10, 0.15, alpha_mult), 2.6)
			elif _blink_open < 0.3:
				_fg_overlay.draw_line(ep + Vector2(-eye_r, 0.0), ep + Vector2(eye_r, 0.0), Color(0.05, 0.10, 0.15, alpha_mult), 2.4)
			else:
				_fg_overlay.draw_circle(ep, eye_r * 1.14, Color(0.92, 1.0, 0.96, 0.52 * alpha_mult))
				_fg_overlay.draw_circle(ep, eye_r, Color(0.04, 0.09, 0.14, alpha_mult))
				_fg_overlay.draw_circle(ep + Vector2(-eye_r * 0.30, -eye_r * 0.30), eye_r * 0.38, Color(1.0, 1.0, 1.0, alpha_mult))
				_fg_overlay.draw_circle(ep + Vector2(eye_r * 0.24, eye_r * 0.26), eye_r * 0.16, Color(0.75, 1.0, 0.95, 0.85 * alpha_mult))

	# 7. Shield dome & Evolution burst ring
	if shield_active:
		var sh_col := Color(0.45, 0.88, 1.0, 0.78 * alpha_mult)
		if bool(active_synergies.get("ice_armor", false)):
			sh_col = Color(0.80, 0.97, 1.0, 0.90 * alpha_mult)
		_fg_overlay.draw_circle(Vector2.ZERO, eff_r * 1.18, Color(sh_col.r, sh_col.g, sh_col.b, 0.14))
		_fg_overlay.draw_arc(Vector2.ZERO, eff_r * 1.18, 0.0, TAU, 36, sh_col, 2.8)

	if evolution_flash > 0.02:
		var er := eff_r * (1.1 + (1.0 - evolution_flash) * 1.4)
		_fg_overlay.draw_arc(Vector2.ZERO, er, 0.0, TAU, 36, Color(0.55, 1.0, 0.82, evolution_flash), 3.5)

	# 8. Diegetic compass chevron pointing toward distant Miniboss / Ancient Forest Guardian
	if not is_dying and compass_dir.length_squared() > 0.25:
		var cd := compass_dir.normalized()
		var cp := cd * (eff_r + 32.0 + 3.0 * sin(_anim_time * 5.0))
		var perp := cd.orthogonal() * 7.5
		_fg_overlay.draw_colored_polygon(PackedVector2Array([cp + cd * 11.5, cp - cd * 4.0 + perp, cp - cd * 4.0 - perp]), Color(compass_color.r, compass_color.g, compass_color.b, 0.92))
