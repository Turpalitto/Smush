class_name OrganicShield
extends Node2D
## EXPERIMENTAL organic shield membrane (GLM visual lab), replacing the static dome
## drawn by SlimeVisual._draw_foreground when `organic_shield` is set.
##
## A translucent second membrane over the body rendered by shaders/organic_shield.gdshader:
## it dents where the blow lands, ripples radiate from the hit, and the film sags and
## re-tensions over the recharge window the mutation already has. Purely visual —
## hit blocking, recharge and the knockback wave stay in PlayerSlime/ArenaController.

var active: bool = false
var quality: int = 2

var _mat: ShaderMaterial
var _rect: ColorRect
var _time: float = 0.0
var _impact: float = 0.0
var _impact_dir: Vector2 = Vector2.RIGHT
var _recovery: float = 1.0
var _shown_alpha: float = 0.0
var _radius: float = 25.0
## Recharge window used only to pace the visual recovery (matches shield's
## recharge_base 11 s / per-level step for context; not gameplay).
var recovery_duration: float = 4.0


func _ready() -> void:
	z_index = 2
	_rect = ColorRect.new()
	_rect.mouse_filter = Control.MOUSE_FILTER_IGNORE
	var shader := load("res://shaders/organic_shield.gdshader") as Shader
	if shader != null:
		_mat = ShaderMaterial.new()
		_mat.shader = shader
		_rect.material = _mat
	add_child(_rect)
	visible = false


func set_radius(r: float) -> void:
	_radius = r


func trigger_impact(local_dir: Vector2) -> void:
	_impact = 1.0
	_impact_dir = local_dir.normalized() if local_dir.length_squared() > 0.001 else Vector2.RIGHT
	_recovery = 0.0


func _process(delta: float) -> void:
	_time += delta
	if active:
		_shown_alpha = move_toward(_shown_alpha, 1.0, delta * 4.5)
		_recovery = move_toward(_recovery, 1.0, delta / maxf(0.3, recovery_duration))
	else:
		_shown_alpha = move_toward(_shown_alpha, 0.0, delta * 3.2)
	_impact = maxf(0.0, _impact - delta * 1.4)

	visible = _shown_alpha > 0.01
	if not visible:
		return
	var box := _radius * 2.6
	_rect.size = Vector2(box, box)
	_rect.position = -Vector2(box, box) * 0.5
	if _mat != null:
		_mat.set_shader_parameter("u_time", _time)
		_mat.set_shader_parameter("film_alpha", _shown_alpha)
		_mat.set_shader_parameter("impact", _impact)
		_mat.set_shader_parameter("impact_dir", _impact_dir)
		_mat.set_shader_parameter("recovery", _recovery)
		_mat.set_shader_parameter("quality", quality)
