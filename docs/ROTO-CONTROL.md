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
- **[test N]**: a test against a Roto-Control, described in section 9 with the firmware version. There are none yet.

A statement with no marker is an inference, and says so.

**Status.** Nothing here has been checked against a Roto-Control yet. Section 8 lists what the
first tests have to settle.

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
| SET MIX TRACK MODE | `0C 02 <page>` | Single-track mode: the controls of one track, in pages of eight. The SysEx doc gives `page` as a multiple of 8, but see "Single-track pages" below. |
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

  Which the Roto-Control sends is open (section 8). `RotoOutgoing.sendNamesStart(forControlPage:numbering:)` handles both.
- **Which send names to send.** After SET MIX ALL TRACKS MODE or REQUEST SEND TRACK NAMES, the block starts at the multiple of 8 at or below the send index. [SysEx doc] After SET MIX TRACK MODE, the SysEx doc's examples (pages 0, 8, and 16 start at sends 0, 6, and 14) fit a block that starts at the page index minus 2, and at 0 for page 0. [SysEx doc] Read as page numbers, the same layout starts at 0 for page 0 and at 6 + (page − 1) × 8 after that, as in Ableton's code. [Ableton]
- **Meter thresholds.** Ableton uses 87 and 113; Logic 106 and 120. [Ableton, Logic]
- **Meter dimming.** Ableton also sends `0C 0C` with eight bytes, one per track of the page, which the SysEx doc does not list. Ableton sends 1 for an unmuted track and 0 for a muted one, or, while any track is soloed, 1 for soloed tracks and 0 for the rest. [Ableton] The inference is that 0 dims a track's meter. `RotoControl` can send it, marked as undocumented.

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

- **Switch values.** Bitwig treats 127 as pressed and 0 as released. [Bitwig] `RotoControl` treats 64 and above as pressed.
- **Transport switches.** Ableton reads them as play, stop, record, session record, loop, punch-in, punch-out, and re-enable automation. [Ableton] That order matches TRANSPORT STATUS. [SysEx doc] Whether the Roto-Control sends them in MIX mode with a non-Logic type is untested.
- **CCs 36 and 37.** Ableton also listens on these, the two CCs after the transport switches, for rewind and fast-forward. [Ableton, Bitwig] The SysEx doc does not list them. `RotoControl` reports them as other CCs.
- **CC 64.** The Roto-Control sends it, with a knob's index as the value, and Ableton then sets that knob's parameter to its default. [Ableton] The SysEx doc names it "level at 0 dB" without saying what triggers it. For TotalMix the inference is: set that strip's fader to 0 dB, which is position 836/1023 (`FaderCurve.unityPosition`).
- **Meter values.** Ableton sends a track's meter as Live's meter reading (0–1) times 127, at most 12 times a second. [Ableton] How Live scales that reading is not in the integration, so the mapping from TotalMix's dB levels to 0–127 is this project's choice, still to be made.

## 6. Feedback to the Roto-Control

- **Moving a knob.** The host sends the same CC pair the knob sends: the high 7 bits on CC 12–19, then the low 7 bits on CC 44–51. [Bitwig, Logic] Bitwig computes the 14-bit value as the parameter (0–1) times 16383, rounded. [Bitwig]
- **Lighting a switch.** The host sends 127 (on) or 0 (off) on the switch's CC. [Ableton]
- **Unchanged values.** Bitwig does not resend a knob position it last sent, except that it resends all eight positions when it switches layers or modes. [Bitwig]
- **Value text.** Ableton sends SHOW CONTROL VALUE whenever a mapped parameter's value changes, from the knob or from Live, at most 12 times a second with one trailing update, and once when a knob is touched. [Ableton] Bitwig sends value text only in PLUGIN mode, within 100 ms (plugin parameters) or 300 ms (macro parameters) of the knob last moving; in MIX mode it sends none. [Bitwig]
- **Bitwig's command for value text.** Bitwig sends value text as `0A 0F`, the number the SysEx doc gives REQUEST ROTO SYSEX API VERSION, with the same layout as SHOW CONTROL VALUE. [Bitwig, SysEx doc] The inference is that `0A 0F` is an older form, from before SHOW CONTROL VALUE was documented. `RotoControl` sends `0A 18`, as Ableton and Logic do. [Ableton, Logic]
- **Hold-off for the motors.** Bitwig holds back a knob position for 100 ms after the knob last moved on its master and return layer, and has the same rule commented out on its track layer. While touch automation is on, it also ignores the knob for 500 ms after release, and it queues knob positions while it switches modes. [Bitwig] Ableton leaves knob feedback to Live's framework, so its rule is not visible in the integration. [Ableton] Surface Bridge will need its own rule, because TotalMix confirms nothing (docs/TOTALMIX-OSC.md, test 5): a position from TotalMix is a change made elsewhere. The planned rule, an inference, is to hold back positions for a knob while it is touched.

## 7. Errata in the SysEx doc

Noted so that nobody builds on them:

- Two sections are numbered 2.21.
- The PLUGIN headings for 3.26–3.29 use command numbers `20`–`23`, but the overview, and Logic's code, use `1A`–`1D`. [SysEx doc, Logic]
- DAW SELECT TRACK (4.4) shows the color field as `CS` in the command but defines it as `CI`. The field is the color scheme, as in TRACK DETAILS.
- The overview gives ROTO SELECT PLUGIN (`0B 07`) as sent to the Roto-Control, though its name says the Roto-Control selected the plugin. Surface Bridge does not use PLUGIN mode.
- Appendix A writes one green value as "BO" (letter O), presumably `B0`.
- Appendix B's Logic formula for a mapped parameter's CC number divides where Logic's code takes the remainder. [SysEx doc, Logic] PLUGIN mode only.
- In PLUGIN mode, the overview also gives the wrong direction for SET PLUGIN LEARN (`0B 09`) and FIRST PLUGIN (`0B 03`), and 3.26 calls both halves of the sweep value "LSB". Logic's code uses a PLUGIN command, `0B 1E`, that the SysEx doc does not list. [SysEx doc, Logic]

## 8. Open questions for the first tests

1. **The handshake.** Does the Roto-Control complete it with type `01` and `02`, and does MIX mode behave the same with both?
2. **What MIX mode needs from the host.** After CONNECTED, which of NUM TRACKS, FIRST TRACK, and TRACK DETAILS does the Roto-Control need before it shows strips?
3. **Knob messages.** Does a turned knob always send both CCs, high then low? Does it skip the high CC when only the low bits change? `RotoControl` emits a knob value when the low CC arrives, using the last high value. Bitwig divides incoming values by 16382, not 16383 [Bitwig]; what is the top value?
4. **Motor echoes.** When the host moves a knob, does the Roto-Control send the new position back?
5. **Pacing.** Does the Roto-Control drop SysEx sent without Ableton's 5 ms gaps?
6. **CC 64.** What gesture sends it?
7. **Transport switches** in MIX mode with a non-Logic type.
8. **Single-track pages.** Does SET MIX TRACK MODE carry 8 or 1 for the second page?

## 9. Tests

None yet.
