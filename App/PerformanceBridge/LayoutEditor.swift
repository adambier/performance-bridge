// The layout editor: the order of the sources and outputs on the surfaces, and labels for them.
// Channels are hidden only in TotalMix FX, per OSC controller, so the editor has no hide setting.
// Channels hidden from this OSC remote in TotalMix FX are not listed, since the app cannot see them.
// Labels are the app's own, for the hardware controllers only (Adam, 2026-11-01; AGENTS.md
// section 4); a channel without one shows TotalMix FX's name. The wording here is to be checked in the
// UI review (Adam, 2026-11-01).

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
    /// Whether the view is in TotalMix FX's own order, so Restore TotalMix FX Order has nothing to do.
    @State private var isTotalMixOrder = true
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

    /// The list's height for its rows (24 points each, group titles a little more), between 120
    /// and 440 points.
    private var listHeight: CGFloat {
        let rows = view == .outputs ? monitoringItems.count + otherItems.count : otherItems.count
        let titles = view == .outputs ? 2 : 0
        return min(max(CGFloat(rows) * 28 + CGFloat(titles) * 30 + 16, 120), 440)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Picker("Show", selection: $view) {
                Text("Sources").tag(ViewKind.sources)
                Text("Outputs").tag(ViewKind.outputs)
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .onChange(of: view) { _ in
                reload()
                // The list's height changes with the view: fit the window after layout.
                DispatchQueue.main.async { Windows.fitToContent("settings") }
            }

            // Above the list, as an instruction rather than a heading (Adam, 2026-10-31).
            // The hardware controllers show only the sources; the outputs' order is the order the
            // send controls step through them (Adam, 2026-11-01).
            // One instruction for both views (Adam, 2026-11-07: the outputs' longer text, and why
            // some outputs aren't listed, were cut).
            Text("Drag to reorder. Click a name to give it a label for the hardware controllers.")
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)

            List {
                if view == .outputs {
                    // Two sections, each reordered on its own, so a monitoring output can't be
                    // dragged among the sends (Adam, 2026-10-31).
                    // "Control Room", as TotalMix FX calls the section these outputs are assigned in
                    // (Adam, 2026-10-31). Two titled sections are clear enough without brackets or
                    // colors (Adam).
                    // Group titles as plain rows rather than Section headers: macOS pins a section
                    // header on a gray bar while its list scrolls (Adam, 2026-10-31: the bar looked
                    // out of place). Each group is still reordered on its own.
                    groupTitle("Control Room")
                    rows(monitoringItems)
                        .onMove { move($0, $1, monitoring: true) }
                    groupTitle("Hardware Outputs")   // TotalMix FX's name for its other outputs (Adam, 2026-10-31)
                    rows(otherItems)
                        .onMove { move($0, $1, monitoring: false) }
                } else {
                    rows(otherItems)
                        .onMove { move($0, $1, monitoring: false) }
                }
            }
            // As tall as its rows, up to a maximum past which it scrolls, so the window fits the
            // list rather than a fixed height (Adam, 2026-11-07: a lot of blank space).
            .frame(height: listHeight)

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
                // Dimmed while there is nothing to restore (Adam, 2026-10-31).
                Button("Restore TotalMix FX Order") {
                    // An empty order is TotalMix FX's own (PerformanceLayout.withOrder).
                    model.engine.setLayout(model.engine.layout.withOrder(view, []))
                    reload()
                }
                .disabled(isTotalMixOrder)
            }

            VStack(alignment: .leading, spacing: 10) {
                // In callout size, for legibility (Adam, 2026-10-31).
                // Only what this tab can't show (Adam, 2026-11-07: the colors, label-clearing, and
                // longer playback notes were cut; how to hide channels is in the Setup Guide).
                Text("Channels hidden from Performance Bridge’s OSC Controller in TotalMix FX aren’t shown (Setup Guide).")
                if view == .sources {
                    Text("A software playback without a label shows as \u{201C}PB 1/2\u{201D} and so on.")
                }
            }
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
        // Channels arrive after a refresh: fit the window to the list again.
        .onChange(of: items.count) { _ in DispatchQueue.main.async { Windows.fitToContent("settings") } }
        .onAppear {
            // A visit here usually follows changes in TotalMix FX's own Channel Layout window,
            // which TotalMix FX doesn't announce over OSC: refresh the channels first.
            model.engine.refresh()
            reload()
        }
        .onChange(of: model.status) { _ in reload() }
    }

    /// A group's title, as a row that isn't dragged and doesn't pin.
    private func groupTitle(_ text: String) -> some View {
        Text(text)
            .font(.subheadline.weight(.semibold))
            .foregroundStyle(.secondary)
            .padding(.top, 6)
            .listRowSeparator(.hidden)
            .moveDisabled(true)
    }

    /// A group's rows: a drag handle and the channel's name.
    private func rows(_ group: [LayoutItem]) -> some DynamicViewContent {
        ForEach(group, id: \.channel) { item in
            LayoutRow(item: item) { text in
                model.engine.setLabel(text, for: item.channel)
                reload()
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
        // The outputs list shows only the send targets: the outputs it leaves out (Main Out, Main
        // Out B, and so on) keep their places, so the saved order matches TotalMix FX's whenever
        // the listed ones do.
        let all = model.engine.layoutItems(view).map(\.channel)
        model.engine.setLayout(model.engine.layout.withOrder(view, items.map(\.channel), among: all))
        isTotalMixOrder = model.engine.isTotalMixOrder(view)
    }

    /// Reads the view's channels again, after a change in the app or in TotalMix FX. The outputs
    /// view lists only the send targets, since in 1.0.x its order is only the order the sends step
    /// through (Adam, 2026-11-02, from the UI review of that date).
    private func reload() {
        let all = model.engine.layoutItems(view)
        let sends = Set(model.status.sendTargets.map(\.output))
        items = view == .outputs ? all.filter { sends.contains($0.channel.channel) } : all
        isTotalMixOrder = model.engine.isTotalMixOrder(view)
    }
}

/// One row of the layout: a drag handle, the channel's name (its label, editable in place), a
/// pencil right after the name while the pointer is over the row, and, beside a label, the name it
/// replaces, dimmed. The pencil shows only on hover (Adam, 2026-11-02: a pencil on every row says
/// nothing), as macOS lists reveal a row's controls where the pointer is.
struct LayoutRow: View {
    let item: LayoutItem
    let commit: (String) -> Void
    @State private var hovering = false
    /// Whether the label field is being edited; the pencil puts the cursor there (Adam, 2026-11-02).
    @FocusState private var editing: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "line.3.horizontal")
                .foregroundStyle(.tertiary)
                .accessibilityHidden(true)
                .padding(.trailing, 2)
            LabelField(item: item, commit: commit, focused: $editing)
                // As wide as the name, so the pencil sits right after it.
                .fixedSize()
            // The pencil edits the name: a click puts the cursor in the field, as clicking the name
            // does (Adam, 2026-11-02: a pencil that did nothing invited a click).
            Button { editing = true } label: {
                Image(systemName: "pencil")
                    .foregroundStyle(.secondary)
            }
            .buttonStyle(.plain)
            .opacity(hovering || editing ? 1 : 0)
            .help("Edit the label")
            .accessibilityLabel("Edit the label for \(item.defaultName)")
            if item.label != nil {
                // Clears the label, back to the name the strip would show anyway (Adam, 2026-11-02).
                Button { commit("") } label: {
                    Image(systemName: "xmark.circle.fill")
                        .foregroundStyle(.tertiary)
                }
                .buttonStyle(.plain)
                .help("Clear the label")
                .accessibilityLabel("Clear the label for \(item.defaultName)")
                // The name the strip would show without the label, for reference.
                Text(item.defaultName)
                    .foregroundStyle(.tertiary)
                    .lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .contentShape(Rectangle())
        .onHover { hovering = $0 }
    }
}

/// A channel's label for the hardware controllers, edited in place. Without a label it shows the
/// name the strip would show anyway, dimmed (TotalMix FX's name, or "PB 1/2" for a playback). The label
/// is saved when Return is pressed or the field loses focus; an empty field removes it.
struct LabelField: View {
    let item: LayoutItem
    let commit: (String) -> Void
    /// Whether the field has the cursor, held by the row so its pencil can put it there.
    var focused: FocusState<Bool>.Binding
    @State private var text = ""

    var body: some View {
        TextField("Label", text: $text, prompt: Text(item.defaultName))
            .textFieldStyle(.plain)
            .labelsHidden()
            .focused(focused)
            .onAppear { text = item.label ?? "" }
            .onChange(of: item.label) { text = $0 ?? "" }
            .onSubmit { save() }
            .onChange(of: focused.wrappedValue) { if !$0 { save() } }
            .accessibilityLabel("Label for \(item.defaultName)")
    }

    private func save() {
        var trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        // A label that is the name the strip would show anyway is no label (UI review of 2026-11-02).
        if trimmed == item.defaultName { trimmed = "" }
        guard trimmed != (item.label ?? "") else { text = item.label ?? ""; return }
        commit(trimmed)
    }
}

