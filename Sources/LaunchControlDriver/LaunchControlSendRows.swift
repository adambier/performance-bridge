// The outputs a Launch Control layout's send rows feed, as chosen with Page on the device or in the
// app. Kept apart from the driver so the engine can hold them while no device is connected
// (Adam, 2026-11-02, from the review of that date).

import Foundation
#if canImport(LaunchControl)
import LaunchControl
#endif

/// The outputs a layout's send rows feed, by output channel (0-based): XL 3, two rows, top first;
/// Launch Control 3, one row, the top row, where `nil` means pan. On the XL 3 `nil` means "the
/// first send target the other row isn't using". A choice that isn't a send target now (e.g.,
/// hidden in TotalMix) is kept, and the row uses another until it comes back.
public struct LaunchControlSendRows: Equatable, Sendable {
    /// The layout the rows belong to.
    public let layout: LaunchControlModel
    /// Each row's chosen output.
    public private(set) var choices: [Int?]

    /// The rows for `layout`, from saved choices; missing rows are `nil` and extra ones dropped.
    public init(layout: LaunchControlModel, choices: [Int?] = []) {
        self.layout = layout
        let rows = Self.rowCount(layout)
        self.choices = (0..<rows).map { choices.indices.contains($0) ? choices[$0] : nil }
    }

    /// How many send rows a layout has: 2 on the XL 3, 1 on the Launch Control 3.
    public static func rowCount(_ layout: LaunchControlModel) -> Int { layout == .xl3 ? 2 : 1 }

    /// The send target (an index into `targets`) each row uses now: a row's chosen output if it is
    /// a target and no earlier row has it; else (XL 3) the first target no row uses; on the Launch
    /// Control 3, pan (`nil`) if its choice isn't a target. Each row's own choice is placed first,
    /// so a row whose output has gone never takes the other row's (review of 2026-11-02).
    public func indices(targets: [Int]) -> [Int?] {
        var indices: [Int?] = choices.map { $0.flatMap { targets.firstIndex(of: $0) } }
        var used = Set<Int>()
        for row in indices.indices {
            if let index = indices[row], !used.insert(index).inserted { indices[row] = nil }
        }
        if layout == .xl3 {
            for row in indices.indices where indices[row] == nil {
                indices[row] = targets.indices.first { !used.contains($0) }
                if let index = indices[row] { used.insert(index) }
            }
        }
        return indices
    }

    /// The output each row feeds now (`indices(targets:)` as outputs); `nil` for pan on the Launch
    /// Control 3, or for an XL 3 row with no output left.
    public func outputs(targets: [Int]) -> [Int?] {
        indices(targets: targets).map { $0.map { targets[$0] } }
    }

    /// Sets a row's output, as Page does on the device: the other rows keep the outputs they feed
    /// now (an XL 3 row left to choose for itself would otherwise take the freed output). Refuses,
    /// returning `false`, an output that isn't a target, one another row feeds, and `nil` (pan) on
    /// the XL 3.
    @discardableResult
    public mutating func set(row: Int, to output: Int?, targets: [Int]) -> Bool {
        guard choices.indices.contains(row) else { return false }
        let current = indices(targets: targets)
        let index = output.flatMap { targets.firstIndex(of: $0) }
        if output != nil && index == nil { return false }
        if output == nil && layout == .xl3 { return false }
        let others = Set(current.enumerated().filter { $0.offset != row }.compactMap(\.element))
        if let index, others.contains(index) { return false }
        for (other, resolved) in current.enumerated() where layout == .xl3 && other != row && choices[other] == nil {
            choices[other] = resolved.map { targets[$0] }
        }
        choices[row] = output
        return true
    }

    /// The outputs a row can be set to: every target except those the other rows feed now, in
    /// target order.
    public func available(row: Int, targets: [Int]) -> [Int] {
        let current = outputs(targets: targets)
        let others = Set(current.enumerated().filter { $0.offset != row }.compactMap(\.element))
        return targets.filter { !others.contains($0) }
    }
}
