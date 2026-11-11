# The Launch Control XL 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control XL 3 in DAW mode, as
`TOTALMIX-OSC.md` is for TotalMix FX and `ROTO-CONTROL.md` for the Roto-Control. Every statement
carries its evidence.

**Status (2026-11-01).** The device was tested on 2026-11-01 (firmware 1.2): every test the driver
needs has been run (section 8), and the records are in section 10. Where a record differs from what
sections 2–7 take from Novation's documents, the record rules. The `LaunchControl` library (which also covers the Launch
Control 3, `LAUNCH-CONTROL-3.md`), `sbdev lcxl`, and the driver (`LaunchControlDriver`, section 9)
are built on them.

## 1. Sources

Novation's documents are linked, not committed (AGENTS.md, section 4). Adam has local copies in
the project folder (`Novation Docs/`).

- **Programmer's reference guide.** "Launch Control XL 3 programmer's reference guide", version
  1.0, PDF dated April 17, 2026, 17 pages
  ([Novation](https://userguides.novationmusic.com/hc/en-gb/articles/27840466285586-About-the-Launch-Control-XL-3-programmer-s-reference-guide)).
  This is the main source. Its control map (page 9) and color palette (page 12) are pictures,
  read from the PDF.
- **User guide.** "Launch Control XL 3 user guide" (PDF, English). It describes the controls and
  the DAW modes as a user sees them.
- **Bitwig setup.** "Launch Control XL Mk3, Bitwig Studio controller extension, setup": Bitwig's
  PDF (its branding), shipped with the Bitwig extension for the device. It gives the DAW port
  names on macOS (in a screenshot), Windows, and Linux.

**How sure each statement is.** A plain statement describes what was found, in Novation's
documents or on the device. A statement that rests on a source has a footnote saying where it
comes from: one of the documents above, with its section or page, or a test on the device, whose
record is in section [10](#10-test-records). "Inference" marks anything the sources don't say
outright, and anything not yet checked on the device is said in words ("untested", "not yet
seen").

[^prg]: Novation's "Launch Control XL 3 programmer's reference guide", version 1.0.
[^prg-midi]: The programmer's reference guide (version 1.0), "MIDI on Launch Control XL 3".
[^prg-bootloader]: The programmer's reference guide (version 1.0), "Entering … bootloader".
[^prg-daw-mode]: The programmer's reference guide (version 1.0), "DAW mode".
[^prg-daw-mode-control]: The programmer's reference guide (version 1.0), "DAW mode control".
[^prg-sysex]: The programmer's reference guide (version 1.0), "SysEx message format".
[^prg-map]: The programmer's reference guide (version 1.0), page 9, the decimal picture.
[^prg-encoder-modes]: The programmer's reference guide (version 1.0), "Absolute and relative
    encoder modes".
[^prg-touch]: The programmer's reference guide (version 1.0), "Continuous control touch events".
[^prg-coloring]: The programmer's reference guide (version 1.0), "Colouring the surface".
[^prg-rgb]: The programmer's reference guide (version 1.0), "RGB Colour".
[^prg-displays]: The programmer's reference guide (version 1.0), "Configure displays".
[^prg-text]: The programmer's reference guide (version 1.0), "Setting text".
[^prg-bitmap]: The programmer's reference guide (version 1.0), "Bitmap".
[^prg-features]: The programmer's reference guide (version 1.0), "Launch Control XL 3 feature
    Controls".
[^prg-feature-table]: The programmer's reference guide (version 1.0), the feature control table.
[^ug]: Novation's "Launch Control XL 3 user guide" (PDF, English).
[^ug-daw-chapters]: The user guide, the chapters for each DAW.
[^ug-pickup]: The user guide, "Fader pickup" and Settings.
[^bitwig]: Bitwig's "Launch Control XL Mk3, Bitwig Studio controller extension, setup" (PDF,
    shipped with the Bitwig extension for the device).
[^bitwig-p2]: Bitwig's setup PDF for the device, page 2.
[^test-1]: Test 1 (2026-11-01), section
    [10](#test-1-2026-11-01-ports-daw-mode-and-the-control-map).
[^test-2]: Test 2 (2026-11-01), section
    [10](#test-2-2026-11-01-encoder-positions-relative-mode-and-fader-pickup).
[^test-3]: Test 3 (2026-11-01), section [10](#test-3-2026-11-01-fader-pickup).
[^test-4]: Test 4 (2026-11-01), section [10](#test-4-2026-11-01-colors).
[^test-5]: Test 5 (2026-11-01), section [10](#test-5-2026-11-01-the-screen).
[^test-6]: Test 6 (2026-11-01), section [10](#test-6-2026-11-01-daw-mixer-and-daw-control).
[^test-7]: Test 7 (2026-11-01), section
    [10](#test-7-2026-11-01-the-fader-values-at-the-printed-ticks).
[^test-9]: Test 9 (2026-11-01), section
    [10](#test-9-2026-11-01-turning-an-encoder-with-shift-held).
[^test-10]: Test 10 (2026-11-01), section
    [10](#test-10-2026-11-01-turning-a-relative-encoder-with-shift-held).
[^test-11]: Test 11 (2026-11-01), section
    [10](#test-11-2026-11-01-the-home-screen-shift--turn-pan-steps-and-the-arc-scale).
[^test-13]: Test 13 (2026-11-02), section [10](#test-13-2026-11-02-button-shades-and-brightness).
[^test-14]: Test 14 (2026-11-02), section [10](#test-14-2026-11-02-asking-for-daw-mode-twice).
[^test-15]: Test 15 (2026-11-02), section [10](#test-15-2026-11-02-mute-master-shades-and-flashing).
[^test-17]: Test 17 (2026-11-02), section [10](#test-17-2026-11-02-colors-and-brightness-for-101).
[^test-18]: Test 18 (2026-11-02), section [10](#test-18-2026-11-02-the-101-build-in-the-app-and-two-adjustments).
[^test-19]: Test 19 (2026-11-02), section [10](#test-19-2026-11-02-dimmer-off-buttons).
[^test-20]: Test 20 (2026-11-10), section [10](#test-20-2026-11-10-a-pans-center-in-totalmix-fx).
[^test-21]: Test 21 (2026-11-10), section [10](#test-21-2026-11-10-bitmaps).
[^test-22]: Test 22 (2026-11-10), section [10](#test-22-2026-11-10-meters-on-the-home-screen).
[^test-23]: Test 23 (2026-11-10), section [10](#test-23-2026-11-10-display-timeout).
[^test-24]: Test 24 (2026-11-11), section [10](#test-24-2026-11-11-numbering-the-meters).
[^nov-settings]: Novation, "Launch Control XL 3's Settings page", Launch Control XL 3 user guide
    (online), <https://userguides.novationmusic.com/hc/en-gb/articles/26190532189330-Launch-Control-XL-3-s-Settings-page>,
    read 2026-11-10.
[^nov-xl3-page]: Novation, "Launch Control XL 3" product page, <https://novationmusic.com/launch/launch-control-xl>, read
    2026-11-11 (dimensions; 128 × 64 monochrome OLED).
[^thomann-e16]: Thomann, "OXI Instruments E16" listing, <https://www.thomann.co.uk/oxi_instruments_e16.htm>, read
    2026-11-11 (dimensions; OXI's own page was not checked).
[^nov-custom]: Novation, "Using Custom Modes on the Launch Control XL 3", Launch Control XL 3 user
    guide (online), <https://userguides.novationmusic.com/hc/en-gb/articles/26190535820562-Using-Custom-Modes-on-the-Launch-Control-XL-3>,
    read 2026-11-10.

## 2. MIDI ports

- Over USB the device has a MIDI port pair, a DAW port pair, and two "To DIN" outputs. A host
  that uses DAW mode talks to the DAW pair.[^prg-midi]
- Port names include the device ID (1–8, set in the bootloader), so several units can be told
  apart.[^prg-bootloader]
- On Linux the DAW ports are "LCXL3 1 LCXL3 1 DAW Out" (the device's output, the host's input)
  and "LCXL3 1 LCXL3 1 DAW In". On Windows they are "MIDIIN2 (LCXL3 1 MIDI)" and "MIDIOUT2
  (LCXL3 1 MIDI)".[^bitwig]
- On macOS, Bitwig's screenshot shows the input as "LCXL3 1 DAW Out" and the output as "LCXL3 1
  DAW In".[^bitwig-p2] Bitwig may show names that differ from CoreMIDI's (inference),
  so `sbdev lcxl` matches by part of the name, "LCXL3 1 DAW", which picks one source and one
  destination if the CoreMIDI names follow the same pattern.
- **Seen on macOS** (Adam's Mac, firmware 1.2, 2026-11-01): CoreMIDI lists the sources "LCXL3 1
  MIDI Out" and "LCXL3 1 DAW Out", and the destinations "LCXL3 1 MIDI In", "LCXL3 1 DAW In",
  "LCXL3 1 To DIN Out", and "LCXL3 1 To DIN Out 2". So "LCXL3 1 DAW" picks the DAW pair.
- In DAW mode the DIN outputs send nothing.[^prg-daw-mode]

## 2a. Firmware

Adam's unit was updated to firmware **1.2** on 2026-11-01, through Novation Components. Novation's
release notes for 1.2 (shown by Components; Adam's screenshot) add, among other things:

- **A "DAW Connection" setting.** "Switch", the default and the earlier behavior, lets a DAW
  connecting move the device into DAW Mixer mode. "Connect Only" leaves the device in its Custom
  Mode, with the DAW modes still available to choose. Where the setting lives on the device isn't
  given in the notes.
- **Relative encoders in Custom Modes.** This doesn't touch DAW mode, which already had relative
  rows (section 4).
- **A higher fader scan rate,** so that fast moves are captured better.
- **Fixes:** Play not lit or not sending while Shift was held; the Easy Start prompt.

The programmer's reference guide still at Novation's address is version 1.0, with no mention of
any of this (checked 2026-11-01). So the guide predates 1.2 (inference). With "Connect Only", a
host that enters DAW mode may also have to select a DAW mode itself (feature control 30), or leave
the choice to the user; test 2 checks both settings.

## 3. DAW mode

- **Entering and leaving.** A host enters DAW mode on connecting and leaves it on quitting, which
  returns the device to standalone mode. Either form works: note 12 on channel 16 (velocity 127
  to enter, 0 to leave), or SysEx command 02h with 7Fh or 00h.[^prg-daw-mode-control] The device
  echoes the note when the mode changes, and only then: asked for DAW mode while already in it, it
  sends nothing.[^test-1][^test-14]
- **SysEx header.** Every SysEx message starts F0h 00h 20h 29h 02h 15h, in both directions, then
  a command byte.[^prg-sysex]
- **Modes.** DAW mode offers two surface modes, DAW Mixer and DAW Control. The device reports a
  mode change on channel 7, Control Change 30, and a host can select a mode the same way. Values:
  - 1 is DAW Mixer and 2 is DAW Control;
  - 6–9 are Custom Modes 1–4;
  - 18–29 are Custom Modes 5–16.

  From the feature control table; its prose differs (section 7).[^prg-feature-table]
- **What the modes change.** On the device, Mode plus Mute/Select or Solo/Arm chooses between
  them. The user guide gives the pairing both ways round (section 7). For Ableton Live, Logic
  Pro, Cubase, and Bitwig Studio the faders and buttons stay the same, and only what the encoders
  control changes; in FL Studio the modes change the buttons too.[^ug-daw-chapters] In DAW mode
  the device doesn't switch them by itself: it names the mode and passes the press on, and the
  host decides.[^test-6]

## 4. The controls

From the control map.[^prg-map] Faders and encoders report on channel 16, buttons on channel 1,
and Shift on channel 7.

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
| Novation logo button | 104 | "nothing… yet"[^ug] |
| Page up, Page down | 106, 107 | |
| Track <, Track > | 103, 102 | the left button has the higher number |
| Record | 118 | |
| Play | 116 | |
| Shift | 63 | channel 7, as a feature control |
| Mode | none | the device keeps it |

- **Button values.** The guide doesn't say what a button sends. The library reads 64 or more as
  pressed and less as released (inference: 127 and 0, as is usual).
- **Encoders, absolute.** By default an encoder sends 0–127, and takes on any position a host
  sends it.[^prg-encoder-modes] The guide doesn't say in which message; the encoder's own Control
  Change back on channel 16 works.[^test-2]
- **Encoders, relative.** Each row can be switched to relative output separately, with feature
  controls 69, 72, and 73 for rows 1–3. A relative row then reports Control Changes 64 higher
  (77–84, 85–92, and 93–100). The value is 64 for no movement, above 64 for clockwise steps, and
  below 64 for counterclockwise.[^prg]
- **Touch.** With touch reports on (feature control 71), a "touch" sends the control's Control
  Change on channel 15, with 127 for touch on and 0 for off. The guide's only example is a fader:
  BEh 05h 7Fh for the leftmost.[^prg-touch]
  - A "touch" is movement, not a touch sensor, for faders and encoders alike: each burst of
    movement sends touch on and, about 80 ms after it stops, touch off.[^test-1] (The guide
    describes the display's touch setting as the Shift + rotate, section 5; with Shift held,
    an encoder sends only these reports, tests 9 and 10.)
  - So SurfaceCore can't use a touch as a hand resting on a control, only as a sign of movement.
- **Fader pickup.** The programmer's reference guide lists feature control 70 as "DAW Fader
  Pickup", on or off, with no description.[^prg-features]
  - The user guide's pickup, where a moved fader takes over only once it reaches the parameter's
    value, is the Settings menu's, which leaves DAW modes alone.[^ug-pickup]
  - That feature 70 works the same way in DAW mode, learning the value from the position message
    above, was an inference that test 3 confirmed.[^test-3]

## 5. Lights and the screen

- **Palette colors.** A Control Change on channel 1, with the control's own number, lights it in
  one of 128 palette colors.[^prg-coloring] The guide says encoder LEDs use their absolute
  numbers even in relative mode, under "RGB Colour"; that the same holds for palette colors is an
  inference. The palette is a picture in the guide (page 12). Index 0 is off and 5 is
  red;[^test-4] indices 0–39 have been seen to match the picture's run of colors, as far as a
  photo can show.
- **RGB.** SysEx 01h 53h, then the control, red, green, and blue, lights a button or an encoder in
  a color of its own.[^prg-rgb] SysEx data bytes are 7-bit, so each part is 0–127. That this
  covers the LED's full range is an inference.
- **The screen** is 128 × 64 pixels.[^prg-bitmap]
  - **Display targets.** Each fader and encoder has a temporary display (target = its Control
    Change, 5–36). There is also a stationary display (53) and an overlay (54).[^prg-displays]
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
    box, 1Dh flat sign, and 1Eh heart.[^prg-text] How many characters a field shows is not
    given.
  - **Bitmap.** SysEx 09h sends a whole picture: 64 rows of 19 bytes, 7 pixels per byte, highest
    bit leftmost. The device answers when it is ready for the next one. It holds one bitmap at a
    time.[^prg-bitmap] On the device, the target is 35h (the stationary display, as "Configure
    displays" numbers it; the guide's 20h drew nothing), the message ends with F7h, a set bit
    lights a pixel, and the first byte is the top left; the reply took 66–72 ms (once 340 ms while a
    control moved), so about 14 pictures a second at most; a control's own temporary display shows over the picture and the picture
    returns after it; pictures sent meanwhile are answered as usual.[^test-21] A picture sent to 36h
    replaced the one on the screen and stayed up; whether 36h differs from 35h at all is not yet
    known.[^test-21]

## 6. Feature controls

Control Changes on channel 7 to the DAW port set them. The same Control Change on channel 8 asks
for one, and replies come on channel 7. In DAW mode all of them listen, but only a few reply.
Note 11 on channel 16 (velocity 127 or 0) enables every feature control, or goes back to DAW
mode's own set.[^prg-features] The inference is that this means their replies, since in DAW
mode they all listen already.

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
   Studio chapters. Twice, in the DAW Control tips, it says the reverse. Mode plus Solo/Arm
   shows "DAW Control" on the screen, so the six are right; but the device doesn't switch by
   itself.[^test-6]
4. **Display targets for names.** The programmer's reference guide's note on arrangements mentions
   targets that only set names, 22h–28h (34–40), a range that overlaps encoder targets (34–36) and
   button numbers (37–40). The target list gives no such range.
5. **Bitmap targets.** The bitmap section names the stationary display 20h and the global
   temporary display 21h, where "Configure displays" uses 35h and 36h. Settled on the device:
   20h drew nothing and got no reply; 35h works.[^test-21]
6. **Bitmap message end.** The bitmap message is shown ending with 7Fh, not F7h, and the reply as
   F0h … 09h 7Fh, with no F7h. Settled on the device: a message ending with F7h alone works with
   35h (with 20h, neither end worked); the reply is read in either form.[^test-21]
7. **The global MIDI channel.** The feature control table gives the range as 00h–0Eh, called 0–15,
   with 00h as channel 1 and 0Eh as channel 16; but 0Eh is 14. Performance Bridge leaves this setting
   alone, so it doesn't matter here.

## 8. Tests to run on the device

Run with `swift run sbdev lcxl` (macOS; `sbdev lcxl --help`). First, `sbdev lcxl ports` lists the
port names.

1. **Ports.** Run.[^test-1] The macOS names of the DAW ports. Does `--port "LCXL3 1 DAW"` connect?
2. **DAW mode.** Does the device show DAW mode on entering, and return to standalone on `quit`? With firmware 1.2's "DAW Connection" set to Switch (the default), does entering DAW mode move it to DAW Mixer? With "Connect Only", does it stay in its Custom Mode, and does `mode mixer` then move it?
3. **The control map.** Run.[^test-1] Move every control and check its name and value against section 4,
   including Track < and > (103, 102) and the Novation button. What do buttons send: 127 and 0?
4. **Modes.** Run.[^test-6] Mode plus Mute/Select, then plus Solo/Arm: which reports 1 and which 2 (section 7,
   item 3)? Does `mode control` switch the device?
5. **Touch.** Run: a touch report comes from movement, not a sensor.[^test-1] With `touch on`: touch a fader and an encoder without moving them, then move each
   with Shift held. Which sends channel 15 reports?
6. **Encoder position.** Run: the encoder takes the position.[^test-2] `pos e11 0`, then turn the encoder one step: does it continue from 0
   (taken) or from where it was (not)? The same with `pos e11 127`.
7. **Fader pickup.** Run: the device's pickup works,[^test-3] with one unexplained run in test 2.[^test-2] `pickup on`, `pos f1 64`, then move fader 1 from the bottom. Does it send
   nothing until it passes the middle?
8. **Relative encoders.** Run: they work as the guide says.[^test-2] `relative 1 on`: do encoders 1–8 report 77–84 with 65 and 63 for single
   steps?
9. **Colors.** Run for indices 0–39 and RGB;[^test-4] 33, 37, 45, 49, and 53 seen in test 17;[^test-17] the rest of 40–127 not yet. `palette 0`, `palette 40`, and `palette 80`. Compare with the guide's palette. Is 0
   off? Then `rgb b11 127 0 0`, and check the Track, Page, Record, Play, and Novation buttons for
   lights.
10. **Screen.** Run.[^test-5] `display f1 2`, then `text f1 0 Mix`, `text f1 1 ADI-2`, `text f1 2 -6.0 dB`, and
    move fader 1. How many characters fit per field? Then `display stationary 3` with eight names,
    and the `quiet` option (no display on change).
11. **Bitmaps** (section 7, items 5 and 6), for meters on the screen (Adam asked, 2026-11-10).
    `bitmap 20 frame`, then `21`, `35`, and `36`: which targets show the picture, does the reply
    come, and with which end (add `7f` for 7Fh F7h)? Does a set bit light a pixel, and is the block
    at the top left? `show stationary off` takes it down. Then `bitmaprate T 10` with a target that
    works: how many pictures a second, and how long the reply takes.
12. **Do level encoders need relative mode?** Part 1 run (2026-11-01, Launch Control 3 layout on
    the XL 3, TotalMix FX's curve): "pretty smooth". Adam then asked for the ARC USB's scale for volume
    encoders (section 9), which is finer near 0 dB. On it, a slow fade of a send from about −20 dB
    to off sounded smooth.[^test-11] **Decided: absolute mode** (Adam, 2026-11-01); relative mode
    has been observed to drop the first step after a reversal and gives nothing Shift could
    use.[^test-10]
    The original test: the encoders send 128 values. With TotalMix FX's own
    curve that is about 0.26 dB a step from −6 to +6 dB, 0.3–0.6 from −20 to −6, 0.6–0.9 from −40
    to −20, and about 1 dB below that (computed from `FaderCurve`). Relative mode would allow finer
    steps, but has been observed to drop the first step after a change of direction.[^test-2] With music playing
    through one playback, and `sbdev lcbridge --layout lc3-sim --in-port 7004 --out-port 9004`
    (the bottom encoder row is level):
    1. **Trim.** Set the playback to about −10 dB, then turn up one step at a time to −5. Do the
       steps sound smooth?
    2. **Targets.** Set 0.0 dB, then −3.0 (the nearest values are −3.12 and −2.86). Close enough?
    3. **Sweep.** From off to about 0 dB in one quick turn: how far did the encoder turn, and was
       that comfortable?
    4. **Fade.** From −20 dB down to off, slowly. Smooth, or audibly stepped?
    5. The same on a send, in the XL 3's layout (`--layout xl3`, a send row), into the phones.

    Keep absolute mode if 1, 2, and 4 sound smooth and 3 is comfortable. If trims or fades are
    audibly stepped, or 2 is too coarse, use relative mode with finer steps (e.g., 0.1 dB for a
    slow step, more as the device accelerates).
13. **The send-reset text.** Run in part: the overlay flashed too fast to read (Adam, 2026-11-02).
    Now on the encoder's display: in the app (1.0.2 or later), hold Shift a moment and turn a send
    encoder. Does its display read "Shift+turn: restore"? Release Shift: is its middle line the send
    ("> Phones 1") again? Then Shift + turn it again: "Send restored"?

## 9. How Performance Bridge uses it

Decided with Adam, 2026-11-01, after the tests; built in `LaunchControlDriver`, and chosen in the
app's Settings → Connections. The layout is to be reviewed closely in the Tier 1 UI review and by
Adam (Adam asked for its efficiency and intuitiveness to be assessed).

- **Eight strips.** Each fader is its strip's level in the home submix (Main Out). The strips
  always show sources.
- **Fader pickup.** The driver turns on the device's pickup (feature 70) and sends each fader's
  level as a position, so the device holds a fader back until it reaches TotalMix FX's level and
  shows the target meanwhile.[^test-3] SurfaceCore's own pickup stays on behind it, with a window
  of 12/127 of TotalMix FX's fader travel for the first value after the device lets go (7 to 18 of
  the fader's values, depending on where on the printed scale), in case the device doesn't hold
  (as in one run of test 2).
- **Fader scale.** The nine ticks printed beside each fader read, top to bottom, +6, +3, 0, −6,
  −10, −20, −40, −60, and off: TotalMix FX's own fader marks (`TOTALMIX-OSC.md`, test 18), placed
  at the fader values measured at each tick.[^test-7] Between ticks the gain moves evenly in dB
  (Adam, 2026-11-01).
- **Level and send encoders.** They use the scale of RME's ARC USB volume wheel, as volume
  controls (Adam, 2026-11-01): its 54 detents from −63.5 to +6 dB (docs/TOTALMIX-OSC.md, test 19),
  spread over the encoder's values so that 0 dB is at 101, as on the faders. That is about 0.2 dB a
  value from −5 to +5 dB, 0.4 dB from −15 to −5, and up to 1.3 dB at the bottom; value 0 is off.
- **Pan encoders.** They are centered at 64, which TotalMix FX has been observed to show as C from
  either side,[^test-20] and land on TotalMix FX's whole pan steps (L100 to R100), about 1.6 steps a value, so they move in steps of 1 or 2. Each value is sent a quarter step to the right of
  its whole step, so that TotalMix FX's window shows the same step as the encoder's display. TotalMix FX
  has been observed to show the whole step below a fractional pan, toward L (Adam, 2026-11-01):
  with plain values, one value right of center (R1.6) showed R01 in TotalMix FX and R2 on the device;
  with a quarter step away from the center, the R side matched and the L side was one step off
  (L2.25 as L03, inference from "off by 1"). A quarter step to the right matches on both sides.
- **Encoder rows.** Fixed (Adam, 2026-11-01): the top two rows are sends and the bottom row pan,
  the order of Novation's own DAW integrations (Live, Logic Pro, and Cubase in the user guide's "DAW
  Mixer mode" sections), with pan directly above the fader. Each send row feeds one output, chosen on
  the device: Page up and down step the top row through the send targets (the Outputs list's order,
  control room outputs first), and Shift + Page the middle row, each skipping the other row's
  output, so the two never feed the same one. The overlay names the row and its output ("Top row" /
  "> Phones 2"). Page is lit where it would move for the top row, and for the middle row while
  Shift is held. The choices are remembered across launches. Gain is left out for now: TotalMix FX sends it only for inputs with a preamp, which the
  project's interfaces don't have. The encoders take positions from the driver,[^test-2] so they
  never jump.
- **Shift + turn.** Resets the encoder (Adam, 2026-11-01; made safer 2026-11-02 after the review
  of that date, which found that a hand reaching for Shift + Page or Shift + Track could brush an
  encoder and reset it):
  - a pan goes to the center;
  - a level (the Launch Control 3's) above 0 dB comes down to 0 dB, and one at or below 0 dB
    stays: a reset never raises a level;
  - a send goes to −oo, and a second Shift + turn, after Shift is released and held again, brings it
    back to where it was; the encoder's own display then reads "Shift+turn: restore", then "Send
    restored", on its middle line, which comes back when Shift is released (Adam, 2026-11-02, from
    the UI review of that date). The overlay was tried first and flashed too fast to read (seen by
    Adam, 2026-11-02), presumably covered at once by the encoder's display (an inference); the encoder's display hasn't been
    seen yet (section 8, item 13);
  - only once Shift has been held 0.3 s with no Page or Track press, and once per encoder per hold
    of Shift.

  With Shift held the device reports only that an encoder turned, not which way,[^test-9][^test-10]
  so a reset is all it can do. The driver also sends the encoder its new position, since the turn
  with Shift held left the device's own value where it was.[^test-9]
- **Buttons.** The top row is PFL (yellow) and the bottom row mute (orange), the colors the
  Roto-Control's firmware gives solo and mute, so every hardware controller shows them alike (Adam,
  2026-11-02). A button that is off shows a dim shade of its color, so the two rows stay
  recognizable (Adam, 2026-11-02): by exact RGB, yellow 16, 11, 0 and orange 12, 4, 0, dimmer than
  the palette's dimmest shades (15 and 11), for more contrast with a button that is on.[^test-19]
  The bright shades have been observed to look as bright as full RGB values.[^test-13] Solo/Arm and Mute/Select do nothing for now: in DAW mode
  the device leaves them to the host.[^test-6]
- **Paging and views.** Track < and > move by eight strips, as the panel's labels say, and with
  Shift to the first or last page. (Novation's integrations move one track, and eight with Shift.
  Here the order is set in the app, so moving one strip gains nothing, and pages stay on multiples
  of eight, as on the Roto-Control; Shift modifies Track rather than adding a new function; Adam,
  2026-11-01.) The strips always show the channels (inputs and playbacks), never the outputs: the
  outputs are set up in TotalMix FX and left alone during a performance (Adam, 2026-11-01). Page
  and Track are lit where they would move.
- **Free buttons.** Solo/Arm, Mute/Select, Record, and Play do nothing, so arm and the transport
  stay free for a later connection to a DAW (Adam, 2026-11-01).
- **Mute and PFL presses** show on the overlay as well as the light: the channel's name and "Mute
  on", "Mute off", "PFL on", or "PFL off" (Adam, 2026-11-02), or "Mute Master off" for a mute while
  TotalMix FX's Mute Master is off.
- **The Novation button** brings TotalMix FX's window to the front, and, with TotalMix FX already
  in front, goes back to the app that was (Adam, 2026-11-02). It was
  tried as a one-press "first page" earlier that day and dropped as hard to find.
- **Both Track buttons together** go to the first page (Adam, 2026-11-02).
- **Mute Master.** While TotalMix FX's Mute Master is off, a mute that is on flashes between bright
  and dim orange (0.5 s each; 0.4 s until Adam slowed it, 2026-11-02), and pressing a mute shows "Mute Master off / in TotalMix FX" on
  the screen (Adam, 2026-11-02). The medium shade was too close to the others, and no way to make
  the device flash a color by itself has been found, so the driver flashes it.[^test-15]
- **Presence.** While connected, the driver asks for the surface mode (feature control 30) after
  5 s with nothing from the device. If two questions go unanswered, or the answer is a Custom Mode
  the device never announced, it assumes that the device restarted and lost DAW mode, and enters
  DAW mode again (Adam, 2026-11-02, from the review of that date). That a restarted device whose
  port stays open answers this way is an inference, not yet seen: the quick replug in test 15 was
  caught by the app's port check, not by this. Whether the device answers the question in a Custom
  Mode is untested, so the check is skipped there (review of 2026-11-02).
- **Colors.** Level and pan encoders show their strip's TotalMix FX color from the palette; a blank
  strip is dark. A send row shows the color of the output it sends to, so each row reads as one
  send, as Ableton Live's integration lights send rows in the send's color.[^ug-daw-chapters] An
  output left white in TotalMix FX (its default) shows the row's own hue instead, as Logic Pro's and
  Cubase's integrations use a fixed color per row: teal (33) for the top row and magenta (53) for
  the middle, neither one of TotalMix FX's eight colors, so the rows can be told apart from each
  other and from the sources (Adam, 2026-11-02, from the Tier 3 review of that date; before 1.0.1,
  a white output was green in the control room and blue otherwise). Both have been seen as named
  and told apart from blue, purple, and green; cyan (37), tried first, looked too close to
  blue.[^test-17] Blue (45) and purple (49) were seen as named in test 17 too.
- **Level by brightness** (Adam, 2026-11-02, from the Tier 3 review of that date). A setting in
  Settings → Connections, off by default, dims each send encoder continuously with its level, so
  turning a control has a visible, proportional effect (it isn't meant for reading a level off the
  light; Adam, 2026-11-02). The light is the color's exact RGB (SysEx 01h 53h), which matched each
  palette color compared on the encoders,[^test-17] scaled so its brightness falls geometrically
  from full at the top of the travel to a value of 5 at the bottom, and dark at −oo.
  - In test 17, even steps of value and a 2.2 gamma curve bunched at the top, values down to about
    80 looked close to full (64 the first clearly dimmer), and a geometric run from 80 down looked
    close to even, while one from 127 bunched its first two or three steps.[^test-17] The curve as
    built, geometric from 127, was seen to dim and brighten predictably as an encoder
    turned.[^test-18] By the curve, a send at 0 dB is at about 55% (70 of 127; computed).
  - In test 18, 9, 7, and 5 dimmed in turn and 4 and below looked dark, hence the floor at
    5.[^test-18] A color with two lit parts dims only until its smaller part reaches 5, so the part
    doesn't go dark first and change the hue: purple (16, 0, 127) stops at 5/16 of full and orange
    (127, 40, 0) at 5/40. At those dimmest values, purple (5, 0, 40) was seen as purple beside blue
    (0, 0, 40), "a bit close but distinguishable", and orange (16, 5, 0) as orange beside red
    (16, 0, 0), "very different".[^test-18]
  - Palette yellow (13) looks greener on the encoders than on the buttons, so the encoders show
    yellow as 127, 85, 0, which matched the buttons' yellow best of those tried, with the setting on
    or off. Palette orange (9) matched as it is; orange's exact color with the setting on (127, 40,
    0) was matched on buttons only (test 13).[^test-18]
  - Pan encoders keep full brightness, and the faders, which carry the level, have no lights. Red's,
    green's, and grey's exact colors are inference (read off the guide's picture; grey's a guess),
    and purple's (16, 0, 127) is inferred from 20 looking slightly redder; 16 itself was not lit.
- **Screen.** Each fader and encoder has a three-line display (arrangement 2): the channel's name,
  what the control does ("Level", "Pan", "> Phones 1"), and the value in dB or as a pan, sent by
  the driver.[^test-5] The stationary display, the home screen, has three lines (arrangement 2): the
  page's first and last channels by name ("Vox to Gtr"), as the controls' displays name them, with
  the page in front when there is more than one ("Page 1/2: " or, if that doesn't fit, "1/2: "; Adam,
  2026-11-10), or the page alone ("Page 1 of 2"; with one page, the number of channels) when the
  names don't fit, rather than names cut into fragments (counts by kind, "In 6-7, PB 1-6", matched nothing in TotalMix FX, and "In" could be read
  as "ln"; Adam, 2026-11-11[^test-24]), and where each send row goes
  ("Top > Phones 1", "Mid > Phones 2"; "Top row >" ran most outputs' names off the
  screen[^test-22]), which nothing else on the device shows (Adam, 2026-11-01). Whether the page's
  line fits is estimated from character widths measured in photos of the screen (an
  inference).[^test-22][^test-24] With **Meters** on (a setting, off by default: on the XL 3 the meters replace the text home screen,
  and the Launch Control 3 hasn't been tried with them; Adam, 2026-11-11, on a review's advice), the home screen is a
  picture instead: a meter for each strip, 45 pixels tall, with a finely dotted line across each bar at 0 dBFS (the top), no clip lights, a stereo channel's two bars one pixel
  apart and the strips five apart, each bar with its peak held 2 s and then falling at 20 dB a second, as TotalMix FX's peaks drop
  (Adam, 2026-11-11[^test-24]), shown even once its bar has emptied, until it meets the level (a
  held peak not yet falling shows only over a bar, since a lone one at a channel's noise floor looked
  like stray pixels[^test-22]), and no dB
  marks; under each meter its place on the page, 1–8 (Adam, 2026-11-11[^test-24]), with one line
  under each run of playbacks' numbers (one pixel thick; kept for now, Adam), and the screen's bottom
  rows dark; Track shows the page and its first and last channels on the overlay, each with its
  slot, the number under its meter, the first pushed left and the last right with spaces, since the
  device centers each line ("Page 1 of 2", "1 Vox", "to" and "3 Gtr"; Adam, 2026-11-10 and 2026-11-11;
  test 24 for the spaces; a page with one channel shows two lines, not yet seen on the device). Flagged for the UI review (Adam, 2026-11-11): a separator after the slot
  number (a colon, an en dash, or an em dash, or a hyphen if the font has no dash), and "Pb" or "PB"
  for an unlabeled playback.[^test-22][^test-24] How long a control's display stays up is the device's own
  Display Timeout setting, in seconds (by eye), which applies in DAW mode too (that it covers the overlay as
  well is an inference); 1 or 2 suits this layout (Adam, 2026-11-10).[^test-23] Every page keeps eight fixed slots, strip k in the kth, an empty slot marked by one dot on the top
  row (centering a shorter page was tried and dropped).[^test-24] The eight names packed to
  four characters (arrangement 3, e.g., "ADI2SonoM1/2Tonv") were tried first and were unreadable
  (Adam, 2026-11-01); each strip's name shows on its control's display when the control moves.
  Page shows the new send on the overlay.
- **Port.** The DAW port, so the MIDI port and the Custom Modes stay free for other uses. Choosing
  a Custom Mode on the device stops the driver drawing until DAW Mixer or DAW Control is chosen
  again.

## 10. Test records

### Test 1 (2026-11-01): ports, DAW mode, and the control map

**Setup.** Adam's Launch Control XL 3, firmware 1.2, "DAW Connection" at its default (Switch). `sbdev lcxl` (and `--raw`), which enters DAW mode and turns on touch reports. Logs from Adam.

**Findings:**
- **Ports.** `sbdev lcxl` found "LCXL3 1 DAW Out" and "LCXL3 1 DAW In" by its default name, "LCXL3 1 DAW" (section 2).
- **Entering and leaving DAW mode.** The device answered `9F 0C 7F` to the same message, and `9F 0C 00` on leaving: it echoes the DAW mode message. Mode Select then showed DAW Mixer. It sent no mode report on entering. On leaving it reported Custom 1 (`B6 1E 06`), whichever mode it had been in before.
- **The control map** matches section 4 for all 59 controls tried. Moved one by one in order, these reported where the map puts them, and nothing else did:
  - faders 1–8 (Control Changes 5–12, channel 16);
  - all 24 encoders, row by row (13–36, channel 16);
  - top-row buttons 1–8 and bottom-row buttons 1–8 (37–52, channel 1);
  - Solo/Arm (65), Mute/Select (66), the Novation button (104), Page up and down (106, 107), Track < and > (103, 102), Record (118), and Play (116), all on channel 1;
  - Shift (63, channel 7).
- **Buttons** send 127 when pressed and 0 when released, Shift included. The Novation button sends, though the user guide says it does nothing yet. Buttons don't light by themselves in DAW mode.
- **Encoders** are smooth, with no detents. In absolute mode, values step by 1 when turned slowly. Faster turns skip values (1 → 3, 1 → 5 → 7), so the device accelerates (inference: the "Encoder Curve" feature, section 6). At 0, turning counterclockwise sends no value.
- **"Touch" is movement, not a touch sensor.** With touch reports on, a fader or encoder sends touch on (channel 15, 127) just before its first value and touch off (0) about 80 ms (encoders) to 120–150 ms (faders) after its last. Turning an encoder at 0 counterclockwise sent touch on and off with no value between. Touching without moving wasn't tried; the inference is that it sends nothing.
- **Mode selection.** After Mode is pressed, the screen shows "Mode Select" and goes dark after a second or so. But the buttons stay mode selectors until a mode is chosen:
  - top-row button 1 chose Custom 1 (named "Tonverk Mixer" on Adam's unit);
  - bottom-row button 1 chose Custom 9 (the button is labeled 9 underneath);
  - Mute/Select chose DAW Mixer.

  Meanwhile Page and Track sent nothing.
- **Mode reports.** Every mode report on Control Change 30 came with **Control Change 31**, which the guide doesn't list:

  | Mode | CC 30 | CC 31 |
  |---|---|---|
  | DAW Mixer | 1 | 1 |
  | Custom 1 | 6 | 6 |
  | Custom 9 | 22 | 17 |

  So CC 31 is not a copy of CC 30, and its meaning is unknown. Custom 9 as 22 fits the guide's feature table (section 7, item 1).
- **The screen** showed a moved fader's or encoder's value for a moment, then went dark.

**Consequences.** The library's control map, button values, and Shift are right. Its touch reports are movement reports: SurfaceCore can't use them as a hand resting on a control, only as a sign of movement, which its holds already take from the values. The library should read the DAW mode echo (`9F 0C`), and CC 31, as their own events (inference: neither choice causes a problem).

### Test 2 (2026-11-01): encoder positions, relative mode, and fader pickup

**Setup.** As test 1. `sbdev lcxl`; logs from Adam.

**Findings:**
- **Encoder positions.** After `pos e11 100` (`BF 0D 64`: the encoder's own Control Change on channel 16), turning the top-left encoder clockwise reported 101, 102, … 107. The screen showed the same. So an absolute encoder takes the position the host sends it in this message, which the guide didn't name (section 4).
- **A change of direction.** The first move after turning the other way sent touch on and off with no value, in both absolute and relative mode (seen three times). The device seems to drop the first step after reversing, though not every time: in a later log an absolute encoder reversed with a value at once (`lcxl-shift-relative.log`, e33 at 201.740 s; review of 2026-11-02).
- **Relative mode.** After `relative 1 on`, the top-left encoder sent Control Change 77 (`4D`) on channel 16, with 65 clockwise and 63 counterclockwise, one step at a time when turned slowly. Its touch reports used 77 too (`BE 4D 7F` and `00`), not 13. The library now reads both.
- **Fader pickup, first run.** After `pickup on` (`B6 46 7F`) and `pos f1 64`, fader 1 was moved from 53 down to 0, then from 0 up to 127. Every value was sent, all the way. Test 3 found pickup working; why it didn't here is unknown (seen once).

**Consequences.**
- Encoders can stay in absolute mode, with the host sending positions, as the Roto-Control's knobs are driven (section 9). Relative mode works too, as a fallback.
- Pickup: see test 3.

### Test 3 (2026-11-01): fader pickup

**Setup.** As test 1. `sbdev lcxl`, then `pickup on` (feature 70), then a position for fader 1 with `pos f1 N` (`BF 05 N`) before each case. Adam watched the screen; log kept.

**Findings:**

| Case | Fader started | Target | Moved | Screen | First value sent |
|---|---|---|---|---|---|
| A | top (127) | 64 | down | showed 64, then counted down once past halfway | 63, 2.4 s after the movement began |
| B | about 31 | 64 | up | showed 64, then counted up once past halfway | 65, 1.7 s after the movement began |
| C | about 63 | 100 | down | showed 100 throughout | none |

- While a fader was held back, it still sent movement reports (touch on and off, channel 15) but no values.
- Once it had passed the target, every value came through, and later moves were unaffected until a new position was sent.

**Consequences.**
- With feature 70 on, the device does pickup itself. It holds back a fader's values until the fader passes the position the host sent, and shows that position on the screen meanwhile.
- That suits the driver better than SurfaceCore's own pickup, since the user sees the target. The driver can turn feature 70 on and send each fader's position, and give SurfaceCore a fader that "follows" (inference at the time; the driver does this, section 9).
- Test 2's run, where nothing was held back, stays unexplained.

### Test 4 (2026-11-01): colors

**Setup.** As test 1. `sbdev lcxl`, then `palette 0` (encoders 0–23, then buttons 24–39, as CCs on channel 1), a photo, then `rgb b11 127 0 0` and `color C 5` for `pageup`, `trackleft`, `record`, `play`, `soloarm`, and `novation`.

**Findings:**
- Index 0 is off: encoder 1's LED stayed dark.
- The 40 indices ran from grays and white through pink, reds, oranges, yellows, and greens to cyans and blues, in the same order as the guide's palette picture. The pale tints (1–3, 8, 12, 16, 20) looked near white in the photo, so their exact shades have not been checked.
- `rgb b11 127 0 0` lit top-row button 1 red.
- Index 5 lit Page up, Track left, Record, Play, and Solo/Arm red, so each has a color LED of its own.
- The Novation button has no LED, as the library assumed: `sbdev` refused `color novation 5` without sending.

**Consequences.**
- The driver can use palette indices for the strips' colors and RGB where a palette color is too far off, e.g., to match TotalMix FX's eight colors.
- Page, Track, Record, Play, and Solo/Arm can show state, e.g., whether another page exists.

### Test 5 (2026-11-01): the screen

**Setup.** As test 1. `sbdev lcxl`, then the commands below; Adam watched the screen and took photos (not committed).

**Findings:**
- **Arrangement 2 on a fader** (`display f1 2`, then `text f1 0 Mix`, `text f1 1 ADI-2`, `text f1 2 -6.0 dB`). Moving fader 1 showed three centered lines, "Mix", "ADI-2", and "-6.0 dB", in place of the number. The text stayed for the rest of the session (about 12 minutes) and came up on every move of fader 1; the device doesn't change it as the fader moves.
- **Line length.** `text f1 1` with the 26 capitals showed "A" to "M" and half of "N", cut off at the screen's edge with no scrolling. With 30 lowercase "i"s it showed 20, centered, in less than half the width.
  - The font is proportional.
  - A field keeps at most 20 characters. This is an inference from the "i"s: the line had room for more, and none showed.
- **Arrangement 3 on the stationary display** (`display stationary 3`, title "Page 1", names "Mic 1" in field 1, "Mic 2" in field 2, and "ABCDEFGHIJ" in field 8, then `show stationary on`).
  - The title was centered on the top line.
  - The names were in two rows of four columns: fields 1–4 in the first row and 5–8 in the second, so field 8 was bottom right.
  - Each column is a quarter of the width. "Mic 1" filled its column, so "Mic 1Mic 2" ran together, with no gap added. Field 8 showed "ABCD", cut off at the column's edge.
- **Back to the stationary display.** After fader 1's display timed out, the screen went back to the stationary display.
- **Quiet** (`display f2 4 quiet`, which clears bits 6 and 5). Moving fader 2 all the way up and down left the stationary display on the screen. Fader 2's values were still sent.

**Consequences.**
- The driver sends each strip's name and a value text of its own (e.g., in dB) as the strip's level changes, since the device shows the text it was given, not the fader's value. That this is fast enough to follow a fader is an inference to check when the driver runs.
- Names on the two- and three-line displays can be about 13 capitals long (more in lowercase), and at most 20 characters. In arrangement 3's columns they fit in about four capitals, so the driver needs short names there, and a space of its own between columns.
- Quiet makes a control send without covering the stationary display, if a strip should not show a display.

### Test 6 (2026-11-01): DAW Mixer and DAW Control

**Setup.** As test 1. `sbdev lcxl`; `query 30` asks for the current mode (`B7 1E 00`), and `mode control` and `mode mixer` select one (`B6 1E 02`, `B6 1E 01`).

**Findings:**
- **On the device.** Mode, then Solo/Arm, showed "DAW Control" on the screen (the label for Mute/Select was "DAW Mixer"). But the device sent only the button's own press and release (Solo/Arm on CC 65, Mute/Select on CC 66), with no mode report, and `query 30` answered DAW Mixer before and after each press.
- **From the host.** `mode control` was answered with a report of DAW Control, and `mode mixer` with DAW Mixer.
- **Encoders.** Encoder 1 sent the same control number (13) in both modes, and its value carried on from one mode to the other.

**Consequences.**
- In DAW mode the device leaves the choice between DAW Mixer and DAW Control to the host: it names the mode on the screen and passes the press on. That the host is meant to answer with a mode message is an inference.
- The two modes change nothing the device sends, so the driver can ignore them, or treat Solo/Arm and Mute/Select as buttons of its own (e.g., to switch what the encoders control) and send a mode message only to keep the device's screen in step.
- Custom Modes chosen on the device do switch it, and are reported.[^test-1]

### Test 7 (2026-11-01): the fader values at the printed ticks

**Setup.** `sbdev lcxl`. Adam pushed fader 1 to the top, then brought it down, stopping with the white line on its cap level with each of the nine ticks printed beside it; log kept. He was not sure he hit each tick exactly. With the fader all the way up the line is level with the top tick, and all the way down with the bottom tick (seen).

**Findings:**

| Tick (from the top) | Stopped at | Straight line through ticks 2–8 |
|---|---|---|
| 1 | 127 (the top of the travel) | — |
| 2 | 120 | 120.0 |
| 3 | 102 (101 for a moment) | 101.7 |
| 4 | 84 | 83.5 |
| 5 | 66 | 65.2 |
| 6 | 45 (47 to 48 on the way) | 47.0 |
| 7 | 29 | 28.7 |
| 8 | 11 | 10.5 |
| 9 | 0 (the bottom) | — |

- The ticks are evenly spaced on the panel (measured in a photo: 133–135 pixels apart). Between ticks 2 and 8 the fader sends about 18 values per tick, but only 7 between ticks 1 and 2 and 11 between ticks 8 and 9. So the fader's values are not linear in its travel near the ends (inference: Novation's firmware shapes them, or the ends have dead zones).
- An earlier reading of the top three ticks as 127, 117, and 107 (from gains Adam read) does not fit and is set aside.

**Consequences.** The driver first took the ticks at 127, 120, 102, 84, 66, 45, 29, 11, and 0; test 8 refined them, and `LaunchControlDriver.faderTicks` is the mean of the two passes (127, 119, 101, 83.5, 65.5, 46, 29, 11), so each tick lands on its label whatever the fader does between them.

### Test 8 (2026-11-01): the fader scale, read back

**Setup.** `sbdev lcbridge` with the fader scale of test 7 (ticks taken at 127, 120, 102, 84, 66, 46, 29, 11, and 0). Adam set fader 1 to each tick and read the gain.

**Findings** (Adam, from the bottom tick up): −oo, −60, −40, −19.5, −10.5, −6.2, −0.7, +2.7, +6.0, against labels of −∞, −60, −40, −20, −10, −6, 0, +3, and +6.

**Consequences.** Each reading, through the slope of its stretch of the scale, places its tick a little off test 7's value: 0 dB at about 99.9 (not 102), +3 at 118.2 (not 120), −6 at 83.1, −10 at 65, −20 at 46.4. Neither pass is exact (Adam's alignment by eye), so the driver takes the mean of the two: 127, 119, 101, 83.5, 65.5, 46, 29, 11, and 0. Readings still off by a few tenths of a dB at a tick are within the accuracy of setting a fader to a tick by eye. Off now shows as "-oo" on the hardware controllers' displays, as TotalMix FX shows it (Adam, 2026-11-01).

### Test 9 (2026-11-01): turning an encoder with Shift held

**Setup.** `sbdev lcxl` (absolute mode, touch reports on). Adam held Shift, turned encoder 1 several clicks clockwise and counterclockwise, released Shift, and turned it again; log kept.

**Findings:**
- Shift sent its press and release (channel 7, CC 63).
- With Shift held, the encoder sent only touch reports, on and off about 80 ms apart for each burst of movement (30 pairs over 6 seconds), and no values. The touch reports carry no direction.
- After Shift was released, the encoder carried on from 62, next to where it had been, so the turns with Shift held had not changed the device's own value (as the user guide's Shift "preview" says).

**Consequences.** In absolute mode the host can't tell which way an encoder turned with Shift held, so Shift can't make coarse steps there. It can still act on "turned with Shift held" (e.g., reset a pan to the center). Whether relative mode sends steps with Shift held is untested.

### Test 10 (2026-11-01): turning a relative encoder with Shift held

**Setup.** `sbdev lcxl` (touch reports on), then `relative 1 on` (the top encoder row in relative mode). Adam turned the top row's first encoder ("e11" in the log) a few clicks each way, then held Shift and turned it again; log `lcxl-shift-relative.log`.

**Findings:**
- Without Shift, each click sent a touch, a step of +1 or −1, and a release about 80 ms later. The first click after a change of direction sent a touch and a release with no step (as in test 2).
- With Shift held, ten bursts of turning over 4.5 s sent only touches and releases, with no steps.

**Consequences.** Relative mode doesn't help: with Shift held, the host learns only that an encoder was turned, never which way. Shift + turn can reset a control (e.g., a pan to the center), but it can't make coarse steps.

### Test 11 (2026-11-01): the home screen, Shift + turn, pan steps, and the ARC scale

**Setup.** `sbdev lcbridge` on main after PRs #55–#58, TotalMix FX "2.10 (1)" with a Digiface AES; the Launch Control 3's layout (`--layout lc3-sim`), then the XL 3's. Logs `lc3-arc.log`, `xl3-pan.log`, `xl3-pan2.log`.

**Findings** (Adam's reports):
- The home screen's three lines ("Channels 1-8", the top row's function, the buttons') "look good".
- Shift + turning a level encoder set it to 0 dB.
- Pan, plain values (PR #57, a quarter step away from the center): the R side matched TotalMix FX's window, the L side was one step off. A quarter step to the right of each whole step (PR #58): both sides match.
- A slow fade of a send from about −20 dB to off, on the ARC scale, sounded smooth.

**Consequences.** The layout's screen, reset, and scales stand as section 9 describes them, and the encoders stay in absolute mode.

### Test 12 (2026-11-01): asking for DAW mode while the device is already in it

**Setup.** This is not a separate test; it records what the logs of the evening's sessions show. `sbdev lcbridge` and the app were often stopped with Control-C, which leaves the device in DAW mode, since only a proper quit sends `9F 0C 00`. None of the five `lcbridge` logs ends with leaving DAW mode.

**Findings:**
- Three `lcbridge` sessions that followed one stopped with Control-C asked for DAW mode 3, 2, and 6 times, 3 s apart, with no echo (`lc3-arc.log`, `xl3-pan.log`, `xl3-pan2.log`). Each "answered" at 9.736, 6.167, and 18.371 s; in two of them a pan message to TotalMix FX followed 1 ms later, so the driver most likely took a moved control as presence (it did then). Two sessions were answered at once, at 0.03 s (`lc3-resolution.log`, `lcxl-sends.log`); what ran before them isn't recorded.
- The app was twice seen stuck on "Launch Control XL 3: Connecting", each time started after a host stopped with Control-C (`app-lc3.log`; the other launch kept no log), and connected at once after a proper quit (`app-lc4.log`, with `lc-daw-trace.log` showing the echo `9F 0C 7F` at 2.728 s).
- Leaving DAW mode, the device sent `B6 1E 06`, `B6 1F 06` (twice), then `9F 0C 00` (`lc-daw-trace.log`, at 86.767 s).

**Consequences.**
- Inference (confirmed by test 14): the device echoes the DAW mode note only when the mode changes, so a host asking a device already in DAW mode gets no answer. The driver therefore leaves DAW mode and enters it again when it starts (`startBytes`), which makes a change either way, and it takes only a control moved or pressed as a sign of presence, not the feature replies sent on the way out.

### Test 13 (2026-11-02): button shades and brightness

**Setup.** Adam's Launch Control XL 3, firmware 1.2. The app (commit `6914def`) with the buttons in
orange for mute and yellow for PFL, bright when on and the dimmest shade when off; then `sbdev lcxl`
with `color b11 9`, `rgb b12 127 40 0`, `color b13 13`, and `rgb b14 127 127 0`. Seen by Adam.

**Findings:**
- Index 11 shows as a dim orange, easily told from dark, and the dim orange and dim yellow rows are
  easily told apart.
- Mute and PFL lit and cleared as pressed. A mute took effect in TotalMix FX only with its Mute Master
  on (as in TOTALMIX-OSC.md, the global mute recheck of 2026-10-31).
- Bright and dim could use more contrast. Palette 9 looked the same as RGB 127, 40, 0, and palette 13
  the same as RGB 127, 127, 0, so the palette's bright shades are already at full brightness as far
  as the eye can tell.

**Consequences.**
- The palette's runs of four (bright to dim) hold for orange as for red and yellow; index 11 is
  orange's dimmest.
- More contrast can come only from the device's own LED brightness (its Settings page, 1–10, 8 by
  default, per Novation's user guide), which is the user's setting and left to the user.

### Test 14 (2026-11-02): asking for DAW mode twice

**Setup.** Adam's Launch Control XL 3, firmware 1.2, after the app had quit properly (leaving DAW
mode). `sbdev lcxl --raw`, which enters DAW mode as it starts; then `daw on`, `daw off`, `daw off`,
`daw on`, and `quit`, about 2 seconds apart. Log `lcxl-daw-echo-1102.log`.

**Findings:**
- On starting, `9F 0C 7F` was answered with `9F 0C 7F` 11 ms later.
- `daw on` while in DAW mode: no answer.
- `daw off`: `B6 1E 06`, `B6 1F 06`, `B6 1E 06`, `B6 1F 06`, then `9F 0C 00`, 11 ms later (Custom 1,
  as in test 12).
- `daw off` while out of DAW mode: no answer.
- `daw on`: `9F 0C 7F`, 12 ms later. `quit` (DAW mode off): the same answer as the first `daw off`.

**Consequence.** The device echoes the DAW mode note only when the mode changes, as test 12
inferred. So a host asking a device already in DAW mode gets no answer, and the driver's start,
leaving DAW mode and entering it again (`startBytes`), is what makes the device answer.

### Test 15 (2026-11-02): Mute Master, shades, and flashing

**Setup.** Adam's Launch Control XL 3 with the app (build 245), then `sbdev lcxl` (log
`lcxl-flash-1102.log`), and TotalMix FX's Mute Master (the M button in its Control Strip).

**Findings:**
- With Mute Master off, a mute pressed on the XL 3 lit index 10, the medium orange: barely brighter
  than index 11, and hard to tell from it or from index 9. Turning Mute Master on brought it to 9,
  and off again back to 10, as the app intended; the menu showed "Mute Master: Off".
- Track < and > pressed together went to the first page, and the device's Settings page did not
  open in DAW mode.
- Unplugged and plugged in again within about 2 seconds, the device was found again and drawn.
- Index 9 sent as a Control Change on channel 2 (`B1 25 09`) or channel 3 (`B2 25 09`) changed
  nothing (seen by Adam; the log kept holds only the second run, with channel 3, since the first run's
  was overwritten by it): no flashing or pulsing, which those channels produce on Novation's Launchpads. The programmer's guide describes
  only channel 1.[^prg-coloring]

**Consequences.**
- The medium shade is not used. A mute that is on while Mute Master is off flashes instead, drawn by
  the driver (`LaunchControlDriver.blinkPeriod`).
- In DAW mode, both Track buttons together are free for the app.

### Test 16 (2026-11-02): the Launch Control 3's layout, Function held

**Setup.** Adam's Launch Control XL 3 with the app and `--launch-control lc3-sim` (the Launch Control
3's layout, Mute/Select standing in for Function). Log `app-lc3sim-1102.log`. Seen by Adam.

**Findings.** All as intended: at rest Mute/Select was dim yellow and the top buttons dim orange
(mute); while it was held, it lit bright yellow, the buttons turned dim yellow (PFL), and the screen
showed "Buttons / PFL"; a button pressed then turned PFL on in TotalMix FX and lit bright yellow; on
release the buttons went back to mute and the screen showed "Buttons / Mute"; holding it again and
pressing the button turned the PFL off. No blue at start.

**Consequence.** Function held for PFL works in the driver; on a Launch Control 3 it also needs
Function to send its release (an inference, docs/LAUNCH-CONTROL-3.md).


### Test 17 (2026-11-02): colors and brightness for 1.0.1

**Setup.** Adam's Launch Control XL 3, firmware 1.2, LED brightness at its default. `sbdev lcxl` on
branch `v1.0.1` (log `lcxl-101-colors-1103.log`), with `color` and `rgb` commands on the encoders.
Seen by Adam.

**Findings:**
- Palette 37, 53, 45, and 49 showed as cyan, magenta, blue, and purple, all told apart, but cyan and
  blue looked "pretty similar". Teal (33) looked "quite different" from blue; green (21) looked
  different from all of them.
- RGB against palette, one above the other: 0, 127, 76 matched teal (33); 127, 0, 127 matched
  magenta (53); 0, 0, 127 matched blue (45); and 127, 127, 127 matched white (3), in hue and
  brightness. Purple (49) looked a little bluer than 42, 0, 127; 20, 0, 127 was closer, still
  slightly redder.
- Brightness steps by RGB (red): 127, 38, 10, and dark all looked different; so did white at 127,
  38, and 10.
- Eight reds in even steps of value (127 down to 5): the brighter ones looked nearly the same, with
  the big changes all at the dim end. On a 2.2 gamma curve (127, 94, 67, 45, 27, 15, 6, 2): still
  bunched at the top. Geometric (127, 70, 39, 21, 12, 7, 4, 2): the first two or three bunched,
  and the bottom changes were less distinct.
- From 127 down (127, 96, 80, 64, 48, 40, 32, 24), 64 was the first that looked clearly dimmer than
  127.
- Geometric from 80 to 6 (80, 55, 38, 26, 18, 13, 9, 6): "pretty close" to even; 80 looked a little
  dimmer than 127; 6 looked clearly lit, and brighter than 9.
- A palette color after an RGB color on the same encoder, and the reverse (`rgb` 38, 0, 0; `color`
  5; `rgb` 10, 0, 0; `color` 0): each showed the newest color, ending dark.

**Consequence.**
- The top send row's hue for white outputs is teal (33), not cyan (37).
- Purple's exact color is 16, 0, 127. This is an inference from 20 being slightly redder; 16 itself
  was not lit.
- Level by brightness dims continuously: brightness falls geometrically from full at the top of the
  travel to 9 at its bottom (Adam, 2026-11-02: "the act of adjusting the fader [should] cause a
  predictable outcome"). The floor was set at 9, because 6 looked brighter than 9; test 18
  lowered it to 5.
- Since values down to about 80 looked close to full, the top of the travel changes little:
  computed for the floor of 9, about the top 17% (above about +0.3 dB); with test 18's floor of
  5, about the top 14% (above about +1.3 dB). Not seen.
- The palette and RGB messages replace each other, so the driver can use either for any state.

### Test 18 (2026-11-02): the 1.0.1 build in the app, and two adjustments

**Setup.** Adam's Launch Control XL 3. The app from branch `v1.0.1` (commit `42888a3`; logs
`app-101-xl3-1102.log`, `app-101-xl3-relaunch-1102.log`, `app-101-lc3sim-1102.log`), then
`sbdev lcxl` (`lcxl-101-tune-1102.log`). TotalMix FX with ADAT 3/4 (white) on the top send row and
Phones 2 (yellow) on the middle. Seen by Adam.

**Findings:**
- **Send-row colors** (setting off). The top row (ADAT 3/4, white) showed teal, which Adam saw as
  cyan on its own. The middle row (Phones 2, yellow in TotalMix FX) showed "lime": yellow, but a
  little greener than the yellow buttons.
- **Show levels by brightness, turned on.** The send encoders dimmed at once to their levels, and
  the pan row stayed at full color.
- **Turning a send encoder by hand.** The light dimmed and brightened as the encoder turned, and
  this "feels predictable"; the dimmest level "could be dimmer".
- **Moving the send in TotalMix FX's window.** The light followed.
- **Shift + turn.** A send at about the middle went to −oo, dark. A second Shift + turn brought it
  back to −18.4 dB, lit at a medium brightness.
- **The setting off.** Full color again at once.
- **The setting on, then a relaunch.** It was remembered.
- **The Launch Control 3 layout on the XL 3** (`lc3-sim`). The level row dimmed with the level
  ("pretty much"; again, it could go dimmer), followed TotalMix FX's fader, and the top row
  dimmed as a send and stayed at full color as pan.
- **The dimmest value** (red, `sbdev lcxl`). 9, 7, and 5 each looked dimmer than the last; 4, 3,
  and 2 looked dark.
- **Yellow on the encoders.** Against a top button lit palette yellow (13), RGB 127, 85, 0 on an
  encoder matched best; palette 13 and 127, 100, 0 were greener.
- **Orange on the encoders.** Palette orange (9) matched the button's orange better than 127, 30, 0.
- Several `sbdev` commands pasted at once lost some of them; one at a time worked.
- **Two-part colors at their dimmest** (after the hue floor was added, `lcxl-101-hue-1102.log`):
  purple at 5, 0, 40 looked purple beside blue at 0, 0, 40 ("a bit close but distinguishable"), and
  orange at 16, 5, 0 looked orange beside red at 16, 0, 0 ("very different").

**Consequence.**
- The floor is 5.
- Encoders show yellow as 127, 85, 0, with the setting on or off; buttons keep palette 13.
- A color with two lit parts dims only until its smaller part reaches 5, which keeps purple and
  orange recognizable at their dimmest.
- Everything else in the 1.0.1 build behaved as section 9 describes.

### Test 19 (2026-11-02): dimmer off buttons

**Setup.** Adam's XL 3 with its LED brightness setting at 10, `sbdev lcxl`
(`lcxl-buttons-1102.log`). Seen by Adam.

**Yellow, top buttons 1–5:** palette 13 (PFL on), palette 15 (PFL off until now), then RGB 16, 11, 0;
10, 7, 0; and 7, 5, 0. Adam chose 16, 11, 0: the two dimmer ones were visible, highly so in the dark,
but their yellow came close to the white of the button's translucent part. After seeing orange,
Adam tried yellow one step dimmer (10, 7, 0) and went back to 16, 11, 0.

**Orange, bottom buttons 1–5:** palette 9 (mute on), palette 11 (mute off until now), then RGB 24, 8, 0;
16, 5, 0; and 12, 4, 0. Adam chose 12, 4, 0.

**Consequence.** A button that is off is drawn by exact RGB, yellow 16, 11, 0 and orange 12, 4, 0
(1.0.2). Not tried: other LED brightness settings.

### Test 20 (2026-11-10): a pan's center in TotalMix FX

**Setup.** Adam's XL 3 with the app (1.2.0, installed), its Launch Control XL 3 layout. Not logged;
seen by Adam. Asked after the Roto-Control's center stop showed L01 in TotalMix FX (`docs/ROTO-CONTROL.md`,
test 13), since 0–127 has no exact middle either.

- **Run 1: from the left.** Bottom 1 (the first channel's pan) turned a little left, then slowly
  right until the XL 3's screen showed C. TotalMix FX showed that pan as C (seen).
- **Run 2: from the right.** The same, turned a little right, then slowly left to C. TotalMix FX
  showed C (seen).

**Consequence.** No change. The XL 3 shows C only at 64 (`LaunchControlDriver.panSteps` maps 63 and 65
to L02 and R02), and TotalMix FX showed C there from both sides.

### Test 21 (2026-11-10): bitmaps

**Setup.** Adam's XL 3 in DAW mode, `sbdev lcxl` on branch `lc-bitmap-probe` (`bitmap` and
`bitmaprate`). Not logged beyond the Terminal lines Adam pasted; the screen seen by Adam.

- **Run 1: target 20h**, `bitmap 20 frame`, then with `7f` (7Fh F7h at the end): no change on the
  screen and no ready reply within 1 s, both times (seen).
- **Run 2: target 35h**, `bitmap 35 frame`: the screen showed a border, a filled block at the top
  left, and a diagonal from the top left toward the bottom right, as drawn (seen); the ready reply
  came after 67.5 ms.
- **Run 3: rate**, `bitmaprate 35 10`: 145 pictures in 10.1 s (14.4 a second), every one answered;
  reply times 65.9–71.9 ms, median 68.4 ms. The bars moved smoothly (seen).
- **Run 4: target 36h**, `bitmap 36 frame` over the last meter picture: the box picture replaced it
  and stayed up (seen); reply after 68.7 ms. Then `bitmap 35 clear` blanked the screen (seen).
- **Run 5: a control over a picture.** With `bitmap 35 frame` up, turning the bottom row's first
  encoder showed its temporary display ("Tonverk", "Pan", "C": text the app had set in an earlier
  session), and after a few seconds the box came back by itself (seen).
- **Run 6: a control during pictures**, `bitmaprate 35 10` while turning the same encoder (8 steps
  over 1.3 s, each with its touch reports): the temporary display stayed up over the moving bars
  for a few seconds, then the bars came back (seen; they had stopped because the run had ended).
  118 pictures in 10.0 s (11.8 a second), all answered; reply times 68.9–339.9 ms, median 71.6 ms.

**Consequences.** Meters can be drawn as pictures on the stationary display (35h) at up to about
14 a second, paced by the ready reply, without hiding a control's own temporary display. One reply
took 340 ms while the encoder moved (inference: the device was busy with the temporary display),
so a driver must wait for the reply rather than send on a timer. Not yet tried: whether 36h ever
differs from 35h; the Launch Control 3. (That the text home screen returns when the driver stops
sending pictures was seen in test 22.)

### Test 22 (2026-11-10): meters on the home screen

**Setup.** Adam's XL 3, `sbdev lcbridge --meters` on branch `lc-bitmap-probe` with TotalMix FX
playing, one build per run. Seen in Adam's videos and photo, and his words; no MIDI log.

- **Run 1:** a page line at the top in the E16's 5 × 7 font over meters 34 pixels tall. "That top
  line of text is too small to read, even with glasses" (Adam). The page line was dropped, the
  meters made the full 64 pixels, and the page put on Track's overlay.
- **Run 2:** two-pixel dB ticks between the strips (and one at each edge) at −6, −20, and −40 dB,
  and a peak line over each bar. The ticks read as a grid, 27 dashes with most strips silent, which
  bothered Adam "a bit"; he found the peaks a little busy too, or perhaps only the two together.
- **Run 3:** one-pixel ticks, no peaks. Adam: bring back the peaks; he doesn't love the grid; and
  it is hard to see where one stereo pair stops and the next starts (both gaps were 2 pixels).
- **Run 4:** no ticks; peaks back; a pair's bars one pixel apart and the strips five apart. The
  bars and peaks followed the music; turning controls showed their temporary displays over the
  meters ("Level −3.9 dB", "> Phones 2 −14.8 dB", "Pan L9"), and the meters came back afterward
  (seen in the video). Adam has not yet said whether this version is final.
- **Run 5:** `meters off`: the text home screen came back in place of the picture (photo). Its
  lines were "In 1-3, PB 1-3", "Top row > ADI-2 3." (cut off at the screen's right edge), and "Mid
  row > Phones 2" (the "2" cut off). The second and third lines started at the screen's left edge,
  the first was centered.
- **Run 6:** the build with "Top >" and "Mid >", without `--meters`: "In 1-3, PB 1-3", "Top >
  ADI-2 3/4", and "Mid > Phones 2", all three whole and centered (photo).
- **Run 7:** with the music stopped, two short lines stayed over strip 1's meter, at different
  heights near the bottom (photo), and TotalMix FX showed a small level on that input (Adam).
  Inference: these were the two sides' peak lines at the channel's noise floor, with the bars,
  6 dB lower, too short to draw. A peak line now shows only over a bar. Adam also asked for the
  channel numbers under the meters, with the playbacks' underlined, and declined dB marks at the
  screen's side.
- **Run 8:** the build with the numbers: "1 2 3 1 2 3" under the meters, the second three
  underlined, readable in Adam's photo (the record writer's reading); with the music quiet, strip 2 showed a short pair
  of bars with its peaks and strip 1 nothing, so no stray lines (Adam: "stray lines are gone").
  The underlines were hard to make out as such (Adam): one pixel, one row under the digits, they
  read as part of the number. A two-pixel line two rows below, one under each run of playbacks,
  replaced them (Adam chose it from a mockup).
- **Run 9:** that build: "1 2 3 1 2 3" with one line under the second three, clear in Adam's
  photo (the record writer's reading). Adam then asked to try the line above the numbers, a little farther from the bars: now
  three dark rows below the meters, the line, two dark rows, and the numbers. He also asked that a page
  with fewer than eight strips be centered on the screen.
- **Run 10** (asked before that build was tried on the device): Adam asked for the line back under
  the numbers, with the screen's bottom row kept dark, since at an angle it is hard to read. Now:
  the meters, two dark rows, the numbers, two dark rows, the line (two rows), and the dark bottom
  row.
- **Run 11:** that build: six strips centered on the screen, "1 2 3 1 2 3" with the line under
  the second three, clear of the bottom row (Adam's photo). Adam then asked for one more dark row
  above the numbers: the meters are now 45 pixels, with three dark rows under them.
- **Run 12** (asked before that build was tried): Adam asked for an indicator at 0 dBFS and chose
  both a fixed mark and a clip light: a hollow box three rows tall over each bar, filled for 2 s
  after that side reaches 0 dBFS, a dark row, then the meters, 41 pixels.
- **Run 13:** that build. Adam couldn't get a signal to 0 dBFS, and the boxes were too small to see
  as boxes ("they need to be quite a bit taller and maybe a bit wider"). They are now five rows
  tall and a pixel wider than the bar on its outer side, the meters 39 pixels, and he asked for a
  one-pixel 0 dB mark at each side of the screen. `clip N` in `sbdev lcbridge` made strip N reach
  0 dBFS once, and a clip counted every message at 0 dBFS, even one that a lower level replaced
  before the next picture (`MixerMirror.overs`); both were removed with the clip boxes in run 15.
- **Run 14:** the edge marks need to be more than one pixel wide, and possibly two tall (Adam).
  They are now 2 × 2, on the meters' top two rows; wider would touch the outer strips' bars on a
  full page.
  Adam asked for room above 0 dBFS, up to +6, then withdrew it, since the meters show only
  inputs and playbacks, whose levels are inferred to stop at 0 dBFS (an input's converter, a
  playback's audio); the top of the meters stays 0 dBFS.
- **Run 15** (asked before the 2 × 2 build was tried): Adam asked for wider 0 dBFS marks, and
  disliked the clip boxes ("they look like tiny glyphs rather than boxes"), asking whether the
  inputs' clipping is even reported reliably. Nothing in the record shows it is: TotalMix FX sends
  peak levels in dB, only when they change, and no test has seen a level at 0 dBFS. The clip boxes
  were dropped (meters 45 pixels again), and the gap between strips went from five pixels to
  four, centering the eight strips with six dark pixels at each side, so the marks are 4 × 2 with
  two dark pixels before the bars.
- **Run 16** (asked before that build was tried): Adam suggested a finely dotted line on each
  meter at 0 dBFS instead of the side marks: every other pixel of the top row over each bar. With
  the side marks gone, the strips went back to five pixels apart (Adam).
- **Run 17:** that build: a dotted line at the top over each of the six strips, the meters, "1 2 3
  1 2 3", and the line under the playbacks (Adam's photo).
  The line under the playbacks then went from two pixels to one (Adam asked for a recommendation:
  the two-pixel line was the heaviest mark on the screen; he agreed to one; not yet seen on the
  device).
  Adam then asked for the 0 dBFS line "even more gray": the screen has one bit per pixel, so its
  dots went from every other pixel to one in three, on one grid across the screen, which "looks
  weirdly mottled" (Adam): the dots fell differently on each bar. Back to every other pixel from
  each bar's left end, which is even and symmetric on a 5- or 11-pixel bar.

**Screen size** (measured 2026-11-11). The makers' top-view photos (`controller-*.png`, 316 pixels
tall), scaled by the published sizes (XL 3 250 × 239 mm;[^nov-xl3-page] E16 114 × 142 mm[^thomann-e16]), give the XL 3's screen window as about 28 × 17 mm and the E16's as about 51 × 24 mm, with
the E16's blank panel visible inside it at about 35.3 × 17.5 mm. In run 17's photo, the dotted
0 dBFS lines (91 screen pixels) put the XL 3's 128 pixels at about 75% of its window: about 21 mm
wide. So the pixel pitch is about 0.16–0.17 mm on the XL 3 and 0.27 mm on the E16, about 1.6 times
as large on the E16 in each direction. Both match common 0.96-inch and 1.54-inch 128 × 64 OLED panels
(an inference; neither maker names its panel). At about ±1 photo pixel, the figures are good to
about ±0.5 mm (E16) and ±0.75 mm (XL 3, from a slightly angled photo). This is why the E16's 5 × 7
font reads and the same font didn't on the XL 3 (run 1): about 1.9 mm against 1.2 mm.
Adam's playing distances (2026-11-11, tape measure, eye to screen): the XL 3 about 24–25 in (about
620 mm), the E16 about 27 in (about 690 mm). In visual angle, the E16's names are about 9.4 arcmin,
the XL 3's 5 × 7 text about 6.4 (unreadable, run 1), and the meter numbers' 11-pixel digits about 9.9
(computed; readable in runs 8–17).

**Consequences.** The meter layout is run 17's, with the line under the playbacks one pixel thick
(not yet seen on the device) and the 0 dBFS line every other pixel. A review of the same day
(Tier 1) found that the averages and peaks were updated only when a picture could go out, so a
peak between two pictures was lost; they now follow every tick. Measured in the photo (about 11.8 of
its pixels to one of the screen's, from the cut-off edge and the centered first line; an
inference), capitals and digits take about 9 screen pixels with their gap, most lowercase letters
nearly as many, "i" about 4, and a space about 3 (about 5, measured better in test 24); "Mid row >
Phones 2" needs about 129 of the 128.
The send rows' lines are "Top >" and "Mid >" again, since with "row" most outputs' names don't fit,
and the driver estimates the first line's width from these figures (`LaunchControlDriver.screenWidth`)
to decide between "Page 1/2: " and "1/2: ".

### Test 23 (2026-11-10): Display Timeout

**Setup.** Adam's XL 3 with `sbdev lcbridge --meters`. Novation's Settings page lists a **Display
Timeout** setting, 1–10, default 3, for how long temporary messages stay on the screen, without
units; the Settings page opens from a Custom Mode by holding both Track buttons, Page ▲▼ step
through the settings, and the top-left encoder changes one; Mode leaves.[^nov-settings] A Custom
Mode is chosen with Mode, one of the 16 buttons lit blue, and Mode again.[^nov-custom]

**Findings** (seen):
- Mode, a blue button, and Mode put the device in a Custom Mode (the screen named a new custom
  mode); both Track buttons then opened the Settings page at "Global MIDI Channel 9"; Display
  Timeout read 5 (not the default 3) and was turned down to 2; Mode left the Settings page with the
  screen blank (the device still in the Custom Mode, which the driver doesn't draw).
- Quitting and starting `sbdev lcbridge --meters` again put the device back in DAW mode with the
  meters.
- At 2, the pop-up after turning an encoder goes away soon enough ("yeah think so at 2", Adam);
  he then judged 1 or 2 both good, and the setting's number to be seconds ("yeah, it's seconds",
  by eye).

**Consequences.** The setting applies to the temporary displays in DAW mode, so the driver needs no
timer of its own. The Controls Guide says where the setting is. Whether Mode and a button can go
back to DAW mode without restarting the host was not tried, so the guide says to quit and reopen
(seen with `sbdev lcbridge`; the app starts the device the same way, `LaunchControlDriver.start`,
an inference).
The Launch Control 3 has a Settings page too; whether it has the same setting was not checked.

### Test 24 (2026-11-11): numbering the meters

**Setup.** Adam's XL 3 with `sbdev lcbridge --meters` and TotalMix FX, three inputs and three
playbacks shown, all on page 1 at first, then with `pbpage on` (the playbacks on page 2). The
question, from the UI review of 2026-11-10: which numbering under the meters lets him tell
fastest which fader a moving meter is over. Playing distance measured first: the XL 3 about 24–25 in, the E16 about 27 in (eye to screen, tape measure).

**Findings** (Adam's words where quoted):
- The digits themselves: "very easy to read" (run 17's 11-pixel digits).
- Six strips centered on the screen: mapping a meter to its fader took "a few seconds, since I had
  to remember that only 6 channels are showing on the screen instead of 8." The page then kept
  eight fixed slots with a dot on the top row of each empty one: "still somewhat slow: it's hard to
  tell at a glance how many channels are to the left of the moving bars", since the dots are on the
  top row, far from the bottom, where most of the motion is.
- `numbers page` (1–8 by slot): "definitely faster."
- `numbers kind` (1 2 3, then 1 2 3 for the playbacks): "a little slower than 1-8, because I had to
  orient to the count restarting and there's nothing obvious causing the restarted numbering
  (playback vs input is not obvious, and i didnt remember the meaning of the bar for a second)."
- `numbers all` with the playbacks on page 2 (4, 5, 6 there): "the playback 1/2 starting with 4 is a
  bit confusing, since I expect it to be the first such channel."
- `numbers page` on page 2 (1, 2, 3): "Seeing 1 as the first channel makes sense."
- Track's pop-up (the page and the channels counted by kind): "isn't very useful at all; it's not an 'overlay,' for one
  thing--it's a screen that pops up and PB1-3 doesn't correspond to any channel numbers in TMFX."
  Asked what it should show, he chose the page and the first and last channels' names, and to keep
  the playbacks' line for now. He added that the mixed-case "In" of the counts could be read as
  "ln".

- The pop-up then showed "Page 2/2", the first channel's name, and "to" and the last's: better, but
  "the 'to' is a little hard to make sense of within the 1 second the screen shows." He chose each
  name with its slot ("1 Vox", "3 Gtr") and asked for the first line left-aligned and the second
  right-aligned.

**Consequences.** The meters are numbered 1–8 by slot on every page; the
other numberings, the peak floor, and the bar fall were then removed (`sbdev lcbridge` keeps
`peakfall`). Track's pop-up shows the page, then
the first and last channels with their slots. The device centers each line, and the display
arrangements this project uses (section 5) choose lines, not alignment, so the driver pushes the
first channel left with trailing spaces and puts "to" at the left of the last line with the channel
pushed right (`LaunchControlDriver.pushed`, `spread`), as far as the field's 20 characters and an
estimated 118 of the screen's 128 pixels allow (runs 2–6 below). The text home
screen's first line names the same two channels ("1/2: Vox to Gtr"), where there is more time to
read, and falls back to the page alone when they don't fit.

Run 2 (photos): Track's pop-up read "Page 1/2", "1 Tonverk" at the screen's left edge, and "3 ADAT
5/" at its right, the "6" lost; on page 2, "Page 2/2", "1 PB 1/2" at the left, and "3 PB 5/6" at
the right with part of its "6" cut off (Adam). So the firmware keeps leading and trailing spaces, and a line wider than the screen
starts at the left edge and loses its end (with ten spaces in front of "3 ADAT 5/6", and twelve in
front of "3 PB 5/6"). Measured
in the photos, the first character of the right line sits twelve spaces (page 2) or ten (page 1)
after the left line's, about 16.6 and 15.5 photo pixels a space, at about 3.25 photo pixels to a
screen pixel (from the meter picture's known slot spacing, 16 pixels): a space is about 5 pixels,
not test 22's 3. The width estimate now counts 5 for a space, and a pushed line keeps about 6 pixels
to spare (an estimated 120 of the 128), since both lines came out wider than estimated: "3 ADAT
5/6" by about 7 pixels, "3 PB 5/6" by about 10 (measured about 72 against 62). With these, "3 ADAT 5/6" gets eight spaces in front and
"3 PB 5/6" eleven. The meter picture on page 2 showed 1 2 3 with the playbacks' line under all three.

Run 3: with those spaces, both right lines fit ("yes it fits", Adam). He asked for "Page 1 of 2" in
place of "Page 1/2": it fits and is faster to take in. The pop-up's first line, and the home
screen's when it shows the page alone, now read that way; the home screen's "Page 1/2: " or "1/2: "
in front of the names stays, since "of" would leave too little room for them. Not yet seen on the
device.

Run 4: "Page 2 of 2" reads well. Adam then suggested "Pb" for an unlabeled playback, which "may
actually be easier to understand/remember than PB", and "to" at the far left of the last line now
that it is pushed right. Both made: unlabeled playbacks are "Pb 1/2" on every hardware controller
(the E16 draws them in capitals, its font having no lowercase), and the last line reads "to", spaces,
then the channel ("to      3 Gtr", `LaunchControlDriver.spread`).

Run 5 (photo, page 1 of 1, all six channels on one page): "Page 1 of 1", "1 Tonverk" at the left, and
"to" at the left with "6 Pb 5/6" at the right, part of its last "6" cut off (Adam). "to" starts at
the screen's left edge and "1" about 3 pixels right of it (measured): the last line was again wider
than the screen, so it started at the edge, while the second, narrower, was centered. Measured in
the photo (about 3.77 photo pixels to a screen pixel, from the left edge to the cut-off end): "Page 1
of 1" about 76 screen pixels wide, against an estimated 84, and "6 Pb 5/6" at least 71, against an
estimated 62; the eight spaces about 41, 5 each, as in run 2. So the estimate now counts digits as
about 10.5 pixels and "1" as 8 (test 22's 9 for every digit was too small for 6 and too large for
1), and a pushed line keeps about 10 pixels to spare (an estimated 118 of the 128). Most lowercase
letters measured narrower than the estimate's 8.75 (about 7.5), and strings of capitals and digits
still about 5 pixels wider than estimated, so the margin, more than the calibration, keeps a padded
line on the screen (a review of 2026-11-11, from the same photos). The last line now
gets seven spaces. Run 6 (photo): "6 Pb 5/6" whole, a few pixels from the right edge, and "to" and
"1 Tonverk" starting at about the same place.

Peaks (videos, `peaks bar` and `peaks floor`, quiet material on channel 1): the review's suggestion
that a held peak also show alone above −40 dBFS after its bar has emptied. Adam "couldn't tell the
difference"; in the frames the bars reach only a few pixels, so the case it covers (a loud hit, then
silence) hardly came up. The default stayed: a held peak only over a bar (until the peak fall
below, which shows a falling peak down to an empty bar).

Fall (`fall 12`, `fall 20`, against TotalMix FX's own meters): "fall 12 is not good. the peaks just
disappear rather than dropping like TMFX. 20 was harder to tell" (Adam). An inference from the
code: with the bar falling slowly, it stays above the held peak once the 2 s hold ends, so the peak
line vanishes into the bar. The default stays: the bar follows the averaged level.

Peak fall (`peakfall 20` and `peakfall 40`): since TotalMix FX's peaks drop where these vanished, a
held peak now falls after its 2 s hold, shown down to an empty bar. "either 20 or 40 was right", "20
maybe closer", "but it's also hard to see the difference" (Adam). 20 dB a second is the default.

Adam also saw "1 Tonverk" not quite at the left edge (run 5: its "1" starts about 3 screen pixels
right of "to", measured). A line is centered unless it is wider than the screen. "1 Tonverk" with
its 9 spaces (estimated 118 pixels; about 119 from its measured width) sits about 4 pixels in from
each side, while the overfull last line started at the edge. In run 6 both lines are centered and
start within about a pixel of each other. A shorter name sits a little further in ("1 Vox" with 15
spaces, an estimated 114.5 pixels, about 7 in): an inference from the estimate, since no wider
blank character is known to push it further.

Adam then flagged two questions for a UI review rather than settling them: whether the slot number
needs a separator after it ("1: Tonverk", "1 – Tonverk", or "1 — Tonverk"; a hyphen if the font
has neither dash, which is "likely fine"), and "Pb" against "PB" for an unlabeled playback ("not
sure").

