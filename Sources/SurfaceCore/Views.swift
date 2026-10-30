import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// Which channels a surface's strips walk through.
public enum ViewKind: Hashable, Codable, Sendable {
    /// Inputs, then playbacks: the channels whose levels go into submixes.
    case sources
    /// Outputs: their own faders, monitoring outputs first, then sends.
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
    /// reverse). With no list, the outputs view puts the monitoring outputs first, in the order of
    /// `MonitoringRole` (Main Out, Main Out B, Phones 1–4, cue), and then the sends in TotalMix's
    /// order.
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
            let visible = mirror.visibleChannels(.output)
            var monitoring: [ChannelRef] = []
            for role in MonitoringRole.allCases {
                guard let output = mirror.monitoring[role] else { continue }
                let ref = ChannelRef(.output, output)
                if visible.contains(ref) && !monitoring.contains(ref) { monitoring.append(ref) }
            }
            return monitoring + visible.filter { !monitoring.contains($0) }
        }
    }
}
