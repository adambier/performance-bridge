import Foundation
#if canImport(RotoControl)
import RotoControl
#endif
#if canImport(ArturiaControl)
import ArturiaControl
#endif

// Names for a Roto-Control from an Arturia plugin's own KeyLab connection, while a DAW's
// integration has the Roto-Control (docs/PLUGIN-MODE-PLAN.md, section 10, item 10). The parts
// were each seen to work in docs/ARTURIA.md, tests 12 and 13; this combination is untested. A
// prototype for sbdev. Not affiliated with or endorsed by Arturia, Melbourne Instruments, or
// Bitwig.

/// What the name relay wants sent, after one call.
public struct ArturiaNameRelayOutput: Equatable, Sendable {
    /// Complete Roto-Control messages for the device, to send after the host's own.
    public var toDevice: [[UInt8]] = []
    /// Control changes for the port the plugin's DAW listens to (the asking).
    public var toInstrument: [[UInt8]] = []
    /// Lines for a log.
    public var notes: [String] = []

    /// Makes an output.
    public init(toDevice: [[UInt8]] = [], toInstrument: [[UInt8]] = [], notes: [String] = []) {
        self.toDevice = toDevice
        self.toInstrument = toInstrument
        self.notes = notes
    }

    mutating func add(_ other: ArturiaNameRelayOutput) {
        toDevice += other.toDevice
        toInstrument += other.toInstrument
        notes += other.notes
    }
}

/// Follows two streams: what an Arturia plugin sends a KeyLab mk3 (the preset's name, each
/// knob's value, and a control's name after a control change), and what a DAW's Roto-Control
/// integration sends the device (its plugins, the one selected, and its eight macro
/// parameters). Where the selected plugin is the one on the KeyLab connection, it puts the
/// plugin's own names into the integration's messages, and sends the preset's name as the
/// track's.
///
/// It is pure: no I/O and no clock. The caller passes the plugin's bytes on to a real keyboard
/// itself, sends what the relay returns, and calls `tick` a few times a second.
///
/// Limits, all from what has been seen and not more:
/// - Only Analog Lab V, and only the integration's first page, whose eight parameters were in
///   the keyboard's order in docs/ROTO-CONTROL.md, tests 18 and 19. A remote-controls page the
///   user has changed would get wrong names.
/// - It cannot tell two copies of the plugin apart: the names come from the copy on the KeyLab
///   connection, whichever copy the DAW has selected.
/// - Asking sends a knob's 7-bit value back through the DAW, which moves the parameter to that
///   step and marks the preset as changed (docs/ARTURIA.md, section 4).
public struct ArturiaNameRelay: Sendable {
    /// The KeyLab profile the plugin talks to; the mk3's.
    public let profile: ArturiaKeyLabProfile
    /// Whether to ask the plugin for names it has not sent, by sending a knob's value again.
    public var asksForNames = true
    /// Whether to send the preset's name as the current track's name.
    public var showsPreset = true
    /// Whether the device is in PLUGIN mode. Set by the caller; nothing is sent to the device,
    /// and nothing is asked, while it is false.
    public var isInPluginMode = false

    /// How a host's plugin name has to begin for the names to be put in.
    public static let pluginNamePrefix = "Analog Lab"
    /// How long after the plugin's last value or preset message the asking starts.
    public static let askDelaySeconds: TimeInterval = 0.5
    /// How long an answer is waited for before the next knob is asked.
    public static let askTimeoutSeconds: TimeInterval = 0.4
    /// How long after an answer the next knob is asked, so that the answer's copies have come.
    public static let askGapSeconds: TimeInterval = 0.2
    /// How long after a control change from the keyboard the asking waits.
    public static let keyboardQuietSeconds: TimeInterval = 1

    // MARK: From the plugin

    /// Whether the plugin has connected on the KeyLab port.
    public private(set) var isConnected = false
    /// Whether the connected plugin is Analog Lab V, by the id in its messages.
    public private(set) var isAnalogLab = false
    /// The preset's name, as the plugin last sent it.
    public private(set) var presetName: String?
    private var presetKind: String?
    /// Whether a preset screen has come since the plugin connected. Until then its values are
    /// not trusted: on connecting it has been seen to report 0 for every knob before the real
    /// values, and the preset screen after both (docs/ARTURIA.md, test 13).
    private var hasPresetSinceConnect = false
    private var values: [Int: Int] = [:]
    /// The items whose values have been reported since the plugin connected or the preset changed.
    private var fresh: Set<Int> = []
    private var names: [Int: String] = [:]
    private var lastReport: TimeInterval?
    private var assembler = ArturiaSysExAssembler()
    private var lastScreen: (screen: ArturiaMk3Message, time: TimeInterval)?

    // MARK: From the host and the device

    /// One of the host's eight macro parameters, as it last described it.
    private struct Slot: Sendable, Equatable {
        var index: [UInt8]
        var hash: [UInt8]
        var name: String
    }

    private var pluginNames: [Int: String] = [:]
    private var selectedPlugin: Int?
    private var macroPage = 0
    private var slots = [Slot?](repeating: nil, count: 8)
    /// The name the device last got for each slot.
    private var shown = [String?](repeating: nil, count: 8)
    private var lastTrackName: String?
    private var warnedOfSelection: Int?

    // MARK: Asking

    /// The control changes lately sent to the plugin, by the asking or by a relayed keyboard,
    /// newest last. The mk3's control screen does not say which control it is about, so it is
    /// taken for the newest of these with its value.
    private var recentChanges: [(controller: Int, value: Int, time: TimeInterval)] = []
    private var asked: Set<Int> = []
    private var asking: (item: Int, since: TimeInterval)?
    private var nextAsk: TimeInterval = 0
    private var lastKeyboardChange: TimeInterval?
    private var keyboardParser = RotoMIDIParser()

    /// Makes a relay for a plugin talking to `profile`.
    public init(profile: ArturiaKeyLabProfile = .keyLabMk3) {
        self.profile = profile
    }

    /// The name the plugin has sent for an item, for the preset shown.
    public func name(forItem item: Int) -> String? { names[item] }
    /// The value the plugin last reported for an item.
    public func value(forItem item: Int) -> Int? { values[item] }
    /// The host's name for the selected plugin, if it has selected one.
    public var selectedPluginName: String? { selectedPlugin.flatMap { pluginNames[$0] } }

    /// Whether the host's selected plugin is taken for the one on the KeyLab connection, on the
    /// page whose order is known.
    public var isActive: Bool {
        isInPluginMode && isConnected && isAnalogLab && macroPage == 0
            && (selectedPluginName?.hasPrefix(Self.pluginNamePrefix) ?? false)
    }

    /// The item of the plugin behind a slot of the host's first page: the keyboard's order.
    private func item(forSlot slot: Int) -> Int? { (0..<8).contains(slot) ? slot : nil }

    /// The names to show for the eight slots: the plugin's where it has sent one, fitted to the
    /// device's 12 characters as a set; otherwise the host's, untouched.
    private var wantedNames: [String?] {
        let own: [String?] = (0..<8).map { slot in
            guard isActive, let known = slots[slot], !known.name.isEmpty, let item = item(forSlot: slot) else { return nil }
            return names[item]
        }
        let limit = RotoSysEx.nameFieldLength - 1
        let fitted = RotoNameFit.fit(own.map { $0 ?? "" }, to: [Int](repeating: limit, count: 8))
        return (0..<8).map { slot in
            guard let known = slots[slot], !known.name.isEmpty else { return nil }
            return own[slot] == nil ? known.name : fitted[slot]
        }
    }

    /// Renames, for the device, each slot whose name is not the one wanted, and sends the
    /// preset's name when it is due.
    private mutating func refresh() -> ArturiaNameRelayOutput {
        var output = ArturiaNameRelayOutput()
        guard isInPluginMode else { return output }
        let wanted = wantedNames
        for slot in 0..<8 {
            guard let known = slots[slot], let name = wanted[slot], shown[slot] != nil, shown[slot] != name else { continue }
            shown[slot] = name
            output.toDevice.append(RotoSysEx.frame(.plugin, 0x0F, known.index + known.hash + RotoSysEx.encodeName(name)))
            output.notes.append("knob \(slot + 1): \"\(known.name)\" shown as \"\(name)\"")
        }
        if isActive, showsPreset, let preset = presetName, preset != lastTrackName {
            lastTrackName = preset
            output.toDevice.append(RotoOutgoing.currentTrackName(preset).bytes)
            output.notes.append("preset \"\(preset)\" sent as the track's name")
        }
        if !isActive { lastTrackName = nil }
        if let selected = selectedPlugin, let name = pluginNames[selected], name.hasPrefix(Self.pluginNamePrefix),
           !isConnected, warnedOfSelection != selected {
            warnedOfSelection = selected
            output.notes.append("\"\(name)\" is selected in the host, but no plugin has connected to the KeyLab port: "
                                + "if it is loaded, it is on the keyboard itself; delete it and add it again")
        }
        return output
    }

    /// Takes one complete message the host is sending the device and returns it as it should be
    /// sent, with whatever is to follow it.
    public mutating func fromHost(_ message: [UInt8], now: TimeInterval) -> (message: [UInt8], output: ArturiaNameRelayOutput) {
        guard let (group, command, data) = RotoSysEx.unframe(message), group == 0x0B else {
            return (message, ArturiaNameRelayOutput())
        }
        switch command {
        case 0x02:
            pluginNames = [:]
            if data.first == 0 { select(plugin: nil, page: 0) }
        case 0x05 where data.count >= 10 + RotoSysEx.nameFieldLength:
            pluginNames[Int(data[0])] = RotoSysEx.decodeName(data[10..<(10 + RotoSysEx.nameFieldLength)])
        case 0x08 where data.count >= 2:
            select(plugin: Int(data[0]), page: Int(data[1]))
        case 0x0A where data.count >= 13 + RotoSysEx.nameFieldLength:
            // LEARN PARAM: index (2), hash (6), macro, center detent, steps, position (2), name.
            let index = RotoSysEx.decode14(data[0], data[1])
            guard data[8] != 0, (1...8).contains(index) else { break }
            return rename(message, data: data, slot: index - 1, nameAt: 13, mayAdd: true)
        case 0x0F where data.count >= 8 + RotoSysEx.nameFieldLength:
            // SET MAPPED CONTROL NAME: index (2), hash (6), name.
            let index = RotoSysEx.decode14(data[0], data[1])
            guard (1...8).contains(index) else { break }
            return rename(message, data: data, slot: index - 1, nameAt: 8, mayAdd: false)
        default:
            break
        }
        return (message, refresh())
    }

    private mutating func select(plugin: Int?, page: Int) {
        guard plugin != selectedPlugin || page != macroPage else { return }
        if plugin != selectedPlugin { warnedOfSelection = nil }
        selectedPlugin = plugin
        macroPage = page
        // The host describes its parameters again for the new plugin or page.
        slots = [Slot?](repeating: nil, count: 8)
        shown = [String?](repeating: nil, count: 8)
    }

    /// Notes a host's name for a slot and puts the wanted name in its place.
    private mutating func rename(_ message: [UInt8], data: [UInt8], slot: Int, nameAt: Int, mayAdd: Bool)
        -> (message: [UInt8], output: ArturiaNameRelayOutput) {
        let hash = Array(data[2..<8])
        let name = RotoSysEx.decodeName(data[nameAt..<(nameAt + RotoSysEx.nameFieldLength)])
        if let known = slots[slot], known.hash == hash {
            // The host sends LEARN PARAM once without a name before the one with it.
            if !name.isEmpty { slots[slot]?.name = name }
        } else if mayAdd {
            slots[slot] = Slot(index: Array(data[0..<2]), hash: hash, name: name)
            shown[slot] = nil
        } else {
            return (message, ArturiaNameRelayOutput())
        }
        guard !name.isEmpty, let wanted = wantedNames[slot] else { return (message, ArturiaNameRelayOutput()) }
        var output = ArturiaNameRelayOutput()
        var changed = data
        if wanted != name {
            changed.replaceSubrange(nameAt..<(nameAt + RotoSysEx.nameFieldLength), with: RotoSysEx.encodeName(wanted))
            if shown[slot] != wanted { output.notes.append("knob \(slot + 1): \"\(name)\" shown as \"\(wanted)\"") }
        }
        shown[slot] = wanted
        // A new name can change how the page's other names are fitted.
        output.add(refresh())
        guard wanted != name, let (_, command, _) = RotoSysEx.unframe(message) else { return (message, output) }
        return (RotoSysEx.frame(.plugin, command, changed), output)
    }

    /// Takes one complete message the device is sending the host.
    public mutating func fromDevice(_ message: [UInt8], now: TimeInterval) -> ArturiaNameRelayOutput {
        if let (group, command, data) = RotoSysEx.unframe(message) {
            if group == 0x0B, command == 0x10, let page = data.first {
                select(plugin: selectedPlugin, page: Int(page))
                return refresh()
            }
            return ArturiaNameRelayOutput()
        }
        // A knob the user has turned is not asked about: the plugin has not been seen to report
        // a change the host makes, so the value held for it may be old.
        if message.count == 3, message[0] == 0xB0 | RotoCC.channel, isActive {
            let controller = Int(message[1])
            let knob = (12...19).contains(controller) ? controller - 12 : (44...51).contains(controller) ? controller - 44 : nil
            if let knob, let item = item(forSlot: knob) { asked.insert(item) }
        }
        return ArturiaNameRelayOutput()
    }

    /// Takes the plugin's bytes from the KeyLab port.
    public mutating func fromInstrument<S: Sequence>(_ bytes: S, now: TimeInterval) -> ArturiaNameRelayOutput where S.Element == UInt8 {
        var output = ArturiaNameRelayOutput()
        for message in assembler.feed(bytes) {
            switch ArturiaMk3Message.parse(message) {
            case .connect(let on, let id)?:
                forgetPlugin()
                isConnected = on
                isAnalogLab = on && id == ArturiaMk3Message.analogLabID
                if on { lastReport = now }
            case .property(let item, 1, let value, _)?:
                values[item] = min(max(value, 0), 127)
                fresh.insert(item)
                lastReport = now
            case .preset(let name, _, let kind, _, _)?:
                if hasPresetSinceConnect, name != presetName || kind != presetKind {
                    // Another preset: its names and values are still to come.
                    names = [:]
                    fresh = []
                    asked = []
                    asking = nil
                }
                presetName = name
                presetKind = kind
                hasPresetSinceConnect = true
                lastReport = now
            case .controlScreen(let valueText, let name, let value, _)?:
                let screen = ArturiaMk3Message.controlScreen(valueText: valueText, name: name, value: value, id: 0)
                if let last = lastScreen, last.screen == screen, now - last.time < 0.25 { continue }
                lastScreen = (screen, now)
                let since = now - 1
                guard let change = recentChanges.last(where: { $0.time >= since && (value == nil || $0.value == value) }),
                      let item = profile.item(forController: change.controller) else { continue }
                if !name.isEmpty { names[item] = name }
                if asking?.item == item {
                    asking = nil
                    nextAsk = max(nextAsk, now + Self.askGapSeconds)
                }
            default:
                break
            }
            output.add(refresh())
        }
        return output
    }

    private mutating func forgetPlugin() {
        isConnected = false
        isAnalogLab = false
        presetName = nil
        presetKind = nil
        hasPresetSinceConnect = false
        values = [:]
        fresh = []
        names = [:]
        asked = []
        asking = nil
        lastScreen = nil
    }

    /// Takes the bytes a real keyboard sends, which the caller passes on to the plugin's port:
    /// its control changes are noted, since the plugin answers them with a control's name.
    public mutating func fromKeyboard<S: Sequence>(_ bytes: S, now: TimeInterval) where S.Element == UInt8 {
        for message in keyboardParser.feed(bytes) {
            guard case .controlChange(_, let controller, let value) = message,
                  profile.item(forController: Int(controller)) != nil else { continue }
            noteChange(controller: Int(controller), value: Int(value), now: now)
            lastKeyboardChange = now
        }
    }

    private mutating func noteChange(controller: Int, value: Int, now: TimeInterval) {
        recentChanges.append((controller, value, now))
        if recentChanges.count > 16 { recentChanges.removeFirst(recentChanges.count - 16) }
    }

    /// Asks the plugin for the next name it has not sent, if one is due: one knob at a time,
    /// only a knob the host has described, only with a value the plugin has reported since it
    /// connected or changed its preset, and only once the preset's screen has come.
    public mutating func tick(now: TimeInterval) -> ArturiaNameRelayOutput {
        if let waiting = asking {
            guard now - waiting.since >= Self.askTimeoutSeconds else { return ArturiaNameRelayOutput() }
            asking = nil
        }
        guard asksForNames, isActive, hasPresetSinceConnect, now >= nextAsk,
              let report = lastReport, now - report >= Self.askDelaySeconds else { return ArturiaNameRelayOutput() }
        if let turned = lastKeyboardChange, now - turned < Self.keyboardQuietSeconds { return ArturiaNameRelayOutput() }
        for slot in 0..<8 {
            guard let known = slots[slot], !known.name.isEmpty, let item = item(forSlot: slot),
                  names[item] == nil, !asked.contains(item), fresh.contains(item), let value = values[item],
                  let controller = profile.controller(forItem: item),
                  let change = profile.controlChange(item: item, value: value) else { continue }
            asked.insert(item)
            asking = (item, now)
            noteChange(controller: controller, value: value, now: now)
            return ArturiaNameRelayOutput(toInstrument: [change], notes: ["asking for knob \(slot + 1)'s name with its value, \(value)"])
        }
        return ArturiaNameRelayOutput()
    }
}
