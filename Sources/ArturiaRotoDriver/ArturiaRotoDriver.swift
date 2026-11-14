import Foundation
#if canImport(RotoControl)
import RotoControl
#endif
#if canImport(ArturiaControl)
import ArturiaControl
#endif

// A prototype driver that shows a standalone Arturia instrument on the Roto-Control's PLUGIN mode
// as one macro plugin (docs/PLUGIN-MODE-PLAN.md, section 6). The instrument's side rests on
// docs/ARTURIA.md (one test, with Pigments); the Roto-Control's side on a reading of Melbourne
// Instruments' Bitwig integration, which test R1 is to check. Nothing here has been tested on a
// device or with an instrument.

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

    /// Makes an output.
    public init(toDevice: [ArturiaRotoDeviceMessage] = [], toInstrument: [[UInt8]] = []) {
        self.toDevice = toDevice
        self.toInstrument = toInstrument
    }

    /// Whether there is nothing to send.
    public var isEmpty: Bool { toDevice.isEmpty && toInstrument.isEmpty }
}

/// One knob of a page: the instrument's item it controls, and its name on the device.
public struct ArturiaRotoControl: Equatable, Sendable {
    /// The item number the instrument reports the control under (`ArturiaKeyLabProfile`).
    public var item: Int
    /// The name shown on the device once the value is known.
    public var name: String

    /// Makes a control.
    public init(item: Int, name: String) {
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
public struct ArturiaRotoDriver: Sendable {
    /// The pages: the first is macros 1–4 and the instrument's four own parameters (items 9, 5, 6,
    /// and 7, in the order of their control change numbers in the profile); the second is the
    /// volume alone. `nil` is a knob with no control. The parameters' real names differ by
    /// instrument and are not known to the driver.
    public static let pages: [[ArturiaRotoControl?]] = [
        [ArturiaRotoControl(item: 1, name: "Macro 1"), ArturiaRotoControl(item: 2, name: "Macro 2"),
         ArturiaRotoControl(item: 3, name: "Macro 3"), ArturiaRotoControl(item: 4, name: "Macro 4"),
         ArturiaRotoControl(item: 9, name: "Param 1"), ArturiaRotoControl(item: 5, name: "Param 2"),
         ArturiaRotoControl(item: 6, name: "Param 3"), ArturiaRotoControl(item: 7, name: "Param 4")],
        [ArturiaRotoControl(item: 8, name: "Volume"), nil, nil, nil, nil, nil, nil, nil],
    ]
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

    /// Makes a driver. With `waitsForControlMapped`, the controls are described only when the
    /// device asks with CONTROL MAPPED, which is the order of Bitwig's integration; without it
    /// they are sent unasked, this project's own variant. Whether the firmware takes the second
    /// is test R1's question, so try `true` first.
    public init(waitsForControlMapped: Bool = false) {
        self.waitsForControlMapped = waitsForControlMapped
    }

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

    /// The text SHOW CONTROL VALUE carries for a 7-bit value: a percentage, e.g., "58%". The
    /// instrument sends no value text, so this is the driver's own.
    public static func valueText(_ value: Int) -> String {
        let clamped = min(max(value, 0), 127)
        let percent: Int = (clamped * 200 + 127) / 254
        return "\(percent)%"
    }

    // MARK: The page

    private func control(_ knob: Int) -> ArturiaRotoControl? {
        (0..<8).contains(knob) ? Self.pages[page][knob] : nil
    }

    private func knob(forItem item: Int) -> Int? {
        Self.pages[page].firstIndex { $0?.item == item }
    }

    /// A control's name as shown: with a trailing "?" while its value is unknown.
    private func shownName(_ control: ArturiaRotoControl) -> String {
        values[control.item] == nil ? control.name + "?" : control.name
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
         .message(.pluginDetails(.macro(index: 0, name: pluginName, pages: Self.pages.count))),
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
    }

    /// SHOW CONTROL VALUE for a knob now, or a note to send it at a later `tick`, so that a knob
    /// gets at most 12 a second and the last value is always shown.
    private mutating func valueText(_ knob: Int, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        guard let control = control(knob), let value = values[control.item] else { return [] }
        if let last = lastValueText[knob], now - last < Self.valueTextInterval {
            valueTextPending[knob] = true
            return []
        }
        lastValueText[knob] = now
        valueTextPending[knob] = false
        return [.message(.showValue(.knob, control: knob, text: Self.valueText(value)))]
    }

    /// SET MAPPED CONTROL NAME with the name without its "?", for a control whose value has just
    /// become known. (The driver's choice over LEARN PARAM again, which also carries a position
    /// and so could move a knob the user is turning.)
    private func nameNowKnown(_ knob: Int, _ control: ArturiaRotoControl) -> ArturiaRotoDeviceMessage {
        .message(.mappedControlName(parameterIndex: knob + 1, hash: .macroParameter(knob + 1), name: control.name))
    }

    // MARK: From the instrument

    /// Takes bytes the instrument sent to the virtual port.
    public mutating func fromInstrument<S: Sequence>(_ bytes: S, now: TimeInterval) -> ArturiaRotoOutput where S.Element == UInt8 {
        var output = ArturiaRotoOutput()
        for message in assembler.feed(bytes) {
            switch ArturiaInstrumentMessage.parse(message) {
            case .value(let item, let value)?:
                output.toDevice += instrumentValue(item: item, value: min(max(value, 0), 127), now: now)
            case .text(let fields)?:
                output.toDevice += instrumentText(fields)
            default:
                break
            }
        }
        return output
    }

    private mutating func instrumentValue(item: Int, value: Int, now: TimeInterval) -> [ArturiaRotoDeviceMessage] {
        let wasUnknown = values[item] == nil
        values[item] = value
        guard isInPluginMode, let knob = knob(forItem: item), let control = control(knob) else { return [] }
        var messages: [ArturiaRotoDeviceMessage] = []
        if wasUnknown { messages.append(nameNowKnown(knob, control)) }
        if let moved = lastKnobMove[knob], now - moved < Self.holdSeconds {
            // The user is turning this knob: the value waits for `tick`.
            heldBack[knob] = true
        } else if knobValue[knob] != value {
            messages.append(.knob(knob, position: Self.position(forValue: value)))
            knobValue[knob] = value
        }
        return messages + valueText(knob, now: now)
    }

    private mutating func instrumentText(_ fields: [ArturiaTextField]) -> [ArturiaRotoDeviceMessage] {
        var messages: [ArturiaRotoDeviceMessage] = []
        if let name = fields.first(where: { $0.tag == 1 })?.text, !name.isEmpty {
            let cut = String(name.prefix(RotoSysEx.nameFieldLength - 1))
            if cut != pluginName {
                pluginName = cut
                if isInPluginMode { messages += pluginList }
            }
        }
        if let preset = fields.first(where: { $0.tag == 2 })?.text {
            // The asterisk before the name has been seen on a preset just loaded; what it means
            // is not known (docs/ARTURIA.md, section 3).
            presetName = preset.hasPrefix("*") ? String(preset.dropFirst()) : preset
            if isInPluginMode { messages += trackName(onlyIfChanged: true) }
        }
        return messages
    }

    /// SET CURRENT TRACK NAME with the preset's name. What the device shows for it in PLUGIN mode
    /// is untested.
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
            return ArturiaRotoOutput(toDevice: deviceMessage(message))
        case .control(.knob(let knob, let position)):
            return knobMoved(knob, position: position, now: now)
        case .control:
            return ArturiaRotoOutput()
        }
    }

    private mutating func deviceMessage(_ message: RotoIncoming) -> [ArturiaRotoDeviceMessage] {
        switch message {
        case .pluginMode:
            isInPluginMode = true
            resetKnobState()
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
            page = min(max(index, 0), Self.pages.count - 1)
            resetKnobState()
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
              let change = ArturiaKeyLabProfile.controlChange(item: control.item, value: value) else {
            return ArturiaRotoOutput()
        }
        let wasUnknown = values[control.item] == nil
        values[control.item] = value
        // The knob's own value is newer than one the instrument sent during the hold.
        heldBack[knob] = false
        var messages: [ArturiaRotoDeviceMessage] = wasUnknown ? [nameNowKnown(knob, control)] : []
        messages += valueText(knob, now: now)
        return ArturiaRotoOutput(toDevice: messages, toInstrument: [change])
    }

    // MARK: Time

    /// Sends what was waiting: a value held back while its knob was being turned, once the hold
    /// has ended and if it still differs from what the knob last reported; and a value text held
    /// back by the limit of 12 a second.
    public mutating func tick(now: TimeInterval) -> ArturiaRotoOutput {
        guard isInPluginMode else { return ArturiaRotoOutput() }
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
            if valueTextPending[knob], let last = lastValueText[knob], now - last >= Self.valueTextInterval {
                messages += valueText(knob, now: now)
            }
        }
        return ArturiaRotoOutput(toDevice: messages)
    }
}
