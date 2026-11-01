# The Launch Control 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control 3 (not the XL) in DAW mode,
as `LAUNCH-CONTROL-XL3.md` is for the Launch Control XL 3. Every statement carries its evidence.

**Status (2026-11-01).** Nothing here has been checked on a device: the project has no Launch
Control 3. Everything comes from Novation's documents, with a few inferences from Bitwig's
extension for the device, marked as such. Its protocol is nearly the XL 3's, which has been
tested (`LAUNCH-CONTROL-XL3.md`, section 10), so where the two guides agree, the XL 3's tests are
good evidence for the Launch Control 3 too; that is still an inference until a unit is tried.
The driver's Launch Control 3 layout can be tried on an XL 3 (section 9).

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
  download (same page). Read for the port names it looks for and the button numbers it uses
  (from its compiled classes; nothing copied). It shares one package of code with the XL 3's
  extension.
- **[Sound On Sound]** "Novation introduce Launch Control 3", news item of March 3, 2026
  ([link](https://www.soundonsound.com/news/novation-introduce-launch-control-3)): the release.

Bracketed tags below name the source. "Inference" marks anything the sources don't say outright.

## 2. The device

- 16 endless encoders in two rows of eight, each with a color LED; 8 buttons in one row; an
  OLED screen; and Page (up and down), Track (< and >), Shift, Mode, and Function buttons, plus a
  button with Novation's logo next to Function. No faders, and no Record, Play, Solo/Arm, or
  Mute/Select buttons. [User guide, "Launch Control 3's Top Panel"; programmer's reference guide,
  control map]
- USB-C, and DIN MIDI In, Out, and Out 2/Thru. [Sound On Sound; programmer's reference guide,
  "MIDI on Launch Control 3"]
- The screen is 128 × 64 pixels. [Programmer's reference guide, "Bitmap"]
- The Function button is labeled "DAW" underneath, and Mode "Edit". [Programmer's reference guide,
  control map picture]

## 3. MIDI ports

- As on the XL 3: a MIDI pair, a DAW pair, and two "To DIN" outputs over USB. A host using DAW
  mode talks to the DAW pair, and in DAW mode the DIN outputs send nothing. [Programmer's
  reference guide, "MIDI on Launch Control 3" and "DAW mode"]
- The device ID (1–8, set in the bootloader by holding both Page buttons while plugging in) is
  part of the port names. [Programmer's reference guide, "Entering Launch Control 3's bootloader"]
- **Port names (inference).** Bitwig's extension looks for "LC3 1 DAW Out" and "LC3 1 DAW In" (and
  "LC3 1 LC3 1 DAW Out/In", the Linux form, and "MIDIIN2/MIDIOUT2 (LC3 1 MIDI)" on Windows). By
  analogy with the XL 3's names seen on macOS ("LCXL3 1 DAW Out/In"), the driver matches "LC3 1
  DAW" on macOS. [Bitwig extension]

## 4. DAW mode

- **Entering and leaving.** The same messages as the XL 3: note 12 on channel 16, velocity 127 to
  enter and 0 to leave, or the SysEx form (command 02h). [Programmer's reference guide, "DAW mode
  control"] That the device echoes the note, as the XL 3 does (its test 1), is an inference.
- **SysEx header.** F0h 00h 20h 29h 02h **16h**, where the XL 3 has 15h. [Programmer's reference
  guide, "SysEx message format"]
- **Control map.** [Programmer's reference guide, "The surface in DAW mode", picture]
  - Encoders: top row 13–20, bottom row 21–28, on channel 16 (the XL 3's top two rows).
  - Buttons: 37–44, on channel 1 (the XL 3's top row).
  - Shift: channel 7, Control Change 63, as a feature control.
  - Page, Track, Function, and the Novation button aren't numbered in the picture. Bitwig's
    extension, shared with the XL 3, uses the XL 3's numbers for Page (106 up, 107 down) and Track
    (103 left, 102 right); that the Launch Control 3 sends them is an inference. Function sits
    where the XL 3 has Solo/Arm (65), and the Novation button where the XL 3 has its own (104);
    that they send those numbers is a further inference.
- **Modes.** Channel 7, Control Change 30, reports and selects the surface mode: 1 DAW Mixer,
  2 DAW Control, 6–9 Custom Modes 1–4, 18–21 Custom Modes 5–8. [Programmer's reference guide,
  "Mode report and select"] Its feature control table gives 18–29 for Custom Modes 5–16 (section 8).
- **On the device** (user guide, "Mode button" and "Using the Function (DAW) button"):
  - Mode enters mode selection, where the 8 buttons choose a mode; the current one is lit white.
  - Mode and Function together cycle between DAW Control and DAW Mixer.
  - In DAW modes, Function changes what the 8 buttons control (Solo, Arm, Mute, or Select in
    Novation's DAW integrations). [User guide, "Launch Control 3's Top Panel" and "Using the
    Launch Control 3's buttons"]
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
  guide, "Continuous control touch events"] On the XL 3 they come from movement (its test 1).
- **No fader pickup.** The feature control table has no feature 70; the device has no faders.

## 5. Lights and the screen

- **Palette colors** by Control Change on channel 1, with the control's number; **RGB** by SysEx
  01h 53h; Shift takes no color. Encoder LEDs take their absolute numbers in either encoder mode.
  [Programmer's reference guide, "Colouring the surface" and "RGB Colour"] The palette picture is
  the same as the XL 3's (inference from comparing the pictures).
- **The screen** works as the XL 3's: configure a display (SysEx 04h), then fill its text fields
  (SysEx 06h), with the same four arrangements and the same character set, or send a bitmap
  (SysEx 09h). [Programmer's reference guide, "Controlling the screen"] The XL 3's tests of field
  lengths and layout (its test 5) are taken to hold here (inference: the same screen and, by
  their pictures, the same firmware family).
- **Display targets:** 35h the stationary display, 36h the overlay, and the encoders' own numbers
  (13–28) for their temporary displays. The guide's range for controls, 05h–24h, is the XL 3's,
  which includes its faders (section 8).

## 6. Feature controls

On channel 7 to set, channel 8 to ask; replies on channel 7. [Programmer's reference guide,
"Launch Control 3 feature Controls"]

| Number | Feature | Values |
|---|---|---|
| 30 | Surface mode | as in section 4 |
| 63 | Shift | on or off |
| 69 | Top encoder row relative | on or off |
| 71 | Touch reports | on or off |
| 72 | Bottom encoder row relative | on or off |
| 100 | Global MIDI channel | 0–15; kept across power cycles |
| 111 | LED brightness | 0–127; kept |
| 112 | Screen brightness | 0–127; kept |
| 113 | Temporary display timeout | tenths of a second, 0–99; kept |
| 120 | Out 2 as MIDI Thru | on or off; kept |
| 121 | Encoder curve | 0 slow, 1 medium, 2 fast; kept |

## 7. Library support

The `LaunchControl` library covers both models: `LaunchControlModel.lc3` gives the 16h header and
the controls the device has (`has(_:)`, `elements`), and the SysEx builders take a `model`. The
library's tests check it against the guide, not against a device.

## 8. Where Novation's documents disagree

1. **Buttons the device lacks.** The programmer's reference guide's standalone-mode chapter names
   Record, Play, Solo/Arm, and Mute/Select, which the Launch Control 3 doesn't have. The text
   appears to come from the XL 3's guide (inference).
2. **Custom Modes.** The mode list gives values for Custom Modes 1–8; the feature control table
   gives 18–29 for "Custom Modes 5–16"; the user guide has seven Custom Modes and a Default mode
   in slot eight. The library reads 1–16 as on the XL 3; the driver uses only DAW Mixer.
3. **Display targets.** "05h–24h" for controls is the XL 3's range, with its faders (5–12) and its
   third encoder row (29–36), which the Launch Control 3 doesn't have.
4. **Bitmap targets and message end.** The same misprints as the XL 3's guide (20h and 21h for the
   displays, a 7Fh where F7h is expected; `LAUNCH-CONTROL-XL3.md`, section 7).

## 9. How Performance Bridge uses it

Decided with Adam, 2026-11-01. The layout gets a close look in the Tier 1 UI review and Adam's
own (Adam asked for its efficiency and intuitiveness to be assessed).

- **Eight strips.** The bottom encoder row is each strip's level, into the mix output (the home
  submix) for sources and the output's own level in the outputs view.
- **Top encoder row.** Pan or a send, chosen on the device: Track < and > step it through Pan,
  then each send in order (control room outputs first). The screen names the choice ("Pan",
  "> Phones 1").
- **Buttons.** Mute, switched to PFL by Function. The buttons are red for mute and yellow for PFL,
  Function is lit while they are on PFL, and the screen names the change.
- **Paging and views.** Page up and down move by eight strips; Shift with Page up shows the
  sources and Shift with Page down the outputs.
- **Simulation on an XL 3.** The driver can run the Launch Control 3's layout on an XL 3: the top
  two encoder rows, the top button row, Page, Track, Shift, and Solo/Arm in Function's place. The
  faders, the bottom encoder row, and the bottom button row are left dark and do nothing. This
  tries the layout and the driver's logic with real hands; it cannot check the Launch Control 3's
  own messages (the 16h header, the port names, or the numbers in section 4 marked as inference).

## 10. Tests to run on a Launch Control 3

When a unit is available:

1. **Ports.** `swift run sbdev roto ports` (it lists every MIDI port): are the DAW ports "LC3 1
   DAW Out" and "LC3 1 DAW In"?
2. **DAW mode.** Does the device echo `9F 0C 7F`, and show DAW Mixer?
3. **Numbers.** Press Page up and down, Track < and >, Function, and the Novation button: which
   numbers do they send (section 4)?
4. **Function and Mode.** Does Function alone send a press, and does Mode with Function change
   the reported mode?
5. **Positions.** Does an encoder continue from a position the host sends?
6. **Screen and colors.** As the XL 3's tests 4 and 5.
