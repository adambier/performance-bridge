import Foundation
#if canImport(CoreMIDI)
import CoreMIDI
#endif

#if canImport(CoreMIDI)

/// A pair of virtual MIDI ports that this program publishes under a name of its choosing: a
/// virtual destination, which other programs can send to, and a virtual source, which other
/// programs can listen to. Other programs see them as they would a device's ports.
///
/// Made for finding out what a program sends to a controller it knows by its port name (`sbdev
/// vport`). Bytes other programs send to the destination arrive on CoreMIDI's own thread, as MIDI
/// 1.0 bytes; a SysEx message may arrive in several pieces. `send` may be called from any thread,
/// but not while `close` runs.
public final class VirtualMIDIPort: @unchecked Sendable {
    /// The name both ports were published under.
    public let name: String

    private var client = MIDIClientRef()
    private var virtualSource = MIDIEndpointRef()
    private var virtualDestination = MIDIEndpointRef()

    /// Publishes a virtual source and a virtual destination, both named `name`, and starts
    /// delivering the bytes other programs send to the destination to `receive`.
    public init(clientName: String, name: String, receive: @escaping @Sendable ([UInt8]) -> Void) throws {
        self.name = name
        try Self.check("MIDIClientCreateWithBlock", MIDIClientCreateWithBlock(clientName as CFString, &client, nil))
        try Self.check("MIDIDestinationCreateWithProtocol",
                       MIDIDestinationCreateWithProtocol(client, name as CFString, ._1_0, &virtualDestination) { list, _ in
            var words: [UInt32] = []
            for packet in list.unsafeSequence() {
                let count = Int(packet.pointee.wordCount)
                let offset = MemoryLayout<MIDIEventPacket>.offset(of: \MIDIEventPacket.words) ?? 12
                let start = UnsafeRawPointer(packet).advanced(by: offset)
                words.append(contentsOf: UnsafeBufferPointer(start: start.assumingMemoryBound(to: UInt32.self), count: count))
            }
            let bytes = UniversalPackets.bytes(fromWords: words)
            if !bytes.isEmpty { receive(bytes) }
        })
        try Self.check("MIDISourceCreateWithProtocol",
                       MIDISourceCreateWithProtocol(client, name as CFString, ._1_0, &virtualSource))
    }

    deinit { close() }

    /// Sends complete MIDI 1.0 messages out of the virtual source, as a device would send them:
    /// every program listening to the source receives them (see `UniversalPackets.words(fromBytes:)`).
    public func send(_ bytes: [UInt8]) throws {
        let words = UniversalPackets.words(fromBytes: bytes)
        guard !words.isEmpty else { return }
        // At most one packet per word, each with a header of 12 bytes or less: a strict bound.
        let size = MemoryLayout<MIDIEventList>.size + words.count * 16
        let buffer = UnsafeMutableRawPointer.allocate(byteCount: size, alignment: 8)
        defer { buffer.deallocate() }
        let list = buffer.bindMemory(to: MIDIEventList.self, capacity: 1)
        var packet: UnsafeMutablePointer<MIDIEventPacket>? = MIDIEventListInit(list, ._1_0)
        for chunk in UniversalPackets.packets(words) {
            let packetWords = Array(chunk)
            packet = packetWords.withUnsafeBufferPointer { MIDIEventListAdd(list, size, packet!, 0, packetWords.count, $0.baseAddress!) }
            guard packet != nil else { throw MIDIConnectionError.coreMIDI(call: "MIDIEventListAdd", status: -1) }
        }
        try Self.check("MIDIReceivedEventList", MIDIReceivedEventList(virtualSource, list))
    }

    /// Removes both ports from the system and closes the client.
    public func close() {
        if virtualSource != 0 { MIDIEndpointDispose(virtualSource); virtualSource = 0 }
        if virtualDestination != 0 { MIDIEndpointDispose(virtualDestination); virtualDestination = 0 }
        if client != 0 { MIDIClientDispose(client); client = 0 }
    }

    private static func check(_ call: String, _ status: OSStatus) throws {
        guard status == noErr else { throw MIDIConnectionError.coreMIDI(call: call, status: status) }
    }
}

#else

/// A pair of virtual MIDI ports. Only implemented on macOS; elsewhere it throws.
public final class VirtualMIDIPort: @unchecked Sendable {
    /// The name both ports were to be published under.
    public let name: String

    /// Throws `MIDIConnectionError.unsupportedPlatform`.
    public init(clientName: String, name: String, receive: @escaping @Sendable ([UInt8]) -> Void) throws {
        self.name = name
        throw MIDIConnectionError.unsupportedPlatform
    }

    /// Throws `MIDIConnectionError.unsupportedPlatform`.
    public func send(_ bytes: [UInt8]) throws { throw MIDIConnectionError.unsupportedPlatform }

    /// Does nothing on this platform.
    public func close() {}
}

#endif
