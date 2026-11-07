# AGENTS.md: Performance Bridge for AI coding tools

This is a machine-first orientation for Claude Code, Cursor, Copilot, and similar tools working in
this repository. Human developers can paste this file into their tool, or point the tool here,
before asking for changes.

`docs/TOTALMIX-OSC.md` is the authority on TotalMix FX's Global OSC as this project uses it. Every
statement there carries its evidence.

## 1. Project at a glance

| Item | Value |
|---|---|
| Repository | `adambier/performance-bridge` (GitHub), Swift package `performance-bridge` |
| What it is | Performance Bridge, a macOS menu-bar app (released from GitHub Releases; 1.0.0 through 1.0.3 on 2026-11-02, 1.0.4 on 2026-11-04) that connects hardware control surfaces to RME TotalMix FX through its Global OSC interface, plus the libraries and developer tool behind it |
| Surfaces | Melbourne Instruments Roto-Control first; Novation Launch Control XL 3 and Launch Control 3 second; the OXI E16 (its Remote Mode) in 1.1.0 (Adam, 2026-11-04); Mackie Control (MCU) surfaces in 1.2.0, to be tested on Adam's Behringer X-Touch (Adam, 2026-11-04) |
| License | MIT (`LICENSE`); not affiliated with or endorsed by RME, Melbourne Instruments, OXI Instruments, or Novation |
| Language, tooling | Swift, `swift-tools-version:5.9`; CI uses the `swift:6.0-noble` image on Linux, Swift 6.2 on Windows, and the runner's Xcode on macOS; XCTest |
| App platform | macOS 13 or later (`platforms: [.macOS(.v13)]`); SwiftUI plus AppKit; no Xcode project; Sparkle 2 for updates |
| Library platforms | macOS, Linux, and Windows (CI tests all three on every push and pull request) |
| TotalMix FX checked | TotalMix FX "2.10 (1)" with a Digiface AES (tests 1–5 in `docs/TOTALMIX-OSC.md`); the second target is an HDSPe MADI FX |

## 2. Repository map

| Path | What |
|---|---|
| `Sources/OSCCodec/` | OSC 1.0 packets: `OSCArgument`, `OSCMessage`, `OSCBundle`, `OSCPacket`, encoding and decoding |
| `Sources/TotalMixOSC/` | Global OSC: `TotalMixBus`, `TotalMixCommand` (messages to send), `TotalMixEvent` (messages received), `TotalMixEndpoint` (host and ports), `TotalMixGroupFlags`, `FaderCurve`, `TotalMixVersion` (RME's version numbers; Global OSC needs 2.1 or later) |
| `Sources/RotoControl/` | Roto-Control protocol: `RotoSysEx` (framing, 14-bit numbers, names), `RotoIncoming` and `RotoOutgoing` (SysEx messages), `RotoMIDIParser`, `RotoControlDecoder` and `RotoFeedback` (CCs and 14-bit knobs), `RotoHandshake`, `RotoInputDecoder`; PLUGIN mode in `RotoPlugin.swift` (`RotoHash`, `RotoPluginDetails`, `RotoParameterDetails`, `RotoControlMapping`) |
| `Sources/LaunchControl/` | The Launch Control XL 3's and Launch Control 3's DAW-mode protocol, from Novation's programmer's reference guides, tested on an XL 3: `LaunchControlModel` (the two models: SysEx header byte, controls, port names), `LaunchControlElement` and `LaunchControlMode` (the control map), `LaunchControlOutgoing` (DAW mode, feature controls, colors, positions, the screen), `LaunchControlText`, `LaunchControlEvent` and `LaunchControlParser` |
| `Sources/LaunchControlDriver/` | `LaunchControlDriver`: both Launch Control models on top of SurfaceCore, as several hub surfaces ("layers") paged together; the XL 3's and the Launch Control 3's layouts, and the Launch Control 3's on an XL 3; `LaunchControlStep`. Its state-free parts are in files of their own as extensions: `LaunchControlScales.swift` (pan, ARC, and fader scales) and `LaunchControlColors.swift` (text fields, colors, brightness, the palette); the rest reads the driver's `private` caches of what it last sent, so it stays in one file (refactoring assessment, 2026-11-04) |
| `Sources/MIDITransport/` | `MIDIConnection`: a CoreMIDI connection on macOS, a placeholder that throws elsewhere; `UniversalPackets`: MIDI 1.0 bytes to and from CoreMIDI's UMP words (Foundation only, tested everywhere) |
| `Sources/SurfaceCore/` | The surface-neutral core: `SurfaceHub` (the engine: strips, paging, the home submix, holds, pickup, thinning, meters), `MixerMirror` (TotalMix FX's state), `PerformanceLayout` and `ViewKind`, `SurfaceCapabilities` and `SurfaceMode`, `SurfaceUpdate` and `CoreOutput`, `MeterScale` and `ValueText` |
| `Sources/RotoDriver/` | `RotoDriver`: the Roto-Control's MIX mode on top of SurfaceCore (handshake, track sets, knob and switch modes, single-track pages, strips, knobs, lights, meters, value text); `RotoStep` |
| `Sources/BridgeEngine/` | `BridgeEngine`: TotalMix FX and a Roto-Control (and a Launch Control, if `BridgeSettings.launchControl` is set: `LaunchControlSetting`) connected through SurfaceCore and the drivers, with the UDP socket, the MIDI ports, and a clock; each side connects on its own and is retried every 3 s (an unplugged Roto-Control is reopened, a silent TotalMix FX asked for its state again); `BridgeSettings`, `BridgeStatus`, `HomeChoice` (for the app's menu); `SetupChecklist` and `SetupStep` (the setup window's steps, checked from the status); `SetupWatch` (when the setup window opens by itself, and the menu-bar warning mark); `DetectedController` (which hardware controllers are plugged in, from the MIDI source names); `ControlsGuide` (the Controls Guide's text). Platform code, like the transports it uses |
| `Sources/UDPTransport/` | `UDPSocket`: POSIX UDP on macOS and Linux; a placeholder that throws on Windows |
| `Sources/sbdev/` | Developer tool: `monitor`, `send`, `roundtrip`, `curve` (main.swift), `roto` (Roto.swift), `bridge` (Bridge.swift), `e16` (E16.swift), `e16bridge` (E16Bridge.swift), `midi` (MIDIMonitor.swift), `lcxl` (LaunchControl.swift), and `lcbridge` (LaunchBridge.swift) |
| `App/PerformanceBridge/` | The menu-bar app (macOS only): `swift run PerformanceBridge` (`--in-port`/`--out-port` override the saved ports), or the bundle from `make-app.sh`. The menu, Setup Guide (an assistant, one step per page with Back and Continue through every page, and a row of step marks; a done page shows its instructions on request, "Show Instructions"; Adam, 2026-11-02; opens by itself the first time the app runs, at the first step not done, or the first note once every check is done, and once per launch at the step of a problem that has never worked with the current settings; the status lines at the top of the menu are dimmed and only report; "Refresh Channels from TotalMix FX" asks for TotalMix FX's whole state and drops channels its answer leaves out, also done by itself when the Channel Layout tab opens and when TotalMix FX returns after going quiet, since TotalMix FX doesn't announce hiding or showing a channel (test 11); a red dot on the menu-bar icon marks a fault (port in use, TotalMix FX running but silent, a Roto-Control plugged in but not connecting); TotalMix FX closed or the Roto-Control unplugged is idle and leaves no mark; the icon is dimmed whenever either connection is down, and normal when both are up), Controls Guide (what each control of a hardware controller does: `ControlsGuide` in BridgeEngine, the same text as docs/SETUP.md, Step 6, which a test checks contains it, each guide in its own section, with the maker's photo under the title; a menu in the top right lists every controller and starts on the one in use, following a change in Settings while open; Adam, 2026-11-02 and 2026-11-04), About (the icon at 128 points), Settings with two tabs, Connections (TotalMix FX's host and ports, the hardware controller, one at a time, listed as Roto-Control, OXI E16, Launch Control XL 3, Launch Control 3 (Adam, 2026-11-04), with no port setting, since each model's MIDI ports have fixed names and the engine finds them (Adam, 2026-11-02); Apply, Revert, and Defaults right under those, boxed with them, and below the box, for a Launch Control, its send rows' outputs, shown as soon as it is chosen, held by the engine for both models and taking effect at once, connected or not (Adam, 2026-11-02); kept in the user defaults; Adam, 2026-11-01) and Channel Layout (ordering channels; the Outputs list shows only the send targets, Adam, 2026-11-02; TotalMix FX has a Channel Layout window too, so app text names TotalMix FX's as "TotalMix FX's own Channel Layout window"); the menu's order follows Apple's HIG (Menus), and "Check for Updates…" when Sparkle is linked |
| `make-app.sh` | Builds "Performance Bridge.app" with `swiftc` as one module, with Sparkle; signing, notarization, and `--appcast` are the owner's |
| `Design/AppIcon/` | The app icon and menu-bar glyph: `make_icon.py` (geometry, writes the SVGs), the layered master, the legacy icon set, and its README |
| `Tests/` | One test target per library |
| `docs/TOTALMIX-OSC.md` | What this project relies on in Global OSC, with evidence, and the open questions |
| `docs/ROTO-CONTROL.md` | What this project relies on in the Roto-Control's protocol, with evidence, and the open questions |
| `docs/LAUNCH-CONTROL-XL3.md` | The same for the Launch Control XL 3, from Novation's documents and tests on the device |
| `docs/LAUNCH-CONTROL-3.md` | The same for the Launch Control 3, from Novation's documents (no device yet) |
| `docs/OXI-E16.md` | The same for the OXI E16's Remote Mode, from OXI's sheet and manual and tests on Adam's unit |

## 3. Architecture and what comes next

The app keeps TotalMix FX's state in a surface-neutral core and drives each control surface through a
small driver of its own.

- **SurfaceCore** (`Sources/SurfaceCore/`). The aim is TotalMix FX as a performance mixer, for live use. Channel strips, each with:
  - a knob or fader: level, pan, or a send;
  - a switch: mute, PFL, or solo (off by default);
  - a name, a color, and a meter. The name is the channel's label if the app gave it one (section 4, recorded exceptions), and otherwise TotalMix FX's name; playbacks without a label are named "PB 1/2" and so on, since an unnamed playback has its output's hardware name (test 15).

  Around the strips:
  - two views: sources (inputs and playbacks) and outputs (the assigned monitoring outputs first, then the sends; a monitoring role with nothing assigned shows no strip). The hardware controllers show only the sources (Adam, 2026-11-01: outputs are set up in TotalMix FX and left alone during a performance); the outputs' order is the order the send controls step through them;
  - a performance layout, chosen in the app and saved: the order of each view (which TotalMix FX can't change), whether the first playback starts a new page (blank strips after the inputs), and the labels; channels it doesn't place yet follow in TotalMix FX's order; the app has no hide setting of its own. Which channels TotalMix FX hides from this OSC remote (Options → Channel Layout…, or right-click a channel and choose Change Channel Layout) are set only in TotalMix FX, per OSC controller, under the rule in section 4;
  - monitoring outputs and sends: the outputs the control room assigns to Main Out, Main Out B, Phones 1–4, and cue are monitoring outputs; every other output TotalMix FX doesn't hide is a send (the app's text calls monitoring outputs "Control Room" outputs and the rest "Hardware Outputs", as TotalMix FX's window does; Adam, 2026-10-31);
  - the home submix, which source levels and pans go into: Main Out, followed when Main Out is reassigned in TotalMix FX's control room. The app's "Mix Output" menu for choosing another was dropped (Adam, 2026-11-01: PFL to the cue output covers previewing); `SurfaceHub.setHomeSubmix` remains for `sbdev`; send knobs reach every other output except Main Out B (it mirrors Main Out whether Speaker B and Link are on or off, tests 10 and 14) and the cue output, control room outputs first (Adam, 2026-10-31: headphone mixes are the ones changed during a performance). Main Out is followed, not fixed;
  - paging, and a focus mode (one source across all submixes);
  - the feedback rules: a control the user holds (touched, or moved in the last 250 ms) is not moved by TotalMix FX and catches up when let go; controls without motors pick up; continuous messages are thinned to one per address per 20 ms; meters update at most 12 times per second.

  `SurfaceHub` is pure: no I/O and no clock, with time passed in.
- **Capabilities.** Each surface declares what it has, and nothing in SurfaceCore assumes a particular controller:
  - how many strips, and which controls each strip has;
  - for each control, whether it is motorized, an endless encoder with an LED ring, or a control that needs pickup;
  - its resolution;
  - its displays.
- **Drivers**, one per surface:
  - **RotoDriver** (`Sources/RotoDriver/`): the Roto-Control's SysEx API, with 14-bit motorized knobs. MIX mode drives the channel strips: both track sets show the sources, and switching keeps the page (the second, "MIX-RTN", chosen by pressing both arrow buttons, used to show the outputs; Adam, 2026-11-01); a mute that is on flashes while TotalMix FX's Mute Master is off, as on a Launch Control (Adam, 2026-11-02); the solo switches are PFL (as TotalMix FX's Solo is in Live Mode) and the record-arm switches do nothing (the firmware still shows their "ARM REC" label). Sources show their TotalMix FX color (each of TotalMix FX's eight colors mapped to a Roto-Control color scheme). PLUGIN mode, for the parts of TotalMix FX that MIX mode can't reach (e.g., a control-room page to choose the home submix), is left to a 1.x.0 release after 1.0 (Adam, 2026-10-31); until then the driver answers PLUGIN mode with no plugins. The driver is pure, like `SurfaceHub`; the app (or `sbdev bridge`) connects it to `MIDITransport`.
  - **LaunchControlDriver** (`Sources/LaunchControlDriver/`, on the `LaunchControl` protocol library; chosen in Settings → Connections): the Launch Control XL 3 and Launch Control 3 in DAW mode, laid out with Adam (2026-11-01):
    - XL 3: faders are level (7-bit, no motor: the device's own pickup holds a fader until it reaches TotalMix FX's level, with the hub's pickup behind it), on the printed ticks (+6, +3, 0, −6, −10, −20, −40, −60, −oo: TotalMix FX's own marks); the top two encoder rows are sends and the bottom row pan, fixed (Novation's order; Adam, 2026-11-01); Page chooses the top send row's output and Shift + Page the middle row's, each skipping the other's, remembered across launches (`LaunchControlDriver.sendOutputs`); send rows light in their output's color, or, for an output left white in TotalMix FX, the row's own hue (teal for the top row, magenta for the middle; Adam, 2026-11-02); an off-by-default setting dims level and send encoders continuously with their level, by exact RGB on a geometric curve, dark at −oo (Adam, 2026-11-02; docs/LAUNCH-CONTROL-XL3.md, tests 17 and 18); encoders show yellow as RGB 127, 85, 0, and buttons keep palette 13; the top buttons are PFL and the bottom mute; on both models mute is orange and PFL yellow, the colors the Roto-Control's firmware gives mute and solo, bright when on and, when off, a dim exact-RGB shade dimmer than the palette's (Adam, 2026-11-02; docs/LAUNCH-CONTROL-XL3.md, test 19).
    - Launch Control 3: the bottom encoder row is level; the top row is pan or a send, stepped by Page up and down; the buttons are mute, and PFL while Function is held (orange for mute, yellow for PFL; Adam, 2026-11-02, replacing a toggle).
    - Both, following the panel's labels and Novation's integrations: Track < and > move by eight strips (with Shift, to the first or last page); Page chooses the sends; the strips show only the sources; level and send encoders use the ARC USB wheel's scale (its detents, read in TotalMix FX: `docs/TOTALMIX-OSC.md`, test 19), with 0 dB at 101 as on the faders; the Novation button brings TotalMix FX to the front, or back to the app that was in front if TotalMix FX already is (Adam, 2026-11-02); Solo/Arm, Mute/Select (XL 3), Record, and Play are left free (Adam, 2026-11-01: arm and transport for a later DAW connection); both Track buttons together go to the first page, and a presence check asks a silent device for its mode every 5 s and enters DAW mode again if it appears to have restarted (Adam, 2026-11-02); Shift + turn resets an encoder, never raising a level (pan to center, a level above 0 dB down to 0 dB, a send to −oo and back on a second Shift + turn, with Shift released and held again), only after Shift has been held 0.3 s with no Page or Track press (Adam, 2026-11-02; the device gives no direction with Shift held); each control's display shows its channel, function, and value, and the home screen the page's channels and where the send rows go (XL 3) or the top row's and buttons' functions (Launch Control 3).
    - The Launch Control 3's layout can run on an XL 3 (`sbdev lcbridge --layout lc3-sim`). The layouts are flagged for the Tier 1 UI review (efficiency and intuitiveness). Details in section 9 of `docs/LAUNCH-CONTROL-XL3.md` and of `docs/LAUNCH-CONTROL-3.md`.
  - **OXI E16** (1.1.0; Adam, 2026-11-04): `OXIE16` (the Remote Mode protocol: SysEx framing and 8-to-7 packing, rings, labels, a host-drawn framebuffer with a 5×7 proportional font of the project's own) and `E16Driver` on SurfaceCore, on the E16's factory firmware (1.3.0 or later; Adam wants no custom firmware). `sbdev e16` is the probe and `sbdev e16bridge` runs the driver with TotalMix FX. Facts and test records: `docs/OXI-E16.md`.
    - Layout (Adam, 2026-11-04; `docs/OXI-E16.md`, section 5): sixteen strips a page, always the sources; turn is level, pan, or a send by the mode; press and release is mute; a 1 s hold is PFL, with a countdown arc after a 0.25 s tap window; push and turn is pan (the level in PAN mode), and a turn while pushed cancels the push (1.1.1); only the ACK connects the driver (a turn or a push from a device in its own scene looks the same).
    - Shift makes the encoders buttons, as the E16's own firmware's hold menu does: 1 LEVEL white, 2 PAN magenta, 3 SEND deep green, 11/12 the previous and next send output, 15/16 the previous and next page, blue; 13/14 the layout (16 channels, 4 channel strips), yellow, in both layouts; in 4 channel strips, 3/4 send A's output and 7/8 send B's, each skipping the other's. Back and forward always in the right two columns of a row, back on the left, on every Shift page (Adam, 2026-11-05), labeled as a "< WORD >" pair ("< SEND >", "< PAGE >": one word, one word space each side, the ">" at the cell's right margin, every arrow on a page lined up); blank and dark where an arrow goes nowhere, pressed or not. A Shift-page label names what its button selects (a mode, a layout, an output, a page), and the lighting shows which is current; mode and layout buttons follow one rule. Ring levels: off; available, at the lowest level that keeps the color's proportions (`availableColor`); in use, pulsing once a second between that and the brightness setting (never below 8), starting bright when Shift goes down, so it reads by motion at any brightness (Adam, 2026-11-07; docs/OXI-E16.md, test 11); pressed, the button's color with its largest part at 127. (The firmware's own page view is a tap-toggle with direct page buttons on knobs 1–12; the doc says how the two compare.)
    - Rings, by the UI review of 2026-11-04 as changed in 1.1.1 (Adam, 2026-11-05): a level fills the ring at 0 dB and above; dark means no strip, unless marks turn on it: four marks a quarter ring apart, orange for mute and pink for PFL, interleaved when both (drawn with LED messages after the RING message, which hold until the next RING: test 5); a mute set while Mute Master is off shows its marks still, alternating with the level, or, with PFL on, turning with PFL's and blinking; a pan is red as soon as it is off center and stops at center when turned, however fast (a pause of 0.05 s, then 2 units, to move past, and leaving moves one step; test 10), drawn at least 1/16 of its range off the top (one LED at R1, test 7); TotalMix FX's colors remapped so they stay apart on the LEDs (gray as cyan).
    - Screen: host-drawn; the mode (or, in 4 channel strips, send A's and B's outputs) at the left, a PFL on another page and the page at the right; names centered in their 32 px cells, no wider than 26 px, shortened as a set so no two come out the same (`fitSet`), a stereo pair keeping both numbers ("ADT3/4", "P15/16", "15/16"; only a three-digit pair is cut); values in fixed digit places, blank at rest; mute and PFL also marked on the name; drawn and packed only when something on it changed.
    - Settings → Connections shows a Brightness slider for the rings, reading 1–100 for 3%–80% of the LEDs' output (the usable range Adam found on the device; a pressed Shift button is always full), default 55% (68 on the slider), live and saved. It is a must-have, since full brightness is unusable in a dark room. The colors and brightness are to be tuned by side-by-side comparison after 1.1.0, at Tier 1 (constants only).
    - Two layouts from 1.2.0, a Settings choice that the Shift page's layout buttons also switch (saved either way): "16 channels" (above) and "4 channel strips" (four channels a page, one column each: send A, send B, pan, level, top to bottom; sends A and B are outputs chosen in Settings or on the Shift page, never the same, saved; a push of any encoder in a column mutes or PFLs that channel, shown on its level ring). Meters under the names are a Settings choice (off by default; TotalMix FX's "Send Level Data" on and "Peak Hold" off). Settings text stays minimal: what a control does is in the Controls Guide, not under the control (Adam, 2026-11-07).
  - **MackieControl** (1.2.0; Adam, 2026-11-04): a Mackie Control driver, to be tested on Adam's Behringer X-Touch (nine motorized touch faders, eight scribble strips, eight encoders with LED rings, meters, jog wheel; USB first, RTP MIDI over Ethernet maybe later). In order: `docs/MACKIE-CONTROL.md` from linkable sources (the Logic Control / Mackie Control reference, Behringer's X-Touch documents for its MC mode, and open implementations for the dialect questions), with a fresh-agent fact check; `sbdev mcu` as the probe; the driver on SurfaceCore, with the layout decided with Adam (open: what the ninth, master fader does, e.g., Main Out's volume; what Select means). New for the core: motor feedback under the hold rule, and meters on a surface that can show them. The X-Touch's mode (MC, HUI, Ctrl) is chosen on the device at power-on and kept, so the Setup Guide gets a step for it. Softube's Console 1 Fader Mk III was looked at (2026-11-04): Softube documents no native protocol, only MIDI CC, MCU, and HUI modes through its On-Screen Display app, so it would be an MCU device here, not a driver of its own. Written before the "more than one controller" item below, which it interacts with (an X-Touch next to the Roto-Control is the obvious case).
- **Later (version 1.2.0 or after): more than one hardware controller at once** (Adam, 2026-11-02, from the Tier 3 review of that date). One at a time is enough for 1.0. The plan: a list in Settings → Connections with a "Use" checkbox per controller, opt-in only; a Launch Control is never connected automatically, since connecting leaves DAW mode and enters it again (`startBytes`), which would end a DAW's own session with the device. The one exception (Adam, 2026-11-02): in each launch, until a hardware controller has connected or the user has applied Settings, the app switches to a controller found plugged in (by its MIDI port names alone, `DetectedController`) when the chosen one isn't and exactly one other is. Flagged for a usability review (Adam, 2026-11-02).
- **Later (version 1.2.0 or after): a DAW connection.** The Roto-Control's record-arm switches would arm and disarm tracks, and its transport switches would drive the transport, in the user's DAW, starting with Logic Pro and Bitwig Studio.
- **Protocol sources.** Each driver's protocol facts go in a `docs/` file of their own, with evidence, as `TOTALMIX-OSC.md` does for TotalMix FX. The vendors' documents are linked, not committed:
  - Melbourne Instruments' [SysEx and serial API documents and integration code](https://github.com/Melbourne-Instruments/roto_control) (MIT);
  - Novation's [Launch Control XL 3 programmer's reference guide](https://userguides.novationmusic.com/hc/en-gb/articles/27840466285586-About-the-Launch-Control-XL-3-programmer-s-reference-guide).
- **The app.** A SwiftUI app modeled on pgdata Packer's (`adambier/3rd-wave-tools`):
  - `make-app.sh` compiles every library folder and the app into one module with `swiftc` (not `sbdev`); CI type-checks that build on macOS;
  - version 1.0.0 was the first release, and 1.0.1, 1.0.2, and 1.0.3 followed (all 2026-11-02), then 1.0.4 (2026-11-04); the build number is the commit count; the update notes Sparkle shows are `hw-tests/release-notes-<version>.md`, which git ignores, so they live on the release signer's Mac;
  - Sparkle 2.10.1 is pinned with its SHA-256, and the XPC services are removed;
  - the app is signed with a Developer ID, notarized, and updated through `appcast.xml` on `main`;
  - its icon and menu-bar glyph come from `Design/AppIcon/` (the About window shows the icon at 128 points); the icon's amber, #FFB13D, is the app's accent color, used only when the user's accent color is Multicolor, as Apple's HIG (Color) has it, and the user's own accent color otherwise (Adam, 2026-10-31);
  - it has its own Sparkle signing key, under the keychain account `org.biers.performancebridge`. The public half, for `SUPublicEDKey`, is `KTt3BYFC8qH22G0zlWbtdfe7E9OGSw14LgkrZQCmfC4=`; the private half stays in the release signer's keychain.

## 4. Rules (do / don't)

Design rule (Adam, 2026-10-31): **whatever can be configured in TotalMix FX is configured only
there.** Performance Bridge reads it over OSC and offers no setting of its own for it (e.g.,
channel names, colors, which channels a remote sees, the control room's monitoring assignments).
The app has settings only for what TotalMix FX can't express, such as the order of channels on a
surface. The aim is less for the user to think about: one place to set each thing, and nothing to
keep in step between TotalMix FX and the app. Where this makes the app's code more complex (e.g.,
reading a setting from TotalMix FX instead of asking for it), that cost is accepted.

The exception (Adam, 2026-10-31): a separate app setting for something TotalMix FX also configures is
acceptable when there is a strong case for the surface behaving differently from TotalMix FX at the
same time. The case is made, and recorded, before the setting is added.

Design rule for virtual detents on encoders (Adam, 2026-11-06): a virtual detent (a pan's sticky
center, a push-and-turn stop) holds a turn until the turn pauses, and the pause sets the balance between going
on easily on purpose and going past by accident. Choose it by what going past costs and by whether
going on is part of the same move: cheap to pass and part of the move (a pan just past center,
then turned on carefully) means a short pause that doesn't slow the user down; costly to pass and a
separate move (a jump to −∞ or +6 dB) means a longer pause, which then costs the user less: going
past should feel like two movements in the second case and one in the first. Too long feels like a
dead knob, worst for a slow, careful turn, since every message restarts the pause and a slow turn's
messages can keep it from ever ending. Aim for water (Adam): a wall when hit fast, little
resistance to slow movement. The pause is the detent's strength (getting past means stopping and
going again, a small re-commitment); a count of units turned before it lets go is only a guard
against a brush, felt as slack rather than resistance, so keep it the smallest that does that job.
Where a surface has real detents (the Roto-Control's 0 dB indent), put the virtual ones at the same
points. Start there, tune on the device with a trial flag, and record the tuning
(`docs/OXI-E16.md`, section 5: 0.05 s at a pan's center, 0.075 s between jumps).

Recorded exceptions:
- **Labels** (Adam, 2026-11-01). The app can give any channel a label of its own, shown only on
  the hardware controllers; a channel without one shows TotalMix FX's name. The case: TotalMix FX's names
  serve TotalMix FX (routing, the matrix, recall), while a hardware controller's labels serve quick
  mixing on a small screen; and TotalMix FX's default playback names repeat its inputs' hardware names
  ("AES", "SPDIF", …; test 15), which Global OSC can't tell from names the user gave. A playback
  without a label keeps showing "PB 1/2". The UI and its wording get a close look in the UI review
  and Adam's own (Adam, 2026-11-01).

Safety interlock, decided but not yet buildable (Adam, 2026-11-02): while TotalMix FX's "Cue/PFL to" is
Main (its default), PFL would replace what Main Out plays, which on stage is what the audience
hears, so the hardware controllers should not turn PFL on then. TotalMix FX doesn't report that
setting over OSC (`docs/TOTALMIX-OSC.md`, test 21), so the app can't tell; the Setup Guide has a
note instead. Build the interlock if a way to read the setting is found (read-only; e.g.,
TotalMix FX's settings file).

Hidden channels (Adam, 2026-10-31; revised the same day). Hiding is done only in TotalMix FX, where
Channel Layout can hide a channel from each OSC controller separately, and from the Mixer/Matrix and
the other controllers. The app has no hide setting of its own, so there is nothing to keep in step.
A channel that TotalMix FX hides from an OSC Controller (Channel Layout, "Hide Channel in") is not shown on any surface that uses that controller, and the app does not
show it greyed out or offer to change it: greyed-out items take up room and cannot be acted on. The
layout shows a note that channels hidden in TotalMix FX are not shown. The app cannot detect hidden
channels from OSC: a hidden channel sends nothing, as a missing one does (`docs/TOTALMIX-OSC.md`,
test 8). So there is no warning, and the note stands alone.

Documentation rule for TotalMix FX (Adam, 2026-10-31): TotalMix FX's menus and configuration screens are
complex, so any text that tells the user where a TotalMix FX setting is (docs, app help, notes) gives
the full path: each menu and submenu, the setting's label as TotalMix FX shows it, and the source for
that location. Where the location has not been checked on a screen, say so.

Do:

- Keep `OSCCodec`, `TotalMixOSC`, `RotoControl`, `LaunchControl`, `SurfaceCore`, `RotoDriver`, `LaunchControlDriver`, and the planned drivers Foundation-only, UI-free, and building on Linux, macOS, and Windows. Platform code (CoreMIDI, sockets, SwiftUI) stays in `UDPTransport`, `MIDITransport`, or the app.
- Write cross-library imports as `#if canImport(OSCCodec)` / `import OSCCodec` / `#endif`. The app build will compile every folder as one module, and there such an import must compile out. No two top-level declarations in the library folders may share a name.
- Put any new or changed claim about what TotalMix FX does in `docs/TOTALMIX-OSC.md` with its evidence: RME's document and its revision, or a test naming the TotalMix FX version and the interface. Evidence goes in a named footnote (`[^rme-doc]`, `[^test-7]`), as pgdata Packer's `docs/FORMATS.md` does; each protocol doc's first section says how sure each statement is and defines its footnotes. Mark inferences as inferences, in the code comment as well as the document. Do the same for the surfaces in their own documents.
- Give every `public` declaration a `///` doc comment.
- Add a test for anything new, and run the tests (section 5) before proposing a change.

Don't:

- Don't commit vendor documents (RME's protocol document, Melbourne Instruments', OXI Instruments', or Novation's PDFs and sheets) or text copied from them. Describe what this project relies on in its own words, and link the source.
  Two exceptions. Screenshots of TotalMix FX's windows (Adam, 2026-10-31) may be published. They live in `App/PerformanceBridge/Resources/` (`totalmix-*.png`, Retina captures), where the Setup Guide shows them and `docs/SETUP.md` links to them. Performance Bridge's own windows are there too (`app-*.png`); whenever a window or menu item they show changes, ask Adam for a new screenshot (Adam, 2026-11-02). Take them from TotalMix FX itself, controller 1 with ports 7001 and 9001, and replace personal details such as the Mac's name ("your-mac.local"). The makers' product photos of the hardware controllers (Adam, 2026-11-04) are the second exception: `controller-*.png`, the top views from Novation's, Melbourne Instruments', and OXI Instruments' websites, cropped to the device itself (no shadow; the Roto-Control's inside its lit rim, which read as a halo on a dark window), fully opaque, and scaled to one height, 316 pixels (158 points), the tallest at which the widest, the Roto-Control's, fits the page (Adam, 2026-11-04), shown by the Controls Guide and `docs/SETUP.md`, Step 6, and credited there. They are the makers' images, not MIT-licensed with the rest of the repository. Each controller's guide is written to stand alone, since the window shows one at a time (Adam, 2026-11-04).
- Don't paste vendor code. Melbourne Instruments' integrations are MIT-licensed, so anything adapted from them keeps their copyright notice in the file.
- Don't add dependencies to the libraries.
- Don't use "TotalMix", "RME", "Roto-Control", or "Launch Control" in the app's name. Use them only to describe what it works with.
- Don't touch signing, notarization, `appcast.xml`, or the Sparkle keys. The release flow is the owner's.
- Never write to another app's preferences or files (Adam, 2026-10-31). Reading TotalMix FX's files is always fine (Adam, 2026-10-31): its app bundle (e.g., its version), and its settings where they can be found; where TotalMix FX keeps them, and whether it writes them as they change, still needs a test on the Mac.

## 5. How to verify

- **Tests on Linux and Windows:** `swift test`.
- **Tests on a Mac:** `PERFORMANCE_BRIDGE_TESTS=1 swift test`. This needs full Xcode, because XCTest is not part of the Command Line Tools.
- **Against TotalMix FX:**
  - `swift run sbdev monitor --sendall` prints what TotalMix FX sends.
  - `swift run sbdev send /input/0/mute 1` sends one message.
  - `swift run sbdev roundtrip /output/8/faderlin 0.5` sends one message and prints what TotalMix FX sends back in the next second. Stop `monitor` first; both need the outgoing port.
  - For TotalMix FX's development ports, add `--in-port 7004 --out-port 9004`.
  - `swift run sbdev curve -6dB` and `swift run sbdev curve --table` check the fader curve offline.
- **Against a Roto-Control** (macOS):
  - `swift run sbdev roto ports` lists the MIDI ports.
  - `swift run sbdev roto` connects, runs the handshake, prints everything the Roto-Control sends, and takes commands (`help` lists them). `--type`, `--setup none`, and `--raw` are for the tests in `docs/ROTO-CONTROL.md` section 8.
- **Against a Launch Control XL 3** (macOS): `swift run sbdev lcxl` puts it in DAW mode, prints what it sends, and takes commands (`help` lists them); the tests are in `docs/LAUNCH-CONTROL-XL3.md` section 8.
- **TotalMix FX and a Launch Control together** (macOS): `swift run sbdev lcbridge` runs SurfaceCore and the Launch Control driver (`--layout xl3`, `lc3`, or `lc3-sim` for the Launch Control 3's layout on an XL 3; `--help` lists the rest). In the app, choose it in Settings → Connections; `swift run PerformanceBridge --launch-control xl3` (or `lc3`, `lc3-sim`; also `--launch-control-port`; `LaunchControlSetting(arguments:)`) overrides that, e.g., for the simulation.
- **TotalMix FX and a Roto-Control together** (macOS): `swift run sbdev bridge --in-port 7004 --out-port 9004` runs SurfaceCore and the Roto-Control driver as the app does, and prints what goes to TotalMix FX (`help` lists the commands).

## 6. House style for text (README, docs, DocC, app strings)

- **Names.** "TotalMix FX" always, never the short "TotalMix" (Adam, 2026-11-02), except in code identifiers (e.g., `TotalMixOSC`) and in TotalMix FX's own labels that use it (e.g., its "TotalMix 1.96" compatibility mode). "RME", "Melbourne Instruments", and "Novation" in full. "Roto-Control" and "Launch Control XL 3" as the makers write them.
- **Claims.** Standing behavior in the present tense. Single observations as "has been observed to …". Inferences said to be inferences. Never claim more than the evidence supports.
- **Spelling and punctuation.** The serial (Oxford) comma. "e.g.," or "for example" before parenthetical examples. American spelling throughout, in code comments and identifiers too.
- **Words.** Plain, short words, and one term for one thing: channel, submix, mixer node, fader position, gain, strip, surface, driver.
- **"Hardware controller" in user-facing text** (the app, the setup guide, the README's introduction): what the code and the technical docs call a "surface" (Adam, 2026-10-31). TotalMix FX's "OSC Controller" keeps its own name.
- **Send labels.** On a surface, a send is labeled "> " and the output's name (e.g., "> Phones"), never "to …" (Adam, 2026-10-31).
- **Commas before "and".** No comma before "and" joining only two items or two short parts (e.g., "Click Details and check …"); the serial comma, for three or more, stays (Adam, 2026-10-31).
- **Instructions in user-facing text.** Tell the user what to do, in the imperative ("Hide and show channels in TotalMix FX."), and say what is optional with "can" ("Channel colors can be set in the same window."), rather than describing it in the passive ("Channels are hidden in TotalMix FX.") (Adam, 2026-10-31).
- **Readability.** A prose paragraph longer than about eight lines is broken into paragraphs, or into a list where the parts are parallel.
