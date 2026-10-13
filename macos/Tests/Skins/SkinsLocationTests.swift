#if os(macOS)
import Foundation
import Testing
@testable import Lostty

struct SkinsLocationTests {
    private func makeHome() throws -> URL {
        let home = FileManager.default.temporaryDirectory.appendingPathComponent("skins-home-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: home, withIntermediateDirectories: true)
        return home
    }

    @Test func newUserGetsLosttysFolder() throws {
        let home = try makeHome()
        let dir = SkinsLocation.configDir(home: home)
        #expect(dir.path == home.appendingPathComponent(".config/lostty/skins").path)
        // Nothing is created until something is saved there.
        #expect(!FileManager.default.fileExists(atPath: dir.path))
    }

    @Test func copiesTheOldFolderOnce() throws {
        let home = try makeHome()
        let legacy = home.appendingPathComponent(".config/ghostty-skins")
        try FileManager.default.createDirectory(
            at: legacy.appendingPathComponent("state"), withIntermediateDirectories: true)
        try "[defaults]\n".write(to: legacy.appendingPathComponent("skins.toml"), atomically: true, encoding: .utf8)
        try "{}".write(to: legacy.appendingPathComponent("state/saved-colors.json"), atomically: true, encoding: .utf8)

        let dir = SkinsLocation.configDir(home: home)
        #expect(dir.path == home.appendingPathComponent(".config/lostty/skins").path)
        #expect(try String(contentsOf: dir.appendingPathComponent("skins.toml"), encoding: .utf8) == "[defaults]\n")
        #expect(FileManager.default.fileExists(atPath: dir.appendingPathComponent("state/saved-colors.json").path))
        // The old folder stays for older builds.
        #expect(FileManager.default.fileExists(atPath: legacy.appendingPathComponent("skins.toml").path))

        // Later launches leave the new folder alone.
        try "[skins.a]\n".write(to: dir.appendingPathComponent("skins.toml"), atomically: true, encoding: .utf8)
        #expect(SkinsLocation.configDir(home: home).path == dir.path)
        #expect(try String(contentsOf: dir.appendingPathComponent("skins.toml"), encoding: .utf8) == "[skins.a]\n")
    }
}
#endif
