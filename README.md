# totalmix-surface-tools

**Surface Bridge** will be a macOS app that connects hardware control surfaces to RME TotalMix FX
through TotalMix's Global OSC interface. With it, the knobs, faders, buttons, and displays of a
surface show and control TotalMix's mixer, in both directions.

The repository also holds the Swift libraries behind the app, and a developer tool for checking
them against TotalMix. The libraries depend only on Foundation, and they build on macOS, Linux, and
Windows.

Not affiliated with or endorsed by RME, Melbourne Instruments, or Novation.

## Status

This project is in early development, and there is no app yet. What exists:

- **`OSCCodec`**: OSC 1.0 messages and bundles, encoded and decoded.
- **`TotalMixOSC`**: TotalMix's Global OSC addresses, the values TotalMix sends and accepts, and the curve between a fader's position and its gain.
- **`RotoControl`**: the Roto-Control's MIDI protocol: its SysEx messages, its knobs, switches, and meters, and the handshake that connects it to a host. Not yet tested against the hardware.
- **`UDPTransport`**: a small UDP socket, on macOS and Linux.
- **`sbdev`**: a developer tool that prints what TotalMix sends and sends single messages to it.

## Planned

- **The Roto-Control.** Melbourne Instruments' Roto-Control comes first, driven through its published SysEx API. Its eight motorized knobs follow TotalMix.
- **The Launch Control XL 3.** Novation's Launch Control XL 3 comes second, in its DAW mode. Its faders are not motorized, so they pick up TotalMix's values.
- **The app.** A macOS app (macOS 13 or later) with in-app updates.

## Requirements

- **TotalMix FX 2.1 or later**, with Global OSC turned on in TotalMix's preferences. Development uses the 2.1 beta.
- **Swift 5.9 or later** for the libraries and `sbdev`.

## Trying `sbdev` with TotalMix

In TotalMix's preferences, turn on Global OSC and note the incoming and outgoing ports. The defaults
are 7001 and 9001. Then, from this folder:

```
swift run sbdev monitor --sendall
```

That prints every message TotalMix sends, after asking TotalMix for its whole state. Other ports are
given with `--in-port` and `--out-port`, and another computer with `--host`.

```
swift run sbdev send /input/0/mute 1
swift run sbdev curve -6dB
```

`swift run sbdev --help` lists everything.

## Documentation

- **[`docs/TOTALMIX-OSC.md`](docs/TOTALMIX-OSC.md)**: what this project relies on in TotalMix's Global OSC, the evidence for each statement, and the questions still to settle by testing.
- **[`docs/ROTO-CONTROL.md`](docs/ROTO-CONTROL.md)**: what this project relies on in the Roto-Control's protocol, the evidence for each statement, and the questions still to settle by testing.
- **[`AGENTS.md`](AGENTS.md)**: an orientation for AI coding tools and for anyone working on the code.

## License

MIT; see [LICENSE](LICENSE).
