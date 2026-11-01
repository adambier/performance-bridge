// The layout editor: the order of the sources and outputs on the surfaces. Channels are hidden only
// in TotalMix FX, per OSC controller, so the editor has no hide setting. Channels hidden from this
// OSC remote in TotalMix are not listed, since the app cannot see them.

import SwiftUI
#if canImport(SurfaceCore)
import SurfaceCore
#endif
#if canImport(BridgeEngine)
import BridgeEngine
#endif

/// The layout editor window. Changes take effect on the surfaces at once.
struct LayoutView: View {
    @ObservedObject var model: BridgeModel
    @State private var view: ViewKind = .sources
    @State private var items: [LayoutItem] = []
    @AppStorage("playbacksOnNewPage") private var playbacksOnNewPage = false

    /// The monitoring outputs (Main Out, Phones, and so on), which always come first in the
    /// outputs view; they are ordered among themselves, and the sends among themselves.
    private var monitoring: Set<Int> { Set(model.status.monitoringOutputs.map(\.output)) }
    private var monitoringItems: [LayoutItem] {
        view == .outputs ? items.filter { monitoring.contains($0.channel.channel) } : []
    }
    private var otherItems: [LayoutItem] {
        view == .outputs ? items.filter { !monitoring.contains($0.channel.channel) } : items
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $view) {
                Text("Sources").tag(ViewKind.sources)
                Text("Outputs").tag(ViewKind.outputs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: view) { _ in reload() }

            List {
                if view == .outputs {
                    // Two sections, each reordered on its own, so a monitoring output can't be
                    // dragged among the sends (Adam, 2026-10-31).
                    // "Control Room", as TotalMix FX calls the section these outputs are assigned in
                    // (Adam, 2026-10-31). Two titled sections are clear enough without brackets or
                    // colors (Adam).
                    Section("Control Room") {
                        rows(monitoringItems)
                            .onMove { move($0, $1, monitoring: true) }
                    }
                    Section("Sends") {
                        rows(otherItems)
                            .onMove { move($0, $1, monitoring: false) }
                    }
                } else {
                    rows(otherItems)
                        .onMove { move($0, $1, monitoring: false) }
                }
            }
            .frame(minHeight: 260)

            HStack {
                if view == .sources {
                    Toggle("Playbacks start on a new page", isOn: Binding(
                        get: { playbacksOnNewPage },
                        set: { on in
                            playbacksOnNewPage = on
                            model.engine.setPlaybacksOnNewPage(on)
                        }))
                }
                Spacer()
                Button("Restore TotalMix FX Order") {
                    // An empty order is TotalMix's own (PerformanceLayout.withOrder).
                    model.engine.setLayout(model.engine.layout.withOrder(view, []))
                    reload()
                }
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(view == .outputs
                     ? "Drag to change the order. Control room outputs (Main Out, Phones, and so on) always come first."
                     : "Drag to change the order.")
                Text("Channel colors are set in TotalMix FX’s own Channel Layout window, and channels are hidden there too: right-click the channel, choose Change Channel Layout, and check the OSC Controller box under \u{201C}Hide Channel in.\u{201D} Channels that TotalMix hides from an OSC Controller are not shown on any surface that uses that controller.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(height: 490)
        .onAppear { reload() }
        .onChange(of: model.status) { _ in reload() }
    }

    /// A group's rows: a drag handle and the channel's name.
    private func rows(_ group: [LayoutItem]) -> some DynamicViewContent {
        ForEach(group, id: \.channel) { item in
            HStack(spacing: 8) {
                Image(systemName: "line.3.horizontal")
                    .foregroundStyle(.tertiary)
                    .accessibilityHidden(true)
                Text(item.name)
                Spacer()
            }
            .frame(minHeight: 24)
            .listRowInsets(EdgeInsets(top: 0, leading: 8, bottom: 0, trailing: 8))
            // No lines between rows: a short one-column list grouped by section titles reads better
            // without them (Apple's HIG keeps row lines and alternating backgrounds for large or
            // multicolumn tables).
            .listRowSeparator(.hidden)
        }
    }

    /// Moves channels within one group (all sources, the monitoring outputs, or the sends) and
    /// saves the view's order: monitoring outputs first, then the rest.
    private func move(_ source: IndexSet, _ destination: Int, monitoring isMonitoring: Bool) {
        var first = monitoringItems
        var rest = otherItems
        if isMonitoring { first.move(fromOffsets: source, toOffset: destination) }
        else { rest.move(fromOffsets: source, toOffset: destination) }
        items = first + rest
        model.engine.setLayout(model.engine.layout.withOrder(view, items.map(\.channel)))
    }

    /// Reads the view's channels again, after a change in the app or in TotalMix.
    private func reload() {
        items = model.engine.layoutItems(view)
    }
}

