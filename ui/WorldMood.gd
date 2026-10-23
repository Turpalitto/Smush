class_name WorldMood
extends CanvasLayer
## The forest's mood, driven by how much the slime has grown.
##
## Sits between the world and the HUD (layer 5: above the low-HP vignette's
## sibling order is irrelevant, below the HUD at 10) and applies one screen-space
## grade to everything drawn under it. The point is that growth has to be visible
## in the *place*, not only on the character: at stage 1 the forest is a cold,
## damp, teal cave; by stage 15 the same forest is warm, lit from the slime
## outwards, with lifted shadows and a softer vignette.
##
## One draw call, one fullscreen pass. Measured against the alternative of
## re-tinting the floor shader plus every prop, which would touch hundreds of
## modulate values per stage change and still miss the enemies.

const MOOD_KEYS: Array[float] = [0.0, 0.34, 0.68, 1.0]

## Per-key grade. Cold and closed at the bottom, open and warm at the top.
## tint/warm are hex because Color() in a const array is not a constant
## expression; they are parsed once below.
const MOOD_TINT: Array[String] = ["#6bf5d8", "#8ef2c8", "#ffd88a", "#fff0c4"]
const MOOD_WARM: Array[String] = ["#8fffd8", "#b6ffd0", "#ffcf82", "#fff2c8"]
const MOOD_TINT_AMOUNT: Array[float] = [0.00, 0.10, 0.20, 0.26]
const MOOD_WARM_AMOUNT: Array[float] = [0.00, 0.22, 0.55, 0.78]
const MOOD_AURA_RADIUS: Array[float] = [0.42, 0.46, 0.52, 0.58]
const MOOD_SATURATION: Array[float] = [1.00, 1.06, 1.14, 1.20]
const MOOD_LIFT: Array[float] = [0.000, 0.010, 0.030, 0.046]
const MOOD_VIGNETTE: Array[float] = [0.34, 0.30, 0.24, 0.18]
## Dream bloom strength. Non-zero at stage 1 on purpose: the brief asks for a magical
## forest, not for magic that switches on halfway. It stays low at the bottom (0.14)
## so the early game still reads as a damp cave, and opens up as the slime grows.
const MOOD_BLOOM: Array[float] = [0.14, 0.26, 0.44, 0.60]

var _rect: ColorRect
var _mat: ShaderMaterial
var _player: Node2D
var _growth: float = -1.0
var _time: float = 0.0
## Stage-up pulse: set by flash(), decays here. Kept as a plain float so the
## uniform write happens only while it is actually fading.
var _flash: float = 0.0


func _ready() -> void:
	layer = 5
	name = "WorldMood"
	_rect = ColorRect.new()
	_rect.name = "Grade"
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	_rect.set_anchors_and_offsets_preset(Control.PRESET_FULL_RECT)
	_rect.color = Color(1.0, 1.0, 1.0, 1.0)
	var sh := load("res://shaders/world_mood.gdshader") as Shader
	if sh == null:
		# Without the shader the node must not black out the screen.
		_rect.color = Color(1.0, 1.0, 1.0, 0.0)
	else:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		_rect.material = _mat
	add_child(_rect)
	set_growth(0.0)


func flash(colour: Color, strength: float = 1.0) -> void:
	## Called on every growth stage change. Not a screen flash: the shader multiplies
	## this by the radial term, so what the player sees is a ring of light leaving
	## the slime and washing over the forest.
	if _mat == null:
		return
	_mat.set_shader_parameter("flash_color", colour)
	_flash = maxf(_flash, clampf(strength, 0.0, 1.0))


func set_player(p: Node2D) -> void:
	_player = p


func set_growth(g: float) -> void:
	## Cheap to call on every mass change: it early-outs unless the value moved.
	var v := clampf(g, 0.0, 1.0)
	if absf(v - _growth) < 0.004 or _mat == null:
		_growth = v
		return
	_growth = v
	var i := 0
	while i < MOOD_KEYS.size() - 2 and v > MOOD_KEYS[i + 1]:
		i += 1
	var lo: float = MOOD_KEYS[i]
	var hi: float = MOOD_KEYS[i + 1]
	var w := clampf((v - lo) / maxf(0.001, hi - lo), 0.0, 1.0)
	_mat.set_shader_parameter("tint", Color(MOOD_TINT[i]).lerp(Color(MOOD_TINT[i + 1]), w))
	_mat.set_shader_parameter("warm", Color(MOOD_WARM[i]).lerp(Color(MOOD_WARM[i + 1]), w))
	_mat.set_shader_parameter("tint_amount", lerpf(MOOD_TINT_AMOUNT[i], MOOD_TINT_AMOUNT[i + 1], w))
	_mat.set_shader_parameter("warm_amount", lerpf(MOOD_WARM_AMOUNT[i], MOOD_WARM_AMOUNT[i + 1], w))
	_mat.set_shader_parameter("aura_radius", lerpf(MOOD_AURA_RADIUS[i], MOOD_AURA_RADIUS[i + 1], w))
	_mat.set_shader_parameter("saturation", lerpf(MOOD_SATURATION[i], MOOD_SATURATION[i + 1], w))
	_mat.set_shader_parameter("lift", lerpf(MOOD_LIFT[i], MOOD_LIFT[i + 1], w))
	_mat.set_shader_parameter("vignette", lerpf(MOOD_VIGNETTE[i], MOOD_VIGNETTE[i + 1], w))
	_mat.set_shader_parameter("dream_bloom", lerpf(MOOD_BLOOM[i], MOOD_BLOOM[i + 1], w))


func _process(delta: float) -> void:
	if _mat == null or _player == null or not is_instance_valid(_player):
		return
	_time += delta
	# The aura has to sit on the slime, and the slime is wherever the camera
	# happens to be looking, so the position is read from the live canvas
	# transform rather than assumed to be the screen centre.
	var vp := get_viewport().get_visible_rect().size
	if vp.x <= 1.0 or vp.y <= 1.0:
		return
	var screen_pos := get_viewport().get_canvas_transform() * _player.global_position
	_mat.set_shader_parameter("player_uv", Vector2(screen_pos.x / vp.x, screen_pos.y / vp.y))
	_mat.set_shader_parameter("pulse", 0.5 + 0.5 * sin(_time * 1.1))
	if _flash > 0.0:
		_flash = maxf(0.0, _flash - delta * 1.8)
		_mat.set_shader_parameter("flash", _flash)
