use std::net::SocketAddr;
use std::time::{Duration, Instant};

use fraypad_protocol::{Packet, PacketKind, RejectReason, codes};

pub const MAX_PLAYERS: usize = 4;

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub struct Rumble {
    pub strong: u16,
    pub weak: u16,
    pub duration_ms: u32,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub struct InputEvent {
    pub event_type: u16,
    pub code: u16,
    pub value: i32,
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub enum Target {
    Gamepad(usize),
    KeyboardMouse,
}

pub trait Backend {
    fn create_pad(&mut self, slot: usize);

    fn destroy_pad(&mut self, slot: usize);

    fn neutralize_pad(&mut self, slot: usize);

    fn emit(&mut self, target: Target, event: InputEvent);

    fn poll_rumble(&mut self, slot: usize) -> Vec<Rumble>;
}

#[derive(Debug, Copy, Clone)]
pub struct Config {
    pub client_timeout: Duration,
    pub housekeep_interval: Duration,
}

impl Default for Config {
    fn default() -> Self {
        Self {
            client_timeout: Duration::from_secs(5),
            housekeep_interval: Duration::from_millis(250),
        }
    }
}

#[derive(Debug, Copy, Clone)]
struct Session {
    last_seen: Instant,
    last_seq: [u16; 2],
}

struct SessionTable {
    slots: [Option<Session>; MAX_PLAYERS],
    addrs: [Option<SocketAddr>; MAX_PLAYERS],
}

impl SessionTable {
    const fn new() -> Self {
        Self {
            slots: [None; MAX_PLAYERS],
            addrs: [None; MAX_PLAYERS],
        }
    }

    fn slot_of(&self, addr: SocketAddr) -> Option<usize> {
        self.addrs.iter().position(|a| *a == Some(addr))
    }

    fn assign(&mut self, addr: SocketAddr, now: Instant) -> Option<usize> {
        if let Some(slot) = self.slot_of(addr) {
            if let Some(session) = self.slots[slot].as_mut() {
                session.last_seq = [0; 2];
                session.last_seen = now;
            }
            return Some(slot);
        }
        let slot = self.slots.iter().position(Option::is_none)?;
        self.slots[slot] = Some(Session {
            last_seen: now,
            last_seq: [0; 2],
        });
        self.addrs[slot] = Some(addr);
        Some(slot)
    }

    fn touch(&mut self, addr: SocketAddr, now: Instant) -> bool {
        match self.slot_of(addr) {
            Some(slot) => {
                if let Some(session) = self.slots[slot].as_mut() {
                    session.last_seen = now;
                }
                true
            }
            None => false,
        }
    }

    fn release(&mut self, addr: SocketAddr) -> Option<usize> {
        let slot = self.slot_of(addr)?;
        self.slots[slot] = None;
        self.addrs[slot] = None;
        Some(slot)
    }

    const fn check_seq(&mut self, slot: usize, route: usize, seq: u16) -> bool {
        let Some(session) = self.slots[slot].as_mut() else {
            return false;
        };
        let last = &mut session.last_seq[route];
        let diff = seq.wrapping_sub(*last);
        if diff == 0 || diff >= 32768 {
            return false;
        }
        *last = seq;
        true
    }

    fn evict_expired(&mut self, now: Instant, timeout: Duration) -> Vec<usize> {
        let mut evicted = Vec::new();
        for slot in 0..MAX_PLAYERS {
            let expired = self.slots[slot]
                .is_some_and(|s| now.saturating_duration_since(s.last_seen) > timeout);
            if expired {
                self.slots[slot] = None;
                self.addrs[slot] = None;
                evicted.push(slot);
            }
        }
        evicted
    }

    const fn addr_of(&self, slot: usize) -> Option<SocketAddr> {
        self.addrs[slot]
    }
}

#[derive(Debug, Copy, Clone, PartialEq, Eq)]
pub struct Reply {
    pub to: SocketAddr,
    pub packet: Packet,
}

pub struct ServerCore<B: Backend> {
    backend: B,
    sessions: SessionTable,
    config: Config,
}

impl<B: Backend> ServerCore<B> {
    #[must_use]
    pub const fn new(backend: B, config: Config) -> Self {
        Self {
            backend,
            sessions: SessionTable::new(),
            config,
        }
    }

    pub const fn backend_mut(&mut self) -> &mut B {
        &mut self.backend
    }

    #[must_use]
    pub const fn client_timeout(&self) -> Duration {
        self.config.client_timeout
    }

    #[must_use]
    pub const fn housekeep_interval(&self) -> Duration {
        self.config.housekeep_interval
    }

    pub fn handle_datagram(&mut self, bytes: &[u8], from: SocketAddr, now: Instant) -> Vec<Reply> {
        let Some(packet) = Packet::from_bytes(bytes) else {
            return Vec::new();
        };

        match packet.kind() {
            Some(PacketKind::Hello) => self.on_hello(from, now),
            Some(PacketKind::Bye) => self.on_bye(from),
            Some(PacketKind::Heartbeat) => self.on_heartbeat(packet, from, now),
            Some(PacketKind::Input) => self.on_input(packet, from, now),
            _ => Vec::new(),
        }
    }

    fn on_hello(&mut self, from: SocketAddr, now: Instant) -> Vec<Reply> {
        if let Some(slot) = self.sessions.assign(from, now) {
            self.backend.create_pad(slot);
            let player_id = u16::try_from(slot).unwrap_or(u16::MAX);
            let welcome = Packet {
                player_id,
                ..Packet::new(PacketKind::Welcome)
            };
            let resync = Packet {
                player_id,
                ..Packet::new(PacketKind::Resync)
            };
            vec![
                Reply {
                    to: from,
                    packet: welcome,
                },
                Reply {
                    to: from,
                    packet: resync,
                },
            ]
        } else {
            let reject = Packet {
                value: RejectReason::ServerFull as i32,
                ..Packet::new(PacketKind::Reject)
            };
            vec![Reply {
                to: from,
                packet: reject,
            }]
        }
    }

    fn on_bye(&mut self, from: SocketAddr) -> Vec<Reply> {
        if let Some(slot) = self.sessions.release(from) {
            self.backend.neutralize_pad(slot);
            self.backend.destroy_pad(slot);
        }
        Vec::new()
    }

    fn on_heartbeat(&mut self, packet: Packet, from: SocketAddr, now: Instant) -> Vec<Reply> {
        if !self.sessions.touch(from, now) {
            return Vec::new();
        }
        let pong = Packet {
            value: packet.value,
            ..Packet::new(PacketKind::Pong)
        };
        vec![Reply {
            to: from,
            packet: pong,
        }]
    }

    fn on_input(&mut self, packet: Packet, from: SocketAddr, now: Instant) -> Vec<Reply> {
        let Some(slot) = self.sessions.slot_of(from) else {
            return Vec::new();
        };
        self.sessions.touch(from, now);

        let kbm = codes::is_kbm(packet.event_type);
        if !self
            .sessions
            .check_seq(slot, usize::from(kbm), packet.seq_id)
        {
            return Vec::new();
        }

        let target = if kbm {
            Target::KeyboardMouse
        } else {
            Target::Gamepad(slot)
        };
        self.backend.emit(
            target,
            InputEvent {
                event_type: codes::event_type(packet.event_type),
                code: packet.code,
                value: packet.value,
            },
        );
        Vec::new()
    }

    pub fn housekeep(&mut self, now: Instant) -> Vec<Reply> {
        let mut replies = Vec::new();

        for slot in 0..MAX_PLAYERS {
            let Some(addr) = self.sessions.addr_of(slot) else {
                continue;
            };
            for rumble in self.backend.poll_rumble(slot) {
                let player_id = u16::try_from(slot).unwrap_or(u16::MAX);
                replies.push(Reply {
                    to: addr,
                    packet: Packet::rumble(
                        player_id,
                        rumble.strong,
                        rumble.weak,
                        rumble.duration_ms,
                    ),
                });
            }
        }

        for slot in self.sessions.evict_expired(now, self.config.client_timeout) {
            self.backend.neutralize_pad(slot);
            self.backend.destroy_pad(slot);
        }

        replies
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use std::net::{IpAddr, Ipv4Addr};

    #[derive(Debug, PartialEq, Eq)]
    enum Call {
        CreatePad(usize),
        DestroyPad(usize),
        NeutralizePad(usize),
        Emit(Target, InputEvent),
    }

    struct MockBackend {
        calls: Vec<Call>,
    }

    impl MockBackend {
        fn new() -> Self {
            Self { calls: Vec::new() }
        }
    }

    impl Backend for MockBackend {
        fn create_pad(&mut self, slot: usize) {
            self.calls.push(Call::CreatePad(slot));
        }
        fn destroy_pad(&mut self, slot: usize) {
            self.calls.push(Call::DestroyPad(slot));
        }
        fn neutralize_pad(&mut self, slot: usize) {
            self.calls.push(Call::NeutralizePad(slot));
        }
        fn emit(&mut self, target: Target, event: InputEvent) {
            self.calls.push(Call::Emit(target, event));
        }
        fn poll_rumble(&mut self, _slot: usize) -> Vec<Rumble> {
            Vec::new()
        }
    }

    fn addr(port: u16) -> SocketAddr {
        SocketAddr::new(IpAddr::V4(Ipv4Addr::LOCALHOST), port)
    }

    fn hello() -> [u8; fraypad_protocol::PACKET_SIZE] {
        Packet::new(PacketKind::Hello).to_bytes()
    }

    fn input(
        seq: u16,
        event_type: u16,
        code: u16,
        value: i32,
    ) -> [u8; fraypad_protocol::PACKET_SIZE] {
        Packet::input(0, seq, event_type, code, value).to_bytes()
    }

    fn start() -> (ServerCore<MockBackend>, Instant) {
        let core = ServerCore::new(MockBackend::new(), Config::default());
        (core, Instant::now())
    }

    fn connect(core: &mut ServerCore<MockBackend>, from: SocketAddr, now: Instant) -> usize {
        let replies = core.handle_datagram(&hello(), from, now);
        let welcome = replies[0].packet;
        assert_eq!(welcome.kind(), Some(PacketKind::Welcome));
        welcome.player_id as usize
    }

    #[test]
    fn hello_assigns_first_slot_and_creates_pad() {
        let (mut core, now) = start();
        let slot = connect(&mut core, addr(1), now);
        assert_eq!(slot, 0);
        assert!(core.backend.calls.contains(&Call::CreatePad(0)));
    }

    #[test]
    fn hello_replies_with_resync_request() {
        let (mut core, now) = start();
        let replies = core.handle_datagram(&hello(), addr(1), now);
        let kinds: Vec<_> = replies.iter().map(|r| r.packet.kind()).collect();
        assert_eq!(
            kinds,
            vec![Some(PacketKind::Welcome), Some(PacketKind::Resync)]
        );
    }

    #[test]
    fn hello_fills_slots_then_rejects() {
        let (mut core, now) = start();
        for port in 1..=4 {
            connect(&mut core, addr(port), now);
        }
        let replies = core.handle_datagram(&hello(), addr(99), now);
        assert_eq!(replies.len(), 1);
        assert_eq!(replies[0].packet.kind(), Some(PacketKind::Reject));
        assert_eq!(replies[0].packet.value, RejectReason::ServerFull as i32);
    }

    #[test]
    fn input_from_unknown_addr_is_ignored() {
        let (mut core, now) = start();
        let replies =
            core.handle_datagram(&input(1, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        assert!(replies.is_empty());
        assert!(core.backend.calls.is_empty());
    }

    #[test]
    fn input_routes_to_connecting_slots_pad() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        core.handle_datagram(&input(1, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        assert_eq!(
            core.backend.calls,
            vec![Call::Emit(
                Target::Gamepad(0),
                InputEvent {
                    event_type: codes::EV_KEY,
                    code: codes::BTN_SOUTH,
                    value: 1
                }
            )]
        );
    }

    #[test]
    fn input_cannot_spoof_another_slot() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        connect(&mut core, addr(2), now);
        core.backend.calls.clear();
        let spoof = Packet::input(0, 1, codes::EV_KEY, codes::BTN_SOUTH, 1);
        core.handle_datagram(&spoof.to_bytes(), addr(2), now);
        assert_eq!(
            core.backend.calls,
            vec![Call::Emit(
                Target::Gamepad(1),
                InputEvent {
                    event_type: codes::EV_KEY,
                    code: codes::BTN_SOUTH,
                    value: 1
                }
            )]
        );
    }

    #[test]
    fn duplicate_and_out_of_order_input_dropped() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        core.handle_datagram(&input(5, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        core.handle_datagram(&input(5, codes::EV_KEY, codes::BTN_SOUTH, 0), addr(1), now);
        core.handle_datagram(&input(3, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        assert_eq!(core.backend.calls.len(), 1);
    }

    #[test]
    fn kbm_and_gamepad_routes_have_independent_sequences() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        let kbm = codes::EV_KEY | codes::ROUTE_KBM;
        core.handle_datagram(&input(5, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        core.handle_datagram(&input(5, kbm, codes::BTN_LEFT, 1), addr(1), now);
        assert_eq!(core.backend.calls.len(), 2);
        assert_eq!(
            core.backend.calls[1],
            Call::Emit(
                Target::KeyboardMouse,
                InputEvent {
                    event_type: codes::EV_KEY,
                    code: codes::BTN_LEFT,
                    value: 1
                }
            )
        );
    }

    #[test]
    fn heartbeat_replies_with_pong_echoing_timestamp() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        let mut hb = Packet::new(PacketKind::Heartbeat);
        hb.value = 12345;
        let replies = core.handle_datagram(&hb.to_bytes(), addr(1), now);
        assert_eq!(replies.len(), 1);
        assert_eq!(replies[0].packet.kind(), Some(PacketKind::Pong));
        assert_eq!(replies[0].packet.value, 12345);
    }

    #[test]
    fn heartbeat_from_unknown_addr_is_ignored() {
        let (mut core, now) = start();
        let hb = Packet::new(PacketKind::Heartbeat);
        assert!(
            core.handle_datagram(&hb.to_bytes(), addr(1), now)
                .is_empty()
        );
    }

    #[test]
    fn reconnect_resets_sequence() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.handle_datagram(&input(10, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        core.handle_datagram(&input(1, codes::EV_KEY, codes::BTN_SOUTH, 1), addr(1), now);
        assert_eq!(core.backend.calls.len(), 1);
    }

    #[test]
    fn bye_neutralizes_and_destroys_pad() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        let bye = Packet::new(PacketKind::Bye);
        core.handle_datagram(&bye.to_bytes(), addr(1), now);
        assert!(core.backend.calls.contains(&Call::NeutralizePad(0)));
        assert!(core.backend.calls.contains(&Call::DestroyPad(0)));
    }

    #[test]
    fn stale_client_is_evicted_and_slot_reusable() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        let later = now + core.client_timeout() + Duration::from_millis(1);
        let replies = core.housekeep(later);
        assert!(replies.is_empty());
        assert!(core.backend.calls.contains(&Call::NeutralizePad(0)));
        assert!(core.backend.calls.contains(&Call::DestroyPad(0)));
        assert_eq!(connect(&mut core, addr(2), later), 0);
    }

    #[test]
    fn active_client_is_not_evicted() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        let hb = Packet::new(PacketKind::Heartbeat);
        let step = Duration::from_millis(100);
        for i in 1..=60u32 {
            let t = now + step * i;
            core.handle_datagram(&hb.to_bytes(), addr(1), t);
            core.backend.calls.clear();
            core.housekeep(t);
            assert!(
                !core.backend.calls.contains(&Call::DestroyPad(0)),
                "evicted at step {i}"
            );
        }
    }

    #[test]
    fn malformed_datagram_is_ignored() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        core.backend.calls.clear();
        assert!(
            core.handle_datagram(b"not a packet", addr(1), now)
                .is_empty()
        );
        assert!(core.backend.calls.is_empty());
    }

    #[test]
    fn wrong_version_datagram_is_ignored() {
        let (mut core, now) = start();
        connect(&mut core, addr(1), now);
        let mut p = Packet::new(PacketKind::Hello);
        p.version = fraypad_protocol::PROTOCOL_VERSION + 1;
        assert!(core.handle_datagram(&p.to_bytes(), addr(1), now).is_empty());
    }
}
