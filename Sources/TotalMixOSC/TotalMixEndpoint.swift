import Foundation

/// Where TotalMix FX's Global OSC service is, as set in TotalMix FX's preferences.
///
/// The ports are named from TotalMix FX's side, as its preferences name them: TotalMix FX receives on its
/// incoming port (Performance Bridge sends there) and sends to its outgoing port (Performance Bridge listens
/// there).
public struct TotalMixEndpoint: Equatable, Sendable, Codable {
    /// The computer running TotalMix FX.
    public var host: String
    /// The port TotalMix FX receives on.
    public var incomingPort: UInt16
    /// The port TotalMix FX sends to.
    public var outgoingPort: UInt16

    /// Makes an endpoint; the defaults are this computer with ports 7001 and 9001, which RME's
    /// manual gives as typical values (docs/TOTALMIX-OSC.md, section 1). They are not known to be
    /// TotalMix FX's own defaults.
    public init(host: String = "localhost", incomingPort: UInt16 = 7001, outgoingPort: UInt16 = 9001) {
        self.host = host
        self.incomingPort = incomingPort
        self.outgoingPort = outgoingPort
    }

    /// TotalMix FX on this computer with ports 7001 and 9001, Performance Bridge's defaults.
    public static let standard = TotalMixEndpoint()
}
