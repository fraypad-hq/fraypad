extends Control
class_name FraypadTrackpad

## A trackpad surface: drag to move the cursor, tap to left-click, two-finger
## tap to right-click, two-finger drag to scroll.
##
## Movement is sent as relative deltas, so the cursor keeps moving from
## wherever it is — that's what makes this feel like a real laptop trackpad
## instead of an absolute "tap where you want the pointer" surface.

## Cursor units sent per screen pixel of finger travel.
@export var sensitivity: float = 1.0
## Scroll clicks sent per pixel of two-finger travel.
@export var scroll_sensitivity: float = 0.02
## A press-release under these bounds is a tap, not a drag.
@export var tap_max_travel: float = 12.0
@export var tap_max_seconds: float = 0.25

var _client: FraypadClient

## Touches currently on the surface: index -> last global position.
var _touches: Dictionary = {}
## The first finger's press, used to decide tap vs drag.
var _primary: int = -1
var _primary_start: Vector2 = Vector2.ZERO
var _primary_time: float = 0.0
var _primary_travel: float = 0.0
## Set once the primary finger has moved enough to be a drag rather than a tap.
var _dragging: bool = false
## Set when the gesture became a two-finger one, so lifting doesn't click.
var _multi: bool = false


func _ready() -> void:
	custom_minimum_size = Vector2(320, 200)
	_client = get_tree().get_first_node_in_group("fraypad_client") as FraypadClient


## Backgrounding the app cancels the touch stream; forget every finger so a
## stale press can't be mistaken for a held click later.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		_touches.clear()
		_primary = -1
		_dragging = false
		_multi = false


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
		if _touches.is_empty():
			_primary = index
			_primary_start = pos
			_primary_time = Time.get_ticks_msec() / 1000.0
			_primary_travel = 0.0
			_dragging = false
			_multi = false
		elif index != _primary:
			# A second finger turns this into a scroll gesture.
			_multi = true
		_touches[index] = pos
	else:
		if index == _primary and not _dragging and not _multi:
			_maybe_tap(pos)
		_touches.erase(index)
		if index == _primary:
			_primary = -1
			_dragging = false
			_multi = false


func _drag(index: int, pos: Vector2) -> void:
	if not _touches.has(index):
		return
	# Delta since this finger's previous position, in screen pixels.
	var delta: Vector2 = pos - _touches[index]
	_touches[index] = pos

	if _touches.size() >= 2:
		# Two fingers scroll: vertical finger travel becomes wheel clicks.
		if _client:
			# Wheel positive is up, so invert the screen-space Y delta.
			_client.send_scroll(int(-delta.y * scroll_sensitivity), 0)
		return

	if index != _primary:
		return

	_primary_travel += delta.length()
	if not _dragging and _primary_travel > tap_max_travel:
		_dragging = true
	if _dragging and _client:
		_client.send_mouse_move(int(delta.x * sensitivity), int(delta.y * sensitivity))


## A quick, near-stationary press-release is a tap. With one finger it is a
## left click; the caller maps two-finger taps to right click before we get
## here (a two-finger gesture never reaches this path).
func _maybe_tap(_pos: Vector2) -> void:
	var elapsed := Time.get_ticks_msec() / 1000.0 - _primary_time
	if _primary_travel <= tap_max_travel and elapsed <= tap_max_seconds and _client:
		_client.send_mouse_button(0x110, true)
		_client.send_mouse_button(0x110, false)
