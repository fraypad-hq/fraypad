extends Button
class_name GamepadButton

enum Action {
	NONE,
	DPAD_UP, DPAD_DOWN, DPAD_LEFT, DPAD_RIGHT,
	FACE_A, FACE_B, FACE_X, FACE_Y,
	BUMPER_LEFT, BUMPER_RIGHT,
	TRIGGER_LEFT, TRIGGER_RIGHT,
	BACK, START, XBOX,
	THUMB_LEFT, THUMB_RIGHT
}

@export var action: Action = Action.NONE
@export var overlap_margin: float = 8.0

var _client: FraypadClient
var _left_stick: FraypadStick
var _right_stick: FraypadStick

var _fingers: Dictionary = {}
var _press_origin: Dictionary = {}
var _is_active: bool = false
var trigger_value: float = 0.0

const MOUSE_TOUCH_INDEX = 99

const COLOR_FACE_A := Color(0.12, 0.82, 0.38)
const COLOR_FACE_B := Color(0.92, 0.22, 0.24)
const COLOR_FACE_X := Color(0.20, 0.65, 0.98)
const COLOR_FACE_Y := Color(0.98, 0.78, 0.12)
const COLOR_XBOX   := Color(0.25, 0.85, 0.45)
const COLOR_TRIGGER := Color(0.06, 0.65, 0.32)


func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	_left_stick = get_node_or_null("%LeftStick") as FraypadStick
	_right_stick = get_node_or_null("%RightStick") as FraypadStick
	resized.connect(_on_resized)
	_on_resized()

	match action:
		Action.DPAD_UP, Action.DPAD_DOWN:
			add_to_group("dpad_y")
		Action.DPAD_LEFT, Action.DPAD_RIGHT:
			add_to_group("dpad_x")
		Action.TRIGGER_LEFT, Action.TRIGGER_RIGHT:
			add_to_group("triggers")
		Action.FACE_A:
			_apply_face_style(COLOR_FACE_A)
		Action.FACE_B:
			_apply_face_style(COLOR_FACE_B)
		Action.FACE_X:
			_apply_face_style(COLOR_FACE_X)
		Action.FACE_Y:
			_apply_face_style(COLOR_FACE_Y)
		Action.XBOX:
			add_theme_color_override("font_color", COLOR_XBOX)
			add_theme_color_override("font_pressed_color", Color.WHITE)


func _on_resized() -> void:
	pivot_offset = size * 0.5


func _apply_face_style(accent: Color) -> void:
	add_theme_color_override("font_color", accent)
	add_theme_color_override("font_pressed_color", Color.WHITE)
	add_theme_color_override("font_hover_color", accent.lightened(0.2))

	var normal := StyleBoxFlat.new()
	normal.bg_color = Color(0.09, 0.10, 0.13, 0.94)
	normal.border_color = Color(accent.r, accent.g, accent.b, 0.35)
	normal.set_border_width_all(2)
	normal.set_corner_radius_all(999)
	add_theme_stylebox_override("normal", normal)

	var pressed := StyleBoxFlat.new()
	pressed.bg_color = Color(accent.r * 0.25, accent.g * 0.25, accent.b * 0.25, 0.98)
	pressed.border_color = accent
	pressed.set_border_width_all(3)
	pressed.set_corner_radius_all(999)
	add_theme_stylebox_override("pressed", pressed)


func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		release()


func release() -> void:
	_fingers.clear()
	_press_origin.clear()
	if _is_active:
		_is_active = false
		trigger_value = 0.0
		_update_visual()
		_send_dpad_aware(false)
		queue_redraw()


func _draw() -> void:
	if _is_trigger() and trigger_value > 0.0:
		var fill_h := size.y * trigger_value
		var fill_r := Rect2(2.0, size.y - fill_h, size.x - 4.0, fill_h - 2.0)
		draw_rect(fill_r, Color(COLOR_TRIGGER.r, COLOR_TRIGGER.g, COLOR_TRIGGER.b, 0.45), true)
		draw_rect(fill_r, Color(COLOR_TRIGGER.r, COLOR_TRIGGER.g, COLOR_TRIGGER.b, 0.85), false, 1.5)
		if trigger_value >= 0.05:
			var font := get_theme_font("font")
			var pct_text := "%d%%" % int(trigger_value * 100.0)
			var font_size := maxi(11, int(size.y * 0.18))
			var text_w := font.get_string_size(pct_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size).x
			var text_pos := Vector2((size.x - text_w) * 0.5, size.y - 8.0)
			draw_string(font, text_pos, pct_text, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color(0.9, 0.95, 1.0, 0.85))


func _get_client() -> FraypadClient:
	if _client == null:
		var root: Node = get_tree().current_scene
		if root == null:
			root = owner
		if root:
			_client = root.get_node_or_null("FraypadClient") as FraypadClient
	return _client


func _is_joystick_finger(index: int) -> bool:
	if _left_stick and _left_stick._touch_index == index:
		return true
	if _right_stick and _right_stick._touch_index == index:
		return true
	return false


func _is_over_stick(pos: Vector2) -> bool:
	for stick in [_left_stick, _right_stick]:
		if stick and stick.is_visible_in_tree() and stick.get_global_rect().has_point(pos):
			return true
	return false


func _is_trigger() -> bool:
	return action == Action.TRIGGER_LEFT or action == Action.TRIGGER_RIGHT


func _is_trigger_finger(index: int) -> bool:
	var tree := get_tree()
	if tree == null:
		return false
	for node in tree.get_nodes_in_group("triggers"):
		if node is GamepadButton and (node as GamepadButton)._press_origin.has(index):
			return true
	return false


func _calculate_trigger_pull(index: int, pos: Vector2) -> float:
	var origin: Vector2 = _press_origin.get(index, pos)
	var drag_down: float = pos.y - origin.y
	var max_travel: float = maxf(size.y * 2.2, 150.0)
	return clampf(drag_down / max_travel, 0.0, 1.0)


func _input(event: InputEvent) -> void:
	if not is_visible_in_tree():
		if not _fingers.is_empty() or _is_active:
			release()
		return

	var index: int = -1
	var global_pos: Vector2
	var is_touch_event: bool = false

	if event is InputEventScreenTouch:
		index = event.index
		global_pos = event.position
		is_touch_event = true
		if _is_joystick_finger(index):
			return
		if event.pressed:
			if _is_over_stick(global_pos):
				return
			if _is_trigger():
				if not get_global_rect().has_point(global_pos):
					return
				_press_origin[index] = global_pos
				_fingers[index] = true
				trigger_value = 0.0
				_send_trigger(0.0)
				queue_redraw()
			else:
				if _is_trigger_finger(index):
					return
				if get_global_rect().grow(overlap_margin).has_point(global_pos):
					_fingers[index] = true
				else:
					_fingers.erase(index)
		else:
			if _is_trigger():
				if not _press_origin.has(index):
					return
				_fingers.erase(index)
				_press_origin.erase(index)
				if _fingers.is_empty():
					trigger_value = 0.0
					_send_trigger(0.0)
					queue_redraw()
			else:
				_fingers.erase(index)

	elif event is InputEventScreenDrag:
		index = event.index
		global_pos = event.position
		is_touch_event = true
		if _is_joystick_finger(index):
			_fingers.erase(index)
			_press_origin.erase(index)
			return
		if _is_trigger():
			if not _press_origin.has(index):
				return
			trigger_value = _calculate_trigger_pull(index, global_pos)
			_send_trigger(trigger_value)
			queue_redraw()
		else:
			if _is_trigger_finger(index):
				return
			if _is_over_stick(global_pos):
				_fingers.erase(index)
			else:
				var inside := get_global_rect().grow(overlap_margin).has_point(global_pos)
				if inside:
					_fingers[index] = true
				else:
					_fingers.erase(index)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		index = MOUSE_TOUCH_INDEX
		global_pos = event.global_position
		is_touch_event = true
		if _is_joystick_finger(index):
			return
		if event.pressed:
			if _is_over_stick(global_pos):
				return
			if _is_trigger():
				if not get_global_rect().has_point(global_pos):
					return
				_press_origin[index] = global_pos
				_fingers[index] = true
				trigger_value = 0.0
				_send_trigger(0.0)
				queue_redraw()
			else:
				if _is_trigger_finger(index):
					return
				if get_global_rect().grow(overlap_margin).has_point(global_pos):
					_fingers[index] = true
				else:
					_fingers.erase(index)
		else:
			if _is_trigger():
				if not _press_origin.has(index):
					return
				_fingers.erase(index)
				_press_origin.erase(index)
				if _fingers.is_empty():
					trigger_value = 0.0
					_send_trigger(0.0)
					queue_redraw()
			else:
				_fingers.erase(index)

	elif event is InputEventMouseMotion:
		index = MOUSE_TOUCH_INDEX
		global_pos = event.global_position
		is_touch_event = true
		if _is_trigger():
			if not _press_origin.has(index):
				return
			trigger_value = _calculate_trigger_pull(MOUSE_TOUCH_INDEX, global_pos)
			_send_trigger(trigger_value)
			queue_redraw()
		else:
			if _is_trigger_finger(index):
				return
			if _is_over_stick(global_pos):
				_fingers.erase(index)
			else:
				var inside := get_global_rect().grow(overlap_margin).has_point(global_pos)
				if inside:
					_fingers[index] = true
				else:
					_fingers.erase(index)

	if not is_touch_event:
		return

	var now_active: bool = false
	for inside in _fingers.values():
		if inside:
			now_active = true
			break

	if now_active != _is_active:
		if now_active:
			Input.vibrate_handheld(12)
		_is_active = now_active
		_update_visual()
		_send_dpad_aware(_is_active)


func _update_visual() -> void:
	if _is_active:
		scale = Vector2(0.93, 0.93)
		modulate = Color(1.15, 1.15, 1.2)
	else:
		scale = Vector2.ONE
		modulate = Color.WHITE


func _send_trigger(val: float) -> void:
	var client := _get_client()
	if client == null:
		return
	if action == Action.TRIGGER_LEFT:
		client.send_trigger_left(val)
	elif action == Action.TRIGGER_RIGHT:
		client.send_trigger_right(val)


func _send_dpad_aware(p_pressed: bool) -> void:
	var client := _get_client()
	if client == null:
		return
	match action:
		Action.DPAD_UP, Action.DPAD_DOWN:
			if p_pressed:
				client.send_dpad_y(-1 if action == Action.DPAD_UP else 1)
			else:
				client.send_dpad_y(_surviving_direction("dpad_y", Action.DPAD_UP, Action.DPAD_DOWN))
		Action.DPAD_LEFT, Action.DPAD_RIGHT:
			if p_pressed:
				client.send_dpad_x(-1 if action == Action.DPAD_LEFT else 1)
			else:
				client.send_dpad_x(_surviving_direction("dpad_x", Action.DPAD_LEFT, Action.DPAD_RIGHT))
		_:
			_send(p_pressed)


func _surviving_direction(group: String, neg_action: Action, _pos_action: Action) -> int:
	for node in get_tree().get_nodes_in_group(group):
		if node is GamepadButton and node != self and node._is_active:
			return -1 if node.action == neg_action else 1
	return 0


func _send(p_pressed: bool) -> void:
	var client := _get_client()
	if client == null:
		return
	match action:
		Action.FACE_A:        client.send_button(0x130, p_pressed)
		Action.FACE_B:        client.send_button(0x131, p_pressed)
		Action.FACE_X:        client.send_button(0x134, p_pressed)
		Action.FACE_Y:        client.send_button(0x133, p_pressed)
		Action.BUMPER_LEFT:   client.send_button(0x136, p_pressed)
		Action.BUMPER_RIGHT:  client.send_button(0x137, p_pressed)
		Action.TRIGGER_LEFT:  _send_trigger(trigger_value if p_pressed else 0.0)
		Action.TRIGGER_RIGHT: _send_trigger(trigger_value if p_pressed else 0.0)
		Action.BACK:          client.send_button(0x13A, p_pressed)
		Action.START:         client.send_button(0x13B, p_pressed)
		Action.XBOX:          client.send_button(0x13C, p_pressed)
		Action.THUMB_LEFT:    client.send_thumb_left(p_pressed)
		Action.THUMB_RIGHT:   client.send_thumb_right(p_pressed)
