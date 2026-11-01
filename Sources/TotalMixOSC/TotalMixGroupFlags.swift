import Foundation

/// The group memberships in a `groupflags` value (sent for outputs and mixer nodes).
///
/// The bits count from 0. Bit 1 is mute group 1 and bit 12 fader group 1, both confirmed in tests
/// (docs/TOTALMIX-OSC.md, tests 1 and 17). Mute groups 1–4 are bits 1–4, solo groups 1–4 bits 6–9,
/// and fader groups 1–4 bits 12–15: RME's protocol document gives these ranges, read here from 0.
/// The solo positions are not yet confirmed by a test. The document writes the fader range as
/// "12..16", taken here to be a slip for four bits. A bit means membership; whether the group is
/// switched on comes separately, as `/fadergroup/N` and the like (test 17).
public struct TotalMixGroupFlags: Equatable, Sendable {
    /// The raw value, as TotalMix sent it.
    public var rawValue: Int

    /// Reads a value as TotalMix sent it (a float holding an integer).
    public init(_ value: Double) {
        rawValue = Int(value.rounded())
    }

    /// Makes flags from the raw integer.
    public init(rawValue: Int) {
        self.rawValue = rawValue
    }

    /// The mute groups (1–4) the channel or node belongs to.
    public var muteGroups: Set<Int> { groups(firstBit: 1) }
    /// The solo groups (1–4) the channel or node belongs to.
    public var soloGroups: Set<Int> { groups(firstBit: 6) }
    /// The fader groups (1–4) the channel or node belongs to.
    public var faderGroups: Set<Int> { groups(firstBit: 12) }

    private func groups(firstBit: Int) -> Set<Int> {
        Set((1...4).filter { rawValue & (1 << (firstBit + $0 - 1)) != 0 })
    }
}
