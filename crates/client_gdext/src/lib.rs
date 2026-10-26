use std::collections::HashMap;
use std::net::UdpSocket;
use std::time::{Duration, Instant};

use fraypad_protocol::{Packet, PacketKind, RejectReason, codes};
use godot::prelude::*;

struct FraypadExtension;

#[gdextension]
unsafe impl ExtensionLibrary for FraypadExtension {}

const HELLO_TIMEOUT: Duration = Duration::from_millis(500);
const HELLO_ATTEMPTS: u32 = 5;
const HEARTBEAT_INTERVAL: Duration = Duration::from_millis(500);
const SERVER_SILENCE_TIMEOUT: Duration = Duration::from_millis(3000);

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
enum ConnState {
    Disconnected,
    Connecting,
    Connected,
}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct FraypadClient {
    base: Base<Node>,
    socket: Option<UdpSocket>,
    server_addr: String,
    state: ConnState,
    player_slot: Option<u16>,
    seq_gamepad: u16,
    seq_kbm: u16,
    hello_deadline: Option<Instant>,
    hello_attempts: u32,
    last_heartbeat: Option<Instant>,
    last_server_contact: Option<Instant>,
    state_cache: HashMap<(u16, u16), i32>,
    start_time: Instant,
    last_ping_ms: i32,
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
            last_server_contact: None,
            state_cache: HashMap::new(),
            start_time: Instant::now(),
            last_ping_ms: -1,
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
    #[signal]
    fn connected(slot: i32);

    #[signal]
    fn disconnected();

    #[signal]
    fn rejected(reason: i32);

    #[signal]
    fn rumble(strong: i32, weak: i32, duration_ms: i32);

    #[signal]
    fn ping_updated(ping_ms: i32);

    #[func]
    #[allow(clippy::needless_pass_by_value)]
    pub fn set_server(&mut self, addr: GString) {
        self.server_addr = addr.to_string();
    }

    #[must_use]
    #[func]
    pub fn is_connected(&self) -> bool {
        self.state == ConnState::Connected
    }

    #[must_use]
    #[func]
    pub fn player_slot(&self) -> i32 {
        self.player_slot.map_or(-1, i32::from)
    }

    #[must_use]
    #[func]
    #[allow(clippy::missing_const_for_fn)]
    pub fn ping_ms(&self) -> i32 {
        self.last_ping_ms
    }

    #[func]
    pub fn connect_to_server(&mut self) {
        self.reset_connection();

        let sock = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(e) => {
                godot_error!("Fraypad: failed to bind socket: {e}");
                self.base_mut().emit_signal("disconnected", &[]);
                return;
            }
        };
        if let Err(e) = sock.set_nonblocking(true) {
            godot_error!("Fraypad: failed to set socket non-blocking: {e}");
            self.base_mut().emit_signal("disconnected", &[]);
            return;
        }

        self.socket = Some(sock);
        self.state = ConnState::Connecting;
        self.hello_attempts = 0;
        self.send_hello();
    }

    #[func]
    pub fn disconnect_from_server(&mut self) {
        if let (Some(sock), Some(_)) = (self.socket.as_ref(), self.player_slot) {
            let bye = Packet::new(PacketKind::Bye);
            let _ = sock.send_to(&bye.to_bytes(), &self.server_addr);
        }
        self.reset_connection();
    }

    #[func]
    pub fn send_key(&mut self, key_code: u16, pressed: bool) {
        self.send_input(
            codes::EV_KEY | codes::ROUTE_KBM,
            key_code,
            i32::from(pressed),
        );
    }

    #[func]
    pub fn send_mouse_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(
            codes::EV_KEY | codes::ROUTE_KBM,
            btn_code,
            i32::from(pressed),
        );
    }

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

    #[func]
    pub fn send_trigger_left(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::EV_ABS, codes::ABS_Z, scale_trigger(v));
        self.send_button(codes::BTN_TL2, v > 0.5);
    }

    #[func]
    pub fn send_trigger_right(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::EV_ABS, codes::ABS_RZ, scale_trigger(v));
        self.send_button(codes::BTN_TR2, v > 0.5);
    }

    #[func]
    pub fn send_thumb_left(&mut self, pressed: bool) {
        self.send_button(codes::BTN_THUMBL, pressed);
    }

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
        self.send_input(
            codes::EV_REL | codes::ROUTE_KBM,
            codes::REL_HWHEEL,
            horizontal,
        );
    }

    fn tick(&mut self) {
        match self.state {
            ConnState::Disconnected => {}
            ConnState::Connecting => self.tick_connecting(),
            ConnState::Connected => self.tick_connected(),
        }
    }

    fn tick_connecting(&mut self) {
        while let Some(packet) = self.poll_packet() {
            match packet.kind() {
                Some(PacketKind::Welcome) => {
                    self.player_slot = Some(packet.player_id);
                    self.state = ConnState::Connected;
                    self.last_heartbeat = Some(Instant::now());
                    self.last_server_contact = Some(Instant::now());
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
                    self.base_mut()
                        .emit_signal("rejected", &[reason.to_variant()]);
                    return;
                }
                _ => {}
            }
        }

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
        let mut heard_from_server = false;
        while let Some(packet) = self.poll_packet() {
            heard_from_server = true;
            match packet.kind() {
                Some(PacketKind::Rumble) => {
                    if let Some((strong, weak, duration_ms)) = packet.rumble_params() {
                        self.base_mut().emit_signal(
                            "rumble",
                            &[
                                i32::from(strong).to_variant(),
                                i32::from(weak).to_variant(),
                                (duration_ms.cast_signed()).to_variant(),
                            ],
                        );
                    }
                }
                Some(PacketKind::Resync) => {
                    self.resync_state();
                }
                Some(PacketKind::Pong) => {
                    let sent_time = packet.value;
                    let now_ms =
                        i32::try_from(self.start_time.elapsed().as_millis()).unwrap_or(i32::MAX);
                    let rtt = (now_ms - sent_time).max(0);
                    self.last_ping_ms = rtt;
                    self.base_mut()
                        .emit_signal("ping_updated", &[rtt.to_variant()]);
                }
                _ => {}
            }
        }
        if heard_from_server {
            self.last_server_contact = Some(Instant::now());
        }

        if self
            .last_heartbeat
            .is_some_and(|t| t.elapsed() >= HEARTBEAT_INTERVAL)
        {
            self.last_heartbeat = Some(Instant::now());
            let mut hb = Packet::new(PacketKind::Heartbeat);
            hb.value = i32::try_from(self.start_time.elapsed().as_millis()).unwrap_or(i32::MAX);
            self.send_raw(&hb);
            self.resync_state();
        }

        if self
            .last_server_contact
            .is_some_and(|t| t.elapsed() >= SERVER_SILENCE_TIMEOUT)
        {
            godot_error!("Fraypad: lost contact with the server");
            self.reset_connection();
            self.base_mut().emit_signal("disconnected", &[]);
        }
    }

    fn send_hello(&mut self) {
        self.hello_attempts += 1;
        self.hello_deadline = Some(Instant::now() + HELLO_TIMEOUT);
        let hello = Packet::new(PacketKind::Hello);
        self.send_raw(&hello);
    }

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

        if codes::event_type(event_type) != codes::EV_REL {
            self.state_cache.insert((event_type, code), value);
        }
    }

    fn resync_state(&mut self) {
        let Some(slot) = self.player_slot else {
            return;
        };
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

    fn send_raw(&self, packet: &Packet) {
        if let Some(sock) = self.socket.as_ref() {
            let _ = sock.send_to(&packet.to_bytes(), &self.server_addr);
        }
    }

    fn poll_packet(&self) -> Option<Packet> {
        let sock = self.socket.as_ref()?;
        let mut buf = [0u8; 64];
        match sock.recv_from(&mut buf) {
            Ok((len, _)) => Packet::from_bytes(&buf[..len]),
            Err(_) => None,
        }
    }

    fn reset_connection(&mut self) {
        self.socket = None;
        self.state = ConnState::Disconnected;
        self.player_slot = None;
        self.hello_deadline = None;
        self.hello_attempts = 0;
        self.last_heartbeat = None;
        self.last_server_contact = None;
        self.seq_gamepad = 0;
        self.seq_kbm = 0;
        self.state_cache.clear();
        self.last_ping_ms = -1;
    }
}

#[allow(clippy::cast_possible_truncation)]
fn scale_axis(v: f32) -> i32 {
    (v.clamp(-1.0, 1.0) * 32767.0).round() as i32
}

#[allow(clippy::cast_possible_truncation)]
fn scale_trigger(v: f32) -> i32 {
    (v.clamp(0.0, 1.0) * 255.0).round() as i32
}
