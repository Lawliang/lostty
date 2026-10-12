import Foundation
import Testing
@testable import LosttyRemote

struct KnownHostsTests {
    let file = FileManager.default.temporaryDirectory
        .appendingPathComponent("lostty-known-hosts-\(UUID().uuidString)")

    @Test func firstKeyIsUnknownThenTrusted() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        #expect(hosts.verdict(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1") == .unknown)
        try hosts.trust(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1")
        #expect(hosts.verdict(host: "localhost", port: 22, key: "ecdsa-sha2-nistp256 AAAA1") == .trusted)
    }

    @Test func aDifferentKeyIsChangedAndThePinIsKept() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        try KnownHosts(fileURL: file).trust(host: "mac", port: 22, key: "ssh-ed25519 OLD")
        let reloaded = KnownHosts(fileURL: file)
        #expect(reloaded.verdict(host: "mac", port: 22, key: "ssh-ed25519 NEW") == .changed(pinned: "ssh-ed25519 OLD"))
        #expect(reloaded.verdict(host: "mac", port: 22, key: "ssh-ed25519 OLD") == .trusted)
    }

    @Test func pinsArePerHostAndPort() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "K1")
        #expect(hosts.verdict(host: "mac", port: 2222, key: "K1") == .unknown)
        #expect(hosts.verdict(host: "other", port: 22, key: "K1") == .unknown)
    }

    @Test func ipv6HostsDoNotCollide() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "fd7a:115c:a1e0::1", port: 22, key: "K1")
        // "fd7a:115c:a1e0::1:22" on port 22 must not read as the host above on another port.
        #expect(hosts.verdict(host: "fd7a:115c:a1e0::1:22", port: 22, key: "K1") == .unknown)
        #expect(hosts.verdict(host: "fd7a:115c:a1e0::1", port: 22, key: "K1") == .trusted)
        #expect(try String(contentsOf: file, encoding: .utf8).hasPrefix("[fd7a:115c:a1e0::1]:22 "))
    }

    @Test func trustingAgainDoesNotOverwriteAPin() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "K1")
        try hosts.trust(host: "mac", port: 22, key: "K2")
        #expect(hosts.verdict(host: "mac", port: 22, key: "K1") == .trusted)
    }

    @Test func forgettingAPinLetsTheNextKeyBePinnedAndKeepsOthers() throws {
        defer { try? FileManager.default.removeItem(at: file) }
        let hosts = KnownHosts(fileURL: file)
        try hosts.trust(host: "mac", port: 22, key: "OLD")
        try hosts.trust(host: "other", port: 22, key: "K2")
        try hosts.forget(host: "mac", port: 22)
        #expect(hosts.verdict(host: "mac", port: 22, key: "NEW") == .unknown)
        #expect(hosts.verdict(host: "other", port: 22, key: "K2") == .trusted)
        try hosts.trust(host: "mac", port: 22, key: "NEW")
        #expect(hosts.verdict(host: "mac", port: 22, key: "NEW") == .trusted)
        try hosts.forget(host: "nobody", port: 22)  // no pin: no error
    }
}
