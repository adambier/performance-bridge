# The Launch Control 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control 3 (not the XL) in DAW mode,
as `LAUNCH-CONTROL-XL3.md` is for the Launch Control XL 3. Every statement carries its evidence.

**Status (2026-11-01).** Nothing here has been checked on a device: the project has no Launch
Control 3. Everything comes from Novation's documents and Bitwig's extension for the device, with
inferences marked. The two programmer's reference guides differ only in the SysEx header byte,
the version, the bootloader's buttons, the controls the Launch Control 3 lacks (faders, the third
encoder row, the second button row, and their feature controls 70 and 73), the fader touch
example, the mode list's prose, and the display-target note (compared by text, 2026-11-01).

The XL 3 has been tested,[^xl3-tests] so where the guides agree, the XL 3's tests are good
evidence for the Launch Control 3 too; that is still an inference until a unit is tried. The
driver's Launch Control 3 layout can be tried on an XL 3 (section 9).

## 1. Sources

Novation's documents are linked, not committed (AGENTS.md, section 4).

- **Programmer's reference guide.** "Launch Control 3 programmer's reference guide", version 1.1,
  PDF dated March 3, 2026, 17 pages
  ([Novation's downloads page](https://downloads.novationmusic.com/novation/launch-control/launch-control-3);
  [PDF](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/launch_control_3_programmer_s_reference_guide.pdf)).
  This is the main source. Its control map (page 9) and palette (page 12) are pictures.
- **User guide.** "Launch Control 3 user guide", version 1.1, PDF dated March 3, 2026, 69 pages
  ([PDF](https://fael-downloads-prod.focusrite.com/customer/prod/downloads/launch_control_3_user_guide_v1.1_pdf_en.pdf)).
- **Bitwig extension.** `LC3.bwextension`, in Novation's "Launch Control 3 Bitwig Integration"
  download (same page). Read for the port names it looks for and the button numbers it uses (from
  its compiled classes; nothing copied). It holds the Launch Control 3's and the XL 3's code in
  one package, and registers only the Launch Control 3.
- **Bitwig help.** The two PDFs that come with it: the help file inside the extension ("Launch
  Control 3") and "LC3 Setup Bitwig". Between them they give the port names on macOS, Windows, and
  Linux, and the roles of Function and the Novation button in Bitwig.
- **Sound On Sound.** "Novation introduce the Launch Control 3", news item of March 3, 2026
  ([link](https://www.soundonsound.com/news/novation-introduce-launch-control-3)): the release.

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote saying where it comes from: one of the sources above (with the section,
for Novation's guides), or a test or section of `LAUNCH-CONTROL-XL3.md`. Where something is
reasoning that has not been checked, the text says so in words ("inference", "not yet checked").
"Inference" marks anything the sources don't say outright.

[^prg-map]: Novation's "Launch Control 3 programmer's reference guide", version 1.1: the control
    map (a picture, page 9).
[^prg-bitmap]: The programmer's reference guide (version 1.1), "Bitmap".
[^prg-midi]: The programmer's reference guide (version 1.1), "MIDI on Launch Control 3".
[^prg-daw-note]: The programmer's reference guide (version 1.1), the note in "Launch Control 3
    programmer's DAW mode".
[^prg-bootloader]: The programmer's reference guide (version 1.1), "Entering Launch Control 3's
    bootloader".
[^prg-daw-control]: The programmer's reference guide (version 1.1), "DAW mode control".
[^prg-sysex]: The programmer's reference guide (version 1.1), "SysEx message format used by
    Launch Control 3".
[^prg-surface-map]: The programmer's reference guide (version 1.1), "The surface in DAW mode",
    its picture.
[^prg-surface-text]: The programmer's reference guide (version 1.1), "The surface in DAW mode",
    its text.
[^prg-feature-table]: The programmer's reference guide (version 1.1), the feature control table.
[^prg-modes]: The programmer's reference guide (version 1.1), "Mode report and select".
[^prg-encoders]: The programmer's reference guide (version 1.1), "Absolute and relative encoder
    modes".
[^prg-touch]: The programmer's reference guide (version 1.1), "Continuous control touch events".
[^prg-coloring]: The programmer's reference guide (version 1.1), "Colouring the surface".
[^prg-rgb]: The programmer's reference guide (version 1.1), "RGB Colour".
[^prg-screen]: The programmer's reference guide (version 1.1), "Controlling the screen".
[^prg-features]: The programmer's reference guide (version 1.1), "Launch Control 3 feature
    Controls".
[^ug-intro]: Novation's "Launch Control 3 user guide", version 1.1: "Introduction".
[^ug-top]: The user guide (version 1.1), "Launch Control 3's Top Panel".
[^ug-specs]: The user guide (version 1.1), "Technical Specifications".
[^ug-buttons]: The user guide (version 1.1), "Using the Launch Control 3's buttons".
[^ug-back]: The user guide (version 1.1), "Launch Control 3's back panel".
[^ug-ableton]: The user guide (version 1.1), "Controlling Ableton Live with the Launch Control 3".
[^ug-daw]: The user guide (version 1.1), "Controlling your DAW with the Launch Control 3".
[^ug-mode]: The user guide (version 1.1), "Mode button (Edit)".
[^ug-function]: The user guide (version 1.1), "Using the Function (DAW) button".
[^ug-daw-mixer]: The user guide (version 1.1), "DAW Mixer encoder mode" in each DAW's chapter.
[^bitwig]: Bitwig's extension for the device, `LC3.bwextension`, in Novation's "Launch Control 3
    Bitwig Integration" download: its compiled classes, read for the port names it looks for and
    the button numbers it uses.
[^bitwig-help]: The two PDFs that come with Bitwig's extension: the help file inside it ("Launch
    Control 3") and "LC3 Setup Bitwig".
[^sos]: Sound On Sound, "Novation introduce the Launch Control 3", news item of March 3, 2026.
[^downloads]: Novation's
    [Launch Control 3 downloads page](https://downloads.novationmusic.com/novation/launch-control/launch-control-3),
    read 2026-11-01.
[^xl3-tests]: [`LAUNCH-CONTROL-XL3.md`, section 10](LAUNCH-CONTROL-XL3.md#10-test-records), the
    XL 3's test records.
[^xl3-test1]: [`LAUNCH-CONTROL-XL3.md`, test 1](LAUNCH-CONTROL-XL3.md#test-1-2026-11-01-ports-daw-mode-and-the-control-map)
    (section 10).
[^xl3-test2]: [`LAUNCH-CONTROL-XL3.md`, test 2](LAUNCH-CONTROL-XL3.md#test-2-2026-11-01-encoder-positions-relative-mode-and-fader-pickup)
    (section 10).
[^xl3-test5]: [`LAUNCH-CONTROL-XL3.md`, test 5](LAUNCH-CONTROL-XL3.md#test-5-2026-11-01-the-screen)
    (section 10).
[^xl3-test6]: [`LAUNCH-CONTROL-XL3.md`, test 6](LAUNCH-CONTROL-XL3.md#test-6-2026-11-01-daw-mixer-and-daw-control)
    (section 10).
[^xl3-firmware]: [`LAUNCH-CONTROL-XL3.md`, section 2a](LAUNCH-CONTROL-XL3.md#2a-firmware).
[^xl3-disagree]: [`LAUNCH-CONTROL-XL3.md`, section 7](LAUNCH-CONTROL-XL3.md#7-where-novations-documents-disagree).
[^xl3-use]: [`LAUNCH-CONTROL-XL3.md`, section 9](LAUNCH-CONTROL-XL3.md#9-how-performance-bridge-uses-it).

## 2. The device

- 16 endless encoders in two rows of eight, each with an RGB LED; 8 buttons in one row; an OLED
  screen; and Page (up and down), Track (< and >), Shift, Mode, and Function
  buttons.[^ug-intro][^ug-top][^ug-specs]
- A button with Novation's logo next to Function: the user guide's row of 10 buttons is Function,
  this button, and the 8.[^ug-buttons][^prg-map][^bitwig-help]
- No faders, and no Record, Play, Solo/Arm, or Mute/Select buttons.[^prg-map]
- One USB-C port, and DIN MIDI In, Out, and Out 2/Thru.[^ug-back][^ug-specs][^sos]
- The screen is 128 × 64 pixels.[^prg-bitmap]
- The Function button is labeled "DAW" underneath, and Mode "Edit".[^prg-map]

## 3. MIDI ports

- As on the XL 3: a MIDI pair, a DAW pair, and two "To DIN" outputs over USB. A host using DAW
  mode talks to the DAW pair, and in DAW mode the DIN outputs send
  nothing.[^prg-midi][^prg-daw-note]
- The device ID (1–8, set in the bootloader by holding both Page buttons while plugging in) is
  part of the port names.[^prg-bootloader]
- **Port names.** On macOS, Bitwig's extension looks for "LC3 1 DAW Out" and "LC3 1 DAW In", and
  its help lists them under Mac; on Linux "LC3 1 LC3 1 DAW Out/In", and on Windows
  "MIDIIN2/MIDIOUT2 (LC3 1 MIDI)".[^bitwig][^bitwig-help] Novation's own setup for Ableton Live
  says to choose the DAW Out and DAW In ports on macOS.[^ug-ableton] The driver matches "LC3 1
  DAW". That CoreMIDI's names are Bitwig's is an inference; for the XL 3 they were.[^xl3-test1]

## 4. DAW mode

- **Entering and leaving.** The same messages as the XL 3: note 12 on channel 16, velocity 127 to
  enter and 0 to leave, or the SysEx form (command 02h).[^prg-daw-control] That the device echoes
  the note, as the XL 3 does,[^xl3-test1] is an inference.
- **The default mode.** Connected to a DAW, the encoders start in DAW Mixer.[^ug-daw]
- **Firmware 1.2 and "DAW Connect".** Novation's Logic Pro script for the Launch Control 3
  (version 1.1) is listed as adding support for a "DAW Connect" feature of firmware
  1.2.[^downloads] The user guide v1.1 has no such setting, so the guides predate 1.2
  (inference). On the XL 3, firmware 1.2's "Connect Only" leaves the device in its Custom
  Mode;[^xl3-firmware] the driver selects DAW Mixer on connecting, for that case.
- **SysEx header.** F0h 00h 20h 29h 02h **16h**, where the XL 3 has 15h.[^prg-sysex][^bitwig]
- **Control map** (unless marked).[^prg-surface-map]
  - Encoders: top row 13–20, bottom row 21–28, on channel 16 (the XL 3's top two rows).
  - Buttons: 37–44, on channel 1 (the XL 3's top row), although they sit at the bottom of the panel.
  - Shift: channel 7, Control Change 63.[^prg-surface-text][^prg-feature-table]
  - Page, Track, Function, and the Novation button aren't numbered in the picture. Bitwig's
    Launch Control 3 code reads Page as 106 (up) and 107 (down), Track as 103 (<) and 102 (>), the
    Novation button as 104, and **Function as 66**, the XL 3's Mute/Select (the XL 3's Solo/Arm, 65,
    appears only in its XL 3 code).[^bitwig] That the device sends these is an inference.
- **Modes.** Channel 7, Control Change 30, reports and selects the surface mode: 1 DAW Mixer,
  2 DAW Control, 6–9 Custom Modes 1–4, 18–21 Custom Modes 5–8.[^prg-modes] Its feature
  control table gives 18–29 for Custom Modes 5–16 (section 8).
- **On the device**:[^ug-mode][^ug-function]
  - Mode enters mode selection, where the 8 buttons choose a mode; the current one is lit white.
  - Mode and Function together cycle between DAW Control and DAW Mixer.
  - In DAW modes, Function changes what the 8 buttons control (Solo, Arm, Mute, or Select in
    Novation's DAW integrations).[^ug-top][^ug-buttons][^bitwig-help] Function has an LED (Adam,
    2026-11-02); Novation's documents don't say so, and Bitwig's code lights 66.
  - On the XL 3, choosing a DAW mode on the device changed nothing it sends and was left to the
    host.[^xl3-test6] That the Launch Control 3 behaves the same is an inference.
- **Relative encoders.** Feature controls 69 (top row) and 72 (bottom row), 127 on and 0 off. In
  relative mode the rows report 77–84 and 85–92, with 64 as no movement, 65 one step clockwise,
  and 63 one step counterclockwise.[^prg-encoders]
- **Positions.** Absolute encoders take position information from the host.[^prg-encoders] On the
  XL 3 the message is the encoder's own Control Change sent back on channel 16;[^xl3-test2] the
  same here is an inference.
- **Touch reports.** Feature control 71; the reports come on channel 15.[^prg-touch] On the XL 3
  they come from movement, with the control's own number, or its relative number in relative
  mode;[^xl3-test1][^xl3-test2] the same here is an inference.
- **No fader pickup.** The feature control table has no feature 70; the device has no faders.

## 5. Lights and the screen

- **Palette colors** by Control Change on channel 1, with the control's number; **RGB** by SysEx
  01h 53h; Shift takes no color. For RGB, encoder LEDs take their absolute numbers in either
  encoder mode; for palette colors that is an inference.[^prg-coloring][^prg-rgb] The palette
  picture is the same image as the XL 3 guide's (identical files, compared 2026-11-01), and the device is taken to show
  colors as the XL 3 does (Adam, 2026-11-02); not yet seen on a Launch Control 3.
- **The screen** works as the XL 3's: configure a display (SysEx 04h), then fill its text fields
  (SysEx 06h), with the same four arrangements and the same character set, or send a bitmap
  (SysEx 09h).[^prg-screen] The XL 3's tests of field lengths and layout[^xl3-test5] are taken to
  hold here (inference: the same screen and, by their pictures, the same firmware family).
- **Display targets:** 35h the stationary display, 36h the overlay, and the encoders' own numbers
  (13–28) for their temporary displays. The guide's range for controls, 05h–24h, is the XL 3's,
  which includes its faders (section 8).

## 6. Feature controls

On channel 7 to set, channel 8 to ask; replies on channel 7. In DAW mode all of them listen, but
only a few essential ones reply; those marked "DAW" below are always on in DAW mode. Note 11 on
channel 16 (`9F 0B 7F`, or `00`) turns on all of them, or goes back to DAW mode's
set.[^prg-features]

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
   with 7Fh, not F7h; and the reply printed as F0h … 09h 7Fh, with no F7h.[^xl3-disagree]
   Performance Bridge's meters on the home screen (the Meters setting, `showsMeters`) use the XL
   3's findings (target 35h, the F7h end, the ready reply; LAUNCH-CONTROL-XL3.md, test 21); that
   they hold on a Launch Control 3 is an inference, untested.
6. **The global MIDI channel.** 00h–0Eh is given as 0–15, with 0Eh as channel 16, but 0Eh is 14.
   Performance Bridge leaves the setting alone.

## 9. How Performance Bridge uses it

Decided with Adam, 2026-11-01. The layout is to be reviewed closely in the Tier 1 UI review and
by Adam (Adam asked for its efficiency and intuitiveness to be assessed).

- **Eight strips.** The bottom encoder row is each strip's level in the home submix (Main Out). The
  strips always show sources.
- **Top encoder row.** Pan or a send, chosen on the device: Page up and down step it through Pan,
  then each send in order (control room outputs first), as Page does in Novation's own DAW
  integrations.[^ug-daw-mixer] The screen names the choice ("Pan", "> Phones 1"), and a send row
  lights in its output's color, or teal for an output left white in TotalMix FX (Adam, 2026-11-02;
  `LAUNCH-CONTROL-XL3.md`, section 9).
- **Buttons.** Mute, and PFL while Function is held (Adam, 2026-11-02, from the review of that date:
  a toggle could leave the buttons on PFL by mistake on stage). The buttons are orange for mute and
  yellow for PFL, Function rests dim yellow and lights bright yellow while they are on PFL, and the
  screen names the change. Function also stays bright yellow, and the home screen reads "PFL on,
  buttons Mute", while any channel's PFL is on, so a PFL left on after Function is released still
  shows (Adam, 2026-11-02, from the UI review of that date). This needs Function to send its release, as the XL 3's buttons do
  (XL 3 test 1; for the Launch Control 3, an inference). A button that is off, and Function at
  rest, show an exact-RGB dim shade (XL 3 test 19), taken to look as on the XL 3 (Adam,
  2026-11-02).
- **Paging.** Track < and > move by eight strips, and with Shift to the first or last
  page.[^xl3-use] The strips always show the channels, never the outputs.
- **Mute and PFL presses** show on the overlay, as on the XL 3 (Adam, 2026-11-02).
- **The Novation button** brings TotalMix FX's window to the front, as on the XL 3 (Adam,
  2026-11-02); that it sends 104 here too is from Bitwig's integration, not yet seen on a device
  (section 4).
- **Levels.** Level and send encoders use the ARC USB's scale, as on the XL 3 (about 0.2 dB a
  value near 0 dB).[^xl3-use] `LAUNCH-CONTROL-XL3.md`, section 8, item 12, tests whether relative
  mode is needed.
- **Shift + turn.** As on the XL 3, it resets the encoder: a pan to the center, a level above 0 dB
  down to 0 dB (never up), and a send to −oo and back again on a second Shift + turn (Shift released and held again), once Shift
  has been held 0.3 s with no Page or Track press.
- **Screen and colors.** As on the XL 3:[^xl3-use] each encoder's display shows its channel, what
  it does, and the value; the encoders show their channel's color. The home
  screen shows the channels on the page, the top row's function ("Top: Pan" or "Top > Phones 1"),
  and the buttons' ("Buttons: Mute" or "Buttons: PFL", or "PFL on, buttons Mute" while a channel's PFL is on with the buttons on mute).
- **Level by brightness.** As on the XL 3 (an off-by-default setting; Adam, 2026-11-02):[^xl3-use]
  the level encoders, and the top row when it is a send, dim continuously with their level, from
  full at the top of the travel to dim at the bottom and dark at −oo; pan keeps full brightness.
  Here the level row has lights, so the levels themselves dim, which the XL 3's faders can't. The
  curve, the floor, and the encoders' yellow (127, 85, 0) were set on the XL 3 (its tests 17 and
  18) and are taken to suit the Launch Control 3's LEDs too (Adam, 2026-11-02).
- **Simulation on an XL 3.** The driver can run the Launch Control 3's layout on an XL 3: the top
  two encoder rows, the top button row, Page, Track, Shift, and Mute/Select as Function (the same
  number, 66). The faders, the bottom encoder row, the bottom button row, Solo/Arm, Record, and
  Play are left dark and do nothing. This tests the layout and the driver's logic by hand;
  it cannot check the Launch Control 3's own messages (the 16h header, the port names, or the
  numbers in section 4 marked as inference).

## 10. Tests to run on a Launch Control 3

When a unit is available:

1. **Ports.** `swift run sbdev roto ports` (it lists every MIDI port): are the DAW ports "LC3 1
   DAW Out" and "LC3 1 DAW In"?
2. **DAW mode.** Does the device echo `9F 0C 7F`, and show DAW Mixer? The driver takes only that
   echo, a DAW mode report, or a control moved or pressed as a sign the device is there, not other
   feature replies (as on the XL 3, test 12 of its doc); check that the Launch Control 3 connects. Is there a "DAW Connect"
   setting (firmware 1.2), and with "Connect Only", does the driver's DAW Mixer selection work?
3. **Numbers.** Press Page up and down, Track < and >, Function, and the Novation button: which
   numbers do they send (expected 106, 107, 103, 102, 66, and 104)?
4. **Function and Mode.** Does Function alone send a press, and does Mode with Function change
   the reported mode? Do mode reports come with Control Change 31, as on the XL 3?[^xl3-test1]
   Does Mode + Function also send Function's own press (66)? On the XL 3, Mode + Solo/Arm passed
   the button's press on,[^xl3-test6] and if the Launch Control 3 does the same, choosing a DAW mode
   on the device would also switch the buttons between mute and PFL (review of 2026-11-02).
5. **Positions and encoders.** Does an encoder continue from a position the host sends? Is the
   first step after a change of direction dropped, as on the XL 3?[^xl3-test2]
6. **Screen and colors.** As the XL 3's tests 4 and 5. Do Function and the Novation button have
   LEDs?
