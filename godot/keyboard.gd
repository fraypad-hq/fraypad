extends Control
class_name FraypadKeyboard

## An on-screen QWERTY keyboard that fires evdev key codes at the server.
##
## Keys are plain `Button`s (so touch, mouse, and accessibility all behave)
## laid out from a row description; each press-release sends the matching
## evdev code through the client's keyboard/mouse route.
##
## The evdev codes are physical keys, so a key labelled with a shifted symbol
## sends its base key and relies on the PC's own layout for the shift.

## Layout: each inner array is a row of `[label, evdev_code]`, with `null`
## entries marking flexible spacers. `codes` come from `fraypad_protocol`.
const ROWS := [
	[["1", 2], ["2", 3], ["3", 4], ["4", 5], ["5", 6], ["6", 7], ["7", 8],
	 ["8", 9], ["9", 10], ["0", 11], ["-", 12], ["=", 13], ["⌫", 14]],
	[["Tab", 15], ["Q", 16], ["W", 17], ["E", 18], ["R", 19], ["T", 20],
	 ["Y", 21], ["U", 22], ["I", 23], ["O", 24], ["P", 25], ["[", 26], ["]", 27]],
	[["Esc", 1], ["A", 30], ["S", 31], ["D", 32], ["F", 33], ["G", 34],
	 ["H", 35], ["J", 36], ["K", 37], ["L", 38], [";", 39], ["'", 40],
	 ["\\", 43], ["Enter", 28]],
	[["⇧", 42], ["Z", 44], ["X", 45], ["C", 46], ["V", 47], ["B", 48],
	 ["N", 49], ["M", 50], [",", 51], [".", 52], ["/", 53], ["⇧", 54]],
	[["Ctrl", 29], ["Alt", 56], ["Space", 57], ["←", 105], ["↑", 103],
	 ["↓", 108], ["→", 106]],
]

## Keys wider than one unit, matched by label so the layout stays declarative.
const WIDE := {
	"⌫": 2.0, "Tab": 1.5, "\\": 1.5, "Enter": 2.0, "⇧": 1.5,
	"Ctrl": 1.5, "Alt": 1.25, "Space": 6.0,
}

var _client: FraypadClient


func _ready() -> void:
	var layout := VBoxContainer.new()
	layout.set_anchors_preset(Control.PRESET_FULL_RECT)
	layout.add_theme_constant_override("separation", 6)
	add_child(layout)

	for row in ROWS:
		layout.add_child(_build_row(row))


func _build_row(keys: Array) -> HBoxContainer:
	var row := HBoxContainer.new()
	row.add_theme_constant_override("separation", 6)
	row.size_flags_horizontal = Control.SIZE_EXPAND_FILL
	for entry in keys:
		var label: String = entry[0]
		var code: int = entry[1]
		var btn := Button.new()
		btn.text = label
		btn.focus_mode = Control.FOCUS_NONE
		btn.size_flags_horizontal = Control.SIZE_EXPAND_FILL
		btn.size_flags_stretch_ratio = WIDE.get(label, 1.0)
		btn.add_theme_font_size_override("font_size", 16)
		# Fire on press and release so held keys (Shift, Ctrl) work.
		btn.button_down.connect(_send.bind(code, true))
		btn.button_up.connect(_send.bind(code, false))
		row.add_child(btn)
	return row


## The signal client, fetched on first use and cached.
##
## Avoids resolving it in `_ready`, where the GDExtension class may still be
## unregistered and the cast would yield null for the rest of the session.
func _get_client() -> FraypadClient:
	if _client == null:
		_client = get_tree().get_first_node_in_group("fraypad_client") as FraypadClient
	return _client


func _send(code: int, pressed: bool) -> void:
	var client := _get_client()
	if client:
		client.send_key(code, pressed)


## Releasing keys on focus loss avoids a modifier being held forever if the
## app is backgrounded mid-chord.
func _notification(what: int) -> void:
	if what == NOTIFICATION_APPLICATION_PAUSED \
			or what == NOTIFICATION_WM_WINDOW_FOCUS_OUT:
		var client := _get_client()
		for row in ROWS:
			for entry in row:
				if client:
					client.send_key(entry[1], false)
