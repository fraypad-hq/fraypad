use fraypad_protocol::{FeedbackPacket, InputPacket};
use godot::prelude::*;
use std::net::UdpSocket;

struct FraypadExtension;

#[gdextension]
unsafe impl ExtensionLibrary for FraypadExtension {}

#[derive(GodotClass)]
#[class(base=Node)]
pub struct FraypadClient {
    base: Base<Node>,
    socket: Option<UdpSocket>,
    server_addr: String,
    player_slot: u16,
    seq_id: u16,
}

#[godot_api]
impl INode for FraypadClient {
    fn init(base: Base<Node>) -> Self {
        Self {
            base,
            socket: None,
            server_addr: String::new(),
            player_slot: 0,
            seq_id: 0,
        }
    }
}

#[godot_api]
impl FraypadClient {
    #[func]
    pub fn set_server(&mut self, addr: GString) {
        self.server_addr = addr.to_string();
    }

    #[func]
    pub fn connect_to_server(&mut self) {
        match UdpSocket::bind("0.0.0.0:0") {
            Ok(sock) => {
                let packet = FeedbackPacket { packet_type: 0, player_id: 0, primary: 0, second: 0 };
                if let Err(e) = sock.send_to(bytemuck::bytes_of(&packet), &self.server_addr) {
                    godot_error!("Fraypad FATAL: send_to failed! Did you enable Internet permission? Error: {e}");
                    return;
                }

                let _ = sock.set_read_timeout(Some(std::time::Duration::from_millis(500)));
                let mut buf = [0u8; 8];
                match sock.recv_from(&mut buf) {
                    Ok((8, _)) => {
                        let ack: &FeedbackPacket = bytemuck::from_bytes(&buf);
                        if ack.packet_type == 0 {
                            self.player_slot = ack.player_id;
                            godot_print!("Fraypad: connected as player {}", self.player_slot + 1);
                        } else {
                            godot_error!("Fraypad FATAL: server full");
                            return;
                        }
                    }
                    Ok((size, _)) => {
                        godot_error!("Fraypad FATAL: Received weird packet of size {}", size);
                        return;
                    }
                    Err(e) => {
                        godot_error!("Fraypad FATAL: Handshake timed out! No response from server. Error: {e}");
                        // We do not return here, we can keep the socket for sending blind inputs
                    }
                }
                
                let _ = sock.set_read_timeout(None);
                self.socket = Some(sock);
            }
            Err(e) => godot_error!("Fraypad FATAL: failed to bind socket: {e}"),
        }
    }

    #[func]
    pub fn send_input(&mut self, packet_type: u16, code: u16, value: i32) {
        let Some(ref sock) = self.socket else {
            godot_warn!("Fraypad: not connected");
            return;
        };

        self.seq_id = self.seq_id.wrapping_add(1);

        let packet = InputPacket {
            packet_type,
            player_id: self.player_slot,
            code,
            seq_id: self.seq_id,
            value,
        };

        if let Err(e) = sock.send_to(bytemuck::bytes_of(&packet), &self.server_addr) {
            godot_error!("Fraypad: send error: {e}");
        }
    }

    #[func]
    pub fn send_key(&mut self, key_code: u16, pressed: bool) {
        self.send_input(0x8001, key_code, if pressed { 1 } else { 0 });
    }

    #[func]
    pub fn send_button(&mut self, btn_code: u16, pressed: bool) {
        self.send_input(0x0001, btn_code, if pressed { 1 } else { 0 });
    }

    #[func]
    pub fn send_stick_left(&mut self, x: f32, y: f32) {
        self.send_input(0x0003, 0, (x.clamp(-1.0, 1.0) * 32767.0) as i32);
        self.send_input(0x0003, 1, (y.clamp(-1.0, 1.0) * 32767.0) as i32);
    }

    #[func]
    pub fn send_stick_right(&mut self, x: f32, y: f32) {
        self.send_input(0x0003, 3, (x.clamp(-1.0, 1.0) * 32767.0) as i32);
        self.send_input(0x0003, 4, (y.clamp(-1.0, 1.0) * 32767.0) as i32);
    }

    #[func]
    pub fn send_trigger_left(&mut self, value: f32) {
        self.send_input(0x0003, 2, (value.clamp(0.0, 1.0) * 255.0) as i32);
    }

    #[func]
    pub fn send_trigger_right(&mut self, value: f32) {
        self.send_input(0x0003, 5, (value.clamp(0.0, 1.0) * 255.0) as i32);
    }

    #[func]
    pub fn send_dpad_x(&mut self, value: i32) {
        self.send_input(0x0003, 16, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_dpad_y(&mut self, value: i32) {
        self.send_input(0x0003, 17, value.clamp(-1, 1));
    }

    #[func]
    pub fn send_mouse_move(&mut self, x: i32, y: i32) {
        self.send_input(0x8002, 0, x);
        self.send_input(0x8002, 1, y);
    }

    #[func]
    pub fn send_scroll(&mut self, vertical: i32, horizontal: i32) {
        self.send_input(0x8002, 8, vertical);
        self.send_input(0x8002, 6, horizontal);
    }
}
