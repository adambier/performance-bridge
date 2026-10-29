import Foundation

/// Why a datagram could not be read as OSC.
public enum OSCDecodeError: Error, Equatable, Sendable {
    /// The data ended before an element it announced.
    case truncated
    /// The packet neither starts with "/" (a message) nor with "#bundle" (a bundle).
    case notOSC
    /// A string was not terminated by a null byte, or was not valid UTF-8.
    case badString
    /// The type tag string does not start with ",".
    case missingTypeTags
    /// A type tag this decoder does not know; the arguments after it cannot be located.
    case unsupportedType(Character)
    /// A bundle element's declared size is negative or not a multiple of four.
    case badElementSize(Int32)
}

extension OSCPacket {
    /// The packet's bytes, as sent in one UDP datagram.
    public func encoded() -> [UInt8] {
        var writer = OSCWriter()
        writer.write(self)
        return writer.bytes
    }

    /// Reads one packet from the bytes of a datagram.
    public init(decoding bytes: [UInt8]) throws {
        var reader = OSCReader(bytes: bytes[...])
        self = try reader.readPacket()
    }

    /// Reads one packet from the bytes of a datagram.
    public init(decoding data: Data) throws {
        try self.init(decoding: [UInt8](data))
    }
}

extension OSCMessage {
    /// The message's bytes, as sent in one UDP datagram.
    public func encoded() -> [UInt8] {
        OSCPacket.message(self).encoded()
    }
}

// MARK: - Writing

struct OSCWriter {
    private(set) var bytes: [UInt8] = []

    mutating func write(_ packet: OSCPacket) {
        switch packet {
        case .message(let message):
            writeString(message.address)
            writeString("," + String(message.arguments.map(\.typeTag)))
            for argument in message.arguments { write(argument) }
        case .bundle(let bundle):
            writeString("#bundle")
            writeUInt64(bundle.timeTag)
            for element in bundle.elements {
                var inner = OSCWriter()
                inner.write(element)
                writeUInt32(UInt32(inner.bytes.count))
                bytes += inner.bytes
            }
        }
    }

    private mutating func write(_ argument: OSCArgument) {
        switch argument {
        case .int(let value): writeUInt32(UInt32(bitPattern: value))
        case .float(let value): writeUInt32(value.bitPattern)
        case .string(let value): writeString(value)
        case .blob(let value):
            writeUInt32(UInt32(value.count))
            bytes += value
            pad()
        case .bool, .null: break
        case .int64(let value): writeUInt64(UInt64(bitPattern: value))
        case .double(let value): writeUInt64(value.bitPattern)
        }
    }

    private mutating func writeString(_ string: String) {
        bytes += Array(string.utf8)
        bytes.append(0)
        pad()
    }

    private mutating func pad() {
        while bytes.count % 4 != 0 { bytes.append(0) }
    }

    private mutating func writeUInt32(_ value: UInt32) {
        for shift in stride(from: 24, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt32(shift))) }
    }

    private mutating func writeUInt64(_ value: UInt64) {
        for shift in stride(from: 56, through: 0, by: -8) { bytes.append(UInt8(truncatingIfNeeded: value >> UInt64(shift))) }
    }
}

// MARK: - Reading

struct OSCReader {
    private var bytes: ArraySlice<UInt8>

    init(bytes: ArraySlice<UInt8>) {
        self.bytes = bytes
    }

    mutating func readPacket() throws -> OSCPacket {
        guard let first = bytes.first else { throw OSCDecodeError.truncated }
        if first == UInt8(ascii: "/") {
            return .message(try readMessage())
        }
        if first == UInt8(ascii: "#") {
            let tag = try readString()
            guard tag == "#bundle" else { throw OSCDecodeError.notOSC }
            let timeTag = try readUInt64()
            var elements: [OSCPacket] = []
            while !bytes.isEmpty {
                let size = Int32(bitPattern: try readUInt32())
                guard size >= 0, size % 4 == 0 else { throw OSCDecodeError.badElementSize(size) }
                let count = Int(size)
                guard bytes.count >= count else { throw OSCDecodeError.truncated }
                let start = bytes.startIndex
                var inner = OSCReader(bytes: bytes[start..<start + count])
                elements.append(try inner.readPacket())
                bytes = bytes[(start + count)...]
            }
            return .bundle(OSCBundle(timeTag: timeTag, elements: elements))
        }
        throw OSCDecodeError.notOSC
    }

    private mutating func readMessage() throws -> OSCMessage {
        let address = try readString()
        // OSC 1.0 says a message without a type tag string should be accepted from older
        // implementations; such a message has no arguments this reader can locate.
        if bytes.isEmpty { return OSCMessage(address) }
        let tags = try readString()
        guard tags.first == "," else { throw OSCDecodeError.missingTypeTags }
        var arguments: [OSCArgument] = []
        for tag in tags.dropFirst() {
            switch tag {
            case "i": arguments.append(.int(Int32(bitPattern: try readUInt32())))
            case "f": arguments.append(.float(Float(bitPattern: try readUInt32())))
            case "s", "S": arguments.append(.string(try readString()))
            case "b":
                let size = Int(Int32(bitPattern: try readUInt32()))
                guard size >= 0, bytes.count >= size else { throw OSCDecodeError.truncated }
                let start = bytes.startIndex
                arguments.append(.blob(Array(bytes[start..<start + size])))
                bytes = bytes[(start + size)...]
                try skipPadding(after: size)
            case "T": arguments.append(.bool(true))
            case "F": arguments.append(.bool(false))
            case "N": arguments.append(.null)
            case "h": arguments.append(.int64(Int64(bitPattern: try readUInt64())))
            case "d": arguments.append(.double(Double(bitPattern: try readUInt64())))
            default: throw OSCDecodeError.unsupportedType(tag)
            }
        }
        return OSCMessage(address, arguments)
    }

    private mutating func readString() throws -> String {
        guard let end = bytes.firstIndex(of: 0) else { throw OSCDecodeError.badString }
        let start = bytes.startIndex
        guard let string = String(bytes: bytes[start..<end], encoding: .utf8) else { throw OSCDecodeError.badString }
        let length = end - start
        bytes = bytes[end...]
        // The string's null terminator and padding: 1 to 4 null bytes in all.
        let padded = (length / 4 + 1) * 4
        let remaining = padded - length
        guard bytes.count >= remaining else { throw OSCDecodeError.truncated }
        bytes = bytes.dropFirst(remaining)
        return string
    }

    private mutating func skipPadding(after length: Int) throws {
        let padding = (4 - length % 4) % 4
        guard bytes.count >= padding else { throw OSCDecodeError.truncated }
        bytes = bytes.dropFirst(padding)
    }

    private mutating func readUInt32() throws -> UInt32 {
        guard bytes.count >= 4 else { throw OSCDecodeError.truncated }
        var value: UInt32 = 0
        for byte in bytes.prefix(4) { value = value << 8 | UInt32(byte) }
        bytes = bytes.dropFirst(4)
        return value
    }

    private mutating func readUInt64() throws -> UInt64 {
        guard bytes.count >= 8 else { throw OSCDecodeError.truncated }
        var value: UInt64 = 0
        for byte in bytes.prefix(8) { value = value << 8 | UInt64(byte) }
        bytes = bytes.dropFirst(8)
        return value
    }
}
