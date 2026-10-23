class_name MenuGarden
extends Node2D
## Slow life behind the main menu: drifting motes and a few glowing blooms.
##
## The menu background is the forest floor shader at a fixed growth, which is
## texture and light but nothing that moves. This adds the two cheapest things that
## make a still frame feel inhabited — motes that drift and breathe, and a handful
## of bloom sprites from resources/art/props that pulse very slowly.
##
## Deliberately not the gameplay WorldGenerator: the menu has no camera, no chunks
## and no fog, and streaming a world behind a static screen would be both heavier
## and wrong (props popping in behind the title). Everything here is a pure function
## of time and a fixed seed, so the layout is stable between visits.

const MOTE_COUNT := 26
const BLOOM_FILES: Array[String] = [
	"res://resources/art/props/bloom_flower.png",
	"res://resources/art/props/bloom_bells.png",
	"res://resources/art/props/bloom_pod.png",
]

var _t: float = 0.0
var _motes: Array[Vector3] = []
var _blooms: Array[Dictionary] = []
var _warm: Color = Color(1.0, 0.90, 0.66)


func _ready() -> void:
	# No z_index: this node is added after the opaque floor ColorRect and before the
	# UI column, so tree order already puts it above the floor and below the buttons.
	# The first version set z_index = -1 and the whole garden was hidden behind the
	# floor, which read as "the effect does nothing".
	var rng := RandomNumberGenerator.new()
	rng.seed = 90210
	var sz := get_viewport_rect().size
	if sz.x < 1.0 or sz.y < 1.0:
		sz = Vector2(720.0, 1280.0)
	for i in range(MOTE_COUNT):
		_motes.append(Vector3(
			rng.randf_range(0.04, 0.96) * sz.x,
			rng.randf_range(0.10, 0.92) * sz.y,
			rng.randf() * TAU
		))
	# Blooms go where the button block is not: the buttons occupy roughly the middle
	# 50-75% of the height, so the first version's spots (0.70, 0.62, 0.90) were all
	# either behind the buttons or off the bottom edge.
	var spots := [Vector2(0.13, 0.20), Vector2(0.87, 0.31), Vector2(0.20, 0.44),
		Vector2(0.82, 0.90), Vector2(0.12, 0.93)]
	for i in range(spots.size()):
		var tex := load(BLOOM_FILES[i % BLOOM_FILES.size()]) as Texture2D
		if tex == null:
			continue
		_blooms.append({
			"pos": Vector2(spots[i].x * sz.x, spots[i].y * sz.y),
			"tex": tex,
			"phase": rng.randf() * TAU,
			"size": rng.randf_range(46.0, 68.0),
		})


func _process(delta: float) -> void:
	_t += delta
	queue_redraw()


func _draw() -> void:
	for b in _blooms:
		var pulse := 0.86 + 0.14 * sin(_t * 0.7 + float(b["phase"]))
		var s: float = float(b["size"]) * pulse
		var p: Vector2 = b["pos"]
		var tex: Texture2D = b["tex"]
		# Soft light behind the sprite: a texture cannot be blurred at runtime, so
		# the glow is three stacked discs rather than a real bloom.
		for i in range(3):
			draw_circle(p, s * (0.62 + 0.16 * float(i)),
				Color(_warm.r, _warm.g, _warm.b, 0.028))
		# Kept translucent on purpose: at full opacity the sprites read as stickers
		# pasted on the floor rather than as something growing out of it.
		draw_texture_rect(tex, Rect2(p - Vector2(s, s) * 0.5, Vector2(s, s)), false,
			Color(1.0, 1.0, 1.0, 0.42 + 0.14 * pulse))

	for m in _motes:
		var x := m.x + sin(_t * 0.24 + m.z) * 26.0
		var y := m.y + cos(_t * 0.19 + m.z * 1.7) * 18.0
		var tw := 0.5 + 0.5 * sin(_t * (1.1 + fmod(m.z, 1.0)) + m.z)
		var a := (0.18 + 0.34 * tw)
		draw_circle(Vector2(x, y), 3.0 + 2.2 * tw, Color(_warm.r, _warm.g, _warm.b, 0.10 * a))
		draw_circle(Vector2(x, y), 1.1 + 0.9 * tw, Color(1.0, 1.0, 0.92, 0.80 * a))
