// sbdev roto: talks to a Roto-Control over MIDI, for the tests in docs/ROTO-CONTROL.md section 8.

import Foundation
import RotoControl
import MIDITransport
import TotalMixOSC

let rotoUsage = """
    Usage:
      sbdev roto ports
          Lists the MIDI sources and destinations.
      sbdev roto [--port NAME | --in NAME --out NAME] [--type ableton|bitwig|logic]
                 [--setup full|none] [--tracks N] [--sends N] [--gap MS] [--raw]
          Connects to the Roto-Control, runs the handshake, and prints everything the
          Roto-Control sends, with the time since starting. Then reads commands from the
          keyboard (type `help`).
          --port matches a source and a destination by name (default "Roto"; an exact name, or
          a part that matches only one port). --in and --out name them separately.
          --type is the DAW type claimed in DAW PING RESPONSE (default bitwig).
          --setup full (default) answers CONNECTED with the versions requests, the meter
          thresholds, NUM TRACKS, FIRST TRACK, and a page of TRACK DETAILS, and answers the
          Roto-Control's requests; --setup none sends only the handshake.
          --tracks is the number of tracks claimed (default 16); --sends the number of sends
          (default 16). --gap is the pause after each
          SysEx message sent (default 5 ms, as Ableton's integration waits). --raw also prints
          the bytes of every message in both directions.
    """

let rotoCommandHelp = """
    Commands (knobs, switches, and tracks on the page count from 1):
      knob K VALUE      move knob K: a 14-bit position (0–16383), a fraction with a point
                        (0.5), or a TotalMix gain (-6dB, 0dB) through the fader curve
      sweep K [MS]      move knob K from 0 to 16383 in 33 steps over MS (default 2000)
      led K on|off      light switch K, or turn it off
      meter K L [R]     set track K's meters (0–127; R defaults to L)
      show K TEXT       SHOW CONTROL VALUE on knob K's screen
      showsw K TEXT     SHOW CONTROL VALUE on switch K's screen
      name K TEXT       SET TRACK DETAILS for track K of the page, with a new name
      tracks N          send NUM TRACKS N, then FIRST TRACK 0 and that page's TRACK DETAILS
      sends N           send NUM SEND TRACKS N
      thresholds Y R    SET MIX VU METER THRESHOLDS
      refresh           REFRESH MIX MODE
    PLUGIN mode (stand-in plugins and parameters; `plugins` lists them):
      plugins           list the plugins and the selected plugin's parameters
      select P          DAW SELECT PLUGIN P (forced)
      learn N           LEARN PARAM for parameter N of the selected plugin (for learn mode,
                        or to try mapping without it)
      ctl K NAME        SET PLUGIN CONTROL DETAILS: name knob K (1–64)
      ctlsw K NAME      the same for switch K
      unmap K           UNMAP CONTROL knob K;  unmapsw K for switch K
      hex BYTES         send raw bytes, e.g. hex F0 00 22 03 02 0A 0D F7
      restart           start the handshake again (DAW STARTED)
      quit
    """

struct RotoOptions {
    var inName = "Roto"
    var outName = "Roto"
    var hostType = RotoHostType.bitwig
    var fullSetup = true
    var trackCount = 16
    var sendCount = 16
    var gapMilliseconds = 5
    var raw = false
}

func parseRotoOptions(_ arguments: ArraySlice<String>) -> RotoOptions {
    var options = RotoOptions()
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(rotoUsage)") }
        return text
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--port": let name = value(argument); options.inName = name; options.outName = name
        case "--in": options.inName = value(argument)
        case "--out": options.outName = value(argument)
        case "--type":
            switch value(argument).lowercased() {
            case "ableton", "1": options.hostType = .ableton
            case "bitwig", "2": options.hostType = .bitwig
            case "logic", "3": options.hostType = .logic
            default: fail("--type is ableton, bitwig, or logic.")
            }
        case "--setup":
            switch value(argument) {
            case "full": options.fullSetup = true
            case "none": options.fullSetup = false
            default: fail("--setup is full or none.")
            }
        case "--tracks":
            guard let count = Int(value(argument)), (0...16383).contains(count) else { fail("--tracks needs a number from 0 to 16383.") }
            options.trackCount = count
        case "--sends":
            guard let count = Int(value(argument)), (0...127).contains(count) else { fail("--sends needs a number from 0 to 127.") }
            options.sendCount = count
        case "--gap":
            guard let gap = Int(value(argument)), gap >= 0 else { fail("--gap needs a number of milliseconds.") }
            options.gapMilliseconds = gap
        case "--raw": options.raw = true
        case "-h", "--help": print(rotoUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(rotoUsage)")
        }
    }
    return options
}

func hex(_ bytes: [UInt8]) -> String {
    bytes.map { String(format: "%02X", $0) }.joined(separator: " ")
}

func describe(_ message: RotoIncoming) -> String {
    switch message {
    case .pingDAW: return "PING DAW"
    case .connected: return "ROTO-DAW CONNECTED"
    case .setFirstTrack(let first): return "SET FIRST TRACK \(first)"
    case .selectTrack(let index): return "ROTO SELECT TRACK \(index)"
    case .requestTransportStatus: return "REQUEST TRANSPORT STATUS"
    case .firmwareVersion(let major, let minor, let patch, let commit): return "ROTO FW VERSION \(major).\(minor).\(patch) (\(commit))"
    case .sysExAPIVersion(let major, let minor): return "ROTO SYSEX API VERSION \(major).\(minor)"
    case .pageLeft: return "ROTO PAGE LEFT"
    case .pageRight: return "ROTO PAGE RIGHT"
    case .pluginMode: return "SET PLUGIN MODE"
    case .setFirstPlugin(let first): return "SET FIRST PLUGIN \(first)"
    case .selectPlugin(let index): return "ROTO SELECT PLUGIN \(index + 1) of the page"
    case .learnMode(let on): return "SET DEVICE LEARN \(on ? "on" : "off")"
    case .controlMapped(let mapping):
        return "CONTROL MAPPED \(mapping.kind) \(mapping.control + 1) → parameter \(mapping.parameterIndex) [hash \(hex(mapping.parameterHash.bytes))]\(mapping.isMacro ? " (macro)" : "")"
    case .pluginEnabled(let index, let enabled): return "SET PLUGIN ENABLED \(index + 1) \(enabled ? "on" : "off")"
    case .pluginsLocked(let locked): return "SET PLUGINS LOCK \(locked ? "on" : "off")"
    case .macroPage(let page): return "MACRO PLUGIN PAGE INDEX \(page)"
    case .controlLearned(let kind, let control): return "CONTROL LEARNED \(kind) \(control + 1)"
    case .toggleRemotePage: return "TOGGLE REMOTE PAGE"
    case .allTracksMode(let mode):
        return "SET MIX ALL TRACKS MODE: \(mode.trackSet) tracks, knobs \(mode.knobMode), switches \(mode.switchMode), send index \(mode.sendIndex)"
    case .singleTrackMode(let page):
        let asMultiple = RotoOutgoing.sendNamesStart(forControlPage: page, numbering: .multiplesOf8)
        let asNumber = RotoOutgoing.sendNamesStart(forControlPage: page, numbering: .pageNumbers)
        return "SET MIX TRACK MODE, page value \(page) (sends from \(asMultiple) if multiples of 8, from \(asNumber) if page numbers)"
    case .trackSet(let set): return "SET ALL TRACKS MODE: \(set) tracks"
    case .toggleTrackGrouping(let index): return "TOGGLE TRACK GROUPING \(index)"
    case .requestSendNames(let index): return "REQUEST SEND TRACK NAMES \(index)"
    case .other(let group, let command, let data):
        return String(format: "unknown %02X %02X", group, command) + (data.isEmpty ? "" : " data " + hex(data))
    }
}

func describe(_ event: RotoControlEvent) -> String {
    switch event {
    case .knob(let index, let position):
        let gain = gainText(FaderCurve.gainDB(position: RotoFeedback.fraction(position)))
        return "knob \(index + 1) = \(position)  (\(String(format: "%.4f", RotoFeedback.fraction(position))); as a TotalMix fader \(gain))"
    case .touch(let index, let touched): return "knob \(index + 1) \(touched ? "touched" : "released")"
    case .switch(let index, let pressed): return "switch \(index + 1) \(pressed ? "pressed" : "released")"
    case .transport(let index, let pressed): return "transport switch \(index + 1) \(pressed ? "pressed" : "released")"
    case .levelToZeroDB(let index): return "level to 0 dB (CC 64), knob \(index + 1)"
    case .otherCC(let channel, let controller, let value): return "CC \(controller) = \(value) on channel \(channel + 1)"
    }
}

func describe(_ message: RotoOutgoing) -> String {
    switch message {
    case .dawStarted: return "DAW STARTED"
    case .pingResponse(let type): return "DAW PING RESPONSE (\(type))"
    case .trackCount(let count): return "NUM TRACKS \(count)"
    case .firstTrack(let first): return "FIRST TRACK \(first)"
    case .trackDetails(let details, let immediate):
        return "\(immediate ? "SET TRACK DETAILS" : "TRACK DETAILS") \(details.index) \"\(details.name)\" scheme \(details.colorScheme)"
    case .trackDetailsEnd: return "TRACK DETAILS END"
    case .resetTrackDetails(let index): return "RESET TRACK DETAILS \(index)"
    case .trackColor(let index, let color): return "SET TRACK COLOUR \(index) \(color.red)/\(color.green)/\(color.blue)"
    case .transportStatus: return "TRANSPORT STATUS"
    case .requestFirmwareVersion: return "REQUEST ROTO FW VERSION"
    case .requestSysExAPIVersion: return "REQUEST ROTO SYSEX API VERSION"
    case .currentTrackName(let name): return "SET CURRENT TRACK NAME \"\(name)\""
    case .currentTrackColor: return "SET CURRENT TRACK COLOUR"
    case .showValue(let kind, let control, let text): return "SHOW CONTROL VALUE \(kind) \(control + 1) \"\(text)\""
    case .sendCount(let count): return "NUM SEND TRACKS \(count)"
    case .selectTrack(let details): return "DAW SELECT TRACK \(details.index)"
    case .sendNames(let start, _): return "SEND TRACK NAMES from \(start)"
    case .refreshMixMode: return "REFRESH MIX MODE"
    case .selectFocusTrack(let index, _): return "DAW SELECT FOCUS TRACK \(index)"
    case .meterThresholds(let yellow, let red): return "SET MIX VU METER THRESHOLDS \(yellow) \(red)"
    case .pluginCount(let count): return "NUM PLUGINS \(count)"
    case .firstPlugin(let first): return "FIRST PLUGIN \(first)"
    case .pluginDetails(let details): return "PLUGIN DETAILS \(details.index) \"\(details.name)\""
    case .pluginDetailsEnd: return "PLUGIN DETAILS END"
    case .dawSelectPlugin(let index, _, let force): return "DAW SELECT PLUGIN \(index)\(force ? " (forced)" : "")"
    case .learnParameter(let details):
        var text = "LEARN PARAM \(details.index) \"\(details.name)\" at \(details.position)"
        if details.centerIndent { text += ", center detent" }
        if details.steps > 0 { text += ", \(details.steps) steps" }
        return text
    case .unmapControl(let kind, let control): return "UNMAP CONTROL \(kind) \(control + 1)"
    case .mappedControlName(let index, _, let name): return "SET MAPPED CONTROL NAME \(index) \"\(name)\""
    case .controlDetails(let kind, let control, let name, _): return "SET PLUGIN CONTROL DETAILS \(kind) \(control + 1) \"\(name)\""
    case .resetControlDetails(let kind, let control): return "RESET PLUGIN CONTROL DETAILS \(kind) \(control + 1)"
    case .meterStates(let states): return "meter states \(states.map { $0 ? "1" : "0" }.joined())"
    }
}

/// One connection to the Roto-Control: the handshake, what is printed, and what is sent.
final class RotoSession: @unchecked Sendable {
    private let options: RotoOptions
    private let lock = NSLock()
    private let start = Date()
    private var handshake: RotoHandshake
    private var decoder = RotoInputDecoder()
    private var connection: MIDIConnection?
    private var firstTrack = 0
    private var selectedTrack = 0
    private var trackCount: Int
    private var knobCommandTimes: [Int: Date] = [:]
    private var sendCount: Int
    private var inPluginMode = false
    private var plugins = testPlugins
    private var firstPlugin = 0
    private var selectedPlugin = 0
    private var pendingLearn: Int?
    /// The parameter each control of the current plugin page is mapped to, by kind and control.
    private var mappings: [String: Int] = [:]

    init(options: RotoOptions) {
        self.options = options
        handshake = RotoHandshake(hostType: options.hostType)
        trackCount = options.trackCount
        sendCount = options.sendCount
    }

    func connect() {
        // Held until the handshake has started, so that input arriving meanwhile waits.
        lock.lock()
        defer { lock.unlock() }
        do {
            connection = try MIDIConnection(clientName: "sbdev", sourceName: options.inName, destinationName: options.outName) { [weak self] bytes in
                self?.received(bytes)
            }
        } catch {
            fail("\(error)")
        }
        log("Listening to \"\(connection!.source.name)\", sending to \"\(connection!.destination.name)\". Claiming \(options.hostType). Type `help` for commands.")
        send(handshake.start())
    }

    // MARK: Output

    /// Prints a line with the time since starting (or since `at`). Called with the lock held.
    private func log(_ text: String, at time: Date = Date()) {
        print(String(format: "%9.3f  ", time.timeIntervalSince(start)) + text)
        flushOutput()
    }

    /// Sends messages, printing each, and pauses after each SysEx. Called with the lock held.
    private func send(_ messages: [RotoOutgoing]) {
        for message in messages {
            sendBytes(message.bytes, label: describe(message))
        }
    }

    private func sendBytes(_ bytes: [UInt8], label: String) {
        log("→ " + label + (options.raw ? "   [\(hex(bytes))]" : ""))
        guard let connection else { log("   not sent: no connection"); return }
        do {
            try connection.send(bytes)
        } catch {
            log("   could not send: \(error)")
        }
        if bytes.first == 0xF0, options.gapMilliseconds > 0 {
            Thread.sleep(forTimeInterval: Double(options.gapMilliseconds) / 1000)
        }
    }

    // MARK: Input

    private func received(_ bytes: [UInt8]) {
        // Taken before waiting for the lock, which a reply's pauses may hold for tens of ms.
        let arrived = Date()
        lock.lock()
        defer { lock.unlock() }
        if options.raw { log("   [\(hex(bytes))]", at: arrived) }
        for input in decoder.feed(bytes) {
            switch input {
            case .message(let message):
                log("← " + describe(message), at: arrived)
                react(to: message)
            case .control(let event):
                var line = "← " + describe(event)
                if inPluginMode, let note = pluginNote(for: event) { line += "   [\(note)]" }
                if case .knob(let index, _) = event, let sent = knobCommandTimes[index] {
                    let elapsed = arrived.timeIntervalSince(sent)
                    if elapsed < 2 { line += String(format: "   [%.0f ms after a knob command]", elapsed * 1000) }
                }
                log(line, at: arrived)
            }
        }
    }

    private func react(to message: RotoIncoming) {
        let (reply, justConnected) = handshake.handle(message)
        send(reply)
        if justConnected {
            log("   handshake complete")
            if options.fullSetup {
                send([.requestFirmwareVersion, .requestSysExAPIVersion, .meterThresholds(yellow: 87, red: 113)])
                sendPage()
            }
            return
        }
        guard options.fullSetup, handshake.isConnected else { return }
        switch message {
        case .setFirstTrack(let first):
            firstTrack = first
            sendPage(countFirst: false)
        case .requestTransportStatus:
            send([.transportStatus(RotoTransportStatus())])
        case .allTracksMode(let mode):
            // Test 2: on returning to all-tracks mode the track screens are blank until the page is sent.
            send([.sendCount(sendCount), sendNames(from: RotoOutgoing.sendNamesStart(forSendIndex: mode.sendIndex))])
            sendPage(countFirst: true)
        case .selectTrack(let index):
            selectedTrack = index
        case .requestSendNames(let index):
            send([sendNames(from: RotoOutgoing.sendNamesStart(forSendIndex: index))])
        case .singleTrackMode(let page):
            // Test 2: the Roto-Control numbers these pages 0, 1, 2.
            // Test 2: the send labels are drawn on DAW SELECT TRACK, not on SEND TRACK NAMES alone.
            send([.sendCount(sendCount), sendNames(from: RotoOutgoing.sendNamesStart(forControlPage: page, numbering: .pageNumbers)),
                  .selectTrack(trackDetails(selectedTrack))])
        default:
            break
        }
        reactInPluginMode(to: message)
    }

    // MARK: PLUGIN mode

    private func key(_ kind: RotoControlKind, _ control: Int) -> String { "\(kind) \(control)" }

    private func reactInPluginMode(to message: RotoIncoming) {
        switch message {
        case .pluginMode:
            inPluginMode = true
            mappings.removeAll()
            sendPluginPage(countFirst: true)
            send([.dawSelectPlugin(index: selectedPlugin, macroPage: 0, force: false)])
        case .allTracksMode, .singleTrackMode, .trackSet:
            inPluginMode = false
        case .setFirstPlugin(let first) where first < plugins.count:
            firstPlugin = first
            sendPluginPage(countFirst: false)
        case .selectPlugin(let index) where firstPlugin + index < plugins.count:
            selectedPlugin = firstPlugin + index
            mappings.removeAll()
            log("   selected \"\(plugins[selectedPlugin].name)\"")
        case .controlMapped(let mapping):
            let plugin = plugins[selectedPlugin]
            guard let index = plugin.parameters.indices.first(where: { plugin.parameterHash($0) == mapping.parameterHash }) else {
                log("   no parameter of \"\(plugin.name)\" has that hash"); return
            }
            mappings[key(mapping.kind, mapping.control)] = index
            send([.learnParameter(plugin.parameterDetails(index))])
        case .controlLearned(let kind, let control):
            if let index = pendingLearn {
                mappings[key(kind, control)] = index
                log("   \(kind) \(control + 1) now controls \"\(plugins[selectedPlugin].parameters[index].name)\"")
            }
            pendingLearn = nil
        case .learnMode(let on):
            if on { log("   learn mode: type `learn N`, then turn or press the control to map it to") } else { pendingLearn = nil }
        default:
            break
        }
    }

    /// NUM PLUGINS (optionally), FIRST PLUGIN, and PLUGIN DETAILS for the plugins of the current page.
    private func sendPluginPage(countFirst: Bool) {
        var messages: [RotoOutgoing] = countFirst ? [.pluginCount(plugins.count)] : []
        messages.append(.firstPlugin(firstPlugin))
        for index in firstPlugin..<max(firstPlugin, min(firstPlugin + 8, plugins.count)) {
            messages.append(.pluginDetails(plugins[index].details(index: index)))
        }
        messages.append(.pluginDetailsEnd)
        send(messages)
    }

    /// The parameter a knob or switch event changed, updating its position. Called with the lock held.
    private func pluginNote(for event: RotoControlEvent) -> String? {
        switch event {
        case .knob(let control, let position):
            guard let index = mappings[key(.knob, control)] else { return "not mapped" }
            plugins[selectedPlugin].parameters[index].position = position
            return "\(plugins[selectedPlugin].name) › \(plugins[selectedPlugin].parameters[index].name)"
        case .switch(let control, _):
            guard let index = mappings[key(.switch, control)] else { return "not mapped" }
            return "\(plugins[selectedPlugin].name) › \(plugins[selectedPlugin].parameters[index].name)"
        default:
            return nil
        }
    }

    private func sendNames(from start: Int) -> RotoOutgoing {
        .sendNames(start: start, names: (start..<max(start, min(start + 8, sendCount))).map { "Send \($0 + 1)" })
    }

    /// NUM TRACKS (optionally), FIRST TRACK, and TRACK DETAILS for the tracks of the current page.
    private func sendPage(countFirst: Bool = true) {
        var messages: [RotoOutgoing] = countFirst ? [.trackCount(trackCount)] : []
        messages.append(.firstTrack(firstTrack))
        for index in firstTrack..<max(firstTrack, min(firstTrack + 8, trackCount)) {
            messages.append(.trackDetails(trackDetails(index), immediate: false))
        }
        messages.append(.trackDetailsEnd)
        send(messages)
    }

    private func trackDetails(_ index: Int, name: String? = nil) -> RotoTrackDetails {
        RotoTrackDetails(index: index, name: name ?? "Track \(index + 1)", colorScheme: UInt8((index * 11) % 83))
    }

    // MARK: Commands

    /// Runs one command typed at the keyboard. Returns false for `quit`.
    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ", omittingEmptySubsequences: true).map(String.init)
        guard let command = words.first?.lowercased() else { return true }
        func index(_ position: Int) -> Int? {
            guard words.count > position, let number = Int(words[position]), (1...8).contains(number) else { return nil }
            return number - 1
        }
        func rest(from position: Int) -> String { words.dropFirst(position).joined(separator: " ") }

        lock.lock()
        defer { lock.unlock() }
        switch command {
        case "help", "?":
            print(rotoCommandHelp)
        case "quit", "exit", "q":
            return false
        case "knob":
            guard let knob = index(1), words.count > 2, let position = knobPosition(words[2]) else {
                log("knob K VALUE: K from 1 to 8; VALUE 0–16383, a fraction such as 0.5, or a gain such as -6dB"); break
            }
            knobCommandTimes[knob] = Date()
            sendBytes(RotoFeedback.knob(knob, position: position), label: "knob \(knob + 1) to \(position)")
        case "sweep":
            guard let knob = index(1) else { log("sweep K [MS]: K from 1 to 8"); break }
            let duration = words.count > 2 ? (Double(words[2]) ?? 2000) / 1000 : 2
            for step in 0...32 {
                let position = min(step * 512, RotoSysEx.maximum14Bit)
                knobCommandTimes[knob] = Date()
                sendBytes(RotoFeedback.knob(knob, position: position), label: "knob \(knob + 1) to \(position)")
                if step < 32 {
                    lock.unlock()
                    Thread.sleep(forTimeInterval: duration / 32)
                    lock.lock()
                }
            }
        case "led":
            guard let control = index(1), words.count > 2, ["on", "off"].contains(words[2].lowercased()) else {
                log("led K on|off: K from 1 to 8"); break
            }
            let on = words[2].lowercased() == "on"
            sendBytes(RotoFeedback.switchLight(control, on: on), label: "switch \(control + 1) light \(on ? "on" : "off")")
        case "meter":
            guard let track = index(1), words.count > 2, let left = UInt8(words[2]) else { log("meter K L [R]: K from 1 to 8, L and R from 0 to 127"); break }
            let right = words.count > 3 ? UInt8(words[3]) ?? left : left
            sendBytes(RotoFeedback.meter(track, left: left, right: right), label: "meter \(track + 1) \(left)/\(right)")
        case "show", "showsw":
            guard let control = index(1) else { log("\(command) K TEXT: K from 1 to 8"); break }
            send([.showValue(command == "show" ? .knob : .switch, control: control, text: rest(from: 2))])
        case "name":
            guard let track = index(1) else { log("name K TEXT: K from 1 to 8"); break }
            send([.trackDetails(trackDetails(firstTrack + track, name: rest(from: 2)), immediate: true)])
        case "tracks":
            guard words.count > 1, let count = Int(words[1]), (0...16383).contains(count) else { log("tracks N"); break }
            trackCount = count
            firstTrack = 0
            sendPage()
        case "sends":
            guard words.count > 1, let count = Int(words[1]), (0...127).contains(count) else { log("sends N: 0 to 127"); break }
            sendCount = count
            send([.sendCount(count)])
        case "thresholds":
            guard words.count > 2, let yellow = UInt8(words[1]), let red = UInt8(words[2]) else { log("thresholds Y R"); break }
            send([.meterThresholds(yellow: yellow, red: red)])
        case "refresh":
            send([.refreshMixMode])
        case "plugins":
            for (number, plugin) in plugins.enumerated() {
                print("  \(number + 1). \(plugin.name)\(number == selectedPlugin ? "   (selected)" : "")")
            }
            for (number, parameter) in plugins[selectedPlugin].parameters.enumerated() {
                var text = "       \(number + 1). \(parameter.name) at \(parameter.position)"
                if parameter.centerIndent { text += ", center detent" }
                if parameter.steps > 0 { text += ", \(parameter.steps) steps" }
                print(text)
            }
        case "select":
            guard words.count > 1, let number = Int(words[1]), (1...plugins.count).contains(number) else { log("select P: P from 1 to \(plugins.count)"); break }
            selectedPlugin = number - 1
            mappings.removeAll()
            send([.dawSelectPlugin(index: selectedPlugin, macroPage: 0, force: true)])
        case "learn":
            let parameters = plugins[selectedPlugin].parameters
            guard words.count > 1, let number = Int(words[1]), (1...parameters.count).contains(number) else {
                log("learn N: N from 1 to \(parameters.count) (`plugins` lists them)"); break
            }
            pendingLearn = number - 1
            send([.learnParameter(plugins[selectedPlugin].parameterDetails(number - 1))])
        case "ctl", "ctlsw":
            guard words.count > 2, let number = Int(words[1]), (1...64).contains(number) else { log("\(command) K NAME: K from 1 to 64"); break }
            send([.controlDetails(command == "ctl" ? .knob : .switch, control: number - 1, name: rest(from: 2), colorScheme: 21)])
        case "unmap", "unmapsw":
            guard let control = index(1) else { log("\(command) K: K from 1 to 8"); break }
            let kind: RotoControlKind = command == "unmap" ? .knob : .switch
            mappings[key(kind, control)] = nil
            send([.unmapControl(kind, control: control)])
        case "hex":
            let bytes = words.dropFirst().compactMap { UInt8($0, radix: 16) }
            guard bytes.count == words.count - 1, !bytes.isEmpty else { log("hex BYTES: two hex digits each, e.g. hex F0 00 22 03 02 0A 0D F7"); break }
            guard UniversalPackets.bytes(fromWords: UniversalPackets.words(fromBytes: bytes)) == bytes else {
                log("hex: not sent. Give complete MIDI 1.0 messages: no running status, and SysEx from F0 to F7 with only data bytes between."); break
            }
            sendBytes(bytes, label: "raw \(hex(bytes))")
        case "restart":
            send(handshake.start())
        default:
            log("Unknown command \"\(command)\". Type `help`.")
        }
        return true
    }

    private func knobPosition(_ text: String) -> Int? {
        if text.lowercased().hasSuffix("db"), let gain = Double(text.dropLast(2)) {
            return RotoFeedback.position(FaderCurve.position(gainDB: gain))
        }
        if text.contains("."), let fraction = Double(text) { return RotoFeedback.position(fraction) }
        if let position = Int(text), (0...RotoSysEx.maximum14Bit).contains(position) { return position }
        return nil
    }

    func close() {
        connection?.close()
    }
}

func rotoPorts() -> Never {
    let sources = MIDIConnection.sources()
    let destinations = MIDIConnection.destinations()
    print("MIDI sources (what devices send):")
    for endpoint in sources { print("  \(endpoint.name)") }
    if sources.isEmpty { print("  (none)") }
    print("MIDI destinations (what devices receive):")
    for endpoint in destinations { print("  \(endpoint.name)") }
    if destinations.isEmpty { print("  (none)") }
    exit(0)
}

func roto(_ arguments: ArraySlice<String>) -> Never {
    if arguments.first == "ports" { rotoPorts() }
    let session = RotoSession(options: parseRotoOptions(arguments))
    session.connect()
    var quit = false
    while let line = readLine() {
        if !session.run(line) { quit = true; break }
    }
    if !quit, isatty(fileno(stdin)) == 0 {
        // Standard input is not a terminal and has ended: keep listening until Ctrl-C.
        while true { Thread.sleep(forTimeInterval: 60) }
    }
    session.close()
    exit(0)
}
