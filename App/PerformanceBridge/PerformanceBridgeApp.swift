// Performance Bridge: the menu-bar app (macOS only). Run it from the package with
// `swift run PerformanceBridge`, or `swift run PerformanceBridge --in-port 7004 --out-port 9004` to
// override the ports saved in Settings; quit `sbdev bridge` first, since both need TotalMix's
// outgoing port and the Roto-Control's MIDI ports. make-app.sh builds the app bundle, with Sparkle.

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
                .tint(Brand.amber)
        } label: {
            // The attention image is drawn in color, so it must not be rendered as a template.
            Image(nsImage: model.needsAttention ? Brand.menuBarAttentionImage : Brand.menuBarImage)
                .renderingMode(model.needsAttention ? .original : .template)
                .accessibilityLabel(model.needsAttention ? "Performance Bridge, needs attention" : "Performance Bridge")
        }
    }
}

/// The app's look: the icon's amber as its accent color, and the menu-bar glyph (a one-color
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

    /// The menu-bar glyph with a red dot at its lower right, cut free of the glyph, for a
    /// connection that needs attention (SetupWatch.needsAttention). A template image is one color,
    /// so this one is not a template: the glyph is drawn in the label color and the dot in the
    /// system red, both resolved for the appearance it is drawn in (light or dark menu bar).
    /// (Adam, 2026-10-31: red, since it reads as a problem, and amber is close to macOS's orange
    /// microphone dot.)
    static let menuBarAttentionImage: NSImage = {
        let base = menuBarImage
        let image = NSImage(size: base.size, flipped: false) { rect in
            base.draw(in: rect)
            NSColor.labelColor.setFill()
            rect.fill(using: .sourceAtop)   // the glyph's shape, in the menu bar's text color
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
        Windows.show("setup", title: "Set Up Performance Bridge") { SetupView(model: self) }
    }

    /// The engine's settings from the saved settings, the command line, and the menu's choices.
    private static func settings(_ saved: SavedSettings, overrides: (incoming: UInt16?, outgoing: UInt16?)) -> BridgeSettings {
        var settings = BridgeSettings()
        settings.endpoint = TotalMixEndpoint(host: saved.host.trimmingCharacters(in: .whitespaces),
                                             incomingPort: overrides.incoming ?? UInt16(saved.incomingPort),
                                             outgoingPort: overrides.outgoing ?? UInt16(saved.outgoingPort))
        settings.rotoPortName = saved.rotoPortName.trimmingCharacters(in: .whitespaces)
        settings.playbacksOnNewPage = UserDefaults.standard.bool(forKey: "playbacksOnNewPage")
        settings.homeSubmix = UserDefaults.standard.object(forKey: homeSubmixKey) as? Int
        return settings
    }

    private func start() {
        let engine = self.engine
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
    /// Whether the home submix menu offers every output, not only the monitoring outputs.
    @AppStorage("showAllOutputs") private var showAllOutputs = false
    /// Whether the first playback starts a new page on the surfaces.

    private var totalMixState: String {
        let status = model.status
        if status.totalMixAnswering { return "connected" }
        if !status.listening { return "port \(model.engine.settings.endpoint.outgoingPort) in use, retrying" }
        return "no answer"
    }

    private var rotoState: String {
        let status = model.status
        if status.rotoConnected { return "connected" }
        if status.rotoFound { return "connecting" }
        return "not found, retrying"
    }

    var body: some View {
        // Short lines: a menu cuts long ones in the middle. The full reasons go to the log.
        // The status lines open the setup window, which says what to do about either.
        Button("TotalMix FX: " + totalMixState) { model.showSetup() }
        Button("Roto-Control: " + rotoState) { model.showSetup() }
        Divider()
        Menu("Home submix") {
            ForEach(model.status.monitoringOutputs, id: \.output) { choice in
                Button(label(for: choice)) { model.setHomeSubmix(choice.output) }
            }
            if model.status.monitoringOutputs.isEmpty {
                Text("No monitoring outputs yet")
            }
            if showAllOutputs && !model.status.otherOutputs.isEmpty {
                Divider()
                Menu("Other outputs") {
                    ForEach(model.status.otherOutputs, id: \.output) { choice in
                        Button(label(for: choice)) { model.setHomeSubmix(choice.output) }
                    }
                }
            }
            Divider()
            Toggle("Show all outputs", isOn: $showAllOutputs)
            Divider()
            // Choosing Main Out's output saves "follow Main Out" (BridgeModel.setHomeSubmix), so
            // the home moves when Main Out is reassigned in TotalMix. Said here so it isn't
            // mistaken for a bug.
            Text("Main Out follows TotalMix's assignment")
        }
        Button("Ask TotalMix FX for its state") { model.engine.refresh() }
        Divider()
        Button("Layout…") {
            Windows.show("layout", title: "Performance Bridge Layout") { LayoutView(model: model) }
        }
        Button("Setup…") { model.showSetup() }
        Button("About Performance Bridge") {
            Windows.show("about", title: "About Performance Bridge") { AboutView() }
        }
        #if canImport(Sparkle)
        Button("Check for Updates…") { AppUpdates.checkNow() }
        #endif
        Button("Settings…") {
            Windows.show("settings", title: "Performance Bridge Settings") { SettingsView(model: model) }
        }
        .keyboardShortcut(",")
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
