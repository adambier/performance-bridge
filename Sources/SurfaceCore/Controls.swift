import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// One TotalMix channel as a strip sees it: a row (input, playback, or output) and the 0-based
/// channel number. A stereo pair is named by its left channel, as Global OSC addresses it.
public struct ChannelRef: Hashable, Codable, Sendable, CustomStringConvertible {
    /// The row: input, playback, or output.
    public var bus: TotalMixBus
    /// The 0-based channel number (the left channel of a stereo pair).
    public var channel: Int

    /// A channel in a row.
    public init(_ bus: TotalMixBus, _ channel: Int) {
        self.bus = bus
        self.channel = channel
    }

    /// Whether this is an input or a playback, whose level is a mixer node into a submix.
    public var isSource: Bool { bus != .output }

    public var description: String { "\(bus.settingsName) \(channel + 1)" }
}

/// What a knob (or other continuous control) controls on a strip.
public enum KnobFunction: Hashable, Codable, Sendable {
    /// The channel's level: a source's node into the home submix, or an output's own fader.
    case level
    /// The channel's pan: a source's node pan in the home submix, or an output's own pan.
    case pan
    /// A source's level into the submix of the n-th send target (0-based), that is, of the n-th
    /// output other than the home submix. Outputs have no sends.
    case send(Int)
}

/// What a switch controls on a strip.
public enum SwitchFunction: Hashable, Codable, Sendable {
    /// The channel's mute (`/<bus>/<channel>/mute`), which mutes it in every submix.
    case mute
    /// The channel's PFL (`/<bus>/<channel>/pfl`): pre-listening on the control room's phones.
    case pfl
    /// A source's solo in the home submix (the mixer node's `solo`). Off by default
    /// (`SurfaceHub.soloEnabled`): what TotalMix's solo does to the rest of the submix is unchecked,
    /// and in live use it could silence the audience's mix.
    case solo
    /// Nothing: the switch does nothing and shows off.
    case none
}

/// One value in TotalMix that a control can be bound to.
public enum ControlTarget: Hashable, Sendable {
    /// A channel's level; for a source, its node into the given submix (an output channel).
    case level(ChannelRef, submix: Int?)
    /// A channel's pan; for a source, its node's pan in the given submix.
    case pan(ChannelRef, submix: Int?)
    /// A channel's mute.
    case mute(ChannelRef)
    /// A channel's PFL.
    case pfl(ChannelRef)
    /// A source's solo in a submix.
    case solo(ChannelRef, submix: Int)

    /// The channel the target belongs to.
    public var channel: ChannelRef {
        switch self {
        case .level(let ref, _), .pan(let ref, _), .mute(let ref), .pfl(let ref), .solo(let ref, _):
            return ref
        }
    }

    /// Whether the target is an on/off value (a switch) rather than a continuous one.
    public var isSwitch: Bool {
        switch self {
        case .mute, .pfl, .solo: return true
        case .level, .pan: return false
        }
    }
}
