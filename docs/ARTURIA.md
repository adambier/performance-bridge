# Arturia instruments: what a controller can learn from them

This is a working reference for one question: whether a program can control Arturia's standalone
instruments (Pigments, MiniFreak V, the V Collection) in both directions, so that a motorized
controller such as the Roto-Control can follow them. It records what has been found, with the
evidence for each statement. Nothing in Performance Bridge uses it yet; the `ArturiaControl`
library holds the message formats, and `sbdev vport` is the probe. It is written in this project's
own words, and nothing from Arturia's files is copied here. This project is not affiliated with or
endorsed by Arturia.

**The short answer.** Yes, within limits. An instrument that finds a MIDI port named like one of
Arturia's first KeyLab keyboards reports parameter changes to it as they happen and takes plain
control changes from it.[^test-1] The limits: nine useful controls an instrument, 7-bit values, no
value text, and no way yet known to ask for the values on connecting (sections 3 and 5).

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote: a test with the instrument running, described in section 6, or a
reading of the files Arturia installs, described in section 1. Statements from the files say what
the files declare, not what an instrument has been seen to do. Where something is reasoning that
has not been checked, the text says so in words ("inference", "untested").

[^test-1]: [Test 1](#test-1-2026-11-13-pigments-and-a-virtual-keylab-61) (2026-11-13), section 6;
    Pigments 7.0.1 standalone.
[^files]: The files Arturia's installers put on Adam's Mac, read on 2026-11-13 by two AI agents
    working through a read-only view of the folders (section 1). Their reports and scripts are
    kept outside this repository. The reading was not repeated by a second reader.
[^code]: The same agents' reading of the Pigments plugin's program file (version 7.0.1): the text
    strings in it and, for the SysEx messages, the instructions that build them. Kept outside this
    repository, and not repeated by a second reader.

## 1. Sources

- **Tests** with an instrument running, in section 6. One so far.
- **Installed files** (Pigments 7.0.1.6772, MiniFreak V 5.1.1.6945, Analog Lab V 5.12.6.6914, and
  about 45 V Collection and Augmented instruments, as their bundles give their versions).[^files]
  Each instrument has, among its resources:
  - a list of controller profiles, shared by nearly all instruments: for each of Arturia's
    controllers, the MIDI port names it goes by and what the instrument sends it;
  - its MIDI configurations: which control change number is assigned to which parameter;
  - its parameter list, which gives the parameters' names.
- **The Pigments plugin's program file**, for what the profile file leaves out: the bytes of each
  message.[^code]

Arturia publishes none of this as a protocol. The profile for Arturia's newer controllers (KeyLab
mk3 and others) uses a second, larger message family that has not been looked at beyond its
headers.[^code]

## 2. How an instrument finds a controller

- An instrument picks a controller profile by the name of a MIDI port.[^files] The profile named
  "KeyLab" (the first KeyLab keyboards) lists four names, "KeyLab 25", "KeyLab 49", "KeyLab 61",
  and "KeyLab 88", and does not ask for partial matches, so the inference is that the name must be
  exact. Only "KeyLab 61" has been tried.
- Pigments took a virtual port named "KeyLab 61" for that controller as soon as the port was
  turned on under MIDI Devices in its audio and MIDI settings window (reached from the main menu
  at the top left of Pigments' window; the labels were not recorded), and not before: with the
  port published but not turned on there, it sent nothing.[^test-1]
- It then showed "KeyLab" as both its MIDI Controller and its MIDI Config, without being
  told to (seen by Adam).[^test-1] Its saved controller before the test was "KeyLab mk3"[^files];
  whether the change is saved is not known.
- Pigments' MIDI Config menu lists three factory configurations: Generic, KeyLab (marked as the
  default), and Empty (seen).[^test-1]
- A profile cannot be added without changing Arturia's files[^files], which this project does not
  do (AGENTS.md, section 4). So a program that wants an instrument's reports has to publish a port
  under one of a real controller's names.

## 3. From the instrument to the controller

Every message is SysEx with Arturia's manufacturer ID, `F0 00 20 6B … F7`. In the "KeyLab"
profile's format the next two bytes are `7F 42`.

| Message | Bytes after `F0 00 20 6B 7F 42` | Evidence |
|---|---|---|
| A control's value | `02 <p> 00 <item> <value>` | seen[^test-1] |
| The display's text | `04 <p> 60`, then fields: a tag byte, ASCII text, a 0 byte | seen[^test-1] |
| A light | `02 <p> 10 <item> <value>` | code only[^code] |
| A light's color | `02 <p> 11 <item> <value>` | code only[^code] |
| A 14-bit value | `0A <p> <b> <item> <high 7 bits> <low 7 bits>` | code only[^code] |

`<p>` was `00` in every message seen.[^test-1]

- **Values.** `value` is 0–127 and `item` is the controller's number for the control (section 4).
  Pigments sent one for each change to Macro 1 made in its own window: 76 messages over two drags,
  a median of 17 ms apart, covering 0 to 127.[^test-1]
- **Preset changes.** Loading the next preset sent eight values within 10 ms, then the text
  message.[^test-1] The eight items are the nine controls Pigments' "KeyLab" configuration
  assigns, less item 1, whose value (0) was the one last reported.[^files] The inference is that a
  preset change reports each assigned control whose value differs from the last one reported.
- **No echo.** A control change sent to Pigments moved the control and drew no message back in
  the 7.9 s before the next change made in the window.[^test-1]
- **Text.** The fields seen were tag 1 with the instrument's name ("Pigments"), tag 2 with the
  preset's name behind an asterisk, tag 3 with a second word about the preset ("Bells",
  "Template"), and tag 4 empty. The message came twice each time, when the controller was first
  found and after the preset change.[^test-1] What the asterisk means is not known; it was there
  on a preset just loaded. No text came with a value: a parameter's name and its value in words
  (e.g., "50%") have not been seen.
- **Nothing on connecting.** The profile declares that current values are sent just after
  connecting[^files], but when the port was turned on with Pigments already running, only the
  text came.[^test-1] Whether the values come when an instrument starts with the port already
  turned on is untested.
- **Resolution.** The value message carries 7 bits. Nine times in the second drag, a message
  repeated the value before it[^test-1]; the inference is that the parameter moved by less than
  one step in 127, so it is finer inside the instrument. The code has a 14-bit value message, but
  no profile Arturia installs asks for it.[^files][^code]

## 4. From the controller to the instrument

- **Control changes.** The profile pairs each control's control change number with its item
  number[^files]:

  | Control change | 7 | 74 | 71 | 76 | 77 | 93 | 18 | 19 | 16 | 17 | 91 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | Item | 48 | 1 | 2 | 3 | 4 | 9 | 5 | 6 | 7 | 8 | 10 |

  Control change 74 on channel 1 with value 100 moved Pigments' Macro 1 to about three quarters
  (seen), and the next value Pigments reported for item 1 was 102, from a drag that began
  there.[^test-1]
- **What the controls are.** 48 of the 49 instruments with factory MIDI configurations have one
  named "KeyLab".[^files] In those:
  - 74, 71, 76, and 77 are macros 1–4 (in the Augmented instruments, their four macro parameters
    under other names);
  - 17 is a master or output volume;
  - 93, 18, 19, and 16 are four parameters of the instrument's own (e.g., a filter, oscillator
    levels, effect mixes);
  - 7 is assigned in none, and 91 in two.

  So nine controls an instrument are of use. Analog Lab V differs: its "KeyLab" configuration is
  in another file and assigns the controls to parameters of its own that stand for whatever the
  loaded preset maps.[^files]
- **Parameters the user assigns.** The reports follow the control change number, not the
  parameter.[^files] The inference, untested, is that a parameter the user assigns to one of the
  eleven control change numbers with the instrument's MIDI learn would be reported under that
  number's item.
- **Asking for values.** No request for all current values is known for this profile. Analog Lab
  V's configurations for some later controllers assign control change 118 to a parameter that
  sends them[^files]; other instruments have the parameter but assign nothing to it.
- **Finer control.** Every assignment in the installed configurations is a 7-bit control change.
  The code also takes NRPN and RPN, but how one would be assigned was not found.[^files][^code]

## 5. Open questions

1. Do the values come when an instrument starts with the port already turned on? If not, a
   controller knows a control's value only after it changes or a preset loads.
2. Do MiniFreak V, Analog Lab V, and a V Collection instrument behave as Pigments does? Users have
   reported trouble with MiniFreak V's MIDI learn on
   [Arturia's forum](https://forum.arturia.com/t/bug-minifreak-v-midi-learn-not-quite-working/2615);
   nothing here has been tried with it.
3. Do "KeyLab 25" and the other names work as "KeyLab 61" does? A name of a controller the user
   doesn't own would be less confusing in the instrument's settings (Adam, 2026-11-13).
4. Does a parameter assigned by MIDI learn report under its control change's item?
5. Does the change of controller and configuration persist, and does it disturb a real KeyLab mk3
   used with the same instrument afterward? After test 1, Adam set MIDI Controller back to
   "KeyLab mk3" by hand; MIDI Config stayed on "KeyLab", the factory default.
6. Can a control be driven, or reported, with more than 7 bits (NRPN in; the newer controllers'
   message family out)?
7. Is the plugin, in a DAW, reachable the same way? The reading suggests the controller code is
   in the plugin[^code], but a DAW has its own, better path to a plugin's parameters.

## 6. Tests

Run with `sbdev vport <port name>` (macOS), which publishes a virtual MIDI source and destination
under that name and prints every message sent to the destination with the time since starting.

### Test 1 (2026-11-13): Pigments and a virtual "KeyLab 61"

**Setup.** Adam's Mac, Pigments 7.0.1 standalone[^files], `sbdev vport "KeyLab 61"` on branch
`vport-probe` at `5a39d70`. The log (95 lines: 88 messages received and 1 sent) is kept outside
this repository; the counts below come from a script over it. Adam's notes are marked "seen". His
own KeyLab 61 mk3 goes by another port name; whether it was plugged in was not recorded.

**Findings:**

- **Before the port was turned on.** The ports were published at 0 s and Pigments opened after
  that. Nothing arrived until 77 s.
- **Turning the port on** (the audio and MIDI settings window, MIDI Devices, "KeyLab 61"): the text message at
  77.145 s and again at 77.163 s, with "Pigments", "*Hang Me Some Me", "Bells", and an empty
  fourth field. No value message followed.
- **A drag of Macro 1 with the mouse**, up and down: 41 value messages for item 1 in 1.0 s
  (117.886–118.884 s), from 1 up to 127 and down to 0, a median of 17 ms apart, with one pause of
  0.35 s at the top.
- **The next preset** (the arrow by the preset's name): eight value messages in 10 ms
  (230.489–230.499 s), for items 8, 2, 3, 4, 9, 5, 6, and 7 in that order, with values 86, 0, 0,
  0, 127, 0, 127, and 0; then the text message at 230.500 s and 230.501 s, with "Pigments",
  "*Welcome", and "Template". Item 1, last reported as 0, was not among them.
- **A control change in** (`cc 1 74 100`, sent at 264.575 s): Macro 1 jumped to about three
  quarters (seen). Nothing arrived until Adam dragged the knob himself, 7.9 s later.
- **That drag:** 35 value messages for item 1 (272.471–274.030 s), the first with 102, between 102
  and 127; nine of them repeated the value before.
- **Every value message** was 12 bytes, with `00 00` between `7F 42 02` and the item. The log
  holds no other kind of message than these two.
- **Afterward** (seen): Pigments' MIDI tab showed "KeyLab" for both MIDI Controller and MIDI
  Config. Set back to "KeyLab mk3", the controller stayed there and MIDI Config stayed on
  "KeyLab"; its menu lists Generic, KeyLab (default), and Empty under Factory.

**Not tested.** Any other instrument; any other port name; a control other than Macro 1 moved by
hand; the lights; starting Pigments with the port already on.
