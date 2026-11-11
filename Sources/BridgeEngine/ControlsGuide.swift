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

    /// The controller's name, with its maker's, as the guide's title (Adam, 2026-11-04).
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
        "Levels and pans go into Main Out's submix: the output TotalMix FX's control room assigns to Main Out, whichever it is. Set the outputs themselves (e.g., Main Out's volume and Speaker B) in TotalMix FX or with an ARC USB; the hardware controllers don't change them.",
        "**Sends** set the headphone mixes and the other submixes. A send control sets how much of its channel goes to one other output, e.g., Phones 1. A row of send controls is that output's whole submix, one channel per column.",
        "The outputs a send row can feed are the ones in **Settings… → Channel Layout → Outputs**, in that order. Main Out and Main Out B (they carry the main mix) aren't listed there, nor is an output that has CUE on in TotalMix FX's Control Room.",
        "**PFL** plays one channel alone in the output chosen in TotalMix FX's Control Room (click **assign**, then **Cue/PFL to**). That output is Main by default, which replaces the main mix, so choose a headphone output before a performance.",
    ]

    /// The guide for a hardware controller.
    public static func guide(for controller: DetectedController) -> ControlsGuide {
        switch controller {
        case .launchControl(.xl3): return launchControlXL3
        case .launchControl(.lc3): return launchControl3
        case .roto: return rotoControl
        case .e16: return e16
        }
    }

    static let launchControlXL3 = ControlsGuide(
        title: "Novation Launch Control XL 3",
        image: "controller-launch-control-xl3",
        introduction: [
            "**Each column of controls is one channel**, and every control in a column acts on that channel.",
        ],
        tables: [
            Table(controlHeading: "Control (in each column)", actionHeading: "What it does for that column's channel", rows: [
                Row("Fader", "Level in Main Out. The ticks read +6, +3, 0, −6, −10, −20, −40, −60, and −oo, as on TotalMix FX's faders. If a fader isn't where TotalMix FX has the level, it takes effect once it reaches it; its display shows the level meanwhile."),
                Row("Top encoder", "Send to the top row's output (e.g., Phones 1)."),
                Row("Middle encoder", "Send to the middle row's output (e.g., Phones 2)."),
                Row("Bottom encoder", "Pan in Main Out."),
                Row("Top button", "PFL: bright yellow when on, dim yellow when off. The screen briefly names the channel and says \"PFL on\" or \"PFL off\"."),
                Row("Bottom button", "Mute: bright orange when on, dim orange when off. The screen says \"Mute on\" or \"Mute off\", or \"Mute Master off\" while TotalMix FX's Mute Master is off; a mute that is on then flashes."),
            ]),
            Table(controlHeading: "Button", actionHeading: "What it does", rows: [
                Row("**Track >** / **Track <**", "Show the next or previous eight channels. With **Shift**: the last or first eight."),
                Row("**Page ▲** / **Page ▼**", "Change the output the **top** encoder row feeds, to the previous or next one in the Outputs list."),
                Row("**Shift + Page ▲** / **▼**", "The same for the **middle** encoder row."),
                Row("**Shift + turn an encoder**", "Reset it: a pan to the center, a send to −oo (release Shift, then Shift + turn it again to bring it back). Hold Shift for a moment (0.3 s) first; after Page or Track in the same hold, turning does nothing."),
            ]),
        ],
        notes: [
            "The two send rows never feed the same output: stepping one skips the output the other has.",
            "The screen shows the page and the channels on it, counted in the order of **Settings… → Channel Layout** with a stereo pair counting once, and where each send row goes (e.g., \"1/2: Inputs 1-8\", \"Top > Phones 1\", \"Mid > Phones 2\"). With **Meters: Show on the home screen** on (Settings… → Connections), it shows a meter for each channel instead, two bars for a stereo channel, with the channel's number under it, inputs and playbacks each counted as in the first line, and a line under the playbacks' numbers; Track shows the page, and the send rows' outputs show only on Page and when an encoder turns. Meters need TotalMix FX's **Send Level Data** on and **Peak Hold** off (see the Setup Guide).",
            "Moving a control shows its channel, what it does, and its value.",
            "How long that stays up, in seconds, is the XL 3's own **Display Timeout** setting. To change it, switch to a Custom Mode (**Mode**, a blue button, **Mode**), hold **Track <** and **Track >** together, press **Page ▼** until the screen shows Display Timeout, and turn the top-left encoder; then press **Mode**, and quit and reopen Performance Bridge to go back to its layout.",
            "After each Page press the screen names the row and its new output, and each send row's lights take the color of the output it feeds: its color in TotalMix FX, or, for an output left white, teal (a blue-green) for the top row and magenta for the middle row.",
            "With **Levels: Show by brightness** on (Settings… → Connections), the send encoders dim with their level and are dark at −oo.",
            "Page and Track are lit where they can move and dark at the ends. While Shift is held, Page lights for the middle row.",
            "Each row's output is remembered when Performance Bridge restarts. It can also be chosen in Settings, in the Launch Control's box on the Connections tab, with the Launch Control connected or not; the change takes effect at once.",
            "Press **Track <** and **Track >** together to go back to the first eight channels.",
            "The **Novation button** brings TotalMix FX's window to the front. Press it again while TotalMix FX is in front to go back to the app you were in (if TotalMix FX came to the front some other way, the press hides it instead).",
            "Solo/Arm, Mute/Select, Record, and Play do nothing in this release; they are kept free for later uses (e.g., a connection to a DAW).",
            "Levels and pans are Main Out's. In TotalMix FX each submix has its own level and pan for every channel, so TotalMix FX's window shows the levels and pans set here only while Main Out's output is selected in its bottom row.",
        ])

    static let launchControl3 = ControlsGuide(
        title: "Novation Launch Control 3",
        image: "controller-launch-control-3",
        introduction: [
            "**Each column of controls is one channel**, and every control in a column acts on that channel.",
        ],
        tables: [
            Table(controlHeading: "Control (in each column)", actionHeading: "What it does for that column's channel", rows: [
                Row("Bottom encoder", "Level in Main Out."),
                Row("Top encoder", "Pan, or a send: **Page ▲** / **▼** steps it through Pan, then each output in the Outputs list."),
                Row("Button", "Mute, or PFL while **Function** (printed \"DAW\" beneath it) is held. Orange for mute, yellow for PFL, dim when off. Function rests dim yellow and lights bright yellow while held, and while any channel's PFL is on, so a PFL left on still shows."),
            ]),
            Table(controlHeading: "Button", actionHeading: "What it does", rows: [
                Row("**Track >** / **Track <**", "Show the next or previous eight channels. With **Shift**: the last or first eight."),
                Row("**Page ▲** / **Page ▼**", "Change what the top encoder row does: Pan, then each output in the Outputs list, in order."),
                Row("**Shift + turn an encoder**", "Reset it: a pan to the center, a level above 0 dB down to 0 dB (one at or below 0 dB stays), a send to −oo (release Shift, then Shift + turn it again to bring it back). Hold Shift for a moment (0.3 s) first; after Page or Track in the same hold, turning does nothing."),
            ]),
        ],
        notes: [
            "The screen shows the channels on the page, counted in the order of **Settings… → Channel Layout** with a stereo pair counting once, the top row's function (e.g., \"Top: Pan\"), and the buttons' (\"Buttons: Mute\", or \"PFL on, buttons Mute\" while a PFL is on; \"Buttons: PFL\" while Function is held).",
            "Moving a control shows its channel, what it does, and its value.",
            "After each Page press the screen names the top row's new function. As a send, the row's lights take the color of the output it feeds: its color in TotalMix FX, or teal (a blue-green) for an output left white.",
            "The top row's function is remembered when Performance Bridge restarts. It can also be chosen in Settings, in the Launch Control's box on the Connections tab, with the Launch Control connected or not; the change takes effect at once.",
            "Press **Track <** and **Track >** together to go back to the first eight channels.",
            "The **Novation button** brings TotalMix FX's window to the front. Press it again while TotalMix FX is in front to go back to the app you were in (if TotalMix FX came to the front some other way, the press hides it instead).",
            "Levels and pans are Main Out's. In TotalMix FX each submix has its own level and pan for every channel, so TotalMix FX's window shows the levels and pans set here only while Main Out's output is selected in its bottom row.",
        ])

    static let rotoControl = ControlsGuide(
        title: "Melbourne Instruments Roto-Control",
        image: "controller-roto-control",
        introduction: [
            "**Each column of controls is one channel**, and every control in a column acts on that channel.",
        ],
        tables: [
            Table(controlHeading: "Control (in each column)", actionHeading: "What it does for that column's channel", rows: [
                Row("Knob", "Level in Main Out, pan in Main Out, or a send, by the knob mode (hold **SEL**, below). A level knob's faint indent is 0 dB; a send knob has no indent, but 0 dB is at the same position. Touching a knob usually selects its channel (for **FUNC**, below; the Roto-Control misses some touches) and holds it: TotalMix FX doesn't move a knob while it is touched or turning."),
                Row("Screen", "The channel's name, in its TotalMix FX color, and its meter. While a knob turns, its value."),
                Row("Switch", "Mute or PFL, by the switch mode (hold **SEL**): orange for mute, yellow for PFL. The Roto-Control's SOLO is PFL here; ARM REC does nothing in this release."),
            ]),
            Table(controlHeading: "Button", actionHeading: "What it does", rows: [
                Row("**←** / **→**", "Show the previous or next eight channels. In the single-channel view (**FUNC**), the previous or next page of sends."),
                Row("**←** and **→** together", "Switch to the Roto-Control's second track set (\"MIX-RTN\" on its screen). It shows the same channels, on the same page; press both again to go back."),
                Row("**SEL** (hold)", "Choose the knob mode with the switch under VOLUME, PAN, or the send (labeled \"FX\"; pressing it again has been observed to step through the sends), and the switch mode with the switch under MUTE or SOLO (ARM does nothing). The modes are kept when the Roto-Control is switched off."),
                Row("**FUNC**", "All of one channel's controls: the channel whose knob was last touched (the first channel until one is), with knob 1 level, knob 2 pan, and knobs 3–8 its first six sends; **←** and **→** page through eight more sends at a time. The switches do nothing in this view. Press **FUNC** again to go back to eight channels."),
                Row("**MODE**", "The Roto-Control's own mode menu. Performance Bridge works in its MIX mode; press **MODE**, then MIX, to return to it. PLUGIN mode shows no plugins in this release, and MIDI mode is not used."),
                Row("**LEARN**, the tape button, the (+) button, and the transport switches", "Nothing in this release. Learn belongs to PLUGIN mode; the tape button switches the eight switches to transport controls, kept for a later connection to a DAW (press it again to get mute or PFL back); the (+) button is track grouping, which TotalMix FX has no use for (it blinks green until pressed again)."),
            ]),
        ],
        notes: [
            "A mute that is on flashes while TotalMix FX's Mute Master is off.",
            "The knob and switch modes, and the track set, are the Roto-Control's own and are kept between sessions; Performance Bridge follows them and can't set them, so a session can start with the knobs on a send. The small screen above LEARN shows both (e.g., \"MIX-TRACKS\" and \"KNOBS-VOL\").",
        ])

    static let e16 = ControlsGuide(
        title: "OXI Instruments E16",
        image: "controller-oxi-e16",
        introduction: [
            "The E16 has two layouts. In the **16-channel layout**, each encoder is one channel: the four rows of four are the channels in order, left to right and top to bottom. In the **channel-strip layout**, each column is one channel: send A level on the top row, send B level on the second, pan on the third, and main level on the bottom. Each ring shows its value in its channel's TotalMix FX color; a send's ring takes its output's color (the channel's, for an output left white).",
        ],
        tables: [
            Table(controlHeading: "Control (each encoder)", actionHeading: "What it does for that encoder's channel", rows: [
                Row("Turn", "In the 16-channel layout, level in Main Out, pan in Main Out, or a send, by the mode (**Shift**, below); in the channel-strip layout, the row's send A level, send B level, pan, or main level. A level or send fills its ring at 0 dB and above."),
                Row("Push and release", "Mute on or off; in the channel-strip layout, any encoder of the channel's column, shown on its main level ring. A muted channel's ring goes dark with four orange lights turning around it; on the screen, its name is struck through. While TotalMix FX's Mute Master is off, a mute is only set and doesn't silence the channel: the four lights stand still and take turns with the level, half a second each, and the line through its name flashes; with PFL also on, the lights turn with the pink ones and blink. The screen says \"MUTE SET\" for such a mute."),
                Row("Hold for one second", "PFL on or off. After a quarter second, a pink arc counts down around the ring; when it closes, PFL switches. While PFL is on, the ring goes dark with four pink lights turning around it, as a mute's orange ones do, and a small square follows the channel's name; with both on, the orange and pink lights turn together."),
                Row("Push and turn", "A jump to the next stop the way it turns: for a level or a send, −∞, 0 dB, or +6 dB; for a pan, hard left, center, or hard right. To jump on to the next stop, pause, then turn again. Start turning within a second of pushing: a push that turns neither mutes nor switches PFL."),
            ]),
            Table(controlHeading: "Hold Shift and press (16-channel layout)", actionHeading: "What it does", rows: [
                Row("**1** LEVEL / **2** PAN / **3** SEND", "What a turn does: level (white), pan (magenta), or a send (green) to the last output used."),
                Row("**11** / **12** < SEND >", "The previous or next output for the sends (green), from the one named beside them; in LEVEL or PAN mode they also switch to SEND."),
                Row("**13** 16 CH / **14** STRIP", "The layout (yellow). STRIP shows the four channels holding the one last turned or pushed."),
                Row("**15** / **16** < PAGE >", "The previous or next sixteen channels (blue)."),
            ]),
            Table(controlHeading: "Hold Shift and press (channel-strip layout)", actionHeading: "What it does", rows: [
                Row("**3** / **4** < SEND >", "The previous or next output for send A, the top row (green). It skips send B's output."),
                Row("**7** / **8** < SEND >", "The same for send B, the second row."),
                Row("**13** 16 CH / **14** STRIP", "The layout (yellow). 16 CH shows the sixteen channels holding these four."),
                Row("**15** / **16** < PAGE >", "The previous or next four channels (blue)."),
            ]),
        ],
        notes: [
            "While Shift is held, the button in use pulses and its label is inverted on the screen, the other buttons available are dim, and an arrow with nowhere to go is dark.",
            "A small square before the page number at the top right means a channel not on this page has PFL on.",
            "A dark ring with no lights on it has no channel. In the channel-strip layout, a muted channel's send rings are dark too.",
            "A pan shows as an arc from the top: in the channel's color at center and red as soon as it moves off center, however little. Turning a pan stops at center, however fast; to move past it, pause, then turn a little further.",
            "The layout, the sends, meters, and ring brightness can be set in **Settings… → Connections**; meters need TotalMix FX's **Send Level Data** on (see the Setup Guide).",
            "Levels and pans are Main Out's. In TotalMix FX each submix has its own level and pan for every channel, so TotalMix FX's window shows the levels and pans set here only while Main Out's output is selected in its bottom row.",
            "The E16 needs firmware 1.3.0 or later (Remote Mode doesn't work before 1.3.0). When Performance Bridge quits, it gives the E16 back to its own firmware; if the E16 is ever left blank, switch it off and on.",
        ])
}
