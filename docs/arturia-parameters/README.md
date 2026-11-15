# What each Arturia plugin gives a host

One list per Arturia VST3 on Adam's Mac: every parameter the plugin reports to a host, with its
name, its value text as the plugin loads, and, for switches and short lists, the values it can
take. `INDEX.tsv` gives each plugin's version, its number of parameters, and the day it was read.
89 plugins (49 instruments and 40 effects), read on 2026-11-15.

**Check the version first.** The lists change as Arturia updates its plugins. Each list's first
line and `INDEX.tsv` give the version it was read from. Before relying on a name, compare that
with what is installed, and read the plugins again after an update.

**How the lists were made.** `arturia_params.py` loads each plugin with
[Pedalboard](https://github.com/spotify/pedalboard) (Spotify's plugin host for Python; 0.9.26),
with no window and no sound, one plugin to a process, and saves what it reports. It changes
nothing in the plugins. About 3 s a plugin.

    python3 arturia_params.py                 # every plugin, to JSON (see the script's first lines)
    python3 arturia_params.py --tsv <folder>  # these lists, from the JSON

The JSON, which also has each parameter's raw value and longer value lists, is kept outside
this repository.

**Limits.**

- A list is the plugin as it loads, with its opening preset. Some plugins rename parameters when
  a preset loads: Analog Lab V's "P1 ..." names have been observed to (`docs/ROTO-CONTROL.md`,
  test 18). So a name here can be the opening preset's.
- VST3 only. Whether the Audio Unit's and the standalone app's lists are the same was not
  checked. The standalone Pigments's MIDI list shows two parameters named "Unsync Rate"; no list
  here has two names alike, and whether Pedalboard drops a second one was not checked.
- About 94 parameters in every plugin are not sound parameters: MPE, program changes, preset
  browsing, and a controller's display.

The names are Arturia's. They are here as facts about the plugins that this project's drivers
rely on (Adam, 2026-11-15); a list will be removed if Arturia asks.

What has been read from the lists so far is in `docs/ARTURIA.md` (test 11).
