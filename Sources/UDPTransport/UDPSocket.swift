import Foundation
#if canImport(Darwin)
import Darwin
#elseif canImport(Glibc)
import Glibc
#endif

/// Why a UDP socket could not be opened or used.
public enum UDPError: Error, Equatable, CustomStringConvertible {
    /// `socket()` failed.
    case socketFailed(errno: Int32)
    /// `bind()` failed, usually because another program already listens on the port.
    case bindFailed(port: UInt16, errno: Int32)
    /// The host name did not resolve to an IPv4 address.
    case hostNotFound(String)
    /// `sendto()` failed.
    case sendFailed(errno: Int32)
    /// UDP is not implemented on this platform yet.
    case unsupportedPlatform

    public var description: String {
        switch self {
        case .socketFailed(let code): return "Could not open a UDP socket (\(UDPError.message(code)))."
        case .bindFailed(let port, let code): return "Could not listen on UDP port \(port) (\(UDPError.message(code))). Another program may be using it."
        case .hostNotFound(let host): return "Could not find an IPv4 address for \"\(host)\"."
        case .sendFailed(let code): return "Could not send a UDP datagram (\(UDPError.message(code)))."
        case .unsupportedPlatform: return "UDP is not implemented on this platform yet."
        }
    }

    static func message(_ code: Int32) -> String {
        #if canImport(Darwin) || canImport(Glibc)
        return String(cString: strerror(code))
        #else
        return "error \(code)"
        #endif
    }
}

#if canImport(Darwin) || canImport(Glibc)

/// A UDP socket that listens on one port and sends datagrams to a host and port.
///
/// IPv4 only: "localhost" resolves to 127.0.0.1. Received datagrams are handed to the handler on a
/// background thread of the socket's own.
public final class UDPSocket {
    private let descriptor: Int32
    private let lock = NSLock()
    private var running = false
    private var thread: Thread?

    /// The port the socket listens on (useful when it was opened with port 0).
    public let localPort: UInt16

    /// Opens a socket listening on `port` (0 for any free port). `localOnly` listens on 127.0.0.1
    /// alone; otherwise on every interface.
    public init(listeningOn port: UInt16, localOnly: Bool = false) throws {
        #if canImport(Darwin)
        let fd = socket(AF_INET, SOCK_DGRAM, 0)
        #else
        let fd = socket(AF_INET, Int32(SOCK_DGRAM.rawValue), 0)
        #endif
        guard fd >= 0 else { throw UDPError.socketFailed(errno: errno) }
        // No SO_REUSEADDR: on Linux it would let two programs bind the same UDP port, and one of
        // them would silently stop receiving TotalMix's messages. A port in use is an error instead.

        var address = sockaddr_in()
        address.sin_family = sa_family_t(AF_INET)
        address.sin_port = port.bigEndian
        address.sin_addr.s_addr = localOnly ? UInt32(0x7F00_0001).bigEndian : UInt32(0).bigEndian
        #if canImport(Darwin)
        address.sin_len = UInt8(MemoryLayout<sockaddr_in>.size)
        #endif
        let bound = withUnsafePointer(to: &address) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                bind(fd, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
            }
        }
        guard bound == 0 else {
            let code = errno
            close(fd)
            throw UDPError.bindFailed(port: port, errno: code)
        }

        var actual = sockaddr_in()
        var length = socklen_t(MemoryLayout<sockaddr_in>.size)
        _ = withUnsafeMutablePointer(to: &actual) {
            $0.withMemoryRebound(to: sockaddr.self, capacity: 1) { getsockname(fd, $0, &length) }
        }
        descriptor = fd
        localPort = UInt16(bigEndian: actual.sin_port)
    }

    deinit {
        stop()
        close(descriptor)
    }

    /// Sends one datagram to `host` (a name or dotted IPv4 address) and `port`.
    public func send(_ bytes: [UInt8], to host: String, port: UInt16) throws {
        var address = try UDPSocket.resolve(host)
        address.sin_port = port.bigEndian
        let sent = bytes.withUnsafeBytes { buffer in
            withUnsafePointer(to: &address) {
                $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                    sendto(descriptor, buffer.baseAddress, buffer.count, 0, $0, socklen_t(MemoryLayout<sockaddr_in>.size))
                }
            }
        }
        guard sent >= 0 else { throw UDPError.sendFailed(errno: errno) }
    }

    /// Starts handing received datagrams to `handler`, with the sender's IPv4 address as text.
    /// Calling it again while running does nothing.
    public func startReceiving(_ handler: @escaping (_ bytes: [UInt8], _ sender: String) -> Void) {
        lock.lock()
        defer { lock.unlock() }
        guard !running else { return }
        running = true
        let fd = descriptor
        let thread = Thread { [weak self] in
            var buffer = [UInt8](repeating: 0, count: 65_536)
            while self?.isRunning == true {
                var poller = pollfd(fd: fd, events: Int16(POLLIN), revents: 0)
                // A short timeout so that stop() takes effect without closing the socket under the thread.
                guard poll(&poller, 1, 200) > 0 else { continue }
                var sender = sockaddr_in()
                var length = socklen_t(MemoryLayout<sockaddr_in>.size)
                let count = buffer.withUnsafeMutableBytes { raw in
                    withUnsafeMutablePointer(to: &sender) {
                        $0.withMemoryRebound(to: sockaddr.self, capacity: 1) {
                            recvfrom(fd, raw.baseAddress, raw.count, 0, $0, &length)
                        }
                    }
                }
                guard count > 0 else { continue }
                handler(Array(buffer[0..<count]), UDPSocket.text(sender.sin_addr))
            }
        }
        thread.name = "UDPSocket \(localPort)"
        self.thread = thread
        thread.start()
    }

    /// Stops receiving. The socket stays open for sending.
    public func stop() {
        lock.lock()
        running = false
        lock.unlock()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    static func resolve(_ host: String) throws -> sockaddr_in {
        var hints = addrinfo()
        hints.ai_family = AF_INET
        #if canImport(Darwin)
        hints.ai_socktype = SOCK_DGRAM
        #else
        hints.ai_socktype = Int32(SOCK_DGRAM.rawValue)
        #endif
        var result: UnsafeMutablePointer<addrinfo>?
        guard getaddrinfo(host, nil, &hints, &result) == 0, let first = result, let address = first.pointee.ai_addr else {
            throw UDPError.hostNotFound(host)
        }
        defer { freeaddrinfo(result) }
        return address.withMemoryRebound(to: sockaddr_in.self, capacity: 1) { $0.pointee }
    }

    static func text(_ address: in_addr) -> String {
        var address = address
        var buffer = [CChar](repeating: 0, count: Int(INET_ADDRSTRLEN))
        guard inet_ntop(AF_INET, &address, &buffer, socklen_t(INET_ADDRSTRLEN)) != nil else { return "?" }
        return String(cString: buffer)
    }
}

#else

/// Placeholder until UDP is implemented on this platform: every call throws.
public final class UDPSocket {
    public let localPort: UInt16 = 0
    public init(listeningOn port: UInt16, localOnly: Bool = false) throws { throw UDPError.unsupportedPlatform }
    public func send(_ bytes: [UInt8], to host: String, port: UInt16) throws { throw UDPError.unsupportedPlatform }
    public func startReceiving(_ handler: @escaping (_ bytes: [UInt8], _ sender: String) -> Void) {}
    public func stop() {}
}

#endif
