extends Control

## Default server address used the first time the app runs (before the user
## sets their own). Saved to user://config.cfg on every change.
const DEFAULT_SERVER := "192.168.29.58:54321"
const CONFIG_PATH := "user://config.cfg"

@onready var client: FraypadClient = $FraypadClient

var _server_addr: String = DEFAULT_SERVER


func _ready() -> void:
	Input.use_accumulated_input = false
	_load_config()

	# ── Settings panel ───────────────────────────────────────────────
	%SettingsButton.pressed.connect(_toggle_settings)
	%SettingsPanel.visible = false
	%ServerField.text = _server_addr
	%ServerField.text_submitted.connect(func(_t: String): _save_settings())
	%SaveButton.pressed.connect(_save_settings)
	%RetryButton.pressed.connect(_reconnect)
	%DisconnectButton.pressed.connect(_disconnect)

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


func _save_settings() -> void:
	var entered := %ServerField.text.strip_edges()
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
	# vibrate the handheld for the requested duration. A zeroed rumble is the
	# game stopping an effect: cancel whatever is still vibrating.
	var magnitude := clampf(maxf(strong, weak) / 65535.0, 0.0, 1.0)
	if magnitude > 0.0 and duration_ms > 0:
		# Keep the game's full duration and drive intensity with magnitude, so
		# quiet rumbles don't truncate to a no-op.
		Input.vibrate_handheld(maxi(duration_ms, 1), magnitude)
	else:
		Input.cancel_vibration()
