// sbdev: developer tool for checking the libraries against TotalMix FX (and, later, the surfaces)
// without the app.
//
//   sbdev monitor [options]           print what TotalMix's Global OSC sends
//   sbdev send [options] <address> [value…]
//                                     send one message to TotalMix
//   sbdev curve <position | gain dB>  convert between fader position and gain
//   sbdev curve --table               print the curve in steps of 1 dB

import Foundation
import OSCCodec
import TotalMixOSC
import UDPTransport

let usage = """
    Usage:
      sbdev monitor [--host H] [--in-port P] [--out-port P] [--sendall | --sendstate | --sendsettings]
                    [--no-levels] [--no-status] [--raw]
          Listens on TotalMix's outgoing port and prints each message TotalMix sends.
          --sendall etc. ask TotalMix to send its current state once listening has started.
          --no-levels leaves out /level messages; --no-status leaves out /status messages
          (TotalMix sends one about every second); --raw prints the OSC arguments as received.
      sbdev send [--host H] [--in-port P] <address> [value…]
          Sends one message to TotalMix's incoming port. Numbers are sent as floats (what
          TotalMix expects); anything else as a string. With no value, 1.0 is sent (a trigger).
      sbdev curve <position 0…1 | gain, e.g. -6dB>
      sbdev curve --table

    Defaults: --host localhost --in-port 7001 --out-port 9001 (TotalMix's own defaults).
    In-port is the port TotalMix receives on; out-port the port TotalMix sends to.
    monitor numbers channels from 1, as TotalMix's window does; addresses count from 0
    (/input/2/mute is input 3).
    """

struct Options {
    var endpoint = TotalMixEndpoint.standard
    var request: OSCMessage?
    var showLevels = true
    var showStatus = true
    var raw = false
    var positional: [String] = []
}

func fail(_ message: String) -> Never {
    FileHandle.standardError.write(Data((message + "\n").utf8))
    exit(2)
}

func parseOptions(_ arguments: ArraySlice<String>) -> Options {
    var options = Options()
    var rest = arguments
    func port(_ text: String?) -> UInt16 {
        guard let text, let value = UInt16(text), value > 0 else { fail("A port must be a number from 1 to 65535.") }
        return value
    }
    while let argument = rest.popFirst() {
        switch argument {
        case "--host":
            guard let host = rest.popFirst() else { fail("--host needs a host name or address.") }
            options.endpoint.host = host
        case "--in-port": options.endpoint.incomingPort = port(rest.popFirst())
        case "--out-port": options.endpoint.outgoingPort = port(rest.popFirst())
        case "--sendall": options.request = TotalMixCommand.sendAll()
        case "--sendstate": options.request = TotalMixCommand.sendState()
        case "--sendsettings": options.request = TotalMixCommand.sendSettings()
        case "--no-levels": options.showLevels = false
        case "--no-status": options.showStatus = false
        case "--raw": options.raw = true
        case "-h", "--help": print(usage); exit(0)
        default:
            if argument.hasPrefix("--") && Double(argument) == nil { fail("Unknown option \(argument).\n\n\(usage)") }
            options.positional.append(argument)
        }
    }
    return options
}

func timestamp() -> String {
    let now = Date()
    let formatter = DateFormatter()
    formatter.dateFormat = "HH:mm:ss.SSS"
    return formatter.string(from: now)
}

func describe(_ argument: OSCArgument) -> String {
    switch argument {
    case .int(let value): return "i:\(value)"
    case .float(let value): return "f:\(value)"
    case .string(let value): return "s:\"\(value)\""
    case .blob(let value): return "b:\(value.count) bytes"
    case .bool(let value): return value ? "T" : "F"
    case .null: return "N"
    case .int64(let value): return "h:\(value)"
    case .double(let value): return "d:\(value)"
    }
}

func describe(_ event: TotalMixEvent) -> String {
    switch event {
    case .channel(let bus, let channel, let parameter, let value):
        var text = "\(bus.rawValue) \(channel + 1) \(parameter) = \(value)"
        if parameter == "faderlin", let position = value.number { text += "  (\(gainText(FaderCurve.gainDB(position: position))))" }
        return text
    case .mix(let bus, let channel, let output, let parameter, let value):
        var text = "mix \(bus.rawValue) \(channel + 1) → output \(output + 1) \(parameter) = \(value)"
        if parameter == "faderlin", let position = value.number { text += "  (\(gainText(FaderCurve.gainDB(position: position))))" }
        return text
    case .level(let bus, let channel, let peak):
        return "level \(bus.rawValue) \(channel + 1) = \(String(format: "%.1f", peak)) dB"
    case .snapshot(let number, let state):
        return "snapshot \(number) \(state)"
    case .other(let path, let value):
        return "\(path) = \(value)"
    }
}

/// Flushes standard output, so that monitor lines appear at once when piped to a file.
func flushOutput() {
    #if canImport(Darwin) || canImport(Glibc)
    fflush(stdout)
    #endif
}

func gainText(_ gain: Double?) -> String {
    guard let gain else { return "off" }
    // Rounded first, so that a gain just below 0 dB prints as +0.00 rather than -0.00.
    let rounded = (gain * 100).rounded() / 100
    return String(format: "%+.2f dB", rounded == 0 ? 0 : rounded)
}

// MARK: - Commands

func monitor(_ options: Options) -> Never {
    let socket: UDPSocket
    do {
        socket = try UDPSocket(listeningOn: options.endpoint.outgoingPort)
    } catch {
        fail("\(error)")
    }
    print("Listening on UDP port \(socket.localPort) for TotalMix at \(options.endpoint.host). Ctrl-C to stop.")
    socket.startReceiving { bytes, sender in
        let packet: OSCPacket
        do {
            packet = try OSCPacket(decoding: bytes)
        } catch {
            print("\(timestamp())  [\(sender)] not OSC (\(error)), \(bytes.count) bytes")
            return
        }
        for message in packet.messages {
            let event = TotalMixEvent(message)
            if !options.showLevels, case .level = event { continue }
            if !options.showStatus, message.address.hasPrefix("/status/") { continue }
            let text: String
            if options.raw || event == nil {
                text = message.address + " " + message.arguments.map(describe).joined(separator: " ")
            } else {
                text = describe(event!)
            }
            print("\(timestamp())  \(text)")
        }
        flushOutput()
    }
    if let request = options.request {
        do {
            try socket.send(request.encoded(), to: options.endpoint.host, port: options.endpoint.incomingPort)
            print("Sent \(request.address) to \(options.endpoint.host):\(options.endpoint.incomingPort).")
        } catch {
            print("Could not send \(request.address): \(error)")
        }
    }
    flushOutput()
    while true { Thread.sleep(forTimeInterval: 60) }
}

func send(_ options: Options) -> Never {
    guard let address = options.positional.first, address.hasPrefix("/") else {
        fail("send needs an address starting with \"/\".\n\n\(usage)")
    }
    let values = options.positional.dropFirst()
    let arguments: [OSCArgument] = values.isEmpty
        ? [.float(1)]
        : values.map { text in Float(text).map(OSCArgument.float) ?? .string(text) }
    let message = OSCMessage(address, arguments)
    do {
        let socket = try UDPSocket(listeningOn: 0)
        try socket.send(message.encoded(), to: options.endpoint.host, port: options.endpoint.incomingPort)
    } catch {
        fail("\(error)")
    }
    print("Sent \(address) \(arguments.map(describe).joined(separator: " ")) to \(options.endpoint.host):\(options.endpoint.incomingPort).")
    exit(0)
}

func curve(_ arguments: [String]) -> Never {
    if arguments == ["--table"] {
        print(" gain dB   position   step")
        for gain in stride(from: 6, through: -65, by: -1) {
            let position = FaderCurve.position(gainDB: Double(gain))
            print(String(format: "%+7d   %.6f   %6.1f", gain, position, position * FaderCurve.steps))
        }
        exit(0)
    }
    guard arguments.count == 1 else { fail(usage) }
    let text = arguments[0]
    if text.lowercased().hasSuffix("db"), let gain = Double(text.dropLast(2)) {
        let position = FaderCurve.position(gainDB: gain)
        print(String(format: "%+.2f dB → position %.6f (step %.1f)", gain, position, position * FaderCurve.steps))
    } else if let position = Double(text) {
        print(String(format: "position %.6f (step %.1f) → ", position, position * FaderCurve.steps) + gainText(FaderCurve.gainDB(position: position)))
    } else {
        fail("curve needs a position from 0 to 1, or a gain such as -6dB.")
    }
    exit(0)
}

// MARK: - Main

let arguments = CommandLine.arguments.dropFirst()
guard let command = arguments.first else { print(usage); exit(0) }
switch command {
case "monitor": monitor(parseOptions(arguments.dropFirst()))
case "send": send(parseOptions(arguments.dropFirst()))
case "curve": curve(Array(arguments.dropFirst()))
case "-h", "--help", "help": print(usage); exit(0)
default: fail("Unknown command \(command).\n\n\(usage)")
}
