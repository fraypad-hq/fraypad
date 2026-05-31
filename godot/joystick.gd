extends Control
class_name VirtualJoystick

signal value_changed(joystick_value: Vector2)

@export var max_distance: float = 60.0

var _touch_index: int = -1
var _center: Vector2
var output: Vector2 = Vector2.ZERO

var _bg: Panel
var _handle: Panel

func _ready() -> void:
	custom_minimum_size = Vector2(max_distance * 2 + 40, max_distance * 2 + 40)
	_center = custom_minimum_size / 2.0
	
	_bg = Panel.new()
	var bg_style = StyleBoxFlat.new()
	bg_style.bg_color = Color(0.2, 0.2, 0.2, 0.5)
	bg_style.corner_radius_top_left = int(max_distance)
	bg_style.corner_radius_top_right = int(max_distance)
	bg_style.corner_radius_bottom_left = int(max_distance)
	bg_style.corner_radius_bottom_right = int(max_distance)
	_bg.add_theme_stylebox_override("panel", bg_style)
	_bg.size = Vector2(max_distance * 2, max_distance * 2)
	_bg.position = _center - Vector2(max_distance, max_distance)
	_bg.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_bg)
	
	_handle = Panel.new()
	var handle_style = StyleBoxFlat.new()
	handle_style.bg_color = Color(0.8, 0.8, 0.8, 0.8)
	handle_style.corner_radius_top_left = 24
	handle_style.corner_radius_top_right = 24
	handle_style.corner_radius_bottom_left = 24
	handle_style.corner_radius_bottom_right = 24
	_handle.add_theme_stylebox_override("panel", handle_style)
	_handle.size = Vector2(48, 48)
	_handle.position = _center - Vector2(24, 24)
	_handle.mouse_filter = Control.MOUSE_FILTER_IGNORE
	add_child(_handle)

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
			_update_joystick(pos)
		elif not is_pressed and _touch_index == index:
			_touch_index = -1
			_update_joystick(_center)
			
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
			_update_joystick(pos)

func _update_joystick(pos: Vector2) -> void:
	var diff = pos - _center
	if diff.length() > max_distance:
		diff = diff.normalized() * max_distance
	output = diff / max_distance
	
	_handle.position = (_center + diff) - Vector2(24, 24)
	value_changed.emit(output)
