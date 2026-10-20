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
var _left_stick: FraypadStick
var _right_stick: FraypadStick

# Maps touch_index -> bool (is this finger currently inside this button?)
var _fingers: Dictionary = {}
# Maps touch_index -> Vector2 where that finger first went down. Used to tell
# whether a finger began on a stick (and so belongs to the stick, not us).
var _press_origin: Dictionary = {}
var _is_active: bool = false

# Sentinel for mouse input on desktop
const MOUSE_TOUCH_INDEX = 99

func _ready() -> void:
	focus_mode = Control.FOCUS_NONE
	# Resolve siblings by unique name; the whole tree lookup would also match
	# unrelated nodes if the scene ever grew a second client or stick.
	_left_stick = get_node_or_null("%LeftStick") as FraypadStick
	_right_stick = get_node_or_null("%RightStick") as FraypadStick

	# The client is looked up lazily (see `_get_client`) rather than here: the
	# GDExtension class can still be unregistered while this node readies, and
	# the `as FraypadClient` cast would quietly yield null for the whole run.

	# Register D-pad buttons into groups for axis conflict resolution
	match action:
		Action.DPAD_UP, Action.DPAD_DOWN:
			add_to_group("dpad_y")
		Action.DPAD_LEFT, Action.DPAD_RIGHT:
			add_to_group("dpad_x")

## Backgrounding the app cancels every touch stream, so drop all fingers and
## release the button. Without this a key held when the user switches away
## stays pressed on the PC forever (the release touch never arrives).
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		if _fingers.is_empty():
			return
		_fingers.clear()
		_press_origin.clear()
		if _is_active:
			_is_active = false
			_update_visual()
			_send_dpad_aware(false)

## The signal client, fetched on first use and cached.
##
## Resolving it in `_ready` proved unreliable on Android: the GDExtension class
## isn't always registered while sibling nodes are readying, so the cast
## returned null and every send logged "cannot call method on a null value"
## for the rest of the session. Looking it up when the first input arrives
## sidesteps the ordering entirely.
func _get_client() -> FraypadClient:
	if _client == null:
		# Look the node up by path rather than by group. The group lookup
		# returned null on Android: the client is a GDExtension node, and its
		# scene-declared group membership is not visible while the rest of the
		# scene readies, so every button silently sent nothing. The path is
		# fixed by the scene, so resolve it from the root we belong to.
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

## Whether a touch landed inside either stick's interactive area.
##
## `_input()` runs before the stick's `_gui_input()` claims a finger, so on
## the very first frame of a touch `_touch_index` is still unset. Checking the
## geometry closes that race, which otherwise made grabbing the right stick
## fire a spurious face-button press.
func _is_over_stick(pos: Vector2) -> bool:
	for stick in [_left_stick, _right_stick]:
		if stick and stick.get_global_rect().has_point(pos):
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
		# A fresh touch inside a stick belongs to the stick, not to us.
		if event.pressed and _is_over_stick(global_pos):
			return
		if event.pressed:
			# Remember where this finger went down. A finger that starts on a
			# stick is excluded above; every other finger is a candidate for
			# slide-to-type, so it is tracked even when it goes down on empty
			# space (that is how a swipe *onto* a button starts).
			_press_origin[index] = global_pos
			_fingers[index] = get_global_rect().has_point(global_pos)
		else:
			_fingers.erase(index)
			_press_origin.erase(index)

	elif event is InputEventScreenDrag:
		index = event.index
		global_pos = event.position
		is_touch_event = true
		# A finger holding a stick is a stick finger: it must never light up a
		# button it happens to slide across, and if it somehow pressed here
		# before grabbing the stick, drop it.
		if _is_joystick_finger(index):
			if _fingers.has(index):
				_fingers.erase(index)
			else:
				return
		elif _is_over_stick(_press_origin.get(index, global_pos)):
			# The finger started on a stick (the stick claims it a frame later,
			# so `_is_joystick_finger` can lag) — leave it to the stick.
			return
		else:
			# Slide-to-type: a free finger presses whatever button it is over
			# right now, so dragging across A -> B -> A -> B types them in turn.
			# The rect is only grown by a hair; a bigger band would light up
			# flush neighbours as the finger crosses the seam between them.
			if not _fingers.has(index):
				return
			_fingers[index] = get_global_rect().grow(overlap_margin).has_point(global_pos)

	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		index = MOUSE_TOUCH_INDEX
		global_pos = event.global_position
		is_touch_event = true
		if event.pressed:
			_press_origin[index] = global_pos
			_fingers[index] = get_global_rect().has_point(global_pos)
		else:
			_fingers.erase(index)
			_press_origin.erase(index)

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

## Dim the button slightly while it is held. The base colour comes from the
## scene (Xbox face buttons are tinted), so this multiplies rather than
## replaces; the pressed tint stays a visible shift for every base colour.
##
## Modulate components stay inside 0..1: values above 1 ask the renderer for an
## overbright/HDR blend, which the GL Compatibility backend handles differently
## from the desktop Vulkan renderer.
func _update_visual() -> void:
	modulate = Color(0.55, 0.6, 0.7) if _is_active else Color.WHITE

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

## Value to send when `self` releases one end of a d-pad axis: whichever end
## is still held keeps its direction, otherwise neutral (0). Sending 0 only
## when *nothing* is held stops a release from leaving the hat stuck on the
## direction the dying press overwrote.
func _surviving_direction(group: String, neg_action: Action, pos_action: Action) -> int:
	for node in get_tree().get_nodes_in_group(group):
		# Only siblings of the same kind can express a direction; a stray node
		# in the group (or one mid-teardown) must not be read as a button.
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
		Action.FACE_X:        client.send_button(0x133, p_pressed)
		Action.FACE_Y:        client.send_button(0x134, p_pressed)
		
		Action.BUMPER_LEFT:   client.send_button(0x136, p_pressed)
		Action.BUMPER_RIGHT:  client.send_button(0x137, p_pressed)
		
		Action.TRIGGER_LEFT:  client.send_trigger_left(1.0 if p_pressed else 0.0)
		Action.TRIGGER_RIGHT: client.send_trigger_right(1.0 if p_pressed else 0.0)
		
		Action.BACK:          client.send_button(0x13A, p_pressed)
		Action.START:         client.send_button(0x13B, p_pressed)
		Action.XBOX:          client.send_button(0x13C, p_pressed)
