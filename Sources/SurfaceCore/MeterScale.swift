import Foundation
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// The scale from TotalMix's peak levels to a surface's meters (0…127).
///
/// TotalMix sends peak levels in dB (`/level/…`, docs/TOTALMIX-OSC.md). The scale is linear in dB
/// over −60…0 dBFS, with the top value reserved for full scale; the −60 dB floor is this project's
/// choice. The color thresholds follow TotalMix's meter colors as Adam gave them (yellow from
/// −5 dBFS, orange from −4, red from −1, flashing at 0; docs/TOTALMIX-OSC.md) as closely as a
/// surface with two thresholds can: yellow from −5 dBFS and red from −1 dBFS.
public enum MeterScale {
    /// The bottom of the scale, in dBFS; anything lower shows 0.
    public static let floorDB: Double = -60
    /// The highest meter value, reached only at full scale (0 dBFS or above).
    public static let fullScale = 127
    /// The level from which a meter shows yellow, in dBFS, as TotalMix's does.
    public static let warningDB: Double = -5
    /// The level from which a meter shows red, in dBFS, as TotalMix's does.
    public static let redDB: Double = -1
    /// The meter value from which a surface should color its meter yellow (−5 dBFS: 116).
    public static var warning: Int { value(peakDB: warningDB) }
    /// The meter value from which a surface should color its meter red (−1 dBFS: 124).
    public static var red: Int { value(peakDB: redDB) }

    /// The meter value for a peak level in dB.
    public static func value(peakDB: Double) -> Int {
        guard peakDB.isFinite else { return peakDB > 0 ? fullScale : 0 }
        if peakDB >= 0 { return fullScale }
        let scaled = (peakDB - floorDB) / -floorDB * Double(fullScale)
        return min(max(Int(scaled.rounded(.down)), 0), fullScale - 1)
    }
}

/// Text for a knob's value, short enough for a surface's display. The format is this project's own.
public enum ValueText {
    /// A fader position as a gain: "-6.0 dB", "+2.5 dB", "0.0 dB", or "off".
    public static func level(position: Double) -> String {
        guard let gain = FaderCurve.gainDB(position: position) else { return "off" }
        let rounded = (gain * 10).rounded() / 10
        if rounded == 0 { return "0.0 dB" }
        return String(format: rounded > 0 ? "+%.1f dB" : "%.1f dB", rounded)
    }

    /// A pan (−1…+1) as "C", "L50", or "R100".
    public static func pan(_ value: Double) -> String {
        let percent = Int((min(max(value, -1), 1) * 100).rounded())
        if percent == 0 { return "C" }
        return percent < 0 ? "L\(-percent)" : "R\(percent)"
    }
}
