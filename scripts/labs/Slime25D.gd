class_name Slime25D
extends Node2D
## 2.5D hero: a painted jelly dome (resources/art/2_5d/slime) that *displays* the
## real PlayerSlime. Position, radius, velocity and mass are read, never written,
## so physics, growth formulas and mutations stay in the normal 2D code. The
## node origin is the dome's base line, which is what the glade y-sorts by.
##
## Motion is procedural on one painted body: breathing, speed squash/stretch,
## a gulp pulse with a squashed pose, blinking, a pulsing core glow and a soft
## contact shadow.

const DIR := "res://resources/art/2_5d/slime/"
const SOFT_GLOW: Texture2D = preload("res://resources/effects/soft_glow.tres")
const DOME_WIDTH_PER_RADIUS := 2.5   ## painted dome width / gameplay radius
const BASE_DROP := 0.62               ## base line below the physics centre, in radii
const CORE := Color(0.45, 0.95, 1.0)
const BASE_CYAN := Color("#8ddee4")
const SHADER := "res://shaders/slime25d.gdshader"

var player: PlayerSlime
var textures: Dictionary = {}

var _body: Sprite2D
var _shadow: Sprite2D
var _under: Sprite2D
var _core: Sprite2D
var _k: float = 1.0
var _stretch: Vector2 = Vector2.ONE
var _stretch_v: Vector2 = Vector2.ZERO
var _gulp: float = 0.0
var _blink_t: float = 3.0
var _blink_open: bool = true
var _clock: float = 0.0
var _dir: Vector2 = Vector2.DOWN
var _mat: ShaderMaterial
var _back: SlimeOrnaments
var _front: SlimeOrnaments
var _solid: SlimeOrnaments
var orn: Dictionary = {}
var look: Dictionary = {}
var _geo: Vector4 = Vector4(60.0, 40.0, 1.0, 1.0)  ## dome width, height, squash x/y (world px)
var clock: float:
	get: return _clock


static func available() -> bool:
	return ResourceLoader.exists(DIR + "idle.png")


func setup(p_player: PlayerSlime) -> void:
	player = p_player
	name = "Slime25D"
	for key in ["idle", "blink", "squash", "stretch"]:
		var path: String = DIR + key + ".png"
		if ResourceLoader.exists(path):
			textures[key] = load(path)
	var idle: Texture2D = textures["idle"]
	_k = 1.0 / float(idle.get_width())  # normalised: width 1.0 -> scaled per frame
	_shadow = Sprite2D.new()
	_shadow.texture = SOFT_GLOW
	_shadow.modulate = Color(0.01, 0.03, 0.07, 0.62)
	_shadow.show_behind_parent = true
	add_child(_shadow)
	_under = Sprite2D.new()
	_under.texture = SOFT_GLOW
	var umat := CanvasItemMaterial.new()
	umat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_under.material = umat
	add_child(_under)
	for key in ["crown", "halo", "wing_l", "wing_r", "horn_l", "horn_r", "sigil", "fireflies"]:
		var op := "res://resources/art/2_5d/ornaments/%s.png" % key
		if ResourceLoader.exists(op):
			orn[key] = load(op)
	_back = SlimeOrnaments.new()
	_back.is_back = true
	_back.slime = self
	var add := CanvasItemMaterial.new()
	add.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_back.material = add
	add_child(_back)
	_body = Sprite2D.new()
	_body.texture = idle
	_mat = ShaderMaterial.new()
	_mat.shader = load(SHADER)
	_body.material = _mat
	_body.centered = false
	_body.texture_filter = CanvasItem.TEXTURE_FILTER_LINEAR_WITH_MIPMAPS
	add_child(_body)
	_front = SlimeOrnaments.new()
	_front.slime = self
	var add2 := CanvasItemMaterial.new()
	add2.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_front.material = add2
	add_child(_front)
	_solid = SlimeOrnaments.new()
	_solid.slime = self
	_solid.is_solid = true
	add_child(_solid)
	_core = Sprite2D.new()
	_core.texture = SOFT_GLOW
	var mat := CanvasItemMaterial.new()
	mat.blend_mode = CanvasItemMaterial.BLEND_MODE_ADD
	_core.material = mat
	add_child(_core)
	if player.visual != null:
		player.visual.visible = false
		player.visual.process_mode = Node.PROCESS_MODE_DISABLED


func gulp() -> void:
	_gulp = 1.0


func _process(delta: float) -> void:
	_clock += delta
	var t := EvolutionStages.t_for_mass(player.mass)
	look = EvolutionStages.look_at(t)
	# Early stages keep the concept's cyan; the stage hue takes over as the ladder climbs.
	var hue_w := clampf((t - 1.0) / 6.0, 0.0, 1.0)
	_mat.set_shader_parameter("tint", BASE_CYAN.lerp(look["body_c"] as Color, hue_w))
	_mat.set_shader_parameter("amount", 0.85 * hue_w)
	var r := player.get_radius()
	position = player.global_position + Vector2(0.0, r * BASE_DROP)
	var vel := player.velocity
	var speed01 := clampf(vel.length() / maxf(player.base_move_speed, 1.0), 0.0, 1.0)
	if vel.length() > 6.0:
		_dir = _dir.lerp(vel.normalized(), 1.0 - exp(-12.0 * delta))
	# Spring toward the target squash: wider and lower sideways, a little taller
	# when moving along the view axis.
	var target := Vector2(1.0 + 0.20 * speed01 * absf(_dir.x) + 0.04 * speed01,
			1.0 - 0.12 * speed01 * absf(_dir.x) + 0.10 * speed01 * absf(_dir.y))
	var breath := 1.0 + 0.026 * sin(_clock * 2.1)
	target.y *= breath
	target.x *= 2.0 - breath
	_stretch_v += (target - _stretch) * 160.0 * delta
	_stretch_v *= exp(-11.0 * delta)
	_stretch += _stretch_v * delta
	_gulp = move_toward(_gulp, 0.0, delta * 2.6)
	var pulse := sin(_gulp * PI)  # 0 -> 1 -> 0
	var sx := _stretch.x * (1.0 + 0.10 * pulse)
	var sy := _stretch.y * (1.0 - 0.07 * pulse)

	_blink_t -= delta
	if _blink_t < 0.13:
		_blink_open = false
		if _blink_t < 0.0:
			_blink_open = true
			_blink_t = randf_range(2.6, 5.0)
	var key := "idle"
	if _gulp > 0.55 and textures.has("squash"):
		key = "squash"
	elif not _blink_open and textures.has("blink"):
		key = "blink"
	var tex: Texture2D = textures[key]
	_body.texture = tex
	# Width of the painted dome in world px follows the gameplay radius.
	var world_w := r * DOME_WIDTH_PER_RADIUS
	var idle_w := float(textures["idle"].get_width())
	var s := world_w / idle_w
	_body.scale = Vector2(s * sx, s * sy)
	# Anchor: bottom centre of the frame on the base line.
	_body.position = Vector2(-tex.get_width() * 0.5 * _body.scale.x, -tex.get_height() * _body.scale.y)

	_geo = Vector4(world_w, tex.get_height() * s * sy, sx, sy)
	_back.queue_redraw()
	_front.queue_redraw()
	_solid.queue_redraw()
	var core_a := 0.34 + 0.12 * sin(_clock * 2.6) + 0.5 * pulse
	_core.modulate = ((look["core_c"] as Color).lerp(CORE, 1.0 - clampf(float(look.get("stage", 1)) / 15.0, 0.0, 1.0) * 0.0)) * Color(1, 1, 1, clampf(core_a, 0.0, 0.9))
	_core.scale = Vector2.ONE * world_w * 0.0075 * (1.0 + 0.3 * pulse)
	_core.position = Vector2(0.0, -tex.get_height() * s * sy * 0.28)
	var glow_c := BASE_CYAN.lerp(look["trail_c"] as Color, hue_w)
	_under.modulate = Color(glow_c.r, glow_c.g, glow_c.b, 0.30 + 0.10 * float(look["glow"]) + 0.08 * sin(_clock * 2.6) + 0.3 * pulse)
	_under.scale = Vector2(world_w * 1.35 / 128.0, world_w * 0.52 / 128.0)
	_under.position = Vector2(0.0, -world_w * 0.04)
	_shadow.scale = Vector2(world_w * 0.86 * sx / 128.0, world_w * 0.22 / 128.0)
	_shadow.position = Vector2(world_w * 0.04, -world_w * 0.02)


## Stage ornaments (wings, halo, crown, horns, motes, petals, ground sigil) drawn
## from the same EvolutionStages weights the 2D slime uses, so growth reads the
## same in both looks. Additive, painted-feeling soft shapes; no gameplay input.
class SlimeOrnaments extends Node2D:
	var slime: Slime25D
	var is_back: bool = false
	var is_solid: bool = false

	## Draws a painted ornament centred on `centre` (bottom-anchored when `base`),
	## `width` world px wide, keeping its aspect.
	func _sprite(key: String, centre: Vector2, width: float, tint: Color, rot: float = 0.0, flip: bool = false, base: bool = false) -> void:
		var tex: Texture2D = slime.orn.get(key)
		if tex == null or width < 1.0:
			return
		var k := width / float(tex.get_width())
		var sz := Vector2(width * (-1.0 if flip else 1.0), float(tex.get_height()) * k)
		draw_set_transform(centre, rot, Vector2.ONE)
		var off := Vector2(-sz.x * 0.5, -sz.y if base else -sz.y * 0.5)
		draw_texture_rect(tex, Rect2(off, sz), false, tint)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _draw() -> void:
		if slime == null or slime.look.is_empty():
			return
		if slime.orn.size() >= 8:
			_draw_painted()
			return
		var L: Dictionary = slime.look
		var w := slime._geo.x
		var h := slime._geo.y
		var t := slime.clock
		var rim: Color = L["rim_c"]
		var core: Color = L["core_c"]
		var trail: Color = L["trail_c"]
		if is_back:
			_sigil(float(L["sigil"]), w, trail, t)
			_wings(float(L["wings"]), w, h, rim, t)
			_petals(float(L["petals"]), w, h, trail, t)
		else:
			_halo(float(L["halo"]), w, h, core, t)
			_horns(float(L["horns"]), w, h, rim)
			_crown(float(L["crown"]), w, h, core)
			_motes(float(L["motes"]), w, h, trail, t)

	func _draw_painted() -> void:
		var L: Dictionary = slime.look
		var w := slime._geo.x
		var h := slime._geo.y
		var t := slime.clock
		var trail: Color = L["trail_c"]
		var rim: Color = L["rim_c"]
		var tint_glow := Color(1, 1, 1).lerp(trail, 0.45)
		if is_back:
			var sg := float(L["sigil"])
			if sg > 0.02:
				_sprite("sigil", Vector2(0.0, -w * 0.02), w * 2.1, Color(tint_glow.r, tint_glow.g, tint_glow.b, (0.75 + 0.15 * sin(t * 1.6)) * sg), 0.0)
			var wg := float(L["wings"])
			if wg > 0.02:
				var flap := 0.07 * sin(t * 1.9)
				var ww := w * (0.45 + 0.45 * wg)
				var wc := Color(tint_glow.r, tint_glow.g, tint_glow.b, 0.9 * clampf(wg * 1.3, 0.0, 1.0))
				_sprite("wing_l", Vector2(-w * 0.50 - ww * 0.30, -h * 0.58), ww, wc, -flap)
				_sprite("wing_r", Vector2(w * 0.50 + ww * 0.30, -h * 0.58), ww, wc, flap)
		elif is_solid:
			var hr := float(L["horns"])
			if hr > 0.2:
				var hw := w * (0.10 + 0.09 * hr)
				_sprite("horn_l", Vector2(-w * 0.22, -h * 0.90), hw, Color(1, 1, 1, 1), -0.25, false, true)
				_sprite("horn_r", Vector2(w * 0.22, -h * 0.90), hw, Color(1, 1, 1, 1), 0.25, false, true)
			var cr := float(L["crown"])
			if cr > 0.05:
				_sprite("crown", Vector2(0.0, -h * 0.93), w * (0.20 + 0.20 * cr), Color(1, 1, 1, clampf(cr * 2.0, 0.0, 1.0)), 0.0, false, true)
		else:
			var hl := float(L["halo"])
			if hl > 0.02:
				_sprite("halo", Vector2(0.0, -h - w * 0.16 + 1.6 * sin(t * 1.4)), w * (0.55 + 0.2 * hl), Color(1, 1, 1, 0.95 * hl), 0.0)
			var mt := float(L["motes"])
			_motes(mt, w, h, trail, t)
			if mt > 0.45:
				_sprite("fireflies", Vector2(w * 0.38 + 6.0 * sin(t * 0.9), -h * 0.78 + 4.0 * cos(t * 1.1)), w * 0.55 * mt, Color(1, 1, 1, 0.8), 0.0)

	func _sigil(a: float, w: float, c: Color, t: float) -> void:
		if a < 0.02:
			return
		var rx := w * 0.82
		draw_set_transform(Vector2(0.0, -w * 0.02), 0.0, Vector2(1.0, 0.36))
		draw_arc(Vector2.ZERO, rx, 0.0, TAU, 56, Color(c.r, c.g, c.b, 0.55 * a), 2.2)
		draw_arc(Vector2.ZERO, rx * 0.8, 0.0, TAU, 48, Color(c.r, c.g, c.b, 0.25 * a), 1.4)
		for i in range(8):
			var ang := t * 0.25 + float(i) * TAU / 8.0
			var p0 := Vector2(cos(ang), sin(ang)) * rx * 0.8
			var p1 := Vector2(cos(ang), sin(ang)) * rx
			draw_line(p0, p1, Color(c.r, c.g, c.b, 0.5 * a), 1.8)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _wings(a: float, w: float, h: float, c: Color, t: float) -> void:
		if a < 0.02:
			return
		var flap := 0.10 * sin(t * 1.7)
		for side: float in [-1.0, 1.0]:
			for i in range(4):
				var base := Vector2(side * w * 0.40, -h * 0.55)
				var dir := Vector2(side * cos(0.5 + 0.3 * float(i) + flap), -sin(0.5 + 0.3 * float(i) + flap) * 0.9)
				var len := w * (0.62 - 0.07 * float(i)) * (0.55 + 0.45 * a)
				var side_v := dir.orthogonal() * len * 0.13
				var pts := PackedVector2Array([base, base + dir * len * 0.5 + side_v, base + dir * len, base + dir * len * 0.5 - side_v])
				draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.20 * a))

	func _petals(a: float, w: float, h: float, c: Color, t: float) -> void:
		var n := int(a * 8.0)
		for i in range(n):
			var ang := t * 0.35 + float(i) * TAU / float(maxi(n, 1))
			var p := Vector2(cos(ang) * w * 0.62, -h * 0.30 + sin(ang) * h * 0.22)
			if sin(ang) < 0.0:
				continue  # only the front half; the back half hides behind the body
			var d := Vector2(cos(ang + PI * 0.5), sin(ang + PI * 0.5) * 0.4)
			var pts := PackedVector2Array([p, p + d * w * 0.05 + Vector2(0, -w * 0.035), p + d * w * 0.1, p + d * w * 0.05 + Vector2(0, w * 0.03)])
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.55))

	func _halo(a: float, w: float, h: float, c: Color, t: float) -> void:
		if a < 0.02:
			return
		var centre := Vector2(0.0, -h - w * 0.10 + 1.5 * sin(t * 1.4))
		draw_set_transform(centre, 0.0, Vector2(1.0, 0.30))
		draw_arc(Vector2.ZERO, w * 0.30, 0.0, TAU, 44, Color(c.r, c.g, c.b, 0.22 * a), 7.0)
		draw_arc(Vector2.ZERO, w * 0.30, 0.0, TAU, 44, Color(c.r, c.g, c.b, 0.85 * a), 2.4)
		draw_set_transform(Vector2.ZERO, 0.0, Vector2.ONE)

	func _horns(a: float, w: float, h: float, c: Color) -> void:
		if a < 0.05:
			return
		for side: float in [-1.0, 1.0]:
			var b := Vector2(side * w * 0.20, -h * 0.90)
			var tip := b + Vector2(side * w * 0.10, -w * 0.18 * a)
			var pts := PackedVector2Array([b + Vector2(-w * 0.03, 0), tip, b + Vector2(w * 0.03, 0)])
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.55))

	func _crown(a: float, w: float, h: float, c: Color) -> void:
		if a < 0.05:
			return
		var n := 3 + int(a * 2.0)
		for i in range(n):
			var u := (float(i) / float(n - 1)) * 2.0 - 1.0 if n > 1 else 0.0
			var b := Vector2(u * w * 0.20, -h * (0.97 - 0.10 * u * u))
			var sz := w * 0.045 * (0.6 + a * 0.5) * (1.0 - 0.3 * absf(u))
			var pts := PackedVector2Array([b + Vector2(-sz, 0), b + Vector2(0, -sz * 2.2), b + Vector2(sz, 0)])
			draw_colored_polygon(pts, Color(c.r, c.g, c.b, 0.9))
			draw_circle(b + Vector2(0, -sz * 2.2), sz * 0.45, Color(1, 1, 1, 0.9))

	func _motes(a: float, w: float, h: float, c: Color, t: float) -> void:
		var n := int(2.0 + 10.0 * a) if a > 0.01 else 0
		for i in range(n):
			var ang := t * (0.5 + 0.05 * float(i % 3)) + float(i) * 2.399
			var rad := 0.62 + 0.18 * sin(float(i) * 1.7)
			var p := Vector2(cos(ang) * w * rad, -h * 0.55 + sin(ang) * h * 0.55 * rad - 4.0 * sin(t * 1.3 + float(i)))
			var tw := 0.55 + 0.45 * sin(t * 2.2 + float(i) * 1.9)
			var rr := w * (0.014 + 0.006 * float(i % 3))
			draw_circle(p, rr * 2.6, Color(c.r, c.g, c.b, 0.18 * tw))
			draw_circle(p, rr, Color(1, 1, 1, 0.8 * tw))
