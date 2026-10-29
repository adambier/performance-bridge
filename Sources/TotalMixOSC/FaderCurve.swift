import Foundation

/// The curve between a TotalMix fader's position and its gain.
///
/// TotalMix's Global OSC sends and accepts fader positions as `faderlin`, scaled 0 to 1. RME's
/// Global OSC protocol document (revision 2026-07-21, sheet "Fader curve") gives the curve as two
/// segments over 1,023 steps of travel. This is our own implementation of that curve, written with
/// the exact fractions behind RME's decimal constants (for example 0.0320855615 = 6/187 and
/// 0.1497326203 = 28/187); see docs/TOTALMIX-OSC.md.
///
/// - From step 649 (−6 dB) to step 1023 (+6 dB) the gain rises linearly: 6/187 dB per step.
/// - Below step 649 the gain follows a parabola from −65 dB at step 0 to −6 dB at step 649.
/// - Gains below −64.9 dB count as off. RME's document names the value used for off
///   (`GAINSUBMIXOFF`) without giving it; here off is `nil`.
public enum FaderCurve {
    /// Steps of fader travel; position 1.0 is step 1023.
    public static let steps: Double = 1023
    /// The step where the two segments meet.
    public static let kneeStep: Double = 649
    /// The gain at the knee, in dB.
    public static let kneeGainDB: Double = -6
    /// The gain at the bottom of travel, in dB.
    public static let minimumGainDB: Double = -65
    /// The gain at the top of travel, in dB.
    public static let maximumGainDB: Double = 6
    /// Gains below this count as off.
    public static let offThresholdDB: Double = -64.9

    /// The gain for a fader position (0…1), in dB, or `nil` for off.
    /// Positions outside 0…1 are clamped.
    public static func gainDB(position: Double) -> Double? {
        let step = min(max(position, 0), 1) * steps
        let gain: Double
        if step >= kneeStep {
            gain = (6 * step - 5016) / 187
        } else {
            gain = minimumGainDB + 28 * step / 187 - step * step / 11033
        }
        return gain < offThresholdDB ? nil : gain
    }

    /// The fader position (0…1) for a gain in dB; `nil` (off) or any gain at or below −65 dB gives
    /// 0, and gains above +6 dB give 1.
    public static func position(gainDB: Double?) -> Double {
        guard let gain = gainDB, gain > minimumGainDB else { return 0 }
        let step: Double
        if gain >= kneeGainDB {
            step = (187 * gain + 5016) / 6
        } else {
            step = 826 - (-34869 - 11033 * gain).squareRoot()
        }
        return min(max(step / steps, 0), 1)
    }

    /// The position of 0 dB (unity gain): step 836, about 0.8172.
    public static var unityPosition: Double { position(gainDB: 0) }
}
