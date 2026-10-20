use std::net::UdpSocket;
use std::time::Duration;

use fraypad_protocol::{FeedbackPacket, InputPacket, codes};
use godot::prelude::*;

struct FraypadExtension;

#[gdextension]
unsafe impl ExtensionLibrary for FraypadExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct FraypadClient {
    base: Base<Node>,
    socket: Option<UdpSocket>,
    server_addr: String,
    /// The slot assigned by the server during the handshake.
    ///
    /// `None` until a handshake succeeds. Input is never sent without a slot,
    /// so a client that cannot reach the server can never impersonate
    /// Player 1.
    player_slot: Option<u16>,
    seq_id: u16,
}

#[godot_api]
impl INode for FraypadClient {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            socket: None,
            server_addr: String::new(),
            player_slot: None,
            seq_id: 0,
        }
    }

    fn exit_tree(&mut self) {
        self.disconnect_from_server();
    }
}

#[godot_api]
impl FraypadClient {
    /// Set the `ip:port` of the Fraypad server.
    #[func]
    pub fn set_server(&mut self, addr: GString) {
        self.server_addr = addr.to_string();
    }

    /// Whether a handshake has assigned this client a player slot.
    #[func]
    pub fn is_connected(&self) -> bool {
        self.player_slot.is_some()
    }

    /// The assigned player slot (0-3), or `-1` if not connected.
    #[func]
    pub fn player_slot(&self) -> i32 {
        self.player_slot.map_or(-1, i32::from)
    }

    /// Send a connect request and block briefly for the server's ack.
    ///
    /// On success the assigned slot is stored and `is_connected()` becomes
    /// true. On timeout or rejection the socket is dropped, so no input can
    /// be sent until a later `connect_to_server()` succeeds.
    #[func]
    pub fn connect_to_server(&mut self) {
        self.player_slot = None;

        let sock = match UdpSocket::bind("0.0.0.0:0") {
            Ok(s) => s,
            Err(e) => {
                godot_error!("Fraypad: failed to bind socket: {e}");
                return;
            }
        };

        let hello = FeedbackPacket {
            packet_type: 0,
            player_id: 0,
            primary: 0,
            second: 0,
        };
        if let Err(e) = sock.send_to(bytemuck::bytes_of(&hello), &self.server_addr) {
            godot_error!("Fraypad: send_to failed! Did you enable Internet permission? Error: {e}");
            return;
        }

        let _ = sock.set_read_timeout(Some(Duration::from_millis(500)));
        let mut buf = [0u8; 8];
        match sock.recv_from(&mut buf) {
            Ok((8, _)) => {
                let ack: &FeedbackPacket = bytemuck::from_bytes(&buf);
                match ack.packet_type {
                    0 => {
                        self.player_slot = Some(ack.player_id);
                        godot_print!("Fraypad: connected as player {}", ack.player_id + 1);
                    }
                    2 => {
                        godot_error!("Fraypad: server full, no slot available");
                        return;
                    }
                    other => {
                        godot_error!("Fraypad: unexpected handshake reply type {other}");
                        return;
                    }
                }
            }
            Ok((size, _)) => {
                godot_error!("Fraypad: received malformed handshake reply of {size} bytes");
                return;
            }
            Err(e) => {
                // No server reachable. Drop the socket: sending blind would
                // either be dropped anyway or, worse, fight over a slot.
                godot_error!("Fraypad: handshake timed out, no response from server. Error: {e}");
                return;
            }
        }

        let _ = sock.set_read_timeout(None);
        self.socket = Some(sock);
    }

    /// Send a disconnect request and drop the socket.
    #[func]
    pub fn disconnect_from_server(&mut self) {
        if let (Some(sock), Some(_slot)) = (self.socket.as_ref(), self.player_slot) {
            let bye = FeedbackPacket {
                packet_type: 1,
                player_id: 0,
                primary: 0,
                second: 0,
            };
            let _ = sock.send_to(bytemuck::bytes_of(&bye), &self.server_addr);
        }
        self.socket = None;
        self.player_slot = None;
    }

    fn send_input(&mut self, packet_type: u16, code: u16, value: i32) {
        let (Some(sock), Some(slot)) = (self.socket.as_ref(), self.player_slot) else {
            return;
        };

        self.seq_id = self.seq_id.wrapping_add(1);

        let packet = InputPacket {
            packet_type,
            player_id: slot,
            code,
            seq_id: self.seq_id,
            value,
        };

        if let Err(e) = sock.send_to(bytemuck::bytes_of(&packet), &self.server_addr) {
            godot_error!("Fraypad: send error: {e}");
        }
    }

    /// Press or release a keyboard key by evdev keycode.
    #[func]
    pub fn send_key(&mut self, key_code: u16, pressed: bool) {
        self.send_input(codes::kbm(codes::EV_KEY), key_code, i32::from(pressed));
    }

    /// Press or release a mouse button.
    #[func]
    pub fn send_mouse_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(codes::kbm(codes::EV_KEY), btn_code, i32::from(pressed));
    }

    /// Press or release a gamepad face/shoulder/menu button.
    #[func]
    pub fn send_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(codes::gamepad(codes::EV_KEY), btn_code, i32::from(pressed));
    }

    #[func]
    pub fn send_stick_left(&mut self, x: f32, y: f32) {
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_X, scale_axis(x));
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_Y, scale_axis(y));
    }

    #[func]
    pub fn send_stick_right(&mut self, x: f32, y: f32) {
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_RX, scale_axis(x));
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_RY, scale_axis(y));
    }

    /// Send the left trigger (LT) as an analog value in `0.0..=1.0`.
    ///
    /// Also emits the matching digital `BTN_TL2` edge so apps that only
    /// expect a digital trigger still see LT.
    #[func]
    pub fn send_trigger_left(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_Z, scale_trigger(v));
        self.send_button(codes::BTN_TL2, v > 0.5);
    }

    /// Send the right trigger (RT) as an analog value in `0.0..=1.0`.
    ///
    /// Also emits the matching digital `BTN_TR2` edge so apps that only
    /// expect a digital trigger still see RT.
    #[func]
    pub fn send_trigger_right(&mut self, value: f32) {
        let v = value.clamp(0.0, 1.0);
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_RZ, scale_trigger(v));
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
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_HAT0X, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_dpad_y(&mut self, value: i32) {
        self.send_input(codes::gamepad(codes::EV_ABS), codes::ABS_HAT0Y, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        self.send_input(codes::kbm(codes::EV_REL), codes::REL_X, x);
        self.send_input(codes::kbm(codes::EV_REL), codes::REL_Y, y);
    }

    #[func]
    pub fn send_scroll(&mut self, vertical: i32, horizontal: i32) {
        self.send_input(codes::kbm(codes::EV_REL), codes::REL_WHEEL, vertical);
        self.send_input(codes::kbm(codes::EV_REL), codes::REL_HWHEEL, horizontal);
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
