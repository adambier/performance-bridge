import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// Which channels a surface's strips walk through.
public enum ViewKind: Hashable, Codable, Sendable {
    /// Inputs and playbacks: the channels whose levels go into submixes.
    case sources
    /// Outputs: their own faders, monitoring outputs first, then sends.
    case outputs
}

/// The order of the channels, as chosen in the app. TotalMix FX cannot reorder its channels; this can,
/// in any order (playbacks among inputs, for example). Channels hidden from this OSC remote in
/// TotalMix FX are not in the mirror, so they are not here either. Hiding is done only in TotalMix FX, per
/// OSC controller; the app has no setting of its own for it (Adam, 2026-10-31).
///
/// For each view, the strips show:
/// 1. the channels in the chosen order, in that order;
/// 2. then any other channel, in TotalMix FX's order: one not yet placed, such as a channel just
///    unhidden in TotalMix FX or one of a different interface, so that none goes missing.
///
/// In the outputs view the assigned monitoring outputs always come before the sends; the chosen
/// order applies within each group. With no chosen order, the monitoring outputs follow the order
/// of `MonitoringRole` (Main Out, Main Out B, Phones 1–4, cue).
public struct PerformanceLayout: Hashable, Codable, Sendable {
    /// The sources (inputs and playbacks), in the order chosen; empty for TotalMix FX's order.
    public var sourceOrder: [ChannelRef]
    /// The outputs, in the order chosen; empty for TotalMix FX's order.
    public var outputOrder: [ChannelRef]
    /// Whether the first playback in the sources view starts a new page, with blank strips after
    /// the inputs before it (Adam, 2026-10-30). Off by default.
    public var playbacksOnNewPage: Bool
    /// Labels chosen in the app for the hardware controllers, by channel; a channel without one shows
    /// TotalMix FX's name (or "Pb 1/2" for a playback). An exception to "configure it only in TotalMix FX"
    /// (AGENTS.md section 4; Adam, 2026-11-01): TotalMix FX's names serve TotalMix FX, while a hardware
    /// controller's labels serve quick mixing on a small screen, and TotalMix FX's default playback
    /// names repeat its inputs' hardware names (test 15).
    public var labels: [ChannelRef: String]

    /// A layout; the default shows every channel in TotalMix FX's order, under TotalMix FX's names.
    public init(sourceOrder: [ChannelRef] = [], outputOrder: [ChannelRef] = [],
                playbacksOnNewPage: Bool = false, labels: [ChannelRef: String] = [:]) {
        self.sourceOrder = sourceOrder
        self.outputOrder = outputOrder
        self.playbacksOnNewPage = playbacksOnNewPage
        self.labels = labels
    }

    private enum CodingKeys: String, CodingKey {
        case sourceOrder, outputOrder, playbacksOnNewPage, labels
    }

    /// Reads a saved layout; a missing field is empty, so layouts saved by older versions still load.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sourceOrder = try container.decodeIfPresent([ChannelRef].self, forKey: .sourceOrder) ?? []
        outputOrder = try container.decodeIfPresent([ChannelRef].self, forKey: .outputOrder) ?? []
        playbacksOnNewPage = try container.decodeIfPresent(Bool.self, forKey: .playbacksOnNewPage) ?? false
        labels = try container.decodeIfPresent([ChannelRef: String].self, forKey: .labels) ?? [:]
    }

    /// The label chosen for `ref`, if any.
    public func label(for ref: ChannelRef) -> String? {
        labels[ref]
    }

    /// This layout with `ref`'s label set to `text`, trimmed; an empty or `nil` text removes the
    /// label, so the channel shows TotalMix FX's name again.
    public func withLabel(_ text: String?, for ref: ChannelRef) -> PerformanceLayout {
        var layout = self
        let trimmed = text?.trimmingCharacters(in: .whitespacesAndNewlines) ?? ""
        layout.labels[ref] = trimmed.isEmpty ? nil : trimmed
        return layout
    }

    /// The strips of a view on a surface with pages of `pageSize` strips: the view's channels, with
    /// `nil` for a blank strip. Blank strips come only from `playbacksOnNewPage`: they fill the rest
    /// of the page before the first playback in the sources view, when anything comes before it.
    public func strips(_ view: ViewKind, in mirror: MixerMirror, pageSize: Int) -> [ChannelRef?] {
        let channels: [ChannelRef?] = self.channels(view, in: mirror)
        guard view == .sources, playbacksOnNewPage, pageSize > 1,
              let first = channels.firstIndex(where: { $0?.bus == .playback }), first % pageSize != 0 else {
            return channels
        }
        let blanks = pageSize - first % pageSize
        return Array(channels[..<first]) + Array(repeating: nil, count: blanks) + Array(channels[first...])
    }

    /// This layout with a view's order replaced by `refs`, as the layout editor produces it when a
    /// channel is moved. Channels not in `refs` keep TotalMix FX's order after them.
    public func withOrder(_ view: ViewKind, _ refs: [ChannelRef]) -> PerformanceLayout {
        var layout = self
        switch view {
        case .sources: layout.sourceOrder = refs
        case .outputs: layout.outputOrder = refs
        }
        return layout
    }

    /// This layout with some of a view's channels reordered: `shown`, in their new order, take the
    /// places they had among `all` (the whole view, in its current order), and every other channel
    /// keeps its place. The layout editor uses it where it lists only part of a view (e.g., only the
    /// send targets among the outputs; UI review of 2026-11-02), so the order it saves still matches
    /// TotalMix FX's whenever the listed channels do.
    public func withOrder(_ view: ViewKind, _ shown: [ChannelRef], among all: [ChannelRef]) -> PerformanceLayout {
        let listed = Set(shown)
        var reordered = shown.makeIterator()
        return withOrder(view, all.map { listed.contains($0) ? (reordered.next() ?? $0) : $0 })
    }

    /// Whether a view shows its channels in TotalMix FX's own order, as it would with no order set
    /// (e.g., after Restore TotalMix FX Order, or with an order that puts them back where TotalMix FX
    /// has them).
    public func isTotalMixOrder(_ view: ViewKind, in mirror: MixerMirror) -> Bool {
        channels(view, in: mirror) == withOrder(view, []).channels(view, in: mirror)
    }

    /// The channels of a view, as the surfaces show them (see the type's description).
    public func channels(_ view: ViewKind, in mirror: MixerMirror) -> [ChannelRef] {
        orderedChannels(view, in: mirror)
    }

    /// The channels of a view in order.
    private func orderedChannels(_ view: ViewKind, in mirror: MixerMirror) -> [ChannelRef] {
        switch view {
        case .sources:
            let available = mirror.visibleChannels(.input) + mirror.visibleChannels(.playback)
            return arrange(available, sourceOrder)
        case .outputs:
            let available = mirror.visibleChannels(.output)
            var monitoring: [ChannelRef] = []
            for role in MonitoringRole.allCases {
                guard let output = mirror.monitoring[role] else { continue }
                let ref = ChannelRef(.output, output)
                if available.contains(ref) && !monitoring.contains(ref) { monitoring.append(ref) }
            }
            let arranged = arrange(available, outputOrder)
            if outputOrder.isEmpty {
                return monitoring + arranged.filter { !monitoring.contains($0) }
            }
            return arranged.filter { monitoring.contains($0) } + arranged.filter { !monitoring.contains($0) }
        }
    }

    /// The channels of a view that the chosen order does not place yet (new to the layout), in
    /// TotalMix FX's order, for the app to point out. Channels TotalMix FX hides are not in the mirror.
    public func unplaced(_ view: ViewKind, in mirror: MixerMirror) -> [ChannelRef] {
        let order = view == .sources ? sourceOrder : outputOrder
        guard !order.isEmpty else { return [] }
        let available = view == .sources
            ? mirror.visibleChannels(.input) + mirror.visibleChannels(.playback)
            : mirror.visibleChannels(.output)
        return available.filter { !order.contains($0) }
    }

    /// The chosen order's available channels, then the rest in TotalMix FX's order.
    private func arrange(_ available: [ChannelRef], _ order: [ChannelRef]) -> [ChannelRef] {
        let availableSet = Set(available)
        var seen: Set<ChannelRef> = []
        var result: [ChannelRef] = []
        for ref in order where availableSet.contains(ref) && seen.insert(ref).inserted {
            result.append(ref)
        }
        for ref in available where !seen.contains(ref) {
            result.append(ref)
        }
        return result
    }
}
