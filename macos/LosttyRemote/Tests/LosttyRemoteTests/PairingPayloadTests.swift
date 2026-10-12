import Crypto
import Foundation
import NIOSSH
import Testing
@testable import LosttyRemote

struct PairingPayloadTests {
    static let hostKey: String = {
        let line = String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
        return String(line.split(separator: " ")[1])
    }()

    /// Bytes whose base64 contains "+" and "/", which a URL must not mangle.
    static let secret = Data((0..<32).map { $0 % 2 == 0 ? 0xFB : 0xFF })

    func payload(
        name: String = "laws-macbook-pro.tail278d1f.ts.net", ip: String = "100.126.63.10",
        user: String = "lawliang", hostKey: String = hostKey, secret: Data = secret
    ) throws -> PairingPayload {
        try PairingPayload(name: name, ip: ip, user: user, hostKey: hostKey, secret: secret)
    }

    @Test func roundTripsThroughItsURL() throws {
        let p = try payload()
        #expect(p.url.scheme == "lostty")
        #expect(p.url.host == "pair")
        #expect(p.url.absoluteString.contains("v=1"))
        #expect(try PairingPayload(url: p.url) == p)
        #expect(try PairingPayload(url: URL(string: p.url.absoluteString)!) == p)
    }

    @Test func hostKeyLineIsWhatKnownHostsStores() throws {
        #expect(try payload().hostKeyLine == "ssh-ed25519 \(Self.hostKey)")
    }

    @Test func refusesBadFields() {
        let ecdsa = String(String(openSSHPublicKey: NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
            .split(separator: " ")[1])
        #expect(throws: PairingError.invalidLink) { try payload(name: "") }
        #expect(throws: PairingError.invalidLink) { try payload(name: "my mac") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "not-an-ip") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "fd7a:115c:a1e0::1") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "8.8.8.8") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "100.128.0.1") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "100.63.255.255") }
        #expect(throws: PairingError.invalidLink) { try payload(ip: "100.64.0.1%en0") }
        #expect(throws: PairingError.invalidLink) { try payload(user: "") }
        #expect(throws: PairingError.invalidLink) { try payload(user: "law liang") }
        #expect(throws: PairingError.invalidLink) { try payload(hostKey: ecdsa) }
        #expect(throws: PairingError.invalidLink) { try payload(hostKey: "garbage") }
        #expect(throws: PairingError.invalidLink) { try payload(secret: Data(repeating: 1, count: 31)) }
    }

    @Test func refusesOtherLinks() throws {
        let good = try payload().url.absoluteString
        for bad in [
            good.replacingOccurrences(of: "lostty://", with: "https://"),
            good.replacingOccurrences(of: "://pair", with: "://other"),
            good.replacingOccurrences(of: "v=1", with: "v=2"),
            "lostty://pair?v=1",
            "lostty://pair",
        ] {
            #expect(throws: PairingError.invalidLink, "\(bad)") { try PairingPayload(url: URL(string: bad)!) }
        }
    }

    @Test func newSecretsAre32RandomBytes() {
        let a = PairingPayload.newSecret()
        #expect(a.count == 32)
        #expect(a != PairingPayload.newSecret())
    }

    @Test func modelNames() {
        #expect(DeviceModel.name(forIdentifier: "iPhone14,5") == "iPhone 13")
        #expect(DeviceModel.name(forIdentifier: "iPhone17,1") == "iPhone 16 Pro")
        #expect(DeviceModel.name(forIdentifier: "iPhone99,9") == "iPhone")
        #expect(DeviceModel.name(forIdentifier: "") == "iPhone")
    }
}
