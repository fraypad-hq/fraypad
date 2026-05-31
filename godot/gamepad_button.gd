extends Button
class_name GamepadButton

enum Action {
	NONE,
	DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
	FACE_A, FACE_B, FACE_X, FACE_Y,
	BUMPER_LEFT, BUMPER_RIGHT,
	TRIGGER_LEFT, TRIGGER_RIGHT,
	BACK, START, XBOX
}

@export var action: Action = Action.NONE
@export var overlap_margin: float = 18.0

var _client: FraypadClient
var _left_stick: VirtualJoystick
var _right_stick: VirtualJoystick

# Maps touch_index -> bool (is this finger currently inside this button?)
var _fingers: Dictionary = {}
var _is_active: bool = false

# Sentinel for mouse input on desktop
const MOUSE_TOUCH_INDEX = 99

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_client = get_tree().root.find_child("FraypadClient", true, false)
	_left_stick = get_tree().root.find_child("LeftStick", true, false)
	_right_stick = get_tree().root.find_child("RightStick", true, false)
	
	# Register D-pad buttons into groups for axis conflict resolution
	match action:
		Action.DPAD_UP, Action.DPAD_DOWN:
			add_to_group("dpad_y")
		Action.DPAD_LEFT, Action.DPAD_RIGHT:
			add_to_group("dpad_x")

func _is_joystick_finger(index: int) -> bool:
	if _left_stick and _left_stick._touch_index == index:
		return true
	if _right_stick and _right_stick._touch_index == index:
		return true
	return false

func _input(event: InputEvent) -> void:
	var index: int = -1
	var global_pos: Vector2
	var is_touch_event: bool = false

	if event is InputEventScreenTouch:
		index = event.index
		global_pos = event.position
		is_touch_event = true
		if _is_joystick_finger(index):
			return
		_fingers[index] = get_global_rect().grow(overlap_margin).has_point(global_pos) and event.pressed
		if not event.pressed:
			_fingers.erase(index)

	elif event is InputEventScreenDrag:
		index = event.index
		global_pos = event.position
		is_touch_event = true
		if _is_joystick_finger(index):
			if _fingers.has(index):
				_fingers.erase(index)
			else:
				return
		else:
			_fingers[index] = get_global_rect().grow(overlap_margin).has_point(global_pos)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		index = MOUSE_TOUCH_INDEX
		global_pos = event.global_position
		is_touch_event = true
		_fingers[index] = get_global_rect().grow(overlap_margin).has_point(global_pos) and event.pressed
		if not event.pressed:
			_fingers.erase(index)

	elif event is InputEventMouseMotion:
		if not _fingers.has(MOUSE_TOUCH_INDEX):
			return
		global_pos = event.global_position
		is_touch_event = true
		_fingers[MOUSE_TOUCH_INDEX] = get_global_rect().grow(overlap_margin).has_point(global_pos)

	if not is_touch_event:
		return

	# Recompute active state — pressed if any finger is inside
	var now_active: bool = false
	for inside in _fingers.values():
		if inside:
			now_active = true
			break

	# Only send on transitions
	if now_active != _is_active:
		_is_active = now_active
		_update_visual()
		_send_dpad_aware(_is_active)

func _update_visual() -> void:
	modulate = Color(0.55, 0.55, 0.55) if _is_active else Color.WHITE

func _send_dpad_aware(p_pressed: bool) -> void:
	match action:
		Action.DPAD_UP, Action.DPAD_DOWN:
			if p_pressed:
				_client.send_dpad_y(-1 if action == Action.DPAD_UP else 1)
			else:
				var dominated := false
				for btn in get_tree().get_nodes_in_group("dpad_y"):
					if btn != self and btn._is_active:
						dominated = true
						break
				if not dominated:
					_client.send_dpad_y(0)
		Action.DPAD_LEFT, Action.DPAD_RIGHT:
			if p_pressed:
				_client.send_dpad_x(-1 if action == Action.DPAD_LEFT else 1)
			else:
				var dominated := false
				for btn in get_tree().get_nodes_in_group("dpad_x"):
					if btn != self and btn._is_active:
						dominated = true
						break
				if not dominated:
					_client.send_dpad_x(0)
		_:
			_send(p_pressed)

func _send(p_pressed: bool) -> void:
	match action:
		Action.FACE_A:        _client.send_button(0x130, p_pressed)
		Action.FACE_B:        _client.send_button(0x131, p_pressed)
		Action.FACE_X:        _client.send_button(0x134, p_pressed)
		Action.FACE_Y:        _client.send_button(0x133, p_pressed)
		
		Action.BUMPER_LEFT:   _client.send_button(0x136, p_pressed)
		Action.BUMPER_RIGHT:  _client.send_button(0x137, p_pressed)
		
		Action.TRIGGER_LEFT:  _client.send_trigger_left(1.0 if p_pressed else 0.0)
		Action.TRIGGER_RIGHT: _client.send_trigger_right(1.0 if p_pressed else 0.0)
		
		Action.BACK:          _client.send_button(0x13A, p_pressed)
		Action.START:         _client.send_button(0x13B, p_pressed)
		Action.XBOX:          _client.send_button(0x13C, p_pressed)
