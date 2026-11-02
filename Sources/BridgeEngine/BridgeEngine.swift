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
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(LaunchControlDriver)
import LaunchControlDriver
#endif

/// A Launch Control for the engine to use: which layout runs on which model, and its MIDI port.
public struct LaunchControlSetting: Equatable, Sendable {
    /// The layout that runs: the XL 3's or the Launch Control 3's.
    public var layout: LaunchControlModel
    /// The model connected; the XL 3 with the Launch Control 3's layout for the simulation.
    public var device: LaunchControlModel
    /// The name, or part of the name, of its DAW MIDI ports; `nil` to find them by the model's
    /// port names (`LaunchControlModel.dawPort(among:)`), as the app does (Adam, 2026-11-02: each
    /// model's DAW port has a fixed name, so there is nothing for the user to choose).
    public var portName: String?

    /// A setting for `layout` on `device` (by default the same model); with no port name, the
    /// device's DAW ports are found by their names.
    public init(layout: LaunchControlModel, device: LaunchControlModel? = nil, portName: String? = nil) {
        self.layout = layout
        self.device = device ?? layout
        self.portName = portName
    }

    /// A setting from command-line arguments, for trying a Launch Control before the app has a
    /// setting for it: `--launch-control xl3`, `lc3`, or `lc3-sim` (the Launch Control 3's layout on
    /// an XL 3), with `--launch-control-port NAME`. `nil` without `--launch-control` or with a value it doesn't know.
    public init?(arguments: [String]) {
        func value(_ option: String) -> String? {
            guard let index = arguments.firstIndex(of: option), index + 1 < arguments.count else { return nil }
            return arguments[index + 1]
        }
        let layout: LaunchControlModel, device: LaunchControlModel
        switch value("--launch-control")?.lowercased() {
        case "xl3": (layout, device) = (.xl3, .xl3)
        case "lc3": (layout, device) = (.lc3, .lc3)
        case "lc3-sim": (layout, device) = (.lc3, .xl3)
        default: return nil
        }
        self.init(layout: layout, device: device, portName: value("--launch-control-port"))
    }

    /// The name the menu and the log use: the model, or the simulation's description.
    public var name: String {
        layout == device ? layout.name : "\(layout.name) on a \(device.name)"
    }
}

/// Where the engine finds TotalMix FX and the Roto-Control.
public struct BridgeSettings: Equatable, Sendable {
    /// TotalMix FX's host and ports.
    public var endpoint: TotalMixEndpoint
    /// The name, or part of the name, of the Roto-Control's MIDI ports.
    public var rotoPortName: String
    /// The home submix's output channel (0-based), or `nil` for TotalMix FX's Main Out.
    public var homeSubmix: Int?
    /// Whether the first playback starts a new page (`PerformanceLayout.playbacksOnNewPage`).
    public var playbacksOnNewPage = false
    /// The layout to start with: the channel order and labels saved by the app.
    public var layout = PerformanceLayout()
    /// A Launch Control to connect, or `nil` for none.
    public var launchControl: LaunchControlSetting?
    /// Each Launch Control layout's send rows as the app saved them (`LaunchControlSendRows.choices`).
    /// The engine holds both layouts' rows, connected or not, so the app can set them with no
    /// device plugged in (Adam, 2026-11-02).
    public var launchControlSends: [LaunchControlModel: [Int?]] = [:]
    /// Whether a Launch Control's level and send encoders show their level by brightness
    /// (`LaunchControlDriver.levelBrightness`); off by default (Adam, 2026-11-02).
    public var launchControlLevelBrightness = false
    /// Whether to connect the Roto-Control. The app uses one hardware controller at a time (Adam,
    /// 2026-11-01), so it turns this off when a Launch Control is chosen.
    public var rotoEnabled = true
    /// How often the engine tries again to open TotalMix FX's port or the Roto-Control's MIDI ports
    /// while either is not open, in seconds.
    public var retryInterval: Double = 3

    /// Settings with TotalMix FX's default ports, the Roto-Control's usual port name, Main Out as the
    /// home submix, and a retry every 3 seconds.
    public init(endpoint: TotalMixEndpoint = .standard, rotoPortName: String = "Roto", homeSubmix: Int? = nil,
                playbacksOnNewPage: Bool = false, retryInterval: Double = 3) {
        self.endpoint = endpoint
        self.rotoPortName = rotoPortName
        self.homeSubmix = homeSubmix
        self.playbacksOnNewPage = playbacksOnNewPage
        self.retryInterval = retryInterval
    }
}

/// An output that can be the home submix, for a menu.
public struct HomeChoice: Equatable, Hashable, Sendable {
    /// The output channel, 0-based (the left channel of a stereo pair).
    public var output: Int
    /// The output's name in TotalMix FX, or "Output n" until TotalMix FX has sent it.
    public var name: String
    /// The monitoring roles assigned to it (e.g., Main Out, Phones 1); empty for other outputs.
    public var roles: [MonitoringRole]
}

/// A channel as the layout editor lists it.
public struct LayoutItem: Equatable, Sendable {
    /// The channel.
    public var channel: ChannelRef
    /// The name a strip shows (see `SurfaceHub.stripName`): the label if there is one.
    public var name: String
    /// The name a strip shows without a label: TotalMix FX's name, or "PB 1/2" for a playback.
    public var defaultName: String
    /// The label chosen in the app, if any.
    public var label: String?

    /// An item for the layout editor.
    public init(channel: ChannelRef, name: String, defaultName: String? = nil, label: String? = nil) {
        self.channel = channel
        self.name = name
        self.defaultName = defaultName ?? name
        self.label = label
    }
}

/// What the engine is doing, for the app's menu.
public struct BridgeStatus: Equatable, Sendable {
    /// Whether the engine is running.
    public var running = false
    /// Whether something has come from TotalMix FX in the last `BridgeEngine.totalMixTimeout` seconds.
    public var totalMixAnswering = false
    /// Whether the engine uses a Roto-Control (`BridgeSettings.rotoEnabled`).
    public var rotoEnabled = true
    /// Whether the Roto-Control has completed the handshake.
    public var rotoConnected = false
    /// Whether TotalMix FX's outgoing port is open (another program, such as `sbdev bridge`, may have
    /// it).
    public var listening = false
    /// Whether the Roto-Control's MIDI ports are open (it is plugged in), handshake or not.
    public var rotoFound = false
    /// The Launch Control the engine uses, by name (e.g., "Launch Control XL 3"), or `nil` for none.
    public var launchControlName: String?
    /// Whether the Launch Control's DAW ports are open (it is plugged in).
    public var launchControlFound = false
    /// Whether the Launch Control has answered (entered DAW mode).
    public var launchControlConnected = false
    /// The layout the Launch Control runs (the XL 3's or the Launch Control 3's), or `nil` for none.
    public var launchControlLayout: LaunchControlModel?
    /// The output each send row of each Launch Control layout feeds now (XL 3: top and middle rows;
    /// Launch Control 3: the top row, `nil` for pan), whether or not a device is connected, from the
    /// send targets TotalMix FX has shown.
    public var launchControlSends: [LaunchControlModel: [Int?]] = [:]
    /// Whether a Launch Control's level and send encoders show their level by brightness.
    public var launchControlLevelBrightness = false
    /// The outputs the send controls step through, in order (`SurfaceHub.sendTargets`), with their
    /// names as the strips show them, for choosing a send row's output.
    public var sendTargets: [HomeChoice] = []
    /// Whether TotalMix FX has reported its Mute Master off: mutes are then only selected and don't
    /// silence (Adam, 2026-11-02). False until TotalMix FX has reported it.
    public var muteMasterOff = false
    /// How many channels TotalMix FX has described (named or set) since the engine started: more than
    /// zero once it has answered `/sendall` with its channels, not only its status.
    public var channelCount = 0
    /// Whether TotalMix FX has sent any level (meter) message since the engine started. It sends
    /// levels only with "Send Level Data" on, and, per RME's protocol document, only when they
    /// change, so a silent mixer may send none.
    public var levelsSeen = false
    /// The home submix's output channel (0-based), if known.
    public var homeSubmix: Int?
    /// Whether the first playback starts a new page.
    public var playbacksOnNewPage = false
    /// The monitoring outputs, in output order, for choosing the home submix.
    public var monitoringOutputs: [HomeChoice] = []
    /// The other outputs TotalMix FX shows over OSC, in the layout's order, for choosing any output as
    /// the home submix.
    public var otherOutputs: [HomeChoice] = []
    /// What the engine can't open yet (TotalMix FX's port, the Roto-Control's MIDI ports, or both),
    /// in full, one line each, for a log or a tooltip; `nil` when both are open. The engine keeps
    /// trying. `listening` and `rotoFound` say the same in short.
    public var error: String?

    /// Nothing running yet.
    public init() {}
}

/// TotalMix FX and a Roto-Control connected through `SurfaceHub` and `RotoDriver`: the sockets, the
/// MIDI ports, and a clock. This is what the app runs; `sbdev bridge` does the same with test
/// commands of its own.
///
/// TotalMix FX and the Roto-Control connect independently: while either can't be opened, the engine
/// tries again every `BridgeSettings.retryInterval` seconds, and it notices a Roto-Control that is
/// unplugged and opens it again when it comes back. When TotalMix FX falls silent, the engine asks it
/// for its state until it answers, so a restarted TotalMix FX is mirrored again.
///
/// Every change happens with a lock held. Callbacks (`onLog`, `onStatus`) are called with the lock
/// released, on whatever thread caused them. MIDI ports are opened and closed with the lock
/// released, since CoreMIDI may wait for a delivery in progress, and a delivery waits for the lock.
public final class BridgeEngine: @unchecked Sendable {
    /// How long TotalMix FX may stay silent before `BridgeStatus.totalMixAnswering` turns false, in
    /// seconds. TotalMix FX sends its status about once a second when "Send status" is on
    /// (docs/TOTALMIX-OSC.md); without it, a quiet mixer also looks silent.
    public static let totalMixTimeout: Double = 5

    /// The settings the engine was made with.
    public let settings: BridgeSettings
    /// Called with a line of text for a log.
    public var onLog: (@Sendable (String) -> Void)?
    /// Called when the status changes.
    public var onStatus: (@Sendable (BridgeStatus) -> Void)?
    /// Called with a layout and its send rows' choices (`LaunchControlSendRows.choices`) whenever
    /// the user changes them, on the device or in the app, so the app can save them. Called with the
    /// lock released.
    public var onLaunchControlSendsChange: (@Sendable (LaunchControlModel, [Int?]) -> Void)?
    /// Called with the new layout whenever the app changes it (order, new-page option, or labels),
    /// so the app can save it. Set it before `start()`.
    public var onLayoutChange: (@Sendable (PerformanceLayout) -> Void)?

    private let lock = NSLock()
    private let startDate = Date()
    private var hub = SurfaceHub()
    private var driver = RotoDriver(id: SurfaceID("roto"))
    private var socket: UDPSocket?
    private var midi: MIDIConnection?
    private var ticker: Thread?
    private var running = false
    private var lastFromTotalMix: Double?
    private var levelsSeen = false
    private var totalMixWasAnswering = false
    private var lastStatus = BridgeStatus()
    private var socketError: String?
    private var midiError: String?
    private var lastSocketTry: Double?
    private var lastMIDITry: Double?
    private var lastMIDICheck: Double?
    private var openingMIDI = false
    private var lcDriver: LaunchControlDriver?
    private var lcMIDI: MIDIConnection?
    private var lcError: String?
    private var lastLCTry: Double?
    private var lastLCCheck: Double?
    private var openingLC = false
    /// Each layout's send rows, kept across a reconnection and while no device is connected.
    private var sendRows: [LaunchControlModel: LaunchControlSendRows]
    /// Whether a Launch Control shows levels by brightness, kept like `sendRows`.
    private var levelBrightness: Bool

    /// How often the engine checks that the Roto-Control's ports are still there, in seconds.
    static let unplugCheckInterval: Double = 1

    /// An engine for these settings; nothing starts until `start()`.
    public init(settings: BridgeSettings = BridgeSettings()) {
        self.settings = settings
        var rows: [LaunchControlModel: LaunchControlSendRows] = [:]
        for model in LaunchControlModel.allCases {
            rows[model] = LaunchControlSendRows(layout: model, choices: settings.launchControlSends[model] ?? [])
        }
        self.sendRows = rows
        self.levelBrightness = settings.launchControlLevelBrightness
    }

    private var now: Double { Date().timeIntervalSince(startDate) }

    /// Starts the engine: opens TotalMix FX's port and the Roto-Control's MIDI ports, asks TotalMix FX
    /// for its state, and starts the Roto-Control's handshake and the clock. Neither side has to be
    /// there: what can't be opened (for example, TotalMix FX's port while another program, such as
    /// `sbdev bridge`, has it, or a Roto-Control that isn't plugged in) is named in `status.error`
    /// and tried again every `BridgeSettings.retryInterval` seconds.
    public func start() {
        lock.lock()
        guard !running else { lock.unlock(); return }
        running = true
        if settings.rotoEnabled { dispatch(hub.addSurface(driver.id, capabilities: RotoDriver.capabilities, now: now)) }
        if let home = settings.homeSubmix { dispatch(hub.setHomeSubmix(home, now: now)) }
        var layout = settings.layout
        if settings.playbacksOnNewPage { layout.playbacksOnNewPage = true }
        if layout != hub.layout { dispatch(hub.setLayout(layout, now: now)) }
        lock.unlock()
        log("Started: TotalMix FX at \(settings.endpoint.host), sending to port \(settings.endpoint.incomingPort), listening on \(settings.endpoint.outgoingPort)")
        openSocketIfDue(force: true)
        openMIDIIfDue(force: true)
        openLaunchControlIfDue(force: true)
        let thread = Thread { [weak self] in
            while let engine = self, engine.isRunning {
                engine.tick()
                Thread.sleep(forTimeInterval: 0.01)
            }
        }
        thread.name = "Performance Bridge clock"
        lock.lock()
        ticker = thread
        lock.unlock()
        thread.start()
        publishStatus()
    }

    /// Closes the socket and the ports and stops the clock.
    public func stop() {
        lock.lock()
        running = false
        // Stopped outside the lock: the socket waits for its receive thread, which may be waiting
        // for the lock in `fromTotalMix`.
        let closingSocket = socket
        socket = nil
        let closing = midi
        midi = nil
        driver = RotoDriver(id: driver.id)
        let closingLC = lcMIDI
        if var lc = lcDriver {
            try? lcMIDI?.send(lc.stop(hub: &hub))
            lcDriver = nil
        }
        lcMIDI = nil
        ticker = nil
        lock.unlock()
        closingSocket?.stop()
        closing?.close()
        closingLC?.close()
        publishStatus()
    }

    // MARK: Connections

    /// Opens TotalMix FX's port if it isn't open and a try is due, then asks TotalMix FX for its state.
    private func openSocketIfDue(force: Bool = false) {
        lock.lock()
        defer { lock.unlock() }
        guard running, socket == nil else { return }
        if !force, let last = lastSocketTry, now - last < settings.retryInterval { return }
        lastSocketTry = now
        let port = settings.endpoint.outgoingPort
        do {
            let opened = try UDPSocket(listeningOn: port)
            socket = opened
            opened.startReceiving { [weak self] bytes, _ in self?.fromTotalMix(bytes) }
            dispatch(hub.connect(now: now))
            if socketError != nil { pendingLogs.append("Listening on port \(port)") }
            socketError = nil
        } catch {
            let message = "Can't listen on port \(port): \(error)"
            if message != socketError { pendingLogs.append(message + "; trying again every \(Self.seconds(settings.retryInterval))") }
            socketError = message
        }
    }

    /// Opens the Roto-Control's MIDI ports if they aren't open and a try is due, and starts the
    /// handshake.
    private func openMIDIIfDue(force: Bool = false) {
        lock.lock()
        guard running, settings.rotoEnabled, midi == nil, !openingMIDI else { lock.unlock(); return }
        if !force, let last = lastMIDITry, now - last < settings.retryInterval { lock.unlock(); return }
        lastMIDITry = now
        openingMIDI = true
        lock.unlock()

        let name = settings.rotoPortName
        let result = Result {
            try MIDIConnection(clientName: "Performance Bridge", sourceName: name, destinationName: name) { [weak self] bytes in
                self?.fromRoto(bytes)
            }
        }

        lock.lock()
        openingMIDI = false
        var unused: MIDIConnection?
        switch result {
        case .success(let connection) where running:
            midi = connection
            driver = RotoDriver(id: driver.id)
            sendToRoto(driver.start(now: now))
            pendingLogs.append("Found the Roto-Control (\(connection.source.name)); starting the handshake")
            midiError = nil
        case .success(let connection):
            unused = connection
        case .failure(let error):
            let message = "Roto-Control not found (\(error))"
            if message != midiError { pendingLogs.append(message + "; trying again every \(Self.seconds(settings.retryInterval))") }
            midiError = message
        }
        lock.unlock()
        unused?.close()
    }

    /// Closes the Roto-Control's ports if it has been unplugged, so that `openMIDIIfDue` opens them
    /// again when it comes back.
    private func checkMIDIIfDue() {
        lock.lock()
        guard let connection = midi else { lock.unlock(); return }
        if let last = lastMIDICheck, now - last < Self.unplugCheckInterval { lock.unlock(); return }
        lastMIDICheck = now
        lock.unlock()
        guard !connection.isAvailable else { return }
        lock.lock()
        guard midi === connection else { lock.unlock(); return }
        midi = nil
        driver = RotoDriver(id: driver.id)
        lastMIDITry = now
        midiError = "Roto-Control unplugged"
        pendingLogs.append("The Roto-Control's ports are gone (unplugged?); trying again every \(Self.seconds(settings.retryInterval))")
        lock.unlock()
        connection.close()
    }

    /// Opens the Launch Control's DAW ports, if one is set and they aren't open and a try is due,
    /// and starts the driver, which asks the device for DAW mode.
    private func openLaunchControlIfDue(force: Bool = false) {
        lock.lock()
        guard running, let setting = settings.launchControl, lcMIDI == nil, !openingLC else { lock.unlock(); return }
        if !force, let last = lastLCTry, now - last < settings.retryInterval { lock.unlock(); return }
        lastLCTry = now
        openingLC = true
        lock.unlock()

        let result = Result { () throws -> MIDIConnection in
            let sources = MIDIConnection.sources().map(\.name)
            guard let port = setting.portName ?? setting.device.dawPort(among: sources) else {
                throw MIDIConnectionError.endpointNotFound(setting.device.portPrefix + " 1 DAW")
            }
            return try MIDIConnection(clientName: "Performance Bridge", sourceName: port,
                                      destinationName: port) { [weak self] bytes in
                self?.fromLaunchControl(bytes)
            }
        }

        lock.lock()
        openingLC = false
        var unused: MIDIConnection?
        switch result {
        case .success(let connection) where running:
            lcMIDI = connection
            var lc = LaunchControlDriver(name: "launchcontrol", layout: setting.layout, device: setting.device,
                                         sendOutputs: sendRows[setting.layout]?.choices ?? [],
                                         levelBrightness: levelBrightness)
            let started = lc.start(hub: &hub, now: now)
            sendToLaunchControl(started.midi)
            lcDriver = lc
            dispatch(started.core)
            pendingLogs.append("Found the \(setting.name) (\(connection.source.name)); asking for DAW mode")
            lcError = nil
        case .success(let connection):
            unused = connection
        case .failure(let error):
            let message = "\(setting.name) not found (\(error))"
            if message != lcError { pendingLogs.append(message + "; trying again every \(Self.seconds(settings.retryInterval))") }
            lcError = message
        }
        lock.unlock()
        unused?.close()
    }

    /// Closes the Launch Control's ports if it has been unplugged, so that
    /// `openLaunchControlIfDue` opens them again when it comes back.
    private func checkLaunchControlIfDue() {
        lock.lock()
        guard let connection = lcMIDI else { lock.unlock(); return }
        if let last = lastLCCheck, now - last < Self.unplugCheckInterval { lock.unlock(); return }
        lastLCCheck = now
        lock.unlock()
        guard !connection.isAvailable else { return }
        lock.lock()
        guard lcMIDI === connection else { lock.unlock(); return }
        lcMIDI = nil
        if var lc = lcDriver {
            _ = lc.stop(hub: &hub)
            lcDriver = nil
        }
        lastLCTry = now
        let name = settings.launchControl?.name ?? "Launch Control"
        lcError = "\(name) unplugged"
        pendingLogs.append("The \(name)'s ports are gone (unplugged?); trying again every \(Self.seconds(settings.retryInterval))")
        lock.unlock()
        connection.close()
    }

    private static func seconds(_ interval: Double) -> String {
        interval == interval.rounded() ? "\(Int(interval)) s" : "\(interval) s"
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

    /// Makes `output` (0-based) the home submix, or TotalMix FX's Main Out for `nil`.
    public func setHomeSubmix(_ output: Int?) {
        lock.lock()
        dispatch(hub.setHomeSubmix(output, now: now))
        lock.unlock()
        publishStatus()
    }

    /// Starts the first playback on a new page, or not.
    public func setPlaybacksOnNewPage(_ on: Bool) {
        lock.lock()
        var layout = hub.layout
        layout.playbacksOnNewPage = on
        dispatch(hub.setLayout(layout, now: now))
        lock.unlock()
        layoutChanged(layout)
        publishStatus()
    }

    private func layoutChanged(_ layout: PerformanceLayout) {
        onLayoutChange?(layout)
    }

    /// Sets the label the hardware controllers show for `ref`; an empty or `nil` text removes it, so
    /// the channel shows TotalMix FX's name again (`PerformanceLayout.withLabel`).
    public func setLabel(_ text: String?, for ref: ChannelRef) {
        lock.lock()
        let layout = hub.layout.withLabel(text, for: ref)
        dispatch(hub.setLayout(layout, now: now))
        lock.unlock()
        layoutChanged(layout)
        publishStatus()
    }

    /// The layout the surfaces use now.
    public var layout: PerformanceLayout {
        lock.lock()
        defer { lock.unlock() }
        return hub.layout
    }

    /// Replaces the layout: the order, the new-page option, and the labels.
    public func setLayout(_ layout: PerformanceLayout) {
        lock.lock()
        dispatch(hub.setLayout(layout, now: now))
        lock.unlock()
        layoutChanged(layout)
        publishStatus()
    }

    /// The channels of a view for the layout editor, in the order the surfaces show them.
    /// Channels hidden from this OSC remote in TotalMix FX are not here.
    public func layoutItems(_ view: ViewKind) -> [LayoutItem] {
        lock.lock()
        defer { lock.unlock() }
        return hub.layout.channels(view, in: hub.mirror).map { ref in
            let state = hub.mirror.channels[ref]
            let label = hub.layout.label(for: ref)
            return LayoutItem(channel: ref, name: SurfaceHub.stripName(ref, state, label: label),
                              defaultName: SurfaceHub.stripName(ref, state), label: label)
        }
    }

    /// Whether a view shows its channels in TotalMix FX's own order
    /// (`PerformanceLayout.isTotalMixOrder`), for hiding Restore TotalMix FX Order when there is
    /// nothing to restore.
    public func isTotalMixOrder(_ view: ViewKind) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        return hub.layout.isTotalMixOrder(view, in: hub.mirror)
    }

    /// Sets a send row's output for a Launch Control layout from the app, as Page does on the device
    /// (`LaunchControlSendRows.set`): `nil` is pan, on the Launch Control 3's top row. Takes effect
    /// at once on a connected device running that layout, and is kept for the layout otherwise.
    /// Does nothing for an output another row feeds or that isn't a send target.
    public func setLaunchControlSend(layout: LaunchControlModel, row: Int, to output: Int?) {
        lock.lock()
        let before = sendRows[layout]
        if var lc = lcDriver, lc.layout == layout {
            let step = lc.setSendOutput(row: row, to: output, hub: &hub, now: now)
            lcDriver = lc
            sendToLaunchControl(step.midi)
            dispatch(step.core)
        } else {
            sendRows[layout]?.set(row: row, to: output, targets: hub.sendTargets)
        }
        let changed = takeSendRowChange(layout, before: before)
        lock.unlock()
        if let changed { onLaunchControlSendsChange?(layout, changed) }
        publishStatusIfChanged()
    }

    /// Turns a Launch Control's level-by-brightness on or off, from the app. Takes effect at once on
    /// a connected device, and is kept for the next one otherwise.
    public func setLaunchControlLevelBrightness(_ on: Bool) {
        lock.lock()
        levelBrightness = on
        if var lc = lcDriver {
            let bytes = lc.setLevelBrightness(on, hub: hub)
            lcDriver = lc
            sendToLaunchControl(bytes)
        }
        lock.unlock()
        publishStatusIfChanged()
    }

    /// The layout's new choices, if they changed since `before`: for the layout the driver runs,
    /// the driver's, copied into `sendRows`. Called with the lock held.
    private func takeSendRowChange(_ layout: LaunchControlModel, before: LaunchControlSendRows?) -> [Int?]? {
        if let lc = lcDriver, lc.layout == layout { sendRows[layout] = lc.sendRows }
        guard let rows = sendRows[layout], rows != before else { return nil }
        return rows.choices
    }

    /// Refreshes the channels from TotalMix FX (`SurfaceHub.refreshChannels`): asks for its whole
    /// state again and drops channels its answer leaves out, so channels hidden or shown in
    /// TotalMix FX since the last refresh leave or join the surfaces.
    public func refresh() {
        lock.lock()
        dispatch(hub.refreshChannels(now: now))
        lock.unlock()
    }

    // MARK: Input

    private func fromTotalMix(_ bytes: [UInt8]) {
        lock.lock()
        guard let packet = try? OSCPacket(decoding: bytes) else { lock.unlock(); return }
        lastFromTotalMix = now
        for message in packet.messages {
            guard let event = TotalMixEvent(message) else { continue }
            if case .level = event { levelsSeen = true }
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

    private func fromLaunchControl(_ bytes: [UInt8]) {
        lock.lock()
        var changed: (LaunchControlModel, [Int?])?
        if var lc = lcDriver {
            let before = sendRows[lc.layout]
            let step = lc.receive(bytes, hub: &hub, now: now)
            lcDriver = lc
            sendToLaunchControl(step.midi)
            dispatch(step.core)
            // Compared with the rows the driver started from (both padded to the layout's rows),
            // so nothing is saved before a row actually changes (review of 2026-11-02).
            changed = takeSendRowChange(lc.layout, before: before).map { (lc.layout, $0) }
        }
        lock.unlock()
        if let changed { onLaunchControlSendsChange?(changed.0, changed.1) }
        publishStatusIfChanged()
    }

    private func tick() {
        openSocketIfDue()
        checkMIDIIfDue()
        openMIDIIfDue()
        checkLaunchControlIfDue()
        openLaunchControlIfDue()
        lock.lock()
        // TotalMix FX has gone quiet (quit, restarted, or OSC turned off): refresh the channels, asking
        // until it answers, so the mirror is whole and current again when it comes back.
        let answering = lastFromTotalMix.map { now - $0 < Self.totalMixTimeout } ?? false
        if totalMixWasAnswering, !answering { dispatch(hub.refreshChannels(now: now)) }
        totalMixWasAnswering = answering
        dispatch(hub.tick(now: now))
        sendToRoto(driver.tick(now: now, hub: hub))
        if var lc = lcDriver {
            let step = lc.tick(hub: &hub, now: now)
            lcDriver = lc
            sendToLaunchControl(step.midi)
            dispatch(step.core)
        }
        lock.unlock()
        publishStatusIfChanged()
    }

    // MARK: Output (with the lock held)

    private func dispatch(_ output: CoreOutput) {
        var output = output
        // The Launch Control's layers first: its driver takes their updates out of the output.
        if var lc = lcDriver {
            let step = lc.take(output, hub: &hub, now: now)
            lcDriver = lc
            sendToLaunchControl(step.midi)
            output = step.core
        }
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

    private func sendToLaunchControl(_ bytes: [UInt8]) {
        guard !bytes.isEmpty else { return }
        try? lcMIDI?.send(bytes)
    }

    // MARK: Status

    private func makeStatus() -> BridgeStatus {
        var status = BridgeStatus()
        status.running = running
        status.totalMixAnswering = lastFromTotalMix.map { now - $0 < Self.totalMixTimeout } ?? false
        status.rotoEnabled = settings.rotoEnabled
        status.rotoConnected = driver.isConnected
        status.listening = socket != nil
        status.rotoFound = midi != nil
        status.launchControlName = settings.launchControl?.name
        status.launchControlFound = lcMIDI != nil
        status.launchControlConnected = lcDriver?.isConnected ?? false
        status.launchControlLayout = settings.launchControl?.layout
        for (layout, rows) in sendRows {
            status.launchControlSends[layout] = rows.outputs(targets: hub.sendTargets)
        }
        status.launchControlLevelBrightness = levelBrightness
        status.sendTargets = hub.sendTargets.map { output in
            let ref = ChannelRef(.output, output)
            let name = hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? "Output \(output + 1)"
            return HomeChoice(output: output, name: name, roles: [])
        }
        // Only while TotalMix FX answers: a closed TotalMix FX shows no stale warning (review of
        // 2026-11-02).
        status.muteMasterOff = status.totalMixAnswering && hub.mirror.muteMaster == false
        status.channelCount = hub.mirror.channels.count
        status.levelsSeen = levelsSeen
        status.homeSubmix = hub.homeSubmix
        status.playbacksOnNewPage = hub.layout.playbacksOnNewPage
        status.monitoringOutputs = Self.monitoringChoices(hub.mirror)
        status.otherOutputs = Self.otherChoices(hub.mirror, layout: hub.layout)
        let errors = [socketError, midiError, lcError].compactMap { $0 }
        status.error = errors.isEmpty ? nil : errors.joined(separator: "\n")
        return status
    }

    /// The monitoring outputs of a mirror, in output order, with their names and roles.
    public static func monitoringChoices(_ mirror: MixerMirror) -> [HomeChoice] {
        var roles: [Int: [MonitoringRole]] = [:]
        for role in MonitoringRole.allCases {
            if let output = mirror.monitoring[role] { roles[output, default: []].append(role) }
        }
        return roles.keys.sorted().map { output in
            let name = mirror.channels[ChannelRef(.output, output)]?.name ?? "Output \(output + 1)"
            return HomeChoice(output: output, name: name, roles: roles[output] ?? [])
        }
    }

    /// The outputs of a mirror that are not monitoring outputs, in the layout's order. Outputs hidden
    /// from this OSC remote in TotalMix FX are left out.
    public static func otherChoices(_ mirror: MixerMirror, layout: PerformanceLayout) -> [HomeChoice] {
        let monitoring = mirror.monitoringOutputs
        return layout.channels(.outputs, in: mirror).map(\.channel)
            .filter { !monitoring.contains($0) }.map { output in
            let name = mirror.channels[ChannelRef(.output, output)]?.name ?? "Output \(output + 1)"
            return HomeChoice(output: output, name: name, roles: [])
        }
    }

    private func publishStatus() {
        lock.lock()
        let status = makeStatus()
        lastStatus = status
        let logs = takeLogs()
        lock.unlock()
        logs.forEach(log)
        onStatus?(status)
    }

    private func publishStatusIfChanged() {
        lock.lock()
        let status = makeStatus()
        let previous = lastStatus
        let changed = status != previous
        if changed { lastStatus = status }
        let logs = takeLogs()
        lock.unlock()
        logs.forEach(log)
        guard changed else { return }
        if status.totalMixAnswering != previous.totalMixAnswering {
            log(status.totalMixAnswering ? "TotalMix FX is answering" : "No answer from TotalMix FX for \(Int(Self.totalMixTimeout)) s")
        }
        if status.rotoConnected != previous.rotoConnected {
            log(status.rotoConnected ? "Roto-Control connected" : "Roto-Control disconnected")
        }
        if status.launchControlConnected != previous.launchControlConnected, let name = status.launchControlName {
            log(status.launchControlConnected ? "\(name) connected (DAW mode)" : "\(name) disconnected")
        }
        onStatus?(status)
    }

    /// Lines to log once the lock is released.
    private var pendingLogs: [String] = []

    private func takeLogs() -> [String] {
        defer { pendingLogs = [] }
        return pendingLogs
    }

    private func log(_ text: String) {
        onLog?(text)
    }
}
