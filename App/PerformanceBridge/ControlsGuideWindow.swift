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

/// The Controls Guide: the common rules, then one hardware controller's tables and notes. A menu in
/// the top right chooses the controller; it starts on the one in use and follows a change of
/// controller while open (Adam, 2026-11-04).
struct ControlsGuideView: View {
    @ObservedObject var model: BridgeModel
    /// The controller the guide shows.
    @State private var shown: ControllerChoice

    /// The page's width in points, padding included.
    private static let width: CGFloat = 600

    init(model: BridgeModel) {
        self.model = model
        _shown = State(initialValue: Self.inUse(model))
    }

    /// The hardware controller the engine runs with: a Launch Control's layout (the Launch Control
    /// 3's when it is simulated on an XL 3), or the Roto-Control.
    private static func inUse(_ model: BridgeModel) -> ControllerChoice {
        switch model.engine.settings.launchControl?.layout {
        case .xl3: return .launchControlXL3
        case .lc3: return .launchControl3
        case nil: return .roto
        }
    }

    /// The controller the guide shows, as the guide's own type.
    private var controller: DetectedController {
        shown.launchControl.map { .launchControl($0) } ?? .roto
    }

    var body: some View {
        let guide = ControlsGuide.guide(for: controller)
        VStack(spacing: 0) {
            // The controller menu has a bar of its own above the guide, so it neither scrolls nor
            // overlaps anything; the title scrolls with the guide (Adam, 2026-11-04).
            HStack {
                Spacer()
                Picker("Hardware controller", selection: $shown) {
                    ForEach(ControllerChoice.allCases) { choice in
                        Text(choice.title).tag(choice)
                    }
                }
                .labelsHidden()
                .fixedSize()
                .accessibilityLabel("Hardware controller shown")
            }
            .padding(.horizontal, 20)
            .padding(.vertical, 12)
            Divider()
            ScrollViewReader { scroller in
            ScrollView(.vertical) {
                VStack(alignment: .leading, spacing: 14) {
                    Text(guide.title)
                        .font(.title2.weight(.semibold))
                        .id("top")
                    photo(guide)
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
                .frame(width: Self.width, alignment: .leading)
            }
            // A new controller starts at the top of its guide (Adam, 2026-11-04).
            .onChange(of: shown) { _ in scroller.scrollTo("top", anchor: .top) }
            }
        }
        .frame(width: Self.width, height: min((NSScreen.main?.visibleFrame.height ?? 800) - 120, 720))
        // Follow a change of controller in Settings while the window is open.
        .onChange(of: model.engine.settings.launchControl?.layout) { _ in shown = Self.inUse(model) }
    }

    /// The controller's photo, under the title, at half its pixel size (the files are Retina
    /// size, all the same height, so the three guides' photos are the same height: the
    /// Roto-Control's spans the page; Adam, 2026-11-04), with an exact height so no space is left
    /// around it.
    @ViewBuilder
    private func photo(_ guide: ControlsGuide) -> some View {
        if let image = Brand.resources.image(forResource: guide.image),
           let rep = image.representations.first, rep.pixelsWide > 0 {
            let width = min(CGFloat(rep.pixelsWide) / 2, Self.width - 40)
            Image(nsImage: image)
                .resizable()
                .interpolation(.high)
                .frame(width: width, height: width * CGFloat(rep.pixelsHigh) / CGFloat(rep.pixelsWide))
                .accessibilityLabel("Photo of the \(guide.title), seen from above")
        }
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

