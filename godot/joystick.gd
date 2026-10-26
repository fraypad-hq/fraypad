extends Control
class_name FraypadStick

signal value_changed(joystick_value: Vector2)
signal clicked

@export_range(0.0, 0.5, 0.01) var deadzone: float = 0.08
@export var tap_max_travel: float = 20.0
@export var tap_max_seconds: float = 0.30

var _touch_index: int = -1
var _center: Vector2 = Vector2.ZERO
var output: Vector2 = Vector2.ZERO

var _radius: float = 60.0
var _knob: float = 48.0

var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _travelled: float = 0.0

var _knob_offset: Vector2 = Vector2.ZERO


func _ready() -> void:
	resized.connect(_layout)
	_layout()


func _layout() -> void:
	var side: float = minf(size.x, size.y)
	_radius = maxf(side * 0.5 - 6.0, 10.0)
	_knob = side * 0.38
	_center = size * 0.5
	_recentre()


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _touch_index != -1:
			_touch_index = -1
			_recentre()


func _recentre() -> void:
	output = Vector2.ZERO
	_knob_offset = Vector2.ZERO
	queue_redraw()
	value_changed.emit(output)


func _draw() -> void:
	draw_circle(_center, _radius, Color(0.08, 0.09, 0.12, 0.92))
	draw_arc(_center, _radius, 0.0, TAU, 64, Color(0.20, 0.23, 0.30, 0.85), 2.0)

	var dz_r := _radius * deadzone
	draw_arc(_center, dz_r, 0.0, TAU, 32, Color(0.24, 0.28, 0.36, 0.4), 1.0)

	var tick_len := 6.0
	var col_tick := Color(0.30, 0.35, 0.44, 0.6)
	draw_line(_center + Vector2(0, -_radius), _center + Vector2(0, -_radius + tick_len), col_tick, 1.5)
	draw_line(_center + Vector2(0, _radius), _center + Vector2(0, _radius - tick_len), col_tick, 1.5)
	draw_line(_center + Vector2(-_radius, 0), _center + Vector2(-_radius + tick_len, 0), col_tick, 1.5)
	draw_line(_center + Vector2(_radius, 0), _center + Vector2(_radius - tick_len, 0), col_tick, 1.5)

	var knob_center := _center + _knob_offset
	var knob_r := _knob * 0.5

	if _knob_offset.length_squared() > 4.0:
		draw_line(_center, knob_center, Color(0.10, 0.65, 0.35, 0.35), 2.0)

	draw_circle(knob_center, knob_r, Color(0.13, 0.15, 0.20, 0.98))
	draw_arc(knob_center, knob_r, 0.0, TAU, 48, Color(0.32, 0.37, 0.48, 0.9), 2.0)

	var inner_r := knob_r * 0.55
	var inner_col := Color(0.10, 0.65, 0.35, 0.7) if output.length_squared() > 0.01 else Color(0.18, 0.21, 0.28, 0.9)
	draw_circle(knob_center, inner_r, Color(0.08, 0.09, 0.12, 1.0))
	draw_arc(knob_center, inner_r, 0.0, TAU, 32, inner_col, 1.5)


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(0, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseMotion and _touch_index == 0:
		_handle_drag(0, event.position)


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed and _touch_index == -1:
		_touch_index = index
		_press_pos = pos
		_press_time = Time.get_ticks_msec() / 1000.0
		_travelled = 0.0
		Input.vibrate_handheld(10)
		_update_joystick(pos)
	elif not pressed and _touch_index == index:
		_touch_index = -1
		_recentre()
		_maybe_emit_click()


func _handle_drag(index: int, pos: Vector2) -> void:
	if index == _touch_index:
		_travelled = maxf(_travelled, pos.distance_to(_press_pos))
		_update_joystick(pos)


func _update_joystick(pos: Vector2) -> void:
	var diff := pos - _center
	var dist := diff.length()
	var clamped_diff := diff
	if dist > _radius:
		clamped_diff = diff.normalized() * _radius
		dist = _radius

	_knob_offset = clamped_diff

	var normalized_mag := dist / _radius
	if normalized_mag < deadzone:
		output = Vector2.ZERO
	else:
		var remapped := (normalized_mag - deadzone) / (1.0 - deadzone)
		output = clamped_diff.normalized() * clampf(remapped, 0.0, 1.0)

	queue_redraw()
	value_changed.emit(output)


func _maybe_emit_click() -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _press_time
	if _travelled <= tap_max_travel * (_radius / 60.0) and elapsed <= tap_max_seconds:
		Input.vibrate_handheld(20)
		clicked.emit()
