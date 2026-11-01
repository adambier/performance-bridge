// Messages to the Launch Control XL 3 in DAW mode, sent to its DAW port. Source: Novation's
// "Launch Control XL 3 programmer's reference guide", version 1.0 (April 2026): "DAW mode control",
// "Absolute and relative encoder modes", "Continuous control touch events", "Colouring the
// surface", "Controlling the screen", and "Launch Control XL 3 feature Controls". None of these
// has been checked on the device yet (docs/LAUNCH-CONTROL-XL3.md).

import Foundation

/// Where text on the Launch Control XL 3's screen goes ("Configure displays" in Novation's guide).
public enum LaunchControlDisplayTarget: Equatable, Sendable {
    /// The temporary display for a fader or an encoder, shown when it moves (its Control Change
    /// number, 5–36).
    case control(LaunchControlElement)
    /// The stationary display, shown when nothing else is (target 53).
    case stationary
    /// The overlay, a temporary display not tied to a control (target 54).
    case overlay

    /// The target's byte, or `nil` for a control that has no display (anything but a fader or an
    /// encoder).
    public var byte: UInt8? {
        switch self {
        case .control(let element): return element.isContinuous && element.isValid ? element.controlNumber : nil
        case .stationary: return 0x35
        case .overlay: return 0x36
        }
    }
}

/// How a display is laid out ("Display arrangements" in Novation's guide). Fields count from 0.
public enum LaunchControlArrangement: UInt8, Sendable, CaseIterable {
    /// Two lines: the parameter's name (field 0) and its value as text (field 1).
    case nameAndValue = 1
    /// Three lines: a title (field 0), the parameter's name (1), and its value as text (2).
    case titleNameAndValue = 2
    /// A title (field 0) and eight names in two rows of four (fields 1–8), for what the encoders do.
    case titleAndEightNames = 3
    /// Two lines: the parameter's name (field 0) and the device's own numeric value; the default.
    case nameAndNumber = 4

    /// How many text fields the arrangement has.
    public var fieldCount: Int {
        switch self {
        case .nameAndValue: return 2
        case .titleNameAndValue: return 3
        case .titleAndEightNames: return 9
        case .nameAndNumber: return 1
        }
    }
}

/// Builds the MIDI messages the Launch Control XL 3 takes in DAW mode. Each function returns the
/// bytes of one message, for the DAW port.
public enum LaunchControlOutgoing {
    /// The start of every SysEx message to or from the Launch Control XL 3: F0h, Novation's
    /// manufacturer ID (00h 20h 29h), and 02h 15h.
    public static let sysExHeader: [UInt8] = [0xF0, 0x00, 0x20, 0x29, 0x02, 0x15]

    /// Enters DAW mode (`true`) or returns to standalone mode (`false`): note 12 on channel 16,
    /// velocity 127 or 0. A host sends it on connecting and on quitting.
    public static func dawMode(_ on: Bool) -> [UInt8] {
        [0x9F, 0x0C, on ? 0x7F : 0x00]
    }

    /// The same as `dawMode(_:)`, as Novation's SysEx form (command 02h).
    public static func dawModeSysEx(_ on: Bool) -> [UInt8] {
        sysExHeader + [0x02, on ? 0x7F : 0x00, 0xF7]
    }

    /// Enables all feature controls (`true`), or returns to DAW mode's own set (`false`): note 11
    /// on channel 16. In DAW mode all of them listen already, so the inference is that this turns
    /// on their replies.
    public static func featureControls(_ on: Bool) -> [UInt8] {
        [0x9F, 0x0B, on ? 0x7F : 0x00]
    }

    /// A feature control (channel 7, Control Change `number`, `value`).
    public static func feature(_ number: UInt8, _ value: UInt8) -> [UInt8] {
        [0xB6, number & 0x7F, value & 0x7F]
    }

    /// Asks for a feature control's setting: the same Control Change on channel 8; the reply comes
    /// on channel 7. The guide gives no value for the question; 0 is an inference.
    public static func queryFeature(_ number: UInt8) -> [UInt8] {
        [0xB7, number & 0x7F, 0x00]
    }

    /// Selects a surface mode (feature control 30), or `nil` for a Custom Mode out of range.
    public static func selectMode(_ mode: LaunchControlMode) -> [UInt8]? {
        mode.value.map { feature(0x1E, $0) }
    }

    /// Switches an encoder row (0–2) to relative output, or back to absolute (feature controls 69,
    /// 72, and 73). In relative mode a row reports Control Changes 64 higher than its own.
    public static func relativeEncoders(row: Int, _ on: Bool) -> [UInt8]? {
        let numbers: [UInt8] = [0x45, 0x48, 0x49]
        guard numbers.indices.contains(row) else { return nil }
        return feature(numbers[row], on ? 0x7F : 0x00)
    }

    /// Turns "DAW Fader Pickup" on or off (feature control 70). The guide doesn't describe it; that
    /// a fader then changes nothing until it passes the value it controls is an inference from the
    /// user guide's pickup for Custom Modes.
    public static func faderPickup(_ on: Bool) -> [UInt8] {
        feature(0x46, on ? 0x7F : 0x00)
    }

    /// Turns touch reports on or off (feature control 71). They then come on channel 15 (see
    /// `LaunchControlEvent.touch`). Whether a "touch" is a touch sensor or Shift held while moving
    /// a control is open (docs/LAUNCH-CONTROL-XL3.md).
    public static func touchEvents(_ on: Bool) -> [UInt8] {
        feature(0x47, on ? 0x7F : 0x00)
    }

    /// The LED brightness (feature control 111), 0–127. Novation marks it as kept across power
    /// cycles.
    public static func ledBrightness(_ level: UInt8) -> [UInt8] {
        feature(0x6F, level)
    }

    /// The screen's brightness (feature control 112), 0–127; kept across power cycles.
    public static func screenBrightness(_ level: UInt8) -> [UInt8] {
        feature(0x70, level)
    }

    /// How long a temporary display stays (feature control 113), in tenths of a second, 0–99 (0 is
    /// one second); kept across power cycles.
    public static func displayTimeout(tenths: UInt8) -> [UInt8] {
        feature(0x71, min(tenths, 99))
    }

    /// Lights a control in one of the 128 palette colors (Control Change on channel 1, with the
    /// control's own number; for an encoder, its absolute-mode number even in relative mode, by
    /// inference from the guide's RGB section), or `nil` for a control without a light.
    public static func color(_ element: LaunchControlElement, _ index: UInt8) -> [UInt8]? {
        guard element.hasLight, element.isValid else { return nil }
        return [0xB0, element.controlNumber, index & 0x7F]
    }

    /// Lights a control in a color of its own (SysEx 01h 53h), each part 0–127 (SysEx data bytes
    /// are 7-bit; that the device reads 0–127 as its full range is an inference), or `nil` for a
    /// control without a light.
    public static func rgb(_ element: LaunchControlElement, red: UInt8, green: UInt8, blue: UInt8) -> [UInt8]? {
        guard element.hasLight, element.isValid else { return nil }
        return sysExHeader + [0x01, 0x53, element.controlNumber, red & 0x7F, green & 0x7F, blue & 0x7F, 0xF7]
    }

    /// Tells a fader or an encoder the position of what it controls, 0–127, or `nil` for any other
    /// control. Novation's guide says absolute encoders pick up position information from the host
    /// but not in which message; sending the control's own Control Change back on channel 16 is an
    /// inference, and so is that faders use it for their pickup.
    public static func position(_ element: LaunchControlElement, _ value: UInt8) -> [UInt8]? {
        guard element.isContinuous, element.isValid else { return nil }
        return [0xBF, element.controlNumber, value & 0x7F]
    }

    /// Sets up a display (SysEx 04h): its arrangement, and whether the device may bring it up by
    /// itself when its control moves (`onChange`) or is touched with Shift held (`onTouch`). Both
    /// are on by default. `nil` for a target that has no display.
    public static func configureDisplay(_ target: LaunchControlDisplayTarget, _ arrangement: LaunchControlArrangement,
                                        onChange: Bool = true, onTouch: Bool = true) -> [UInt8]? {
        guard let byte = target.byte else { return nil }
        let config = arrangement.rawValue | (onChange ? 0x40 : 0) | (onTouch ? 0x20 : 0)
        return sysExHeader + [0x04, byte, config, 0xF7]
    }

    /// Brings a display up with its current text (`true`) or takes it down (`false`), or `nil` for a
    /// target that has no display.
    public static func showDisplay(_ target: LaunchControlDisplayTarget, _ show: Bool) -> [UInt8]? {
        guard let byte = target.byte else { return nil }
        return sysExHeader + [0x04, byte, show ? 0x7F : 0x00, 0xF7]
    }

    /// Fills in one text field of a display (SysEx 06h), or `nil` for a target that has no display.
    /// The text is made fit for the screen by `LaunchControlText.bytes(_:)`. How many characters a
    /// field shows is not in the guide.
    public static func text(_ target: LaunchControlDisplayTarget, field: Int, _ text: String) -> [UInt8]? {
        guard let byte = target.byte, (0..<128).contains(field) else { return nil }
        return sysExHeader + [0x06, byte, UInt8(field)] + LaunchControlText.bytes(text) + [0xF7]
    }
}

/// Text for the Launch Control XL 3's screen: printable ASCII (20h–7Eh), plus four symbols the
/// device draws in place of control codes.
public enum LaunchControlText {
    /// An empty box (1Bh).
    public static let emptyBox: Character = "\u{25A1}"
    /// A filled box (1Ch).
    public static let filledBox: Character = "\u{25A0}"
    /// A flat sign (1Dh).
    public static let flat: Character = "\u{266D}"
    /// A heart (1Eh).
    public static let heart: Character = "\u{2665}"

    /// The bytes for `text`: printable ASCII as it is; the four symbols as the device's codes;
    /// curly quotes, dashes, and arrows as their plain ASCII forms; accented letters without their
    /// accents; and anything else as "?".
    public static func bytes(_ text: String) -> [UInt8] {
        var bytes: [UInt8] = []
        for character in text {
            switch character {
            case emptyBox: bytes.append(0x1B)
            case filledBox: bytes.append(0x1C)
            case flat: bytes.append(0x1D)
            case heart: bytes.append(0x1E)
            case "\u{2018}", "\u{2019}": bytes.append(0x27)
            case "\u{201C}", "\u{201D}": bytes.append(0x22)
            case "\u{2013}", "\u{2014}", "\u{2212}": bytes.append(0x2D)
            case "\u{2192}": bytes.append(0x3E)
            case "\u{2190}": bytes.append(0x3C)
            case "\u{2026}": bytes.append(contentsOf: [0x2E, 0x2E, 0x2E])
            default:
                let plain = String(character).folding(options: .diacriticInsensitive, locale: nil)
                for scalar in plain.unicodeScalars {
                    bytes.append((0x20...0x7E).contains(scalar.value) ? UInt8(scalar.value) : 0x3F)
                }
            }
        }
        return bytes
    }
}
