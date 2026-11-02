// The app's two windows, About and Settings. They are plain AppKit windows holding SwiftUI views,
// opened from the menu: a SwiftUI `Window` scene would open by itself at launch, and the `Settings`
// scene can't be opened the same way on macOS 13 and 14.

import AppKit
import SwiftUI
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(MIDITransport)
import MIDITransport
#endif
#if canImport(BridgeEngine)
import BridgeEngine
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif

/// Opens the app's windows, one of each, bringing the app forward (a menu-bar app is otherwise in
/// the background).
@MainActor
enum Windows {
    private static var open: [String: NSWindow] = [:]

    /// Shows the window named `id`, with fresh content, making it the first time.
    static func show<Content: View>(_ id: String, title: String, @ViewBuilder content: () -> Content) {
        let window = open[id] ?? {
            let window = NSWindow(contentRect: .zero, styleMask: [.titled, .closable], backing: .buffered, defer: false)
            window.isReleasedWhenClosed = false
            open[id] = window
            return window
        }()
        window.title = title
        window.contentViewController = NSHostingController(rootView: content().tint(Brand.accent))
        if !window.isVisible { window.center() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
    }

    /// Sets the title of the window named `id`, if it is open.
    static func setTitle(_ id: String, _ title: String) {
        open[id]?.title = title
    }

    /// Resizes the window named `id` to fit its content, keeping its top edge where it is. A
    /// hosted SwiftUI view makes its window grow when the content grows, but not shrink when it
    /// shrinks, so the Settings window calls this when its tab changes (Adam, 2026-10-31). The
    /// change is animated, as macOS settings windows animate between panes, unless Reduce Motion
    /// is on.
    static func fitToContent(_ id: String) {
        guard let window = open[id], let view = window.contentViewController?.view else { return }
        view.layoutSubtreeIfNeeded()
        let content = view.fittingSize
        guard content.width > 0, content.height > 0 else { return }
        var frame = window.frameRect(forContentRect: NSRect(origin: .zero, size: content))
        frame.origin.x = window.frame.minX
        frame.origin.y = window.frame.maxY - frame.height
        let animate = !NSWorkspace.shared.accessibilityDisplayShouldReduceMotion
        window.setFrame(frame, display: true, animate: animate)
    }

    /// Closes the window named `id`, if it is open.
    static func close(_ id: String) {
        open[id]?.close()
    }
}

/// The About window: the icon at 128 points, large enough for its details, and what the app is.
struct AboutView: View {
    var body: some View {
        VStack(spacing: 10) {
            Image(nsImage: Brand.appIcon)
                .resizable()
                .interpolation(.high)
                .frame(width: 128, height: 128)
                .accessibilityLabel("Performance Bridge icon")
            Text("Performance Bridge")
                .font(.title2.weight(.semibold))
            Text(Brand.version)
                .foregroundStyle(.secondary)
            Text("Connects hardware controllers to RME TotalMix FX for mixing live.")
                .multilineTextAlignment(.center)
                .padding(.top, 4)
            Link("github.com/adambier/performance-bridge",
                 destination: URL(string: "https://github.com/adambier/performance-bridge")!)
            Text("© 2026 Adam Arthur Bier. MIT License.")
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.top, 4)
        }
        .padding(24)
        .frame(width: 360)
        .fixedSize()
    }
}

/// The Settings window's tabs.
enum SettingsTab: String, Hashable {
    /// Where to find TotalMix FX and the hardware controller.
    case connections
    /// The order of the channels on the surfaces.
    case channelLayout

    /// The tab's name, also the window's title while it shows (Apple's HIG, Settings: the title
    /// names the pane that is showing).
    var title: String {
        switch self {
        case .connections: return "Connections"
        case .channelLayout: return "Channel Layout"
        }
    }

    /// The tab shown last, which Settings… opens on (Apple's HIG, Settings: restore the pane
    /// viewed most recently).
    static var lastShown: SettingsTab {
        get { UserDefaults.standard.string(forKey: "settingsTab").flatMap(SettingsTab.init(rawValue:)) ?? .connections }
        set { UserDefaults.standard.set(newValue.rawValue, forKey: "settingsTab") }
    }
}

/// The Settings window: Connections and Channel Layout, in tabs (Adam, 2026-10-31). The window
/// fits the tab that is showing, as macOS settings windows do, rather than the taller of the two
/// (Adam, 2026-10-31): only that tab's content is built, and the other is empty, since a tab view
/// otherwise takes the size of its largest tab.
struct SettingsWindowView: View {
    @ObservedObject var model: BridgeModel
    @State var tab: SettingsTab
    /// The Connections tab's edits, kept here so they survive a visit to the other tab.
    @State private var edited = SavedSettings.load()

    var body: some View {
        TabView(selection: $tab) {
            pane(.connections) { SettingsView(model: model, edited: $edited) }
                .tabItem { Text(SettingsTab.connections.title) }
                .tag(SettingsTab.connections)
            pane(.channelLayout) { LayoutView(model: model) }
                .tabItem { Text(SettingsTab.channelLayout.title) }
                .tag(SettingsTab.channelLayout)
        }
        .padding(.top, 8)
        .frame(width: 480)
        .onAppear { show(tab) }
        .onChange(of: edited.controller) { _ in
            // The Connections tab grows or shrinks with the chosen controller's settings.
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
        .onChange(of: tab) { tab in
            show(tab)
            // After SwiftUI has laid out the new tab.
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
    }

    /// A tab's content while it shows, and nothing otherwise.
    @ViewBuilder
    private func pane<Content: View>(_ which: SettingsTab, @ViewBuilder _ content: () -> Content) -> some View {
        if tab == which {
            content()
        } else {
            Color.clear.frame(width: 0, height: 0)
        }
    }

    /// Names the window after the tab, and remembers it for the next Settings….
    private func show(_ tab: SettingsTab) {
        Windows.setTitle("settings", tab.title)
        SettingsTab.lastShown = tab
    }
}

extension BridgeModel {
    /// Opens the Settings window on `tab`, or on the tab shown last.
    func showSettings(_ tab: SettingsTab? = nil) {
        let tab = tab ?? SettingsTab.lastShown
        Windows.show("settings", title: tab.title) {
            SettingsWindowView(model: self, tab: tab)
        }
    }
}

/// The Connections tab: where to find TotalMix FX, and which hardware controller is used and its
/// MIDI port. Only the chosen controller's settings show, and they change as soon as another is
/// chosen (Adam, 2026-11-01): a Launch Control's send rows appear below its port. Apply saves the
/// settings and restarts the connections.
struct SettingsView: View {
    @ObservedObject var model: BridgeModel
    /// The edits, held by the Settings window so they survive switching tabs.
    @Binding var edited: SavedSettings

    private let saved = SavedSettings.load()

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TotalMix FX")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Computer")
                    TextField("Computer", text: $edited.host, prompt: Text("localhost"))
                        .labelsHidden()
                }
                portRow("Incoming port", value: $edited.incomingPort, override: model.portOverrides.incoming)
                portRow("Outgoing port", value: $edited.outgoingPort, override: model.portOverrides.outgoing)
            }
            note("The computer that runs TotalMix FX and the ports of the OSC controller set up for Performance Bridge.\n\nIn TotalMix FX: Options → Mixer Settings… → OSC, “Port (incoming)” and “Port (outgoing)”, with “Global OSC” selected by “Compatibility (Mode)”.")

            Divider()
                .padding(.vertical, 4)

            Text("Hardware Controller")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Controller")
                    Picker("Controller", selection: controllerChoice) {
                        ForEach(ControllerChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                }
                GridRow {
                    label("MIDI port")
                    Picker("MIDI port", selection: $edited.portName) {
                        ForEach(portChoices, id: \.self) { name in
                            Text(portTitle(name)).tag(name)
                        }
                    }
                    .labelsHidden()
                }
            }
            note(portNote)
            if model.launchControlFromCommandLine {
                Text("A Launch Control from the command line is in use instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let chosen = edited.controller.launchControl {
                LaunchControlSendRowsView(model: model, chosen: chosen)
                    .padding(.top, 4)
            }

            if !edited.isValid {
                Text("Ports must be from 1 to 65535 and different from each other, and no field may be empty.")
                    .font(.callout)
                    .foregroundStyle(.red)
                    .fixedSize(horizontal: false, vertical: true)
            }
            HStack {
                Button("Defaults") { edited = SavedSettings() }
                Spacer()
                Button("Revert") { edited = saved }
                    .disabled(edited == saved)
                Button("Apply") {
                    model.apply(edited)
                    Windows.close("settings")
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!edited.isValid || edited == saved)
            }
            .padding(.top, 8)
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The controller menu's selection: choosing a model also moves a Launch Control port left at
    /// the other model's usual name to this one's.
    private var controllerChoice: Binding<ControllerChoice> {
        Binding(get: { edited.controller }, set: { edited.choose($0) })
    }

    /// The note under the hardware controller's settings.
    private var portNote: String {
        if edited.controller == .roto {
            return "The MIDI ports connected now.\n\nIf the Roto-Control isn’t listed, connect it by USB and open Settings again."
        }
        return "The MIDI ports connected now. Choose the Launch Control’s DAW port (e.g., “LCXL3 1 DAW”), not its MIDI port.\n\nIf it isn’t listed, connect it by USB and open Settings again."
    }

    /// The MIDI ports that both send and receive, as they are when the window opens: a source and
    /// a destination with the same name (the Roto-Control's), or a pair named "… Out" and "… In"
    /// (the Launch Controls'), listed by the part they share (e.g., "LCXL3 1 DAW").
    @State private var ports = Self.listPorts()

    private static func listPorts() -> [MIDIEndpointInfo] {
        let destinations = Set(MIDIConnection.destinations().map(\.name))
        var seen = Set<String>()
        var ports: [MIDIEndpointInfo] = []
        for source in MIDIConnection.sources() {
            var port = source
            if !destinations.contains(source.name) {
                guard source.name.hasSuffix(" Out") else { continue }
                let stem = String(source.name.dropLast(4))
                guard destinations.contains(stem + " In") else { continue }
                port.name = stem
            }
            if seen.insert(port.name).inserted { ports.append(port) }
        }
        return ports.sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The menu's choices: the ports, and the chosen name too when it is not exactly one of them
    /// (e.g., the default "Roto", which matches "Roto-Control" by part of its name).
    private var portChoices: [String] {
        let names = ports.map(\.name)
        return names.contains(edited.portName) ? names : [edited.portName] + names
    }

    /// A choice's title: a port's name, or a chosen name that is not a port's, with what it matches.
    private func portTitle(_ name: String) -> String {
        if ports.contains(where: { $0.name == name }) { return name }
        if let port = MIDIEndpointInfo.match(name, in: ports) { return "“\(name)” (matches \(port.name))" }
        return "“\(name)” (not found)"
    }

    /// A row label, right-aligned in its column, in the width all rows share.
    private func label(_ text: String) -> some View {
        Text(text)
            .frame(width: 110, alignment: .trailing)
    }

    /// A note under a group, wrapping to the window's width, in callout size rather than caption,
    /// and with a blank line starting a new paragraph, for legibility (Adam, 2026-10-31).
    private func note(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 6) {
            ForEach(text.components(separatedBy: "\n\n"), id: \.self) { paragraph in
                Text(paragraph)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .font(.callout)
        .foregroundStyle(.secondary)
    }

    /// A port's row, with a line under it when a port from the command line is in use instead.
    @ViewBuilder
    private func portRow(_ title: String, value: Binding<Int>, override: UInt16?) -> some View {
        GridRow {
            label(title)
            TextField(title, value: value, format: .number.grouping(.never))
                .labelsHidden()
                .frame(width: 80)
        }
        if let override {
            GridRow {
                Color.clear
                    .gridCellUnsizedAxes([.horizontal, .vertical])
                Text("Port \(String(override)) from the command line is in use instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}

/// A Launch Control's send rows, at the bottom of the Connections tab while a Launch Control is
/// chosen: the outputs they feed, also chosen on the device with Page (top row) and Shift + Page
/// (the XL 3's middle row). Changes take effect at once, as on the device; until the chosen model
/// is the one running (after Apply) and connected, a note says so instead.
struct LaunchControlSendRowsView: View {
    @ObservedObject var model: BridgeModel
    /// The model chosen in the Connections tab, applied or not.
    var chosen: LaunchControlModel

    var body: some View {
        let status = model.status
        let live = status.launchControlLayout == chosen && !status.launchControlSends.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(0..<rowCount, id: \.self) { row in
                    GridRow {
                        Text(rowTitle(row))
                            .frame(width: 110, alignment: .trailing)
                        Picker(rowTitle(row), selection: selection(row)) {
                            if chosen == .lc3 {
                                Text("Pan").tag(Int?.none)
                            }
                            ForEach(choices(row), id: \.output) { choice in
                                Text("> " + choice.name).tag(Int?.some(choice.output))
                            }
                        }
                        .labelsHidden()
                        .disabled(!live)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 6) {
                if !live {
                    Text(status.launchControlLayout == chosen
                         ? "Connect the \(chosen.name) to choose its send rows here."
                         : "Click Apply to use the \(chosen.name), then choose its send rows here.")
                        .fixedSize(horizontal: false, vertical: true)
                }
                Text(chosen == .lc3
                     ? "Page ▲ and ▼ on the Launch Control step the top row through Pan and the outputs too."
                     : "Page ▲ and ▼ on the Launch Control step the top row, and Shift + Page the middle row. The two rows never feed the same output.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("The outputs follow the order of the Outputs list on the Channel Layout tab.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)
        }
    }

    private var rowCount: Int { chosen == .xl3 ? 2 : 1 }

    private func rowTitle(_ row: Int) -> String {
        chosen == .lc3 ? "Top row" : row == 0 ? "Top row" : "Middle row"
    }

    /// The outputs a row can feed: every send target except the other row's.
    private func choices(_ row: Int) -> [HomeChoice] {
        let sends = model.status.launchControlSends
        let others = Set(sends.indices.filter { $0 != row }.compactMap { sends[$0] })
        return model.status.sendTargets.filter { !others.contains($0.output) }
    }

    private func selection(_ row: Int) -> Binding<Int?> {
        Binding(
            get: { model.status.launchControlSends.indices.contains(row) ? model.status.launchControlSends[row] : nil },
            set: { model.engine.setLaunchControlSend(row: row, to: $0) })
    }
}
