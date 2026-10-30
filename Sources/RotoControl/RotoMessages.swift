import Foundation

/// Which tracks all-tracks mode shows.
public enum RotoTrackSet: UInt8, Sendable {
    /// Audio tracks.
    case audio = 0x00
    /// Master and return tracks.
    case masterReturn = 0x01
}

/// What the eight knobs control in all-tracks mode.
public enum RotoKnobMode: UInt8, Sendable {
    /// Each track's level.
    case level = 0x00
    /// Each track's pan.
    case pan = 0x01
    /// One send of each track.
    case send = 0x02
}

/// What the eight switches control in all-tracks mode.
public enum RotoSwitchMode: UInt8, Sendable {
    /// Mute.
    case mute = 0x00
    /// Solo.
    case solo = 0x01
    /// Record arm.
    case arm = 0x02
}

/// The settings SET MIX ALL TRACKS MODE reports.
public struct RotoAllTracksMode: Equatable, Sendable {
    /// Which tracks are shown.
    public var trackSet: RotoTrackSet
    /// What the knobs control.
    public var knobMode: RotoKnobMode
    /// What the switches control.
    public var switchMode: RotoSwitchMode
    /// The 0-based send the knobs control when `knobMode` is `.send`.
    public var sendIndex: Int

    /// Makes the settings.
    public init(trackSet: RotoTrackSet, knobMode: RotoKnobMode, switchMode: RotoSwitchMode, sendIndex: Int) {
        self.trackSet = trackSet
        self.knobMode = knobMode
        self.switchMode = switchMode
        self.sendIndex = sendIndex
    }
}

/// A message from the Roto-Control (docs/ROTO-CONTROL.md, sections 3 and 4).
public enum RotoIncoming: Equatable, Sendable {
    /// PING DAW (`0A 02`): the host should answer with DAW PING RESPONSE.
    case pingDAW
    /// ROTO-DAW CONNECTED (`0A 0C`): the host may now send other commands.
    case connected
    /// SET FIRST TRACK (`0A 06`): the user paged the tracks; a multiple of 8.
    case setFirstTrack(Int)
    /// ROTO SELECT TRACK (`0A 09`): the user selected a track.
    case selectTrack(Int)
    /// REQUEST TRANSPORT STATUS (`0A 0A`).
    case requestTransportStatus
    /// ROTO FW VERSION (`0A 0E`): major, minor, and patch, and the short Git commit.
    case firmwareVersion(major: Int, minor: Int, patch: Int, commit: String)
    /// ROTO SYSEX API VERSION (`0A 10`).
    case sysExAPIVersion(major: Int, minor: Int)
    /// ROTO PAGE LEFT (`0A 14`); sent only to a host that claims to be Logic.
    case pageLeft
    /// ROTO PAGE RIGHT (`0A 15`); sent only to a host that claims to be Logic.
    case pageRight
    /// SET PLUGIN MODE (`0B 01`): the user left MIX mode for PLUGIN mode.
    case pluginMode
    /// SET MIX ALL TRACKS MODE (`0C 01`).
    case allTracksMode(RotoAllTracksMode)
    /// SET MIX TRACK MODE (`0C 02`): single-track mode, with the page of track controls as sent.
    /// The SysEx doc gives it as a multiple of 8; Ableton's and Bitwig's integrations read it as a
    /// page number (docs/ROTO-CONTROL.md, section 4). See `RotoPageNumbering`.
    case singleTrackMode(controlPage: Int)
    /// SET ALL TRACKS MODE (`0C 05`): the user switched the set of tracks.
    case trackSet(RotoTrackSet)
    /// TOGGLE TRACK GROUPING (`0C 06`), for a track.
    case toggleTrackGrouping(Int)
    /// REQUEST SEND TRACK NAMES (`0C 07`), for the block holding a send index.
    case requestSendNames(sendIndex: Int)
    /// Any other message, or one whose data did not decode.
    case other(group: UInt8, command: UInt8, data: [UInt8])

    /// Decodes a complete SysEx message (`F0` … `F7`), or returns `nil` if it is not a
    /// Roto-Control message.
    public init?(sysEx bytes: [UInt8]) {
        guard let (group, command, data) = RotoSysEx.unframe(bytes) else { return nil }
        self = RotoIncoming.decode(group: group, command: command, data: data)
            ?? .other(group: group, command: command, data: data)
    }

    private static func decode(group: UInt8, command: UInt8, data: [UInt8]) -> RotoIncoming? {
        func index(at offset: Int = 0) -> Int? {
            data.count >= offset + 2 ? RotoSysEx.decode14(data[offset], data[offset + 1]) : nil
        }
        switch (group, command) {
        case (0x0A, 0x02): return .pingDAW
        case (0x0A, 0x0C): return .connected
        case (0x0A, 0x06): return index().map { .setFirstTrack($0) }
        case (0x0A, 0x09): return index().map { .selectTrack($0) }
        case (0x0A, 0x0A): return .requestTransportStatus
        case (0x0A, 0x0E):
            guard data.count >= 3 else { return nil }
            return .firmwareVersion(major: Int(data[0]), minor: Int(data[1]), patch: Int(data[2]),
                                    commit: RotoSysEx.decodeName(data.dropFirst(3)))
        case (0x0A, 0x10):
            guard data.count >= 2 else { return nil }
            return .sysExAPIVersion(major: Int(data[0]), minor: Int(data[1]))
        case (0x0A, 0x14): return .pageLeft
        case (0x0A, 0x15): return .pageRight
        case (0x0B, 0x01): return .pluginMode
        case (0x0C, 0x01):
            guard data.count >= 4,
                  let set = RotoTrackSet(rawValue: data[0]),
                  let knobs = RotoKnobMode(rawValue: data[1]),
                  let switches = RotoSwitchMode(rawValue: data[2]) else { return nil }
            return .allTracksMode(RotoAllTracksMode(trackSet: set, knobMode: knobs, switchMode: switches,
                                                    sendIndex: Int(data[3])))
        case (0x0C, 0x02):
            guard let page = data.first else { return nil }
            return .singleTrackMode(controlPage: Int(page))
        case (0x0C, 0x05):
            guard let raw = data.first, let set = RotoTrackSet(rawValue: raw) else { return nil }
            return .trackSet(set)
        case (0x0C, 0x06): return index().map { .toggleTrackGrouping($0) }
        case (0x0C, 0x07):
            guard let send = data.first else { return nil }
            return .requestSendNames(sendIndex: Int(send))
        default: return nil
        }
    }
}

/// A track as TRACK DETAILS and DAW SELECT TRACK describe it.
public struct RotoTrackDetails: Equatable, Sendable {
    /// The track's index.
    public var index: Int
    /// The name; at most 12 characters are shown.
    public var name: String
    /// An index (0–82) into the Roto-Control's color table (the SysEx doc's Appendix A).
    public var colorScheme: UInt8
    /// Whether the track is grouped.
    public var grouped: Bool

    /// Makes a track's details.
    public init(index: Int, name: String, colorScheme: UInt8, grouped: Bool = false) {
        self.index = index
        self.name = name
        self.colorScheme = colorScheme
        self.grouped = grouped
    }

    var bytes: [UInt8] {
        RotoSysEx.encode14(index) + RotoSysEx.encodeName(name) + [min(colorScheme, 82), grouped ? 1 : 0]
    }
}

/// An RGB color, for the commands that take one.
public struct RotoColor: Equatable, Sendable {
    /// Red, 0–255.
    public var red: UInt8
    /// Green, 0–255.
    public var green: UInt8
    /// Blue, 0–255.
    public var blue: UInt8

    /// Makes a color.
    public init(red: UInt8, green: UInt8, blue: UInt8) {
        self.red = red
        self.green = green
        self.blue = blue
    }

    var bytes: [UInt8] {
        RotoSysEx.encodeColorComponent(red) + RotoSysEx.encodeColorComponent(green)
            + RotoSysEx.encodeColorComponent(blue)
    }
}

/// The flags of TRANSPORT STATUS. Stop has no flag: the SysEx doc says it is always off.
public struct RotoTransportStatus: Equatable, Sendable {
    /// Playing.
    public var play = false
    /// Recording.
    public var record = false
    /// Session recording.
    public var sessionRecord = false
    /// Looping.
    public var loop = false
    /// Punch-in on.
    public var punchIn = false
    /// Punch-out on.
    public var punchOut = false
    /// Re-enable automation lit.
    public var reenableAutomation = false

    /// Makes a status with every flag off.
    public init() {}

    var bytes: [UInt8] {
        [play, false, record, sessionRecord, loop, punchIn, punchOut, reenableAutomation].map { $0 ? 1 : 0 }
    }
}

/// How SET MIX TRACK MODE numbers its pages. The SysEx doc and Melbourne Instruments' integrations
/// disagree, and which one the Roto-Control sends is untested (docs/ROTO-CONTROL.md, section 8).
public enum RotoPageNumbering: Sendable {
    /// 0, 8, 16, …, as the SysEx doc says.
    case multiplesOf8
    /// 0, 1, 2, …, as Ableton's and Bitwig's integrations read it.
    case pageNumbers
}

/// The kind of control SHOW CONTROL VALUE writes to.
public enum RotoControlKind: UInt8, Sendable {
    /// A knob's screen.
    case knob = 0x00
    /// A switch's screen.
    case `switch` = 0x01
}

/// A message to the Roto-Control (docs/ROTO-CONTROL.md, sections 3 and 4).
public enum RotoOutgoing: Equatable, Sendable {
    /// DAW STARTED (`0A 01`).
    case dawStarted
    /// DAW PING RESPONSE (`0A 03`), naming the DAW the host claims to be.
    case pingResponse(RotoHostType)
    /// NUM TRACKS (`0A 04`).
    case trackCount(Int)
    /// FIRST TRACK (`0A 05`): the current page, a multiple of 8.
    case firstTrack(Int)
    /// TRACK DETAILS (`0A 07`), or SET TRACK DETAILS (`0A 11`) when `immediate`.
    case trackDetails(RotoTrackDetails, immediate: Bool)
    /// TRACK DETAILS END (`0A 08`).
    case trackDetailsEnd
    /// RESET TRACK DETAILS (`0A 12`): clears a track's screen.
    case resetTrackDetails(Int)
    /// SET TRACK COLOUR (`0A 13`).
    case trackColor(index: Int, RotoColor)
    /// TRANSPORT STATUS (`0A 0B`).
    case transportStatus(RotoTransportStatus)
    /// REQUEST ROTO FW VERSION (`0A 0D`).
    case requestFirmwareVersion
    /// REQUEST ROTO SYSEX API VERSION (`0A 0F`).
    case requestSysExAPIVersion
    /// SET CURRENT TRACK NAME (`0A 16`).
    case currentTrackName(String)
    /// SET CURRENT TRACK COLOUR (`0A 17`).
    case currentTrackColor(RotoColor)
    /// SHOW CONTROL VALUE (`0A 18`): text on a control's screen (control 0–7) until a timeout.
    case showValue(RotoControlKind, control: Int, text: String)
    /// NUM SEND TRACKS (`0C 03`).
    case sendCount(Int)
    /// DAW SELECT TRACK (`0C 04`).
    case selectTrack(RotoTrackDetails)
    /// SEND TRACK NAMES (`0C 08`): up to eight names from `start`; missing names are sent empty.
    case sendNames(start: Int, names: [String])
    /// REFRESH MIX MODE (`0C 09`).
    case refreshMixMode
    /// DAW SELECT FOCUS TRACK (`0C 0A`).
    case selectFocusTrack(index: Int, RotoColor)
    /// SET MIX VU METER THRESHOLDS (`0C 0B`), each clamped to 0–127. The SysEx doc requires red
    /// above yellow; the caller must ensure it.
    case meterThresholds(yellow: UInt8, red: UInt8)
    /// `0C 0C`, eight flags, one per track of the page. Not in the SysEx doc: Ableton's integration
    /// sends it, and the inference is that `false` dims a track's meter (docs/ROTO-CONTROL.md,
    /// section 4).
    case meterStates([Bool])

    /// The complete SysEx message.
    public var bytes: [UInt8] {
        switch self {
        case .dawStarted:
            return RotoSysEx.frame(.general, 0x01)
        case .pingResponse(let type):
            return RotoSysEx.frame(.general, 0x03, [type.rawValue])
        case .trackCount(let count):
            return RotoSysEx.frame(.general, 0x04, RotoSysEx.encode14(count))
        case .firstTrack(let first):
            return RotoSysEx.frame(.general, 0x05, RotoSysEx.encode14(first))
        case .trackDetails(let details, let immediate):
            return RotoSysEx.frame(.general, immediate ? 0x11 : 0x07, details.bytes)
        case .trackDetailsEnd:
            return RotoSysEx.frame(.general, 0x08)
        case .resetTrackDetails(let index):
            return RotoSysEx.frame(.general, 0x12, RotoSysEx.encode14(index))
        case .trackColor(let index, let color):
            return RotoSysEx.frame(.general, 0x13, RotoSysEx.encode14(index) + color.bytes)
        case .transportStatus(let status):
            return RotoSysEx.frame(.general, 0x0B, status.bytes)
        case .requestFirmwareVersion:
            return RotoSysEx.frame(.general, 0x0D)
        case .requestSysExAPIVersion:
            return RotoSysEx.frame(.general, 0x0F)
        case .currentTrackName(let name):
            return RotoSysEx.frame(.general, 0x16, RotoSysEx.encodeName(name))
        case .currentTrackColor(let color):
            return RotoSysEx.frame(.general, 0x17, color.bytes)
        case .showValue(let kind, let control, let text):
            return RotoSysEx.frame(.general, 0x18,
                                   [kind.rawValue, UInt8(min(max(control, 0), 7))] + RotoSysEx.encodeName(text))
        case .sendCount(let count):
            return RotoSysEx.frame(.mix, 0x03, [UInt8(min(max(count, 0), 127))])
        case .selectTrack(let details):
            return RotoSysEx.frame(.mix, 0x04, details.bytes)
        case .sendNames(let start, let names):
            let padded = (0..<8).map { $0 < names.count ? RotoSysEx.encodeName(names[$0]) : RotoSysEx.encodeName("") }
            return RotoSysEx.frame(.mix, 0x08, [UInt8(min(max(start, 0), 127))] + padded.flatMap { $0 })
        case .refreshMixMode:
            return RotoSysEx.frame(.mix, 0x09)
        case .selectFocusTrack(let index, let color):
            return RotoSysEx.frame(.mix, 0x0A, RotoSysEx.encode14(index) + color.bytes)
        case .meterThresholds(let yellow, let red):
            return RotoSysEx.frame(.mix, 0x0B, [min(yellow, 127), min(red, 127)])
        case .meterStates(let states):
            let flags = (0..<8).map { $0 < states.count && states[$0] ? UInt8(1) : 0 }
            return RotoSysEx.frame(.mix, 0x0C, flags)
        }
    }

    /// The first send of the block of eight SEND TRACK NAMES should start at, after SET MIX ALL
    /// TRACKS MODE or REQUEST SEND TRACK NAMES: the multiple of 8 at or below the send index.
    public static func sendNamesStart(forSendIndex sendIndex: Int) -> Int {
        max(sendIndex, 0) / 8 * 8
    }

    /// The first send of the block after SET MIX TRACK MODE, for the page value as the Roto-Control
    /// sent it. Both numberings describe the same layout: level, pan, and six sends on the first
    /// page, and eight sends on each later page (docs/ROTO-CONTROL.md, section 4).
    ///
    /// - `.multiplesOf8`: the SysEx doc's examples (pages 0, 8, and 16 start at sends 0, 6, and
    ///   14) give the page minus 2; the formula is an inference from them.
    /// - `.pageNumbers`: Ableton's integration starts page 1 and later at 6 + (page − 1) × 8.
    public static func sendNamesStart(forControlPage page: Int, numbering: RotoPageNumbering) -> Int {
        guard page > 0 else { return 0 }
        switch numbering {
        case .multiplesOf8: return max(page - 2, 0)
        case .pageNumbers: return 6 + (page - 1) * 8
        }
    }
}
