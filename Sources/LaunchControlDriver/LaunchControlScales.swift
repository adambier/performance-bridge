// The Launch Control driver's value scales: pan in TotalMix FX's whole steps, the ARC USB wheel's
// scale for level and send encoders, and the fader scale on the printed ticks. Pure functions of the
// driver's state-free kind, moved out of LaunchControlDriver.swift unchanged (refactoring of
// 2026-11-04); the evidence is in docs/LAUNCH-CONTROL-XL3.md, tests 7, 8, and 11.

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

extension LaunchControlDriver {
    /// The pan, in TotalMix FX's whole steps (−100 for L100 to +100 for R100), for a pan encoder's
    /// value: 64 is the center, 0 is L100, and 127 is R100, each value about 1.6 steps (so steps of
    /// 1 or 2; Adam, 2026-11-01).
    public static func panSteps(_ value: UInt8) -> Int {
        let offset = Double(Int(min(value, 127)) - 64)
        return Int((offset < 0 ? offset * 100 / 64 : offset * 100 / 63).rounded())
    }

    /// The hub position (0…1, the center at 0.5) for a pan encoder's value. It lands a quarter step
    /// to the right of one of TotalMix FX's whole pan steps, so that TotalMix FX's window and the
    /// encoder's display show the same step. TotalMix FX has been observed to show the whole step
    /// below a fractional pan, toward L (R1.6 as R01, L2.25 as L03; Adam, 2026-11-01;
    /// docs/LAUNCH-CONTROL-XL3.md, section 9), and the display rounds, so a quarter step to the
    /// right gives the same step in both.
    public static func panPosition(_ value: UInt8) -> Double {
        let steps = panSteps(value)
        guard steps != 0 else { return 0.5 }
        guard steps > -100 else { return 0 }  // L100 is the end, exactly
        let pan = min((Double(steps) + 0.25) / 100, 1)
        return (pan + 1) / 2
    }

    /// The pan encoder's value for a hub position (0…1): the inverse of `panPosition(_:)`, by the
    /// nearest whole pan step.
    public static func panValue(_ position: Double) -> UInt8 {
        let pan = min(max(position.isFinite ? position : 0.5, 0), 1) * 2 - 1
        let steps = (pan * 100).rounded()
        let offset = steps < 0 ? steps * 64 / 100 : steps * 63 / 100
        return UInt8(min(max(64 + offset.rounded(), 0), 127))
    }

    /// The gains of the ARC USB's wheel, one per detent from the bottom (after off) to the top, as
    /// TotalMix FX shows them (Adam, 2026-11-01; docs/TOTALMIX-OSC.md, test 19): 3 dB steps at the
    /// bottom, then 2.5, 2, 1.5, and 1 dB, and 0.5 dB from −5 to +5 dB. Level and send encoders use
    /// this scale, as volume controls (Adam, 2026-11-01).
    public static let arcDetents: [Double] = [
        -63.5, -60.5, -57.5, -54.5, -51.5, -48.5, -45.5, -43, -40.5, -38, -35.5, -33.5, -31.5, -29.5,
        -27.5, -25.5, -24, -22.5, -21, -19.5, -18, -16.5, -15, -14, -13, -12, -11, -10, -9, -8, -7, -6,
        -5, -4.5, -4, -3.5, -3, -2.5, -2, -1.5, -1, -0.5, 0, 0.5, 1, 1.5, 2, 2.5, 3, 3.5, 4, 4.5, 5, 6,
    ]

    /// The encoder value at 0 dB on the ARC scale: 101, as on the XL 3's faders (`faderTicks`).
    /// Values 1–101 spread the detents from −63.5 to 0 dB evenly, and 101–127 those from 0 to +6 dB
    /// (about 0.42 detents a value either side: 0.2 dB a value near 0 dB, 1.3 dB at the bottom).
    /// Value 0 is off.
    public static let encoderUnityValue = 101

    /// The gain in dB for an encoder value on the ARC scale (fractional values between whole ones),
    /// or `nil` for off.
    static func encoderGain(exactly value: Double) -> Double? {
        guard value >= 1 else { return nil }
        let unity = Double(encoderUnityValue)
        let zero = Double(arcDetents.firstIndex(of: 0) ?? 0)
        let top = Double(arcDetents.count - 1)
        let index = value <= unity ? (value - 1) * zero / (unity - 1) : zero + (min(value, 127) - unity) * (top - zero) / (127 - unity)
        let lower = Int(index.rounded(.down))
        guard lower + 1 < arcDetents.count else { return arcDetents.last }
        let fraction = index - Double(lower)
        return arcDetents[lower] + fraction * (arcDetents[lower + 1] - arcDetents[lower])
    }

    /// TotalMix FX's fader position (0…1) for a level or send encoder's value, on the ARC scale.
    public static func encoderPosition(_ value: UInt8) -> Double {
        guard let gain = encoderGain(exactly: Double(min(value, 127))) else { return 0 }
        return FaderCurve.position(gainDB: gain)
    }

    /// The encoder value for TotalMix FX's fader position (0…1) on the ARC scale: the inverse of
    /// `encoderPosition(_:)`, rounded. A gain between off and the lowest detent is value 1.
    public static func encoderValue(_ position: Double) -> UInt8 {
        guard position.isFinite, let gain = FaderCurve.gainDB(position: min(max(position, 0), 1)) else { return 0 }
        guard let first = arcDetents.first, gain > first else { return 1 }
        let zero = Double(arcDetents.firstIndex(of: 0) ?? 0)
        let top = Double(arcDetents.count - 1)
        var index = top
        for (offset, pair) in zip(arcDetents, arcDetents.dropFirst()).enumerated() where gain <= pair.1 {
            index = Double(offset) + (gain - pair.0) / (pair.1 - pair.0)
            break
        }
        let unity = Double(encoderUnityValue)
        let value = index <= zero ? 1 + index * (unity - 1) / zero : unity + (index - zero) * (127 - unity) / (top - zero)
        return UInt8(min(max(value.rounded(), 1), 127))
    }

    /// The XL 3's fader scale (Adam, 2026-11-01): the gain at each of the nine ticks printed beside
    /// each fader, top to bottom, with the fader value measured at each tick
    /// (docs/LAUNCH-CONTROL-XL3.md, tests 7 and 8: the mean of two passes). The labels are TotalMix FX's own fader marks: +6 (the
    /// top), +3, 0, −6, −10, −20, −40, −60 (docs/TOTALMIX-OSC.md, test 18); the bottom tick, value 0,
    /// is off. Between ticks the gain moves evenly in dB; below −60 it follows TotalMix FX's fader
    /// position down to off.
    public static let faderTicks: [(value: Double, gainDB: Double)] = [
        (127, 6), (119, 3), (101, 0), (83.5, -6), (65.5, -10), (46, -20), (29, -40), (11, -60),
    ]

    /// TotalMix FX's fader position (0…1) for an XL 3 fader value, on the printed scale.
    public static func faderPosition(_ value: UInt8) -> Double {
        faderPosition(exactly: Double(min(value, 127)))
    }

    /// `faderPosition(_:)` for any value from 0 to 127, including the ticks between whole values.
    static func faderPosition(exactly value: Double) -> Double {
        guard let lowest = faderTicks.last else { return value / 127 }
        if value <= lowest.value {
            return value / lowest.value * FaderCurve.position(gainDB: lowest.gainDB)
        }
        for (upper, lower) in zip(faderTicks, faderTicks.dropFirst()) where value >= lower.value {
            let fraction = (value - lower.value) / (upper.value - lower.value)
            return FaderCurve.position(gainDB: lower.gainDB + fraction * (upper.gainDB - lower.gainDB))
        }
        return 1
    }

    /// The XL 3 fader value for TotalMix FX's fader position (0…1): the inverse of
    /// `faderPosition(_:)`, rounded.
    public static func faderValue(_ position: Double) -> UInt8 {
        let position = min(max(position.isFinite ? position : 0, 0), 1)
        guard let lowest = faderTicks.last else { return UInt8((position * 127).rounded()) }
        let lowestPosition = FaderCurve.position(gainDB: lowest.gainDB)
        if position <= lowestPosition {
            return UInt8((position / lowestPosition * lowest.value).rounded())
        }
        guard let gain = FaderCurve.gainDB(position: position) else { return 0 }
        for (upper, lower) in zip(faderTicks, faderTicks.dropFirst()) where gain >= lower.gainDB {
            let fraction = min((gain - lower.gainDB) / (upper.gainDB - lower.gainDB), 1)
            return UInt8(min(max((lower.value + fraction * (upper.value - lower.value)).rounded(), 0), 127))
        }
        return 127
    }

    /// A position (0…1) for a 7-bit value, with 64 as the exact middle, so that a pan can be
    /// centered: 0–64 map to 0–0.5 and 64–127 to 0.5–1.
    public static func position(_ value: UInt8) -> Double {
        let value = Double(min(value, 127))
        return value <= 64 ? value / 128 : 0.5 + (value - 64) / 126
    }

    /// The 7-bit value for a position (0…1): the inverse of `position(_:)`, rounded.
    public static func value(_ position: Double) -> UInt8 {
        let position = min(max(position.isFinite ? position : 0, 0), 1)
        let value = position <= 0.5 ? position * 128 : 64 + (position - 0.5) * 126
        return UInt8(min(max(value.rounded(), 0), 127))
    }
}
