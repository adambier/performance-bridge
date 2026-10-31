// Performance Bridge: a first look at the menu-bar app (macOS only). Run it from the package with
// `swift run PerformanceBridge --in-port 7004 --out-port 9004`; quit `sbdev bridge` first, since both
// need TotalMix's outgoing port and the Roto-Control's MIDI ports. The released app will be built by
// make-app.sh instead.

import AppKit
import SwiftUI
import BridgeEngine
import TotalMixOSC
import SurfaceCore

@main
struct PerformanceBridgeApp: App {
    @StateObject private var model = BridgeModel()

    init() {
        NSApplication.shared.setActivationPolicy(.accessory)
    }

    var body: some Scene {
        MenuBarExtra {
            MenuContent(model: model)
                .tint(Brand.amber)
        } label: {
            Image(nsImage: Brand.menuBarImage)
                .accessibilityLabel("Performance Bridge")
        }
    }
}

/// The app's look: the icon's amber as its accent color, and the menu-bar glyph (a one-color
/// template image from Design/AppIcon, which macOS colors to suit the menu bar).
enum Brand {
    static let amber = Color(red: 1, green: 0xB1 / 255.0, blue: 0x3D / 255.0)

    static let menuBarImage: NSImage = {
        let image = Bundle.module.image(forResource: "MenuBarIcon")
            ?? NSImage(systemSymbolName: "slider.horizontal.3", accessibilityDescription: "Performance Bridge")
            ?? NSImage()
        image.isTemplate = true
        return image
    }()
}

/// The engine and its latest status, for the menu.
@MainActor
final class BridgeModel: ObservableObject {
    @Published var status = BridgeStatus()
    let engine: BridgeEngine

    init() {
        var settings = BridgeSettings()
        let arguments = CommandLine.arguments
        func port(_ option: String) -> UInt16? {
            guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
            return UInt16(arguments[index + 1])
        }
        if let port = port("--in-port") { settings.endpoint.incomingPort = port }
        if let port = port("--out-port") { settings.endpoint.outgoingPort = port }
        settings.playbacksOnNewPage = UserDefaults.standard.bool(forKey: "playbacksOnNewPage")
        engine = BridgeEngine(settings: settings)
        engine.onStatus = { [weak self] status in
            Task { @MainActor in self?.status = status }
        }
        do {
            try engine.start()
        } catch {
            status.error = "\(error)"
        }
    }
}

struct MenuContent: View {
    @ObservedObject var model: BridgeModel
    /// Whether the home submix menu offers every output, not only the monitoring outputs.
    @AppStorage("showAllOutputs") private var showAllOutputs = false
    /// Whether the first playback starts a new page on the surfaces.
    @AppStorage("playbacksOnNewPage") private var playbacksOnNewPage = false

    var body: some View {
        Text(model.status.totalMixAnswering ? "TotalMix FX: connected" : "TotalMix FX: no answer")
        Text(model.status.rotoConnected ? "Roto-Control: connected" : "Roto-Control: not connected")
        if let error = model.status.error {
            Text("Error: \(error)")
        }
        Divider()
        Menu("Home submix") {
            ForEach(model.status.monitoringOutputs, id: \.output) { choice in
                Button(label(for: choice)) { model.engine.setHomeSubmix(choice.output) }
            }
            if model.status.monitoringOutputs.isEmpty {
                Text("No monitoring outputs yet")
            }
            if showAllOutputs && !model.status.otherOutputs.isEmpty {
                Divider()
                Menu("Other outputs") {
                    ForEach(model.status.otherOutputs, id: \.output) { choice in
                        Button(label(for: choice)) { model.engine.setHomeSubmix(choice.output) }
                    }
                }
            }
            Divider()
            Toggle("Show all outputs", isOn: $showAllOutputs)
        }
        Toggle("Playbacks start on a new page", isOn: Binding(
            get: { playbacksOnNewPage },
            set: { on in
                playbacksOnNewPage = on
                model.engine.setPlaybacksOnNewPage(on)
            }))
        Button("Ask TotalMix FX for its state") { model.engine.refresh() }
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
