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

    /// Brings the window named `id` forward if it is on screen, keeping its content, and says
    /// whether it was (e.g., Setup Guide… from the menu keeps the page the guide is on).
    static func front(_ id: String) -> Bool {
        guard let window = open[id], window.isVisible else { return false }
        NSApplication.shared.activate(ignoringOtherApps: true)
        window.makeKeyAndOrderFront(nil)
        return true
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
    /// The settings last applied, which Revert goes back to; kept here too, so a controller the app
    /// chose by itself while the other tab showed is followed (review of 1.0.2).
    @State private var saved = SavedSettings.load()

    var body: some View {
        TabView(selection: $tab) {
            pane(.connections) { SettingsView(model: model, edited: $edited, saved: $saved) }
                .tabItem { Text(SettingsTab.connections.title) }
                .tag(SettingsTab.connections)
            pane(.channelLayout) { LayoutView(model: model) }
                .tabItem { Text(SettingsTab.channelLayout.title) }
                .tag(SettingsTab.channelLayout)
        }
        .padding(.top, 8)
        .frame(width: 480)
        .onAppear { show(tab) }
        // The app chose the hardware controller by itself (BridgeModel.chooseControllerIfNeeded):
        // show it, unless the user has already picked another here.
        .onChange(of: model.autoChosen) { choice in
            guard let choice else { return }
            if edited.controller == saved.controller { edited.controller = choice }
            saved.controller = choice
        }
        .onChange(of: edited.controller) { _ in
            // The Connections tab grows or shrinks with the chosen controller's settings.
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
        // Rows that come and go with the E16's layout and with TotalMix FX's outputs (Tier 1
        // review, 2026-11-07: the window grew but never shrank back).
        .onChange(of: model.status.e16FourChannelStrips) { _ in
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
        .onChange(of: model.status.sendTargets.isEmpty) { _ in
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
        // The login item's notes come and go too.
        .onChange(of: model.loginItem) { _ in
            DispatchQueue.main.async { Windows.fitToContent("settings") }
        }
        .onChange(of: model.loginItemError) { _ in
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

    /// The settings last applied (held by the Settings window).
    @Binding var saved: SavedSettings

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // The settings Apply covers, boxed with its buttons, apart from a Launch Control's
            // section below, which takes effect at once (Adam, 2026-11-02, from the UI review of
            // that date).
            GroupBox {
                appliedSettings
                    .padding(8)
            }

            // The chosen controller's own settings, which take effect at once, in a box of their
            // own so their columns line up with the box above (UI review of 2026-11-07).
            if let chosen = edited.controller.launchControl {
                GroupBox {
                    LaunchControlSendRowsView(model: model, chosen: chosen)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }
            if edited.controller == .e16 {
                GroupBox {
                    E16SettingsView(model: model)
                        .padding(8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            // Opening at login, last, in a box of its own: it takes effect at once and isn't
            // covered by Apply (Adam, 2026-11-10).
            GroupBox {
                OpenAtLoginToggle(model: model)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
        }
        .padding(20)
        .fixedSize(horizontal: false, vertical: true)
    }

    /// TotalMix FX's host and ports and the hardware controller, with Defaults, Revert, and Apply.
    private var appliedSettings: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("TotalMix FX")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Computer")
                    TextField("Computer", text: $edited.host, prompt: Text("localhost"))
                        .labelsHidden()
                }
                // TotalMix FX's own labels, so they match its window word for word (UI review of
                // 2026-11-02): "incoming" and "outgoing" are TotalMix FX's side.
                portRow("Port (incoming)", value: $edited.incomingPort, override: model.portOverrides.incoming)
                portRow("Port (outgoing)", value: $edited.outgoingPort, override: model.portOverrides.outgoing)
            }
            note("Use the ports set in TotalMix FX: Options → Mixer Settings… → OSC, with “Compatibility (Mode)” set to “Global OSC”.")

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
        }
    }

    /// The note under the hardware controller's menu.
    private var controllerNote: String {
        // Only what the user needs to do or know before connecting; how the app finds the port
        // is in the Setup Guide, where it matters if it fails (UI review of 2026-11-07).
        if edited.controller == .roto {
            return "Connect the Roto-Control by USB."
        }
        if edited.controller == .e16 {
            return "Connect the E16 by USB. It needs firmware 1.3.0 or later."
        }
        let model = edited.controller.launchControl ?? .xl3
        return "Connect the \(model.name) by USB."
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

/// The E16's settings, in a box of their own below the Connections tab's box while the E16 is
/// chosen: its layout, its send rows (only for channel strips, the layout that uses them), its
/// meters, and its rings' brightness. Each takes effect at once, connected or not; the layout and
/// sends also follow a change made on the device. Text is only what Settings can't do without:
/// what the layouts and the Shift page do is in the Controls Guide (Adam, 2026-11-07).
struct E16SettingsView: View {
    @ObservedObject var model: BridgeModel

    /// Every row as tall as a menu row, so checkbox and slider rows aren't crowded against the
    /// menus (Adam, 2026-11-07).
    static let rowHeight: CGFloat = 24

    /// The slider reads 1–100 for the engine's usable range (`BridgeEngine.e16MinimumBrightness`
    /// to `e16MaximumBrightness`, 3%–80% of the LEDs' full output; Adam, 2026-11-04).
    static let shownRange = 1.0...100.0

    /// The slider's reading for an engine brightness.
    static func shown(_ brightness: Double) -> Double {
        let low = BridgeEngine.e16MinimumBrightness, high = BridgeEngine.e16MaximumBrightness
        guard brightness.isFinite else { return shownRange.lowerBound }
        let fraction = (brightness - low) / (high - low)
        return min(max(shownRange.lowerBound + fraction * (shownRange.upperBound - shownRange.lowerBound), shownRange.lowerBound), shownRange.upperBound)
    }

    /// The engine brightness for a slider reading.
    static func brightness(shown: Double) -> Double {
        let low = BridgeEngine.e16MinimumBrightness, high = BridgeEngine.e16MaximumBrightness
        guard shown.isFinite else { return low }
        let fraction = (shown - shownRange.lowerBound) / (shownRange.upperBound - shownRange.lowerBound)
        return min(max(low + fraction * (high - low), low), high)
    }

    var body: some View {
        let status = model.status
        let live = !status.sendTargets.isEmpty
        VStack(alignment: .leading, spacing: 12) {
            Text("OXI E16")
                .font(.headline)
            Grid(alignment: .leadingFirstTextBaseline, horizontalSpacing: 10, verticalSpacing: 8) {
                GridRow {
                    label("Layout")
                    Picker("Layout", selection: Binding(
                        get: { model.status.e16FourChannelStrips },
                        set: { model.engine.setE16Layout(fourChannelStrips: $0) })) {
                        Text("16 channels").tag(false)
                        Text("Channel strips").tag(true)
                    }
                    .labelsHidden()
                    .frame(width: 200, alignment: .leading)
                }
                if status.e16FourChannelStrips {
                    ForEach(0..<2, id: \.self) { row in
                        GridRow {
                            label(row == 0 ? "Send A" : "Send B")
                            Picker(row == 0 ? "Send A" : "Send B", selection: selection(row)) {
                                if selection(row).wrappedValue == nil {
                                    Text("None").tag(Int?.none)
                                }
                                ForEach(choices(row), id: \.output) { choice in
                                    Text(choice.name).tag(Int?.some(choice.output))
                                }
                            }
                            .labelsHidden()
                            .frame(width: 200, alignment: .leading)
                            .disabled(!live)
                        }
                    }
                    if !live {
                        GridRow {
                            Color.clear
                                .gridCellUnsizedAxes([.horizontal, .vertical])
                            Text("The outputs come from TotalMix FX. Open it to choose them here.")
                                .font(.callout)
                                .foregroundStyle(.secondary)
                                .fixedSize(horizontal: false, vertical: true)
                        }
                    }
                }
                GridRow {
                    label("Meters")
                    Toggle("Show under the channel names", isOn: Binding(
                        get: { model.status.e16Meters },
                        set: { model.setE16Meters($0) }))
                        .frame(minHeight: Self.rowHeight)
                }
                GridRow {
                    label("Ring brightness")
                    HStack {
                        Slider(value: Binding(
                            get: { Self.shown(model.status.e16Brightness) },
                            set: { model.setE16Brightness(Self.brightness(shown: $0)) }), in: Self.shownRange)
                            .frame(width: 200)
                        Text("\(Int(Self.shown(model.status.e16Brightness).rounded()))")
                            .monospacedDigit()
                            .frame(width: 32, alignment: .trailing)
                    }
                    .frame(minHeight: Self.rowHeight)
                }
            }
        }
    }

    /// A row label, right-aligned in its column, in the width every Settings row shares.
    private func label(_ text: String) -> some View {
        Text(text)
            .frame(width: 110, alignment: .trailing)
    }

    /// The outputs a send row can feed: every send target except the other row's.
    private func choices(_ row: Int) -> [HomeChoice] {
        let sends = model.status.e16Sends
        let others = Set(sends.indices.filter { $0 != row }.compactMap { sends[$0] })
        return model.status.sendTargets.filter { !others.contains($0.output) }
    }

    private func selection(_ row: Int) -> Binding<Int?> {
        Binding(
            get: { model.status.e16Sends.indices.contains(row) ? model.status.e16Sends[row] : nil },
            set: { output in if let output { model.engine.setE16Send(row: row, to: output) } })
    }
}

/// A Launch Control's send rows, in their own box on the Connections tab while a Launch Control is
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
        VStack(alignment: .leading, spacing: 12) {
            // A heading of its own, so the menus can list plain output names (Adam, 2026-11-01). On
            // the Launch Control 3 the row can be Pan, so it is named for the row (UI review of
            // 2026-11-02).
            Text(chosen.name)
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
                            // Each output carries the "> " that marks a send (Adam, 2026-11-02 for
                            // the Launch Control 3, where a row can also be pan; 2026-11-07 for the
                            // XL 3, since the box is headed by the model, not "Sends").
                            ForEach(choices(row), id: \.output) { choice in
                                Text(choiceTitle(choice.name))
                                    .tag(Int?.some(choice.output))
                            }
                        }
                        .labelsHidden()
                        .frame(width: 200, alignment: .leading)
                        .disabled(!live)
                    }
                }
                // Only what Settings can't do without: why the menus are greyed out. What Page,
                // the colors, and the brightness setting do is in the Controls Guide (UI review
                // of 2026-11-07, as for the E16).
                if !live {
                    GridRow {
                        Color.clear
                            .gridCellUnsizedAxes([.horizontal, .vertical])
                        Text("The outputs come from TotalMix FX. Open it to choose them here.")
                            .font(.callout)
                            .foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }
                // Off by default (Adam, 2026-11-02); takes effect at once, like the send rows.
                GridRow {
                    Text("Levels")
                        .frame(width: 110, alignment: .trailing)
                    Toggle("Show by brightness", isOn: Binding(
                        get: { model.status.launchControlLevelBrightness },
                        set: { model.setLevelBrightness($0) }))
                        .frame(minHeight: E16SettingsView.rowHeight)
                }
            }
        }
    }

    private var rowCount: Int { LaunchControlSendRows.rowCount(chosen) }

    /// An output's title in a row's menu: "> Phones 1", a send to it, on both models.
    private func choiceTitle(_ name: String) -> String {
        LaunchControlDriver.sendLabel(name)
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
