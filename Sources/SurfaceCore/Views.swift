import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// Which channels a surface's strips walk through.
public enum ViewKind: Hashable, Codable, Sendable {
    /// Inputs, then playbacks: the channels whose levels go into submixes.
    case sources
    /// Outputs: the submixes' own faders.
    case outputs
}

/// The channels a performance uses, and their order, chosen in the app. A `nil` list means every
/// channel TotalMix shows this OSC remote, in TotalMix's order.
public struct PerformanceLayout: Hashable, Codable, Sendable {
    /// The sources (inputs and playbacks) on the strips, in order; `nil` for all of them.
    public var sources: [ChannelRef]?
    /// The outputs on the strips and as send targets, in order; `nil` for all of them.
    public var outputs: [ChannelRef]?

    /// A layout; the default shows every channel.
    public init(sources: [ChannelRef]? = nil, outputs: [ChannelRef]? = nil) {
        self.sources = sources
        self.outputs = outputs
    }

    /// The channels of a view, as the strips show them. A chosen list keeps its order, minus
    /// channels TotalMix hides from this OSC remote and outputs listed under sources (or the
    /// reverse).
    public func channels(_ view: ViewKind, in mirror: MixerMirror) -> [ChannelRef] {
        switch view {
        case .sources:
            if let sources {
                return sources.filter { $0.isSource && mirror.channels[$0]?.isHidden != true }
            }
            return mirror.visibleChannels(.input) + mirror.visibleChannels(.playback)
        case .outputs:
            if let outputs {
                return outputs.filter { !$0.isSource && mirror.channels[$0]?.isHidden != true }
            }
            return mirror.visibleChannels(.output)
        }
    }
}
