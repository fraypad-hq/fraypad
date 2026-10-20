//! # Fraypad
//!
//! UDP server that receives Fraypad packets from clients and re-emits them as
//! virtual input events via Linux `uinput`.
//!
//! All session, routing, and reliability logic lives in `fraypad_server_core`.
//! This binary is just the Linux `uinput` [`Backend`] plus the socket loop: it
//! feeds datagrams into the core and prints the replies the core asks it to
//! send. A native Windows driver would implement the same [`Backend`] trait
//! with none of this loop changed.

use std::collections::{HashMap, VecDeque};
use std::net::UdpSocket;
use std::os::fd::AsRawFd;
use std::time::{Duration, Instant};

use evdev::{
    AbsInfo, AbsoluteAxisCode, AttributeSet, EventSummary, FFEffectCode, FFEffectKind, InputEvent,
    KeyCode, RelativeAxisCode, UInputCode, UinputAbsSetup, uinput::VirtualDevice,
};
use nix::fcntl::{F_SETFL, OFlag, fcntl};

use anyhow::{Context, Result};
use fraypad_protocol::codes;
use fraypad_server_core::{
    Backend, Config, InputEvent as CoreEvent, Reply, Rumble, ServerCore, Target,
};

/// How long the socket blocks waiting for a datagram before the main loop
/// wakes up to run housekeeping.
const RECV_TIMEOUT: Duration = Duration::from_millis(50);

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
    let axis_left_x = UinputAbsSetup::new(AbsoluteAxisCode::ABS_X, stick_setup);
    let axis_left_y = UinputAbsSetup::new(AbsoluteAxisCode::ABS_Y, stick_setup);
    let axis_right_x = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RX, stick_setup);
    let axis_right_y = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RY, stick_setup);

    let trigger_setup = AbsInfo::new(0, 0, 255, 0, 0, 0);
    let axis_trigger_l = UinputAbsSetup::new(AbsoluteAxisCode::ABS_Z, trigger_setup);
    let axis_trigger_r = UinputAbsSetup::new(AbsoluteAxisCode::ABS_RZ, trigger_setup);

    let hat_setup = AbsInfo::new(0, -1, 1, 0, 0, 0);
    let axis_hat_x = UinputAbsSetup::new(AbsoluteAxisCode::ABS_HAT0X, hat_setup);
    let axis_hat_y = UinputAbsSetup::new(AbsoluteAxisCode::ABS_HAT0Y, hat_setup);

    let name = format!("Fraypad Gamepad (P{})", player_num + 1);

    // Spoofing a Microsoft Xbox 360 controller
    let input_id = evdev::InputId::new(evdev::BusType::BUS_USB, 0x045E, 0x028E, 0x0110);

    VirtualDevice::builder()?
        .name(&name)
        .input_id(input_id)
        .with_keys(&keys)?
        .with_ff(&ff)?
        .with_ff_effects_max(16)
        .with_absolute_axis(&axis_left_x)?
        .with_absolute_axis(&axis_left_y)?
        .with_absolute_axis(&axis_right_x)?
        .with_absolute_axis(&axis_right_y)?
        .with_absolute_axis(&axis_trigger_l)?
        .with_absolute_axis(&axis_trigger_r)?
        .with_absolute_axis(&axis_hat_x)?
        .with_absolute_axis(&axis_hat_y)?
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

/// A force-feedback effect uploaded by a game, remembered so we can map
/// later play/stop events back to rumble magnitudes.
#[derive(Clone, Copy)]
struct FfEffect {
    strong: u16,
    weak: u16,
    length_ms: u16,
}

/// Per-pad force-feedback state: effects uploaded by the game, keyed by the
/// effect id the kernel assigned, plus rumbles waiting to be sent.
#[derive(Default)]
struct FfTable {
    effects: HashMap<u16, FfEffect>,
    pending: VecDeque<Rumble>,
}

/// The set of button codes that make up a gamepad's neutral (all-released)
/// state.
const NEUTRAL_KEYS: &[u16] = &[
    codes::BTN_SOUTH,
    codes::BTN_EAST,
    codes::BTN_NORTH,
    codes::BTN_WEST,
    codes::BTN_TL,
    codes::BTN_TR,
    codes::BTN_TL2,
    codes::BTN_TR2,
    codes::BTN_SELECT,
    codes::BTN_START,
    codes::BTN_MODE,
    codes::BTN_THUMBL,
    codes::BTN_THUMBR,
];

/// The set of axis codes that make up a gamepad's neutral (centered) state.
const NEUTRAL_AXES: &[u16] = &[
    codes::ABS_X,
    codes::ABS_Y,
    codes::ABS_RX,
    codes::ABS_RY,
    codes::ABS_Z,
    codes::ABS_RZ,
    codes::ABS_HAT0X,
    codes::ABS_HAT0Y,
];

/// Build the event batch that returns a gamepad to neutral: every button
/// released (value 0) and every axis centered (value 0), then a sync.
fn neutral_events() -> Vec<InputEvent> {
    let mut events = Vec::with_capacity(NEUTRAL_KEYS.len() + NEUTRAL_AXES.len() + 1);
    for &code in NEUTRAL_KEYS {
        events.push(InputEvent::new(codes::EV_KEY, code, 0));
    }
    for &code in NEUTRAL_AXES {
        events.push(InputEvent::new(codes::EV_ABS, code, 0));
    }
    events.push(InputEvent::new(codes::EV_SYN, 0, 0));
    events
}

/// Linux `uinput` implementation of the server [`Backend`].
///
/// Pads are created on connect and destroyed on disconnect, so only slots with
/// a live client exist as devices. The keyboard/mouse board is shared and
/// created eagerly (cheap, and shared across players).
struct EvdevBackend {
    pads: [Option<VirtualDevice>; fraypad_server_core::MAX_PLAYERS],
    ff: [FfTable; fraypad_server_core::MAX_PLAYERS],
    mouseboard: VirtualDevice,
}

impl EvdevBackend {
    fn new() -> Result<Self> {
        let mouseboard = build_mouseboard()?;
        println!("Mouseboard created.");
        Ok(Self {
            pads: [None, None, None, None],
            ff: Default::default(),
            mouseboard,
        })
    }

    /// Poll force-feedback events (upload/play/erase) from every live pad.
    /// Called every server-loop iteration; pads are non-blocking so this is a
    /// no-op when nothing happened.
    fn drain_ff(&mut self) {
        let Self { pads, ff, .. } = self;
        for slot in 0..fraypad_server_core::MAX_PLAYERS {
            let Some(device) = pads[slot].as_mut() else {
                continue;
            };
            let table = &mut ff[slot];

            // Collect first: the fetch_events iterator borrows the device,
            // and processing needs it back.
            let events: Vec<InputEvent> = match device.fetch_events() {
                Ok(iter) => iter.collect(),
                Err(e) if e.kind() == std::io::ErrorKind::WouldBlock => continue,
                Err(e) => {
                    eprintln!("FF read error on player {} pad: {e}", slot + 1);
                    continue;
                }
            };

            for ev in events {
                match EventSummary::from(ev) {
                    EventSummary::UInput(uev, UInputCode::UI_FF_UPLOAD, _) => {
                        // Dropping the upload event commits it (retval 0).
                        // The kernel assigns the id (0..ff_effects_max), so a
                        // non-negative value is guaranteed for a successful
                        // upload; `try_from` keeps that assumption explicit.
                        if let Ok(upload) = device.process_ff_upload(uev)
                            && let Ok(effect_id) = u16::try_from(upload.effect_id())
                            && let FFEffectKind::Rumble {
                                strong_magnitude,
                                weak_magnitude,
                            } = upload.effect().kind
                        {
                            table.effects.insert(
                                effect_id,
                                FfEffect {
                                    strong: strong_magnitude,
                                    weak: weak_magnitude,
                                    length_ms: upload.effect().replay.length,
                                },
                            );
                        }
                    }
                    EventSummary::UInput(uev, UInputCode::UI_FF_ERASE, _) => {
                        if let Ok(erase) = device.process_ff_erase(uev)
                            && let Ok(effect_id) = u16::try_from(erase.effect_id())
                        {
                            table.effects.remove(&effect_id);
                        }
                    }
                    // Play (value > 0) or stop (value 0) of an uploaded effect;
                    // the event code carries the effect id.
                    EventSummary::ForceFeedback(_, code, value) => {
                        let id = code.0;
                        if value == 0 {
                            table.pending.push_back(Rumble {
                                strong: 0,
                                weak: 0,
                                duration_ms: 0,
                            });
                        } else if let Some(effect) = table.effects.get(&id) {
                            table.pending.push_back(Rumble {
                                strong: effect.strong,
                                weak: effect.weak,
                                duration_ms: u32::from(effect.length_ms),
                            });
                        }
                    }
                    _ => {}
                }
            }
        }
    }
}

impl Backend for EvdevBackend {
    fn create_pad(&mut self, slot: usize) {
        match build_gamepad(slot) {
            Ok(device) => {
                // Non-blocking so drain_ff() can poll for FF events inline
                // without stalling the server loop.
                let flags = fcntl(device.as_raw_fd(), F_SETFL(OFlag::O_NONBLOCK));
                if let Err(e) = flags {
                    eprintln!("Failed to set player {} pad non-blocking: {e}", slot + 1);
                }
                self.pads[slot] = Some(device);
                self.ff[slot] = FfTable::default();
                println!("Player {} pad created.", slot + 1);
            }
            Err(e) => eprintln!("Failed to create pad for player {}: {e}", slot + 1),
        }
    }

    fn destroy_pad(&mut self, slot: usize) {
        // Dropping the VirtualDevice destroys the uinput node.
        if self.pads[slot].take().is_some() {
            self.ff[slot] = FfTable::default();
            println!("Player {} pad destroyed.", slot + 1);
        }
    }

    fn neutralize_pad(&mut self, slot: usize) {
        if let Some(device) = self.pads[slot].as_mut()
            && let Err(e) = device.emit(&neutral_events())
        {
            eprintln!("Failed to neutralize player {} pad: {e}", slot + 1);
        }
    }

    fn emit(&mut self, target: Target, event: CoreEvent) {
        let ev = InputEvent::new(event.event_type, event.code, event.value);
        let sync = InputEvent::new(codes::EV_SYN, 0, 0);

        let device = match target {
            Target::Gamepad(slot) => self.pads[slot].as_mut(),
            Target::KeyboardMouse => Some(&mut self.mouseboard),
        };

        if let Some(device) = device
            && let Err(e) = device.emit(&[ev, sync])
        {
            eprintln!("Failed to emit event: {e}");
        }
    }

    fn poll_rumble(&mut self, slot: usize) -> Vec<Rumble> {
        self.ff[slot].pending.drain(..).collect()
    }
}

struct FraypadServer {
    core: ServerCore<EvdevBackend>,
    socket: UdpSocket,
}

impl FraypadServer {
    fn new() -> Result<Self> {
        println!("Welcome to Fraypad server! Building virtual devices...");

        let backend = EvdevBackend::new()?;
        let core = ServerCore::new(backend, Config::default());

        let socket = UdpSocket::bind("0.0.0.0:54321").context("Failed to bind UDP socket.")?;
        socket
            .set_read_timeout(Some(RECV_TIMEOUT))
            .context("Failed to set socket read timeout.")?;
        println!("Server listening on port 54321");

        Ok(Self { core, socket })
    }

    fn send_replies(&self, replies: &[Reply]) {
        for reply in replies {
            let _ = self.socket.send_to(&reply.packet.to_bytes(), reply.to);
        }
    }

    fn run(&mut self) -> Result<()> {
        // 16-byte packet; over-allocate a touch and slice to the actual length.
        let mut buf = [0u8; 64];
        let interval = self.core.housekeep_interval();
        let mut last_housekeep = Instant::now();

        loop {
            // Process FF events before reading the next datagram: effect
            // uploads must be acked promptly or the game blocks.
            self.core.backend_mut().drain_ff();

            match self.socket.recv_from(&mut buf) {
                Ok((len, src_addr)) => {
                    let replies = self
                        .core
                        .handle_datagram(&buf[..len], src_addr, Instant::now());
                    self.send_replies(&replies);
                }
                Err(ref e)
                    if e.kind() == std::io::ErrorKind::WouldBlock
                        || e.kind() == std::io::ErrorKind::TimedOut =>
                {
                    // Idle; fall through to housekeeping below.
                }
                Err(e) => return Err(e).context("UDP read error"),
            }

            // Run housekeeping whenever the interval has elapsed, regardless of
            // whether the last recv timed out or returned traffic.
            let now = Instant::now();
            if now.duration_since(last_housekeep) >= interval {
                last_housekeep = now;
                let replies = self.core.housekeep(now);
                self.send_replies(&replies);
            }
        }
    }
}

fn main() -> Result<()> {
    FraypadServer::new()?.run()
}
