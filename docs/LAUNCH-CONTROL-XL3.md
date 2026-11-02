# The Launch Control XL 3: what Performance Bridge relies on

This is the authority, for this project, on Novation's Launch Control XL 3 in DAW mode, as
`TOTALMIX-OSC.md` is for TotalMix FX and `ROTO-CONTROL.md` for the Roto-Control. Every statement
carries its evidence.

**Status (2026-11-01).** Tested on the device on 2026-11-01 (firmware 1.2): every test the driver
needs is done (section 8), and the records are in section 10. Where a record differs from what
sections 2–7 take from Novation's documents, the record rules. The `LaunchControl` library (which also covers the Launch
Control 3, `LAUNCH-CONTROL-3.md`), `sbdev lcxl`, and the driver (`LaunchControlDriver`, section 9)
are built on them.

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
- **Seen on macOS** (Adam's Mac, firmware 1.2, 2026-11-01): CoreMIDI lists the sources "LCXL3 1
  MIDI Out" and "LCXL3 1 DAW Out", and the destinations "LCXL3 1 MIDI In", "LCXL3 1 DAW In",
  "LCXL3 1 To DIN Out", and "LCXL3 1 To DIN Out 2". So "LCXL3 1 DAW" picks the DAW pair.
- In DAW mode the DIN outputs send nothing. [Programmer's reference guide, "DAW mode"]

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
  sends it. [Programmer's reference guide, "Absolute and relative encoder modes"] The guide doesn't say in which message; the encoder's own Control
  Change back on channel 16 works (test 2).
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
  (page 12). Index 0 is off and 5 is red (test 4); indices 0–39 have been seen to match the picture's
  run of colors, as far as a photo can show.
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
   Studio chapters. Twice, in the DAW Control tips, it says the reverse. Test 6: Mode plus
   Solo/Arm shows "DAW Control" on the screen, so the six are right; but the device doesn't
   switch by itself (test 6).
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

1. **Ports.** Done (test 1). The macOS names of the DAW ports. Does `--port "LCXL3 1 DAW"` connect?
2. **DAW mode.** Does the device show DAW mode on entering, and return to standalone on `quit`? With firmware 1.2's "DAW Connection" set to Switch (the default), does entering DAW mode move it to DAW Mixer? With "Connect Only", does it stay in its Custom Mode, and does `mode mixer` then move it?
3. **The control map.** Done (test 1). Move every control and check its name and value against section 4,
   including Track < and > (103, 102) and the Novation button. What do buttons send: 127 and 0?
4. **Modes.** Done (test 6). Mode plus Mute/Select, then plus Solo/Arm: which reports 1 and which 2 (section 7,
   item 3)? Does `mode control` switch the device?
5. **Touch.** Done (test 1): movement, not a sensor. With `touch on`: touch a fader and an encoder without moving them, then move each
   with Shift held. Which sends channel 15 reports?
6. **Encoder position.** Done (test 2): taken. `pos e11 0`, then turn the encoder one step: does it continue from 0
   (taken) or from where it was (not)? The same with `pos e11 127`.
7. **Fader pickup.** Done (tests 2 and 3): the device's pickup works; one unexplained run in test 2. `pickup on`, `pos f1 64`, then move fader 1 from the bottom. Does it send
   nothing until it passes the middle?
8. **Relative encoders.** Done (test 2): as the guide says. `relative 1 on`: do encoders 1–8 report 77–84 with 65 and 63 for single
   steps?
9. **Colors.** Done (test 4) for indices 0–39 and RGB; 40–127 not yet seen. `palette 0`, `palette 40`, and `palette 80`. Compare with the guide's palette. Is 0
   off? Then `rgb b11 127 0 0`, and check the Track, Page, Record, Play, and Novation buttons for
   lights.
10. **Screen.** Done (test 5). `display f1 2`, then `text f1 0 Mix`, `text f1 1 ADI-2`, `text f1 2 -6.0 dB`, and
    move fader 1. How many characters fit per field? Then `display stationary 3` with eight names,
    and the `quiet` option (no display on change).
11. **Bitmap targets** (section 7, item 5), only if a bitmap is wanted later.

## 9. How Performance Bridge uses it

Decided with Adam, 2026-11-01, after the tests; built in `LaunchControlDriver`, not yet in the app.
The layout gets a close look in the Tier 1 UI review and Adam's own (Adam asked for its efficiency
and intuitiveness to be assessed).

- **Eight strips.** Each fader is its strip's level: into the mix output (the home submix) for a
  source, or the output's own level in the outputs view.
- **Fader pickup.** The driver turns on the device's pickup (feature 70) and sends each fader's
  level as a position, so the device holds a fader back until it reaches TotalMix's level and
  shows the target meanwhile (test 3). SurfaceCore's own pickup stays on behind it, with a window
  of 12 steps for the first value after the device lets go, in case the device doesn't hold (as in
  one run of test 2).
- **Fader scale.** The nine ticks printed beside each fader read, top to bottom, +6, +3, 0, −6,
  −10, −20, −40, −60, and off: TotalMix FX's own fader marks (`TOTALMIX-OSC.md`, test 18), placed
  at the fader values measured at each tick (test 7). Between ticks the gain moves evenly in dB
  (Adam, 2026-11-01). The encoders keep TotalMix's own fader curve: they have no printed scale.
- **Encoder rows.** Each row is Pan or Send, set in the app (default Pan, Send, Send). Send rows
  take consecutive send targets (control room outputs first), and Track < and > step them
  together. Gain is left out for now: TotalMix sends it only for inputs with a preamp, which the
  project's interfaces don't have. The encoders take positions from the driver (test 2), so they
  never jump.
- **Buttons.** The top row is PFL (yellow; dark yellow when off), as on the Roto-Control; the bottom
  row is mute (red; dark red when off). Solo/Arm and Mute/Select do nothing for now: in DAW mode
  the device leaves them to the host (test 6).
- **Paging and views.** Page up and down move by eight strips; Shift with Page up shows the sources,
  and with Page down the outputs. Page and Track are lit where they would move.
- **Colors.** Encoders show their strip's TotalMix color from the palette (an output left white:
  green for monitoring, blue for sends, as on the Roto-Control); a blank strip is dark. Blue (45)
  and purple (49) are past the part of the palette seen in test 4 (inference from the guide's
  picture).
- **Screen.** Each fader and encoder has a three-line display (arrangement 2): the channel's name,
  what the control does ("Level", "Pan", "> Phones 1"), and the value in dB or as a pan, sent by
  the driver (test 5). The stationary display (arrangement 3) shows the view and the strips on the
  page as its title, and the eight names, packed to four characters so that the columns stay apart
  (e.g., "Mic1"). Track shows the new send on the overlay; that the overlay comes up as other
  displays do is untested.
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
- **Encoders** are smooth, with no detents. In absolute mode, values step by 1 when turned slowly. Faster turns skip values (1 → 3, 1 → 5 → 7), so the device accelerates (inference: the "Encoder Curve" feature, section 6). At 0, turning anticlockwise sends no value.
- **"Touch" is movement, not a touch sensor.** With touch reports on, a fader or encoder sends touch on (channel 15, 127) just before its first value and touch off (0) about 80 ms (encoders) to 120–150 ms (faders) after its last. Turning an encoder at 0 anticlockwise sent touch on and off with no value between. Touching without moving wasn't tried; the inference is that it sends nothing.
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

**Consequences.** The library's control map, button values, and Shift are right. Its touch reports are really movement reports: SurfaceCore can't use them as a hand resting on a control, only as a sign of movement, which its holds already take from the values. The library should read the DAW mode echo (`9F 0C`), and CC 31, as their own events (inference: harmless either way).

### Test 2 (2026-11-01): encoder positions, relative mode, and fader pickup

**Setup.** As test 1. `sbdev lcxl`; logs from Adam.

**Findings:**
- **Encoder positions.** After `pos e11 100` (`BF 0D 64`: the encoder's own Control Change on channel 16), turning the top-left encoder clockwise reported 101, 102, … 107. The screen showed the same. So an absolute encoder takes the position the host sends it in this message, which the guide didn't name (section 4).
- **A change of direction.** The first move after turning the other way sent touch on and off with no value, in both absolute and relative mode (seen three times). The device seems to drop the first step after reversing.
- **Relative mode.** After `relative 1 on`, the top-left encoder sent Control Change 77 (`4D`) on channel 16, with 65 clockwise and 63 anticlockwise, one step at a time when turned slowly. Its touch reports used 77 too (`BE 4D 7F` and `00`), not 13. The library now reads both.
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
- That suits the driver better than SurfaceCore's own pickup, since the user sees the target. The driver can turn feature 70 on and send each fader's position, and give SurfaceCore a fader that "follows" (inference, to settle when the driver is written).
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
- The driver can use palette indices for the strips' colors and RGB where a palette color is too far off, e.g., to match TotalMix's eight colors.
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
- Custom Modes chosen on the device do switch it, and are reported (test 1).

### Test 7 (2026-11-01): the fader values at the printed ticks

**Setup.** `sbdev lcxl`. Adam pushed fader 1 to the top, then brought it down, stopping with the white line on its cap level with each of the nine ticks printed beside it; log kept. He wasn't highly confident of hitting each tick exactly. With the fader all the way up the line is level with the top tick, and all the way down with the bottom tick (seen).

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

**Consequences.** The driver takes the ticks at 127, 120, 102, 84, 66, 46, 29, 11, and 0 (`LaunchControlDriver.faderTicks`), so each lands on its label whatever the fader does between them.
