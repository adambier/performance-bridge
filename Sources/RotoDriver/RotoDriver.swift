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
#if canImport(SurfaceCore)
import SurfaceCore
#endif

/// What the Roto-Control driver produces in answer to MIDI from the Roto-Control: MIDI bytes for
/// the Roto-Control, and the core's output for TotalMix and the other surfaces.
public struct RotoStep: Equatable, Sendable {
    /// Complete MIDI messages for the Roto-Control, in order.
    public var midi: [UInt8] = []
    /// Messages for TotalMix, and updates for the other surfaces. This driver's own updates are
    /// already turned into `midi`.
    public var core = CoreOutput()

    /// Nothing to send.
    public init() {}
}

/// The driver for Melbourne Instruments' Roto-Control, in MIX mode, on top of `SurfaceHub`.
///
/// The driver does no input or output. The app passes it the bytes from the Roto-Control's MIDI
/// port with `receive(_:hub:now:)` and sends on what comes back; it passes the hub's updates for
/// this surface to `render(_:hub:)` and sends the bytes to the Roto-Control.
///
/// How the Roto-Control's MIX mode maps onto the core (docs/ROTO-CONTROL.md):
/// - the audio track set is the sources view, and the master and return set the outputs view;
/// - the level, pan, and send knob modes are the core's `level`, `pan`, and `send(n)`;
/// - the mute and solo switch modes are mute and solo; record arm is PFL (the Roto-Control still
///   labels it "ARM REC");
/// - single-track mode is the core's focus mode on the selected track: level, pan, and six sends
///   on page 0, and eight sends on each later page.
///
/// The driver claims to be Bitwig (`02`), as test 3 recommends: no 0 dB indent at the wrong
/// place, and switches that send only presses.
public struct RotoDriver: Sendable {
    /// What the Roto-Control has, for `SurfaceHub.addSurface`. The jump guard is 8,000 of the
    /// knob's 16,384 counts. In the kept logs of tests 2 and 3, counted by script, every end event
    /// in MIX mode jumped at least 12,690 counts, and no other report in MIX mode differed from the
    /// knob's last by more than 2,942 (docs/ROTO-CONTROL.md, section 6).
    public static let capabilities = SurfaceCapabilities(stripCount: RotoCC.controlCount, feel: .follows,
                                                         hasSwitches: true, hasMeters: true,
                                                         jumpGuard: 8000.0 / Double(RotoSysEx.maximum14Bit))

    /// The meter thresholds sent on connecting: yellow from `MeterScale.warning`, red at
    /// `MeterScale.fullScale`, so that red shows only at full scale. Whether the Roto-Control turns
    /// red at or above the red threshold is untested.
    public static let meterThresholds = (yellow: UInt8(MeterScale.warning), red: UInt8(MeterScale.fullScale))

    /// The surface's name in the hub.
    public let id: SurfaceID
    private var handshake: RotoHandshake
    private var decoder = RotoInputDecoder()
    private var inPluginMode = false
    private var selectedTrack = 0
    private var trackSet: RotoTrackSet = .audio
    private var infos: [StripInfo?] = Array(repeating: nil, count: RotoCC.controlCount)
    private var page = (first: 0, count: 0)

    /// A driver for one Roto-Control, which will claim `hostType` (Bitwig by default).
    public init(id: SurfaceID, hostType: RotoHostType = .bitwig) {
        self.id = id
        handshake = RotoHandshake(hostType: hostType)
    }

    /// Whether the handshake is complete.
    public var isConnected: Bool { handshake.isConnected }

    /// Starts, or restarts, the handshake: the bytes to send now.
    public mutating func start() -> [UInt8] {
        handshake.start().flatMap(\.bytes)
    }

    // MARK: - From the Roto-Control

    /// Takes bytes from the Roto-Control's MIDI port, as they arrive.
    public mutating func receive<S: Sequence>(_ bytes: S, hub: inout SurfaceHub, now: Double) -> RotoStep
    where S.Element == UInt8 {
        var step = RotoStep()
        for input in decoder.feed(bytes) {
            switch input {
            case .message(let message): handle(message, hub: &hub, now: now, into: &step)
            case .control(let event): handle(event, hub: &hub, now: now, into: &step)
            }
        }
        return step
    }

    private mutating func handle(_ message: RotoIncoming, hub: inout SurfaceHub, now: Double, into step: inout RotoStep) {
        let (reply, justConnected) = handshake.handle(message)
        step.midi += reply.flatMap(\.bytes)
        if justConnected {
            inPluginMode = false
            let thresholds = Self.meterThresholds
            step.midi += RotoOutgoing.meterThresholds(yellow: thresholds.yellow, red: thresholds.red).bytes
            take(hub.resend(id, now: now), hub: hub, into: &step)
            return
        }
        guard handshake.isConnected else { return }

        switch message {
        case .pluginMode:
            // PLUGIN mode is not driven yet. The answer is the start of the sequence `sbdev roto`
            // sent in tests 2 and 3, with no plugins; that it settles the Roto-Control with no
            // plugins is an inference, still to be tested.
            inPluginMode = true
            step.midi += [RotoOutgoing.pluginCount(0), .firstPlugin(0), .pluginDetailsEnd].flatMap(\.bytes)
        case .allTracksMode(let mode):
            inPluginMode = false
            trackSet = mode.trackSet
            let next = SurfaceMode.strips(view: Self.view(mode.trackSet), first: firstIfSameView(hub, mode.trackSet),
                                          knob: Self.knobFunction(mode), switch: Self.switchFunction(mode.switchMode))
            take(hub.setMode(id, next, now: now), hub: hub, into: &step)
        case .trackSet(let set):
            trackSet = set
            selectedTrack = 0
            guard case .strips(_, _, let knob, let switchFunction)? = hub.mode(of: id) else { return }
            take(hub.setMode(id, .strips(view: Self.view(set), first: 0, knob: knob, switch: switchFunction), now: now),
                 hub: hub, into: &step)
        case .setFirstTrack(let first):
            guard case .strips(let view, _, let knob, let switchFunction)? = hub.mode(of: id) else { return }
            take(hub.setMode(id, .strips(view: view, first: first, knob: knob, switch: switchFunction), now: now),
                 hub: hub, into: &step)
        case .selectTrack(let index):
            selectedTrack = index
            if case .focus(_, let first)? = hub.mode(of: id), let channel = channel(at: index, hub: hub) {
                take(hub.setMode(id, .focus(channel: channel, first: first), now: now), hub: hub, into: &step)
            }
        case .singleTrackMode(let controlPage):
            inPluginMode = false
            // Test 2: the Roto-Control numbers these pages 0, 1, 2. Page 0 holds level, pan, and
            // sends 1–6; each later page eight sends, so page p starts at the core's slot 8p.
            guard let channel = channel(at: selectedTrack, hub: hub) ?? channel(at: 0, hub: hub) else { return }
            take(hub.setMode(id, .focus(channel: channel, first: max(controlPage, 0) * 8), now: now),
                 hub: hub, into: &step)
        case .requestSendNames(let sendIndex):
            step.midi += sendNames(start: RotoOutgoing.sendNamesStart(forSendIndex: sendIndex), hub: hub).bytes
        case .requestTransportStatus:
            step.midi += RotoOutgoing.transportStatus(RotoTransportStatus()).bytes
        default:
            break
        }
    }

    private mutating func handle(_ event: RotoControlEvent, hub: inout SurfaceHub, now: Double, into step: inout RotoStep) {
        guard handshake.isConnected, !inPluginMode else { return }
        switch event {
        case .knob(let index, let position):
            take(hub.controlMoved(id, strip: index, to: RotoFeedback.fraction(position), now: now), hub: hub, into: &step)
        case .touch(let index, let touched):
            take(hub.touched(id, strip: index, touched, now: now), hub: hub, into: &step)
        case .switch(let index, let value):
            // Type 02: 127 on a press, nothing on release (docs/ROTO-CONTROL.md, section 5).
            guard value >= 64 else { return }
            take(hub.switchPressed(id, strip: index, now: now), hub: hub, into: &step)
        case .transport, .levelToZeroDB, .otherCC:
            break
        }
    }

    /// Moves this surface's updates out of a core output and into MIDI.
    private mutating func take(_ output: CoreOutput, hub: SurfaceHub, into step: inout RotoStep) {
        var output = output
        if let own = output.updates.removeValue(forKey: id) {
            step.midi += render(own, hub: hub)
        }
        step.core.append(output)
    }

    // MARK: - To the Roto-Control

    /// Turns the hub's updates for this surface into MIDI for the Roto-Control. Returns nothing
    /// before the handshake is complete, or in PLUGIN mode.
    public mutating func render(_ updates: [SurfaceUpdate], hub: SurfaceHub) -> [UInt8] {
        guard handshake.isConnected, !inPluginMode, !updates.isEmpty else { return [] }
        var pageChanged = false
        var controls: [UInt8] = []
        for update in updates {
            switch update {
            case .page(let first, let count):
                page = (first, count)
                pageChanged = true
            case .strip(let index, let info):
                guard infos.indices.contains(index) else { continue }
                infos[index] = info
                pageChanged = true
            case .knob(let index, let value):
                guard let value else { continue }
                controls += RotoFeedback.knob(index, position: RotoFeedback.position(value))
            case .valueText(let index, let text):
                controls += RotoOutgoing.showValue(.knob, control: index, text: text).bytes
            case .switchState(let index, let on):
                controls += RotoFeedback.switchLight(index, on: on)
            case .meter(let index, let value):
                let level = UInt8(min(max(value, 0), 127))
                controls += RotoFeedback.meter(index, left: level, right: level)
            }
        }
        guard pageChanged else { return controls }
        return pageMessages(hub: hub).flatMap(\.bytes) + controls
    }

    /// The messages that draw the current page: in all-tracks mode the send names and the eight
    /// strips (TRACK DETAILS END draws them; blank strips are reset); in single-track mode the send
    /// names and DAW SELECT TRACK, which draws the send labels (docs/ROTO-CONTROL.md, section 4).
    private func pageMessages(hub: SurfaceHub) -> [RotoOutgoing] {
        let sendCount = hub.sendTargets.count
        switch hub.mode(of: id) {
        case .focus(let channel, let first)?:
            let controlPage = first / 8
            let start = RotoOutgoing.sendNamesStart(forControlPage: controlPage, numbering: .pageNumbers)
            let info = infos.compactMap { $0 }.first
            let details = RotoTrackDetails(index: max(selectedTrack, 0), name: info?.name ?? channel.description,
                                           colorScheme: Self.colorScheme(forTotalMixColor: info?.color))
            return [.sendCount(sendCount), sendNames(start: start, hub: hub), .selectTrack(details)]
        case .strips(_, _, let knob, _)?:
            var messages: [RotoOutgoing] = [.sendCount(sendCount)]
            if case .send(let sendIndex) = knob {
                messages.append(sendNames(start: RotoOutgoing.sendNamesStart(forSendIndex: sendIndex), hub: hub))
            }
            messages += [.trackCount(page.count), .firstTrack(page.first)]
            for (offset, info) in infos.enumerated() {
                guard let info else { continue }
                messages.append(.trackDetails(RotoTrackDetails(index: page.first + offset, name: info.name,
                                                               colorScheme: Self.colorScheme(forTotalMixColor: info.color)),
                                              immediate: false))
            }
            messages.append(.trackDetailsEnd)
            for (offset, info) in infos.enumerated() where info == nil {
                messages.append(.resetTrackDetails(page.first + offset))
            }
            return messages
        case nil:
            return []
        }
    }

    private func sendNames(start: Int, hub: SurfaceHub) -> RotoOutgoing {
        let targets = hub.sendTargets
        let names = (start..<max(start, min(start + 8, targets.count))).map { index -> String in
            let ref = ChannelRef(.output, targets[index])
            return hub.mirror.channels[ref]?.name ?? ref.description
        }
        return .sendNames(start: start, names: names)
    }

    // MARK: - Mapping

    /// The core's view for a Roto-Control track set.
    public static func view(_ set: RotoTrackSet) -> ViewKind {
        set == .audio ? .sources : .outputs
    }

    /// The core's knob function for a Roto-Control knob mode.
    public static func knobFunction(_ mode: RotoAllTracksMode) -> KnobFunction {
        switch mode.knobMode {
        case .level: return .level
        case .pan: return .pan
        case .send: return .send(mode.sendIndex)
        }
    }

    /// The core's switch function for a Roto-Control switch mode: record arm is PFL.
    public static func switchFunction(_ mode: RotoSwitchMode) -> SwitchFunction {
        switch mode {
        case .mute: return .mute
        case .solo: return .solo
        case .arm: return .pfl
        }
    }

    /// The Roto-Control color scheme (0–82) for a TotalMix color index. A placeholder: TotalMix's
    /// colors have not been matched to the Roto-Control's table yet, so each TotalMix index gets a
    /// different scheme, spread across the table, and no color (or index 1, the default) gets
    /// scheme 0.
    public static func colorScheme(forTotalMixColor color: Int?) -> UInt8 {
        guard let color, color > 1 else { return 0 }
        return UInt8(((color - 1) * 11) % 83)
    }

    private func channel(at index: Int, hub: SurfaceHub) -> ChannelRef? {
        let channels = hub.layout.channels(Self.view(trackSet), in: hub.mirror)
        return channels.indices.contains(index) ? channels[index] : nil
    }

    /// Keeps the page when only the knob or switch mode changed; starts at 0 on a new view.
    private func firstIfSameView(_ hub: SurfaceHub, _ set: RotoTrackSet) -> Int {
        if case .strips(let view, let first, _, _)? = hub.mode(of: id), view == Self.view(set) { return first }
        return 0
    }
}
