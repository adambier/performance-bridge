# Arturia instruments: what a controller can learn from them

This is a working reference for one question: whether a program can control Arturia's standalone
instruments (Pigments, MiniFreak V, the V Collection) in both directions, so that a motorized
controller such as the Roto-Control can follow them. It records what has been found, with the
evidence for each statement. Nothing in the Performance Bridge app uses it yet; the
`ArturiaControl` library holds the message formats, `sbdev vport` is the probe, and `sbdev
arturia` is a prototype that puts an instrument on the Roto-Control (test 2). It is written in this project's
own words, and nothing from Arturia's files is copied here. This project is not affiliated with or
endorsed by Arturia.

**The short answer.** Yes for Pigments, in two tests, within limits. Pigments, finding a MIDI
port named like one of Arturia's first KeyLab keyboards, reported changes to its macros to it as
they happened and took plain control changes from it[^test-1][^test-2]; in the second test a
prototype kept a Roto-Control's knobs and Pigments' controls in step in both directions.[^test-2]
Analog Lab V, in one test with the probe, reported to the same port and took a control change
from it.[^test-3] The other instruments share the profile file but are untested. The limits:
nine useful controls an instrument (eleven in Analog Lab V), 7-bit values, and no way yet known
to ask for the values (sections 3 and 5).

**Which controller to imitate.** The KeyLab mkII's profile uses the same messages as the first
KeyLab's and adds what the first lacks: when a control is changed from the controller, Analog
Lab V and Pigments each sent the control's name and its value in words (e.g., "F1 Cutoff" and
"1448 Hz").[^test-4] Analog Lab V sent the name the preset gives the control; Pigments sent its
parameter's fixed name ("Macro 1", where its window shows "Timbre"). Everything here is about
the standalone apps. Nothing has been tested with the plugins in a DAW, and nothing found here
should be assumed to hold there (Adam, 2026-11-14).

**How sure each statement is.** A plain statement describes what was found. A statement that rests
on a source has a footnote: a test with the instrument running, described in section 6, or a
reading of the files Arturia installs, described in section 1. Statements from the files say what
the files declare, not what an instrument has been seen to do. Where something is reasoning that
has not been checked, the text says so in words ("inference", "untested").

[^test-1]: [Test 1](#test-1-2026-11-13-pigments-and-a-virtual-keylab-61) (2026-11-13), section 6;
    Pigments 7.0.1 standalone.
[^test-2]: [Test 2](#test-2-2026-11-14-pigments-and-a-roto-control-through-sbdev-arturia)
    (2026-11-14), section 6; Pigments standalone, version not rechecked since test 1.
[^test-3]: [Test 3](#test-3-2026-11-14-analog-lab-v-and-a-virtual-keylab-61) (2026-11-14),
    section 6; Analog Lab V standalone, version not read that day.
[^test-4]: [Test 4](#test-4-2026-11-14-a-virtual-keylab-mkii-61-with-analog-lab-v-and-pigments)
    (2026-11-14), section 6; Analog Lab V and Pigments standalone, versions not read that day.
[^files-2]: The controller profile files and one preset file, read directly on Adam's Mac
    (read-only) on 2026-11-14: `controllers-common.prefmidi.xml` in Pigments' resources,
    `controllers.prefmidi.xml` in Analog Lab V's, and Pigments' factory preset "Hanging Threads".
    One reader.
[^files]: The files Arturia's installers put on Adam's Mac, read on 2026-11-13 by two AI agents
    working through a read-only view of the folders (section 1). Their reports and scripts are
    kept outside this repository. The reading was not repeated by a second reader.
[^code]: The same agents' reading of the Pigments plugin's program file (version 7.0.1): the text
    strings in it and, for the SysEx messages, the instructions that build them. Kept outside this
    repository, and not repeated by a second reader.

## 1. Sources

- **Tests** with an instrument running, in section 6. Three so far: two with Pigments and one
  with Analog Lab V, and one with both.
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
  at the top left of Pigments' window; the labels were not recorded) (seen); the log holds
  nothing before then.[^test-1]
- It then showed "KeyLab" as both its MIDI Controller and its MIDI Config, without being
  told to (seen by Adam).[^test-1] Its saved controller before the test was "KeyLab mk3"[^files];
  whether the change is saved is not known.
- The day after test 1, the port was listed under MIDI Devices again but turned off (seen).[^test-2]
  So Pigments either doesn't keep that setting or drops it when the port goes away; which is not
  known.
- Pigments' MIDI Config menu lists three factory configurations: Generic, KeyLab (marked as the
  default), and Empty (seen).[^test-1]
- **The profiles compared.**[^files-2] The first KeyLab's, the KeyLab Essential's, and the KeyLab
  mkII's all use the message family of section 3 (the files call it version 2). The Essential's
  and the mkII's carry a flag for displaying values, which the first KeyLab's lacks; test 4 shows
  what it does. Both list nine controls, on control changes 74, 71, 76, 77, 93, 18, 19, 16, and
  17 as items 1–9 (so items 5–9 are not the first KeyLab's). The mkII's port names are "KeyLab
  mkII 49", "61", and "88", each also with " MIDI" or " (1)" after it. In Analog Lab V's own
  file these profiles also declare that all values are sent when a certain control change
  arrives; the shared file doesn't. The KeyLab mk3's and Essential mk3's profiles use a newer
  family (version 3: another display message, a property message for knob values, and a connect
  step), which has not been read further.
- With a port named "KeyLab mkII 61", Analog Lab V chose "KeyLab mkII" as its MIDI Controller by
  itself; in Pigments Adam had to choose it (seen).[^test-4] Why they differed is not known.
- The audio and MIDI settings window is titled "Audio MIDI Settings" in Pigments, and the list
  is "MIDI ports" under "MIDI Settings" (seen).[^test-4]
- A profile cannot be added without changing Arturia's files[^files], which this project does not
  do (AGENTS.md, section 4). So a program that wants an instrument's reports has to publish a port
  under one of a real controller's names.

## 3. From the instrument to the controller

Every message is SysEx with Arturia's manufacturer ID, `F0 00 20 6B … F7`.[^test-1][^code] In
the "KeyLab" profile's format the next two bytes are `7F 42`.

| Message | Bytes after `F0 00 20 6B 7F 42` | Evidence |
|---|---|---|
| A control's value | `02 <p> 00 <item> <value>` | seen[^test-1] |
| The display's text | `04 <p> 60`, then fields: a tag byte, ASCII text, a 0 byte | seen[^test-1] |
| A light | `02 <p> 10 <item> <value>` | seen, from Analog Lab V[^test-3] |
| A light's color | `02 <p> 11 <item> <value>` | code only[^code] |
| A 14-bit value | `0A <p> <b> <item> <high 7 bits> <low 7 bits>` | code only[^code] |

`<p>` was `00` in every message seen.[^test-1]

- **Values.** `value` is 0–127 and `item` is the controller's number for the control (section 4).
  Pigments sent value messages while Macro 1 was dragged in its own window (seen): 76 messages
  over two drags, a median of 17 ms apart, covering 0 to 127.[^test-1]
- **Preset changes.** Loading the next preset sent eight values within 10 ms, then the text
  message.[^test-1] The eight items are the nine controls Pigments' "KeyLab" configuration
  assigns, less item 1, whose value (0) was the one last reported.[^files] One inference,
  untested: a preset change reports only the controls whose values changed. Item 1's value in the new preset
  was not recorded and items 2–9 had not been reported before, so the burst fits other rules too.
- **No echo.** A control change sent to Pigments moved the control and drew no message back in
  the 7.9 s before the next change made in the window.[^test-1] In test 2, 231 control changes
  sent over 22 s moved Macro 1 (seen) and drew none.[^test-2] So a controller has to keep the
  values it sends.
- **Analog Lab V** sent every value when the port was turned on and again at a preset change,
  with lights and the text; its text's first field named the instrument the preset comes from
  ("Pigments", "Augmented VOICES"), not Analog Lab. Its window names its controls differently
  for each preset (e.g., "Filters", "Density", "Time", and "FX", then "Color", "Morph", "Time",
  and "Motion"; seen), and none of those names was sent, on connecting, at the preset change, or
  while four of the controls were dragged.[^test-3]
- **A control's name and value, under the mkII profile.** After a control change from the
  controller, the instrument sent the text message with the control's name in field 1, its value
  in words in field 2, field 3 empty, and in field 4 the letter "c", the control change's number
  and value as two bytes, and ";". It came three times within about 0.1 s, and the usual text
  (instrument, preset, type) came back 2.0 s later. Five control changes, five times.[^test-4]
  The values read "0.236", "0.709", and "39 %" from Analog Lab V and "0.472" and "1448 Hz" from
  Pigments. A drag in the instrument's window drew no such text (Analog Lab V, two drags); so
  the text follows the controller's own changes, an inference from those two cases.
- **Text.** The fields seen were tag 1 with the instrument's name ("Pigments"), tag 2 with the
  preset's name behind an asterisk, tag 3 with a second word about the preset ("Bells",
  "Template"), and tag 4 empty. The message came twice each time, when the controller was first
  found and after the preset change.[^test-1] What the asterisk means is not known; it was there
  on a preset just loaded, and in test 3 on a preset whose name had none in Analog Lab V's
  window.[^test-3] Under the first KeyLab's profile no text came with a value; under the
  mkII's it does (above).
- **On connecting: sometimes.** The profile declares that current values are sent just after
  connecting.[^files] When the port was turned on in test 1, only the text came[^test-1]; in test
  2 the same action brought all nine values within 46 ms, and then the text[^test-2]; in test
  4, with the mkII port, Pigments sent lights and the text and no values.[^test-4] What
  differed is not known; which controller Pigments had selected beforehand was not recorded in
  any of the three, and is the first thing to hold fixed next time (Adam, 2026-11-14) (in test 1 Pigments was started after the port existed; in test 2 it may
  have been running already). Whether the values come when an instrument starts with the port
  already turned on is untested.
- **Resolution.** The value message carries 7 bits, and a motorized knob following it moves in
  visible steps (seen).[^test-2] Ten times in test 1 (once in the first drag, nine in the second)
  a message repeated the value before it[^test-1], several just after a pause; in test 2's five
  logged drags, 145 of 480 did.[^test-2] The
  inference, unconfirmed, is that the parameter moved by less than one step in 127; a message for
  each movement of the mouse would look the same. The code has a 14-bit value message, but
  no profile Arturia installs asks for it.[^files][^code]

## 4. From the controller to the instrument

- **Control changes.** The profile pairs each control's control change number with its item
  number[^files]:

  | Control change | 7 | 74 | 71 | 76 | 77 | 93 | 18 | 19 | 16 | 17 | 91 |
  |---|---|---|---|---|---|---|---|---|---|---|---|
  | Item | 48 | 1 | 2 | 3 | 4 | 9 | 5 | 6 | 7 | 8 | 10 |

  Control change 74 on channel 1 with value 100 moved Pigments' Macro 1 to about three quarters
  (seen), and the next value Pigments reported for item 1 was 102, from a drag that began
  there.[^test-1] In test 2, control change 93 changed Filter 1's cutoff in the preset then
  loaded, and control change 17 the master volume (seen; neither logged).[^test-2]
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
  loaded preset maps.[^files] In test 3 it reported all eleven items, with item 48 (control
  change 7) at a value that fits its Master knob, an inference; items 1–4 moved as its first four
  knobs were dragged, and control change 74 moved the first (seen).[^test-3]
- **Per-preset names.** Pigments' window labels its four macros per preset, and its factory
  preset file holds those labels as four named fields ("Hanging Threads": Timbre, Time,
  Inharmonicity, and Delay, as the window showed).[^files-2][^test-4] So a controller that knows
  the instrument and the preset (the text message gives both) could read the labels from the
  preset's file. Untested, and open: two presets of one name, where user presets are kept,
  whether other instruments store the labels the same way, and a label changed but not saved.
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

1. Do the values come when an instrument starts with the port already turned on, and why did
   turning the port on bring them in test 2 and not in test 1? Until that is known, a controller
   can count on a control's value only after it changes or a preset loads.
2. Do MiniFreak V and a V Collection instrument behave as Pigments does? (Analog Lab V: test
   3.) Does any profile carry Analog Lab V's per-preset control names? The newer controllers'
   message family, not yet read, is the place to look. Users have
   reported trouble with MiniFreak V's MIDI learn on
   [Arturia's forum](https://forum.arturia.com/t/bug-minifreak-v-midi-learn-not-quite-working/2615);
   nothing here has been tried with it.
3. Do "KeyLab 25" and the other names work as "KeyLab 61" does? (With the mkII's profile now the
   better one to imitate, the same question goes for "KeyLab mkII 49" and "88".) A name of a controller the user
   doesn't own would be less confusing in the instrument's settings (Adam, 2026-11-13).
4. Does a parameter assigned by MIDI learn report under its control change's item?
5. Does the change of controller and configuration persist, and does it disturb a real KeyLab mk3
   used with the same instrument afterward? After test 1, Adam set MIDI Controller back to
   "KeyLab mk3" by hand; MIDI Config stayed on "KeyLab", the factory default. What Pigments
   showed there before and after test 2 was not recorded.
6. Can a control be driven, or reported, with more than 7 bits (NRPN in; the newer controllers'
   message family out)?
8. Do Arturia's apps share their MIDI settings, and does that explain why the same step went
   differently from run to run (Adam, 2026-11-14)? Where each app saves them has not been read.
9. Which control change makes Analog Lab V send all its values under the mkII profile, and does
   it work?
7. Is the plugin, in a DAW, reachable the same way? The reading suggests the controller code is
   in the plugin[^code], but a DAW has its own, better path to a plugin's parameters.

## 6. Tests

Run with `sbdev vport <port name>` (macOS), which publishes a virtual MIDI source and destination
under that name and prints every message sent to the destination with the time since starting.
The times are when `sbdev` received each message. The version used for test 1 did not yet print
decoded lines. Test 2 used `sbdev arturia`, which publishes the same kind of port and runs the
`ArturiaRotoDriver` prototype between it and a Roto-Control.

### Test 1 (2026-11-13): Pigments and a virtual "KeyLab 61"

**Setup.** Adam's Mac, Pigments 7.0.1 standalone[^files], `sbdev vport "KeyLab 61"` on branch
`vport-probe` at `5a39d70`. The log (95 lines: 88 messages received and 1 sent) is kept outside
this repository; the counts below come from a script over it. Adam's notes are marked "seen". His
own KeyLab 61 mk3 goes by another port name; whether it was plugged in was not recorded.

**Findings:**

- **Before the port was turned on.** The ports were published at 0 s and Pigments opened after
  that (seen). Nothing arrived until 77 s.
- **Turning the port on** (seen: the audio and MIDI settings window, MIDI Devices, "KeyLab
  61"): the text message at
  77.145 s and again at 77.163 s, with "Pigments", "*Hang Me Some Me", "Bells", and an empty
  fourth field. No value message followed.
- **A drag of Macro 1 with the mouse** (seen), up and down: 41 value messages for item 1 in 1.0 s
  (117.886–118.884 s), from 1 up to 127 and down to 0, a median of 17 ms apart, with one pause of
  0.35 s at the top.
- **The next preset** (the arrow by the preset's name): eight value messages in 10 ms
  (230.489–230.499 s), for items 8, 2, 3, 4, 9, 5, 6, and 7 in that order, with values 86, 0, 0,
  0, 127, 0, 127, and 0; then the text message at 230.500 s and 230.501 s, with "Pigments",
  "*Welcome", and "Template". Item 1, last reported as 0, was not among them.
- **A control change in** (`cc 1 74 100`, sent at 264.575 s): Macro 1 jumped to about three
  quarters (seen). Nothing arrived for 7.9 s, until Adam dragged the knob himself (seen).
- **That drag:** 35 value messages for item 1 (272.471–274.030 s), the first with 102, between 102
  and 127; nine of them repeated the value before. The first drag has one such repeat, of 127
  on either side of its pause.
- **Every value message** was 12 bytes, with `00 00` between `7F 42 02` and the item. The log
  holds no other kind of message than these two.
- **Afterward** (seen): Pigments' MIDI tab showed "KeyLab" for both MIDI Controller and MIDI
  Config. Set back to "KeyLab mk3", the controller stayed there and MIDI Config stayed on
  "KeyLab"; its menu lists Generic, KeyLab (default), and Empty under Factory.

**Not tested.** Any other instrument; any other port name; a control other than Macro 1 moved by
hand; the lights; starting Pigments with the port already on.

### Test 2 (2026-11-14): Pigments and a Roto-Control, through `sbdev arturia`

**Setup.** Adam's Mac; Pigments standalone (7.0.1 in test 1; not rechecked); his Roto-Control,
firmware 3.3.0; `sbdev arturia --wait` on branch `vport-probe` at `044c4b1`, with the port named
"KeyLab 61". The prototype offers the Roto-Control one macro plugin (`docs/ROTO-CONTROL.md`,
section 4a): knobs 1–4 on items 1–4 (macros 1–4), knobs 5–8 on items 9, 5, 6, and 7, and, on a
second page, knob 1 on item 8 (the volume). The log is kept outside this repository, and the
counts below come from a script over it. It is whole from 0 to 182.2 s and has two later pieces
(207.6–209.1 s and 249.9–276.1 s); what happened after 276 s was not copied. Adam's notes are
marked "seen".

**Findings:**

- **Before the port was turned on.** Pigments may have been running before `sbdev` started (Adam
  was not sure). Nothing arrived from it in the first 84.5 s.
- **Turning the port on.** "KeyLab 61" was listed under MIDI Devices and turned off (seen); Adam
  turned it on. Eleven value messages arrived in 46 ms (84.561–84.607 s), covering all nine items
  (items 8 and 3 came twice), and then the text message, once: "Pigments", "*Hang Me Some Me",
  "Bells", and an empty fourth field. The values were 0 for items 1, 2, 3, 5, and 7; 59 for item
  4; 127 for items 6 and 9; and 87 for item 8.
- **On the Roto-Control** (seen): the plugin's name in the top line of the MENU window became
  "Pigments", with the bottom line dark; the eight knob names lost the "?" that marks an unknown
  value. The preset's name, which the prototype sent with SET CURRENT TRACK NAME, showed nowhere,
  in PLUGIN mode or, after MODE and MIX, in MIX mode.
- **Knob 1 turned by hand,** three times (160.2–182.2 s): 341 position reports from the
  Roto-Control, from 138 to 16028, became 231 control changes for controller 74, with values 1 to
  124. Pigments' Macro 1 moved and the percentage showed on the knob's screen (seen). Pigments
  sent nothing in those 22 s.
- **Drags in Pigments' window** (seen; five in the log, of Macro 1 and Macro 2): 480 value
  messages, a median of 16 or 17 ms apart in each drag, 145 of them repeating the value before.
  The prototype sent 333 knob positions, each within 6 ms of its value message, and the knobs
  followed (seen): evenly, but in visible steps. A step of 1 in 127 is 129 of the knob's 16,383
  positions.
- **A preset change** (seen; not in the log): the knobs moved to new positions.
- **Knob 5** (seen; not in the log): changed Filter 1's cutoff. The preset's name was not
  recorded.
- **The second page** (seen; not in the log): knob 1 moved Pigments' master volume; the other
  seven screens were dark.

**Not tested.** Any other instrument or port name; `sbdev arturia` without `--wait`; starting
Pigments with the port already on; a real KeyLab used afterward. What Pigments' MIDI tab showed
before and after was not recorded.

### Test 3 (2026-11-14): Analog Lab V and a virtual "KeyLab 61"

**Setup.** Adam's Mac; Analog Lab V standalone (5.12.6 in the file reading of 2026-11-13; not
read again); `sbdev vport "KeyLab 61"` on branch `vport-probe` (its `vport` unchanged since
`044c4b1`), with its output also written to a file. The log (712 lines) is whole and is kept
outside this repository; the counts below come from a script over it. Adam's notes and two
screenshots of Analog Lab V's window are marked "seen". The question was whether Analog Lab V
sends the names it gives its controls for each preset.

**Findings:**

- **Turning the port on.** Analog Lab V was opened after the port was published; "KeyLab 61" was
  listed under MIDI Devices, turned off (seen), and Adam turned it on. In 86 ms (62.506–62.594 s)
  came 31 value messages covering eleven items (1–10 and 48), 11 light messages for five lights
  (items `12`, `13`, `14`, `1E`, and `1F` hex), and the text once: "Pigments", "*Fever Keys",
  "Lofi Keys", and an empty fourth field. The window showed the preset "Fever Keys*", from the
  instrument Pigments, with MIDI Controller "KeyLab" (seen).
- **The values against the window.** Items 1–4 were 51, 100, 67, and 46, and item 48 was 109; the
  window's first four knobs were labeled Filters, Density, Time, and FX, beside a Master knob
  (seen). That item 48 is the Master is an inference from its value and the knob's position.
- **Four drags** of knobs in the window (seen in the log as items 1, 2, 3, and 4, in that order;
  which knob each was, was not noted): 338 value messages, a median of 6 to 8 ms apart, 204 of
  them repeating the value before. No text and no light came with them.
- **Another preset** ("Fiber Lines", from Augmented VOICES): 20 value messages in 20 ms for nine
  items (1–8 and 48; not 9 or 10), four light messages, and the text twice: "Augmented VOICES",
  "*Fiber Lines", "Poly Lead". The window showed "Fiber Lines" with no asterisk and the first
  four knobs as Color, Morph, Time, and Motion (seen). Items 2 and 3 were 64 and 127, which fits
  Morph at the middle and Time at full in the screenshot.
- **Names.** None of the knob names in the window appears in any message of the log.
- **The nine faders** in the window were not reported under any item.
- **A control change in** (`cc 1 74 64`, at 519.4 s): the Color knob jumped to about the middle
  (seen). Nothing came back before the log ends.

**Not tested.** Whether items 5–10 are the window's other knobs; the faders moved by hand; the
lights' meaning; what Analog Lab V's MIDI tab showed before the test, and whether its setting
changed.

### Test 4 (2026-11-14): a virtual "KeyLab mkII 61", with Analog Lab V and Pigments

**Setup.** Adam's Mac; `sbdev vport "KeyLab mkII 61"` on branch `vport-probe`, with its output
also written to a file; Analog Lab V standalone, still running from test 3 with the preset "Fiber
Lines", and then Pigments standalone. The log (635 lines) is whole and is kept outside this
repository; the counts below come from a script over it. Adam's notes and screenshots are marked
"seen". The probe labels values with the first KeyLab's control change numbers, which are wrong
for items 5–9 under this profile; the items below are as received.

**Analog Lab V:**

- **Connecting.** In 88 ms (14.284–14.372 s): 29 value messages for items 1–9, 23 light messages
  for 14 lights, and the text once ("Augmented VOICES", "*Fiber Lines", "Poly Lead"). Its MIDI
  Controller read "KeyLab mkII", and the window showed nine knobs over nine faders (seen). Adam
  did not choose the controller.
- **Two drags in the window** (Color, then Chorus Mix; seen): 172 value messages for item 1 and
  94 for item 5. No text.
- **Control changes from the probe.** `cc 1 74 30`: the text "Color", "0.236", three times from
  66 ms after, and the usual text 2.06 s after. `cc 1 74 90`: "Color", "0.709"; Color moved to
  about 70% (seen). `cc 1 93 50`: "Chorus Mix", "39 %"; Chorus Mix moved (seen). No value message
  followed any of them.
- **Quitting** sent a value 0 for item 89 and one short message of another kind (`7F 42 00 00 05
  00` after the manufacturer ID), not seen before.

**Pigments** (preset "Hanging Threads", whose macros the window labels Timbre, Time,
Inharmonicity, and Delay; seen):

- **Connecting.** Adam turned the port on under MIDI ports and had to choose "KeyLab mkII" as the
  MIDI Controller himself (seen); MIDI Config read "KeyLab" and Fader Mode "Scale" (seen). In
  28 ms (610.557–610.585 s): 27 light messages for 11 lights and the text once ("Pigments",
  "*Hanging Threads", "Evolving Keys"). No value message.
- **Control changes from the probe.** `cc 1 74 60`: "Macro 1", "0.472", three times from 24 ms
  after; the M1 bar in the window rose (seen in two screenshots). `cc 1 93 80`: "F1 Cutoff",
  "1448 Hz". Pigments' MIDI tab lists 74 as Macro 1 and 93 as F1 Cutoff (seen).

**Not tested.** Whether a control turned on a real controller draws the text for every step or
only now and then; the faders; the value request; any other instrument; either plugin in a DAW.
