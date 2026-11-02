# The Launch Control 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control 3 (not the XL) in DAW mode,
as `LAUNCH-CONTROL-XL3.md` is for the Launch Control XL 3. Every statement carries its evidence.

**Status (2026-11-01).** Nothing here has been checked on a device: the project has no Launch
Control 3. Everything comes from Novation's documents and Bitwig's extension for the device, with
inferences marked. The two programmer's reference guides differ only in the SysEx header byte,
the version, the bootloader's buttons, the controls the Launch Control 3 lacks (faders, the third
encoder row, the second button row, and their feature controls 70 and 73), the fader touch
example, the mode list's prose, and the display-target note (compared by text, 2026-11-01). The
XL 3 has been tested (`LAUNCH-CONTROL-XL3.md`, section 10), so where the guides agree, the XL 3's
tests are good evidence for the Launch Control 3 too; that is still an inference until a unit is
tried. The driver's Launch Control 3 layout can be tried on an XL 3 (section 9).

## 1. Sources

Novation's documents are linked, not committed (AGENTS.md, section 4).

- **[Programmer's reference guide]** "Launch Control 3 programmer's reference guide", version 1.1,
  PDF dated March 3, 2026, 17 pages
  ([Novation's downloads page](https://downloads.novationmusic.com/novation/launch-control/launch-control-3);
  [PDF](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/launch_control_3_programmer_s_reference_guide.pdf)).
  The main source. Its control map (page 9) and palette (page 12) are pictures.
- **[User guide]** "Launch Control 3 user guide", version 1.1, PDF dated March 3, 2026, 69 pages
  ([PDF](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/launch_control_3_user_guide_v1.1_pdf_en.pdf)).
- **[Bitwig extension]** `LC3.bwextension`, in Novation's "Launch Control 3 Bitwig Integration"
  download (same page). Read for the port names it looks for and the button numbers it uses (from
  its compiled classes; nothing copied). It holds the Launch Control 3's and the XL 3's code in
  one package, and registers only the Launch Control 3.
- **[Bitwig help]** The two PDFs that come with it: the help file inside the extension ("Launch
  Control 3") and "LC3 Setup Bitwig". Between them they give the port names on macOS, Windows, and
  Linux, and the roles of Function and the Novation button in Bitwig.
- **[Sound On Sound]** "Novation introduce the Launch Control 3", news item of March 3, 2026
  ([link](https://www.soundonsound.com/news/novation-introduce-launch-control-3)): the release.

Bracketed tags below name the source. "Inference" marks anything the sources don't say outright.

## 2. The device

- 16 endless encoders in two rows of eight, each with an RGB LED; 8 buttons in one row; an OLED
  screen; and Page (up and down), Track (< and >), Shift, Mode, and Function buttons. [User guide,
  "Introduction", "Launch Control 3's Top Panel", and "Technical Specifications"]
- A button with Novation's logo next to Function: the user guide's row of 10 buttons is Function,
  this button, and the 8. [User guide, "Using the Launch Control 3's buttons"; programmer's
  reference guide, control map; Bitwig help]
- No faders, and no Record, Play, Solo/Arm, or Mute/Select buttons. [Programmer's reference guide,
  control map]
- One USB-C port, and DIN MIDI In, Out, and Out 2/Thru. [User guide, "Launch Control 3's back
  panel" and "Technical Specifications"; Sound On Sound]
- The screen is 128 × 64 pixels. [Programmer's reference guide, "Bitmap"]
- The Function button is labeled "DAW" underneath, and Mode "Edit". [Programmer's reference guide,
  control map picture]

## 3. MIDI ports

- As on the XL 3: a MIDI pair, a DAW pair, and two "To DIN" outputs over USB. A host using DAW
  mode talks to the DAW pair, and in DAW mode the DIN outputs send nothing. [Programmer's
  reference guide, "MIDI on Launch Control 3" and the note in "Launch Control 3 programmer's DAW
  mode"]
- The device ID (1–8, set in the bootloader by holding both Page buttons while plugging in) is
  part of the port names. [Programmer's reference guide, "Entering Launch Control 3's bootloader"]
- **Port names.** On macOS, Bitwig's extension looks for "LC3 1 DAW Out" and "LC3 1 DAW In", and
  its help lists them under Mac; on Linux "LC3 1 LC3 1 DAW Out/In", and on Windows
  "MIDIIN2/MIDIOUT2 (LC3 1 MIDI)". [Bitwig extension; Bitwig help] Novation's own setup for
  Ableton Live says to choose the DAW Out and DAW In ports on macOS. [User guide, "Controlling
  Ableton Live with the Launch Control 3"] The driver matches "LC3 1 DAW". That CoreMIDI's names
  are Bitwig's is an inference; for the XL 3 they were (its test 1).

## 4. DAW mode

- **Entering and leaving.** The same messages as the XL 3: note 12 on channel 16, velocity 127 to
  enter and 0 to leave, or the SysEx form (command 02h). [Programmer's reference guide, "DAW mode
  control"] That the device echoes the note, as the XL 3 does (its test 1), is an inference.
- **The default mode.** Connected to a DAW, the encoders start in DAW Mixer. [User guide,
  "Controlling your DAW with the Launch Control 3"]
- **Firmware 1.2 and "DAW Connect".** Novation's Logic Pro script for the Launch Control 3
  (version 1.1) is listed as adding support for a "DAW Connect" feature of firmware 1.2 (Novation's
  downloads page, read 2026-11-01). The user guide v1.1 has no such setting, so the guides predate
  1.2 (inference). On the XL 3, firmware 1.2's "Connect Only" leaves the device in its Custom
  Mode (`LAUNCH-CONTROL-XL3.md`, section 2a); the driver selects DAW Mixer on connecting, for that
  case.
- **SysEx header.** F0h 00h 20h 29h 02h **16h**, where the XL 3 has 15h. [Programmer's reference
  guide, "SysEx message format used by Launch Control 3"; Bitwig extension]
- **Control map.** [Programmer's reference guide, "The surface in DAW mode", picture, unless
  marked]
  - Encoders: top row 13–20, bottom row 21–28, on channel 16 (the XL 3's top two rows).
  - Buttons: 37–44, on channel 1 (the XL 3's top row), although they sit at the bottom of the panel.
  - Shift: channel 7, Control Change 63. [Same section's text, and the feature control table]
  - Page, Track, Function, and the Novation button aren't numbered in the picture. Bitwig's
    Launch Control 3 code reads Page as 106 (up) and 107 (down), Track as 103 (<) and 102 (>), the
    Novation button as 104, and **Function as 66**, the XL 3's Mute/Select (the XL 3's Solo/Arm, 65,
    appears only in its XL 3 code). [Bitwig extension] That the device sends these is an
    inference.
- **Modes.** Channel 7, Control Change 30, reports and selects the surface mode: 1 DAW Mixer,
  2 DAW Control, 6–9 Custom Modes 1–4, 18–21 Custom Modes 5–8. [Programmer's reference guide,
  "Mode report and select"] Its feature control table gives 18–29 for Custom Modes 5–16 (section 8).
- **On the device** (user guide, "Mode button (Edit)" and "Using the Function (DAW) button"):
  - Mode enters mode selection, where the 8 buttons choose a mode; the current one is lit white.
  - Mode and Function together cycle between DAW Control and DAW Mixer.
  - In DAW modes, Function changes what the 8 buttons control (Solo, Arm, Mute, or Select in
    Novation's DAW integrations). [User guide, "Launch Control 3's Top Panel" and "Using the
    Launch Control 3's buttons"; Bitwig help] Whether Function has an LED is not in Novation's
    documents; Bitwig's code lights 66 (inference).
  - On the XL 3, choosing a DAW mode on the device changed nothing it sends and was left to the
    host (`LAUNCH-CONTROL-XL3.md`, test 6). That the Launch Control 3 behaves the same is an
    inference.
- **Relative encoders.** Feature controls 69 (top row) and 72 (bottom row), 127 on and 0 off. In
  relative mode the rows report 77–84 and 85–92, with 64 as no movement, 65 one step clockwise,
  and 63 one step anticlockwise. [Programmer's reference guide, "Absolute and relative encoder
  modes"]
- **Positions.** Absolute encoders take position information from the host. [Programmer's
  reference guide, same section] On the XL 3 the message is the encoder's own Control Change sent
  back on channel 16 (its test 2); the same here is an inference.
- **Touch reports.** Feature control 71; the reports come on channel 15. [Programmer's reference
  guide, "Continuous control touch events"] On the XL 3 they come from movement, with the control's
  own number, or its relative number in relative mode (its tests 1 and 2); the same here is an
  inference.
- **No fader pickup.** The feature control table has no feature 70; the device has no faders.

## 5. Lights and the screen

- **Palette colors** by Control Change on channel 1, with the control's number; **RGB** by SysEx
  01h 53h; Shift takes no color. For RGB, encoder LEDs take their absolute numbers in either
  encoder mode; for palette colors that is an inference. [Programmer's reference guide, "Colouring
  the surface" and "RGB Colour"] The palette picture is the same image as the XL 3 guide's
  (identical files, compared 2026-11-01); that the device shows those colors is an inference.
- **The screen** works as the XL 3's: configure a display (SysEx 04h), then fill its text fields
  (SysEx 06h), with the same four arrangements and the same character set, or send a bitmap
  (SysEx 09h). [Programmer's reference guide, "Controlling the screen"] The XL 3's tests of field
  lengths and layout (its test 5) are taken to hold here (inference: the same screen and, by
  their pictures, the same firmware family).
- **Display targets:** 35h the stationary display, 36h the overlay, and the encoders' own numbers
  (13–28) for their temporary displays. The guide's range for controls, 05h–24h, is the XL 3's,
  which includes its faders (section 8).

## 6. Feature controls

On channel 7 to set, channel 8 to ask; replies on channel 7. In DAW mode all of them listen, but
only a few essential ones reply; those marked "DAW" below are always on in DAW mode. Note 11 on
channel 16 (`9F 0B 7F`, or `00`) turns on all of them, or goes back to DAW mode's set.
[Programmer's reference guide, "Launch Control 3 feature Controls"]

| Number | Feature | Values |
|---|---|---|
| 30 | Surface mode | as in section 4; DAW |
| 63 | Shift | on or off; DAW |
| 69 | Top encoder row relative | on or off; DAW |
| 71 | Touch reports | on or off; DAW |
| 72 | Bottom encoder row relative | on or off; DAW |
| 100 | Global MIDI channel | 0–15; kept across power cycles |
| 111 | LED brightness | 0–127; kept |
| 112 | Screen brightness | 0–127; kept |
| 113 | Temporary display timeout | tenths of a second, 0–99, at least one second; kept |
| 120 | Out 2 as MIDI Thru | on or off; kept |
| 121 | Encoder curve | 0 slow, 1 medium, 2 fast; kept |

The user guide says the matching setting on the device ("Encoder Response") doesn't affect DAW
modes; whether feature 121 does is open.

## 7. Library support

The `LaunchControl` library covers both models: `LaunchControlModel.lc3` gives the 16h header and
the controls the device has (`has(_:)`, `elements`), and the SysEx builders take a `model`. The
library's tests check it against the guide, not against a device.

## 8. Where Novation's documents disagree

1. **Buttons the device lacks.** The programmer's reference guide's standalone-mode chapter names
   Record, Play, Solo/Arm, and Mute/Select, which the Launch Control 3 doesn't have. The paragraph
   is the same, word for word, as in the XL 3's guide; that it was carried over from there is an
   inference.
2. **Custom Modes.** The mode list gives values for Custom Modes 1–8; the feature control table
   gives 18–29 for "Custom Modes 5–16"; the user guide has seven Custom Modes and a Default mode
   in slot eight. The library reads 1–16 as on the XL 3; the driver uses only DAW Mixer.
3. **Display targets.** "05h–24h" for controls is the XL 3's range, with its faders (5–12) and its
   third encoder row (29–36), which the Launch Control 3 doesn't have.
4. **Display targets for names.** The same note as the XL 3's guide: targets 22h–28h (34–40)
   only set names. On the Launch Control 3 those are no control (34–36) and buttons 1–4 (37–40).
5. **Bitmap targets and message end.** The same discrepancies as the XL 3's guide, unresolved: 20h
   and 21h for the displays where "Configure displays" uses 35h and 36h; the message shown ending
   with 7Fh, not F7h; and the reply printed as F0h … 09h 7Fh, with no F7h
   (`LAUNCH-CONTROL-XL3.md`, section 7).
6. **The global MIDI channel.** 00h–0Eh is given as 0–15, with 0Eh as channel 16, but 0Eh is 14.
   Performance Bridge leaves the setting alone.

## 9. How Performance Bridge uses it

Decided with Adam, 2026-11-01. The layout gets a close look in the Tier 1 UI review and Adam's
own (Adam asked for its efficiency and intuitiveness to be assessed).

- **Eight strips.** The bottom encoder row is each strip's level, into the mix output (the home
  submix) for sources and the output's own level in the outputs view.
- **Top encoder row.** Pan or a send, chosen on the device: Page up and down step it through Pan,
  then each send in order (control room outputs first), as Page does in Novation's own DAW
  integrations [User guide, "DAW Mixer encoder mode" in each DAW's chapter]. The screen names the
  choice ("Pan", "> Phones 1"), and a send row lights in its output's color.
- **Buttons.** Mute, switched to PFL by Function. The buttons are red for mute and yellow for PFL,
  Function is lit while they are on PFL (if it has an LED, section 4), and the screen names the
  change.
- **Paging and views.** Track < and > move by eight strips, and with Shift to the first or last
  page (`LAUNCH-CONTROL-XL3.md`, section 9); Shift with Page up shows the sources and
  Shift with Page down the outputs.
- **Levels.** The encoders keep TotalMix's own fader curve (0.26 dB a step near 0 dB);
  `LAUNCH-CONTROL-XL3.md`, section 8, item 12, tests whether relative mode is needed.
- **Screen and colors.** As on the XL 3 (`LAUNCH-CONTROL-XL3.md`, section 9): each encoder's display
  shows its channel, what it does, and the value; the stationary display the page and the names;
  the encoders their channel's color.
- **Simulation on an XL 3.** The driver can run the Launch Control 3's layout on an XL 3: the top
  two encoder rows, the top button row, Page, Track, Shift, and Mute/Select as Function (the same
  number, 66). The faders, the bottom encoder row, the bottom button row, Solo/Arm, Record, and
  Play are left dark and do nothing. This tries the layout and the driver's logic with real hands;
  it cannot check the Launch Control 3's own messages (the 16h header, the port names, or the
  numbers in section 4 marked as inference).

## 10. Tests to run on a Launch Control 3

When a unit is available:

1. **Ports.** `swift run sbdev roto ports` (it lists every MIDI port): are the DAW ports "LC3 1
   DAW Out" and "LC3 1 DAW In"?
2. **DAW mode.** Does the device echo `9F 0C 7F`, and show DAW Mixer? Is there a "DAW Connect"
   setting (firmware 1.2), and with "Connect Only", does the driver's DAW Mixer selection work?
3. **Numbers.** Press Page up and down, Track < and >, Function, and the Novation button: which
   numbers do they send (expected 106, 107, 103, 102, 66, and 104)?
4. **Function and Mode.** Does Function alone send a press, and does Mode with Function change
   the reported mode? Do mode reports come with Control Change 31, as on the XL 3 (its test 1)?
5. **Positions and encoders.** Does an encoder continue from a position the host sends? Is the
   first step after a change of direction dropped, as on the XL 3 (its test 2)?
6. **Screen and colors.** As the XL 3's tests 4 and 5. Do Function and the Novation button have
   LEDs?
