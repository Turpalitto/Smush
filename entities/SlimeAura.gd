class_name SlimeAura
extends Node2D
## Draws the growth regalia around the slime: the ground sigil, petals, wings,
## halo, crown, antlers and orbiting motes.
##
## Two instances exist, one behind the body and one in front of it, because the
## sigil and the wings must sit under the jelly while the crown must sit on top.
## Everything is drawn procedurally from the stage look in EvolutionStages, so the
## whole ladder costs no textures and interpolates smoothly between stages.
##
## Why not painted sprites: the body is a wobbling shader blob whose silhouette
## changes every frame. A pasted sprite would either float rigidly against that
## wobble or need fifteen separate animations; rings and polygons inherit the
## blob's motion for free.
##
## Shape language: every ornament is a tapered stroke or a filled blade with a
## bright edge, never a one-pixel line. The first version drew the crown and the
## antlers with draw_line() at 1-2.6 px and at 720x1280 on a phone they read as
## scratches rather than as regalia, so the primitives below are polygons with a
## width that falls off along the stroke.

var front: bool = false

var _look: Dictionary = {}
var _radius: float = 25.0
var _time: float = 0.0
var _alpha: float = 1.0
var _mote_phase: Array[float] = []
## Regalia accent. Derived from the stage rim, but forced to keep a hue: the last
## two stages have a near-white rim, and white ornaments on a white body vanish.
var _acc: Color = Color.WHITE


func _ready() -> void:
	# Ornaments are decoration: they must never eat a touch or a physics query.
	z_index = 1 if front else -1


func set_look(look: Dictionary, radius: float, time: float, alpha: float) -> void:
	_look = look
	_radius = radius
	_time = time
	_alpha = alpha
	queue_redraw()


func _draw() -> void:
	if _look.is_empty() or _alpha <= 0.01:
		return
	var rim: Color = _look["rim_c"]
	_acc = rim
	_acc.s = clampf(maxf(rim.s, 0.40), 0.0, 1.0)
	_acc.v = minf(rim.v, 0.93)
	if front:
		_draw_crown()
		_draw_antlers()
		_draw_halo()
		_draw_motes()
	else:
		_draw_ground_pool()
		_draw_sigil()
		_draw_wings()
		_draw_petals()


# --- primitives ----------------------------------------------------------

func _quad_pts(a: Vector2, c: Vector2, b: Vector2, steps: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var u := 1.0 - t
		pts.append(a * (u * u) + c * (2.0 * u * t) + b * (t * t))
	return pts


func _taper(a: Vector2, b: Vector2, w0: float, w1: float, col: Color) -> void:
	## A stroke that loses width along its length. Two triangles would leave a
	## visible seam at the joint, so this is one quad with rounded ends.
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([
		a + n * w0 * 0.5, b + n * w1 * 0.5, b - n * w1 * 0.5, a - n * w0 * 0.5,
	]), col)
	draw_circle(a, w0 * 0.5, col)
	draw_circle(b, w1 * 0.5, col)


func _blade(root: Vector2, tip: Vector2, width: float, curl: float, fill: Color, edge: Color) -> void:
	## A leaf-shaped fill between two quadratic curves, with a bright rim. Used for
	## feathers and petals: a plain triangle reads as a sticker, a curved blade with
	## a thin bright edge reads as something grown.
	var d := (tip - root).normalized()
	var n := d.orthogonal()
	var mid := (root + tip) * 0.5 + n * curl
	var up := _quad_pts(root, mid + n * width, tip)
	var dn := _quad_pts(tip, mid - n * width * 0.62, root)
	var poly := PackedVector2Array(up)
	for i in range(dn.size()):
		poly.append(dn[i])
	draw_colored_polygon(poly, fill)
	var rim := PackedVector2Array(up)
	rim.append(tip)
	draw_polyline(rim, edge, 1.3)
	# One vein from root to tip: the cheapest thing that makes a blade look grown
	# rather than printed.
	draw_line(root, tip, edge, 1.0)


# --- back layer ----------------------------------------------------------

func _draw_ground_pool() -> void:
	## Light the slime casts on the floor. Deliberately under everything else and
	## always on: even at stage 1 the slime is faintly luminous, and by stage 15 this
	## is what makes the grove look lit from the character instead of from nowhere.
	var g := float(_look.get("glow", 0.0))
	var core: Color = _look["core_c"]
	var rim: Color = _acc
	var breathe := 0.9 + 0.1 * sin(_time * 1.3)
	var r := _radius * (2.4 + 1.5 * g) * breathe
	for i in range(3):
		var k := 1.0 - float(i) * 0.24
		draw_circle(Vector2(0.0, _radius * 0.12), r * k,
			Color(core.r, core.g, core.b, (0.020 + 0.016 * g) * _alpha))
	draw_circle(Vector2(0.0, _radius * 0.10), _radius * 0.95,
		Color(rim.r, rim.g, rim.b, 0.05 * g * _alpha))


func _draw_sigil() -> void:
	var s := float(_look.get("sigil", 0.0))
	if s <= 0.02:
		return
	var rim: Color = _acc
	var core: Color = _look["core_c"]
	var r := _radius * (1.85 + 0.12 * sin(_time * 0.7))
	for i in range(4):
		var k := 1.0 - float(i) * 0.18
		draw_circle(Vector2.ZERO, r * k, Color(rim.r, rim.g, rim.b, 0.035 * s * _alpha))
	# Two counter-rotating rings of rune ticks, the inner one carrying diamonds so
	# the sigil has a readable "inscription" at a glance instead of an even comb.
	for ring in range(2):
		var rr := r * (1.0 if ring == 0 else 0.82)
		var dir := 1.0 if ring == 0 else -1.0
		draw_arc(Vector2.ZERO, rr, 0.0, TAU, 56, Color(rim.r, rim.g, rim.b, 0.22 * s * _alpha), 1.8)
		var ticks := 12 if ring == 0 else 8
		for i in range(ticks):
			var a := (TAU / float(ticks)) * float(i) + _time * 0.35 * dir
			var d := Vector2.from_angle(a)
			if ring == 0:
				var p0 := d * rr
				var p1 := d * (rr + r * 0.075)
				_taper(p0, p1, 3.2, 1.6, Color(core.r, core.g, core.b, 0.34 * s * _alpha))
			else:
				# Diamonds, rotated with the ring: the "letters" of the sigil.
				var c := d * (rr - r * 0.055)
				var t2 := d.orthogonal() * r * 0.035
				var rr2 := d * r * 0.035
				draw_colored_polygon(PackedVector2Array([c + rr2, c + t2, c - rr2, c - t2]),
					Color(rim.r, rim.g, rim.b, 0.40 * s * _alpha))


func _draw_wings() -> void:
	var w := float(_look.get("wings", 0.0))
	if w <= 0.05:
		return
	var rim: Color = _acc
	var core: Color = _look["core_c"]
	var flap := 0.88 + 0.12 * sin(_time * 2.1)
	# Three feathers per side, each shorter and lower than the last, so the wing has
	# a leading edge instead of a single triangular sheet.
	for side: float in [-1.0, 1.0]:
		for lobe in range(3):
			var t := float(lobe)
			var root := Vector2(side * _radius * 0.42, -_radius * 0.34 + t * _radius * 0.26)
			var spread := _radius * (1.48 + 0.46 * w) * flap * (1.0 - t * 0.16)
			var tip := root + Vector2(side * spread, -_radius * (0.42 - t * 0.30))
			_blade(root, tip, _radius * (0.20 + 0.10 * w),
				side * _radius * (0.22 - t * 0.05),
				Color(rim.r, rim.g, rim.b, (0.21 - t * 0.04) * w * _alpha),
				Color(core.r, core.g, core.b, (0.48 - t * 0.10) * w * _alpha))


func _draw_petals() -> void:
	var p := float(_look.get("petals", 0.0))
	if p <= 0.05:
		return
	var core: Color = _look["core_c"]
	var rim: Color = _acc
	var count := 6
	for i in range(count):
		var a := (TAU / float(count)) * float(i) - PI * 0.5 + sin(_time * 0.6) * 0.08
		var dir := Vector2.from_angle(a)
		var base := dir * (_radius * 0.88)
		var tip := dir * (_radius * (1.30 + 0.14 * p)) + dir.orthogonal() * sin(_time * 0.9 + float(i)) * _radius * 0.06
		_blade(base, tip, _radius * 0.16 * p, _radius * 0.10 * p,
			Color(core.r, core.g, core.b, 0.26 * p * _alpha),
			Color(rim.r, rim.g, rim.b, 0.40 * p * _alpha))


# --- front layer ---------------------------------------------------------

func _draw_crown() -> void:
	var c := float(_look.get("crown", 0.0))
	if c <= 0.05:
		return
	var core: Color = _look["core_c"]
	var rim: Color = _acc
	var band_r := _radius * 0.99
	var span := 1.95
	# The band follows the head instead of cutting across it: an arc, not a line.
	var band := PackedVector2Array()
	for i in range(25):
		var a := -PI * 0.5 + (float(i) / 24.0 - 0.5) * span
		band.append(Vector2.from_angle(a) * band_r)
	var band_col := rim
	band_col.v = minf(rim.v, 0.72)
	draw_polyline(band, Color(band_col.r, band_col.g, band_col.b, 0.80 * c * _alpha), 3.0)
	draw_polyline(band, Color(core.r, core.g, core.b, 0.55 * c * _alpha), 1.4)

	var count := 3 + int(round(c * 4.0))
	for i in range(count):
		var f := float(i) / float(maxi(1, count - 1))
		var a := -PI * 0.5 + (f - 0.5) * span * 0.86
		var dir := Vector2.from_angle(a)
		# The middle point is the tallest, like a real crown.
		var tall := 1.0 - absf(f - 0.5) * 1.1
		var base := dir * band_r
		var tip := dir * (band_r + _radius * (0.20 + 0.34 * c) * tall)
		_taper(base, tip, _radius * 0.15, _radius * 0.03,
			Color(core.r, core.g, core.b, 0.66 * c * _alpha))
		draw_circle(tip, _radius * 0.045, Color(1.0, 1.0, 1.0, 0.55 * c * _alpha))
		# A gem at the foot of each point.
		draw_circle(base, _radius * 0.055,
			Color(rim.r, rim.g, rim.b, 0.65 * c * _alpha))
	# The centre gem: the one place the stage colour is allowed to be pure.
	draw_circle(Vector2(0.0, -band_r), _radius * 0.11 * c,
		Color(rim.r, rim.g, rim.b, 0.80 * c * _alpha))
	draw_circle(Vector2(0.0, -band_r), _radius * 0.055 * c,
		Color(1.0, 1.0, 1.0, 0.70 * c * _alpha))


func _draw_antlers() -> void:
	var h := float(_look.get("horns", 0.0))
	if h <= 0.05:
		return
	var rim: Color = _acc
	var core: Color = _look["core_c"]
	for side: float in [-1.0, 1.0]:
		var root := Vector2(side * _radius * 0.46, -_radius * 0.80)
		var mid := root + Vector2(side * _radius * 0.26, -_radius * (0.52 + 0.22 * h))
		var tip := mid + Vector2(side * _radius * 0.30, -_radius * (0.40 + 0.28 * h))
		_taper(root, mid, _radius * 0.13, _radius * 0.09, Color(core.r, core.g, core.b, 0.62 * h * _alpha))
		_taper(mid, tip, _radius * 0.09, _radius * 0.03, Color(core.r, core.g, core.b, 0.55 * h * _alpha))
		# Two side prongs, the thing that makes an antler read as an antler.
		var prong := mid + Vector2(side * _radius * 0.36, -_radius * 0.04)
		_taper(mid, prong, _radius * 0.07, _radius * 0.02, Color(rim.r, rim.g, rim.b, 0.46 * h * _alpha))
		var prong2 := mid + Vector2(-side * _radius * 0.14, -_radius * 0.34)
		_taper(mid, prong2, _radius * 0.06, _radius * 0.02, Color(rim.r, rim.g, rim.b, 0.42 * h * _alpha))
		draw_circle(tip, _radius * 0.075, Color(rim.r, rim.g, rim.b, 0.35 * h * _alpha))
		draw_circle(tip, _radius * 0.038, Color(1.0, 1.0, 1.0, 0.70 * h * _alpha))


func _draw_halo() -> void:
	var ha := float(_look.get("halo", 0.0))
	if ha <= 0.05:
		return
	var rim: Color = _acc
	var core: Color = _look["core_c"]
	var ry := _radius * 0.30
	var rx := _radius * (1.05 + 0.15 * ha)
	var centre := Vector2(0.0, -_radius * (1.12 + 0.10 * ha))
	# A soft disc behind the ring so the halo glows instead of being a wire loop.
	for i in range(3):
		var k := 1.0 + float(i) * 0.10
		draw_circle(centre, _radius * (0.72 + 0.10 * ha) * k,
			Color(core.r, core.g, core.b, 0.012 * ha * _alpha))
	var pts := PackedVector2Array()
	for i in range(41):
		var a := (TAU / 40.0) * float(i)
		pts.append(centre + Vector2(cos(a) * rx, sin(a) * ry))
	draw_polyline(pts, Color(core.r, core.g, core.b, 0.52 * ha * _alpha), 2.4)
	draw_polyline(pts, Color(1.0, 1.0, 1.0, 0.26 * ha * _alpha), 1.0)
	var pts2 := PackedVector2Array()
	for i in range(41):
		var a := (TAU / 40.0) * float(i)
		pts2.append(centre + Vector2(cos(a) * rx * 0.84, sin(a) * ry * 0.84))
	draw_polyline(pts2, Color(rim.r, rim.g, rim.b, 0.26 * ha * _alpha), 1.2)


func _draw_motes() -> void:
	var m := float(_look.get("motes", 0.0))
	if m <= 0.05:
		return
	var core: Color = _look["core_c"]
	var rim: Color = _acc
	var count := 2 + int(round(m * 7.0))
	if _mote_phase.size() < count:
		_mote_phase.resize(count)
		for i in range(count):
			_mote_phase[i] = randf() * TAU
	for i in range(count):
		var a := _mote_phase[i] + _time * (0.55 + 0.10 * float(i % 3))
		var orbit := _radius * (1.25 + 0.18 * sin(_time * 1.3 + float(i)))
		var p := Vector2(cos(a) * orbit, sin(a) * orbit * 0.72) + Vector2(0.0, -_radius * 0.25)
		var tw := 0.55 + 0.45 * sin(_time * 3.4 + float(i) * 1.7)
		var rad := _radius * 0.055 * (0.7 + 0.5 * tw)
		draw_circle(p, rad * 2.6, Color(rim.r, rim.g, rim.b, 0.10 * m * _alpha * tw))
		draw_circle(p, rad, Color(core.r, core.g, core.b, 0.85 * m * _alpha * tw))
