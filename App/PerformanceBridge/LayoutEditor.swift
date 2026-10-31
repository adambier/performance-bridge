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
                ForEach(items, id: \.channel) { item in
                    Text(item.name)
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                    model.engine.setLayout(model.engine.layout.withOrder(view, items.map(\.channel)))
                }
            }
            .frame(minHeight: 260)

            if view == .sources {
                Toggle("Playbacks start on a new page", isOn: Binding(
                    get: { playbacksOnNewPage },
                    set: { on in
                        playbacksOnNewPage = on
                        model.engine.setPlaybacksOnNewPage(on)
                    }))
            }

            VStack(alignment: .leading, spacing: 6) {
                Text(view == .outputs
                     ? "Monitoring outputs (Main Out, Phones, and so on) always come first. Drag to order the sends."
                     : "Drag to change the order. TotalMix can't reorder its channels; this can.")
                Text("Channel colors are set in TotalMix FX, in Channel Layout. Channels are hidden there too: right-click the channel, choose Change Channel Layout, and check the OSC Controller box under \u{201C}Hide Channel in.\u{201D} Channels that TotalMix hides from an OSC Controller are not shown on any surface that uses that controller.")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380, height: 490)
        .onAppear { reload() }
        .onChange(of: model.status) { _ in reload() }
    }

    /// Reads the view's channels again, after a change in the app or in TotalMix.
    private func reload() {
        items = model.engine.layoutItems(view)
    }
}
