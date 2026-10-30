import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif

/// Thins continuous messages to TotalMix: at most one per address per interval, and the latest
/// value always goes out. TotalMix updates on a 20 ms cycle (docs/TOTALMIX-OSC.md, tests 1 and 3),
/// so sending faster than that adds load and nothing else (an inference).
public struct OutgoingThinner: Sendable {
    /// The shortest time between two messages to one address, in seconds.
    public var interval: Double
    private var lastSent: [String: Double] = [:]
    private var pending: [String: OSCMessage] = [:]
    private var pendingOrder: [String] = []

    /// A thinner; the default interval is TotalMix's 20 ms cycle.
    public init(interval: Double = 0.02) {
        self.interval = interval
    }

    /// Offers a message at time `now` (seconds). Returns it if it may go now; otherwise keeps it,
    /// replacing any message kept earlier for the same address, until `flush(now:)`.
    public mutating func offer(_ message: OSCMessage, now: Double) -> OSCMessage? {
        let address = message.address
        if let last = lastSent[address], now - last < interval {
            if pending[address] == nil { pendingOrder.append(address) }
            pending[address] = message
            return nil
        }
        lastSent[address] = now
        if pending.removeValue(forKey: address) != nil { pendingOrder.removeAll { $0 == address } }
        return message
    }

    /// The kept messages whose interval has passed, oldest address first.
    public mutating func flush(now: Double) -> [OSCMessage] {
        var ready: [OSCMessage] = []
        var waiting: [String] = []
        for address in pendingOrder {
            guard let message = pending[address] else { continue }
            if let last = lastSent[address], now - last < interval {
                waiting.append(address)
                continue
            }
            ready.append(message)
            lastSent[address] = now
            pending[address] = nil
        }
        pendingOrder = waiting
        return ready
    }

    /// Whether any message is waiting.
    public var hasPending: Bool { !pending.isEmpty }
}

/// Whether a strip's control is in the user's hand, so that values from TotalMix must not move it.
/// A control is held while touched, and for a short time after it last moved, because the
/// Roto-Control's touch sensing has been observed to be unreliable (docs/ROTO-CONTROL.md).
public struct ControlHold: Hashable, Sendable {
    /// How long a control stays held after its last move, in seconds.
    public static let moveWindow: Double = 0.25

    /// Whether the surface reports the control as touched.
    public var touched = false
    /// When the control last moved, in seconds.
    public var lastMove: Double?

    /// A control not held.
    public init() {}

    /// Whether the control is held at time `now`.
    public func isHeld(now: Double) -> Bool {
        if touched { return true }
        guard let lastMove else { return false }
        return now - lastMove < Self.moveWindow
    }
}

/// The rule for a control without a motor ("pickup"): after TotalMix's value has changed, moves
/// are ignored until the control reaches the value, or crosses it.
public enum Pickup {
    /// Whether a move from `previous` to `position` picks up `target` (all 0…1). `previous` is
    /// `nil` when the control's position is unknown.
    public static func catches(target: Double, previous: Double?, position: Double, window: Double) -> Bool {
        if abs(position - target) <= window { return true }
        guard let previous else { return false }
        return (previous - target) * (position - target) <= 0
    }
}
