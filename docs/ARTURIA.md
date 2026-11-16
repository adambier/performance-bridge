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
nine useful controls an instrument (eleven in Analog Lab V), 7-bit values (Pigments learned an
NRPN message as a plain control change and ignored its fine byte[^test-10]), and no way yet
known to ask for the values (sections 3 and 5).

**Which controller to imitate.** The KeyLab mkII's profile uses the same messages as the first
KeyLab's and adds what the first lacks: when a control is changed from the controller, Analog
Lab V and Pigments each sent the control's name and its value in words (e.g., "F1 Cutoff" and
"1448 Hz").[^test-4] Analog Lab V sent the name the preset gives the control; Pigments sent its
parameter's fixed name ("Macro 1", where its window shows "Timbre"). In test 7 a prototype on
this profile showed those names and values on a Roto-Control's knobs once each knob had been
turned.[^test-7] Pigments' fixed names, and each preset's labels for its four macros, can also
be read before any turn from Pigments' own files (section 4), and showed so on the device in test
9.[^files-3][^test-9] Beside a real KeyLab mk3, the Roto-Control's driver has to sit between the
keyboard and the instrument, which worked in test 9 with Pigments and Analog Lab V. Everything here is about
the standalone apps. Nothing has been tested with the plugins in a DAW, and nothing found here
should be assumed to hold there (Adam, 2026-11-14).

[ARTURIA-KEYLAB.md](ARTURIA-KEYLAB.md) arranges the same findings by controller (the first
KeyLab, the KeyLab mkII, and the KeyLab mk3), as a reference for imitating one.

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
[^test-5]: [Test 5](#test-5-2026-11-14-a-virtual-keylab-61-mk3-midi-with-pigments) (2026-11-14),
    section 6; Pigments standalone, version not read that day.
[^test-6]: [Test 6](#test-6-2026-11-14-a-virtual-keylab-61-mk3-midi-with-analog-lab-v) (2026-11-14),
    section 6; Analog Lab V standalone, version not read that day.
[^test-7]: [Test 7](#test-7-2026-11-14-a-roto-control-on-the-keylab-mkiis-profile-through-sbdev-arturia)
    (2026-11-14), section 6; Analog Lab V and Pigments standalone, versions not read that day.
[^test-8]: [Test 8](#test-8-2026-11-14-a-real-keylab-61-mk3-its-touch-and-a-second-controller-beside-it)
    (2026-11-14), section 6; Pigments standalone and Adam's KeyLab 61 mk3, versions not read.
[^test-9]: [Test 9](#test-9-2026-11-14-the-relay-a-keylab-61-mk3-and-a-roto-control-at-once)
    (2026-11-14), section 6; the keyboard's firmware 1.5.1.
[^test-10]: [Test 10](#test-10-2026-11-15-nrpn-and-pigments-midi-learn) (2026-11-15), section 6;
    Pigments standalone, version not read that day.
[^files-3]: Read directly on Adam's Mac (read-only) on 2026-11-14, under `/Library/Arturia/`:
    each instrument's `resources/plugin.prefmidi.xml` and `resources/Reference_ParamNames.xml`;
    every file under `Presets/Pigments/` (9,595, by script) and one preset file each of ten
    other instruments; and the `tmp` folders of Pigments and Analog Lab V. None is copied into
    this repository.
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
mk3 and others) uses a second message family; test 5 shows what Pigments sends in it, and
[ARTURIA-KEYLAB.md](ARTURIA-KEYLAB.md), section 5, describes it.[^code][^test-5] It gave nothing
for the knobs that the mkII's profile doesn't: the same fixed names, and 7-bit values. Test 6
shows Analog Lab V in it: its per-preset labels, again only after a turn from the
controller.[^test-6]

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

**One controller at a time.** With a real KeyLab 61 mk3 connected, checking a second port that a
profile matches moved Pigments to that port: the keyboard fell back to its plain mode, and did
not come back until its own port was unchecked and checked again. That was so for a port named
"KeyLab mkII 61" (Midi Controller changed to "KeyLab mkII") and for one named "KeyLab 88 mk3
MIDI" (Midi Controller stayed "KeyLab mk3").[^test-8] So a second controller beside a real KeyLab
has to sit between the keyboard and the instrument, passing the keyboard's messages on; `sbdev
arturia --keyboard` does (test 9).[^test-9] The instrument has to be started after the tool's
port exists: checked in a Pigments that was already running, the port got Pigments' input and
nothing from it, in one run of two.

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
  Inharmonicity, and Delay, as the window showed).[^files-2][^test-4] "Names from the
  instrument's own files", below, says how a controller can find the file.
- **Parameters the user assigns.** The reports follow the control change number, not the
  parameter.[^files] The inference, untested, is that a parameter the user assigns to one of the
  eleven control change numbers with the instrument's MIDI learn would be reported under that
  number's item.
- **Asking for values.** No request for all current values is known for this profile. Analog Lab
  V's configurations for some later controllers assign control change 118 to a parameter that
  sends them[^files]; other instruments have the parameter but assign nothing to it.
- **Finer control.** Every assignment in the installed configurations is a 7-bit control change.
  The code also takes NRPN and RPN, but how one would be assigned was not found.[^files][^code]

**Asking for a name: a touch.** A KeyLab mk3's knobs and faders sense touch. Touched and not
moved, a knob sent the control change of its control with the value it stood at, and Pigments
answered as to any control change, with the control's name and value for the keyboard's screen.
There is no touch message.[^test-8] A control change that repeats the value drew the name and
value text under the mkII's profile too. So a controller can ask for a control's name by sending
its known value again. It is not free: the value is 7-bit, and Pigments took it, moving a macro
its preset held at 0.272 to 0.268 (34 of 127) and marking the preset as changed. `ArturiaRotoDriver`
asks this way for knobs it has no name for, where its host reads no files for the instrument
(Adam, 2026-11-14).

**Why a preset's name gets an asterisk.** The instruments mark a preset as changed, with an
asterisk by its name, once any of its controls is set, even to the value it already had as
nearly as 7 bits can say it. Asking for a name sends a control's value again, so a preset whose
names were asked for shows the asterisk though nobody turned anything (tests 9 and 13).
Arturia's own keyboards do the same: a touch of a KeyLab mk3's knob is that same message, and
it marked the preset too (test 8; and Adam, 2026-11-15, of Arturia's implementation in
general). Nothing is lost by it: the preset is as it was, to within one 7-bit step for each
control asked about, and is not saved over. A guide for users should say so.

### Names from the instrument's own files

Read on Adam's Mac on 2026-11-14, read-only.[^files-3] `ArturiaParameterFiles`, `ArturiaPresetFile`,
and `ArturiaPresetMatch` (in `Sources/ArturiaControl/`) read them, and `sbdev arturia-files` prints
what they give. Used so far only by `sbdev arturia`, for Pigments; on the device the names showed
before any knob was turned, for four presets (test 9).[^test-9]

**A control's parameter.** An instrument's `resources/plugin.prefmidi.xml` has a "KeyLab" set of
assignments, each a control change number and a parameter number, and its
`resources/Reference_ParamNames.xml` lists each parameter's internal and display names. In
Pigments, counting the first list from 0, the parameters of control changes 93, 18, 19, 16, 74,
and 17 are "F1 Cutoff", "F1 Resonance", "F2 Cutoff", "F2 Resonance", "Macro 1", and "Master
Volume"; the first five are the names Pigments sent in test 7.[^test-7] That a parameter's number
is its position in the list is an inference from those five.

- For 39 other instruments the same reading gives names. For 37 they look plausible (macros 1–4
  on 74, 71, 76, and 77, and a volume on 17, in most), but for MiniFreak V it puts "All Sounds
  Off" on 74 and for DX7 V "Macro 1" on both 74 and 93, so the inference may not hold everywhere. The eight
  Augmented instruments have no parameter-name file. None has been checked on a device.
- These are the factory assignments. Analog Lab V's `tmp` folder holds a `plugin.prefmidi.xml`
  of its own; the inference, untested, is that an instrument keeps assignments the user changes
  there.

**A preset's macro labels.** An instrument's presets are files under
`/Library/Arturia/Presets/<instrument>/Factory/<bank>/` (and `User/`, seen for two instruments,
not read), each named as its preset (all 9,392 of Pigments' factory presets). A file is a text
serialization: a string is its length, a space, and its bytes, and a parameter is its name
followed by its value. It holds the preset's name, a "Subtype" or "Type", the four labels as
`Macro1_Name` to `Macro4_Name` (padded with 0 bytes in some instruments' files, empty where the
preset keeps the default), and, in Pigments' files, the macros' values and the master volume.
One file from each of nine other instruments had the labels the same way; MiniFreak V's had
none.

An instrument's text gives the preset's name cut to 15 characters ("Hang Me Some Me" for "Hang
Me Some Melodies") and, as its third field, the preset's subtype (three Pigments presets), or
its type where the file has no subtype ("Template", one preset). Counted by a script over Pigments' 9,392 factory
presets, taking a group of presets as ambiguous when its members' labels differ:

| Known to the controller | Presets left ambiguous |
|---|---|
| The name as sent | 387 |
| The name and the type | 85 |
| The name, the type, and the macros' values and the volume, within 1 or 2 of the file's | 2 |

Pigments sent every value before the text at a preset change, and no value on connecting, in
test 7, so the values are there to use only after a preset change. A value has been seen 1 off
the file's value × 127, rounded (86 for 0.673). Where the choice stays open the controller has
no labels. A preset the user has changed and not saved, and a user preset, are untried.

**Which program is sending.** The text can't tell Analog Lab V from the instrument a preset comes
from: field 1 is "Pigments" either way. The lights can: in four logs, Analog Lab V lit items
31–33 (its three control tabs) on connecting and at each preset change, and Pigments never
did.[^test-4][^test-7] `ArturiaRotoDriver.hostIsAnalogLab` goes by that, and `sbdev arturia`
reads no files then, since Analog Lab V sends its own labels and what its presets' files say of
them is unchecked: for one Memory V preset the file's labels were empty where Analog Lab V
showed "Brightness", "Timbre", "Time", and "Movement".

**Each instrument's own settings.** An instrument's `tmp` folder holds `standalone.pref` (the
MIDI ports turned on, as `MidiDevice_1` and so on, and the audio device) and `plugin.pref.xml`
(`MidiController`, among others): one set an instrument, so the standalone apps don't share
them. Across the installed products' files `MidiController` read "KeyLab mk3" in 48, "KeyLab mkII"
in 2, and "None" in 4. When the files are written was not worked out. `tmp/lastpresetc.pref` is
the last preset in the preset files' format, labels included, but in Pigments it was written
when the app quit, not when a preset loaded, so it can't say what is loaded now.

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
6. Can a control be driven, or reported, with more than 7 bits? Not reported, under the mk3's
   profile: 137 values from Pigments were 7-bit (test 5). Not driven by NRPN or by the 14-bit
   pair of control changes 6 and 38, in Pigments (test 10): its MIDI learn took control change
   6 alone. Untried: other 14-bit pairs, the other instruments, and a narrowed range (the
   table's Min and Max) to make 127 steps finer over part of a parameter.
7. Is the plugin, in a DAW, reachable the same way? The reading suggests the controller code is
   in the plugin[^code], but a DAW has its own, better path to a plugin's parameters. With a
   KeyLab 61 mk3 in its Arturia program, Analog Lab V as a plugin in Bitwig Studio took the
   keyboard's encoder itself, and Bitwig was not told of the change (`docs/ROTO-CONTROL.md`,
   test 17), which fits the reading. Test 12: yes, for Analog Lab V in Bitwig Studio, on a
   port it finds by name, with its control changes coming through the DAW. Test 13: the same
   for Pigments, and with a relay that passes everything on to a real keyboard. Open: the
   single instruments as plugins, and another DAW.
8. Do Arturia's apps share their MIDI settings, and does that explain why the same step went
   differently from run to run (Adam, 2026-11-14)? Each instrument has settings files of its
   own (section 4), so not by a shared file; when an instrument reads and writes them, and so
   why Pigments chose "KeyLab mkII" by itself in test 7 and not in test 4, is still open.
9. Which control change makes Analog Lab V send all its values under the mkII profile, and does
   it work?
10. Do the names read from files show rightly on the device, for Pigments (test A9 of the plan)?
    Then: an instrument where the reading looks wrong (MiniFreak V), a user preset, and a preset
    changed and not saved.
11. In Analog Lab V, do a preset's first four controls follow its file's four macro labels, in
    order? If so the files could name them before a turn there too.
12. Why did a running Pigments send nothing to a port newly checked in it, in one run of test 9,
    when in test 8 it did? And how long do the two extra passes through macOS's MIDI system add
    to a note (the time inside the tool is about 0.03 ms)?
13. In a DAW, an instrument's parameters are not 7-bit. Does Bitwig Studio with the plugin give
    the Roto-Control finer values, names before any turn, and the presets' own labels (the next
    tests; `docs/PLUGIN-MODE-PLAN.md`)?
14. Does a second part's names tell a Multi in Analog Lab V? As loaded, part 2's twenty
    parameters are "P2 Param0" to "P2 Param19" (test 11). If a Multi renames them and a preset
    of one part doesn't (an inference, not seen), a host could tell the two by name.
15. Are the Audio Unit's and the standalone app's parameter lists the same as the VST3's
    (test 11)?
16. What decides which KeyLab port a plugin takes when it loads? With a real KeyLab 61 mk3 and
    a virtual port of another size's name both present, it took the virtual one in seven loads
    of eight (tests 12 and 13). The one exception was the first load after the tool that
    publishes the port had been stopped and started with the plugin loaded. Untried: a
    virtual port with the real keyboard's own name, two virtual ports, and the real keyboard
    plugged in after the port is published.

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

### Test 5 (2026-11-14): a virtual "KeyLab 61 mk3 MIDI", with Pigments

**Setup.** Adam's Mac, with his real KeyLab 61 mk3 unplugged; Pigments standalone, already
running (preset "Hanging Threads", Midi Controller "KeyLab mkII" from test 4, whose port had gone);
then `sbdev vport "KeyLab 61 mk3 MIDI"`, with its output also written to a file. The log (176
lines) is whole and is kept outside this repository; the counts below come from a script over
it. The probe does not decode this message family, so the readings below are from the bytes.
Adam's notes and a screenshot are marked "seen".

- **Before the port was turned on.** The port was published with Pigments running. It was listed
  under MIDI ports, turned off (seen), and nothing arrived in the first 60 s.
- **Turning the port on** (seen): Midi Controller changed to "KeyLab mk3" by itself. In 74 ms
  (60.187–60.261 s) came 22 messages, all with the header `7F 42 00 0D`: three connect messages
  (on, off, on), a screen with "Hanging Threads*" and "Evolving Keys", and screens 1–8, some more
  than once, the first four each with an icon number and a color and the last four empty. No
  knob value.
- **A control change in** (`cc 1 74 70`): Macro 1 moved (seen). 27 ms later a screen with
  "0.551", "Macro 1", and the value 70, three times; 2.0 s later the preset screen and screens
  1–8 again.
- **A drag of Macro 1 in the window** (seen): 137 value messages in 3.2 s, each with item 0, the
  value in one byte (0–127; 107 different values), and a last byte that was 0 every time.
- **Removing the port** with Pigments running (seen): nothing was turned on under MIDI ports
  afterward, and Midi Controller still read "KeyLab mk3".

**Not tested.** Analog Lab V under this profile; the Save, Undo, Redo, Back, and display button
control changes (Save could overwrite a preset); anything sent to Pigments in this format; a
real KeyLab mk3 beside the virtual port.

### Test 6 (2026-11-14): a virtual "KeyLab 61 mk3 MIDI", with Analog Lab V

**Setup.** Adam's Mac, with his real KeyLab 61 mk3 unplugged and Pigments quit; Analog Lab V
standalone, already running with the preset "Fiber Lines" and Midi Controller "Generic 9 Knobs";
then `sbdev vport "KeyLab 61 mk3 MIDI"`, with its output also written to a file. The log (240
messages) is whole and is kept outside this repository; the counts below come from a script over
it. Adam's notes and screenshots are marked "seen".

- **Before the port was turned on** (seen): Analog Lab V showed a "Controller Setup" window, "Let's
  set up your KeyLab 61 mk3", offering a firmware update to version 1.5.1. Nothing had arrived on
  the port. Adam chose "Cancel & close". The port was listed under MIDI ports, turned off.
- **Turning the port on** (seen): Midi Controller changed to "KeyLab mk3" by itself, a "Fader Mode"
  setting (None) appeared under it, and a row of faders appeared under the knobs. In 0.19 s
  (203.996–204.188 s) came 50 messages, all with the header `7F 42 00 01`: three connect messages
  (on, off, on); 29 knob values, all nine three times over (two more for items 6 and 7), matching
  the window (Color 90, Morph 64, Time 127, Master 109, …); four messages setting a second
  property of items 51–54 to 0; screens 1–8, some twice; and the preset screen, "Fiber Lines*" and
  "Poly Lead".
- **A control change in** (`cc 1 74 70`): Color moved from about 0.7 to about 0.55 (seen). 28 ms
  later an undecoded `03 0D 11 11 11 00`, then a screen with "0.551", **"Color"**, and the value 70,
  three times, in the same bytes as Pigments' "Macro 1" screen; 2.0 s later the preset screen and
  screens 1–4 and 8.
- **Stepping to the next preset** with the window's arrow, to "00 SYNTH (Sweep with Glide)", whose
  first four knobs read Brightness, Timbre, Time, and Movement (seen): in 0.12 s, 32 messages,
  the old and new preset screens, `03 0F 01 01 01 00`, 19 knob values (item 0 three times: 0, then
  127 twice), and the button screens twice. None of the four labels.
- **A drag of Brightness in the window** (seen): 146 value messages for item 0 in 1.4 s (66
  different values, 6–127, the last byte always 0), the preset screen with an asterisk added, and
  `03 0F 01 01 01 00` again. No label.
- **Removing the port** with Analog Lab V running (seen): nothing was turned on under MIDI ports
  afterward, and Midi Controller still read "KeyLab mk3".

**Not tested.** A preset change from the controller (control changes 114 and 115); the faders;
the Save, Undo, Redo, Back, and display button control changes; anything sent in this format.

### Test 7 (2026-11-14): a Roto-Control on the KeyLab mkII's profile, through `sbdev arturia`

**Setup.** Adam's Mac; his Roto-Control (firmware 3.3.0); `sbdev arturia --wait --device
"Roto-Control"` at commit `f0da505` (run 1), then `e910d19` (runs 2 and 3), publishing "KeyLab mkII
61", with its output written to a file. Three runs: Analog Lab V (runs 1 and 2), then Pigments
(run 3), each standalone. The three logs (1,233, 643, and 2,499 lines) are whole and are kept
outside this repository; the counts below come from a script over them. Adam's notes and
screenshots are marked "seen".

- **Choosing the controller** (seen). In Analog Lab V, already set to "KeyLab mkII", only the port
  needed checking. Pigments, last set to "KeyLab mkII" in test 4 by hand, switched to it by itself
  when the port was checked. Each time the port was published again it came back unchecked, in
  both apps. After the last run, Pigments showed no port checked and Midi Controller still read
  "KeyLab mkII".
- **On connecting**, Analog Lab V sent all nine values (three times) and the text, "Memory" and
  "*00 SYNTH (Sweep", the preset's name cut to 16 characters.
- **The MENU window** (seen): "Memory >" over "00 SYNTH (Sw" in run 1, "Prophet-VS >" over "00
  ZENNY 1" in run 2, and "Pigments >" over "Hanging Thre" in run 3. The bottom line is SET CURRENT
  TRACK NAME's text, cut to 12 characters on the device. In test 2 the same message showed
  nothing; what differs between the runs is not known.
- **Names and value text** (seen). Each knob turned on the Roto-Control was renamed with the
  instrument's name for the control and then showed the instrument's value text: Analog Lab V's
  "Brightness" ("0.528" … "0.583"), "Chorus Mix" ("6 %"), and, in the log only, "Phaser Mix"; Pigments' "F1
  Cutoff", "F1 Resonance", "F2 Cutoff", and "F2 Resonance". The matching controls moved in the
  instruments' windows, except F2 Resonance in Pigments, which Adam found has no control for the
  preset's Filter 2 type (HP6); Pigments still took it and named it.
- **Counts.** 387 control changes went to the instruments; 417 control texts came back (each
  usually three times, every copy counted). Matched to the control change they answer, the texts came a median of
  43–54 ms after it (all three copies counted; 90% within about 0.1 s, the slowest 0.3 s).
- **A preset change** (seen): the names went back to "Macro 1" … "Param 4", the knobs moved, and
  the MENU window showed the new preset, with both apps. For Pigments, whose names don't change
  with the preset, that loses names for nothing; Adam chose to keep names across presets for a
  list of instruments, Pigments first (commit after this test).
- **Two flaws, fixed between and after runs.** In run 1 a late answer to an earlier step of a knob
  still being turned was taken for a change made elsewhere, and the knob moved back one step
  when let go (seen in the log; fixed in `e910d19`, and in run 2 the knob stayed put, seen). In
  runs 1 and 2 a held-back value text came due while the instrument's text was awaited and
  showed a percentage for a moment ("47%" between "0.480" and "0.472"; fixed in `3a857b9`, not
  yet run).

**Not tested.** The first value of a turn before any text has come shows a percentage ("53%",
"34%"), as designed; values the instrument reports without a turn (a preset change, a mouse drag)
show percentages too. Any instrument but these two; the plugins.

### Test 8 (2026-11-14): a real KeyLab 61 mk3: its touch, and a second controller beside it

**Setup.** Adam's Mac and his KeyLab 61 mk3 (ports "KeyLab 61 mk3 MIDI" and "KeyLab 61 mk3 DAW");
Pigments standalone. `sbdev midi "KeyLab 61 mk3 MIDI"` printed what the keyboard sent; `sbdev
vport` published a second port. Four short logs, whole, kept outside this repository. What the
keyboard's screen and Pigments' windows showed is Adam's report ("seen"); what Pigments sent the
real keyboard could not be logged.

- **Touch, with no instrument running.** Touching encoder 1 and fader 1 sent nothing; the screen
  showed "Encoder 1" and "Fader 1" with a number (seen). Turning encoder 1 sent control change
  74, values 0–9.
- **Touch, with Pigments connected** (the keyboard showing the instrument's picture, "Welcome*",
  and "Template"; seen). Touching encoder 1 sent control change 74 with value 0, and touching
  fader 1 control change 73 with value 0 (five messages in all); the screen showed "Macro 1", "0"
  and "Env Amp Attack", ".537 ms" (seen).
- **A touch changes the preset** (seen). With "Hanging Threads" just loaded, the Delay macro read
  0.272; after a touch of encoder 4 it read 0.268, and the preset's name had an asterisk.
- **A second port, as a KeyLab mkII.** With the keyboard's port and "KeyLab mkII 61" both checked,
  Midi Controller read "KeyLab mkII" (seen), the virtual port got the lights and the text, and the
  keyboard's screen showed "Encoder 1" for a touch (seen).
- **A second port, as another KeyLab mk3** ("KeyLab 88 mk3 MIDI"). Midi Controller read "KeyLab
  mk3" (seen); the virtual port got the connect messages, all nine values, and the preset's
  screen; the keyboard's screen still showed "Encoder 1" (seen), and a touch on the keyboard
  brought nothing to the virtual port.
- **After the second port went away** the keyboard stayed in its plain mode, with only its own
  port checked (seen), until that port was unchecked and checked again (seen).
- **A repeated value under the mkII's profile.** `cc 1 74 40` twice, 8 s apart, to "KeyLab mkII
  61": each drew "Macro 1", "0.315" three times. On connecting this time Pigments sent all nine
  values.

**Not tested.** Analog Lab V; whether a touch's value differs from the last the instrument sent
the keyboard; the relay (`sbdev arturia --keyboard`).

### Test 9 (2026-11-14): the relay: a KeyLab 61 mk3 and a Roto-Control at once

**Setup.** Adam's Mac; his KeyLab 61 mk3, updated that hour from firmware 1.5.0 to 1.5.1 (test 8
ran on 1.5.0); his Roto-Control; `sbdev arturia --wait --device "Roto-Control" --keyboard "KeyLab
61 mk3 MIDI"`, three runs at commits `b9be295` (port "KeyLab 88 mk3 MIDI"), `ed504dc`, and
`4951f1a` (port "KeyLab 49 mk3 MIDI"); Pigments, then Analog Lab V, standalone. Three logs (3,888,
3,174, and 1,063 lines), whole, kept outside this repository; counts are from them. What the
devices and windows showed is Adam's report ("seen").

- **Connecting.** Pigments, opened with the tool's port published, had that port checked already
  from test 8, beside the keyboard's own (seen); it sent the connect messages, the screens, and
  the values through the tool. Unchecking the keyboard's own port made Pigments disconnect, and
  the keyboard lost the picture until the tool's port was unchecked and checked again (seen). In
  run 2, a port of a new name, checked in a Pigments already running, got Pigments' input and
  nothing back, also after unchecking and checking; quitting Pigments and opening it again, with
  the port there, connected it (seen).
- **The keyboard through the tool** (seen): the instrument's picture and the preset's name, and the
  name and value on a touch or a turn, as without the tool. It showed nothing when a knob was
  turned on the Roto-Control.
- **Names from files** (seen, and in the log): the MENU window read "Pigments" over the preset;
  knobs 1–4 took each preset's labels from its file ("Get The Info": Anger, Speed, Sanity, Delay;
  "Welcome": Timbre, Time, Unison, Reverb, chosen from two files by its type; "Leadustrial":
  Timbre, Time, Vocoder, Reverb), and knobs 5–8 the parameter names, before any knob was turned.
- **A turn of the keyboard's encoder 1** moved the Roto-Control's knob 1 (seen). In run 1 it was
  jerky and showed percentages between Pigments' value texts (seen, a video; in the log, late
  answers moved the knob back a step and forward again); with both fixed (`ed504dc`) it was smooth
  and showed only Pigments' texts (seen, run 2 after the reconnect).
- **A turn of the Roto-Control's knob 1**, then a touch of the keyboard's encoder 1: the value
  did not jump back (seen). The tool had sent the keyboard each new value in the instrument's
  format (299 messages), and the touch sent the last of them, 106. So the keyboard takes it.
- **Time in the tool** for the keyboard's messages, from `status`: over 1,460 messages, a median
  of 0.032 ms, a 99th percentile of 0.070 ms, and 0.107 ms at most. Playing felt no later than
  without the tool (seen). The two more passes through macOS's MIDI system are not in the figure.
- **Analog Lab V, asked for names** (runs 2 and 3). In run 2 the copies of one answer were taken
  for the next knobs' answers ("Macro 3" on knobs 3, 4, and 5), and names stayed across presets
  because the driver still took the program for Pigments; both fixed in `4951f1a`. In run 3, two
  presets each had all eight knobs named within about 2 s of loading, with nothing touched
  ("Fiber Lines": Color, Morph, Time, Motion, Chorus Mix, Phaser Mix, Delay Volume, Reverb Volume,
  the last cut to 12 characters on the device; "22 Bongo 2": Brightness, Timbre, Time, Movement,
  and the same four; seen, and in the log one knob at a time, each answer three times). After
  the asking, Analog Lab V's preset screen marked the preset as changed, for all four presets
  asked in runs 2 and 3 (in the logs); for one of them Adam saw no asterisk in Analog Lab V's
  window, so what the window shows was not settled.
- At a preset change the Roto-Control shows a percentage for each value the instrument reports
  without a text.

**Not tested.** Notes' full delay; the keyboard's faders through the tool; the tool stopped
while an instrument runs; names fitted as a page (`RotoNameFit`, written after this test).

### Test 10 (2026-11-15): NRPN, and Pigments' MIDI learn

**Setup.** Adam's Mac; Pigments standalone (version not read), with the preset "Rods", shown as
changed before the test; `sbdev vport "NRPN Test"` on branch `vport-probe` at `8f5be68`,
started before Pigments, with "NRPN Test" checked as a MIDI input in Pigments (not seen, but
the learning below shows it was). The keyboard was not touched. One log, kept outside this
repository: the four messages sent, and nothing received. What Pigments showed is from Adam's
screenshots and his reading of the knob ("seen"). This is question 4 of
`docs/PLUGIN-MODE-PLAN.md`, section 10.

- **The MIDI panel** (screenshots). Its table has the columns Ch, CC, Control, Min, and Max,
  and nothing for a message's type. "Midi Controller" read "KeyLab mk3" and was left so. MIDI
  Config read "KeyLab", the factory default; its menu lists the factory configurations Generic,
  KeyLab (default), and Empty, with "Save Current Config" grayed out. Empty was chosen for the
  test, and its table was empty.
- **Learning.** With Learn on and Filter 2's Cutoff clicked, the tool sent one NRPN message:
  parameter 16, value 64 and 0 (`B0 63 00`, `B0 62 10`, `B0 06 40`, `B0 26 00`). The table
  gained one row: channel 1, CC 6, "F2 Cutoff", 20.0Hz to 20000Hz, and the configuration's name
  became "Empty*" (seen). So of the message's four control changes, Pigments learned the data
  entry's coarse byte as an ordinary control change.
- **The fine byte.** The same message sent three times, with the data entry at 64 and 0, 64 and
  64, and 65 and 0, gave a cutoff of 204 Hz, 204 Hz, and 228 Hz (seen, read from the knob after
  each). Half a 7-bit step made no difference, and a whole step made one that the readout
  would have split.
- **Afterward** Adam set MIDI Config back to "KeyLab (default)" and loaded the preset again
  without saving. Whether the Empty configuration kept the learned row was not checked.

**Consequences.** Pigments' MIDI learn takes 7 bits: an NRPN message is not treated as one, and
the fine half of the 14-bit pair of control changes 6 and 38 is ignored. One parameter, one
run. The other 14-bit pairs and the other instruments are untried; that they behave the same is
an inference from their sharing this panel. Whether Pigments would report a value more finely
was not tried, since nothing can set one (and test 5's reports were 7-bit).

### Test 11 (2026-11-15): what each plugin gives a host

**Setup.** Adam's Mac, with Bitwig Studio and Arturia's apps closed. `arturia_params.py`
(`docs/arturia-parameters/`) loaded each of the 89 Arturia VST3 plugins installed (49 instruments
and 40 effects) with Pedalboard 0.9.26, with no window and no sound, and saved every parameter's
name, value text, and value list. All 89 loaded, at about 3 s each. The versions are in
`docs/arturia-parameters/INDEX.tsv` (Analog Lab V 5.12.6, Pigments 7.0.1, MiniFreak V 5.1.1). A
first run printed nothing for over a minute and was stopped; the second, the same command with a
timer added, ran through. Why is not known.

These are counts from the lists, each plugin as it loads.

- **Size.** 42,686 parameters in all; 34,320 without the 94 or so in every plugin that are not
  sound parameters (MPE, program changes, preset browsing, a controller's display). Pigments has
  2,345 and Matrix-12 V2 has 4,522.
- **Length.** Of the 34,320, 31,415 (92%) have names longer than 12 characters, the width of a
  Roto-Control's name, and 26,301 (77%) share their first 12 characters with another parameter
  of the same plugin. The longest name has 53 characters.
- **How names are built.** A section, then a part, then the parameter: "FX A1 Multiband Compressor
  Low Below Threshold", "Sampler 1 Tremolo Depth", "Envelope 1 KYBD Follow". Some join two
  words: "Env Amp AttackCurve" and "Env Amp ReleaseLink" in Pigments.
- **Macros.** Of the 49 instruments, 29 have "Brightness" and "Timbre" (most with "Movement"), 7 have "Macro 1" to "Macro 4", and 4 have "Macro1" to "Macro4" with no space; three
  have both kinds. The eight Augmented instruments have "Morph", "Color", "Time", and "Motion".
- **"P1".** Only Analog Lab V has names that start with "P1" or "P2".
- **Analog Lab V** (547 parameters). Part 1 has 20 named for the loaded preset ("P1 Brightness",
  "P1 VCF Cutoff", ..., with "P1 Param9" for one not used) and "P1 Volume", "P1 Pan", "P1
  Active", and two sends. Part 2's 20 were "P2 Param0" to "P2 Param19". There are also "Macro 1"
  to "Macro 4" with no part, which is an inference away from being the Multi's own macros (in
  `docs/ROTO-CONTROL.md`, test 18, parameters with no part took a Multi's names); "FXA Dry/Wet"
  and "FXB Dry/Wet"; and "Delay Volume" and "Reverb Volume".
- **Which effect is in a slot.** Clavinet V ("FX in slot 2"), DX7 V ("FX 1  Type"), Matrix-12 V2
  ("FX1 Selector"), and Synclavier V ("Effect1 Selector") have a parameter whose values name
  the effects. Analog Lab V and Pigments have none that was found (a search for value lists
  naming three or more effects); their slots have a "Dry/Wet", an "Active" or "Bypass", and a set
  of parameters for every effect the slot could hold.

**Consequences.**

- Cutting names at 12 characters loses most of them, and three in four of the cut names are no
  longer unique in their plugin. Shortening words helps the shorter names; the long ones need
  the words that a whole page shares to be dropped (`docs/PLUGIN-MODE-PLAN.md`, section 10).
- A host is not told which effect is in an Analog Lab V slot. The instrument does tell a KeyLab
  mk3: in test 9's third log the relay took "Chorus Mix" and "Phaser Mix" from it. So those
  names can come by the relay and not by a DAW.
- The eight Augmented instruments, which have no parameter-name file (section 4), are covered
  here.

### Test 12 (2026-11-15): Analog Lab V as a plugin in Bitwig Studio, and a virtual KeyLab mk3

**Setup.** Adam's Mac; Bitwig Studio 6.1.4 with Analog Lab V 5.12.6 as a plugin on a track,
preset "Classic Jun Keys"; his KeyLab 61 mk3 connected; no standalone Arturia app open (Adam);
`sbdev vport "KeyLab 88 mk3 MIDI"` at `1a988c2`, in two runs. Two logs (102 and 98 lines), whole,
kept outside this repository. What the windows and the keyboard showed is Adam's report and
screenshots ("seen"). Hosted, the plugin's settings offer no choice of MIDI port (Adam).

**First run** (the plugin added to the track after the port was published).

- **It found the port by itself.** 35.9 s after the port was published, the plugin sent it
  what the standalone app sends a KeyLab mk3 (test 6): the connect messages, the nine knob
  values (item 0 at 28, where Bitwig showed "P1 Brightness" at 0.223), the knob screens, and
  the preset screen with "Classic Jun Keys" and "Classic Synth Keys". Nothing in Bitwig or the
  plugin had been set.
- **A control change sent on the port drew nothing** (`item 4 0`, control change 93 with the
  value the item stood at, 177.9 s).
- **The real keyboard had lost the plugin.** In its Arturia program it showed no instrument, and
  a click of its main encoder no longer changed its program (seen). When Adam changed its
  program by hand, the plugin sent its knob and preset screens to the virtual port (321.4 s
  and 322.8 s).
- **Bitwig noticed the port**: "MIDI Input Connected: KeyLab 88 mk3 MIDI was just found", with
  an "Add Controller" button (seen); closed unused.
- **With the port removed**, the keyboard still showed no instrument, until the plugin was
  deleted from the track and added again (seen).

**Second run** (the port published with the plugin already loaded and on the real keyboard).

- **A plugin already loaded stayed where it was.** Nothing came to the port, and the keyboard
  went on showing "Classic Jun Keys" (seen).
- **Through Bitwig, a control change reaches the plugin.** Adam added the port in Bitwig's
  settings as a controller; Bitwig made it "Generic KeyLab 88 mk3 MIDI", with the port as its
  input (seen). Then `item 4 64` moved the plugin's Distortion Mix knob, the fifth, to about
  half (seen). So item 4 is the fifth knob here.
- **The plugin on the real keyboard named nothing for it.** `item 4 64` again and `item 4 70`
  showed nothing on the keyboard's screen (seen), though a turn of the keyboard's own
  encoder 5 showed "Distortion Mix" (seen).
- **The plugin on the virtual port answered.** With the plugin deleted and added again it
  connected to the virtual port (457.4 s), and the keyboard read "Open an Arturia plugin"
  (seen). `item 4 70` (517.7 s) drew, 54 ms later, an undecoded `03 0D 11 11 11 00` and a
  screen with "55 %", "Distortion Mix", and the value 70, three times, and 2.0 s later the
  preset screen and knob screens: as test 6's standalone answer. The same message again
  (647.9 s), with the value unchanged, drew the same screen 53 ms later.
- Afterward the controller was removed from Bitwig, the port closed, and the plugin added
  again; the keyboard showed the preset (seen).

**Consequences.**

- A plugin chooses its KeyLab when it loads (an inference from three loads): the port
  published last, if it has a KeyLab mk3's name. It does not look again when that port goes.
- Hosted, the plugin writes to that port itself and takes control changes from the DAW, not
  from the port (the first run's silence; an inference). And it answers with a name only on
  the connection it has, for a control change that reaches it.
- So a controller can ask the hosted plugin for a control's name, the effect's included, by
  being its KeyLab and sending the control's value again through the DAW ("Asking for a name",
  section 4, with its cost: the value is 7-bit). The preset's name comes unasked.
- Not tried: passing the plugin's messages on to the real keyboard at the same time (test 9
  did it for the standalone apps), Pigments or a single instrument as a plugin, another DAW,
  and the plugin's other eight controls.

### Test 13 (2026-11-15): the relay with the plugin in Bitwig Studio: keyboard, Roto-Control, and names

**Setup.** As test 12, with Pigments 7.0.1 for the last part; a Roto-Control, in PLUGIN mode;
`sbdev arturia --wait --device "Roto-Control" --keyboard "KeyLab 61 mk3 MIDI"` at `870ca00`,
which publishes "KeyLab 49 mk3 MIDI", passes messages both ways between that port and the
real keyboard, and drives the Roto-Control (test 9). Bitwig's own Roto-Control extension was
idle, its ports unconnected. Three runs of the tool; the first and third logs (298 and 4,394
lines) are whole and kept outside this repository; the third overwrote the second's, whose
names below are from a reading of it before that. "Seen" is Adam's report.

**Run 1** (the plugin added after the port was published; no controller added in Bitwig).

- The plugin connected to the tool's port (47.0 s), and the tool passed its messages on: the
  keyboard showed the preset (seen), and the Roto-Control showed "Classic Jun Keys".
- The knobs kept placeholder names ("Macro 1" and so on). The tool's asking went to the port,
  which the hosted plugin takes nothing from (test 12).

**Run 2** (Bitwig given "Generic KeyLab 49 mk3 MIDI", with the tool's port as its input, as in
test 12; the tool started again; the plugin deleted and added).

- The Roto-Control got the instrument's own names, the effects' included: "Fifth", "Time",
  "Chorus Mix", "Phaser Mix", "Delay Volume". After a change of preset, to "Classic Lead", it
  got that preset's names ("Time", "Brightness", and others). Before the plugin was added
  again the Roto-Control showed question marks (seen).

**Run 3** (the tool started again with the plugin loaded; then the plugin deleted and added
four times, the last time as Pigments).

- **First load: the real keyboard.** For 404 s nothing came from the plugin to the tool. The
  keyboard showed "Classic Jun Keys*" (seen), so the plugin was connected to it directly.
  A Roto-Control knob still moved the plugin's knob (seen): the tool's control changes reach
  the plugin through Bitwig's controller whichever port the plugin holds. A knob turned in
  the plugin's window moved nothing on the Roto-Control (seen). A turn of the keyboard's
  encoder made the Roto-Control's knob jump to 0 and then follow (seen): the tool passed
  the keyboard's control changes on and took them as values for a control it had no value
  for.
- **Second load: the tool's port** (404.6 s). The preset and the eight knobs' names came, and
  as Adam turned the keyboard's preset encoder, each preset's name and type in turn (fifty
  and more, "Classic Keys" to "Clav Delay").
- **The asking changed the preset.** The tool asks about a knob by sending the value it holds
  for it. On connecting, the plugin reported 0 for two knobs (404.6 s) and then for all nine
  (406.3 s), before their real values (406.4 s: 28, 54, 80, 0, 0, 0, 0, 25, 109), and the
  preset's screen after those (406.9 s). The tool also still held 71 for the first knob, from
  the first load. So it sent control change 74 as 71 (404.9 s) and control changes 19 and 16
  as 0 (405.3 s and 405.7 s), the last for a knob that stood at 25. The plugin took that one
  at least: "Reverb Volume" came back as "-70.0 dB", value 0, and the preset was marked as
  changed. So asking is not harmless once the route through the DAW exists. A relay must
  drop the values it holds when the plugin connects, and ask only after the preset's screen
  has come and the values have stopped.
- **Third load: the tool's port** (the plugin let the port go at 578.5 s and connected again
  at 584.0 s).
- **Pigments: the tool's port** (connected 633.7 s). Its messages carry `0D` where Analog Lab
  V's carry `01`, after the header (taken here for a number of the product; a guess). It
  sent the preset "Welcome", "Template", and the names "Macro 1" to "Macro 4", "F1 Cutoff"
  ("20000 Hz"), "F1 Resonance", and the rest. The keyboard's first encoder (control change
  74) moved "Macro 1" from 0 to 13, the Roto-Control's knob and value text following
  ("0.008", "0.016", up to "0.102"); then the Roto-Control's first knob took it on from 14 to
  45 ("0.354") with no jump.

**Consequences.**

- The whole chain works with the plugin in a DAW, for Analog Lab V and Pigments: the keyboard
  keeps its screens and controls, a second controller gets the preset's name and each
  control's name and value text, and both move the same parameters. In this arrangement the
  second controller's values are 7-bit control changes, not the DAW's own finer parameters.
- Which port the plugin holds cannot be told from the keyboard's screen while a relay passes
  the plugin's messages on; only from whether the plugin's messages arrive at the relay.
  A relay should check that, and say so when the plugin is on the keyboard instead.
- The plugin took the tool's port in four loads of five here, and in seven of eight with
  test 12's (open question 16).
- Not tried: the DAW's own extension driving the Roto-Control's values while the relay
  supplies only the names (`docs/PLUGIN-MODE-PLAN.md`, section 10, item 10); the single
  instruments; another DAW.
