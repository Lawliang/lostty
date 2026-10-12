import Crypto
import Foundation
import NIOSSH
import Testing
@testable import LosttyRemote

struct RemoteHostSettingsTests {
    @Test func trimsWhatAPhoneKeyboardAdds() {
        let s = RemoteHostSettings(host: " my-mac.tail1234.ts.net ", port: 22, user: "lawliang ")
        #expect(s.problem == nil)
        #expect(s.remoteHost == RemoteHost(host: "my-mac.tail1234.ts.net", port: 22, user: "lawliang"))
    }

    @Test func incompleteSettingsSayWhatIsMissing() {
        #expect(RemoteHostSettings(host: "", port: 22, user: "me").problem == "Enter the Mac's address.")
        #expect(RemoteHostSettings(host: "mac", port: 22, user: " ").problem == "Enter your user name on the Mac.")
        #expect(RemoteHostSettings(host: "mac", port: 0, user: "me").problem == "The port must be between 1 and 65535.")
        #expect(RemoteHostSettings(host: "mac", port: 70000, user: "me").remoteHosts.isEmpty)
        #expect(RemoteHostSettings(host: "mac mini", port: 22, user: "me").problem == "The Mac's address can't contain spaces.")
    }

    @Test func theFallbackComesSecondAndOnlyWhenDifferent() {
        let s = RemoteHostSettings(host: "mac.ts.net", port: 22, user: "me", fallbackHost: "100.1.2.3")
        #expect(s.remoteHosts.map(\.host) == ["mac.ts.net", "100.1.2.3"])
        #expect(RemoteHostSettings(host: "mac", port: 22, user: "me", fallbackHost: " mac ").remoteHosts.count == 1)
        #expect(RemoteHostSettings(host: "mac", port: 22, user: "me", fallbackHost: "").remoteHosts.count == 1)
    }

    @Test func pairingFillsEverything() throws {
        let hostKey = String(String(openSSHPublicKey: NIOSSHPrivateKey(ed25519Key: Curve25519.Signing.PrivateKey()).publicKey)
            .split(separator: " ")[1])
        let payload = try PairingPayload(name: "mac.ts.net", ip: "100.64.1.3", user: "law", hostKey: hostKey,
                                         secret: Data(repeating: 1, count: 32))
        let date = Date(timeIntervalSince1970: 1_000)
        let s = RemoteHostSettings.paired(with: payload, at: date)
        #expect(s == RemoteHostSettings(host: "mac.ts.net", port: 22, user: "law", fallbackHost: "100.64.1.3", pairedAt: date))
        #expect(s.paired)
        #expect(!RemoteHostSettings(host: "mac", port: 22, user: "me").paired)
    }

    @Test func savesAndLoads() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        #expect(RemoteHostSettings.load(from: defaults) == RemoteHostSettings())
        let s = RemoteHostSettings(host: "mac.ts.net", port: 2222, user: "me", fallbackHost: "100.1.2.3",
                                   pairedAt: Date(timeIntervalSince1970: 5))
        s.save(to: defaults)
        #expect(RemoteHostSettings.load(from: defaults) == s)
    }

    @Test func loadsSettingsSavedBeforePairingExisted() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        defaults.set(#"{"host":"localhost","port":22,"user":"me","terminfoDir":"/t"}"#, forKey: RemoteHostSettings.defaultsKey)
        let s = RemoteHostSettings.load(from: defaults)
        #expect(s == RemoteHostSettings(host: "localhost", port: 22, user: "me"))
        #expect(!s.paired)
    }
}
