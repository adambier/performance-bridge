# TotalMix FX Global OSC: what this project relies on

This is a working reference for the parts of TotalMix FX's Global OSC interface that Performance Bridge
uses, with the evidence for each statement. It is written in this project's own words; it is not
a copy of RME's documentation.

**Sources.** Two kinds of evidence back the statements below:

- **[RME doc]**: RME's Global OSC protocol document for TotalMix FX 2.1 beta 2, revision 2026-07-21. It is not included in this repository.
- **[RME manual]**: the TotalMix FX chapter of RME's Digiface AES User's Guide (PDF dated 2023-11-20). It predates Global OSC, so it describes TotalMix's settings, not this protocol.
- **[RME forum]**: a post by RME's staff on RME's user forum, linked where it is cited.
- **[Adam]**: information from the project's owner, from his use of TotalMix, without a published source cited here.
- **[test N]**: a test against TotalMix, described in section 6 with the TotalMix version, the interface, and the settings used.

A statement with neither marker is an inference, and says so.

**Status.** Five tests so far (section 6). They cover what TotalMix sends with "Send faders in
linear scale" off and on, and the fader messages it accepts.

## 1. Connection

- **Version.** Global OSC needs TotalMix FX 2.1 or later; earlier versions don't have it, and release candidates of 2.1 or later are fine. [Adam, 2026-10-31; RME's document is for "TotalMix FX 2.1 beta 2"] RME writes the version with a two-digit minor number ("1.96", "2.10"), so it reads as a decimal: "2.10 (1)" is version 2.1 (inference from the version strings seen). TotalMix doesn't send its version over Global OSC (`/status/device` gives the device's name only, test 9), so the app reads it from TotalMix's app bundle (`Info.plist`; reading TotalMix's files is always fine, Adam, 2026-10-31; which key holds the version hasn't been checked on a Mac).
- TotalMix receives on its "incoming" port and sends to its "outgoing" port. Both ports, and the address of the computer that receives TotalMix's messages, are set in TotalMix's Mixer Settings window, on its OSC tab: Options → Mixer Settings… (shortcut F3). [Adam, screenshots 2026-10-31] The Mixer Settings window's labels are "Port (incoming)" and "Port (outgoing)" under "TotalMix FX OSC Service" and "Remote Controller Address". Performance Bridge's defaults are localhost, incoming 7001, and outgoing 9001.
- **The OSC menu items** (Options menu; checked on screen, Adam, 2026-10-31). The menu lists "Enable MIDI Control", "Submix linked to MIDI Controller", "Enable OSC Control", and "Submix linked to OSC Controller" (a submenu with items 1, 2, 3, and 4, one per controller, all checked on this Mac [Adam, screenshot 2026-10-31]). The RME manual names the item "Enable MIDI / OSC Control" and does not list the OSC submenu; the running TotalMix's labels are the ones used here.
  - "Enable OSC Control" was checked on Adam's Mac.
  - Mixer Settings' OSC tab has "Select Controller" 1–4 with an "In Use" box, the two address groups described above, "Send Level Data", "Peak Hold", "Lock Remote to Submix", "Number of faders per bank", "Compatibility (Mode)" (set to "Global OSC"), and a "Details" button.
  - The Details window is titled "Gobal OSC - Detailed Settings" (TotalMix's spelling). Its options are "Send changes", "Send all data on start (enable)", "Send status", "Receive to hidden channels", "Set all faders in group", "Send faders in linear scale", "Re-send received", "Re-send if different", and a bandwidth limit ("None", "500kByte/s", "200kByte/s").
  - On the setup machine, with controller 4, "Send changes", "Send status", and "Send faders in linear scale" were on; "Send all data on start", "Receive to hidden channels", and "Re-send received" were off; the bandwidth limit was 500kByte/s. [Adam, screenshots 2026-10-31] Test 1 had "Send faders in linear scale" off, and test 2 had it on.
- **Bundles.** TotalMix sends every message inside an OSC bundle. [test 3]
  - A single change, or a status message, comes as a bundle of one message.
  - The `/sendall` reply comes as bundles of up to 16 messages, none larger than 480 bytes.
  - The OSC codec accepts both bundles and single messages.
- The document does not say how many clients TotalMix serves.
- The document says "Follow Submix" should be off when Global OSC is used. [RME doc]
  - TotalMix's Options menu has no item by that name. The closest is "Submix linked to MIDI / OSC controller (1-4)" (the manual's label; the running TotalMix shows "Submix linked to OSC Controller", a submenu of its Options menu, [Adam, screenshot 2026-10-31]): "The 8-channel group follows the currently selected submix", whether the submix is chosen on the remote or in TotalMix, and it "can be useful to deactivate this feature for specific windows". [RME manual]
  - The inference is that this is the setting the document means. Test 1, with it on, showed no effect on what Global OSC sends.
- "Lock Remote to Submix", on the OSC tab of Options → Mixer Settings… [Adam, screenshot 2026-10-31; the manual calls it "Lock Remote to submix" on "the OSC page of TotalMix's preferences"], lets a remote "only modify the submix selected from the drop-down list". [RME manual] It is left off: Performance Bridge chooses submixes itself.
- The document says status is sent at about one parameter per second. [RME doc] It does not define "status"; the inference here is that it means the `/status/…` messages.

## 2. Numbering and values

- Channels count from 0 in addresses: `/input/2/…` is input 3 in TotalMix's window. Snapshots, layouts, and groups count from 1. [RME doc] `sbdev monitor` prints channel numbers as TotalMix's window does, from 1 (its source adds 1 to each address). In this document, "input 1" or "monitor input 1" means that display number, and "address 0" means the number used in an OSC address. [Project code, `Sources/sbdev/main.swift`]
- **Stereo channels.** A stereo channel is addressed by its left channel. A few parameters differ between left and right, and their right side is addressed as the left channel + 1. [RME doc] Those parameters are `phase`, `gain`, `delay`, and the Room EQ bands and types.
- **Hidden channels.** Channel Layout can hide channels from each OSC remote. [Adam, screenshot 2026-10-31] Its window is opened by right-clicking a channel strip and choosing "Change Channel Layout", or by Options → Channel Layout…. The group "Hide Channel in" lists "OSC Controller 1" to "OSC Controller 4" (on screen, and a checked box hides the channel from that controller [Adam, confirmed 2026-10-31]); the manual's label "Hide Channel in OSC Remote 1-4" is not the label in the running TotalMix. Channels hidden in the mixer are also unavailable to OSC. [RME manual] With classic OSC, hidden channels are skipped within a block of faders. [RME manual] With Global OSC, the document says hidden channels "may be received by option" (TotalMix's "Receive to hidden channels"). [RME doc] Hiding does not renumber the channels Global OSC sends (inference from one run; the same run's input 3 keeps its number, and the hidden input sends nothing). [Adam, hide-test.log, 2026-10-31; test 8] A hidden channel sends no messages, so the app cannot tell it apart from a channel the interface does not have: it cannot detect hidden channels from OSC (test 8). In test 1 nothing was hidden, and the channel numbers matched the Digiface AES's 14 inputs, 16 playbacks, and 16 outputs. [RME manual, test 1]
- **Index values.** List-box settings, such as `reflevel` and the EQ band types, are index values from 0. Their meaning depends on the device. [RME doc]
- **Value types.** TotalMix accepts true/false and integers wherever it expects a float. [RME doc] `OSCArgument.numericValue` reads all of these forms.
- **`groupflags`.** The bits count from 0. Outputs 3/4 and 7/8, members of mute group 1, report 4098 = 2¹² + 2¹. So bit 1 is mute group 1 [test 1]; had the bits counted from 1, mute group 1 would have been the value 1. The document's ranges, read from 0, then give:
  - mute groups 1–4 in bits 1–4;
  - solo groups 1–4 in bits 6–9;
  - fader groups 1–4 in bits 12–15. The document writes "12..16", taken here to be a slip.

  Only the mute bit is confirmed; the solo and fader positions follow from the document. `TotalMixGroupFlags` decodes the value.
- **Control-room assignments.** `mainout`, `mainoutb`, `phones1`–`phones4`, `cuechan`, `extinchannel`, and `talkchannel` hold the 0-based number of the assigned channel's left channel, and −1 for none. Main Out = 0 ("Monitors", outputs 1/2), Phones 1 = 2 ("ADI-2 3/4"), and Phones 2 = 6 ("Phones 2", outputs 7/8) were sent and match TotalMix's window. [test 1] The same reading for the other assignments is an inference.
- **Triggers.** For trigger messages (`/undo`, `/sendall`, and so on), a value is optional. A value below 0.5 makes TotalMix ignore the message, so `TotalMixCommand` always sends 1.0. [RME doc]

## 3. Addresses this project uses

The three rows of the mixer are spelled three ways (`TotalMixBus`). [RME doc]

| Where | Inputs | Playbacks | Outputs |
|---|---|---|---|
| Channel settings, `/sendchan` | `input` | `playback` | `output` |
| Mixer nodes (`/mix/…`) | `in` | `pb` | (not a node source) |
| Levels (`/level/…`) | `in` | `pb` | `out` |

**Channel settings** have the form `/<bus>/<channel>/<parameter>`, with sub-paths for the low cut, EQ, dynamics, AutoLevel, and Room EQ. Examples are `mute`, `name` (a string), `faderlin`, `volume`, `balpan`, `color` (sent only), and `eq/band1gain`. [RME doc]

**Record-enable.** `record` is a channel setting that TotalMix sends and accepts. [RME doc] The document does not say what it does; the inference is that it is the channel's record-enable for DURec, TotalMix's recorder on interfaces that have one. The Digiface AES's manual does not mention DURec. [RME manual] This project does not use `record`.

**Meter colors.** RME's M-32 AD Pro lights its front-panel level meters green from −54 dBFS (barely visible) to −20 dBFS (bright), yellow from −5 dBFS, orange from −4, red from −1, and red flashing fast at 0 dBFS for at least three samples in a row. [RME: [M-32 AD Pro manual, "Meter to dB"](https://docs.rme-audio.com/m32ad/020-4r_meter_to_db/)] This is a hardware meter, not TotalMix's; that TotalMix's meters use the same steps is not established here. TotalMix's own meters reach down to about −65 dBFS: the lowest level its readout shows is −64.5 dB, and anything lower reads −∞. [Adam] Levels sent over OSC are peak levels in dB (above); SurfaceCore's `MeterScale` maps −65…0 dBFS to a surface's meter and borrows RME's −5 and −1 dBFS as its yellow and red thresholds.

**Playback names.** TotalMix names each playback after the output of the same number, because by default playback n is routed to output n alone. [RME forum](https://forum.rme-audio.de/viewtopic.php?id=36883) SurfaceCore therefore shows playbacks as "PB 1/2", "PB 3/4", and so on, so that they cannot be mistaken for inputs. Whether Global OSC sends a playback's own name or its output's has not been checked.

`color` is 0 for a hidden channel, and otherwise a color index from 1 (1 is the default color). [RME doc] TotalMix offers eight colors (Channel Layout, Color (Name)), and the index follows their order in that menu: 1 white, 2 grey, 3 orange, 4 red, 5 blue, 6 green, 7 yellow, 8 pink. [test 7] The inference is that "hidden" means hidden from this OSC remote in Options → Channel Layout; SurfaceCore leaves such channels off the strips. Whether TotalMix sends a hidden channel's settings at all is untested.

**Mixer nodes** have the form `/mix/<in|pb>/<channel>/<output>/<parameter>`. A node is the send from an input or playback to an output, that is, its level in that output's submix. [RME doc] The parameters are:

- `fader`, in dB, going down to −300 dB for off (in fader groups);
- `faderlin`, the position from 0 to 1;
- `balpan`, from −1 to +1;
- `solo`;
- `groupflags`.

**Levels** have the form `/level/<in|pb|out>/<channel>`. Each is a peak level in dB, and only changing values are sent. TotalMix sends them; it does not accept them. [RME doc]

**Requests for state** [RME doc]:

| Message | What TotalMix sends in reply |
|---|---|
| `/sendall` | Every parameter. With 2, mixer nodes are sent only where the fader is above −65 dB. |
| `/sendsettings` | Control parameters and FX settings. |
| `/sendstate` | Every status message, DURec's included. |
| `/sendchan/<bus>/<channel>` | Every setting of that channel. |
| `/sendmix` | All mixer nodes. With 2, only those above −65 dB. |
| `/sendsubmix/<output>` | The nodes of that output's submix. With 2, only those above −65 dB. |

**Snapshots:** `/snapshot/load/<number>` loads a snapshot when sent with 1. TotalMix itself sends 0 (off), 2 (active), or 3 (changed). [RME doc]

## 4. The fader curve (`faderlin`)

`FaderCurve` implements the curve the document gives for `faderlin` positions. [RME doc] The curve is defined over 1,023 steps, with position 1.0 at step 1023:

- **Upper segment.** From step 649 (−6 dB) to step 1023 (+6 dB), the gain is linear at 6/187 dB per step. In the document's decimals that is 0.0320855615.
- **Lower segment.** Below step 649 the gain is −65 + 28·step/187 − step²/11033 dB. The document writes 28/187 as 0.1497326203. This segment meets the upper one at −6 dB.
- **Inverse.** For gains at or above −6 dB, step = (187·dB + 5016)/6. Below −6 dB, step = 826 − √(−34869 − 11033·dB).
- **Off.** Gains below −64.9 dB are off. The document names the value used for off (`GAINSUBMIXOFF`) without defining it. `FaderCurve` returns `nil` for off.
- **Unity.** 0 dB is at step 836, about position 0.8172.

`FaderCurveTests` checks the fractions against the document's decimal constants at every step.

## 5. Open questions to settle by testing

- **Accepting fader messages with "Send faders in linear scale" off.** With the option on, TotalMix accepted `volume`, `faderlin`, and `fader` (test 2). Whether it accepts them with the option off is untested.
- **Echoes to other clients.** TotalMix does not send a command's result back to the client that sent it (test 5). Whether it tells other OSC remotes (controllers 1–4) about the change is untested.
- **The test 3 value.** In test 3, outputs 9/10 reported 0.499274 around the time a `faderlin` 0.5 command was sent from another window, and 0 dB 82 ms later. Given test 5, that was not an echo. The inference is that both values came from changes made in TotalMix's window.
- **The current submix.** Input and playback channels sent no channel-level `volume` or `faderlin`: their faders in TotalMix's window arrived as mixer nodes of the selected submix. [test 1] Whether TotalMix accepts a channel-level `volume` for inputs, and what it would act on, is untested.
- **Unanswered `/sendall`.** One `/sendall` went unanswered: status messages arrived, but nothing else. A later one, with the same settings, was answered in full. [test 1] The cause is unknown; the app should repeat the request if no reply comes.
- **`/sologroup` and `/fadergroup`.** The document gives no value type for either. Both were sent as 0 or 1 by group. [test 1]
- **Main Out B with Speaker B off.** Test 10 found Main Out B's submix kept the same as Main Out's with Speaker B on. Whether that holds with Speaker B off, or with Link off, is untested.
- **Fader groups in `groupflags`.** Bits 12–15 are taken to be fader groups 1–4 (see section 2). Outputs 3/4 and 7/8 have bit 12 set [test 1]; whether they are in fader group 1 has not been checked in TotalMix's window.

## 6. Tests

### Test 1 (2026-10-28): what TotalMix sends

**Setup.** TotalMix FX shown as "2.10 (1)" in its About window, with a Digiface AES, and `sbdev monitor`
on the same Mac. RME's protocol document is for 2.1 beta 2; whether "2.10 (1)" is that build is not
known.

- **TotalMix's OSC preferences.** Controller 4, Global OSC mode, incoming port 7004, outgoing port 9004, remote host localhost.
- **Details options.** "Send changes" and "Send status" on. "Send all data on start", "Send faders in linear scale", "Re-send received", and "Send Level Data" off.
- **Options menu.** "Submix linked to MIDI / OSC controller (1-4)" (the manual's label; the running TotalMix shows "Submix linked to OSC Controller", a submenu of its Options menu, [Adam, screenshot 2026-10-31]) on.
- **Moves.** Faders were moved with the mouse in TotalMix's window; no surface was connected.

**Findings:**

- **Status.** With "Send status" on, TotalMix cycles through `/status/dsp`, `/status/device`, and `/status/connection`, one message about every second; the cycle repeats every 3.2 seconds. Example values: `dsp` = 9, `device` = "Digiface AES (52103031)", `connection` = 1.
  - The inference is that the number in parentheses is the unit's serial number, and that `dsp` is a percentage.
  - No DURec or FX messages were sent. The inference is that this interface has neither.
- **The `/sendall` reply.** The reply arrived within 83 ms of the request: 962 messages.
  - **Inputs and playbacks.** Every input and playback sent its settings (`stereo`, `name`, `mute`, `phase`, `msproc`, `width`, `color`, the low cut and EQ). Inputs with a preamp also sent `gain`, `48v`, `pad`, and `autoset`.
  - **Outputs.** Every output sent `volume`, `balpan`, `mute`, `stereo`, `name`, `color`, `groupflags`, `loopback`, `talkbacksel`, the low cut and EQ. Some outputs also sent `reflevel`. The document lists `groupflags` only for mixer nodes.
  - **Mixer nodes.** Every mixer node sent `fader`, `balpan`, `solo`, and `groupflags`, all of them, not only active ones: 7 inputs and 8 playbacks into 8 outputs (all stereo).
  - **The rest.** The control room's settings, `globalmute`, `globalsolo`, mute, solo, and fader groups 1–4, and snapshots 1–8.
- **Stereo channels.** A stereo channel sent its settings under the left channel. Under the right channel it sent only the L/R parameters seen here (`phase`, and `gain` on a preamp input).
- **Off.** A mixer node that is off reports `fader` = −300 dB (107 of the 120 nodes).
- **Moving a fader in TotalMix's window:**
  - An output's fader sends `/output/<channel>/volume` in dB.
  - An input's or playback's fader sends `/mix/<in|pb>/<channel>/<output>/fader` in dB, for the submix selected in the window.
  - While a fader moves, updates arrive every 20 ms. Pauses come in multiples of 20 ms, so the inference is that TotalMix sends changes on a 20 ms cycle.
  - Values from mouse moves in the upper part of the fader's travel are multiples of 3/28 dB, e.g. −0.107143, −0.214287, and 0.642857. The inference is that this is the resolution of the fader in TotalMix's window, not of Global OSC.
- **Duplicates.** One message (`/mix/pb/10/12/groupflags`) was sent twice in the reply.

### Test 2 (2026-10-28): what TotalMix accepts

**Setup.** As in test 1, with "Send faders in linear scale" on. Each message was sent with
`sbdev send`, and the fader was watched in TotalMix's window.

**Findings.** Each message moved the fader as expected:

- `/output/8/volume` −20 set outputs 9/10 ("ADAT 1/2") to −20 dB. TotalMix accepts an output's fader in dB.
- `/output/8/faderlin` 0.5 set the same output to about −12.1 dB, the gain `FaderCurve` gives for position 0.5. TotalMix accepts the position, and its curve agrees with `FaderCurve`.
- `/mix/in/8/2/fader` −10 set the send from inputs 9/10 ("ADAT 3/4") to outputs 3/4 ("ADI-2 3/4") to −10 dB. TotalMix accepts a mixer node's fader in dB. Whether this also works while the window shows a different submix was not checked.

### Test 3 (2026-10-28): what TotalMix sends with "Send faders in linear scale" on

**Setup.** As in test 1, with "Send faders in linear scale" on, and `sbdev monitor --packets`.

**Findings:**

- **Fader messages.** Output faders and mixer nodes now arrive as `faderlin`, positions from 0 to 1; no `volume` or `fader` was sent. A mixer node that is off reports 0. The option therefore switches what TotalMix sends between dB (off) and positions (on).
- **The `/sendall` reply.** The same 962 messages as in test 1, in 79 bundles of up to 16 messages and at most 480 bytes, within 0.2 s.
- **Bundles everywhere.** No message arrived outside a bundle. Each change, and each status message, came in a bundle of its own.
- **Update rate.** While a fader moved, updates again arrived every 20 ms.
- **The 0.5 command.** Output 9/10 reported 0.499274 (−12.17 dB) at the time a `faderlin` 0.5 command was sent, and 0.817204 (0 dB) 82 ms later. See "Echoes" in section 5.

### Test 4 (2026-10-28): fader commands, one at a time

**Setup.** As in test 3, with "Send faders in linear scale" on. Each command was sent with
`sbdev roundtrip`, and the fader's value was read in TotalMix's window afterward.

**Findings.** Each command left the fader at the value expected, and the value stayed:

| Command | Fader in TotalMix's window |
|---|---|
| `/output/8/faderlin` 0.5 | −12.1 dB |
| `/output/8/volume` −20 | −20 dB |
| `/mix/in/8/2/faderlin` 0.5 | −12.1 dB |
| `/mix/in/8/2/fader` −10 | −10 dB |

- **Positions.** The gain for position 0.5 matches `FaderCurve`'s −12.13 dB, for outputs and mixer nodes alike.
- **Both forms are accepted.** TotalMix accepts dB (`volume`, `fader`) and positions (`faderlin`) with "Send faders in linear scale" on; the option governs only what TotalMix sends.

### Test 5 (2026-10-28): does TotalMix echo a command?

**Setup.** As in test 4. Each command was sent with `sbdev roundtrip`, which listens on the outgoing
port and prints everything TotalMix sends in the second after the command (status and level
messages left out).

**Findings.** Nothing came back for any of the commands:

- `/output/8/faderlin` 0.5 and `/output/8/volume` −20 were sent alternately, three times each. Each one therefore changed the fader, between −12.1 dB and −20 dB.
- `/mix/in/8/2/faderlin` 0.5 was sent, then `/mix/in/8/2/fader` −10.

So, with "Re-send received" off, TotalMix does not echo a command to its sender. Performance Bridge
therefore records the values it sends itself. The only messages that can move a surface's control
are changes made elsewhere, in TotalMix's window or from another client.

**The check.** `roundtrip` does receive on the outgoing port. `/sendchan/output/8`, a request that
must be answered, came back with output 9's settings: the first bundle after 21 ms and the last
after 40 ms. They included `faderlin` 0.386085 (−20.00 dB), the value the last command had set.


### Test 6 (2026-10-30): PFL and Live Mode

**Setup.** TotalMix FX "2.10 (1)" with a Digiface AES, through `sbdev bridge` and `sbdev monitor
--sendsettings`. The user's notes are marked "seen".

**Findings:**

- **PFL shows only in Live Mode.** `/input/<n>/pfl` 1 was sent and accepted, but the user found no sign of it in TotalMix's window until "Live Mode, PFL replaces Solo" (PFL Mode, in Settings) was turned on; then the channel's Solo/PFL button lit, and clicking it in TotalMix was sent back as `pfl` (seen). [RME manual: Live Mode replaces Solo with PFL]
- **Live Mode cannot be read.** Turning Live Mode off and on sent nothing, and the reply to `/sendsettings` does not mention it. RME's document lists only the device name, the connection, and the DSP load as status. [RME doc]
- **PFL goes to Main when Cue/PFL to is unassigned.** With `controlroom/cuechan` reported as −1, PFL on a silent input silenced Main, which had been playing another input (seen). [RME manual: the Cue/PFL to setting also routes PFL]


### Test 7 (2026-10-30): color indexes

**Setup.** TotalMix FX "2.10 (1)" with a Digiface AES. In Channel Layout, the first eight playback pairs were given the eight colors in menu order (white, grey, orange, red, blue, green, yellow, pink), and `sbdev monitor --sendall` recorded what TotalMix sent.

**Findings.** Playbacks 1, 3, 5, 7, 9, 11, 13, and 15 (each the left channel of a pair) sent `color` 1 to 8 in that order, so the index is the color's position in the menu, counting from 1. The pairs' names were the outputs' default names (AES, SPDIF, Analog 1/2, Phones, ADAT 1/2 to ADAT 7/8), as section 3 describes.

### Test 8 (2026-10-31): a channel hidden from OSC Controller 4

**Setup.** TotalMix FX "2.10 (1)" with a Digiface AES, and controller 4 (incoming 7004, outgoing 9004, host 127.0.0.1). In Channel Layout, the ADI-2 input was hidden from OSC Controller 4 ("Hide Channel in", checked; Adam's report, 2026-10-31). `sbdev monitor --sendall --in-port 7004 --out-port 9004` ran, with its output in `logs/hide-test.log` in the project folder, and it was stopped after the `/sendall` reply.

**Findings** (seen in the log):

- The `/sendall` reply came at 14:38:43, with messages for every playback and every output, and for inputs 3 to 13 (names such as "Sonos", "Mic 1/2", "Tonverk", and "ADAT 3/4").
- No message came for monitor input 1 (address 0) or monitor input 2 (address 1, the right half of the same stereo pair). The other even-numbered addresses were absent in the same way, and the reply sent them only as right-hand halves of stereo pairs, if at all.
- The outputs were all present, including "ADI-2 3/4" (output 3) and "ADI-2 +6dB" (output 5), as expected, because only an input was hidden.
- Input 3 kept its number (Sonos).

**Inferences:**

- Monitor input 1 (address 0) is the ADI-2 input. Confirmed by an unhidden baseline run (`logs/test8a-unhidden.log`, 2026-10-31, Adam): with the ADI-2 input unhidden, monitor input 1 sends "name = ADI-2" and monitor inputs 1 to 14 all appear.
- A channel hidden from an OSC Controller sends no messages on that controller. From OSC alone, the app cannot tell a hidden channel from one the interface does not have. So the app cannot detect hidden channels.
- Hiding does not renumber the channels that remain. This is one run; the baseline run shows the same numbers for the remaining inputs.

**Test 8b (same day, `logs/test8b-receive-hidden.log`):** the same run with the ADI-2 input hidden from OSC Controller 4 and "Receive to hidden channels" on (Options → Mixer Settings… → OSC → Details). Monitor input 1 sent nothing, as in the first run. Monitor inputs 3 to 14, all 16 playbacks, and all 16 outputs were present. So on this connection, turning on "Receive to hidden channels" did not make TotalMix send a hidden channel's messages.

**Test 8a (baseline, `logs/test8a-unhidden.log`):** the same run with the ADI-2 input unhidden. Monitor input 1 sent its settings, starting with `name = "ADI-2"`.

**Test 8e (same day):** with ADI-2 hidden from OSC Controller 4 and "Receive to hidden channels" off, `sbdev send /mix/in/1/8/faderlin 0.5` did not move the ADI-2 fader in TotalMix's window. With the option on, the same message moved it. Address 1 is the right half of the ADI-2 stereo pair, not its left channel (address 0), which the spec says addresses a pair. The message still went to the hidden pair, and TotalMix acted on it only with the option on. So the option lets TotalMix accept messages addressed to a hidden channel. It does not make TotalMix send that channel's state back to the remote (test 8b).

**Test 8f (same day), with the left channel's address:** the same steps with `sbdev send /mix/in/0/8/faderlin 0.5`. With ADI-2 hidden from OSC Controller 4 and "Receive to hidden channels" off, the ADI-2 fader did not move. With the option on, it moved (Adam, 2026-10-31). Afterward the fader was returned with `/mix/in/0/8/faderlin 0`, the option turned off, and ADI-2 unhidden. This confirms test 8e for the address the spec gives for a stereo pair.

**Test 9 (same day): which sends TotalMix applies.** Each message went to controller 4's incoming port (7004) with `sbdev send`, and the result was read in TotalMix's window or in `sbdev monitor --sendall`:
- `/output/8/faderlin 0.5` moved the ADAT 1/2 output fader (applied). Address 8 is monitor output 9 (ADAT 1/2).
- `/output/8/mute 1` lit the ADAT 1/2 output's M button (applied).
- `sbdev roundtrip` received no reply to a command, which matches test 5: TotalMix does not send a command's result back to the client that sent it.

**Channel numbers (corrected the same day).** The addresses count channels from 0, as the RME spec says, and a stereo pair's settings are addressed by its left channel. Earlier sends in this test used the monitor's display numbers as addresses, so they missed the intended channels:
- `/input/1/mute 1` addressed address 1 (monitor input 2, the right half of ADI-2), and `/input/3/mute 1` addressed address 3 (monitor input 4). Neither is the Sonos input (address 2). The monitor showed `input 1 mute = 0` (address 0, ADI-2) and `input 3 mute = 0` (address 2, Sonos) unchanged, as expected.
- `/playback/1/mute 1` addressed address 1 (monitor playback 2). The monitor showed `playback 1 mute = 0` (address 0, AES), unchanged, as expected.
- `/mix/in/1/8/faderlin 0.5` addressed address 1 (the right half of ADI-2), not the left channel, and it moved the ADI-2 fader. So TotalMix has been observed to act on a mixer-node message addressed to a stereo pair's right channel. It is the message used in test 8e.

**Rechecked with 0-based numbers (same day):**
- `/playback/0/mute 1` lit the AES playback's M button (applied). `/playback/0/mute 0` turned it off.
- `/input/0/mute 1` lit the ADI-2 input's M button (applied). `/input/0/mute 0` turned it off.
- `/mix/in/0/8/faderlin 0.5` moved the ADI-2 input's fader in the ADAT 1/2 submix to −12.1 dB, which matches the spec's fader curve for position 0.5 (applied). `/mix/in/0/8/faderlin 0` returned it to the bottom.

**Global mute.** The monitor reported `globalmute = 1` in the dumps before this recheck, and `globalmute = 0` after Adam turned it off with `/globalmute 0`. RME's manual calls this the Mute Master button in the Control Strip: it lights when any Mute button is pressed, and "all selected mutes can be switched off and on again" with it (docs.rme-audio.com, Control Strip). With `globalmute = 0`, `/playback/0/mute 1` lit the AES M button only partially (Adam, screenshot 2026-10-31). Inference: a partial light shows a mute that is selected but switched off by the Mute Master, so the channel was probably not muted in the audio. Not checked by listening.

**Not tested:** the other controllers, other interfaces, and the effect of the earlier sends on the channels at addresses 1 and 3.

### Test 10 (2026-10-31): Main Out B and Speaker B

**Setup.** TotalMix FX "2.10 (1)" with a Digiface AES, controller 4. Main Out was "Monitors" (`controlroom/mainout = 0`), and no Main Out B was assigned (`mainoutb = -1`, test 9's dumps). In the Control Room section, assign → Main Out B → ADAT 5/6 (Adam, 2026-10-31). Before this, every mixer node into ADAT 5/6 was off (test 9's `/sendall` dump). Music played from the Mac into Main Out.

**Findings:**
- With Speaker B on, the Main Out B strip (ADAT 5/6) showed the music on its meter, and the Monitors meter stopped (Adam). RME's manual says Speaker B "switches playback from Main Out to Main Out B" (docs.rme-audio.com, Control Room strip).
- `sbdev monitor --sendall` then reported `mainoutb = 12` (address 12, ADAT 5/6), `speakerb = 1`, and `linkab = 1`. Main Out B's mixer nodes (monitor output 13) were the same as Main Out's: Sonos at −8.2 dB; monitor inputs 5–13 and AES at 0 dB; ADI-2 and the other playbacks off.
- `/mix/in/2/0/faderlin 0.5`, sent to Main Out (address 0), set Sonos to −12.13 dB in Main Out's submix and in Main Out B's, in the same reply.
- The assign menu's item for no assignment is "None" (Adam). Afterward Sonos was returned to −8.2 dB, Speaker B turned off, and Main Out B set to None.

**Inference:** while Main Out B is assigned and Speaker B is on, Main Out B plays Main Out's submix, and TotalMix keeps the two submixes the same. So a surface that writes to Main Out's submix reaches Main Out B as well, and the home submix need not move when Speaker B is switched. Not tested: whether the mirroring holds with Speaker B off, and with Link off.
