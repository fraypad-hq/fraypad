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

Status: early development. The gamepad path works end to end; rumble,
keyboard/mouse mode, and session resilience are in progress.

## Repository layout

| Path                        | What it is                                                     |
| --------------------------- | -------------------------------------------------------------- |
| `crates/fraypad_protocol`   | Wire format shared by client and server (packets + evdev codes). |
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
# Fraypad server listening on 0.0.0.0:54321
```

Four virtual pads are created at startup, named `Fraypad Gamepad (P1..P4)`, and
one shared `Fraypad MouseBoard`. Verify with:

```sh
sudo evtest                      # pick a Fraypad device and wiggle inputs
sdl2-jstest --list               # games see it as an Xbox 360 controller
```

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
adb shell am start -n com.fraypad.app/com.godot.game.MainActivity
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
| `GODOT_BIN`         | `godot`                         | Godot executable.                        |

`build-android.sh` refuses to succeed if the exported APK does not contain a
real (non-empty) `libclient_gdext.so`, because Godot will silently package a
0-byte placeholder when the native library is missing.

## Playing

Launch the app on the phone and the PC server at the same time; the app
connects on startup and is assigned one of four slots. Press any button to
drive the matching virtual pad on the PC.

> The server address is currently hardcoded in `godot/main.gd`. Point it at
> your PC's LAN IP before building.

## Protocol

The wire format is defined in `crates/fraypad_protocol`. Two fixed-size little-endian
packets share one UDP socket, distinguished by datagram length:

- `InputPacket` (12 bytes) — a single input event: a Linux evdev type/code/value
  triple plus the sender's slot and a wrapping sequence id used to drop
  duplicate or out-of-order packets.
- `FeedbackPacket` (8 bytes) — signalling and control: connect (with slot
  assignment), disconnect, rejected (server full), and rumble.

The client's player slot is assigned by the server during the handshake. The
server keys each session on the client's source `SocketAddr` and resolves the
slot from that, so packets cannot be spoofed into another player's pad.

Keyboard/mouse events share the `InputPacket` format; bit 15 of `packet_type`
routes the event to the MouseBoard instead of a gamepad.

## License

Apache-2.0. See [LICENSE](LICENSE).
