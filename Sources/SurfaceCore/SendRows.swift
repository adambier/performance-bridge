// The outputs a surface's send rows feed, chosen on the device or in the app: the Launch Control
// XL 3's two send rows, the Launch Control 3's top row, and the E16's send A and B rows in its
// 4-channel layout. Kept apart from the drivers so the engine can hold the choices while no
// device is connected (Adam, 2026-11-02, from the review of that date).

import Foundation

/// The outputs a surface's send rows feed, by output channel (0-based). Two rows never feed the
/// same output. With `fillsEmptyRows`, a row whose choice is `nil` takes the first send target no
/// other row uses; without it, `nil` means the row isn't a send (the Launch Control 3's top row as
/// pan). A choice that isn't a send target now (e.g., hidden in TotalMix FX) is kept, and the row
/// uses another until it comes back.
public struct SendRows: Equatable, Sendable {
    /// Whether a row without a choice takes the first free send target (else it is no send).
    public let fillsEmptyRows: Bool
    /// Each row's chosen output.
    public private(set) var choices: [Int?]

    /// `rowCount` rows from saved choices; missing rows are `nil` and extra ones dropped.
    public init(rowCount: Int, fillsEmptyRows: Bool, choices: [Int?] = []) {
        self.fillsEmptyRows = fillsEmptyRows
        self.choices = (0..<max(rowCount, 0)).map { choices.indices.contains($0) ? choices[$0] : nil }
    }

    /// The send target (an index into `targets`) each row uses now: a row's chosen output if it is
    /// a target and no earlier row has it; else, with `fillsEmptyRows`, the first target no row
    /// uses, and without it `nil`. Each row's own choice is placed first, so a row whose output
    /// has gone never takes another row's (review of 2026-11-02).
    public func indices(targets: [Int]) -> [Int?] {
        var indices: [Int?] = choices.map { $0.flatMap { targets.firstIndex(of: $0) } }
        var used = Set<Int>()
        for row in indices.indices {
            if let index = indices[row], !used.insert(index).inserted { indices[row] = nil }
        }
        if fillsEmptyRows {
            for row in indices.indices where indices[row] == nil {
                indices[row] = targets.indices.first { !used.contains($0) }
                if let index = indices[row] { used.insert(index) }
            }
        }
        return indices
    }

    /// The output each row feeds now (`indices(targets:)` as outputs); `nil` for no send.
    public func outputs(targets: [Int]) -> [Int?] {
        indices(targets: targets).map { $0.map { targets[$0] } }
    }

    /// Sets a row's output: the other rows keep the outputs they feed now (a row left to choose
    /// for itself would otherwise take the freed output). Refuses, returning `false`, an output
    /// that isn't a target, one another row feeds, and `nil` with `fillsEmptyRows`.
    @discardableResult
    public mutating func set(row: Int, to output: Int?, targets: [Int]) -> Bool {
        guard choices.indices.contains(row) else { return false }
        let current = indices(targets: targets)
        let index = output.flatMap { targets.firstIndex(of: $0) }
        if output != nil && index == nil { return false }
        if output == nil && fillsEmptyRows { return false }
        let others = Set(current.enumerated().filter { $0.offset != row }.compactMap(\.element))
        if let index, others.contains(index) { return false }
        for (other, resolved) in current.enumerated() where fillsEmptyRows && other != row && choices[other] == nil {
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
