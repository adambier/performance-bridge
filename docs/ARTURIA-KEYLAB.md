# Arturia's KeyLab profiles: a reference

Arturia's instruments (Pigments, Analog Lab V, the V Collection) each recognize Arturia's own
keyboards by MIDI port name and talk to them in a private dialect. This is a reference to what the
instruments expect of three generations of KeyLab, the first KeyLab, the KeyLab mkII, and the
KeyLab mk3, written so that another project can imitate one without repeating the reading. The
findings and their tests are in [ARTURIA.md](ARTURIA.md); this file arranges them by controller.
It is in this project's own words, and nothing from Arturia's files is copied here. This project
is not affiliated with or endorsed by Arturia.

**How sure each statement is.** "Declared" means the installed profile files say so and no test
has shown it.[^files] "Seen" means a test with the standalone app showed it, with the test's
number in ARTURIA.md, section 6. Everything here is about the standalone apps on macOS. Nothing
has been tested with the plugins in a DAW, with any instrument but Pigments and Analog Lab V, or
with a real KeyLab.

[^files]: Two profile files on Adam's Mac, read on 2026-11-13 and 2026-11-14: the one shared by
    Pigments and the V Collection instruments (`controllers-common.prefmidi.xml`, read in
    Pigments' resources) and Analog Lab V's own (`controllers.prefmidi.xml`). The versions were
    Pigments 7.0.1 and Analog Lab V 5.12.6 on 2026-11-13.

## 1. At a glance

| | First KeyLab | KeyLab mkII | KeyLab mk3 |
|---|---|---|---|
| Port names | "KeyLab 25", "49", "61", "88" | "KeyLab mkII 49", "61", "88", each also with " MIDI" or " (1)" after it | "KeyLab 49 mk3 MIDI", "61", "88" (matched as part of the name) |
| Message family | version 2 | version 2 | version 3 |
| Knobs reported | 11 | 9 | 9 |
| A control's name and value in words | no (seen, tests 1–3) | yes, when changed from the controller (seen, test 4) | yes, likewise (seen, tests 5 and 6) |
| Per-preset labels | no | Analog Lab V only (seen, test 4) | Analog Lab V only (seen, test 6) |
| Resolution of reported values | 7 bits (seen) | 7 bits (seen) | 7 bits (seen, tests 5 and 6) |
| Previous and next preset | no | controllers 28 and 29 (declared) | no; browse and validate only (declared) |
| Save, Undo, and Redo | no | no | controllers 53, 54, and 55, with lights (declared) |
| Chosen by the instrument by itself | Pigments (seen, test 1); Analog Lab V showed it, how it was chosen not recorded (test 3) | Analog Lab V; in Pigments, chosen by hand (seen, test 4) | Pigments and Analog Lab V (seen, tests 5 and 6) |

For a controller with its own displays and no KeyLab screen, the mkII's profile is the one to
imitate: the first KeyLab's sends no names, and the mk3's adds only what belongs to the mk3's
panel, in a second message format. Neither the mkII's nor the mk3's sends a knob's label before
the knob is moved from the controller (tests 4 and 6).

## 2. Finding the controller

The instrument looks through its MIDI ports for a name a profile lists (declared), and the user
turns the port on in the instrument's Audio MIDI Settings window, under MIDI ports (seen). A port
that went away was no longer turned on afterward (test 5), and one that came back the next day
came back turned off (test 2). The
instrument's Midi Controller setting has been observed to follow the port by itself, except
Pigments with the mkII port (test 4); after the port went away, Pigments and Analog Lab V kept the
setting (tests 5 and 6). Analog Lab V also recognized the mk3's port by its name before anything
was exchanged, and offered to update "your KeyLab 61 mk3" to a newer firmware (test 6; declined).

## 3. Knobs

Each profile ties control change numbers to item numbers; the instrument reports a knob under its
item. The parameter behind each control change is the instrument's own business (its "KeyLab"
MIDI configuration).

| Control change | 74 | 71 | 76 | 77 | 93 | 18 | 19 | 16 | 17 | 7 | 91 |
|---|---|---|---|---|---|---|---|---|---|---|---|
| First KeyLab's item | 1 | 2 | 3 | 4 | 9 | 5 | 6 | 7 | 8 | 48 | 10 |
| KeyLab mkII's item | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | 9 | | |
| KeyLab mk3's item | 0 | 1 | 2 | 3 | 4 | 5 | 6 | 7 | 8 | | |

In Pigments these are Macros 1–4, Filter 1's cutoff and resonance, Filter 2's cutoff and
resonance, and the master volume, in the table's order (seen in its MIDI tab, test 4; 7 and 91
are not assigned there). In Analog Lab V they are the preset's first four controls, four more
(Chorus Mix was the first of them in one preset; seen, test 4), and, by an inference from its
value, Master.

**Faders.** The instruments' KeyLab configurations also assign nine more control changes, 73, 75,
79, 72, 80, 81, 82, 83, and 85: in Pigments, the amplitude envelope's attack, decay, sustain, and
release, envelope 2's, and the aux send (seen in its MIDI tab). No profile declares a report for
them, and none was seen (test 3). The inference is that they work inward only.

## 4. Version 2 messages (first KeyLab and KeyLab mkII)

All are SysEx beginning `F0 00 20 6B 7F 42` and ending `F7`. After that header:

| Message | Bytes | Evidence |
|---|---|---|
| A knob's value | `02 00 00 <item> <value>` | seen (tests 1–4) |
| A light | `02 00 10 <item> <value>` | seen (tests 3 and 4) |
| The display's text | `04 00 60`, then fields: a tag byte, ASCII text, a 0 byte | seen (tests 1–4) |

- **The usual text** has tag 1 with the instrument (or, from Analog Lab V, the instrument the
  preset comes from), tag 2 with the preset's name behind an asterisk, tag 3 with its type, and
  tag 4 empty.
- **After a control change from the controller, under the mkII's profile:** tag 1 is the control's
  name, tag 2 its value in words (e.g., "0.472", "39 %", "1448 Hz"), tag 3 is empty, and tag 4
  holds "c", the control change's number and value as two bytes, and ";". It comes three times
  within about 0.1 s; the usual text returns about 2 s later (five of five, test 4).
- **Values** are 0–127. They come as the control moves in the instrument's window, about every
  17 ms from Pigments and every 6–8 ms from Analog Lab V, often repeating a value. A control
  change from the controller draws no value message back.
- **On connecting,** Analog Lab V sent every value, its lights, and the text (tests 3 and 4).
  Pigments sent the text always, the lights under the mkII's profile, and the values in one run
  of three (tests 1, 2, and 4). At a preset change both sent values and the text (tests 1 and 3).
- **Lights seen from Analog Lab V** match its profile: as a first KeyLab, items 18–20 (its three
  control tabs) and 30 and 31 (Sound and Multi); as a mkII, items 31–33 (tabs), 24 and 25
  (browsing by category or by preset), and 34–42 (nine lights for the browsing filter). Pigments
  as a mkII sent items 24, 25, and 34–42.

## 5. Version 3 messages (KeyLab mk3)

Seen from Pigments (test 5) and Analog Lab V (test 6). SysEx beginning `F0 00 20 6B 7F 42 00 <id>`,
where `<id>` was `0D` from Pigments and `01` from Analog Lab V (the numbers their profiles give),
then a subcommand:

| Message | Bytes after the id | Evidence |
|---|---|---|
| A knob's value | `00 <item> 01 <value> 00` | seen: 137 messages from Pigments and 146 from Analog Lab V in drags, the last byte always 0 |
| Another property | `00 <item> 02 <value> 00` | seen from Analog Lab V on connecting: items 51–54, value 0 |
| Not known | `03 <byte> <byte> <byte> <byte> 00` | seen from Analog Lab V only: `03 0D 11 11 11` after a control change in, `03 0F 01 01 01` at a preset change and at the first edit |
| A screen | `04 <screen>`, then fields: a tag byte, bytes, a 0 byte | seen |
| Connect, disconnect | `05 01`, `05 00` | seen on connecting (01, 00, 01) |

- **Screen `10` hex** is the preset: its name with an asterisk after it, its type, and a color
  among other small fields.
- **Screens `01`–`08`** came as a set of eight. From Pigments the first four had an icon number
  and a color and the last four were empty; from Analog Lab V screens 1–4 and 8 had them. That they are the mk3's eight display buttons is an inference from the
  count and the profile.
- **Screen `1C` hex** followed a control change from the controller: the value in words
  ("0.551"), the control's name, the raw value, and two more small fields, the same bytes from
  both apps; three times, with the preset and the screens sent again 2 s later. The name was
  Pigments' fixed one ("Macro 1") and Analog Lab V's per-preset label ("Color").
- **Knob values** came from Analog Lab V on connecting (all nine, three times) and at a preset
  change; from Pigments, not on connecting (test 5; a preset change was not tried).
- The profile also declares a "soft connect" (subcommand 8), lights with three colors each for
  Save, Undo, and Redo (items 15, 13, and 12), and, in Analog Lab V, lights for transpose and
  octave. None was seen. Analog Lab V's second property (items 51–54) is its four part buttons,
  by the profile.
- Not every field has been worked out, and nothing was sent in this format to the instrument.

## 6. Buttons and other controls (declared; none tested)

Control changes the instruments' KeyLab configurations assign beyond the knobs and faders:

| Function | First KeyLab | KeyLab mkII | KeyLab mk3 |
|---|---|---|---|
| Browse presets, and select | 114, 115 | 114, 115 | 114, 115 |
| Browse filters, and select | 112, 113 | 112, 113 | |
| Browse by category, by preset | | 116, 117 | |
| Previous preset, next preset | | 28, 29 | |
| A filter button | | 30 | |
| Back | | | 65 |
| Save, Undo, Redo | | | 53, 54, 55 |
| Display buttons 1–8 | | | 60, 61, 62, 63, 56, 57, 58, 59 |
| Soft connect, from the controller | | | 117 |

Analog Lab V adds, as a mkII: its three control tabs on 24, 22, and 23, octave down and up on 26
and 27, and a request for all current values on 118. As a mk3 it has transpose and octave on 86,
87, 89, and 90; its profile declares the value request, but its configuration lists no control
change for it. Save has not been sent in any test,
since it could overwrite a preset.

## 7. Per-preset labels

Analog Lab V sends the label the preset gives a control ("Color", "Chorus Mix"), under both the
mkII's and the mk3's profiles, but only when that control is moved from the controller: not on
connecting, not at a preset change, and not when it is moved in the window (tests 4 and 6).
Pigments sends its parameter's fixed name ("Macro 1") where its window shows the preset's label
("Timbre"), under both profiles (tests 4 and 5). Pigments' preset files hold the four
macro labels as named fields (one factory preset read), so a controller that knows the instrument
and the preset could look them up; see ARTURIA.md, section 4, for what is open.
