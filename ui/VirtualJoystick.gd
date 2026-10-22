class_name VirtualJoystick
extends Control
## One-finger virtual joystick supporting both Fixed ("fixed") and Floating ("floating") modes,
## multi-resolution scaling, touch events, and desktop mouse drag testing.

var max_radius: float = 68.0
var deadzone: float = 0.08
var output_vector: Vector2 = Vector2.ZERO

var _active: bool = false
var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_PASS
	Events.settings_changed.connect(_on_settings_changed)
	resized.connect(_recompute_default_anchor)
	_recompute_default_anchor()


func _on_settings_changed() -> void:
	_recompute_default_anchor()
	queue_redraw()


func is_floating_mode() -> bool:
	return str(SaveData.get_setting("joystick_mode", "floating")) == "floating"


func _recompute_default_anchor() -> void:
	var default_p := Vector2(size.x * 0.5, maxf(120.0, size.y - 165.0))
	if not _active:
		_base_pos = default_p
		_knob_pos = default_p
	queue_redraw()


func reset_stick() -> void:
	_active = false
	_touch_index = -1
	output_vector = Vector2.ZERO
	_recompute_default_anchor()


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not _active:
			_begin_drag(st.index, st.position)
			accept_event()
		elif not st.pressed and st.index == _touch_index:
			reset_stick()
			accept_event()
	elif event is InputEventScreenDrag:
		var sd := event as InputEventScreenDrag
		if _active and sd.index == _touch_index:
			_update_drag(sd.position)
			accept_event()
	elif event is InputEventMouseButton:
		var mb := event as InputEventMouseButton
		if mb.button_index == MOUSE_BUTTON_LEFT:
			if mb.pressed and not _active:
				_begin_drag(-99, mb.position)
				accept_event()
			elif not mb.pressed and _touch_index == -99:
				reset_stick()
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _active and _touch_index == -99:
			_update_drag(mm.position)
			accept_event()


func _begin_drag(idx: int, local_pos: Vector2) -> void:
	_active = true
	_touch_index = idx
	if is_floating_mode():
		_base_pos = local_pos
		_knob_pos = local_pos
		output_vector = Vector2.ZERO
	else:
		_update_drag(local_pos)
	queue_redraw()


func _update_drag(local_pos: Vector2) -> void:
	var delta := local_pos - _base_pos
	var dist := delta.length()
	if dist > max_radius:
		delta = delta.normalized() * max_radius
	_knob_pos = _base_pos + delta
	var raw_vec := delta / maxf(1.0, max_radius)
	output_vector = Vector2.ZERO if raw_vec.length() < deadzone else raw_vec
	queue_redraw()


func _draw() -> void:
	if is_floating_mode() and not _active:
		# Subtle hint ring at lower center when idle
		var hint_p := Vector2(size.x * 0.5, maxf(120.0, size.y - 165.0))
		draw_arc(hint_p, max_radius * 0.72, 0.0, TAU, 36, Color(0.55, 1.0, 0.86, 0.18), 2.5)
		draw_circle(hint_p, 16.0, Color(0.55, 1.0, 0.86, 0.14))
		return

	var alpha := 0.88 if _active else 0.48
	draw_circle(_base_pos, max_radius, Color(0.05, 0.14, 0.17, 0.45 * alpha))
	draw_arc(_base_pos, max_radius, 0.0, TAU, 40, Color(0.45, 0.96, 0.80, 0.75 * alpha), 3.0)
	draw_circle(_knob_pos, 26.0, Color(0.28, 0.92, 0.72, 0.92 * alpha))
	draw_circle(_knob_pos + Vector2(-5, -5), 7.0, Color(0.90, 1.0, 0.96, 0.75 * alpha))
