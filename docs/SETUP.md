# Setting up Performance Bridge

This guide sets up Performance Bridge with TotalMix FX and a hardware controller: a Roto-Control, a
Launch Control XL 3, or a Launch Control 3. There is no released app yet:
the app runs from source, with `swift run PerformanceBridge`, or is built with `./make-app.sh`
(README, "Trying the app"). The steps below mark what has been checked on a Mac and what has not.

**Checked.** The settings in each step were used in the tests in `docs/TOTALMIX-OSC.md` (section 6) and
`docs/ROTO-CONTROL.md` (section 9), and `docs/LAUNCH-CONTROL-XL3.md` (section 10), with the versions
named there: TotalMix FX "2.10 (1)" with a Digiface AES, a Roto-Control on firmware 3.3.0, and a Launch
Control XL 3 on firmware 1.2. No Launch Control 3 has been tried.

**Not checked on screen.** Where a menu path or a label below comes from RME's manual or the project's
notes and has not been seen in TotalMix, the step says so.

## What you need

- A Mac running macOS 13 or later.
- TotalMix FX 2.1 or later (release candidates included), on a supported RME interface. Earlier versions don't have Global OSC; the setup window checks the version. The project has tested only a Digiface AES.
- A hardware controller, connected to the Mac by USB: a Roto-Control (tested with firmware 3.3.0), a Launch
  Control XL 3 (tested with firmware 1.2), or a Launch Control 3 (not yet tried on a device).
- The Swift toolchain (Xcode, or the Command Line Tools with Swift 5.9 or later), to run the app from source.

The app has a setup window that follows these steps and checks each one live where it can: whether
TotalMix answers, whether it has sent its channels, whether meters arrive, and whether the
hardware controller is connected. It opens by itself the first time the app runs; after that, choose
**Setup Guide…** from the menu.

The window also opens by itself, at most once per launch, for a problem that has never worked with
the current settings: the port in use; TotalMix running but not answering for 30 seconds; or the
hardware controller plugged in but not connected after 15 seconds. A hardware controller that isn't
plugged in, or TotalMix not running, never opens it.

Once a connection has worked, a fault only puts a red dot on the menu-bar icon, so a window never
takes the focus during a performance. The dot is for faults: the port in use, TotalMix running but
silent for 10 seconds, or the hardware controller plugged in but not connected for 10 seconds.
TotalMix closed, or the hardware controller unplugged, is idle and leaves no dot, so the app can run
all the time. The icon is dimmed whenever TotalMix or the hardware controller isn't connected and
drawn normally when both are; a fault shows the red dot on the dimmed icon.

## Step 1: Turn on Global OSC in TotalMix FX

Checked on screen with TotalMix FX "2.10 (1)" on a Mac (Adam, 2026-10-31); the screenshots are from it.

1. Open TotalMix's **Options** menu and check **Enable OSC Control**. (RME's online manual calls the item
   "Enable MIDI / OSC Control", docs.rme-audio.com/aoxd/818-1c_menu_options/; the running TotalMix shows "Enable
   OSC Control" and a separate "Enable MIDI Control".)

   <img src="../App/PerformanceBridge/Resources/totalmix-options-menu.png" width="300" alt="TotalMix FX's Options menu, with Enable OSC Control checked">

2. Choose **Options → Mixer Settings…** (shortcut F3) and open the **OSC** tab.
3. Under **Select Controller**, choose a controller (1–4) for Performance Bridge and check **In Use**.
   - Each program or device that connects to TotalMix over OSC (Performance Bridge, a tablet app, another
     remote) needs its own controller and its own ports (Adam, 2026-10-31).
   - Controller 1 is shown below, with incoming 7001 and outgoing 9001. If another program already uses
     controller 1, choose another controller and give it ports no other controller uses (for example, 7002 and
     9002).
4. Under **Compatibility (Mode)**, choose **Global OSC**.
5. Set the ports:
   - **Port (incoming)**, under "Totalmix FX OSC Service" (TotalMix's capitalization), is where Performance
     Bridge sends to TotalMix. The **Host** above it is your Mac's own name, shown for reference.
   - Under **Remote Controller Address**, **Host** is the computer Performance Bridge runs on (`localhost` or
     `127.0.0.1` on the same Mac), and **Port (outgoing)** is where TotalMix sends to Performance Bridge.
   - Enter the same two ports in Performance Bridge's **Settings… → Connections**. Its defaults are 7001 and
     9001, which RME's manual gives as typical values. To try other ports without changing Settings, start the
     app with `--in-port` and `--out-port`.

   <img src="../App/PerformanceBridge/Resources/totalmix-osc-tab.png" width="380" alt="Mixer Settings, OSC tab: controller 1 in use, ports 7001 and 9001, host localhost, Global OSC">

6. Under **Options**, check **Send Level Data** for meters on the hardware controllers and leave **Lock Remote
   to Submix** off (Performance Bridge chooses submixes itself). The effect of **Number of faders per bank** on
   the app has not been tested.
7. Click **Details**, which opens "Gobal OSC - Detailed Settings" (TotalMix's spelling), and check **Send
   changes** and **Send status**. The other settings shown are the ones used in the tests: "Send all data on
   start (enable)" off, "Receive to hidden channels" off, "Set all faders in group" off, "Send faders in linear
   scale" on (TotalMix accepts both scales, test 2), "Re-send received (use carefully!)" off, and "Bandwith
   Limitation" (TotalMix's spelling) at 500kByte/s. Whether the app needs
   any of them set a certain way has not been tested.

   <img src="../App/PerformanceBridge/Resources/totalmix-osc-details.png" width="320" alt="Gobal OSC - Detailed Settings: Send changes and Send status checked">

8. **Options → Submix linked to OSC Controller** is a submenu with one item per controller, 1 to 4; all four
   were checked on Adam's Mac. RME's Global OSC document says "Follow Submix" should be off with Global OSC;
   this submenu is inferred to be that setting, since TotalMix has no item by that name. The tests ran with it
   checked and Global OSC worked (`docs/TOTALMIX-OSC.md`, section 1); a run with it unchecked hasn't been
   compared, so leave it as it is.

## Step 2: Choose which channels the hardware controllers show

Hide and show channels in TotalMix; Performance Bridge has no setting for hiding. A channel that TotalMix
hides from an OSC Controller is not shown on the hardware controllers connected through it, and the app does
not show it grayed out. Checked on screen (Adam, 2026-10-31) unless marked otherwise.

1. Open TotalMix FX's own **Channel Layout** window: right-click a channel's strip and choose **Change Channel
   Layout**, or choose **Options → Channel Layout…**. It has tabs for Inputs, Playbacks, and Outputs.
2. Select the channel's row. Under **Hide Channel in**, check the **OSC Controller** box for the controller
   Performance Bridge uses (OSC Controller 1 for controller 1). Hiding from one controller doesn't affect the
   others, or Mixer/Matrix.
3. Channel colors can be set in the same window, in the **Color** column or with **Color (Name)** below the
   boxes. The Roto-Control shows them too.

   <img src="../App/PerformanceBridge/Resources/totalmix-channel-layout.png" width="560" alt="TotalMix FX's Channel Layout window, Inputs tab, with the Hide Channel in boxes">

4. Then choose **Refresh Channels from TotalMix FX** in Performance Bridge's menu: TotalMix doesn't announce
   hidden or shown channels over OSC (`docs/TOTALMIX-OSC.md`, test 11). The app also refreshes by itself when
   its Channel Layout tab opens and when TotalMix comes back after going quiet.

The table's **Remote Controller** column lists M1–M4 and O1–O4 for each channel when nothing is hidden; what it
shows for a hidden channel has not been checked. Hiding has been seen not to renumber the other channels (one
run).

## Step 3: Connect the hardware controller

Performance Bridge uses one hardware controller at a time: a Roto-Control, a Launch Control XL 3, or a
Launch Control 3.

1. Connect the hardware controller to the Mac by USB. It can be connected before or after the app starts.
2. In Performance Bridge, open **Settings… → Connections** and choose it from the **Controller** menu
   under Hardware Controller. The Roto-Control is the default.
3. The app finds the controller by the name of its MIDI port, shown in the **MIDI port** menu below it.
   The defaults match the usual names: "Roto" for the Roto-Control's port "Roto-Control", and the Launch
   Controls' DAW ports, "LCXL3 1 DAW" and "LC3 1 DAW" (the part their "… Out" and "… In" ports share).
   The menu lists the ports connected when Settings opens; choose another one if yours is named
   differently.
4. Click **Apply**. With a Launch Control chosen, the Connections tab also shows its send rows, whose outputs
   can be chosen there once it is connected (Step 6).

## Step 4: Start the app

From the package folder:

```
swift run PerformanceBridge
```

To use ports other than the saved ones, add them to the command line:

```
swift run PerformanceBridge --in-port 7004 --out-port 9004
```

The menu-bar icon's menu starts with two status lines, dimmed because they only report. The app keeps
retrying in every state:

- **TotalMix FX: Connected** means TotalMix has answered. **No Answer** means it has not yet; the app asks
  again every 3 seconds. **Port N in Use** means another program has the port the app sends from, so quit
  that program, such as `sbdev`.
- **Roto-Control: Connected** means the handshake is complete. **Connecting** means the device was found and
  the handshake is under way. **Not Found** means no MIDI port matches the one in Settings.
- With a Launch Control chosen, its line takes the Roto-Control's place: **Launch Control XL 3: Connected**
  means the device has entered DAW mode, **Connecting** that its DAW port is open and the app is asking for
  DAW mode, and **Not Found** that no MIDI port matches the one in Settings.

The full reason for any state goes to the log in the Terminal the app was started from.

After hiding or showing channels in TotalMix FX's own Channel Layout window, choose **Refresh Channels from
TotalMix FX** from the menu (Step 2).

## Step 5: Set the layout

Choose **Settings…** from the menu and open the **Channel Layout** tab.

- The **Sources** and **Outputs** buttons switch between the two lists.
- **Sources** are the channels the hardware controllers show. Drag a channel to change its place on them.
- **Playbacks start on a new page**, under the Sources list, puts the first playback at the start of a new
  page of strips, after blank strips that fill the inputs' last page.
- **Outputs** are the outputs the send controls can feed (Step 6). Their order is the order you step through
  them on the hardware controllers. The **Control Room** outputs (those assigned in TotalMix's control room:
  Phones, and so on) and the **Hardware Outputs** are ordered in their own sections, since control room outputs
  always come first.
- Click a channel's name to give it a **label** for the hardware controllers, e.g., a short name for mixing. The label shows only on the hardware controllers; TotalMix keeps its own name, shown dimmed beside the label. Clear the label to show TotalMix's name again. A playback without a label shows as "PB 1/2" and so on, since an unnamed playback otherwise has its output's hardware name, which can be the same as an input's.
- The order and the labels are kept when Performance Bridge restarts.
- **Restore TotalMix FX Order** puts the view back in TotalMix's order. It is dimmed when the order is already TotalMix's.
- To take a channel off the hardware controllers, hide it in TotalMix (Step 2). The layout has no hide setting of its own.
- Channel colors can be set in TotalMix FX's own Channel Layout window (the Color column and the Color (Name) menu for the selected channel). Checked on screen (Adam, 2026-10-31).
- The note at the bottom repeats the rule for channels hidden in TotalMix.

## Step 6: Use the hardware controllers

Every hardware controller works the same way: **each column of controls is one channel**, and every control in a
column controls that channel. Levels and pans go into the submix of the output that TotalMix's control room
assigns to Main Out and follow Main Out if it is reassigned there. Set the outputs themselves (Main Out's volume,
Speaker B, and so on) in TotalMix or with an ARC USB; the hardware controllers don't change them.

**Sends** make the headphone mixes. A send control sets how much of its channel goes to one other output, e.g.,
Phones 1. A row of send controls is that output's whole submix, one channel per column. The outputs a send row can
feed are the ones in Settings → Channel Layout → Outputs, in that order, except Main Out and Main Out B (they carry
the main mix) and the cue output (PFL uses it).

### Launch Control XL 3

| Control (in each column) | What it does for that column's channel |
|---|---|
| Fader | Level in Main Out. The ticks read +6, +3, 0, −6, −10, −20, −40, −60, and −oo, as on TotalMix's faders. |
| Top encoder | Send to the top row's output (e.g., Phones 1) |
| Middle encoder | Send to the middle row's output (e.g., Phones 2) |
| Bottom encoder | Pan in Main Out |
| Top button | PFL (yellow when on) |
| Bottom button | Mute (red when on) |

| Button | What it does |
|---|---|
| **Track >** / **Track <** | Show the next or previous eight channels. With **Shift**: the last or first eight. |
| **Page ▼** / **Page ▲** | Change the output the **top** encoder row feeds, to the next or previous one in the Outputs list. |
| **Shift + Page ▼** / **▲** | The same for the **middle** encoder row. |
| **Shift + turn an encoder** | Reset it: a pan to the center, a send to −oo. |

- The two send rows never feed the same output: stepping one skips the output the other has.
- The screen shows the channels on the page, counted in the order of Settings → Channel Layout with a stereo pair
  counting once, and where each send row goes (e.g., "Inputs 1-7", "Top > Phones 1",
  "Mid > Phones 2"). Moving a control shows its channel, what it does, and its value. After each Page press the
  screen names the row and its new output, and each send row's lights take the color of the output it feeds.
- Page and Track are lit where they can move and dark at the ends. While Shift is held, Page lights for the middle
  row.
- Each row's output is remembered when Performance Bridge restarts and can also be chosen in Settings, at the
  bottom of the Connections tab.
- Solo/Arm, Mute/Select, Record, Play, and the Novation button do nothing, so they stay free for later uses (e.g., a
  connection to a DAW).
- Level and pan are Main Out's. In TotalMix each submix has its own level and pan for every channel, so TotalMix's
  window shows the pans set here only while Main Out's output is selected in its bottom row (seen 2026-11-01).

### Launch Control 3

The Launch Control 3 works the same way, with fewer controls:

| Control (in each column) | What it does for that column's channel |
|---|---|
| Bottom encoder | Level in Main Out |
| Top encoder | Pan, or a send: **Page ▼** / **▲** steps it through Pan, then each output in the Outputs list |
| Button | Mute, or PFL after **Function** (red for mute, yellow for PFL; Function lights yellow while the buttons are PFL) |

Track works as on the XL 3, and Shift + turn resets an encoder (a level to 0 dB). The screen shows the channels on
the page, the top row's function (e.g., "Top: Pan"), and the buttons' ("Buttons: Mute"). The Launch Control 3 has not been tried on a device yet (`docs/LAUNCH-CONTROL-3.md`).

### Roto-Control

Each of the eight knobs is a channel. Hold **SEL** to choose what the knobs control (Volume, Pan, or a send, "FX")
and what the switches do (Mute, or Solo, which is PFL here). The < and > buttons page through the channels. Pressing
both arrow buttons together switches the Roto-Control to its second track set ("MIX-RTN" on its screen), which shows
the same channels.

## If something does not work

- **TotalMix FX: Port N in Use.** Another program has the port. Quit `sbdev` or any other OSC remote.
- **TotalMix FX: No Answer.** Check that Global OSC is on and that the ports in Settings match TotalMix's
  (Step 1). Then choose **Refresh Channels from TotalMix FX**.
- **Roto-Control: Not Found.** Check the cable and the MIDI port in Settings (Step 3).
- **A channel is missing from the hardware controllers.** Check whether TotalMix hides it from the OSC Controller the app uses
  (Step 2).

## Reporting a problem

Send the Terminal's log with the report: the app writes every connection event to it.
