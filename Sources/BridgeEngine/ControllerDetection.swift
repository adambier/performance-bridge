// Finding which hardware controllers are plugged in, from the names of the system's MIDI sources
// alone: nothing is sent to any device. The app uses it while setting up, to choose the hardware
// controller by itself when the one chosen isn't plugged in and exactly one other is (Adam,
// 2026-11-02).

import Foundation
#if canImport(LaunchControl)
import LaunchControl
#endif
#if canImport(MIDITransport)
import MIDITransport
#endif

/// A hardware controller Performance Bridge can drive, as found among the MIDI ports.
public enum DetectedController: Equatable, Sendable {
    /// Melbourne Instruments' Roto-Control.
    case roto
    /// A Novation Launch Control, by model.
    case launchControl(LaunchControlModel)

    /// The hardware controllers whose MIDI sources are among `sources`, in the order Settings
    /// lists them (Roto-Control, Launch Control XL 3, Launch Control 3). The Roto-Control is found
    /// as the engine finds it (`MIDIEndpointInfo.match` with `rotoPortName`), and a Launch Control
    /// by its DAW port (`LaunchControlModel.dawPort(among:)`).
    public static func found(among sources: [MIDIEndpointInfo], rotoPortName: String) -> [DetectedController] {
        var found: [DetectedController] = []
        if MIDIEndpointInfo.match(rotoPortName, in: sources) != nil { found.append(.roto) }
        let names = sources.map(\.name)
        for model in LaunchControlModel.allCases where model.dawPort(among: names) != nil {
            found.append(.launchControl(model))
        }
        return found
    }

    /// The hardware controller to switch to: the only one found, when `chosen` isn't found;
    /// otherwise `nil` (the chosen one is plugged in, none is, or several are and the user
    /// chooses).
    public static func switchTarget(chosen: DetectedController, found: [DetectedController]) -> DetectedController? {
        guard !found.contains(chosen), found.count == 1 else { return nil }
        return found[0]
    }
}
