import Foundation
import Testing
@testable import LosttyRemote

struct RemoteHostSettingsTests {
    @Test func trimsWhatAPhoneKeyboardAdds() {
        let s = RemoteHostSettings(host: " my-mac.tail1234.ts.net ", port: 22, user: "lawliang ", terminfoDir: RemoteHostSettings.defaultTerminfoDir)
        #expect(s.problem == nil)
        #expect(s.remoteHost == RemoteHost(host: "my-mac.tail1234.ts.net", port: 22, user: "lawliang", terminfoDir: RemoteHostSettings.defaultTerminfoDir))
    }

    @Test func incompleteSettingsSayWhatIsMissing() {
        #expect(RemoteHostSettings(host: "", port: 22, user: "me", terminfoDir: "/t").problem == "Enter the Mac's address.")
        #expect(RemoteHostSettings(host: "mac", port: 22, user: " ", terminfoDir: "/t").problem == "Enter your user name on the Mac.")
        #expect(RemoteHostSettings(host: "mac", port: 0, user: "me", terminfoDir: "/t").problem == "The port must be between 1 and 65535.")
        #expect(RemoteHostSettings(host: "mac", port: 70000, user: "me", terminfoDir: "/t").remoteHost == nil)
        #expect(RemoteHostSettings(host: "mac mini", port: 22, user: "me", terminfoDir: "/t").problem == "The Mac's address can't contain spaces.")
    }

    @Test func savesAndLoads() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        #expect(RemoteHostSettings.load(from: defaults) == RemoteHostSettings())
        let s = RemoteHostSettings(host: "100.101.102.103", port: 2222, user: "me", terminfoDir: "/t")
        s.save(to: defaults)
        #expect(RemoteHostSettings.load(from: defaults) == s)
    }

    @Test func loadsAJSONStringSoALaunchArgumentCanSetIt() {
        let defaults = UserDefaults(suiteName: "lostty-settings-\(UUID().uuidString)")!
        defaults.set(#"{"host":"localhost","port":22,"user":"me","terminfoDir":"/t"}"#, forKey: RemoteHostSettings.defaultsKey)
        #expect(RemoteHostSettings.load(from: defaults).host == "localhost")
    }

    @Test func defaultsAreEmptyWithTheStandardTerminfo() {
        let s = RemoteHostSettings()
        #expect(s.host.isEmpty && s.user.isEmpty && s.port == 22)
        #expect(s.terminfoDir == "/Applications/Lostty.app/Contents/Resources/terminfo")
    }
}
