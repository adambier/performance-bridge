import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// One step of setting up Performance Bridge, as the app's setup window shows it.
public struct SetupStep: Equatable, Sendable, Identifiable {
    /// Where a step stands.
    public enum State: Equatable, Sendable {
        /// Seen working.
        case done
        /// Not seen yet; the detail says what to do.
        case waiting
        /// Something is in the way; the detail says what.
        case problem
        /// Optional: not needed for the surfaces to work.
        case optional
        /// Something the app can't check; the detail says how to do it.
        case instruction
    }

    /// A stable name for the step.
    public var id: String
    /// What the step is, in a few words.
    public var title: String
    /// Where it stands.
    public var state: State
    /// What to do, or what was seen. Empty when there is nothing to add. Each line is shown on
    /// its own (e.g., a numbered step), and a blank line starts a new paragraph. A line
    /// `[image: name]` marks where the app shows the screenshot `name`: right after the steps it
    /// shows (Adam, 2026-11-02).
    public var detail: String
    /// For a step that is done, how it is set up, shown on request (Adam, 2026-11-02): e.g., to
    /// set up a second Mac the same way. Empty when there is nothing to show.
    public var instructions: String

    /// Makes a step.
    public init(id: String, title: String, state: State, detail: String, instructions: String = "") {
        self.id = id
        self.title = title
        self.state = state
        self.detail = detail
        self.instructions = instructions
    }
}

/// The steps of setting up Performance Bridge with TotalMix FX and a Roto-Control, checked live
/// from the engine's status where the app can see the result, and given as instructions where it
/// can't. Every TotalMix FX location is given in full, with the labels TotalMix FX shows; they were
/// checked on screen with TotalMix FX "2.10 (1)" (docs/SETUP.md).
public enum SetupChecklist {
    /// The steps for a status and the settings the engine runs with. `totalMixRunning` says whether
    /// TotalMix FX is among the running apps, and `totalMixVersion` is its version as its app bundle
    /// gives it (`nil` when not running or not read).
    public static func steps(status: BridgeStatus, settings: BridgeSettings, totalMixRunning: Bool = false,
                             totalMixVersion: String? = nil) -> [SetupStep] {
        let incoming = settings.endpoint.incomingPort
        let outgoing = settings.endpoint.outgoingPort
        var steps: [SetupStep] = []

        steps.append(status.listening
            ? SetupStep(id: "port", title: "Performance Bridge is listening on port \(outgoing)",
                        state: .done, detail: "No other program is using port \(outgoing), so TotalMix FX’s messages can reach Performance Bridge.")
            : SetupStep(id: "port", title: "Port \(outgoing) is in use",
                        state: .problem,
                        detail: "Another program is using port \(outgoing), the port TotalMix FX sends to. Quit it (for example, another OSC remote or a developer tool left running).\n\nPerformance Bridge keeps trying."))

        steps.append(versionStep(status: status, running: totalMixRunning, version: totalMixVersion))

        // Lines are list items; a blank line starts a new paragraph (SetupView spaces them). Each
        // screenshot follows the steps it shows.
        let oscSetup = """
            In TotalMix FX:
            1. Options → Enable OSC Control: checked.
            2. Options → Mixer Settings… (F3) → OSC.
            [image: totalmix-options-menu]
            3. “Select Controller”: an OSC Controller (1–4) no other program or device uses. Check “In Use”.
            4. “Compatibility (Mode)”: Global OSC.
            5. “Port (incoming)”: \(incoming).
            6. Under “Remote Controller Address”, “Port (outgoing)”: \(outgoing).
            7. “Host”: localhost (if Performance Bridge runs on this Mac).
            [image: totalmix-osc-tab]
            8. Click Details and check “Send changes” and “Send status”.
            [image: totalmix-osc-details]

            Each OSC Controller needs its own ports. If TotalMix FX uses other ports, set the same ones in Performance Bridge’s Settings, on the Connections tab.
            """
        if status.totalMixAnswering {
            steps.append(SetupStep(id: "totalmix", title: "TotalMix FX is connected", state: .done,
                                   detail: "TotalMix FX answers on its OSC Controller for Performance Bridge, with ports \(incoming) (incoming) and \(outgoing) (outgoing).",
                                   instructions: oscSetup))
        } else {
            steps.append(SetupStep(id: "totalmix", title: "TotalMix FX hasn’t answered yet",
                                   state: status.listening ? .waiting : .problem, detail: oscSetup))
        }

        if status.channelCount > 0 {
            steps.append(SetupStep(id: "channels", title: "TotalMix FX has sent its channels", state: .done,
                                   detail: "Performance Bridge has detected \(status.channelCount) TotalMix FX channels. Channels hidden from its OSC Controller aren’t detected."))
        } else {
            steps.append(SetupStep(id: "channels", title: "TotalMix FX hasn’t sent its channels yet",
                                   state: .waiting,
                                   detail: status.totalMixAnswering
                                       ? "TotalMix FX answered with its status only. Performance Bridge keeps asking.\n\nIf this doesn’t change, choose Refresh Channels from TotalMix FX from the menu."
                                       : ""))
        }

        let metersSetup = "For meters on the hardware controllers: in TotalMix FX, Options → Mixer Settings… (F3) → OSC, check “Send Level Data” for Performance Bridge’s OSC Controller.\n\nTotalMix FX sends levels only when they change, so play something to see them."
        steps.append(status.levelsSeen
            ? SetupStep(id: "meters", title: "Meter levels are arriving", state: .done,
                        detail: "TotalMix FX is sending meter levels.", instructions: metersSetup)
            : SetupStep(id: "meters", title: "No meters yet", state: .optional, detail: metersSetup))

        if status.muteMasterOff {
            steps.append(SetupStep(id: "mutemaster", title: "Mute Master is off in TotalMix FX", state: .problem,
                                   detail: "While it’s off, a mute turned on from the hardware controller is only set and doesn’t silence the channel; TotalMix FX shows its M button partly lit. Turning on Mute Master immediately mutes every channel whose mute is set.\n\nIn TotalMix FX, turn on the “M” (Mute Master) button in the Control Strip, below the interface’s name and “undo”."))
        }

        let rotoBusy = "If it stays here, quit any other program that talks to the Roto-Control, such as a DAW with its Roto-Control integration."
        if !status.rotoEnabled {
            // Another hardware controller is in use.
        } else if status.rotoConnected {
            steps.append(SetupStep(id: "roto", title: "Roto-Control is connected", state: .done,
                                   detail: "Its knobs and switches control TotalMix FX, in MIX mode.",
                                   instructions: "Connect the Roto-Control by USB. If it doesn’t connect, quit any other program that talks to the Roto-Control, such as a DAW with its Roto-Control integration."))
        } else if status.rotoFound {
            steps.append(SetupStep(id: "roto", title: "Roto-Control found, connecting", state: .waiting, detail: rotoBusy))
        } else {
            steps.append(SetupStep(id: "roto", title: "Roto-Control not found", state: .waiting,
                                   detail: "Connect the Roto-Control by USB. If it’s connected, try another cable or USB port.\n\nIf a Launch Control XL 3 or Launch Control 3 is plugged in instead, Performance Bridge switches to it by itself. Otherwise, choose it in Performance Bridge’s Settings, on the Connections tab."))
        }

        if let name = status.launchControlName {
            if status.launchControlConnected {
                steps.append(SetupStep(id: "launchcontrol", title: "\(name) is connected", state: .done,
                                       detail: "It is in DAW mode, and it controls TotalMix FX.",
                                       instructions: "Connect the Launch Control by USB. If it doesn’t connect, quit any other program that uses its DAW ports, such as a DAW with its Launch Control integration."))
            } else if status.launchControlFound {
                steps.append(SetupStep(id: "launchcontrol", title: "\(name) found, connecting", state: .waiting,
                                       detail: "If it stays here, quit any other program that uses its DAW ports, such as a DAW with its Launch Control integration."))
            } else {
                steps.append(SetupStep(id: "launchcontrol", title: "\(name) not found", state: .waiting,
                                       detail: "Connect the Launch Control by USB. If it’s connected, check that the model chosen in Performance Bridge’s Settings, on the Connections tab, is the one connected, then try another cable or USB port."))
            }
        }

        // Neither Live mode nor "Cue/PFL to" can be read over OSC (docs/TOTALMIX-OSC.md, tests 6
        // and 21), so they are notes.
        steps.append(SetupStep(id: "livemode", title: "Turn on Live mode for PFL", state: .instruction,
                               detail: "The hardware controllers’ PFL buttons have been seen to do nothing visible unless TotalMix FX is in Live mode, which Performance Bridge can’t check. With Live mode on, the channels’ buttons read PFL instead of S.\n\nIn TotalMix FX’s Control Strip, click “options” and, under “solo/pfl mode”, choose “live”."))
        steps.append(SetupStep(id: "cue", title: "Send PFL to your headphones", state: .instruction,
                               detail: "TotalMix FX sends PFL to Main by default, so PFL from a hardware controller replaces what Main Out plays: on stage, the audience hears only the channel being checked. Performance Bridge can’t check this setting.\n\nIn TotalMix FX’s Control Room section, click “assign”, then “Cue/PFL to”, and choose a headphone output (e.g., “Phones 1”)."))

        // The color tip is only for a Launch Control, so it shows only once one is chosen (Adam,
        // 2026-11-02).
        let colorTip = status.launchControlName == nil ? ""
            : " Give each output the send rows feed (e.g., each headphone output) a color of its own: a send row lights in its output’s color, so the color shows which output it feeds."
        steps.append(SetupStep(id: "hide", title: "Hide channels in TotalMix FX", state: .instruction,
                               detail: "Hide and show channels in TotalMix FX: choose Options → Channel Layout…, or right-click the channel and choose Change Channel Layout. Under “Hide Channel in”, check or uncheck the box for Performance Bridge’s OSC Controller.\n\nChannel colors can be set in the same window." + colorTip))
        steps.append(SetupStep(id: "order", title: "Set the order of the channels", state: .optional,
                               detail: "Set the order of the channels, and give them short labels for the hardware controllers, on the Channel Layout tab of Performance Bridge’s Settings."))
        return steps
    }

    /// TotalMix FX's version: Global OSC needs 2.1 or later; release candidates count.
    static func versionStep(status: BridgeStatus, running: Bool, version: String?) -> SetupStep {
        // An answer from TotalMix FX proves it runs, whatever the list of running apps says.
        let running = running || status.totalMixAnswering
        let needs = "Performance Bridge requires TotalMix FX 2.1 or later."
        guard running else {
            return SetupStep(id: "version", title: "TotalMix FX isn’t running", state: .waiting,
                             detail: "Open TotalMix FX. " + needs)
        }
        // The About window is under the TotalMix FX menu (Adam, 2026-11-02); the item's exact label
        // hasn't been checked on screen.
        guard let text = version, let parsed = TotalMixVersion(text) else {
            return SetupStep(id: "version", title: "TotalMix FX’s version couldn’t be read", state: .instruction,
                             detail: needs + " To check TotalMix FX’s version, choose About from the TotalMix FX menu.")
        }
        if parsed.supportsGlobalOSC {
            return SetupStep(id: "version", title: "TotalMix FX \(text) has Global OSC", state: .done,
                             detail: "Global OSC is supported by TotalMix FX 2.1 or later.")
        }
        return SetupStep(id: "version", title: "TotalMix FX \(text) is too old", state: .problem,
                         detail: needs + " Update it from RME’s website.")
    }

    /// The page the setup assistant opens at: the step `openFor` names if it is there (e.g., the
    /// problem that opened the window), else the first step that is waiting or has a problem, else
    /// the first one not done (e.g., the notes), else the first page. Back and Continue then go
    /// through every page, done or not (Adam, 2026-11-02).
    public static func startIndex(of steps: [SetupStep], openFor: String? = nil) -> Int {
        if let openFor, let index = steps.firstIndex(where: { $0.id == openFor }) { return index }
        return steps.firstIndex { $0.state == .waiting || $0.state == .problem }
            ?? steps.firstIndex { $0.state != .done } ?? 0
    }

    /// Whether every step the surfaces need is done: TotalMix FX answering with its channels, the
    /// Roto-Control connected if it is used, and the Launch Control connected if one is set.
    public static func isComplete(_ status: BridgeStatus) -> Bool {
        status.listening && status.totalMixAnswering && status.channelCount > 0
            && (!status.rotoEnabled || status.rotoConnected)
            && (status.launchControlName == nil || status.launchControlConnected)
    }
}
