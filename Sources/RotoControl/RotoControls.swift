import Foundation

/// The Roto-Control's CC numbers in MIX mode, all on MIDI channel 16 (docs/ROTO-CONTROL.md,
/// section 5).
public enum RotoCC {
    /// MIDI channel 16, counted from 0.
    public static let channel: UInt8 = 15
    /// The number of knobs, switches, and meter strips.
    public static let controlCount = 8
    /// Knob 1's high 7 bits; knobs 2–8 follow.
    public static let knobHigh: UInt8 = 12
    /// Knob 1's low 7 bits; knobs 2–8 follow.
    public static let knobLow: UInt8 = 44
    /// Switch 1; switches 2–8 follow.
    public static let switchFirst: UInt8 = 20
    /// Transport switch 1; transport switches 2–8 follow.
    public static let transportFirst: UInt8 = 28
    /// Knob 1's touch; knobs 2–8 follow.
    public static let touchFirst: UInt8 = 52
    /// "Level at 0 dB", sent with a knob's index as the value.
    public static let levelToZeroDB: UInt8 = 64
    /// Track 1's left meter; its right meter is next, then track 2's pair, and so on.
    public static let meterFirst: UInt8 = 65

    /// The CC for control `index` (0–7) of a block that starts at `first`.
    static func cc(_ first: UInt8, _ index: Int) -> UInt8 {
        first + UInt8(min(max(index, 0), controlCount - 1))
    }
}

/// A control the user worked on the Roto-Control.
public enum RotoControlEvent: Equatable, Sendable {
    /// A knob (0–7) turned to a 14-bit position (0–16383).
    case knob(Int, position: Int)
    /// A knob (0–7) touched or released.
    case touch(Int, touched: Bool)
    /// A switch (0–7) pressed or released.
    case `switch`(Int, pressed: Bool)
    /// A transport switch (0–7) pressed or released.
    case transport(Int, pressed: Bool)
    /// CC 64: set a knob's (0–7) level to 0 dB.
    case levelToZeroDB(Int)
    /// A CC this library does not interpret: channel 0–15, controller, and value.
    case otherCC(channel: UInt8, controller: UInt8, value: UInt8)
}

/// Turns control changes from the Roto-Control into `RotoControlEvent`s.
///
/// A knob sends its position as two CCs, the high 7 bits and then the low 7 bits. The decoder
/// keeps the last high value of each knob and reports a position when the low value arrives. That
/// the Roto-Control always sends the high CC before the low one, and may leave out an unchanged
/// high CC, are inferences still to be tested (docs/ROTO-CONTROL.md, section 8). A low CC before any
/// high CC for that knob is dropped.
public struct RotoControlDecoder: Sendable {
    private var high: [UInt8?] = Array(repeating: nil, count: RotoCC.controlCount)

    /// Makes a decoder that has seen no knob.
    public init() {}

    /// The event for one control change, or `nil` for a knob's high CC, which only waits for its low
    /// CC, and for a low CC with no high CC before it.
    public mutating func decode(channel: UInt8, controller: UInt8, value: UInt8) -> RotoControlEvent? {
        guard channel == RotoCC.channel else {
            return .otherCC(channel: channel, controller: controller, value: value)
        }
        func index(_ first: UInt8) -> Int? {
            controller >= first && controller < first + UInt8(RotoCC.controlCount) ? Int(controller - first) : nil
        }
        let pressed = value >= 64
        if let knob = index(RotoCC.knobHigh) {
            high[knob] = value & 0x7F
            return nil
        }
        if let knob = index(RotoCC.knobLow) {
            guard let highBits = high[knob] else { return nil }
            return .knob(knob, position: RotoSysEx.decode14(highBits, value))
        }
        if let control = index(RotoCC.switchFirst) { return .switch(control, pressed: pressed) }
        if let control = index(RotoCC.transportFirst) { return .transport(control, pressed: pressed) }
        if let knob = index(RotoCC.touchFirst) { return .touch(knob, touched: pressed) }
        if controller == RotoCC.levelToZeroDB, Int(value) < RotoCC.controlCount {
            return .levelToZeroDB(Int(value))
        }
        return .otherCC(channel: channel, controller: controller, value: value)
    }
}

/// The CC messages that move a knob, light a switch, or set a meter on the Roto-Control
/// (docs/ROTO-CONTROL.md, sections 5 and 6). Each function returns complete MIDI bytes.
public enum RotoFeedback {
    private static let status: UInt8 = 0xB0 | RotoCC.channel

    /// Moves knob `index` (0–7) to a 14-bit position (clamped to 0–16383): the high CC, then the low.
    public static func knob(_ index: Int, position: Int) -> [UInt8] {
        let bytes = RotoSysEx.encode14(position)
        return [status, RotoCC.cc(RotoCC.knobHigh, index), bytes[0],
                status, RotoCC.cc(RotoCC.knobLow, index), bytes[1]]
    }

    /// Lights switch `index` (0–7), or turns it off: 127 or 0.
    public static func switchLight(_ index: Int, on: Bool) -> [UInt8] {
        [status, RotoCC.cc(RotoCC.switchFirst, index), on ? 127 : 0]
    }

    /// Sets the meters of track `index` (0–7) of the page; values are clamped to 0–127.
    public static func meter(_ index: Int, left: UInt8, right: UInt8) -> [UInt8] {
        let first = RotoCC.meterFirst + UInt8(min(max(index, 0), RotoCC.controlCount - 1) * 2)
        return [status, first, min(left, 127), status, first + 1, min(right, 127)]
    }

    /// The 14-bit position for a value from 0 to 1, rounded, as Bitwig's integration computes it.
    public static func position(_ fraction: Double) -> Int {
        Int((min(max(fraction, 0), 1) * Double(RotoSysEx.maximum14Bit)).rounded())
    }

    /// The value from 0 to 1 for a 14-bit position.
    public static func fraction(_ position: Int) -> Double {
        Double(min(max(position, 0), RotoSysEx.maximum14Bit)) / Double(RotoSysEx.maximum14Bit)
    }
}
