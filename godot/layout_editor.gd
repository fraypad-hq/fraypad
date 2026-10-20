extends Control

## One movable, resizable unit of the pad.
##
## `centre` is in canvas pixels; `design` is the unit's size as a fraction of
## the canvas height at scale 1.0; `size_scale` is the user's multiplier on that.
class_name LayoutUnit

var key: String = ""
var label: String = ""
## Centre as a fraction of the canvas: x of the width, y of the height. Storing
## fractions rather than pixels keeps a layout proportional on any screen and
## means there is no "is this a fraction or a pixel?" state to get wrong.
var centre: Vector2 = Vector2.ZERO
## This unit's size as a fraction of the canvas height at scale 1.0.
var design: float = 0.2
## The user's multiplier on `design`.
var size_scale: float = 1.0
## Half-extent in pixels at scale 1.0, used to draw the editor handle.
var half: Vector2 = Vector2(80, 80)
var min_scale: float = 0.6
var max_scale: float = 1.8

## Canvas the editor is currently working against, in pixels.
var _canvas: Vector2 = Vector2(1, 1)

func _init(p_key: String = "", p_label: String = "") -> void:
	key = p_key
	label = p_label


## Tell the unit which canvas its fractional centre is expressed against.
func set_canvas(canvas: Vector2) -> void:
	_canvas = canvas


## The unit's centre in canvas pixels.
func pixel_centre() -> Vector2:
	return Vector2(centre.x * _canvas.x, centre.y * _canvas.y)


## Move the unit so its pixel centre is `p_pixels`.
func set_pixel_centre(p_pixels: Vector2) -> void:
	centre = Vector2(p_pixels.x / _canvas.x, p_pixels.y / _canvas.y)


## The unit's on-screen size in pixels.
func pixel_size(h: float) -> float:
	return design * h * size_scale


## The editor's box for this unit, in pixels.
func handle_rect() -> Rect2:
	var ext := half * size_scale
	return Rect2(pixel_centre() - ext, ext * 2.0)


## Overlay: lets the user move and resize the pad's thumb units by hand.
##
## The pad is laid out from a small set of *units* (face diamond, d-pad, left
## stick, right stick). In layout mode this overlay draws a translucent box over
## each unit and lets the user drag a box to move its unit, or pinch a box with
## two fingers to resize it. It never touches the real controls: it only writes
## centres and scales back into `main.gd`, which re-runs the layout.
##
## The overlay sits above `GamepadView`, so while it is visible the pad never
## sees a touch and cannot send input by accident.

var _units: Array[LayoutUnit] = []

## Which unit each active touch index is holding.
var _drag_index: Dictionary = {}
## Per touch index: offset from the unit centre to where the finger went down,
## so the unit does not jump to centre under the finger.
var _drag_grab: Dictionary = {}

## Two-finger pinch state: the unit being scaled, its two touch indices, and
## the span/scale captured when the pinch began.
var _pinch_unit: LayoutUnit = null
var _pinch_a: int = -1
var _pinch_b: int = -1
var _pinch_start_span: float = 0.0
var _pinch_start_scale: float = 1.0

## Emitted whenever a unit moves or scales, so `main.gd` can re-lay-out.
signal changed()

const LABEL_SIZE := 26


func _ready() -> void:
	mouse_filter = Control.MOUSE_FILTER_STOP
	visible = false


## Rebuild the handle list from the current unit state and repaint.
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
		draw_rect(r, Color(0.2, 0.6, 1.0, 0.16), true)
		draw_rect(r, Color(0.45, 0.8, 1.0, 0.9), false, 3.0)
		var label := "%s  %.2fx" % [u.label if u.label != "" else u.key, u.size_scale]
		var ts := font.get_string_size(label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE)
		var tp := r.position + Vector2(12, ts.y + 10)
		# Dark plate behind the text so it stays legible over the pad art.
		draw_rect(Rect2(tp + Vector2(-7, -ts.y - 2), ts + Vector2(14, 12)),
			Color(0, 0, 0, 0.62), true)
		draw_string(font, tp, label, HORIZONTAL_ALIGNMENT_LEFT, -1, LABEL_SIZE,
			Color(0.85, 0.95, 1.0))


func _gui_input(event: InputEvent) -> void:
	if not visible:
		return
	if event is InputEventScreenTouch:
		_handle_touch(event)
	elif event is InputEventScreenDrag:
		_handle_drag(event)


func _handle_touch(event: InputEventScreenTouch) -> void:
	var idx: int = event.index
	if not event.pressed:
		_drag_index.erase(idx)
		_drag_grab.erase(idx)
		if idx == _pinch_a or idx == _pinch_b:
			_end_pinch()
		return

	# A second finger landing on the unit the first finger already holds starts
	# a pinch. A second finger anywhere else is ignored, so only one unit scales.
	if _pinch_unit == null and _drag_index.size() == 1:
		var other: int = _drag_index.keys()[0]
		var held_unit: LayoutUnit = _drag_index[other]
		if held_unit == _unit_at(event.position):
			_start_pinch(held_unit, other, idx)
			return

	var hit := _unit_at(event.position)
	if hit == null:
		return
	_drag_index[idx] = hit
	_drag_grab[idx] = event.position - hit.pixel_centre()


## The unit whose box contains `pos`. Ties pick the smallest box, so an overlap
## still selects the unit the user most likely aimed at.
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


## Begin scaling `u` with two fingers.
##
## Neither finger's live position is known at press time, so the baseline span
## is not captured here: it is taken from the first drag that has reported both
## fingers. Until then the unit does not move, which stops the first drag from
## being mistaken for a large jump.
func _start_pinch(u: LayoutUnit, hold_idx: int, new_idx: int) -> void:
	_pinch_unit = u
	_pinch_a = hold_idx
	_pinch_b = new_idx
	# The held finger went down on the unit, so its press position is the grab
	# point; the new finger's position arrives with its first drag.
	_finger_a = u.pixel_centre() + _drag_grab.get(hold_idx, Vector2.ZERO)
	_finger_a_known = true
	_finger_b = Vector2.ZERO
	_finger_b_known = false
	_pinch_start_span = 0.0
	_pinch_start_scale = u.size_scale
	_drag_index.clear()
	_drag_grab.clear()


## Latest known position of each pinch finger, and whether it has been seen.
var _finger_a: Vector2 = Vector2.ZERO
var _finger_b: Vector2 = Vector2.ZERO
var _finger_a_known: bool = false
var _finger_b_known: bool = false


func _end_pinch() -> void:
	_pinch_unit = null
	_pinch_a = -1
	_pinch_b = -1
	_finger_a_known = false
	_finger_b_known = false


func _handle_drag(event: InputEventScreenDrag) -> void:
	var idx: int = event.index

	if _pinch_unit != null:
		if idx == _pinch_a:
			_finger_a = event.position
			_finger_a_known = true
		elif idx == _pinch_b:
			_finger_b = event.position
			_finger_b_known = true
		else:
			return
		if not (_finger_a_known and _finger_b_known):
			return
		var span := _finger_a.distance_to(_finger_b)
		if span <= 0.0:
			return
		# Capture the starting span on the first drag that has both fingers, then
		# scale by the ratio so the unit tracks the pinch rather than jumping.
		if _pinch_start_span <= 0.0:
			_pinch_start_span = span
			return
		var ratio := span / _pinch_start_span
		_pinch_unit.size_scale = clampf(_pinch_start_scale * ratio,
			_pinch_unit.min_scale, _pinch_unit.max_scale)
		queue_redraw()
		changed.emit()
		return

	if not _drag_index.has(idx):
		return
	var u: LayoutUnit = _drag_index[idx]
	var grab: Vector2 = _drag_grab.get(idx, Vector2.ZERO)
	u.set_pixel_centre(event.position - grab)
	# The unit's size comes from the canvas height, which the editor does not
	# know directly, so ask the pad to re-derive the handle on the next layout.
	queue_redraw()
	changed.emit()
