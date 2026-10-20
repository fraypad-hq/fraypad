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

	# ── Pad geometry ─────────────────────────────────────────────────
	# Place the controller controls in code, then redo it whenever the canvas
	# or window changes (rotation, resize, split-screen).
	%PadFit.resized.connect(_layout_pad)
	_layout_pad()

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

	# ── Thumb clusters ───────────────────────────────────────────────
	# Vertical budget, in fractions of the height:
	#   bumpers 0..0.17 | left stick 0.20..0.58 | d-pad 0.66..0.95
	#                   | face diamond 0.21..0.67 | right stick 0.70..0.98
	#
	# The two sides are not mirror images. On the left the **stick** sits high,
	# where the d-pad used to be, and the d-pad drops below it: the left thumb
	# lives on the stick, so it gets the easier, higher position. The d-pad is a
	# deliberate reach and is used less, so it goes where the thumb falls
	# naturally onto it. The right side keeps the stick down in the corner
	# under the face diamond, which is the usual layout.
	#
	# The face diamond gets a bigger button than the d-pad, so the whole right
	# cluster is scaled up. `dspan`/`fspan` are the distance from the cluster
	# centre to a button's centre along each axis; the corner buttons are offset
	# by that on both axes, which is what puts them on the diagonals and leaves
	# the centre empty.
	var face: float = h * 0.145       # one face button (large, easy to hit)
	var dpad: float = h * 0.10        # one d-pad button
	var cluster_y: float = h * 0.44   # vertical centre of the face diamond
	var right_cx: float = w - h * 0.46
	var left_cx: float = h * 0.46     # vertical axis both left controls share
	var stick: float = h * 0.38       # thumbstick touch area (square, left)
	var rstick: float = h * 0.30      # right thumbstick touch area (square)

	# Left stick: high, where the d-pad used to be, and large.
	var ls_y: float = h * 0.39 - stick * 0.5
	_place(%LeftStick, left_cx - stick * 0.5, ls_y, stick, stick)

	# D-pad diamond, below the stick on the same vertical axis.
	#   Buttons sit on the diagonals, each offset from the cluster centre by
	#   `dspan` on both axes. `dspan` must be at least the button size, or
	#   diagonally adjacent buttons share a corner square; the extra 5% opens a
	#   clean gap so it is obvious which corner a thumb is on.
	var dspan: float = dpad * 1.05
	var dcx: float = left_cx
	var dcy: float = h * 0.79
	_place(%DUp, dcx - dpad * 0.5, dcy - dspan - dpad * 0.5, dpad, dpad)
	_place(%DDown, dcx - dpad * 0.5, dcy + dspan - dpad * 0.5, dpad, dpad)
	_place(%DLeft, dcx - dspan - dpad * 0.5, dcy - dpad * 0.5, dpad, dpad)
	_place(%DRight, dcx + dspan - dpad * 0.5, dcy - dpad * 0.5, dpad, dpad)

	# Face diamond on the right.
	var fspan: float = face * 1.05
	_place(%BtnY, right_cx - face * 0.5, cluster_y - fspan - face * 0.5, face, face)
	_place(%BtnA, right_cx - face * 0.5, cluster_y + fspan - face * 0.5, face, face)
	_place(%BtnX, right_cx - fspan - face * 0.5, cluster_y - face * 0.5, face, face)
	_place(%BtnB, right_cx + fspan - face * 0.5, cluster_y - face * 0.5, face, face)

	# Right stick in the bottom corner, below the face diamond. Its top edge
	# clears the diamond's bottom button so a thumb reaching for the stick never
	# clips the button above it.
	_place(%RightStick, w - margin - rstick, h - margin - rstick, rstick, rstick)

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
