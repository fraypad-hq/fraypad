use bytemuck::{Pod, Zeroable};

pub const PACKET_MAGIC: u16 = 0xF3A9;

pub const PROTOCOL_VERSION: u8 = 1;

pub const PACKET_SIZE: usize = 16;

#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq, Pod, Zeroable)]
pub struct Packet {
    pub magic: u16,
    pub version: u8,
    pub kind: u8,
    pub player_id: u16,
    pub seq_id: u16,
    pub event_type: u16,
    pub code: u16,
    pub value: i32,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
#[repr(u8)]
pub enum PacketKind {
    Hello = 0,
    Welcome = 1,
    Reject = 2,
    Bye = 3,
    Input = 4,
    Heartbeat = 5,
    Pong = 6,
    Rumble = 7,
    Resync = 8,
}

impl PacketKind {
    #[must_use]
    pub const fn from_u8(v: u8) -> Option<Self> {
        match v {
            0 => Some(Self::Hello),
            1 => Some(Self::Welcome),
            2 => Some(Self::Reject),
            3 => Some(Self::Bye),
            4 => Some(Self::Input),
            5 => Some(Self::Heartbeat),
            6 => Some(Self::Pong),
            7 => Some(Self::Rumble),
            8 => Some(Self::Resync),
            _ => None,
        }
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
#[repr(i32)]
pub enum RejectReason {
    ServerFull = 0,
    VersionMismatch = 1,
}

pub mod codes {
    pub const ROUTE_KBM: u16 = 1 << 15;

    pub const TYPE_MASK: u16 = 0x7FFF;

    pub const EV_SYN: u16 = 0;
    pub const EV_KEY: u16 = 1;
    pub const EV_REL: u16 = 2;
    pub const EV_ABS: u16 = 3;

    #[must_use]
    pub const fn event_type(event_type: u16) -> u16 {
        event_type & TYPE_MASK
    }

    #[must_use]
    pub const fn is_kbm(event_type: u16) -> bool {
        event_type & ROUTE_KBM != 0
    }

    pub const BTN_SOUTH: u16 = 0x130;
    pub const BTN_EAST: u16 = 0x131;
    pub const BTN_NORTH: u16 = 0x133;
    pub const BTN_WEST: u16 = 0x134;
    pub const BTN_TL: u16 = 0x136;
    pub const BTN_TR: u16 = 0x137;
    pub const BTN_TL2: u16 = 0x138;
    pub const BTN_TR2: u16 = 0x139;
    pub const BTN_SELECT: u16 = 0x13A;
    pub const BTN_START: u16 = 0x13B;
    pub const BTN_MODE: u16 = 0x13C;
    pub const BTN_THUMBL: u16 = 0x13D;
    pub const BTN_THUMBR: u16 = 0x13E;

    pub const ABS_X: u16 = 0;
    pub const ABS_Y: u16 = 1;
    pub const ABS_Z: u16 = 2;
    pub const ABS_RX: u16 = 3;
    pub const ABS_RY: u16 = 4;
    pub const ABS_RZ: u16 = 5;
    pub const ABS_HAT0X: u16 = 16;
    pub const ABS_HAT0Y: u16 = 17;

    pub const REL_X: u16 = 0;
    pub const REL_Y: u16 = 1;
    pub const REL_HWHEEL: u16 = 6;
    pub const REL_WHEEL: u16 = 8;

    pub const BTN_LEFT: u16 = 0x110;
    pub const BTN_RIGHT: u16 = 0x111;
    pub const BTN_MIDDLE: u16 = 0x112;

    pub const KEY_A: u16 = 30;
    pub const KEY_Z: u16 = 44;
    pub const KEY_1: u16 = 2;
    pub const KEY_0: u16 = 11;
    pub const KEY_ESC: u16 = 1;
    pub const KEY_TAB: u16 = 15;
    pub const KEY_CAPSLOCK: u16 = 58;
    pub const KEY_ENTER: u16 = 28;
    pub const KEY_BACKSPACE: u16 = 14;
    pub const KEY_SPACE: u16 = 57;
    pub const KEY_MINUS: u16 = 12;
    pub const KEY_EQUAL: u16 = 13;
    pub const KEY_LEFTBRACE: u16 = 26;
    pub const KEY_RIGHTBRACE: u16 = 27;
    pub const KEY_BACKSLASH: u16 = 43;
    pub const KEY_SEMICOLON: u16 = 39;
    pub const KEY_APOSTROPHE: u16 = 40;
    pub const KEY_GRAVE: u16 = 41;
    pub const KEY_COMMA: u16 = 51;
    pub const KEY_DOT: u16 = 52;
    pub const KEY_SLASH: u16 = 53;
    pub const KEY_LEFTSHIFT: u16 = 42;
    pub const KEY_RIGHTSHIFT: u16 = 54;
    pub const KEY_LEFTCTRL: u16 = 29;
    pub const KEY_LEFTALT: u16 = 56;
    pub const KEY_LEFTMETA: u16 = 125;
    pub const KEY_UP: u16 = 103;
    pub const KEY_DOWN: u16 = 108;
    pub const KEY_LEFT: u16 = 105;
    pub const KEY_RIGHT: u16 = 106;
    pub const KEY_DELETE: u16 = 111;
    pub const KEY_HOME: u16 = 102;
    pub const KEY_END: u16 = 107;
    pub const KEY_PAGEUP: u16 = 104;
    pub const KEY_PAGEDOWN: u16 = 109;
}

impl Packet {
    #[must_use]
    pub const fn new(kind: PacketKind) -> Self {
        Self {
            magic: PACKET_MAGIC,
            version: PROTOCOL_VERSION,
            kind: kind as u8,
            player_id: 0,
            seq_id: 0,
            event_type: 0,
            code: 0,
            value: 0,
        }
    }

    #[must_use]
    pub const fn kind(self) -> Option<PacketKind> {
        PacketKind::from_u8(self.kind)
    }

    #[must_use]
    pub const fn is_valid(&self) -> bool {
        self.magic == PACKET_MAGIC && self.version == PROTOCOL_VERSION
    }

    #[must_use]
    pub const fn input(
        player_id: u16,
        seq_id: u16,
        event_type: u16,
        code: u16,
        value: i32,
    ) -> Self {
        Self {
            magic: PACKET_MAGIC,
            version: PROTOCOL_VERSION,
            kind: PacketKind::Input as u8,
            player_id,
            seq_id,
            event_type,
            code,
            value,
        }
    }

    #[must_use]
    pub fn rumble(player_id: u16, strong: u16, weak: u16, duration_ms: u32) -> Self {
        Self {
            magic: PACKET_MAGIC,
            version: PROTOCOL_VERSION,
            kind: PacketKind::Rumble as u8,
            player_id,
            seq_id: 0,
            event_type: weak,
            code: strong,
            value: duration_ms.min(i32::MAX as u32).cast_signed(),
        }
    }

    #[must_use]
    pub fn rumble_params(self) -> Option<(u16, u16, u32)> {
        if self.kind() == Some(PacketKind::Rumble) {
            Some((
                self.code,
                self.event_type,
                self.value.max(0).cast_unsigned(),
            ))
        } else {
            None
        }
    }

    #[must_use]
    pub fn to_bytes(self) -> [u8; PACKET_SIZE] {
        bytemuck::bytes_of(&self)
            .try_into()
            .expect("Packet is PACKET_SIZE bytes")
    }

    #[must_use]
    pub fn from_bytes(bytes: &[u8]) -> Option<Self> {
        let packet: &Self = bytemuck::try_from_bytes(bytes).ok()?;
        if packet.is_valid() {
            Some(*packet)
        } else {
            None
        }
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn packet_is_sixteen_bytes() {
        assert_eq!(core::mem::size_of::<Packet>(), PACKET_SIZE);
    }

    #[test]
    fn packet_round_trips_through_bytes() {
        let p = Packet::input(2, 7, codes::EV_ABS, codes::ABS_X, -1234);
        let bytes = p.to_bytes();
        assert_eq!(bytes.len(), PACKET_SIZE);
        assert_eq!(Packet::from_bytes(&bytes), Some(p));
    }

    #[test]
    fn bad_magic_is_rejected() {
        let mut p = Packet::input(0, 1, codes::EV_KEY, codes::BTN_SOUTH, 1);
        p.magic = 0xDEAD;
        assert_eq!(Packet::from_bytes(&p.to_bytes()), None);
    }

    #[test]
    fn wrong_version_is_rejected() {
        let mut p = Packet::new(PacketKind::Hello);
        p.version = PROTOCOL_VERSION + 1;
        assert!(!p.is_valid());
        assert_eq!(Packet::from_bytes(&p.to_bytes()), None);
    }

    #[test]
    fn truncated_bytes_are_rejected() {
        let p = Packet::new(PacketKind::Hello).to_bytes();
        assert_eq!(Packet::from_bytes(&p[..15]), None);
        assert_eq!(Packet::from_bytes(&[]), None);
    }

    #[test]
    fn kind_discriminants_round_trip() {
        for kind in [
            PacketKind::Hello,
            PacketKind::Welcome,
            PacketKind::Reject,
            PacketKind::Bye,
            PacketKind::Input,
            PacketKind::Heartbeat,
            PacketKind::Pong,
            PacketKind::Rumble,
            PacketKind::Resync,
        ] {
            assert_eq!(PacketKind::from_u8(kind as u8), Some(kind));
        }
        assert_eq!(PacketKind::from_u8(200), None);
    }

    #[test]
    fn input_preserves_route_bit() {
        let kbm = Packet::input(1, 1, codes::EV_KEY | codes::ROUTE_KBM, codes::BTN_LEFT, 1);
        assert!(codes::is_kbm(kbm.event_type));
        assert_eq!(codes::event_type(kbm.event_type), codes::EV_KEY);

        let pad = Packet::input(1, 2, codes::EV_ABS, codes::ABS_Y, 5);
        assert!(!codes::is_kbm(pad.event_type));
        assert_eq!(codes::event_type(pad.event_type), codes::EV_ABS);
    }

    #[test]
    fn keyboard_codes_match_the_evdev_uapi() {
        assert_eq!(codes::KEY_A, 30);
        assert_eq!(codes::KEY_Z, 44);
        assert_eq!(codes::KEY_1, 2);
        assert_eq!(codes::KEY_0, 11);
        assert_eq!(codes::KEY_ENTER, 28);
        assert_eq!(codes::KEY_BACKSPACE, 14);
        assert_eq!(codes::KEY_SPACE, 57);
        assert_eq!(codes::KEY_LEFTSHIFT, 42);
        assert_eq!(codes::KEY_LEFTCTRL, 29);
        assert_eq!(codes::KEY_ESC, 1);
        assert_eq!(codes::KEY_UP, 103);
        assert_eq!(codes::KEY_LEFT, 105);
    }

    #[test]
    fn rumble_params_survive_round_trip() {
        let p = Packet::rumble(3, 40000, 20000, 250);
        let decoded = Packet::from_bytes(&p.to_bytes()).expect("valid");
        assert_eq!(decoded.rumble_params(), Some((40000, 20000, 250)));
    }

    #[test]
    fn input_equality_supports_state_snapshot_diffing() {
        let a = Packet::input(0, 5, codes::EV_ABS, codes::ABS_X, 100);
        let b = Packet::input(0, 9, codes::EV_ABS, codes::ABS_X, 100);
        assert_ne!(a, b);
        assert_eq!(a.code, b.code);
    }
}
