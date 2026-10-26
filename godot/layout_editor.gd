extends Control

class_name LayoutUnit

var key: String = ""
var label: String = ""
var centre: Vector2 = Vector2.ZERO
var design: float = 0.2
var size_scale: float = 1.0
var half: Vector2 = Vector2(80, 80)
var min_scale: float = 0.6
var max_scale: float = 1.8

var _canvas: Vector2 = Vector2(1, 1)

func _init(p_key: String = "", p_label: String = "") -> void:
	key = p_key
	label = p_label


func set_canvas(canvas: Vector2) -> void:
	_canvas = canvas


func pixel_centre() -> Vector2:
	return Vector2(centre.x * _canvas.x, centre.y * _canvas.y)


func set_pixel_centre(p_pixels: Vector2) -> void:
	if _canvas.x > 0 and _canvas.y > 0:
		centre = Vector2(p_pixels.x / _canvas.x, p_pixels.y / _canvas.y)


func pixel_size(h: float) -> float:
	return design * h * size_scale


func handle_rect() -> Rect2:
	var ext := half * size_scale
	return Rect2(pixel_centre() - ext, ext * 2.0)


signal changed()

var _units: Array[LayoutUnit] = []
var _drag_index: Dictionary = {}
var _drag_grab: Dictionary = {}

var _pinch_unit: LayoutUnit = null
var _pinch_a: int = -1
var _pinch_b: int = -1
var _pinch_start_span: float = 0.0
var _pinch_start_scale: float = 1.0
var _finger_a: Vector2 = Vector2.ZERO
var _finger_b: Vector2 = Vector2.ZERO
var _finger_a_known: bool = false
var _finger_b_known: bool = false

const LABEL_SIZE := 20


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


func set_units(units: Array) -> void:
	_units.clear()
	for u in units:
		_units.append(u)
	queue_redraw()


func _draw() -> void:
	if not visible:
		return
	var font := ThemeDB.fallback_font
	for u in _units:
		var r := u.handle_rect()
		draw_rect(r, Color(0.10, 0.65, 0.35, 0.12), true)
		draw_rect(r, Color(0.12, 0.82, 0.40, 0.85), false, 2.0)

		var label_str := "%s  %.2fx" % [u.label if u.label != "" else u.key, u.size_scale]
		var ts := font.get_string_size(label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var tp := r.position + Vector2(10, ts.y + 8)

		draw_rect(Rect2(tp + Vector2(-6, -ts.y - 2), ts + Vector2(12, 8)), Color(0.08, 0.09, 0.12, 0.92), true)
		draw_rect(Rect2(tp + Vector2(-6, -ts.y - 2), ts + Vector2(12, 8)), Color(0.12, 0.82, 0.40, 0.6), false, 1.0)
		draw_string(font, tp, label_str, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE, Color(0.92, 0.95, 1.0))


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	var slots := get_node_or_null("%LayoutSlotsPanel") as Control
	if slots and slots.visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event.index, event.position, event.pressed)
	elif event is InputEventMouseButton and event.button_index == MOUSE_BUTTON_LEFT:
		_handle_touch(99, event.position, event.pressed)
	elif event is InputEventScreenDrag:
		_handle_drag(event.index, event.position)
	elif event is InputEventMouseMotion and _drag_index.has(99):
		_handle_drag(99, event.position)
	accept_event()


func _handle_touch(idx: int, pos: Vector2, pressed: bool) -> void:
	if not pressed:
		_drag_index.erase(idx)
		_drag_grab.erase(idx)
		if idx == _pinch_a or idx == _pinch_b:
			_end_pinch()
		return

	if _pinch_unit == null and _drag_index.size() == 1:
		var other: int = _drag_index.keys()[0]
		var held_unit: LayoutUnit = _drag_index[other]
		if held_unit == _unit_at(pos):
			_start_pinch(held_unit, other, idx, pos)
			return

	var hit := _unit_at(pos)
	if hit == null:
		return
	_drag_index[idx] = hit
	_drag_grab[idx] = pos - hit.pixel_centre()


func _unit_at(pos: Vector2) -> LayoutUnit:
	var best: LayoutUnit = null
	var best_area := INF
	for u in _units:
		var r := u.handle_rect()
		if not r.has_point(pos):
			continue
		var area := r.size.x * r.size.y
		if area < best_area:
			best_area = area
			best = u
	return best


func _start_pinch(u: LayoutUnit, hold_idx: int, new_idx: int, new_pos: Vector2) -> void:
	_pinch_unit = u
	_pinch_a = hold_idx
	_pinch_b = new_idx
	_finger_a = u.pixel_centre() + _drag_grab.get(hold_idx, Vector2.ZERO)
	_finger_a_known = true
	_finger_b = new_pos
	_finger_b_known = true
	_pinch_start_span = maxf(_finger_a.distance_to(_finger_b), 1.0)
	_pinch_start_scale = u.size_scale
	_drag_index.clear()
	_drag_grab.clear()


func _end_pinch() -> void:
	_pinch_unit = null
	_pinch_a = -1
	_pinch_b = -1
	_finger_a_known = false
	_finger_b_known = false


func _handle_drag(idx: int, pos: Vector2) -> void:
	if _pinch_unit != null:
		if idx == _pinch_a:
			_finger_a = pos
			_finger_a_known = true
		elif idx == _pinch_b:
			_finger_b = pos
			_finger_b_known = true
		else:
			return

		if not (_finger_a_known and _finger_b_known):
			return
		var span := _finger_a.distance_to(_finger_b)
		if span <= 0.0 or _pinch_start_span <= 0.0:
			return
		var ratio := span / _pinch_start_span
		_pinch_unit.size_scale = clampf(_pinch_start_scale * ratio, _pinch_unit.min_scale, _pinch_unit.max_scale)
		queue_redraw()
		changed.emit()
		return

	if not _drag_index.has(idx):
		return
	var u: LayoutUnit = _drag_index[idx]
	var grab: Vector2 = _drag_grab.get(idx, Vector2.ZERO)
	var target_px := pos - grab

	var ext := u.half * u.size_scale
	target_px.x = clampf(target_px.x, ext.x, size.x - ext.x)
	target_px.y = clampf(target_px.y, ext.y, size.y - ext.y)

	u.set_pixel_centre(target_px)
	queue_redraw()
	changed.emit()
