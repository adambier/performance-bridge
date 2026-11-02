# Performance Bridge

**Performance Bridge** will be a macOS app that connects hardware controllers to RME TotalMix FX
through TotalMix's Global OSC interface. With it, the knobs, faders, buttons, and displays of a
hardware controller show and control TotalMix's mixer, in both directions.

Its aim is TotalMix FX as a performance mixer: for mixing live, in practice or on stage, with the
hands on the hardware controller rather than the mouse.

The repository also holds the Swift libraries behind the app, and a developer tool for checking
them against TotalMix. The libraries depend only on Foundation, and they build on macOS, Linux, and
Windows.

Not affiliated with or endorsed by RME, Melbourne Instruments, or Novation.

## Status

This project is in early development. There is no released app yet, only a first look at it, run from source. What exists:

- **`OSCCodec`**: OSC 1.0 messages and bundles, encoded and decoded.
- **`TotalMixOSC`**: TotalMix's Global OSC addresses, the values TotalMix sends and accepts, and the curve between a fader's position and its gain.
- **`RotoControl`**: the Roto-Control's MIDI protocol: its SysEx messages, its knobs, switches, and meters, and the handshake that connects it to a host. Tested against a Roto-Control (`docs/ROTO-CONTROL.md`, section 9).
- **`LaunchControl`**: the DAW mode protocol of Novation's Launch Control XL 3 and Launch Control 3 (their controls, colors, screen, and settings), from Novation's programmer's reference guides. Tested against a Launch Control XL 3 (`docs/LAUNCH-CONTROL-XL3.md`, section 10); the Launch Control 3 has not been tried on a device (`docs/LAUNCH-CONTROL-3.md`).
- **`SurfaceCore`**: the surface-neutral core. It keeps a copy of TotalMix's state and maps it onto any surface's strips: sources (inputs and playbacks) or outputs, levels into a chosen home submix, pans, sends, mute, PFL, and meters, with paging and a single-channel focus mode. It keeps TotalMix from moving a control in the user's hand, and makes faders without motors pick up. Tested on its own.
- **`RotoDriver`**: the Roto-Control's driver on top of `SurfaceCore`, for its MIX mode: inputs and playbacks on the main track set and outputs on the second (monitoring outputs, such as Main Out and the phones, first, then sends), level, pan, and send knob modes, mute, PFL (on the solo switches), single-track pages, names, TotalMix's colors (outputs left white show green for monitoring and blue for sends), lights, and meters. Tried on the hardware through `sbdev bridge`.
- **`LaunchControlDriver`**: the driver for both Launch Control models on top of `SurfaceCore`. On the XL 3: faders for level, an encoder row each for pan or a send, PFL and mute buttons, and the screen. On the Launch Control 3: level and pan or a send on the encoders, and mute or PFL on the buttons. It can run the Launch Control 3's layout on an XL 3. Not yet in the app; tried through `sbdev lcbridge`.
- **`BridgeEngine`**: TotalMix and a Roto-Control connected through the core and the driver: the socket, the MIDI ports, and a clock. Each side connects on its own and is tried again every 3 seconds, so either can be started, quit, or unplugged at any time.
- **The app, a first look**: a menu-bar app (macOS 13 or later) that runs `BridgeEngine`, with the connection states, the home submix, an option to start the playbacks on a new page, About, and Settings for TotalMix's host and ports.
- **`MIDITransport`**: a MIDI connection through CoreMIDI, on macOS.
- **`UDPTransport`**: a small UDP socket, on macOS and Linux.
- **`sbdev`**: a developer tool that prints what TotalMix sends and sends single messages to it, talks to a Roto-Control or (`sbdev lcxl`) a Launch Control XL 3, and runs the core and a driver between TotalMix and a Roto-Control (`sbdev bridge`) or a Launch Control (`sbdev lcbridge`).

## Planned

- **The Roto-Control.** Melbourne Instruments' Roto-Control comes first, driven through its published SysEx API. Its eight motorized knobs follow TotalMix. Version 1.0 uses its MIX mode; its PLUGIN mode, for the parts of TotalMix that MIX mode can't reach (e.g., the control room), comes in a later 1.x release.
- **The Launch Control XL 3 and Launch Control 3.** Novation's Launch Controls come second, in their DAW mode, in the app. The XL 3's faders are not motorized, so they pick up TotalMix's values.
- **The app.** A signed macOS app (macOS 13 or later) with in-app updates, a setup guide, and a layout editor.
- **Later: a DAW connection.** Arming tracks and driving the transport in a DAW from the hardware controller, starting with Logic Pro and Bitwig Studio.

## Requirements

- **TotalMix FX 2.1 or later**, with Global OSC turned on in TotalMix's preferences. Development uses the 2.1 beta.
- **Swift 5.9 or later** for the libraries and `sbdev`.

## Trying `sbdev` with TotalMix

In TotalMix's preferences, turn on Global OSC and note the incoming and outgoing ports. RME's manual
gives 7001 and 9001 as typical values, and they are Performance Bridge's defaults. Then, from this folder:

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

## Trying the app

On a Mac, quit `sbdev` first (both need TotalMix's outgoing port), then:

```
swift run PerformanceBridge
```

The app appears in the menu bar. Set TotalMix's host and ports in Settings, or give the ports on
the command line with `--in-port` and `--out-port`. The connection log goes to the Terminal.

A Launch Control can be tried alongside the Roto-Control before Settings has a place for it:
`--launch-control xl3` for a Launch Control XL 3, `lc3` for a Launch Control 3, or `lc3-sim` for
the Launch Control 3's layout on an XL 3, with `--launch-control-rows send,send,pan` for the XL 3's
encoder rows and `--launch-control-port NAME` for another MIDI port. The menu then shows a third
status line.

To build the app itself, `./make-app.sh` makes "Performance Bridge.app" in the package folder (the
Command Line Tools are enough; the first build downloads Sparkle). Open it with
`open "Performance Bridge.app"`. `./make-app.sh debug` makes a debug build.

The setup guide, [`docs/SETUP.md`](docs/SETUP.md), goes through each step and what the menu says.

## Documentation

- **[`docs/TOTALMIX-OSC.md`](docs/TOTALMIX-OSC.md)**: what this project relies on in TotalMix's Global OSC, the evidence for each statement, and the questions still to settle by testing.
- **[`docs/SETUP.md`](docs/SETUP.md)**: setting up Performance Bridge with TotalMix FX and a Roto-Control, step by step, with what has and has not been checked on screen.
- **[`docs/ROTO-CONTROL.md`](docs/ROTO-CONTROL.md)**: what this project relies on in the Roto-Control's protocol, the evidence for each statement, and the questions still to settle by testing.
- **[`AGENTS.md`](AGENTS.md)**: an orientation for AI coding tools and for anyone working on the code.

## License

MIT; see [LICENSE](LICENSE).
