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
/// neither should leave a standing red dot. So the mark shows for the port in use, TotalMix running
/// but silent for `attentionDelay` seconds, or a Roto-Control plugged in but not connected for
/// `attentionDelay` seconds.
///
/// - The port in use at launch: the window opens at once.
/// - TotalMix FX running but not answering for `totalMixDelay` seconds, when it has never answered
///   with these settings: the window opens. TotalMix not running is not a problem: starting
///   Performance Bridge first is normal.
/// - The Roto-Control found but its handshake not finished after `rotoDelay` seconds, when it has
///   never connected with this port name: the window opens. (Inference: another program, such as a
///   DAW's Roto-Control integration, has it.)
/// - TotalMix FX older than 2.1 (no Global OSC): the window opens at once, whatever worked before.
/// - A Roto-Control that isn't plugged in never opens the window.
///
/// Pure: the app passes the time, the engine's status, and whether TotalMix is running, and keeps
/// `totalMixWorked` and `rotoWorked` between launches for the current settings.
public struct SetupWatch: Sendable {
    /// Why the window opens.
    public enum Reason: Equatable, Sendable {
        /// Another program has the port TotalMix sends to.
        case portInUse
        /// TotalMix is running but has not answered.
        case totalMixNotAnswering
        /// The Roto-Control is plugged in but has not finished its handshake.
        case rotoHandshake
        /// TotalMix is older than 2.1, which has no Global OSC.
        case totalMixTooOld
    }

    /// How long TotalMix may run without answering before the window opens, in seconds.
    public static let totalMixDelay: Double = 30
    /// How long the Roto-Control's handshake may take before the window opens, in seconds.
    public static let rotoDelay: Double = 15
    /// How long TotalMix may be silent while running, or the Roto-Control unconnected while plugged
    /// in, before the menu-bar icon is marked, in seconds: long enough for a normal start.
    public static let attentionDelay: Double = 10

    /// Whether TotalMix has ever answered with the current settings.
    public private(set) var totalMixWorked: Bool
    /// Whether the Roto-Control has ever connected with the current port name.
    public private(set) var rotoWorked: Bool

    private var listenedThisLaunch = false
    private var silentSince: Double?
    private var rotoPendingSince: Double?
    private var opened = false

    /// A watch for a new launch, or for new settings, with what has worked before.
    public init(totalMixWorked: Bool, rotoWorked: Bool) {
        self.totalMixWorked = totalMixWorked
        self.rotoWorked = rotoWorked
    }

    /// Takes the latest status and returns a reason when the setup window should open now; at most
    /// once for the life of the watch.
    public mutating func update(status: BridgeStatus, totalMixRunning: Bool, now: Double,
                                totalMixTooOld: Bool = false) -> Reason? {
        guard status.running else { return nil }
        if status.listening { listenedThisLaunch = true }
        if status.totalMixAnswering { totalMixWorked = true }
        if status.rotoConnected { rotoWorked = true }
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
        }
        if reason != nil { opened = true }
        return reason
    }

    /// Whether the menu-bar icon should show its warning mark, as of the last `update`: the port is
    /// in use, TotalMix is running but has been silent for `attentionDelay` seconds, or the
    /// Roto-Control is plugged in but hasn't connected for `attentionDelay` seconds. TotalMix not
    /// running, or the Roto-Control unplugged, is idle, not a fault.
    public func needsAttention(status: BridgeStatus, now: Double) -> Bool {
        guard status.running else { return false }
        if !status.listening { return true }
        if let since = silentSince, now - since >= Self.attentionDelay { return true }
        if let since = rotoPendingSince, now - since >= Self.attentionDelay { return true }
        return false
    }
}
