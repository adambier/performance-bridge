import Foundation

/// The three rows of TotalMix's mixer.
///
/// Global OSC spells them differently in different addresses (see docs/TOTALMIX-OSC.md):
/// channel settings and `/sendchan` use the full words, mixer nodes use `in` and `pb`, and levels
/// use `in`, `pb`, and `out`.
public enum TotalMixBus: String, CaseIterable, Sendable, Codable {
    case input
    case playback
    case output

    /// The word in channel-setting addresses (`/input/<channel>/…`) and in `/sendchan`.
    public var settingsName: String { rawValue }

    /// The word in mixer-node addresses (`/mix/in/…`, `/mix/pb/…`); outputs are not node sources.
    public var mixName: String? {
        switch self {
        case .input: return "in"
        case .playback: return "pb"
        case .output: return nil
        }
    }

    /// The word in level addresses (`/level/in/…`, `/level/pb/…`, `/level/out/…`).
    public var levelName: String {
        switch self {
        case .input: return "in"
        case .playback: return "pb"
        case .output: return "out"
        }
    }

    /// The bus named by a word from any of the three spellings.
    public init?(word: String) {
        switch word {
        case "input", "in": self = .input
        case "playback", "pb": self = .playback
        case "output", "out": self = .output
        default: return nil
        }
    }
}
