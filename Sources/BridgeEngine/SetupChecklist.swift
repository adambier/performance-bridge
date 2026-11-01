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
    /// What to do, or what was seen. Empty when there is nothing to add.
    public var detail: String

    /// Makes a step.
    public init(id: String, title: String, state: State, detail: String) {
        self.id = id
        self.title = title
        self.state = state
        self.detail = detail
    }
}

/// The steps of setting up Performance Bridge with TotalMix FX and a Roto-Control, checked live
/// from the engine's status where the app can see the result, and given as instructions where it
/// can't. Every TotalMix location is given in full, with the labels TotalMix shows; they were
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
                        state: .done, detail: "")
            : SetupStep(id: "port", title: "Port \(outgoing) is in use",
                        state: .problem,
                        detail: "Another program is using port \(outgoing), the port TotalMix FX sends to. Quit it (for example, sbdev or another OSC remote). Performance Bridge keeps trying."))

        steps.append(versionStep(status: status, running: totalMixRunning, version: totalMixVersion))

        let oscSetup = """
            In TotalMix FX:
            1. Options → Enable OSC Control: checked.
            2. Options → Mixer Settings… (F3) → OSC. Under “Select Controller”, choose a controller that no other program or device uses, and check “In Use”.
            3. “Compatibility (Mode)”: Global OSC.
            4. “Port (incoming)”: \(incoming). Under “Remote Controller Address”, “Host”: localhost if Performance Bridge runs on this Mac, and “Port (outgoing)”: \(outgoing).
            5. Click Details, and check “Send changes” and “Send status”.
            Each controller needs its own ports: no two may share one. If TotalMix FX uses other ports, set the same ones in Performance Bridge’s Settings.
            """
        if status.totalMixAnswering {
            steps.append(SetupStep(id: "totalmix", title: "TotalMix FX answers", state: .done, detail: ""))
        } else {
            steps.append(SetupStep(id: "totalmix", title: "TotalMix FX hasn’t answered yet",
                                   state: status.listening ? .waiting : .problem, detail: oscSetup))
        }

        if status.channelCount > 0 {
            steps.append(SetupStep(id: "channels", title: "TotalMix FX sent its channels", state: .done,
                                   detail: "\(status.channelCount) channels."))
        } else {
            steps.append(SetupStep(id: "channels", title: "TotalMix FX hasn’t sent its channels yet",
                                   state: .waiting,
                                   detail: status.totalMixAnswering
                                       ? "TotalMix FX answered with its status only. Performance Bridge keeps asking; if this stays, choose Refresh Channels from TotalMix FX from the menu."
                                       : "This follows once TotalMix FX answers."))
        }

        steps.append(status.levelsSeen
            ? SetupStep(id: "meters", title: "Meters arrive", state: .done, detail: "")
            : SetupStep(id: "meters", title: "No meters yet", state: .optional,
                        detail: "For meters on the hardware controllers: in TotalMix FX, Options → Mixer Settings… (F3) → OSC, check “Send Level Data” for the controller. TotalMix FX sends levels only when they change, so play something to see them."))

        if status.rotoConnected {
            steps.append(SetupStep(id: "roto", title: "Roto-Control connected", state: .done, detail: ""))
        } else if status.rotoFound {
            steps.append(SetupStep(id: "roto", title: "Roto-Control found, connecting", state: .waiting,
                                   detail: "If it stays here, quit any other program that talks to the Roto-Control, such as a DAW with its Roto-Control integration."))
        } else {
            steps.append(SetupStep(id: "roto", title: "Roto-Control not found", state: .waiting,
                                   detail: "Connect the Roto-Control by USB. If it’s connected, choose its MIDI port in Performance Bridge’s Settings."))
        }

        steps.append(SetupStep(id: "hide", title: "Channels the hardware controllers don’t show", state: .instruction,
                               detail: "Channels are hidden in TotalMix FX: right-click the channel, choose Change Channel Layout, and under “Hide Channel in” check the OSC Controller box for the controller Performance Bridge uses. Channel colors are set in the same window."))
        steps.append(SetupStep(id: "order", title: "The order of the channels", state: .instruction,
                               detail: "Choose Settings… from the menu, open the Channel Layout tab, and drag. Restore TotalMix FX Order puts them back."))
        return steps
    }

    /// TotalMix FX's version: Global OSC needs 2.1 or later; release candidates count.
    static func versionStep(status: BridgeStatus, running: Bool, version: String?) -> SetupStep {
        // An answer from TotalMix proves it runs, whatever the list of running apps says.
        let running = running || status.totalMixAnswering
        let needs = "Performance Bridge needs TotalMix FX 2.1 or later (release candidates are fine): earlier versions don’t have Global OSC."
        guard running else {
            return SetupStep(id: "version", title: "TotalMix FX isn’t running", state: .waiting,
                             detail: "Open TotalMix FX. " + needs)
        }
        guard let text = version, let parsed = TotalMixVersion(text) else {
            return SetupStep(id: "version", title: "TotalMix FX’s version", state: .instruction,
                             detail: "Performance Bridge couldn’t read it. " + needs)
        }
        if parsed.supportsGlobalOSC {
            return SetupStep(id: "version", title: "TotalMix FX \(text) has Global OSC", state: .done, detail: "")
        }
        return SetupStep(id: "version", title: "TotalMix FX \(text) is too old", state: .problem,
                         detail: needs + " Update it from RME’s website.")
    }

    /// Whether every step the surfaces need is done: TotalMix answering with its channels, and the
    /// Roto-Control connected.
    public static func isComplete(_ status: BridgeStatus) -> Bool {
        status.listening && status.totalMixAnswering && status.channelCount > 0 && status.rotoConnected
    }
}
