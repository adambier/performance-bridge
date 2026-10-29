import XCTest
@testable import UDPTransport

final class UDPSocketTests: XCTestCase {
    #if canImport(Darwin) || canImport(Glibc)
    func testLoopbackDelivery() throws {
        let receiver = try UDPSocket(listeningOn: 0, localOnly: true)
        let sender = try UDPSocket(listeningOn: 0, localOnly: true)
        XCTAssertNotEqual(receiver.localPort, 0)

        let delivered = expectation(description: "datagram received")
        let payload: [UInt8] = Array("/sendall".utf8) + [0, 0, 0, 0]
        receiver.startReceiving { bytes, source in
            XCTAssertEqual(bytes, payload)
            XCTAssertEqual(source, "127.0.0.1")
            delivered.fulfill()
        }
        try sender.send(payload, to: "localhost", port: receiver.localPort)
        wait(for: [delivered], timeout: 5)
        receiver.stop()
    }

    func testBindingAPortInUseFails() throws {
        let first = try UDPSocket(listeningOn: 0, localOnly: true)
        XCTAssertThrowsError(try UDPSocket(listeningOn: first.localPort, localOnly: true)) { error in
            guard case .bindFailed(let port, _) = error as? UDPError else { return XCTFail("unexpected \(error)") }
            XCTAssertEqual(port, first.localPort)
        }
    }

    func testUnknownHostIsReported() throws {
        let socket = try UDPSocket(listeningOn: 0, localOnly: true)
        XCTAssertThrowsError(try socket.send([0], to: "no-such-host.invalid", port: 9)) {
            XCTAssertEqual($0 as? UDPError, .hostNotFound("no-such-host.invalid"))
        }
    }
    #endif
}
