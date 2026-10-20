# Fraypad

Use your phone as an Xbox 360 controller for your PC.

Fraypad turns a Godot app running on an Android phone into a wireless gamepad.
A server on your Linux PC receives the input over UDP and re-emits it through a
virtual `uinput` device that is spoofed to look like a Microsoft Xbox 360
controller, so games see a normal X360 pad.

```
 ┌─────────────────────┐   UDP :54321   ┌──────────────────────────┐
 │  Phone (Godot app)  │ ─────────────► │  PC (fraypad server)     │
 │  crates/client_gdext│ ◄───────────── │  crates/server_evdev     │
 └─────────────────────┘   handshake,   └────────────┬─────────────┘
                        heartbeat, rumble            │ uinput
                                                     ▼
                                        4× virtual X360 pad + MouseBoard
```

Status: usable. The gamepad path, rumble (force-feedback from games vibrates
the phone), reliable sessions (handshake, heartbeats, eviction, resync), and a
keyboard/mouse mode all work end to end. See "Playing" for how to point the app
at your PC.

## Repository layout

| Path                        | What it is                                                     |
| --------------------------- | -------------------------------------------------------------- |
| `crates/fraypad_protocol`   | Wire format shared by client and server (packets + evdev codes). |
| `crates/fraypad_server_core` | Backend-agnostic server logic: sessions, routing, eviction.    |
| `crates/client_gdext`       | Godot GDExtension (Rust) — the phone-side networking client.     |
| `crates/server_evdev`       | Linux server (`fraypad` binary) — receives UDP, drives `uinput`. |
| `godot/`                    | The Android app: UI scene, virtual sticks/buttons, GDScript.     |
| `scripts/`                  | Android toolchain setup and build.                               |

## Running the server (Linux PC)

The server needs permission to create `uinput` devices. Either run as root, or
install the udev rule below (preferred):

```sh
sudo bash -c 'cat > /etc/udev/rules.d/99-fraypad.rules <<EOF
KERNEL=="uinput", MODE="0660", GROUP="input", OPTIONS+="static_node=uinput"
EOF'
sudo usermod -aG input "$USER"   # then log out and back in
```

Then start it:

```sh
cargo run --release -p fraypad
# Server listening on port 54321
```

A shared `Fraypad MouseBoard` is created at startup. Each `Fraypad Gamepad
(P1..P4)` appears when a phone connects and is torn down when it leaves, so
`/dev/input` only lists pads that are actually in use. Verify with:

```sh
sudo evtest                      # pick a Fraypad device and wiggle inputs
sdl2-jstest --list               # games see it as an Xbox 360 controller
```

To debug without `sudo`, add your user to the `input` group (the udev rule
above does this) and log back in; otherwise reading the virtual devices
requires root even though the server itself does not.

Your firewall must allow inbound **UDP 54321** on the LAN, and the PC and phone
must be on the same network.

## Building the phone app (Android)

Two steps: provision the toolchain once, then build.

```sh
./scripts/setup-android.sh      # SDK, NDK, build-tools, debug keystore, templates
./scripts/build-android.sh      # cross-compile the client + export the APK
# -> godot/export/fraypad-android.apk
```

Install and run it:

```sh
adb install -r godot/export/fraypad-android.apk
adb shell am start -n com.fraypad.app/com.godot.game.GodotApp
```

> If you previously saw `Unable to open Android 'build-tools' directory`, that
> means the SDK was not installed where Godot expects. `setup-android.sh`
> installs `build-tools`, `platforms`, `platform-tools`, and the NDK under
> `~/android` (override with `ANDROID_SDK_ROOT`). The pacman `android-tools`
> package only ships `adb`/`fastboot` and is **not** sufficient on its own.

### Toolchain requirements

- Godot **4.7.x** (the project's feature tag and export templates must match
  your editor version)
- A JDK (for `keytool` and `apksigner`)
- [`cargo-ndk`](https://github.com/bbqsrc/cargo-ndk) for cross-compiling

`setup-android.sh` is idempotent and prints the exact paths to plug into
Godot's Editor Settings if you prefer doing it by hand.

### Build flags

| Variable            | Default                         | Effect                                  |
| ------------------- | ------------------------------- | --------------------------------------- |
| `RELEASE=1`         | `0`                             | Optimized build + release export.        |
| `APK_OUT`           | `godot/export/fraypad-android.apk` | Where to write the APK.               |
| `ANDROID_SDK_ROOT`  | `~/android`                     | SDK root.                                |
| `ANDROID_NDK_HOME`  | `<sdk>/ndk/<ndk>`               | NDK directory.                           |
| `ANDROID_NDK`       | `28.2.13676358`                 | NDK version.                             |
| `ANDROID_API`       | `36`                            | Platform / build-tools API level (setup). |
| `ANDROID_BUILD_TOOLS` | `36.0.0`                      | build-tools revision (setup).            |
| `SKIP_TEMPLATES=1`  | `0`                             | Skip the ~1.2 GB export-template download (setup). |
| `GODOT_BIN`         | `godot`                         | Godot executable.                        |

`build-android.sh` refuses to succeed if the exported APK does not contain a
real (non-empty) `libclient_gdext.so`, because Godot will silently package a
0-byte placeholder when the native library is missing.

A `RELEASE=1` export is signed with a local self-signed keystore that
`setup-android.sh` generates at `~/.android/fraypad-release.keystore`. Override
the path with `FRAYPAD_RELEASE_KEYSTORE` and the credentials with
`FRAYPAD_RELEASE_KEYSTORE_USER` / `FRAYPAD_RELEASE_KEYSTORE_PASSWORD`. Swap in
your own keystore before distributing.

## Playing

Launch the app on the phone and the PC server at the same time; the app
connects on startup and is assigned one of four slots. Press any button to
drive the matching virtual pad on the PC.

The first time it runs, the app uses a placeholder server address. Tap the ⚙
button, enter your PC's LAN IP and port (e.g. `192.168.1.10:54321`), and hit
**Save & Connect**. The address is stored on the phone, so you only set it
once. The status line at the top shows the connection state and offers a retry
when the server is unreachable.

### Keyboard & mouse

Tap the ⌨ button to swap the whole pad for a keyboard/mouse surface; the button
becomes 🎮 and swaps back. Switching releases anything the hidden side was
holding, so nothing sticks on the PC.

The surface is a trackpad on the left and a QWERTY keyboard on the right:

- **Trackpad** — drag to move the cursor, tap to left-click, two-finger drag to
  scroll. The keyboard covers keys, modifiers, and arrows, so you can type and
  play with the same screen.

Both modes share the connection, so you can flip mid-game.

## Protocol

The wire format is defined in `crates/fraypad_protocol`. Everything is a single
fixed-size 16-byte little-endian `Packet`, so there is one datagram type on one
UDP socket:

```
offset  size  field        meaning
  0      2    magic        0xF3A9 sanity check
  2      1    version      protocol version (bumped on any layout change)
  3      1    kind         PacketKind discriminant
  4      2    player_id    controller slot (0..=3) when assigned
  6      2    seq_id       wrapping per-route sequence (Input only)
  8      2    event_type   evdev type; bit 15 = keyboard/mouse route
 10      2    code         evdev code (Input) / strong rumble magnitude
 12      4    value        evdev value (Input) / payload
```

`kind` selects the meaning: `Hello`/`Welcome`/`Reject`/`Bye` drive the
handshake, `Input` carries an evdev event, `Heartbeat`/`Pong` keep the session
alive and measure liveness, `Rumble` vibrates the phone, and `Resync` asks the
client to re-send its whole input state (used after connecting and to self-heal
lost UDP packets).

The client's player slot is assigned by the server during the handshake. The
server keys each session on the client's source `SocketAddr` and resolves the
slot from that, so packets cannot be spoofed into another player's pad.

Keyboard/mouse events share the `Input` kind; bit 15 of `event_type` routes the
event to the MouseBoard instead of a gamepad.

## License

Apache-2.0. See [LICENSE](LICENSE).
