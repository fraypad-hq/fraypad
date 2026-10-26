extends Control
class_name FraypadKeyboard

const ROWS := [
	[["1", 2], ["2", 3], ["3", 4], ["4", 5], ["5", 6], ["6", 7], ["7", 8],
	 ["8", 9], ["9", 10], ["0", 11], ["-", 12], ["=", 13], ["Bksp", 14]],
	[["Tab", 15], ["Q", 16], ["W", 17], ["E", 18], ["R", 19], ["T", 20],
	 ["Y", 21], ["U", 22], ["I", 23], ["O", 24], ["P", 25], ["[", 26], ["]", 27]],
	[["Esc", 1], ["A", 30], ["S", 31], ["D", 32], ["F", 33], ["G", 34],
	 ["H", 35], ["J", 36], ["K", 37], ["L", 38], [";", 39], ["'", 40],
	 ["\\", 43], ["Enter", 28]],
	[["Shift", 42], ["Z", 44], ["X", 45], ["C", 46], ["V", 47], ["B", 48],
	 ["N", 49], ["M", 50], [",", 51], [".", 52], ["/", 53], ["Shift", 54]],
	[["Ctrl", 29], ["Alt", 56], ["Space", 57], ["Left", 105], ["Up", 103],
	 ["Down", 108], ["Right", 106]],
]

const WIDE := {
	"Bksp": 1.5, "Tab": 1.25, "\\": 1.2, "Enter": 1.8, "Shift": 1.4,
	"Ctrl": 1.4, "Alt": 1.2, "Space": 4.5, "Esc": 1.0,
}

var _client: FraypadClient
var _touch_keys: Dictionary = {}
var _key_refcount: Dictionary = {}
var _key_rects: Array = []


func _ready() -> void:
	resized.connect(_rebuild_layout)
	_rebuild_layout()


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
		_release_all()


func _release_all() -> void:
	for code in _key_refcount.keys():
		_send(code, false)
	_touch_keys.clear()
	_key_refcount.clear()
	queue_redraw()


func _rebuild_layout() -> void:
	_key_rects.clear()
	var row_count := ROWS.size()
	if row_count == 0 or size.y <= 0:
		return

	var gap := 4.0
	var total_gap_y := gap * (row_count - 1)
	var row_h := maxf((size.y - total_gap_y) / row_count, 10.0)

	for r in range(row_count):
		var row: Array = ROWS[r]
		var total_units := 0.0
		for entry in row:
			total_units += WIDE.get(entry[0], 1.0)

		var total_gap_x := gap * (row.size() - 1)
		var avail_w := maxf(size.x - total_gap_x, 10.0)
		var unit_w := avail_w / total_units

		var x := 0.0
		var y := r * (row_h + gap)
		for entry in row:
			var label: String = entry[0]
			var code: int = entry[1]
			var w: float = unit_w * WIDE.get(label, 1.0)
			_key_rects.append({
				"rect": Rect2(x, y, w, row_h),
				"label": label,
				"code": code,
			})
			x += w + gap

	queue_redraw()


func _draw() -> void:
	var font := ThemeDB.fallback_font
	var normal_bg := Color(0.09, 0.10, 0.14, 0.94)
	var pressed_bg := Color(0.10, 0.60, 0.30, 0.95)
	var border_color := Color(0.24, 0.28, 0.36, 0.8)

	for item in _key_rects:
		var r: Rect2 = item["rect"]
		var code: int = item["code"]
		var is_pressed: bool = int(_key_refcount.get(code, 0)) > 0
		var bg: Color = pressed_bg if is_pressed else normal_bg

		draw_rect(r, bg, true)
		draw_rect(r, border_color, false, 1.5)

		var label: String = item["label"]
		var font_size := int(clampf(r.size.y * 0.38, 12.0, 22.0))
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size)
		var text_pos := Vector2(r.position.x + (r.size.x - ts.x) * 0.5, r.position.y + (r.size.y + ts.y * 0.6) * 0.5)
		draw_string(font, text_pos, label, HORIZONTAL_ALIGNMENT_CENTER, -1, font_size, Color.WHITE)


func _key_at(pos: Vector2) -> Dictionary:
	for item in _key_rects:
		if (item["rect"] as Rect2).has_point(pos):
			return item
	return {}


func _gui_input(event: InputEvent) -> void:
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(99, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseMotion and _touch_keys.has(99):
		_handle_drag(99, event.position)
	accept_event()


func _handle_touch(index: int, pos: Vector2, pressed: bool) -> void:
	if pressed:
		var key := _key_at(pos)
		if not key.is_empty():
			var code: int = key["code"]
			_touch_keys[index] = code
			_press_key(code)
	else:
		if _touch_keys.has(index):
			var code: int = _touch_keys[index]
			_touch_keys.erase(index)
			_release_key(code)


func _handle_drag(index: int, pos: Vector2) -> void:
	if not _touch_keys.has(index):
		return
	var current_code: int = _touch_keys[index]
	var key := _key_at(pos)
	var new_code: int = key.get("code", -1)
	if new_code != current_code:
		_release_key(current_code)
		if new_code != -1:
			_touch_keys[index] = new_code
			_press_key(new_code)
		else:
			_touch_keys.erase(index)


func _press_key(code: int) -> void:
	var count: int = _key_refcount.get(code, 0)
	_key_refcount[code] = count + 1
	if count == 0:
		Input.vibrate_handheld(8)
		_send(code, true)
		queue_redraw()


func _release_key(code: int) -> void:
	var count: int = _key_refcount.get(code, 0)
	if count <= 1:
		_key_refcount.erase(code)
		_send(code, false)
		queue_redraw()
	else:
		_key_refcount[code] = count - 1


func _send(code: int, pressed: bool) -> void:
	var client := _get_client()
	if client:
		client.send_key(code, pressed)
