import Foundation

/// One argument of an OSC message.
///
/// The cases cover the OSC 1.0 core types (`i`, `f`, `s`, `b`) and the common nonstandard types
/// that TotalMix FX or other software may send (`T`, `F`, `N`, `h`, `d`). TotalMix's Global OSC
/// documentation says it sends floats and strings, and that it also accepts true/false and
/// integers where it expects a float.
public enum OSCArgument: Equatable, Sendable {
    /// `i`: 32-bit big-endian two's-complement integer.
    case int(Int32)
    /// `f`: 32-bit big-endian IEEE 754 float.
    case float(Float)
    /// `s`: ASCII string, null-terminated and padded to a multiple of four bytes.
    case string(String)
    /// `b`: blob, a 32-bit size followed by that many bytes, padded to a multiple of four bytes.
    case blob([UInt8])
    /// `T` or `F`: a Boolean carried in the type tag alone.
    case bool(Bool)
    /// `N`: nil, carried in the type tag alone.
    case null
    /// `h`: 64-bit big-endian integer.
    case int64(Int64)
    /// `d`: 64-bit big-endian IEEE 754 double.
    case double(Double)

    /// The type tag character for this argument.
    public var typeTag: Character {
        switch self {
        case .int: return "i"
        case .float: return "f"
        case .string: return "s"
        case .blob: return "b"
        case .bool(let value): return value ? "T" : "F"
        case .null: return "N"
        case .int64: return "h"
        case .double: return "d"
        }
    }

    /// The argument as a number, for receivers that accept any numeric form: an integer or a
    /// Boolean (1 or 0) is converted; a string, blob, or nil gives `nil`.
    public var numericValue: Double? {
        switch self {
        case .int(let value): return Double(value)
        case .float(let value): return Double(value)
        case .int64(let value): return Double(value)
        case .double(let value): return value
        case .bool(let value): return value ? 1 : 0
        case .string, .blob, .null: return nil
        }
    }

    /// The argument's text, if it is a string.
    public var stringValue: String? {
        if case .string(let value) = self { return value }
        return nil
    }
}

/// An OSC message: an address pattern and its arguments.
public struct OSCMessage: Equatable, Sendable {
    /// The address pattern, beginning with "/".
    public var address: String
    /// The arguments, in order.
    public var arguments: [OSCArgument]

    /// Makes a message.
    public init(_ address: String, _ arguments: [OSCArgument] = []) {
        self.address = address
        self.arguments = arguments
    }

    /// The address split at "/", without the empty part before the first "/".
    /// "/input/3/mute" gives ["input", "3", "mute"].
    public var addressParts: [String] {
        address.split(separator: "/", omittingEmptySubsequences: false).dropFirst().map(String.init)
    }
}

/// An OSC bundle: a time tag and the packets it holds.
public struct OSCBundle: Equatable, Sendable {
    /// The time tag that means "immediately" in OSC 1.0.
    public static let immediately: UInt64 = 1

    /// The NTP-format time tag (seconds since 1900 in the high 32 bits, fraction in the low 32).
    public var timeTag: UInt64
    /// The bundle's elements, each a message or a bundle.
    public var elements: [OSCPacket]

    /// Makes a bundle.
    public init(timeTag: UInt64 = OSCBundle.immediately, elements: [OSCPacket]) {
        self.timeTag = timeTag
        self.elements = elements
    }
}

/// An OSC packet: the content of one UDP datagram.
public indirect enum OSCPacket: Equatable, Sendable {
    case message(OSCMessage)
    case bundle(OSCBundle)

    /// Every message in the packet, with bundles flattened in order.
    public var messages: [OSCMessage] {
        switch self {
        case .message(let message): return [message]
        case .bundle(let bundle): return bundle.elements.flatMap(\.messages)
        }
    }
}
