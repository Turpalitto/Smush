class_name LakeTouchHud
extends Node
## Lab-only thumb buttons for the Lunar Nova and the dash (phone readiness). Pure UI: it calls the
## same methods as the keyboard (LakeLegends.cast_nova, LakeMutations.dash) and touches no game code.

const SIZE := 112.0
const MARGIN := 28.0

var lab: Node2D
var layer: CanvasLayer
var nova_button: Button
var dash_button: Button


func setup(p_lab: Node2D) -> void:
	lab = p_lab
	layer = CanvasLayer.new()
	layer.layer = 18
	add_child(layer)
	nova_button = _make_button("✦", Color(0.62, 0.85, 1.0))
	dash_button = _make_button("»", Color(0.7, 1.0, 0.85))
	nova_button.pressed.connect(func() -> void: lab.legends.cast_nova())
	dash_button.pressed.connect(func() -> void: lab.mutations_fx.dash())
	nova_button.visible = false
	dash_button.visible = false
	get_viewport().size_changed.connect(_layout)
	_layout()


func _make_button(text: String, tint: Color) -> Button:
	var b := Button.new()
	b.text = text
	b.focus_mode = Control.FOCUS_NONE
	b.mouse_filter = Control.MOUSE_FILTER_STOP
	b.custom_minimum_size = Vector2(SIZE, SIZE)
	b.size = Vector2(SIZE, SIZE)
	b.add_theme_font_size_override("font_size", 46)
	b.add_theme_color_override("font_color", tint)
	var sb := StyleBoxFlat.new()
	sb.bg_color = Color(0.03, 0.1, 0.2, 0.55)
	sb.set_corner_radius_all(int(SIZE * 0.5))
	sb.set_border_width_all(3)
	sb.border_color = Color(tint.r, tint.g, tint.b, 0.8)
	for state in ["normal", "hover", "pressed", "focus", "disabled"]:
		b.add_theme_stylebox_override(state, sb)
	layer.add_child(b)
	return b


func _layout() -> void:
	if nova_button == null:
		return
	var vp := get_viewport().get_visible_rect().size
	nova_button.position = Vector2(vp.x - SIZE - MARGIN, vp.y - SIZE - MARGIN * 2.0)
	dash_button.position = Vector2(vp.x - SIZE * 2.0 - MARGIN * 1.6, vp.y - SIZE - MARGIN * 2.0 + 8.0)


func _process(_delta: float) -> void:
	if lab == null or lab.player == null:
		return
	nova_button.visible = lab.legends.nova_ready
	var p = lab.player
	dash_button.visible = p.mutations.has_mutation("dash")
	dash_button.modulate.a = 1.0 if p.dash_cooldown <= 0.0 else 0.4
