import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// What the core knows about one TotalMix channel.
public struct ChannelState: Equatable, Sendable {
    /// The channel's name, as TotalMix sends it (`name`).
    public var name: String?
    /// TotalMix's color index (`color`): 0 for a hidden channel, 1 and up for a color (RME's
    /// document). That 0 means hidden from this OSC remote is an inference (docs/TOTALMIX-OSC.md).
    public var color: Int?
    /// Whether the channel is the left half of a stereo pair (`stereo`).
    public var stereo = false
    /// The channel's mute.
    public var mute = false
    /// The channel's PFL.
    public var pfl = false
    /// An output's own fader position (0…1); `nil` for inputs and playbacks, whose level is a node.
    public var level: Double?
    /// An output's own pan (−1…+1); `nil` for inputs and playbacks.
    public var pan: Double?

    /// An empty state.
    public init() {}

    /// Whether TotalMix hides the channel from this OSC remote (color index 0).
    public var isHidden: Bool { color == 0 }
}

/// A mixer node: the send from an input or playback channel into an output's submix.
public struct NodeKey: Hashable, Sendable {
    /// The input or playback channel.
    public var source: ChannelRef
    /// The output channel whose submix the node feeds (0-based, the left channel of a pair).
    public var output: Int

    /// The node from `source` into `output`'s submix.
    public init(_ source: ChannelRef, _ output: Int) {
        self.source = source
        self.output = output
    }
}

/// What the core knows about one mixer node.
public struct NodeState: Equatable, Sendable {
    /// The node's fader position (0…1); 0 is off.
    public var level: Double?
    /// The node's pan (−1…+1).
    public var pan: Double?
    /// The node's solo.
    public var solo = false

    /// An empty state.
    public init() {}
}

/// What changed in the mirror after a message from TotalMix or a local change.
public enum MirrorChange: Hashable, Sendable {
    /// A channel's settings (name, color, stereo, mute, PFL, or an output's level or pan).
    case channel(ChannelRef)
    /// A mixer node's level, pan, or solo.
    case node(NodeKey)
    /// A peak level, for one channel number (a stereo pair's halves are separate).
    case meter(ChannelRef)
    /// The control room's Main Out assignment.
    case mainOut
}

/// The core's copy of TotalMix's state, filled by `/sendall` and kept current by what TotalMix
/// sends. TotalMix does not echo a command to its sender (docs/TOTALMIX-OSC.md, test 5), so local
/// changes are written here too, with `set(_:to:)`.
public struct MixerMirror: Sendable {
    /// Every channel TotalMix has reported a setting for, by its left channel.
    public private(set) var channels: [ChannelRef: ChannelState] = [:]
    /// Every mixer node TotalMix has reported.
    public private(set) var nodes: [NodeKey: NodeState] = [:]
    /// The last peak level in dB of each channel number (both halves of a pair).
    public private(set) var meters: [ChannelRef: Double] = [:]
    /// The output channel assigned to Main Out in the control room (`mainout`), if any.
    public private(set) var mainOut: Int?
    private var visible: [TotalMixBus: [ChannelRef]] = [:]

    /// An empty mirror.
    public init() {}

    /// Applies one message from TotalMix and returns what changed, or `nil` if nothing the core
    /// keeps changed.
    @discardableResult
    public mutating func apply(_ event: TotalMixEvent) -> MirrorChange? {
        switch event {
        case .channel(let bus, let channel, let parameter, let value):
            return applyChannel(ChannelRef(bus, channel), parameter, value)
        case .mix(let bus, let channel, let output, let parameter, let value):
            return applyNode(NodeKey(ChannelRef(bus, channel), output), parameter, value)
        case .level(let bus, let channel, let peakDB):
            let ref = ChannelRef(bus, channel)
            if meters[ref] == peakDB { return nil }
            meters[ref] = peakDB
            return .meter(ref)
        case .other(let path, let value):
            guard path == "controlroom/mainout", let number = value.number else { return nil }
            let assigned = number < 0 ? nil : Int(number.rounded())
            if mainOut == assigned { return nil }
            mainOut = assigned
            return .mainOut
        case .snapshot:
            return nil
        }
    }

    private mutating func applyChannel(_ ref: ChannelRef, _ parameter: String, _ value: TotalMixValue) -> MirrorChange? {
        var state = channels[ref] ?? ChannelState()
        let before = state
        switch parameter {
        case "name":
            guard case .text(let text) = value else { return nil }
            state.name = text
        case "color":
            guard let number = value.number else { return nil }
            state.color = Int(number.rounded())
        case "stereo":
            guard let number = value.number else { return nil }
            state.stereo = number >= 0.5
        case "mute":
            guard let number = value.number else { return nil }
            state.mute = number >= 0.5
        case "pfl":
            guard let number = value.number else { return nil }
            state.pfl = number >= 0.5
        case "volume" where ref.bus == .output:
            guard let number = value.number else { return nil }
            state.level = FaderCurve.position(gainDB: number)
        case "faderlin" where ref.bus == .output:
            guard let number = value.number else { return nil }
            state.level = min(max(number, 0), 1)
        case "balpan" where ref.bus == .output:
            guard let number = value.number else { return nil }
            state.pan = min(max(number, -1), 1)
        default:
            return nil
        }
        store(state, for: ref)
        return state == before ? nil : .channel(ref)
    }

    private mutating func applyNode(_ key: NodeKey, _ parameter: String, _ value: TotalMixValue) -> MirrorChange? {
        guard let number = value.number else { return nil }
        var state = nodes[key] ?? NodeState()
        let before = state
        switch parameter {
        case "fader": state.level = FaderCurve.position(gainDB: number)
        case "faderlin": state.level = min(max(number, 0), 1)
        case "balpan": state.pan = min(max(number, -1), 1)
        case "solo": state.solo = number >= 0.5
        default: return nil
        }
        nodes[key] = state
        return state == before ? nil : .node(key)
    }

    /// The current value of a target: a fader position (0…1), a pan (−1…+1), or 1/0 for on/off.
    /// `nil` when TotalMix has not reported it yet.
    public func value(of target: ControlTarget) -> Double? {
        switch target {
        case .level(let ref, let submix):
            if ref.isSource {
                guard let submix else { return nil }
                return nodes[NodeKey(ref, submix)]?.level
            }
            return channels[ref]?.level
        case .pan(let ref, let submix):
            if ref.isSource {
                guard let submix else { return nil }
                return nodes[NodeKey(ref, submix)]?.pan
            }
            return channels[ref]?.pan
        case .mute(let ref):
            return channels[ref].map { $0.mute ? 1 : 0 }
        case .pfl(let ref):
            return channels[ref].map { $0.pfl ? 1 : 0 }
        case .solo(let ref, let submix):
            return nodes[NodeKey(ref, submix)].map { $0.solo ? 1 : 0 }
        }
    }

    /// Writes a local change (one the core has sent, or is about to send, to TotalMix) and returns
    /// what changed. Values are clamped to the target's range; on/off values count from 0.5.
    @discardableResult
    public mutating func set(_ target: ControlTarget, to value: Double) -> MirrorChange? {
        switch target {
        case .level(let ref, let submix):
            if ref.isSource {
                guard let submix else { return nil }
                return setNode(NodeKey(ref, submix)) { $0.level = min(max(value, 0), 1) }
            }
            return setChannel(ref) { $0.level = min(max(value, 0), 1) }
        case .pan(let ref, let submix):
            if ref.isSource {
                guard let submix else { return nil }
                return setNode(NodeKey(ref, submix)) { $0.pan = min(max(value, -1), 1) }
            }
            return setChannel(ref) { $0.pan = min(max(value, -1), 1) }
        case .mute(let ref):
            return setChannel(ref) { $0.mute = value >= 0.5 }
        case .pfl(let ref):
            return setChannel(ref) { $0.pfl = value >= 0.5 }
        case .solo(let ref, let submix):
            return setNode(NodeKey(ref, submix)) { $0.solo = value >= 0.5 }
        }
    }

    private mutating func setChannel(_ ref: ChannelRef, _ change: (inout ChannelState) -> Void) -> MirrorChange? {
        var state = channels[ref] ?? ChannelState()
        let before = state
        change(&state)
        store(state, for: ref)
        return state == before ? nil : .channel(ref)
    }

    /// Stores a channel's state, and redoes the row's list of visible channels when the channel is
    /// new or its color or stereo setting changed.
    private mutating func store(_ state: ChannelState, for ref: ChannelRef) {
        let old = channels[ref]
        channels[ref] = state
        if old == nil || old?.color != state.color || old?.stereo != state.stereo {
            visible[ref.bus] = listVisible(ref.bus)
        }
    }

    private mutating func setNode(_ key: NodeKey, _ change: (inout NodeState) -> Void) -> MirrorChange? {
        var state = nodes[key] ?? NodeState()
        let before = state
        change(&state)
        nodes[key] = state
        return state == before ? nil : .node(key)
    }

    /// The channels of one row that a surface can show, in TotalMix's order: every channel with a
    /// reported setting, minus the right halves of stereo pairs and channels hidden from this OSC
    /// remote.
    public func visibleChannels(_ bus: TotalMixBus) -> [ChannelRef] {
        visible[bus] ?? []
    }

    private func listVisible(_ bus: TotalMixBus) -> [ChannelRef] {
        let all = channels.keys.filter { $0.bus == bus }.sorted { $0.channel < $1.channel }
        var result: [ChannelRef] = []
        var skip: Set<Int> = []
        for ref in all {
            if skip.contains(ref.channel) { continue }
            let state = channels[ref] ?? ChannelState()
            if state.stereo { skip.insert(ref.channel + 1) }
            if state.isHidden { continue }
            result.append(ref)
        }
        return result
    }
}
