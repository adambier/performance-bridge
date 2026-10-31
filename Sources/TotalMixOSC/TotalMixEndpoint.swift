import Foundation

/// Where TotalMix's Global OSC service is, as set in TotalMix's preferences.
///
/// The ports are named from TotalMix's side, as its preferences name them: TotalMix receives on its
/// incoming port (Performance Bridge sends there) and sends to its outgoing port (Performance Bridge listens
/// there).
public struct TotalMixEndpoint: Equatable, Sendable, Codable {
    /// The computer running TotalMix.
    public var host: String
    /// The port TotalMix receives on.
    public var incomingPort: UInt16
    /// The port TotalMix sends to.
    public var outgoingPort: UInt16

    /// Makes an endpoint; the defaults are TotalMix's on this computer.
    public init(host: String = "localhost", incomingPort: UInt16 = 7001, outgoingPort: UInt16 = 9001) {
        self.host = host
        self.incomingPort = incomingPort
        self.outgoingPort = outgoingPort
    }

    /// TotalMix on this computer with its default ports, 7001 and 9001.
    public static let standard = TotalMixEndpoint()
}
