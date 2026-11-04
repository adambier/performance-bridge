// What each control of a hardware controller does, for the app's Controls Guide window (Adam,
// 2026-11-02). The same text is in docs/SETUP.md, Step 6; a test checks that the two agree, so
// change both together. Text may use Markdown's **bold**, which the app shows as bold.

import Foundation
#if canImport(LaunchControl)
import LaunchControl
#endif

/// The Controls Guide for one hardware controller: an introduction, tables of controls and what
/// they do, and notes.
public struct ControlsGuide: Equatable, Sendable {
    /// One row of a table: the control and what it does.
    public struct Row: Equatable, Sendable {
        /// The control (e.g., "Fader", "**Track >** / **Track <**").
        public var control: String
        /// What it does.
        public var action: String

        /// Makes a row.
        public init(_ control: String, _ action: String) {
            self.control = control
            self.action = action
        }
    }

    /// A table of controls, with its two column headings.
    public struct Table: Equatable, Sendable {
        /// The heading of the controls column.
        public var controlHeading: String
        /// The heading of the column saying what they do.
        public var actionHeading: String
        /// The rows.
        public var rows: [Row]
    }

    /// The controller's name, as the guide's title.
    public var title: String
    /// The resource name of the controller's photo (`controller-*.png` in the app's resources, the
    /// maker's top view, trimmed), shown under the title; docs/SETUP.md shows the same file.
    public var image: String
    /// Paragraphs before the tables.
    public var introduction: [String]
    /// The tables.
    public var tables: [Table]
    /// Notes after the tables, one paragraph each.
    public var notes: [String]

    /// What every hardware controller has in common: paragraphs shown before each guide.
    public static let common: [String] = [
        "Every hardware controller works the same way: **each column of controls is one channel** and every control in a column controls that channel.",
        "Levels and pans go into the submix of the output that TotalMix FX's control room assigns to Main Out and follow Main Out if it is reassigned there. Set the outputs themselves (e.g., Main Out's volume and Speaker B) in TotalMix FX or with an ARC USB; the hardware controllers don't change them.",
        "**Sends** set the headphone mixes and the other submixes. A send control sets how much of its channel goes to one other output, e.g., Phones 1. A row of send controls is that output's whole submix, one channel per column.",
        "The outputs a send row can feed are the ones in **Settings… → Channel Layout → Outputs**, in that order. Main Out and Main Out B (they carry the main mix) and the cue output (PFL uses it) aren't listed there.",
    ]

    /// The guide for a hardware controller.
    public static func guide(for controller: DetectedController) -> ControlsGuide {
        switch controller {
        case .launchControl(.xl3): return launchControlXL3
        case .launchControl(.lc3): return launchControl3
        case .roto: return rotoControl
        }
    }

    static let launchControlXL3 = ControlsGuide(
        title: "Launch Control XL 3",
        image: "controller-launch-control-xl3",
        introduction: [],
        tables: [
            Table(controlHeading: "Control (in each column)", actionHeading: "What it does for that column's channel", rows: [
                Row("Fader", "Level in Main Out. The ticks read +6, +3, 0, −6, −10, −20, −40, −60, and −oo, as on TotalMix FX's faders."),
                Row("Top encoder", "Send to the top row's output (e.g., Phones 1)"),
                Row("Middle encoder", "Send to the middle row's output (e.g., Phones 2)"),
                Row("Bottom encoder", "Pan in Main Out"),
                Row("Top button", "PFL (bright yellow when on, dim yellow when off; the screen briefly names the channel and says \"PFL on\" or \"PFL off\")"),
                Row("Bottom button", "Mute (bright orange when on, dim orange when off, and \"Mute on\" or \"Mute off\" on the screen, or \"Mute Master off\" while TotalMix FX's Mute Master is off; a mute that is on flashes while TotalMix FX's Mute Master is off)"),
            ]),
            Table(controlHeading: "Button", actionHeading: "What it does", rows: [
                Row("**Track >** / **Track <**", "Show the next or previous eight channels. With **Shift**: the last or first eight."),
                Row("**Page ▼** / **Page ▲**", "Change the output the **top** encoder row feeds, to the next or previous one in the Outputs list."),
                Row("**Shift + Page ▼** / **▲**", "The same for the **middle** encoder row."),
                Row("**Shift + turn an encoder**", "Reset it: a pan to the center, a send to −oo (release Shift, then Shift + turn it again to bring it back). Hold Shift for a moment (0.3 s) first; after Page or Track in the same hold, turning does nothing."),
            ]),
        ],
        notes: [
            "The two send rows never feed the same output: stepping one skips the output the other has.",
            "The screen shows the channels on the page, counted in the order of **Settings… → Channel Layout** with a stereo pair counting once, and where each send row goes (e.g., \"Inputs 1-7\", \"Top > Phones 1\", \"Mid > Phones 2\").",
            "Moving a control shows its channel, what it does, and its value.",
            "After each Page press the screen names the row and its new output, and each send row's lights take the color of the output it feeds: its color in TotalMix FX, or, for an output left white, teal (a blue-green) for the top row and magenta for the middle row.",
            "Page and Track are lit where they can move and dark at the ends. While Shift is held, Page lights for the middle row.",
            "Each row's output is remembered when Performance Bridge restarts. It can also be chosen in Settings, at the bottom of the Connections tab, with the Launch Control connected or not; the change takes effect at once.",
            "Press **Track <** and **Track >** together to go back to the first eight channels.",
            "The **Novation button** brings TotalMix FX's window to the front. Press it again while TotalMix FX is in front to go back to the app you were in (if TotalMix FX came to the front some other way, the press hides it instead).",
            "Solo/Arm, Mute/Select, Record, and Play do nothing in this release; they are kept free for later uses (e.g., a connection to a DAW).",
            "Level and pan are Main Out's. In TotalMix FX each submix has its own level and pan for every channel, so TotalMix FX's window shows the pans set here only while Main Out's output is selected in its bottom row (observed 2026-11-01).",
        ])

    static let launchControl3 = ControlsGuide(
        title: "Launch Control 3",
        image: "controller-launch-control-3",
        introduction: ["The Launch Control 3 works the same way, with fewer controls:"],
        tables: [
            Table(controlHeading: "Control (in each column)", actionHeading: "What it does for that column's channel", rows: [
                Row("Bottom encoder", "Level in Main Out"),
                Row("Top encoder", "Pan, or a send: **Page ▼** / **▲** steps it through Pan, then each output in the Outputs list"),
                Row("Button", "Mute; PFL while **Function** (labeled \"DAW\" underneath) is held (orange for mute, yellow for PFL, dim when off). Function rests dim yellow; it lights bright yellow while held, and also while any channel's PFL is on, so a PFL left on still shows"),
            ]),
        ],
        notes: [
            "Track works as on the XL 3 and Shift + turn resets an encoder as it does there; a level above 0 dB comes down to 0 dB, and one at or below 0 dB stays.",
            "The screen shows the channels on the page, the top row's function (e.g., \"Top: Pan\"), and the buttons' (\"Buttons: Mute\", or \"PFL on, buttons Mute\" while a PFL is on; briefly \"Buttons\" over \"PFL\" while Function is held).",
            "The **Novation button** brings TotalMix FX's window to the front, as on the XL 3.",
            "The Launch Control 3 has not been tried on a device yet.",
        ])

    static let rotoControl = ControlsGuide(
        title: "Roto-Control",
        image: "controller-roto-control",
        introduction: [
            "Each of the eight knobs is a channel.",
            "Hold **SEL** to choose what the knobs control (Volume, Pan, or a send, \"FX\") and what the switches do (Mute or Solo; Solo is PFL here).",
            "The < and > buttons page through the channels. Pressing both arrow buttons together switches the Roto-Control to its second track set (\"MIX-RTN\" on its screen), which shows the same channels.",
        ],
        tables: [],
        notes: [
            "A mute that is on flashes while TotalMix FX's Mute Master is off.",
        ])
}
