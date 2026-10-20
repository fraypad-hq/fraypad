extends Control

@onready var client: FraypadClient = $FraypadClient

func _ready() -> void:
	Input.use_accumulated_input = false
	client.set_server("192.168.29.58:54321")

	%LeftStick.value_changed.connect(func(v: Vector2): client.send_stick_left(v.x, v.y))
	%RightStick.value_changed.connect(func(v: Vector2): client.send_stick_right(v.x, v.y))
	# A tap on the knob is the stick click: L3 / R3.
	%LeftStick.clicked.connect(func(): client.send_thumb_left(true))
	%LeftStick.clicked.connect(func(): client.send_thumb_left(false))
	%RightStick.clicked.connect(func(): client.send_thumb_right(true))
	%RightStick.clicked.connect(func(): client.send_thumb_right(false))

	# Connection lifecycle.
	client.connected.connect(_on_connected)
	client.rejected.connect(_on_rejected)
	client.disconnected.connect(_on_disconnected)
	client.rumble.connect(_on_rumble)

	# Kick off the (non-blocking) handshake. The outcome arrives via signals.
	client.connect_to_server()


func _on_connected(slot: int) -> void:
	print("Connected to server as player ", slot + 1)


func _on_rejected() -> void:
	printerr("Server rejected the connection (all slots full).")


func _on_disconnected() -> void:
	printerr("Disconnected from server.")


func _on_rumble(strong: int, weak: int, duration_ms: int) -> void:
	# Scale the 0-65535 magnitudes down to the 0..1 range Android expects and
	# vibrate the handheld for the requested duration. A zeroed rumble is the
	# game stopping an effect: cancel whatever is still vibrating.
	var magnitude := clampf(maxf(strong, weak) / 65535.0, 0.0, 1.0)
	if magnitude > 0.0 and duration_ms > 0:
		Input.vibrate_handheld(int(duration_ms * magnitude), magnitude)
	else:
		Input.cancel_vibration()
