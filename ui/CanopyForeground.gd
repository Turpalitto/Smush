class_name CanopyForeground
extends CanvasLayer
## Multi-plane foreground parallax layer rendered between the world and WorldMood (layer 4).
## Draws silhouetted overhanging canopy boughs along the screen corners,
## gentle falling leaves & flower petals, harmless bioluminescent forest butterflies,
## and large soft foreground bokeh light motes moving at 1.42x camera parallax to give the
## 2D arena genuine three-plane vertical depth and relaxing enchanted atmosphere.

var _painter: Control
var _camera_pos: Vector2 = Vector2.ZERO
var _prev_camera_pos: Vector2 = Vector2.ZERO
var _growth: float = 0.0
var _time: float = 0.0

var _motes: Array[Dictionary] = []
var _leaves: Array[Dictionary] = []
var _butterflies: Array[Dictionary] = []
var _stardust: Array[Dictionary] = []

var _tex_broadleaf: Texture2D = null
var _tex_fern: Texture2D = null

const MOTE_COUNT: int = 10
const SOFT_GLOW: Texture2D = preload("res://resources/effects/soft_glow.tres")
const LEAF_COUNT: int = 14
const BUTTERFLY_COUNT: int = 5
const STARDUST_COUNT: int = 12
const PARALLAX_BOUGH: float = 0.28
const PARALLAX_MOTE: float = 1.42
const PARALLAX_LEAF: float = 0.88
const WRAP_SPAN: float = 1480.0


func _ready() -> void:
	layer = 4
	name = "CanopyForeground"
	_tex_broadleaf = AssetRegistry.get_texture("res://resources/art/props/broadleaf_clump.png")
	_tex_fern = AssetRegistry.get_texture("res://resources/art/props/fern_cluster.png")

	_init_motes()
	_init_leaves()
	_init_butterflies()
	_init_stardust()

	_painter = Control.new()
	_painter.name = "ForegroundPainter"
	_painter.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_painter.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_painter.draw.connect(_draw_foreground)
	add_child(_painter)


func _init_motes() -> void:
	_motes.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x51F15EED
	for i in range(MOTE_COUNT):
		_motes.append({
			"pos": Vector2(rng.randf_range(-WRAP_SPAN * 0.5, WRAP_SPAN * 0.5), rng.randf_range(-WRAP_SPAN * 0.5, WRAP_SPAN * 0.5)),
			"vel": Vector2(rng.randf_range(-16.0, 16.0), rng.randf_range(-22.0, -8.0)),
			"radius": rng.randf_range(34.0, 68.0),
			"phase": rng.randf_range(0.0, TAU),
			"warm": rng.randf_range(0.0, 1.0),
		})


func _init_leaves() -> void:
	_leaves.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x7EAFA11
	for i in range(LEAF_COUNT):
		var is_petal := (i % 3 == 0)
		var base_col: Color
		if is_petal:
			# Soft pink cherry blossom or starlight gold petal
			base_col = Color(0.96, 0.72, 0.82, 0.72) if (i % 2 == 0) else Color(0.98, 0.88, 0.58, 0.72)
		else:
			# Gentle translucent emerald / willow / amber leaf
			var t := rng.randf()
			base_col = Color(0.26, 0.62, 0.40, 0.68).lerp(Color(0.72, 0.58, 0.24, 0.68), t * 0.65)

		_leaves.append({
			"pos": Vector2(rng.randf_range(-WRAP_SPAN * 0.5, WRAP_SPAN * 0.5), rng.randf_range(-WRAP_SPAN * 0.5, WRAP_SPAN * 0.5)),
			"vel_y": rng.randf_range(28.0, 48.0),
			"drift_amp": rng.randf_range(16.0, 32.0),
			"drift_spd": rng.randf_range(0.8, 1.8),
			"rot": rng.randf_range(0.0, TAU),
			"rot_spd": rng.randf_range(-1.4, 1.4),
			"flip_phase": rng.randf_range(0.0, TAU),
			"flip_spd": rng.randf_range(1.8, 3.4),
			"size": rng.randf_range(6.5, 11.5),
			"is_petal": is_petal,
			"color": base_col,
		})


func _init_butterflies() -> void:
	_butterflies.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0x8077EF1
	var hues: Array[Color] = [
		Color(0.40, 0.95, 0.88), # Bioluminescent Cyan
		Color(0.85, 0.72, 1.00), # Ethereal Lavender
		Color(1.00, 0.88, 0.45), # Solar Gold
		Color(0.50, 0.98, 0.65), # Forest Emerald
		Color(0.98, 0.65, 0.82), # Blossom Rose
	]
	for i in range(BUTTERFLY_COUNT):
		_butterflies.append({
			"pos": Vector2(rng.randf_range(-400.0, 400.0), rng.randf_range(-600.0, 600.0)),
			"vel": Vector2.from_angle(rng.randf_range(0.0, TAU)) * rng.randf_range(32.0, 52.0),
			"target_angle": rng.randf_range(0.0, TAU),
			"turn_timer": rng.randf_range(1.0, 3.0),
			"wing_phase": rng.randf_range(0.0, TAU),
			"size": rng.randf_range(8.0, 12.0),
			"hue": hues[i % hues.size()],
		})


func _init_stardust() -> void:
	_stardust.clear()
	var rng := RandomNumberGenerator.new()
	rng.seed = 0xD057BEAD
	for i in range(STARDUST_COUNT):
		_stardust.append({
			"pos": Vector2(rng.randf_range(-600.0, 600.0), rng.randf_range(-900.0, 900.0)),
			"phase": rng.randf_range(0.0, TAU),
			"blink_spd": rng.randf_range(2.5, 5.5),
			"size": rng.randf_range(1.3, 2.2),
			"drift_x": rng.randf_range(-8.0, 8.0),
			"drift_y": rng.randf_range(-12.0, -3.0),
			"warm": rng.randf() < 0.3,
		})


func set_camera_center(world_pos: Vector2) -> void:
	_camera_pos = world_pos


func set_growth(g: float) -> void:
	_growth = clampf(g, 0.0, 1.0)


func _process(delta: float) -> void:
	_time += delta
	var half_span := WRAP_SPAN * 0.5

	# Update large bokeh motes
	for m: Dictionary in _motes:
		var p: Vector2 = m["pos"]
		var v: Vector2 = m["vel"]
		p += v * delta
		m["pos"] = p

	# Update falling leaves / petals
	for lf: Dictionary in _leaves:
		var lp: Vector2 = lf["pos"]
		var vy: float = float(lf["vel_y"])
		var d_spd: float = float(lf["drift_spd"])
		var d_amp: float = float(lf["drift_amp"])
		lp.y += vy * delta
		lp.x += sin(_time * d_spd + float(lf["flip_phase"])) * d_amp * delta
		lf["rot"] = float(lf["rot"]) + float(lf["rot_spd"]) * delta
		lf["flip_phase"] = float(lf["flip_phase"]) + float(lf["flip_spd"]) * delta
		# Wrap around screen bounds
		if lp.y > half_span:
			lp.y = -half_span
			lp.x = randf_range(-half_span, half_span)
		lf["pos"] = lp

	# Update harmless wandering butterflies with reactive evasion
	for b: Dictionary in _butterflies:
		var bp: Vector2 = b["pos"]
		var b_turn: float = float(b["turn_timer"]) - delta
		var dist_to_player := bp.length()
		var is_startled := dist_to_player < 175.0
		var flap_speed := 14.0

		if is_startled:
			# Player proximity reaction: turn directly away from player center with a burst of speed
			b["target_angle"] = bp.angle() + randf_range(-0.35, 0.35)
			b_turn = randf_range(1.2, 2.0)
			flap_speed = 34.0
		elif b_turn <= 0.0:
			b["target_angle"] = randf_range(0.0, TAU)
			b_turn = randf_range(1.5, 3.5)
		b["turn_timer"] = b_turn

		var cruise_spd := 92.0 if is_startled else 42.0
		var steer_k := 4.5 if is_startled else 2.0
		var cur_vel: Vector2 = b["vel"]
		var target_vel := Vector2.from_angle(float(b["target_angle"])) * cruise_spd
		# Steer smoothly toward target angle
		cur_vel = cur_vel.lerp(target_vel, steer_k * delta)
		bp += cur_vel * delta

		# Keep butterflies meandering around the camera field
		if bp.length() > 580.0:
			b["target_angle"] = (-bp).angle() + randf_range(-0.4, 0.4)

		b["vel"] = cur_vel
		b["pos"] = bp
		b["wing_phase"] = float(b["wing_phase"]) + flap_speed * delta

	# Update twinkling star dust
	for sd: Dictionary in _stardust:
		var sp: Vector2 = sd["pos"]
		sp.x += float(sd["drift_x"]) * delta
		sp.y += float(sd["drift_y"]) * delta
		if sp.y < -950.0:
			sp.y = 950.0
			sp.x = randf_range(-600.0, 600.0)
		if sp.x < -650.0 or sp.x > 650.0:
			sp.x = -sp.x * 0.9
		sd["pos"] = sp

	if _painter != null:
		_painter.queue_redraw()


func _draw_foreground() -> void:
	if _painter == null:
		return
	var vp := _painter.size
	if vp.x <= 10.0 or vp.y <= 10.0:
		vp = Vector2(720.0, 1280.0)

	var half_span := WRAP_SPAN * 0.5
	var is_low_fx := (str(SaveData.get_setting("fx_quality", "high")) == "low")

	# 1. Silhouetted overhanging canopy bough clusters in the four corners
	_draw_canopy_corners(vp)

	# 2. Gentle drifting leaves & petals
	if not is_low_fx:
		_draw_falling_leaves(vp, half_span)

	# 3. Harmless bioluminescent butterflies fluttering above the arena
	if not is_low_fx:
		_draw_butterflies(vp)

	# 4. Large out-of-focus foreground bokeh motes drifting between camera and ground
	if not is_low_fx:
		_draw_bokeh_motes(vp, half_span)

	# 5. Twinkling magical star dust motes
	if not is_low_fx:
		_draw_star_dust(vp)


func _draw_canopy_corners(vp: Vector2) -> void:
	var par := Vector2(
		sin(_camera_pos.x * 0.0022) * 22.0 + sin(_time * 0.55) * 7.0,
		cos(_camera_pos.y * 0.0022) * 22.0 + cos(_time * 0.43) * 6.0
	)
	var shadow_col := Color(0.012, 0.035, 0.038, 0.78)
	var rim_col := Color(0.12, 0.36, 0.30, 0.22).lerp(Color(0.42, 0.58, 0.26, 0.26), _growth)

	# Corner origins and foliage directions
	var corners: Array[Vector2] = [
		Vector2(-14.0, -12.0) + par * 0.8,
		Vector2(vp.x + 14.0, -12.0) + Vector2(-par.x * 0.7, par.y * 0.8),
		Vector2(-16.0, vp.y + 14.0) + Vector2(par.x * 0.8, -par.y * 0.7),
		Vector2(vp.x + 16.0, vp.y + 14.0) - par * 0.8,
	]
	var corner_angles: Array[float] = [0.82, 2.32, -0.82, -2.32]

	for ci in range(corners.size()):
		var c := corners[ci]
		var sway := Vector2(sin(_time * 0.65 + float(ci) * 1.6) * 6.0, cos(_time * 0.55 + float(ci) * 1.2) * 5.0)
		var center_pt := c + sway

		# Layer A: Soft out-of-focus background bough volume
		_painter.draw_circle(center_pt, 92.0, rim_col)
		_painter.draw_circle(center_pt + sway * 0.4, 76.0, shadow_col)

		# Layer B: Painted foliage silhouettes hanging inwards from the screen edges
		var tex := _tex_broadleaf if (ci % 2 == 0) else _tex_fern
		if tex != null:
			var ang := corner_angles[ci] + sin(_time * 0.5 + float(ci)) * 0.06
			var sz := 210.0
			_painter.draw_set_transform(center_pt, ang, Vector2.ONE)
			# Shadow silhouette
			_painter.draw_texture_rect(tex, Rect2(Vector2(-sz * 0.45, -sz * 0.2), Vector2(sz, sz)), false, shadow_col)
			# Soft top rim highlight
			_painter.draw_texture_rect(tex, Rect2(Vector2(-sz * 0.45 + 2.0, -sz * 0.2 + 2.0), Vector2(sz, sz)), false, rim_col)
			_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)
		else:
			# Fallback procedural leaf bough
			var dir := Vector2.from_angle(corner_angles[ci])
			_painter.draw_circle(center_pt + dir * 48.0, 52.0, shadow_col)
			_painter.draw_circle(center_pt + dir * 72.0, 38.0, shadow_col)


func _draw_falling_leaves(vp: Vector2, half_span: float) -> void:
	for lf: Dictionary in _leaves:
		var base_p: Vector2 = lf["pos"]
		var rel := base_p - _camera_pos * PARALLAX_LEAF
		var wx := fposmod(rel.x + half_span, WRAP_SPAN) - half_span
		var wy := fposmod(rel.y + half_span, WRAP_SPAN) - half_span
		var screen_p := vp * 0.5 + Vector2(wx, wy)

		var sz: float = float(lf["size"])
		if screen_p.x < -30.0 or screen_p.x > vp.x + 30.0 or screen_p.y < -30.0 or screen_p.y > vp.y + 30.0:
			continue

		var flip := cos(float(lf["flip_phase"]))
		var rot: float = float(lf["rot"])
		var col: Color = lf["color"]
		var is_petal: bool = bool(lf["is_petal"])

		# 3D tumbling leaf transform (horizontal scale flutters through zero as it turns in the wind)
		_painter.draw_set_transform(screen_p, rot, Vector2(flip, 1.0))

		if is_petal:
			# Delicate curved blossom petal
			var petal_pts := PackedVector2Array([
				Vector2(0.0, -sz * 1.1),
				Vector2(sz * 0.65, -sz * 0.3),
				Vector2(sz * 0.45, sz * 0.75),
				Vector2(0.0, sz * 1.0),
				Vector2(-sz * 0.45, sz * 0.75),
				Vector2(-sz * 0.65, -sz * 0.3),
			])
			_painter.draw_colored_polygon(petal_pts, col)
			# Translucent soft white inner sheen
			_painter.draw_circle(Vector2(0.0, -sz * 0.2), sz * 0.35, Color(1.0, 1.0, 1.0, col.a * 0.45))
		else:
			# Slender willow / forest leaf with central vein
			var leaf_pts := PackedVector2Array([
				Vector2(0.0, -sz * 1.3),
				Vector2(sz * 0.48, -sz * 0.2),
				Vector2(sz * 0.38, sz * 0.75),
				Vector2(0.0, sz * 1.2),
				Vector2(-sz * 0.38, sz * 0.75),
				Vector2(-sz * 0.48, -sz * 0.2),
			])
			_painter.draw_colored_polygon(leaf_pts, col)
			# Leaf vein
			var vein_col := col.darkened(0.25)
			_painter.draw_line(Vector2(0.0, -sz * 1.1), Vector2(0.0, sz * 1.3), vein_col, 1.1)

		_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_butterflies(vp: Vector2) -> void:
	for b: Dictionary in _butterflies:
		var bp: Vector2 = b["pos"]
		# Follow camera with gentle 0.95 parallax
		var screen_p := vp * 0.5 + (bp - _camera_pos * 0.12)
		if screen_p.x < -40.0 or screen_p.x > vp.x + 40.0 or screen_p.y < -40.0 or screen_p.y > vp.y + 40.0:
			continue

		var vel: Vector2 = b["vel"]
		var flight_ang := vel.angle() + PI * 0.5
		var flap := sin(float(b["wing_phase"]))
		var sz: float = float(b["size"])
		var hue: Color = b["hue"]
		var wing_span := maxf(0.12, absf(flap))

		# Luminous bioluminescent aura around the fluttering creature
		var glow_extent := Vector2.ONE * sz * 2.8
		_painter.draw_texture_rect(SOFT_GLOW, Rect2(screen_p - glow_extent, glow_extent * 2.0), false,
			Color(hue.r, hue.g, hue.b, 0.22))

		_painter.draw_set_transform(screen_p, flight_ang, Vector2(wing_span, 1.0))

		# Forewings (upper pair)
		var left_forewing := PackedVector2Array([
			Vector2(-0.8, -sz * 0.2),
			Vector2(-sz * 1.35, -sz * 1.25),
			Vector2(-sz * 1.55, -sz * 0.35),
			Vector2(-0.8, sz * 0.35)
		])
		var right_forewing := PackedVector2Array([
			Vector2(0.8, -sz * 0.2),
			Vector2(sz * 1.35, -sz * 1.25),
			Vector2(sz * 1.55, -sz * 0.35),
			Vector2(0.8, sz * 0.35)
		])
		_painter.draw_colored_polygon(left_forewing, Color(hue.r, hue.g, hue.b, 0.85))
		_painter.draw_colored_polygon(right_forewing, Color(hue.r, hue.g, hue.b, 0.85))

		# Hindwings (lower pair)
		var left_hindwing := PackedVector2Array([
			Vector2(-0.5, sz * 0.25),
			Vector2(-sz * 1.15, sz * 0.45),
			Vector2(-sz * 0.75, sz * 1.25),
			Vector2(-0.5, sz * 0.85)
		])
		var right_hindwing := PackedVector2Array([
			Vector2(0.5, sz * 0.25),
			Vector2(sz * 1.15, sz * 0.45),
			Vector2(sz * 0.75, sz * 1.25),
			Vector2(0.5, sz * 0.85)
		])
		var hind_col := Color(hue.r, hue.g, hue.b, 0.72).lerp(Color.WHITE, 0.25)
		_painter.draw_colored_polygon(left_hindwing, hind_col)
		_painter.draw_colored_polygon(right_hindwing, hind_col)

		# Luminescent core spot on wings
		_painter.draw_circle(Vector2(-sz * 0.75, -sz * 0.45), sz * 0.28, Color(1.0, 1.0, 0.94, 0.75))
		_painter.draw_circle(Vector2(sz * 0.75, -sz * 0.45), sz * 0.28, Color(1.0, 1.0, 0.94, 0.75))

		# Body & antennae
		_painter.draw_line(Vector2(0.0, -sz * 0.75), Vector2(0.0, sz * 0.95), Color(0.12, 0.16, 0.18, 0.95), 1.8)
		_painter.draw_line(Vector2(0.0, -sz * 0.75), Vector2(-sz * 0.45, -sz * 1.35), Color(hue.r, hue.g, hue.b, 0.8), 1.1)
		_painter.draw_line(Vector2(0.0, -sz * 0.75), Vector2(sz * 0.45, -sz * 1.35), Color(hue.r, hue.g, hue.b, 0.8), 1.1)

		_painter.draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)


func _draw_bokeh_motes(vp: Vector2, half_span: float) -> void:
	var cool_mote := Color(0.45, 0.98, 0.86)
	var warm_mote := Color(1.0, 0.88, 0.52)
	for m: Dictionary in _motes:
		var base_p: Vector2 = m["pos"]
		var rel := base_p - _camera_pos * PARALLAX_MOTE
		var wx := fposmod(rel.x + half_span, WRAP_SPAN) - half_span
		var wy := fposmod(rel.y + half_span, WRAP_SPAN) - half_span
		var screen_p := vp * 0.5 + Vector2(wx, wy)
		var r: float = float(m["radius"])
		if screen_p.x < -r * 1.5 or screen_p.x > vp.x + r * 1.5 or screen_p.y < -r * 1.5 or screen_p.y > vp.y + r * 1.5:
			continue
		var pulse := 0.55 + 0.45 * sin(_time * 1.15 + float(m["phase"]))
		var mcol := cool_mote.lerp(warm_mote, clampf(float(m["warm"]) * 0.45 + _growth * 0.55, 0.0, 1.0))
		var a := 0.032 * pulse
		var extent := Vector2.ONE * r
		_painter.draw_texture_rect(SOFT_GLOW, Rect2(screen_p - extent, extent * 2.0), false,
			Color(mcol.r, mcol.g, mcol.b, a * 1.6))


func _draw_star_dust(vp: Vector2) -> void:
	for sd: Dictionary in _stardust:
		var sp: Vector2 = sd["pos"]
		var screen_p := vp * 0.5 + sp
		if screen_p.x < -5.0 or screen_p.x > vp.x + 5.0 or screen_p.y < -5.0 or screen_p.y > vp.y + 5.0:
			continue
		var blink := sin(_time * float(sd["blink_spd"]) + float(sd["phase"]))
		var a := smoothstep(0.3, 1.0, blink) * 0.65
		if a <= 0.01:
			continue
		var sz: float = float(sd["size"])
		var col: Color
		if bool(sd["warm"]):
			col = Color(1.0, 0.92, 0.65, a)
		else:
			col = Color(0.75, 0.96, 1.0, a)
		_painter.draw_circle(screen_p, sz * 2.8, Color(col.r, col.g, col.b, a * 0.18))
		_painter.draw_circle(screen_p, sz, col)
