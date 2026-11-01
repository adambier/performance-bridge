// sbdev lcxl: talks to a Novation Launch Control XL 3 in DAW mode, for the tests in
// docs/LAUNCH-CONTROL-XL3.md.

import Foundation
import LaunchControlXL3
import MIDITransport

let lcxlUsage = """
    Usage:
      sbdev lcxl ports
          Lists the MIDI sources and destinations.
      sbdev lcxl [--port NAME | --in NAME --out NAME] [--no-touch] [--raw]
          Connects to the Launch Control XL 3's DAW port, puts it in DAW mode, turns on touch
          reports (unless --no-touch), and prints everything it sends, with the time since
          starting. Then reads commands from the keyboard (type `help`). Leaving with `quit`
          returns it to standalone mode.
          --port matches a source and a destination by name (default "LCXL3 1 DAW", from the
          names in Bitwig's setup guide; an exact name, or a part that matches only one port).
          --raw also prints the bytes of every message in both directions.
    """

let lcxlCommandHelp = """
    Controls: f1–f8 (faders), e11–e38 (encoder row 1–3, column 1–8), b11–b28 (button row 1–2,
    column 1–8), soloarm, muteselect, novation, pageup, pagedown, trackleft, trackright, record,
    play, shift. Display targets: a fader or an encoder, stationary, or overlay.
    Commands:
      color C N          light control C in palette color N (0–127)
      rgb C R G B        light control C in a color of its own (each 0–127)
      palette N          light the 16 buttons and 24 encoders in palette colors N, N+1, …
      off                turn every light off (palette color 0)
      pos C V            send position V (0–127) to a fader or an encoder
      relative R on|off  encoder row R (1–3) to relative output, or back
      pickup on|off      the faders' own pickup
      touch on|off       touch reports
      mode mixer|control|custom N
      display T A [quiet]  set up display T with arrangement A (1–4); quiet: not brought up by itself
      text T F TEXT      fill field F (from 0) of display T
      show T on|off      bring display T up, or take it down
      feature N V        send feature control N with value V;  query N  asks for its setting
      daw on|off         DAW mode on or off
      hex BYTES          send raw bytes, e.g. hex B0 25 05
      quit
    """

/// The connection, the parser, and what was asked for. Every change happens with the lock held.
final class LaunchControlSession: @unchecked Sendable {
    private let lock = NSLock()
    private var parser = LaunchControlParser()
    private var connection: MIDIConnection?
    private let start = Date()
    private let inName: String
    private let outName: String
    private let raw: Bool
    private let touch: Bool

    init(inName: String, outName: String, raw: Bool, touch: Bool) {
        self.inName = inName
        self.outName = outName
        self.raw = raw
        self.touch = touch
    }

    private func stamp() -> String {
        String(format: "%9.3f  ", Date().timeIntervalSince(start))
    }

    func connect() {
        do {
            connection = try MIDIConnection(clientName: "sbdev lcxl", sourceName: inName, destinationName: outName) { [weak self] bytes in
                self?.received(bytes)
            }
        } catch {
            fail("\(error)\n\n\(lcxlUsage)")
        }
        guard let connection else { return }
        print("Connected: from \"\(connection.source.name)\", to \"\(connection.destination.name)\". Type `help` for commands.")
        send(LaunchControlOutgoing.dawMode(true), "DAW mode on")
        if touch { send(LaunchControlOutgoing.touchEvents(true), "touch reports on") }
        flushOutput()
    }

    private func received(_ bytes: [UInt8]) {
        lock.lock()
        defer { lock.unlock() }
        if raw { print(stamp() + "<- " + hex(bytes)) }
        for event in parser.feed(bytes) { print(stamp() + describeLaunchControl(event)) }
        flushOutput()
    }

    func send(_ bytes: [UInt8]?, _ what: String) {
        guard let bytes else { print("Not sent: \(what) doesn't apply to that control."); return }
        do {
            try connection?.send(bytes)
            print(stamp() + "-> " + what + (raw ? "  [" + hex(bytes) + "]" : ""))
        } catch {
            print("Could not send \(what): \(error)")
        }
    }

    /// Runs one command line; false to quit.
    func run(_ line: String) -> Bool {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first?.lowercased() else { return true }
        let rest = Array(words.dropFirst())
        func number(_ index: Int, _ range: ClosedRange<Int> = 0...127) -> Int? {
            guard rest.indices.contains(index), let value = Int(rest[index]), range.contains(value) else { return nil }
            return value
        }
        func on(_ index: Int) -> Bool? {
            guard rest.indices.contains(index) else { return nil }
            switch rest[index].lowercased() {
            case "on": return true
            case "off": return false
            default: return nil
            }
        }
        switch command {
        case "help": print(lcxlCommandHelp)
        case "quit", "exit": return false
        case "color":
            guard let element = rest.first.flatMap(parseLaunchControlElement), let index = number(1) else { print("color C N"); break }
            send(LaunchControlOutgoing.color(element, UInt8(index)), "color \(rest[0]) \(index)")
        case "rgb":
            guard let element = rest.first.flatMap(parseLaunchControlElement), let r = number(1), let g = number(2), let b = number(3) else {
                print("rgb C R G B"); break
            }
            send(LaunchControlOutgoing.rgb(element, red: UInt8(r), green: UInt8(g), blue: UInt8(b)), "rgb \(rest[0]) \(r) \(g) \(b)")
        case "palette", "off":
            let first = command == "off" ? 0 : (number(0) ?? 0)
            let lit = LaunchControlElement.all.filter { $0.hasLight && ($0.isContinuous || ($0.controlNumber >= 37 && $0.controlNumber <= 52)) }
            for (offset, element) in lit.enumerated() {
                let index = command == "off" ? 0 : (first + offset) % 128
                if let bytes = LaunchControlOutgoing.color(element, UInt8(index)) { try? connection?.send(bytes) }
            }
            print(stamp() + "-> " + (command == "off" ? "lights off" : "palette from \(first): encoders \(first)–\((first + 23) % 128), then buttons \((first + 24) % 128)–\((first + 39) % 128)"))
        case "pos":
            guard let element = rest.first.flatMap(parseLaunchControlElement), let value = number(1) else { print("pos C V"); break }
            send(LaunchControlOutgoing.position(element, UInt8(value)), "position \(rest[0]) \(value)")
        case "relative":
            guard let row = number(0, 1...3), let value = on(1) else { print("relative R on|off"); break }
            send(LaunchControlOutgoing.relativeEncoders(row: row - 1, value), "encoder row \(row) relative \(value ? "on" : "off")")
        case "pickup":
            guard let value = on(0) else { print("pickup on|off"); break }
            send(LaunchControlOutgoing.faderPickup(value), "fader pickup \(value ? "on" : "off")")
        case "touch":
            guard let value = on(0) else { print("touch on|off"); break }
            send(LaunchControlOutgoing.touchEvents(value), "touch reports \(value ? "on" : "off")")
        case "mode":
            let mode: LaunchControlMode?
            switch rest.first?.lowercased() {
            case "mixer": mode = .dawMixer
            case "control": mode = .dawControl
            case "custom": mode = number(1, 1...16).map { .custom($0) }
            default: mode = nil
            }
            guard let mode else { print("mode mixer|control|custom N"); break }
            send(LaunchControlOutgoing.selectMode(mode), "mode \(rest.joined(separator: " "))")
        case "display":
            guard let target = rest.first.flatMap(parseLaunchControlTarget), let arrangementNumber = number(1, 1...4),
                  let arrangement = LaunchControlArrangement(rawValue: UInt8(arrangementNumber)) else {
                print("display T A [quiet]"); break
            }
            let quiet = rest.count > 2 && rest[2].lowercased() == "quiet"
            send(LaunchControlOutgoing.configureDisplay(target, arrangement, onChange: !quiet, onTouch: !quiet),
                 "display \(rest[0]) arrangement \(arrangementNumber)\(quiet ? " quiet" : "")")
        case "text":
            guard let target = rest.first.flatMap(parseLaunchControlTarget), let field = number(1) else { print("text T F TEXT"); break }
            let text = rest.dropFirst(2).joined(separator: " ")
            send(LaunchControlOutgoing.text(target, field: field, text), "text \(rest[0]) field \(field) \"\(text)\"")
        case "show":
            guard let target = rest.first.flatMap(parseLaunchControlTarget), let value = on(1) else { print("show T on|off"); break }
            send(LaunchControlOutgoing.showDisplay(target, value), "show \(rest[0]) \(value ? "on" : "off")")
        case "feature":
            guard let feature = number(0), let value = number(1) else { print("feature N V"); break }
            send(LaunchControlOutgoing.feature(UInt8(feature), UInt8(value)), "feature \(feature) = \(value)")
        case "query":
            guard let feature = number(0) else { print("query N"); break }
            send(LaunchControlOutgoing.queryFeature(UInt8(feature)), "query feature \(feature)")
        case "daw":
            guard let value = on(0) else { print("daw on|off"); break }
            send(LaunchControlOutgoing.dawMode(value), "DAW mode \(value ? "on" : "off")")
        case "hex":
            let bytes = rest.compactMap { UInt8($0, radix: 16) }
            guard bytes.count == rest.count, !bytes.isEmpty else { print("hex BYTES (in hexadecimal)"); break }
            send(bytes, "hex \(hex(bytes))")
        default:
            print("Unknown command. Type `help`.")
        }
        flushOutput()
        return true
    }

    func close() {
        send(LaunchControlOutgoing.dawMode(false), "DAW mode off")
        Thread.sleep(forTimeInterval: 0.1)
        connection?.close()
    }
}

/// A control from its short name: f1–f8, e11–e38, b11–b28, or a button's name.
func parseLaunchControlElement(_ text: String) -> LaunchControlElement? {
    let name = text.lowercased()
    let named: [String: LaunchControlElement] = [
        "soloarm": .soloArm, "muteselect": .muteSelect, "novation": .novation, "pageup": .pageUp,
        "pagedown": .pageDown, "trackleft": .trackLeft, "trackright": .trackRight, "record": .record,
        "play": .play, "shift": .shift,
    ]
    if let element = named[name] { return element }
    let digits = name.dropFirst().compactMap { $0.wholeNumberValue }
    let element: LaunchControlElement?
    switch (name.first, digits.count) {
    case ("f", 1): element = .fader(digits[0] - 1)
    case ("e", 2): element = .encoder(row: digits[0] - 1, column: digits[1] - 1)
    case ("b", 2): element = .button(row: digits[0] - 1, column: digits[1] - 1)
    default: element = nil
    }
    return element.flatMap { $0.isValid ? $0 : nil }
}

/// A display target from its name: stationary, overlay, or a fader or an encoder.
func parseLaunchControlTarget(_ text: String) -> LaunchControlDisplayTarget? {
    switch text.lowercased() {
    case "stationary": return .stationary
    case "overlay": return .overlay
    default:
        guard let element = parseLaunchControlElement(text), element.isContinuous else { return nil }
        return .control(element)
    }
}

/// A control's short name, as the commands take it.
func launchControlName(_ element: LaunchControlElement) -> String {
    switch element {
    case .fader(let index): return "f\(index + 1)"
    case .encoder(let row, let column): return "e\(row + 1)\(column + 1)"
    case .button(let row, let column): return "b\(row + 1)\(column + 1)"
    case .soloArm: return "soloarm"
    case .muteSelect: return "muteselect"
    case .novation: return "novation"
    case .pageUp: return "pageup"
    case .pageDown: return "pagedown"
    case .trackLeft: return "trackleft"
    case .trackRight: return "trackright"
    case .record: return "record"
    case .play: return "play"
    case .shift: return "shift"
    }
}

/// One line for an event.
func describeLaunchControl(_ event: LaunchControlEvent) -> String {
    switch event {
    case .moved(let element, let value): return "\(launchControlName(element)) = \(value)"
    case .turned(let element, let steps): return "\(launchControlName(element)) turned \(steps > 0 ? "+" : "")\(steps)"
    case .button(let element, let pressed): return "\(launchControlName(element)) \(pressed ? "pressed" : "released")"
    case .touch(let element, let touched): return "\(launchControlName(element)) \(touched ? "touched" : "let go")"
    case .mode(let mode):
        switch mode {
        case .dawMixer: return "mode DAW Mixer"
        case .dawControl: return "mode DAW Control"
        case .custom(let number): return "mode Custom \(number)"
        }
    case .feature(let number, let value): return "feature \(number) = \(value)"
    case .bitmapReady: return "bitmap ready"
    case .unknown(let bytes): return "unknown: \(hex(bytes))"
    }
}

func launchControl(_ arguments: ArraySlice<String>) -> Never {
    if arguments.first == "ports" { rotoPorts() }
    var inName = "LCXL3 1 DAW"
    var outName = "LCXL3 1 DAW"
    var raw = false
    var touch = true
    var rest = arguments
    func value(_ option: String) -> String {
        guard let text = rest.popFirst() else { fail("\(option) needs a value.\n\n\(lcxlUsage)") }
        return text
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--port": let name = value(argument); inName = name; outName = name
        case "--in": inName = value(argument)
        case "--out": outName = value(argument)
        case "--raw": raw = true
        case "--no-touch": touch = false
        case "-h", "--help": print(lcxlUsage); exit(0)
        default: fail("Unknown option \(argument).\n\n\(lcxlUsage)")
        }
    }
    let session = LaunchControlSession(inName: inName, outName: outName, raw: raw, touch: touch)
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
