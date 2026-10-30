import Foundation

/// A hash that names a plugin (8 bytes) or a parameter (6 bytes) in PLUGIN mode. The Roto-Control
/// stores its learned mappings under these hashes (docs/ROTO-CONTROL.md, section 4a), so a hash
/// must stay the same for the same plugin or parameter from one session to the next.
public struct RotoHash: Hashable, Sendable {
    /// The hash's bytes, each 7-bit.
    public let bytes: [UInt8]

    /// A hash from its bytes, masked to 7 bits.
    public init(bytes: [UInt8]) {
        self.bytes = bytes.map { $0 & 0x7F }
    }

    /// A stable hash of a text, `length` bytes long (at most 9). Melbourne Instruments' Ableton
    /// integration uses SHA-1; any hash that is stable will do, on the inference that the
    /// Roto-Control treats it only as a name. This one is FNV-1a (64 bits), 7 bits per byte.
    public static func of(_ text: String, length: Int) -> RotoHash {
        var value: UInt64 = 0xCBF2_9CE4_8422_2325
        for byte in text.utf8 {
            value ^= UInt64(byte)
            value = value &* 0x0000_0100_0000_01B3
        }
        return RotoHash(bytes: (0..<min(max(length, 0), 9)).map { UInt8((value >> (7 * UInt64($0))) & 0x7F) })
    }

    /// The hash padded with 0 bytes, or cut, to exactly `length` bytes.
    func field(_ length: Int) -> [UInt8] {
        Array(bytes.prefix(length)) + [UInt8](repeating: 0, count: max(length - bytes.count, 0))
    }
}

/// What kind of plugin PLUGIN DETAILS describes.
public enum RotoPluginType: UInt8, Sendable {
    /// An ordinary plugin.
    case normal = 0x00
    /// A macro plugin, with pages of macro controls.
    case macro = 0x01
    /// A third-party plugin.
    case thirdParty = 0x02
}

/// One plugin, as PLUGIN DETAILS describes it.
public struct RotoPluginDetails: Equatable, Sendable {
    /// The plugin's index (in the whole list, not the page).
    public var index: Int
    /// The plugin's hash (8 bytes), under which the Roto-Control stores its mappings.
    public var hash: RotoHash
    /// Whether the plugin is enabled.
    public var enabled: Bool
    /// The name; at most 12 characters are shown.
    public var name: String
    /// The kind of plugin.
    public var type: RotoPluginType
    /// The number of macro pages; 0 unless `type` is `.macro`.
    public var macroPages: Int

    /// Makes a plugin's details.
    public init(index: Int, hash: RotoHash, enabled: Bool = true, name: String, type: RotoPluginType = .normal, macroPages: Int = 0) {
        self.index = index
        self.hash = hash
        self.enabled = enabled
        self.name = name
        self.type = type
        self.macroPages = macroPages
    }

    var bytes: [UInt8] {
        [UInt8(min(max(index, 0), 127))] + hash.field(8) + [enabled ? 1 : 0] + RotoSysEx.encodeName(name)
            + [type.rawValue, UInt8(min(max(macroPages, 0), 127))]
    }
}

/// A parameter, as LEARN PARAM describes it to the Roto-Control.
public struct RotoParameterDetails: Equatable, Sendable {
    /// The largest number of steps.
    public static let maximumSteps = 24
    /// The largest number of steps that may carry step names.
    public static let maximumNamedSteps = 16

    /// The parameter's index in its plugin.
    public var index: Int
    /// The parameter's hash (6 bytes).
    public var hash: RotoHash
    /// Whether the parameter is a macro parameter.
    public var isMacro: Bool
    /// A center detent (knobs only). When set, `steps` is ignored by the Roto-Control.
    public var centerIndent: Bool
    /// The number of steps: 0 for a continuous parameter, otherwise 2–24.
    public var steps: Int
    /// The current position, 0–16383.
    public var position: Int
    /// The name; at most 12 characters are shown.
    public var name: String
    /// A name for each step, sent only when there are 2–16 steps. Missing names are sent empty.
    public var stepNames: [String]

    /// Makes a parameter's details. `steps` outside 2–24 becomes 0 (continuous), or 24.
    public init(index: Int, hash: RotoHash, name: String, position: Int, isMacro: Bool = false,
                centerIndent: Bool = false, steps: Int = 0, stepNames: [String] = []) {
        self.index = index
        self.hash = hash
        self.name = name
        self.position = position
        self.isMacro = isMacro
        self.centerIndent = centerIndent
        self.steps = steps < 2 ? 0 : min(steps, Self.maximumSteps)
        self.stepNames = stepNames
    }

    /// The step a stepped switch's value stands for (0-based), for a parameter of `steps` steps.
    /// Test 2 observed 0 and 127 for two steps, and 42, 84, 127, and 0 for four
    /// (docs/ROTO-CONTROL.md, section 4a): each step an even share of 0–127, rounded down. This
    /// inverse rounds to the nearest step. Returns 0 for a continuous parameter.
    public static func step(forSwitchValue value: UInt8, steps: Int) -> Int {
        guard steps >= 2 else { return 0 }
        let count = min(steps, maximumSteps)
        return min((Int(value & 0x7F) * (count - 1) + 63) / 127, count - 1)
    }

    var bytes: [UInt8] {
        // Clamped here as well as in init, because `steps` is a public var.
        let stepCount = steps < 2 ? 0 : min(steps, Self.maximumSteps)
        var data = RotoSysEx.encode14(index) + hash.field(6)
        data += [isMacro ? 1 : 0, centerIndent ? 1 : 0, UInt8(stepCount)]
        data += RotoSysEx.encode14(position) + RotoSysEx.encodeName(name)
        if stepCount >= 2 && stepCount <= Self.maximumNamedSteps {
            for step in 0..<stepCount {
                data += RotoSysEx.encodeName(step < stepNames.count ? stepNames[step] : "")
            }
        }
        return data
    }
}

/// A mapping the Roto-Control reports with CONTROL MAPPED.
public struct RotoControlMapping: Equatable, Sendable {
    /// The parameter's index, as the host gave it in LEARN PARAM.
    public var parameterIndex: Int
    /// The parameter's hash (6 bytes), as the host gave it.
    public var parameterHash: RotoHash
    /// A knob or a switch.
    public var kind: RotoControlKind
    /// The control's index on the current page (0–7).
    public var control: Int
    /// Whether the parameter is a macro parameter.
    public var isMacro: Bool

    /// Makes a mapping.
    public init(parameterIndex: Int, parameterHash: RotoHash, kind: RotoControlKind, control: Int, isMacro: Bool) {
        self.parameterIndex = parameterIndex
        self.parameterHash = parameterHash
        self.kind = kind
        self.control = control
        self.isMacro = isMacro
    }
}
