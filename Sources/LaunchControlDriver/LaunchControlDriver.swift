import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(SurfaceCore)
import SurfaceCore
#endif

/// What an encoder row of the Launch Control XL 3 controls, chosen in the app.
public enum LaunchControlRowFunction: String, Codable, Sendable, CaseIterable {
    /// Each strip's pan (in the mix output, for a source).
    case pan
    /// A send: each strip's level into one of the send targets (`SurfaceHub.sendTargets`). Send
    /// rows take consecutive targets, and Page up and down step them together.
    case send
}

/// What the Launch Control driver produces in answer to MIDI or a call: MIDI bytes for the device,
/// and the core's output for TotalMix and the other surfaces.
public struct LaunchControlStep: Equatable, Sendable {
    /// Complete MIDI messages for the device's DAW port, in order.
    public var midi: [UInt8] = []
    /// Messages for TotalMix, and updates for the other surfaces. This driver's own updates are
    /// already turned into `midi`.
    public var core = CoreOutput()

    /// Nothing to send.
    public init() {}
}

/// The driver for Novation's Launch Control XL 3 and Launch Control 3 in DAW mode, on top of
/// `SurfaceHub`.
///
/// Like `RotoDriver`, it does no input or output: the app passes it the bytes from the device's
/// DAW port with `receive(_:hub:now:)`, the hub's output with `take(_:hub:now:)`, and the time with
/// `tick(hub:now:)`, and sends on what comes back.
///
/// **Layers.** The hub gives a surface one knob and one switch per strip. A Launch Control strip
/// has more (on the XL 3, a fader, three encoders, and two buttons), so the driver adds one hub
/// surface per layer of controls, all paged together:
/// - XL 3: the faders (level) with the top buttons (PFL); each encoder row (pan or a send, from
///   `rowFunctions`), the top row with the bottom buttons (mute).
/// - Launch Control 3: the bottom encoder row (level) with the buttons (mute, or PFL after
///   Function); the top encoder row (pan or a send, stepped by Page up and down).
///
/// **Controls** (decided with Adam, 2026-11-01; docs/LAUNCH-CONTROL-XL3.md, section 9, and
/// docs/LAUNCH-CONTROL-3.md, section 9), following the labels and Novation's own DAW integrations:
/// Track < and > move by eight strips, or with Shift to the first or last page; Page up and down
/// step the sends; Shift
/// with Page up shows the sources and with Page down the outputs.
///
/// **Simulation.** With `layout` `.lc3` and `device` `.xl3`, the Launch Control 3's layout runs on
/// an XL 3: its top two encoder rows, top button row, Page, Track, Shift, and Mute/Select as
/// Function, which has its number (66). The XL 3's other controls stay dark and do nothing.
public struct LaunchControlDriver: Sendable {
    /// The hub surface for each layer of controls.
    public enum Layer: String, Sendable, CaseIterable {
        /// XL 3: the faders, and the top button row.
        case faders
        /// XL 3: the top encoder row, and the bottom button row. Launch Control 3: the top encoder row.
        case row0
        /// XL 3: the middle encoder row. Launch Control 3: the bottom encoder row (level), and the buttons.
        case row1
        /// XL 3: the bottom encoder row.
        case row2
    }

    /// The layout the driver runs: the XL 3's or the Launch Control 3's.
    public let layout: LaunchControlModel
    /// The device it talks to. The same as `layout`, except when the Launch Control 3's layout runs
    /// on an XL 3.
    public let device: LaunchControlModel
    /// The start of the hub surfaces' names; each layer adds its own (e.g., "lcxl-1.faders").
    public let name: String

    /// What the XL 3's three encoder rows control, top to bottom (Pan, Send, Send by default).
    /// Ignored in the Launch Control 3's layout. Set it with `setRowFunctions(_:hub:now:)`.
    public private(set) var rowFunctions: [LaunchControlRowFunction] = Self.defaultRows

    /// The XL 3's encoder rows unless the app sets them: Send, Send, Pan, as in Novation's own DAW
    /// integrations (XL 3 user guide, "DAW Mixer mode" in each DAW's chapter), with pan just above
    /// the fader (Adam, 2026-11-01).
    public static let defaultRows: [LaunchControlRowFunction] = [.send, .send, .pan]

    /// XL 3: the first send target of the send rows. Launch Control 3: what the top row controls,
    /// −1 for pan and n ≥ 0 for send n.
    public private(set) var sendStep = 0
    /// Launch Control 3: whether the buttons are PFL (`true`) or mute.
    public private(set) var buttonsArePFL = false
    /// The view the strips show.
    public private(set) var view: ViewKind = .sources

    private var connected = false
    private var inCustomMode = false
    private var lastStart: Double?
    private var shiftHeld = false
    private var parser = LaunchControlParser()
    private var page = (first: 0, count: 0)
    private var infos: [Layer: [StripInfo?]] = [:]
    private var knobOn: [Layer: [Bool]] = [:]
    private var switchOn: [Layer: [Bool]] = [:]
    private var sentPositions: [UInt8: UInt8] = [:]  // control number → position
    private var sentColors: [UInt8: UInt8] = [:]  // control number → palette index
    private var sentTexts: [String: String] = [:]  // "target/field" → text
    private var sentConfig: [UInt8: UInt8] = [:]  // target byte → arrangement and flags

    /// How close to the level a fader's first value must be for the hub's pickup to take it, as a
    /// fraction of the range: 12 steps of 127. The device holds a fader back until it crosses the
    /// level, and then sends its first value just past it (one step past in test 3's slow moves),
    /// but the hub has no earlier position to see the crossing with; a fast move may land a few
    /// steps further (inference), and the window has to take it. If the device didn't hold the
    /// fader (test 2), a jump of up to this much gets through.
    public static let faderPickupWindow = 12.0 / 127

    /// How often entering DAW mode is asked again until the device answers, in seconds.
    public static let restartInterval: Double = 3
    /// The strips shown at once.
    public static let stripCount = 8
    /// The Launch Control 3's Function button, as the library names its number (66, the XL 3's
    /// Mute/Select; `LaunchControlModel.has(_:)`).
    public static let functionButton = LaunchControlElement.muteSelect

    /// A driver for one device. `name` starts the hub surfaces' names; `layout` is the model whose
    /// layout runs and `device` the model connected (by default the same).
    public init(name: String, layout: LaunchControlModel, device: LaunchControlModel? = nil) {
        self.name = name
        self.layout = layout
        self.device = device ?? layout
        sendStep = layout == .lc3 ? -1 : 0
    }

    /// Whether the device has answered.
    public var isConnected: Bool { connected }

    /// The layers this layout uses.
    public var layers: [Layer] { layout == .xl3 ? [.faders, .row0, .row1, .row2] : [.row1, .row0] }

    /// The hub surface for a layer.
    public func id(_ layer: Layer) -> SurfaceID { SurfaceID("\(name).\(layer.rawValue)") }

    /// What each layer has, for the hub. The XL 3's faders have no motor: the device holds a
    /// fader back until it passes the position the driver sent (feature control 70;
    /// docs/LAUNCH-CONTROL-XL3.md, test 3), and the hub's own pickup stays on behind it, in case
    /// the device's doesn't hold (test 2). Encoders take the position the driver sends (test 2),
    /// so they follow.
    public func capabilities(_ layer: Layer) -> SurfaceCapabilities {
        let hasSwitches: Bool
        switch (layout, layer) {
        case (.xl3, .faders), (.xl3, .row0), (.lc3, .row1): hasSwitches = true
        default: hasSwitches = false
        }
        if layout == .xl3 && layer == .faders {
            return SurfaceCapabilities(stripCount: Self.stripCount, feel: .pickup, hasSwitches: true,
                                       pickupWindow: Self.faderPickupWindow)
        }
        return SurfaceCapabilities(stripCount: Self.stripCount, feel: .follows, hasSwitches: hasSwitches)
    }

    // MARK: - Starting and stopping

    /// Adds the layers to the hub, and returns the bytes that start DAW mode. Until the device
    /// answers, `tick(hub:now:)` asks again every `restartInterval`.
    public mutating func start(hub: inout SurfaceHub, now: Double) -> LaunchControlStep {
        for layer in layers {
            _ = hub.addSurface(id(layer), capabilities: capabilities(layer), mode: mode(for: layer, first: page.first), now: now)
        }
        connected = false
        lastStart = now
        var step = LaunchControlStep()
        step.midi = startBytes()
        return step
    }

    /// The bytes that leave DAW mode, for when the app quits or the device is let go; and the
    /// layers leave the hub.
    public mutating func stop(hub: inout SurfaceHub) -> [UInt8] {
        for layer in layers { hub.removeSurface(id(layer)) }
        connected = false
        lastStart = nil
        return LaunchControlOutgoing.dawMode(false)
    }

    private func startBytes() -> [UInt8] {
        var bytes = LaunchControlOutgoing.dawMode(true) + LaunchControlOutgoing.touchEvents(true)
        for row in 0..<device.encoderRows {
            bytes += LaunchControlOutgoing.relativeEncoders(row: row, false) ?? []
        }
        if device == .xl3 { bytes += LaunchControlOutgoing.faderPickup(layout == .xl3) }
        return bytes
    }

    /// What is due as time passes: entering DAW mode, asked again while the device hasn't
    /// answered. (The app passes the hub's own `tick(now:)` output to `take(_:hub:now:)`.)
    public mutating func tick(hub: inout SurfaceHub, now: Double) -> LaunchControlStep {
        var step = LaunchControlStep()
        if !connected, let lastStart, now - lastStart >= Self.restartInterval {
            self.lastStart = now
            step.midi += startBytes()
        }
        return step
    }

    // MARK: - From the device

    /// Takes bytes from the device's DAW port, as they arrive.
    public mutating func receive<S: Sequence>(_ bytes: S, hub: inout SurfaceHub, now: Double) -> LaunchControlStep
    where S.Element == UInt8 {
        var step = LaunchControlStep()
        for event in parser.feed(bytes) { handle(event, hub: &hub, now: now, into: &step) }
        return step
    }

    private mutating func handle(_ event: LaunchControlEvent, hub: inout SurfaceHub, now: Double,
                                 into step: inout LaunchControlStep) {
        if case .dawMode(let on) = event {
            if on {
                if !connected { connect(hub: &hub, now: now, into: &step) }
            } else {
                // Left DAW mode (e.g., another program on the same port asked it to): ask again.
                connected = false
                inCustomMode = false
                lastStart = now
            }
            return
        }
        if case .mode(let mode) = event {
            switch mode {
            case .custom:
                inCustomMode = true
            case .dawMixer, .dawControl:
                if inCustomMode || !connected {
                    inCustomMode = false
                    connect(hub: &hub, now: now, into: &step)
                }
            }
            return
        }
        // Anything else from the device also shows that it is there: the Launch Control 3's echo
        // of the DAW mode note is an inference (docs/LAUNCH-CONTROL-3.md).
        if !connected { connect(hub: &hub, now: now, into: &step) }
        guard !inCustomMode else { return }

        switch event {
        case .moved(let element, let value):
            // The device is where the hand left it: a later position equal to this one must still
            // be sent, so the driver's record of what it sent follows the device.
            sentPositions[element.controlNumber] = value
            guard let (layer, strip) = control(for: element) else { return }
            let position = usesFaderScale(layer) ? Self.faderPosition(value) : Self.position(value)
            take(hub.controlMoved(id(layer), strip: strip, to: position, now: now), hub: hub, into: &step)
        case .touch(let element, let touched):
            guard let (layer, strip) = control(for: element) else { return }
            take(hub.touched(id(layer), strip: strip, touched, now: now), hub: hub, into: &step)
        case .button(.shift, let pressed):
            shiftHeld = pressed
        case .button(let element, pressed: true):
            pressed(element, hub: &hub, now: now, into: &step)
        default:
            break
        }
    }

    private mutating func pressed(_ element: LaunchControlElement, hub: inout SurfaceHub, now: Double,
                                  into step: inout LaunchControlStep) {
        switch element {
        case .button:
            guard let (layer, strip) = switchControl(for: element) else { return }
            take(hub.switchPressed(id(layer), strip: strip, now: now), hub: hub, into: &step)
        case .pageUp, .pageDown:
            if shiftHeld {
                let next: ViewKind = element == .pageUp ? .sources : .outputs
                guard next != view else { return }
                view = next
                setModes(first: 0, hub: &hub, now: now, into: &step)
            } else {
                stepSends(by: element == .pageUp ? -1 : 1, hub: &hub, now: now, into: &step)
            }
        case .trackLeft, .trackRight:
            // Eight strips a press; with Shift, the first or the last page. Pages always start at
            // a multiple of eight, as on the Roto-Control: the order is set in the app, so there is
            // nothing to gain from moving one strip (Adam, 2026-11-01).
            let direction = element == .trackLeft ? -1 : 1
            let primary = id(layers[0])
            var output: CoreOutput
            if shiftHeld {
                // Past the end, the hub goes to the start of the last page.
                output = hub.setMode(primary, mode(for: layers[0], first: direction < 0 ? 0 : Int(Int32.max)), now: now)
            } else {
                output = hub.page(primary, by: direction, now: now)
            }
            if case .strips(_, let first, _, _)? = hub.mode(of: primary) {
                for layer in layers.dropFirst() {
                    output.append(hub.setMode(id(layer), mode(for: layer, first: first), now: now))
                }
            }
            take(output, hub: hub, into: &step)
        case Self.functionButton where layout == .lc3:
            buttonsArePFL.toggle()
            setModes(first: page.first, hub: &hub, now: now, into: &step)
            step.midi += overlay("Buttons", buttonsArePFL ? "PFL" : "Mute")
        default:
            break
        }
    }

    /// The range `sendStep` may take: XL 3, so that every send row has a target; Launch Control 3,
    /// from pan (−1) to the last send.
    private func sendStepRange(_ hub: SurfaceHub) -> ClosedRange<Int> {
        let targets = hub.sendTargets.count
        if layout == .lc3 { return -1...max(targets - 1, -1) }
        let sendRows = rowFunctions.filter { $0 == .send }.count
        return 0...max(targets - sendRows, 0)
    }

    private mutating func stepSends(by delta: Int, hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        if layout == .xl3 && !rowFunctions.contains(.send) { return }
        let range = sendStepRange(hub)
        let next = min(max(sendStep + delta, range.lowerBound), range.upperBound)
        guard next != sendStep else { return }
        sendStep = next
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        if layout == .lc3 {
            step.midi += overlay("Top row", sendStep < 0 ? "Pan" : Self.sendLabel(sendName(sendStep, hub: hub)))
        } else {
            step.midi += overlay("Sends", Self.sendLabel(sendName(sendStep, hub: hub)))
        }
    }

    private func sendName(_ index: Int, hub: SurfaceHub) -> String {
        let targets = hub.sendTargets
        guard targets.indices.contains(index) else { return "none" }
        let ref = ChannelRef(.output, targets[index])
        return hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? ref.description
    }

    private mutating func connect(hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        connected = true
        lastStart = nil
        sentPositions = [:]
        sentColors = [:]
        sentTexts = [:]
        sentConfig = [:]
        step.midi += LaunchControlOutgoing.selectMode(.dawMixer) ?? []
        // The XL 3's controls the simulated layout doesn't use stay dark.
        for element in device.elements where element.hasLight && control(for: element) == nil && switchControl(for: element) == nil {
            step.midi += color(element, 0)
        }
        for element in device.elements where element.isContinuous && control(for: element) == nil {
            step.midi += configure(.control(element), .titleNameAndValue, quiet: true)
        }
        var output = CoreOutput()
        for layer in layers { output.append(hub.resend(id(layer), now: now)) }
        take(output, hub: hub, into: &step)
        // Brings the stationary display up with what was just drawn on it (test 5 brought it up
        // this way; whether it comes up by itself is untested).
        step.midi += LaunchControlOutgoing.showDisplay(.stationary, true, model: device) ?? []
    }

    // MARK: - Modes

    /// The hub mode for a layer, from the driver's settings.
    func mode(for layer: Layer, first: Int) -> SurfaceMode {
        let knob: KnobFunction
        var switchFunction = SwitchFunction.none
        switch (layout, layer) {
        case (.xl3, .faders):
            knob = .level
            switchFunction = .pfl
        case (.xl3, .row0), (.xl3, .row1), (.xl3, .row2):
            let row = layer == .row0 ? 0 : layer == .row1 ? 1 : 2
            knob = rowKnob(row)
            if layer == .row0 { switchFunction = .mute }
        case (.lc3, .row1):
            knob = .level
            switchFunction = buttonsArePFL ? .pfl : .mute
        case (.lc3, _):
            knob = sendStep < 0 ? .pan : .send(sendStep)
        }
        return .strips(view: view, first: first, knob: knob, switch: switchFunction)
    }

    /// XL 3: the knob function of encoder row `row`: pan, or the next send after the send rows
    /// above it.
    private func rowKnob(_ row: Int) -> KnobFunction {
        guard rowFunctions.indices.contains(row), rowFunctions[row] == .send else { return .pan }
        let before = rowFunctions.prefix(row).filter { $0 == .send }.count
        return .send(sendStep + before)
    }

    /// Sets what the XL 3's encoder rows control, top to bottom (three values; missing rows are pan).
    public mutating func setRowFunctions(_ functions: [LaunchControlRowFunction], hub: inout SurfaceHub,
                                         now: Double) -> LaunchControlStep {
        rowFunctions = (0..<3).map { functions.indices.contains($0) ? functions[$0] : .pan }
        let range = sendStepRange(hub)
        sendStep = min(max(sendStep, range.lowerBound), range.upperBound)
        var step = LaunchControlStep()
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        return step
    }

    private mutating func setModes(first: Int, hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        var output = CoreOutput()
        for layer in layers { output.append(hub.setMode(id(layer), mode(for: layer, first: first), now: now)) }
        take(output, hub: hub, into: &step)
    }

    // MARK: - Controls

    /// The layer and strip of a fader or encoder, in this layout on this device; `nil` for a control
    /// the layout doesn't use.
    func control(for element: LaunchControlElement) -> (Layer, Int)? {
        guard device.has(element) else { return nil }
        switch (layout, element) {
        case (.xl3, .fader(let index)): return (.faders, index)
        case (.xl3, .encoder(let row, let column)): return (row == 0 ? .row0 : row == 1 ? .row1 : .row2, column)
        case (.lc3, .encoder(let row, let column)) where row < 2: return (row == 0 ? .row0 : .row1, column)
        default: return nil
        }
    }

    /// The layer and strip of a strip button; `nil` for any other control.
    func switchControl(for element: LaunchControlElement) -> (Layer, Int)? {
        guard device.has(element), case .button(let row, let column) = element else { return nil }
        switch (layout, row) {
        case (.xl3, 0): return (.faders, column)
        case (.xl3, 1): return (.row0, column)
        case (.lc3, 0): return (.row1, column)
        default: return nil
        }
    }

    /// The fader or encoder of a layer's strip.
    func element(_ layer: Layer, _ strip: Int) -> LaunchControlElement {
        switch (layout, layer) {
        case (.xl3, .faders): return .fader(strip)
        case (.xl3, .row0), (.lc3, .row0): return .encoder(row: 0, column: strip)
        case (.xl3, .row1), (.lc3, .row1): return .encoder(row: 1, column: strip)
        case (_, .row2): return .encoder(row: 2, column: strip)
        case (.lc3, .faders): return .encoder(row: 1, column: strip)
        }
    }

    /// The button of a layer's strip, if the layer has buttons.
    func button(_ layer: Layer, _ strip: Int) -> LaunchControlElement? {
        switch (layout, layer) {
        case (.xl3, .faders), (.lc3, .row1): return .button(row: 0, column: strip)
        case (.xl3, .row0): return .button(row: 1, column: strip)
        default: return nil
        }
    }

    /// Whether a layer's controls are the XL 3's faders, which use the printed scale
    /// (`faderTicks`).
    private func usesFaderScale(_ layer: Layer) -> Bool { layout == .xl3 && device == .xl3 && layer == .faders }

    /// The XL 3's fader scale (Adam, 2026-11-01): the gain at each of the nine ticks printed beside
    /// each fader, top to bottom, with the fader value measured at each tick
    /// (docs/LAUNCH-CONTROL-XL3.md, test 7). The labels are TotalMix FX's own fader marks: +6 (the
    /// top), +3, 0, −6, −10, −20, −40, −60 (docs/TOTALMIX-OSC.md, test 18); the bottom tick, value 0,
    /// is off. Between ticks the gain moves evenly in dB; below −60 it follows TotalMix's fader
    /// position down to off.
    public static let faderTicks: [(value: Double, gainDB: Double)] = [
        (127, 6), (120, 3), (102, 0), (84, -6), (66, -10), (46, -20), (29, -40), (11, -60),
    ]

    /// TotalMix's fader position (0…1) for an XL 3 fader value, on the printed scale.
    public static func faderPosition(_ value: UInt8) -> Double {
        let value = Double(min(value, 127))
        guard let lowest = faderTicks.last else { return value / 127 }
        if value <= lowest.value {
            return value / lowest.value * FaderCurve.position(gainDB: lowest.gainDB)
        }
        for (upper, lower) in zip(faderTicks, faderTicks.dropFirst()) where value >= lower.value {
            let fraction = (value - lower.value) / (upper.value - lower.value)
            return FaderCurve.position(gainDB: lower.gainDB + fraction * (upper.gainDB - lower.gainDB))
        }
        return 1
    }

    /// The XL 3 fader value for TotalMix's fader position (0…1): the inverse of
    /// `faderPosition(_:)`, rounded.
    public static func faderValue(_ position: Double) -> UInt8 {
        let position = min(max(position.isFinite ? position : 0, 0), 1)
        guard let lowest = faderTicks.last else { return UInt8((position * 127).rounded()) }
        let lowestPosition = FaderCurve.position(gainDB: lowest.gainDB)
        if position <= lowestPosition {
            return UInt8((position / lowestPosition * lowest.value).rounded())
        }
        guard let gain = FaderCurve.gainDB(position: position) else { return 0 }
        for (upper, lower) in zip(faderTicks, faderTicks.dropFirst()) where gain >= lower.gainDB {
            let fraction = min((gain - lower.gainDB) / (upper.gainDB - lower.gainDB), 1)
            return UInt8(min(max((lower.value + fraction * (upper.value - lower.value)).rounded(), 0), 127))
        }
        return 127
    }

    /// A position (0…1) for a 7-bit value, with 64 as the exact middle, so that a pan can be
    /// centered: 0–64 map to 0–0.5 and 64–127 to 0.5–1.
    public static func position(_ value: UInt8) -> Double {
        let value = Double(min(value, 127))
        return value <= 64 ? value / 128 : 0.5 + (value - 64) / 126
    }

    /// The 7-bit value for a position (0…1): the inverse of `position(_:)`, rounded.
    public static func value(_ position: Double) -> UInt8 {
        let position = min(max(position.isFinite ? position : 0, 0), 1)
        let value = position <= 0.5 ? position * 128 : 64 + (position - 0.5) * 126
        return UInt8(min(max(value.rounded(), 0), 127))
    }

    // MARK: - To the device

    /// Moves this driver's updates out of a core output (e.g., the hub's answer to TotalMix) and
    /// into MIDI. If the send targets have changed so that the send step is out of range, the step
    /// moves back into it.
    public mutating func take(_ output: CoreOutput, hub: inout SurfaceHub, now: Double) -> LaunchControlStep {
        var step = LaunchControlStep()
        take(output, hub: hub, into: &step)
        let range = sendStepRange(hub)
        if !range.contains(sendStep) {
            sendStep = min(max(sendStep, range.lowerBound), range.upperBound)
            setModes(first: page.first, hub: &hub, now: now, into: &step)
        }
        if connected && !inCustomMode { step.midi += drawNavigation(hub: hub) }
        return step
    }

    private mutating func take(_ output: CoreOutput, hub: SurfaceHub, into step: inout LaunchControlStep) {
        var output = output
        var own: [(Layer, [SurfaceUpdate])] = []
        for layer in layers {
            if let updates = output.updates.removeValue(forKey: id(layer)) { own.append((layer, updates)) }
        }
        step.core.append(output)
        guard connected, !inCustomMode, !own.isEmpty else { return }
        step.midi += render(own, hub: hub)
    }

    private mutating func render(_ updates: [(Layer, [SurfaceUpdate])], hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        var pageChanged = false
        for (layer, list) in updates {
            var layerInfos = infos[layer] ?? Array(repeating: nil, count: Self.stripCount)
            var layerKnobs = knobOn[layer] ?? Array(repeating: false, count: Self.stripCount)
            var layerSwitches = switchOn[layer] ?? Array(repeating: false, count: Self.stripCount)
            var touched = Set<Int>()
            var values: [Int: String] = [:]  // sent after the strips, once their displays are set up
            for update in list {
                switch update {
                case .page(let first, let count):
                    if layer == layers[0] {
                        page = (first, count)
                        pageChanged = true
                    }
                case .strip(let index, let info):
                    guard layerInfos.indices.contains(index) else { continue }
                    layerInfos[index] = info
                    touched.insert(index)
                    if layer == layers[0] { pageChanged = true }
                case .knob(let index, let value):
                    guard layerKnobs.indices.contains(index) else { continue }
                    layerKnobs[index] = value != nil
                    touched.insert(index)
                    if let value {
                        let control = self.element(layer, index)
                        let position = usesFaderScale(layer) ? Self.faderValue(value) : Self.value(value)
                        if sentPositions[control.controlNumber] != position {
                            sentPositions[control.controlNumber] = position
                            bytes += LaunchControlOutgoing.position(control, position) ?? []
                        }
                        values[index] = valueText(layer, value)
                    }
                case .valueText(let index, let text):
                    guard (0..<Self.stripCount).contains(index) else { continue }
                    values[index] = text
                case .switchState(let index, let on):
                    guard layerSwitches.indices.contains(index) else { continue }
                    layerSwitches[index] = on
                    touched.insert(index)
                case .meter:
                    break
                }
            }
            infos[layer] = layerInfos
            knobOn[layer] = layerKnobs
            switchOn[layer] = layerSwitches
            for index in touched.sorted() { bytes += drawStrip(layer, index, hub: hub) }
            for (index, value) in values.sorted(by: { $0.key < $1.key }) {
                bytes += text(.control(element(layer, index)), 2, value)
            }
        }
        if pageChanged { bytes += drawStationary() }
        // Every time: Page's ends change with the send targets, not only with the page (the
        // lights are sent only when they change).
        return bytes + drawNavigation(hub: hub)
    }

    /// A strip's display, encoder or fader light, and button light, for one layer.
    private mutating func drawStrip(_ layer: Layer, _ index: Int, hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        let element = self.element(layer, index)
        let info = infos[layer]?[index] ?? nil
        let active = info != nil && (knobOn[layer]?[index] ?? false)
        let target = LaunchControlDisplayTarget.control(element)
        if let info, active {
            bytes += configure(target, .titleNameAndValue, quiet: false)
            bytes += text(target, 0, info.name)
            bytes += text(target, 1, functionLabel(layer, info))
        } else {
            bytes += configure(target, .titleNameAndValue, quiet: true)
        }
        if element.hasLight {
            bytes += color(element, active ? (sendColor(layer, hub: hub) ?? Self.color(for: info)) : 0)
        }
        if let button = button(layer, index) {
            let on = switchOn[layer]?[index] ?? false
            let isPFL: Bool
            if case .strips(_, _, _, .pfl)? = hub.mode(of: id(layer)) { isPFL = true } else { isPFL = false }
            let colorIndex: UInt8 = info == nil ? 0 : isPFL ? (on ? Self.pflOn : Self.pflOff) : (on ? Self.muteOn : Self.muteOff)
            bytes += color(button, colorIndex)
        }
        return bytes
    }

    /// For a layer of sends, the palette color of the output it sends to, so that each send row
    /// reads as one send, as in Novation's integrations (Adam, 2026-11-01): the output's TotalMix
    /// color, or, if left white, green for a control room output and blue for another; `nil` for
    /// any other layer.
    private func sendColor(_ layer: Layer, hub: SurfaceHub) -> UInt8? {
        guard case .strips(_, _, .send(let index), _) = mode(for: layer, first: 0) else { return nil }
        let targets = hub.sendTargets
        guard targets.indices.contains(index) else { return nil }
        let ref = ChannelRef(.output, targets[index])
        let state = hub.mirror.channels[ref]
        let kind: StripKind = hub.mirror.monitoringOutputs.contains(ref.channel) ? .monitoring : .send
        return Self.color(for: StripInfo(channel: ref, name: "", color: state?.color, stereo: state?.stereo ?? false,
                                         kind: kind, knobLabel: "", switchLabel: ""))
    }

    /// What a layer's controls do, as its displays' second line: "Level", "Pan", or "> " and the
    /// send target's name.
    private func functionLabel(_ layer: Layer, _ info: StripInfo) -> String {
        guard case .strips(_, _, let knob, _) = mode(for: layer, first: 0) else { return "" }
        switch knob {
        case .level: return "Level"
        case .pan: return "Pan"
        case .send: return Self.sendLabel(info.knobLabel)
        }
    }

    private func valueText(_ layer: Layer, _ value: Double) -> String {
        if case .strips(_, _, .pan, _) = mode(for: layer, first: 0) { return ValueText.pan(value * 2 - 1) }
        return ValueText.level(position: value)
    }

    /// The stationary display: the view and the strips on the page as its title, and the strips'
    /// names, cut to `stationaryNameLength`, in the two rows of four (docs/LAUNCH-CONTROL-XL3.md,
    /// test 5).
    private mutating func drawStationary() -> [UInt8] {
        var bytes = configure(.stationary, .titleAndEightNames, quiet: false)
        let shown = (infos[layers[0]] ?? []).filter { $0 != nil }.count
        let viewName = view == .sources ? "Sources" : "Outputs"
        let title = shown == 0 ? viewName : "\(viewName) \(page.first + 1)-\(page.first + shown)"
        bytes += text(.stationary, 0, title)
        let names = infos[layers[0]] ?? []
        for index in 0..<Self.stripCount {
            let name = names.indices.contains(index) ? names[index]?.name ?? "" : ""
            bytes += text(.stationary, index + 1, Self.shortName(name))
        }
        return bytes
    }

    /// Page and Track lights: lit where they would move, dark at the ends. The Function button (the
    /// Launch Control 3's layout) is yellow while the buttons are PFL and dim otherwise.
    private mutating func drawNavigation(hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += color(.trackLeft, page.first > 0 ? Self.navigationOn : 0)
        bytes += color(.trackRight, page.first + Self.stripCount < page.count ? Self.navigationOn : 0)
        let range = sendStepRange(hub)
        let steps = layout == .lc3 || rowFunctions.contains(.send)
        bytes += color(.pageUp, steps && sendStep > range.lowerBound ? Self.navigationOn : 0)
        bytes += color(.pageDown, steps && sendStep < range.upperBound ? Self.navigationOn : 0)
        if layout == .lc3 { bytes += color(Self.functionButton, buttonsArePFL ? Self.pflOn : Self.functionIdle) }
        return bytes
    }

    /// Shows two lines on the overlay (a temporary display not tied to a control), e.g., after
    /// Function or Page. That the overlay comes up with SysEx 04h 7Fh, as other displays do, is
    /// an inference (not yet tried on the device).
    private mutating func overlay(_ first: String, _ second: String) -> [UInt8] {
        guard connected else { return [] }
        var bytes = configure(.overlay, .nameAndValue, quiet: false)
        bytes += text(.overlay, 0, first, force: true)
        bytes += text(.overlay, 1, second, force: true)
        bytes += LaunchControlOutgoing.showDisplay(.overlay, true, model: device) ?? []
        return bytes
    }

    private mutating func configure(_ target: LaunchControlDisplayTarget, _ arrangement: LaunchControlArrangement,
                                    quiet: Bool) -> [UInt8] {
        guard let byte = target.byte else { return [] }
        let config = arrangement.rawValue | (quiet ? 0 : 0x60)
        guard sentConfig[byte] != config else { return [] }
        sentConfig[byte] = config
        return LaunchControlOutgoing.configureDisplay(target, arrangement, onChange: !quiet, onTouch: !quiet, model: device) ?? []
    }

    private mutating func text(_ target: LaunchControlDisplayTarget, _ field: Int, _ text: String,
                               force: Bool = false) -> [UInt8] {
        guard let byte = target.byte else { return [] }
        let text = String(text.prefix(Self.fieldLength))
        let key = "\(byte)/\(field)"
        guard force || sentTexts[key] != text else { return [] }
        sentTexts[key] = text
        return LaunchControlOutgoing.text(target, field: field, text, model: device) ?? []
    }

    private mutating func color(_ element: LaunchControlElement, _ index: UInt8) -> [UInt8] {
        guard element.hasLight, sentColors[element.controlNumber] != index else { return [] }
        sentColors[element.controlNumber] = index
        return LaunchControlOutgoing.color(element, index) ?? []
    }

    // MARK: - Text and colors

    /// The most characters a display field keeps: 20 (inference from the XL 3, test 5).
    public static let fieldLength = 20
    /// The characters of a name kept on the stationary display, whose columns hold about four
    /// capitals and run together when full ("Mic 1Mic 2"; docs/LAUNCH-CONTROL-XL3.md, test 5).
    public static let stationaryNameLength = 4

    /// A name cut to `stationaryNameLength` for the stationary display. A longer name loses its
    /// spaces first, and then letters from before its number, so that numbered channels stay
    /// apart: "Mic 1" → "Mic1", "Phones 2" → "Pho2", "PB 1/2" → "P1/2", "Tracks" → "Trac".
    public static func shortName(_ name: String) -> String {
        let limit = stationaryNameLength
        guard name.count > limit else { return name }
        let packed = name.filter { $0 != " " }
        guard packed.count > limit else { return packed }
        let number = String(packed.reversed().prefix { $0.isNumber || $0 == "/" }.reversed())
        guard !number.isEmpty, number.count < limit else { return String(packed.prefix(limit)) }
        return String(packed.prefix(limit - number.count)) + number
    }

    /// The label for a send: "> " and the output's name (AGENTS.md, house style).
    public static func sendLabel(_ name: String) -> String { "> " + name }

    /// Palette colors for the buttons and the navigation lights. The palette's first 40 colors
    /// have been seen to run as the guide's picture does (docs/LAUNCH-CONTROL-XL3.md, test 4):
    /// 5 red and 7 a darker red, 13 yellow and 15 a darker yellow, 3 white and 1 a dim grey. That
    /// the darker ones read as "off" next to the bright ones is an inference, for Adam to judge.
    public static let muteOn: UInt8 = 5
    /// A mute button that is off: dark red.
    public static let muteOff: UInt8 = 7
    /// A PFL button that is on: yellow.
    public static let pflOn: UInt8 = 13
    /// A PFL button that is off: dark yellow.
    public static let pflOff: UInt8 = 15
    /// Page and Track where they would move: white.
    public static let navigationOn: UInt8 = 3
    /// The Function button while the buttons are mute: dim grey.
    public static let functionIdle: UInt8 = 1

    /// The palette color for each of TotalMix's eight colors (1 white, 2 grey, 3 orange, 4 red,
    /// 5 blue, 6 green, 7 yellow, 8 pink; docs/TOTALMIX-OSC.md, test 7). White, grey, orange, red,
    /// yellow, and green are from the part of the palette seen on the device (test 4); blue (45)
    /// and purple for pink (49) are past it, chosen from the guide's picture (inference).
    public static let paletteForTotalMixColor: [Int: UInt8] = [
        1: 3,   // white
        2: 1,   // grey
        3: 9,   // orange
        4: 5,   // red
        5: 45,  // blue
        6: 21,  // green
        7: 13,  // yellow
        8: 49,  // pink, as purple (TotalMix draws it purple)
    ]

    /// The palette color for a strip: its TotalMix color; an output left white (TotalMix's
    /// default) by its kind instead, monitoring outputs green and sends blue, as on the
    /// Roto-Control.
    public static func color(for info: StripInfo?) -> UInt8 {
        guard let info else { return 0 }
        let white = info.color == nil || info.color == 1
        switch info.kind {
        case .monitoring where white: return paletteForTotalMixColor[6] ?? 21
        case .send where white: return paletteForTotalMixColor[5] ?? 45
        default: return info.color.flatMap { paletteForTotalMixColor[$0] } ?? paletteForTotalMixColor[1] ?? 3
        }
    }
}
