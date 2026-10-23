class_name VirtualJoystick
extends Control
## One-finger virtual joystick supporting both Fixed ("fixed") and Floating ("floating") modes,
## dynamic floating-anchor follow for instant reversals, analog deadzone remapping,
## optional quick double-tap gesture, multi-resolution scaling, touch events, and mouse drag.

signal quick_double_tapped()

## Alpha the joystick rests at. The brief asks for 0.22 and the whole drawing is
## scaled by one factor, so the brightest element of a parked joystick is drawn at
## exactly this value instead of "roughly dim".
const REST_ALPHA: float = 0.22
## Seconds to travel from fully visible to REST_ALPHA once the thumb lifts.
const REST_FADE_SEC: float = 0.55

var max_radius: float = 66.0
var deadzone: float = 0.08
var has_right_skill_buttons: bool = false
var excluded_zones: Array[Rect2] = []
var output_vector: Vector2 = Vector2.ZERO

var _active: bool = false
var _touch_index: int = -1
var _base_pos: Vector2 = Vector2.ZERO
var _knob_pos: Vector2 = Vector2.ZERO
var _press_origin: Vector2 = Vector2.ZERO
var _max_excursion: float = 0.0
var _press_time_msec: int = 0
var _last_tap_msec: int = -9999
var _last_tap_pos: Vector2 = Vector2.ZERO
var _rest_fade: float = 1.0


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
	var anchor_x := size.x * (0.36 if has_right_skill_buttons else 0.5)
	if not is_floating_mode():
		anchor_x = clampf(anchor_x, max_radius + 26.0, maxf(max_radius + 26.0, size.x - 185.0))
	var default_p := Vector2(anchor_x, maxf(120.0, size.y - 155.0))
	if not _active:
		_base_pos = default_p
		_knob_pos = default_p
	queue_redraw()


func reset_stick() -> void:
	_active = false
	_touch_index = -1
	output_vector = Vector2.ZERO
	_recompute_default_anchor()


func _process(delta: float) -> void:
	tick_rest(delta)


func tick_rest(delta: float) -> void:
	## Fades the whole stick toward REST_ALPHA while it is parked, and snaps back
	## to full on the first touch. Split out of _process so the test can advance
	## the fade deterministically instead of hoping for enough real frames.
	if _active:
		if not is_equal_approx(_rest_fade, 1.0):
			_rest_fade = 1.0
			queue_redraw()
		return
	if _rest_fade <= REST_ALPHA + 0.0005:
		if not is_equal_approx(_rest_fade, REST_ALPHA):
			_rest_fade = REST_ALPHA
			queue_redraw()
		return
	_rest_fade = maxf(REST_ALPHA, _rest_fade - delta / REST_FADE_SEC * (1.0 - REST_ALPHA))
	queue_redraw()


func draw_alpha() -> float:
	## The alpha the stick's brightest element is drawn at. Held: 1.0. Parked:
	## exactly REST_ALPHA. The test asserts on this function, which is the same
	## expression _draw multiplies every colour by.
	if _active:
		return 1.0
	return _rest_fade


func _is_in_excluded_zone(local_pos: Vector2) -> bool:
	for zone in excluded_zones:
		if zone.has_point(local_pos):
			return true
	return false


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		var st := event as InputEventScreenTouch
		if st.pressed and not _active:
			if _is_in_excluded_zone(st.position):
				return
			_begin_drag(st.index, st.position)
			accept_event()
		elif not st.pressed and st.index == _touch_index:
			_finish_drag(st.position)
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
				if _is_in_excluded_zone(mb.position):
					return
				_begin_drag(-99, mb.position)
				accept_event()
			elif not mb.pressed and _touch_index == -99:
				_finish_drag(mb.position)
				accept_event()
	elif event is InputEventMouseMotion:
		var mm := event as InputEventMouseMotion
		if _active and _touch_index == -99:
			_update_drag(mm.position)
			accept_event()


func _begin_drag(idx: int, local_pos: Vector2) -> void:
	_active = true
	_touch_index = idx
	_press_origin = local_pos
	_max_excursion = 0.0
	_press_time_msec = Time.get_ticks_msec()
	# Instant restore: a parked stick becomes fully visible on the touch-down
	# frame, not 0.55 s later.
	_rest_fade = 1.0
	if is_floating_mode():
		_base_pos = local_pos
		_knob_pos = local_pos
		output_vector = Vector2.ZERO
	else:
		_update_drag(local_pos)
	queue_redraw()


func _finish_drag(release_pos: Vector2) -> void:
	var now := Time.get_ticks_msec()
	var held_ms := now - _press_time_msec
	var moved := maxf(_max_excursion, release_pos.distance_to(_press_origin))
	reset_stick()
	if not bool(SaveData.get_setting("double_tap_dash", true)):
		return
	if held_ms <= 165 and moved <= 8.0:
		if (now - _last_tap_msec) <= 230 and release_pos.distance_to(_last_tap_pos) <= 28.0:
			_last_tap_msec = -9999
			quick_double_tapped.emit()
		else:
			_last_tap_msec = now
			_last_tap_pos = release_pos


func _update_drag(local_pos: Vector2) -> void:
	_max_excursion = maxf(_max_excursion, local_pos.distance_to(_press_origin))
	var delta := local_pos - _base_pos
	var dist := delta.length()
	if dist > max_radius:
		var dir := delta / maxf(0.001, dist)
		if is_floating_mode():
			# Dynamic follow-base eliminates dead-space lag when reversing thumb direction
			_base_pos = local_pos - dir * max_radius
		delta = dir * max_radius
	_knob_pos = _base_pos + delta
	var raw_vec := delta / maxf(1.0, max_radius)
	var mag := raw_vec.length()
	if mag < deadzone:
		output_vector = Vector2.ZERO
	else:
		var remapped := clampf((mag - deadzone) / maxf(0.01, 1.0 - deadzone), 0.0, 1.0)
		output_vector = (raw_vec / mag) * remapped
	queue_redraw()


func _draw() -> void:
	# One factor for the whole stick. At rest it is REST_ALPHA, so the brightest
	# element (the knob) lands on exactly 0.22 and nothing is drawn brighter than
	# the brief allows; held, it is 1.0.
	var a := draw_alpha()
	if is_floating_mode() and not _active:
		# Subtle hint ring at lower center when idle. In floating mode this ring is
		# the whole joystick, so its alpha is the rest alpha directly.
		var hint_x := size.x * (0.40 if has_right_skill_buttons else 0.5)
		var hint_p := Vector2(hint_x, maxf(120.0, size.y - 155.0))
		draw_arc(hint_p, max_radius * 0.72, 0.0, TAU, 36, Color(0.55, 1.0, 0.86, a), 2.5)
		draw_circle(hint_p, 16.0, Color(0.55, 1.0, 0.86, a * 0.64))
		return

	draw_circle(_base_pos, max_radius, Color(0.05, 0.14, 0.17, 0.45 * a))
	draw_arc(_base_pos, max_radius, 0.0, TAU, 40, Color(0.45, 0.96, 0.80, 0.78 * a), 3.0)
	if _active and output_vector.length() > 0.05:
		draw_line(_base_pos, _knob_pos, Color(0.55, 1.0, 0.86, 0.42 * a), 4.0)
	draw_circle(_knob_pos, 26.0, Color(0.28, 0.92, 0.72, a))
	draw_circle(_knob_pos + Vector2(-5, -5), 7.0, Color(0.90, 1.0, 0.96, 0.78 * a))
