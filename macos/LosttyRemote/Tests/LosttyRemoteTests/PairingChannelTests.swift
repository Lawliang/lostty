import Crypto
import Foundation
import Network
import Testing
@testable import LosttyRemote

final class Box<T>: @unchecked Sendable {
    private let lock = NSLock()
    private var stored: T
    init(_ value: T) { stored = value }
    var value: T {
        get { lock.lock(); defer { lock.unlock() }; return stored }
        set { lock.lock(); stored = newValue; lock.unlock() }
    }
}

/// Real TLS-PSK over loopback: proves the handshake, the framing, and that
/// only the right secret gets a request in.
@Suite(.serialized) struct PairingChannelTests {
    static let phoneKey = RemoteKey(software: P256.Signing.PrivateKey()).publicKeyLine
    let secret = Data(repeating: 7, count: 32)

    func listen(_ decide: @escaping PairingServer.Decide) async throws -> (PairingServer, NWEndpoint) {
        let server = try PairingServer(secret: secret, advertise: false, decide: decide)
        let port = try await server.start()
        return (server, .hostPort(host: "127.0.0.1", port: port))
    }

    @Test func theRightCodeGetsAnAnswer() async throws {
        let seen = Box<PairingRequest?>(nil)
        let (server, endpoint) = try await listen { request in
            seen.value = request
            return true
        }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "iPhone 13")
        let response = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .allowed)
        #expect(seen.value == request)
    }

    @Test func aWrongCodeNeverReachesThePromptAndDoesNotUseUpTheCode() async throws {
        let asked = Box(0)
        let (server, endpoint) = try await listen { _ in
            asked.value += 1
            return true
        }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "x")
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(request, to: endpoint, secret: Data(repeating: 8, count: 32), timeout: 5)
        }
        #expect(asked.value == 0)
        let response = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .allowed)
        #expect(asked.value == 1)
    }

    @Test func denyIsReported() async throws {
        let (server, endpoint) = try await listen { _ in false }
        defer { server.stop() }
        let response = try await PairingClient.send(
            PairingRequest(publicKey: Self.phoneKey, model: "x"), to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .denied)
    }

    @Test func aKeyThatIsNotAPhoneKeyIsDeniedWithoutAsking() async throws {
        let asked = Box(0)
        let (server, endpoint) = try await listen { _ in
            asked.value += 1
            return true
        }
        defer { server.stop() }
        let response = try await PairingClient.send(
            PairingRequest(publicKey: "ssh-rsa AAAAB3NzaC1yc2E", model: "x"), to: endpoint, secret: secret, timeout: 10)
        #expect(response.result == .denied)
        #expect(asked.value == 0)
    }

    @Test func theCodeWorksOnce() async throws {
        let (server, endpoint) = try await listen { _ in true }
        defer { server.stop() }
        let request = PairingRequest(publicKey: Self.phoneKey, model: "x")
        #expect(try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 10).result == .allowed)
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(request, to: endpoint, secret: secret, timeout: 5)
        }
    }

    @Test func aMacThatNeverAnswersTimesOut() async throws {
        let (server, endpoint) = try await listen { _ in
            try? await Task.sleep(for: .seconds(30))
            return true
        }
        defer { server.stop() }
        let start = Date()
        await #expect(throws: (any Error).self) {
            _ = try await PairingClient.send(
                PairingRequest(publicKey: Self.phoneKey, model: "x"), to: endpoint, secret: secret, timeout: 2)
        }
        #expect(Date().timeIntervalSince(start) < 10)
    }
}
