# Roto-Control: what this project relies on

This is a working reference for the parts of Melbourne Instruments' Roto-Control protocol that
Surface Bridge uses, with the evidence for each statement. It is written in this project's own
words; it is not a copy of Melbourne Instruments' documentation. The `RotoControl` library
implements it.

**Sources.** Melbourne Instruments publishes the protocol and its own DAW integrations in
[Melbourne-Instruments/roto_control](https://github.com/Melbourne-Instruments/roto_control)
(commit 2d43a72, read 2026-10-29). The markers below say which part backs a statement:

- **[SysEx doc]**: the "ROTO-CONTROL SYSEX API", version 1.6 (dated 24 July 2026), listed there as matching ROTO-SETUP 3.0.1 to 3.2.0. It is not included in this repository.
- **[Serial doc]**: the "ROTO-CONTROL SERIAL API", version 1.3 (dated 26 November 2025). It is not included in this repository either.
- **[Ableton]**, **[Bitwig]**, **[Logic]**: Melbourne Instruments' integration code for each DAW, in the same repository (`src/ableton/ROTO_CONTROL.py`, `src/bitwig/…`, and `src/logic/config.lua`). Nothing from it is copied here.
- **[Bitwig guide]**: the 6-page "Melbourne Instruments Roto-Control" guide to the Bitwig Studio controller extension, in the same repository (`src/bitwig/src/main/resources/Documentation/…/Roto-Control.pdf`, created 9 November 2025). It is not included in this repository.
- **[test N]**: a test against a Roto-Control, described in section 9 with the firmware version.

A statement with no marker is an inference, and says so.

**Status.** Two tests so far (section 9), with firmware 3.3.0. Section 8 lists what the
next tests have to settle.

## 1. Two interfaces

- **SysEx and CCs over USB MIDI.** The Roto-Control talks to a DAW in both directions over its USB MIDI port: SysEx for track details, modes, and paging, and control change messages (CCs) for knobs, switches, and meters. [SysEx doc] This is the interface Surface Bridge uses.
- **A serial port.** A separate serial API, over a USB serial port, reads and writes the Roto-Control's stored setups and its mode. [Serial doc] Surface Bridge does not use it so far. A later version might use it to put the Roto-Control into MIX mode at startup.

## 2. SysEx framing and values

- **The frame.** Every SysEx message is `F0 00 22 03 02 <group> <command> <data> F7`. `00 22 03` is Melbourne Instruments' manufacturer ID, and `02` the Roto-Control's device ID. [SysEx doc]
- **Groups.** `0A` holds general commands, `0B` PLUGIN mode, and `0C` MIX mode. [SysEx doc] Surface Bridge uses `0A` and `0C`.
- **Numbers.** Bytes are 7-bit, as in all MIDI data.
  - A number that can exceed 127, such as a track index or a track count, takes two bytes, "two 7-bit values". [SysEx doc] The high seven bits come first. [Ableton, Bitwig]
  - An RGB color component (0–255) takes two bytes the same way: bit 7 first, then the low seven bits. [Logic]
- **Names.** A name is 13 bytes of ASCII, ending in a 0 byte and padded with 0 bytes. [SysEx doc] That leaves 12 visible characters. Ableton cuts names to 12 characters, and clears the top bit of each byte of a value string. [Ableton] Surface Bridge replaces anything outside printable ASCII with `?`; that choice is this project's.
- **Pacing.** Ableton waits 5 ms after each SysEx message it sends. [Ableton] The SysEx doc says nothing about pacing. `RotoControl` leaves pacing to the transport; whether the Roto-Control needs it is a question for testing (section 8).

## 3. The handshake

1. The host sends DAW STARTED (`0A 01`) when it starts, and then sends nothing more until the Roto-Control pings it. [SysEx doc]
2. The Roto-Control sends PING DAW (`0A 02`). It does so after DAW STARTED, and also when it is plugged into a computer. It repeats the ping every second for a minute while it looks for a host. [SysEx doc]
3. The host answers with DAW PING RESPONSE (`0A 03 <type>`), naming its DAW: `01` Ableton Live, `02` Bitwig Studio, or `03` Logic Pro. The SysEx doc lists no other type. [SysEx doc]
4. The Roto-Control sends ROTO-DAW CONNECTED (`0A 0C`). Only then may the host send other commands. [SysEx doc]

After CONNECTED, Ableton sends its track information and the meter thresholds. [Ableton] Bitwig
asks for the Roto-Control's firmware version (`0A 0D`). [Bitwig]

**Which type to claim.** Surface Bridge has to claim to be one of the three DAWs. Ableton's
integration answers `01`, Bitwig's `02`, and Logic's `03`. [Ableton, Bitwig, Logic] Some of the
Roto-Control's behavior depends on the type:

- With Logic, the Roto-Control sends page-left and page-right commands in MIX mode while a single track is in focus, expects transport status as CCs instead of SysEx, and reserves CCs 81–127. [SysEx doc] Ableton's code handles the two page commands anyway. [Ableton]
- Between Ableton and Bitwig, the SysEx doc names differences only in PLUGIN mode (two fields the Roto-Control ignores for Ableton), and none in MIX mode or in the general commands. [SysEx doc]

The inference is that Ableton (`01`) or Bitwig (`02`) suits Surface Bridge better than Logic,
because both use the SysEx commands that section 4 describes. `RotoHandshake` takes the type as a
setting, and the first tests should compare `01` and `02` (section 8).

**Reconnecting.** The SysEx doc does not say what a host should do if the Roto-Control pings again
after CONNECTED. The inference is that the Roto-Control was restarted or plugged in again, so
`RotoHandshake` answers the ping and waits for CONNECTED again.

## 4. MIX mode

The Roto-Control drives MIX mode, and the host answers.

**From the Roto-Control:**

| Command | Bytes | What it means |
|---|---|---|
| SET MIX ALL TRACKS MODE | `0C 01 <set> <knobs> <switches> <send>` | All-tracks mode: eight tracks, one per knob. `set` is audio tracks (`00`) or master and return tracks (`01`). `knobs` is level (`00`), pan (`01`), or a send (`02`). `switches` is mute (`00`), solo (`01`), or record arm (`02`). `send` is the 0-based send the knobs control in send mode. |
| SET MIX TRACK MODE | `0C 02 <page>` | Single-track mode: the controls of one track, in pages of eight. `page` is a page number (0, 1, 2), not the multiple of 8 the SysEx doc gives [test 2]; see "Single-track pages" below. |
| SET ALL TRACKS MODE | `0C 05 <set>` | The user switched between audio and master/return tracks. |
| SET FIRST TRACK | `0A 06 <first:2>` | The user paged the tracks; `first` is a multiple of 8. |
| ROTO SELECT TRACK | `0A 09 <index:2>` | The user selected a track. |
| TOGGLE TRACK GROUPING | `0C 06 <index:2>` | The user toggled grouping on the selected track. |
| REQUEST SEND TRACK NAMES | `0C 07 <send>` | The host should send the block of eight send names that holds `send`. |
| REQUEST TRANSPORT STATUS | `0A 0A` | The host should send TRANSPORT STATUS. |

All of these are from the SysEx doc.

**To the Roto-Control:**

| Command | Bytes | What it does |
|---|---|---|
| NUM TRACKS | `0A 04 <count:2>` | The number of tracks in the current set. |
| FIRST TRACK | `0A 05 <first:2>` | The current track page; `first` is a multiple of 8. |
| TRACK DETAILS | `0A 07 <index:2> <name:13> <scheme> <grouped>` | One track of the current page, followed after the page's tracks by TRACK DETAILS END (`0A 08`). |
| SET TRACK DETAILS | `0A 11 …` | As TRACK DETAILS, shown at once. |
| RESET TRACK DETAILS | `0A 12 <index:2>` | Clears a track's screen at once. |
| SET TRACK COLOUR | `0A 13 <index:2> <r:2> <g:2> <b:2>` | A track's color as RGB. |
| SHOW CONTROL VALUE | `0A 18 <kind> <control> <text:13>` | Shows a value on a knob's (`kind` `00`) or switch's (`01`) screen; the screen goes back to the control's name after a timeout. |
| TRANSPORT STATUS | `0A 0B <eight flags>` | Play, stop (always off), record, session record, loop, punch-in, punch-out, and re-enable automation, each `00` or `01`. |
| NUM SEND TRACKS | `0C 03 <count>` | The number of sends. |
| DAW SELECT TRACK | `0C 04 <index:2> <name:13> <scheme> <grouped>` | The host selected a track. |
| SEND TRACK NAMES | `0C 08 <start> <8 names>` | Eight send names, from `start`; a missing name is all 0 bytes. |
| REFRESH MIX MODE | `0C 09` | Asks the Roto-Control to redraw MIX mode. |
| DAW SELECT FOCUS TRACK | `0C 0A <index:2> <r:2> <g:2> <b:2>` | Selects the focus track, with its color. |
| SET MIX VU METER THRESHOLDS | `0C 0B <yellow> <red>` | Where the meters turn yellow and red, each 0–127; red must be above yellow. |

All of these are from the SysEx doc. `scheme` is an index (0–82) into the Roto-Control's color
table (the SysEx doc's Appendix A, not reproduced here), and `grouped` is `00` or `01`.

- **Single-track pages.** Ableton and Bitwig both put level on knob 1, pan on knob 2, and the first six sends on knobs 3–8 of the first page, and eight sends on each later page. [Ableton, Bitwig] They differ from the SysEx doc on how the page is numbered:
  - The SysEx doc says `page` is a multiple of 8 (0, 8, 16, …). [SysEx doc]
  - Ableton and Bitwig both treat it as a page number (0, 1, 2, …). With a multiple of 8, Ableton's arithmetic would point far past the sends. [Ableton, Bitwig]

  The Roto-Control sends page numbers. [test 2] `RotoOutgoing.sendNamesStart(forControlPage:numbering:)` handles both readings; drivers use `.pageNumbers`.
- **Which send names to send.** After SET MIX ALL TRACKS MODE or REQUEST SEND TRACK NAMES, the block starts at the multiple of 8 at or below the send index. [SysEx doc] After SET MIX TRACK MODE, the SysEx doc's examples (pages 0, 8, and 16 start at sends 0, 6, and 14) fit a block that starts at the page index minus 2, and at 0 for page 0. [SysEx doc] Read as page numbers, the same layout starts at 0 for page 0 and at 6 + (page − 1) × 8 after that, as in Ableton's code [Ableton], and that reading is the one the Roto-Control uses. [test 2]
- **When the screens are drawn.** The Roto-Control draws a single track's send labels when it gets DAW SELECT TRACK, not when it gets SEND TRACK NAMES; so after every SET MIX TRACK MODE the host sends the names, then DAW SELECT TRACK. On returning to all-tracks mode, the track screens are blank until the host sends the page again (NUM TRACKS, FIRST TRACK, and TRACK DETAILS). [test 2] Bitwig's code sends DAW SELECT TRACK on a single-track page change. [Bitwig]
- **Track colors.** The color scheme in TRACK DETAILS sets each strip's color, and the SysEx doc's table gives the colors seen. [test 2]
- **Meter thresholds.** Ableton uses 87 and 113; Logic 106 and 120. [Ableton, Logic]
- **Meter dimming.** Ableton also sends `0C 0C` with eight bytes, one per track of the page, which the SysEx doc does not list. Ableton sends 1 for an unmuted track and 0 for a muted one, or, while any track is soloed, 1 for soloed tracks and 0 for the rest. [Ableton] The inference is that 0 dims a track's meter. `RotoControl` can send it, marked as undocumented.

## 4a. PLUGIN mode

In PLUGIN mode the host lists "plugins" (Ableton's devices), and the user maps the Roto-Control's
controls to their parameters. The Roto-Control stores each mapping on the device, under a hash of
the plugin and a hash of the parameter. [SysEx doc, Ableton] Surface Bridge could present parts
of TotalMix as plugins, for example the control room or the selected channel's EQ; that use is
this project's idea, not Melbourne Instruments'.

**The flow, as Ableton's integration runs it** [Ableton]:

1. The Roto-Control sends SET PLUGIN MODE (`0B 01`). Ableton first sends the track page (NUM TRACKS, FIRST TRACK, TRACK DETAILS), then answers with NUM PLUGINS (`0B 02`), FIRST PLUGIN (`0B 03`), a PLUGIN DETAILS (`0B 05`) for each plugin on the page, PLUGIN DETAILS END (`0B 06`), and DAW SELECT PLUGIN (`0B 08`).
2. When the user selects a plugin, the Roto-Control sends ROTO SELECT PLUGIN (`0B 07`, the index on the page).
3. For each control it has a mapping for on that plugin, the Roto-Control sends CONTROL MAPPED (`0B 0B`) with the parameter's index and hash. The host finds the parameter (by hash; by index when two share a hash) and answers with LEARN PARAM (`0B 0A`), which carries the parameter's name and position. From then on the control's CCs (section 5) change that parameter. Ableton answers this way only for knobs, unless the parameter is a macro; the SysEx doc says to answer every CONTROL MAPPED, and `sbdev` does, for switches too, without visible harm. [Ableton, SysEx doc, test 2]
4. To make a mapping, the user turns on learn mode (the Roto-Control sends SET DEVICE LEARN (`0B 09`) on) and touches a control, whose screen shows LEARNING. The parameter is then chosen in the DAW, the host sends LEARN PARAM, and the Roto-Control answers with CONTROL LEARNED (`0B 11`). [Bitwig guide, test 2] Ableton sends LEARN PARAM whenever a parameter is selected while learn mode is on. [Ableton]

**What a parameter can carry** (LEARN PARAM) [SysEx doc]:

- a name, and a position (14 bits);
- a center detent, for knobs;
- or a number of steps: the SysEx doc gives 0 (continuous) or `02`–`18` hex, so 2–24, and names for each step when there are no more than `10` hex (16) steps. Ableton's integration caps steps at 24 and step names at 16 [Ableton], which agrees.

**Hashes.** A plugin's hash is 8 bytes and a parameter's 6, each byte 7-bit. [SysEx doc] Ableton
takes them from SHA-1 digests of the device's and parameter's names. [Ableton] The inference is
that the Roto-Control uses them only as names for stored mappings, so any stable hash will do;
`RotoHash.of` uses FNV-1a.

**Host-set control names.** SET PLUGIN CONTROL DETAILS (`0B 13`) names a control (0–63) and sets
its color, without learning. The SysEx doc says it is normally used in Logic's SMART mode. Whether
it works with another DAW type, and whether an unmapped control sends CCs at all, are open
(section 8).

**What test 2 found** (type `02`) [test 2]:

- PLUGIN DETAILS and this project's hashes are accepted: holding SEL shows the plugin names, and selecting one sends ROTO SELECT PLUGIN.
- An unmapped control sends its touch CC and nothing else, and SET PLUGIN CONTROL DETAILS does not name it. Every control has to be learned before it does anything.
- Learning works in the order the Bitwig guide gives: LEARN, then touch the control (its screen shows LEARNING; it sometimes took more than one touch), then LEARN PARAM from the host. CONTROL LEARNED came back 44–161 ms after LEARN PARAM. While learn mode is on, touching a knob sent no touch CC.
- On leaving learn mode, and after the host selects a plugin with mappings (DAW SELECT PLUGIN, including after the host restarts), the Roto-Control sends CONTROL MAPPED for every mapped control on the page. Once it also sent them with no message from the host before them (test 2, 235.558 s). The mappings are stored on the Roto-Control.
- A center detent settles the knob at 8191, the middle of the range (the host sent 8192).
- A switch mapped to a stepped parameter steps through the values itself, wrapping round, and sends each step as a share of 0–127: 0 and 127 for two steps; 42, 84, 127, and 0 for four. The step names were not shown; the inference is that the host is expected to show them with SHOW CONTROL VALUE, as Ableton's integration does with its value text. [Ableton]
- Once knob 1 had been learned under one plugin, it would not show LEARNING under another (seen); knob 2 could still be learned there. The inference is that a control mapped under one plugin can't be learned under another without UNMAP CONTROL first; untested.

**What PLUGIN mode lacks.** The meter CCs are listed for MIX mode only, and the per-track screens
and track paging are MIX-mode features. [SysEx doc]

## 5. CCs

All on MIDI channel 16. [SysEx doc] "Knob 1–8" means CC numbers in that order.

| Control | CC (decimal) | Values |
|---|---|---|
| Knobs 1–8 | 12–19 (high 7 bits) and 44–51 (low 7 bits) | 14 bits, 0–16383 |
| Switches 1–8 | 20–27 | 7 bits |
| Transport switches 1–8 | 28–35 | 7 bits |
| Knob touch 1–8 | 52–59 | 127 touched, 0 released |
| Level to 0 dB | 64 | the knob's index |
| Meters, tracks 1–8 | 65–80, in left and right pairs (65 and 66 for track 1) | 7 bits |

The CC numbers, that knobs are 14-bit and switches 7-bit, and the touch values are from the SysEx
doc, which only pairs the knob CCs. That CCs 12–19 carry the high 7 bits and CCs 44–51 the low 7
bits is from Bitwig's and Logic's code. [Bitwig, Logic] The rest:

- **Switch values.** In MIX mode, with the switches on record arm, a switch sends 127 on each press and nothing on release, and changes no state by itself: the host decides the new state and sets the light (section 6). [test 1, test 2] In PLUGIN mode a switch sends the mapped parameter's value instead (section 4a). [test 2] `RotoControlDecoder` reports the value as sent, and a driver reads it as a press or a value depending on the mode. Bitwig treats 127 as pressed and 0 as released. [Bitwig]
- **Transport switches.** Ableton reads them as play, stop, record, session record, loop, punch-in, punch-out, and re-enable automation. [Ableton] That order matches TRANSPORT STATUS. [SysEx doc] With type `02` the Roto-Control sends them in transport mode, 127 on press and 0 on release, and asks for TRANSPORT STATUS when that mode is entered. [test 2]
- **CCs 36 and 37.** Ableton also listens on these, the two CCs after the transport switches, for rewind and fast-forward. [Ableton, Bitwig] The SysEx doc does not list them. `RotoControl` reports them as other CCs.
- **CC 64.** The Roto-Control sends it, with a knob's index as the value, and Ableton then sets that knob's parameter to its default. [Ableton] The SysEx doc names it "level at 0 dB" without saying what triggers it. For TotalMix the inference is: set that strip's fader to 0 dB, which is position 836/1023 (`FaderCurve.unityPosition`).
- **Meters hold.** A meter has been observed to stay where it was set until the host sets it again; the host sends the falls as well as the rises. [test 2]
- **Meter values.** Ableton sends a track's meter as Live's meter reading (0–1) times 127, at most 12 times a second. [Ableton] How Live scales that reading is not in the integration, so the mapping from TotalMix's dB levels to 0–127 is this project's choice, still to be made.

## 6. Feedback to the Roto-Control

- **Moving a knob.** The host sends the same CC pair the knob sends: the high 7 bits on CC 12–19, then the low 7 bits on CC 44–51. [Bitwig, Logic] Bitwig computes the 14-bit value as the parameter (0–1) times 16383, rounded. [Bitwig]
- **Lighting a switch.** The host sends 127 (on) or 0 (off) on the switch's CC. [Ableton] In MIX mode, with the switches on record arm, this sets both the light and the label on the screen: with 127 the light is red and "ARM REC" shows as on; with 0 the light is off and the label gray. [test 2]
- **Moving a knob.** The motor follows the host's position: 0 dB (13388) put knob 1 at about 3 o'clock, and the range runs from about 7 o'clock (0) to about 5 o'clock (16383), 300° of travel. [test 2]
- **Past the ends.** The knob has no physical stop (seen) [test 2]. Past an end it has been observed to do three different things, and what decides between them is unknown:
  - In test 2's third run it went silent and resisted (seen). Forced on, it reported a position about 3,300–3,700 counts in from the other end and carried on from there. This happened nine times: five from 0 (reporting 13010–13078) and four from 16383 (reporting 3325–3693). [test 2]
  - In test 2's first run it went silent for 32–212 ms, then reported the other end (0 to 16383, or 16383 to 0) and carried on from there, ten times. [test 2]
  - In test 1 it went silent for 51–122 ms, reported 16383, and then came back to 0 three times; the fourth time it was released at 16383. [test 1]

  A driver must therefore treat a jump across most of the range as an end event, not as a new level: for a TotalMix fader, 0 to 16383 is off to +6 dB. Test 2's knob observations were all made in pan mode, test 1's in level mode.
- **Unchanged values.** Bitwig does not resend a knob position it last sent, except that it resends all eight positions when it switches layers or modes. [Bitwig]
- **Value text lasts about 2 seconds** on the screen before the name comes back, as the user timed it. [test 2]
- **Value text.** Ableton sends SHOW CONTROL VALUE whenever a mapped parameter's value changes, from the knob or from Live, at most 12 times a second with one trailing update, and once when a knob is touched. [Ableton] Bitwig sends value text only in PLUGIN mode, within 100 ms (plugin parameters) or 300 ms (macro parameters) of the knob last moving; in MIX mode it sends none. [Bitwig]
- **Bitwig's command for value text.** Bitwig sends value text as `0A 0F`, the number the SysEx doc gives REQUEST ROTO SYSEX API VERSION, with the same layout as SHOW CONTROL VALUE. [Bitwig, SysEx doc] The inference is that `0A 0F` is an older form, from before SHOW CONTROL VALUE was documented. `RotoControl` sends `0A 18`, as Ableton and Logic do. [Ableton, Logic]
- **Hold-off for the motors.** Bitwig holds back a knob position for 100 ms after the knob last moved on its master and return layer, and has the same rule commented out on its track layer. While touch automation is on, it also ignores the knob for 500 ms after release, and it queues knob positions while it switches modes. [Bitwig] Ableton leaves knob feedback to Live's framework, so its rule is not visible in the integration. [Ableton] Surface Bridge will need its own rule, because TotalMix confirms nothing (docs/TOTALMIX-OSC.md, test 5): a position from TotalMix is a change made elsewhere. The planned rule, an inference, was to hold back positions for a knob while it is touched; test 1 shows a knob turning before its touch CC, so the rule will also have to count recent movement.

## 7. Errata in the SysEx doc

Noted so that nobody builds on them:

- Two sections are numbered 2.21.
- The PLUGIN headings for 3.26–3.29 use command numbers `20`–`23`, but the overview, and Logic's code, use `1A`–`1D`. [SysEx doc, Logic]
- DAW SELECT TRACK (4.4) shows the color field as `CS` in the command but defines it as `CI`. The field is the color scheme, as in TRACK DETAILS.
- The overview gives ROTO SELECT PLUGIN (`0B 07`) as sent to the Roto-Control, though its name says the Roto-Control selected the plugin. Surface Bridge does not use PLUGIN mode.
- Appendix A writes one green value as "BO" (letter O), presumably `B0`.
- Appendix B's Logic formula for a mapped parameter's CC number divides where Logic's code takes the remainder. [SysEx doc, Logic] PLUGIN mode only.
- In PLUGIN mode, the overview also gives the wrong direction for SET PLUGIN LEARN (`0B 09`) and FIRST PLUGIN (`0B 03`), and 3.26 calls both halves of the sweep value "LSB". Logic's code uses a PLUGIN command, `0B 1E`, that the SysEx doc does not list. [SysEx doc, Logic]

## 8. Open questions

Settled by tests 1 and 2 (section 9): the handshake with type `02`; the knob CCs (both, high then
low, every time; 0–16383); that host moves are not echoed; motor moves; the single-track page
numbering; transport switches; switch and light behavior with the switches on record arm; and,
in PLUGIN mode, host-set names, unmapped controls, learning, stored mappings, detents, and steps.

1. **The handshake with type `01`.** Does MIX mode behave the same as with `02`?
2. **What MIX mode needs from the host.** Which of NUM TRACKS, FIRST TRACK, and TRACK DETAILS does the Roto-Control need before it shows strips? (`--setup none`.)
3. **Pacing.** Does the Roto-Control drop SysEx sent without Ableton's 5 ms gaps? (`--gap 0`.)
4. **CC 64.** What gesture sends it?
5. **Switches in mute and solo modes.** Do they behave as in record-arm mode?
6. **SET PLUGIN MODE's data byte.** What does it mean?
7. **Relearning a control.** Does UNMAP CONTROL let a control mapped under one plugin be learned under another?
8. **Step names.** Does SHOW CONTROL VALUE show a stepped switch's value, and does LEARN PARAM's step names list show anywhere?
9. **Host-set names with type `03`.** Does SET PLUGIN CONTROL DETAILS work when the host claims Logic?
10. **The ends of the knob's range.** What decides between holding, wrapping, and bouncing back (speed, mode, or something else)? Is the jump on release always about 3,300 counts?

## 9. Tests

Run with `sbdev roto` (macOS), which prints every message in both directions with the time since
starting and takes commands for knobs, lights, meters, screens, and PLUGIN mode. Times of messages
that arrive while `sbdev` is still sending a reply are the times it could read them, not arrival
times.

### Test 1 (2026-10-29): handshake, MIX mode, knobs, and feedback

**Setup.** Roto-Control firmware 3.3.0 (commit `eaa37b0`), SysEx API 1.6, as the Roto-Control
reported them. macOS, one MIDI source and one destination named "Roto-Control". `sbdev roto --raw`
claiming Bitwig (`02`), with the default setup (16 tracks, 4 sends, 5 ms after each SysEx).

**Findings:**

- **The handshake.** DAW STARTED was answered by PING DAW within 1 ms. CONNECTED came within 5 ms of DAW PING RESPONSE; `sbdev` pauses 5 ms after each SysEx inside the MIDI callback, so the log cannot show less. The firmware and API versions came back in one packet, logged at 0.099 s. That is the first moment `sbdev` could read it, after its reply to CONNECTED, so the Roto-Control's own delay is unknown.
- **SET PLUGIN MODE with data.** The Roto-Control sent SET PLUGIN MODE straight after CONNECTED (the inference is that it was in PLUGIN mode), with one data byte (`00`) that the SysEx doc does not list. Bitwig's integration reads one byte there. [Bitwig] Its meaning is unknown.
- **MIX mode.** Switching to MIX mode sent SET MIX ALL TRACKS MODE (audio tracks, level, record arm, send 0). The host's NUM SEND TRACKS and SEND TRACK NAMES drew no error.
- **Touch and select.** Touching a knob sent ROTO SELECT TRACK for its track and then the touch CC, within 1 ms. Release sent the touch CC with 0.
- **Knob CCs.** Every update carried both CCs, high then low, even when the high value had not changed. Updates came about every 11 ms while a knob turned. The values covered 0 to 16383.
- **Touch can trail turning.** Once, knob 1 sent six position updates (27.540 s to 27.747 s) before its touch CC (27.747 s). A rule that holds back positions only while a knob is touched would miss that.
- **The jump to 16383.** Four times (knob 1 once, knob 2 three times), a knob turned down to 0 next reported 16383, 51–122 ms later. Three times it reported 0 again 111–321 ms after that; the fourth time it was released at 16383. See section 6.
- **Switches.** Switches 1 and 2 sent 127 on each press, twice each, and nothing on release, with the switches in record-arm mode.
- **No echo of host moves.** After `knob 1 0dB` and a sweep of knob 1 from 0 to 16383, the Roto-Control sent no CCs back.
- **Not recorded.** Whether the knob moved, the light lit, the meters showed, or "hello" appeared on knob 1's screen. Test 2 repeated these with notes.


### Test 2 (2026-10-29): feedback, single-track mode, transport, and PLUGIN mode

**Setup.** As in test 1 (firmware 3.3.0, `eaa37b0`; type `02`), in four runs of `sbdev roto --raw`
on branch `roto-midi`, the later runs with the changes made during the test (16 sends; send names
and DAW SELECT TRACK on single-track pages; the track page on returning to all-tracks mode). The
user noted what the Roto-Control showed and did; those notes are marked "seen" below. Clock
positions are approximate. Knobs were in pan mode (`0C 01 00 01 02 00`) throughout MIX mode.

**MIX mode:**

- **Track colors** (seen). Schemes 0, 11, 22, 33, 44, 55, 66, and 77 showed as pink, purple, blue, green, brownish gray, gray, royal blue, and red-brown, matching the SysEx doc's table, except that scheme 66 (a purple in the table) looked royal blue.
- **Knob range** (seen). No physical end stop. `sweep 1` took the knob from about 7 o'clock to about 5 o'clock, and `knob 1 0dB` to about 3 o'clock.
- **End stops.** Turned down past 0, the knob held (seen: resistance) and sent nothing. Turned on round, it let go and reported a position near the top. In the third run this happened five times from 0 (13010–13078) and four times from 16383 (3325–3693); for example, knob 1 sat at 0 from 195.236 s and next reported 13026 at 207.057 s. In the first run the knob instead wrapped without holding, ten times: for example, 0 at 20.008 s, then 16383 at 20.200 s and 16346 at 20.981 s.
- **Switches.** In record-arm mode, presses sent 127 and nothing on release. Seen: the screen showed "ARM REC" and a press made the light brighter; a press did not switch arm on or off. `led 1 on` lit the light red and showed "ARM REC" as on; `led 1 off` turned the light off and grayed the label.
- **Meters** (seen). `meter 1 100` filled the yellow part of the meter (thresholds 87 and 113) and the meter stayed there.
- **Value text** (seen). `show 1 hello` showed for about 2 seconds. `name 1 analog 1` renamed track 1's screen.
- **Single-track mode.** With 4 sends claimed, > did not page. With 16, SET MIX TRACK MODE carried 0, 1, and 2 for the three pages (seen: level, pan, and six sends; eight sends; two sends). Send labels showed only after DAW SELECT TRACK; once `sbdev` sent it after the names on every page, they showed on every page (seen). On returning to all-tracks mode the track screens were blank until the page was sent again (seen); once `sbdev` sent it on SET MIX ALL TRACKS MODE, they showed at once (seen).
- **Transport.** Entering transport mode sent REQUEST TRANSPORT STATUS. The eight transport switches sent CCs 28–35, 127 on press and 0 on release, each release 70–90 ms after its press.

**PLUGIN mode:**

- NUM PLUGINS, FIRST PLUGIN, four PLUGIN DETAILS, PLUGIN DETAILS END, and DAW SELECT PLUGIN were sent on SET PLUGIN MODE. Seen: no names on the screens until SEL was held, then the four plugin names.
- `ctl 1 main vol` (SET PLUGIN CONTROL DETAILS) showed nothing (seen); turning unmapped knob 1 sent only its touch CC.
- Learning knob 1 to "Main Vol": LEARN, then touches until LEARNING showed (seen), then `learn 1`; CONTROL LEARNED came 110 ms after LEARN PARAM, and the screen showed LEARNED and "Main Vol" (seen). On leaving learn mode the Roto-Control sent CONTROL MAPPED for knob 1 with this project's parameter hash; after `sbdev`'s LEARN PARAM answer (position 13388), the knob's first reported position was 13522.
- After quitting and restarting `sbdev`, the Roto-Control sent CONTROL MAPPED for knob 1 by itself, 52 ms after DAW SELECT PLUGIN.
- Switch 1 learned to "Dim" (two steps) sent 127, then 0, on successive presses; switch 2 learned to "Main Out" (four steps) sent 42, 84, 127, and 0. Seen: the screen showed the names ("Main Vol | Dim") but no step names, and did not change on a press.
- Under "Ch EQ", knob 1 would not show LEARNING in learn mode (seen), including after turning learn mode off and on three times; knob 2 would. The log has no LEARN PARAM for knob 1 under "Ch EQ". It also has two SET DEVICE LEARN off in a row (369.264 s, 372.545 s). Knob 2 learned to "Gain 1" (center detent) settled at 8191 (seen: a detent at 12 o'clock); the host had sent 8192.
