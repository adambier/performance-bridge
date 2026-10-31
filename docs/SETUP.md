# Setting up Performance Bridge

This guide sets up Performance Bridge with TotalMix FX and a Roto-Control. There is no released app yet:
the app runs from source, with `swift run PerformanceBridge` (README, "Trying the app"). The steps below
mark what has been checked on a Mac and what has not.

**Checked.** The settings in each step were used in the tests in `docs/TOTALMIX-OSC.md` (section 6) and
`docs/ROTO-CONTROL.md` (section 9), with the versions named there: TotalMix FX "2.10 (1)" with a Digiface AES,
and a Roto-Control on firmware 3.3.0.

**Not checked on screen.** Where a menu path or a label below comes from RME's manual or the project's
notes and has not been seen in TotalMix, the step says so.

## What you need

- A Mac running macOS 13 or later.
- TotalMix FX 2.1 or later, on a supported RME interface. The project has tested a Digiface AES only.
- A Roto-Control, connected to the Mac by USB. The project has tested firmware 3.3.0.
- The Swift toolchain (Xcode, or the Command Line Tools with Swift 5.9 or later), to run the app from source.

## Step 1: Turn on Global OSC in TotalMix FX

Steps 1 and 2 were checked on screen against two screenshots of TotalMix (Mac, 2026-10-31). The menu's
title is not in the screenshot, so the top-level menu is not checked.

1. Open the Options menu, and check "Enable OSC Control" (Options → Enable OSC Control). The menu also lists
   "Enable MIDI Control" as a separate item, which is unchecked. RME's online manual names the item "Enable
   MIDI / OSC Control" (docs.rme-audio.com/aoxd/818-1c_menu_options/); the label in the running TotalMix
   differs from the manual.
2. Choose Options → Mixer Settings… (shortcut F3), and open the OSC tab.
3. Under "Select Controller", choose the slot the remote will use (1–4), and check "In Use" for it. The
   Mixer Settings window opens on controller 1, which other programs may use. Checked on screen (Adam, 2026-10-31):
   controller 4 selected, "In Use" checked. The tests also used controller 4.
4. Under "Compatibility (Mode)", choose "Global OSC".
5. Check the ports. Under "TotalMix FX OSC Service", "Port (incoming)" is where the app sends to TotalMix. Under
   "Remote Controller Address", "Host" is the computer the app runs on, and "Port (outgoing)" is where TotalMix
   sends to the app. These are per controller slot. On controller 4 the screenshot shows incoming 7004, host
   127.0.0.1, and outgoing 9004. On controller 1 the screenshot shows 7001 and 9001, and host localhost.
   The app's defaults are 7001 and 9001, so for controller 4 set the app's ports to 7004 and 9004 in Settings
   (or start it with `--in-port 7004 --out-port 9004`). The app sends to 127.0.0.1 or localhost; both reach
   the same Mac, and the app's Settings take the host name.
6. Under "Options", the screenshot shows "Send Level Data" on, "Peak Hold" off, and "Lock Remote to Submix" off.
   The tests had "Send Level Data" off. Whether the app needs it on is not tested. "Number of faders per bank"
   reads 8 on controller 4 and 48 on controller 1; its effect on the app is not tested.
7. The "Details" button opens a window titled "Gobal OSC - Detailed Settings". TotalMix's title has this spelling.
   Checked on screen (Adam, 2026-10-31): "Send changes" on, "Send status" on, "Send all data on start (enable)" off,
   "Receive to hidden channels" off, "Send faders in linear scale" on, "Re-send received" off, and bandwidth
   limitation 500kByte/s. Test 1 had "Send faders in linear scale" off, and test 2 had it on. Whether the app
   needs any of these set a certain way is not tested.
8. Options → Submix linked to OSC Controller is a submenu. Its choices have not been checked on screen.

## Step 2: Choose which channels the remote sees

Channels are hidden only in TotalMix FX, and the app has no setting for hiding. A channel hidden from an OSC
controller in TotalMix is not shown on any surface configured for that controller slot, and the app does not show it greyed out. Checked on screen
(Adam, 2026-10-31) unless marked otherwise:

1. Open the Channel Layout window. Right-click a channel's strip in TotalMix's main window and choose
   "Change Channel Layout", or choose Options → Channel Layout…. The window has tabs for Inputs, Playbacks,
   and Outputs.
2. Select the channel's row in the table. Under "Hide Channel in", check "OSC Controller 1" for the controller
   the app uses (the app's default). Hiding from one controller does not affect the others, or Mixer/Matrix.
   The text next to the group says it hides the channel in the selected OSC controller. Confirmed by Adam on
   2026-10-31: checking "OSC Controller" for a controller hides the channel from that controller.
3. The table's "Remote Controller" column lists M1–M4 and O1–O4 for each channel. What that column shows
   for a hidden channel has not been checked.

Reordering is done in the app (Step 5). It does not change what TotalMix sends. Whether TotalMix's hidden
channels change the channel numbers the app receives has not been tested.

## Step 3: Connect the Roto-Control

1. Connect the Roto-Control to the Mac by USB. It can be connected before or after the app starts.
2. The app finds the Roto-Control by the name of its MIDI port. The default name is "Roto". To use a
   different name, change it in Settings, under Roto-Control.
3. If you need the exact port names, run `swift run sbdev roto ports` from the package folder. Quit the app
   first if it is running, since both need the Roto-Control's MIDI ports.

## Step 4: Start the app

From the package folder:

```
swift run PerformanceBridge
```

To use ports other than the saved ones, add them to the command line:

```
swift run PerformanceBridge --in-port 7004 --out-port 9004
```

The menu-bar icon shows two status lines:

- **TotalMix FX: connected** means TotalMix has answered. **No answer** means it has not yet; the app asks
  again every 3 seconds. **Port N in use, retrying** means another program has the port the app sends from,
  so quit that program, such as `sbdev`.
- **Roto-Control: connected** means the handshake is complete. **Connecting** means the device was found and
  the handshake is under way. **Not found, retrying** means no port matches the name in Settings.

The full reason for any state goes to the log in the Terminal the app was started from.

If TotalMix does not show its state, choose **Ask TotalMix FX for its state** from the menu.

## Step 5: Set the layout

Choose **Layout…** from the menu.

- The **Sources** and **Outputs** buttons switch between the two views.
- Drag a channel to change its place on the surfaces. TotalMix cannot reorder its channels; the app can.
- To take a channel off the surfaces, hide it in TotalMix (Step 2). The layout has no hide setting of its own.
- Channel colors are set in TotalMix FX, in Channel Layout (the Color column, and the Color (Name) menu for the selected channel). Checked on screen (Adam, 2026-10-31).
- The note at the bottom repeats the rule for channels hidden in TotalMix.

## Step 6: Choose the home submix

The home submix is the output the surfaces' levels and pans go into. Choose it from the menu, under
**Home submix**.

- Main Out is the default. Choosing Main Out's output saves "follow Main Out", so the home moves when Main Out
  is reassigned in TotalMix. The menu says so.
- To choose any output, turn on **Show all outputs** in the same menu.

## If something does not work

- **TotalMix FX: port N in use.** Another program has the port. Quit `sbdev` or any other OSC remote.
- **TotalMix FX: no answer.** Check that Global OSC is on and that the ports in Settings match TotalMix's
  (Step 1). Then choose **Ask TotalMix FX for its state**.
- **Roto-Control: not found.** Check the cable, and the MIDI port name in Settings (Step 3).
- **A channel is missing from the surfaces.** Check whether TotalMix hides it from the OSC controller the app uses
  (Step 2).

## Reporting a problem

Keep the Terminal's log: the app writes every connection event to it. The log is the record to send
with a report.
