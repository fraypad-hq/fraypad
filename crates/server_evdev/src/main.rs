//! # Fraypad
//!
//! The core logic for the Fraypad control suite.
//! Currently under initial construction.

use std::net::UdpSocket;

use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, FFEffectCode, InputEvent, KeyCode, UinputAbsSetup,
    uinput::VirtualDevice,
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
        .build()
        .context("Failed to build virtual gamepad. Do you have uinput permissions?")
}

fn main() -> Result<()> {
    println!("Welcome to Fraypad server! Starting up gamepad 1...");

    let mut device = build_gamepad(0)?;
    println!("Gamepad 1 created!");

    let socket = UdpSocket::bind("0.0.0.0:54321").context("Failed to bind UDP socket.")?;
    println!("Server listening on port 54321");

    let mut aligned_buf = [0u32; 3];
    let buf = bytemuck::bytes_of_mut(&mut aligned_buf);

    let mut last_seq_id: u16 = 0;

    loop {
        let (len, _src_addr) = socket.recv_from(buf).context("UDP read error")?;

        match len {
            12 => {
                let packet: &InputPacket = bytemuck::from_bytes(&buf[..12]);

                let diff = packet.seq_id.wrapping_sub(last_seq_id);
                if diff == 0 || diff >= 32768 {
                    continue;
                }
                last_seq_id = packet.seq_id;

                let event = InputEvent::new(packet.packet_type, packet.code, packet.value);

                let sync_event = InputEvent::new(0, 0, 0);

                if let Err(e) = device.emit(&[event, sync_event]) {
                    eprintln!("Failed to emit event: {}", e);
                }
            }

            8 => {
                let packet: &FeedbackPacket = bytemuck::from_bytes(&buf[..8]);

                println!("Received feedback packet: {:#?}", packet);
            }

            _ => continue,
        }
    }
}
