# OXI E16: what this project relies on

This is a working reference for the parts of OXI Instruments' E16 that Performance Bridge uses:
its Remote Mode, on the factory firmware. In Remote Mode the host draws the screen and the
encoder rings, and the device sends the host its encoders' turns and pushes. The text is written
in this project's own words, with the evidence for each statement; nothing is copied from OXI
Instruments' documents. The `OXIE16` library implements the protocol and `E16Driver` the layout.

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote saying where it comes from: one of the sources in section 1, or a test
against an E16, described in section [7](#7-tests) with the firmware version. Where something is
reasoning that has not been checked, the text says so in words ("inference", "untested").

[^sheet]: OXI Instruments' "E16 REMOTE CONTROL" Google Sheet
    ([link](https://docs.google.com/spreadsheets/d/1Yccnrluv10QL_PauMmtCt64EtYjfSeZEXKrlrw8P24w/edit),
    gid 1057524829), linked from the E16 1.2.0 release notes, read 2026-11-04.
[^manual]: OXI Instruments' "OXI E16" manual, edition 1.3.0a (October 2026), from their
    [downloads](https://oxiinstruments.com/), read 2026-11-04; Remote Mode is on p. 87.
[^release-notes]: OXI Instruments' E16 firmware release notes
    ([GitHub](https://github.com/OXI-Instruments/OXI-E16-Releases/releases)): 1.2.0 (Remote Mode
    announced) and 1.3.0 (Remote Mode restored after 1.2 had broken it), read 2026-11-04.
[^schwung]: The `docs/E16_REMOTE.md` notes of charlesvestal's open-source
    [schwung](https://github.com/charlesvestal/schwung) project, which drives an E16 in Remote
    Mode from an Ableton Move, read 2026-11-04. Nothing from it is copied here.
[^test-1]: [Test 1](#test-1-2026-11-04-the-probe) (2026-11-04), section 7; firmware 1.3.0.
[^test-2]: [Test 2](#test-2-2026-11-04-the-driver-with-totalmix-fx-through-sbdev-e16bridge)
    (2026-11-04), section 7; firmware 1.3.0.
[^test-3]: [Test 3](#test-3-2026-11-04-the-app) (2026-11-04), section 7; firmware 1.3.0.
[^test-4]: [Test 4](#test-4-2026-11-04-sends) (2026-11-04), section 7; firmware 1.3.0.
[^test-5]: [Test 5](#test-5-2026-11-05-the-per-led-message) (2026-11-05), section 7; firmware 1.3.0.
[^test-6]: [Test 6](#test-6-2026-11-05-push-and-turn) (2026-11-05), section 7; firmware 1.3.0.
[^test-7]: [Test 7](#test-7-2026-11-05-111-on-the-device) (2026-11-05), section 7; firmware 1.3.0.

**Status (2026-11-05).** Seven tests have been run, all on Adam's E16 with firmware 1.3.0 (section
7). Section 6 lists what is still open.

## 1. Sources

OXI Instruments' documents are linked, not committed (AGENTS.md, section 4).

- **The Remote Mode sheet.** "E16 REMOTE CONTROL", a Google Sheet linked from the 1.2.0 release
  notes.[^sheet] The main source: every message, its ID, and its payload.
- **The manual.** "OXI E16", edition 1.3.0a; Remote Mode on p. 87, the controls, scenes, and
  System settings elsewhere.[^manual]
- **The release notes.** 1.2.0 and 1.3.0, for the firmware Remote Mode needs.[^release-notes]
- **schwung's notes.** A third-party host's notes on Remote Mode, for the layout of the 7-bit
  packing and for what happens when a host quits without EXIT.[^schwung]
- **The firmware's source** (github.com/OXI-Instruments) is open but is not used: this project
  works with the factory firmware only (Adam, 2026-11-04).

## 2. The device

The E16 has sixteen push encoders in four rows of four, each with a ring of 16 RGB LEDs; a 128×64
one-bit OLED screen above them; a Shift button; and USB-C and Bluetooth MIDI.[^manual] Over USB it
has three MIDI ports, "OXI E16 Port 1", "OXI E16 Port 2", and "OXI E16 Port 3", as sources and
destinations; Remote Mode works on Port 1.[^test-1] (Whether a one-port USB setting exists, and
what it does to the names: untested; it is in neither the sheet nor the manual.) The encoders are
not detented.[^test-1]

Remote Mode needs firmware 1.3.0 or later. OXI Instruments announced it in 1.2.0, and the 1.3.0
release notes say 1.3.0 restored it after 1.2 had broken it.[^release-notes] The firmware tested
is SW 1.3.0, HW v5, BLE 1.0.5.[^test-1]

## 3. SysEx framing

Every host message is `F0 00 21 5B 02 01`, a two-byte message ID, a payload, and `F7`.[^sheet] The
payload is "7-bit packed" (the sheet's words).[^sheet] The layout follows a published
example:[^schwung] for each group of up to seven raw bytes, one byte carrying their high bits (bit
k for byte k of the group), then the seven bytes with bit 7 cleared (`FF 00 80 7F 01 FE 55 AA` →
`25 7F 00 00 7F 01 7E 55 01 2A`, a test in `OXIE16Tests`). The device confirmed it: the
host-drawn labels, whose second pixel row is bit 7 of its page, read correctly.[^test-2]

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
  +8 when fast, with a message every 4–5 ms);
- a push: note 0–15 on (press) and off (release);
- Shift: note 16 on and off;
- the ACK, `F0 00 21 5B 02 01 06 53 F7`, after ENTER.

## 4. What the device does with them

- **ENTER** is answered within a few milliseconds: 1–6 ms after ENTER in the eight `sbdev
  e16bridge` runs of test 2.[^test-2] The screen and every ring go dark until the host draws
  them.[^test-1] **EXIT** brings the device's own screen and rings back at once.[^test-1] A host
  that quits without EXIT leaves the device blank until an EXIT or a power cycle (reported by
  schwung's notes;[^schwung] untested here), so the driver's `stop` always sends EXIT.
- **LED RING** fills a ring clockwise from the bottom (six o'clock), in sixteenths, with the LED at
  the boundary dimmed in proportion rather than on or off; the color is per ring.[^test-1] The
  LEDs are already bright at small values: 3 or 4 of 127 is clearly lit, 2 reads dim, and 1 is
  barely there; the steps above about 64 are hard to tell apart.[^test-2] With the driver's
  brightness setting below about 15%, orange and yellow were hard to tell apart; the usable range
  was set at 3%–80% with proportional dimming (3% being the floor, a color's largest part at 4), which the app's slider shows as 1–100.[^test-3] Sixteen
  rings sent at 60 frames per second (180 messages in 3057 ms) looked smooth to the eye; the tool
  measures only its own sending.[^test-1]
- **LED (single)** sets one LED (index 0 is the first LED left of six o'clock, the index running
  clockwise) and holds it until the next LED RING message for that ring, which replaces the whole
  ring; a LED message after a RING fill punches that LED into the fill; sixteen LED messages draw
  a striped ring or, sent every 150 ms, a smooth rotation of four LEDs; and RING draws normally
  afterwards, with nothing left behind.[^test-5] (Test 2 had read the message as a persistent
  override that also inverted the encoder's label: test 5 shows it is not. The likely cause was
  the driver of that build re-sending its own LED messages every tick, not the device; the label
  inversion is unexplained.) The driver uses it from 1.1.1 for a mute's rotating marks.
- **OLED LABELS** draws the title on the top line and the labels in the 4×4 layout of the
  encoders. The firmware centers the title and shows only 15 of its 16 characters; padding a
  title with spaces moves it off center, padding with nulls doesn't.[^test-2]
- **OLED FRAMEBUFFER** replaces the whole screen; the page layout above (bit 0 at the top) was
  confirmed by readable text.[^test-2] A screen drawn this way and one drawn with LABELS
  replace each other.

## 5. The layout Performance Bridge uses

The layout was decided with Adam on 2026-11-04, in tests 2 and 3. Each page has sixteen strips,
always sources.

- **Turn**: the strip's level in the home submix, its pan, or its send to one output, by the mode.
  The device's 1–8 steps are scaled by `E16Driver.levelStep` (0.0025 of the fader's travel per
  step) and `panStep`.
- **Push and release** (under 1 s): mute, on release. **Hold** 1 s: PFL, with a countdown arc after
  a 0.25 s tap window; the title says "NAME -> PFL" while the countdown runs and "NAME PFL ON" (or
  OFF) while the encoder stays held. One push at a time: a second push while one is held replaces
  it (a design choice; two-finger mutes would need a hold per encoder).
- **Push and turn** (1.1.1; Adam, 2026-11-05): pan, or the level in PAN mode, while the encoder is
  held; the ring shows that value and the title its number, and on release the ring goes back to
  the mode's. A turn while pushed, before PFL has switched (1 s), cancels the push: no mute on
  release, and no PFL however long it is then held; a turn after PFL has switched is an ordinary
  turn of the mode's function.[^test-6]
- **Shift** makes the encoders buttons: 1 LEVEL (white), 2 PAN (magenta), 3 SEND (deep green; back
  to the last output used), 11 and 12 the previous and next send output (deep green; outside SEND
  mode either arrow enters it at the last output used),[^test-4] 15 and 16 the previous and next
  page (blue). While Shift is held the screen names them (blank where an arrow goes nowhere) and the
  rings show them at four levels: off (nothing there, or nowhere to go), 2 of 127 (available), the
  brightness setting (in use), and the button's color with its largest part at 127 (pressed).
- **How this compares with the factory firmware's Shift** (the manual, sections 1.5–1.6 and 2.6,
  and the "hold" menu;[^manual] checked in the review of 2026-11-04). The firmware's *hold* of
  Shift opens a momentary menu whose commands sit on the knobs until Shift is released, and
  inside its editor Shift + knobs 1–3 choose tabs; its lighting rule is that any knob with a
  selectable option is lit and the rest are dark. The driver's Shift page follows that idiom and
  that rule. The firmware's *page* selection, though, is a tap of Shift that toggles a page view
  where knobs 1–12 are pages 1–12 and the bottom row holds commands; the driver's previous and
  next arrows, and its arrows on row 3, have no counterpart there. The firmware's documented
  colors (red for Off and No, green for Yes, a scene's own color) do not conflict with the
  driver's (no red on the Shift page; deep green for SEND).
- **Rings**, from the UI review of 2026-11-04, as changed in 1.1.1: the strip's TotalMix FX color
  filled to its level, the whole ring at 0 dB and above (`levelAmount`; Adam, 2026-11-05; 1.1.0
  kept the last LED for a switch); a pan as its arc from the top, in the channel's color at center and red as
  soon as it is off center, drawn at least one LED's worth off the top (`panMinimumOffset`; R1
  lit one red LED[^test-7]) so L1 and R1 show by shape on a red channel too; dark means
  no strip (a strip always lights at least one LED), unless marks turn on it: a switch that is on
  is four marks a quarter ring apart turning one LED every 150 ms (by LED messages after the
  RING message[^test-5] [^test-7]), orange for a mute and pink for a PFL, interleaved two LEDs
  apart when both are on (Adam, 2026-11-05: mute and PFL alike, by color); a mute that is set
  while TotalMix FX's Mute Master is off shows its marks still, alternating every 0.5 s with the
  level. (1.1.0 showed mute as a steady full orange ring, one LED from a full-level orange
  channel, and PFL as a pink heartbeat: Adam, 2026-11-04.)
- **Colors.** TotalMix FX's channel colors are mapped so they stay apart on these LEDs: gray is
  shown as cyan (0, 110, 127), the hue TotalMix FX leaves free, since a dim gray read as a dim
  white or a level; orange (127, 25, 0), red (127, 0, 0), blue (0, 0, 127), green (0, 105, 0),
  yellow (127, 85, 0), purple (70, 0, 127). Mute uses this orange, and PFL is pink (127, 30, 60), the hue TotalMix FX leaves free: with more blue it blended with purple at the top of the range. The
  brightness setting (3%–80%, shown as 1–100; default 55%, 68 on the slider) scales all of them in proportion, so
  a color's hue is the same at every setting; a color's largest part never goes below 4, so a lit
  ring stays lit. (A floor added to each part was tried first and pushed orange toward yellow at
  the lowest settings.) The colors and brightness are
  to be tuned by side-by-side comparison after 1.1.0 (Adam, 2026-11-04).
- **Screen.** The host draws it (FRAMEBUFFER) with a 5×7 proportional font of the project's own,
  after 3×5 and 4×6 fonts were too small to read. The title (the mode, or an overlay) is at the
  left and "PFL" and the page at the right; a rule runs under them; the sixteen labels sit in four
  rows 14 pixels apart, each at the left of its 32-pixel cell and no wider than 26 pixels (the
  Shift page's arrow labels are 28 pixels, accepted on the device). A stereo pair keeps both
  numbers, losing its word first ("ADAT3/4", "ADT3/4", "AD3/4", "3/4"; "P15/16", "15/16"); only a
  pair of three-digit numbers, which no form fits, is cut from the end ("100/10").
  The firmware's own LABELS layout, with four-character labels (e.g., "P1/2"), is kept as a
  fallback.

## 6. Open questions

- Bluetooth MIDI: untested.
- The device's System settings in Remote Mode: whether Brightness (Low, Med, High) scales the
  host's ring colors, whether Auto Turn Off and the Screensaver still fire, and whether Animations
  morph the host's ring changes (the manual's System table).[^manual] Untested; the tests ran with
  the unit's settings as found, not recorded. Also untested: whether a long hold of Shift does
  anything in Remote Mode.
- The partial OLED messages (scanline, rectangle, clear) and the bipolar flag's exact drawing:
  untested; the driver uses FRAMEBUFFER and sends bipolar rings for pans, which looked right.
- Why test 2 saw stuck LEDs and inverted labels: test 5 found no override in the device; the
  driver of that build re-sending its own LED messages is the likely cause (inference), and the
  inversion is unexplained. Watch for it when the driver uses LED messages in 1.1.1.
- Whether the driver needs an acceleration curve of its own. For now it multiplies the device's
  1–8 steps by a fixed step.
- A 4-channel "strip" layout (four channels across, LEVEL on the fourth row, rows 1–3 each
  assignable to PAN or one send): an idea for after 1.1.0 (Adam, 2026-11-04).

## 7. Tests

Run with `sbdev e16` (the probe: `ports`, `monitor`, `enter`, `exit`, `labels`, `ramp`, `palette`,
`demo`) and `sbdev e16bridge` (the driver with TotalMix FX, as the app runs it), on macOS. Both
print what they send and receive with the time since starting. The logs of tests 2 and 3 are
Adam's Terminal transcript of the day (`e16bridge-terminal-1104.log`, in the project folder); the
probe's runs in test 1 were not logged, so its numbers rest on the session's notes.

### Test 1 (2026-11-04): the probe

**Setup.** Adam's E16, firmware SW 1.3.0, HW v5, BLE 1.0.5, over USB; the OXI App closed. `sbdev
e16` on branch `e16-probe`.

**Findings:**

- **Ports.** Sources and destinations "OXI E16 Port 1", "OXI E16 Port 2", "OXI E16 Port 3".
- **ENTER.** ACK after one message; the screen and all rings went dark. (The probe's own "42 ms"
  was measured from the tool's start with 20 ms polling, not from ENTER; `sbdev e16bridge` logs
  the ACK 1–6 ms after ENTER, test 2, and the probe now reports from the last ENTER it sent.)
  **EXIT** brought them back at once, as did Control-C (which sends EXIT).
- **LABELS.** A title ("TOTALMIX  MAIN") and sixteen labels drew in the device's 4×4 layout.
- **LED RING.** Sixteen rings, each its own color, filled 1/17 to 16/17; the boundary LED dims in
  steps, not on/off.
- **Turns.** Slow: +1 per message (`01`), counter-clockwise `7F`. Fast: up to +8 (`08`), a message
  every 4–5 ms. The unit is not detented.
- **Pushes.** Note on, then note off on release. **Shift.** Note 16 on and off.
- **Rate.** All sixteen rings sent at 25 fps (75 messages in 3028 ms) and at 60 fps (180 in 3057
  ms): smooth to the eye. The tool measures its own sending, not what the device rendered.

### Test 2 (2026-11-04): the driver with TotalMix FX, through `sbdev e16bridge`

**Setup.** As test 1; TotalMix FX 2.10 on the same Mac, Global OSC, ports 7001 and 9001. Eight
runs, logged from the TotalMix FX side only (`--verbose` off).

**Findings:**

- **End to end.** Turns moved TotalMix FX's faders (`/mix/in/n/0/faderlin`, `/mix/pb/n/0/faderlin`)
  and one pan (`/mix/in/0/0/balpan`); pushes muted (`/input/n/mute`, `/playback/n/mute`) and held
  pushes set PFL (`/input/n/pfl`); TotalMix FX's changes drew on the rings. Sends are in test 4.
- **The ACK** came 1–6 ms after ENTER in every run.
- **The single-LED message** appeared to be a persistent override: rings showed holes and
  alternating LEDs and some labels drew inverted; EXIT and ENTER didn't clear it, a power cycle
  did. The driver stopped using it. (Test 5 later showed the device holds no such override; see
  it for the likely cause.)
- **The title** is cut to 15 characters on the screen; space padding moved it off center, null
  padding didn't.
- **Brightness.** From the `ramp` command (white rings at 1, 2, 3, 4, 6, 8, 12, 16, 24, 32, 48,
  64, 80, 96, 112, 127): 3 reads as lit, 2 as dim, 1 barely; the steps above 64 are close. Full
  brightness was too much for a dark room, and 70% still a little too much; 55% was chosen as the
  default.
- **Colors.** From the `palette` command: a dim gray read as a dim white or as a level, and the
  blue-grays as blue; gray became cyan. Orange was moved toward red and yellow toward orange so
  the two stayed apart; purple was set between blue and magenta, after (16, 0, 127) was too close
  to blue and (90, 0, 127) too close to magenta.
- **The framebuffer.** Text drawn with the page layout of section 3 read correctly, so bit 0 is
  the top pixel. The 3×5 font was unreadable and the 4×6 still too small; 5×7 is readable.
- **The layout.** Most of the layout of section 5 was decided in this test (the colors and
  brightness in test 3): Shift as buttons, tap for mute, hold for PFL with a countdown, the two
  arrow pairs, the four Shift levels, and the indicator rules from the UI review.

### Test 3 (2026-11-04): the app

**Setup.** As test 2, with the app (`swift run PerformanceBridge`), the E16 the only hardware
controller plugged in. From Adam's session; the app's own log was not kept beyond the transcript,
whose two app runs were of the previous build (a `git pull` had been refused).

**Findings:**

- The app switched to the E16 by itself ("Choosing the OXI E16: it is plugged in and the
  Roto-Control isn't") and connected it; the menu showed "OXI E16: Connected".
- The Brightness slider dimmed the rings at once. With the setting below about 15%, orange and
  yellow were hard to tell apart, with or without the dimming floor. With a 0–100% slider, Adam set
  the usable range at 10%–80% with the floor, then 3%–80% once the dimming kept proportions (`sbdev e16 colors`: every color distinct at the floor, PFL chosen there and at 80%), shown as 1–100; a pressed Shift button stays at full.
- Colors as finally set (section 5): TotalMix FX's green, yellow, and orange read as three colors
  and PFL as a fourth; the yellow was moved toward orange, the orange toward red, the green a
  little darker, and PFL from the first lime (too green) to a paler yellow-green. Then, with
  `sbdev e16 colors` at the lowest setting, that yellow-green was too close to both green and
  yellow; pink was chosen from pinks, salmons, and turquoises (turquoise sat
  between grey-as-cyan and green).

### Test 4 (2026-11-04): sends

**Setup.** As test 2, after the substance review found no send in the earlier logs. Log
`e16-sends-1104.log` in the project folder.

**Findings:**

- Shift + 3 (SEND) put the title at "> ADI-2 3/4" (the last output used, with the "PFL" marker at
  the right for a PFL still on); turning encoder 1 sent `/mix/in/4/2/faderlin` (20 messages:
  input 5's send to output 3).
- Shift + 12 (SEND>) moved the title to the next output, "> PHONES 2"; turning encoder 1 sent
  `/mix/in/4/6/faderlin` (14 messages: the same input's send to output 7).
- Shift + 1 (LEVEL) went back to LEVEL; Control-C sent EXIT.

### Test 5 (2026-11-05): the per-LED message

**Setup.** As test 1, with `sbdev e16 led` (branch `e16-shapes`): ten scripted steps on rings 1 and
2, Adam reporting each. The ACK came 0.7 ms after ENTER (the probe now measures from the ENTER).

**Findings:**

- A LED message for ring 1, LED 0, red, lit the first LED left of six o'clock; the rest of the
  ring's half-blue fill was unchanged and the label was not inverted.
- A RING fill to three-quarters replaced it: the red LED went away.
- A LED message setting LED 0 black punched a dark LED into the three-quarter fill; a RING fill
  to half then drew the ring normally.
- Sixteen LED messages drew ring 2 striped (every other LED orange, the rest dark), with ring 1
  unchanged.
- Four orange LEDs at the quadrants, moved one LED every 150 ms by sixteen LED messages a frame
  for 4 s, rotated smoothly with no flicker.
- Sixteen LED messages set to black left ring 2 dark; a RING fill to half, then a full green
  ring, drew normally with no LED stuck.
- So a LED message holds until the next RING message for its ring, and the mute indicator of
  1.1.1 (four orange marks rotating on a dark ring) needs one RING and four LED messages per step.
  The driver's drawing of it is test 7.

### Test 6 (2026-11-05): push and turn

**Setup.** As test 1, with `sbdev e16 labels TEST` (Remote Mode, every event printed). Adam pushed
encoder 1, turned it while holding it, and released it. (`sbdev e16 monitor` first, without Remote
Mode, showed only the device's own scene: CC 1–16 on several channels, no pushes.)

**Findings:**

- The device sends the push, the turns, and the release in order: `PUSH encoder 1 down` at
  2.681 s, 27 turns of +1 to +4 from 2.817 s to 3.926 s, `PUSH encoder 1 up` at 3.991 s. So
  push-and-turn is a gesture the host can see.
- The push was held 1.3 s. In 1.1.0 that would have set PFL on top of the turns; from 1.1.1 a turn
  while pushed cancels the push.
- Push-and-turn as pan was then seen working through `sbdev e16bridge`; at first L1, L2, R1, and
  R2 drew in the channel's white like center, so off-center pans are now red (Adam).

### Test 7 (2026-11-05): 1.1.1 on the device

**Setup.** As test 2, `sbdev e16bridge` on branch `e16-shapes` after the Tier 1 review's fixes.

**Findings (Adam):**

- A muted channel's ring was dark with four orange lights turning around it.
- Push-and-turn from center: at R1 (the screen's value) one red LED lit to the right of the top;
  turning on, the screen went to R2.
