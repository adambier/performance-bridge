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
instrument elsewhere. It ran with both devices, Pigments, and Analog Lab V that evening
(`docs/ARTURIA.md`, test 9; A9, A11, and A12 below).

**What the standalone path can't do** (Adam, 2026-11-14). An instrument tells a controller its
values in 7 bits and takes them in 7 bits, so the Roto-Control's 14-bit knobs move in 128 steps,
and asking for a name can move a parameter by a step. A plugin's parameters in a DAW have no such
limit, and most use of these instruments is in a DAW. So the next tests are of Pigments and Analog
Lab V as plugins in Bitwig Studio through the existing relay (B1–B3 in section 7): if Bitwig
gives finer values and names as good, it is the main path, and the standalone relay is for
playing without a DAW.

**The Bitwig tests** (2026-11-14, evening; `docs/ROTO-CONTROL.md`, test 16). B1 and B2 ran, and B3
began. Through Bitwig the knobs work at 14 bits both ways with the host's value text, and Analog
Lab V's per-preset labels arrive; Pigments' macros arrive as "Macro 1" to "Macro 4", and names
are cut at 12 characters. Section 10 has what follows from that, for review.

**The next day** (2026-11-15). Two of section 10's questions have answers, and Adam has
answered its first (in a DAW or a host of our own, for the resolution; section 10). Standalone Pigments
takes 7 bits and no more: its MIDI learn took an NRPN message as a plain control change
(`docs/ARTURIA.md`, test 10), so the standalone path keeps its largest limit. And B3 is done
(`docs/ROTO-CONTROL.md`, test 17): the KeyLab mk3 and the Roto-Control work on one plugin at
once when both go through Bitwig, the keyboard in its DAW program and Device mode; in the
keyboard's Arturia program the plugin is changed without Bitwig being told, and the
Roto-Control can't follow. That afternoon the name-shortening build ran in Bitwig, and a
remote controls page made by hand put an Analog Lab V Multi's own macros on the Roto-Control
at full resolution (`docs/ROTO-CONTROL.md`, test 18). Then every installed Arturia plugin's
parameters were read with a small host (`docs/ARTURIA.md`, test 11), and a fifth build ran:
shortened names, a page count that follows, and "P1" dropped for Analog Lab V's presets of one
part (test 19).

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
  49 mk3 MIDI" for the instrument, where the user checks it and unchecks the keyboard's own port.
  The name is one no keyboard of Adam's has (he has a 61 and an 88): Pigments remembers a checked
  port and checks it again when it reappears (seen, A11), so a real keyboard of the bridge's name
  would be taken for it.
- Everything passes both ways untouched, the keyboard's bytes before anything else is done with
  them; `status` prints how long they spent in the tool, the part of the delay it can measure.
- The driver reads the same stream in the mk3's format (`ArturiaMk3Message`): values, the preset,
  and the name and value screen that follows a control change. That screen doesn't say which
  control it is about, so it is taken for the newest control change sent with its value.
- A knob moved on the keyboard moves the Roto-Control's; a knob moved on the Roto-Control is sent
  to the keyboard as a value in the instrument's own format, so that the keyboard's knob follows
  (it does: `docs/ARTURIA.md`, test 9).
- Start the tool before the instrument: a running Pigments has been seen to send nothing to a
  port newly checked in it.
- When the tool starts or stops, the instrument's port has to be checked again by hand.
- Names: from the instrument's files where they are read (Pigments), which changes nothing in
  the instrument; elsewhere, including Analog Lab V, by asking as the keyboard's touch does,
  which moves a parameter by up to one 7-bit step and marks the preset as changed (Adam's choice
  of the two, 2026-11-14; `--no-ask` turns the asking off).
- **Flagged for the user-experience review** (Adam, 2026-11-14): whether the bridge should ever
  write to an instrument only to learn a name. Asking sends values back, which can move a
  parameter by a 7-bit step and marks the preset as changed; once, before a fix, it sent a value
  from the preset before and set a macro from 23 to 0 (`docs/ARTURIA.md`, test 9). The other
  choice is names only once a knob is turned, where no file gives them. Decide before the
  Arturia driver goes into the app.

  With that choice, the review also decides what a knob shows until its name comes (Adam,
  2026-11-14). The name field holds 12 characters, in the firmware's font; a trailing "?" already
  means "value not known". Options:
  1. The slot's own name, as now ("Macro 1", "Param 1"): short, but reads as if it were the
     real name, and for Analog Lab V it usually isn't.
  2. The slot's name marked as pending, by a sign of its own, e.g., "Macro 1~" or "·Macro 1",
     kept apart from the "?" for an unknown value.
  3. A hint, "Turn to name" (12 characters), on every knob not yet named: clear, but eight of
     them at once are noise, and it says nothing of which knob is which.
  4. Blank: honest, but a blank screen reads as "nothing here", which on this device means a
     knob with no control.
  The inference, unchecked, is that 2 is the best fit: a reader learns one sign once, the slot
  stays recognizable, and it is gone after the first turn. Check it on the device for legibility
  at playing distance (section 4 of AGENTS.md).
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
- **B1.** Pigments as a plugin in Bitwig Studio, the Roto-Control through `sbdev relay`: what the
  eight knobs are named (the preset's labels, "Macro 1", or nothing), with and without Show Remote
  Controls; whether a slow turn moves the parameter in finer steps than 1/127 (the plugin's
  window, or Bitwig's value); whether a change in the plugin's window moves the knob smoothly.
  **Run (test 16): "Macro 1" to "Macro 4" either way, and with Show Remote Controls four more
  parameters a page, cut at 12 characters; moves of 12 units of 16383 each changed the
  parameter; the knob followed the window smoothly.**
- **B2.** The same with Analog Lab V as a plugin: do its per-preset labels reach the Roto-Control,
  and when? **Run (test 16): yes, with Show Remote Controls on, as "P1 Color" and so on; without
  it the device showed names stored with old mappings. After a preset change, names came for
  knobs 1–3 and not for knob 4, twice; open.**
- **B3.** The KeyLab 61 mk3 beside it in Bitwig, on its own ports and integration: do both work at
  once with no relay between them, and what does the keyboard's screen show? **Begun (test 16):
  the keyboard moved the plugin's macro and showed its name and value; the Roto-Control's knob
  did not follow the first turn, and Bitwig sent it positions on the second. Finished (test
  17): with the keyboard in its DAW program and Device mode, and the track and the plugin
  selected in Bitwig, the knob followed in three turns of three, in steps of 1/200; a knob
  turned on the Roto-Control changed the parameter and did not show on the keyboard. In the
  keyboard's Arturia program the plugin changed and Bitwig was not told, in two turns of two.**
- **A11.** The relay with Pigments: the keyboard's picture, screen, and touch as without the tool;
  names on the Roto-Control from the files before any turn; a knob turned on each device moves
  the other, and a touch on the keyboard afterward doesn't jump the value back; notes play, with
  `status` giving the time in the tool; the value-text flash fix and names kept across presets.
  **Passed (`docs/ARTURIA.md`, test 9), after two fixes; about 0.03 ms in the tool.**
- **A12.** The relay with Analog Lab V: the asking names all eight knobs after a preset loads, one
  at a time, with no value text flashing; what it does to the preset. **Passed after two fixes
  (test 9): eight names about 2 s after a preset loads; every preset asked was marked changed in what
  Analog Lab V sent.**
- **A10.** Analog Lab V: do a preset's first four controls follow its file's macro labels, in
  order (`docs/ARTURIA.md`, section 5, item 11)? Until then no files are read for it.
- **A8.** The preset-file lookup for macro labels: a second instrument, a user preset, and two
  presets of one name. **Built for Pigments (2026-11-14; `docs/ARTURIA.md`, section 4): the file
  is found by the preset's name, type, and values, which leaves 2 of Pigments' 9,392 factory
  presets open. Four presets showed their labels on the device (test 9); a user preset and a
  second instrument are untried.**
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
5. Before more work on the standalone path: B1–B3, which say whether Bitwig is the better home
   for these instruments (Adam, 2026-11-14).

6. The review of section 10's questions with Adam, before choosing among them. First of them
   (Adam, 2026-11-14): whether a standalone instrument takes NRPN at more than 7 bits (section
   10, "Read on the web"), then the rest of B3. Both done, 2026-11-15: no, for Pigments, and
   test 17.

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

## 10. After the Bitwig tests: for review (Adam, 2026-11-14)

Nothing here is decided. Adam raised the questions; the answers are Claude's first reading, and
each "inference" or "guess" is marked.

**Three routes to an instrument's parameters**, cheapest first:

1. **Bitwig's own integration, improved** (below). Test 16 shows it already gives full
   resolution, value text, and Analog Lab V's labels. Performance Bridge's part stays the relay:
   MIX mode on TotalMix FX, PLUGIN mode to the DAW.
2. **The standalone path** (section 6), for playing with no DAW, with its limits: 7 bits, the
   start order, and writing to learn names in Analog Lab V.
3. **Performance Bridge, or a helper, as a plugin host.** It would get what any host gets (full
   resolution, every parameter, any maker's instruments, no imitation of a keyboard), but not
   Pigments' preset labels, which Pigments doesn't give its host (test 16). It would also own
   the audio: the device, buffer, and sample rate, MIDI from the keyboard, plugin windows and
   state, and a plugin's crash on stage. That makes the app a small live host, a role
   MainStage, Gig Performer, and Bitwig already fill. Audio Units through Apple's own classes
   would be the lightest form on a Mac (a guess at the size: a few hundred lines; not checked).

**What the standalone work is good for besides.**

- The preset-file readers are the only source found for Pigments' macro labels, in any host.
  Missing for that: which preset a hosted Pigments has loaded (Bitwig showed "init").
- `RotoNameFit` applies wherever names go to a 12-character field.
- The KeyLab mk3 as a hardware controller for TotalMix FX: its screen and controls take names,
  value text, and values (`docs/ARTURIA.md`, test 9). An inference; the keyboard's modes and
  sharing its port with an instrument are untested.
- Listening without writing: the relay sees the preset's name and each control's name and value.
- The driver's shape (a macro plugin made from a MIDI source, with holds and stale answers
  ignored) for hardware synthesizers in PLUGIN mode, with NRPN where a synthesizer has it.

**Questions these raise.**

1. Which matters most: playing with no DAW, or in one? Adam, 2026-11-15: full resolution is
   strongly preferred, which means a DAW or hosting the plugins, not the standalone path
   (7 bits; `docs/ARTURIA.md`, test 10). Most of his playing is live, not recording, so the
   host should be light, and in Bitwig he has to add gain every time to get the level up
   (both instrument tracks stood at -10.0 dB in the day's screenshots; whether that is the
   whole of it was not looked into).
2. Does another plugin format give the host Pigments' macro labels? (Test 16's was not noted.)
   For Audio Units there is a probe, `sbdev auhost` (branch `au-probe`; written on Linux and
   never compiled on a Mac): it prints the parameters an Audio Unit gives a host, and what
   changes when a preset does.
3. Does a plugin always tell its host when the keyboard moves a control? No (test 17): with
   the keyboard in its Arturia program, Analog Lab V changed and Bitwig was not told, in two
   turns of two. Through the keyboard's DAW program, in Device mode, the change is Bitwig's
   own, and the Roto-Control followed. Test 16's one turn that Bitwig did follow in the
   Arturia program is not explained.
4. Can a standalone instrument be controlled at more than 7 bits at all (14-bit control changes
   or NRPN through MIDI learn)? Not Pigments, by NRPN or by control changes 6 and 38
   (`docs/ARTURIA.md`, test 10); other pairs and the other instruments are untried. So the
   standalone path keeps its largest limit.
5. How does a host learn which preset a plugin has loaded?
6. Is Performance Bridge in the audio path acceptable on stage?
7. If a host, which plugin format? Audio Units are the cheapest to host on a Mac. Adam asks
   whether they have a name for being buggy or slow next to other formats; see below.

**Read on the web, 2026-11-14** (forum posts and one manual; none of it tested here).

- **Pigments and its macro names.** Users on Arturia's forum report that Pigments is the one
  Arturia instrument that gives neither a KeyLab's screen nor a DAW's automation lanes its
  macros' names, and that this was first asked for in 2020
  ([forum thread](https://forum.arturia.com/t/feature-request-display-macro-names-of-pigments-on-the-keylab-screen/7218)).
  That agrees with test 16 and with `docs/ARTURIA.md`, and says a host of any format is
  unlikely to get them (question 2), though only the probe would show it.
- **Changed parameter names, by format.** Plugin developers describe a way to announce a
  changed name in each of Audio Units, VST3, and AAX, with hosts differing in whether they act
  on it ([JUCE forum](https://forum.juce.com/t/audioprocessorvaluetreestate-parameter-name-change/34110)).
  In VST3 the announcement is a restart request, which a widely used framework has sent
  together with a latency change that some hosts answer with a glitch
  ([JUCE forum](https://forum.juce.com/t/vst3-parameter-name-changes-dont-work/28313/20)). So
  the recollection in question 7 that Audio Units tell a host less than VST3 does is not
  supported by what was found; nothing found bears on speed.
- **More than 7 bits, standalone** (question 4). An older Arturia manual (Moog Modular V 2.6)
  describes NRPN in the instrument's MIDI assignment window
  ([manual page](https://www.manualsdir.com/manuals/39764/arturia-moog-modular-26.html?page=58)).
  Whether today's instruments still take NRPN, and at what resolution, is a test: assign one
  in Pigments' MIDI tab and send it from `sbdev`. Run on 2026-11-15 (`docs/ARTURIA.md`, test
  10): Pigments learned the message as control change 6 and ignored its fine byte. A search
  engine's AI summary that Adam read the same day says the same of Arturia's current
  instruments, and that an NRPN setting in older ones was removed; its sources were not read.
- **CLAP** (Adam's question). Arturia does not appear to ship its instruments as CLAP plugins:
  a listing checked in June 2026 gives Pigments' formats as standalone, VST, VST3, AAX, Audio
  Unit, and NKS, and CLAP is a users' request on Arturia's forum
  ([forum thread](https://forum.arturia.com/t/feature-request-clap-support-and-per-voice-modulation/1448)).
  So a CLAP host would not load the instruments this plan is about. To confirm on the Mac:
  whether /Library/Audio/Plug-Ins/CLAP holds anything of Arturia's. It also means test 16's
  plugins were VST3 or VST2 (an inference: Bitwig hosts those and CLAP, not Audio Units).
- **Where extensions go.** Bitwig's guide gives Documents/Bitwig Studio/Extensions for a
  `.bwextension` file ([Bitwig](https://www.bitwig.com/en/community/control_scripts/installation_guide)).
  Nothing found says what happens when one there has the same identity as one that comes
  with Bitwig.

**Improving the Roto-Control's Bitwig integration** (Adam, 2026-11-14). The code is
MIT-licensed. The aim is to have changes accepted into the version most Bitwig users run. So
(Adam, the same evening, replacing "one pull request with everything"): small pull requests,
one per coherent change, to the author's fork (below), each prepared once it is understood and
tested in Bitwig, and opened on Adam's word; Adam introduces himself to the author before the
first. A commit keeps its usual co-author line, and a description says plainly what was tested
and how. What test 16 suggests:

1. **Names shortened, not cut.** Three test builds ran or were made on 2026-11-15
   (`docs/ROTO-CONTROL.md`, test 18), and the rule settled in three steps (Adam, that day):
   a name that fits on its screen is left whole; a word that has to be shortened gets the
   same short form wherever it is shortened; and an abbreviation from the list is final (it
   loses no letters afterward). `RotoNameFit` follows all three, with vowels dropped and
   words shortened from the end before anything is cut.

   The pull request is narrower (Adam, 2026-11-15, on the grounds that it reads better for
   most users and is easier for the author to take): common words are abbreviated, the last
   first, only in a name that doesn't fit; spaces are closed up if that alone makes it fit;
   and what still doesn't fit is cut as today. Each name is fitted alone, so nothing has to
   be sent again when another name changes. From the code's own output:

   | Full name | Cut at 12 (today) | The pull request |
   |---|---|---|
   | Reverb Volume | Reverb Volum | Reverb Vol |
   | Delay Volume | Delay Volume | Delay Volume |
   | P1 Brightness | P1 Brightnes | P1 Bright |
   | Env Amp Attack | Env Amp Atta | Env Amp Atk |
   | Env Amp Attack Curve | Env Amp Atta | EnvAmpAtkCrv |
   | Env 2 Release | Env 2 Releas | Env 2 Rel |
   | P1 Release Time | P1 Release T | P1 Rel Time |
   | P1 Low Shelf Gain | P1 Low Shelf | P1 Lo Shelf |
   | P1 High Shelf Gain | P1 High Shel | P1 Hi Shelf |
   | P1 Hammer Noise | P1 Hammer No | P1 Hammer No |
   | P1 Brilliance | P1 Brillianc | P1Brilliance |

   (The "Curve" name is an inference from test 16's cut names.) Kept outside this repository
   as a commit on the fork's `e0cd9eb`, now with joined words split (item 8) and five tests,
   which pass. A build with it (the fifth) ran in Bitwig with Analog Lab V (`docs/ROTO-CONTROL.md`,
   test 19): "Delay Volume" whole and "Reverb Vol", and with Pigments' two pages, where
   "EnvAmpAtkCrv" and "EnvAmpRelLnk" could be read on the device. Over the survey's 34,320 names (`docs/ARTURIA.md`, test 11) it changes 8,745,
   and the names that share their 12 characters with another of their plugin go from 26,324
   to 22,540. A later offer, if the author is receptive: where a cut
   leaves two names on a page the same, squeeze those two further.
2. **Stored names when Show Remote Controls is off** (`docs/ROTO-CONTROL.md`, section 8, item
   10). The cause is not found. In test 17 Bitwig did answer the stored mappings, once, in a
   state that was not identified.
3. **A name change that may not arrive** after a preset change (item 11).
4. **The position sent back** to a knob that just sent it. Looked harmless in test 16. In
   test 17 Bitwig sent back 196 positions during one turn of 352, most of them 1 above what
   the knob had sent and some after the knob had moved on, and Adam felt the knob resist once
   as the turn began; that the one caused the other is a guess (`docs/ROTO-CONTROL.md`,
   section 8, item 12). The published code holds a position back for 100 ms after the knob
   moves only on one of its layers (`docs/ROTO-CONTROL.md`, section 6).
5. From B3 (test 17): the answer to the Roto-Control's CONTROL MAPPED messages took 1.73 s once
   (117 ms in test 16). Nothing else for the extension; that the keyboard's screen doesn't
   show a turn of the Roto-Control is the keyboard's script's matter.
6. **The page count is not sent when it changes** (test 18): after a remote controls page was
   added in Bitwig, the Roto-Control's page buttons stopped at the old last page until
   another track had been selected. A small change of its own, drafted on the fork's
   `e0cd9eb` (send the plugin's details again when the count changes while the plugin is
   shown). Run in Bitwig (test 19): a page was added, the details came with four pages, and
   the Roto-Control reached the fourth with no track selected again. A page removed was
   followed the same way (test 20).
7. **Analog Lab V** (test 18; nothing to be written before the author has been asked, and not
   before the first pull requests are in; Adam, 2026-11-15). Three things would make its
   knobs read as its own window and the KeyLab do: dropping the "P1" before a part's
   parameter names; for a preset of two parts, showing the preset's own macros (plugin
   parameters without a prefix) in place of part 1's; and the FX knobs' names ("Chorus Mix"
   where Bitwig says "FXA Dry/Wet"; Adam: the standard to aim for, if it can be had). The
   extension already treats four of Bitwig's own devices by name, and no plugin of another
   maker; a general rule per plugin, with Analog Lab V as its first entry, is the likelier
   shape. Whether a preset of two parts can be told from one of one part is open: "P2
   Volume" read "0.000" in one and "-2.33" in the other, two presets in all.

   From the survey of the plugins' parameters (`docs/ARTURIA.md`, test 11): only Analog Lab V
   has the "P1" names, so dropping them touches no other plugin. Part 2's parameters load as
   "P2 Param0" to "P2 Param19"; if a Multi renames them (not seen), that tells a Multi by name.
   And the FX knobs' names can't come from Bitwig: the plugin has no parameter that says which
   effect a slot holds. They can come by Performance Bridge's relay, which has taken "Chorus
   Mix" from the instrument's messages to a KeyLab mk3 (`docs/ARTURIA.md`, test 9). With the
   plugin in Bitwig that would mean two programs writing names to the Roto-Control, Bitwig's
   extension and Performance Bridge; not tried. In that test the driver asked for each
   knob's name and had all eight within about 2 s of a preset's loading, with nothing
   touched, and the asking marked the preset as changed on the instrument's preset screen.
   Tried in a test build (test 19; not for a pull request as it stands): with a preset of
   one part the knobs read "Brightness", "Timbre", "Time", "Movement"; with a Multi the "P1"
   stayed, told by part 2's names as above. Two presets of each kind, of 30,802.
   The Roto-Control's menu screen shows no preset's name with the plugin in Bitwig (test
   19); the instrument does send it to a KeyLab (`docs/ARTURIA.md`, section 3), so the relay
   could supply that as well as the effects' names. Not tried.
8. **Two more changes to the names, from the survey** (`docs/ARTURIA.md`, test 11). Of 34,320
   parameters in 89 Arturia plugins, 92% have names longer than 12 characters and 77% share
   their first 12 with another parameter of their plugin.
   - Split joined words before abbreviating ("Env Amp AttackCurve"). Small; part of item 1.
     The table's "Env Amp Attack Curve" row was a wrong guess at that name.
   - Where every name on a page starts with the same words, drop them ("FX A1 Reverb
     Predelay", "FX A1 Reverb Decay", ... to "Predelay", "Decay", ...). Needs no plugin's
     name, so it singles none out; it does need a page fitted together, which item 1 avoids.
     A pull request of its own, later.
9. **Show Remote Controls has to be on** for the names and pages above, and Bitwig starts a new
   project with it off. Adam opens a new project each time and has to remember the panel, "a
   likely point of error" (2026-11-15). Three ways out, none tried:
   - A project saved with the panel open opens with it open (Adam, seen), and Bitwig can
     perhaps be set to start with a project. It holds for as long as he starts from that
     project, and only for the devices in it.
   - The extension could open the panel itself: Bitwig's API lets a controller set it
     (`Device.isRemoteControlsSectionVisible()` is settable in API 25, read from the API's
     classes), and the extension already has a preferences page. As a preference that is off
     unless chosen, because the author's design uses the panel as the user's switch between
     the Roto-Control's own learned mappings and Bitwig's pages. A third small pull request,
     to be asked about with the others.
     Drafted and run (`docs/ROTO-CONTROL.md`, test 20): with the preference on, a plugin
     added to a new project had its panel opened and its pages on the Roto-Control with
     nothing clicked. The code has a preferences class of the author's that nothing uses,
     so he may want it done there.
   - Performance Bridge hosting or relaying on its own doesn't depend on the panel at all;
     that weighs for it in section 10's first question, against the work it takes.
10. **Both at once: Bitwig for the values, the relay for what a host isn't told** (an idea from
    2026-11-15; nothing below is tried). In Bitwig the knobs have full resolution, pages, and
    Bitwig's value text, but a host is not told which effect an Analog Lab V slot holds or the
    preset's name (`docs/ARTURIA.md`, test 11; `docs/ROTO-CONTROL.md`, test 19). The
    instrument does tell a KeyLab both (`docs/ARTURIA.md`, test 9), and as a plugin in Bitwig
    it still talks to a KeyLab by itself (`docs/ROTO-CONTROL.md`, test 17).
    - The extension already reaches the Roto-Control through `sbdev relay`'s port. So
      Performance Bridge would not be a second writer of names: it could change a name in
      the extension's own message as it passes ("FXA Dry/Wet" to "Chorus Mix"), and add the
      preset's name to the plugin's.
    - It needs to know which of the instrument's controls is which knob. For Analog Lab V's
      first page the eight are in the keyboard's order (seen in tests 18 and 19); beyond
      that, not known.
    - Costs: Performance Bridge has to be running, which Adam wants light; the plugin has to
      be pointed at the relay's port; asking the instrument for names marked its preset as
      changed (test 9); and nothing here helps a plugin that is not Arturia's.
    - First tests, in order: does the plugin inside Bitwig answer a KeyLab's questions on a
      virtual port, with no keyboard; can one run of `sbdev` carry both relays (not checked);
      then the renaming.
11. **One app or two** (Adam and Claude, 2026-11-15; not decided). The relay is of use to
    someone with a Roto-Control, Arturia's instruments, and Bitwig, and no RME interface. But
    one program has to own the Roto-Control (section 2), and the relay already answers its
    MIX mode itself while passing PLUGIN mode to the DAW, which is what lets one Roto-Control
    serve TotalMix FX and Bitwig.
    - Adam likes one integrated app for an owner of all three, and a lighter one for people
      without RME, though two apps "could be more annoying to test".
    - Adam's other idea: one bridge app that loads modules to suit the user's hardware.
    - Claude's reading: the second gives most of the first at less cost, if "module" means
      a driver built into the app and switched on by what is connected or chosen, as the
      surfaces are now, and not code loaded at run time (which on macOS brings code signing
      and notarizing questions that were not looked into). An app with TotalMix FX not set
      up is then the lighter app. The name "Performance Bridge" already fits both.
    - The package is in libraries (`RotoControl`, `RotoRelay`, `ArturiaControl`), so a second,
      small product can still be added later without moving code. A separate repository
      only if the relay gets users of its own, or for the vendor material's sake.
    - Not looked at: what the app needs to change to carry the relay, and how the relay
      behaves when the app's window is closed or the app is busy.

**Where the extension's code is.** The extension Adam runs was not built from the code in
Melbourne Instruments' repository (test 16: it sends `0A 18` where that code sends `0A 0F`).
That repository has the extension as first committed in November 2025. Its author, Eric
Ahrens, keeps his later work (April to October 2026) in a fork,
[ericahrens/roto_control](https://github.com/ericahrens/roto_control), which does send `0A 18`.
His two pull requests offering that work to Melbourne Instruments' repository (October 2026)
were closed unmerged, with no comments, and the repository's one issue (July 2026) has no
answer. So:

- the draft of item 1 now applies to the fork's newest code (`e0cd9eb`), builds there against
  extension API 25, and its tests pass; it has still not run in Bitwig;
- Adam's was taken on 2026-11-14 for the one that comes with Bitwig Studio 6.1.4. Checked on
  his Mac on 2026-11-15, it is not: Documents/Bitwig Studio/Extensions holds
  `Roto-Control.bwextension`, dated 2026-07-15, with the fork's ID, version 1.0.2, and version
  date 29-05-26 (the same three as the fork's newest code and the draft's build, so they don't
  tell builds apart), and no `.jar` or `.bwextension` file inside the Bitwig Studio 6.1.4
  application names Melbourne Instruments or the Roto-Control. Adam recalls installing it,
  from Melbourne Instruments as far as he remembers. So this Bitwig Studio ships no copy, a
  build is tried by putting it in that folder in place of the July file, and a change reaches
  users through whoever hands out the file. Who does (Melbourne Instruments' download, the
  author, or a later Bitwig release) is not known, and the statements below about "Bitwig's
  copy" are open with it;
- the author also writes extensions that come with Bitwig: 458 of the 1,423 commits in
  Bitwig's public extensions repository
  ([bitwig/bitwig-extensions](https://github.com/bitwig/bitwig-extensions), counted
  2026-11-14) are his, from February 2021 to October 2026. The Roto-Control's extension is not
  in that repository, so where Bitwig builds it from is not known; his fork is the nearest
  public source (an inference that Bitwig's copy comes from the same work);
- in his own repositories he has merged four pull requests from outside, all from one
  contributor, in 2022 and 2023, each small and on one subject, and has not merged seven from
  another (2025 and 2026). That is the case for small, single-purpose pull requests to the fork.

That issue, from another integrator, also says two things worth checking before items 2 and 3:
that answering CONTROL MAPPED for a stored (learned) plugin caused problems and ignoring it
works, and that UNMAP CONTROL on a control with a stored mapping deletes the mapping for good.
Neither is tested here.
