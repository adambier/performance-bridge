import Foundation

/// A TotalMix FX version, such as "2.10 (1)" as TotalMix shows it, compared as RME numbers them.
///
/// RME writes TotalMix versions with a two-digit minor number ("1.96", "2.10"), which reads as a
/// decimal: 2.10 is "2.1", and comes after 1.99 and before 2.11. So the minor number is read as
/// hundredths: "2.1" and "2.10" are the same version. (Inference from the version strings seen:
/// "2.10 (1)" on Adam's Mac, and RME's protocol document for "TotalMix FX 2.1 beta 2".) Anything
/// after the number, such as a build number or "RC1", is ignored, so release candidates count as
/// their version.
public struct TotalMixVersion: Comparable, Sendable, CustomStringConvertible {
    /// The major number.
    public var major: Int
    /// The minor number in hundredths: 10 for "2.1" and "2.10", 96 for "1.96".
    public var hundredths: Int

    /// The first version with Global OSC: 2.1 (Adam, 2026-10-31; RME's protocol document is for
    /// "TotalMix FX 2.1 beta 2"). Earlier versions don't support it.
    public static let globalOSC = TotalMixVersion(major: 2, hundredths: 10)

    /// Makes a version from its numbers.
    public init(major: Int, hundredths: Int) {
        self.major = major
        self.hundredths = hundredths
    }

    /// Reads the first "major.minor" in `text` (e.g., "2.10 (1)", "Version 2.1 RC2", "1.96");
    /// `nil` if there is none.
    public init?(_ text: String) {
        let characters = Array(text)
        var index = 0
        while index < characters.count {
            guard characters[index].isASCII, characters[index].isNumber else { index += 1; continue }
            var end = index
            while end < characters.count, characters[end].isASCII, characters[end].isNumber { end += 1 }
            guard end < characters.count, characters[end] == "." else { index = end; continue }
            var minorEnd = end + 1
            while minorEnd < characters.count, characters[minorEnd].isASCII, characters[minorEnd].isNumber { minorEnd += 1 }
            guard minorEnd > end + 1, let major = Int(String(characters[index..<end])) else { index = end + 1; continue }
            var minor = String(characters[(end + 1)..<minorEnd])
            minor = String((minor + "0").prefix(2))   // "1" → "10"; "10" → "10"; "123" → "12"
            guard let hundredths = Int(minor) else { return nil }
            self.init(major: major, hundredths: hundredths)
            return
        }
        return nil
    }

    /// Whether this version has Global OSC (2.1 or later).
    public var supportsGlobalOSC: Bool { self >= Self.globalOSC }

    /// "2.10", as RME writes it.
    public var description: String { "\(major).\(hundredths < 10 ? "0" : "")\(hundredths)" }

    /// Orders versions as RME numbers them.
    public static func < (lhs: TotalMixVersion, rhs: TotalMixVersion) -> Bool {
        (lhs.major, lhs.hundredths) < (rhs.major, rhs.hundredths)
    }
}
