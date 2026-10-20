use std::collections::HashMap;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

use fraypad_protocol::{Packet, PacketKind, RejectReason, codes};
use godot::prelude::*;

struct FraypadExtension;

#[gdextension]
unsafe impl ExtensionLibrary for FraypadExtension {}

/// How long to wait for the server's Welcome before re-sending Hello.
const HELLO_TIMEOUT: Duration = Duration::from_millis(500);
/// How many Hello attempts before giving up on connecting.
const HELLO_ATTEMPTS: u32 = 5;
/// How often to send a keep-alive (and re-send the pad snapshot) once
/// connected. Also bounds how long the server waits before it may evict us.
const HEARTBEAT_INTERVAL: Duration = Duration::from_millis(500);

/// Connection state, advanced one step per frame from `_process`.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum ConnState {
    /// No socket, not trying.
    Disconnected,
    /// Hello sent, awaiting Welcome.
    Connecting,
    /// A slot is assigned; input flows.
    Connected,
}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct FraypadClient {
    base: Base<Node>,
    socket: Option<UdpSocket>,
    server_addr: String,
    state: ConnState,
    /// The slot assigned by the server during the handshake.
    ///
    /// `None` until a handshake succeeds. Input is never sent without a slot,
    /// so a client that cannot reach the server can never impersonate
    /// Player 1.
    player_slot: Option<u16>,
    /// Independent sequence counters per route (gamepad vs keyboard/mouse),
    /// matching how the server de-duplicates.
    seq_gamepad: u16,
    seq_kbm: u16,
    /// Deadline for the current Hello attempt, and how many have been sent.
    hello_deadline: Option<Instant>,
    hello_attempts: u32,
    /// When the last heartbeat went out.
    last_heartbeat: Option<Instant>,
    /// The most recent value sent for each `(event_type, code)`, including the
    /// routing bit in `event_type`. Re-sent in full on resync so a lost packet
    /// self-heals instead of leaving a button stuck.
    state_cache: HashMap<(u16, u16), i32>,
}

#[godot_api]
impl INode for FraypadClient {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            socket: None,
            server_addr: String::new(),
            state: ConnState::Disconnected,
            player_slot: None,
            seq_gamepad: 0,
            seq_kbm: 0,
            hello_deadline: None,
            hello_attempts: 0,
            last_heartbeat: None,
            state_cache: HashMap::new(),
        }
    }

    fn process(&mut self, _delta: f64) {
        self.tick();
    }

    fn exit_tree(&mut self) {
        self.disconnect_from_server();
    }
}

#[godot_api]
impl FraypadClient {
    /// Emitted when the server assigns us a player slot. Argument: slot (0-3).
    #[signal]
    fn connected(slot: i32);

    /// Emitted when the connection ends after having been established.
    #[signal]
    fn disconnected();

    /// Emitted when the server refuses our connection (all slots full).
    #[signal]
    fn rejected();

    /// Emitted when the host asks the phone to vibrate.
    /// Arguments: strong (0-65535), weak (0-65535), duration_ms.
    #[signal]
    fn rumble(strong: i32, weak: i32, duration_ms: i32);

    /// Set the `ip:port` of the Fraypad server.
    #[func]
    pub fn set_server(&mut self, addr: GString) {
        self.server_addr = addr.to_string();
    }

    /// Whether a handshake has assigned this client a player slot.
    #[func]
    pub fn is_connected(&self) -> bool {
        self.state == ConnState::Connected
    }

    /// The assigned player slot (0-3), or `-1` if not connected.
    #[func]
    pub fn player_slot(&self) -> i32 {
        self.player_slot.map_or(-1, i32::from)
    }

    /// Begin connecting. Non-blocking.
    ///
    /// Binds a socket, sends Hello, and returns immediately; the connection is
    /// advanced each frame by `_process`. Watch the `connected`, `rejected`,
    /// and `disconnected` signals for the outcome.
    #[func]
    pub fn connect_to_server(&mut self) {
        // Tear down any prior attempt first.
        self.reset_connection();

        let sock = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(e) => {
                godot_error!("Fraypad: failed to bind socket: {e}");
                return;
            }
        };
        // Non-blocking so the handshake never stalls a frame.
        if let Err(e) = sock.set_nonblocking(true) {
            godot_error!("Fraypad: failed to set socket non-blocking: {e}");
            return;
        }

        self.socket = Some(sock);
        self.state = ConnState::Connecting;
        self.hello_attempts = 0;
        self.send_hello();
    }

    /// Send a disconnect request and drop the socket.
    #[func]
    pub fn disconnect_from_server(&mut self) {
        if let (Some(sock), Some(_)) = (self.socket.as_ref(), self.player_slot) {
            let bye = Packet::new(PacketKind::Bye);
            let _ = sock.send_to(&bye.to_bytes(), &self.server_addr);
        }
        self.reset_connection();
    }

    // ── Input senders ────────────────────────────────────────────────────

    /// Press or release a keyboard key by evdev keycode.
    #[func]
    pub fn send_key(&mut self, key_code: u16, pressed: bool) {
        self.send_input(codes::EV_KEY | codes::ROUTE_KBM, key_code, i32::from(pressed));
    }

    /// Press or release a mouse button.
    #[func]
    pub fn send_mouse_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(codes::EV_KEY | codes::ROUTE_KBM, btn_code, i32::from(pressed));
    }

    /// Press or release a gamepad face/shoulder/menu button.
    #[func]
    pub fn send_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(codes::EV_KEY, btn_code, i32::from(pressed));
    }

    #[func]
    pub fn send_stick_left(&mut self, x: f32, y: f32) {
        self.send_input(codes::EV_ABS, codes::ABS_X, scale_axis(x));
        self.send_input(codes::EV_ABS, codes::ABS_Y, scale_axis(y));
    }

    #[func]
    pub fn send_stick_right(&mut self, x: f32, y: f32) {
        self.send_input(codes::EV_ABS, codes::ABS_RX, scale_axis(x));
        self.send_input(codes::EV_ABS, codes::ABS_RY, scale_axis(y));
    }

    /// Send the left trigger (LT) as an analog value in `0.0..=1.0`.
    ///
    /// Also emits the matching digital `BTN_TL2` edge so apps that only
    /// expect a digital trigger still see LT.
    #[func]
    pub fn send_trigger_left(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::EV_ABS, codes::ABS_Z, scale_trigger(v));
        self.send_button(codes::BTN_TL2, v > 0.5);
    }

    /// Send the right trigger (RT) as an analog value in `0.0..=1.0`.
    ///
    /// Also emits the matching digital `BTN_TR2` edge so apps that only
    /// expect a digital trigger still see RT.
    #[func]
    pub fn send_trigger_right(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::EV_ABS, codes::ABS_RZ, scale_trigger(v));
        self.send_button(codes::BTN_TR2, v > 0.5);
    }

    /// Press or release the left stick click (L3).
    #[func]
    pub fn send_thumb_left(&mut self, pressed: bool) {
        self.send_button(codes::BTN_THUMBL, pressed);
    }

    /// Press or release the right stick click (R3).
    #[func]
    pub fn send_thumb_right(&mut self, pressed: bool) {
        self.send_button(codes::BTN_THUMBR, pressed);
    }

    #[func]
    pub fn send_dpad_x(&mut self, value: i32) {
        self.send_input(codes::EV_ABS, codes::ABS_HAT0X, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_dpad_y(&mut self, value: i32) {
        self.send_input(codes::EV_ABS, codes::ABS_HAT0Y, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        self.send_input(codes::EV_REL | codes::ROUTE_KBM, codes::REL_X, x);
        self.send_input(codes::EV_REL | codes::ROUTE_KBM, codes::REL_Y, y);
    }

    #[func]
    pub fn send_scroll(&mut self, vertical: i32, horizontal: i32) {
        self.send_input(codes::EV_REL | codes::ROUTE_KBM, codes::REL_WHEEL, vertical);
        self.send_input(codes::EV_REL | codes::ROUTE_KBM, codes::REL_HWHEEL, horizontal);
    }

    // ── Connection state machine ─────────────────────────────────────────

    /// Advance the connection one step. Called every frame from `_process`.
    fn tick(&mut self) {
        match self.state {
            ConnState::Disconnected => {}
            ConnState::Connecting => self.tick_connecting(),
            ConnState::Connected => self.tick_connected(),
        }
    }

    fn tick_connecting(&mut self) {
        // Drain anything the server has sent.
        while let Some(packet) = self.poll_packet() {
            match packet.kind() {
                Some(PacketKind::Welcome) => {
                    self.player_slot = Some(packet.player_id);
                    self.state = ConnState::Connected;
                    self.last_heartbeat = Some(Instant::now());
                    // Reset per-route sequence counters to match the fresh
                    // session the server just opened for us.
                    self.seq_gamepad = 0;
                    self.seq_kbm = 0;
                    self.state_cache.clear();
                    godot_print!("Fraypad: connected as player {}", packet.player_id + 1);
                    self.base_mut()
                        .emit_signal("connected", &[i32::from(packet.player_id).to_variant()]);
                    return;
                }
                Some(PacketKind::Reject) => {
                    let reason = packet.value;
                    if reason == RejectReason::ServerFull as i32 {
                        godot_error!("Fraypad: server full, no slot available");
                    } else {
                        godot_error!("Fraypad: server rejected us (reason {reason})");
                    }
                    self.reset_connection();
                    self.base_mut().emit_signal("rejected", &[]);
                    return;
                }
                _ => {} // Ignore stray packets while connecting.
            }
        }

        // No reply yet; re-send Hello on timeout, give up after the attempts.
        if self.hello_deadline.is_some_and(|d| Instant::now() >= d) {
            if self.hello_attempts >= HELLO_ATTEMPTS {
                godot_error!("Fraypad: no response from server after {HELLO_ATTEMPTS} attempts");
                self.reset_connection();
                self.base_mut().emit_signal("disconnected", &[]);
                return;
            }
            self.send_hello();
        }
    }

    fn tick_connected(&mut self) {
        // Handle any server packets (Pong, Rumble, Resync).
        while let Some(packet) = self.poll_packet() {
            match packet.kind() {
                Some(PacketKind::Rumble) => {
                    if let Some((strong, weak, duration_ms)) = packet.rumble_params() {
                        self.base_mut().emit_signal(
                            "rumble",
                            &[
                                i32::from(strong).to_variant(),
                                i32::from(weak).to_variant(),
                                (duration_ms as i32).to_variant(),
                            ],
                        );
                    }
                }
                Some(PacketKind::Resync) => {
                    self.resync_state();
                }
                _ => {} // Pong and anything else needs no action here.
            }
        }

        // Keep-alive and periodic self-healing snapshot.
        if self.last_heartbeat.is_some_and(|t| t.elapsed() >= HEARTBEAT_INTERVAL) {
            self.last_heartbeat = Some(Instant::now());
            let mut hb = Packet::new(PacketKind::Heartbeat);
            hb.value = Instant::now().elapsed().as_millis() as i32;
            self.send_raw(&hb);
            self.resync_state();
        }
    }

    fn send_hello(&mut self) {
        self.hello_attempts += 1;
        self.hello_deadline = Some(Instant::now() + HELLO_TIMEOUT);
        let hello = Packet::new(PacketKind::Hello);
        self.send_raw(&hello);
    }

    /// Send one input event, remember it for resync, and advance the matching
    /// route's sequence counter.
    fn send_input(&mut self, event_type: u16, code: u16, value: i32) {
        if self.state != ConnState::Connected {
            return;
        }
        let Some(slot) = self.player_slot else {
            return;
        };

        let kbm = codes::is_kbm(event_type);
        let seq = if kbm {
            self.seq_kbm = self.seq_kbm.wrapping_add(1);
            self.seq_kbm
        } else {
            self.seq_gamepad = self.seq_gamepad.wrapping_add(1);
            self.seq_gamepad
        };

        let packet = Packet::input(slot, seq, event_type, code, value);
        self.send_raw(&packet);

        // Remember the latest value so a resync can replay it.
        self.state_cache.insert((event_type, code), value);
    }

    /// Re-send every cached input so the server converges on our true state.
    ///
    /// Sent after a Welcome and on each heartbeat. This is what makes lost
    /// UDP packets self-heal: even if an individual Input was dropped, the
    /// next snapshot overwrites the stale value.
    fn resync_state(&mut self) {
        let Some(slot) = self.player_slot else {
            return;
        };
        // Collect to avoid holding a borrow of the cache across sends.
        let entries: Vec<(u16, u16, i32)> = self
            .state_cache
            .iter()
            .map(|(&(event_type, code), &value)| (event_type, code, value))
            .collect();

        for (event_type, code, value) in entries {
            let kbm = codes::is_kbm(event_type);
            let seq = if kbm {
                self.seq_kbm = self.seq_kbm.wrapping_add(1);
                self.seq_kbm
            } else {
                self.seq_gamepad = self.seq_gamepad.wrapping_add(1);
                self.seq_gamepad
            };
            let packet = Packet::input(slot, seq, event_type, code, value);
            self.send_raw(&packet);
        }
    }

    /// Send a packet if a socket exists. Errors are non-fatal (a full send
    /// buffer just drops a UDP datagram; the next resync covers it).
    fn send_raw(&self, packet: &Packet) {
        if let Some(sock) = self.socket.as_ref() {
            let _ = sock.send_to(&packet.to_bytes(), &self.server_addr);
        }
    }

    /// Read one datagram, non-blocking. Returns `None` when nothing is pending
    /// or the packet is malformed.
    fn poll_packet(&self) -> Option<Packet> {
        let sock = self.socket.as_ref()?;
        let mut buf = [0u8; 64];
        match sock.recv_from(&mut buf) {
            Ok((len, _)) => Packet::from_bytes(&buf[..len]),
            Err(_) => None, // WouldBlock (nothing pending) or transient error.
        }
    }

    /// Drop all connection state without sending anything.
    fn reset_connection(&mut self) {
        self.socket = None;
        self.state = ConnState::Disconnected;
        self.player_slot = None;
        self.hello_deadline = None;
        self.hello_attempts = 0;
        self.last_heartbeat = None;
        self.seq_gamepad = 0;
        self.seq_kbm = 0;
        self.state_cache.clear();
    }
}

/// Scale a `-1.0..=1.0` stick axis to the wire's `-32767..=32767` range.
fn scale_axis(v: f32) -> i32 {
    (v.clamp(-1.0, 1.0) * 32767.0).round() as i32
}

/// Scale a `0.0..=1.0` trigger to the wire's `0..=255` range.
fn scale_trigger(v: f32) -> i32 {
    (v.clamp(0.0, 1.0) * 255.0).round() as i32
}
