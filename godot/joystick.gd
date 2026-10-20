extends Control
class_name FraypadStick

signal value_changed(joystick_value: Vector2)
## Emitted when the stick is tapped rather than dragged. This is the stick
## click (L3 / R3).
signal clicked

## Radial deadzone. Inputs with a magnitude below this emit exactly zero so
## tiny thumb-rest drift never registers as movement. Above it the output is
## rescaled so the stick still reaches full deflection.
@export_range(0.0, 0.5, 0.01) var deadzone: float = 0.08

## A press-release inside this travel distance and this time counts as a tap,
## which fires `clicked` (the stick click, L3 / R3) instead of a drag.
## Travel is measured against the stick's own size, so this scales with it.
@export var tap_max_travel: float = 20.0
@export var tap_max_seconds: float = 0.30

var _touch_index: int = -1
var _center: Vector2
var output: Vector2 = Vector2.ZERO

## Radius of the deflection circle, derived from the control's actual size in
## `_ready` so the stick scales with the screen instead of staying a fixed
## pixel size on a large phone display.
var _radius: float = 60.0
## Diameter of the draggable knob, also derived from the control size.
var _knob: float = 48.0

var _press_pos: Vector2 = Vector2.ZERO
var _press_time: float = 0.0
var _travelled: float = 0.0

var _bg: Panel
var _handle: Panel

func _ready() -> void:
	_build()
	# Fill the control rect and take the circle radius from it. The scene sizes
	# this node per screen, so no hardcoded pixel size here.
	resized.connect(_layout)

## Recompute the circle and knob geometry from the current control rect.
func _layout() -> void:
	var side: float = minf(size.x, size.y)
	_radius = side * 0.5 - 6.0
	_knob = side * 0.42
	_center = size * 0.5

	if _bg:
		_bg.size = Vector2(_radius * 2, _radius * 2)
		_bg.position = _center - Vector2(_radius, _radius)
	if _handle:
		_handle.size = Vector2(_knob, _knob)
		_handle.position = _center - Vector2(_knob, _knob) * 0.5


func _build() -> void:
	_bg = Panel.new()
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.18, 0.18, 0.20, 0.85)
	bg_style.border_color = Color(0.35, 0.35, 0.38, 0.9)
	bg_style.set_border_width_all(2)
	bg_style.set_corner_radius_all(999)
	_bg.add_theme_stylebox_override("panel", bg_style)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)

	_handle = Panel.new()
	var handle_style = StyleBoxFlat.new()
	handle_style.bg_color = Color(0.30, 0.30, 0.34, 1.0)
	handle_style.border_color = Color(0.9, 0.9, 0.92, 0.95)
	handle_style.set_border_width_all(3)
	handle_style.set_corner_radius_all(999)
	_handle.add_theme_stylebox_override("panel", handle_style)
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_handle)

	_layout()

## Backgrounding the app cancels all touches, so recenter the stick and tell
## the game. Otherwise a stick left deflected when the user switches away
## keeps the character walking into a wall.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _touch_index == -1:
			return
		_touch_index = -1
		_update_joystick(_center)

func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch or event is InputEventMouseButton:
		var is_pressed: bool = false
		var pos: Vector2
		var index: int = -1
		
		if event is InputEventScreenTouch:
			is_pressed = event.pressed
			pos = event.position
			index = event.index
		elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
			is_pressed = event.pressed
			pos = event.position
			index = 0
			
		if index == -1: return

		if is_pressed and _touch_index == -1:
			_touch_index = index
			_press_pos = pos
			_press_time = Time.get_ticks_msec() / 1000.0
			_travelled = 0.0
			# Deliberately no _update_joystick() here: deflection starts on
			# the first drag, so landing a finger near the rim doesn't snap
			# the stick to full throw.
		elif not is_pressed and _touch_index == index:
			_touch_index = -1
			_update_joystick(_center)
			_maybe_emit_click()
			
	elif event is InputEventScreenDrag or event is InputEventMouseMotion:
		var pos: Vector2
		var index: int = -1
		
		if event is InputEventScreenDrag:
			pos = event.position
			index = event.index
		elif event is InputEventMouseMotion and _touch_index == 0:
			pos = event.position
			index = 0
			
		if index != -1 and index == _touch_index:
			_travelled = maxf(_travelled, pos.distance_to(_press_pos))
			_update_joystick(pos)

func _update_joystick(pos: Vector2) -> void:
	var diff = pos - _center
	var limit: float = maxf(_radius, 1.0)
	if diff.length() > limit:
		diff = diff.normalized() * limit
	output = _apply_deadzone(diff / limit)

	_handle.position = (_center + diff) - Vector2(_knob, _knob) * 0.5
	value_changed.emit(output)

## Fire `clicked` if this press-release was a quick tap rather than a drag.
##
## The press must start on the knob itself (within the knob's radius of
## center), so a tap near the rim of the control can't fire L3/R3; the short
## travel/time window keeps aiming gestures from registering as clicks. Both
## thresholds scale with the stick, which is sized per screen.
func _maybe_emit_click() -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _press_time
	if _press_pos.distance_to(_center) > _knob * 0.6:
		return
	if _travelled <= tap_max_travel * (_radius / 60.0) and elapsed <= tap_max_seconds:
		clicked.emit()

## Map a raw stick vector through a radial deadzone, rescaling the region
## outside the deadzone to the full 0..1 range.
func _apply_deadzone(v: Vector2) -> Vector2:
	var mag = v.length()
	# The `mag < eps` guard also covers deadzone == 0 with a zero vector
	# (0/0 -> NaN) if the export is ever set to its minimum.
	if mag < deadzone or mag < 0.0001:
		return Vector2.ZERO
	return v * ((mag - deadzone) / (1.0 - deadzone)) / mag
