# PLUGIN mode: the plan

This is a plan, not a record. It sets out how Performance Bridge could use the Roto-Control's
PLUGIN mode, what is known, and the tests that decide each part. Nothing here is in the app. What
exists is for the tests: the probe (`sbdev vport`), the `ArturiaControl` library, and three
prototypes that have run on no device (`sbdev roto`'s macro commands, `sbdev relay`, and `sbdev
arturia`). Statements about the Roto-Control rest on
`docs/ROTO-CONTROL.md`, and those about Arturia's instruments on `docs/ARTURIA.md`; statements
about Melbourne Instruments' Bitwig Studio and Logic Pro integrations come from reading their code
in [roto_control](https://github.com/Melbourne-Instruments/roto_control) (commit 2d43a72) on
2026-11-13 (the Bitwig integration by two readers, the second checking the first) and have not
been tested unless a test is named. Everything else is a proposal.

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
  again, so on its DAW STARTED the relay tells it (untested).
- **Going back to MIX mode.** Bitwig writes its own track list to the device while in PLUGIN
  mode, so Performance Bridge must draw its page again. It already does on SET MIX ALL TRACKS
  MODE.
- **Ports.** The integration looks for ports named "Roto-Control" but has no check of its own on
  the name; Melbourne Instruments' guide says the ports can be chosen by hand in Bitwig's
  controller settings. The inference is that Bitwig will also add the integration on the device's
  real ports by itself, and that the user must remove that one.

What the user gets is what Bitwig's integration gives: remote-control pages mapped to the eight
knobs with no learning, or learned mappings stored on the device, with names, motor positions, and
value text. An Arturia plugin in Bitwig is reached this way, with 14-bit knobs.

## 4. Transport, for Bitwig

The transport switches can go to Bitwig while the knobs stay in MIX mode on TotalMix FX, since
TotalMix FX has no transport and the integration's transport switches work apart from its knobs.
Forward REQUEST TRANSPORT STATUS and CCs 28–37; pass back TRANSPORT STATUS and CCs 28–35; drop the
rest. Two things to know: the loop and punch-in flags in the integration's TRANSPORT STATUS are
filled from the wrong settings (an apparent bug in its code; the lights it sends as CCs afterward
are right), and its stop light is lit while playing.

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

## 7. Tests, in order

Arturia (each a few minutes with `sbdev vport`):

- **A1.** Start Pigments with the port already turned on. Do the values come?
- **A2.** MiniFreak V, a V Collection instrument, and Analog Lab V in place of Pigments.
- **A3.** "KeyLab 25" in place of "KeyLab 61".
- **A4.** Assign another parameter to control change 74 by MIDI learn. Does it report as item 1?
- **A5.** Two instruments at once, on two port names.
- **A6.** Adam's KeyLab 61 mk3 with the same instrument afterward: does it still work as before?

Roto-Control:

- **R1.** From `sbdev roto`: a macro plugin with no learning on the device, first as Bitwig does it
  (`macro --wait`: LEARN PARAM only in answer to CONTROL MAPPED), then unasked (`macro`). Do names
  and positions show, and do the knobs then send?
- **R2.** A relay in `sbdev` between the device and Bitwig Studio, in PLUGIN mode only.
- **R3.** A new handshake as `03` and back to `02` without unplugging: does the device change
  type cleanly, and how long does it take?
- **R4.** Transport to Bitwig Studio while in MIX mode. Watch what the device sends on leaving
  transport mode: the relay ends transport only on SET PLUGIN MODE or a MIX-mode message.

If R1 passes, `sbdev arturia` puts the two halves together: the Roto-Control's PLUGIN mode on a
standalone instrument, with values marked unknown until the instrument reports them.

## 8. Order of work

1. Tests A1–A6 and R1: they settle whether the Arturia driver is worth building and how.
2. The Bitwig relay in `sbdev` (R2, R4), then in the app, with a setting for the virtual port and
   a Setup Guide page for Bitwig's controller settings.
3. The Arturia driver, if step 1 says so.
4. Logic (R3 first).

Each step merges only after the review its tier calls for; until then it lives on a test branch.

## 9. For `docs/ROTO-CONTROL.md`, once checked

The reading of Bitwig's integration found things section 4a doesn't have yet. They are code
readings, to be added with their source once a second reader or a test has confirmed them:

- the macro plugin path (section 6 above), against 4a's "every control has to be learned";
- that Bitwig does not send the track page on SET PLUGIN MODE, as Ableton does;
- that Bitwig also takes its hashes from SHA-1, of the device's name and the parameter's full ID;
- that in PLUGIN mode Bitwig reads and lights a switch as a 0–127 value, not only as on and off;
- that Bitwig handles SET FIRST PLUGIN, SET PLUGIN ENABLED, SET PLUGINS LOCK, MACRO PLUGIN PAGE
  INDEX, and TOGGLE REMOTE PAGE, and that DAW SELECT PLUGIN carries three bytes;
- an erratum in the serial API document: ADD PLUGIN's command is printed with SET PLUGIN's bytes;
- an apparent bug in Bitwig's integration, not to be copied: it unmaps a macro knob with control
  type `01`, which the SysEx doc gives to switches.
