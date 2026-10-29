import Foundation
#if canImport(OSCCodec)
import OSCCodec
#endif

/// Messages to send to TotalMix's Global OSC.
///
/// Channel numbers count from 0; snapshot, layout, and group numbers from 1 (as in RME's protocol
/// document). For a stereo channel, address the left channel; parameters marked L/R in
/// docs/TOTALMIX-OSC.md address the right channel as the left channel + 1.
public enum TotalMixCommand {
    /// Sets a channel setting, e.g. `set(.input, 2, "mute", 1)` or `set(.output, 0, "eq/band1gain", 3)`.
    public static func set(_ bus: TotalMixBus, _ channel: Int, _ parameter: String, _ value: Float) -> OSCMessage {
        OSCMessage("/\(bus.settingsName)/\(channel)/\(parameter)", [.float(value)])
    }

    /// Sets a mixer-node parameter: the send from an input or playback channel to an output
    /// (a submix). `parameter` is `fader` (dB), `faderlin` (position 0…1), `balpan`, `solo`, or
    /// `groupflags`.
    public static func setMix(from bus: TotalMixBus, _ channel: Int, to output: Int, _ parameter: String, _ value: Float) -> OSCMessage? {
        guard let source = bus.mixName else { return nil }
        return OSCMessage("/mix/\(source)/\(channel)/\(output)/\(parameter)", [.float(value)])
    }

    /// Sets a parameter outside the channels, e.g. `global("controlroom/dim", 1)` or
    /// `global("reverb/enable", 0)`.
    public static func global(_ path: String, _ value: Float) -> OSCMessage {
        OSCMessage("/\(path)", [.float(value)])
    }

    /// Asks TotalMix to send every parameter (`/sendall`). With `activeNodesOnly`, mixer nodes are
    /// sent only where the fader is above −65 dB.
    public static func sendAll(activeNodesOnly: Bool = false) -> OSCMessage {
        OSCMessage("/sendall", [.float(activeNodesOnly ? 2 : 1)])
    }

    /// Asks TotalMix to send the control parameters and FX settings (`/sendsettings`).
    public static func sendSettings() -> OSCMessage { trigger("/sendsettings") }

    /// Asks TotalMix to send every status message, DURec's included (`/sendstate`).
    public static func sendState() -> OSCMessage { trigger("/sendstate") }

    /// Asks TotalMix to send every setting of one channel (`/sendchan/<bus>/<channel>`).
    public static func sendChannel(_ bus: TotalMixBus, _ channel: Int) -> OSCMessage {
        trigger("/sendchan/\(bus.settingsName)/\(channel)")
    }

    /// Asks TotalMix to send all mixer nodes (`/sendmix`), or only those with the fader above −65 dB.
    public static func sendMix(activeNodesOnly: Bool = false) -> OSCMessage {
        OSCMessage("/sendmix", [.float(activeNodesOnly ? 2 : 1)])
    }

    /// Asks TotalMix to send the mixer nodes of one submix (`/sendsubmix/<output>`).
    public static func sendSubmix(_ output: Int, activeNodesOnly: Bool = false) -> OSCMessage {
        OSCMessage("/sendsubmix/\(output)", [.float(activeNodesOnly ? 2 : 1)])
    }

    /// Loads a snapshot (numbered from 1).
    public static func loadSnapshot(_ number: Int) -> OSCMessage { trigger("/snapshot/load/\(number)") }

    /// A trigger message: TotalMix ignores values below 0.5, so 1.0 is sent.
    public static func trigger(_ address: String) -> OSCMessage {
        OSCMessage(address, [.float(1)])
    }
}
