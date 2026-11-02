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
#if canImport(LaunchControlDriver)
import LaunchControlDriver
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

/// The Connections tab: where to find TotalMix FX, and which hardware controller is used. Apply,
/// Revert, and Defaults sit right under those settings, which they alone cover (Adam, 2026-11-02);
/// Apply saves them and restarts the connections, and leaves the window open. A Launch Control's
/// send rows follow below, shown as soon as one is chosen (Adam, 2026-11-01); they take effect at
/// once, connected or not. There is no MIDI port setting: each model's ports have fixed names, and
/// the engine finds them (Adam, 2026-11-02).
struct SettingsView: View {
    @ObservedObject var model: BridgeModel
    /// The edits, held by the Settings window so they survive switching tabs.
    @Binding var edited: SavedSettings

    @State private var saved = SavedSettings.load()

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
            note("The computer that runs TotalMix FX and the ports of the OSC controller set up for Performance Bridge.\n\nIn TotalMix FX: Options → Mixer Settings… → OSC, “Port (incoming)” and “Port (outgoing)”, with “Compatibility (Mode)” set to “Global OSC”.")

            Divider()
                .padding(.vertical, 4)

            Text("Hardware Controller")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Controller")
                    Picker("Controller", selection: $edited.controller) {
                        ForEach(ControllerChoice.allCases) { choice in
                            Text(choice.title).tag(choice)
                        }
                    }
                    .labelsHidden()
                }
            }
            note(controllerNote)
            if model.launchControlFromCommandLine {
                Text("A Launch Control chosen on the command line is in use instead.")
                    .font(.callout)
                    .foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
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
                    saved = edited
                }
                .keyboardShortcut(.defaultAction)
                .disabled(!edited.isValid || edited == saved)
            }
            .padding(.top, 4)

            if let chosen = edited.controller.launchControl {
                Divider()
                    .padding(.vertical, 4)
                LaunchControlSendRowsView(model: model, chosen: chosen)
            }
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// The note under the hardware controller's menu.
    private var controllerNote: String {
        if edited.controller == .roto {
            return "Connect the Roto-Control by USB. Performance Bridge finds it by the name of its MIDI port."
        }
        let model = edited.controller.launchControl ?? .xl3
        return "Connect the \(model.name) by USB. Performance Bridge finds its DAW port (“\(model.portPrefix) 1 DAW”) by name; with more than one connected, it uses the one with the lowest device ID."
    }

    /// A row label, right-aligned in its column, in the width all rows share.
    private func label(_ text: String) -> some View {
        Text(text)
            .frame(width: 110, alignment: .trailing)
    }

    /// A note under a group, wrapping to the window's width, in callout size rather than caption,
    /// and with a blank line starting a new paragraph, for legibility (Adam, 2026-10-31).
    private func note(_ text: String) -> some View {
        VStack(alignment: .leading, spacing: 10) {
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
/// (the XL 3's middle row). The engine holds both models' rows, so they can be set whether or not
/// the model is applied or connected (Adam, 2026-11-02); changes take effect at once. The outputs
/// come from TotalMix FX, so the menus wait for it to answer.
struct LaunchControlSendRowsView: View {
    @ObservedObject var model: BridgeModel
    /// The model chosen in the Connections tab, applied or not.
    var chosen: LaunchControlModel

    var body: some View {
        let status = model.status
        let live = !status.sendTargets.isEmpty
        VStack(alignment: .leading, spacing: 8) {
            // A heading of its own, so the menus can list plain output names (Adam, 2026-11-01).
            Text("Sends")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                ForEach(0..<rowCount, id: \.self) { row in
                    GridRow {
                        Text(rowTitle(row))
                            .frame(width: 110, alignment: .trailing)
                        Picker(rowTitle(row), selection: selection(row)) {
                            if chosen == .lc3 {
                                Text("Pan").tag(Int?.none)
                            } else if selection(row).wrappedValue == nil {
                                // An XL 3 row with no output left to feed (review of 2026-11-02).
                                Text("None").tag(Int?.none)
                            }
                            // On the Launch Control 3 the row is pan or a send, so the sends carry
                            // the "> " that marks a send (Adam, 2026-11-02); the XL 3's rows are
                            // always sends, under the "Sends" heading (Adam, 2026-11-01).
                            ForEach(choices(row), id: \.output) { choice in
                                Text(choiceTitle(choice.name))
                                    .tag(Int?.some(choice.output))
                            }
                        }
                        .labelsHidden()
                        .disabled(!live)
                    }
                }
            }
            VStack(alignment: .leading, spacing: 10) {
                Text(live
                     ? "Changes here take effect at once."
                     : "The outputs come from TotalMix FX. Open it to choose them here.")
                    .fixedSize(horizontal: false, vertical: true)
                Text(chosen == .lc3
                     ? "Page ▲ and ▼ on the Launch Control also step the top row through Pan and the outputs."
                     : "Page ▲ and ▼ on the Launch Control step the top row, and Shift + Page the middle row. The two rows never feed the same output.")
                    .fixedSize(horizontal: false, vertical: true)
                Text("The outputs follow the order of the Outputs list on the Channel Layout tab.")
                    .fixedSize(horizontal: false, vertical: true)
            }
            .font(.callout)
            .foregroundStyle(.secondary)

            // Off by default (Adam, 2026-11-02); takes effect at once, like the send rows.
            Toggle("Show levels by brightness", isOn: Binding(
                get: { model.status.launchControlLevelBrightness },
                set: { model.setLevelBrightness($0) }))
                .padding(.top, 6)
            Text(chosen == .lc3
                 ? "The level and send encoders dim as their levels fall: bright above −10 dB, dimmer down to −40 dB, dimmest below, and dark at −oo. Pan keeps full brightness."
                 : "The send encoders dim as their levels fall: bright above −10 dB, dimmer down to −40 dB, dimmest below, and dark at −oo. Pan keeps full brightness, and the faders have no lights.")
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var rowCount: Int { LaunchControlSendRows.rowCount(chosen) }

    /// An output's title in a row's menu: "> Phones 1" on the Launch Control 3, where the row can
    /// also be Pan; the plain name on the XL 3, under the "Sends" heading.
    private func choiceTitle(_ name: String) -> String {
        chosen == .lc3 ? LaunchControlDriver.sendLabel(name) : name
    }

    /// The output each of the chosen model's rows feeds now, as the engine reports it.
    private var rows: [Int?] { model.status.launchControlSends[chosen] ?? [] }

    private func rowTitle(_ row: Int) -> String {
        chosen == .lc3 ? "Top row" : row == 0 ? "Top row" : "Middle row"
    }

    /// The outputs a row can feed: every send target except the other row's.
    private func choices(_ row: Int) -> [HomeChoice] {
        let sends = rows
        let others = Set(sends.indices.filter { $0 != row }.compactMap { sends[$0] })
        return model.status.sendTargets.filter { !others.contains($0.output) }
    }

    private func selection(_ row: Int) -> Binding<Int?> {
        Binding(
            get: { rows.indices.contains(row) ? rows[row] : nil },
            set: { model.engine.setLaunchControlSend(layout: chosen, row: row, to: $0) })
    }
}
