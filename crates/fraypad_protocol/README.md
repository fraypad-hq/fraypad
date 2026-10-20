# fraypad_protocol

The wire format shared by the Fraypad client and server.

Everything exchanged over UDP is a single fixed-size 16-byte [`Packet`],
little-endian on the wire, carrying a `magic` + `version` header so a receiver
can reject garbage and stale clients before reading any other field. A `kind`
field selects which of the remaining fields are meaningful for that packet
(Hello / Welcome / Reject / Bye / Input / Heartbeat / Pong / Rumble / Resync).

Input events are encoded with Linux evdev codes. That is a transport detail
only: each backend (Linux `uinput` today, a native driver elsewhere) maps these
codes onto its own device semantics, so the protocol itself stays
backend-agnostic.

See the crate-level docs for the full field-by-field layout, and the `codes`
module for the named event codes and routing helpers.

Licensed Apache-2.0.
