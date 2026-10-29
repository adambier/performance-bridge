# TotalMix FX Global OSC: what this project relies on

This is a working reference for the parts of TotalMix FX's Global OSC interface that Surface Bridge
uses, with the evidence for each statement. It is written in this project's own words; it is not
a copy of RME's documentation.

**Sources.** Two kinds of evidence back the statements below:

- **[RME doc]**: RME's Global OSC protocol document for TotalMix FX 2.1 beta 2, revision 2026-07-21. It is not included in this repository.
- **[tested]**: a test against TotalMix, with the TotalMix version and the interface named.

A statement with neither marker is an inference, and says so.

**Status.** As of this revision, nothing here has been tested against TotalMix. Every statement is
from the document, or an inference.

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

- **`volume`.** What unit is the channel setting `volume` in, and how does it relate to `faderlin`? The document gives no unit.
- **The current submix.** Do `/<bus>/<channel>/volume` and `faderlin` act on the submix selected in TotalMix's window? Or are they used only where no submix applies, as for outputs? (Unknown.)
- **`groupflags`.** The document gives bits 1–4 for mute groups 1–4 and bits 6–9 for solo groups 1–4. For fader groups 1–4 it gives "12..16", which is five bits for four groups. Bit numbering from 0 or from 1 is also not stated.
- **`GAINSUBMIXOFF`.** What value marks off? Is it −300 dB, as the mixer node's `fader` suggests? (An inference, untested.)
- **`/sologroup` and `/fadergroup`.** The document gives no value type for either.
- **Bundles.** Does TotalMix send bundles, and how many messages a second does it send during `/sendall` and while meters run?
- **The re-send options.** RME notes that the re-send options can trigger "ping-pong transmissions and lag of faders and dials". How do they interact with a motorized surface? Surface Bridge's plan is to leave them off and suppress echoes itself.
- **"Not implemented."** The document's legend marks unimplemented commands in red. In revision 2026-07-21 no populated cell is red, so the inference is that everything listed is implemented.
