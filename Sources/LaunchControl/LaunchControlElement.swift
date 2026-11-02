// The Launch Control XL 3's controls in DAW mode, and the MIDI Control Changes they send and take.
// Source: Novation's "Launch Control XL 3 programmer's reference guide", version 1.0 (April 2026),
// "The surface in DAW mode" (the control map is a picture there; read 2026-10-31). The whole map
// has been checked on the device (docs/LAUNCH-CONTROL-XL3.md, test 1). The Launch Control 3 has a
// subset of these controls (`LaunchControlModel.has(_:)`).

import Foundation

/// A control on the Launch Control XL 3, as DAW mode reports it. Rows and columns count from 0:
/// the encoder rows from the top, the button rows from the top, and the columns from the left.
public enum LaunchControlElement: Hashable, Sendable {
    /// One of the eight faders (0–7). Not motorized; no LED in the guide's pictures.
    case fader(Int)
    /// One of the 24 endless encoders: row 0–2, column 0–7. Each has an LED under it.
    case encoder(row: Int, column: Int)
    /// One of the 16 buttons under the faders: row 0 (Novation's "Solo/Arm" row) or 1 ("Mute/Select"
    /// row), column 0–7.
    case button(row: Int, column: Int)
    /// The Solo/Arm button, left of the top button row.
    case soloArm
    /// The Mute/Select button, left of the bottom button row. On the Launch Control 3, the Function
    /// button, by its number (`LaunchControlModel.has(_:)`).
    case muteSelect
    /// The button with Novation's logo, in the top button row between Solo/Arm and button 1 (the
    /// control map). "Nothing… yet", says the user guide.
    case novation
    /// Page up, the left button of the Page pair.
    case pageUp
    /// Page down, the right button of the Page pair.
    case pageDown
    /// Track left (<).
    case trackLeft
    /// Track right (>).
    case trackRight
    /// The Record button.
    case record
    /// The Play button.
    case play
    /// The Shift button. It reports on channel 7, as a feature control, and takes no color.
    case shift

    /// Every control, in the order of the control map: faders, encoders by row, buttons by row, then
    /// the buttons on the left.
    public static let all: [LaunchControlElement] =
        (0..<8).map { .fader($0) }
        + (0..<3).flatMap { row in (0..<8).map { .encoder(row: row, column: $0) } }
        + (0..<2).flatMap { row in (0..<8).map { .button(row: row, column: $0) } }
        + [.soloArm, .muteSelect, .novation, .pageUp, .pageDown, .trackLeft, .trackRight, .record, .play, .shift]

    /// Whether the control's numbers are in range (e.g., a fader from 0 to 7).
    public var isValid: Bool {
        switch self {
        case .fader(let index): return (0..<8).contains(index)
        case .encoder(let row, let column): return (0..<3).contains(row) && (0..<8).contains(column)
        case .button(let row, let column): return (0..<2).contains(row) && (0..<8).contains(column)
        default: return true
        }
    }

    /// The Control Change number the control sends, and takes for its color: faders 5–12, encoders
    /// 13–20, 21–28, and 29–36 by row, buttons 37–44 and 45–52 by row, Solo/Arm 65, Mute/Select 66,
    /// Novation 104, Page 106 and 107, Track 103 (left) and 102 (right), Record 118, Play 116,
    /// Shift 63.
    public var controlNumber: UInt8 {
        switch self {
        case .fader(let index): return UInt8(5 + index)
        case .encoder(let row, let column): return UInt8(13 + 8 * row + column)
        case .button(let row, let column): return UInt8(37 + 8 * row + column)
        case .soloArm: return 65
        case .muteSelect: return 66
        case .novation: return 104
        case .pageUp: return 106
        case .pageDown: return 107
        case .trackLeft: return 103
        case .trackRight: return 102
        case .record: return 118
        case .play: return 116
        case .shift: return 63
        }
    }

    /// The MIDI channel the control reports on, counting from 0: 15 (Novation's channel 16) for
    /// faders and encoders, 6 (channel 7) for Shift, and 0 (channel 1) for the other buttons.
    public var reportChannel: UInt8 {
        switch self {
        case .fader, .encoder: return 15
        case .shift: return 6
        default: return 0
        }
    }

    /// Whether the control is a fader or an encoder, which send a position rather than press and
    /// release.
    public var isContinuous: Bool {
        switch self {
        case .fader, .encoder: return true
        default: return false
        }
    }

    /// Whether the control can be given a color. Shift's light belongs to its feature control. That
    /// the Novation button has no LED has been seen (docs/LAUNCH-CONTROL-XL3.md, test 4); that faders
    /// have none is an inference from the guide's pictures.
    public var hasLight: Bool {
        switch self {
        case .fader, .shift, .novation: return false
        default: return true
        }
    }

    /// The control that reports `controlNumber` on `channel` (counting from 0), if any. Encoders in
    /// relative mode report other numbers (see `LaunchControlEvent`).
    public init?(channel: UInt8, controlNumber: UInt8) {
        switch (channel, controlNumber) {
        case (15, 5...12): self = .fader(Int(controlNumber) - 5)
        case (15, 13...36):
            let index = Int(controlNumber) - 13
            self = .encoder(row: index / 8, column: index % 8)
        case (0, 37...52):
            let index = Int(controlNumber) - 37
            self = .button(row: index / 8, column: index % 8)
        case (0, 65): self = .soloArm
        case (0, 66): self = .muteSelect
        case (0, 104): self = .novation
        case (0, 106): self = .pageUp
        case (0, 107): self = .pageDown
        case (0, 103): self = .trackLeft
        case (0, 102): self = .trackRight
        case (0, 118): self = .record
        case (0, 116): self = .play
        case (6, 63): self = .shift
        default: return nil
        }
    }
}

/// The Launch Control XL 3's surface modes, as Mode selects them and the device reports them
/// (channel 7, Control Change 30).
public enum LaunchControlMode: Equatable, Sendable {
    /// DAW Mixer (value 1).
    case dawMixer
    /// DAW Control (value 2).
    case dawControl
    /// A Custom Mode, 1–16 (values 6–9 for 1–4 and 18–29 for 5–16, per the guide's feature
    /// control table; its prose has the same values but labels them inconsistently,
    /// docs/LAUNCH-CONTROL-XL3.md).
    case custom(Int)

    /// The mode a reported value stands for, if any.
    public init?(value: UInt8) {
        switch value {
        case 1: self = .dawMixer
        case 2: self = .dawControl
        case 6...9: self = .custom(Int(value) - 5)
        case 18...29: self = .custom(Int(value) - 13)
        default: return nil
        }
    }

    /// The value that selects the mode, or `nil` for a Custom Mode number out of range.
    public var value: UInt8? {
        switch self {
        case .dawMixer: return 1
        case .dawControl: return 2
        case .custom(let number):
            switch number {
            case 1...4: return UInt8(number + 5)
            case 5...16: return UInt8(number + 13)
            default: return nil
            }
        }
    }
}
