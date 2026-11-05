import Foundation

/// When the app opens its setup window by itself, and when its menu-bar icon shows a warning mark.
///
/// The rule (Adam, 2026-10-31): the window opens by itself only for something that has never worked
/// with the current settings, at most once per launch, because a window that takes the focus during
/// a performance is worse than a missed hint. Once a connection has worked, a fault only marks the
/// menu-bar icon.
///
/// The mark is for faults only, not for idle states (Adam, 2026-10-31): the app may run all the
/// time, with TotalMix FX closed or the Roto-Control unplugged while the mixer isn't in use, and
/// neither should leave a standing red dot. So the mark shows for the port in use, TotalMix FX running
/// but silent for `attentionDelay` seconds, or a Roto-Control or Launch Control plugged in but not
/// connected for `attentionDelay` seconds.
///
/// - The port in use at launch: the window opens at once.
/// - TotalMix FX running but not answering for `totalMixDelay` seconds, when it has never answered
///   with these settings: the window opens. TotalMix FX not running is not a problem: starting
///   Performance Bridge first is normal.
/// - The Roto-Control found but its handshake not finished after `rotoDelay` seconds, when it has
///   never connected with this port name: the window opens. (Inference: another program, such as a
///   DAW's Roto-Control integration, has it.)
/// - The Launch Control found but not in DAW mode after `rotoDelay` seconds, when it has never
///   connected with these settings: the window opens.
/// - The OXI E16 found but not in Remote Mode after `rotoDelay` seconds, when it has never
///   connected: the window opens.
/// - TotalMix FX older than 2.1 (no Global OSC): the window opens at once, whatever worked before.
/// - A Roto-Control that isn't plugged in never opens the window.
///
/// Pure: the app passes the time, the engine's status, and whether TotalMix FX is running, and keeps
/// `totalMixWorked`, `rotoWorked`, and `launchControlWorked` between launches for the current
/// settings.
public struct SetupWatch: Sendable {
    /// Why the window opens.
    public enum Reason: Equatable, Sendable {
        /// Another program has the port TotalMix FX sends to.
        case portInUse
        /// TotalMix FX is running but has not answered.
        case totalMixNotAnswering
        /// The Roto-Control is plugged in but has not finished its handshake.
        case rotoHandshake
        /// The Launch Control is plugged in but has not entered DAW mode.
        case launchControlNotConnecting
        /// The OXI E16 is plugged in but has not entered Remote Mode.
        case e16NotConnecting
        /// TotalMix FX is older than 2.1, which has no Global OSC.
        case totalMixTooOld

        /// The setup step (`SetupStep.id`) the window opens at for this reason.
        public var stepID: String {
            switch self {
            case .portInUse: return "port"
            case .totalMixNotAnswering: return "totalmix"
            case .rotoHandshake: return "roto"
            case .launchControlNotConnecting: return "launchcontrol"
            case .e16NotConnecting: return "e16"
            case .totalMixTooOld: return "version"
            }
        }
    }

    /// How long TotalMix FX may run without answering before the window opens, in seconds.
    public static let totalMixDelay: Double = 30
    /// How long the Roto-Control's handshake may take before the window opens, in seconds.
    public static let rotoDelay: Double = 15
    /// How long TotalMix FX may be silent while running, or the Roto-Control unconnected while plugged
    /// in, before the menu-bar icon is marked, in seconds: long enough for a normal start.
    public static let attentionDelay: Double = 10

    /// Whether TotalMix FX has ever answered with the current settings.
    public private(set) var totalMixWorked: Bool
    /// Whether the Roto-Control has ever connected with the current port name.
    public private(set) var rotoWorked: Bool
    /// Whether the Launch Control has ever connected with the current settings.
    public private(set) var launchControlWorked: Bool
    /// Whether the OXI E16 has ever connected.
    public private(set) var e16Worked: Bool

    private var listenedThisLaunch = false
    private var silentSince: Double?
    private var rotoPendingSince: Double?
    /// Since when the Launch Control has been plugged in but not in DAW mode.
    private var launchControlPendingSince: Double?
    /// Since when the E16 has been plugged in but not in Remote Mode.
    private var e16PendingSince: Double?
    private var opened = false

    /// A watch for a new launch, or for new settings, with what has worked before.
    public init(totalMixWorked: Bool, rotoWorked: Bool, launchControlWorked: Bool = false, e16Worked: Bool = false) {
        self.totalMixWorked = totalMixWorked
        self.rotoWorked = rotoWorked
        self.launchControlWorked = launchControlWorked
        self.e16Worked = e16Worked
    }

    /// Takes the latest status and returns a reason when the setup window should open now; at most
    /// once for the life of the watch.
    public mutating func update(status: BridgeStatus, totalMixRunning: Bool, now: Double,
                                totalMixTooOld: Bool = false) -> Reason? {
        guard status.running else { return nil }
        if status.listening { listenedThisLaunch = true }
        if status.totalMixAnswering { totalMixWorked = true }
        if status.rotoConnected { rotoWorked = true }
        if status.launchControlConnected { launchControlWorked = true }
        if status.e16Connected { e16Worked = true }
        if status.listening, totalMixRunning, !status.totalMixAnswering {
            silentSince = silentSince ?? now
        } else {
            silentSince = nil
        }
        if status.rotoFound, !status.rotoConnected {
            rotoPendingSince = rotoPendingSince ?? now
        } else {
            rotoPendingSince = nil
        }
        if status.launchControlFound, !status.launchControlConnected {
            launchControlPendingSince = launchControlPendingSince ?? now
        } else {
            launchControlPendingSince = nil
        }
        if status.e16Found, !status.e16Connected {
            e16PendingSince = e16PendingSince ?? now
        } else {
            e16PendingSince = nil
        }

        guard !opened else { return nil }
        var reason: Reason?
        if totalMixRunning, totalMixTooOld {
            reason = .totalMixTooOld
        } else if !status.listening, !listenedThisLaunch {
            reason = .portInUse
        } else if let since = silentSince, !totalMixWorked, now - since >= Self.totalMixDelay {
            reason = .totalMixNotAnswering
        } else if let since = rotoPendingSince, !rotoWorked, now - since >= Self.rotoDelay {
            reason = .rotoHandshake
        } else if let since = launchControlPendingSince, !launchControlWorked, now - since >= Self.rotoDelay {
            // The same wait as the Roto-Control's handshake.
            reason = .launchControlNotConnecting
        } else if let since = e16PendingSince, !e16Worked, now - since >= Self.rotoDelay {
            reason = .e16NotConnecting
        }
        if reason != nil { opened = true }
        return reason
    }

    /// Whether the menu-bar icon should show its warning mark, as of the last `update`: the port is
    /// in use, TotalMix FX is running but has been silent for `attentionDelay` seconds, or the
    /// Roto-Control or the Launch Control is plugged in but hasn't connected for `attentionDelay`
    /// seconds. TotalMix FX not running, or a hardware controller unplugged, is idle, not a fault.
    public func needsAttention(status: BridgeStatus, now: Double) -> Bool {
        guard status.running else { return false }
        if !status.listening { return true }
        if let since = silentSince, now - since >= Self.attentionDelay { return true }
        if let since = rotoPendingSince, now - since >= Self.attentionDelay { return true }
        if let since = launchControlPendingSince, now - since >= Self.attentionDelay { return true }
        if let since = e16PendingSince, now - since >= Self.attentionDelay { return true }
        return false
    }
}
