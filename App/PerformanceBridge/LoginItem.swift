// Opening Performance Bridge at login (Adam, 2026-11-10): off until the user turns it on, in
// Settings → Connections or on the Setup Guide's last page. macOS 13's SMAppService registers the
// app itself as a login item; there is no helper app and nothing written to another app's files.
// macOS lists the app in System Settings → General → Login Items, where the user can also turn it
// off, so the app reads the state back from macOS rather than keeping a setting of its own. (That
// pane is "Login Items & Extensions" from macOS 15, an inference not yet checked on screen; the
// app's text says "Login Items" and its button opens the pane, whatever its name.)

import AppKit
import ServiceManagement
import SwiftUI

/// Whether Performance Bridge opens at login, as macOS has it.
enum LoginItemState: Equatable {
    /// Not registered: the default.
    case off
    /// Registered and allowed: the app opens at login.
    case on
    /// Registered, but turned off in System Settings → General → Login Items; macOS won't open the
    /// app until the user allows it there.
    case needsApproval
    /// The app can't register itself: it isn't running from an app bundle (e.g., `swift run`).
    case unavailable

    /// The state SMAppService reports for this app.
    static var current: LoginItemState {
        guard Bundle.main.bundleURL.pathExtension == "app" else { return .unavailable }
        switch SMAppService.mainApp.status {
        case .enabled: return .on
        case .requiresApproval: return .needsApproval
        case .notRegistered, .notFound: return .off
        @unknown default: return .off
        }
    }
}

extension BridgeModel {
    /// Reads the login item's state from macOS again: when Settings or the Setup Guide shows it,
    /// and when the app becomes active, since the user can change it in System Settings.
    func refreshLoginItem() {
        let state = LoginItemState.current
        if loginItem != state { loginItem = state }
    }

    /// Turns opening at login on or off. macOS shows its own notice when an app adds a login item.
    func setOpenAtLogin(_ on: Bool) {
        loginItemError = nil
        do {
            if on {
                try SMAppService.mainApp.register()
            } else {
                try SMAppService.mainApp.unregister()
            }
        } catch {
            loginItemError = error.localizedDescription
        }
        refreshLoginItem()
    }
}

/// The "Open at login" checkbox, with a note when macOS needs the user's approval or refused. Used
/// at the bottom of Settings → Connections and on the Setup Guide's last page.
struct OpenAtLoginToggle: View {
    @ObservedObject var model: BridgeModel

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Toggle("Open Performance Bridge at login", isOn: Binding(
                get: { model.loginItem == .on || model.loginItem == .needsApproval },
                set: { model.setOpenAtLogin($0) }))
                .disabled(model.loginItem == .unavailable)
            if model.loginItem == .needsApproval {
                note("Performance Bridge is turned off in the Login Items of System Settings. Turn it on there to open it at login.")
                Button("Open Login Items Settings…") { SMAppService.openSystemSettingsLoginItems() }
            } else if model.loginItem == .unavailable {
                note("Opening at login needs the app itself, not a build run from Terminal.")
            }
            if let error = model.loginItemError {
                note("macOS didn’t allow it: \(error)")
            }
        }
        .onAppear { model.refreshLoginItem() }
        .onReceive(NotificationCenter.default.publisher(for: NSApplication.didBecomeActiveNotification)) { _ in
            model.refreshLoginItem()
        }
    }

    private func note(_ text: String) -> some View {
        Text(text)
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
    }
}
