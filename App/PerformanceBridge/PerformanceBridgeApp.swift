// Performance Bridge: the menu-bar app (macOS only). Run it from the package with
// `swift run PerformanceBridge`, or `swift run PerformanceBridge --in-port 7004 --out-port 9004` to
// override the ports saved in Settings; quit `sbdev bridge` first, since both need TotalMix's
// outgoing port and the Roto-Control's MIDI ports. make-app.sh builds the app bundle, with Sparkle.
// A Launch Control can be tried with `--launch-control xl3`, `lc3`, or `lc3-sim`
// (`LaunchControlSetting(arguments:)`) until Settings has a place for it.

import AppKit
import SwiftUI
#if canImport(BridgeEngine)
import BridgeEngine
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif
// Sparkle (in-app updates) is linked by make-app.sh. Package.swift does not declare it, so
// `swift run` compiles without it and the menu has no "Check for Updates…" item.
#if canImport(Sparkle)
import Sparkle
#endif

@main
struct PerformanceBridgeApp: App {
    @StateObject private var model = BridgeModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
        #if canImport(Sparkle)
        AppUpdates.start()
        #endif
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .tint(Brand.accent)
        } label: {
            // Three looks (Adam, 2026-10-31): normal when TotalMix FX and the Roto-Control are both
            // connected; dimmed when either is down for a routine reason (closed, unplugged); dimmed
            // with a red dot for a fault. The attention image is drawn in color, so it must not be
            // rendered as a template.
            if model.needsAttention {
                Image(nsImage: Brand.menuBarAttentionImage)
                    .renderingMode(.original)
                    .accessibilityLabel("Performance Bridge, needs attention")
            } else if model.allConnected {
                Image(nsImage: Brand.menuBarImage)
                    .renderingMode(.template)
                    .accessibilityLabel("Performance Bridge, connected")
            } else {
                Image(nsImage: Brand.menuBarDimmedImage)
                    .renderingMode(.template)
                    .accessibilityLabel("Performance Bridge, not connected")
            }
        }
    }
}

/// The app's look: the icon's amber as its accent color when the user's accent is Multicolor, and the menu-bar glyph (a one-color
/// template image from Design/AppIcon, which macOS colors to suit the menu bar).
enum Brand {
    /// The app's resources: the package's resource bundle under `swift run`, the app bundle when
    /// make-app.sh builds everything as one module.
    static var resources: Bundle {
        #if SWIFT_PACKAGE
        return Bundle.module
        #else
        return Bundle.main
        #endif
    }

    static let amber = Color(red: 1, green: 0xB1 / 255.0, blue: 0x3D / 255.0)

    /// Whether the user's accent color (System Settings → Appearance → Accent color) is
    /// Multicolor, the one choice that lets an app use its own accent color (Apple's HIG, Color).
    /// macOS keeps the choice in the global defaults' `AppleAccentColor`, which is absent for
    /// Multicolor (seen on Adam's Mac, 2026-10-31: `defaults read -g AppleAccentColor` found no
    /// such key with Multicolor chosen, and printed 5 with another color chosen). Read only: the app
    /// never writes another app's or the system's preferences.
    static var userChoseMulticolor: Bool {
        UserDefaults.standard.persistentDomain(forName: UserDefaults.globalDomain)?["AppleAccentColor"] == nil
    }

    /// The app's accent: its amber when the user's accent color is Multicolor, and the user's own
    /// accent color otherwise (Adam, 2026-10-31). Read when a window opens, so a change in System
    /// Settings shows the next time a window opens.
    static var accent: Color {
        userChoseMulticolor ? amber : .accentColor
    }

    /// The app icon at 128 points (the 128 and 256 px art from Design/AppIcon), for the About
    /// window.
    static let appIcon: NSImage = resources.image(forResource: "AppIcon") ?? NSApplication.shared.applicationIconImage

    /// "Version 1.0 (12)" from the app bundle, or "Development build" when run with `swift run`.
    static let version: String = {
        let info = Bundle.main.infoDictionary ?? [:]
        guard let short = info["CFBundleShortVersionString"] as? String else { return "Development build" }
        if let build = info["CFBundleVersion"] as? String, build != short { return "Version \(short) (\(build))" }
        return "Version \(short)"
    }()

    static let menuBarImage: NSImage = {
        let image = resources.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Performance Bridge")
            ?? NSImage()
        image.isTemplate = true
        return image
    }()

    /// How strongly a dimmed glyph is drawn: the 35% Apple uses for disabled elements (Bjango,
    /// "Designing macOS menu bar extras").
    static let dimmedOpacity: CGFloat = 0.35

    /// The menu-bar glyph dimmed, for a connection that is down for a routine reason. Still a
    /// template, so macOS colors it for the menu bar; the opacity carries through.
    static let menuBarDimmedImage: NSImage = {
        let base = menuBarImage
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect, from: .zero, operation: .sourceOver, fraction: dimmedOpacity)
            return true
        }
        image.isTemplate = true
        return image
    }()

    /// The menu-bar glyph, dimmed, with a red dot at its lower right, cut free of the glyph, for a
    /// fault (SetupWatch.needsAttention): dimmed since a connection is down, red since it needs
    /// attention (Adam, 2026-10-31; red because it reads as a problem, and amber is close to
    /// macOS's orange microphone dot). A template image is one color, so this one is not a
    /// template: the glyph is drawn in the label color and the dot in the system red, both
    /// resolved for the appearance it is drawn in (light or dark menu bar).
    static let menuBarAttentionImage: NSImage = {
        let base = menuBarImage
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.labelColor.withAlphaComponent(dimmedOpacity).setFill()
            rect.fill(using: .sourceIn)     // the glyph's shape, dimmed, in the menu bar's text color
            let diameter = (min(rect.width, rect.height) * 0.4).rounded()
            let dot = NSRect(x: rect.maxX - diameter, y: rect.minY, width: diameter, height: diameter)
            NSGraphicsContext.current?.compositingOperation = .clear
            NSBezierPath(ovalIn: dot.insetBy(dx: -1.5, dy: -1.5)).fill()
            NSGraphicsContext.current?.compositingOperation = .sourceOver
            NSColor.systemRed.setFill()
            NSBezierPath(ovalIn: dot).fill()
            return true
        }
        image.isTemplate = false
        return image
    }()
}

/// The settings kept between launches, in the user defaults.
struct SavedSettings: Equatable {
    var host = TotalMixEndpoint.standard.host
    var incomingPort = Int(TotalMixEndpoint.standard.incomingPort)
    var outgoingPort = Int(TotalMixEndpoint.standard.outgoingPort)
    var rotoPortName = BridgeSettings().rotoPortName

    private enum Key {
        static let host = "totalMixHost"
        static let incomingPort = "totalMixIncomingPort"
        static let outgoingPort = "totalMixOutgoingPort"
        static let rotoPortName = "rotoPortName"
    }

    static func load(_ defaults: UserDefaults = .standard) -> SavedSettings {
        var saved = SavedSettings()
        if let host = defaults.string(forKey: Key.host), !host.isEmpty { saved.host = host }
        if let port = defaults.object(forKey: Key.incomingPort) as? Int, SavedSettings.isPort(port) { saved.incomingPort = port }
        if let port = defaults.object(forKey: Key.outgoingPort) as? Int, SavedSettings.isPort(port) { saved.outgoingPort = port }
        if let name = defaults.string(forKey: Key.rotoPortName), !name.isEmpty { saved.rotoPortName = name }
        return saved
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Key.host)
        defaults.set(incomingPort, forKey: Key.incomingPort)
        defaults.set(outgoingPort, forKey: Key.outgoingPort)
        defaults.set(rotoPortName, forKey: Key.rotoPortName)
    }

    static func isPort(_ value: Int) -> Bool { (1...65_535).contains(value) }

    /// Whether every field can be used.
    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && Self.isPort(incomingPort) && Self.isPort(outgoingPort)
            && incomingPort != outgoingPort && !rotoPortName.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

/// The engine and its latest status, for the menu.
@MainActor
final class BridgeModel: ObservableObject {
    @Published var status = BridgeStatus()
    /// Whether the menu-bar icon shows its warning mark.
    @Published private(set) var needsAttention = false
    /// Whether TotalMix FX and the Roto-Control (and a Launch Control, if one is set) are all
    /// connected (the menu-bar icon is dimmed otherwise).
    var allConnected: Bool {
        status.totalMixAnswering && status.rotoConnected
            && (status.launchControlName == nil || status.launchControlConnected)
    }
    /// Whether TotalMix FX is among the running apps, and its version from its app bundle, for the
    /// setup window.
    @Published private(set) var totalMixRunning = false
    @Published private(set) var totalMixVersion: String?
    /// When the setup window opens by itself (SetupWatch in BridgeEngine).
    private var watch = SetupWatch(totalMixWorked: false, rotoWorked: false)
    private var watchTimer: Timer?
    @Published private(set) var engine: BridgeEngine
    /// Ports given on the command line (`--in-port`, `--out-port`), which win over the saved ones.
    let portOverrides: (incoming: UInt16?, outgoing: UInt16?)

    private static let homeSubmixKey = "homeSubmix"

    init() {
        let arguments = CommandLine.arguments
        func port(_ option: String) -> UInt16? {
            guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
            return UInt16(arguments[index + 1])
        }
        portOverrides = (port("--in-port"), port("--out-port"))
        engine = BridgeEngine(settings: Self.settings(SavedSettings.load(), overrides: portOverrides))
        watch = makeWatch()
        start()
        watchTimer = Timer.scheduledTimer(withTimeInterval: 1, repeats: true) { [weak self] _ in
            Task { @MainActor in self?.checkSetup() }
        }
        // The setup window opens by itself the first time the app runs; later, from the menu.
        if !UserDefaults.standard.bool(forKey: Self.setupShownKey) {
            DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) { [weak self] in
                guard let self else { return }
                UserDefaults.standard.set(true, forKey: Self.setupShownKey)
                self.showSetup()
            }
        }
    }

    private static let setupShownKey = "setupShown"

    /// The keys under which "worked with these settings" is kept: TotalMix's host and ports, and the
    /// Roto-Control's port name, as the engine uses them.
    private var totalMixWorkedKey: String {
        let endpoint = engine.settings.endpoint
        return "totalMixWorked \(endpoint.host) \(endpoint.incomingPort) \(endpoint.outgoingPort)"
    }
    private var rotoWorkedKey: String { "rotoWorked \(engine.settings.rotoPortName)" }

    /// A new watch for the engine's settings, with what has worked with them before.
    private func makeWatch() -> SetupWatch {
        SetupWatch(totalMixWorked: UserDefaults.standard.bool(forKey: totalMixWorkedKey),
                   rotoWorked: UserDefaults.standard.bool(forKey: rotoWorkedKey))
    }

    /// Once a second: opens the setup window when SetupWatch says to, remembers what has worked,
    /// and sets the menu-bar icon's mark.
    private func checkSetup() {
        let app = Self.runningTotalMix()
        let running = app != nil
        let version = app.flatMap(Self.version(of:))
        if running != totalMixRunning { totalMixRunning = running }
        if version != totalMixVersion { totalMixVersion = version }
        let tooOld = version.flatMap(TotalMixVersion.init).map { !$0.supportsGlobalOSC } ?? false
        let now = Date().timeIntervalSinceReferenceDate
        let reason = watch.update(status: status, totalMixRunning: running, now: now, totalMixTooOld: tooOld)
        if watch.totalMixWorked { UserDefaults.standard.set(true, forKey: totalMixWorkedKey) }
        if watch.rotoWorked { UserDefaults.standard.set(true, forKey: rotoWorkedKey) }
        let attention = watch.needsAttention(status: status, now: now)
        if attention != needsAttention { needsAttention = attention }
        if let reason {
            switch reason {
            case .portInUse: print("Opening setup: port \(engine.settings.endpoint.outgoingPort) is in use")
            case .totalMixNotAnswering: print("Opening setup: TotalMix FX is running but hasn't answered")
            case .rotoHandshake: print("Opening setup: the Roto-Control hasn't finished connecting")
            case .totalMixTooOld: print("Opening setup: TotalMix FX \(version ?? "") is older than 2.1")
            }
            fflush(stdout)
            showSetup()
        }
    }

    /// TotalMix FX among the running apps, if it is running. Matched by name, since its bundle
    /// identifier hasn't been checked on a Mac (inference: it contains "TotalMix").
    private static func runningTotalMix() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            let names = [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }
            return names.contains { $0.contains("totalmix") }
        }
    }

    /// A running app's version, read from its app bundle's Info.plist (read only; nothing of
    /// TotalMix's is written). Which key holds TotalMix's "2.10" hasn't been checked on a Mac, so
    /// the short version string is preferred and the build version is the fallback.
    private static func version(of app: NSRunningApplication) -> String? {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return nil }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let text = info[key] as? String, TotalMixVersion(text) != nil { return text }
        }
        return nil
    }

    /// Opens the setup window.
    func showSetup() {
        Windows.show("setup", title: "Performance Bridge Setup Guide") { SetupView(model: self) }
    }

    /// The engine's settings from the saved settings, the command line, and the menu's choices.
    private static func settings(_ saved: SavedSettings, overrides: (incoming: UInt16?, outgoing: UInt16?)) -> BridgeSettings {
        var settings = BridgeSettings()
        settings.endpoint = TotalMixEndpoint(host: saved.host.trimmingCharacters(in: .whitespaces),
                                             incomingPort: overrides.incoming ?? UInt16(saved.incomingPort),
                                             outgoingPort: overrides.outgoing ?? UInt16(saved.outgoingPort))
        settings.rotoPortName = saved.rotoPortName.trimmingCharacters(in: .whitespaces)
        settings.playbacksOnNewPage = UserDefaults.standard.bool(forKey: "playbacksOnNewPage")
        settings.layout = savedLayout()
        settings.homeSubmix = UserDefaults.standard.object(forKey: homeSubmixKey) as? Int
        settings.launchControl = LaunchControlSetting(arguments: CommandLine.arguments)
        return settings
    }

    /// The key for the saved layout (channel order, new-page option, and labels), as JSON.
    nonisolated private static let layoutKey = "layout"

    /// The layout saved last, or the default (TotalMix's order and names). Earlier builds didn't
    /// save the order at all, so it went back to TotalMix's at every launch and every Apply.
    private static func savedLayout() -> PerformanceLayout {
        guard let data = UserDefaults.standard.data(forKey: layoutKey),
              let layout = try? JSONDecoder().decode(PerformanceLayout.self, from: data) else { return PerformanceLayout() }
        return layout
    }

    private func start() {
        let engine = self.engine
        engine.onLayoutChange = { layout in
            if let data = try? JSONEncoder().encode(layout) { UserDefaults.standard.set(data, forKey: Self.layoutKey) }
        }
        // For now the log goes to the Terminal the app was started from.
        engine.onLog = { line in
            print(line)
            fflush(stdout)
        }
        engine.onStatus = { [weak self, weak engine] status in
            Task { @MainActor in
                // A stopped engine's last status is not wanted once a new engine has replaced it.
                guard let self, let engine, self.engine === engine else { return }
                self.status = status
            }
        }
        engine.start()
    }

    /// Saves new settings and restarts the engine with them.
    func apply(_ saved: SavedSettings) {
        saved.save()
        engine.stop()
        engine = BridgeEngine(settings: Self.settings(saved, overrides: portOverrides))
        status = BridgeStatus()
        watch = makeWatch()
        start()
    }

    /// Makes `output` the home submix and remembers it. The output Main Out is assigned to is
    /// saved as "follow Main Out", so a later change of Main Out in TotalMix moves the home too.
    func setHomeSubmix(_ output: Int) {
        let followsMainOut = status.monitoringOutputs.first { $0.roles.contains(.mainOut) }?.output == output
        if followsMainOut {
            UserDefaults.standard.removeObject(forKey: Self.homeSubmixKey)
            engine.setHomeSubmix(nil)
        } else {
            UserDefaults.standard.set(output, forKey: Self.homeSubmixKey)
            engine.setHomeSubmix(output)
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: BridgeModel

    // Short states of about the same length: a menu sizes itself when it opens, so a longer state
    // arriving while it's open is cut in the middle. (The engine keeps retrying in every state.)
    private var totalMixState: String {
        let status = model.status
        if status.totalMixAnswering { return "Connected" }
        if !status.listening { return "Port \(model.engine.settings.endpoint.outgoingPort) in Use" }
        return "No Answer"
    }

    private var rotoState: String {
        let status = model.status
        if status.rotoConnected { return "Connected" }
        if status.rotoFound { return "Connecting" }
        return "Not Found"
    }

    private var launchControlState: String {
        let status = model.status
        if status.launchControlConnected { return "Connected" }
        if status.launchControlFound { return "Connecting" }
        return "Not Found"
    }

    var body: some View {
        // Status only, always dimmed (Adam, 2026-10-31), as macOS's own menu bar menus show status
        // lines. The full reasons go to the log; the Setup Guide says what to do.
        Text("TotalMix FX: " + totalMixState)
        Text("Roto-Control: " + rotoState)
        if let name = model.status.launchControlName {
            Text(name + ": " + launchControlState)
        }
        Divider()
        // "Mix Output" (Adam, 2026-10-31): the output whose submix the level knobs and pans go into;
        // the code calls it the home submix.
        Menu("Mix Output") {
            ForEach(model.status.monitoringOutputs, id: \.output) { choice in
                Button(label(for: choice)) { model.setHomeSubmix(choice.output) }
            }
            if model.status.monitoringOutputs.isEmpty {
                Text("No monitoring outputs yet")
            }
            // Every other output TotalMix shows, always offered in a submenu (Adam, 2026-10-31).
            if !model.status.otherOutputs.isEmpty {
                Divider()
                Menu("Hardware Outputs") {   // TotalMix FX's name for these outputs (Adam, 2026-10-31)
                    ForEach(model.status.otherOutputs, id: \.output) { choice in
                        Button(label(for: choice)) { model.setHomeSubmix(choice.output) }
                    }
                }
            }
            // Choosing Main Out's output saves "follow Main Out" (BridgeModel.setHomeSubmix), so
            // the home moves when Main Out is reassigned in TotalMix. The menu no longer says so:
            // the note wasn't actionable (Adam, 2026-10-31); the setup guide (docs/SETUP.md) does.
        }
        // Order (Apple's HIG, Menus): what is used most first, related items grouped and separated;
        // then the rarely used items in the order of a Mac app menu: the Setup Guide (mostly at
        // first launch, Adam, 2026-10-31), About and Check for Updates, Settings, Quit. Labels in
        // title-style capitalization, with an ellipsis where a window asks for more.
        Button("Refresh Channels from TotalMix FX") { model.engine.refresh() }
        Divider()
        Button("Setup Guide…") { model.showSetup() }
        Button("About Performance Bridge") {
            Windows.show("about", title: "About Performance Bridge") { AboutView() }
        }
        #if canImport(Sparkle)
        Button("Check for Updates…") { AppUpdates.checkNow() }
        #endif
        Divider()
        Button("Settings…") { model.showSettings() }
            .keyboardShortcut(",")
        Divider()
        Button("Quit Performance Bridge") {
            model.engine.stop()
            NSApplication.shared.terminate(nil)
        }
        .keyboardShortcut("q")
    }

    private func label(for choice: HomeChoice) -> String {
        let mark = choice.output == model.status.homeSubmix ? "✓ " : "    "
        let roles = choice.roles.map(roleName).joined(separator: ", ")
        return roles.isEmpty ? "\(mark)\(choice.name)" : "\(mark)\(choice.name) (\(roles))"
    }

    private func roleName(_ role: MonitoringRole) -> String {
        switch role {
        case .mainOut: return "Main Out"
        case .mainOutB: return "Main Out B"
        case .phones1: return "Phones 1"
        case .phones2: return "Phones 2"
        case .phones3: return "Phones 3"
        case .phones4: return "Phones 4"
        case .cue: return "Cue"
        }
    }
}

#if canImport(Sparkle)
/// In-app updates through Sparkle: the updater starts at launch (scheduled checks follow the user's
/// choice, which Sparkle asks for on the second launch), and the menu can check at once.
@MainActor
enum AppUpdates {
    private static var controller: SPUStandardUpdaterController?

    /// Starts the updater, once.
    static func start() {
        if controller == nil {
            controller = SPUStandardUpdaterController(startingUpdater: true, updaterDelegate: nil,
                                                      userDriverDelegate: nil)
        }
    }

    /// Checks for an update now, showing Sparkle's window with the result.
    static func checkNow() {
        start()
        NSApplication.shared.activate(ignoringOtherApps: true)
        controller?.checkForUpdates(nil)
    }
}
#endif
