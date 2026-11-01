// The two Novation Launch Control models this library covers, and how they differ. Sources:
// Novation's "Launch Control XL 3 programmer's reference guide", version 1.0, and "Launch Control 3
// programmer's reference guide", version 1.1 (dated March 2026): "SysEx message format" and "The
// surface in DAW mode" in each. The Launch Control 3 has not been checked on a device
// (docs/LAUNCH-CONTROL-3.md).

import Foundation

/// A Launch Control model. Both speak the same DAW-mode protocol; they differ in their controls and
/// in one byte of the SysEx header.
public enum LaunchControlModel: String, Hashable, Sendable, CaseIterable {
    /// The Launch Control XL 3: 8 faders, 24 encoders in three rows, two rows of 8 buttons, and a
    /// screen. Checked on a device (docs/LAUNCH-CONTROL-XL3.md, section 10).
    case xl3
    /// The Launch Control 3: 16 encoders in two rows, one row of 8 buttons, and a screen; no
    /// faders, Record, Play, or Mute/Select. Not checked on a device (docs/LAUNCH-CONTROL-3.md).
    case lc3

    /// The model's name as Novation writes it.
    public var name: String {
        switch self {
        case .xl3: return "Launch Control XL 3"
        case .lc3: return "Launch Control 3"
        }
    }

    /// The byte after Novation's manufacturer ID and 02h in every SysEx message, both ways: 15h for
    /// the XL 3 and 16h for the Launch Control 3. [Each model's programmer's reference guide,
    /// "SysEx message format"]
    public var deviceByte: UInt8 {
        switch self {
        case .xl3: return 0x15
        case .lc3: return 0x16
        }
    }

    /// The start of every SysEx message to or from this model: F0h, Novation's manufacturer ID
    /// (00h 20h 29h), 02h, and `deviceByte`.
    public var sysExHeader: [UInt8] { [0xF0, 0x00, 0x20, 0x29, 0x02, deviceByte] }

    /// The start of the name of the model's DAW MIDI ports on macOS, with device ID 1: "LCXL3 1 DAW"
    /// (seen, docs/LAUNCH-CONTROL-XL3.md, test 1) and "LC3 1 DAW" (inference: Bitwig's own
    /// Launch Control 3 extension looks for "LC3 1 DAW In" and "LC3 1 DAW Out").
    public var defaultPortName: String {
        switch self {
        case .xl3: return "LCXL3 1 DAW"
        case .lc3: return "LC3 1 DAW"
        }
    }

    /// How many rows of encoders the model has: 3 or 2.
    public var encoderRows: Int { self == .xl3 ? 3 : 2 }

    /// How many rows of 8 buttons the model has: 2 or 1.
    public var buttonRows: Int { self == .xl3 ? 2 : 1 }

    /// Whether the model has faders.
    public var hasFaders: Bool { self == .xl3 }

    /// Whether the model has a control. On the Launch Control 3:
    /// - the encoders are the XL 3's top two rows and the buttons its top row, with the same
    ///   numbers [Launch Control 3 programmer's reference guide, control map];
    /// - `soloArm` stands for its Function button, in the same place (inference: the guide's
    ///   control map doesn't number it; Bitwig's extension, shared between the two models, reads
    ///   the XL 3's numbers);
    /// - Page, Track, Shift, and the Novation button are on the device; that they send the XL 3's
    ///   numbers is the same inference.
    public func has(_ element: LaunchControlElement) -> Bool {
        guard element.isValid else { return false }
        switch (self, element) {
        case (.xl3, _): return true
        case (.lc3, .fader), (.lc3, .muteSelect), (.lc3, .record), (.lc3, .play): return false
        case (.lc3, .encoder(let row, _)): return row < 2
        case (.lc3, .button(let row, _)): return row < 1
        case (.lc3, _): return true
        }
    }

    /// The model's controls, in the order of `LaunchControlElement.all`.
    public var elements: [LaunchControlElement] { LaunchControlElement.all.filter(has) }

    /// The model whose SysEx header starts `bytes`, if any.
    public init?(sysEx bytes: [UInt8]) {
        guard let model = Self.allCases.first(where: { Array(bytes.prefix(6)) == $0.sysExHeader }) else { return nil }
        self = model
    }
}
