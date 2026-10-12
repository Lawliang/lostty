#if os(macOS)
import Foundation
import LosttyRemote
import Testing
@testable import Ghostty

struct PhoneAccessRowsTests {
    let ready = PhoneAccessStatus(
        tailscale: .init(running: true, name: "mac.ts.net", ipv4: "100.1.2.3"),
        tmuxPath: "/opt/homebrew/bin/tmux", remoteLogin: true, authMethods: ["publickey"],
        lockdownFileExists: true, blockAllIncoming: false, terminfoInstalled: true)

    func row(_ kind: PhoneAccessRow.Kind, _ status: PhoneAccessStatus, skipped: Bool = false) -> PhoneAccessRow {
        PhoneAccessRow.rows(for: status, lockdownSkipped: skipped).first { $0.id == kind }!
    }

    @Test func allDoneIsAllOK() {
        let rows = PhoneAccessRow.rows(for: ready, lockdownSkipped: false)
        #expect(rows.map(\.id) == [.tailscale, .tmux, .remoteLogin, .passwords, .firewall, .terminfo])
        #expect(rows.allSatisfy { $0.state == .ok })
    }

    @Test func tailscaleMissingOrSignedOut() {
        var s = ready
        s.tailscale = nil
        #expect(row(.tailscale, s).fixes == [.installTailscale])
        s.tailscale = .init(running: false, name: nil, ipv4: nil)
        #expect(row(.tailscale, s).fixes == [.openTailscale])
        #expect(row(.tailscale, s).state == .missing)
    }

    @Test func passwordsOnOffersSetUpOrSkip() {
        var s = ready
        s.authMethods = ["publickey", "password"]
        s.lockdownFileExists = false
        #expect(row(.passwords, s).state == .missing)
        #expect(row(.passwords, s).fixes == [.lockPasswords, .skipLockdown])
        let skipped = row(.passwords, s, skipped: true)
        #expect(skipped.state == .warning)
        #expect(skipped.detail == "Without this, anyone who can reach this Mac can try your password over SSH, on any network, for every account on this Mac. If you SSH into this Mac with a password from elsewhere, that keeps working.")
        #expect(skipped.fixes == [.lockPasswords])
    }

    @Test func lockdownFileButPasswordsStillOn() {
        var s = ready
        s.authMethods = ["publickey", "password"]
        let r = row(.passwords, s)
        #expect(r.state == .missing)
        #expect(r.fixes == [.skipLockdown])
        #expect(r.detail.contains("/etc/ssh/sshd_config"))
        let skipped = row(.passwords, s, skipped: true)
        #expect(skipped.state == .warning)
        #expect(skipped.fixes.isEmpty)
        #expect(skipped.detail == r.detail)
        #expect(s.readyToPair(lockdownSkipped: true))
        #expect(!s.readyToPair(lockdownSkipped: false))
    }

    @Test func remoteLoginOffNeedsTheAdminStep() {
        var s = ready
        s.remoteLogin = false
        s.authMethods = nil
        #expect(row(.remoteLogin, s).fixes == [.adminSetup])
        #expect(row(.passwords, s).state == .missing)
        #expect(row(.passwords, s).fixes.isEmpty)
    }

    @Test func otherRowsHaveTheirFixes() {
        var s = ready
        s.tmuxPath = nil
        s.blockAllIncoming = true
        s.terminfoInstalled = false
        #expect(row(.tmux, s).fixes == [.copyBrew])
        #expect(row(.firewall, s).fixes == [.openFirewall])
        #expect(row(.terminfo, s).fixes == [.installTerminfo])
    }
}

struct PairingDecisionTests {
    @Test func finishedMessageKeepsWriteFailure() {
        #expect(PairingDecision.finishedMessage(.writeFailed, allowed: false) == nil)
        #expect(PairingDecision.finishedMessage(.denied, allowed: false) == "Pairing was declined.")
        #expect(PairingDecision.finishedMessage(.allowed, allowed: true) == "Paired. Finish on your phone.")
        #expect(PairingDecision.finishedMessage(nil, allowed: false) == "Pairing didn't finish.")
    }
}

struct PhoneAccessNamesTests {
    @Test func storesNamesAndMergesThemWithTheKeysFile() {
        let names = PhoneAccessNames(defaults: UserDefaults(suiteName: "lostty-phones-\(UUID().uuidString)")!)
        let date = Date(timeIntervalSince1970: 100)
        names.set("a1", .init(name: "iPhone 13", paired: date))
        let keys = """
        ssh-ed25519 AAAA mine
        restrict,pty ecdsa-sha2-nistp256 AAAAKEY1 lostty-phone:a1
        restrict,pty ecdsa-sha2-nistp256 AAAAKEY2 lostty-phone:b2

        """
        #expect(PhoneAccessNames.phones(keysText: keys, names: names.entries()) == [
            PairedPhone(id: "a1", name: "iPhone 13", paired: date),
            PairedPhone(id: "b2", name: "iPhone", paired: nil),
        ])
        names.set("a1", nil)
        #expect(names.entries().isEmpty)
    }

    @Test func readsTheMacsHostKey() {
        #expect(PhoneAccessHostKey.base64(fromPub: "ssh-ed25519 AAAAC3NzaKEY root@mac\n") == "AAAAC3NzaKEY")
        #expect(PhoneAccessHostKey.base64(fromPub: "ecdsa-sha2-nistp256 AAAA root@mac") == nil)
        #expect(PhoneAccessHostKey.base64(fromPub: "") == nil)
    }
}
#endif
