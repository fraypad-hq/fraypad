extends Control

## Default server address used the first time the app runs (before the user
## sets their own). Saved to user://config.cfg on every change.
const DEFAULT_SERVER := "192.168.29.58:54321"
const CONFIG_PATH := "user://config.cfg"

## Set while chasing a layout bug: writes the loaded layout to the log and to
## `user://layout_dump.txt`. Off in normal builds.
const DEBUG_DUMP_LAYOUT := false

@onready var client: FraypadClient = $FraypadClient

var _server_addr: String = DEFAULT_SERVER

## Named layouts, on disk as JSON so they survive a config change and can be
## exported to another phone.
var _store: LayoutStore

## The movable thumb units, keyed by name. Each entry holds the unit's centre
## as a fraction of the canvas plus a scale multiplier on its design size.
## Layout mode edits these; `_layout_pad` reads them. The top band is
## deliberately not a unit. Storing fractions keeps a hand-made layout
## proportional on any screen.
var _units: Array[LayoutUnit] = []

## Design (scale 1.0) sizes as a fraction of canvas height, and the default
## centre as a fraction of the canvas. Units on the right are authored from the
## right edge, which is why their x fraction is above 0.5.
const UNIT_DEFAULTS := {
	"face":        {"size": 0.145, "centre": Vector2(0.7933, 0.44)},
	"dpad":        {"size": 0.100, "centre": Vector2(0.2067, 0.79)},
	"left_stick":  {"size": 0.380, "centre": Vector2(0.2067, 0.39)},
	"right_stick": {"size": 0.300, "centre": Vector2(0.9236, 0.83)},
}
## Human-readable names for the editor's handles.
const UNIT_LABELS := {
	"face": "Face",
	"dpad": "D-pad",
	"left_stick": "L Stick",
	"right_stick": "R Stick",
}


func _ready() -> void:
	Input.use_accumulated_input = false
	_store = LayoutStore.new()
	_migrate_legacy_layout()
	_load_config()
	_build_units()
	if DEBUG_DUMP_LAYOUT:
		_dump_layout_debug()

	# ── Pad geometry ─────────────────────────────────────────────────
	# Place the controller controls in code, then redo it whenever the canvas
	# or window changes (rotation, resize, split-screen).
	%PadFit.resized.connect(_on_pad_resized)
	_layout_pad()

	# ── Layout editor ────────────────────────────────────────────────
	%LayoutButton.pressed.connect(_toggle_layout_mode)
	%LayoutEditor.changed.connect(_layout_pad)
	%LayoutResetButton.pressed.connect(_reset_layout)
	%LayoutSaveAsButton.pressed.connect(_save_layout_as)
	%LayoutSlotsButton.pressed.connect(_toggle_slots)
	%LayoutExportButton.pressed.connect(_export_active_layout)
	%LayoutImportButton.pressed.connect(_import_layout)
	%LayoutDeleteButton.pressed.connect(_delete_selected_layout)
	%LayoutSlotsPanel.visible = false
	%LayoutSlotsList.item_selected.connect(_on_slot_selected)

	# ── Settings panel ───────────────────────────────────────────────
	%SettingsButton.pressed.connect(_toggle_settings)
	%SettingsPanel.visible = false
	%ServerField.text = _server_addr
	%ServerField.text_submitted.connect(func(_t: String): _save_settings())
	%SaveButton.pressed.connect(_save_settings)
	%RetryButton.pressed.connect(_reconnect)
	%DisconnectButton.pressed.connect(_disconnect)

	# ── Mode switch ──────────────────────────────────────────────────
	%ModeButton.pressed.connect(_toggle_mode)
	%KBMView.visible = false

	# ── Sticks ───────────────────────────────────────────────────────
	%LeftStick.value_changed.connect(func(v: Vector2): client.send_stick_left(v.x, v.y))
	%RightStick.value_changed.connect(func(v: Vector2): client.send_stick_right(v.x, v.y))
	# A tap on the knob is the stick click: L3 / R3.
	%LeftStick.clicked.connect(_tap_left_stick)
	%RightStick.clicked.connect(_tap_right_stick)

	# ── Connection lifecycle ─────────────────────────────────────────
	client.connected.connect(_on_connected)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)
	client.rumble.connect(_on_rumble)

	client.set_server(_server_addr)
	client.connect_to_server()


# ── Pad geometry ─────────────────────────────────────────────────────────

## Lay the gamepad controls out like an Xbox 360 pad, in code.
##
## Godot's `expand` stretch mode widens the canvas to match the window aspect,
## so a 20:9 phone gives a canvas much wider than the 900x500 design size.
## Anchors alone would then stretch the d-pad arms and face buttons into
## lopsided rectangles. Instead every control is sized off the canvas *height*
## (so round/square things stay round/square at any aspect) and positioned in
## px offsets, with the two thumb clusters pinned to the left and right edges.
##
## Both clusters are laid out as a four-corner **diamond** (A bottom, B right,
## X left, Y top) rather than a plus/cross. Arms that touch edge-to-edge read
## as one blob and make it ambiguous which button a thumb is on; separating the
## four corners makes each one its own target. The face buttons are deliberately
## larger than the d-pad: they are the most-tapped controls on the pad, while
## the d-pad is usually nudged rather than mashed.
func _layout_pad() -> void:
	var w: float = %PadFit.size.x
	var h: float = %PadFit.size.y
	if w <= 1.0 or h <= 1.0:
		return

	var margin: float = h * 0.02

	# ── Top band: triggers reach the corners, bumpers sit inboard ────
	var band_h: float = h * 0.17
	var trigger_w: float = w * 0.11
	var bumper_w: float = w * 0.085
	_place(%LT, margin, margin, trigger_w, band_h - margin)
	_place(%LB, margin + trigger_w + margin, margin, bumper_w, band_h - margin)
	_place(%RT, w - margin - trigger_w, margin, trigger_w, band_h - margin)
	_place(%RB, w - margin - trigger_w - margin - bumper_w, margin, bumper_w, band_h - margin)

	# ── Top centre: Back / Xbox / Start, sized off height ────────────
	var menu_h: float = band_h - margin
	var menu_w: float = h * 0.13
	var gap: float = h * 0.02
	_place(%Xbox, w * 0.5 - menu_w * 0.5, margin, menu_w, menu_h)
	_place(%Back, w * 0.5 - menu_w * 0.5 - gap - menu_w, margin, menu_w, menu_h)
	_place(%Start, w * 0.5 + menu_w * 0.5 + gap, margin, menu_w, menu_h)

	# ── Thumb units ──────────────────────────────────────────────────
	# Each unit's centre and scale live in `_units`, so the user's layout is
	# what gets painted here. A unit's on-screen size is its design fraction of
	# the canvas height times its scale, which keeps round things round at any
	# aspect. The two diamonds place their four buttons on the diagonals, offset
	# by `span` on both axes: buttons that touch edge to edge read as one blob,
	# and the gap makes it obvious which corner a thumb is on.
	for u in _units:
		u.set_canvas(Vector2(w, h))
		var size: float = u.pixel_size(h)
		var half: float = size * 0.5
		var c: Vector2 = u.pixel_centre()
		match u.key:
			"left_stick":
				_place(%LeftStick, c.x - half, c.y - half, size, size)
			"right_stick":
				_place(%RightStick, c.x - half, c.y - half, size, size)
			"dpad":
				var span: float = size * 1.05
				_place(%DUp, c.x - half, c.y - span - half, size, size)
				_place(%DDown, c.x - half, c.y + span - half, size, size)
				_place(%DLeft, c.x - span - half, c.y - half, size, size)
				_place(%DRight, c.x + span - half, c.y - half, size, size)
			"face":
				var span: float = size * 1.05
				_place(%BtnY, c.x - half, c.y - span - half, size, size)
				_place(%BtnA, c.x - half, c.y + span - half, size, size)
				_place(%BtnX, c.x - span - half, c.y - half, size, size)
				_place(%BtnB, c.x + span - half, c.y - half, size, size)

	# Keep the layout editor's handles on top of the controls they represent.
	_refresh_unit_handles()
	if %LayoutEditor.visible:
		%LayoutEditor.set_units(_units)

	# Scale label text with the pad so it stays readable on a big phone and
	# doesn't overflow the button on a small one. The face buttons get a
	# proportionally larger glyph now that they are bigger targets.
	for ctrl in [%LT, %LB, %RB, %RT, %Back, %Xbox, %Start,
			%DUp, %DLeft, %DDown, %DRight]:
		var fs: int = maxi(12, int(h * 0.055))
		ctrl.add_theme_font_size_override("font_size", fs)
	for ctrl in [%BtnA, %BtnB, %BtnX, %BtnY]:
		var ffs: int = maxi(14, int(h * 0.075))
		ctrl.add_theme_font_size_override("font_size", ffs)


## Canvas changed shape (rotation, resize, split-screen): unit centres are stored
## as fractions, so `_layout_pad` re-derives everything from the new size.
func _on_pad_resized() -> void:
	_layout_pad()


## Park a control at an absolute pixel rect. Anchors are pinned to the top-left
## so the offsets are the whole geometry and the control keeps the exact size
## the caller computed (no stretching from fractional anchors).
func _place(ctrl: Control, x: float, y: float, cw: float, ch: float) -> void:
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = x
	ctrl.offset_top = y
	ctrl.offset_right = x + cw
	ctrl.offset_bottom = y + ch


# ── Layout units ─────────────────────────────────────────────────────────

## TEMPORARY: write the layout the app loaded to a world-readable path so it can
## be read off the device over adb. Release builds are not debuggable, so
## `run-as` cannot reach the app's own data directory. Remove once captured.
func _dump_layout_debug() -> void:
	var lines: Array = ["# fraypad layout dump"]
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		lines.append("config.cfg: not present")
	else:
		lines.append("config.cfg loaded")
		lines.append("custom=%s" % str(cfg.get_value("layout", "custom", "MISSING")))
		for key in UNIT_DEFAULTS:
			var c: Variant = cfg.get_value("layout_%s" % key, "centre", "MISSING")
			var s: Variant = cfg.get_value("layout_%s" % key, "scale", "MISSING")
			lines.append("%s centre=%s scale=%s" % [key, str(c), str(s)])
	for u in _units:
		lines.append("unit %s frac=(%.5f, %.5f) scale=%.3f" % [
			u.key, u.centre.x, u.centre.y, u.size_scale])
	var f := FileAccess.open("user://layout_dump.txt", FileAccess.WRITE)
	if f != null:
		f.store_string("\n".join(lines) + "\n")
		f.close()
	for line in lines:
		print("LAYOUTDUMP ", line)


## Create the four thumb units, preferring the layout the user last had active.
##
## Centres are held as *fractions* of the canvas (x of width, y of height), not
## pixels, so a layout keeps its proportions on a differently shaped screen and
## no conversion state has to be tracked. `LayoutUnit.pixel_centre` derives the
## pixel position for the current canvas. The active named layout overrides the
## built-in defaults in both position and scale.
func _build_units() -> void:
	_units.clear()
	var saved: Dictionary = {}
	if _store != null and _store.has_slot(_store.ACTIVE):
		saved = _store.get_slot(_store.ACTIVE)
	elif _store != null and _store.active_slot() != "" \
			and _store.has_slot(_store.active_slot()):
		saved = _store.get_slot(_store.active_slot())
	for key in UNIT_DEFAULTS:
		var u := LayoutUnit.new(key, UNIT_LABELS[key])
		u.design = UNIT_DEFAULTS[key]["size"]
		u.centre = UNIT_DEFAULTS[key]["centre"]
		u.size_scale = 1.0
		if saved.has(key):
			var entry: Dictionary = saved[key]
			u.centre = entry.get("centre", u.centre)
			u.size_scale = float(entry.get("scale", 1.0))
		_units.append(u)
	_refresh_unit_handles()


## A unit's current centre and scale, as a plain dictionary for JSON storage.
func _units_payload() -> Dictionary:
	var payload: Dictionary = {}
	for u in _units:
		payload[u.key] = {"centre": [u.centre.x, u.centre.y], "scale": u.size_scale}
	return payload


## Apply a stored payload to the units and repaint the pad.
func _apply_units_payload(payload: Dictionary) -> void:
	for u in _units:
		if not payload.has(u.key):
			continue
		var entry: Dictionary = payload[u.key]
		# JSON has no Vector2, so centres come back as a two-element array.
		var raw: Variant = entry.get("centre", null)
		if raw is Array and (raw as Array).size() == 2:
			u.centre = Vector2(float(raw[0]), float(raw[1]))
		u.size_scale = float(entry.get("scale", u.size_scale))
	_refresh_unit_handles()
	_layout_pad()
	%LayoutEditor.set_units(_units)


## Refresh each unit's editor handle from the current canvas size.
##
## The handle covers the whole unit: for a diamond that is two button spans plus
## one button, for a stick just the stick. Called from `_layout_pad`, so the
## boxes always match the controls they represent.
func _refresh_unit_handles() -> void:
	var w: float = %PadFit.size.x
	var h: float = %PadFit.size.y
	if w <= 1.0 or h <= 1.0:
		return
	for u in _units:
		u.set_canvas(Vector2(w, h))
		var extent: float = u.design * h * (2.0 * 1.05 + 1.0) * 0.5
		if u.key.ends_with("stick"):
			extent = u.design * h * 0.5
		u.half = Vector2(extent, extent)


## Persist the layout currently on screen as the active (working) layout.
##
## Safe to call at any time, including after the editor has been hidden, so
## leaving layout mode cannot silently skip the save. Layouts live in their own
## JSON file, not `config.cfg`: the two used to share one file and saving the
## server address wiped the layout.
func _save_layout() -> void:
	_store.set_slot(_store.ACTIVE, _units_payload())
	_store.save()


## Restore the built-in layout: drop the working layout, keep named slots.
func _reset_layout() -> void:
	_store.erase_slot(_store.ACTIVE)
	_store.set_active_slot("")
	_store.save()
	for key in UNIT_DEFAULTS:
		for u in _units:
			if u.key == key:
				u.centre = UNIT_DEFAULTS[key]["centre"]
				u.size_scale = 1.0
	_refresh_unit_handles()
	_layout_pad()
	%LayoutEditor.set_units(_units)
	_refresh_layout_ui()


# ── Named layouts ────────────────────────────────────────────────────────

## Bring a layout saved by an older build across from `config.cfg`.
##
## Older versions wrote the layout into the shared config file under `layout_*`
## sections. New builds read `layouts.json`, so on first launch move any such
## layout into the active slot and drop the old keys. Without this the user's
## arrangement would silently revert to the built-in one after upgrading.
func _migrate_legacy_layout() -> void:
	if FileAccess.file_exists(LayoutStore.PATH):
		return
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) != OK:
		return
	if not cfg.get_value("layout", "custom", false):
		return
	var payload: Dictionary = {}
	for key in UNIT_DEFAULTS:
		if not cfg.has_section("layout_%s" % key):
			continue
		var centre: Variant = cfg.get_value("layout_%s" % key, "centre", null)
		if not (centre is Vector2):
			continue
		payload[key] = {
			"centre": [(centre as Vector2).x, (centre as Vector2).y],
			"scale": float(cfg.get_value("layout_%s" % key, "scale", 1.0)),
		}
	if payload.is_empty():
		return
	_store.set_slot(_store.ACTIVE, payload)
	_store.save()
	# Drop the old keys so the migration runs once and the files do not diverge.
	cfg.erase_section("layout")
	for key in UNIT_DEFAULTS:
		cfg.erase_section("layout_%s" % key)
	cfg.save(CONFIG_PATH)
	print("Fraypad: migrated layout from config.cfg")


## Ask for a name, then store the on-screen layout under it.
func _save_layout_as() -> void:
	var name: String = %LayoutNameField.text.strip_edges()
	if name == "":
		_set_status("Give the layout a name first.", Color(0.9, 0.6, 0.3))
		return
	if name == LayoutStore.ACTIVE:
		_set_status("That name is reserved.", Color(0.9, 0.6, 0.3))
		return
	_store.set_slot(name, _units_payload())
	_store.set_active_slot(name)
	_store.set_slot(LayoutStore.ACTIVE, _units_payload())
	_store.save()
	%LayoutNameField.text = ""
	_set_status("Saved layout \"%s\"." % name, Color(0.6, 0.9, 0.6))
	_refresh_layout_ui()


## Load the tapped slot.
func _on_slot_selected(index: int) -> void:
	var names: Array = _store.slot_names()
	if index < 0 or index >= names.size():
		return
	var name: String = names[index]
	_apply_units_payload(_store.get_slot(name))
	_store.set_active_slot(name)
	_store.set_slot(LayoutStore.ACTIVE, _store.get_slot(name))
	_store.save()
	_set_status("Loaded layout \"%s\"." % name, Color(0.6, 0.9, 0.6))
	_refresh_layout_ui()


## Remove the selected layout. Deleting is keystroke-free but explicit, and it
## never touches the layout currently on the pad until the user loads another,
## so a mis-tap cannot strand them on a half-arranged pad.
func _delete_selected_layout() -> void:
	var list: ItemList = %LayoutSlotsList
	var sel: Array = list.get_selected_items()
	if sel.is_empty():
		_set_status("Pick a layout to delete first.", Color(0.9, 0.6, 0.3))
		return
	var names: Array = _store.slot_names()
	var index: int = sel[0]
	if index < 0 or index >= names.size():
		return
	var name: String = names[index]
	if name == _store.active_slot():
		_store.set_active_slot("")
	_store.erase_slot(name)
	_store.save()
	_set_status("Deleted layout \"%s\"." % name, Color(0.9, 0.7, 0.4))
	_refresh_layout_ui()


func _toggle_slots() -> void:
	%LayoutSlotsPanel.visible = not %LayoutSlotsPanel.visible
	_refresh_layout_ui()


## Refresh the slot list and the header line showing what is active.
func _refresh_layout_ui() -> void:
	var names: Array = _store.slot_names()
	var list: ItemList = %LayoutSlotsList
	list.clear()
	for n in names:
		list.add_item(str(n))
	var active: String = _store.active_slot()
	if active != "" and names.has(active):
		list.select(names.find(active))
	%LayoutActiveLabel.text = "Active: %s" % (active if active != "" else "built-in")


## Write every saved layout to a JSON file the user chooses.
##
## Uses Godot's own file dialog: on Android that opens the system picker, so the
## file lands wherever the user wants (Downloads, Drive, a share target) instead
## of a hardcoded path that shared storage may not even allow writing to.
func _export_active_layout() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_SAVE_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Export layouts"
	dlg.add_filter("*.json", "Fraypad layouts")
	dlg.current_file = "fraypad-layouts.json"
	add_child(dlg)
	dlg.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.WRITE)
		if f == null:
			_set_status("Could not write %s" % path.get_file(), Color(0.9, 0.6, 0.3))
		else:
			f.store_string(_store.export_all())
			f.close()
			_set_status("Exported to %s" % path.get_file(), Color(0.6, 0.9, 0.6))
		dlg.queue_free())
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


## Read a layout JSON file the user picks and merge it into the saved layouts.
func _import_layout() -> void:
	var dlg := FileDialog.new()
	dlg.file_mode = FileDialog.FILE_MODE_OPEN_FILE
	dlg.access = FileDialog.ACCESS_FILESYSTEM
	dlg.use_native_dialog = true
	dlg.title = "Import layouts"
	dlg.add_filter("*.json", "Fraypad layouts")
	add_child(dlg)
	dlg.file_selected.connect(func(path: String):
		var f := FileAccess.open(path, FileAccess.READ)
		if f == null:
			_set_status("Could not read %s" % path.get_file(), Color(0.9, 0.6, 0.3))
			dlg.queue_free()
			return
		var text := f.get_as_text()
		f.close()
		dlg.queue_free()
		_apply_imported(text))
	dlg.canceled.connect(dlg.queue_free)
	dlg.popup_centered()


## Merge imported JSON and show the first layout that came in.
func _apply_imported(text: String) -> void:
	var report: Dictionary = _store.import_json(text)
	if not report["ok"]:
		_set_status("Import failed: %s" % report["error"], Color(0.9, 0.6, 0.3))
		return
	var added: Array = report["added"]
	# Show what came in straight away, so the result is visible without hunting.
	if added.size() > 0:
		_apply_units_payload(_store.get_slot(str(added[0])))
		_store.set_active_slot(str(added[0]))
		_store.set_slot(LayoutStore.ACTIVE, _store.get_slot(str(added[0])))
		_store.save()
	_set_status("Imported %d layout(s)." % added.size(), Color(0.6, 0.9, 0.6))
	_refresh_layout_ui()


# ── Config ───────────────────────────────────────────────────────────────

func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_server_addr = str(cfg.get_value("net", "server", DEFAULT_SERVER))


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server", _server_addr)
	cfg.save(CONFIG_PATH)


# ── UI actions ───────────────────────────────────────────────────────────

func _toggle_settings() -> void:
	%SettingsPanel.visible = not %SettingsPanel.visible


## Enter or leave layout mode.
##
## In layout mode the editor overlay covers the pad and eats every touch, so no
## input can reach the PC while the user is moving boxes around. Leaving drops
## the pad and persists whatever the user settled on.
func _toggle_layout_mode() -> void:
	var entering: bool = not %LayoutEditor.visible
	if entering:
		# Nothing should stay held on the PC while the pad is being rearranged.
		_release_gamepad()
		%LayoutEditor.set_units(_units)
	else:
		# Save while the units still hold the user's arrangement. Doing it after
		# hiding the editor used to be a no-op.
		_save_layout()
	%LayoutEditor.visible = entering
	%GamepadView.visible = not entering
	%LayoutResetButton.visible = entering
	%LayoutSlotsButton.visible = entering
	%LayoutButton.text = "✓ Done" if entering else "✥ Layout"
	%LayoutHint.visible = entering
	if not entering:
		# Leaving the editor takes the slots panel with it, so returning to the
		# pad is always one tap rather than two.
		%LayoutSlotsPanel.visible = false
	else:
		_refresh_layout_ui()


## Swap between the gamepad controls and the keyboard/mouse surface.
##
## Before hiding a side we release what it might be holding: a stick left
## deflected or a key left down would otherwise stay that way on the PC,
## because the release touch lands on a control that is no longer visible.
func _toggle_mode() -> void:
	var to_kbm: bool = not %KBMView.visible
	if to_kbm:
		_release_gamepad()
	%GamepadView.visible = not to_kbm
	%KBMView.visible = to_kbm
	%ModeButton.text = "🎮 Gamepad" if to_kbm else "⌨ KBM"


## Recenter both sticks and let every button drop whatever it is holding, so
## the PC sees a neutral pad.
func _release_gamepad() -> void:
	client.send_stick_left(0.0, 0.0)
	client.send_stick_right(0.0, 0.0)
	for node in get_tree().get_nodes_in_group("dpad_x"):
		node._fingers.clear()
		if node._is_active:
			node._is_active = false
			node._update_visual()
			node._send_dpad_aware(false)
	for node in get_tree().get_nodes_in_group("dpad_y"):
		node._fingers.clear()
		if node._is_active:
			node._is_active = false
			node._update_visual()
			node._send_dpad_aware(false)
	# Face/menu/bumper/trigger buttons are GamepadButtons not in a d-pad group.
	for node in %GamepadView.get_children():
		if node is GamepadButton and not node.is_in_group("dpad_x") \
				and not node.is_in_group("dpad_y"):
			node._fingers.clear()
			if node._is_active:
				node._is_active = false
				node._update_visual()
				node._send(false)


func _save_settings() -> void:
	var entered: String = %ServerField.text.strip_edges()
	if entered == "":
		return
	_server_addr = entered
	_save_config()
	_set_status("Server set to " + _server_addr + ". Reconnecting…", Color(0.8, 0.8, 0.4))
	%SettingsPanel.visible = false
	_reconnect()


func _reconnect() -> void:
	client.set_server(_server_addr)
	client.connect_to_server()


func _disconnect() -> void:
	client.disconnect_from_server()
	%SettingsPanel.visible = true


func _set_status(text: String, color: Color) -> void:
	%StatusLabel.text = text
	%StatusLabel.modulate = color


# ── Stick taps (L3 / R3) ─────────────────────────────────────────────────

func _tap_left_stick() -> void:
	client.send_thumb_left(true)
	client.send_thumb_left(false)


func _tap_right_stick() -> void:
	client.send_thumb_right(true)
	client.send_thumb_right(false)


# ── Connection lifecycle ─────────────────────────────────────────────────

func _on_connected(slot: int) -> void:
	_set_status("Connected as Player %d" % (slot + 1), Color(0.4, 1.0, 0.5))


func _on_rejected(reason: int) -> void:
	# 0 = server full, 1 = version mismatch (see RejectReason in the protocol).
	var why := "server is full" if reason == 0 else "server/client version mismatch"
	_set_status("Rejected: " + why + ". Tap to retry.", Color(1.0, 0.4, 0.4))
	%SettingsPanel.visible = true


func _on_disconnected() -> void:
	_set_status("Disconnected. Tap to retry.", Color(1.0, 0.4, 0.4))
	%SettingsPanel.visible = true


func _on_rumble(strong: int, weak: int, duration_ms: int) -> void:
	# Scale the 0-65535 magnitudes down to the 0..1 range Android expects and
	# vibrate the handheld for the requested duration. Keep the game's full
	# duration and drive intensity with magnitude, so quiet rumbles don't
	# truncate to a no-op.
	#
	# A zeroed rumble means the game stopped an effect. Handheld vibration is
	# a fire-and-forget duration with no cancel API, so there is nothing to
	# do: the previous buzz simply runs out its (short) remaining time.
	var magnitude := clampf(maxf(strong, weak) / 65535.0, 0.0, 1.0)
	if magnitude > 0.0 and duration_ms > 0:
		Input.vibrate_handheld(maxi(duration_ms, 1), magnitude)
