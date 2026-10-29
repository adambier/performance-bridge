# TotalMix FX Global OSC: what this project relies on

This is a working reference for the parts of TotalMix FX's Global OSC interface that Surface Bridge
uses, with the evidence for each statement. It is written in this project's own words; it is not
a copy of RME's documentation.

**Sources.** Two kinds of evidence back the statements below:

- **[RME doc]**: RME's Global OSC protocol document for TotalMix FX 2.1 beta 2, revision 2026-07-21. It is not included in this repository.
- **[RME manual]**: the TotalMix FX chapter of RME's Digiface AES User's Guide (PDF dated 2023-11-20). It predates Global OSC, so it describes TotalMix's settings, not this protocol.
- **[test N]**: a test against TotalMix, described in section 6 with the TotalMix version, the interface, and the settings used.

A statement with neither marker is an inference, and says so.

**Status.** Five tests so far (section 6). They cover what TotalMix sends with "Send faders in
linear scale" off and on, and the fader messages it accepts.

## 1. Connection

- TotalMix receives on its "incoming" port and sends to its "outgoing" port. Both ports, and the address of the computer that receives TotalMix's messages, are set in TotalMix's preferences. Surface Bridge's defaults are localhost, incoming 7001, and outgoing 9001.
- **Bundles.** TotalMix sends every message inside an OSC bundle. [test 3]
  - A single change, or a status message, comes as a bundle of one message.
  - The `/sendall` reply comes as bundles of up to 16 messages, none larger than 480 bytes.
  - The OSC codec accepts both bundles and single messages.
- The document does not say how many clients TotalMix serves.
- The document says "Follow Submix" should be off when Global OSC is used. [RME doc]
  - TotalMix's Options menu has no item by that name. The closest is "Submix linked to MIDI / OSC controller (1-4)": "The 8-channel group follows the currently selected submix", whether the submix is chosen on the remote or in TotalMix, and it "can be useful to deactivate this feature for specific windows". [RME manual]
  - The inference is that this is the setting the document means. Test 1, with it on, showed no effect on what Global OSC sends.
- "Lock Remote to submix", on the OSC page of TotalMix's preferences, lets a remote "only modify the submix selected from the drop-down list". [RME manual] It is left off: Surface Bridge chooses submixes itself.
- The document says status is sent at about one parameter per second. [RME doc] It does not define "status"; the inference here is that it means the `/status/…` messages.

## 2. Numbering and values

- Channels count from 0 in addresses: `/input/2/…` is input 3 in TotalMix's window. Snapshots, layouts, and groups count from 1. [RME doc]
- **Stereo channels.** A stereo channel is addressed by its left channel. A few parameters differ between left and right, and their right side is addressed as the left channel + 1. [RME doc] Those parameters are `phase`, `gain`, `delay`, and the Room EQ bands and types.
- **Hidden channels.** Options → Channel Layout can hide channels from each OSC remote ("Hide Channel in OSC Remote 1-4"). Channels hidden in the mixer are also unavailable to OSC. [RME manual] With classic OSC, hidden channels are skipped within a block of faders. [RME manual] With Global OSC, the document says hidden channels "may be received by option" (TotalMix's "Receive to hidden channels"). [RME doc] Whether hiding renumbers the channels Global OSC sends is untested. In test 1 nothing was hidden, and the channel numbers matched the Digiface AES's 14 inputs, 16 playbacks, and 16 outputs. [RME manual, test 1]
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
- **Fader groups in `groupflags`.** Bits 12–15 are taken to be fader groups 1–4 (see section 2). Outputs 3/4 and 7/8 have bit 12 set [test 1]; whether they are in fader group 1 has not been checked in TotalMix's window.

## 6. Tests

### Test 1 (2026-10-28): what TotalMix sends

**Setup.** TotalMix FX shown as "2.10 (1)" in its About window, with a Digiface AES, and `sbdev monitor`
on the same Mac. RME's protocol document is for 2.1 beta 2; whether "2.10 (1)" is that build is not
known.

- **TotalMix's OSC preferences.** Controller 4, Global OSC mode, incoming port 7004, outgoing port 9004, remote host localhost.
- **Details options.** "Send changes" and "Send status" on. "Send all data on start", "Send faders in linear scale", "Re-send received", and "Send Level Data" off.
- **Options menu.** "Submix linked to MIDI / OSC controller (1-4)" on.
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

So, with "Re-send received" off, TotalMix does not echo a command to its sender. Surface Bridge
therefore records the values it sends itself. The only messages that can move a surface's control
are changes made elsewhere, in TotalMix's window or from another client.

**The check.** `roundtrip` does receive on the outgoing port. `/sendchan/output/8`, a request that
must be answered, came back with output 9's settings: the first bundle after 21 ms and the last
after 40 ms. They included `faderlin` 0.386085 (−20.00 dB), the value the last command had set.
