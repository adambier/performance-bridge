# OXI E16: what this project relies on

This is a working reference for the parts of OXI Instruments' E16 that Performance Bridge uses: its
Remote Mode, in which a host draws the screen and the encoder rings and receives the encoders'
turns and pushes, on the factory firmware. It is written in this project's own words, with the
evidence for each statement; it is not a copy of OXI's documentation. The `OXIE16` library
implements the protocol and `E16Driver` the layout.

**Sources.** OXI publishes the Remote Mode as a Google Sheet, "E16 REMOTE CONTROL", linked from the
firmware 1.2.0 release notes (the "sheet"), and describes it in the manual.[^sheet] [^manual]
The firmware's source is open (github.com/OXI-Instruments) but is not used here: this project
works with the factory firmware only (Adam, 2026-11-04). Nothing from OXI's documents or code is
copied here.

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote saying where it comes from: the sheet, the manual, or a test against an
E16, described in section [6](#6-tests) with the firmware version. Where something is reasoning
that has not been checked, the text says so in words ("inference", "untested").

[^sheet]: OXI Instruments' "E16 REMOTE CONTROL" Google Sheet (gid 1057524829), linked from the E16
    1.2.0 release notes, read 2026-11-04.
[^manual]: OXI Instruments' "OXI E16" manual, version 1.1.0a (Adam's copy; the 1.3.0a edition
    describes Remote Mode on p. 87), read 2026-11-04.
[^release-notes]: OXI Instruments' E16 firmware release notes: 1.2.0 (Remote Mode announced) and
    1.3.0 (Remote Mode "restored"; 1.2 had broken it), read 2026-11-04.
[^test-1]: [Test 1](#test-1-2026-11-04-the-probe) (2026-11-04), section 6; firmware 1.3.0.
[^test-2]: [Test 2](#test-2-2026-11-04-the-driver-with-totalmix-fx-through-sbdev-e16bridge)
    (2026-11-04), section 6; firmware 1.3.0.
[^test-3]: [Test 3](#test-3-2026-11-04-the-app) (2026-11-04), section 6; firmware 1.3.0.

**Status.** Three tests so far (section 6), all on Adam's E16 with firmware 1.3.0. Section 5 lists
what is still open.

## 1. The device

Sixteen push encoders in four rows of four, each with a ring of 16 RGB LEDs; a 128×64 one-bit OLED
screen above them; a Shift button; USB-C and Bluetooth MIDI.[^manual] Over USB, with USB Multi
Port on (the default), it has three MIDI ports, "OXI E16 Port 1", "Port 2", and "Port 3", as
sources and destinations; Remote Mode is on Port 1.[^sheet] [^test-1] The encoders are not
detented.[^test-1]

Remote Mode needs firmware 1.3.0 or later: 1.2 announced it and broke it, 1.3.0 restored
it.[^release-notes] The firmware tested is SW 1.3.0, HW v5, BLE 1.0.5.[^test-1]

## 2. SysEx framing

Every host message is `F0 00 21 5B 02 01`, a two-byte message ID, a payload, and `F7`.[^sheet] The
payload is packed 8-to-7: for each group of up to seven raw bytes, one byte carrying their high
bits (bit 0 for the first byte of the group) and then the seven bytes with their high bits
cleared.[^sheet] The known example (`FF 00 80 7F 01 FE 55 AA` → `25 7F 00 00 7F 01 7E 55 01 2A`)
is a test in `OXIE16Tests`.

| Message | ID | Payload |
|---|---|---|
| ENTER REMOTE MODE | `06 55` | none; the device answers with `06 53` (the ACK) |
| EXIT REMOTE MODE | `06 00` | none |
| LED RING | `06 04` | per ring, 7 bytes: encoder 0–15, R, G, B (each 0–127), amount MSB and LSB (14-bit, 0–16383), bipolar flag |
| LED (single) | `06 01` | per LED: encoder, LED 0–15, R, G, B |
| OLED LABELS | `06 03` | 80 bytes: a 16-character title, then 16 labels of 4 characters |
| OLED FRAMEBUFFER | `06 02` | 1024 bytes: 8 pages of 128 bytes, each byte a column of 8 pixels, the top pixel in bit 0 (the SSD1306 page layout) |
| OLED SCANLINE, RECTANGLE, CLEAR | `06 05`, `06 08`, `06 07` | partial draws (not used; the sheet says the device answers `53` or `54`) |

What the device sends, all on MIDI channel 1:[^sheet] [^test-1]

- a turn: CC 1–16 (encoder 1–16), value `01`–`08` clockwise and `7F`–`78` counter-clockwise, the
  magnitude growing with speed (the device's own acceleration: +1 per message when slow, up to
  +8 when fast, a message every 4–5 ms);
- a push: note 0–15 on (press) and off (release);
- Shift: note 16 on and off;
- the ACK, `F0 00 21 5B 02 01 06 53 F7`, after ENTER.

## 3. What the device does with them

- **ENTER** is answered within about 42 ms; the screen and every ring go dark until the host draws
  them.[^test-1] **EXIT** brings the device's own screen and rings back at once.[^test-1] A host
  that quits without EXIT leaves the device blank until an EXIT or a power cycle (reported in
  OXI's community; not tried here), so the driver's `stop` always sends EXIT.
- **LED RING** fills a ring clockwise from the bottom (six o'clock), in sixteenths, with the LED at
  the boundary dimmed in proportion rather than on or off; the color is per ring.[^test-1] The
  LEDs are bright already at small values: 3 or 4 of 127 is clearly lit, 2 reads dim, and 1 is
  barely there; the steps above about 64 are hard to tell apart.[^test-2] Below about 15% of the
  driver's brightness, orange and yellow can't be told apart.[^test-3] Sixteen rings at 60 frames
  per second drew smoothly (180 frames in 3057 ms, 58.9 fps, nothing dropped).[^test-1]
- **LED (single)** is a persistent override: an LED set this way keeps its color through later
  LED RING messages for that ring, and the encoder's label on the screen draws inverted, until a
  power cycle.[^test-2] The driver never uses it.
- **OLED LABELS** draws the title on the top line and the labels in the 4×4 layout of the
  encoders. The title is centered by the firmware and only 15 of its 16 characters are shown;
  padding a title with spaces moves it off center, padding with nulls doesn't.[^test-2]
- **OLED FRAMEBUFFER** replaces the whole screen; the page layout above (bit 0 at the top) was
  confirmed by a readable title.[^test-2] A screen drawn this way and one drawn with LABELS
  replace each other.

## 4. The layout Performance Bridge uses

Decided with Adam on 2026-11-04, in tests 2 and 3. Sixteen strips a page, always the sources.

- **Turn**: the strip's level in the home submix, its pan, or its send to one output, by the mode.
  The device's 1–8 steps are scaled by `E16Driver.levelStep` (0.0025 of the fader's travel per
  step) and `panStep`.
- **Push and release** (under 1 s): mute, on release. **Hold** 1 s: PFL, with a countdown arc after
  a 0.25 s tap window; the title says "NAME -> PFL" while the countdown runs and "NAME PFL ON" (or
  OFF) while the encoder stays held.
- **Shift** makes the encoders buttons, as the E16's own firmware does: 1 LEVEL (white), 2 PAN
  (magenta), 3 SEND (deep green; back to the last output used), 11 and 12 the previous and next
  send output (deep green; either enters SEND mode), 15 and 16 the previous and next page (blue).
  While Shift is held the screen names them (blank where an arrow goes nowhere) and the rings
  show them at four levels: off (nothing there or nowhere to go), 2 (available), the driver's
  brightness (in use), 127 (pressed).
- **Rings**, from the UI review of 2026-11-04: the strip's TotalMix FX color filled to its level
  (bipolar for a pan); dark means no strip (a strip always lights at least one LED); a complete
  ring means a switch is on (a level never fills the last LED); mute is a steady orange ring,
  blinking between full and half while TotalMix FX's Mute Master is off; PFL is a heartbeat (0.8 s
  of yellow-green, a 0.2 s dip to what is underneath).
- **Colors.** TotalMix FX's channel colors are mapped so they stay apart on these LEDs: grey is
  shown as cyan (0, 110, 127), the hue TotalMix FX leaves free, since a dim grey read as a dim
  white or a level; orange (127, 16, 0), red (127, 0, 0), blue (0, 0, 127), green (0, 105, 0),
  yellow (127, 72, 0), purple (70, 0, 127); mute is the orange; PFL (110, 127, 18). All of it
  scaled by a brightness setting (default 55%, no lower than 15%) that starts from a floor of 4
  per lit part, so colors keep their hue when dim. To be tuned by side-by-side comparison after
  1.1.0 (Adam, 2026-11-04).
- **Screen.** Drawn by the host (FRAMEBUFFER) with a 5×7 proportional font of the project's own,
  after 3×5 and 4×6 were too small to read: the title (the mode, or an overlay) at the left and
  "PFL" and the page at the right, a rule, and the sixteen labels in four rows 14 pixels apart,
  each at the left of its 32-pixel cell and no wider than 26 pixels. A stereo pair always shows
  both numbers, losing its word first ("ADAT3/4", "ADT3/4", "AD3/4", "3/4"; "P15/16", "15/16");
  "P1/2" is the four-character form for the firmware's LABELS layout, kept as a fallback.

## 5. Open questions

- Bluetooth MIDI, and USB Multi Port off (one port): untested.
- The partial OLED messages (scanline, rectangle, clear) and the bipolar flag's exact drawing:
  untested; the driver uses FRAMEBUFFER and sends bipolar rings for pans, which looked right.
- Whether the LED override from a single-LED message can be cleared by anything short of a power
  cycle: EXIT and ENTER didn't (test 2).
- The acceleration curve: the device's own 1–8 steps times a fixed step; no curve of the driver's
  own yet.
- A 4-channel "strip" layout (four channels across, LEVEL on the fourth row, rows 1–3 each
  assignable to PAN or one send): an idea for after 1.1.0 (Adam, 2026-11-04).

## 6. Tests

Run with `sbdev e16` (the probe: `ports`, `monitor`, `enter`, `exit`, `labels`, `ramp`, `palette`,
`demo`) and `sbdev e16bridge` (the driver with TotalMix FX, as the app runs it), on macOS. Both
print what they send and receive with the time since starting.

### Test 1 (2026-11-04): the probe

**Setup.** Adam's E16, firmware SW 1.3.0, HW v5, BLE 1.0.5, over USB with USB Multi Port on; the
OXI App closed. `sbdev e16` on branch `e16-probe`.

**Findings:**

- **Ports.** Sources and destinations "OXI E16 Port 1", "Port 2", "Port 3".
- **ENTER.** ACK after one message, 42 ms; the screen and all rings went dark. **EXIT** brought
  them back at once, as did Control-C (which sends EXIT).
- **LABELS.** A title ("TOTALMIX  MAIN") and sixteen labels drew in the device's 4×4 layout.
- **LED RING.** Sixteen rings, each its own color, filled 1/17 to 16/17; the boundary LED dims in
  steps, not on/off.
- **Turns.** Slow: +1 per message (`01`), counter-clockwise `7F`. Fast: up to +8 (`08`), a message
  every 4–5 ms. The unit is not detented.
- **Pushes.** Note on, then note off on release. **Shift.** Note 16 on and off.
- **Rate.** All sixteen rings at 25 fps (75 frames in 3028 ms) and at 60 fps (180 frames in 3057
  ms, 58.9 fps): smooth, nothing dropped.

### Test 2 (2026-11-04): the driver with TotalMix FX, through `sbdev e16bridge`

**Setup.** As test 1; TotalMix FX 2.10 on the same Mac, Global OSC, ports 7001 and 9001.

**Findings:**

- **End to end.** Turns moved TotalMix FX's faders (`/mix/in/n/0/faderlin`), pans (`balpan`), and
  sends; pushes muted (`/input/n/mute`) and held pushes set PFL (`/input/n/pfl`); TotalMix FX's
  changes drew on the rings.
- **The single-LED message** is a persistent override: rings showed holes and alternating LEDs
  and some labels drew inverted; EXIT and ENTER didn't clear it, a power cycle did. The driver
  stopped using it.
- **The title** is cut to 15 characters on the screen; space padding moved it off center, null
  padding didn't.
- **Brightness.** From the `ramp` command (white rings at 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48,
  64, 80, 96, 112, 127): 3 reads as lit, 2 as dim, 1 barely; the steps above 64 are close. Full
  brightness was too much for a dark room; 70% still a little; 55% chosen as the default.
- **Colors.** From the `palette` command: a dim grey read as a dim white or as a level, and the
  blue-greys as blue; grey became cyan. Orange was moved toward red and yellow toward orange so
  the two stayed apart; purple was moved between blue (too close at (16, 0, 127)) and magenta
  (too close at (90, 0, 127)).
- **The framebuffer.** A title drawn with the page layout of section 2 read correctly, so bit 0 is
  the top pixel. The 3×5 font was unreadable and the 4×6 still too small; 5×7 is readable.
- **The layout** of section 4 was decided in this test: Shift as buttons, tap for mute, hold for
  PFL with a countdown, the two arrow pairs, the four Shift levels, and the indicator rules from
  the UI review.

### Test 3 (2026-11-04): the app

**Setup.** As test 2, with the app (`swift run PerformanceBridge`), the E16 the only hardware
controller plugged in.

**Findings:**

- The app switched to the E16 by itself ("Choosing the OXI E16: it is plugged in and the
  Roto-Control isn't") once detection matched the port's name as the engine does; an exact match
  on "OXI E16 Port 1" had not found it (first build).
- The Brightness slider dimmed the rings at once. Below about 15% orange and yellow could not be
  told apart, with or without the dimming floor; the slider now stops at 15%.
- Colors as finally set (section 4): TotalMix FX's green, yellow, and orange read as three colors
  and PFL as a fourth; the yellow was moved toward orange, the orange toward red, the green a
  little darker, and PFL from the first lime (too green) to a paler yellow-green.
