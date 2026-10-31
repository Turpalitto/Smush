class_name ClaudeShield
extends ColorRect
## shield, as anatomy: a second, thin, glassy membrane around the body. It pops in with
## a spring overshoot when the game says the shield is ready (SlimeVisual.shield_active),
## dents and rings when something hits it, and bursts outward when the game consumes it.
## Refraction means the dented bubble bends the slime behind it instead of just
## flashing. Numbers (block, recharge) stay in PlayerSlime.

const SHIELD_SCALE: float = 1.22
const EXTENT: float = 1.5
const SHADER_PATH := "res://shaders/slime_shield_claude.gdshader"

var quality: int = 2

var _mat: ShaderMaterial
var _pop: float = 0.0
var _pop_v: float = 0.0
var _burst: float = -1.0
var _was_active: bool = false
var _impact_t: float = 9.0
var _impact_dir: Vector2 = Vector2.DOWN
var _impact_amp: float = 0.0
var _time: float = 0.0


func _init() -> void:
	mouse_filter = Control.MOUSE_FILTER_IGNORE
	var sh := load(SHADER_PATH) as Shader
	if sh != null:
		_mat = ShaderMaterial.new()
		_mat.shader = sh
		material = _mat
	visible = false


func trigger_impact(dir: Vector2, strength: float) -> void:
	_impact_dir = dir
	_impact_t = 0.0
	_impact_amp = clampf(strength, 0.2, 1.5)


func update_state(dt: float, r0: float, active: bool, frame_ang: float, squash: Vector2,
		body: Color, alpha: float, ice: bool) -> void:
	_time += dt
	if _was_active and not active:
		_burst = 0.0
	_was_active = active
	var target := 1.0 if active else 0.0
	_pop_v += ((target - _pop) * 150.0 - _pop_v * 10.5) * minf(dt, 0.03)
	_pop += _pop_v * minf(dt, 0.03)
	if not active and _pop < 0.0:
		_pop = 0.0
		_pop_v = 0.0
	if _burst >= 0.0:
		_burst += dt * 3.2
		if _burst >= 1.0:
			_burst = -1.0
	_impact_t += dt

	var show := _pop > 0.01 or _burst >= 0.0
	visible = show and alpha > 0.01
	if not visible or _mat == null:
		return
	var rs := r0 * SHIELD_SCALE
	var box := rs * EXTENT * 2.0
	size = Vector2(box, box)
	position = -Vector2(box, box) * 0.5
	_mat.set_shader_parameter(&"extent", EXTENT)
	_mat.set_shader_parameter(&"u_time", _time)
	_mat.set_shader_parameter(&"pop", maxf(_pop, 0.0))
	_mat.set_shader_parameter(&"burst", _burst)
	_mat.set_shader_parameter(&"impact_dir", _impact_dir)
	_mat.set_shader_parameter(&"impact_t", _impact_t)
	_mat.set_shader_parameter(&"impact_amp", _impact_amp)
	_mat.set_shader_parameter(&"frame_dir", Vector2.from_angle(frame_ang))
	_mat.set_shader_parameter(&"squash", Vector2.ONE + (squash - Vector2.ONE) * 0.7)
	_mat.set_shader_parameter(&"tint", body)
	_mat.set_shader_parameter(&"alpha", alpha)
	_mat.set_shader_parameter(&"quality", quality)
	_mat.set_shader_parameter(&"ice", 1.0 if ice else 0.0)
	var vp := get_viewport()
	if vp != null:
		var xf := vp.get_final_transform() * get_global_transform_with_canvas()
		_mat.set_shader_parameter(&"px_per_unit", maxf(xf.get_scale().x * rs, 8.0))
