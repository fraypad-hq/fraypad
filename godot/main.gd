extends Control

const DEFAULT_SERVER := "192.168.29.58:54321"
const CONFIG_PATH := "user://config.cfg"

@onready var client: FraypadClient = $FraypadClient

var _server_addr: String = DEFAULT_SERVER
var _store: LayoutStore
var _units: Array[LayoutUnit] = []
var _is_kbm: bool = false

const UNIT_DEFAULTS := {
	"face":        {"size": 0.155, "centre": Vector2(0.795, 0.52)},
	"dpad":        {"size": 0.088, "centre": Vector2(0.085, 0.835)},
	"left_stick":  {"size": 0.440, "centre": Vector2(0.180, 0.475)},
	"right_stick": {"size": 0.245, "centre": Vector2(0.915, 0.825)},
}

const UNIT_LABELS := {
	"face": "Face",
	"dpad": "D-pad",
	"left_stick": "L Stick",
	"right_stick": "R Stick",
}


func _ready() -> void:
	DisplayServer.screen_set_orientation(DisplayServer.SCREEN_LANDSCAPE)
	DisplayServer.screen_set_keep_on(true)
	Input.use_accumulated_input = false
	_apply_safe_area()

	_store = LayoutStore.new()
	_load_config()
	_build_units()

	%PadFit.resized.connect(_layout_pad)
	_layout_pad()

	%LayoutButton.pressed.connect(_toggle_layout_mode)
	%LayoutEditor.changed.connect(_layout_pad)
	%LayoutResetButton.pressed.connect(_reset_layout)
	%LayoutSaveAsButton.pressed.connect(_save_layout_as)
	%LayoutSlotsButton.pressed.connect(_toggle_slots)
	%LayoutSlotsCloseButton.pressed.connect(func(): %LayoutSlotsPanel.visible = false)
	%LayoutExportButton.pressed.connect(_export_active_layout)
	%LayoutImportButton.pressed.connect(_import_layout)
	%LayoutDeleteButton.pressed.connect(_delete_selected_layout)
	%LayoutSlotsList.item_selected.connect(_on_slot_selected)
	%LayoutNameField.text_submitted.connect(func(_t: String): _save_layout_as())

	%SettingsButton.pressed.connect(_toggle_settings)
	%SettingsCloseButton.pressed.connect(func(): %SettingsPanel.visible = false)
	%ServerField.text = _server_addr
	%ServerField.text_submitted.connect(func(_t: String): _save_settings())
	%SaveButton.pressed.connect(_save_settings)
	%RetryButton.pressed.connect(_reconnect)
	%DisconnectButton.pressed.connect(_disconnect)

	%ModeButton.pressed.connect(_toggle_mode)

	%LeftStick.value_changed.connect(func(v: Vector2): client.send_stick_left(v.x, v.y))
	%RightStick.value_changed.connect(func(v: Vector2): client.send_stick_right(v.x, v.y))
	%LeftStick.clicked.connect(_tap_left_stick)
	%RightStick.clicked.connect(_tap_right_stick)

	client.connected.connect(_on_connected)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)
	client.rumble.connect(_on_rumble)
	client.ping_updated.connect(_on_ping_updated)

	client.set_server(_server_addr)
	client.connect_to_server()


func _apply_safe_area() -> void:
	var safe := DisplayServer.get_display_safe_area()
	var win_size := DisplayServer.window_get_size()
	if safe.size.x > 0 and win_size.x > 0:
		var pad_margin_left := maxf(safe.position.x, 0.0) * 0.5
		var pad_margin_right := maxf(float(win_size.x) - (safe.position.x + safe.size.x), 0.0) * 0.5
		%PadFit.offset_left = pad_margin_left
		%PadFit.offset_right = -pad_margin_right


func _notification(what: int) -> void:
	if what == NOTIFICATION_WM_GO_BACK_REQUEST:
		if %LayoutSlotsPanel.visible:
			%LayoutSlotsPanel.visible = false
			return
		if %SettingsPanel.visible:
			%SettingsPanel.visible = false
			return
		if %LayoutEditor.visible:
			_toggle_layout_mode()
			return
		if _is_kbm:
			_toggle_mode()
			return


func _layout_pad() -> void:
	var w: float = %PadFit.size.x
	var h: float = %PadFit.size.y
	if w <= 1.0 or h <= 1.0:
		return

	var margin: float = h * 0.025
	var band_h: float = h * 0.18
	var trigger_w: float = w * 0.115
	var bumper_w: float = w * 0.090
	var gap_tb: float = margin * 1.0

	_place(%LT, margin, margin, trigger_w, band_h - margin)
	_place(%LB, margin + trigger_w + gap_tb, margin, bumper_w, band_h - margin)
	_place(%RT, w - margin - trigger_w, margin, trigger_w, band_h - margin)
	_place(%RB, w - margin - trigger_w - gap_tb - bumper_w, margin, bumper_w, band_h - margin)

	var menu_h: float = band_h - margin
	var menu_w: float = h * 0.14
	var gap: float = h * 0.025
	_place(%Xbox, w * 0.5 - menu_w * 0.5, margin, menu_w, menu_h)
	_place(%Back, w * 0.5 - menu_w * 0.5 - gap - menu_w, margin, menu_w, menu_h)
	_place(%Start, w * 0.5 + menu_w * 0.5 + gap, margin, menu_w, menu_h)

	for u in _units:
		u.set_canvas(Vector2(w, h))
		var size: float = u.pixel_size(h)
		var half: float = size * 0.5
		var c: Vector2 = u.pixel_centre()
		match u.key:
			"left_stick":
				_place(%LeftStick, c.x - half, c.y - half, size, size)
				var btn_s := clampf(size * 0.28, 38.0, 56.0)
				_place(%L3, c.x + half + 8.0, c.y - btn_s * 0.5, btn_s, btn_s)
			"right_stick":
				_place(%RightStick, c.x - half, c.y - half, size, size)
				var btn_s := clampf(size * 0.28, 38.0, 56.0)
				_place(%R3, c.x - half - btn_s - 8.0, c.y - btn_s * 0.5, btn_s, btn_s)
			"dpad":
				var span: float = size * 1.06
				_place(%DUp, c.x - half, c.y - span - half, size, size)
				_place(%DDown, c.x - half, c.y + span - half, size, size)
				_place(%DLeft, c.x - span - half, c.y - half, size, size)
				_place(%DRight, c.x + span - half, c.y - half, size, size)
			"face":
				var span: float = size * 1.06
				_place(%BtnY, c.x - half, c.y - span - half, size, size)
				_place(%BtnA, c.x - half, c.y + span - half, size, size)
				_place(%BtnX, c.x - span - half, c.y - half, size, size)
				_place(%BtnB, c.x + span - half, c.y - half, size, size)

	_refresh_unit_handles()
	if %LayoutEditor.visible:
		%LayoutEditor.set_units(_units)

	for ctrl in [%LT, %LB, %RB, %RT, %Back, %Xbox, %Start,
			%DUp, %DLeft, %DDown, %DRight, %L3, %R3]:
		ctrl.add_theme_font_size_override("font_size", maxi(13, int(h * 0.052)))
	for ctrl in [%BtnA, %BtnB, %BtnX, %BtnY]:
		ctrl.add_theme_font_size_override("font_size", maxi(15, int(h * 0.075)))


func _place(ctrl: Control, x: float, y: float, cw: float, ch: float) -> void:
	ctrl.anchor_left = 0.0
	ctrl.anchor_top = 0.0
	ctrl.anchor_right = 0.0
	ctrl.anchor_bottom = 0.0
	ctrl.offset_left = x
	ctrl.offset_top = y
	ctrl.offset_right = x + cw
	ctrl.offset_bottom = y + ch


func _build_units() -> void:
	_units.clear()
	var saved: Dictionary = {}
	if _store != null and _store.has_slot(_store.ACTIVE):
		saved = _store.get_slot(_store.ACTIVE)
	elif _store != null and _store.active_slot() != "" and _store.has_slot(_store.active_slot()):
		saved = _store.get_slot(_store.active_slot())

	for key in UNIT_DEFAULTS:
		var u := LayoutUnit.new(key, UNIT_LABELS[key])
		u.design = UNIT_DEFAULTS[key]["size"]
		u.centre = UNIT_DEFAULTS[key]["centre"]
		u.size_scale = 1.0
		if saved.has(key):
			var entry: Dictionary = saved[key]
			var raw: Variant = entry.get("centre", null)
			if raw is Array and (raw as Array).size() == 2:
				u.centre = Vector2(float(raw[0]), float(raw[1]))
			elif raw is Vector2:
				u.centre = raw
			u.size_scale = float(entry.get("scale", 1.0))
		_units.append(u)
	_refresh_unit_handles()


func _units_payload() -> Dictionary:
	var payload: Dictionary = {}
	for u in _units:
		payload[u.key] = {"centre": [u.centre.x, u.centre.y], "scale": u.size_scale}
	return payload


func _apply_units_payload(payload: Dictionary) -> void:
	for u in _units:
		if not payload.has(u.key):
			continue
		var entry: Dictionary = payload[u.key]
		var raw: Variant = entry.get("centre", null)
		if raw is Array and (raw as Array).size() == 2:
			var cx := clampf(float(raw[0]), 0.05, 0.95)
			var cy := clampf(float(raw[1]), 0.05, 0.95)
			u.centre = Vector2(cx, cy)
		u.size_scale = clampf(float(entry.get("scale", u.size_scale)), u.min_scale, u.max_scale)
	_refresh_unit_handles()
	_layout_pad()
	%LayoutEditor.set_units(_units)


func _refresh_unit_handles() -> void:
	var w: float = %PadFit.size.x
	var h: float = %PadFit.size.y
	if w <= 1.0 or h <= 1.0:
		return
	for u in _units:
		u.set_canvas(Vector2(w, h))
		var extent: float = u.design * h * (2.0 * 1.06 + 1.0) * 0.5
		if u.key.ends_with("stick"):
			extent = u.design * h * 0.5
		u.half = Vector2(extent, extent)


func _save_layout() -> void:
	_store.set_slot(_store.ACTIVE, _units_payload())
	_store.save()


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


func _save_layout_as() -> void:
	var name: String = %LayoutNameField.text.strip_edges()
	if name == "":
		name = "Layout %d" % (_store.slot_names().size() + 1)
	if name == LayoutStore.ACTIVE:
		_set_status("Reserved name.", Color(0.9, 0.6, 0.3))
		return
	_store.set_slot(name, _units_payload())
	_store.set_active_slot(name)
	_store.set_slot(LayoutStore.ACTIVE, _units_payload())
	_store.save()
	%LayoutNameField.text = ""
	_set_status("Saved layout: " + name, Color(0.3, 0.9, 0.5))
	_refresh_layout_ui()


func _on_slot_selected(index: int) -> void:
	var names: Array = _store.slot_names()
	if index < 0 or index >= names.size():
		return
	var name: String = names[index]
	_apply_units_payload(_store.get_slot(name))
	_store.set_active_slot(name)
	_store.set_slot(LayoutStore.ACTIVE, _store.get_slot(name))
	_store.save()
	_set_status("Loaded layout: " + name, Color(0.3, 0.9, 0.5))
	_refresh_layout_ui()


func _delete_selected_layout() -> void:
	var list: ItemList = %LayoutSlotsList
	var sel: Array = list.get_selected_items()
	if sel.is_empty():
		_set_status("Select a layout to delete.", Color(0.9, 0.6, 0.3))
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
	_set_status("Deleted layout: " + name, Color(0.9, 0.7, 0.4))
	_refresh_layout_ui()


func _toggle_slots() -> void:
	%LayoutSlotsPanel.visible = not %LayoutSlotsPanel.visible
	if %LayoutSlotsPanel.visible:
		var default_name := "Layout %d" % (_store.slot_names().size() + 1)
		%LayoutNameField.text = default_name
		%LayoutNameField.select_all()
		_refresh_layout_ui()


func _refresh_layout_ui() -> void:
	var names: Array = _store.slot_names()
	var list: ItemList = %LayoutSlotsList
	list.clear()
	for n in names:
		list.add_item(str(n))
	var active: String = _store.active_slot()
	if active != "" and names.has(active):
		list.select(names.find(active))
	%LayoutActiveLabel.text = "Active: " + (active if active != "" else "built-in")


func _export_active_layout() -> void:
	var json_str := _store.export_all()
	DisplayServer.clipboard_set(json_str)
	_set_status("Layouts copied to clipboard.", Color(0.3, 0.9, 0.5))


func _import_layout() -> void:
	var clip := DisplayServer.clipboard_get()
	if clip.begins_with("{") and clip.contains("slots"):
		_apply_imported(clip)
	else:
		_set_status("No valid layout JSON in clipboard.", Color(0.9, 0.6, 0.3))


func _apply_imported(text: String) -> void:
	var report: Dictionary = _store.import_json(text)
	if not report["ok"]:
		_set_status("Import failed: " + report["error"], Color(0.9, 0.6, 0.3))
		return
	var added: Array = report["added"]
	if added.size() > 0:
		_apply_units_payload(_store.get_slot(str(added[0])))
		_store.set_active_slot(str(added[0]))
		_store.set_slot(LayoutStore.ACTIVE, _store.get_slot(str(added[0])))
		_store.save()
	_set_status("Imported " + str(added.size()) + " layout(s).", Color(0.3, 0.9, 0.5))
	_refresh_layout_ui()


func _load_config() -> void:
	var cfg := ConfigFile.new()
	if cfg.load(CONFIG_PATH) == OK:
		_server_addr = str(cfg.get_value("net", "server", DEFAULT_SERVER))


func _save_config() -> void:
	var cfg := ConfigFile.new()
	cfg.set_value("net", "server", _server_addr)
	cfg.save(CONFIG_PATH)


func _toggle_settings() -> void:
	%SettingsPanel.visible = not %SettingsPanel.visible


func _toggle_layout_mode() -> void:
	var entering: bool = not %LayoutEditor.visible
	if entering:
		_release_gamepad()
		%LayoutEditor.set_units(_units)
	else:
		_save_layout()

	%LayoutEditor.visible = entering
	%LayoutResetButton.visible = entering
	%LayoutSlotsButton.visible = entering
	%LayoutButton.text = "Done" if entering else "Layout"
	%LayoutHint.visible = entering
	%ModeButton.visible = not entering

	if entering:
		%GamepadView.visible = false
		%KBMView.visible = false
		_refresh_layout_ui()
	else:
		%LayoutSlotsPanel.visible = false
		if _is_kbm:
			%KBMView.visible = true
			%GamepadView.visible = false
		else:
			%GamepadView.visible = true
			%KBMView.visible = false


func _toggle_mode() -> void:
	_is_kbm = not _is_kbm
	if _is_kbm:
		_release_gamepad()
	%GamepadView.visible = not _is_kbm
	%KBMView.visible = _is_kbm
	%ModeButton.text = "Pad" if _is_kbm else "KBM"
	%LayoutButton.visible = not _is_kbm


func _release_gamepad() -> void:
	client.send_stick_left(0.0, 0.0)
	client.send_stick_right(0.0, 0.0)
	%LeftStick._recentre()
	%RightStick._recentre()
	for node in %GamepadView.get_children():
		if node is GamepadButton:
			node.release()


func _save_settings() -> void:
	var entered: String = %ServerField.text.strip_edges()
	if entered == "":
		return
	_server_addr = entered
	_save_config()
	_set_status("Server: " + _server_addr + ". Connecting...", Color(0.8, 0.8, 0.4))
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


func _tap_left_stick() -> void:
	client.send_thumb_left(true)
	await get_tree().create_timer(0.05).timeout
	client.send_thumb_left(false)


func _tap_right_stick() -> void:
	client.send_thumb_right(true)
	await get_tree().create_timer(0.05).timeout
	client.send_thumb_right(false)


func _on_connected(slot: int) -> void:
	_set_status("Connected as Player %d" % (slot + 1), Color(0.4, 1.0, 0.5))


func _on_ping_updated(ping_ms: int) -> void:
	if client.is_connected():
		_set_status("P%d  |  %d ms" % [client.player_slot() + 1, ping_ms], Color(0.4, 1.0, 0.5))


func _on_rejected(reason: int) -> void:
	var why := "server is full" if reason == 0 else "version mismatch"
	_set_status("Rejected: " + why + ".", Color(1.0, 0.4, 0.4))
	%SettingsPanel.visible = true


func _on_disconnected() -> void:
	_set_status("Disconnected.", Color(1.0, 0.4, 0.4))
	%SettingsPanel.visible = true


func _on_rumble(strong: int, weak: int, duration_ms: int) -> void:
	var magnitude := clampf(maxf(strong, weak) / 65535.0, 0.0, 1.0)
	if magnitude > 0.0 and duration_ms > 0:
		Input.vibrate_handheld(maxi(duration_ms, 1), magnitude)
