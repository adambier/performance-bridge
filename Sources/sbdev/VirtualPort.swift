// sbdev vport: publishes a pair of virtual MIDI ports under a chosen name and prints whatever
// other programs send to them. Made to find out what an instrument program sends back to a
// controller it recognizes by its port name (the Arturia question of 2026-11-13: whether a
// standalone instrument reports its parameter values to a controller, and when).

import Foundation
import ArturiaControl
import MIDITransport

let vportUsage = """
    Usage: sbdev vport <port name>
        Publishes a virtual MIDI source and a virtual MIDI destination, both named <port name>
        (quote a name with spaces), and prints, with the time since starting, every message
        another program sends to the destination. A message from an Arturia instrument in the
        format it uses for the first KeyLab keyboards is also printed decoded ("value" or "text";
        docs/ARTURIA.md). Type a command and press Return:

    """ + vportCommandHelp

let vportCommandHelp = """
      cc <channel 1–16> <number 0–127> <value 0–127>   sends a control change from the source
      item <item> <value 0–127>                        sends the control change for one of the "KeyLab"
                                                       profile's items (e.g., item 1 100 is cc 1 74 100)
      raw <hex bytes>                                  sends those bytes from the source (e.g., raw B0 4A 40)
      mark <text>                                      prints a line with the time and the text
      help                                             this list
      quit                                             removes the ports and exits
    """

/// The bytes of a `cc` command's arguments, or `nil` if they are not a channel (1–16), a number
/// (0–127), and a value (0–127).
func vportControlChange(_ words: [String]) -> [UInt8]? {
    guard words.count == 3, let channel = Int(words[0]), let number = Int(words[1]), let value = Int(words[2]),
          (1...16).contains(channel), (0...127).contains(number), (0...127).contains(value) else { return nil }
    return [UInt8(0xB0 + channel - 1), UInt8(number), UInt8(value)]
}

/// The bytes of a `raw` command's arguments (hex, two digits each), or `nil` if any is not a byte.
func vportRawBytes(_ words: [String]) -> [UInt8]? {
    let bytes = words.compactMap { UInt8($0, radix: 16) }
    return bytes.count == words.count && !bytes.isEmpty ? bytes : nil
}

/// A decoded Arturia message in words, or `nil` for one this tool has no words for.
func vportDescribe(_ message: ArturiaInstrumentMessage) -> String? {
    switch message {
    case .value(let item, let value):
        let controller = ArturiaKeyLabProfile.controller(forItem: item).map { "CC \($0)" } ?? "no CC in the profile"
        return "value     item \(item) (\(controller)) = \(value)"
    case .text(let fields):
        return "text      " + fields.map { "\($0.tag): \"\($0.text)\"" }.joined(separator: "  ")
    case .other:
        return nil
    }
}

/// Joins the pieces of SysEx messages as they arrive on CoreMIDI's thread.
final class VportAssembler: @unchecked Sendable {
    private var assembler = ArturiaSysExAssembler()
    private let lock = NSLock()

    func feed(_ bytes: [UInt8]) -> [[UInt8]] {
        lock.lock()
        defer { lock.unlock() }
        return assembler.feed(bytes)
    }
}

/// The time since `start`, in seconds, as the first column of a line.
func vportStamp(since start: Date) -> String {
    String(format: "%9.3f  ", Date().timeIntervalSince(start))
}

func virtualPort(_ arguments: ArraySlice<String>) -> Never {
    if let first = arguments.first, first == "-h" || first == "--help" { print(vportUsage); exit(0) }
    guard let name = arguments.first, arguments.count == 1 else { fail(vportUsage) }
    let start = Date()
    let assembler = VportAssembler()
    let port: VirtualMIDIPort
    do {
        port = try VirtualMIDIPort(clientName: "sbdev vport", name: name) { bytes in
            print(vportStamp(since: start) + "received  " + hex(bytes))
            for message in assembler.feed(bytes) {
                if let parsed = ArturiaInstrumentMessage.parse(message), let words = vportDescribe(parsed) {
                    print(vportStamp(since: start) + words)
                }
            }
            flushOutput()
        }
    } catch {
        fail("\(error)")
    }
    print("Published a MIDI source and a MIDI destination named \"\(port.name)\".")
    print("Lines marked \"received\" are what another program sent to the destination.")
    print("Type help and press Return for the commands, or quit to stop.")
    flushOutput()
    var quit = false
    while let line = readLine() {
        let words = line.split(separator: " ").map(String.init)
        guard let command = words.first else { continue }
        let rest = Array(words.dropFirst())
        switch command {
        case "cc", "raw", "item":
            let parsed: [UInt8]?
            switch command {
            case "cc": parsed = vportControlChange(rest)
            case "raw": parsed = vportRawBytes(rest)
            default:
                parsed = rest.count == 2 ? Int(rest[0]).flatMap { item in
                    Int(rest[1]).flatMap { ArturiaKeyLabProfile.controlChange(item: item, value: $0) }
                } : nil
            }
            guard let bytes = parsed else {
                print("Not understood. Type help for the commands."); break
            }
            do {
                try port.send(bytes)
                print(vportStamp(since: start) + "sent      " + hex(bytes))
            } catch {
                print("Sending failed: \(error)")
            }
        case "mark":
            print(vportStamp(since: start) + "mark      " + rest.joined(separator: " "))
        case "help":
            print(vportCommandHelp)
        case "quit", "exit":
            quit = true
        default:
            print("Not understood. Type help for the commands.")
        }
        flushOutput()
        if quit { break }
    }
    if !quit, !standardInputIsTerminal() {
        // Standard input is not a terminal and has ended: keep listening until Ctrl-C.
        while true { Thread.sleep(forTimeInterval: 60) }
    }
    port.close()
    exit(0)
}
