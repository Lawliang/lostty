import Foundation
import Testing
@testable import LosttyRemote

struct AuthorizedKeysTests {
    let key = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKEY1"
    let other = "ecdsa-sha2-nistp256 AAAAE2VjZHNhLXNoYTItbmlzdHAyNTYAAAAIbmlzdHAyNTYAAABBBKEY2"
    let theirs = """
    # my keys
    ssh-ed25519 AAAAC3NzaC1lZDI1NTE5AAAAIMINE me@laptop
    from="10.0.0.0/8",no-agent-forwarding ssh-rsa AAAAB3NzaRSA work\r
    """

    @Test func addsARestrictedTaggedLine() throws {
        let text = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: ""))
        #expect(text == "restrict,pty \(key) lostty-phone:a1\n")
        #expect(AuthorizedKeys.phones(in: text) == [.init(id: "a1", key: key)])
    }

    @Test func addingKeepsTheirLinesAndFixesAMissingNewline() throws {
        let text = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs))
        #expect(text == theirs + "\nrestrict,pty \(key) lostty-phone:a1\n")
    }

    @Test func aKeyAlreadyThereIsNotAddedTwice() throws {
        let once = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs))
        #expect(AuthorizedKeys.adding(key: key, id: "b2", to: once) == nil)
        #expect(AuthorizedKeys.adding(key: key, id: "b2", to: "\(key) added-by-hand\n") == nil)
    }

    @Test func removingOnePhoneLeavesEveryOtherByte() throws {
        let one = try #require(AuthorizedKeys.adding(key: key, id: "a1", to: theirs + "\n"))
        let two = try #require(AuthorizedKeys.adding(key: other, id: "b2", to: one))
        #expect(AuthorizedKeys.removing(id: "a1", from: two) == theirs + "\nrestrict,pty \(other) lostty-phone:b2\n")
        #expect(AuthorizedKeys.removingAll(from: two) == theirs + "\n")
        #expect(AuthorizedKeys.removing(id: "zz", from: two) == two)
    }

    @Test func onlyLinesLosttyWroteCountAsPhones() {
        let text = theirs + "\n" + "\(key) lostty-phone:hand\n" + "restrict,pty \(other) lostty-phone:\n"
        #expect(AuthorizedKeys.phones(in: text).isEmpty)
        #expect(AuthorizedKeys.removingAll(from: text) == text)
    }
}

struct AuthorizedKeysFileTests {
    let home = FileManager.default.temporaryDirectory.appendingPathComponent("lostty-home-\(UUID().uuidString)")

    func perms(_ url: URL) throws -> Int {
        try FileManager.default.attributesOfItem(atPath: url.path)[.posixPermissions] as! Int
    }

    @Test func createsSSHDirAndFileWithTightPermissions() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let file = AuthorizedKeysFile(url: home.appendingPathComponent(".ssh/authorized_keys"))
        #expect(try file.read() == "")
        try file.write("line\n")
        #expect(try file.read() == "line\n")
        #expect(try perms(home.appendingPathComponent(".ssh")) == 0o700)
        #expect(try perms(home.appendingPathComponent(".ssh/authorized_keys")) == 0o600)
    }

    @Test func aSymlinkStaysASymlink() throws {
        defer { try? FileManager.default.removeItem(at: home) }
        let dotfiles = home.appendingPathComponent("dotfiles")
        let ssh = home.appendingPathComponent(".ssh")
        try FileManager.default.createDirectory(at: dotfiles, withIntermediateDirectories: true)
        try FileManager.default.createDirectory(at: ssh, withIntermediateDirectories: true)
        let target = dotfiles.appendingPathComponent("authorized_keys")
        try "old\n".write(to: target, atomically: true, encoding: .utf8)
        let link = ssh.appendingPathComponent("authorized_keys")
        try FileManager.default.createSymbolicLink(at: link, withDestinationURL: target)

        try AuthorizedKeysFile(url: link).write("new\n")
        #expect(try FileManager.default.destinationOfSymbolicLink(atPath: link.path) == target.path)
        #expect(try String(contentsOf: target, encoding: .utf8) == "new\n")
    }
}
