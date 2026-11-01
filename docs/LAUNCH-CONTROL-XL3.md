# The Launch Control XL 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control XL 3 in DAW mode, as
`TOTALMIX-OSC.md` is for TotalMix FX and `ROTO-CONTROL.md` for the Roto-Control. Every statement
carries its evidence.

**Status (2026-10-31).** Everything here comes from Novation's documents. None of it has been
checked on the device yet. The `LaunchControlXL3` library and `sbdev lcxl` are built from these
documents, and their tests check them against the documents, not against the device. Section 8
lists the tests that will check them.

## 1. Sources

Novation's documents are linked, not committed (AGENTS.md, section 4). Adam has local copies in
the project folder (`Novation Docs/`).

- **[Programmer's reference guide]** "Launch Control XL 3 programmer's reference guide", version
  1.0, PDF dated April 17, 2026, 17 pages
  ([Novation](https://userguides.novationmusic.com/hc/en-gb/articles/27840466285586-About-the-Launch-Control-XL-3-programmer-s-reference-guide)).
  This is the main source. Its control map (page 9) and color palette (page 12) are pictures,
  read from the PDF.
- **[User guide]** "Launch Control XL 3 user guide" (PDF, English). It describes the controls and
  the DAW modes as a user sees them.
- **[Bitwig setup]** "Launch Control XL Mk3, Bitwig Studio controller extension, setup": Bitwig's
  PDF (its branding), shipped with the Bitwig extension for the device. It gives the DAW port
  names on macOS (in a screenshot), Windows, and Linux.

Bracketed tags below name the source. "Inference" marks anything the sources don't say outright.

## 2. MIDI ports

- Over USB the device has a MIDI port pair, a DAW port pair, and two "To DIN" outputs. A host
  that uses DAW mode talks to the DAW pair. [Programmer's reference guide, "MIDI on Launch
  Control XL 3"]
- Port names include the device ID (1–8, set in the bootloader), so several units can be told
  apart. [Programmer's reference guide, "Entering … bootloader"]
- On Linux the DAW ports are "LCXL3 1 LCXL3 1 DAW Out" (the device's output, the host's input)
  and "LCXL3 1 LCXL3 1 DAW In". On Windows they are "MIDIIN2 (LCXL3 1 MIDI)" and "MIDIOUT2
  (LCXL3 1 MIDI)". [Bitwig setup]
- On macOS, Bitwig's screenshot shows the input as "LCXL3 1 DAW Out" and the output as "LCXL3 1
  DAW In". [Bitwig setup, page 2] Bitwig may show names that differ from CoreMIDI's (inference),
  so `sbdev lcxl` matches by part of the name, "LCXL3 1 DAW", which picks one source and one
  destination if the CoreMIDI names follow the same pattern.
- In DAW mode the DIN outputs send nothing. [Programmer's reference guide, "DAW mode"]

## 3. DAW mode

- **Entering and leaving.** A host enters DAW mode on connecting and leaves it on quitting, which
  returns the device to standalone mode. Either form works: note 12 on channel 16 (velocity 127
  to enter, 0 to leave), or SysEx command 02h with 7Fh or 00h. [Programmer's reference guide,
  "DAW mode control"]
- **SysEx header.** Every SysEx message starts F0h 00h 20h 29h 02h 15h, in both directions, then
  a command byte. [Programmer's reference guide, "SysEx message format"]
- **Modes.** DAW mode offers two surface modes, DAW Mixer and DAW Control. The device reports a
  mode change on channel 7, Control Change 30, and a host can select a mode the same way. Values:
  - 1 is DAW Mixer and 2 is DAW Control;
  - 6–9 are Custom Modes 1–4;
  - 18–29 are Custom Modes 5–16.

  [Programmer's reference guide, feature control table; its prose differs, section 7]
- **What the modes change.** On the device, Mode plus Mute/Select or Solo/Arm chooses between
  them. The user guide gives the pairing both ways round (section 7). For Ableton Live, Logic
  Pro, Cubase, and Bitwig Studio the faders and buttons stay the same, and only what the encoders
  control changes; in FL Studio the modes change the buttons too. [User guide, the chapters for
  each DAW] So, for Performance Bridge, the two modes are two encoder pages
  that the device switches for us (inference).

## 4. The controls

From the control map. [Programmer's reference guide, page 9, the decimal picture] Faders and
encoders report on channel 16, buttons on channel 1, and Shift on channel 7.

| Control | Control Change | Notes |
|---|---|---|
| Faders 1–8 | 5–12 | **not motorized**; no LED in the guide's pictures |
| Encoders, row 1 (top) | 13–20 | endless; one LED under each |
| Encoders, row 2 | 21–28 | |
| Encoders, row 3 | 29–36 | |
| Buttons, top row 1–8 | 37–44 | Novation's Solo or Arm row |
| Buttons, bottom row 1–8 | 45–52 | Novation's Mute or Select row |
| Solo/Arm | 65 | left of the top row |
| Mute/Select | 66 | left of the bottom row |
| Novation logo button | 104 | "nothing… yet" [User guide] |
| Page up, Page down | 106, 107 | |
| Track <, Track > | 103, 102 | the left button has the higher number |
| Record | 118 | |
| Play | 116 | |
| Shift | 63 | channel 7, as a feature control |
| Mode | none | the device keeps it |

- **Button values.** The guide doesn't say what a button sends. The library reads 64 or more as
  pressed and less as released (inference: 127 and 0, as is usual).
- **Encoders, absolute.** By default an encoder sends 0–127, and takes on any position a host
  sends it. [Programmer's reference guide, "Absolute and relative encoder modes"] The guide doesn't say in which message. The library sends the
  encoder's own Control Change back on channel 16 (inference, to test).
- **Encoders, relative.** Each row can be switched to relative output separately, with feature
  controls 69, 72, and 73 for rows 1–3. A relative row then reports Control Changes 64 higher
  (77–84, 85–92, and 93–100). The value is 64 for no movement, above 64 for clockwise steps, and
  below 64 for anticlockwise. [Programmer's reference guide]
- **Touch.** With touch reports on (feature control 71), a "touch" sends the control's Control
  Change on channel 15, with 127 for touch on and 0 for off. The guide's only example is a fader:
  BEh 05h 7Fh for the leftmost. [Programmer's reference guide, "Continuous control touch events"]
  - What a touch is remains open. The guide describes the display's touch setting as "this is
    the Shift + rotate" (section 5), and the user guide never mentions touch sensing. So a
    "touch" may be moving a control with Shift held, not a touch sensor (inference).
  - It matters for SurfaceCore, which holds a control while it is touched. Test 5 checks both.
  - Whether encoders report touch too is also open.
- **Fader pickup.** The programmer's reference guide lists feature control 70 as "DAW Fader
  Pickup", on or off, with no description. [Programmer's reference guide, feature controls]
  - The user guide's pickup, where a moved fader takes over only once it reaches the parameter's
    value, is the Settings menu's, which leaves DAW modes alone. [User guide, "Fader pickup" and
    Settings]
  - That feature 70 works the same way in DAW mode is an inference. So is that the device learns
    the parameter's value from the position message above. Test 7 checks both.

## 5. Lights and the screen

- **Palette colors.** A Control Change on channel 1, with the control's own number, lights it in
  one of 128 palette colors. [Programmer's reference guide, "Colouring the surface"] The guide
  says encoder LEDs use their absolute numbers even in relative mode, under "RGB Colour"; that the
  same holds for palette colors is an inference. The palette is a picture in the guide
  (page 12). Index 0 looks dark gray, perhaps off, and 3 looks white (inference from the picture).
- **RGB.** SysEx 01h 53h, then the control, red, green, and blue, lights a button or an encoder in
  a color of its own. [Programmer's reference guide, "RGB Colour"] SysEx data bytes are 7-bit, so
  each part is 0–127. That this covers the LED's full range is an inference.
- **The screen** is 128 × 64 pixels. [Programmer's reference guide, "Bitmap"]
  - **Display targets.** Each fader and encoder has a temporary display (target = its Control
    Change, 5–36). There is also a stationary display (53) and an overlay (54). [Programmer's
    reference guide, "Configure displays"]
  - **Setting up a display.** SysEx 04h, then the target and a config byte, sets up a display:
    - bits 0–4 are the arrangement;
    - bit 6 lets the device bring it up by itself when the control changes;
    - bit 5 does the same when the control is touched (Shift and turn);
    - 00h takes the display down, and 7Fh brings it up with its current text.
  - **Arrangements:**
    - 1: name and value as text;
    - 2: title, name, and value as text;
    - 3: title and eight names in two rows of four, for what the encoders do;
    - 4: name and the device's own numeric value, the default.
  - **Text.** SysEx 06h, then the target, the field (from 0), and the text, fills one field.
    Text is ASCII 20h–7Eh, plus four symbols in place of control codes: 1Bh empty box, 1Ch filled
    box, 1Dh flat sign, and 1Eh heart. [Programmer's reference guide, "Setting text"] How many
    characters a field shows is not given.
  - **Bitmap.** SysEx 09h sends a whole picture: 64 rows of 19 bytes, 7 pixels per byte, highest
    bit leftmost. The device answers when it is ready for the next one. It holds one bitmap at a
    time. [Programmer's reference guide, "Bitmap"]

## 6. Feature controls

Control Changes on channel 7 to the DAW port set them. The same Control Change on channel 8 asks
for one, and replies come on channel 7. In DAW mode all of them listen, but only a few reply.
Note 11 on channel 16 (velocity 127 or 0) enables every feature control, or goes back to DAW
mode's own set. The inference is that this means their replies, since in DAW mode they all
listen already.
[Programmer's reference guide, "Launch Control XL 3 feature Controls"]

| CC | Feature | Values |
|---|---|---|
| 30 | Surface mode | section 3 |
| 63 | Shift | on or off |
| 69, 72, 73 | Encoder rows 1–3, relative | on or off |
| 70 | Fader pickup | on or off |
| 71 | Touch reports | on or off |
| 111 | LED brightness | 0–127; kept across power cycles |
| 112 | Screen brightness | 0–127; kept |
| 113 | Temporary display time | 0–99 tenths of a second (0 is 1 s); kept |
| 100 | Global MIDI channel | 0–15; kept |
| 120 | Out 2 as MIDI Thru | on or off; kept |
| 121 | Encoder curve | 0 slow, 1 medium, 2 fast; kept |

The kept ones are the user's settings, so Performance Bridge should not change them (inference
from "non-volatile").

## 7. Where Novation's documents disagree

Each is resolved here as stated, until the device settles it.

1. **Custom Mode values.** The programmer's reference guide's prose gives 12h–15h for "modes 5 – 8"
   and 16h–1Dh for "Custom Modes 8 - 16". Mode 8 is listed twice, and 16h–1Dh is eight values for
   nine modes. Its feature control table gives 12h–1Dh for modes 5–16. The library follows the
   table.
2. **How many Custom Modes.** The programmer's reference guide has 16. The user guide has 15, with
   a Default mode in the sixteenth slot.
3. **Which button chooses which DAW mode.** The user guide says Mode plus Mute/Select is DAW Mixer
   and Solo/Arm is DAW Control six times, in the Ableton Live, Logic Pro, Cubase, and Bitwig
   Studio chapters. Twice, in the DAW Control tips, it says the reverse.
4. **Display targets for names.** The programmer's reference guide's note on arrangements mentions
   targets that only set names, 22h–28h (34–40), a range that overlaps encoder targets (34–36) and
   button numbers (37–40). The target list gives no such range.
5. **Bitmap targets.** The bitmap section names the stationary display 20h and the global
   temporary display 21h, where "Configure displays" uses 35h and 36h.
6. **Bitmap message end.** The bitmap message is shown ending with 7Fh, not F7h, and the reply as
   F0h … 09h 7Fh, with no F7h. The 7Fh may be a misprint for F7h, or the reply may have a 7Fh and
   lost its F7h in print (inference either way). The library reads either form as the reply.
7. **The global MIDI channel.** The feature control table gives the range as 00h–0Eh, called 0–15,
   with 00h as channel 1 and 0Eh as channel 16; but 0Eh is 14. Performance Bridge leaves this setting
   alone, so it doesn't matter here.

## 8. Tests to run on the device

Run with `swift run sbdev lcxl` (macOS; `sbdev lcxl --help`). First, `sbdev lcxl ports` lists the
port names.

1. **Ports.** The macOS names of the DAW ports. Does `--port "LCXL3 1 DAW"` connect?
2. **DAW mode.** Does the device show DAW mode on entering, and return to standalone on `quit`?
3. **The control map.** Move every control and check its name and value against section 4,
   including Track < and > (103, 102) and the Novation button. What do buttons send: 127 and 0?
4. **Modes.** Mode plus Mute/Select, then plus Solo/Arm: which reports 1 and which 2 (section 7,
   item 3)? Does `mode control` switch the device?
5. **Touch.** With `touch on`: touch a fader and an encoder without moving them, then move each
   with Shift held. Which sends channel 15 reports?
6. **Encoder position.** `pos e11 0`, then turn the encoder one step: does it continue from 0
   (taken) or from where it was (not)? The same with `pos e11 127`.
7. **Fader pickup.** `pickup on`, `pos f1 64`, then move fader 1 from the bottom. Does it send
   nothing until it passes the middle?
8. **Relative encoders.** `relative 1 on`: do encoders 1–8 report 77–84 with 65 and 63 for single
   steps?
9. **Colors.** `palette 0`, `palette 40`, and `palette 80`. Compare with the guide's palette. Is 0
   off? Then `rgb b11 127 0 0`, and check the Track, Page, Record, Play, and Novation buttons for
   lights.
10. **Screen.** `display f1 2`, then `text f1 0 Mix`, `text f1 1 ADI-2`, `text f1 2 -6.0 dB`, and
    move fader 1. How many characters fit per field? Then `display stationary 3` with eight names,
    and the `quiet` option (no display on change).
11. **Bitmap targets** (section 7, item 5), only if a bitmap is wanted later.

## 9. What this means for the driver (planning, not yet built)

Everything in this section is inference, for discussion with Adam before the driver is written.

- **Capabilities** (SurfaceCore):
  - 8 strips, each with:
    - one 7-bit fader without motor, so it needs pickup;
    - three endless encoders with a color LED each, absolute;
    - two buttons with RGB LEDs;
    - a temporary display per fader and encoder.
  - Plus a stationary display, Page and Track buttons, Record and Play, and Shift.
- **Pickup.** Pickup could be the device's own (feature 70, fed by position messages), or
  SurfaceCore's, which already handles surfaces whose controls need pickup. Test 7 decides
  whether the device's can be used.
- **Encoders.** Absolute with position feedback (test 6) would let SurfaceCore treat them like the
  Roto-Control's knobs at 7 bits. Relative output is the fallback.
- **Pages.** The Page buttons could page the strips, as on the Roto-Control. The Track buttons
  could move one strip at a time, or switch between sources and outputs. DAW Mixer and DAW
  Control could be two encoder layouts (e.g., sends and pan), since the device switches between
  them itself.
- **Buttons.** The top row could be PFL (or solo) and the bottom row mute. Solo/Arm and
  Mute/Select could switch what each row does, as on the device.
- **Screen.** A name and value on every move, which the Roto-Control's displays also show. The
  stationary display could show the page and the mix output.
- **Port.** The DAW port, so the MIDI port and Custom Modes stay free for other uses.
