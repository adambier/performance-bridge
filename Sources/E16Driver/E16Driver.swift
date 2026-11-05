import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(OXIE16)
import OXIE16
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif

/// What the E16 driver produces in answer to MIDI or a call: SysEx for the device, and the core's
/// output for TotalMix FX and the other surfaces.
public struct E16Step: Equatable, Sendable {
    /// Complete MIDI messages for the device's first USB port ("OXI E16 Port 1"), in order.
    public var midi: [UInt8] = []
    /// Messages for TotalMix FX, and updates for the other surfaces. This driver's own updates are
    /// already turned into `midi`.
    public var core = CoreOutput()

    /// Nothing to send.
    public init() {}
}

/// The driver for the OXI E16 in its Remote Mode, on top of `SurfaceHub`.
///
/// Like the other drivers, it does no input or output: the app passes it the bytes from the
/// device's first USB port with `receive(_:hub:now:)`, the hub's output with `take(_:hub:now:)`,
/// and the time with `tick(hub:now:)`, and sends on what comes back.
///
/// **Layout** (decided with Adam, 2026-11-04; docs/OXI-E16.md, section 4). Sixteen strips, one
/// encoder each, always the sources:
/// - turn: the strip's level in the home submix, or its pan or its send to one output, as the
///   surface's function is set (`function`);
/// - a short push (under `pflHold`): mute, on release; a push held `pflHold`: PFL;
/// - with Shift held the encoders are buttons (`ShiftButton`, as OXI's own firmware does it):
///   the modes LEVEL, PAN, and SEND (encoders 1–3), the previous and next send output (11 and
///   12), the previous and next page of sixteen strips (15 and 16); the screen names them and
///   the rings show the mode in use and which arrows go somewhere;
/// - the ring shows the strip's color, filled to its level (bipolar for a pan), and the switch
///   states by shape and motion, orange for mute and yellow for PFL (`look`, and the rules in
///   its comment); the screen's title shows the function and the page, "PFL" while any PFL is
///   on, and for a moment the value of a turned encoder or the result of a push.
///
/// **Layers.** The hub gives a surface one switch per strip, and the E16's push is mute or PFL,
/// so the driver adds two hub surfaces: the main one (the knob's function, with mute) and a PFL
/// one (level, unused, with PFL), paged together.
public struct E16Driver: Sendable {
    /// The hub surface for each layer.
    public enum Layer: String, Sendable, CaseIterable {
        /// The encoders' function, and mute.
        case main
        /// PFL (its knobs are unused).
        case pfl
    }

    /// The start of the hub surfaces' names; each layer adds its own (e.g., "e16.main").
    public let name: String

    /// What the encoders do now: level, pan, or a send (an index into `SurfaceHub.sendTargets`).
    public private(set) var function = KnobFunction.level
    /// The send output (an index into `SurfaceHub.sendTargets`) SEND goes back to.
    private var lastSend = 0
    /// Whether the screen is drawn by the driver (the FRAMEBUFFER message, with this project's
    /// small font: a title and labels fitted to `labelMaxWidth`) rather than by the firmware's own label
    /// layout (a title and four characters a label). Adam, 2026-11-04: four characters can't
    /// name a stereo pair.
    public var drawsScreen = true
    /// The widest a label may be on the host-drawn screen, in pixels: a 32-pixel cell with at
    /// least 6 pixels between neighbors (Adam, 2026-11-04: 3 was too close).
    public static let labelMaxWidth = 26
    /// How bright the rings are, 0…1, applied to every color sent: full was too bright for a
    /// dark room, and 70% still a little (Adam, 2026-11-04). A lit part never goes below 1.
    public var brightness: Double = E16Driver.defaultBrightness
    /// The brightness a new setting starts at.
    public static let defaultBrightness = 0.55
    /// The name of the device's first USB MIDI port, the one Remote Mode uses.
    public static let defaultPortName = "OXI E16 Port 1"

    /// How many strips the device shows at once.
    public static let stripCount = 16
    /// How often ENTER REMOTE MODE is sent again until the device answers, in seconds.
    public static let enterInterval: Double = 1
    /// How long a push must be held to be PFL rather than mute, in seconds. A mute acts when a
    /// shorter push is released (Adam, 2026-11-04: Shift + push went to the button page). A
    /// second, with a countdown on the screen and the ring, since a hand resting on an encoder
    /// must not put a channel on PFL by mistake (Adam, 2026-11-04).
    public static let pflHold: Double = 1
    /// How long a push may last before the countdown starts drawing, in seconds, so a tap to mute
    /// never flashes the countdown (UI review, 2026-11-04).
    public static let tapTime: Double = 0.25
    /// How often the countdown is redrawn, in seconds.
    public static let countdownStep: Double = 0.1
    /// The PFL heartbeat: the ring is a complete yellow ring for `heartbeatOn` of each
    /// `heartbeatPeriod`, then dips to what is underneath for the rest.
    public static let heartbeatPeriod: Double = 1
    /// How long the heartbeat's ring is complete, in seconds.
    public static let heartbeatOn: Double = 0.8

    /// What an encoder does as a button while Shift is held: a mode button (LEVEL, PAN, SEND:
    /// one of them is in use) or a step button (an arrow: it goes somewhere, or nowhere).
    public enum ShiftButton: Hashable, Sendable {
        /// The encoders set levels.
        case level
        /// The encoders set pans.
        case pan
        /// The encoders set sends, to the output last used.
        case send
        /// The encoders set sends to the previous output, or the next.
        case output(Int)
        /// The previous page of strips, or the next.
        case page(Int)

        /// The encoder each button is on: the modes on the first row, the output arrows at the
        /// end of the third, the page arrows at the end of the last (Adam, 2026-11-04).
        public static let layout: [Int: ShiftButton] = [
            0: .level, 1: .pan, 2: .send, 10: .output(-1), 11: .output(1), 14: .page(-1), 15: .page(1),
        ]

        /// The label on the screen.
        public var label: String {
            switch self {
            case .level: return "LVL"
            case .pan: return "PAN"
            case .send: return "SEND"
            case .output(let d): return d < 0 ? "<SND" : "SND>"
            case .page(let d): return d < 0 ? "<PG" : "PG>"
            }
        }

        /// The label on the host-drawn screen: the arrows are 28 px, 2 px over `labelMaxWidth`
        /// (a 4 px gap to the next cell, accepted on the device; Adam, 2026-11-04).
        public var longLabel: String {
            switch self {
            case .level: return "LEVEL"
            case .pan: return "PAN"
            case .send: return "SEND"
            case .output(let d): return d < 0 ? "<SEND" : "SEND>"
            case .page(let d): return d < 0 ? "<PAGE" : "PAGE>"
            }
        }

        /// Whether this is a mode button (else an arrow).
        public var isMode: Bool {
            switch self {
            case .level, .pan, .send: return true
            case .output, .page: return false
            }
        }
    }
    /// How far one unit of a turn moves a level or send, as a fraction of the fader's travel. The
    /// device sends 1–8 units a message with its own acceleration.
    public static let levelStep: Double = 0.0025
    /// How far one unit of a turn moves a pan, as a fraction of the hub's 0…1 (about one of
    /// TotalMix FX's 200 steps).
    public static let panStep: Double = 0.005
    /// How many of the title's 16 characters the device shows: the last one was cut off ("PF"
    /// for "PFL" at the end; seen 2026-11-04).
    public static let titleWidth = 15
    /// How long the title shows a turned encoder's value or a press's result, in seconds.
    public static let overlayTime: Double = 1
    /// How long each half of a flashing mute lasts, in seconds (a mute set while TotalMix FX's Mute
    /// Master is off, as on the other surfaces).
    public static let blinkPeriod: Double = 0.5

    private var connected = false
    private var lastEnter: Double?
    private var shiftHeld = false
    private var blinkLit = true
    /// Whether PFL rings are in the complete-ring phase of their heartbeat now.
    private var heartbeatHigh = true
    private var overlay: (text: String, until: Double)?
    /// The encoder held down, if any, since when, and whether the hold has already toggled PFL.
    /// Its overlay stays until it is released (Adam, 2026-11-04).
    private var held: (encoder: Int, since: Double, didPFL: Bool)?
    /// The Shift-page button held down, if any: its ring is full bright while it is (Adam,
    /// 2026-11-04).
    private var pressedButton: Int?
    /// The countdown step last drawn for a held push.
    private var countdownShown = -1
    private var page = (first: 0, count: 0)
    private var infos: [StripInfo?] = Array(repeating: nil, count: E16Driver.stripCount)
    private var knobValues: [Double?] = Array(repeating: nil, count: E16Driver.stripCount)
    private var muteOn: [Bool] = Array(repeating: false, count: E16Driver.stripCount)
    private var pflOn: [Bool] = Array(repeating: false, count: E16Driver.stripCount)
    private var sentLabels: [UInt8]?
    /// What the last screen showed (its title parts and labels), so the framebuffer is drawn and
    /// packed only when something on it changed, not on every tick (review of 2026-11-04).
    private var shownScreen: (title: String, tail: String, labels: [String])?
    private var sentRings: [RingLook?] = Array(repeating: nil, count: E16Driver.stripCount)

    /// How one encoder's ring is drawn: a RING message alone. The single-LED message is never
    /// used: on the device it is a persistent override that outlives later fills and inverts the
    /// encoder's label until a power cycle (seen 2026-11-04).
    struct RingLook: Hashable {
        var ring: E16Ring
        /// Whether the ring's color is sent as it is, outside the driver's `brightness`: the
        /// Shift page's dim and maximum levels.
        var exact = false
    }

    /// A driver for one device; `name` starts the hub surfaces' names.
    public init(name: String) {
        self.name = name
    }

    /// Whether the device has answered ENTER REMOTE MODE.
    public var isConnected: Bool { connected }

    /// The hub surface for a layer.
    public func id(_ layer: Layer) -> SurfaceID { SurfaceID("\(name).\(layer.rawValue)") }

    /// What each layer has, for the hub: sixteen strips with an endless encoder and a ring, which
    /// follow TotalMix FX, and a switch.
    public static let capabilities = SurfaceCapabilities(stripCount: stripCount, feel: .follows, hasSwitches: true)

    // MARK: - Starting and stopping

    /// Adds the layers to the hub and returns the bytes that ask for Remote Mode. Until the device
    /// answers, `tick(hub:now:)` asks again every `enterInterval`.
    public mutating func start(hub: inout SurfaceHub, now: Double) -> E16Step {
        for layer in Layer.allCases {
            _ = hub.addSurface(id(layer), capabilities: Self.capabilities, mode: mode(for: layer, first: page.first), now: now)
        }
        connected = false
        lastEnter = now
        var step = E16Step()
        step.midi = E16Outgoing.enterRemoteMode
        return step
    }

    /// The bytes that give the device back (EXIT REMOTE MODE; without it the device stays blank),
    /// for when the app quits or the device is let go; and the layers leave the hub.
    public mutating func stop(hub: inout SurfaceHub) -> [UInt8] {
        for layer in Layer.allCases { hub.removeSurface(id(layer)) }
        connected = false
        lastEnter = nil
        return E16Outgoing.exitRemoteMode
    }

    /// What is due as time passes: ENTER asked again while the device hasn't answered, a push
    /// held long enough for PFL (with its countdown), an overlay ending, and flashing mutes.
    public mutating func tick(hub: inout SurfaceHub, now: Double) -> E16Step {
        var step = E16Step()
        if !connected, let lastEnter, now - lastEnter >= Self.enterInterval {
            self.lastEnter = now
            step.midi += E16Outgoing.enterRemoteMode
        }
        guard connected else { return step }
        if let held, !held.didPFL {
            if now - held.since >= Self.pflHold {
                self.held = (held.encoder, held.since, true)
                pfl(held.encoder, hub: &hub, now: now, into: &step)
            } else if now - held.since >= Self.tapTime {
                // The countdown, after the tap window: the title says where the hold leads, and
                // a yellow arc sweeps the ring (growing for PFL on, shrinking for off; Adam and
                // the UI review, 2026-11-04).
                let stepIndex = Int((now - held.since - Self.tapTime) / Self.countdownStep + 1e-6)
                if stepIndex != countdownShown {
                    let first = countdownShown < 0
                    countdownShown = stepIndex
                    if first, let info = infos[held.encoder] {
                        overlay = (Self.fit(info.name, 7) + (pflOn[held.encoder] ? " -> PFL OFF" : " -> PFL"), .infinity)
                        step.midi += drawLabels(hub: hub)
                    }
                    step.midi += drawRing(held.encoder, hub: hub)
                }
            }
        }
        if let overlay, now >= overlay.until {
            self.overlay = nil
            step.midi += drawLabels(hub: hub)
        }
        let lit = Int((now / Self.blinkPeriod).rounded(.down)) % 2 == 0
        let high = now.truncatingRemainder(dividingBy: Self.heartbeatPeriod) < Self.heartbeatOn
        if lit != blinkLit || high != heartbeatHigh {
            blinkLit = lit
            heartbeatHigh = high
            step.midi += drawRings(hub: hub)  // only the rings that change are sent
        }
        return step
    }

    // MARK: - From the device

    private var parser = E16Parser()

    /// Takes bytes from the device's first USB port, as they arrive.
    public mutating func receive<S: Sequence>(_ bytes: S, hub: inout SurfaceHub, now: Double) -> E16Step
    where S.Element == UInt8 {
        var step = E16Step()
        for event in parser.feed(bytes) { handle(event, hub: &hub, now: now, into: &step) }
        return step
    }

    private mutating func handle(_ event: E16Event, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        if let overlay, now >= overlay.until { self.overlay = nil }
        if case .remoteEntered = event {
            connect(hub: &hub, now: now, into: &step)
            return
        }
        // Only the ACK shows the device is in Remote Mode: a turn or a push looks the same from
        // a device in its own scene (CC 1–16 and notes on channel 1), and taking one as proof
        // would stop the ENTER retries and move faders by the scene's values (review of
        // 2026-11-04). ENTER is asked again every `enterInterval` until the ACK comes.
        if !connected { return }
        switch event {
        case .turned(let encoder, let delta):
            guard (0..<Self.stripCount).contains(encoder), !shiftHeld else { return }
            turn(encoder, by: delta, hub: &hub, now: now, into: &step)
        case .pushed(let encoder, true):
            guard (0..<Self.stripCount).contains(encoder) else { return }
            if shiftHeld {
                pressedButton = encoder
                if let button = ShiftButton.layout[encoder] { press(button, hub: &hub, now: now, into: &step) }
                step.midi += drawRing(encoder, hub: hub)
            } else {
                held = (encoder, now, false)
                countdownShown = -1
            }
        case .pushed(let encoder, false):
            if pressedButton == encoder {
                pressedButton = nil
                step.midi += drawRing(encoder, hub: hub)
            }
            guard let held, held.encoder == encoder else { return }
            self.held = nil
            if !held.didPFL, !shiftHeld {
                overlay = nil  // the countdown
                mute(encoder, hub: &hub, now: now, into: &step)
            }
            if let overlay, overlay.until == .infinity { self.overlay = (overlay.text, now + Self.overlayTime) }
            step.midi += drawRing(encoder, hub: hub)
        case .shift(let down):
            shiftHeld = down
            held = nil
            pressedButton = nil
            overlay = nil
            step.midi += drawLabels(hub: hub) + drawRings(hub: hub)
        default:
            break
        }
    }

    private mutating func connect(hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        connected = true
        lastEnter = nil
        shiftHeld = false
        overlay = nil
        held = nil
        pressedButton = nil
        blinkLit = true
        sentLabels = nil
        shownScreen = nil
        sentRings = Array(repeating: nil, count: Self.stripCount)
        var output = CoreOutput()
        for layer in Layer.allCases { output.append(hub.resend(id(layer), now: now)) }
        take(output, hub: hub, into: &step)
    }

    /// Sets the rings' brightness from the app and redraws every ring at it, on a connected
    /// device; kept for the next one otherwise.
    public mutating func setBrightness(_ value: Double, hub: SurfaceHub) -> [UInt8] {
        brightness = value
        guard connected else { return [] }
        sentRings = Array(repeating: nil, count: Self.stripCount)
        return drawRings(hub: hub)
    }

    // MARK: - Controls

    /// An encoder turned without Shift: moves its strip's knob by `delta` units.
    private mutating func turn(_ encoder: Int, by delta: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        guard let strips = hub.strips(of: id(.main)), strips.indices.contains(encoder),
              let target = strips[encoder].knobTarget else { return }
        let stored = hub.mirror.value(of: target)
        let current: Double
        let stepSize: Double
        if case .pan = target {
            current = stored.map { ($0 + 1) / 2 } ?? 0.5
            stepSize = Self.panStep
        } else {
            current = stored ?? 0
            stepSize = Self.levelStep
        }
        let position = min(max(current + Double(delta) * stepSize, 0), 1)
        take(hub.controlMoved(id(.main), strip: encoder, to: position, now: now), hub: hub, into: &step)
        // The hub doesn't send a surface its own move back: draw the ring from the mirror, and
        // show the value in the title.
        let moved = hub.mirror.value(of: target)
        knobValues[encoder] = isPan ? moved.map { ($0 + 1) / 2 } : moved
        step.midi += drawRing(encoder, hub: hub)
        if let info = infos[encoder], let moved {
            let text = isPan ? ValueText.pan(moved) : ValueText.level(position: moved)
            show(Self.fit(info.name, 8) + " " + text, now: now, into: &step, hub: hub)
        }
    }

    /// A short push released: toggles the strip's mute and says so on the screen.
    private mutating func mute(_ encoder: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        take(hub.switchPressed(id(.main), strip: encoder, now: now), hub: hub, into: &step)
        guard let info = infos[encoder] else { return }
        // While Mute Master is off a mute is "set", TotalMix FX's own notion, and does nothing in
        // the audio; the ring's blink says so continuously, so the title says what the press did.
        let on = muteOn[encoder]
        let result = hub.mirror.muteMaster == false ? (on ? " MUTE SET" : " MUTE CLR") : (on ? " MUTE ON" : " MUTE OFF")
        show(Self.fit(info.name, 7) + result, now: now, into: &step, hub: hub)
    }

    /// A push held `pflHold`: toggles the strip's PFL and says so on the screen.
    private mutating func pfl(_ encoder: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        take(hub.switchPressed(id(.pfl), strip: encoder, now: now), hub: hub, into: &step)
        guard let info = infos[encoder] else { return }
        show(Self.fit(info.name, 7) + " PFL" + (pflOn[encoder] ? " ON" : " OFF"), now: now, into: &step, hub: hub)
    }

    /// A button on the Shift page pressed.
    private mutating func press(_ button: ShiftButton, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        switch button {
        case .level: setFunction(.level, hub: &hub, now: now, into: &step)
        case .pan: setFunction(.pan, hub: &hub, now: now, into: &step)
        case .send:
            let count = hub.sendTargets.count
            guard count > 0 else { return }
            setFunction(.send(min(lastSend, count - 1)), hub: &hub, now: now, into: &step)
        case .output(let direction):
            let count = hub.sendTargets.count
            guard count > 0 else { return }
            // Not in SEND mode, either arrow enters it at the last output used.
            let current: Int = { if case .send(let n) = function { return n } else { return min(lastSend, count - 1) - direction } }()
            let next = current + direction
            guard (0..<count).contains(next) else { return }
            setFunction(.send(next), hub: &hub, now: now, into: &step)
        case .page(let direction):
            movePage(by: direction, hub: &hub, now: now, into: &step)
        }
    }

    private mutating func setFunction(_ next: KnobFunction, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        guard next != function else { return }
        function = next
        if case .send(let n) = next { lastSend = n }
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        step.midi += drawLabels(hub: hub) + drawRings(hub: hub)
    }

    /// Whether a Shift button does something now: an output or page beyond the ends does not.
    func isAvailable(_ button: ShiftButton, hub: SurfaceHub) -> Bool {
        switch button {
        case .level, .pan: return true
        case .send: return !hub.sendTargets.isEmpty
        case .output(let direction):
            let count = hub.sendTargets.count
            guard count > 0 else { return false }
            let current: Int = { if case .send(let n) = function { return n } else { return min(lastSend, count - 1) - direction } }()
            return (0..<count).contains(current + direction)
        case .page(let direction):
            let current = page.first / Self.stripCount
            return (0..<pageCount).contains(current + direction)
        }
    }

    /// How many pages of strips there are.
    var pageCount: Int { max(1, Int((Double(page.count) / Double(Self.stripCount)).rounded(.up))) }

    /// Moves both layers a page (`direction` ±1), staying within the view.
    private mutating func movePage(by direction: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        let primary = id(.main)
        var output = hub.page(primary, by: direction, now: now)
        if case .strips(_, let first, _, _)? = hub.mode(of: primary) {
            output.append(hub.setMode(id(.pfl), mode(for: .pfl, first: first), now: now))
        }
        take(output, hub: hub, into: &step)
        step.midi += drawLabels(hub: hub) + drawRings(hub: hub)
    }

    // MARK: - Modes

    /// The hub mode for a layer: the sources, from `first`, with the encoders' function and mute
    /// on the main layer, or level and PFL on the PFL layer.
    func mode(for layer: Layer, first: Int) -> SurfaceMode {
        switch layer {
        case .main: return .strips(view: .sources, first: first, knob: function, switch: .mute)
        case .pfl: return .strips(view: .sources, first: first, knob: .level, switch: .pfl)
        }
    }

    private mutating func setModes(first: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        var output = CoreOutput()
        for layer in Layer.allCases {
            let mode = mode(for: layer, first: first)
            if hub.mode(of: id(layer)) != mode { output.append(hub.setMode(id(layer), mode, now: now)) }
        }
        take(output, hub: hub, into: &step)
    }

    private var isPan: Bool { if case .pan = function { return true } else { return false } }

    // MARK: - To the device

    /// Moves this driver's updates out of a core output (e.g., the hub's answer to TotalMix FX) and
    /// into SysEx. A function that is a send past the end (an output gone from TotalMix FX) falls
    /// back to level.
    public mutating func take(_ output: CoreOutput, hub: inout SurfaceHub, now: Double) -> E16Step {
        var step = E16Step()
        take(output, hub: hub, into: &step)
        if case .send(let n) = function, n >= hub.sendTargets.count {
            function = .level
            setModes(first: page.first, hub: &hub, now: now, into: &step)
        }
        if connected { step.midi += drawLabels(hub: hub) + drawRings(hub: hub) }
        return step
    }

    private mutating func take(_ output: CoreOutput, hub: SurfaceHub, into step: inout E16Step) {
        var output = output
        var own: [(Layer, [SurfaceUpdate])] = []
        for layer in Layer.allCases {
            if let updates = output.updates.removeValue(forKey: id(layer)) { own.append((layer, updates)) }
        }
        step.core.append(output)
        guard !own.isEmpty else { return }
        var touched = Set<Int>()
        for (layer, list) in own {
            for update in list {
                switch update {
                case .page(let first, let count):
                    if layer == .main { page = (first, count) }
                case .strip(let index, let info):
                    guard layer == .main, infos.indices.contains(index) else { continue }
                    infos[index] = info
                    touched.insert(index)
                case .knob(let index, let value):
                    guard layer == .main, knobValues.indices.contains(index) else { continue }
                    knobValues[index] = value
                    touched.insert(index)
                case .valueText:
                    break  // the title shows the value of a turn from `turn(_:by:hub:now:into:)`
                case .switchState(let index, let on):
                    guard muteOn.indices.contains(index) else { continue }
                    if layer == .main { muteOn[index] = on } else { pflOn[index] = on }
                    touched.insert(index)
                case .meter:
                    break
                }
            }
        }
        guard connected else { return }
        for index in touched.sorted() { step.midi += drawRing(index, hub: hub) }
        step.midi += drawLabels(hub: hub)
    }

    /// Shows `text` in the title for `overlayTime`, or while an encoder is held and `overlayTime`
    /// after.
    private mutating func show(_ text: String, now: Double, into step: inout E16Step, hub: SurfaceHub) {
        overlay = (text, held == nil ? now + Self.overlayTime : .infinity)
        step.midi += drawLabels(hub: hub)
    }

    /// The screen: the title and the sixteen labels, sent only when they change; drawn by the
    /// driver (`drawsScreen`) or by the firmware's label layout.
    private mutating func drawLabels(hub: SurfaceHub) -> [UInt8] {
        guard connected else { return [] }
        let labels: [String] = (0..<Self.stripCount).map { index in
            if shiftHeld {
                // An arrow that goes nowhere shows no label either (Adam, 2026-11-04).
                guard let button = ShiftButton.layout[index], button.isMode || isAvailable(button, hub: hub) else { return "" }
                return drawsScreen ? button.longLabel : button.label
            }
            let name = infos[index]?.name ?? ""
            return drawsScreen ? Self.fit(name, width: Self.labelMaxWidth) : Self.fit(name, E16Outgoing.labelLength)
        }
        let parts = titleParts(hub: hub)
        if let shown = shownScreen, shown.title == parts.0, shown.tail == parts.1, shown.labels == labels { return [] }
        shownScreen = (parts.0, parts.1, labels)
        let bytes = drawsScreen ? E16Outgoing.framebuffer(Self.screen(title: parts.0, tail: parts.1, labels: labels))
            : E16Outgoing.labels(title: title(hub: hub), labels: labels)
        guard bytes != sentLabels else { return [] }
        sentLabels = bytes
        return bytes
    }

    /// The host-drawn screen, on a grid of four columns: the title in the first column and its
    /// tail ("PFL 2/3") ending at the last column's edge, a rule under them, and the sixteen
    /// labels in four rows 14 pixels apart, each at the left of its 32-pixel cell and no wider
    /// than `labelMaxWidth`. Everything in a column starts on the same pixel, so the title
    /// lines up with the labels (Adam, 2026-11-04).
    public static func screen(title: String, tail: String = "", labels: [String]) -> E16Screen {
        var screen = E16Screen()
        let cell = E16Screen.width / 4
        let margin = (cell - labelMaxWidth) / 2
        screen.draw(title, x: margin, y: 0)
        if !tail.isEmpty {
            let x = E16Screen.width - margin - E16Screen.width(of: tail)
            // Blank the title under the tail if a long one runs into it.
            for px in (x - 3)..<E16Screen.width { for py in 0..<8 { screen.set(px, py, false) } }
            screen.draw(tail, x: x, y: 0)
        }
        screen.line(y: 10, from: 0, to: E16Screen.width - 1)
        for (index, label) in labels.prefix(stripCount).enumerated() {
            screen.draw(label, x: (index % 4) * cell + margin, y: 14 + (index / 4) * 14)
        }
        return screen
    }

    /// The title: an overlay while one shows; else the function ("LEVEL", "PAN", "> PHONES 1"),
    /// "PFL" while any strip's PFL is on (TotalMix FX doesn't echo a PFL and "Cue/PFL to" can't
    /// be read, so the app's own record is the only one; UI review, 2026-11-04), and, with more
    /// than one page, the page. The same with Shift held, so the choice made there shows at
    /// once and stays (Adam, 2026-11-04).
    public func title(hub: SurfaceHub) -> String {
        let (name, tail) = titleParts(hub: hub)
        guard !tail.isEmpty else { return name }
        let width = Self.titleWidth - tail.count - 1
        return Self.fit(name, width).padding(toLength: width, withPad: " ", startingAt: 0) + " " + tail
    }

    /// The title in two parts: the text on the left (the function or an overlay) and, on the
    /// right, the "PFL" marker and the page ("PFL 2/3"), or nothing (an overlay has the whole
    /// title). On the host-drawn screen they are left- and right-justified (Adam, 2026-11-04).
    public func titleParts(hub: SurfaceHub) -> (String, String) {
        if let overlay { return (overlay.text, "") }
        var tail: [String] = []
        if pflOn.contains(true) { tail.append("PFL") }
        if pageCount > 1 { tail.append("\(page.first / Self.stripCount + 1)/\(pageCount)") }
        return (functionName(hub: hub), tail.joined(separator: " "))
    }

    /// The function's name for the title: "LEVEL", "PAN", or "> " and the send's output.
    public func functionName(hub: SurfaceHub) -> String {
        switch function {
        case .level: return "LEVEL"
        case .pan: return "PAN"
        case .send(let index):
            let targets = hub.sendTargets
            guard targets.indices.contains(index) else { return "SEND" }
            let ref = ChannelRef(.output, targets[index])
            let name = hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? ref.description
            return "> " + name.uppercased()
        }
    }

    /// Every ring, sent only where it changed, in one RING message.
    private mutating func drawRings(hub: SurfaceHub) -> [UInt8] {
        var rings: [(encoder: Int, ring: E16Ring)] = []
        for index in 0..<Self.stripCount {
            let look = look(index, hub: hub)
            guard sentRings[index] != look else { continue }
            sentRings[index] = look
            rings.append((index, look.exact ? look.ring : dimmed(look.ring)))
        }
        return E16Outgoing.rings(rings)
    }

    /// A lit part of a color never goes below this when dimmed, and the scaling starts from it:
    /// at low brightness a small part scaled all the way down vanished, so orange and red were
    /// the same below about 10% (Adam, 2026-11-04). The LEDs are bright already at 3 or 4.
    public static let dimFloor: UInt8 = 4

    /// A part of a color at the driver's `brightness`: `dimFloor` plus the rest scaled, so the
    /// parts keep their proportions above the floor and a lit part stays visibly lit.
    private func dim(_ part: UInt8) -> UInt8 {
        guard part > 0 else { return 0 }
        guard part > Self.dimFloor else { return part }
        let scale = brightness.isFinite ? min(max(brightness, 0), 1) : 1
        let above = Double(part - Self.dimFloor) * scale
        return UInt8(min(Double(Self.dimFloor) + above.rounded(), 127))
    }

    private func dimmed(_ ring: E16Ring) -> E16Ring {
        E16Ring(red: dim(ring.red), green: dim(ring.green), blue: dim(ring.blue), amount: ring.amount, bipolar: ring.bipolar)
    }

    private mutating func drawRing(_ index: Int, hub: SurfaceHub) -> [UInt8] {
        let look = look(index, hub: hub)
        guard sentRings[index] != look else { return [] }
        sentRings[index] = look
        return E16Outgoing.rings([(encoder: index, ring: look.exact ? look.ring : dimmed(look.ring))])
    }

    /// A strip's ring, by the rules from the UI review (2026-11-04), drawn with RING messages
    /// alone:
    /// - dark means no channel: a strip with a channel always lights at least one LED (`floor`,
    ///   as OXI's own "Color Indicator" setting does);
    /// - a complete ring always means a switch is on: a level never fills the last LED (`cap`);
    /// - color is the second cue, shape and motion the first: orange for mute, yellow for PFL,
    ///   the colors the other surfaces use;
    /// - one meaning per motion: steady is a value or a state; a symmetric blink (full orange
    ///   ring ↔ half ring, `blinkPeriod` each) is a mute that is set but not in effect while
    ///   TotalMix FX's Mute Master is off; the heartbeat (`heartbeatOn` of each
    ///   `heartbeatPeriod` a complete yellow ring, then a dip to what is underneath: the level,
    ///   or the mute's ring) is PFL; a one-shot yellow arc growing (or, for PFL off, shrinking)
    ///   is the push held for PFL.
    func look(_ index: Int, hub: SurfaceHub) -> RingLook {
        if shiftHeld { return buttonRing(index, hub: hub) }
        guard let info = infos[index], let value = knobValues[index] else { return RingLook(ring: .off) }
        if let held, held.encoder == index, !held.didPFL, countdownShown >= 0 {
            let progress = min(Double(countdownShown) * Self.countdownStep / (Self.pflHold - Self.tapTime), 1)
            let amount = pflOn[index] ? 1 - progress : progress
            return RingLook(ring: E16Ring(red: Self.pflRGB.0, green: Self.pflRGB.1, blue: Self.pflRGB.2, amount: amount))
        }
        var rgb = Self.rgb(for: info)
        if case .send(let n) = function, hub.sendTargets.indices.contains(n) {
            let output = ChannelRef(.output, hub.sendTargets[n])
            if let color = hub.mirror.channels[output]?.color, color != 1, let sendRGB = Self.totalMixRGB[color] { rgb = sendRGB }
        }
        let level: E16Ring = isPan
            ? E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: value, bipolar: true)
            : E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: min(max(value, Self.floor), Self.cap))
        var underneath = level
        if muteOn[index] {
            let amount = hub.mirror.muteMaster == false && !blinkLit ? 0.5 : 1
            underneath = E16Ring(red: Self.muteRGB.0, green: Self.muteRGB.1, blue: Self.muteRGB.2, amount: amount)
        }
        if pflOn[index], heartbeatHigh {
            return RingLook(ring: E16Ring(red: Self.pflRGB.0, green: Self.pflRGB.1, blue: Self.pflRGB.2, amount: 1))
        }
        return RingLook(ring: underneath)
    }

    /// The least a strip with a channel lights, as a fraction of the ring: one LED.
    public static let floor = 1.0 / 16
    /// The most a level lights, as a fraction of the ring: fifteen LEDs, so a complete ring is
    /// a switch.
    public static let cap = 15.0 / 16

    /// A ring on the Shift page, full, in the button's color (`buttonColors`), at one of four
    /// levels (Adam, 2026-11-04, after the brightness ramp): dark for a blank or an arrow that
    /// goes nowhere; `availableLevel` (a color scaled to a maximum part of 2 of 127, the lowest
    /// level that reads as lit) for a button that is available; the driver's `brightness` for
    /// the mode in use; and the full 127 while a button is held down, a momentary answer to
    /// the press.
    func buttonRing(_ index: Int, hub: SurfaceHub) -> RingLook {
        guard let button = ShiftButton.layout[index] else { return RingLook(ring: .off) }
        let rgb: (UInt8, UInt8, UInt8)
        var inUse = false
        switch button {
        case .level: rgb = Self.buttonColors.level; inUse = function == .level
        case .pan: rgb = Self.buttonColors.pan; inUse = function == .pan
        case .send:
            rgb = Self.buttonColors.send
            if case .send = function { inUse = true }
        case .output: rgb = Self.buttonColors.send
        case .page: rgb = Self.buttonColors.page
        }
        guard inUse || isAvailable(button, hub: hub) else { return RingLook(ring: .off) }  // dark stays dark, pressed or not
        let top = Double(max(rgb.0, rgb.1, rgb.2))
        if pressedButton == index {
            // The color with its largest part at 127, whatever the brightness: the deep green's
            // 60 would not show a press at full brightness (review of 2026-11-04).
            func full(_ v: UInt8) -> UInt8 { v == 0 ? 0 : UInt8(min((Double(v) / top * 127).rounded(), 127)) }
            return RingLook(ring: E16Ring(red: full(rgb.0), green: full(rgb.1), blue: full(rgb.2), amount: 1), exact: true)
        }
        if inUse { return RingLook(ring: E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: 1)) }
        func part(_ v: UInt8) -> UInt8 { v == 0 ? 0 : UInt8(max((Double(v) / top * Self.availableLevel).rounded(), 1)) }
        return RingLook(ring: E16Ring(red: part(rgb.0), green: part(rgb.1), blue: part(rgb.2), amount: 1), exact: true)
    }

    /// The largest part of an available button's color, 0–127: 2, the lowest value that read as
    /// lit on the device (Adam, 2026-11-04, from `sbdev e16 ramp`).
    public static let availableLevel = 2.0

    /// The Shift page's colors (Adam and the UI review, 2026-11-04): white for LEVEL (orange is
    /// the mute color), magenta for PAN, a deep green for SEND and the output arrows, a deep
    /// blue for the page arrows. The page shows no channel colors, so they only need to differ
    /// from each other. Color is an extra cue: the buttons' positions and labels, and the ring
    /// fills, carry the meaning.
    public static let buttonColors: (level: (UInt8, UInt8, UInt8), pan: (UInt8, UInt8, UInt8),
                                     send: (UInt8, UInt8, UInt8), page: (UInt8, UInt8, UInt8))
        = ((127, 127, 127), (127, 0, 100), (0, 60, 0), (0, 0, 127))

    /// Orange, for a mute, as on the other surfaces.
    public static let muteRGB: (UInt8, UInt8, UInt8) = (127, 16, 0)
    /// A pale yellow-green, for a PFL and for the countdown, apart from TotalMix FX's
    /// channel yellow, which is nearer orange (Adam, 2026-11-04).
    public static let pflRGB: (UInt8, UInt8, UInt8) = (110, 127, 18)

    /// An RGB (0–127 per part) for each of TotalMix FX's eight colors (1 white, 2 grey, 3 orange,
    /// 4 red, 5 blue, 6 green, 7 yellow, 8 pink; docs/TOTALMIX-OSC.md, test 7), as the Launch
    /// Control driver renders them.
    public static let totalMixRGB: [Int: (UInt8, UInt8, UInt8)] = [
        1: (127, 127, 127),
        2: (0, 110, 127),  // grey as cyan, the hue TotalMix FX leaves free: a dim grey looked like a dimmer white or a level, and blue-greys like blue (Adam, 2026-11-04)
        3: (127, 16, 0),   // orange, redder still, apart from the yellow that moved toward it (Adam, 2026-11-04)
        4: (127, 0, 0),
        5: (0, 0, 127),
        6: (0, 105, 0),    // green, slightly darker, further from PFL's yellow-green (Adam, 2026-11-04)
        7: (127, 72, 0),   // yellow, a little toward orange, so PFL's yellow-green stays apart from it (Adam, 2026-11-04)
        8: (70, 0, 127),   // purple: (16, 0, 127) was too close to blue on the device, (90, 0, 127) read as magenta (Adam, 2026-11-04)
    ]

    /// A strip's color: its TotalMix FX color, or white.
    public static func rgb(for info: StripInfo) -> (UInt8, UInt8, UInt8) {
        info.color.flatMap { totalMixRGB[$0] } ?? totalMixRGB[1]!
    }

    /// `text` cut to `length` characters, keeping what tells strips apart (UI review,
    /// 2026-11-04): a name that fits is kept as is; one that ends in a number or a pair ("ADAT
    /// 3/4", "PB 11/12") first keeps the whole pair: without its space ("ADAT3/4"), with the
    /// word's vowels gone ("ADT3/4"), or a playback's "PB" as "P" ("P11/12", "P1/2"); failing
    /// that it keeps its first number, loses "/n", and shortens its word: the space goes, then
    /// the vowels, then letters from the end ("AD11", "Mic1", "Anl1"); anything else is cut
    /// ("Tonv"). Hyphens go first ("ADI2").
    public static func fit(_ text: String, _ length: Int) -> String {
        candidates(text).first { $0.count <= length } ?? String(candidates(text).last!.prefix(length))
    }

    /// The same, for the host-drawn screen: the first form of `text` no wider than `width`
    /// pixels in the screen's font.
    public static func fit(_ text: String, width: Int) -> String {
        if let fit = candidates(text).first(where: { E16Screen.width(of: $0) <= width }) { return fit }
        // Nothing fits (three-digit pairs): cut the shortest form from the end rather than show
        // nothing for a strip that has a channel (review of 2026-11-04).
        var last = candidates(text).last ?? ""
        while !last.isEmpty, E16Screen.width(of: last) > width { last.removeLast() }
        return last
    }

    /// The forms of a channel name from longest to shortest: as it is; without hyphens
    /// ("ADI2"); for a stereo pair, the pair with less and less of its word ("ADAT3/4",
    /// "ADT3/4", "AD3/4", "A3/4", "3/4"; "P11/12", "11/12") and never less than the pair; for a
    /// single numbered name, the number after less and less of the word ("ADAT 3", "ADAT3",
    /// "ADT 3", "ADT3", "AD3", "A3", "3"); for anything else, the name cut from the end.
    static func candidates(_ text: String) -> [String] {
        var out = [text]
        let text = text.replacingOccurrences(of: "-", with: "")
        out.append(text)
        let parts = text.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        if parts.count >= 2, let last = parts.last, let number = last.split(separator: "/").first, Int(number) != nil {
            let word = parts.dropLast().joined(separator: " ")
            let vowels: Set<Character> = ["a", "e", "i", "o", "u", "A", "E", "I", "O", "U"]
            var tight = ""
            for (i, c) in word.enumerated() where i == 0 || !vowels.contains(c) { tight.append(c) }
            if last.contains("/") {
                // A stereo pair always shows both numbers (Adam, 2026-11-04): the word goes
                // first, without its space, then its vowels, then letters from the end, then
                // altogether ("ADAT3/4", "ADT3/4", "AD3/4", "A3/4", "3/4"; "P15/16", "15/16").
                out += [word + last]
                for k in stride(from: tight.count, through: 0, by: -1) { out.append(String(tight.prefix(k)) + last) }
                return out
            }
            let digits = String(number)
            out += [word + " " + digits, word + digits, tight + " " + digits]
            for k in stride(from: tight.count, through: 0, by: -1) { out.append(String(tight.prefix(k)) + digits) }
        } else {
            for k in stride(from: text.count - 1, through: 1, by: -1) { out.append(String(text.prefix(k))) }
        }
        return out
    }
}
