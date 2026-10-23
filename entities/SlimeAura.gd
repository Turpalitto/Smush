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
## Shape language: every ornament is a *filled form with a dark contour, a body
## colour and a lit highlight*, never a one-pixel line and never a flat stroke.
## Two earlier versions failed on real captures: the first drew 1-2.6 px
## draw_line() strokes, the second drew tapered strokes but in the same hue as the
## body. Both read as white wire — at stages 6-8 the halo plus the antlers looked
## like a spider, and at stages 13-15 the pale gold body swallowed the pale gold
## crown entirely. The rule that came out of those captures: an ornament needs a
## contour darker than the body *and* a highlight lighter than it, or it is
## invisible at phone size no matter how correct its geometry is.

var front: bool = false

var _look: Dictionary = {}
var _radius: float = 25.0
var _time: float = 0.0
var _alpha: float = 1.0
var _mote_phase: Array[float] = []
## Regalia accent. Derived from the stage rim, but forced to keep a hue: the last
## two stages have a near-white rim, and white ornaments on a white body vanish.
var _acc: Color = Color.WHITE
## Contour: the same hue driven dark. This is what gives every form a silhouette.
var _edge: Color = Color.BLACK
## Highlight: the same hue driven light. Only used on small specular accents.
var _lit: Color = Color.WHITE
## Emissive accent: the same hue driven pale and low-saturation, for the things that
## are made of light rather than metal (halo, wings, petals, motes). Without this the
## contrast rule below turned the halo dark magenta on stages 9-12: a crown wants to
## be darker than a pale body, a halo never does.
var _glow: Color = Color.WHITE
## Fill for the large shapes (wings, petals). Contrasts with the BODY: pale on a
## dark body, a deep shade of the same hue on a pale one. `_glow` cannot do this
## job because it is deliberately near-white, which vanishes on the cream stages.
var _veil: Color = Color.WHITE
## 0 on a dark body, 1 on the cream stages. The large shapes read as translucent
## light on a dark body and as near-solid dark silhouettes on a light one, because
## a 54%-opaque mid-tone over a mid-tone world measured as "no wings at all".
var _darken: float = 0.0
## Companion stars earned by growing past the top of the ladder. They are the only
## regalia that is not driven by the stage look, because they exist precisely to
## show growth AFTER the ladder has run out.
var _stars: int = 0
## Golden angle: spreads any number of stars evenly around the orbit without a
## table, and keeps the pattern stable when one more star is added mid-run.
const STAR_GOLDEN_ANGLE: float = 2.3999632


func _ready() -> void:
	# Ornaments are decoration: they must never eat a touch or a physics query.
	z_index = 1 if front else -1


func set_look(look: Dictionary, radius: float, time: float, alpha: float) -> void:
	_look = look
	_radius = radius
	_time = time
	_alpha = alpha
	queue_redraw()


func set_ascension_stars(count: int) -> void:
	## Separate from `set_look` because the count is a function of MASS, not of the
	## ladder position: past stage 15 the look is constant while mass keeps climbing.
	var c := clampi(count, 0, EvolutionStages.MAX_ASCENSION_STARS)
	if c == _stars:
		return
	_stars = c
	queue_redraw()


func _draw() -> void:
	if _look.is_empty() or _alpha <= 0.01:
		return
	var rim: Color = _look["rim_c"]
	_acc = rim
	_acc.s = clampf(maxf(rim.s, 0.40), 0.0, 1.0)
	_acc.v = minf(rim.v, 0.93)
	# The last stages have a near-white rim *and* a pale body, so a rim-coloured
	# crown has nothing to contrast against — measured on the stage-15 preview, where
	# the tiara disappeared into the body. When the accent is that light, darken it
	# into bronze instead: a dark gold crown on a cream body reads by its shadow.
	if _acc.v > 0.84:
		_acc.v = 0.60
		_acc.s = clampf(_acc.s * 1.40, 0.45, 1.0)
	_edge = _acc
	_edge.s = minf(_acc.s * 1.18, 1.0)
	_edge.v = _acc.v * 0.36
	_lit = _acc
	_lit.s = _acc.s * 0.30
	_lit.v = 1.0
	# Light-made elements: halo bands, motes. These stay light, because their job is
	# to look like emission rather than like an object.
	_glow = rim
	_glow.s = clampf(rim.s * 0.55, 0.0, 0.45)
	_glow.v = maxf(rim.v, 0.94)
	# ...but the LARGE shapes (wings, petals) cannot use that colour on the last
	# stages. The body there is cream (luminance 0.74 at stage 13, 0.88 at 15) and
	# the world behind it is warm gold, so white wings measured as "not there" on a
	# real stage-15 frame - the slime read as a potato with a crown. Big shapes get
	# their own colour that crosses over as the body brightens: pale on a dark body,
	# a deep shade of the same hue on a light one, with _lit kept bright so the shape
	# always has one luminous edge.
	var body_lum := (_look["body_c"] as Color).get_luminance()
	var darken := clampf((body_lum - 0.60) / 0.26, 0.0, 1.0)
	_darken = darken
	_veil = rim
	_veil.s = clampf(lerpf(rim.s * 0.55, 0.70, darken), 0.0, 1.0)
	_veil.v = lerpf(maxf(rim.v, 0.94), 0.16, darken)
	if front:
		_draw_ascension_stars(false)
		_draw_crown()
		_draw_motes()
	else:
		_draw_ground_pool()
		_draw_sigil()
		_draw_wings()
		_draw_petals()
		_draw_antlers()
		_draw_halo()
		_draw_ascension_stars(true)


# --- primitives ----------------------------------------------------------

func _quad_pts(a: Vector2, c: Vector2, b: Vector2, steps: int = 10) -> PackedVector2Array:
	var pts := PackedVector2Array()
	for i in range(steps + 1):
		var t := float(i) / float(steps)
		var u := 1.0 - t
		pts.append(a * (u * u) + c * (2.0 * u * t) + b * (t * t))
	return pts


func _capsule(a: Vector2, b: Vector2, w: float, col: Color) -> void:
	## A stroke with round ends. Widths are never allowed under ~1.6 px by the
	## callers: below that a form stops reading as a form and starts reading as a
	## scratch, which is exactly what the previous version looked like.
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal() * (w * 0.5)
	draw_colored_polygon(PackedVector2Array([a + n, b + n, b - n, a - n]), col)
	draw_circle(a, w * 0.5, col)
	draw_circle(b, w * 0.5, col)


func _taper(a: Vector2, b: Vector2, w0: float, w1: float, col: Color) -> void:
	## A stroke that loses width along its length: one quad plus rounded ends, so
	## there is no seam at the joint.
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal()
	draw_colored_polygon(PackedVector2Array([
		a + n * w0 * 0.5, b + n * w1 * 0.5, b - n * w1 * 0.5, a - n * w0 * 0.5,
	]), col)
	draw_circle(a, w0 * 0.5, col)
	draw_circle(b, w1 * 0.5, col)


func _branch(a: Vector2, b: Vector2, w0: float, w1: float, k: float) -> void:
	## A grown limb: soft outer glow, dark contour, body colour, lit highlight.
	## `k` is the ornament weight (0..1) and scales every alpha so a stage that has
	## only just unlocked horns draws them faintly instead of at full strength.
	var glow := Color(_acc.r, _acc.g, _acc.b, 0.10 * k * _alpha)
	_taper(a, b, w0 + 5.0, w1 + 4.0, glow)
	_taper(a, b, w0 + 1.7, w1 + 1.5, Color(_edge.r, _edge.g, _edge.b, 0.90 * k * _alpha))
	_taper(a, b, w0, w1, Color(_acc.r, _acc.g, _acc.b, 0.95 * k * _alpha))
	# Highlight offset along the normal: the single cheapest cue that a limb is a
	# cylinder rather than a flat stripe.
	var d := b - a
	if d.length_squared() < 0.0001:
		return
	var n := d.normalized().orthogonal() * (w0 * 0.24)
	_taper(a + n, b + n, w0 * 0.34, w1 * 0.34,
		Color(_lit.r, _lit.g, _lit.b, 0.55 * k * _alpha))


func _gem(p: Vector2, r: float, k: float) -> void:
	## A cut stone: dark rhombus, accent fill, one specular dot.
	var up := Vector2(0.0, -r)
	var rt := Vector2(r * 0.78, 0.0)
	draw_colored_polygon(PackedVector2Array([
		p + up * 1.45, p + rt * 1.45, p - up * 1.45, p - rt * 1.45,
	]), Color(_edge.r, _edge.g, _edge.b, 0.85 * k * _alpha))
	draw_colored_polygon(PackedVector2Array([p + up, p + rt, p - up, p - rt]),
		Color(_acc.r, _acc.g, _acc.b, 0.95 * k * _alpha))
	draw_circle(p + up * 0.42 + rt * 0.22, r * 0.30,
		Color(_lit.r, _lit.g, _lit.b, 0.75 * k * _alpha))


func _ring_band(centre: Vector2, rx: float, ry: float, half_w: float, col: Color,
		segs: int = 44) -> void:
	## A filled annulus built from quads. draw_arc() with a small width draws a
	## wire loop, and a wire loop around a character reads as a UI element or a
	## debug gizmo; a band with real thickness reads as light or as metal.
	var prev_o := Vector2.ZERO
	var prev_i := Vector2.ZERO
	for i in range(segs + 1):
		var ang := TAU * float(i) / float(segs)
		var dx := cos(ang)
		var dy := sin(ang)
		var o := centre + Vector2(dx * (rx + half_w), dy * (ry + half_w))
		var inn := centre + Vector2(dx * maxf(rx - half_w, 0.4), dy * maxf(ry - half_w, 0.4))
		if i > 0:
			draw_colored_polygon(PackedVector2Array([prev_o, o, inn, prev_i]), col)
		prev_o = o
		prev_i = inn


func _arc_band(centre: Vector2, r0: float, r1: float, a0: float, a1: float,
		col: Color, segs: int = 22) -> void:
	## A filled ribbon following an arc: the crown band is one of these.
	var prev_a := Vector2.ZERO
	var prev_b := Vector2.ZERO
	for i in range(segs + 1):
		var ang := lerpf(a0, a1, float(i) / float(segs))
		var d := Vector2.from_angle(ang)
		var pa := centre + d * r0
		var pb := centre + d * r1
		if i > 0:
			draw_colored_polygon(PackedVector2Array([prev_a, pa, pb, prev_b]), col)
		prev_a = pa
		prev_b = pb


func _blade(root: Vector2, tip: Vector2, width: float, curl: float, fill: Color,
		edge: Color, k: float) -> void:
	## A leaf-shaped fill between two quadratic curves, with a dark rim and a lit
	## vein. Used for feathers and petals: a plain triangle reads as a sticker, a
	## curved blade with a contour reads as something grown.
	var d := (tip - root).normalized()
	var n := d.orthogonal()
	var mid := (root + tip) * 0.5 + n * curl
	var up := _quad_pts(root, mid + n * width, tip)
	var dn := _quad_pts(tip, mid - n * width * 0.62, root)
	var poly := PackedVector2Array(up)
	for i in range(dn.size()):
		poly.append(dn[i])
	draw_colored_polygon(poly, fill)
	# Contour on both edges: without it a translucent blade on a bright floor
	# loses its outline completely.
	var rim := PackedVector2Array(up)
	rim.append(tip)
	draw_polyline(rim, edge, 1.6)
	var rim2 := PackedVector2Array([tip])
	rim2.append_array(dn)
	draw_polyline(rim2, edge, 1.6)
	draw_line(root, tip, Color(_lit.r, _lit.g, _lit.b, 0.45 * k * _alpha), 1.2)


# --- back layer ----------------------------------------------------------

func _draw_ground_pool() -> void:
	## Light the slime casts on the floor. Deliberately under everything else and
	## always on: even at stage 1 the slime is faintly luminous, and by stage 15 this
	## is what makes the grove look lit from the character instead of from nowhere.
	var g := float(_look.get("glow", 0.0))
	var core: Color = _look["core_c"]
	var breathe := 0.9 + 0.1 * sin(_time * 1.3)
	var r := _radius * (2.4 + 1.5 * g) * breathe
	var base := Vector2(0.0, _radius * 0.12)
	for i in range(5):
		var k := 1.0 - float(i) * 0.16
		draw_circle(base, r * k,
			Color(core.r, core.g, core.b, (0.014 + 0.013 * g) * _alpha))
	# A brighter core disc right under the body: the pool needs a source.
	draw_circle(base, _radius * (0.85 + 0.20 * g),
		Color(core.r, core.g, core.b, (0.05 + 0.06 * g) * _alpha))


func _draw_sigil() -> void:
	var s := float(_look.get("sigil", 0.0))
	if s <= 0.02:
		return
	var r := _radius * (2.15 + 0.14 * sin(_time * 0.7))
	# A soft disc under the inscription so the rings sit in light, not on dirt.
	for i in range(3):
		draw_circle(Vector2.ZERO, r * (1.0 - float(i) * 0.22),
			Color(_acc.r, _acc.g, _acc.b, 0.024 * s * _alpha))
	# One ring of inscription, drawn as a soft band of light rather than two thin
	# circles. Two crisp circles at 2.15r and 1.76r read as a radar sweep around the
	# character; one thick faint band plus the floating rune marks reads as light
	# spilling on the floor.
	# Two soft bands and no crisp core. A 1.7 px lit core at this radius is a drawn
	# circle, and a drawn circle around a character reads as a gizmo or a radar
	# sweep; the bands alone read as the edge of a pool of light on the floor.
	_ring_band(Vector2.ZERO, r, r, 10.0, Color(_acc.r, _acc.g, _acc.b, 0.045 * s * _alpha), 56)
	_ring_band(Vector2.ZERO, r, r, 4.2, Color(_acc.r, _acc.g, _acc.b, 0.11 * s * _alpha), 56)
	for i in range(10):
		var a := (TAU / 10.0) * float(i) + _time * 0.35
		var d := Vector2.from_angle(a)
		_gem(d * (r * 0.86), r * 0.030, 0.52 * s)


func _draw_wings() -> void:
	var w := float(_look.get("wings", 0.0))
	if w <= 0.05:
		return
	var flap := 0.88 + 0.12 * sin(_time * 2.1)
	# Three feathers per side, fanned upward and outward. Two earlier versions were
	# wrong here and the preview rig (tools/aura_preview.gd) is what showed it: the
	# tips were computed as -(0.42 - t*0.30)r, so the third lobe pointed *down* and
	# the wing read as a horizontal arrow, and the fill was core_c at 0.24 alpha,
	# which on a pale stage is grey — they looked like dead leaves stuck to the body.
	# Now every tip sweeps up, and the fill is the stage accent with a lit edge.
	for side: float in [-1.0, 1.0]:
		for lobe in range(3):
			var t := float(lobe)
			var root := Vector2(side * _radius * 0.40, -_radius * (0.20 + t * 0.10))
			var spread := _radius * (1.12 + 0.34 * w) * flap * (1.0 - t * 0.14)
			var tip := root + Vector2(side * spread, -_radius * (0.54 - t * 0.15))
			_blade(root, tip, _radius * (0.30 + 0.14 * w),
				side * _radius * (0.24 - t * 0.04),
				Color(_veil.r, _veil.g, _veil.b,
					(lerpf(0.44, 0.92, _darken) - t * 0.09) * w * _alpha),
				Color(_lit.r, _lit.g, _lit.b, (0.58 - t * 0.10) * w * _alpha),
				w)


func _draw_petals() -> void:
	var p := float(_look.get("petals", 0.0))
	if p <= 0.05:
		return
	var count := 6
	for i in range(count):
		var a := (TAU / float(count)) * float(i) - PI * 0.5 + sin(_time * 0.6) * 0.08
		var dir := Vector2.from_angle(a)
		var base := dir * (_radius * 0.86)
		var tip := dir * (_radius * (1.32 + 0.16 * p)) + dir.orthogonal() * sin(_time * 0.9 + float(i)) * _radius * 0.06
		_blade(base, tip, _radius * 0.17 * p, _radius * 0.10 * p,
			Color(_veil.r, _veil.g, _veil.b, lerpf(0.44, 0.88, _darken) * p * _alpha),
			Color(_lit.r, _lit.g, _lit.b, 0.70 * p * _alpha),
			p)


# --- front layer ---------------------------------------------------------

func _draw_crown() -> void:
	var c := float(_look.get("crown", 0.0))
	if c <= 0.05:
		return
	# A tiara on the forehead, not a strap around the head. The first version put
	# the band at 0.99r across 112 degrees, which cut the face in half, and with the
	# points rising from it the whole thing read as a wire basket. The band now sits
	# at 0.62r over 66 degrees — above the eyes — and the points grow outward from it.
	var band_r := _radius * 0.66
	var span := 1.20
	var a0 := -PI * 0.5 - span * 0.5
	var a1 := -PI * 0.5 + span * 0.5
	_arc_band(Vector2.ZERO, band_r - 3.0, band_r + 3.4, a0, a1,
		Color(_edge.r, _edge.g, _edge.b, 0.88 * c * _alpha), 20)
	_arc_band(Vector2.ZERO, band_r - 1.6, band_r + 2.0, a0, a1,
		Color(_acc.r, _acc.g, _acc.b, 0.96 * c * _alpha), 20)
	_arc_band(Vector2.ZERO, band_r + 1.2, band_r + 2.0, a0, a1,
		Color(_lit.r, _lit.g, _lit.b, 0.60 * c * _alpha), 20)

	# Three points: centre tallest, like a real crown. More than three at 34 px
	# radius turns into a comb.
	var count := 3
	for i in range(count):
		var f := float(i) / float(maxi(1, count - 1))
		var a := -PI * 0.5 + (f - 0.5) * span * 0.92
		var dir := Vector2.from_angle(a)
		var tall := 1.0 - absf(f - 0.5) * 1.10
		var base := dir * (band_r + 1.6)
		var tip := dir * (band_r + _radius * (0.10 + 0.26 * c) * tall)
		_branch(base, tip, _radius * 0.16, maxf(_radius * 0.055, 2.2), c)
		_gem(tip, _radius * 0.062, c)
	# The centre stone sits on the band, between the outer points.
	_gem(Vector2(0.0, -band_r - _radius * 0.02), _radius * 0.085 * (0.6 + 0.4 * c), c)


func _draw_antlers() -> void:
	var h := float(_look.get("horns", 0.0))
	if h <= 0.05:
		return
	# Behind the body: an antler grows out of the back of the head, so letting the
	# jelly occlude its root is what makes it sit in the silhouette instead of
	# floating in front of the face.
	for side: float in [-1.0, 1.0]:
		var root := Vector2(side * _radius * 0.40, -_radius * 0.66)
		var mid := root + Vector2(side * _radius * 0.30, -_radius * (0.50 + 0.20 * h))
		var tip := mid + Vector2(side * _radius * 0.22, -_radius * (0.30 + 0.26 * h))
		_branch(root, mid, _radius * 0.20, _radius * 0.14, h)
		_branch(mid, tip, _radius * 0.14, maxf(_radius * 0.07, 2.6), h)
		# One prong, swept back and up. Two prongs per side read as an insect leg
		# at phone size; one reads as a branch.
		var prong := mid + Vector2(-side * _radius * 0.10, -_radius * 0.34)
		_branch(mid, prong, _radius * 0.11, maxf(_radius * 0.05, 2.2), h * 0.92)
		_gem(tip, _radius * 0.058, h)
		_gem(prong, _radius * 0.042, h * 0.9)


func _draw_halo() -> void:
	var ha := float(_look.get("halo", 0.0))
	if ha <= 0.05:
		return
	# Behind the body and wider than it, so the jelly occludes the lower arc and
	# only the top of the ring shows: that is what makes a ring read as a halo
	# rather than as a wire hoop. The previous version drew it in front, at 1.05r,
	# which put a bright ellipse straight across the crown.
	var rx := _radius * (1.26 + 0.12 * ha)
	var ry := _radius * (0.34 + 0.04 * ha)
	var centre := Vector2(0.0, -_radius * 0.86)
	# The band carries the glow and the core carries the edge. An earlier pass set
	# the wide bands to 0.02 alpha, which is invisible on a lit floor: only the thin
	# core survived and the halo went straight back to reading as a wire hoop.
	_ring_band(centre, rx, ry, 11.0, Color(_glow.r, _glow.g, _glow.b, 0.10 * ha * _alpha), 44)
	_ring_band(centre, rx, ry, 6.0, Color(_glow.r, _glow.g, _glow.b, 0.22 * ha * _alpha), 44)
	_ring_band(centre, rx, ry, 3.4, Color(_glow.r, _glow.g, _glow.b, 0.45 * ha * _alpha), 44)
	# A contour BETWEEN the glow and the core. Without it the halo is pure light, and
	# pure light has nothing to define it against the warm gold the world turns at
	# the top of the ladder - on the stage-15 frame the ring was simply absent. The
	# dark band is wider than the lit core, so it survives as an outline on both
	# sides of it while the core stays bright.
	_ring_band(centre, rx, ry, 4.6, Color(_edge.r, _edge.g, _edge.b, 0.42 * ha * _alpha), 44)
	_ring_band(centre, rx, ry, 1.9, Color(_lit.r, _lit.g, _lit.b, 0.62 * ha * _alpha), 44)
	# A tighter inner ring with the contour colour gives the halo depth, so it reads
	# as a ring with thickness rather than as one drawn ellipse.
	_ring_band(centre, rx * 0.62, ry * 0.58, 1.1,
		Color(_edge.r, _edge.g, _edge.b, 0.26 * ha * _alpha), 36)


func _draw_motes() -> void:
	var m := float(_look.get("motes", 0.0))
	if m <= 0.05:
		return
	var core: Color = _look["core_c"]
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
		draw_circle(p, rad * 3.0, Color(_glow.r, _glow.g, _glow.b, 0.11 * m * _alpha * tw))
		draw_circle(p, rad * 1.25, Color(_edge.r, _edge.g, _edge.b, 0.30 * m * _alpha * tw))
		draw_circle(p, rad, Color(core.r, core.g, core.b, 0.88 * m * _alpha * tw))
		draw_circle(p - Vector2(rad * 0.3, rad * 0.3), rad * 0.42,
			Color(_lit.r, _lit.g, _lit.b, 0.70 * m * _alpha * tw))


## One star's hue. The orbit is a colour wheel in miniature: neighbouring stars sit
## 0.09 apart in hue, so a full set of seven spans a rainbow arc around the slime
## instead of seven identical dots.
func _star_color(index: int) -> Color:
	var h := fposmod(_glow.h + 0.09 * float(index), 1.0)
	# Saturation drops a little per star so the seventh is a soft pearl rather than
	# a seventh competing colour on an already busy silhouette.
	var s := clampf(0.62 - 0.05 * float(index), 0.18, 1.0)
	return Color.from_hsv(h, s, 1.0)


func _star_pts(centre: Vector2, outer: float, inner: float) -> PackedVector2Array:
	## A four-point sparkle: long axis at 0/90 degrees, short axis on the diagonals.
	## A plain circle at this size (4-8 px on a phone) reads as dust; the four points
	## are what makes the eye call it a star even when it is only a few pixels across.
	var pts := PackedVector2Array()
	for i in range(8):
		var a := float(i) * TAU / 8.0 - PI * 0.5
		var r := outer if (i % 2) == 0 else inner
		pts.append(centre + Vector2(cos(a), sin(a)) * r)
	return pts


func _draw_ascension_stars(behind: bool) -> void:
	## Companion stars for endless growth. Split across the two aura instances by
	## whether the star is currently above or below the body's centre, so the body
	## occludes the far half of the orbit instead of the stars floating on top of it.
	if _stars <= 0 or _alpha <= 0.01:
		return
	var centre := Vector2(0.0, -_radius * 0.30)
	for i in range(_stars):
		var phase := float(i) * STAR_GOLDEN_ANGLE
		# Alternating direction: two stars never sit on the same bearing, and the
		# whole set reads as orbiting rather than as a rotating rigid ring.
		var dir := 1.0 if (i % 2) == 0 else -1.0
		var speed := 0.62 + 0.07 * float(i)
		var a := phase + _time * speed * dir
		var orbit := _radius * (1.58 + 0.085 * float(i))
		var p := centre + Vector2(cos(a) * orbit, sin(a) * orbit * 0.52)
		if (p.y < centre.y) != behind:
			continue
		var tw := 0.72 + 0.28 * sin(_time * 2.6 + phase)
		# Size floor: below ~4 px a sparkle stops being a shape and becomes a smudge,
		# and the early stages have a radius of only 25-35 px.
		var outer := maxf(_radius * 0.135, 4.2) * (0.85 + 0.20 * tw)
		var col := _star_color(i)
		# Trail: three shrinking ghosts of the same star, behind it along the orbit.
		for k in range(1, 4):
			var ta := a - dir * 0.15 * float(k)
			var tp := centre + Vector2(cos(ta) * orbit, sin(ta) * orbit * 0.52)
			var fade := (1.0 - float(k) / 4.0) * 0.34 * tw
			var tr := outer * (1.0 - 0.16 * float(k))
			draw_colored_polygon(_star_pts(tp, tr * 0.62, tr * 0.18),
				Color(col.r, col.g, col.b, fade * _alpha))
		# Halo, contour, body, core - the same four layers as every other form here,
		# for the same reason: on the cream stages a bare bright shape has nothing to
		# sit against, and the contour is what keeps it legible.
		draw_circle(p, outer * 1.85, Color(col.r, col.g, col.b, 0.11 * tw * _alpha))
		draw_colored_polygon(_star_pts(p, outer * 1.16, outer * 0.34),
			Color(_edge.r, _edge.g, _edge.b, 0.42 * tw * _alpha))
		draw_colored_polygon(_star_pts(p, outer, outer * 0.30),
			Color(col.r, col.g, col.b, 0.95 * tw * _alpha))
		draw_circle(p, outer * 0.26, Color(1.0, 1.0, 1.0, 0.88 * tw * _alpha))
