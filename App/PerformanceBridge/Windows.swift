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
        window.contentViewController = NSHostingController(rootView: content().tint(Brand.amber))
        if !window.isVisible { window.center() }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
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
            Text("Connects hardware control surfaces to RME TotalMix FX for mixing live.")
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
enum SettingsTab: Hashable {
    /// Where to find TotalMix FX and the Roto-Control.
    case connections
    /// The order of the channels on the surfaces.
    case channelLayout
}

/// The Settings window: Connections and Channel Layout, in tabs (Adam, 2026-10-31).
struct SettingsWindowView: View {
    @ObservedObject var model: BridgeModel
    @State var tab: SettingsTab

    var body: some View {
        TabView(selection: $tab) {
            SettingsView(model: model)
                .tabItem { Text("Connections") }
                .tag(SettingsTab.connections)
            LayoutView(model: model)
                .tabItem { Text("Channel Layout") }
                .tag(SettingsTab.channelLayout)
        }
        .padding(.top, 8)
        .frame(width: 480)
    }
}

extension BridgeModel {
    /// Opens the Settings window on `tab`.
    func showSettings(_ tab: SettingsTab = .connections) {
        Windows.show("settings", title: "Performance Bridge Settings") {
            SettingsWindowView(model: self, tab: tab)
        }
    }
}

/// The Connections tab: where to find TotalMix FX and the Roto-Control. Apply saves the settings
/// and restarts the connections.
struct SettingsView: View {
    @ObservedObject var model: BridgeModel
    @State private var edited = SavedSettings.load()

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
            note("The computer that runs TotalMix FX, and the ports of the OSC controller set up for Performance Bridge in TotalMix FX: Options → Mixer Settings… → OSC, “Port (incoming)” and “Port (outgoing)”, with “Global OSC” chosen.")

            Divider()
                .padding(.vertical, 4)

            Text("Roto-Control")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("MIDI port")
                    Picker("MIDI port", selection: $edited.rotoPortName) {
                        ForEach(portChoices, id: \.self) { name in
                            Text(portTitle(name)).tag(name)
                        }
                    }
                    .labelsHidden()
                }
            }
            note("The MIDI ports connected now. If the Roto-Control isn’t listed, connect it by USB and open Settings again.")

            if !edited.isValid {
                Text("Ports must be from 1 to 65535 and different from each other, and no field may be empty.")
                    .font(.caption)
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

    /// The names of the MIDI ports that both send and receive, as they are when the window opens.
    @State private var ports = Self.listPorts()

    private static func listPorts() -> [MIDIEndpointInfo] {
        let destinations = Set(MIDIConnection.destinations().map(\.name))
        var seen = Set<String>()
        return MIDIConnection.sources()
            .filter { destinations.contains($0.name) && seen.insert($0.name).inserted }
            .sorted { $0.name.localizedStandardCompare($1.name) == .orderedAscending }
    }

    /// The menu's choices: the ports, and the chosen name too when it is not exactly one of them
    /// (e.g., the default "Roto", which matches "Roto-Control" by part of its name).
    private var portChoices: [String] {
        let names = ports.map(\.name)
        return names.contains(edited.rotoPortName) ? names : [edited.rotoPortName] + names
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

    /// A note under a group, wrapping to the window's width.
    private func note(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
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
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }
}
