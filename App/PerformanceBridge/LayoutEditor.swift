// The layout editor: the order of the sources and outputs on the surfaces, and which channels the
// app takes off them. Channels hidden from this OSC remote in TotalMix are not listed, since the
// app cannot see them.

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
                    Toggle(item.name, isOn: Binding(
                        get: { !item.hidden },
                        set: { shown in
                            model.engine.setLayout(model.engine.layout.settingHidden(item.channel, !shown))
                        }))
                }
                .onMove { source, destination in
                    items.move(fromOffsets: source, toOffset: destination)
                    model.engine.setLayout(model.engine.layout.withOrder(view, items.map(\.channel)))
                }
            }
            .frame(minHeight: 260)

            VStack(alignment: .leading, spacing: 6) {
                Text(view == .outputs
                     ? "Monitoring outputs (Main Out, Phones, and so on) always come first. Drag to order the sends."
                     : "Drag to change the order. TotalMix can't reorder its channels; this can.")
                Text("Channels hidden from OSC in TotalMix are not shown here or on any surface. To show one, right-click the channel in TotalMix FX, choose Change Channel Layout, and clear the OSC Controller box that Performance Bridge uses under \u{201C}Hide Channel in.\u{201D}")
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .frame(width: 380, height: 460)
        .onAppear { reload() }
        .onChange(of: model.status) { _ in reload() }
    }

    /// Reads the view's channels again, after a change in the app or in TotalMix.
    private func reload() {
        items = model.engine.layoutItems(view)
    }
}
