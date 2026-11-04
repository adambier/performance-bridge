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
/// **Layout** (decided with Adam, 2026-11-04; docs/OXI-E16.md, section 6). Sixteen strips, one
/// encoder each, always the sources:
/// - turn: the strip's level in the home submix, or its pan or its send to one output, as the
///   surface's function is set (`function`);
/// - a short push (under `pflHold`): mute, on release; a push held `pflHold`: PFL;
/// - with Shift held the encoders are buttons (`ShiftButton`, as OXI's own firmware does it):
///   the modes LEVEL, PAN, and SEND (encoders 1–3), the previous and next send output (11 and
///   12), the previous and next page of sixteen strips (15 and 16); the screen names them and
///   the rings show the mode in use and which arrows go somewhere;
/// - the ring shows the strip's color, filled to its level (bipolar for a pan), with red marks
///   while muted and a running white LED while on PFL (`look`); the screen's title shows the
///   function and the page, and for a moment the value of a turned encoder or the result of a
///   push.
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

    /// How many strips the device shows at once.
    public static let stripCount = 16
    /// How often ENTER REMOTE MODE is sent again until the device answers, in seconds.
    public static let enterInterval: Double = 1
    /// How long a push must be held to be PFL rather than mute, in seconds. A mute acts when a
    /// shorter push is released (Adam, 2026-11-04: Shift + push went to the button page). A
    /// second, with a countdown on the screen and the ring, since a hand resting on an encoder
    /// must not put a channel on PFL by mistake (Adam, 2026-11-04).
    public static let pflHold: Double = 1
    /// How often the countdown is redrawn, in seconds.
    public static let countdownStep: Double = 0.1

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
            case .level: return "LEVL"
            case .pan: return "PAN"
            case .send: return "SEND"
            case .output(let d): return d < 0 ? "<SND" : "SND>"
            case .page(let d): return d < 0 ? "<PG" : "PG>"
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
    /// How long the title shows a turned encoder's value or a press's result, in seconds.
    public static let overlayTime: Double = 1
    /// How long each half of a flashing mute lasts, in seconds (a mute set while TotalMix FX's Mute
    /// Master is off, as on the other surfaces).
    public static let blinkPeriod: Double = 0.5

    private var connected = false
    private var lastEnter: Double?
    private var shiftHeld = false
    private var blinkLit = true
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
    private var sentRings: [RingLook?] = Array(repeating: nil, count: E16Driver.stripCount)

    /// How one encoder's ring is drawn: the ring, then single LEDs over it (the needles).
    struct RingLook: Hashable {
        var ring: E16Ring
        var leds: [LED] = []
        struct LED: Hashable { var index: Int; var red: UInt8; var green: UInt8; var blue: UInt8 }
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
            } else {
                // The countdown: the title says what the hold does, and a white arc grows round
                // the ring like a clock face (Adam, 2026-11-04).
                let stepIndex = Int((now - held.since) / Self.countdownStep + 1e-6)
                if stepIndex != countdownShown {
                    let first = countdownShown < 0
                    countdownShown = stepIndex
                    if first, let info = infos[held.encoder] {
                        overlay = (Self.fit(info.name, 4) + (pflOn[held.encoder] ? " HOLD:PFLOFF" : " HOLD:PFL ON"), .infinity)
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
        if lit != blinkLit {
            blinkLit = lit
            if hub.mirror.muteMaster == false { step.midi += drawRings(hub: hub) }  // only the rings that change
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
        // A turn or a press shows the device is in Remote Mode even if the ACK was missed.
        if !connected {
            switch event {
            case .turned, .pushed, .shift: connect(hub: &hub, now: now, into: &step)
            default: return
            }
        }
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
        sentRings = Array(repeating: nil, count: Self.stripCount)
        var output = CoreOutput()
        for layer in Layer.allCases { output.append(hub.resend(id(layer), now: now)) }
        take(output, hub: hub, into: &step)
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
        if hub.mirror.muteMaster == false {
            // A mute does nothing in the audio while TotalMix FX's Mute Master is off: say so.
            show("MUTE MASTER OFF", now: now, into: &step, hub: hub)
        } else {
            show(Self.fit(info.name, 7) + " MUTE" + (muteOn[encoder] ? " ON" : " OFF"), now: now, into: &step, hub: hub)
        }
    }

    /// A push held `pflHold`: toggles the strip's PFL and says so on the screen.
    private mutating func pfl(_ encoder: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        take(hub.switchPressed(id(.pfl), strip: encoder, now: now), hub: hub, into: &step)
        guard let info = infos[encoder] else { return }
        show(Self.fit(info.name, 8) + " PFL" + (pflOn[encoder] ? " ON" : " OFF"), now: now, into: &step, hub: hub)
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

    /// The screen: the title and the sixteen labels, sent only when they change.
    private mutating func drawLabels(hub: SurfaceHub) -> [UInt8] {
        guard connected else { return [] }
        let labels: [String] = (0..<Self.stripCount).map { index in
            if shiftHeld { return ShiftButton.layout[index]?.label ?? "" }
            return Self.fit(infos[index]?.name ?? "", 4)
        }
        let bytes = E16Outgoing.labels(title: title(hub: hub), labels: labels)
        guard bytes != sentLabels else { return [] }
        sentLabels = bytes
        return bytes
    }

    /// The title: an overlay while one shows; else the function ("LEVEL", "PAN", "> PHONES 1")
    /// and, with more than one page, the page. The same with Shift held, so the choice made
    /// there shows at once and stays (Adam, 2026-11-04).
    public func title(hub: SurfaceHub) -> String {
        if let overlay { return overlay.text }
        let pageText = pageCount > 1 ? " \(page.first / Self.stripCount + 1)/\(pageCount)" : ""
        let width = E16Outgoing.titleLength - pageText.count
        return Self.fit(functionName(hub: hub), width).padding(toLength: width, withPad: " ", startingAt: 0) + pageText
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

    /// Every ring, sent only where it changed: one RING message for the rings, then one LED
    /// message for the needles, so the needles are drawn over the rings.
    private mutating func drawRings(hub: SurfaceHub) -> [UInt8] {
        var rings: [(encoder: Int, ring: E16Ring)] = []
        var leds: [(encoder: Int, led: Int, red: UInt8, green: UInt8, blue: UInt8)] = []
        for index in 0..<Self.stripCount {
            let look = look(index, hub: hub)
            guard sentRings[index] != look else { continue }
            sentRings[index] = look
            rings.append((index, look.ring))
            leds += look.leds.map { (index, $0.index, $0.red, $0.green, $0.blue) }
        }
        return E16Outgoing.rings(rings) + E16Outgoing.leds(leds)
    }

    private mutating func drawRing(_ index: Int, hub: SurfaceHub) -> [UInt8] {
        let look = look(index, hub: hub)
        guard sentRings[index] != look else { return [] }
        sentRings[index] = look
        return E16Outgoing.rings([(encoder: index, ring: look.ring)])
            + E16Outgoing.leds(look.leds.map { (index, $0.index, $0.red, $0.green, $0.blue) })
    }

    /// A strip's ring: dark for no channel; else its color (`rgb(for:)`, or for a send the
    /// output's) filled to its value, bipolar for a pan. A mute or a PFL that is on shows as a
    /// shape over the fill, not as a color, since a channel can itself be any color (Adam,
    /// 2026-11-04): a mute lights four red LEDs at the ring's quarter points (`muteMarks`), off
    /// in every other half second while Mute Master is off; a PFL lights one white LED that
    /// runs round the ring (`rotationStep` a step), the state to notice on stage.
    func look(_ index: Int, hub: SurfaceHub) -> RingLook {
        if shiftHeld { return RingLook(ring: buttonRing(index, hub: hub)) }
        guard let info = infos[index], let value = knobValues[index] else { return RingLook(ring: .off) }
        var rgb = Self.rgb(for: info)
        if case .send(let n) = function, hub.sendTargets.indices.contains(n) {
            let output = ChannelRef(.output, hub.sendTargets[n])
            if let color = hub.mirror.channels[output]?.color, color != 1, let sendRGB = Self.totalMixRGB[color] { rgb = sendRGB }
        }
        if let held, held.encoder == index, !held.didPFL, countdownShown >= 0 {
            // The countdown: a white arc from empty to full over the hold, in place of the fill;
            // from full to empty when the hold turns PFL off (Adam, 2026-11-04).
            let progress = min(Double(countdownShown) * Self.countdownStep / Self.pflHold, 1)
            let amount = pflOn[index] ? 1 - progress : progress
            return RingLook(ring: E16Ring(red: Self.pflRGB.0, green: Self.pflRGB.1, blue: Self.pflRGB.2, amount: amount))
        }
        var look = RingLook(ring: E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: value, bipolar: isPan))
        if muteOn[index], !(hub.mirror.muteMaster == false && !blinkLit) {
            look.leds += Self.muteMarks.map { RingLook.LED(index: $0, red: Self.muteRGB.0, green: Self.muteRGB.1, blue: Self.muteRGB.2) }
        }
        if pflOn[index] {
            // Every other LED of the fill turned white: a striped fill.
            let lit = Int((min(max(value, 0), 1) * 16).rounded())
            for led in stride(from: 1, to: max(lit, 2), by: 2) {
                look.leds.append(RingLook.LED(index: led, red: Self.pflRGB.0, green: Self.pflRGB.1, blue: Self.pflRGB.2))
            }
        }
        return look
    }

    /// A ring on the Shift page, full, in the button's color (`buttonColors`; Adam, 2026-11-04).
    /// A mode button is dim, or at the medium level for the mode in use; an arrow is dim when
    /// it goes somewhere and dark when it doesn't; any button is full while held down. A blank
    /// is dark.
    func buttonRing(_ index: Int, hub: SurfaceHub) -> E16Ring {
        guard let button = ShiftButton.layout[index] else { return .off }
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
        let scale: Double
        if pressedButton == index { scale = 1 }
        else if inUse { scale = Self.inUseLevel }
        else if isAvailable(button, hub: hub) { scale = Self.availableLevel }
        else { return .off }
        // A lit part never goes below `dimFloor`, so a deep color still shows when dim.
        func part(_ v: UInt8) -> UInt8 { v == 0 ? 0 : UInt8(max((Double(v) * scale).rounded(), Self.dimFloor)) }
        return E16Ring(red: part(rgb.0), green: part(rgb.1), blue: part(rgb.2), amount: 1)
    }

    /// How bright an available button is, as a fraction of full; far from the mode in use
    /// (Adam, 2026-11-04).
    public static let availableLevel = 0.03
    /// The least a lit part of a dim button goes to, 0–127.
    public static let dimFloor = 3.0
    /// How bright the mode in use is, as a fraction of full; between available and held down.
    public static let inUseLevel = 0.45

    /// The Shift page's colors (Adam, 2026-11-04): yellow for LEVEL, orange for PAN, a deep
    /// green for SEND and the output arrows, a deep blue for the page arrows. The page shows no
    /// channel colors, so they only need to differ from each other. Color is an extra cue: the
    /// buttons' positions and labels, and the brighter ring of the mode in use, carry the
    /// meaning, since yellow, orange, and green are hard to tell apart with a red-green color
    /// deficiency.
    public static let buttonColors: (level: (UInt8, UInt8, UInt8), pan: (UInt8, UInt8, UInt8),
                                     send: (UInt8, UInt8, UInt8), page: (UInt8, UInt8, UInt8))
        = ((127, 85, 0), (127, 30, 0), (0, 60, 0), (0, 0, 127))

    /// The LEDs a mute lights: the pair at the ring's bottom gap, where the eye lands looking at
    /// the device from below, and the pair at the top. No single LED sits at 9 or 3 o'clock on
    /// the device, so side marks looked off (Adam, 2026-11-04).
    public static let muteMarks = [0, 7, 8, 15]
    /// Red, for a mute's marks.
    public static let muteRGB: (UInt8, UInt8, UInt8) = (127, 0, 0)
    /// White, for a PFL's stripes and the countdown.
    public static let pflRGB: (UInt8, UInt8, UInt8) = (127, 127, 127)

    /// An RGB (0–127 per part) for each of TotalMix FX's eight colors (1 white, 2 grey, 3 orange,
    /// 4 red, 5 blue, 6 green, 7 yellow, 8 pink; docs/TOTALMIX-OSC.md, test 7), as the Launch
    /// Control driver renders them.
    public static let totalMixRGB: [Int: (UInt8, UInt8, UInt8)] = [
        1: (127, 127, 127),
        2: (40, 40, 40),
        3: (127, 40, 0),
        4: (127, 0, 0),
        5: (0, 0, 127),
        6: (0, 127, 0),
        7: (127, 85, 0),
        8: (90, 0, 127),   // purple: (16, 0, 127) was too close to blue on the device (Adam, 2026-11-04)
    ]

    /// A strip's color: its TotalMix FX color, or white.
    public static func rgb(for info: StripInfo) -> (UInt8, UInt8, UInt8) {
        info.color.flatMap { totalMixRGB[$0] } ?? totalMixRGB[1]!
    }

    /// `text` cut to `length` characters; a longer text first loses a stereo pair's second
    /// number ("PB 1/2" to "PB 1"), then its spaces ("PB 11/12" to "PB11").
    static func fit(_ text: String, _ length: Int) -> String {
        if text.count <= length { return text }
        var short = text
        if let slash = short.firstIndex(of: "/") { short = String(short[..<slash]) }
        if short.count > length { short = short.filter { $0 != " " } }
        return String(short.prefix(length))
    }
}
