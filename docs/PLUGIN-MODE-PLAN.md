# PLUGIN mode: the plan

This is a plan, not a record. It sets out how Performance Bridge could use the Roto-Control's
PLUGIN mode, what is known, and the tests that decide each part. Nothing here is in the app. What
exists is for the tests: the probe (`sbdev vport`), the `ArturiaControl` library, and three
prototypes (`sbdev roto`'s macro commands, `sbdev relay`, and `sbdev arturia`), each run once on
Adam's Roto-Control, on 2026-11-14 (section 7). Statements about the Roto-Control rest on
`docs/ROTO-CONTROL.md`, and those about Arturia's instruments on `docs/ARTURIA.md`; statements
about Melbourne Instruments' Bitwig Studio and Logic Pro integrations come from reading their code
in [roto_control](https://github.com/Melbourne-Instruments/roto_control) (commit 2d43a72) on
2026-11-13 (the Bitwig integration by two readers, the second checking the first) and have not
been tested unless a test is named. Everything else is a proposal.

**Where it stands (2026-11-14).** Tests R1 (with a caveat, R6), R2, and R4 passed, and the Arturia prototype kept
Pigments and the Roto-Control in step both ways (`docs/ROTO-CONTROL.md`, test 15;
`docs/ARTURIA.md`, test 2). One run each; parts of R2 and of the Pigments run rest on what Adam
saw, since their logs were not kept whole. R3 (Logic) and A1–A6 are not done.

**Later the same day.** On the KeyLab mkII's profile the Roto-Control showed the instruments' own
names and value text (`docs/ARTURIA.md`, test 7). Then test 8 changed the design: Adam uses a
real KeyLab mk3 beside the Roto-Control, and an instrument talks to one controller at a time, so
the driver has to sit between the keyboard and the instrument, in the mk3's format (section 6,
"Beside a real KeyLab mk3"). Built, with names read from Pigments' files and asked of the
instrument elsewhere; none of that has run with the devices (A8–A12).

## 1. The aim

Adam, 2026-11-13: MIX mode stays on TotalMix FX. A quick switch to PLUGIN mode on the device puts
the knobs on the macros and other parameters of a standalone Arturia instrument or of the plugin in
front in a DAW (Bitwig Studio and Logic Pro first), with Performance Bridge passing data both ways.
Later, the transport switches reach the DAW. Everything is two-way as far as the other side
allows; a one-way connection is not worth building.

## 2. One owner of the device

The Roto-Control talks to one host. CoreMIDI lets several programs open its ports, so nothing but
agreement stops two hosts from talking to it at once. The plan: Performance Bridge is the only
program that opens the device's ports, and every other program reaches the device through a
virtual port that Performance Bridge publishes (`VirtualMIDIPort`). The device tells its host
which mode it is in (SET PLUGIN MODE, SET MIX ALL TRACKS MODE, SET MIX TRACK MODE, REQUEST
TRANSPORT STATUS), so Performance Bridge can route by mode with no setting to keep in step.

What PLUGIN mode is connected to (the "target") is one of: Bitwig Studio, Logic Pro, an Arturia
instrument, or nothing (today's behavior: no plugins). How the target is chosen is open: the app in
front, or a menu. The app in front needs no setting, and is the proposal.

## 3. Bitwig Studio: a relay

Bitwig's integration claims type `02`, as Performance Bridge does, so the device needs no new
handshake. Performance Bridge passes messages between the device and the virtual port, by rule.
From the integration's code:

- **Starting.** The integration sends DAW STARTED when it loads; the relay must not pass it on, or
  the device starts a new handshake. The integration sends nothing else until it receives SET
  PLUGIN MODE, SET MIX ALL TRACKS MODE, or REQUEST TRANSPORT STATUS, so forwarding the device's
  next SET PLUGIN MODE is enough to bring it up. It answers a ping and CONNECTED, but waits for
  neither.
- **Device to Bitwig, in PLUGIN mode:** every PLUGIN (`0B`) message; SET FIRST TRACK, ROTO SELECT
  TRACK, REQUEST TRANSPORT STATUS, TOGGLE TRACK GROUPING, and REQUEST SEND TRACK NAMES; and the
  CCs for knobs, switches, touches, and transport.
- **Kept from Bitwig, always:** SET MIX ALL TRACKS MODE, SET MIX TRACK MODE, and SET ALL TRACKS
  MODE. Performance Bridge answers them itself. Bitwig then goes on believing the device is in
  PLUGIN mode.
- **Bitwig to device:** everything while the device is in PLUGIN mode; nothing while it is in MIX
  mode (Bitwig keeps sending knob positions and plugin lists as things change, and waits for no
  answer, so dropping them does it no harm).
- **Coming back to PLUGIN mode.** On SET PLUGIN MODE Bitwig sends the plugin list again, the
  selection if the selected plugin is on the page, the positions of the knobs that have a
  parameter, and the switch lights. It sends the selected track only if that has changed, and
  never the track page or the send names, which Performance Bridge's own MIX page has
  overwritten; the relay keeps Bitwig's last ones and sends them again.
- **Bitwig reloading its integration.** A new instance sends nothing until it is told the mode
  again, so on its DAW STARTED the relay tells it. Seen once, in PLUGIN mode: the integration's
  plugin list followed within 1 ms (test 15).
- **Going back to MIX mode.** Bitwig writes its own track list to the device while in PLUGIN
  mode, so Performance Bridge must draw its page again. It already does on SET MIX ALL TRACKS
  MODE.
- **Ports.** The integration looks for ports named "Roto-Control" but has no check of its own on
  the name; Melbourne Instruments' guide says the ports can be chosen by hand in Bitwig's
  controller settings. In test 15 Bitwig already had the integration on the device's real
  ports, and talked to the device directly until both of its port menus were set to the relay's
  port (seen); the menus have to be set back to use Bitwig without the relay. For the app this
  means a Setup Guide page, and a way to notice a second host on the device (it shows as a new
  PING DAW).
- **The relay's port name.** "PB Roto Relay" contains "Roto", the name `sbdev` and the engine
  look for the device by, and `sbdev relay` could not find the device until it opened the device
  first. The app needs a name that can't be taken for the device, or an exact match.

What the user gets is what Bitwig's integration gives: remote-control pages mapped to the eight
knobs with no learning, or learned mappings stored on the device, with names, motor positions, and
value text. An Arturia plugin in Bitwig is reached this way, with 14-bit knobs. In test 15 the
eight knobs showed Polysynth's remote controls and worked both ways through the relay (seen),
but only once Show Remote Controls was on in Bitwig; which messages carried them was not logged,
so "no learning" is still from the code reading (`docs/ROTO-CONTROL.md`, section 8, item 8).

## 4. Transport, for Bitwig

The transport switches can go to Bitwig while the knobs stay in MIX mode on TotalMix FX, since
TotalMix FX has no transport and the integration's transport switches work apart from its knobs.
Forward REQUEST TRANSPORT STATUS and CCs 28–37; pass back TRANSPORT STATUS and CCs 28–35; drop the
rest. Two things to know: the loop and punch-in flags in the integration's TRANSPORT STATUS are
filled from the wrong settings (an apparent bug in its code; the lights it sends as CCs afterward
are right), and its stop light is lit while playing. Test 15 ran this through the relay: play
and stop reached Bitwig from MIX mode, both lights lit while it played, and leaving transport
mode gave the page back to the relay.

## 5. Logic Pro: later, and differently

Logic's integration is a script inside Logic's own control-surface layer. It names the port
"Roto-Control" in every control, claims type `03`, and relies on what the device does only for
that type: mapped parameters on other MIDI channels, a parameter sweep for learning, and transport
status as CCs. With `03`, Performance Bridge's own PLUGIN-mode replies never settled
(`docs/ROTO-CONTROL.md`, test 3).

So a relay for Logic means a new handshake as `03` whenever Logic is the target, with the device
behaving differently in MIX mode too while it lasts, and a virtual port named "Roto-Control" with
the device's own ports renamed in Audio MIDI Setup so that Logic finds only the virtual one. The
simpler first step is a switch that hands the whole device to Logic and takes it back. Both wait
for test R3.

## 6. Arturia's standalone instruments: a driver

Performance Bridge publishes a virtual port under one of the first KeyLab keyboards' names, and
the instrument reports to it (`docs/ARTURIA.md`). The driver presents the instrument to the device
as one plugin.

- **Controls.** Nine an instrument: macros 1–4, four parameters of the instrument's own, and the
  master volume. Proposal: knobs 1–4 the macros, 5–8 the four parameters, and the volume on a
  second page. The layout is Adam's to decide.
- **No learning.** Bitwig's integration shows eight named, positioned knobs with no learning by
  declaring a "macro" plugin. It then waits for the device to send CONTROL MAPPED for a macro
  knob, and answers with LEARN PARAM, with the macro flag, for all eight. So the path depends on
  the device announcing macro knobs that were never learned, which is test R1. The driver would do
  the same; sending LEARN PARAM unasked is this project's own variant, also in R1.
- **Names.** The parameter behind each control differs by instrument. The driver can read the
  instrument's own installed files for the names when it starts (reading another app's files is
  allowed; nothing of Arturia's is shipped).
- **Values.** 7 bits from the instrument, scaled to the knob's 14. The device's value text has to
  be worked out by the driver (a percentage), since the instrument sends none.
- **Not knowing a value.** Until an instrument reports a control, the driver doesn't know where it
  is, so it should leave that knob unmapped or unmoved rather than show a wrong position. Test A1
  decides how often that happens.
- **More than one instrument.** A value message doesn't say which instrument sent it, and a
  control change sent from one virtual port reaches every instrument listening to it. So each
  running instrument needs a port of its own, and the profile has four names. Which instrument a
  port belongs to can be read from the text message's first field. This limit, and whether one
  instrument at a time is enough, are for Adam.
- **The name.** "KeyLab 25" (Adam doesn't own one) rather than "KeyLab 61", if test A3 passes.

What the first run of the prototype showed (`docs/ARTURIA.md`, test 2), and what follows from it:

- **It works both ways** on all nine controls of Pigments, with the layout proposed above.
- **Steps.** The knobs follow in 128 visible steps. The driver could glide the motor between
  values instead of jumping (a proposal; it hides the steps and adds no resolution).
- **The preset's name.** Adam, 2026-11-14: the plugin's name in the MENU window's top line and
  the preset's name in its bottom line. SET CURRENT TRACK NAME, which the prototype sends, put
  nothing there in this run, but did in all three runs of test 7 (`docs/ARTURIA.md`), cut to 12
  characters; why it failed here is not known (`docs/ROTO-CONTROL.md`, section 8, item 7).
- **Values on connecting** came in this run and not in test 1, so "not knowing a value" above
  still stands until A1 says which is the rule.
- **Names.** "Param 1" to "Param 4" tell the user nothing; reading the instrument's files for
  the real names matters more than it seemed (knob 5 was Filter 1's cutoff in one preset).

Then tests 3 and 4 (`docs/ARTURIA.md`) changed the picture, and the driver should change with
them:

- **Imitate the KeyLab mkII, not the first KeyLab.** Same messages, and the instrument then
  sends each control's name and its value in words when the control is changed from the
  controller. That answers "Names" and "Values" above without reading files: the driver learns a
  knob's name the first time the knob is turned, and shows the instrument's own value text
  ("1448 Hz") in place of a percentage. The item numbers differ, and the port is "KeyLab mkII
  61" (or 49 or 88). Done in `ArturiaRotoDriver` and `sbdev arturia` (2026-11-14), untested on
  the device (A7): a name learned from the instrument is kept until the preset's name changes;
  once the instrument has sent any value text, a turned knob waits up to 0.2 s for the
  instrument's text before showing a percentage.
- **Not the mk3.** Its profile was probed too, with Pigments and Analog Lab V (tests 5 and 6): for
  the knobs it gives what the mkII's gives, in a second message format, plus Save, Undo, and
  Redo, which could go on switches later. Neither profile brings Analog Lab V's labels before a
  knob is turned from the controller.
  `docs/ARTURIA-KEYLAB.md` sets the three generations side by side.
- **More on the mkII's profile, untested:** previous and next preset on control changes 28 and
  29, which the Roto-Control's switches could send, and nine more controls (the faders'), which
  the inference is work inward only.
- **Per-preset labels** (Adam, 2026-11-14: the aim is what Analog Lab V gives, on the single
  instruments too). Analog Lab V sends the preset's own label for a control; Pigments sends
  "Macro 1" where its window says "Timbre". Pigments' preset file holds the labels, so the driver
  could look them up by the instrument and preset names the text message gives. A proposal,
  with open questions in `docs/ARTURIA.md`, section 4.
- **Names before the first turn.** A knob has no name until it is turned once, or until the
  preset file is read. Open: whether sending each control's current value back to the instrument
  on a preset change would draw all nine names without changing anything.
- **The plugins are a separate question** (Adam, 2026-11-14). In a DAW the names come through
  the plugin interface, where Adam has seen Analog Lab V's parameters renamed per preset and the
  single instruments' not (which DAW integration, he did not say). None of the above has been tried with a plugin.

### Beside a real KeyLab mk3 (Adam, 2026-11-14)

Adam needs his KeyLab 61 mk3 and the Roto-Control at once. An instrument talks to one controller
at a time (`docs/ARTURIA.md`, test 8), so, as with Bitwig, there is one owner in the middle:

- `sbdev arturia --keyboard "KeyLab 61 mk3 MIDI"` opens the keyboard's port and publishes "KeyLab
  88 mk3 MIDI" for the instrument, where the user checks it and unchecks the keyboard's own port.
- Everything passes both ways untouched, the keyboard's bytes before anything else is done with
  them; `status` prints how long they spent in the tool, the part of the delay it can measure.
- The driver reads the same stream in the mk3's format (`ArturiaMk3Message`): values, the preset,
  and the name and value screen that follows a control change. That screen doesn't say which
  control it is about, so it is taken for the newest control change sent with its value.
- A knob moved on the keyboard moves the Roto-Control's; a knob moved on the Roto-Control is sent
  to the keyboard as a value in the instrument's own format, so that the keyboard's knob follows
  (untested: a guess at what the keyboard accepts).
- When the tool starts or stops, the instrument's port has to be checked again by hand.
- Names: from the instrument's files where they are read (Pigments), which changes nothing in
  the instrument; elsewhere, including Analog Lab V, by asking as the keyboard's touch does,
  which moves a parameter by up to one 7-bit step and marks the preset as changed (Adam's choice
  of the two, 2026-11-14; `--no-ask` turns the asking off).
- The mk3's format doesn't name the instrument. The driver knows three by a number in the preset's
  screen (Pigments, Augmented VOICES, Memory V); others show as "Arturia" and get no files.

## 7. Tests, in order

Arturia (each a few minutes with `sbdev vport`):

- **A1.** Start Pigments with the port already turned on. Do the values come?
- **A2.** MiniFreak V, a V Collection instrument, and Analog Lab V in place of Pigments.
- **A3.** "KeyLab 25" in place of "KeyLab 61".
- **A7.** `sbdev arturia` on the mkII profile, with a Roto-Control: do names and value text
  follow each knob, at what rate, and does the text keep up with a turning knob? **Passed with
  Analog Lab V and Pigments (`docs/ARTURIA.md`, test 7): names and the instruments' value texts
  followed each knob turned, answering in about 50 ms; two flaws found and fixed, the second not
  yet run.**
- **A9.** Names before any turn, from the instrument's own files (`docs/ARTURIA.md`, section 4):
  read Pigments' MIDI configuration and parameter-name files and name knobs 5–8 on entering
  PLUGIN mode; then a V Collection instrument; then where MIDI-learn changes are kept. **Built
  for Pigments (`sbdev arturia`, and `sbdev arturia-files` to see what is read); to run: with
  "Hanging Threads", knobs 1–8 should read Timbre, Time, Inharmonicit, Delay, F1 Cutoff, F1
  Resonance, F2 Cutoff, and F2 Resonance before any is turned, and with the "Welcome" template
  Timbre, Time, Unison, and Reverb.**
- **A11.** The relay with Pigments: the keyboard's picture, screen, and touch as without the tool;
  names on the Roto-Control from the files before any turn; a knob turned on each device moves
  the other, and a touch on the keyboard afterward doesn't jump the value back; notes play, with
  `status` giving the time in the tool; the value-text flash fix and names kept across presets.
- **A12.** The relay with Analog Lab V: the asking names all eight knobs after a preset loads, one
  at a time, with no value text flashing; what it does to the preset.
- **A10.** Analog Lab V: do a preset's first four controls follow its file's macro labels, in
  order (`docs/ARTURIA.md`, section 5, item 11)? Until then no files are read for it.
- **A8.** The preset-file lookup for macro labels: a second instrument, a user preset, and two
  presets of one name. **Built for Pigments (2026-11-14; `docs/ARTURIA.md`, section 4): the file
  is found by the preset's name, type, and values, which leaves 2 of Pigments' 9,392 factory
  presets open. Not yet run with the device; a user preset and a second instrument are untried.**
- **A4.** Assign another parameter to control change 74 by MIDI learn. Does it report as item 1?
- **A5.** Two instruments at once, on two port names.
- **A6.** Adam's KeyLab 61 mk3 with the same instrument afterward: does it still work as before?

Roto-Control:

- **R1.** From `sbdev roto`: a macro plugin with no learning on the device, first as Bitwig does it
  (`macro --wait`: LEARN PARAM only in answer to CONTROL MAPPED), then unasked (`macro`). Do names
  and positions show, and do the knobs then send? **Passed as Bitwig does it (test 15, run 1);
  unasked was not tried.**
- **R2.** A relay in `sbdev` between the device and Bitwig Studio, in PLUGIN mode only. **Passed
  (test 15, run 2), largely on what Adam saw; to be repeated with the whole log kept
  (`swift run sbdev relay 2>&1 | tee relay.log`, and no clearing of the Terminal window).**
- **R3.** A new handshake as `03` and back to `02` without unplugging: does the device change
  type cleanly, and how long does it take?
- **R4.** Transport to Bitwig Studio while in MIX mode. Watch what the device sends on leaving
  transport mode: the relay ends transport only on SET PLUGIN MODE or a MIX-mode message.
  **Passed (test 15, run 2): leaving sent SET MIX ALL TRACKS MODE.**
- **R5.** In PLUGIN mode from `sbdev roto`: DAW SELECT TRACK by itself, then a track page by
  itself. Which one fills the MENU window's bottom line?
- **R6.** A macro plugin under a plugin hash the device has never been sent. R1 used the hash of
  Bitwig's macro plugin, on a device that has been used with Bitwig, so it can't show that no
  stored mapping was involved. The Arturia driver should not rest on that hash until this passes.

`sbdev arturia` puts the two halves together: the Roto-Control's PLUGIN mode on a standalone
instrument, with values marked unknown until the instrument reports them. Its first run is
`docs/ARTURIA.md`, test 2.

## 8. Order of work

1. Tests A1–A6 and R1: they settle whether the Arturia driver is worth building and how. R1 is
   done; A1–A6 are not, and R5 and R6 join them.
2. The Bitwig relay in `sbdev` (R2 and R4, done once; R2 again with its log), then in the app,
   with a setting for the virtual port and a Setup Guide page for Bitwig's controller settings.
3. The Arturia driver, if step 1 says so. Its first run says it is worth building for Pigments.
4. Logic (R3 first).

Each step merges only after the review its tier calls for; until then it lives on a test branch.

## 9. For `docs/ROTO-CONTROL.md`, once checked

The reading of Bitwig's integration found things section 4a doesn't have yet. They are code
readings, to be added with their source once a second reader or a test has confirmed them:

- the macro plugin path (section 6 above), against 4a's "every control has to be learned":
  **confirmed by test 15 and now in section 4a**;
- that Bitwig does not send the track page on SET PLUGIN MODE, as Ableton does;
- that Bitwig also takes its hashes from SHA-1, of the device's name and the parameter's full ID;
- that in PLUGIN mode Bitwig reads and lights a switch as a 0–127 value, not only as on and off;
- that Bitwig handles SET FIRST PLUGIN, SET PLUGIN ENABLED, SET PLUGINS LOCK, MACRO PLUGIN PAGE
  INDEX, and TOGGLE REMOTE PAGE, and that DAW SELECT PLUGIN carries three bytes;
- an erratum in the serial API document: ADD PLUGIN's command is printed with SET PLUGIN's bytes;
- an apparent bug in Bitwig's integration, not to be copied: it unmaps a macro knob with control
  type `01`, which the SysEx doc gives to switches.
