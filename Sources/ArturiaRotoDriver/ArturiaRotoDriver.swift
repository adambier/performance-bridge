import Foundation
#if canImport(RotoControl)
import RotoControl
#endif
#if canImport(ArturiaControl)
import ArturiaControl
#endif

// A prototype driver that shows a standalone Arturia instrument on the Roto-Control's PLUGIN mode
// as one macro plugin (docs/PLUGIN-MODE-PLAN.md, section 6). The instrument's side rests on
// docs/ARTURIA.md (tests 1–4, with Pigments and Analog Lab V); the Roto-Control's side on a
// reading of Melbourne Instruments' Bitwig integration and test R1. Run once, under the first
// KeyLab's profile, with Pigments and a Roto-Control (docs/ARTURIA.md, test 2); under the KeyLab
// mkII's profile, which names the controls, not yet.

/// One message from the driver to the Roto-Control.
public enum ArturiaRotoDeviceMessage: Equatable, Sendable {
    /// A SysEx message.
    case message(RotoOutgoing)
    /// A knob (0–7) moved to a 14-bit position: its two control changes.
    case knob(Int, position: Int)

    /// The complete MIDI bytes.
    public var bytes: [UInt8] {
        switch self {
        case .message(let message): return message.bytes
        case .knob(let knob, let position): return RotoFeedback.knob(knob, position: position)
        }
    }
}

/// What the driver wants sent after one call.
public struct ArturiaRotoOutput: Equatable, Sendable {
    /// Messages for the Roto-Control, in order.
    public var toDevice: [ArturiaRotoDeviceMessage]
    /// Complete MIDI messages (control changes) for the instrument, in order.
    public var toInstrument: [[UInt8]]
    /// Messages for a real keyboard relayed beside the Roto-Control, as raw MIDI bytes: a knob's
    /// new value in the instrument's own format, so that the keyboard's knob follows a change made
    /// on the Roto-Control (a KeyLab 61 mk3 has been seen to take it: docs/ARTURIA.md, test 9).
    public var toKeyboard: [[UInt8]] = []

    /// Makes an output.
    public init(toDevice: [ArturiaRotoDeviceMessage] = [], toInstrument: [[UInt8]] = []) {
        self.toDevice = toDevice
        self.toInstrument = toInstrument
    }

    /// Whether there is nothing to send.
    public var isEmpty: Bool { toDevice.isEmpty && toInstrument.isEmpty && toKeyboard.isEmpty }
}

/// One knob of a page: the control change it sends the instrument, the item the instrument reports
/// it under, and its name on the device until the instrument names it.
public struct ArturiaRotoControl: Equatable, Sendable {
    /// The control change number.
    public var controller: Int
    /// The item number the instrument reports the control under (by the driver's profile).
    public var item: Int
    /// The name shown on the device until the instrument has sent one.
    public var name: String

    /// Makes a control.
    public init(controller: Int, item: Int, name: String) {
        self.controller = controller
        self.item = item
        self.name = name
    }
}

/// An Arturia instrument as one macro plugin of two pages on the Roto-Control.
///
/// The driver is pure: no I/O, and the time is passed in (seconds, from any fixed start). Feed it
/// the bytes the instrument sends to the virtual port, what the Roto-Control sends, and a `tick`
/// every 20 ms or so, and send what each call returns. It sends the device nothing while the
/// device is not in PLUGIN mode.
///
/// An item's value is unknown until the instrument reports it or the user turns its knob, since
/// no way to ask an instrument for its values is known (docs/ARTURIA.md, section 4). Until then
/// the control's name ends in "?" and its knob is sent no position. (LEARN PARAM has to carry
/// one, and carries 0; whether that moves the knob is untested.)
///
/// Under the KeyLab mkII's profile (the default) the instrument answers a control change with the
/// control's name and its value in words (`ArturiaControlText`). The driver then shows that name
/// in place of its own, and the instrument's value text in place of a percentage. A name is kept
/// across presets for an instrument in `fixedNameInstruments`, and dropped at a preset change for
/// any other, since Analog Lab V names controls by preset. A name is known only once its knob has been turned: no instrument has been
/// seen to send the names otherwise (docs/ARTURIA.md, tests 4 and 6).
public struct ArturiaRotoDriver: Sendable {
    /// The pages, by control change number and the name shown until the instrument sends one: the
    /// first is macros 1–4 and four parameters of the instrument's own, in the order of their
    /// control change numbers in the profile file; the second is the volume alone. `nil` is a
    /// knob with no control.
    public static let layout: [[(controller: Int, name: String)?]] = [
        [(74, "Macro 1"), (71, "Macro 2"), (76, "Macro 3"), (77, "Macro 4"),
         (93, "Param 1"), (18, "Param 2"), (19, "Param 3"), (16, "Param 4")],
        [(17, "Volume"), nil, nil, nil, nil, nil, nil, nil],
    ]
    /// How long after a knob is turned the driver waits for the instrument's value text before
    /// showing a percentage instead, once the instrument has sent any (it has been seen to answer
    /// in about 30 ms; test 4).
    public static let textWaitSeconds: TimeInterval = 0.2

    /// The instruments, by the name their text sends in field 1, whose control names are the same in
    /// every preset: Pigments (test A7: its names are its parameters' fixed names). Analog Lab V
    /// sends the name of each preset's own instrument there, which is not in the set, so its
    /// per-preset labels are dropped at each preset change, as are any unknown instrument's.
    public static let fixedNameInstruments: Set<String> = ["Pigments"]

    /// The controller profile the instrument is talking to.
    public let profile: ArturiaKeyLabProfile
    /// The pages: `layout` with the profile's item numbers.
    public let pages: [[ArturiaRotoControl?]]
    /// The plugin's name until the instrument has sent its own.
    public static let defaultPluginName = "Arturia"
    /// How long after a knob's last report a value from the instrument is kept from moving it.
    public static let holdSeconds: TimeInterval = 0.25
    /// The shortest time between two SHOW CONTROL VALUE messages for one knob: 12 a second.
    public static let valueTextInterval: TimeInterval = 1.0 / 12.0

    /// Whether LEARN PARAM is sent only in answer to CONTROL MAPPED, not unasked. `true` is the
    /// order of Bitwig's integration, per its code: on SET PLUGIN MODE it sends the plugin list
    /// and the selection but no LEARN PARAM. `false`, LEARN PARAM unasked, is this project's own
    /// variant.
    public let waitsForControlMapped: Bool
    /// Whether the Roto-Control is in PLUGIN mode, by what it last sent.
    public private(set) var isInPluginMode = false
    /// The macro page shown (0 or 1).
    public private(set) var page = 0
    /// The plugin's name on the device: the instrument's, cut to 12 characters.
    public private(set) var pluginName = ArturiaRotoDriver.defaultPluginName
    /// The instrument's name as its text last sent it, uncut. From Analog Lab V this is the
    /// instrument the preset comes from.
    public private(set) var instrumentName: String?
    /// The third field of the instrument's last text: the preset's subtype or type.
    public private(set) var presetKind: String?
    /// Whether the instrument has lit one of the lights only Analog Lab V has been seen to light
    /// (its three control tabs, items 31–33: docs/ARTURIA.md, tests 4 and 7). Kept until the
    /// driver is made again.
    public private(set) var hostIsAnalogLab = false
    /// Names for controls read from the instrument's own files, by item: shown until the
    /// instrument sends a name of its own.
    private var parameterNames: [Int: String] = [:]
    /// The loaded preset's labels for the four macros, by item, read from its file.
    private var presetLabels: [Int: String] = [:]
    /// The preset's name, without its leading asterisk, once the instrument has sent it.
    public private(set) var presetName: String?

    /// Each item's value (0–127): the last the instrument reported or the driver sent it.
    private var values: [Int: Int] = [:]
    private var assembler = ArturiaSysExAssembler()
    /// For each knob of the page, the 7-bit value it stands at: from its last report, or from the
    /// last position sent to it.
    private var knobValue = [Int?](repeating: nil, count: 8)
    private var lastKnobMove = [TimeInterval?](repeating: nil, count: 8)
    /// Knobs with a value from the instrument waiting for the hold to end.
    private var heldBack = [Bool](repeating: false, count: 8)
    private var lastValueText = [TimeInterval?](repeating: nil, count: 8)
    private var valueTextPending = [Bool](repeating: false, count: 8)
    private var lastTrackNameSent: String?
    /// Each item's name as the instrument last sent it, for the preset shown.
    private var names: [Int: String] = [:]
    /// Each item's value text as the instrument last sent it, with the value it was for.
    private var instrumentText: [Int: (value: Int, text: String)] = [:]
    /// Whether the instrument has sent any control text, which makes the driver wait for it.
    public private(set) var instrumentSendsText = false
    /// For each knob, when it was turned, while the driver waits for the instrument's value text.
    private var awaitingText = [TimeInterval?](repeating: nil, count: 8)
    /// For each knob, the value text last shown.
    private var shownText = [String?](repeating: nil, count: 8)
    /// For each knob, the name the device was last told, or `nil` if none since the page was set.
    private var sentNames = [String?](repeating: nil, count: 8)

    /// Notes the names `output` tells the device, and adds a rename for every knob whose shown
    /// name now differs from what the device was last told: fitting names as a set can change
    /// one name when another does.
    private mutating func finish(_ output: ArturiaRotoOutput) -> ArturiaRotoOutput {
        var output = output
        for message in output.toDevice {
            switch message {
            case .message(.learnParameter(let details)) where (1...8).contains(details.index):
                sentNames[details.index - 1] = details.name
            case .message(.mappedControlName(let index, _, let name)) where (1...8).contains(index):
                sentNames[index - 1] = name
            default:
                break
            }
        }
        guard isInPluginMode else { return output }
        let shown = shownNames
        for knob in 0..<8 {
            guard let control = control(knob), let sent = sentNames[knob], let name = shown[knob], name != sent else { continue }
            output.toDevice.append(renamed(knob, control))
            sentNames[knob] = name
        }
        return output
    }
    /// The control changes lately sent to the instrument, by the driver or by a relayed keyboard,
    /// newest last: the mk3's control screen does not say which control it is about, so it is
    /// taken for the newest of these with its value.
    private var recentChanges: [(controller: Int, value: Int, time: TimeInterval)] = []
    /// The id the instrument's mk3 messages carry.
    private var instrumentID = ArturiaMk3Message.instrumentID

    /// Whether the driver asks the instrument for the names of knobs it has none for, by sending
    /// each such knob's known value again, as a KeyLab mk3 does when a knob is touched
    /// (docs/ARTURIA.md, test 8). The instrument then takes the value, which has been seen to
    /// move a parameter by up to one 7-bit step and mark the preset as changed; so a host turns
    /// this off for an instrument whose names it reads from files (Adam, 2026-11-14).
    public var asksForNames = true
    /// How long after the page, the preset, or a value changes the asking starts.
    public static let askDelaySeconds: TimeInterval = 0.3
    /// How long an answer is waited for before the next knob is asked.
    public static let askTimeoutSeconds: TimeInterval = 0.4
    private var askDue: TimeInterval?
    /// The items asked since the asking was last set off.
    private var asked: Set<Int> = []
    /// The item being asked, and when.
    private var asking: (item: Int, since: TimeInterval)?
    /// When each item was last asked, so that its answer's value text is not shown.
    private var askedAt: [Int: TimeInterval] = [:]
    /// The last control screen in the mk3's format, and when: the instrument sends each three
    /// times within about 0.1 s, and a copy must not be taken for the answer to the next question
    /// (seen in test A12).
    private var lastScreen: (screen: ArturiaMk3Message, time: TimeInterval)?
    /// How long after an answer the next knob is asked, so that the answer's copies have come.
    public static let askGapSeconds: TimeInterval = 0.2

    /// Sets the asking off again, a moment from now.
    private mutating func askSoon(_ now: TimeInterval) {
        asked = []
        askDue = now + Self.askDelaySeconds
    }

    /// Makes a driver for an instrument talking to `profile`. With `waitsForControlMapped`, the
    /// controls are described only when the device asks with CONTROL MAPPED, which is the order of
    /// Bitwig's integration; without it they are sent unasked, this project's own variant (test
    /// R1 and test 2 ran with `true`).
    public init(profile: ArturiaKeyLabProfile = .keyLabMkII, waitsForControlMapped: Bool = false) {
        self.profile = profile
        self.waitsForControlMapped = waitsForControlMapped
        pages = Self.layout.map { page in
            page.map { entry in
                entry.flatMap { entry in
                    profile.item(forController: entry.controller).map {
                        ArturiaRotoControl(controller: entry.controller, item: $0, name: entry.name)
                    }
                }
            }
        }
    }

    /// The name the instrument last sent for an item, for the preset shown, or `nil`.
    public func name(forItem item: Int) -> String? { names[item] }

    /// The value (0–127) known for an item, or `nil` while it is unknown.
    public func value(forItem item: Int) -> Int? { values[item] }

    // MARK: Scaling

    /// The knob position (0–16383) for an instrument's 7-bit value: value × 16383 ÷ 127, rounded.
    public static func position(forValue value: Int) -> Int {
        let clamped = min(max(value, 0), 127)
        return (clamped * RotoSysEx.maximum14Bit * 2 + 127) / (127 * 2)
    }

    /// The 7-bit value for a knob position: position × 127 ÷ 16383, rounded.
    public static func value(forPosition position: Int) -> Int {
        let clamped = min(max(position, 0), RotoSysEx.maximum14Bit)
        return (clamped * 127 * 2 + RotoSysEx.maximum14Bit) / (RotoSysEx.maximum14Bit * 2)
    }

    /// The text SHOW CONTROL VALUE carries for a 7-bit value when the instrument has sent none for
    /// it: a percentage, e.g., "58%".
    public static func valueText(_ value: Int) -> String {
        let clamped = min(max(value, 0), 127)
        let percent: Int = (clamped * 200 + 127) / 254
        return "\(percent)%"
    }

    // MARK: The page

    private func control(_ knob: Int) -> ArturiaRotoControl? {
        (0..<8).contains(knob) ? pages[page][knob] : nil
    }

    private func knob(forItem item: Int) -> Int? {
        pages[page].firstIndex { $0?.item == item }
    }

    /// A control's name before it is fitted. In order: the name the instrument sent, unless it is
    /// only the driver's own default (Pigments sends "Macro 1" for a macro its preset labels
    /// "Timbre"); the preset's label from its file; the name the instrument sent; the parameter's
    /// name from the instrument's files; the default.
    private func fullName(_ control: ArturiaRotoControl) -> String {
        let sent = names[control.item]
        let informative = sent == control.name ? nil : sent
        return informative ?? presetLabels[control.item] ?? sent ?? parameterNames[control.item] ?? control.name
    }

    /// The page's names as shown: fitted to the device's 12 characters as a set (`RotoNameFit`),
    /// with a trailing "?" while a value is unknown.
    private var shownNames: [String?] {
        let controls = (0..<8).map(control)
        let unknown = controls.map { $0.map { values[$0.item] == nil } ?? false }
        let limit = RotoSysEx.nameFieldLength - 1
        let fitted = RotoNameFit.fit(controls.map { $0.map(fullName) ?? "" }, to: unknown.map { $0 ? limit - 1 : limit })
        return (0..<8).map { controls[$0] == nil ? nil : fitted[$0] + (unknown[$0] ? "?" : "") }
    }

    /// A control's name as shown.
    private func shownName(_ control: ArturiaRotoControl) -> String {
        if let knob = knob(forItem: control.item), let name = shownNames[knob] { return name }
        return RotoNameFit.fit(fullName(control))
    }

    /// The value text for an item at its current value: the instrument's, if it sent one for this
    /// value, otherwise a percentage.
    private func currentValueText(item: Int) -> String? {
        guard let value = values[item] else { return nil }
        if let sent = instrumentText[item], sent.value == value { return sent.text }
        return Self.valueText(value)
    }

    /// LEARN PARAM for a knob of the page: macro number knob + 1, as Bitwig's integration numbers
    /// its macros. The message has to carry a position, so it carries 0 while the value is
    /// unknown; whether that moves the knob is untested.
    private func learn(_ knob: Int, _ control: ArturiaRotoControl) -> ArturiaRotoDeviceMessage {
        .message(.learnParameter(.macro(knob + 1, name: shownName(control),
                                        position: Self.position(forValue: values[control.item] ?? 0))))
    }

    /// NUM PLUGINS, FIRST PLUGIN, PLUGIN DETAILS, and PLUGIN DETAILS END for the one plugin, then
    /// DAW SELECT PLUGIN for it with the macro page shown. Bitwig's integration always follows
    /// its macro plugin's list with the selection, per its code, and sets the force byte only
    /// while its plugin lock is on, so it is off here.
    private var pluginList: [ArturiaRotoDeviceMessage] {
        [.message(.pluginCount(1)), .message(.firstPlugin(0)),
         .message(.pluginDetails(.macro(index: 0, name: pluginName, pages: pages.count))),
         .message(.pluginDetailsEnd),
         .message(.dawSelectPlugin(index: 0, macroPage: page, force: false))]
    }

    /// The page's LEARN PARAM messages, then the knob positions of the controls whose values are
    /// known. A control whose value is unknown gets no knob position, and the position its knob
    /// stands at stays unknown, so that the first value reported moves it, 0 included. Its LEARN
    /// PARAM still carries position 0; whether that moves the knob is untested. Knobs without a
    /// control get nothing (a guess: whether the device then shows them empty on the second page
    /// is untested).
    private mutating func pageControls() -> [ArturiaRotoDeviceMessage] {
        var learns: [ArturiaRotoDeviceMessage] = []
        var knobs: [ArturiaRotoDeviceMessage] = []
        for knob in 0..<8 {
            guard let control = control(knob) else { continue }
            learns.append(learn(knob, control))
            guard let value = values[control.item] else { continue }
            knobs.append(.knob(knob, position: Self.position(forValue: value)))
            knobValue[knob] = value
        }
        return learns + knobs
    }

    private mutating func resetKnobState() {
        knobValue = [Int?](repeating: nil, count: 8)
        lastKnobMove = [TimeInterval?](repeating: nil, count: 8)
        heldBack = [Bool](repeating: false, count: 8)
        lastValueText = [TimeInterval?](repeating: nil, count: 8)
        valueTextPending = [Bool](repeating: false, count: 8)
        awaitingText = [TimeInterval?](repeating: nil, count: 8)
        shownText = [String?](repeating: nil, count: 8)
        sentNames = [String?](repeating: nil, count: 8)
    }

    /// SHOW CONTROL VALUE for a knob now, or a note to send it at a later `tick`, so that a knob
    /// gets at most 12 a second and the last value is always shown.
    /// An identical text is not sent again (the instrument sends each of its texts three times).
    private mutating func valueText(_ knob: Int, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        guard let control = control(knob), let text = currentValueText(item: control.item) else { return [] }
        if text == shownText[knob], !valueTextPending[knob] { return [] }
        if let last = lastValueText[knob], now - last < Self.valueTextInterval {
            valueTextPending[knob] = true
            return []
        }
        lastValueText[knob] = now
        valueTextPending[knob] = false
        shownText[knob] = text
        return [.message(.showValue(.knob, control: knob, text: text))]
    }

    /// SET MAPPED CONTROL NAME with a control's name as now shown, for a control whose value has
    /// just become known or whose name has changed. (The driver's choice over LEARN PARAM again,
    /// which also carries a position and so could move a knob the user is turning.)
    private func renamed(_ knob: Int, _ control: ArturiaRotoControl) -> ArturiaRotoDeviceMessage {
        .message(.mappedControlName(parameterIndex: knob + 1, hash: .macroParameter(knob + 1), name: shownName(control)))
    }

    // MARK: Names from files

    /// The knobs of the page whose shown name differs from `before`, renamed.
    private func renames(since before: [String?]) -> [ArturiaRotoDeviceMessage] {
        guard isInPluginMode else { return [] }
        return (0..<8).compactMap { knob in
            guard let control = control(knob), shownName(control) != before[knob] else { return nil }
            return renamed(knob, control)
        }
    }

    /// Sets names for controls read from the instrument's own files, by control change number
    /// (`ArturiaParameterFiles.names`). They show until the instrument sends a name of its own.
    public mutating func setParameterNames(_ names: [Int: String]) -> ArturiaRotoOutput {
        let before = shownNames
        parameterNames = [:]
        for (controller, name) in names {
            if let item = profile.item(forController: controller) { parameterNames[item] = name }
        }
        return finish(ArturiaRotoOutput(toDevice: renames(since: before)))
    }

    /// Sets the loaded preset's labels for macros 1–4, read from its file
    /// (`ArturiaPresetMatch.macroLabels`), or none with `nil`. They are dropped when the
    /// instrument's text names another preset.
    public mutating func setPresetLabels(_ labels: [String?]?) -> ArturiaRotoOutput {
        let before = shownNames
        presetLabels = [:]
        for (index, controller) in [74, 71, 76, 77].enumerated() {
            guard let labels, index < labels.count, let label = labels[index], !label.isEmpty,
                  let item = profile.item(forController: controller) else { continue }
            presetLabels[item] = label
        }
        return finish(ArturiaRotoOutput(toDevice: renames(since: before)))
    }

    /// The macros' values (0–127) and the volume's as last known, for choosing a preset file.
    public var presetValues: (macros: [Int?], volume: Int?) {
        func value(_ controller: Int) -> Int? { profile.item(forController: controller).flatMap { values[$0] } }
        return ([74, 71, 76, 77].map(value), value(17))
    }

    // MARK: From the instrument

    /// Takes bytes the instrument sent to the virtual port.
    public mutating func fromInstrument<S: Sequence>(_ bytes: S, now: TimeInterval) -> ArturiaRotoOutput where S.Element == UInt8 {
        var output = ArturiaRotoOutput()
        for message in assembler.feed(bytes) {
            if profile.messageFormat == .version3 {
                output.toDevice += mk3Message(message, now: now)
                continue
            }
            switch ArturiaInstrumentMessage.parse(message) {
            case .value(let item, let value)?:
                output.toDevice += instrumentValue(item: item, value: min(max(value, 0), 127), now: now)
            case .text(let fields)?:
                output.toDevice += instrumentText(fields, now: now)
            case .controlText(let text)?:
                output.toDevice += controlText(text, now: now)
            case .light(let item, _)? where (31...33).contains(item):
                hostIsAnalogLab = true
            default:
                break
            }
        }
        return finish(output)
    }

    /// The instruments by the number in their preset screen (`ArturiaMk3Message.preset`), each
    /// seen in one preset: the mk3's format does not name the instrument otherwise.
    public static let instrumentsByPicture: [Int: String] = [45: "Pigments", 22: "Augmented VOICES", 59: "Memory"]

    /// One message in the mk3's format.
    private mutating func mk3Message(_ message: [UInt8], now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        switch ArturiaMk3Message.parse(message) {
        case .connect(_, let id)?:
            instrumentID = id
            if id == ArturiaMk3Message.analogLabID { hostIsAnalogLab = true }
            return []
        case .property(let item, 1, let value, let id)?:
            instrumentID = id
            return instrumentValue(item: item, value: min(max(value, 0), 127), now: now)
        case .property(_, 2, _, _)?:
            hostIsAnalogLab = true
            return []
        case .preset(let name, _, let kind, let picture, let id)?:
            instrumentID = id
            if id == ArturiaMk3Message.analogLabID { hostIsAnalogLab = true }
            // Analog Lab V's picture is its preset's instrument's, which is not the program here.
            let instrument = hostIsAnalogLab ? "Analog Lab" : picture.flatMap { Self.instrumentsByPicture[$0] } ?? Self.defaultPluginName
            return presetInfo(instrument: instrument, preset: name, kind: kind, now: now)
        case .controlScreen(let valueText, let name, let value, _)?:
            let screen = ArturiaMk3Message.controlScreen(valueText: valueText, name: name, value: value, id: 0)
            if let last = lastScreen, last.screen == screen, now - last.time < 0.25 { return [] }
            lastScreen = (screen, now)
            // Which control: the newest control change sent with this value in the last second.
            let since = now - 1
            guard let change = recentChanges.last(where: { $0.time >= since && (value == nil || $0.value == value) }) else { return [] }
            return controlText(ArturiaControlText(name: name, valueText: valueText, controller: change.controller, value: change.value), now: now)
        default:
            return []
        }
    }

    /// Notes a control change sent to the instrument, for `mk3Message`.
    private mutating func noteChange(controller: Int, value: Int, now: TimeInterval) {
        recentChanges.append((controller, value, now))
        if recentChanges.count > 16 { recentChanges.removeFirst(recentChanges.count - 16) }
    }

    /// With `awaitsText`, the value text waits for the instrument's own (as after a turn of the
    /// Roto-Control's knob), rather than showing a percentage meanwhile (seen in test A11).
    private mutating func instrumentValue(item: Int, value: Int, now: TimeInterval, awaitsText: Bool = false) -> [ArturiaRotoDeviceMessage] {
        let wasUnknown = values[item] == nil
        if wasUnknown, names[item] == nil { askSoon(now) }
        values[item] = value
        guard isInPluginMode, let knob = knob(forItem: item), let control = control(knob) else { return [] }
        var messages: [ArturiaRotoDeviceMessage] = []
        if wasUnknown { messages.append(renamed(knob, control)) }
        if let moved = lastKnobMove[knob], now - moved < Self.holdSeconds {
            // The user is turning this knob: the value waits for `tick`.
            heldBack[knob] = true
        } else if knobValue[knob] != value {
            messages.append(.knob(knob, position: Self.position(forValue: value)))
            knobValue[knob] = value
        }
        if awaitsText {
            awaitingText[knob] = now
            return messages
        }
        return messages + valueText(knob, now: now)
    }

    private mutating func instrumentText(_ fields: [ArturiaTextField], now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        let instrument = fields.first(where: { $0.tag == 1 })?.text
        guard let preset = fields.first(where: { $0.tag == 2 })?.text else {
            return presetInfo(instrument: instrument, preset: nil, kind: nil, now: now)
        }
        // The asterisk before the name has been seen on every preset in this format; in the mk3's
        // it follows the name once the preset has been changed.
        return presetInfo(instrument: instrument, preset: preset.hasPrefix("*") ? String(preset.dropFirst()) : preset,
                          kind: fields.first(where: { $0.tag == 3 })?.text, now: now)
    }

    /// The instrument's and the preset's names, from either format's text.
    private mutating func presetInfo(instrument: String?, preset: String?, kind: String?, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        var messages: [ArturiaRotoDeviceMessage] = []
        if let name = instrument, !name.isEmpty {
            instrumentName = name
            let cut = String(name.prefix(RotoSysEx.nameFieldLength - 1))
            if cut != pluginName {
                pluginName = cut
                if isInPluginMode { messages += pluginList }
            }
        }
        if let name = preset {
            if let previous = presetName, previous != name || presetKind != kind {
                let before = shownNames
                presetLabels = [:]
                if hostIsAnalogLab || !Self.fixedNameInstruments.contains(instrumentName ?? "") {
                    names = [:]
                    instrumentText = [:]
                }
                messages += renames(since: before)
                askSoon(now)
            }
            presetName = name
            presetKind = kind
            if isInPluginMode { messages += trackName(onlyIfChanged: true) }
        }
        return messages
    }

    /// A control's name and value text from the instrument, after a control change from the driver
    /// (or from anything else on the port).
    private mutating func controlText(_ text: ArturiaControlText, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        instrumentSendsText = true
        guard let item = profile.item(forController: text.controller) else { return [] }
        let value = min(max(text.value, 0), 127)
        // Whether the name shown changes: a name that is only the default changes nothing.
        let shownBefore = knob(forItem: item).flatMap { control($0) }.map(shownName)
        if !text.name.isEmpty { names[item] = text.name }
        let nameChanged = knob(forItem: item).flatMap { control($0) }.map(shownName) != shownBefore
        if !text.valueText.isEmpty { instrumentText[item] = (value, text.valueText) }
        // A newer control change for this control has gone to the instrument since the one this
        // answers (a relayed keyboard's knob turning: seen in test A11, where late answers moved
        // the Roto-Control's knob back a step and forward again).
        let isStale = recentChanges.last(where: { $0.controller == text.controller }).map { $0.value != value } ?? false
        if values[item] != value, isStale {
            if asking?.item == item { asking = nil }
            guard isInPluginMode, let knob = knob(forItem: item), let control = control(knob) else { return [] }
            return nameChanged ? [renamed(knob, control)] : []
        }
        if values[item] != value {
            if isInPluginMode, let knob = knob(forItem: item), let control = control(knob),
               let moved = lastKnobMove[knob], now - moved < Self.holdSeconds {
                // A late answer to an earlier step of a knob still being turned (the instrument
                // has been seen to answer up to about 50 ms behind: test A7): its name is kept,
                // its value is not, so the knob isn't moved back when it is let go.
                return nameChanged ? [renamed(knob, control)] : []
            }
            // A control change the driver didn't send: handled as a value report, which renames a
            // knob whose value was unknown and shows the text.
            let wasUnknown = values[item] == nil
            var messages = instrumentValue(item: item, value: value, now: now)
            if nameChanged, !wasUnknown, isInPluginMode, let knob = knob(forItem: item), let control = control(knob) {
                messages.insert(renamed(knob, control), at: 0)
            }
            return messages
        }
        if asking?.item == item {
            asking = nil
            if let due = askDue { askDue = max(due, now + Self.askGapSeconds) }
        }
        guard isInPluginMode, let knob = knob(forItem: item), let control = control(knob) else { return [] }
        awaitingText[knob] = nil
        // An answer to the driver's own asking shows no value text: nothing was turned.
        let wasAsked = askedAt[item].map { now - $0 < 0.5 } ?? false
        return (nameChanged ? [renamed(knob, control)] : []) + (wasAsked ? [] : valueText(knob, now: now))
    }

    /// SET CURRENT TRACK NAME with the preset's name, for the MENU window's bottom line. It showed
    /// there, cut to 12 characters, in the three runs of docs/ARTURIA.md, test 7, and not in test
    /// 2, for reasons not known.
    private mutating func trackName(onlyIfChanged: Bool) -> [ArturiaRotoDeviceMessage] {
        guard let name = presetName, !(onlyIfChanged && name == lastTrackNameSent) else { return [] }
        lastTrackNameSent = name
        return [.message(.currentTrackName(name))]
    }

    // MARK: From the Roto-Control

    /// Takes one message or control from the Roto-Control. Switches, touches, and every message
    /// that is not PLUGIN mode's are left alone.
    public mutating func fromDevice(_ input: RotoInput, now: TimeInterval) -> ArturiaRotoOutput {
        switch input {
        case .message(let message):
            return finish(ArturiaRotoOutput(toDevice: deviceMessage(message, now: now)))
        case .control(.knob(let knob, let position)):
            return finish(knobMoved(knob, position: position, now: now))
        case .control:
            return ArturiaRotoOutput()
        }
    }

    private mutating func deviceMessage(_ message: RotoIncoming, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        switch message {
        case .pluginMode:
            isInPluginMode = true
            resetKnobState()
            askSoon(now)
            var messages = pluginList
            messages += trackName(onlyIfChanged: false)
            // Unasked LEARN PARAM is this project's own variant: Bitwig's integration sends none
            // on SET PLUGIN MODE, only after CONTROL MAPPED.
            if !waitsForControlMapped { messages += pageControls() }
            return messages
        case .allTracksMode, .singleTrackMode:
            isInPluginMode = false
            resetKnobState()
            return []
        default:
            break
        }
        guard isInPluginMode else { return [] }
        switch message {
        case .macroPage(let index):
            page = min(max(index, 0), pages.count - 1)
            resetKnobState()
            askSoon(now)
            return waitsForControlMapped ? [] : pageControls()
        case .controlMapped(let mapping):
            // A macro is found by its number (1–8), as Bitwig's integration finds it.
            let knob = mapping.parameterIndex - 1
            guard let control = control(knob) else { return [] }
            // LEARN PARAM carries the position, taken here to move the knob when the value is
            // known (untested). An unknown value leaves the knob's position unknown.
            if let value = values[control.item] { knobValue[knob] = value }
            return [learn(knob, control)]
        case .setFirstPlugin(0):
            // A guess: one plugin has one page of plugins, so the list is sent again for it, with
            // the selection after it.
            return pluginList
        case .selectPlugin(0):
            // A guess: the device selected the plugin itself, so only the controls are sent.
            return waitsForControlMapped ? [] : pageControls()
        default:
            return []
        }
    }

    private mutating func knobMoved(_ knob: Int, position: Int, now: TimeInterval) -> ArturiaRotoOutput {
        guard isInPluginMode, let control = control(knob) else { return ArturiaRotoOutput() }
        lastKnobMove[knob] = now
        let value = Self.value(forPosition: position)
        knobValue[knob] = value
        guard values[control.item] != value,
              let change = profile.controlChange(item: control.item, value: value) else {
            return ArturiaRotoOutput()
        }
        let wasUnknown = values[control.item] == nil
        values[control.item] = value
        // The knob's own value is newer than one the instrument sent during the hold.
        heldBack[knob] = false
        var messages: [ArturiaRotoDeviceMessage] = wasUnknown ? [renamed(knob, control)] : []
        if instrumentSendsText {
            // The instrument's own text for the new value is expected shortly.
            awaitingText[knob] = now
        } else {
            messages += valueText(knob, now: now)
        }
        noteChange(controller: control.controller, value: value, now: now)
        var output = ArturiaRotoOutput(toDevice: messages, toInstrument: [change])
        if profile.messageFormat == .version3 {
            output.toKeyboard = [ArturiaMk3Message.knobValue(item: control.item, value: value, id: instrumentID)]
        }
        return output
    }

    // MARK: From a relayed keyboard

    /// Takes bytes a real keyboard sent, which the host has passed on to the instrument: a control
    /// change for one of the profile's controls is a new value, which moves the Roto-Control's
    /// knob (the instrument reports no value for a change a controller makes), and the instrument
    /// will answer it with the control's name and value text.
    public mutating func fromKeyboard<S: Sequence>(_ bytes: S, now: TimeInterval) -> ArturiaRotoOutput where S.Element == UInt8 {
        let bytes = Array(bytes)
        var messages: [ArturiaRotoDeviceMessage] = []
        var index = 0
        while index + 2 < bytes.count {
            // Channel 1, as the instruments' configurations assign; anything else is skipped.
            guard bytes[index] == 0xB0, bytes[index + 1] < 0x80, bytes[index + 2] < 0x80 else { index += 1; continue }
            let controller = Int(bytes[index + 1]), value = Int(bytes[index + 2])
            index += 3
            guard let item = profile.item(forController: controller) else { continue }
            noteChange(controller: controller, value: value, now: now)
            messages += instrumentValue(item: item, value: value, now: now, awaitsText: instrumentSendsText)
        }
        return finish(ArturiaRotoOutput(toDevice: messages))
    }

    // MARK: Time

    /// Sends what was waiting: a value held back while its knob was being turned, once the hold
    /// has ended and if it still differs from what the knob last reported; a value text held back
    /// by the limit of 12 a second; and a percentage for a knob whose value text the instrument
    /// has not sent within `textWaitSeconds`.
    public mutating func tick(now: TimeInterval) -> ArturiaRotoOutput {
        guard isInPluginMode else { return ArturiaRotoOutput() }
        var output = ArturiaRotoOutput(toDevice: heldMessages(now: now))
        output.toInstrument = ask(now: now)
        return finish(output)
    }

    /// Asks the instrument for the name of the next knob of the page that has a value and no name
    /// from the instrument, by sending its value again; one knob at a time, since the mk3's
    /// answer does not say which knob it is about. Waits while a knob is being turned.
    private mutating func ask(now: TimeInterval) -> [[UInt8]] {
        if let waiting = asking {
            guard now - waiting.since >= Self.askTimeoutSeconds else { return [] }
            asking = nil
        }
        guard asksForNames, let due = askDue, now >= due else { return [] }
        guard !lastKnobMove.contains(where: { $0.map { now - $0 < 2 * Self.holdSeconds } ?? false }) else { return [] }
        for knob in 0..<8 {
            guard let control = control(knob), !asked.contains(control.item), names[control.item] == nil,
                  let value = values[control.item], let change = profile.controlChange(item: control.item, value: value) else { continue }
            asked.insert(control.item)
            asking = (control.item, now)
            askedAt[control.item] = now
            noteChange(controller: control.controller, value: value, now: now)
            return [change]
        }
        askDue = nil
        return []
    }

    private mutating func heldMessages(now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        var messages: [ArturiaRotoDeviceMessage] = []
        for knob in 0..<8 {
            guard let control = control(knob), let value = values[control.item] else { continue }
            if heldBack[knob], let moved = lastKnobMove[knob], now - moved >= Self.holdSeconds {
                heldBack[knob] = false
                if knobValue[knob] != value {
                    messages.append(.knob(knob, position: Self.position(forValue: value)))
                    knobValue[knob] = value
                }
            }
            if let turned = awaitingText[knob] {
                // While the instrument's text is awaited, a held-back text waits too, or it would
                // show a percentage for a moment (seen in test A7).
                if now - turned >= Self.textWaitSeconds {
                    awaitingText[knob] = nil
                    messages += valueText(knob, now: now)
                }
            } else if valueTextPending[knob], let last = lastValueText[knob], now - last >= Self.valueTextInterval {
                messages += valueText(knob, now: now)
            }
        }
        return messages
    }
}
