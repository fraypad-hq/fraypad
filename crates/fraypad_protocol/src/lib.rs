//! # Fraypad Protocol
//!
//! The wire format shared by the Fraypad client and server.
//!
//! ## Design
//!
//! Everything is a single fixed-size [`Packet`], 16 bytes, little-endian on
//! the wire. A `magic` + `version` header lets a server reject garbage and
//! stale clients cheaply before touching any other field. `kind` selects which
//! fields are meaningful for that packet.
//!
//! ```text
//! offset  size  field        meaning
//!   0      2    magic        PACKET_MAGIC sanity check
//!   2      1    version      PROTOCOL_VERSION
//!   3      1    kind         PacketKind discriminant
//!   4      2    player_id    controller slot (0..=3) when assigned
//!   6      2    seq_id       wrapping per-route sequence for Input
//!   8      2    event_type   evdev type; bit 15 = kbm route (Input only)
//!  10      2    code         evdev code (Input), or rumble magnitude
//!  12      4    value        evdev value (Input), or packet payload
//! ```
//!
//! The wire encoding uses Linux evdev codes as its canonical input encoding.
//! That is an implementation detail of the transport: each backend (Linux
//! `uinput` today, a native driver elsewhere) maps these codes onto its own
//! device semantics, so the protocol stays backend-agnostic.

use bytemuck::{Pod, Zeroable};

/// Magic value in the first two bytes of every packet.
///
/// Lets a receiver reject unrelated UDP traffic before interpreting fields.
pub const PACKET_MAGIC: u16 = 0xF3A9;

/// Version of this wire format.
///
/// Bumped on any change to the layout or the meaning of a `kind`. A server
/// rejects packets whose version does not match, so an out-of-date phone app
/// fails loudly instead of misparsing.
pub const PROTOCOL_VERSION: u8 = 1;

/// Number of bytes in a serialized [`Packet`].
pub const PACKET_SIZE: usize = 16;

/// The fixed-size packet exchanged between client and server.
#[repr(C)]
#[derive(Debug, Copy, Clone, PartialEq, Eq, Pod, Zeroable)]
pub struct Packet {
    /// Must equal [`PACKET_MAGIC`].
    pub magic: u16,
    /// Must equal [`PROTOCOL_VERSION`].
    pub version: u8,
    /// A [`PacketKind`] discriminant.
    pub kind: u8,
    /// The controller slot, `0..=3`. Assigned by the server in a [`PacketKind::Welcome`].
    pub player_id: u16,
    /// Wrapping sequence number. Only meaningful for [`PacketKind::Input`],
    /// where it is tracked per slot and per route to drop duplicates and
    /// out-of-order deliveries.
    pub seq_id: u16,
    /// The evdev event type (Input only).
    ///
    /// Bit 15 doubles as a routing flag:
    /// * `0`: routes to the virtual gamepad
    /// * `1`: routes to the virtual keyboard/mouse
    ///
    /// For [`PacketKind::Rumble`] this instead carries the weak-motor
    /// magnitude, unused elsewhere.
    pub event_type: u16,
    /// The evdev code identifying a specific key, button, or axis (Input
    /// only). For [`PacketKind::Rumble`] this carries the strong-motor
    /// magnitude.
    pub code: u16,
    /// The payload: the evdev value for Input, a duration in milliseconds for
    /// Rumble, a timestamp for Heartbeat/Pong, or a status code for
    /// Welcome/Reject.
    pub value: i32,
}

/// The kind of packet, selecting which fields are meaningful.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
#[repr(u8)]
pub enum PacketKind {
    /// Client → server: request a slot. No other fields used.
    Hello = 0,
    /// Server → client: slot granted; `player_id` holds the assigned slot.
    Welcome = 1,
    /// Server → client: connection refused; `value` holds a [`RejectReason`].
    Reject = 2,
    /// Client → server: release our slot and leave.
    Bye = 3,
    /// Client → server: a single input event.
    Input = 4,
    /// Client → server: keep-alive; `value` carries a timestamp for RTT.
    Heartbeat = 5,
    /// Server → client: reply to a Heartbeat; echoes the client's timestamp.
    Pong = 6,
    /// Server → client: vibrate the phone. See [`Packet::rumble`].
    Rumble = 7,
    /// Server → client: re-send a full input-state snapshot now. Sent after a
    /// Welcome so the server learns the client's current state, and usable
    /// later to recover from loss.
    Resync = 8,
}

impl PacketKind {
    /// Convert a raw discriminant back into a `PacketKind`.
    ///
    /// Returns `None` for unknown values so callers can ignore future kinds
    /// gracefully.
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

/// Why a server refused a connection.
#[derive(Debug, Copy, Clone, PartialEq, Eq)]
#[repr(i32)]
pub enum RejectReason {
    /// Every player slot is currently taken.
    ServerFull = 0,
    /// The client's [`PROTOCOL_VERSION`] did not match the server's.
    VersionMismatch = 1,
}

/// Wire codes carried inside [`Packet`].
///
/// See the crate docs: evdev codes are the canonical input encoding, mapped to
/// device semantics by each backend.
pub mod codes {
    /// Bit set in [`Packet::event_type`] to route a packet to the virtual
    /// keyboard/mouse instead of the virtual gamepad.
    ///
    /// `0`: routes to the gamepad. `1`: routes to the keyboard/mouse.
    pub const ROUTE_KBM: u16 = 1 << 15;

    /// Mask to recover the evdev event type from [`Packet::event_type`].
    pub const TYPE_MASK: u16 = 0x7FFF;

    /// `EV_SYN` - input event sync / end of report.
    pub const EV_SYN: u16 = 0;
    /// `EV_KEY` - a binary key or button state change.
    pub const EV_KEY: u16 = 1;
    /// `EV_REL` - a relative axis change (mouse movement, scroll).
    pub const EV_REL: u16 = 2;
    /// `EV_ABS` - an absolute axis change (sticks, triggers, d-pad).
    pub const EV_ABS: u16 = 3;

    /// Recover just the evdev event type, dropping the routing bit.
    #[must_use]
    pub const fn event_type(event_type: u16) -> u16 {
        event_type & TYPE_MASK
    }

    /// Whether a packet's `event_type` is routed to the keyboard/mouse.
    #[must_use]
    pub const fn is_kbm(event_type: u16) -> bool {
        event_type & ROUTE_KBM != 0
    }

    // ── Gamepad buttons (EV_KEY) ─────────────────────────────────────────
    /// A / cross - bottom face button.
    pub const BTN_SOUTH: u16 = 0x130;
    /// B / circle - right face button.
    pub const BTN_EAST: u16 = 0x131;
    /// North face button. On an Xbox pad this is the **X** button:
    /// `BTN_X = BTN_NORTH = 0x133` in the Linux uapi, which is what the
    /// xpad driver emits for the physical X key.
    pub const BTN_NORTH: u16 = 0x133;
    /// West face button. On an Xbox pad this is the **Y** button.
    ///
    /// `BTN_Y = BTN_WEST = 0x134` in the Linux uapi (the xpad driver's
    /// physical Y). Note the historical alias quirk: X aliases to NORTH,
    /// Y aliases to WEST.
    pub const BTN_WEST: u16 = 0x134;
    /// Left bumper (LB).
    pub const BTN_TL: u16 = 0x136;
    /// Right bumper (RB).
    pub const BTN_TR: u16 = 0x137;
    /// Left trigger as a digital button (LT fully pressed).
    pub const BTN_TL2: u16 = 0x138;
    /// Right trigger as a digital button (RT fully pressed).
    pub const BTN_TR2: u16 = 0x139;
    /// Back / select / view.
    pub const BTN_SELECT: u16 = 0x13A;
    /// Start / options / menu.
    pub const BTN_START: u16 = 0x13B;
    /// Guide / Xbox / home button.
    pub const BTN_MODE: u16 = 0x13C;
    /// Left stick click (L3).
    pub const BTN_THUMBL: u16 = 0x13D;
    /// Right stick click (R3).
    pub const BTN_THUMBR: u16 = 0x13E;

    // ── Absolute axes (EV_ABS) ───────────────────────────────────────────
    /// Left stick X. `-32768..=32767`, negative is left.
    pub const ABS_X: u16 = 0;
    /// Left stick Y. `-32768..=32767`, negative is up.
    pub const ABS_Y: u16 = 1;
    /// Left trigger analog. `0..=255`.
    pub const ABS_Z: u16 = 2;
    /// Right stick X. `-32768..=32767`, negative is left.
    pub const ABS_RX: u16 = 3;
    /// Right stick Y. `-32768..=32767`, negative is up.
    pub const ABS_RY: u16 = 4;
    /// Right trigger analog. `0..=255`.
    pub const ABS_RZ: u16 = 5;
    /// D-pad horizontal. `-1` left, `0` center, `1` right.
    pub const ABS_HAT0X: u16 = 16;
    /// D-pad vertical. `-1` up, `0` center, `1` down.
    pub const ABS_HAT0Y: u16 = 17;

    // ── Mouse / relative axes (EV_REL, kbm-routed) ──────────────────────
    /// Mouse horizontal movement, in device units.
    pub const REL_X: u16 = 0;
    /// Mouse vertical movement, in device units.
    pub const REL_Y: u16 = 1;
    /// Horizontal scroll. Positive is right.
    pub const REL_HWHEEL: u16 = 6;
    /// Vertical scroll. Positive is up.
    pub const REL_WHEEL: u16 = 8;

    /// Left mouse button.
    pub const BTN_LEFT: u16 = 0x110;
    /// Right mouse button.
    pub const BTN_RIGHT: u16 = 0x111;
    /// Middle mouse button.
    pub const BTN_MIDDLE: u16 = 0x112;
}

impl Packet {
    /// Build a well-formed packet with the correct magic and version.
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

    /// The `PacketKind`, or `None` if the discriminant is not recognised.
    #[must_use]
    pub const fn kind(self) -> Option<PacketKind> {
        PacketKind::from_u8(self.kind)
    }

    /// Whether the magic and version match this build of the protocol.
    #[must_use]
    pub const fn is_valid(&self) -> bool {
        self.magic == PACKET_MAGIC && self.version == PROTOCOL_VERSION
    }

    /// Build an Input packet carrying a single evdev event.
    ///
    /// `event_type` is a raw evdev type (the routing bit, if any, is preserved
    /// from the value passed in).
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

    /// Build a Rumble packet.
    ///
    /// `strong` and `weak` are motor magnitudes `0..=65535`; `duration_ms` is
    /// how long to vibrate.
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

    /// The rumble magnitudes and duration, if this is a Rumble packet.
    #[must_use]
    pub fn rumble_params(self) -> Option<(u16, u16, u32)> {
        if self.kind() == Some(PacketKind::Rumble) {
            Some((self.code, self.event_type, self.value.max(0).cast_unsigned()))
        } else {
            None
        }
    }

    /// Serialize to the 16-byte wire representation.
    ///
    /// # Panics
    ///
    /// Never in practice: the conversion is from `size_of::<Packet>()` bytes,
    /// which a test pins to `PACKET_SIZE`.
    #[must_use]
    pub fn to_bytes(self) -> [u8; PACKET_SIZE] {
        bytemuck::bytes_of(&self).try_into().expect("Packet is PACKET_SIZE bytes")
    }

    /// Parse from the 16-byte wire representation.
    ///
    /// Returns `None` if the magic or version does not match, so a caller can
    /// drop stale or unrelated traffic without misreading fields.
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
    fn rumble_params_survive_round_trip() {
        let p = Packet::rumble(3, 40000, 20000, 250);
        let decoded = Packet::from_bytes(&p.to_bytes()).expect("valid");
        assert_eq!(decoded.rumble_params(), Some((40000, 20000, 250)));
    }

    #[test]
    fn input_equality_supports_state_snapshot_diffing() {
        // The client re-sends its full state on resync; equality lets it skip
        // unchanged entries.
        let a = Packet::input(0, 5, codes::EV_ABS, codes::ABS_X, 100);
        let b = Packet::input(0, 9, codes::EV_ABS, codes::ABS_X, 100);
        assert_ne!(a, b); // seq differs
        assert_eq!(a.code, b.code);
    }
}
