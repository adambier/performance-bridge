import Foundation
#if canImport(RotoControl)
import RotoControl
#endif

// A relay between a Roto-Control and Melbourne Instruments' Bitwig Studio integration, for tests
// R2 and R4 of docs/PLUGIN-MODE-PLAN.md (sections 2–4). The routing rules come from a reading of
// the integration's code and of the SysEx doc; none has been tested on the device or with
// Bitwig Studio. Each rule is one function or one constant below, named for what it decides.

/// What the Roto-Control's knobs are on, as the relay follows it from what the device sends.
public enum RotoRelayKnobMode: Equatable, Sendable {
    /// MIX mode: the local owner has the device, and the host's messages are dropped.
    case mix
    /// PLUGIN mode: the host has the device.
    case plugin
}

/// One routing decision of the relay, for a log.
public struct RotoRelayDecision: Equatable, Sendable, CustomStringConvertible {
    /// Where a message came from.
    public enum Source: String, Equatable, Sendable {
        /// The Roto-Control.
        case device
        /// The host (Bitwig Studio's integration).
        case host
        /// The relay itself: a replayed message, or an answer it gives in the device's place.
        case relay
    }

    /// Where a message went.
    public enum Route: String, Equatable, Sendable {
        /// Sent on to the host.
        case toHost = "host"
        /// Sent on to the device.
        case toDevice = "device"
        /// Left for the local owner of MIX mode.
        case forLocal = "local"
        /// Sent nowhere.
        case dropped
    }

    /// Where the message came from.
    public var source: Source
    /// Where it went.
    public var route: Route
    /// The complete message.
    public var bytes: [UInt8]
    /// The rule that decided, in a few words.
    public var rule: String

    /// Makes a decision.
    public init(source: Source, route: Route, bytes: [UInt8], rule: String) {
        self.source = source
        self.route = route
        self.bytes = bytes
        self.rule = rule
    }

    /// The direction as a log prints it: "device → host", "host → device", "device → local",
    /// "relay → device", "relay → host", "dropped host", or "dropped device".
    public var direction: String {
        route == .dropped ? "dropped \(source.rawValue)" : "\(source.rawValue) → \(route.rawValue)"
    }

    /// The direction, the bytes in hex, and the rule.
    public var description: String {
        let hex = bytes.map { byte in
            let digits = String(byte, radix: 16, uppercase: true)
            return digits.count < 2 ? "0" + digits : digits
        }.joined(separator: " ")
        return "\(direction)  \(hex)   [\(rule)]"
    }
}

/// What the relay does with the bytes of one call: the routing decisions, in order.
public struct RotoRelayOutput: Equatable, Sendable {
    /// Every decision the call made, in the order the messages are to be sent.
    public var decisions: [RotoRelayDecision]

    /// Makes an output.
    public init(decisions: [RotoRelayDecision] = []) {
        self.decisions = decisions
    }

    /// The complete messages to send to the host, in order.
    public var toHost: [[UInt8]] { decisions.filter { $0.route == .toHost }.map(\.bytes) }
    /// The complete messages to send to the device, in order.
    public var toDevice: [[UInt8]] { decisions.filter { $0.route == .toDevice }.map(\.bytes) }
    /// The complete messages from the device left for the local owner, in order.
    public var forLocal: [[UInt8]] { decisions.filter { $0.route == .forLocal }.map(\.bytes) }
    /// The complete messages sent nowhere, in order.
    public var dropped: [[UInt8]] { decisions.filter { $0.route == .dropped }.map(\.bytes) }
}

/// Routes MIDI between a Roto-Control (the device) and a host that believes it has the device to
/// itself, by the mode the device says it is in. The local owner, which ran the handshake as type
/// `02` and draws MIX mode, gets what is left.
///
/// The relay is pure: no I/O and no clock. Feed it each side's bytes as they arrive, in chunks of
/// any size (a SysEx message may span calls, and control changes may use running status), and
/// send what it returns. Every message it returns is complete.
///
/// The device's mode is unknown until the device sends one of the messages that tell it, so the
/// relay starts in MIX mode (or `initialMode`), where the host's messages are dropped.
public struct RotoRelay: Sendable {
    /// What the knobs are on. While the transport switches are active this is the mode the knobs
    /// were in when they became active.
    public private(set) var knobMode: RotoRelayKnobMode
    /// Whether the transport switches are active: from REQUEST TRANSPORT STATUS until the next
    /// SET PLUGIN MODE, SET MIX ALL TRACKS MODE, or SET MIX TRACK MODE.
    public private(set) var transportSwitchesActive = false
    /// The device's ROTO FW VERSION message (`0A 0E`), complete, if one is known. The relay keeps
    /// the last one the device sends; set it to give the relay one from elsewhere.
    public var firmwareVersionReply: [UInt8]?

    private var deviceParser = RotoMIDIParser()
    private var hostParser = RotoMIDIParser()
    private var remembered = Remembered()

    /// Makes a relay that takes the device to be in `initialMode`.
    public init(initialMode: RotoRelayKnobMode = .mix) {
        knobMode = initialMode
    }

    // MARK: The host's last track page and sends

    /// What the host last sent of its track page and sends, each a complete message.
    private struct Remembered: Sendable {
        var trackCount: [UInt8]?
        var firstTrack: [UInt8]?
        var trackDetails: [[UInt8]] = []
        var trackDetailsEnd: [UInt8]?
        /// Whether TRACK DETAILS END has closed the list, so that the next TRACK DETAILS starts a
        /// new one.
        var trackDetailsClosed = false
        var sendCount: [UInt8]?
        var sendNames: [UInt8]?
        var selectTrack: [UInt8]?
    }

    /// The most TRACK DETAILS messages kept, against a host that never ends its list. A page has
    /// eight.
    static let maximumRememberedTrackDetails = 64

    /// Keeps a host message if it is one of those replayed on coming back to PLUGIN mode: NUM
    /// TRACKS, FIRST TRACK, each TRACK DETAILS up to the next TRACK DETAILS END, NUM SEND TRACKS,
    /// SEND TRACK NAMES, and DAW SELECT TRACK. Called in every mode.
    private mutating func remember(_ bytes: [UInt8], group: UInt8, command: UInt8) {
        switch (group, command) {
        case (0x0A, 0x04): remembered.trackCount = bytes
        case (0x0A, 0x05): remembered.firstTrack = bytes
        case (0x0A, 0x07):
            if remembered.trackDetailsClosed {
                remembered.trackDetails = []
                remembered.trackDetailsClosed = false
            }
            if remembered.trackDetails.count < Self.maximumRememberedTrackDetails {
                remembered.trackDetails.append(bytes)
            }
        case (0x0A, 0x08):
            remembered.trackDetailsEnd = bytes
            remembered.trackDetailsClosed = true
        case (0x0C, 0x03): remembered.sendCount = bytes
        case (0x0C, 0x08): remembered.sendNames = bytes
        case (0x0C, 0x04): remembered.selectTrack = bytes
        default: break
        }
    }

    /// The remembered messages, in the order they are replayed to the device on a change into
    /// PLUGIN mode: NUM TRACKS, FIRST TRACK, the TRACK DETAILS, TRACK DETAILS END, NUM SEND
    /// TRACKS, SEND TRACK NAMES, and DAW SELECT TRACK, each only if the host has sent one. A list
    /// of TRACK DETAILS the host has not yet ended is ended here (this project's choice).
    ///
    /// The reason for the replay is an inference from the integration's code: on SET PLUGIN MODE
    /// it sends its plugins again, but not these, which the local owner's MIX page has overwritten.
    public var replayOnEnteringPluginMode: [[UInt8]] {
        var messages: [[UInt8]] = []
        if let count = remembered.trackCount { messages.append(count) }
        if let first = remembered.firstTrack { messages.append(first) }
        messages += remembered.trackDetails
        if let end = remembered.trackDetailsEnd {
            messages.append(end)
        } else if !remembered.trackDetails.isEmpty {
            messages.append(RotoOutgoing.trackDetailsEnd.bytes)
        }
        if let count = remembered.sendCount { messages.append(count) }
        if let names = remembered.sendNames { messages.append(names) }
        if let track = remembered.selectTrack { messages.append(track) }
        return messages
    }

    // MARK: Control changes

    /// Whether a control change on channel 16 is one the device sends its host in PLUGIN mode:
    /// knobs (12–19 and 44–51), switches (20–27), touches (52–59), and transport (28–37).
    static func isPluginModeDeviceCC(channel: UInt8, controller: UInt8) -> Bool {
        guard channel == RotoCC.channel else { return false }
        return (12...19).contains(controller) || (44...51).contains(controller)
            || (20...27).contains(controller) || (52...59).contains(controller)
            || isDeviceTransportCC(channel: channel, controller: controller)
    }

    /// Whether a control change is one of the device's transport controls: channel 16, 28–37.
    static func isDeviceTransportCC(channel: UInt8, controller: UInt8) -> Bool {
        channel == RotoCC.channel && (28...37).contains(controller)
    }

    /// Whether a control change is one of the host's transport lights: channel 16, 28–35.
    static func isHostTransportCC(channel: UInt8, controller: UInt8) -> Bool {
        channel == RotoCC.channel && (28...35).contains(controller)
    }

    // MARK: From the device

    /// Whether a SysEx message from the device changes the mode, and to what. SET PLUGIN MODE
    /// (`0B 01`) means PLUGIN mode; SET MIX ALL TRACKS MODE (`0C 01`) and SET MIX TRACK MODE
    /// (`0C 02`) mean MIX mode. Each also ends the transport switches' layer.
    static func knobMode(setBy group: UInt8, _ command: UInt8) -> RotoRelayKnobMode? {
        switch (group, command) {
        case (0x0B, 0x01): return .plugin
        case (0x0C, 0x01), (0x0C, 0x02): return .mix
        default: return nil
        }
    }

    /// Whether a SysEx message from the device is never passed to the host, in any mode: SET MIX
    /// ALL TRACKS MODE, SET MIX TRACK MODE, and SET ALL TRACKS MODE, which the local owner
    /// answers; and ROTO-DAW CONNECTED, PING DAW, ROTO FW VERSION, and ROTO SYSEX API VERSION,
    /// which belong to the local owner's handshake.
    static func isAlwaysLocal(_ group: UInt8, _ command: UInt8) -> Bool {
        switch (group, command) {
        case (0x0C, 0x01), (0x0C, 0x02), (0x0C, 0x05): return true
        case (0x0A, 0x0C), (0x0A, 0x02), (0x0A, 0x0E), (0x0A, 0x10): return true
        default: return false
        }
    }

    /// Whether a SysEx message from the device goes to the host in PLUGIN mode: every PLUGIN
    /// (`0B`) message, SET FIRST TRACK (`0A 06`), ROTO SELECT TRACK (`0A 09`), REQUEST TRANSPORT
    /// STATUS (`0A 0A`), TOGGLE TRACK GROUPING (`0C 06`), and REQUEST SEND TRACK NAMES (`0C 07`).
    static func passesToHostInPluginMode(_ group: UInt8, _ command: UInt8) -> Bool {
        if group == 0x0B { return true }
        switch (group, command) {
        case (0x0A, 0x06), (0x0A, 0x09), (0x0A, 0x0A), (0x0C, 0x06), (0x0C, 0x07): return true
        default: return false
        }
    }

    /// Whether a SysEx message from the device goes to the host in MIX mode: only REQUEST
    /// TRANSPORT STATUS (`0A 0A`).
    static func passesToHostInMixMode(_ group: UInt8, _ command: UInt8) -> Bool {
        group == 0x0A && command == 0x0A
    }

    /// Takes bytes from the device and returns what to do with the messages they complete.
    public mutating func fromDevice<S: Sequence>(_ bytes: S) -> RotoRelayOutput where S.Element == UInt8 {
        var output = RotoRelayOutput()
        for message in deviceParser.feed(bytes) {
            switch message {
            case .sysEx(let sysEx):
                routeDeviceSysEx(sysEx, into: &output)
            case .controlChange(let channel, let controller, let value):
                let cc: [UInt8] = [0xB0 | (channel & 0x0F), controller, value]
                output.decisions.append(routeDeviceCC(cc, channel: channel, controller: controller))
            case .other(let other):
                output.decisions.append(RotoRelayDecision(source: .device, route: .forLocal, bytes: other,
                                                          rule: "not a control change or SysEx"))
            }
        }
        return output
    }

    private mutating func routeDeviceSysEx(_ bytes: [UInt8], into output: inout RotoRelayOutput) {
        func decide(_ route: RotoRelayDecision.Route, _ rule: String) {
            output.decisions.append(RotoRelayDecision(source: .device, route: route, bytes: bytes, rule: rule))
        }
        guard let (group, command, _) = RotoSysEx.unframe(bytes) else {
            decide(.forLocal, "not a Roto-Control message")
            return
        }
        if group == 0x0A, command == 0x0E { firmwareVersionReply = bytes }
        if group == 0x0A, command == 0x0A { transportSwitchesActive = true }

        if let mode = Self.knobMode(setBy: group, command) {
            let entering = mode == .plugin && knobMode != .plugin
            knobMode = mode
            transportSwitchesActive = false
            if mode == .plugin {
                decide(.toHost, entering ? "SET PLUGIN MODE: now in PLUGIN mode" : "SET PLUGIN MODE: still in PLUGIN mode")
                if entering {
                    for replay in replayOnEnteringPluginMode {
                        output.decisions.append(RotoRelayDecision(source: .relay, route: .toDevice, bytes: replay,
                                                                  rule: "replayed on entering PLUGIN mode"))
                    }
                }
            } else {
                decide(.forLocal, "now in MIX mode; never passed to the host")
            }
            return
        }
        if Self.isAlwaysLocal(group, command) {
            decide(.forLocal, "never passed to the host")
            return
        }
        switch knobMode {
        case .plugin:
            if Self.passesToHostInPluginMode(group, command) {
                decide(.toHost, "PLUGIN mode")
            } else {
                decide(.forLocal, "PLUGIN mode, not a message for the host")
            }
        case .mix:
            if Self.passesToHostInMixMode(group, command) {
                decide(.toHost, "REQUEST TRANSPORT STATUS: transport switches active")
            } else {
                decide(.forLocal, "MIX mode")
            }
        }
    }

    private func routeDeviceCC(_ bytes: [UInt8], channel: UInt8, controller: UInt8) -> RotoRelayDecision {
        switch knobMode {
        case .plugin:
            if Self.isPluginModeDeviceCC(channel: channel, controller: controller) {
                return RotoRelayDecision(source: .device, route: .toHost, bytes: bytes, rule: "PLUGIN mode")
            }
            return RotoRelayDecision(source: .device, route: .forLocal, bytes: bytes, rule: "PLUGIN mode, not a control for the host")
        case .mix:
            if transportSwitchesActive, Self.isDeviceTransportCC(channel: channel, controller: controller) {
                return RotoRelayDecision(source: .device, route: .toHost, bytes: bytes, rule: "MIX mode, transport switches active")
            }
            return RotoRelayDecision(source: .device, route: .forLocal, bytes: bytes, rule: "MIX mode")
        }
    }

    // MARK: From the host

    /// Whether a SysEx message from the host is swallowed in every mode: DAW STARTED (`0A 01`),
    /// which would start the device's handshake again, DAW PING RESPONSE (`0A 03`), and REQUEST
    /// ROTO FW VERSION (`0A 0D`), which the relay answers itself if it knows the version.
    static func isSwallowedFromHost(_ group: UInt8, _ command: UInt8) -> Bool {
        group == 0x0A && (command == 0x01 || command == 0x03 || command == 0x0D)
    }

    /// Whether a SysEx message from the host goes to the device in MIX mode while the transport
    /// switches are active: only TRANSPORT STATUS (`0A 0B`).
    static func passesToDeviceWithTransportInMixMode(_ group: UInt8, _ command: UInt8) -> Bool {
        group == 0x0A && command == 0x0B
    }

    /// Takes bytes from the host and returns what to do with the messages they complete.
    public mutating func fromHost<S: Sequence>(_ bytes: S) -> RotoRelayOutput where S.Element == UInt8 {
        var output = RotoRelayOutput()
        for message in hostParser.feed(bytes) {
            switch message {
            case .sysEx(let sysEx):
                routeHostSysEx(sysEx, into: &output)
            case .controlChange(let channel, let controller, let value):
                let cc: [UInt8] = [0xB0 | (channel & 0x0F), controller, value]
                output.decisions.append(routeHostChannelMessage(
                    cc, isTransportLight: Self.isHostTransportCC(channel: channel, controller: controller)))
            case .other(let other):
                output.decisions.append(routeHostChannelMessage(other, isTransportLight: false))
            }
        }
        return output
    }

    private mutating func routeHostSysEx(_ bytes: [UInt8], into output: inout RotoRelayOutput) {
        func decide(_ route: RotoRelayDecision.Route, _ rule: String) {
            output.decisions.append(RotoRelayDecision(source: .host, route: route, bytes: bytes, rule: rule))
        }
        guard let (group, command, _) = RotoSysEx.unframe(bytes) else {
            // SysEx that is not the Roto-Control's follows the mode, like everything else.
            decide(knobMode == .plugin ? .toDevice : .dropped, knobMode == .plugin ? "PLUGIN mode" : "MIX mode")
            return
        }
        if Self.isSwallowedFromHost(group, command) {
            if command == 0x0D, let reply = firmwareVersionReply {
                decide(.dropped, "REQUEST ROTO FW VERSION: answered by the relay")
                output.decisions.append(RotoRelayDecision(source: .relay, route: .toHost, bytes: reply,
                                                          rule: "ROTO FW VERSION, as the device last sent it"))
            } else if command == 0x0D {
                decide(.dropped, "REQUEST ROTO FW VERSION: no version known")
            } else {
                decide(.dropped, command == 0x01 ? "DAW STARTED: never passed to the device"
                                                 : "DAW PING RESPONSE: never passed to the device")
            }
            return
        }
        remember(bytes, group: group, command: command)
        switch knobMode {
        case .plugin:
            decide(.toDevice, "PLUGIN mode")
        case .mix:
            if transportSwitchesActive, Self.passesToDeviceWithTransportInMixMode(group, command) {
                decide(.toDevice, "MIX mode, transport switches active")
            } else {
                decide(.dropped, "MIX mode")
            }
        }
    }

    private func routeHostChannelMessage(_ bytes: [UInt8], isTransportLight: Bool) -> RotoRelayDecision {
        switch knobMode {
        case .plugin:
            return RotoRelayDecision(source: .host, route: .toDevice, bytes: bytes, rule: "PLUGIN mode")
        case .mix:
            if transportSwitchesActive, isTransportLight {
                return RotoRelayDecision(source: .host, route: .toDevice, bytes: bytes, rule: "MIX mode, transport switches active")
            }
            return RotoRelayDecision(source: .host, route: .dropped, bytes: bytes, rule: "MIX mode")
        }
    }
}
