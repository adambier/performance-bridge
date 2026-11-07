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
/// **Layout** (decided with Adam, 2026-11-04; docs/OXI-E16.md, section 5). Sixteen strips, one
/// encoder each, always the sources:
/// - turn: the strip's level in the home submix, or its pan or its send to one output, as the
///   surface's function is set (`function`);
/// - a short push (under `pflHold`): mute, on release; a push held `pflHold`: PFL; a turn
///   while pushed (push-and-turn): a jump to the next stop that way (`jumpStops`), and no mute
///   or PFL for that push;
/// - with Shift held the encoders are buttons (`ShiftButton`, as OXI's own firmware does it):
///   the modes LEVEL, PAN, and SEND (encoders 1–3), the previous and next send output (11 and
///   12), the previous and next page of sixteen strips (15 and 16); the screen names them and
///   the rings show the mode in use and which arrows go somewhere;
/// - the ring shows the strip's color, filled to its level (bipolar for a pan), and the switch
///   states by shape and motion, orange marks rotating for mute and pink for PFL (`look`, and the rules in
///   its comment); the screen's title shows the function and the page, "PFL" while any PFL is
///   on, and for a moment the value of a turned encoder or the result of a push.
///
/// **The 4-channel layout** (`Layout.four`; Adam, 2026-11-05, "claude/E16 4-channel layout
/// plan.md"): four strips a page, one column each; the rows are send A, send B, pan, and level,
/// top to bottom. A push on any encoder of a column is that channel's mute, a 1 s hold its PFL
/// (the countdown and the marks on the level ring); a mute leaves the pan ring as it is and
/// darkens the send rings. With Shift held, 3 and 4 step send A's output back and forward, 7 and
/// 8 send B's (each skipping the other's), and 15 and 16 the page.
///
/// **Layers.** The hub gives a surface one knob and one switch per strip. In the 16-channel
/// layout the E16's push is mute or PFL, so the driver adds two hub surfaces: the main one (the
/// knob's function, with mute) and a PFL one (the same knob function, unused, with PFL), paged
/// together. In the 4-channel layout each row is a hub surface of four strips: level
/// (with mute), pan (with PFL), send A, and send B.
public struct E16Driver: Sendable {
    /// The hub surface for each layer.
    public enum Layer: String, Sendable, CaseIterable {
        /// The 16-channel layout: the encoders' function, and mute.
        case main
        /// The 16-channel layout: PFL (its knobs, bound to the same function, go unused).
        case pfl
        /// The 4-channel layout: the fourth row, level, with mute.
        case level
        /// The 4-channel layout: the third row, pan, with PFL.
        case pan
        /// The 4-channel layout: the first row, send A.
        case sendA
        /// The 4-channel layout: the second row, send B.
        case sendB
    }

    /// How the encoders are laid out.
    public enum Layout: String, Sendable, CaseIterable {
        /// Sixteen channels a page, one encoder each (1.1.0).
        case sixteen
        /// Four channels a page, one column each: send A, send B, pan, level (Adam, 2026-11-05).
        case four
    }

    /// The layout this driver uses.
    public let layout: Layout

    /// The start of the hub surfaces' names; each layer adds its own (e.g., "e16.main").
    public let name: String

    /// What the encoders do now: level, pan, or a send (an index into `SurfaceHub.sendTargets`).
    public private(set) var function = KnobFunction.level
    /// The send output (an index into `SurfaceHub.sendTargets`) SEND goes back to.
    private var lastSend = 0
    /// The 4-channel layout's send rows, A and B (`SendRows`, as the Launch Control XL 3's two
    /// send rows: never the same output, and a row without a choice takes the first output the
    /// other doesn't use).
    public private(set) var sendRows = SendRows(rowCount: 2, fillsEmptyRows: true)
    /// The output each send row (A, B) was chosen to send to; the app can save these and pass
    /// them back to `init`.
    public var sendOutputs: [Int?] { sendRows.choices }
    /// Whether the screen is drawn by the driver (the FRAMEBUFFER message, with this project's
    /// small font: a title and labels fitted to `labelMaxWidth`) rather than by the firmware's own label
    /// layout (a title and four characters a label). Adam, 2026-11-04: four characters can't
    /// name a stereo pair.
    public var drawsScreen = true
    /// Whether a muted channel's name is drawn inverted (a lit box, dark letters) and a PFL'd
    /// one followed by a small square, on the host-drawn screen: a trial (Adam, 2026-11-05: "let's see it",
    /// with a way to turn it off; `sbdev e16bridge --no-name-marks`).
    public var marksNames = true
    /// Whether the labels are centered in their cells rather than at the left (the title stays
    /// at the left; numbers have places of their own, `drawValue`): chosen by Adam, 2026-11-06
    /// (`sbdev e16bridge --left` for the left).
    public var centersLabels = true
    /// Whether the host-drawn screen shows each channel's level as a bar under its name, from
    /// TotalMix FX's level data ("Send Level Data"), two bars for a stereo channel: a trial
    /// (Adam, 2026-11-06; `sbdev e16bridge --meters`).
    public var showsMeters = false
    /// The shortest time between two screens drawn for a meter's change alone: 25 a second
    /// (the device drew 60 a second smoothly, OXI-E16 test 8).
    public static let meterFrame = 1.0 / 25
    /// How long a meter's peak pixel holds before it drops to the level: a starting value
    /// (inferred, to tune on the device; `sbdev e16bridge --peak-hold`). TotalMix FX's own
    /// "Peak Hold" for OSC holds the whole level, which made the bars slow (Adam, 2026-11-06), so
    /// the driver holds the peak itself and TotalMix FX's option stays off.
    public var peakHold = 2.0
    /// Each channel's held peak, as a bar width, and when it was reached.
    private var peaks: [ChannelRef: (width: Int, at: Double)] = [:]
    /// How quickly a meter's bar follows the level: the time constant, in seconds, of an average
    /// of TotalMix FX's peaks in power. TotalMix FX draws its bar as RMS under a peak line, but
    /// OSC carries only the peaks (OXI-E16 doc; Adam, 2026-11-06: −1.7 dB sent against a −2.9 dB
    /// peak readout), so the bar is an RMS-like average of them, not true RMS; the held pixel is
    /// the true peak. 0.03 s, tuned by eye against TotalMix FX's bar, which is "really snappy"
    /// (Adam, 2026-11-06: 0.3 s and 0.1 s were slower; `sbdev e16bridge --meter-average`).
    public var meterAverage = 0.03
    /// How far below the averaged peaks the bar sits, in dB: 6, tuned by eye so music looks like
    /// TotalMix FX's RMS bar (Adam, 2026-11-06). An approximation: an average of peaks reads
    /// above true RMS by the music's crest, and TotalMix FX's "RMS +3dB" and Peak Hold time
    /// can't be read over OSC (inferred), so the app keeps fixed values rather than settings of
    /// its own (Adam's choice; `sbdev e16bridge --meter-offset`).
    public var meterOffset = 6.0
    /// Each channel's averaged level, in power, and when it was last updated.
    private var averages: [ChannelRef: (power: Double, at: Double)] = [:]
    /// When the screen was last sent, by the driver's clock (`tick`'s `now`).
    private var screenSentAt = -Double.infinity
    private var clock = 0.0
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

    /// How many encoders the device has (and strips the 16-channel layout shows at once).
    public static let stripCount = 16
    /// How many strips a page shows: 16, or 4 in the 4-channel layout.
    public var columns: Int { layout == .four ? 4 : Self.stripCount }
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
        /// The 4-channel layout: a send row's (0 for A, 1 for B) previous output, or next.
        case rowOutput(row: Int, direction: Int)

        /// The encoder each button is on: the modes on the first row, the output arrows at the
        /// end of the third, the page arrows at the end of the last (Adam, 2026-11-04).
        public static let layout: [Int: ShiftButton] = [
            0: .level, 1: .pan, 2: .send, 10: .output(-1), 11: .output(1), 14: .page(-1), 15: .page(1),
        ]

        /// The 4-channel layout's: each send row's arrows at the end of its own row, the page
        /// arrows at the end of the last; back and forward always in the right two columns (Adam,
        /// 2026-11-05).
        public static let fourLayout: [Int: ShiftButton] = [
            2: .rowOutput(row: 0, direction: -1), 3: .rowOutput(row: 0, direction: 1),
            6: .rowOutput(row: 1, direction: -1), 7: .rowOutput(row: 1, direction: 1),
            14: .page(-1), 15: .page(1),
        ]

        /// The label on the screen.
        public var label: String {
            switch self {
            case .level: return "LVL"
            case .pan: return "PAN"
            case .send: return "SEND"
            case .output(let d), .rowOutput(_, let d): return d < 0 ? "<SND" : "SND>"
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
            case .output(let d), .rowOutput(_, let d): return d < 0 ? "<SEND" : "SEND>"
            case .page(let d): return d < 0 ? "<PAGE" : "PAGE>"
            }
        }

        /// Whether this is a mode button (else an arrow).
        public var isMode: Bool {
            switch self {
            case .level, .pan, .send: return true
            case .output, .page, .rowOutput: return false
            }
        }

        /// An arrow's direction (−1 back, +1 forward); 0 for a mode.
        public var direction: Int {
            switch self {
            case .output(let d), .page(let d), .rowOutput(_, let d): return d
            default: return 0
            }
        }
    }
    /// How far one unit of a turn moves a level or send, as a fraction of the fader's travel. The
    /// device sends 1–8 units a message with its own acceleration.
    public static let levelStep: Double = 0.0025
    /// How far one unit of a turn moves a pan, as a fraction of the hub's 0…1 (about one of
    /// TotalMix FX's 200 steps).
    public static let panStep: Double = 0.005
    /// Units a push-and-turn takes one way before it jumps (`jumpStops`): two, so a push that
    /// nudges the knob one unit doesn't jump (inferred; to check on the device, Adam, 2026-11-06).
    public static let jumpUnits = 2
    /// How many of the title's 16 characters the device shows: the last one was cut off ("PF"
    /// for "PFL" at the end; seen 2026-11-04).
    public static let titleWidth = 15
    /// How long the title shows a turned encoder's value or a press's result, in seconds.
    public static let overlayTime: Double = 1
    /// How long the marks and the level each show for a set-only mute, in seconds (a mute set while TotalMix FX's Mute
    /// Master is off, as on the other surfaces).
    public static let blinkPeriod: Double = 0.5
    /// A switch's marks (mute orange, PFL pink): four LEDs a quarter ring apart on a dark ring, moved one LED every
    /// `rotationStep` seconds (Adam's choice, 2026-11-05, OXI's own rotating idiom; a steady
    /// full ring had been one LED from a full-level orange channel).
    public static let rotationStep: Double = 0.15
    /// How many units of turning, one way, a pan at center takes before it moves (`centerStop`):
    /// a starting value, to tune on the device.
    public static let panCenterUnits = 4
    /// How long a turn must pause, after it has stopped at center, before turning moves the pan
    /// on (`centerStop`): 0.05 s, tuned on the device (Adam, 2026-11-06: 0.25 s and 0.1 s felt
    /// like a wait; a fast turn's messages come 4–5 ms apart, so 0.05 s still catches it).
    public static let panCenterPauseDefault = 0.05
    /// `panCenterPauseDefault`, settable for trying values (`sbdev e16bridge --pan-pause`).
    public var panCenterPause = E16Driver.panCenterPauseDefault
    /// For trying amounts side by side (`sbdev e16bridge --pan-center`): encoder n's pan takes
    /// the (n mod count)th of these instead of `panCenterUnits`. Empty in the app.
    public var panCenterTrial: [Int] = []
    /// How near center (in the 0…1 pan) counts as center: well under one of TotalMix FX's 200
    /// pan steps (0.005).
    static let panCenterTolerance = 0.001
    /// How many marks a switch shows.
    public static let markCount = 4

    private var connected = false
    private var lastEnter: Double?
    private var shiftHeld = false
    private var blinkLit = true
    /// The position of the switches' marks, 0–15, advanced every `rotationStep`.
    private var rotation = 0
    /// Units turned at a centered pan so far, and which way, by encoder (`centerStop`).
    private var panCenterHold: [Int: (direction: Int, units: Int)] = [:]
    /// When a turn that stopped at center last sent a message, by encoder (`centerStop`).
    private var panCenterArrival: [Int: Double] = [:]
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
    /// The encoder being pushed and turned (push-and-turn), until it is released.
    private var pushTurning: Int?
    /// Units turned one way since push-and-turn began or last jumped (`jumpUnits`), signed.
    private var jumpTurned = 0
    private var muteOn: [Bool] = Array(repeating: false, count: E16Driver.stripCount)
    private var pflOn: [Bool] = Array(repeating: false, count: E16Driver.stripCount)
    private var sentLabels: [UInt8]?
    /// What the last screen showed (its title parts and labels), so the framebuffer is drawn and
    /// packed only when something on it changed, not on every tick (review of 2026-11-04).
    private var shownScreen: (title: String, tail: String, labels: [String], drawn: Bool, marks: [Int], meters: [Int: [Int]], peaks: [Int: [Int]])?
    private var sentRings: [RingLook?] = Array(repeating: nil, count: E16Driver.stripCount)

    /// How one encoder's ring is drawn: a RING message, then LED messages for any marks. (A
    /// LED message holds until the next RING for its ring: docs/OXI-E16.md, test 5. An earlier
    /// build saw LEDs stick, most likely its own re-sending; the device holds no override.)
    struct RingLook: Hashable {
        var ring: E16Ring
        /// Whether the ring's color is sent as it is, outside the driver's `brightness`: the
        /// Shift page's dim and maximum levels.
        var exact = false
        /// LEDs drawn over the ring with LED messages after it (mute's and PFL's rotating
        /// marks), by index (0 is the first LED left of six o'clock, clockwise; docs/OXI-E16.md,
        /// test 5), each with its color as red, green, blue.
        var marks: [Mark] = []
    }

    struct Mark: Hashable {
        var led: Int
        var rgb: [UInt8]
    }

    /// A driver for one device; `name` starts the hub surfaces' names. `sendOutputs` are the
    /// 4-channel layout's send rows' saved choices (`sendOutputs`).
    public init(name: String, layout: Layout = .sixteen, sendOutputs: [Int?] = []) {
        self.name = name
        self.layout = layout
        self.sendRows = SendRows(rowCount: 2, fillsEmptyRows: true, choices: sendOutputs)
    }

    /// The layers this layout adds to the hub.
    public var layers: [Layer] { layout == .four ? [.level, .pan, .sendA, .sendB] : [.main, .pfl] }
    /// The layer whose switch is mute, and whose strips name the channels and set the page.
    var muteLayer: Layer { layout == .four ? .level : .main }
    /// The layer whose switch is PFL.
    var pflLayer: Layer { layout == .four ? .pan : .pfl }
    /// The 4-channel layout's row for a layer, top first.
    static func row(of layer: Layer) -> Int? {
        switch layer {
        case .sendA: return 0
        case .sendB: return 1
        case .pan: return 2
        case .level: return 3
        case .main, .pfl: return nil
        }
    }
    static let fourRows: [Layer] = [.sendA, .sendB, .pan, .level]

    /// The strip (the column, in the 4-channel layout) an encoder belongs to.
    func column(_ encoder: Int) -> Int { layout == .four ? encoder % 4 : encoder }
    /// The encoders of a strip: one, or a column of four.
    func encoders(ofStrip strip: Int) -> [Int] { layout == .four ? (0..<4).map { strip + $0 * 4 } : [strip] }
    /// The encoder whose ring shows a strip's switches (mute and PFL marks, the countdown): its
    /// own, or the column's level encoder.
    func switchEncoder(ofStrip strip: Int) -> Int { layout == .four ? 12 + strip : strip }
    /// The Shift page's button on an encoder, if any.
    func shiftButton(at encoder: Int) -> ShiftButton? {
        layout == .four ? ShiftButton.fourLayout[encoder] : ShiftButton.layout[encoder]
    }

    /// Whether the device has answered ENTER REMOTE MODE.
    public var isConnected: Bool { connected }

    /// The hub surface for a layer.
    public func id(_ layer: Layer) -> SurfaceID { SurfaceID("\(name).\(layer.rawValue)") }

    /// What each layer has, for the hub: sixteen strips with an endless encoder and a ring, which
    /// follow TotalMix FX, and a switch.
    public static let capabilities = SurfaceCapabilities(stripCount: stripCount, feel: .follows, hasSwitches: true)
    /// What each layer has in this driver's layout: `capabilities`, with four strips in the
    /// 4-channel layout.
    public var layerCapabilities: SurfaceCapabilities {
        SurfaceCapabilities(stripCount: columns, feel: .follows, hasSwitches: true)
    }

    // MARK: - Starting and stopping

    /// Adds the layers to the hub and returns the bytes that ask for Remote Mode. Until the device
    /// answers, `tick(hub:now:)` asks again every `enterInterval`.
    public mutating func start(hub: inout SurfaceHub, now: Double) -> E16Step {
        for layer in layers {
            _ = hub.addSurface(id(layer), capabilities: layerCapabilities, mode: mode(for: layer, first: page.first, hub: hub), now: now)
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
        for layer in layers { hub.removeSurface(id(layer)) }
        connected = false
        lastEnter = nil
        return E16Outgoing.exitRemoteMode
    }

    /// What is due as time passes: ENTER asked again while the device hasn't answered, a push
    /// held long enough for PFL (with its countdown), an overlay ending, and the marks' rotation and alternation.
    public mutating func tick(hub: inout SurfaceHub, now: Double) -> E16Step {
        var step = E16Step()
        clock = now
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
                // a pink arc sweeps the ring (growing for PFL on, shrinking for off; Adam and
                // the UI review, 2026-11-04).
                let stepIndex = Int((now - held.since - Self.tapTime) / Self.countdownStep + 1e-6)
                if stepIndex != countdownShown {
                    let first = countdownShown < 0
                    countdownShown = stepIndex
                    if first, let info = infos[column(held.encoder)] {
                        overlay = (Self.fit(info.name, 7) + (pflOn[held.encoder] ? " -> PFL OFF" : " -> PFL"), .infinity)
                        step.midi += drawLabels(hub: hub)
                    }
                    step.midi += drawRing(switchEncoder(ofStrip: column(held.encoder)), hub: hub)
                }
            }
        }
        if let overlay, now >= overlay.until {
            self.overlay = nil
            step.midi += drawLabels(hub: hub)
        }
        let lit = Int((now / Self.blinkPeriod).rounded(.down)) % 2 == 0
        let turn = Int((now / Self.rotationStep).rounded(.down)) % Self.stripCount
        if lit != blinkLit || turn != rotation {
            blinkLit = lit
            rotation = turn
            step.midi += drawRings(hub: hub)  // only the rings that change are sent
            step.midi += drawLabels(hub: hub)  // a set-only mute's name flashing (`marksNames`)
        } else if showsMeters {
            step.midi += drawLabels(hub: hub)  // the meters, at most `meterFrame` apart
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
            // A turn while the encoder is pushed cancels the push: no mute on release and no
            // PFL countdown (a push-and-turn held over a second would otherwise set PFL; test
            // 6, Adam, 2026-11-05). Push-and-turn is then just a turn until it is given a job.
            if let held, held.encoder == encoder, !held.didPFL {
                self.held = nil
                pushTurning = encoder
                jumpTurned = 0
                if countdownShown >= 0 {
                    countdownShown = -1
                    overlay = nil
                    step.midi += drawLabels(hub: hub)
                }
            }
            let layer = layout == .four ? Self.fourRows[encoder / 4] : Layer.main
            // Push-and-turn jumps to the next stop the way it turns, in both layouts and on every
            // row (Adam, 2026-11-06: "it's best for all encoders to work the same"; it replaced
            // 1.1.1's pan, or level in PAN mode). It takes `jumpUnits` one way, so a push that
            // nudges the knob a unit doesn't jump; a turn back starts the count again.
            if pushTurning == encoder {
                jumpTurned = (jumpTurned != 0 && (jumpTurned > 0) != (delta > 0)) ? delta : jumpTurned + delta
                guard abs(jumpTurned) >= Self.jumpUnits else { return }
                let direction = jumpTurned > 0 ? 1 : -1
                jumpTurned = 0
                turn(encoder, by: direction, jump: true, layer: layer, hub: &hub, now: now, into: &step)
            } else {
                turn(encoder, by: delta, layer: layer, hub: &hub, now: now, into: &step)
            }
        case .pushed(let encoder, true):
            guard (0..<Self.stripCount).contains(encoder) else { return }
            if shiftHeld {
                pressedButton = encoder
                if let button = shiftButton(at: encoder) { press(button, hub: &hub, now: now, into: &step) }
                step.midi += drawRing(encoder, hub: hub)
            } else {
                held = (encoder, now, false)
                countdownShown = -1
                if let other = pushTurning, other != encoder {
                    pushTurning = nil
                    step.midi += drawRing(other, hub: hub)
                }
            }
        case .pushed(let encoder, false):
            if pressedButton == encoder {
                pressedButton = nil
                step.midi += drawRing(encoder, hub: hub)
            }
            if pushTurning == encoder {
                pushTurning = nil
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
            if layout == .four { step.midi += drawRing(switchEncoder(ofStrip: column(encoder)), hub: hub) }
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
        pushTurning = nil
        blinkLit = true
        sentLabels = nil
        shownScreen = nil
        sentRings = Array(repeating: nil, count: Self.stripCount)
        var output = CoreOutput()
        for layer in layers { output.append(hub.resend(id(layer), now: now)) }
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

    /// An encoder turned without Shift: moves its strip's knob by `delta` units, or, with `jump`,
    /// to the next of `jumpStops` the way `delta` points (none that way: nothing).
    private mutating func turn(_ encoder: Int, by delta: Int, jump: Bool = false, layer: Layer = .main, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        let strip = column(encoder)
        guard let strips = hub.strips(of: id(layer)), strips.indices.contains(strip),
              let target = strips[strip].knobTarget else { return }
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
        var position = min(max(current + Double(delta) * stepSize, 0), 1)
        if jump {
            let isPanTarget: Bool = { if case .pan = target { return true } else { return false } }()
            guard let stop = Self.nextStop(from: current, direction: delta, stops: Self.jumpStops(pan: isPanTarget),
                                           tolerance: stepSize / 2) else { return }
            position = stop
        } else if case .pan = target {
            position = centerStop(encoder, from: current, to: position, delta: delta, now: now)
        }
        take(hub.controlMoved(id(layer), strip: strip, to: position, now: now), hub: hub, into: &step)
        // The hub doesn't send a surface its own move back: draw the ring from the mirror, and
        // show the value in the title.
        let moved = hub.mirror.value(of: target)
        let panning: Bool = { if case .pan = target { return true } else { return false } }()
        let value = panning ? moved.map { ($0 + 1) / 2 } : moved
        knobValues[encoder] = value
        step.midi += drawRing(encoder, hub: hub)
        if let info = infos[strip], let moved {
            let text = panning ? ValueText.pan(moved) : ValueText.level(position: moved)
            var who = Self.fit(info.name, 8)
            // A send names its output too, "KEYS>ADI2 -6.0 dB", on the host-drawn screen, where
            // it fits (Adam, 2026-11-06: the title showed only the channel and the level).
            if drawsScreen, case .strips(_, _, .send(let n), _)? = hub.mode(of: id(layer)), hub.sendTargets.indices.contains(n) {
                who = Self.fit(info.name, width: 34) + ">" + shortOutputName(n, width: 34, hub: hub).uppercased()
            }
            show(who + " " + text, now: now, into: &step, hub: hub)
        }
    }

    /// A pan's sticky center (Adam, 2026-11-05): a turn that reaches or crosses center stops
    /// there, however fast, and the rest of that turn is ignored: turn messages arriving less than
    /// `panCenterPause` apart count as the same turn (a fast turn arrived as a burst of messages
    /// of up to 8 units each and went straight through a count of units: Adam, 14:56). After a
    /// pause, the pan stays until `panCenterUnits` units have been turned one way (a turn the
    /// other way starts the count again), and the units beyond move it on. The device's turns are
    /// accelerated (1–8 units a message) and endless, so center is otherwise hard to land on.
    private mutating func centerStop(_ encoder: Int, from current: Double, to proposed: Double, delta: Int, now: Double) -> Double {
        guard delta != 0 else { return proposed }
        let direction = delta > 0 ? 1 : -1
        guard abs(current - 0.5) <= Self.panCenterTolerance else {
            panCenterHold[encoder] = nil
            guard (current - 0.5) * (proposed - 0.5) <= 0 else { return proposed }
            panCenterArrival[encoder] = now
            return 0.5
        }
        if let last = panCenterArrival[encoder] {
            if now - last < panCenterPause {
                panCenterArrival[encoder] = now  // the same turn, still going
                return 0.5
            }
            panCenterArrival[encoder] = nil
        }
        var hold = panCenterHold[encoder] ?? (direction, 0)
        if hold.direction != direction { hold = (direction, 0) }
        hold.units += abs(delta)
        let units = panCenterTrial.isEmpty ? Self.panCenterUnits : panCenterTrial[encoder % panCenterTrial.count]
        guard hold.units > units else {
            panCenterHold[encoder] = hold
            return 0.5
        }
        panCenterHold[encoder] = nil
        return min(max(0.5 + Double(direction * (hold.units - units)) * Self.panStep, 0), 1)
    }

    /// A short push released: toggles the strip's mute and says so on the screen.
    private mutating func mute(_ encoder: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        let strip = column(encoder)
        take(hub.switchPressed(id(muteLayer), strip: strip, now: now), hub: hub, into: &step)
        guard let info = infos[strip] else { return }
        // While Mute Master is off a mute is "set", TotalMix FX's own notion, and does nothing in
        // the audio; the ring's blink says so continuously, so the title says what the press did.
        let on = muteOn[strip]
        let result = hub.mirror.muteMaster == false ? (on ? " MUTE SET" : " MUTE CLR") : (on ? " MUTE ON" : " MUTE OFF")
        show(Self.fit(info.name, 7) + result, now: now, into: &step, hub: hub)
    }

    /// A push held `pflHold`: toggles the strip's PFL and says so on the screen.
    private mutating func pfl(_ encoder: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        let strip = column(encoder)
        take(hub.switchPressed(id(pflLayer), strip: strip, now: now), hub: hub, into: &step)
        guard let info = infos[strip] else { return }
        show(Self.fit(info.name, 7) + " PFL" + (pflOn[strip] ? " ON" : " OFF"), now: now, into: &step, hub: hub)
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
        case .rowOutput(let row, let direction):
            stepSend(row: row, by: direction, hub: &hub, now: now, into: &step)
        }
    }

    /// The send target (an index into `SurfaceHub.sendTargets`) each send row of the 4-channel
    /// layout uses now (A, B); `nil` for a row with no output left.
    public func sendIndices(hub: SurfaceHub) -> [Int?] { sendRows.indices(targets: hub.sendTargets) }

    /// The output each send row feeds now (A, B), by output channel; `nil` for none.
    public func currentSendOutputs(hub: SurfaceHub) -> [Int?] { sendRows.outputs(targets: hub.sendTargets) }

    /// The send target a send row's arrow leads to (`delta` ±1), skipping the other row's; `nil`
    /// past the ends (no wrap).
    func nextSend(row: Int, by delta: Int, hub: SurfaceHub) -> Int? {
        let count = hub.sendTargets.count
        let indices = sendIndices(hub: hub)
        guard indices.indices.contains(row) else { return nil }
        let others = Set(indices.enumerated().filter { $0.offset != row }.compactMap(\.element))
        var next = indices[row] ?? (delta > 0 ? -1 : count)
        repeat { next += delta } while others.contains(next)
        return (0..<count).contains(next) ? next : nil
    }

    /// A send row's arrow pressed: the row moves to the previous or next output.
    private mutating func stepSend(row: Int, by delta: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        guard let next = nextSend(row: row, by: delta, hub: hub) else { return }
        let targets = hub.sendTargets
        guard sendRows.set(row: row, to: targets[next], targets: targets) else { return }
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        step.midi += drawLabels(hub: hub) + drawRings(hub: hub)
    }

    /// Sets a send row's output (0 for A, 1 for B) from the app, as the Shift page's arrows do;
    /// an output the other row has, or that isn't a send target, is refused.
    public mutating func setSendOutput(row: Int, to output: Int, hub: inout SurfaceHub, now: Double) -> E16Step {
        var step = E16Step()
        guard sendRows.set(row: row, to: output, targets: hub.sendTargets) else { return step }
        setModes(first: page.first, hub: &hub, now: now, into: &step)
        if connected { step.midi += drawLabels(hub: hub) + drawRings(hub: hub) }
        return step
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
            let current = page.first / columns
            return (0..<pageCount).contains(current + direction)
        case .rowOutput(let row, let direction):
            return nextSend(row: row, by: direction, hub: hub) != nil
        }
    }

    /// How many pages of strips there are.
    var pageCount: Int { max(1, Int((Double(page.count) / Double(columns)).rounded(.up))) }

    /// Moves every layer a page (`direction` ±1), staying within the view.
    private mutating func movePage(by direction: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        let primary = id(muteLayer)
        var output = hub.page(primary, by: direction, now: now)
        if case .strips(_, let first, _, _)? = hub.mode(of: primary) {
            for layer in layers where layer != muteLayer {
                output.append(hub.setMode(id(layer), mode(for: layer, first: first, hub: hub), now: now))
            }
        }
        take(output, hub: hub, into: &step)
        step.midi += drawLabels(hub: hub) + drawRings(hub: hub)
    }

    // MARK: - Modes

    /// The hub mode for a layer: the sources, from `first`, with the encoders' function and mute
    /// on the main layer, or the same function (unused) and PFL on the PFL layer; in the 4-channel
    /// layout, the row's function, with mute on the level row and PFL on the pan row. A send row
    /// with no output left gets a send number past the end, which the hub binds to nothing.
    func mode(for layer: Layer, first: Int, hub: SurfaceHub) -> SurfaceMode {
        let knob: KnobFunction
        let switchFunction: SwitchFunction
        switch layer {
        case .main: (knob, switchFunction) = (function, .mute)
        case .pfl: (knob, switchFunction) = (function, .pfl)
        case .level: (knob, switchFunction) = (.level, .mute)
        case .pan: (knob, switchFunction) = (.pan, .pfl)
        case .sendA, .sendB:
            let indices = sendIndices(hub: hub)
            let row = layer == .sendA ? 0 : 1
            knob = (indices.indices.contains(row) ? indices[row] : nil).map { .send($0) } ?? .send(Int.max)
            switchFunction = .none
        }
        return .strips(view: .sources, first: first, knob: knob, switch: switchFunction)
    }

    private mutating func setModes(first: Int, hub: inout SurfaceHub, now: Double, into step: inout E16Step) {
        var output = CoreOutput()
        for layer in layers {
            let mode = mode(for: layer, first: first, hub: hub)
            if hub.mode(of: id(layer)) != mode { output.append(hub.setMode(id(layer), mode, now: now)) }
        }
        take(output, hub: hub, into: &step)
    }

    private var isPan: Bool { if case .pan = function { return true } else { return false } }

    /// Push-and-turn's stops (Adam, 2026-11-06): for a level or a send, off (−∞) and 0 dB (no
    /// +6 dB: a one-step 6 dB jump is risky); for a pan, hard left, center, and hard right. As
    /// knob positions, a pan's from 0 (left) to 1 (right).
    static func jumpStops(pan: Bool) -> [Double] { pan ? [0, 0.5, 1] : [0, FaderCurve.unityPosition] }

    /// The first of `stops` (ascending) past `current` the way `direction` points; a stop within
    /// `tolerance` of `current` counts as where the knob is.
    static func nextStop(from current: Double, direction: Int, stops: [Double], tolerance: Double) -> Double? {
        direction > 0 ? stops.first { $0 > current + tolerance } : stops.last { $0 < current - tolerance }
    }

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
        // The send rows follow the send targets as TotalMix FX reports or changes them.
        // (`setModes` changes only the layers whose mode differs.)
        if layout == .four { setModes(first: page.first, hub: &hub, now: now, into: &step) }
        if connected { step.midi += drawLabels(hub: hub) + drawRings(hub: hub) }
        return step
    }

    private mutating func take(_ output: CoreOutput, hub: SurfaceHub, into step: inout E16Step) {
        var output = output
        var own: [(Layer, [SurfaceUpdate])] = []
        for layer in layers {
            if let updates = output.updates.removeValue(forKey: id(layer)) { own.append((layer, updates)) }
        }
        step.core.append(output)
        guard !own.isEmpty else { return }
        var touched = Set<Int>()
        for (layer, list) in own {
            for update in list {
                switch update {
                case .page(let first, let count):
                    if layer == muteLayer { page = (first, count) }
                case .strip(let index, let info):
                    guard layer == muteLayer, infos.indices.contains(index) else { continue }
                    infos[index] = info
                    touched.formUnion(encoders(ofStrip: index))
                case .knob(let index, let value):
                    // The 16-channel layout: the strip's own encoder; the 4-channel layout: the
                    // layer's row in the strip's column.
                    let encoder = Self.row(of: layer).map { $0 * 4 + index } ?? index
                    guard knobValues.indices.contains(encoder), layer != .pfl else { continue }
                    knobValues[encoder] = value
                    touched.insert(encoder)
                case .valueText:
                    break  // the title shows the value of a turn from `turn(_:by:hub:now:into:)`
                case .switchState(let index, let on):
                    guard muteOn.indices.contains(index) else { continue }
                    if layer == muteLayer { muteOn[index] = on } else if layer == pflLayer { pflOn[index] = on }
                    touched.formUnion(encoders(ofStrip: index))
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
        // Channel names fitted as a set, so no two strips show the same short name.
        let fittedNames = Self.fitSet((0..<columns).map { infos[$0]?.name ?? "" }, width: Self.labelMaxWidth)
        let sendIndexNow = sendIndices(hub: hub)
        let labels: [String] = (0..<Self.stripCount).map { index in
            if shiftHeld, layout == .four, index == 0 || index == 4 {
                // The 4-channel Shift page: each send's current output, across the row's two free
                // cells, so the arrows' labels (where they lead) aren't read as it (Adam,
                // 2026-11-06).
                let row = index / 4
                guard sendIndexNow.indices.contains(row), let current = sendIndexNow[row] else { return "" }
                // "A: ADI 3/4": the send's letter goes with its output, as in the title ("A>"),
                // and the arrows say "< SEND >" as on the 16-channel page, the same width as
                // "PAGE" (Adam, 2026-11-06; "SEND A"/"SEND B" on the arrows was tried).
                let prefix = row == 0 ? "A: " : "B: "
                if !drawsScreen { return Self.fit(outputName(current, hub: hub), E16Outgoing.labelLength) }
                return prefix + shortOutputName(current, width: Self.spanWidth - E16Screen.width(of: prefix), hub: hub)
            }
            if shiftHeld, layout == .sixteen, index == 8, !hub.sendTargets.isEmpty {
                // The 16-channel Shift page: the send output across encoders 9–10, beside
                // "< SEND >" (the one in use in SEND mode, else the one SEND goes back to), as
                // the 4-channel page's rows show theirs (Adam, 2026-11-06).
                let current: Int = { if case .send(let n) = function { return n } else { return min(lastSend, hub.sendTargets.count - 1) } }()
                if !drawsScreen { return Self.fit(outputName(current, hub: hub), E16Outgoing.labelLength) }
                // The plain name: a ">" in front read as one more arrow beside "< SEND >".
                return shortOutputName(current, width: Self.spanWidth, hub: hub)
            }
            if shiftHeld {
                // An arrow that goes nowhere shows no label either (Adam, 2026-11-04).
                guard let button = shiftButton(at: index), button.isMode || isAvailable(button, hub: hub) else { return "" }
                if drawsScreen, !button.isMode, case let direction = button.direction {
                    // On the host-drawn screen every arrow pair is "<  WORD  >": the arrows at
                    // the pair's outer margins and one word ("SEND", "PAGE") centered between
                    // them (`pairWords`; Adam, 2026-11-06).
                    return direction < 0 ? "<" : ">"
                }
                if case .rowOutput(_, let direction) = button {
                    // Plain arrows: the row's own label names the send's current output, and a
                    // press shows the new one at once; naming the destination here was read as
                    // the current output (Adam, 2026-11-06).
                    return direction < 0 ? "<" : ">"
                }
                return drawsScreen ? button.longLabel : button.label
            }
            if layout == .four, index < 12 {
                // The 4-channel layout names a channel once, at the bottom; the rows above show
                // their values: send A's level, send B's, and the pan (Adam, 2026-11-05).
                guard infos[column(index)] != nil, let value = knobValues[index] else { return "" }
                let width = drawsScreen ? Self.labelMaxWidth : nil
                if index >= 8 {
                    // A centered pan shows nothing, as an off send does: only values away from
                    // rest show (Adam, 2026-11-06); the ring and, while turning, the title say C.
                    let pan = ValueText.pan(value * 2 - 1)
                    return pan == "C" ? "" : pan
                }
                // A level that is off shows nothing: the name at the bottom of the column says
                // there is a channel, and most sends are off (Adam, 2026-11-05).
                let level = Self.shortLevel(value, width: width)
                return level == "-oo" ? "" : level
            }
            let name = infos[column(index)]?.name ?? ""
            return drawsScreen ? fittedNames[column(index)] : Self.fit(name, E16Outgoing.labelLength)
        }
        let parts = titleParts(hub: hub)
        // The names that show a switch (`marksNames`): the 16-channel layout's every label, the
        // 4-channel layout's bottom row.
        var inverted = Set<Int>(), pflMarked = Set<Int>()
        if marksNames, !shiftHeld {
            for strip in 0..<columns {
                let index = layout == .four ? 12 + strip : strip
                // A mute set while Mute Master is off (not silencing) flashes, in step with its
                // ring (Adam, 2026-11-05).
                if muteOn[strip], hub.mirror.muteMaster != false || blinkLit { inverted.insert(index) }
                if pflOn[strip] { pflMarked.insert(index) }
            }
        }
        // The meters, as bar widths, under the names (`showsMeters`), and their held peaks.
        var meters: [Int: [Int]] = [:], peakWidths: [Int: [Int]] = [:]
        if showsMeters, drawsScreen, !shiftHeld {
            for strip in 0..<columns {
                guard let info = infos[strip] else { continue }
                var refs = [info.channel]
                if info.stereo { refs.append(ChannelRef(info.channel.bus, info.channel.channel + 1)) }
                func width(_ db: Double) -> Int {
                    Int((Double(MeterScale.value(peakDB: db)) / Double(MeterScale.fullScale) * Double(Self.labelMaxWidth)).rounded())
                }
                let index = layout == .four ? 12 + strip : strip
                meters[index] = refs.map { ref in
                    let db = hub.mirror.meters[ref] ?? -.infinity
                    let power = db.isFinite ? pow(10, db / 10) : 0
                    var average = averages[ref] ?? (power, clock)
                    let dt = max(clock - average.at, 0)
                    average.power += (power - average.power) * (meterAverage > 0 ? 1 - exp(-dt / meterAverage) : 1)
                    average.at = clock
                    averages[ref] = average
                    return average.power > 0 ? width(10 * log10(average.power) - meterOffset) : 0
                }
                peakWidths[index] = refs.map { ref in
                    let now = width(hub.mirror.meters[ref] ?? -.infinity)
                    if let held = peaks[ref], held.width >= now, clock - held.at < peakHold { return held.width }
                    peaks[ref] = (now, clock)
                    return now
                }
            }
        }
        let values: Set<Int> = layout == .four && !shiftHeld ? Set(0..<12) : []
        let marks = inverted.sorted() + [-1] + pflMarked.sorted()
        let key = marks + (centersLabels ? [-2] : [])
        if let shown = shownScreen, shown.title == parts.0, shown.tail == parts.1, shown.labels == labels, shown.drawn == drawsScreen, shown.marks == key {
            // Only the meters changed: at most `meterFrame` apart.
            if (shown.meters == meters && shown.peaks == peakWidths) || clock - screenSentAt < Self.meterFrame { return [] }
        }
        shownScreen = (parts.0, parts.1, labels, drawsScreen, key, meters, peakWidths)
        screenSentAt = clock
        let spans: Set<Int> = !shiftHeld ? [] : layout == .four ? [0, 4] : [8]
        // The word between each pair of arrows on the Shift page, keyed by the pair's left cell.
        var pairWords: [Int: String] = [:]
        if shiftHeld, drawsScreen {
            let pairs: [(Int, String)] = layout == .four ? [(2, "SEND"), (6, "SEND"), (14, "PAGE")] : [(10, "SEND"), (14, "PAGE")]
            for (left, word) in pairs where !labels[left].isEmpty || !labels[left + 1].isEmpty { pairWords[left] = word }
        }
        let bytes = drawsScreen ? E16Outgoing.framebuffer(Self.screen(title: parts.0, tail: parts.1, labels: labels, inverted: inverted, pflMarked: pflMarked,
                                                                      centered: centersLabels, values: values, meters: meters, peaks: peakWidths, spans: spans, pairWords: pairWords))
            : E16Outgoing.labels(title: title(hub: hub), labels: labels)
        guard bytes != sentLabels else { return [] }
        sentLabels = bytes
        return bytes
    }

    /// The top of the first row of labels: three clear lines under the title's rule (at 13 the
    /// numbers crowded it; Adam, 2026-11-05).
    public static let labelTop = 14
    /// The distance from one row of labels to the next: 13, so the last row's meter, two pixels
    /// under its letters and two lines for a stereo channel, is on the screen (at 14 an
    /// underline there fell off; Adam, 2026-11-05).
    public static let labelPitch = 13

    /// The host-drawn screen, on a grid of four columns: the title in the first column and its
    /// tail ("PFL 2/3") ending at the last column's edge, a rule under them, and the sixteen
    /// labels in four rows 13 pixels apart in their 32-pixel cells, no wider than
    /// `labelMaxWidth`: at the left of the cell, lined up with the title (Adam, 2026-11-04), or
    /// centered (`centered`; Adam, 2026-11-06). The cells in `values` hold numbers, drawn with
    /// their digits in fixed places (`drawValue`). `inverted` names are drawn in a lit box (a
    /// mute) and `pflMarked` ones followed by a small square (a PFL); `meters` draws a bar of the
    /// given width under a name, a second one under it for a stereo channel's right side.
    public static func screen(title: String, tail: String = "", labels: [String], inverted: Set<Int> = [], pflMarked: Set<Int> = [],
                              centered: Bool = false, values: Set<Int> = [], meters: [Int: [Int]] = [:], peaks: [Int: [Int]] = [:], spans: Set<Int> = [],
                              pairWords: [Int: String] = [:]) -> E16Screen {
        // "-oo" (off) as "-∞": the font has no lowercase (Adam, 2026-11-05).
        let title = title.replacingOccurrences(of: "-oo", with: "-∞")
        let labels = labels.map { $0.replacingOccurrences(of: "-oo", with: "-∞") }
        var screen = E16Screen()
        let cell = E16Screen.width / 4
        let margin = (cell - labelMaxWidth) / 2
        if let tab = title.firstIndex(of: "\t") {
            // Send B, after the break, ends at the third column's right margin.
            screen.draw(String(title[..<tab]), x: margin, y: 0)
            let rest = String(title[title.index(after: tab)...])
            screen.draw(rest, x: cell * 3 - margin - E16Screen.width(of: rest), y: 0)
        } else {
            screen.draw(title, x: margin, y: 0)
        }
        if !tail.isEmpty {
            let x = E16Screen.width - margin - E16Screen.width(of: tail)
            // Blank the title under the tail if a long one runs into it.
            for px in (x - 3)..<E16Screen.width { for py in 0..<8 { screen.set(px, py, false) } }
            screen.draw(tail, x: x, y: 0)
        }
        screen.line(y: 10, from: 0, to: E16Screen.width - 1)
        for (index, label) in labels.prefix(stripCount).enumerated() {
            let cellX = (index % 4) * cell, y = Self.labelTop + (index / 4) * Self.labelPitch
            // A meter: one pixel tall, two under the letters, from the cell's margin; a stereo
            // channel's right side on the line under its left (Adam, 2026-11-06: below the name
            // in both layouts, so it is plainly that channel's).
            for (line, width) in (meters[index] ?? []).enumerated() where width > 0 {
                screen.line(y: y + Self.meterTop + line, from: cellX + margin, to: cellX + margin + min(width, labelMaxWidth) - 1)
            }
            // A held peak: one pixel where the bar last reached, while it's past the bar (Adam,
            // 2026-11-06: "a fast bar and just a pixel for peaks").
            for (line, peak) in (peaks[index] ?? []).enumerated() where peak > (meters[index].map { $0.indices.contains(line) ? $0[line] : 0 } ?? 0) {
                screen.set(cellX + margin + min(peak, labelMaxWidth) - 1, y + Self.meterTop + line)
            }
            if values.contains(index), drawValue(label, cellX: cellX, y: y, on: &screen) { continue }
            if pairWords[index] != nil || pairWords[index - 1] != nil {
                // An arrow of a pair, close beside its word: "< SEND >" (Adam, 2026-11-06: the
                // arrows at the cells' margins left too much space).
                let left = pairWords[index] != nil ? index : index - 1
                let field = pairWords.values.map { E16Screen.width(of: $0) }.max() ?? 0
                let fieldX = Self.pairFieldX(field, left: left)
                let x = left == index ? fieldX - Self.pairGap - E16Screen.width(of: label)
                    : fieldX + field + Self.pairGap
                screen.draw(label, x: x, y: y)
                continue
            }
            if spans.contains(index) {
                // A label across this cell and the next, from this cell's margin.
                screen.draw(label, x: cellX + margin, y: y)
                continue
            }
            let width = E16Screen.width(of: label)
            let x = cellX + (centered ? (cell - width) / 2 : margin)
            screen.draw(label, x: x, y: y)
            guard !label.isEmpty else { continue }
            // PFL: a square after the name, in the cell's spare room (Adam, 2026-11-06: it
            // replaced an underline, which met the meter).
            if pflMarked.contains(index) {
                for px in (x + width + 2)...(x + width + 4) { for py in (y + 2)...(y + 4) { screen.set(px, py) } }
            }
            if inverted.contains(index) {
                // A box one pixel larger than the letters all round, its pixels flipped; with PFL
                // on too, it takes in the square, so the two read as one channel's (Adam,
                // 2026-11-06).
                let boxEnd = pflMarked.contains(index) ? x + width + 5 : x + width
                for px in (x - 1)...boxEnd {
                    for py in (y - 1)...(y + E16Font.glyphHeight) { screen.set(px, py, !screen.pixel(px, py)) }
                }
            }
        }
        for (left, word) in pairWords {
            // Centered on the line between the pair's two cells.
            let y = Self.labelTop + (left / 4) * Self.labelPitch
            let field = pairWords.values.map { E16Screen.width(of: $0) }.max() ?? 0
            screen.draw(word, x: Self.pairFieldX(field, left: left) + (field - E16Screen.width(of: word)) / 2, y: y)
        }
        return screen
    }

    /// Where a Shift-page pair's word field starts. Every pair on a page shares one field, as wide
    /// as the page's widest word, so all the "<" line up and all the ">" line up (Adam,
    /// 2026-11-06); a shorter word is centered in it. The ">" ends at the right cell's margin,
    /// where the column's values end, and the arrows stay put whether or not they're shown.
    static func pairFieldX(_ field: Int, left: Int) -> Int {
        let cell = E16Screen.width / 4
        let rightEdge = (left % 4 + 2) * cell - (cell - labelMaxWidth) / 2 - 1
        return rightEdge - E16Screen.width(of: ">") + 1 - pairGap - field
    }

    /// The space between a Shift-page pair's word and its arrows: one of the font's word spaces,
    /// exactly as "< SEND >" would be set as text (a gap, the space, a gap: 5 px; Adam,
    /// 2026-11-06: 3 px was tight).
    static let pairGap = E16Font.gap + E16Screen.width(of: " ") + E16Font.gap

    /// How far below a label's top its meter's first line is: two blank lines under the letters.
    /// One blank line was tried for a clearer tie to its own name and felt crowded (Adam,
    /// 2026-11-06); the rows can't move further apart on the 64-line screen.
    public static let meterTop = E16Font.glyphHeight + 2

        /// The width of a label across two cells (`spans`): from the first cell's margin to the
    /// second's.
    static let spanWidth = E16Screen.width / 2 - 2 * ((E16Screen.width / 4 - labelMaxWidth) / 2)

    /// The width of a digit's place in `drawValue`: the widest digit.
    static let digitSlot = 4

    /// Draws a number in a cell with its digits in fixed places, so a value holds still while it
    /// changes (Adam, 2026-11-06): a level's tenths digit ends at the cell's right margin and its
    /// point stays put; a pan's last digit ends there too (lining it up with a level's units was
    /// tried and dropped: pans and levels aren't compared, and the right edge is tidier); each
    /// digit sits at the right of a place `digitSlot` wide (a "1" is narrower), and the sign
    /// ("-", "+", "L", "R") just before the first digit's place. "C" ends at the margin too. Returns false
    /// for text it doesn't lay out this way.
    static func drawValue(_ text: String, cellX: Int, y: Int, on screen: inout E16Screen) -> Bool {
        guard !text.isEmpty else { return true }
        let cell = E16Screen.width / 4
        let right = cellX + (cell - labelMaxWidth) / 2 + labelMaxWidth - 1
        if text == "C" {
            // At the right margin, as a pan's last digit, so it holds still as C turns into R1
            // (Adam, 2026-11-06; centered, it jumped).
            screen.draw(text, x: right - E16Screen.width(of: text) + 1, y: y)
            return true
        }
        var body = Substring(text)
        var sign = ""
        if let first = body.first, "+-LR".contains(first) { sign = String(first); body = body.dropFirst() }
        let parts = body.split(separator: ".", omittingEmptySubsequences: false)
        guard (1...2).contains(parts.count), parts.allSatisfy({ !$0.isEmpty && $0.allSatisfy(\.isNumber) }) else { return false }
        let gap = E16Font.gap
        func place(_ digit: Character, endingAt end: Int) {
            screen.draw(String(digit), x: end - E16Screen.width(of: String(digit)) + 1, y: y)
        }
        var end = right
        if parts.count == 2 {
            for digit in parts[1].reversed() { place(digit, endingAt: end); end -= digitSlot + gap }
            // `end` is now the point's column: the tenths' place, then a gap, after it.
            let point = E16Screen.width(of: ".")
            screen.draw(".", x: end - point + 1, y: y)
            end -= point + gap
        }
        for digit in parts[0].reversed() { place(digit, endingAt: end); end -= digitSlot + gap }
        if !sign.isEmpty { screen.draw(sign, x: end + 1 - E16Screen.width(of: sign), y: y) }
        return true
    }

    /// The title: an overlay while one shows; else the function ("LEVEL", "PAN", "> PHONES 1"),
    /// "PFL" (a square on the host-drawn screen) while a channel's PFL is on, anywhere in the mixer
    /// (UI review, 2026-11-04: "Cue/PFL to" can't be read, so the app shows that PFL is in use;
    /// TotalMix FX doesn't answer the app's own PFL, but does report one set in its window), and,
    /// with more than one page, the page. The same with Shift held, so the choice made there shows at
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
        // PFL anywhere in the mixer, not only on this page (it read only this page's strips
        // before, so a PFL left on another page didn't show; found 2026-11-06). On the host-drawn
        // screen with name marks on, a PFL'd channel on this page already shows its square, so
        // the title shows the square only for one that isn't on the page (Adam, 2026-11-06); it
        // is the name marks' square, narrow enough for the 4-channel title's send B.
        let pflRefs = Set(hub.mirror.channels.filter { $0.value.pfl }.map(\.key))
        if !pflRefs.isEmpty {
            let shown = Set(infos.compactMap { $0?.channel })
            if !drawsScreen || !marksNames { tail.append(drawsScreen ? "■" : "PFL") }
            else if !pflRefs.isSubset(of: shown) { tail.append("■") }
        }
        if pageCount > 1 { tail.append("\(page.first / columns + 1)/\(pageCount)") }
        return (functionName(hub: hub), tail.joined(separator: " "))
    }

    /// The function's name for the title: "LEVEL", "PAN", or "> " and the send's output.
    public func functionName(hub: SurfaceHub) -> String {
        if layout == .four {
            // The send rows' outputs: "A>ADI2 3/4 B>MONS". On the host-drawn screen each name
            // gets half the title's width left after a tail of "PFL 9/9" (so a name doesn't
            // change as PFL comes and goes; Adam, 2026-11-06: longer names); the firmware's
            // labels keep three characters.
            let indices = sendIndices(hub: hub)
            let margin = (E16Screen.width / 4 - Self.labelMaxWidth) / 2
            // Send B's name ends at the third column's right margin (Adam, 2026-11-06: one space
            // between the names was crowded), so the two names share the first three columns.
            let room = E16Screen.width * 3 / 4 - 2 * margin - E16Screen.width(of: "A>B>") - 6
            func part(_ row: Int) -> String {
                let index = indices.indices.contains(row) ? indices[row] : nil
                let name = index.map { outputName($0, hub: hub) }
                let short = index.flatMap { i in name.map { drawsScreen ? shortOutputName(i, width: room / 2, hub: hub).uppercased() : Self.fit($0, 3).uppercased() } }
                return (row == 0 ? "A>" : "B>") + (short ?? "-")
            }
            return part(0) + (drawsScreen ? Self.sendNameBreak : " ") + part(1)
        }
        switch function {
        case .level: return "LEVEL"
        case .pan: return "PAN"
        case .send(let index):
            let targets = hub.sendTargets
            guard targets.indices.contains(index) else { return "SEND" }
            guard drawsScreen else { return "> " + outputName(index, hub: hub).uppercased() }
            // ">ADI 3/4", shortened with the rest of the send targets, as the 4-channel title's
            // "A>…" is (Adam, 2026-11-06); room is left for a "■ 9/9" tail.
            let margin = (E16Screen.width / 4 - Self.labelMaxWidth) / 2
            let room = E16Screen.width - 2 * margin - E16Screen.width(of: "■ 9/9") - 4 - E16Screen.width(of: ">")
            return ">" + shortOutputName(index, width: room, hub: hub).uppercased()
        }
    }

    /// A level as a label: its gain without " dB" ("-6.0", "+2.5", "0.0", "-oo"), or in whole
    /// decibels ("-12") where the tenth doesn't fit: `width` pixels on the host-drawn screen, or
    /// the firmware's four characters (`width` nil).
    static func shortLevel(_ position: Double, width: Int?) -> String {
        guard let gain = FaderCurve.gainDB(position: position) else { return "-oo" }
        func text(_ format: String, _ value: Double) -> String {
            let rounded = abs(value) < 0.05 ? 0 : value
            return String(format: rounded > 0 ? "+" + format : format, rounded)
        }
        func fits(_ label: String) -> Bool { width.map { E16Screen.width(of: label) <= $0 } ?? (label.count <= E16Outgoing.labelLength) }
        // A tenth, then whole decibels; the "+" goes only where nothing else fits (Adam,
        // 2026-11-05).
        let forms = [text("%.1f", (gain * 10).rounded() / 10), text("%.0f", gain.rounded())]
        let all = forms + forms.map { $0.hasPrefix("+") ? String($0.dropFirst()) : $0 }
        return all.first(where: fits) ?? all.last!
    }

    /// Marks where the 4-channel title's send B starts: `screen` draws what follows ending at the
    /// third column's right margin, not after send A (Adam, 2026-11-06).
    static let sendNameBreak = "\t"

    /// A send target's name (an index into `SurfaceHub.sendTargets`): the app's label for it, or
    /// TotalMix FX's name.
    /// A send target's name fitted to `width` pixels as one of the set of send targets
    /// (`fitSet`), so no two outputs show the same short name.
    func shortOutputName(_ index: Int, width: Int, hub: SurfaceHub) -> String {
        let names = hub.sendTargets.indices.map { outputName($0, hub: hub) }
        guard names.indices.contains(index) else { return "" }
        return Self.fitSet(names, width: width)[index]
    }

    func outputName(_ index: Int, hub: SurfaceHub) -> String {
        let targets = hub.sendTargets
        guard targets.indices.contains(index) else { return "" }
        let ref = ChannelRef(.output, targets[index])
        return hub.layout.label(for: ref) ?? hub.mirror.channels[ref]?.name ?? ref.description
    }

    /// Every ring, sent only where it changed, in one RING message.
    private mutating func drawRings(hub: SurfaceHub) -> [UInt8] {
        var rings: [(encoder: Int, ring: E16Ring)] = []
        var leds: [(encoder: Int, led: Int, red: UInt8, green: UInt8, blue: UInt8)] = []
        for index in 0..<Self.stripCount {
            let look = look(index, hub: hub)
            guard sentRings[index] != look else { continue }
            sentRings[index] = look
            rings.append((index, look.exact ? look.ring : dimmed(look.ring)))
            leds += Self.leds(for: look, encoder: index, brightness: brightness)
        }
        // The RING message first: a LED message holds until the next RING for its ring (test 5).
        return E16Outgoing.rings(rings) + E16Outgoing.leds(leds)
    }

    /// A look's marks as LED messages' chunks, dimmed like the ring.
    private static func leds(for look: RingLook, encoder: Int, brightness: Double) -> [(encoder: Int, led: Int, red: UInt8, green: UInt8, blue: UInt8)] {
        look.marks.compactMap { mark in
            guard mark.rgb.count == 3 else { return nil }
            let rgb = scaled((mark.rgb[0], mark.rgb[1], mark.rgb[2]), brightness: brightness)
            return (encoder: encoder, led: mark.led, red: rgb.0, green: rgb.1, blue: rgb.2)
        }
    }

    /// The dimmest a color's largest part goes: a lit ring stays visibly lit (the LEDs are bright
    /// already at 3 or 4). Below the brightness where a color would reach it, the whole color is
    /// held there, in proportion.
    public static let dimFloor: UInt8 = 4

    /// A color at a brightness, 0…1, in proportion: every part scaled alike, so the hue is the
    /// same at every setting (a floor added to each part pushed orange toward yellow at low
    /// settings; Adam, 2026-11-04); the largest part never below `dimFloor`, and a part that is
    /// lit never rounds to nothing.
    public static func scaled(_ rgb: (UInt8, UInt8, UInt8), brightness: Double) -> (UInt8, UInt8, UInt8) {
        let top = Double(max(rgb.0, rgb.1, rgb.2))
        guard top > 0 else { return (0, 0, 0) }
        var scale = brightness.isFinite ? min(max(brightness, 0), 1) : 1
        if top * scale < Double(dimFloor) { scale = Double(dimFloor) / top }
        func part(_ v: UInt8) -> UInt8 { v == 0 ? 0 : UInt8(min(max((Double(v) * scale).rounded(), 1), 127)) }
        return (part(rgb.0), part(rgb.1), part(rgb.2))
    }

    private func dimmed(_ ring: E16Ring) -> E16Ring {
        let rgb = Self.scaled((ring.red, ring.green, ring.blue), brightness: brightness)
        return E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: ring.amount, bipolar: ring.bipolar)
    }

    private mutating func drawRing(_ index: Int, hub: SurfaceHub) -> [UInt8] {
        let look = look(index, hub: hub)
        guard sentRings[index] != look else { return [] }
        sentRings[index] = look
        return E16Outgoing.rings([(encoder: index, ring: look.exact ? look.ring : dimmed(look.ring))])
            + E16Outgoing.leds(Self.leds(for: look, encoder: index, brightness: brightness))
    }

    /// A strip's ring, by the rules from the UI review (2026-11-04), with RING messages and, for
    /// a switch's marks, LED messages after them (test 5):
    /// - dark means no channel: a strip with a channel always lights at least one LED (`floor`,
    ///   as OXI's own "Color Indicator" setting does);
    /// - a level fills the ring at 0 dB and above (`levelAmount`; Adam, 2026-11-05), since a
    ///   switch that is on is no longer a full ring;
    /// - color is the second cue, shape and motion the first: orange for mute, as on the
    ///   other surfaces, and pink for PFL (`pflRGB`);
    /// - one meaning per motion: steady is a value; four marks a quarter ring apart rotating on
    ///   a dark ring (`rotationStep` a step) is a switch that is on, orange for mute and pink
    ///   for PFL (both: interleaved); a mute that is set but not in effect while TotalMix FX's
    ///   Mute Master is off shows its marks still, alternating with the level every
    ///   `blinkPeriod`, or, with PFL on, turning with PFL's and blinking; a one-shot pink arc growing (or, for PFL off, shrinking) is the push
    ///   held for PFL.
    func look(_ index: Int, hub: SurfaceHub) -> RingLook {
        if shiftHeld { return buttonRing(index, hub: hub) }
        let strip = column(index)
        guard let info = infos[strip], let value = knobValues[index] else { return RingLook(ring: .off) }
        if let held, column(held.encoder) == strip, index == switchEncoder(ofStrip: strip), !held.didPFL, countdownShown >= 0 {
            let progress = min(Double(countdownShown) * Self.countdownStep / (Self.pflHold - Self.tapTime), 1)
            let amount = pflOn[strip] ? 1 - progress : progress
            return RingLook(ring: E16Ring(red: Self.pflRGB.0, green: Self.pflRGB.1, blue: Self.pflRGB.2, amount: amount))
        }
        var rgb = Self.rgb(for: info)
        let muteInEffect = muteOn[strip] && hub.mirror.muteMaster != false
        if layout == .four, index < 12 {
            // The 4-channel layout's other rows (the plan, 2026-11-05): a pan as in the
            // 16-channel layout, unchanged by a mute; a send in its output's color (the
            // channel's, for an output left white), dark while a mute is in effect, since a mute
            // silences the channel's sends too (inference; to test on the device).
            if index >= 8 { return RingLook(ring: Self.panRing(value, rgb)) }
            guard !muteInEffect else { return RingLook(ring: .off) }
            let indices = sendIndices(hub: hub)
            if let n = indices[index / 4], hub.sendTargets.indices.contains(n),
               let color = hub.mirror.channels[ChannelRef(.output, hub.sendTargets[n])]?.color, color != 1,
               let sendRGB = Self.totalMixRGB[color] { rgb = sendRGB }
            return RingLook(ring: E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: Self.levelAmount(value)))
        }
        if layout == .sixteen, case .send(let n) = function, hub.sendTargets.indices.contains(n) {
            let output = ChannelRef(.output, hub.sendTargets[n])
            if let color = hub.mirror.channels[output]?.color, color != 1, let sendRGB = Self.totalMixRGB[color] { rgb = sendRGB }
        }
        let level: E16Ring = isPan
            ? Self.panRing(value, rgb)
            : E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: Self.levelAmount(value))
        // A switch that is on is four marks a quarter ring apart turning on a dark ring: orange
        // for mute, pink for PFL, interleaved two LEDs apart when both are on (Adam,
        // 2026-11-05: mute and PFL alike, by color). A mute that is set while TotalMix FX's
        // Mute Master is off (not silencing) shows its marks still, alternating with the level
        // every `blinkPeriod`; with PFL on, they turn with PFL's and blink, and the level
        // does not show.
        let muteSetOnly = muteOn[strip] && hub.mirror.muteMaster == false
        let turning = pflOn[strip] || muteInEffect
        let start = turning ? rotation : 0
        var marks: [Mark] = []
        if muteInEffect || (muteSetOnly && blinkLit) {
            marks += Self.quarterMarks(from: start, Self.muteRGB)
        }
        if pflOn[strip] {
            marks += Self.quarterMarks(from: start + Self.stripCount / Self.markCount / 2, Self.pflRGB)
        }
        guard !marks.isEmpty else { return RingLook(ring: level) }
        return RingLook(ring: .off, marks: marks)
    }

    /// Four marks a quarter ring apart, from `start`.
    static func quarterMarks(from start: Int, _ rgb: (UInt8, UInt8, UInt8)) -> [Mark] {
        (0..<markCount).map { Mark(led: (start + $0 * stripCount / markCount) % stripCount, rgb: [rgb.0, rgb.1, rgb.2]) }
    }

    /// A pan's ring, from the top: in the channel's color at center, red as soon as it is off
    /// center, since a pan of L1 or R1 draws too small an arc to tell from center (Adam,
    /// 2026-11-05).
    /// Off center, the arc is also at least `panMinimumOffset` from the top, so L1 and R1 show
    /// by shape too, on a channel that is red itself (Adam, 2026-11-05).
    static func panRing(_ position: Double, _ rgb: (UInt8, UInt8, UInt8)) -> E16Ring {
        let position = position.isFinite ? min(max(position, 0), 1) : 0.5  // a NaN never equals itself, so would re-send forever
        let offset = position - 0.5
        guard abs(offset) > 0.001 else {
            return E16Ring(red: rgb.0, green: rgb.1, blue: rgb.2, amount: position, bipolar: true)
        }
        let shown = 0.5 + (offset < 0 ? -1 : 1) * max(abs(offset), Self.panMinimumOffset)
        let c = Self.panOffCenterRGB
        return E16Ring(red: c.0, green: c.1, blue: c.2, amount: shown, bipolar: true)
    }

    /// The least a pan off center is drawn from the top, as a fraction of the pan's range: one
    /// LED's worth: at R1 the device lit one red LED right of the top (docs/OXI-E16.md, test 7).
    public static let panMinimumOffset = 1.0 / 16

    /// A pan's color off center (`panRing`).
    public static let panOffCenterRGB: (UInt8, UInt8, UInt8) = (127, 0, 0)

    /// The least a strip with a channel lights, as a fraction of the ring: one LED.
    public static let floor = 1.0 / 16
    /// How much of the ring a level (a fader position, 0…1) lights: the whole ring at 0 dB and
    /// above (Adam, 2026-11-05), in proportion below, and never less than `floor`.
    public static func levelAmount(_ position: Double) -> Double {
        guard position.isFinite else { return floor }
        return min(max(position / FaderCurve.unityPosition, floor), 1)
    }

    /// A ring on the Shift page, full, in the button's color (`buttonColors`), at one of four
    /// levels (Adam, 2026-11-04, after the brightness ramp): dark for a blank or an arrow that
    /// goes nowhere; `availableLevel` (a color scaled to a maximum part of 2 of 127, the lowest
    /// level that reads as lit) for a button that is available; the driver's `brightness` for
    /// the mode in use; and its color with its largest part at 127 while a button is held down, a momentary answer to
    /// the press.
    func buttonRing(_ index: Int, hub: SurfaceHub) -> RingLook {
        guard let button = shiftButton(at: index) else { return RingLook(ring: .off) }
        let rgb: (UInt8, UInt8, UInt8)
        var inUse = false
        switch button {
        case .level: rgb = Self.buttonColors.level; inUse = function == .level
        case .pan: rgb = Self.buttonColors.pan; inUse = function == .pan
        case .send:
            rgb = Self.buttonColors.send
            if case .send = function { inUse = true }
        case .output, .rowOutput: rgb = Self.buttonColors.send
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
    public static let muteRGB: (UInt8, UInt8, UInt8) = (127, 25, 0)
    /// Pink, for a PFL and for the countdown: the hue TotalMix FX's colors leave free; the
    /// yellows and yellow-greens tried first were too close to yellow or green at the lowest
    /// brightness (Adam, 2026-11-04, with `sbdev e16 colors`).
    public static let pflRGB: (UInt8, UInt8, UInt8) = (127, 30, 60)

    /// An RGB (0–127 per part) for each of TotalMix FX's eight colors (1 white, 2 grey, 3 orange,
    /// 4 red, 5 blue, 6 green, 7 yellow, 8 pink; docs/TOTALMIX-OSC.md, test 7), as the Launch
    /// Control driver renders them.
    public static let totalMixRGB: [Int: (UInt8, UInt8, UInt8)] = [
        1: (127, 127, 127),
        2: (0, 110, 127),  // grey as cyan, the hue TotalMix FX leaves free: a dim grey looked like a dimmer white or a level, and blue-greys like blue (Adam, 2026-11-04)
        3: (127, 25, 0),   // orange: at 10% (13, 3, 0), three steps of green over red's none (Adam, 2026-11-04)
        4: (127, 0, 0),
        5: (0, 0, 127),
        6: (0, 105, 0),    // green, slightly darker (Adam, 2026-11-04)
        7: (127, 85, 0),   // yellow: at 6% (8, 5, 0), apart from orange's (8, 2, 0) (Adam, 2026-11-04)
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
    /// Fits a set of names to `width` pixels together (Adam, 2026-11-06): each takes the
    /// longest of its `candidates` that fits, and where two different names would come out the
    /// same ("ADI-2 3/4" and "ADAT 3/4" both "AD3/4"), each of them takes instead the first of its
    /// `distinctForms` that fits and no other name in the set uses ("AI3/4", "AT3/4").
    static func fitSet(_ names: [String], width: Int) -> [String] {
        var chosen = names.map { fit($0, width: width) }
        for _ in 0..<3 {
            var changed = false
            let groups = Dictionary(grouping: chosen.indices, by: { chosen[$0].uppercased() })
            for (_, members) in groups where members.count > 1 && Set(members.map { names[$0].uppercased() }).count > 1 {
                let others = Set(chosen.indices.filter { !members.contains($0) }.map { chosen[$0].uppercased() })
                var taken = others
                for i in members {
                    if let form = distinctForms(names[i]).first(where: { E16Screen.width(of: $0) <= width && !taken.contains($0.uppercased()) }) {
                        chosen[i] = form
                        taken.insert(form.uppercased())
                        changed = true
                    }
                }
            }
            if !changed { break }
        }
        return chosen
    }

    /// Short forms of a "word number" name that keep more of what tells it apart: the word's
    /// first three letters, then its first letter with each later letter (the last first), each
    /// with the number or pair ("ADAT 3/4": "ADA3/4", "AT3/4", "AA3/4", "AD3/4").
    static func distinctForms(_ text: String) -> [String] {
        let plain = text.replacingOccurrences(of: #"-[0-9]+(?= )"#, with: "", options: .regularExpression)
        let parts = plain.split(separator: " ").map(String.init)
        guard parts.count >= 2, let rest = parts.last, rest.first?.isNumber == true else { return [] }
        let word = Array(parts.dropLast().joined())
        guard word.count >= 2 else { return [] }
        var forms = [String(word.prefix(3)) + rest]
        for j in stride(from: word.count - 1, through: 1, by: -1) { forms.append(String(word[0]) + String(word[j]) + rest) }
        return forms
    }

    static func candidates(_ text: String) -> [String] {
        // A hyphenated model number before a pair or number ("ADI-2 3/4") goes before any of
        // the word's letters: "ADI 3/4", "ADI3/4", then the word's ladder (Adam, 2026-11-06).
        if let range = text.range(of: #"^[A-Za-z]+-[0-9]+(?= [0-9])"#, options: .regularExpression),
           let hyphen = text[range].firstIndex(of: "-") {
            let shorter = String(text[..<hyphen]) + String(text[range.upperBound...])
            var out = [text]
            for form in candidates(shorter) where !out.contains(form) { out.append(form) }
            return out
        }
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
