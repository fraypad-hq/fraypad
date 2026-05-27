//! # Fraypad
//!
//! The core logic for the Fraypad control suite.
//! Currently under initial construction.

use std::net::UdpSocket;

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

    // Numpad
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

    // Media
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

fn main() -> Result<()> {
    let player_index = 0;
    println!(
        "Welcome to Fraypad server! Starting up gamepad {}...",
        player_index + 1
    );

    let mut device = build_gamepad(player_index)?;
    println!("Gamepad {} created!", player_index + 1);

    let _mouseboard = build_mouseboard()?;
    println!("Mouseboard created!");

    let socket = UdpSocket::bind("0.0.0.0:54321").context("Failed to bind UDP socket.")?;
    println!("Server listening on port 54321");

    let mut aligned_buf = [0u32; 3];
    let buf = bytemuck::bytes_of_mut(&mut aligned_buf);

    let mut last_seq_id: [u16; 4] = [0; 4];

    loop {
        let (len, _src_addr) = socket.recv_from(buf).context("UDP read error")?;

        match len {
            12 => {
                let packet: &InputPacket = bytemuck::from_bytes(&buf[..12]);

                let diff = packet.seq_id.wrapping_sub(last_seq_id[player_index]);
                if diff == 0 || diff >= 32768 {
                    continue;
                }
                last_seq_id[player_index] = packet.seq_id;

                let event_type = packet.packet_type & 0x7FFF;
                let event = InputEvent::new(event_type, packet.code, packet.value);

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
