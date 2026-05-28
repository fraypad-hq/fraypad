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
