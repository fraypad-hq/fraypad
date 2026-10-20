//! # Fraypad Protocol
//!
//! This crate defines the network protocol for all Fraypad
//! packets.

use bytemuck::{Pod, Zeroable};

/// A struct for a single input payload from client to server
#[repr(C)]
#[derive(Debug, Copy, Clone, Pod, Zeroable)]
pub struct InputPacket {
    /// The evdev event type
    ///
    /// Bit 15 is reserved as a routing flag:
    /// * `0`: Routes to the virtual gamepad
    /// * `1`: Routes to the virtual keyboard/mouse
    pub packet_type: u16,

    /// The assigned controller slot, supporting values from
    /// `0` to `3`
    pub player_id: u16,

    /// The evdev input code defining the specific key, button,
    /// or axis
    pub code: u16,

    /// A wrapping sequence identifier used to discard delayed
    /// or out-of-order packets
    pub seq_id: u16,

    /// The input value
    ///
    /// Represents binary state, or analog coordinates or
    /// motion data
    pub value: i32,
}

/// A struct for a single feedback payload for intercommunication
/// between the client and the server
#[repr(C)]
#[derive(Debug, Copy, Clone, Pod, Zeroable)]
pub struct FeedbackPacket {
    /// The feedback event type
    ///
    /// Signaling (bidirectional):
    /// * `0`: Connect - request (client to server) or ack with assigned slot (server to client)
    /// * `1`: Disconnect (client to server)
    /// * `2`: Rejected - all player slots are full (server to client)
    ///
    /// Data (server to client):
    /// * `3`: Rumble/Vibration
    pub packet_type: u16,

    /// The target or assigned player slot, supporting values from
    /// `0` to `3`
    pub player_id: u16,

    /// The primary payload data
    ///
    /// For Rumble (`type = 3`), this is the motor magnitude
    /// (0 to 65535).
    pub primary: u16,

    /// The secondary payload data
    ///
    /// For Rumble (`type = 3`), this is the duration in ms.
    pub second: u16,
}

/// Wire codes carried inside `InputPacket`.
///
/// The wire format uses Linux evdev codes as its canonical encoding: each
/// backend (Linux uinput today, a native driver elsewhere) maps these to its
/// own device semantics. Clients should use the constants here rather than
/// hardcoding numbers.
pub mod codes {
    /// Bit set in `InputPacket::packet_type` to route a packet to the virtual
    /// keyboard/mouse instead of the virtual gamepad.
    ///
    /// `0`: routes to the gamepad. `1`: routes to the keyboard/mouse.
    pub const ROUTE_KBM: u16 = 1 << 15;

    /// Mask to recover the evdev event type from `InputPacket::packet_type`.
    pub const TYPE_MASK: u16 = 0x7FFF;

    /// `EV_SYN` - input event sync / end of report.
    pub const EV_SYN: u16 = 0;
    /// `EV_KEY` - a binary key or button state change.
    pub const EV_KEY: u16 = 1;
    /// `EV_REL` - a relative axis change (mouse movement, scroll).
    pub const EV_REL: u16 = 2;
    /// `EV_ABS` - an absolute axis change (sticks, triggers, d-pad).
    pub const EV_ABS: u16 = 3;

    /// Build a gamepad-routed `packet_type` from an evdev event type.
    #[must_use]
    pub const fn gamepad(event_type: u16) -> u16 {
        event_type & TYPE_MASK
    }

    /// Build a keyboard/mouse-routed `packet_type` from an evdev event type.
    #[must_use]
    pub const fn kbm(event_type: u16) -> u16 {
        (event_type & TYPE_MASK) | ROUTE_KBM
    }

    // ── Gamepad buttons (EV_KEY) ─────────────────────────────────────────
    /// A / cross - bottom face button.
    pub const BTN_SOUTH: u16 = 0x130;
    /// B / circle - right face button.
    pub const BTN_EAST: u16 = 0x131;
    /// Y / triangle - top face button.
    pub const BTN_NORTH: u16 = 0x133;
    /// X / square - left face button.
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

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn input_packet_is_twelve_bytes() {
        assert_eq!(core::mem::size_of::<InputPacket>(), 12);
    }

    #[test]
    fn feedback_packet_is_eight_bytes() {
        assert_eq!(core::mem::size_of::<FeedbackPacket>(), 8);
    }

    #[test]
    fn routing_bit_is_isolated_from_event_type() {
        let kbm_key = codes::kbm(codes::EV_KEY);
        assert_eq!(kbm_key >> 15, 1);
        assert_eq!(kbm_key & codes::TYPE_MASK, codes::EV_KEY);

        let pad_abs = codes::gamepad(codes::EV_ABS);
        assert_eq!(pad_abs >> 15, 0);
        assert_eq!(pad_abs & codes::TYPE_MASK, codes::EV_ABS);
    }

    #[test]
    fn routing_helpers_are_const_constructible() {
        // Mirrors what the client sends for a button and a stick axis.
        assert_eq!(codes::kbm(codes::EV_KEY), 0x8001);
        assert_eq!(codes::gamepad(codes::EV_KEY), 0x0001);
        assert_eq!(codes::gamepad(codes::EV_ABS), 0x0003);
        assert_eq!(codes::kbm(codes::EV_REL), 0x8002);
    }
}
