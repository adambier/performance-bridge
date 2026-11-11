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
    /// Whether the app should bring TotalMix FX's window to the front: the Novation button was
    /// pressed (Adam, 2026-11-02).
    public var showTotalMix = false

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
    /// Whether the home screen (the stationary display) is a picture with a meter for each strip
    /// instead of its text: a setting, off by default (Adam, 2026-11-10;
    /// `LaunchControlMeters.swift`).
    public internal(set) var showsMeters: Bool
    /// How the meters' strips are numbered (`MeterNumbering`): by slot, 1–8 on every page, the
    /// default (Adam, 2026-11-11; test 24); the others remain for trials (`sbdev lcbridge --numbers`).
    public var meterNumbering = MeterNumbering.page {
        didSet { if meterNumbering != oldValue { shownBitmap = nil; meterPeaks = [:] } }
    }
    /// For a trial on the device (the UI review of 2026-11-10): the level, in dBFS, above which a
    /// held peak shows even with no bar under it; `nil`, the default, shows a peak only over a bar.
    public var meterPeakFloor: Double?
    /// For a trial on the device (the UI review of 2026-11-10): how fast a bar may fall, in dB a
    /// second; `nil`, the default, lets it follow the average down.
    public var meterFall: Double?
    /// Each channel's shown bar level, in dBFS, and when, for `meterFall`.
    var meterShown: [ChannelRef: (db: Double, at: Double)] = [:]
    /// Each channel's averaged level, in power, and when it was last updated (`showsMeters`).
    var meterAverages: [ChannelRef: (power: Double, at: Double)] = [:]
    /// Each channel's held peak, as a bar height, and when it was reached.
    var meterPeaks: [ChannelRef: (height: Int, at: Double)] = [:]
    /// When the last picture was sent, while its ready reply hasn't come (`bitmapTimeout`).
    var bitmapSentAt: Double?
    /// The last picture sent, packed, so an unchanged one isn't sent again.
    var shownBitmap: [UInt8]?
    /// The send target (an index into `SurfaceHub.sendTargets`) each send row uses now, from
    /// `sendOutputs` (`resolveSends(_:)`); `nil` for none, or pan on the Launch Control 3.
    private var sendIndices: [Int?] = []

    private var connected = false
    private(set) var inCustomMode = false
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
    /// Encoders whose display says a send was reset (`reset`), drawn as usual again when Shift is
    /// released.
    private var resetShown: [(Layer, Int)] = []
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
                levelBrightness: Bool = false, showsMeters: Bool = false) {
        self.name = name
        self.layout = layout
        self.device = device ?? layout
        self.sendRows = LaunchControlSendRows(layout: layout, choices: sendOutputs)
        self.levelBrightness = levelBrightness
        self.showsMeters = showsMeters
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
        // Mutes set while Mute Master is off flash; the lights are sent only when they change.
        let lit = Int((now / Self.blinkPeriod).rounded(.down)) % 2 == 0
        if connected, !inCustomMode, lit != blinkLit, hub.mirror.muteMaster == false {
            blinkLit = lit
            step.midi += drawButtons(hub: hub)
        }
        if connected, !inCustomMode, showsMeters { step.midi += drawMeterScreen(hub: hub, now: now) }
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
        if case .bitmapReady = event {
            // Ready for the next picture (docs/LAUNCH-CONTROL-XL3.md, test 21). It doesn't answer
            // the presence check's mode question, which may still be on its way.
            bitmapSentAt = nil
            return
        }
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
            if !pressed {
                for (layer, strip) in resetShown { step.midi += drawStrip(layer, strip, hub: hub) }
                resetShown = []
            }
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
            guard let info = infos[layer]?[strip] ?? nil else { return }
            let isPFL = isPFLLayer(layer, hub: hub)
            if hub.mirror.muteMaster == false, !isPFL {
                // A mute does nothing in the audio while TotalMix FX's Mute Master is off: say so
                // where the eyes are (Adam, 2026-11-02).
                step.midi += overlay("Mute Master off", "in TotalMix FX")
            } else {
                // The screen says what the press did, as well as the light (Adam, 2026-11-02).
                let on = switchOn[layer]?[strip] ?? false
                step.midi += overlay(info.name, (isPFL ? "PFL" : "Mute") + (on ? " on" : " off"))
            }
        case .novation:
            // Brings TotalMix FX to the front, e.g., to see a setting the controller can't show
            // (Adam, 2026-11-02; it had been left free).
            step.showTotalMix = true
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
        // The meter screen has no page line (too small to read, Adam, 2026-11-10), so the page
        // shows here, in the device's own text, as Page shows a send row's output: its number, then
        // its first and last channels, each with its slot, the number under its meter ("1 Vox",
        // "3 Gtr"), the first pushed left and the last right (Adam, 2026-11-11; test 24: "Vox" and
        // "to Gtr" were slow to take in while the pop-up showed).
        if showsMeters, connected, !inCustomMode {
            let number = pageNumber.map { "Page \($0.current)/\($0.of)" } ?? "Page 1/1"
            let ends = pageEnds().map { "\($0.slot) \($0.name)" }
            switch ends.count {
            case 0: step.midi += overlay(number, "No channels")
            case 1: step.midi += overlay(number, Self.pushed(ends[0], to: .left))
            default: step.midi += overlay(number, Self.pushed(ends[0], to: .left), Self.pushed(ends[1], to: .right))
            }
        }
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
        shownBitmap = nil
        bitmapSentAt = nil
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
        // this way; whether it comes up by itself is untested). With meters, the picture is
        // drawn by `tick` instead.
        if !showsMeters { step.midi += LaunchControlOutgoing.showDisplay(.stationary, true, model: device) ?? [] }
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
        if case .strips(_, _, .send, _) = mode(for: layer, first: 0) {
            // Silencing a send is the one reset that takes something away, so say how to undo it
            // (Adam, 2026-11-02, from the UI review of that date). On the encoder's own display,
            // which the turn brings up: the overlay was covered by it at once (Adam, 2026-11-02);
            // its function line comes back when Shift is released.
            step.midi += text(.control(element), 1, position == 0 ? "Shift+turn: restore" : "Send restored")
            resetShown.append((layer, strip))
        }
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

    /// A strip button's light: bright when on, a dim exact-RGB shade when off (`muteOff`, `pflOff`);
    /// a mute that is on while
    /// TotalMix FX's Mute Master is off (set but not silencing) flashes between the two,
    /// `blinkPeriod` each (docs/LAUNCH-CONTROL-XL3.md, test 15; Adam, 2026-11-02).
    private mutating func drawButton(_ layer: Layer, _ index: Int, hub: SurfaceHub) -> [UInt8] {
        guard let button = button(layer, index) else { return [] }
        let info = infos[layer]?[index] ?? nil
        let on = switchOn[layer]?[index] ?? false
        let light: LightColor
        if info == nil {
            light = .palette(0)
        } else if isPFLLayer(layer, hub: hub) {
            light = on ? .palette(Self.pflOn) : Self.pflOff
        } else if on {
            light = hub.mirror.muteMaster == false && !blinkLit ? Self.muteOff : .palette(Self.muteOn)
        } else {
            light = Self.muteOff
        }
        return color(button, light)
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

    /// The stationary display (the home screen): the page and its first and last channels (`pageLine`), then what isn't shown
    /// anywhere else on the device (Adam, 2026-11-01). XL 3: where each send row goes ("Top >
    /// Phones 1", "Mid > ADI-2 3/4"). Launch Control 3: the top row ("Top: Pan" or "Top > Phones 1")
    /// and the buttons ("Buttons: Mute" or "Buttons: PFL", or "PFL on, buttons Mute" while a channel's
    /// PFL is on with the buttons on mute). Each strip's own name shows on its
    /// control's display when the control moves. (Four-letter names in two rows of four were tried
    /// first and were unreadable; docs/LAUNCH-CONTROL-XL3.md, test 5.)
    func stationaryLines(hub: SurfaceHub) -> [String] {
        let title = Self.pageLine(pageNames(), count: pageChannelNames.count, pageNumber: pageNumber, fits: Self.fitsScreen)
        func row(_ prefix: String, _ index: Int?, none: String) -> String {
            guard let index, hub.sendTargets.indices.contains(index) else { return prefix + ": " + none }
            return prefix + " " + Self.sendLabel(sendName(index, hub: hub))
        }
        let send = { (row: Int) -> Int? in self.sendIndices.indices.contains(row) ? self.sendIndices[row] : nil }
        // "Top" and "Mid", not "Top row" and "Mid row": with "row", most outputs' names ran off the
        // screen ("Top row > ADI-2 3/4", "Mid row > Phones 2"; docs/LAUNCH-CONTROL-XL3.md, test 22).
        if layout == .xl3 {
            return [title, row("Top", send(0), none: "none"), row("Mid", send(1), none: "none")]
        }
        // "PFL on" when a channel's PFL is on while the buttons are mute, since nothing else would
        // show it once Function is released (UI review of 2026-11-02); 20 characters at most.
        let buttons = buttonsArePFL ? "Buttons: PFL" : Self.anyPFL(hub) ? "PFL on, buttons Mute" : "Buttons: Mute"
        return [title, row("Top", send(0), none: "Pan"), buttons]
    }

    /// The page's strips, as the first layer shows them (`nil` for a blank strip).
    var stripInfos: [StripInfo?] { infos[layers[0]] ?? Array(repeating: nil, count: Self.stripCount) }

    /// Forgets what the stationary display was last sent, so `drawStationary` sends it all again
    /// (after pictures replaced it).
    mutating func forgetStationaryText() {
        guard let byte = LaunchControlDisplayTarget.stationary.byte else { return }
        sentConfig[byte] = nil
        for key in sentTexts.keys where key.hasPrefix("\(byte)/") { sentTexts[key] = nil }
    }

    /// The first and last channels' names on the page, as their controls' displays show them (the
    /// app's label, or TotalMix FX's name), `last` `nil` with one channel.
    func pageNames() -> (first: String, last: String?)? {
        let names = pageChannelNames
        guard let first = names.first else { return nil }
        return (first, names.count > 1 ? names.last : nil)
    }

    /// The names of the page's channels, in order, blanks left out.
    var pageChannelNames: [String] { stripInfos.compactMap { $0?.name } }

    /// The page's first and last channels (one, with one channel), each with its slot, 1–8, as the
    /// meters number them.
    func pageEnds() -> [(slot: Int, name: String)] {
        let named = stripInfos.enumerated().compactMap { index, info in info.map { (slot: index + 1, name: $0.name) } }
        guard let first = named.first, let last = named.last else { return [] }
        return named.count > 1 ? [first, last] : [first]
    }

    /// The estimated width (`screenWidth`) a pushed line may take (test 24).
    static let pushedWidth = 120.0

    /// A side of the screen, for `pushed(_:to:fits:)`.
    enum Side { case left, right }

    /// `text` pushed toward one side of the screen with spaces on the other, as far as the field's
    /// 20 characters and `fits` allow. The device centers a line and keeps its spaces; a line wider
    /// than the screen starts at its left edge and loses its end ("3 ADAT 5/6" with ten leading
    /// spaces showed "3 ADAT 5/"; test 24). So the default leaves about 6 pixels to spare
    /// (`pushedWidth`), since the widths are estimates and that one was about 7 short.
    static func pushed(_ text: String, to side: Side,
                       fits: (String) -> Bool = { $0.count <= fieldLength && screenWidth($0) <= pushedWidth }) -> String {
        var line = text
        while true {
            let next = side == .left ? line + " " : " " + line
            guard fits(next) else { return line }
            line = next
        }
    }

    /// The page shown and the number of pages, or `nil` with only one page.
    var pageNumber: (current: Int, of: Int)? {
        let pages = max(1, (page.count + Self.stripCount - 1) / Self.stripCount)
        guard pages > 1 else { return nil }
        return (page.first / Self.stripCount + 1, pages)
    }

    /// The home screen's first line: the page, then its first and last channels by name ("Page 1/2:
    /// Keys to PB 1/2"), as the controls' displays name them. Counts by position ("In 1-3, PB 1-3")
    /// matched nothing in TotalMix FX, and "In" could be read as "ln" (Adam, 2026-11-11; test 24).
    /// "Page " goes when the line doesn't `fit`; then the names go, rather than being cut into
    /// fragments, leaving the page ("Page 1/2") or, with one page, the number of channels, since the
    /// Track pop-up and each control's display show the names in full.
    static func pageLine(_ names: (first: String, last: String?)?, count: Int, pageNumber: (current: Int, of: Int)?,
                         fits: (String) -> Bool) -> String {
        let number = pageNumber.map { "\($0.current)/\($0.of)" }
        guard let names else { return number.map { "Page \($0)" } ?? "No channels" }
        let range = names.last.map { "\(names.first) to \($0)" } ?? names.first
        let candidates = number.map { ["Page \($0): \(range)", "\($0): \(range)", "Page \($0)"] }
            ?? [range, count == 1 ? "1 channel" : "\(count) channels"]
        return candidates.first(where: fits) ?? candidates[candidates.count - 1]
    }

    /// Sends the home screen's lines that changed, and then brings the screen up again: Track >
    /// changed the text without changing what the screen showed (Adam, 2026-11-01), so the device
    /// seems to redraw the stationary display only when it is brought up (inference; at connect it
    /// is brought up the same way, test 5).
    mutating func drawStationary(hub: SurfaceHub) -> [UInt8] {
        // With meters, the home screen is a picture (`drawMeterScreen`, from `tick`).
        guard !showsMeters else { return [] }
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
        // Lit bright yellow while the buttons are PFL, and also whenever a channel's PFL is on, so
        // a PFL left on after Function is released still shows (UI review of 2026-11-02).
        if layout == .lc3 {
            bytes += color(Self.functionButton, buttonsArePFL || Self.anyPFL(hub) ? .palette(Self.pflOn) : Self.functionIdle)
        }
        return bytes
    }

    /// Shows two lines on the overlay (a temporary display not tied to a control), e.g., after
    /// Function or Page. It has been seen after a button press (docs/LAUNCH-CONTROL-XL3.md, test
    /// 16); after Shift + turn on a send it has been seen to flash too fast to read (Adam,
    /// 2026-11-02), so that text goes on the encoder's display instead (section 8, item 13).
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

    /// The bytes that light `element` in `light` on `model`, as the driver sends them (e.g., for
    /// tests).
    public static func lightBytes(_ element: LaunchControlElement, _ light: LightColor,
                                  model: LaunchControlModel = .xl3) -> [UInt8] {
        switch light {
        case .palette(let index):
            return LaunchControlOutgoing.color(element, index) ?? []
        case .rgb(let rgb):
            return LaunchControlOutgoing.rgb(element, red: rgb.red, green: rgb.green, blue: rgb.blue, model: model) ?? []
        }
    }
}
