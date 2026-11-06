// The outputs a Launch Control layout's send rows feed, as chosen with Page on the device or in the
// app: SurfaceCore's `SendRows`, shaped by the layout.

import Foundation
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif

/// The outputs a layout's send rows feed, by output channel (0-based): XL 3, two rows, top first;
/// Launch Control 3, one row, the top row, where `nil` means pan. On the XL 3 `nil` means "the
/// first send target the other row isn't using". The rules are `SendRows`'.
public struct LaunchControlSendRows: Equatable, Sendable {
    /// The layout the rows belong to.
    public let layout: LaunchControlModel
    private var rows: SendRows
    /// Each row's chosen output.
    public var choices: [Int?] { rows.choices }

    /// The rows for `layout`, from saved choices; missing rows are `nil` and extra ones dropped.
    public init(layout: LaunchControlModel, choices: [Int?] = []) {
        self.layout = layout
        rows = SendRows(rowCount: Self.rowCount(layout), fillsEmptyRows: layout == .xl3, choices: choices)
    }

    /// How many send rows a layout has: 2 on the XL 3, 1 on the Launch Control 3.
    public static func rowCount(_ layout: LaunchControlModel) -> Int { layout == .xl3 ? 2 : 1 }

    /// The send target (an index into `targets`) each row uses now (`SendRows.indices(targets:)`);
    /// on the Launch Control 3, pan (`nil`) if its choice isn't a target.
    public func indices(targets: [Int]) -> [Int?] { rows.indices(targets: targets) }

    /// The output each row feeds now; `nil` for pan on the Launch Control 3, or for an XL 3 row
    /// with no output left.
    public func outputs(targets: [Int]) -> [Int?] { rows.outputs(targets: targets) }

    /// Sets a row's output, as Page does on the device (`SendRows.set(row:to:targets:)`); `nil`
    /// (pan) is refused on the XL 3.
    @discardableResult
    public mutating func set(row: Int, to output: Int?, targets: [Int]) -> Bool {
        rows.set(row: row, to: output, targets: targets)
    }

    /// The outputs a row can be set to: every target except those the other rows feed now.
    public func available(row: Int, targets: [Int]) -> [Int] { rows.available(row: row, targets: targets) }
}
