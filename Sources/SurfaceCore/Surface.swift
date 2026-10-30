import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif
#if canImport(TotalMixOSC)
import TotalMixOSC
#endif

/// A name for one connected surface, chosen by the app (e.g., "roto-1").
public struct SurfaceID: Hashable, Sendable, CustomStringConvertible {
    /// The name.
    public var rawValue: String

    /// A surface's name.
    public init(_ rawValue: String) { self.rawValue = rawValue }

    public var description: String { rawValue }
}

/// How a surface's knobs or faders follow values that change in TotalMix.
public enum ControlFeel: Hashable, Sendable {
    /// The control shows TotalMix's value itself: a motorized knob or fader, or an endless encoder
    /// with an LED ring. The core sends it every value.
    case follows
    /// The control stays where the hand left it (e.g., a fader without a motor). After TotalMix's
    /// value changes, the control does nothing until it reaches that value ("pickup").
    case pickup
}

/// What one surface has. The core assumes nothing else about it.
public struct SurfaceCapabilities: Hashable, Sendable {
    /// Strips (columns of controls) shown at once.
    public var stripCount: Int
    /// How the strips' knobs or faders follow TotalMix.
    public var feel: ControlFeel
    /// Whether each strip has a switch.
    public var hasSwitches: Bool
    /// Whether each strip has a level meter.
    public var hasMeters: Bool
    /// A move larger than this, as a fraction of the control's range, in one message, is taken as
    /// a glitch and ignored. On the Roto-Control a knob turned past its end has been observed to
    /// report a jump across most of its range (docs/ROTO-CONTROL.md); `nil` for no guard.
    public var jumpGuard: Double?
    /// For pickup controls: how close to TotalMix's value, as a fraction of the range, counts as
    /// reaching it.
    public var pickupWindow: Double

    /// A surface's capabilities.
    public init(stripCount: Int, feel: ControlFeel, hasSwitches: Bool = true, hasMeters: Bool = false,
                jumpGuard: Double? = nil, pickupWindow: Double = 0.02) {
        self.stripCount = stripCount
        self.feel = feel
        self.hasSwitches = hasSwitches
        self.hasMeters = hasMeters
        self.jumpGuard = jumpGuard
        self.pickupWindow = pickupWindow
    }
}

/// What a surface's strips show.
public enum SurfaceMode: Hashable, Sendable {
    /// One channel per strip, from `first` (an index into the view's channels). Every knob has the
    /// same function, and every switch.
    case strips(view: ViewKind, first: Int, knob: KnobFunction, switch: SwitchFunction)
    /// One channel across the strips (the Roto-Control's single-track mode). For a source the
    /// knobs are its level and pan in the home submix, then its sends, from slot `first`; the first
    /// two switches are its mute and PFL. For an output the knobs are its level and pan.
    case focus(channel: ChannelRef, first: Int)

    /// The default: the sources, from the first, knobs at level and switches at mute.
    public static let standard = SurfaceMode.strips(view: .sources, first: 0, knob: .level, switch: .mute)
}

/// What one strip shows, apart from its values.
public struct StripInfo: Hashable, Sendable {
    /// The channel on the strip.
    public var channel: ChannelRef
    /// The channel's name, or a stand-in such as "input 3" before TotalMix has sent one.
    public var name: String
    /// TotalMix's color index for the channel, if TotalMix has sent one.
    public var color: Int?
    /// Whether the channel is a stereo pair.
    public var stereo: Bool
    /// What the knob does, in a few words: the submix's name for a level or send, "Pan" for a pan.
    /// Empty when the knob does nothing.
    public var knobLabel: String
    /// What the switch does ("Mute", "PFL", "Solo"), or empty when it does nothing.
    public var switchLabel: String

    /// A strip's description.
    public init(channel: ChannelRef, name: String, color: Int?, stereo: Bool, knobLabel: String, switchLabel: String) {
        self.channel = channel
        self.name = name
        self.color = color
        self.stereo = stereo
        self.knobLabel = knobLabel
        self.switchLabel = switchLabel
    }
}

/// One change for a surface's driver to show.
public enum SurfaceUpdate: Hashable, Sendable {
    /// Where the strips are in their view: the index of the first strip's channel, and how many
    /// channels (or, in focus mode, knob slots) there are.
    case page(first: Int, count: Int)
    /// A strip's channel, name, color, and labels; `nil` for a blank strip.
    case strip(index: Int, info: StripInfo?)
    /// A knob's position, 0…1 (a pan's −1…+1 is scaled to 0…1, with the center at 0.5); `nil`
    /// when the knob does nothing.
    case knob(index: Int, value: Double?)
    /// A knob's value as text, e.g., "-6.0 dB", "off", "L25".
    case valueText(index: Int, text: String)
    /// A switch's light: on or off.
    case switchState(index: Int, on: Bool)
    /// A strip's meter, 0…127 (see `MeterScale`).
    case meter(index: Int, value: Int)
}

/// What the core produces in answer to one call: messages for TotalMix, and updates for each surface.
public struct CoreOutput: Equatable, Sendable {
    /// Messages to send to TotalMix, in order.
    public var messages: [OSCMessage] = []
    /// Updates for each surface, in order.
    public var updates: [SurfaceID: [SurfaceUpdate]] = [:]

    /// Nothing to send.
    public init() {}

    /// Whether there is nothing to send.
    public var isEmpty: Bool { messages.isEmpty && updates.values.allSatisfy(\.isEmpty) }

    /// Appends another output's messages and updates.
    public mutating func append(_ other: CoreOutput) {
        messages += other.messages
        for (id, list) in other.updates { updates[id, default: []] += list }
    }

    mutating func add(_ update: SurfaceUpdate, for id: SurfaceID) {
        updates[id, default: []].append(update)
    }
}
