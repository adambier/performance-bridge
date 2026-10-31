import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(RotoControl)
import RotoControl
#endif
#if canImport(MIDITransport)
import MIDITransport
#endif
#if canImport(UDPTransport)
import UDPTransport
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif
#if canImport(RotoDriver)
import RotoDriver
#endif

/// Where the engine finds TotalMix FX and the Roto-Control.
public struct BridgeSettings: Equatable, Sendable {
    /// TotalMix's host and ports.
    public var endpoint: TotalMixEndpoint
    /// The name, or part of the name, of the Roto-Control's MIDI ports.
    public var rotoPortName: String
    /// The home submix's output channel (0-based), or `nil` for TotalMix's Main Out.
    public var homeSubmix: Int?

    /// Settings with TotalMix's default ports, the Roto-Control's usual port name, and Main Out as
    /// the home submix.
    public init(endpoint: TotalMixEndpoint = .standard, rotoPortName: String = "Roto", homeSubmix: Int? = nil) {
        self.endpoint = endpoint
        self.rotoPortName = rotoPortName
        self.homeSubmix = homeSubmix
    }
}

/// A monitoring output that can be the home submix, for a menu.
public struct MonitoringChoice: Equatable, Hashable, Sendable {
    /// The output channel, 0-based.
    public var output: Int
    /// The output's name in TotalMix, or "Output n" until TotalMix has sent it.
    public var name: String
    /// The monitoring roles assigned to it (e.g., Main Out, Phones 1).
    public var roles: [MonitoringRole]
}

/// What the engine is doing, for the app's menu.
public struct BridgeStatus: Equatable, Sendable {
    /// Whether the engine is running.
    public var running = false
    /// Whether something has come from TotalMix in the last `BridgeEngine.totalMixTimeout` seconds.
    public var totalMixAnswering = false
    /// Whether the Roto-Control has completed the handshake.
    public var rotoConnected = false
    /// The home submix's output channel (0-based), if known.
    public var homeSubmix: Int?
    /// The monitoring outputs, in output order, for choosing the home submix.
    public var monitoringOutputs: [MonitoringChoice] = []
    /// Why the engine could not start, if it could not.
    public var error: String?

    /// Nothing running yet.
    public init() {}
}

/// TotalMix FX and a Roto-Control connected through `SurfaceHub` and `RotoDriver`: the sockets, the
/// MIDI ports, and a clock. This is what the app runs; `sbdev bridge` does the same with test
/// commands of its own.
///
/// Every change happens with a lock held. Callbacks (`onLog`, `onStatus`) are called with the lock
/// released, on whatever thread caused them.
public final class BridgeEngine: @unchecked Sendable {
    /// How long TotalMix may stay silent before `BridgeStatus.totalMixAnswering` turns false, in
    /// seconds. TotalMix sends its status about once a second when "Send status" is on
    /// (docs/TOTALMIX-OSC.md); without it, a quiet mixer also looks silent.
    public static let totalMixTimeout: Double = 5

    /// The settings the engine was made with.
    public let settings: BridgeSettings
    /// Called with a line of text for a log.
    public var onLog: (@Sendable (String) -> Void)?
    /// Called when the status changes.
    public var onStatus: (@Sendable (BridgeStatus) -> Void)?

    private let lock = NSLock()
    private let startDate = Date()
    private var hub = SurfaceHub()
    private var driver = RotoDriver(id: SurfaceID("roto"))
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var ticker: Thread?
    private var running = false
    private var lastFromTotalMix: Double?
    private var lastStatus = BridgeStatus()

    /// An engine for these settings; nothing starts until `start()`.
    public init(settings: BridgeSettings = BridgeSettings()) {
        self.settings = settings
    }

    private var now: Double { Date().timeIntervalSince(startDate) }

    /// Opens the UDP socket and the MIDI ports, asks TotalMix for its state, and starts the
    /// Roto-Control's handshake and the clock. Throws if a socket or port can't be opened.
    public func start() throws {
        lock.lock()
        guard !running else { lock.unlock(); return }
        do {
            socket = try UDPSocket(listeningOn: settings.endpoint.outgoingPort)
            midi = try MIDIConnection(clientName: "Performance Bridge", sourceName: settings.rotoPortName,
                                      destinationName: settings.rotoPortName) { [weak self] bytes in
                self?.fromRoto(bytes)
            }
        } catch {
            socket?.stop()
            socket = nil
            lastStatus.error = "\(error)"
            lock.unlock()
            onStatus?(lastStatus)
            throw error
        }
        running = true
        socket?.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
        dispatch(hub.addSurface(driver.id, capabilities: RotoDriver.capabilities, now: now))
        if let home = settings.homeSubmix { dispatch(hub.setHomeSubmix(home, now: now)) }
        dispatch(hub.connect(now: now))
        sendToRoto(driver.start(now: now))
        let thread = Thread { [weak self] in
            while let engine = self, engine.isRunning {
                engine.tick()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        thread.name = "Performance Bridge clock"
        ticker = thread
        thread.start()
        lock.unlock()
        log("Started: TotalMix at \(settings.endpoint.host), ports \(settings.endpoint.incomingPort) and \(settings.endpoint.outgoingPort)")
        publishStatus()
    }

    /// Closes the socket and the ports and stops the clock.
    public func stop() {
        lock.lock()
        running = false
        socket?.stop()
        socket = nil
        midi?.close()
        midi = nil
        ticker = nil
        lock.unlock()
        publishStatus()
    }

    private var isRunning: Bool {
        lock.lock()
        defer { lock.unlock() }
        return running
    }

    /// The current status.
    public var status: BridgeStatus {
        lock.lock()
        defer { lock.unlock() }
        return makeStatus()
    }

    /// Makes `output` (0-based) the home submix, or TotalMix's Main Out for `nil`.
    public func setHomeSubmix(_ output: Int?) {
        lock.lock()
        dispatch(hub.setHomeSubmix(output, now: now))
        lock.unlock()
        publishStatus()
    }

    /// Asks TotalMix for its whole state again.
    public func refresh() {
        lock.lock()
        dispatch(hub.connect(now: now))
        lock.unlock()
    }

    // MARK: Input

    private func fromTotalMix(_ bytes: [UInt8]) {
        lock.lock()
        guard let packet = try? OSCPacket(decoding: bytes) else { lock.unlock(); return }
        lastFromTotalMix = now
        for message in packet.messages {
            guard let event = TotalMixEvent(message) else { continue }
            dispatch(hub.handle(event, now: now))
        }
        lock.unlock()
        publishStatusIfChanged()
    }

    private func fromRoto(_ bytes: [UInt8]) {
        lock.lock()
        let step = driver.receive(bytes, hub: &hub, now: now)
        sendToRoto(step.midi)
        dispatch(step.core)
        lock.unlock()
        publishStatusIfChanged()
    }

    private func tick() {
        lock.lock()
        dispatch(hub.tick(now: now))
        sendToRoto(driver.tick(now: now))
        lock.unlock()
        publishStatusIfChanged()
    }

    // MARK: Output (with the lock held)

    private func dispatch(_ output: CoreOutput) {
        for message in output.messages {
            try? socket?.send(message.encoded(), to: settings.endpoint.host, port: settings.endpoint.incomingPort)
        }
        for (id, updates) in output.updates where id == driver.id {
            sendToRoto(driver.render(updates, hub: hub, now: now))
        }
    }

    private func sendToRoto(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        try? midi?.send(bytes)
    }

    // MARK: Status

    private func makeStatus() -> BridgeStatus {
        var status = BridgeStatus()
        status.running = running
        status.totalMixAnswering = lastFromTotalMix.map { now - $0 < Self.totalMixTimeout } ?? false
        status.rotoConnected = driver.isConnected
        status.homeSubmix = hub.homeSubmix
        status.monitoringOutputs = Self.monitoringChoices(hub.mirror)
        status.error = lastStatus.error
        return status
    }

    /// The monitoring outputs of a mirror, in output order, with their names and roles.
    public static func monitoringChoices(_ mirror: MixerMirror) -> [MonitoringChoice] {
        var roles: [Int: [MonitoringRole]] = [:]
        for role in MonitoringRole.allCases {
            if let output = mirror.monitoring[role] { roles[output, default: []].append(role) }
        }
        return roles.keys.sorted().map { output in
            let name = mirror.channels[ChannelRef(.output, output)]?.name ?? "Output \(output + 1)"
            return MonitoringChoice(output: output, name: name, roles: roles[output] ?? [])
        }
    }

    private func publishStatus() {
        lock.lock()
        let status = makeStatus()
        lastStatus = status
        lock.unlock()
        onStatus?(status)
    }

    private func publishStatusIfChanged() {
        lock.lock()
        let status = makeStatus()
        let changed = status != lastStatus
        if changed { lastStatus = status }
        lock.unlock()
        if changed { onStatus?(status) }
    }

    private func log(_ text: String) {
        onLog?(text)
    }
}
