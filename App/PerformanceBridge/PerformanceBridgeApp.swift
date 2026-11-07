// Performance Bridge: the menu-bar app (macOS only). Run it from the package with
// `swift run PerformanceBridge`, or `swift run PerformanceBridge --in-port 7004 --out-port 9004` to
// override the ports saved in Settings; quit `sbdev bridge` first, since both need TotalMix FX's
// outgoing port and the Roto-Control's MIDI ports. make-app.sh builds the app bundle, with Sparkle.
// The hardware controller is chosen in Settings → Connections. `--launch-control xl3`, `lc3`, or
// `lc3-sim` (`LaunchControlSetting(arguments:)`) overrides it, e.g., for the Launch Control 3's
// layout on an XL 3, which Settings doesn't offer.

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
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(MIDITransport)
import MIDITransport
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

/// The hardware controller the app uses: one at a time (Adam, 2026-11-01), in the order the menus
/// list them (Adam, 2026-11-04).
enum ControllerChoice: String, CaseIterable, Identifiable {
    /// Melbourne Instruments' Roto-Control.
    case roto
    /// OXI Instruments' E16.
    case e16
    /// Novation's Launch Control XL 3.
    case launchControlXL3
    /// Novation's Launch Control 3.
    case launchControl3

    var id: String { rawValue }

    /// The name the Settings menu shows.
    var title: String {
        switch self {
        case .roto: return "Roto-Control"
        case .e16: return "OXI E16"
        case .launchControlXL3: return LaunchControlModel.xl3.name
        case .launchControl3: return LaunchControlModel.lc3.name
        }
    }

    /// The Launch Control model, or `nil` for the others.
    var launchControl: LaunchControlModel? {
        switch self {
        case .roto, .e16: return nil
        case .launchControlXL3: return .xl3
        case .launchControl3: return .lc3
        }
    }

    /// The same hardware controller, as `DetectedController` names it.
    var detected: DetectedController {
        switch self {
        case .roto: return .roto
        case .e16: return .e16
        case .launchControlXL3: return .launchControl(.xl3)
        case .launchControl3: return .launchControl(.lc3)
        }
    }

    /// The choice for a hardware controller found plugged in.
    init(_ detected: DetectedController) {
        switch detected {
        case .roto: self = .roto
        case .e16: self = .e16
        case .launchControl(.xl3): self = .launchControlXL3
        case .launchControl(.lc3): self = .launchControl3
        }
    }
}

/// The settings kept between launches, in the user defaults.
struct SavedSettings: Equatable {
    var host = TotalMixEndpoint.standard.host
    var incomingPort = Int(TotalMixEndpoint.standard.incomingPort)
    var outgoingPort = Int(TotalMixEndpoint.standard.outgoingPort)
    /// The hardware controller. Its MIDI ports are found by their names, which are fixed for each
    /// model (Adam, 2026-11-02), so there is no port setting; port names saved by earlier builds
    /// are ignored.
    var controller = ControllerChoice.roto

    private enum Key {
        static let host = "totalMixHost"
        static let incomingPort = "totalMixIncomingPort"
        static let outgoingPort = "totalMixOutgoingPort"
        static let controller = "hardwareController"
    }

    static func load(_ defaults: UserDefaults = .standard) -> SavedSettings {
        var saved = SavedSettings()
        if let host = defaults.string(forKey: Key.host), !host.isEmpty { saved.host = host }
        if let port = defaults.object(forKey: Key.incomingPort) as? Int, SavedSettings.isPort(port) { saved.incomingPort = port }
        if let port = defaults.object(forKey: Key.outgoingPort) as? Int, SavedSettings.isPort(port) { saved.outgoingPort = port }
        if let raw = defaults.string(forKey: Key.controller), let choice = ControllerChoice(rawValue: raw) { saved.controller = choice }
        return saved
    }

    func save(_ defaults: UserDefaults = .standard) {
        defaults.set(host, forKey: Key.host)
        defaults.set(incomingPort, forKey: Key.incomingPort)
        defaults.set(outgoingPort, forKey: Key.outgoingPort)
        defaults.set(controller.rawValue, forKey: Key.controller)
    }

    static func isPort(_ value: Int) -> Bool { (1...65_535).contains(value) }

    /// Whether every field can be used.
    var isValid: Bool {
        !host.trimmingCharacters(in: .whitespaces).isEmpty && Self.isPort(incomingPort) && Self.isPort(outgoingPort)
            && incomingPort != outgoingPort
    }
}

/// The engine and its latest status, for the menu.
@MainActor
final class BridgeModel: ObservableObject {
    @Published var status = BridgeStatus()
    /// Whether the menu-bar icon shows its warning mark.
    @Published private(set) var needsAttention = false
    /// Whether TotalMix FX and the hardware controller in use are all connected (the menu-bar icon
    /// is dimmed otherwise).
    var allConnected: Bool {
        status.totalMixAnswering && (!status.rotoEnabled || status.rotoConnected)
            && (status.launchControlName == nil || status.launchControlConnected)
            && (!status.e16Enabled || status.e16Connected)
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
    /// Whether a Launch Control given on the command line (`--launch-control`) is used instead of
    /// the hardware controller chosen in Settings.
    let launchControlFromCommandLine = LaunchControlSetting(arguments: CommandLine.arguments) != nil

    private static let homeSubmixKey = "homeSubmix"
    /// The Launch Control's send rows, as output channels (−1 for none), saved when changed on the
    /// device.
    nonisolated private static let launchControlSendsKey = "launchControlSends"
    /// Whether a Launch Control shows levels by brightness (off by default; Adam, 2026-11-02).
    nonisolated private static let levelBrightnessKey = "launchControlLevelBrightness"

    /// Turns a Launch Control's level-by-brightness on or off: at once, and saved.
    func setLevelBrightness(_ on: Bool) {
        UserDefaults.standard.set(on, forKey: Self.levelBrightnessKey)
        engine.setLaunchControlLevelBrightness(on)
    }

    /// The E16's ring brightness, 0…1 (a must-have setting: full brightness is unusable in a dark
    /// room; Adam, 2026-11-04).
    nonisolated private static let e16BrightnessKey = "e16Brightness"

    /// Sets the E16's ring brightness: at once, and saved.
    func setE16Brightness(_ value: Double) {
        UserDefaults.standard.set(value, forKey: Self.e16BrightnessKey)
        engine.setE16Brightness(value)
    }

    /// The key for one layout's send rows: the XL 3 has two and the Launch Control 3 one (its top
    /// row, pan or a send), so they are kept apart (review of 2026-11-02). The XL 3's are under the
    /// key earlier builds used for both.
    nonisolated private static func sendsKey(_ layout: LaunchControlModel) -> String {
        layout == .xl3 ? launchControlSendsKey : launchControlSendsKey + " " + layout.rawValue
    }

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
        // Once now, so the Setup Guide's first page knows whether TotalMix FX is running: the timer
        // first fires after the window has opened (review of 1.0.2). No status has come from the
        // engine yet, so only a TotalMix FX older than 2.1 can be reported now.
        checkSetup()
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

    /// The app that was in front when the Novation button last brought TotalMix FX forward.
    private var appBeforeTotalMix: NSRunningApplication?

    /// Brings TotalMix FX to the front; if it is already there, goes back to the app that was in
    /// front before, or, if there is none to go back to, hides TotalMix FX so the next app comes
    /// forward (Adam, 2026-11-02).
    private func toggleTotalMix() {
        guard let totalMix = Self.runningTotalMix() else { return }
        if totalMix.isActive {
            if let previous = appBeforeTotalMix, !previous.isTerminated, previous != totalMix {
                previous.activate(options: [.activateIgnoringOtherApps])
            } else {
                totalMix.hide()
            }
            appBeforeTotalMix = nil
        } else {
            appBeforeTotalMix = NSWorkspace.shared.frontmostApplication
            totalMix.activate(options: [.activateIgnoringOtherApps])
        }
    }

    /// Set once a hardware controller has connected in this launch, or the user has applied
    /// Settings; until then the app chooses the hardware controller by itself (Adam, 2026-11-02:
    /// each launch starts over).
    private var controllerSettled = false
    /// The hardware controller the app last chose by itself, for the Settings window to follow.
    @Published private(set) var autoChosen: ControllerChoice?

    /// Until a hardware controller has connected in this launch, or the user has applied
    /// Settings: if the one chosen isn't plugged in and exactly one other is, chooses that one
    /// (Adam, 2026-11-02). Only the MIDI ports' names are read, so nothing is sent to a device
    /// until it is chosen. Not after that in the same launch, since a Launch Control taken over this
    /// way leaves a DAW's session with it (see AGENTS.md, section 3).
    private func chooseControllerIfNeeded() {
        guard !launchControlFromCommandLine, !controllerSettled else { return }
        if status.rotoConnected || status.launchControlConnected || status.e16Connected {
            controllerSettled = true
            return
        }
        var saved = SavedSettings.load()
        let found = DetectedController.found(among: MIDIConnection.sources(), rotoPortName: engine.settings.rotoPortName)
        guard let target = DetectedController.switchTarget(chosen: saved.controller.detected, found: found) else { return }
        let choice = ControllerChoice(target)
        print("Choosing the \(choice.title): it is plugged in and the \(saved.controller.title) isn’t")
        saved.controller = choice
        apply(saved, chosenByUser: false)
        autoChosen = choice
    }

    /// The keys under which "worked with these settings" is kept: TotalMix FX's host and ports, and the
    /// Roto-Control's port name, as the engine uses them.
    private var totalMixWorkedKey: String {
        let endpoint = engine.settings.endpoint
        return "totalMixWorked \(endpoint.host) \(endpoint.incomingPort) \(endpoint.outgoingPort)"
    }
    private var rotoWorkedKey: String { "rotoWorked \(engine.settings.rotoPortName)" }
    private var launchControlWorkedKey: String {
        let setting = engine.settings.launchControl
        return "launchControlWorked \(setting?.name ?? "")"
    }
    private var e16WorkedKey: String { "e16Worked \(engine.settings.e16PortName)" }

    /// A new watch for the engine's settings, with what has worked with them before.
    private func makeWatch() -> SetupWatch {
        SetupWatch(totalMixWorked: UserDefaults.standard.bool(forKey: totalMixWorkedKey),
                   rotoWorked: UserDefaults.standard.bool(forKey: rotoWorkedKey),
                   launchControlWorked: UserDefaults.standard.bool(forKey: launchControlWorkedKey),
                   e16Worked: UserDefaults.standard.bool(forKey: e16WorkedKey))
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
        if watch.launchControlWorked, engine.settings.launchControl != nil {
            UserDefaults.standard.set(true, forKey: launchControlWorkedKey)
        }
        if watch.e16Worked, engine.settings.e16Enabled { UserDefaults.standard.set(true, forKey: e16WorkedKey) }
        chooseControllerIfNeeded()
        let attention = watch.needsAttention(status: status, now: now)
        if attention != needsAttention { needsAttention = attention }
        if let reason {
            switch reason {
            case .portInUse: print("Opening setup: port \(engine.settings.endpoint.outgoingPort) is in use")
            case .totalMixNotAnswering: print("Opening setup: TotalMix FX is running but hasn't answered")
            case .rotoHandshake: print("Opening setup: the Roto-Control hasn't finished connecting")
            case .launchControlNotConnecting: print("Opening setup: the Launch Control hasn't entered DAW mode")
            case .e16NotConnecting: print("Opening setup: the OXI E16 hasn't entered Remote Mode")
            case .totalMixTooOld: print("Opening setup: TotalMix FX \(version ?? "") is older than 2.1")
            }
            fflush(stdout)
            showSetup(openFor: reason.stepID)
        }
    }

    /// TotalMix FX among the running apps, if it is running. Matched by name, since its bundle
    /// identifier hasn't been checked on a Mac (inference: it contains "totalmix", whatever the case).
    private static func runningTotalMix() -> NSRunningApplication? {
        NSWorkspace.shared.runningApplications.first { app in
            let names = [app.bundleIdentifier, app.localizedName].compactMap { $0?.lowercased() }
            return names.contains { $0.contains("totalmix") }
        }
    }

    /// A running app's version, read from its app bundle's Info.plist (read only; nothing of
    /// TotalMix FX's is written). Which key holds TotalMix FX's "2.10" hasn't been checked on a Mac, so
    /// the short version string is preferred and the build version is the fallback.
    private static func version(of app: NSRunningApplication) -> String? {
        guard let url = app.bundleURL, let info = Bundle(url: url)?.infoDictionary else { return nil }
        for key in ["CFBundleShortVersionString", "CFBundleVersion"] {
            if let text = info[key] as? String, TotalMixVersion(text) != nil { return text }
        }
        return nil
    }

    /// Opens the setup window, at the step `openFor` names (e.g., a problem's), or at the first
    /// step that isn't done.
    func showSetup(openFor: String? = nil) {
        // From the menu, an open guide stays on its page; a problem opens at its step.
        if openFor == nil, Windows.front("setup") { return }
        Windows.show("setup", title: "Performance Bridge Setup Guide") { SetupView(model: self, openFor: openFor) }
    }

    /// The engine's settings from the saved settings, the command line, and the menu's choices.
    private static func settings(_ saved: SavedSettings, overrides: (incoming: UInt16?, outgoing: UInt16?)) -> BridgeSettings {
        var settings = BridgeSettings()
        settings.endpoint = TotalMixEndpoint(host: saved.host.trimmingCharacters(in: .whitespaces),
                                             incomingPort: overrides.incoming ?? UInt16(saved.incomingPort),
                                             outgoingPort: overrides.outgoing ?? UInt16(saved.outgoingPort))
        settings.playbacksOnNewPage = UserDefaults.standard.bool(forKey: "playbacksOnNewPage")
        settings.layout = savedLayout()
        // Level and pan always go to Main Out (the Mix Output menu was dropped; Adam, 2026-11-01),
        // so a choice saved by an earlier build is ignored.
        UserDefaults.standard.removeObject(forKey: homeSubmixKey)
        // One hardware controller at a time: the one chosen in Settings, or a Launch Control from the
        // command line.
        settings.launchControl = LaunchControlSetting(arguments: CommandLine.arguments)
            ?? saved.controller.launchControl.map { LaunchControlSetting(layout: $0) }
        settings.e16Enabled = settings.launchControl == nil && saved.controller == .e16
        settings.rotoEnabled = settings.launchControl == nil && !settings.e16Enabled
        if let brightness = UserDefaults.standard.object(forKey: e16BrightnessKey) as? Double {
            settings.e16Brightness = min(max(brightness, 0), 1)
        }
        // The E16's layout, meters, and send rows: set from Terminal for now (`defaults write
        // org.biers.performancebridge e16FourChannelStrips -bool true`, `e16Meters -bool true`,
        // `e16Sends -array 2 4`); Settings gets them in phase 2.
        settings.e16FourChannelStrips = UserDefaults.standard.bool(forKey: "e16FourChannelStrips")
        settings.e16Meters = UserDefaults.standard.bool(forKey: "e16Meters")
        if let saved = UserDefaults.standard.array(forKey: "e16Sends") as? [Int] {
            settings.e16Sends = saved.map { $0 < 0 ? nil : $0 }
        }
        // Both layouts' send rows, so either can be set in Settings with no device connected.
        for layout in LaunchControlModel.allCases {
            if let saved = UserDefaults.standard.array(forKey: sendsKey(layout)) as? [Int] {
                settings.launchControlSends[layout] = saved.map { $0 < 0 ? nil : $0 }
            }
        }
        settings.launchControlLevelBrightness = UserDefaults.standard.bool(forKey: levelBrightnessKey)
        return settings
    }

    /// The key for the saved layout (channel order, new-page option, and labels), as JSON.
    nonisolated private static let layoutKey = "layout"

    /// The layout saved last, or the default (TotalMix FX's order and names). Earlier builds didn't
    /// save the order at all, so it went back to TotalMix FX's at every launch and every Apply.
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
        engine.onE16LayoutChange = { four in
            UserDefaults.standard.set(four, forKey: "e16FourChannelStrips")
        }
        engine.onLaunchControlSendsChange = { layout, outputs in
            UserDefaults.standard.set(outputs.map { $0 ?? -1 }, forKey: Self.sendsKey(layout))
        }
        // The Launch Control's Novation button brings TotalMix FX to the front, and with TotalMix FX
        // already in front goes back to the app that was (Adam, 2026-11-02).
        engine.onShowTotalMix = { [weak self] in
            Task { @MainActor in self?.toggleTotalMix() }
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

    /// Saves new settings and restarts the engine with them. Once the user applies Settings, the
    /// hardware controller they chose stays chosen for this launch.
    func apply(_ saved: SavedSettings, chosenByUser: Bool = true) {
        if chosenByUser { controllerSettled = true }
        saved.save()
        engine.stop()
        engine = BridgeEngine(settings: Self.settings(saved, overrides: portOverrides))
        status = BridgeStatus()
        watch = makeWatch()
        start()
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

    private var e16State: String {
        let status = model.status
        if status.e16Connected { return "Connected" }
        if status.e16Found { return "Connecting" }
        return "Not Found"
    }

    var body: some View {
        // Status only, always dimmed (Adam, 2026-10-31), as macOS's own menu bar menus show status
        // lines. The full reasons go to the log; the Setup Guide says what to do.
        Text("TotalMix FX: " + totalMixState)
        if model.status.rotoEnabled {
            Text("Roto-Control: " + rotoState)
        }
        if let name = model.status.launchControlName {
            Text(name + ": " + launchControlState)
        }
        if model.status.e16Enabled {
            Text("OXI E16: " + e16State)
        }
        // Only while it's off: mutes then do nothing in the audio (Adam, 2026-11-02). A TotalMix FX
        // state that can change between sessions, so a status line, not a fault mark.
        if model.status.muteMasterOff {
            Text("Mute Master: Off")
        }
        Divider()
        // Order (Apple's HIG, Menus): what is used most first, related items grouped and separated;
        // then the rarely used items in the order of a Mac app menu: the Setup Guide (mostly at
        // first launch, Adam, 2026-10-31), About and Check for Updates, Settings, Quit. Labels in
        // title-style capitalization, with an ellipsis where a window asks for more.
        Button("Refresh Channels from TotalMix FX") { model.engine.refresh() }
        Divider()
        Button("Setup Guide…") { model.showSetup() }
        Button("Controls Guide…") {
            Windows.show("controls", title: "Performance Bridge Controls Guide") { ControlsGuideView(model: model) }
        }
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
