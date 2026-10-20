extends Control

@onready var client: FraypadClient = $FraypadClient

func _ready() -> void:
	Input.use_accumulated_input = false
	client.set_server("192.168.29.58:54321")
	client.connect_to_server()
	%LeftStick.value_changed.connect(func(v: Vector2): client.send_stick_left(v.x, v.y))
	%RightStick.value_changed.connect(func(v: Vector2): client.send_stick_right(v.x, v.y))
	# A tap on the knob is the stick click: L3 / R3.
	%LeftStick.clicked.connect(func(): client.send_thumb_left(true))
	%LeftStick.clicked.connect(func(): client.send_thumb_left(false))
	%RightStick.clicked.connect(func(): client.send_thumb_right(true))
	%RightStick.clicked.connect(func(): client.send_thumb_right(false))



