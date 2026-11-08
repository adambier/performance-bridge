# Roto-Control: what this project relies on

This is a working reference for the parts of Melbourne Instruments' Roto-Control protocol that
Performance Bridge uses, with the evidence for each statement. It is written in this project's own
words; it is not a copy of Melbourne Instruments' documentation. The `RotoControl` library
implements it.

**Sources.** Melbourne Instruments publishes the protocol and its own DAW integrations in
[Melbourne-Instruments/roto_control](https://github.com/Melbourne-Instruments/roto_control)
(commit 2d43a72, read 2026-10-29). The text calls the SysEx API document there "the SysEx doc".
Neither API document is included in this repository, and nothing from the integration code is
copied here.

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote saying where it comes from: one of Melbourne Instruments' documents or
integrations, or a test against a Roto-Control, described in section [9](#9-tests) with the
firmware version. Where something is reasoning that has not been checked, the text says so in
words ("inference", "untested").

[^sysex-1.6]: Melbourne Instruments' "ROTO-CONTROL SYSEX API" (the SysEx doc), version 1.6, dated
    24 July 2026, listed in roto_control as matching ROTO-SETUP 3.0.1 to 3.2.0.
[^serial-1.3]: Melbourne Instruments' "ROTO-CONTROL SERIAL API", version 1.3, dated 26 November
    2025.
[^ableton]: Melbourne Instruments' Ableton Live integration, `src/ableton/ROTO_CONTROL.py` in
    roto_control.
[^bitwig]: Melbourne Instruments' Bitwig Studio controller extension, `src/bitwig/…` in
    roto_control.
[^logic]: Melbourne Instruments' Logic Pro integration, `src/logic/config.lua` in roto_control.
[^logic-sysex]: Melbourne Instruments' Logic Pro integration (`src/logic/config.lua` in
    roto_control), its `process_sysex_command`.
[^logic-read]: Melbourne Instruments' Logic Pro integration (`src/logic/config.lua` in
    roto_control), as read for this project on 2026-11-01.
[^bitwig-guide]: Melbourne Instruments' 6-page "Melbourne Instruments Roto-Control" guide to the
    Bitwig Studio controller extension, in roto_control
    (`src/bitwig/src/main/resources/Documentation/…/Roto-Control.pdf`, created 9 November 2025).
    It is not included in this repository.
[^manual]: Melbourne Instruments' Roto-Control user manual, version 1.1.4 (16 April 2025), from
    their [support page](https://www.melbourneinstruments.com/support). It predates the firmware
    tested here, so it is used only for the names of the front-panel buttons and screens.
[^release-notes]: Melbourne Instruments' ROTO-SETUP release notes, on the same support page: 2.1.0
    (28 October 2025), 3.0.1 (15 January 2026), 3.1.0 (23 February 2026), and 3.2.0 (3 June 2026).
[^test-1]: [Test 1](#test-1-2026-10-29-handshake-mix-mode-knobs-and-feedback) (2026-10-29),
    section 9; firmware 3.3.0.
[^test-2]: [Test 2](#test-2-2026-10-29-feedback-single-track-mode-transport-and-plugin-mode)
    (2026-10-29), section 9; firmware 3.3.0.
[^test-3]: [Test 3](#test-3-2026-10-30-the-open-questions) (2026-10-30), section 9; firmware
    3.3.0.
[^test-4]: [Test 4](#test-4-2026-10-30-rotodriver-with-totalmix-fx-through-sbdev-bridge)
    (2026-10-30), section 9; firmware 3.3.0.
[^test-5]: [Test 5](#test-5-2026-11-01-where-the-02-indent-is-and-send-knobs) (2026-11-01),
    section 9; firmware 3.3.0.
[^test-6]: [Test 6](#test-6-2026-11-01-the-hold-rule-and-a-power-cycle) (2026-11-01), section 9;
    firmware 3.3.0.
[^test-7]: [Test 7](#test-7-2026-11-01-the-fx-label) (2026-11-01), section 9; firmware 3.3.0.
[^test-12]: [Test 12](#test-12-2026-11-04-the-tape-and--buttons-mute-master-flashing-and-the-menu-screen)
    (2026-11-04), section 9; firmware 3.3.0.
[^totalmix-test-5]: Test 5 (2026-10-28) of the TotalMix FX tests,
    [docs/TOTALMIX-OSC.md](TOTALMIX-OSC.md#test-5-2026-10-28-does-totalmix-fx-echo-a-command),
    section 6.
[^totalmix-meters]: [docs/TOTALMIX-OSC.md](TOTALMIX-OSC.md#3-addresses-this-project-uses),
    section 3, "Meter colors".

**Status.** Twelve tests so far (section 9), with firmware 3.3.0. Section 8 lists what is still
open.

## 1. Two interfaces

- **SysEx and CCs over USB MIDI.** The Roto-Control talks to a DAW in both directions over its USB MIDI port: SysEx for track details, modes, and paging, and control change messages (CCs) for knobs, switches, and meters.[^sysex-1.6] This is the interface Performance Bridge uses.
- **A serial port.** A separate serial API, over a USB serial port, reads and writes the Roto-Control's stored setups and its mode.[^serial-1.3] Performance Bridge does not use it yet. A later version might use it to put the Roto-Control into MIX mode at startup.

## 2. SysEx framing and values

- **The frame.** Every SysEx message is `F0 00 22 03 02 <group> <command> <data> F7`. `00 22 03` is Melbourne Instruments' manufacturer ID, and `02` the Roto-Control's device ID.[^sysex-1.6]
- **Groups.** `0A` holds general commands, `0B` PLUGIN mode, and `0C` MIX mode.[^sysex-1.6] Performance Bridge uses all three.
- **Numbers.** Bytes are 7-bit, as in all MIDI data.
  - A number that can exceed 127, such as a track index or a track count, takes two bytes, "two 7-bit values".[^sysex-1.6] The high seven bits come first.[^ableton][^bitwig]
  - An RGB color component (0–255) takes two bytes the same way: bit 7 first, then the low seven bits.[^logic]
- **Names.** A name is 13 bytes of ASCII, ending in a 0 byte and padded with 0 bytes.[^sysex-1.6] That leaves 12 visible characters. Ableton cuts names to 12 characters, and clears the top bit of each byte of a value string.[^ableton] Performance Bridge replaces anything outside printable ASCII with `?`; that choice is this project's.
- **Pacing.** Ableton waits 5 ms after each SysEx message it sends.[^ableton] The SysEx doc says nothing about pacing. With no pause at all, the Roto-Control took a full track page and a full plugin page without losing a message.[^test-3] `RotoControl` leaves pacing to the transport. `RotoDriver` draws a page at most once every 100 ms (`pageDrawInterval`); a page that changes sooner is drawn once, when the interval is up. Before this, at every connection, TotalMix FX's answer to `/sendall` redrew the page about 33 times in 0.35 s (review of 2026-11-02), and bursts of SysEx have preceded freezes (test 4, runs 17–19). That the burst could freeze the Roto-Control is an inference (Adam, 2026-11-02).

## 3. The handshake

1. The host sends DAW STARTED (`0A 01`) when it starts, and then sends nothing more until the Roto-Control pings it.[^sysex-1.6]
2. The Roto-Control sends PING DAW (`0A 02`). It does so after DAW STARTED, and also when it is plugged into a computer. It repeats the ping every second for a minute while it looks for a host.[^sysex-1.6]
3. The host answers with DAW PING RESPONSE (`0A 03 <type>`), naming its DAW: `01` Ableton Live, `02` Bitwig Studio, or `03` Logic Pro. The SysEx doc lists no other type.[^sysex-1.6]
4. The Roto-Control sends ROTO-DAW CONNECTED (`0A 0C`). Only then may the host send other commands.[^sysex-1.6]

After CONNECTED, Ableton sends its track information and the meter thresholds.[^ableton] Bitwig
asks for the Roto-Control's firmware version (`0A 0D`).[^bitwig]

**Which type to claim.** Performance Bridge has to claim to be one of the three DAWs. Ableton's
integration answers `01`, Bitwig's `02`, and Logic's `03`.[^ableton][^bitwig][^logic] Some of the
Roto-Control's behavior depends on the type:

- With Logic, the Roto-Control sends page-left and page-right commands in MIX mode while a single track is in focus, expects transport status as CCs instead of SysEx, and reserves CCs 81–127.[^sysex-1.6] Ableton's code also handles the two page commands.[^ableton]
- Between Ableton and Bitwig, the SysEx doc names differences only in PLUGIN mode (two fields the Roto-Control ignores for Ableton), and none in MIX mode or in the general commands.[^sysex-1.6] In use they differ in MIX mode too[^test-3]:
  - With `01`, level knobs have a 0 dB indent at 13926 (0.85 of the range, where Live puts 0 dB), and the Roto-Control sends CC 64 when a knob lands in it (section 5).
  - With `02` there is no indent at 13926 and no CC 64[^test-3]; there is an indent lower down, felt where a TotalMix FX fader reads "-0.8 dB", about 0.79 of the range (seen, 2026-10-30, with `sbdev bridge`). The inference is that it is Bitwig's 0 dB, which on a volume law of twice the cube of the position is at 0.5 raised to 1/3, 0.794 (count 13003); that law is from memory of Bitwig, not from Melbourne Instruments' code. Test 5 measured it at 13004. With `RotoDriver`'s scale bent to put 0.794 at TotalMix FX's 0 dB (below), the indent was felt at 0.0 dB (seen, 2026-10-30), which fits the inferred position to within what a hand can feel. The indent caught the knob at 0 dB reliably (seen).
  - With `01`, switches send 0 on release as well as 127 on press; with `02`, nothing on release.
  - The solo color differs: yellow with `02`, blue with `01` (seen).
- With `03`, PLUGIN mode never settled with the Bitwig-style replies `sbdev` sends: the Roto-Control sent SET PLUGIN MODE again about every 200 ms (section 4a).[^test-3]

The handshake itself, MIX mode's messages, and the stored PLUGIN-mode mappings were the same
with `01` and `02`.[^test-3] Neither type's indent is at TotalMix FX's 0 dB, which is at 0.817 of the
range: `01`'s, at 0.85, would read about +1.1 dB on a TotalMix FX fader, and `02`'s about −0.8 dB.
`RotoDriver` therefore bends the scale of level and send knobs, linearly on each side of the
indent, so that the indent is TotalMix FX's 0 dB. The inference is that `02` suits Performance Bridge
better: no CC 64 to ignore, and switches that give the same press messages without release
messages. `RotoHandshake` takes the type as a setting.

**A firmer indent.** Neither the SysEx API (1.6) nor the serial API (1.3) has a setting for how strongly an indent holds; they set only where indents are (for MIDI-mode setups and PLUGIN-mode controls).[^sysex-1.6][^serial-1.3] A "magnet" was tried on 2026-10-30 with `sbdev bridge`: once a level knob had sent nothing for 200 ms within a window of the indent, the host moved it into the indent and set 0 dB. It pulled nothing while the knob was being turned, only moved it afterward (seen: visible from about −6 dB, hard to see from −3 dB), so it felt like a delayed jump rather than a firmer indent, and it would move a knob left near 0 dB on purpose. It was removed.

**Reconnecting.** The SysEx doc does not say what a host should do if the Roto-Control pings again
after CONNECTED. The inference is that the Roto-Control was restarted or plugged in again, so
`RotoHandshake` answers the ping and waits for CONNECTED again.

## 4. MIX mode

The Roto-Control drives MIX mode, and the host answers.

**From the Roto-Control:**

| Command | Bytes | What it means |
|---|---|---|
| SET MIX ALL TRACKS MODE | `0C 01 <set> <knobs> <switches> <send>` | All-tracks mode: eight tracks, one per knob. `set` is audio tracks (`00`) or master and return tracks (`01`). `knobs` is level (`00`), pan (`01`), or a send (`02`). `switches` is mute (`00`), solo (`01`), or record arm (`02`). `send` is the 0-based send the knobs control in send mode. |
| SET MIX TRACK MODE | `0C 02 <page>` | Single-track mode: the controls of one track, in pages of eight. `page` is a page number (0, 1, 2), not the multiple of 8 the SysEx doc gives[^test-2]; see "Single-track pages" below. |
| SET ALL TRACKS MODE | `0C 05 <set>` | The user switched between audio and master/return tracks. |
| SET FIRST TRACK | `0A 06 <first:2>` | The user paged the tracks; `first` is a multiple of 8. |
| ROTO SELECT TRACK | `0A 09 <index:2>` | The user selected a track. |
| TOGGLE TRACK GROUPING | `0C 06 <index:2>` | The user toggled grouping on the selected track. Pressing the (+) button by itself sends nothing; it blinks green until pressed again (seen).[^test-12] |
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
| SHOW CONTROL VALUE | `0A 18 <kind> <control> <text:13>` | Shows a value on a knob's (`kind` `00`) or switch's (`01`) screen; the screen goes back to the control's name after a timeout. A switch's value has not been seen to show (section 6). |
| TRANSPORT STATUS | `0A 0B <eight flags>` | Play, stop (always off), record, session record, loop, punch-in, punch-out, and re-enable automation, each `00` or `01`. |
| NUM SEND TRACKS | `0C 03 <count>` | The number of sends. |
| DAW SELECT TRACK | `0C 04 <index:2> <name:13> <scheme> <grouped>` | The host selected a track. |
| SEND TRACK NAMES | `0C 08 <start> <8 names>` | Eight send names, from `start`; a missing name is all 0 bytes. |
| REFRESH MIX MODE | `0C 09` | Asks the Roto-Control to redraw MIX mode. |
| DAW SELECT FOCUS TRACK | `0C 0A <index:2> <r:2> <g:2> <b:2>` | Selects the focus track, with its color. |
| SET MIX VU METER THRESHOLDS | `0C 0B <yellow> <red>` | Where the meters turn yellow and red, each 0–127; red must be above yellow. |

All of these are from the SysEx doc. `scheme` is an index (0–82) into the Roto-Control's color
table (the SysEx doc's Appendix A, not reproduced here), and `grouped` is `00` or `01`.

- **Single-track pages.** Ableton and Bitwig both put level on knob 1, pan on knob 2, and the first six sends on knobs 3–8 of the first page, and eight sends on each later page.[^ableton][^bitwig] They differ from the SysEx doc on how the page is numbered:
  - The SysEx doc says `page` is a multiple of 8 (0, 8, 16, …).[^sysex-1.6]
  - Ableton and Bitwig both treat it as a page number (0, 1, 2, …). With a multiple of 8, Ableton's arithmetic would point far past the sends.[^ableton][^bitwig]

  The Roto-Control sends page numbers.[^test-2] `RotoOutgoing.sendNamesStart(forControlPage:numbering:)` handles both readings; drivers use `.pageNumbers`.
- **Which send names to send.** After SET MIX ALL TRACKS MODE or REQUEST SEND TRACK NAMES, the block starts at the multiple of 8 at or below the send index.[^sysex-1.6] After SET MIX TRACK MODE, the SysEx doc's examples (pages 0, 8, and 16 start at sends 0, 6, and 14) fit a block that starts at the page index minus 2, and at 0 for page 0.[^sysex-1.6] Read as page numbers, the same layout starts at 0 for page 0 and at 6 + (page − 1) × 8 after that, as in Ableton's code[^ableton], and that reading is the one the Roto-Control uses.[^test-2]
- **When the screens are drawn.** The Roto-Control draws a single track's send labels when it gets DAW SELECT TRACK, not when it gets SEND TRACK NAMES; so after every SET MIX TRACK MODE the host sends the names, then DAW SELECT TRACK. On returning to all-tracks mode, the track screens are blank until the host sends the page again (NUM TRACKS, FIRST TRACK, and TRACK DETAILS).[^test-2] Bitwig's code sends DAW SELECT TRACK on a single-track page change.[^bitwig]
- **What draws the strips.** After a power cycle, the strips stay blank until the host sends NUM TRACKS, TRACK DETAILS, and TRACK DETAILS END; nothing shows before END, and TRACK DETAILS and END without NUM TRACKS show nothing. FIRST TRACK was not needed for the first page (the inference is that it starts at 0).[^test-3]
- **Strips outlast the host.** Left in MIX mode between the host quitting and a new handshake, the Roto-Control keeps the strips it was last sent: track 1's name and color, sent in one run, still showed in the next. A power cycle clears them, and so does switching to another mode and back[^test-2].[^test-3] So a host should send all eight strips on every connection, blanking any it does not use.
- **Track colors.** The color scheme in TRACK DETAILS sets each strip's color, and the SysEx doc's table gives the colors seen.[^test-2]
- **Meter thresholds.** Ableton uses 87 and 113; Logic 106 and 120.[^ableton][^logic]
- **Meter dimming.** Ableton also sends `0C 0C` with eight bytes, one per track of the page, which the SysEx doc does not list. Ableton sends 1 for an unmuted track and 0 for a muted one, or, while any track is soloed, 1 for soloed tracks and 0 for the rest.[^ableton] The inference is that 0 dims a track's meter. `RotoControl` can send it, marked as undocumented.

## 4a. PLUGIN mode

In PLUGIN mode the host lists "plugins" (Ableton's devices), and the user maps the Roto-Control's
controls to their parameters. The Roto-Control stores each mapping on the device, under a hash of
the plugin and a hash of the parameter.[^sysex-1.6][^ableton] Performance Bridge could present parts
of TotalMix FX as plugins, for example the control room or the selected channel's EQ; that use is
this project's idea, not Melbourne Instruments'.

**The flow, as Ableton's integration runs it**[^ableton]:

1. The Roto-Control sends SET PLUGIN MODE (`0B 01`). Ableton first sends the track page (NUM TRACKS, FIRST TRACK, TRACK DETAILS), then answers with NUM PLUGINS (`0B 02`), FIRST PLUGIN (`0B 03`), a PLUGIN DETAILS (`0B 05`) for each plugin on the page, PLUGIN DETAILS END (`0B 06`), and DAW SELECT PLUGIN (`0B 08`).
2. When the user selects a plugin, the Roto-Control sends ROTO SELECT PLUGIN (`0B 07`, the index on the page).
3. For each control it has a mapping for on that plugin, the Roto-Control sends CONTROL MAPPED (`0B 0B`) with the parameter's index and hash. The host finds the parameter (by hash; by index when two share a hash) and answers with LEARN PARAM (`0B 0A`), which carries the parameter's name and position. From then on the control's CCs (section 5) change that parameter. Ableton answers this way only for knobs, unless the parameter is a macro; the SysEx doc says to answer every CONTROL MAPPED, and `sbdev` does, for switches too, with no problem seen.[^ableton][^sysex-1.6][^test-2]
4. To make a mapping, the user turns on learn mode (the Roto-Control sends SET DEVICE LEARN (`0B 09`) on) and moves a control, whose screen shows LEARNING. For a knob, turning starts learning and touch alone does not.[^test-3] The parameter is then chosen in the DAW, the host sends LEARN PARAM, and the Roto-Control answers with CONTROL LEARNED (`0B 11`).[^bitwig-guide][^test-2] Ableton sends LEARN PARAM whenever a parameter is selected while learn mode is on.[^ableton]

**What a parameter can carry** (LEARN PARAM)[^sysex-1.6]:

- a name, and a position (14 bits);
- a center detent, for knobs;
- or a number of steps: the SysEx doc gives 0 (continuous) or `02`–`18` hex, so 2–24, and names for each step when there are no more than `10` hex (16) steps. Ableton's integration caps steps at 24 and step names at 16[^ableton], which agrees.

**Hashes.** A plugin's hash is 8 bytes and a parameter's 6, each byte 7-bit.[^sysex-1.6] Ableton
takes them from SHA-1 digests of the device's and parameter's names.[^ableton] The inference is
that the Roto-Control uses them only as names for stored mappings, so any stable hash will do;
`RotoHash.of` uses FNV-1a.

**Host-set control names.** SET PLUGIN CONTROL DETAILS (`0B 13`) names a control (0–63) and sets
its color, without learning. The SysEx doc says it is normally used in Logic's SMART mode. Whether
it works with another DAW type is open (section 8): with type `02` it named nothing[^test-2], and
with type `03` PLUGIN mode never settled.[^test-3]

**What test 2 found** (type `02`)[^test-2]:

- PLUGIN DETAILS and this project's hashes are accepted: holding SEL shows the plugin names, and selecting one sends ROTO SELECT PLUGIN.
- An unmapped control sends its touch CC and nothing else, and SET PLUGIN CONTROL DETAILS does not name it. Every control has to be learned before it does anything.
- Learning works in the order the Bitwig guide gives: LEARN, then the control (its screen shows LEARNING), then LEARN PARAM from the host. CONTROL LEARNED came back 44–161 ms after LEARN PARAM. While learn mode is on, touching a knob sent no touch CC. (Test 2 recorded "touches"; test 3 found that turning is what counts.)
- On leaving learn mode, and after the host selects a plugin with mappings (DAW SELECT PLUGIN, including after the host restarts), the Roto-Control sends CONTROL MAPPED for every mapped control on the page. Once it also sent them with no message from the host before them (235.558 s).[^test-2] The mappings are stored on the Roto-Control.
- A center detent settles the knob at 8191, the middle of the range (the host sent 8192).
- A switch mapped to a stepped parameter steps through the values itself, wrapping around, and sends each step as a share of 0–127: 0 and 127 for two steps; 42, 84, 127, and 0 for four. The step names were not shown; the inference is that the host is expected to show them with SHOW CONTROL VALUE, as Ableton's integration does with its value text.[^ableton]
- Once knob 1 had been learned under one plugin, it would not show LEARNING under another (seen); knob 2 could still be learned there. The inference from test 3 is that this came from touching without turning, not from the existing mapping.

**What test 3 found** (types `02`, `01`, and `03`)[^test-3]:

- **Mappings are kept per plugin.** Knob 1 mapped to "Main Vol" under one plugin and to "Freq 1" under another, and knob 2 to "Gain 1" and "Phones 1"; selecting either plugin brought back its own mappings. A control mapped under one plugin was learned under another without UNMAP CONTROL.
- **UNMAP CONTROL clears the screen, not the stored mapping.** After UNMAP CONTROL, knob 1's name disappeared (seen), but selecting the same plugin again brought back CONTROL MAPPED for knob 1, twice out of twice.
- **Learning.** Turning a knob in learn mode showed LEARNING on the first slight turn (knobs 4 and 5), and eight touches without turning did not (seen); a knob turned with a rubber eraser, so not touched, showed LEARNING at once (seen). In learn mode the Roto-Control sent nothing at all while knobs were turned, and nothing says which control shows LEARNING: LEARN PARAM goes to whichever does. Leaving learn mode with a control still showing LEARNING sent nothing about it. CONTROL LEARNED came 40–92 ms after LEARN PARAM. During learning the whole screen belongs to the knob (top half LEARNED, bottom half the parameter name; seen).
- **A knob on a stepped parameter.** Mapped to a parameter with three steps, the knob moved in three haptic steps (seen) and sent only 0, 8191, and 16383. No step names showed, on the knob or, as in test 2, on a switch (seen).
- **SET PLUGIN MODE's data byte** was `00` in all 300 SET PLUGIN MODE messages in the eleven logs of tests 2 and 3, with either of two plugins selected. Its meaning is still unknown.
- **Type `03`.** Claiming Logic, the Roto-Control sent SET PLUGIN MODE 292 times in 61 seconds, every 185–281 ms (median 207 ms), each time after `sbdev`'s plugin page, and never sent CONTROL MAPPED; the screens flickered between the MENU window and screens 1–3 (seen). The inference was that it waits for something Logic's integration sends. Reading that integration (section 8, item 2) shows its answers go through Logic itself, so `sbdev` can't imitate them.

**What PLUGIN mode lacks.** The meter CCs are listed for MIX mode only, and the per-track screens
and track paging are MIX-mode features.[^sysex-1.6]

## 5. CCs

All on MIDI channel 16.[^sysex-1.6] "Knob 1–8" means CC numbers in that order.

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
bits is from Bitwig's and Logic's code.[^bitwig][^logic] The rest:

- **Switch values.** In MIX mode, with type `02`, a switch sends 127 on each press and nothing on release, and changes no state by itself: the host decides the new state and sets the light (section 6). This holds in record-arm, mute, and solo modes.[^test-1][^test-2][^test-3] With type `01` a switch also sends 0 on release, and still changes nothing by itself.[^test-3] In PLUGIN mode a switch sends the mapped parameter's value instead (section 4a).[^test-2] `RotoControlDecoder` reports the value as sent, and a driver reads it as a press or a value depending on the mode. Bitwig treats 127 as pressed and 0 as released.[^bitwig]
- **Transport switches.** Ableton reads them as play, stop, record, session record, loop, punch-in, punch-out, and re-enable automation.[^ableton] That order matches TRANSPORT STATUS.[^sysex-1.6] With type `02` the Roto-Control sends them in transport mode, 127 on press and 0 on release, and asks for TRANSPORT STATUS when that mode is entered.[^test-2]
- **CCs 36 and 37.** Ableton also listens on these, the two CCs after the transport switches, for rewind and fast-forward.[^ableton][^bitwig] The SysEx doc does not list them. `RotoControl` reports them as other CCs.
- **CC 64.** The Roto-Control sends it, with a knob's index as the value, and Ableton then sets that knob's parameter to its default.[^ableton] The SysEx doc names it "level at 0 dB" without saying what triggers it. With type `01`, in all-tracks level mode, the Roto-Control sent it each time a knob landed in its 0 dB indent: ten times out of ten passes, always with the knob reporting exactly 13926 in the same millisecond, and the knob then said nothing for 32–601 ms. Seen: the indent was too weak to feel. With type `02` there was no CC 64 in 31 passes of knob 1 through 13926 (12 in level mode, 19 in pan mode).[^test-3] Melbourne Instruments' release notes add 0 dB indents for volume (3.0.1, Logic) and for volume and send knobs (3.1.0, all three DAWs).[^release-notes] Sends, and the exact position of the `02` indent (section 3), are untested. With type `01`, CC 64 has therefore been observed only as a notice that a knob reached the indent, not as a reset gesture; a TotalMix FX driver that claims `02` will not see it.
- **Meters hold.** A meter has been observed to stay where it was set until the host sets it again; the host sends the falls as well as the rises.[^test-2]
- **Meter values.** Ableton sends a track's meter as Live's meter reading (0–1) times 127, at most 12 times a second.[^ableton] How Live scales that reading is not in the integration, so the mapping from TotalMix FX's dB levels to 0–127 is this project's choice, still to be made.

## 6. Feedback to the Roto-Control

- **Moving a knob.** The host sends the same CC pair the knob sends: the high 7 bits on CC 12–19, then the low 7 bits on CC 44–51.[^bitwig][^logic] Bitwig computes the 14-bit value as the parameter (0–1) times 16383, rounded.[^bitwig]
- **Lighting a switch.** The host sends 127 (on) or 0 (off) on the switch's CC.[^ableton] In MIX mode this sets both the light and the label in the bottom half of the switch's screen. With 127 the light comes on in the mode's color and the label shows on that color: "ARM REC" in red; "MUTE" in orange; "SOLO" in yellow with type `02` and blue with type `01`. With 0 the light is off and the label gray (seen).[^test-2][^test-3] In mute and solo modes the label stays blank until the host first sets the light; "ARM REC" shows from the start (seen).[^test-3]
- **Mute Master off.** While TotalMix FX's Mute Master is off, a mute that is on is only set
  (`TOTALMIX-OSC.md`, the global mute recheck), so the driver flashes it: it sends 0 and 127 on the
  switch's CC in turn, 0.5 s each, as the Launch Control driver flashes its mute buttons (Adam,
  2026-11-02). The light and the "MUTE" label both flash orange with it (seen).[^test-12]
- **Moving a knob.** The motor follows the host's position: 0 dB (13388) put knob 1 at about 3 o'clock, and the range runs from about 7 o'clock (0) to about 5 o'clock (16383), 300° of travel.[^test-2]
- **Past the ends.** The knob has no physical stop (seen).[^test-2] Past an end it does one of two things[^test-2][^test-3]:
  - **Hold.** It goes silent and resists (seen). Forced on, it lets go and reports a position about 3,300–3,700 counts in from the other end, and carries on from there: 13004–13078 from 0, and 3325–3693 from 16383.
  - **Wrap.** It goes silent for 32–1,491 ms with no resistance (seen), reports the other end (0 to 16383, or 16383 to 0), and carries on from there.

  Every one of the 41 end events in the logs of tests 2 and 3 fits this rule: **a knob holds once the host has sent it a position in MIX mode, until the knob mode (level, pan, or send) changes; otherwise it wraps.** Twelve holds and 29 wraps fit; none does not. In particular:
  - the hold outlasted the host quitting and reconnecting, and switching to single-track mode and back[^test-2];
  - a position set by LEARN PARAM in PLUGIN mode did not count[^test-3];
  - changing the knob mode from level to pan cleared it, and changing back did not restore it[^test-3];
  - in one run, a knob the host had not set wrapped while one it had set held.[^test-3]

  This is an inference from those events; the SysEx doc says nothing about it. The releases from 0, at 13004–13078, sit at the `02` indent's position (13004[^test-5]), so the knob may let go into its indent; another inference, from that match alone. Test 1's "bounce" (0 to 16383 and back to 0) fits as two wraps, but its log was not kept, so whether the host had set that knob is unknown.

  A driver must therefore send every knob's position after each change of knob mode, and still treat a jump across most of the range as an end event, not as a new level: for a TotalMix FX fader, 0 to 16383 is off to +6 dB.

  How large a jump is an end event: in the kept logs of tests 2 and 3, a script comparing each knob report with that knob's last found every end event at 12,690 counts or more, and every other report at 2,942 or less, apart from the 8,191- and 8,192-count steps of a stepped knob in PLUGIN mode. `RotoDriver` therefore takes a jump of more than 8,000 counts in MIX mode as an end event, ignores it, and sends the knob back to its last position.
- **Unchanged values.** Bitwig does not resend a knob position it last sent, except that it resends all eight positions when it switches layers or modes.[^bitwig]
- **Value text lasts about 2 seconds** on the screen before the name comes back, as the user timed it.[^test-2] It shows on a knob's screen in MIX and PLUGIN modes. On a switch's screen it showed nothing, in either mode, so a switch's state can be shown only by its light and label (seen).[^test-3]
- **Value text.** Ableton sends SHOW CONTROL VALUE whenever a mapped parameter's value changes, from the knob or from Live, at most 12 times a second with one trailing update, and once when a knob is touched.[^ableton] Bitwig sends value text only in PLUGIN mode, within 100 ms (plugin parameters) or 300 ms (macro parameters) of the knob last moving; in MIX mode it sends none.[^bitwig]
- **Bitwig's command for value text.** Bitwig sends value text as `0A 0F`, the number the SysEx doc gives REQUEST ROTO SYSEX API VERSION, with the same layout as SHOW CONTROL VALUE.[^bitwig][^sysex-1.6] The inference is that `0A 0F` is an older form, from before SHOW CONTROL VALUE was documented. `RotoControl` sends `0A 18`, as Ableton and Logic do.[^ableton][^logic]
- **Hold-off for the motors.** Bitwig holds back a knob position for 100 ms after the knob last moved on its master and return layer, and has the same rule commented out on its track layer. While touch automation is on, it also ignores the knob for 500 ms after release, and it queues knob positions while it switches modes.[^bitwig] Ableton leaves knob feedback to Live's framework, so its rule is not visible in the integration.[^ableton] Performance Bridge will need its own rule, because TotalMix FX confirms nothing[^totalmix-test-5]: a position from TotalMix FX is a change made elsewhere. The planned rule, an inference, was to hold back positions for a knob while it is touched; test 1 shows a knob turning before its touch CC, so the rule will also have to count recent movement. Test 3 adds that touches often failed to register at all (seen; a double tap sent nothing), so movement is the more reliable sign. Melbourne Instruments removed the touch-sensitivity setting in 2.1.0.[^release-notes]

## 7. Errata in the SysEx doc

They are noted here so that nobody builds on them:

- Two sections are numbered 2.21.
- The PLUGIN headings for 3.26–3.29 use command numbers `20`–`23`, but the overview, and Logic's code, use `1A`–`1D`.[^sysex-1.6][^logic]
- DAW SELECT TRACK (4.4) shows the color field as `CS` in the command but defines it as `CI`. The field is the color scheme, as in TRACK DETAILS.
- The overview gives ROTO SELECT PLUGIN (`0B 07`) as sent to the Roto-Control, though its name says the Roto-Control selected the plugin; the Roto-Control does send it.[^test-2]
- Appendix A writes one green value as "BO" (letter O), presumably `B0`.
- Appendix B's Logic formula for a mapped parameter's CC number divides where Logic's code takes the remainder.[^sysex-1.6][^logic] PLUGIN mode only.
- In PLUGIN mode, the overview also gives the wrong direction for SET PLUGIN LEARN (`0B 09`) and FIRST PLUGIN (`0B 03`), and 3.26 calls both halves of the sweep value "LSB". Logic's code uses a PLUGIN command, `0B 1E`, that the SysEx doc does not list; it comes from the Roto-Control, with a switch index ("request switch parameter value" in Logic's code).[^sysex-1.6][^logic]

## 8. Open questions

Tests 1–3 (section 9) settled the handshake with types `01` and `02`; what MIX mode needs from
the host; pacing; the knob CCs; that host moves are not echoed; motor moves; the single-track page
numbering; transport switches; switches and lights in record-arm, mute, and solo modes; CC 64 and
the 0 dB indent with type `01`; the ends of the knob's range (as an inferred rule); and, in PLUGIN
mode, unmapped controls, learning and relearning, stored mappings, UNMAP CONTROL, detents, steps,
and step names.

1. **SET PLUGIN MODE's data byte.** Answered by Logic's integration, not a test: `00` is PLUGIN mode and `01` Logic's Smart Controls mode, not a page number. With `02` it has always been `00`[^test-2][^test-3], which fits.[^logic-sysex]
2. **Type `03`.** Left open on purpose. Logic's integration runs inside Logic's control-surface layer: it answers SET PLUGIN MODE with commands to Logic, and the Roto-Control's plugin details follow from what Logic then reports. So `sbdev` can't stand in for it without imitating Logic. Performance Bridge claims `02`, so this isn't needed.[^logic-read] The undocumented `0B 1E` goes from the Roto-Control to the host (named "request switch parameter value" there, with a switch index), not the other way.[^logic]
3. **The 0 dB indent.** Settled by tests 5 and 8: with `02`, level knobs at 13004 and send knobs none; with `01`, send knobs none either. Still open: whether `03` has one (not needed, since Performance Bridge claims `02`).
4. **The hold rule.** Settled by tests 6, 8, and 9: a power cycle or a trip through PLUGIN mode clears it; a forced release doesn't; from 0 the knob lets go at the indent (13004), from 16383 at about 3,250–3,700.
5. **The FX label.** Settled by test 7: it labels the send-mode switch, shown only while the host reports sends.
6. **Virtual detents, for parity with the E16** (Adam, 2026-11-06; the rule is in AGENTS.md,
   and the E16's tuning in `docs/OXI-E16.md`, section 5). The E16 holds a pan at center and a
   push-and-turn at −∞, 0 dB, and +6 dB. The Roto-Control has a real 0 dB indent on level knobs
   (claimed type `02`, bent to TotalMix FX's 0 dB) and none on send knobs (tests 5 and 8). Open:
   whether its pan knobs have a center indent in MIX mode (to check on the device); the SysEx API
   sets neither indents nor their strength in MIX mode (feature requests 1 and 2). A host-side
   detent on this knob is a different thing from the E16's: the knob reports where it physically
   is, so holding the value while the knob moves on leaves the two apart until the host moves the
   knob back, which is what the "magnet" of 2026-10-30 did, and it felt like a delayed jump
   (section 3). So: check the pan knobs; ask Melbourne Instruments for indents on send knobs
   (and on pans, if missing); add a host-side detent only if a way is found that doesn't feel like
   the magnet. The knobs don't push, so push-and-turn jumps have no counterpart.

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
- **SET PLUGIN MODE with data.** The Roto-Control sent SET PLUGIN MODE immediately after CONNECTED (the inference is that it was in PLUGIN mode), with one data byte (`00`) that the SysEx doc does not list. Bitwig's integration reads one byte there.[^bitwig] Its meaning is unknown.
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

### Test 3 (2026-10-30): the open questions

**Setup.** Firmware 3.3.0 (`eaa37b0`) and SysEx API 1.6, as in tests 1 and 2, with `sbdev roto
--raw` on `main` at `ced6f80`, in seven runs: run 1 claiming Bitwig (`02`) with the default setup;
run 2 claiming Ableton (`01`); run 3 claiming Logic (`03`); runs 4, 4b, and 4c with `--setup none`,
with a power cycle before 4c; and run 5 with `--gap 0`. The counts below come from scripts over
the raw logs of tests 2 and 3, which are kept outside this repository. The user's notes are marked
"seen". On the Roto-Control each knob has a screen below it, shared with its switch: the top half
belongs to the knob and the bottom half to the switch. The screen above the front-panel
buttons is the MENU window (seen).[^manual]

**Front panel** (seen):

- FUNC switches MIX mode between all tracks and a single track.
- Holding SEL shows the modes: VOLUME, PAN, and Send 1 in the top halves of screens 1–3 ("FX" under Send 1), and MUTE, SOLO, and ARM in the bottom halves of screens 4–6, the current one lit (MUTE, in orange, when it was current). Releasing SEL sent SET MIX ALL TRACKS MODE with the new modes; holding it sent REQUEST SEND TRACK NAMES for send 0. The modes are kept across host runs and a power cycle.

**Findings:**

- **The handshake** was the same with all three types: CONNECTED 5 ms after DAW PING RESPONSE, the limit `sbdev`'s pause allows (1 ms in run 5, with no pause).
- **Type `01`** (run 2): MIX mode's messages were the same as with `02`, and the PLUGIN-mode mappings made under `02` came back unchanged. The differences are in section 3: the 0 dB indent with CC 64 (ten of ten passes), switches that send 0 on release (three presses, each released 130–250 ms later), and the solo color.
- **Type `03`** (run 3): the PLUGIN-mode loop in section 4a.
- **What MIX mode needs** (runs 4–4c): with `--setup none` the strips stayed blank. Sent one at a time, NUM TRACKS, FIRST TRACK, and track 1's TRACK DETAILS changed nothing on the screens; TRACK DETAILS END then drew track 1 (seen). In run 4b, track 1 still showed from run 4, and track 2's details and END drew track 2. After the power cycle (run 4c), track 2's details and END drew nothing, and NUM TRACKS, the same details, and END drew it (seen).
- **No pause** (run 5): with `--gap 0` the eight strips, the four plugin names, and the replies to CONTROL MAPPED all arrived (seen), and the Roto-Control answered DAW SELECT PLUGIN within 64 ms.
- **Switches in mute and solo modes** (run 1): one press each sent 127 and nothing on release, and changed neither the light nor the screen (seen); `led 1 on` and `led 1 off` set the light and the label (section 6).
- **Value text** (run 1): `show 1 -6.0 dB` showed briefly in PLUGIN mode; `showsw` showed nothing on a switch's screen, twice in PLUGIN mode and once in MIX mode (seen). The bytes sent had kind `01` (switch).
- **CC 64 and the 0 dB indent:** section 5.
- **The ends of the knob's range:** section 6. Run 1 had ten wraps; run 2 four; run 5 two wraps on knob 1 before `knob 1 -20dB` and three holds after it, a wrap on knob 2, which the host had not set, and wraps on knob 1 after the knob mode changed to pan and back to level.
- **PLUGIN mode** (run 1): per-plugin mappings, UNMAP CONTROL, learning by turning, and the stepped knob, all in section 4a.
- **Touch** (seen): touches often did not register, and a double tap sent nothing.

### Test 4 (2026-10-30): `RotoDriver` with TotalMix FX, through `sbdev bridge`

**Setup.** Firmware 3.3.0, type `02`, with `sbdev bridge` on branch `roto-driver` (commits
`ab1eb2f` to `fde305a`), in five runs with TotalMix FX "2.10 (1)" and a Digiface AES. The logs are
kept outside this repository; `sbdev bridge` logs SysEx from the Roto-Control and every message to
TotalMix FX, and from `fde305a` also every CC other than knobs and touches. The user's notes are
marked "seen".

**Findings:**

- **Strips, lights, and meters** (seen): the eight sources drew with their names; mute and PFL (on
  the record-arm switches) lit and followed TotalMix FX both ways; a meter moved with an input's level.
- **The 0 dB indent:** section 3 (felt at "-0.8 dB" before the scale was bent, and at 0.0 dB after).
- **The second track set** (seen): monitoring outputs in green, then sends in blue; a knob moved
  an output's fader, and the knob followed the fader moved in TotalMix FX.
- **Choosing a knob mode** (seen): with SEL held, a knob mode is chosen with the switch below it;
  the switch below Send 1 is labeled "FX". Choosing it sent SET MIX ALL TRACKS MODE with knobs on
  send. While SEL is held the Roto-Control showed a send name from an earlier run, so the host must
  send the names in every knob mode.
- **Single-track mode:** knob 3 set the focused input's level into the first send's submix. Switches
  1 and 2 sent no CC at all in single-track mode (run 5), so a host cannot use them there; that
  all eight behave alike is an inference.
- **Knob reports on connecting** (run 6): within 0.6 s of the driver sending knob positions on
  connecting, knobs 5–7 reported positions near the ones sent (for example 0.444, 0.458, and
  0.456 for a position of about 0.46), and the driver passed them on to TotalMix FX. The user is not
  sure whether a hand was on those knobs. The inference is that the motors' travel was reported as
  turns; test 1 saw no echo of a host move, but there the knob was at rest. `RotoDriver` now
  ignores a knob's reports for 0.75 s after it moves the knob, and for 2 s those within 200 counts
  of where it put the knob. In run 7, with the guard and hands off the Roto-Control (seen), nothing
  went to TotalMix FX on connecting, but the Roto-Control still sent ROTO SELECT TRACK for knobs 3 and
  8 about 0.6 s after the knobs were moved, which supports the inference that motor travel is
  reported like a hand's.
- **SET CURRENT TRACK NAME** (run 7, seen): sent with "Outputs" while the second track set was
  shown, it renamed screen 8's top half, the strip of the track last reported by ROTO SELECT
  TRACK (7, counting from 0); the MENU window still showed "MIX-RTN". So it names the selected
  track, not the track set, and no command found sets the MENU window's text.
- **PLUGIN mode with no plugins** (run 7): answered with NUM PLUGINS 0, FIRST PLUGIN 0, and PLUGIN
  DETAILS END, the Roto-Control sent SET PLUGIN MODE once each time the user chose PLUGIN mode
  and nothing more. Seen: the knob screens black, the MENU window blue with "---" on top and the
  selected track's name below, and no flicker or cycling.
- **Meter colors** (`sbdev roto`, after run 7, seen): with thresholds 126 and 127, meter 1 at 125
  was green almost to its end, at 126 much the same (any yellow was at most a pixel or two), and
  at 127 full with a red last pixel. So a meter shows red at the red threshold itself. A yellow
  threshold of 126 leaves no visible yellow, so `RotoDriver` now borrows the levels of RME's own
  hardware meters[^totalmix-meters]:
  yellow from −5 dBFS (117 on a −65…0 dBFS scale) and red from −1 dBFS (125). With those
  thresholds, meter values 112, 120, and 126 showed green, a yellow end, and a red end, as expected
  (seen). Since 2026-11-06 the scale follows TotalMix FX's fader law (`MeterScale`;
  docs/TOTALMIX-OSC.md), so the same levels are thresholds 103 and 122. Seen 2026-11-07 (Adam,
  branch `e16-four`, music through one channel): the meter rose and fell about as high as TotalMix
  FX's for the same channel and turned yellow at the top; red not seen (not pushed toward 0 dBFS).
  The Roto-Control is sent the peak level and draws its bar from it, so its bar sits nearer its
  peak dot than TotalMix FX's, whose bar is an average; the E16's meters are drawn like TotalMix
  FX's (an average bar and a held peak), a difference noted for the 1.2.0 UI review.
- **Track colors against TotalMix FX's** (run 8, seen): with the playback pairs in TotalMix FX's eight
  colors and each mapped to the table color nearest in hue, schemes 9 (blue) and 61 (green)
  matched TotalMix FX; 50 looked slate blue, 57 brown, 56 burgundy, 2 ochre, and 24 royal blue
  (like 66 in test 2). So the screens show some table colors darker or bluer than their RGB
  values suggest, and the driver's colors are chosen by eye. A second round (run 10) found 61
  forest or olive green against TotalMix FX's lime, and 17 lemon against TotalMix FX's yellow-orange;
  in a third (run 11), 18 looked fluorescent and 1 plain orange, a better match for TotalMix FX's
  orange than 15. Run 12: 47 looked olive, and 59 brownish ("peanut butter"). Run 13: 19 matched
  TotalMix FX's green, and 73 was a little too green for its yellow.
- **SET TRACK COLOUR** (run 14, seen): sent after TRACK DETAILS END, it changed the strip's color
  in MIX mode (FFC800, a yellow-orange), with the strip's name in white, where scheme 73 alone had
  black text. The host cannot choose the text color. In run 15 an exact color sent for the third
  strip on the first page stayed on the third screen after paging, over the next page's own scheme,
  and after the Roto-Control was plugged in again an exact color sent for a strip did not show.
  So an exact color belongs to a screen rather than a track, and `RotoDriver` does not use them.
- **SOLO and ARM** (run 7, seen): with the switches on solo, a press set PFL in TotalMix FX and lit
  the switch; on record arm, a press did nothing.
- **Modes kept across sessions** (run 16, seen): on connecting, the Roto-Control reported SET MIX
  ALL TRACKS MODE with knobs on send 1 and switches on record arm, the modes left from run 15, so
  the knobs moved the first send's submix rather than the main one. No message sets these modes
  from the host.
- **Scheme 73** (run 16, seen): TotalMix FX's yellow drawn as scheme 73 looked "banana" against
  TotalMix FX's "mango". `sbdev bridge` has `color` commands to try exact colors again, sent to every
  strip on every page, and to tune a color with knobs 1–3.
- **A hang after exact colors** (run 17, seen): on a page of 7 strips (tracks 8–14 of 15), `color
  exact` sent SET TRACK COLOUR for tracks 8–14 and black for track 15, past the track count, twice
  in 7 seconds; the Roto-Control then hung. That the color past the track count caused the hang
  is an inference; the driver no longer sends colors for blank screens.
- **A hang after exact colors, again** (run 18, seen): with no color past the track count, `color
  exact` sent SET TRACK COLOUR for the seven strips (tracks 8–14) at once, and the Roto-Control
  froze. So the color past the track count was not the cause (or not the only one). Run 14, with
  one SET TRACK COLOUR per page, did not hang. That a burst of them causes the hang is an
  inference; `sbdev bridge` now sends them 150 ms apart, to test it.
- **Switch labels after a redraw** (run 19, seen): while `scheme tune` drew the page again and
  again (TRACK DETAILS … END, with no switch lights), the lower halves of several screens went
  dark. The labels are drawn with the switch lights, so `sbdev bridge` now sends the lights after
  each redraw (that this restores them is still to be seen).
- **A freeze after many redraws** (run 19, seen; its log was overwritten): after `scheme tune` had
  drawn the whole page up to every 100 ms for a while, the Roto-Control stopped responding: knobs
  and switches did nothing, some front-panel buttons still lit, and it did not answer DAW STARTED
  in the next run until plugged in again. Runs 17, 18, and 19 all froze while the host sent many
  SysEx messages in a short time; that this is the cause is an inference. `scheme tune` now sends
  one SET TRACK DETAILS per changed strip, at most every 250 ms.
- **`scheme tune`, lighter** (run 20, seen): one SET TRACK DETAILS per change, about 50 changes in
  30 s, and no freeze.
- **SET TRACK COLOUR's index** (run 20, seen; the reading is an inference): `color exact`, now
  paced 150 ms apart, sent colors for tracks 8–14 and the Roto-Control froze again. Across test 4,
  every SET TRACK COLOUR with an index of 0–7 worked (run 14: index 2) and every one with an index
  of 8 or more was followed by a freeze (run 15: index 13, the hang before run 16; runs 17, 18,
  and 20: indexes 8–15). With run 15's color staying on its screen across pages, this reads as:
  the index is the screen (0–7), not the track, and an index past 7 freezes the firmware.
  `RotoDriver` now sends the screen number.
- **Screen numbers on a later page** (run 21, seen): on the page of tracks 8–14, SET TRACK COLOUR
  with indexes 0–6 froze nothing but changed nothing on the screens, during `color tune` and
  `color 7 F0A030`. So the screen reading above does not hold either. A reading that fits every
  run (an inference): the firmware draws an exact color only for a track on the current page,
  but keeps it in an eight-entry table indexed by the track number, so indexes 0–7 work only on
  the first page (and stay with that screen afterward), and 8 or more overrun the table. If so,
  exact colors are usable only for the first eight tracks.
- **SET TRACK DETAILS** (run 22, seen): `swatch` sent SET TRACK DETAILS (`0A 11`, shown at once)
  for screens 1–4 on the first page with schemes 3, 17, 59, and 73; the names changed, the colors
  did not. Exact colors sent in run 21 (indexes 0–6) may still have been held for those screens,
  since the Roto-Control was not plugged in again in between, so this is not yet a clean result.
  `swatch` now draws the page with TRACK DETAILS … END instead.
- **Yellow** (run 23, seen): side by side, drawn as a page after plugging in again, schemes 3, 17,
  59, and 73 all showed; 73 was the closest to TotalMix FX's yellow ("not great"), 59 closer in hue
  but brownish. Yellow stays scheme 73.
- **The table's colors.** Melbourne Instruments' Bitwig integration lists an RGB value for each
  scheme (`ColorUtil.java` in [roto_control](https://github.com/Melbourne-Instruments/roto_control),
  MIT), which is a quicker guide than the SysEx doc's table to which schemes to try. By it, the
  neutral grays are 13 (white), 27, 41, 55, and 69 (darkest), with 70 black; 49, used for
  TotalMix FX's gray, is a bluish gray. How each looks on the screens still has to be seen.
- **Choosing a send** (2026-10-30, seen): with SEL held, pressing the switch under screen 3 (the
  one labeled "FX") again and again steps through the sends; turning knob 3 with SEL held did not
  change the send.
- **White** (run 24, seen): side by side, 13, 27, 41, 55, 69, and 49; TotalMix FX's default white is
  drawn as 27 (light gray). Schemes 2 and 30 were no better than 73 for yellow.

### Test 5 (2026-11-01): where the `02` indent is, and send knobs

**Setup.** Firmware 3.3.0, SysEx API 1.6. `sbdev roto`, claiming Bitwig (`02`), 16 tracks. Knob 1 was turned slowly upward from below, three times in level mode and then several times in send mode (send index 4). Logs from Adam, 2026-11-01.

**Findings:**
- **Level knobs.** In all three passes through the upper range, knob 1 reported exactly **13004** and then nothing for 0.40, 0.13, and 0.12 s before going on (13033, 13053, 13054). No other value in the passes had a comparable pause. Adam didn't feel a detent this time; on 2026-10-30 he had felt one.[^test-4]
- **Send knobs.** In three passes through the same range in send mode, knob 1 went straight through: 12987 → 13035 and 12994 → 13024, with no stop at 13004 or anywhere between about 12700 and 13300.
- **Ends.** Turned past 16383, the knob went to 0 (two passes), and past 0 to 16383. This fits the rule for the ends of the range in section 6, settled earlier.

**Consequences.**
- The `02` indent is at 13004, one count above the 13003 inferred from Bitwig's volume law. `RotoDriver` now uses 13004.
- Send knobs have no indent with `02`. The 3.1.0 release notes' send indents may hold only for other types, or not on 3.3.0 (inference).
- The indent's hold is weak enough that a hand may not feel it.

### Test 6 (2026-11-01): the hold rule and a power cycle

**Setup.** Firmware 3.3.0, `sbdev roto` claiming Bitwig (`02`), knobs in send mode throughout (send index 4).

**Findings** (Adam, 2026-11-01):
- `knob 1 0.5` moved knob 1 to a little left of its middle (seen).
- Turned up past the top, knob 1 then **held**: it resisted and went silent (felt; this part of the log wasn't kept).
- `sbdev roto` was quit and the Roto-Control unplugged for 5 seconds and plugged in again. In a new `sbdev roto`, with no position sent, knob 1 turned up to 16383, went silent for 0.45 s, reported 0, and carried on upward: a **wrap** (log kept).

**Consequence.** A power cycle clears the hold, as the rule in section 6 predicts: the knob holds only once the host has sent it a position since it was last powered (and since the knob mode last changed). `RotoDriver` sends positions as soon as it connects, so after a power cycle the knobs hold again once the handshake is done (inference from the driver's behavior).

### Test 7 (2026-11-01): the "FX" label

**Setup.** Firmware 3.3.0, `sbdev roto` claiming Bitwig (`02`), 16 tracks and 16 sends named "Send 1" to "Send 16", knobs in send mode at send index 4.

**Findings** (Adam, 2026-11-01):
- With SEL held, the third screen read "Send 5" on top and "FX" below. "Send 5" is the name the host gave send index 4.
- After `sends 0` (NUM SEND TRACKS 0), the row under SEL read VOLUME, PAN, MUTE, SOLO, ARM REC: the send switch was gone. Pressing the third switch chose mute mode. At the next mode report the knobs had gone back from send to level, with send index 0 (log).
- `sends 16` put the sends back.

**Consequence.** "FX" is only the label of the send-mode switch, and the screen above it names the selected send. The switch exists only while the host reports at least one send, and the Roto-Control leaves send mode when the host reports none. With no outputs to send to, `RotoDriver` should report no sends (inference; it reports one per send output now).

### Test 8 (2026-11-01): send knobs with `01`, and the hold after PLUGIN mode

**Setup.** Firmware 3.3.0, `sbdev roto --type ableton` (claiming `01`), knobs in send mode. With `01` the send switch (SEL held, third screen) reads "SEND A" on top and "assign A…P" below, where `02` shows the send's name and "FX".[^test-7] PLUGIN mode is reached with MODE, then PLUGIN (seen).

**Findings** (Adam, 2026-11-01):
- **The hold after PLUGIN mode.** After `knob 1 0.5`, the Roto-Control was switched to PLUGIN mode and back to MIX (the knobs stayed in send mode). Turned up past the top, knob 1 turned freely, and its values went 16383 → 0 twice: a wrap. In PLUGIN mode `sbdev` had also sent LEARN PARAM positions for knob 1's mapped parameter.
- **The baseline.** Later in the same session, `knob 1 0.5` moved knob 1 to dead center (with `02`[^test-6], it had stopped a little left of center; seen). Turned up past the top, it **held** at about 5 o'clock (felt; the log shows 16383 and then silence).
- **Send knobs.** In three slow passes from about 0.5 to 0.93 of the range (8067–8399 up to 15135–15374), knob 1 showed no common stopping place. One pass paused 0.33 s at 13317 and another 0.43 s at 15281; the third had no pause over 0.08 s.

**Consequences.**
- Switching to PLUGIN mode and back clears the hold, as a change of knob mode does (section 6's rule). After such a switch `RotoDriver` should send the knob positions again (inference: it already does on every mode report).
- Send knobs have no indent with `01` either. The 3.1.0 release notes' send indents have not been seen on 3.3.0 with `01` or `02`.

### Test 9 (2026-11-01): where a held knob lets go

**Setup.** Firmware 3.3.0, `sbdev roto` claiming Bitwig (`02`), knobs in level mode. One `knob 1 0.5` was sent before the clockwise passes and one before the counterclockwise passes. Knob 1 was turned past the end each time until it held, then forced on until it gave way (Adam, 2026-11-01; log kept).

**Findings:**

| Pass | Held at | Silent for | Let go at |
|---|---|---|---|
| Clockwise 1 | 16383 | 2.2 s | 3524 |
| Clockwise 2 | 16383 | 4.0 s | 3256 |
| Clockwise 3 | 16383 | 2.7 s | 3264 |
| Counterclockwise 1 | 0 | 1.5 s | 13004 |
| Counterclockwise 2 | 0 | 2.5 s | 13004 |
| Counterclockwise 3 | 0 | 1.8 s | 13004 |

- The second and third passes in each direction held although no position had been sent since the first: **a forced release doesn't clear the hold.**
- From 0 the knob let go at exactly **13004**, the `02` indent[^test-5], all three times. From 16383 it let go between **3256 and 3524**, scattered around 3379 (16383 − 13004, the indent's mirror image; inference that this is related).
- Earlier tests found 13004–13078 from 0 and 3325–3693 from 16383 (section 6), so from the top the range across all tests is 3256–3693.

**Consequences.** Section 6's hold rule stands, with two additions: a forced release leaves the hold in place, and a knob forced on from 0 lands in the indent. A knob forced past either end in Performance Bridge therefore jumps to near 0 dB (from the bottom) or to about −37 dB (from the top). `SurfaceHub`'s guard against sudden jumps of more than 8,000 counts (`jumpGuard`) catches both (inference from its setting).

### Test 10 (2026-11-01): choosing the second track set

**Setup.** `sbdev bridge`, Roto-Control firmware 3.3.0, MIX mode. Adam pressed both arrow buttons at once; log kept.

**Findings:** the Roto-Control sent SET ALL TRACKS MODE with the master and return tracks (`0C 05 01`), and its screen named the set "MIX-RTN" (seen).

**Second session (2026-11-01, evening), with both sets showing the channels.** `sbdev bridge` on main after PR #53, TotalMix FX 2.10 (1), Digiface AES. The logs were written to `roto-trackset.log` and `roto-trackset2.log` and both were overwritten by later runs: run 1 survives only in the Terminal output Adam pasted into the conversation (the bridge's log of run 1, up to his Ctrl-C), and run 2 not at all (the counts below were read from it before it was overwritten; review of 2026-11-02).

- **Run 1.** Six track-set switches in 5.3 s (2.75–8.05 s), each answered with the channels' names, then nothing more from the Roto-Control: no knob reports, no touches, and no SET MIX ALL TRACKS MODE when Adam changed the knob mode with SEL. Its screens went blank after the SEL change. The bridge was still running (stopped with Ctrl-C). This has occurred once and is not explained. That the firmware stalled is an inference.
- **Run 2** (relaunched): six switches over 54 s, one per press of both arrows; knobs moved TotalMix FX's faders in both sets throughout (`/mix/in/0/0/faderlin` and `/mix/in/2/0/faderlin`).

**Consequences.** The driver shows the channels on both track sets (Adam, 2026-11-01); the outputs are no longer shown on any hardware controller. The second set has no TotalMix FX job of its own: TotalMix FX has no return tracks, and its FX returns (reverb and echo) aren't used here (Adam, 2026-11-01). Because the second set mirrors the first and keeps the page and the selected track when the set changes (fixed after the review of 2026-11-02, which found a switch went back to the first page), an accidental press leaves the knobs on the same channels. No host command sets or locks the track set (SET ALL TRACKS MODE goes only from the Roto-Control to the host), so the switch can't be turned off; this is a feature request.

### Test 11 (2026-11-02): page draws held to one per 100 ms

**Setup.** Adam's Roto-Control in MIX mode, with the app (build 250), whose `RotoDriver` draws a page
at most once every 100 ms (`pageDrawInterval`, section 3). Log `app-roto-1102.log`. Seen by Adam.

**Findings.** All as intended: on connecting, all eight screens showed their names and TotalMix FX
colors; after six quick presses each of the right and left arrows, the screens settled on the right
page and the knobs responded; a knob turned within about half a second of a page change behaved as
expected; pressing both arrows kept the page. No stall.

**Consequence.** Holding page draws back has no visible effect on the device. Whether it prevents the
freezes seen in test 4 and test 10's run 1 can't be shown by one session; that it helps stays an
inference.

### Test 12 (2026-11-04): the tape and (+) buttons, Mute Master flashing, and the MENU screen

**Setup.** Adam's Roto-Control, firmware 3.3.0, in MIX mode. Runs 1 and 2 with `sbdev roto --raw`
(claiming `02`), log `roto-icons-1104.log`; runs 3 and 4 with the app (branch `v1.0.4`), log
`app-mutemaster-1104.log`. Seen by Adam; the review of the Controls Guide (2026-11-04) asked for
the first three.

- **Run 1: the tape button** (left column, second row, left side, printed with two tape reels).
  One press sent REQUEST TRANSPORT STATUS (31.7 s) and nothing else, and the switches became the
  transport switches on the screens (seen). A second press sent SET MIX ALL TRACKS MODE with the
  modes unchanged (63.9 s), and `sbdev` redrew the page. So the tape button enters and leaves
  transport mode, and the host sees each change.
- **Run 2: the (+) button** (right of SEL). One press sent nothing; the button blinked green (seen).
  A second press sent nothing and the blinking stopped (seen). Nothing else was pressed in between,
  so what a track switch would send while it blinks (TOGGLE TRACK GROUPING, by the SysEx doc's
  description) is untested.
- **Run 3: Mute Master flashing.** With the switches in mute mode and channel 1's mute on, and
  TotalMix FX's Mute Master off, channel 1's light and its "MUTE" label both flashed orange
  (seen). Section 6's rule is confirmed. The Mute Master button's place in TotalMix FX's window was
  not checked on screen before the run; Adam found it.
- **Run 4: the MENU screen.** After the knob mode was changed to pan with SEL, the small screen
  above MODE read "MIX-TRACKS >" on its first line and "KNOBS-PAN" on its second (seen): it shows
  the track set and the knob mode without holding SEL.

**Consequences.** The Controls Guide names the tape button and the (+) button, says Mute Master
flashing as standing behavior, and points to the MENU screen for the current modes.

### Test 13 (2026-11-07): knobs through a refresh of the channels, and the pan's center

**Setup.** Adam's Roto-Control (firmware not rechecked since test 12's 3.3.0), in MIX mode, with the app (branch
`e16-four`, 1.2.0). Not logged; seen by Adam. The Tier 1 review of 2026-11-07 asked whether the
automatic refresh (a `/sendall` every 30 s while idle) moves a knob, since TotalMix FX answers with
its own rounded positions (test 3 of `docs/TOTALMIX-OSC.md`: 0.5 came back as 0.499274).

- **Run 1: a level.** Knob 1 turned to a spot between its marks and let go; then Update Hidden
  Channels (the same refresh, at once). The knob didn't move (seen).
- **Run 2: a pan.** With the knobs on pan (MENU screen), knob 2 turned a little off center and let
  go; then Update Hidden Channels. The knob didn't move (seen).

- **Run 3: the pan's center stop.** With the knobs on pan, a knob turned into its center stop
  showed C on its screen but L01 in TotalMix FX (seen). The 14-bit range has no exact middle; that
  the stop reports 8191, just under it, is an inference (not logged). With pans rounded to
  TotalMix FX's hundredths before they're sent (`RotoDriver.panInSteps`), TotalMix FX showed C
  (seen).

**Consequences.** No knob movement from the refresh in runs 1 and 2. Pan knobs are rounded to
TotalMix FX's pan steps from 1.2.0.

