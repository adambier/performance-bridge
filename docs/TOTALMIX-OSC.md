# TotalMix FX Global OSC: what this project relies on

This is a working reference for the parts of TotalMix FX's Global OSC interface that Surface Bridge
uses, with the evidence for each statement. It is written in this project's own words; it is not
a copy of RME's documentation.

**Sources.** Two kinds of evidence back the statements below:

- **[RME doc]**: RME's Global OSC protocol document for TotalMix FX 2.1 beta 2, revision 2026-07-21. It is not included in this repository.
- **[test N]**: a test against TotalMix, described in section 6 with the TotalMix version, the interface, and the settings used.

A statement with neither marker is an inference, and says so.

**Status.** One test so far (section 6), covering what TotalMix sends. What it accepts is not yet
tested.

## 1. Connection

- TotalMix receives on its "incoming" port and sends to its "outgoing" port. Both ports, and the address of the computer that receives TotalMix's messages, are set in TotalMix's preferences. Surface Bridge's defaults are localhost, incoming 7001, and outgoing 9001.
- The document does not say whether TotalMix sends bundles or single messages, how many clients it serves, or what limits its sending rate. The OSC codec accepts both bundles and single messages.
- The document says "Follow Submix" should be off when Global OSC is used. [RME doc]
- The document says status is sent at about one parameter per second. [RME doc] It does not define "status"; the inference here is that it means the `/status/…` messages.

## 2. Numbering and values

- Channels count from 0 in addresses: `/input/2/…` is input 3 in TotalMix's window. Snapshots, layouts, and groups count from 1. [RME doc]
- **Stereo channels.** A stereo channel is addressed by its left channel. A few parameters differ between left and right, and their right side is addressed as the left channel + 1. [RME doc] Those parameters are `phase`, `gain`, `delay`, and the Room EQ bands and types.
- **Index values.** List-box settings, such as `reflevel` and the EQ band types, are index values from 0. Their meaning depends on the device. [RME doc]
- **Value types.** TotalMix accepts true/false and integers wherever it expects a float. [RME doc] `OSCArgument.numericValue` reads all of these forms.
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

- **`volume` and `faderlin` with "Send faders in linear scale" on.** With the option off, output faders arrive as `volume` in dB and mixer nodes as `fader` in dB, and no `faderlin` was sent at all. [test 1] The inference is that the option switches both to `faderlin`. Which messages TotalMix accepts in each setting is also untested.
- **The current submix.** Input and playback channels sent no channel-level `volume` or `faderlin`: their faders in TotalMix's window arrived as mixer nodes of the selected submix. [test 1] Whether TotalMix accepts a channel-level `volume` for inputs, and what it would act on, is untested.
- **`groupflags`.** The document gives bits 1–4 for mute groups 1–4 and bits 6–9 for solo groups 1–4. For fader groups 1–4 it gives "12..16", which is five bits for four groups. Bit numbering from 0 or from 1 is also not stated. Outputs 3/4 and 7/8 reported 4098 = 2¹² + 2¹ [test 1]. Read from 0, that is mute group 1 and fader group 1; read from 1, mute group 2 and fader group 2. The groups those outputs belong to in TotalMix will settle it.
- **Unanswered `/sendall`.** One `/sendall` went unanswered: status messages arrived, but nothing else. A later one, with the same settings, was answered in full. [test 1] The cause is unknown; the app should repeat the request if no reply comes.
- **`/sologroup` and `/fadergroup`.** The document gives no value type for either. Both were sent as 0 or 1 by group. [test 1]
- **Bundles.** Does TotalMix send bundles? `sbdev monitor --packets` shows them.
- **Control-room assignments.** `mainout`, `phones1`, and `phones2` arrived as 0, 2, and 6, and the unused assignments as −1. [test 1] The inference, from the channel names, is that each value is the 0-based number of the assigned output's left channel (0 = "Monitors", 2 = "ADI-2 3/4", 6 = "Phones 2"), and −1 means none.
- **The re-send options.** RME notes that the re-send options can trigger "ping-pong transmissions and lag of faders and dials". How do they interact with a motorized surface? Surface Bridge's plan is to leave them off and suppress echoes itself.
- **"Not implemented."** The document's legend marks unimplemented commands in red. In revision 2026-07-21 no populated cell is red, so the inference is that everything listed is implemented.

## 6. Tests

### Test 1 (2026-10-28): what TotalMix sends

**Setup.** TotalMix FX 2.1 beta (exact build to be recorded) with a Digiface AES, and `sbdev monitor`
on the same Mac:

- **TotalMix's OSC preferences.** Controller 4, Global OSC mode, incoming port 7004, outgoing port 9004, remote host localhost.
- **Details options.** "Send changes" and "Send status" on. "Send all data on start", "Send faders in linear scale", "Re-send received", and "Send Level Data" off.
- **Options menu.** "Submix linked to MIDI / OSC control" on.
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
