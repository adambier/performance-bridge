// The Controls Guide window: what each control of the chosen hardware controller does (Adam,
// 2026-11-02), for looking up during use, once the Setup Guide has nothing left to show. The text
// is ControlsGuide's (BridgeEngine), which docs/SETUP.md, Step 6, matches.

import SwiftUI
#if canImport(BridgeEngine)
import BridgeEngine
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif

/// The Controls Guide for the hardware controller the engine runs with: the common rules, then its
/// tables and notes. It follows a change of controller while open.
struct ControlsGuideView: View {
    @ObservedObject var model: BridgeModel

    /// The hardware controller in use: a Launch Control's layout (the Launch Control 3's when it
    /// is simulated on an XL 3), or the Roto-Control.
    private var controller: DetectedController {
        model.engine.settings.launchControl.map { .launchControl($0.layout) } ?? .roto
    }

    var body: some View {
        let guide = ControlsGuide.guide(for: controller)
        ScrollView(.vertical) {
            VStack(alignment: .leading, spacing: 14) {
                Text(guide.title)
                    .font(.title2.weight(.semibold))
                ForEach(ControlsGuide.common + guide.introduction, id: \.self) { paragraph($0) }
                ForEach(guide.tables.indices, id: \.self) { table(guide.tables[$0]) }
                if !guide.notes.isEmpty {
                    Text("Notes")
                        .font(.headline)
                        .padding(.top, 4)
                    VStack(alignment: .leading, spacing: 12) {
                        ForEach(guide.notes, id: \.self) { note in
                            HStack(alignment: .firstTextBaseline, spacing: 6) {
                                Text("•").foregroundStyle(.secondary)
                                paragraph(note)
                            }
                        }
                    }
                }
            }
            .padding(20)
            .frame(width: 600, alignment: .leading)
        }
        .frame(height: min((NSScreen.main?.visibleFrame.height ?? 800) - 120, 720))
    }

    /// A paragraph, with Markdown's **bold** shown as bold.
    private func paragraph(_ text: String) -> some View {
        Text(.init(text))
            .fixedSize(horizontal: false, vertical: true)
            .textSelection(.enabled)
    }

    /// A table of controls: a heading row, then one row per control, the controls in a column of
    /// their own.
    private func table(_ table: ControlsGuide.Table) -> some View {
        Grid(alignment: .topLeading, horizontalSpacing: 14, verticalSpacing: 14) {
            GridRow {
                Text(table.controlHeading).font(.callout.weight(.semibold))
                Text(table.actionHeading).font(.callout.weight(.semibold))
            }
            .foregroundStyle(.secondary)
            Divider().gridCellUnsizedAxes(.horizontal)
            ForEach(table.rows.indices, id: \.self) { index in
                let row = table.rows[index]
                GridRow {
                    paragraph(row.control)
                        .frame(width: 170, alignment: .leading)
                    paragraph(row.action)
                }
            }
        }
        .padding(12)
        .background(RoundedRectangle(cornerRadius: 8).fill(Color.secondary.opacity(0.08)))
    }
}
