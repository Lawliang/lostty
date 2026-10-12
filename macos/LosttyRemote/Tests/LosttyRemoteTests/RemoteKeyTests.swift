import Crypto
import Foundation
import NIOCore
import NIOEmbedded
import NIOSSH
import Testing
@testable import LosttyRemote

struct RemoteKeyTests {
    @Test func publicKeyLineIsAnAuthorizedKeysLine() {
        let key = RemoteKey(software: P256.Signing.PrivateKey())
        let parts = key.publicKeyLine.split(separator: " ")
        #expect(parts.count == 3)
        #expect(parts[0] == "ecdsa-sha2-nistp256")
        #expect(parts[2] == "lostty-mobile")
        #expect((try? NIOSSHPublicKey(openSSHPublicKey: "\(parts[0]) \(parts[1])")) != nil)
    }

    @Test func softwareKeyIsCreatedOnceAndKept() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-swkey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        let first = try RemoteKey.software(storedAt: file)
        let again = try RemoteKey.software(storedAt: file)
        #expect(first.publicKeyLine == again.publicKeyLine)
        let perms = try FileManager.default.attributesOfItem(atPath: file.path)[.posixPermissions] as? Int
        #expect(perms == 0o600)
    }

    @Test func aCorruptSoftwareKeyFileIsNotReplaced() throws {
        let file = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-swkey-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: file) }
        try Data("junk".utf8).write(to: file)
        #expect(throws: (any Error).self) { try RemoteKey.software(storedAt: file) }
        #expect(try Data(contentsOf: file) == Data("junk".utf8))
    }
}

struct PinnedHostKeysTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("lostty-pins-\(UUID().uuidString)")

    func validate(_ pins: PinnedHostKeys, _ key: NIOSSHPublicKey) -> Result<Void, Error> {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: Void.self)
        pins.validateHostKey(hostKey: key, validationCompletePromise: promise)
        var result: Result<Void, Error>?
        promise.futureResult.whenComplete { result = $0 }
        loop.run()
        return result!
    }

    @Test func firstConnectPinsThenAcceptsTheSameKey() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let pins = PinnedHostKeys(host: "localhost", port: 22, knownHosts: KnownHosts(fileURL: file))
        let key = NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey
        #expect((try? validate(pins, key).get()) != nil)
        #expect((try? validate(pins, key).get()) != nil)
    }

    @Test func aChangedKeyIsAHardStop() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let pins = PinnedHostKeys(host: "localhost", port: 22, knownHosts: KnownHosts(fileURL: file))
        _ = validate(pins, NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
        let result = validate(pins, NIOSSHPrivateKey(p256Key: P256.Signing.PrivateKey()).publicKey)
        guard case .failure(let error) = result, case .hostKeyChanged? = error as? RemoteError else {
            Issue.record("expected hostKeyChanged, got \(result)")
            return
        }
    }
}

struct KeyAuthTests {
    func request(_ auth: KeyAuth, _ methods: NIOSSHAvailableUserAuthenticationMethods) -> Result<NIOSSHUserAuthenticationOffer?, Error> {
        let loop = EmbeddedEventLoop()
        let promise = loop.makePromise(of: NIOSSHUserAuthenticationOffer?.self)
        auth.nextAuthenticationType(availableMethods: methods, nextChallengePromise: promise)
        var result: Result<NIOSSHUserAuthenticationOffer?, Error>?
        promise.futureResult.whenComplete { result = $0 }
        loop.run()
        return result!
    }

    @Test func offersTheKeyOnceThenReportsItRejected() {
        let auth = KeyAuth(user: "me", key: RemoteKey(software: P256.Signing.PrivateKey()))
        guard case .success(let offer?) = request(auth, .publicKey) else {
            Issue.record("expected an offer")
            return
        }
        #expect(offer.username == "me")
        guard case .failure(let error) = request(auth, .publicKey) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error as? RemoteError == .keyRejected)
    }

    @Test func failsWhenPublicKeyAuthIsNotOffered() {
        let auth = KeyAuth(user: "me", key: RemoteKey(software: P256.Signing.PrivateKey()))
        guard case .failure(let error) = request(auth, .password) else {
            Issue.record("expected a failure")
            return
        }
        #expect(error as? RemoteError == .keyRejected)
    }
}
