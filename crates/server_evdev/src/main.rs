//! # Fraypad
//!
//! UDP server that receives input packets from Fraypad clients
//! and emits them as virtual input events via Linux uinput.

use std::net::{SocketAddr, UdpSocket};

use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, FFEffectCode, InputEvent, KeyCode, RelativeAxisCode,
    UinputAbsSetup, uinput::VirtualDevice,
};

use anyhow::{Context, Result};
use fraypad_protocol::{FeedbackPacket, InputPacket};

fn build_gamepad(player_num: usize) -> Result<VirtualDevice> {
    let mut keys = AttributeSet::new();

    keys.insert(KeyCode::BTN_SOUTH);
    keys.insert(KeyCode::BTN_EAST);
    keys.insert(KeyCode::BTN_NORTH);
    keys.insert(KeyCode::BTN_WEST);

    keys.insert(KeyCode::BTN_TL);
    keys.insert(KeyCode::BTN_TR);
    keys.insert(KeyCode::BTN_TL2);
    keys.insert(KeyCode::BTN_TR2);
    keys.insert(KeyCode::BTN_SELECT);
    keys.insert(KeyCode::BTN_START);
    keys.insert(KeyCode::BTN_MODE);
    keys.insert(KeyCode::BTN_THUMBL);
    keys.insert(KeyCode::BTN_THUMBR);

    let mut ff = AttributeSet::new();
    ff.insert(FFEffectCode::FF_RUMBLE);

    let stick_setup = AbsInfo::new(0, -32768, 32767, 16, 128, 0);
    let abs_x = UinputAbsSetup::new(AbsoluteAxisCode::ABS_X, stick_setup);
    let abs_y = UinputAbsSetup::new(AbsoluteAxisCode::ABS_Y, stick_setup);
    let abs_rx = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RX, stick_setup);
    let abs_ry = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RY, stick_setup);

    let trigger_setup = AbsInfo::new(0, 0, 255, 0, 0, 0);
    let abs_z = UinputAbsSetup::new(AbsoluteAxisCode::ABS_Z, trigger_setup);
    let abs_rz = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RZ, trigger_setup);

    let hat_setup = AbsInfo::new(0, -1, 1, 0, 0, 0);
    let abs_hat0x = UinputAbsSetup::new(AbsoluteAxisCode::ABS_HAT0X, hat_setup);
    let abs_hat0y = UinputAbsSetup::new(AbsoluteAxisCode::ABS_HAT0Y, hat_setup);

    let name = format!("Fraypad Gamepad (P{})", player_num + 1);

    // Spoofing a Microsoft Xbox 360 controller
    let input_id = evdev::InputId::new(evdev::BusType::BUS_USB, 0x045E, 0x028E, 0x0110);

    VirtualDevice::builder()?
        .name(&name)
        .input_id(input_id)
        .with_keys(&keys)?
        .with_ff(&ff)?
        .with_ff_effects_max(16)
        .with_absolute_axis(&abs_x)?
        .with_absolute_axis(&abs_y)?
        .with_absolute_axis(&abs_rx)?
        .with_absolute_axis(&abs_ry)?
        .with_absolute_axis(&abs_z)?
        .with_absolute_axis(&abs_rz)?
        .with_absolute_axis(&abs_hat0x)?
        .with_absolute_axis(&abs_hat0y)?
        .build()
        .context("Failed to build virtual gamepad. Do you have uinput permissions?")
}


#[allow(clippy::too_many_lines)]
fn build_mouseboard() -> Result<VirtualDevice> {
    let mut keys = AttributeSet::new();

    keys.insert(KeyCode::BTN_LEFT);
    keys.insert(KeyCode::BTN_RIGHT);
    keys.insert(KeyCode::BTN_MIDDLE);

    let mut axes = AttributeSet::new();
    axes.insert(RelativeAxisCode::REL_X);
    axes.insert(RelativeAxisCode::REL_Y);
    axes.insert(RelativeAxisCode::REL_WHEEL);
    axes.insert(RelativeAxisCode::REL_HWHEEL);

    keys.insert(KeyCode::KEY_A);
    keys.insert(KeyCode::KEY_B);
    keys.insert(KeyCode::KEY_C);
    keys.insert(KeyCode::KEY_D);
    keys.insert(KeyCode::KEY_E);
    keys.insert(KeyCode::KEY_F);
    keys.insert(KeyCode::KEY_G);
    keys.insert(KeyCode::KEY_H);
    keys.insert(KeyCode::KEY_I);
    keys.insert(KeyCode::KEY_J);
    keys.insert(KeyCode::KEY_K);
    keys.insert(KeyCode::KEY_L);
    keys.insert(KeyCode::KEY_M);
    keys.insert(KeyCode::KEY_N);
    keys.insert(KeyCode::KEY_O);
    keys.insert(KeyCode::KEY_P);
    keys.insert(KeyCode::KEY_Q);
    keys.insert(KeyCode::KEY_R);
    keys.insert(KeyCode::KEY_S);
    keys.insert(KeyCode::KEY_T);
    keys.insert(KeyCode::KEY_U);
    keys.insert(KeyCode::KEY_V);
    keys.insert(KeyCode::KEY_W);
    keys.insert(KeyCode::KEY_X);
    keys.insert(KeyCode::KEY_Y);
    keys.insert(KeyCode::KEY_Z);

    keys.insert(KeyCode::KEY_0);
    keys.insert(KeyCode::KEY_1);
    keys.insert(KeyCode::KEY_2);
    keys.insert(KeyCode::KEY_3);
    keys.insert(KeyCode::KEY_4);
    keys.insert(KeyCode::KEY_5);
    keys.insert(KeyCode::KEY_6);
    keys.insert(KeyCode::KEY_7);
    keys.insert(KeyCode::KEY_8);
    keys.insert(KeyCode::KEY_9);

    keys.insert(KeyCode::KEY_GRAVE);
    keys.insert(KeyCode::KEY_MINUS);
    keys.insert(KeyCode::KEY_EQUAL);
    keys.insert(KeyCode::KEY_LEFTBRACE);
    keys.insert(KeyCode::KEY_RIGHTBRACE);
    keys.insert(KeyCode::KEY_BACKSLASH);
    keys.insert(KeyCode::KEY_SEMICOLON);
    keys.insert(KeyCode::KEY_APOSTROPHE);
    keys.insert(KeyCode::KEY_COMMA);
    keys.insert(KeyCode::KEY_DOT);
    keys.insert(KeyCode::KEY_SLASH);

    keys.insert(KeyCode::KEY_ESC);
    keys.insert(KeyCode::KEY_TAB);
    keys.insert(KeyCode::KEY_CAPSLOCK);
    keys.insert(KeyCode::KEY_ENTER);
    keys.insert(KeyCode::KEY_BACKSPACE);
    keys.insert(KeyCode::KEY_SPACE);

    keys.insert(KeyCode::KEY_LEFTSHIFT);
    keys.insert(KeyCode::KEY_RIGHTSHIFT);
    keys.insert(KeyCode::KEY_LEFTCTRL);
    keys.insert(KeyCode::KEY_RIGHTCTRL);
    keys.insert(KeyCode::KEY_LEFTALT);
    keys.insert(KeyCode::KEY_RIGHTALT);
    keys.insert(KeyCode::KEY_LEFTMETA);
    keys.insert(KeyCode::KEY_RIGHTMETA);
    keys.insert(KeyCode::KEY_COMPOSE);

    keys.insert(KeyCode::KEY_F1);
    keys.insert(KeyCode::KEY_F2);
    keys.insert(KeyCode::KEY_F3);
    keys.insert(KeyCode::KEY_F4);
    keys.insert(KeyCode::KEY_F5);
    keys.insert(KeyCode::KEY_F6);
    keys.insert(KeyCode::KEY_F7);
    keys.insert(KeyCode::KEY_F8);
    keys.insert(KeyCode::KEY_F9);
    keys.insert(KeyCode::KEY_F10);
    keys.insert(KeyCode::KEY_F11);
    keys.insert(KeyCode::KEY_F12);

    keys.insert(KeyCode::KEY_SYSRQ);
    keys.insert(KeyCode::KEY_SCROLLLOCK);
    keys.insert(KeyCode::KEY_PAUSE);
    keys.insert(KeyCode::KEY_INSERT);
    keys.insert(KeyCode::KEY_DELETE);
    keys.insert(KeyCode::KEY_HOME);
    keys.insert(KeyCode::KEY_END);
    keys.insert(KeyCode::KEY_PAGEUP);
    keys.insert(KeyCode::KEY_PAGEDOWN);

    keys.insert(KeyCode::KEY_UP);
    keys.insert(KeyCode::KEY_DOWN);
    keys.insert(KeyCode::KEY_LEFT);
    keys.insert(KeyCode::KEY_RIGHT);

    keys.insert(KeyCode::KEY_NUMLOCK);
    keys.insert(KeyCode::KEY_KPSLASH);
    keys.insert(KeyCode::KEY_KPASTERISK);
    keys.insert(KeyCode::KEY_KPMINUS);
    keys.insert(KeyCode::KEY_KPPLUS);
    keys.insert(KeyCode::KEY_KPENTER);
    keys.insert(KeyCode::KEY_KP0);
    keys.insert(KeyCode::KEY_KP1);
    keys.insert(KeyCode::KEY_KP2);
    keys.insert(KeyCode::KEY_KP3);
    keys.insert(KeyCode::KEY_KP4);
    keys.insert(KeyCode::KEY_KP5);
    keys.insert(KeyCode::KEY_KP6);
    keys.insert(KeyCode::KEY_KP7);
    keys.insert(KeyCode::KEY_KP8);
    keys.insert(KeyCode::KEY_KP9);
    keys.insert(KeyCode::KEY_KPDOT);

    keys.insert(KeyCode::KEY_PLAYPAUSE);
    keys.insert(KeyCode::KEY_STOPCD);
    keys.insert(KeyCode::KEY_PREVIOUSSONG);
    keys.insert(KeyCode::KEY_NEXTSONG);
    keys.insert(KeyCode::KEY_MUTE);
    keys.insert(KeyCode::KEY_VOLUMEDOWN);
    keys.insert(KeyCode::KEY_VOLUMEUP);

    let name = "Fraypad MouseBoard";

    VirtualDevice::builder()?
        .name(name)
        .with_keys(&keys)?
        .with_relative_axes(&axes)?
        .build()
        .context("Failed to build virtual mouseboard. Do you have uinput permissions?")
}

enum ConnectOutcome {
    Connected(usize),
    Reconnected(usize),
    Rejected,
}

/// Pure session state, separated from device I/O for testability.
struct SessionTable {
    clients: [Option<SocketAddr>; 4],
    last_gamepad_seq_ids: [u16; 4],
    last_kbm_seq_ids: [u16; 4],
}

impl SessionTable {
    fn new() -> Self {
        Self {
            clients: [None; 4],
            last_gamepad_seq_ids: [0; 4],
            last_kbm_seq_ids: [0; 4],
        }
    }

    fn connect(&mut self, src_addr: SocketAddr) -> ConnectOutcome {
        if let Some(slot) = self.clients.iter().position(|c| *c == Some(src_addr)) {
            // A reconnect starts a fresh sequence so the client's counter
            // (which also restarts at 0) is not rejected as stale.
            self.last_gamepad_seq_ids[slot] = 0;
            self.last_kbm_seq_ids[slot] = 0;
            return ConnectOutcome::Reconnected(slot);
        }
        if let Some(slot) = self.clients.iter().position(|c| c.is_none()) {
            self.clients[slot] = Some(src_addr);
            return ConnectOutcome::Connected(slot);
        }
        ConnectOutcome::Rejected
    }

    /// Resolve a sender's address to its assigned slot, if any.
    fn slot_of(&self, src_addr: SocketAddr) -> Option<usize> {
        self.clients.iter().position(|c| *c == Some(src_addr))
    }

    fn disconnect(&mut self, src_addr: SocketAddr) -> Option<usize> {
        let slot = self.clients.iter().position(|c| *c == Some(src_addr))?;
        self.clients[slot] = None;
        self.last_gamepad_seq_ids[slot] = 0;
        self.last_kbm_seq_ids[slot] = 0;
        // TODO: consider a heartbeat packet for timeout-based eviction
        Some(slot)
    }

    /// Returns `true` and advances the stored seq if `seq_id` is a valid
    /// new packet. Returns `false` for duplicates and out-of-order packets.
    fn check_seq(&mut self, player_index: usize, seq_id: u16, kbm: bool) -> bool {
        let last = if kbm {
            &mut self.last_kbm_seq_ids[player_index]
        } else {
            &mut self.last_gamepad_seq_ids[player_index]
        };
        let diff = seq_id.wrapping_sub(*last);
        if diff == 0 || diff >= 32768 {
            return false;
        }
        *last = seq_id;
        true
    }
}

struct FraypadServer {
    gamepads: [VirtualDevice; 4],
    mouseboard: VirtualDevice,
    sessions: SessionTable,
    socket: UdpSocket,
}

impl FraypadServer {
    fn new() -> Result<Self> {
        println!("Welcome to Fraypad server! Building virtual devices...");

        let gamepads = [
            build_gamepad(0).context("Failed to build gamepad 1")?,
            build_gamepad(1).context("Failed to build gamepad 2")?,
            build_gamepad(2).context("Failed to build gamepad 3")?,
            build_gamepad(3).context("Failed to build gamepad 4")?,
        ];
        println!("Gamepads 1-4 created.");

        let mouseboard = build_mouseboard()?;
        println!("Mouseboard created.");

        let socket =
            UdpSocket::bind("0.0.0.0:54321").context("Failed to bind UDP socket.")?;
        println!("Server listening on port 54321");

        Ok(Self {
            gamepads,
            mouseboard,
            sessions: SessionTable::new(),
            socket,
        })
    }

    /// Emit an input event on behalf of a connected client.
    ///
    /// The player slot is resolved from the sender's address, never from the
    /// packet, so a client cannot inject input into another player's pad.
    /// Packets from unregistered addresses are dropped.
    fn handle_input(&mut self, packet: &InputPacket, src_addr: SocketAddr) {
        let Some(player_index) = self.sessions.slot_of(src_addr) else {
            return;
        };

        let routing_bit = packet.packet_type >> 15;
        let event_type = packet.packet_type & 0x7FFF;

        if !self.sessions.check_seq(player_index, packet.seq_id, routing_bit != 0) {
            return;
        }

        let event = InputEvent::new(event_type, packet.code, packet.value);
        let sync_event = InputEvent::new(0, 0, 0);

        let target = if routing_bit == 0 {
            &mut self.gamepads[player_index]
        } else {
            &mut self.mouseboard
        };

        if let Err(e) = target.emit(&[event, sync_event]) {
            eprintln!("Failed to emit event: {}", e);
        }
    }

    fn handle_sidecar(&mut self, packet: &FeedbackPacket, src_addr: SocketAddr) {
        match packet.packet_type {
            0 => match self.sessions.connect(src_addr) {
                ConnectOutcome::Connected(slot) => {
                    println!("Player {} connected: {}", slot + 1, src_addr);
                    let ack = FeedbackPacket {
                        packet_type: 0,
                        player_id: slot as u16,
                        primary: 0,
                        second: 0,
                    };
                    let _ = self.socket.send_to(bytemuck::bytes_of(&ack), src_addr);
                }
                ConnectOutcome::Reconnected(slot) => {
                    let ack = FeedbackPacket {
                        packet_type: 0,
                        player_id: slot as u16,
                        primary: 0,
                        second: 0,
                    };
                    let _ = self.socket.send_to(bytemuck::bytes_of(&ack), src_addr);
                }
                ConnectOutcome::Rejected => {
                    println!("Rejected connection from {} - all slots full.", src_addr);
                    let reject = FeedbackPacket {
                        packet_type: 2,
                        player_id: 0,
                        primary: 0,
                        second: 0,
                    };
                    let _ = self.socket.send_to(bytemuck::bytes_of(&reject), src_addr);
                }
            },

            1 => {
                if let Some(slot) = self.sessions.disconnect(src_addr) {
                    println!("Player {} disconnected: {}", slot + 1, src_addr);
                }
            }

            3 => println!("Received rumble packet from {}: {:#?}", src_addr, packet),

            _ => {}
        }
    }

    fn run(&mut self) -> Result<()> {
        let mut aligned_buf = [0u32; 3];
        let buf = bytemuck::bytes_of_mut(&mut aligned_buf);

        loop {
            let (len, src_addr) = self.socket.recv_from(buf).context("UDP read error")?;

            match len {
                12 => {
                    let packet: &InputPacket = bytemuck::from_bytes(&buf[..12]);
                    self.handle_input(packet, src_addr);
                }
                8 => {
                    let packet: &FeedbackPacket = bytemuck::from_bytes(&buf[..8]);
                    self.handle_sidecar(packet, src_addr);
                }
                _ => {}
            }
        }
    }
}

fn main() -> Result<()> {
    FraypadServer::new()?.run()
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    fn addr(port: u16) -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port)
    }

    #[test]
    fn connect_assigns_first_free_slot() {
        let mut s = SessionTable::new();
        assert!(matches!(s.connect(addr(1)), ConnectOutcome::Connected(0)));
    }

    #[test]
    fn connect_fills_slots_in_order() {
        let mut s = SessionTable::new();
        for (port, expected_slot) in (1u16..=4).zip(0usize..=3) {
            assert!(matches!(s.connect(addr(port)), ConnectOutcome::Connected(slot) if slot == expected_slot));
        }
    }

    #[test]
    fn reconnect_returns_existing_slot() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        assert!(matches!(s.connect(addr(1)), ConnectOutcome::Reconnected(0)));
    }

    #[test]
    fn reject_when_all_slots_full() {
        let mut s = SessionTable::new();
        for port in 1u16..=4 {
            s.connect(addr(port));
        }
        assert!(matches!(s.connect(addr(5)), ConnectOutcome::Rejected));
    }

    #[test]
    fn disconnect_frees_slot_for_reuse() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        s.disconnect(addr(1));
        assert!(matches!(s.connect(addr(2)), ConnectOutcome::Connected(0)));
    }

    #[test]
    fn disconnect_resets_seq_ids() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        s.check_seq(0, 10, false);
        s.check_seq(0, 20, true);
        s.disconnect(addr(1));
        assert_eq!(s.last_gamepad_seq_ids[0], 0);
        assert_eq!(s.last_kbm_seq_ids[0], 0);
    }

    #[test]
    fn seq_accepts_sequential_packets() {
        let mut s = SessionTable::new();
        assert!(s.check_seq(0, 1, false));
        assert!(s.check_seq(0, 2, false));
        assert!(s.check_seq(0, 3, false));
    }

    #[test]
    fn seq_drops_duplicate() {
        let mut s = SessionTable::new();
        s.check_seq(0, 5, false);
        assert!(!s.check_seq(0, 5, false));
    }

    #[test]
    fn seq_drops_out_of_order() {
        let mut s = SessionTable::new();
        s.check_seq(0, 10, false);
        assert!(!s.check_seq(0, 5, false));
    }

    #[test]
    fn seq_accepts_wrapping() {
        let mut s = SessionTable::new();
        s.last_gamepad_seq_ids[0] = u16::MAX;
        assert!(s.check_seq(0, 0, false));
    }

    #[test]
    fn seq_tracked_independently_per_player() {
        let mut s = SessionTable::new();
        s.check_seq(0, 5, false);
        assert!(s.check_seq(1, 5, false));
    }

    #[test]
    fn seq_tracked_independently_gamepad_vs_kbm() {
        let mut s = SessionTable::new();
        s.check_seq(0, 5, false);
        assert!(s.check_seq(0, 5, true));
    }

    #[test]
    fn disconnect_unknown_addr_returns_none() {
        let mut s = SessionTable::new();
        assert!(s.disconnect(addr(99)).is_none());
    }

    #[test]
    fn disconnect_middle_slot_reuses_it() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        s.connect(addr(2));
        s.connect(addr(3));
        s.disconnect(addr(2));
        assert!(matches!(s.connect(addr(4)), ConnectOutcome::Connected(1)));
    }

    #[test]
    fn slot_of_resolves_registered_addr() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        s.connect(addr(2));
        assert_eq!(s.slot_of(addr(2)), Some(1));
        assert_eq!(s.slot_of(addr(1)), Some(0));
    }

    #[test]
    fn slot_of_unknown_addr_is_none() {
        let s = SessionTable::new();
        assert_eq!(s.slot_of(addr(7)), None);
    }

    #[test]
    fn reconnect_resets_seq_ids() {
        let mut s = SessionTable::new();
        s.connect(addr(1));
        s.check_seq(0, 10, false);
        s.check_seq(0, 20, true);
        // Same addr reconnects; the client restarts its counter at 0, so the
        // server must clear its stored seq or everything would be dropped.
        assert!(matches!(s.connect(addr(1)), ConnectOutcome::Reconnected(0)));
        assert_eq!(s.last_gamepad_seq_ids[0], 0);
        assert_eq!(s.last_kbm_seq_ids[0], 0);
        assert!(s.check_seq(0, 1, false));
    }
}
