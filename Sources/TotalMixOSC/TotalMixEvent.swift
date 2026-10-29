import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif

/// A value TotalMix sent: a number, a text, or nothing.
public enum TotalMixValue: Equatable, Sendable, CustomStringConvertible {
    case number(Double)
    case text(String)
    case none

    /// The value from a message's first argument.
    public init(_ arguments: [OSCArgument]) {
        guard let first = arguments.first else { self = .none; return }
        if let number = first.numericValue { self = .number(number) }
        else if let text = first.stringValue { self = .text(text) }
        else { self = .none }
    }

    /// The number, if the value is one.
    public var number: Double? {
        if case .number(let value) = self { return value }
        return nil
    }

    public var description: String {
        switch self {
        case .number(let value): return String(format: "%g", value)
        case .text(let text): return "\"\(text)\""
        case .none: return "(no value)"
        }
    }
}

/// What a snapshot message from TotalMix reports.
public enum SnapshotState: Int, Sendable {
    case off = 0
    case active = 2
    case changed = 3
}

/// A message from TotalMix's Global OSC, sorted by what it is about.
public enum TotalMixEvent: Equatable, Sendable {
    /// A channel setting: `/input|playback|output/<channel>/<parameter>`. `parameter` keeps any
    /// sub-path, e.g. `eq/band1gain`.
    case channel(bus: TotalMixBus, channel: Int, parameter: String, value: TotalMixValue)
    /// A mixer node: `/mix/in|pb/<source>/<output>/<parameter>`.
    case mix(bus: TotalMixBus, channel: Int, output: Int, parameter: String, value: TotalMixValue)
    /// A peak level in dB: `/level/in|pb|out/<channel>`.
    case level(bus: TotalMixBus, channel: Int, peakDB: Double)
    /// A snapshot's state: `/snapshot/load/<number>`.
    case snapshot(number: Int, state: SnapshotState)
    /// Anything else TotalMix sends (control room, FX, DURec, status, global mute and solo), by its
    /// path without the leading "/".
    case other(path: String, value: TotalMixValue)

    /// Sorts a message. Returns `nil` only for an address that cannot be TotalMix's (no parts).
    public init?(_ message: OSCMessage) {
        let parts = message.addressParts
        guard let head = parts.first, !head.isEmpty else { return nil }
        let value = TotalMixValue(message.arguments)

        if let bus = TotalMixBus(word: head), bus.settingsName == head,
           parts.count >= 3, let channel = Int(parts[1]) {
            self = .channel(bus: bus, channel: channel, parameter: parts[2...].joined(separator: "/"), value: value)
            return
        }
        if head == "mix", parts.count == 5, let bus = TotalMixBus(word: parts[1]), bus.mixName == parts[1],
           let channel = Int(parts[2]), let output = Int(parts[3]) {
            self = .mix(bus: bus, channel: channel, output: output, parameter: parts[4], value: value)
            return
        }
        if head == "level", parts.count == 3, let bus = TotalMixBus(word: parts[1]), bus.levelName == parts[1],
           let channel = Int(parts[2]), let peak = value.number {
            self = .level(bus: bus, channel: channel, peakDB: peak)
            return
        }
        if head == "snapshot", parts.count == 3, parts[1] == "load", let number = Int(parts[2]),
           let raw = value.number, let state = SnapshotState(rawValue: Int(raw)) {
            self = .snapshot(number: number, state: state)
            return
        }
        self = .other(path: parts.joined(separator: "/"), value: value)
    }
}
