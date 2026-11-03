# Performance Bridge

**Performance Bridge** is a macOS menu-bar app that connects hardware controllers to RME TotalMix FX
bidirectionally through TotalMix FX's Global OSC interface.

With Melbourne Instruments' Roto-Control, its motorized knobs turn in real time with the TotalMix
FX faders, with detents and other haptics, and channel names and colors are carried over.

Novation's Launch Control 3 and Launch Control XL 3 are also currently supported.

The repository also holds the Swift libraries behind the app and a developer tool for checking
them against TotalMix FX. The libraries depend only on Foundation, and they build on macOS, Linux, and
Windows.

Performance Bridge is not affiliated with or endorsed by RME, Melbourne Instruments, or Novation.

To set it up, follow the in-app setup guide or preview it here: [`docs/SETUP.md`](docs/SETUP.md).

## Installing

Performance Bridge runs on macOS 13 or later. Download the zip file from the
[latest release](https://github.com/adambier/performance-bridge/releases/latest), open it, and move
"Performance Bridge.app" to the Applications folder. The app is signed with a Developer ID and notarized
by Apple. To update it later, choose **Check for Updates…** from its menu.

The setup guide covers TotalMix FX's settings, the hardware controller, and what each control does. The
app's own Setup Guide (in its menu) checks each step as it goes.

## What it works with

- **TotalMix FX 2.1 or later**, with Global OSC turned on (`docs/SETUP.md`, Step 1). It has been
  tested with TotalMix FX "2.10 (1)" and a Digiface AES.
- **One hardware controller at a time:**
  - **Melbourne Instruments' Roto-Control**, in its MIX mode: eight motorized knobs for level, pan,
    or a send; switches for mute and PFL; and each channel's name, TotalMix FX color, and meter. Tested
    on the device (`docs/ROTO-CONTROL.md`).
  - **Novation's Launch Control XL 3**, in its DAW mode: faders for level, two encoder rows for
    sends and one for pan, PFL and mute buttons, and the screen. Tested on the device
    (`docs/LAUNCH-CONTROL-XL3.md`).
  - **Novation's Launch Control 3**, in its DAW mode: encoders for level and for pan or a send, and
    buttons for mute or PFL. Built from Novation's documents and tried as a simulation on an XL 3,
    but not yet on a Launch Control 3 (`docs/LAUNCH-CONTROL-3.md`).

The app has a menu with the connection states, a Setup Guide, and Settings for TotalMix FX's host and
ports, the hardware controller, a Launch Control's send rows, and the order and labels of the
channels. Everything TotalMix FX can configure itself (e.g., names, colors, and which channels
each OSC Controller sees) is set in TotalMix FX and read from it.

Planned for later releases: the Roto-Control's PLUGIN mode, for the parts of TotalMix FX that MIX mode
can't reach (e.g., the control room); more than one hardware controller at once; and a connection to
a DAW, for arming tracks and controlling the transport, starting with Logic Pro and Bitwig Studio.

## What the repository holds

- **`OSCCodec`**: OSC 1.0 messages and bundles, encoded and decoded.
- **`TotalMixOSC`**: TotalMix FX's Global OSC addresses, the values TotalMix FX sends and accepts, and the curve between a fader's position and its gain.
- **`RotoControl`**: the Roto-Control's MIDI protocol: its SysEx messages, its knobs, switches, and meters, and the handshake that connects it to a host.
- **`LaunchControl`**: the DAW mode protocol of Novation's Launch Control XL 3 and Launch Control 3 (their controls, colors, screen, and settings), from Novation's programmer's reference guides.
- **`SurfaceCore`**: the surface-neutral core. It keeps a copy of TotalMix FX's state and maps it onto any controller's strips: levels and pans in Main Out's submix, sends, mute, PFL, and meters, with paging and a single-channel focus mode. It keeps TotalMix FX from moving a control in the user's hand and makes faders without motors pick up.
- **`RotoDriver`** and **`LaunchControlDriver`**: the drivers for the Roto-Control and the two Launch Controls, on top of `SurfaceCore`.
- **`BridgeEngine`**: TotalMix FX and a hardware controller connected through the core and the drivers: the socket, the MIDI ports, and a clock. Each side connects on its own and is tried again every 3 seconds, so either can be started, quit, or unplugged at any time.
- **The app** (`App/PerformanceBridge/`): the menu-bar app, which runs `BridgeEngine`.
- **`MIDITransport`**: a MIDI connection through CoreMIDI, on macOS.
- **`UDPTransport`**: a small UDP socket, on macOS and Linux.
- **`sbdev`**: a developer tool that prints what TotalMix FX sends and sends single messages to it, talks to a Roto-Control or (`sbdev lcxl`) a Launch Control XL 3, and runs the core and a driver between TotalMix FX and a Roto-Control (`sbdev bridge`) or a Launch Control (`sbdev lcbridge`).

## Building from source

For development, or to try changes before a release, you need Swift 5.9 or later for the libraries and
`sbdev`, plus Xcode or its Command Line Tools to build the app.

### Trying `sbdev` with TotalMix FX

In TotalMix FX, turn on Global OSC (Options → Mixer Settings… → OSC, "Compatibility (Mode)" set to "Global
OSC"; `docs/SETUP.md`, Step 1, has every setting) and note the incoming and outgoing ports. RME's manual
gives 7001 and 9001 as typical values, and they are Performance Bridge's defaults. Then, from this folder:

```
swift run sbdev monitor --sendall
```

That prints every message TotalMix FX sends, after asking TotalMix FX for its whole state. Give other ports
with `--in-port` and `--out-port` and another computer with `--host`.

```
swift run sbdev send /input/0/mute 1
swift run sbdev curve -6dB
```

`swift run sbdev --help` lists everything.

### Running the app from source

On a Mac, quit `sbdev` first (both need TotalMix FX's outgoing port), then:

```
swift run PerformanceBridge
```

The app appears in the menu bar. Set TotalMix FX's host and ports and the hardware controller in
Settings, or give the ports on the command line with `--in-port` and `--out-port`. The connection
log goes to Terminal.

On the command line, `--launch-control xl3` (a Launch Control XL 3), `lc3` (a Launch Control 3), or
`lc3-sim` (the Launch Control 3's layout on an XL 3) overrides the hardware controller chosen in
Settings, and the Roto-Control is then not used; `--launch-control-port NAME` names another MIDI
port.

To build the app itself, `./make-app.sh` makes "Performance Bridge.app" in the package folder (the
Command Line Tools are enough; the first build downloads Sparkle). Open it with
`open "Performance Bridge.app"`, or, to see its log, run
`./"Performance Bridge.app"/Contents/MacOS/PerformanceBridge`. `./make-app.sh debug` makes a debug build.

## Documentation

- **[`docs/TOTALMIX-OSC.md`](docs/TOTALMIX-OSC.md)**: what this project relies on in TotalMix FX's Global OSC, the evidence for each statement, and the questions still to settle by testing.
- **[`docs/SETUP.md`](docs/SETUP.md)**: setting up Performance Bridge with TotalMix FX and a hardware controller, step by step, with what has and has not been checked on screen.
- **[`docs/ROTO-CONTROL.md`](docs/ROTO-CONTROL.md)**: what this project relies on in the Roto-Control's protocol, the evidence for each statement, and the questions still to settle by testing.
- **[`docs/LAUNCH-CONTROL-XL3.md`](docs/LAUNCH-CONTROL-XL3.md)** and **[`docs/LAUNCH-CONTROL-3.md`](docs/LAUNCH-CONTROL-3.md)**: the same for the Launch Control XL 3 and the Launch Control 3.
- **[`AGENTS.md`](AGENTS.md)**: an orientation for AI coding tools and for anyone working on the code.

## License

MIT; see [LICENSE](LICENSE).
