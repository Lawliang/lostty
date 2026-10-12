#if os(macOS)
import Foundation
import Testing
@testable import Ghostty

struct PhoneAccessChecksTests {
    @Test func readsTailscaleStatus() {
        let json = #"{"BackendState":"Running","Self":{"DNSName":"laws-mbp.tail278d1f.ts.net.","TailscaleIPs":["fd7a:115c:a1e0::1","100.126.63.10"]}}"#
        #expect(PhoneAccessParse.tailscale(statusJSON: Data(json.utf8))
            == .init(running: true, name: "laws-mbp.tail278d1f.ts.net", ipv4: "100.126.63.10"))
        let out = #"{"BackendState":"NeedsLogin","Self":{"DNSName":"","TailscaleIPs":[]}}"#
        #expect(PhoneAccessParse.tailscale(statusJSON: Data(out.utf8)) == .init(running: false, name: nil, ipv4: nil))
        #expect(PhoneAccessParse.tailscale(statusJSON: Data("not json".utf8)) == nil)
    }

    @Test func readsWhetherRemoteLoginIsEnabled() {
        let on = "disabled services = {\n\t\t\"com.apple.foo\" => disabled\n\t\t\"com.openssh.sshd\" => enabled\n}"
        let off = "disabled services = {\n\t\t\"com.openssh.sshd\" => disabled\n}"
        #expect(PhoneAccessParse.sshdEnabled(printDisabled: on))
        #expect(!PhoneAccessParse.sshdEnabled(printDisabled: off))
        #expect(!PhoneAccessParse.sshdEnabled(printDisabled: ""))
    }

    @Test func readsTheLoginMethodsSSHOffers() {
        #expect(PhoneAccessParse.authMethods(sshOutput: "me@127.0.0.1: Permission denied (publickey).\r\n") == ["publickey"])
        #expect(PhoneAccessParse.authMethods(sshOutput: "me@127.0.0.1: Permission denied (publickey,password,keyboard-interactive).")
            == ["publickey", "password", "keyboard-interactive"])
        #expect(PhoneAccessParse.authMethods(sshOutput: "ssh: connect to host 127.0.0.1 port 22: Connection refused") == nil)
    }

    @Test func passwordStillOfferedIsNotLockedDown() {
        var status = Self.ready
        status.authMethods = ["publickey", "password"]
        #expect(!status.passwordsOff)
        status.authMethods = ["publickey", "keyboard-interactive"]
        #expect(!status.passwordsOff)
        #expect(!status.readyToPair(lockdownSkipped: false))
        #expect(status.readyToPair(lockdownSkipped: true))
    }

    @Test func readsTheFirewallsBlockAll() {
        #expect(PhoneAccessParse.blockAll(firewallOutput: "Firewall has block all state set to enabled."))
        #expect(!PhoneAccessParse.blockAll(firewallOutput: "Firewall has block all state set to disabled."))
        #expect(!PhoneAccessParse.blockAll(firewallOutput: ""))
    }

    static let ready = PhoneAccessStatus(
        tailscale: .init(running: true, name: "mac.ts.net", ipv4: "100.1.2.3"),
        tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
        lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true)

    @Test func everyRowMustBeDoneToPair() {
        #expect(Self.ready.readyToPair(lockdownSkipped: false))
        var s = Self.ready
        s.tailscale = .init(running: true, name: nil, ipv4: "100.1.2.3")
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.tmuxPath = nil
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.remoteLogin = false
        #expect(!s.readyToPair(lockdownSkipped: true))
        s = Self.ready; s.blockAllIncoming = true
        #expect(!s.readyToPair(lockdownSkipped: false))
        s = Self.ready; s.terminfoInstalled = false
        #expect(!s.readyToPair(lockdownSkipped: false))
    }

    @Test func installsTerminfoAndNoticesWhenItMatches() throws {
        let root = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-ti-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: root) }
        let bundle = root.appendingPathComponent("bundle")
        let home = root.appendingPathComponent("home/.terminfo")
        for entry in PhoneAccessTerminfo.entries {
            let file = bundle.appendingPathComponent(entry)
            try FileManager.default.createDirectory(at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
            try Data(entry.utf8).write(to: file)
        }
        #expect(!PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try PhoneAccessTerminfo.install(bundle: bundle, home: home)
        #expect(PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try Data("older".utf8).write(to: home.appendingPathComponent(PhoneAccessTerminfo.entries[0]))
        #expect(!PhoneAccessTerminfo.installed(bundle: bundle, home: home))
        try PhoneAccessTerminfo.install(bundle: bundle, home: home)
        #expect(PhoneAccessTerminfo.installed(bundle: bundle, home: home))
    }

    @Test func commandsReturnOutputAndGiveUpOnHangs() {
        let echo = Command.run("/bin/sh", ["-c", "echo out; echo err >&2; exit 3"])
        #expect(echo?.status == 3)
        #expect(echo?.output.contains("out") == true)
        #expect(echo?.output.contains("err") == true)
        let start = Date()
        #expect(Command.run("/bin/sleep", ["10"], timeout: 0.5) == nil)
        #expect(Date().timeIntervalSince(start) < 3)
        #expect(Command.run("/nonexistent/tool", []) == nil)
    }
}
#endif
