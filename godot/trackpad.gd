extends Control
class_name FraypadTrackpad

@export var sensitivity: float = 1.2
@export var scroll_sensitivity: float = 0.08
@export var jitter_deadzone: float = 1.2
@export var tap_max_travel: float = 14.0
@export var tap_max_seconds: float = 0.28

var _client: FraypadClient

var _touches: Dictionary = {}
var _primary: int = -1
var _primary_time: float = 0.0
var _primary_travel: float = 0.0
var _secondary: int = -1
var _secondary_travel: float = 0.0
var _dragging: bool = false
var _scrolling: bool = false

var _scroll_accum: float = 0.0
var _mouse_accum: Vector2 = Vector2.ZERO


func _ready() -> void:
	custom_minimum_size = Vector2(240, 200)


func _draw() -> void:
	var r := Rect2(Vector2.ZERO, size)
	draw_rect(r, Color(0.08, 0.09, 0.12, 0.92), true)
	draw_rect(r, Color(0.20, 0.24, 0.32, 0.85), false, 1.5)
	var font := ThemeDB.fallback_font
	var title := "Trackpad"
	draw_string(font, Vector2(16, 26), title, HORIZONTAL_ALIGNMENT_LEFT, -1, 14, Color(0.85, 0.90, 0.96))
	var sub := "Tap: Click  •  2-Finger: Right Click / Scroll"
	draw_string(font, Vector2(16, 44), sub, HORIZONTAL_ALIGNMENT_LEFT, -1, 11, Color(0.45, 0.50, 0.60))


func _get_client() -> FraypadClient:
	if _client == null:
		var root: Node = get_tree().current_scene
		if root == null:
			root = owner
		if root:
			_client = root.get_node_or_null("FraypadClient") as FraypadClient
	return _client


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_reset_gestures()


func _reset_gestures() -> void:
	_touches.clear()
	_primary = -1
	_secondary = -1
	_primary_travel = 0.0
	_secondary_travel = 0.0
	_dragging = false
	_scrolling = false
	_scroll_accum = 0.0
	_mouse_accum = Vector2.ZERO


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_touch(99, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_drag(event.index, event.position)
	elif event is InputEventMouseMotion and _touches.has(99):
		_drag(99, event.position)
	accept_event()


func _touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		_touches[index] = pos
		if _touches.size() == 1:
			_primary = index
			_primary_time = Time.get_ticks_msec() / 1000.0
			_primary_travel = 0.0
			_dragging = false
			_scrolling = false
		elif _touches.size() == 2:
			_secondary = index
			_secondary_travel = 0.0
	else:
		if _touches.size() == 2 and not _scrolling and not _dragging:
			var elapsed := Time.get_ticks_msec() / 1000.0 - _primary_time
			if _primary_travel <= tap_max_travel and _secondary_travel <= tap_max_travel and elapsed <= tap_max_seconds:
				_send_right_click()
		elif index == _primary and not _dragging and not _scrolling and _touches.size() == 1:
			var elapsed := Time.get_ticks_msec() / 1000.0 - _primary_time
			if _primary_travel <= tap_max_travel and elapsed <= tap_max_seconds:
				_send_left_click()

		_touches.erase(index)
		if _touches.is_empty():
			_reset_gestures()


func _drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	var delta: Vector2 = pos - _touches[index]
	if delta.length() < jitter_deadzone:
		return
	_touches[index] = pos

	if _touches.size() >= 2:
		_secondary_travel += delta.length()
		if _secondary_travel > tap_max_travel:
			_scrolling = true
		_scroll_accum += -delta.y * scroll_sensitivity
		var steps := int(_scroll_accum)
		if steps != 0:
			var client := _get_client()
			if client:
				client.send_scroll(steps, 0)
			_scroll_accum -= steps
		return

	if index != _primary:
		return

	_primary_travel += delta.length()
	if not _dragging and _primary_travel > tap_max_travel:
		_dragging = true

	if _dragging:
		_mouse_accum += delta * sensitivity
		var mx := int(_mouse_accum.x)
		var my := int(_mouse_accum.y)
		if mx != 0 or my != 0:
			var client := _get_client()
			if client:
				client.send_mouse_move(mx, my)
			_mouse_accum -= Vector2(mx, my)


func _send_left_click() -> void:
	Input.vibrate_handheld(12)
	var client := _get_client()
	if client:
		client.send_mouse_button(0x110, true)
		client.send_mouse_button(0x110, false)


func _send_right_click() -> void:
	Input.vibrate_handheld(16)
	var client := _get_client()
	if client:
		client.send_mouse_button(0x111, true)
		client.send_mouse_button(0x111, false)
