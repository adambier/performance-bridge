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

/// What the Launch Control driver produces in answer to MIDI or a call: MIDI bytes for the device,
/// and the core's output for TotalMix FX and the other surfaces.
public struct LaunchControlStep: Equatable, Sendable {
    /// Complete MIDI messages for the device's DAW port, in order.
    public var midi: [UInt8] = []
    /// Messages for TotalMix FX, and updates for the other surfaces. This driver's own updates are
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
/// - XL 3: the faders (level) with the top buttons (PFL); the top encoder row (a send) with the
///   bottom buttons (mute); the middle encoder row (another send); the bottom encoder row (pan).
/// - Launch Control 3: the bottom encoder row (level) with the buttons (mute, or PFL while
///   Function is held); the top encoder row (pan or a send, stepped by Page up and down).
///
/// **Controls** (decided with Adam, 2026-11-01; docs/LAUNCH-CONTROL-XL3.md, section 9, and
/// docs/LAUNCH-CONTROL-3.md, section 9), following the labels and Novation's own DAW integrations:
/// Track < and > move by eight strips, or with Shift to the first or last page; Page up and down
/// choose the top send row's output, and on the XL 3 Shift + Page the middle row's, each skipping
/// the other row's. The strips always show the channels (inputs and playbacks), never the outputs.
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

    /// The send rows' chosen outputs (`LaunchControlSendRows`), as the user last chose them with
    /// Page (top row) and Shift + Page (middle row) or in the app.
    public private(set) var sendRows: LaunchControlSendRows
    /// The output each send row was chosen to send to (`LaunchControlSendRows.choices`). The app
    /// can save these and pass them back to `init`.
    public var sendOutputs: [Int?] { sendRows.choices }
    /// Launch Control 3: whether the buttons are PFL (`true`, while Function is held) or mute.
    public private(set) var buttonsArePFL = false
    /// Whether level and send encoders dim with their level (`brightness(position:)`), a
    /// setting that is off by default (Adam, 2026-11-02, from the Tier 3 review of that date).
    /// Pan encoders keep full brightness.
    public private(set) var levelBrightness: Bool
    /// The send target (an index into `SurfaceHub.sendTargets`) each send row uses now, from
    /// `sendOutputs` (`resolveSends(_:)`); `nil` for none, or pan on the Launch Control 3.
    private var sendIndices: [Int?] = []

    private var connected = false
    private var inCustomMode = false
    private var lastStart: Double?
    /// When the device last sent anything, and when the driver last asked it for its surface mode,
    /// for the presence check (`presenceInterval`).
    private var lastHeard: Double?
    /// Whether flashing buttons are in their bright half now (`blinkPeriod`).
    private var blinkLit = true
    private var lastQuery: Double?
    private var awaitingModeReply = false

    /// How long the device may stay silent before the driver asks for its surface mode (feature
    /// control 30, which the XL 3 has answered: docs/LAUNCH-CONTROL-XL3.md, test 6), in seconds.
    /// With no answer to two questions, or an answer of a Custom Mode the device never announced,
    /// the driver takes it that the device restarted and lost DAW mode, and enters DAW mode
    /// again, which draws everything (Adam, 2026-11-02, from the review of that date). That a
    /// device restarted without its port going away answers this way is an inference, not yet
    /// seen; the check is skipped in a Custom Mode. It also relies on the device answering
    /// feature control 30, which the Launch Control 3 has not been seen to do (inference from its
    /// guide).
    public static let presenceInterval: Double = 5
    private var shiftHeld = false
    private var trackLeftHeld = false
    private var trackRightHeld = false
    /// When Shift went down, and whether Page or Track has been pressed since, for the reset's
    /// guard (`resetAllowed`).
    private var shiftDownAt: Double?
    private var shiftUsedForNavigation = false
    /// The encoders reset during this hold of Shift: each resets once per hold, since one turn can
    /// send several touch reports.
    private var resetThisShift: Set<UInt8> = []
    /// A send's position before Shift + turn took it to −oo, so the next Shift + turn restores it.
    private var sendsBeforeReset: [ControlTarget: Double] = [:]

    /// How long Shift must be held, with no Page or Track press, before Shift + turn resets: so a
    /// hand reaching for Shift + Page or Shift + Track that brushes an encoder changes nothing
    /// (Adam, 2026-11-02, from the review of that date).
    public static let resetHold: Double = 0.3
    private var parser = LaunchControlParser()
    private var page = (first: 0, count: 0)
    private var infos: [Layer: [StripInfo?]] = [:]
    private var knobOn: [Layer: [Bool]] = [:]
    private var knobValues: [Layer: [Double?]] = [:]  // the last position the hub sent, 0…1
    private var switchOn: [Layer: [Bool]] = [:]
    private var sentPositions: [UInt8: UInt8] = [:]  // control number → position
    private var sentColors: [UInt8: LightColor] = [:]  // control number → color sent
    private var sentTexts: [String: String] = [:]  // "target/field" → text
    private var sentConfig: [UInt8: UInt8] = [:]  // target byte → arrangement and flags

    /// How close to the level a fader's first value must be for the hub's pickup to take it, as a
    /// fraction of TotalMix FX's fader travel (0…1): 12/127 of it, which on the printed scale is 7 to
    /// 18 of the fader's values depending on where the fader is (review of 2026-11-02). The device holds a fader back until it crosses the
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
    public init(name: String, layout: LaunchControlModel, device: LaunchControlModel? = nil, sendOutputs: [Int?] = [],
                levelBrightness: Bool = false) {
        self.name = name
        self.layout = layout
        self.device = device ?? layout
        self.sendRows = LaunchControlSendRows(layout: layout, choices: sendOutputs)
        self.levelBrightness = levelBrightness
    }

    /// Turns `levelBrightness` on or off, and returns the lights that change (none while the
    /// device isn't in DAW mode; they are drawn when it is).
    public mutating func setLevelBrightness(_ on: Bool, hub: SurfaceHub) -> [UInt8] {
        levelBrightness = on
        guard connected, !inCustomMode else { return [] }
        var bytes: [UInt8] = []
        for layer in layers {
            for index in 0..<Self.stripCount {
                let element = self.element(layer, index)
                if element.hasLight { bytes += color(element, lightColor(layer, index, hub: hub)) }
            }
        }
        return bytes
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
        resolveSends(hub)
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

    /// Leaves DAW mode and enters it again, so the device answers with its echo even when a host
    /// that quit without leaving (e.g., stopped with Control-C) left it in DAW mode: started after
    /// such a host, the app was seen stuck on "Connecting", and connected at once after a host that
    /// left properly (Adam, 2026-11-01). The device echoes only a change (docs/LAUNCH-CONTROL-XL3.md, test 14).
    private func startBytes() -> [UInt8] {
        var bytes = LaunchControlOutgoing.dawMode(false) + LaunchControlOutgoing.dawMode(true)
            + LaunchControlOutgoing.touchEvents(true)
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
        // Mutes selected while Mute Master is off flash; the lights are sent only when they change.
        let lit = Int((now / Self.blinkPeriod).rounded(.down)) % 2 == 0
        if connected, !inCustomMode, lit != blinkLit, hub.mirror.muteMaster == false {
            blinkLit = lit
            step.midi += drawButtons(hub: hub)
        }
        // Not in a Custom Mode the user chose: whether the device answers the question there is
        // untested, and restarting would take it out of that mode (review of 2026-11-02).
        if connected, !inCustomMode, let heard = lastHeard, now - heard >= Self.presenceInterval {
            if now - heard >= 2 * Self.presenceInterval + 1 {
                restart(now: now, into: &step)   // two questions unanswered
            } else if now - (lastQuery ?? -Double.infinity) >= Self.presenceInterval {
                lastQuery = now
                awaitingModeReply = true
                step.midi += LaunchControlOutgoing.queryFeature(0x1E)
            }
        }
        return step
    }

    /// Takes the device as no longer in DAW mode, and asks for it again; the echo draws everything.
    private mutating func restart(now: Double, into step: inout LaunchControlStep) {
        connected = false
        inCustomMode = false
        awaitingModeReply = false
        lastStart = now
        step.midi += startBytes()
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
        lastHeard = now
        // Anything else heard settles the question: the device is there (review of 2026-11-02).
        if case .mode = event {} else { awaitingModeReply = false }
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
            let answer = awaitingModeReply
            awaitingModeReply = false
            switch mode {
            case .custom where answer && connected && !inCustomMode:
                // A Custom Mode chosen on the device is announced when chosen (test 1); one that
                // shows up only in an answer means the device restarted (inference).
                restart(now: now, into: &step)
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
        // A control moved or pressed also shows that the device is there in DAW mode (the Launch
        // Control 3's echo of the DAW mode note is an inference, docs/LAUNCH-CONTROL-3.md). Feature
        // replies don't: leaving DAW mode, the device sends CC 30 and 31 before its 9F 0C 00, and
        // taking those as presence drew everything on a device on its way out (review of
        // 2026-11-02; docs/LAUNCH-CONTROL-XL3.md, test 12).
        switch event {
        case .moved, .turned, .touch, .button:
            if !connected { connect(hub: &hub, now: now, into: &step) }
        default:
            return
        }
        // Shift and Track are tracked even in a Custom Mode, so a button released there isn't
        // still taken as held back in DAW mode (review of 2026-11-02).
        if inCustomMode {
            switch event {
            case .button(.shift, let pressed):
                shiftHeld = pressed
                shiftDownAt = pressed ? now : nil
            case .button(.trackLeft, let pressed): trackLeftHeld = pressed
            case .button(.trackRight, let pressed): trackRightHeld = pressed
            default: break
            }
            return
        }

        switch event {
        case .moved(let element, let value):
            // The device is where the hand left it: a later position equal to this one must still
            // be sent, so the driver's record of what it sent follows the device.
            sentPositions[element.controlNumber] = value
            guard let (layer, strip) = control(for: element) else { return }
            let position = devicePosition(layer, value)
            take(hub.controlMoved(id(layer), strip: strip, to: position, now: now), hub: hub, into: &step)
            step.midi += drawOwnMove(layer, strip, hub: hub)
        case .touch(let element, let touched):
            guard let (layer, strip) = control(for: element) else { return }
            if touched, shiftHeld, case .encoder = element, resetAllowed(now: now),
               resetThisShift.insert(element.controlNumber).inserted {
                reset(element, layer: layer, strip: strip, hub: &hub, now: now, into: &step)
            }
            take(hub.touched(id(layer), strip: strip, touched, now: now), hub: hub, into: &step)
        case .button(.shift, let pressed):
            shiftHeld = pressed
            shiftDownAt = pressed ? now : nil
            shiftUsedForNavigation = false
            resetThisShift = []
            // Page and Track light for what they do with Shift held, and back on release.
            step.midi += drawNavigation(hub: hub)
        case .button(Self.functionButton, let pressed) where layout == .lc3:
            // PFL only while Function is held, so the buttons can't be left on PFL by mistake on
            // stage (Adam, 2026-11-02, from the review of that date; it was a toggle). Buttons send
            // 0 on release (XL 3, test 1).
            guard pressed != buttonsArePFL else { return }
            buttonsArePFL = pressed
            setModes(first: page.first, hub: &hub, now: now, into: &step)
            step.midi += overlay("Buttons", buttonsArePFL ? "PFL" : "Mute")
        case .button(let element, let isPressed) where element == .trackLeft || element == .trackRight:
            if element == .trackLeft { trackLeftHeld = isPressed } else { trackRightHeld = isPressed }
            if isPressed { pressed(element, hub: &hub, now: now, into: &step) }
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
            // A mute does nothing in the audio while TotalMix FX's Mute Master is off: say so where
            // the eyes are (Adam, 2026-11-02).
            if hub.mirror.muteMaster == false, !isPFLLayer(layer, hub: hub), infos[layer]?[strip] ?? nil != nil {
                step.midi += overlay("Mute Master off", "in TotalMix FX")
            }
        case .pageUp, .pageDown:
            if shiftHeld { shiftUsedForNavigation = true }
            // Page steps the top send row's output; on the XL 3, Shift + Page the middle row's
            // (Adam, 2026-11-01).
            let row = shiftHeld && layout == .xl3 ? 1 : 0
            guard !shiftHeld || layout == .xl3 else { return }
            stepSend(row: row, by: element == .pageUp ? -1 : 1, hub: &hub, now: now, into: &step)
        case .trackLeft, .trackRight:
            if shiftHeld { shiftUsedForNavigation = true }
            // Eight strips a press; with Shift, the first or the last page. Pages always start at
            // a multiple of eight, as on the Roto-Control: the order is set in the app, so there is
            // nothing to gain from moving one strip (Adam, 2026-11-01).
            // Both Track buttons together go to the first page (Adam, 2026-11-02; the Novation button
            // was tried for this the same day and dropped as hard to find).
            let direction = element == .trackLeft ? -1 : 1
            let bothHeld = trackLeftHeld && trackRightHeld
            goToPage(bothHeld ? .first : shiftHeld ? (direction < 0 ? .first : .last) : .by(direction),
                     hub: &hub, now: now, into: &step)
        default:
            break
        }
    }

    private enum PageMove { case first, last, by(Int) }

    /// Moves every layer to another page: the first, the last (past the end, the hub goes to the
    /// start of the last page), or by eight strips either way.
    private mutating func goToPage(_ move: PageMove, hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        let primary = id(layers[0])
        var output: CoreOutput
        switch move {
        case .first: output = hub.setMode(primary, mode(for: layers[0], first: 0), now: now)
        case .last: output = hub.setMode(primary, mode(for: layers[0], first: Int(Int32.max)), now: now)
        case .by(let direction): output = hub.page(primary, by: direction, now: now)
        }
        if case .strips(_, let first, _, _)? = hub.mode(of: primary) {
            for layer in layers.dropFirst() {
                output.append(hub.setMode(id(layer), mode(for: layer, first: first), now: now))
            }
        }
        take(output, hub: hub, into: &step)
    }

    /// Resolves the send rows against the send targets now (`LaunchControlSendRows.indices`).
    private mutating func resolveSends(_ hub: SurfaceHub) {
        sendIndices = sendRows.indices(targets: hub.sendTargets)
    }

    /// The next send target from `index` in direction `delta` (±1), skipping the other row's;
    /// `nil` past the end. On the Launch Control 3 the top row runs from pan (−1) to the last send.
    private func nextSend(row: Int, by delta: Int, hub: SurfaceHub) -> Int?? {
        let count = hub.sendTargets.count
        let others = Set(sendIndices.enumerated().filter { $0.offset != row }.compactMap(\.element))
        let lowest = layout == .lc3 ? -1 : 0
        var next = (sendIndices.indices.contains(row) ? sendIndices[row] : nil) ?? (layout == .lc3 ? -1 : -delta)
        repeat { next += delta } while others.contains(next)
        guard next >= lowest, next < count else { return nil }
        return .some(next < 0 ? nil : next)
    }

    private mutating func stepSend(row: Int, by delta: Int, hub: inout SurfaceHub, now: Double,
                                   into step: inout LaunchControlStep) {
        guard sendOutputs.indices.contains(row), let next = nextSend(row: row, by: delta, hub: hub) else { return }
        let targets = hub.sendTargets
        guard sendRows.set(row: row, to: next.map { targets[$0] }, targets: targets) else { return }
        resolveSends(hub)
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        let label = next.map { Self.sendLabel(sendName($0, hub: hub)) } ?? "Pan"
        step.midi += overlay(layout == .lc3 ? "Top row" : row == 0 ? "Top row" : "Middle row", label)
    }

    /// The output each send row feeds now, as the device shows it (XL 3: top and middle rows;
    /// Launch Control 3: the top row, `nil` for pan); `nil` for a row with no output.
    public func currentSendOutputs(hub: SurfaceHub) -> [Int?] {
        let targets = hub.sendTargets
        return sendIndices.map { index in index.flatMap { targets.indices.contains($0) ? targets[$0] : nil } }
    }

    /// Sets a send row's output from the app (`nil`: pan, on the Launch Control 3's top row), as
    /// Page does on the device: the other rows keep theirs, and an output the other row has is
    /// refused. Shows the change on the overlay.
    public mutating func setSendOutput(row: Int, to output: Int?, hub: inout SurfaceHub, now: Double) -> LaunchControlStep {
        var step = LaunchControlStep()
        let targets = hub.sendTargets
        let index = output.flatMap { targets.firstIndex(of: $0) }
        guard sendRows.set(row: row, to: output, targets: targets) else { return step }
        resolveSends(hub)
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        let label = index.map { Self.sendLabel(sendName($0, hub: hub)) } ?? "Pan"
        step.midi += overlay(layout == .lc3 ? "Top row" : row == 0 ? "Top row" : "Middle row", label)
        return step
    }

    private func sendName(_ index: Int, hub: SurfaceHub) -> String {
        let targets = hub.sendTargets
        guard targets.indices.contains(index) else { return "none" }
        let ref = ChannelRef(.output, targets[index])
        return hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? ref.description
    }

    private mutating func connect(hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        connected = true
        inCustomMode = false
        lastStart = nil
        lastHeard = now
        lastQuery = nil
        awaitingModeReply = false
        // Buttons held across a reconnection are not known to be held now (review of 2026-11-02).
        shiftHeld = false
        shiftDownAt = nil
        shiftUsedForNavigation = false
        resetThisShift = []
        trackLeftHeld = false
        trackRightHeld = false
        blinkLit = true
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
        case (.xl3, .row0), (.xl3, .row1):
            // The two send rows (Adam, 2026-11-01). A row with no target controls nothing.
            let row = layer == .row0 ? 0 : 1
            // A row with no target gets a send number past the end, which the hub binds to nothing.
            knob = (sendIndices.indices.contains(row) ? sendIndices[row] : nil).map { .send($0) } ?? .send(Int.max)
            if layer == .row0 { switchFunction = .mute }
        case (.xl3, _):
            knob = .pan
        case (.lc3, .row1):
            knob = .level
            switchFunction = buttonsArePFL ? .pfl : .mute
        case (.lc3, _):
            knob = (sendIndices.first ?? nil).map { .send($0) } ?? .pan
        }
        // Always the sources: the outputs are set up in TotalMix FX and left alone during a
        // performance (Adam, 2026-11-01).
        return .strips(view: .sources, first: first, knob: knob, switch: switchFunction)
    }

    private mutating func setModes(first: Int, hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        var output = CoreOutput()
        // Only the layers whose mode changes: setting a mode redraws the layer and resets its
        // holds and pickup, which a Page press has no reason to do to the faders (review of
        // 2026-11-02).
        for layer in layers {
            let mode = mode(for: layer, first: first)
            if hub.mode(of: id(layer)) != mode { output.append(hub.setMode(id(layer), mode, now: now)) }
        }
        take(output, hub: hub, into: &step)
    }

    // MARK: - Controls

    /// Whether Shift + turn may reset now: Shift held at least `resetHold`, with no Page or Track
    /// press since it went down.
    private func resetAllowed(now: Double) -> Bool {
        guard let down = shiftDownAt else { return false }
        return now - down >= Self.resetHold && !shiftUsedForNavigation
    }

    /// Where Shift + turn puts an encoder, from where it is now (`current`, the hub position), or
    /// `nil` to leave it (Adam, 2026-11-02, after the review of that date: a brushed encoder must
    /// never make anything louder):
    /// - a pan goes to the center;
    /// - a level above 0 dB comes down to 0 dB, and one at or below 0 dB stays;
    /// - a send goes to −oo, and a send at −oo goes back to where the last reset took it from
    ///   (`previous`).
    /// With Shift held the device reports only that an encoder turned, not which way, in absolute
    /// and relative mode alike (docs/LAUNCH-CONTROL-XL3.md, tests 9 and 10), so a reset is all
    /// Shift + turn can do.
    func resetPosition(_ layer: Layer, current: Double?, previous: Double?) -> Double? {
        guard case .strips(_, _, let knob, _) = mode(for: layer, first: 0) else { return nil }
        switch knob {
        case .pan:
            return 0.5
        case .level:
            let unity = FaderCurve.position(gainDB: 0)
            return (current ?? 0) > unity ? unity : nil
        case .send(let index):
            guard index != Int.max else { return nil }
            if (current ?? 0) > 0 { return 0 }
            return previous
        }
    }

    /// Resets an encoder turned with Shift held, and moves the device's own value there too, since
    /// the turn left it where it was (test 9), so the next turn without Shift carries on from the
    /// reset.
    private mutating func reset(_ element: LaunchControlElement, layer: Layer, strip: Int,
                                hub: inout SurfaceHub, now: Double, into step: inout LaunchControlStep) {
        guard let strips = hub.strips(of: id(layer)), strips.indices.contains(strip),
              let target = strips[strip].knobTarget else { return }
        let stored = hub.mirror.value(of: target)
        // The hub keeps a pan as −1…+1 and positions as 0…1.
        let current: Double? = { if case .pan = target { return stored.map { ($0 + 1) / 2 } }; return stored }()
        guard let position = resetPosition(layer, current: current, previous: sendsBeforeReset[target]) else { return }
        if case .strips(_, _, .send, _) = mode(for: layer, first: 0) {
            if position == 0 { sendsBeforeReset[target] = current } else { sendsBeforeReset[target] = nil }
        }
        take(hub.controlMoved(id(layer), strip: strip, to: position, now: now), hub: hub, into: &step)
        step.midi += drawOwnMove(layer, strip, hub: hub)
        let value = deviceValue(layer, position)
        guard connected, !inCustomMode, sentPositions[element.controlNumber] != value else { return }
        sentPositions[element.controlNumber] = value
        step.midi += LaunchControlOutgoing.position(element, value) ?? []
    }

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

    /// Whether a layer's encoders set a level or a send, and so use the ARC USB's scale
    /// (`encoderPosition(_:)`); pan encoders don't.
    private func usesVolumeScale(_ layer: Layer) -> Bool {
        guard !usesFaderScale(layer), case .strips(_, _, let knob, _) = mode(for: layer, first: 0) else { return false }
        if case .pan = knob { return false }
        return true
    }

    /// TotalMix FX's position (0…1) for a value from a layer's controls.
    private func devicePosition(_ layer: Layer, _ value: UInt8) -> Double {
        usesFaderScale(layer) ? Self.faderPosition(value)
            : usesVolumeScale(layer) ? Self.encoderPosition(value) : Self.panPosition(value)
    }

    /// The value to send a layer's control for TotalMix FX's position (0…1).
    private func deviceValue(_ layer: Layer, _ position: Double) -> UInt8 {
        usesFaderScale(layer) ? Self.faderValue(position)
            : usesVolumeScale(layer) ? Self.encoderValue(position) : Self.panValue(position)
    }

    /// The pan, in TotalMix FX's whole steps (−100 for L100 to +100 for R100), for a pan encoder's
    /// value: 64 is the center, 0 is L100, and 127 is R100, each value about 1.6 steps (so steps of
    /// 1 or 2; Adam, 2026-11-01).
    public static func panSteps(_ value: UInt8) -> Int {
        let offset = Double(Int(min(value, 127)) - 64)
        return Int((offset < 0 ? offset * 100 / 64 : offset * 100 / 63).rounded())
    }

    /// The hub position (0…1, the center at 0.5) for a pan encoder's value. It lands a quarter step
    /// to the right of one of TotalMix FX's whole pan steps, so that TotalMix FX's window and the
    /// encoder's display show the same step. TotalMix FX has been observed to show the whole step
    /// below a fractional pan, toward L (R1.6 as R01, L2.25 as L03; Adam, 2026-11-01;
    /// docs/LAUNCH-CONTROL-XL3.md, section 9), and the display rounds, so a quarter step to the
    /// right gives the same step in both.
    public static func panPosition(_ value: UInt8) -> Double {
        let steps = panSteps(value)
        guard steps != 0 else { return 0.5 }
        guard steps > -100 else { return 0 }  // L100 is the end, exactly
        let pan = min((Double(steps) + 0.25) / 100, 1)
        return (pan + 1) / 2
    }

    /// The pan encoder's value for a hub position (0…1): the inverse of `panPosition(_:)`, by the
    /// nearest whole pan step.
    public static func panValue(_ position: Double) -> UInt8 {
        let pan = min(max(position.isFinite ? position : 0.5, 0), 1) * 2 - 1
        let steps = (pan * 100).rounded()
        let offset = steps < 0 ? steps * 64 / 100 : steps * 63 / 100
        return UInt8(min(max(64 + offset.rounded(), 0), 127))
    }

    /// The gains of the ARC USB's wheel, one per detent from the bottom (after off) to the top, as
    /// TotalMix FX shows them (Adam, 2026-11-01; docs/TOTALMIX-OSC.md, test 19): 3 dB steps at the
    /// bottom, then 2.5, 2, 1.5, and 1 dB, and 0.5 dB from −5 to +5 dB. Level and send encoders use
    /// this scale, as volume controls (Adam, 2026-11-01).
    public static let arcDetents: [Double] = [
        -63.5, -60.5, -57.5, -54.5, -51.5, -48.5, -45.5, -43, -40.5, -38, -35.5, -33.5, -31.5, -29.5,
        -27.5, -25.5, -24, -22.5, -21, -19.5, -18, -16.5, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6,
        -5, -4.5, -4, -3.5, -3, -2.5, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6,
    ]

    /// The encoder value at 0 dB on the ARC scale: 101, as on the XL 3's faders (`faderTicks`).
    /// Values 1–101 spread the detents from −63.5 to 0 dB evenly, and 101–127 those from 0 to +6 dB
    /// (about 0.42 detents a value either side: 0.2 dB a value near 0 dB, 1.3 dB at the bottom).
    /// Value 0 is off.
    public static let encoderUnityValue = 101

    /// The gain in dB for an encoder value on the ARC scale (fractional values between whole ones),
    /// or `nil` for off.
    static func encoderGain(exactly value: Double) -> Double? {
        guard value >= 1 else { return nil }
        let unity = Double(encoderUnityValue)
        let zero = Double(arcDetents.firstIndex(of: 0) ?? 0)
        let top = Double(arcDetents.count - 1)
        let index = value <= unity ? (value - 1) * zero / (unity - 1) : zero + (min(value, 127) - unity) * (top - zero) / (127 - unity)
        let lower = Int(index.rounded(.down))
        guard lower + 1 < arcDetents.count else { return arcDetents.last }
        let fraction = index - Double(lower)
        return arcDetents[lower] + fraction * (arcDetents[lower + 1] - arcDetents[lower])
    }

    /// TotalMix FX's fader position (0…1) for a level or send encoder's value, on the ARC scale.
    public static func encoderPosition(_ value: UInt8) -> Double {
        guard let gain = encoderGain(exactly: Double(min(value, 127))) else { return 0 }
        return FaderCurve.position(gainDB: gain)
    }

    /// The encoder value for TotalMix FX's fader position (0…1) on the ARC scale: the inverse of
    /// `encoderPosition(_:)`, rounded. A gain between off and the lowest detent is value 1.
    public static func encoderValue(_ position: Double) -> UInt8 {
        guard position.isFinite, let gain = FaderCurve.gainDB(position: min(max(position, 0), 1)) else { return 0 }
        guard let first = arcDetents.first, gain > first else { return 1 }
        let zero = Double(arcDetents.firstIndex(of: 0) ?? 0)
        let top = Double(arcDetents.count - 1)
        var index = top
        for (offset, pair) in zip(arcDetents, arcDetents.dropFirst()).enumerated() where gain <= pair.1 {
            index = Double(offset) + (gain - pair.0) / (pair.1 - pair.0)
            break
        }
        let unity = Double(encoderUnityValue)
        let value = index <= zero ? 1 + index * (unity - 1) / zero : unity + (index - zero) * (127 - unity) / (top - zero)
        return UInt8(min(max(value.rounded(), 1), 127))
    }

    /// The XL 3's fader scale (Adam, 2026-11-01): the gain at each of the nine ticks printed beside
    /// each fader, top to bottom, with the fader value measured at each tick
    /// (docs/LAUNCH-CONTROL-XL3.md, tests 7 and 8: the mean of two passes). The labels are TotalMix FX's own fader marks: +6 (the
    /// top), +3, 0, −6, −10, −20, −40, −60 (docs/TOTALMIX-OSC.md, test 18); the bottom tick, value 0,
    /// is off. Between ticks the gain moves evenly in dB; below −60 it follows TotalMix FX's fader
    /// position down to off.
    public static let faderTicks: [(value: Double, gainDB: Double)] = [
        (127, 6), (119, 3), (101, 0), (83.5, -6), (65.5, -10), (46, -20), (29, -40), (11, -60),
    ]

    /// TotalMix FX's fader position (0…1) for an XL 3 fader value, on the printed scale.
    public static func faderPosition(_ value: UInt8) -> Double {
        faderPosition(exactly: Double(min(value, 127)))
    }

    /// `faderPosition(_:)` for any value from 0 to 127, including the ticks between whole values.
    static func faderPosition(exactly value: Double) -> Double {
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

    /// The XL 3 fader value for TotalMix FX's fader position (0…1): the inverse of
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

    /// Moves this driver's updates out of a core output (e.g., the hub's answer to TotalMix FX) and
    /// into MIDI. If the send targets have changed, the send rows are resolved again
    /// (`sendOutputs`).
    public mutating func take(_ output: CoreOutput, hub: inout SurfaceHub, now: Double) -> LaunchControlStep {
        var step = LaunchControlStep()
        take(output, hub: hub, into: &step)
        let before = sendIndices
        resolveSends(hub)
        if sendIndices != before { setModes(first: page.first, hub: &hub, now: now, into: &step) }
        // Each time, since they depend on the outputs, not on this surface's strips: a send row's
        // color and the home screen follow an output recolored or renamed in TotalMix FX (review of
        // 2026-11-02). All three send only what changed.
        if connected && !inCustomMode {
            step.midi += drawNavigation(hub: hub) + drawSendColors(hub: hub) + drawStationary(hub: hub)
                + drawButtons(hub: hub)
        }
        return step
    }

    /// The send rows' lights, in their outputs' colors, for the strips that show a channel.
    private mutating func drawSendColors(hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        for layer in layers where sendColor(layer, hub: hub) != nil {
            for index in 0..<Self.stripCount {
                let element = self.element(layer, index)
                let active = (infos[layer]?[index] ?? nil) != nil && (knobOn[layer]?[index] ?? false)
                if element.hasLight, active { bytes += color(element, lightColor(layer, index, hub: hub)) }
            }
        }
        return bytes
    }

    /// After the device moved a control, or Shift + turn reset it: the hub doesn't send a surface
    /// its own move back (`SurfaceHub.controlMoved` records the position as already shown), so the
    /// driver notes the level itself, from the mirror (which pickup leaves alone for a move it
    /// doesn't take), and redraws the light's shade when `levelBrightness` is on (review of
    /// 2026-11-02, for 1.0.1).
    private mutating func drawOwnMove(_ layer: Layer, _ strip: Int, hub: SurfaceHub) -> [UInt8] {
        guard levelBrightness, connected, !inCustomMode, let strips = hub.strips(of: id(layer)),
              strips.indices.contains(strip), let target = strips[strip].knobTarget else { return [] }
        if case .pan = target { return [] }
        var values = knobValues[layer] ?? Array(repeating: nil, count: Self.stripCount)
        guard values.indices.contains(strip) else { return [] }
        values[strip] = hub.mirror.value(of: target)
        knobValues[layer] = values
        let element = self.element(layer, strip)
        return element.hasLight ? color(element, lightColor(layer, strip, hub: hub)) : []
    }

    /// An encoder's light: dark for a strip with no channel; else a send row's output color
    /// (`sendColor`) or the strip's own (`color(for:)`), shaded by its level when
    /// `levelBrightness` is on and the encoder is a level or a send.
    private func lightColor(_ layer: Layer, _ index: Int, hub: SurfaceHub) -> LightColor {
        let info = infos[layer]?[index] ?? nil
        guard info != nil, knobOn[layer]?[index] ?? false else { return .palette(0) }
        let base = sendColor(layer, hub: hub) ?? Self.color(for: info)
        let full = Self.encoderColor(base)
        guard levelBrightness, case .strips(_, _, let knob, _) = mode(for: layer, first: 0) else { return full }
        if case .pan = knob { return full }
        guard let position = knobValues[layer]?[index] ?? nil else { return full }
        return Self.shaded(base, position: position)
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
        for (layer, list) in updates {
            var layerInfos = infos[layer] ?? Array(repeating: nil, count: Self.stripCount)
            var layerKnobs = knobOn[layer] ?? Array(repeating: false, count: Self.stripCount)
            var layerValues = knobValues[layer] ?? Array(repeating: nil, count: Self.stripCount)
            var layerSwitches = switchOn[layer] ?? Array(repeating: false, count: Self.stripCount)
            var touched = Set<Int>()
            var values: [Int: String] = [:]  // sent after the strips, once their displays are set up
            for update in list {
                switch update {
                case .page(let first, let count):
                    if layer == layers[0] { page = (first, count) }
                case .strip(let index, let info):
                    guard layerInfos.indices.contains(index) else { continue }
                    layerInfos[index] = info
                    touched.insert(index)
                case .knob(let index, let value):
                    guard layerKnobs.indices.contains(index) else { continue }
                    layerKnobs[index] = value != nil
                    layerValues[index] = value
                    touched.insert(index)
                    if let value {
                        let control = self.element(layer, index)
                        let position = deviceValue(layer, value)
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
            knobValues[layer] = layerValues
            switchOn[layer] = layerSwitches
            for index in touched.sorted() { bytes += drawStrip(layer, index, hub: hub) }
            for (index, value) in values.sorted(by: { $0.key < $1.key }) {
                bytes += text(.control(element(layer, index)), 2, value)
            }
        }
        // Every time (the texts are sent only when they change): the send rows and the buttons'
        // function show there too.
        bytes += drawStationary(hub: hub)
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
        if element.hasLight { bytes += color(element, lightColor(layer, index, hub: hub)) }
        bytes += drawButton(layer, index, hub: hub)
        return bytes
    }

    /// A strip button's light: bright when on, the dimmest shade when off; a mute that is on while
    /// TotalMix FX's Mute Master is off (selected but not silencing) flashes between the two,
    /// `blinkPeriod` each (docs/LAUNCH-CONTROL-XL3.md, test 15; Adam, 2026-11-02).
    private mutating func drawButton(_ layer: Layer, _ index: Int, hub: SurfaceHub) -> [UInt8] {
        guard let button = button(layer, index) else { return [] }
        let info = infos[layer]?[index] ?? nil
        let on = switchOn[layer]?[index] ?? false
        let colorIndex: UInt8
        if info == nil {
            colorIndex = 0
        } else if isPFLLayer(layer, hub: hub) {
            colorIndex = on ? Self.pflOn : Self.pflOff
        } else if on {
            colorIndex = hub.mirror.muteMaster == false && !blinkLit ? Self.muteOff : Self.muteOn
        } else {
            colorIndex = Self.muteOff
        }
        return color(button, colorIndex)
    }

    private func isPFLLayer(_ layer: Layer, hub: SurfaceHub) -> Bool {
        if case .strips(_, _, _, .pfl)? = hub.mode(of: id(layer)) { return true }
        return false
    }

    /// Every strip button's light again; only changed ones are sent. For a change of Mute Master,
    /// which changes no strip.
    private mutating func drawButtons(hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        for layer in layers {
            for index in 0..<Self.stripCount { bytes += drawButton(layer, index, hub: hub) }
        }
        return bytes
    }

    /// For a layer of sends, the palette color of the output it sends to, so that each send row
    /// reads as one send, as in Novation's integrations (Adam, 2026-11-01): the output's TotalMix FX
    /// color, or, if left white (TotalMix FX's default), the row's own hue (`sendRowHues`), so the
    /// rows can be told apart from each other and from the sources (Adam, 2026-11-02, from the
    /// Tier 3 review of that date); `nil` for any other layer.
    private func sendColor(_ layer: Layer, hub: SurfaceHub) -> UInt8? {
        guard case .strips(_, _, .send(let index), _) = mode(for: layer, first: 0) else { return nil }
        let targets = hub.sendTargets
        guard targets.indices.contains(index) else { return nil }
        let color = hub.mirror.channels[ChannelRef(.output, targets[index])]?.color
        if let color, color != 1, let palette = Self.paletteForTotalMixColor[color] { return palette }
        let row = layer == .row1 && layout == .xl3 ? 1 : 0
        return Self.sendRowHues[row]
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

    /// The stationary display (the home screen): what is on the page (`pageTitle`), then what isn't shown
    /// anywhere else on the device (Adam, 2026-11-01). XL 3: where each send row goes ("Top >
    /// Phones 1", "Mid > ADI-2 3/4"). Launch Control 3: the top row ("Top: Pan" or "Top > Phones 1")
    /// and the buttons ("Buttons: Mute" or "Buttons: PFL"). Each strip's own name shows on its
    /// control's display when the control moves. (Four-letter names in two rows of four were tried
    /// first and were unreadable; docs/LAUNCH-CONTROL-XL3.md, test 5.)
    func stationaryLines(hub: SurfaceHub) -> [String] {
        let title = Self.pageTitle((infos[layers[0]] ?? []).compactMap { $0?.channel },
                                   order: hub.layout.channels(.sources, in: hub.mirror))
        func row(_ prefix: String, _ index: Int?, none: String) -> String {
            guard let index, hub.sendTargets.indices.contains(index) else { return prefix + ": " + none }
            return prefix + " " + Self.sendLabel(sendName(index, hub: hub))
        }
        let send = { (row: Int) -> Int? in self.sendIndices.indices.contains(row) ? self.sendIndices[row] : nil }
        if layout == .xl3 {
            return [title, row("Top", send(0), none: "none"), row("Mid", send(1), none: "none")]
        }
        return [title, row("Top", send(0), none: "Pan"), "Buttons: " + (buttonsArePFL ? "PFL" : "Mute")]
    }

    /// The home screen's first line: what is on the page, each kind counted on its own in the
    /// channel order (Adam, 2026-11-01), e.g., "Inputs 1-7", then "Playbacks 1-8" on the next page,
    /// or "In 6-7, PB 1-6" for a page with both. Counting strips instead would count the blanks
    /// left before the playbacks when they start a new page.
    static func pageTitle(_ shown: [ChannelRef], order: [ChannelRef]) -> String {
        func range(_ bus: TotalMixBus) -> (Int, Int)? {
            let ofKind = order.filter { $0.bus == bus }
            let numbers = shown.filter { $0.bus == bus }.compactMap { ref in ofKind.firstIndex(of: ref).map { $0 + 1 } }
            guard let low = numbers.min(), let high = numbers.max() else { return nil }
            return (low, high)
        }
        func text(_ range: (Int, Int)) -> String { range.0 == range.1 ? "\(range.0)" : "\(range.0)-\(range.1)" }
        switch (range(.input), range(.playback)) {
        case let (inputs?, playbacks?): return "In \(text(inputs)), PB \(text(playbacks))"
        case let (inputs?, nil): return (inputs.0 == inputs.1 ? "Input " : "Inputs ") + text(inputs)
        case let (nil, playbacks?): return (playbacks.0 == playbacks.1 ? "Playback " : "Playbacks ") + text(playbacks)
        case (nil, nil): return "No channels"
        }
    }

    /// Sends the home screen's lines that changed, and then brings the screen up again: Track >
    /// changed the text without changing what the screen showed (Adam, 2026-11-01), so the device
    /// seems to redraw the stationary display only when it is brought up (inference; at connect it
    /// is brought up the same way, test 5).
    private mutating func drawStationary(hub: SurfaceHub) -> [UInt8] {
        var bytes = configure(.stationary, .titleNameAndValue, quiet: false)
        for (field, line) in stationaryLines(hub: hub).enumerated() { bytes += text(.stationary, field, line) }
        guard !bytes.isEmpty, connected else { return bytes }
        return bytes + (LaunchControlOutgoing.showDisplay(.stationary, true, model: device) ?? [])
    }

    /// Page and Track lights: lit where they would move, dark at the ends. The Function button (the
    /// Launch Control 3's layout) is yellow while the buttons are PFL and dim otherwise.
    private mutating func drawNavigation(hub: SurfaceHub) -> [UInt8] {
        var bytes: [UInt8] = []
        bytes += color(.trackLeft, page.first > 0 ? Self.navigationOn : 0)
        bytes += color(.trackRight, page.first + Self.stripCount < page.count ? Self.navigationOn : 0)
        // Page for the top send row; while Shift is held (XL 3), for the middle row.
        let row = shiftHeld && layout == .xl3 ? 1 : 0
        let usable = !shiftHeld || layout == .xl3
        bytes += color(.pageUp, usable && nextSend(row: row, by: -1, hub: hub) != nil ? Self.navigationOn : 0)
        bytes += color(.pageDown, usable && nextSend(row: row, by: 1, hub: hub) != nil ? Self.navigationOn : 0)
        if layout == .lc3 { bytes += color(Self.functionButton, buttonsArePFL ? Self.pflOn : Self.functionIdle) }
        return bytes
    }

    /// Shows two lines on the overlay (a temporary display not tied to a control), e.g., after
    /// Function or Page. That the overlay comes up with SysEx 04h 7Fh, as other displays do, is
    /// an inference (not yet tried on the device).
    private mutating func overlay(_ first: String, _ second: String, _ third: String? = nil) -> [UInt8] {
        guard connected else { return [] }
        var bytes = configure(.overlay, third == nil ? .nameAndValue : .titleNameAndValue, quiet: false)
        bytes += text(.overlay, 0, first, force: true)
        bytes += text(.overlay, 1, second, force: true)
        if let third { bytes += text(.overlay, 2, third, force: true) }
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
        color(element, .palette(index))
    }

    private mutating func color(_ element: LaunchControlElement, _ light: LightColor) -> [UInt8] {
        guard element.hasLight, sentColors[element.controlNumber] != light else { return [] }
        sentColors[element.controlNumber] = light
        switch light {
        case .palette(let index):
            return LaunchControlOutgoing.color(element, index) ?? []
        case .rgb(let rgb):
            return LaunchControlOutgoing.rgb(element, red: rgb.red, green: rgb.green, blue: rgb.blue, model: device) ?? []
        }
    }

    // MARK: - Text and colors

    /// The most characters a display field keeps: 20 (inference from the XL 3, test 5).
    public static let fieldLength = 20

    /// The label for a send: "> " and the output's name (AGENTS.md, house style).
    public static func sendLabel(_ name: String) -> String { "> " + name }

    /// Palette colors for the buttons and the navigation lights. Mute is orange and PFL yellow on
    /// every hardware controller, since the Roto-Control's firmware fixes those two and a host can
    /// only turn them on or off (docs/ROTO-CONTROL.md, section 3); a button that is off shows the
    /// dimmest shade of its color, so the two rows can still be told apart (Adam, 2026-11-02).
    /// The palette's first 40 colors have been seen to run as the guide's picture does
    /// (docs/LAUNCH-CONTROL-XL3.md, test 4), each hue a run of four from bright to dim: 5 red and
    /// 7 a darker red, 13 yellow and 15 a darker yellow, 3 white and 1 a dim grey; 9 orange and 11
    /// its dimmest (test 13).
    public static let muteOn: UInt8 = 9
    /// A mute button that is off: the dimmest orange.
    public static let muteOff: UInt8 = 11
    /// How a mute that is on while TotalMix FX's Mute Master is off shows: it flashes between bright
    /// and dim orange, `blinkPeriod` seconds each, drawn by the driver. The medium shade (10) was
    /// tried and was too close to the others to read, and the device has no flashing of its own
    /// (docs/LAUNCH-CONTROL-XL3.md, test 15; Adam, 2026-11-02).
    public static let blinkPeriod: Double = 0.4
    /// A PFL button that is on: yellow.
    public static let pflOn: UInt8 = 13
    /// A PFL button that is off: the dimmest yellow.
    public static let pflOff: UInt8 = 15
    /// Page and Track where they would move: white.
    public static let navigationOn: UInt8 = 3
    /// The Function button while the buttons are mute: the dimmest yellow, PFL's color when off,
    /// as for any button that is off (Adam, 2026-11-02).
    public static let functionIdle: UInt8 = 15
    /// The hue of a send row whose output is left white in TotalMix FX: teal (33) for the top row,
    /// magenta (53) for the XL 3's middle row; neither is one of TotalMix FX's eight colors (Adam,
    /// 2026-11-02, from the Tier 3 review of that date). On the XL 3 both have been told apart from
    /// blue, purple, and green (test 17); teal on its own was seen as cyan (test 18); cyan (37),
    /// tried first, looked too close to blue (test 17).
    public static let sendRowHues: [UInt8] = [33, 53]

    /// A light's color: a palette index (CC on channel 1), or an exact color (SysEx 01h 53h).
    public enum LightColor: Equatable, Sendable {
        /// A palette index, 0 for off.
        case palette(UInt8)
        /// An exact color.
        case rgb(RGB)
    }

    /// An exact color, each part 0–127.
    public struct RGB: Equatable, Sendable {
        /// Red, 0–127.
        public var red: UInt8
        /// Green, 0–127.
        public var green: UInt8
        /// Blue, 0–127.
        public var blue: UInt8

        /// A color from its three parts, each 0–127.
        public init(_ red: UInt8, _ green: UInt8, _ blue: UInt8) {
            (self.red, self.green, self.blue) = (red, green, blue)
        }

        /// This color at `fraction` (0…1) of its brightness, each part rounded and a part that was
        /// lit kept at 1 or more, so the hue stays roughly the same (only roughly at small
        /// fractions, and a fraction of 0 is not dark: use `.palette(0)` for off).
        public func scaled(_ fraction: Double) -> RGB {
            guard fraction.isFinite else { return self }
            func part(_ value: UInt8) -> UInt8 {
                guard value > 0 else { return 0 }
                return UInt8(min(max((Double(value) * fraction).rounded(), 1), 127))
            }
            return RGB(part(red), part(green), part(blue))
        }
    }

    /// The exact color of each palette color the driver lights encoders with, for dimming. Orange
    /// has been seen to match its palette color on buttons (test 13; on encoders it has not been
    /// compared, an inference); yellow is set to the value that matched the buttons' yellow best,
    /// as the encoders show it (test 18); teal, magenta, blue, and white matched on encoders (test
    /// 17); purple's 16, 0, 127 is inferred from 20 looking slightly redder (16 itself not lit);
    /// red and green are read off the guide's palette picture (inference), and grey's is a guess.
    public static let paletteRGB: [UInt8: RGB] = [
        3: RGB(127, 127, 127),   // white
        1: RGB(40, 40, 40),      // grey (a guess)
        9: RGB(127, 40, 0),      // orange (test 13)
        5: RGB(127, 0, 0),       // red
        45: RGB(0, 0, 127),      // blue
        21: RGB(0, 127, 0),      // green
        13: RGB(127, 85, 0),     // yellow, as the encoders show the buttons' yellow (test 18)
        49: RGB(16, 0, 127),     // purple, for TotalMix FX's pink (test 17: 20 was a little redder)
        33: RGB(0, 127, 76),     // teal, the top send row's hue
        53: RGB(127, 0, 127),    // magenta, the middle send row's hue
    ]

    /// The device value (0–127) of the dimmest lit level, at the bottom of an encoder's travel:
    /// 9, 7, and 5 have been seen to dim in turn, and 4 and below to look dark (docs/
    /// LAUNCH-CONTROL-XL3.md, test 18).
    public static let dimmestValue = 5.0

    /// Palette colors an encoder shows as an exact color instead, at full brightness: palette
    /// yellow (13) has been seen to look greener on the encoders than on the buttons, and 127, 85, 0
    /// to match the buttons' yellow best of those tried; palette orange (9) matched (test 18). The
    /// Launch Control 3 gets the same, an inference from the XL 3.
    public static let encoderExactColors: Set<UInt8> = [13]

    /// An encoder's light at full brightness for a palette color: the palette color, or its exact
    /// color (`paletteRGB`) for those in `encoderExactColors`.
    public static func encoderColor(_ color: UInt8) -> LightColor {
        guard encoderExactColors.contains(color), let rgb = paletteRGB[color] else { return .palette(color) }
        return .rgb(rgb)
    }

    /// How bright a level or send encoder is, as a fraction of its color, for a fader position
    /// (0…1), when `levelBrightness` is on; `nil` for dark (−oo, or a position that isn't a
    /// number). The brightness falls geometrically from full at the top of the travel to `floor`
    /// at the bottom, so equal steps of fader travel give equal ratios of brightness (roughly
    /// equal per encoder value on the ARC scale; computed). On the XL 3, even steps of value and a
    /// 2.2 gamma curve bunched at the top, values down to about 80 looked close to full (64 the
    /// first clearly dimmer), and a geometric run from 80 down looked close to even (test 17); the
    /// curve as built was seen to dim and brighten predictably as an encoder turned (test 18). The
    /// dimming is continuous, so turning a control has a visible, proportional effect; it isn't
    /// meant for reading a level off the light (Adam, 2026-11-02).
    public static func brightness(position: Double, floor: Double = dimmestValue / 127) -> Double? {
        guard position.isFinite, FaderCurve.gainDB(position: position) != nil else { return nil }
        let position = min(max(position, 0), 1)
        let floor = min(max(floor, 1e-3), 1)
        return floor * pow(1 / floor, position)
    }

    /// How far a color can dim and keep its hue: until its smallest lit part reaches
    /// `dimmestValue`, the lowest value seen as lit (test 18). Purple (16, 0, 127) stops at
    /// 5/16 of its brightness and orange (127, 40, 0) at 5/40, so their smaller parts don't go
    /// dark first and leave blue or red; red, white, and the other one-part or even colors dim
    /// all the way. At those floors purple and orange were seen to keep their hue beside blue and
    /// red of the same brightness (test 18).
    public static func dimmestFraction(_ rgb: RGB) -> Double {
        let lit = [rgb.red, rgb.green, rgb.blue].filter { $0 > 0 }
        guard let smallest = lit.min() else { return 1 }
        return min(dimmestValue / Double(smallest), 1)
    }

    /// A palette color dimmed for a fader position (`brightness(position:floor:)`, down to the
    /// color's `dimmestFraction`), as its exact RGB (`paletteRGB`), or dark at −oo. A color
    /// without an exact one stays undimmed.
    public static func shaded(_ color: UInt8, position: Double) -> LightColor {
        guard let rgb = paletteRGB[color] else {
            return brightness(position: position) == nil ? .palette(0) : .palette(color)
        }
        guard let fraction = brightness(position: position, floor: dimmestFraction(rgb)) else { return .palette(0) }
        return .rgb(rgb.scaled(fraction))
    }

    /// The palette color for each of TotalMix FX's eight colors (1 white, 2 grey, 3 orange, 4 red,
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
        8: 49,  // pink, as purple (TotalMix FX draws it purple)
    ]

    /// The palette color for a strip: its TotalMix FX color; an output left white (TotalMix FX's
    /// default) by its kind instead, monitoring outputs green and sends blue, as on the
    /// Roto-Control. The by-kind colors are for output strips, which this driver doesn't show (its
    /// strips are always sources); send rows take their colors from `sendColor`.
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
