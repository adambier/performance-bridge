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
| What it is | Performance Bridge, a macOS app (planned) that connects hardware control surfaces to RME TotalMix FX through its Global OSC interface, plus the libraries and developer tool behind it |
| Surfaces | Melbourne Instruments Roto-Control first; Novation Launch Control XL 3 second; Mackie Control (MCU) surfaces possibly later |
| License | MIT (`LICENSE`); not affiliated with or endorsed by RME, Melbourne Instruments, or Novation |
| Language, tooling | Swift, `swift-tools-version:5.9`; CI uses the `swift:6.0-noble` image on Linux, Swift 6.2 on Windows, and the runner's Xcode on macOS; XCTest |
| App platform | macOS 13 or later (`platforms: [.macOS(.v13)]`); SwiftUI plus AppKit; no Xcode project; Sparkle 2 for updates |
| Library platforms | macOS, Linux, and Windows (CI tests all three on every push and pull request) |
| TotalMix checked | TotalMix FX "2.10 (1)" with a Digiface AES (tests 1–5 in `docs/TOTALMIX-OSC.md`); the second target is an HDSPe MADI FX |

## 2. Repository map

| Path | What |
|---|---|
| `Sources/OSCCodec/` | OSC 1.0 packets: `OSCArgument`, `OSCMessage`, `OSCBundle`, `OSCPacket`, encoding and decoding |
| `Sources/TotalMixOSC/` | Global OSC: `TotalMixBus`, `TotalMixCommand` (messages to send), `TotalMixEvent` (messages received), `TotalMixEndpoint` (host and ports), `TotalMixGroupFlags`, `FaderCurve`, `TotalMixVersion` (RME's version numbers; Global OSC needs 2.1 or later) |
| `Sources/RotoControl/` | Roto-Control protocol: `RotoSysEx` (framing, 14-bit numbers, names), `RotoIncoming` and `RotoOutgoing` (SysEx messages), `RotoMIDIParser`, `RotoControlDecoder` and `RotoFeedback` (CCs and 14-bit knobs), `RotoHandshake`, `RotoInputDecoder`; PLUGIN mode in `RotoPlugin.swift` (`RotoHash`, `RotoPluginDetails`, `RotoParameterDetails`, `RotoControlMapping`) |
| `Sources/MIDITransport/` | `MIDIConnection`: a CoreMIDI connection on macOS, a placeholder that throws elsewhere; `UniversalPackets`: MIDI 1.0 bytes to and from CoreMIDI's UMP words (Foundation only, tested everywhere) |
| `Sources/SurfaceCore/` | The surface-neutral core: `SurfaceHub` (the engine: strips, paging, the home submix, holds, pickup, thinning, meters), `MixerMirror` (TotalMix's state), `PerformanceLayout` and `ViewKind`, `SurfaceCapabilities` and `SurfaceMode`, `SurfaceUpdate` and `CoreOutput`, `MeterScale` and `ValueText` |
| `Sources/RotoDriver/` | `RotoDriver`: the Roto-Control's MIX mode on top of SurfaceCore (handshake, track sets, knob and switch modes, single-track pages, strips, knobs, lights, meters, value text); `RotoStep` |
| `Sources/BridgeEngine/` | `BridgeEngine`: TotalMix and a Roto-Control connected through SurfaceCore and RotoDriver, with the UDP socket, the MIDI ports, and a clock; each side connects on its own and is retried every 3 s (an unplugged Roto-Control is reopened, a silent TotalMix asked for its state again); `BridgeSettings`, `BridgeStatus`, `HomeChoice` (for the app's menu); `SetupChecklist` and `SetupStep` (the setup window's steps, checked from the status); `SetupWatch` (when the setup window opens by itself, and the menu-bar warning mark). Platform code, like the transports it uses |
| `Sources/UDPTransport/` | `UDPSocket`: POSIX UDP on macOS and Linux; a placeholder that throws on Windows |
| `Sources/sbdev/` | Developer tool: `monitor`, `send`, `roundtrip`, `curve` (main.swift), `roto` (Roto.swift), `bridge` (Bridge.swift), and `midi` (MIDIMonitor.swift) |
| `App/PerformanceBridge/` | The menu-bar app (macOS only): `swift run PerformanceBridge` (`--in-port`/`--out-port` override the saved ports), or the bundle from `make-app.sh`. The menu, Setup Guide (opens by itself at first launch, and once per launch for a problem that has never worked with the current settings; the status lines at the top of the menu are dimmed and only report; "Refresh Channels from TotalMix FX" asks for TotalMix's whole state and drops channels its answer leaves out, also done by itself when the Channel Layout tab opens and when TotalMix returns after going quiet, since TotalMix doesn't announce hiding or showing a channel (test 11); a red dot on the menu-bar icon marks a fault (port in use, TotalMix running but silent, a Roto-Control plugged in but not connecting); TotalMix closed or the Roto-Control unplugged is idle and leaves no mark; the icon is dimmed whenever either connection is down, and normal when both are up), About (the icon at 128 points), Settings with two tabs, Connections (TotalMix's host and ports, the Roto-Control's MIDI port, kept in the user defaults) and Channel Layout (ordering channels; TotalMix FX has a Channel Layout window too, so app text names TotalMix's as "TotalMix FX's own Channel Layout window"); the menu's order follows Apple's HIG (Menus), and "Check for Updates…" when Sparkle is linked |
| `make-app.sh` | Builds "Performance Bridge.app" with `swiftc` as one module, with Sparkle; signing, notarization, and `--appcast` are the owner's |
| `Design/AppIcon/` | The app icon and menu-bar glyph: `make_icon.py` (geometry, writes the SVGs), the layered master, the legacy icon set, and its README |
| `Tests/` | One test target per library |
| `docs/TOTALMIX-OSC.md` | What this project relies on in Global OSC, with evidence, and the open questions |
| `docs/ROTO-CONTROL.md` | What this project relies on in the Roto-Control's protocol, with evidence, and the open questions |

## 3. Architecture and what comes next

The app keeps TotalMix's state in a surface-neutral core and drives each control surface through a
small driver of its own.

- **SurfaceCore** (`Sources/SurfaceCore/`). The aim is TotalMix FX as a performance mixer, for live use. Channel strips, each with:
  - a knob or fader: level, pan, or a send;
  - a switch: mute, PFL, or solo (off by default);
  - a name, a color, and a meter. Playbacks are named "PB 1/2" and so on, not after the outputs TotalMix names them for.

  Around the strips:
  - two views: sources (inputs and playbacks) and outputs (the assigned monitoring outputs first, then the sends; a monitoring role with nothing assigned shows no strip);
  - a performance layout, chosen in the app: the order of each view (which TotalMix can't change) and whether the first playback starts a new page (blank strips after the inputs); channels it doesn't place yet follow in TotalMix's order; the app has no hide setting of its own. Which channels TotalMix hides from this OSC remote (Options → Channel Layout…, or right-click a channel and choose Change Channel Layout) are set only in TotalMix, per OSC controller, under the rule in section 4;
  - monitoring outputs and sends: the outputs the control room assigns to Main Out, Main Out B, Phones 1–4, and cue are monitoring outputs; every other output TotalMix doesn't hide is a send (the app's text calls monitoring outputs "Control Room" outputs, as TotalMix FX does; Adam, 2026-10-31);
  - the home submix, called "Mix Output" in the app (Adam, 2026-10-31) (Main Out unless the app chooses another control room output, or any other output from the menu's Other Outputs submenu), which source levels and pans go into; send knobs reach every other output except Main Out B (it mirrors Main Out with Speaker B on, test 10) and the cue output, control room outputs first (Adam, 2026-10-31: headphone mixes are the ones changed during a performance). Main Out is followed, not fixed: when Main Out is reassigned in TotalMix's control room, the home moves with it; any other choice stays on its output;
  - paging, and a focus mode (one source across all submixes);
  - the feedback rules: a control the user holds (touched, or moved in the last 250 ms) is not moved by TotalMix and catches up when let go; controls without motors pick up; continuous messages are thinned to one per address per 20 ms; meters update at most 12 times per second.

  `SurfaceHub` is pure: no I/O and no clock, with time passed in.
- **Capabilities.** Each surface declares what it has, and nothing in SurfaceCore assumes a particular controller:
  - how many strips, and which controls each strip has;
  - for each control, whether it is motorized, an endless encoder with an LED ring, or a control that needs pickup;
  - its resolution;
  - its displays.
- **Drivers**, one per surface:
  - **RotoDriver** (`Sources/RotoDriver/`): the Roto-Control's SysEx API, with 14-bit motorized knobs. MIX mode drives the channel strips: the audio track set is the sources view and the master and return set the outputs view; the solo switches are PFL (as TotalMix's Solo is in Live Mode) and the record-arm switches do nothing (the firmware still shows their "ARM REC" label). Sources show their TotalMix color (each of TotalMix's eight colors mapped to a Roto-Control color scheme); outputs show their TotalMix color too, and those left white (TotalMix's default) show by kind, monitoring green and sends blue. PLUGIN mode, for the parts of TotalMix that MIX mode can't reach (e.g., a control-room page to choose the home submix), is left to a 1.x.0 release after 1.0 (Adam, 2026-10-31); until then the driver answers PLUGIN mode with no plugins. The driver is pure, like `SurfaceHub`; the app (or `sbdev bridge`) connects it to `MIDITransport`.
  - **LaunchControlXL3**: the Launch Control XL 3's DAW mode, with 7-bit faders that are not motorized and endless encoders.
  - **MackieControl**: later.
- **Later (version 1.1.0 or after): a DAW connection.** The Roto-Control's record-arm switches would arm and disarm tracks, and its transport switches would drive the transport, in the user's DAW, starting with Logic Pro and Bitwig Studio.
- **Protocol sources.** Each driver's protocol facts go in a `docs/` file of their own, with evidence, as `TOTALMIX-OSC.md` does for TotalMix. The vendors' documents are linked, not committed:
  - Melbourne Instruments' [SysEx and serial API documents and integration code](https://github.com/Melbourne-Instruments/roto_control) (MIT);
  - Novation's [Launch Control XL 3 programmer's reference guide](https://userguides.novationmusic.com/hc/en-gb/articles/27840466285586-About-the-Launch-Control-XL-3-programmer-s-reference-guide).
- **The app.** A SwiftUI app modeled on pgdata Packer's (`adambier/3rd-wave-tools`):
  - `make-app.sh` compiles every library folder and the app into one module with `swiftc` (not `sbdev`); CI type-checks that build on macOS;
  - version 0.1.0 until the first release; the build number is the commit count;
  - Sparkle 2.10.1 is pinned with its SHA-256, and the XPC services are removed;
  - the app is signed with a Developer ID, notarized, and updated through `appcast.xml` on `main`;
  - its icon and menu-bar glyph come from `Design/AppIcon/` (the About window shows the icon at 128 points); the icon's amber, #FFB13D, is the app's accent color;
  - it has its own Sparkle signing key, under the keychain account `org.biers.performancebridge`. The public half, for `SUPublicEDKey`, is `KTt3BYFC8qH22G0zlWbtdfe7E9OGSw14LgkrZQCmfC4=`; the private half stays in the release signer's keychain.

## 4. Rules (do / don't)

Design rule (Adam, 2026-10-31): **whatever can be configured in TotalMix is configured only
there.** Performance Bridge reads it over OSC and offers no setting of its own for it (e.g.,
channel names, colors, which channels a remote sees, the control room's monitoring assignments).
The app has settings only for what TotalMix can't express, such as the order of channels on a
surface. The aim is less for the user to think about: one place to set each thing, and nothing to
keep in step between TotalMix and the app. Where this makes the app's code more complex (e.g.,
reading a setting from TotalMix instead of asking for it), that cost is accepted.

The exception (Adam, 2026-10-31): a separate app setting for something TotalMix also configures is
acceptable when there is a strong case for the surface behaving differently from TotalMix at the
same time. The case is made, and recorded, before the setting is added.

Hidden channels (Adam, 2026-10-31; revised the same day). Hiding is done only in TotalMix, where
Channel Layout can hide a channel from each OSC controller separately, and from the Mixer/Matrix and
the other controllers. The app has no hide setting of its own, so there is nothing to keep in step.
A channel that TotalMix hides from an OSC Controller (Channel Layout, "Hide Channel in") is not shown on any surface that uses that controller, and the app does not
show it greyed out or offer to change it: greyed-out items take up room and cannot be acted on. The
layout shows a note that channels hidden in TotalMix are not shown. The app cannot detect hidden
channels from OSC: a hidden channel sends nothing, as a missing one does (`docs/TOTALMIX-OSC.md`,
test 8). So there is no warning, and the note stands alone.

Documentation rule for TotalMix (Adam, 2026-10-31): TotalMix's menus and configuration screens are
complex, so any text that tells the user where a TotalMix setting is (docs, app help, notes) gives
the full path: each menu and submenu, the setting's label as TotalMix shows it, and the source for
that location. Where the location has not been checked on a screen, say so.

Do:

- Keep `OSCCodec`, `TotalMixOSC`, `RotoControl`, `SurfaceCore`, `RotoDriver`, and the planned drivers Foundation-only, UI-free, and building on Linux, macOS, and Windows. Platform code (CoreMIDI, sockets, SwiftUI) stays in `UDPTransport`, `MIDITransport`, or the app.
- Write cross-library imports as `#if canImport(OSCCodec)` / `import OSCCodec` / `#endif`. The app build will compile every folder as one module, and there such an import must compile out. No two top-level declarations in the library folders may share a name.
- Put any new or changed claim about what TotalMix does in `docs/TOTALMIX-OSC.md` with its evidence: RME's document and its revision, or a test naming the TotalMix version and the interface. Mark inferences as inferences, in the code comment as well as the document. Do the same for the surfaces in their own documents.
- Give every `public` declaration a `///` doc comment.
- Add a test for anything new, and run the tests (section 5) before proposing a change.

Don't:

- Don't commit vendor documents (RME's protocol document, Melbourne Instruments' or Novation's PDFs) or text copied from them. Describe what this project relies on in its own words, and link the source.
- Don't paste vendor code. Melbourne Instruments' integrations are MIT-licensed, so anything adapted from them keeps their copyright notice in the file.
- Don't add dependencies to the libraries.
- Don't use "TotalMix", "RME", "Roto-Control", or "Launch Control" in the app's name. Use them only to describe what it works with.
- Don't touch signing, notarization, `appcast.xml`, or the Sparkle keys. The release flow is the owner's.
- Never write to another app's preferences or files (Adam, 2026-10-31). Reading TotalMix's files is always fine (Adam, 2026-10-31): its app bundle (e.g., its version), and its settings where they can be found; where TotalMix keeps them, and whether it writes them as they change, still needs a test on the Mac.

## 5. How to verify

- **Tests on Linux and Windows:** `swift test`.
- **Tests on a Mac:** `PERFORMANCE_BRIDGE_TESTS=1 swift test`. This needs full Xcode, because XCTest is not part of the Command Line Tools.
- **Against TotalMix:**
  - `swift run sbdev monitor --sendall` prints what TotalMix sends.
  - `swift run sbdev send /input/0/mute 1` sends one message.
  - `swift run sbdev roundtrip /output/8/faderlin 0.5` sends one message and prints what TotalMix sends back in the next second. Stop `monitor` first; both need the outgoing port.
  - For TotalMix's development ports, add `--in-port 7004 --out-port 9004`.
  - `swift run sbdev curve -6dB` and `swift run sbdev curve --table` check the fader curve offline.
- **Against a Roto-Control** (macOS):
  - `swift run sbdev roto ports` lists the MIDI ports.
  - `swift run sbdev roto` connects, runs the handshake, prints everything the Roto-Control sends, and takes commands (`help` lists them). `--type`, `--setup none`, and `--raw` are for the tests in `docs/ROTO-CONTROL.md` section 8.
- **TotalMix and a Roto-Control together** (macOS): `swift run sbdev bridge --in-port 7004 --out-port 9004` runs SurfaceCore and the Roto-Control driver as the app will, and prints what goes to TotalMix (`help` lists the commands).

## 6. House style for text (README, docs, DocC, app strings)

- **Names.** "TotalMix FX" at first mention in a document and "TotalMix" after. "RME", "Melbourne Instruments", and "Novation" in full. "Roto-Control" and "Launch Control XL 3" as the makers write them.
- **Claims.** Standing behavior in the present tense. Single observations as "has been observed to …". Inferences said to be inferences. Never claim more than the evidence supports.
- **Spelling and punctuation.** The serial (Oxford) comma. "e.g.," or "for example" before parenthetical examples. American spelling throughout, in code comments and identifiers too.
- **Words.** Plain, short words, and one term for one thing: channel, submix, mixer node, fader position, gain, strip, surface, driver.
- **"Hardware controller" in user-facing text** (the app, the setup guide, the README's introduction): what the code and the technical docs call a "surface" (Adam, 2026-10-31). TotalMix FX's "OSC Controller" keeps its own name.
- **Send labels.** On a surface, a send is labeled "> " and the output's name (e.g., "> Phones"), never "to …" (Adam, 2026-10-31).
- **Readability.** A prose paragraph longer than about eight lines is broken into paragraphs, or into a list where the parts are parallel.
