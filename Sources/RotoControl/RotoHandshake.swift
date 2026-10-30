import Foundation

/// The host's side of the Roto-Control's handshake (docs/ROTO-CONTROL.md, section 3).
///
/// The host sends DAW STARTED, answers PING DAW with the DAW type it claims, and may send other
/// commands once the Roto-Control has sent ROTO-DAW CONNECTED. The Roto-Control also pings by
/// itself when it is plugged in, so a ping is answered in any state. A ping after CONNECTED is
/// taken to mean that the Roto-Control was restarted or plugged in again (an inference; the SysEx
/// doc does not say), so the handshake goes back to waiting for CONNECTED.
public struct RotoHandshake: Sendable {
    /// Where the handshake stands.
    public enum State: Equatable, Sendable {
        /// Nothing sent yet.
        case idle
        /// DAW STARTED sent; waiting for PING DAW.
        case waitingForPing
        /// DAW PING RESPONSE sent; waiting for ROTO-DAW CONNECTED.
        case waitingForConnected
        /// Connected: the host may send other commands.
        case connected
    }

    /// The DAW type sent in DAW PING RESPONSE.
    public let hostType: RotoHostType
    /// Where the handshake stands.
    public private(set) var state: State = .idle

    /// Makes a handshake that will claim `hostType`.
    public init(hostType: RotoHostType) {
        self.hostType = hostType
    }

    /// Whether the host may send commands other than the handshake's.
    public var isConnected: Bool { state == .connected }

    /// Starts, or restarts, the handshake: the messages to send now.
    public mutating func start() -> [RotoOutgoing] {
        state = .waitingForPing
        return [.dawStarted]
    }

    /// Takes a message from the Roto-Control and returns the handshake's answer, if any. Returns
    /// `true` in `justConnected` when this message completed the handshake.
    public mutating func handle(_ message: RotoIncoming) -> (reply: [RotoOutgoing], justConnected: Bool) {
        switch message {
        case .pingDAW:
            state = .waitingForConnected
            return ([.pingResponse(hostType)], false)
        case .connected:
            guard state == .waitingForConnected else { return ([], false) }
            state = .connected
            return ([], true)
        default:
            return ([], false)
        }
    }
}

/// Something the Roto-Control sent: a SysEx message or a control.
public enum RotoInput: Equatable, Sendable {
    /// A SysEx message.
    case message(RotoIncoming)
    /// A knob, switch, or touch.
    case control(RotoControlEvent)
}

/// Turns the raw MIDI bytes from the Roto-Control's port into `RotoInput`s, combining
/// `RotoMIDIParser` and `RotoControlDecoder`. SysEx from other makers, and channel messages other
/// than control changes, are dropped.
public struct RotoInputDecoder: Sendable {
    private var parser = RotoMIDIParser()
    private var controls = RotoControlDecoder()

    /// Makes a decoder with no partial message.
    public init() {}

    /// Feeds bytes as they arrive and returns what they complete.
    public mutating func feed<S: Sequence>(_ bytes: S) -> [RotoInput] where S.Element == UInt8 {
        parser.feed(bytes).compactMap { message -> RotoInput? in
            switch message {
            case .sysEx(let bytes):
                return RotoIncoming(sysEx: bytes).map { .message($0) }
            case .controlChange(let channel, let controller, let value):
                return controls.decode(channel: channel, controller: controller, value: value).map { .control($0) }
            case .other:
                return nil
            }
        }
    }
}
